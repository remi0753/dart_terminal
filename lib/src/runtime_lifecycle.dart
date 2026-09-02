import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'runtime_worker_protocol.dart';

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

/// Accumulates child-process termination evidence before classification.
///
/// This type is public only so the repository test harness can exercise exit,
/// protocol-stream, and diagnostic-stream arrival orders. It is not exported
/// by `dart_terminal.dart`.
final class RuntimeLifecycleTerminationEvidence {
  bool _sawError = false;
  bool _sawExit = false;
  bool _protocolStreamDrained = false;
  bool _diagnosticsStreamDrained = false;

  bool get sawError => _sawError;
  bool get sawExit => _sawExit;
  bool get canReconcile =>
      _sawExit && _protocolStreamDrained && _diagnosticsStreamDrained;

  void recordError() {
    if (_diagnosticsStreamDrained) {
      throw StateError('worker diagnostic arrived after its stream barrier');
    }
    _sawError = true;
  }

  void recordExit() {
    _sawExit = true;
  }

  void recordProtocolStreamDrained() {
    _protocolStreamDrained = true;
  }

  void recordDiagnosticsStreamDrained() {
    _diagnosticsStreamDrained = true;
  }

  RuntimeLifecycleWorkerTermination classify({
    required bool workerWasReady,
    required bool shutdownRequested,
    required bool stopAcknowledged,
    required bool forcedCleanup,
    required bool processExitedSuccessfully,
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
    if (shutdownRequested && stopAcknowledged && processExitedSuccessfully) {
      return RuntimeLifecycleWorkerTermination.graceful;
    }
    return RuntimeLifecycleWorkerTermination.unexpectedExit;
  }
}

final class RuntimeLifecycleWorkerCommand {
  const RuntimeLifecycleWorkerCommand({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
  });

  const RuntimeLifecycleWorkerCommand.unconfigured()
    : executable = '',
      arguments = const <String>[],
      workingDirectory = null,
      environment = const <String, String>{};

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;

  List<String> invocationArguments(
    RuntimeLifecycleScenario scenario,
    int generation,
  ) => <String>[
    ...arguments,
    '--scenario=${scenario.name}',
    '--generation=$generation',
  ];
}

enum _ShutdownSignal { stopAcknowledged, workerExited }

enum _CoordinatorState { idle, starting, running, stopping, stopped }

final class RuntimeLifecycleCoordinator {
  RuntimeLifecycleCoordinator({
    required this.scenario,
    required this.observer,
    this.workerCommand = const RuntimeLifecycleWorkerCommand.unconfigured(),
    this.startupTimeout = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 1),
    this.shutdownTimeout = const Duration(milliseconds: 250),
    this.forcedExitTimeout = const Duration(milliseconds: 250),
  });

  static const int _maximumDiagnosticBytes = 64 * 1024;
  static int _outstandingProcessCount = 0;

  final RuntimeLifecycleScenario scenario;
  final RuntimeLifecycleObserver observer;
  final RuntimeLifecycleWorkerCommand workerCommand;
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
  bool _diagnosticsTruncated = false;
  bool _processReaped = false;
  Object? _protocolFailure;
  int? _processExitStatus;
  int? _workerPid;
  final BytesBuilder _diagnostics = BytesBuilder(copy: false);
  final RuntimeLifecycleTerminationEvidence _terminationEvidence =
      RuntimeLifecycleTerminationEvidence();

  Process? _worker;
  RuntimeWorkerFrameDecoder? _decoder;
  RuntimeWorkerFrameWriter? _writer;
  StreamSubscription<RuntimeWorkerFrame>? _protocolSubscription;
  StreamSubscription<List<int>>? _diagnosticSubscription;
  Completer<void>? _ready;
  Completer<void>? _exitSignal;
  Completer<void>? _protocolStreamDrained;
  Completer<void>? _diagnosticsStreamDrained;
  Completer<void>? _stopAcknowledged;
  Completer<RuntimeLifecycleWorkerTermination>? _termination;
  final Map<int, Completer<int>> _responses = <int, Completer<int>>{};
  Future<RuntimeLifecycleShutdownResult>? _shutdownFuture;
  Future<void>? _reconcileFuture;

  static int get outstandingProcessCount => _outstandingProcessCount;

  int get generation => _generation;
  int? get workerPid => _workerPid;
  Object? get protocolFailure => _protocolFailure;

  String get workerDiagnostics {
    final String text = utf8.decode(
      _diagnostics.toBytes(),
      allowMalformed: true,
    );
    return _diagnosticsTruncated ? '$text\n[diagnostics truncated]' : text;
  }

  Future<RuntimeLifecycleStartStatus> start() async {
    if (_state != _CoordinatorState.idle) {
      throw StateError('runtime lifecycle coordinator may start only once');
    }
    _state = _CoordinatorState.starting;
    ++_generation;
    _emit('worker-start');
    _ready = Completer<void>();
    _exitSignal = Completer<void>();
    _protocolStreamDrained = Completer<void>();
    _diagnosticsStreamDrained = Completer<void>();
    _termination = Completer<RuntimeLifecycleWorkerTermination>();

    if (workerCommand.executable.isEmpty) {
      _state = _CoordinatorState.stopped;
      _emit('worker-startup-failure');
      _completeTermination(RuntimeLifecycleWorkerTermination.startupFailure);
      return RuntimeLifecycleStartStatus.startupFailure;
    }

    try {
      final Process worker = await Process.start(
        workerCommand.executable,
        workerCommand.invocationArguments(scenario, _generation),
        workingDirectory: workerCommand.workingDirectory,
        environment: workerCommand.environment.isEmpty
            ? null
            : workerCommand.environment,
      );
      _worker = worker;
      _workerPid = worker.pid;
      ++_outstandingProcessCount;
      _writer = RuntimeWorkerFrameWriter(worker.stdin);
      final RuntimeWorkerFrameDecoder decoder = RuntimeWorkerFrameDecoder(
        worker.stdout,
      );
      _decoder = decoder;
      _protocolSubscription = decoder.frames.listen(
        _handleWorkerFrame,
        onError: _handleProtocolError,
        onDone: _handleProtocolDone,
        cancelOnError: false,
      );
      _diagnosticSubscription = worker.stderr.listen(
        _handleWorkerDiagnostics,
        onError: _handleDiagnosticError,
        onDone: _handleDiagnosticsDone,
        cancelOnError: false,
      );
      unawaited(worker.exitCode.then(_handleWorkerExit));
    } on Object {
      _state = _CoordinatorState.stopped;
      _emit('worker-startup-failure');
      await _closeTransport();
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
        _killWorker();
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
        _writer == null ||
        _terminationEvidence.sawExit) {
      throw StateError('runtime lifecycle worker is not ready');
    }
    final int operation = _nextOperation++;
    if (operation > 0xffffffff) {
      throw StateError('runtime lifecycle operation space is exhausted');
    }
    final Completer<int> response = Completer<int>();
    _responses[operation] = response;
    _emit('worker-request');
    try {
      await _writer!.send(
        RuntimeWorkerFrame(
          type: RuntimeWorkerMessageType.request,
          generation: _generation,
          operation: operation,
          payload: RuntimeWorkerFrameCodec.int64Payload(value),
        ),
      );
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
        _killWorker();
        await _exitSignal!.future.timeout(forcedExitTimeout);
      }
    } on Object {
      if (!_exitSignal!.isCompleted) {
        _killWorker();
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
      await _closeTransport();
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
    final Stopwatch deadline = Stopwatch()..start();
    try {
      await _writer!.send(
        RuntimeWorkerFrame(
          type: RuntimeWorkerMessageType.stop,
          generation: _generation,
          operation: 0,
          payload: Uint8List(0),
        ),
      );
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
        _killWorker();
        await _exitSignal!.future.timeout(forcedExitTimeout);
      }
    } on Object {
      if (!_exitSignal!.isCompleted) {
        _forcedCleanup = true;
        _emit('worker-force-kill');
        _killWorker();
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

  void _handleWorkerFrame(RuntimeWorkerFrame frame) {
    try {
      if (frame.generation != _generation) {
        throw FormatException(
          'worker generation ${frame.generation} != $_generation',
        );
      }
      switch (frame.type) {
        case RuntimeWorkerMessageType.ready:
          if (frame.operation != 0 ||
              _state != _CoordinatorState.starting ||
              RuntimeWorkerFrameCodec.readInt64Payload(frame) != _workerPid) {
            throw const FormatException('invalid worker ready frame');
          }
          _workerWasReady = true;
          _state = _CoordinatorState.running;
          _acceptResponses = true;
          _emit('worker-ready');
          if (!_ready!.isCompleted) {
            _ready!.complete();
          }
          return;
        case RuntimeWorkerMessageType.response:
          if (frame.operation == 0) {
            throw const FormatException('response operation must be nonzero');
          }
          final int value = RuntimeWorkerFrameCodec.readInt64Payload(frame);
          if (!_acceptResponses || _state != _CoordinatorState.running) {
            if (!_emittedLateCompletion) {
              _emittedLateCompletion = true;
              _emit('late-completion-ignored');
            }
            return;
          }
          final Completer<int>? response = _responses[frame.operation];
          if (response != null && !response.isCompleted) {
            _emit('worker-response');
            response.complete(value);
          }
          return;
        case RuntimeWorkerMessageType.stopAcknowledged:
          if (frame.operation != 0 || frame.payload.isNotEmpty) {
            throw const FormatException('invalid stop acknowledgement');
          }
          if (_state == _CoordinatorState.stopping) {
            _emit('worker-stop-ack');
            if (!(_stopAcknowledged?.isCompleted ?? true)) {
              _stopAcknowledged!.complete();
            }
          }
          return;
        case RuntimeWorkerMessageType.request:
        case RuntimeWorkerMessageType.stop:
          throw FormatException(
            'worker sent parent-only frame ${frame.type.name}',
          );
      }
    } on Object catch (error, stackTrace) {
      _handleProtocolError(error, stackTrace);
    }
  }

  void _handleProtocolError(Object error, StackTrace stackTrace) {
    if (_protocolFailure != null) {
      return;
    }
    _protocolFailure = error;
    if (!(_exitSignal?.isCompleted ?? true)) {
      _killWorker();
    }
  }

  void _handleProtocolDone() {
    if (!_terminationEvidence.canReconcile) {
      _terminationEvidence.recordProtocolStreamDrained();
    }
    if (!(_protocolStreamDrained?.isCompleted ?? true)) {
      _protocolStreamDrained!.complete();
    }
  }

  void _handleWorkerDiagnostics(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    if (!_terminationEvidence.sawError) {
      _terminationEvidence.recordError();
    }
    final int remaining = _maximumDiagnosticBytes - _diagnostics.length;
    if (remaining <= 0) {
      _diagnosticsTruncated = true;
      return;
    }
    final int accepted = bytes.length < remaining ? bytes.length : remaining;
    _diagnostics.add(bytes.sublist(0, accepted));
    if (accepted != bytes.length) {
      _diagnosticsTruncated = true;
    }
  }

  void _handleDiagnosticError(Object error, StackTrace stackTrace) {
    if (!_terminationEvidence.sawError) {
      _terminationEvidence.recordError();
    }
    final List<int> encoded = utf8.encode('diagnostic stream error: $error\n');
    _handleWorkerDiagnostics(encoded);
  }

  void _handleDiagnosticsDone() {
    _terminationEvidence.recordDiagnosticsStreamDrained();
    if (!(_diagnosticsStreamDrained?.isCompleted ?? true)) {
      _diagnosticsStreamDrained!.complete();
    }
  }

  void _handleWorkerExit(int status) {
    if (_processReaped) {
      return;
    }
    _processReaped = true;
    _processExitStatus = status;
    if (_outstandingProcessCount <= 0) {
      throw StateError('worker process count underflow');
    }
    --_outstandingProcessCount;
    _terminationEvidence.recordExit();
    if (!(_exitSignal?.isCompleted ?? true)) {
      _exitSignal!.complete();
    }
    _reconcileFuture ??= _reconcileWorkerTermination();
  }

  Future<void> _reconcileWorkerTermination() async {
    await Future.wait<void>(<Future<void>>[
      _protocolStreamDrained!.future,
      _diagnosticsStreamDrained!.future,
    ]);
    if (!_terminationEvidence.canReconcile) {
      throw StateError('worker streams did not reach their exit barriers');
    }

    final RuntimeLifecycleWorkerTermination termination = _terminationEvidence
        .classify(
          workerWasReady: _workerWasReady,
          shutdownRequested: _shutdownRequested,
          stopAcknowledged: _stopAcknowledged?.isCompleted ?? false,
          forcedCleanup: _forcedCleanup,
          processExitedSuccessfully: _processExitStatus == 0,
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
    await _closeTransport();
    _completeTermination(termination);
  }

  void _killWorker() {
    _worker?.kill(ProcessSignal.sigkill);
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

  Future<void> _closeTransport() async {
    _acceptResponses = false;
    _responses.clear();
    try {
      await _writer?.close();
    } on Object {
      // Process exit commonly closes stdin before the parent does.
    }
    await _protocolSubscription?.cancel();
    await _diagnosticSubscription?.cancel();
    await _decoder?.cancel();
    _protocolSubscription = null;
    _diagnosticSubscription = null;
    _decoder = null;
    _writer = null;
    _worker = null;
  }
}

Future<void> runRuntimeLifecycleWorkerProcess(List<String> arguments) async {
  RuntimeLifecycleScenario? scenario;
  int? generation;
  for (final String argument in arguments) {
    if (argument.startsWith('--scenario=')) {
      if (scenario != null) {
        throw const FormatException('--scenario may be supplied only once');
      }
      scenario = RuntimeLifecycleScenario.byName(
        argument.substring('--scenario='.length),
      );
      if (scenario == null) {
        throw FormatException('unknown worker scenario: $argument');
      }
      continue;
    }
    if (argument.startsWith('--generation=')) {
      if (generation != null) {
        throw const FormatException('--generation may be supplied only once');
      }
      generation = int.tryParse(argument.substring('--generation='.length));
      if (generation == null || generation <= 0 || generation > 0xffffffff) {
        throw FormatException('invalid worker generation: $argument');
      }
      continue;
    }
    throw FormatException('unknown worker argument: $argument');
  }
  if (scenario == null || generation == null) {
    throw const FormatException('worker scenario and generation are required');
  }
  if (scenario == RuntimeLifecycleScenario.rootStartupFailure ||
      scenario == RuntimeLifecycleScenario.rootUncaught) {
    throw FormatException('root-only scenario cannot run in worker: $scenario');
  }
  if (scenario == RuntimeLifecycleScenario.workerStartupFailure) {
    throw StateError('requested lifecycle worker startup failure');
  }

  final RuntimeWorkerFrameDecoder decoder = RuntimeWorkerFrameDecoder(stdin);
  final RuntimeWorkerFrameWriter writer = RuntimeWorkerFrameWriter(stdout);
  Timer? idleAction;
  Future<void>? lateResponse;
  try {
    await writer.send(
      RuntimeWorkerFrame(
        type: RuntimeWorkerMessageType.ready,
        generation: generation,
        operation: 0,
        payload: RuntimeWorkerFrameCodec.int64Payload(pid),
      ),
    );
    if (scenario == RuntimeLifecycleScenario.workerIdleUncaught) {
      idleAction = Timer(const Duration(milliseconds: 35), () {
        throw StateError('requested idle worker failure');
      });
    } else if (scenario == RuntimeLifecycleScenario.workerIdleExit) {
      idleAction = Timer(const Duration(milliseconds: 35), () => exit(0));
    }

    await for (final RuntimeWorkerFrame frame in decoder.frames) {
      if (frame.generation != generation) {
        throw FormatException(
          'parent generation ${frame.generation} != $generation',
        );
      }
      switch (frame.type) {
        case RuntimeWorkerMessageType.request:
          if (frame.operation == 0) {
            throw const FormatException('request operation must be nonzero');
          }
          final int value = RuntimeWorkerFrameCodec.readInt64Payload(frame);
          if (scenario == RuntimeLifecycleScenario.workerSyncUncaught) {
            throw StateError('requested synchronous worker failure');
          }
          if (scenario == RuntimeLifecycleScenario.workerAsyncUncaught) {
            await Future<void>.delayed(Duration.zero);
            throw StateError('requested asynchronous worker failure');
          }
          if (scenario == RuntimeLifecycleScenario.workerUnexpectedExit) {
            exit(0);
          }
          final RuntimeWorkerFrame response = RuntimeWorkerFrame(
            type: RuntimeWorkerMessageType.response,
            generation: generation,
            operation: frame.operation,
            payload: RuntimeWorkerFrameCodec.int64Payload(value + 1),
          );
          if (scenario == RuntimeLifecycleScenario.lateCompletion) {
            lateResponse = Future<void>.delayed(
              const Duration(milliseconds: 35),
              () => writer.send(response),
            );
          } else {
            await writer.send(response);
          }
          break;
        case RuntimeWorkerMessageType.stop:
          if (frame.operation != 0 || frame.payload.isNotEmpty) {
            throw const FormatException('invalid stop frame');
          }
          if (scenario == RuntimeLifecycleScenario.shutdownTimeout) {
            await Completer<void>().future;
          }
          if (scenario == RuntimeLifecycleScenario.workerStopUncaught) {
            throw StateError('requested worker failure while stopping');
          }
          await writer.send(
            RuntimeWorkerFrame(
              type: RuntimeWorkerMessageType.stopAcknowledged,
              generation: generation,
              operation: 0,
              payload: Uint8List(0),
            ),
          );
          if (scenario == RuntimeLifecycleScenario.lateCompletion) {
            await Future<void>.delayed(const Duration(milliseconds: 70));
            await lateResponse;
          }
          return;
        case RuntimeWorkerMessageType.ready:
        case RuntimeWorkerMessageType.response:
        case RuntimeWorkerMessageType.stopAcknowledged:
          throw FormatException(
            'parent sent worker-only frame ${frame.type.name}',
          );
      }
    }
  } finally {
    idleAction?.cancel();
    await decoder.cancel();
    await stdout.flush();
  }
}
