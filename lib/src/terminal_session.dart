import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';

import 'terminal_buffer.dart';
import 'terminal_pane.dart';

enum TerminalSessionLifecycleStage {
  startRequested,
  processStarted,
  startFailed,
  eofRequested,
  eofWriteAccepted,
  eofWriteBackpressured,
  eofWriteIgnored,
  nativeExitObserved,
  outputDrainStarted,
  outputDrained,
  terminationObservationFailed,
  terminationCompleted,
  ownerTerminationNotified,
  disposeStarted,
  gracefulCloseRequested,
  gracefulCloseSkipped,
  gracefulCloseFailed,
  terminationWaitCompleted,
  terminationWaitTimedOut,
  terminationWaitFailed,
  forceCloseRequested,
  forceCloseFailed,
  finalTerminationWaitCompleted,
  finalTerminationWaitFailed,
  finalDeadlineExceeded,
  outputCancellationStarted,
  outputCancellationCompleted,
  outputCancellationTimedOut,
  outputCancellationFailed,
  outputDrainAbandoned,
  processDisposeStarted,
  processDisposeCompleted,
  processDisposeSkipped,
  processDisposeTimedOut,
  processDisposeFailed,
  shutdownResultPublished,
  disposeCompleted,
}

final class TerminalSessionShutdownResult
    extends TerminalPaneSessionShutdownResult {
  const TerminalSessionShutdownResult({
    required TerminalSessionId sessionId,
    required int? processId,
    required TerminalSessionShutdownDisposition disposition,
    required bool terminationObserved,
    required bool cleanupCompleted,
    required this.exit,
  }) : super(
         sessionId: sessionId,
         processId: processId,
         disposition: disposition,
         terminationObserved: terminationObserved,
         cleanupCompleted: cleanupCompleted,
       );

  final PtyExit? exit;
}

final class TerminalSessionLifecycleObservation {
  const TerminalSessionLifecycleObservation({
    required this.sessionId,
    required this.stage,
    required this.processId,
  });

  final TerminalSessionId sessionId;
  final TerminalSessionLifecycleStage stage;
  final int? processId;

  String machineLine() =>
      'TERMINAL_PTY_LIFECYCLE pane=${sessionId.paneId} '
      'session=$sessionId process_id=${processId ?? 0} '
      'stage=${stage.name}';
}

typedef TerminalSessionLifecycleObserver = void Function(
  TerminalSessionLifecycleObservation observation,
);

/// One persistent interactive shell generation owned by a terminal pane.
final class TerminalSession implements TerminalPaneSession {
  TerminalSession({
    required this.id,
    required void Function() onChanged,
    required void Function() onTerminated,
    PtyBackend? ptyBackend,
    String? initialWorkingDirectory,
    Map<String, String>? environment,
    this.shellExecutable = '/bin/zsh',
    List<String> shellArguments = const <String>[],
    this.writeCapacityBytes = 1024 * 1024,
    this.gracefulShutdownTimeout = const Duration(seconds: 3),
    this.finalShutdownTimeout = const Duration(seconds: 1),
    this.cleanupStepTimeout = const Duration(seconds: 1),
    TerminalSessionLifecycleObserver? lifecycleObserver,
  }) : _onChanged = onChanged,
       _onTerminated = onTerminated,
       _lifecycleObserver = lifecycleObserver,
       _ptyBackend = ptyBackend ?? MacosPtyBackend.shared,
       shellArguments = List<String>.unmodifiable(shellArguments),
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _workingDirectory = Directory(
         initialWorkingDirectory ?? Directory.current.path,
       ).absolute.path {
    if (writeCapacityBytes <= 0) {
      throw ArgumentError.value(
        writeCapacityBytes,
        'writeCapacityBytes',
        'must be positive',
      );
    }
    for (final MapEntry<String, Duration> timeout in <String, Duration>{
      'gracefulShutdownTimeout': gracefulShutdownTimeout,
      'finalShutdownTimeout': finalShutdownTimeout,
      'cleanupStepTimeout': cleanupStepTimeout,
    }.entries) {
      if (timeout.value <= Duration.zero) {
        throw ArgumentError.value(
          timeout.value,
          timeout.key,
          'must be positive',
        );
      }
    }
  }

  @override
  final TerminalSessionId id;
  final void Function() _onChanged;
  final void Function() _onTerminated;
  final TerminalSessionLifecycleObserver? _lifecycleObserver;
  final PtyBackend _ptyBackend;
  final Map<String, String> _environment;
  final String shellExecutable;
  final List<String> shellArguments;
  final int writeCapacityBytes;
  final Duration gracefulShutdownTimeout;
  final Duration finalShutdownTimeout;
  final Duration cleanupStepTimeout;

  final TerminalBuffer buffer = TerminalBuffer();
  final Completer<void> _terminated = Completer<void>();
  final String _workingDirectory;

  PtyProcess? _process;
  // ignore: cancel_subscriptions - bounded cancellation is centralized below.
  StreamSubscription<String>? _outputSubscription;
  Completer<void>? _outputDone;
  Future<void>? _startFuture;
  Future<void>? _terminationFuture;
  Future<void>? _disposeFuture;
  Future<TerminalSessionShutdownResult>? _shutdownFuture;
  PtyExit? _exit;
  Object? _failure;
  TerminalSessionShutdownResult? _shutdownResult;
  var _live = false;
  var _disposed = false;
  var _outputDrainAbandoned = false;
  var _terminationNotified = false;
  var _writeBackpressured = false;
  var _rows = 23;
  var _columns = 100;
  var _writeBackpressureCount = 0;

  @override
  bool get isLive => _live;
  int? get processId => _process?.pid;
  PtyExit? get exit => _exit;
  Object? get failure => _failure;
  int get writeBackpressureCount => _writeBackpressureCount;
  TerminalSessionShutdownResult? get shutdownResult => _shutdownResult;

  Future<void> waitForTermination() => _terminated.future;

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_disposed) {
      throw StateError('terminal session $id is disposed');
    }
    _observeLifecycle(TerminalSessionLifecycleStage.startRequested);
    try {
      final Map<String, String> environment = <String, String>{..._environment};
      environment.putIfAbsent('TERM', () => 'xterm-256color');
      environment.putIfAbsent('COLORTERM', () => 'truecolor');
      final PtyProcess process = await _ptyBackend.start(
        PtyCommand(
          executable: shellExecutable,
          arguments: shellArguments,
          environment: environment,
          includeParentEnvironment: false,
          workingDirectory: _workingDirectory,
          loginShell: true,
        ),
        initialSize: PtySize(rows: _rows, columns: _columns),
        writeCapacityBytes: writeCapacityBytes,
      );
      if (_disposed) {
        process.close(gracePeriod: Duration.zero);
        await process.dispose();
        return;
      }
      _process = process;
      _live = true;
      _observeLifecycle(TerminalSessionLifecycleStage.processStarted);
      final Completer<void> outputDone = Completer<void>();
      _outputDone = outputDone;
      const Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
      _outputSubscription = process.output
          .cast<List<int>>()
          .transform(decoder)
          .listen(
            _appendOutput,
            onError: (Object error, StackTrace stackTrace) {
              if (!outputDone.isCompleted) {
                outputDone.completeError(error, stackTrace);
              }
            },
            onDone: () {
              if (!outputDone.isCompleted) {
                outputDone.complete();
              }
            },
            cancelOnError: false,
          );
      _terminationFuture = _observeTermination(process, outputDone.future);
      unawaited(_terminationFuture);
      _notifyChanged();
    } on Object catch (error) {
      _failure = error;
      _observeLifecycle(TerminalSessionLifecycleStage.startFailed);
      buffer.appendStatusLine('Could not start login shell: $error');
      _completeTermination(notifyOwner: false);
      _notifyChanged();
      rethrow;
    }
  }

  Future<void> _observeTermination(
    PtyProcess process,
    Future<void> outputDone,
  ) async {
    try {
      final PtyExit exit = await process.exit;
      _observeLifecycle(TerminalSessionLifecycleStage.nativeExitObserved);
      _observeLifecycle(TerminalSessionLifecycleStage.outputDrainStarted);
      await outputDone;
      _observeLifecycle(
        _outputDrainAbandoned
            ? TerminalSessionLifecycleStage.outputDrainAbandoned
            : TerminalSessionLifecycleStage.outputDrained,
      );
      if (!identical(_process, process)) {
        return;
      }
      _exit = exit;
      _live = false;
      buffer.finishOutput();
      if (!_disposed && exit.exitCode != 0) {
        final String status = exit.signal == null
            ? '${exit.exitCode}'
            : 'signal ${exit.signal}';
        buffer.appendStatusLine('[shell exited with status $status]');
      }
    } on Object catch (error) {
      _observeLifecycle(
        TerminalSessionLifecycleStage.terminationObservationFailed,
      );
      if (identical(_process, process)) {
        _failure = error;
        _live = false;
        if (!_disposed) {
          buffer.appendStatusLine('[shell stream failed: $error]');
        }
      }
    } finally {
      if (identical(_process, process)) {
        _completeTermination();
        _notifyChanged();
      }
    }
  }

  @override
  String render() => buffer.renderOutput(rows: _rows);

  @override
  void insertText(String value) {
    if (value.isEmpty) {
      return;
    }
    _write(utf8.encode(value));
  }

  @override
  void deleteBackward() => _write(const <int>[0x7f]);

  @override
  void deleteForward() => _write(const <int>[0x1b, 0x5b, 0x33, 0x7e]);

  @override
  void moveLeft() => _write(const <int>[0x1b, 0x5b, 0x44]);

  @override
  void moveRight() => _write(const <int>[0x1b, 0x5b, 0x43]);

  @override
  void moveToStart() => _write(const <int>[0x1b, 0x5b, 0x48]);

  @override
  void moveToEnd() => _write(const <int>[0x1b, 0x5b, 0x46]);

  @override
  void previousHistory() => _write(const <int>[0x1b, 0x5b, 0x41]);

  @override
  void nextHistory() => _write(const <int>[0x1b, 0x5b, 0x42]);

  @override
  Future<void> submit() async {
    _write(const <int>[0x0d]);
  }

  @override
  void interrupt() => _sendSignal(PtySignal.interrupt);

  @override
  void suspend() => _sendSignal(PtySignal.suspend);

  @override
  void quitForegroundProcess() => _sendSignal(PtySignal.quit);

  @override
  void sendEndOfFile() {
    _observeLifecycle(TerminalSessionLifecycleStage.eofRequested);
    final PtyWriteResult? result = _write(const <int>[0x04]);
    _observeLifecycle(switch (result) {
      PtyWriteResult.accepted => TerminalSessionLifecycleStage.eofWriteAccepted,
      PtyWriteResult.backpressured =>
        TerminalSessionLifecycleStage.eofWriteBackpressured,
      null => TerminalSessionLifecycleStage.eofWriteIgnored,
    });
  }

  @override
  void resize({required int rows, required int columns}) {
    if (rows <= 0 || rows > 65535 || columns <= 0 || columns > 65535) {
      throw ArgumentError('terminal dimensions must be between 1 and 65535');
    }
    _rows = rows;
    _columns = columns;
    if (_live) {
      try {
        _process!.resize(PtySize(rows: rows, columns: columns));
      } on StateError {
        // The exit callback will publish the terminal state.
      }
    }
    _notifyChanged();
  }

  @override
  void showCloseConfirmation() {
    if (_disposed) {
      return;
    }
    buffer.appendStatusLine(
      '[shell is still running — repeat Close or Quit to terminate it]',
    );
    _notifyChanged();
  }

  @override
  Future<TerminalSessionShutdownResult> shutdown() =>
      _shutdownFuture ??= _shutdown();

  Future<void> dispose() => _disposeFuture ??= _disposeAndDiscardResult();

  Future<void> _disposeAndDiscardResult() async {
    await shutdown();
  }

  Future<TerminalSessionShutdownResult> _shutdown() async {
    _disposed = true;
    _observeLifecycle(TerminalSessionLifecycleStage.disposeStarted);
    final PtyProcess? process = _process;
    if (process == null) {
      _completeTermination(notifyOwner: false);
      final TerminalSessionShutdownResult result = _publishShutdownResult(
        disposition: _failure == null
            ? TerminalSessionShutdownDisposition.clean
            : TerminalSessionShutdownDisposition.failed,
        processId: null,
        terminationObserved: true,
        cleanupCompleted: true,
      );
      _observeLifecycle(TerminalSessionLifecycleStage.disposeCompleted);
      return result;
    }
    final int processId = process.pid;
    var shutdownFailed = false;
    try {
      process.close();
      _observeLifecycle(TerminalSessionLifecycleStage.gracefulCloseRequested);
    } on StateError {
      _observeLifecycle(TerminalSessionLifecycleStage.gracefulCloseSkipped);
      // The process exited between the live-state check and close.
    } on Object catch (error) {
      _failure ??= error;
      shutdownFailed = true;
      _observeLifecycle(TerminalSessionLifecycleStage.gracefulCloseFailed);
    }
    final Future<void> termination = _terminationFuture ?? process.exit;
    var terminationObserved = false;
    var forced = false;
    var deadlineExceeded = false;
    try {
      await termination.timeout(gracefulShutdownTimeout);
      terminationObserved = true;
      _observeLifecycle(TerminalSessionLifecycleStage.terminationWaitCompleted);
    } on TimeoutException {
      _observeLifecycle(TerminalSessionLifecycleStage.terminationWaitTimedOut);
      try {
        process.forceClose();
        forced = true;
        _observeLifecycle(TerminalSessionLifecycleStage.forceCloseRequested);
      } on Object catch (error) {
        _failure ??= error;
        shutdownFailed = true;
        _observeLifecycle(TerminalSessionLifecycleStage.forceCloseFailed);
      }
      try {
        await termination.timeout(finalShutdownTimeout);
        terminationObserved = true;
        _observeLifecycle(
          TerminalSessionLifecycleStage.finalTerminationWaitCompleted,
        );
      } on TimeoutException {
        deadlineExceeded = true;
        _observeLifecycle(TerminalSessionLifecycleStage.finalDeadlineExceeded);
      } on Object catch (error) {
        _failure ??= error;
        shutdownFailed = true;
        _observeLifecycle(
          TerminalSessionLifecycleStage.finalTerminationWaitFailed,
        );
      }
    } on Object catch (error) {
      _failure ??= error;
      shutdownFailed = true;
      _observeLifecycle(TerminalSessionLifecycleStage.terminationWaitFailed);
    }

    final bool outputCancelled = await _cancelOutputSubscription();
    var processDisposed = false;
    if (terminationObserved) {
      _observeLifecycle(TerminalSessionLifecycleStage.processDisposeStarted);
      try {
        await process.dispose().timeout(cleanupStepTimeout);
        processDisposed = true;
        _observeLifecycle(
          TerminalSessionLifecycleStage.processDisposeCompleted,
        );
      } on TimeoutException {
        shutdownFailed = true;
        _observeLifecycle(TerminalSessionLifecycleStage.processDisposeTimedOut);
      } on Object catch (error) {
        _failure ??= error;
        shutdownFailed = true;
        _observeLifecycle(TerminalSessionLifecycleStage.processDisposeFailed);
      }
    } else {
      _observeLifecycle(TerminalSessionLifecycleStage.processDisposeSkipped);
    }
    _live = false;
    _completeTermination(notifyOwner: false);
    final TerminalSessionShutdownResult result = _publishShutdownResult(
      disposition: deadlineExceeded
          ? TerminalSessionShutdownDisposition.deadlineExceeded
          : shutdownFailed || _failure != null || !outputCancelled
          ? TerminalSessionShutdownDisposition.failed
          : forced
          ? TerminalSessionShutdownDisposition.forced
          : TerminalSessionShutdownDisposition.clean,
      processId: processId,
      terminationObserved: terminationObserved,
      cleanupCompleted:
          outputCancelled && terminationObserved && processDisposed,
    );
    _observeLifecycle(TerminalSessionLifecycleStage.disposeCompleted);
    return result;
  }

  Future<bool> _cancelOutputSubscription() async {
    _observeLifecycle(TerminalSessionLifecycleStage.outputCancellationStarted);
    final StreamSubscription<String>? subscription = _outputSubscription;
    _outputSubscription = null;
    if (subscription == null) {
      _observeLifecycle(
        TerminalSessionLifecycleStage.outputCancellationCompleted,
      );
      return true;
    }
    try {
      final Future<void> cancellation = subscription.cancel();
      final Completer<void>? outputDone = _outputDone;
      if (outputDone != null && !outputDone.isCompleted) {
        _outputDrainAbandoned = true;
        outputDone.complete();
      }
      await cancellation.timeout(cleanupStepTimeout);
      _observeLifecycle(
        TerminalSessionLifecycleStage.outputCancellationCompleted,
      );
      return true;
    } on TimeoutException {
      _observeLifecycle(
        TerminalSessionLifecycleStage.outputCancellationTimedOut,
      );
      return false;
    } on Object catch (error) {
      _failure ??= error;
      _observeLifecycle(TerminalSessionLifecycleStage.outputCancellationFailed);
      return false;
    }
  }

  TerminalSessionShutdownResult _publishShutdownResult({
    required TerminalSessionShutdownDisposition disposition,
    required int? processId,
    required bool terminationObserved,
    required bool cleanupCompleted,
  }) {
    final TerminalSessionShutdownResult result = TerminalSessionShutdownResult(
      sessionId: id,
      processId: processId,
      disposition: disposition,
      terminationObserved: terminationObserved,
      cleanupCompleted: cleanupCompleted,
      exit: _exit,
    );
    _shutdownResult = result;
    _observeLifecycle(TerminalSessionLifecycleStage.shutdownResultPublished);
    return result;
  }

  PtyWriteResult? _write(List<int> bytes) {
    final PtyProcess? process = _process;
    if (!_live || _disposed || process == null) {
      return null;
    }
    late final PtyWriteResult result;
    try {
      result = process.write(Uint8List.fromList(bytes));
    } on StateError {
      return null;
    }
    if (result == PtyWriteResult.backpressured) {
      ++_writeBackpressureCount;
      if (!_writeBackpressured) {
        _writeBackpressured = true;
        buffer.appendStatusLine('[terminal input is backpressured]');
        _notifyChanged();
      }
      return result;
    }
    _writeBackpressured = false;
    return result;
  }

  void _sendSignal(PtySignal signal) {
    final PtyProcess? process = _process;
    if (!_live || _disposed || process == null) {
      return;
    }
    _trySendSignal(process, signal);
  }

  void _appendOutput(String value) {
    if (_disposed || value.isEmpty) {
      return;
    }
    buffer.appendOutput(value);
    _notifyChanged();
  }

  void _trySendSignal(PtyProcess process, PtySignal signal) {
    try {
      process.sendSignal(signal);
    } on StateError {
      // A concurrently delivered exit owns the final state transition.
    }
  }

  void _completeTermination({bool notifyOwner = true}) {
    if (!_terminated.isCompleted) {
      _terminated.complete();
      _observeLifecycle(TerminalSessionLifecycleStage.terminationCompleted);
    }
    if (notifyOwner && !_terminationNotified) {
      _terminationNotified = true;
      _observeLifecycle(TerminalSessionLifecycleStage.ownerTerminationNotified);
      _onTerminated();
    }
  }

  void _observeLifecycle(TerminalSessionLifecycleStage stage) {
    final TerminalSessionLifecycleObserver? observer = _lifecycleObserver;
    if (observer == null) {
      return;
    }
    try {
      observer(
        TerminalSessionLifecycleObservation(
          sessionId: id,
          stage: stage,
          processId: processId,
        ),
      );
    } on Object {
      // Diagnostics cannot change PTY ownership or shutdown behavior.
    }
  }

  void _notifyChanged() {
    if (!_disposed) {
      _onChanged();
    }
  }
}
