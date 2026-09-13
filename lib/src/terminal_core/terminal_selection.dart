part of 'terminal_screen_set.dart';

enum TerminalSelectionUnit { cell, word, logicalLine }

final class TerminalSelectionSpan {
  TerminalSelectionSpan({
    required this.row,
    required this.startColumn,
    required this.endColumn,
  }) {
    RangeError.checkValueInInterval(row, 0, TerminalScreen.maxRows - 1, 'row');
    RangeError.checkValueInInterval(
      startColumn,
      0,
      TerminalScreen.maxColumns - 1,
      'startColumn',
    );
    RangeError.checkValueInInterval(
      endColumn,
      1,
      TerminalScreen.maxColumns,
      'endColumn',
    );
    if (startColumn >= endColumn) {
      throw ArgumentError('selection span must be non-empty');
    }
  }

  final int row;
  final int startColumn;
  final int endColumn;

  int get cellCount => endColumn - startColumn;
}

final class TerminalSelectionProjection {
  TerminalSelectionProjection._(List<TerminalSelectionSpan> spans)
    : spans = List<TerminalSelectionSpan>.unmodifiable(spans),
      selectedCellCount = spans.fold<int>(
        0,
        (int total, TerminalSelectionSpan span) => total + span.cellCount,
      );

  final List<TerminalSelectionSpan> spans;
  final int selectedCellCount;

  bool get isEmpty => spans.isEmpty;
}

/// A normalized, end-exclusive range over retained terminal content.
final class TerminalSelectionRange {
  const TerminalSelectionRange._({
    required this.start,
    required this.end,
    required this.unit,
    required this.isReversed,
    required this.semanticRowFlags,
    required this.isBoundaryLimited,
  });

  static const int defaultMaxWordScanCells = 4096;
  static const int maximumWordScanCells = 65536;

  final TerminalLogicalAnchor start;
  final TerminalLogicalAnchor end;
  final TerminalSelectionUnit unit;
  final bool isReversed;
  final int semanticRowFlags;
  final bool isBoundaryLimited;

  bool get isCollapsed => start == end;
}

/// Bounded text extracted from a stable selection range.
final class TerminalSelectionText {
  const TerminalSelectionText._({
    required this.text,
    required this.scalarCount,
    required this.isTruncated,
  });

  static const int defaultMaxScalars = 1048576;
  static const int maximumScalars = 4194304;

  final String text;
  final int scalarCount;
  final bool isTruncated;
}

enum TerminalSearchDirection { forward, backward }

final class TerminalSearchMatch {
  const TerminalSearchMatch._(this.range);

  final TerminalSelectionRange range;

  TerminalLogicalAnchor get start => range.start;
  TerminalLogicalAnchor get end => range.end;
  int get semanticRowFlags => range.semanticRowFlags;
}

/// Bounded exact-search results in the requested traversal order.
final class TerminalSearchResult {
  TerminalSearchResult._({
    required List<TerminalSearchMatch> matches,
    required this.sourceScreenKind,
    required this.sourceScreenGeneration,
    required this.sourceScrollbackGeneration,
    required this.scannedScalars,
    required this.scanLimitReached,
    required this.matchLimitReached,
  }) : matches = List<TerminalSearchMatch>.unmodifiable(matches);

  static const int maximumQueryScalars = 256;
  static const int defaultMaxScalars = 1048576;
  static const int maximumScalars = 4194304;
  static const int defaultMaxMatches = 100;
  static const int maximumMatches = 1000;

  final List<TerminalSearchMatch> matches;
  final TerminalScreenKind sourceScreenKind;
  final int sourceScreenGeneration;
  final int sourceScrollbackGeneration;
  final int scannedScalars;
  final bool scanLimitReached;
  final bool matchLimitReached;

  bool get isTruncated => scanLimitReached || matchLimitReached;
}

TerminalSelectionRange? _createSelectionRange(
  TerminalViewport viewport,
  TerminalLogicalAnchor base,
  TerminalLogicalAnchor extent, {
  required TerminalSelectionUnit unit,
  required int maxWordScanCells,
}) {
  RangeError.checkValueInInterval(
    maxWordScanCells,
    1,
    TerminalSelectionRange.maximumWordScanCells,
    'maxWordScanCells',
  );
  viewport._sync();
  if (base.screenKind != extent.screenKind ||
      base.screenKind != viewport._screens.activeKind) {
    return null;
  }
  final _DocumentBoundary? baseBoundary = _resolveDocumentBoundary(
    viewport,
    base,
  );
  final _DocumentBoundary? extentBoundary = _resolveDocumentBoundary(
    viewport,
    extent,
  );
  if (baseBoundary == null || extentBoundary == null) {
    return null;
  }
  final int direction = _compareDocumentBoundaries(
    baseBoundary,
    extentBoundary,
  );
  final bool reversed = direction > 0;
  _DocumentBoundary start = reversed ? extentBoundary : baseBoundary;
  _DocumentBoundary end = reversed ? baseBoundary : extentBoundary;
  var boundaryLimited = false;

  if (unit != TerminalSelectionUnit.cell) {
    final _DocumentCell? first;
    final _DocumentCell? last;
    if (_compareDocumentBoundaries(start, end) == 0) {
      final _DocumentCell? focus = start.cellIndex < start.cellCount
          ? _cellAtBoundary(viewport, start)
          : _cellBeforeBoundary(viewport, start);
      first = focus;
      last = focus;
    } else {
      first = _cellAtOrAfterBoundary(viewport, start);
      last = _cellBeforeBoundary(viewport, end);
    }

    if (unit == TerminalSelectionUnit.word && first != null && last != null) {
      final _ExpandedWord expandedStart = _expandWord(
        viewport,
        first,
        maxWordScanCells,
      );
      final _ExpandedWord expandedEnd = first.samePosition(last)
          ? expandedStart
          : _expandWord(viewport, last, maxWordScanCells);
      start = expandedStart.start;
      end = expandedEnd.end;
      boundaryLimited = expandedStart.isLimited || expandedEnd.isLimited;
    } else if (unit == TerminalSelectionUnit.logicalLine) {
      final _DocumentBoundary startFocus = first?.start ?? start;
      final _DocumentBoundary endFocus = last?.end ?? end;
      start = _logicalLineStart(viewport, startFocus);
      end = _logicalLineEnd(viewport, endFocus);
    }
  }

  return _selectionRangeFromBoundaries(
    viewport,
    start,
    end,
    unit: unit,
    isReversed: reversed,
    isBoundaryLimited: boundaryLimited,
  );
}

TerminalSelectionRange _selectionRangeFromBoundaries(
  TerminalViewport viewport,
  _DocumentBoundary start,
  _DocumentBoundary end, {
  required TerminalSelectionUnit unit,
  required bool isReversed,
  required bool isBoundaryLimited,
  int? semanticRowFlags,
}) => TerminalSelectionRange._(
  start: start.anchor,
  end: end.anchor,
  unit: unit,
  isReversed: isReversed,
  semanticRowFlags:
      semanticRowFlags ?? _semanticFlagsForRange(viewport, start, end),
  isBoundaryLimited: isBoundaryLimited,
);

TerminalSelectionText? _extractSelection(
  TerminalViewport viewport,
  TerminalSelectionRange range, {
  required int maxScalars,
}) {
  RangeError.checkValueInInterval(
    maxScalars,
    1,
    TerminalSelectionText.maximumScalars,
    'maxScalars',
  );
  final _DocumentBoundary? start = _resolveDocumentBoundary(
    viewport,
    range.start,
  );
  final _DocumentBoundary? end = _resolveDocumentBoundary(viewport, range.end);
  if (start == null ||
      end == null ||
      _compareDocumentBoundaries(start, end) > 0) {
    return null;
  }

  final StringBuffer text = StringBuffer();
  var scalarCount = 0;

  bool appendScalars(List<int> scalars) {
    if (scalarCount + scalars.length > maxScalars) {
      return false;
    }
    for (final int scalar in scalars) {
      text.writeCharCode(scalar);
    }
    scalarCount += scalars.length;
    return true;
  }

  bool appendCell(int row, int column) {
    final TerminalScreenKind kind = range.start.screenKind;
    final int content = viewport._combinedContentAt(kind, row, column);
    final int flags = viewport._combinedWidthFlagsAt(kind, row, column);
    if (flags & TerminalCellFlags.grapheme != 0) {
      return appendScalars(viewport._screens.graphemeTable.scalarsAt(content));
    }
    if (scalarCount == maxScalars) {
      return false;
    }
    text.writeCharCode(content == 0 ? 0x20 : content);
    scalarCount++;
    return true;
  }

  for (int row = start.row; row <= end.row; row++) {
    final int cellCount = viewport._combinedLogicalCellCount(
      range.start.screenKind,
      row,
    );
    final int firstCell = row == start.row ? start.cellIndex : 0;
    final int lastCell = row == end.row ? end.cellIndex : cellCount;
    final int extent = viewport._combinedRowExtent(range.start.screenKind, row);
    var logicalCell = 0;
    for (int column = 0; column < extent; column++) {
      if ((viewport._combinedWidthFlagsAt(range.start.screenKind, row, column) &
              TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
        continue;
      }
      if (logicalCell >= firstCell &&
          logicalCell < lastCell &&
          !appendCell(row, column)) {
        return TerminalSelectionText._(
          text: text.toString(),
          scalarCount: scalarCount,
          isTruncated: true,
        );
      }
      logicalCell++;
    }
    if (row < end.row &&
        !viewport._combinedJoinsNext(range.start.screenKind, row)) {
      if (scalarCount == maxScalars) {
        return TerminalSelectionText._(
          text: text.toString(),
          scalarCount: scalarCount,
          isTruncated: true,
        );
      }
      text.writeCharCode(0x0a);
      scalarCount++;
    }
  }
  return TerminalSelectionText._(
    text: text.toString(),
    scalarCount: scalarCount,
    isTruncated: false,
  );
}

TerminalSelectionProjection? _projectSelection(
  TerminalViewport viewport,
  TerminalSelectionRange range,
) {
  viewport._sync();
  if (!viewport.isSelectionAvailable(range)) return null;
  final _DocumentBoundary start = _resolveDocumentBoundary(
    viewport,
    range.start,
  )!;
  final _DocumentBoundary end = _resolveDocumentBoundary(viewport, range.end)!;
  if (_compareDocumentBoundaries(start, end) > 0) return null;
  final List<TerminalSelectionSpan> spans = <TerminalSelectionSpan>[];
  final TerminalScreenKind kind = range.start.screenKind;
  for (int viewportRow = 0; viewportRow < viewport.rows; viewportRow++) {
    final _ViewportLocation location = viewport._locate(viewportRow);
    final int combinedRow = kind == TerminalScreenKind.primary
        ? (location.history
              ? location.row
              : viewport._screens.scrollback.length + location.row)
        : location.row;
    if (combinedRow < start.row || combinedRow > end.row) continue;
    final int cellCount = viewport._combinedLogicalCellCount(kind, combinedRow);
    final int firstCell = (combinedRow == start.row ? start.cellIndex : 0)
        .clamp(0, cellCount);
    final int lastCell = (combinedRow == end.row ? end.cellIndex : cellCount)
        .clamp(0, cellCount);
    if (firstCell >= lastCell) continue;
    final int startColumn = _selectionBoundaryColumn(
      viewport,
      kind,
      combinedRow,
      firstCell,
    );
    final int endColumn = _selectionBoundaryColumn(
      viewport,
      kind,
      combinedRow,
      lastCell,
    );
    if (startColumn >= endColumn) continue;
    spans.add(
      TerminalSelectionSpan(
        row: viewportRow,
        startColumn: startColumn,
        endColumn: endColumn,
      ),
    );
  }
  return TerminalSelectionProjection._(spans);
}

int _selectionBoundaryColumn(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int cellIndex,
) {
  final int cellCount = viewport._combinedLogicalCellCount(kind, row);
  if (cellIndex >= cellCount) {
    return viewport._combinedRowExtent(kind, row).clamp(0, viewport.columns);
  }
  return viewport
      ._combinedColumnForLogicalCell(kind, row, cellIndex)
      .clamp(0, viewport.columns);
}

TerminalSearchResult? _searchTerminalDocument(
  TerminalViewport viewport,
  String query, {
  required TerminalSearchDirection direction,
  required TerminalLogicalAnchor? start,
  required int maxScalars,
  required int maxMatches,
}) {
  RangeError.checkValueInInterval(
    maxScalars,
    1,
    TerminalSearchResult.maximumScalars,
    'maxScalars',
  );
  RangeError.checkValueInInterval(
    maxMatches,
    1,
    TerminalSearchResult.maximumMatches,
    'maxMatches',
  );
  final List<int> queryScalars = <int>[];
  for (final int scalar in query.runes) {
    if (queryScalars.length == TerminalSearchResult.maximumQueryScalars) {
      throw RangeError.range(
        queryScalars.length + 1,
        1,
        TerminalSearchResult.maximumQueryScalars,
        'query.runes.length',
      );
    }
    queryScalars.add(scalar);
  }
  if (queryScalars.isEmpty) {
    throw ArgumentError.value(query, 'query', 'must not be empty');
  }

  viewport._sync();
  final TerminalScreenKind kind = viewport._screens.activeKind;
  final _DocumentBoundary? startBoundary;
  if (start != null) {
    if (start.screenKind != kind) {
      return null;
    }
    startBoundary = _resolveDocumentBoundary(viewport, start);
    if (startBoundary == null) {
      return null;
    }
  } else {
    startBoundary = direction == TerminalSearchDirection.forward
        ? _documentStart(viewport, kind)
        : _documentEnd(viewport, kind);
  }

  final List<int> pattern = direction == TerminalSearchDirection.forward
      ? queryScalars
      : queryScalars.reversed.toList(growable: false);
  final _TerminalSearchScanner scanner = _TerminalSearchScanner(
    viewport,
    kind,
    direction,
    pattern,
    maxScalars,
    maxMatches,
  );
  if (direction == TerminalSearchDirection.forward) {
    _scanForward(viewport, kind, startBoundary, scanner);
  } else {
    _scanBackward(viewport, kind, startBoundary, scanner);
  }
  return scanner.result();
}

void _scanForward(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  _DocumentBoundary start,
  _TerminalSearchScanner scanner,
) {
  final int rowCount = viewport._combinedRowCount(kind);
  for (int row = start.row; row < rowCount && !scanner.stopped; row++) {
    final int firstCell = row == start.row ? start.cellIndex : 0;
    final int extent = viewport._combinedRowExtent(kind, row);
    var logicalCell = 0;
    for (int column = 0; column < extent && !scanner.stopped; column++) {
      if ((viewport._combinedWidthFlagsAt(kind, row, column) &
              TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
        continue;
      }
      if (logicalCell++ < firstCell) {
        continue;
      }
      final int cell = logicalCell - 1;
      _scanCellScalars(
        viewport,
        kind,
        row,
        column,
        cell,
        scanner,
        reverse: false,
      );
    }
    if (row + 1 < rowCount && !viewport._combinedJoinsNext(kind, row)) {
      scanner.breakLogicalLine();
    }
  }
}

void _scanBackward(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  _DocumentBoundary start,
  _TerminalSearchScanner scanner,
) {
  for (int row = start.row; row >= 0 && !scanner.stopped; row--) {
    final int cellCount = viewport._combinedLogicalCellCount(kind, row);
    final int lastCell = row == start.row ? start.cellIndex - 1 : cellCount - 1;
    final int extent = viewport._combinedRowExtent(kind, row);
    var logicalCell = cellCount - 1;
    for (int column = extent - 1; column >= 0 && !scanner.stopped; column--) {
      if ((viewport._combinedWidthFlagsAt(kind, row, column) &
              TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
        continue;
      }
      final int cell = logicalCell--;
      if (cell > lastCell) {
        continue;
      }
      _scanCellScalars(
        viewport,
        kind,
        row,
        column,
        cell,
        scanner,
        reverse: true,
      );
    }
    if (row > 0 && !viewport._combinedJoinsNext(kind, row - 1)) {
      scanner.breakLogicalLine();
    }
  }
}

void _scanCellScalars(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int column,
  int cell,
  _TerminalSearchScanner scanner, {
  required bool reverse,
}) {
  final int content = viewport._combinedContentAt(kind, row, column);
  final int flags = viewport._combinedWidthFlagsAt(kind, row, column);
  if (flags & TerminalCellFlags.grapheme == 0) {
    scanner.add(
      content == 0 ? 0x20 : content,
      row,
      cell,
      isCellFirst: true,
      isCellLast: true,
    );
    return;
  }
  final Uint32List scalars = viewport._screens.graphemeTable.scalarsAt(content);
  if (reverse) {
    for (int index = scalars.length - 1; index >= 0; index--) {
      if (!scanner.add(
        scalars[index],
        row,
        cell,
        isCellFirst: index == 0,
        isCellLast: index == scalars.length - 1,
      )) {
        return;
      }
    }
    return;
  }
  for (int index = 0; index < scalars.length; index++) {
    if (!scanner.add(
      scalars[index],
      row,
      cell,
      isCellFirst: index == 0,
      isCellLast: index == scalars.length - 1,
    )) {
      return;
    }
  }
}

final class _TerminalSearchScanner {
  _TerminalSearchScanner(
    this.viewport,
    this.kind,
    this.direction,
    List<int> pattern,
    this.maxScalars,
    this.maxMatches,
  ) : pattern = Uint32List.fromList(pattern),
      prefix = Uint16List(pattern.length),
      ringRows = Uint32List(pattern.length),
      ringCells = Uint16List(pattern.length),
      ringFlags = Uint8List(pattern.length),
      ringSemanticFlags = Uint8List(pattern.length) {
    int matched = 0;
    for (int index = 1; index < pattern.length; index++) {
      while (matched > 0 && pattern[index] != pattern[matched]) {
        matched = prefix[matched - 1];
      }
      if (pattern[index] == pattern[matched]) {
        matched++;
      }
      prefix[index] = matched;
    }
  }

  static const int _cellFirst = 1 << 0;
  static const int _cellLast = 1 << 1;
  static const int _semanticMask =
      TerminalRowFlags.prompt |
      TerminalRowFlags.command |
      TerminalRowFlags.output;

  final TerminalViewport viewport;
  final TerminalScreenKind kind;
  final TerminalSearchDirection direction;
  final Uint32List pattern;
  final Uint16List prefix;
  final Uint32List ringRows;
  final Uint16List ringCells;
  final Uint8List ringFlags;
  final Uint8List ringSemanticFlags;
  final int maxScalars;
  final int maxMatches;
  final List<TerminalSearchMatch> _matches = <TerminalSearchMatch>[];
  int _matched = 0;
  int _processed = 0;
  int _scannedScalars = 0;
  bool _scanLimitReached = false;
  bool _matchLimitReached = false;

  bool get stopped => _scanLimitReached || _matchLimitReached;

  bool add(
    int scalar,
    int row,
    int cell, {
    required bool isCellFirst,
    required bool isCellLast,
  }) {
    if (_scannedScalars == maxScalars) {
      _scanLimitReached = true;
      return false;
    }
    final int ringIndex = _processed % pattern.length;
    ringRows[ringIndex] = row;
    ringCells[ringIndex] = cell;
    ringFlags[ringIndex] =
        (isCellFirst ? _cellFirst : 0) | (isCellLast ? _cellLast : 0);
    ringSemanticFlags[ringIndex] =
        viewport._combinedRowFlagsAt(kind, row) & _semanticMask;
    _processed++;
    _scannedScalars++;

    while (_matched > 0 && scalar != pattern[_matched]) {
      _matched = prefix[_matched - 1];
    }
    if (scalar == pattern[_matched]) {
      _matched++;
    }
    if (_matched != pattern.length) {
      return true;
    }

    final int oldestIndex = (_processed - pattern.length) % pattern.length;
    final int newestIndex = (_processed - 1) % pattern.length;
    final bool cellAligned = direction == TerminalSearchDirection.forward
        ? ringFlags[oldestIndex] & _cellFirst != 0 &&
              ringFlags[newestIndex] & _cellLast != 0
        : ringFlags[oldestIndex] & _cellLast != 0 &&
              ringFlags[newestIndex] & _cellFirst != 0;
    if (cellAligned) {
      final int startIndex = direction == TerminalSearchDirection.forward
          ? oldestIndex
          : newestIndex;
      final int endIndex = direction == TerminalSearchDirection.forward
          ? newestIndex
          : oldestIndex;
      final _DocumentBoundary matchStart = _boundaryForCell(
        viewport,
        kind,
        ringRows[startIndex],
        ringCells[startIndex],
      );
      final _DocumentBoundary matchEnd = _boundaryAfterCell(
        viewport,
        kind,
        ringRows[endIndex],
        ringCells[endIndex],
      );
      var semanticFlags = 0;
      for (int index = 0; index < pattern.length; index++) {
        semanticFlags |= ringSemanticFlags[index];
      }
      _matches.add(
        TerminalSearchMatch._(
          _selectionRangeFromBoundaries(
            viewport,
            matchStart,
            matchEnd,
            unit: TerminalSelectionUnit.cell,
            isReversed: false,
            isBoundaryLimited: false,
            semanticRowFlags: semanticFlags,
          ),
        ),
      );
      if (_matches.length == maxMatches) {
        _matchLimitReached = true;
        return false;
      }
    }
    _matched = prefix[_matched - 1];
    return true;
  }

  void breakLogicalLine() {
    _matched = 0;
  }

  TerminalSearchResult result() => TerminalSearchResult._(
    matches: _matches,
    sourceScreenKind: kind,
    sourceScreenGeneration: viewport._screens.activeScreen.generation,
    sourceScrollbackGeneration: viewport._screens.scrollback.generation,
    scannedScalars: _scannedScalars,
    scanLimitReached: _scanLimitReached,
    matchLimitReached: _matchLimitReached,
  );
}

final class _DocumentBoundary {
  const _DocumentBoundary({
    required this.anchor,
    required this.row,
    required this.cellIndex,
    required this.cellCount,
  });

  final TerminalLogicalAnchor anchor;
  final int row;
  final int cellIndex;
  final int cellCount;
}

final class _DocumentCell {
  const _DocumentCell({
    required this.start,
    required this.end,
    required this.row,
    required this.cellIndex,
  });

  final _DocumentBoundary start;
  final _DocumentBoundary end;
  final int row;
  final int cellIndex;

  bool samePosition(_DocumentCell other) =>
      row == other.row && cellIndex == other.cellIndex;
}

final class _ExpandedWord {
  const _ExpandedWord(this.start, this.end, this.isLimited);

  final _DocumentBoundary start;
  final _DocumentBoundary end;
  final bool isLimited;
}

_DocumentBoundary? _resolveDocumentBoundary(
  TerminalViewport viewport,
  TerminalLogicalAnchor anchor,
) {
  final int rowCount = viewport._combinedRowCount(anchor.screenKind);
  for (int row = 0; row < rowCount; row++) {
    if (viewport._combinedLogicalLineIdAt(anchor.screenKind, row) !=
            anchor.logicalLineId ||
        viewport._combinedLogicalLineEpochAt(anchor.screenKind, row) !=
            anchor.logicalLineEpoch) {
      continue;
    }
    final int base = viewport._combinedLogicalOffsetAt(anchor.screenKind, row);
    final int cellCount = viewport._combinedLogicalCellCount(
      anchor.screenKind,
      row,
    );
    final int end = base + cellCount;
    if (anchor.cellOffset < base) {
      return null;
    }
    if (anchor.cellOffset > end) {
      continue;
    }
    if (anchor.cellOffset == end &&
        viewport._combinedJoinsNext(anchor.screenKind, row)) {
      continue;
    }
    return _DocumentBoundary(
      anchor: anchor,
      row: row,
      cellIndex: anchor.cellOffset - base,
      cellCount: cellCount,
    );
  }
  return null;
}

int _compareDocumentBoundaries(
  _DocumentBoundary first,
  _DocumentBoundary second,
) {
  if (first.row != second.row) {
    return first.row.compareTo(second.row);
  }
  return first.cellIndex.compareTo(second.cellIndex);
}

_DocumentBoundary _documentStart(
  TerminalViewport viewport,
  TerminalScreenKind kind,
) => _boundaryForCell(viewport, kind, 0, 0);

_DocumentBoundary _documentEnd(
  TerminalViewport viewport,
  TerminalScreenKind kind,
) {
  final int row = viewport._combinedRowCount(kind) - 1;
  return _boundaryAt(
    viewport,
    kind,
    row,
    viewport._combinedLogicalCellCount(kind, row),
  );
}

_DocumentBoundary _boundaryForCell(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int cell,
) => _boundaryAt(viewport, kind, row, cell);

_DocumentBoundary _boundaryAfterCell(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int cell,
) => _boundaryAt(viewport, kind, row, cell + 1);

_DocumentBoundary _boundaryAt(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int cell,
) {
  final int cellCount = viewport._combinedLogicalCellCount(kind, row);
  if (cell < 0 || cell > cellCount) {
    throw RangeError.range(cell, 0, cellCount, 'cell');
  }
  final TerminalLogicalAnchor anchor = TerminalLogicalAnchor(
    screenKind: kind,
    logicalLineId: viewport._combinedLogicalLineIdAt(kind, row),
    logicalLineEpoch: viewport._combinedLogicalLineEpochAt(kind, row),
    cellOffset: viewport._combinedLogicalOffsetAt(kind, row) + cell,
  );
  return _DocumentBoundary(
    anchor: anchor,
    row: row,
    cellIndex: cell,
    cellCount: cellCount,
  );
}

_DocumentCell _cellAtBoundary(
  TerminalViewport viewport,
  _DocumentBoundary boundary,
) => _cellAt(
  viewport,
  boundary.anchor.screenKind,
  boundary.row,
  boundary.cellIndex,
);

_DocumentCell _cellAt(
  TerminalViewport viewport,
  TerminalScreenKind kind,
  int row,
  int cell,
) => _DocumentCell(
  start: _boundaryForCell(viewport, kind, row, cell),
  end: _boundaryAfterCell(viewport, kind, row, cell),
  row: row,
  cellIndex: cell,
);

_DocumentCell? _cellAtOrAfterBoundary(
  TerminalViewport viewport,
  _DocumentBoundary boundary,
) {
  final TerminalScreenKind kind = boundary.anchor.screenKind;
  final int rowCount = viewport._combinedRowCount(kind);
  for (int row = boundary.row; row < rowCount; row++) {
    final int firstCell = row == boundary.row ? boundary.cellIndex : 0;
    final int cellCount = viewport._combinedLogicalCellCount(kind, row);
    if (firstCell < cellCount) {
      return _cellAt(viewport, kind, row, firstCell);
    }
  }
  return null;
}

_DocumentCell? _cellBeforeBoundary(
  TerminalViewport viewport,
  _DocumentBoundary boundary,
) {
  final TerminalScreenKind kind = boundary.anchor.screenKind;
  for (int row = boundary.row; row >= 0; row--) {
    final int cellCount = viewport._combinedLogicalCellCount(kind, row);
    final int endCell = row == boundary.row ? boundary.cellIndex : cellCount;
    if (endCell > 0) {
      return _cellAt(viewport, kind, row, endCell - 1);
    }
  }
  return null;
}

_DocumentCell? _previousCellInLogicalLine(
  TerminalViewport viewport,
  _DocumentCell cell,
) {
  if (cell.cellIndex > 0) {
    return _cellAt(
      viewport,
      cell.start.anchor.screenKind,
      cell.row,
      cell.cellIndex - 1,
    );
  }
  final TerminalScreenKind kind = cell.start.anchor.screenKind;
  var row = cell.row;
  while (row > 0 && viewport._combinedJoinsNext(kind, row - 1)) {
    row--;
    final int count = viewport._combinedLogicalCellCount(kind, row);
    if (count > 0) {
      return _cellAt(viewport, kind, row, count - 1);
    }
  }
  return null;
}

_DocumentCell? _nextCellInLogicalLine(
  TerminalViewport viewport,
  _DocumentCell cell,
) {
  final TerminalScreenKind kind = cell.start.anchor.screenKind;
  final int count = viewport._combinedLogicalCellCount(kind, cell.row);
  if (cell.cellIndex + 1 < count) {
    return _cellAt(viewport, kind, cell.row, cell.cellIndex + 1);
  }
  var row = cell.row;
  final int rowCount = viewport._combinedRowCount(kind);
  while (row + 1 < rowCount && viewport._combinedJoinsNext(kind, row)) {
    row++;
    final int nextCount = viewport._combinedLogicalCellCount(kind, row);
    if (nextCount > 0) {
      return _cellAt(viewport, kind, row, 0);
    }
  }
  return null;
}

_ExpandedWord _expandWord(
  TerminalViewport viewport,
  _DocumentCell focus,
  int maxScanCells,
) {
  final int wordClass = _wordClassForCell(viewport, focus);
  if (wordClass >= _wordSeparatorBase) {
    return _ExpandedWord(focus.start, focus.end, false);
  }
  _DocumentCell first = focus;
  _DocumentCell last = focus;
  var limited = false;
  var scanned = 0;
  while (scanned < maxScanCells) {
    final _DocumentCell? previous = _previousCellInLogicalLine(viewport, first);
    if (previous == null ||
        _wordClassForCell(viewport, previous) != wordClass) {
      break;
    }
    first = previous;
    scanned++;
  }
  if (scanned == maxScanCells) {
    final _DocumentCell? previous = _previousCellInLogicalLine(viewport, first);
    limited =
        previous != null && _wordClassForCell(viewport, previous) == wordClass;
  }
  scanned = 0;
  while (scanned < maxScanCells) {
    final _DocumentCell? next = _nextCellInLogicalLine(viewport, last);
    if (next == null || _wordClassForCell(viewport, next) != wordClass) {
      break;
    }
    last = next;
    scanned++;
  }
  if (scanned == maxScanCells) {
    final _DocumentCell? next = _nextCellInLogicalLine(viewport, last);
    limited =
        limited ||
        (next != null && _wordClassForCell(viewport, next) == wordClass);
  }
  return _ExpandedWord(first.start, last.end, limited);
}

const int _wordWhitespace = 0;
const int _wordContent = 1;
const int _wordSeparatorBase = 0x100;

int _wordClassForCell(TerminalViewport viewport, _DocumentCell cell) {
  final TerminalScreenKind kind = cell.start.anchor.screenKind;
  final int column = viewport._combinedColumnForLogicalCell(
    kind,
    cell.row,
    cell.cellIndex,
  );
  final int content = viewport._combinedContentAt(kind, cell.row, column);
  final int flags = viewport._combinedWidthFlagsAt(kind, cell.row, column);
  final int scalar = content == 0
      ? 0x20
      : flags & TerminalCellFlags.grapheme != 0
      ? viewport._screens.graphemeTable.scalarsAt(content).first
      : content;
  if (_isUnicodeWhitespace(scalar)) {
    return _wordWhitespace;
  }
  if (scalar > 0x7f ||
      scalar >= 0x30 && scalar <= 0x39 ||
      scalar >= 0x41 && scalar <= 0x5a ||
      scalar == 0x5f ||
      scalar >= 0x61 && scalar <= 0x7a) {
    return _wordContent;
  }
  return _wordSeparatorBase + scalar;
}

bool _isUnicodeWhitespace(int scalar) =>
    scalar >= 0x09 && scalar <= 0x0d ||
    scalar == 0x20 ||
    scalar == 0x85 ||
    scalar == 0xa0 ||
    scalar == 0x1680 ||
    scalar >= 0x2000 && scalar <= 0x200a ||
    scalar == 0x2028 ||
    scalar == 0x2029 ||
    scalar == 0x202f ||
    scalar == 0x205f ||
    scalar == 0x3000;

_DocumentBoundary _logicalLineStart(
  TerminalViewport viewport,
  _DocumentBoundary focus,
) {
  final TerminalScreenKind kind = focus.anchor.screenKind;
  var row = focus.row;
  while (row > 0 && viewport._combinedJoinsNext(kind, row - 1)) {
    row--;
  }
  return _boundaryAt(viewport, kind, row, 0);
}

_DocumentBoundary _logicalLineEnd(
  TerminalViewport viewport,
  _DocumentBoundary focus,
) {
  final TerminalScreenKind kind = focus.anchor.screenKind;
  var row = focus.row;
  final int rowCount = viewport._combinedRowCount(kind);
  while (row + 1 < rowCount && viewport._combinedJoinsNext(kind, row)) {
    row++;
  }
  return _boundaryAt(
    viewport,
    kind,
    row,
    viewport._combinedLogicalCellCount(kind, row),
  );
}

int _semanticFlagsForRange(
  TerminalViewport viewport,
  _DocumentBoundary start,
  _DocumentBoundary end,
) {
  if (_compareDocumentBoundaries(start, end) == 0) {
    return 0;
  }
  const int mask =
      TerminalRowFlags.prompt |
      TerminalRowFlags.command |
      TerminalRowFlags.output;
  int lastRow = end.row;
  if (end.cellIndex == 0 && lastRow > start.row) {
    lastRow--;
  }
  var result = 0;
  for (int row = start.row; row <= lastRow; row++) {
    result |= viewport._combinedRowFlagsAt(start.anchor.screenKind, row) & mask;
  }
  return result;
}
