import 'dart:convert';
import 'dart:io';

import 'ghostty_performance_capture.dart';
import 'product_performance_comparator.dart';
import 'terminal_differential_sha256.dart';

const int _maximumInputCharacters = 64 * 1024;
const String productPerformanceAggregateFormat =
    'dart-terminal-product-performance-regression-result';

final class ProductPerformanceAggregateResult {
  const ProductPerformanceAggregateResult({
    required this.document,
    required this.passed,
  });

  final Map<String, Object?> document;
  final bool passed;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

ProductPerformanceAggregateResult buildProductPerformanceAggregate({
  required String microbenchmarkSource,
  required String runtimeSource,
  required String comparatorSource,
}) {
  for (final String source in <String>[
    microbenchmarkSource,
    runtimeSource,
    comparatorSource,
  ]) {
    if (source.isEmpty || source.length > _maximumInputCharacters) {
      throw const FormatException(
        'performance gate input is empty or too large',
      );
    }
  }

  final ProductRelativeInputObservation product = decodeProductRelativeInput(
    microbenchmarkSource: microbenchmarkSource,
    runtimeSource: runtimeSource,
  );
  final ProductPerformanceComparatorEvidence comparator =
      decodeProductPerformanceComparator(comparatorSource);
  final _MicrobenchmarkObservation micro = _decodeMicrobenchmark(
    microbenchmarkSource,
  );
  final _RuntimeObservation runtime = _decodeRuntime(runtimeSource);

  for (final String key in <String>[
    'os',
    'abi',
    'hardware_model',
    'memory_bytes',
  ]) {
    if (product.environment[key] != comparator.environment[key]) {
      throw StateError('product and comparator environment differ');
    }
  }
  if (product.refreshTierHz != comparator.environment['refresh_tier_hz'] ||
      runtime.refreshTierHz != product.refreshTierHz) {
    throw StateError('product and comparator refresh tiers differ');
  }
  if (micro.parserP50 != product.parserThroughputMiBPerSecond ||
      runtime.visibleP95Microseconds != product.inputVisibleP95Microseconds ||
      runtime.idleResidentBytes != product.idleResidentBytes ||
      runtime.aggregateCpuBasisPoints != product.aggregateCpuBasisPoints) {
    throw const FormatException('aggregate product observations differ');
  }

  final ProductRelativePerformanceResult relative =
      evaluateProductRelativePerformance(
        product: ProductRelativePerformanceObservation(
          environment: comparator.environment,
          workload: comparator.workload,
          inputVisibleP95Microseconds: runtime.visibleP95Microseconds
              .toDouble(),
          parserOutputThroughputMiBPerSecond: micro.parserP50,
          idleResidentBytes: runtime.idleResidentBytes.toDouble(),
          idleCpuBasisPoints: runtime.aggregateCpuBasisPoints.toDouble(),
        ),
        comparator: comparator,
      );
  final List<Object?> relativeGates =
      (relative.document['gates']! as List<Object?>)
          .map<Object?>(
            (Object? value) => Map<String, Object?>.unmodifiable(
              value! as Map<String, Object?>,
            ),
          )
          .toList(growable: false);
  final bool passed = relative.passed;
  return ProductPerformanceAggregateResult(
    passed: passed,
    document: <String, Object?>{
      'format': productPerformanceAggregateFormat,
      'version': 1,
      'status': passed ? 'pass' : 'fail',
      'input_integrity': <String, Object?>{
        'product_micro_sha256': terminalDifferentialSha256(
          utf8.encode(microbenchmarkSource),
        ),
        'product_runtime_sha256': terminalDifferentialSha256(
          utf8.encode(runtimeSource),
        ),
        'comparator_evidence_sha256': terminalDifferentialSha256(
          utf8.encode(comparatorSource),
        ),
      },
      'environment': <String, Object?>{
        ...product.environment,
        'os_build': comparator.environment['os_build'],
        'refresh_tier_hz': product.refreshTierHz,
      },
      'product': <String, Object?>{
        'baseline_id': micro.baselineId,
        'micro_metrics': micro.metrics,
        'runtime_metrics': runtime.toJson(),
        'fairness': true,
      },
      'comparator': <String, Object?>{
        'id': comparator.id,
        'provenance': comparator.provenance,
        'workload': comparator.workload,
      },
      'policy': const <String, Object?>{
        'product_hard_gates_required': true,
        'product_baseline_gates_required': true,
        'ordinary_product_absolute_gates_required': true,
        'cross_pane_fairness_required': true,
        'pinned_relative_gates_required': true,
        'raw_samples_retained': false,
      },
      'gates': <String, Object?>{
        'product_micro': true,
        'ordinary_product': true,
        'cross_pane_fairness': true,
        'relative': relativeGates,
        'passed': passed,
      },
    },
  );
}

final class _MicrobenchmarkObservation {
  const _MicrobenchmarkObservation({
    required this.baselineId,
    required this.parserP50,
    required this.metrics,
  });

  final String baselineId;
  final double parserP50;
  final List<Map<String, Object?>> metrics;
}

final class _MetricContract {
  const _MetricContract({
    required this.unit,
    required this.direction,
    required this.sampleCount,
    required this.hardStat,
    required this.hardOperator,
    required this.hardValue,
    required this.baselineStat,
  });

  final String unit;
  final String direction;
  final int sampleCount;
  final String hardStat;
  final String hardOperator;
  final double hardValue;
  final String baselineStat;
}

const Map<String, _MetricContract> _metricContracts = <String, _MetricContract>{
  'parser.product_mixed.throughput': _MetricContract(
    unit: 'MiB/s',
    direction: 'higher',
    sampleCount: 5,
    hardStat: 'min',
    hardOperator: '>=',
    hardValue: 100,
    baselineStat: 'p50',
  ),
  'render.damage.capture_copy_latency': _MetricContract(
    unit: 'us',
    direction: 'lower',
    sampleCount: 64,
    hardStat: 'p95',
    hardOperator: '<',
    hardValue: 4000,
    baselineStat: 'p95',
  ),
  'render.damage.transfer_decode_ack_latency': _MetricContract(
    unit: 'us',
    direction: 'lower',
    sampleCount: 64,
    hardStat: 'p95',
    hardOperator: '<',
    hardValue: 4000,
    baselineStat: 'p95',
  ),
  'render.damage.end_to_end_latency': _MetricContract(
    unit: 'us',
    direction: 'lower',
    sampleCount: 64,
    hardStat: 'p95',
    hardOperator: '<',
    hardValue: 8000,
    baselineStat: 'p95',
  ),
  'input.key_to_pane_write_latency': _MetricContract(
    unit: 'ns',
    direction: 'lower',
    sampleCount: 100000,
    hardStat: 'p95',
    hardOperator: '<',
    hardValue: 2000000,
    baselineStat: 'p95',
  ),
};

_MicrobenchmarkObservation _decodeMicrobenchmark(String source) {
  final Map<String, Object?> decoded = _object(
    jsonDecode(source),
    'product microbenchmark',
  );
  final String baselineId = _string(decoded['baseline_id'], 'baseline id');
  if (baselineId != 'product-micro-macos-arm64-m1') {
    throw const FormatException('aggregate baseline identity is invalid');
  }
  final Map<String, Object?> provenance = _object(
    decoded['provenance'],
    'product provenance',
  );
  if (provenance['workload'] != 'phase11-product-micro-v1' ||
      provenance['damage_packet_version'] != 2 ||
      provenance['damage_rows'] != 200 ||
      provenance['damage_columns'] != 500 ||
      provenance['damage_iterations'] != 64 ||
      provenance['input_route'] != 'terminal-key-router-pane-write-v1' ||
      provenance['input_iterations'] != 100000 ||
      provenance['measurement_policy_version'] != 1) {
    throw const FormatException('aggregate product provenance is invalid');
  }
  final Map<String, Object?> integrity = _object(
    decoded['integrity'],
    'product integrity',
  );
  final Map<String, Object?> parser = _object(
    integrity['parser'],
    'parser integrity',
  );
  final Map<String, Object?> damage = _object(
    integrity['damage'],
    'damage integrity',
  );
  final Map<String, Object?> input = _object(
    integrity['input'],
    'input integrity',
  );
  _expectExactKeys(damage, const <String>{
    'packet_bytes',
    'transferred_bytes',
    'iterations',
  }, 'damage integrity');
  _expectExactKeys(input, const <String>{
    'events',
    'writes',
    'bytes',
    'checksum',
    'queue_capacity_bytes',
    'queue_peak_bytes',
    'queue_rejections',
  }, 'input integrity');
  if (!_allNonNegativeIntegers(parser.values) ||
      !_allNonNegativeIntegers(damage.values) ||
      !_allNonNegativeIntegers(input.values) ||
      damage['packet_bytes'] != 1704904 ||
      damage['iterations'] != 64 ||
      damage['transferred_bytes'] != 1704904 * 64 ||
      input['events'] != 100000 ||
      input['writes'] != 100000 ||
      (input['bytes']! as int) <= 0 ||
      (input['checksum']! as int) <= 0 ||
      input['queue_capacity_bytes'] != 65536 ||
      (input['queue_peak_bytes']! as int) <= 0 ||
      (input['queue_peak_bytes']! as int) > 65536 ||
      input['queue_rejections'] != 0) {
    throw const FormatException('aggregate product integrity is invalid');
  }

  final Object? rawMetrics = decoded['metrics'];
  if (rawMetrics is! List<Object?> || rawMetrics.length != 5) {
    throw const FormatException('aggregate metric inventory is invalid');
  }
  final List<Map<String, Object?>> summaries = <Map<String, Object?>>[];
  final Set<String> seen = <String>{};
  var parserP50 = 0.0;
  for (final Object? rawMetric in rawMetrics) {
    final Map<String, Object?> metric = _object(rawMetric, 'product metric');
    _expectExactKeys(metric, const <String>{
      'id',
      'unit',
      'direction',
      'sample_count',
      'min',
      'p50',
      'p95',
      'p99',
      'max',
      'hard_gate',
      'baseline_gate',
      'passed',
    }, 'product metric');
    final String id = _string(metric['id'], 'product metric id');
    final _MetricContract? contract = _metricContracts[id];
    if (contract == null || !seen.add(id)) {
      throw const FormatException('aggregate metric inventory is invalid');
    }
    final double minimum = _finite(metric['min'], '$id minimum');
    final double p50 = _finite(metric['p50'], '$id p50');
    final double p95 = _finite(metric['p95'], '$id p95');
    final double p99 = _finite(metric['p99'], '$id p99');
    final double maximum = _finite(metric['max'], '$id maximum');
    if (metric['unit'] != contract.unit ||
        metric['direction'] != contract.direction ||
        metric['sample_count'] != contract.sampleCount ||
        minimum > p50 ||
        p50 > p95 ||
        p95 > p99 ||
        p99 > maximum) {
      throw FormatException('$id distribution is invalid');
    }
    final Map<String, Object?> hard = _object(
      metric['hard_gate'],
      '$id hard gate',
    );
    _expectExactKeys(hard, const <String>{
      'stat',
      'operator',
      'value',
      'passed',
    }, '$id hard gate');
    final double hardValue = _finite(hard['value'], '$id hard value');
    final double hardObserved = contract.hardStat == 'min' ? minimum : p95;
    final bool hardPassed = contract.hardOperator == '>='
        ? hardObserved >= contract.hardValue
        : hardObserved < contract.hardValue;
    if (hard['stat'] != contract.hardStat ||
        hard['operator'] != contract.hardOperator ||
        hardValue != contract.hardValue ||
        hard['passed'] != hardPassed ||
        !hardPassed) {
      throw FormatException('$id hard gate failed or is malformed');
    }
    final Map<String, Object?> baseline = _object(
      metric['baseline_gate'],
      '$id baseline gate',
    );
    _expectExactKeys(baseline, const <String>{
      'stat',
      'reference',
      'relative_tolerance',
      'absolute_slack',
      'threshold',
      'passed',
    }, '$id baseline gate');
    final double reference = _finite(baseline['reference'], '$id reference');
    final double tolerance = _finite(
      baseline['relative_tolerance'],
      '$id tolerance',
    );
    final double slack = _finite(baseline['absolute_slack'], '$id slack');
    final double threshold = _finite(baseline['threshold'], '$id threshold');
    if (reference <= 0 || tolerance < 0 || tolerance >= 1 || slack < 0) {
      throw FormatException('$id baseline policy is invalid');
    }
    final double expectedThreshold = contract.direction == 'higher'
        ? reference * (1 - tolerance) - slack
        : reference * (1 + tolerance) + slack;
    final double baselineObserved = contract.baselineStat == 'p50' ? p50 : p95;
    final bool baselinePassed = contract.direction == 'higher'
        ? baselineObserved >= threshold
        : baselineObserved <= threshold;
    if (baseline['stat'] != contract.baselineStat ||
        threshold != expectedThreshold ||
        baseline['passed'] != baselinePassed ||
        !baselinePassed ||
        metric['passed'] != true) {
      throw FormatException('$id baseline gate failed or is malformed');
    }
    if (id == 'parser.product_mixed.throughput') parserP50 = p50;
    summaries.add(<String, Object?>{
      'id': id,
      'unit': contract.unit,
      'sample_count': contract.sampleCount,
      'min': minimum,
      'p50': p50,
      'p95': p95,
      'p99': p99,
      'max': maximum,
      'hard_threshold': contract.hardValue,
      'baseline_threshold': threshold,
      'passed': true,
    });
  }
  if (seen.length != _metricContracts.length || parserP50 <= 0) {
    throw const FormatException('aggregate metric inventory is incomplete');
  }
  return _MicrobenchmarkObservation(
    baselineId: baselineId,
    parserP50: parserP50,
    metrics: List<Map<String, Object?>>.unmodifiable(summaries),
  );
}

final class _RuntimeObservation {
  const _RuntimeObservation({
    required this.startupMicroseconds,
    required this.refreshIntervalMicroseconds,
    required this.inputP95Microseconds,
    required this.visibleP95Microseconds,
    required this.frameP95Microseconds,
    required this.idleResidentBytes,
    required this.workloadResidentBytes,
    required this.peakResidentBytes,
    required this.idleCpuBasisPoints,
    required this.occludedCpuBasisPoints,
    required this.aggregateCpuBasisPoints,
  });

  final int startupMicroseconds;
  final int refreshIntervalMicroseconds;
  final int inputP95Microseconds;
  final int visibleP95Microseconds;
  final int frameP95Microseconds;
  final int idleResidentBytes;
  final int workloadResidentBytes;
  final int peakResidentBytes;
  final int idleCpuBasisPoints;
  final int occludedCpuBasisPoints;
  final int aggregateCpuBasisPoints;

  int get refreshTierHz => refreshIntervalMicroseconds <= 12500 ? 120 : 60;

  Map<String, Object?> toJson() => <String, Object?>{
    'startup_us': startupMicroseconds,
    'refresh_interval_us': refreshIntervalMicroseconds,
    'input_p95_us': inputP95Microseconds,
    'visible_p95_us': visibleP95Microseconds,
    'visible_budget_us': refreshIntervalMicroseconds + 4000,
    'frame_p95_us': frameP95Microseconds,
    'frame_budget_us': refreshIntervalMicroseconds * 7 ~/ 10,
    'idle_rss_bytes': idleResidentBytes,
    'workload_rss_bytes': workloadResidentBytes,
    'peak_rss_bytes': peakResidentBytes,
    'rss_budget_bytes': 512 * 1024 * 1024,
    'idle_cpu_basis_points': idleCpuBasisPoints,
    'occluded_cpu_basis_points': occludedCpuBasisPoints,
    'aggregate_cpu_basis_points': aggregateCpuBasisPoints,
    'aggregate_cpu_budget_basis_points': 50,
  };
}

final RegExp _runtimeSummary = RegExp(
  r'^RUNTIME_PRODUCT_PERFORMANCE_INTEGRATION_PASS mode=release-aot '
  r'launch_architecture=native startup_us=([1-9][0-9]*) '
  r'refresh_interval_us=([1-9][0-9]*) input_p95_us=([1-9][0-9]*) '
  r'visible_p95_us=([1-9][0-9]*) frame_p95_us=([1-9][0-9]*) '
  r'idle_rss_bytes=([1-9][0-9]*) workload_rss_bytes=([1-9][0-9]*) '
  r'peak_rss_bytes=([1-9][0-9]*) idle_cpu_basis_points=([0-9]+) '
  r'occluded_cpu_basis_points=([0-9]+) aggregate_cpu_basis_points=([0-9]+) '
  r'fairness=true elapsed_ms=([1-9][0-9]*)$',
  multiLine: true,
);

_RuntimeObservation _decodeRuntime(String source) {
  final List<RegExpMatch> matches = _runtimeSummary.allMatches(source).toList();
  if (matches.length != 1) {
    throw const FormatException('aggregate runtime summary is invalid');
  }
  final RegExpMatch match = matches.single;
  final List<int> values = List<int>.generate(
    12,
    (int index) => int.parse(match.group(index + 1)!),
    growable: false,
  );
  final _RuntimeObservation result = _RuntimeObservation(
    startupMicroseconds: values[0],
    refreshIntervalMicroseconds: values[1],
    inputP95Microseconds: values[2],
    visibleP95Microseconds: values[3],
    frameP95Microseconds: values[4],
    idleResidentBytes: values[5],
    workloadResidentBytes: values[6],
    peakResidentBytes: values[7],
    idleCpuBasisPoints: values[8],
    occludedCpuBasisPoints: values[9],
    aggregateCpuBasisPoints: values[10],
  );
  const int rssBudget = 512 * 1024 * 1024;
  final int frameBudget = result.refreshIntervalMicroseconds * 7 ~/ 10;
  if (result.startupMicroseconds > 5000000 ||
      result.refreshIntervalMicroseconds > 25000 ||
      result.inputP95Microseconds >= 2000 ||
      result.visibleP95Microseconds >
          result.refreshIntervalMicroseconds + 4000 ||
      result.frameP95Microseconds >= frameBudget ||
      result.idleResidentBytes > rssBudget ||
      result.workloadResidentBytes > rssBudget ||
      result.peakResidentBytes > rssBudget ||
      result.peakResidentBytes < result.idleResidentBytes ||
      result.peakResidentBytes < result.workloadResidentBytes ||
      result.aggregateCpuBasisPoints >= 50) {
    throw const FormatException('aggregate ordinary-product gate failed');
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = _parseArguments(arguments);
  final File microbenchmark = File(options['product-micro']!);
  final File runtime = File(options['product-runtime']!);
  final File comparator = File(options['comparator']!);
  final File output = File(options['output']!);
  for (final File input in <File>[microbenchmark, runtime, comparator]) {
    if (!input.isAbsolute || !await input.exists()) {
      throw const FormatException('aggregate input must be an absolute file');
    }
  }
  if (!output.isAbsolute) {
    throw const FormatException('aggregate output must be an absolute file');
  }
  final ProductPerformanceAggregateResult result =
      buildProductPerformanceAggregate(
        microbenchmarkSource: await microbenchmark.readAsString(),
        runtimeSource: await runtime.readAsString(),
        comparatorSource: await comparator.readAsString(),
      );
  await _writeAtomic(output, result.encode());
  stdout.writeln(
    'PRODUCT_PERFORMANCE_REGRESSION_${result.passed ? 'PASS' : 'FAIL'} '
    'absolute=true baseline=true fairness=true relative=${result.passed} '
    'content_free=true',
  );
  if (!result.passed) exitCode = 1;
}

Map<String, String> _parseArguments(List<String> arguments) {
  const Set<String> expected = <String>{
    'product-micro',
    'product-runtime',
    'comparator',
    'output',
  };
  final Map<String, String> result = <String, String>{};
  for (final String argument in arguments) {
    final int separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator <= 2) {
      throw const FormatException('aggregate argument is malformed');
    }
    final String key = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    if (!expected.contains(key) || value.isEmpty || result[key] != null) {
      throw const FormatException(
        'aggregate argument is unknown or duplicated',
      );
    }
    result[key] = value;
  }
  if (result.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(result.keys.toSet()).isNotEmpty) {
    throw const FormatException('aggregate argument inventory is incomplete');
  }
  return result;
}

Future<void> _writeAtomic(File output, String source) async {
  await output.parent.create(recursive: true);
  final File temporary = File('${output.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString(source, flush: true);
  await temporary.rename(output.path);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _string(Object? value, String name) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains('\n')) {
    throw FormatException('$name must be a bounded string');
  }
  return value;
}

double _finite(Object? value, String name) {
  if (value is! num || !value.toDouble().isFinite || value < 0) {
    throw FormatException('$name must be finite and non-negative');
  }
  return value.toDouble();
}

bool _allNonNegativeIntegers(Iterable<Object?> values) =>
    values.every((Object? value) => value is int && value >= 0);

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String name,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('$name has an invalid key inventory');
  }
}
