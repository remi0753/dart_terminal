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

/// Serializes focused-pane close admission above application state ownership.
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
  var _nextOperationId = 0;
  var _removalInProgress = false;
  var _applicationQuitInProgress = false;

  TerminalPaneCloseConfirmation? get pendingConfirmation =>
      _pendingConfirmation;
  bool get removalInProgress => _removalInProgress;
  bool get applicationQuitInProgress => _applicationQuitInProgress;

  /// Reserves hierarchy mutation for one aggregate application-quit flow.
  ///
  /// A pending pane confirmation is cancelled before the reservation is
  /// granted. An in-flight pane removal cannot be interrupted and therefore
  /// makes the quit request temporarily busy.
  bool beginApplicationQuit() {
    if (_removalInProgress || _applicationQuitInProgress) {
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
    if (_removalInProgress || _applicationQuitInProgress) {
      return const TerminalPaneCloseResult.busy();
    }
    final PaneId? targetId = paneId ?? _focusedPaneId();
    if (targetId == null) {
      _cancelPending();
      return const TerminalPaneCloseResult.noTarget();
    }

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
    if (_removalInProgress || _applicationQuitInProgress) {
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
    final TerminalPaneCloseConfirmation? pending = _pendingConfirmation;
    _pendingConfirmation = null;
    if (pending == null) return;
    final TerminalPane? pane = _state.paneForId(pending.paneId);
    if (pane?.sessionId == pending.sessionId) {
      pane!.cancelCloseConfirmation();
    }
  }
}
