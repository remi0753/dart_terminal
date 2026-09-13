import 'dart:ffi';
import 'dart:io';

/// A content-free snapshot of resources owned by the current product process.
final class TerminalProcessResourceSnapshot {
  const TerminalProcessResourceSnapshot({
    required this.cpuTimeMicroseconds,
    required this.currentResidentBytes,
    required this.peakResidentBytes,
  });

  final int cpuTimeMicroseconds;
  final int currentResidentBytes;
  final int peakResidentBytes;
}

/// A fixed-window delta derived from two monotonic process snapshots.
final class TerminalProcessResourceWindow {
  TerminalProcessResourceWindow({
    required this.before,
    required this.after,
    required this.elapsedMicroseconds,
  }) : cpuMicroseconds = after.cpuTimeMicroseconds - before.cpuTimeMicroseconds,
       maximumResidentBytes =
           before.currentResidentBytes > after.currentResidentBytes
           ? before.currentResidentBytes
           : after.currentResidentBytes {
    if (elapsedMicroseconds <= 0) {
      throw ArgumentError.value(elapsedMicroseconds, 'elapsedMicroseconds');
    }
    if (cpuMicroseconds < 0) {
      throw StateError('process CPU time regressed');
    }
    if (before.currentResidentBytes <= 0 ||
        after.currentResidentBytes <= 0 ||
        before.peakResidentBytes <= 0 ||
        after.peakResidentBytes <= 0) {
      throw StateError('process resident memory is unavailable');
    }
  }

  final TerminalProcessResourceSnapshot before;
  final TerminalProcessResourceSnapshot after;
  final int elapsedMicroseconds;
  final int cpuMicroseconds;
  final int maximumResidentBytes;

  int get cpuBasisPoints => cpuMicroseconds * 10000 ~/ elapsedMicroseconds;
}

/// Samples current-process CPU time through POSIX `getrusage` and RSS through
/// Dart's public process information API. This intentionally does not retain a
/// process identifier, command, path, environment, or raw application data.
final class TerminalCurrentProcessResourceSampler {
  TerminalCurrentProcessResourceSampler() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('process resource sampling requires macOS');
    }
  }

  static final DynamicLibrary _process = DynamicLibrary.process();
  static final _GetResourceUsageDart _getResourceUsage = _process
      .lookupFunction<_GetResourceUsageNative, _GetResourceUsageDart>(
        'getrusage',
      );
  static final _MallocDart _malloc = _process
      .lookupFunction<_MallocNative, _MallocDart>('malloc');
  static final _FreeDart _free = _process
      .lookupFunction<_FreeNative, _FreeDart>('free');
  static final _GetDescriptorTableSizeDart _getDescriptorTableSize = _process
      .lookupFunction<
        _GetDescriptorTableSizeNative,
        _GetDescriptorTableSizeDart
      >('getdtablesize');
  static final _FileControlDart _fileControl = _process
      .lookupFunction<_FileControlNative, _FileControlDart>('fcntl');

  static const int maximumDescriptorScanCount = 65536;
  static const int _getDescriptorFlagsCommand = 1;

  TerminalProcessResourceSnapshot snapshot() {
    final Pointer<_DarwinResourceUsage> usage = _malloc(
      sizeOf<_DarwinResourceUsage>(),
    ).cast<_DarwinResourceUsage>();
    if (usage == nullptr) {
      throw StateError('process resource snapshot allocation failed');
    }
    try {
      if (_getResourceUsage(0, usage) != 0) {
        throw StateError('process resource snapshot failed');
      }
      final int userMicroseconds = _timevalMicroseconds(
        usage.ref.userSeconds,
        usage.ref.userMicroseconds,
      );
      final int systemMicroseconds = _timevalMicroseconds(
        usage.ref.systemSeconds,
        usage.ref.systemMicroseconds,
      );
      final int currentResidentBytes = ProcessInfo.currentRss;
      final int peakResidentBytes = ProcessInfo.maxRss;
      if (currentResidentBytes <= 0 || peakResidentBytes <= 0) {
        throw StateError('process resident memory is unavailable');
      }
      return TerminalProcessResourceSnapshot(
        cpuTimeMicroseconds: userMicroseconds + systemMicroseconds,
        currentResidentBytes: currentResidentBytes,
        peakResidentBytes: peakResidentBytes,
      );
    } finally {
      _free(usage.cast<Void>());
    }
  }

  /// Counts open current-process descriptors without retaining their identity.
  int openFileDescriptorCount() {
    final int descriptorTableSize = _getDescriptorTableSize();
    if (descriptorTableSize <= 0 ||
        descriptorTableSize > maximumDescriptorScanCount) {
      throw StateError('process descriptor table bound is unavailable');
    }
    var count = 0;
    for (var descriptor = 0; descriptor < descriptorTableSize; descriptor++) {
      if (_fileControl(descriptor, _getDescriptorFlagsCommand) >= 0) count++;
    }
    if (count <= 0) {
      throw StateError('process descriptor count is unavailable');
    }
    return count;
  }

  static int _timevalMicroseconds(int seconds, int microseconds) {
    if (seconds < 0 || microseconds < 0 || microseconds >= 1000000) {
      throw StateError('process CPU time is malformed');
    }
    return seconds * 1000000 + microseconds;
  }
}

final class _DarwinResourceUsage extends Struct {
  @Int64()
  external int userSeconds;

  @Int64()
  external int userMicroseconds;

  @Int64()
  external int systemSeconds;

  @Int64()
  external int systemMicroseconds;

  @Array(14)
  external Array<Int64> opaque;
}

typedef _GetResourceUsageNative = Int32 Function(
  Int32 who,
  Pointer<_DarwinResourceUsage> usage,
);
typedef _GetResourceUsageDart = int Function(
  int who,
  Pointer<_DarwinResourceUsage> usage,
);
typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _MallocDart = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> pointer);
typedef _FreeDart = void Function(Pointer<Void> pointer);
typedef _GetDescriptorTableSizeNative = Int32 Function();
typedef _GetDescriptorTableSizeDart = int Function();
typedef _FileControlNative = Int32 Function(Int32 descriptor, Int32 command);
typedef _FileControlDart = int Function(int descriptor, int command);
