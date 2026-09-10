import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalViewportTests();

void runTerminalViewportTests() {
  _testHistoryScreenProjectionAndNavigation();
  _testScrolledOutputStabilityEvictionAndClear();
  _testAlternateIsolationAndOffsetRestore();
  _testPromptNavigation();
  _testResizeIdentityAndReflowedHistoryWidth();
  _testGenerationAndAccessBounds();
}

void _testPromptNavigation() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 3,
    scrollback: TerminalScrollback(maxLines: 12, maxBytes: 10000, pageRows: 2),
  );
  final TerminalScreen screen = screens.primary;
  _setRow(screen, 0, 0x41, 601);
  screen.setRowFlags(0, TerminalRowFlags.prompt);
  _setRow(screen, 1, 0x42, 602);
  _setRow(screen, 2, 0x43, 603);
  screen.setRowFlags(2, TerminalRowFlags.prompt);
  screen.scrollUp(3);
  _setRow(screen, 0, 0x44, 604);
  _setRow(screen, 1, 0x45, 605);
  screen.setRowFlags(1, TerminalRowFlags.prompt | TerminalRowFlags.softWrapped);
  _setRow(screen, 2, 0x46, 605);
  screen.setRowFlags(2, TerminalRowFlags.prompt);
  screen.setCursorPosition(2, 0);

  final TerminalViewport viewport = screens.viewport;
  _expect(
    viewport.canJumpToPreviousPrompt && !viewport.canJumpToNextPrompt,
    'bottom can move only toward an older retained prompt',
  );
  _expect(
    viewport.jumpToPreviousPrompt() &&
        viewport.offset == 1 &&
        _rowLeads(viewport) == 'CDE',
    'previous skips unscrollable live prompt rows and selects newest history mark',
  );
  _expect(
    viewport.jumpToPreviousPrompt() &&
        viewport.offset == 3 &&
        _rowLeads(viewport) == 'ABC' &&
        !viewport.canJumpToPreviousPrompt,
    'repeated previous reaches the oldest retained prompt exactly once',
  );
  _expect(
    !viewport.jumpToPreviousPrompt() && viewport.offset == 3,
    'previous boundary is a no-op',
  );
  _expect(
    viewport.jumpToNextPrompt() && viewport.offset == 1,
    'next selects the following retained prompt',
  );
  _expect(
    viewport.jumpToNextPrompt() &&
        viewport.offset == 0 &&
        viewport.atBottom &&
        !viewport.canJumpToNextPrompt,
    'next collapses a wrapped prompt logical line and returns to live grid',
  );
  _expect(
    !viewport.jumpToNextPrompt() && viewport.offset == 0,
    'next boundary is a no-op',
  );

  viewport.jumpToPreviousPrompt();
  final int primaryOffset = viewport.offset;
  screens.setAlternateMode47(true);
  screens.alternate.setRowFlags(0, TerminalRowFlags.prompt);
  _expect(
    !viewport.canJumpToPreviousPrompt &&
        !viewport.canJumpToNextPrompt &&
        !viewport.jumpToPreviousPrompt() &&
        !viewport.jumpToNextPrompt() &&
        viewport.primaryOffset == primaryOffset,
    'alternate prompt flags cannot move or discard the retained primary offset',
  );
  screens.setAlternateMode47(false);

  final TerminalViewport empty = TerminalScreenSet(
    rows: 2,
    columns: 2,
  ).viewport;
  _expect(
    !empty.canJumpToPreviousPrompt &&
        !empty.canJumpToNextPrompt &&
        !empty.jumpToPreviousPrompt() &&
        !empty.jumpToNextPrompt() &&
        empty.atBottom,
    'missing prompt marks are deterministic no-ops',
  );
}

void _testHistoryScreenProjectionAndNavigation() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 2),
  );
  final TerminalScreen screen = screens.primary;
  _setRow(screen, 0, 0x41, 101);
  screen.setNarrowCell(
    0,
    1,
    0x61,
    foreground: 1,
    background: 2,
    style: 3,
    hyperlink: 4,
    isProtected: true,
  );
  _setRow(screen, 1, 0x42, 102);
  screen.setWideCell(1, 1, 0x754c, foreground: 5, background: 6);
  _setRow(screen, 2, 0x43, 103);
  screen.scrollUp(3);
  _setRow(screen, 0, 0x44, 104);
  _setRow(screen, 1, 0x45, 105);
  _setRow(screen, 2, 0x46, 106);
  screen.setCursorPosition(0, 2);

  final TerminalViewport viewport = screens.viewport;
  _expect(
    viewport.rows == 3 &&
        viewport.columns == 4 &&
        viewport.offset == 0 &&
        viewport.maximumOffset == 3 &&
        viewport.atBottom &&
        _rowLead(viewport, 0) == 0x44 &&
        _rowLead(viewport, 1) == 0x45 &&
        _rowLead(viewport, 2) == 0x46 &&
        !viewport.isHistoryRow(0),
    'bottom viewport projects the complete primary grid',
  );
  _expect(
    viewport.cursorRow == 0 && viewport.cursorColumn == 2,
    'bottom viewport projects the primary cursor',
  );

  viewport.scrollByRows(1);
  _expect(
    viewport.offset == 1 &&
        !viewport.atBottom &&
        _rowLead(viewport, 0) == 0x43 &&
        _rowLead(viewport, 1) == 0x44 &&
        _rowLead(viewport, 2) == 0x45 &&
        viewport.isHistoryRow(0) &&
        !viewport.isHistoryRow(1) &&
        viewport.logicalLineIdAt(0) == 103 &&
        viewport.logicalLineEpochAt(0) ==
            screens.scrollback.logicalLineEpochAt(2) &&
        viewport.rowFlagsAt(0) == TerminalRowFlags.output &&
        viewport.cursorRow == 1 &&
        viewport.cursorColumn == 2,
    'one-row offset crosses the history/screen boundary',
  );

  viewport.scrollByPages(1);
  _expect(
    viewport.offset == 3 &&
        _rowLead(viewport, 0) == 0x41 &&
        _rowLead(viewport, 1) == 0x42 &&
        _rowLead(viewport, 2) == 0x43 &&
        viewport.isHistoryRow(2) &&
        viewport.cursorRow == null &&
        viewport.cursorColumn == null,
    'page navigation clamps to the oldest retained row and hides cursor',
  );
  _expect(
    viewport.contentAt(0, 1) == 0x61 &&
        viewport.foregroundAt(0, 1) == 1 &&
        viewport.backgroundAt(0, 1) == 2 &&
        viewport.styleAt(0, 1) == 3 &&
        viewport.hyperlinkAt(0, 1) == 4 &&
        viewport.widthFlagsAt(0, 1) ==
            TerminalCellFlags.narrow | TerminalCellFlags.protected &&
        viewport.contentAt(1, 1) == 0x754c &&
        viewport.widthFlagsAt(1, 1) == TerminalCellFlags.wide &&
        viewport.widthFlagsAt(1, 2) == TerminalCellFlags.continuation,
    'viewport delegates every stored cell field and wide topology',
  );

  viewport.scrollByRows(-1);
  _expect(viewport.offset == 2, 'negative row delta moves toward the bottom');
  viewport.scrollToTop();
  _expect(viewport.offset == 3, 'scroll-to-top selects maximum offset');
  viewport.scrollToBottom();
  _expect(
    viewport.offset == 0 && viewport.atBottom,
    'scroll-to-bottom follows',
  );
}

void _testScrolledOutputStabilityEvictionAndClear() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 3,
    scrollback: TerminalScrollback(maxLines: 6, maxBytes: 10000, pageRows: 2),
  );
  final TerminalScreen screen = screens.primary;
  _setBatch(screen, const <int>[0x41, 0x42, 0x43], 201);
  screen.scrollUp(3);
  _setBatch(screen, const <int>[0x44, 0x45, 0x46], 204);
  screen.scrollUp(3);
  _setBatch(screen, const <int>[0x47, 0x48, 0x49], 207);

  final TerminalViewport viewport = screens.viewport;
  viewport.scrollByRows(2);
  _expect(
    _rowLeads(viewport) == 'EFG',
    'initial scrolled projection spans recent history and screen',
  );
  final int beforeAppend = viewport.generation;
  screen.scrollUp(1);
  _expect(
    viewport.offset == 3 &&
        viewport.maximumOffset == 5 &&
        _rowLeads(viewport) == 'EFG' &&
        viewport.generation > beforeAppend,
    'new output increases offset and preserves a retained viewport anchor',
  );

  viewport.scrollToTop();
  _expect(_rowLeads(viewport) == 'CDE', 'top clamps after first page eviction');
  screen.scrollUp(1);
  _expect(
    viewport.offset == 6 && _rowLeads(viewport) == 'CDE',
    'top anchor remains stable while it is retained',
  );
  screen.scrollUp(1);
  _expect(
    viewport.offset == 5 &&
        viewport.maximumOffset == 5 &&
        _rowLeads(viewport) == 'EFG',
    'evicted anchor clamps to the new oldest retained row',
  );

  screens.scrollback.clear();
  _expect(
    viewport.offset == 0 &&
        viewport.maximumOffset == 0 &&
        viewport.atBottom &&
        !viewport.isHistoryRow(0),
    'history clear clamps viewport to the active screen',
  );

  screen.scrollUp(1);
  viewport.scrollToTop();
  screens.scrollback.clear();
  screen.scrollUp(1);
  _expect(
    viewport.offset == 0 && viewport.atBottom,
    'clear followed by unseen output resets rather than revives the old anchor',
  );
}

void _testAlternateIsolationAndOffsetRestore() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 3);
  _setBatch(screens.primary, const <int>[0x41, 0x42], 301);
  screens.primary.scrollUp(2);
  _setBatch(screens.primary, const <int>[0x43, 0x44], 303);
  final TerminalViewport viewport = screens.viewport;
  viewport.scrollToTop();
  final int primaryOffset = viewport.offset;
  _expect(primaryOffset == 2, 'primary begins scrolled to retained history');

  screens.setAlternateMode47(true);
  _setBatch(screens.alternate, const <int>[0x58, 0x59], 401);
  _expect(
    viewport.offset == 0 &&
        viewport.maximumOffset == 0 &&
        viewport.atBottom &&
        _rowLeads(viewport) == 'XY' &&
        !viewport.isHistoryRow(0),
    'DEC 47 projects only alternate rows at offset zero',
  );
  viewport.scrollByRows(20);
  viewport.scrollByPages(2);
  viewport.scrollToTop();
  _expect(viewport.offset == 0, 'alternate navigation cannot change offset');
  screens.setAlternateMode47(false);
  _expect(
    viewport.offset == primaryOffset && _rowLeads(viewport) == 'AB',
    'DEC 47 return restores the primary viewport position',
  );

  screens.setAlternateMode1047(true);
  _expect(viewport.offset == 0, 'DEC 1047 alternate starts at zero offset');
  screens.setAlternateMode1047(false);
  _expect(
    viewport.offset == primaryOffset,
    'DEC 1047 return restores primary offset',
  );

  screens.setAlternateMode1049(true);
  _expect(viewport.offset == 0, 'DEC 1049 alternate starts at zero offset');
  screens.setAlternateMode1049(false);
  _expect(
    viewport.offset == primaryOffset,
    'DEC 1049 return restores primary offset',
  );
}

void _testResizeIdentityAndReflowedHistoryWidth() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 3);
  _setRow(screens.primary, 0, 0x41, 501);
  screens.primary.scrollUp(1);
  final TerminalViewport viewport = screens.viewport;
  viewport.scrollToTop();
  final int generation = viewport.generation;

  screens.resize(rows: 2, columns: 5);
  _expect(
    identical(viewport, screens.viewport) &&
        viewport.rows == 2 &&
        viewport.columns == 5 &&
        viewport.offset == 1 &&
        viewport.maximumOffset == 1 &&
        viewport.columnsAt(0) == 5 &&
        viewport.columnsAt(1) == 5 &&
        viewport.contentAt(0, 0) == 0x41 &&
        viewport.generation > generation,
    'resize preserves viewport identity and reflows history to the new width',
  );
}

void _testGenerationAndAccessBounds() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 2);
  final TerminalViewport viewport = screens.viewport;
  final int initial = viewport.generation;
  _expect(
    viewport.generation == initial,
    'unchanged reads are revision-neutral',
  );
  screens.primary.setNarrowCell(0, 0, 0x41);
  final int mutated = viewport.generation;
  _expect(mutated > initial, 'visible screen mutation advances revision');
  _expect(
    viewport.generation == mutated,
    'observed mutation advances only once',
  );

  _expectThrowsRangeError(
    () => viewport.contentAt(-1, 0),
    'negative viewport row is rejected',
  );
  _expectThrowsRangeError(
    () => viewport.contentAt(2, 0),
    'viewport row beyond height is rejected',
  );
  _expectThrowsRangeError(
    () => viewport.contentAt(0, 2),
    'column beyond projected source width is rejected',
  );
}

void _setBatch(TerminalScreen screen, List<int> scalars, int firstLineId) {
  for (int row = 0; row < scalars.length; row++) {
    _setRow(screen, row, scalars[row], firstLineId + row);
  }
}

void _setRow(TerminalScreen screen, int row, int scalar, int logicalLineId) {
  screen.setNarrowCell(row, 0, scalar);
  screen.setRowFlags(row, TerminalRowFlags.output);
  screen.setLogicalLineId(row, logicalLineId);
}

int _rowLead(TerminalViewport viewport, int row) => viewport.contentAt(row, 0);

String _rowLeads(TerminalViewport viewport) => String.fromCharCodes(
  List<int>.generate(viewport.rows, (int row) => _rowLead(viewport, row)),
);

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(description);
  }
}

void _expectThrowsRangeError(void Function() operation, String description) {
  try {
    operation();
  } on RangeError {
    return;
  }
  throw StateError(description);
}
