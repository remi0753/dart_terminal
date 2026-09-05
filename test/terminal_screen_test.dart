import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalScreenTests();

void runTerminalScreenTests() {
  _testStorageDefaultsAndBounds();
  _testNarrowCellStorageAndAtomicValidation();
  _testDamageCoalescingAndRowMetadata();
  _testCursorSaveRestore();
  _testTabStops();
}

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
    0x1f600,
    foreground: 0x80112233,
    background: 256,
    style: 65534,
    hyperlink: 42,
    isProtected: true,
  );
  _expect(screen.contentAt(1, 2) == 0x1f600, 'stored scalar');
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
    0x1f600,
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
    () => screen.setNarrowCell(1, 2, 0x41, foreground: 257),
    () => screen.setNarrowCell(1, 2, 0x41, background: 0x81000000),
    () => screen.setNarrowCell(1, 2, 0x41, style: 65535),
    () => screen.setNarrowCell(1, 2, 0x41, hyperlink: -1),
  ]) {
    _expectThrowsArgumentError(mutate, 'invalid cell field rejected');
    _expect(screen.contentAt(1, 2) == 0x1f600, 'invalid write is atomic');
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

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('test failed: $message');
  }
}
