import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalPaletteTests();

void runTerminalPaletteTests() {
  _testXtermPaletteDefaultsAndResolution();
  _testPaletteMutationResetDamageAndAtomicity();
  _testDefaultColorMutationAndReset();
  _testOscColorMutationAndRejection();
  _testOscColorChunkIndependence();
}

void _testXtermPaletteDefaultsAndResolution() {
  final TerminalPalette palette = TerminalPalette();
  const List<int> base = <int>[
    0x80000000,
    0x80cd0000,
    0x8000cd00,
    0x80cdcd00,
    0x800000ee,
    0x80cd00cd,
    0x8000cdcd,
    0x80e5e5e5,
    0x807f7f7f,
    0x80ff0000,
    0x8000ff00,
    0x80ffff00,
    0x805c5cff,
    0x80ff00ff,
    0x8000ffff,
    0x80ffffff,
  ];
  _expect(palette.typedStorageBytes == 2048, 'palette typed storage bytes');
  _expect(palette.generation == 1, 'initial palette generation');
  for (int index = 0; index < base.length; index++) {
    _expect(palette.colorAt(index) == base[index], 'base color $index');
  }

  const List<int> levels = <int>[0, 95, 135, 175, 215, 255];
  int index = 16;
  for (final int red in levels) {
    for (final int green in levels) {
      for (final int blue in levels) {
        _expect(
          palette.colorAt(index) ==
              0x80000000 | (red << 16) | (green << 8) | blue,
          'color cube index $index',
        );
        index++;
      }
    }
  }
  for (int step = 0; step < 24; step++) {
    final int component = 8 + step * 10;
    _expect(
      palette.colorAt(232 + step) ==
          0x80000000 | (component << 16) | (component << 8) | component,
      'gray ramp index ${232 + step}',
    );
  }
  _expect(
    palette.defaultForeground == TerminalPalette.xtermDefaultForeground,
    'default foreground',
  );
  _expect(
    palette.defaultBackground == TerminalPalette.xtermDefaultBackground,
    'default background',
  );
  _expect(
    palette.resolveToken(0, foreground: true) == palette.defaultForeground,
    'foreground default token resolves',
  );
  _expect(
    palette.resolveToken(0, foreground: false) == palette.defaultBackground,
    'background default token resolves',
  );
  _expect(
    palette.resolveToken(1, foreground: true) == palette.colorAt(0) &&
        palette.resolveToken(256, foreground: false) == palette.colorAt(255),
    'palette token endpoints resolve',
  );
  _expect(
    palette.resolveToken(0x80123456, foreground: true) == 0x80123456,
    'direct token resolves unchanged',
  );
  _expectThrowsArgumentError(
    () => palette.resolveToken(257, foreground: true),
    'invalid logical token rejected',
  );
  _expectThrowsRangeError(
    () => palette.colorAt(256),
    'palette index boundary rejected',
  );

  final List<int> custom = List<int>.filled(256, 0x80112233);
  final TerminalPalette configured = TerminalPalette(
    colors: custom,
    defaultForeground: 0x80445566,
    defaultBackground: 0x80778899,
  );
  custom[0] = 0x80ffffff;
  _expect(
    configured.colorAt(0) == 0x80112233,
    'configured palette copies caller storage',
  );
  _expectThrowsArgumentError(
    () => TerminalPalette(colors: <int>[0x80000000]),
    'configured palette requires 256 entries',
  );
  final List<int> invalid = List<int>.filled(256, 0x80000000)..[255] = 0;
  _expectThrowsArgumentError(
    () => TerminalPalette(colors: invalid),
    'configured palette rejects untagged colors',
  );
}

void _testPaletteMutationResetDamageAndAtomicity() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 3);
  screen.setNarrowCell(0, 0, 0x41, foreground: 2);
  screen.clearDamage();
  final int original = screen.paletteColorAt(1);
  final int screenGeneration = screen.generation;
  final int paletteGeneration = screen.paletteGeneration;
  screen.setPaletteColor(1, 0x80123456);
  _expect(screen.paletteColorAt(1) == 0x80123456, 'palette color mutation');
  _expect(screen.foregroundAt(0, 0) == 2, 'cell keeps logical palette token');
  _expect(
    screen.resolveColorToken(screen.foregroundAt(0, 0), foreground: true) ==
        0x80123456,
    'mutated palette resolves existing cell token',
  );
  _expect(
    screen.generation > screenGeneration &&
        screen.paletteGeneration > paletteGeneration,
    'palette mutation advances resource and screen generations',
  );
  for (int row = 0; row < screen.rows; row++) {
    _expect(
      screen.dirtyStartAt(row) == 0 && screen.dirtyEndAt(row) == screen.columns,
      'palette mutation dirties full row $row',
    );
  }

  screen.clearDamage();
  final int unchangedScreenGeneration = screen.generation;
  final int unchangedPaletteGeneration = screen.paletteGeneration;
  screen.setPaletteColor(1, 0x80123456);
  _expect(
    screen.generation == unchangedScreenGeneration &&
        screen.paletteGeneration == unchangedPaletteGeneration,
    'identical palette mutation is idempotent',
  );
  _expect(
    !screen.isRowDirty(0) && !screen.isRowDirty(1),
    'no-op has no damage',
  );

  screen.setPaletteColors(<int>[1, 1], <int>[0x80abcdef, 0x80123456]);
  _expect(
    screen.generation == unchangedScreenGeneration &&
        screen.paletteGeneration == unchangedPaletteGeneration,
    'duplicate batch with original final value is a no-op',
  );

  for (final void Function() mutate in <void Function()>[
    () => screen.setPaletteColor(-1, 0x80000000),
    () => screen.setPaletteColor(0, 0),
    () => screen.setPaletteColors(<int>[2, 256], <int>[0x80111111, 0x80222222]),
    () => screen.setPaletteColors(<int>[2], <int>[], 1),
    () => screen.setPaletteColors(<int>[2], <int>[0x80111111], 0),
    () => screen.setPaletteColors(
      List<int>.filled(TerminalPalette.maxBatchEntries + 1, 0),
      List<int>.filled(TerminalPalette.maxBatchEntries + 1, 0x80000000),
    ),
  ]) {
    _expectThrowsArgumentError(mutate, 'invalid palette batch rejected');
    _expect(screen.paletteColorAt(1) == 0x80123456, 'invalid batch is atomic');
    _expect(
      screen.generation == unchangedScreenGeneration &&
          screen.paletteGeneration == unchangedPaletteGeneration,
      'invalid batch leaves generations unchanged',
    );
  }

  screen.resetPaletteColor(1);
  _expect(screen.paletteColorAt(1) == original, 'individual palette reset');
  screen.setPaletteColor(2, 0x80abcdef);
  screen.setPaletteColor(3, 0x80101010);
  screen.resetPalette();
  _expect(
    screen.paletteColorAt(2) == TerminalPalette().colorAt(2) &&
        screen.paletteColorAt(3) == TerminalPalette().colorAt(3),
    'whole palette reset',
  );
}

void _testDefaultColorMutationAndReset() {
  final TerminalPalette configured = TerminalPalette(
    defaultForeground: 0x80111111,
    defaultBackground: 0x80222222,
  );
  final TerminalScreen screen = TerminalScreen(
    rows: 1,
    columns: 1,
    palette: configured,
  );
  screen.clearDamage();
  screen.setDefaultForegroundColor(0x80333333);
  screen.setDefaultBackgroundColor(0x80444444);
  _expect(
    screen.resolveColorToken(0, foreground: true) == 0x80333333 &&
        screen.resolveColorToken(0, foreground: false) == 0x80444444,
    'default color mutation changes token-zero resolution',
  );
  _expect(screen.isRowDirty(0), 'default color mutation damages screen');
  screen.resetDefaultForegroundColor();
  screen.resetDefaultBackgroundColor();
  _expect(
    screen.defaultForegroundColor == 0x80111111 &&
        screen.defaultBackgroundColor == 0x80222222,
    'default colors reset to configured values',
  );
  _expectThrowsArgumentError(
    () => screen.setDefaultForegroundColor(1),
    'default foreground requires direct color',
  );
  _expectThrowsArgumentError(
    () => screen.setDefaultBackgroundColor(0x81000000),
    'default background rejects reserved bits',
  );

  screen.setPaletteColor(0, 0x80555555);
  screen.resetScreen();
  _expect(
    screen.paletteColorAt(0) == 0x80555555,
    'RIS does not silently reset palette resources',
  );
}

void _testOscColorMutationAndRejection() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 2);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('4;1;#123;200;rgb:ffff/8000/0000'),
      ..._osc('10;#abcdef', bell: false),
      ..._osc('11;rgb:0/f/0'),
    ]),
  );
  _expect(screen.paletteColorAt(1) == 0x80112233, 'OSC 4 hash color');
  _expect(screen.paletteColorAt(200) == 0x80ff8000, 'OSC 4 scaled rgb color');
  _expect(
    screen.defaultForegroundColor == 0x80abcdef &&
        screen.defaultBackgroundColor == 0x8000ff00,
    'OSC 10/11 mutate default colors',
  );
  final int generation = screen.paletteGeneration;
  final int originalTwo = screen.paletteColorAt(2);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('4;1;?'),
      ..._osc('4;2;#010203;999;#fff'),
      ..._osc('10;?'),
      ..._osc('11;#12'),
      ..._osc('0;title'),
    ]),
  );
  _expect(screen.paletteColorAt(1) == 0x80112233, 'OSC query is no-op');
  _expect(
    screen.paletteColorAt(2) == originalTwo,
    'malformed multi-entry OSC 4 is atomic',
  );
  _expect(
    screen.paletteGeneration == generation,
    'rejected OSC colors leave generation unchanged',
  );
  _expect(
    sink.unsupportedSequenceCount == 5,
    'query, malformed, and unrelated OSC are counted',
  );

  final StringBuffer oversized = StringBuffer('4');
  for (int item = 0; item <= TerminalPalette.maxBatchEntries; item++) {
    oversized.write(';${item % TerminalPalette.colorCount};#000');
  }
  parser.parse(Uint8List.fromList(_osc(oversized.toString())));
  _expect(
    sink.unsupportedSequenceCount == 6 &&
        screen.paletteGeneration == generation,
    'OSC palette mutation count is bounded and atomic',
  );

  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('104;1;200'),
      ..._osc('110'),
      ..._osc('111'),
    ]),
  );
  _expect(
    screen.paletteColorAt(1) == TerminalPalette().colorAt(1) &&
        screen.paletteColorAt(200) == TerminalPalette().colorAt(200),
    'OSC 104 resets selected entries',
  );
  _expect(
    screen.defaultForegroundColor == TerminalPalette.xtermDefaultForeground &&
        screen.defaultBackgroundColor == TerminalPalette.xtermDefaultBackground,
    'OSC 110/111 reset default colors',
  );
  parser.parse(Uint8List.fromList(_osc('4;7;#010203')));
  parser.parse(Uint8List.fromList(_osc('104')));
  parser.finish();
  _expect(
    screen.paletteColorAt(7) == TerminalPalette().colorAt(7),
    'OSC 104 without indexes resets all entries',
  );
}

void _testOscColorChunkIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    ..._osc('4;0;#123456;255;rgb:f/8/0'),
    ..._osc('10;rgb:1111/2222/3333', bell: false),
    ..._osc('11;#abc'),
    ..._osc('104;255'),
  ]);
  final List<int> expected = _oscSnapshot(input);
  for (int split = 0; split <= input.length; split++) {
    _expectList(
      _oscSnapshot(input, <int>[split, input.length - split]),
      expected,
      'OSC color split $split',
    );
  }
  _expectList(
    _oscSnapshot(input, List<int>.filled(input.length, 1)),
    expected,
    'OSC color bytewise chunks',
  );
}

List<int> _oscSnapshot(Uint8List input, [List<int>? chunks]) {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  screen.clearDamage();
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  parser.finish();
  return <int>[
    screen.paletteColorAt(0),
    screen.paletteColorAt(255),
    screen.defaultForegroundColor,
    screen.defaultBackgroundColor,
    screen.paletteGeneration,
    screen.generation,
    screen.dirtyStartAt(0),
    screen.dirtyEndAt(0),
    sink.unsupportedSequenceCount,
  ];
}

List<int> _osc(String payload, {bool bell = true}) => <int>[
  0x1b,
  0x5d,
  ...ascii.encode(payload),
  if (bell) 0x07 else ...<int>[0x1b, 0x5c],
];

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

void _expectThrowsRangeError(void Function() body, String message) {
  try {
    body();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('test failed: $message');
  }
}
