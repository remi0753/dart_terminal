import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'product_parser_benchmark.dart';
import 'terminal_damage_benchmark.dart';

const bool _releaseAot = bool.fromEnvironment('dart.vm.product');
const int _maximumMetrics = 32;
const int _maximumSamplesPerMetric = 200000;
const int _maximumBaselineCharacters = 64 * 1024;
const String productPerformanceWorkload = 'phase11-product-micro-v1';

enum ProductPerformanceDirection { higher, lower }

final class ProductPerformanceMetric {
  ProductPerformanceMetric({
    required this.id,
    required this.unit,
    required this.direction,
    required Iterable<num> samples,
    required this.hardStat,
    required this.hardOperator,
    required this.hardValue,
  }) : samples = List<double>.unmodifiable(
         samples.map((num value) => value.toDouble()),
       ) {
    if (!_validToken(id) || !_validToken(unit)) {
      throw ArgumentError('metric id and unit must be bounded tokens');
    }
    if (this.samples.isEmpty ||
        this.samples.length > _maximumSamplesPerMetric ||
        this.samples.any((double value) => !value.isFinite || value < 0)) {
      throw ArgumentError('metric samples must be finite and bounded');
    }
    if (hardStat != 'min' && hardStat != 'p95') {
      throw ArgumentError.value(hardStat, 'hardStat');
    }
    if (hardOperator != '>=' && hardOperator != '<') {
      throw ArgumentError.value(hardOperator, 'hardOperator');
    }
    if (!hardValue.isFinite || hardValue <= 0) {
      throw ArgumentError.value(hardValue, 'hardValue');
    }
  }

  final String id;
  final String unit;
  final ProductPerformanceDirection direction;
  final List<double> samples;
  final String hardStat;
  final String hardOperator;
  final double hardValue;

  Map<String, Object?> toJson({ProductPerformanceBaselineSpec? baseline}) {
    final List<double> sorted = List<double>.of(samples)..sort();
    final Map<String, double> statistics = <String, double>{
      'min': sorted.first,
      'p50': _percentile(sorted, 50),
      'p95': _percentile(sorted, 95),
      'p99': _percentile(sorted, 99),
      'max': sorted.last,
    };
    final double hardObserved = statistics[hardStat]!;
    final bool hardPassed = _compare(hardObserved, hardOperator, hardValue);
    Map<String, Object?>? baselineGate;
    var passed = hardPassed;
    if (baseline != null) {
      final double observed = statistics[baseline.stat]!;
      final double threshold = direction == ProductPerformanceDirection.higher
          ? baseline.reference * (1 - baseline.relativeTolerance) -
                baseline.absoluteSlack
          : baseline.reference * (1 + baseline.relativeTolerance) +
                baseline.absoluteSlack;
      final bool baselinePassed =
          direction == ProductPerformanceDirection.higher
          ? observed >= threshold
          : observed <= threshold;
      baselineGate = <String, Object?>{
        'stat': baseline.stat,
        'reference': baseline.reference,
        'relative_tolerance': baseline.relativeTolerance,
        'absolute_slack': baseline.absoluteSlack,
        'threshold': threshold,
        'passed': baselinePassed,
      };
      passed = passed && baselinePassed;
    }
    return <String, Object?>{
      'id': id,
      'unit': unit,
      'direction': direction.name,
      'sample_count': samples.length,
      ...statistics,
      'hard_gate': <String, Object?>{
        'stat': hardStat,
        'operator': hardOperator,
        'value': hardValue,
        'passed': hardPassed,
      },
      if (baselineGate != null) 'baseline_gate': baselineGate,
      'passed': passed,
    };
  }
}

final class ProductPerformanceBaselineSpec {
  const ProductPerformanceBaselineSpec({
    required this.stat,
    required this.reference,
    required this.relativeTolerance,
    required this.absoluteSlack,
  });

  final String stat;
  final double reference;
  final double relativeTolerance;
  final double absoluteSlack;
}

final class ProductPerformanceBaseline {
  ProductPerformanceBaseline({
    required this.id,
    required Map<String, Object?> environment,
    required Map<String, Object?> provenance,
    required Map<String, ProductPerformanceBaselineSpec> metrics,
  }) : environment = Map<String, Object?>.unmodifiable(environment),
       provenance = Map<String, Object?>.unmodifiable(provenance),
       metrics = Map<String, ProductPerformanceBaselineSpec>.unmodifiable(
         metrics,
       );

  final String id;
  final Map<String, Object?> environment;
  final Map<String, Object?> provenance;
  final Map<String, ProductPerformanceBaselineSpec> metrics;
}

final class ProductPerformanceRun {
  const ProductPerformanceRun({required this.document, required this.passed});

  final Map<String, Object?> document;
  final bool passed;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

ProductPerformanceBaseline decodeProductPerformanceBaseline(String source) {
  if (source.length > _maximumBaselineCharacters) {
    throw const FormatException('benchmark baseline is too large');
  }
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('benchmark baseline must be an object');
  }
  _expectExactKeys(decoded, const <String>{
    'format',
    'version',
    'id',
    'environment',
    'provenance',
    'metrics',
  }, 'baseline');
  if (decoded['format'] != 'dart-terminal-product-benchmark-baseline' ||
      decoded['version'] != 1 ||
      decoded['id'] is! String ||
      !_validToken(decoded['id']! as String)) {
    throw const FormatException('unsupported benchmark baseline');
  }
  final Map<String, Object?> environment = _object(
    decoded['environment'],
    'environment',
  );
  final Map<String, Object?> provenance = _object(
    decoded['provenance'],
    'provenance',
  );
  final Map<String, Object?> rawMetrics = _object(
    decoded['metrics'],
    'metrics',
  );
  if (rawMetrics.isEmpty || rawMetrics.length > _maximumMetrics) {
    throw const FormatException('baseline metric count is invalid');
  }
  final Map<String, ProductPerformanceBaselineSpec> metrics =
      <String, ProductPerformanceBaselineSpec>{};
  for (final MapEntry<String, Object?> entry in rawMetrics.entries) {
    if (!_validToken(entry.key)) {
      throw const FormatException('baseline metric id is invalid');
    }
    final Map<String, Object?> specification = _object(
      entry.value,
      'metric specification',
    );
    _expectExactKeys(specification, const <String>{
      'stat',
      'reference',
      'relative_tolerance',
      'absolute_slack',
    }, 'metric specification');
    final Object? stat = specification['stat'];
    final double reference = _finiteNumber(
      specification['reference'],
      'reference',
    );
    final double tolerance = _finiteNumber(
      specification['relative_tolerance'],
      'relative_tolerance',
    );
    final double slack = _finiteNumber(
      specification['absolute_slack'],
      'absolute_slack',
    );
    if ((stat != 'min' && stat != 'p50' && stat != 'p95') ||
        reference <= 0 ||
        tolerance < 0 ||
        tolerance >= 1 ||
        slack < 0) {
      throw const FormatException('baseline metric threshold is invalid');
    }
    metrics[entry.key] = ProductPerformanceBaselineSpec(
      stat: stat! as String,
      reference: reference,
      relativeTolerance: tolerance,
      absoluteSlack: slack,
    );
  }
  return ProductPerformanceBaseline(
    id: decoded['id']! as String,
    environment: environment,
    provenance: provenance,
    metrics: metrics,
  );
}

ProductPerformanceRun evaluateProductPerformance({
  required Iterable<ProductPerformanceMetric> metrics,
  required Map<String, Object?> environment,
  required Map<String, Object?> provenance,
  required Map<String, Object?> integrity,
  ProductPerformanceBaseline? baseline,
}) {
  final List<ProductPerformanceMetric> ordered =
      List<ProductPerformanceMetric>.of(metrics);
  if (ordered.isEmpty || ordered.length > _maximumMetrics) {
    throw ArgumentError('metric count is invalid');
  }
  final Set<String> ids = ordered
      .map((ProductPerformanceMetric value) => value.id)
      .toSet();
  if (ids.length != ordered.length) {
    throw ArgumentError('metric ids must be unique');
  }
  if (baseline != null) {
    _expectCompatible(environment, baseline.environment, 'environment');
    _expectCompatible(provenance, baseline.provenance, 'provenance');
    if (baseline.metrics.keys.toSet().difference(ids).isNotEmpty ||
        ids.difference(baseline.metrics.keys.toSet()).isNotEmpty) {
      throw const FormatException('baseline metric inventory differs');
    }
  }
  final List<Map<String, Object?>> encodedMetrics = ordered
      .map(
        (ProductPerformanceMetric metric) =>
            metric.toJson(baseline: baseline?.metrics[metric.id]),
      )
      .toList(growable: false);
  final bool passed = encodedMetrics.every(
    (Map<String, Object?> metric) => metric['passed'] == true,
  );
  return ProductPerformanceRun(
    passed: passed,
    document: <String, Object?>{
      'format': 'dart-terminal-product-benchmark-result',
      'version': 1,
      'suite': 'product-micro',
      'status': passed ? 'pass' : 'fail',
      'baseline_id': baseline?.id,
      'environment': Map<String, Object?>.unmodifiable(environment),
      'provenance': Map<String, Object?>.unmodifiable(provenance),
      'measurement_policy': const <String, Object?>{
        'clock': 'dart-stopwatch-monotonic',
        'percentiles': <int>[50, 95, 99],
        'warmup_required': true,
        'raw_samples_retained': false,
      },
      'metrics': encodedMetrics,
      'integrity': Map<String, Object?>.unmodifiable(integrity),
    },
  );
}

Future<ProductPerformanceRun> runProductPerformanceMicrobenchmark({
  int parserSampleCount = 5,
  int parserTargetBytes = productParserThroughputTargetBytes,
  int damageWarmupIterations = 8,
  int damageTimedIterations = 64,
  int inputWarmupIterations = 10000,
  int inputTimedIterations = 100000,
  Map<String, Object?>? environment,
  ProductPerformanceBaseline? baseline,
}) async {
  if (parserSampleCount < 3 || parserSampleCount > 31) {
    throw RangeError.range(parserSampleCount, 3, 31, 'parserSampleCount');
  }
  final List<ProductParserBenchmarkResult> parserRuns =
      <ProductParserBenchmarkResult>[];
  for (var sample = 0; sample < parserSampleCount; sample++) {
    parserRuns.add(
      runProductParserBenchmark(
        targetBytes: parserTargetBytes,
        warmupRuns: sample == 0 ? 16 : 2,
      ),
    );
  }
  final ProductParserBenchmarkResult parserIntegrity = parserRuns.first;
  if (parserRuns.any(
    (ProductParserBenchmarkResult value) =>
        value.seedBytes != parserIntegrity.seedBytes ||
        value.parsedBytes != parserIntegrity.parsedBytes ||
        value.integrityHash != parserIntegrity.integrityHash ||
        value.textScalars != parserIntegrity.textScalars ||
        value.controls != parserIntegrity.controls ||
        value.sequences != parserIntegrity.sequences ||
        value.cancels != 0 ||
        value.limits != 0 ||
        value.malformed != 0 ||
        value.incomplete != 0,
  )) {
    throw StateError('product parser benchmark integrity drifted');
  }

  final ProductDamageBenchmarkResult damage = await runProductDamageBenchmark(
    warmupIterations: damageWarmupIterations,
    timedIterations: damageTimedIterations,
  );
  final _ProductInputBenchmarkResult input = await _benchmarkProductInput(
    warmupIterations: inputWarmupIterations,
    timedIterations: inputTimedIterations,
  );
  final Map<String, Object?> provenance = <String, Object?>{
    'workload': productPerformanceWorkload,
    'parser_workload': 'phase0-mixed-v1-product-vt-parser',
    'parser_target_bytes': parserTargetBytes,
    'parser_seed_bytes': parserIntegrity.seedBytes,
    'damage_packet_version': TerminalDamageCodec.version,
    'damage_rows': 200,
    'damage_columns': 500,
    'damage_iterations': damageTimedIterations,
    'input_route': 'terminal-key-router-pane-write-v1',
    'input_iterations': inputTimedIterations,
    'measurement_policy_version': 1,
  };
  return evaluateProductPerformance(
    metrics: <ProductPerformanceMetric>[
      ProductPerformanceMetric(
        id: 'parser.product_mixed.throughput',
        unit: 'MiB/s',
        direction: ProductPerformanceDirection.higher,
        samples: parserRuns.map(
          (ProductParserBenchmarkResult value) => value.mibPerSecond,
        ),
        hardStat: 'min',
        hardOperator: '>=',
        hardValue: productParserMinimumMiBPerSecond,
      ),
      ProductPerformanceMetric(
        id: 'render.damage.capture_copy_latency',
        unit: 'us',
        direction: ProductPerformanceDirection.lower,
        samples: damage.captureMicros,
        hardStat: 'p95',
        hardOperator: '<',
        hardValue: 4000,
      ),
      ProductPerformanceMetric(
        id: 'render.damage.transfer_decode_ack_latency',
        unit: 'us',
        direction: ProductPerformanceDirection.lower,
        samples: damage.transferMicros,
        hardStat: 'p95',
        hardOperator: '<',
        hardValue: 4000,
      ),
      ProductPerformanceMetric(
        id: 'render.damage.end_to_end_latency',
        unit: 'us',
        direction: ProductPerformanceDirection.lower,
        samples: damage.endToEndMicros,
        hardStat: 'p95',
        hardOperator: '<',
        hardValue: 8000,
      ),
      ProductPerformanceMetric(
        id: 'input.key_to_pane_write_latency',
        unit: 'ns',
        direction: ProductPerformanceDirection.lower,
        samples: input.latencyNanoseconds,
        hardStat: 'p95',
        hardOperator: '<',
        hardValue: 2000000,
      ),
    ],
    environment: environment ?? _currentEnvironment(),
    provenance: provenance,
    integrity: <String, Object?>{
      'parser': <String, Object?>{
        'parsed_bytes_per_sample': parserIntegrity.parsedBytes,
        'action_hash': parserIntegrity.integrityHash,
        'text_scalars': parserIntegrity.textScalars,
        'controls': parserIntegrity.controls,
        'sequences': parserIntegrity.sequences,
      },
      'damage': <String, Object?>{
        'packet_bytes': damage.transferredBytes ~/ damage.timedIterations,
        'transferred_bytes': damage.transferredBytes,
        'iterations': damage.timedIterations,
      },
      'input': <String, Object?>{
        'events': input.eventCount,
        'writes': input.writeCount,
        'bytes': input.byteCount,
        'checksum': input.checksum,
        'queue_capacity_bytes': input.queueCapacityBytes,
        'queue_peak_bytes': input.queuePeakBytes,
        'queue_rejections': input.queueRejections,
      },
    },
    baseline: baseline,
  );
}

Future<void> main(List<String> arguments) async {
  if (!_releaseAot) {
    throw StateError('product performance benchmark must run as Release AOT');
  }
  String? baselinePath;
  for (final String argument in arguments) {
    if (argument.startsWith('--baseline=')) {
      baselinePath = argument.substring('--baseline='.length);
    } else {
      throw FormatException('unknown benchmark argument');
    }
  }
  if (baselinePath != null && !File(baselinePath).isAbsolute) {
    throw const FormatException('benchmark baseline path must be absolute');
  }
  final ProductPerformanceBaseline? baseline = baselinePath == null
      ? null
      : decodeProductPerformanceBaseline(
          await File(baselinePath).readAsString(),
        );
  final ProductPerformanceRun result =
      await runProductPerformanceMicrobenchmark(baseline: baseline);
  stdout.write(result.encode());
  stderr.writeln(
    'PRODUCT_PERFORMANCE_BENCHMARK_${result.passed ? 'PASS' : 'FAIL'} '
    'metrics=5 baseline=${baseline?.id ?? 'none'}',
  );
  if (!result.passed) exitCode = 1;
}

Future<_ProductInputBenchmarkResult> _benchmarkProductInput({
  required int warmupIterations,
  required int timedIterations,
}) async {
  if (warmupIterations < 0 || warmupIterations > 1000000) {
    throw RangeError.range(warmupIterations, 0, 1000000, 'warmupIterations');
  }
  if (timedIterations <= 0 || timedIterations > _maximumSamplesPerMetric) {
    throw RangeError.range(
      timedIterations,
      1,
      _maximumSamplesPerMetric,
      'timedIterations',
    );
  }
  final TerminalPaneOwner owner = TerminalPaneOwner();
  late final _BenchmarkPaneSession session;
  final TerminalPane pane = owner.createPane(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          session = _BenchmarkPaneSession(id);
          return session;
        },
    onChanged: () {},
    onExitRequested: () {},
  );
  await pane.start();
  final TerminalKeyEventRouter router = TerminalKeyEventRouter();
  const List<TerminalKeyEvent> events = <TerminalKeyEvent>[
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyA,
      text: 'a',
      unmodifiedText: 'a',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyB,
      text: 'b',
      unmodifiedText: 'b',
      modifiers: TerminalKeyModifiers(option: true),
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.arrowUp,
      modifiers: TerminalKeyModifiers(function: true),
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyJ,
      text: '日',
      unmodifiedText: 'j',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.enter,
      text: '\r',
      unmodifiedText: '\r',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyZ,
      text: 'Z',
      unmodifiedText: 'z',
      modifiers: TerminalKeyModifiers(shift: true),
    ),
  ];
  void route(int iteration) {
    final TerminalKeyRouteResult result = router.handleTerminalKeyEvent(
      events[iteration % events.length],
      pane,
    );
    if (result.disposition != TerminalKeyRouteDisposition.encoded ||
        result.encodedByteCount <= 0) {
      throw StateError('product input benchmark did not write one event');
    }
  }

  for (var warmup = 0; warmup < warmupIterations; warmup++) {
    route(warmup);
  }
  session.resetMeasurements();
  final Stopwatch clock = Stopwatch()..start();
  final List<double> latencyNanoseconds = List<double>.filled(
    timedIterations,
    0,
  );
  for (var sample = 0; sample < timedIterations; sample++) {
    final int before = clock.elapsedTicks;
    route(sample);
    final int after = clock.elapsedTicks;
    latencyNanoseconds[sample] =
        (after - before) * 1000000000 / clock.frequency;
  }
  clock.stop();
  final _ProductInputBenchmarkResult result = _ProductInputBenchmarkResult(
    latencyNanoseconds: List<double>.unmodifiable(latencyNanoseconds),
    eventCount: timedIterations,
    writeCount: session.writeCount,
    byteCount: session.byteCount,
    checksum: session.checksum,
    queueCapacityBytes: _BenchmarkPaneSession.queueCapacityBytes,
    queuePeakBytes: session.queuePeakBytes,
    queueRejections: session.queueRejections,
  );
  await owner.shutdown();
  if (result.writeCount != timedIterations ||
      result.queueRejections != 0 ||
      result.queuePeakBytes > result.queueCapacityBytes ||
      result.checksum == 0) {
    throw StateError('product input benchmark integrity drifted');
  }
  return result;
}

final class _ProductInputBenchmarkResult {
  const _ProductInputBenchmarkResult({
    required this.latencyNanoseconds,
    required this.eventCount,
    required this.writeCount,
    required this.byteCount,
    required this.checksum,
    required this.queueCapacityBytes,
    required this.queuePeakBytes,
    required this.queueRejections,
  });

  final List<double> latencyNanoseconds;
  final int eventCount;
  final int writeCount;
  final int byteCount;
  final int checksum;
  final int queueCapacityBytes;
  final int queuePeakBytes;
  final int queueRejections;
}

final class _BenchmarkPaneSession implements TerminalPaneSession {
  _BenchmarkPaneSession(this.id);

  @override
  final TerminalSessionId id;
  static const int queueCapacityBytes = 64 * 1024;
  var _live = false;
  var _queuedBytes = 0;
  var writeCount = 0;
  var byteCount = 0;
  var checksum = 0;
  var queuePeakBytes = 0;
  var queueRejections = 0;

  void resetMeasurements() {
    _queuedBytes = 0;
    writeCount = 0;
    byteCount = 0;
    checksum = 0;
    queuePeakBytes = 0;
    queueRejections = 0;
  }

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() => _live
      ? TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: 1,
          owningProcessGroup: 1,
          foregroundProcessGroup: 1,
        )
      : TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => _live = true;
  @override
  String render() => '';
  @override
  void insertText(String value) {}
  @override
  void deleteBackward() {}
  @override
  void deleteForward() {}
  @override
  void moveLeft() {}
  @override
  void moveRight() {}
  @override
  void moveToStart() {}
  @override
  void moveToEnd() {}
  @override
  void previousHistory() {}
  @override
  void nextHistory() {}
  @override
  Future<void> submit() async {}
  @override
  void interrupt() {}
  @override
  void suspend() {}
  @override
  void quitForegroundProcess() {}
  @override
  void sendEndOfFile() {}
  @override
  void sendInput(Uint8List bytes) {
    if (_queuedBytes + bytes.length > queueCapacityBytes) {
      queueRejections++;
      throw StateError('bounded input benchmark queue rejected a key');
    }
    _queuedBytes += bytes.length;
    writeCount++;
    byteCount += bytes.length;
    for (final int byte in bytes) {
      checksum = ((checksum * 16777619) ^ byte) & 0x7fffffff;
    }
    if (_queuedBytes > queuePeakBytes) queuePeakBytes = _queuedBytes;
    if (writeCount % 64 == 0) _queuedBytes = 0;
  }

  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async =>
      const TerminalPasteTransferResult(
        disposition: TerminalPasteTransferDisposition.completed,
        encodedBytes: 0,
        completedChunks: 0,
        backpressureCount: 0,
        maximumQueuedBytes: 0,
        concurrentInputRejections: 0,
      );
  @override
  void resize({required int rows, required int columns}) {}
  @override
  void showClipboardNotice(TerminalClipboardNotice notice) {}
  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {}
  @override
  void showCloseConfirmation() {}
  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    _live = false;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

Map<String, Object?> _currentEnvironment() => <String, Object?>{
  'os': Platform.operatingSystem,
  'abi': Abi.current().toString(),
  'dart_sdk': Platform.version.split(' ').first,
  'build_mode': 'release-aot',
  'hardware_model': _sysctl('hw.model'),
  'memory_bytes': int.parse(_sysctl('hw.memsize')),
};

String _sysctl(String name) {
  final ProcessResult result = Process.runSync('/usr/sbin/sysctl', <String>[
    '-n',
    name,
  ]);
  if (result.exitCode != 0 || result.stdout is! String) {
    throw StateError('benchmark environment is unavailable');
  }
  final String value = (result.stdout! as String).trim();
  if (value.isEmpty || value.length > 128 || value.contains('\n')) {
    throw StateError('benchmark environment is malformed');
  }
  return value;
}

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
    throw StateError('benchmark baseline $name is incompatible');
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

double _percentile(List<double> sorted, int percentile) {
  final int index = ((sorted.length * percentile + 99) ~/ 100) - 1;
  return sorted[index < 0 ? 0 : index];
}

bool _compare(double observed, String operator, double threshold) =>
    switch (operator) {
      '>=' => observed >= threshold,
      '<' => observed < threshold,
      _ => false,
    };

bool _validToken(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9._+/-]+$').hasMatch(value);
