import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _frameMagic = 0x4c475444;
const int _frameVersion = 1;
const int _headerBytes = 32;
const int _instanceStride = 32;
const int _instanceCount = 100000;
const int _targetFrames = 120;
const Duration _testTimeout = Duration(seconds: 10);

typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _Uint32ArgNative = Int32 Function(Uint32);
typedef _Uint32ArgDart = int Function(int);
typedef _Uint64Native = Uint64 Function();
typedef _Uint64Dart = int Function();
typedef _ReportNative = Int32 Function(Uint64);
typedef _ReportDart = int Function(int);

@Native<Int32 Function(Pointer<Uint8>, Uint64, Uint64)>(
  symbol: 'dt_phase0_metal_submit',
  isLeaf: true,
)
external int _submitMetalFrame(
  Pointer<Uint8> bytes,
  int length,
  int generation,
);

final DynamicLibrary _process = DynamicLibrary.process();
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
final _Uint64Dart _threadId = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>('dt_phase0_aot_thread_id');
final _Uint64Dart _completedFrames = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>(
      'dt_phase0_metal_completed_frames',
    );
final _Uint64Dart _acceptedSubmissions = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>(
      'dt_phase0_metal_accepted_submissions',
    );
final _Uint64Dart _backpressureRejections = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>(
      'dt_phase0_metal_backpressure_rejections',
    );

Uint8List _buildPackedFrame() {
  final int totalBytes = _headerBytes + _instanceCount * _instanceStride;
  final Uint8List bytes = Uint8List(totalBytes);
  final ByteData data = ByteData.sublistView(bytes);
  data.setUint32(0, _frameMagic, Endian.little);
  data.setUint16(4, _frameVersion, Endian.little);
  data.setUint16(6, _headerBytes, Endian.little);
  data.setUint32(8, _instanceStride, Endian.little);
  data.setUint32(12, _instanceCount, Endian.little);
  data.setUint32(16, totalBytes, Endian.little);
  data.setUint32(20, 0, Endian.little);
  data.setUint64(24, 1, Endian.little);

  const int columns = 500;
  const double cellWidth = 960 / columns;
  const double cellHeight = 600 / 200;
  for (int index = 0; index < _instanceCount; index++) {
    final int column = index % columns;
    final int row = index ~/ columns;
    final int offset = _headerBytes + index * _instanceStride;
    data.setFloat32(offset, column * cellWidth, Endian.little);
    data.setFloat32(offset + 4, row * cellHeight, Endian.little);
    data.setFloat32(offset + 8, cellWidth * 0.88, Endian.little);
    data.setFloat32(offset + 12, cellHeight * 0.84, Endian.little);
    final int red = 80 + (index % 150);
    final int green = 110 + (row % 120);
    final int blue = 160 + (column % 90);
    final int rgba = 0xff000000 | (blue << 16) | (green << 8) | red;
    data.setUint32(offset + 16, rgba, Endian.little);
    data.setUint32(offset + 20, 32 + (index % 95), Endian.little);
    data.setUint32(offset + 24, index.isEven ? 1 : 0, Endian.little);
    data.setUint32(offset + 28, 0, Endian.little);
  }
  return bytes;
}

@pragma('vm:entry-point')
Future<void> _renderWorker(SendPort rootPort) async {
  try {
    final int workerThread = _threadId();
    if (_isMainThread() != 0 || workerThread == 0) {
      throw StateError('render worker ran on the AppKit main thread');
    }

    final Stopwatch buildClock = Stopwatch()..start();
    final Uint8List packedFrame = _buildPackedFrame();
    final int buildMicros = buildClock.elapsedMicroseconds;
    final ByteData header = ByteData.sublistView(packedFrame, 0, _headerBytes);
    final Stopwatch submitClock = Stopwatch()..start();
    int generation = 1;
    int accepted = 0;
    int backpressure = 0;
    while (_completedFrames() < _targetFrames &&
        submitClock.elapsed < const Duration(seconds: 8)) {
      header.setUint64(24, generation, Endian.little);
      final int status = _submitMetalFrame(
        packedFrame.address,
        packedFrame.length,
        generation,
      );
      if (status == 0) {
        accepted++;
      } else if (status == 2) {
        backpressure++;
      } else {
        throw StateError('Metal submit failed: $status at $generation');
      }
      generation++;
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }

    final int completed = _completedFrames();
    if (completed < _targetFrames || _isMainThread() != 0) {
      throw TimeoutException('Metal completed only $completed frames');
    }
    rootPort.send(<Object?>[
      'pass',
      workerThread,
      buildMicros,
      submitClock.elapsedMicroseconds,
      accepted,
      backpressure,
      completed,
      _acceptedSubmissions(),
      _backpressureRejections(),
      packedFrame.length,
    ]);
  } on Object catch (error, stackTrace) {
    rootPort.send(<Object?>['error', error.toString(), stackTrace.toString()]);
  }
}

Future<void> main() async {
  final _Int32Dart showWindow = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_show_window');
  final _Uint32ArgDart createRenderer = _process
      .lookupFunction<_Uint32ArgNative, _Uint32ArgDart>(
        'dt_phase0_metal_create',
      );
  final _Int32Dart validateAndStop = _process
      .lookupFunction<_Int32Native, _Int32Dart>(
        'dt_phase0_metal_validate_and_stop',
      );
  final _ReportDart reportSuccess = _process
      .lookupFunction<_ReportNative, _ReportDart>(
        'dt_phase0_aot_report_success',
      );
  final _Int32Dart terminate = _process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_terminate');

  final int rootThread = _threadId();
  if (_isMainThread() != 1 || rootThread == 0 || showWindow() != 0) {
    stderr.writeln('PHASE0_METAL_FAIL root ownership validation');
    terminate();
    return;
  }
  final Stopwatch elapsed = Stopwatch()..start();
  final int createStatus = createRenderer(_instanceCount);
  final int createMicros = elapsed.elapsedMicroseconds;
  if (createStatus != 0) {
    stderr.writeln('PHASE0_METAL_FAIL create status=$createStatus');
    terminate();
    return;
  }

  int previousHeartbeat = elapsed.elapsedMicroseconds;
  int maxHeartbeatGap = 0;
  bool heartbeatOwnershipFailed = false;
  final Timer heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final int now = elapsed.elapsedMicroseconds;
    final int gap = now - previousHeartbeat;
    maxHeartbeatGap = gap > maxHeartbeatGap ? gap : maxHeartbeatGap;
    previousHeartbeat = now;
    if (_isMainThread() != 1 || _threadId() != rootThread) {
      heartbeatOwnershipFailed = true;
    }
  });

  final ReceivePort results = ReceivePort('phase0-metal-results');
  final ReceivePort errors = ReceivePort('phase0-metal-worker-errors');
  final ReceivePort exits = ReceivePort('phase0-metal-worker-exit');
  Isolate? worker;
  try {
    worker = await Isolate.spawn<SendPort>(
      _renderWorker,
      results.sendPort,
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
      debugName: 'phase0-render-coordinator',
    );
    final List<Object?> result =
        (await results.first.timeout(_testTimeout))! as List<Object?>;
    if (result[0] != 'pass') {
      throw StateError('Metal worker failed: ${result.skip(1).join('\n')}');
    }
    await exits.first.timeout(_testTimeout);
    worker = null;
    final Object? unexpectedError = await errors.first.timeout(
      const Duration(milliseconds: 20),
      onTimeout: () => null,
    );
    if (unexpectedError != null || heartbeatOwnershipFailed) {
      throw StateError('Metal worker/root lifecycle validation failed');
    }

    heartbeat.cancel();
    final int validationStatus = validateAndStop();
    if (validationStatus != 0) {
      throw StateError('native Metal validation failed: $validationStatus');
    }
    final int reportStatus = reportSuccess(elapsed.elapsedMicroseconds);
    stdout.writeln(
      'PHASE0_METAL_DART_${reportStatus == 0 ? 'PASS' : 'FAIL'} '
      'instances=$_instanceCount frame_bytes=${result[9]} '
      'build_us=${result[2]} submit_test_us=${result[3]} '
      'accepted=${result[4]}/${result[7]} '
      'backpressure=${result[5]}/${result[8]} frames=${result[6]} '
      'create_us=$createMicros heartbeat_gap_us=$maxHeartbeatGap '
      'root_thread=$rootThread worker_thread=${result[1]} '
      'report_status=$reportStatus',
    );
    terminate();
  } on Object catch (error, stackTrace) {
    heartbeat.cancel();
    stderr.writeln('PHASE0_METAL_FAIL $error');
    stderr.writeln(stackTrace);
    terminate();
  } finally {
    worker?.kill(priority: Isolate.immediate);
    results.close();
    errors.close();
    exits.close();
  }
}
