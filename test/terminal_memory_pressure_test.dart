import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalMemoryPressureTests();

void runTerminalMemoryPressureTests() {
  _testStormCoalescesToHighestSeverity();
  _testFailureRetryIsBounded();
  _testDisposeMakesScheduledWorkInert();
}

void _testStormCoalescesToHighestSeverity() {
  final List<void Function()> scheduled = <void Function()>[];
  final List<AppKitMemoryPressureLevel> applied = <AppKitMemoryPressureLevel>[];
  final TerminalMemoryPressureController controller =
      TerminalMemoryPressureController(
        apply: applied.add,
        schedule: scheduled.add,
      );

  _expect(
    controller.handle(_pressure(10, AppKitMemoryPressureLevel.warning)) ==
            TerminalMemoryPressureEventDisposition.accepted &&
        controller.handle(_pressure(11, AppKitMemoryPressureLevel.warning)) ==
            TerminalMemoryPressureEventDisposition.coalesced &&
        controller.handle(_pressure(12, AppKitMemoryPressureLevel.critical)) ==
            TerminalMemoryPressureEventDisposition.accepted &&
        controller.handle(_pressure(13, AppKitMemoryPressureLevel.warning)) ==
            TerminalMemoryPressureEventDisposition.coalesced &&
        scheduled.length == 1 &&
        applied.isEmpty,
    'same-turn pressure work was not bounded or escaped the native callback',
  );
  scheduled.removeAt(0)();
  final TerminalMemoryPressureSnapshot critical = controller.snapshot();
  _expect(
    applied.length == 1 &&
        applied.single == AppKitMemoryPressureLevel.critical &&
        critical.pendingLevel == null &&
        critical.acceptedEventCount == 2 &&
        critical.coalescedEventCount == 2 &&
        critical.applicationCount == 1,
    'pressure storm did not retain and apply exactly its highest severity',
  );
  _expect(
    controller.handle(_pressure(12, AppKitMemoryPressureLevel.normal)) ==
            TerminalMemoryPressureEventDisposition.stale &&
        controller.handle(_pressure(14, AppKitMemoryPressureLevel.normal)) ==
            TerminalMemoryPressureEventDisposition.accepted &&
        controller.handle(_pressure(15, AppKitMemoryPressureLevel.normal)) ==
            TerminalMemoryPressureEventDisposition.coalesced &&
        controller.snapshot().recoveryCount == 1 &&
        scheduled.isEmpty,
    'normal recovery or stale/duplicate pressure handling diverged',
  );
  _expect(
    controller.handle(
          const ApplicationScreenSetChangedEvent(
            protocolVersion: 15,
            monotonicMicros: 16,
          ),
        ) ==
        TerminalMemoryPressureEventDisposition.unhandled,
    'memory controller consumed an unrelated generic event',
  );
}

void _testFailureRetryIsBounded() {
  final List<void Function()> scheduled = <void Function()>[];
  var attempts = 0;
  var reported = 0;
  final TerminalMemoryPressureController succeeds =
      TerminalMemoryPressureController(
        apply: (AppKitMemoryPressureLevel _) {
          attempts++;
          if (attempts < 3) throw StateError('synthetic allocation failure');
        },
        schedule: scheduled.add,
        onError: (Object _, StackTrace _) => reported++,
      );
  succeeds.handle(_pressure(20, AppKitMemoryPressureLevel.critical));
  while (scheduled.isNotEmpty) {
    scheduled.removeAt(0)();
  }
  _expect(
    attempts == 3 &&
        reported == 0 &&
        succeeds.snapshot().failureCount == 2 &&
        succeeds.snapshot().applicationCount == 1 &&
        succeeds.snapshot().exhaustedCount == 0,
    'transient allocation failure did not recover within its fixed budget',
  );

  final List<void Function()> exhaustedWork = <void Function()>[];
  final TerminalMemoryPressureController exhausted =
      TerminalMemoryPressureController(
        apply: (AppKitMemoryPressureLevel _) =>
            throw StateError('persistent allocation failure'),
        schedule: exhaustedWork.add,
        maximumAttempts: 2,
        onError: (Object _, StackTrace _) => reported++,
      );
  exhausted.handle(_pressure(30, AppKitMemoryPressureLevel.warning));
  while (exhaustedWork.isNotEmpty) {
    exhaustedWork.removeAt(0)();
  }
  final TerminalMemoryPressureSnapshot snapshot = exhausted.snapshot();
  _expect(
    snapshot.drainCount == 2 &&
        snapshot.failureCount == 2 &&
        snapshot.exhaustedCount == 1 &&
        snapshot.pendingLevel == null &&
        !snapshot.hasScheduledDrain &&
        reported == 1,
    'persistent allocation failure exceeded the bounded retry/error policy',
  );
}

void _testDisposeMakesScheduledWorkInert() {
  final List<void Function()> scheduled = <void Function()>[];
  var applicationCount = 0;
  final TerminalMemoryPressureController controller =
      TerminalMemoryPressureController(
        apply: (AppKitMemoryPressureLevel _) => applicationCount++,
        schedule: scheduled.add,
      );
  controller.handle(_pressure(40, AppKitMemoryPressureLevel.warning));
  controller.dispose();
  scheduled.single();
  _expect(
    applicationCount == 0 &&
        controller.snapshot().isDisposed &&
        controller.snapshot().pendingLevel == null &&
        controller.handle(_pressure(41, AppKitMemoryPressureLevel.critical)) ==
            TerminalMemoryPressureEventDisposition.disposed,
    'disposed pressure controller retained or admitted work',
  );
}

ApplicationMemoryPressureChangedEvent _pressure(
  int monotonicMicros,
  AppKitMemoryPressureLevel level,
) => ApplicationMemoryPressureChangedEvent(
  protocolVersion: 15,
  monotonicMicros: monotonicMicros,
  level: level,
);

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('terminal memory pressure test failed: $message');
  }
}
