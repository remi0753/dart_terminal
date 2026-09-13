part of 'terminal_screen.dart';

/// Package-internal staged cell used by the text snapshot restore oracle.
final class TerminalSnapshotCellState {
  const TerminalSnapshotCellState({
    required this.row,
    required this.column,
    required this.content,
    required this.foreground,
    required this.background,
    required this.style,
    required this.hyperlink,
    required this.flags,
  });

  final int row;
  final int column;
  final int content;
  final int foreground;
  final int background;
  final int style;
  final int hyperlink;
  final int flags;
}

/// Package-internal staged row used by the text snapshot restore oracle.
final class TerminalSnapshotRowState {
  const TerminalSnapshotRowState({
    required this.columns,
    required this.flags,
    required this.logicalLineId,
    required this.logicalLineEpoch,
    required this.logicalCellOffset,
    required this.cells,
    this.logicalCellCount,
  });

  final int columns;
  final int flags;
  final int logicalLineId;
  final int logicalLineEpoch;
  final int logicalCellOffset;
  final int? logicalCellCount;
  final List<TerminalSnapshotCellState> cells;
}

/// Package-internal complete screen state staged before a fresh owner is built.
final class TerminalSnapshotScreenState {
  const TerminalSnapshotScreenState({
    required this.rows,
    required this.columns,
    required this.cursorRow,
    required this.cursorColumn,
    required this.savedCursorRow,
    required this.savedCursorColumn,
    required this.currentForeground,
    required this.currentBackground,
    required this.currentStyle,
    required this.currentProtected,
    required this.savedForeground,
    required this.savedBackground,
    required this.savedStyle,
    required this.savedProtected,
    required this.g0,
    required this.g1,
    required this.gl,
    required this.savedG0,
    required this.savedG1,
    required this.savedGl,
    required this.topMargin,
    required this.bottomMargin,
    required this.leftMargin,
    required this.rightMargin,
    required this.modes,
    required this.cursorShape,
    required this.cursorVisible,
    required this.cursorBlinking,
    required this.wrapPending,
    required this.tabStops,
    required this.rowStates,
  });

  final int rows;
  final int columns;
  final int cursorRow;
  final int cursorColumn;
  final int savedCursorRow;
  final int savedCursorColumn;
  final int currentForeground;
  final int currentBackground;
  final int currentStyle;
  final bool currentProtected;
  final int savedForeground;
  final int savedBackground;
  final int savedStyle;
  final bool savedProtected;
  final TerminalCharacterSet g0;
  final TerminalCharacterSet g1;
  final int gl;
  final TerminalCharacterSet savedG0;
  final TerminalCharacterSet savedG1;
  final int savedGl;
  final int topMargin;
  final int bottomMargin;
  final int leftMargin;
  final int rightMargin;
  final List<bool> modes;
  final TerminalCursorShape cursorShape;
  final bool cursorVisible;
  final bool cursorBlinking;
  final bool wrapPending;
  final List<int> tabStops;
  final List<TerminalSnapshotRowState> rowStates;
}

/// Applies already-staged state to one fresh screen without exposing partial
/// mutation to a caller. The parser owns syntax; this boundary owns packed-grid
/// and resource invariants.
void restoreTerminalScreenSnapshotState(
  TerminalScreen screen,
  TerminalSnapshotScreenState state,
) {
  if (screen.rows != state.rows ||
      screen.columns != state.columns ||
      state.rowStates.length != screen.rows) {
    throw StateError('snapshot screen dimensions differ');
  }
  if (state.modes.length != TerminalScreenMode.values.length) {
    throw StateError('snapshot screen mode count differs');
  }
  if (screen.rows == 1) {
    if (state.topMargin != 0 || state.bottomMargin != 0) {
      throw StateError('invalid single-row snapshot margins');
    }
  } else {
    TerminalScreen._validateMargins(
      state.topMargin,
      state.bottomMargin,
      screen.rows,
      'vertical',
    );
  }
  if (screen.columns == 1) {
    if (state.leftMargin != 0 || state.rightMargin != 0) {
      throw StateError('invalid single-column snapshot margins');
    }
  } else {
    TerminalScreen._validateMargins(
      state.leftMargin,
      state.rightMargin,
      screen.columns,
      'horizontal',
    );
  }
  screen._checkRow(state.cursorRow);
  screen._checkColumn(state.cursorColumn);
  screen._checkRow(state.savedCursorRow);
  screen._checkColumn(state.savedCursorColumn);
  TerminalScreen._validateColor(state.currentForeground, 'currentForeground');
  TerminalScreen._validateColor(state.currentBackground, 'currentBackground');
  TerminalScreen._validateColor(state.savedForeground, 'savedForeground');
  TerminalScreen._validateColor(state.savedBackground, 'savedBackground');
  _validateSnapshotStyle(screen.styleTable, state.currentStyle);
  _validateSnapshotStyle(screen.styleTable, state.savedStyle);
  RangeError.checkValueInInterval(state.gl, 0, 1, 'gl');
  RangeError.checkValueInInterval(state.savedGl, 0, 1, 'savedGl');
  if (state.wrapPending && !state.modes[TerminalScreenMode.autoWrap.index]) {
    throw StateError('snapshot wrap pending requires auto-wrap');
  }

  screen.breakGraphemeSequence();
  screen._firstPhysicalRow = 0;
  screen._content.fillRange(0, screen.cellCount, 0);
  screen._foreground.fillRange(0, screen.cellCount, 0);
  screen._background.fillRange(0, screen.cellCount, 0);
  screen._styles.fillRange(0, screen.cellCount, 0);
  screen._hyperlinks.fillRange(0, screen.cellCount, 0);
  screen._widthFlags.fillRange(0, screen.cellCount, TerminalCellFlags.narrow);
  final Uint8List occupied = Uint8List(screen.cellCount);
  var maximumEpoch = 1;
  var maximumIdAtEpoch = 0;
  for (var row = 0; row < state.rowStates.length; row++) {
    final TerminalSnapshotRowState rowState = state.rowStates[row];
    if (rowState.columns != screen.columns ||
        rowState.flags < 0 ||
        rowState.flags & ~TerminalRowFlags.knownMask != 0 ||
        rowState.logicalLineId <= 0 ||
        rowState.logicalLineId > TerminalScreen.maxLogicalLineId ||
        rowState.logicalLineEpoch <= 0 ||
        rowState.logicalLineEpoch > 0x7fffffffffffffff ||
        rowState.logicalCellOffset < 0 ||
        rowState.logicalCellOffset > 0x7fffffffffffffff) {
      throw StateError('invalid snapshot screen row');
    }
    screen._rowFlags[row] = rowState.flags;
    screen._logicalLineIds[row] = rowState.logicalLineId;
    screen._logicalLineEpochs[row] = rowState.logicalLineEpoch;
    if (rowState.logicalLineEpoch > maximumEpoch) {
      maximumEpoch = rowState.logicalLineEpoch;
      maximumIdAtEpoch = rowState.logicalLineId;
    } else if (rowState.logicalLineEpoch == maximumEpoch &&
        rowState.logicalLineId > maximumIdAtEpoch) {
      maximumIdAtEpoch = rowState.logicalLineId;
    }
    for (final TerminalSnapshotCellState cell in rowState.cells) {
      if (cell.row != row || cell.column < 0 || cell.column >= screen.columns) {
        throw StateError('invalid snapshot screen cell coordinate');
      }
      final int index = row * screen.columns + cell.column;
      if (occupied[index] != 0) {
        throw StateError('duplicate snapshot screen cell');
      }
      occupied[index] = 1;
      _validateSnapshotCell(
        cell,
        styles: screen.styleTable,
        graphemes: screen.graphemeTable,
        hyperlinks: screen.hyperlinkTable,
      );
      screen._content[index] = cell.content;
      screen._foreground[index] = cell.foreground;
      screen._background[index] = cell.background;
      screen._styles[index] = cell.style;
      screen._hyperlinks[index] = cell.hyperlink;
      screen._widthFlags[index] = cell.flags;
    }
  }
  screen._firstLogicalCellOffset = state.rowStates.first.logicalCellOffset;
  // A cursor or saved cursor beyond the last populated cell contributes to
  // the formatter-visible logical row extent. Install both before checking
  // offsets so validation uses the same state as the source snapshot.
  screen._cursorRow = state.cursorRow;
  screen._cursorColumn = state.cursorColumn;
  screen._savedCursorRow = state.savedCursorRow;
  screen._savedCursorColumn = state.savedCursorColumn;
  screen.validateCellTopology();
  for (var row = 0; row < state.rowStates.length; row++) {
    if (screen.logicalCellOffsetAt(row) !=
        state.rowStates[row].logicalCellOffset) {
      throw StateError('snapshot logical screen offsets are inconsistent');
    }
  }

  screen._currentForeground = state.currentForeground;
  screen._currentBackground = state.currentBackground;
  screen._currentStyleId = state.currentStyle;
  screen._currentCellProtected = state.currentProtected;
  screen._savedForeground = state.savedForeground;
  screen._savedBackground = state.savedBackground;
  screen._savedStyleId = state.savedStyle;
  screen._savedCellProtected = state.savedProtected;
  screen._g0CharacterSet = state.g0;
  screen._g1CharacterSet = state.g1;
  screen._glCharacterSetSlot = state.gl;
  screen._savedG0CharacterSet = state.savedG0;
  screen._savedG1CharacterSet = state.savedG1;
  screen._savedGlCharacterSetSlot = state.savedGl;
  screen._topMargin = state.topMargin;
  screen._bottomMargin = state.bottomMargin;
  screen._leftMargin = state.leftMargin;
  screen._rightMargin = state.rightMargin;
  screen._originMode = state.modes[TerminalScreenMode.origin.index];
  screen._insertMode = state.modes[TerminalScreenMode.insert.index];
  screen._autoWrapMode = state.modes[TerminalScreenMode.autoWrap.index];
  screen._reverseVideoMode = state.modes[TerminalScreenMode.reverseVideo.index];
  screen._horizontalMarginsMode =
      state.modes[TerminalScreenMode.horizontalMargins.index];
  screen._wrapPending = state.wrapPending;
  screen._cursorShape = state.cursorShape;
  screen._cursorVisible = state.cursorVisible;
  screen._cursorBlinking = state.cursorBlinking;
  screen._tabStops.fillRange(0, screen.columns, 0);
  for (final int column in state.tabStops) {
    screen._checkColumn(column);
    if (screen._tabStops[column] != 0) {
      throw StateError('duplicate snapshot tab stop');
    }
    screen._tabStops[column] = 1;
  }
  screen._logicalLineEpoch = maximumEpoch;
  screen._nextLogicalLineId = maximumIdAtEpoch + 1;
  screen._pendingScalarCount = 0;
  screen._lastPrintRow = -1;
  screen._lastPrintColumn = -1;
  screen._lastPrintGeneration = 0;
  screen._generation++;
  screen._dirtyStarts.fillRange(0, screen.rows, 0);
  screen._dirtyEnds.fillRange(0, screen.rows, screen.columns);
  screen._presentationDamageRequired = true;
  screen._fullSnapshotRequired = true;
}

/// Rebuilds bounded history pages from fully staged rows. One-row pages avoid
/// speculative capacity while preserving the formatter-visible state.
void restoreTerminalScrollbackSnapshotState(
  TerminalScrollback history,
  List<TerminalSnapshotRowState> rows,
  TerminalStyleTable styles,
  TerminalGraphemeTable graphemes,
  TerminalHyperlinkTable hyperlinks,
) {
  if (rows.length > history.maxLines) {
    throw StateError('snapshot history exceeds its line policy');
  }
  history._dropAllPages();
  var allocatedBytes = 0;
  for (var row = 0; row < rows.length; row++) {
    final TerminalSnapshotRowState rowState = rows[row];
    if (rowState.columns <= 0 ||
        rowState.columns > TerminalScreen.maxColumns ||
        rowState.flags < 0 ||
        rowState.flags & ~TerminalRowFlags.knownMask != 0 ||
        rowState.logicalLineId <= 0 ||
        rowState.logicalLineId > TerminalScreen.maxLogicalLineId ||
        rowState.logicalLineEpoch <= 0 ||
        rowState.logicalLineEpoch > 0x7fffffffffffffff ||
        rowState.logicalCellOffset < 0 ||
        rowState.logicalCellOffset > 0x7fffffffffffffff) {
      throw StateError('invalid snapshot history row');
    }
    final int bytes = rowState.columns * 17 + 23;
    allocatedBytes += bytes;
    if (allocatedBytes > history.maxBytes) {
      throw StateError('snapshot history exceeds its byte policy');
    }
    final _ScrollbackPage page = _ScrollbackPage(
      columns: rowState.columns,
      capacity: 1,
    );
    final Uint8List occupied = Uint8List(rowState.columns);
    for (final TerminalSnapshotCellState cell in rowState.cells) {
      if (cell.row != row ||
          cell.column < 0 ||
          cell.column >= rowState.columns ||
          occupied[cell.column] != 0) {
        throw StateError('invalid or duplicate snapshot history cell');
      }
      occupied[cell.column] = 1;
      _validateSnapshotCell(
        cell,
        styles: styles,
        graphemes: graphemes,
        hyperlinks: hyperlinks,
      );
      page.content[cell.column] = cell.content;
      page.foreground[cell.column] = cell.foreground;
      page.background[cell.column] = cell.background;
      page.styles[cell.column] = cell.style;
      page.hyperlinks[cell.column] = cell.hyperlink;
      page.widthFlags[cell.column] = cell.flags;
    }
    page.rowFlags[0] = rowState.flags;
    page.logicalLineIds[0] = rowState.logicalLineId;
    page.logicalLineEpochs[0] = rowState.logicalLineEpoch;
    page.logicalCellOffsets[0] = rowState.logicalCellOffset;
    final int? logicalCellCount = rowState.logicalCellCount;
    if (logicalCellCount == null ||
        logicalCellCount < 0 ||
        logicalCellCount > rowState.columns) {
      throw StateError('invalid snapshot history logical cell count');
    }
    page.logicalCellCounts[0] = logicalCellCount;
    page.usedRows = 1;
    history._appendPage(page);
    history._length++;
  }
  history._allocatedBytes = allocatedBytes;
  history._totalRowsAppended = rows.length;
  history._generation++;
  history._continuityGeneration++;
  history.validateCellTopology();
}

void _validateSnapshotCell(
  TerminalSnapshotCellState cell, {
  required TerminalStyleTable styles,
  required TerminalGraphemeTable graphemes,
  required TerminalHyperlinkTable hyperlinks,
}) {
  if (cell.flags < 0 || cell.flags & ~TerminalCellFlags.knownMask != 0) {
    throw StateError('snapshot cell has unknown flags');
  }
  TerminalScreen._validateColor(cell.foreground, 'foreground');
  TerminalScreen._validateColor(cell.background, 'background');
  _validateSnapshotStyle(styles, cell.style);
  if (cell.hyperlink < 0 || cell.hyperlink > hyperlinks.definitionCount) {
    throw StateError('snapshot cell hyperlink is undefined');
  }
  final int width = cell.flags & TerminalCellFlags.widthMask;
  if (width == TerminalCellFlags.continuation) {
    if (cell.content != 0 || cell.flags & TerminalCellFlags.grapheme != 0) {
      throw StateError('snapshot continuation has content');
    }
    return;
  }
  if (cell.content == 0) {
    if (cell.flags & TerminalCellFlags.grapheme != 0) {
      throw StateError('snapshot blank has grapheme identity');
    }
    return;
  }
  if (cell.flags & TerminalCellFlags.grapheme != 0) {
    if (cell.content > graphemes.definitionCount) {
      throw StateError('snapshot cell grapheme is undefined');
    }
  } else {
    TerminalUnicode.validateScalar(cell.content);
  }
}

void _validateSnapshotStyle(TerminalStyleTable styles, int id) {
  if (id < 0 || id > styles.definitionCount) {
    throw StateError('snapshot style is undefined');
  }
}
