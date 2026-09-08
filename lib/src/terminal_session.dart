import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';

import 'terminal_buffer.dart';
import 'terminal_core/terminal_keyboard_modes.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_core/terminal_screen_parser_sink.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_core/vt_parser.dart';
import 'terminal_input/terminal_hyperlink_interaction.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_input/terminal_paste.dart';
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
    this.writeRequestId,
  });

  final TerminalSessionId sessionId;
  final TerminalSessionLifecycleStage stage;
  final int? processId;
  final int? writeRequestId;

  String machineLine() =>
      'TERMINAL_PTY_LIFECYCLE pane=${sessionId.paneId} '
      'session=$sessionId process_id=${processId ?? 0} '
      'stage=${stage.name}'
      '${writeRequestId == null ? '' : ' request_id=$writeRequestId'}';
}

typedef TerminalSessionLifecycleObserver = void Function(
  TerminalSessionLifecycleObservation observation,
);

final class TerminalSessionNativeObservation {
  const TerminalSessionNativeObservation({
    required this.sessionId,
    required this.processId,
    required this.event,
  });

  final TerminalSessionId sessionId;
  final int? processId;
  final PtyDiagnosticEvent event;

  String machineLine() =>
      'TERMINAL_PTY_NATIVE pane=${sessionId.paneId} session=$sessionId '
      'process_id=${processId ?? 0} stage=${event.stage.name} '
      'request_id=${event.requestId ?? 0} byte_count=${event.byteCount ?? 0} '
      'queued_bytes=${event.queuedBytes ?? 0} '
      'foreground_pgid=${event.foregroundProcessGroup ?? 0} '
      'state_flags=${event.sessionStateFlags ?? 0} '
      'terminal_lflag=${event.terminalLocalFlags ?? 0} '
      'terminal_veof=${event.terminalEofCharacter ?? 0} '
      'signal=${event.signal ?? 0} signal_target=${event.signalTarget ?? 0} '
      'operation_result=${event.operationResult ?? 0} '
      'waitpid_result=${event.waitpidResult ?? 0} '
      'child_status=${event.childStatus ?? 0} '
      'child_status_valid=${event.childStatus != null} '
      'child_process_id=${event.childProcessId ?? 0} '
      'exit_code=${event.exitCode ?? 0} exit_signal=${event.exitSignal ?? 0} '
      'errno=${event.systemError}';
}

typedef TerminalSessionNativeObserver = void Function(
  TerminalSessionNativeObservation observation,
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
    this.readBatchBytes = defaultReadBatchBytes,
    this.writeCapacityBytes = 1024 * 1024,
    this.gracefulShutdownTimeout = const Duration(seconds: 3),
    this.finalShutdownTimeout = const Duration(seconds: 1),
    this.cleanupStepTimeout = const Duration(seconds: 1),
    TerminalSessionLifecycleObserver? lifecycleObserver,
    TerminalSessionNativeObserver? nativeObserver,
  }) : _onChanged = onChanged,
       _onTerminated = onTerminated,
       _lifecycleObserver = lifecycleObserver,
       _nativeObserver = nativeObserver,
       _ptyBackend = ptyBackend ?? MacosPtyBackend.shared,
       shellArguments = List<String>.unmodifiable(shellArguments),
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _workingDirectory = Directory(
         initialWorkingDirectory ?? Directory.current.path,
       ).absolute.path {
    if (readBatchBytes <= 0 ||
        readBatchBytes > PtyCommand.maximumReadBatchBytes) {
      throw RangeError.range(
        readBatchBytes,
        1,
        PtyCommand.maximumReadBatchBytes,
        'readBatchBytes',
      );
    }
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
    terminalScreenSet = TerminalScreenSet(rows: _rows, columns: _columns);
    terminalParserSink = TerminalScreenParserSink.forScreenSet(
      terminalScreenSet,
      onReply: _writeTerminalReply,
    );
    _terminalParser = VtParser(sink: terminalParserSink);
  }

  @override
  final TerminalSessionId id;
  final void Function() _onChanged;
  final void Function() _onTerminated;
  final TerminalSessionLifecycleObserver? _lifecycleObserver;
  final TerminalSessionNativeObserver? _nativeObserver;
  final PtyBackend _ptyBackend;
  final Map<String, String> _environment;
  final String shellExecutable;
  final List<String> shellArguments;
  static const int defaultReadBatchBytes = 4 * 1024;
  static const int defaultReadHighWaterBytes = defaultReadBatchBytes;
  static const int defaultReadLowWaterBytes = 0;
  final int readBatchBytes;
  final int writeCapacityBytes;
  final Duration gracefulShutdownTimeout;
  final Duration finalShutdownTimeout;
  final Duration cleanupStepTimeout;

  final TerminalBuffer buffer = TerminalBuffer();
  late final TerminalScreenSet terminalScreenSet;
  late final TerminalScreenParserSink terminalParserSink;
  late final VtParser _terminalParser;
  final Completer<void> _terminated = Completer<void>();
  final String _workingDirectory;

  PtyProcess? _process;
  // ignore: cancel_subscriptions - bounded cancellation is centralized below.
  StreamSubscription<String>? _outputSubscription;
  // ignore: cancel_subscriptions - bounded cancellation is centralized below.
  StreamSubscription<PtyDiagnosticEvent>? _diagnosticSubscription;
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
  var _replyWriteBackpressured = false;
  Future<TerminalPasteTransferResult>? _pasteFuture;
  Completer<_TerminalPasteWriteOutcome>? _pasteWriteCompletion;
  int? _pasteWriteRequestId;
  var _pasteWriteMaximumQueuedBytes = 0;
  var _pasteConcurrentInputNoticePublished = false;
  var _pasteConcurrentInputRejectionCount = 0;
  var _rows = 23;
  var _columns = 100;
  var _writeBackpressureCount = 0;
  var _replyWriteBackpressureCount = 0;

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition {
    if (_failure != null) {
      return TerminalPaneSessionExitDisposition.failed;
    }
    final PtyExit? observedExit = _exit;
    if (observedExit == null) {
      return null;
    }
    if (observedExit.signal != null) {
      return TerminalPaneSessionExitDisposition.signaled;
    }
    return observedExit.exitCode == 0
        ? TerminalPaneSessionExitDisposition.clean
        : TerminalPaneSessionExitDisposition.nonZero;
  }

  @override
  TerminalKeyboardModes get keyboardModes => terminalScreenSet.keyboardModes;
  @override
  bool get bracketedPasteMode => terminalScreenSet.bracketedPasteMode;
  @override
  bool get pasteInProgress => _pasteFuture != null;

  int? get processId => _process?.pid;
  PtyExit? get exit => _exit;
  Object? get failure => _failure;
  int get writeBackpressureCount => _writeBackpressureCount;
  int get replyWriteBackpressureCount => _replyWriteBackpressureCount;
  bool get replyWriteBackpressured => _replyWriteBackpressured;
  int get pasteConcurrentInputRejectionCount =>
      _pasteConcurrentInputRejectionCount;
  TerminalSessionShutdownResult? get shutdownResult => _shutdownResult;

  @override
  TerminalPaneProcessSnapshot processSnapshot() {
    if (!_live) {
      return TerminalPaneProcessSnapshot.nonLive(id);
    }
    final PtyProcess? process = _process;
    if (process == null) {
      return TerminalPaneProcessSnapshot.unavailable(sessionId: id);
    }
    try {
      final PtyProcessSnapshot snapshot = process.processSnapshot();
      if (!_live || snapshot.hasExited) {
        return TerminalPaneProcessSnapshot.nonLive(id);
      }
      final int? childProcessId = snapshot.childPid;
      final int? owningProcessGroup = snapshot.childProcessGroup;
      final int? foregroundProcessGroup = snapshot.foregroundProcessGroup;
      if (!snapshot.isAvailable ||
          childProcessId == null ||
          owningProcessGroup == null ||
          foregroundProcessGroup == null) {
        return TerminalPaneProcessSnapshot.unavailable(
          sessionId: id,
          childProcessId: childProcessId,
          owningProcessGroup: owningProcessGroup,
          foregroundProcessGroup: foregroundProcessGroup,
          owningProcessGroupSystemError: snapshot.childProcessGroupSystemError,
          foregroundProcessGroupSystemError:
              snapshot.foregroundProcessGroupSystemError,
        );
      }
      return TerminalPaneProcessSnapshot.available(
        sessionId: id,
        childProcessId: childProcessId,
        owningProcessGroup: owningProcessGroup,
        foregroundProcessGroup: foregroundProcessGroup,
      );
    } on Object {
      return TerminalPaneProcessSnapshot.unavailable(sessionId: id);
    }
  }

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
          readBatchBytes: readBatchBytes,
        ),
        initialSize: PtySize(rows: _rows, columns: _columns),
        readHighWaterBytes: defaultReadHighWaterBytes,
        readLowWaterBytes: defaultReadLowWaterBytes,
        writeCapacityBytes: writeCapacityBytes,
        enableDiagnostics: true,
      );
      if (_disposed) {
        process.close(gracePeriod: Duration.zero);
        await process.dispose();
        return;
      }
      _process = process;
      _live = true;
      _observeLifecycle(TerminalSessionLifecycleStage.processStarted);
      _diagnosticSubscription = process.diagnostics.listen(
        _observeNativeDiagnostic,
        onError: (Object _, StackTrace _) {},
      );
      final Completer<void> outputDone = Completer<void>();
      _outputDone = outputDone;
      const Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
      _outputSubscription = process.output
          .map<List<int>>((Uint8List bytes) {
            if (!_disposed && identical(_process, process)) {
              _terminalParser.parse(bytes);
            }
            return bytes;
          })
          .transform(decoder)
          .listen(
            _appendOutput,
            onError: (Object error, StackTrace stackTrace) {
              if (!outputDone.isCompleted) {
                outputDone.completeError(error, stackTrace);
              }
            },
            onDone: () {
              _terminalParser.finish();
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
    final PtyWriteReceipt? receipt = _writeTracked(const <int>[0x04]);
    _observeLifecycle(switch (receipt?.result) {
      PtyWriteResult.accepted => TerminalSessionLifecycleStage.eofWriteAccepted,
      PtyWriteResult.backpressured =>
        TerminalSessionLifecycleStage.eofWriteBackpressured,
      null => TerminalSessionLifecycleStage.eofWriteIgnored,
    }, writeRequestId: receipt?.requestId);
  }

  @override
  void sendInput(Uint8List bytes) {
    if (bytes.length > TerminalInputLimits.maximumEncodedBytesPerKeyEvent) {
      throw RangeError.range(
        bytes.length,
        0,
        TerminalInputLimits.maximumEncodedBytesPerKeyEvent,
        'bytes.length',
      );
    }
    if (bytes.isNotEmpty) {
      _write(bytes);
    }
  }

  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) {
    if (_pasteFuture != null) {
      return Future<TerminalPasteTransferResult>.value(
        _pasteResult(TerminalPasteTransferDisposition.busy),
      );
    }
    if (plan.analysis.isEmpty) {
      return Future<TerminalPasteTransferResult>.value(
        _pasteResult(TerminalPasteTransferDisposition.completed),
      );
    }
    if (!_live || _disposed || _process == null) {
      return Future<TerminalPasteTransferResult>.value(
        _pasteResult(TerminalPasteTransferDisposition.unavailable),
      );
    }
    _pasteConcurrentInputNoticePublished = false;
    final Future<TerminalPasteTransferResult> future = _transportPaste(plan);
    _pasteFuture = future;
    return future;
  }

  Future<TerminalPasteTransferResult> _transportPaste(
    TerminalPastePlan plan,
  ) async {
    final int rejectionBaseline = _pasteConcurrentInputRejectionCount;
    var encodedBytes = 0;
    var completedChunks = 0;
    var backpressureCount = 0;
    var maximumQueuedBytes = 0;
    var disposition = TerminalPasteTransferDisposition.completed;
    final TerminalPasteChunkEncoder encoder = plan.encoder(
      maximumChunkBytes:
          writeCapacityBytes < TerminalPasteCodec.defaultChunkBytes
          ? writeCapacityBytes
          : TerminalPasteCodec.defaultChunkBytes,
    );
    try {
      while (true) {
        final Uint8List? chunk = encoder.nextChunk();
        if (chunk == null) break;
        while (true) {
          final PtyProcess? process = _process;
          if (!_live || _disposed || process == null) {
            disposition = TerminalPasteTransferDisposition.cancelled;
            break;
          }
          late final PtyWriteReceipt receipt;
          try {
            receipt = process.writeTracked(chunk);
          } on StateError {
            disposition = TerminalPasteTransferDisposition.cancelled;
            break;
          } on Object {
            disposition = TerminalPasteTransferDisposition.writeFailed;
            break;
          }
          if (receipt.result == PtyWriteResult.backpressured) {
            backpressureCount++;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            continue;
          }
          final int? requestId = receipt.requestId;
          if (requestId == null || requestId <= 0) {
            disposition = TerminalPasteTransferDisposition.writeFailed;
            break;
          }
          final Completer<_TerminalPasteWriteOutcome> completion =
              Completer<_TerminalPasteWriteOutcome>();
          _pasteWriteRequestId = requestId;
          _pasteWriteMaximumQueuedBytes = 0;
          _pasteWriteCompletion = completion;
          final _TerminalPasteWriteOutcome outcome = await completion.future;
          _pasteWriteRequestId = null;
          _pasteWriteCompletion = null;
          if (outcome.maximumQueuedBytes > maximumQueuedBytes) {
            maximumQueuedBytes = outcome.maximumQueuedBytes;
          }
          if (!outcome.completed) {
            disposition = _disposed || !_live
                ? TerminalPasteTransferDisposition.cancelled
                : TerminalPasteTransferDisposition.writeFailed;
            break;
          }
          encodedBytes += chunk.length;
          completedChunks++;
          break;
        }
        if (disposition != TerminalPasteTransferDisposition.completed) break;
      }
    } finally {
      _pasteWriteRequestId = null;
      _pasteWriteCompletion = null;
      _pasteWriteMaximumQueuedBytes = 0;
      _pasteFuture = null;
      _pasteConcurrentInputNoticePublished = false;
    }
    return TerminalPasteTransferResult(
      disposition: disposition,
      encodedBytes: encodedBytes,
      completedChunks: completedChunks,
      backpressureCount: backpressureCount,
      maximumQueuedBytes: maximumQueuedBytes,
      concurrentInputRejections:
          _pasteConcurrentInputRejectionCount - rejectionBaseline,
    );
  }

  static TerminalPasteTransferResult _pasteResult(
    TerminalPasteTransferDisposition disposition,
  ) => TerminalPasteTransferResult(
    disposition: disposition,
    encodedBytes: 0,
    completedChunks: 0,
    backpressureCount: 0,
    maximumQueuedBytes: 0,
    concurrentInputRejections: 0,
  );

  @override
  void resize({required int rows, required int columns}) {
    terminalScreenSet.resize(rows: rows, columns: columns);
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
  void showClipboardNotice(TerminalClipboardNotice notice) {
    if (_disposed) return;
    final String message = switch (notice.kind) {
      TerminalClipboardNoticeKind.copyUnavailable =>
        '[nothing selected to copy]',
      TerminalClipboardNoticeKind.copyTooLarge =>
        '[selection is too large to copy]',
      TerminalClipboardNoticeKind.copyFailed => '[could not copy selection]',
      TerminalClipboardNoticeKind.pasteUnavailable =>
        '[clipboard does not contain plain text]',
      TerminalClipboardNoticeKind.pasteTooLarge =>
        '[clipboard text is too large to paste]',
      TerminalClipboardNoticeKind.pasteConfirmationRequired =>
        _pasteConfirmationMessage(notice.analysis),
      TerminalClipboardNoticeKind.pasteBusy =>
        '[a paste is already in progress]',
      TerminalClipboardNoticeKind.pasteCancelled => '[paste was cancelled]',
      TerminalClipboardNoticeKind.pasteFailed => '[paste could not be sent]',
    };
    buffer.appendStatusLine(message);
    _terminalParser.parse(utf8.encode('\r\n$message\r\n'));
    _notifyChanged();
  }

  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {
    if (_disposed) return;
    final String message = switch (kind) {
      TerminalHyperlinkNoticeKind.blocked => '[link target is not allowed]',
      TerminalHyperlinkNoticeKind.unavailable => '[link could not be opened]',
    };
    buffer.appendStatusLine(message);
    _terminalParser.parse(utf8.encode('\r\n$message\r\n'));
    _notifyChanged();
  }

  static String _pasteConfirmationMessage(TerminalPasteAnalysis? analysis) {
    if (analysis == null) {
      return '[paste requires confirmation — repeat Paste within 10 seconds]';
    }
    final String breaks = analysis.logicalNewlineCount == 1
        ? '1 line break'
        : '${analysis.logicalNewlineCount} line breaks';
    return '[paste requires confirmation: ${analysis.encodedBodyBytes} bytes, '
        '$breaks — repeat Paste within 10 seconds]';
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
    _cancelPasteWrite();
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
    final bool diagnosticsCancelled = await _cancelDiagnosticSubscription();
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
          : shutdownFailed ||
                _failure != null ||
                !outputCancelled ||
                !diagnosticsCancelled
          ? TerminalSessionShutdownDisposition.failed
          : forced
          ? TerminalSessionShutdownDisposition.forced
          : TerminalSessionShutdownDisposition.clean,
      processId: processId,
      terminationObserved: terminationObserved,
      cleanupCompleted:
          outputCancelled &&
          diagnosticsCancelled &&
          terminationObserved &&
          processDisposed,
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

  Future<bool> _cancelDiagnosticSubscription() async {
    final StreamSubscription<PtyDiagnosticEvent>? subscription =
        _diagnosticSubscription;
    _diagnosticSubscription = null;
    if (subscription == null) {
      return true;
    }
    try {
      await subscription.cancel().timeout(cleanupStepTimeout);
      return true;
    } on Object catch (error) {
      _failure ??= error;
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
    if (_rejectConcurrentPasteInput()) {
      return PtyWriteResult.backpressured;
    }
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

  PtyWriteReceipt? _writeTracked(List<int> bytes) {
    if (_rejectConcurrentPasteInput()) {
      return const PtyWriteReceipt(
        result: PtyWriteResult.backpressured,
        requestId: null,
      );
    }
    final PtyProcess? process = _process;
    if (!_live || _disposed || process == null) {
      return null;
    }
    late final PtyWriteReceipt receipt;
    try {
      receipt = process.writeTracked(Uint8List.fromList(bytes));
    } on StateError {
      return null;
    }
    if (receipt.result == PtyWriteResult.backpressured) {
      ++_writeBackpressureCount;
      if (!_writeBackpressured) {
        _writeBackpressured = true;
        buffer.appendStatusLine('[terminal input is backpressured]');
        _notifyChanged();
      }
      return receipt;
    }
    _writeBackpressured = false;
    return receipt;
  }

  bool _writeTerminalReply(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > TerminalReplyEncoder.maximumReplyBytes) {
      return false;
    }
    if (_rejectConcurrentPasteInput()) return false;
    final PtyProcess? process = _process;
    if (!_live || _disposed || process == null) {
      return false;
    }
    late final PtyWriteResult result;
    try {
      result = process.write(bytes);
    } on StateError {
      return false;
    }
    if (result == PtyWriteResult.backpressured) {
      if (_replyWriteBackpressureCount < 0x7fffffff) {
        _replyWriteBackpressureCount++;
      }
      _replyWriteBackpressured = true;
      return false;
    }
    _replyWriteBackpressured = false;
    return true;
  }

  void _observeNativeDiagnostic(PtyDiagnosticEvent event) {
    _observePasteDiagnostic(event);
    final TerminalSessionNativeObserver? observer = _nativeObserver;
    if (observer == null) {
      return;
    }
    try {
      observer(
        TerminalSessionNativeObservation(
          sessionId: id,
          processId: processId,
          event: event,
        ),
      );
    } on Object {
      // Diagnostics cannot change PTY ownership or shutdown behavior.
    }
  }

  void _observePasteDiagnostic(PtyDiagnosticEvent event) {
    final Completer<_TerminalPasteWriteOutcome>? completion =
        _pasteWriteCompletion;
    if (completion == null || completion.isCompleted) return;
    if (event.requestId != _pasteWriteRequestId) return;
    final int queuedBytes = event.queuedBytes ?? 0;
    if (queuedBytes > _pasteWriteMaximumQueuedBytes) {
      _pasteWriteMaximumQueuedBytes = queuedBytes;
    }
    switch (event.stage) {
      case PtyDiagnosticStage.writeEnqueued:
      case PtyDiagnosticStage.writeDequeued:
        return;
      case PtyDiagnosticStage.writeCompleted:
        completion.complete(
          _TerminalPasteWriteOutcome(
            completed: true,
            maximumQueuedBytes: _pasteWriteMaximumQueuedBytes,
          ),
        );
      case PtyDiagnosticStage.writeError:
        completion.complete(
          _TerminalPasteWriteOutcome(
            completed: false,
            maximumQueuedBytes: _pasteWriteMaximumQueuedBytes,
          ),
        );
      case PtyDiagnosticStage.forceCloseDequeued:
      case PtyDiagnosticStage.signalDelivery:
      case PtyDiagnosticStage.waitpidResult:
      case PtyDiagnosticStage.exitPublished:
      case PtyDiagnosticStage.stateSnapshot:
      case PtyDiagnosticStage.termiosSnapshot:
      case PtyDiagnosticStage.processExitReady:
      case PtyDiagnosticStage.externalReapObserved:
        return;
    }
  }

  void _cancelPasteWrite() {
    final Completer<_TerminalPasteWriteOutcome>? completion =
        _pasteWriteCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        _TerminalPasteWriteOutcome(
          completed: false,
          maximumQueuedBytes: _pasteWriteMaximumQueuedBytes,
        ),
      );
    }
  }

  bool _rejectConcurrentPasteInput() {
    if (_pasteFuture == null) return false;
    if (_pasteConcurrentInputRejectionCount < 0x7fffffff) {
      _pasteConcurrentInputRejectionCount++;
    }
    if (!_pasteConcurrentInputNoticePublished && !_disposed) {
      _pasteConcurrentInputNoticePublished = true;
      buffer.appendStatusLine('[terminal input ignored while paste is active]');
      _notifyChanged();
    }
    return true;
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
    _cancelPasteWrite();
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

  void _observeLifecycle(
    TerminalSessionLifecycleStage stage, {
    int? writeRequestId,
  }) {
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
          writeRequestId: writeRequestId,
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

final class _TerminalPasteWriteOutcome {
  const _TerminalPasteWriteOutcome({
    required this.completed,
    this.maximumQueuedBytes = 0,
  });

  final bool completed;
  final int maximumQueuedBytes;
}
