import 'dart:typed_data';

import 'terminal_style.dart';

/// Version-one width and cell flag values from the packed-grid contract.
abstract final class TerminalCellFlags {
  static const int widthMask = 0x03;
  static const int continuation = 0;
  static const int narrow = 1;
  static const int wide = 2;
  static const int grapheme = 1 << 2;
  static const int protected = 1 << 3;
  static const int knownMask = widthMask | grapheme | protected;
}

/// Version-one row flag values from the packed-grid contract.
abstract final class TerminalRowFlags {
  static const int softWrapped = 1 << 0;
  static const int prompt = 1 << 1;
  static const int command = 1 << 2;
  static const int output = 1 << 3;
  static const int hardBreak = 1 << 4;
  static const int knownMask = (1 << 5) - 1;
}

enum TerminalScreenMode {
  origin,
  insert,
  autoWrap,
  reverseVideo,
  horizontalMargins,
}

enum TerminalCursorShape { block, underline, bar }

/// Bounded Dart-owned terminal screen using Struct-of-Arrays cell storage.
///
/// The screen is a single-writer object. Authoritative typed arrays remain
/// private so every mutation participates in row damage and generation
/// tracking. This phase accepts only blank or width-one Unicode scalars;
/// wide/grapheme mutation is introduced with the later Unicode/reflow task.
final class TerminalScreen {
  factory TerminalScreen({
    required int rows,
    required int columns,
    TerminalStyleTable? styleTable,
  }) {
    _validateDimensions(rows, columns);
    return TerminalScreen._(
      rows: rows,
      columns: columns,
      styleTable: styleTable ?? TerminalStyleTable(),
    );
  }

  TerminalScreen._({
    required this.rows,
    required this.columns,
    required this.styleTable,
  }) : cellCount = rows * columns,
       _content = Uint32List(rows * columns),
       _foreground = Uint32List(rows * columns),
       _background = Uint32List(rows * columns),
       _styles = Uint16List(rows * columns),
       _hyperlinks = Uint16List(rows * columns),
       _widthFlags = Uint8List(rows * columns),
       _rowVersions = Uint32List(rows),
       _dirtyStarts = Uint16List(rows),
       _dirtyEnds = Uint16List(rows),
       _rowFlags = Uint8List(rows),
       _logicalLineIds = Uint32List(rows),
       _tabStops = Uint8List(columns) {
    _widthFlags.fillRange(0, cellCount, TerminalCellFlags.narrow);
    _dirtyStarts.fillRange(0, rows, columns);
    for (int row = 0; row < rows; row++) {
      _logicalLineIds[row] = row + 1;
    }
    _nextLogicalLineId = rows + 1;
    _writeDefaultTabStops();
  }

  static const int maxRows = 4096;
  static const int maxColumns = 4096;
  static const int maxCellCount = 1048576;
  static const int maxResourceId = 65534;
  static const int maxLogicalLineId = 0xffffffff;
  static const int maxRowVersion = 0xffffffff;

  final int rows;
  final int columns;
  final int cellCount;
  final TerminalStyleTable styleTable;

  final Uint32List _content;
  final Uint32List _foreground;
  final Uint32List _background;
  final Uint16List _styles;
  final Uint16List _hyperlinks;
  final Uint8List _widthFlags;

  final Uint32List _rowVersions;
  final Uint16List _dirtyStarts;
  final Uint16List _dirtyEnds;
  final Uint8List _rowFlags;
  final Uint32List _logicalLineIds;
  final Uint8List _tabStops;

  int _firstPhysicalRow = 0;
  int _cursorRow = 0;
  int _cursorColumn = 0;
  int _savedCursorRow = 0;
  int _savedCursorColumn = 0;
  int _currentForeground = 0;
  int _currentBackground = 0;
  int _currentStyleId = 0;
  int _savedForeground = 0;
  int _savedBackground = 0;
  int _savedStyleId = 0;
  late int _nextLogicalLineId;
  int _generation = 1;
  bool _fullSnapshotRequired = true;

  int _topMargin = 0;
  late int _bottomMargin = rows - 1;
  int _leftMargin = 0;
  late int _rightMargin = columns - 1;
  bool _originMode = false;
  bool _insertMode = false;
  bool _autoWrapMode = true;
  bool _reverseVideoMode = false;
  bool _horizontalMarginsMode = false;
  bool _wrapPending = false;
  bool _cursorVisible = true;
  bool _cursorBlinking = true;
  TerminalCursorShape _cursorShape = TerminalCursorShape.block;

  int get cursorRow => _cursorRow;
  int get cursorColumn => _cursorColumn;
  int get savedCursorRow => _savedCursorRow;
  int get savedCursorColumn => _savedCursorColumn;
  int get currentForeground => _currentForeground;
  int get currentBackground => _currentBackground;
  int get currentStyleId => _currentStyleId;
  int get currentStyleAttributes => styleTable.attributesAt(_currentStyleId);
  int get savedForeground => _savedForeground;
  int get savedBackground => _savedBackground;
  int get savedStyleId => _savedStyleId;
  int get generation => _generation;
  bool get fullSnapshotRequired => _fullSnapshotRequired;
  int get topMargin => _topMargin;
  int get bottomMargin => _bottomMargin;
  int get leftMargin => _leftMargin;
  int get rightMargin => _rightMargin;
  int get activeLeftMargin => _horizontalMarginsMode ? _leftMargin : 0;
  int get activeRightMargin =>
      _horizontalMarginsMode ? _rightMargin : columns - 1;
  bool get wrapPending => _wrapPending;
  bool get cursorVisible => _cursorVisible;
  bool get cursorBlinking => _cursorBlinking;
  TerminalCursorShape get cursorShape => _cursorShape;

  int get cellStorageBytes => cellCount * 17;
  int get rowStorageBytes => rows * 13;
  int get tabStopStorageBytes => columns;
  int get typedStorageBytes =>
      cellStorageBytes + rowStorageBytes + tabStopStorageBytes;

  int contentAt(int row, int column) => _content[_cellIndex(row, column)];

  int foregroundAt(int row, int column) => _foreground[_cellIndex(row, column)];

  int backgroundAt(int row, int column) => _background[_cellIndex(row, column)];

  int styleAt(int row, int column) => _styles[_cellIndex(row, column)];

  int hyperlinkAt(int row, int column) => _hyperlinks[_cellIndex(row, column)];

  int widthFlagsAt(int row, int column) => _widthFlags[_cellIndex(row, column)];

  int rowVersionAt(int row) => _rowVersions[_physicalRowFor(row)];

  int dirtyStartAt(int row) => _dirtyStarts[_physicalRowFor(row)];

  int dirtyEndAt(int row) => _dirtyEnds[_physicalRowFor(row)];

  bool isRowDirty(int row) => dirtyStartAt(row) < dirtyEndAt(row);

  int rowFlagsAt(int row) => _rowFlags[_physicalRowFor(row)];

  int logicalLineIdAt(int row) => _logicalLineIds[_physicalRowFor(row)];

  /// Writes one canonical blank or width-one scalar cell.
  void setNarrowCell(
    int row,
    int column,
    int content, {
    int foreground = 0,
    int background = 0,
    int style = 0,
    int hyperlink = 0,
    bool isProtected = false,
  }) {
    final int index = _cellIndex(row, column);
    _validateContent(content);
    _validateColor(foreground, 'foreground');
    _validateColor(background, 'background');
    _validateResourceId(style, 'style');
    _validateResourceId(hyperlink, 'hyperlink');
    final int flags =
        TerminalCellFlags.narrow |
        (isProtected ? TerminalCellFlags.protected : 0);
    if (_content[index] == content &&
        _foreground[index] == foreground &&
        _background[index] == background &&
        _styles[index] == style &&
        _hyperlinks[index] == hyperlink &&
        _widthFlags[index] == flags) {
      return;
    }

    _content[index] = content;
    _foreground[index] = foreground;
    _background[index] = background;
    _styles[index] = style;
    _hyperlinks[index] = hyperlink;
    _widthFlags[index] = flags;
    _markDirtyPhysical(index ~/ columns, column, column + 1);
    _incrementGeneration();
  }

  void setRowFlags(int row, int flags) {
    final int physical = _physicalRowFor(row);
    if (flags < 0 || (flags & ~TerminalRowFlags.knownMask) != 0) {
      throw ArgumentError.value(flags, 'flags', 'contains unknown row flags');
    }
    if (_rowFlags[physical] == flags) {
      return;
    }
    _rowFlags[physical] = flags;
    _markDirtyPhysical(physical, 0, columns);
    _incrementGeneration();
  }

  void setLogicalLineId(int row, int logicalLineId) {
    final int physical = _physicalRowFor(row);
    if (logicalLineId <= 0 || logicalLineId > maxLogicalLineId) {
      throw RangeError.range(
        logicalLineId,
        1,
        maxLogicalLineId,
        'logicalLineId',
      );
    }
    if (_logicalLineIds[physical] == logicalLineId) {
      return;
    }
    _logicalLineIds[physical] = logicalLineId;
    _markDirtyPhysical(physical, 0, columns);
    _incrementGeneration();
  }

  void setCursorPosition(int row, int column) {
    _checkRow(row);
    _checkColumn(column);
    if (_setCursorUnchecked(row, column)) {
      _incrementGeneration();
    }
  }

  void saveCursor() {
    if (_savedCursorRow == _cursorRow &&
        _savedCursorColumn == _cursorColumn &&
        _savedForeground == _currentForeground &&
        _savedBackground == _currentBackground &&
        _savedStyleId == _currentStyleId) {
      return;
    }
    _savedCursorRow = _cursorRow;
    _savedCursorColumn = _cursorColumn;
    _savedForeground = _currentForeground;
    _savedBackground = _currentBackground;
    _savedStyleId = _currentStyleId;
    _incrementGeneration();
  }

  void restoreCursor() {
    bool changed = _setCursorUnchecked(_savedCursorRow, _savedCursorColumn);
    if (_currentForeground != _savedForeground ||
        _currentBackground != _savedBackground ||
        _currentStyleId != _savedStyleId) {
      _currentForeground = _savedForeground;
      _currentBackground = _savedBackground;
      _currentStyleId = _savedStyleId;
      changed = true;
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  /// Atomically updates the current SGR rendition.
  void setCurrentRendition({
    int? foreground,
    int? background,
    int? styleAttributes,
  }) {
    final int nextForeground = foreground ?? _currentForeground;
    final int nextBackground = background ?? _currentBackground;
    _validateColor(nextForeground, 'foreground');
    _validateColor(nextBackground, 'background');
    final int nextStyleId = styleAttributes == null
        ? _currentStyleId
        : styleTable.intern(styleAttributes);
    if (_currentForeground == nextForeground &&
        _currentBackground == nextBackground &&
        _currentStyleId == nextStyleId) {
      return;
    }
    _currentForeground = nextForeground;
    _currentBackground = nextBackground;
    _currentStyleId = nextStyleId;
    _incrementGeneration();
  }

  void resetCurrentRendition() {
    if (_currentForeground == 0 &&
        _currentBackground == 0 &&
        _currentStyleId == 0) {
      return;
    }
    _currentForeground = 0;
    _currentBackground = 0;
    _currentStyleId = 0;
    _incrementGeneration();
  }

  void homeCursor() {
    final int row = _originMode ? _topMargin : 0;
    final int column = _originMode ? activeLeftMargin : 0;
    if (_setCursorUnchecked(row, column)) {
      _incrementGeneration();
    }
  }

  void clampCursorToMargins() {
    final int row = _cursorRow.clamp(_topMargin, _bottomMargin);
    final int column = _cursorColumn.clamp(activeLeftMargin, activeRightMargin);
    if (_setCursorUnchecked(row, column)) {
      _incrementGeneration();
    }
  }

  void setWrapPending(bool value) {
    if (value && !_autoWrapMode) {
      throw StateError('wrap pending requires auto-wrap mode');
    }
    if (_wrapPending == value) {
      return;
    }
    _wrapPending = value;
    _incrementGeneration();
  }

  bool modeEnabled(TerminalScreenMode mode) => switch (mode) {
    TerminalScreenMode.origin => _originMode,
    TerminalScreenMode.insert => _insertMode,
    TerminalScreenMode.autoWrap => _autoWrapMode,
    TerminalScreenMode.reverseVideo => _reverseVideoMode,
    TerminalScreenMode.horizontalMargins => _horizontalMarginsMode,
  };

  bool get replaceMode => !_insertMode;

  void setMode(TerminalScreenMode mode, bool enabled) {
    bool changed = false;
    switch (mode) {
      case TerminalScreenMode.origin:
        if (_originMode != enabled) {
          _originMode = enabled;
          changed = true;
        }
        changed =
            _setCursorUnchecked(
              enabled ? _topMargin : 0,
              enabled ? activeLeftMargin : 0,
            ) ||
            changed;
      case TerminalScreenMode.insert:
        if (_insertMode != enabled) {
          _insertMode = enabled;
          changed = true;
        }
      case TerminalScreenMode.autoWrap:
        if (_autoWrapMode != enabled) {
          _autoWrapMode = enabled;
          changed = true;
        }
        if (!enabled && _wrapPending) {
          _wrapPending = false;
          changed = true;
        }
      case TerminalScreenMode.reverseVideo:
        if (_reverseVideoMode != enabled) {
          _reverseVideoMode = enabled;
          _markEveryRowDirty();
          changed = true;
        }
      case TerminalScreenMode.horizontalMargins:
        if (_horizontalMarginsMode != enabled) {
          _horizontalMarginsMode = enabled;
          changed = true;
        }
        if (!enabled && (_leftMargin != 0 || _rightMargin != columns - 1)) {
          _leftMargin = 0;
          _rightMargin = columns - 1;
          changed = true;
        }
        changed =
            _setCursorUnchecked(
              _originMode ? _topMargin : 0,
              _originMode ? activeLeftMargin : 0,
            ) ||
            changed;
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  void setCursorPresentation({
    TerminalCursorShape? shape,
    bool? visible,
    bool? blinking,
  }) {
    final TerminalCursorShape nextShape = shape ?? _cursorShape;
    final bool nextVisible = visible ?? _cursorVisible;
    final bool nextBlinking = blinking ?? _cursorBlinking;
    if (_cursorShape == nextShape &&
        _cursorVisible == nextVisible &&
        _cursorBlinking == nextBlinking) {
      return;
    }
    _cursorShape = nextShape;
    _cursorVisible = nextVisible;
    _cursorBlinking = nextBlinking;
    _incrementGeneration();
  }

  void setVerticalMargins(int top, int bottom) {
    _validateMargins(top, bottom, rows, 'vertical');
    bool changed = false;
    if (_topMargin != top || _bottomMargin != bottom) {
      _topMargin = top;
      _bottomMargin = bottom;
      changed = true;
    }
    changed =
        _setCursorUnchecked(
          _originMode ? _topMargin : 0,
          _originMode ? activeLeftMargin : 0,
        ) ||
        changed;
    if (changed) {
      _incrementGeneration();
    }
  }

  void resetVerticalMargins() {
    bool changed = false;
    if (_topMargin != 0 || _bottomMargin != rows - 1) {
      _topMargin = 0;
      _bottomMargin = rows - 1;
      changed = true;
    }
    changed =
        _setCursorUnchecked(
          _originMode ? _topMargin : 0,
          _originMode ? activeLeftMargin : 0,
        ) ||
        changed;
    if (changed) {
      _incrementGeneration();
    }
  }

  void setHorizontalMargins(int left, int right) {
    _validateMargins(left, right, columns, 'horizontal');
    bool changed = false;
    if (_leftMargin != left || _rightMargin != right) {
      _leftMargin = left;
      _rightMargin = right;
      changed = true;
    }
    changed =
        _setCursorUnchecked(
          _originMode ? _topMargin : 0,
          _originMode ? activeLeftMargin : 0,
        ) ||
        changed;
    if (changed) {
      _incrementGeneration();
    }
  }

  void resetHorizontalMargins() {
    bool changed = false;
    if (_leftMargin != 0 || _rightMargin != columns - 1) {
      _leftMargin = 0;
      _rightMargin = columns - 1;
      changed = true;
    }
    changed =
        _setCursorUnchecked(
          _originMode ? _topMargin : 0,
          _originMode ? activeLeftMargin : 0,
        ) ||
        changed;
    if (changed) {
      _incrementGeneration();
    }
  }

  /// Restores non-cell terminal state without erasing cell or row metadata.
  void resetTerminalState() {
    final bool reverseChanged = _reverseVideoMode;
    bool changed =
        _topMargin != 0 ||
        _bottomMargin != rows - 1 ||
        _leftMargin != 0 ||
        _rightMargin != columns - 1 ||
        _originMode ||
        _insertMode ||
        !_autoWrapMode ||
        _reverseVideoMode ||
        _horizontalMarginsMode ||
        _wrapPending ||
        !_cursorVisible ||
        !_cursorBlinking ||
        _cursorShape != TerminalCursorShape.block ||
        _cursorRow != 0 ||
        _cursorColumn != 0 ||
        _savedCursorRow != 0 ||
        _savedCursorColumn != 0 ||
        _currentForeground != 0 ||
        _currentBackground != 0 ||
        _currentStyleId != 0 ||
        _savedForeground != 0 ||
        _savedBackground != 0 ||
        _savedStyleId != 0 ||
        !_tabStopsAreDefault();

    _topMargin = 0;
    _bottomMargin = rows - 1;
    _leftMargin = 0;
    _rightMargin = columns - 1;
    _originMode = false;
    _insertMode = false;
    _autoWrapMode = true;
    _reverseVideoMode = false;
    _horizontalMarginsMode = false;
    _wrapPending = false;
    _cursorVisible = true;
    _cursorBlinking = true;
    _cursorShape = TerminalCursorShape.block;
    _cursorRow = 0;
    _cursorColumn = 0;
    _savedCursorRow = 0;
    _savedCursorColumn = 0;
    _currentForeground = 0;
    _currentBackground = 0;
    _currentStyleId = 0;
    _savedForeground = 0;
    _savedBackground = 0;
    _savedStyleId = 0;
    _writeDefaultTabStops();
    if (reverseChanged) {
      _markEveryRowDirty();
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  /// Prints a caller-classified width-one scalar at the cursor.
  void printNarrowScalar(int scalar) {
    _validateContent(scalar);
    if (scalar == 0) {
      throw ArgumentError.value(scalar, 'scalar', 'NUL is not printable');
    }
    if (_wrapPending) {
      _wrapToNextLine();
    }
    final int right = _horizontalRightForCursor();
    if (_insertMode) {
      insertCharacters(1);
    }
    setNarrowCell(
      _cursorRow,
      _cursorColumn,
      scalar,
      foreground: _currentForeground,
      background: _currentBackground,
      style: _currentStyleId,
    );
    if (_cursorColumn >= right) {
      if (_autoWrapMode && !_wrapPending) {
        _wrapPending = true;
        _incrementGeneration();
      }
      return;
    }
    if (_setCursorUnchecked(_cursorRow, _cursorColumn + 1)) {
      _incrementGeneration();
    }
  }

  void moveCursorUp(int count) {
    _validateCount(count);
    final int first = _verticalFirstForCursor();
    final int last = _verticalLastForCursor();
    _moveCursorClamped(
      _cursorRow - count,
      _cursorColumn,
      first,
      last,
      0,
      columns - 1,
    );
  }

  void moveCursorDown(int count) {
    _validateCount(count);
    final int first = _verticalFirstForCursor();
    final int last = _verticalLastForCursor();
    _moveCursorClamped(
      _cursorRow + count,
      _cursorColumn,
      first,
      last,
      0,
      columns - 1,
    );
  }

  void moveCursorForward(int count) {
    _validateCount(count);
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(
      _cursorRow,
      _cursorColumn + count,
      0,
      rows - 1,
      left,
      right,
    );
  }

  void moveCursorBackward(int count) {
    _validateCount(count);
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(
      _cursorRow,
      _cursorColumn - count,
      0,
      rows - 1,
      left,
      right,
    );
  }

  void moveCursorNextLine(int count) {
    _validateCount(count);
    final int first = _verticalFirstForCursor();
    final int last = _verticalLastForCursor();
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(_cursorRow + count, left, first, last, left, right);
  }

  void moveCursorPreviousLine(int count) {
    _validateCount(count);
    final int first = _verticalFirstForCursor();
    final int last = _verticalLastForCursor();
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(_cursorRow - count, left, first, last, left, right);
  }

  /// Uses zero-based row/column parameters, relative to margins in origin mode.
  void setCursorAddress(int row, int column) {
    if (row < 0 || column < 0) {
      throw RangeError('cursor address must be nonnegative');
    }
    final int targetRow;
    final int targetColumn;
    final int firstRow;
    final int lastRow;
    final int firstColumn;
    final int lastColumn;
    if (_originMode) {
      firstRow = _topMargin;
      lastRow = _bottomMargin;
      firstColumn = activeLeftMargin;
      lastColumn = activeRightMargin;
      targetRow = firstRow + row;
      targetColumn = firstColumn + column;
    } else {
      firstRow = 0;
      lastRow = rows - 1;
      firstColumn = 0;
      lastColumn = columns - 1;
      targetRow = row;
      targetColumn = column;
    }
    _moveCursorClamped(
      targetRow,
      targetColumn,
      firstRow,
      lastRow,
      firstColumn,
      lastColumn,
    );
  }

  void setCursorColumn(int column) {
    if (column < 0) {
      throw RangeError.value(column, 'column', 'must be nonnegative');
    }
    final int left = _originMode ? activeLeftMargin : 0;
    final int right = _originMode ? activeRightMargin : columns - 1;
    final int target = left + column;
    _moveCursorClamped(_cursorRow, target, 0, rows - 1, left, right);
  }

  void setCursorRow(int row) {
    if (row < 0) {
      throw RangeError.value(row, 'row', 'must be nonnegative');
    }
    final int first = _originMode ? _topMargin : 0;
    final int last = _originMode ? _bottomMargin : rows - 1;
    _moveCursorClamped(first + row, _cursorColumn, first, last, 0, columns - 1);
  }

  void backspace() {
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(_cursorRow, _cursorColumn - 1, 0, rows - 1, left, right);
  }

  void carriageReturn() {
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(_cursorRow, left, 0, rows - 1, left, right);
  }

  void horizontalTab([int count = 1]) {
    _validateCount(count);
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    int column = _cursorColumn;
    final int steps = count.clamp(1, columns);
    for (int step = 0; step < steps; step++) {
      int next = right;
      for (int candidate = column + 1; candidate <= right; candidate++) {
        if (_tabStops[candidate] != 0) {
          next = candidate;
          break;
        }
      }
      column = next;
    }
    _moveCursorClamped(_cursorRow, column, 0, rows - 1, left, right);
  }

  void backwardTab([int count = 1]) {
    _validateCount(count);
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    int column = _cursorColumn;
    final int steps = count.clamp(1, columns);
    for (int step = 0; step < steps; step++) {
      int previous = left;
      for (int candidate = column - 1; candidate >= left; candidate--) {
        if (_tabStops[candidate] != 0) {
          previous = candidate;
          break;
        }
      }
      column = previous;
    }
    _moveCursorClamped(_cursorRow, column, 0, rows - 1, left, right);
  }

  void lineFeed() {
    final int flags = rowFlagsAt(_cursorRow);
    setRowFlags(
      _cursorRow,
      (flags & ~TerminalRowFlags.softWrapped) | TerminalRowFlags.hardBreak,
    );
    index();
  }

  void index() {
    final int column = _cursorColumn;
    if (_cursorRow >= _topMargin && _cursorRow <= _bottomMargin) {
      if (_cursorRow == _bottomMargin) {
        scrollUp(1);
      } else {
        _moveCursorClamped(_cursorRow + 1, column, 0, rows - 1, 0, columns - 1);
      }
      return;
    }
    _moveCursorClamped(_cursorRow + 1, column, 0, rows - 1, 0, columns - 1);
  }

  void reverseIndex() {
    final int column = _cursorColumn;
    if (_cursorRow >= _topMargin && _cursorRow <= _bottomMargin) {
      if (_cursorRow == _topMargin) {
        scrollDown(1);
      } else {
        _moveCursorClamped(_cursorRow - 1, column, 0, rows - 1, 0, columns - 1);
      }
      return;
    }
    _moveCursorClamped(_cursorRow - 1, column, 0, rows - 1, 0, columns - 1);
  }

  void nextLine() {
    lineFeed();
    carriageReturn();
  }

  void insertCharacters(int count) {
    _validateCount(count);
    _wrapPending = false;
    final int right = _horizontalRightForCursor();
    final int amount = count.clamp(1, right - _cursorColumn + 1);
    final int physical = _physicalRow(_cursorRow);
    for (int column = right; column >= _cursorColumn + amount; column--) {
      _copyCell(physical, column - amount, physical, column);
    }
    _clearCellRange(physical, _cursorColumn, _cursorColumn + amount);
    _markDirtyPhysical(physical, _cursorColumn, right + 1);
    _incrementGeneration();
  }

  void deleteCharacters(int count) {
    _validateCount(count);
    _wrapPending = false;
    final int right = _horizontalRightForCursor();
    final int amount = count.clamp(1, right - _cursorColumn + 1);
    final int physical = _physicalRow(_cursorRow);
    for (int column = _cursorColumn; column + amount <= right; column++) {
      _copyCell(physical, column + amount, physical, column);
    }
    _clearCellRange(physical, right - amount + 1, right + 1);
    _markDirtyPhysical(physical, _cursorColumn, right + 1);
    _incrementGeneration();
  }

  void eraseCharacters(int count) {
    _validateCount(count);
    bool changed = _clearWrapPending();
    final int right = _horizontalRightForCursor();
    final int end = (_cursorColumn + count).clamp(_cursorColumn + 1, right + 1);
    final int physical = _physicalRow(_cursorRow);
    if (_clearCellRange(physical, _cursorColumn, end)) {
      _markDirtyPhysical(physical, _cursorColumn, end);
      changed = true;
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  void eraseInLine(int mode) {
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    final int start;
    final int end;
    switch (mode) {
      case 0:
        start = _cursorColumn;
        end = right + 1;
      case 1:
        start = left;
        end = _cursorColumn + 1;
      case 2:
        start = left;
        end = right + 1;
      default:
        throw ArgumentError.value(mode, 'mode', 'must be 0, 1, or 2');
    }
    bool changed = _clearWrapPending();
    final int physical = _physicalRow(_cursorRow);
    if (_clearCellRange(physical, start, end)) {
      _markDirtyPhysical(physical, start, end);
      changed = true;
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  void eraseInDisplay(int mode) {
    if (mode < 0 || mode > 2) {
      throw ArgumentError.value(mode, 'mode', 'must be 0, 1, or 2');
    }
    bool changed = _clearWrapPending();
    for (int row = 0; row < rows; row++) {
      final int start;
      final int end;
      if (mode == 0) {
        if (row < _cursorRow) {
          continue;
        }
        start = row == _cursorRow ? _cursorColumn : 0;
        end = columns;
      } else if (mode == 1) {
        if (row > _cursorRow) {
          continue;
        }
        start = 0;
        end = row == _cursorRow ? _cursorColumn + 1 : columns;
      } else {
        start = 0;
        end = columns;
      }
      final int physical = _physicalRow(row);
      if (_clearCellRange(physical, start, end)) {
        _markDirtyPhysical(physical, start, end);
        changed = true;
      }
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  void insertLines(int count) {
    _validateCount(count);
    if (_cursorRow < _topMargin || _cursorRow > _bottomMargin) {
      return;
    }
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _scrollDownRegion(_cursorRow, _bottomMargin, left, right, count);
  }

  void deleteLines(int count) {
    _validateCount(count);
    if (_cursorRow < _topMargin || _cursorRow > _bottomMargin) {
      return;
    }
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _scrollUpRegion(_cursorRow, _bottomMargin, left, right, count);
  }

  void scrollUp(int count) {
    _validateCount(count);
    _scrollUpRegion(
      _topMargin,
      _bottomMargin,
      activeLeftMargin,
      activeRightMargin,
      count,
    );
  }

  void scrollDown(int count) {
    _validateCount(count);
    _scrollDownRegion(
      _topMargin,
      _bottomMargin,
      activeLeftMargin,
      activeRightMargin,
      count,
    );
  }

  void resetScreen() {
    resetTerminalState();
    _firstPhysicalRow = 0;
    _content.fillRange(0, cellCount, 0);
    _foreground.fillRange(0, cellCount, 0);
    _background.fillRange(0, cellCount, 0);
    _styles.fillRange(0, cellCount, 0);
    _hyperlinks.fillRange(0, cellCount, 0);
    _widthFlags.fillRange(0, cellCount, TerminalCellFlags.narrow);
    _rowFlags.fillRange(0, rows, 0);
    for (int row = 0; row < rows; row++) {
      _logicalLineIds[row] = row + 1;
    }
    _nextLogicalLineId = rows + 1;
    _markEveryRowDirty();
    _fullSnapshotRequired = true;
    _incrementGeneration();
  }

  bool isTabStop(int column) {
    _checkColumn(column);
    return _tabStops[column] != 0;
  }

  void setTabStop(int column, {bool enabled = true}) {
    _checkColumn(column);
    final int value = enabled ? 1 : 0;
    if (_tabStops[column] == value) {
      return;
    }
    _tabStops[column] = value;
    _incrementGeneration();
  }

  void clearAllTabStops() {
    for (int column = 0; column < columns; column++) {
      if (_tabStops[column] != 0) {
        _tabStops.fillRange(0, columns, 0);
        _incrementGeneration();
        return;
      }
    }
  }

  void resetDefaultTabStops() {
    bool changed = false;
    for (int column = 0; column < columns; column++) {
      final int expected = column != 0 && column % 8 == 0 ? 1 : 0;
      if (_tabStops[column] != expected) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return;
    }
    _writeDefaultTabStops();
    _incrementGeneration();
  }

  int nextTabStop(int fromColumn) {
    _checkColumn(fromColumn);
    for (int column = fromColumn + 1; column < columns; column++) {
      if (_tabStops[column] != 0) {
        return column;
      }
    }
    return columns - 1;
  }

  int previousTabStop(int fromColumn) {
    _checkColumn(fromColumn);
    for (int column = fromColumn - 1; column >= 0; column--) {
      if (_tabStops[column] != 0) {
        return column;
      }
    }
    return 0;
  }

  void clearDamage() {
    _dirtyStarts.fillRange(0, rows, columns);
    _dirtyEnds.fillRange(0, rows, 0);
  }

  /// Records that a renderer has accepted a complete snapshot of this screen.
  void acknowledgeFullSnapshot() {
    _fullSnapshotRequired = false;
  }

  void markAllDirty() {
    bool changed = false;
    for (int physical = 0; physical < rows; physical++) {
      changed = _markDirtyPhysical(physical, 0, columns) || changed;
    }
    if (changed) {
      _incrementGeneration();
    }
  }

  static void _validateDimensions(int rows, int columns) {
    if (rows <= 0 || rows > maxRows) {
      throw RangeError.range(rows, 1, maxRows, 'rows');
    }
    if (columns <= 0 || columns > maxColumns) {
      throw RangeError.range(columns, 1, maxColumns, 'columns');
    }
    final int cells = rows * columns;
    if (cells > maxCellCount) {
      throw ArgumentError.value(
        cells,
        'rows * columns',
        'must not exceed $maxCellCount cells',
      );
    }
  }

  static void _validateContent(int content) {
    if (content < 0 ||
        content > 0x10ffff ||
        (content >= 0xd800 && content <= 0xdfff)) {
      throw ArgumentError.value(
        content,
        'content',
        'must be zero or a Unicode scalar',
      );
    }
  }

  static void _validateColor(int color, String name) {
    final bool defaultOrPalette = color >= 0 && color <= 256;
    final bool direct = color >= 0x80000000 && color <= 0x80ffffff;
    if (!defaultOrPalette && !direct) {
      throw ArgumentError.value(color, name, 'invalid terminal color token');
    }
  }

  static void _validateResourceId(int value, String name) {
    if (value < 0 || value > maxResourceId) {
      throw RangeError.range(value, 0, maxResourceId, name);
    }
  }

  static void _validateMargins(int first, int last, int extent, String name) {
    if (first < 0 || last >= extent || first >= last) {
      throw ArgumentError.value(
        <int>[first, last],
        name,
        'must be an ordered range within 0..${extent - 1}',
      );
    }
  }

  int _cellIndex(int row, int column) {
    _checkRow(row);
    _checkColumn(column);
    return _physicalRow(row) * columns + column;
  }

  int _physicalRowFor(int row) {
    _checkRow(row);
    return _physicalRow(row);
  }

  int _physicalRow(int logicalRow) => (_firstPhysicalRow + logicalRow) % rows;

  void _checkRow(int row) {
    RangeError.checkValueInInterval(row, 0, rows - 1, 'row');
  }

  void _checkColumn(int column) {
    RangeError.checkValueInInterval(column, 0, columns - 1, 'column');
  }

  static void _validateCount(int count) {
    if (count <= 0) {
      throw RangeError.value(count, 'count', 'must be positive');
    }
  }

  bool get _cursorUsesVerticalMargins =>
      _cursorRow >= _topMargin && _cursorRow <= _bottomMargin;

  int _verticalFirstForCursor() => _cursorUsesVerticalMargins ? _topMargin : 0;

  int _verticalLastForCursor() =>
      _cursorUsesVerticalMargins ? _bottomMargin : rows - 1;

  bool get _cursorUsesHorizontalMargins =>
      _horizontalMarginsMode &&
      _cursorColumn >= _leftMargin &&
      _cursorColumn <= _rightMargin;

  int _horizontalLeftForCursor() =>
      _cursorUsesHorizontalMargins ? _leftMargin : 0;

  int _horizontalRightForCursor() =>
      _cursorUsesHorizontalMargins ? _rightMargin : columns - 1;

  void _moveCursorClamped(
    int row,
    int column,
    int firstRow,
    int lastRow,
    int firstColumn,
    int lastColumn,
  ) {
    final int nextRow = row.clamp(firstRow, lastRow);
    final int nextColumn = column.clamp(firstColumn, lastColumn);
    if (_setCursorUnchecked(nextRow, nextColumn)) {
      _incrementGeneration();
    }
  }

  void _wrapToNextLine() {
    final int previousRow = _cursorRow;
    final int logicalLineId = logicalLineIdAt(previousRow);
    final int flags = rowFlagsAt(previousRow);
    setRowFlags(
      previousRow,
      (flags & ~TerminalRowFlags.hardBreak) | TerminalRowFlags.softWrapped,
    );
    final int left = _horizontalLeftForCursor();
    final int right = _horizontalRightForCursor();
    _moveCursorClamped(previousRow, left, 0, rows - 1, left, right);
    index();
    setLogicalLineId(_cursorRow, logicalLineId);
  }

  void _copyCell(
    int sourcePhysical,
    int sourceColumn,
    int destinationPhysical,
    int destinationColumn,
  ) {
    final int source = sourcePhysical * columns + sourceColumn;
    final int destination = destinationPhysical * columns + destinationColumn;
    _content[destination] = _content[source];
    _foreground[destination] = _foreground[source];
    _background[destination] = _background[source];
    _styles[destination] = _styles[source];
    _hyperlinks[destination] = _hyperlinks[source];
    _widthFlags[destination] = _widthFlags[source];
  }

  void _copyCellRange(
    int sourcePhysical,
    int destinationPhysical,
    int startColumn,
    int endColumn,
  ) {
    final int source = sourcePhysical * columns + startColumn;
    final int destination = destinationPhysical * columns + startColumn;
    final int length = endColumn - startColumn;
    _content.setRange(destination, destination + length, _content, source);
    _foreground.setRange(
      destination,
      destination + length,
      _foreground,
      source,
    );
    _background.setRange(
      destination,
      destination + length,
      _background,
      source,
    );
    _styles.setRange(destination, destination + length, _styles, source);
    _hyperlinks.setRange(
      destination,
      destination + length,
      _hyperlinks,
      source,
    );
    _widthFlags.setRange(
      destination,
      destination + length,
      _widthFlags,
      source,
    );
  }

  bool _clearCellRange(int physical, int startColumn, int endColumn) {
    final int start = physical * columns + startColumn;
    final int end = physical * columns + endColumn;
    bool changed = false;
    for (int index = start; index < end; index++) {
      if (_content[index] != 0 ||
          _foreground[index] != 0 ||
          _background[index] != _currentBackground ||
          _styles[index] != 0 ||
          _hyperlinks[index] != 0 ||
          _widthFlags[index] != TerminalCellFlags.narrow) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return false;
    }
    _content.fillRange(start, end, 0);
    _foreground.fillRange(start, end, 0);
    _background.fillRange(start, end, _currentBackground);
    _styles.fillRange(start, end, 0);
    _hyperlinks.fillRange(start, end, 0);
    _widthFlags.fillRange(start, end, TerminalCellFlags.narrow);
    return true;
  }

  void _scrollUpRegion(int top, int bottom, int left, int right, int count) {
    _wrapPending = false;
    final int amount = count.clamp(1, bottom - top + 1);
    if (top == 0 && bottom == rows - 1 && left == 0 && right == columns - 1) {
      _firstPhysicalRow = (_firstPhysicalRow + amount) % rows;
      for (int row = rows - amount; row < rows; row++) {
        final int physical = _physicalRow(row);
        _clearCellRange(physical, 0, columns);
        _rowFlags[physical] = 0;
        _logicalLineIds[physical] = _allocateLogicalLineId();
      }
      _markEveryRowDirty();
      _incrementGeneration();
      return;
    }

    final bool fullWidth = left == 0 && right == columns - 1;
    for (int row = top; row <= bottom - amount; row++) {
      final int destination = _physicalRow(row);
      final int source = _physicalRow(row + amount);
      _copyCellRange(source, destination, left, right + 1);
      if (fullWidth) {
        _rowFlags[destination] = _rowFlags[source];
        _logicalLineIds[destination] = _logicalLineIds[source];
      }
    }
    for (int row = bottom - amount + 1; row <= bottom; row++) {
      final int physical = _physicalRow(row);
      _clearCellRange(physical, left, right + 1);
      if (fullWidth) {
        _rowFlags[physical] = 0;
        _logicalLineIds[physical] = _allocateLogicalLineId();
      }
    }
    _markRegionDirty(top, bottom, left, right + 1);
    _incrementGeneration();
  }

  void _scrollDownRegion(int top, int bottom, int left, int right, int count) {
    _wrapPending = false;
    final int amount = count.clamp(1, bottom - top + 1);
    if (top == 0 && bottom == rows - 1 && left == 0 && right == columns - 1) {
      _firstPhysicalRow = (_firstPhysicalRow - amount) % rows;
      for (int row = 0; row < amount; row++) {
        final int physical = _physicalRow(row);
        _clearCellRange(physical, 0, columns);
        _rowFlags[physical] = 0;
        _logicalLineIds[physical] = _allocateLogicalLineId();
      }
      _markEveryRowDirty();
      _incrementGeneration();
      return;
    }

    final bool fullWidth = left == 0 && right == columns - 1;
    for (int row = bottom; row >= top + amount; row--) {
      final int destination = _physicalRow(row);
      final int source = _physicalRow(row - amount);
      _copyCellRange(source, destination, left, right + 1);
      if (fullWidth) {
        _rowFlags[destination] = _rowFlags[source];
        _logicalLineIds[destination] = _logicalLineIds[source];
      }
    }
    for (int row = top; row < top + amount; row++) {
      final int physical = _physicalRow(row);
      _clearCellRange(physical, left, right + 1);
      if (fullWidth) {
        _rowFlags[physical] = 0;
        _logicalLineIds[physical] = _allocateLogicalLineId();
      }
    }
    _markRegionDirty(top, bottom, left, right + 1);
    _incrementGeneration();
  }

  void _markRegionDirty(int top, int bottom, int start, int end) {
    for (int row = top; row <= bottom; row++) {
      _markDirtyPhysical(_physicalRow(row), start, end);
    }
  }

  int _allocateLogicalLineId() {
    if (_nextLogicalLineId > maxLogicalLineId) {
      for (int row = 0; row < rows; row++) {
        _logicalLineIds[_physicalRow(row)] = row + 1;
      }
      _nextLogicalLineId = rows + 1;
      _markEveryRowDirty();
      _fullSnapshotRequired = true;
    }
    return _nextLogicalLineId++;
  }

  bool _markDirtyPhysical(int physical, int start, int end) {
    final int previousStart = _dirtyStarts[physical];
    final int previousEnd = _dirtyEnds[physical];
    final bool wasClean = previousStart >= previousEnd;
    if (wasClean) {
      if (_advanceRowVersion(physical)) {
        return true;
      }
      _dirtyStarts[physical] = start;
      _dirtyEnds[physical] = end;
      return true;
    }
    final int nextStart = start < previousStart ? start : previousStart;
    final int nextEnd = end > previousEnd ? end : previousEnd;
    if (nextStart == previousStart && nextEnd == previousEnd) {
      return false;
    }
    _dirtyStarts[physical] = nextStart;
    _dirtyEnds[physical] = nextEnd;
    return true;
  }

  bool _markEveryRowDirty() {
    bool changed = false;
    for (int physical = 0; physical < rows; physical++) {
      changed = _markDirtyPhysical(physical, 0, columns) || changed;
    }
    return changed;
  }

  bool _advanceRowVersion(int physical) {
    final int version = _rowVersions[physical];
    if (version < maxRowVersion) {
      _rowVersions[physical] = version + 1;
      return false;
    }
    for (int row = 0; row < rows; row++) {
      _rowVersions[row] = 1;
      _dirtyStarts[row] = 0;
      _dirtyEnds[row] = columns;
    }
    _fullSnapshotRequired = true;
    return true;
  }

  void _writeDefaultTabStops() {
    _tabStops.fillRange(0, columns, 0);
    for (int column = 8; column < columns; column += 8) {
      _tabStops[column] = 1;
    }
  }

  bool _tabStopsAreDefault() {
    for (int column = 0; column < columns; column++) {
      final int expected = column != 0 && column % 8 == 0 ? 1 : 0;
      if (_tabStops[column] != expected) {
        return false;
      }
    }
    return true;
  }

  bool _setCursorUnchecked(int row, int column) {
    final bool changed =
        _cursorRow != row || _cursorColumn != column || _wrapPending;
    _cursorRow = row;
    _cursorColumn = column;
    _wrapPending = false;
    return changed;
  }

  bool _clearWrapPending() {
    if (!_wrapPending) {
      return false;
    }
    _wrapPending = false;
    return true;
  }

  void _incrementGeneration() {
    _generation++;
  }
}
