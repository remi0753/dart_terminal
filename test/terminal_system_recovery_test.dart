import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSystemRecoveryTests();

void runTerminalSystemRecoveryTests() {
  _testSignalsAreCoalescedOntoLaterTurns();
  _testSameTurnSleepWakeStillSuspendsBeforeRecovery();
  _testDisplayRecoveryCanWaitForHierarchyReconciliation();
  _testDisposedControllerIgnoresScheduledWork();
}

void _testSignalsAreCoalescedOntoLaterTurns() {
  final List<void Function()> scheduled = <void Function()>[];
  final List<String> operations = <String>[];
  final TerminalSystemRecoveryController controller =
      TerminalSystemRecoveryController(
        suspendPresentation: () => operations.add('suspend'),
        recoverDisplays: () {
          operations.add('recover');
          return true;
        },
        resumePresentation: () => operations.add('resume'),
        schedule: scheduled.add,
      );

  _expect(
    controller.handle(
          const ApplicationPowerStateChangedEvent(
            monotonicMicros: 10,
            state: AppKitApplicationPowerState.willSleep,
          ),
        ) ==
        TerminalSystemRecoveryEventDisposition.accepted,
    'first sleep was not accepted',
  );
  _expect(
    controller.handle(
          const ApplicationPowerStateChangedEvent(
            monotonicMicros: 11,
            state: AppKitApplicationPowerState.willSleep,
          ),
        ) ==
        TerminalSystemRecoveryEventDisposition.coalesced,
    'duplicate sleep was not coalesced',
  );
  _expect(
    controller.handle(
              const ApplicationScreenSetChangedEvent(monotonicMicros: 20),
            ) ==
            TerminalSystemRecoveryEventDisposition.accepted &&
        controller.handle(
              const ApplicationScreenSetChangedEvent(monotonicMicros: 21),
            ) ==
            TerminalSystemRecoveryEventDisposition.coalesced,
    'screen-set burst was not coalesced',
  );
  _expect(
    scheduled.length == 1 && operations.isEmpty,
    'native callbacks performed work synchronously or queued more than once',
  );

  scheduled.removeAt(0)();
  TerminalSystemRecoverySnapshot snapshot = controller.snapshot();
  _expect(
    operations.join(',') == 'suspend' &&
        snapshot.isSleeping &&
        snapshot.isPresentationSuspended &&
        snapshot.hasPendingScreenRecovery &&
        !snapshot.hasScheduledDrain,
    'sleep drain recovered displays or lost deferred screen work',
  );
  _expect(
    controller.handle(
          const ApplicationPowerStateChangedEvent(
            monotonicMicros: 10,
            state: AppKitApplicationPowerState.didWake,
          ),
        ) ==
        TerminalSystemRecoveryEventDisposition.stale,
    'stale power transition was accepted',
  );
  _expect(
    controller.handle(
          const ApplicationPowerStateChangedEvent(
            monotonicMicros: 12,
            state: AppKitApplicationPowerState.didWake,
          ),
        ) ==
        TerminalSystemRecoveryEventDisposition.accepted,
    'wake was not accepted',
  );
  scheduled.removeAt(0)();
  snapshot = controller.snapshot();
  _expect(
    operations.join(',') == 'suspend,recover,resume' &&
        !snapshot.isSleeping &&
        !snapshot.isPresentationSuspended &&
        !snapshot.hasPendingScreenRecovery &&
        snapshot.acceptedEventCount == 3 &&
        snapshot.coalescedEventCount == 2 &&
        snapshot.staleEventCount == 1 &&
        snapshot.drainCount == 2 &&
        snapshot.suspendCount == 1 &&
        snapshot.displayRecoveryCount == 1 &&
        snapshot.resumeCount == 1,
    'coalesced recovery counters or operation order diverged',
  );
  _expect(
    controller.handle(
          const ApplicationMemoryPressureChangedEvent(
            monotonicMicros: 30,
            level: AppKitMemoryPressureLevel.warning,
          ),
        ) ==
        TerminalSystemRecoveryEventDisposition.unhandled,
    'ordered memory-pressure policy was consumed early',
  );
}

void _testSameTurnSleepWakeStillSuspendsBeforeRecovery() {
  final List<void Function()> scheduled = <void Function()>[];
  final List<String> operations = <String>[];
  final TerminalSystemRecoveryController controller =
      TerminalSystemRecoveryController(
        suspendPresentation: () => operations.add('suspend'),
        recoverDisplays: () {
          operations.add('recover');
          return true;
        },
        resumePresentation: () => operations.add('resume'),
        schedule: scheduled.add,
      );
  controller.handle(
    const ApplicationPowerStateChangedEvent(
      monotonicMicros: 1,
      state: AppKitApplicationPowerState.willSleep,
    ),
  );
  controller.handle(const ApplicationScreenSetChangedEvent(monotonicMicros: 1));
  controller.handle(
    const ApplicationPowerStateChangedEvent(
      monotonicMicros: 2,
      state: AppKitApplicationPowerState.didWake,
    ),
  );
  _expect(scheduled.length == 1, 'same-turn sequence queued multiple drains');
  scheduled.single();
  _expect(
    operations.join(',') == 'suspend,recover,resume',
    'same-turn wake resumed before suspension and display recovery',
  );
}

void _testDisplayRecoveryCanWaitForHierarchyReconciliation() {
  final List<void Function()> scheduled = <void Function()>[];
  final List<String> operations = <String>[];
  var hierarchyIsReconciled = false;
  final TerminalSystemRecoveryController controller =
      TerminalSystemRecoveryController(
        suspendPresentation: () => operations.add('suspend'),
        recoverDisplays: () {
          operations.add('recover');
          return hierarchyIsReconciled;
        },
        resumePresentation: () => operations.add('resume'),
        schedule: scheduled.add,
      );

  controller.handle(const ApplicationScreenSetChangedEvent(monotonicMicros: 1));
  scheduled.removeAt(0)();
  TerminalSystemRecoverySnapshot snapshot = controller.snapshot();
  _expect(
    operations.join(',') == 'recover' &&
        snapshot.hasPendingScreenRecovery &&
        !snapshot.hasScheduledDrain &&
        snapshot.displayRecoveryCount == 0,
    'deferred display recovery was lost or counted as complete',
  );

  hierarchyIsReconciled = true;
  _expect(
    controller.retryPendingDisplayRecovery() && scheduled.length == 1,
    'reconciled hierarchy did not schedule its retained recovery',
  );
  _expect(
    !controller.retryPendingDisplayRecovery() && scheduled.length == 1,
    'duplicate recovery retry queued more than one drain',
  );
  scheduled.removeAt(0)();
  snapshot = controller.snapshot();
  _expect(
    operations.join(',') == 'recover,recover' &&
        !snapshot.hasPendingScreenRecovery &&
        !snapshot.hasScheduledDrain &&
        snapshot.drainCount == 2 &&
        snapshot.displayRecoveryCount == 1,
    'successful retry did not complete retained display recovery once',
  );
}

void _testDisposedControllerIgnoresScheduledWork() {
  final List<void Function()> scheduled = <void Function()>[];
  var operationCount = 0;
  final TerminalSystemRecoveryController controller =
      TerminalSystemRecoveryController(
        suspendPresentation: () => operationCount++,
        recoverDisplays: () {
          operationCount++;
          return true;
        },
        resumePresentation: () => operationCount++,
        schedule: scheduled.add,
      );
  controller.handle(const ApplicationScreenSetChangedEvent(monotonicMicros: 1));
  controller.dispose();
  scheduled.single();
  _expect(
    operationCount == 0 &&
        controller.snapshot().isDisposed &&
        controller.handle(
              const ApplicationScreenSetChangedEvent(monotonicMicros: 2),
            ) ==
            TerminalSystemRecoveryEventDisposition.disposed,
    'disposed controller retained scheduled or new work',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('terminal system recovery test failed: $message');
  }
}
