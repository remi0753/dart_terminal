import 'dart:collection';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';
import 'terminal_pane.dart';
import 'terminal_pane_close_coordinator.dart';

typedef TerminalApplicationTerminationReply = void Function(
  ApplicationTerminateRequestedEvent request, {
  required bool allow,
});

enum TerminalApplicationQuitDisposition {
  confirmationRequired,
  terminated,
  terminatedWithCleanupFailure,
  stale,
  busy,
}

/// One pane's content-free identity and process state in a quit transaction.
final class TerminalApplicationQuitPaneSnapshot {
  const TerminalApplicationQuitPaneSnapshot({
    required this.paneId,
    required this.sessionId,
    required this.processDisposition,
    required this.childProcessId,
    required this.owningProcessGroup,
    required this.foregroundProcessGroup,
    required this.owningProcessGroupSystemError,
    required this.foregroundProcessGroupSystemError,
  });

  factory TerminalApplicationQuitPaneSnapshot.fromPane(TerminalPane pane) {
    TerminalPaneProcessSnapshot observed;
    try {
      observed = pane.processSnapshot();
    } on Object {
      observed = TerminalPaneProcessSnapshot.unavailable(
        sessionId: pane.sessionId,
      );
    }
    if (observed.sessionId != pane.sessionId) {
      observed = TerminalPaneProcessSnapshot.unavailable(
        sessionId: pane.sessionId,
      );
    }
    return TerminalApplicationQuitPaneSnapshot(
      paneId: pane.id,
      sessionId: pane.sessionId,
      processDisposition: observed.disposition,
      childProcessId: observed.childProcessId,
      owningProcessGroup: observed.owningProcessGroup,
      foregroundProcessGroup: observed.foregroundProcessGroup,
      owningProcessGroupSystemError: observed.owningProcessGroupSystemError,
      foregroundProcessGroupSystemError:
          observed.foregroundProcessGroupSystemError,
    );
  }

  final PaneId paneId;
  final TerminalSessionId sessionId;
  final TerminalPaneProcessDisposition processDisposition;
  final int? childProcessId;
  final int? owningProcessGroup;
  final int? foregroundProcessGroup;
  final int owningProcessGroupSystemError;
  final int foregroundProcessGroupSystemError;

  bool get requiresConfirmation =>
      processDisposition == TerminalPaneProcessDisposition.foregroundProcess ||
      processDisposition == TerminalPaneProcessDisposition.unavailable;

  @override
  bool operator ==(Object other) =>
      other is TerminalApplicationQuitPaneSnapshot &&
      other.paneId == paneId &&
      other.sessionId == sessionId &&
      other.processDisposition == processDisposition &&
      other.childProcessId == childProcessId &&
      other.owningProcessGroup == owningProcessGroup &&
      other.foregroundProcessGroup == foregroundProcessGroup &&
      other.owningProcessGroupSystemError == owningProcessGroupSystemError &&
      other.foregroundProcessGroupSystemError ==
          foregroundProcessGroupSystemError;

  @override
  int get hashCode => Object.hash(
    paneId,
    sessionId,
    processDisposition,
    childProcessId,
    owningProcessGroup,
    foregroundProcessGroup,
    owningProcessGroupSystemError,
    foregroundProcessGroupSystemError,
  );
}

/// Immutable, deterministic all-pane admission state for one Quit request.
final class TerminalApplicationQuitSnapshot {
  TerminalApplicationQuitSnapshot(
    Iterable<TerminalApplicationQuitPaneSnapshot> panes,
  ) : panes = List<TerminalApplicationQuitPaneSnapshot>.unmodifiable(panes);

  final List<TerminalApplicationQuitPaneSnapshot> panes;

  bool get requiresConfirmation => panes.any(
    (TerminalApplicationQuitPaneSnapshot pane) => pane.requiresConfirmation,
  );

  int count(TerminalPaneProcessDisposition disposition) => panes
      .where(
        (TerminalApplicationQuitPaneSnapshot pane) =>
            pane.processDisposition == disposition,
      )
      .length;

  String machineLine() =>
      'TERMINAL_APPLICATION_QUIT_SNAPSHOT panes=${panes.length} '
      'non_live=${count(TerminalPaneProcessDisposition.nonLive)} '
      'idle=${count(TerminalPaneProcessDisposition.idleShell)} '
      'foreground=${count(TerminalPaneProcessDisposition.foregroundProcess)} '
      'unavailable=${count(TerminalPaneProcessDisposition.unavailable)} '
      'confirmation=$requiresConfirmation';

  @override
  bool operator ==(Object other) {
    if (other is! TerminalApplicationQuitSnapshot ||
        other.panes.length != panes.length) {
      return false;
    }
    for (var index = 0; index < panes.length; index++) {
      if (other.panes[index] != panes[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(panes);
}

/// Token proving the exact all-pane state shown at the confirmation boundary.
final class TerminalApplicationQuitConfirmation {
  TerminalApplicationQuitConfirmation({
    required this.operationId,
    required this.snapshot,
  }) {
    if (operationId <= 0) {
      throw ArgumentError.value(operationId, 'operationId', 'must be positive');
    }
    if (!snapshot.requiresConfirmation) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'must contain at least one risky pane',
      );
    }
  }

  final int operationId;
  final TerminalApplicationQuitSnapshot snapshot;

  @override
  bool operator ==(Object other) =>
      other is TerminalApplicationQuitConfirmation &&
      other.operationId == operationId &&
      other.snapshot == snapshot;

  @override
  int get hashCode => Object.hash(operationId, snapshot);
}

final class TerminalApplicationQuitResult {
  const TerminalApplicationQuitResult._({
    required this.disposition,
    this.confirmation,
    this.snapshot,
    this.shutdown,
    this.nativeOperationId,
    this.preShutdownFailed = false,
  });

  factory TerminalApplicationQuitResult.confirmationRequired(
    TerminalApplicationQuitConfirmation confirmation, {
    int? nativeOperationId,
  }) => TerminalApplicationQuitResult._(
    disposition: TerminalApplicationQuitDisposition.confirmationRequired,
    confirmation: confirmation,
    snapshot: confirmation.snapshot,
    nativeOperationId: nativeOperationId,
  );

  factory TerminalApplicationQuitResult.terminated({
    required TerminalApplicationQuitSnapshot snapshot,
    required TerminalPaneOwnerShutdownResult shutdown,
    required bool preShutdownFailed,
    int? nativeOperationId,
  }) => TerminalApplicationQuitResult._(
    disposition: shutdown.isClean && !preShutdownFailed
        ? TerminalApplicationQuitDisposition.terminated
        : TerminalApplicationQuitDisposition.terminatedWithCleanupFailure,
    snapshot: snapshot,
    shutdown: shutdown,
    nativeOperationId: nativeOperationId,
    preShutdownFailed: preShutdownFailed,
  );

  const TerminalApplicationQuitResult.stale()
    : this._(disposition: TerminalApplicationQuitDisposition.stale);

  const TerminalApplicationQuitResult.busy()
    : this._(disposition: TerminalApplicationQuitDisposition.busy);

  final TerminalApplicationQuitDisposition disposition;
  final TerminalApplicationQuitConfirmation? confirmation;
  final TerminalApplicationQuitSnapshot? snapshot;
  final TerminalPaneOwnerShutdownResult? shutdown;
  final int? nativeOperationId;
  final bool preShutdownFailed;

  String machineLine() =>
      'TERMINAL_APPLICATION_QUIT disposition=${disposition.name} '
      'operation_id=${confirmation?.operationId ?? 0} '
      'native_operation_id=${nativeOperationId ?? 0} '
      'panes=${snapshot?.panes.length ?? 0} '
      'cleanup=${shutdown?.disposition.name ?? 'pending'} '
      'pre_shutdown_failed=$preShutdownFailed';
}

/// Serializes aggregate Quit admission, teardown, and native request replies.
final class TerminalApplicationQuitCoordinator {
  TerminalApplicationQuitCoordinator({
    required TerminalApplicationState state,
    TerminalPaneCloseCoordinator? paneCloseCoordinator,
    TerminalApplicationTerminationReply? replyToTerminationRequest,
    Future<void> Function()? onPreShutdown,
    Future<void> Function()? terminateProgrammatically,
  }) : _state = state,
       _paneCloseCoordinator = paneCloseCoordinator,
       _replyToTerminationRequest = replyToTerminationRequest,
       _onPreShutdown = onPreShutdown,
       _terminateProgrammatically = terminateProgrammatically;

  static const int maximumOperationId = 0x7fffffffffffffff;
  static const int maximumRememberedNativeReplies = 64;

  final TerminalApplicationState _state;
  final TerminalPaneCloseCoordinator? _paneCloseCoordinator;
  final TerminalApplicationTerminationReply? _replyToTerminationRequest;
  final Future<void> Function()? _onPreShutdown;
  final Future<void> Function()? _terminateProgrammatically;
  final LinkedHashMap<int, bool> _nativeReplies = LinkedHashMap<int, bool>();

  var _nextOperationId = 0;
  TerminalApplicationQuitConfirmation? _pendingConfirmation;
  ApplicationTerminateRequestedEvent? _pendingNativeRequest;
  ApplicationTerminateRequestedEvent? _activeNativeRequest;
  Future<TerminalApplicationQuitResult>? _completionFuture;
  TerminalApplicationQuitResult? _completedResult;

  TerminalApplicationQuitConfirmation? get pendingConfirmation =>
      _pendingConfirmation;
  bool get quitInProgress =>
      _pendingConfirmation != null || _completionFuture != null;
  TerminalApplicationQuitResult? get completedResult => _completedResult;

  /// Repeating menu Quit is an explicit confirmation of the current snapshot.
  Future<TerminalApplicationQuitResult> requestQuit() async {
    final TerminalApplicationQuitResult? completed = _completedResult;
    if (completed != null) return completed;
    final Future<TerminalApplicationQuitResult>? active = _completionFuture;
    if (active != null) return active;
    final TerminalApplicationQuitConfirmation? pending = _pendingConfirmation;
    if (pending != null) return confirmQuit(pending);
    return _begin(nativeRequest: null);
  }

  Future<TerminalApplicationQuitResult> handleTerminationRequest(
    ApplicationTerminateRequestedEvent request,
  ) async {
    if (request.operationId <= 0) {
      throw ArgumentError.value(
        request.operationId,
        'request.operationId',
        'must be positive',
      );
    }
    if (_nativeReplies.containsKey(request.operationId)) {
      return const TerminalApplicationQuitResult.stale();
    }

    final TerminalApplicationQuitResult? completed = _completedResult;
    if (completed != null) {
      _replyNative(request, allow: true);
      return completed;
    }

    final Future<TerminalApplicationQuitResult>? active = _completionFuture;
    if (active != null) {
      if (_activeNativeRequest?.operationId == request.operationId) {
        return active;
      }
      _replyNative(request, allow: false);
      return const TerminalApplicationQuitResult.busy();
    }

    final TerminalApplicationQuitConfirmation? pending = _pendingConfirmation;
    if (pending != null) {
      final ApplicationTerminateRequestedEvent? pendingNative =
          _pendingNativeRequest;
      if (pendingNative != null) {
        if (pendingNative.operationId == request.operationId) {
          return TerminalApplicationQuitResult.confirmationRequired(
            pending,
            nativeOperationId: request.operationId,
          );
        }
        _replyNative(request, allow: false);
        return const TerminalApplicationQuitResult.busy();
      }
      if (_capture() == pending.snapshot) {
        _pendingNativeRequest = request;
        return TerminalApplicationQuitResult.confirmationRequired(
          pending,
          nativeOperationId: request.operationId,
        );
      }
      _retirePending(allowNative: false);
    }
    return _begin(nativeRequest: request);
  }

  Future<TerminalApplicationQuitResult> confirmQuit(
    TerminalApplicationQuitConfirmation confirmation,
  ) async {
    if (_completedResult != null) {
      return const TerminalApplicationQuitResult.stale();
    }
    if (_completionFuture != null) {
      return const TerminalApplicationQuitResult.busy();
    }
    if (_pendingConfirmation != confirmation) {
      return const TerminalApplicationQuitResult.stale();
    }
    if (_capture() != confirmation.snapshot) {
      _retirePending(allowNative: false);
      return const TerminalApplicationQuitResult.stale();
    }
    final ApplicationTerminateRequestedEvent? native = _pendingNativeRequest;
    _pendingConfirmation = null;
    _pendingNativeRequest = null;
    return _accept(confirmation.snapshot, nativeRequest: native);
  }

  bool cancelQuit(TerminalApplicationQuitConfirmation confirmation) {
    if (_pendingConfirmation != confirmation) return false;
    _retirePending(allowNative: false);
    return true;
  }

  Future<TerminalApplicationQuitResult> _begin({
    required ApplicationTerminateRequestedEvent? nativeRequest,
  }) async {
    if (!_reservePaneMutation()) {
      if (nativeRequest != null) {
        _replyNative(nativeRequest, allow: false);
      }
      return const TerminalApplicationQuitResult.busy();
    }
    late final TerminalApplicationQuitSnapshot snapshot;
    try {
      snapshot = _capture();
      if (snapshot.requiresConfirmation) {
        if (_nextOperationId >= maximumOperationId) {
          throw StateError(
            'terminal application quit operation ID is exhausted',
          );
        }
        final TerminalApplicationQuitConfirmation confirmation =
            TerminalApplicationQuitConfirmation(
              operationId: ++_nextOperationId,
              snapshot: snapshot,
            );
        _pendingConfirmation = confirmation;
        _pendingNativeRequest = nativeRequest;
        return TerminalApplicationQuitResult.confirmationRequired(
          confirmation,
          nativeOperationId: nativeRequest?.operationId,
        );
      }
    } on Object {
      _releasePaneMutation();
      rethrow;
    }
    return _accept(snapshot, nativeRequest: nativeRequest);
  }

  TerminalApplicationQuitSnapshot _capture() {
    final List<TerminalApplicationQuitPaneSnapshot> panes =
        <TerminalApplicationQuitPaneSnapshot>[];
    for (final TerminalWindowState window in _state.windows) {
      for (final TerminalTabState tab in window.tabs) {
        for (final PaneId paneId in tab.paneIds) {
          final TerminalPane? pane = _state.paneForId(paneId);
          if (pane == null) {
            throw StateError('quit snapshot lost pane $paneId');
          }
          panes.add(TerminalApplicationQuitPaneSnapshot.fromPane(pane));
        }
      }
    }
    if (panes.length != _state.paneCount) {
      throw StateError('quit snapshot and application pane counts differ');
    }
    return TerminalApplicationQuitSnapshot(panes);
  }

  Future<TerminalApplicationQuitResult> _accept(
    TerminalApplicationQuitSnapshot snapshot, {
    required ApplicationTerminateRequestedEvent? nativeRequest,
  }) {
    final Future<TerminalApplicationQuitResult>? active = _completionFuture;
    if (active != null) return active;
    _activeNativeRequest = nativeRequest;
    final Future<TerminalApplicationQuitResult> completion = _completeAccepted(
      snapshot,
      nativeRequest: nativeRequest,
    );
    _completionFuture = completion;
    return completion;
  }

  Future<TerminalApplicationQuitResult> _completeAccepted(
    TerminalApplicationQuitSnapshot snapshot, {
    required ApplicationTerminateRequestedEvent? nativeRequest,
  }) async {
    var preShutdownFailed = false;
    try {
      try {
        await _onPreShutdown?.call();
      } on Object {
        preShutdownFailed = true;
      }
      final TerminalPaneOwnerShutdownResult shutdown = await _state.shutdown();
      final TerminalApplicationQuitResult result =
          TerminalApplicationQuitResult.terminated(
            snapshot: snapshot,
            shutdown: shutdown,
            preShutdownFailed: preShutdownFailed,
            nativeOperationId: nativeRequest?.operationId,
          );
      _completedResult = result;
      if (nativeRequest != null) {
        _replyNative(nativeRequest, allow: true);
      } else {
        await _terminateProgrammatically?.call();
      }
      return result;
    } finally {
      _activeNativeRequest = null;
    }
  }

  void _retirePending({required bool allowNative}) {
    final ApplicationTerminateRequestedEvent? native = _pendingNativeRequest;
    _pendingConfirmation = null;
    _pendingNativeRequest = null;
    if (native != null) _replyNative(native, allow: allowNative);
    _releasePaneMutation();
  }

  bool _reservePaneMutation() =>
      _paneCloseCoordinator?.beginApplicationQuit() ?? true;

  void _releasePaneMutation() {
    _paneCloseCoordinator?.endApplicationQuit();
  }

  bool _replyNative(
    ApplicationTerminateRequestedEvent request, {
    required bool allow,
  }) {
    if (_nativeReplies.containsKey(request.operationId)) return false;
    final TerminalApplicationTerminationReply? reply =
        _replyToTerminationRequest;
    if (reply == null) {
      throw StateError('native termination reply callback is unavailable');
    }
    _nativeReplies[request.operationId] = allow;
    while (_nativeReplies.length > maximumRememberedNativeReplies) {
      _nativeReplies.remove(_nativeReplies.keys.first);
    }
    reply(request, allow: allow);
    return true;
  }
}
