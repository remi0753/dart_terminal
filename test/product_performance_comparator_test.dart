import 'dart:convert';

import '../tool/product_performance_comparator.dart';

void main() => runProductPerformanceComparatorTests();

void runProductPerformanceComparatorTests() {
  _testExactComparatorAndBoundaries();
  _testComparatorEvidenceFailures();
  _testCompatibilityFailures();
}

void _testExactComparatorAndBoundaries() {
  final ProductPerformanceComparatorEvidence comparator =
      decodeProductPerformanceComparator(jsonEncode(_evidence()));
  final ProductRelativePerformanceObservation boundary = _product(
    inputVisibleP95Microseconds: 14000,
    parserOutputThroughputMiBPerSecond: 75,
    idleResidentBytes: 150,
    idleCpuBasisPoints: 30,
  );
  final ProductRelativePerformanceResult accepted =
      evaluateProductRelativePerformance(
        product: boundary,
        comparator: comparator,
      );
  final String encoded = accepted.encode();
  _expect(
    accepted.passed &&
        encoded.endsWith('\n') &&
        encoded.contains('dart-terminal-product-relative-performance-result') &&
        encoded.contains(pinnedGhosttyRevision) &&
        !encoded.contains('/Users/') &&
        !encoded.contains('command_line'),
    'all exact relative boundaries pass in a content-free result',
  );
  for (final ProductRelativePerformanceObservation rejected
      in <ProductRelativePerformanceObservation>[
        _product(
          inputVisibleP95Microseconds: 14000.1,
          parserOutputThroughputMiBPerSecond: 75,
          idleResidentBytes: 150,
          idleCpuBasisPoints: 30,
        ),
        _product(
          inputVisibleP95Microseconds: 14000,
          parserOutputThroughputMiBPerSecond: 74.99,
          idleResidentBytes: 150,
          idleCpuBasisPoints: 30,
        ),
        _product(
          inputVisibleP95Microseconds: 14000,
          parserOutputThroughputMiBPerSecond: 75,
          idleResidentBytes: 150.1,
          idleCpuBasisPoints: 30,
        ),
        _product(
          inputVisibleP95Microseconds: 14000,
          parserOutputThroughputMiBPerSecond: 75,
          idleResidentBytes: 150,
          idleCpuBasisPoints: 30.1,
        ),
      ]) {
    _expect(
      !evaluateProductRelativePerformance(
        product: rejected,
        comparator: comparator,
      ).passed,
      'a relative metric beyond its exact threshold fails closed',
    );
  }
  final Map<String, Object?> ratioEvidence = _evidence();
  (ratioEvidence['metrics']! as Map<String, Object?>)['input_visible_p95_us'] =
      20000;
  final ProductPerformanceComparatorEvidence ratioComparator =
      decodeProductPerformanceComparator(jsonEncode(ratioEvidence));
  _expect(
    evaluateProductRelativePerformance(
      product: _product(
        inputVisibleP95Microseconds: 25000,
        parserOutputThroughputMiBPerSecond: 75,
        idleResidentBytes: 150,
        idleCpuBasisPoints: 30,
      ),
      comparator: ratioComparator,
    ).passed,
    'the exact 1.25x input branch passes when it exceeds 4 ms slack',
  );
  _expect(
    !evaluateProductRelativePerformance(
      product: _product(
        inputVisibleP95Microseconds: 25000.1,
        parserOutputThroughputMiBPerSecond: 75,
        idleResidentBytes: 150,
        idleCpuBasisPoints: 30,
      ),
      comparator: ratioComparator,
    ).passed,
    'the 1.25x input branch rejects the first value beyond its boundary',
  );
}

void _testComparatorEvidenceFailures() {
  final Map<String, Object?> extra = _evidence()..['extra'] = true;
  _expectThrows(
    () => decodeProductPerformanceComparator(jsonEncode(extra)),
    'unknown top-level evidence key',
  );
  final Map<String, Object?> revision = _evidence();
  (revision['provenance']! as Map<String, Object?>)['revision'] = '0' * 40;
  _expectThrows(
    () => decodeProductPerformanceComparator(jsonEncode(revision)),
    'unpinned revision',
  );
  final Map<String, Object?> patched = _evidence();
  (patched['provenance']! as Map<String, Object?>)['project_local_patches'] =
      true;
  _expectThrows(
    () => decodeProductPerformanceComparator(jsonEncode(patched)),
    'project-local comparator patch',
  );
  final Map<String, Object?> workload = _evidence();
  (workload['workload']! as Map<String, Object?>)['animation_enabled'] = true;
  _expectThrows(
    () => decodeProductPerformanceComparator(jsonEncode(workload)),
    'incompatible animation workload',
  );
  final Map<String, Object?> metric = _evidence();
  (metric['metrics']! as Map<String, Object?>)['idle_rss_bytes'] = 0;
  _expectThrows(
    () => decodeProductPerformanceComparator(jsonEncode(metric)),
    'non-positive comparator RSS',
  );
  _expectThrows(
    () => decodeProductPerformanceComparator(' ' * (64 * 1024 + 1)),
    'oversized comparator evidence',
  );
}

void _testCompatibilityFailures() {
  final ProductPerformanceComparatorEvidence comparator =
      decodeProductPerformanceComparator(jsonEncode(_evidence()));
  final ProductRelativePerformanceObservation compatible = _product(
    inputVisibleP95Microseconds: 10000,
    parserOutputThroughputMiBPerSecond: 100,
    idleResidentBytes: 100,
    idleCpuBasisPoints: 20,
  );
  _expectThrows(
    () => evaluateProductRelativePerformance(
      product: ProductRelativePerformanceObservation(
        environment: <String, Object?>{
          ...compatible.environment,
          'refresh_tier_hz': 120,
        },
        workload: compatible.workload,
        inputVisibleP95Microseconds: 10000,
        parserOutputThroughputMiBPerSecond: 100,
        idleResidentBytes: 100,
        idleCpuBasisPoints: 20,
      ),
      comparator: comparator,
    ),
    'refresh-tier mismatch',
  );
  _expectThrows(
    () => evaluateProductRelativePerformance(
      product: ProductRelativePerformanceObservation(
        environment: compatible.environment,
        workload: <String, Object?>{...compatible.workload, 'input_samples': 8},
        inputVisibleP95Microseconds: 10000,
        parserOutputThroughputMiBPerSecond: 100,
        idleResidentBytes: 100,
        idleCpuBasisPoints: 20,
      ),
      comparator: comparator,
    ),
    'workload mismatch',
  );
}

Map<String, Object?> _evidence() => <String, Object?>{
  'format': 'dart-terminal-performance-comparator-evidence',
  'version': 1,
  'id': 'ghostty-pinned-m1-fixture',
  'environment': _environment(),
  'provenance': <String, Object?>{
    'product': 'ghostty',
    'revision': pinnedGhosttyRevision,
    'zig_version': pinnedGhosttyZigVersion,
    'build_command': pinnedGhosttyBuildCommand,
    'macos_configuration': pinnedGhosttyMacosConfiguration,
    'project_local_patches': false,
    'executable_sha256': '1' * 64,
    'harness_sha256': '2' * 64,
  },
  'workload': _workload(),
  'metrics': <String, Object?>{
    'input_visible_p95_us': 10000,
    'parser_output_throughput_mib_s': 100,
    'idle_rss_bytes': 100,
    'idle_cpu_basis_points': 20,
  },
};

ProductRelativePerformanceObservation _product({
  required double inputVisibleP95Microseconds,
  required double parserOutputThroughputMiBPerSecond,
  required double idleResidentBytes,
  required double idleCpuBasisPoints,
}) => ProductRelativePerformanceObservation(
  environment: _environment(),
  workload: _workload(),
  inputVisibleP95Microseconds: inputVisibleP95Microseconds,
  parserOutputThroughputMiBPerSecond: parserOutputThroughputMiBPerSecond,
  idleResidentBytes: idleResidentBytes,
  idleCpuBasisPoints: idleCpuBasisPoints,
);

Map<String, Object?> _environment() => <String, Object?>{
  'os': 'macos',
  'abi': 'macos_arm64',
  'hardware_model': 'MacBookPro17,1',
  'memory_bytes': 17179869184,
  'os_build': '25G83',
  'refresh_tier_hz': 60,
};

Map<String, Object?> _workload() => <String, Object?>{
  'id': productRelativeWorkloadId,
  'shell_fixture': 'isolated-zsh-v1',
  'configuration': 'parity-minimal-v1',
  'input_samples': 7,
  'parser_output_bytes': 134264777,
  'memory_output_bytes': 22048,
  'idle_window_count': 2,
  'idle_window_us': 2000000,
  'animation_enabled': false,
  'raw_samples_retained': false,
};

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
