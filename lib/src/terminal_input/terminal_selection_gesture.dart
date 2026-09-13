import '../terminal_core/terminal_screen_set.dart';
import 'terminal_mouse_event.dart';
import 'terminal_mouse_router.dart';

enum TerminalSelectionGestureOutcome {
  ignored,
  began,
  updated,
  ended,
  cancelled,
  cleared,
}

/// Immutable presentation state for one local terminal selection owner.
final class TerminalSelectionGestureSnapshot {
  const TerminalSelectionGestureSnapshot._({
    required this.generation,
    required this.isActive,
    required this.unit,
    required this.range,
    required this.verticalEdge,
  });

  final int generation;
  final bool isActive;
  final TerminalSelectionUnit? unit;
  final TerminalSelectionRange? range;
  final TerminalPointerVerticalEdge verticalEdge;

  bool get hasSelection => range != null && !range!.isCollapsed;
}

final class TerminalSelectionGestureUpdate {
  const TerminalSelectionGestureUpdate({
    required this.outcome,
    required this.snapshot,
  });

  final TerminalSelectionGestureOutcome outcome;
  final TerminalSelectionGestureSnapshot snapshot;

  bool get changed => outcome != TerminalSelectionGestureOutcome.ignored;
}

/// Converts local pointer phases into one stable, end-exclusive selection.
final class TerminalSelectionGestureController {
  TerminalSelectionGestureController({required this.viewport});

  static const int maximumGeneration = 0x7fffffffffffffff;

  final TerminalViewport viewport;
  int _generation = 0;
  bool _isActive = false;
  TerminalSelectionUnit? _unit;
  TerminalSelectionRange? _range;
  TerminalLogicalAnchor? _originStart;
  TerminalLogicalAnchor? _originEnd;
  int? _focusColumn;
  TerminalPointerVerticalEdge _verticalEdge =
      TerminalPointerVerticalEdge.inside;

  TerminalSelectionGestureSnapshot get snapshot =>
      TerminalSelectionGestureSnapshot._(
        generation: _generation,
        isActive: _isActive,
        unit: _unit,
        range: _range,
        verticalEdge: _verticalEdge,
      );

  TerminalSelectionGestureUpdate handle(TerminalLocalSelectionIntent intent) {
    if (intent.button != TerminalMouseButton.left) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    return switch (intent.phase) {
      TerminalLocalSelectionPhase.begin => _begin(intent),
      TerminalLocalSelectionPhase.update => _continue(intent, ending: false),
      TerminalLocalSelectionPhase.end => _continue(intent, ending: true),
    };
  }

  /// Clears a range whose stable anchors were evicted or changed screen kind.
  TerminalSelectionGestureUpdate synchronize() {
    final TerminalSelectionRange? current = _range;
    if (current == null || viewport.isSelectionAvailable(current)) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    _reset();
    _advanceGeneration();
    return _result(TerminalSelectionGestureOutcome.cancelled);
  }

  TerminalSelectionGestureUpdate clear() {
    if (_range == null && !_isActive) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    _reset();
    _advanceGeneration();
    return _result(TerminalSelectionGestureOutcome.cleared);
  }

  /// Ends only the transient pointer gesture while preserving its selection.
  TerminalSelectionGestureUpdate cancelInteraction() {
    if (!_isActive) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    _isActive = false;
    _verticalEdge = TerminalPointerVerticalEdge.inside;
    _advanceGeneration();
    return _result(TerminalSelectionGestureOutcome.ended);
  }

  TerminalSelectionGestureUpdate _begin(TerminalLocalSelectionIntent intent) {
    if (intent.clickCount < 1 || !_cellIsAvailable(intent.cell)) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    final TerminalLogicalAnchor start = viewport.anchorAt(
      intent.cell.row,
      intent.cell.column,
    );
    final TerminalLogicalAnchor end = viewport.anchorAfter(
      intent.cell.row,
      intent.cell.column,
    );
    final TerminalSelectionUnit unit = intent.clickCount == 1
        ? TerminalSelectionUnit.cell
        : intent.clickCount == 2
        ? TerminalSelectionUnit.word
        : TerminalSelectionUnit.logicalLine;
    final TerminalSelectionRange? range = viewport.selectionRange(
      start,
      end,
      unit: unit,
    );
    if (range == null) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    _isActive = true;
    _unit = unit;
    _range = range;
    _originStart = start;
    _originEnd = end;
    _focusColumn = intent.cell.column;
    _verticalEdge = intent.verticalEdge;
    _advanceGeneration();
    return _result(TerminalSelectionGestureOutcome.began);
  }

  TerminalSelectionGestureUpdate _continue(
    TerminalLocalSelectionIntent intent, {
    required bool ending,
  }) {
    if (!_isActive) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    if (!_cellIsAvailable(intent.cell)) {
      _reset();
      _advanceGeneration();
      return _result(TerminalSelectionGestureOutcome.cancelled);
    }
    return _updateFocus(intent.cell, ending: ending, edge: intent.verticalEdge);
  }

  /// Re-resolves the clamped edge cell after one bounded viewport scroll.
  TerminalSelectionGestureUpdate extendToAutoscrolledEdge() {
    if (!_isActive ||
        _focusColumn == null ||
        _verticalEdge == TerminalPointerVerticalEdge.inside) {
      return _result(TerminalSelectionGestureOutcome.ignored);
    }
    return _updateFocus(
      TerminalPointerCell(
        row: _verticalEdge == TerminalPointerVerticalEdge.above
            ? 0
            : viewport.rows - 1,
        column: _focusColumn!.clamp(0, viewport.columns - 1),
      ),
      ending: false,
      edge: _verticalEdge,
    );
  }

  TerminalSelectionGestureUpdate _updateFocus(
    TerminalPointerCell cell, {
    required bool ending,
    required TerminalPointerVerticalEdge edge,
  }) {
    final TerminalLogicalAnchor focusStart = viewport.anchorAt(
      cell.row,
      cell.column,
    );
    final TerminalLogicalAnchor focusEnd = viewport.anchorAfter(
      cell.row,
      cell.column,
    );
    final TerminalSelectionRange? forwardProbe = viewport.selectionRange(
      _originStart!,
      focusEnd,
      unit: _unit!,
    );
    if (forwardProbe == null) {
      _reset();
      _advanceGeneration();
      return _result(TerminalSelectionGestureOutcome.cancelled);
    }
    final TerminalSelectionRange? range = forwardProbe.isReversed
        ? viewport.selectionRange(_originEnd!, focusStart, unit: _unit!)
        : forwardProbe;
    if (range == null) {
      _reset();
      _advanceGeneration();
      return _result(TerminalSelectionGestureOutcome.cancelled);
    }
    _range = range;
    _focusColumn = cell.column;
    _isActive = !ending;
    _verticalEdge = ending ? TerminalPointerVerticalEdge.inside : edge;
    _advanceGeneration();
    return _result(
      ending
          ? TerminalSelectionGestureOutcome.ended
          : TerminalSelectionGestureOutcome.updated,
    );
  }

  bool _cellIsAvailable(TerminalPointerCell cell) =>
      cell.row < viewport.rows && cell.column < viewport.columns;

  void _reset() {
    _isActive = false;
    _unit = null;
    _range = null;
    _originStart = null;
    _originEnd = null;
    _focusColumn = null;
    _verticalEdge = TerminalPointerVerticalEdge.inside;
  }

  void _advanceGeneration() {
    if (_generation == maximumGeneration) {
      throw StateError('selection gesture generation exhausted');
    }
    _generation++;
  }

  TerminalSelectionGestureUpdate _result(
    TerminalSelectionGestureOutcome outcome,
  ) => TerminalSelectionGestureUpdate(outcome: outcome, snapshot: snapshot);
}
