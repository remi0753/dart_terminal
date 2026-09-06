import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalAccessibilitySnapshotTests();

void runTerminalAccessibilitySnapshotTests() {
  _testUnicodeColumnAndCursorMapping();
  _testVisibleSelectionAndPhysicalLines();
  _testHistoryAlternateAndHiddenCursor();
  _testBoundsAndGeneration();
}

void _testUnicodeColumnAndCursorMapping() {
  final TerminalGraphemeTable graphemes = TerminalGraphemeTable();
  final int combining = graphemes.tryIntern(const <int>[0x65, 0x301])!;
  final int emoji = graphemes.tryIntern(const <int>[0x1f469, 0x200d, 0x1f4bb])!;
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 8,
    graphemeTable: graphemes,
  );
  final TerminalScreen screen = screens.primary;
  screen
    ..setNarrowCell(0, 0, 0x41)
    ..setWideCell(0, 1, 0x754c)
    ..setGraphemeCell(0, 3, combining)
    ..setGraphemeCell(0, 4, emoji)
    ..setCursorPosition(1, 3);

  final TerminalAccessibilitySnapshot snapshot =
      TerminalAccessibilitySnapshot.capture(screens.viewport);
  _expect(
    snapshot.text == 'A界e\u0301👩‍💻\n   \n' &&
        snapshot.utf16Length == snapshot.text.length &&
        snapshot.utf8Length == 23 &&
        snapshot.lines.length == 3,
    'snapshot preserves Unicode and trims only irrelevant trailing blanks',
  );
  _expect(
    _offsets(snapshot.lines[0]) == '0,1,1,2,4,4,9' &&
        snapshot.lines[0].representedColumns == 6,
    'wide and grapheme columns map to indivisible UTF-16 boundaries',
  );
  _expect(
    snapshot.cursorRow == 1 &&
        snapshot.cursorColumn == 3 &&
        snapshot.cursorRange ==
            TerminalAccessibilityTextRange(location: 13, length: 0) &&
        snapshot.selectedRange == snapshot.cursorRange &&
        !snapshot.hasVisibleSelection,
    'visible cursor is the collapsed selection when no text is selected',
  );
}

void _testVisibleSelectionAndPhysicalLines() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 5);
  final TerminalScreen screen = screens.primary;
  screen
    ..setWideCell(0, 0, 0x754c)
    ..setNarrowCell(0, 2, 0x41)
    ..setRowFlags(0, TerminalRowFlags.softWrapped)
    ..setNarrowCell(1, 0, 0x42)
    ..setCursorPosition(2, 0);
  final TerminalViewport viewport = screens.viewport;
  final TerminalSelectionRange selection = viewport.selectionRange(
    viewport.anchorAt(0, 0),
    viewport.anchorAfter(1, 1),
  )!;
  final TerminalAccessibilitySnapshot snapshot =
      TerminalAccessibilitySnapshot.capture(viewport, selection: selection);

  _expect(
    snapshot.text == '界A\nB\n' &&
        snapshot.hasVisibleSelection &&
        snapshot.selectedRange ==
            TerminalAccessibilityTextRange(location: 0, length: 4) &&
        snapshot.selectedText == '界A\nB',
    'selection clips through physical soft-wrap rows using one text range',
  );
  _expect(
    snapshot.cursorRange ==
        TerminalAccessibilityTextRange(location: 5, length: 0),
    'selection does not replace independently reported cursor position',
  );
}

void _testHistoryAlternateAndHiddenCursor() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 3);
  screens.primary
    ..setNarrowCell(0, 0, 0x41)
    ..setNarrowCell(1, 0, 0x42)
    ..scrollUp(1)
    ..setNarrowCell(1, 0, 0x43)
    ..setCursorPosition(1, 1);
  screens.viewport.scrollToTop();
  TerminalAccessibilitySnapshot snapshot =
      TerminalAccessibilitySnapshot.capture(screens.viewport);
  _expect(
    snapshot.text == 'A\nB' && snapshot.cursorRange == null,
    'history viewport exposes only visible rows and hides an offscreen cursor',
  );

  screens.setAlternateMode47(true);
  screens.alternate
    ..setNarrowCell(0, 0, 0x58)
    ..setCursorPosition(1, 2)
    ..setCursorPresentation(visible: false);
  snapshot = TerminalAccessibilitySnapshot.capture(screens.viewport);
  _expect(
    snapshot.text == 'X\n' &&
        snapshot.cursorRange == null &&
        snapshot.cursorRow == null &&
        snapshot.selectedRange.isCollapsed,
    'alternate content is isolated and a hidden cursor is not exposed',
  );
}

void _testBoundsAndGeneration() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  screens.primary
    ..printScalar(0x1f600)
    ..printScalar(0x41);
  final TerminalAccessibilitySnapshot before =
      TerminalAccessibilitySnapshot.capture(screens.viewport);
  _expectLimit(
    () => TerminalAccessibilitySnapshot.capture(
      screens.viewport,
      maxUtf8Bytes: 4,
    ),
    TerminalAccessibilityLimitKind.utf8Bytes,
  );
  _expectLimit(
    () => TerminalAccessibilitySnapshot.capture(
      screens.viewport,
      maxUtf16CodeUnits: 2,
    ),
    TerminalAccessibilityLimitKind.utf16CodeUnits,
  );
  _expectLimit(
    () => TerminalAccessibilitySnapshot.capture(
      screens.viewport,
      maxColumnBoundaries: 2,
    ),
    TerminalAccessibilityLimitKind.columnBoundaries,
  );
  screens.primary.setNarrowCell(0, 3, 0x42);
  final TerminalAccessibilitySnapshot after =
      TerminalAccessibilitySnapshot.capture(screens.viewport);
  _expect(
    after.viewportGeneration > before.viewportGeneration &&
        after.text == '😀AB',
    'snapshot identifies the exact viewport generation it captured',
  );
}

String _offsets(TerminalAccessibilityLine line) =>
    line.columnUtf16Offsets.join(',');

void _expectLimit(
  void Function() callback,
  TerminalAccessibilityLimitKind kind,
) {
  try {
    callback();
  } on TerminalAccessibilityLimitException catch (error) {
    _expect(error.kind == kind, 'limit exception retains its category');
    return;
  }
  throw StateError('expected ${kind.name} accessibility limit');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
