import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalPaneWorkSchedulerTests();

Future<void> runTerminalPaneWorkSchedulerTests() async {
  _testLimitsAndAdmission();
  _testRoundRobinCoalescingAndTurnYield();
  _testDelayedRequestPromotion();
  _testTimeBudgetAndFaultIsolation();
  _testUnregisterAndDisposal();
  await _testAutomaticScheduling();
}

void _testLimitsAndAdmission() {
  _expectThrows<RangeError>(
    () => TerminalPaneWorkScheduler(
      limits: const TerminalPaneWorkSchedulerLimits(maximumPanes: 0),
    ),
    'scheduler rejects an empty registration budget',
  );
  _expectThrows<RangeError>(
    () => TerminalPaneWorkScheduler(
      limits: const TerminalPaneWorkSchedulerLimits(maximumPanes: 65),
    ),
    'scheduler cannot exceed the product-wide pane budget',
  );
  _expectThrows<RangeError>(
    () => TerminalPaneWorkScheduler(
      limits: const TerminalPaneWorkSchedulerLimits(maximumWorkPerTurn: 65),
    ),
    'one turn cannot exceed the product-wide pane budget',
  );
  _expect(
    TerminalPaneWorkSchedulerLimits.maximumSupportedPanes ==
        TerminalApplicationStateLimits.maximumTotalPanes,
    'scheduler and live hierarchy use one aggregate pane budget',
  );

  final TerminalPaneWorkScheduler scheduler = TerminalPaneWorkScheduler(
    limits: const TerminalPaneWorkSchedulerLimits(
      maximumPanes: 2,
      maximumWorkPerTurn: 2,
    ),
    automaticScheduling: false,
  );
  final TerminalSessionId first = _session(1);
  final TerminalSessionId second = _session(2);
  scheduler
    ..register(first, () {})
    ..register(second, () {});
  _expectThrows<StateError>(
    () => scheduler.register(first, () {}),
    'duplicate session registration is rejected',
  );
  _expectThrows<StateError>(
    () => scheduler.register(_session(3), () {}),
    'registration beyond the fixed pane budget is rejected',
  );
  _expect(
    !scheduler.request(_session(3)) &&
        scheduler.snapshot().registeredPaneCount == 2 &&
        scheduler.snapshot().pendingPaneCount == 0,
    'unknown requests allocate no pending scheduler state',
  );
  _expectThrows<RangeError>(
    () => scheduler.request(first, delay: const Duration(microseconds: -1)),
    'negative delay is rejected',
  );
  _expectThrows<RangeError>(
    () => scheduler.request(first, delay: const Duration(minutes: 2)),
    'unbounded delayed work is rejected',
  );
  scheduler.dispose();
}

void _testRoundRobinCoalescingAndTurnYield() {
  var now = 0;
  final List<int> order = <int>[];
  final Map<int, int> counts = <int, int>{};
  late final TerminalPaneWorkScheduler scheduler;
  final TerminalSessionId first = _session(1);
  final TerminalSessionId second = _session(2);
  final TerminalSessionId third = _session(3);
  void work(TerminalSessionId sessionId) {
    final int pane = sessionId.paneId.value;
    order.add(pane);
    final int count = (counts[pane] ?? 0) + 1;
    counts[pane] = count;
    if (pane != 3 && count == 1) scheduler.request(sessionId);
  }

  scheduler = TerminalPaneWorkScheduler(
    limits: const TerminalPaneWorkSchedulerLimits(
      maximumPanes: 3,
      maximumWorkPerTurn: 2,
      maximumTurnDuration: Duration(seconds: 1),
    ),
    automaticScheduling: false,
    monotonicMicros: () => now,
  );
  scheduler
    ..register(first, () => work(first))
    ..register(second, () => work(second))
    ..register(third, () => work(third))
    ..request(first)
    ..request(first)
    ..request(second)
    ..request(third);
  final TerminalPaneWorkTurnResult firstTurn = scheduler.processPending();
  final TerminalPaneWorkTurnResult secondTurn = scheduler.processPending();
  final TerminalPaneWorkTurnResult thirdTurn = scheduler.processPending();
  final TerminalPaneWorkSchedulerSnapshot snapshot = scheduler.snapshot();
  _expect(
    order.join(',') == '1,2,3,1,2' &&
        firstTurn.workCount == 2 &&
        firstTurn.yielded &&
        secondTurn.workCount == 2 &&
        secondTurn.yielded &&
        thirdTurn.workCount == 1 &&
        !thirdTurn.yielded &&
        snapshot.pendingPaneCount == 0 &&
        snapshot.peakPendingPaneCount == 3 &&
        snapshot.requestCount == 6 &&
        snapshot.coalescedRequestCount == 1 &&
        snapshot.turnCount == 3 &&
        snapshot.workCount == 5 &&
        snapshot.yieldCount == 2 &&
        snapshot.maximumWorkPerTurnObserved == 2,
    'coalesced reentrant work remains round-robin and yields by turn budget',
  );
  scheduler.dispose();
}

void _testDelayedRequestPromotion() {
  var now = 0;
  final List<int> order = <int>[];
  final TerminalPaneWorkScheduler scheduler = TerminalPaneWorkScheduler(
    limits: const TerminalPaneWorkSchedulerLimits(
      maximumPanes: 2,
      maximumWorkPerTurn: 2,
    ),
    automaticScheduling: false,
    monotonicMicros: () => now,
  );
  final TerminalSessionId first = _session(1);
  final TerminalSessionId second = _session(2);
  scheduler
    ..register(first, () => order.add(1))
    ..register(second, () => order.add(2))
    ..request(first, delay: const Duration(microseconds: 100))
    ..request(second, delay: const Duration(microseconds: 200))
    ..request(second);
  final TerminalPaneWorkTurnResult initial = scheduler.processPending();
  now = 99;
  final TerminalPaneWorkTurnResult early = scheduler.processPending();
  now = 100;
  final TerminalPaneWorkTurnResult due = scheduler.processPending();
  _expect(
    initial.workCount == 1 &&
        !initial.yielded &&
        early.workCount == 0 &&
        due.workCount == 1 &&
        order.join(',') == '2,1' &&
        scheduler.snapshot().coalescedRequestCount == 1 &&
        scheduler.pendingPaneCount == 0,
    'immediate work promotes a delayed pane without losing later deadlines',
  );
  scheduler.dispose();
}

void _testTimeBudgetAndFaultIsolation() {
  var now = 0;
  final List<int> order = <int>[];
  final List<int> faulted = <int>[];
  late final TerminalPaneWorkScheduler scheduler;
  final TerminalSessionId first = _session(1);
  final TerminalSessionId second = _session(2);
  final TerminalSessionId third = _session(3);
  var firstCount = 0;
  scheduler = TerminalPaneWorkScheduler(
    limits: const TerminalPaneWorkSchedulerLimits(
      maximumPanes: 3,
      maximumWorkPerTurn: 3,
      maximumTurnDuration: Duration(microseconds: 4),
    ),
    automaticScheduling: false,
    monotonicMicros: () => now,
    onError: (TerminalSessionId sessionId, Object _, StackTrace _) {
      faulted.add(sessionId.paneId.value);
      throw StateError('injected observer failure');
    },
  );
  scheduler
    ..register(first, () {
      order.add(1);
      firstCount++;
      if (firstCount == 1) scheduler.request(first);
      now += 4;
    })
    ..register(second, () {
      order.add(2);
      throw StateError('injected pane failure');
    })
    ..register(third, () => order.add(3))
    ..request(first)
    ..request(second)
    ..request(third);
  final TerminalPaneWorkTurnResult bounded = scheduler.processPending();
  final TerminalPaneWorkTurnResult continued = scheduler.processPending();
  _expect(
    bounded.workCount == 1 &&
        bounded.yielded &&
        continued.workCount == 3 &&
        continued.faultCount == 1 &&
        order.join(',') == '1,2,3,1' &&
        faulted.join(',') == '2' &&
        scheduler.snapshot().faultCount == 1 &&
        scheduler.snapshot().yieldCount == 1 &&
        scheduler.pendingPaneCount == 0,
    'time exhaustion yields and one pane fault cannot block its peers',
  );
  scheduler.dispose();
}

void _testUnregisterAndDisposal() {
  final TerminalPaneWorkScheduler scheduler = TerminalPaneWorkScheduler(
    automaticScheduling: false,
  );
  final TerminalSessionId first = _session(1);
  var calls = 0;
  scheduler
    ..register(first, () => calls++)
    ..request(first);
  _expect(
    scheduler.cancel(first) &&
        !scheduler.cancel(first) &&
        scheduler.processPending().workCount == 0 &&
        calls == 0,
    'cancel removes exact pending work while retaining registration',
  );
  scheduler.request(first);
  _expect(
    scheduler.unregister(first) &&
        !scheduler.unregister(first) &&
        scheduler.processPending().workCount == 0 &&
        calls == 0,
    'unregister removes exact pending work without invoking it',
  );
  scheduler.register(first, () => calls++);
  scheduler.request(first);
  scheduler.dispose();
  scheduler.dispose();
  _expect(
    scheduler.snapshot().isDisposed &&
        scheduler.snapshot().registeredPaneCount == 0 &&
        scheduler.snapshot().pendingPaneCount == 0 &&
        !scheduler.request(first) &&
        !scheduler.unregister(first),
    'dispose is idempotent and retires all registrations and pending work',
  );
  _expectThrows<StateError>(
    () => scheduler.register(first, () {}),
    'disposed scheduler refuses new ownership',
  );
}

Future<void> _testAutomaticScheduling() async {
  final Completer<void> completed = Completer<void>();
  final TerminalPaneWorkScheduler scheduler = TerminalPaneWorkScheduler(
    limits: const TerminalPaneWorkSchedulerLimits(maximumPanes: 1),
  );
  final TerminalSessionId first = _session(1);
  scheduler.register(first, () => completed.complete());
  _expect(
    scheduler.request(first) && scheduler.snapshot().hasScheduledTimer,
    'automatic request owns one scheduled timer',
  );
  await completed.future.timeout(const Duration(seconds: 1));
  final TerminalPaneWorkSchedulerSnapshot snapshot = scheduler.snapshot();
  _expect(
    snapshot.turnCount == 1 &&
        snapshot.workCount == 1 &&
        snapshot.pendingPaneCount == 0 &&
        !snapshot.hasScheduledTimer,
    'automatic timer runs one exact bounded turn',
  );
  scheduler.dispose();
}

TerminalSessionId _session(int pane) =>
    TerminalSessionId(paneId: PaneId(pane), generation: 1);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}
