import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const String _assetId =
    'package:dart_durable_file_macos/dart_durable_file_macos.dart';

abstract final class MacosDurableFileLimits {
  static const int maximumPathUtf8Bytes = 4096;
  static const int maximumLeafUtf8Bytes = 255;
  static const int maximumPayloadBytes = 16 * 1024 * 1024;
}

enum MacosDurableFileFailure {
  invalidArgument(1),
  unsupported(2),
  notFound(3),
  permissionDenied(4),
  unsafeType(5),
  hardLink(6),
  wrongOwner(7),
  alreadyExists(8),
  busy(9),
  tooLarge(10),
  readFailed(11),
  writeFailed(12),
  fileSyncFailed(13),
  renameFailed(14),
  unlinkFailed(15),
  directorySyncFailed(16),
  resourceLimit(17),
  invalidState(18),
  unknown(19);

  const MacosDurableFileFailure(this.wireValue);

  final int wireValue;

  static MacosDurableFileFailure fromWireValue(int value) {
    for (final MacosDurableFileFailure failure in values) {
      if (failure.wireValue == value) return failure;
    }
    return MacosDurableFileFailure.unknown;
  }
}

/// Fixed, path- and content-free native operation failure.
final class MacosDurableFileException implements Exception {
  const MacosDurableFileException(this.failure);

  final MacosDurableFileFailure failure;

  @override
  String toString() => 'Durable file operation failed: ${failure.name}';
}

final class MacosDurableFileInfo {
  const MacosDurableFileInfo._({
    required this.exists,
    required this.length,
    required this.permissionBits,
    required this.linkCount,
  });

  final bool exists;
  final int length;
  final int permissionBits;
  final int linkCount;

  @override
  String toString() => exists
      ? 'MacosDurableFileInfo(exists, bytes=$length, mode=$permissionBits, links=$linkCount)'
      : 'MacosDurableFileInfo(missing)';
}

/// Descriptor-relative durable file session rooted at one caller-selected path.
///
/// The native boundary creates missing path components with the selected mode,
/// rejects symlink traversal, and optionally narrows the final directory before
/// returning. No path is retained in public result or error types.
final class MacosDurableDirectorySession {
  MacosDurableDirectorySession._(this._handle) {
    _finalizer.attach(this, _handle, detach: this);
  }

  static final Finalizer<int> _finalizer = Finalizer<int>(_closeUnobserved);

  int _handle;

  static int get abiVersion => _abiVersion();

  static int get debugOpenSessionCount => _debugOpenSessionCount();

  static MacosDurableDirectorySession open(
    String absolutePath, {
    bool create = false,
    int directoryPermissionBits = 0x1c0,
    bool narrowDirectoryPermissions = true,
  }) {
    if (!Platform.isMacOS ||
        !_validAbsolutePath(absolutePath) ||
        directoryPermissionBits < 0 ||
        directoryPermissionBits > 0x1ff ||
        utf8Length(absolutePath) >
            MacosDurableFileLimits.maximumPathUtf8Bytes) {
      throw const MacosDurableFileException(
        MacosDurableFileFailure.invalidArgument,
      );
    }
    final Pointer<Utf8> path = absolutePath.toNativeUtf8();
    final Pointer<Int32> failure = calloc<Int32>();
    try {
      final int handle = _sessionOpen(
        path,
        create ? 1 : 0,
        directoryPermissionBits,
        narrowDirectoryPermissions ? 1 : 0,
        failure,
      );
      if (handle == 0) _throwFailure(failure.value);
      return MacosDurableDirectorySession._(handle);
    } finally {
      calloc
        ..free(path)
        ..free(failure);
    }
  }

  bool get isClosed => _handle == 0;

  void acquireExclusiveLock(String leafName) {
    _withLeaf(leafName, (Pointer<Utf8> leaf) {
      _check(_acquireLock(_requireHandle(), leaf));
    });
  }

  MacosDurableFileInfo inspect(String leafName) =>
      _withLeaf(leafName, (Pointer<Utf8> leaf) {
        final Pointer<_DdfFileInfoV1> info = calloc<_DdfFileInfoV1>();
        try {
          info.ref
            ..structSize = sizeOf<_DdfFileInfoV1>()
            ..version = 1;
          _check(_inspect(_requireHandle(), leaf, info));
          return MacosDurableFileInfo._(
            exists: info.ref.exists != 0,
            length: info.ref.length,
            permissionBits: info.ref.mode,
            linkCount: info.ref.linkCount,
          );
        } finally {
          calloc.free(info);
        }
      });

  Uint8List read(
    String leafName, {
    int maximumBytes = MacosDurableFileLimits.maximumPayloadBytes,
  }) {
    if (maximumBytes < 0 ||
        maximumBytes > MacosDurableFileLimits.maximumPayloadBytes) {
      throw const MacosDurableFileException(
        MacosDurableFileFailure.invalidArgument,
      );
    }
    final MacosDurableFileInfo info = inspect(leafName);
    if (!info.exists) {
      throw const MacosDurableFileException(MacosDurableFileFailure.notFound);
    }
    if (info.length > maximumBytes) {
      throw const MacosDurableFileException(MacosDurableFileFailure.tooLarge);
    }
    return _withLeaf(leafName, (Pointer<Utf8> leaf) {
      final int capacity = info.length == 0 ? 1 : info.length;
      final Pointer<Uint8> output = calloc<Uint8>(capacity);
      final Pointer<Uint64> outputLength = calloc<Uint64>();
      try {
        _check(
          _read(
            _requireHandle(),
            leaf,
            maximumBytes,
            output,
            capacity,
            outputLength,
          ),
        );
        if (outputLength.value > capacity) {
          throw const MacosDurableFileException(
            MacosDurableFileFailure.resourceLimit,
          );
        }
        return Uint8List.fromList(output.asTypedList(outputLength.value));
      } finally {
        calloc
          ..free(output)
          ..free(outputLength);
      }
    });
  }

  void writeExclusive(String leafName, List<int> bytes) {
    if (bytes.length > MacosDurableFileLimits.maximumPayloadBytes) {
      throw const MacosDurableFileException(MacosDurableFileFailure.tooLarge);
    }
    final Uint8List copy = Uint8List.fromList(bytes);
    _withLeaf(leafName, (Pointer<Utf8> leaf) {
      final Pointer<Uint8> input = calloc<Uint8>(
        copy.isEmpty ? 1 : copy.length,
      );
      try {
        input.asTypedList(copy.length).setAll(0, copy);
        _check(_writeExclusive(_requireHandle(), leaf, input, copy.length));
      } finally {
        calloc.free(input);
      }
    });
  }

  void rename(String sourceLeaf, String destinationLeaf) {
    _withTwoLeaves(sourceLeaf, destinationLeaf, (
      Pointer<Utf8> source,
      Pointer<Utf8> destination,
    ) {
      _check(_rename(_requireHandle(), source, destination));
    });
  }

  void unlink(String leafName, {bool missingOkay = false}) {
    _withLeaf(leafName, (Pointer<Utf8> leaf) {
      final int result = _unlink(_requireHandle(), leaf);
      if (missingOkay && result == MacosDurableFileFailure.notFound.wireValue) {
        return;
      }
      _check(result);
    });
  }

  void flushDirectory() => _check(_syncDirectory(_requireHandle()));

  void close() {
    final int handle = _handle;
    if (handle == 0) return;
    _handle = 0;
    _finalizer.detach(this);
    _check(_sessionClose(handle));
  }

  int _requireHandle() {
    if (_handle == 0) {
      throw const MacosDurableFileException(
        MacosDurableFileFailure.invalidState,
      );
    }
    return _handle;
  }

  static T _withLeaf<T>(String leafName, T Function(Pointer<Utf8>) callback) {
    if (!_validLeaf(leafName)) {
      throw const MacosDurableFileException(
        MacosDurableFileFailure.invalidArgument,
      );
    }
    final Pointer<Utf8> leaf = leafName.toNativeUtf8();
    try {
      return callback(leaf);
    } finally {
      calloc.free(leaf);
    }
  }

  static T _withTwoLeaves<T>(
    String first,
    String second,
    T Function(Pointer<Utf8>, Pointer<Utf8>) callback,
  ) => _withLeaf(
    first,
    (Pointer<Utf8> firstPointer) => _withLeaf(
      second,
      (Pointer<Utf8> secondPointer) => callback(firstPointer, secondPointer),
    ),
  );

  static bool _validAbsolutePath(String path) =>
      path.startsWith('/') &&
      path != '/' &&
      !path.contains('\u0000') &&
      !path.split('/').any((String part) => part == '..');

  static bool _validLeaf(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        utf8Length(value) > MacosDurableFileLimits.maximumLeafUtf8Bytes) {
      return false;
    }
    for (final int unit in value.codeUnits) {
      if (unit == 0x2f || unit < 0x20 || unit == 0x7f) {
        return false;
      }
    }
    return true;
  }

  static int utf8Length(String value) => utf8.encode(value).length;

  static void _check(int result) {
    if (result != 0) _throwFailure(result);
  }

  static Never _throwFailure(int wireValue) => throw MacosDurableFileException(
    MacosDurableFileFailure.fromWireValue(wireValue),
  );

  static void _closeUnobserved(int handle) {
    if (handle != 0) _sessionClose(handle);
  }
}

final class _DdfFileInfoV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint32()
  external int exists;

  @Uint32()
  external int mode;

  @Uint64()
  external int length;

  @Uint64()
  external int linkCount;

  @Uint32()
  external int ownerMatches;

  @Uint32()
  external int reserved;
}

@Native<Uint32 Function()>(symbol: 'ddf_abi_version', assetId: _assetId)
external int _abiVersion();

@Native<Uint64 Function()>(
  symbol: 'ddf_debug_open_session_count',
  assetId: _assetId,
)
external int _debugOpenSessionCount();

@Native<IntPtr Function(Pointer<Utf8>, Uint32, Uint32, Uint32, Pointer<Int32>)>(
  symbol: 'ddf_session_open',
  assetId: _assetId,
)
external int _sessionOpen(
  Pointer<Utf8> path,
  int create,
  int directoryPermissionBits,
  int narrowDirectoryPermissions,
  Pointer<Int32> failure,
);

@Native<Int32 Function(IntPtr)>(symbol: 'ddf_session_close', assetId: _assetId)
external int _sessionClose(int handle);

@Native<Int32 Function(IntPtr, Pointer<Utf8>)>(
  symbol: 'ddf_acquire_lock',
  assetId: _assetId,
)
external int _acquireLock(int handle, Pointer<Utf8> leaf);

@Native<Int32 Function(IntPtr, Pointer<Utf8>, Pointer<_DdfFileInfoV1>)>(
  symbol: 'ddf_inspect',
  assetId: _assetId,
)
external int _inspect(
  int handle,
  Pointer<Utf8> leaf,
  Pointer<_DdfFileInfoV1> info,
);

@Native<
  Int32 Function(
    IntPtr,
    Pointer<Utf8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint64>,
  )
>(symbol: 'ddf_read', assetId: _assetId)
external int _read(
  int handle,
  Pointer<Utf8> leaf,
  int maximumBytes,
  Pointer<Uint8> output,
  int capacity,
  Pointer<Uint64> outputLength,
);

@Native<Int32 Function(IntPtr, Pointer<Utf8>, Pointer<Uint8>, Uint64)>(
  symbol: 'ddf_write_exclusive',
  assetId: _assetId,
)
external int _writeExclusive(
  int handle,
  Pointer<Utf8> leaf,
  Pointer<Uint8> input,
  int length,
);

@Native<Int32 Function(IntPtr, Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'ddf_rename',
  assetId: _assetId,
)
external int _rename(
  int handle,
  Pointer<Utf8> source,
  Pointer<Utf8> destination,
);

@Native<Int32 Function(IntPtr, Pointer<Utf8>)>(
  symbol: 'ddf_unlink',
  assetId: _assetId,
)
external int _unlink(int handle, Pointer<Utf8> leaf);

@Native<Int32 Function(IntPtr)>(symbol: 'ddf_sync_directory', assetId: _assetId)
external int _syncDirectory(int handle);
