import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _chunkBytes = 256 * 1024;
const int _totalBytes = 128 * 1024 * 1024;
const Duration _operationTimeout = Duration(seconds: 5);

final class _NativeWorker extends Opaque {}

typedef _CreateWorkerNative = Pointer<_NativeWorker> Function();
typedef _CreateWorkerDart = Pointer<_NativeWorker> Function();
typedef _StartWorkerNative = Int32 Function(
  Pointer<_NativeWorker>,
  Int64,
  Int64,
  Int64,
);
typedef _StartWorkerDart = int Function(Pointer<_NativeWorker>, int, int, int);
typedef _WorkerActionNative = Void Function(Pointer<_NativeWorker>);
typedef _WorkerActionDart = void Function(Pointer<_NativeWorker>);
typedef _WorkerStatusNative = Int32 Function(Pointer<_NativeWorker>);
typedef _WorkerStatusDart = int Function(Pointer<_NativeWorker>);
typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _ReportNative = Void Function(
  Int32,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
);
typedef _ReportDart = void Function(
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
);

final DynamicLibrary _process = DynamicLibrary.process();
final _CreateWorkerDart _createWorker = _process
    .lookupFunction<_CreateWorkerNative, _CreateWorkerDart>(
      'dt_public_embedder_create_worker',
    );
final _StartWorkerDart _startWorker = _process
    .lookupFunction<_StartWorkerNative, _StartWorkerDart>(
      'dt_public_embedder_start_worker',
    );
final _WorkerActionDart _killWorker = _process
    .lookupFunction<_WorkerActionNative, _WorkerActionDart>(
      'dt_public_embedder_kill_worker',
    );
final _WorkerStatusDart _workerCleaned = _process
    .lookupFunction<_WorkerStatusNative, _WorkerStatusDart>(
      'dt_public_embedder_worker_cleaned',
    );
final _WorkerStatusDart _releaseWorker = _process
    .lookupFunction<_WorkerStatusNative, _WorkerStatusDart>(
      'dt_public_embedder_release_worker',
    );
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>(
      'dt_public_embedder_is_main_thread',
    );
final _ReportDart _report = _process.lookupFunction<_ReportNative, _ReportDart>(
  'dt_public_embedder_report',
);

int _spinValue = 0;

void main() {}

Future<void> _waitForNativeCleanup(Pointer<_NativeWorker> handle) async {
  final Stopwatch deadline = Stopwatch()..start();
  while (_workerCleaned(handle) == 0) {
    if (deadline.elapsed >= _operationTimeout) {
      throw TimeoutException('native worker cleanup did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

@pragma('vm:entry-point', 'call')
void startPublicEmbedderWorkerProbe() {
  unawaited(_runAndReport());
}

@pragma('vm:entry-point', 'call')
void publicEmbedderWorkerMain(SendPort rootPort) {
  final ReceivePort commands = ReceivePort('public-embedder-worker');
  rootPort.send(<Object?>['ready', commands.sendPort, _isMainThread()]);

  int receivedBytes = 0;
  int receivedChunks = 0;
  commands.listen((Object? raw) {
    final List<Object?> message = raw! as List<Object?>;
    final String operation = message.first! as String;
    switch (operation) {
      case 'ping':
        rootPort.send(<Object?>['pong', message[1], _isMainThread()]);
      case 'data':
        final int sequence = message[1]! as int;
        final TransferableTypedData transfer =
            message[2]! as TransferableTypedData;
        final Uint8List bytes = transfer.materialize().asUint8List();
        final int marker = sequence & 0xff;
        if (bytes.length != _chunkBytes ||
            bytes.first != marker ||
            bytes.last != (marker ^ 0xff)) {
          throw StateError('worker received corrupt chunk $sequence');
        }
        receivedBytes += bytes.length;
        receivedChunks += 1;
        rootPort.send(<Object?>[
          'ack',
          sequence,
          receivedBytes,
          receivedChunks,
          _isMainThread(),
        ]);
      case 'microtask':
        try {
          scheduleMicrotask(() {
            rootPort.send(<Object?>['microtask-ran', _isMainThread()]);
          });
          rootPort.send(<Object?>[
            'microtask-status',
            true,
            '',
            _isMainThread(),
          ]);
        } on Object catch (error) {
          rootPort.send(<Object?>[
            'microtask-status',
            false,
            error.toString(),
            _isMainThread(),
          ]);
        }
      case 'stop':
        rootPort.send(<Object?>[
          'stopped',
          receivedBytes,
          receivedChunks,
          _isMainThread(),
        ]);
        commands.close();
      case 'fail':
        throw StateError('public-embedder-expected-worker-fault');
      case 'hang':
        rootPort.send(<Object?>['hanging', _isMainThread()]);
        while (true) {
          _spinValue = (_spinValue + 1) & 0x7fffffff;
        }
      default:
        throw UnsupportedError('unknown worker operation: $operation');
    }
  });
}

Future<void> _runAndReport() async {
  int status = 0;
  int transferredBytes = 0;
  int transferMicros = 0;
  int normalObserved = 0;
  int faultObserved = 0;
  int forcedObserved = 0;
  int replacementObserved = 0;
  int microtasksUnavailableObserved = 0;
  int faultDiagnosticLostObserved = 0;
  final List<_WorkerSession> active = <_WorkerSession>[];

  try {
    if (_isMainThread() != 1) {
      throw StateError('root probe is not running on the process main thread');
    }

    final _WorkerSession normal = await _WorkerSession.start();
    active.add(normal);
    normal.commands.send(<Object?>['ping', 1]);
    final List<Object?> pong = await normal.nextEvent('pong');
    if (pong[1] != 1 || pong[2] != 0) {
      throw StateError('normal worker ping violated its thread domain');
    }
    normal.commands.send(<Object?>['microtask']);
    final List<Object?> microtaskStatus = await normal.nextEvent(
      'microtask-status',
    );
    if (microtaskStatus.length != 4 ||
        microtaskStatus[1] != false ||
        !microtaskStatus[2].toString().contains(
          'Microtasks are not supported',
        ) ||
        microtaskStatus[3] != 0) {
      throw StateError(
        'unmodified Engine child unexpectedly supported microtasks: '
        '$microtaskStatus',
      );
    }
    microtasksUnavailableObserved = 1;

    final int chunkCount = _totalBytes ~/ _chunkBytes;
    final Stopwatch transferClock = Stopwatch()..start();
    for (int sequence = 0; sequence < chunkCount; sequence += 1) {
      final int marker = sequence & 0xff;
      final Uint8List bytes = Uint8List(_chunkBytes);
      bytes.first = marker;
      bytes.last = marker ^ 0xff;
      normal.commands.send(<Object?>[
        'data',
        sequence,
        TransferableTypedData.fromList(<Uint8List>[bytes]),
      ]);
      final List<Object?> acknowledgement = await normal.nextEvent('ack');
      if (acknowledgement[1] != sequence ||
          acknowledgement[2] != (sequence + 1) * _chunkBytes ||
          acknowledgement[3] != sequence + 1 ||
          acknowledgement[4] != 0 ||
          _isMainThread() != 1) {
        throw StateError('invalid transfer acknowledgement $sequence');
      }
    }
    transferClock.stop();
    transferredBytes = _totalBytes;
    transferMicros = transferClock.elapsedMicroseconds;

    final Future<Object?> normalExit = normal.nextExit();
    normal.commands.send(<Object?>['stop']);
    final List<Object?> stopped = await normal.nextEvent('stopped');
    if (stopped[1] != _totalBytes ||
        stopped[2] != chunkCount ||
        stopped[3] != 0) {
      throw StateError('normal worker stop summary was invalid');
    }
    await normalExit;
    await normal.releaseAfterCleanup();
    active.remove(normal);
    normalObserved = 1;

    final _WorkerSession fault = await _WorkerSession.start();
    active.add(fault);
    final Future<Object?> faultError = fault.nextError();
    final Future<Object?> faultExit = fault.nextExit();
    fault.commands.send(<Object?>['fail']);
    final Object? error = await faultError;
    await faultExit;
    final String faultDescription = error.toString();
    if (faultDescription.contains('public-embedder-expected-worker-fault')) {
      throw StateError(
        'unmodified Engine child unexpectedly preserved the worker fault: '
        '$error',
      );
    }
    if (!faultDescription.contains('Microtasks are not supported')) {
      throw StateError('worker error port had an unknown diagnostic: $error');
    }
    faultDiagnosticLostObserved = 1;
    await fault.releaseAfterCleanup();
    active.remove(fault);
    faultObserved = 1;

    final _WorkerSession forced = await _WorkerSession.start();
    active.add(forced);
    final Future<Object?> forcedExit = forced.nextExit();
    forced.commands.send(<Object?>['hang']);
    final List<Object?> hanging = await forced.nextEvent('hanging');
    if (hanging[1] != 0) {
      throw StateError('forced worker ran on the process main thread');
    }
    _killWorker(forced.handle);
    await forcedExit;
    await forced.releaseAfterCleanup();
    active.remove(forced);
    forcedObserved = 1;

    final _WorkerSession replacement = await _WorkerSession.start();
    active.add(replacement);
    replacement.commands.send(<Object?>['ping', 2]);
    final List<Object?> replacementPong = await replacement.nextEvent('pong');
    if (replacementPong[1] != 2 || replacementPong[2] != 0) {
      throw StateError('replacement worker did not become usable');
    }
    final Future<Object?> replacementExit = replacement.nextExit();
    replacement.commands.send(<Object?>['stop']);
    await replacement.nextEvent('stopped');
    await replacementExit;
    await replacement.releaseAfterCleanup();
    active.remove(replacement);
    replacementObserved = 1;
  } on Object catch (error, stackTrace) {
    status = 1;
    stderr.writeln('PUBLIC_EMBEDDER_WORKER_PROBE_FAIL $error');
    stderr.writeln(stackTrace);
  } finally {
    for (final _WorkerSession session in active) {
      try {
        await session.forceRelease();
      } on Object catch (error) {
        status = 1;
        stderr.writeln('PUBLIC_EMBEDDER_WORKER_CLEANUP_FAIL $error');
      }
    }
    _report(
      status,
      transferredBytes,
      transferMicros,
      normalObserved,
      faultObserved,
      forcedObserved,
      replacementObserved,
      microtasksUnavailableObserved,
      faultDiagnosticLostObserved,
    );
  }
}

final class _WorkerSession {
  _WorkerSession({
    required this.handle,
    required this.events,
    required this.errors,
    required this.exits,
    required this.iterator,
    required this.commands,
  });

  final Pointer<_NativeWorker> handle;
  final ReceivePort events;
  final ReceivePort errors;
  final ReceivePort exits;
  final StreamIterator<Object?> iterator;
  final SendPort commands;
  bool _released = false;

  static Future<_WorkerSession> start() async {
    final Pointer<_NativeWorker> handle = _createWorker();
    if (handle == nullptr) {
      throw StateError('native worker creation failed');
    }
    final ReceivePort events = ReceivePort('public-embedder-events');
    final ReceivePort errors = ReceivePort('public-embedder-errors');
    final ReceivePort exits = ReceivePort('public-embedder-exits');
    final StreamIterator<Object?> iterator = StreamIterator<Object?>(
      events.cast<Object?>(),
    );
    try {
      final int startStatus = _startWorker(
        handle,
        events.sendPort.nativePort,
        errors.sendPort.nativePort,
        exits.sendPort.nativePort,
      );
      if (startStatus != 0) {
        throw StateError('native worker start failed: $startStatus');
      }
      final bool hasReady = await iterator.moveNext().timeout(
        _operationTimeout,
      );
      if (!hasReady) {
        throw StateError('worker event stream ended before ready');
      }
      final List<Object?> ready = iterator.current! as List<Object?>;
      if (ready.length != 3 ||
          ready[0] != 'ready' ||
          ready[1] is! SendPort ||
          ready[2] != 1) {
        throw StateError('worker ready message was invalid: $ready');
      }
      return _WorkerSession(
        handle: handle,
        events: events,
        errors: errors,
        exits: exits,
        iterator: iterator,
        commands: ready[1]! as SendPort,
      );
    } on Object catch (error, stackTrace) {
      Object? cleanupError;
      try {
        _killWorker(handle);
        await _waitForNativeCleanup(handle);
        final int releaseStatus = _releaseWorker(handle);
        if (releaseStatus != 0) {
          throw StateError(
            'native worker release after failed start was rejected: '
            '$releaseStatus',
          );
        }
      } on Object catch (caught) {
        cleanupError = caught;
      }
      await iterator.cancel();
      events.close();
      errors.close();
      exits.close();
      if (cleanupError != null) {
        Error.throwWithStackTrace(
          StateError('$error; failed-start cleanup also failed: $cleanupError'),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<List<Object?>> nextEvent(String expected) async {
    final bool hasNext = await iterator.moveNext().timeout(_operationTimeout);
    if (!hasNext) {
      throw StateError('worker event stream ended before $expected');
    }
    final List<Object?> message = iterator.current! as List<Object?>;
    if (message.isEmpty || message.first != expected) {
      throw StateError('expected $expected but received $message');
    }
    return message;
  }

  Future<Object?> nextError() => errors.first.timeout(_operationTimeout);

  Future<Object?> nextExit() => exits.first.timeout(_operationTimeout);

  Future<void> releaseAfterCleanup() async {
    await _waitForNativeCleanup(handle);
    if (_releaseWorker(handle) != 0) {
      throw StateError('native worker release was rejected');
    }
    _released = true;
    await iterator.cancel();
    events.close();
    errors.close();
    exits.close();
  }

  Future<void> forceRelease() async {
    if (_released) {
      return;
    }
    _killWorker(handle);
    await _waitForNativeCleanup(handle);
    if (_releaseWorker(handle) != 0) {
      throw StateError('forced native worker release was rejected');
    }
    _released = true;
    await iterator.cancel();
    events.close();
    errors.close();
    exits.close();
  }
}
