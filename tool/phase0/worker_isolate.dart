import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _chunkBytes = 256 * 1024;
const int _totalBytes = 128 * 1024 * 1024;
const Duration _operationTimeout = Duration(seconds: 5);

typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _Uint64Native = Uint64 Function();
typedef _Uint64Dart = int Function();
typedef _WorkerReportNative = Int32 Function(
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
  Uint64,
);
typedef _WorkerReportDart = int Function(
  int,
  int,
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
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
final _Uint64Dart _threadId = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>('dt_phase0_aot_thread_id');

@pragma('vm:entry-point')
Future<void> _terminalWorker(SendPort rootPort) async {
  final ReceivePort commands = ReceivePort('phase0-terminal-worker');
  final int workerThread = _threadId();
  rootPort.send(<Object?>[
    'ready',
    commands.sendPort,
    workerThread,
    _isMainThread(),
  ]);

  int receivedBytes = 0;
  int receivedChunks = 0;
  await for (final Object? raw in commands.cast<Object?>()) {
    final List<Object?> message = raw! as List<Object?>;
    final String operation = message[0]! as String;
    switch (operation) {
      case 'ping':
        rootPort.send(<Object?>[
          'pong',
          message[1]! as int,
          _threadId(),
          _isMainThread(),
        ]);
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
        receivedChunks++;
        rootPort.send(<Object?>[
          'ack',
          sequence,
          receivedBytes,
          receivedChunks,
          _threadId(),
          _isMainThread(),
        ]);
      case 'stop':
        rootPort.send(<Object?>[
          'stopped',
          receivedBytes,
          receivedChunks,
          _threadId(),
          _isMainThread(),
        ]);
        commands.close();
    }
  }
}

@pragma('vm:entry-point')
void _faultWorker(SendPort rootPort) {
  rootPort.send(<Object?>['fault-ready', _threadId(), _isMainThread()]);
  throw StateError('phase0-expected-worker-fault');
}

Future<List<Object?>> _nextMessage(
  StreamIterator<Object?> iterator,
  String expectedOperation,
) async {
  final bool hasNext = await iterator.moveNext().timeout(
    _operationTimeout,
    onTimeout: () => false,
  );
  if (!hasNext) {
    throw TimeoutException('timed out waiting for $expectedOperation');
  }
  final List<Object?> message = iterator.current! as List<Object?>;
  if (message[0] != expectedOperation) {
    throw StateError('expected $expectedOperation but received ${message[0]}');
  }
  return message;
}

Future<void> main() async {
  final _Int32Dart showWindow = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_show_window');
  final _WorkerReportDart reportSuccess = _process
      .lookupFunction<_WorkerReportNative, _WorkerReportDart>(
        'dt_phase0_worker_report_success',
      );
  final _Int32Dart terminate = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_terminate');

  final int rootThread = _threadId();
  if (_isMainThread() != 1 || rootThread == 0 || showWindow() != 0) {
    stderr.writeln('PHASE0_WORKER_FAIL root isolate ownership validation');
    terminate();
    return;
  }

  final Stopwatch heartbeatClock = Stopwatch()..start();
  int previousHeartbeat = heartbeatClock.elapsedMicroseconds;
  int maxHeartbeatGap = 0;
  bool heartbeatLeftMainThread = false;
  final Timer heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final int now = heartbeatClock.elapsedMicroseconds;
    final int gap = now - previousHeartbeat;
    if (gap > maxHeartbeatGap) {
      maxHeartbeatGap = gap;
    }
    previousHeartbeat = now;
    if (_isMainThread() != 1 || _threadId() != rootThread) {
      heartbeatLeftMainThread = true;
    }
  });

  ReceivePort? replies;
  ReceivePort? workerExit;
  Isolate? worker;
  ReceivePort? faultReady;
  ReceivePort? faultErrors;
  ReceivePort? faultExit;
  Isolate? faultWorker;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));

    replies = ReceivePort('phase0-worker-replies');
    workerExit = ReceivePort('phase0-worker-exit');
    final StreamIterator<Object?> replyIterator = StreamIterator<Object?>(
      replies.cast<Object?>(),
    );
    worker = await Isolate.spawn<SendPort>(
      _terminalWorker,
      replies.sendPort,
      onExit: workerExit.sendPort,
      errorsAreFatal: true,
      debugName: 'phase0-terminal-engine',
    );

    final List<Object?> ready = await _nextMessage(replyIterator, 'ready');
    final SendPort commands = ready[1]! as SendPort;
    final int workerThread = ready[2]! as int;
    if (ready[3] != 0 || workerThread == 0 || workerThread == rootThread) {
      throw StateError('worker isolate did not use its owned native thread');
    }

    final Stopwatch pingClock = Stopwatch()..start();
    commands.send(<Object?>['ping', 1]);
    final List<Object?> pong = await _nextMessage(replyIterator, 'pong');
    final int pingMicros = pingClock.elapsedMicroseconds;
    if (pong[1] != 1 || pong[2] == 0 || pong[2] == rootThread || pong[3] != 0) {
      throw StateError('worker ping violated identity or ordering');
    }

    final int chunkCount = _totalBytes ~/ _chunkBytes;
    final Stopwatch transferClock = Stopwatch()..start();
    for (int sequence = 0; sequence < chunkCount; sequence++) {
      final int marker = sequence & 0xff;
      final Uint8List bytes = Uint8List(_chunkBytes);
      bytes.first = marker;
      bytes.last = marker ^ 0xff;
      commands.send(<Object?>[
        'data',
        sequence,
        TransferableTypedData.fromList(<Uint8List>[bytes]),
      ]);
      final List<Object?> acknowledgement = await _nextMessage(
        replyIterator,
        'ack',
      );
      if (acknowledgement[1] != sequence ||
          acknowledgement[2] != (sequence + 1) * _chunkBytes ||
          acknowledgement[3] != sequence + 1 ||
          acknowledgement[4] == 0 ||
          acknowledgement[4] == rootThread ||
          acknowledgement[5] != 0 ||
          _isMainThread() != 1 ||
          _threadId() != rootThread) {
        throw StateError('transfer acknowledgement $sequence was invalid');
      }
    }
    final int transferMicros = transferClock.elapsedMicroseconds;

    commands.send(<Object?>['stop']);
    final List<Object?> stopped = await _nextMessage(replyIterator, 'stopped');
    if (stopped[1] != _totalBytes ||
        stopped[2] != chunkCount ||
        stopped[3] == 0 ||
        stopped[3] == rootThread ||
        stopped[4] != 0) {
      throw StateError('worker shutdown summary was invalid');
    }
    await workerExit.first.timeout(_operationTimeout);
    worker = null;
    await replyIterator.cancel();
    replies.close();
    replies = null;
    workerExit.close();
    workerExit = null;

    faultReady = ReceivePort('phase0-fault-ready');
    faultErrors = ReceivePort('phase0-fault-errors');
    faultExit = ReceivePort('phase0-fault-exit');
    faultWorker = await Isolate.spawn<SendPort>(
      _faultWorker,
      faultReady.sendPort,
      onError: faultErrors.sendPort,
      onExit: faultExit.sendPort,
      errorsAreFatal: true,
      debugName: 'phase0-expected-fault',
    );
    final List<Object?> faultIdentity =
        (await faultReady.first.timeout(_operationTimeout))! as List<Object?>;
    final Object? faultError = await faultErrors.first.timeout(
      _operationTimeout,
    );
    await faultExit.first.timeout(_operationTimeout);
    faultWorker = null;
    final int faultThread = faultIdentity[1]! as int;
    if (faultIdentity[0] != 'fault-ready' ||
        faultIdentity[2] != 0 ||
        faultThread == rootThread ||
        !faultError.toString().contains('phase0-expected-worker-fault')) {
      throw StateError('worker fault contract was not observed');
    }

    heartbeat.cancel();
    if (heartbeatLeftMainThread || maxHeartbeatGap == 0) {
      throw StateError('root heartbeat ownership validation failed');
    }

    final int reportStatus = reportSuccess(
      _totalBytes,
      transferMicros,
      chunkCount,
      rootThread,
      workerThread,
      pingMicros,
      maxHeartbeatGap,
      1,
      faultThread,
      1,
      1,
    );
    final double mibPerSecond =
        (_totalBytes * 1000000 / transferMicros) / (1024 * 1024);
    stdout.writeln(
      'PHASE0_WORKER_DART_${reportStatus == 0 ? 'PASS' : 'FAIL'} '
      'bytes=$_totalBytes chunks=$chunkCount elapsed_us=$transferMicros '
      'mib_s=${mibPerSecond.toStringAsFixed(2)} ping_us=$pingMicros '
      'heartbeat_gap_us=$maxHeartbeatGap root_thread=$rootThread '
      'worker_thread=$workerThread fault_thread=$faultThread '
      'report_status=$reportStatus',
    );
    terminate();
  } on Object catch (error, stackTrace) {
    heartbeat.cancel();
    stderr.writeln('PHASE0_WORKER_FAIL $error');
    stderr.writeln(stackTrace);
    terminate();
  } finally {
    worker?.kill(priority: Isolate.immediate);
    faultWorker?.kill(priority: Isolate.immediate);
    replies?.close();
    workerExit?.close();
    faultReady?.close();
    faultErrors?.close();
    faultExit?.close();
  }
}
