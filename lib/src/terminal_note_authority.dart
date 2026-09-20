import 'dart:async';
import 'dart:collection';

import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_note_store_isolate.dart';
import 'terminal_note_store_worker.dart';
import 'terminal_pane.dart';

abstract final class TerminalNoteAuthorityLimits {
  static const int maximumPendingIntents = 32;
  static const int maximumPendingBodyBytes = 128 * 1024;
  static const int maximumIntentSources = 64;
  static const int maximumSequence = 0x7fffffffffffffff;
}

enum TerminalNoteAuthorityCapability {
  starting,
  ready,
  recoveryRequired,
  upgradeRequired,
  unavailable,
  stopping,
  stopped,
}

enum TerminalNoteAuthorityFailure {
  invalidStartup,
  reconciliationRejected,
  recoveryRequired,
  upgradeRequired,
  storeUnavailable,
  commitRejected,
}

/// One content-free, process-local authority ingress sequence.
final class TerminalNoteAuthoritySequence {
  const TerminalNoteAuthoritySequence._(this.authorityGeneration, this.value);

  final int authorityGeneration;
  final int value;

  @override
  String toString() => 'TerminalNoteAuthoritySequence(<redacted>)';
}

/// Generation-bound duplicate identity for a semantic user intent.
final class TerminalNoteAuthorityIntentToken {
  TerminalNoteAuthorityIntentToken({
    required this.authorityGeneration,
    required this.sourceGeneration,
    required this.eventSequence,
  }) {
    if (!_isPositiveSequence(authorityGeneration) ||
        !_isPositiveSequence(sourceGeneration) ||
        !_isPositiveSequence(eventSequence)) {
      throw ArgumentError('Note authority intent token is invalid');
    }
  }

  final int authorityGeneration;
  final int sourceGeneration;
  final int eventSequence;

  @override
  String toString() => 'TerminalNoteAuthorityIntentToken(<redacted>)';
}

abstract interface class TerminalNoteAuthorityStorePort {
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  });

  Future<TerminalNoteStoreResult> stop();
}

/// Adapter from the CM-03 isolate client to the application authority port.
final class TerminalNoteStoreWorkerAuthorityPort
    implements TerminalNoteAuthorityStorePort {
  const TerminalNoteStoreWorkerAuthorityPort(this.client);

  final TerminalNoteStoreWorkerClient client;

  @override
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) => client.commitCandidate(candidate, deletions: deletions);

  @override
  Future<TerminalNoteStoreResult> stop() => client.stop();
}

enum TerminalNoteAuthorityPublicationKind { startup, durable, runtime }

/// Content-free notification emitted only after an authority state is applied.
final class TerminalNoteAuthorityPublication {
  const TerminalNoteAuthorityPublication({
    required this.kind,
    required this.storeRevision,
    required this.noteCount,
    required this.activeCount,
    required this.dueCount,
    required this.detachedCount,
  });

  final TerminalNoteAuthorityPublicationKind kind;
  final BigInt storeRevision;
  final int noteCount;
  final int activeCount;
  final int dueCount;
  final int detachedCount;

  @override
  String toString() =>
      'TerminalNoteAuthorityPublication('
      '${kind.name}, notes=$noteCount, active=$activeCount, '
      'due=$dueCount, detached=$detachedCount)';
}

typedef TerminalNoteAuthorityPublicationObserver = void Function(
  TerminalNoteAuthorityPublication publication,
);

final class TerminalNoteAuthorityMutationPlan {
  TerminalNoteAuthorityMutationPlan({
    required this.mutation,
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) : deletions = List<TerminalNoteDeletionTombstone>.unmodifiable(deletions);

  final TerminalNoteMutationResult mutation;
  final List<TerminalNoteDeletionTombstone> deletions;

  @override
  String toString() =>
      'TerminalNoteAuthorityMutationPlan('
      '${mutation.disposition.name}, deletions=${deletions.length})';
}

typedef TerminalNoteAuthorityTransition =
    TerminalNoteAuthorityMutationPlan Function(TerminalNoteSnapshot snapshot);

enum TerminalNoteAuthorityMutationDisposition {
  committed,
  runtimeApplied,
  noChange,
  rejected,
  busy,
  duplicate,
  stale,
  unavailable,
  failed,
}

/// Content-free result returned to one mutation producer.
final class TerminalNoteAuthorityMutationResult {
  const TerminalNoteAuthorityMutationResult({
    required this.disposition,
    required this.storeRevision,
    this.mutationFailure,
    this.storeFailure,
  });

  final TerminalNoteAuthorityMutationDisposition disposition;
  final BigInt storeRevision;
  final TerminalNoteMutationFailure? mutationFailure;
  final TerminalNoteStoreFailure? storeFailure;

  bool get isAccepted => switch (disposition) {
    TerminalNoteAuthorityMutationDisposition.committed ||
    TerminalNoteAuthorityMutationDisposition.runtimeApplied ||
    TerminalNoteAuthorityMutationDisposition.noChange => true,
    _ => false,
  };

  @override
  String toString() =>
      'TerminalNoteAuthorityMutationResult(${disposition.name})';
}

/// Sole application-root owner for durable Note state and mutation ordering.
final class TerminalNoteAuthority {
  TerminalNoteAuthority._({
    required this.authorityGeneration,
    required TerminalNoteAuthorityStorePort? store,
    required TerminalNoteStoreDocument document,
    required TerminalNoteContextBindings bindings,
    required TerminalNoteAuthorityCapability capability,
    required TerminalNoteAuthorityFailure? failure,
    required TerminalNoteStoreFailure? storeFailure,
    required TerminalNoteAuthorityPublicationObserver? onPublished,
  }) : _store = store,
       _document = document,
       _bindings = bindings,
       _capability = capability,
       _failure = failure,
       _storeFailure = storeFailure,
       _onPublished = onPublished;

  static Future<TerminalNoteAuthority> startWorker({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
    required bool ensureQuickTerminalContext,
    required int updatedAtUtcMicros,
    TerminalNoteContextIdGenerator? idGenerator,
    TerminalNoteAuthorityPublicationObserver? onPublished,
    Duration loadTimeout = TerminalNoteStoreWorkerLimits.loadTimeout,
    Duration stopTimeout = TerminalNoteStoreWorkerLimits.stopTimeout,
    TerminalNoteStoreWorkerEntrypoint entrypoint =
        terminalNoteStoreWorkerEntrypoint,
  }) async {
    final TerminalNoteStoreWorkerStartup startup =
        await TerminalNoteStoreWorkerClient.start(
          location: location,
          authorityGeneration: authorityGeneration,
          loadTimeout: loadTimeout,
          stopTimeout: stopTimeout,
          entrypoint: entrypoint,
        );
    return start(
      authorityGeneration: authorityGeneration,
      store: startup.client == null
          ? null
          : TerminalNoteStoreWorkerAuthorityPort(startup.client!),
      loadResult: startup.loadResult,
      restoration: restoration,
      paneIdsInTraversalOrder: paneIdsInTraversalOrder,
      ensureQuickTerminalContext: ensureQuickTerminalContext,
      updatedAtUtcMicros: updatedAtUtcMicros,
      idGenerator: idGenerator,
      onPublished: onPublished,
    );
  }

  static Future<TerminalNoteAuthority> start({
    required int authorityGeneration,
    required TerminalNoteAuthorityStorePort? store,
    required TerminalNoteStoreResult loadResult,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
    required bool ensureQuickTerminalContext,
    required int updatedAtUtcMicros,
    TerminalNoteContextIdGenerator? idGenerator,
    TerminalNoteAuthorityPublicationObserver? onPublished,
  }) async {
    if (!_isPositiveSequence(authorityGeneration)) {
      throw ArgumentError.value(
        authorityGeneration,
        'authorityGeneration',
        'must be a positive bounded sequence',
      );
    }
    final TerminalNoteStoreDocument loaded =
        loadResult.document ??
        TerminalNoteStoreDocument(snapshot: TerminalNoteSnapshot.empty());
    final TerminalNoteAuthority authority = TerminalNoteAuthority._(
      authorityGeneration: authorityGeneration,
      store: store,
      document: loaded,
      bindings: TerminalNoteContextBindings(
        standardPaneContexts: const <PaneId, TerminalNoteContextId>{},
        quickTerminalContextId: null,
      ),
      capability: TerminalNoteAuthorityCapability.starting,
      failure: null,
      storeFailure: loadResult.failure,
      onPublished: onPublished,
    );
    if (loadResult.disposition ==
            TerminalNoteStoreDisposition.recoveryPreview ||
        loadResult.disposition ==
            TerminalNoteStoreDisposition.recoveryRequired) {
      authority._capability = TerminalNoteAuthorityCapability.recoveryRequired;
      authority._failure = TerminalNoteAuthorityFailure.recoveryRequired;
      return authority;
    }
    if (loadResult.disposition ==
        TerminalNoteStoreDisposition.upgradeRequired) {
      authority._capability = TerminalNoteAuthorityCapability.upgradeRequired;
      authority._failure = TerminalNoteAuthorityFailure.upgradeRequired;
      return authority;
    }
    final bool loadAccepted =
        loadResult.disposition == TerminalNoteStoreDisposition.loaded ||
        loadResult.disposition == TerminalNoteStoreDisposition.empty;
    if (!loadAccepted ||
        loadResult.document == null ||
        store == null ||
        loadResult.storeRevision != loaded.snapshot.storeRevision) {
      authority._markUnavailable(
        TerminalNoteAuthorityFailure.invalidStartup,
        loadResult.failure,
      );
      return authority;
    }
    TerminalNoteContextReconciliationResult reconciled;
    try {
      reconciled =
          TerminalNoteContextReconciler(
            idGenerator ?? TerminalNoteContextIdGenerator.secure(),
          ).reconcile(
            stored: loaded,
            restoration: restoration,
            paneIdsInTraversalOrder: paneIdsInTraversalOrder,
            ensureQuickTerminalContext: ensureQuickTerminalContext,
            updatedAtUtcMicros: updatedAtUtcMicros,
          );
    } on Object {
      authority._markUnavailable(
        TerminalNoteAuthorityFailure.reconciliationRejected,
        null,
      );
      return authority;
    }
    if (reconciled.requiresCommit) {
      final TerminalNoteStoreResult committed;
      try {
        committed = await store.commitCandidate(reconciled.document);
      } on Object {
        authority._markUnavailable(
          TerminalNoteAuthorityFailure.commitRejected,
          TerminalNoteStoreFailure.unknown,
        );
        return authority;
      }
      if (!_isMatchingCommit(committed, reconciled.document)) {
        authority._markUnavailable(
          TerminalNoteAuthorityFailure.commitRejected,
          committed.failure,
        );
        return authority;
      }
    }
    authority._document = reconciled.document;
    authority._bindings = reconciled.bindings;
    authority._capability = TerminalNoteAuthorityCapability.ready;
    authority._failure = null;
    authority._storeFailure = null;
    authority._publish(TerminalNoteAuthorityPublicationKind.startup);
    return authority;
  }

  final int authorityGeneration;
  final TerminalNoteAuthorityStorePort? _store;
  final TerminalNoteAuthorityPublicationObserver? _onPublished;
  final Queue<_PendingAuthorityMutation> _pending =
      Queue<_PendingAuthorityMutation>();
  final Map<int, int> _sourceEventHighWatermarks = <int, int>{};
  TerminalNoteStoreDocument _document;
  TerminalNoteContextBindings _bindings;
  TerminalNoteAuthorityCapability _capability;
  TerminalNoteAuthorityFailure? _failure;
  TerminalNoteStoreFailure? _storeFailure;
  _PendingAuthorityMutation? _inFlight;
  Completer<void>? _idleCompleter;
  Future<TerminalNoteStoreResult>? _stopFuture;
  TerminalNoteStoreResult? _stopResult;
  var _pendingBodyBytes = 0;
  var _nextAuthoritySequence = 1;
  var _lastIngressSequence = 0;

  TerminalNoteAuthorityCapability get capability => _capability;
  TerminalNoteAuthorityFailure? get failure => _failure;
  TerminalNoteStoreFailure? get storeFailure => _storeFailure;
  TerminalNoteStoreDocument get document => _document;
  TerminalNoteContextBindings get bindings => _bindings;
  int get pendingIntentCount => _pending.length;
  int get outstandingIntentCount =>
      _pending.length + (_inFlight == null ? 0 : 1);
  int get pendingBodyBytes => _pendingBodyBytes;
  bool get hasInFlightMutation => _inFlight != null;

  TerminalNoteAuthoritySequence nextSequence() {
    if (_nextAuthoritySequence > TerminalNoteAuthorityLimits.maximumSequence) {
      throw StateError('Terminal Note authority sequence exhausted');
    }
    return TerminalNoteAuthoritySequence._(
      authorityGeneration,
      _nextAuthoritySequence++,
    );
  }

  Future<TerminalNoteAuthorityMutationResult> submitMutation({
    required TerminalNoteAuthoritySequence sequence,
    required TerminalNoteAuthorityIntentToken token,
    required int bodyUtf8Bytes,
    required TerminalNoteAuthorityTransition transition,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _validateIngress(sequence, token, bodyUtf8Bytes);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    _lastIngressSequence = sequence.value;
    final int? previousEvent =
        _sourceEventHighWatermarks[token.sourceGeneration];
    if (previousEvent != null && token.eventSequence <= previousEvent) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(
          token.eventSequence == previousEvent
              ? TerminalNoteAuthorityMutationDisposition.duplicate
              : TerminalNoteAuthorityMutationDisposition.stale,
        ),
      );
    }
    if (previousEvent == null &&
        _sourceEventHighWatermarks.length >=
            TerminalNoteAuthorityLimits.maximumIntentSources) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    _sourceEventHighWatermarks[token.sourceGeneration] = token.eventSequence;
    if (bodyUtf8Bytes < 0 ||
        bodyUtf8Bytes > TerminalNoteAuthorityLimits.maximumPendingBodyBytes) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(
          TerminalNoteAuthorityMutationDisposition.rejected,
          mutationFailure: TerminalNoteMutationFailure.invalidInput,
        ),
      );
    }
    if ((_inFlight != null &&
            _pending.length >=
                TerminalNoteAuthorityLimits.maximumPendingIntents) ||
        _pendingBodyBytes + bodyUtf8Bytes >
            TerminalNoteAuthorityLimits.maximumPendingBodyBytes) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    final _PendingAuthorityMutation pending = _PendingAuthorityMutation(
      transition: transition,
      bodyUtf8Bytes: bodyUtf8Bytes,
    );
    _pending.add(pending);
    _pendingBodyBytes += bodyUtf8Bytes;
    _idleCompleter ??= Completer<void>();
    _pump();
    return pending.completer.future;
  }

  Future<void> whenIdle() => _idleCompleter?.future ?? Future<void>.value();

  Future<TerminalNoteStoreResult> stop() => _stopFuture ??= _runStop();

  void releaseIntentSource(int sourceGeneration) {
    _sourceEventHighWatermarks.remove(sourceGeneration);
  }

  TerminalNoteAuthorityMutationResult? _validateIngress(
    TerminalNoteAuthoritySequence sequence,
    TerminalNoteAuthorityIntentToken token,
    int bodyUtf8Bytes,
  ) {
    if (_capability != TerminalNoteAuthorityCapability.ready) {
      return _result(TerminalNoteAuthorityMutationDisposition.unavailable);
    }
    if (sequence.authorityGeneration != authorityGeneration ||
        token.authorityGeneration != authorityGeneration ||
        sequence.value <= _lastIngressSequence ||
        sequence.value >= _nextAuthoritySequence) {
      return _result(TerminalNoteAuthorityMutationDisposition.stale);
    }
    return null;
  }

  void _pump() {
    if (_inFlight != null || _pending.isEmpty) return;
    final _PendingAuthorityMutation pending = _pending.removeFirst();
    _inFlight = pending;
    unawaited(
      _runMutation(pending).whenComplete(() {
        _pendingBodyBytes -= pending.bodyUtf8Bytes;
        _inFlight = null;
        if (_capability == TerminalNoteAuthorityCapability.ready) {
          _pump();
        } else {
          _failPending();
        }
        if (_inFlight == null && _pending.isEmpty) {
          final Completer<void>? idle = _idleCompleter;
          _idleCompleter = null;
          if (idle != null && !idle.isCompleted) idle.complete();
        }
      }),
    );
  }

  Future<void> _runMutation(_PendingAuthorityMutation pending) async {
    TerminalNoteAuthorityMutationPlan plan;
    try {
      plan = pending.transition(_document.snapshot);
    } on Object {
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.rejected,
          mutationFailure: TerminalNoteMutationFailure.invalidInput,
        ),
      );
      return;
    }
    final TerminalNoteMutationResult mutation = plan.mutation;
    switch (mutation.disposition) {
      case TerminalNoteMutationDisposition.rejected:
        pending.complete(
          _result(
            TerminalNoteAuthorityMutationDisposition.rejected,
            mutationFailure: mutation.failure,
          ),
        );
        return;
      case TerminalNoteMutationDisposition.noChange:
        pending.complete(
          _result(TerminalNoteAuthorityMutationDisposition.noChange),
        );
        return;
      case TerminalNoteMutationDisposition.runtimeOnly:
        _document = TerminalNoteStoreDocument(
          snapshot: mutation.snapshot,
          restorationBinding: _document.restorationBinding,
        );
        _publish(TerminalNoteAuthorityPublicationKind.runtime);
        pending.complete(
          _result(TerminalNoteAuthorityMutationDisposition.runtimeApplied),
        );
        return;
      case TerminalNoteMutationDisposition.accepted:
        break;
    }
    final TerminalNoteStoreDocument candidate = TerminalNoteStoreDocument(
      snapshot: mutation.snapshot,
      restorationBinding: _document.restorationBinding,
    );
    final TerminalNoteAuthorityStorePort? store = _store;
    if (store == null) {
      _markUnavailable(
        TerminalNoteAuthorityFailure.storeUnavailable,
        TerminalNoteStoreFailure.invalidState,
      );
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.unavailable,
          storeFailure: TerminalNoteStoreFailure.invalidState,
        ),
      );
      return;
    }
    TerminalNoteStoreResult committed;
    try {
      committed = await store.commitCandidate(
        candidate,
        deletions: plan.deletions,
      );
    } on Object {
      committed = _storeFailureResult(TerminalNoteStoreFailure.unknown);
    }
    if (!_isMatchingCommit(committed, candidate)) {
      _markUnavailable(
        TerminalNoteAuthorityFailure.commitRejected,
        committed.failure,
      );
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.failed,
          storeFailure: committed.failure,
        ),
      );
      return;
    }
    _document = candidate;
    _publish(TerminalNoteAuthorityPublicationKind.durable);
    pending.complete(
      _result(TerminalNoteAuthorityMutationDisposition.committed),
    );
  }

  Future<TerminalNoteStoreResult> _runStop() async {
    if (_capability == TerminalNoteAuthorityCapability.stopped) {
      return _stopResult ??= _stoppedStoreResult();
    }
    _capability = TerminalNoteAuthorityCapability.stopping;
    _failPending();
    _completeIdleIfNeeded();
    await whenIdle();
    final TerminalNoteAuthorityStorePort? store = _store;
    late TerminalNoteStoreResult result;
    try {
      result = store == null ? _stoppedStoreResult() : await store.stop();
    } on Object {
      result = _storeFailureResult(TerminalNoteStoreFailure.unknown);
    }
    _capability = TerminalNoteAuthorityCapability.stopped;
    _stopResult = result;
    return result;
  }

  void _failPending() {
    while (_pending.isNotEmpty) {
      final _PendingAuthorityMutation pending = _pending.removeFirst();
      _pendingBodyBytes -= pending.bodyUtf8Bytes;
      pending.complete(
        _result(TerminalNoteAuthorityMutationDisposition.unavailable),
      );
    }
  }

  void _completeIdleIfNeeded() {
    if (_inFlight != null || _pending.isNotEmpty) return;
    final Completer<void>? idle = _idleCompleter;
    _idleCompleter = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }

  void _markUnavailable(
    TerminalNoteAuthorityFailure failure,
    TerminalNoteStoreFailure? storeFailure,
  ) {
    _capability = TerminalNoteAuthorityCapability.unavailable;
    _failure = failure;
    _storeFailure = storeFailure;
  }

  TerminalNoteAuthorityMutationResult _result(
    TerminalNoteAuthorityMutationDisposition disposition, {
    TerminalNoteMutationFailure? mutationFailure,
    TerminalNoteStoreFailure? storeFailure,
  }) => TerminalNoteAuthorityMutationResult(
    disposition: disposition,
    storeRevision: _document.snapshot.storeRevision,
    mutationFailure: mutationFailure,
    storeFailure: storeFailure,
  );

  void _publish(TerminalNoteAuthorityPublicationKind kind) {
    final TerminalNoteAuthorityPublicationObserver? observer = _onPublished;
    if (observer == null) return;
    final TerminalNoteSnapshot snapshot = _document.snapshot;
    try {
      observer(
        TerminalNoteAuthorityPublication(
          kind: kind,
          storeRevision: snapshot.storeRevision,
          noteCount: snapshot.notes.length,
          activeCount: snapshot.notes.values
              .where((NoteRecord note) => note.status == NoteStatus.active)
              .length,
          dueCount: snapshot.deliveries.length,
          detachedCount: snapshot.notes.values
              .where((NoteRecord note) => note.attachment.isDetached)
              .length,
        ),
      );
    } on Object {
      // Publication observers cannot invalidate committed authority state.
    }
  }

  static bool _isMatchingCommit(
    TerminalNoteStoreResult result,
    TerminalNoteStoreDocument candidate,
  ) =>
      result.disposition == TerminalNoteStoreDisposition.committed &&
      result.failure == null &&
      result.storeRevision == candidate.snapshot.storeRevision;
}

final class _PendingAuthorityMutation {
  _PendingAuthorityMutation({
    required this.transition,
    required this.bodyUtf8Bytes,
  });

  final TerminalNoteAuthorityTransition transition;
  final int bodyUtf8Bytes;
  final Completer<TerminalNoteAuthorityMutationResult> completer =
      Completer<TerminalNoteAuthorityMutationResult>();

  void complete(TerminalNoteAuthorityMutationResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}

bool _isPositiveSequence(int value) =>
    value > 0 && value <= TerminalNoteAuthorityLimits.maximumSequence;

TerminalNoteStoreResult _storeFailureResult(TerminalNoteStoreFailure failure) =>
    TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.unavailable,
      failure: failure,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );

TerminalNoteStoreResult _stoppedStoreResult() => TerminalNoteStoreResult(
  disposition: TerminalNoteStoreDisposition.stopped,
  failure: null,
  storeRevision: BigInt.zero,
  metrics: TerminalNoteStoreMetrics.zero,
);
