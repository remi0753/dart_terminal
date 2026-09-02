import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/runtime_worker_protocol.dart';

Future<void> runRuntimeLifecycleTests() async {
  await _protocolContract();
  _sourceBoundary();
  await _normalLifecycle();
  await _startupFailure();
  await _uncaughtWorkerFailures();
  await _unexpectedWorkerExit();
  await _idleWorkerTermination();
  await _stopProcessingFailure();
  await _forcedShutdown();
  await _lateCompletion();
  await _doubleShutdown();
  await _replacementAfterFailure();
  await _processLaunchFailure();
  _terminationEvidenceOrdering();
  _expect(
    RuntimeLifecycleCoordinator.outstandingProcessCount == 0,
    'all child processes are reaped after the suite',
  );
}

Future<void> _protocolContract() async {
  final RuntimeWorkerFrame frame = RuntimeWorkerFrame(
    type: RuntimeWorkerMessageType.response,
    generation: 7,
    operation: 11,
    payload: RuntimeWorkerFrameCodec.int64Payload(-42),
  );
  final Uint8List encoded = RuntimeWorkerFrameCodec.encode(frame);
  final StreamController<List<int>> chunks = StreamController<List<int>>();
  final RuntimeWorkerFrameDecoder decoder = RuntimeWorkerFrameDecoder(
    chunks.stream,
  );
  final Future<List<RuntimeWorkerFrame>> decoded = decoder.frames.toList();
  for (var index = 0; index < encoded.length; ++index) {
    chunks.add(encoded.sublist(index, index + 1));
  }
  await chunks.close();
  final List<RuntimeWorkerFrame> frames = await decoded;
  _expect(frames.length == 1, 'split frame decodes exactly once');
  _expect(
    frames.single.type == RuntimeWorkerMessageType.response &&
        frames.single.generation == 7 &&
        frames.single.operation == 11 &&
        RuntimeWorkerFrameCodec.readInt64Payload(frames.single) == -42,
    'frame fields and signed payload survive chunking',
  );

  final Uint8List badMagic = Uint8List.fromList(encoded)..[0] = 0;
  await _expectAsyncThrows<FormatException>(
    RuntimeWorkerFrameDecoder(
      Stream<List<int>>.fromIterable(<List<int>>[badMagic]),
    ).frames.toList(),
    'invalid protocol magic',
  );
  await _expectAsyncThrows<FormatException>(
    RuntimeWorkerFrameDecoder(
      Stream<List<int>>.fromIterable(<List<int>>[
        encoded.sublist(0, runtimeWorkerHeaderLength - 1),
      ]),
    ).frames.toList(),
    'partial final frame',
  );
  await _expectAsyncThrows<FormatException>(
    Future<void>.sync(() {
      RuntimeWorkerFrameCodec.encode(
        RuntimeWorkerFrame(
          type: RuntimeWorkerMessageType.request,
          generation: 1,
          operation: 1,
          payload: Uint8List(runtimeWorkerMaximumPayloadLength + 1),
        ),
      );
    }),
    'oversized payload',
  );
}

void _sourceBoundary() {
  final String coordinator = File(
    '${Directory.current.path}/lib/src/runtime_lifecycle.dart',
  ).readAsStringSync();
  _expect(
    !coordinator.contains("import 'dart:isolate';") &&
        !coordinator.contains('Isolate.spawn'),
    'product lifecycle has no in-process isolate transport',
  );
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
  _expect(
    harness.coordinator.workerDiagnostics.contains(
      'requested lifecycle worker startup failure',
    ),
    'startup failure preserves child stderr',
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
    _expect(
      harness.coordinator.workerDiagnostics.contains('requested') &&
          harness.coordinator.workerDiagnostics.contains('worker failure'),
      '${scenario.name} preserves its child stderr diagnostic',
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
    if (fixture.$1 == RuntimeLifecycleScenario.workerIdleUncaught) {
      _expect(
        harness.coordinator.workerDiagnostics.contains(
          'requested idle worker failure',
        ),
        'idle uncaught failure preserves child stderr',
      );
    }
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
  _expect(
    harness.coordinator.workerDiagnostics.contains(
      'requested worker failure while stopping',
    ),
    'stop-processing failure preserves child stderr',
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

Future<void> _replacementAfterFailure() async {
  final _Harness failed = _Harness(RuntimeLifecycleScenario.workerSyncUncaught);
  _expect(
    await failed.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'replacement fixture starts failed generation',
  );
  final int failedPid = failed.coordinator.workerPid!;
  await failed.coordinator.request(1);
  failed.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-error',
    'worker-exit',
  ]);

  final _Harness replacement = _Harness(RuntimeLifecycleScenario.normal);
  _expect(
    await replacement.coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'replacement worker becomes ready',
  );
  _expect(
    replacement.coordinator.workerPid != failedPid,
    'replacement owns a distinct process',
  );
  final RuntimeLifecycleRequestResult response = await replacement.coordinator
      .request(9);
  _expect(
    response.status == RuntimeLifecycleRequestStatus.response &&
        response.value == 10,
    'replacement responds without stale state',
  );
  await replacement.coordinator.shutdown();
  replacement.expectEvents(<String>[
    'worker-start',
    'worker-ready',
    'worker-request',
    'worker-response',
    'worker-stop-request',
    'worker-stop-ack',
    'worker-exit',
  ]);
}

Future<void> _processLaunchFailure() async {
  final List<RuntimeLifecycleObservation> observations =
      <RuntimeLifecycleObservation>[];
  final RuntimeLifecycleCoordinator coordinator = RuntimeLifecycleCoordinator(
    scenario: RuntimeLifecycleScenario.normal,
    observer: observations.add,
    workerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/path/that/does/not/exist/dart',
    ),
  );
  _expect(
    await coordinator.start() == RuntimeLifecycleStartStatus.startupFailure,
    'missing executable is a bounded startup failure',
  );
  _expect(
    _sameStrings(
      observations
          .map((RuntimeLifecycleObservation observation) => observation.event)
          .toList(),
      <String>['worker-start', 'worker-startup-failure'],
    ),
    'process launch failure has deterministic events',
  );
  _expect(
    RuntimeLifecycleCoordinator.outstandingProcessCount == 0,
    'failed launch does not create outstanding process ownership',
  );
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
    evidence.recordProtocolStreamDrained();
    _expect(
      !evidence.canReconcile,
      'one channel barrier cannot finalize termination',
    );
    evidence.recordDiagnosticsStreamDrained();
    _expect(evidence.canReconcile, 'both channel barriers permit reconcile');
    _expect(
      evidence.classify(
            workerWasReady: true,
            shutdownRequested: false,
            stopAcknowledged: false,
            forcedCleanup: false,
            processExitedSuccessfully: false,
          ) ==
          RuntimeLifecycleWorkerTermination.uncaughtError,
      'error/exit order preserves uncaught classification',
    );
  }

  final RuntimeLifecycleTerminationEvidence graceful =
      RuntimeLifecycleTerminationEvidence()
        ..recordExit()
        ..recordProtocolStreamDrained()
        ..recordDiagnosticsStreamDrained();
  _expect(
    graceful.classify(
          workerWasReady: true,
          shutdownRequested: true,
          stopAcknowledged: true,
          forcedCleanup: false,
          processExitedSuccessfully: true,
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
          processExitedSuccessfully: true,
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
          processExitedSuccessfully: false,
        ) ==
        RuntimeLifecycleWorkerTermination.forcedCleanup,
    'deadline expiry is forced cleanup',
  );

  final RuntimeLifecycleTerminationEvidence stopCrash =
      RuntimeLifecycleTerminationEvidence()
        ..recordExit()
        ..recordError()
        ..recordProtocolStreamDrained()
        ..recordDiagnosticsStreamDrained();
  _expect(
    stopCrash.classify(
          workerWasReady: true,
          shutdownRequested: true,
          stopAcknowledged: false,
          forcedCleanup: false,
          processExitedSuccessfully: false,
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
         workerCommand: _workerCommand,
         shutdownTimeout: shutdownTimeout,
       );

  static final List<RuntimeLifecycleObservation> observations =
      <RuntimeLifecycleObservation>[];
  static final RuntimeLifecycleWorkerCommand _workerCommand =
      RuntimeLifecycleWorkerCommand(
        executable: Platform.resolvedExecutable,
        arguments: <String>[
          '${Directory.current.path}/bin/runtime_worker.dart',
        ],
        workingDirectory: Directory.current.path,
      );

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
    _expect(
      RuntimeLifecycleCoordinator.outstandingProcessCount == 0,
      'event reconciliation leaves no child process outstanding',
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

Future<void> _expectAsyncThrows<T extends Object>(
  Future<void> future,
  String description,
) async {
  try {
    await future;
  } on T {
    return;
  }
  throw StateError('Expected $T: $description');
}
