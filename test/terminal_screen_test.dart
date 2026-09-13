import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalScreenTests();

void runTerminalScreenTests() {
  _testStorageDefaultsAndBounds();
  _testNarrowCellStorageAndAtomicValidation();
  _testDamageCoalescingAndRowMetadata();
  _testCursorSaveRestore();
  _testTabStops();
  _testMarginAndOriginInvariants();
  _testModesCursorPresentationAndReset();
  _testPrintingWrappingAndCharacterEditing();
  _testEraseLineAndDisplay();
  _testLineEditingAndMarginScrolling();
  _testParserEditingDispatch();
  _testParserCursorTabAndStyleDispatch();
  _testLegacyCharacterSetDispatchAndState();
  _testParserScreenIntegrationAcrossChunks();
}

void _testLegacyCharacterSetDispatchAndState() {
  const List<int> expectedGraphics = <int>[
    0x00a0,
    0x25c6,
    0x2592,
    0x2409,
    0x240c,
    0x240d,
    0x240a,
    0x00b0,
    0x00b1,
    0x2424,
    0x240b,
    0x2518,
    0x2510,
    0x250c,
    0x2514,
    0x253c,
    0x23ba,
    0x23bb,
    0x2500,
    0x23bc,
    0x23bd,
    0x251c,
    0x2524,
    0x2534,
    0x252c,
    0x2502,
    0x2264,
    0x2265,
    0x03c0,
    0x2260,
    0x00a3,
    0x00b7,
  ];
  final TerminalScreen mapped = TerminalScreen(rows: 2, columns: 40);
  final TerminalScreenParserSink mappedSink = _parseInto(
    mapped,
    Uint8List.fromList(<int>[
      0x1b,
      0x29,
      0x30,
      0x0e,
      for (int scalar = 0x5f; scalar <= 0x7e; scalar++) scalar,
      0x0f,
      0x71,
      ...utf8.encode('界'),
    ]),
  );
  for (int column = 0; column < expectedGraphics.length; column++) {
    _expect(
      mapped.contentAt(0, column) == expectedGraphics[column],
      'DEC Special Graphics scalar $column is exact',
    );
  }
  _expect(
    mapped.contentAt(0, 32) == 0x71 && mapped.contentAt(0, 33) == 0x754c,
    'SI restores G0 ASCII and decoded non-ASCII bypasses GL mapping',
  );
  _expect(
    mapped.g1CharacterSet == TerminalCharacterSet.decSpecialGraphics &&
        mapped.glCharacterSetSlot == 0 &&
        mappedSink.unsupportedControlCount == 0 &&
        mappedSink.unsupportedSequenceCount == 0,
    'designation and SO/SI are declared semantic operations',
  );

  final TerminalScreen state = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink stateSink = _parseInto(
    state,
    Uint8List.fromList(<int>[
      0x71,
      0x1b,
      0x28,
      0x30,
      0x1b,
      0x37,
      0x1b,
      0x28,
      0x42,
      0x78,
      0x1b,
      0x38,
      0x71,
    ]),
  );
  _expect(
    state.contentAt(0, 0) == 0x71 && state.contentAt(0, 1) == 0x2500,
    'DECSC and DECRC save and restore the designated character sets',
  );
  _expect(stateSink.unsupportedSequenceCount == 0, 'character state stream');
  final TerminalScreen resized = state.resized(rows: 2, columns: 8);
  _expect(
    resized.g0CharacterSet == TerminalCharacterSet.decSpecialGraphics &&
        resized.savedG0CharacterSet == TerminalCharacterSet.decSpecialGraphics,
    'reflow preserves current and saved character-set state',
  );
  state.resetTerminalState();
  _expect(
    state.g0CharacterSet == TerminalCharacterSet.ascii &&
        state.g1CharacterSet == TerminalCharacterSet.ascii &&
        state.glCharacterSetSlot == 0,
    'terminal reset restores ASCII G0/G1 and invokes G0',
  );
}

void _testPrintingWrappingAndCharacterEditing() {
  final TerminalScreen wrapped = TerminalScreen(rows: 2, columns: 4);
  for (final int scalar in 'ABCDEFGHI'.codeUnits) {
    wrapped.printNarrowScalar(scalar);
  }
  _expect(_rowText(wrapped, 0) == 'EFGH', 'bottom wrap scrolls ring upward');
  _expect(_rowText(wrapped, 1) == 'I...', 'wrapped scalar enters new row');
  _expect(
    wrapped.rowFlagsAt(0) & TerminalRowFlags.softWrapped != 0,
    'wrapped row retains soft-wrap metadata',
  );
  _expect(
    wrapped.logicalLineIdAt(0) == wrapped.logicalLineIdAt(1),
    'soft-wrapped rows share logical line identity',
  );
  _expect(
    wrapped.cursorRow == 1 && wrapped.cursorColumn == 1,
    'cursor advances after wrapped print',
  );

  final TerminalScreen edited = TerminalScreen(rows: 1, columns: 5);
  _writeRow(edited, 0, 'ABCD');
  edited.setCursorPosition(0, 1);
  edited.setMode(TerminalScreenMode.insert, true);
  edited.printNarrowScalar(0x58);
  _expect(_rowText(edited, 0) == 'AXBCD', 'insert-mode print shifts cells');
  edited.deleteCharacters(2);
  _expect(_rowText(edited, 0) == 'AXD..', 'delete characters shifts left');
  edited.eraseCharacters(1);
  _expect(_rowText(edited, 0) == 'AX...', 'erase characters writes blanks');

  edited.setCursorPosition(0, 4);
  edited.backspace();
  _expect(edited.cursorColumn == 3, 'backspace moves left');
  edited.carriageReturn();
  _expect(edited.cursorColumn == 0, 'carriage return reaches left bound');
  edited.setCursorPosition(0, 0);
  edited.horizontalTab();
  _expect(edited.cursorColumn == 4, 'tab clamps when row has no stop');
  edited.backwardTab();
  _expect(edited.cursorColumn == 0, 'backward tab clamps at left bound');

  final String state = _screenKey(edited, null);
  final int generation = edited.generation;
  for (final void Function() invalid in <void Function()>[
    () => edited.printNarrowScalar(0),
    () => edited.moveCursorUp(0),
    () => edited.insertCharacters(-1),
    () => edited.eraseCharacters(0),
    () => edited.setCursorAddress(-1, 0),
  ]) {
    _expectThrowsArgumentError(invalid, 'invalid editing argument rejected');
    _expect(_screenKey(edited, null) == state, 'invalid editing is atomic');
    _expect(
      edited.generation == generation,
      'invalid editing leaves generation unchanged',
    );
  }
}

void _testEraseLineAndDisplay() {
  final TerminalScreen line = TerminalScreen(rows: 2, columns: 5);
  _writeRow(line, 0, 'ABCDE');
  line.setCursorPosition(0, 2);
  line.eraseInLine(0);
  _expect(_rowText(line, 0) == 'AB...', 'EL 0 erases through line end');
  _writeRow(line, 0, 'ABCDE');
  line.eraseInLine(1);
  _expect(_rowText(line, 0) == '...DE', 'EL 1 erases through cursor');
  _writeRow(line, 0, 'ABCDE');
  line.eraseInLine(2);
  _expect(_rowText(line, 0) == '.....', 'EL 2 erases whole line');

  final TerminalScreen display = TerminalScreen(rows: 3, columns: 4);
  _writeRow(display, 0, 'ABCD');
  _writeRow(display, 1, 'EFGH');
  _writeRow(display, 2, 'IJKL');
  display.setCursorPosition(1, 1);
  display.eraseInDisplay(0);
  _expect(_rowText(display, 0) == 'ABCD', 'ED 0 preserves earlier rows');
  _expect(_rowText(display, 1) == 'E...', 'ED 0 erases cursor onward');
  _expect(_rowText(display, 2) == '....', 'ED 0 erases later rows');

  _writeRow(display, 0, 'ABCD');
  _writeRow(display, 1, 'EFGH');
  _writeRow(display, 2, 'IJKL');
  display.eraseInDisplay(1);
  _expect(_rowText(display, 0) == '....', 'ED 1 erases earlier rows');
  _expect(_rowText(display, 1) == '..GH', 'ED 1 erases through cursor');
  _expect(_rowText(display, 2) == 'IJKL', 'ED 1 preserves later rows');
  display.eraseInDisplay(2);
  _expect(
    _rowText(display, 0) == '....' &&
        _rowText(display, 1) == '....' &&
        _rowText(display, 2) == '....',
    'ED 2 erases all rows',
  );
  _expectThrowsArgumentError(
    () => display.eraseInDisplay(3),
    'invalid ED mode rejected',
  );

  final TerminalScreen selective = TerminalScreen(rows: 2, columns: 5);
  _writeRow(selective, 0, 'ABCDE');
  _writeRow(selective, 1, 'FGHIJ');
  selective.setNarrowCell(0, 1, 0x42, isProtected: true);
  selective.setWideCell(1, 1, 0x754c, isProtected: true);
  selective.setCursorPosition(0, 0);
  selective.eraseInDisplay(2, selective: true);
  selective.validateCellTopology();
  _expect(
    _rowText(selective, 0) == '.B...' &&
        selective.contentAt(1, 1) == 0x754c &&
        selective.widthFlagsAt(1, 1) ==
            (TerminalCellFlags.wide | TerminalCellFlags.protected) &&
        selective.widthFlagsAt(1, 2) ==
            (TerminalCellFlags.continuation | TerminalCellFlags.protected),
    'DECSED keeps protected narrow and wide groups atomically',
  );
  selective.eraseInDisplay(2);
  _expect(
    _rowText(selective, 0) == '.....' && _rowText(selective, 1) == '.....',
    'ordinary ED clears protected cells',
  );
}

void _testLineEditingAndMarginScrolling() {
  final TerminalScreen ring = TerminalScreen(rows: 3, columns: 2);
  ring.setNarrowCell(
    1,
    0,
    0x58,
    foreground: 0x80010203,
    background: 0x80050607,
    style: 17,
    hyperlink: 23,
    isProtected: true,
  );
  ring.setRowFlags(1, TerminalRowFlags.output);
  final int logicalLineId = ring.logicalLineIdAt(1);
  ring.scrollUp(1);
  _expect(ring.contentAt(0, 0) == 0x58, 'ring scroll preserves content');
  _expect(
    ring.foregroundAt(0, 0) == 0x80010203 &&
        ring.backgroundAt(0, 0) == 0x80050607 &&
        ring.styleAt(0, 0) == 17 &&
        ring.hyperlinkAt(0, 0) == 23 &&
        ring.widthFlagsAt(0, 0) ==
            (TerminalCellFlags.narrow | TerminalCellFlags.protected),
    'ring scroll preserves every packed cell field',
  );
  _expect(
    ring.rowFlagsAt(0) == TerminalRowFlags.output &&
        ring.logicalLineIdAt(0) == logicalLineId,
    'ring scroll preserves row metadata',
  );
  _expect(
    _rowText(ring, 2) == '..' && ring.rowFlagsAt(2) == 0,
    'ring scroll initializes the exposed row',
  );

  final TerminalScreen vertical = TerminalScreen(rows: 3, columns: 4);
  _writeRow(vertical, 0, 'AAAA');
  _writeRow(vertical, 1, 'BBBB');
  _writeRow(vertical, 2, 'CCCC');
  vertical.setVerticalMargins(1, 2);
  vertical.setCursorPosition(2, 0);
  vertical.lineFeed();
  _expect(_rowText(vertical, 0) == 'AAAA', 'scroll preserves row above margin');
  _expect(_rowText(vertical, 1) == 'CCCC', 'LF scrolls bottom margin upward');
  _expect(_rowText(vertical, 2) == '....', 'LF exposes blank bottom row');
  vertical.setCursorPosition(1, 0);
  vertical.reverseIndex();
  _expect(_rowText(vertical, 1) == '....', 'RI exposes blank top margin row');
  _expect(_rowText(vertical, 2) == 'CCCC', 'RI scrolls margin downward');

  final TerminalScreen lines = TerminalScreen(rows: 4, columns: 4);
  _writeRow(lines, 0, 'AAAA');
  _writeRow(lines, 1, 'BBBB');
  _writeRow(lines, 2, 'CCCC');
  _writeRow(lines, 3, 'DDDD');
  lines.setCursorPosition(1, 0);
  lines.insertLines(1);
  _expect(
    _rowsText(lines) == 'AAAA\n....\nBBBB\nCCCC',
    'insert line scrolls cursor-to-bottom down',
  );
  lines.deleteLines(1);
  _expect(
    _rowsText(lines) == 'AAAA\nBBBB\nCCCC\n....',
    'delete line scrolls cursor-to-bottom up',
  );

  final TerminalScreen rectangle = TerminalScreen(rows: 3, columns: 6);
  _writeRow(rectangle, 0, 'aaaaaa');
  _writeRow(rectangle, 1, 'bbbbbb');
  _writeRow(rectangle, 2, 'cccccc');
  rectangle.setHorizontalMargins(1, 4);
  rectangle.setMode(TerminalScreenMode.horizontalMargins, true);
  rectangle.scrollUp(1);
  _expect(
    _rowsText(rectangle) == 'abbbba\nbccccb\nc....c',
    'rectangular scroll preserves cells outside horizontal margins',
  );
}

void _testParserCursorTabAndStyleDispatch() {
  final TerminalScreen screen = TerminalScreen(rows: 5, columns: 20);
  final TerminalScreenParserSink sink = _parseInto(
    screen,
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('3;5H'),
      0x1b,
      0x5b,
      ...ascii.encode('2A'),
      0x1b,
      0x5b,
      ...ascii.encode('3B'),
      0x1b,
      0x5b,
      ...ascii.encode('2C'),
      0x1b,
      0x5b,
      ...ascii.encode('1D'),
      0x1b,
      0x5b,
      ...ascii.encode('2E'),
      0x1b,
      0x5b,
      ...ascii.encode('2F'),
      0x1b,
      0x5b,
      ...ascii.encode('7G'),
      0x1b,
      0x5b,
      ...ascii.encode('4d'),
      0x1b,
      0x5b,
      ...ascii.encode('2;3f'),
      0x1b,
      0x48,
      0x1b,
      0x5b,
      ...ascii.encode('2I'),
      0x1b,
      0x5b,
      0x5a,
      0x1b,
      0x5b,
      0x67,
      0x1b,
      0x5b,
      ...ascii.encode('3g'),
      0x1b,
      0x5b,
      ...ascii.encode('4 q'),
      0x1b,
      0x5b,
      ...ascii.encode('?12h'),
      0x1b,
      0x5b,
      ...ascii.encode('?25l'),
      0x1b,
      0x5b,
      ...ascii.encode('?69h'),
      0x1b,
      0x5b,
      ...ascii.encode('3;10s'),
      0x1b,
      0x5b,
      ...ascii.encode('?6h'),
    ]),
  );
  _expect(
    screen.cursorRow == 0 && screen.cursorColumn == 2,
    'origin mode homes within horizontal margins',
  );
  _expect(
    screen.leftMargin == 2 && screen.rightMargin == 9,
    'DECSLRM parser dispatch',
  );
  _expect(
    screen.cursorShape == TerminalCursorShape.underline &&
        screen.cursorBlinking &&
        !screen.cursorVisible,
    'DECSCUSR and cursor private modes dispatch',
  );
  for (int column = 0; column < screen.columns; column++) {
    _expect(!screen.isTabStop(column), 'TBC 3 clears tab column $column');
  }
  _expect(
    sink.unsupportedControlCount == 0 && sink.unsupportedSequenceCount == 0,
    'supported cursor/tab/style stream has no unsupported actions',
  );
}

void _testParserEditingDispatch() {
  final TerminalScreen controls = TerminalScreen(rows: 3, columns: 10);
  controls.setCursorPosition(1, 1);
  final TerminalScreenParserSink controlSink = _parseInto(
    controls,
    Uint8List.fromList(<int>[0x08, 0x09, 0x0d, 0x85, 0x8d, 0x84, 0x88]),
  );
  _expect(
    controls.cursorRow == 2 &&
        controls.cursorColumn == 0 &&
        controls.isTabStop(0),
    'C0 and C1 editing controls dispatch',
  );
  _expect(
    controlSink.unsupportedControlCount == 0,
    'supported C0 and C1 controls are not counted as unknown',
  );

  final TerminalScreen characters = TerminalScreen(rows: 2, columns: 5);
  _writeRow(characters, 0, 'ABCDE');
  _parseInto(
    characters,
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('1;2H'),
      0x1b,
      0x5b,
      ...ascii.encode('2@'),
      0x1b,
      0x5b,
      0x50,
      0x1b,
      0x5b,
      ...ascii.encode('2X'),
    ]),
  );
  _expect(
    _rowText(characters, 0) == 'A..C.',
    'CSI ICH, DCH, and ECH dispatch in order',
  );

  final TerminalScreen lines = TerminalScreen(rows: 4, columns: 4);
  _writeRow(lines, 0, 'AAAA');
  _writeRow(lines, 1, 'BBBB');
  _writeRow(lines, 2, 'CCCC');
  _writeRow(lines, 3, 'DDDD');
  _parseInto(
    lines,
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('2;1H'),
      0x1b,
      0x5b,
      0x4c,
      0x1b,
      0x5b,
      0x4d,
    ]),
  );
  _expect(
    _rowsText(lines) == 'AAAA\nBBBB\nCCCC\n....',
    'CSI IL and DL dispatch in order',
  );

  final TerminalScreen scrolling = TerminalScreen(rows: 3, columns: 3);
  _writeRow(scrolling, 0, 'AAA');
  _writeRow(scrolling, 1, 'BBB');
  _writeRow(scrolling, 2, 'CCC');
  _parseInto(
    scrolling,
    Uint8List.fromList(<int>[0x1b, 0x5b, 0x53, 0x1b, 0x5b, 0x54]),
  );
  _expect(
    _rowsText(scrolling) == '...\nBBB\nCCC',
    'CSI SU and SD dispatch in order',
  );

  final TerminalScreen erasing = TerminalScreen(rows: 2, columns: 4);
  _writeRow(erasing, 0, 'ABCD');
  _writeRow(erasing, 1, 'EFGH');
  _parseInto(
    erasing,
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('1;3H'),
      0x1b,
      0x5b,
      0x4b,
      0x1b,
      0x5b,
      ...ascii.encode('2J'),
    ]),
  );
  _expect(_rowsText(erasing) == '....\n....', 'CSI EL and ED dispatch');

  final TerminalScreen reset = TerminalScreen(rows: 2, columns: 4);
  reset.setNarrowCell(1, 2, 0x58);
  reset.setMode(TerminalScreenMode.insert, true);
  reset.setCursorPosition(1, 2);
  _parseInto(reset, Uint8List.fromList(<int>[0x1b, 0x63]));
  _expect(
    _rowsText(reset) == '....\n....' &&
        reset.cursorRow == 0 &&
        reset.cursorColumn == 0 &&
        !reset.modeEnabled(TerminalScreenMode.insert),
    'ESC RIS resets screen cells and terminal state',
  );
}

void _testParserScreenIntegrationAcrossChunks() {
  final Uint8List input = Uint8List.fromList(<int>[
    ...ascii.encode('ABCDEFG'),
    0x0d,
    0x0a,
    ...ascii.encode('12'),
    0x1b,
    0x5b,
    ...ascii.encode('2;4Hxy'),
    0x1b,
    0x5b,
    ...ascii.encode('1D'),
    0x1b,
    0x5b,
    0x50,
    0x1b,
    0x5b,
    ...ascii.encode('2;3r'),
    0x1b,
    0x5b,
    ...ascii.encode('?6hQ'),
    0x1b,
    0x5b,
    ...ascii.encode('?25l'),
    0x1b,
    0x5b,
    ...ascii.encode('4h'),
    0x1b,
    0x5b,
    ...ascii.encode('1;3HZ'),
    0x1b,
    0x5b,
    ...ascii.encode('4l'),
    0x1b,
    0x37,
    0x1b,
    0x5b,
    ...ascii.encode('2B'),
    0x1b,
    0x38,
    0x1b,
    0x48,
    0x1b,
    0x5d,
    ...ascii.encode('0;title'),
    0x07,
    0x1b,
    0x5b,
    ...ascii.encode('1?2m'),
    0x1b,
    0x5b,
    ...ascii.encode('31'),
    0x1b,
    0x5b,
    ...ascii.encode('0m'),
  ]);
  final String expected = _parseScreen(input);
  for (final String expectedLine in const <String>[
    'screen row=0 flags=soft-wrapped logical=1:1+0 text="ABCDEF"',
    'screen row=1 flags=hard-break logical=1:1+6 text="Q Z x "',
    'screen row=2 flags=- logical=1:3+0 text="12    "',
    'screen cursor=1,3 saved=1,3',
    'screen margins=1,2,0,5 '
        'modes=origin:true,insert:false,autoWrap:true,'
        'reverseVideo:false,horizontalMargins:false',
    'screen cursor_style=block visible=false blinking=true '
        'wrap_pending=false',
    'screen tabs=3',
    'parser unsupported_controls=0 unsupported_sequences=1 '
        'cancel=1 limit=0 malformed=1 incomplete=0 '
        'replies_accepted=0 replies_rejected=0',
  ]) {
    _expect(
      expected.contains(expectedLine),
      'whole parser-to-screen snapshot contains $expectedLine',
    );
  }
  for (int split = 0; split <= input.length; split++) {
    const TerminalSnapshotComparator()
        .compare(
          expected,
          _parseScreen(input, <int>[split, input.length - split]),
        )
        .requireMatch('parser-to-screen split $split');
  }
  const TerminalSnapshotComparator()
      .compare(expected, _parseScreen(input, List<int>.filled(input.length, 1)))
      .requireMatch('parser-to-screen bytewise chunks');
}

String _parseScreen(Uint8List input, [List<int>? chunks]) {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 6);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  _expect(offset == input.length, 'screen chunk plan consumes all input');
  parser.finish();
  return const TerminalSnapshotFormatter().formatScreen(
    screen,
    parserSink: sink,
  );
}

TerminalScreenParserSink _parseInto(TerminalScreen screen, Uint8List input) {
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(input);
  parser.finish();
  return sink;
}

String _screenKey(TerminalScreen screen, TerminalScreenParserSink? sink) =>
    const TerminalSnapshotFormatter().formatScreen(screen, parserSink: sink);

String _rowText(TerminalScreen screen, int row) {
  final StringBuffer result = StringBuffer();
  for (int column = 0; column < screen.columns; column++) {
    final int content = screen.contentAt(row, column);
    result.writeCharCode(content == 0 ? 0x2e : content);
  }
  return result.toString();
}

String _rowsText(TerminalScreen screen) =>
    <String>[for (int row = 0; row < screen.rows; row++) _rowText(screen, row)]
        .join('\n');

void _writeRow(TerminalScreen screen, int row, String text) {
  for (int column = 0; column < text.length; column++) {
    screen.setNarrowCell(row, column, text.codeUnitAt(column));
  }
}

void _testMarginAndOriginInvariants() {
  final TerminalScreen screen = TerminalScreen(rows: 5, columns: 8);
  _expect(
    screen.topMargin == 0 && screen.bottomMargin == 4,
    'default vertical margins',
  );
  _expect(
    screen.leftMargin == 0 && screen.rightMargin == 7,
    'default horizontal margins',
  );
  _expect(
    screen.activeLeftMargin == 0 && screen.activeRightMargin == 7,
    'horizontal margins initially inactive',
  );

  screen.setCursorPosition(4, 7);
  screen.setVerticalMargins(1, 3);
  _expect(
    screen.cursorRow == 0 && screen.cursorColumn == 0,
    'margin set homes',
  );
  screen.setHorizontalMargins(2, 5);
  _expect(
    screen.activeLeftMargin == 0 && screen.activeRightMargin == 7,
    'stored horizontal margins remain inactive',
  );
  screen.setMode(TerminalScreenMode.horizontalMargins, true);
  screen.setMode(TerminalScreenMode.origin, true);
  _expect(
    screen.activeLeftMargin == 2 && screen.activeRightMargin == 5,
    'horizontal margins become active',
  );
  _expect(screen.cursorRow == 1 && screen.cursorColumn == 2, 'origin home');

  screen.setCursorPosition(0, 7);
  screen.clampCursorToMargins();
  _expect(screen.cursorRow == 1 && screen.cursorColumn == 5, 'margin clamp');
  screen.setMode(TerminalScreenMode.origin, false);
  _expect(
    screen.cursorRow == 0 && screen.cursorColumn == 0,
    'origin reset homes',
  );

  final String beforeInvalid = _stateKey(screen);
  final int generation = screen.generation;
  for (final void Function() mutation in <void Function()>[
    () => screen.setVerticalMargins(-1, 2),
    () => screen.setVerticalMargins(2, 2),
    () => screen.setVerticalMargins(1, 5),
    () => screen.setHorizontalMargins(-1, 4),
    () => screen.setHorizontalMargins(4, 3),
    () => screen.setHorizontalMargins(1, 8),
  ]) {
    _expectThrowsArgumentError(mutation, 'invalid margins rejected');
    _expect(_stateKey(screen) == beforeInvalid, 'invalid margin is atomic');
    _expect(
      screen.generation == generation,
      'invalid margin generation stable',
    );
  }

  screen.setMode(TerminalScreenMode.horizontalMargins, false);
  _expect(
    screen.leftMargin == 0 &&
        screen.rightMargin == 7 &&
        screen.activeLeftMargin == 0 &&
        screen.activeRightMargin == 7,
    'disabling horizontal margins restores full width',
  );
  screen.resetVerticalMargins();
  _expect(
    screen.topMargin == 0 && screen.bottomMargin == 4,
    'vertical margins reset',
  );
}

void _testModesCursorPresentationAndReset() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 12);
  _expect(!screen.modeEnabled(TerminalScreenMode.origin), 'origin default');
  _expect(!screen.modeEnabled(TerminalScreenMode.insert), 'insert default');
  _expect(screen.replaceMode, 'replace default');
  _expect(screen.modeEnabled(TerminalScreenMode.autoWrap), 'autowrap default');
  _expect(
    !screen.modeEnabled(TerminalScreenMode.reverseVideo),
    'reverse video default',
  );
  _expect(
    !screen.modeEnabled(TerminalScreenMode.horizontalMargins),
    'horizontal margin mode default',
  );
  _expect(
    screen.cursorVisible &&
        screen.cursorBlinking &&
        screen.cursorShape == TerminalCursorShape.block,
    'cursor presentation defaults',
  );

  screen.setMode(TerminalScreenMode.insert, true);
  _expect(!screen.replaceMode, 'insert disables replace behavior');
  screen.setWrapPending(true);
  _expect(screen.wrapPending, 'autowrap permits wrap pending');
  screen.setMode(TerminalScreenMode.autoWrap, false);
  _expect(!screen.wrapPending, 'disabling autowrap clears pending wrap');
  _expectThrowsStateError(
    () => screen.setWrapPending(true),
    'wrap pending rejected without autowrap',
  );

  screen.clearDamage();
  screen.setMode(TerminalScreenMode.reverseVideo, true);
  for (int row = 0; row < screen.rows; row++) {
    _expect(screen.dirtyStartAt(row) == 0, 'reverse video damages row start');
    _expect(screen.dirtyEndAt(row) == 12, 'reverse video damages row end');
  }
  screen.setCursorPresentation(
    shape: TerminalCursorShape.bar,
    visible: false,
    blinking: false,
  );
  _expect(
    !screen.cursorVisible &&
        !screen.cursorBlinking &&
        screen.cursorShape == TerminalCursorShape.bar,
    'cursor presentation update',
  );

  screen.setVerticalMargins(1, 2);
  screen.setHorizontalMargins(2, 9);
  screen.setMode(TerminalScreenMode.horizontalMargins, true);
  screen.setMode(TerminalScreenMode.origin, true);
  screen.setCursorPosition(2, 8);
  screen.saveCursor();
  screen.clearAllTabStops();
  screen.setNarrowCell(2, 8, 0x58);
  final int content = screen.contentAt(2, 8);
  screen.resetTerminalState();
  _expect(
    _stateKey(screen) == _defaultStateKey(screen),
    'state reset defaults',
  );
  _expect(screen.isTabStop(8), 'state reset restores default tabs');
  _expect(screen.contentAt(2, 8) == content, 'state reset preserves cells');
  final int generation = screen.generation;
  screen.resetTerminalState();
  _expect(screen.generation == generation, 'default state reset is a no-op');
}

String _stateKey(TerminalScreen screen) => <Object>[
  screen.cursorRow,
  screen.cursorColumn,
  screen.savedCursorRow,
  screen.savedCursorColumn,
  screen.topMargin,
  screen.bottomMargin,
  screen.leftMargin,
  screen.rightMargin,
  screen.modeEnabled(TerminalScreenMode.origin),
  screen.modeEnabled(TerminalScreenMode.insert),
  screen.modeEnabled(TerminalScreenMode.autoWrap),
  screen.modeEnabled(TerminalScreenMode.reverseVideo),
  screen.modeEnabled(TerminalScreenMode.horizontalMargins),
  screen.wrapPending,
  screen.cursorVisible,
  screen.cursorBlinking,
  screen.cursorShape,
].join('|');

String _defaultStateKey(TerminalScreen screen) => <Object>[
  0,
  0,
  0,
  0,
  0,
  screen.rows - 1,
  0,
  screen.columns - 1,
  false,
  false,
  true,
  false,
  false,
  false,
  true,
  true,
  TerminalCursorShape.block,
].join('|');

void _testStorageDefaultsAndBounds() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 10);
  _expect(screen.rows == 2, 'screen row count');
  _expect(screen.columns == 10, 'screen column count');
  _expect(screen.cellCount == 20, 'screen cell count');
  _expect(screen.cellStorageBytes == 20 * 17, 'six SoA cell bytes');
  _expect(screen.rowStorageBytes == 2 * 13, 'five SoA row bytes');
  _expect(screen.tabStopStorageBytes == 10, 'typed tab-stop bytes');
  _expect(screen.typedStorageBytes == 376, 'total typed storage bytes');
  _expect(screen.generation == 1, 'initial screen generation is nonzero');
  _expect(screen.fullSnapshotRequired, 'new screen requires full snapshot');
  screen.acknowledgeFullSnapshot();
  _expect(!screen.fullSnapshotRequired, 'full snapshot acknowledgement');

  for (int row = 0; row < screen.rows; row++) {
    _expect(screen.logicalLineIdAt(row) == row + 1, 'initial logical line ID');
    _expect(screen.rowVersionAt(row) == 0, 'initial row version');
    _expect(!screen.isRowDirty(row), 'new row starts clean');
    _expect(screen.dirtyStartAt(row) == 10, 'clean dirty start sentinel');
    _expect(screen.dirtyEndAt(row) == 0, 'clean dirty end sentinel');
    _expect(screen.rowFlagsAt(row) == 0, 'initial row flags');
    for (int column = 0; column < screen.columns; column++) {
      _expect(screen.contentAt(row, column) == 0, 'initial blank content');
      _expect(screen.foregroundAt(row, column) == 0, 'initial foreground');
      _expect(screen.backgroundAt(row, column) == 0, 'initial background');
      _expect(screen.styleAt(row, column) == 0, 'initial style');
      _expect(screen.hyperlinkAt(row, column) == 0, 'initial hyperlink');
      _expect(
        screen.widthFlagsAt(row, column) == TerminalCellFlags.narrow,
        'initial narrow blank flags',
      );
    }
  }

  for (final void Function() create in <void Function()>[
    () => TerminalScreen(rows: 0, columns: 1),
    () => TerminalScreen(rows: 1, columns: 0),
    () => TerminalScreen(rows: TerminalScreen.maxRows + 1, columns: 1),
    () => TerminalScreen(rows: 1, columns: TerminalScreen.maxColumns + 1),
    () => TerminalScreen(rows: 1025, columns: 1024),
  ]) {
    _expectThrowsArgumentError(create, 'invalid dimensions rejected');
  }
  _expectThrowsRangeError(
    () => screen.contentAt(-1, 0),
    'negative row rejected',
  );
  _expectThrowsRangeError(
    () => screen.contentAt(0, 10),
    'column beyond grid rejected',
  );
}

void _testNarrowCellStorageAndAtomicValidation() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 3);
  screen.setNarrowCell(
    1,
    2,
    0x10400,
    foreground: 0x80112233,
    background: 256,
    style: 65534,
    hyperlink: 42,
    isProtected: true,
  );
  _expect(screen.contentAt(1, 2) == 0x10400, 'stored scalar');
  _expect(screen.foregroundAt(1, 2) == 0x80112233, 'stored direct color');
  _expect(screen.backgroundAt(1, 2) == 256, 'stored palette color');
  _expect(screen.styleAt(1, 2) == 65534, 'stored maximum style ID');
  _expect(screen.hyperlinkAt(1, 2) == 42, 'stored hyperlink ID');
  _expect(
    screen.widthFlagsAt(1, 2) ==
        TerminalCellFlags.narrow | TerminalCellFlags.protected,
    'stored narrow/protected flags',
  );
  final int generation = screen.generation;
  screen.setNarrowCell(
    1,
    2,
    0x10400,
    foreground: 0x80112233,
    background: 256,
    style: 65534,
    hyperlink: 42,
    isProtected: true,
  );
  _expect(screen.generation == generation, 'identical cell write is a no-op');

  for (final void Function() mutate in <void Function()>[
    () => screen.setNarrowCell(1, 2, 0xd800),
    () => screen.setNarrowCell(1, 2, 0x110000),
    () => screen.setNarrowCell(1, 2, 0x1f600),
    () => screen.setNarrowCell(1, 2, 0x41, foreground: 257),
    () => screen.setNarrowCell(1, 2, 0x41, background: 0x81000000),
    () => screen.setNarrowCell(1, 2, 0x41, style: 65535),
    () => screen.setNarrowCell(1, 2, 0x41, hyperlink: -1),
  ]) {
    _expectThrowsArgumentError(mutate, 'invalid cell field rejected');
    _expect(screen.contentAt(1, 2) == 0x10400, 'invalid write is atomic');
    _expect(screen.generation == generation, 'invalid write has no generation');
  }
}

void _testDamageCoalescingAndRowMetadata() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 6);
  screen.setNarrowCell(1, 4, 0x41);
  final int firstGeneration = screen.generation;
  _expect(screen.rowVersionAt(1) == 1, 'first dirty edit advances version');
  _expect(screen.dirtyStartAt(1) == 4, 'first dirty start');
  _expect(screen.dirtyEndAt(1) == 5, 'first dirty end');

  screen.setNarrowCell(1, 1, 0x42);
  _expect(
    screen.generation > firstGeneration,
    'effective edit advances generation',
  );
  _expect(screen.rowVersionAt(1) == 1, 'dirty row version advances once');
  _expect(screen.dirtyStartAt(1) == 1, 'damage coalesces lower start');
  _expect(screen.dirtyEndAt(1) == 5, 'damage preserves upper end');

  screen.setRowFlags(1, TerminalRowFlags.softWrapped | TerminalRowFlags.output);
  screen.setLogicalLineId(1, TerminalScreen.maxLogicalLineId);
  _expect(
    screen.rowFlagsAt(1) ==
        TerminalRowFlags.softWrapped | TerminalRowFlags.output,
    'row flags stored',
  );
  _expect(
    screen.logicalLineIdAt(1) == TerminalScreen.maxLogicalLineId,
    'logical line ID stored',
  );
  _expect(screen.dirtyStartAt(1) == 0, 'row metadata dirties full row');
  _expect(screen.dirtyEndAt(1) == 6, 'row metadata full dirty end');
  _expect(screen.rowVersionAt(1) == 1, 'metadata coalesces same dirty version');

  screen.clearDamage();
  _expect(!screen.isRowDirty(1), 'damage clear uses clean sentinel');
  screen.setNarrowCell(1, 5, 0x43);
  _expect(screen.rowVersionAt(1) == 2, 'post-clear edit advances version');
  _expect(screen.dirtyStartAt(1) == 5, 'post-clear dirty start');
  _expect(screen.dirtyEndAt(1) == 6, 'post-clear dirty end');

  screen.markAllDirty();
  for (int row = 0; row < screen.rows; row++) {
    _expect(screen.dirtyStartAt(row) == 0, 'full damage starts at zero');
    _expect(screen.dirtyEndAt(row) == 6, 'full damage reaches columns');
    _expect(screen.rowVersionAt(row) == (row == 1 ? 2 : 1), 'row version rule');
  }
  final int generation = screen.generation;
  screen.markAllDirty();
  _expect(screen.generation == generation, 'already-full damage is a no-op');

  _expectThrowsArgumentError(
    () => screen.setRowFlags(0, 1 << 7),
    'unknown row flag rejected',
  );
  _expectThrowsRangeError(
    () => screen.setLogicalLineId(0, 0),
    'zero logical line ID rejected',
  );
}

void _testCursorSaveRestore() {
  final TerminalScreen screen = TerminalScreen(rows: 4, columns: 5);
  screen.setCursorPosition(2, 3);
  screen.saveCursor();
  final int savedGeneration = screen.generation;
  screen.setCursorPosition(1, 1);
  screen.restoreCursor();
  _expect(screen.cursorRow == 2 && screen.cursorColumn == 3, 'cursor restored');
  _expect(
    screen.savedCursorRow == 2 && screen.savedCursorColumn == 3,
    'saved cursor retained',
  );
  _expect(screen.generation > savedGeneration, 'cursor changes generation');
  final int generation = screen.generation;
  screen.restoreCursor();
  _expect(screen.generation == generation, 'same restore is a no-op');
  _expectThrowsRangeError(
    () => screen.setCursorPosition(4, 0),
    'cursor row beyond grid rejected',
  );
  _expectThrowsRangeError(
    () => screen.setCursorPosition(0, -1),
    'negative cursor column rejected',
  );
  _expect(
    screen.cursorRow == 2 && screen.cursorColumn == 3,
    'invalid cursor atomic',
  );
}

void _testTabStops() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 20);
  for (int column = 0; column < screen.columns; column++) {
    _expect(
      screen.isTabStop(column) == (column == 8 || column == 16),
      'default tab stop at column $column',
    );
  }
  _expect(screen.nextTabStop(0) == 8, 'next default tab stop');
  _expect(screen.nextTabStop(8) == 16, 'next tab excludes current column');
  _expect(screen.nextTabStop(16) == 19, 'next tab clamps at last column');
  _expect(screen.previousTabStop(19) == 16, 'previous default tab stop');
  _expect(
    screen.previousTabStop(8) == 0,
    'previous tab excludes current column',
  );

  screen.setTabStop(3);
  screen.setTabStop(8, enabled: false);
  _expect(screen.nextTabStop(0) == 3, 'custom tab stop');
  _expect(!screen.isTabStop(8), 'individual tab stop cleared');
  screen.clearAllTabStops();
  _expect(screen.nextTabStop(0) == 19, 'no stop clamps at last column');
  final int generation = screen.generation;
  screen.clearAllTabStops();
  _expect(screen.generation == generation, 'clearing empty tabs is a no-op');
  screen.resetDefaultTabStops();
  _expect(screen.isTabStop(8) && screen.isTabStop(16), 'default tabs restored');

  _expectThrowsRangeError(
    () => screen.isTabStop(20),
    'tab query beyond grid rejected',
  );
  _expectThrowsRangeError(
    () => screen.setTabStop(-1),
    'negative tab mutation rejected',
  );
}

void _expectThrowsArgumentError(void Function() action, String message) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectThrowsRangeError(void Function() action, String message) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectThrowsStateError(void Function() action, String message) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('test failed: $message');
  }
}
