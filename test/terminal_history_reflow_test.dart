import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalHistoryReflowTests();

void runTerminalHistoryReflowTests() {
  _testCrossPageLogicalLineRoundTripAndAnchors();
  _testWideGraphemeAndOneColumnAnchorStability();
  _testReflowRepaginationCapAndEvictedAnchor();
  _testSoftLinePrefixEvictionInvalidatesAnchor();
  _testCursorPaddingSurvivesHistoryReflow();
  _testLogicalLineEpochPreventsResetAliasing();
  _testAlternateOwnershipAndInvalidResizeAtomicity();
  _testAnchorValidation();
}

void _testCursorPaddingSurvivesHistoryReflow() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 8,
    columns: 13,
    scrollback: TerminalScrollback(maxLines: 8, maxBytes: 32768, pageRows: 4),
  );
  final TerminalScreen screen = screens.primary;
  screen.setCursorPosition(1, 4);
  for (final int scalar in 'jq(Dd'.runes) {
    screen.printScalar(scalar);
  }

  screens.resize(rows: 3, columns: 4);
  _expect(
    screens.scrollback.length == 3 &&
        screens.scrollback.logicalCellOffsetAt(1) == 0 &&
        screens.scrollback.logicalCellOffsetAt(2) == 4,
    'cursor-significant canonical padding retains its logical extent',
  );
  screens.scrollback.validateCellTopology();
  screens.primary.validateCellTopology();

  screens.resize(rows: 3, columns: 21);
  _expect(
    screens.primary.contentAt(0, 4) == 0x6a &&
        screens.primary.contentAt(0, 8) == 0x64,
    'wider reflow restores content after retained cursor padding: '
    '${_screenText(screens.primary).codeUnits}',
  );
  screens.scrollback.validateCellTopology();
  screens.primary.validateCellTopology();
}

void _testCrossPageLogicalLineRoundTripAndAnchors() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 1),
  );
  for (final int scalar in 'ABCDEFGHIJKLMNOPQR'.runes) {
    screens.primary.printScalar(scalar);
  }
  final int logicalLineId = screens.scrollback.logicalLineIdAt(0);
  _expect(
    screens.scrollback.length == 2 &&
        screens.scrollback.pageCount == 2 &&
        screens.scrollback.logicalCellOffsetAt(0) == 0 &&
        screens.scrollback.logicalCellOffsetAt(1) == 4,
    'captured soft wraps retain logical offsets across page boundaries',
  );
  screens.viewport.scrollToTop();
  final TerminalLogicalAnchor start = screens.viewport.anchorAt(0, 0);
  final TerminalLogicalAnchor letterH = screens.viewport.anchorAt(1, 3);
  _expect(
    start.logicalLineId == logicalLineId &&
        start.logicalLineEpoch == screens.scrollback.logicalLineEpochAt(0) &&
        start.cellOffset == 0 &&
        letterH.logicalLineId == logicalLineId &&
        letterH.cellOffset == 7,
    'anchors use logical-cell ordinals across history/screen boundary',
  );

  screens.resize(rows: 2, columns: 3);
  _expect(
    screens.scrollback.length == 5 &&
        screens.scrollback.pageCount == 5 &&
        screens.scrollback.columnsAt(0) == 3 &&
        screens.scrollback.columnsAt(4) == 3 &&
        screens.scrollback.logicalCellOffsetAt(0) == 0 &&
        screens.scrollback.logicalCellOffsetAt(1) == 3 &&
        screens.scrollback.logicalCellOffsetAt(2) == 6 &&
        screens.scrollback.logicalCellOffsetAt(3) == 9 &&
        screens.scrollback.logicalCellOffsetAt(4) == 12 &&
        _historyRow(screens.scrollback, 0) == 'ABC' &&
        _historyRow(screens.scrollback, 1) == 'DEF' &&
        _historyRow(screens.scrollback, 2) == 'GHI' &&
        _historyRow(screens.scrollback, 3) == 'JKL' &&
        _historyRow(screens.scrollback, 4) == 'MNO' &&
        _screenRow(screens.primary, 0) == 'PQR',
    'narrower/shorter resize reflows one cross-page logical line',
  );
  _expect(
    screens.viewport.offset == 5 &&
        screens.viewport.positionOf(start) ==
            const TerminalViewportPosition(row: 0, column: 0) &&
        screens.viewport.positionOf(letterH) == null,
    'narrower/shorter resize preserves viewport top and logical anchors: '
    '${screens.viewport.offset}, ${screens.viewport.positionOf(start)}, '
    '${screens.viewport.positionOf(letterH)}',
  );
  screens.viewport.scrollByRows(-2);
  _expect(
    screens.viewport.positionOf(letterH) ==
        const TerminalViewportPosition(row: 0, column: 1),
    'a stable anchor resolves after its reflowed row enters the viewport',
  );
  screens.viewport.scrollToTop();
  _expect(
    screens.primary.cursorRow == 1 && screens.primary.cursorColumn == 0,
    'narrower/shorter history-aware resize maps active cursor',
  );
  screens.scrollback.validateCellTopology();
  screens.primary.validateCellTopology();

  screens.resize(rows: 4, columns: 6);
  _expect(
    screens.scrollback.isEmpty &&
        screens.viewport.offset == 0 &&
        _screenRow(screens.primary, 0) == 'ABCDEF' &&
        _screenRow(screens.primary, 1) == 'GHIJKL' &&
        _screenRow(screens.primary, 2) == 'MNOPQR',
    'wider/taller resize pulls retained history back into the visible grid',
  );
  _expect(
    screens.viewport.positionOf(start) ==
            const TerminalViewportPosition(row: 0, column: 0) &&
        screens.viewport.positionOf(letterH) ==
            const TerminalViewportPosition(row: 1, column: 1),
    'anchors survive history-to-screen movement on wider round trip',
  );
  _expect(
    _combinedText(screens) == 'ABCDEFGHIJKLMNOPQR',
    'round trip preserves complete logical scalar content',
  );
}

void _testWideGraphemeAndOneColumnAnchorStability() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 5,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 1),
  );
  final int accent = screens.graphemeTable.intern(const <int>[0x65, 0x0301]);
  final int emoji = screens.graphemeTable.intern(const <int>[
    0x1f469,
    0x200d,
    0x1f4bb,
  ]);
  final TerminalScreen screen = screens.primary;
  screen.setNarrowCell(0, 0, 0x41);
  screen.setWideCell(0, 1, 0x754c, foreground: 1, background: 2);
  screen.setGraphemeCell(0, 3, accent, style: 3, hyperlink: 4);
  screen.setNarrowCell(0, 4, 0x42);
  screen.setRowFlags(0, TerminalRowFlags.softWrapped | TerminalRowFlags.prompt);
  screen.setLogicalLineId(0, 77);
  screen.setGraphemeCell(1, 0, emoji, foreground: 5, background: 6);
  screen.setNarrowCell(1, 2, 0x5a);
  screen.setRowFlags(1, TerminalRowFlags.hardBreak | TerminalRowFlags.output);
  screen.setLogicalLineId(1, 77);
  screen.scrollUp(1);
  screens.viewport.scrollToTop();

  final TerminalLogicalAnchor wide = screens.viewport.anchorAt(0, 2);
  final TerminalLogicalAnchor emojiAnchor = screens.viewport.anchorAt(1, 1);
  _expect(
    wide.cellOffset == 1 && emojiAnchor.cellOffset == 4,
    'wide continuations normalize to stable lead-cell ordinals',
  );

  screens.resize(rows: 3, columns: 3);
  final TerminalViewportPosition? mappedWide = screens.viewport.positionOf(
    wide,
  );
  final TerminalViewportPosition? mappedEmoji = screens.viewport.positionOf(
    emojiAnchor,
  );
  _expect(
    screens.scrollback.length == 1 &&
        screens.viewport.offset == 1 &&
        mappedWide == const TerminalViewportPosition(row: 0, column: 1) &&
        mappedEmoji == const TerminalViewportPosition(row: 2, column: 0),
    'wide and grapheme anchors map through representable reflow: '
    '$mappedWide / $mappedEmoji',
  );
  _expect(
    screens.viewport.contentAt(0, 1) == 0x754c &&
        screens.viewport.foregroundAt(0, 2) == 1 &&
        screens.viewport.backgroundAt(0, 2) == 2 &&
        screens.viewport.contentAt(1, 0) == accent &&
        screens.viewport.styleAt(1, 0) == 3 &&
        screens.viewport.hyperlinkAt(1, 0) == 4 &&
        screens.viewport.contentAt(2, 0) == emoji &&
        screens.viewport.foregroundAt(2, 1) == 5 &&
        screens.viewport.backgroundAt(2, 1) == 6,
    'reflow preserves wide/grapheme content and presentation resources',
  );
  screens.primary.validateCellTopology();

  screens.resize(rows: 8, columns: 1);
  _expect(
    screens.viewport.positionOf(wide) ==
            const TerminalViewportPosition(row: 1, column: 0) &&
        screens.viewport.positionOf(emojiAnchor) ==
            const TerminalViewportPosition(row: 4, column: 0),
    'logical-cell ordinals survive one-column wide replacement',
  );
  _expect(
    screens.primary.contentAt(1, 0) == 0xfffd &&
        screens.primary.contentAt(4, 0) == 0xfffd,
    'one-column reflow contains both unrepresentable wide cells',
  );
  screens.primary.validateCellTopology();
}

void _testReflowRepaginationCapAndEvictedAnchor() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 4, maxBytes: 10000, pageRows: 2),
  );
  int logicalLineId = 100;
  for (final String text in const <String>['AAAA', 'BBBB', 'CCCC']) {
    _setHardRows(screens.primary, text, logicalLineId);
    logicalLineId += 2;
    screens.primary.scrollUp(2);
  }
  _setHardRows(screens.primary, 'DDDD', logicalLineId);
  screens.viewport.scrollToTop();
  final TerminalLogicalAnchor evicted = screens.viewport.anchorAt(0, 0);

  screens.resize(rows: 2, columns: 2);
  _expect(
    screens.scrollback.length == 4 &&
        screens.scrollback.pageCount == 2 &&
        screens.scrollback.allocatedBytes <= screens.scrollback.maxBytes,
    'reflow repaginates under the original line, page, and byte caps',
  );
  for (int row = 0; row < screens.scrollback.length; row++) {
    _expect(
      screens.scrollback.columnsAt(row) == 2,
      'repaginated history row $row uses target width',
    );
  }
  _expect(
    screens.viewport.positionOf(evicted) == null,
    'anchor whose logical content was evicted becomes unresolved',
  );
  screens.scrollback.validateCellTopology();
  screens.primary.validateCellTopology();
}

void _testSoftLinePrefixEvictionInvalidatesAnchor() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 2,
    scrollback: TerminalScrollback(maxLines: 2, maxBytes: 10000, pageRows: 1),
  );
  for (final int scalar in 'ABCDEF'.runes) {
    screens.primary.printScalar(scalar);
  }
  screens.viewport.scrollToTop();
  final TerminalLogicalAnchor prefix = screens.viewport.anchorAt(0, 0);
  screens.viewport.scrollToBottom();

  for (final int scalar in 'GHI'.runes) {
    screens.primary.printScalar(scalar);
  }
  screens.viewport.scrollToTop();
  _expect(
    screens.scrollback.length == 2 &&
        screens.scrollback.logicalCellOffsetAt(0) == 2 &&
        screens.scrollback.logicalCellOffsetAt(1) == 4,
    'retained suffix preserves non-zero logical offsets after page eviction',
  );
  _expect(
    screens.viewport.positionOf(prefix) == null,
    'anchor in an evicted prefix cannot alias the retained logical suffix',
  );
  screens.scrollback.validateCellTopology();
}

void _testLogicalLineEpochPreventsResetAliasing() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 2);
  final TerminalLogicalAnchor beforeReset = screens.viewport.anchorAt(0, 0);
  screens.primary.resetScreen();
  final TerminalLogicalAnchor afterReset = screens.viewport.anchorAt(0, 0);

  _expect(
    beforeReset.logicalLineId == afterReset.logicalLineId &&
        beforeReset.logicalLineEpoch != afterReset.logicalLineEpoch &&
        screens.viewport.positionOf(beforeReset) == null &&
        screens.viewport.positionOf(afterReset) ==
            const TerminalViewportPosition(row: 0, column: 0),
    'logical-line epochs prevent a reset from aliasing reused row IDs',
  );
}

void _testAlternateOwnershipAndInvalidResizeAtomicity() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 2),
  );
  for (final int scalar in 'ABCDEFGHIJ'.runes) {
    screens.primary.printScalar(scalar);
  }
  screens.viewport.scrollToTop();
  final TerminalLogicalAnchor primaryTop = screens.viewport.anchorAt(0, 0);
  screens.setAlternateMode47(true);
  for (final int scalar in '123456'.runes) {
    screens.alternate.printScalar(scalar);
  }
  screens.resize(rows: 3, columns: 3);
  _expect(
    screens.usingAlternate &&
        screens.viewport.offset == 0 &&
        screens.alternate.columns == 3 &&
        _screenText(screens.alternate).startsWith('123456'),
    'history-aware primary resize keeps alternate ownership and content',
  );
  screens.setAlternateMode47(false);
  _expect(
    screens.viewport.positionOf(primaryTop) ==
        const TerminalViewportPosition(row: 0, column: 0),
    'primary viewport anchor survives resize while alternate is active',
  );

  final TerminalScreen primary = screens.primary;
  final TerminalScreen alternate = screens.alternate;
  final String history = _historyState(screens.scrollback);
  final int offset = screens.viewport.offset;
  final int transition = screens.transitionGeneration;
  _expectThrowsRangeError(
    () => screens.resize(rows: 0, columns: 3),
    'invalid resize is rejected before transaction construction',
  );
  _expect(
    identical(screens.primary, primary) &&
        identical(screens.alternate, alternate) &&
        _historyState(screens.scrollback) == history &&
        screens.viewport.offset == offset &&
        screens.transitionGeneration == transition,
    'invalid resize leaves screens, history, viewport, and transition atomic',
  );
  screens.resize(rows: 3, columns: 3);
  _expect(
    identical(screens.primary, primary) &&
        identical(screens.alternate, alternate) &&
        _historyState(screens.scrollback) == history,
    'same-size history-aware resize is a no-op',
  );
}

void _testAnchorValidation() {
  _expectThrowsRangeError(
    () => TerminalLogicalAnchor(
      screenKind: TerminalScreenKind.primary,
      logicalLineId: 0,
      logicalLineEpoch: 1,
      cellOffset: 0,
    ),
    'zero logical-line ID is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalLogicalAnchor(
      screenKind: TerminalScreenKind.primary,
      logicalLineId: 1,
      logicalLineEpoch: 1,
      cellOffset: -1,
    ),
    'negative logical-cell offset is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalLogicalAnchor(
      screenKind: TerminalScreenKind.primary,
      logicalLineId: 1,
      logicalLineEpoch: 1,
      cellOffset: TerminalLogicalAnchor.maxCellOffset + 1,
    ),
    'oversized logical-cell offset is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalLogicalAnchor(
      screenKind: TerminalScreenKind.primary,
      logicalLineId: 1,
      logicalLineEpoch: 0,
      cellOffset: 0,
    ),
    'zero logical-line epoch is rejected',
  );
}

void _setHardRows(TerminalScreen screen, String text, int firstLineId) {
  for (int row = 0; row < screen.rows; row++) {
    for (int column = 0; column < screen.columns; column++) {
      screen.setNarrowCell(row, column, text.codeUnitAt(column));
    }
    screen.setRowFlags(row, TerminalRowFlags.hardBreak);
    screen.setLogicalLineId(row, firstLineId + row);
  }
}

String _combinedText(TerminalScreenSet screens) =>
    '${List<String>.generate(screens.scrollback.length, (int row) => _historyRow(screens.scrollback, row)).join()}'
            '${_screenText(screens.primary)}'
        .replaceAll('\u0000', '');

String _screenText(TerminalScreen screen) => List<String>.generate(
  screen.rows,
  (int row) => _screenRow(screen, row),
).join();

String _screenRow(TerminalScreen screen, int row) {
  final List<int> scalars = <int>[];
  for (int column = 0; column < screen.columns; column++) {
    final int flags = screen.widthFlagsAt(row, column);
    if ((flags & TerminalCellFlags.widthMask) ==
        TerminalCellFlags.continuation) {
      continue;
    }
    final int content = screen.contentAt(row, column);
    if (content == 0) {
      scalars.add(0);
    } else if (flags & TerminalCellFlags.grapheme != 0) {
      scalars.addAll(screen.graphemeTable.scalarsAt(content));
    } else {
      scalars.add(content);
    }
  }
  return String.fromCharCodes(scalars);
}

String _historyRow(TerminalScrollback history, int row) {
  final List<int> scalars = <int>[];
  for (int column = 0; column < history.columnsAt(row); column++) {
    final int flags = history.widthFlagsAt(row, column);
    if ((flags & TerminalCellFlags.widthMask) ==
        TerminalCellFlags.continuation) {
      continue;
    }
    scalars.add(history.contentAt(row, column));
  }
  return String.fromCharCodes(scalars);
}

String _historyState(TerminalScrollback history) {
  final StringBuffer result = StringBuffer(
    '${history.length}/${history.pageCount}/${history.allocatedBytes}|',
  );
  for (int row = 0; row < history.length; row++) {
    result
      ..write(history.columnsAt(row))
      ..write('/')
      ..write(history.logicalLineIdAt(row))
      ..write('/')
      ..write(history.logicalLineEpochAt(row))
      ..write('/')
      ..write(history.logicalCellOffsetAt(row))
      ..write('/')
      ..write(history.rowFlagsAt(row))
      ..write(':')
      ..write(_historyRow(history, row))
      ..write(';');
  }
  return result.toString();
}

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
