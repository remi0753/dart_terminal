import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
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
  final TerminalOptions options = TerminalOptions.parse(
    _workerOptions(<String>[
      '--working-directory=/tmp',
      '--auto-close-after=3',
    ]),
  );
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
        options.runtimeWorkerCommand.arguments.single ==
            '/tmp/runtime_worker.dill',
    'native-injected runtime worker command',
  );
  final TerminalOptions selfContained = TerminalOptions.parse(const <String>[
    '--runtime-worker-executable=/usr/bin/true',
    '--runtime-worker-mode=self-contained',
  ]);
  _expect(
    selfContained.runtimeWorkerCommand.executable == '/usr/bin/true' &&
        selfContained.runtimeWorkerCommand.arguments.isEmpty,
    'native-injected self-contained runtime worker command',
  );
  final TerminalOptions faultOptions = TerminalOptions.parse(
    _workerOptions(<String>[
      '--runtime-lifecycle-scenario=worker-sync-uncaught',
    ]),
    environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
  );
  _expect(
    faultOptions.runtimeLifecycleScenario ==
        RuntimeLifecycleScenario.workerSyncUncaught,
    'gated lifecycle scenario option',
  );
  final TerminalOptions resourceOptions = TerminalOptions.parse(
    _workerOptions(<String>['--runtime-resource-stress']),
    environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
  );
  _expect(resourceOptions.runtimeResourceStress, 'gated resource stress');
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>['--runtime-resource-stress']),
      environment: const <String, String>{},
    ),
    'resource stress gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>[
        '--runtime-resource-stress',
        '--runtime-resource-stress',
      ]),
      environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
    ),
    'duplicate resource stress option',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>[
        '--runtime-resource-stress',
        '--runtime-lifecycle-scenario=worker-sync-uncaught',
      ]),
      environment: const <String, String>{
        'DT_RUNTIME_RESOURCE_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'resource stress and lifecycle fault are mutually exclusive',
  );
  final TerminalOptions shutdownFaultOptions = TerminalOptions.parse(
    _workerOptions(<String>[
      '--runtime-shutdown-faults',
      '--runtime-lifecycle-scenario=worker-unexpected-exit',
    ]),
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
    () => TerminalOptions.parse(
      _workerOptions(<String>[
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ]),
      environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
    ),
    'shutdown fault gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>['--runtime-shutdown-faults']),
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      },
    ),
    'shutdown faults require the worker crash scenario',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>[
        '--runtime-shutdown-faults',
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ]),
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'duplicate shutdown fault option',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      _workerOptions(<String>[
        '--runtime-lifecycle-scenario=worker-sync-uncaught',
      ]),
      environment: const <String, String>{},
    ),
    'lifecycle scenario gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(_workerOptions(<String>['--unknown'])),
    'unknown option',
  );
  _expectThrows(
    () => TerminalOptions.parse(const <String>[]),
    'missing internal worker configuration',
  );
  _expectThrows(
    () => TerminalOptions.parse(<String>[
      ..._workerOptions(const <String>[]),
      '--runtime-worker-executable=/usr/bin/false',
    ]),
    'application argument cannot replace the worker executable',
  );
  _expectThrows(
    () => TerminalOptions.parse(const <String>[
      '--runtime-worker-executable=/usr/bin/true',
      '--runtime-worker-mode=kernel',
    ]),
    'kernel worker requires a Kernel path',
  );
  _expectThrows(
    () => TerminalOptions.parse(const <String>[
      '--runtime-worker-executable=/usr/bin/true',
      '--runtime-worker-mode=self-contained',
      '--runtime-worker-kernel=/tmp/runtime_worker.dill',
    ]),
    'self-contained worker rejects a Kernel path',
  );
  _expectThrows(
    () => TerminalOptions.parse(<String>[
      '--runtime-worker-executable=relative/dart',
      '--runtime-worker-mode=kernel',
      '--runtime-worker-kernel=/tmp/runtime_worker.dill',
    ]),
    'worker executable must be absolute',
  );
}

List<String> _workerOptions(List<String> applicationOptions) => <String>[
  '--runtime-worker-executable=/usr/bin/true',
  '--runtime-worker-mode=kernel',
  '--runtime-worker-kernel=/tmp/runtime_worker.dill',
  ...applicationOptions,
];

Future<void> _testCommandSession() async {
  var changeCount = 0;
  var exitRequested = false;
  final TerminalSession session = TerminalSession(
    initialWorkingDirectory: Directory.systemTemp.path,
    onChanged: () {
      ++changeCount;
    },
    onExitRequested: () {
      exitRequested = true;
    },
  );
  session.insertText("printf 'shell-ok\\n'");
  await session.submit();
  _expect(
    session.buffer.transcript.contains('shell-ok'),
    'zsh output reaches the terminal buffer',
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
