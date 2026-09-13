import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalStyleTests();

void runTerminalStyleTests() {
  _testStyleTableBoundsAndStableIds();
  _testRenditionPrintSaveRestoreResetAndErase();
  _testSgrAttributesAndColors();
  _testSgrUnderlineAndPaletteFamilies();
  _testProtectedSelectiveErase();
  _testSgrMalformedGroupsAndUnknownParameters();
  _testSgrChunkIndependence();
}

void _testStyleTableBoundsAndStableIds() {
  final TerminalStyleTable table = TerminalStyleTable(capacity: 4);
  _expect(table.definitionCount == 0, 'style table starts with default only');
  _expect(table.attributesAt(0) == 0, 'style zero is default');
  final int generation = table.generation;
  final int bold = table.intern(TerminalStyleAttributes.bold);
  _expect(bold == 1, 'first nondefault style ID');
  _expect(table.definitionCount == 1, 'style definition count');
  _expect(table.generation > generation, 'new style advances generation');
  final int stableGeneration = table.generation;
  _expect(
    table.intern(TerminalStyleAttributes.bold) == bold,
    'equal style reuses ID',
  );
  _expect(
    table.generation == stableGeneration,
    'equal style does not advance generation',
  );

  final int curlyAttributes = TerminalStyleAttributes.withUnderline(
    TerminalStyleAttributes.italic,
    TerminalUnderlineStyle.curly,
  );
  final int curly = table.intern(curlyAttributes);
  _expect(curly == 2, 'second style ID');
  _expect(
    TerminalStyleAttributes.underline(table.attributesAt(curly)) ==
        TerminalUnderlineStyle.curly,
    'underline kind round trip',
  );
  _expect(
    TerminalStyleAttributes.has(
      table.attributesAt(curly),
      TerminalStyleAttributes.italic,
    ),
    'style flag round trip',
  );

  final int coloredCurly = table.intern(curlyAttributes, underlineColor: 7);
  _expect(
    coloredCurly == 3 &&
        table.attributesAt(coloredCurly) == curlyAttributes &&
        table.underlineColorAt(coloredCurly) == 7 &&
        table.intern(curlyAttributes, underlineColor: 7) == coloredCurly,
    'underline color participates in stable style identity',
  );
  final int overline = table.intern(TerminalStyleAttributes.overline);
  _expect(
    overline == 4 &&
        TerminalStyleAttributes.has(
          table.attributesAt(overline),
          TerminalStyleAttributes.overline,
        ) &&
        table.underlineColorAt(overline) == 0,
    'overline and default underline color round trip',
  );

  final int fullGeneration = table.generation;
  _expectThrowsStateError(
    () => table.intern(TerminalStyleAttributes.faint),
    'style capacity is hard bounded',
  );
  _expect(table.definitionCount == 4, 'capacity failure is atomic');
  _expect(table.generation == fullGeneration, 'capacity failure generation');
  _expectThrowsArgumentError(
    () => table.intern(1 << 15),
    'unknown style flag rejected',
  );
  _expectThrowsArgumentError(
    () => TerminalStyleTable().intern(0, underlineColor: 257),
    'invalid underline color rejected',
  );
  _expectThrowsArgumentError(
    () => TerminalStyleAttributes.withUnderline(
      6 << TerminalStyleAttributes.underlineShift,
      TerminalUnderlineStyle.single,
    ),
    'invalid packed underline rejected',
  );
  _expectThrowsArgumentError(
    () => TerminalStyleTable(capacity: 0),
    'zero style capacity rejected',
  );
}

void _testRenditionPrintSaveRestoreResetAndErase() {
  final TerminalStyleTable styles = TerminalStyleTable();
  final TerminalScreen screen = TerminalScreen(
    rows: 2,
    columns: 5,
    styleTable: styles,
  );
  final int attributes =
      TerminalStyleAttributes.bold | TerminalStyleAttributes.italic;
  screen.setCurrentRendition(
    foreground: 4,
    background: 0x80112233,
    styleAttributes: attributes,
    underlineColor: 6,
  );
  final int styleId = screen.currentStyleId;
  screen.printNarrowScalar(0x41);
  _expect(screen.contentAt(0, 0) == 0x41, 'rendition print content');
  _expect(screen.foregroundAt(0, 0) == 4, 'rendition print foreground');
  _expect(
    screen.backgroundAt(0, 0) == 0x80112233,
    'rendition print background',
  );
  _expect(screen.styleAt(0, 0) == styleId, 'rendition print style ID');
  _expect(
    styles.underlineColorAt(styleId) == 6,
    'rendition print keeps underline color in its style definition',
  );
  _expect(
    styles.attributesAt(styleId) == attributes,
    'printed style resolves through shared table',
  );

  screen.setCursorPosition(1, 3);
  screen.saveCursor();
  screen.setCurrentRendition(
    foreground: 0,
    background: 7,
    styleAttributes: TerminalStyleAttributes.faint,
  );
  screen.setCursorPosition(0, 0);
  screen.restoreCursor();
  _expect(
    screen.cursorRow == 1 && screen.cursorColumn == 3,
    'restore returns saved position',
  );
  _expect(
    screen.currentForeground == 4 &&
        screen.currentBackground == 0x80112233 &&
        screen.currentStyleId == styleId &&
        screen.currentUnderlineColor == 6,
    'restore returns saved rendition',
  );

  screen.setCursorPosition(0, 0);
  screen.eraseCharacters(1);
  _expect(screen.contentAt(0, 0) == 0, 'erase clears content');
  _expect(screen.foregroundAt(0, 0) == 0, 'erase clears foreground');
  _expect(
    screen.backgroundAt(0, 0) == 0x80112233,
    'erase preserves current background for BCE',
  );
  _expect(screen.styleAt(0, 0) == 0, 'erase clears text attributes');

  final int renditionGeneration = screen.generation;
  final int styleDefinitions = styles.definitionCount;
  for (final void Function() mutate in <void Function()>[
    () => screen.setCurrentRendition(foreground: 257),
    () => screen.setCurrentRendition(background: 0x81000000),
    () => screen.setCurrentRendition(styleAttributes: 1 << 15),
    () => screen.setCurrentRendition(underlineColor: 257),
  ]) {
    _expectThrowsArgumentError(mutate, 'invalid rendition rejected');
    _expect(screen.currentForeground == 4, 'invalid rendition foreground');
    _expect(
      screen.currentBackground == 0x80112233,
      'invalid rendition background',
    );
    _expect(screen.currentStyleId == styleId, 'invalid rendition style');
    _expect(
      screen.generation == renditionGeneration,
      'invalid rendition leaves screen generation',
    );
    _expect(
      styles.definitionCount == styleDefinitions,
      'invalid rendition leaves style table',
    );
  }

  screen.resetTerminalState();
  _expect(
    screen.currentForeground == 0 &&
        screen.currentBackground == 0 &&
        screen.currentStyleId == 0 &&
        screen.currentUnderlineColor == 0,
    'terminal reset clears current rendition',
  );
  _expect(
    screen.savedForeground == 0 &&
        screen.savedBackground == 0 &&
        screen.savedStyleId == 0,
    'terminal reset clears saved rendition',
  );
  _expect(
    styles.definitionCount == styleDefinitions,
    'terminal reset keeps referenced immutable styles',
  );
}

void _testSgrAttributesAndColors() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 5);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._csi('1;2;3;4;5;7;8;9;31;104;53;58:2::9:8:7m'),
      0x41,
      ..._csi('22;23;24;25;27;28;29;39;49;55;59m'),
      0x42,
      ..._csi('4:3;38:2::1:2:3;48:5:196m'),
      0x43,
      ..._csi('21;38;2;10;20;30;48;5;7m'),
      0x44,
      ..._csi('m'),
      0x45,
    ]),
  );
  parser.finish();

  final int all = screen.styleTable.attributesAt(screen.styleAt(0, 0));
  _expect(
    TerminalStyleAttributes.has(all, TerminalStyleAttributes.bold) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.faint) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.italic) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.blink) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.inverse) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.conceal) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.strike) &&
        TerminalStyleAttributes.has(all, TerminalStyleAttributes.overline) &&
        TerminalStyleAttributes.underline(all) == TerminalUnderlineStyle.single,
    'SGR sets base and extended text attributes',
  );
  _expect(
    screen.foregroundAt(0, 0) == 2 && screen.backgroundAt(0, 0) == 13,
    'SGR maps ANSI normal and bright colors to palette tokens',
  );
  _expect(
    screen.styleTable.underlineColorAt(screen.styleAt(0, 0)) == 0x80090807,
    'SGR maps direct underline color into style identity',
  );
  _expect(
    screen.styleAt(0, 1) == 0 &&
        screen.foregroundAt(0, 1) == 0 &&
        screen.backgroundAt(0, 1) == 0 &&
        screen.styleTable.underlineColorAt(screen.styleAt(0, 1)) == 0,
    'SGR unset and default colors restore default rendition',
  );

  final int curly = screen.styleTable.attributesAt(screen.styleAt(0, 2));
  _expect(
    TerminalStyleAttributes.underline(curly) == TerminalUnderlineStyle.curly,
    'colon SGR applies curly underline',
  );
  _expect(
    screen.foregroundAt(0, 2) == 0x80010203 && screen.backgroundAt(0, 2) == 197,
    'colon SGR applies RGB and indexed colors',
  );

  final int doubleUnderline = screen.styleTable.attributesAt(
    screen.styleAt(0, 3),
  );
  _expect(
    TerminalStyleAttributes.underline(doubleUnderline) ==
        TerminalUnderlineStyle.double,
    'SGR 21 applies double underline',
  );
  _expect(
    screen.foregroundAt(0, 3) == 0x800a141e && screen.backgroundAt(0, 3) == 8,
    'semicolon SGR applies RGB and indexed colors',
  );
  _expect(
    screen.styleAt(0, 4) == 0 &&
        screen.foregroundAt(0, 4) == 0 &&
        screen.backgroundAt(0, 4) == 0,
    'empty SGR resets rendition',
  );
  _expect(sink.unsupportedSequenceCount == 0, 'supported SGR has no rejects');
}

void _testProtectedSelectiveErase() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 6);
  final TerminalScreenParserSink sink = _parse(screen, <int>[
    ..._csi('1"q'),
    ...utf8.encode('界'),
    ..._csi('0"q'),
    ...ascii.encode('AB'),
  ]);
  _expect(
    screen.widthFlagsAt(0, 0) ==
            (TerminalCellFlags.wide | TerminalCellFlags.protected) &&
        screen.widthFlagsAt(0, 1) ==
            (TerminalCellFlags.continuation | TerminalCellFlags.protected) &&
        screen.widthFlagsAt(0, 2) == TerminalCellFlags.narrow &&
        !screen.currentCellProtected,
    'DECSCA marks complete later cell groups and can return to erasable mode',
  );

  screen.setCursorPosition(0, 1);
  _parse(screen, _csi('?0K'));
  screen.validateCellTopology();
  _expect(
    screen.contentAt(0, 0) != 0 &&
        screen.contentAt(0, 1) == 0 &&
        screen.contentAt(0, 2) == 0 &&
        screen.contentAt(0, 3) == 0,
    'DECSEL preserves a protected wide group and erases later cells',
  );

  screen.eraseInLine(2);
  _expect(
    screen.contentAt(0, 0) == 0 &&
        screen.widthFlagsAt(0, 0) == TerminalCellFlags.narrow,
    'ordinary EL ignores DEC protection',
  );

  _parse(screen, _csi('1"q'));
  screen.saveCursor();
  _parse(screen, _csi('2"q'));
  screen.restoreCursor();
  screen.printNarrowScalar(0x50);
  _expect(
    screen.savedCellProtected &&
        screen.currentCellProtected &&
        screen.widthFlagsAt(0, 1) & TerminalCellFlags.protected != 0,
    'cursor save and restore retains character protection',
  );
  final TerminalScreen resized = screen.resized(rows: 3, columns: 7);
  _expect(
    resized.currentCellProtected && resized.savedCellProtected,
    'resize and reflow retain current and saved protection',
  );
  final TerminalScreenParserSink invalid = _parse(screen, _csi('3"q'));
  _expect(
    screen.currentCellProtected &&
        sink.unsupportedSequenceCount == 0 &&
        invalid.unsupportedSequenceCount == 1,
    'invalid DECSCA is counted without changing protection',
  );
  screen.resetTerminalState();
  _expect(
    !screen.currentCellProtected && !screen.savedCellProtected,
    'terminal reset clears current and saved protection',
  );
}

void _testSgrMalformedGroupsAndUnknownParameters() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 3);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._csi('38:2:1:2m'),
      0x41,
      ..._csi('48;5;300m'),
      0x42,
      ..._csi('1;999;31m'),
      0x43,
    ]),
  );
  parser.finish();
  _expect(
    screen.foregroundAt(0, 0) == 0 && screen.backgroundAt(0, 0) == 0,
    'short colon color group is atomic no-op',
  );
  _expect(
    screen.foregroundAt(0, 1) == 0 && screen.backgroundAt(0, 1) == 0,
    'out-of-range indexed group is atomic no-op',
  );
  final int last = screen.styleTable.attributesAt(screen.styleAt(0, 2));
  _expect(
    TerminalStyleAttributes.has(last, TerminalStyleAttributes.bold) &&
        screen.foregroundAt(0, 2) == 2,
    'known parameters surrounding unknown SGR still apply',
  );
  _expect(
    sink.unsupportedSequenceCount == 3,
    'invalid groups and unknown SGR are counted',
  );

  final TerminalScreen bounded = TerminalScreen(
    rows: 1,
    columns: 2,
    styleTable: TerminalStyleTable(capacity: 1),
  );
  final TerminalScreenParserSink boundedSink = _parse(bounded, <int>[
    ..._csi('1m'),
    0x41,
    ..._csi('3m'),
    0x42,
  ]);
  _expect(
    bounded.styleAt(0, 0) == bounded.styleAt(0, 1),
    'style-table exhaustion leaves current rendition unchanged',
  );
  _expect(
    boundedSink.unsupportedSequenceCount == 1,
    'style-table exhaustion is contained by the stream sink',
  );
}

void _testSgrUnderlineAndPaletteFamilies() {
  final TerminalScreen underlines = TerminalScreen(rows: 1, columns: 6);
  final List<int> underlineInput = <int>[];
  for (int variant = 0; variant < 6; variant++) {
    underlineInput.addAll(_csi('4:${variant}m'));
    underlineInput.add(0x41 + variant);
  }
  _parse(underlines, underlineInput);
  for (int variant = 0; variant < 6; variant++) {
    final int attributes = underlines.styleTable.attributesAt(
      underlines.styleAt(0, variant),
    );
    _expect(
      TerminalStyleAttributes.underline(attributes) ==
          TerminalUnderlineStyle.values[variant],
      'SGR underline variant $variant',
    );
  }

  final TerminalScreen colors = TerminalScreen(rows: 1, columns: 32);
  final List<int> colorInput = <int>[];
  for (int code = 30; code <= 37; code++) {
    colorInput.addAll(_csi('${code}m'));
    colorInput.add(0x41);
  }
  for (int code = 90; code <= 97; code++) {
    colorInput.addAll(_csi('${code}m'));
    colorInput.add(0x42);
  }
  for (int code = 40; code <= 47; code++) {
    colorInput.addAll(_csi('${code}m'));
    colorInput.add(0x43);
  }
  for (int code = 100; code <= 107; code++) {
    colorInput.addAll(_csi('${code}m'));
    colorInput.add(0x44);
  }
  _parse(colors, colorInput);
  for (int index = 0; index < 8; index++) {
    _expect(
      colors.foregroundAt(0, index) == index + 1,
      'normal foreground palette token $index',
    );
    _expect(
      colors.foregroundAt(0, index + 8) == index + 9,
      'bright foreground palette token $index',
    );
    _expect(
      colors.backgroundAt(0, index + 16) == index + 1,
      'normal background palette token $index',
    );
    _expect(
      colors.backgroundAt(0, index + 24) == index + 9,
      'bright background palette token $index',
    );
  }
}

void _testSgrChunkIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    ..._csi('1;4:5;38;5;255;48:2::7:8:9m'),
    ...ascii.encode('AB'),
    ..._csi('22;24;39;49m'),
    0x43,
  ]);
  final List<int> expected = _sgrSnapshot(input);
  for (int split = 0; split <= input.length; split++) {
    _expectList(
      _sgrSnapshot(input, <int>[split, input.length - split]),
      expected,
      'SGR split $split',
    );
  }
  _expectList(
    _sgrSnapshot(input, List<int>.filled(input.length, 1)),
    expected,
    'SGR bytewise chunks',
  );
}

TerminalScreenParserSink _parse(TerminalScreen screen, List<int> input) {
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(Uint8List.fromList(input));
  parser.finish();
  return sink;
}

List<int> _sgrSnapshot(Uint8List input, [List<int>? chunks]) {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 3);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  parser.finish();
  return <int>[
    for (int column = 0; column < 3; column++) ...<int>[
      screen.contentAt(0, column),
      screen.foregroundAt(0, column),
      screen.backgroundAt(0, column),
      screen.styleTable.attributesAt(screen.styleAt(0, column)),
      screen.styleTable.underlineColorAt(screen.styleAt(0, column)),
    ],
    screen.currentForeground,
    screen.currentBackground,
    screen.currentStyleAttributes,
    screen.currentUnderlineColor,
    sink.unsupportedSequenceCount,
  ];
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

void _expectThrowsArgumentError(void Function() body, String message) {
  try {
    body();
  } on ArgumentError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectThrowsStateError(void Function() body, String message) {
  try {
    body();
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
