part of 'terminal_screen_set.dart';

/// A privacy-safe semantic segment emitted by the shell integration lifecycle.
enum TerminalSemanticRangeKind { prompt, command, output }

enum TerminalPromptCursorMoveDirection { left, right }

enum TerminalPromptCursorMoveDisposition { move, noMovement, rejected }

enum TerminalPromptCursorMoveRejectionReason {
  outsideViewport,
  alternateScreen,
  historyViewport,
  inactiveInput,
  unavailableInput,
  differentLogicalLine,
  outsideInput,
  movementLimit,
}

/// One content-free, bounded cursor movement derived from retained OSC 133
/// input boundaries and the live cursor position.
final class TerminalPromptCursorMovePlan {
  const TerminalPromptCursorMovePlan._({
    required this.direction,
    required this.count,
    required this.semanticGeneration,
    required this.screenGeneration,
  });

  static const int maximumCount = 85;

  final TerminalPromptCursorMoveDirection direction;
  final int count;
  final int semanticGeneration;
  final int screenGeneration;

  int get encodedByteCount => count * 3;
}

final class TerminalPromptCursorMoveResolution {
  const TerminalPromptCursorMoveResolution._({
    required this.disposition,
    required this.plan,
    required this.rejectionReason,
  });

  const TerminalPromptCursorMoveResolution.move(
    TerminalPromptCursorMovePlan plan,
  ) : this._(
        disposition: TerminalPromptCursorMoveDisposition.move,
        plan: plan,
        rejectionReason: null,
      );

  const TerminalPromptCursorMoveResolution.noMovement()
    : this._(
        disposition: TerminalPromptCursorMoveDisposition.noMovement,
        plan: null,
        rejectionReason: null,
      );

  const TerminalPromptCursorMoveResolution.rejected(
    TerminalPromptCursorMoveRejectionReason reason,
  ) : this._(
        disposition: TerminalPromptCursorMoveDisposition.rejected,
        plan: null,
        rejectionReason: reason,
      );

  final TerminalPromptCursorMoveDisposition disposition;
  final TerminalPromptCursorMovePlan? plan;
  final TerminalPromptCursorMoveRejectionReason? rejectionReason;
}

/// One retained end-exclusive semantic segment over stable logical anchors.
final class TerminalSemanticRange {
  const TerminalSemanticRange._({
    required this.commandId,
    required this.kind,
    required this.start,
    required this.end,
    required this.isComplete,
  });

  final int commandId;
  final TerminalSemanticRangeKind kind;
  final TerminalLogicalAnchor start;
  final TerminalLogicalAnchor end;
  final bool isComplete;

  bool get isCollapsed => start == end;
}

/// Bounded immutable view of currently resolvable semantic segments.
final class TerminalSemanticRangeSnapshot {
  TerminalSemanticRangeSnapshot._({
    required List<TerminalSemanticRange> ranges,
    required this.generation,
    required this.storedRangeCount,
    required this.unavailableRangeCount,
    required this.evictedRangeCount,
    required this.limitReached,
  }) : ranges = List<TerminalSemanticRange>.unmodifiable(ranges);

  static const int defaultStorageCapacity = 1024;
  static const int maximumStorageCapacity = 65536;
  static const int defaultMaximumRanges = 256;
  static const int maximumRanges = 4096;

  final List<TerminalSemanticRange> ranges;
  final int generation;
  final int storedRangeCount;
  final int unavailableRangeCount;
  final int evictedRangeCount;
  final bool limitReached;

  bool get isTruncated =>
      unavailableRangeCount != 0 || evictedRangeCount != 0 || limitReached;
}

final class _TerminalSemanticRangeTracker
    implements TerminalSemanticPromptObserver {
  _TerminalSemanticRangeTracker(this._screens, {required this.capacity})
    : _completed = List<_StoredSemanticRange?>.filled(capacity, null);

  final TerminalScreenSet _screens;
  final int capacity;
  final List<_StoredSemanticRange?> _completed;
  int _head = 0;
  int _count = 0;
  int _evicted = 0;
  int _generation = 1;
  int _nextCommandId = 1;
  int _activeCommandId = 0;
  _OpenSemanticRange? _open;

  @override
  void didApplySemanticPrompt(
    TerminalSemanticPromptAction action,
    TerminalScreen screen,
  ) {
    final TerminalScreenKind? kind = _kindFor(screen);
    if (kind == null) return;
    final TerminalLogicalAnchor point = _cursorBoundary(kind);
    switch (action) {
      case TerminalSemanticPromptAction.freshLine:
        return;
      case TerminalSemanticPromptAction.promptStart:
      case TerminalSemanticPromptAction.newCommand:
        _beginCommand(TerminalSemanticRangeKind.prompt, point);
      case TerminalSemanticPromptAction.secondaryPrompt:
        if (!_sameOpenKind(kind, TerminalSemanticRangeKind.prompt)) {
          if (_activeCommandId == 0 ||
              _open?.kind == TerminalSemanticRangeKind.output ||
              _open?.start.screenKind != kind) {
            _activeCommandId = _takeCommandId();
          }
          _transition(TerminalSemanticRangeKind.prompt, point);
        }
      case TerminalSemanticPromptAction.inputStart:
      case TerminalSemanticPromptAction.inputStartUntilLineEnd:
        _ensureCommand(kind);
        _transition(TerminalSemanticRangeKind.command, point);
      case TerminalSemanticPromptAction.outputStart:
        _ensureCommand(kind);
        _transition(TerminalSemanticRangeKind.output, point);
      case TerminalSemanticPromptAction.commandEnd:
        _closeOpen(point);
        _activeCommandId = 0;
    }
  }

  @override
  void didCompleteSemanticPromptLineFeed(TerminalScreen screen) {
    final TerminalScreenKind? kind = _kindFor(screen);
    if (kind == null) return;
    _ensureCommand(kind);
    _transition(TerminalSemanticRangeKind.output, _cursorBoundary(kind));
  }

  @override
  void didResetSemanticPrompt() {
    if (_count == 0 && _open == null && _evicted == 0) return;
    _completed.fillRange(0, _completed.length, null);
    _head = 0;
    _count = 0;
    _evicted = 0;
    _activeCommandId = 0;
    _open = null;
    _generation++;
  }

  TerminalSemanticRangeSnapshot snapshot({
    required TerminalScreenKind screenKind,
    required int maxRanges,
  }) {
    RangeError.checkValueInInterval(
      maxRanges,
      1,
      TerminalSemanticRangeSnapshot.maximumRanges,
      'maxRanges',
    );
    _screens.viewport._sync();
    final List<TerminalSemanticRange?> newest =
        List<TerminalSemanticRange?>.filled(maxRanges, null);
    var available = 0;
    var unavailable = 0;

    void consider(_StoredSemanticRange stored, {required bool complete}) {
      if (stored.start.screenKind != screenKind) return;
      final TerminalSemanticRange? range = _resolve(stored, complete: complete);
      if (range == null) {
        unavailable++;
        return;
      }
      newest[available % maxRanges] = range;
      available++;
    }

    for (var index = 0; index < _count; index++) {
      consider(_completed[(_head + index) % capacity]!, complete: true);
    }
    final _OpenSemanticRange? open = _open;
    if (open != null && open.start.screenKind == screenKind) {
      consider(
        _StoredSemanticRange(
          commandId: open.commandId,
          kind: open.kind,
          start: open.start,
          end: _cursorBoundary(screenKind),
        ),
        complete: false,
      );
    }

    final int retained = available.clamp(0, maxRanges);
    final int first = available > maxRanges ? available % maxRanges : 0;
    final List<TerminalSemanticRange> ranges = <TerminalSemanticRange>[];
    for (var index = 0; index < retained; index++) {
      ranges.add(newest[(first + index) % maxRanges]!);
    }
    return TerminalSemanticRangeSnapshot._(
      ranges: ranges,
      generation: _generation,
      storedRangeCount: _count + (_open == null ? 0 : 1),
      unavailableRangeCount: unavailable,
      evictedRangeCount: _evicted,
      limitReached: available > maxRanges,
    );
  }

  void _beginCommand(
    TerminalSemanticRangeKind kind,
    TerminalLogicalAnchor point,
  ) {
    _closeOpen(point);
    _activeCommandId = _takeCommandId();
    _open = _OpenSemanticRange(
      commandId: _activeCommandId,
      kind: kind,
      start: point,
    );
    _generation++;
  }

  void _ensureCommand(TerminalScreenKind kind) {
    if (_activeCommandId == 0 || _open?.start.screenKind != kind) {
      final _OpenSemanticRange? open = _open;
      if (open != null && open.start.screenKind != kind) {
        _closeOpen(_cursorBoundary(open.start.screenKind));
      }
      _activeCommandId = _takeCommandId();
    }
  }

  void _transition(
    TerminalSemanticRangeKind kind,
    TerminalLogicalAnchor point,
  ) {
    if (_sameOpenKind(point.screenKind, kind)) return;
    _closeOpen(point);
    _open = _OpenSemanticRange(
      commandId: _activeCommandId,
      kind: kind,
      start: point,
    );
    _generation++;
  }

  bool _sameOpenKind(
    TerminalScreenKind screenKind,
    TerminalSemanticRangeKind kind,
  ) => _open?.start.screenKind == screenKind && _open?.kind == kind;

  void _closeOpen(TerminalLogicalAnchor proposedEnd) {
    final _OpenSemanticRange? open = _open;
    if (open == null) return;
    final TerminalLogicalAnchor end =
        open.start.screenKind == proposedEnd.screenKind
        ? proposedEnd
        : _cursorBoundary(open.start.screenKind);
    _append(
      _StoredSemanticRange(
        commandId: open.commandId,
        kind: open.kind,
        start: open.start,
        end: end,
      ),
    );
    _open = null;
    _generation++;
  }

  void _append(_StoredSemanticRange range) {
    if (_count < capacity) {
      _completed[(_head + _count) % capacity] = range;
      _count++;
      return;
    }
    _completed[_head] = range;
    _head = (_head + 1) % capacity;
    _evicted++;
  }

  TerminalSemanticRange? _resolve(
    _StoredSemanticRange stored, {
    required bool complete,
  }) {
    final _DocumentBoundary? start = _resolveDocumentBoundary(
      _screens.viewport,
      stored.start,
    );
    final _DocumentBoundary? end = _resolveDocumentBoundary(
      _screens.viewport,
      stored.end,
    );
    if (start == null ||
        end == null ||
        stored.start.screenKind != stored.end.screenKind ||
        _compareDocumentBoundaries(start, end) > 0) {
      return null;
    }
    return TerminalSemanticRange._(
      commandId: stored.commandId,
      kind: stored.kind,
      start: stored.start,
      end: stored.end,
      isComplete: complete,
    );
  }

  TerminalScreenKind? _kindFor(TerminalScreen screen) {
    if (identical(screen, _screens.primary)) return TerminalScreenKind.primary;
    if (identical(screen, _screens.alternate)) {
      return TerminalScreenKind.alternate;
    }
    return null;
  }

  TerminalLogicalAnchor _cursorBoundary(TerminalScreenKind kind) {
    final TerminalScreen screen = _screens.screenFor(kind);
    final int combinedRow = kind == TerminalScreenKind.primary
        ? _screens.scrollback.length + screen.cursorRow
        : screen.cursorRow;
    int logicalCell = _screens.viewport._combinedLogicalCellIndex(
      kind,
      combinedRow,
      screen.cursorColumn,
    );
    if (screen.wrapPending) logicalCell++;
    return _boundaryAt(
      _screens.viewport,
      kind,
      combinedRow,
      logicalCell.clamp(
        0,
        _screens.viewport._combinedLogicalCellCount(kind, combinedRow),
      ),
    ).anchor;
  }

  int _takeCommandId() {
    final int result = _nextCommandId;
    _nextCommandId++;
    return result;
  }
}

TerminalPromptCursorMoveResolution _resolvePromptCursorMove(
  TerminalScreenSet screens,
  int viewportRow,
  int column, {
  required int maxMovements,
}) {
  RangeError.checkValueInInterval(
    maxMovements,
    1,
    TerminalPromptCursorMovePlan.maximumCount,
    'maxMovements',
  );
  final TerminalViewport viewport = screens.viewport;
  if (viewportRow < 0 ||
      viewportRow >= viewport.rows ||
      column < 0 ||
      column >= viewport.columnsAt(viewportRow)) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.outsideViewport,
    );
  }
  if (screens.usingAlternate) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.alternateScreen,
    );
  }
  if (!viewport.atBottom || viewport.isHistoryRow(viewportRow)) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.historyViewport,
    );
  }
  if (screens.semanticPrompt.shellState != TerminalSemanticShellState.input) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.inactiveInput,
    );
  }

  final TerminalSemanticRangeSnapshot snapshot = screens
      .semanticRangeSnapshot();
  TerminalSemanticRange? input;
  for (final TerminalSemanticRange range in snapshot.ranges.reversed) {
    if (range.kind == TerminalSemanticRangeKind.command && !range.isComplete) {
      input = range;
      break;
    }
  }
  if (input == null) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.unavailableInput,
    );
  }

  final TerminalLogicalAnchor target = viewport.anchorAt(viewportRow, column);
  final TerminalLogicalAnchor cursor = screens._semanticRanges._cursorBoundary(
    TerminalScreenKind.primary,
  );
  if (target.logicalLineId != input.start.logicalLineId ||
      target.logicalLineEpoch != input.start.logicalLineEpoch ||
      cursor.logicalLineId != input.start.logicalLineId ||
      cursor.logicalLineEpoch != input.start.logicalLineEpoch) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.differentLogicalLine,
    );
  }
  final _DocumentBoundary? inputStart = _resolveDocumentBoundary(
    viewport,
    input.start,
  );
  final _DocumentBoundary? targetBoundary = _resolveDocumentBoundary(
    viewport,
    target,
  );
  final _DocumentBoundary? cursorBoundary = _resolveDocumentBoundary(
    viewport,
    cursor,
  );
  if (inputStart == null || targetBoundary == null || cursorBoundary == null) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.unavailableInput,
    );
  }
  final _DocumentBoundary lineEnd = _logicalLineEnd(viewport, inputStart);
  if (_compareDocumentBoundaries(targetBoundary, inputStart) < 0 ||
      _compareDocumentBoundaries(targetBoundary, lineEnd) > 0 ||
      _compareDocumentBoundaries(cursorBoundary, inputStart) < 0 ||
      _compareDocumentBoundaries(cursorBoundary, lineEnd) > 0) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.outsideInput,
    );
  }

  final int delta = target.cellOffset - cursor.cellOffset;
  if (delta == 0) {
    return const TerminalPromptCursorMoveResolution.noMovement();
  }
  final int count = delta.abs();
  if (count > maxMovements) {
    return const TerminalPromptCursorMoveResolution.rejected(
      TerminalPromptCursorMoveRejectionReason.movementLimit,
    );
  }
  return TerminalPromptCursorMoveResolution.move(
    TerminalPromptCursorMovePlan._(
      direction: delta < 0
          ? TerminalPromptCursorMoveDirection.left
          : TerminalPromptCursorMoveDirection.right,
      count: count,
      semanticGeneration: snapshot.generation,
      screenGeneration: screens.primary.generation,
    ),
  );
}

final class _OpenSemanticRange {
  const _OpenSemanticRange({
    required this.commandId,
    required this.kind,
    required this.start,
  });

  final int commandId;
  final TerminalSemanticRangeKind kind;
  final TerminalLogicalAnchor start;
}

final class _StoredSemanticRange {
  const _StoredSemanticRange({
    required this.commandId,
    required this.kind,
    required this.start,
    required this.end,
  });

  final int commandId;
  final TerminalSemanticRangeKind kind;
  final TerminalLogicalAnchor start;
  final TerminalLogicalAnchor end;
}
