import 'terminal_application_state.dart';
import 'terminal_pane.dart';

abstract final class TerminalWindowInteractionLimits {
  static const int maximumGeneration =
      TerminalApplicationState.maximumIdentityValue;
}

enum TerminalWindowInteractionOwnerKind {
  terminal,
  contextDock,
  noteRail,
  noteEditor,
  systemSurface,
}

enum TerminalWindowNoteEditorPhase { clean, dirty, confirmDiscard }

/// Content-free identity for the one logical input owner in a native window.
final class TerminalWindowInteractionOwner {
  factory TerminalWindowInteractionOwner.terminal({
    required TerminalWindowId windowId,
    required PaneId paneId,
  }) => TerminalWindowInteractionOwner._(
    kind: TerminalWindowInteractionOwnerKind.terminal,
    windowId: windowId,
    paneId: paneId,
  );

  factory TerminalWindowInteractionOwner.contextDock({
    required TerminalWindowId windowId,
    required PaneId paneId,
  }) => TerminalWindowInteractionOwner._(
    kind: TerminalWindowInteractionOwnerKind.contextDock,
    windowId: windowId,
    paneId: paneId,
  );

  factory TerminalWindowInteractionOwner.noteRail({
    required TerminalWindowId windowId,
    required PaneId paneId,
    required int surfaceGeneration,
  }) => TerminalWindowInteractionOwner._(
    kind: TerminalWindowInteractionOwnerKind.noteRail,
    windowId: windowId,
    paneId: paneId,
    surfaceGeneration: surfaceGeneration,
  );

  factory TerminalWindowInteractionOwner.noteEditor({
    required TerminalWindowId windowId,
    required PaneId paneId,
    required int surfaceGeneration,
    required int draftGeneration,
  }) => TerminalWindowInteractionOwner._(
    kind: TerminalWindowInteractionOwnerKind.noteEditor,
    windowId: windowId,
    paneId: paneId,
    surfaceGeneration: surfaceGeneration,
    draftGeneration: draftGeneration,
  );

  factory TerminalWindowInteractionOwner.systemSurface({
    required TerminalWindowId windowId,
    required int surfaceGeneration,
  }) => TerminalWindowInteractionOwner._(
    kind: TerminalWindowInteractionOwnerKind.systemSurface,
    windowId: windowId,
    surfaceGeneration: surfaceGeneration,
  );

  TerminalWindowInteractionOwner._({
    required this.kind,
    required this.windowId,
    this.paneId,
    this.surfaceGeneration,
    this.draftGeneration,
  }) {
    final bool hasPane = paneId != null;
    final bool hasSurface = surfaceGeneration != null;
    final bool hasDraft = draftGeneration != null;
    final bool validShape = switch (kind) {
      TerminalWindowInteractionOwnerKind.terminal ||
      TerminalWindowInteractionOwnerKind.contextDock =>
        hasPane && !hasSurface && !hasDraft,
      TerminalWindowInteractionOwnerKind.noteRail =>
        hasPane && hasSurface && !hasDraft,
      TerminalWindowInteractionOwnerKind.noteEditor =>
        hasPane && hasSurface && hasDraft,
      TerminalWindowInteractionOwnerKind.systemSurface =>
        !hasPane && hasSurface && !hasDraft,
    };
    if (!validShape ||
        !_validGeneration(surfaceGeneration) ||
        !_validGeneration(draftGeneration)) {
      throw ArgumentError('window interaction owner identity is invalid');
    }
  }

  final TerminalWindowInteractionOwnerKind kind;
  final TerminalWindowId windowId;
  final PaneId? paneId;
  final int? surfaceGeneration;
  final int? draftGeneration;

  bool get isNoteOwner =>
      kind == TerminalWindowInteractionOwnerKind.noteRail ||
      kind == TerminalWindowInteractionOwnerKind.noteEditor;

  @override
  bool operator ==(Object other) =>
      other is TerminalWindowInteractionOwner &&
      other.kind == kind &&
      other.windowId == windowId &&
      other.paneId == paneId &&
      other.surfaceGeneration == surfaceGeneration &&
      other.draftGeneration == draftGeneration;

  @override
  int get hashCode =>
      Object.hash(kind, windowId, paneId, surfaceGeneration, draftGeneration);

  @override
  String toString() => 'TerminalWindowInteractionOwner(${kind.name})';
}

enum TerminalWindowInteractionTransferDisposition {
  requested,
  noChange,
  busy,
  rejected,
  confirmed,
  cancelled,
  stale,
  unavailable,
}

/// Single-flight token retained across native first-responder acquisition.
final class TerminalWindowInteractionTransferRequest {
  const TerminalWindowInteractionTransferRequest._({
    required this.windowId,
    required this.requestGeneration,
    required this.authorityGeneration,
    required this.topologyGeneration,
    required this.previousOwner,
    required this.requestedOwner,
  });

  final TerminalWindowId windowId;
  final int requestGeneration;
  final int authorityGeneration;
  final int topologyGeneration;
  final TerminalWindowInteractionOwner previousOwner;
  final TerminalWindowInteractionOwner requestedOwner;

  @override
  String toString() => 'TerminalWindowInteractionTransferRequest(<redacted>)';
}

final class TerminalWindowInteractionTransferResult {
  const TerminalWindowInteractionTransferResult(
    this.disposition, {
    this.request,
  });

  final TerminalWindowInteractionTransferDisposition disposition;
  final TerminalWindowInteractionTransferRequest? request;

  bool get isAccepted => switch (disposition) {
    TerminalWindowInteractionTransferDisposition.requested ||
    TerminalWindowInteractionTransferDisposition.noChange ||
    TerminalWindowInteractionTransferDisposition.confirmed ||
    TerminalWindowInteractionTransferDisposition.cancelled => true,
    _ => false,
  };

  @override
  String toString() =>
      'TerminalWindowInteractionTransferResult(${disposition.name})';
}

final class TerminalWindowInteractionSnapshot {
  const TerminalWindowInteractionSnapshot({
    required this.owner,
    required this.generation,
    required this.topologyGeneration,
    required this.transferPending,
    required this.noteEditorPhase,
  });

  final TerminalWindowInteractionOwner owner;
  final int generation;
  final int topologyGeneration;
  final bool transferPending;
  final TerminalWindowNoteEditorPhase? noteEditorPhase;

  bool get blocksHierarchyMutation =>
      transferPending ||
      noteEditorPhase == TerminalWindowNoteEditorPhase.dirty ||
      noteEditorPhase == TerminalWindowNoteEditorPhase.confirmDiscard;
}

/// Sole product authority for logical input ownership in every native window.
///
/// This class does not move native focus. Callers request a transfer, acquire
/// the native first responder, then confirm the same generation-bound token.
final class TerminalWindowInteractionAuthority {
  TerminalWindowInteractionAuthority(this.applicationState) {
    synchronize();
  }

  final TerminalApplicationState applicationState;
  final Map<TerminalWindowId, _TerminalWindowInteractionState> _windows =
      <TerminalWindowId, _TerminalWindowInteractionState>{};
  var _nextRequestGeneration = 1;
  var _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get windowCount => _windows.length;

  TerminalWindowInteractionSnapshot? snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed) return null;
    final _TerminalWindowInteractionState? window = _windows[windowId];
    return window == null ? null : _snapshot(window);
  }

  /// Reconciles owner liveness after a settled hierarchy mutation.
  ///
  /// A call while the hierarchy is mutating observes no partial topology and
  /// leaves the current owner untouched. Input routing must separately reject
  /// while [TerminalApplicationState.mutationInProgress] is true.
  bool synchronize() {
    _ensureAlive();
    if (applicationState.mutationInProgress) return false;
    if (applicationState.isDisposed) {
      final bool changed = _windows.isNotEmpty;
      _windows.clear();
      return changed;
    }
    final Set<TerminalWindowId> live = applicationState.windowIds.toSet();
    var changed = false;
    for (final TerminalWindowId stale
        in _windows.keys
            .where((TerminalWindowId id) => !live.contains(id))
            .toList(growable: false)) {
      _windows.remove(stale);
      changed = true;
    }
    for (final TerminalWindowState applicationWindow
        in applicationState.windows) {
      final PaneId focusedPaneId = applicationWindow.selectedTab.focusedPaneId;
      final String topologySignature = _topologySignature(applicationWindow);
      final _TerminalWindowInteractionState? existing =
          _windows[applicationWindow.id];
      if (existing == null) {
        _windows[applicationWindow.id] = _TerminalWindowInteractionState(
          windowId: applicationWindow.id,
          owner: TerminalWindowInteractionOwner.terminal(
            windowId: applicationWindow.id,
            paneId: focusedPaneId,
          ),
          topologySignature: topologySignature,
        );
        changed = true;
        continue;
      }
      if (existing.topologySignature == topologySignature) continue;
      existing
        ..topologySignature = topologySignature
        ..topologyGeneration = _advance(existing.topologyGeneration)
        ..generation = _advance(existing.generation)
        ..pending = null;
      if (!_ownerIsLive(existing.owner, applicationWindow)) {
        existing
          ..owner = TerminalWindowInteractionOwner.terminal(
            windowId: applicationWindow.id,
            paneId: focusedPaneId,
          )
          ..noteEditorPhase = null;
      }
      changed = true;
    }
    _validate();
    return changed;
  }

  TerminalWindowInteractionTransferResult requestOwner(
    TerminalWindowInteractionOwner requestedOwner,
  ) {
    _ensureAlive();
    final _TerminalWindowInteractionState? window =
        _windows[requestedOwner.windowId];
    if (window == null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.unavailable,
      );
    }
    if (applicationState.mutationInProgress ||
        !_ownerIsLive(
          requestedOwner,
          applicationState.windowForId(requestedOwner.windowId),
        )) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.rejected,
      );
    }
    if (window.pending != null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.busy,
      );
    }
    if (window.owner == requestedOwner) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.noChange,
      );
    }
    if (_blocksOwnerExit(window) ||
        (window.owner.kind ==
                TerminalWindowInteractionOwnerKind.systemSurface &&
            requestedOwner.kind !=
                TerminalWindowInteractionOwnerKind.terminal)) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.rejected,
      );
    }
    final int requestGeneration = _takeRequestGeneration();
    window.generation = _advance(window.generation);
    final TerminalWindowInteractionTransferRequest request =
        TerminalWindowInteractionTransferRequest._(
          windowId: requestedOwner.windowId,
          requestGeneration: requestGeneration,
          authorityGeneration: window.generation,
          topologyGeneration: window.topologyGeneration,
          previousOwner: window.owner,
          requestedOwner: requestedOwner,
        );
    window.pending = request;
    _validate();
    return TerminalWindowInteractionTransferResult(
      TerminalWindowInteractionTransferDisposition.requested,
      request: request,
    );
  }

  TerminalWindowInteractionTransferResult requestTerminal(
    TerminalWindowId windowId,
  ) {
    final TerminalWindowState? window = applicationState.windowForId(windowId);
    if (window == null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.unavailable,
      );
    }
    return requestOwner(
      TerminalWindowInteractionOwner.terminal(
        windowId: windowId,
        paneId: window.selectedTab.focusedPaneId,
      ),
    );
  }

  TerminalWindowInteractionTransferResult confirm(
    TerminalWindowInteractionTransferRequest request,
  ) {
    _ensureAlive();
    final _TerminalWindowInteractionState? window = _windows[request.windowId];
    if (window == null) return _staleResult;
    if (applicationState.mutationInProgress ||
        !identical(window.pending, request) ||
        window.generation != request.authorityGeneration ||
        window.topologyGeneration != request.topologyGeneration ||
        window.owner != request.previousOwner ||
        !_ownerIsLive(
          request.requestedOwner,
          applicationState.windowForId(request.windowId),
        )) {
      _clearMatchingStale(window, request);
      return _staleResult;
    }
    window
      ..owner = request.requestedOwner
      ..pending = null
      ..noteEditorPhase =
          request.requestedOwner.kind ==
              TerminalWindowInteractionOwnerKind.noteEditor
          ? TerminalWindowNoteEditorPhase.clean
          : null
      ..generation = _advance(window.generation);
    _validate();
    return const TerminalWindowInteractionTransferResult(
      TerminalWindowInteractionTransferDisposition.confirmed,
    );
  }

  TerminalWindowInteractionTransferResult cancel(
    TerminalWindowInteractionTransferRequest request,
  ) {
    _ensureAlive();
    final _TerminalWindowInteractionState? window = _windows[request.windowId];
    if (window == null || !identical(window.pending, request)) {
      return _staleResult;
    }
    window
      ..pending = null
      ..generation = _advance(window.generation);
    _validate();
    return const TerminalWindowInteractionTransferResult(
      TerminalWindowInteractionTransferDisposition.cancelled,
    );
  }

  bool setNoteEditorPhase(
    TerminalWindowId windowId,
    TerminalWindowNoteEditorPhase phase,
  ) {
    _ensureAlive();
    final _TerminalWindowInteractionState? window = _windows[windowId];
    if (window == null ||
        window.pending != null ||
        window.owner.kind != TerminalWindowInteractionOwnerKind.noteEditor) {
      return false;
    }
    if (window.noteEditorPhase == phase) return false;
    window
      ..noteEditorPhase = phase
      ..generation = _advance(window.generation);
    _validate();
    return true;
  }

  bool permitsHierarchyMutation(TerminalWindowId windowId) {
    if (_isDisposed || applicationState.mutationInProgress) return false;
    final _TerminalWindowInteractionState? window = _windows[windowId];
    return window != null && !_snapshot(window).blocksHierarchyMutation;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _windows.clear();
  }

  static const TerminalWindowInteractionTransferResult _staleResult =
      TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.stale,
      );

  void _clearMatchingStale(
    _TerminalWindowInteractionState window,
    TerminalWindowInteractionTransferRequest request,
  ) {
    if (!identical(window.pending, request)) return;
    window
      ..pending = null
      ..generation = _advance(window.generation);
  }

  int _takeRequestGeneration() {
    if (_nextRequestGeneration >
        TerminalWindowInteractionLimits.maximumGeneration) {
      throw StateError('window interaction request generation exhausted');
    }
    return _nextRequestGeneration++;
  }

  void _validate() {
    if (_windows.length > TerminalApplicationStateLimits.maximumWindows) {
      throw StateError('window interaction authority window bound exceeded');
    }
    for (final _TerminalWindowInteractionState window in _windows.values) {
      if (window.owner.windowId != window.windowId ||
          window.generation <= 0 ||
          window.topologyGeneration <= 0 ||
          (window.owner.kind ==
                  TerminalWindowInteractionOwnerKind.noteEditor) !=
              (window.noteEditorPhase != null) ||
          (window.pending != null &&
              (window.pending!.windowId != window.windowId ||
                  window.pending!.previousOwner != window.owner))) {
        throw StateError('window interaction authority state is inconsistent');
      }
    }
  }

  void _ensureAlive() {
    if (_isDisposed) {
      throw StateError('window interaction authority is disposed');
    }
  }

  static TerminalWindowInteractionSnapshot _snapshot(
    _TerminalWindowInteractionState window,
  ) => TerminalWindowInteractionSnapshot(
    owner: window.owner,
    generation: window.generation,
    topologyGeneration: window.topologyGeneration,
    transferPending: window.pending != null,
    noteEditorPhase: window.noteEditorPhase,
  );

  static bool _blocksOwnerExit(_TerminalWindowInteractionState window) =>
      window.noteEditorPhase == TerminalWindowNoteEditorPhase.dirty ||
      window.noteEditorPhase == TerminalWindowNoteEditorPhase.confirmDiscard;

  static bool _ownerIsLive(
    TerminalWindowInteractionOwner owner,
    TerminalWindowState? window,
  ) {
    if (window == null || owner.windowId != window.id) return false;
    if (owner.kind == TerminalWindowInteractionOwnerKind.systemSurface) {
      return true;
    }
    return owner.paneId == window.selectedTab.focusedPaneId;
  }

  static String _topologySignature(TerminalWindowState window) {
    final StringBuffer result = StringBuffer()
      ..write(window.role.index)
      ..write(':')
      ..write(window.selectedTabId.value);
    for (final TerminalTabState tab in window.tabs) {
      result
        ..write('|')
        ..write(tab.id.value)
        ..write(':')
        ..write(tab.focusedPaneId.value)
        ..write(':')
        ..write(tab.zoomedPaneId?.value ?? 0)
        ..write(':');
      for (final PaneId paneId in tab.paneIds) {
        result
          ..write(paneId.value)
          ..write(',');
      }
    }
    return result.toString();
  }
}

final class _TerminalWindowInteractionState {
  _TerminalWindowInteractionState({
    required this.windowId,
    required this.owner,
    required this.topologySignature,
  });

  final TerminalWindowId windowId;
  TerminalWindowInteractionOwner owner;
  String topologySignature;
  int generation = 1;
  int topologyGeneration = 1;
  TerminalWindowInteractionTransferRequest? pending;
  TerminalWindowNoteEditorPhase? noteEditorPhase;
}

bool _validGeneration(int? value) =>
    value == null ||
    (value > 0 && value <= TerminalWindowInteractionLimits.maximumGeneration);

int _advance(int value) {
  if (value >= TerminalWindowInteractionLimits.maximumGeneration) {
    throw StateError('window interaction generation exhausted');
  }
  return value + 1;
}
