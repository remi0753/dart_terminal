import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalReflowTests();

void runTerminalReflowTests() {
  _testNarrowerWiderLogicalLineRoundTrip();
  _testStateMarginsTabsAndWideCursorNormalization();
  _testHeightWindowKeepsActiveCursor();
  _testOneColumnWideContainment();
  _testResizeDimensionMatrix();
  _testAtomicPrimaryAlternateResize();
}

void _testNarrowerWiderLogicalLineRoundTrip() {
  final TerminalScreen source = TerminalScreen(rows: 4, columns: 6);
  source.setCurrentRendition(
    foreground: 4,
    background: 0x80112233,
    styleAttributes: TerminalStyleAttributes.bold,
  );
  for (final int scalar in 'ABCDE界FG'.runes) {
    source.printScalar(scalar);
  }
  final int logicalLineId = source.logicalLineIdAt(0);
  source.setRowFlags(0, source.rowFlagsAt(0) | TerminalRowFlags.prompt);
  source.setRowFlags(
    1,
    source.rowFlagsAt(1) | TerminalRowFlags.output | TerminalRowFlags.hardBreak,
  );
  source.setCursorPosition(0, 4);
  source.saveCursor();
  source.setCursorPosition(1, 4);
  source.setNarrowCell(2, 3, 0, background: 5);
  final String sourceState = _screenState(source);

  final TerminalScreen narrow = source.resized(rows: 5, columns: 4);
  _expect(source.rows == 4 && source.columns == 6, 'source size is unchanged');
  _expect(_screenState(source) == sourceState, 'source state is unchanged');
  _expect(
    identical(source.styleTable, narrow.styleTable) &&
        identical(source.palette, narrow.palette) &&
        identical(source.graphemeTable, narrow.graphemeTable),
    'replacement shares immutable and presentation resources',
  );
  _expect(
    String.fromCharCodes(_visibleScalars(narrow)).startsWith('ABCDE界FG'),
    'narrow reflow preserves logical cell order',
  );
  _expect(
    narrow.cursorRow == 2 &&
        narrow.cursorColumn == 1 &&
        narrow.savedCursorRow == 1 &&
        narrow.savedCursorColumn == 0,
    'active and saved cursor map through narrow reflow',
  );
  _expect(
    narrow.logicalLineIdAt(0) == logicalLineId &&
        narrow.logicalLineIdAt(1) == logicalLineId &&
        narrow.logicalLineIdAt(2) == logicalLineId,
    'rewrapped rows retain logical-line identity',
  );
  _expect(
    narrow.rowFlagsAt(0) & TerminalRowFlags.softWrapped != 0 &&
        narrow.rowFlagsAt(1) & TerminalRowFlags.softWrapped != 0 &&
        narrow.rowFlagsAt(2) & TerminalRowFlags.hardBreak != 0 &&
        narrow.rowFlagsAt(2) & TerminalRowFlags.softWrapped == 0,
    'soft and hard row boundaries are recomputed',
  );
  _expect(
    narrow.rowFlagsAt(0) & TerminalRowFlags.prompt != 0 &&
        narrow.rowFlagsAt(1) & TerminalRowFlags.output != 0,
    'semantic row classifications survive reflow',
  );
  final ({int row, int column}) wide = _findScalar(narrow, 0x754c);
  _expect(
    narrow.foregroundAt(wide.row, wide.column) == 4 &&
        narrow.backgroundAt(wide.row, wide.column + 1) == 0x80112233 &&
        narrow.styleAt(wide.row, wide.column + 1) == source.currentStyleId,
    'wide presentation fields survive reflow',
  );
  _expect(
    narrow.backgroundAt(3, 3) == 5,
    'noncanonical styled trailing blank remains retained',
  );
  _assertReplacement(narrow, source.generation, 'narrow replacement');

  final TerminalScreen wideAgain = narrow.resized(rows: 5, columns: 8);
  _expect(
    String.fromCharCodes(_visibleScalars(wideAgain)).startsWith('ABCDE界FG'),
    'wider round trip preserves retained logical content',
  );
  _expect(
    wideAgain.cursorRow == 1 &&
        wideAgain.cursorColumn == 1 &&
        wideAgain.savedCursorRow == 0 &&
        wideAgain.savedCursorColumn == 4,
    'cursor mappings remain stable when widening',
  );
  _assertReplacement(wideAgain, narrow.generation, 'wide replacement');
}

void _testStateMarginsTabsAndWideCursorNormalization() {
  final TerminalScreen source = TerminalScreen(rows: 3, columns: 10);
  source.clearAllTabStops();
  source.setTabStop(3);
  source.setMode(TerminalScreenMode.insert, true);
  source.setMode(TerminalScreenMode.autoWrap, false);
  source.setMode(TerminalScreenMode.reverseVideo, true);
  source.setCursorPresentation(
    visible: false,
    blinking: false,
    shape: TerminalCursorShape.bar,
  );
  source.setVerticalMargins(1, 2);
  source.setHorizontalMargins(2, 8);
  source.setMode(TerminalScreenMode.horizontalMargins, true);
  source.setMode(TerminalScreenMode.origin, true);
  source.setCurrentRendition(
    foreground: 2,
    background: 3,
    styleAttributes: TerminalStyleAttributes.italic,
  );
  source.setCursorPosition(2, 7);
  source.saveCursor();

  final TerminalScreen resized = source.resized(rows: 4, columns: 17);
  _expect(
    resized.topMargin == 0 &&
        resized.bottomMargin == 3 &&
        resized.leftMargin == 0 &&
        resized.rightMargin == 16 &&
        !resized.modeEnabled(TerminalScreenMode.origin) &&
        !resized.modeEnabled(TerminalScreenMode.horizontalMargins),
    'resize resets margins and dependent modes safely',
  );
  _expect(
    resized.modeEnabled(TerminalScreenMode.insert) &&
        !resized.modeEnabled(TerminalScreenMode.autoWrap) &&
        resized.modeEnabled(TerminalScreenMode.reverseVideo),
    'independent modes survive resize',
  );
  _expect(
    !resized.cursorVisible &&
        !resized.cursorBlinking &&
        resized.cursorShape == TerminalCursorShape.bar,
    'cursor presentation survives resize',
  );
  _expect(
    resized.currentForeground == 2 &&
        resized.currentBackground == 3 &&
        resized.currentStyleId == source.currentStyleId &&
        resized.savedForeground == 2 &&
        resized.savedBackground == 3 &&
        resized.savedStyleId == source.currentStyleId,
    'current and saved rendition survive resize',
  );
  _expect(
    resized.isTabStop(3) && !resized.isTabStop(8) && resized.isTabStop(16),
    'old tab choices and new default tab columns coexist',
  );
  _assertReplacement(resized, source.generation, 'stateful replacement');

  final TerminalScreen wideCursor = TerminalScreen(rows: 1, columns: 4);
  wideCursor.printScalar(0x41);
  wideCursor.printScalar(0x42);
  wideCursor.printScalar(0x754c);
  _expect(wideCursor.wrapPending, 'wide source reaches wrap pending');
  final TerminalScreen mapped = wideCursor.resized(rows: 2, columns: 4);
  _expect(
    mapped.cursorRow == 0 &&
        mapped.cursorColumn == 2 &&
        mapped.widthFlagsAt(0, 2) == TerminalCellFlags.wide &&
        mapped.wrapPending,
    'wide continuation cursor maps to its lead and preserves edge wrap',
  );
  _assertReplacement(mapped, wideCursor.generation, 'wide-cursor replacement');
}

void _testHeightWindowKeepsActiveCursor() {
  final TerminalScreen source = TerminalScreen(rows: 4, columns: 4);
  for (int row = 0; row < 4; row++) {
    source.setNarrowCell(row, 0, 0x41 + row);
  }
  source.setCursorPosition(3, 0);
  source.saveCursor();
  source.setCursorPosition(0, 0);
  final TerminalScreen top = source.resized(rows: 2, columns: 4);
  _expect(
    top.contentAt(0, 0) == 0x41 &&
        top.contentAt(1, 0) == 0x42 &&
        top.cursorRow == 0 &&
        top.savedCursorRow == 1,
    'height shrink prioritizes active cursor and clamps dropped saved cursor',
  );
  _assertReplacement(top, source.generation, 'top-anchored replacement');

  source.setCursorPosition(3, 0);
  final TerminalScreen bottom = source.resized(rows: 2, columns: 4);
  _expect(
    bottom.contentAt(0, 0) == 0x43 &&
        bottom.contentAt(1, 0) == 0x44 &&
        bottom.cursorRow == 1,
    'ordinary height shrink retains newest bottom rows around cursor',
  );
  _assertReplacement(bottom, source.generation, 'bottom replacement');
}

void _testOneColumnWideContainment() {
  final TerminalScreen source = TerminalScreen(rows: 1, columns: 4);
  source.setWideCell(0, 0, 0x754c, foreground: 2, background: 3);
  final TerminalScreen resized = source.resized(rows: 2, columns: 1);
  _expect(
    resized.contentAt(0, 0) == 0xfffd &&
        resized.widthFlagsAt(0, 0) == TerminalCellFlags.narrow &&
        resized.foregroundAt(0, 0) == 2 &&
        resized.backgroundAt(0, 0) == 3,
    'one-column reflow contains an unrepresentable wide cell',
  );
  _assertReplacement(resized, source.generation, 'one-column replacement');
}

void _testResizeDimensionMatrix() {
  final TerminalScreen source = TerminalScreen(rows: 5, columns: 9);
  for (final int scalar in 'AB界e\u0301👩‍💻CD'.runes) {
    source.printScalar(scalar);
  }
  source.setNarrowCell(3, 7, 0, background: 6);
  source.setCursorPosition(1, 2);
  source.saveCursor();
  source.setCursorPosition(3, 7);
  final String sourceState = _screenState(source);

  for (int rows = 1; rows <= 7; rows++) {
    for (int columns = 1; columns <= 12; columns++) {
      final TerminalScreen resized = source.resized(
        rows: rows,
        columns: columns,
      );
      _expect(
        resized.rows == rows && resized.columns == columns,
        'dimension matrix produces ${rows}x$columns',
      );
      _expect(
        identical(resized.styleTable, source.styleTable) &&
            identical(resized.palette, source.palette) &&
            identical(resized.graphemeTable, source.graphemeTable),
        'dimension matrix preserves resources at ${rows}x$columns',
      );
      _assertReplacement(
        resized,
        source.generation,
        'dimension matrix ${rows}x$columns',
      );
    }
  }
  _expect(
    _screenState(source) == sourceState,
    'dimension matrix leaves its source unchanged',
  );
}

void _testAtomicPrimaryAlternateResize() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  for (final int scalar in 'AB界'.runes) {
    screens.primary.printScalar(scalar);
  }
  screens.setAlternateMode47(true);
  screens.alternate.printScalar(0x1f600);
  final TerminalScreen oldPrimary = screens.primary;
  final TerminalScreen oldAlternate = screens.alternate;
  final int generation = screens.transitionGeneration;
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );

  screens.resize(rows: 3, columns: 4);
  _expect(
    !identical(screens.primary, oldPrimary) &&
        !identical(screens.alternate, oldAlternate) &&
        screens.primary.rows == 3 &&
        screens.primary.columns == 4 &&
        screens.alternate.rows == 3 &&
        screens.alternate.columns == 4,
    'screen set publishes two new equal-sized grids',
  );
  _expect(
    screens.usingAlternate &&
        screens.transitionGeneration == generation + 1 &&
        identical(screens.primary.styleTable, screens.styleTable) &&
        identical(screens.alternate.palette, screens.palette) &&
        identical(screens.primary.graphemeTable, screens.graphemeTable),
    'active identity, transition, and shared resources survive resize',
  );
  _expect(
    String.fromCharCodes(_visibleScalars(screens.primary)).startsWith('AB界') &&
        _visibleScalars(screens.alternate).first == 0x1f600,
    'both buffer contents survive independently',
  );
  _assertReplacement(screens.primary, oldPrimary.generation, 'primary resize');
  _assertReplacement(
    screens.alternate,
    oldAlternate.generation,
    'alternate resize',
  );
  final int primaryBeforePalette = screens.primary.generation;
  final int alternateBeforePalette = screens.alternate.generation;
  screens.alternate.setPaletteColor(1, 0x80010203);
  _expect(
    screens.primary.generation > primaryBeforePalette &&
        screens.alternate.generation > alternateBeforePalette,
    'replacement grids both observe their shared palette',
  );

  final VtParser parser = VtParser(sink: sink);
  parser.parse(Uint8List.fromList(utf8.encode('X')));
  parser.finish();
  _expect(
    _visibleScalars(screens.alternate).contains(0x58),
    'pre-existing parser sink resolves the replacement active screen',
  );

  final TerminalScreen stablePrimary = screens.primary;
  final TerminalScreen stableAlternate = screens.alternate;
  final String stablePrimaryState = _screenState(stablePrimary);
  final String stableAlternateState = _screenState(stableAlternate);
  final int stableTransition = screens.transitionGeneration;
  _expectThrowsArgumentError(
    () => screens.resize(rows: 0, columns: 4),
    'invalid set resize is rejected',
  );
  _expectThrowsRangeError(
    () => screens.resize(rows: TerminalScreen.maxRows + 1, columns: 1),
    'row allocation cap is enforced',
  );
  _expectThrowsRangeError(
    () => screens.resize(rows: 1, columns: TerminalScreen.maxColumns + 1),
    'column allocation cap is enforced',
  );
  _expectThrowsArgumentError(
    () => screens.resize(
      rows: TerminalScreen.maxRows,
      columns: TerminalScreen.maxColumns,
    ),
    'cell allocation cap is enforced',
  );
  _expect(
    identical(screens.primary, stablePrimary) &&
        identical(screens.alternate, stableAlternate) &&
        _screenState(screens.primary) == stablePrimaryState &&
        _screenState(screens.alternate) == stableAlternateState &&
        screens.transitionGeneration == stableTransition,
    'failed resize leaves both buffers and transition atomic',
  );
  screens.resize(rows: 3, columns: 4);
  _expect(
    identical(screens.primary, stablePrimary) &&
        identical(screens.alternate, stableAlternate) &&
        screens.transitionGeneration == stableTransition,
    'same-size resize is a no-op',
  );

  final TerminalScreenSet mode1049 = TerminalScreenSet(rows: 2, columns: 5);
  mode1049.primary.setCursorPosition(1, 3);
  mode1049.setAlternateMode1049(true);
  mode1049.resize(rows: 3, columns: 4);
  _expect(
    mode1049.mode1049Active && mode1049.usingAlternate,
    'active 1049 ownership survives resize',
  );
  mode1049.setAlternateMode1049(false);
  _expect(
    !mode1049.mode1049Active &&
        !mode1049.usingAlternate &&
        mode1049.primary.cursorRow == 1 &&
        mode1049.primary.cursorColumn == 3,
    '1049 return restores the resized primary saved cursor',
  );
}

void _assertReplacement(
  TerminalScreen screen,
  int previousGeneration,
  String description,
) {
  screen.validateCellTopology();
  _expect(screen.generation > previousGeneration, '$description generation');
  _expect(screen.fullSnapshotRequired, '$description full snapshot');
  for (int row = 0; row < screen.rows; row++) {
    _expect(screen.isRowDirty(row), '$description row $row dirty');
    _expect(screen.dirtyStartAt(row) == 0, '$description row $row dirty start');
    _expect(
      screen.dirtyEndAt(row) == screen.columns,
      '$description row $row dirty end',
    );
  }
  final int cursorFlags = screen.widthFlagsAt(
    screen.cursorRow,
    screen.cursorColumn,
  );
  final int savedFlags = screen.widthFlagsAt(
    screen.savedCursorRow,
    screen.savedCursorColumn,
  );
  _expect(
    cursorFlags & TerminalCellFlags.widthMask !=
            TerminalCellFlags.continuation &&
        savedFlags & TerminalCellFlags.widthMask !=
            TerminalCellFlags.continuation,
    '$description cursors do not point to continuations',
  );
}

List<int> _visibleScalars(TerminalScreen screen) {
  final List<int> result = <int>[];
  for (int row = 0; row < screen.rows; row++) {
    for (int column = 0; column < screen.columns; column++) {
      final int flags = screen.widthFlagsAt(row, column);
      if ((flags & TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
        continue;
      }
      final int content = screen.contentAt(row, column);
      if (content == 0) {
        continue;
      }
      if (flags & TerminalCellFlags.grapheme != 0) {
        result.addAll(screen.graphemeTable.scalarsAt(content));
      } else {
        result.add(content);
      }
    }
  }
  return result;
}

({int row, int column}) _findScalar(TerminalScreen screen, int scalar) {
  for (int row = 0; row < screen.rows; row++) {
    for (int column = 0; column < screen.columns; column++) {
      if (screen.contentAt(row, column) == scalar) {
        return (row: row, column: column);
      }
    }
  }
  throw StateError('scalar U+${scalar.toRadixString(16)} not found');
}

String _screenState(TerminalScreen screen) {
  final StringBuffer result = StringBuffer(
    '${screen.rows}x${screen.columns}|${screen.cursorRow},'
    '${screen.cursorColumn}|${screen.savedCursorRow},'
    '${screen.savedCursorColumn}|',
  );
  for (int row = 0; row < screen.rows; row++) {
    result
      ..write(screen.logicalLineIdAt(row))
      ..write('/')
      ..write(screen.rowFlagsAt(row))
      ..write(':');
    for (int column = 0; column < screen.columns; column++) {
      result
        ..write(screen.contentAt(row, column))
        ..write('/')
        ..write(screen.foregroundAt(row, column))
        ..write('/')
        ..write(screen.backgroundAt(row, column))
        ..write('/')
        ..write(screen.styleAt(row, column))
        ..write('/')
        ..write(screen.hyperlinkAt(row, column))
        ..write('/')
        ..write(screen.widthFlagsAt(row, column))
        ..write(',');
    }
    result.write(';');
  }
  return result.toString();
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

void _expectThrowsRangeError(void Function() operation, String description) {
  try {
    operation();
  } on RangeError {
    return;
  }
  throw StateError(description);
}
