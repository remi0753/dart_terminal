import 'dart:convert';

const String pinnedGhosttyRevision = 'd4d8f62262cb1a974a7d2470d5f79f811fab15e4';
const String pinnedGhosttyZigVersion = '0.16.0';
const String pinnedGhosttyBuildCommand = 'zig build -Doptimize=ReleaseFast';
const String pinnedGhosttyBenchmarkBuildCommand =
    'zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false';
const String pinnedGhosttyMacosConfiguration = 'ReleaseLocal';
const String productRelativeWorkloadId = 'phase11-ghostty-parity-v1';
const int _maximumEvidenceCharacters = 64 * 1024;

final class ProductPerformanceComparatorEvidence {
  const ProductPerformanceComparatorEvidence({
    required this.id,
    required this.environment,
    required this.provenance,
    required this.workload,
    required this.inputVisibleP95Microseconds,
    required this.parserOutputThroughputMiBPerSecond,
    required this.idleResidentBytes,
    required this.idleCpuBasisPoints,
  });

  final String id;
  final Map<String, Object?> environment;
  final Map<String, Object?> provenance;
  final Map<String, Object?> workload;
  final double inputVisibleP95Microseconds;
  final double parserOutputThroughputMiBPerSecond;
  final double idleResidentBytes;
  final double idleCpuBasisPoints;
}

final class ProductRelativePerformanceObservation {
  ProductRelativePerformanceObservation({
    required Map<String, Object?> environment,
    required Map<String, Object?> workload,
    required this.inputVisibleP95Microseconds,
    required this.parserOutputThroughputMiBPerSecond,
    required this.idleResidentBytes,
    required this.idleCpuBasisPoints,
  }) : environment = Map<String, Object?>.unmodifiable(environment),
       workload = Map<String, Object?>.unmodifiable(workload) {
    for (final num metric in <num>[
      inputVisibleP95Microseconds,
      parserOutputThroughputMiBPerSecond,
      idleResidentBytes,
      idleCpuBasisPoints,
    ]) {
      if (!metric.toDouble().isFinite || metric < 0) {
        throw ArgumentError('product relative metric is invalid');
      }
    }
    if (inputVisibleP95Microseconds <= 0 ||
        parserOutputThroughputMiBPerSecond <= 0 ||
        idleResidentBytes <= 0) {
      throw ArgumentError('product relative metric must be positive');
    }
  }

  final Map<String, Object?> environment;
  final Map<String, Object?> workload;
  final double inputVisibleP95Microseconds;
  final double parserOutputThroughputMiBPerSecond;
  final double idleResidentBytes;
  final double idleCpuBasisPoints;
}

final class ProductRelativePerformanceResult {
  const ProductRelativePerformanceResult({
    required this.document,
    required this.passed,
  });

  final Map<String, Object?> document;
  final bool passed;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

ProductPerformanceComparatorEvidence decodeProductPerformanceComparator(
  String source,
) {
  if (source.length > _maximumEvidenceCharacters) {
    throw const FormatException('comparator evidence is too large');
  }
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('comparator evidence must be an object');
  }
  _expectExactKeys(decoded, const <String>{
    'format',
    'version',
    'id',
    'environment',
    'provenance',
    'workload',
    'metrics',
  }, 'comparator evidence');
  if (decoded['format'] != 'dart-terminal-performance-comparator-evidence' ||
      decoded['version'] != 1 ||
      decoded['id'] is! String ||
      !_validToken(decoded['id']! as String)) {
    throw const FormatException('unsupported comparator evidence');
  }

  final Map<String, Object?> environment = _object(
    decoded['environment'],
    'comparator environment',
  );
  _expectExactKeys(environment, const <String>{
    'os',
    'abi',
    'hardware_model',
    'memory_bytes',
    'os_build',
    'refresh_tier_hz',
  }, 'comparator environment');
  if (environment['os'] != 'macos' ||
      environment['abi'] != 'macos_arm64' ||
      environment['hardware_model'] is! String ||
      !_validToken(environment['hardware_model']! as String) ||
      environment['memory_bytes'] is! int ||
      (environment['memory_bytes']! as int) <= 0 ||
      environment['os_build'] is! String ||
      !_validToken(environment['os_build']! as String) ||
      (environment['refresh_tier_hz'] != 60 &&
          environment['refresh_tier_hz'] != 120)) {
    throw const FormatException('comparator environment is invalid');
  }

  final Map<String, Object?> provenance = _object(
    decoded['provenance'],
    'comparator provenance',
  );
  _expectExactKeys(provenance, const <String>{
    'product',
    'revision',
    'zig_version',
    'build_command',
    'benchmark_build_command',
    'macos_configuration',
    'project_local_patches',
    'app_executable_sha256',
    'benchmark_executable_sha256',
    'capture_harness_sha256',
  }, 'comparator provenance');
  if (provenance['product'] != 'ghostty' ||
      provenance['revision'] != pinnedGhosttyRevision ||
      provenance['zig_version'] != pinnedGhosttyZigVersion ||
      provenance['build_command'] != pinnedGhosttyBuildCommand ||
      provenance['benchmark_build_command'] !=
          pinnedGhosttyBenchmarkBuildCommand ||
      provenance['macos_configuration'] != pinnedGhosttyMacosConfiguration ||
      provenance['project_local_patches'] != false ||
      !_validSha256(provenance['app_executable_sha256']) ||
      !_validSha256(provenance['benchmark_executable_sha256']) ||
      !_validSha256(provenance['capture_harness_sha256'])) {
    throw const FormatException('comparator provenance is invalid');
  }

  final Map<String, Object?> workload = _object(
    decoded['workload'],
    'comparator workload',
  );
  _expectExactKeys(workload, const <String>{
    'id',
    'shell_fixture',
    'configuration',
    'input_transport',
    'visibility_observer',
    'input_samples',
    'parser_action',
    'parser_warmup_runs',
    'parser_sample_count',
    'parser_statistic',
    'parser_output_bytes',
    'parser_corpus_sha256',
    'memory_output_bytes',
    'resource_scope',
    'idle_window_count',
    'idle_window_us',
    'animation_enabled',
    'raw_samples_retained',
  }, 'comparator workload');
  if (workload['id'] != productRelativeWorkloadId ||
      workload['shell_fixture'] != 'isolated-zsh-v1' ||
      workload['configuration'] != 'parity-minimal-v1' ||
      workload['input_transport'] != 'applescript-input-text' ||
      workload['visibility_observer'] != 'screencapturekit-window-pixel' ||
      workload['input_samples'] != 7 ||
      workload['parser_action'] != 'terminal-parser' ||
      workload['parser_warmup_runs'] != 2 ||
      workload['parser_sample_count'] != 5 ||
      workload['parser_statistic'] != 'p50' ||
      workload['parser_output_bytes'] != 134264777 ||
      !_validSha256(workload['parser_corpus_sha256']) ||
      workload['memory_output_bytes'] != 22048 ||
      workload['resource_scope'] != 'root-process' ||
      workload['idle_window_count'] != 2 ||
      workload['idle_window_us'] != 2000000 ||
      workload['animation_enabled'] != false ||
      workload['raw_samples_retained'] != false) {
    throw const FormatException('comparator workload is invalid');
  }

  final Map<String, Object?> metrics = _object(
    decoded['metrics'],
    'comparator metrics',
  );
  _expectExactKeys(metrics, const <String>{
    'input_visible_p95_us',
    'parser_output_throughput_mib_s',
    'idle_rss_bytes',
    'idle_cpu_basis_points',
  }, 'comparator metrics');
  final double inputVisibleP95 = _finiteNumber(
    metrics['input_visible_p95_us'],
    'comparator input latency',
  );
  final double parserOutputThroughput = _finiteNumber(
    metrics['parser_output_throughput_mib_s'],
    'comparator parser/output throughput',
  );
  final double idleResidentBytes = _finiteNumber(
    metrics['idle_rss_bytes'],
    'comparator idle RSS',
  );
  final double idleCpuBasisPoints = _finiteNumber(
    metrics['idle_cpu_basis_points'],
    'comparator idle CPU',
  );
  if (inputVisibleP95 <= 0 ||
      parserOutputThroughput <= 0 ||
      idleResidentBytes <= 0 ||
      idleCpuBasisPoints < 0) {
    throw const FormatException('comparator metric is invalid');
  }
  return ProductPerformanceComparatorEvidence(
    id: decoded['id']! as String,
    environment: Map<String, Object?>.unmodifiable(environment),
    provenance: Map<String, Object?>.unmodifiable(provenance),
    workload: Map<String, Object?>.unmodifiable(workload),
    inputVisibleP95Microseconds: inputVisibleP95,
    parserOutputThroughputMiBPerSecond: parserOutputThroughput,
    idleResidentBytes: idleResidentBytes,
    idleCpuBasisPoints: idleCpuBasisPoints,
  );
}

ProductRelativePerformanceResult evaluateProductRelativePerformance({
  required ProductRelativePerformanceObservation product,
  required ProductPerformanceComparatorEvidence comparator,
}) {
  _expectCompatible(product.environment, comparator.environment, 'environment');
  _expectCompatible(product.workload, comparator.workload, 'workload');
  final double inputThreshold = _maximum(
    comparator.inputVisibleP95Microseconds + 4000,
    comparator.inputVisibleP95Microseconds * 1.25,
  );
  final double parserThreshold =
      comparator.parserOutputThroughputMiBPerSecond * 0.75;
  final double memoryThreshold = comparator.idleResidentBytes * 1.5;
  final double cpuThreshold = comparator.idleCpuBasisPoints * 1.5;
  final List<Map<String, Object?>> gates = <Map<String, Object?>>[
    _gate(
      id: 'input.visible_p95',
      unit: 'us',
      operator: '<=',
      product: product.inputVisibleP95Microseconds,
      comparator: comparator.inputVisibleP95Microseconds,
      threshold: inputThreshold,
      passed: product.inputVisibleP95Microseconds <= inputThreshold,
    ),
    _gate(
      id: 'parser.output_throughput',
      unit: 'MiB/s',
      operator: '>=',
      product: product.parserOutputThroughputMiBPerSecond,
      comparator: comparator.parserOutputThroughputMiBPerSecond,
      threshold: parserThreshold,
      passed: product.parserOutputThroughputMiBPerSecond >= parserThreshold,
    ),
    _gate(
      id: 'idle.resident_memory',
      unit: 'bytes',
      operator: '<=',
      product: product.idleResidentBytes,
      comparator: comparator.idleResidentBytes,
      threshold: memoryThreshold,
      passed: product.idleResidentBytes <= memoryThreshold,
    ),
    _gate(
      id: 'idle.process_cpu',
      unit: 'basis-points',
      operator: '<=',
      product: product.idleCpuBasisPoints,
      comparator: comparator.idleCpuBasisPoints,
      threshold: cpuThreshold,
      passed: product.idleCpuBasisPoints <= cpuThreshold,
    ),
  ];
  final bool passed = gates.every(
    (Map<String, Object?> gate) => gate['passed'] == true,
  );
  return ProductRelativePerformanceResult(
    passed: passed,
    document: <String, Object?>{
      'format': 'dart-terminal-product-relative-performance-result',
      'version': 1,
      'status': passed ? 'pass' : 'fail',
      'comparator_id': comparator.id,
      'comparator_provenance': comparator.provenance,
      'environment': product.environment,
      'workload': product.workload,
      'policy': const <String, Object?>{
        'input': 'max-comparator-plus-4000us-or-1.25x',
        'parser_output_minimum_ratio': 0.75,
        'refresh_tier': 'exact-compatible-environment',
        'idle_memory_maximum_ratio': 1.5,
        'idle_cpu_maximum_ratio': 1.5,
        'raw_samples_retained': false,
      },
      'gates': gates,
    },
  );
}

Map<String, Object?> _gate({
  required String id,
  required String unit,
  required String operator,
  required double product,
  required double comparator,
  required double threshold,
  required bool passed,
}) => <String, Object?>{
  'id': id,
  'unit': unit,
  'operator': operator,
  'product': product,
  'comparator': comparator,
  'threshold': threshold,
  'passed': passed,
};

void _expectCompatible(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
  String name,
) {
  if (actual.length != expected.length ||
      actual.entries.any(
        (MapEntry<String, Object?> entry) =>
            !expected.containsKey(entry.key) ||
            expected[entry.key] != entry.value,
      )) {
    throw StateError('comparator $name is incompatible');
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

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

double _finiteNumber(Object? value, String name) {
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$name must be finite');
  }
  return value.toDouble();
}

bool _validSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _validToken(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/+,:-]*$').hasMatch(value);

double _maximum(double first, double second) => first > second ? first : second;
