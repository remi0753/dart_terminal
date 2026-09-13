import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSelectionGestureTests();

void runTerminalSelectionGestureTests() {
  _testInclusiveCellDragInBothDirections();
  _testWideCellDragNormalizesBothVisualHalves();
  _testWordAndLogicalLineClickUnits();
  _testSemanticTripleClickUnitsAndDragging();
  _testSemanticOutputGestureRejectsStaleAndNonOutputTargets();
  _testGestureOwnershipAndPersistentRange();
  _testTransientCancellationPreservesSelection();
  _testReflowRetentionAndInvalidation();
}

void _testSemanticTripleClickUnitsAndDragging() {
  final _SemanticHarness sameLine = _SemanticHarness(rows: 2, columns: 20);
  sameLine
    ..parse(_osc('A'))
    ..parse(r'$ ')
    ..parse(_osc('B'))
    ..parse('echo')
    ..parse(_osc('C'))
    ..parse('result')
    ..parse(_osc('D'));
  final TerminalSelectionGestureController lines =
      TerminalSelectionGestureController(viewport: sameLine.screens.viewport);
  for (final (int, String) expected in <(int, String)>[
    (0, r'$ '),
    (3, 'echo'),
    (8, 'result'),
  ]) {
    final TerminalSelectionGestureUpdate began = lines.handle(
      _intent(
        TerminalLocalSelectionPhase.begin,
        row: 0,
        column: expected.$1,
        clickCount: 3,
      ),
    );
    _expect(
      began.snapshot.unit == TerminalSelectionUnit.logicalLine &&
          _text(sameLine.screens.viewport, began.snapshot.range!) ==
              expected.$2,
      'ordinary triple-click stays inside its semantic segment',
    );
    lines.clear();
  }
  lines.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 8,
      clickCount: 3,
    ),
  );
  final TerminalSelectionGestureUpdate withinOutput = lines.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 10, clickCount: 3),
  );
  _expect(
    _text(sameLine.screens.viewport, withinOutput.snapshot.range!) == 'result',
    'ordinary triple-click drag within one semantic segment stays clamped',
  );

  final _SemanticHarness blocks = _twoOutputBlocks();
  final TerminalSelectionGestureController output =
      TerminalSelectionGestureController(viewport: blocks.screens.viewport);
  final TerminalSelectionGestureUpdate began = output.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 1,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  final TerminalSelectionGestureUpdate expanded = output.handle(
    _intent(
      TerminalLocalSelectionPhase.update,
      row: 3,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  final String expandedText = _text(
    blocks.screens.viewport,
    expanded.snapshot.range!,
  );
  _expect(
    began.snapshot.unit == TerminalSelectionUnit.semanticOutput &&
        _text(blocks.screens.viewport, began.snapshot.range!) == 'out1' &&
        expandedText.startsWith('out1') &&
        expandedText.endsWith('out2') &&
        expandedText.contains(r'$ two'),
    'Control triple-click and drag select complete output blocks',
  );

  output.clear();
  final TerminalSelectionGestureUpdate command = output.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 3,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.commandBit),
    ),
  );
  final TerminalSelectionGestureUpdate reverse = output.handle(
    _intent(
      TerminalLocalSelectionPhase.end,
      row: 1,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.commandBit),
    ),
  );
  _expect(
    command.snapshot.unit == TerminalSelectionUnit.semanticOutput &&
        reverse.snapshot.range!.isReversed &&
        _text(blocks.screens.viewport, reverse.snapshot.range!) == expandedText,
    'Command triple-click uses Super semantics and preserves reverse output drag',
  );
}

void _testSemanticOutputGestureRejectsStaleAndNonOutputTargets() {
  final _SemanticHarness harness = _twoOutputBlocks();
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: harness.screens.viewport);
  final TerminalSelectionGestureUpdate prompt = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 0,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  _expect(
    prompt.outcome == TerminalSelectionGestureOutcome.ignored &&
        !prompt.snapshot.hasSelection,
    'semantic output gesture is inert on prompt and input cells',
  );

  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 1,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  final TerminalSelectionRange original = gesture.snapshot.range!;
  final TerminalSelectionGestureUpdate held = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.update,
      row: 2,
      column: 1,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  _expect(
    held.snapshot.range!.start == original.start &&
        held.snapshot.range!.end == original.end &&
        held.snapshot.isActive,
    'dragging across a non-output target keeps the originating output block',
  );
  harness.screens.setAlternateMode47(true);
  final TerminalSelectionGestureUpdate stale = gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.update,
      row: 0,
      column: 0,
      clickCount: 3,
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  );
  _expect(
    stale.outcome == TerminalSelectionGestureOutcome.cancelled &&
        !stale.snapshot.hasSelection &&
        !stale.snapshot.isActive,
    'a stale semantic output gesture cancels instead of retaining old anchors',
  );
}

void _testTransientCancellationPreservesSelection() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 6);
  _setText(screens.primary, 0, 'abcdef');
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 1,
      edge: TerminalPointerVerticalEdge.below,
    ),
  );
  final int generation = gesture.snapshot.generation;
  final TerminalSelectionGestureUpdate cancelled = gesture.cancelInteraction();
  _expect(
    cancelled.outcome == TerminalSelectionGestureOutcome.ended &&
        cancelled.snapshot.generation == generation + 1 &&
        !cancelled.snapshot.isActive &&
        cancelled.snapshot.verticalEdge == TerminalPointerVerticalEdge.inside &&
        _text(screens.viewport, cancelled.snapshot.range!) == 'b',
    'transient cancellation did not preserve the stable selection range',
  );
  _expect(
    gesture.cancelInteraction().outcome ==
        TerminalSelectionGestureOutcome.ignored,
    'inactive transient cancellation changed selection again',
  );
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
  ModifierKeys modifiers = const ModifierKeys(0),
}) => TerminalLocalSelectionIntent(
  phase: phase,
  cell: TerminalPointerCell(row: row, column: column),
  button: button,
  clickCount: clickCount,
  modifiers: modifiers,
  verticalEdge: edge,
);

_SemanticHarness _twoOutputBlocks() {
  final _SemanticHarness harness = _SemanticHarness(rows: 6, columns: 12);
  harness
    ..parse(_osc('A'))
    ..parse(r'$ ')
    ..parse(_osc('B'))
    ..parse('one')
    ..parse(_osc('C'))
    ..parse('\r\nout1')
    ..parse(_osc('D'))
    ..parse(_osc('A'))
    ..parse(r'$ ')
    ..parse(_osc('B'))
    ..parse('two')
    ..parse(_osc('C'))
    ..parse('\r\nout2')
    ..parse(_osc('D'));
  return harness;
}

String _osc(String payload) => '\x1b]133;$payload\x07';

final class _SemanticHarness {
  _SemanticHarness({required int rows, required int columns})
    : screens = TerminalScreenSet(rows: rows, columns: columns) {
    parser = VtParser(sink: TerminalScreenParserSink.forScreenSet(screens));
  }

  final TerminalScreenSet screens;
  late final VtParser parser;

  void parse(String value) =>
      parser.parse(Uint8List.fromList(utf8.encode(value)));
}

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
