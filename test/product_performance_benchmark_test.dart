import 'dart:convert';
import 'dart:io';

import '../tool/product_performance_benchmark.dart';
import '../tool/runtime_product_performance_result.dart';

Future<void> main() => runProductPerformanceBenchmarkTests();

Future<void> runProductPerformanceBenchmarkTests() async {
  _testMetricAndBaselineContract();
  _testBaselineFailures();
  _testRuntimeProductPerformanceResult();
  _testCheckedBaselineContract();
  await _testShortProductWorkloads();
}

void _testRuntimeProductPerformanceResult() {
  const String valid =
      'TERMINAL_PRODUCT_PERFORMANCE_TEST refresh_samples=8 '
      'refresh_interval_us=10000 input_samples=7 input_p95_us=100 '
      'visible_p95_us=12000 visible_budget_us=14000 frame_samples=8 '
      'frame_p95_us=6000 frame_budget_us=7000 idle_build_delta=0 '
      'idle_frame_delta=0 occluded_build_delta=0 occluded_frame_delta=0 '
      'resume_frame=true pending_bound=true content_free=true';
  final RuntimeProductPerformanceResult result =
      RuntimeProductPerformanceResult.parse(
        'before\n$valid\nafter\n',
        startupElapsed: const Duration(milliseconds: 800),
      );
  _expect(
    result.startupMicroseconds == 800000 &&
        result.refreshIntervalMicroseconds == 10000 &&
        result.inputP95Microseconds == 100 &&
        result.visibleP95Microseconds == 12000 &&
        result.frameP95Microseconds == 6000,
    'ordinary-product result parser accepts one exact passing line',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      '$valid extra=true',
      startupElapsed: const Duration(milliseconds: 800),
    ),
    'ordinary-product result rejects extra fields',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      '$valid\n$valid',
      startupElapsed: const Duration(milliseconds: 800),
    ),
    'ordinary-product result rejects duplicate lines',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      valid,
      startupElapsed: const Duration(microseconds: 5000001),
    ),
    'ordinary-product result rejects startup over its fixed budget',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      valid.replaceFirst('input_p95_us=100', 'input_p95_us=2000'),
      startupElapsed: const Duration(milliseconds: 800),
    ),
    'ordinary-product result rejects input at the strict 2 ms boundary',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      valid.replaceFirst('visible_p95_us=12000', 'visible_p95_us=14001'),
      startupElapsed: const Duration(milliseconds: 800),
    ),
    'ordinary-product result rejects visible echo over one tier plus slack',
  );
  _expectThrows(
    () => RuntimeProductPerformanceResult.parse(
      valid.replaceFirst('frame_p95_us=6000', 'frame_p95_us=7000'),
      startupElapsed: const Duration(milliseconds: 800),
    ),
    'ordinary-product result rejects frame work at the strict budget',
  );
  _expect(
    RuntimeProductPerformanceResult.parse(
          valid.replaceFirst('input_p95_us=100', 'input_p95_us=9000'),
          startupElapsed: const Duration(seconds: 6),
          enforceLatencyBudgets: false,
        ).inputP95Microseconds ==
        9000,
    'Developer JIT validates structure without acting as release authority',
  );
}

void _testMetricAndBaselineContract() {
  final List<ProductPerformanceMetric> metrics = <ProductPerformanceMetric>[
    ProductPerformanceMetric(
      id: 'parser.test.throughput',
      unit: 'MiB/s',
      direction: ProductPerformanceDirection.higher,
      samples: const <num>[110, 120, 130],
      hardStat: 'min',
      hardOperator: '>=',
      hardValue: 100,
    ),
    ProductPerformanceMetric(
      id: 'input.test.latency',
      unit: 'ns',
      direction: ProductPerformanceDirection.lower,
      samples: const <num>[10, 20, 30, 40, 50],
      hardStat: 'p95',
      hardOperator: '<',
      hardValue: 100,
    ),
  ];
  const Map<String, Object?> environment = <String, Object?>{
    'os': 'macos',
    'abi': 'macos_arm64',
  };
  const Map<String, Object?> provenance = <String, Object?>{
    'workload': 'fixture-v1',
  };
  final ProductPerformanceBaseline baseline = decodeProductPerformanceBaseline(
    jsonEncode(<String, Object?>{
      'format': 'dart-terminal-product-benchmark-baseline',
      'version': 1,
      'id': 'fixture-baseline',
      'environment': environment,
      'provenance': provenance,
      'metrics': <String, Object?>{
        'parser.test.throughput': <String, Object?>{
          'stat': 'p50',
          'reference': 120,
          'relative_tolerance': 0.1,
          'absolute_slack': 0,
        },
        'input.test.latency': <String, Object?>{
          'stat': 'p95',
          'reference': 50,
          'relative_tolerance': 0.1,
          'absolute_slack': 1,
        },
      },
    }),
  );
  final ProductPerformanceRun result = evaluateProductPerformance(
    metrics: metrics,
    environment: environment,
    provenance: provenance,
    integrity: const <String, Object?>{'checksum': 7},
    baseline: baseline,
  );
  final String encoded = result.encode();
  final Map<String, Object?> decoded =
      jsonDecode(encoded) as Map<String, Object?>;
  final List<Object?> encodedMetrics = decoded['metrics']! as List<Object?>;
  _expect(
    result.passed &&
        decoded['format'] == 'dart-terminal-product-benchmark-result' &&
        decoded['version'] == 1 &&
        decoded['status'] == 'pass' &&
        decoded['baseline_id'] == 'fixture-baseline' &&
        encodedMetrics.length == 2 &&
        ((encodedMetrics.last! as Map<String, Object?>)['p95'] as num) == 50 &&
        encoded.endsWith('\n') &&
        !encoded.contains('/Users/') &&
        !encoded.contains('command'),
    'versioned product benchmark result is deterministic and content-free',
  );

  final ProductPerformanceBaseline impossible =
      decodeProductPerformanceBaseline(
        jsonEncode(<String, Object?>{
          'format': 'dart-terminal-product-benchmark-baseline',
          'version': 1,
          'id': 'impossible-baseline',
          'environment': environment,
          'provenance': provenance,
          'metrics': <String, Object?>{
            'parser.test.throughput': <String, Object?>{
              'stat': 'p50',
              'reference': 1000,
              'relative_tolerance': 0,
              'absolute_slack': 0,
            },
            'input.test.latency': <String, Object?>{
              'stat': 'p95',
              'reference': 50,
              'relative_tolerance': 0.1,
              'absolute_slack': 1,
            },
          },
        }),
      );
  _expect(
    !evaluateProductPerformance(
      metrics: metrics,
      environment: environment,
      provenance: provenance,
      integrity: const <String, Object?>{'checksum': 7},
      baseline: impossible,
    ).passed,
    'an impossible accepted-product threshold fails without moving baseline',
  );
}

void _testBaselineFailures() {
  const String valid =
      '{"format":"dart-terminal-product-benchmark-baseline",'
      '"version":1,"id":"fixture","environment":{"os":"macos"},'
      '"provenance":{"workload":"v1"},"metrics":{"metric.one":{'
      '"stat":"p95","reference":1,"relative_tolerance":0.1,'
      '"absolute_slack":0}}}';
  final ProductPerformanceBaseline baseline = decodeProductPerformanceBaseline(
    valid,
  );
  _expectThrows(
    () => decodeProductPerformanceBaseline(
      valid.replaceFirst('"version":1', '"version":1,"extra":true'),
    ),
    'unknown baseline key',
  );
  _expectThrows(
    () => decodeProductPerformanceBaseline(
      valid.replaceFirst('"relative_tolerance":0.1', '"relative_tolerance":1'),
    ),
    'unbounded relative tolerance',
  );
  final ProductPerformanceMetric metric = ProductPerformanceMetric(
    id: 'metric.one',
    unit: 'us',
    direction: ProductPerformanceDirection.lower,
    samples: const <num>[1, 1, 1],
    hardStat: 'p95',
    hardOperator: '<',
    hardValue: 2,
  );
  _expectThrows(
    () => evaluateProductPerformance(
      metrics: <ProductPerformanceMetric>[metric],
      environment: const <String, Object?>{'os': 'linux'},
      provenance: const <String, Object?>{'workload': 'v1'},
      integrity: const <String, Object?>{},
      baseline: baseline,
    ),
    'incompatible environment',
  );
  _expectThrows(
    () => evaluateProductPerformance(
      metrics: <ProductPerformanceMetric>[
        ProductPerformanceMetric(
          id: 'metric.two',
          unit: 'us',
          direction: ProductPerformanceDirection.lower,
          samples: const <num>[1],
          hardStat: 'p95',
          hardOperator: '<',
          hardValue: 2,
        ),
      ],
      environment: const <String, Object?>{'os': 'macos'},
      provenance: const <String, Object?>{'workload': 'v1'},
      integrity: const <String, Object?>{},
      baseline: baseline,
    ),
    'different metric inventory',
  );
  _expectThrows(
    () => decodeProductPerformanceBaseline(' ' * (64 * 1024 + 1)),
    'oversized baseline',
  );
}

void _testCheckedBaselineContract() {
  final ProductPerformanceBaseline baseline = decodeProductPerformanceBaseline(
    File('benchmark/baselines/product-micro-macos-arm64-m1.json')
        .readAsStringSync(),
  );
  _expect(
    baseline.id == 'product-micro-macos-arm64-m1' &&
        baseline.metrics.keys.toSet().containsAll(const <String>{
          'parser.product_mixed.throughput',
          'render.damage.capture_copy_latency',
          'render.damage.transfer_decode_ack_latency',
          'render.damage.end_to_end_latency',
          'input.key_to_pane_write_latency',
        }) &&
        baseline.metrics.length == 5,
    'checked M1 baseline retains the exact product metric inventory',
  );
}

Future<void> _testShortProductWorkloads() async {
  final ProductPerformanceRun result =
      await runProductPerformanceMicrobenchmark(
        parserSampleCount: 3,
        parserTargetBytes: 64 * 1024,
        damageWarmupIterations: 0,
        damageTimedIterations: 3,
        inputWarmupIterations: 8,
        inputTimedIterations: 24,
        environment: const <String, Object?>{
          'os': 'macos',
          'abi': 'test',
          'dart_sdk': 'test',
          'build_mode': 'test',
          'hardware_model': 'test',
          'memory_bytes': 1,
        },
      );
  final List<Object?> metrics = result.document['metrics']! as List<Object?>;
  final Map<String, Object?> integrity =
      result.document['integrity']! as Map<String, Object?>;
  final Map<String, Object?> input =
      integrity['input']! as Map<String, Object?>;
  _expect(
    metrics.length == 5 &&
        input['events'] == 24 &&
        input['writes'] == 24 &&
        input['queue_rejections'] == 0 &&
        (input['queue_peak_bytes']! as int) <=
            (input['queue_capacity_bytes']! as int),
    'short real product workloads retain exact integrity and bounded input',
  );
}

void _expectThrows(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  } on FormatException {
    return;
  } on StateError {
    return;
  }
  throw StateError('Expected failure: $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('Expectation failed: $description');
}
