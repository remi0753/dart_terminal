import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

const int _summaryMagic = 0x454d4944;
const int _summaryVersion = 1;
const int _summaryBytes = 256;
const int _requiredFlags = (1 << 10) - 1;
const int _iterations = 64;

typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _Uint64Native = Uint64 Function();
typedef _Uint64Dart = int Function();
typedef _ReportNative = Int32 Function(Uint64);
typedef _ReportDart = int Function(int);

@Native<Int32 Function(Pointer<Uint8>, Uint64)>(
  symbol: 'dt_phase0_ime_run',
  isLeaf: true,
)
external int _runIme(Pointer<Uint8> output, int outputLength);

final DynamicLibrary _process = DynamicLibrary.process();
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
final _Uint64Dart _threadId = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>('dt_phase0_aot_thread_id');

class _Summary {
  _Summary(Uint8List bytes)
    : magic = ByteData.sublistView(bytes).getUint32(0, Endian.little),
      version = ByteData.sublistView(bytes).getUint16(4, Endian.little),
      summaryBytes = ByteData.sublistView(bytes).getUint16(6, Endian.little),
      flags = ByteData.sublistView(bytes).getUint32(8, Endian.little),
      eventCount = ByteData.sublistView(bytes).getUint32(12, Endian.little),
      markedUpdates = ByteData.sublistView(bytes).getUint32(16, Endian.little),
      commits = ByteData.sublistView(bytes).getUint32(20, Endian.little),
      unmarks = ByteData.sublistView(bytes).getUint32(24, Endian.little),
      candidateQueries = ByteData.sublistView(bytes)
          .getUint32(28, Endian.little),
      rawDelivered = ByteData.sublistView(bytes).getUint32(32, Endian.little),
      rawSuppressed = ByteData.sublistView(bytes).getUint32(36, Endian.little),
      finalDocumentUtf16 = ByteData.sublistView(bytes)
          .getUint32(40, Endian.little),
      finalSelectionLocation = ByteData.sublistView(bytes)
          .getUint32(44, Endian.little),
      firstMarkedLocation = ByteData.sublistView(bytes)
          .getUint32(48, Endian.little),
      firstMarkedLength = ByteData.sublistView(bytes)
          .getUint32(52, Endian.little),
      candidateActualLocation = ByteData.sublistView(bytes)
          .getUint32(56, Endian.little),
      candidateActualLength = ByteData.sublistView(bytes)
          .getUint32(60, Endian.little),
      scenarioMicros = ByteData.sublistView(bytes).getUint64(64, Endian.little),
      screenX = ByteData.sublistView(bytes).getFloat64(72, Endian.little),
      screenY = ByteData.sublistView(bytes).getFloat64(80, Endian.little),
      screenWidth = ByteData.sublistView(bytes).getFloat64(88, Endian.little),
      screenHeight = ByteData.sublistView(bytes).getFloat64(96, Endian.little),
      localX = ByteData.sublistView(bytes).getFloat64(104, Endian.little),
      localY = ByteData.sublistView(bytes).getFloat64(112, Endian.little),
      localWidth = ByteData.sublistView(bytes).getFloat64(120, Endian.little),
      localHeight = ByteData.sublistView(bytes).getFloat64(128, Endian.little),
      eventHash = ByteData.sublistView(bytes).getUint64(136, Endian.little),
      mainThreadViolation = ByteData.sublistView(bytes)
          .getUint32(144, Endian.little),
      errorCode = ByteData.sublistView(bytes).getUint32(148, Endian.little),
      finalDocument = _readCString(bytes, 152, 64),
      eventOrder = _readCString(bytes, 216, 40);

  final int magic;
  final int version;
  final int summaryBytes;
  final int flags;
  final int eventCount;
  final int markedUpdates;
  final int commits;
  final int unmarks;
  final int candidateQueries;
  final int rawDelivered;
  final int rawSuppressed;
  final int finalDocumentUtf16;
  final int finalSelectionLocation;
  final int firstMarkedLocation;
  final int firstMarkedLength;
  final int candidateActualLocation;
  final int candidateActualLength;
  final int scenarioMicros;
  final double screenX;
  final double screenY;
  final double screenWidth;
  final double screenHeight;
  final double localX;
  final double localY;
  final double localWidth;
  final double localHeight;
  final int eventHash;
  final int mainThreadViolation;
  final int errorCode;
  final String finalDocument;
  final String eventOrder;
}

String _readCString(Uint8List bytes, int offset, int length) {
  int end = offset;
  while (end < offset + length && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(offset, end));
}

int _percentile95(List<int> values) {
  values.sort();
  return values[((values.length * 95 + 99) ~/ 100) - 1];
}

void _validate(_Summary summary) {
  if (summary.magic != _summaryMagic ||
      summary.version != _summaryVersion ||
      summary.summaryBytes != _summaryBytes ||
      summary.flags != _requiredFlags ||
      summary.mainThreadViolation != 0 ||
      summary.errorCode != 0 ||
      summary.eventCount != 8 ||
      summary.markedUpdates != 3 ||
      summary.commits != 1 ||
      summary.unmarks != 1 ||
      summary.candidateQueries != 1 ||
      summary.rawDelivered != 2 ||
      summary.rawSuppressed != 1 ||
      summary.finalDocumentUtf16 != 11 ||
      summary.finalSelectionLocation != 11 ||
      summary.firstMarkedLocation != 8 ||
      summary.firstMarkedLength != 3 ||
      summary.candidateActualLocation != 8 ||
      summary.candidateActualLength != 3 ||
      summary.finalDocument != 'prompt> 日本語' ||
      summary.eventOrder != 'R,P,X,P,C,R,P,U' ||
      summary.eventHash == 0 ||
      !summary.screenX.isFinite ||
      !summary.screenY.isFinite ||
      summary.screenWidth != summary.localWidth ||
      summary.screenHeight != summary.localHeight) {
    throw StateError(
      'invalid IME summary flags=0x${summary.flags.toRadixString(16)} '
      'error=${summary.errorCode} events=${summary.eventOrder} '
      'document=${summary.finalDocument}',
    );
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
    stderr.writeln('PHASE0_IME_FAIL root ownership validation');
    terminate();
    return;
  }

  final Stopwatch elapsed = Stopwatch()..start();
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

  try {
    final Uint8List output = Uint8List(_summaryBytes);
    final List<int> nativeMicros = <int>[];
    final List<int> ffiMicros = <int>[];
    int maxNativeMicros = 0;
    int maxFfiMicros = 0;
    int? stableEventHash;
    _Summary? finalSummary;
    for (int iteration = 0; iteration < _iterations; iteration++) {
      output.fillRange(0, output.length, 0);
      final Stopwatch ffiClock = Stopwatch()..start();
      final int status = _runIme(output.address, output.length);
      final int ffiValue = ffiClock.elapsedMicroseconds;
      if (status != 0) {
        throw StateError('native IME status $status');
      }
      final _Summary summary = _Summary(output);
      _validate(summary);
      stableEventHash ??= summary.eventHash;
      if (stableEventHash != summary.eventHash) {
        throw StateError('IME event order hash changed');
      }
      nativeMicros.add(summary.scenarioMicros);
      ffiMicros.add(ffiValue);
      maxNativeMicros = summary.scenarioMicros > maxNativeMicros
          ? summary.scenarioMicros
          : maxNativeMicros;
      maxFfiMicros = ffiValue > maxFfiMicros ? ffiValue : maxFfiMicros;
      finalSummary = summary;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (heartbeatOwnershipFailed || _isMainThread() != 1) {
      throw StateError('IME heartbeat ownership failed');
    }
    heartbeat.cancel();
    final int reportStatus = reportSuccess(elapsed.elapsedMicroseconds);
    stdout.writeln(
      'PHASE0_IME_DART_${reportStatus == 0 ? 'PASS' : 'FAIL'} '
      'iterations=$_iterations events=${finalSummary!.eventOrder} '
      'marked=${finalSummary.markedUpdates} commits=${finalSummary.commits} '
      'unmarks=${finalSummary.unmarks} raw=${finalSummary.rawDelivered} '
      'raw_suppressed=${finalSummary.rawSuppressed} '
      'candidate_screen=${finalSummary.screenX.toStringAsFixed(1)},'
      '${finalSummary.screenY.toStringAsFixed(1)},'
      '${finalSummary.screenWidth.toStringAsFixed(1)},'
      '${finalSummary.screenHeight.toStringAsFixed(1)} '
      'native_p95_us=${_percentile95(nativeMicros)} '
      'native_max_us=$maxNativeMicros ffi_p95_us=${_percentile95(ffiMicros)} '
      'ffi_max_us=$maxFfiMicros heartbeat_gap_us=$maxHeartbeatGap '
      'root_thread=$rootThread report_status=$reportStatus '
      'document=${finalSummary.finalDocument}',
    );
    terminate();
  } on Object catch (error, stackTrace) {
    heartbeat.cancel();
    stderr.writeln('PHASE0_IME_FAIL $error');
    stderr.writeln(stackTrace);
    terminate();
  }
}
