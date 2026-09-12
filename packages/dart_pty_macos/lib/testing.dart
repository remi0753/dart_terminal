library;

import 'dart:async';
import 'dart:typed_data';

import 'dart_pty_macos.dart';

final class FakePtyBackend implements PtyBackend {
  FakePtyBackend({
    this.firstPid = 4000,
    this.autoExitOnClose = true,
    this.autoExitOnForceClose = true,
  });

  final int firstPid;
  final bool autoExitOnClose;
  final bool autoExitOnForceClose;
  final List<PtyCommand> commands = <PtyCommand>[];
  final List<FakePtyProcess> processes = <FakePtyProcess>[];

  @override
  Future<PtyProcess> start(
    PtyCommand command, {
    PtySize initialSize = const PtySize(rows: 24, columns: 80),
    int readHighWaterBytes = 1024 * 1024,
    int readLowWaterBytes = 512 * 1024,
    int writeCapacityBytes = 1024 * 1024,
    bool enableDiagnostics = false,
  }) async {
    if (readHighWaterBytes <= 0 ||
        readLowWaterBytes < 0 ||
        readLowWaterBytes >= readHighWaterBytes ||
        writeCapacityBytes <= 0) {
      throw ArgumentError('PTY queue watermarks are invalid');
    }
    commands.add(command);
    final FakePtyProcess process = FakePtyProcess(
      pid: firstPid + processes.length,
      initialSize: initialSize,
      writeCapacityBytes: writeCapacityBytes,
      autoExitOnClose: autoExitOnClose,
      autoExitOnForceClose: autoExitOnForceClose,
      diagnosticsEnabled: enableDiagnostics,
    );
    processes.add(process);
    return process;
  }
}

final class FakePtyProcess implements PtyProcess {
  FakePtyProcess({
    required this.pid,
    required PtySize initialSize,
    required this.writeCapacityBytes,
    required this.autoExitOnClose,
    required this.autoExitOnForceClose,
    required this.diagnosticsEnabled,
  }) : sizes = <PtySize>[initialSize];

  @override
  final int pid;
  final int writeCapacityBytes;
  final bool autoExitOnClose;
  final bool autoExitOnForceClose;
  final bool diagnosticsEnabled;
  final List<Uint8List> writes = <Uint8List>[];
  final List<PtySize> sizes;
  final List<PtySignal> signals = <PtySignal>[];
  final List<Duration> closeGracePeriods = <Duration>[];
  int forceCloseRequests = 0;
  final StreamController<Uint8List> _output = StreamController<Uint8List>(
    sync: true,
  );
  final StreamController<PtyDiagnosticEvent> _diagnostics =
      StreamController<PtyDiagnosticEvent>(sync: true);
  final Completer<PtyExit> _exit = Completer<PtyExit>();
  var _queuedWriteBytes = 0;
  var _bytesRead = 0;
  var _nextWriteRequestId = 1;
  var _finished = false;
  PtyStats? _finalStats;
  int? childProcessGroup;
  int? foregroundProcessGroup;
  int childProcessGroupSystemError = 0;
  int foregroundProcessGroupSystemError = 0;
  bool terminalEchoEnabled = true;
  int terminalAttributesSystemError = 0;

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
    childProcessGroup ??= pid;
    foregroundProcessGroup ??= pid;
    return PtyProcessSnapshot(
      childPid: pid,
      childProcessGroup: childProcessGroupSystemError == 0
          ? childProcessGroup
          : null,
      foregroundProcessGroup: foregroundProcessGroupSystemError == 0
          ? foregroundProcessGroup
          : null,
      childProcessGroupSystemError: childProcessGroupSystemError,
      foregroundProcessGroupSystemError: foregroundProcessGroupSystemError,
      hasExited: false,
      terminalEchoEnabled: terminalAttributesSystemError == 0
          ? terminalEchoEnabled
          : null,
      terminalAttributesSystemError: terminalAttributesSystemError,
    );
  }

  @override
  PtyWriteResult write(Uint8List bytes) {
    _requireRunning();
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    if (bytes.length > writeCapacityBytes ||
        _queuedWriteBytes > writeCapacityBytes - bytes.length) {
      return PtyWriteResult.backpressured;
    }
    final Uint8List copied = Uint8List.fromList(bytes);
    writes.add(copied);
    _queuedWriteBytes += copied.length;
    return PtyWriteResult.accepted;
  }

  @override
  PtyWriteReceipt writeTracked(Uint8List bytes) {
    final PtyWriteResult result = write(bytes);
    return PtyWriteReceipt(
      result: result,
      requestId: result == PtyWriteResult.accepted
          ? _nextWriteRequestId++
          : null,
    );
  }

  void drainWrites() {
    _queuedWriteBytes = 0;
  }

  void emitOutput(List<int> bytes) {
    _requireRunning();
    final Uint8List copied = Uint8List.fromList(bytes);
    _bytesRead += copied.length;
    _output.add(copied);
  }

  void emitDiagnostic(PtyDiagnosticEvent event) {
    _requireRunning();
    if (diagnosticsEnabled) {
      _diagnostics.add(event);
    }
  }

  @override
  void resize(PtySize size) {
    _requireRunning();
    sizes.add(size);
  }

  @override
  void sendSignal(PtySignal signal) {
    _requireRunning();
    signals.add(signal);
  }

  @override
  void close({Duration gracePeriod = const Duration(seconds: 2)}) {
    if (_finished) {
      return;
    }
    closeGracePeriods.add(gracePeriod);
    if (autoExitOnClose) {
      finish(exitCode: 129, signal: 1);
    }
  }

  @override
  void forceClose() {
    if (_finished) {
      return;
    }
    ++forceCloseRequests;
    if (autoExitOnForceClose) {
      finish(exitCode: 137, signal: 9);
    }
  }

  void finish({required int exitCode, int? signal}) {
    _requireRunning();
    _finished = true;
    _finalStats = PtyStats(
      bytesRead: _bytesRead,
      bytesWritten: writes.fold<int>(
        0,
        (int sum, Uint8List value) => sum + value.length,
      ),
      readBatches: 0,
      writeBackpressureRejections: 0,
      maxReadInFlightBytes: 0,
      maxWriteQueuedBytes: _queuedWriteBytes,
      readPauseCount: 0,
      childPid: pid,
      hasExited: true,
    );
    _exit.complete(PtyExit(exitCode: exitCode, signal: signal));
    unawaited(_output.close());
    unawaited(_diagnostics.close());
  }

  @override
  Future<void> dispose() async {
    if (!_finished) {
      close();
      if (!_finished) {
        finish(exitCode: 0);
      }
    }
    await exit;
  }

  void _requireRunning() {
    if (_finished) {
      throw StateError('fake PTY process has finished');
    }
  }
}
