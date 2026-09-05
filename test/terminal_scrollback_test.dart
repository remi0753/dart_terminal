import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalScrollbackTests();

void runTerminalScrollbackTests() {
  _testPageStorageFidelityAndLineEviction();
  _testByteCapAndUnrepresentableRows();
  _testRepeatedPageEvictionStaysBounded();
  _testMixedWidthsAndReplacementOwnership();
  _testCapturePolicyAndResetLifetime();
  _testParserCaptureAndAlternateIsolation();
  _testConfigurationAndAccessBounds();
}

void _testPageStorageFidelityAndLineEviction() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 5,
    maxBytes: 10000,
    pageRows: 2,
  );
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: history,
  );
  final TerminalScreen screen = screens.primary;
  screen.setNarrowCell(
    0,
    0,
    0x41,
    foreground: 1,
    background: 0x80112233,
    style: 2,
    hyperlink: 3,
    isProtected: true,
  );
  screen.setWideCell(
    0,
    1,
    0x754c,
    foreground: 4,
    background: 5,
    style: 6,
    hyperlink: 7,
  );
  screen.setRowFlags(0, TerminalRowFlags.prompt | TerminalRowFlags.hardBreak);
  screen.setLogicalLineId(0, 41);
  final int generation = history.generation;
  screen.scrollUp(1);

  _expect(
    history.length == 1 &&
        history.pageCount == 1 &&
        history.columnsAt(0) == 4 &&
        history.generation == generation + 1,
    'first captured row creates one page and revision',
  );
  _expect(
    history.contentAt(0, 0) == 0x41 &&
        history.foregroundAt(0, 0) == 1 &&
        history.backgroundAt(0, 0) == 0x80112233 &&
        history.styleAt(0, 0) == 2 &&
        history.hyperlinkAt(0, 0) == 3 &&
        history.widthFlagsAt(0, 0) ==
            TerminalCellFlags.narrow | TerminalCellFlags.protected,
    'narrow cell fields are copied exactly',
  );
  _expect(
    history.contentAt(0, 1) == 0x754c &&
        history.widthFlagsAt(0, 1) == TerminalCellFlags.wide &&
        history.contentAt(0, 2) == 0 &&
        history.widthFlagsAt(0, 2) == TerminalCellFlags.continuation &&
        history.foregroundAt(0, 2) == 4 &&
        history.backgroundAt(0, 2) == 5 &&
        history.styleAt(0, 2) == 6 &&
        history.hyperlinkAt(0, 2) == 7,
    'wide pair fields are copied atomically',
  );
  _expect(
    history.rowFlagsAt(0) ==
            TerminalRowFlags.prompt | TerminalRowFlags.hardBreak &&
        history.logicalLineIdAt(0) == 41,
    'row metadata is copied exactly',
  );
  _expect(
    history.allocatedBytes == 2 * (4 * 17 + 5),
    'allocated bytes count full typed page capacity',
  );
  final int graphemeId = screens.graphemeTable.intern(const <int>[
    0x65,
    0x0301,
  ]);
  screen.setGraphemeCell(
    0,
    0,
    graphemeId,
    foreground: 8,
    background: 9,
    style: 10,
    hyperlink: 11,
    isProtected: true,
  );
  screen.setRowFlags(0, TerminalRowFlags.output);
  screen.setLogicalLineId(0, 42);
  screen.scrollUp(1);
  _expect(
    history.length == 2 &&
        history.contentAt(1, 0) == graphemeId &&
        history.widthFlagsAt(1, 0) ==
            TerminalCellFlags.narrow |
                TerminalCellFlags.grapheme |
                TerminalCellFlags.protected &&
        history.foregroundAt(1, 0) == 8 &&
        history.backgroundAt(1, 0) == 9 &&
        history.styleAt(1, 0) == 10 &&
        history.hyperlinkAt(1, 0) == 11 &&
        history.rowFlagsAt(1) == TerminalRowFlags.output &&
        history.logicalLineIdAt(1) == 42 &&
        screens.graphemeTable.scalarsAt(graphemeId).last == 0x0301,
    'grapheme cells and their resource IDs are copied exactly',
  );
  history.validateCellTopology();

  history.clear();
  for (int index = 0; index < 6; index++) {
    screen.setNarrowCell(0, 0, 0x61 + index);
    screen.setLogicalLineId(0, 100 + index);
    screen.scrollUp(1);
    history.validateCellTopology();
  }
  _expect(
    history.length == 4 && history.pageCount == 2,
    'line limit evicts one complete oldest page',
  );
  _expect(
    history.contentAt(0, 0) == 0x63 &&
        history.logicalLineIdAt(0) == 102 &&
        history.contentAt(3, 0) == 0x66 &&
        history.logicalLineIdAt(3) == 105,
    'page-granular line eviction retains an ordered newest suffix',
  );
}

void _testByteCapAndUnrepresentableRows() {
  const int threeColumnPageBytes = 2 * (3 * 17 + 5);
  final TerminalScrollback bounded = TerminalScrollback(
    maxLines: 10,
    maxBytes: threeColumnPageBytes * 2,
    pageRows: 2,
  );
  final TerminalScreen screen = TerminalScreenSet(
    rows: 2,
    columns: 3,
    scrollback: bounded,
  ).primary;
  for (int index = 0; index < 5; index++) {
    screen.setNarrowCell(0, 0, 0x41 + index);
    screen.scrollUp(1);
  }
  _expect(
    bounded.allocatedBytes == threeColumnPageBytes * 2 &&
        bounded.pageCount == 2 &&
        bounded.length == 3 &&
        bounded.contentAt(0, 0) == 0x43 &&
        bounded.contentAt(2, 0) == 0x45,
    'byte cap evicts a full page before linking the next page',
  );
  bounded.validateCellTopology();

  final TerminalScrollback tiny = TerminalScrollback(
    maxLines: 4,
    maxBytes: 72,
    pageRows: 4,
  );
  final TerminalScreenSet changing = TerminalScreenSet(
    rows: 2,
    columns: 2,
    scrollback: tiny,
  );
  changing.primary.setNarrowCell(0, 0, 0x58);
  changing.primary.scrollUp(1);
  _expect(
    tiny.length == 1 && tiny.pageCount == 1 && tiny.allocatedBytes == 39,
    'byte cap reduces page capacity for a representable row',
  );
  final int generation = tiny.generation;
  changing.resize(rows: 2, columns: 4);
  changing.primary.scrollUp(1);
  _expect(
    tiny.isEmpty &&
        tiny.pageCount == 0 &&
        tiny.allocatedBytes == 0 &&
        tiny.generation == generation + 1,
    'an individually unrepresentable newest row clears older discontinuous history',
  );
  tiny.validateCellTopology();
}

void _testRepeatedPageEvictionStaysBounded() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 16,
    maxBytes: 10000,
    pageRows: 4,
  );
  final TerminalScreen screen = TerminalScreenSet(
    rows: 1,
    columns: 2,
    scrollback: history,
  ).primary;
  for (int index = 1; index <= 4096; index++) {
    screen.setNarrowCell(0, 0, 0x41 + index % 26);
    screen.setLogicalLineId(0, index);
    screen.scrollUp(1);
    if (index % 257 == 0) {
      history.validateCellTopology();
    }
  }
  _expect(
    history.length == 16 &&
        history.pageCount == 4 &&
        history.logicalLineIdAt(0) == 4081 &&
        history.logicalLineIdAt(15) == 4096 &&
        history.allocatedBytes == 4 * 4 * (2 * 17 + 5),
    'repeated page eviction remains bounded and ordered',
  );
  history.validateCellTopology();
}

void _testMixedWidthsAndReplacementOwnership() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 20,
    maxBytes: 10000,
    pageRows: 4,
  );
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 3,
    scrollback: history,
  );
  screens.primary.setNarrowCell(0, 0, 0x41);
  screens.primary.scrollUp(1);
  final TerminalScreen oldPrimary = screens.primary;

  screens.resize(rows: 2, columns: 5);
  oldPrimary.setNarrowCell(0, 0, 0x58);
  oldPrimary.scrollUp(1);
  _expect(
    history.length == 1,
    'superseded primary screen cannot append through the shared attachment',
  );
  screens.primary.setNarrowCell(0, 0, 0x42);
  screens.primary.scrollUp(1);
  _expect(
    history.length == 2 &&
        history.pageCount == 2 &&
        history.columnsAt(0) == 3 &&
        history.columnsAt(1) == 5 &&
        history.contentAt(0, 0) == 0x41 &&
        history.contentAt(1, 0) == 0x42,
    'column changes close the tail page and preserve source widths',
  );
  _expect(
    identical(screens.scrollback, history),
    'screen-set resize preserves scrollback ownership identity',
  );
  _expectThrowsStateError(
    () => TerminalScreenSet(rows: 1, columns: 1, scrollback: history),
    'one scrollback cannot be attached to two screen sets',
  );
  final int lengthBeforeReuseFailure = history.length;
  screens.primary.scrollUp(1);
  _expect(
    history.length == lengthBeforeReuseFailure + 1,
    'failed attachment reuse leaves the original owner usable',
  );
  history.validateCellTopology();
}

void _testCapturePolicyAndResetLifetime() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 20,
    maxBytes: 10000,
    pageRows: 4,
  );
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: history,
  );

  screens.setAlternateMode47(true);
  screens.alternate.setNarrowCell(0, 0, 0x41);
  screens.alternate.scrollUp(1);
  screens.setAlternateMode47(false);
  _expect(history.isEmpty, 'alternate full-screen scroll is isolated');

  screens.primary.setVerticalMargins(1, 2);
  screens.primary.scrollUp(1);
  _expect(history.isEmpty, 'partial vertical scroll region is not captured');

  screens.primary.resetTerminalState();
  screens.primary.setHorizontalMargins(1, 3);
  screens.primary.setMode(TerminalScreenMode.horizontalMargins, true);
  screens.primary.scrollUp(1);
  _expect(history.isEmpty, 'partial horizontal scroll region is not captured');

  screens.primary.resetTerminalState();
  screens.primary.setCursorPosition(0, 0);
  screens.primary.deleteLines(1);
  _expect(history.isEmpty, 'delete-line movement is not output history');

  screens.primary.setNarrowCell(0, 0, 0x50);
  screens.primary.setNarrowCell(1, 0, 0x51);
  screens.primary.setNarrowCell(2, 0, 0x52);
  screens.primary.scrollUp(3);
  _expect(
    history.length == 3 &&
        history.contentAt(0, 0) == 0x50 &&
        history.contentAt(1, 0) == 0x51 &&
        history.contentAt(2, 0) == 0x52,
    'multi-row primary full-screen scroll captures rows in order',
  );
  screens.primary.scrollDown(1);
  _expect(history.length == 3, 'reverse scrolling does not append history');
  screens.reset();
  _expect(history.length == 3, 'screen reset preserves retained scrollback');
  history.validateCellTopology();
}

void _testParserCaptureAndAlternateIsolation() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 20,
    maxBytes: 10000,
    pageRows: 4,
  );
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: history,
  );
  final VtParser parser = VtParser(
    sink: TerminalScreenParserSink.forScreenSet(screens),
  );
  parser.parse(Uint8List.fromList(utf8.encode('A\r\nB\r\nC')));
  _expect(
    history.length == 1 &&
        history.contentAt(0, 0) == 0x41 &&
        history.rowFlagsAt(0) & TerminalRowFlags.hardBreak != 0,
    'parser line feed captures the outgoing primary row',
  );

  parser.parse(Uint8List.fromList(utf8.encode('\x1b[?1049hX\r\nY\r\nZ')));
  parser.finish();
  _expect(
    screens.usingAlternate && history.length == 1,
    'parser-driven alternate scrolling does not enter primary history',
  );
  history.validateCellTopology();
}

void _testConfigurationAndAccessBounds() {
  _expectThrowsRangeError(
    () => TerminalScrollback(maxLines: 0),
    'zero line cap is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalScrollback(maxLines: TerminalScrollback.maximumLineLimit + 1),
    'oversized line cap is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalScrollback(maxBytes: 0),
    'zero byte cap is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalScrollback(pageRows: 0),
    'zero page capacity is rejected',
  );
  _expectThrowsRangeError(
    () => TerminalScrollback(pageRows: TerminalScrollback.maximumPageRows + 1),
    'page capacity above the format baseline is rejected',
  );

  final TerminalScrollback empty = TerminalScrollback(maxLines: 1);
  final int generation = empty.generation;
  empty.clear();
  _expect(
    empty.generation == generation,
    'clearing empty history is revision-neutral',
  );
  _expectThrowsRangeError(
    () => empty.columnsAt(0),
    'empty row access is rejected',
  );
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

void _expectThrowsStateError(void Function() operation, String description) {
  try {
    operation();
  } on StateError {
    return;
  }
  throw StateError(description);
}
