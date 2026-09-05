part of 'terminal_screen.dart';

/// Bounded fixed-page history retained from the primary terminal screen.
final class TerminalScrollback {
  TerminalScrollback({
    this.maxLines = defaultMaxLines,
    this.maxBytes = defaultMaxBytes,
    this.pageRows = defaultPageRows,
  }) {
    if (maxLines <= 0 || maxLines > maximumLineLimit) {
      throw RangeError.range(maxLines, 1, maximumLineLimit, 'maxLines');
    }
    if (maxBytes <= 0 || maxBytes > maximumByteLimit) {
      throw RangeError.range(maxBytes, 1, maximumByteLimit, 'maxBytes');
    }
    if (pageRows <= 0 || pageRows > maximumPageRows) {
      throw RangeError.range(pageRows, 1, maximumPageRows, 'pageRows');
    }
  }

  static const int defaultMaxLines = 10000;
  static const int defaultMaxBytes = 64 * 1024 * 1024;
  static const int defaultPageRows = 256;
  static const int maximumLineLimit = 1000000;
  static const int maximumByteLimit = 1024 * 1024 * 1024;
  static const int maximumPageRows = 256;

  final int maxLines;
  final int maxBytes;
  final int pageRows;

  _ScrollbackPage? _head;
  _ScrollbackPage? _tail;
  int _length = 0;
  int _pageCount = 0;
  int _allocatedBytes = 0;
  int _generation = 1;
  int _totalRowsAppended = 0;
  int _continuityGeneration = 1;
  TerminalScrollbackAttachment? _attachment;
  _ScrollbackPage? _lookupPage;
  int _lookupPageStart = 0;

  int get length => _length;
  int get pageCount => _pageCount;
  int get allocatedBytes => _allocatedBytes;
  int get generation => _generation;
  int get totalRowsAppended => _totalRowsAppended;
  int get continuityGeneration => _continuityGeneration;
  bool get isEmpty => _length == 0;

  int columnsAt(int row) => _locate(row).page.columns;

  int rowFlagsAt(int row) {
    final _ScrollbackLocation location = _locate(row);
    return location.page.rowFlags[location.row];
  }

  int logicalLineIdAt(int row) {
    final _ScrollbackLocation location = _locate(row);
    return location.page.logicalLineIds[location.row];
  }

  int logicalLineEpochAt(int row) {
    final _ScrollbackLocation location = _locate(row);
    return location.page.logicalLineEpochs[location.row];
  }

  int logicalCellOffsetAt(int row) {
    final _ScrollbackLocation location = _locate(row);
    return location.page.logicalCellOffsets[location.row];
  }

  int _reflowRowExtentAt(int row) {
    final _ScrollbackLocation location = _locate(row);
    final int visibleExtent = location.page.rowExtent(location.row);
    final int visibleLogicalCells = location.page.visibleLogicalCellCount(
      location.row,
    );
    final int retainedLogicalCells = location.page.logicalCellCount(
      location.row,
    );
    return (visibleExtent + retainedLogicalCells - visibleLogicalCells).clamp(
      0,
      location.page.columns,
    );
  }

  int contentAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.content);

  int foregroundAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.foreground);

  int backgroundAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.background);

  int styleAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.styles);

  int hyperlinkAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.hyperlinks);

  int widthFlagsAt(int row, int column) =>
      _cellValue(row, column, (_ScrollbackPage page) => page.widthFlags);

  /// Drops all retained pages without changing the configured limits.
  void clear() {
    if (_head == null) {
      return;
    }
    _dropAllPages();
    _continuityGeneration++;
    _generation++;
  }

  /// Throws when page links, counters, or packed cell topology are invalid.
  void validateCellTopology() {
    int rowsSeen = 0;
    int pagesSeen = 0;
    int bytesSeen = 0;
    int previousFlags = 0;
    int previousLogicalLineId = 0;
    int previousLogicalLineEpoch = 0;
    int previousLogicalOffset = 0;
    int previousLogicalCellCount = 0;
    _ScrollbackPage? previous;
    _ScrollbackPage? page = _head;
    while (page != null) {
      if (!identical(page.previous, previous) || page.usedRows == 0) {
        throw StateError('invalid scrollback page links or row count');
      }
      if (page.usedRows > page.capacity || page.capacity > pageRows) {
        throw StateError('invalid scrollback page capacity');
      }
      for (int row = 0; row < page.usedRows; row++) {
        final int flags = page.rowFlags[row];
        if ((flags & ~TerminalRowFlags.knownMask) != 0 ||
            page.logicalLineIds[row] == 0) {
          throw StateError('invalid scrollback row metadata');
        }
        _validatePageRowTopology(page, row);
        final int logicalCellCount = page.logicalCellCount(row);
        if (logicalCellCount < page.visibleLogicalCellCount(row) ||
            logicalCellCount > page.columns) {
          throw StateError('invalid scrollback logical cell count');
        }
        final int logicalLineId = page.logicalLineIds[row];
        final int logicalLineEpoch = page.logicalLineEpochs[row];
        final int logicalOffset = page.logicalCellOffsets[row];
        if (logicalLineEpoch == 0) {
          throw StateError('invalid scrollback logical-line epoch');
        }
        if (rowsSeen + row != 0) {
          final bool joined =
              previousFlags & TerminalRowFlags.softWrapped != 0 &&
              previousLogicalLineId == logicalLineId &&
              previousLogicalLineEpoch == logicalLineEpoch;
          final int expected = joined
              ? previousLogicalOffset + previousLogicalCellCount
              : 0;
          if (logicalOffset != expected) {
            throw StateError('invalid scrollback logical cell offset');
          }
        }
        previousFlags = flags;
        previousLogicalLineId = logicalLineId;
        previousLogicalLineEpoch = logicalLineEpoch;
        previousLogicalOffset = logicalOffset;
        previousLogicalCellCount = page.logicalCellCount(row);
      }
      rowsSeen += page.usedRows;
      pagesSeen++;
      bytesSeen += page.allocatedBytes;
      previous = page;
      page = page.next;
    }
    if (!identical(previous, _tail) ||
        rowsSeen != _length ||
        pagesSeen != _pageCount ||
        bytesSeen != _allocatedBytes ||
        _length > maxLines ||
        _allocatedBytes > maxBytes ||
        (_head == null) != (_tail == null)) {
      throw StateError('invalid scrollback aggregate state');
    }
  }

  int _cellValue(
    int row,
    int column,
    TypedData Function(_ScrollbackPage page) values,
  ) {
    final _ScrollbackLocation location = _locate(row);
    if (column < 0 || column >= location.page.columns) {
      throw RangeError.range(column, 0, location.page.columns - 1, 'column');
    }
    final int index = location.row * location.page.columns + column;
    final TypedData data = values(location.page);
    return switch (data) {
      Uint32List typed => typed[index],
      Uint16List typed => typed[index],
      Uint8List typed => typed[index],
      _ => throw StateError('unsupported scrollback cell storage'),
    };
  }

  _ScrollbackLocation _locate(int row) {
    if (row < 0 || row >= _length) {
      throw RangeError.range(row, 0, _length - 1, 'row');
    }
    _ScrollbackPage? page = _lookupPage;
    int start = _lookupPageStart;
    if (page == null) {
      page = _head;
      start = 0;
    } else if (row < start) {
      while (page != null && row < start) {
        final _ScrollbackPage? previous = page.previous;
        if (previous == null) {
          break;
        }
        page = previous;
        start -= page.usedRows;
      }
    }
    while (page != null && row >= start + page.usedRows) {
      start += page.usedRows;
      page = page.next;
    }
    if (page != null && row >= start && row < start + page.usedRows) {
      _lookupPage = page;
      _lookupPageStart = start;
      return _ScrollbackLocation(page, row - start);
    }
    throw StateError('scrollback row index was not found');
  }

  bool _appendScreenRow(TerminalScreen source, int row) {
    final int logicalOffset = source.logicalCellOffsetAt(row);
    while (_length >= maxLines) {
      _evictHead();
    }

    _ScrollbackPage? page = _tail;
    if (page == null || page.columns != source.columns || page.isFull) {
      final int bytesPerRow = source.columns * 17 + 23;
      final int capacity = _minimum3(
        pageRows,
        maxLines,
        maxBytes ~/ bytesPerRow,
      );
      if (capacity == 0) {
        final bool changed = _head != null;
        _dropAllPages();
        if (changed) {
          _continuityGeneration++;
        }
        return changed;
      }
      final _ScrollbackPage allocated = _ScrollbackPage(
        columns: source.columns,
        capacity: capacity,
      );
      while (_allocatedBytes + allocated.allocatedBytes > maxBytes) {
        _evictHead();
      }
      _appendPage(allocated);
      page = allocated;
    }

    page.appendScreenRow(
      source,
      row,
      logicalOffset,
      _reflowLogicalCellCount(_ReflowSource(source), row),
    );
    _length++;
    _totalRowsAppended++;
    return true;
  }

  void _appendReflowRow(_ReflowRow row, int columns) {
    while (_length >= maxLines) {
      _evictHead();
    }

    _ScrollbackPage? page = _tail;
    if (page == null || page.columns != columns || page.isFull) {
      final int bytesPerRow = columns * 17 + 23;
      final int capacity = _minimum3(
        pageRows,
        maxLines,
        maxBytes ~/ bytesPerRow,
      );
      if (capacity == 0) {
        _dropAllPages();
        return;
      }
      final _ScrollbackPage allocated = _ScrollbackPage(
        columns: columns,
        capacity: capacity,
      );
      while (_allocatedBytes + allocated.allocatedBytes > maxBytes) {
        _evictHead();
      }
      _appendPage(allocated);
      page = allocated;
    }

    page.appendReflowRow(row);
    _length++;
  }

  void _appendPage(_ScrollbackPage page) {
    final _ScrollbackPage? tail = _tail;
    if (tail == null) {
      _head = page;
    } else {
      tail.next = page;
      page.previous = tail;
    }
    _tail = page;
    _pageCount++;
    _allocatedBytes += page.allocatedBytes;
  }

  void _evictHead() {
    final _ScrollbackPage? page = _head;
    if (page == null) {
      throw StateError('cannot evict an empty scrollback');
    }
    final _ScrollbackPage? next = page.next;
    if (next == null) {
      _head = null;
      _tail = null;
    } else {
      next.previous = null;
      _head = next;
    }
    page.next = null;
    page.previous = null;
    if (identical(_lookupPage, page)) {
      _lookupPage = null;
      _lookupPageStart = 0;
    } else if (_lookupPage != null) {
      _lookupPageStart -= page.usedRows;
    }
    _length -= page.usedRows;
    _pageCount--;
    _allocatedBytes -= page.allocatedBytes;
  }

  void _dropAllPages() {
    _head = null;
    _tail = null;
    _length = 0;
    _pageCount = 0;
    _allocatedBytes = 0;
    _lookupPage = null;
    _lookupPageStart = 0;
  }

  void _replacePagesFrom(TerminalScrollback replacement) {
    if (replacement.maxLines != maxLines ||
        replacement.maxBytes != maxBytes ||
        replacement.pageRows != pageRows ||
        replacement._attachment != null) {
      throw StateError('incompatible scrollback replacement');
    }
    _head = replacement._head;
    _tail = replacement._tail;
    _length = replacement._length;
    _pageCount = replacement._pageCount;
    _allocatedBytes = replacement._allocatedBytes;
    _lookupPage = null;
    _lookupPageStart = 0;
    replacement._head = null;
    replacement._tail = null;
    replacement._length = 0;
    replacement._pageCount = 0;
    replacement._allocatedBytes = 0;
    replacement._lookupPage = null;
    replacement._lookupPageStart = 0;
    _generation++;
  }

  void _claim(TerminalScrollbackAttachment attachment) {
    final TerminalScrollbackAttachment? current = _attachment;
    if (current != null && !identical(current, attachment)) {
      throw StateError('scrollback already belongs to another screen set');
    }
    _attachment = attachment;
  }

  void _validatePageRowTopology(_ScrollbackPage page, int row) {
    final int base = row * page.columns;
    for (int column = 0; column < page.columns; column++) {
      final int index = base + column;
      final int flags = page.widthFlags[index];
      if ((flags & ~TerminalCellFlags.knownMask) != 0 ||
          (flags & TerminalCellFlags.widthMask) ==
              TerminalCellFlags.widthMask) {
        throw StateError('invalid scrollback cell flags');
      }
      final int width = flags & TerminalCellFlags.widthMask;
      final bool grapheme = flags & TerminalCellFlags.grapheme != 0;
      if (width == TerminalCellFlags.continuation) {
        if (column == 0 || page.content[index] != 0 || grapheme) {
          throw StateError('orphan scrollback continuation');
        }
        final int lead = index - 1;
        if ((page.widthFlags[lead] & TerminalCellFlags.widthMask) !=
                TerminalCellFlags.wide ||
            page.foreground[index] != page.foreground[lead] ||
            page.background[index] != page.background[lead] ||
            page.styles[index] != page.styles[lead] ||
            page.hyperlinks[index] != page.hyperlinks[lead] ||
            (page.widthFlags[index] & TerminalCellFlags.protected) !=
                (page.widthFlags[lead] & TerminalCellFlags.protected)) {
          throw StateError('mismatched scrollback continuation');
        }
      } else if (width == TerminalCellFlags.wide) {
        if (page.content[index] == 0 || column + 1 >= page.columns) {
          throw StateError('invalid scrollback wide lead');
        }
        final int continuation = page.widthFlags[index + 1];
        if ((continuation & TerminalCellFlags.widthMask) !=
            TerminalCellFlags.continuation) {
          throw StateError('scrollback wide lead lacks continuation');
        }
      } else if (grapheme && page.content[index] == 0) {
        throw StateError('blank scrollback grapheme cell');
      }
    }
  }
}

/// Non-exported ownership token shared by one screen set and its primary grid.
final class TerminalScrollbackAttachment {
  TerminalScrollbackAttachment(this.scrollback);

  final TerminalScrollback scrollback;
  TerminalScreen? _owner;

  void activate(TerminalScreen screen) {
    scrollback._claim(this);
    _owner = screen;
  }

  void captureRows(TerminalScreen source, int startRow, int count) {
    if (!identical(source, _owner)) {
      return;
    }
    var changed = false;
    for (int row = startRow; row < startRow + count; row++) {
      changed = scrollback._appendScreenRow(source, row) || changed;
    }
    if (changed) {
      scrollback._generation++;
    }
  }
}

final class _ScrollbackPage {
  _ScrollbackPage({required this.columns, required this.capacity})
    : content = Uint32List(columns * capacity),
      foreground = Uint32List(columns * capacity),
      background = Uint32List(columns * capacity),
      styles = Uint16List(columns * capacity),
      hyperlinks = Uint16List(columns * capacity),
      widthFlags = Uint8List(columns * capacity),
      rowFlags = Uint8List(capacity),
      logicalLineIds = Uint32List(capacity),
      logicalLineEpochs = Uint64List(capacity),
      logicalCellOffsets = Uint64List(capacity),
      logicalCellCounts = Uint16List(capacity) {
    widthFlags.fillRange(0, widthFlags.length, TerminalCellFlags.narrow);
  }

  final int columns;
  final int capacity;
  final Uint32List content;
  final Uint32List foreground;
  final Uint32List background;
  final Uint16List styles;
  final Uint16List hyperlinks;
  final Uint8List widthFlags;
  final Uint8List rowFlags;
  final Uint32List logicalLineIds;
  final Uint64List logicalLineEpochs;
  final Uint64List logicalCellOffsets;
  final Uint16List logicalCellCounts;
  _ScrollbackPage? previous;
  _ScrollbackPage? next;
  int usedRows = 0;

  bool get isFull => usedRows == capacity;
  int get allocatedBytes => capacity * (columns * 17 + 23);

  void appendScreenRow(
    TerminalScreen source,
    int row,
    int logicalOffset,
    int logicalCellCount,
  ) {
    if (isFull || source.columns != columns) {
      throw StateError('incompatible scrollback page append');
    }
    final int sourcePhysical = source._physicalRowFor(row);
    final int sourceStart = sourcePhysical * columns;
    final int destinationStart = usedRows * columns;
    content.setRange(
      destinationStart,
      destinationStart + columns,
      source._content,
      sourceStart,
    );
    foreground.setRange(
      destinationStart,
      destinationStart + columns,
      source._foreground,
      sourceStart,
    );
    background.setRange(
      destinationStart,
      destinationStart + columns,
      source._background,
      sourceStart,
    );
    styles.setRange(
      destinationStart,
      destinationStart + columns,
      source._styles,
      sourceStart,
    );
    hyperlinks.setRange(
      destinationStart,
      destinationStart + columns,
      source._hyperlinks,
      sourceStart,
    );
    widthFlags.setRange(
      destinationStart,
      destinationStart + columns,
      source._widthFlags,
      sourceStart,
    );
    rowFlags[usedRows] = source._rowFlags[sourcePhysical];
    logicalLineIds[usedRows] = source._logicalLineIds[sourcePhysical];
    logicalLineEpochs[usedRows] = source._logicalLineEpochs[sourcePhysical];
    logicalCellOffsets[usedRows] = logicalOffset;
    logicalCellCounts[usedRows] = logicalCellCount;
    usedRows++;
  }

  void appendReflowRow(_ReflowRow row) {
    if (isFull) {
      throw StateError('full scrollback page append');
    }
    final int destinationStart = usedRows * columns;
    int column = 0;
    for (final _ReflowCell cell in row.cells) {
      final int index = destinationStart + column;
      final int width = cell.width;
      final int leadFlags =
          (width == 2 ? TerminalCellFlags.wide : TerminalCellFlags.narrow) |
          (cell.replacement ? 0 : cell.flags & TerminalCellFlags.grapheme) |
          (cell.flags & TerminalCellFlags.protected);
      content[index] = cell.content;
      foreground[index] = cell.foreground;
      background[index] = cell.background;
      styles[index] = cell.style;
      hyperlinks[index] = cell.hyperlink;
      widthFlags[index] = leadFlags;
      if (width == 2) {
        final int continuation = index + 1;
        content[continuation] = 0;
        foreground[continuation] = cell.foreground;
        background[continuation] = cell.background;
        styles[continuation] = cell.style;
        hyperlinks[continuation] = cell.hyperlink;
        widthFlags[continuation] =
            TerminalCellFlags.continuation |
            (cell.flags & TerminalCellFlags.protected);
      }
      column += width;
    }
    rowFlags[usedRows] = row.flags;
    logicalLineIds[usedRows] = row.logicalLineId;
    logicalLineEpochs[usedRows] = row.logicalLineEpoch;
    logicalCellOffsets[usedRows] = row.logicalOffset;
    logicalCellCounts[usedRows] = row.cells.length;
    usedRows++;
  }

  int rowExtent(int row) {
    final int start = row * columns;
    int extent = 0;
    for (int column = 0; column < columns; column++) {
      final int index = start + column;
      if (content[index] != 0 ||
          foreground[index] != 0 ||
          background[index] != 0 ||
          styles[index] != 0 ||
          hyperlinks[index] != 0 ||
          widthFlags[index] != TerminalCellFlags.narrow) {
        extent = column + 1;
      }
    }
    return extent;
  }

  int logicalCellCount(int row) => logicalCellCounts[row];

  int visibleLogicalCellCount(int row) {
    final int start = row * columns;
    final int extent = rowExtent(row);
    int count = 0;
    for (int column = 0; column < extent; column++) {
      if ((widthFlags[start + column] & TerminalCellFlags.widthMask) !=
          TerminalCellFlags.continuation) {
        count++;
      }
    }
    return count;
  }
}

final class _ScrollbackLocation {
  const _ScrollbackLocation(this.page, this.row);

  final _ScrollbackPage page;
  final int row;
}

int _minimum3(int first, int second, int third) {
  int result = first < second ? first : second;
  if (third < result) {
    result = third;
  }
  return result;
}
