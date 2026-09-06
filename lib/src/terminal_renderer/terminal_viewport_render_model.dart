import 'dart:typed_data';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_screen_set.dart';
import 'terminal_render_model.dart';

/// Bounded copied projection of the currently visible history/screen viewport.
final class TerminalViewportRenderModel implements TerminalRenderModel {
  TerminalViewportRenderModel._({
    required this.viewportGeneration,
    required this.requiredResourceGeneration,
    required this.rows,
    required this.columns,
    required this.cursorRow,
    required this.cursorColumn,
    required this.cursorShape,
    required this.cursorVisible,
    required Uint32List content,
    required Uint32List foreground,
    required Uint32List background,
    required Uint16List styles,
    required Uint8List widthFlags,
  }) : _content = content,
       _foreground = foreground,
       _background = background,
       _styles = styles,
       _widthFlags = widthFlags;

  factory TerminalViewportRenderModel.capture(
    TerminalViewport viewport, {
    required TerminalScreen activeScreen,
    required int requiredResourceGeneration,
  }) {
    if (requiredResourceGeneration <= 0 ||
        requiredResourceGeneration > 0x7fffffffffffffff) {
      throw RangeError.range(
        requiredResourceGeneration,
        1,
        0x7fffffffffffffff,
        'requiredResourceGeneration',
      );
    }
    final int rows = viewport.rows;
    final int columns = viewport.columns;
    validateTerminalScreenDimensions(rows, columns);
    if (activeScreen.rows != rows || activeScreen.columns != columns) {
      throw ArgumentError('viewport and active screen dimensions differ');
    }
    final int cellCount = rows * columns;
    final Uint32List content = Uint32List(cellCount);
    final Uint32List foreground = Uint32List(cellCount);
    final Uint32List background = Uint32List(cellCount);
    final Uint16List styles = Uint16List(cellCount);
    final Uint8List widthFlags = Uint8List(cellCount);
    for (int row = 0; row < rows; row++) {
      final int sourceColumns = viewport.columnsAt(row);
      final int copiedColumns = sourceColumns.clamp(0, columns);
      for (int column = 0; column < copiedColumns; column++) {
        final int flags = viewport.widthFlagsAt(row, column);
        final int width = flags & TerminalCellFlags.widthMask;
        if ((width == TerminalCellFlags.wide && column + 1 >= columns) ||
            (width == TerminalCellFlags.continuation &&
                (column == 0 ||
                    (viewport.widthFlagsAt(row, column - 1) &
                            TerminalCellFlags.widthMask) !=
                        TerminalCellFlags.wide))) {
          continue;
        }
        final int index = row * columns + column;
        content[index] = viewport.contentAt(row, column);
        foreground[index] = viewport.foregroundAt(row, column);
        background[index] = viewport.backgroundAt(row, column);
        styles[index] = viewport.styleAt(row, column);
        widthFlags[index] = flags;
      }
    }
    final int? projectedCursorRow = viewport.cursorRow;
    return TerminalViewportRenderModel._(
      viewportGeneration: viewport.generation,
      requiredResourceGeneration: requiredResourceGeneration,
      rows: rows,
      columns: columns,
      cursorRow: projectedCursorRow ?? 0,
      cursorColumn: projectedCursorRow == null ? 0 : viewport.cursorColumn!,
      cursorShape: activeScreen.cursorShape,
      cursorVisible: projectedCursorRow != null && activeScreen.cursorVisible,
      content: content,
      foreground: foreground,
      background: background,
      styles: styles,
      widthFlags: widthFlags,
    );
  }

  final int viewportGeneration;
  @override
  final int requiredResourceGeneration;
  @override
  final int rows;
  @override
  final int columns;
  @override
  final int cursorRow;
  @override
  final int cursorColumn;
  @override
  final TerminalCursorShape cursorShape;
  @override
  final bool cursorVisible;
  final Uint32List _content;
  final Uint32List _foreground;
  final Uint32List _background;
  final Uint16List _styles;
  final Uint8List _widthFlags;

  @override
  bool get isInitialized => true;

  @override
  int contentAt(int row, int column) => _content[_index(row, column)];
  @override
  int foregroundAt(int row, int column) => _foreground[_index(row, column)];
  @override
  int backgroundAt(int row, int column) => _background[_index(row, column)];
  @override
  int styleAt(int row, int column) => _styles[_index(row, column)];
  @override
  int widthFlagsAt(int row, int column) => _widthFlags[_index(row, column)];

  int _index(int row, int column) {
    RangeError.checkValueInInterval(row, 0, rows - 1, 'row');
    RangeError.checkValueInInterval(column, 0, columns - 1, 'column');
    return row * columns + column;
  }
}
