import 'dart:typed_data';

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

/// Bounded Dart-owned terminal screen using Struct-of-Arrays cell storage.
///
/// The screen is a single-writer object. Authoritative typed arrays remain
/// private so every mutation participates in row damage and generation
/// tracking. This phase accepts only blank or width-one Unicode scalars;
/// wide/grapheme mutation is introduced with the later Unicode/reflow task.
final class TerminalScreen {
  factory TerminalScreen({required int rows, required int columns}) {
    _validateDimensions(rows, columns);
    return TerminalScreen._(rows: rows, columns: columns);
  }

  TerminalScreen._({required this.rows, required this.columns})
    : cellCount = rows * columns,
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
  int _generation = 1;
  bool _fullSnapshotRequired = true;

  int get cursorRow => _cursorRow;
  int get cursorColumn => _cursorColumn;
  int get savedCursorRow => _savedCursorRow;
  int get savedCursorColumn => _savedCursorColumn;
  int get generation => _generation;
  bool get fullSnapshotRequired => _fullSnapshotRequired;

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
    if (_cursorRow == row && _cursorColumn == column) {
      return;
    }
    _cursorRow = row;
    _cursorColumn = column;
    _incrementGeneration();
  }

  void saveCursor() {
    if (_savedCursorRow == _cursorRow && _savedCursorColumn == _cursorColumn) {
      return;
    }
    _savedCursorRow = _cursorRow;
    _savedCursorColumn = _cursorColumn;
    _incrementGeneration();
  }

  void restoreCursor() {
    if (_cursorRow == _savedCursorRow && _cursorColumn == _savedCursorColumn) {
      return;
    }
    _cursorRow = _savedCursorRow;
    _cursorColumn = _savedCursorColumn;
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

  void _incrementGeneration() {
    _generation++;
  }
}
