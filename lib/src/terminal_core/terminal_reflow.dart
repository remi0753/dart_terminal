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
  _ReflowLine(this.logicalLineId);

  final int logicalLineId;
  final List<_ReflowCell> cells = <_ReflowCell>[];
  int semanticFlags = 0;
  bool hardBreak = false;
  bool continuesBeyondVisible = false;
}

final class _ReflowRow {
  _ReflowRow({
    required this.logicalLineId,
    required this.flags,
    required this.cells,
  });

  final int logicalLineId;
  final int flags;
  final List<_ReflowCell> cells;
}

final class _MappedPosition {
  const _MappedPosition(this.row, this.column, {this.atRightEdge = false});

  final int row;
  final int column;
  final bool atRightEdge;
}

TerminalScreen _resizeTerminalScreen(
  TerminalScreen source, {
  required int rows,
  required int columns,
}) {
  TerminalScreen._validateDimensions(rows, columns);
  source.validateCellTopology();
  final List<_ReflowLine> lines = _extractReflowLines(source);
  final List<_ReflowRow> reflowed = _wrapReflowLines(lines, columns);
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

  final int windowStart = _reflowWindowStart(
    reflowed.length,
    rows,
    active?.row,
  );
  final int retainedCount = (reflowed.length - windowStart).clamp(0, rows);
  final TerminalScreen target = TerminalScreen(
    rows: rows,
    columns: columns,
    styleTable: source.styleTable,
    palette: source.palette,
    graphemeTable: source.graphemeTable,
  );

  int nextLogicalLineId = source._nextLogicalLineId;
  var needsLogicalLineRenumber = false;
  for (int targetRow = 0; targetRow < retainedCount; targetRow++) {
    final _ReflowRow input = reflowed[windowStart + targetRow];
    target._logicalLineIds[targetRow] = input.logicalLineId;
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
  }
  if (needsLogicalLineRenumber) {
    nextLogicalLineId = _renumberLogicalLines(target);
  }
  target._nextLogicalLineId = nextLogicalLineId;

  final _MappedPosition mappedActive = _positionInWindow(
    active,
    windowStart,
    rows,
    columns,
  );
  final _MappedPosition mappedSaved = _positionInWindow(
    saved,
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
  target._savedForeground = source._savedForeground;
  target._savedBackground = source._savedBackground;
  target._savedStyleId = source._savedStyleId;
  target._insertMode = source._insertMode;
  target._autoWrapMode = source._autoWrapMode;
  target._reverseVideoMode = source._reverseVideoMode;
  target._cursorVisible = source._cursorVisible;
  target._cursorBlinking = source._cursorBlinking;
  target._cursorShape = source._cursorShape;

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
  target._fullSnapshotRequired = true;
  target._markEveryRowDirty();
  target.validateCellTopology();
  return target;
}

List<_ReflowLine> _extractReflowLines(TerminalScreen source) {
  final List<_ReflowLine> lines = <_ReflowLine>[];
  int row = 0;
  while (row < source.rows) {
    final _ReflowLine line = _ReflowLine(source.logicalLineIdAt(row));
    while (true) {
      final int flags = source.rowFlagsAt(row);
      line.semanticFlags |=
          flags &
          (TerminalRowFlags.prompt |
              TerminalRowFlags.command |
              TerminalRowFlags.output);
      line.hardBreak = flags & TerminalRowFlags.hardBreak != 0;
      final int extent = _reflowRowExtent(source, row);
      final int activeColumn = source._cursorRow == row
          ? _normalizeSourceColumn(source, row, source._cursorColumn)
          : -1;
      final int savedColumn = source._savedCursorRow == row
          ? _normalizeSourceColumn(source, row, source._savedCursorColumn)
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
          row + 1 < source.rows &&
          source.logicalLineIdAt(row + 1) == line.logicalLineId;
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

int _reflowRowExtent(TerminalScreen screen, int row) {
  int extent = 0;
  for (int column = 0; column < screen.columns; column++) {
    if (!_isCanonicalBlank(screen, row, column)) {
      extent = column + 1;
    }
  }
  if (screen._cursorRow == row && screen._cursorColumn + 1 > extent) {
    extent = screen._cursorColumn + 1;
  }
  if (screen._savedCursorRow == row && screen._savedCursorColumn + 1 > extent) {
    extent = screen._savedCursorColumn + 1;
  }
  return extent;
}

bool _isCanonicalBlank(TerminalScreen screen, int row, int column) =>
    screen.contentAt(row, column) == 0 &&
    screen.foregroundAt(row, column) == 0 &&
    screen.backgroundAt(row, column) == 0 &&
    screen.styleAt(row, column) == 0 &&
    screen.hyperlinkAt(row, column) == 0 &&
    screen.widthFlagsAt(row, column) == TerminalCellFlags.narrow;

int _normalizeSourceColumn(TerminalScreen screen, int row, int column) {
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
          flags: flags,
          cells: rows[row],
        ),
      );
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
  }
  return next;
}
