import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'terminal_buffer.dart';

typedef TerminalChanged = void Function();
typedef TerminalExitRequested = void Function();

/// A small command-console backend that can later be replaced by a PTY backend.
final class TerminalSession {
  TerminalSession({
    required TerminalChanged onChanged,
    required TerminalExitRequested onExitRequested,
    String? initialWorkingDirectory,
    Map<String, String>? environment,
  }) : _onChanged = onChanged,
       _onExitRequested = onExitRequested,
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _workingDirectory = Directory(
         initialWorkingDirectory ?? Directory.current.path,
       ).absolute.path {
    buffer.appendLines(<String>[
      'Dart Terminal',
      '─────────────',
      'dart_appkit command-console starter',
      'Type "help" for starter commands.',
      '',
    ]);
  }

  final TerminalChanged _onChanged;
  final TerminalExitRequested _onExitRequested;
  final Map<String, String> _environment;

  final TerminalBuffer buffer = TerminalBuffer();
  String _workingDirectory;
  Process? _process;
  Future<void>? _runningCommand;
  bool _busy = false;
  bool _disposed = false;
  bool _interrupted = false;

  int viewportRows = 23;

  bool get isBusy => _busy;
  String get workingDirectory => _workingDirectory;

  String get prompt => '${_shortWorkingDirectory()} % ';

  String render() =>
      buffer.render(prompt: prompt, rows: viewportRows, isBusy: _busy);

  void insertText(String value) {
    if (_cannotEdit) {
      return;
    }
    buffer.insert(value);
    _notifyChanged();
  }

  void deleteBackward() {
    if (_cannotEdit) {
      return;
    }
    buffer.deleteBackward();
    _notifyChanged();
  }

  void deleteForward() {
    if (_cannotEdit) {
      return;
    }
    buffer.deleteForward();
    _notifyChanged();
  }

  void moveLeft() {
    if (_cannotEdit) {
      return;
    }
    buffer.moveLeft();
    _notifyChanged();
  }

  void moveRight() {
    if (_cannotEdit) {
      return;
    }
    buffer.moveRight();
    _notifyChanged();
  }

  void moveToStart() {
    if (_cannotEdit) {
      return;
    }
    buffer.moveToStart();
    _notifyChanged();
  }

  void moveToEnd() {
    if (_cannotEdit) {
      return;
    }
    buffer.moveToEnd();
    _notifyChanged();
  }

  void previousHistory() {
    if (_cannotEdit) {
      return;
    }
    buffer.previousHistory();
    _notifyChanged();
  }

  void nextHistory() {
    if (_cannotEdit) {
      return;
    }
    buffer.nextHistory();
    _notifyChanged();
  }

  Future<void> submit() async {
    if (_cannotEdit) {
      return;
    }
    final String command = buffer.takeInput();
    buffer.appendLine('$prompt$command');
    if (command.trim().isEmpty) {
      _notifyChanged();
      return;
    }

    _busy = true;
    _interrupted = false;
    _notifyChanged();
    final Future<void> operation = _execute(command.trim());
    _runningCommand = operation;
    try {
      await operation;
    } on Object catch (error) {
      if (!_disposed) {
        buffer.appendLine('Command failed: $error');
      }
    } finally {
      _process = null;
      _runningCommand = null;
      _busy = false;
      _notifyChanged();
    }
  }

  void interrupt() {
    if (!_busy || _disposed) {
      return;
    }
    _interrupted = true;
    buffer.appendLine('^C');
    _process?.kill(ProcessSignal.sigint);
    _notifyChanged();
  }

  void requestExitIfIdle() {
    if (!_busy && !_disposed) {
      _onExitRequested();
    }
  }

  void refresh() => _notifyChanged();

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final Process? process = _process;
    process?.kill(ProcessSignal.sigterm);
    final Future<void>? runningCommand = _runningCommand;
    if (runningCommand == null) {
      return;
    }
    try {
      await runningCommand.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
        },
      );
    } on Object {
      process?.kill(ProcessSignal.sigkill);
    }
  }

  bool get _cannotEdit => _busy || _disposed;

  Future<void> _execute(String command) async {
    if (command == 'clear') {
      buffer.clearTranscript();
      return;
    }
    if (command == 'exit') {
      _onExitRequested();
      return;
    }
    if (command == 'help') {
      buffer.appendLines(<String>[
        'Starter commands:',
        '  help      show this message',
        '  clear     clear visible scrollback',
        '  cd PATH   change the command working directory',
        '  exit      close the window',
        '',
        'Other input is executed by /bin/zsh -lc.',
      ]);
      return;
    }
    if (command == 'cd' || command.startsWith('cd ')) {
      _changeDirectory(command.length == 2 ? '' : command.substring(2).trim());
      return;
    }
    await _runExternalCommand(command);
  }

  void _changeDirectory(String requestedPath) {
    String path = requestedPath;
    final String? home = _environment['HOME'];
    if (path.isEmpty || path == '~') {
      path = home ?? _workingDirectory;
    } else if (path.startsWith('~/') && home != null) {
      path = '$home/${path.substring(2)}';
    }
    if (path.length >= 2 &&
        ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'")))) {
      path = path.substring(1, path.length - 1);
    }
    final Directory directory = Directory(
      path.startsWith('/') ? path : '$_workingDirectory/$path',
    ).absolute;
    if (!directory.existsSync()) {
      buffer.appendLine('cd: no such directory: $requestedPath');
      return;
    }
    _workingDirectory = directory.path;
  }

  Future<void> _runExternalCommand(String command) async {
    try {
      final Process process = await Process.start(
        '/bin/zsh',
        <String>['-lc', command],
        workingDirectory: _workingDirectory,
        environment: <String, String>{..._environment, 'TERM': 'dumb'},
        includeParentEnvironment: false,
      );
      _process = process;
      if (_disposed) {
        process.kill(ProcessSignal.sigterm);
      } else if (_interrupted) {
        process.kill(ProcessSignal.sigint);
      }
      await process.stdin.close();

      const Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
      final Future<void> stdoutDone = process.stdout
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(_appendProcessLine);
      final Future<void> stderrDone = process.stderr
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(_appendProcessLine);
      final int status = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (status != 0 && !_interrupted && !_disposed) {
        buffer.appendLine('[process exited with status $status]');
      }
    } on ProcessException catch (error) {
      if (!_disposed) {
        buffer.appendLine('Could not start zsh: ${error.message}');
      }
    } on FileSystemException catch (error) {
      if (!_disposed) {
        buffer.appendLine('File system error: ${error.message}');
      }
    }
  }

  void _appendProcessLine(String line) {
    if (_disposed) {
      return;
    }
    buffer.appendLine(line);
    _notifyChanged();
  }

  String _shortWorkingDirectory() {
    final String? home = _environment['HOME'];
    if (home != null) {
      if (_workingDirectory == home) {
        return '~';
      }
      if (_workingDirectory.startsWith('$home/')) {
        return '~${_workingDirectory.substring(home.length)}';
      }
    }
    return _workingDirectory;
  }

  void _notifyChanged() {
    if (!_disposed) {
      _onChanged();
    }
  }
}
