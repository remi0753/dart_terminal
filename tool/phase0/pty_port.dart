import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _batchEvent = 1;
const int _summaryEvent = 2;
const int _minimumBurstBytes = 10 * 1024 * 1024;
const int _deliveryBatchBytes = 64 * 1024;
const int _highWaterBytes = 1024 * 1024;
const Duration _scenarioTimeout = Duration(seconds: 12);

typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _Int64Native = Int64 Function();
typedef _Int64Dart = int Function();
typedef _StartNative = Int32 Function(Int64);
typedef _StartDart = int Function(int);
typedef _AckNative = Int32 Function(Uint64, Uint64);
typedef _AckDart = int Function(int, int);
typedef _ReportNative = Int32 Function(Uint64);
typedef _ReportDart = int Function(int);

final DynamicLibrary _process = DynamicLibrary.process();
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
final _Int64Dart _threadId = _process.lookupFunction<_Int64Native, _Int64Dart>(
  'dt_phase0_aot_thread_id',
);
final _StartDart _startPty = _process.lookupFunction<_StartNative, _StartDart>(
  'dt_phase0_pty_start',
);
final _AckDart _ackPty = _process.lookupFunction<_AckNative, _AckDart>(
  'dt_phase0_pty_ack',
);
final _Int32Dart _joinPty = _process.lookupFunction<_Int32Native, _Int32Dart>(
  'dt_phase0_pty_join',
);

final class _ByteMarker {
  _ByteMarker(String marker) : _pattern = marker.codeUnits;

  final List<int> _pattern;
  int _matched = 0;
  bool found = false;

  void add(int byte) {
    if (found) {
      return;
    }
    if (byte == _pattern[_matched]) {
      _matched++;
      if (_matched == _pattern.length) {
        found = true;
      }
      return;
    }
    _matched = byte == _pattern.first ? 1 : 0;
  }
}

@pragma('vm:entry-point')
Future<void> _ptyWorker(SendPort rootPort) async {
  final ReceivePort events = ReceivePort('phase0-pty-events');
  final int workerThread = _threadId();
  bool started = false;
  try {
    if (_isMainThread() != 0 || workerThread == 0) {
      throw StateError('PTY worker ran on the AppKit main thread');
    }
    final int startStatus = _startPty(events.sendPort.nativePort);
    if (startStatus != 0) {
      throw StateError('native PTY start failed: $startStatus');
    }
    started = true;

    int expectedSequence = 0;
    int totalBytes = 0;
    int batchCount = 0;
    int minLargeBatch = 0;
    int maxBatch = 0;
    int xBytes = 0;
    final List<_ByteMarker> markers = <_ByteMarker>[
      _ByteMarker('__DT_TTY_OK__'),
      _ByteMarker('__DT_SIZE__43 132'),
      _ByteMarker('__DT_SIGINT__130'),
      _ByteMarker('__DT_BURST_BEGIN__'),
      _ByteMarker('__DT_BURST_END__'),
    ];

    await for (final Object? raw in events.cast<Object?>().timeout(
      _scenarioTimeout,
    )) {
      final List<Object?> message = raw! as List<Object?>;
      final int kind = message[0]! as int;
      if (kind == _batchEvent) {
        final int sequence = message[1]! as int;
        final Uint8List bytes = message[2]! as Uint8List;
        if (sequence != expectedSequence ||
            bytes.isEmpty ||
            bytes.length > _deliveryBatchBytes) {
          throw StateError('invalid PTY batch $sequence/${bytes.length}');
        }
        for (final int byte in bytes) {
          if (byte == 0x78) {
            xBytes++;
          }
          for (final _ByteMarker marker in markers) {
            marker.add(byte);
          }
        }
        totalBytes += bytes.length;
        batchCount++;
        maxBatch = bytes.length > maxBatch ? bytes.length : maxBatch;
        if (bytes.length >= _deliveryBatchBytes &&
            (minLargeBatch == 0 || bytes.length < minLargeBatch)) {
          minLargeBatch = bytes.length;
        }
        if (sequence == 0) {
          // Force the native producer through its high/low-water path once.
          // The delay is confined to the PTY worker, never the UI root.
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        final int ackStatus = _ackPty(sequence, bytes.length);
        if (ackStatus != 0) {
          throw StateError('native PTY ack failed: $ackStatus');
        }
        expectedSequence++;
        continue;
      }

      if (kind != _summaryEvent || message.length != 22) {
        throw StateError('unexpected native PTY event $kind');
      }
      final int status = message[1]! as int;
      final int failedStep = message[2]! as int;
      final int systemError = message[3]! as int;
      final int execError = message[4]! as int;
      final int childPid = message[5]! as int;
      final int nativeBytes = message[6]! as int;
      final int nativeBatches = message[7]! as int;
      final int nativeMinLargeBatch = message[8]! as int;
      final int nativeMaxBatch = message[9]! as int;
      final int maxInFlight = message[10]! as int;
      final int backpressureWaits = message[11]! as int;
      final int nativeXBytes = message[12]! as int;
      final int ttyOk = message[13]! as int;
      final int resizeOk = message[14]! as int;
      final int signalOk = message[15]! as int;
      final int exitCode = message[16]! as int;
      final int readCalls = message[17]! as int;
      final int elapsedMicros = message[18]! as int;
      final int maxPostMicros = message[19]! as int;
      final int postFailures = message[20]! as int;
      final int ackFailures = message[21]! as int;

      if (status != 0 ||
          failedStep != 0 ||
          systemError != 0 ||
          execError != 0 ||
          childPid <= 1 ||
          nativeBytes != totalBytes ||
          nativeBatches != batchCount ||
          nativeMinLargeBatch != minLargeBatch ||
          nativeMaxBatch != maxBatch ||
          minLargeBatch < _deliveryBatchBytes ||
          maxBatch > _deliveryBatchBytes ||
          maxInFlight > _highWaterBytes ||
          backpressureWaits == 0 ||
          totalBytes < _minimumBurstBytes ||
          xBytes < _minimumBurstBytes ||
          nativeXBytes != xBytes ||
          markers.any((marker) => !marker.found) ||
          ttyOk != 1 ||
          resizeOk != 1 ||
          signalOk != 1 ||
          exitCode != 37 ||
          readCalls == 0 ||
          elapsedMicros <= 0 ||
          maxPostMicros < 0 ||
          postFailures != 0 ||
          ackFailures != 0 ||
          _isMainThread() != 0) {
        throw StateError(
          'PTY summary rejected: status=$status step=$failedStep '
          'errno=$systemError exec_errno=$execError',
        );
      }

      final int joinStatus = _joinPty();
      started = false;
      if (joinStatus != 0) {
        throw StateError('native PTY join failed: $joinStatus');
      }
      rootPort.send(<Object?>[
        'pass',
        workerThread,
        totalBytes,
        batchCount,
        minLargeBatch,
        maxBatch,
        maxInFlight,
        backpressureWaits,
        xBytes,
        exitCode,
        readCalls,
        elapsedMicros,
        maxPostMicros,
      ]);
      events.close();
      return;
    }
    throw StateError('native PTY event stream closed before summary');
  } on Object catch (error, stackTrace) {
    if (started) {
      final int joinStatus = _joinPty();
      stderr.writeln('PHASE0_PTY_WORKER_JOIN_AFTER_ERROR status=$joinStatus');
    }
    rootPort.send(<Object?>['error', error.toString(), stackTrace.toString()]);
    events.close();
  }
}

Future<void> main() async {
  final _Int32Dart showWindow = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_show_window');
  final _ReportDart reportSuccess = _process
      .lookupFunction<_ReportNative, _ReportDart>(
        'dt_phase0_aot_report_success',
      );
  final _Int32Dart terminate = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_terminate');

  final int rootThread = _threadId();
  if (_isMainThread() != 1 || rootThread == 0 || showWindow() != 0) {
    stderr.writeln('PHASE0_PTY_FAIL root isolate ownership validation');
    terminate();
    return;
  }

  final Stopwatch elapsed = Stopwatch()..start();
  int lastHeartbeat = elapsed.elapsedMicroseconds;
  int maxHeartbeatGap = 0;
  bool heartbeatOwnershipFailed = false;
  final Timer heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final int now = elapsed.elapsedMicroseconds;
    final int gap = now - lastHeartbeat;
    maxHeartbeatGap = gap > maxHeartbeatGap ? gap : maxHeartbeatGap;
    lastHeartbeat = now;
    if (_isMainThread() != 1 || _threadId() != rootThread) {
      heartbeatOwnershipFailed = true;
    }
  });

  final ReceivePort results = ReceivePort('phase0-pty-results');
  final ReceivePort errors = ReceivePort('phase0-pty-worker-errors');
  final ReceivePort exits = ReceivePort('phase0-pty-worker-exit');
  Isolate? worker;
  try {
    worker = await Isolate.spawn<SendPort>(
      _ptyWorker,
      results.sendPort,
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
      debugName: 'phase0-pty-consumer',
    );
    final List<Object?> result =
        (await results.first.timeout(_scenarioTimeout))! as List<Object?>;
    if (result[0] != 'pass') {
      throw StateError('PTY worker failed: ${result.skip(1).join('\n')}');
    }
    await exits.first.timeout(_scenarioTimeout);
    worker = null;
    final Object? unexpectedError = await errors.first.timeout(
      const Duration(milliseconds: 20),
      onTimeout: () => null,
    );
    if (unexpectedError != null || heartbeatOwnershipFailed) {
      throw StateError('PTY worker/root lifecycle validation failed');
    }

    heartbeat.cancel();
    final int workerThread = result[1]! as int;
    final int bytes = result[2]! as int;
    final int batches = result[3]! as int;
    final int minBatch = result[4]! as int;
    final int maxBatch = result[5]! as int;
    final int maxInFlight = result[6]! as int;
    final int waits = result[7]! as int;
    final int xBytes = result[8]! as int;
    final int exitCode = result[9]! as int;
    final int readCalls = result[10]! as int;
    final int scenarioMicros = result[11]! as int;
    final int maxPostMicros = result[12]! as int;
    if (workerThread == rootThread || workerThread == 0) {
      throw StateError('PTY worker did not remain off the main thread');
    }

    final int reportStatus = reportSuccess(elapsed.elapsedMicroseconds);
    stdout.writeln(
      'PHASE0_PTY_DART_${reportStatus == 0 ? 'PASS' : 'FAIL'} '
      'bytes=$bytes batches=$batches min_batch=$minBatch '
      'max_batch=$maxBatch max_in_flight=$maxInFlight waits=$waits '
      'x_bytes=$xBytes exit=$exitCode reads=$readCalls '
      'scenario_us=$scenarioMicros max_post_us=$maxPostMicros '
      'heartbeat_gap_us=$maxHeartbeatGap root_thread=$rootThread '
      'worker_thread=$workerThread report_status=$reportStatus',
    );
    terminate();
  } on Object catch (error, stackTrace) {
    heartbeat.cancel();
    stderr.writeln('PHASE0_PTY_FAIL $error');
    stderr.writeln(stackTrace);
    terminate();
  } finally {
    worker?.kill(priority: Isolate.immediate);
    results.close();
    errors.close();
    exits.close();
  }
}
