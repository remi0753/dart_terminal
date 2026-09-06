import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSelectionGestureTests();

void runTerminalSelectionGestureTests() {
  _testInclusiveCellDragInBothDirections();
  _testWideCellDragNormalizesBothVisualHalves();
  _testWordAndLogicalLineClickUnits();
  _testGestureOwnershipAndPersistentRange();
  _testReflowRetentionAndInvalidation();
}

void _testWideCellDragNormalizesBothVisualHalves() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 8);
  screens.primary.setNarrowCell(0, 0, 0x41);
  screens.primary.setWideCell(0, 1, 0x65e5);
  screens.primary.setWideCell(0, 3, 0x672c);
  screens.primary.setWideCell(0, 5, 0x8a9e);
  screens.primary.setNarrowCell(0, 7, 0x42);
  screens.primary.setRowFlags(0, TerminalRowFlags.hardBreak);
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);

  for (final (int, String) expectation in <(int, String)>[
    (1, '日'),
    (2, '日'),
    (3, '本'),
    (4, '本'),
    (5, '語'),
    (6, '語'),
  ]) {
    gesture.handle(
      _intent(
        TerminalLocalSelectionPhase.begin,
        row: 0,
        column: expectation.$1,
      ),
    );
    final TerminalSelectionGestureUpdate ended = gesture.handle(
      _intent(TerminalLocalSelectionPhase.end, row: 0, column: expectation.$1),
    );
    _expect(
      _text(screens.viewport, ended.snapshot.range!) == expectation.$2,
      'either terminal cell of a wide grapheme selects that grapheme alone',
    );
  }

  gesture.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 2));
  final TerminalSelectionGestureUpdate forward = gesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 5),
  );
  final TerminalSelectionProjection forwardProjection = screens.viewport
      .projectSelection(forward.snapshot.range!)!;
  _expect(
    _text(screens.viewport, forward.snapshot.range!) == '日本語' &&
        forwardProjection.spans.single.startColumn == 1 &&
        forwardProjection.spans.single.endColumn == 7,
    'forward wide drag copies and highlights the same three graphemes',
  );

  gesture.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 6));
  final TerminalSelectionGestureUpdate reverse = gesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 1),
  );
  _expect(
    reverse.snapshot.range!.isReversed &&
        _text(screens.viewport, reverse.snapshot.range!) == '日本語',
    'reverse wide drag preserves the same indivisible grapheme range',
  );
}

void _testInclusiveCellDragInBothDirections() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  _setText(screens.primary, 0, 'abcdef');
  _setText(screens.primary, 1, 'ghijkl');
  screens.primary.setRowFlags(0, TerminalRowFlags.hardBreak);
  screens.primary.setRowFlags(1, TerminalRowFlags.hardBreak);
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);

  final TerminalSelectionGestureUpdate began = gesture.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 2),
  );
  final TerminalSelectionGestureSnapshot beginSnapshot = began.snapshot;
  final TerminalSelectionGestureUpdate ended = gesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 1, column: 1),
  );
  _expect(
    began.outcome == TerminalSelectionGestureOutcome.began &&
        beginSnapshot.isActive &&
        _text(screens.viewport, beginSnapshot.range!) == 'c' &&
        ended.outcome == TerminalSelectionGestureOutcome.ended &&
        !ended.snapshot.isActive &&
        ended.snapshot.unit == TerminalSelectionUnit.cell &&
        _text(screens.viewport, ended.snapshot.range!) == 'cdef\ngh' &&
        beginSnapshot.generation < ended.snapshot.generation &&
        _text(screens.viewport, beginSnapshot.range!) == 'c',
    'forward cell drag includes both pointer cells and snapshots stay immutable',
  );

  gesture.handle(_intent(TerminalLocalSelectionPhase.begin, row: 1, column: 1));
  final TerminalSelectionGestureUpdate reversed = gesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 2),
  );
  _expect(
    reversed.snapshot.range!.isReversed &&
        _text(screens.viewport, reversed.snapshot.range!) == 'cdef\ngh',
    'reverse cell drag is inclusive and normalizes to the same text',
  );
}

void _testWordAndLogicalLineClickUnits() {
  final TerminalScreenSet words = TerminalScreenSet(rows: 2, columns: 8);
  _setText(words.primary, 0, 'foo bar');
  final TerminalSelectionGestureController wordGesture =
      TerminalSelectionGestureController(viewport: words.viewport);
  wordGesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 1,
      clickCount: 2,
    ),
  );
  _expect(
    wordGesture.snapshot.unit == TerminalSelectionUnit.word &&
        _text(words.viewport, wordGesture.snapshot.range!) == 'foo',
    'double click delegates word boundaries to the viewport',
  );
  wordGesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 5),
  );
  _expect(
    _text(words.viewport, wordGesture.snapshot.range!) == 'foo bar',
    'word drag expands both endpoint words',
  );

  final TerminalScreenSet lines = TerminalScreenSet(rows: 2, columns: 4);
  _setText(lines.primary, 0, 'ABCD');
  _setText(lines.primary, 1, 'EFG');
  lines.primary.setRowFlags(0, TerminalRowFlags.softWrapped);
  lines.primary.setRowFlags(1, TerminalRowFlags.hardBreak);
  lines.primary.setLogicalLineId(0, 77);
  lines.primary.setLogicalLineId(1, 77);
  final TerminalSelectionGestureController lineGesture =
      TerminalSelectionGestureController(viewport: lines.viewport);
  lineGesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 1,
      column: 1,
      clickCount: 3,
    ),
  );
  _expect(
    lineGesture.snapshot.unit == TerminalSelectionUnit.logicalLine &&
        _text(lines.viewport, lineGesture.snapshot.range!) == 'ABCDEFG',
    'triple click uses soft-wrap-aware logical-line semantics',
  );
}

void _testGestureOwnershipAndPersistentRange() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 5);
  _setText(screens.primary, 0, 'abcde');
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  final TerminalSelectionGestureUpdate inactiveUpdate = gesture.handle(
    _intent(TerminalLocalSelectionPhase.update, row: 0, column: 2),
  );
  final TerminalSelectionGestureUpdate rightBegin = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 1,
      button: TerminalMouseButton.right,
    ),
  );
  final TerminalSelectionGestureUpdate zeroClick = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 1,
      clickCount: 0,
    ),
  );
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 1,
      edge: TerminalPointerVerticalEdge.above,
    ),
  );
  final TerminalSelectionGestureUpdate update = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.update,
      row: 0,
      column: 3,
      edge: TerminalPointerVerticalEdge.below,
    ),
  );
  final int beforeWrongEnd = gesture.snapshot.generation;
  final TerminalSelectionGestureUpdate wrongEnd = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.end,
      row: 0,
      column: 3,
      button: TerminalMouseButton.middle,
    ),
  );
  final TerminalSelectionGestureUpdate end = gesture.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 3),
  );
  _expect(
    inactiveUpdate.outcome == TerminalSelectionGestureOutcome.ignored &&
        rightBegin.outcome == TerminalSelectionGestureOutcome.ignored &&
        zeroClick.outcome == TerminalSelectionGestureOutcome.ignored &&
        update.snapshot.verticalEdge == TerminalPointerVerticalEdge.below &&
        wrongEnd.outcome == TerminalSelectionGestureOutcome.ignored &&
        wrongEnd.snapshot.generation == beforeWrongEnd &&
        end.snapshot.verticalEdge == TerminalPointerVerticalEdge.inside &&
        !end.snapshot.isActive &&
        _text(screens.viewport, end.snapshot.range!) == 'bcd',
    'only a valid primary gesture mutates and mouse-up retains its range',
  );
  _expect(
    gesture.clear().outcome == TerminalSelectionGestureOutcome.cleared &&
        !gesture.snapshot.hasSelection &&
        gesture.clear().outcome == TerminalSelectionGestureOutcome.ignored,
    'clear removes persistent selection exactly once',
  );
}

void _testReflowRetentionAndInvalidation() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 2, maxBytes: 1000, pageRows: 1),
  );
  for (final int scalar in 'abcdef'.runes) {
    screens.primary.printScalar(scalar);
  }
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  gesture.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 1));
  gesture.handle(_intent(TerminalLocalSelectionPhase.end, row: 1, column: 1));
  final String before = _text(screens.viewport, gesture.snapshot.range!);
  screens.resize(rows: 3, columns: 3);
  final TerminalSelectionGestureUpdate retained = gesture.synchronize();
  _expect(
    retained.outcome == TerminalSelectionGestureOutcome.ignored &&
        gesture.snapshot.hasSelection &&
        _text(screens.viewport, gesture.snapshot.range!) == before,
    'retained stable anchors survive screen reflow',
  );

  screens.setAlternateMode47(true);
  final TerminalSelectionGestureUpdate switched = gesture.synchronize();
  _expect(
    switched.outcome == TerminalSelectionGestureOutcome.cancelled &&
        !gesture.snapshot.hasSelection,
    'screen-kind transition cancels an unavailable selection',
  );

  screens.setAlternateMode47(false);
  _setText(screens.primary, 0, 'XYZ');
  gesture.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 0));
  screens.primary.scrollUp(3);
  screens.scrollback.clear();
  final TerminalSelectionGestureUpdate evicted = gesture.synchronize();
  _expect(
    evicted.outcome == TerminalSelectionGestureOutcome.cancelled &&
        !gesture.snapshot.isActive &&
        !gesture.snapshot.hasSelection,
    'history eviction cancels active stale anchors',
  );
}

TerminalLocalSelectionIntent _intent(
  TerminalLocalSelectionPhase phase, {
  required int row,
  required int column,
  int clickCount = 1,
  TerminalMouseButton button = TerminalMouseButton.left,
  TerminalPointerVerticalEdge edge = TerminalPointerVerticalEdge.inside,
}) => TerminalLocalSelectionIntent(
  phase: phase,
  cell: TerminalPointerCell(row: row, column: column),
  button: button,
  clickCount: clickCount,
  modifiers: const ModifierKeys(0),
  verticalEdge: edge,
);

void _setText(TerminalScreen screen, int row, String text) {
  var column = 0;
  for (final int scalar in text.runes) {
    screen.setNarrowCell(row, column++, scalar);
  }
}

String _text(TerminalViewport viewport, TerminalSelectionRange range) {
  final TerminalSelectionText? extracted = viewport.extractSelection(range);
  if (extracted == null) throw StateError('selection unexpectedly unavailable');
  return extracted.text;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
