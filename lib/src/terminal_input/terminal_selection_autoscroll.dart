import 'terminal_mouse_router.dart';
import 'terminal_selection_gesture.dart';

enum TerminalSelectionAutoscrollOutcome {
  idle,
  armed,
  waiting,
  scrolled,
  bounded,
  stopped,
  cancelled,
}

final class TerminalSelectionAutoscrollUpdate {
  const TerminalSelectionAutoscrollUpdate({
    required this.outcome,
    required this.nextDeadlineMicros,
    required this.tickCount,
    required this.scrolledRowCount,
  });

  final TerminalSelectionAutoscrollOutcome outcome;
  final int? nextDeadlineMicros;
  final int tickCount;
  final int scrolledRowCount;

  bool get didScroll => outcome == TerminalSelectionAutoscrollOutcome.scrolled;
}

/// One-deadline, no-catch-up autoscroller for an active edge drag.
final class TerminalSelectionAutoscroller {
  TerminalSelectionAutoscroller({
    required this.gesture,
    this.interval = const Duration(milliseconds: 50),
    this.rowsPerTick = 1,
  }) {
    if (interval <= Duration.zero || interval > const Duration(seconds: 1)) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be positive and at most one second',
      );
    }
    RangeError.checkValueInInterval(rowsPerTick, 1, 8, 'rowsPerTick');
  }

  static const int maximumCounter = 0x7fffffffffffffff;

  final TerminalSelectionGestureController gesture;
  final Duration interval;
  final int rowsPerTick;
  int? _nextDeadlineMicros;
  TerminalPointerVerticalEdge _armedEdge = TerminalPointerVerticalEdge.inside;
  int _lastMonotonicMicros = 0;
  bool _hasObservedTime = false;
  int _tickCount = 0;
  int _scrolledRowCount = 0;

  int? get nextDeadlineMicros => _nextDeadlineMicros;
  int get tickCount => _tickCount;
  int get scrolledRowCount => _scrolledRowCount;

  TerminalSelectionAutoscrollUpdate observeGesture({
    required int monotonicMicros,
  }) {
    _validateTime(monotonicMicros);
    final TerminalSelectionGestureSnapshot snapshot = gesture.snapshot;
    final TerminalPointerVerticalEdge edge = snapshot.verticalEdge;
    if (!snapshot.isActive || edge == TerminalPointerVerticalEdge.inside) {
      final bool stopped = _nextDeadlineMicros != null;
      _nextDeadlineMicros = null;
      _armedEdge = TerminalPointerVerticalEdge.inside;
      return _result(
        stopped
            ? TerminalSelectionAutoscrollOutcome.stopped
            : TerminalSelectionAutoscrollOutcome.idle,
      );
    }
    if (!_canScroll(edge)) {
      _nextDeadlineMicros = null;
      _armedEdge = edge;
      return _result(TerminalSelectionAutoscrollOutcome.bounded);
    }
    if (_nextDeadlineMicros == null || _armedEdge != edge) {
      _armedEdge = edge;
      _nextDeadlineMicros = _deadlineAfter(monotonicMicros);
      return _result(TerminalSelectionAutoscrollOutcome.armed);
    }
    return _result(TerminalSelectionAutoscrollOutcome.waiting);
  }

  TerminalSelectionAutoscrollUpdate advance({required int monotonicMicros}) {
    _validateTime(monotonicMicros);
    final TerminalSelectionGestureSnapshot snapshot = gesture.snapshot;
    if (!snapshot.isActive ||
        snapshot.verticalEdge == TerminalPointerVerticalEdge.inside) {
      final bool stopped = _nextDeadlineMicros != null;
      _nextDeadlineMicros = null;
      _armedEdge = TerminalPointerVerticalEdge.inside;
      return _result(
        stopped
            ? TerminalSelectionAutoscrollOutcome.stopped
            : TerminalSelectionAutoscrollOutcome.idle,
      );
    }
    if (_armedEdge != snapshot.verticalEdge || _nextDeadlineMicros == null) {
      return observeGesture(monotonicMicros: monotonicMicros);
    }
    if (monotonicMicros < _nextDeadlineMicros!) {
      return _result(TerminalSelectionAutoscrollOutcome.waiting);
    }
    if (!_canScroll(_armedEdge)) {
      _nextDeadlineMicros = null;
      return _result(TerminalSelectionAutoscrollOutcome.bounded);
    }
    final int before = gesture.viewport.offset;
    gesture.viewport.scrollByRows(
      _armedEdge == TerminalPointerVerticalEdge.above
          ? rowsPerTick
          : -rowsPerTick,
    );
    final int delta = (gesture.viewport.offset - before).abs();
    if (delta == 0) {
      _nextDeadlineMicros = null;
      return _result(TerminalSelectionAutoscrollOutcome.bounded);
    }
    final TerminalSelectionGestureUpdate extended = gesture
        .extendToAutoscrolledEdge();
    if (extended.outcome == TerminalSelectionGestureOutcome.cancelled) {
      _nextDeadlineMicros = null;
      _armedEdge = TerminalPointerVerticalEdge.inside;
      return _result(TerminalSelectionAutoscrollOutcome.cancelled);
    }
    _advanceCounters(delta);
    _nextDeadlineMicros = _canScroll(_armedEdge)
        ? _deadlineAfter(monotonicMicros)
        : null;
    return _result(TerminalSelectionAutoscrollOutcome.scrolled);
  }

  bool _canScroll(TerminalPointerVerticalEdge edge) => switch (edge) {
    TerminalPointerVerticalEdge.above =>
      gesture.viewport.offset < gesture.viewport.maximumOffset,
    TerminalPointerVerticalEdge.below => gesture.viewport.offset > 0,
    TerminalPointerVerticalEdge.inside => false,
  };

  int _deadlineAfter(int now) {
    final int delta = interval.inMicroseconds;
    if (now > maximumCounter - delta) {
      throw StateError('selection autoscroll deadline exhausted');
    }
    return now + delta;
  }

  void _advanceCounters(int rows) {
    if (_tickCount == maximumCounter ||
        _scrolledRowCount > maximumCounter - rows) {
      throw StateError('selection autoscroll counters exhausted');
    }
    _tickCount++;
    _scrolledRowCount += rows;
  }

  void _validateTime(int value) {
    if (value < 0 || value > maximumCounter) {
      throw RangeError.range(value, 0, maximumCounter, 'monotonicMicros');
    }
    if (_hasObservedTime && value < _lastMonotonicMicros) {
      throw StateError('selection autoscroll time regressed');
    }
    _hasObservedTime = true;
    _lastMonotonicMicros = value;
  }

  TerminalSelectionAutoscrollUpdate _result(
    TerminalSelectionAutoscrollOutcome outcome,
  ) => TerminalSelectionAutoscrollUpdate(
    outcome: outcome,
    nextDeadlineMicros: _nextDeadlineMicros,
    tickCount: _tickCount,
    scrolledRowCount: _scrolledRowCount,
  );
}
