import 'dart:async';

import 'terminal_application_state.dart';
import 'terminal_pane.dart';

typedef TerminalPanePreRemovalCallback = FutureOr<void> Function(PaneId paneId);

enum TerminalPaneCloseDisposition {
  confirmationRequired,
  removed,
  removedWithCleanupFailure,
  noTarget,
  stale,
  busy,
}

/// Content-free identity for one pending pane-close confirmation.
final class TerminalPaneCloseConfirmation {
  TerminalPaneCloseConfirmation({
    required this.operationId,
    required this.paneId,
    required this.sessionId,
    required this.processDisposition,
  }) {
    if (operationId <= 0) {
      throw ArgumentError.value(operationId, 'operationId', 'must be positive');
    }
    if (paneId != sessionId.paneId) {
      throw ArgumentError('pane and session identity must match');
    }
    if (processDisposition !=
            TerminalPaneProcessDisposition.owningShellCommand &&
        processDisposition !=
            TerminalPaneProcessDisposition.foregroundProcess &&
        processDisposition != TerminalPaneProcessDisposition.unavailable) {
      throw ArgumentError.value(
        processDisposition,
        'processDisposition',
        'must require confirmation',
      );
    }
  }

  final int operationId;
  final PaneId paneId;
  final TerminalSessionId sessionId;
  final TerminalPaneProcessDisposition processDisposition;

  @override
  bool operator ==(Object other) =>
      other is TerminalPaneCloseConfirmation &&
      other.operationId == operationId &&
      other.paneId == paneId &&
      other.sessionId == sessionId &&
      other.processDisposition == processDisposition;

  @override
  int get hashCode =>
      Object.hash(operationId, paneId, sessionId, processDisposition);
}

final class TerminalPaneCloseResult {
  const TerminalPaneCloseResult._({
    required this.disposition,
    this.confirmation,
    this.removal,
  });

  factory TerminalPaneCloseResult.confirmationRequired(
    TerminalPaneCloseConfirmation confirmation,
  ) => TerminalPaneCloseResult._(
    disposition: TerminalPaneCloseDisposition.confirmationRequired,
    confirmation: confirmation,
  );

  factory TerminalPaneCloseResult.removed(TerminalPaneRemovalResult removal) =>
      TerminalPaneCloseResult._(
        disposition: removal.shutdown.isClean
            ? TerminalPaneCloseDisposition.removed
            : TerminalPaneCloseDisposition.removedWithCleanupFailure,
        removal: removal,
      );

  const TerminalPaneCloseResult.noTarget()
    : this._(disposition: TerminalPaneCloseDisposition.noTarget);

  const TerminalPaneCloseResult.stale()
    : this._(disposition: TerminalPaneCloseDisposition.stale);

  const TerminalPaneCloseResult.busy()
    : this._(disposition: TerminalPaneCloseDisposition.busy);

  final TerminalPaneCloseDisposition disposition;
  final TerminalPaneCloseConfirmation? confirmation;
  final TerminalPaneRemovalResult? removal;

  String machineLine() {
    final TerminalPaneCloseConfirmation? pending = confirmation;
    final TerminalPaneRemovalResult? completed = removal;
    return 'TERMINAL_PANE_CLOSE_TRANSACTION '
        'disposition=${disposition.name} '
        'operation_id=${pending?.operationId ?? 0} '
        'pane=${pending?.paneId ?? completed?.paneId ?? 0} '
        'session=${pending?.sessionId ?? completed?.shutdown.sessionId ?? 0} '
        'removed_tab=${completed?.removedTab ?? false} '
        'removed_window=${completed?.removedWindow ?? false} '
        'cleanup=${completed?.shutdown.disposition.name ?? 'pending'}';
  }
}

typedef _WindowClosePaneSnapshot = ({
  PaneId paneId,
  TerminalSessionId sessionId,
  TerminalPaneProcessDisposition disposition,
  int? child,
  int? owning,
  int? foreground,
  int owningError,
  int foregroundError,
});

/// Captured whole-window identity and bounded content-free process evidence.
final class TerminalWindowCloseConfirmation {
  TerminalWindowCloseConfirmation._(
    this.operationId,
    this.windowId,
    List<_WindowClosePaneSnapshot> panes,
  ) : _panes = List<_WindowClosePaneSnapshot>.unmodifiable(panes);

  final int operationId;
  final TerminalWindowId windowId;
  final List<_WindowClosePaneSnapshot> _panes;
  List<PaneId> get paneIds =>
      List<PaneId>.unmodifiable(_panes.map((pane) => pane.paneId));
}

enum TerminalWindowCloseDisposition {
  confirmationRequired,
  removed,
  removedWithCleanupFailure,
  stale,
  busy,
  noTarget,
}

final class TerminalWindowCloseResult {
  const TerminalWindowCloseResult(
    this.disposition, {
    this.confirmation,
    this.removal,
  });

  final TerminalWindowCloseDisposition disposition;
  final TerminalWindowCloseConfirmation? confirmation;
  final TerminalWindowRemovalResult? removal;

  String machineLine() =>
      'TERMINAL_WINDOW_CLOSE_TRANSACTION '
      'disposition=${disposition.name} '
      'window=${confirmation?.windowId ?? removal?.windowId ?? 0} '
      'panes=${confirmation?.paneIds.length ?? removal?.shutdown.sessions.length ?? 0}';
}

/// Serializes pane/window Close admission above application state ownership.
final class TerminalPaneCloseCoordinator {
  TerminalPaneCloseCoordinator({
    required TerminalApplicationState state,
    TerminalPanePreRemovalCallback? onBeforePaneRemoved,
    void Function()? onHierarchyChanged,
  }) : _state = state,
       _onBeforePaneRemoved = onBeforePaneRemoved,
       _onHierarchyChanged = onHierarchyChanged;

  static const int maximumOperationId = 0x7fffffffffffffff;

  final TerminalApplicationState _state;
  final TerminalPanePreRemovalCallback? _onBeforePaneRemoved;
  final void Function()? _onHierarchyChanged;

  TerminalPaneCloseConfirmation? _pendingConfirmation;
  TerminalWindowCloseConfirmation? _pendingWindowConfirmation;
  var _nextOperationId = 0;
  var _removalInProgress = false;
  var _applicationQuitInProgress = false;

  TerminalPaneCloseConfirmation? get pendingConfirmation =>
      _pendingConfirmation;
  bool get removalInProgress => _removalInProgress;
  bool get applicationQuitInProgress => _applicationQuitInProgress;
  TerminalWindowCloseConfirmation? get pendingWindowConfirmation =>
      _pendingWindowConfirmation;

  /// Repeating the native button confirms only the same live whole-window
  /// snapshot; changed membership, process identity, or interaction asks again.
  Future<TerminalWindowCloseResult> requestWindowClose(
    TerminalWindowId windowId,
  ) async {
    if (_removalInProgress ||
        _applicationQuitInProgress ||
        _state.mutationInProgress) {
      return const TerminalWindowCloseResult(
        TerminalWindowCloseDisposition.busy,
      );
    }
    if (_state.isDisposed || _state.windowForId(windowId) == null) {
      if (_pendingWindowConfirmation?.windowId == windowId)
        _cancelWindowPending();
      return const TerminalWindowCloseResult(
        TerminalWindowCloseDisposition.noTarget,
      );
    }
    final List<_WindowClosePaneSnapshot> panes = _captureWindow(windowId);
    final TerminalWindowCloseConfirmation? pending = _pendingWindowConfirmation;
    if (pending != null &&
        pending.windowId == windowId &&
        _sameWindowSnapshot(pending._panes, panes) &&
        panes.every(
          (pane) => _state.paneForId(pane.paneId)!.closeConfirmationPending,
        )) {
      _cancelPending();
      return _removeWindow(windowId, panes);
    }
    _cancelPending();
    if (panes.any(
      (pane) =>
          pane.disposition ==
              TerminalPaneProcessDisposition.foregroundProcess ||
          pane.disposition ==
              TerminalPaneProcessDisposition.owningShellCommand ||
          pane.disposition == TerminalPaneProcessDisposition.unavailable,
    )) {
      if (_nextOperationId >= maximumOperationId)
        throw StateError('terminal close operation ID is exhausted');
      final TerminalWindowCloseConfirmation confirmation =
          TerminalWindowCloseConfirmation._(
            ++_nextOperationId,
            windowId,
            panes,
          );
      _pendingWindowConfirmation = confirmation;
      for (final _WindowClosePaneSnapshot pane in panes) {
        _state.paneForId(pane.paneId)!.showWindowCloseConfirmation();
      }
      return TerminalWindowCloseResult(
        TerminalWindowCloseDisposition.confirmationRequired,
        confirmation: confirmation,
      );
    }
    return _removeWindow(windowId, panes);
  }

  List<_WindowClosePaneSnapshot> _captureWindow(TerminalWindowId windowId) =>
      <_WindowClosePaneSnapshot>[
        for (final TerminalTabState tab in _state.windowForId(windowId)!.tabs)
          for (final PaneId paneId in tab.paneIds) _captureWindowPane(paneId),
      ];

  _WindowClosePaneSnapshot _captureWindowPane(PaneId paneId) {
    final TerminalPaneProcessSnapshot process = _state
        .paneForId(paneId)!
        .processSnapshot();
    return (
      paneId: paneId,
      sessionId: process.sessionId,
      disposition: process.disposition,
      child: process.childProcessId,
      owning: process.owningProcessGroup,
      foreground: process.foregroundProcessGroup,
      owningError: process.owningProcessGroupSystemError,
      foregroundError: process.foregroundProcessGroupSystemError,
    );
  }

  static bool _sameWindowSnapshot(
    List<_WindowClosePaneSnapshot> first,
    List<_WindowClosePaneSnapshot> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<TerminalWindowCloseResult> _removeWindow(
    TerminalWindowId windowId,
    List<_WindowClosePaneSnapshot> panes,
  ) async {
    _removalInProgress = true;
    try {
      for (final _WindowClosePaneSnapshot pane in panes) {
        await _onBeforePaneRemoved?.call(pane.paneId);
      }
      // No newly created/replaced session may be admitted by an old request.
      final TerminalWindowState? window = _state.windowForId(windowId);
      if (window == null ||
          !_sameWindowSnapshot(panes, _captureWindow(windowId))) {
        return const TerminalWindowCloseResult(
          TerminalWindowCloseDisposition.stale,
        );
      }
      final TerminalWindowRemovalResult removal = await _state.removeWindow(
        windowId,
      );
      _onHierarchyChanged?.call();
      return TerminalWindowCloseResult(
        removal.shutdown.isClean
            ? TerminalWindowCloseDisposition.removed
            : TerminalWindowCloseDisposition.removedWithCleanupFailure,
        removal: removal,
      );
    } finally {
      _removalInProgress = false;
    }
  }

  /// Reserves hierarchy mutation for one aggregate application-quit flow.
  ///
  /// A pending pane confirmation is cancelled before the reservation is
  /// granted. An in-flight pane removal cannot be interrupted and therefore
  /// makes the quit request temporarily busy.
  bool beginApplicationQuit() {
    if (_removalInProgress ||
        _applicationQuitInProgress ||
        _state.mutationInProgress) {
      return false;
    }
    _cancelPending();
    _applicationQuitInProgress = true;
    return true;
  }

  void endApplicationQuit() {
    _applicationQuitInProgress = false;
  }

  /// Repeating the same pending request is an explicit confirmation.
  Future<TerminalPaneCloseResult> requestClose({PaneId? paneId}) async {
    if (_removalInProgress ||
        _applicationQuitInProgress ||
        _state.mutationInProgress) {
      return const TerminalPaneCloseResult.busy();
    }
    final PaneId? targetId = paneId ?? _focusedPaneId();
    if (targetId == null) {
      _cancelPending();
      return const TerminalPaneCloseResult.noTarget();
    }

    _cancelWindowPending();

    final TerminalPaneCloseConfirmation? pending = _pendingConfirmation;
    if (pending != null) {
      if (pending.paneId == targetId && _isCurrent(pending)) {
        return confirmClose(pending);
      }
      _cancelPending();
    }

    final TerminalPane? pane = _state.paneForId(targetId);
    if (pane == null) {
      return const TerminalPaneCloseResult.noTarget();
    }
    final TerminalPaneProcessSnapshot snapshot = pane.processSnapshot();
    if (snapshot.requiresConfirmation) {
      final TerminalPaneCloseDecision paneDecision = pane.requestClose();
      if (paneDecision == TerminalPaneCloseDecision.confirmationRequired) {
        if (_nextOperationId >= maximumOperationId) {
          pane.cancelCloseConfirmation();
          throw StateError('terminal pane close operation ID is exhausted');
        }
        final TerminalPaneCloseConfirmation confirmation =
            TerminalPaneCloseConfirmation(
              operationId: ++_nextOperationId,
              paneId: pane.id,
              sessionId: pane.sessionId,
              processDisposition: snapshot.disposition,
            );
        _pendingConfirmation = confirmation;
        return TerminalPaneCloseResult.confirmationRequired(confirmation);
      }
    }
    return _remove(pane.id);
  }

  Future<TerminalPaneCloseResult> confirmClose(
    TerminalPaneCloseConfirmation confirmation,
  ) async {
    if (_removalInProgress ||
        _applicationQuitInProgress ||
        _state.mutationInProgress) {
      return const TerminalPaneCloseResult.busy();
    }
    if (_pendingConfirmation != confirmation) {
      return const TerminalPaneCloseResult.stale();
    }
    if (!_isCurrent(confirmation)) {
      _pendingConfirmation = null;
      return const TerminalPaneCloseResult.stale();
    }
    _pendingConfirmation = null;
    return _remove(confirmation.paneId);
  }

  bool cancelClose(TerminalPaneCloseConfirmation confirmation) {
    if (_pendingConfirmation != confirmation) {
      return false;
    }
    if (!_isCurrent(confirmation)) {
      _pendingConfirmation = null;
      return false;
    }
    _cancelPending();
    return true;
  }

  void cancelPending() => _cancelPending();

  Future<TerminalPaneCloseResult> _remove(PaneId paneId) async {
    if (_removalInProgress) {
      return const TerminalPaneCloseResult.busy();
    }
    if (_state.paneForId(paneId) == null) {
      return const TerminalPaneCloseResult.stale();
    }
    _removalInProgress = true;
    try {
      await _onBeforePaneRemoved?.call(paneId);
      final TerminalPaneRemovalResult removal = await _state.removePane(paneId);
      _onHierarchyChanged?.call();
      return TerminalPaneCloseResult.removed(removal);
    } finally {
      _removalInProgress = false;
    }
  }

  PaneId? _focusedPaneId() => _state.activeWindow?.selectedTab.focusedPaneId;

  bool _isCurrent(TerminalPaneCloseConfirmation confirmation) {
    final TerminalPane? pane = _state.paneForId(confirmation.paneId);
    return pane != null &&
        pane.sessionId == confirmation.sessionId &&
        pane.closeConfirmationPending;
  }

  void _cancelPending() {
    _cancelWindowPending();
    final TerminalPaneCloseConfirmation? pending = _pendingConfirmation;
    _pendingConfirmation = null;
    if (pending == null) return;
    final TerminalPane? pane = _state.paneForId(pending.paneId);
    if (pane?.sessionId == pending.sessionId) {
      pane!.cancelCloseConfirmation();
    }
  }

  void _cancelWindowPending() {
    final TerminalWindowCloseConfirmation? pending = _pendingWindowConfirmation;
    _pendingWindowConfirmation = null;
    if (pending == null) return;
    for (final _WindowClosePaneSnapshot pane in pending._panes) {
      final TerminalPane? current = _state.paneForId(pane.paneId);
      if (current?.sessionId == pane.sessionId)
        current!.cancelCloseConfirmation();
    }
  }
}
