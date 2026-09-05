import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_session.dart';

import 'runtime_lifecycle_test.dart';

@Native<Uint64 Function()>(
  symbol: 'dpty_debug_live_session_count',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _livePtySessionCount();

Future<void> main() async {
  _testEditing();
  _testUnicodeEditing();
  _testHistoryNavigation();
  _testTranscriptLimitAndViewport();
  _testOptions();
  await _testPaneIdentityOwnershipAndClosePolicy();
  await runRuntimeLifecycleTests().timeout(const Duration(seconds: 30));
  await _testPersistentCommandSession();
  await _testRealPersistentPtySession();
  await _testRepeatedControlDNaturalExit().timeout(const Duration(seconds: 45));
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

  final TerminalBuffer output = TerminalBuffer(maxTranscriptLines: 3);
  output.appendOutput('one\r\ntw');
  output.appendOutput('o\b');
  output.appendOutput('o\rreplace\npartial');
  _expect(
    output.outputText == 'one\nreplace\npartial',
    'PTY projection preserves split lines and applies CR/backspace',
  );
  _expect(
    output.renderOutput(rows: 2) == 'replace\npartial',
    'PTY projection keeps the newest visible rows',
  );
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

Future<void> _testPersistentCommandSession() async {
  var changeCount = 0;
  var terminationCount = 0;
  final FakePtyBackend ptyBackend = FakePtyBackend(autoExitOnClose: false);
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(7), generation: 3),
    ptyBackend: ptyBackend,
    initialWorkingDirectory: Directory.systemTemp.path,
    onChanged: () {
      ++changeCount;
    },
    onTerminated: () {
      ++terminationCount;
    },
  );
  final Future<void> start = session.start();
  _expect(identical(start, session.start()), 'session start is idempotent');
  await start;
  _expect(session.isLive, 'persistent shell is live after start');
  _expect(
    ptyBackend.commands.length == 1 &&
        ptyBackend.commands.single.executable == '/bin/zsh' &&
        ptyBackend.commands.single.arguments.isEmpty &&
        ptyBackend.commands.single.loginShell,
    'one login shell is created for the session generation',
  );
  final FakePtyProcess process = ptyBackend.processes.single;
  final int processId = session.processId!;

  session.insertText("printf 'shell-ok\\n'");
  await session.submit();
  session.insertText("printf 'second-command\\n'");
  await session.submit();
  session.resize(rows: 40, columns: 120);
  session.deleteBackward();
  session.deleteForward();
  session.moveLeft();
  session.moveRight();
  session.previousHistory();
  session.nextHistory();
  session.moveToStart();
  session.moveToEnd();
  session.sendEndOfFile();
  session.interrupt();
  session.suspend();
  session.quitForegroundProcess();
  process.emitOutput(<int>[0xe2]);
  process.emitOutput(<int>[0x82, 0xac, 0x0d, 0x0a]);
  session.showCloseConfirmation();
  _expect(
    ptyBackend.processes.length == 1 && session.processId == processId,
    'multiple commands retain the same PTY process',
  );
  _expect(
    utf8.decode(process.writes[0]) == "printf 'shell-ok\\n'" &&
        process.writes[1].single == 0x0d &&
        utf8.decode(process.writes[2]) == "printf 'second-command\\n'" &&
        process.writes[3].single == 0x0d,
    'commands are written to the persistent shell instead of spawning',
  );
  _expect(
    process.sizes.last.rows == 40 && process.sizes.last.columns == 120,
    'active PTY tracks terminal size',
  );
  _expect(
    process.signals.join(',') ==
        <PtySignal>[
          PtySignal.interrupt,
          PtySignal.suspend,
          PtySignal.quit,
        ].join(','),
    'foreground control signals use the PTY process group',
  );
  _expect(
    session.buffer.outputText.contains('€') &&
        session.buffer.outputText.contains('repeat Close or Quit'),
    'split UTF-8 output and close notice reach the projection',
  );
  process.finish(exitCode: 0);
  await session.waitForTermination();
  _expect(!session.isLive && terminationCount == 1, 'shell exit is observed');
  _expect(changeCount > 0, 'session emits view updates');
  await session.dispose();
  await session.dispose();

  final FakePtyBackend boundedBackend = FakePtyBackend();
  final TerminalSession bounded = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(9), generation: 1),
    ptyBackend: boundedBackend,
    writeCapacityBytes: 2,
    onChanged: () {},
    onTerminated: () {},
  );
  await bounded.start();
  bounded.insertText('three bytes');
  _expect(
    bounded.writeBackpressureCount == 1 &&
        bounded.buffer.outputText.contains('input is backpressured') &&
        boundedBackend.processes.single.writes.isEmpty,
    'rejected input is surfaced without an unbounded retry queue',
  );
  bounded.insertText('x');
  _expect(
    utf8.decode(boundedBackend.processes.single.writes.single) == 'x',
    'session accepts later input after a bounded rejection',
  );
  await bounded.dispose();
  await bounded.dispose();
  _expect(
    boundedBackend.processes.single.closeGracePeriods.length == 1,
    'active persistent process is closed exactly once',
  );
}

Future<void> _testRealPersistentPtySession() async {
  var terminated = false;
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(8), generation: 1),
    initialWorkingDirectory: Directory.systemTemp.path,
    environment: <String, String>{
      'PATH': '/usr/bin:/bin',
      'HOME': Directory.systemTemp.path,
      'TERM': 'dumb',
      'LC_ALL': 'C',
    },
    shellArguments: const <String>['-f'],
    onChanged: () {},
    onTerminated: () {
      terminated = true;
    },
  );
  session.resize(rows: 37, columns: 111);
  await session.start().timeout(const Duration(seconds: 5));
  final int processId = session.processId!;
  session.insertText("stty -echo; printf '__SHELL_READY__\\n'");
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => _occurrences(output, '__SHELL_READY__') >= 2,
    'interactive shell startup',
  );
  session.insertText(
    "printf '__DART_TERMINAL_PTY__\\n'; tty; stty size; "
    "printf '__FIRST_COMMAND_DONE__\\n'",
  );
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => output.contains('__FIRST_COMMAND_DONE__'),
    'first persistent-shell command',
  );
  session.insertText("sleep 5 & jobs; printf '__JOB_READY__\\n'");
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => output.contains('__JOB_READY__'),
    'background job listing',
  );
  session.insertText('fg');
  await session.submit();
  await Future<void>.delayed(const Duration(milliseconds: 150));
  session.interrupt();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  session.insertText("printf '__AFTER_INTERRUPT__\\n'; exit");
  await session.submit();
  await session.waitForTermination().timeout(const Duration(seconds: 8));
  final String output = session.buffer.outputText;
  _expect(
    output.contains('__DART_TERMINAL_PTY__') &&
        output.contains('__FIRST_COMMAND_DONE__') &&
        output.contains('__JOB_READY__') &&
        output.toLowerCase().contains('running') &&
        output.contains('__AFTER_INTERRUPT__'),
    'multiple real commands use the persistent session',
  );
  _expect(
    output.contains('/dev/tty') && output.contains('37 111'),
    'real shell has a PTY and observes the initial window size',
  );
  _expect(
    session.processId == processId && session.exit?.exitCode == 0 && terminated,
    'real login shell exits and is reaped once',
  );
  await session.dispose();
}

Future<void> _testRepeatedControlDNaturalExit() async {
  const int repetitions = 24;
  _expect(_livePtySessionCount() == 0, 'Control-D test starts without PTYs');
  for (var iteration = 0; iteration < repetitions; ++iteration) {
    var terminationCount = 0;
    final TerminalSession session = TerminalSession(
      id: TerminalSessionId(paneId: PaneId(1000 + iteration), generation: 1),
      initialWorkingDirectory: Directory.systemTemp.path,
      environment: <String, String>{
        'PATH': '/usr/bin:/bin',
        'HOME': Directory.systemTemp.path,
        'TERM': 'dumb',
        'LC_ALL': 'C',
        'PS1': '__CTRL_D_PROMPT_${iteration}__ ',
        'RPS1': '',
      },
      shellArguments: const <String>['-f'],
      onChanged: () {},
      onTerminated: () {
        ++terminationCount;
      },
    );
    await session.start().timeout(const Duration(seconds: 3));
    session.insertText(
      "stty -echo; unsetopt ignoreeof; printf '__CTRL_D_READY_${iteration}__\\n'",
    );
    await session.submit();
    await _waitForTerminalOutput(
      session,
      (String output) =>
          _occurrences(output, '__CTRL_D_READY_${iteration}__') >= 2,
      'Control-D ready marker for iteration $iteration',
    );
    session.sendEndOfFile();
    await session.waitForTermination().timeout(const Duration(seconds: 3));
    _expect(
      session.exit?.exitCode == 0 &&
          session.exit?.signal == null &&
          terminationCount == 1,
      'Control-D iteration $iteration exits and notifies exactly once',
    );
    await session.dispose().timeout(const Duration(seconds: 1));
    _expect(
      _livePtySessionCount() == 0,
      'Control-D iteration $iteration reaps and destroys its native session',
    );
  }
}

Future<void> _waitForTerminalOutput(
  TerminalSession session,
  bool Function(String output) predicate,
  String description,
) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 3)) {
    if (predicate(session.buffer.outputText)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for $description: ${session.buffer.outputText}',
  );
}

int _occurrences(String value, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(value).length;

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
