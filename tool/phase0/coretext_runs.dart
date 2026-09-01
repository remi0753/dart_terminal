import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _summaryMagic = 0x54435444;
const int _summaryVersion = 1;
const int _summaryBytes = 384;
const int _iterationsPerCase = 64;
const int _requiredFlags = (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7);
const Duration _timeout = Duration(seconds: 10);

typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _Uint64Native = Uint64 Function();
typedef _Uint64Dart = int Function();
typedef _ReportNative = Int32 Function(Uint64);
typedef _ReportDart = int Function(int);

@Native<Int32 Function(Pointer<Uint8>, Uint64, Uint32, Pointer<Uint8>, Uint64)>(
  symbol: 'dt_phase0_coretext_shape',
  isLeaf: true,
)
external int _shape(
  Pointer<Uint8> input,
  int inputLength,
  int caseId,
  Pointer<Uint8> output,
  int outputLength,
);

final DynamicLibrary _process = DynamicLibrary.process();
final _Int32Dart _isMainThread = _process
    .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
final _Uint64Dart _threadId = _process
    .lookupFunction<_Uint64Native, _Uint64Dart>('dt_phase0_aot_thread_id');

class _Case {
  const _Case(this.id, this.label, this.text);

  final int id;
  final String label;
  final String text;
}

const List<_Case> _cases = <_Case>[
  _Case(0, 'latin', 'Hello, terminal!'),
  _Case(1, 'cjk', '日本語漢字かなカナ'),
  _Case(2, 'emoji', 'A👩🏽‍💻🧑‍🚀🇯🇵B'),
  _Case(3, 'ligature', 'office ffi affluent'),
];

class _Summary {
  _Summary(Uint8List bytes)
    : magic = ByteData.sublistView(bytes).getUint32(0, Endian.little),
      version = ByteData.sublistView(bytes).getUint16(4, Endian.little),
      summaryBytes = ByteData.sublistView(bytes).getUint16(6, Endian.little),
      caseId = ByteData.sublistView(bytes).getUint32(8, Endian.little),
      flags = ByteData.sublistView(bytes).getUint32(12, Endian.little),
      utf16Units = ByteData.sublistView(bytes).getUint32(16, Endian.little),
      scalarCount = ByteData.sublistView(bytes).getUint32(20, Endian.little),
      runCount = ByteData.sublistView(bytes).getUint32(24, Endian.little),
      glyphCount = ByteData.sublistView(bytes).getUint32(28, Endian.little),
      uniqueFontCount = ByteData.sublistView(bytes)
          .getUint32(32, Endian.little),
      fallbackRunCount = ByteData.sublistView(bytes)
          .getUint32(36, Endian.little),
      colorGlyphRunCount = ByteData.sublistView(bytes)
          .getUint32(40, Endian.little),
      ligatureClusterCount = ByteData.sublistView(bytes)
          .getUint32(44, Endian.little),
      zeroGlyphCount = ByteData.sublistView(bytes).getUint32(48, Endian.little),
      nonzeroAdvanceCount = ByteData.sublistView(bytes)
          .getUint32(52, Endian.little),
      nonmonotonicIndexCount = ByteData.sublistView(bytes)
          .getUint32(56, Endian.little),
      shapeMicros = ByteData.sublistView(bytes).getUint64(64, Endian.little),
      width = ByteData.sublistView(bytes).getFloat64(72, Endian.little),
      glyphHash = ByteData.sublistView(bytes).getUint64(104, Endian.little),
      fontHash = ByteData.sublistView(bytes).getUint64(112, Endian.little),
      mainThreadViolation = ByteData.sublistView(bytes)
          .getUint32(120, Endian.little),
      errorCode = ByteData.sublistView(bytes).getUint32(124, Endian.little),
      fontNames = _readCString(bytes, 128, 256);

  final int magic;
  final int version;
  final int summaryBytes;
  final int caseId;
  final int flags;
  final int utf16Units;
  final int scalarCount;
  final int runCount;
  final int glyphCount;
  final int uniqueFontCount;
  final int fallbackRunCount;
  final int colorGlyphRunCount;
  final int ligatureClusterCount;
  final int zeroGlyphCount;
  final int nonzeroAdvanceCount;
  final int nonmonotonicIndexCount;
  final int shapeMicros;
  final double width;
  final int glyphHash;
  final int fontHash;
  final int mainThreadViolation;
  final int errorCode;
  final String fontNames;

  List<Object?> toMessage(String label, int nativeP95, int ffiP95) => <Object?>[
    label,
    utf16Units,
    scalarCount,
    runCount,
    glyphCount,
    uniqueFontCount,
    fallbackRunCount,
    colorGlyphRunCount,
    ligatureClusterCount,
    shapeMicros,
    nativeP95,
    ffiP95,
    width,
    fontNames,
    glyphHash,
    fontHash,
  ];
}

String _readCString(Uint8List bytes, int offset, int length) {
  int end = offset;
  final int limit = offset + length;
  while (end < limit && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(offset, end));
}

int _percentile95(List<int> values) {
  values.sort();
  return values[((values.length * 95 + 99) ~/ 100) - 1];
}

void _validateSummary(_Case testCase, _Summary summary) {
  if (summary.magic != _summaryMagic ||
      summary.version != _summaryVersion ||
      summary.summaryBytes != _summaryBytes ||
      summary.caseId != testCase.id ||
      summary.errorCode != 0 ||
      summary.mainThreadViolation != 0) {
    throw StateError('${testCase.label}: invalid summary envelope');
  }
  if ((summary.flags & _requiredFlags) != _requiredFlags ||
      summary.utf16Units != testCase.text.length ||
      summary.scalarCount != testCase.text.runes.length ||
      summary.runCount == 0 ||
      summary.glyphCount == 0 ||
      summary.uniqueFontCount == 0 ||
      summary.zeroGlyphCount != 0 ||
      summary.nonzeroAdvanceCount == 0 ||
      summary.nonmonotonicIndexCount != 0 ||
      !summary.width.isFinite ||
      summary.width <= 0 ||
      summary.fontNames.isEmpty ||
      summary.glyphHash == 0 ||
      summary.fontHash == 0) {
    throw StateError('${testCase.label}: invalid glyph-run content');
  }
  switch (testCase.id) {
    case 0:
      if (summary.fallbackRunCount != 0) {
        throw StateError('latin unexpectedly required fallback');
      }
    case 1:
      if (summary.fallbackRunCount == 0) {
        throw StateError('CJK did not exercise font fallback');
      }
    case 2:
      if (summary.fallbackRunCount == 0 || summary.colorGlyphRunCount == 0) {
        throw StateError('emoji did not produce a color fallback run');
      }
    case 3:
      if (summary.ligatureClusterCount == 0 ||
          summary.glyphCount >= summary.scalarCount) {
        throw StateError(
          'ligature shaping did not collapse a cluster: '
          'clusters=${summary.ligatureClusterCount} '
          'glyphs=${summary.glyphCount} scalars=${summary.scalarCount} '
          'flags=0x${summary.flags.toRadixString(16)} '
          'faces=${summary.fontNames}',
        );
      }
  }
}

@pragma('vm:entry-point')
void _shapeWorker(SendPort rootPort) {
  try {
    final int workerThread = _threadId();
    if (_isMainThread() != 0 || workerThread == 0) {
      throw StateError('CoreText worker ran on the AppKit main thread');
    }
    final Stopwatch all = Stopwatch()..start();
    final List<List<Object?>> results = <List<Object?>>[];
    for (final _Case testCase in _cases) {
      final Uint8List input = Uint8List.fromList(utf8.encode(testCase.text));
      final Uint8List output = Uint8List(_summaryBytes);
      final List<int> nativeMicros = <int>[];
      final List<int> ffiMicros = <int>[];
      _Summary? finalSummary;
      for (int iteration = 0; iteration < _iterationsPerCase; iteration++) {
        output.fillRange(0, output.length, 0);
        final Stopwatch ffiClock = Stopwatch()..start();
        final int status = _shape(
          input.address,
          input.length,
          testCase.id,
          output.address,
          output.length,
        );
        final int ffiMicrosValue = ffiClock.elapsedMicroseconds;
        if (status != 0) {
          throw StateError('${testCase.label}: native status $status');
        }
        final _Summary summary = _Summary(output);
        _validateSummary(testCase, summary);
        nativeMicros.add(summary.shapeMicros);
        ffiMicros.add(ffiMicrosValue);
        finalSummary = summary;
      }
      results.add(
        finalSummary!.toMessage(
          testCase.label,
          _percentile95(nativeMicros),
          _percentile95(ffiMicros),
        ),
      );
    }
    rootPort.send(<Object?>[
      'pass',
      workerThread,
      all.elapsedMicroseconds,
      _iterationsPerCase,
      results,
    ]);
  } on Object catch (error, stackTrace) {
    rootPort.send(<Object?>['error', error.toString(), stackTrace.toString()]);
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
    stderr.writeln('PHASE0_CORETEXT_FAIL root ownership validation');
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

  final ReceivePort results = ReceivePort('phase0-coretext-results');
  final ReceivePort errors = ReceivePort('phase0-coretext-errors');
  final ReceivePort exits = ReceivePort('phase0-coretext-exit');
  Isolate? worker;
  try {
    worker = await Isolate.spawn<SendPort>(
      _shapeWorker,
      results.sendPort,
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
      debugName: 'phase0-coretext-shaper',
    );
    final List<Object?> result =
        (await results.first.timeout(_timeout))! as List<Object?>;
    if (result[0] != 'pass') {
      throw StateError('CoreText worker failed: ${result.skip(1).join('\n')}');
    }
    await exits.first.timeout(_timeout);
    worker = null;
    final Object? unexpectedError = await errors.first.timeout(
      const Duration(milliseconds: 20),
      onTimeout: () => null,
    );
    if (unexpectedError != null || heartbeatOwnershipFailed) {
      throw StateError('CoreText worker/root lifecycle validation failed');
    }

    heartbeat.cancel();
    final int reportStatus = reportSuccess(elapsed.elapsedMicroseconds);
    final List<Object?> shaped = result[4]! as List<Object?>;
    for (final Object? item in shaped) {
      final List<Object?> row = item! as List<Object?>;
      stdout.writeln(
        'PHASE0_CORETEXT_CASE label=${row[0]} utf16=${row[1]} '
        'scalars=${row[2]} runs=${row[3]} glyphs=${row[4]} '
        'fonts=${row[5]} fallback=${row[6]} color=${row[7]} '
        'ligatures=${row[8]} last_native_us=${row[9]} '
        'native_p95_us=${row[10]} ffi_p95_us=${row[11]} '
        'width=${(row[12]! as double).toStringAsFixed(3)} '
        'faces=${row[13]} glyph_hash=${row[14]} font_hash=${row[15]}',
      );
    }
    stdout.writeln(
      'PHASE0_CORETEXT_DART_${reportStatus == 0 ? 'PASS' : 'FAIL'} '
      'cases=${shaped.length} iterations_per_case=${result[3]} '
      'worker_elapsed_us=${result[2]} heartbeat_gap_us=$maxHeartbeatGap '
      'root_thread=$rootThread worker_thread=${result[1]} '
      'report_status=$reportStatus',
    );
    terminate();
  } on Object catch (error, stackTrace) {
    heartbeat.cancel();
    stderr.writeln('PHASE0_CORETEXT_FAIL $error');
    stderr.writeln(stackTrace);
    terminate();
  } finally {
    worker?.kill(priority: Isolate.immediate);
    results.close();
    errors.close();
    exits.close();
  }
}
