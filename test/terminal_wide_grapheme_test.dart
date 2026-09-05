import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalWideGraphemeTests();

void runTerminalWideGraphemeTests() {
  _testAtomicWideAndGraphemeStorage();
  _testStreamingPrintAndEdgeWrapping();
  _testEditingAndScrollingRepairWideBoundaries();
  _testParserUnicodeChunkIndependence();
  _testBoundedAndMalformedStreams();
  _testScreenSetSharesGraphemeResources();
  _testDeterministicMutationInvariantSweep();
}

void _testAtomicWideAndGraphemeStorage() {
  final TerminalGraphemeTable graphemes = TerminalGraphemeTable();
  final TerminalScreen screen = TerminalScreen(
    rows: 2,
    columns: 6,
    graphemeTable: graphemes,
  );
  screen.setWideCell(
    0,
    1,
    0x754c,
    foreground: 0x80112233,
    background: 7,
    style: 12,
    hyperlink: 13,
    isProtected: true,
  );
  _expect(
    screen.widthFlagsAt(0, 1) ==
            (TerminalCellFlags.wide | TerminalCellFlags.protected) &&
        screen.widthFlagsAt(0, 2) ==
            (TerminalCellFlags.continuation | TerminalCellFlags.protected),
    'wide scalar stores one lead and continuation',
  );
  _expect(
    screen.contentAt(0, 2) == 0 &&
        screen.foregroundAt(0, 2) == 0x80112233 &&
        screen.backgroundAt(0, 2) == 7 &&
        screen.styleAt(0, 2) == 12 &&
        screen.hyperlinkAt(0, 2) == 13,
    'continuation copies all presentation fields',
  );
  _assertTopology(screen, 'initial wide scalar');

  screen.setNarrowCell(0, 2, 0x58);
  _expect(
    screen.contentAt(0, 1) == 0 && screen.contentAt(0, 2) == 0x58,
    'overwriting continuation clears its lead atomically',
  );
  _assertTopology(screen, 'continuation overwrite');

  final int narrowId = graphemes.intern(const <int>[0x41, 0x0301]);
  final int wideId = graphemes.intern(const <int>[0x00a9, 0xfe0f]);
  final int zeroId = graphemes.intern(const <int>[0x0301]);
  screen.setGraphemeCell(1, 0, narrowId, foreground: 2);
  screen.setGraphemeCell(1, 2, wideId, background: 3);
  _expect(
    screen.contentAt(1, 0) == narrowId &&
        screen.widthFlagsAt(1, 0) ==
            (TerminalCellFlags.narrow | TerminalCellFlags.grapheme),
    'narrow grapheme cell stores resource ID',
  );
  _expect(
    screen.contentAt(1, 2) == wideId &&
        screen.widthFlagsAt(1, 2) ==
            (TerminalCellFlags.wide | TerminalCellFlags.grapheme) &&
        screen.widthFlagsAt(1, 3) == TerminalCellFlags.continuation,
    'wide grapheme stores ID only on lead',
  );
  _assertTopology(screen, 'direct grapheme cells');

  final String state = _screenKey(screen);
  final int generation = screen.generation;
  for (final void Function() invalid in <void Function()>[
    () => screen.setWideCell(0, 5, 0x754c),
    () => screen.setWideCell(0, 0, 0x41),
    () => screen.setNarrowCell(0, 0, 0x754c),
    () => screen.setGraphemeCell(0, 0, zeroId),
    () => screen.setGraphemeCell(0, 0, 65534),
  ]) {
    _expectThrowsArgumentError(invalid, 'invalid width write is rejected');
    _expect(_screenKey(screen) == state, 'invalid width write is atomic');
    _expect(screen.generation == generation, 'invalid write generation stable');
  }
}

void _testStreamingPrintAndEdgeWrapping() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 4);
  screen.setCurrentRendition(
    foreground: 4,
    background: 5,
    styleAttributes: TerminalStyleAttributes.bold,
  );
  screen.printScalar(0x41);
  screen.printScalar(0x0301);
  final int accentId = screen.contentAt(0, 0);
  _expect(
    screen.widthFlagsAt(0, 0) ==
            (TerminalCellFlags.narrow | TerminalCellFlags.grapheme) &&
        _equals(screen.graphemeTable.scalarsAt(accentId), const <int>[
          0x41,
          0x0301,
        ]),
    'combining mark extends the preceding scalar',
  );
  screen.printScalar(0x754c);
  _expect(
    screen.widthFlagsAt(0, 1) == TerminalCellFlags.wide &&
        screen.widthFlagsAt(0, 2) == TerminalCellFlags.continuation,
    'classified CJK print occupies two cells',
  );
  _expect(
    screen.foregroundAt(0, 1) == 4 &&
        screen.foregroundAt(0, 2) == 4 &&
        screen.backgroundAt(0, 2) == 5 &&
        screen.styleAt(0, 2) == screen.currentStyleId,
    'wide continuation inherits current rendition',
  );
  screen.printScalar(0x1f600);
  _expect(
    screen.contentAt(1, 0) == 0x1f600 &&
        screen.widthFlagsAt(1, 0) == TerminalCellFlags.wide &&
        screen.widthFlagsAt(1, 1) == TerminalCellFlags.continuation,
    'wide glyph wraps before a last-column orphan can be written',
  );
  _expect(
    screen.rowFlagsAt(0) & TerminalRowFlags.softWrapped != 0 &&
        screen.logicalLineIdAt(0) == screen.logicalLineIdAt(1),
    'pre-wrap preserves logical-line identity',
  );
  _assertTopology(screen, 'mixed streaming print');

  final TerminalScreen variation = TerminalScreen(rows: 2, columns: 4);
  variation.setCursorPosition(0, 3);
  variation.printScalar(0x00a9);
  variation.printScalar(0xfe0f);
  _expect(
    variation.contentAt(0, 3) == 0 &&
        variation.widthFlagsAt(1, 0) ==
            (TerminalCellFlags.wide | TerminalCellFlags.grapheme) &&
        _equals(
          variation.graphemeTable.scalarsAt(variation.contentAt(1, 0)),
          const <int>[0x00a9, 0xfe0f],
        ),
    'VS16 width growth relocates a last-column base atomically',
  );
  _assertTopology(variation, 'variation width growth');

  final TerminalScreen narrowOnly = TerminalScreen(rows: 1, columns: 1);
  narrowOnly.printScalar(0x754c);
  _expect(
    narrowOnly.contentAt(0, 0) == 0xfffd &&
        narrowOnly.widthFlagsAt(0, 0) == TerminalCellFlags.narrow,
    'one-column region contains an unrepresentable wide glyph safely',
  );
  _assertTopology(narrowOnly, 'one-column fallback');

  final TerminalScreen noWrap = TerminalScreen(rows: 1, columns: 4);
  noWrap.setMode(TerminalScreenMode.autoWrap, false);
  noWrap.setCursorPosition(0, 3);
  noWrap.printScalar(0x754c);
  _expect(
    noWrap.contentAt(0, 3) == 0xfffd && !noWrap.wrapPending,
    'wide glyph at a no-wrap edge uses the contained replacement',
  );
  _assertTopology(noWrap, 'no-wrap wide fallback');

  final TerminalScreen inserted = TerminalScreen(rows: 1, columns: 8);
  for (final int scalar in 'ABCDE'.codeUnits) {
    inserted.printNarrowScalar(scalar);
  }
  inserted.setCursorPosition(0, 1);
  inserted.setMode(TerminalScreenMode.insert, true);
  inserted.printScalar(0x754c);
  _expect(
    inserted.contentAt(0, 0) == 0x41 &&
        inserted.contentAt(0, 1) == 0x754c &&
        inserted.contentAt(0, 3) == 0x42,
    'insert-mode wide print shifts by two cells',
  );
  _assertTopology(inserted, 'insert-mode wide print');

  final TerminalScreen pending = TerminalScreen(rows: 1, columns: 6);
  pending.printScalar(0x0301);
  pending.printScalar(0x41);
  pending.printScalar(0x0600);
  pending.printScalar(0x42);
  _expect(
    pending.contentAt(0, 0) == 0x41 &&
        _equals(
          pending.graphemeTable.scalarsAt(pending.contentAt(0, 1)),
          const <int>[0x0600, 0x42],
        ),
    'standalone Extend is dropped while Prepend waits for its base',
  );
  _assertTopology(pending, 'zero-width and prepend printing');
}

void _testEditingAndScrollingRepairWideBoundaries() {
  final TerminalScreen erase = TerminalScreen(rows: 2, columns: 6);
  erase.setWideCell(0, 1, 0x754c);
  erase.setCursorPosition(0, 2);
  erase.eraseCharacters(1);
  _expect(
    erase.contentAt(0, 1) == 0 && erase.contentAt(0, 2) == 0,
    'ECH on continuation clears the complete pair',
  );
  _assertTopology(erase, 'ECH repair');
  erase.setWideCell(0, 1, 0x754c);
  erase.setCursorPosition(0, 2);
  erase.eraseInLine(0);
  _assertTopology(erase, 'EL repair');
  erase.setWideCell(0, 1, 0x754c);
  erase.setCursorPosition(0, 2);
  erase.eraseInDisplay(0);
  _assertTopology(erase, 'ED repair');

  final TerminalScreen characters = TerminalScreen(rows: 1, columns: 8);
  characters.setWideCell(0, 2, 0x754c);
  characters.setNarrowCell(0, 4, 0x58);
  characters.setCursorPosition(0, 3);
  characters.insertCharacters(1);
  _assertTopology(characters, 'ICH at continuation');
  characters.setWideCell(0, 2, 0x754c);
  characters.setCursorPosition(0, 3);
  characters.deleteCharacters(1);
  _assertTopology(characters, 'DCH at continuation');

  final TerminalScreen fullScroll = TerminalScreen(rows: 3, columns: 6);
  fullScroll.setWideCell(1, 2, 0x754c, foreground: 6);
  fullScroll.scrollUp(1);
  _expect(
    fullScroll.contentAt(0, 2) == 0x754c && fullScroll.foregroundAt(0, 3) == 6,
    'full-width ring scroll preserves complete pair',
  );
  _assertTopology(fullScroll, 'full-width ring scroll');
  fullScroll.scrollDown(1);
  _assertTopology(fullScroll, 'full-width reverse scroll');

  final TerminalScreen rectangle = TerminalScreen(rows: 3, columns: 6);
  rectangle.setWideCell(1, 0, 0x754c);
  rectangle.setWideCell(1, 4, 0x754c);
  rectangle.setHorizontalMargins(1, 4);
  rectangle.setMode(TerminalScreenMode.horizontalMargins, true);
  rectangle.scrollUp(1);
  _assertTopology(rectangle, 'partial-width scroll clipping both pair edges');
  rectangle.setCursorPosition(1, 1);
  rectangle.insertLines(1);
  _assertTopology(rectangle, 'partial-width insert line');
  rectangle.deleteLines(1);
  _assertTopology(rectangle, 'partial-width delete line');
  rectangle.resetScreen();
  _assertTopology(rectangle, 'screen reset');
}

void _testParserUnicodeChunkIndependence() {
  final Uint8List input = Uint8List.fromList(
    utf8.encode(
      String.fromCharCodes(const <int>[
        0x41,
        0x0301,
        0x754c,
        0x1f469,
        0x200d,
        0x1f4bb,
        0x1f1ef,
        0x1f1f5,
        0x1100,
        0x1161,
        0x11a8,
        0x0915,
        0x094d,
        0x0915,
      ]),
    ),
  );
  final TerminalScreen whole = _parseScreen(input);
  final String expected = _screenKey(whole);
  _expect(
    _equals(_cellScalars(whole, 0, 0), const <int>[0x41, 0x0301]) &&
        _equals(_cellScalars(whole, 0, 1), const <int>[0x754c]) &&
        _equals(_cellScalars(whole, 0, 3), const <int>[
          0x1f469,
          0x200d,
          0x1f4bb,
        ]) &&
        _equals(_cellScalars(whole, 0, 5), const <int>[0x1f1ef, 0x1f1f5]) &&
        _equals(_cellScalars(whole, 0, 7), const <int>[
          0x1100,
          0x1161,
          0x11a8,
        ]) &&
        _equals(_cellScalars(whole, 0, 9), const <int>[
          0x0915,
          0x094d,
          0x0915,
        ]) &&
        whole.cursorColumn == 10,
    'parser forms combining, CJK, ZWJ, RI, Hangul, and Indic cells',
  );
  for (int split = 0; split <= input.length; split++) {
    _expect(
      _parseKey(input, <int>[split, input.length - split]) == expected,
      'Unicode parser output is stable at byte split $split',
    );
  }
  _expect(
    _parseKey(input, List<int>.filled(input.length, 1)) == expected,
    'Unicode parser output is stable bytewise',
  );
}

void _testBoundedAndMalformedStreams() {
  final TerminalGraphemeTable bounded = TerminalGraphemeTable(
    capacity: 1,
    maximumScalarCount: 2,
    maximumClusterLength: 2,
  );
  final TerminalScreen screen = TerminalScreen(
    rows: 2,
    columns: 8,
    graphemeTable: bounded,
  );
  screen.printScalar(0x41);
  screen.printScalar(0x0301);
  screen.printScalar(0x0302);
  screen.printScalar(0x42);
  _expect(
    bounded.definitionCount == 1 && bounded.scalarCount == 2,
    'screen cannot exceed shared grapheme resource limits',
  );
  _assertTopology(screen, 'grapheme exhaustion containment');

  final List<int> bytes = <int>[0x41];
  for (int count = 0; count < 500; count++) {
    bytes.addAll(const <int>[0xcc, 0x81]);
  }
  bytes.addAll(<int>[0xff, ...utf8.encode('界')]);
  final Uint8List malformed = Uint8List.fromList(bytes);
  final TerminalScreen parsed = TerminalScreen(rows: 3, columns: 20);
  final VtParser parser = VtParser(sink: TerminalScreenParserSink(parsed));
  parser.parse(malformed);
  parser.finish();
  _expect(
    parsed.graphemeTable.definitionCount <=
        parsed.graphemeTable.maximumClusterLength,
    'overlong and malformed streams retain bounded grapheme definitions',
  );
  _assertTopology(parsed, 'overlong and malformed parser stream');

  final TerminalScreen control = TerminalScreen(rows: 1, columns: 4);
  final VtParser controlParser = VtParser(
    sink: TerminalScreenParserSink(control),
  );
  controlParser.parse(Uint8List.fromList(<int>[0x41, 0x0d, 0xcc, 0x81, 0x42]));
  controlParser.finish();
  _expect(
    control.widthFlagsAt(0, 0) == TerminalCellFlags.narrow,
    'control action prevents a later combining mark crossing the boundary',
  );
  _assertTopology(control, 'control-separated grapheme stream');
}

void _testScreenSetSharesGraphemeResources() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  _expect(
    identical(screens.primary.graphemeTable, screens.graphemeTable) &&
        identical(screens.alternate.graphemeTable, screens.graphemeTable),
    'primary and alternate share grapheme meanings',
  );
  screens.primary.printScalar(0x41);
  screens.primary.printScalar(0x0301);
  final int id = screens.primary.contentAt(0, 0);
  screens.setAlternateMode47(true);
  screens.alternate.setGraphemeCell(0, 0, id);
  screens.setAlternateMode47(false);
  screens.primary.printScalar(0x0302);
  _expect(
    _equals(
      screens.graphemeTable.scalarsAt(screens.primary.contentAt(0, 0)),
      const <int>[0x41, 0x0301],
    ),
    'screen switching closes the prior streaming grapheme',
  );
  _assertTopology(screens.primary, 'primary after screen switch');
  _assertTopology(screens.alternate, 'alternate after screen switch');
}

void _testDeterministicMutationInvariantSweep() {
  final TerminalScreen screen = TerminalScreen(rows: 5, columns: 12);
  var state = 0x6d2b79f5;
  int next() {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return state;
  }

  for (int iteration = 0; iteration < 768; iteration++) {
    final int row = next() % screen.rows;
    final int column = next() % screen.columns;
    screen.setCursorPosition(row, column);
    switch (next() % 12) {
      case 0:
        screen.setNarrowCell(row, column, 0x41 + next() % 26);
      case 1:
        if (column + 1 < screen.columns) {
          screen.setWideCell(row, column, 0x754c);
        }
      case 2:
        screen.eraseCharacters(next() % 5 + 1);
      case 3:
        screen.insertCharacters(next() % 5 + 1);
      case 4:
        screen.deleteCharacters(next() % 5 + 1);
      case 5:
        screen.eraseInLine(next() % 3);
      case 6:
        screen.eraseInDisplay(next() % 3);
      case 7:
        screen.scrollUp(next() % 3 + 1);
      case 8:
        screen.scrollDown(next() % 3 + 1);
      case 9:
        screen.printScalar(0x1f600);
      case 10:
        screen.printScalar(0x41);
        screen.printScalar(0x0301);
      case 11:
        if (iteration % 97 == 0) {
          screen.resetScreen();
        }
    }
    _assertTopology(screen, 'deterministic mutation $iteration');
  }
}

String _parseKey(Uint8List input, [List<int>? chunks]) {
  return _screenKey(_parseScreen(input, chunks));
}

TerminalScreen _parseScreen(Uint8List input, [List<int>? chunks]) {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 20);
  final VtParser parser = VtParser(sink: TerminalScreenParserSink(screen));
  var offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  parser.finish();
  _assertTopology(screen, 'parsed Unicode stream');
  return screen;
}

List<int> _cellScalars(TerminalScreen screen, int row, int column) {
  final int flags = screen.widthFlagsAt(row, column);
  final int content = screen.contentAt(row, column);
  return flags & TerminalCellFlags.grapheme != 0
      ? screen.graphemeTable.scalarsAt(content)
      : <int>[content];
}

String _screenKey(TerminalScreen screen) {
  final StringBuffer result = StringBuffer(
    '${screen.cursorRow},${screen.cursorColumn},${screen.wrapPending}|',
  );
  for (int row = 0; row < screen.rows; row++) {
    for (int column = 0; column < screen.columns; column++) {
      final int flags = screen.widthFlagsAt(row, column);
      result
        ..write(screen.contentAt(row, column))
        ..write('/')
        ..write(flags)
        ..write('/');
      if (flags & TerminalCellFlags.grapheme != 0) {
        result.write(
          screen.graphemeTable.scalarsAt(screen.contentAt(row, column)),
        );
      }
      result.write(',');
    }
    result.write(';');
  }
  return result.toString();
}

void _assertTopology(TerminalScreen screen, String description) {
  try {
    screen.validateCellTopology();
  } on Object catch (error) {
    throw StateError('$description: $error');
  }
}

bool _equals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(description);
  }
}

void _expectThrowsArgumentError(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError(description);
}
