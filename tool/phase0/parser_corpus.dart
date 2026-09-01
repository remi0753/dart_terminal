import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'parser_probe.dart';

const String _defaultCorpus = 'test/corpus/parser/phase0.json';

final class _CorpusCase {
  const _CorpusCase({
    required this.id,
    required this.description,
    required this.bytes,
    required this.limits,
    required this.expected,
  });

  final String id;
  final String description;
  final Uint8List bytes;
  final ParserLimits limits;
  final List<String> expected;
}

final class _RunResult {
  const _RunResult(this.snapshot, this.hash);

  final List<String> snapshot;
  final int hash;
}

Uint8List _decodeHex(String source) {
  final String compact = source.replaceAll(RegExp(r'\s+'), '');
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
    throw FormatException('invalid corpus hex input');
  }
  final Uint8List result = Uint8List(compact.length ~/ 2);
  for (int index = 0; index < result.length; index++) {
    result[index] = int.parse(
      compact.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

ParserLimits _decodeLimits(Object? value) {
  if (value == null) {
    return const ParserLimits();
  }
  final Map<String, Object?> map = (value as Map<Object?, Object?>)
      .cast<String, Object?>();
  return ParserLimits(
    maxSequenceBytes: (map['max_sequence_bytes'] as int?) ?? 8192,
    maxStringBytes: (map['max_string_bytes'] as int?) ?? 4096,
    maxParameters: (map['max_parameters'] as int?) ?? 32,
    maxNumericValue: (map['max_numeric_value'] as int?) ?? 1000000,
  );
}

List<_CorpusCase> _loadCorpus(String path) {
  final Object? decoded = jsonDecode(File(path).readAsStringSync());
  final Map<String, Object?> root = (decoded! as Map<Object?, Object?>)
      .cast<String, Object?>();
  if (root['format'] != 'dart-terminal-parser-corpus' || root['version'] != 1) {
    throw FormatException('unsupported parser corpus format');
  }
  final List<Object?> entries = root['cases']! as List<Object?>;
  final Set<String> ids = <String>{};
  return entries
      .map((Object? entry) {
        final Map<String, Object?> map = (entry! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final String id = map['id']! as String;
        if (!ids.add(id)) {
          throw FormatException('duplicate corpus id $id');
        }
        final List<String> expected = (map['snapshot']! as List<Object?>)
            .cast<String>();
        return _CorpusCase(
          id: id,
          description: map['description']! as String,
          bytes: _decodeHex(map['input_hex']! as String),
          limits: _decodeLimits(map['limits']),
          expected: List<String>.unmodifiable(expected),
        );
      })
      .toList(growable: false);
}

_RunResult _runCase(_CorpusCase testCase, List<int> chunks) {
  final ParserActionRecorder recorder = ParserActionRecorder();
  final VtStreamProbe parser = VtStreamProbe(
    limits: testCase.limits,
    recorder: recorder,
  );
  int offset = 0;
  for (final int chunk in chunks) {
    if (chunk < 0 || offset + chunk > testCase.bytes.length) {
      throw StateError('${testCase.id}: invalid chunk plan');
    }
    parser.parse(testCase.bytes, offset, offset + chunk);
    offset += chunk;
  }
  if (offset != testCase.bytes.length) {
    throw StateError('${testCase.id}: chunk plan did not consume input');
  }
  parser.finish();
  if (!parser.isGround) {
    throw StateError('${testCase.id}: parser did not finish in ground');
  }
  return _RunResult(recorder.formatSnapshot(), parser.actionHash);
}

bool _sameSnapshot(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

Never _snapshotFailure(
  _CorpusCase testCase,
  String plan,
  List<String> expected,
  List<String> actual,
) {
  stderr.writeln('PARSER_SNAPSHOT_MISMATCH id=${testCase.id} plan=$plan');
  stderr.writeln('description=${testCase.description}');
  stderr.writeln('expected:');
  for (final String line in expected) {
    stderr.writeln('  $line');
  }
  stderr.writeln('actual:');
  for (final String line in actual) {
    stderr.writeln('  $line');
  }
  throw StateError('${testCase.id}: parser snapshot mismatch');
}

Uint8List _benchmarkSeed() {
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

Map<String, Object> _runThroughputBenchmark() {
  final Uint8List seed = _benchmarkSeed();
  final VtStreamProbe parser = VtStreamProbe();
  for (int warmup = 0; warmup < 16; warmup++) {
    parser.reset();
    parser.parse(seed);
    parser.finish();
  }
  const int targetBytes = 128 * 1024 * 1024;
  final int iterations = (targetBytes + seed.length - 1) ~/ seed.length;
  final int parsedBytes = seed.length * iterations;
  parser.reset();
  final Stopwatch clock = Stopwatch()..start();
  for (int iteration = 0; iteration < iterations; iteration++) {
    parser.parse(seed);
  }
  parser.finish();
  final int elapsedMicros = clock.elapsedMicroseconds;
  final double mibPerSecond =
      parsedBytes * 1000000 / elapsedMicros / (1024 * 1024);
  if (!parser.isGround ||
      parser.sequences == 0 ||
      parser.textScalars == 0 ||
      parser.actionHash == 0) {
    throw StateError('parser benchmark result was not consumed');
  }
  return <String, Object>{
    'seed_bytes': seed.length,
    'parsed_bytes': parsedBytes,
    'elapsed_us': elapsedMicros,
    'mib_s': mibPerSecond,
    'text_scalars': parser.textScalars,
    'controls': parser.controls,
    'sequences': parser.sequences,
    'hash': parser.actionHash,
  };
}

Future<void> main(List<String> arguments) async {
  bool printSnapshots = false;
  String corpusPath = _defaultCorpus;
  for (final String argument in arguments) {
    if (argument == '--print-snapshots') {
      printSnapshots = true;
    } else if (argument.startsWith('--corpus=')) {
      corpusPath = argument.substring('--corpus='.length);
    } else {
      throw FormatException('unknown argument: $argument');
    }
  }

  final List<_CorpusCase> corpus = _loadCorpus(corpusPath);
  int splitRuns = 0;
  int snapshotLines = 0;
  int aggregateHash = 0;
  for (final _CorpusCase testCase in corpus) {
    final _RunResult whole = _runCase(testCase, <int>[testCase.bytes.length]);
    if (printSnapshots) {
      stdout.writeln('SNAPSHOT ${testCase.id}');
      for (final String line in whole.snapshot) {
        stdout.writeln('  ${jsonEncode(line)},');
      }
      continue;
    }
    if (!_sameSnapshot(testCase.expected, whole.snapshot)) {
      _snapshotFailure(testCase, 'whole', testCase.expected, whole.snapshot);
    }
    snapshotLines += whole.snapshot.length;
    aggregateHash = (aggregateHash + whole.hash) & 0x7fffffff;
    for (int split = 0; split <= testCase.bytes.length; split++) {
      final _RunResult divided = _runCase(testCase, <int>[
        split,
        testCase.bytes.length - split,
      ]);
      splitRuns++;
      if (divided.hash != whole.hash ||
          !_sameSnapshot(divided.snapshot, whole.snapshot)) {
        _snapshotFailure(
          testCase,
          'split-$split',
          whole.snapshot,
          divided.snapshot,
        );
      }
    }
    final _RunResult bytewise = _runCase(
      testCase,
      List<int>.filled(testCase.bytes.length, 1),
    );
    splitRuns++;
    if (bytewise.hash != whole.hash ||
        !_sameSnapshot(bytewise.snapshot, whole.snapshot)) {
      _snapshotFailure(testCase, 'bytewise', whole.snapshot, bytewise.snapshot);
    }
  }
  if (printSnapshots) {
    return;
  }

  final Map<String, Object> benchmark = _runThroughputBenchmark();
  final double mibPerSecond = benchmark['mib_s']! as double;
  final bool passed = mibPerSecond >= 100 && corpus.isNotEmpty && splitRuns > 0;
  stdout.writeln(
    'PHASE0_PARSER_${passed ? 'PASS' : 'FAIL'} corpus_cases=${corpus.length} '
    'split_runs=$splitRuns snapshot_lines=$snapshotLines '
    'corpus_hash=$aggregateHash seed_bytes=${benchmark['seed_bytes']} '
    'parsed_bytes=${benchmark['parsed_bytes']} elapsed_us='
    '${benchmark['elapsed_us']} mib_s=${mibPerSecond.toStringAsFixed(2)} '
    'text_scalars=${benchmark['text_scalars']} controls='
    '${benchmark['controls']} sequences=${benchmark['sequences']} '
    'action_hash=${benchmark['hash']}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
