import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSelectionSearchTests();

void runTerminalSelectionSearchTests() {
  _testEndExclusiveReversedAndReflowedCellSelection();
  _testWideGraphemeExtractionAndScalarCap();
  _testWordSelectionPolicyAndBoundaryCap();
  _testLogicalLineSelectionSemanticFlagsAndEviction();
  _testUnretainedOneRowPrefixDoesNotAlias();
  _testForwardBackwardSearchAndLimits();
  _testGraphemeAlignedSearchAndAlternateIsolation();
  _testAdversarialOverlapSearch();
  _testPagedHistorySearchTraversal();
  _testSelectionAndSearchValidation();
}

void _testEndExclusiveReversedAndReflowedCellSelection() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 4);
  for (final int scalar in 'abcdef'.runes) {
    screens.primary.printScalar(scalar);
  }
  screens.primary.nextLine();
  for (final int scalar in 'gh'.runes) {
    screens.primary.printScalar(scalar);
  }

  final TerminalLogicalAnchor start = screens.viewport.anchorAt(0, 1);
  final TerminalLogicalAnchor end = screens.viewport.anchorAfter(1, 0);
  final TerminalSelectionRange reversed = _requiredRange(
    screens.viewport,
    end,
    start,
  );
  _expect(
    reversed.isReversed &&
        !reversed.isCollapsed &&
        reversed.start == start &&
        reversed.end == end &&
        _requiredText(screens.viewport, reversed).text == 'bcde',
    'reversed endpoints normalize to an end-exclusive soft-wrap selection',
  );

  final TerminalSelectionRange hardBreak = _requiredRange(
    screens.viewport,
    screens.viewport.anchorAt(1, 1),
    screens.viewport.anchorAfter(2, 1),
  );
  _expect(
    _requiredText(screens.viewport, hardBreak).text == 'f\ngh',
    'extraction omits soft-wrap newlines and retains hard row boundaries',
  );
  final TerminalSelectionRange collapsed = _requiredRange(
    screens.viewport,
    start,
    start,
  );
  _expect(
    collapsed.isCollapsed &&
        _requiredText(screens.viewport, collapsed).text.isEmpty,
    'equal end-exclusive cell boundaries produce an empty selection',
  );

  screens.resize(rows: 5, columns: 3);
  _expect(
    _requiredText(screens.viewport, reversed).text == 'bcde',
    'stable selection boundaries survive narrower/taller reflow',
  );
}

void _testWideGraphemeExtractionAndScalarCap() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  final int grapheme = screens.graphemeTable.intern(const <int>[0x65, 0x0301]);
  final TerminalScreen screen = screens.primary;
  screen.setWideCell(0, 0, 0x754c);
  screen.setGraphemeCell(0, 2, grapheme);
  screen.setNarrowCell(0, 3, 0x58);
  screen.setNarrowCell(0, 4, 0, background: 1);
  screen.setRowFlags(0, TerminalRowFlags.hardBreak);

  final TerminalLogicalAnchor wideLead = screens.viewport.anchorAt(0, 0);
  final TerminalLogicalAnchor wideContinuation = screens.viewport.anchorAt(
    0,
    1,
  );
  final TerminalSelectionRange range = _requiredRange(
    screens.viewport,
    wideContinuation,
    screens.viewport.anchorAfter(0, 4),
  );
  final TerminalSelectionText extracted = _requiredText(
    screens.viewport,
    range,
  );
  _expect(
    wideLead == wideContinuation &&
        extracted.text == '界e\u0301X ' &&
        extracted.scalarCount == 5 &&
        !extracted.isTruncated,
    'wide continuation normalizes and grapheme/blank extraction is exact',
  );

  final TerminalSelectionText truncated = _requiredText(
    screens.viewport,
    range,
    maxScalars: 2,
  );
  _expect(
    truncated.text == '界' &&
        truncated.scalarCount == 1 &&
        truncated.isTruncated,
    'the scalar cap never splits an interned grapheme',
  );
}

void _testWordSelectionPolicyAndBoundaryCap() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 16);
  for (final int scalar in 'foo_bar  ++界字'.runes) {
    screens.primary.printScalar(scalar);
  }

  _expect(
    _selectedTextAt(screens, 2, TerminalSelectionUnit.word) == 'foo_bar',
    'ASCII alphanumeric and underscore cells form one word',
  );
  _expect(
    _selectedTextAt(screens, 7, TerminalSelectionUnit.word) == '  ',
    'Unicode whitespace cells form a whitespace run',
  );
  _expect(
    _selectedTextAt(screens, 9, TerminalSelectionUnit.word) == '+',
    'ASCII separators remain single-cell word units',
  );
  _expect(
    _selectedTextAt(screens, 14, TerminalSelectionUnit.word) == '界字',
    'non-ASCII wide cells form a word without splitting continuations',
  );

  final TerminalLogicalAnchor focus = screens.viewport.anchorAt(0, 3);
  final TerminalSelectionRange limited = _requiredRange(
    screens.viewport,
    focus,
    focus,
    unit: TerminalSelectionUnit.word,
    maxWordScanCells: 1,
  );
  _expect(
    limited.isBoundaryLimited &&
        _requiredText(screens.viewport, limited).text == 'o_b',
    'adversarial word expansion reports its explicit scan boundary',
  );

  final TerminalScreenSet wrapped = TerminalScreenSet(rows: 3, columns: 4);
  for (final int scalar in 'abcdef'.runes) {
    wrapped.primary.printScalar(scalar);
  }
  _expect(
    _selectedTextAt(wrapped, 0, TerminalSelectionUnit.word, row: 1) == 'abcdef',
    'word expansion crosses a valid soft-wrapped logical line',
  );
}

void _testLogicalLineSelectionSemanticFlagsAndEviction() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 4, maxBytes: 10000, pageRows: 1),
  );
  _setText(screens.primary, 0, 'ABCD');
  _setText(screens.primary, 1, 'EFG');
  screens.primary.setRowFlags(
    0,
    TerminalRowFlags.softWrapped | TerminalRowFlags.prompt,
  );
  screens.primary.setRowFlags(
    1,
    TerminalRowFlags.hardBreak | TerminalRowFlags.command,
  );
  screens.primary.setLogicalLineId(0, 77);
  screens.primary.setLogicalLineId(1, 77);
  screens.primary.scrollUp(1);
  screens.viewport.scrollToTop();

  final TerminalLogicalAnchor focus = screens.viewport.anchorAt(0, 1);
  final TerminalSelectionRange line = _requiredRange(
    screens.viewport,
    focus,
    focus,
    unit: TerminalSelectionUnit.logicalLine,
  );
  _expect(
    _requiredText(screens.viewport, line).text == 'ABCDEFG' &&
        line.semanticRowFlags ==
            TerminalRowFlags.prompt | TerminalRowFlags.command,
    'logical-line selection spans history/screen and aggregates semantic flags',
  );
  final TerminalSearchResult historyMatch = _requiredSearch(
    screens.viewport,
    'CDE',
  );
  _expect(
    historyMatch.matches.length == 1 &&
        _matchText(screens.viewport, historyMatch.matches.single) == 'CDE',
    'search streams across the retained history/screen soft-wrap boundary',
  );

  screens.scrollback.clear();
  _expect(
    screens.primary.logicalCellOffsetAt(0) == 4 &&
        screens.viewport.extractSelection(line) == null &&
        screens.viewport.search('ABC', start: line.start) == null,
    'visible suffix keeps its base and rejects an evicted prefix anchor',
  );
}

void _testUnretainedOneRowPrefixDoesNotAlias() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 1,
    columns: 2,
    scrollback: TerminalScrollback(maxLines: 2, maxBytes: 1, pageRows: 1),
  );
  for (final int scalar in 'AB'.runes) {
    screens.primary.printScalar(scalar);
  }
  final TerminalLogicalAnchor prefix = screens.viewport.anchorAt(0, 0);
  screens.primary.printScalar(0x43);

  _expect(
    screens.scrollback.isEmpty &&
        screens.primary.logicalCellOffsetAt(0) == 2 &&
        screens.viewport.positionOf(prefix) == null &&
        screens.viewport.anchorAt(0, 0).cellOffset == 2,
    'one-row wrap preserves a logical base when its prefix cannot be retained',
  );
}

void _testForwardBackwardSearchAndLimits() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 4, columns: 5);
  _setText(screens.primary, 0, 'alpha');
  _setText(screens.primary, 1, ' beta');
  _setText(screens.primary, 2, 'alpha');
  screens.primary.setRowFlags(
    0,
    TerminalRowFlags.softWrapped | TerminalRowFlags.prompt,
  );
  screens.primary.setRowFlags(
    1,
    TerminalRowFlags.hardBreak | TerminalRowFlags.prompt,
  );
  screens.primary.setRowFlags(
    2,
    TerminalRowFlags.hardBreak | TerminalRowFlags.output,
  );
  screens.primary.setLogicalLineId(0, 100);
  screens.primary.setLogicalLineId(1, 100);
  screens.primary.setLogicalLineId(2, 200);

  final TerminalSearchResult wrapped = _requiredSearch(
    screens.viewport,
    'ha be',
  );
  _expect(
    wrapped.matches.length == 1 &&
        _matchText(screens.viewport, wrapped.matches.single) == 'ha be' &&
        wrapped.matches.single.semanticRowFlags == TerminalRowFlags.prompt,
    'forward search spans a valid soft wrap and retains semantic flags',
  );
  _expect(
    _requiredSearch(screens.viewport, 'taalp').matches.isEmpty,
    'search never crosses a hard logical-line boundary',
  );

  final TerminalSearchResult forward = _requiredSearch(
    screens.viewport,
    'alpha',
  );
  final TerminalSearchResult backward = _requiredSearch(
    screens.viewport,
    'alpha',
    direction: TerminalSearchDirection.backward,
  );
  _expect(
    forward.matches.length == 2 &&
        backward.matches.length == 2 &&
        forward.matches.first.semanticRowFlags == TerminalRowFlags.prompt &&
        forward.matches.last.semanticRowFlags == TerminalRowFlags.output &&
        backward.matches.first.start == forward.matches.last.start &&
        backward.matches.last.start == forward.matches.first.start,
    'forward/backward results follow deterministic document order',
  );

  final TerminalSearchResult resumed = _requiredSearch(
    screens.viewport,
    'alpha',
    start: forward.matches.first.end,
  );
  _expect(
    resumed.matches.length == 1 &&
        resumed.matches.single.start == forward.matches.last.start,
    'an end-exclusive match anchor resumes forward search after that match',
  );
  final TerminalSearchResult resumedBackward = _requiredSearch(
    screens.viewport,
    'alpha',
    direction: TerminalSearchDirection.backward,
    start: backward.matches.first.start,
  );
  _expect(
    resumedBackward.matches.length == 1 &&
        resumedBackward.matches.single.start == forward.matches.first.start,
    'a start anchor resumes backward search before the later match',
  );
  final TerminalSearchResult matchLimited = _requiredSearch(
    screens.viewport,
    'alpha',
    maxMatches: 1,
  );
  _expect(
    matchLimited.matches.length == 1 &&
        matchLimited.matchLimitReached &&
        matchLimited.isTruncated,
    'the retained result count stops at its explicit hard limit',
  );
  final TerminalSearchResult scanLimited = _requiredSearch(
    screens.viewport,
    'alpha',
    maxScalars: 3,
  );
  _expect(
    scanLimited.matches.isEmpty &&
        scanLimited.scannedScalars == 3 &&
        scanLimited.scanLimitReached,
    'the scalar work limit stops an incomplete adversarial scan',
  );
}

void _testGraphemeAlignedSearchAndAlternateIsolation() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  final int grapheme = screens.graphemeTable.intern(const <int>[0x65, 0x0301]);
  screens.primary.setWideCell(0, 0, 0x754c);
  screens.primary.setGraphemeCell(0, 2, grapheme);
  screens.primary.setNarrowCell(0, 3, 0x58);

  final TerminalSearchResult exact = _requiredSearch(
    screens.viewport,
    'e\u0301X',
  );
  _expect(
    exact.matches.length == 1 &&
        _matchText(screens.viewport, exact.matches.single) == 'e\u0301X' &&
        _requiredSearch(screens.viewport, 'e').matches.isEmpty &&
        _requiredSearch(screens.viewport, '界').matches.length == 1,
    'search matches complete grapheme and wide cells but not partial clusters',
  );

  screens.setAlternateMode47(true);
  _setText(screens.alternate, 0, 'alt');
  final TerminalSelectionRange alternateRange = _requiredRange(
    screens.viewport,
    screens.viewport.anchorAt(0, 0),
    screens.viewport.anchorAfter(0, 2),
  );
  _expect(
    _requiredText(screens.viewport, alternateRange).text == 'alt' &&
        screens.viewport.selectionRange(
              exact.matches.single.start,
              exact.matches.single.end,
            ) ==
            null &&
        _requiredSearch(screens.viewport, 'alt').matches.length == 1 &&
        _requiredSearch(screens.viewport, '界').matches.isEmpty &&
        screens.viewport.search('alt', start: exact.matches.single.start) ==
            null,
    'alternate search is isolated and rejects a primary start anchor',
  );
}

void _testAdversarialOverlapSearch() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 512);
  final String prefix = List<String>.filled(511, 'a').join();
  _setText(screens.primary, 0, '${prefix}b');
  final String query = '${List<String>.filled(255, 'a').join()}b';
  final TerminalSearchResult kmp = _requiredSearch(screens.viewport, query);
  _expect(
    kmp.matches.length == 1 &&
        _matchText(screens.viewport, kmp.matches.single) == query &&
        kmp.scannedScalars == 512,
    'streaming prefix fallback handles the maximum repeated-prefix query',
  );
  final TerminalSearchResult backward = _requiredSearch(
    screens.viewport,
    query,
    direction: TerminalSearchDirection.backward,
  );
  _expect(
    backward.matches.length == 1 &&
        backward.matches.single.start == kmp.matches.single.start &&
        backward.scannedScalars == 512,
    'backward prefix matching finds the same maximum-length query in reverse',
  );

  final TerminalSearchResult overlaps = _requiredSearch(
    screens.viewport,
    'aa',
    maxMatches: 3,
  );
  _expect(
    overlaps.matches.length == 3 && overlaps.matchLimitReached,
    'overlapping matches remain deterministic under the result cap',
  );
}

void _testPagedHistorySearchTraversal() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(
      maxLines: 600,
      maxBytes: 100000,
      pageRows: 1,
    ),
  );
  for (int row = 0; row < 512; row++) {
    _setText(screens.primary, 0, 'aaaa');
    screens.primary.setRowFlags(0, TerminalRowFlags.hardBreak);
    screens.primary.scrollUp(1);
  }
  final int generation = screens.scrollback.generation;
  final TerminalSearchResult forward = _requiredSearch(
    screens.viewport,
    'zzzz',
  );
  final TerminalSearchResult backward = _requiredSearch(
    screens.viewport,
    'zzzz',
    direction: TerminalSearchDirection.backward,
  );
  _expect(
    screens.scrollback.pageCount == 512 &&
        forward.matches.isEmpty &&
        backward.matches.isEmpty &&
        forward.scannedScalars >= 2048 &&
        backward.scannedScalars == forward.scannedScalars &&
        !forward.isTruncated &&
        !backward.isTruncated &&
        screens.scrollback.generation == generation,
    'forward/backward scans traverse hundreds of linked pages completely',
  );
  screens.scrollback.validateCellTopology();
}

void _testSelectionAndSearchValidation() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  final TerminalLogicalAnchor anchor = screens.viewport.anchorAt(0, 0);
  _expectThrowsRangeError(
    () => screens.viewport.selectionRange(
      anchor,
      anchor,
      unit: TerminalSelectionUnit.word,
      maxWordScanCells: 0,
    ),
    'zero word scan cap is rejected',
  );
  final TerminalSelectionRange range = _requiredRange(
    screens.viewport,
    anchor,
    screens.viewport.anchorAfter(0, 0),
  );
  final TerminalLogicalAnchor unavailable = TerminalLogicalAnchor(
    screenKind: anchor.screenKind,
    logicalLineId: anchor.logicalLineId,
    logicalLineEpoch: anchor.logicalLineEpoch,
    cellOffset: 99,
  );
  _expect(
    screens.viewport.positionOf(unavailable) == null &&
        screens.viewport.selectionRange(anchor, unavailable) == null &&
        screens.viewport.search('x', start: unavailable) == null,
    'an out-of-content stable boundary is unavailable instead of clamped',
  );
  _expectThrowsRangeError(
    () => screens.viewport.extractSelection(range, maxScalars: 0),
    'zero extraction scalar cap is rejected',
  );
  _expectThrowsArgumentError(
    () => screens.viewport.search(''),
    'empty search query is rejected',
  );
  _expectThrowsRangeError(
    () => screens.viewport.search(List<String>.filled(257, 'x').join()),
    'oversized search query is rejected before unbounded growth',
  );
  _expectThrowsRangeError(
    () => screens.viewport.search('x', maxScalars: 0),
    'zero search work cap is rejected',
  );
  _expectThrowsRangeError(
    () => screens.viewport.search('x', maxMatches: 0),
    'zero search result cap is rejected',
  );
  _expectThrowsRangeError(
    () => screens.viewport.selectionRange(
      anchor,
      anchor,
      maxWordScanCells: TerminalSelectionRange.maximumWordScanCells + 1,
    ),
    'oversized word scan cap is rejected',
  );
  _expectThrowsRangeError(
    () => screens.viewport.extractSelection(
      range,
      maxScalars: TerminalSelectionText.maximumScalars + 1,
    ),
    'oversized extraction cap is rejected',
  );
}

String _selectedTextAt(
  TerminalScreenSet screens,
  int column,
  TerminalSelectionUnit unit, {
  int row = 0,
}) {
  final TerminalLogicalAnchor focus = screens.viewport.anchorAt(row, column);
  final TerminalSelectionRange range = _requiredRange(
    screens.viewport,
    focus,
    focus,
    unit: unit,
  );
  return _requiredText(screens.viewport, range).text;
}

TerminalSelectionRange _requiredRange(
  TerminalViewport viewport,
  TerminalLogicalAnchor base,
  TerminalLogicalAnchor extent, {
  TerminalSelectionUnit unit = TerminalSelectionUnit.cell,
  int maxWordScanCells = TerminalSelectionRange.defaultMaxWordScanCells,
}) {
  final TerminalSelectionRange? range = viewport.selectionRange(
    base,
    extent,
    unit: unit,
    maxWordScanCells: maxWordScanCells,
  );
  if (range == null) {
    throw StateError('expected retained selection range');
  }
  return range;
}

TerminalSelectionText _requiredText(
  TerminalViewport viewport,
  TerminalSelectionRange range, {
  int maxScalars = TerminalSelectionText.defaultMaxScalars,
}) {
  final TerminalSelectionText? text = viewport.extractSelection(
    range,
    maxScalars: maxScalars,
  );
  if (text == null) {
    throw StateError('expected retained selection text');
  }
  return text;
}

TerminalSearchResult _requiredSearch(
  TerminalViewport viewport,
  String query, {
  TerminalSearchDirection direction = TerminalSearchDirection.forward,
  TerminalLogicalAnchor? start,
  int maxScalars = TerminalSearchResult.defaultMaxScalars,
  int maxMatches = TerminalSearchResult.defaultMaxMatches,
}) {
  final TerminalSearchResult? result = viewport.search(
    query,
    direction: direction,
    start: start,
    maxScalars: maxScalars,
    maxMatches: maxMatches,
  );
  if (result == null) {
    throw StateError('expected searchable retained document');
  }
  return result;
}

String _matchText(TerminalViewport viewport, TerminalSearchMatch match) =>
    _requiredText(viewport, match.range).text;

void _setText(TerminalScreen screen, int row, String text) {
  var column = 0;
  for (final int scalar in text.runes) {
    screen.setNarrowCell(row, column++, scalar);
  }
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
