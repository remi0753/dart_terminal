import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalScreenSetTests();

void runTerminalScreenSetTests() {
  _testSharedResourcesAndPaletteDamage();
  _testMode47IsolationAndPreservation();
  _testCharacterSetIsolationAcrossScreenSwitches();
  _testMode1047ClearOnReturn();
  _testMode1048SaveAndRestore();
  _testMode1049ClearSaveRestoreAndIdempotence();
  _testScreenSetReset();
  _testKeyboardModesAcrossScreensAndReset();
  _testParserScreenModeDispatch();
  _testParserScreenSetChunkIndependence();
}

void _testKeyboardModesAcrossScreensAndReset() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 1);
  screens
    ..setApplicationEscape(true)
    ..setModifyOtherKeys(2)
    ..pushKittyKeyboardFlags(3)
    ..setAlternateMode47(true)
    ..pushKittyKeyboardFlags(8);
  _expect(
    screens.keyboardModes ==
            const TerminalKeyboardModes(
              applicationEscape: true,
              modifyOtherKeys: 2,
              kittyKeyboardFlags: 8,
            ) &&
        screens.kittyKeyboardStackDepth == 1,
    'alternate screen owns an independent Kitty keyboard stack',
  );
  screens.setAlternateMode47(false);
  _expect(
    screens.keyboardModes.kittyKeyboardFlags == 3 &&
        screens.kittyKeyboardStackDepth == 1,
    'primary Kitty keyboard state survives an alternate-screen round trip',
  );
  screens.reset();
  _expect(
    screens.keyboardModes == const TerminalKeyboardModes() &&
        screens.kittyKeyboardStackDepth == 0,
    'RIS resets global and per-screen keyboard protocol state',
  );
}

void _testCharacterSetIsolationAcrossScreenSwitches() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 6);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      0x1b,
      0x29,
      0x30,
      0x0e,
      0x71,
      ..._csi('?47h'),
      0x71,
      0x1b,
      0x28,
      0x30,
      0x78,
      ..._csi('?47l'),
      0x78,
      ..._csi('?47h'),
      0x71,
    ]),
  );
  parser.finish();
  _expect(
    screens.primary.contentAt(0, 0) == 0x2500 &&
        screens.primary.contentAt(0, 1) == 0x2502 &&
        screens.primary.g0CharacterSet == TerminalCharacterSet.ascii &&
        screens.primary.g1CharacterSet ==
            TerminalCharacterSet.decSpecialGraphics &&
        screens.primary.glCharacterSetSlot == 1,
    'primary retains its invoked G1 DEC set while inactive',
  );
  _expect(
    screens.alternate.contentAt(0, 0) == 0x71 &&
        screens.alternate.contentAt(0, 1) == 0x2502 &&
        screens.alternate.contentAt(0, 2) == 0x2500 &&
        screens.alternate.g0CharacterSet ==
            TerminalCharacterSet.decSpecialGraphics &&
        screens.alternate.g1CharacterSet == TerminalCharacterSet.ascii &&
        screens.alternate.glCharacterSetSlot == 0,
    'alternate owns an independent G0 designation and invocation state',
  );
  _expect(
    sink.unsupportedControlCount == 0 && sink.unsupportedSequenceCount == 0,
    'screen-switch character-set stream is fully supported',
  );
}

void _testSharedResourcesAndPaletteDamage() {
  final TerminalStyleTable styles = TerminalStyleTable();
  final TerminalPalette palette = TerminalPalette();
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    styleTable: styles,
    palette: palette,
  );
  _expect(
    screens.activeKind == TerminalScreenKind.primary &&
        identical(screens.activeScreen, screens.primary),
    'screen set starts on primary',
  );
  _expect(!identical(screens.primary, screens.alternate), 'grids are distinct');
  _expect(
    identical(screens.primary.styleTable, styles) &&
        identical(screens.alternate.styleTable, styles) &&
        identical(screens.primary.palette, palette) &&
        identical(screens.alternate.palette, palette),
    'both grids share style and palette resources',
  );

  screens.primary.setCurrentRendition(
    styleAttributes: TerminalStyleAttributes.bold,
  );
  screens.alternate.setCurrentRendition(
    styleAttributes: TerminalStyleAttributes.bold,
  );
  _expect(
    screens.primary.currentStyleId == screens.alternate.currentStyleId,
    'equal rendition has one shared style ID',
  );

  screens.primary.clearDamage();
  screens.alternate.clearDamage();
  final int primaryGeneration = screens.primary.generation;
  final int alternateGeneration = screens.alternate.generation;
  screens.primary.setPaletteColor(1, 0x80123456);
  _expect(
    screens.primary.paletteColorAt(1) == 0x80123456 &&
        screens.alternate.paletteColorAt(1) == 0x80123456,
    'palette mutation is shared',
  );
  _expect(
    screens.primary.generation > primaryGeneration &&
        screens.alternate.generation > alternateGeneration,
    'shared palette mutation advances both screen generations',
  );
  for (final TerminalScreen screen in <TerminalScreen>[
    screens.primary,
    screens.alternate,
  ]) {
    for (int row = 0; row < screen.rows; row++) {
      _expect(
        screen.dirtyStartAt(row) == 0 &&
            screen.dirtyEndAt(row) == screen.columns,
        'shared palette mutation damages both grids',
      );
    }
  }
}

void _testMode47IsolationAndPreservation() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  screens.primary.printNarrowScalar(0x50);
  screens.primary.setCursorPosition(1, 2);
  screens.primary.setCurrentRendition(
    foreground: 2,
    styleAttributes: TerminalStyleAttributes.bold,
  );
  screens.alternate.acknowledgeFullSnapshot();
  screens.alternate.clearDamage();

  screens.setAlternateMode47(true);
  screens.setBracketedPasteMode(true);
  _expect(screens.usingAlternate, 'mode 47 selects alternate');
  _expect(
    _rowText(screens.alternate, 0) == '....',
    'alternate starts isolated',
  );
  _expect(screens.alternate.fullSnapshotRequired, 'switch requests snapshot');
  _expect(
    screens.alternate.dirtyStartAt(0) == 0 &&
        screens.alternate.dirtyEndAt(0) == screens.alternate.columns,
    'switch marks active presentation dirty',
  );
  final int activeGeneration = screens.transitionGeneration;
  screens.setAlternateMode47(true);
  _expect(
    screens.transitionGeneration == activeGeneration,
    'repeated mode 47 set is no-op',
  );
  screens.alternate.printNarrowScalar(0x41);
  screens.alternate.setCursorPosition(1, 1);

  screens.setAlternateMode47(false);
  _expect(!screens.usingAlternate, 'mode 47 reset selects primary');
  _expect(_rowText(screens.primary, 0) == 'P...', 'primary content preserved');
  _expect(
    screens.primary.cursorRow == 1 &&
        screens.primary.cursorColumn == 2 &&
        screens.primary.currentForeground == 2 &&
        TerminalStyleAttributes.has(
          screens.primary.currentStyleAttributes,
          TerminalStyleAttributes.bold,
        ),
    'primary cursor and rendition preserved',
  );
  screens.setAlternateMode47(true);
  _expect(
    _rowText(screens.alternate, 0) == 'A...',
    'alternate content preserved',
  );
  _expect(
    screens.alternate.cursorRow == 1 && screens.alternate.cursorColumn == 1,
    'alternate cursor state preserved',
  );
}

void _testMode1047ClearOnReturn() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  screens.setAlternateMode1047(true);
  screens.alternate.setCurrentRendition(
    background: 3,
    styleAttributes: TerminalStyleAttributes.italic,
  );
  screens.alternate.printNarrowScalar(0x58);
  final int activeGeneration = screens.transitionGeneration;
  screens.setAlternateMode1047(true);
  _expect(
    screens.transitionGeneration == activeGeneration &&
        screens.alternate.contentAt(0, 0) == 0x58,
    'repeated mode 1047 set preserves active alternate',
  );

  screens.setAlternateMode1047(false);
  _expect(!screens.usingAlternate, 'mode 1047 reset returns to primary');
  _expect(
    _allBlank(screens.alternate) &&
        screens.alternate.cursorRow == 0 &&
        screens.alternate.cursorColumn == 0 &&
        screens.alternate.currentStyleId == 0 &&
        screens.alternate.currentBackground == 0,
    'mode 1047 reset clears alternate before return',
  );
  final int inactiveGeneration = screens.transitionGeneration;
  screens.setAlternateMode1047(false);
  _expect(
    screens.transitionGeneration == inactiveGeneration,
    'repeated mode 1047 reset is no-op',
  );
  screens.setAlternateMode1047(true);
  _expect(_allBlank(screens.alternate), 'cleared alternate remains blank');
}

void _testMode1048SaveAndRestore() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  screens.primary.setCursorPosition(1, 2);
  screens.primary.setCurrentRendition(
    foreground: 6,
    background: 0x80112233,
    styleAttributes: TerminalStyleAttributes.faint,
  );
  screens.setCursorSaveMode1048(true);
  screens.primary.setCursorPosition(0, 0);
  screens.primary.resetCurrentRendition();
  screens.setCursorSaveMode1048(false);
  _expect(
    screens.primary.cursorRow == 1 && screens.primary.cursorColumn == 2,
    'mode 1048 restores active cursor',
  );
  _expect(
    screens.primary.currentForeground == 6 &&
        screens.primary.currentBackground == 0x80112233 &&
        TerminalStyleAttributes.has(
          screens.primary.currentStyleAttributes,
          TerminalStyleAttributes.faint,
        ),
    'mode 1048 restores active rendition',
  );
}

void _testMode1049ClearSaveRestoreAndIdempotence() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  screens.primary.setCursorPosition(1, 2);
  screens.primary.setCurrentRendition(
    foreground: 4,
    styleAttributes: TerminalStyleAttributes.withUnderline(
      0,
      TerminalUnderlineStyle.dotted,
    ),
  );
  screens.setAlternateMode47(true);
  screens.alternate.printNarrowScalar(0x4f);
  screens.setAlternateMode47(false);

  screens.setAlternateMode1049(true);
  _expect(
    screens.usingAlternate && screens.mode1049Active,
    'mode 1049 activates alternate state',
  );
  _expect(_allBlank(screens.alternate), 'mode 1049 clears alternate on entry');
  screens.alternate.printNarrowScalar(0x41);
  final int activeGeneration = screens.transitionGeneration;
  final int alternateGeneration = screens.alternate.generation;
  screens.setAlternateMode1049(true);
  _expect(
    screens.transitionGeneration == activeGeneration &&
        screens.alternate.generation == alternateGeneration &&
        screens.alternate.contentAt(0, 0) == 0x41,
    'repeated mode 1049 set does not resave or reclear',
  );

  screens.setAlternateMode1049(false);
  _expect(
    !screens.usingAlternate && !screens.mode1049Active,
    'mode 1049 reset returns to primary',
  );
  _expect(
    screens.primary.cursorRow == 1 &&
        screens.primary.cursorColumn == 2 &&
        screens.primary.currentForeground == 4 &&
        TerminalStyleAttributes.underline(
              screens.primary.currentStyleAttributes,
            ) ==
            TerminalUnderlineStyle.dotted,
    'mode 1049 restores primary cursor and rendition',
  );
  final int inactiveGeneration = screens.transitionGeneration;
  screens.setAlternateMode1049(false);
  _expect(
    screens.transitionGeneration == inactiveGeneration,
    'repeated mode 1049 reset is no-op',
  );
  screens.setAlternateMode47(true);
  _expect(
    screens.alternate.contentAt(0, 0) == 0x41,
    'mode 1049 reset does not add an undocumented exit clear',
  );
}

void _testScreenSetReset() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 3);
  screens.primary.setCurrentRendition(
    styleAttributes: TerminalStyleAttributes.bold,
  );
  final int styleCount = screens.styleTable.definitionCount;
  screens.primary.printNarrowScalar(0x50);
  screens.primary.setPaletteColor(0, 0x80123456);
  screens.setAlternateMode47(true);
  screens.alternate.printNarrowScalar(0x41);
  screens.reset();
  _expect(
    !screens.usingAlternate &&
        !screens.bracketedPasteMode &&
        _allBlank(screens.primary) &&
        _allBlank(screens.alternate),
    'screen-set reset clears both grids and selects primary',
  );
  _expect(
    screens.primary.currentStyleId == 0 &&
        screens.alternate.currentStyleId == 0 &&
        screens.styleTable.definitionCount == styleCount,
    'screen-set reset preserves shared immutable styles',
  );
  _expect(
    screens.palette.colorAt(0) == 0x80123456,
    'screen-set reset preserves palette resource mutation',
  );
  _expect(
    screens.primary.fullSnapshotRequired,
    'screen-set reset requires primary full snapshot',
  );
}

void _testParserScreenModeDispatch() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  screens.primary.setCursorPosition(1, 2);
  parser.parse(Uint8List.fromList(_csi('?1048h')));
  screens.primary.setCursorPosition(0, 0);
  parser.parse(Uint8List.fromList(_csi('?1048l')));
  _expect(
    screens.primary.cursorRow == 1 && screens.primary.cursorColumn == 2,
    'parser dispatches mode 1048',
  );
  parser.parse(Uint8List.fromList(<int>[..._csi('?1047h'), 0x58]));
  _expect(screens.usingAlternate, 'parser dispatches mode 1047 set');
  parser.parse(Uint8List.fromList(_csi('?1047l')));
  _expect(
    !screens.usingAlternate && _allBlank(screens.alternate),
    'parser dispatches mode 1047 reset and clear',
  );
  parser.parse(Uint8List.fromList(<int>[..._csi('?47h'), 0x41]));
  _expect(screens.usingAlternate, 'parser dispatches mode 47 set');
  parser.parse(Uint8List.fromList(_csi('?47l')));
  _expect(
    !screens.usingAlternate && screens.alternate.contentAt(0, 0) == 0x41,
    'parser dispatches preserving mode 47 reset',
  );
  parser.parse(Uint8List.fromList(_csi('?2004h')));
  _expect(screens.bracketedPasteMode, 'parser dispatches mode 2004 set');
  parser.parse(Uint8List.fromList(_csi('?2004l')));
  _expect(!screens.bracketedPasteMode, 'parser dispatches mode 2004 reset');
  parser.parse(Uint8List.fromList(_csi('?2004h')));
  parser.parse(Uint8List.fromList(<int>[0x1b, 0x63]));
  parser.finish();
  _expect(
    !screens.usingAlternate &&
        !screens.bracketedPasteMode &&
        _allBlank(screens.primary) &&
        _allBlank(screens.alternate),
    'RIS through screen-set sink resets both grids',
  );
  _expect(sink.unsupportedSequenceCount == 0, 'all screen modes supported');

  final TerminalScreen single = TerminalScreen(rows: 1, columns: 1);
  final TerminalScreenParserSink singleSink = TerminalScreenParserSink(single);
  final VtParser singleParser = VtParser(sink: singleSink);
  singleParser.parse(Uint8List.fromList(_csi('?1049h')));
  singleParser.finish();
  _expect(
    singleSink.unsupportedSequenceCount == 1,
    'screen-set mode is safely rejected by a single-screen sink',
  );
}

void _testParserScreenSetChunkIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    ..._csi('2;2H'),
    ..._csi('1;31m'),
    0x50,
    ..._csi('?1049h'),
    ..._csi('3;4H'),
    ..._csi('32m'),
    0x41,
    ..._csi('?1049l'),
    0x51,
    ..._csi('?47h'),
    0x42,
    ..._csi('?47l'),
    0x1b,
    0x28,
    0x30,
    0x71,
    0x1b,
    0x28,
    0x42,
    0x1b,
    0x29,
    0x30,
    0x0e,
    0x78,
    0x0f,
    0x1b,
    0x29,
    0x42,
  ]);
  final List<int> expected = _screenSetSnapshot(input);
  for (int split = 0; split <= input.length; split++) {
    _expectList(
      _screenSetSnapshot(input, <int>[split, input.length - split]),
      expected,
      'screen-set split $split',
    );
  }
  _expectList(
    _screenSetSnapshot(input, List<int>.filled(input.length, 1)),
    expected,
    'screen-set bytewise chunks',
  );

  final TerminalScreenSet reviewed = _parseScreenSet(input);
  _expect(_rowText(reviewed.primary, 1) == '.PQ─│', 'reviewed primary state');
  _expect(
    _rowText(reviewed.alternate, 2) == '...AB',
    'reviewed alternate state',
  );
  _expect(!reviewed.usingAlternate, 'reviewed stream returns to primary');
}

TerminalScreenSet _parseScreenSet(Uint8List input, [List<int>? chunks]) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 5);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  parser.finish();
  _expect(sink.unsupportedSequenceCount == 0, 'screen-set stream supported');
  return screens;
}

List<int> _screenSetSnapshot(Uint8List input, [List<int>? chunks]) {
  final TerminalScreenSet screens = _parseScreenSet(input, chunks);
  return <int>[
    screens.activeKind.index,
    screens.mode1049Active ? 1 : 0,
    screens.bracketedPasteMode ? 1 : 0,
    screens.transitionGeneration,
    for (final TerminalScreen screen in <TerminalScreen>[
      screens.primary,
      screens.alternate,
    ]) ...<int>[
      screen.cursorRow,
      screen.cursorColumn,
      screen.savedCursorRow,
      screen.savedCursorColumn,
      screen.currentForeground,
      screen.currentBackground,
      screen.currentStyleAttributes,
      screen.savedForeground,
      screen.savedBackground,
      screen.styleTable.attributesAt(screen.savedStyleId),
      screen.wrapPending ? 1 : 0,
      screen.generation,
      for (int row = 0; row < screen.rows; row++)
        for (int column = 0; column < screen.columns; column++) ...<int>[
          screen.contentAt(row, column),
          screen.foregroundAt(row, column),
          screen.backgroundAt(row, column),
          screen.styleTable.attributesAt(screen.styleAt(row, column)),
        ],
    ],
  ];
}

bool _allBlank(TerminalScreen screen) {
  for (int row = 0; row < screen.rows; row++) {
    for (int column = 0; column < screen.columns; column++) {
      if (screen.contentAt(row, column) != 0 ||
          screen.foregroundAt(row, column) != 0 ||
          screen.backgroundAt(row, column) != 0 ||
          screen.styleAt(row, column) != 0 ||
          screen.hyperlinkAt(row, column) != 0 ||
          screen.widthFlagsAt(row, column) != TerminalCellFlags.narrow) {
        return false;
      }
    }
  }
  return true;
}

String _rowText(TerminalScreen screen, int row) {
  final StringBuffer result = StringBuffer();
  for (int column = 0; column < screen.columns; column++) {
    final int content = screen.contentAt(row, column);
    result.writeCharCode(content == 0 ? 0x2e : content);
  }
  return result.toString();
}

List<int> _csi(String body) => <int>[0x1b, 0x5b, ...ascii.encode(body)];

void _expectList(List<int> actual, List<int> expected, String message) {
  if (actual.length != expected.length) {
    throw StateError('test failed: $message; $actual != $expected');
  }
  for (int index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      throw StateError('test failed: $message; $actual != $expected');
    }
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('test failed: $message');
  }
}
