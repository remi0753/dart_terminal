part of 'terminal_screen_set.dart';

/// A stable lead-cell boundary within one logical terminal line.
final class TerminalLogicalAnchor {
  static const int maxCellOffset = 0x7fffffffffffffff;
  static const int maxLogicalLineEpoch = 0x7fffffffffffffff;

  factory TerminalLogicalAnchor({
    required TerminalScreenKind screenKind,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int cellOffset,
  }) {
    if (logicalLineId <= 0 || logicalLineId > TerminalScreen.maxLogicalLineId) {
      throw RangeError.range(
        logicalLineId,
        1,
        TerminalScreen.maxLogicalLineId,
        'logicalLineId',
      );
    }
    if (logicalLineEpoch <= 0 || logicalLineEpoch > maxLogicalLineEpoch) {
      throw RangeError.range(
        logicalLineEpoch,
        1,
        maxLogicalLineEpoch,
        'logicalLineEpoch',
      );
    }
    if (cellOffset < 0 || cellOffset > maxCellOffset) {
      throw RangeError.range(cellOffset, 0, maxCellOffset, 'cellOffset');
    }
    return TerminalLogicalAnchor._(
      screenKind,
      logicalLineId,
      logicalLineEpoch,
      cellOffset,
    );
  }

  const TerminalLogicalAnchor._(
    this.screenKind,
    this.logicalLineId,
    this.logicalLineEpoch,
    this.cellOffset,
  );

  final TerminalScreenKind screenKind;
  final int logicalLineId;
  final int logicalLineEpoch;
  final int cellOffset;

  @override
  bool operator ==(Object other) =>
      other is TerminalLogicalAnchor &&
      other.screenKind == screenKind &&
      other.logicalLineId == logicalLineId &&
      other.logicalLineEpoch == logicalLineEpoch &&
      other.cellOffset == cellOffset;

  @override
  int get hashCode =>
      Object.hash(screenKind, logicalLineId, logicalLineEpoch, cellOffset);

  @override
  String toString() =>
      'TerminalLogicalAnchor('
      '$screenKind, $logicalLineId, $logicalLineEpoch, $cellOffset)';
}

/// A currently visible coordinate resolved from a logical anchor.
final class TerminalViewportPosition {
  const TerminalViewportPosition({required this.row, required this.column});

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is TerminalViewportPosition &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'TerminalViewportPosition($row, $column)';
}

/// Navigable row projection over primary history plus the active screen.
///
/// Positive offsets and scroll deltas move toward older primary rows. An
/// alternate screen always projects its own grid at effective offset zero;
/// the primary offset remains available when primary ownership returns.
final class TerminalViewport {
  TerminalViewport._(this._screens)
    : _seenHistoryGeneration = _screens.scrollback.generation,
      _seenRowsAppended = _screens.scrollback.totalRowsAppended,
      _seenContinuityGeneration = _screens.scrollback.continuityGeneration,
      _seenPrimaryGeneration = _screens.primary.generation,
      _seenAlternateGeneration = _screens.alternate.generation,
      _seenTransitionGeneration = _screens.transitionGeneration;

  final TerminalScreenSet _screens;
  int _primaryOffset = 0;
  int _generation = 1;
  int _seenHistoryGeneration;
  int _seenRowsAppended;
  int _seenContinuityGeneration;
  int _seenPrimaryGeneration;
  int _seenAlternateGeneration;
  int _seenTransitionGeneration;

  int get rows {
    _sync();
    return _screens.activeScreen.rows;
  }

  int get columns {
    _sync();
    return _screens.activeScreen.columns;
  }

  int get offset {
    _sync();
    return _screens.usingAlternate ? 0 : _primaryOffset;
  }

  /// Returns the retained primary offset even while alternate is active.
  int get primaryOffset {
    _sync();
    return _primaryOffset;
  }

  int get maximumOffset {
    _sync();
    return _screens.usingAlternate ? 0 : _screens.scrollback.length;
  }

  bool get atBottom => offset == 0;

  int get generation {
    _sync();
    return _generation;
  }

  int? get cursorRow {
    _sync();
    final TerminalScreen screen = _screens.activeScreen;
    if (_screens.usingAlternate) {
      return screen.cursorRow;
    }
    final int projected = _primaryOffset + screen.cursorRow;
    return projected < screen.rows ? projected : null;
  }

  int? get cursorColumn =>
      cursorRow == null ? null : _screens.activeScreen.cursorColumn;

  bool get cursorVisible =>
      cursorRow != null && _screens.activeScreen.cursorVisible;

  /// Moves by physical rows; positive values move toward older history.
  void scrollByRows(int rows) {
    _sync();
    if (_screens.usingAlternate || rows == 0) {
      return;
    }
    _setPrimaryOffset(_primaryOffset + rows);
  }

  /// Moves by active-grid heights; positive values move toward history.
  void scrollByPages(int pages) {
    _sync();
    if (_screens.usingAlternate || pages == 0) {
      return;
    }
    _setPrimaryOffset(_primaryOffset + pages * _screens.primary.rows);
  }

  void scrollToTop() {
    _sync();
    if (_screens.usingAlternate) {
      return;
    }
    _setPrimaryOffset(_screens.scrollback.length);
  }

  void scrollToBottom() {
    _sync();
    if (_screens.usingAlternate) {
      return;
    }
    _setPrimaryOffset(0);
  }

  bool get canJumpToPreviousPrompt =>
      _promptTargetOffset(previous: true) != null;

  bool get canJumpToNextPrompt => _promptTargetOffset(previous: false) != null;

  /// Moves the newest retained prompt before the current navigation position
  /// to the top of the primary viewport where possible.
  bool jumpToPreviousPrompt() => _jumpToPrompt(previous: true);

  /// Moves the oldest retained prompt after the current navigation position
  /// to the top of the primary viewport, or returns to the live grid.
  bool jumpToNextPrompt() => _jumpToPrompt(previous: false);

  bool isHistoryRow(int viewportRow) => _locate(viewportRow).history;

  /// Returns the stored source width for a projected physical row.
  int columnsAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.columnsAt(location.row)
        : _screens.activeScreen.columns;
  }

  int rowFlagsAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.rowFlagsAt(location.row)
        : _screens.activeScreen.rowFlagsAt(location.row);
  }

  int logicalLineIdAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.logicalLineIdAt(location.row)
        : _screens.activeScreen.logicalLineIdAt(location.row);
  }

  int logicalLineEpochAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.logicalLineEpochAt(location.row)
        : _screens.activeScreen.logicalLineEpochAt(location.row);
  }

  int contentAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.contentAt(location.row, column)
        : _screens.activeScreen.contentAt(location.row, column);
  }

  int foregroundAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.foregroundAt(location.row, column)
        : _screens.activeScreen.foregroundAt(location.row, column);
  }

  int backgroundAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.backgroundAt(location.row, column)
        : _screens.activeScreen.backgroundAt(location.row, column);
  }

  int styleAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.styleAt(location.row, column)
        : _screens.activeScreen.styleAt(location.row, column);
  }

  int hyperlinkAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.hyperlinkAt(location.row, column)
        : _screens.activeScreen.hyperlinkAt(location.row, column);
  }

  /// Resolves a visible cell to an immutable OSC 8 definition.
  ///
  /// Pointer-style out-of-grid coordinates return null. A wide continuation
  /// resolves to its canonical lead so a later click cannot split the cell.
  TerminalHyperlinkHit? hitTestHyperlink(int viewportRow, int column) {
    _sync();
    if (viewportRow < 0 || viewportRow >= _screens.activeScreen.rows) {
      return null;
    }
    final int sourceColumns = columnsAt(viewportRow);
    if (column < 0 || column >= sourceColumns) {
      return null;
    }
    int leadColumn = column;
    int flags = widthFlagsAt(viewportRow, leadColumn);
    if ((flags & TerminalCellFlags.widthMask) ==
        TerminalCellFlags.continuation) {
      if (leadColumn == 0) return null;
      leadColumn--;
      flags = widthFlagsAt(viewportRow, leadColumn);
      if ((flags & TerminalCellFlags.widthMask) != TerminalCellFlags.wide) {
        return null;
      }
    }
    final int hyperlink = hyperlinkAt(viewportRow, leadColumn);
    final TerminalHyperlinkTable table = _screens.hyperlinkTable;
    if (hyperlink <= 0 || hyperlink > table.definitionCount) {
      return null;
    }
    return TerminalHyperlinkHit(
      viewportGeneration: _generation,
      row: viewportRow,
      column: leadColumn,
      pointerColumn: column,
      cellWidth: (flags & TerminalCellFlags.widthMask) == TerminalCellFlags.wide
          ? 2
          : 1,
      definition: table.definitionAt(hyperlink),
    );
  }

  /// Re-resolves a prior physical pointer position after viewport mutation.
  TerminalHyperlinkHit? refreshHyperlinkHit(TerminalHyperlinkHit previous) {
    final TerminalHyperlinkHit? current = hitTestHyperlink(
      previous.row,
      previous.pointerColumn,
    );
    return current?.hyperlinkId == previous.hyperlinkId ? current : null;
  }

  int widthFlagsAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.widthFlagsAt(location.row, column)
        : _screens.activeScreen.widthFlagsAt(location.row, column);
  }

  List<int> _cellScalarsAt(int viewportRow, int column) {
    final int flags = widthFlagsAt(viewportRow, column);
    if ((flags & TerminalCellFlags.widthMask) ==
        TerminalCellFlags.continuation) {
      return const <int>[];
    }
    final int content = contentAt(viewportRow, column);
    if (flags & TerminalCellFlags.grapheme != 0) {
      return _screens.graphemeTable.scalarsAt(content);
    }
    return <int>[content == 0 ? 0x20 : content];
  }

  /// Returns the stable boundary at a projected cell's canonical lead.
  TerminalLogicalAnchor anchorAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    final TerminalScreenKind kind = _screens.activeKind;
    final int combinedRow = kind == TerminalScreenKind.primary
        ? (location.history
              ? location.row
              : _screens.scrollback.length + location.row)
        : location.row;
    return _anchorAtCombined(kind, combinedRow, column);
  }

  /// Captures a stable anchor from the active live grid, independently of the
  /// user's current primary-history viewport offset.
  TerminalLogicalAnchor anchorAtActiveScreen(int row, int column) {
    return anchorAtScreen(_screens.activeKind, row, column);
  }

  /// Captures a stable anchor from either live grid without changing which
  /// screen is active or observing the primary viewport offset.
  TerminalLogicalAnchor anchorAtScreen(
    TerminalScreenKind kind,
    int row,
    int column,
  ) {
    _sync();
    final TerminalScreen screen = _screens.screenFor(kind);
    if (row < 0 || row >= screen.rows) {
      throw RangeError.range(row, 0, screen.rows - 1, 'row');
    }
    final int combinedRow = kind == TerminalScreenKind.primary
        ? _screens.scrollback.length + row
        : row;
    return _anchorAtCombined(kind, combinedRow, column);
  }

  /// Captures a grid-exact anchor for resources placed in trailing blank cells.
  TerminalLogicalAnchor anchorAtScreenCell(
    TerminalScreenKind kind,
    int row,
    int column,
  ) {
    _sync();
    final TerminalScreen screen = _screens.screenFor(kind);
    if (row < 0 || row >= screen.rows) {
      throw RangeError.range(row, 0, screen.rows - 1, 'row');
    }
    final int combinedRow = kind == TerminalScreenKind.primary
        ? _screens.scrollback.length + row
        : row;
    return _anchorAtCombined(
      kind,
      combinedRow,
      column,
      preserveTrailingCells: true,
    );
  }

  /// Resolves an anchor relative to the active live grid, not the navigated
  /// viewport. A negative row identifies retained primary scrollback.
  TerminalViewportPosition? activeScreenPositionOf(
    TerminalLogicalAnchor anchor,
  ) => screenPositionOf(_screens.activeKind, anchor);

  /// Resolves an anchor relative to either live grid. A negative primary row
  /// identifies retained scrollback.
  TerminalViewportPosition? screenPositionOf(
    TerminalScreenKind kind,
    TerminalLogicalAnchor anchor,
  ) {
    _sync();
    if (anchor.screenKind != kind) return null;
    final _CombinedPosition? position = _resolveCombined(anchor);
    if (position == null) return null;
    final int row = anchor.screenKind == TerminalScreenKind.primary
        ? position.row - _screens.scrollback.length
        : position.row;
    return TerminalViewportPosition(row: row, column: position.column);
  }

  /// Resolves a grid-exact resource anchor relative to either live grid.
  TerminalViewportPosition? screenCellPositionOf(
    TerminalScreenKind kind,
    TerminalLogicalAnchor anchor,
  ) {
    _sync();
    if (anchor.screenKind != kind) return null;
    final _CombinedPosition? position = _resolveCombined(
      anchor,
      preserveTrailingCells: true,
    );
    if (position == null) return null;
    final int row = anchor.screenKind == TerminalScreenKind.primary
        ? position.row - _screens.scrollback.length
        : position.row;
    return TerminalViewportPosition(row: row, column: position.column);
  }

  /// Returns the stable boundary immediately after one projected cell.
  TerminalLogicalAnchor anchorAfter(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    final TerminalScreenKind kind = _screens.activeKind;
    final int combinedRow = kind == TerminalScreenKind.primary
        ? (location.history
              ? location.row
              : _screens.scrollback.length + location.row)
        : location.row;
    return _anchorAtCombined(kind, combinedRow, column, after: true);
  }

  /// Orders and optionally expands retained boundaries for selection.
  ///
  /// Returns null when either boundary is evicted or belongs to another
  /// active screen. Cell ranges are end-exclusive.
  TerminalSelectionRange? selectionRange(
    TerminalLogicalAnchor base,
    TerminalLogicalAnchor extent, {
    TerminalSelectionUnit unit = TerminalSelectionUnit.cell,
    int maxWordScanCells = TerminalSelectionRange.defaultMaxWordScanCells,
  }) => _createSelectionRange(
    this,
    base,
    extent,
    unit: unit,
    maxWordScanCells: maxWordScanCells,
  );

  /// Selects one logical line, clamped to a retained semantic segment when the
  /// target cell belongs to prompt, command input, or command output.
  TerminalSelectionRange? semanticLineSelectionAt(
    int viewportRow,
    int column, {
    int maxRanges = TerminalSemanticRangeSnapshot.defaultMaximumRanges,
  }) =>
      _semanticLineSelectionAt(this, viewportRow, column, maxRanges: maxRanges);

  /// Selects the complete retained command-output segment under one cell.
  TerminalSelectionRange? semanticOutputSelectionAt(
    int viewportRow,
    int column, {
    int maxRanges = TerminalSemanticRangeSnapshot.defaultMaximumRanges,
  }) => _semanticOutputSelectionAt(
    this,
    viewportRow,
    column,
    maxRanges: maxRanges,
  );

  /// Combines two retained output blocks for semantic output dragging.
  TerminalSelectionRange? combineSemanticOutputSelections(
    TerminalSelectionRange first,
    TerminalSelectionRange second,
  ) => _combineSemanticOutputSelections(this, first, second);

  /// Extracts retained text or returns null when either boundary was evicted.
  TerminalSelectionText? extractSelection(
    TerminalSelectionRange range, {
    int maxScalars = TerminalSelectionText.defaultMaxScalars,
  }) => _extractSelection(this, range, maxScalars: maxScalars);

  /// Whether both selection boundaries still belong to retained active content.
  bool isSelectionAvailable(TerminalSelectionRange range) {
    _sync();
    return range.start.screenKind == _screens.activeKind &&
        range.end.screenKind == _screens.activeKind &&
        _resolveDocumentBoundary(this, range.start) != null &&
        _resolveDocumentBoundary(this, range.end) != null;
  }

  /// Clips a stable selection to non-empty spans in the current viewport.
  TerminalSelectionProjection? projectSelection(TerminalSelectionRange range) =>
      _projectSelection(this, range);

  /// Whether an exact-search result still describes current retained content.
  bool isSearchResultCurrent(TerminalSearchResult result) {
    _sync();
    return result.sourceScreenKind == _screens.activeKind &&
        result.sourceScreenGeneration == _screens.activeScreen.generation &&
        result.sourceScrollbackGeneration == _screens.scrollback.generation;
  }

  /// Searches active retained logical lines without crossing hard boundaries.
  ///
  /// Returns null only when an explicit [start] boundary is unavailable.
  TerminalSearchResult? search(
    String query, {
    TerminalSearchDirection direction = TerminalSearchDirection.forward,
    TerminalLogicalAnchor? start,
    int maxScalars = TerminalSearchResult.defaultMaxScalars,
    int maxMatches = TerminalSearchResult.defaultMaxMatches,
  }) => _searchTerminalDocument(
    this,
    query,
    direction: direction,
    start: start,
    maxScalars: maxScalars,
    maxMatches: maxMatches,
  );

  TerminalViewportPosition? positionOf(TerminalLogicalAnchor anchor) {
    final TerminalViewportPosition? projected = projectedPositionOf(anchor);
    if (projected == null ||
        projected.row < 0 ||
        projected.row >= _screens.activeScreen.rows) {
      return null;
    }
    return projected;
  }

  /// Resolves an active-screen anchor relative to the navigated viewport,
  /// retaining negative/off-bottom rows for rectangular intersection tests.
  TerminalViewportPosition? projectedPositionOf(TerminalLogicalAnchor anchor) {
    _sync();
    if (anchor.screenKind != _screens.activeKind) {
      return null;
    }
    final _CombinedPosition? position = _resolveCombined(anchor);
    if (position == null) {
      return null;
    }
    final int start = anchor.screenKind == TerminalScreenKind.primary
        ? _screens.scrollback.length - _primaryOffset
        : 0;
    final int viewportRow = position.row - start;
    return TerminalViewportPosition(row: viewportRow, column: position.column);
  }

  /// Resolves a grid-exact resource anchor relative to viewport navigation.
  TerminalViewportPosition? projectedCellPositionOf(
    TerminalLogicalAnchor anchor,
  ) {
    _sync();
    if (anchor.screenKind != _screens.activeKind) return null;
    final _CombinedPosition? position = _resolveCombined(
      anchor,
      preserveTrailingCells: true,
    );
    if (position == null) return null;
    final int start = anchor.screenKind == TerminalScreenKind.primary
        ? _screens.scrollback.length - _primaryOffset
        : 0;
    return TerminalViewportPosition(
      row: position.row - start,
      column: position.column,
    );
  }

  _ViewportLocation _locate(int viewportRow) {
    _sync();
    final TerminalScreen screen = _screens.activeScreen;
    if (viewportRow < 0 || viewportRow >= screen.rows) {
      throw RangeError.range(viewportRow, 0, screen.rows - 1, 'viewportRow');
    }
    if (_screens.usingAlternate) {
      return _ViewportLocation.screen(viewportRow);
    }
    final int historyLength = _screens.scrollback.length;
    final int combinedRow = historyLength - _primaryOffset + viewportRow;
    if (combinedRow < historyLength) {
      return _ViewportLocation.history(combinedRow);
    }
    return _ViewportLocation.screen(combinedRow - historyLength);
  }

  void _setPrimaryOffset(int value) {
    final int next = value.clamp(0, _screens.scrollback.length);
    if (_primaryOffset == next) {
      return;
    }
    _primaryOffset = next;
    _generation++;
  }

  bool _jumpToPrompt({required bool previous}) {
    final int? target = _promptTargetOffset(previous: previous);
    if (target == null) return false;
    _setPrimaryOffset(target);
    return true;
  }

  int? _promptTargetOffset({required bool previous}) {
    _sync();
    if (_screens.usingAlternate) return null;
    final int historyLength = _screens.scrollback.length;
    final int current = _primaryOffset;
    if (previous) {
      final int before = current == 0
          ? historyLength + _screens.primary.cursorRow
          : historyLength - current;
      for (int row = before - 1; row >= 0; row--) {
        if (!_isPromptStart(row)) continue;
        final int target = (historyLength - row).clamp(0, historyLength);
        if (target != current) return target;
      }
      return null;
    }
    if (current == 0) return null;
    final int combinedRows = historyLength + _screens.primary.rows;
    for (int row = historyLength - current + 1; row < combinedRows; row++) {
      if (!_isPromptStart(row)) continue;
      final int target = (historyLength - row).clamp(0, historyLength);
      if (target != current) return target;
    }
    return null;
  }

  bool _isPromptStart(int row) {
    if (_combinedRowFlagsAt(TerminalScreenKind.primary, row) &
            TerminalRowFlags.prompt ==
        0) {
      return false;
    }
    if (row == 0 ||
        _combinedRowFlagsAt(TerminalScreenKind.primary, row - 1) &
                TerminalRowFlags.prompt ==
            0) {
      return true;
    }
    return !_combinedJoinsNext(TerminalScreenKind.primary, row - 1);
  }

  ({TerminalLogicalAnchor? anchor, bool atBottom})
  capturePrimaryReflowPosition() {
    _sync();
    if (_primaryOffset == 0) {
      return (anchor: null, atBottom: true);
    }
    final int combinedRow = _screens.scrollback.length - _primaryOffset;
    return (
      anchor: _anchorAtCombined(TerminalScreenKind.primary, combinedRow, 0),
      atBottom: false,
    );
  }

  void restorePrimaryReflowPosition(
    TerminalLogicalAnchor? anchor, {
    required bool wasAtBottom,
  }) {
    if (wasAtBottom || anchor == null) {
      _primaryOffset = 0;
      return;
    }
    final _CombinedPosition? position = _resolveCombined(anchor);
    if (position == null) {
      _primaryOffset = _screens.scrollback.length;
      return;
    }
    _primaryOffset = (_screens.scrollback.length - position.row).clamp(
      0,
      _screens.scrollback.length,
    );
  }

  TerminalLogicalAnchor _anchorAtCombined(
    TerminalScreenKind kind,
    int row,
    int column, {
    bool after = false,
    bool preserveTrailingCells = false,
  }) {
    final int columns = _combinedColumnsAt(kind, row);
    if (column < 0 || column >= columns) {
      throw RangeError.range(column, 0, columns - 1, 'column');
    }
    final int normalized =
        column > 0 &&
            (_combinedWidthFlagsAt(kind, row, column) &
                    TerminalCellFlags.widthMask) ==
                TerminalCellFlags.continuation
        ? column - 1
        : column;
    final int extent = _combinedRowExtent(kind, row);
    final int cellCount = _combinedLogicalCellCount(kind, row);
    int cellOffset = preserveTrailingCells || normalized < extent
        ? _combinedLogicalCellIndex(kind, row, normalized)
        : cellCount;
    if (after && normalized < extent) {
      cellOffset++;
    }
    return TerminalLogicalAnchor(
      screenKind: kind,
      logicalLineId: _combinedLogicalLineIdAt(kind, row),
      logicalLineEpoch: _combinedLogicalLineEpochAt(kind, row),
      cellOffset: _combinedLogicalOffsetAt(kind, row) + cellOffset,
    );
  }

  _CombinedPosition? _resolveCombined(
    TerminalLogicalAnchor anchor, {
    bool preserveTrailingCells = false,
  }) {
    final int rowCount = _combinedRowCount(anchor.screenKind);
    for (int row = 0; row < rowCount; row++) {
      if (_combinedLogicalLineIdAt(anchor.screenKind, row) !=
              anchor.logicalLineId ||
          _combinedLogicalLineEpochAt(anchor.screenKind, row) !=
              anchor.logicalLineEpoch) {
        continue;
      }
      final int base = _combinedLogicalOffsetAt(anchor.screenKind, row);
      if (anchor.cellOffset < base) {
        continue;
      }
      final int logicalCellCount = _combinedLogicalCellCount(
        anchor.screenKind,
        row,
      );
      final bool joinsNext = _combinedJoinsNext(anchor.screenKind, row);
      final int end = base + logicalCellCount;
      if (anchor.cellOffset > end) {
        if (joinsNext) {
          continue;
        }
        if (preserveTrailingCells) {
          final int gridCellCount = _combinedLogicalCellIndex(
            anchor.screenKind,
            row,
            _combinedColumnsAt(anchor.screenKind, row),
          );
          final int targetCell = anchor.cellOffset - base;
          if (targetCell >= 0 && targetCell < gridCellCount) {
            return _CombinedPosition(
              row,
              _combinedColumnForLogicalCell(anchor.screenKind, row, targetCell),
            );
          }
        }
        return null;
      }
      if (anchor.cellOffset == end && joinsNext) {
        continue;
      }
      final int logicalCell = (anchor.cellOffset - base).clamp(
        0,
        logicalCellCount == 0 ? 0 : logicalCellCount - 1,
      );
      return _CombinedPosition(
        row,
        _combinedColumnForLogicalCell(anchor.screenKind, row, logicalCell),
      );
    }
    return null;
  }

  int _combinedRowCount(TerminalScreenKind kind) =>
      kind == TerminalScreenKind.primary
      ? _screens.scrollback.length + _screens.primary.rows
      : _screens.alternate.rows;

  int _combinedColumnsAt(TerminalScreenKind kind, int row) {
    final int rowCount = _combinedRowCount(kind);
    if (row < 0 || row >= rowCount) {
      throw RangeError.range(row, 0, rowCount - 1, 'row');
    }
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.columnsAt(row);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.columns
        : _screens.alternate.columns;
  }

  int _combinedRowFlagsAt(TerminalScreenKind kind, int row) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.rowFlagsAt(row);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.rowFlagsAt(row - _screens.scrollback.length)
        : _screens.alternate.rowFlagsAt(row);
  }

  int _combinedLogicalLineIdAt(TerminalScreenKind kind, int row) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.logicalLineIdAt(row);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.logicalLineIdAt(row - _screens.scrollback.length)
        : _screens.alternate.logicalLineIdAt(row);
  }

  int _combinedLogicalLineEpochAt(TerminalScreenKind kind, int row) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.logicalLineEpochAt(row);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.logicalLineEpochAt(row - _screens.scrollback.length)
        : _screens.alternate.logicalLineEpochAt(row);
  }

  int _combinedWidthFlagsAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.widthFlagsAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.widthFlagsAt(
            row - _screens.scrollback.length,
            column,
          )
        : _screens.alternate.widthFlagsAt(row, column);
  }

  int _combinedLogicalOffsetAt(TerminalScreenKind kind, int row) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.logicalCellOffsetAt(row);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.logicalCellOffsetAt(row - _screens.scrollback.length)
        : _screens.alternate.logicalCellOffsetAt(row);
  }

  int _combinedRowExtent(TerminalScreenKind kind, int row) {
    final int columns = _combinedColumnsAt(kind, row);
    int extent = 0;
    for (int column = 0; column < columns; column++) {
      if (_combinedContentAt(kind, row, column) != 0 ||
          _combinedForegroundAt(kind, row, column) != 0 ||
          _combinedBackgroundAt(kind, row, column) != 0 ||
          _combinedStyleAt(kind, row, column) != 0 ||
          _combinedHyperlinkAt(kind, row, column) != 0 ||
          _combinedWidthFlagsAt(kind, row, column) !=
              TerminalCellFlags.narrow) {
        extent = column + 1;
      }
    }
    if (!(kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length)) {
      final TerminalScreen screen = kind == TerminalScreenKind.primary
          ? _screens.primary
          : _screens.alternate;
      final int screenRow = kind == TerminalScreenKind.primary
          ? row - _screens.scrollback.length
          : row;
      if (screen.cursorRow == screenRow && screen.cursorColumn + 1 > extent) {
        extent = screen.cursorColumn + 1;
      }
      if (screen.savedCursorRow == screenRow &&
          screen.savedCursorColumn + 1 > extent) {
        extent = screen.savedCursorColumn + 1;
      }
    }
    return extent;
  }

  int _combinedLogicalCellCount(TerminalScreenKind kind, int row) {
    final int extent = _combinedRowExtent(kind, row);
    int count = 0;
    for (int column = 0; column < extent; column++) {
      if ((_combinedWidthFlagsAt(kind, row, column) &
              TerminalCellFlags.widthMask) !=
          TerminalCellFlags.continuation) {
        count++;
      }
    }
    return count;
  }

  int _combinedLogicalCellIndex(
    TerminalScreenKind kind,
    int row,
    int targetColumn,
  ) {
    int logicalCell = 0;
    for (int column = 0; column < targetColumn; column++) {
      if ((_combinedWidthFlagsAt(kind, row, column) &
              TerminalCellFlags.widthMask) !=
          TerminalCellFlags.continuation) {
        logicalCell++;
      }
    }
    return logicalCell;
  }

  int _combinedColumnForLogicalCell(
    TerminalScreenKind kind,
    int row,
    int targetCell,
  ) {
    final int columns = _combinedColumnsAt(kind, row);
    int logicalCell = 0;
    for (int column = 0; column < columns; column++) {
      if ((_combinedWidthFlagsAt(kind, row, column) &
              TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
        continue;
      }
      if (logicalCell == targetCell) {
        return column;
      }
      logicalCell++;
    }
    return 0;
  }

  bool _combinedJoinsNext(TerminalScreenKind kind, int row) =>
      row + 1 < _combinedRowCount(kind) &&
      _combinedRowFlagsAt(kind, row) & TerminalRowFlags.softWrapped != 0 &&
      _combinedLogicalLineIdAt(kind, row + 1) ==
          _combinedLogicalLineIdAt(kind, row) &&
      _combinedLogicalLineEpochAt(kind, row + 1) ==
          _combinedLogicalLineEpochAt(kind, row);

  int _combinedContentAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.contentAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.contentAt(row - _screens.scrollback.length, column)
        : _screens.alternate.contentAt(row, column);
  }

  int _combinedForegroundAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.foregroundAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.foregroundAt(
            row - _screens.scrollback.length,
            column,
          )
        : _screens.alternate.foregroundAt(row, column);
  }

  int _combinedBackgroundAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.backgroundAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.backgroundAt(
            row - _screens.scrollback.length,
            column,
          )
        : _screens.alternate.backgroundAt(row, column);
  }

  int _combinedStyleAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.styleAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.styleAt(row - _screens.scrollback.length, column)
        : _screens.alternate.styleAt(row, column);
  }

  int _combinedHyperlinkAt(TerminalScreenKind kind, int row, int column) {
    if (kind == TerminalScreenKind.primary &&
        row < _screens.scrollback.length) {
      return _screens.scrollback.hyperlinkAt(row, column);
    }
    return kind == TerminalScreenKind.primary
        ? _screens.primary.hyperlinkAt(row - _screens.scrollback.length, column)
        : _screens.alternate.hyperlinkAt(row, column);
  }

  void _sync() {
    final TerminalScrollback history = _screens.scrollback;
    final int appended = history.totalRowsAppended - _seenRowsAppended;
    bool offsetChanged = false;
    if (history.continuityGeneration != _seenContinuityGeneration) {
      offsetChanged = _primaryOffset != 0;
      _primaryOffset = 0;
    } else if (_primaryOffset > 0 && appended > 0) {
      final int next = (_primaryOffset + appended).clamp(0, history.length);
      offsetChanged = next != _primaryOffset;
      _primaryOffset = next;
    } else if (_primaryOffset > history.length) {
      _primaryOffset = history.length;
      offsetChanged = true;
    }

    final bool usingAlternate = _screens.usingAlternate;
    final bool historyChanged = history.generation != _seenHistoryGeneration;
    final bool primaryChanged =
        _screens.primary.generation != _seenPrimaryGeneration;
    final bool alternateChanged =
        _screens.alternate.generation != _seenAlternateGeneration;
    final bool transitionChanged =
        _screens.transitionGeneration != _seenTransitionGeneration;
    if (transitionChanged ||
        (usingAlternate ? alternateChanged : primaryChanged) ||
        (!usingAlternate && (historyChanged || offsetChanged))) {
      _generation++;
    }

    _seenHistoryGeneration = history.generation;
    _seenRowsAppended = history.totalRowsAppended;
    _seenContinuityGeneration = history.continuityGeneration;
    _seenPrimaryGeneration = _screens.primary.generation;
    _seenAlternateGeneration = _screens.alternate.generation;
    _seenTransitionGeneration = _screens.transitionGeneration;
  }
}

final class _ViewportLocation {
  const _ViewportLocation.history(this.row) : history = true;
  const _ViewportLocation.screen(this.row) : history = false;

  final bool history;
  final int row;
}

final class _CombinedPosition {
  const _CombinedPosition(this.row, this.column);

  final int row;
  final int column;
}
