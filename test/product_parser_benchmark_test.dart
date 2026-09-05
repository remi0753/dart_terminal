import '../tool/product_parser_benchmark.dart';

void main() => runProductParserBenchmarkTests();

void runProductParserBenchmarkTests() {
  final ProductParserBenchmarkResult result = runProductParserBenchmark(
    targetBytes: 64 * 1024,
    warmupRuns: 1,
    minimumMiBPerSecond: 0.001,
  );
  _expect(result.seedBytes == 65591, 'phase0 mixed seed byte count');
  _expect(result.parsedBytes == 65591, 'one complete seed is parsed');
  _expect(
    result.elapsedMicroseconds > 0 &&
        result.mibPerSecond.isFinite &&
        result.passed,
    'short correctness benchmark has a valid clock result',
  );
  _expect(
    result.textScalars == 28811 &&
        result.controls == 1226 &&
        result.sequences == 2452 &&
        result.integrityHash == 271809813 &&
        result.cancels == 0 &&
        result.limits == 0 &&
        result.malformed == 0 &&
        result.incomplete == 0,
    'short benchmark publishes stable consumption fields',
  );
  _expect(
    result.machineLine().startsWith(
      'PRODUCT_PARSER_BENCHMARK_PASS mode=release-aot '
      'workload=phase0-mixed-v1 seed_bytes=65591 parsed_bytes=65591 ',
    ),
    'benchmark output is machine-readable and versioned by workload',
  );
  _expectThrows(
    () => runProductParserBenchmark(targetBytes: 0),
    'zero target byte count',
  );
  _expectThrows(
    () => runProductParserBenchmark(warmupRuns: -1),
    'negative warmup count',
  );
  _expectThrows(
    () => runProductParserBenchmark(minimumMiBPerSecond: double.nan),
    'non-finite throughput gate',
  );
}

void _expectThrows(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError('Expected ArgumentError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}
