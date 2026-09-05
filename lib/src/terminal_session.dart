import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';

import 'terminal_buffer.dart';
import 'terminal_pane.dart';

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
  }) : _onChanged = onChanged,
       _onTerminated = onTerminated,
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
  }

  @override
  final TerminalSessionId id;
  final void Function() _onChanged;
  final void Function() _onTerminated;
  final PtyBackend _ptyBackend;
  final Map<String, String> _environment;
  final String shellExecutable;
  final List<String> shellArguments;
  final int writeCapacityBytes;

  final TerminalBuffer buffer = TerminalBuffer();
  final Completer<void> _terminated = Completer<void>();
  final String _workingDirectory;

  PtyProcess? _process;
  StreamSubscription<String>? _outputSubscription;
  Future<void>? _startFuture;
  Future<void>? _terminationFuture;
  Future<void>? _disposeFuture;
  PtyExit? _exit;
  Object? _failure;
  var _live = false;
  var _disposed = false;
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

  Future<void> waitForTermination() => _terminated.future;

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_disposed) {
      throw StateError('terminal session $id is disposed');
    }
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
      final Completer<void> outputDone = Completer<void>();
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
            onDone: outputDone.complete,
            cancelOnError: false,
          );
      _terminationFuture = _observeTermination(process, outputDone.future);
      unawaited(_terminationFuture);
      _notifyChanged();
    } on Object catch (error) {
      _failure = error;
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
      await outputDone;
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
  void sendEndOfFile() => _write(const <int>[0x04]);

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
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final PtyProcess? process = _process;
    if (process == null) {
      _completeTermination(notifyOwner: false);
      return;
    }
    try {
      process.close();
    } on StateError {
      // The process exited between the live-state check and close.
    }
    try {
      await (_terminationFuture ?? process.exit).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _trySendSignal(process, PtySignal.kill);
        },
      );
    } on Object {
      if (_live) {
        _trySendSignal(process, PtySignal.kill);
      }
    } finally {
      await _outputSubscription?.cancel();
      await process.dispose();
      _live = false;
      _completeTermination(notifyOwner: false);
    }
  }

  void _write(List<int> bytes) {
    final PtyProcess? process = _process;
    if (!_live || _disposed || process == null) {
      return;
    }
    late final PtyWriteResult result;
    try {
      result = process.write(Uint8List.fromList(bytes));
    } on StateError {
      return;
    }
    if (result == PtyWriteResult.backpressured) {
      ++_writeBackpressureCount;
      if (!_writeBackpressured) {
        _writeBackpressured = true;
        buffer.appendStatusLine('[terminal input is backpressured]');
        _notifyChanged();
      }
      return;
    }
    _writeBackpressured = false;
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
    }
    if (notifyOwner && !_terminationNotified) {
      _terminationNotified = true;
      _onTerminated();
    }
  }

  void _notifyChanged() {
    if (!_disposed) {
      _onChanged();
    }
  }
}
