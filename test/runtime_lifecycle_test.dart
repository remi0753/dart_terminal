import 'dart:async';

import 'package:dart_terminal/src/runtime_lifecycle.dart';

Future<void> runRuntimeLifecycleTests() async {
  await _normalLifecycle();
  await _startupFailure();
  await _uncaughtWorkerFailures();
  await _unexpectedWorkerExit();
  await _idleWorkerTermination();
  await _stopProcessingFailure();
  await _forcedShutdown();
  await _lateCompletion();
  await _doubleShutdown();
  _terminationEvidenceOrdering();
}

Future<void> _normalLifecycle() async {
  final _Harness harness = _Harness(RuntimeLifecycleScenario.normal);
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'normal worker becomes ready',
  );
  final RuntimeLifecycleRequestResult request = await harness.coordinator
      .request(41);
  _expect(
    request.status == RuntimeLifecycleRequestStatus.response &&
        request.value == 42,
    'normal worker returns its response',
  );
  final RuntimeLifecycleShutdownResult shutdown = await harness.coordinator
      .shutdown();
  _expect(!shutdown.forced, 'normal worker stops gracefully');
  _expect(
    shutdown.termination == RuntimeLifecycleWorkerTermination.graceful,
    'normal worker has a graceful termination classification',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-response',
    'worker-stop-request',
    'worker-stop-ack',
    'worker-exit',
  ]);
}

Future<void> _startupFailure() async {
  final _Harness harness = _Harness(
    RuntimeLifecycleScenario.workerStartupFailure,
  );
  _expect(
    await harness.coordinator.start() ==
        RuntimeLifecycleStartStatus.startupFailure,
    'worker startup failure is contained',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-error',
    'worker-startup-failure',
    'worker-exit',
  ]);
}

Future<void> _uncaughtWorkerFailures() async {
  for (final RuntimeLifecycleScenario scenario in <RuntimeLifecycleScenario>[
    RuntimeLifecycleScenario.workerSyncUncaught,
    RuntimeLifecycleScenario.workerAsyncUncaught,
  ]) {
    final _Harness harness = _Harness(scenario);
    _expect(
      await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
      '${scenario.name} worker becomes ready',
    );
    final RuntimeLifecycleRequestResult request = await harness.coordinator
        .request(1);
    _expect(
      request.status == RuntimeLifecycleRequestStatus.uncaughtError,
      '${scenario.name} is classified as an uncaught worker error',
    );
    harness.expectEvents(<String>[
      'worker-start',
      'worker-ready',
      'worker-request',
      'worker-error',
      'worker-exit',
    ]);
  }
}

Future<void> _unexpectedWorkerExit() async {
  final _Harness harness = _Harness(
    RuntimeLifecycleScenario.workerUnexpectedExit,
  );
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'unexpected-exit worker becomes ready',
  );
  final RuntimeLifecycleRequestResult request = await harness.coordinator
      .request(1);
  _expect(
    request.status == RuntimeLifecycleRequestStatus.unexpectedExit,
    'exit without an error is classified separately',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-unexpected-exit',
    'worker-exit',
  ]);
}

Future<void> _idleWorkerTermination() async {
  for (final (
        RuntimeLifecycleScenario,
        RuntimeLifecycleWorkerTermination,
        List<String>,
      )
      fixture
      in <
        (
          RuntimeLifecycleScenario,
          RuntimeLifecycleWorkerTermination,
          List<String>,
        )
      >[
        (
          RuntimeLifecycleScenario.workerIdleUncaught,
          RuntimeLifecycleWorkerTermination.uncaughtError,
          <String>[
            'worker-start',
            'worker-ready',
            'worker-error',
            'worker-exit',
          ],
        ),
        (
          RuntimeLifecycleScenario.workerIdleExit,
          RuntimeLifecycleWorkerTermination.unexpectedExit,
          <String>[
            'worker-start',
            'worker-ready',
            'worker-unexpected-exit',
            'worker-exit',
          ],
        ),
      ]) {
    final _Harness harness = _Harness(fixture.$1);
    _expect(
      await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
      '${fixture.$1.name} worker becomes ready',
    );
    final RuntimeLifecycleWorkerTermination termination = await harness
        .coordinator
        .waitForTermination()
        .timeout(const Duration(seconds: 1));
    _expect(
      termination == fixture.$2,
      '${fixture.$1.name} reconciles while no request is pending',
    );
    harness.expectEvents(fixture.$3);
  }
}

Future<void> _stopProcessingFailure() async {
  final _Harness harness = _Harness(
    RuntimeLifecycleScenario.workerStopUncaught,
  );
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'stop-failure worker becomes ready',
  );
  final RuntimeLifecycleRequestResult request = await harness.coordinator
      .request(2);
  _expect(
    request.status == RuntimeLifecycleRequestStatus.response &&
        request.value == 3,
    'stop-failure worker handles work before shutdown',
  );
  final RuntimeLifecycleShutdownResult shutdown = await harness.coordinator
      .shutdown();
  _expect(!shutdown.forced, 'stop-processing crash is not a timeout');
  _expect(
    shutdown.termination == RuntimeLifecycleWorkerTermination.uncaughtError,
    'stop-processing crash retains its error classification',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-response',
    'worker-stop-request',
    'worker-error',
    'worker-exit',
  ]);
}

Future<void> _forcedShutdown() async {
  final _Harness harness = _Harness(
    RuntimeLifecycleScenario.shutdownTimeout,
    shutdownTimeout: const Duration(milliseconds: 40),
  );
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'unresponsive worker becomes ready before shutdown',
  );
  final RuntimeLifecycleShutdownResult shutdown = await harness.coordinator
      .shutdown();
  _expect(shutdown.forced, 'unresponsive worker is forcibly stopped');
  _expect(
    shutdown.termination == RuntimeLifecycleWorkerTermination.forcedCleanup,
    'unresponsive worker records forced cleanup',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-stop-request',
    'worker-stop-timeout',
    'worker-force-kill',
    'worker-exit',
  ]);
}

Future<void> _lateCompletion() async {
  final _Harness harness = _Harness(RuntimeLifecycleScenario.lateCompletion);
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'late-completion worker becomes ready',
  );
  final Future<RuntimeLifecycleRequestResult> request = harness.coordinator
      .request(8);
  final RuntimeLifecycleShutdownResult shutdown = await harness.coordinator
      .shutdown();
  final RuntimeLifecycleRequestResult requestResult = await request;
  _expect(!shutdown.forced, 'late-completion worker acknowledges shutdown');
  _expect(
    requestResult.status == RuntimeLifecycleRequestStatus.cancelled,
    'in-flight request is cancelled after generation invalidation',
  );
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-stop-request',
    'worker-stop-ack',
    'late-completion-ignored',
    'worker-exit',
  ]);
}

Future<void> _doubleShutdown() async {
  final _Harness harness = _Harness(RuntimeLifecycleScenario.doubleShutdown);
  _expect(
    await harness.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'double-shutdown worker becomes ready',
  );
  final Future<RuntimeLifecycleShutdownResult> first = harness.coordinator
      .shutdown();
  final Future<RuntimeLifecycleShutdownResult> second = harness.coordinator
      .shutdown();
  _expect(identical(first, second), 'shutdown returns one cached future');
  _expect(!(await first).forced, 'cached shutdown completes gracefully');
  harness.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-stop-request',
    'shutdown-idempotent',
    'worker-stop-ack',
    'worker-exit',
  ]);
}

void _terminationEvidenceOrdering() {
  for (final bool exitFirst in <bool>[false, true]) {
    final RuntimeLifecycleTerminationEvidence evidence =
        RuntimeLifecycleTerminationEvidence();
    if (exitFirst) {
      evidence.recordExit();
      _expect(
        !evidence.canReconcile,
        'exit alone waits for delayed error and channel barriers',
      );
      evidence.recordError();
    } else {
      evidence.recordError();
      evidence.recordExit();
    }
    evidence.recordEventChannelDrained();
    _expect(
      !evidence.canReconcile,
      'one channel barrier cannot finalize termination',
    );
    evidence.recordErrorChannelDrained();
    _expect(evidence.canReconcile, 'both channel barriers permit reconcile');
    _expect(
      evidence.classify(
            workerWasReady: true,
            shutdownRequested: false,
            stopAcknowledged: false,
            forcedCleanup: false,
          ) ==
          RuntimeLifecycleWorkerTermination.uncaughtError,
      'error/exit order preserves uncaught classification',
    );
  }

  final RuntimeLifecycleTerminationEvidence graceful =
      RuntimeLifecycleTerminationEvidence()
        ..recordExit()
        ..recordEventChannelDrained()
        ..recordErrorChannelDrained();
  _expect(
    graceful.classify(
          workerWasReady: true,
          shutdownRequested: true,
          stopAcknowledged: true,
          forcedCleanup: false,
        ) ==
        RuntimeLifecycleWorkerTermination.graceful,
    'acknowledged stop is graceful',
  );
  _expect(
    graceful.classify(
          workerWasReady: true,
          shutdownRequested: false,
          stopAcknowledged: false,
          forcedCleanup: false,
        ) ==
        RuntimeLifecycleWorkerTermination.unexpectedExit,
    'idle exit is unexpected',
  );
  _expect(
    graceful.classify(
          workerWasReady: true,
          shutdownRequested: true,
          stopAcknowledged: false,
          forcedCleanup: true,
        ) ==
        RuntimeLifecycleWorkerTermination.forcedCleanup,
    'deadline expiry is forced cleanup',
  );

  final RuntimeLifecycleTerminationEvidence stopCrash =
      RuntimeLifecycleTerminationEvidence()
        ..recordExit()
        ..recordError()
        ..recordEventChannelDrained()
        ..recordErrorChannelDrained();
  _expect(
    stopCrash.classify(
          workerWasReady: true,
          shutdownRequested: true,
          stopAcknowledged: false,
          forcedCleanup: false,
        ) ==
        RuntimeLifecycleWorkerTermination.uncaughtError,
    'stop-processing crash is not a timeout',
  );
}

final class _Harness {
  _Harness(
    RuntimeLifecycleScenario scenario, {
    Duration shutdownTimeout = const Duration(milliseconds: 250),
  }) : coordinator = RuntimeLifecycleCoordinator(
         scenario: scenario,
         observer: (RuntimeLifecycleObservation observation) {
           observations.add(observation);
         },
         shutdownTimeout: shutdownTimeout,
       );

  static final List<RuntimeLifecycleObservation> observations =
      <RuntimeLifecycleObservation>[];

  final RuntimeLifecycleCoordinator coordinator;

  void expectEvents(List<String> expected) {
    final List<RuntimeLifecycleObservation> actual = List.of(observations);
    observations.clear();
    _expect(
      actual.every(
        (RuntimeLifecycleObservation observation) =>
            observation.generation == 1,
      ),
      'all observations belong to generation one',
    );
    final List<String> events = actual
        .map((RuntimeLifecycleObservation observation) => observation.event)
        .toList();
    _expect(
      _sameStrings(events, expected),
      'events $events match expected $expected',
    );
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; ++index) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Lifecycle expectation failed: $description');
  }
}
