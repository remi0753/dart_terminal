part of 'terminal_screen_set.dart';

/// One valid end-exclusive UTF-16 range in an accessibility document.
final class TerminalAccessibilityTextRange {
  TerminalAccessibilityTextRange({
    required this.location,
    required this.length,
  }) {
    if (location < 0 || length < 0 || location > 0x7fffffff - length) {
      throw RangeError('accessibility range must fit a signed 32-bit domain');
    }
  }

  final int location;
  final int length;

  int get end => location + length;
  bool get isCollapsed => length == 0;

  @override
  bool operator ==(Object other) =>
      other is TerminalAccessibilityTextRange &&
      other.location == location &&
      other.length == length;

  @override
  int get hashCode => Object.hash(location, length);

  @override
  String toString() => 'TerminalAccessibilityTextRange($location, $length)';
}

/// UTF-16 and terminal-column topology for one physical viewport row.
final class TerminalAccessibilityLine {
  TerminalAccessibilityLine._({
    required this.row,
    required this.utf16Start,
    required this.utf16Length,
    required List<int> columnUtf16Offsets,
  }) : columnUtf16Offsets = List<int>.unmodifiable(columnUtf16Offsets);

  final int row;
  final int utf16Start;
  final int utf16Length;

  /// Row-relative UTF-16 boundary for columns 0 through [representedColumns].
  ///
  /// A wide continuation shares the lead boundary. The next boundary after
  /// the complete cell reaches the end of the grapheme.
  final List<int> columnUtf16Offsets;

  int get representedColumns => columnUtf16Offsets.length - 1;
  TerminalAccessibilityTextRange get textRange =>
      TerminalAccessibilityTextRange(location: utf16Start, length: utf16Length);

  int utf16OffsetForColumn(int column) {
    RangeError.checkValueInInterval(column, 0, representedColumns, 'column');
    return utf16Start + columnUtf16Offsets[column];
  }
}

enum TerminalAccessibilityLimitKind {
  utf8Bytes,
  utf16CodeUnits,
  columnBoundaries,
}

final class TerminalAccessibilityLimitException implements Exception {
  const TerminalAccessibilityLimitException({
    required this.kind,
    required this.limit,
  });

  final TerminalAccessibilityLimitKind kind;
  final int limit;

  @override
  String toString() =>
      'TerminalAccessibilityLimitException(${kind.name}, limit=$limit)';
}

/// Immutable bounded text document for the currently visible terminal rows.
final class TerminalAccessibilitySnapshot {
  TerminalAccessibilitySnapshot._({
    required this.viewportGeneration,
    required this.rows,
    required this.columns,
    required this.text,
    required this.utf8Length,
    required this.utf16Length,
    required List<TerminalAccessibilityLine> lines,
    required this.selectedRange,
    required this.hasVisibleSelection,
    required this.cursorRange,
    required this.cursorRow,
    required this.cursorColumn,
  }) : lines = List<TerminalAccessibilityLine>.unmodifiable(lines);

  static const int defaultMaximumUtf8Bytes = 4 * 1024 * 1024;
  static const int maximumUtf8Bytes = 8 * 1024 * 1024;
  static const int defaultMaximumUtf16CodeUnits = 2 * 1024 * 1024;
  static const int maximumUtf16CodeUnits = 4 * 1024 * 1024;
  static const int defaultMaximumColumnBoundaries =
      TerminalScreen.maxCellCount + TerminalScreen.maxRows;
  static const int maximumColumnBoundaries =
      TerminalScreen.maxCellCount + TerminalScreen.maxRows;

  final int viewportGeneration;
  final int rows;
  final int columns;
  final String text;
  final int utf8Length;
  final int utf16Length;
  final List<TerminalAccessibilityLine> lines;

  /// Visible nonempty selection, or the collapsed visible cursor/fallback.
  final TerminalAccessibilityTextRange selectedRange;
  final bool hasVisibleSelection;
  final TerminalAccessibilityTextRange? cursorRange;
  final int? cursorRow;
  final int? cursorColumn;

  TerminalAccessibilityTextRange get visibleRange =>
      TerminalAccessibilityTextRange(location: 0, length: utf16Length);

  String get selectedText =>
      text.substring(selectedRange.location, selectedRange.end);

  factory TerminalAccessibilitySnapshot.capture(
    TerminalViewport viewport, {
    TerminalSelectionRange? selection,
    int maxUtf8Bytes = defaultMaximumUtf8Bytes,
    int maxUtf16CodeUnits = defaultMaximumUtf16CodeUnits,
    int maxColumnBoundaries = defaultMaximumColumnBoundaries,
  }) {
    RangeError.checkValueInInterval(
      maxUtf8Bytes,
      1,
      maximumUtf8Bytes,
      'maxUtf8Bytes',
    );
    RangeError.checkValueInInterval(
      maxUtf16CodeUnits,
      1,
      maximumUtf16CodeUnits,
      'maxUtf16CodeUnits',
    );
    RangeError.checkValueInInterval(
      maxColumnBoundaries,
      1,
      maximumColumnBoundaries,
      'maxColumnBoundaries',
    );

    final int viewportGeneration = viewport.generation;
    final int rows = viewport.rows;
    final int columns = viewport.columns;
    final TerminalSelectionProjection? projection = selection == null
        ? null
        : viewport.projectSelection(selection);
    final List<TerminalSelectionSpan?> spans =
        List<TerminalSelectionSpan?>.filled(rows, null);
    if (projection != null) {
      for (final TerminalSelectionSpan span in projection.spans) {
        spans[span.row] = span;
      }
    }
    final int? cursorRow = viewport.cursorVisible ? viewport.cursorRow : null;
    final int? cursorColumn = cursorRow == null ? null : viewport.cursorColumn;

    final StringBuffer output = StringBuffer();
    final List<TerminalAccessibilityLine> lines = <TerminalAccessibilityLine>[];
    var utf8Length = 0;
    var utf16Length = 0;
    var boundaryCount = 0;

    void addLengths(List<int> scalars) {
      for (final int scalar in scalars) {
        utf8Length += _accessibilityUtf8Length(scalar);
        utf16Length += scalar > 0xffff ? 2 : 1;
      }
      if (utf8Length > maxUtf8Bytes) {
        throw TerminalAccessibilityLimitException(
          kind: TerminalAccessibilityLimitKind.utf8Bytes,
          limit: maxUtf8Bytes,
        );
      }
      if (utf16Length > maxUtf16CodeUnits) {
        throw TerminalAccessibilityLimitException(
          kind: TerminalAccessibilityLimitKind.utf16CodeUnits,
          limit: maxUtf16CodeUnits,
        );
      }
    }

    for (var row = 0; row < rows; row++) {
      final int availableColumns = viewport.columnsAt(row).clamp(0, columns);
      var extent = 0;
      for (var column = 0; column < availableColumns; column++) {
        final int flags = viewport.widthFlagsAt(row, column);
        if ((flags & TerminalCellFlags.widthMask) ==
            TerminalCellFlags.continuation) {
          continue;
        }
        if (viewport.contentAt(row, column) != 0) {
          extent =
              column +
              ((flags & TerminalCellFlags.widthMask) == TerminalCellFlags.wide
                  ? 2
                  : 1);
        }
      }
      final TerminalSelectionSpan? span = spans[row];
      if (span != null) extent = _maxInt(extent, span.endColumn);
      if (cursorRow == row) extent = _maxInt(extent, cursorColumn!);
      extent = extent.clamp(0, availableColumns);
      boundaryCount += extent + 1;
      if (boundaryCount > maxColumnBoundaries) {
        throw TerminalAccessibilityLimitException(
          kind: TerminalAccessibilityLimitKind.columnBoundaries,
          limit: maxColumnBoundaries,
        );
      }

      final int lineStart = utf16Length;
      final List<int> offsets = List<int>.filled(extent + 1, 0);
      var column = 0;
      while (column < extent) {
        final int flags = viewport.widthFlagsAt(row, column);
        final int width = flags & TerminalCellFlags.widthMask;
        if (width == TerminalCellFlags.continuation) {
          offsets[column + 1] = utf16Length - lineStart;
          column++;
          continue;
        }
        final List<int> scalars = viewport._cellScalarsAt(row, column);
        final int before = utf16Length - lineStart;
        output.write(String.fromCharCodes(scalars));
        addLengths(scalars);
        final int after = utf16Length - lineStart;
        if (width == TerminalCellFlags.wide && column + 1 < extent) {
          offsets[column + 1] = before;
          offsets[column + 2] = after;
          column += 2;
        } else {
          offsets[column + 1] = after;
          column++;
        }
      }
      lines.add(
        TerminalAccessibilityLine._(
          row: row,
          utf16Start: lineStart,
          utf16Length: utf16Length - lineStart,
          columnUtf16Offsets: offsets,
        ),
      );
      if (row + 1 < rows) {
        output.writeCharCode(0x0a);
        addLengths(const <int>[0x0a]);
      }
    }

    TerminalAccessibilityTextRange? cursorRange;
    if (cursorRow != null && cursorColumn != null) {
      final TerminalAccessibilityLine line = lines[cursorRow];
      final int column = cursorColumn.clamp(0, line.representedColumns);
      cursorRange = TerminalAccessibilityTextRange(
        location: line.utf16OffsetForColumn(column),
        length: 0,
      );
    }

    TerminalAccessibilityTextRange? visibleSelection;
    if (projection != null && projection.spans.isNotEmpty) {
      final TerminalSelectionSpan first = projection.spans.first;
      final TerminalSelectionSpan last = projection.spans.last;
      final int start = lines[first.row].utf16OffsetForColumn(
        first.startColumn.clamp(0, lines[first.row].representedColumns),
      );
      final int end = lines[last.row].utf16OffsetForColumn(
        last.endColumn.clamp(0, lines[last.row].representedColumns),
      );
      if (end > start) {
        visibleSelection = TerminalAccessibilityTextRange(
          location: start,
          length: end - start,
        );
      }
    }
    final TerminalAccessibilityTextRange selectedRange =
        visibleSelection ??
        cursorRange ??
        TerminalAccessibilityTextRange(location: 0, length: 0);
    return TerminalAccessibilitySnapshot._(
      viewportGeneration: viewportGeneration,
      rows: rows,
      columns: columns,
      text: output.toString(),
      utf8Length: utf8Length,
      utf16Length: utf16Length,
      lines: lines,
      selectedRange: selectedRange,
      hasVisibleSelection: visibleSelection != null,
      cursorRange: cursorRange,
      cursorRow: cursorRange == null ? null : cursorRow,
      cursorColumn: cursorRange == null ? null : cursorColumn,
    );
  }
}

int _maxInt(int first, int second) => first >= second ? first : second;

int _accessibilityUtf8Length(int scalar) {
  if (scalar <= 0x7f) return 1;
  if (scalar <= 0x7ff) return 2;
  if (scalar <= 0xffff) return 3;
  return 4;
}
