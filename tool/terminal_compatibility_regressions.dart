import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_differential_sha256.dart';

const String terminalCompatibilityRegressionCorpusPath =
    'test/corpus/compatibility/regressions_v1.json';

final class TerminalCompatibilityRegressionException implements Exception {
  const TerminalCompatibilityRegressionException(this.message);

  final String message;

  @override
  String toString() => 'TerminalCompatibilityRegressionException: $message';
}

final class TerminalCompatibilityRegressionRun {
  const TerminalCompatibilityRegressionRun({
    required this.cases,
    required this.inputBytes,
    required this.splitRuns,
    required this.fixFamilies,
    required this.observations,
  });

  final int cases;
  final int inputBytes;
  final int splitRuns;
  final List<String> fixFamilies;
  final Map<String, Map<String, Object?>> observations;

  String machineLine() =>
      'TERMINAL_COMPATIBILITY_REGRESSIONS_PASS cases=$cases '
      'input_bytes=$inputBytes split_runs=$splitRuns '
      'fix_families=${fixFamilies.length}';
}

final class TerminalCompatibilityRegressionCorpus {
  const TerminalCompatibilityRegressionCorpus._({
    required _CorpusLimits limits,
    required List<_RegressionCase> cases,
  }) : _limits = limits,
       _cases = cases;

  final _CorpusLimits _limits;
  final List<_RegressionCase> _cases;
}

extension on TerminalCompatibilityRegressionCorpus {
  _CorpusLimits get limits => _limits;
  List<_RegressionCase> get cases => _cases;
}

TerminalCompatibilityRegressionCorpus
parseTerminalCompatibilityRegressionCorpus(
  String source, {
  bool requireExpected = true,
}) {
  if (source.length > 1024 * 1024) {
    throw const TerminalCompatibilityRegressionException(
      'corpus source exceeds 1 MiB',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw TerminalCompatibilityRegressionException('invalid JSON: $error');
  }
  final Map<String, Object?> root = _object(decoded, 'root');
  _keys(root, const <String>{'format', 'version', 'limits', 'cases'}, 'root');
  _expect(
    root['format'] == 'dart-terminal-compatibility-regressions' &&
        root['version'] == 1,
    'invalid corpus identity',
  );
  final Map<String, Object?> limitMap = _object(root['limits'], 'limits');
  _keys(limitMap, const <String>{
    'max_cases',
    'max_input_bytes_per_case',
    'max_total_input_bytes',
    'max_rows',
    'max_columns',
    'max_reply_bytes',
    'max_snapshot_bytes',
  }, 'limits');
  final _CorpusLimits limits = _CorpusLimits(
    maxCases: _boundedInt(limitMap['max_cases'], 'limits.max_cases', 1, 128),
    maxInputBytesPerCase: _boundedInt(
      limitMap['max_input_bytes_per_case'],
      'limits.max_input_bytes_per_case',
      1,
      4096,
    ),
    maxTotalInputBytes: _boundedInt(
      limitMap['max_total_input_bytes'],
      'limits.max_total_input_bytes',
      1,
      65536,
    ),
    maxRows: _boundedInt(limitMap['max_rows'], 'limits.max_rows', 1, 64),
    maxColumns: _boundedInt(
      limitMap['max_columns'],
      'limits.max_columns',
      1,
      256,
    ),
    maxReplyBytes: _boundedInt(
      limitMap['max_reply_bytes'],
      'limits.max_reply_bytes',
      1,
      65536,
    ),
    maxSnapshotBytes: _boundedInt(
      limitMap['max_snapshot_bytes'],
      'limits.max_snapshot_bytes',
      1024,
      1024 * 1024,
    ),
  );
  final List<Object?> caseValues = _array(root['cases'], 'cases');
  _expect(
    caseValues.isNotEmpty && caseValues.length <= limits.maxCases,
    'case count is outside the declared bound',
  );
  final List<_RegressionCase> cases = <_RegressionCase>[];
  final Set<String> ids = <String>{};
  var totalInputBytes = 0;
  for (var index = 0; index < caseValues.length; index++) {
    final Map<String, Object?> map = _object(
      caseValues[index],
      'cases[$index]',
    );
    _keys(map, const <String>{
      'id',
      'fix_family',
      'owner',
      'rows',
      'columns',
      'logical_width',
      'logical_height',
      'input_hex',
      'expected',
    }, 'cases[$index]');
    final String id = _id(map['id'], 'cases[$index].id');
    _expect(ids.add(id), 'duplicate case id: $id');
    final String family = _id(map['fix_family'], 'cases[$index].fix_family');
    final String owner = _text(map['owner'], 'cases[$index].owner', 200);
    _expect(
      RegExp(r'^docs/phase6/[a-z0-9-]+\.md$').hasMatch(owner),
      '$id owner is not a safe Phase 6 document',
    );
    _expect(File(owner).existsSync(), '$id owner does not exist: $owner');
    final int rows = _boundedInt(map['rows'], '$id.rows', 1, limits.maxRows);
    final int columns = _boundedInt(
      map['columns'],
      '$id.columns',
      1,
      limits.maxColumns,
    );
    final int logicalWidth = _boundedInt(
      map['logical_width'],
      '$id.logical_width',
      1,
      TerminalScreenSet.maximumLogicalViewportExtent,
    );
    final int logicalHeight = _boundedInt(
      map['logical_height'],
      '$id.logical_height',
      1,
      TerminalScreenSet.maximumLogicalViewportExtent,
    );
    final Uint8List input = _hex(
      map['input_hex'],
      '$id.input_hex',
      limits.maxInputBytesPerCase,
    );
    _expect(input.isNotEmpty, '$id input is empty');
    totalInputBytes += input.length;
    _expect(
      totalInputBytes <= limits.maxTotalInputBytes,
      'total input exceeds ${limits.maxTotalInputBytes} bytes',
    );
    final Object? expectedValue = map['expected'];
    final Map<String, Object?>? expected = expectedValue == null
        ? null
        : _expectedObservation(expectedValue, id, limits);
    _expect(
      !requireExpected || expected != null,
      '$id is missing a reviewed expected observation',
    );
    cases.add(
      _RegressionCase(
        id: id,
        fixFamily: family,
        owner: owner,
        rows: rows,
        columns: columns,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        input: input,
        expected: expected,
      ),
    );
  }
  return TerminalCompatibilityRegressionCorpus._(
    limits: limits,
    cases: List<_RegressionCase>.unmodifiable(cases),
  );
}

TerminalCompatibilityRegressionRun runTerminalCompatibilityRegressionCorpus(
  TerminalCompatibilityRegressionCorpus corpus, {
  bool requireExpected = true,
}) {
  final Map<String, Map<String, Object?>> observations =
      <String, Map<String, Object?>>{};
  final Set<String> families = <String>{};
  var inputBytes = 0;
  var splitRuns = 0;
  for (final _RegressionCase testCase in corpus.cases) {
    final _CaseObservation whole = _runCase(testCase, <int>[
      testCase.input.length,
    ], corpus.limits);
    final Map<String, Object?> actual = whole.toJson();
    observations[testCase.id] = actual;
    families.add(testCase.fixFamily);
    inputBytes += testCase.input.length;
    splitRuns++;
    final Map<String, Object?>? expected = testCase.expected;
    if (requireExpected) {
      _expect(expected != null, '${testCase.id} expected observation missing');
      _expect(
        jsonEncode(actual) == jsonEncode(expected),
        '${testCase.id} differs from reviewed observation\n'
        'expected=${jsonEncode(expected)}\nactual=${jsonEncode(actual)}',
      );
    }
    for (var split = 0; split <= testCase.input.length; split++) {
      final _CaseObservation divided = _runCase(testCase, <int>[
        split,
        testCase.input.length - split,
      ], corpus.limits);
      splitRuns++;
      _expect(divided.sameAs(whole), '${testCase.id} differs at split $split');
    }
    final _CaseObservation bytewise = _runCase(
      testCase,
      List<int>.filled(testCase.input.length, 1),
      corpus.limits,
    );
    splitRuns++;
    _expect(bytewise.sameAs(whole), '${testCase.id} differs bytewise');
  }
  final List<String> orderedFamilies = families.toList()..sort();
  return TerminalCompatibilityRegressionRun(
    cases: corpus.cases.length,
    inputBytes: inputBytes,
    splitRuns: splitRuns,
    fixFamilies: List<String>.unmodifiable(orderedFamilies),
    observations: Map<String, Map<String, Object?>>.unmodifiable(observations),
  );
}

TerminalCompatibilityRegressionCorpus
loadTerminalCompatibilityRegressionCorpus({
  String path = terminalCompatibilityRegressionCorpusPath,
  bool requireExpected = true,
}) => parseTerminalCompatibilityRegressionCorpus(
  File(path).readAsStringSync(),
  requireExpected: requireExpected,
);

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1 ||
        arguments.single != '--check' &&
            arguments.single != '--generate' &&
            arguments.single != '--inspect') {
      throw const TerminalCompatibilityRegressionException(
        'usage: terminal_compatibility_regressions.dart '
        '[--check|--generate|--inspect]',
      );
    }
    if (arguments.single == '--generate') {
      final File file = File(terminalCompatibilityRegressionCorpusPath);
      final String source = await file.readAsString();
      final TerminalCompatibilityRegressionRun result =
          runTerminalCompatibilityRegressionCorpus(
            parseTerminalCompatibilityRegressionCorpus(
              source,
              requireExpected: false,
            ),
            requireExpected: false,
          );
      final Map<String, Object?> root = _object(jsonDecode(source), 'root');
      for (final Object? value in _array(root['cases'], 'cases')) {
        final Map<String, Object?> testCase = _object(value, 'case');
        final String id = _id(testCase['id'], 'case.id');
        testCase['expected'] = result.observations[id]!;
      }
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(root)}\n',
      );
      stdout.writeln(
        'TERMINAL_COMPATIBILITY_REGRESSIONS_GENERATED '
        'path=$terminalCompatibilityRegressionCorpusPath cases=${result.cases}',
      );
      return;
    }
    final bool inspect = arguments.single == '--inspect';
    final TerminalCompatibilityRegressionRun result =
        runTerminalCompatibilityRegressionCorpus(
          loadTerminalCompatibilityRegressionCorpus(requireExpected: !inspect),
          requireExpected: !inspect,
        );
    if (inspect) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'format': 'dart-terminal-compatibility-regression-observations',
          'version': 1,
          'cases': <Object?>[
            for (final MapEntry<String, Map<String, Object?>> entry
                in result.observations.entries)
              <String, Object?>{'id': entry.key, 'expected': entry.value},
          ],
        }),
      );
    } else {
      stdout.writeln(result.machineLine());
    }
  } on Object catch (error) {
    stderr.writeln('TERMINAL_COMPATIBILITY_REGRESSIONS_FAIL $error');
    exitCode = 1;
  }
}

_CaseObservation _runCase(
  _RegressionCase testCase,
  List<int> chunks,
  _CorpusLimits limits,
) {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: testCase.rows,
    columns: testCase.columns,
  );
  _expect(
    screens.updateLogicalViewportSize(
      width: testCase.logicalWidth.toDouble(),
      height: testCase.logicalHeight.toDouble(),
    ),
    '${testCase.id} logical geometry is invalid',
  );
  final BytesBuilder replies = BytesBuilder(copy: false);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List reply) {
      if (replies.length + reply.length > limits.maxReplyBytes) return false;
      replies.add(reply);
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  var offset = 0;
  for (final int length in chunks) {
    _expect(
      length >= 0 && offset + length <= testCase.input.length,
      '${testCase.id} has an invalid chunk plan',
    );
    parser.parse(testCase.input, offset, offset + length);
    offset += length;
  }
  _expect(
    offset == testCase.input.length,
    '${testCase.id} chunk plan consumed $offset/${testCase.input.length}',
  );
  parser.finish();
  _expect(parser.isGround, '${testCase.id} parser is not in ground state');
  screens.primary.validateCellTopology();
  screens.alternate.validateCellTopology();
  screens.scrollback.validateCellTopology();
  final String snapshot = const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
  final List<int> snapshotBytes = utf8.encode(snapshot);
  _expect(
    snapshotBytes.length <= limits.maxSnapshotBytes,
    '${testCase.id} snapshot exceeds ${limits.maxSnapshotBytes} bytes',
  );
  final Uint8List replyBytes = replies.takeBytes();
  return _CaseObservation(
    snapshot: snapshot,
    snapshotSha256: terminalDifferentialSha256(snapshotBytes),
    snapshotUtf8Bytes: snapshotBytes.length,
    snapshotProjection: _snapshotProjection(snapshot),
    repliesHex: _encodeHex(replyBytes),
    state: <String, Object?>{
      'active_screen': screens.activeKind.name,
      'application_cursor': screens.keyboardModes.applicationCursorKeys,
      'application_keypad': screens.keyboardModes.applicationKeypad,
      'bracketed_paste': screens.bracketedPasteMode,
      'focus_reporting': screens.focusReportingMode,
      'mouse_tracking': screens.mouseModes.tracking.name,
      'mouse_encoding': screens.mouseModes.encoding.name,
      'window_title': screens.metadata.windowTitle,
      'icon_title': screens.metadata.iconTitle,
      'working_directory': screens.metadata.workingDirectory?.toString(),
      'window_title_stack': screens.metadata.windowTitleStack,
      'icon_title_stack': screens.metadata.iconTitleStack,
      'default_foreground': screens.palette.defaultForeground,
      'default_background': screens.palette.defaultBackground,
      'cursor_color': screens.palette.cursorColor,
      'palette_1': screens.palette.colorAt(1),
      'current_foreground': screens.activeScreen.currentForeground,
      'current_background': screens.activeScreen.currentBackground,
      'current_style_attributes': screens.activeScreen.currentStyleAttributes,
      'current_hyperlink_id': sink.currentHyperlinkId,
      'logical_width': screens.logicalViewportSize!.width,
      'logical_height': screens.logicalViewportSize!.height,
    },
    counters: <String, Object?>{
      'unsupported_controls': sink.unsupportedControlCount,
      'unsupported_sequences': sink.unsupportedSequenceCount,
      'cancel': sink.cancelCount,
      'limit': sink.limitCount,
      'malformed': sink.malformedCount,
      'incomplete': sink.incompleteCount,
      'accepted_replies': sink.acceptedReplyCount,
      'rejected_replies': sink.rejectedReplyCount,
      'accepted_hyperlinks': sink.acceptedHyperlinkCount,
      'rejected_hyperlinks': sink.rejectedHyperlinkCount,
      'denied_clipboard_reads': sink.deniedClipboardReadCount,
      'denied_clipboard_writes': sink.deniedClipboardWriteCount,
      'denied_clipboard_clears': sink.deniedClipboardClearCount,
      'rejected_clipboard_requests': sink.rejectedClipboardRequestCount,
    },
  );
}

List<String> _snapshotProjection(String snapshot) {
  final List<String> result = <String>[];
  for (final String line in const LineSplitter().convert(snapshot)) {
    if (line.startsWith('set ') ||
        line.startsWith('metadata ') ||
        line.startsWith('hyperlinks ') ||
        line.startsWith('hyperlink id=') ||
        line.startsWith('palette defaults ') ||
        line.startsWith('palette range=000-015 ') ||
        line.startsWith('primary cursor=') ||
        line.startsWith('primary charsets=') ||
        line.startsWith('primary margins=') ||
        line.startsWith('primary cursor_style=') ||
        line.startsWith('primary row=') ||
        line.startsWith('primary cell=') ||
        line.startsWith('parser ')) {
      result.add(line);
    }
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?> _expectedObservation(
  Object? value,
  String id,
  _CorpusLimits limits,
) {
  final Map<String, Object?> expected = _object(value, '$id.expected');
  _keys(expected, const <String>{
    'snapshot_sha256',
    'snapshot_utf8_bytes',
    'snapshot_projection',
    'replies_hex',
    'state',
    'counters',
  }, '$id.expected');
  final String hash = _text(
    expected['snapshot_sha256'],
    '$id.expected.snapshot_sha256',
    64,
  );
  _expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), '$id has invalid hash');
  _boundedInt(
    expected['snapshot_utf8_bytes'],
    '$id.expected.snapshot_utf8_bytes',
    1,
    limits.maxSnapshotBytes,
  );
  final List<Object?> projection = _array(
    expected['snapshot_projection'],
    '$id.expected.snapshot_projection',
  );
  _expect(projection.length <= 128, '$id projection is too large');
  for (var index = 0; index < projection.length; index++) {
    _text(projection[index], '$id projection[$index]', 1024);
  }
  _hex(
    expected['replies_hex'],
    '$id.expected.replies_hex',
    limits.maxReplyBytes,
  );
  final Map<String, Object?> state = _object(expected['state'], '$id.state');
  _keys(state, _stateKeys, '$id.state');
  final Map<String, Object?> counters = _object(
    expected['counters'],
    '$id.counters',
  );
  _keys(counters, _counterKeys, '$id.counters');
  for (final String key in _counterKeys) {
    _boundedInt(counters[key], '$id.counters.$key', 0, 1000000);
  }
  return expected;
}

const Set<String> _stateKeys = <String>{
  'active_screen',
  'application_cursor',
  'application_keypad',
  'bracketed_paste',
  'focus_reporting',
  'mouse_tracking',
  'mouse_encoding',
  'window_title',
  'icon_title',
  'working_directory',
  'window_title_stack',
  'icon_title_stack',
  'default_foreground',
  'default_background',
  'cursor_color',
  'palette_1',
  'current_foreground',
  'current_background',
  'current_style_attributes',
  'current_hyperlink_id',
  'logical_width',
  'logical_height',
};

const Set<String> _counterKeys = <String>{
  'unsupported_controls',
  'unsupported_sequences',
  'cancel',
  'limit',
  'malformed',
  'incomplete',
  'accepted_replies',
  'rejected_replies',
  'accepted_hyperlinks',
  'rejected_hyperlinks',
  'denied_clipboard_reads',
  'denied_clipboard_writes',
  'denied_clipboard_clears',
  'rejected_clipboard_requests',
};

final class _CorpusLimits {
  const _CorpusLimits({
    required this.maxCases,
    required this.maxInputBytesPerCase,
    required this.maxTotalInputBytes,
    required this.maxRows,
    required this.maxColumns,
    required this.maxReplyBytes,
    required this.maxSnapshotBytes,
  });

  final int maxCases;
  final int maxInputBytesPerCase;
  final int maxTotalInputBytes;
  final int maxRows;
  final int maxColumns;
  final int maxReplyBytes;
  final int maxSnapshotBytes;
}

final class _RegressionCase {
  const _RegressionCase({
    required this.id,
    required this.fixFamily,
    required this.owner,
    required this.rows,
    required this.columns,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.input,
    required this.expected,
  });

  final String id;
  final String fixFamily;
  final String owner;
  final int rows;
  final int columns;
  final int logicalWidth;
  final int logicalHeight;
  final Uint8List input;
  final Map<String, Object?>? expected;
}

final class _CaseObservation {
  const _CaseObservation({
    required this.snapshot,
    required this.snapshotSha256,
    required this.snapshotUtf8Bytes,
    required this.snapshotProjection,
    required this.repliesHex,
    required this.state,
    required this.counters,
  });

  final String snapshot;
  final String snapshotSha256;
  final int snapshotUtf8Bytes;
  final List<String> snapshotProjection;
  final String repliesHex;
  final Map<String, Object?> state;
  final Map<String, Object?> counters;

  Map<String, Object?> toJson() => <String, Object?>{
    'snapshot_sha256': snapshotSha256,
    'snapshot_utf8_bytes': snapshotUtf8Bytes,
    'snapshot_projection': snapshotProjection,
    'replies_hex': repliesHex,
    'state': state,
    'counters': counters,
  };

  bool sameAs(_CaseObservation other) =>
      snapshot == other.snapshot &&
      repliesHex == other.repliesHex &&
      jsonEncode(state) == jsonEncode(other.state) &&
      jsonEncode(counters) == jsonEncode(other.counters);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw TerminalCompatibilityRegressionException('$name must be an object');
  }
  return value;
}

List<Object?> _array(Object? value, String name) {
  if (value is! List<Object?>) {
    throw TerminalCompatibilityRegressionException('$name must be an array');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> expected, String name) {
  final Set<String> actual = value.keys.toSet();
  _expect(
    actual.length == expected.length && actual.containsAll(expected),
    '$name has unexpected fields: ${actual.difference(expected)}; '
    'missing: ${expected.difference(actual)}',
  );
}

int _boundedInt(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw TerminalCompatibilityRegressionException(
      '$name must be an integer between $minimum and $maximum',
    );
  }
  return value;
}

String _text(Object? value, String name, int maximumLength) {
  if (value is! String || value.length > maximumLength) {
    throw TerminalCompatibilityRegressionException(
      '$name must be a string no longer than $maximumLength characters',
    );
  }
  return value;
}

String _id(Object? value, String name) {
  final String result = _text(value, name, 80);
  _expect(
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(result),
    '$name invalid',
  );
  return result;
}

Uint8List _hex(Object? value, String name, int maximumBytes) {
  final String source = _text(value, name, maximumBytes * 2);
  _expect(
    source.length.isEven && RegExp(r'^[0-9a-f]*$').hasMatch(source),
    '$name must be lowercase byte-aligned hex',
  );
  final Uint8List result = Uint8List(source.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      source.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

String _encodeHex(Iterable<int> bytes) =>
    bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void _expect(bool condition, String message) {
  if (!condition) throw TerminalCompatibilityRegressionException(message);
}
