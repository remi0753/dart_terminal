import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'api.dart';

const String _assetId = 'package:dart_pty_macos/dart_pty_macos.dart';
const int _abiVersion = 6;
const int _statusOk = 0;
const int _statusBackpressured = 4;
const int _eventStarted = 1;
const int _eventOutput = 2;
const int _eventExit = 3;
const int _eventError = 4;
const int _eventWriteEnqueued = 5;
const int _eventWriteDequeued = 6;
const int _eventWriteCompleted = 7;
const int _eventWriteError = 8;
const int _eventForceCloseDequeued = 9;
const int _eventSignalDelivery = 10;
const int _eventWaitpidResult = 11;
const int _eventExitPublished = 12;
const int _eventStateSnapshot = 13;
const int _eventTermiosSnapshot = 14;
const int _eventProcessExitReady = 15;
const int _eventExternalReapObserved = 16;

typedef _EventNative = Void Function(
  Uint64,
  Uint32,
  Uint64,
  Pointer<Uint8>,
  Size,
  Int64,
  Int64,
  Int32,
  Pointer<Void>,
);

final class _SessionConfig extends Struct {
  @Size()
  external int structSize;

  @Uint32()
  external int abiVersion;

  external Pointer<Utf8> executable;
  external Pointer<Pointer<Utf8>> arguments;

  @Size()
  external int argumentCount;

  external Pointer<Pointer<Utf8>> environment;

  @Size()
  external int environmentCount;

  external Pointer<Utf8> workingDirectory;

  @Uint16()
  external int initialRows;

  @Uint16()
  external int initialColumns;

  @Size()
  external int readHighWaterBytes;

  @Size()
  external int readLowWaterBytes;

  @Size()
  external int writeCapacityBytes;

  external Pointer<NativeFunction<_EventNative>> callback;
  external Pointer<Void> callbackContext;

  @Uint32()
  external int diagnosticsEnabled;

  @Size()
  external int readBatchBytes;

  @Uint32()
  external int readBatchesPerEventLoopTurn;
}

final class _NativeStats extends Struct {
  @Size()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int bytesRead;

  @Uint64()
  external int bytesWritten;

  @Uint64()
  external int readBatches;

  @Uint64()
  external int writeBackpressureRejections;

  @Uint64()
  external int maxReadInFlightBytes;

  @Uint64()
  external int maxWriteQueuedBytes;

  @Uint64()
  external int readPauseCount;

  @Int64()
  external int childPid;

  @Int32()
  external int hasExited;
}

final class _NativeProcessSnapshot extends Struct {
  @Size()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Int64()
  external int childPid;

  @Int64()
  external int childProcessGroup;

  @Int64()
  external int foregroundProcessGroup;

  @Int32()
  external int childProcessGroupError;

  @Int32()
  external int foregroundProcessGroupError;

  @Int32()
  external int hasExited;

  @Int32()
  external int terminalEchoEnabled;

  @Int32()
  external int terminalAttributesError;
}

@Native<Uint32 Function()>(symbol: 'dpty_abi_version', assetId: _assetId)
external int _nativeAbiVersion();

@Native<Int32 Function(Pointer<_SessionConfig>, Pointer<Uint64>)>(
  symbol: 'dpty_session_create',
  assetId: _assetId,
)
external int _sessionCreate(
  Pointer<_SessionConfig> config,
  Pointer<Uint64> output,
);

@Native<Int32 Function(Uint64)>(symbol: 'dpty_session_start', assetId: _assetId)
external int _sessionStart(int session);

@Native<Int32 Function(Uint64, Pointer<Uint8>, Size)>(
  symbol: 'dpty_session_write',
  assetId: _assetId,
)
external int _sessionWrite(int session, Pointer<Uint8> bytes, int length);

@Native<Int32 Function(Uint64, Pointer<Uint8>, Size, Pointer<Uint64>)>(
  symbol: 'dpty_session_write_tracked',
  assetId: _assetId,
)
external int _sessionWriteTracked(
  int session,
  Pointer<Uint8> bytes,
  int length,
  Pointer<Uint64> requestId,
);

@Native<Int32 Function(Uint64, Uint64, Size)>(
  symbol: 'dpty_session_ack_output',
  assetId: _assetId,
)
external int _sessionAckOutput(int session, int sequence, int length);

@Native<Int32 Function(Uint64, Uint16, Uint16)>(
  symbol: 'dpty_session_resize',
  assetId: _assetId,
)
external int _sessionResize(int session, int rows, int columns);

@Native<Int32 Function(Uint64, Uint32)>(
  symbol: 'dpty_session_send_signal',
  assetId: _assetId,
)
external int _sessionSendSignal(int session, int signal);

@Native<Int32 Function(Uint64, Uint32)>(
  symbol: 'dpty_session_close',
  assetId: _assetId,
)
external int _sessionClose(int session, int gracePeriodMillis);

@Native<Int32 Function(Uint64)>(
  symbol: 'dpty_session_force_close',
  assetId: _assetId,
)
external int _sessionForceClose(int session);

@Native<Int32 Function(Uint64, Pointer<_NativeStats>)>(
  symbol: 'dpty_session_get_stats',
  assetId: _assetId,
)
external int _sessionGetStats(int session, Pointer<_NativeStats> stats);

@Native<Int32 Function(Uint64, Pointer<_NativeProcessSnapshot>)>(
  symbol: 'dpty_session_get_process_snapshot',
  assetId: _assetId,
)
external int _sessionGetProcessSnapshot(
  int session,
  Pointer<_NativeProcessSnapshot> snapshot,
);

@Native<Int32 Function(Uint64)>(
  symbol: 'dpty_session_destroy',
  assetId: _assetId,
)
external int _sessionDestroy(int session);

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _SessionCreateNative = Int32 Function(
  Pointer<_SessionConfig>,
  Pointer<Uint64>,
);
typedef _SessionCreateDart = int Function(
  Pointer<_SessionConfig>,
  Pointer<Uint64>,
);
typedef _SessionHandleNative = Int32 Function(Uint64);
typedef _SessionHandleDart = int Function(int);
typedef _SessionWriteNative = Int32 Function(Uint64, Pointer<Uint8>, Size);
typedef _SessionWriteDart = int Function(int, Pointer<Uint8>, int);
typedef _SessionWriteTrackedNative = Int32 Function(
  Uint64,
  Pointer<Uint8>,
  Size,
  Pointer<Uint64>,
);
typedef _SessionWriteTrackedDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint64>,
);
typedef _SessionAckNative = Int32 Function(Uint64, Uint64, Size);
typedef _SessionAckDart = int Function(int, int, int);
typedef _SessionResizeNative = Int32 Function(Uint64, Uint16, Uint16);
typedef _SessionResizeDart = int Function(int, int, int);
typedef _SessionUint32Native = Int32 Function(Uint64, Uint32);
typedef _SessionUint32Dart = int Function(int, int);
typedef _SessionStatsNative = Int32 Function(Uint64, Pointer<_NativeStats>);
typedef _SessionStatsDart = int Function(int, Pointer<_NativeStats>);
typedef _SessionProcessSnapshotNative = Int32 Function(
  Uint64,
  Pointer<_NativeProcessSnapshot>,
);
typedef _SessionProcessSnapshotDart = int Function(
  int,
  Pointer<_NativeProcessSnapshot>,
);

final class _PtyFunctions {
  _PtyFunctions.nativeAssets()
    : abiVersion = _nativeAbiVersion,
      sessionCreate = _sessionCreate,
      sessionStart = _sessionStart,
      sessionWrite = _sessionWrite,
      sessionWriteTracked = _sessionWriteTracked,
      sessionAckOutput = _sessionAckOutput,
      sessionResize = _sessionResize,
      sessionSendSignal = _sessionSendSignal,
      sessionClose = _sessionClose,
      sessionForceClose = _sessionForceClose,
      sessionGetStats = _sessionGetStats,
      sessionGetProcessSnapshot = _sessionGetProcessSnapshot,
      sessionDestroy = _sessionDestroy;

  _PtyFunctions.dynamic(DynamicLibrary library)
    : abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'dpty_abi_version',
      ),
      sessionCreate = library
          .lookupFunction<_SessionCreateNative, _SessionCreateDart>(
            'dpty_session_create',
          ),
      sessionStart = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_start',
          ),
      sessionWrite = library
          .lookupFunction<_SessionWriteNative, _SessionWriteDart>(
            'dpty_session_write',
          ),
      sessionWriteTracked = library
          .lookupFunction<_SessionWriteTrackedNative, _SessionWriteTrackedDart>(
            'dpty_session_write_tracked',
          ),
      sessionAckOutput = library
          .lookupFunction<_SessionAckNative, _SessionAckDart>(
            'dpty_session_ack_output',
          ),
      sessionResize = library
          .lookupFunction<_SessionResizeNative, _SessionResizeDart>(
            'dpty_session_resize',
          ),
      sessionSendSignal = library
          .lookupFunction<_SessionUint32Native, _SessionUint32Dart>(
            'dpty_session_send_signal',
          ),
      sessionClose = library
          .lookupFunction<_SessionUint32Native, _SessionUint32Dart>(
            'dpty_session_close',
          ),
      sessionForceClose = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_force_close',
          ),
      sessionGetStats = library
          .lookupFunction<_SessionStatsNative, _SessionStatsDart>(
            'dpty_session_get_stats',
          ),
      sessionGetProcessSnapshot = library
          .lookupFunction<
            _SessionProcessSnapshotNative,
            _SessionProcessSnapshotDart
          >('dpty_session_get_process_snapshot'),
      sessionDestroy = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_destroy',
          );

  final _AbiVersionDart abiVersion;
  final _SessionCreateDart sessionCreate;
  final _SessionHandleDart sessionStart;
  final _SessionWriteDart sessionWrite;
  final _SessionWriteTrackedDart sessionWriteTracked;
  final _SessionAckDart sessionAckOutput;
  final _SessionResizeDart sessionResize;
  final _SessionUint32Dart sessionSendSignal;
  final _SessionUint32Dart sessionClose;
  final _SessionHandleDart sessionForceClose;
  final _SessionStatsDart sessionGetStats;
  final _SessionProcessSnapshotDart sessionGetProcessSnapshot;
  final _SessionHandleDart sessionDestroy;
}

final Map<int, _MacosPtyProcess> _sessions = <int, _MacosPtyProcess>{};
final NativeCallable<_EventNative> _eventCallback =
    NativeCallable<_EventNative>.listener(_dispatchEvent)
      ..keepIsolateAlive = false;

void _refreshCallbackKeepAlive() {
  _eventCallback.keepIsolateAlive = _sessions.isNotEmpty;
}

void _dispatchEvent(
  int session,
  int eventType,
  int sequence,
  Pointer<Uint8> data,
  int length,
  int value1,
  int value2,
  int systemError,
  Pointer<Void> _,
) {
  final _MacosPtyProcess? process = _sessions[session];
  if (process == null) {
    return;
  }
  switch (eventType) {
    case _eventStarted:
      process._didStart(value1);
      return;
    case _eventOutput:
      if (data == nullptr || length <= 0) {
        process._didFail(
          const PtyException('native PTY returned an invalid output event'),
        );
        return;
      }
      final Uint8List bytes = Uint8List.fromList(data.asTypedList(length));
      process._didOutput(sequence, bytes);
      return;
    case _eventExit:
      process._didExit(value1, value2);
      return;
    case _eventError:
      process._didFail(
        PtyException(
          'native PTY reactor failed',
          status: value1,
          systemError: systemError,
        ),
      );
      return;
    case _eventWriteEnqueued:
    case _eventWriteDequeued:
    case _eventWriteCompleted:
    case _eventWriteError:
    case _eventForceCloseDequeued:
    case _eventSignalDelivery:
    case _eventWaitpidResult:
    case _eventExitPublished:
    case _eventStateSnapshot:
    case _eventTermiosSnapshot:
    case _eventProcessExitReady:
    case _eventExternalReapObserved:
      process._didDiagnostic(
        _decodeDiagnostic(
          eventType,
          sequence,
          length,
          value1,
          value2,
          systemError,
        ),
      );
      return;
    default:
      process._didFail(
        PtyException('native PTY returned unknown event $eventType'),
      );
      return;
  }
}

PtyDiagnosticEvent _decodeDiagnostic(
  int eventType,
  int sequence,
  int length,
  int value1,
  int value2,
  int systemError,
) {
  final int? requestId = sequence == 0 ? null : sequence;
  return switch (eventType) {
    _eventWriteEnqueued => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.writeEnqueued,
      requestId: requestId,
      byteCount: length,
      queuedBytes: value1,
    ),
    _eventWriteDequeued => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.writeDequeued,
      requestId: requestId,
      byteCount: length,
      queuedBytes: value1,
    ),
    _eventWriteCompleted => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.writeCompleted,
      requestId: requestId,
      byteCount: length,
      queuedBytes: value1,
    ),
    _eventWriteError => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.writeError,
      requestId: requestId,
      byteCount: length,
      queuedBytes: value1,
      systemError: systemError,
    ),
    _eventForceCloseDequeued => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.forceCloseDequeued,
      queuedBytes: value1,
    ),
    _eventSignalDelivery => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.signalDelivery,
      signal: length,
      signalTarget: value1,
      operationResult: value2,
      systemError: systemError,
    ),
    _eventWaitpidResult => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.waitpidResult,
      waitpidResult: value1,
      childStatus: value1 > 0 ? value2 : null,
      systemError: systemError,
    ),
    _eventExitPublished => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.exitPublished,
      exitCode: value1,
      exitSignal: value2 == 0 ? null : value2,
    ),
    _eventStateSnapshot => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.stateSnapshot,
      requestId: requestId,
      queuedBytes: length,
      foregroundProcessGroup: value1,
      sessionStateFlags: value2,
      systemError: systemError,
    ),
    _eventTermiosSnapshot => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.termiosSnapshot,
      requestId: requestId,
      terminalEofCharacter: value2 == 1 ? length : null,
      terminalLocalFlags: value2 == 1 ? value1 : null,
      operationResult: value2,
      systemError: systemError,
    ),
    _eventProcessExitReady => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.processExitReady,
      childProcessId: value1,
      childStatus: length == 1 ? value2 : null,
    ),
    _eventExternalReapObserved => PtyDiagnosticEvent(
      stage: PtyDiagnosticStage.externalReapObserved,
      childProcessId: value1,
      childStatus: value2,
      systemError: systemError,
    ),
    _ => throw StateError('unreachable PTY diagnostic event $eventType'),
  };
}

Future<PtyProcess> startPty(
  PtyCommand command, {
  PtyBackend? backend,
  PtySize initialSize = const PtySize(rows: 24, columns: 80),
  int readHighWaterBytes = 1024 * 1024,
  int readLowWaterBytes = 512 * 1024,
  int writeCapacityBytes = 1024 * 1024,
  bool enableDiagnostics = false,
}) {
  final PtyBackend selected = backend ?? MacosPtyBackend.shared;
  return selected.start(
    command,
    initialSize: initialSize,
    readHighWaterBytes: readHighWaterBytes,
    readLowWaterBytes: readLowWaterBytes,
    writeCapacityBytes: writeCapacityBytes,
    enableDiagnostics: enableDiagnostics,
  );
}

final class MacosPtyBackend implements PtyBackend {
  MacosPtyBackend._(this._functions);

  static final MacosPtyBackend shared = MacosPtyBackend._(
    _PtyFunctions.nativeAssets(),
  );

  factory MacosPtyBackend.open(String libraryPath) {
    final File library = File(libraryPath);
    if (!library.isAbsolute || !library.existsSync()) {
      throw ArgumentError.value(
        libraryPath,
        'libraryPath',
        'must name an existing absolute dylib path',
      );
    }
    return MacosPtyBackend._(
      _PtyFunctions.dynamic(DynamicLibrary.open(library.path)),
    );
  }

  final _PtyFunctions _functions;

  @override
  Future<PtyProcess> start(
    PtyCommand command, {
    PtySize initialSize = const PtySize(rows: 24, columns: 80),
    int readHighWaterBytes = 1024 * 1024,
    int readLowWaterBytes = 512 * 1024,
    int writeCapacityBytes = 1024 * 1024,
    bool enableDiagnostics = false,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('dart_pty_macos requires macOS');
    }
    if (_functions.abiVersion() != _abiVersion) {
      throw const PtyException('native PTY ABI version mismatch');
    }
    if (readHighWaterBytes <= 0 ||
        readLowWaterBytes < 0 ||
        readLowWaterBytes >= readHighWaterBytes ||
        writeCapacityBytes <= 0) {
      throw ArgumentError('PTY queue watermarks are invalid');
    }

    final Map<String, String> environment = <String, String>{
      if (command.includeParentEnvironment) ...Platform.environment,
      ...command.environment,
    };
    final String executableName = command.executable
        .split('/')
        .where((String part) => part.isNotEmpty)
        .last;
    final List<String> arguments = <String>[
      command.loginShell ? '-$executableName' : executableName,
      ...command.arguments,
    ];
    final List<String> environmentEntries = <String>[
      for (final String key in environment.keys.toList()..sort())
        '$key=${environment[key]}',
    ];
    final Arena arena = Arena();
    try {
      final Pointer<_SessionConfig> config = arena<_SessionConfig>();
      final Pointer<Pointer<Utf8>> argumentPointers = arena<Pointer<Utf8>>(
        arguments.length,
      );
      for (var index = 0; index < arguments.length; ++index) {
        argumentPointers[index] = arguments[index].toNativeUtf8(
          allocator: arena,
        );
      }
      final Pointer<Pointer<Utf8>> environmentPointers =
          environmentEntries.isEmpty
          ? nullptr
          : arena<Pointer<Utf8>>(environmentEntries.length);
      for (var index = 0; index < environmentEntries.length; ++index) {
        environmentPointers[index] = environmentEntries[index].toNativeUtf8(
          allocator: arena,
        );
      }
      config.ref
        ..structSize = sizeOf<_SessionConfig>()
        ..abiVersion = _abiVersion
        ..executable = command.executable.toNativeUtf8(allocator: arena)
        ..arguments = argumentPointers
        ..argumentCount = arguments.length
        ..environment = environmentPointers
        ..environmentCount = environmentEntries.length
        ..workingDirectory =
            (command.workingDirectory ?? Directory.current.path).toNativeUtf8(
              allocator: arena,
            )
        ..initialRows = initialSize.rows
        ..initialColumns = initialSize.columns
        ..readHighWaterBytes = readHighWaterBytes
        ..readLowWaterBytes = readLowWaterBytes
        ..writeCapacityBytes = writeCapacityBytes
        ..callback = _eventCallback.nativeFunction
        ..callbackContext = nullptr
        ..diagnosticsEnabled = enableDiagnostics ? 1 : 0
        ..readBatchBytes = command.readBatchBytes
        ..readBatchesPerEventLoopTurn = command.readBatchesPerEventLoopTurn;
      final Pointer<Uint64> output = arena<Uint64>();
      final int createStatus = _functions.sessionCreate(config, output);
      if (createStatus != _statusOk || output.value == 0) {
        throw PtyException(
          'native PTY session creation failed',
          status: createStatus,
        );
      }
      final _MacosPtyProcess process = _MacosPtyProcess(
        output.value,
        _functions,
        readBatchesPerEventLoopTurn: command.readBatchesPerEventLoopTurn,
      );
      _sessions[output.value] = process;
      _refreshCallbackKeepAlive();
      final int startStatus = _functions.sessionStart(output.value);
      if (startStatus != _statusOk) {
        _sessions.remove(output.value);
        _refreshCallbackKeepAlive();
        _functions.sessionDestroy(output.value);
        throw PtyException(
          'native PTY session start failed',
          status: startStatus,
        );
      }
      await process._started.future;
      return process;
    } finally {
      arena.releaseAll();
    }
  }
}

final class _MacosPtyProcess implements PtyProcess {
  _MacosPtyProcess(
    this._handle,
    this._functions, {
    required int readBatchesPerEventLoopTurn,
  }) : _readBatchesPerEventLoopTurn = readBatchesPerEventLoopTurn;

  final int _handle;
  final _PtyFunctions _functions;
  final int _readBatchesPerEventLoopTurn;
  final Completer<void> _started = Completer<void>();
  final Completer<PtyExit> _exit = Completer<PtyExit>();
  final StreamController<Uint8List> _output = StreamController<Uint8List>(
    sync: true,
  );
  final StreamController<PtyDiagnosticEvent> _diagnostics =
      StreamController<PtyDiagnosticEvent>(sync: true);
  int _pid = -1;
  bool _finished = false;
  bool _disposed = false;
  int _readBatchesSinceEventLoopYield = 0;
  PtyStats? _finalStats;

  @override
  int get pid => _pid;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Stream<PtyDiagnosticEvent> get diagnostics => _diagnostics.stream;

  @override
  Future<PtyExit> get exit => _exit.future;

  @override
  PtyStats? get finalStats => _finalStats;

  @override
  PtyProcessSnapshot processSnapshot() {
    _requireRunning();
    final Pointer<_NativeProcessSnapshot> snapshot =
        calloc<_NativeProcessSnapshot>();
    try {
      snapshot.ref
        ..structSize = sizeOf<_NativeProcessSnapshot>()
        ..abiVersion = _abiVersion;
      _checkStatus(
        _functions.sessionGetProcessSnapshot(_handle, snapshot),
        'PTY process snapshot',
      );
      final _NativeProcessSnapshot value = snapshot.ref;
      return PtyProcessSnapshot(
        childPid: value.childPid > 0 ? value.childPid : null,
        childProcessGroup: value.childProcessGroup > 0
            ? value.childProcessGroup
            : null,
        foregroundProcessGroup: value.foregroundProcessGroup > 0
            ? value.foregroundProcessGroup
            : null,
        childProcessGroupSystemError: value.childProcessGroupError,
        foregroundProcessGroupSystemError: value.foregroundProcessGroupError,
        hasExited: value.hasExited != 0,
        terminalEchoEnabled: value.terminalAttributesError == 0
            ? value.terminalEchoEnabled != 0
            : null,
        terminalAttributesSystemError: value.terminalAttributesError,
      );
    } finally {
      calloc.free(snapshot);
    }
  }

  @override
  PtyWriteResult write(Uint8List bytes) {
    return _write(bytes, tracked: false).result;
  }

  @override
  PtyWriteReceipt writeTracked(Uint8List bytes) {
    return _write(bytes, tracked: true);
  }

  PtyWriteReceipt _write(Uint8List bytes, {required bool tracked}) {
    _requireRunning();
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    final Pointer<Uint8> nativeBytes = malloc<Uint8>(bytes.length);
    final Pointer<Uint64> requestId = tracked ? calloc<Uint64>() : nullptr;
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      final int status = tracked
          ? _functions.sessionWriteTracked(
              _handle,
              nativeBytes,
              bytes.length,
              requestId,
            )
          : _functions.sessionWrite(_handle, nativeBytes, bytes.length);
      if (status == _statusBackpressured) {
        return const PtyWriteReceipt(
          result: PtyWriteResult.backpressured,
          requestId: null,
        );
      }
      _checkStatus(status, 'PTY write');
      final int? acceptedRequestId = tracked ? requestId.value : null;
      return PtyWriteReceipt(
        result: PtyWriteResult.accepted,
        requestId: acceptedRequestId,
      );
    } finally {
      if (tracked) {
        calloc.free(requestId);
      }
      malloc.free(nativeBytes);
    }
  }

  @override
  void resize(PtySize size) {
    _requireRunning();
    _checkStatus(
      _functions.sessionResize(_handle, size.rows, size.columns),
      'PTY resize',
    );
  }

  @override
  void sendSignal(PtySignal signal) {
    _requireRunning();
    _checkStatus(
      _functions.sessionSendSignal(_handle, signal.index + 1),
      'PTY signal',
    );
  }

  @override
  void close({Duration gracePeriod = const Duration(seconds: 2)}) {
    if (_finished) {
      return;
    }
    final int milliseconds = gracePeriod.inMilliseconds;
    if (milliseconds < 0 || milliseconds > 60000) {
      throw ArgumentError.value(
        gracePeriod,
        'gracePeriod',
        'must be between zero and 60 seconds',
      );
    }
    _checkStatus(_functions.sessionClose(_handle, milliseconds), 'PTY close');
  }

  @override
  void forceClose() {
    if (_finished || _disposed) {
      return;
    }
    _checkStatus(_functions.sessionForceClose(_handle), 'PTY force close');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (!_finished) {
      close();
      try {
        await exit;
      } on PtyException {
        // Native failure has already released the finished session.
      }
    }
    _disposed = true;
  }

  void _didStart(int pid) {
    if (_finished || _started.isCompleted) {
      _didFail(const PtyException('native PTY started more than once'));
      return;
    }
    _pid = pid;
    _started.complete();
  }

  void _didOutput(int sequence, Uint8List bytes) {
    if (!_finished) {
      _output.add(bytes);
    }
    if (_readBatchesPerEventLoopTurn > 0) {
      ++_readBatchesSinceEventLoopYield;
      if (_readBatchesSinceEventLoopYield >= _readBatchesPerEventLoopTurn) {
        _readBatchesSinceEventLoopYield = 0;
        Timer.run(() => _acknowledgeOutput(sequence, bytes.length));
        return;
      }
    }
    _acknowledgeOutput(sequence, bytes.length);
  }

  void _acknowledgeOutput(int sequence, int length) {
    if (_finished) {
      return;
    }
    final int status = _functions.sessionAckOutput(_handle, sequence, length);
    if (status != _statusOk) {
      _didFail(
        PtyException(
          'native PTY output acknowledgement failed',
          status: status,
        ),
      );
      return;
    }
  }

  void _didDiagnostic(PtyDiagnosticEvent event) {
    if (!_finished) {
      _diagnostics.add(event);
    }
  }

  void _didExit(int exitCode, int signal) {
    if (_finished) {
      return;
    }
    _finished = true;
    _finalStats = _readStats();
    final int destroyStatus = _functions.sessionDestroy(_handle);
    _sessions.remove(_handle);
    _refreshCallbackKeepAlive();
    if (destroyStatus != _statusOk) {
      _didFail(
        PtyException('native PTY destroy failed', status: destroyStatus),
      );
      return;
    }
    if (!_started.isCompleted) {
      _started.completeError(
        const PtyException('native PTY exited before reporting start'),
      );
    }
    _exit.complete(
      PtyExit(exitCode: exitCode, signal: signal == 0 ? null : signal),
    );
    unawaited(_output.close());
    unawaited(_diagnostics.close());
  }

  void _didFail(PtyException error) {
    if (_finished && _exit.isCompleted) {
      return;
    }
    _finished = true;
    _finalStats = _readStats();
    _sessions.remove(_handle);
    _refreshCallbackKeepAlive();
    _functions.sessionDestroy(_handle);
    final bool failedBeforeStart = !_started.isCompleted;
    if (failedBeforeStart) {
      _started.completeError(error);
    }
    if (!failedBeforeStart && !_exit.isCompleted) {
      _exit.completeError(error);
    }
    _output.addError(error);
    unawaited(_output.close());
    unawaited(_diagnostics.close());
  }

  PtyStats? _readStats() {
    final Pointer<_NativeStats> stats = calloc<_NativeStats>();
    try {
      stats.ref
        ..structSize = sizeOf<_NativeStats>()
        ..abiVersion = _abiVersion;
      if (_functions.sessionGetStats(_handle, stats) != _statusOk) {
        return null;
      }
      return PtyStats(
        bytesRead: stats.ref.bytesRead,
        bytesWritten: stats.ref.bytesWritten,
        readBatches: stats.ref.readBatches,
        writeBackpressureRejections: stats.ref.writeBackpressureRejections,
        maxReadInFlightBytes: stats.ref.maxReadInFlightBytes,
        maxWriteQueuedBytes: stats.ref.maxWriteQueuedBytes,
        readPauseCount: stats.ref.readPauseCount,
        childPid: stats.ref.childPid,
        hasExited: stats.ref.hasExited != 0,
      );
    } finally {
      calloc.free(stats);
    }
  }

  void _requireRunning() {
    if (_finished || _disposed) {
      throw StateError('PTY process has finished');
    }
  }
}

void _checkStatus(int status, String operation) {
  if (status != _statusOk) {
    throw PtyException('$operation failed', status: status);
  }
}
