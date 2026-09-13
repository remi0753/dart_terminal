import 'dart:convert';
import 'dart:io';

import '../tool/product_performance_regression_gate.dart';

void main() => runProductPerformanceRegressionGateTests();

void runProductPerformanceRegressionGateTests() {
  _testPassingAggregateAndPrivacy();
  _testMicrobenchmarkFailures();
  _testRuntimeAndRelativeFailures();
  _testCheckedAggregateEvidence();
}

void _testPassingAggregateAndPrivacy() {
  final String micro = jsonEncode(_microbenchmark());
  final String runtime = _runtime();
  final String comparator = _checkedComparator();
  final ProductPerformanceAggregateResult result =
      buildProductPerformanceAggregate(
        microbenchmarkSource: micro,
        runtimeSource: runtime,
        comparatorSource: comparator,
      );
  final String encoded = result.encode();
  final Map<String, Object?> document =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> integrity =
      document['input_integrity']! as Map<String, Object?>;
  _expect(
    result.passed &&
        document['format'] == productPerformanceAggregateFormat &&
        document['version'] == 1 &&
        document['status'] == 'pass' &&
        integrity.values.every(
          (Object? value) =>
              value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
        ) &&
        encoded.endsWith('\n') &&
        !encoded.contains('/Users/private/terminal-content') &&
        !encoded.contains('secret-command') &&
        !encoded.contains('"raw_samples":'),
    'passing aggregate binds content-free input identities and all gate groups',
  );
}

void _testMicrobenchmarkFailures() {
  final Map<String, Object?> failedStatus = _microbenchmark();
  failedStatus['status'] = 'fail';
  _expectThrows(
    () => _build(microbenchmark: failedStatus),
    'failed microbenchmark status',
  );

  final Map<String, Object?> falseHardClaim = _microbenchmark();
  final Map<String, Object?> capture = _metricById(
    falseHardClaim,
    'render.damage.capture_copy_latency',
  );
  capture['p95'] = 4000;
  capture['p99'] = 4000;
  capture['max'] = 4000;
  _expectThrows(
    () => _build(microbenchmark: falseHardClaim),
    'false passing hard-gate claim',
  );

  final Map<String, Object?> falseBaselineClaim = _microbenchmark();
  final Map<String, Object?> parser = _metricById(
    falseBaselineClaim,
    'parser.product_mixed.throughput',
  );
  (parser['baseline_gate']! as Map<String, Object?>)['threshold'] = 1;
  _expectThrows(
    () => _build(microbenchmark: falseBaselineClaim),
    'forged baseline threshold',
  );

  final Map<String, Object?> extraMetricKey = _microbenchmark();
  _metricById(
    extraMetricKey,
    'input.key_to_pane_write_latency',
  )['raw_samples'] = <int>[
    1,
  ];
  _expectThrows(
    () => _build(microbenchmark: extraMetricKey),
    'raw sample or unknown metric field',
  );
}

void _testRuntimeAndRelativeFailures() {
  _expectThrows(
    () => _build(
      runtime: _runtime().replaceFirst('fairness=true', 'fairness=false'),
    ),
    'missing successful fairness claim',
  );
  _expectThrows(
    () => _build(
      runtime: _runtime().replaceFirst(
        'startup_us=700000',
        'startup_us=5000001',
      ),
    ),
    'startup beyond the fixed product budget',
  );
  _expectThrows(
    () => _build(
      runtime: _runtime().replaceFirst('input_p95_us=100', 'input_p95_us=2000'),
    ),
    'input at the strict 2 ms boundary',
  );

  final ProductPerformanceAggregateResult relativeFailure = _build(
    runtime: _runtime()
        .replaceFirst('idle_rss_bytes=120000000', 'idle_rss_bytes=200000000')
        .replaceFirst('peak_rss_bytes=130000000', 'peak_rss_bytes=200000000'),
  );
  _expect(
    !relativeFailure.passed &&
        relativeFailure.document['status'] == 'fail' &&
        (relativeFailure.document['gates']!
                as Map<String, Object?>)['passed'] ==
            false,
    'an absolute passing product still fails the aggregate relative RSS gate',
  );

  final Map<String, Object?> incompatible = _microbenchmark();
  (incompatible['environment']! as Map<String, Object?>)['memory_bytes'] = 1;
  _expectThrows(
    () => _build(microbenchmark: incompatible),
    'incompatible product/comparator environment',
  );
  _expectThrows(
    () => buildProductPerformanceAggregate(
      microbenchmarkSource: ' ' * (64 * 1024 + 1),
      runtimeSource: _runtime(),
      comparatorSource: _checkedComparator(),
    ),
    'oversized aggregate input',
  );
}

void _testCheckedAggregateEvidence() {
  final File evidence = File(
    'benchmark/evidence/product-performance-regression-macos-arm64-m1.json',
  );
  _expect(evidence.existsSync(), 'checked aggregate evidence exists');
  final String source = evidence.readAsStringSync();
  final Map<String, Object?> document =
      jsonDecode(source) as Map<String, Object?>;
  final Map<String, Object?> gates = document['gates']! as Map<String, Object?>;
  final List<Object?> relative = gates['relative']! as List<Object?>;
  _expect(
    source.length <= 64 * 1024 &&
        document.keys.toSet().difference(const <String>{
          'format',
          'version',
          'status',
          'input_integrity',
          'environment',
          'product',
          'comparator',
          'policy',
          'gates',
        }).isEmpty &&
        document['format'] == productPerformanceAggregateFormat &&
        document['version'] == 1 &&
        document['status'] == 'pass' &&
        gates['product_micro'] == true &&
        gates['ordinary_product'] == true &&
        gates['cross_pane_fairness'] == true &&
        gates['passed'] == true &&
        relative.length == 4 &&
        relative.every(
          (Object? value) => (value! as Map<String, Object?>)['passed'] == true,
        ) &&
        !source.contains('/Users/') &&
        !source.contains('terminal_text') &&
        !source.contains('command_line') &&
        !source.contains('timestamp') &&
        !source.contains('process_id') &&
        !source.contains('"raw_samples":'),
    'checked aggregate evidence is exact, passing, bounded, and content-free',
  );
}

ProductPerformanceAggregateResult _build({
  Map<String, Object?>? microbenchmark,
  String? runtime,
}) => buildProductPerformanceAggregate(
  microbenchmarkSource: jsonEncode(microbenchmark ?? _microbenchmark()),
  runtimeSource: runtime ?? _runtime(),
  comparatorSource: _checkedComparator(),
);

String _checkedComparator() => File(
  'benchmark/evidence/ghostty-performance-comparator-macos-arm64-m1.json',
).readAsStringSync();

Map<String, Object?> _microbenchmark() => <String, Object?>{
  'format': 'dart-terminal-product-benchmark-result',
  'version': 1,
  'suite': 'product-micro',
  'status': 'pass',
  'baseline_id': 'product-micro-macos-arm64-m1',
  'environment': <String, Object?>{
    'os': 'macos',
    'abi': 'macos_arm64',
    'dart_sdk': '3.13.2',
    'build_mode': 'release-aot',
    'hardware_model': 'MacBookPro17,1',
    'memory_bytes': 17179869184,
  },
  'provenance': <String, Object?>{
    'workload': 'phase11-product-micro-v1',
    'parser_workload': 'phase0-mixed-v1-product-vt-parser',
    'parser_target_bytes': 134217728,
    'parser_seed_bytes': 65591,
    'damage_packet_version': 2,
    'damage_rows': 200,
    'damage_columns': 500,
    'damage_iterations': 64,
    'input_route': 'terminal-key-router-pane-write-v1',
    'input_iterations': 100000,
    'measurement_policy_version': 1,
  },
  'measurement_policy': <String, Object?>{
    'clock': 'dart-stopwatch-monotonic',
    'percentiles': <int>[50, 95, 99],
    'warmup_required': true,
    'raw_samples_retained': false,
  },
  'metrics': <Object?>[
    _metric(
      id: 'parser.product_mixed.throughput',
      unit: 'MiB/s',
      direction: 'higher',
      sampleCount: 5,
      minimum: 105,
      p50: 110,
      p95: 115,
      p99: 115,
      maximum: 115,
      hardStat: 'min',
      hardOperator: '>=',
      hardValue: 100,
      baselineStat: 'p50',
      reference: 110.28,
      tolerance: 0.08,
      slack: 0,
      threshold: 101.4576,
    ),
    _metric(
      id: 'render.damage.capture_copy_latency',
      unit: 'us',
      direction: 'lower',
      sampleCount: 64,
      minimum: 300,
      p50: 350,
      p95: 400,
      p99: 450,
      maximum: 500,
      hardStat: 'p95',
      hardOperator: '<',
      hardValue: 4000,
      baselineStat: 'p95',
      reference: 456,
      tolerance: 0.25,
      slack: 100,
      threshold: 670,
    ),
    _metric(
      id: 'render.damage.transfer_decode_ack_latency',
      unit: 'us',
      direction: 'lower',
      sampleCount: 64,
      minimum: 1000,
      p50: 1100,
      p95: 1200,
      p99: 1250,
      maximum: 1300,
      hardStat: 'p95',
      hardOperator: '<',
      hardValue: 4000,
      baselineStat: 'p95',
      reference: 1351,
      tolerance: 0.2,
      slack: 100,
      threshold: 1721.2,
    ),
    _metric(
      id: 'render.damage.end_to_end_latency',
      unit: 'us',
      direction: 'lower',
      sampleCount: 64,
      minimum: 1400,
      p50: 1500,
      p95: 1600,
      p99: 1650,
      maximum: 1700,
      hardStat: 'p95',
      hardOperator: '<',
      hardValue: 8000,
      baselineStat: 'p95',
      reference: 1815,
      tolerance: 0.2,
      slack: 200,
      threshold: 2378,
    ),
    _metric(
      id: 'input.key_to_pane_write_latency',
      unit: 'ns',
      direction: 'lower',
      sampleCount: 100000,
      minimum: 300,
      p50: 350,
      p95: 400,
      p99: 450,
      maximum: 500,
      hardStat: 'p95',
      hardOperator: '<',
      hardValue: 2000000,
      baselineStat: 'p95',
      reference: 375,
      tolerance: 0.5,
      slack: 250,
      threshold: 812.5,
    ),
  ],
  'integrity': <String, Object?>{
    'parser': <String, Object?>{
      'parsed_bytes_per_sample': 134264777,
      'action_hash': 271809813,
      'text_scalars': 58976117,
      'controls': 2509622,
      'sequences': 5019244,
    },
    'damage': <String, Object?>{
      'packet_bytes': 1704904,
      'transferred_bytes': 109113856,
      'iterations': 64,
    },
    'input': <String, Object?>{
      'events': 100000,
      'writes': 100000,
      'bytes': 100000,
      'checksum': 1,
      'queue_capacity_bytes': 65536,
      'queue_peak_bytes': 119,
      'queue_rejections': 0,
    },
  },
};

Map<String, Object?> _metric({
  required String id,
  required String unit,
  required String direction,
  required int sampleCount,
  required num minimum,
  required num p50,
  required num p95,
  required num p99,
  required num maximum,
  required String hardStat,
  required String hardOperator,
  required num hardValue,
  required String baselineStat,
  required num reference,
  required num tolerance,
  required num slack,
  required num threshold,
}) => <String, Object?>{
  'id': id,
  'unit': unit,
  'direction': direction,
  'sample_count': sampleCount,
  'min': minimum,
  'p50': p50,
  'p95': p95,
  'p99': p99,
  'max': maximum,
  'hard_gate': <String, Object?>{
    'stat': hardStat,
    'operator': hardOperator,
    'value': hardValue,
    'passed': true,
  },
  'baseline_gate': <String, Object?>{
    'stat': baselineStat,
    'reference': reference,
    'relative_tolerance': tolerance,
    'absolute_slack': slack,
    'threshold': threshold,
    'passed': true,
  },
  'passed': true,
};

Map<String, Object?> _metricById(Map<String, Object?> document, String id) =>
    (document['metrics']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((Map<String, Object?> metric) => metric['id'] == id);

String _runtime() =>
    '/Users/private/terminal-content secret-command\n'
    'RUNTIME_PRODUCT_PERFORMANCE_INTEGRATION_PASS mode=release-aot '
    'launch_architecture=native startup_us=700000 refresh_interval_us=16667 '
    'input_p95_us=100 visible_p95_us=10000 frame_p95_us=500 '
    'idle_rss_bytes=120000000 workload_rss_bytes=125000000 '
    'peak_rss_bytes=130000000 idle_cpu_basis_points=5 '
    'occluded_cpu_basis_points=15 aggregate_cpu_basis_points=10 '
    'fairness=true elapsed_ms=10000';

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
