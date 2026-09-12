import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSecureKeyboardEntryTests();

void runTerminalSecureKeyboardEntryTests() {
  _testAutomaticFocusAndEchoArbitration();
  _testManualLifecycleAndLiveConfiguration();
  _testFailureRetryAndDeterministicDisposal();
  _testUnavailableNativeOwnerRemainsVisible();
}

void _testAutomaticFocusAndEchoArbitration() {
  final _FakeSecureLease lease = _FakeSecureLease();
  final List<TerminalSecureKeyboardEntryStatus> statuses =
      <TerminalSecureKeyboardEntryStatus>[];
  final TerminalSecureKeyboardEntryController controller =
      TerminalSecureKeyboardEntryController(
        lease: lease,
        onStatusChanged: statuses.add,
      );
  final _FakeSecureTarget first = _FakeSecureTarget('first');
  final _FakeSecureTarget second = _FakeSecureTarget('second');

  controller.reconcile(first.target(echo: true));
  _expect(
    lease.setDesiredCalls == 0 &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.disabled &&
        first.writes.isEmpty,
    'echo-on target keeps automatic Secure Keyboard Entry released',
  );

  controller.reconcile(first.target(echo: false));
  _expect(
    lease.setDesiredCalls == 1 &&
        lease.desired &&
        lease.owned &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.automatic &&
        first.writes.single == TerminalSecureKeyboardEntryIndicator.automatic,
    'focused live echo-off target acquires and shows automatic indication',
  );
  final int statusCount = statuses.length;
  controller.reconcile(first.target(echo: false));
  _expect(
    lease.setDesiredCalls == 1 &&
        first.writes.length == 1 &&
        statuses.length == statusCount,
    'equivalent observations do not duplicate native or UI transitions',
  );

  controller.reconcile(first.target(echo: false, focused: false));
  _expect(
    !lease.desired &&
        !lease.owned &&
        first.writes.last == TerminalSecureKeyboardEntryIndicator.hidden,
    'window focus loss releases automatic mode and hides its indication',
  );

  controller.reconcile(second.target(echo: false));
  _expect(
    first.writes.last == TerminalSecureKeyboardEntryIndicator.hidden &&
        second.writes.single ==
            TerminalSecureKeyboardEntryIndicator.automatic &&
        lease.setDesiredCalls == 3,
    'focus change hides the old pane before indicating the new pane',
  );
  controller.reconcile(second.target(echo: null));
  _expect(
    !lease.desired &&
        !lease.owned &&
        second.writes.last == TerminalSecureKeyboardEntryIndicator.hidden &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.disabled &&
        controller.status.terminalEchoEnabled == null,
    'unavailable terminal attributes fail closed by releasing automatic mode',
  );
  controller.dispose();
}

void _testManualLifecycleAndLiveConfiguration() {
  final _FakeSecureLease lease = _FakeSecureLease();
  final TerminalSecureKeyboardEntryController controller =
      TerminalSecureKeyboardEntryController(lease: lease);
  final _FakeSecureTarget target = _FakeSecureTarget('manual');

  controller.toggleManual(target: target.target(echo: true));
  _expect(
    controller.manualRequested &&
        lease.desired &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.manual &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.manual,
    'manual intent overrides echo-on and projects a distinct indication',
  );

  lease.setApplicationActive(false);
  controller.setApplicationActive(false, target: target.target(echo: true));
  _expect(
    controller.manualRequested &&
        lease.desired &&
        !lease.owned &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.manual &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.hidden,
    'manual desire is retained while the native owner yields when inactive',
  );

  lease.setApplicationActive(true);
  controller.setApplicationActive(true, target: target.target(echo: true));
  _expect(
    lease.desired &&
        lease.owned &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.manual,
    'activation observes native reacquisition and restores manual indication',
  );

  controller.applyConfiguration(
    automaticEnabled: false,
    indicationEnabled: false,
    target: target.target(echo: true),
  );
  _expect(
    lease.owned &&
        controller.manualRequested &&
        !controller.status.automaticEnabled &&
        !controller.status.indicationEnabled &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.hidden,
    'live indication disablement hides UI without weakening manual ownership',
  );
  controller.toggleManual(target: target.target(echo: false));
  _expect(
    !lease.desired &&
        !lease.owned &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.disabled,
    'manual off plus automatic config off releases even for echo-off',
  );
  controller.applyConfiguration(
    automaticEnabled: true,
    indicationEnabled: true,
    target: target.target(echo: false),
  );
  _expect(
    lease.owned &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.automatic &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.automatic,
    'live automatic reload immediately reconciles focused echo state',
  );
  controller.dispose();
}

void _testFailureRetryAndDeterministicDisposal() {
  final _FakeSecureLease lease = _FakeSecureLease()..failNextSet = true;
  final _FakeSecureTarget target = _FakeSecureTarget('failure');
  final List<Object> failures = <Object>[];
  final TerminalSecureKeyboardEntryController controller =
      TerminalSecureKeyboardEntryController(
        lease: lease,
        onFailure: (Object error, StackTrace _) => failures.add(error),
      );

  controller.reconcile(target.target(echo: false));
  _expect(
    controller.status.mode == TerminalSecureKeyboardEntryMode.failed &&
        controller.status.failure is StateError &&
        controller.status.desired &&
        !controller.status.ownedEnabled &&
        failures.length == 1 &&
        target.writes.isEmpty,
    'acquisition failure is typed in status and never shows a false indicator',
  );
  controller.reconcile(target.target(echo: false));
  _expect(
    lease.setDesiredCalls == 2 &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.automatic &&
        lease.owned &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.automatic,
    'a failed retained acquire is retried on the next observation',
  );

  lease.failNextSet = true;
  controller.reconcile(target.target(echo: true));
  _expect(
    controller.status.mode == TerminalSecureKeyboardEntryMode.failed &&
        !controller.status.desired &&
        controller.status.ownedEnabled &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.hidden,
    'release failure remains visible and hides indication conservatively',
  );
  controller.reconcile(target.target(echo: true));
  _expect(
    !lease.owned &&
        controller.status.mode == TerminalSecureKeyboardEntryMode.disabled,
    'failed release retries until the owned reference is cleared',
  );

  controller.toggleManual(target: target.target(echo: true));
  final int callsBeforeDispose = lease.setDesiredCalls;
  controller.dispose();
  controller.dispose();
  _expect(
    lease.setDesiredCalls == callsBeforeDispose + 1 &&
        lease.disposeCalls == 1 &&
        !lease.owned &&
        target.writes.last == TerminalSecureKeyboardEntryIndicator.hidden &&
        controller.isDisposed,
    'dispose hides, releases, and disposes exactly once',
  );
  _expectThrows<StateError>(
    () => controller.reconcile(target.target(echo: false)),
    'disposed controller rejects later observations',
  );
}

void _testUnavailableNativeOwnerRemainsVisible() {
  final StateError unavailable = StateError('injected unavailable owner');
  final TerminalSecureKeyboardEntryController controller =
      TerminalSecureKeyboardEntryController(
        lease: TerminalUnavailableSecureKeyboardEntryLease(
          unavailable,
          StackTrace.current,
        ),
      );
  final _FakeSecureTarget target = _FakeSecureTarget('private-content');
  controller.reconcile(target.target(echo: false));
  _expect(
    controller.status.mode == TerminalSecureKeyboardEntryMode.failed &&
        controller.status.failure == unavailable &&
        !controller.status.settingsLine.contains('private-content') &&
        !controller.status.machineLine().contains('private-content') &&
        target.writes.isEmpty,
    'unavailable native support remains visible without exposing target data',
  );
  controller.dispose();
}

final class _FakeSecureLease implements TerminalSecureKeyboardEntryLease {
  bool applicationActive = true;
  bool desired = false;
  bool owned = false;
  bool externalSystemOwner = false;
  bool failNextSet = false;
  int lastOsStatus = 0;
  int setDesiredCalls = 0;
  int disposeCalls = 0;

  void setApplicationActive(bool value) {
    applicationActive = value;
    owned = desired && applicationActive;
  }

  @override
  void setDesired(bool value) {
    setDesiredCalls++;
    desired = value;
    if (failNextSet) {
      failNextSet = false;
      lastOsStatus = -50;
      throw StateError('injected Secure Event Input failure');
    }
    owned = desired && applicationActive;
    lastOsStatus = 0;
  }

  @override
  TerminalSecureKeyboardEntryLeaseSnapshot snapshot() =>
      TerminalSecureKeyboardEntryLeaseSnapshot(
        desired: desired,
        ownedEnabled: owned,
        systemEnabled: owned || externalSystemOwner,
        lastOsStatus: lastOsStatus,
      );

  @override
  void dispose() {
    disposeCalls++;
    desired = false;
    owned = false;
  }
}

final class _FakeSecureTarget {
  _FakeSecureTarget(this.identity);

  final Object identity;
  final List<TerminalSecureKeyboardEntryIndicator> writes =
      <TerminalSecureKeyboardEntryIndicator>[];

  TerminalSecureKeyboardEntryTarget target({
    required bool? echo,
    bool focused = true,
    bool live = true,
  }) => TerminalSecureKeyboardEntryTarget(
    identity: identity,
    isFocused: focused,
    isLive: live,
    terminalEchoEnabled: echo,
    setIndicator: writes.add,
  );
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}
