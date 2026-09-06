import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalViewportRenderModelTests();

void runTerminalViewportRenderModelTests() {
  _testHistoryProjectionCopiesEveryRenderField();
  _testSelectionProjectionClipsWideCellsAndViewport();
  _testProjectionValidation();
}

void _testHistoryProjectionCopiesEveryRenderField() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 1),
  );
  for (int row = 0; row < 3; row++) {
    screens.primary.setNarrowCell(
      row,
      0,
      0x41 + row,
      foreground: row + 1,
      background: row + 4,
      style: row + 7,
      isProtected: true,
    );
  }
  screens.primary.scrollUp(3);
  for (int row = 0; row < 3; row++) {
    screens.primary.setNarrowCell(row, 0, 0x44 + row);
  }
  screens.primary.setCursorPosition(0, 2);
  screens.viewport.scrollByRows(1);
  final TerminalViewportRenderModel visible =
      TerminalViewportRenderModel.capture(
        screens.viewport,
        activeScreen: screens.activeScreen,
        requiredResourceGeneration: 9,
      );
  _expect(
    visible.isInitialized &&
        visible.viewportGeneration == screens.viewport.generation &&
        visible.requiredResourceGeneration == 9 &&
        visible.rows == 3 &&
        visible.columns == 4 &&
        visible.contentAt(0, 0) == 0x43 &&
        visible.foregroundAt(0, 0) == 3 &&
        visible.backgroundAt(0, 0) == 6 &&
        visible.styleAt(0, 0) == 9 &&
        visible.widthFlagsAt(0, 0) ==
            TerminalCellFlags.narrow | TerminalCellFlags.protected &&
        visible.contentAt(1, 0) == 0x44 &&
        visible.cursorVisible &&
        visible.cursorRow == 1 &&
        visible.cursorColumn == 2,
    'scrolled snapshot copies history/screen fields and projects the cursor',
  );
  screens.primary.setNarrowCell(0, 0, 0x5a);
  _expect(
    visible.contentAt(1, 0) == 0x44,
    'viewport render snapshot does not alias mutable terminal cells',
  );
  screens.viewport.scrollToTop();
  final TerminalViewportRenderModel oldest =
      TerminalViewportRenderModel.capture(
        screens.viewport,
        activeScreen: screens.activeScreen,
        requiredResourceGeneration: 9,
      );
  _expect(
    !oldest.cursorVisible && oldest.cursorRow == 0 && oldest.cursorColumn == 0,
    'offscreen cursor is hidden with bounded placeholder coordinates',
  );
}

void _testSelectionProjectionClipsWideCellsAndViewport() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  _setText(screens.primary, 0, 'abcdef');
  screens.primary.setNarrowCell(1, 0, 0x41);
  screens.primary.setWideCell(1, 1, 0x754c);
  screens.primary.setNarrowCell(1, 3, 0x42);
  screens.primary.setRowFlags(0, TerminalRowFlags.hardBreak);
  screens.primary.setRowFlags(1, TerminalRowFlags.hardBreak);
  final TerminalSelectionRange range = screens.viewport.selectionRange(
    screens.viewport.anchorAt(0, 4),
    screens.viewport.anchorAfter(1, 1),
  )!;
  final TerminalSelectionProjection projection = screens.viewport
      .projectSelection(range)!;
  _expect(
    projection.spans.length == 2 &&
        projection.spans[0].row == 0 &&
        projection.spans[0].startColumn == 4 &&
        projection.spans[0].endColumn == 6 &&
        projection.spans[1].row == 1 &&
        projection.spans[1].startColumn == 0 &&
        projection.spans[1].endColumn == 3 &&
        projection.selectedCellCount == 5,
    'selection projection uses physical spans without splitting a wide cell',
  );

  screens.primary.scrollUp(2);
  screens.viewport.scrollToBottom();
  final TerminalSelectionProjection offscreen = screens.viewport
      .projectSelection(range)!;
  _expect(
    offscreen.isEmpty,
    'retained selection outside the current viewport yields no visible spans',
  );
  screens.setAlternateMode47(true);
  _expect(
    screens.viewport.projectSelection(range) == null,
    'selection projection rejects a different active screen kind',
  );
}

void _testProjectionValidation() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 2);
  _expectThrows<RangeError>(
    () => TerminalViewportRenderModel.capture(
      screens.viewport,
      activeScreen: screens.activeScreen,
      requiredResourceGeneration: 0,
    ),
    'resource generation is positive and bounded',
  );
  _expectThrows<ArgumentError>(
    () => TerminalViewportRenderModel.capture(
      screens.viewport,
      activeScreen: TerminalScreen(rows: 2, columns: 2),
      requiredResourceGeneration: 1,
    ),
    'active screen dimensions must match the viewport',
  );
  _expectThrows<ArgumentError>(
    () => TerminalSelectionSpan(row: 0, startColumn: 1, endColumn: 1),
    'public selection spans cannot be empty',
  );
}

void _setText(TerminalScreen screen, int row, String text) {
  var column = 0;
  for (final int scalar in text.runes) {
    screen.setNarrowCell(row, column++, scalar);
  }
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
