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
  await _testPaneIdentityOwnershipAndClosePolicy();
  await runRuntimeLifecycleTests().timeout(const Duration(seconds: 30));
  await _testCommandSession();
  await _testRealPtyCommandSession();
  stdout.writeln('dart_terminal tests passed');
}

Future<void> _testPaneIdentityOwnershipAndClosePolicy() async {
  final TerminalPaneOwner owner = TerminalPaneOwner(initialPaneId: 40);
  final List<_FakePaneSession> sessions = <_FakePaneSession>[];
  var changed = 0;
  var exitRequests = 0;
  TerminalPane createPane() => owner.createPane(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          final _FakePaneSession session = _FakePaneSession(
            id: id,
            onChanged: onChanged,
            onTerminated: onTerminated,
          );
          sessions.add(session);
          return session;
        },
    onChanged: () {
      ++changed;
    },
    onExitRequested: () {
      ++exitRequests;
    },
  );

  final TerminalPane first = createPane();
  final TerminalPane second = createPane();
  _expect(first.id == const PaneId(41), 'first monotonic pane ID');
  _expect(second.id == const PaneId(42), 'second monotonic pane ID');
  _expect(first.id != second.id, 'pane IDs are unique');
  _expect(
    first.sessionId ==
        const TerminalSessionId(paneId: PaneId(41), generation: 1),
    'session identity binds pane and generation',
  );
  _expect(owner.livePaneCount == 2, 'owner retains created panes');

  final Future<void> firstStart = first.start();
  _expect(identical(firstStart, first.start()), 'pane start is idempotent');
  await firstStart;
  _expect(first.state == TerminalPaneState.running, 'pane reaches running');
  _expect(
    sessions.first.startCount == 1,
    'owner starts one session generation',
  );

  _expect(
    first.requestClose() == TerminalPaneCloseDecision.confirmationRequired &&
        first.state == TerminalPaneState.confirmationPending &&
        sessions.first.confirmationCount == 1,
    'first live close requires confirmation',
  );
  first.insertText('x');
  _expect(
    first.state == TerminalPaneState.running &&
        sessions.first.insertedText.single == 'x',
    'terminal interaction cancels close confirmation',
  );
  _expect(
    first.requestClose() == TerminalPaneCloseDecision.confirmationRequired,
    'close after interaction requires confirmation again',
  );
  _expect(
    first.requestClose() == TerminalPaneCloseDecision.allow &&
        first.state == TerminalPaneState.closing,
    'second consecutive close is allowed',
  );
  await owner.disposePane(first);
  await owner
      .disposePane(first)
      .then<void>(
        (_) => throw StateError('removed pane disposal unexpectedly succeeded'),
        onError: (Object error) {
          _expect(error is StateError, 'removed pane is rejected by owner');
        },
      );
  _expect(
    sessions.first.disposeCount == 1 &&
        first.state == TerminalPaneState.closed &&
        owner.livePaneCount == 1,
    'pane disposal is owned and idempotent',
  );

  await second.start();
  sessions[1].finish();
  _expect(
    second.state == TerminalPaneState.exited && exitRequests == 1,
    'natural session exit updates pane before requesting window close',
  );
  _expect(
    second.requestClose() == TerminalPaneCloseDecision.allow,
    'exited pane closes without confirmation',
  );

  final TerminalPane failed = createPane();
  sessions[2].failStart = true;
  try {
    await failed.start();
    throw StateError('failing pane session unexpectedly started');
  } on StateError catch (error) {
    _expect(
      error.message == 'requested fake start failure',
      'start failure remains observable',
    );
  }
  _expect(
    failed.state == TerminalPaneState.failed &&
        failed.requestClose() == TerminalPaneCloseDecision.allow,
    'failed pane closes without confirmation',
  );
  await owner.dispose();
  await owner.dispose();
  _expect(
    owner.livePaneCount == 0 &&
        sessions[1].disposeCount == 1 &&
        sessions[2].disposeCount == 1,
    'owner teardown reaches zero panes exactly once',
  );
  _expect(changed > 0, 'pane lifecycle emits view changes');
  _expectThrows(
    createPane,
    'disposed owner refuses new pane publication',
    expectedType: StateError,
  );
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

void _expectThrows(
  void Function() callback,
  String description, {
  Type expectedType = FormatException,
}) {
  try {
    callback();
  } on Object catch (error) {
    if (error.runtimeType == expectedType) {
      return;
    }
    throw StateError(
      'Expected $expectedType for $description, got ${error.runtimeType}',
    );
  }
  throw StateError('Expected $expectedType: $description');
}

final class _FakePaneSession implements TerminalPaneSession {
  _FakePaneSession({
    required this.id,
    required void Function() onChanged,
    required void Function() onTerminated,
  }) : _onChanged = onChanged,
       _onTerminated = onTerminated;

  @override
  final TerminalSessionId id;
  final void Function() _onChanged;
  final void Function() _onTerminated;
  final List<String> insertedText = <String>[];

  var startCount = 0;
  var disposeCount = 0;
  var confirmationCount = 0;
  var failStart = false;
  var _live = false;

  @override
  bool get isLive => _live;

  @override
  Future<void> start() async {
    ++startCount;
    if (failStart) {
      throw StateError('requested fake start failure');
    }
    _live = true;
  }

  void finish() {
    _live = false;
    _onTerminated();
  }

  @override
  String render() => '';

  @override
  void insertText(String value) {
    insertedText.add(value);
    _onChanged();
  }

  @override
  void deleteBackward() {}

  @override
  void deleteForward() {}

  @override
  void moveLeft() {}

  @override
  void moveRight() {}

  @override
  void moveToStart() {}

  @override
  void moveToEnd() {}

  @override
  void previousHistory() {}

  @override
  void nextHistory() {}

  @override
  Future<void> submit() async {}

  @override
  void interrupt() {}

  @override
  void suspend() {}

  @override
  void quitForegroundProcess() {}

  @override
  void sendEndOfFile() {}

  @override
  void resize({required int rows, required int columns}) {}

  @override
  void showCloseConfirmation() {
    ++confirmationCount;
    _onChanged();
  }

  @override
  Future<void> dispose() async {
    ++disposeCount;
    _live = false;
  }
}
