import 'dart:convert';
import 'dart:io';

import '../tool/ghostty_performance_capture.dart';
import '../tool/product_performance_comparator.dart';
import '../tool/terminal_differential_sha256.dart';

void main() => runGhosttyPerformanceCaptureTests();

void runGhosttyPerformanceCaptureTests() {
  _testCaptureAndEvidenceContract();
  _testProductInputContract();
  _testHostileCaptureFailures();
  _testCheckedEvidence();
}

void _testCaptureAndEvidenceContract() {
  final GhosttyUiPerformanceObservation ui =
      GhosttyUiPerformanceObservation.parse(_uiLine());
  final Map<String, Object?> evidence = buildGhosttyComparatorEvidence(
    ui: ui,
    parser: const GhosttyParserPerformanceObservation(
      outputBytes: 134264777,
      corpusSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      throughputMiBPerSecond: 500,
    ),
    captureHarnessSha256:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    environment: _comparatorEnvironment(),
  );
  final ProductPerformanceComparatorEvidence decoded =
      decodeProductPerformanceComparator(jsonEncode(evidence));
  _expect(
    decoded.inputVisibleP95Microseconds == 12000 &&
        decoded.parserOutputThroughputMiBPerSecond == 500 &&
        decoded.idleResidentBytes == 100000000 &&
        decoded.idleCpuBasisPoints == 25 &&
        decoded.provenance['app_executable_sha256'] ==
            pinnedGhosttyAppExecutableSha256 &&
        decoded.provenance['benchmark_executable_sha256'] ==
            pinnedGhosttyBenchmarkExecutableSha256 &&
        decoded.workload['parser_action'] == 'terminal-parser' &&
        decoded.workload['raw_samples_retained'] == false,
    'capture evidence keeps exact split provenance and content-free workload',
  );
}

void _testProductInputContract() {
  final ProductRelativeInputObservation product = decodeProductRelativeInput(
    microbenchmarkSource: jsonEncode(_productMicrobenchmark()),
    runtimeSource: _productRuntime(),
  );
  _expect(
    product.environment['hardware_model'] == 'MacBookPro17,1' &&
        product.parserThroughputMiBPerSecond == 110 &&
        product.inputVisibleP95Microseconds == 12000 &&
        product.idleResidentBytes == 200000000 &&
        product.aggregateCpuBasisPoints == 20 &&
        product.refreshTierHz == 60,
    'fresh product inputs preserve the compatible relative metrics',
  );
}

void _testHostileCaptureFailures() {
  _expectThrows(
    () => GhosttyUiPerformanceObservation.parse('${_uiLine()}\n${_uiLine()}'),
    'duplicate UI result',
  );
  _expectThrows(
    () => GhosttyUiPerformanceObservation.parse(
      _uiLine().replaceFirst(
        'aggregate_cpu_basis_points=25',
        'aggregate_cpu_basis_points=26',
      ),
    ),
    'false aggregate CPU claim',
  );
  final Map<String, Object?> invalidMicro = _productMicrobenchmark();
  invalidMicro['status'] = 'fail';
  _expectThrows(
    () => decodeProductRelativeInput(
      microbenchmarkSource: jsonEncode(invalidMicro),
      runtimeSource: _productRuntime(),
    ),
    'failed product input',
  );
  final Map<String, Object?> extraMicro = _productMicrobenchmark()
    ..['unexpected'] = true;
  _expectThrows(
    () => decodeProductRelativeInput(
      microbenchmarkSource: jsonEncode(extraMicro),
      runtimeSource: _productRuntime(),
    ),
    'unknown product result field',
  );
  _expectThrows(
    () => decodeProductRelativeInput(
      microbenchmarkSource: jsonEncode(_productMicrobenchmark()),
      runtimeSource: _productRuntime().replaceFirst(
        'launch_architecture=native',
        'launch_architecture=x86_64',
      ),
    ),
    'non-native product runtime',
  );
}

void _testCheckedEvidence() {
  final File comparatorFile = File(
    'benchmark/evidence/ghostty-performance-comparator-macos-arm64-m1.json',
  );
  final File relativeFile = File(
    'benchmark/evidence/product-relative-performance-macos-arm64-m1.json',
  );
  final File harnessFile = File('tool/macos_ghostty_performance_capture.swift');
  _expect(
    comparatorFile.existsSync() &&
        relativeFile.existsSync() &&
        harnessFile.existsSync(),
    'checked comparator evidence inventory exists',
  );
  final String comparatorSource = comparatorFile.readAsStringSync();
  final String relativeSource = relativeFile.readAsStringSync();
  final ProductPerformanceComparatorEvidence comparator =
      decodeProductPerformanceComparator(comparatorSource);
  _expect(
    comparator.provenance['capture_harness_sha256'] ==
            terminalDifferentialSha256(harnessFile.readAsBytesSync()) &&
        comparator.provenance['app_executable_sha256'] ==
            pinnedGhosttyAppExecutableSha256 &&
        comparator.provenance['benchmark_executable_sha256'] ==
            pinnedGhosttyBenchmarkExecutableSha256,
    'checked evidence matches the pinned executables and capture source',
  );
  final Object? decodedRelative = jsonDecode(relativeSource);
  _expect(
    decodedRelative is Map<String, Object?>,
    'checked relative result is an object',
  );
  final Map<String, Object?> relative =
      decodedRelative! as Map<String, Object?>;
  final Object? rawGates = relative['gates'];
  const Set<String> relativeKeys = <String>{
    'format',
    'version',
    'status',
    'comparator_id',
    'comparator_provenance',
    'environment',
    'workload',
    'policy',
    'gates',
  };
  _expect(
    relative.keys.toSet().difference(relativeKeys).isEmpty &&
        relativeKeys.difference(relative.keys.toSet()).isEmpty &&
        relative['format'] ==
            'dart-terminal-product-relative-performance-result' &&
        relative['version'] == 1 &&
        relative['status'] == 'pass' &&
        relative['comparator_id'] == comparator.id &&
        jsonEncode(relative['comparator_provenance']) ==
            jsonEncode(comparator.provenance) &&
        jsonEncode(relative['environment']) ==
            jsonEncode(comparator.environment) &&
        jsonEncode(relative['workload']) == jsonEncode(comparator.workload) &&
        rawGates is List<Object?> &&
        rawGates.length == 4 &&
        rawGates.whereType<Map<String, Object?>>().length == 4 &&
        rawGates.whereType<Map<String, Object?>>().every(
          (Map<String, Object?> gate) => gate['passed'] == true,
        ),
    'checked relative evidence has four exact passing gates',
  );
  final List<Map<String, Object?>> gates = (rawGates as List<Object?>)
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  final Map<String, Map<String, Object?>> gatesById =
      <String, Map<String, Object?>>{
        for (final Map<String, Object?> gate in gates)
          gate['id']! as String: gate,
      };
  const Set<String> expectedGateIds = <String>{
    'input.visible_p95',
    'parser.output_throughput',
    'idle.resident_memory',
    'idle.process_cpu',
  };
  final double inputRatioThreshold =
      comparator.inputVisibleP95Microseconds * 1.25;
  final double inputSlackThreshold =
      comparator.inputVisibleP95Microseconds + 4000;
  const Set<String> gateKeys = <String>{
    'id',
    'unit',
    'operator',
    'product',
    'comparator',
    'threshold',
    'passed',
  };
  _expect(
    gatesById.keys.toSet().difference(expectedGateIds).isEmpty &&
        expectedGateIds.difference(gatesById.keys.toSet()).isEmpty &&
        gates.every(
          (Map<String, Object?> gate) =>
              gate.keys.toSet().difference(gateKeys).isEmpty &&
              gateKeys.difference(gate.keys.toSet()).isEmpty,
        ) &&
        gatesById['input.visible_p95']!['comparator'] ==
            comparator.inputVisibleP95Microseconds &&
        gatesById['parser.output_throughput']!['comparator'] ==
            comparator.parserOutputThroughputMiBPerSecond &&
        gatesById['idle.resident_memory']!['comparator'] ==
            comparator.idleResidentBytes &&
        gatesById['idle.process_cpu']!['comparator'] ==
            comparator.idleCpuBasisPoints &&
        gatesById['input.visible_p95']!['threshold'] ==
            (inputRatioThreshold > inputSlackThreshold
                ? inputRatioThreshold
                : inputSlackThreshold) &&
        gatesById['parser.output_throughput']!['threshold'] ==
            comparator.parserOutputThroughputMiBPerSecond * 0.75 &&
        gatesById['idle.resident_memory']!['threshold'] ==
            comparator.idleResidentBytes * 1.5 &&
        gatesById['idle.process_cpu']!['threshold'] ==
            comparator.idleCpuBasisPoints * 1.5,
    'checked relative gate arithmetic matches comparator evidence',
  );
  final String combined = '$comparatorSource\n$relativeSource';
  _expect(
    !combined.toLowerCase().contains('/users/') &&
        !combined.contains('"pid"') &&
        !combined.contains('"cwd"') &&
        !combined.contains('"timestamp"') &&
        !combined.contains('"raw_samples_retained": true') &&
        !combined.contains('"samples"'),
    'checked evidence retains no paths, process ids, timestamps, or samples',
  );
}

String _uiLine() =>
    'GHOSTTY_COMPARATOR_CAPTURE_PASS input_samples=7 '
    'input_visible_p95_us=12000 idle_window_count=2 '
    'idle_window_us=2000000 idle_cpu_us=5000 '
    'idle_rss_bytes=100000000 occluded_window_us=2000000 '
    'occluded_cpu_us=5000 aggregate_cpu_basis_points=25 '
    'memory_output_bytes=22048 refresh_tier_hz=60 '
    'screen_api=screencapturekit apple_event=true '
    'raw_samples_retained=false content_free=true';

Map<String, Object?> _comparatorEnvironment() => <String, Object?>{
  'os': 'macos',
  'abi': 'macos_arm64',
  'hardware_model': 'MacBookPro17,1',
  'memory_bytes': 17179869184,
  'os_build': '25G83',
  'refresh_tier_hz': 60,
};

Map<String, Object?> _productMicrobenchmark() => <String, Object?>{
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
    <String, Object?>{
      'id': 'parser.product_mixed.throughput',
      'p50': 110,
      'passed': true,
    },
    <String, Object?>{
      'id': 'render.damage.capture_copy_latency',
      'passed': true,
    },
    <String, Object?>{
      'id': 'render.damage.transfer_decode_ack_latency',
      'passed': true,
    },
    <String, Object?>{'id': 'render.damage.end_to_end_latency', 'passed': true},
    <String, Object?>{'id': 'input.key_to_pane_write_latency', 'passed': true},
  ],
  'integrity': <String, Object?>{
    'parser': <String, Object?>{
      'parsed_bytes_per_sample': 134264777,
      'action_hash': 271809813,
      'text_scalars': 58976117,
      'controls': 2509622,
      'sequences': 5019244,
    },
    'damage': <String, Object?>{},
    'input': <String, Object?>{},
  },
};

String _productRuntime() =>
    'TERMINAL_PRODUCT_PERFORMANCE_TEST refresh_samples=8 '
    'refresh_interval_us=16667 input_samples=7 marker=true\n'
    'TERMINAL_PRODUCT_RESOURCE_TEST idle_window_us=2000000 '
    'workload_bytes=22048 marker=true\n'
    'RUNTIME_PRODUCT_PERFORMANCE_INTEGRATION_PASS mode=release-aot '
    'launch_architecture=native startup_us=700000 refresh_interval_us=16667 '
    'input_p95_us=1700 visible_p95_us=12000 frame_p95_us=800 '
    'idle_rss_bytes=200000000 workload_rss_bytes=210000000 '
    'peak_rss_bytes=220000000 idle_cpu_basis_points=10 '
    'occluded_cpu_basis_points=30 aggregate_cpu_basis_points=20 '
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
