import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalDesktopSignalProjectionTests();

Future<void> runTerminalDesktopSignalProjectionTests() async {
  _testDeterministicAdmissionAndCoalescing();
  _testPaneProgressSemanticAndResetLifecycle();
  _testProjectionFailureAndConfigurationBounds();
  _testLiveDisableAndAsynchronousDeliveryFailure();
  await _testTerminalSessionOutputAndCloseIntegration();
}

void _testLiveDisableAndAsynchronousDeliveryFailure() {
  final _FakeNativePort port = _FakeNativePort();
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(
        nativePort: port,
        notificationBudget: 8,
        notificationsEnabled: false,
      );
  const TerminalSessionId id = TerminalSessionId(
    paneId: PaneId(25),
    generation: 2,
  );
  final _Harness harness = _Harness();
  final TerminalDesktopSignalSessionProjection projection = coordinator
      .registerSession(id);
  harness.parse(_osc(99, 'i=job;disabled'));
  projection.synchronize(harness.screens);
  coordinator.setNotificationsEnabled(true);
  harness.parse(_osc(99, 'i=job;enabled'));
  projection.synchronize(harness.screens);
  final String identifier = port.posts.single.identifier;
  coordinator.reportNotificationDeliveryFailure(identifier);
  _expect(
    port.posts.single.sessionId == id &&
        coordinator.snapshotFor(id)!.liveNotificationCount == 0 &&
        coordinator.metrics.projectionFailureCount == 1,
    'live enable or asynchronous delivery failure state was not exact',
  );
  harness.parse(_osc(99, 'i=job;retry'));
  projection.synchronize(harness.screens);
  coordinator.setNotificationsEnabled(false);
  _expect(
    port.posts.length == 2 &&
        port.removed.single == port.posts.last.identifier &&
        coordinator.snapshotFor(id)!.liveNotificationCount == 0,
    'live disable did not cancel the currently tracked native identity',
  );
  coordinator.dispose();
}

void _testDeterministicAdmissionAndCoalescing() {
  final _FakeNativePort port = _FakeNativePort();
  final _FakeClock clock = _FakeClock();
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(
        nativePort: port,
        monotonicMicros: clock.call,
      );
  const TerminalSessionId firstId = TerminalSessionId(
    paneId: PaneId(1),
    generation: 2,
  );
  const TerminalSessionId secondId = TerminalSessionId(
    paneId: PaneId(2),
    generation: 1,
  );
  final _Harness first = _Harness();
  final _Harness second = _Harness();
  final TerminalDesktopSignalSessionProjection firstProjection = coordinator
      .registerSession(firstId);
  final TerminalDesktopSignalSessionProjection secondProjection = coordinator
      .registerSession(secondId);
  coordinator.focusSession(firstId);

  first.parse('${_osc(99, 'i=job;first')}${_osc(99, 'i=job;second')}');
  firstProjection.synchronize(first.screens);
  _expect(
    port.posts.length == 1 &&
        port.posts.single.sessionId == firstId &&
        port.posts.single.title == 'second' &&
        !port.posts.single.identifier.contains('job') &&
        coordinator.metrics.coalescedNotificationCount == 1,
    'one parser turn keeps only the last logical-ID notification and uses an '
    'internal native identity',
  );

  first.parse(_osc(99, 'i=job;second'));
  firstProjection.synchronize(first.screens);
  first.parse('${_osc(9, 'legacy-1')}${_osc(9, 'legacy-2')}');
  firstProjection.synchronize(first.screens);
  first.parse(_osc(9, 'rate-limited'));
  firstProjection.synchronize(first.screens);
  _expect(
    port.posts.length == 3 &&
        port.posts[1].title == 'Dart Terminal' &&
        coordinator.metrics.admittedNotificationCount == 3 &&
        coordinator.metrics.projectedNotificationCount == 3 &&
        coordinator.metrics.coalescedNotificationCount == 2 &&
        coordinator.metrics.rateLimitedNotificationCount == 1,
    'duplicate suppression and the application-global sliding budget are exact',
  );

  clock.advance(const Duration(seconds: 10));
  first.parse(_osc(9, 'after-window'));
  firstProjection.synchronize(first.screens);
  coordinator.setApplicationActive(true);
  first.parse(_osc(9, 'focused-and-active'));
  firstProjection.synchronize(first.screens);
  second.parse(_osc(9, 'background-pane'));
  secondProjection.synchronize(second.screens);
  _expect(
    port.posts.length == 5 &&
        port.posts.last.body == 'background-pane' &&
        coordinator.metrics.focusSuppressedNotificationCount == 1,
    'active focused output is suppressed while an unfocused pane remains '
    'eligible for the same global budget',
  );
  coordinator.dispose();
}

void _testPaneProgressSemanticAndResetLifecycle() {
  final _FakeNativePort port = _FakeNativePort();
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(
        nativePort: port,
        notificationBudget: 8,
        maximumLiveNotificationsPerSession: 2,
      );
  const TerminalSessionId firstId = TerminalSessionId(
    paneId: PaneId(11),
    generation: 3,
  );
  const TerminalSessionId secondId = TerminalSessionId(
    paneId: PaneId(12),
    generation: 4,
  );
  final _Harness first = _Harness();
  final _Harness second = _Harness();
  final TerminalDesktopSignalSessionProjection firstProjection = coordinator
      .registerSession(firstId);
  final TerminalDesktopSignalSessionProjection secondProjection = coordinator
      .registerSession(secondId);
  coordinator.focusSession(firstId);

  first.parse('${_osc(9, '4;1;42')}${_osc(133, 'B')}');
  firstProjection.synchronize(first.screens);
  for (final String identifier in const <String>['a', 'b', 'c']) {
    first.parse(_osc(99, 'i=$identifier;notification-$identifier'));
    firstProjection.synchronize(first.screens);
  }
  final TerminalDesktopSignalSessionSnapshot firstSnapshot = coordinator
      .snapshotFor(firstId)!;
  _expect(
    firstSnapshot.progress.state == TerminalProgressState.set &&
        firstSnapshot.progress.percent == 42 &&
        firstSnapshot.semanticShellState == TerminalSemanticShellState.input &&
        firstSnapshot.liveNotificationCount == 2 &&
        port.badgeLabels.last == '42%' &&
        port.removed.length == 1,
    'focused progress, content-free semantic state, and per-session native '
    'identity eviction remain bounded',
  );

  second.parse(
    '${_osc(9, '4;2;55')}${_osc(133, 'N')}${_osc(99, 'i=a;other-pane')}',
  );
  secondProjection.synchronize(second.screens);
  coordinator.focusSession(secondId);
  final TerminalDesktopSignalSessionSnapshot secondSnapshot = coordinator
      .snapshotFor(secondId)!;
  _expect(
    secondSnapshot.progress.state == TerminalProgressState.error &&
        secondSnapshot.semanticShellState ==
            TerminalSemanticShellState.prompt &&
        secondSnapshot.liveNotificationCount == 1 &&
        port.badgeLabels.last == '55%!' &&
        port.posts.last.identifier != port.posts.first.identifier,
    'progress, semantic state, and terminal logical identifiers cannot leak '
    'between pane sessions',
  );

  final int resetGeneration = first.screens.resetGeneration;
  first.parse('\x1bc');
  firstProjection.synchronize(first.screens);
  final TerminalDesktopSignalSessionSnapshot resetSnapshot = coordinator
      .snapshotFor(firstId)!;
  _expect(
    resetSnapshot.resetGeneration == resetGeneration + 1 &&
        resetSnapshot.progress.state == TerminalProgressState.removed &&
        resetSnapshot.semanticShellState ==
            TerminalSemanticShellState.unknown &&
        resetSnapshot.liveNotificationCount == 0 &&
        port.removed.length == 3,
    'RIS has a dedicated generation and cancels already-drained native '
    'identities while clearing progress and semantic state',
  );

  coordinator.removeSession(secondId);
  second.parse(_osc(9, 'stale-after-close'));
  secondProjection.synchronize(second.screens);
  _expect(
    coordinator.snapshotFor(secondId) == null &&
        port.removed.length == 4 &&
        port.badgeLabels.last == null &&
        port.posts.length == 4 &&
        coordinator.metrics.revokedSessionDroppedNotificationCount == 1,
    'session close removes its snapshot, notification identity, and focused '
    'Dock progress while its stale lease cannot project again',
  );
  coordinator.dispose();
}

void _testProjectionFailureAndConfigurationBounds() {
  _expectThrows<RangeError>(
    () => TerminalDesktopSignalCoordinator(
      nativePort: _FakeNativePort(),
      notificationBudget: 0,
    ),
    'zero notification budget',
  );
  _expectThrows<RangeError>(
    () => TerminalDesktopSignalCoordinator(
      nativePort: _FakeNativePort(),
      notificationBudget:
          TerminalDesktopSignalCoordinator.maximumNotificationBudget + 1,
    ),
    'budget beyond the hard maximum',
  );
  _expectThrows<RangeError>(
    () => TerminalDesktopSignalCoordinator(
      nativePort: _FakeNativePort(),
      notificationWindow: const Duration(milliseconds: 999),
    ),
    'window below the hard minimum',
  );

  final _FakeNativePort port = _FakeNativePort()..failPost = true;
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(nativePort: port);
  const TerminalSessionId id = TerminalSessionId(
    paneId: PaneId(21),
    generation: 1,
  );
  final _Harness harness = _Harness()..parse(_osc(9, 'failure'));
  coordinator.registerSession(id).synchronize(harness.screens);
  _expect(
    coordinator.metrics.admittedNotificationCount == 1 &&
        coordinator.metrics.projectedNotificationCount == 0 &&
        coordinator.metrics.projectionFailureCount == 1 &&
        coordinator.snapshotFor(id)!.liveNotificationCount == 0,
    'a native failure is observable but cannot publish or retry hidden state',
  );
  coordinator.dispose();
}

Future<void> _testTerminalSessionOutputAndCloseIntegration() async {
  final _FakeNativePort port = _FakeNativePort();
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(nativePort: port, notificationBudget: 8);
  const TerminalSessionId id = TerminalSessionId(
    paneId: PaneId(31),
    generation: 5,
  );
  final FakePtyBackend backend = FakePtyBackend();
  final TerminalSession session = TerminalSession(
    id: id,
    ptyBackend: backend,
    desktopSignalCoordinator: coordinator,
    onChanged: () {},
    onTerminated: () {},
  );
  coordinator.focusSession(id);
  await session.start();
  final FakePtyProcess process = backend.processes.single;
  process.emitOutput(
    utf8.encode('${_osc(99, 'i=session;ready')}${_osc(9, '4;3')}'),
  );
  _expect(
    port.posts.length == 1 &&
        port.badgeLabels.last == '…' &&
        coordinator.snapshotFor(id)!.liveNotificationCount == 1,
    'one real TerminalSession output callback synchronizes parser state to the '
    'native port',
  );

  process.emitOutput(utf8.encode('\x1bc'));
  _expect(
    port.removed.length == 1 &&
        port.badgeLabels.last == null &&
        coordinator.snapshotFor(id)!.liveNotificationCount == 0,
    'the session parser callback projects RIS cancellation in the same turn',
  );
  process.emitOutput(utf8.encode(_osc(99, 'i=session;again')));
  await session.dispose();
  _expect(
    coordinator.snapshotFor(id) == null && port.removed.length == 2,
    'TerminalSession shutdown closes the coordinator lifecycle before PTY '
    'cleanup completes',
  );
  coordinator.dispose();
}

String _osc(int command, String payload) => '\x1b]$command;$payload\x07';

final class _Harness {
  _Harness() : screens = TerminalScreenSet(rows: 3, columns: 8) {
    parser = VtParser(sink: TerminalScreenParserSink.forScreenSet(screens));
  }

  final TerminalScreenSet screens;
  late final VtParser parser;

  void parse(String value) =>
      parser.parse(Uint8List.fromList(utf8.encode(value)));
}

final class _FakeClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
  }
}

final class _FakeNativePort implements TerminalDesktopSignalNativePort {
  final List<
    ({
      TerminalSessionId sessionId,
      String identifier,
      String title,
      String body,
    })
  >
  posts =
      <
        ({
          TerminalSessionId sessionId,
          String identifier,
          String title,
          String body,
        })
      >[];
  final List<String> removed = <String>[];
  final List<String?> badgeLabels = <String?>[];
  bool failPost = false;
  bool failRemove = false;
  bool failBadge = false;

  @override
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  }) {
    if (failPost) return false;
    posts.add((
      sessionId: sessionId,
      identifier: identifier,
      title: title,
      body: body,
    ));
    return true;
  }

  @override
  bool removeNotification(String identifier) {
    if (failRemove) return false;
    removed.add(identifier);
    return true;
  }

  @override
  bool setDockBadgeLabel(String? label) {
    if (failBadge) return false;
    badgeLabels.add(label);
    return true;
  }
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _expectThrows<T extends Object>(
  void Function() action,
  String description,
) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}
