import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'product_parser_benchmark.dart';
import 'product_performance_comparator.dart';
import 'terminal_differential_sha256.dart';

const String pinnedGhosttyAppExecutableSha256 =
    '73744c9d8479d7326b1a95920ad6931c3eaed8500eafd97eb133eefd03e1f1dc';
const String pinnedGhosttyBenchmarkExecutableSha256 =
    '0c6ea29728a6429e02a9326be40ccb8d7b36d80d743a90f19b7c599377dbbf23';
const int ghosttyParserWarmupRuns = 2;
const int ghosttyParserSampleCount = 5;
const int ghosttyComparatorInputSamples = 7;
const int ghosttyComparatorMemoryOutputBytes = 22048;
const int _maximumInputCharacters = 64 * 1024;

final class GhosttyUiPerformanceObservation {
  const GhosttyUiPerformanceObservation._({
    required this.inputVisibleP95Microseconds,
    required this.idleResidentBytes,
    required this.aggregateCpuBasisPoints,
    required this.refreshTierHz,
  });

  static final RegExp _machineLine = RegExp(
    r'^GHOSTTY_COMPARATOR_CAPTURE_PASS input_samples=7 '
    r'input_visible_p95_us=([1-9][0-9]*) idle_window_count=2 '
    r'idle_window_us=([1-9][0-9]*) idle_cpu_us=([0-9]+) '
    r'idle_rss_bytes=([1-9][0-9]*) '
    r'occluded_window_us=([1-9][0-9]*) occluded_cpu_us=([0-9]+) '
    r'aggregate_cpu_basis_points=([0-9]+) memory_output_bytes=22048 '
    r'refresh_tier_hz=(60|120) screen_api=screencapturekit '
    r'apple_event=true raw_samples_retained=false content_free=true$',
    multiLine: true,
  );

  final int inputVisibleP95Microseconds;
  final int idleResidentBytes;
  final int aggregateCpuBasisPoints;
  final int refreshTierHz;

  static GhosttyUiPerformanceObservation parse(String source) {
    if (source.length > _maximumInputCharacters) {
      throw const FormatException('Ghostty UI capture output is too large');
    }
    final List<RegExpMatch> matches = _machineLine.allMatches(source).toList();
    if (matches.length != 1 || source.trim() != matches.single.group(0)) {
      throw const FormatException(
        'Ghostty UI capture output is missing, duplicated, or malformed',
      );
    }
    final RegExpMatch match = matches.single;
    final int idleWindowMicroseconds = int.parse(match.group(2)!);
    final int idleCpuMicroseconds = int.parse(match.group(3)!);
    final int occludedWindowMicroseconds = int.parse(match.group(5)!);
    final int occludedCpuMicroseconds = int.parse(match.group(6)!);
    final int aggregateCpuBasisPoints = int.parse(match.group(7)!);
    if (idleWindowMicroseconds < 2000000 ||
        idleWindowMicroseconds > 10000000 ||
        occludedWindowMicroseconds < 2000000 ||
        occludedWindowMicroseconds > 10000000 ||
        idleCpuMicroseconds > idleWindowMicroseconds ||
        occludedCpuMicroseconds > occludedWindowMicroseconds ||
        aggregateCpuBasisPoints !=
            (idleCpuMicroseconds + occludedCpuMicroseconds) *
                10000 ~/
                (idleWindowMicroseconds + occludedWindowMicroseconds)) {
      throw const FormatException('Ghostty resource observation is invalid');
    }
    return GhosttyUiPerformanceObservation._(
      inputVisibleP95Microseconds: int.parse(match.group(1)!),
      idleResidentBytes: int.parse(match.group(4)!),
      aggregateCpuBasisPoints: aggregateCpuBasisPoints,
      refreshTierHz: int.parse(match.group(8)!),
    );
  }
}

final class GhosttyParserPerformanceObservation {
  const GhosttyParserPerformanceObservation({
    required this.outputBytes,
    required this.corpusSha256,
    required this.throughputMiBPerSecond,
  });

  final int outputBytes;
  final String corpusSha256;
  final double throughputMiBPerSecond;
}

final class ProductRelativeInputObservation {
  const ProductRelativeInputObservation({
    required this.environment,
    required this.parserThroughputMiBPerSecond,
    required this.inputVisibleP95Microseconds,
    required this.idleResidentBytes,
    required this.aggregateCpuBasisPoints,
    required this.refreshTierHz,
  });

  final Map<String, Object?> environment;
  final double parserThroughputMiBPerSecond;
  final double inputVisibleP95Microseconds;
  final double idleResidentBytes;
  final double aggregateCpuBasisPoints;
  final int refreshTierHz;
}

Future<GhosttyParserPerformanceObservation> measureGhosttyParser({
  required File benchmarkExecutable,
}) async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-ghostty-parser-',
  );
  try {
    final File corpus = File('${temporary.path}/parser-corpus.bin');
    final Uint8List seed = _ghosttyParserCorpusSeed();
    final int iterations =
        (productParserThroughputTargetBytes + seed.length - 1) ~/ seed.length;
    final IOSink sink = corpus.openWrite();
    for (var iteration = 0; iteration < iterations; iteration++) {
      sink.add(seed);
    }
    await sink.close();
    final int outputBytes = await corpus.length();
    if (outputBytes != 134264777) {
      throw StateError('shared parser corpus length drifted');
    }
    final String corpusSha256 = terminalDifferentialSha256(
      await corpus.readAsBytes(),
    );
    final List<double> samples = <double>[];
    for (
      var run = 0;
      run < ghosttyParserWarmupRuns + ghosttyParserSampleCount;
      run++
    ) {
      final Stopwatch clock = Stopwatch()..start();
      final ({int exitCode, String stdout, String stderr}) result =
          await _runBounded(
            benchmarkExecutable.path,
            <String>['+terminal-parser', '--data=${corpus.path}'],
            timeout: const Duration(seconds: 10),
            environment: <String, String>{
              'HOME': temporary.path,
              'XDG_CACHE_HOME': temporary.path,
              'XDG_CONFIG_HOME': temporary.path,
              'LANG': 'C',
              'LC_ALL': 'C',
            },
          );
      clock.stop();
      final String benchmarkStdout = result.stdout;
      final String benchmarkStderr = result.stderr;
      if (result.exitCode != 0) {
        throw StateError('Ghostty parser benchmark exited unsuccessfully');
      }
      if (benchmarkStdout.trim().isNotEmpty) {
        throw StateError('Ghostty parser benchmark emitted stdout');
      }
      if (!_validGhosttyBenchmarkDiagnostic(benchmarkStderr)) {
        throw StateError('Ghostty parser benchmark diagnostic drifted');
      }
      if (clock.elapsedMicroseconds <= 0) {
        throw StateError('Ghostty parser benchmark clock did not advance');
      }
      if (run >= ghosttyParserWarmupRuns) {
        samples.add(
          outputBytes * 1000000 / clock.elapsedMicroseconds / (1024 * 1024),
        );
      }
    }
    samples.sort();
    return GhosttyParserPerformanceObservation(
      outputBytes: outputBytes,
      corpusSha256: corpusSha256,
      throughputMiBPerSecond: samples[2],
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

Map<String, Object?> buildGhosttyComparatorEvidence({
  required GhosttyUiPerformanceObservation ui,
  required GhosttyParserPerformanceObservation parser,
  required String captureHarnessSha256,
  required Map<String, Object?> environment,
}) {
  if (parser.outputBytes != 134264777 ||
      !_validSha256(parser.corpusSha256) ||
      !_validSha256(captureHarnessSha256) ||
      environment['refresh_tier_hz'] != ui.refreshTierHz) {
    throw ArgumentError('comparator capture inputs are incompatible');
  }
  return <String, Object?>{
    'format': 'dart-terminal-performance-comparator-evidence',
    'version': 1,
    'id': 'ghostty-d4d8f62-macos-arm64-m1',
    'environment': environment,
    'provenance': <String, Object?>{
      'product': 'ghostty',
      'revision': pinnedGhosttyRevision,
      'zig_version': pinnedGhosttyZigVersion,
      'build_command': pinnedGhosttyBuildCommand,
      'benchmark_build_command': pinnedGhosttyBenchmarkBuildCommand,
      'macos_configuration': pinnedGhosttyMacosConfiguration,
      'project_local_patches': false,
      'app_executable_sha256': pinnedGhosttyAppExecutableSha256,
      'benchmark_executable_sha256': pinnedGhosttyBenchmarkExecutableSha256,
      'capture_harness_sha256': captureHarnessSha256,
    },
    'workload': <String, Object?>{
      'id': productRelativeWorkloadId,
      'shell_fixture': 'isolated-zsh-v1',
      'configuration': 'parity-minimal-v1',
      'input_transport': 'applescript-input-text',
      'visibility_observer': 'screencapturekit-window-pixel',
      'input_samples': ghosttyComparatorInputSamples,
      'parser_action': 'terminal-parser',
      'parser_warmup_runs': ghosttyParserWarmupRuns,
      'parser_sample_count': ghosttyParserSampleCount,
      'parser_statistic': 'p50',
      'parser_output_bytes': parser.outputBytes,
      'parser_corpus_sha256': parser.corpusSha256,
      'memory_output_bytes': ghosttyComparatorMemoryOutputBytes,
      'resource_scope': 'root-process',
      'idle_window_count': 2,
      'idle_window_us': 2000000,
      'animation_enabled': false,
      'raw_samples_retained': false,
    },
    'metrics': <String, Object?>{
      'input_visible_p95_us': ui.inputVisibleP95Microseconds,
      'parser_output_throughput_mib_s': parser.throughputMiBPerSecond,
      'idle_rss_bytes': ui.idleResidentBytes,
      'idle_cpu_basis_points': ui.aggregateCpuBasisPoints,
    },
  };
}

ProductRelativeInputObservation decodeProductRelativeInput({
  required String microbenchmarkSource,
  required String runtimeSource,
}) {
  if (microbenchmarkSource.length > _maximumInputCharacters ||
      runtimeSource.length > _maximumInputCharacters) {
    throw const FormatException('product performance input is too large');
  }
  final Object? decoded = jsonDecode(microbenchmarkSource);
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != 'dart-terminal-product-benchmark-result' ||
      decoded['version'] != 1 ||
      decoded['suite'] != 'product-micro' ||
      decoded['status'] != 'pass' ||
      decoded['baseline_id'] != 'product-micro-macos-arm64-m1') {
    throw const FormatException('product microbenchmark result is invalid');
  }
  _expectExactKeys(decoded, const <String>{
    'format',
    'version',
    'suite',
    'status',
    'baseline_id',
    'environment',
    'provenance',
    'measurement_policy',
    'metrics',
    'integrity',
  }, 'product microbenchmark');
  final Map<String, Object?> environment = _object(
    decoded['environment'],
    'product environment',
  );
  final Map<String, Object?> provenance = _object(
    decoded['provenance'],
    'product provenance',
  );
  final Map<String, Object?> integrity = _object(
    decoded['integrity'],
    'product integrity',
  );
  final Map<String, Object?> parserIntegrity = _object(
    integrity['parser'],
    'product parser integrity',
  );
  final Map<String, Object?> measurementPolicy = _object(
    decoded['measurement_policy'],
    'product measurement policy',
  );
  _expectExactKeys(environment, const <String>{
    'os',
    'abi',
    'dart_sdk',
    'build_mode',
    'hardware_model',
    'memory_bytes',
  }, 'product environment');
  _expectExactKeys(provenance, const <String>{
    'workload',
    'parser_workload',
    'parser_target_bytes',
    'parser_seed_bytes',
    'damage_packet_version',
    'damage_rows',
    'damage_columns',
    'damage_iterations',
    'input_route',
    'input_iterations',
    'measurement_policy_version',
  }, 'product provenance');
  _expectExactKeys(integrity, const <String>{
    'parser',
    'damage',
    'input',
  }, 'product integrity');
  _expectExactKeys(parserIntegrity, const <String>{
    'parsed_bytes_per_sample',
    'action_hash',
    'text_scalars',
    'controls',
    'sequences',
  }, 'product parser integrity');
  _expectExactKeys(measurementPolicy, const <String>{
    'clock',
    'percentiles',
    'warmup_required',
    'raw_samples_retained',
  }, 'product measurement policy');
  final Object? percentiles = measurementPolicy['percentiles'];
  if (environment['os'] != 'macos' ||
      environment['abi'] != 'macos_arm64' ||
      environment['build_mode'] != 'release-aot' ||
      environment['hardware_model'] is! String ||
      environment['memory_bytes'] is! int ||
      provenance['parser_workload'] != 'phase0-mixed-v1-product-vt-parser' ||
      provenance['parser_target_bytes'] != productParserThroughputTargetBytes ||
      provenance['parser_seed_bytes'] != _ghosttyParserCorpusSeed().length ||
      parserIntegrity['parsed_bytes_per_sample'] != 134264777 ||
      measurementPolicy['clock'] != 'dart-stopwatch-monotonic' ||
      percentiles is! List<Object?> ||
      jsonEncode(percentiles) != '[50,95,99]' ||
      measurementPolicy['warmup_required'] != true ||
      measurementPolicy['raw_samples_retained'] != false) {
    throw const FormatException('product parser compatibility is invalid');
  }
  final Object? rawMetrics = decoded['metrics'];
  if (rawMetrics is! List<Object?> || rawMetrics.length != 5) {
    throw const FormatException('product metrics are invalid');
  }
  final List<Map<String, Object?>> metrics = rawMetrics
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  const Set<String> expectedMetricIds = <String>{
    'parser.product_mixed.throughput',
    'render.damage.capture_copy_latency',
    'render.damage.transfer_decode_ack_latency',
    'render.damage.end_to_end_latency',
    'input.key_to_pane_write_latency',
  };
  if (metrics.length != 5 ||
      metrics
          .map((Map<String, Object?> metric) => metric['id'])
          .toSet()
          .difference(expectedMetricIds)
          .isNotEmpty ||
      expectedMetricIds
          .difference(
            metrics.map((Map<String, Object?> metric) => metric['id']).toSet(),
          )
          .isNotEmpty ||
      metrics.any((Map<String, Object?> metric) => metric['passed'] != true)) {
    throw const FormatException('product metric inventory is invalid');
  }
  final List<Map<String, Object?>> parserMetrics = metrics
      .where(
        (Map<String, Object?> metric) =>
            metric['id'] == 'parser.product_mixed.throughput',
      )
      .toList();
  if (parserMetrics.length != 1 ||
      parserMetrics.single['passed'] != true ||
      parserMetrics.single['p50'] is! num) {
    throw const FormatException('product parser metric is invalid');
  }

  final RegExp summaryPattern = RegExp(
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
  final List<RegExpMatch> summaries = summaryPattern
      .allMatches(runtimeSource)
      .toList();
  if (summaries.length != 1) {
    throw const FormatException('product runtime result is invalid');
  }
  final RegExpMatch summary = summaries.single;
  final int refreshIntervalMicroseconds = int.parse(summary.group(2)!);
  if (refreshIntervalMicroseconds <= 0 || refreshIntervalMicroseconds > 25000) {
    throw const FormatException('product refresh tier is invalid');
  }
  return ProductRelativeInputObservation(
    environment: environment,
    parserThroughputMiBPerSecond: _finite(
      parserMetrics.single['p50'],
      'product parser p50',
    ),
    inputVisibleP95Microseconds: int.parse(summary.group(4)!).toDouble(),
    idleResidentBytes: int.parse(summary.group(6)!).toDouble(),
    aggregateCpuBasisPoints: int.parse(summary.group(11)!).toDouble(),
    refreshTierHz: refreshIntervalMicroseconds <= 12500 ? 120 : 60,
  );
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = _parseArguments(arguments);
  final Directory app = Directory(options['ghostty-app']!);
  final File appExecutable = File('${app.path}/Contents/MacOS/ghostty');
  final File benchmarkExecutable = File(options['ghostty-benchmark']!);
  final File captureSource = File(options['capture-source']!);
  final File productMicro = File(options['product-micro']!);
  final File productRuntime = File(options['product-runtime']!);
  final File evidenceOutput = File(options['output-evidence']!);
  final File relativeOutput = File(options['output-relative']!);
  for (final File file in <File>[
    appExecutable,
    benchmarkExecutable,
    captureSource,
    productMicro,
    productRuntime,
  ]) {
    if (!file.isAbsolute || !await file.exists()) {
      throw const FormatException('capture input must be an absolute file');
    }
  }
  if (!evidenceOutput.isAbsolute || !relativeOutput.isAbsolute) {
    throw const FormatException('capture output must be absolute');
  }
  final String appHash = await _fileSha256(appExecutable);
  final String benchmarkHash = await _fileSha256(benchmarkExecutable);
  if (appHash != pinnedGhosttyAppExecutableSha256 ||
      benchmarkHash != pinnedGhosttyBenchmarkExecutableSha256) {
    throw StateError('pinned Ghostty executable identity is invalid');
  }

  final Directory helperDirectory = await Directory.systemTemp.createTemp(
    'dart-terminal-ghostty-capture-',
  );
  try {
    final File helper = File('${helperDirectory.path}/capture');
    final ({int exitCode, String stdout, String stderr}) compilation =
        await _runBounded('/usr/bin/xcrun', <String>[
          'swiftc',
          '-module-cache-path',
          '${helperDirectory.path}/module-cache',
          '-parse-as-library',
          '-O',
          '-framework',
          'AppKit',
          '-framework',
          'ScreenCaptureKit',
          '-framework',
          'CoreGraphics',
          captureSource.path,
          '-o',
          helper.path,
        ], timeout: const Duration(seconds: 30));
    if (compilation.exitCode != 0 ||
        compilation.stdout.trim().isNotEmpty ||
        compilation.stderr.trim().isNotEmpty) {
      throw StateError('Ghostty capture helper compilation failed closed');
    }
    final ({int exitCode, String stdout, String stderr}) capture =
        await _runBounded(helper.path, <String>[
          '--app=${app.path}',
        ], timeout: const Duration(seconds: 45));
    if (capture.exitCode != 0 || capture.stderr.trim().isNotEmpty) {
      throw StateError('Ghostty UI capture failed closed');
    }
    final GhosttyUiPerformanceObservation ui =
        GhosttyUiPerformanceObservation.parse(capture.stdout);
    final GhosttyParserPerformanceObservation parser =
        await measureGhosttyParser(benchmarkExecutable: benchmarkExecutable);
    final Map<String, Object?> environment = _currentEnvironment(
      refreshTierHz: ui.refreshTierHz,
    );
    final Map<String, Object?> evidence = buildGhosttyComparatorEvidence(
      ui: ui,
      parser: parser,
      captureHarnessSha256: await _fileSha256(captureSource),
      environment: environment,
    );
    final String encodedEvidence =
        '${const JsonEncoder.withIndent('  ').convert(evidence)}\n';
    final ProductPerformanceComparatorEvidence comparator =
        decodeProductPerformanceComparator(encodedEvidence);
    final ProductRelativeInputObservation product = decodeProductRelativeInput(
      microbenchmarkSource: await productMicro.readAsString(),
      runtimeSource: await productRuntime.readAsString(),
    );
    for (final String key in <String>[
      'os',
      'abi',
      'hardware_model',
      'memory_bytes',
    ]) {
      if (product.environment[key] != environment[key]) {
        throw StateError('product and comparator environment differ');
      }
    }
    if (product.refreshTierHz != ui.refreshTierHz) {
      throw StateError('product and comparator refresh tiers differ');
    }
    final ProductRelativePerformanceResult relative =
        evaluateProductRelativePerformance(
          product: ProductRelativePerformanceObservation(
            environment: environment,
            workload: comparator.workload,
            inputVisibleP95Microseconds: product.inputVisibleP95Microseconds,
            parserOutputThroughputMiBPerSecond:
                product.parserThroughputMiBPerSecond,
            idleResidentBytes: product.idleResidentBytes,
            idleCpuBasisPoints: product.aggregateCpuBasisPoints,
          ),
          comparator: comparator,
        );
    stdout.writeln(
      'GHOSTTY_RELATIVE_PERFORMANCE_${relative.passed ? 'PASS' : 'FAIL'} '
      'metrics=4 comparator=${comparator.id} content_free=true',
    );
    if (!relative.passed) {
      exitCode = 1;
      return;
    }
    await _writeAtomic(evidenceOutput, encodedEvidence);
    await _writeAtomic(relativeOutput, relative.encode());
  } finally {
    await helperDirectory.delete(recursive: true);
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  const Set<String> expected = <String>{
    'ghostty-app',
    'ghostty-benchmark',
    'capture-source',
    'product-micro',
    'product-runtime',
    'output-evidence',
    'output-relative',
  };
  final Map<String, String> result = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw const FormatException('capture argument is malformed');
    }
    final int separator = argument.indexOf('=');
    final String key = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    if (!expected.contains(key) || value.isEmpty || result.containsKey(key)) {
      throw const FormatException('capture argument is unknown or duplicated');
    }
    result[key] = value;
  }
  if (result.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(result.keys.toSet()).isNotEmpty) {
    throw const FormatException('capture argument inventory is incomplete');
  }
  return result;
}

Map<String, Object?> _currentEnvironment({
  required int refreshTierHz,
}) => <String, Object?>{
  'os': Platform.operatingSystem,
  'abi': Abi.current().toString(),
  'hardware_model': _systemValue('/usr/sbin/sysctl', const <String>[
    '-n',
    'hw.model',
  ]),
  'memory_bytes': int.parse(
    _systemValue('/usr/sbin/sysctl', const <String>['-n', 'hw.memsize']),
  ),
  'os_build': _systemValue('/usr/bin/sw_vers', const <String>['-buildVersion']),
  'refresh_tier_hz': refreshTierHz,
};

String _systemValue(String executable, List<String> arguments) {
  final ProcessResult result = Process.runSync(executable, arguments);
  final String value = result.stdout is String
      ? (result.stdout as String).trim()
      : '';
  if (result.exitCode != 0 ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains('\n')) {
    throw StateError('comparator environment is unavailable');
  }
  return value;
}

Future<String> _fileSha256(File file) async =>
    terminalDifferentialSha256(await file.readAsBytes());

Future<void> _writeAtomic(File output, String source) async {
  await output.parent.create(recursive: true);
  final File temporary = File('${output.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString(source, flush: true);
  await temporary.rename(output.path);
}

Future<({int exitCode, String stdout, String stderr})> _runBounded(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  Map<String, String>? environment,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    environment: environment,
  );
  final Future<String> stdoutResult = process.stdout
      .transform(utf8.decoder)
      .join();
  final Future<String> stderrResult = process.stderr
      .transform(utf8.decoder)
      .join();
  late final int status;
  try {
    status = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await Future.wait(<Future<String>>[stdoutResult, stderrResult]);
    throw StateError('bounded comparator child timed out');
  }
  return (
    exitCode: status,
    stdout: await stdoutResult,
    stderr: await stderrResult,
  );
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
  final Set<String> actual = value.keys.toSet();
  if (actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw FormatException('$name has an invalid key inventory');
  }
}

double _finite(Object? value, String name) {
  if (value is! num || !value.toDouble().isFinite || value <= 0) {
    throw FormatException('$name must be finite and positive');
  }
  return value.toDouble();
}

bool _validSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _validGhosttyBenchmarkDiagnostic(String source) {
  if (source.length > 4096) return false;
  final List<String> lines = const LineSplitter()
      .convert(source.trim())
      .toList(growable: false);
  const List<String> required = <String>[
    'info: ghostty version=1.3.2-HEAD-+d4d8f62',
    'info: ghostty build optimize=ReleaseFast',
    'info: runtime=.none',
    'info: font_backend=.coretext',
    'info: renderer=renderer.generic.Renderer(renderer.Metal)',
    'info: libxev default backend=kqueue',
    'info(os_locale): setlocale from env result=C',
  ];
  const Set<String> optional = <String>{
    'error: SentryInitFailed',
    'info(sentry): sentry envelope does not contain crash, discarding',
  };
  final List<String> normalized = lines
      .where((String line) => !optional.contains(line))
      .toList(growable: false);
  if (normalized.length != required.length ||
      lines.length > required.length + optional.length ||
      optional.any(
        (String line) =>
            lines.where((String value) => value == line).length > 1,
      )) {
    return false;
  }
  for (var index = 0; index < required.length; index++) {
    if (normalized[index] != required[index]) return false;
  }
  return true;
}

Uint8List _ghosttyParserCorpusSeed() {
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
