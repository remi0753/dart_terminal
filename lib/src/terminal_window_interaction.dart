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

enum TerminalWindowInteractionInputFamily {
  rawKey,
  ime,
  menuKeyEquivalent,
  copy,
  cutPasteSelectAll,
  servicesText,
  plainTextDrop,
  richOrFileDrop,
  mouse,
  scroll,
  accessibility,
  automationWrite,
}

enum TerminalWindowInteractionRouteTarget {
  terminal,
  contextDock,
  noteRail,
  noteEditor,
  systemSurface,
  applicationAction,
  consumed,
  interactionBusy,
  stale,
}

final class TerminalWindowInteractionRouteResult {
  const TerminalWindowInteractionRouteResult({
    required this.target,
    required this.authorityGeneration,
  });

  final TerminalWindowInteractionRouteTarget target;
  final int authorityGeneration;

  bool get forwardsToTerminal =>
      target == TerminalWindowInteractionRouteTarget.terminal;

  @override
  String toString() => 'TerminalWindowInteractionRouteResult(${target.name})';
}

enum TerminalWindowConsumedGesturePhase {
  down,
  drag,
  up,
  scroll,
  momentum,
  cancel,
}

enum TerminalWindowConsumedGestureDisposition {
  started,
  consumedCurrent,
  consumedStale,
  rejected,
  busy,
}

/// Opaque identity proving that one Note child consumed a pointer sequence.
final class TerminalWindowConsumedGestureIdentity {
  const TerminalWindowConsumedGestureIdentity._({
    required this.windowId,
    required this.paneId,
    required this.surfaceGeneration,
    required this.authorityGeneration,
    required this.gestureGeneration,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int surfaceGeneration;
  final int authorityGeneration;
  final int gestureGeneration;

  @override
  String toString() => 'TerminalWindowConsumedGestureIdentity(<redacted>)';
}

final class TerminalWindowConsumedGestureResult {
  const TerminalWindowConsumedGestureResult(this.disposition, {this.identity});

  final TerminalWindowConsumedGestureDisposition disposition;
  final TerminalWindowConsumedGestureIdentity? identity;

  bool get forwardsToTerminal => false;
}

/// Owner-aware, side-effect-free routing decisions plus bounded Note gesture
/// identities. Native adapters remain responsible for the actual operation.
final class TerminalWindowInteractionRouter {
  TerminalWindowInteractionRouter(this.authority);

  static const int maximumConsumedGestures = 64;

  final TerminalWindowInteractionAuthority authority;
  final Map<int, TerminalWindowConsumedGestureIdentity> _gestures =
      <int, TerminalWindowConsumedGestureIdentity>{};
  var _nextGestureGeneration = 1;
  var _isDisposed = false;

  int get activeConsumedGestureCount => _gestures.length;
  bool get isDisposed => _isDisposed;

  TerminalWindowInteractionRouteResult route({
    required TerminalWindowId windowId,
    required PaneId paneId,
    required TerminalWindowInteractionInputFamily family,
    int? expectedAuthorityGeneration,
  }) {
    _ensureAlive();
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (snapshot == null ||
        (expectedAuthorityGeneration != null &&
            expectedAuthorityGeneration != snapshot.generation)) {
      return TerminalWindowInteractionRouteResult(
        target: TerminalWindowInteractionRouteTarget.stale,
        authorityGeneration: snapshot?.generation ?? 0,
      );
    }
    if (authority.applicationState.mutationInProgress ||
        snapshot.transferPending) {
      return TerminalWindowInteractionRouteResult(
        target: TerminalWindowInteractionRouteTarget.consumed,
        authorityGeneration: snapshot.generation,
      );
    }
    final TerminalWindowInteractionOwner owner = snapshot.owner;
    if (owner.paneId != null && owner.paneId != paneId) {
      return TerminalWindowInteractionRouteResult(
        target: TerminalWindowInteractionRouteTarget.stale,
        authorityGeneration: snapshot.generation,
      );
    }
    final TerminalWindowInteractionRouteTarget target = switch (owner.kind) {
      TerminalWindowInteractionOwnerKind.terminal =>
        family == TerminalWindowInteractionInputFamily.menuKeyEquivalent
            ? TerminalWindowInteractionRouteTarget.applicationAction
            : TerminalWindowInteractionRouteTarget.terminal,
      TerminalWindowInteractionOwnerKind.contextDock => switch (family) {
        TerminalWindowInteractionInputFamily.menuKeyEquivalent =>
          TerminalWindowInteractionRouteTarget.applicationAction,
        TerminalWindowInteractionInputFamily.automationWrite =>
          TerminalWindowInteractionRouteTarget.terminal,
        _ => TerminalWindowInteractionRouteTarget.contextDock,
      },
      TerminalWindowInteractionOwnerKind.noteRail => switch (family) {
        TerminalWindowInteractionInputFamily.menuKeyEquivalent =>
          TerminalWindowInteractionRouteTarget.applicationAction,
        TerminalWindowInteractionInputFamily.automationWrite =>
          TerminalWindowInteractionRouteTarget.interactionBusy,
        TerminalWindowInteractionInputFamily.ime ||
        TerminalWindowInteractionInputFamily.cutPasteSelectAll ||
        TerminalWindowInteractionInputFamily.servicesText ||
        TerminalWindowInteractionInputFamily.plainTextDrop ||
        TerminalWindowInteractionInputFamily.richOrFileDrop =>
          TerminalWindowInteractionRouteTarget.consumed,
        _ => TerminalWindowInteractionRouteTarget.noteRail,
      },
      TerminalWindowInteractionOwnerKind.noteEditor => switch (family) {
        TerminalWindowInteractionInputFamily.menuKeyEquivalent =>
          TerminalWindowInteractionRouteTarget.applicationAction,
        TerminalWindowInteractionInputFamily.automationWrite =>
          TerminalWindowInteractionRouteTarget.interactionBusy,
        _ => TerminalWindowInteractionRouteTarget.noteEditor,
      },
      TerminalWindowInteractionOwnerKind.systemSurface =>
        TerminalWindowInteractionRouteTarget.systemSurface,
    };
    return TerminalWindowInteractionRouteResult(
      target: target,
      authorityGeneration: snapshot.generation,
    );
  }

  TerminalWindowConsumedGestureResult beginNoteGesture({
    required TerminalWindowId windowId,
    required PaneId paneId,
    required int surfaceGeneration,
    required int eventSequence,
  }) {
    _ensureAlive();
    if (!_validGeneration(surfaceGeneration) ||
        !_validGeneration(eventSequence)) {
      return const TerminalWindowConsumedGestureResult(
        TerminalWindowConsumedGestureDisposition.rejected,
      );
    }
    if (_gestures.length >= maximumConsumedGestures) {
      return const TerminalWindowConsumedGestureResult(
        TerminalWindowConsumedGestureDisposition.busy,
      );
    }
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    final TerminalWindowInteractionOwner? owner = snapshot?.owner;
    if (snapshot == null ||
        snapshot.transferPending ||
        authority.applicationState.mutationInProgress ||
        owner == null ||
        !owner.isNoteOwner ||
        owner.paneId != paneId ||
        owner.surfaceGeneration != surfaceGeneration) {
      return const TerminalWindowConsumedGestureResult(
        TerminalWindowConsumedGestureDisposition.rejected,
      );
    }
    final int generation = _takeGestureGeneration();
    final TerminalWindowConsumedGestureIdentity identity =
        TerminalWindowConsumedGestureIdentity._(
          windowId: windowId,
          paneId: paneId,
          surfaceGeneration: surfaceGeneration,
          authorityGeneration: snapshot.generation,
          gestureGeneration: generation,
        );
    _gestures[generation] = identity;
    return TerminalWindowConsumedGestureResult(
      TerminalWindowConsumedGestureDisposition.started,
      identity: identity,
    );
  }

  TerminalWindowConsumedGestureResult consumeGesture(
    TerminalWindowConsumedGestureIdentity identity,
    TerminalWindowConsumedGesturePhase phase,
  ) {
    _ensureAlive();
    final bool wasActive = identical(
      _gestures[identity.gestureGeneration],
      identity,
    );
    if (phase == TerminalWindowConsumedGesturePhase.up ||
        phase == TerminalWindowConsumedGesturePhase.cancel) {
      _gestures.remove(identity.gestureGeneration);
    }
    if (!wasActive) {
      return const TerminalWindowConsumedGestureResult(
        TerminalWindowConsumedGestureDisposition.consumedStale,
      );
    }
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(identity.windowId);
    final TerminalWindowInteractionOwner? owner = snapshot?.owner;
    final bool current =
        snapshot != null &&
        !snapshot.transferPending &&
        snapshot.generation == identity.authorityGeneration &&
        owner != null &&
        owner.isNoteOwner &&
        owner.paneId == identity.paneId &&
        owner.surfaceGeneration == identity.surfaceGeneration;
    return TerminalWindowConsumedGestureResult(
      current
          ? TerminalWindowConsumedGestureDisposition.consumedCurrent
          : TerminalWindowConsumedGestureDisposition.consumedStale,
    );
  }

  void synchronizeGestures() {
    _ensureAlive();
    _gestures.removeWhere(
      (_, TerminalWindowConsumedGestureIdentity identity) =>
          authority.snapshotForWindow(identity.windowId) == null,
    );
  }

  int releaseNoteGestures({
    required TerminalWindowId windowId,
    required PaneId paneId,
    required int surfaceGeneration,
  }) {
    _ensureAlive();
    final int before = _gestures.length;
    _gestures.removeWhere(
      (_, TerminalWindowConsumedGestureIdentity identity) =>
          identity.windowId == windowId &&
          identity.paneId == paneId &&
          identity.surfaceGeneration == surfaceGeneration,
    );
    return before - _gestures.length;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _gestures.clear();
  }

  int _takeGestureGeneration() {
    if (_nextGestureGeneration >
        TerminalWindowInteractionLimits.maximumGeneration) {
      throw StateError('window consumed gesture generation exhausted');
    }
    return _nextGestureGeneration++;
  }

  void _ensureAlive() {
    if (_isDisposed) throw StateError('window interaction router is disposed');
  }
}

enum TerminalWindowNoteOutsideDisposition {
  focusTransferRequested,
  discardConfirmation,
  noChange,
  busy,
  rejected,
  stale,
  unavailable,
}

/// Content-free result for an outside pointer-down while a Note owns input.
///
/// The current pointer event is always consumed. A caller may move native
/// focus only for [focusTransferRequested], then confirm the attached token.
final class TerminalWindowNoteOutsideResult {
  const TerminalWindowNoteOutsideResult(this.disposition, {this.request});

  final TerminalWindowNoteOutsideDisposition disposition;
  final TerminalWindowInteractionTransferRequest? request;

  bool get forwardsToTerminal => false;
}

/// Product adapter binding one native Note surface to the sole window input
/// authority. It owns no Note content and performs no native focus mutation.
///
/// Focus transfer remains two-phase: request here, move the native first
/// responder, then call [confirmNativeFocus]. Teardown must similarly return
/// ownership, dispose this adapter, and only then destroy the native view.
final class TerminalWindowNoteInteractionAdapter {
  TerminalWindowNoteInteractionAdapter({
    required this.authority,
    required this.router,
    required this.windowId,
    required this.paneId,
    required this.surfaceGeneration,
  }) {
    if (!_validGeneration(surfaceGeneration)) {
      throw ArgumentError.value(
        surfaceGeneration,
        'surfaceGeneration',
        'must be a positive bounded generation',
      );
    }
  }

  final TerminalWindowInteractionAuthority authority;
  final TerminalWindowInteractionRouter router;
  final TerminalWindowId windowId;
  final PaneId paneId;
  final int surfaceGeneration;

  TerminalWindowInteractionTransferRequest? _pendingFocus;
  var _isDisposed = false;

  bool get isDisposed => _isDisposed;
  bool get hasPendingNativeFocus => _pendingFocus != null;

  TerminalWindowInteractionTransferResult requestRailFocus() => _requestOwner(
    TerminalWindowInteractionOwner.noteRail(
      windowId: windowId,
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
    ),
  );

  TerminalWindowInteractionTransferResult requestEditorFocus({
    required int draftGeneration,
  }) => _requestOwner(
    TerminalWindowInteractionOwner.noteEditor(
      windowId: windowId,
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
      draftGeneration: draftGeneration,
    ),
  );

  TerminalWindowInteractionTransferResult confirmNativeFocus(
    TerminalWindowInteractionTransferRequest request,
  ) {
    _ensureAlive();
    if (!identical(_pendingFocus, request)) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.stale,
      );
    }
    _pendingFocus = null;
    return authority.confirm(request);
  }

  TerminalWindowInteractionTransferResult cancelNativeFocus(
    TerminalWindowInteractionTransferRequest request,
  ) {
    _ensureAlive();
    if (!identical(_pendingFocus, request)) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.stale,
      );
    }
    _pendingFocus = null;
    return authority.cancel(request);
  }

  bool synchronizeEditorPhase({
    required bool dirty,
    required bool confirmingDiscard,
  }) {
    _ensureAlive();
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (!_ownsEditor(snapshot)) return false;
    final TerminalWindowNoteEditorPhase phase = confirmingDiscard
        ? TerminalWindowNoteEditorPhase.confirmDiscard
        : dirty
        ? TerminalWindowNoteEditorPhase.dirty
        : TerminalWindowNoteEditorPhase.clean;
    if (snapshot!.noteEditorPhase == phase) return true;
    return authority.setNoteEditorPhase(windowId, phase);
  }

  TerminalWindowInteractionRouteResult route(
    TerminalWindowInteractionInputFamily family, {
    int? expectedAuthorityGeneration,
  }) {
    _ensureAlive();
    return router.route(
      windowId: windowId,
      paneId: paneId,
      family: family,
      expectedAuthorityGeneration: expectedAuthorityGeneration,
    );
  }

  TerminalWindowConsumedGestureResult beginGesture({
    required int eventSequence,
  }) {
    _ensureAlive();
    return router.beginNoteGesture(
      windowId: windowId,
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
      eventSequence: eventSequence,
    );
  }

  TerminalWindowConsumedGestureResult consumeGesture(
    TerminalWindowConsumedGestureIdentity identity,
    TerminalWindowConsumedGesturePhase phase,
  ) {
    _ensureAlive();
    return router.consumeGesture(identity, phase);
  }

  TerminalWindowNoteOutsideResult handleOutsidePointerDown() {
    _ensureAlive();
    if (_pendingFocus != null) {
      return const TerminalWindowNoteOutsideResult(
        TerminalWindowNoteOutsideDisposition.busy,
      );
    }
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (!_ownsSurface(snapshot)) {
      return const TerminalWindowNoteOutsideResult(
        TerminalWindowNoteOutsideDisposition.stale,
      );
    }
    if (snapshot!.owner.kind == TerminalWindowInteractionOwnerKind.noteEditor &&
        snapshot.noteEditorPhase != TerminalWindowNoteEditorPhase.clean) {
      if (snapshot.noteEditorPhase == TerminalWindowNoteEditorPhase.dirty) {
        authority.setNoteEditorPhase(
          windowId,
          TerminalWindowNoteEditorPhase.confirmDiscard,
        );
      }
      return const TerminalWindowNoteOutsideResult(
        TerminalWindowNoteOutsideDisposition.discardConfirmation,
      );
    }
    final TerminalWindowInteractionTransferResult transfer = authority
        .requestTerminal(windowId);
    if (transfer.request != null) _pendingFocus = transfer.request;
    return TerminalWindowNoteOutsideResult(
      _outsideDisposition(transfer.disposition),
      request: transfer.request,
    );
  }

  bool keepEditingAfterDiscardConfirmation() {
    _ensureAlive();
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (!_ownsEditor(snapshot) ||
        snapshot!.noteEditorPhase !=
            TerminalWindowNoteEditorPhase.confirmDiscard) {
      return false;
    }
    return authority.setNoteEditorPhase(
      windowId,
      TerminalWindowNoteEditorPhase.dirty,
    );
  }

  TerminalWindowInteractionTransferResult requestTerminalAfterResolution() {
    _ensureAlive();
    if (_pendingFocus != null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.busy,
      );
    }
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (!_ownsSurface(snapshot)) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.stale,
      );
    }
    if (snapshot!.owner.kind == TerminalWindowInteractionOwnerKind.noteEditor &&
        snapshot.noteEditorPhase != TerminalWindowNoteEditorPhase.clean) {
      authority.setNoteEditorPhase(
        windowId,
        TerminalWindowNoteEditorPhase.clean,
      );
    }
    final TerminalWindowInteractionTransferResult transfer = authority
        .requestTerminal(windowId);
    if (transfer.request != null) _pendingFocus = transfer.request;
    return transfer;
  }

  TerminalWindowInteractionTransferResult prepareForViewTeardown() {
    _ensureAlive();
    router.releaseNoteGestures(
      windowId: windowId,
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
    );
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (snapshot == null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.unavailable,
      );
    }
    if (!_ownsSurface(snapshot)) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.noChange,
      );
    }
    if (snapshot.blocksHierarchyMutation) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.rejected,
      );
    }
    return requestTerminalAfterResolution();
  }

  void dispose() {
    if (_isDisposed) return;
    final TerminalWindowInteractionTransferRequest? pending = _pendingFocus;
    if (pending != null) {
      authority.cancel(pending);
      _pendingFocus = null;
    }
    router.releaseNoteGestures(
      windowId: windowId,
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
    );
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (_ownsSurface(snapshot)) {
      throw StateError(
        'Note interaction adapter still owns input during teardown',
      );
    }
    _isDisposed = true;
  }

  TerminalWindowInteractionTransferResult _requestOwner(
    TerminalWindowInteractionOwner owner,
  ) {
    _ensureAlive();
    if (_pendingFocus != null) {
      return const TerminalWindowInteractionTransferResult(
        TerminalWindowInteractionTransferDisposition.busy,
      );
    }
    final TerminalWindowInteractionTransferResult transfer = authority
        .requestOwner(owner);
    if (transfer.request != null) _pendingFocus = transfer.request;
    return transfer;
  }

  bool _ownsSurface(TerminalWindowInteractionSnapshot? snapshot) =>
      snapshot != null &&
      snapshot.owner.isNoteOwner &&
      snapshot.owner.windowId == windowId &&
      snapshot.owner.paneId == paneId &&
      snapshot.owner.surfaceGeneration == surfaceGeneration;

  bool _ownsEditor(TerminalWindowInteractionSnapshot? snapshot) =>
      _ownsSurface(snapshot) &&
      snapshot!.owner.kind == TerminalWindowInteractionOwnerKind.noteEditor;

  static TerminalWindowNoteOutsideDisposition _outsideDisposition(
    TerminalWindowInteractionTransferDisposition disposition,
  ) => switch (disposition) {
    TerminalWindowInteractionTransferDisposition.requested =>
      TerminalWindowNoteOutsideDisposition.focusTransferRequested,
    TerminalWindowInteractionTransferDisposition.noChange =>
      TerminalWindowNoteOutsideDisposition.noChange,
    TerminalWindowInteractionTransferDisposition.busy =>
      TerminalWindowNoteOutsideDisposition.busy,
    TerminalWindowInteractionTransferDisposition.rejected =>
      TerminalWindowNoteOutsideDisposition.rejected,
    TerminalWindowInteractionTransferDisposition.stale =>
      TerminalWindowNoteOutsideDisposition.stale,
    TerminalWindowInteractionTransferDisposition.unavailable =>
      TerminalWindowNoteOutsideDisposition.unavailable,
    TerminalWindowInteractionTransferDisposition.confirmed ||
    TerminalWindowInteractionTransferDisposition.cancelled =>
      TerminalWindowNoteOutsideDisposition.stale,
  };

  void _ensureAlive() {
    if (_isDisposed) {
      throw StateError('Note interaction adapter is disposed');
    }
  }
}

/// Binds native system-surface presentation lifecycles to the one logical
/// owner without retaining presenter content or constructing an owner stack.
///
/// A presenter calls [present] only after acquiring its native responder and
/// [dismiss] only after restoring the terminal responder. Multiple concurrent
/// system surfaces in one terminal window share one priority owner; the last
/// dismissal returns explicitly to the currently focused terminal.
final class TerminalWindowSystemSurfaceCoordinator {
  TerminalWindowSystemSurfaceCoordinator(this.authority);

  static const int maximumActiveSurfaces = 32;

  final TerminalWindowInteractionAuthority authority;
  final List<_TerminalWindowSystemSurfaceLease> _leases =
      <_TerminalWindowSystemSurfaceLease>[];
  var _nextSurfaceGeneration = 1;
  var _isDisposed = false;

  int get activeSurfaceCount => _leases.length;
  bool get isDisposed => _isDisposed;

  bool present(Object identity, TerminalWindowId windowId) {
    _ensureAlive();
    final _TerminalWindowSystemSurfaceLease? existing = _leaseFor(identity);
    if (existing != null) return existing.windowId == windowId;
    if (_leases.length >= maximumActiveSurfaces) return false;
    authority.synchronize();
    if (authority.snapshotForWindow(windowId) == null) return false;
    final bool alreadyPresented = _leases.any(
      (_TerminalWindowSystemSurfaceLease lease) => lease.windowId == windowId,
    );
    if (!alreadyPresented) {
      final int generation = _takeSurfaceGeneration();
      final TerminalWindowInteractionTransferResult requested = authority
          .requestOwner(
            TerminalWindowInteractionOwner.systemSurface(
              windowId: windowId,
              surfaceGeneration: generation,
            ),
          );
      if (requested.disposition ==
          TerminalWindowInteractionTransferDisposition.requested) {
        if (authority.confirm(requested.request!).disposition !=
            TerminalWindowInteractionTransferDisposition.confirmed) {
          return false;
        }
      } else if (requested.disposition !=
          TerminalWindowInteractionTransferDisposition.noChange) {
        return false;
      }
    }
    if (authority.snapshotForWindow(windowId)?.owner.kind !=
        TerminalWindowInteractionOwnerKind.systemSurface) {
      return false;
    }
    _leases.add(
      _TerminalWindowSystemSurfaceLease(identity: identity, windowId: windowId),
    );
    return true;
  }

  bool dismiss(Object identity) {
    _ensureAlive();
    final int index = _leases.indexWhere(
      (_TerminalWindowSystemSurfaceLease lease) =>
          identical(lease.identity, identity),
    );
    if (index < 0) return false;
    final TerminalWindowId windowId = _leases.removeAt(index).windowId;
    if (_leases.any(
      (_TerminalWindowSystemSurfaceLease lease) => lease.windowId == windowId,
    )) {
      return true;
    }
    authority.synchronize();
    final TerminalWindowInteractionSnapshot? snapshot = authority
        .snapshotForWindow(windowId);
    if (snapshot == null ||
        snapshot.owner.kind !=
            TerminalWindowInteractionOwnerKind.systemSurface) {
      return true;
    }
    final TerminalWindowInteractionTransferResult requested = authority
        .requestTerminal(windowId);
    if (requested.disposition ==
        TerminalWindowInteractionTransferDisposition.noChange) {
      return true;
    }
    return requested.disposition ==
            TerminalWindowInteractionTransferDisposition.requested &&
        authority.confirm(requested.request!).disposition ==
            TerminalWindowInteractionTransferDisposition.confirmed;
  }

  void synchronize() {
    _ensureAlive();
    authority.synchronize();
    _leases.removeWhere(
      (_TerminalWindowSystemSurfaceLease lease) =>
          authority.snapshotForWindow(lease.windowId) == null,
    );
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _leases.clear();
  }

  _TerminalWindowSystemSurfaceLease? _leaseFor(Object identity) {
    for (final _TerminalWindowSystemSurfaceLease lease in _leases) {
      if (identical(lease.identity, identity)) return lease;
    }
    return null;
  }

  int _takeSurfaceGeneration() {
    if (_nextSurfaceGeneration >
        TerminalWindowInteractionLimits.maximumGeneration) {
      throw StateError('system surface generation exhausted');
    }
    return _nextSurfaceGeneration++;
  }

  void _ensureAlive() {
    if (_isDisposed) {
      throw StateError('system surface coordinator is disposed');
    }
  }
}

final class _TerminalWindowSystemSurfaceLease {
  const _TerminalWindowSystemSurfaceLease({
    required this.identity,
    required this.windowId,
  });

  final Object identity;
  final TerminalWindowId windowId;
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
