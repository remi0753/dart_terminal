import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSelectionAutoscrollTests();

void runTerminalSelectionAutoscrollTests() {
  _testOneDeadlineAndNoCatchUp();
  _testDirectionReversalAndStop();
  _testExplicitCancellationDropsDeadline();
  _testBoundsAlternateAndValidation();
}

void _testExplicitCancellationDropsDeadline() {
  final TerminalScreenSet screens = _historyScreens();
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  final TerminalSelectionAutoscroller autoscroll =
      TerminalSelectionAutoscroller(gesture: gesture);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      edge: TerminalPointerVerticalEdge.above,
    ),
  );
  autoscroll.observeGesture(monotonicMicros: 1);
  _expect(
    autoscroll.nextDeadlineMicros != null,
    'fixture did not arm an autoscroll deadline',
  );
  autoscroll.cancel();
  _expect(
    autoscroll.nextDeadlineMicros == null,
    'explicit cancellation retained an autoscroll deadline',
  );
}

void _testOneDeadlineAndNoCatchUp() {
  final TerminalScreenSet screens = _historyScreens();
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  final TerminalSelectionAutoscroller autoscroll =
      TerminalSelectionAutoscroller(gesture: gesture);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      edge: TerminalPointerVerticalEdge.above,
    ),
  );
  final TerminalSelectionAutoscrollUpdate armed = autoscroll.observeGesture(
    monotonicMicros: 1000,
  );
  final TerminalSelectionAutoscrollUpdate waiting = autoscroll.advance(
    monotonicMicros: 50999,
  );
  final TerminalSelectionAutoscrollUpdate first = autoscroll.advance(
    monotonicMicros: 51000,
  );
  final int firstGeneration = gesture.snapshot.generation;
  final TerminalSelectionAutoscrollUpdate late = autoscroll.advance(
    monotonicMicros: 251000,
  );
  _expect(
    armed.outcome == TerminalSelectionAutoscrollOutcome.armed &&
        armed.nextDeadlineMicros == 51000 &&
        waiting.outcome == TerminalSelectionAutoscrollOutcome.waiting &&
        first.didScroll &&
        screens.viewport.offset == 2 &&
        first.tickCount == 1 &&
        late.didScroll &&
        late.tickCount == 2 &&
        late.scrolledRowCount == 2 &&
        late.nextDeadlineMicros == 301000 &&
        gesture.snapshot.generation == firstGeneration + 1,
    'each due call scrolls once and a late call never catches up',
  );
}

void _testDirectionReversalAndStop() {
  final TerminalScreenSet screens = _historyScreens();
  screens.viewport.scrollByRows(2);
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  final TerminalSelectionAutoscroller autoscroll =
      TerminalSelectionAutoscroller(gesture: gesture);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 2,
      edge: TerminalPointerVerticalEdge.below,
    ),
  );
  autoscroll.observeGesture(monotonicMicros: 10);
  autoscroll.advance(monotonicMicros: 50010);
  _expect(screens.viewport.offset == 1, 'below drag moves toward live output');
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.update,
      row: 0,
      edge: TerminalPointerVerticalEdge.above,
    ),
  );
  final TerminalSelectionAutoscrollUpdate reversed = autoscroll.observeGesture(
    monotonicMicros: 50011,
  );
  _expect(
    reversed.outcome == TerminalSelectionAutoscrollOutcome.armed &&
        reversed.nextDeadlineMicros == 100011,
    'edge reversal replaces the old deadline',
  );
  gesture.handle(_intent(TerminalLocalSelectionPhase.end, row: 0));
  final TerminalSelectionAutoscrollUpdate stopped = autoscroll.observeGesture(
    monotonicMicros: 50012,
  );
  _expect(
    stopped.outcome == TerminalSelectionAutoscrollOutcome.stopped &&
        stopped.nextDeadlineMicros == null &&
        autoscroll.advance(monotonicMicros: 500000).outcome ==
            TerminalSelectionAutoscrollOutcome.idle &&
        screens.viewport.offset == 1,
    'mouse-up clears the sole deadline and prevents later movement',
  );
}

void _testBoundsAlternateAndValidation() {
  final TerminalScreenSet screens = _historyScreens();
  final TerminalSelectionGestureController gesture =
      TerminalSelectionGestureController(viewport: screens.viewport);
  final TerminalSelectionAutoscroller autoscroll =
      TerminalSelectionAutoscroller(gesture: gesture, rowsPerTick: 8);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 2,
      edge: TerminalPointerVerticalEdge.below,
    ),
  );
  _expect(
    autoscroll.observeGesture(monotonicMicros: 0).outcome ==
        TerminalSelectionAutoscrollOutcome.bounded,
    'below drag at bottom cannot schedule work',
  );
  gesture.clear();
  screens.setAlternateMode47(true);
  gesture.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      edge: TerminalPointerVerticalEdge.above,
    ),
  );
  _expect(
    autoscroll.observeGesture(monotonicMicros: 1).outcome ==
        TerminalSelectionAutoscrollOutcome.bounded,
    'alternate screen remains fixed at zero offset',
  );
  _expectThrows<ArgumentError>(
    () => TerminalSelectionAutoscroller(
      gesture: gesture,
      interval: Duration.zero,
    ),
    'zero interval is rejected',
  );
  _expectThrows<RangeError>(
    () => TerminalSelectionAutoscroller(gesture: gesture, rowsPerTick: 9),
    'rows per tick is bounded',
  );
  _expectThrows<StateError>(
    () => autoscroll.advance(monotonicMicros: 0),
    'monotonic time cannot regress',
  );
}

TerminalScreenSet _historyScreens() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 3,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 20, maxBytes: 10000, pageRows: 1),
  );
  for (int value = 0; value < 6; value++) {
    screens.primary.setNarrowCell(0, 0, 0x41 + value);
    screens.primary.scrollUp(1);
  }
  return screens;
}

TerminalLocalSelectionIntent _intent(
  TerminalLocalSelectionPhase phase, {
  required int row,
  TerminalPointerVerticalEdge edge = TerminalPointerVerticalEdge.inside,
}) => TerminalLocalSelectionIntent(
  phase: phase,
  cell: TerminalPointerCell(row: row, column: 0),
  button: TerminalMouseButton.left,
  clickCount: 1,
  modifiers: const ModifierKeys(0),
  verticalEdge: edge,
);

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
