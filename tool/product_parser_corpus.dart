import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const String defaultProductParserCorpusPath =
    'test/corpus/parser/product_v1.json';

final class ProductParserCorpusResult {
  const ProductParserCorpusResult({
    required this.caseCount,
    required this.inputBytes,
    required this.splitRuns,
    required this.snapshotHash,
  });

  final int caseCount;
  final int inputBytes;
  final int splitRuns;
  final int snapshotHash;

  String machineLine() =>
      'PRODUCT_PARSER_CORPUS_PASS cases=$caseCount input_bytes=$inputBytes '
      'split_runs=$splitRuns snapshot_hash=$snapshotHash';
}

final class ProductParserCorpusException implements Exception {
  const ProductParserCorpusException(this.message);

  final String message;

  @override
  String toString() => 'ProductParserCorpusException: $message';
}

final class _ProductCorpusCase {
  const _ProductCorpusCase({
    required this.id,
    required this.description,
    required this.input,
    required this.expectedSnapshot,
    required this.rows,
    required this.columns,
    required this.parserLimits,
    required this.scrollbackMaxLines,
    required this.scrollbackMaxBytes,
    required this.scrollbackPageRows,
  });

  final String id;
  final String description;
  final Uint8List input;
  final String expectedSnapshot;
  final int rows;
  final int columns;
  final VtParserLimits parserLimits;
  final int scrollbackMaxLines;
  final int scrollbackMaxBytes;
  final int scrollbackPageRows;
}

final class _ProductCorpusLoader {
  const _ProductCorpusLoader();

  static const int maximumCases = 128;
  static const int maximumCaseInputBytes = 16 * 1024;
  static const int maximumAggregateInputBytes = 64 * 1024;
  static const int maximumAggregateSplitRuns = 65536;
  static const int maximumSnapshotBytes = 16 * 1024 * 1024;
  static const int maximumDescriptionCharacters = 256;
  static const int maximumRows = 256;
  static const int maximumColumns = 512;
  static const int maximumCells = 65536;

  List<_ProductCorpusCase> load(String path) {
    final File manifest = File(path);
    _expect(manifest.existsSync(), 'corpus manifest does not exist: $path');
    final int manifestBytes = manifest.lengthSync();
    _expect(
      manifestBytes > 0 && manifestBytes <= 1024 * 1024,
      'corpus manifest size $manifestBytes is outside 1..1048576',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(manifest.readAsStringSync());
    } on Object catch (error) {
      throw ProductParserCorpusException('invalid corpus JSON: $error');
    }
    final Map<String, Object?> root = _objectMap(decoded, 'corpus root');
    _expectKeys(root, const <String>{'format', 'version', 'cases'}, 'root');
    _expect(
      root['format'] == 'dart-terminal-product-parser-corpus',
      'unsupported corpus format',
    );
    _expect(root['version'] == 1, 'unsupported corpus version');
    final List<Object?> entries = _objectList(root['cases'], 'cases');
    _expect(entries.isNotEmpty, 'corpus cases must not be empty');
    _expect(
      entries.length <= maximumCases,
      'corpus cases ${entries.length} exceed $maximumCases',
    );

    final Uri manifestDirectory = manifest.absolute.parent.uri;
    final Set<String> ids = <String>{};
    final List<_ProductCorpusCase> cases = <_ProductCorpusCase>[];
    int aggregateInputBytes = 0;
    int aggregateSplitRuns = 0;
    for (int index = 0; index < entries.length; index++) {
      final _ProductCorpusCase testCase = _decodeCase(
        _objectMap(entries[index], 'cases[$index]'),
        manifestDirectory,
      );
      _expect(ids.add(testCase.id), 'duplicate corpus id ${testCase.id}');
      aggregateInputBytes += testCase.input.length;
      aggregateSplitRuns += testCase.input.length + 2;
      _expect(
        aggregateInputBytes <= maximumAggregateInputBytes,
        'aggregate input bytes exceed $maximumAggregateInputBytes',
      );
      _expect(
        aggregateSplitRuns <= maximumAggregateSplitRuns,
        'aggregate split runs exceed $maximumAggregateSplitRuns',
      );
      cases.add(testCase);
    }
    return List<_ProductCorpusCase>.unmodifiable(cases);
  }

  _ProductCorpusCase _decodeCase(
    Map<String, Object?> map,
    Uri manifestDirectory,
  ) {
    _expectKeys(map, const <String>{
      'id',
      'description',
      'input_hex',
      'snapshot',
      'rows',
      'columns',
      'parser_limits',
      'scrollback',
    }, 'corpus case');
    final String id = _string(map['id'], 'id');
    _expect(_validId(id), 'invalid corpus id $id');
    final String description = _string(map['description'], 'description');
    _expect(
      description.isNotEmpty &&
          description.length <= maximumDescriptionCharacters &&
          !_containsControl(description),
      '$id: invalid description',
    );
    final Uint8List input = _decodeHex(
      _string(map['input_hex'], '$id.input_hex'),
      id,
    );
    final int rows = _integer(map['rows'], '$id.rows');
    final int columns = _integer(map['columns'], '$id.columns');
    _expect(rows >= 1 && rows <= maximumRows, '$id: invalid rows $rows');
    _expect(
      columns >= 1 && columns <= maximumColumns,
      '$id: invalid columns $columns',
    );
    _expect(rows * columns <= maximumCells, '$id: grid exceeds $maximumCells');
    final VtParserLimits parserLimits = _parserLimits(
      _objectMap(map['parser_limits'], '$id.parser_limits'),
      id,
    );
    final ({int maxLines, int maxBytes, int pageRows}) scrollback = _scrollback(
      _objectMap(map['scrollback'], '$id.scrollback'),
      id,
    );
    final String snapshotPath = _string(map['snapshot'], '$id.snapshot');
    _expect(
      snapshotPath == 'snapshots/$id.snapshot',
      '$id: snapshot path must be snapshots/$id.snapshot',
    );
    _expect(_safeRelativePath(snapshotPath), '$id: unsafe snapshot path');
    final File snapshot = File.fromUri(manifestDirectory.resolve(snapshotPath));
    _expect(snapshot.existsSync(), '$id: snapshot does not exist');
    _expect(
      FileSystemEntity.typeSync(snapshot.path, followLinks: false) ==
          FileSystemEntityType.file,
      '$id: snapshot must be a regular file',
    );
    final int snapshotBytes = snapshot.lengthSync();
    _expect(
      snapshotBytes > 0 && snapshotBytes <= maximumSnapshotBytes,
      '$id: snapshot size $snapshotBytes is outside 1..$maximumSnapshotBytes',
    );
    final String expectedSnapshot;
    try {
      expectedSnapshot = snapshot.readAsStringSync();
    } on Object catch (error) {
      throw ProductParserCorpusException('$id: invalid UTF-8 snapshot: $error');
    }
    _expect(
      expectedSnapshot.endsWith('\n') &&
          (expectedSnapshot.length == 1 ||
              expectedSnapshot.codeUnitAt(expectedSnapshot.length - 2) != 0x0a),
      '$id: snapshot must end with one newline',
    );
    _expect(
      expectedSnapshot.startsWith(
        '${TerminalSnapshotFormatter.formatName} '
        'version=${TerminalSnapshotFormatter.formatVersion} kind=screen-set\n',
      ),
      '$id: snapshot has an unsupported terminal-state header',
    );

    return _ProductCorpusCase(
      id: id,
      description: description,
      input: input,
      expectedSnapshot: expectedSnapshot,
      rows: rows,
      columns: columns,
      parserLimits: parserLimits,
      scrollbackMaxLines: scrollback.maxLines,
      scrollbackMaxBytes: scrollback.maxBytes,
      scrollbackPageRows: scrollback.pageRows,
    );
  }

  VtParserLimits _parserLimits(Map<String, Object?> map, String id) {
    _expectKeys(map, const <String>{
      'max_sequence_bytes',
      'max_string_bytes',
      'max_application_program_command_bytes',
      'max_parameters',
      'max_intermediates',
      'max_numeric_value',
    }, '$id.parser_limits');
    final VtParserLimits limits = VtParserLimits(
      maxSequenceBytes: _integer(
        map['max_sequence_bytes'],
        '$id.max_sequence_bytes',
      ),
      maxStringBytes: _integer(map['max_string_bytes'], '$id.max_string_bytes'),
      maxApplicationProgramCommandBytes: _integer(
        map['max_application_program_command_bytes'],
        '$id.max_application_program_command_bytes',
      ),
      maxParameters: _integer(map['max_parameters'], '$id.max_parameters'),
      maxIntermediates: _integer(
        map['max_intermediates'],
        '$id.max_intermediates',
      ),
      maxNumericValue: _integer(
        map['max_numeric_value'],
        '$id.max_numeric_value',
      ),
    );
    try {
      limits.validate();
    } on ArgumentError catch (error) {
      throw ProductParserCorpusException('$id: invalid parser limits: $error');
    }
    return limits;
  }

  ({int maxLines, int maxBytes, int pageRows}) _scrollback(
    Map<String, Object?> map,
    String id,
  ) {
    _expectKeys(map, const <String>{
      'max_lines',
      'max_bytes',
      'page_rows',
    }, '$id.scrollback');
    final int maxLines = _integer(map['max_lines'], '$id.max_lines');
    final int maxBytes = _integer(map['max_bytes'], '$id.max_bytes');
    final int pageRows = _integer(map['page_rows'], '$id.page_rows');
    _expect(
      maxLines >= 1 && maxLines <= 4096,
      '$id: invalid scrollback max_lines',
    );
    _expect(
      maxBytes >= 1 && maxBytes <= 16 * 1024 * 1024,
      '$id: invalid scrollback max_bytes',
    );
    _expect(
      pageRows >= 1 && pageRows <= TerminalScrollback.maximumPageRows,
      '$id: invalid scrollback page_rows',
    );
    return (maxLines: maxLines, maxBytes: maxBytes, pageRows: pageRows);
  }

  Uint8List _decodeHex(String source, String id) {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    int high = -1;
    for (int index = 0; index < source.length; index++) {
      final int unit = source.codeUnitAt(index);
      if (_isWhitespace(unit)) {
        continue;
      }
      final int nibble = _hexNibble(unit);
      _expect(nibble >= 0, '$id: invalid hex character at $index');
      if (high < 0) {
        high = nibble;
      } else {
        bytes.addByte((high << 4) | nibble);
        high = -1;
        _expect(
          bytes.length <= maximumCaseInputBytes,
          '$id: input exceeds $maximumCaseInputBytes bytes',
        );
      }
    }
    _expect(high < 0, '$id: input hex has an odd digit count');
    _expect(bytes.isNotEmpty, '$id: input must not be empty');
    return bytes.takeBytes();
  }

  static Map<String, Object?> _objectMap(Object? value, String name) {
    if (value is! Map<Object?, Object?>) {
      throw ProductParserCorpusException('$name must be an object');
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ProductParserCorpusException('$name has a non-string key');
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _objectList(Object? value, String name) {
    if (value is! List<Object?>) {
      throw ProductParserCorpusException('$name must be an array');
    }
    return value;
  }

  static String _string(Object? value, String name) {
    if (value is! String) {
      throw ProductParserCorpusException('$name must be a string');
    }
    return value;
  }

  static int _integer(Object? value, String name) {
    if (value is! int) {
      throw ProductParserCorpusException('$name must be an integer');
    }
    return value;
  }

  static void _expectKeys(
    Map<String, Object?> map,
    Set<String> expected,
    String name,
  ) {
    final Set<String> actual = map.keys.toSet();
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      final List<String> missing = expected.difference(actual).toList()..sort();
      final List<String> unknown = actual.difference(expected).toList()..sort();
      throw ProductParserCorpusException(
        '$name keys differ; missing=${missing.join(',')} '
        'unknown=${unknown.join(',')}',
      );
    }
  }

  static bool _validId(String value) {
    if (value.isEmpty || value.length > 64) {
      return false;
    }
    for (int index = 0; index < value.length; index++) {
      final int unit = value.codeUnitAt(index);
      final bool alphanumeric =
          (unit >= 0x61 && unit <= 0x7a) || (unit >= 0x30 && unit <= 0x39);
      if (!alphanumeric && (unit != 0x2d || index == 0)) {
        return false;
      }
    }
    return true;
  }

  static bool _containsControl(String value) {
    for (int index = 0; index < value.length; index++) {
      final int unit = value.codeUnitAt(index);
      if (unit < 0x20 || unit == 0x7f) {
        return true;
      }
    }
    return false;
  }

  static bool _safeRelativePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      return false;
    }
    final List<String> segments = path.split('/');
    return segments.every(
      (String segment) =>
          segment.isNotEmpty && segment != '.' && segment != '..',
    );
  }

  static bool _isWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

  static int _hexNibble(int unit) {
    if (unit >= 0x30 && unit <= 0x39) {
      return unit - 0x30;
    }
    if (unit >= 0x41 && unit <= 0x46) {
      return unit - 0x41 + 10;
    }
    if (unit >= 0x61 && unit <= 0x66) {
      return unit - 0x61 + 10;
    }
    return -1;
  }

  static void _expect(bool condition, String message) {
    if (!condition) {
      throw ProductParserCorpusException(message);
    }
  }
}

ProductParserCorpusResult runProductParserCorpus({
  String corpusPath = defaultProductParserCorpusPath,
  bool printSnapshots = false,
  StringSink? output,
}) {
  final StringSink destination = output ?? stdout;
  final List<_ProductCorpusCase> corpus = const _ProductCorpusLoader().load(
    corpusPath,
  );
  const TerminalSnapshotComparator comparator = TerminalSnapshotComparator();
  int inputBytes = 0;
  int splitRuns = 0;
  int snapshotHash = 0x811c9dc5;
  for (final _ProductCorpusCase testCase in corpus) {
    inputBytes += testCase.input.length;
    final String whole = _runCase(testCase, <int>[testCase.input.length]);
    if (printSnapshots) {
      destination.writeln('SNAPSHOT ${testCase.id} ${testCase.description}');
      destination.write(whole);
      destination.writeln('END_SNAPSHOT ${testCase.id}');
      continue;
    }
    comparator
        .compare(testCase.expectedSnapshot, whole)
        .requireMatch('${testCase.id} whole');
    snapshotHash = _hashString(snapshotHash, whole);
    for (int split = 0; split <= testCase.input.length; split++) {
      final String actual = _runCase(testCase, <int>[
        split,
        testCase.input.length - split,
      ]);
      splitRuns++;
      comparator
          .compare(whole, actual)
          .requireMatch('${testCase.id} split-$split');
    }
    final String bytewise = _runCase(
      testCase,
      List<int>.filled(testCase.input.length, 1),
    );
    splitRuns++;
    comparator.compare(whole, bytewise).requireMatch('${testCase.id} bytewise');
  }
  return ProductParserCorpusResult(
    caseCount: corpus.length,
    inputBytes: inputBytes,
    splitRuns: splitRuns,
    snapshotHash: snapshotHash & 0x7fffffff,
  );
}

String _runCase(_ProductCorpusCase testCase, List<int> chunks) {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: testCase.rows,
    columns: testCase.columns,
    scrollback: TerminalScrollback(
      maxLines: testCase.scrollbackMaxLines,
      maxBytes: testCase.scrollbackMaxBytes,
      pageRows: testCase.scrollbackPageRows,
    ),
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (_) => true,
  );
  final VtParser parser = VtParser(sink: sink, limits: testCase.parserLimits);
  int offset = 0;
  for (final int length in chunks) {
    if (length < 0 || offset + length > testCase.input.length) {
      throw ProductParserCorpusException(
        '${testCase.id}: invalid chunk plan at $offset+$length',
      );
    }
    parser.parse(testCase.input, offset, offset + length);
    offset += length;
  }
  if (offset != testCase.input.length) {
    throw ProductParserCorpusException(
      '${testCase.id}: chunk plan consumed $offset/${testCase.input.length}',
    );
  }
  parser.finish();
  if (!parser.isGround) {
    throw ProductParserCorpusException('${testCase.id}: parser is not ground');
  }
  screens.primary.validateCellTopology();
  screens.alternate.validateCellTopology();
  screens.scrollback.validateCellTopology();
  return const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
}

int _hashString(int hash, String value) {
  int result = hash;
  for (int index = 0; index < value.length; index++) {
    result ^= value.codeUnitAt(index);
    result = (result * 0x01000193) & 0xffffffff;
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  String corpusPath = defaultProductParserCorpusPath;
  var printSnapshots = false;
  for (final String argument in arguments) {
    if (argument == '--print-snapshots') {
      printSnapshots = true;
    } else if (argument.startsWith('--corpus=')) {
      corpusPath = argument.substring('--corpus='.length);
    } else {
      stderr.writeln('PRODUCT_PARSER_CORPUS_FAIL unknown argument: $argument');
      exitCode = 64;
      return;
    }
  }
  try {
    final ProductParserCorpusResult result = runProductParserCorpus(
      corpusPath: corpusPath,
      printSnapshots: printSnapshots,
    );
    if (!printSnapshots) {
      stdout.writeln(result.machineLine());
    }
  } on Object catch (error) {
    stderr.writeln('PRODUCT_PARSER_CORPUS_FAIL $error');
    exitCode = 1;
  }
}
