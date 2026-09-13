import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSnapshotTests();

void runTerminalSnapshotTests() {
  _testStandaloneSnapshotIsExactAndReadable();
  _testScreenSetSnapshotIncludesHistoryAndBothBuffers();
  _testSnapshotIncludesOwnedParserCounters();
  _testFormattingDoesNotMutateTerminalState();
  _testSnapshotLimitsRejectIncompleteOracles();
  _testParserChunkPlansProduceIdenticalSnapshots();
  _testSnapshotComparisonExactMatchAndMismatch();
  _testSnapshotComparisonEndAndControlDiagnostics();
  _testSnapshotComparisonLimitsAndTypedFailure();
}

void _testStandaloneSnapshotIsExactAndReadable() {
  final TerminalStyleTable styles = TerminalStyleTable();
  final int style = styles.intern(
    TerminalStyleAttributes.bold |
        TerminalStyleAttributes.withUnderline(
          TerminalStyleAttributes.overline,
          TerminalUnderlineStyle.double,
        ),
    underlineColor: 7,
  );
  final TerminalGraphemeTable graphemes = TerminalGraphemeTable();
  final int grapheme = graphemes.intern(const <int>[0x65, 0x301]);
  final TerminalScreen screen = TerminalScreen(
    rows: 2,
    columns: 6,
    styleTable: styles,
    graphemeTable: graphemes,
  );
  screen.setNarrowCell(0, 0, 0x41, foreground: 3, style: style);
  screen.setGraphemeCell(0, 1, grapheme, background: 0x80112233);
  screen.setWideCell(0, 2, 0x65e5, hyperlink: 9);
  screen.setNarrowCell(0, 5, 0, isProtected: true);
  screen.setRowFlags(0, TerminalRowFlags.softWrapped | TerminalRowFlags.prompt);
  screen.setCurrentRendition(
    foreground: 2,
    background: 0x80445566,
    styleAttributes: styles.attributesAt(style),
    underlineColor: styles.underlineColorAt(style),
  );
  screen.setCurrentCellProtection(true);
  screen.setCursorPosition(1, 4);
  screen.designateCharacterSet(1, TerminalCharacterSet.decSpecialGraphics);
  screen.invokeGlCharacterSet(1);
  screen.saveCursor();
  screen.invokeGlCharacterSet(0);
  screen.setMode(TerminalScreenMode.insert, true);
  screen.setCursorPresentation(
    shape: TerminalCursorShape.bar,
    visible: false,
    blinking: false,
  );
  screen.setCursorColor(0x80abcdef);
  screen.clearAllTabStops();
  screen.setTabStop(3);

  const TerminalSnapshotFormatter formatter = TerminalSnapshotFormatter();
  final String snapshot = formatter.formatScreen(screen);
  _expect(
    snapshot.startsWith('dart-terminal-state-snapshot version=4 kind=screen\n'),
    'standalone snapshot has a versioned header',
  );
  _expect(
    snapshot.contains(
      'palette defaults foreground=#e5e5e5 background=#000000 '
      'cursor=#abcdef\n',
    ),
    'snapshot retains independent cursor color state',
  );
  _expect(
    snapshot.contains(
      'style id=$style attributes=bold|underline:double|overline '
      'bits=0x0411 underline_color=palette:6\n',
    ),
    'style definition is readable and exact',
  );
  _expect(
    snapshot.contains(
      'grapheme id=$grapheme width=1 scalars=U+0065,U+0301 text="é"\n',
    ),
    'grapheme definition retains scalars and readable text',
  );
  _expect(
    snapshot.contains(
      'screen row=0 flags=soft-wrapped|prompt logical=1:1+0 '
      'text="Aé日·  "\n',
    ),
    'row projection makes graphemes, wide continuation, and blanks visible',
  );
  _expect(
    snapshot.contains(
      'screen cell=0,0 content=U+0041 flags=narrow '
      'foreground=palette:2 background=default style=$style hyperlink=0\n',
    ),
    'scalar cell retains exact resources',
  );
  _expect(
    snapshot.contains(
      'screen cell=0,3 content=continuation flags=continuation '
      'foreground=default background=default style=0 hyperlink=9\n',
    ),
    'wide continuation is explicit',
  );
  _expect(
    snapshot.contains(
      'screen cell=0,5 content=blank flags=narrow|protected '
      'foreground=default background=default style=0 hyperlink=0\n',
    ),
    'styled or protected blank does not disappear',
  );
  _expect(
    snapshot.contains(
      'screen cursor=1,4 saved=1,4 '
      'current=palette:1/rgb:#445566/$style '
      'saved_rendition=palette:1/rgb:#445566/$style '
      'protection=current:true,saved:true\n',
    ),
    'cursor, rendition, and DEC protection state are retained',
  );
  _expect(
    snapshot.contains(
      'screen charsets=g0:ascii,g1:decSpecialGraphics,gl:0 '
      'saved=g0:ascii,g1:decSpecialGraphics,gl:1\n',
    ),
    'current and saved character-set state is retained',
  );
  _expect(
    snapshot.contains('screen tabs=3\n') && snapshot.endsWith('end\n'),
    'tab stops and terminal marker are deterministic',
  );
  _expect(
    snapshot == formatter.formatScreen(screen),
    'repeated formatting is byte-identical',
  );
}

void _testScreenSetSnapshotIncludesHistoryAndBothBuffers() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 4, maxBytes: 4096, pageRows: 2),
  );
  _writeRow(screens.primary, 0, 'old!');
  screens.primary.setRowFlags(0, TerminalRowFlags.output);
  screens.primary.setCursorPosition(1, 0);
  screens.primary.lineFeed();
  _writeRow(screens.primary, 1, 'new!');
  screens.viewport.scrollToTop();
  screens.setAlternateMode47(true);
  _writeRow(screens.alternate, 0, 'alt!');

  final String snapshot = const TerminalSnapshotFormatter().formatScreenSet(
    screens,
  );
  _expect(
    snapshot.contains(
      'set active=alternate mode1049=false viewport_offset=0 '
      'primary_viewport_offset=1\n',
    ),
    'screen-set ownership and effective alternate viewport are explicit',
  );
  _expect(
    snapshot.contains(
      'history rows=1 max_lines=4 max_bytes=4096 page_rows=2\n',
    ),
    'history configuration and retained row count are captured',
  );
  _expect(
    snapshot.contains('history row=0 columns=4 flags=output') &&
        snapshot.contains('text="old!"'),
    'history row text and semantics are captured',
  );
  _expect(
    snapshot.contains('screen name=primary rows=2 columns=4\n') &&
        snapshot.contains('primary row=1') &&
        snapshot.contains('text="new!"'),
    'primary grid is retained while alternate is active',
  );
  _expect(
    snapshot.contains('screen name=alternate rows=2 columns=4\n') &&
        snapshot.contains('alternate row=0') &&
        snapshot.contains('text="alt!"'),
    'alternate grid is independently captured',
  );
}

void _testSnapshotIncludesOwnedParserCounters() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (_) => false,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('5n'),
      0x1b,
      0x5b,
      0x3f,
      ...ascii.encode('9999h'),
      0x1b,
      0x5b,
      0x31,
    ]),
  );
  parser.finish();

  final String snapshot = const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
  _expect(
    snapshot.contains(
      'parser unsupported_controls=0 unsupported_sequences=1 '
      'cancel=0 limit=0 malformed=0 incomplete=1 '
      'replies_accepted=0 replies_rejected=1\n',
    ),
    'owned parser counters distinguish unsupported, incomplete, and reply state',
  );

  final TerminalScreenParserSink unrelated =
      TerminalScreenParserSink.forScreenSet(
        TerminalScreenSet(rows: 2, columns: 4),
      );
  _expectThrows<ArgumentError>(
    () => const TerminalSnapshotFormatter().formatScreenSet(
      screens,
      parserSink: unrelated,
    ),
    'unrelated parser sink is rejected',
  );
}

void _testFormattingDoesNotMutateTerminalState() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  _writeRow(screens.primary, 0, 'stay');
  screens.primary.clearDamage();
  screens.primary.acknowledgeFullSnapshot();
  screens.viewport.scrollToBottom();

  final int primaryGeneration = screens.primary.generation;
  final int alternateGeneration = screens.alternate.generation;
  final int viewportGeneration = screens.viewport.generation;
  final int viewportOffset = screens.viewport.offset;
  final int primaryViewportOffset = screens.viewport.primaryOffset;
  final List<(int, int)> damage = <(int, int)>[
    for (int row = 0; row < screens.primary.rows; row++)
      (screens.primary.dirtyStartAt(row), screens.primary.dirtyEndAt(row)),
  ];

  const TerminalSnapshotFormatter().formatScreenSet(screens);
  _expect(
    screens.primary.generation == primaryGeneration &&
        screens.alternate.generation == alternateGeneration &&
        screens.viewport.generation == viewportGeneration &&
        screens.viewport.offset == viewportOffset &&
        screens.viewport.primaryOffset == primaryViewportOffset &&
        !screens.primary.fullSnapshotRequired,
    'formatting preserves screen, viewport, and snapshot generations',
  );
  for (int row = 0; row < screens.primary.rows; row++) {
    _expect(
      damage[row] ==
          (screens.primary.dirtyStartAt(row), screens.primary.dirtyEndAt(row)),
      'formatting preserves row $row damage',
    );
  }
}

void _testSnapshotLimitsRejectIncompleteOracles() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 3);
  final int style = screen.styleTable.intern(TerminalStyleAttributes.bold);
  screen.setNarrowCell(0, 0, 0x41, style: style);

  _expectLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxRows: 1),
    ).formatScreen(screen),
    'rows',
    2,
    1,
  );
  _expectLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxCells: 5),
    ).formatScreen(screen),
    'cells',
    6,
    5,
  );
  _expectLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxStyleDefinitions: 0),
    ).formatScreen(screen),
    'style definitions',
    1,
    0,
  );
  _expectLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxOutputCharacters: 32),
    ).formatScreen(screen),
    'output characters',
    null,
    32,
  );
}

void _testParserChunkPlansProduceIdenticalSnapshots() {
  final Uint8List input = Uint8List.fromList(<int>[
    ...utf8.encode('A日é'),
    0x1b,
    0x5b,
    ...ascii.encode('1;34m'),
    ...utf8.encode('Z'),
    0x0d,
    0x0a,
    ...ascii.encode('next'),
    0x1b,
    0x5b,
    0x3f,
    ...ascii.encode('1049h'),
    ...ascii.encode('alt'),
  ]);
  final String expected = _parseSnapshot(input, <int>[input.length]);
  for (int split = 0; split <= input.length; split++) {
    _expect(
      _parseSnapshot(input, <int>[split, input.length - split]) == expected,
      'snapshot is identical at parser split $split',
    );
  }
  _expect(
    _parseSnapshot(input, List<int>.filled(input.length, 1)) == expected,
    'snapshot is identical for bytewise parser chunks',
  );
}

void _testSnapshotComparisonExactMatchAndMismatch() {
  const TerminalSnapshotComparator comparator = TerminalSnapshotComparator();
  const String expected = 'header\nrow text="a b"\nmode=true\nend\n';
  final TerminalSnapshotComparison match = comparator.compare(
    expected,
    expected,
  );
  _expect(
    match.matches &&
        match.firstDifferenceOffset == null &&
        match.firstDifferenceLine == null &&
        match.firstDifferenceColumn == null &&
        match.diagnostic.isEmpty,
    'exact comparison has an allocation-small success result',
  );
  match.requireMatch('matching snapshot');

  const String actual = 'header\nrow text="a\tb"\nmode=true\nend\n';
  final TerminalSnapshotComparison mismatch = comparator.compare(
    expected,
    actual,
  );
  _expect(!mismatch.matches, 'different whitespace does not compare equal');
  _expect(
    mismatch.firstDifferenceOffset == expected.indexOf(' b') &&
        mismatch.firstDifferenceLine == 2 &&
        mismatch.firstDifferenceColumn == 12,
    'first difference exposes exact offset, line, and UTF-16 column',
  );
  _expect(
    mismatch.diagnostic.contains(
          'terminal snapshot mismatch at line 2, column 12 '
          '(UTF-16 code units)',
        ) &&
        mismatch.diagnostic.contains('expected next: 0x0020 " "') &&
        mismatch.diagnostic.contains(r'actual next:   0x0009 "\t"') &&
        mismatch.diagnostic.contains(r'> 2 | "row text=\"a b\""') &&
        mismatch.diagnostic.contains(r'> 2 | "row text=\"a\tb\""'),
    'diagnostic makes whitespace visible in both bounded contexts',
  );
}

void _testSnapshotComparisonEndAndControlDiagnostics() {
  const TerminalSnapshotComparator comparator = TerminalSnapshotComparator();
  final TerminalSnapshotComparison missingNewline = comparator.compare(
    'same\n',
    'same',
  );
  _expect(
    missingNewline.firstDifferenceLine == 1 &&
        missingNewline.firstDifferenceColumn == 5 &&
        missingNewline.diagnostic.contains(r'expected next: 0x000a "\n"') &&
        missingNewline.diagnostic.contains('actual next:   <end-of-snapshot>'),
    'trailing newline versus end-of-snapshot is explicit',
  );

  final TerminalSnapshotComparison missingLine = comparator.compare(
    'first\nsecond\n',
    'first\n',
  );
  _expect(
    missingLine.firstDifferenceLine == 2 &&
        missingLine.firstDifferenceColumn == 1 &&
        missingLine.diagnostic.contains('actual next:   <end-of-snapshot>') &&
        missingLine.diagnostic.contains('> 2 | ""'),
    'missing whole line receives an end marker at its expected line',
  );
}

void _testSnapshotComparisonLimitsAndTypedFailure() {
  const TerminalSnapshotComparator bounded = TerminalSnapshotComparator(
    limits: TerminalSnapshotComparisonLimits(
      maxSnapshotCharacters: 128,
      maxDiagnosticCharacters: 160,
      contextLines: 1,
      maxContextLineCharacters: 12,
    ),
  );
  final String expected = '${'a'.padRight(80, 'a')}X\nnext\n';
  final String actual = '${'a'.padRight(80, 'a')}Y\nnext\n';
  final TerminalSnapshotComparison mismatch = bounded.compare(expected, actual);
  _expect(
    mismatch.diagnostic.length <= 160 &&
        mismatch.diagnostic.endsWith('… diagnostic truncated\n'),
    'diagnostic truncation is explicit and within its hard cap',
  );
  var mismatchThrown = false;
  try {
    mismatch.requireMatch('bounded state oracle');
  } on TerminalSnapshotMismatchException catch (error) {
    mismatchThrown = true;
    _expect(
      error.description == 'bounded state oracle' &&
          error.line == 1 &&
          error.column == 81 &&
          error.diagnostic == mismatch.diagnostic &&
          !error.diagnostic.contains(expected),
      'typed mismatch carries only bounded context and location',
    );
  }
  _expect(mismatchThrown, 'requireMatch throws a typed mismatch');

  _expectLimit(
    () => bounded.compare('b'.padRight(129, 'b'), ''),
    'expected snapshot characters',
    129,
    128,
  );
  _expectLimit(
    () => bounded.compare('', 'b'.padRight(129, 'b')),
    'actual snapshot characters',
    129,
    128,
  );
}

String _parseSnapshot(Uint8List input, List<int> chunks) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 8);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int length in chunks) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  _expect(offset == input.length, 'snapshot chunk plan consumes all input');
  parser.finish();
  return const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
}

void _writeRow(TerminalScreen screen, int row, String text) {
  for (int column = 0; column < text.length; column++) {
    screen.setNarrowCell(row, column, text.codeUnitAt(column));
  }
}

void _expectLimit(
  void Function() callback,
  String resource,
  int? actual,
  int limit,
) {
  try {
    callback();
  } on TerminalSnapshotLimitException catch (error) {
    _expect(error.resource == resource, '$resource limit resource');
    if (actual != null) {
      _expect(error.actual == actual, '$resource limit actual');
    } else {
      _expect(error.actual > limit, '$resource limit actual exceeds limit');
    }
    _expect(error.limit == limit, '$resource limit value');
    return;
  }
  throw StateError('Expected TerminalSnapshotLimitException for $resource');
}

void _expectThrows<T extends Object>(
  void Function() callback,
  String description,
) {
  try {
    callback();
  } on Object catch (error) {
    if (error is T) {
      return;
    }
    throw StateError('Expected $T for $description, got ${error.runtimeType}');
  }
  throw StateError('Expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}
