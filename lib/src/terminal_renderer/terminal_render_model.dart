import '../terminal_core/terminal_screen.dart';

/// Minimum immutable/read-only grid contract consumed by terminal composition.
abstract interface class TerminalRenderModel {
  bool get isInitialized;
  int get requiredResourceGeneration;
  int get rows;
  int get columns;
  int get cursorRow;
  int get cursorColumn;
  TerminalCursorShape get cursorShape;
  bool get cursorVisible;

  int contentAt(int row, int column);
  int foregroundAt(int row, int column);
  int backgroundAt(int row, int column);
  int styleAt(int row, int column);
  int hyperlinkAt(int row, int column);
  int widthFlagsAt(int row, int column);
}
