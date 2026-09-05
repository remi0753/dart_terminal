import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalDamageCopyTests();

void runTerminalDamageCopyTests() {
  _testEveryColumnAndLogicalRingRow();
  _testDestinationValidationIsAtomic();
  _testSourceBounds();
}

void _testEveryColumnAndLogicalRingRow() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 5);
  screen.setNarrowCell(
    1,
    1,
    0x41,
    foreground: 0x80010203,
    background: 17,
    style: 19,
    hyperlink: 23,
    isProtected: true,
  );
  screen.setWideCell(
    1,
    2,
    0x754c,
    foreground: 256,
    background: 3,
    style: 29,
    hyperlink: 31,
  );
  screen.scrollUp(1);

  final Uint32List content = Uint32List(6)..fillRange(0, 6, 0xffffffff);
  final Uint32List foreground = Uint32List(6)..fillRange(0, 6, 0xffffffff);
  final Uint32List background = Uint32List(6)..fillRange(0, 6, 0xffffffff);
  final Uint16List styles = Uint16List(6)..fillRange(0, 6, 0xffff);
  final Uint16List hyperlinks = Uint16List(6)..fillRange(0, 6, 0xffff);
  final Uint8List widthFlags = Uint8List(6)..fillRange(0, 6, 0xff);

  screen.copyPackedCellSpanTo(
    row: 0,
    firstColumn: 1,
    cellCount: 3,
    destinationOffset: 2,
    content: content,
    foreground: foreground,
    background: background,
    styles: styles,
    hyperlinks: hyperlinks,
    widthFlags: widthFlags,
  );
  _expect(
    content[0] == 0xffffffff &&
        content[1] == 0xffffffff &&
        content[2] == 0x41 &&
        content[3] == 0x754c &&
        content[4] == 0 &&
        content[5] == 0xffffffff,
    'logical ring-row subspan writes only its destination interval',
  );
  _expect(
    foreground[2] == 0x80010203 &&
        background[2] == 17 &&
        styles[2] == 19 &&
        hyperlinks[2] == 23 &&
        widthFlags[2] ==
            (TerminalCellFlags.narrow | TerminalCellFlags.protected),
    'narrow cell copies every packed column',
  );
  _expect(
    foreground[3] == 256 &&
        foreground[4] == 256 &&
        background[3] == 3 &&
        background[4] == 3 &&
        styles[3] == 29 &&
        styles[4] == 29 &&
        hyperlinks[3] == 31 &&
        hyperlinks[4] == 31 &&
        widthFlags[3] == TerminalCellFlags.wide &&
        widthFlags[4] == TerminalCellFlags.continuation,
    'wide lead and continuation copy every matching packed field',
  );
}

void _testDestinationValidationIsAtomic() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 3);
  screen.setNarrowCell(0, 0, 0x41, foreground: 2);
  final Uint32List content = Uint32List.fromList(<int>[7, 7, 7]);
  final Uint32List foreground = Uint32List.fromList(<int>[8, 8, 8]);
  final Uint32List background = Uint32List.fromList(<int>[9, 9, 9]);
  final Uint16List styles = Uint16List.fromList(<int>[10, 10, 10]);
  final Uint16List hyperlinks = Uint16List.fromList(<int>[11, 11, 11]);
  final Uint8List tooShort = Uint8List.fromList(<int>[12, 12]);

  _expectRange(
    () => screen.copyPackedCellSpanTo(
      row: 0,
      firstColumn: 0,
      cellCount: 3,
      destinationOffset: 0,
      content: content,
      foreground: foreground,
      background: background,
      styles: styles,
      hyperlinks: hyperlinks,
      widthFlags: tooShort,
    ),
    'one short destination rejects the whole copy',
  );
  _expect(
    _allEqual(content, 7) &&
        _allEqual(foreground, 8) &&
        _allEqual(background, 9) &&
        _allEqual(styles, 10) &&
        _allEqual(hyperlinks, 11) &&
        _allEqual(tooShort, 12),
    'destination validation occurs before any column mutation',
  );
}

void _testSourceBounds() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 3);
  Uint32List u32() => Uint32List(3);
  Uint16List u16() => Uint16List(3);
  Uint8List u8() => Uint8List(3);
  void copy(int row, int firstColumn, int cellCount, int destinationOffset) {
    screen.copyPackedCellSpanTo(
      row: row,
      firstColumn: firstColumn,
      cellCount: cellCount,
      destinationOffset: destinationOffset,
      content: u32(),
      foreground: u32(),
      background: u32(),
      styles: u16(),
      hyperlinks: u16(),
      widthFlags: u8(),
    );
  }

  for (final void Function() invalid in <void Function()>[
    () => copy(-1, 0, 1, 0),
    () => copy(1, 0, 1, 0),
    () => copy(0, -1, 1, 0),
    () => copy(0, 3, 1, 0),
    () => copy(0, 0, 0, 0),
    () => copy(0, 1, 3, 0),
    () => copy(0, 0, 1, -1),
    () => copy(0, 0, 1, 3),
  ]) {
    _expectRange(invalid, 'invalid source/destination span is rejected');
  }
}

bool _allEqual(List<int> values, int expected) {
  for (final int value in values) {
    if (value != expected) return false;
  }
  return true;
}

void _expectRange(void Function() action, String message) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
