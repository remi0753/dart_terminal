import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const String _defaultFuzzSeedPath = 'test/corpus/fuzz/product_v1.json';
const int _propertySeed = 0x4d595df4;
const int _generatedCaseCount = 96;
const int _mutationsPerSeed = 16;
const VtParserLimits _parserLimits = VtParserLimits(
  maxSequenceBytes: 64,
  maxStringBytes: 32,
  maxParameters: 8,
  maxIntermediates: 2,
  maxNumericValue: 9999,
);
const TerminalSnapshotFormatter _formatter = TerminalSnapshotFormatter(
  limits: TerminalSnapshotFormatLimits(
    maxRows: 64,
    maxCells: 4096,
    maxStyleDefinitions: 256,
    maxGraphemeDefinitions: 64,
    maxOutputCharacters: 512 * 1024,
  ),
);

void main() {
  final TerminalPropertyFuzzResult result = runTerminalPropertyFuzzTests();
  stdout.writeln(result.machineLine());
}

final class TerminalPropertyFuzzResult {
  const TerminalPropertyFuzzResult({
    required this.generatedCases,
    required this.seedCases,
    required this.mutationCases,
    required this.executions,
    required this.parsedBytes,
    required this.stateHash,
  });

  final int generatedCases;
  final int seedCases;
  final int mutationCases;
  final int executions;
  final int parsedBytes;
  final int stateHash;

  String machineLine() =>
      'TERMINAL_PROPERTY_FUZZ_PASS seed=0x${_propertySeed.toRadixString(16)} '
      'generated=$generatedCases seeds=$seedCases mutations=$mutationCases '
      'executions=$executions parsed_bytes=$parsedBytes state_hash=$stateHash';
}

TerminalPropertyFuzzResult runTerminalPropertyFuzzTests({
  String seedPath = _defaultFuzzSeedPath,
}) {
  _testSeedManifestValidation();
  final List<_FuzzSeed> seeds = const _FuzzSeedLoader().load(seedPath);
  final _RunAccumulator accumulator = _RunAccumulator();
  _runGeneratedProperties(accumulator);
  _runReviewedSeeds(seeds, accumulator);
  final TerminalPropertyFuzzResult result = TerminalPropertyFuzzResult(
    generatedCases: _generatedCaseCount,
    seedCases: seeds.length,
    mutationCases: seeds.length * _mutationsPerSeed,
    executions: accumulator.executions,
    parsedBytes: accumulator.parsedBytes,
    stateHash: accumulator.stateHash,
  );
  _expect(
    result.executions == 837,
    'property/fuzz execution budget remains fixed',
  );
  _expect(
    result.machineLine() ==
        'TERMINAL_PROPERTY_FUZZ_PASS seed=0x4d595df4 generated=96 seeds=7 '
            'mutations=112 executions=837 parsed_bytes=66675 '
            'state_hash=1721827890',
    'property/fuzz result is deterministic: ${result.machineLine()}',
  );
  return result;
}

void _runGeneratedProperties(_RunAccumulator accumulator) {
  for (var caseIndex = 0; caseIndex < _generatedCaseCount; caseIndex++) {
    final int caseSeed = _caseSeed(_propertySeed, caseIndex);
    final _XorShift32 random = _XorShift32(caseSeed);
    final Uint8List input = _generatedInput(random);
    final int initialRows = 2 + random.nextInt(7);
    final int initialColumns = 4 + random.nextInt(17);
    final List<_ResizeEvent> resizes = _generatedResizes(input.length, random);
    final List<int> chunks = _generatedChunks(input.length, random);
    final String context =
        'seed=0x${caseSeed.toRadixString(16)} case=$caseIndex';
    try {
      final _RunDigest whole = _run(
        input,
        initialRows: initialRows,
        initialColumns: initialColumns,
        resizes: resizes,
        chunks: <int>[input.length],
        accumulator: accumulator,
      );
      final _RunDigest generated = _run(
        input,
        initialRows: initialRows,
        initialColumns: initialColumns,
        resizes: resizes,
        chunks: chunks,
        accumulator: accumulator,
      );
      final _RunDigest bytewise = _run(
        input,
        initialRows: initialRows,
        initialColumns: initialColumns,
        resizes: resizes,
        chunks: List<int>.filled(input.length, 1),
        accumulator: accumulator,
      );
      final _RunDigest repeated = _run(
        input,
        initialRows: initialRows,
        initialColumns: initialColumns,
        resizes: resizes,
        chunks: chunks,
        accumulator: accumulator,
      );
      _expectEquivalent(whole, generated, '$context plan=generated');
      _expectEquivalent(whole, bytewise, '$context plan=bytewise');
      _expectEquivalent(generated, repeated, '$context plan=repeat');
      _expectRecovery(input, context, accumulator);
    } on Object catch (error) {
      if (error.toString().contains('PROPERTY_FAILURE')) {
        rethrow;
      }
      throw StateError('PROPERTY_FAILURE $context execution: $error');
    }
  }
}

void _runReviewedSeeds(List<_FuzzSeed> seeds, _RunAccumulator accumulator) {
  for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
    final _FuzzSeed seed = seeds[seedIndex];
    final _XorShift32 random = _XorShift32(
      _caseSeed(_propertySeed ^ 0xa5a5a5a5, seedIndex),
    );
    _compareReviewedPlans(
      seed.input,
      seed.resizes,
      random,
      'reviewed=${seed.id}',
      accumulator,
    );
    for (var mutation = 0; mutation < _mutationsPerSeed; mutation++) {
      final Uint8List changed = Uint8List.fromList(seed.input);
      final int offset = random.nextInt(changed.length);
      changed[offset] ^= 1 << random.nextInt(8);
      _compareReviewedPlans(
        changed,
        seed.resizes,
        random,
        'reviewed=${seed.id} mutation=$mutation offset=$offset',
        accumulator,
      );
    }
  }
}

void _compareReviewedPlans(
  Uint8List input,
  List<_ResizeEvent> resizes,
  _XorShift32 random,
  String context,
  _RunAccumulator accumulator,
) {
  try {
    _comparePlans(input, resizes, random, context, accumulator);
  } on Object catch (error) {
    if (error.toString().contains('PROPERTY_FAILURE')) {
      rethrow;
    }
    throw StateError('PROPERTY_FAILURE $context execution: $error');
  }
}

void _comparePlans(
  Uint8List input,
  List<_ResizeEvent> resizes,
  _XorShift32 random,
  String context,
  _RunAccumulator accumulator,
) {
  final _RunDigest whole = _run(
    input,
    initialRows: 4,
    initialColumns: 12,
    resizes: resizes,
    chunks: <int>[input.length],
    accumulator: accumulator,
  );
  final _RunDigest generated = _run(
    input,
    initialRows: 4,
    initialColumns: 12,
    resizes: resizes,
    chunks: _generatedChunks(input.length, random),
    accumulator: accumulator,
  );
  final _RunDigest bytewise = _run(
    input,
    initialRows: 4,
    initialColumns: 12,
    resizes: resizes,
    chunks: List<int>.filled(input.length, 1),
    accumulator: accumulator,
  );
  _expectEquivalent(whole, generated, '$context plan=generated');
  _expectEquivalent(whole, bytewise, '$context plan=bytewise');
}

void _expectRecovery(
  Uint8List arbitrary,
  String context,
  _RunAccumulator accumulator,
) {
  final BytesBuilder builder = BytesBuilder(copy: false)
    ..add(arbitrary)
    ..add(const <int>[0x18, 0x1b, 0x63])
    ..add(ascii.encode('RECOVER'));
  final Uint8List recovery = builder.takeBytes();
  final _RunDigest digest = _run(
    recovery,
    initialRows: 4,
    initialColumns: 20,
    resizes: const <_ResizeEvent>[],
    chunks: List<int>.filled(recovery.length, 1),
    accumulator: accumulator,
  );
  _expect(
    digest.recoveryVisible,
    'PROPERTY_FAILURE $context recovery sentinel is not visible after CAN/RIS',
  );
}

_RunDigest _run(
  Uint8List input, {
  required int initialRows,
  required int initialColumns,
  required List<_ResizeEvent> resizes,
  required List<int> chunks,
  required _RunAccumulator accumulator,
}) {
  final TerminalStyleTable styles = TerminalStyleTable(capacity: 256);
  final TerminalGraphemeTable graphemes = TerminalGraphemeTable(
    capacity: 64,
    maximumScalarCount: 512,
    maximumClusterLength: 16,
  );
  final TerminalScrollback scrollback = TerminalScrollback(
    maxLines: 8,
    maxBytes: 32 * 1024,
    pageRows: 4,
  );
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: initialRows,
    columns: initialColumns,
    styleTable: styles,
    graphemeTable: graphemes,
    scrollback: scrollback,
  );
  var replyHash = 0x811c9dc5;
  var replyCount = 0;
  var maximumReplyBytes = 0;
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List reply) {
      _expect(
        reply.isNotEmpty &&
            reply.length <= TerminalReplyEncoder.maximumReplyBytes,
        'generated reply remains within the hard byte cap',
      );
      replyCount++;
      if (reply.length > maximumReplyBytes) {
        maximumReplyBytes = reply.length;
      }
      replyHash = _hashBytes(replyHash, reply);
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink, limits: _parserLimits);
  _feedWithResizes(parser, screens, input, chunks, resizes);
  parser.finish();
  _expect(parser.isGround, 'parser finishes in ground state');
  screens.primary.validateCellTopology();
  screens.alternate.validateCellTopology();
  scrollback.validateCellTopology();
  _expect(scrollback.length <= scrollback.maxLines, 'scrollback line cap');
  _expect(
    scrollback.allocatedBytes <= scrollback.maxBytes,
    'scrollback byte cap',
  );
  _expect(styles.definitionCount <= styles.capacity, 'style definition cap');
  _expect(
    graphemes.definitionCount <= graphemes.capacity &&
        graphemes.scalarCount <= graphemes.maximumScalarCount,
    'grapheme definition and scalar caps',
  );
  final String snapshot = _formatter.formatScreenSet(screens, parserSink: sink);
  final _RunDigest digest = _RunDigest(
    snapshot: snapshot,
    replyHash: replyHash,
    replyCount: replyCount,
    maximumReplyBytes: maximumReplyBytes,
    recoveryVisible: _rowStartsWith(screens.primary, 'RECOVER'),
  );
  accumulator.add(digest, input.length);
  return digest;
}

void _feedWithResizes(
  VtParser parser,
  TerminalScreenSet screens,
  Uint8List input,
  List<int> chunks,
  List<_ResizeEvent> resizes,
) {
  var offset = 0;
  var resizeIndex = 0;
  void applyResizes() {
    while (resizeIndex < resizes.length &&
        resizes[resizeIndex].offset == offset) {
      final _ResizeEvent resize = resizes[resizeIndex++];
      try {
        screens.resize(rows: resize.rows, columns: resize.columns);
      } on Object catch (error) {
        throw StateError(
          'resize at byte $offset to ${resize.rows}x${resize.columns}: $error',
        );
      }
    }
  }

  for (final int chunk in chunks) {
    if (chunk < 0 || offset + chunk > input.length) {
      throw StateError('invalid property chunk plan at $offset+$chunk');
    }
    final int target = offset + chunk;
    applyResizes();
    while (resizeIndex < resizes.length &&
        resizes[resizeIndex].offset < target) {
      final int boundary = resizes[resizeIndex].offset;
      parser.parse(input, offset, boundary);
      offset = boundary;
      applyResizes();
    }
    parser.parse(input, offset, target);
    offset = target;
    applyResizes();
  }
  if (offset != input.length || resizeIndex != resizes.length) {
    throw StateError(
      'property plan consumed $offset/${input.length} bytes and '
      '$resizeIndex/${resizes.length} resizes',
    );
  }
}

void _expectEquivalent(_RunDigest expected, _RunDigest actual, String context) {
  final TerminalSnapshotComparison comparison =
      const TerminalSnapshotComparator().compare(
        expected.snapshot,
        actual.snapshot,
      );
  if (!comparison.matches) {
    throw StateError('PROPERTY_FAILURE $context\n${comparison.diagnostic}');
  }
  _expect(
    expected.replyHash == actual.replyHash &&
        expected.replyCount == actual.replyCount &&
        expected.maximumReplyBytes == actual.maximumReplyBytes,
    'PROPERTY_FAILURE $context reply digest differs',
  );
}

bool _rowStartsWith(TerminalScreen screen, String value) {
  if (screen.rows == 0 || screen.columns < value.length) {
    return false;
  }
  for (var column = 0; column < value.length; column++) {
    if (screen.contentAt(0, column) != value.codeUnitAt(column)) {
      return false;
    }
  }
  return true;
}

Uint8List _generatedInput(_XorShift32 random) {
  final int targetLength = 1 + random.nextInt(192);
  final BytesBuilder builder = BytesBuilder(copy: false);
  while (builder.length < targetLength) {
    final int choice = random.nextInt(100);
    if (choice < 42) {
      builder.addByte(0x20 + random.nextInt(0x5f));
    } else if (choice < 54) {
      builder.addByte(
        const <int>[0x00, 0x08, 0x09, 0x0a, 0x0d, 0x18, 0x1a, 0x1b][random
            .nextInt(8)],
      );
    } else if (choice < 65) {
      builder.addByte(random.nextInt(256));
    } else {
      final List<int> fragment =
          _structuredFragments[random.nextInt(_structuredFragments.length)];
      builder.add(fragment);
    }
  }
  final Uint8List bytes = builder.takeBytes();
  return Uint8List.sublistView(bytes, 0, targetLength);
}

const List<List<int>> _structuredFragments = <List<int>>[
  <int>[0xe6, 0x97, 0xa5],
  <int>[0xf0, 0x9f, 0x98, 0x80],
  <int>[0x65, 0xcc, 0x81],
  <int>[0xf0, 0x28, 0x8c, 0x28],
  <int>[0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x34, 0x6d],
  <int>[0x1b, 0x5b, 0x32, 0x3b, 0x35, 0x48],
  <int>[0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68],
  <int>[0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c],
  <int>[0x1b, 0x5b, 0x36, 0x6e],
  <int>[0x1b, 0x5d, 0x34, 0x3b, 0x31, 0x3b, 0x3f, 0x07],
  <int>[0x1b, 0x5d, 0x31, 0x30, 0x3b, 0x3f, 0x1b, 0x5c],
  <int>[0x1b, 0x50, 0x31, 0x3b, 0x32, 0x71, 0x78, 0x1b, 0x5c],
];

List<_ResizeEvent> _generatedResizes(int inputLength, _XorShift32 random) {
  final int count = random.nextInt(3);
  final Set<int> offsets = <int>{};
  while (offsets.length < count) {
    offsets.add(random.nextInt(inputLength + 1));
  }
  final List<int> ordered = offsets.toList()..sort();
  return <_ResizeEvent>[
    for (final int offset in ordered)
      _ResizeEvent(
        offset: offset,
        rows: 2 + random.nextInt(7),
        columns: 4 + random.nextInt(21),
      ),
  ];
}

List<int> _generatedChunks(int inputLength, _XorShift32 random) {
  final List<int> chunks = <int>[if (random.nextInt(2) == 0) 0];
  var remaining = inputLength;
  while (remaining > 0) {
    final int length = 1 + random.nextInt(remaining < 17 ? remaining : 17);
    chunks.add(length);
    remaining -= length;
    if (random.nextInt(8) == 0) {
      chunks.add(0);
    }
  }
  if (random.nextInt(2) == 0) {
    chunks.add(0);
  }
  return chunks;
}

final class _RunDigest {
  const _RunDigest({
    required this.snapshot,
    required this.replyHash,
    required this.replyCount,
    required this.maximumReplyBytes,
    required this.recoveryVisible,
  });

  final String snapshot;
  final int replyHash;
  final int replyCount;
  final int maximumReplyBytes;
  final bool recoveryVisible;
}

final class _RunAccumulator {
  int executions = 0;
  int parsedBytes = 0;
  int stateHash = 0x811c9dc5;

  void add(_RunDigest digest, int inputBytes) {
    executions++;
    parsedBytes += inputBytes;
    stateHash = _hashString(stateHash, digest.snapshot);
    stateHash = _hashInteger(stateHash, digest.replyHash);
    stateHash = _hashInteger(stateHash, digest.replyCount);
    stateHash = _hashInteger(stateHash, digest.maximumReplyBytes);
  }
}

final class _ResizeEvent {
  const _ResizeEvent({
    required this.offset,
    required this.rows,
    required this.columns,
  });

  final int offset;
  final int rows;
  final int columns;
}

final class _FuzzSeed {
  const _FuzzSeed({
    required this.id,
    required this.description,
    required this.input,
    required this.resizes,
  });

  final String id;
  final String description;
  final Uint8List input;
  final List<_ResizeEvent> resizes;
}

final class _FuzzSeedLoader {
  const _FuzzSeedLoader();

  List<_FuzzSeed> load(String path) {
    final File file = File(path);
    _expect(file.existsSync(), 'fuzz seed manifest exists');
    _expect(
      file.lengthSync() > 0 && file.lengthSync() <= 256 * 1024,
      'fuzz seed manifest size is bounded',
    );
    final Map<String, Object?> root = _map(
      jsonDecode(file.readAsStringSync()),
      'root',
    );
    _keys(root, const <String>{'format', 'version', 'seeds'}, 'root');
    _expect(
      root['format'] == 'dart-terminal-product-fuzz-seeds' &&
          root['version'] == 1,
      'supported fuzz seed format and version',
    );
    final List<Object?> entries = _list(root['seeds'], 'seeds');
    _expect(entries.isNotEmpty && entries.length <= 32, '1..32 fuzz seeds');
    final Set<String> ids = <String>{};
    final List<_FuzzSeed> seeds = <_FuzzSeed>[];
    var aggregateBytes = 0;
    for (var index = 0; index < entries.length; index++) {
      final Map<String, Object?> entry = _map(entries[index], 'seeds[$index]');
      _keys(entry, const <String>{
        'id',
        'description',
        'input_hex',
        'resizes',
      }, 'seed');
      final String id = _string(entry['id'], 'id');
      _expect(
        RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id),
        'valid seed id',
      );
      _expect(ids.add(id), 'unique seed id');
      final String description = _string(entry['description'], 'description');
      _expect(
        description.isNotEmpty &&
            description.length <= 256 &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(description),
        'bounded control-free seed description',
      );
      final Uint8List input = _hex(_string(entry['input_hex'], 'input_hex'));
      aggregateBytes += input.length;
      _expect(aggregateBytes <= 16 * 1024, 'aggregate seed bytes <= 16384');
      final List<Object?> resizeEntries = _list(entry['resizes'], 'resizes');
      _expect(resizeEntries.length <= 8, 'at most 8 seed resizes');
      final List<_ResizeEvent> resizes = <_ResizeEvent>[];
      var previousOffset = -1;
      for (final Object? value in resizeEntries) {
        final Map<String, Object?> resize = _map(value, 'resize');
        _keys(resize, const <String>{'offset', 'rows', 'columns'}, 'resize');
        final int offset = _integer(resize['offset'], 'resize.offset');
        final int rows = _integer(resize['rows'], 'resize.rows');
        final int columns = _integer(resize['columns'], 'resize.columns');
        _expect(
          offset >= 0 && offset <= input.length && offset > previousOffset,
          'ordered in-range resize offsets',
        );
        _expect(
          rows >= 2 &&
              rows <= 32 &&
              columns >= 2 &&
              columns <= 80 &&
              rows * columns <= 1024,
          'bounded resize grid',
        );
        previousOffset = offset;
        resizes.add(_ResizeEvent(offset: offset, rows: rows, columns: columns));
      }
      seeds.add(
        _FuzzSeed(
          id: id,
          description: description,
          input: input,
          resizes: List<_ResizeEvent>.unmodifiable(resizes),
        ),
      );
    }
    return List<_FuzzSeed>.unmodifiable(seeds);
  }

  static Uint8List _hex(String value) {
    final BytesBuilder result = BytesBuilder(copy: false);
    var high = -1;
    for (var index = 0; index < value.length; index++) {
      final int unit = value.codeUnitAt(index);
      if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
        continue;
      }
      final int nibble = _nibble(unit);
      _expect(nibble >= 0, 'valid fuzz seed hex');
      if (high < 0) {
        high = nibble;
      } else {
        result.addByte(high << 4 | nibble);
        high = -1;
        _expect(result.length <= 4096, 'seed input <= 4096 bytes');
      }
    }
    _expect(high < 0 && result.length > 0, 'nonempty even fuzz seed hex');
    return result.takeBytes();
  }

  static int _nibble(int unit) {
    if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
    if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
    if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
    return -1;
  }

  static Map<String, Object?> _map(Object? value, String name) {
    _expect(value is Map<Object?, Object?>, '$name is an object');
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry
        in (value! as Map<Object?, Object?>).entries) {
      _expect(entry.key is String, '$name keys are strings');
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _list(Object? value, String name) {
    _expect(value is List<Object?>, '$name is an array');
    return value! as List<Object?>;
  }

  static String _string(Object? value, String name) {
    _expect(value is String, '$name is a string');
    return value! as String;
  }

  static int _integer(Object? value, String name) {
    _expect(value is int, '$name is an integer');
    return value! as int;
  }

  static void _keys(
    Map<String, Object?> value,
    Set<String> expected,
    String name,
  ) {
    _expect(
      value.length == expected.length &&
          value.keys.toSet().containsAll(expected),
      '$name has exact keys',
    );
  }
}

void _testSeedManifestValidation() {
  final Directory root = Directory.systemTemp.createTempSync(
    'dart-terminal-fuzz-seeds-',
  );
  final File file = File('${root.path}/seeds.json');
  const Map<String, Object?> seed = <String, Object?>{
    'id': 'fixture',
    'description': 'loader fixture',
    'input_hex': '41 42',
    'resizes': <Object?>[],
  };
  const Map<String, Object?> manifest = <String, Object?>{
    'format': 'dart-terminal-product-fuzz-seeds',
    'version': 1,
    'seeds': <Object?>[seed],
  };
  try {
    void rejects(Map<String, Object?> value, String description) {
      file.writeAsStringSync(jsonEncode(value));
      var rejected = false;
      try {
        const _FuzzSeedLoader().load(file.path);
      } on StateError {
        rejected = true;
      }
      _expect(rejected, description);
    }

    file.writeAsStringSync(jsonEncode(manifest));
    _expect(const _FuzzSeedLoader().load(file.path).length == 1, 'valid seed');
    rejects(<String, Object?>{...manifest, 'extra': true}, 'unknown root key');
    rejects(<String, Object?>{
      ...manifest,
      'seeds': <Object?>[seed, seed],
    }, 'duplicate seed id');
    rejects(<String, Object?>{
      ...manifest,
      'seeds': <Object?>[
        <String, Object?>{...seed, 'input_hex': '4'},
      ],
    }, 'odd seed hex');
    rejects(<String, Object?>{
      ...manifest,
      'seeds': <Object?>[
        <String, Object?>{
          ...seed,
          'resizes': <Object?>[
            <String, Object?>{'offset': 3, 'rows': 2, 'columns': 2},
          ],
        },
      ],
    }, 'out-of-range resize offset');
  } finally {
    root.deleteSync(recursive: true);
  }
}

final class _XorShift32 {
  _XorShift32(int seed) : _state = seed & 0xffffffff {
    if (_state == 0) {
      _state = 0x6d2b79f5;
    }
  }

  int _state;

  int nextUint32() {
    var value = _state;
    value ^= value << 13 & 0xffffffff;
    value ^= value >> 17;
    value ^= value << 5 & 0xffffffff;
    _state = value & 0xffffffff;
    return _state;
  }

  int nextInt(int upperBound) {
    if (upperBound <= 0) {
      throw RangeError.value(upperBound, 'upperBound', 'must be positive');
    }
    return nextUint32() % upperBound;
  }
}

int _caseSeed(int root, int index) {
  var value = (root + index * 0x9e3779b9) & 0xffffffff;
  value ^= value >> 16;
  value = value * 0x7feb352d & 0xffffffff;
  value ^= value >> 15;
  value = value * 0x846ca68b & 0xffffffff;
  value ^= value >> 16;
  return value & 0xffffffff;
}

int _hashBytes(int hash, Iterable<int> bytes) {
  var result = hash;
  for (final int byte in bytes) {
    result = ((result ^ byte) * 0x01000193) & 0x7fffffff;
  }
  return result;
}

int _hashString(int hash, String value) {
  var result = hash;
  for (var index = 0; index < value.length; index++) {
    result = ((result ^ value.codeUnitAt(index)) * 0x01000193) & 0x7fffffff;
  }
  return result;
}

int _hashInteger(int hash, int value) {
  var result = hash;
  for (var shift = 0; shift < 32; shift += 8) {
    result = ((result ^ (value >> shift & 0xff)) * 0x01000193) & 0x7fffffff;
  }
  return result;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}
