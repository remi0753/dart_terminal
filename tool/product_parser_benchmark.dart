import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const int productParserThroughputTargetBytes = 128 * 1024 * 1024;
const double productParserMinimumMiBPerSecond = 100;
const int _warmupRuns = 16;
const bool _releaseAot = bool.fromEnvironment('dart.vm.product');
const int _expectedSeedTextScalars = 28811;
const int _expectedSeedControls = 1226;
const int _expectedSeedSequences = 2452;
const int _expectedSeedIntegrityHash = 271809813;

final class ProductParserBenchmarkResult {
  const ProductParserBenchmarkResult({
    required this.seedBytes,
    required this.parsedBytes,
    required this.elapsedMicroseconds,
    required this.mibPerSecond,
    required this.minimumMiBPerSecond,
    required this.textScalars,
    required this.controls,
    required this.sequences,
    required this.cancels,
    required this.limits,
    required this.malformed,
    required this.incomplete,
    required this.integrityHash,
  });

  final int seedBytes;
  final int parsedBytes;
  final int elapsedMicroseconds;
  final double mibPerSecond;
  final double minimumMiBPerSecond;
  final int textScalars;
  final int controls;
  final int sequences;
  final int cancels;
  final int limits;
  final int malformed;
  final int incomplete;
  final int integrityHash;

  bool get passed => mibPerSecond >= minimumMiBPerSecond;

  String machineLine() =>
      'PRODUCT_PARSER_BENCHMARK_${passed ? 'PASS' : 'FAIL'} '
      'mode=release-aot workload=phase0-mixed-v1 seed_bytes=$seedBytes '
      'parsed_bytes=$parsedBytes elapsed_us=$elapsedMicroseconds '
      'mib_s=${mibPerSecond.toStringAsFixed(2)} '
      'minimum_mib_s=${minimumMiBPerSecond.toStringAsFixed(2)} '
      'text_scalars=$textScalars controls=$controls sequences=$sequences '
      'cancel=$cancels limit=$limits malformed=$malformed '
      'incomplete=$incomplete integrity_hash=$integrityHash';
}

ProductParserBenchmarkResult runProductParserBenchmark({
  int targetBytes = productParserThroughputTargetBytes,
  int warmupRuns = _warmupRuns,
  double minimumMiBPerSecond = productParserMinimumMiBPerSecond,
}) {
  if (targetBytes <= 0) {
    throw RangeError.value(targetBytes, 'targetBytes', 'must be positive');
  }
  if (warmupRuns < 0 || warmupRuns > 1024) {
    throw RangeError.range(warmupRuns, 0, 1024, 'warmupRuns');
  }
  if (!minimumMiBPerSecond.isFinite || minimumMiBPerSecond <= 0) {
    throw ArgumentError.value(
      minimumMiBPerSecond,
      'minimumMiBPerSecond',
      'must be finite and positive',
    );
  }

  final Uint8List seed = _benchmarkSeed();
  final _BenchmarkSink integritySink = _BenchmarkSink();
  final VtParser integrityParser = VtParser(sink: integritySink);
  integrityParser.parse(seed);
  integrityParser.finish();
  _validateConsumed(integrityParser, integritySink, 'seed integrity');
  final _BenchmarkCounters perSeed = integritySink.snapshot();

  final _NoopBenchmarkSink timedSink = _NoopBenchmarkSink();
  final VtParser timedParser = VtParser(sink: timedSink);
  for (var warmup = 0; warmup < warmupRuns; warmup++) {
    timedParser.reset();
    timedParser.parse(seed);
    timedParser.finish();
    _validateGround(timedParser, 'warmup');
  }

  final int iterations = (targetBytes + seed.length - 1) ~/ seed.length;
  final int parsedBytes = seed.length * iterations;
  timedParser.reset();
  final Stopwatch clock = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration++) {
    timedParser.parse(seed);
  }
  timedParser.finish();
  clock.stop();
  _validateGround(timedParser, 'timed run');
  final int elapsedMicroseconds = clock.elapsedMicroseconds;
  if (elapsedMicroseconds <= 0) {
    throw StateError('product parser benchmark clock did not advance');
  }
  final double mibPerSecond =
      parsedBytes * 1000000 / elapsedMicroseconds / (1024 * 1024);
  return ProductParserBenchmarkResult(
    seedBytes: seed.length,
    parsedBytes: parsedBytes,
    elapsedMicroseconds: elapsedMicroseconds,
    mibPerSecond: mibPerSecond,
    minimumMiBPerSecond: minimumMiBPerSecond,
    textScalars: perSeed.textScalars * iterations,
    controls: perSeed.controls * iterations,
    sequences: perSeed.sequences * iterations,
    cancels: perSeed.cancels * iterations,
    limits: perSeed.limits * iterations,
    malformed: perSeed.malformed * iterations,
    incomplete: perSeed.incomplete * iterations,
    integrityHash: integritySink.actionHash,
  );
}

void _validateConsumed(VtParser parser, _BenchmarkSink sink, String stage) {
  if (!parser.isGround ||
      sink.textScalars != _expectedSeedTextScalars ||
      sink.controls != _expectedSeedControls ||
      sink.sequences != _expectedSeedSequences ||
      sink.cancels != 0 ||
      sink.limits != 0 ||
      sink.malformedCount != 0 ||
      sink.incompleteCount != 0 ||
      sink.actionHash != _expectedSeedIntegrityHash) {
    throw StateError('$stage did not consume the mixed parser workload');
  }
}

void _validateGround(VtParser parser, String stage) {
  if (!parser.isGround) {
    throw StateError('$stage did not finish in the parser ground state');
  }
}

Uint8List _benchmarkSeed() {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Uint8List pattern = Uint8List.fromList(<int>[
    ...utf8.encode(r'prompt $ printf terminal-output-0123456789 '),
    0x1b,
    0x5b,
    ...ascii.encode('38:2::120:180:240m'),
    ...utf8.encode('日本語😀'),
    0x1b,
    0x5b,
    ...ascii.encode('0m'),
    0x0d,
    0x0a,
    0x1b,
    0x5d,
    ...ascii.encode('0;Dart Terminal'),
    0x07,
    0x1b,
    0x50,
    ...ascii.encode(r'$qm'),
    0x1b,
    0x5c,
  ]);
  while (builder.length < 64 * 1024) {
    builder.add(pattern);
  }
  return builder.takeBytes();
}

final class _BenchmarkCounters {
  const _BenchmarkCounters({
    required this.textScalars,
    required this.controls,
    required this.sequences,
    required this.cancels,
    required this.limits,
    required this.malformed,
    required this.incomplete,
  });

  final int textScalars;
  final int controls;
  final int sequences;
  final int cancels;
  final int limits;
  final int malformed;
  final int incomplete;
}

final class _BenchmarkSink
    implements VtParserSink, VtParserAsciiSink, VtParserUncapturedSequenceSink {
  int textScalars = 0;
  int controls = 0;
  int sequences = 0;
  int cancels = 0;
  int limits = 0;
  int malformedCount = 0;
  int incompleteCount = 0;
  int _controlChecksum = 0;
  int _sequenceChecksum = 0;

  int get actionHash {
    var result = 0x811c9dc5 ^ _sequenceChecksum;
    for (final int value in <int>[
      textScalars,
      controls,
      _controlChecksum,
      sequences,
      cancels,
      limits,
      malformedCount,
      incompleteCount,
    ]) {
      result = ((result ^ value) * 0x01000193) & 0x7fffffff;
    }
    return result;
  }

  void reset() {
    textScalars = 0;
    controls = 0;
    sequences = 0;
    cancels = 0;
    limits = 0;
    malformedCount = 0;
    incompleteCount = 0;
    _controlChecksum = 0;
    _sequenceChecksum = 0;
  }

  _BenchmarkCounters snapshot() => _BenchmarkCounters(
    textScalars: textScalars,
    controls: controls,
    sequences: sequences,
    cancels: cancels,
    limits: limits,
    malformed: malformedCount,
    incomplete: incompleteCount,
  );

  @override
  void print(int scalar) {
    textScalars++;
  }

  @override
  void printAscii(Uint8List bytes, int start, int end) {
    textScalars += end - start;
  }

  @override
  void execute(int controlByte) {
    controls++;
    _controlChecksum += controlByte;
  }

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    throw StateError('capture-disabled benchmark received retained ESC');
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    throw StateError('capture-disabled benchmark received retained CSI');
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    throw StateError('capture-disabled benchmark received retained OSC');
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    throw StateError('capture-disabled benchmark received retained DCS');
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    throw StateError('capture-disabled benchmark received retained string');
  }

  @override
  void dispatchUncapturedSequence(
    VtUncapturedSequenceKind kind,
    int privateMarker,
    int parameterCount,
    int intermediateCount,
    int finalByte,
    int payloadLength,
    int terminator,
  ) {
    sequences++;
    _sequenceChecksum =
        (_sequenceChecksum + kind.index + finalByte + payloadLength) &
        0x7fffffff;
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    cancels++;
    _mix(8);
    _mix(state.index);
    _mix(controlByte);
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    limits++;
    _mix(9);
    _mix(state.index);
    _mix(kind.index);
  }

  @override
  void malformed(VtParserState state, int byte) {
    malformedCount++;
    _mix(10);
    _mix(state.index);
    _mix(byte);
  }

  @override
  void incomplete(VtParserState state) {
    incompleteCount++;
    _mix(11);
    _mix(state.index);
  }

  void _mix(int value) {
    _sequenceChecksum = ((_sequenceChecksum ^ value) * 0x01000193) & 0x7fffffff;
  }
}

final class _NoopBenchmarkSink
    implements VtParserSink, VtParserAsciiSink, VtParserUncapturedSequenceSink {
  @override
  void print(int scalar) {}

  @override
  void printAscii(Uint8List bytes, int start, int end) {}

  @override
  void execute(int controlByte) {}

  @override
  void dispatchUncapturedSequence(
    VtUncapturedSequenceKind kind,
    int privateMarker,
    int parameterCount,
    int intermediateCount,
    int finalByte,
    int payloadLength,
    int terminator,
  ) {}

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    throw StateError('capture-disabled benchmark received retained ESC');
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    throw StateError('capture-disabled benchmark received retained CSI');
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    throw StateError('capture-disabled benchmark received retained OSC');
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    throw StateError('capture-disabled benchmark received retained DCS');
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    throw StateError('capture-disabled benchmark received retained string');
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    throw StateError('benchmark workload unexpectedly cancelled a sequence');
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    throw StateError('benchmark workload unexpectedly reached a limit');
  }

  @override
  void malformed(VtParserState state, int byte) {
    throw StateError('benchmark workload unexpectedly became malformed');
  }

  @override
  void incomplete(VtParserState state) {
    throw StateError('benchmark workload unexpectedly ended incomplete');
  }
}

Future<void> main(List<String> arguments) async {
  if (!_releaseAot) {
    stderr.writeln(
      'PRODUCT_PARSER_BENCHMARK_FAIL benchmark must run as Release AOT',
    );
    exitCode = 64;
    return;
  }
  var minimum = productParserMinimumMiBPerSecond;
  for (final String argument in arguments) {
    if (!argument.startsWith('--minimum-mib-per-second=')) {
      stderr.writeln('PRODUCT_PARSER_BENCHMARK_FAIL unknown argument');
      exitCode = 64;
      return;
    }
    final String value = argument.substring('--minimum-mib-per-second='.length);
    final double? parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 1 || parsed > 10000) {
      stderr.writeln('PRODUCT_PARSER_BENCHMARK_FAIL invalid minimum');
      exitCode = 64;
      return;
    }
    minimum = parsed;
  }
  try {
    final ProductParserBenchmarkResult result = runProductParserBenchmark(
      minimumMiBPerSecond: minimum,
    );
    stdout.writeln(result.machineLine());
    if (!result.passed) {
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('PRODUCT_PARSER_BENCHMARK_FAIL $error');
    exitCode = 1;
  }
}
