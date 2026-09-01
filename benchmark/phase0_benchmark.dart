import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../tool/phase0/input_probe.dart';
import '../tool/phase0/packed_grid.dart';
import '../tool/phase0/parser_probe.dart';

const int _rows = 200;
const int _columns = 500;
const int _cells = _rows * _columns;
const String _ghosttyReferenceCommit =
    'd4d8f62262cb1a974a7d2470d5f79f811fab15e4';
const String _ghosttyZigVersion = '0.16.0';
const String _ghosttyBuildCommand = 'zig build -Doptimize=ReleaseFast';
const String _ghosttyMacosConfiguration = 'ReleaseLocal';
const int _parserCorpusFormatVersion = 1;
const String _parserCorpusSha256 =
    '37414501d31cede8a3e39f70fceaae5ae2500e0be40ce5b10178e6e4ce2fb8be';
const String _parserWorkload = 'phase0-mixed-v1';
const int _inputProbeVersion = 1;
const int _measurementPolicyVersion = 1;

double _percentile(List<double> sorted, int percentile) {
  final int index = ((sorted.length * percentile + 99) ~/ 100) - 1;
  return sorted[index < 0 ? 0 : index];
}

Map<String, Object?> _metric({
  required String id,
  required String unit,
  required String direction,
  required List<double> samples,
  required String hardOperator,
  required double hardValue,
}) {
  final List<double> sorted = List<double>.of(samples)..sort();
  final double p50 = _percentile(sorted, 50);
  final double p95 = _percentile(sorted, 95);
  final double p99 = _percentile(sorted, 99);
  final double observed = direction == 'higher' ? sorted.first : p95;
  final bool hardPassed = switch (hardOperator) {
    '>=' => observed >= hardValue,
    '<' => observed < hardValue,
    '<=' => observed <= hardValue,
    _ => throw ArgumentError('unknown hard gate operator $hardOperator'),
  };
  return <String, Object?>{
    'id': id,
    'unit': unit,
    'direction': direction,
    'sample_count': sorted.length,
    'min': sorted.first,
    'p50': p50,
    'p95': p95,
    'p99': p99,
    'max': sorted.last,
    'hard_gate': <String, Object>{
      'stat': direction == 'higher' ? 'min' : 'p95',
      'operator': hardOperator,
      'value': hardValue,
      'passed': hardPassed,
    },
    'passed': hardPassed,
  };
}

Uint8List _parserSeed() {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Uint8List pattern = Uint8List.fromList(<int>[
    ...utf8.encode(r'prompt $ output-0123456789 abcdefghijklmnopqrstuvwxyz '),
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

Map<String, Object?> _benchmarkParser() {
  final Uint8List seed = _parserSeed();
  final VtStreamProbe parser = VtStreamProbe();
  for (int warmup = 0; warmup < 16; warmup++) {
    parser.reset();
    parser.parse(seed);
    parser.finish();
  }
  const int targetBytes = 32 * 1024 * 1024;
  final int iterations = (targetBytes + seed.length - 1) ~/ seed.length;
  final int bytesPerSample = seed.length * iterations;
  final List<double> throughput = <double>[];
  int stableHash = 0;
  for (int sample = 0; sample < 7; sample++) {
    parser.reset();
    final Stopwatch clock = Stopwatch()..start();
    for (int iteration = 0; iteration < iterations; iteration++) {
      parser.parse(seed);
    }
    parser.finish();
    final int elapsedMicros = clock.elapsedMicroseconds;
    throughput.add(bytesPerSample * 1000000 / elapsedMicros / (1024 * 1024));
    stableHash = sample == 0 ? parser.actionHash : stableHash;
    if (!parser.isGround ||
        parser.actionHash != stableHash ||
        parser.sequences == 0 ||
        parser.textScalars == 0) {
      throw StateError('parser benchmark integrity changed');
    }
  }
  return <String, Object?>{
    'metric': _metric(
      id: 'parser.mixed.throughput',
      unit: 'MiB/s',
      direction: 'higher',
      samples: throughput,
      hardOperator: '>=',
      hardValue: 100,
    ),
    'integrity': <String, Object>{
      'seed_bytes': seed.length,
      'bytes_per_sample': bytesPerSample,
      'action_hash': stableHash,
      'text_scalars_last_sample': parser.textScalars,
      'controls_last_sample': parser.controls,
      'sequences_last_sample': parser.sequences,
    },
  };
}

@pragma('vm:entry-point')
void _damageReceiver(SendPort rootPort) {
  final ReceivePort messages = ReceivePort('phase0-benchmark-render-receiver');
  rootPort.send(messages.sendPort);
  messages.listen((Object? message) {
    if (message == 'stop') {
      rootPort.send('stopped');
      messages.close();
      return;
    }
    final List<Object?> envelope = message! as List<Object?>;
    final int sequence = envelope[0]! as int;
    final TransferableTypedData transfer =
        envelope[1]! as TransferableTypedData;
    final Uint8List bytes = transfer.materialize().asUint8List();
    final DamagePacketView view = DamagePacketView(bytes);
    rootPort.send(<Object?>[
      sequence,
      bytes.length,
      view.generation,
      view.sampleChecksum(),
    ]);
  });
}

Future<Map<String, Object?>> _benchmarkRender() async {
  final PackedGrid grid = PackedGrid(rows: _rows, columns: _columns)
    ..fillDeterministic(31);
  grid.packDamage(generation: 1, resourceGeneration: 1, fullSnapshot: true);
  for (int warmup = 0; warmup < 8; warmup++) {
    grid.markAllDirty();
    grid.packDamage(
      generation: 100 + warmup,
      resourceGeneration: 1,
      fullSnapshot: true,
    );
  }

  final List<double> fullMicros = <double>[];
  Uint8List? fullPacket;
  int checksum = 0;
  for (int sample = 0; sample < 64; sample++) {
    grid.markAllDirty();
    final Stopwatch clock = Stopwatch()..start();
    final Uint8List packet = grid.packDamage(
      generation: 1000 + sample,
      resourceGeneration: 2,
      fullSnapshot: true,
    );
    fullMicros.add(clock.elapsedMicroseconds.toDouble());
    final DamagePacketView view = DamagePacketView(packet);
    checksum = (checksum + view.sampleChecksum()) & 0x7fffffff;
    fullPacket = packet;
  }

  final List<double> sparseMicros = <double>[];
  int sparseBytes = 0;
  for (int sample = 0; sample < 256; sample++) {
    final Stopwatch clock = Stopwatch()..start();
    grid.updateSpans(seed: sample + 1, damagedRows: 32, span: 128);
    final Uint8List packet = grid.packDamage(
      generation: 2000 + sample,
      resourceGeneration: 2,
    );
    sparseMicros.add(clock.elapsedMicroseconds.toDouble());
    sparseBytes += packet.length;
    checksum =
        (checksum + DamagePacketView(packet).sampleChecksum()) & 0x7fffffff;
  }

  final Uint8List transferPacket = Uint8List.fromList(fullPacket!);
  ByteData.sublistView(transferPacket).setUint64(8, 9001, Endian.little);
  final ReceivePort replies = ReceivePort('phase0-benchmark-render-root');
  final StreamIterator<Object?> iterator = StreamIterator<Object?>(replies);
  final Isolate receiver = await Isolate.spawn<SendPort>(
    _damageReceiver,
    replies.sendPort,
    errorsAreFatal: true,
    debugName: 'phase0-benchmark-render-receiver',
  );
  if (!await iterator.moveNext()) {
    throw StateError('render transfer receiver did not start');
  }
  final SendPort receiverPort = iterator.current! as SendPort;
  final List<double> transferMicros = <double>[];
  int transferChecksum = 0;
  for (int sequence = 0; sequence < 64; sequence++) {
    final Stopwatch clock = Stopwatch()..start();
    receiverPort.send(<Object?>[
      sequence,
      TransferableTypedData.fromList(<Uint8List>[transferPacket]),
    ]);
    if (!await iterator.moveNext()) {
      throw StateError('render transfer stopped at $sequence');
    }
    final List<Object?> acknowledgement = iterator.current! as List<Object?>;
    if (acknowledgement[0] != sequence ||
        acknowledgement[1] != transferPacket.length ||
        acknowledgement[2] != 9001) {
      throw StateError('render transfer acknowledgement mismatch');
    }
    transferChecksum =
        (transferChecksum + (acknowledgement[3]! as int)) & 0x7fffffff;
    transferMicros.add(clock.elapsedMicroseconds.toDouble());
  }
  receiverPort.send('stop');
  if (!await iterator.moveNext() || iterator.current != 'stopped') {
    throw StateError('render transfer receiver did not stop');
  }
  await iterator.cancel();
  replies.close();
  receiver.kill(priority: Isolate.immediate);
  if (checksum == 0 || transferChecksum == 0) {
    throw StateError('render benchmark checksum was not consumed');
  }

  return <String, Object?>{
    'metrics': <Object?>[
      _metric(
        id: 'render.damage.full_pack_latency',
        unit: 'us',
        direction: 'lower',
        samples: fullMicros,
        hardOperator: '<',
        hardValue: 4000,
      ),
      _metric(
        id: 'render.damage.sparse_pack_latency',
        unit: 'us',
        direction: 'lower',
        samples: sparseMicros,
        hardOperator: '<',
        hardValue: 1000,
      ),
      _metric(
        id: 'render.damage.transfer_latency',
        unit: 'us',
        direction: 'lower',
        samples: transferMicros,
        hardOperator: '<',
        hardValue: 4000,
      ),
    ],
    'integrity': <String, Object>{
      'rows': _rows,
      'columns': _columns,
      'cells': _cells,
      'typed_grid_bytes': grid.typedStorageBytes,
      'full_packet_bytes': transferPacket.length,
      'average_sparse_packet_bytes': sparseBytes / 256,
      'damage_checksum': checksum,
      'transfer_checksum': transferChecksum,
    },
  };
}

void _expectBytes(
  InputEncoderProbe encoder,
  List<int> expected, {
  required int key,
  int scalar = 0,
  int modifiers = 0,
  int modes = 0,
}) {
  final int length = encoder.encode(
    key: key,
    scalar: scalar,
    modifiers: modifiers,
    modes: modes,
  );
  if (length != expected.length) {
    throw StateError('input fixture length mismatch');
  }
  for (int index = 0; index < length; index++) {
    if (encoder.bytes[index] != expected[index]) {
      throw StateError('input fixture byte mismatch at $index');
    }
  }
}

void _verifyBoundedQueue() {
  final BoundedByteQueueProbe queue = BoundedByteQueueProbe(8);
  final Uint8List first = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
  final Uint8List second = Uint8List.fromList(<int>[7, 8, 9, 10, 11, 12]);
  final Uint8List output = Uint8List(8);
  if (!queue.enqueue(first, first.length) ||
      queue.drainInto(output, 4) != 4 ||
      output[0] != 1 ||
      output[1] != 2 ||
      output[2] != 3 ||
      output[3] != 4 ||
      !queue.enqueue(second, second.length) ||
      queue.length != 8 ||
      queue.enqueue(first, 1) ||
      queue.drainInto(output, output.length) != 8 ||
      queue.length != 0) {
    throw StateError('bounded input queue fixture failed');
  }
  for (int index = 0; index < 8; index++) {
    if (output[index] != index + 5) {
      throw StateError('bounded input queue order mismatch at $index');
    }
  }
}

Map<String, Object?> _benchmarkInput() {
  final InputEncoderProbe encoder = InputEncoderProbe();
  _expectBytes(encoder, <int>[0x61], key: inputKeyText, scalar: 0x61);
  _expectBytes(
    encoder,
    <int>[0x03],
    key: inputKeyText,
    scalar: 0x43,
    modifiers: inputModifierControl,
  );
  _expectBytes(
    encoder,
    <int>[0x1b, 0x78],
    key: inputKeyText,
    scalar: 0x78,
    modifiers: inputModifierAlt,
  );
  _expectBytes(
    encoder,
    <int>[0xe6, 0x97, 0xa5],
    key: inputKeyText,
    scalar: 0x65e5,
  );
  _expectBytes(encoder, <int>[0x1b, 0x5b, 0x41], key: inputKeyUp);
  _expectBytes(
    encoder,
    <int>[0x1b, 0x4f, 0x41],
    key: inputKeyUp,
    modes: inputModeApplicationCursor,
  );
  _expectBytes(
    encoder,
    <int>[0x1b, 0x5b, 0x31, 0x3b, 0x36, 0x43],
    key: inputKeyRight,
    modifiers: inputModifierShift | inputModifierControl,
  );
  _verifyBoundedQueue();

  final BoundedByteQueueProbe queue = BoundedByteQueueProbe(64 * 1024);
  for (int warmup = 0; warmup < 10000; warmup++) {
    final int length = encoder.encode(
      key: warmup % 5 == 0 ? inputKeyUp : inputKeyText,
      scalar: 0x61 + (warmup % 26),
      modifiers: warmup % 17 == 0 ? inputModifierAlt : 0,
      modes: warmup.isEven ? inputModeApplicationCursor : 0,
    );
    if (!queue.enqueue(encoder.bytes, length)) {
      throw StateError('input warmup queue overflow');
    }
    if (warmup % 64 == 63) {
      queue.drain(queue.length);
    }
  }
  queue.drain(queue.length);

  const int sampleCount = 100000;
  final List<double> latencyNanoseconds = List<double>.filled(sampleCount, 0);
  final Stopwatch clock = Stopwatch()..start();
  int checksum = 0;
  int rejected = 0;
  for (int sample = 0; sample < sampleCount; sample++) {
    final int before = clock.elapsedTicks;
    final int selector = sample % 8;
    final int length = encoder.encode(
      key: selector < 5 ? inputKeyText : inputKeyUp + (selector - 5),
      scalar: 0x61 + (sample % 26),
      modifiers: sample % 31 == 0
          ? inputModifierControl
          : (sample % 17 == 0 ? inputModifierAlt : 0),
      modes: sample.isEven ? inputModeApplicationCursor : 0,
    );
    if (!queue.enqueue(encoder.bytes, length)) {
      rejected++;
    }
    final int after = clock.elapsedTicks;
    latencyNanoseconds[sample] =
        (after - before) * 1000000000 / clock.frequency;
    checksum = (checksum + length + encoder.bytes[0]) & 0x7fffffff;
    if (sample % 64 == 63) {
      queue.drain(queue.length);
    }
  }
  queue.drain(queue.length);
  if (rejected != 0 || checksum == 0 || queue.length != 0) {
    throw StateError('input queue benchmark integrity failed');
  }
  return <String, Object?>{
    'metric': _metric(
      id: 'input.key_to_queue_latency',
      unit: 'ns',
      direction: 'lower',
      samples: latencyNanoseconds,
      hardOperator: '<',
      hardValue: 2000000,
    ),
    'integrity': <String, Object>{
      'key_encoding_fixtures': 7,
      'bounded_queue_fixtures': 1,
      'events': sampleCount,
      'queue_capacity_bytes': queue.capacity,
      'queue_max_bytes': queue.maxLength,
      'queue_rejections': rejected,
      'checksum': checksum,
    },
  };
}

Map<String, Object?> _loadBaseline(String path) {
  final Object? decoded = jsonDecode(File(path).readAsStringSync());
  final Map<String, Object?> baseline = (decoded! as Map<Object?, Object?>)
      .cast<String, Object?>();
  if (baseline['format'] != 'dart-terminal-benchmark-baseline' ||
      baseline['version'] != 1) {
    throw FormatException('unsupported benchmark baseline');
  }
  return baseline;
}

bool _applyBaseline(
  List<Map<String, Object?>> metrics,
  Map<String, Object?> baseline,
  Map<String, Object> currentEnvironment,
  Map<String, Object> currentProvenance,
) {
  final Map<String, Object?> environment =
      (baseline['environment']! as Map<Object?, Object?>)
          .cast<String, Object?>();
  for (final String key in <String>['os', 'abi', 'dart_sdk', 'build_mode']) {
    if (environment[key] != currentEnvironment[key]) {
      throw StateError(
        'benchmark baseline environment mismatch for $key: '
        '${environment[key]} != ${currentEnvironment[key]}',
      );
    }
  }
  final Map<String, Object?> provenance =
      (baseline['provenance']! as Map<Object?, Object?>)
          .cast<String, Object?>();
  for (final MapEntry<String, Object> entry in currentProvenance.entries) {
    if (provenance[entry.key] != entry.value) {
      throw StateError(
        'benchmark baseline provenance mismatch for ${entry.key}: '
        '${provenance[entry.key]} != ${entry.value}',
      );
    }
  }
  final Map<String, Object?> specifications =
      (baseline['metrics']! as Map<Object?, Object?>).cast<String, Object?>();
  bool passed = true;
  for (final Map<String, Object?> metric in metrics) {
    final String id = metric['id']! as String;
    final Object? rawSpecification = specifications[id];
    if (rawSpecification == null) {
      throw FormatException('baseline is missing metric $id');
    }
    final Map<String, Object?> specification =
        (rawSpecification as Map<Object?, Object?>).cast<String, Object?>();
    final String stat = specification['stat']! as String;
    final double reference = (specification['reference']! as num).toDouble();
    final double relativeTolerance =
        (specification['relative_tolerance']! as num).toDouble();
    final double absoluteSlack = (specification['absolute_slack']! as num)
        .toDouble();
    final double observed = (metric[stat]! as num).toDouble();
    final String direction = metric['direction']! as String;
    final double threshold = direction == 'higher'
        ? reference * (1 - relativeTolerance) - absoluteSlack
        : reference * (1 + relativeTolerance) + absoluteSlack;
    final bool baselinePassed = direction == 'higher'
        ? observed >= threshold
        : observed <= threshold;
    metric['baseline_gate'] = <String, Object>{
      'stat': stat,
      'reference': reference,
      'relative_tolerance': relativeTolerance,
      'absolute_slack': absoluteSlack,
      'threshold': threshold,
      'passed': baselinePassed,
    };
    final bool metricPassed = (metric['passed']! as bool) && baselinePassed;
    metric['passed'] = metricPassed;
    passed = passed && metricPassed;
  }
  if (specifications.length != metrics.length) {
    throw FormatException('baseline has unknown or duplicate metric entries');
  }
  return passed;
}

Future<void> main(List<String> arguments) async {
  String? baselinePath;
  for (final String argument in arguments) {
    if (argument.startsWith('--baseline=')) {
      baselinePath = argument.substring('--baseline='.length);
    } else {
      throw FormatException('unknown benchmark argument $argument');
    }
  }

  final Stopwatch suiteClock = Stopwatch()..start();
  final Map<String, Object?> parser = _benchmarkParser();
  final Map<String, Object?> render = await _benchmarkRender();
  final Map<String, Object?> input = _benchmarkInput();
  final List<Map<String, Object?>> metrics = <Map<String, Object?>>[
    parser['metric']! as Map<String, Object?>,
    ...(render['metrics']! as List<Object?>).cast<Map<String, Object?>>(),
    input['metric']! as Map<String, Object?>,
  ];
  bool passed = metrics.every(
    (Map<String, Object?> metric) => metric['passed']! as bool,
  );
  final Map<String, Object> environment = <String, Object>{
    'os': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'abi': Abi.current().toString(),
    'dart_sdk': Platform.version.split(' ').first,
    'build_mode': 'release-aot',
  };
  final Map<String, Object> provenance = <String, Object>{
    'ghostty_reference_commit': _ghosttyReferenceCommit,
    'ghostty_zig_version': _ghosttyZigVersion,
    'ghostty_build_command': _ghosttyBuildCommand,
    'ghostty_macos_configuration': _ghosttyMacosConfiguration,
    'parser_corpus_format_version': _parserCorpusFormatVersion,
    'parser_corpus_sha256': _parserCorpusSha256,
    'parser_workload': _parserWorkload,
    'damage_packet_version': damageVersion,
    'input_probe_version': _inputProbeVersion,
    'measurement_policy_version': _measurementPolicyVersion,
  };
  String? baselineId;
  if (baselinePath != null) {
    final Map<String, Object?> baseline = _loadBaseline(baselinePath);
    baselineId = baseline['id']! as String;
    passed =
        _applyBaseline(metrics, baseline, environment, provenance) && passed;
  }

  final Map<String, Object?> result = <String, Object?>{
    'format': 'dart-terminal-benchmark-result',
    'version': 1,
    'suite': 'phase0',
    'status': passed ? 'pass' : 'fail',
    'baseline_id': baselineId,
    'environment': environment,
    'provenance': provenance,
    'measurement_policy': <String, Object>{
      'version': _measurementPolicyVersion,
      'clock': 'dart-stopwatch-monotonic',
      'percentiles': <int>[50, 95, 99],
      'warmup_required': true,
      'stdout': 'single-json-document',
      'lower_latency_is_better': true,
    },
    'metrics': metrics,
    'integrity': <String, Object?>{
      'parser': parser['integrity'],
      'render': render['integrity'],
      'input': input['integrity'],
      'suite_elapsed_us': suiteClock.elapsedMicroseconds,
      'rss_bytes': ProcessInfo.currentRss,
    },
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  stderr.writeln(
    'PHASE0_BENCHMARK_${passed ? 'PASS' : 'FAIL'} '
    'metrics=${metrics.length} baseline=${baselineId ?? 'none'}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
