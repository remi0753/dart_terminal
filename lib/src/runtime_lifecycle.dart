import 'dart:async';
import 'dart:isolate';

enum RuntimeLifecycleScenario {
  normal('normal'),
  workerSyncUncaught('worker-sync-uncaught'),
  workerAsyncUncaught('worker-async-uncaught'),
  workerUnexpectedExit('worker-unexpected-exit'),
  workerStartupFailure('worker-startup-failure'),
  workerIdleUncaught('worker-idle-uncaught'),
  workerIdleExit('worker-idle-exit'),
  workerStopUncaught('worker-stop-uncaught'),
  shutdownTimeout('shutdown-timeout'),
  lateCompletion('late-completion'),
  doubleShutdown('double-shutdown'),
  rootStartupFailure('root-startup-failure'),
  rootUncaught('root-uncaught');

  const RuntimeLifecycleScenario(this.name);

  final String name;

  static RuntimeLifecycleScenario? byName(String name) {
    for (final RuntimeLifecycleScenario candidate in values) {
      if (candidate.name == name) {
        return candidate;
      }
    }
    return null;
  }
}

final class RuntimeLifecycleObservation {
  const RuntimeLifecycleObservation({
    required this.event,
    required this.generation,
  });

  final String event;
  final int generation;

  String machineLine(RuntimeLifecycleScenario scenario) =>
      'RUNTIME_LIFECYCLE event=$event scenario=${scenario.name} '
      'generation=$generation';
}

typedef RuntimeLifecycleObserver = void Function(
  RuntimeLifecycleObservation observation,
);

enum RuntimeLifecycleStartStatus { ready, startupFailure }

enum RuntimeLifecycleRequestStatus {
  response,
  uncaughtError,
  unexpectedExit,
  cancelled,
}

final class RuntimeLifecycleRequestResult {
  const RuntimeLifecycleRequestResult(this.status, {this.value});

  final RuntimeLifecycleRequestStatus status;
  final int? value;
}

final class RuntimeLifecycleShutdownResult {
  const RuntimeLifecycleShutdownResult({required this.termination});

  final RuntimeLifecycleWorkerTermination termination;

  bool get forced =>
      termination == RuntimeLifecycleWorkerTermination.forcedCleanup;
}

enum RuntimeLifecycleWorkerTermination {
  graceful,
  startupFailure,
  uncaughtError,
  unexpectedExit,
  forcedCleanup,
}

/// Accumulates termination evidence before one authoritative classification.
///
/// This type is public only so the repository test harness can exercise both
/// listener arrival orders. It is not exported by `dart_terminal.dart`.
final class RuntimeLifecycleTerminationEvidence {
  bool _sawError = false;
  bool _sawExit = false;
  bool _eventChannelDrained = false;
  bool _errorChannelDrained = false;

  bool get sawError => _sawError;
  bool get sawExit => _sawExit;
  bool get canReconcile =>
      _sawExit && _eventChannelDrained && _errorChannelDrained;

  void recordError() {
    if (_errorChannelDrained) {
      throw StateError('worker error arrived after its channel barrier');
    }
    _sawError = true;
  }

  void recordExit() {
    _sawExit = true;
  }

  void recordEventChannelDrained() {
    _eventChannelDrained = true;
  }

  void recordErrorChannelDrained() {
    _errorChannelDrained = true;
  }

  RuntimeLifecycleWorkerTermination classify({
    required bool workerWasReady,
    required bool shutdownRequested,
    required bool stopAcknowledged,
    required bool forcedCleanup,
  }) {
    if (!canReconcile) {
      throw StateError('worker termination evidence is not fully drained');
    }
    if (!workerWasReady) {
      return RuntimeLifecycleWorkerTermination.startupFailure;
    }
    if (forcedCleanup) {
      return RuntimeLifecycleWorkerTermination.forcedCleanup;
    }
    if (_sawError) {
      return RuntimeLifecycleWorkerTermination.uncaughtError;
    }
    if (shutdownRequested && stopAcknowledged) {
      return RuntimeLifecycleWorkerTermination.graceful;
    }
    return RuntimeLifecycleWorkerTermination.unexpectedExit;
  }
}

final class _ChannelDrainMarker {
  const _ChannelDrainMarker(this.generation);

  final int generation;
}

enum _ShutdownSignal { stopAcknowledged, workerExited }

enum _CoordinatorState { idle, starting, running, stopping, stopped }

final class RuntimeLifecycleCoordinator {
  RuntimeLifecycleCoordinator({
    required this.scenario,
    required this.observer,
    this.startupTimeout = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 1),
    this.shutdownTimeout = const Duration(milliseconds: 250),
    this.forcedExitTimeout = const Duration(milliseconds: 250),
  });

  final RuntimeLifecycleScenario scenario;
  final RuntimeLifecycleObserver observer;
  final Duration startupTimeout;
  final Duration requestTimeout;
  final Duration shutdownTimeout;
  final Duration forcedExitTimeout;

  _CoordinatorState _state = _CoordinatorState.idle;
  int _generation = 0;
  int _nextOperation = 1;
  bool _acceptResponses = false;
  bool _workerWasReady = false;
  bool _shutdownRequested = false;
  bool _forcedCleanup = false;
  bool _emittedWorkerError = false;
  bool _emittedExit = false;
  bool _emittedLateCompletion = false;
  final RuntimeLifecycleTerminationEvidence _terminationEvidence =
      RuntimeLifecycleTerminationEvidence();

  Isolate? _worker;
  SendPort? _commands;
  ReceivePort? _events;
  ReceivePort? _errors;
  ReceivePort? _exits;
  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Completer<void>? _ready;
  Completer<void>? _exitSignal;
  Completer<void>? _eventChannelDrained;
  Completer<void>? _errorChannelDrained;
  Completer<void>? _stopAcknowledged;
  Completer<RuntimeLifecycleWorkerTermination>? _termination;
  final Map<int, Completer<int>> _responses = <int, Completer<int>>{};
  Future<RuntimeLifecycleShutdownResult>? _shutdownFuture;

  int get generation => _generation;

  Future<RuntimeLifecycleStartStatus> start() async {
    if (_state != _CoordinatorState.idle) {
      throw StateError('runtime lifecycle coordinator may start only once');
    }
    _state = _CoordinatorState.starting;
    ++_generation;
    _emit('worker-start');
    _ready = Completer<void>();
    _exitSignal = Completer<void>();
    _eventChannelDrained = Completer<void>();
    _errorChannelDrained = Completer<void>();
    _termination = Completer<RuntimeLifecycleWorkerTermination>();
    _events = ReceivePort('dart-terminal-lifecycle-events');
    _errors = ReceivePort('dart-terminal-lifecycle-errors');
    _exits = ReceivePort('dart-terminal-lifecycle-exits');
    _eventSubscription = _events!.listen(_handleWorkerEvent);
    _errorSubscription = _errors!.listen(_handleWorkerError);
    _exitSubscription = _exits!.listen(_handleWorkerExit);

    try {
      _worker = await Isolate.spawn<List<Object?>>(
        runtimeLifecycleWorkerMain,
        <Object?>[_events!.sendPort, scenario.name, _generation],
        onError: _errors!.sendPort,
        onExit: _exits!.sendPort,
        errorsAreFatal: true,
        debugName: 'dart-terminal-lifecycle-worker',
      );
    } on Object {
      _emit('worker-startup-failure');
      _state = _CoordinatorState.stopped;
      await _closePorts();
      _completeTermination(RuntimeLifecycleWorkerTermination.startupFailure);
      return RuntimeLifecycleStartStatus.startupFailure;
    }

    try {
      await Future.any<void>(<Future<void>>[
        _ready!.future,
        _exitSignal!.future,
      ]).timeout(startupTimeout);
      if (_workerWasReady) {
        return RuntimeLifecycleStartStatus.ready;
      }
    } on TimeoutException {
      if (_workerWasReady) {
        return RuntimeLifecycleStartStatus.ready;
      }
      if (!_exitSignal!.isCompleted) {
        _worker?.kill(priority: Isolate.immediate);
        await _exitSignal!.future.timeout(forcedExitTimeout);
      }
    }

    await _termination!.future;
    return RuntimeLifecycleStartStatus.startupFailure;
  }

  Future<RuntimeLifecycleWorkerTermination> waitForTermination() {
    final Completer<RuntimeLifecycleWorkerTermination>? termination =
        _termination;
    if (termination == null) {
      throw StateError('runtime lifecycle worker has not been started');
    }
    return termination.future;
  }

  Future<RuntimeLifecycleRequestResult> request(int value) async {
    if (_state != _CoordinatorState.running ||
        _commands == null ||
        _terminationEvidence.sawExit) {
      throw StateError('runtime lifecycle worker is not ready');
    }
    final int operation = _nextOperation++;
    final Completer<int> response = Completer<int>();
    _responses[operation] = response;
    _emit('worker-request');
    _commands!.send(<Object?>['request', _generation, operation, value]);

    try {
      final ({bool exited, int? value}) result = await Future.any(
        <Future<({bool exited, int? value})>>[
          response.future.then((int reply) => (exited: false, value: reply)),
          _exitSignal!.future.then((_) => (exited: true, value: null)),
        ],
      ).timeout(requestTimeout);
      if (!result.exited) {
        return RuntimeLifecycleRequestResult(
          RuntimeLifecycleRequestStatus.response,
          value: result.value,
        );
      }
    } on TimeoutException {
      if (!_exitSignal!.isCompleted) {
        _worker?.kill(priority: Isolate.immediate);
        await _exitSignal!.future.timeout(forcedExitTimeout);
      }
    } finally {
      _responses.remove(operation);
    }

    final RuntimeLifecycleWorkerTermination termination =
        await _termination!.future;
    if (_shutdownRequested || _shutdownFuture != null) {
      return const RuntimeLifecycleRequestResult(
        RuntimeLifecycleRequestStatus.cancelled,
      );
    }
    return RuntimeLifecycleRequestResult(
      termination == RuntimeLifecycleWorkerTermination.uncaughtError
          ? RuntimeLifecycleRequestStatus.uncaughtError
          : RuntimeLifecycleRequestStatus.unexpectedExit,
    );
  }

  Future<RuntimeLifecycleShutdownResult> shutdown() {
    final Future<RuntimeLifecycleShutdownResult>? existing = _shutdownFuture;
    if (existing != null) {
      _emit('shutdown-idempotent');
      return existing;
    }
    final Future<RuntimeLifecycleShutdownResult> created = _performShutdown();
    _shutdownFuture = created;
    return created;
  }

  Future<RuntimeLifecycleShutdownResult> _performShutdown() async {
    if (_state == _CoordinatorState.idle) {
      _state = _CoordinatorState.stopped;
      await _closePorts();
      return const RuntimeLifecycleShutdownResult(
        termination: RuntimeLifecycleWorkerTermination.graceful,
      );
    }
    if (_state == _CoordinatorState.stopped) {
      final Completer<RuntimeLifecycleWorkerTermination>? termination =
          _termination;
      return RuntimeLifecycleShutdownResult(
        termination: termination == null
            ? RuntimeLifecycleWorkerTermination.graceful
            : await termination.future,
      );
    }
    if (_state == _CoordinatorState.starting) {
      throw StateError('cannot shut down while worker startup is pending');
    }
    if (_exitSignal?.isCompleted ?? false) {
      return RuntimeLifecycleShutdownResult(
        termination: await _termination!.future,
      );
    }

    _state = _CoordinatorState.stopping;
    _shutdownRequested = true;
    _acceptResponses = false;
    _stopAcknowledged = Completer<void>();
    _emit('worker-stop-request');
    _commands?.send(<Object?>['stop', _generation]);
    final Stopwatch deadline = Stopwatch()..start();
    try {
      final _ShutdownSignal first = await _beforeDeadline(
        Future.any<_ShutdownSignal>(<Future<_ShutdownSignal>>[
          _stopAcknowledged!.future.then(
            (_) => _ShutdownSignal.stopAcknowledged,
          ),
          _exitSignal!.future.then((_) => _ShutdownSignal.workerExited),
        ]),
        deadline,
        shutdownTimeout,
      );
      if (first == _ShutdownSignal.stopAcknowledged) {
        await _beforeDeadline(_exitSignal!.future, deadline, shutdownTimeout);
      }
    } on TimeoutException {
      if (!_exitSignal!.isCompleted) {
        _forcedCleanup = true;
        _emit('worker-stop-timeout');
        _emit('worker-force-kill');
        _worker?.kill(priority: Isolate.immediate);
        await _exitSignal!.future.timeout(forcedExitTimeout);
      }
    }
    final RuntimeLifecycleWorkerTermination termination =
        await _termination!.future;
    return RuntimeLifecycleShutdownResult(termination: termination);
  }

  Future<T> _beforeDeadline<T>(
    Future<T> future,
    Stopwatch stopwatch,
    Duration deadline,
  ) {
    final Duration remaining = deadline - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(TimeoutException('lifecycle deadline'));
    }
    return future.timeout(remaining);
  }

  void _handleWorkerEvent(Object? message) {
    if (message is _ChannelDrainMarker && message.generation == _generation) {
      _terminationEvidence.recordEventChannelDrained();
      if (!(_eventChannelDrained?.isCompleted ?? true)) {
        _eventChannelDrained!.complete();
      }
      return;
    }
    if (message is! List<Object?> || message.isEmpty) {
      return;
    }
    switch (message.first) {
      case 'ready':
        if (message.length != 3 ||
            message[1] != _generation ||
            message[2] is! SendPort ||
            _state != _CoordinatorState.starting) {
          return;
        }
        _commands = message[2]! as SendPort;
        _workerWasReady = true;
        _state = _CoordinatorState.running;
        _acceptResponses = true;
        _emit('worker-ready');
        if (!_ready!.isCompleted) {
          _ready!.complete();
        }
        return;
      case 'response':
        if (message.length != 4 ||
            message[1] != _generation ||
            message[2] is! int ||
            message[3] is! int) {
          return;
        }
        if (!_acceptResponses || _state != _CoordinatorState.running) {
          if (!_emittedLateCompletion) {
            _emittedLateCompletion = true;
            _emit('late-completion-ignored');
          }
          return;
        }
        final Completer<int>? response = _responses[message[2]! as int];
        if (response != null && !response.isCompleted) {
          _emit('worker-response');
          response.complete(message[3]! as int);
        }
        return;
      case 'stop-ack':
        if (message.length == 2 && message[1] == _generation) {
          _emit('worker-stop-ack');
          if (!(_stopAcknowledged?.isCompleted ?? true)) {
            _stopAcknowledged!.complete();
          }
        }
        return;
    }
  }

  void _handleWorkerError(Object? message) {
    if (message is _ChannelDrainMarker && message.generation == _generation) {
      _terminationEvidence.recordErrorChannelDrained();
      if (!(_errorChannelDrained?.isCompleted ?? true)) {
        _errorChannelDrained!.complete();
      }
      return;
    }
    _terminationEvidence.recordError();
  }

  void _handleWorkerExit(Object? message) {
    if (_terminationEvidence.sawExit) {
      return;
    }
    _terminationEvidence.recordExit();
    if (!(_exitSignal?.isCompleted ?? true)) {
      _exitSignal!.complete();
    }
    unawaited(_reconcileWorkerTermination());
  }

  Future<void> _reconcileWorkerTermination() async {
    final ReceivePort? events = _events;
    final ReceivePort? errors = _errors;
    if (events == null || errors == null) {
      throw StateError('worker termination ports closed before reconciliation');
    }
    events.sendPort.send(_ChannelDrainMarker(_generation));
    errors.sendPort.send(_ChannelDrainMarker(_generation));
    await Future.wait<void>(<Future<void>>[
      _eventChannelDrained!.future,
      _errorChannelDrained!.future,
    ]);
    if (!_terminationEvidence.canReconcile) {
      throw StateError(
        'worker termination channels did not reach their barrier',
      );
    }

    final RuntimeLifecycleWorkerTermination termination = _terminationEvidence
        .classify(
          workerWasReady: _workerWasReady,
          shutdownRequested: _shutdownRequested,
          stopAcknowledged: _stopAcknowledged?.isCompleted ?? false,
          forcedCleanup: _forcedCleanup,
        );
    if (_terminationEvidence.sawError && !_emittedWorkerError) {
      _emittedWorkerError = true;
      _emit('worker-error');
    }
    switch (termination) {
      case RuntimeLifecycleWorkerTermination.startupFailure:
        _emit('worker-startup-failure');
        break;
      case RuntimeLifecycleWorkerTermination.unexpectedExit:
        _emit('worker-unexpected-exit');
        break;
      case RuntimeLifecycleWorkerTermination.graceful:
      case RuntimeLifecycleWorkerTermination.uncaughtError:
      case RuntimeLifecycleWorkerTermination.forcedCleanup:
        break;
    }
    _emitWorkerExit();
    _state = _CoordinatorState.stopped;
    _acceptResponses = false;
    await _closePorts();
    _completeTermination(termination);
  }

  void _completeTermination(RuntimeLifecycleWorkerTermination termination) {
    if (!(_termination?.isCompleted ?? true)) {
      _termination!.complete(termination);
    }
  }

  void _emitWorkerExit() {
    if (!_emittedExit) {
      _emittedExit = true;
      _emit('worker-exit');
    }
  }

  void _emit(String event) {
    observer(
      RuntimeLifecycleObservation(event: event, generation: _generation),
    );
  }

  Future<void> _closePorts() async {
    _acceptResponses = false;
    await _eventSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _events?.close();
    _errors?.close();
    _exits?.close();
    _eventSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;
    _events = null;
    _errors = null;
    _exits = null;
    _commands = null;
    _worker = null;
  }
}

@pragma('vm:entry-point')
void runtimeLifecycleWorkerMain(List<Object?> bootstrap) {
  final SendPort events = bootstrap[0]! as SendPort;
  final String scenario = bootstrap[1]! as String;
  final int generation = bootstrap[2]! as int;
  if (scenario == RuntimeLifecycleScenario.workerStartupFailure.name) {
    throw StateError('requested lifecycle worker startup failure');
  }

  final ReceivePort commands = ReceivePort('dart-terminal-lifecycle-commands');
  events.send(<Object?>['ready', generation, commands.sendPort]);
  if (scenario == RuntimeLifecycleScenario.workerIdleUncaught.name) {
    Timer(const Duration(milliseconds: 35), () {
      throw StateError('requested idle worker failure');
    });
  } else if (scenario == RuntimeLifecycleScenario.workerIdleExit.name) {
    Timer(const Duration(milliseconds: 35), Isolate.exit);
  }
  commands.listen((Object? message) {
    if (message is! List<Object?> || message.isEmpty) {
      return;
    }
    switch (message.first) {
      case 'request':
        final int requestGeneration = message[1]! as int;
        final int operation = message[2]! as int;
        final int value = message[3]! as int;
        if (scenario == RuntimeLifecycleScenario.workerSyncUncaught.name) {
          throw StateError('requested synchronous worker failure');
        }
        if (scenario == RuntimeLifecycleScenario.workerAsyncUncaught.name) {
          Timer.run(() {
            throw StateError('requested asynchronous worker failure');
          });
          return;
        }
        if (scenario == RuntimeLifecycleScenario.workerUnexpectedExit.name) {
          Isolate.exit();
        }
        if (scenario == RuntimeLifecycleScenario.lateCompletion.name) {
          Timer(const Duration(milliseconds: 35), () {
            events.send(<Object?>[
              'response',
              requestGeneration,
              operation,
              value + 1,
            ]);
          });
          return;
        }
        events.send(<Object?>[
          'response',
          requestGeneration,
          operation,
          value + 1,
        ]);
        return;
      case 'stop':
        if (scenario == RuntimeLifecycleScenario.shutdownTimeout.name) {
          return;
        }
        if (scenario == RuntimeLifecycleScenario.workerStopUncaught.name) {
          throw StateError('requested worker failure while stopping');
        }
        events.send(<Object?>['stop-ack', generation]);
        if (scenario == RuntimeLifecycleScenario.lateCompletion.name) {
          Timer(const Duration(milliseconds: 70), commands.close);
        } else {
          commands.close();
        }
        return;
    }
  });
}
