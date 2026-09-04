import 'dart:io';

import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_session.dart';

import 'runtime_lifecycle_test.dart';

Future<void> main() async {
  _testEditing();
  _testUnicodeEditing();
  _testHistoryNavigation();
  _testTranscriptLimitAndViewport();
  _testOptions();
  await runRuntimeLifecycleTests().timeout(const Duration(seconds: 30));
  await _testCommandSession();
  await _testRealPtyCommandSession();
  stdout.writeln('dart_terminal tests passed');
}

void _testEditing() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('helo');
  buffer.moveLeft();
  buffer.insert('l');
  _expect(buffer.input == 'hello', 'insertion at cursor');
  buffer.deleteBackward();
  _expect(buffer.input == 'helo', 'backspace');
  buffer.deleteForward();
  _expect(buffer.input == 'hel', 'forward delete');
  buffer.moveToStart();
  buffer.insert('s');
  buffer.moveToEnd();
  _expect(buffer.input == 'shel', 'home/end movement');
}

void _testUnicodeEditing() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('A😀B');
  buffer.moveLeft();
  buffer.deleteBackward();
  _expect(buffer.input == 'AB', 'editing uses Unicode scalar values');
}

void _testHistoryNavigation() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('pwd');
  _expect(buffer.takeInput() == 'pwd', 'take first command');
  buffer.insert('ls -la');
  _expect(buffer.takeInput() == 'ls -la', 'take second command');
  buffer.insert('draft');
  buffer.previousHistory();
  _expect(buffer.input == 'ls -la', 'latest history item');
  buffer.previousHistory();
  _expect(buffer.input == 'pwd', 'older history item');
  buffer.nextHistory();
  _expect(buffer.input == 'ls -la', 'newer history item');
  buffer.nextHistory();
  _expect(buffer.input == 'draft', 'history restores draft');
}

void _testTranscriptLimitAndViewport() {
  final TerminalBuffer buffer = TerminalBuffer(maxTranscriptLines: 3);
  buffer.appendLines(<String>['one', 'two', 'three', 'four']);
  _expect(
    buffer.transcript.join(',') == 'two,three,four',
    'scrollback line limit',
  );
  buffer.insert('echo hi');
  final String rendered = buffer.render(prompt: '% ', rows: 2, isBusy: false);
  _expect(rendered == 'four\n% echo hi▌', 'viewport keeps newest rows');
}

void _testOptions() {
  final TerminalOptions options = _parseOptions(<String>[
    '--working-directory=/tmp',
    '--auto-close-after=3',
  ]);
  _expect(
    options.initialWorkingDirectory == '/tmp',
    'working directory option',
  );
  _expect(
    options.autoCloseAfter == const Duration(seconds: 3),
    'auto-close option',
  );
  _expect(!options.runtimeResourceStress, 'resource stress defaults off');
  _expect(
    !options.runtimeShutdownFaultInjection,
    'shutdown fault injection defaults off',
  );
  _expect(
    options.runtimeWorkerCommand.executable == '/usr/bin/true' &&
        options.runtimeWorkerCommand.arguments.isEmpty,
    'declarative bundled worker command',
  );
  final TerminalOptions faultOptions = _parseOptions(
    const <String>['--runtime-lifecycle-scenario=worker-sync-uncaught'],
    environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
  );
  _expect(
    faultOptions.runtimeLifecycleScenario ==
        RuntimeLifecycleScenario.workerSyncUncaught,
    'gated lifecycle scenario option',
  );
  final TerminalOptions resourceOptions = _parseOptions(
    const <String>['--runtime-resource-stress'],
    environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
  );
  _expect(resourceOptions.runtimeResourceStress, 'gated resource stress');
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-resource-stress',
    ], environment: const <String, String>{}),
    'resource stress gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>['--runtime-resource-stress', '--runtime-resource-stress'],
      environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
    ),
    'duplicate resource stress option',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-resource-stress',
        '--runtime-lifecycle-scenario=worker-sync-uncaught',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_RESOURCE_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'resource stress and lifecycle fault are mutually exclusive',
  );
  final TerminalOptions shutdownFaultOptions = _parseOptions(
    const <String>[
      '--runtime-shutdown-faults',
      '--runtime-lifecycle-scenario=worker-unexpected-exit',
    ],
    environment: const <String, String>{
      'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      'DT_RUNTIME_LIFECYCLE_TEST': '1',
    },
  );
  _expect(
    shutdownFaultOptions.runtimeShutdownFaultInjection,
    'gated shutdown fault injection',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ],
      environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
    ),
    'shutdown fault gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>['--runtime-shutdown-faults'],
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      },
    ),
    'shutdown faults require the worker crash scenario',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shutdown-faults',
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'duplicate shutdown fault option',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-lifecycle-scenario=worker-sync-uncaught',
    ], environment: const <String, String>{}),
    'lifecycle scenario gate',
  );
  _expectThrows(
    () => _parseOptions(const <String>['--unknown']),
    'unknown option',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-worker-executable=relative/dart',
    ]),
    'internal worker configuration is not an application option',
  );
}

TerminalOptions _parseOptions(
  List<String> arguments, {
  Map<String, String>? environment,
}) => TerminalOptions.parse(
  arguments,
  environment: environment,
  runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
    executable: '/usr/bin/true',
  ),
);

Future<void> _testCommandSession() async {
  var changeCount = 0;
  var exitRequested = false;
  final FakePtyBackend ptyBackend = FakePtyBackend(autoExitOnClose: false);
  final TerminalSession session = TerminalSession(
    ptyBackend: ptyBackend,
    initialWorkingDirectory: Directory.systemTemp.path,
    onChanged: () {
      ++changeCount;
    },
    onExitRequested: () {
      exitRequested = true;
    },
  );
  session.insertText("printf 'shell-ok\\n'");
  final Future<void> submitted = session.submit();
  while (ptyBackend.processes.isEmpty) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration.zero);
  final FakePtyProcess process = ptyBackend.processes.single;
  session.resize(rows: 40, columns: 120);
  process.emitOutput('shell-ok\r\n'.codeUnits);
  process.finish(exitCode: 0);
  await submitted;
  _expect(
    session.buffer.transcript.contains('shell-ok'),
    'zsh output reaches the terminal buffer',
  );
  _expect(
    ptyBackend.commands.single.executable == '/bin/zsh' &&
        ptyBackend.commands.single.arguments.first == '-lc',
    'external command uses the PTY capability',
  );
  _expect(
    process.sizes.last.rows == 40 && process.sizes.last.columns == 120,
    'active PTY tracks terminal size',
  );
  session.insertText('help');
  await session.submit();
  _expect(
    session.buffer.transcript.contains('Starter commands:'),
    'built-in help command',
  );
  session.insertText('exit');
  await session.submit();
  _expect(exitRequested, 'exit callback');
  _expect(changeCount > 0, 'session emits view updates');
  await session.dispose();
}

Future<void> _testRealPtyCommandSession() async {
  final TerminalSession session = TerminalSession(
    initialWorkingDirectory: Directory.systemTemp.path,
    environment: const <String, String>{'PATH': '/usr/bin:/bin'},
    onChanged: () {},
    onExitRequested: () {},
  );
  session.insertText("printf '__DART_TERMINAL_PTY__\\n'");
  await session.submit().timeout(const Duration(seconds: 5));
  _expect(
    session.buffer.transcript.contains('__DART_TERMINAL_PTY__'),
    'real PTY output reaches the application session adapter',
  );
  await session.dispose();
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}

void _expectThrows(void Function() callback, String description) {
  try {
    callback();
  } on FormatException {
    return;
  }
  throw StateError('Expected FormatException: $description');
}
