part of 'terminal_screen.dart';

final class _ReflowCell {
  const _ReflowCell({
    required this.content,
    required this.foreground,
    required this.background,
    required this.style,
    required this.hyperlink,
    required this.flags,
    required this.activeCursor,
    required this.savedCursor,
    this.replacement = false,
  });

  final int content;
  final int foreground;
  final int background;
  final int style;
  final int hyperlink;
  final int flags;
  final bool activeCursor;
  final bool savedCursor;
  final bool replacement;

  int get width => replacement
      ? 1
      : (flags & TerminalCellFlags.widthMask) == TerminalCellFlags.wide
      ? 2
      : 1;

  _ReflowCell asReplacement() => _ReflowCell(
    content: 0xfffd,
    foreground: foreground,
    background: background,
    style: style,
    hyperlink: hyperlink,
    flags: TerminalCellFlags.narrow | (flags & TerminalCellFlags.protected),
    activeCursor: activeCursor,
    savedCursor: savedCursor,
    replacement: true,
  );
}

final class _ReflowLine {
  _ReflowLine(this.logicalLineId, this.logicalLineEpoch, this.logicalOffset);

  final int logicalLineId;
  final int logicalLineEpoch;
  final int logicalOffset;
  final List<_ReflowCell> cells = <_ReflowCell>[];
  int semanticFlags = 0;
  bool hardBreak = false;
  bool continuesBeyondVisible = false;
}

final class _ReflowRow {
  _ReflowRow({
    required this.logicalLineId,
    required this.logicalLineEpoch,
    required this.logicalOffset,
    required this.flags,
    required this.cells,
  });

  final int logicalLineId;
  final int logicalLineEpoch;
  final int logicalOffset;
  final int flags;
  final List<_ReflowCell> cells;
}

final class _MappedPosition {
  const _MappedPosition(this.row, this.column, {this.atRightEdge = false});

  final int row;
  final int column;
  final bool atRightEdge;
}

final class _ReflowPositions {
  const _ReflowPositions(this.active, this.saved);

  final _MappedPosition? active;
  final _MappedPosition? saved;
}

final class _ReflowSource {
  const _ReflowSource(this.screen, [this.history]);

  final TerminalScreen screen;
  final TerminalScrollback? history;

  int get rowCount => (history?.length ?? 0) + screen.rows;

  int columnsAt(int row) =>
      _isHistoryRow(row) ? history!.columnsAt(row) : screen.columns;

  int rowFlagsAt(int row) => _isHistoryRow(row)
      ? history!.rowFlagsAt(row)
      : screen.rowFlagsAt(_screenRow(row));

  int logicalLineIdAt(int row) => _isHistoryRow(row)
      ? history!.logicalLineIdAt(row)
      : screen.logicalLineIdAt(_screenRow(row));

  int logicalLineEpochAt(int row) => _isHistoryRow(row)
      ? history!.logicalLineEpochAt(row)
      : screen.logicalLineEpochAt(_screenRow(row));

  int contentAt(int row, int column) => _isHistoryRow(row)
      ? history!.contentAt(row, column)
      : screen.contentAt(_screenRow(row), column);

  int foregroundAt(int row, int column) => _isHistoryRow(row)
      ? history!.foregroundAt(row, column)
      : screen.foregroundAt(_screenRow(row), column);

  int backgroundAt(int row, int column) => _isHistoryRow(row)
      ? history!.backgroundAt(row, column)
      : screen.backgroundAt(_screenRow(row), column);

  int styleAt(int row, int column) => _isHistoryRow(row)
      ? history!.styleAt(row, column)
      : screen.styleAt(_screenRow(row), column);

  int hyperlinkAt(int row, int column) => _isHistoryRow(row)
      ? history!.hyperlinkAt(row, column)
      : screen.hyperlinkAt(_screenRow(row), column);

  int widthFlagsAt(int row, int column) => _isHistoryRow(row)
      ? history!.widthFlagsAt(row, column)
      : screen.widthFlagsAt(_screenRow(row), column);

  int activeCursorColumnAt(int row) {
    final int screenRow = _screenRowOrNegative(row);
    return screenRow == screen._cursorRow ? screen._cursorColumn : -1;
  }

  int savedCursorColumnAt(int row) {
    final int screenRow = _screenRowOrNegative(row);
    return screenRow == screen._savedCursorRow ? screen._savedCursorColumn : -1;
  }

  int logicalCellOffsetAt(int row) {
    return _isHistoryRow(row)
        ? history!.logicalCellOffsetAt(row)
        : screen.logicalCellOffsetAt(_screenRow(row));
  }

  bool _isHistoryRow(int row) => row < (history?.length ?? 0);

  int _screenRow(int row) => row - (history?.length ?? 0);

  int _screenRowOrNegative(int row) =>
      _isHistoryRow(row) ? -1 : _screenRow(row);
}

/// Package-internal transaction built before a screen set publishes resize.
final class TerminalScreenHistoryResizeResult {
  TerminalScreenHistoryResizeResult._(
    this.screen,
    this._history,
    this._replacement,
  );

  final TerminalScreen screen;
  final TerminalScrollback _history;
  final TerminalScrollback _replacement;
  bool _committed = false;

  void commitHistory() {
    if (_committed) {
      throw StateError('history resize result was already committed');
    }
    _history._replacePagesFrom(_replacement);
    _committed = true;
  }
}

TerminalScreen _resizeTerminalScreen(
  TerminalScreen source, {
  required int rows,
  required int columns,
}) {
  TerminalScreen._validateDimensions(rows, columns);
  source.validateCellTopology();
  final List<_ReflowLine> lines = _extractReflowLines(_ReflowSource(source));
  final List<_ReflowRow> reflowed = _wrapReflowLines(lines, columns);
  final _ReflowPositions positions = _findReflowPositions(reflowed, columns);
  final int windowStart = _reflowWindowStart(
    reflowed.length,
    rows,
    positions.active?.row,
  );
  return _buildReflowedScreen(
    source,
    reflowed,
    positions,
    windowStart: windowStart,
    rows: rows,
    columns: columns,
  );
}

TerminalScreenHistoryResizeResult resizeTerminalScreenWithHistory(
  TerminalScreen source,
  TerminalScrollback history, {
  required int rows,
  required int columns,
}) {
  TerminalScreen._validateDimensions(rows, columns);
  source.validateCellTopology();
  history.validateCellTopology();
  final List<_ReflowLine> lines = _extractReflowLines(
    _ReflowSource(source, history),
  );
  final List<_ReflowRow> reflowed = _wrapReflowLines(lines, columns);
  final _ReflowPositions positions = _findReflowPositions(reflowed, columns);
  final int windowStart = _reflowWindowStart(
    reflowed.length,
    rows,
    positions.active?.row,
  );
  final TerminalScrollback replacement = TerminalScrollback(
    maxLines: history.maxLines,
    maxBytes: history.maxBytes,
    pageRows: history.pageRows,
  );
  for (int row = 0; row < windowStart; row++) {
    replacement._appendReflowRow(reflowed[row], columns);
  }
  replacement.validateCellTopology();
  final TerminalScreen target = _buildReflowedScreen(
    source,
    reflowed,
    positions,
    windowStart: windowStart,
    rows: rows,
    columns: columns,
  );
  return TerminalScreenHistoryResizeResult._(target, history, replacement);
}

_ReflowPositions _findReflowPositions(List<_ReflowRow> reflowed, int columns) {
  _MappedPosition? active;
  _MappedPosition? saved;
  for (int row = 0; row < reflowed.length; row++) {
    int column = 0;
    for (final _ReflowCell cell in reflowed[row].cells) {
      if (cell.activeCursor) {
        active = _MappedPosition(
          row,
          column,
          atRightEdge: column + cell.width == columns,
        );
      }
      if (cell.savedCursor) {
        saved = _MappedPosition(row, column);
      }
      column += cell.width;
    }
  }
  return _ReflowPositions(active, saved);
}

TerminalScreen _buildReflowedScreen(
  TerminalScreen source,
  List<_ReflowRow> reflowed,
  _ReflowPositions positions, {
  required int windowStart,
  required int rows,
  required int columns,
}) {
  final int retainedCount = (reflowed.length - windowStart).clamp(0, rows);
  final TerminalScreen target = TerminalScreen._(
    rows: rows,
    columns: columns,
    styleTable: source.styleTable,
    palette: source.palette,
    graphemeTable: source.graphemeTable,
    hyperlinkTable: source.hyperlinkTable,
    scrollbackAttachment: source._scrollbackAttachment,
    initialCursorShape: source.initialCursorShape,
    initialCursorBlinking: source.initialCursorBlinking,
  );
  target._logicalLineEpoch = source._logicalLineEpoch;
  target._firstLogicalCellOffset = retainedCount == 0
      ? 0
      : reflowed[windowStart].logicalOffset;

  int nextLogicalLineId = source._nextLogicalLineId;
  var needsLogicalLineRenumber = false;
  for (int targetRow = 0; targetRow < retainedCount; targetRow++) {
    final _ReflowRow input = reflowed[windowStart + targetRow];
    target._logicalLineIds[targetRow] = input.logicalLineId;
    target._logicalLineEpochs[targetRow] = input.logicalLineEpoch;
    target._rowFlags[targetRow] = input.flags;
    int targetColumn = 0;
    for (final _ReflowCell cell in input.cells) {
      _writeReflowCell(target, targetRow, targetColumn, cell);
      targetColumn += cell.width;
    }
  }
  for (int targetRow = retainedCount; targetRow < rows; targetRow++) {
    if (nextLogicalLineId > TerminalScreen.maxLogicalLineId) {
      needsLogicalLineRenumber = true;
      break;
    }
    target._logicalLineIds[targetRow] = nextLogicalLineId++;
    target._logicalLineEpochs[targetRow] = target._logicalLineEpoch;
  }
  if (needsLogicalLineRenumber) {
    nextLogicalLineId = _renumberLogicalLines(target);
  }
  target._nextLogicalLineId = nextLogicalLineId;

  final _MappedPosition mappedActive = _positionInWindow(
    positions.active,
    windowStart,
    rows,
    columns,
  );
  final _MappedPosition mappedSaved = _positionInWindow(
    positions.saved,
    windowStart,
    rows,
    columns,
  );
  target._cursorRow = mappedActive.row;
  target._cursorColumn = _normalizeCursorColumn(
    target,
    mappedActive.row,
    mappedActive.column,
  );
  target._savedCursorRow = mappedSaved.row;
  target._savedCursorColumn = _normalizeCursorColumn(
    target,
    mappedSaved.row,
    mappedSaved.column,
  );
  target._wrapPending =
      source._wrapPending && mappedActive.atRightEdge && source._autoWrapMode;

  target._currentForeground = source._currentForeground;
  target._currentBackground = source._currentBackground;
  target._currentStyleId = source._currentStyleId;
  target._currentCellProtected = source._currentCellProtected;
  target._savedForeground = source._savedForeground;
  target._savedBackground = source._savedBackground;
  target._savedStyleId = source._savedStyleId;
  target._savedCellProtected = source._savedCellProtected;
  target._g0CharacterSet = source._g0CharacterSet;
  target._g1CharacterSet = source._g1CharacterSet;
  target._glCharacterSetSlot = source._glCharacterSetSlot;
  target._savedG0CharacterSet = source._savedG0CharacterSet;
  target._savedG1CharacterSet = source._savedG1CharacterSet;
  target._savedGlCharacterSetSlot = source._savedGlCharacterSetSlot;
  target._insertMode = source._insertMode;
  target._autoWrapMode = source._autoWrapMode;
  target._reverseVideoMode = source._reverseVideoMode;
  target._cursorVisible = source._cursorVisible;
  target._cursorBlinking = source._cursorBlinking;
  target._cursorShape = source._cursorShape;
  target._visualBellGeneration = source._visualBellGeneration;

  final int sharedColumns = source.columns < columns ? source.columns : columns;
  target._tabStops.setRange(0, sharedColumns, source._tabStops);
  target._topMargin = 0;
  target._bottomMargin = rows - 1;
  target._leftMargin = 0;
  target._rightMargin = columns - 1;
  target._originMode = false;
  target._horizontalMarginsMode = false;
  target.breakGraphemeSequence();
  target._generation = source._generation + 1;
  target._markEveryRowDirty();
  target.validateCellTopology();
  return target;
}

List<_ReflowLine> _extractReflowLines(_ReflowSource source) {
  final List<_ReflowLine> lines = <_ReflowLine>[];
  int row = 0;
  while (row < source.rowCount) {
    final _ReflowLine line = _ReflowLine(
      source.logicalLineIdAt(row),
      source.logicalLineEpochAt(row),
      source.logicalCellOffsetAt(row),
    );
    while (true) {
      final int flags = source.rowFlagsAt(row);
      line.semanticFlags |=
          flags &
          (TerminalRowFlags.prompt |
              TerminalRowFlags.command |
              TerminalRowFlags.output);
      line.hardBreak = flags & TerminalRowFlags.hardBreak != 0;
      final int extent = _reflowRowExtent(source, row);
      final int sourceActiveColumn = source.activeCursorColumnAt(row);
      final int sourceSavedColumn = source.savedCursorColumnAt(row);
      final int activeColumn = sourceActiveColumn >= 0
          ? _normalizeSourceColumn(source, row, sourceActiveColumn)
          : -1;
      final int savedColumn = sourceSavedColumn >= 0
          ? _normalizeSourceColumn(source, row, sourceSavedColumn)
          : -1;
      for (int column = 0; column < extent; column++) {
        final int cellFlags = source.widthFlagsAt(row, column);
        if ((cellFlags & TerminalCellFlags.widthMask) ==
            TerminalCellFlags.continuation) {
          continue;
        }
        line.cells.add(
          _ReflowCell(
            content: source.contentAt(row, column),
            foreground: source.foregroundAt(row, column),
            background: source.backgroundAt(row, column),
            style: source.styleAt(row, column),
            hyperlink: source.hyperlinkAt(row, column),
            flags: cellFlags,
            activeCursor: activeColumn == column,
            savedCursor: savedColumn == column,
          ),
        );
      }
      final bool softWrapped = flags & TerminalRowFlags.softWrapped != 0;
      final bool joinsNext =
          softWrapped &&
          row + 1 < source.rowCount &&
          source.logicalLineIdAt(row + 1) == line.logicalLineId &&
          source.logicalLineEpochAt(row + 1) == line.logicalLineEpoch;
      if (!joinsNext) {
        line.continuesBeyondVisible = softWrapped;
        break;
      }
      row++;
    }
    lines.add(line);
    row++;
  }
  return lines;
}

int _reflowRowExtent(_ReflowSource screen, int row) {
  if (screen._isHistoryRow(row)) {
    return screen.history!._reflowRowExtentAt(row);
  }
  int extent = 0;
  for (int column = 0; column < screen.columnsAt(row); column++) {
    if (!_isCanonicalBlank(screen, row, column)) {
      extent = column + 1;
    }
  }
  final int activeColumn = screen.activeCursorColumnAt(row);
  if (activeColumn >= 0 && activeColumn + 1 > extent) {
    extent = activeColumn + 1;
  }
  final int savedColumn = screen.savedCursorColumnAt(row);
  if (savedColumn >= 0 && savedColumn + 1 > extent) {
    extent = savedColumn + 1;
  }
  return extent;
}

int _reflowLogicalCellCount(_ReflowSource screen, int row) {
  final int extent = _reflowRowExtent(screen, row);
  int count = 0;
  for (int column = 0; column < extent; column++) {
    if ((screen.widthFlagsAt(row, column) & TerminalCellFlags.widthMask) !=
        TerminalCellFlags.continuation) {
      count++;
    }
  }
  return count;
}

bool _isCanonicalBlank(_ReflowSource screen, int row, int column) =>
    screen.contentAt(row, column) == 0 &&
    screen.foregroundAt(row, column) == 0 &&
    screen.backgroundAt(row, column) == 0 &&
    screen.styleAt(row, column) == 0 &&
    screen.hyperlinkAt(row, column) == 0 &&
    screen.widthFlagsAt(row, column) == TerminalCellFlags.narrow;

int _normalizeSourceColumn(_ReflowSource screen, int row, int column) {
  if (column > 0 &&
      (screen.widthFlagsAt(row, column) & TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
    return column - 1;
  }
  return column;
}

List<_ReflowRow> _wrapReflowLines(List<_ReflowLine> lines, int columns) {
  final List<_ReflowRow> result = <_ReflowRow>[];
  for (final _ReflowLine line in lines) {
    final List<List<_ReflowCell>> rows = <List<_ReflowCell>>[];
    var current = <_ReflowCell>[];
    var used = 0;
    for (final _ReflowCell sourceCell in line.cells) {
      final _ReflowCell cell = sourceCell.width > columns
          ? sourceCell.asReplacement()
          : sourceCell;
      if (used != 0 && used + cell.width > columns) {
        rows.add(current);
        current = <_ReflowCell>[];
        used = 0;
      }
      current.add(cell);
      used += cell.width;
      if (used == columns) {
        rows.add(current);
        current = <_ReflowCell>[];
        used = 0;
      }
    }
    if (current.isNotEmpty || rows.isEmpty) {
      rows.add(current);
    }
    int logicalOffset = line.logicalOffset;
    for (int row = 0; row < rows.length; row++) {
      final bool finalRow = row == rows.length - 1;
      int flags = line.semanticFlags;
      if (!finalRow || line.continuesBeyondVisible) {
        flags |= TerminalRowFlags.softWrapped;
      } else if (line.hardBreak) {
        flags |= TerminalRowFlags.hardBreak;
      }
      result.add(
        _ReflowRow(
          logicalLineId: line.logicalLineId,
          logicalLineEpoch: line.logicalLineEpoch,
          logicalOffset: logicalOffset,
          flags: flags,
          cells: rows[row],
        ),
      );
      logicalOffset += rows[row].length;
    }
  }
  return result;
}

void _writeReflowCell(
  TerminalScreen screen,
  int row,
  int column,
  _ReflowCell cell,
) {
  final int index = row * screen.columns + column;
  final int width = cell.width;
  final int leadFlags =
      (width == 2 ? TerminalCellFlags.wide : TerminalCellFlags.narrow) |
      (cell.replacement ? 0 : cell.flags & TerminalCellFlags.grapheme) |
      (cell.flags & TerminalCellFlags.protected);
  screen._content[index] = cell.content;
  screen._foreground[index] = cell.foreground;
  screen._background[index] = cell.background;
  screen._styles[index] = cell.style;
  screen._hyperlinks[index] = cell.hyperlink;
  screen._widthFlags[index] = leadFlags;
  if (width == 2) {
    final int continuation = index + 1;
    screen._content[continuation] = 0;
    screen._foreground[continuation] = cell.foreground;
    screen._background[continuation] = cell.background;
    screen._styles[continuation] = cell.style;
    screen._hyperlinks[continuation] = cell.hyperlink;
    screen._widthFlags[continuation] =
        TerminalCellFlags.continuation |
        (cell.flags & TerminalCellFlags.protected);
  }
}

int _reflowWindowStart(int totalRows, int capacity, int? activeRow) {
  int start = totalRows > capacity ? totalRows - capacity : 0;
  if (activeRow == null) {
    return start;
  }
  if (activeRow < start) {
    start = activeRow;
  } else if (activeRow >= start + capacity) {
    start = activeRow - capacity + 1;
  }
  return start.clamp(0, totalRows > capacity ? totalRows - capacity : 0);
}

_MappedPosition _positionInWindow(
  _MappedPosition? position,
  int windowStart,
  int rows,
  int columns,
) {
  if (position == null) {
    return const _MappedPosition(0, 0);
  }
  final int row = (position.row - windowStart).clamp(0, rows - 1);
  return _MappedPosition(
    row,
    position.column.clamp(0, columns - 1),
    atRightEdge:
        position.row >= windowStart &&
        position.row < windowStart + rows &&
        position.atRightEdge,
  );
}

int _normalizeCursorColumn(TerminalScreen screen, int row, int column) {
  if (column > 0 &&
      (screen.widthFlagsAt(row, column) & TerminalCellFlags.widthMask) ==
          TerminalCellFlags.continuation) {
    return column - 1;
  }
  return column;
}

int _renumberLogicalLines(TerminalScreen screen) {
  screen._advanceLogicalLineEpoch();
  screen._firstLogicalCellOffset = 0;
  var next = 1;
  for (int row = 0; row < screen.rows; row++) {
    if (row == 0 ||
        screen._rowFlags[row - 1] & TerminalRowFlags.softWrapped == 0) {
      if (next > TerminalScreen.maxLogicalLineId) {
        throw StateError('visible logical-line ID capacity exhausted');
      }
      next++;
    }
    screen._logicalLineIds[row] = next - 1;
    screen._logicalLineEpochs[row] = screen._logicalLineEpoch;
  }
  return next;
}
