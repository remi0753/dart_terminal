import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_projection.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_note_store_isolate.dart';
import 'terminal_note_store_worker.dart';
import 'terminal_pane.dart';

abstract final class TerminalNoteAuthorityLimits {
  static const int maximumPendingIntents = 32;
  static const int maximumPendingBodyBytes = 128 * 1024;
  static const int maximumIntentSources = 64;
  static const int maximumLiveContexts = 64;
  static const int maximumLiveSessions = 64;
  static const int maximumPromptEventsPerSession = 32;
  static const int maximumSequence = 0x7fffffffffffffff;
}

typedef TerminalNoteIdEntropySource = List<int> Function();

/// Issues opaque Note identities inside the sole durable authority.
final class TerminalNoteIdGenerator {
  factory TerminalNoteIdGenerator.secure() {
    final Random random = Random.secure();
    return TerminalNoteIdGenerator._(
      () => List<int>.generate(16, (_) => random.nextInt(256), growable: false),
    );
  }

  const TerminalNoteIdGenerator.fromEntropySource(
    TerminalNoteIdEntropySource source,
  ) : _source = source;

  const TerminalNoteIdGenerator.forTesting(TerminalNoteIdEntropySource source)
    : this.fromEntropySource(source);

  const TerminalNoteIdGenerator._(this._source);

  final TerminalNoteIdEntropySource _source;

  NoteId next({Iterable<NoteId> excluding = const <NoteId>[]}) {
    final Set<NoteId> reserved = excluding.toSet();
    for (var attempt = 0; attempt < 32; attempt++) {
      final List<int> bytes = _source();
      if (bytes.length != 16 ||
          bytes.any((int value) => value < 0 || value > 0xff)) {
        throw const TerminalNoteValidationException(
          TerminalNoteValidationFailure.invalidId,
        );
      }
      final StringBuffer encoded = StringBuffer();
      for (final int byte in bytes) {
        encoded.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      final NoteId candidate = NoteId.fromHex(encoded.toString());
      if (!reserved.contains(candidate)) return candidate;
    }
    throw const TerminalNoteValidationException(
      TerminalNoteValidationFailure.invalidId,
    );
  }
}

enum TerminalNoteAuthorityCapability {
  starting,
  ready,
  draining,
  recoveryRequired,
  upgradeRequired,
  unavailable,
  stopping,
  stopped,
}

enum TerminalNoteSurfaceDisposition {
  applied,
  rejected,
  duplicate,
  stale,
  unavailable,
}

final class TerminalNoteSurfaceResult {
  const TerminalNoteSurfaceResult({required this.disposition, this.projection});

  final TerminalNoteSurfaceDisposition disposition;
  final TerminalNoteSurfaceProjection? projection;

  @override
  String toString() => 'TerminalNoteSurfaceResult(${disposition.name})';
}

enum TerminalNoteSurfaceIntentKind {
  open,
  close,
  showCurrent,
  showDetached,
  previousPage,
  nextPage,
  selectCard,
  beginCreate,
  beginEdit,
  cancelEditor,
  save,
  saveAlwaysAvailable,
  saveOnReturn,
  armOnReturn,
  makeAlwaysAvailable,
  changeColor,
  moveEarlier,
  moveLater,
  resolve,
  reopen,
  delete,
  reattach,
  copy,
  export,
}

enum TerminalNoteApplicationSurfaceAction { newNote, toggleNotes }

/// Content-free semantic intent result for one authority-owned surface.
final class TerminalNoteSurfaceIntentResult {
  const TerminalNoteSurfaceIntentResult({
    required this.disposition,
    required this.storeRevision,
    this.projection,
    this.mutationFailure,
    this.storeFailure,
  });

  final TerminalNoteAuthorityMutationDisposition disposition;
  final BigInt storeRevision;
  final TerminalNoteSurfaceProjection? projection;
  final TerminalNoteMutationFailure? mutationFailure;
  final TerminalNoteStoreFailure? storeFailure;

  bool get isAccepted => switch (disposition) {
    TerminalNoteAuthorityMutationDisposition.committed ||
    TerminalNoteAuthorityMutationDisposition.runtimeApplied => true,
    _ => false,
  };

  @override
  String toString() => 'TerminalNoteSurfaceIntentResult(${disposition.name})';
}

enum TerminalNoteAuthorityShutdownDisposition {
  committed,
  drainTimedOut,
  preparationFailed,
  persistenceFailed,
  storeStopFailed,
}

final class TerminalNoteAuthorityShutdownResult {
  const TerminalNoteAuthorityShutdownResult({
    required this.disposition,
    required this.persistence,
    required this.storeDisposition,
    required this.surfaceDisposeCount,
  });

  final TerminalNoteAuthorityShutdownDisposition disposition;
  final TerminalNoteOrderedPersistenceResult? persistence;
  final TerminalNoteStoreDisposition storeDisposition;
  final int surfaceDisposeCount;

  bool get isSuccess =>
      disposition == TerminalNoteAuthorityShutdownDisposition.committed;

  @override
  String toString() =>
      'TerminalNoteAuthorityShutdownResult(${disposition.name}, '
      'surfaces=$surfaceDisposeCount)';
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

  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath destination,
  );

  Future<TerminalNoteStoreResult> stop();
}

/// One bounded store worker startup, independent of its transport.
final class TerminalNoteAuthorityStoreStartup {
  const TerminalNoteAuthorityStoreStartup({
    required this.store,
    required this.loadResult,
  });

  final TerminalNoteAuthorityStorePort? store;
  final TerminalNoteStoreResult loadResult;
}

/// Product injection boundary for isolate- or helper-process-backed stores.
abstract interface class TerminalNoteAuthorityStoreFactory {
  Future<TerminalNoteAuthorityStoreStartup> start({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
  });
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
  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath destination,
  ) => client.exportToApprovedPath(destination);

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

enum TerminalNoteLifecycleDisposition {
  accepted,
  coalesced,
  duplicate,
  overflowed,
  stale,
  busy,
  unavailable,
}

/// Immediate, content-free admission result for one lifecycle observation.
final class TerminalNoteLifecycleResult {
  const TerminalNoteLifecycleResult(
    this.disposition, {
    required this.pendingFocusEdgeCount,
    required this.pendingPromptEventCount,
  });

  final TerminalNoteLifecycleDisposition disposition;
  final int pendingFocusEdgeCount;
  final int pendingPromptEventCount;

  bool get isAccepted => switch (disposition) {
    TerminalNoteLifecycleDisposition.accepted ||
    TerminalNoteLifecycleDisposition.coalesced ||
    TerminalNoteLifecycleDisposition.overflowed => true,
    _ => false,
  };

  @override
  String toString() => 'TerminalNoteLifecycleResult(${disposition.name})';
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
    required TerminalNoteContextIdGenerator contextIdGenerator,
    required TerminalNoteIdGenerator noteIdGenerator,
  }) : _store = store,
       _document = document,
       _bindings = bindings,
       _capability = capability,
       _failure = failure,
       _storeFailure = storeFailure,
       _onPublished = onPublished,
       _contextIdGenerator = contextIdGenerator,
       _noteIdGenerator = noteIdGenerator {
    _debugLiveAuthorityCount++;
  }

  static int _debugLiveAuthorityCount = 0;

  static int get debugLiveAuthorityCount => _debugLiveAuthorityCount;

  static Future<TerminalNoteAuthority> startWorker({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
    required bool ensureQuickTerminalContext,
    required int updatedAtUtcMicros,
    TerminalNoteContextIdGenerator? idGenerator,
    TerminalNoteIdGenerator? noteIdGenerator,
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
      noteIdGenerator: noteIdGenerator,
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
    TerminalNoteIdGenerator? noteIdGenerator,
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
    final TerminalNoteContextIdGenerator contextIdGenerator =
        idGenerator ?? TerminalNoteContextIdGenerator.secure();
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
      contextIdGenerator: contextIdGenerator,
      noteIdGenerator: noteIdGenerator ?? TerminalNoteIdGenerator.secure(),
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
      reconciled = TerminalNoteContextReconciler(contextIdGenerator).reconcile(
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
    authority._initializeLiveBindings();
    authority._publish(TerminalNoteAuthorityPublicationKind.startup);
    return authority;
  }

  final int authorityGeneration;
  final TerminalNoteAuthorityStorePort? _store;
  final TerminalNoteAuthorityPublicationObserver? _onPublished;
  final TerminalNoteContextIdGenerator _contextIdGenerator;
  final TerminalNoteIdGenerator _noteIdGenerator;
  final Queue<_PendingAuthorityMutation> _pending =
      Queue<_PendingAuthorityMutation>();
  final Map<int, int> _sourceEventHighWatermarks = <int, int>{};
  final Map<PaneId, _LiveNotePane> _livePanes = <PaneId, _LiveNotePane>{};
  final Map<TerminalSessionId, _LivePromptSession> _liveSessions =
      <TerminalSessionId, _LivePromptSession>{};
  TerminalNoteStoreDocument _document;
  TerminalNoteContextBindings _bindings;
  TerminalNoteAuthorityCapability _capability;
  TerminalNoteAuthorityFailure? _failure;
  TerminalNoteStoreFailure? _storeFailure;
  _PendingAuthorityMutation? _inFlight;
  Completer<void>? _idleCompleter;
  Future<TerminalNoteStoreResult>? _stopFuture;
  TerminalNoteStoreResult? _stopResult;
  Future<TerminalNoteAuthorityShutdownResult>? _shutdownFuture;
  var _pendingUserIntentCount = 0;
  var _pendingBodyBytes = 0;
  var _nextAuthoritySequence = 1;
  var _lastIngressSequence = 0;
  var _nextCardToken = 1;
  var _nextSurfaceIntentSourceGeneration =
      TerminalNoteAuthorityLimits.maximumSequence;
  var _debugRetired = false;
  var _discardLateCommit = false;

  TerminalNoteAuthorityCapability get capability => _capability;
  TerminalNoteAuthorityFailure? get failure => _failure;
  TerminalNoteStoreFailure? get storeFailure => _storeFailure;
  TerminalNoteStoreDocument get document => _document;
  TerminalNoteContextBindings get bindings => _bindings;
  int get pendingIntentCount => _pendingUserIntentCount;
  int get outstandingIntentCount =>
      _pendingUserIntentCount +
      (_inFlight?.countsTowardUserIntentLimit ?? false ? 1 : 0);
  int get pendingBodyBytes => _pendingBodyBytes;
  bool get hasInFlightMutation => _inFlight != null;
  int get livePaneCount => _livePanes.length;
  int get liveSessionCount => _liveSessions.length;
  int get liveSurfaceCount => _livePanes.values
      .where((_LiveNotePane pane) => pane.surface != null)
      .length;
  int get pendingFocusEdgeCount => _livePanes.values.fold<int>(
    0,
    (int total, _LiveNotePane pane) => total + pane.focusEdges.length,
  );
  int get pendingPromptEventCount => _liveSessions.values.fold<int>(
    0,
    (int total, _LivePromptSession session) =>
        total + session.promptEvents.length,
  );

  TerminalNoteContextId? contextForPane(PaneId paneId) =>
      _livePanes[paneId]?.contextId;

  NoteTriggerRuntimeBinding? promptBindingForSession(
    TerminalSessionId sessionId,
  ) {
    final _LivePromptSession? session = _liveSessions[sessionId];
    return session?.runtimeBinding;
  }

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
    void Function()? onBeforePublication,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _admitUserIntent(sequence, token);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    return _enqueueUserMutation(
      bodyUtf8Bytes: bodyUtf8Bytes,
      transition: transition,
      onBeforePublication: onBeforePublication,
    );
  }

  Future<TerminalNoteAuthorityMutationResult> _enqueueUserMutation({
    required int bodyUtf8Bytes,
    required TerminalNoteAuthorityTransition transition,
    void Function()? onBeforePublication,
  }) {
    if (bodyUtf8Bytes < 0 ||
        bodyUtf8Bytes > TerminalNoteAuthorityLimits.maximumPendingBodyBytes) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(
          TerminalNoteAuthorityMutationDisposition.rejected,
          mutationFailure: TerminalNoteMutationFailure.invalidInput,
        ),
      );
    }
    if (_pendingUserIntentCount >=
            TerminalNoteAuthorityLimits.maximumPendingIntents ||
        _pendingBodyBytes + bodyUtf8Bytes >
            TerminalNoteAuthorityLimits.maximumPendingBodyBytes) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    final _PendingAuthorityMutation pending = _PendingAuthorityMutation(
      transition: transition,
      bodyUtf8Bytes: bodyUtf8Bytes,
      countsTowardUserIntentLimit: true,
      onBeforePublication: onBeforePublication,
    );
    _pendingUserIntentCount++;
    _pendingBodyBytes += bodyUtf8Bytes;
    _enqueue(pending);
    return pending.completer.future;
  }

  Future<TerminalNoteAuthorityMutationResult> _enqueueUserExport({
    required TerminalNoteApprovedExportPath destination,
    required BigInt expectedStoreRevision,
  }) {
    if (_pendingUserIntentCount >=
        TerminalNoteAuthorityLimits.maximumPendingIntents) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    final _PendingAuthorityMutation pending = _PendingAuthorityMutation.export(
      destination: destination,
      expectedStoreRevision: expectedStoreRevision,
    );
    _pendingUserIntentCount++;
    _enqueue(pending);
    return pending.completer.future;
  }

  /// Applies one generation-bound UI intent without exposing persistent IDs.
  ///
  /// Navigation state is volatile and authority-owned. Durable operations are
  /// serialized through the same commit queue as every other Note mutation.
  Future<TerminalNoteSurfaceIntentResult> submitSurfaceIntent({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int surfaceGeneration,
    required int projectionGeneration,
    required int eventGeneration,
    required int draftGeneration,
    required TerminalNoteCardToken? cardToken,
    required BigInt expectedStoreRevision,
    required TerminalNoteSurfaceIntentKind kind,
    int? updatedAtUtcMicros,
    String? body,
    NoteColorKey? color,
    TerminalNoteApprovedExportPath? exportDestination,
  }) {
    final TerminalNoteAuthorityMutationResult? sequenceFailure =
        _validateSequence(sequence);
    if (sequenceFailure != null) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentFailure(sequenceFailure),
      );
    }
    final _LiveNotePane? pane = _livePanes[paneId];
    final _LiveNoteSurface? surface = pane?.surface;
    if (pane == null ||
        pane.retired ||
        surface == null ||
        surface.retired ||
        surface.generation != surfaceGeneration) {
      _lastIngressSequence = sequence.value;
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentResult(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    if (!_isPositiveSequence(eventGeneration)) {
      _lastIngressSequence = sequence.value;
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentResult(
          TerminalNoteAuthorityMutationDisposition.rejected,
          surface: surface,
          mutationFailure: TerminalNoteMutationFailure.invalidInput,
        ),
      );
    }
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _admitUserIntent(
          sequence,
          TerminalNoteAuthorityIntentToken(
            authorityGeneration: authorityGeneration,
            sourceGeneration: surface.intentSourceGeneration,
            eventSequence: eventGeneration,
          ),
        );
    if (ingressFailure != null) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentFailure(ingressFailure, surface: surface),
      );
    }
    final TerminalNoteSurfaceProjection? projection = surface.latest;
    if (projection == null ||
        projection.projectionGeneration != projectionGeneration ||
        projection.storeRevision != expectedStoreRevision ||
        expectedStoreRevision != _document.snapshot.storeRevision ||
        projection.draftGeneration != draftGeneration) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentResult(
          TerminalNoteAuthorityMutationDisposition.stale,
          surface: surface,
          mutationFailure:
              expectedStoreRevision != _document.snapshot.storeRevision
              ? TerminalNoteMutationFailure.revisionConflict
              : null,
        ),
      );
    }
    if (!_validSurfaceIntentPayload(
      kind: kind,
      body: body,
      color: color,
      updatedAtUtcMicros: updatedAtUtcMicros,
      exportDestination: exportDestination,
    )) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentResult(
          TerminalNoteAuthorityMutationDisposition.rejected,
          surface: surface,
          mutationFailure: TerminalNoteMutationFailure.invalidInput,
        ),
      );
    }

    switch (kind) {
      case TerminalNoteSurfaceIntentKind.open:
        if (cardToken != null || draftGeneration != 0) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface.visibility = TerminalNoteSurfaceVisibility.expanded;
          }),
        );
      case TerminalNoteSurfaceIntentKind.close:
        if (cardToken != null ||
            draftGeneration != 0 ||
            surface.editorMode != TerminalNoteEditorMode.inactive) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface.visibility = TerminalNoteSurfaceVisibility.collapsed;
          }),
        );
      case TerminalNoteSurfaceIntentKind.copy:
        final NoteId? noteId = _projectedNoteId(surface, cardToken);
        final NoteRecord? note = noteId == null
            ? null
            : _document.snapshot.noteFor(noteId);
        if (note == null ||
            body != note.body.value ||
            draftGeneration != 0 ||
            surface.visibility != TerminalNoteSurfaceVisibility.expanded ||
            surface.editorMode != TerminalNoteEditorMode.inactive) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _surfaceIntentResult(
            TerminalNoteAuthorityMutationDisposition.runtimeApplied,
            surface: surface,
          ),
        );
      case TerminalNoteSurfaceIntentKind.export:
        if (cardToken != null ||
            draftGeneration != 0 ||
            surface.visibility != TerminalNoteSurfaceVisibility.expanded ||
            surface.editorMode != TerminalNoteEditorMode.inactive) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return _enqueueUserExport(
          destination: exportDestination!,
          expectedStoreRevision: expectedStoreRevision,
        ).then(
          (TerminalNoteAuthorityMutationResult result) =>
              _surfaceIntentFailure(result, surface: surface),
        );
      case TerminalNoteSurfaceIntentKind.showCurrent:
      case TerminalNoteSurfaceIntentKind.showDetached:
        final TerminalNoteCollectionSection section =
            kind == TerminalNoteSurfaceIntentKind.showCurrent
            ? TerminalNoteCollectionSection.current
            : TerminalNoteCollectionSection.detached;
        if (cardToken != null ||
            draftGeneration != 0 ||
            surface.visibility != TerminalNoteSurfaceVisibility.expanded ||
            surface.editorMode != TerminalNoteEditorMode.inactive ||
            surface.section == section) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface
              ..section = section
              ..pageStart = 0
              ..selectedNoteId = null;
          }),
        );
      case TerminalNoteSurfaceIntentKind.previousPage:
      case TerminalNoteSurfaceIntentKind.nextPage:
        final int totalCount = surface.latest?.totalCount ?? 0;
        final bool previous =
            kind == TerminalNoteSurfaceIntentKind.previousPage;
        final bool canMove = previous
            ? surface.pageStart > 0
            : surface.pageStart +
                      TerminalNoteProjectionLimits.maximumExpandedCards <
                  totalCount;
        if (cardToken != null ||
            draftGeneration != 0 ||
            surface.visibility != TerminalNoteSurfaceVisibility.expanded ||
            surface.section != TerminalNoteCollectionSection.detached ||
            surface.editorMode != TerminalNoteEditorMode.inactive ||
            !canMove) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface
              ..pageStart = previous
                  ? surface.pageStart -
                        TerminalNoteProjectionLimits.maximumExpandedCards
                  : surface.pageStart +
                        TerminalNoteProjectionLimits.maximumExpandedCards
              ..selectedNoteId = null;
          }),
        );
      case TerminalNoteSurfaceIntentKind.selectCard:
        final NoteId? noteId = _projectedNoteId(surface, cardToken);
        if (noteId == null ||
            draftGeneration != 0 ||
            surface.editorMode != TerminalNoteEditorMode.inactive) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface.selectedNoteId = noteId;
          }),
        );
      case TerminalNoteSurfaceIntentKind.beginCreate:
        if (cardToken != null ||
            draftGeneration != 0 ||
            surface.section != TerminalNoteCollectionSection.current ||
            surface.editorMode != TerminalNoteEditorMode.inactive ||
            surface.nextDraftGeneration >
                TerminalNoteProjectionLimits.maximumGeneration) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface
              ..visibility = TerminalNoteSurfaceVisibility.expanded
              ..selectedNoteId = null
              ..editorMode = TerminalNoteEditorMode.creating
              ..draftGeneration = surface.nextDraftGeneration++;
          }),
        );
      case TerminalNoteSurfaceIntentKind.beginEdit:
        final NoteId? noteId = _currentNoteId(surface, cardToken);
        if (noteId == null ||
            draftGeneration != 0 ||
            surface.editorMode != TerminalNoteEditorMode.inactive ||
            surface.nextDraftGeneration >
                TerminalNoteProjectionLimits.maximumGeneration) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface
              ..visibility = TerminalNoteSurfaceVisibility.expanded
              ..selectedNoteId = noteId
              ..editorMode = TerminalNoteEditorMode.editing
              ..draftGeneration = surface.nextDraftGeneration++;
          }),
        );
      case TerminalNoteSurfaceIntentKind.cancelEditor:
        if (!_matchesEditorIntent(surface, cardToken, draftGeneration)) {
          return Future<TerminalNoteSurfaceIntentResult>.value(
            _invalidSurfaceIntent(surface),
          );
        }
        return Future<TerminalNoteSurfaceIntentResult>.value(
          _applyRuntimeSurfaceIntent(pane, surface, () {
            surface
              ..editorMode = TerminalNoteEditorMode.inactive
              ..draftGeneration = 0;
          }),
        );
      case TerminalNoteSurfaceIntentKind.save:
      case TerminalNoteSurfaceIntentKind.saveAlwaysAvailable:
      case TerminalNoteSurfaceIntentKind.saveOnReturn:
      case TerminalNoteSurfaceIntentKind.armOnReturn:
      case TerminalNoteSurfaceIntentKind.makeAlwaysAvailable:
      case TerminalNoteSurfaceIntentKind.changeColor:
      case TerminalNoteSurfaceIntentKind.moveEarlier:
      case TerminalNoteSurfaceIntentKind.moveLater:
      case TerminalNoteSurfaceIntentKind.resolve:
      case TerminalNoteSurfaceIntentKind.reopen:
      case TerminalNoteSurfaceIntentKind.delete:
      case TerminalNoteSurfaceIntentKind.reattach:
        return _submitDurableSurfaceIntent(
          pane: pane,
          surface: surface,
          kind: kind,
          cardToken: cardToken,
          draftGeneration: draftGeneration,
          expectedStoreRevision: expectedStoreRevision,
          updatedAtUtcMicros: updatedAtUtcMicros,
          body: body,
          color: color,
        );
    }
  }

  /// Applies one application action without aliasing the native event stream.
  Future<TerminalNoteSurfaceIntentResult> submitApplicationSurfaceAction({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int surfaceGeneration,
    required int projectionGeneration,
    required BigInt expectedStoreRevision,
    required TerminalNoteApplicationSurfaceAction action,
  }) {
    final TerminalNoteAuthorityMutationResult? sequenceFailure =
        _acceptStructuralSequence(sequence);
    if (sequenceFailure != null) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentFailure(sequenceFailure),
      );
    }
    final _LiveNotePane? pane = _livePanes[paneId];
    final _LiveNoteSurface? surface = pane?.surface;
    final TerminalNoteSurfaceProjection? projection = surface?.latest;
    if (pane == null ||
        pane.retired ||
        surface == null ||
        surface.retired ||
        projection == null ||
        surface.generation != surfaceGeneration ||
        projection.projectionGeneration != projectionGeneration ||
        projection.storeRevision != expectedStoreRevision ||
        expectedStoreRevision != _document.snapshot.storeRevision) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _surfaceIntentResult(
          TerminalNoteAuthorityMutationDisposition.stale,
          surface: surface,
          mutationFailure:
              expectedStoreRevision != _document.snapshot.storeRevision
              ? TerminalNoteMutationFailure.revisionConflict
              : null,
        ),
      );
    }
    if (surface.editorMode != TerminalNoteEditorMode.inactive ||
        surface.draftGeneration != 0) {
      return Future<TerminalNoteSurfaceIntentResult>.value(
        _invalidSurfaceIntent(surface),
      );
    }
    return Future<TerminalNoteSurfaceIntentResult>.value(switch (action) {
      TerminalNoteApplicationSurfaceAction.toggleNotes =>
        _applyRuntimeSurfaceIntent(pane, surface, () {
          surface.visibility =
              surface.visibility == TerminalNoteSurfaceVisibility.collapsed
              ? TerminalNoteSurfaceVisibility.expanded
              : TerminalNoteSurfaceVisibility.collapsed;
        }),
      TerminalNoteApplicationSurfaceAction.newNote
          when surface.nextDraftGeneration <=
              TerminalNoteProjectionLimits.maximumGeneration =>
        _applyRuntimeSurfaceIntent(pane, surface, () {
          surface
            ..visibility = TerminalNoteSurfaceVisibility.expanded
            ..section = TerminalNoteCollectionSection.current
            ..pageStart = 0
            ..selectedNoteId = null
            ..editorMode = TerminalNoteEditorMode.creating
            ..draftGeneration = surface.nextDraftGeneration++;
        }),
      TerminalNoteApplicationSurfaceAction.newNote => _invalidSurfaceIntent(
        surface,
      ),
    });
  }

  Future<TerminalNoteAuthorityMutationResult> bindPane({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    TerminalNoteContextKind kind = TerminalNoteContextKind.standard,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    if (_livePanes.containsKey(paneId)) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.duplicate),
      );
    }
    if (_livePanes.length >= TerminalNoteAuthorityLimits.maximumLiveContexts) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    final TerminalNoteContextId? quickContext =
        _bindings.quickTerminalContextId;
    if (kind == TerminalNoteContextKind.quickTerminal &&
        (quickContext == null ||
            _livePanes.values.any(
              (_LiveNotePane pane) => pane.contextId == quickContext,
            ))) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(
          TerminalNoteAuthorityMutationDisposition.rejected,
          mutationFailure: TerminalNoteMutationFailure.invalidState,
        ),
      );
    }
    final TerminalNoteContextId contextId =
        kind == TerminalNoteContextKind.quickTerminal
        ? quickContext!
        : _contextIdGenerator.next(
            excluding: <TerminalNoteContextId>{
              ..._document.snapshot.contexts.keys,
              ..._livePanes.values.map((_LiveNotePane pane) => pane.contextId),
            },
          );
    final _LiveNotePane pane = _LiveNotePane(
      paneId: paneId,
      contextId: contextId,
      kind: kind,
      initialSurfaceGeneration: authorityGeneration,
    );
    _livePanes[paneId] = pane;
    if (kind == TerminalNoteContextKind.quickTerminal) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.noChange),
      );
    }
    return _enqueueStructuralMutation(
      transition: (TerminalNoteSnapshot snapshot) =>
          TerminalNoteAuthorityMutationPlan(
            mutation: snapshot.createContext(
              id: contextId,
              kind: TerminalNoteContextKind.standard,
              expectedStoreRevision: snapshot.storeRevision,
            ),
          ),
      onResult: (TerminalNoteAuthorityMutationResult result) {
        if (result.disposition ==
                TerminalNoteAuthorityMutationDisposition.committed &&
            identical(_livePanes[paneId], pane) &&
            !pane.retired) {
          _replaceStandardBinding(paneId, contextId);
        } else if (!result.isAccepted && identical(_livePanes[paneId], pane)) {
          _livePanes.remove(paneId);
        }
      },
    );
  }

  Future<TerminalNoteAuthorityMutationResult> closePane({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int updatedAtUtcMicros,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    final _LiveNotePane? pane = _livePanes.remove(paneId);
    if (pane == null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    pane
      ..retired = true
      ..focusEdges.clear();
    final _LiveNoteSurface? surface = pane.surface;
    pane.surface = null;
    final Future<void> surfaceDisposed = surface == null
        ? Future<void>.value()
        : _disposeSurface(surface);
    final _LivePromptSession? session = pane.promptSession;
    if (session != null) {
      session
        ..retired = true
        ..promptEvents.clear();
      _liveSessions.remove(session.sessionId);
      pane.promptSession = null;
    }
    if (pane.kind == TerminalNoteContextKind.quickTerminal) {
      return surfaceDisposed.then(
        (_) => _result(TerminalNoteAuthorityMutationDisposition.noChange),
      );
    }
    _removeStandardBinding(paneId);
    final Future<TerminalNoteAuthorityMutationResult> detached =
        _enqueueStructuralMutation(
          transition: (TerminalNoteSnapshot snapshot) {
            final NoteContextRecord? context = snapshot.contextFor(
              pane.contextId,
            );
            return TerminalNoteAuthorityMutationPlan(
              mutation: context == null
                  ? snapshot.observeEligibleFocus(
                      contextId: pane.contextId,
                      isEligible: false,
                      expectedStoreRevision: snapshot.storeRevision,
                    )
                  : snapshot.detachContext(
                      contextId: pane.contextId,
                      reason: TerminalNoteDetachReason.contextUnavailable,
                      updatedAtUtcMicros: updatedAtUtcMicros,
                      expectedStoreRevision: snapshot.storeRevision,
                      expectedContextRevision: context.revision,
                    ),
            );
          },
        );
    return () async {
      final TerminalNoteAuthorityMutationResult result = await detached;
      await surfaceDisposed;
      return result;
    }();
  }

  Future<TerminalNoteAuthorityMutationResult> startPromptSession({
    required TerminalNoteAuthoritySequence sequence,
    required TerminalSessionId sessionId,
    required ShellIntegrationInstanceId instanceId,
    required BigInt semanticGeneration,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    final _LiveNotePane? pane = _livePanes[sessionId.paneId];
    if (pane == null ||
        pane.retired ||
        !_isPositiveSequence(sessionId.generation) ||
        semanticGeneration <= BigInt.zero ||
        semanticGeneration > TerminalNoteLimits.maximumUnsigned64) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    final _LivePromptSession? previous = pane.promptSession;
    if (previous != null) {
      if (sessionId.generation < previous.sessionId.generation) {
        return Future<TerminalNoteAuthorityMutationResult>.value(
          _result(TerminalNoteAuthorityMutationDisposition.stale),
        );
      }
      if (sessionId == previous.sessionId &&
          instanceId == previous.instanceId &&
          semanticGeneration == previous.semanticGeneration) {
        return Future<TerminalNoteAuthorityMutationResult>.value(
          _result(TerminalNoteAuthorityMutationDisposition.duplicate),
        );
      }
    } else if (_liveSessions.length >=
        TerminalNoteAuthorityLimits.maximumLiveSessions) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.busy),
      );
    }
    final NoteTriggerRuntimeBinding? previousBinding = previous?.runtimeBinding;
    if (previous != null) {
      previous
        ..retired = true
        ..promptEvents.clear();
      _liveSessions.remove(previous.sessionId);
    }
    final _LivePromptSession next = _LivePromptSession(
      sessionId: sessionId,
      instanceId: instanceId,
      semanticGeneration: semanticGeneration,
    );
    pane.promptSession = next;
    _liveSessions[sessionId] = next;
    if (previousBinding == null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.noChange),
      );
    }
    return _enqueueStructuralMutation(
      transition: (TerminalNoteSnapshot snapshot) =>
          TerminalNoteAuthorityMutationPlan(
            mutation: snapshot.suspendAtNextPrompt(
              contextId: pane.contextId,
              reason: NoteTriggerSuspendReason.instanceChanged,
              expectedStoreRevision: snapshot.storeRevision,
              matchingBinding: previousBinding,
            ),
          ),
    );
  }

  Future<TerminalNoteAuthorityMutationResult> endPromptSession({
    required TerminalNoteAuthoritySequence sequence,
    required TerminalSessionId sessionId,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    final _LivePromptSession? session = _liveSessions[sessionId];
    final _LiveNotePane? pane = _livePanes[sessionId.paneId];
    if (session == null || pane?.promptSession != session) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    final NoteTriggerRuntimeBinding binding = session.runtimeBinding;
    session
      ..retired = true
      ..promptEvents.clear();
    _liveSessions.remove(sessionId);
    pane!.promptSession = null;
    return _enqueueStructuralMutation(
      transition: (TerminalNoteSnapshot snapshot) =>
          TerminalNoteAuthorityMutationPlan(
            mutation: snapshot.suspendAtNextPrompt(
              contextId: pane.contextId,
              reason: NoteTriggerSuspendReason.sessionEnded,
              expectedStoreRevision: snapshot.storeRevision,
              matchingBinding: binding,
            ),
          ),
    );
  }

  TerminalNoteLifecycleResult observeEligibleFocus({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required bool isEligible,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) return _lifecycleFailure(ingressFailure);
    final _LiveNotePane? pane = _livePanes[paneId];
    if (pane == null || pane.retired) {
      return _lifecycleResult(TerminalNoteLifecycleDisposition.stale);
    }
    if (pane.lastObservedEligibility == isEligible) {
      return _lifecycleResult(TerminalNoteLifecycleDisposition.duplicate);
    }
    pane.lastObservedEligibility = isEligible;
    if (isEligible) {
      if (pane.eligibleVisitGeneration >=
          TerminalNoteProjectionLimits.maximumGeneration) {
        pane.eligibleVisitGeneration = 1;
        final _LiveNoteSurface? surface = pane.surface;
        if (surface != null) surface.lastAutomaticPresentationVisit = 0;
      } else {
        pane.eligibleVisitGeneration++;
      }
    }
    final bool atEdgeLimit =
        pane.focusEdges.length >= TerminalNoteLimits.maximumCoalescedFocusEdges;
    if (!atEdgeLimit) pane.focusEdges.add(isEligible);
    _ensureLifecyclePlaceholder(pane);
    return _lifecycleResult(
      atEdgeLimit
          ? TerminalNoteLifecycleDisposition.coalesced
          : TerminalNoteLifecycleDisposition.accepted,
    );
  }

  TerminalNoteLifecycleResult observePromptEvent({
    required TerminalNoteAuthoritySequence sequence,
    required TerminalSessionId sessionId,
    required ShellIntegrationInstanceId instanceId,
    required BigInt semanticGeneration,
    required BigInt eventSequence,
    required TerminalNotePromptAction action,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) return _lifecycleFailure(ingressFailure);
    final _LivePromptSession? session = _liveSessions[sessionId];
    final _LiveNotePane? pane = _livePanes[sessionId.paneId];
    if (session == null ||
        pane?.promptSession != session ||
        session.retired ||
        instanceId != session.instanceId ||
        semanticGeneration != session.semanticGeneration ||
        eventSequence <= BigInt.zero ||
        eventSequence > TerminalNoteLimits.maximumUnsigned64) {
      return _lifecycleResult(TerminalNoteLifecycleDisposition.stale);
    }
    if (eventSequence <= session.lastObservedEventSequence) {
      return _lifecycleResult(
        eventSequence == session.lastObservedEventSequence
            ? TerminalNoteLifecycleDisposition.duplicate
            : TerminalNoteLifecycleDisposition.stale,
      );
    }
    session.lastObservedEventSequence = eventSequence;
    if (session.overflowed) {
      return _lifecycleResult(TerminalNoteLifecycleDisposition.unavailable);
    }
    if (session.promptEvents.length >=
        TerminalNoteAuthorityLimits.maximumPromptEventsPerSession) {
      session
        ..overflowed = true
        ..overflowPending = true
        ..promptEvents.clear();
      _ensureLifecyclePlaceholder(pane!);
      return _lifecycleResult(TerminalNoteLifecycleDisposition.overflowed);
    }
    session.promptEvents.add(
      TerminalNotePromptEvent(sequence: eventSequence, action: action),
    );
    _ensureLifecyclePlaceholder(pane!);
    return _lifecycleResult(TerminalNoteLifecycleDisposition.accepted);
  }

  TerminalNoteSurfaceResult attachSurface({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required TerminalNoteSurfacePort port,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) return _surfaceFailure(ingressFailure);
    final _LiveNotePane? pane = _livePanes[paneId];
    if (pane == null || pane.retired) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.stale,
      );
    }
    if (pane.surface != null) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.duplicate,
      );
    }
    if (pane.nextSurfaceGeneration >
        TerminalNoteProjectionLimits.maximumGeneration) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.unavailable,
      );
    }
    final _LiveNoteSurface surface = _LiveNoteSurface(
      generation: pane.nextSurfaceGeneration++,
      intentSourceGeneration: _takeSurfaceIntentSourceGeneration(),
      port: port,
    );
    pane.surface = surface;
    return _applySurfaceProjection(pane, surface);
  }

  TerminalNoteSurfaceResult updateSurface({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int surfaceGeneration,
    required TerminalNoteSurfaceVisibility visibility,
    required bool foreground,
    required bool occluded,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) return _surfaceFailure(ingressFailure);
    final _LiveNotePane? pane = _livePanes[paneId];
    final _LiveNoteSurface? surface = pane?.surface;
    if (pane == null ||
        pane.retired ||
        surface == null ||
        surface.retired ||
        surface.generation != surfaceGeneration) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.stale,
      );
    }
    if (!surface.automaticPresentation) surface.visibility = visibility;
    surface
      ..foreground = foreground
      ..occluded = occluded;
    _prepareAutomaticDuePresentation(pane, surface);
    return _applySurfaceProjection(pane, surface);
  }

  Future<TerminalNoteSurfaceResult> detachSurface({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int surfaceGeneration,
  }) async {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) return _surfaceFailure(ingressFailure);
    final _LiveNotePane? pane = _livePanes[paneId];
    final _LiveNoteSurface? surface = pane?.surface;
    if (pane == null ||
        surface == null ||
        surface.retired ||
        surface.generation != surfaceGeneration) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.stale,
      );
    }
    pane.surface = null;
    await _disposeSurface(surface);
    return const TerminalNoteSurfaceResult(
      disposition: TerminalNoteSurfaceDisposition.applied,
    );
  }

  Future<TerminalNoteAuthorityMutationResult> acknowledgePresentation({
    required TerminalNoteAuthoritySequence sequence,
    required PaneId paneId,
    required int surfaceGeneration,
    required int projectionGeneration,
    required TerminalNoteCardToken cardToken,
    required bool visiblyLaidOut,
  }) {
    final TerminalNoteAuthorityMutationResult? ingressFailure =
        _acceptStructuralSequence(sequence);
    if (ingressFailure != null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(ingressFailure);
    }
    final _LiveNotePane? pane = _livePanes[paneId];
    final _LiveNoteSurface? surface = pane?.surface;
    final TerminalNoteSurfaceProjection? projection = surface?.latest;
    if (pane == null ||
        pane.retired ||
        surface == null ||
        surface.retired ||
        projection == null ||
        surface.generation != surfaceGeneration ||
        projection.projectionGeneration != projectionGeneration ||
        !projection.presentationEligible ||
        !visiblyLaidOut) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    if (surface.acknowledgedTokens.contains(cardToken)) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.duplicate),
      );
    }
    final NoteId? noteId = surface.noteIdsByToken[cardToken];
    final NoteDeliveryRecord? delivery = noteId == null
        ? null
        : _document.snapshot.deliveryFor(noteId);
    if (noteId == null || delivery == null) {
      return Future<TerminalNoteAuthorityMutationResult>.value(
        _result(TerminalNoteAuthorityMutationDisposition.stale),
      );
    }
    surface.acknowledgedTokens.add(cardToken);
    return _enqueueStructuralMutation(
      transition: (TerminalNoteSnapshot snapshot) =>
          TerminalNoteAuthorityMutationPlan(
            mutation: snapshot.acknowledgePresentation(
              noteId: noteId,
              triggerGeneration: delivery.triggerGeneration,
              expectedStoreRevision: snapshot.storeRevision,
            ),
          ),
    );
  }

  Future<TerminalNoteAuthorityShutdownResult> shutdownApplication({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    Duration drainTimeout = const Duration(seconds: 3),
  }) => _shutdownFuture ??= _runApplicationShutdown(
    capture: capture,
    updatedAtUtcMicros: updatedAtUtcMicros,
    commitRestoration: commitRestoration,
    drainTimeout: drainTimeout,
  );

  Future<void> whenIdle() => _idleCompleter?.future ?? Future<void>.value();

  Future<TerminalNoteStoreResult> stop() => _stopFuture ??= _runStop();

  void releaseIntentSource(int sourceGeneration) {
    _sourceEventHighWatermarks.remove(sourceGeneration);
  }

  TerminalNoteSurfaceResult _surfaceFailure(
    TerminalNoteAuthorityMutationResult failure,
  ) => TerminalNoteSurfaceResult(
    disposition: switch (failure.disposition) {
      TerminalNoteAuthorityMutationDisposition.unavailable =>
        TerminalNoteSurfaceDisposition.unavailable,
      _ => TerminalNoteSurfaceDisposition.stale,
    },
  );

  TerminalNoteSurfaceIntentResult _surfaceIntentFailure(
    TerminalNoteAuthorityMutationResult failure, {
    _LiveNoteSurface? surface,
  }) => TerminalNoteSurfaceIntentResult(
    disposition: failure.disposition,
    storeRevision: failure.storeRevision,
    projection: surface?.latest,
    mutationFailure: failure.mutationFailure,
    storeFailure: failure.storeFailure,
  );

  TerminalNoteSurfaceIntentResult _surfaceIntentResult(
    TerminalNoteAuthorityMutationDisposition disposition, {
    _LiveNoteSurface? surface,
    TerminalNoteMutationFailure? mutationFailure,
    TerminalNoteStoreFailure? storeFailure,
  }) => TerminalNoteSurfaceIntentResult(
    disposition: disposition,
    storeRevision: _document.snapshot.storeRevision,
    projection: surface?.latest,
    mutationFailure: mutationFailure,
    storeFailure: storeFailure,
  );

  TerminalNoteSurfaceIntentResult _invalidSurfaceIntent(
    _LiveNoteSurface surface,
  ) => _surfaceIntentResult(
    TerminalNoteAuthorityMutationDisposition.rejected,
    surface: surface,
    mutationFailure: TerminalNoteMutationFailure.invalidState,
  );

  static bool _validSurfaceIntentPayload({
    required TerminalNoteSurfaceIntentKind kind,
    required String? body,
    required NoteColorKey? color,
    required int? updatedAtUtcMicros,
    required TerminalNoteApprovedExportPath? exportDestination,
  }) => switch (kind) {
    TerminalNoteSurfaceIntentKind.save ||
    TerminalNoteSurfaceIntentKind.saveAlwaysAvailable ||
    TerminalNoteSurfaceIntentKind.saveOnReturn =>
      body != null &&
          color != null &&
          updatedAtUtcMicros != null &&
          exportDestination == null,
    TerminalNoteSurfaceIntentKind.armOnReturn ||
    TerminalNoteSurfaceIntentKind.makeAlwaysAvailable =>
      body == null &&
          color == null &&
          updatedAtUtcMicros == null &&
          exportDestination == null,
    TerminalNoteSurfaceIntentKind.copy =>
      body != null &&
          color == null &&
          updatedAtUtcMicros == null &&
          exportDestination == null,
    TerminalNoteSurfaceIntentKind.export =>
      body == null &&
          color == null &&
          updatedAtUtcMicros == null &&
          exportDestination != null,
    TerminalNoteSurfaceIntentKind.changeColor =>
      body == null &&
          color != null &&
          updatedAtUtcMicros != null &&
          exportDestination == null,
    TerminalNoteSurfaceIntentKind.moveEarlier ||
    TerminalNoteSurfaceIntentKind.moveLater ||
    TerminalNoteSurfaceIntentKind.resolve ||
    TerminalNoteSurfaceIntentKind.reopen ||
    TerminalNoteSurfaceIntentKind.delete ||
    TerminalNoteSurfaceIntentKind.reattach =>
      body == null &&
          color == null &&
          updatedAtUtcMicros != null &&
          exportDestination == null,
    TerminalNoteSurfaceIntentKind.open ||
    TerminalNoteSurfaceIntentKind.close ||
    TerminalNoteSurfaceIntentKind.showCurrent ||
    TerminalNoteSurfaceIntentKind.showDetached ||
    TerminalNoteSurfaceIntentKind.previousPage ||
    TerminalNoteSurfaceIntentKind.nextPage ||
    TerminalNoteSurfaceIntentKind.selectCard ||
    TerminalNoteSurfaceIntentKind.beginCreate ||
    TerminalNoteSurfaceIntentKind.beginEdit ||
    TerminalNoteSurfaceIntentKind.cancelEditor =>
      body == null &&
          color == null &&
          updatedAtUtcMicros == null &&
          exportDestination == null,
  };

  NoteId? _currentNoteId(
    _LiveNoteSurface surface,
    TerminalNoteCardToken? token,
  ) {
    if (surface.section != TerminalNoteCollectionSection.current ||
        token == null) {
      return null;
    }
    return surface.noteIdsByToken[token];
  }

  NoteId? _projectedNoteId(
    _LiveNoteSurface surface,
    TerminalNoteCardToken? token,
  ) => token == null ? null : surface.noteIdsByToken[token];

  bool _matchesEditorIntent(
    _LiveNoteSurface surface,
    TerminalNoteCardToken? token,
    int draftGeneration,
  ) {
    if (draftGeneration == 0 || surface.draftGeneration != draftGeneration) {
      return false;
    }
    return switch (surface.editorMode) {
      TerminalNoteEditorMode.inactive => false,
      TerminalNoteEditorMode.creating => token == null,
      TerminalNoteEditorMode.editing =>
        surface.selectedNoteId != null &&
            _currentNoteId(surface, token) == surface.selectedNoteId,
    };
  }

  TerminalNoteSurfaceIntentResult _applyRuntimeSurfaceIntent(
    _LiveNotePane pane,
    _LiveNoteSurface surface,
    void Function() update,
  ) {
    final TerminalNoteSurfaceVisibility previousVisibility = surface.visibility;
    final TerminalNoteCollectionSection previousSection = surface.section;
    final int previousPageStart = surface.pageStart;
    final NoteId? previousSelectedNoteId = surface.selectedNoteId;
    final TerminalNoteEditorMode previousEditorMode = surface.editorMode;
    final int previousDraftGeneration = surface.draftGeneration;
    final int previousNextDraftGeneration = surface.nextDraftGeneration;
    final bool previousAutomaticPresentation = surface.automaticPresentation;
    final int previousPendingAutomaticPresentationVisit =
        surface.pendingAutomaticPresentationVisit;
    surface
      ..automaticPresentation = false
      ..pendingAutomaticPresentationVisit = 0;
    update();
    final TerminalNoteSurfaceResult applied = _applySurfaceProjection(
      pane,
      surface,
    );
    if (applied.disposition == TerminalNoteSurfaceDisposition.applied) {
      return _surfaceIntentResult(
        TerminalNoteAuthorityMutationDisposition.runtimeApplied,
        surface: surface,
      );
    }
    surface
      ..visibility = previousVisibility
      ..section = previousSection
      ..pageStart = previousPageStart
      ..selectedNoteId = previousSelectedNoteId
      ..editorMode = previousEditorMode
      ..draftGeneration = previousDraftGeneration
      ..nextDraftGeneration = previousNextDraftGeneration
      ..automaticPresentation = previousAutomaticPresentation
      ..pendingAutomaticPresentationVisit =
          previousPendingAutomaticPresentationVisit;
    return _surfaceIntentResult(
      applied.disposition == TerminalNoteSurfaceDisposition.unavailable
          ? TerminalNoteAuthorityMutationDisposition.unavailable
          : TerminalNoteAuthorityMutationDisposition.rejected,
      surface: surface,
    );
  }

  Future<TerminalNoteSurfaceIntentResult> _submitDurableSurfaceIntent({
    required _LiveNotePane pane,
    required _LiveNoteSurface surface,
    required TerminalNoteSurfaceIntentKind kind,
    required TerminalNoteCardToken? cardToken,
    required int draftGeneration,
    required BigInt expectedStoreRevision,
    required int? updatedAtUtcMicros,
    required String? body,
    required NoteColorKey? color,
  }) async {
    final bool detachedReorder =
        surface.section == TerminalNoteCollectionSection.detached &&
        (kind == TerminalNoteSurfaceIntentKind.moveEarlier ||
            kind == TerminalNoteSurfaceIntentKind.moveLater);
    final bool reattaching = kind == TerminalNoteSurfaceIntentKind.reattach;
    if (surface.section != TerminalNoteCollectionSection.current &&
        !detachedReorder &&
        !reattaching) {
      return _invalidSurfaceIntent(surface);
    }
    final bool saving =
        kind == TerminalNoteSurfaceIntentKind.save ||
        kind == TerminalNoteSurfaceIntentKind.saveAlwaysAvailable ||
        kind == TerminalNoteSurfaceIntentKind.saveOnReturn;
    final bool triggerOnly =
        kind == TerminalNoteSurfaceIntentKind.armOnReturn ||
        kind == TerminalNoteSurfaceIntentKind.makeAlwaysAvailable;
    final NoteId? selectedNoteId = saving
        ? surface.selectedNoteId
        : _projectedNoteId(surface, cardToken);
    if (saving) {
      if (!_matchesEditorIntent(surface, cardToken, draftGeneration)) {
        return _invalidSurfaceIntent(surface);
      }
    } else if (surface.editorMode != TerminalNoteEditorMode.inactive ||
        draftGeneration != 0 ||
        selectedNoteId == null) {
      return _invalidSurfaceIntent(surface);
    }
    final NoteRecord? selectedNote = selectedNoteId == null
        ? null
        : _document.snapshot.noteFor(selectedNoteId);
    if (selectedNote != null) {
      final bool validAttachment = reattaching || detachedReorder
          ? selectedNote.attachment.isDetached
          : selectedNote.attachment.contextId == pane.contextId;
      if (!validAttachment) return _invalidSurfaceIntent(surface);
    }
    if (triggerOnly &&
        (selectedNote == null || selectedNote.status != NoteStatus.active)) {
      return _invalidSurfaceIntent(surface);
    }
    if (kind == TerminalNoteSurfaceIntentKind.makeAlwaysAvailable &&
        _document.snapshot.triggerFor(selectedNote!.id) == null) {
      return _invalidSurfaceIntent(surface);
    }

    NoteId? createdNoteId;
    TerminalNoteMutationResult applyShowTiming({
      required TerminalNoteMutationResult base,
      required NoteId noteId,
      required bool onReturn,
    }) {
      if (base.disposition == TerminalNoteMutationDisposition.rejected) {
        return base;
      }
      TerminalNoteMutationResult retained = base;
      TerminalNoteSnapshot working = base.snapshot;
      if (working.triggerFor(noteId) != null) {
        final NoteRecord note = working.noteFor(noteId)!;
        final TerminalNoteMutationResult canceled = working.cancelTrigger(
          noteId: noteId,
          expectedStoreRevision: working.storeRevision,
          expectedNoteRevision: note.revision,
        );
        if (canceled.disposition == TerminalNoteMutationDisposition.rejected) {
          return canceled;
        }
        if (canceled.disposition == TerminalNoteMutationDisposition.accepted) {
          retained = canceled;
          working = canceled.snapshot;
        }
      }
      if (!onReturn) return retained;
      final NoteRecord note = working.noteFor(noteId)!;
      return working.armOnReturn(
        noteId: noteId,
        isEligible: surface.foreground && !surface.occluded,
        expectedStoreRevision: working.storeRevision,
        expectedNoteRevision: note.revision,
      );
    }

    late final TerminalNoteAuthorityTransition transition;
    switch (kind) {
      case TerminalNoteSurfaceIntentKind.save:
      case TerminalNoteSurfaceIntentKind.saveAlwaysAvailable:
      case TerminalNoteSurfaceIntentKind.saveOnReturn:
        if (surface.editorMode == TerminalNoteEditorMode.creating) {
          transition = (TerminalNoteSnapshot snapshot) {
            createdNoteId = _noteIdGenerator.next(
              excluding: snapshot.notes.keys,
            );
            final TerminalNoteMutationResult created = snapshot.createNote(
              id: createdNoteId!,
              contextId: pane.contextId,
              body: body!,
              color: color!,
              utcMicros: updatedAtUtcMicros!,
              expectedStoreRevision: expectedStoreRevision,
            );
            return TerminalNoteAuthorityMutationPlan(
              mutation: kind == TerminalNoteSurfaceIntentKind.save
                  ? created
                  : applyShowTiming(
                      base: created,
                      noteId: createdNoteId!,
                      onReturn:
                          kind == TerminalNoteSurfaceIntentKind.saveOnReturn,
                    ),
            );
          };
          break;
        } else {
          if (selectedNote == null) return _invalidSurfaceIntent(surface);
          transition = (TerminalNoteSnapshot snapshot) {
            final TerminalNoteMutationResult edited = snapshot.editNote(
              noteId: selectedNote.id,
              body: body!,
              color: color!,
              updatedAtUtcMicros: updatedAtUtcMicros!,
              expectedStoreRevision: expectedStoreRevision,
              expectedNoteRevision: selectedNote.revision,
            );
            return TerminalNoteAuthorityMutationPlan(
              mutation: kind == TerminalNoteSurfaceIntentKind.save
                  ? edited
                  : applyShowTiming(
                      base: edited,
                      noteId: selectedNote.id,
                      onReturn:
                          kind == TerminalNoteSurfaceIntentKind.saveOnReturn,
                    ),
            );
          };
          break;
        }
      case TerminalNoteSurfaceIntentKind.armOnReturn:
        transition = (TerminalNoteSnapshot snapshot) {
          final NoteRecord note = snapshot.noteFor(selectedNote!.id)!;
          TerminalNoteSnapshot working = snapshot;
          if (snapshot.triggerFor(note.id) != null) {
            final TerminalNoteMutationResult canceled = snapshot.cancelTrigger(
              noteId: note.id,
              expectedStoreRevision: snapshot.storeRevision,
              expectedNoteRevision: note.revision,
            );
            if (canceled.disposition ==
                TerminalNoteMutationDisposition.rejected) {
              return TerminalNoteAuthorityMutationPlan(mutation: canceled);
            }
            working = canceled.snapshot;
          }
          final NoteRecord current = working.noteFor(note.id)!;
          return TerminalNoteAuthorityMutationPlan(
            mutation: working.armOnReturn(
              noteId: note.id,
              isEligible: surface.foreground && !surface.occluded,
              expectedStoreRevision: working.storeRevision,
              expectedNoteRevision: current.revision,
            ),
          );
        };
        break;
      case TerminalNoteSurfaceIntentKind.makeAlwaysAvailable:
        transition = (TerminalNoteSnapshot snapshot) {
          final NoteRecord note = snapshot.noteFor(selectedNote!.id)!;
          return TerminalNoteAuthorityMutationPlan(
            mutation: snapshot.cancelTrigger(
              noteId: note.id,
              expectedStoreRevision: expectedStoreRevision,
              expectedNoteRevision: note.revision,
            ),
          );
        };
        break;
      case TerminalNoteSurfaceIntentKind.changeColor:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) =>
            TerminalNoteAuthorityMutationPlan(
              mutation: snapshot.editNote(
                noteId: selectedNote.id,
                body: selectedNote.body.value,
                color: color!,
                updatedAtUtcMicros: updatedAtUtcMicros!,
                expectedStoreRevision: expectedStoreRevision,
                expectedNoteRevision: selectedNote.revision,
              ),
            );
        break;
      case TerminalNoteSurfaceIntentKind.moveEarlier:
      case TerminalNoteSurfaceIntentKind.moveLater:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) {
          final List<NoteRecord> notes =
              snapshot.notes.values
                  .where(
                    (NoteRecord note) => detachedReorder
                        ? note.attachment.isDetached
                        : note.attachment.contextId == pane.contextId,
                  )
                  .toList()
                ..sort((NoteRecord left, NoteRecord right) {
                  final int order = left.order.compareTo(right.order);
                  return order == 0 ? left.id.compareTo(right.id) : order;
                });
          final int index = notes.indexWhere(
            (NoteRecord note) => note.id == selectedNote.id,
          );
          if (index >= 0) {
            final int other = kind == TerminalNoteSurfaceIntentKind.moveEarlier
                ? index - 1
                : index + 1;
            if (other >= 0 && other < notes.length) {
              final NoteRecord moved = notes.removeAt(index);
              notes.insert(other, moved);
            }
          }
          return TerminalNoteAuthorityMutationPlan(
            mutation: detachedReorder
                ? snapshot.reorderDetachedNotes(
                    orderedNoteIds: notes.map((NoteRecord note) => note.id),
                    updatedAtUtcMicros: updatedAtUtcMicros!,
                    expectedStoreRevision: expectedStoreRevision,
                  )
                : snapshot.reorderAttachedNotes(
                    contextId: pane.contextId,
                    orderedNoteIds: notes.map((NoteRecord note) => note.id),
                    updatedAtUtcMicros: updatedAtUtcMicros!,
                    expectedStoreRevision: expectedStoreRevision,
                  ),
          );
        };
        break;
      case TerminalNoteSurfaceIntentKind.resolve:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) =>
            TerminalNoteAuthorityMutationPlan(
              mutation: snapshot.resolveNote(
                noteId: selectedNote.id,
                updatedAtUtcMicros: updatedAtUtcMicros!,
                expectedStoreRevision: expectedStoreRevision,
                expectedNoteRevision: selectedNote.revision,
              ),
            );
        break;
      case TerminalNoteSurfaceIntentKind.reopen:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) =>
            TerminalNoteAuthorityMutationPlan(
              mutation: snapshot.reopenNote(
                noteId: selectedNote.id,
                updatedAtUtcMicros: updatedAtUtcMicros!,
                expectedStoreRevision: expectedStoreRevision,
                expectedNoteRevision: selectedNote.revision,
              ),
            );
        break;
      case TerminalNoteSurfaceIntentKind.delete:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) {
          final TerminalNoteMutationResult mutation = snapshot.deleteNote(
            noteId: selectedNote.id,
            updatedAtUtcMicros: updatedAtUtcMicros!,
            expectedStoreRevision: expectedStoreRevision,
            expectedNoteRevision: selectedNote.revision,
          );
          return TerminalNoteAuthorityMutationPlan(
            mutation: mutation,
            deletions:
                mutation.disposition == TerminalNoteMutationDisposition.accepted
                ? <TerminalNoteDeletionTombstone>[
                    TerminalNoteDeletionTombstone(
                      noteId: selectedNote.id,
                      deletionRevision: mutation.snapshot.storeRevision,
                    ),
                  ]
                : const <TerminalNoteDeletionTombstone>[],
          );
        };
        break;
      case TerminalNoteSurfaceIntentKind.reattach:
        if (selectedNote == null) return _invalidSurfaceIntent(surface);
        transition = (TerminalNoteSnapshot snapshot) =>
            TerminalNoteAuthorityMutationPlan(
              mutation: snapshot.reattachNote(
                noteId: selectedNote.id,
                contextId: pane.contextId,
                updatedAtUtcMicros: updatedAtUtcMicros!,
                expectedStoreRevision: expectedStoreRevision,
                expectedNoteRevision: selectedNote.revision,
              ),
            );
        break;
      case TerminalNoteSurfaceIntentKind.open:
      case TerminalNoteSurfaceIntentKind.close:
      case TerminalNoteSurfaceIntentKind.showCurrent:
      case TerminalNoteSurfaceIntentKind.showDetached:
      case TerminalNoteSurfaceIntentKind.previousPage:
      case TerminalNoteSurfaceIntentKind.nextPage:
      case TerminalNoteSurfaceIntentKind.copy:
      case TerminalNoteSurfaceIntentKind.export:
      case TerminalNoteSurfaceIntentKind.selectCard:
      case TerminalNoteSurfaceIntentKind.beginCreate:
      case TerminalNoteSurfaceIntentKind.beginEdit:
      case TerminalNoteSurfaceIntentKind.cancelEditor:
        throw StateError('runtime Note intent reached durable dispatch');
    }

    final int previousProjectionGeneration =
        surface.latest!.projectionGeneration;
    final TerminalNoteAuthorityMutationResult result =
        await _enqueueUserMutation(
          bodyUtf8Bytes: body == null ? 0 : utf8.encode(body).length,
          transition: transition,
          onBeforePublication: () {
            surface
              ..automaticPresentation = false
              ..pendingAutomaticPresentationVisit = 0;
            if (saving) {
              surface
                ..selectedNoteId = createdNoteId ?? selectedNoteId
                ..editorMode = TerminalNoteEditorMode.inactive
                ..draftGeneration = 0;
            } else if (kind == TerminalNoteSurfaceIntentKind.delete) {
              surface
                ..selectedNoteId = null
                ..editorMode = TerminalNoteEditorMode.inactive
                ..draftGeneration = 0;
            } else if (kind == TerminalNoteSurfaceIntentKind.reattach) {
              surface.selectedNoteId = null;
            }
          },
        );
    if (result.disposition ==
        TerminalNoteAuthorityMutationDisposition.committed) {
      final TerminalNoteSurfaceProjection? published = surface.latest;
      if (surface.retired ||
          published == null ||
          published.storeRevision != result.storeRevision ||
          published.projectionGeneration <= previousProjectionGeneration) {
        return TerminalNoteSurfaceIntentResult(
          disposition: TerminalNoteAuthorityMutationDisposition.unavailable,
          storeRevision: result.storeRevision,
          projection: published,
        );
      }
    }
    return _surfaceIntentFailure(result, surface: surface);
  }

  TerminalNoteSurfaceResult _applySurfaceProjection(
    _LiveNotePane pane,
    _LiveNoteSurface surface,
  ) {
    if (pane.retired || surface.retired) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.stale,
      );
    }
    if (surface.nextProjectionGeneration >
        TerminalNoteProjectionLimits.maximumGeneration) {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.unavailable,
      );
    }
    final TerminalNoteContextProjection contextProjection;
    try {
      contextProjection = _document.snapshot.projectionFor(pane.contextId);
    } on Object {
      return const TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.unavailable,
      );
    }
    final List<NoteRecord> orderedNotes =
        surface.section == TerminalNoteCollectionSection.current
        ? contextProjection.orderedNotes
        : (_document.snapshot.notes.values
              .where((NoteRecord note) => note.attachment.isDetached)
              .toList()
            ..sort((NoteRecord left, NoteRecord right) {
              final int order = left.order.compareTo(right.order);
              return order == 0 ? left.id.compareTo(right.id) : order;
            }));
    final int totalCount = orderedNotes.length;
    final int selectedIndex = surface.selectedNoteId == null
        ? -1
        : orderedNotes.indexWhere(
            (NoteRecord note) => note.id == surface.selectedNoteId,
          );
    if (surface.selectedNoteId != null && selectedIndex < 0) {
      surface
        ..selectedNoteId = null
        ..editorMode = TerminalNoteEditorMode.inactive
        ..draftGeneration = 0;
    }
    if (surface.visibility == TerminalNoteSurfaceVisibility.collapsed &&
        surface.editorMode == TerminalNoteEditorMode.editing) {
      return TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.rejected,
        projection: surface.latest,
      );
    }
    if (totalCount == 0) {
      surface.pageStart = 0;
    } else if (surface.pageStart >= totalCount) {
      surface.pageStart =
          surface.section == TerminalNoteCollectionSection.detached
          ? ((totalCount - 1) ~/
                    TerminalNoteProjectionLimits.maximumExpandedCards) *
                TerminalNoteProjectionLimits.maximumExpandedCards
          : totalCount - 1;
    }
    if (surface.visibility == TerminalNoteSurfaceVisibility.expanded &&
        selectedIndex >= 0 &&
        (selectedIndex < surface.pageStart ||
            selectedIndex >=
                surface.pageStart +
                    TerminalNoteProjectionLimits.maximumExpandedCards)) {
      surface.pageStart =
          surface.section == TerminalNoteCollectionSection.detached
          ? (selectedIndex ~/
                    TerminalNoteProjectionLimits.maximumExpandedCards) *
                TerminalNoteProjectionLimits.maximumExpandedCards
          : selectedIndex;
    }
    final Map<TerminalNoteCardToken, NoteId> noteIdsByToken =
        <TerminalNoteCardToken, NoteId>{};
    final List<TerminalNoteCardProjection> cards =
        <TerminalNoteCardProjection>[];
    TerminalNoteCardToken? selectedToken;
    if (surface.visibility == TerminalNoteSurfaceVisibility.expanded) {
      var bodyBytes = 0;
      for (final NoteRecord note in orderedNotes.skip(surface.pageStart)) {
        if (cards.length >= TerminalNoteProjectionLimits.maximumExpandedCards) {
          break;
        }
        if (bodyBytes + note.body.utf8Length >
            TerminalNoteProjectionLimits.maximumExpandedBodyUtf8Bytes) {
          break;
        }
        if (_nextCardToken > TerminalNoteProjectionLimits.maximumGeneration) {
          return const TerminalNoteSurfaceResult(
            disposition: TerminalNoteSurfaceDisposition.unavailable,
          );
        }
        final TerminalNoteCardToken token = TerminalNoteCardToken(
          _nextCardToken++,
        );
        final NoteTriggerRecord? trigger = _document.snapshot.triggerFor(
          note.id,
        );
        final bool due = _document.snapshot.deliveryFor(note.id) != null;
        cards.add(
          TerminalNoteCardProjection(
            token: token,
            body: note.body.value,
            color: note.color,
            status: note.status,
            order: note.order,
            due: due,
            triggerKind: trigger?.kind,
            triggerPhase: trigger?.phase,
          ),
        );
        noteIdsByToken[token] = note.id;
        if (note.id == surface.selectedNoteId) selectedToken = token;
        bodyBytes += note.body.utf8Length;
      }
    }
    if (surface.editorMode == TerminalNoteEditorMode.editing &&
        selectedToken == null) {
      return TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.unavailable,
        projection: surface.latest,
      );
    }
    final TerminalNoteSurfaceProjection candidate =
        TerminalNoteSurfaceProjection(
          paneId: pane.paneId,
          surfaceGeneration: surface.generation,
          projectionGeneration: surface.nextProjectionGeneration++,
          storeRevision: _document.snapshot.storeRevision,
          visibility: surface.visibility,
          presentationEligible:
              surface.visibility == TerminalNoteSurfaceVisibility.expanded &&
              surface.foreground &&
              !surface.occluded,
          automaticPresentation: surface.automaticPresentation,
          activeCount: contextProjection.activeCount,
          dueCount: contextProjection.dueCount,
          section: surface.section,
          pageStart: surface.pageStart,
          totalCount: totalCount,
          selectedToken: selectedToken,
          editorMode: surface.editorMode,
          draftGeneration: surface.draftGeneration,
          cards: cards,
        );
    try {
      if (!surface.port.applyProjection(candidate)) {
        return TerminalNoteSurfaceResult(
          disposition: TerminalNoteSurfaceDisposition.rejected,
          projection: surface.latest,
        );
      }
    } on Object {
      return TerminalNoteSurfaceResult(
        disposition: TerminalNoteSurfaceDisposition.rejected,
        projection: surface.latest,
      );
    }
    surface
      ..latest = candidate
      ..noteIdsByToken = noteIdsByToken
      ..acknowledgedTokens.clear();
    if (surface.pendingAutomaticPresentationVisit != 0) {
      surface
        ..lastAutomaticPresentationVisit =
            surface.pendingAutomaticPresentationVisit
        ..pendingAutomaticPresentationVisit = 0;
    }
    return TerminalNoteSurfaceResult(
      disposition: TerminalNoteSurfaceDisposition.applied,
      projection: candidate,
    );
  }

  void _refreshAllSurfaces() {
    for (final _LiveNotePane pane in _livePanes.values) {
      final _LiveNoteSurface? surface = pane.surface;
      if (surface != null) {
        _prepareAutomaticDuePresentation(pane, surface);
        _applySurfaceProjection(pane, surface);
      }
    }
  }

  void _prepareAutomaticDuePresentation(
    _LiveNotePane pane,
    _LiveNoteSurface surface,
  ) {
    final int visit = pane.eligibleVisitGeneration;
    if (visit == 0 ||
        pane.lastObservedEligibility != true ||
        !surface.foreground ||
        surface.occluded ||
        surface.editorMode != TerminalNoteEditorMode.inactive ||
        surface.lastAutomaticPresentationVisit == visit ||
        surface.pendingAutomaticPresentationVisit == visit) {
      return;
    }
    final TerminalNoteContextProjection projection;
    try {
      projection = _document.snapshot.projectionFor(pane.contextId);
    } on Object {
      return;
    }
    NoteRecord? firstDue;
    for (final NoteRecord note in projection.orderedNotes) {
      if (_document.snapshot.deliveryFor(note.id) != null) {
        firstDue = note;
        break;
      }
    }
    if (firstDue == null) return;
    surface
      ..visibility = TerminalNoteSurfaceVisibility.expanded
      ..section = TerminalNoteCollectionSection.current
      ..pageStart = 0
      ..selectedNoteId = firstDue.id
      ..automaticPresentation = true
      ..pendingAutomaticPresentationVisit = visit;
  }

  Future<void> _disposeSurface(_LiveNoteSurface surface) async {
    if (surface.retired) return;
    _sourceEventHighWatermarks.remove(surface.intentSourceGeneration);
    surface
      ..retired = true
      ..noteIdsByToken = <TerminalNoteCardToken, NoteId>{}
      ..acknowledgedTokens.clear();
    try {
      await surface.port.dispose();
    } on Object {
      // Surface teardown failure cannot retain authority ownership.
    }
  }

  int _takeSurfaceIntentSourceGeneration() {
    if (_nextSurfaceIntentSourceGeneration <= 0) {
      throw StateError('Note surface intent source generation exhausted');
    }
    return _nextSurfaceIntentSourceGeneration--;
  }

  void _initializeLiveBindings() {
    _livePanes.clear();
    for (final MapEntry<PaneId, TerminalNoteContextId> entry
        in _bindings.standardPaneContexts.entries) {
      _livePanes[entry.key] = _LiveNotePane(
        paneId: entry.key,
        contextId: entry.value,
        kind: TerminalNoteContextKind.standard,
        initialSurfaceGeneration: authorityGeneration,
      );
    }
  }

  void _replaceStandardBinding(PaneId paneId, TerminalNoteContextId contextId) {
    _bindings = TerminalNoteContextBindings(
      standardPaneContexts: <PaneId, TerminalNoteContextId>{
        ..._bindings.standardPaneContexts,
        paneId: contextId,
      },
      quickTerminalContextId: _bindings.quickTerminalContextId,
    );
  }

  void _removeStandardBinding(PaneId paneId) {
    final Map<PaneId, TerminalNoteContextId> standard =
        Map<PaneId, TerminalNoteContextId>.of(_bindings.standardPaneContexts)
          ..remove(paneId);
    _bindings = TerminalNoteContextBindings(
      standardPaneContexts: standard,
      quickTerminalContextId: _bindings.quickTerminalContextId,
    );
  }

  Future<TerminalNoteAuthorityMutationResult> _enqueueStructuralMutation({
    required TerminalNoteAuthorityTransition transition,
    void Function(TerminalNoteAuthorityMutationResult result)? onResult,
  }) {
    final _PendingAuthorityMutation pending = _PendingAuthorityMutation(
      transition: transition,
      bodyUtf8Bytes: 0,
      countsTowardUserIntentLimit: false,
      onResult: onResult,
    );
    _enqueue(pending);
    return pending.completer.future;
  }

  void _ensureLifecyclePlaceholder(_LiveNotePane pane) {
    if (pane.retired || pane.lifecycleQueued) return;
    pane.lifecycleQueued = true;
    final _PendingAuthorityMutation pending = _PendingAuthorityMutation(
      transition: (TerminalNoteSnapshot snapshot) =>
          _captureLifecyclePlan(pane, snapshot),
      bodyUtf8Bytes: 0,
      countsTowardUserIntentLimit: false,
      onFinished: () {
        pane.lifecycleQueued = false;
        if (pane.retired ||
            (_capability != TerminalNoteAuthorityCapability.ready &&
                _capability != TerminalNoteAuthorityCapability.draining)) {
          return;
        }
        final bool? observed = pane.lastObservedEligibility;
        if (pane.focusEdges.isEmpty &&
            observed != null &&
            observed != pane.lastDrainedEligibility) {
          pane.focusEdges.add(observed);
        }
        final _LivePromptSession? session = pane.promptSession;
        if (pane.focusEdges.isNotEmpty ||
            (session != null &&
                (session.promptEvents.isNotEmpty || session.overflowPending))) {
          _ensureLifecyclePlaceholder(pane);
        }
      },
    );
    _enqueue(pending);
  }

  TerminalNoteAuthorityMutationPlan _captureLifecyclePlan(
    _LiveNotePane pane,
    TerminalNoteSnapshot snapshot,
  ) {
    if (pane.retired) {
      return TerminalNoteAuthorityMutationPlan(
        mutation: snapshot.observeLifecycleBatch(
          contextId: pane.contextId,
          expectedStoreRevision: snapshot.storeRevision,
        ),
      );
    }
    final List<bool> focusEdges = List<bool>.of(pane.focusEdges);
    pane.focusEdges.clear();
    if (focusEdges.isNotEmpty) {
      pane.lastDrainedEligibility = focusEdges.last;
    }
    final _LivePromptSession? session = pane.promptSession;
    final List<TerminalNotePromptEvent> promptEvents = session == null
        ? const <TerminalNotePromptEvent>[]
        : List<TerminalNotePromptEvent>.of(session.promptEvents);
    session?.promptEvents.clear();
    final bool promptOverflow = session?.overflowPending ?? false;
    if (session != null) session.overflowPending = false;
    return TerminalNoteAuthorityMutationPlan(
      mutation: snapshot.observeLifecycleBatch(
        contextId: pane.contextId,
        expectedStoreRevision: snapshot.storeRevision,
        eligibleFocusEdges: focusEdges,
        promptBinding: session?.runtimeBinding,
        promptEvents: promptEvents,
        promptEventOverflow: promptOverflow,
      ),
    );
  }

  void _enqueue(_PendingAuthorityMutation pending) {
    _pending.add(pending);
    _idleCompleter ??= Completer<void>();
    _pump();
  }

  TerminalNoteLifecycleResult _lifecycleResult(
    TerminalNoteLifecycleDisposition disposition,
  ) => TerminalNoteLifecycleResult(
    disposition,
    pendingFocusEdgeCount: pendingFocusEdgeCount,
    pendingPromptEventCount: pendingPromptEventCount,
  );

  TerminalNoteLifecycleResult _lifecycleFailure(
    TerminalNoteAuthorityMutationResult failure,
  ) => _lifecycleResult(switch (failure.disposition) {
    TerminalNoteAuthorityMutationDisposition.unavailable =>
      TerminalNoteLifecycleDisposition.unavailable,
    TerminalNoteAuthorityMutationDisposition.busy =>
      TerminalNoteLifecycleDisposition.busy,
    _ => TerminalNoteLifecycleDisposition.stale,
  });

  TerminalNoteAuthorityMutationResult? _acceptStructuralSequence(
    TerminalNoteAuthoritySequence sequence,
  ) {
    final TerminalNoteAuthorityMutationResult? failure = _validateSequence(
      sequence,
    );
    if (failure == null) _lastIngressSequence = sequence.value;
    return failure;
  }

  TerminalNoteAuthorityMutationResult? _validateIngress(
    TerminalNoteAuthoritySequence sequence,
    TerminalNoteAuthorityIntentToken token,
  ) {
    final TerminalNoteAuthorityMutationResult? sequenceFailure =
        _validateSequence(sequence);
    if (sequenceFailure != null) return sequenceFailure;
    if (token.authorityGeneration != authorityGeneration) {
      return _result(TerminalNoteAuthorityMutationDisposition.stale);
    }
    return null;
  }

  TerminalNoteAuthorityMutationResult? _admitUserIntent(
    TerminalNoteAuthoritySequence sequence,
    TerminalNoteAuthorityIntentToken token,
  ) {
    final TerminalNoteAuthorityMutationResult? failure = _validateIngress(
      sequence,
      token,
    );
    if (failure != null) return failure;
    _lastIngressSequence = sequence.value;
    final int? previousEvent =
        _sourceEventHighWatermarks[token.sourceGeneration];
    if (previousEvent != null && token.eventSequence <= previousEvent) {
      return _result(
        token.eventSequence == previousEvent
            ? TerminalNoteAuthorityMutationDisposition.duplicate
            : TerminalNoteAuthorityMutationDisposition.stale,
      );
    }
    if (previousEvent == null &&
        _sourceEventHighWatermarks.length >=
            TerminalNoteAuthorityLimits.maximumIntentSources) {
      return _result(TerminalNoteAuthorityMutationDisposition.busy);
    }
    _sourceEventHighWatermarks[token.sourceGeneration] = token.eventSequence;
    return null;
  }

  TerminalNoteAuthorityMutationResult? _validateSequence(
    TerminalNoteAuthoritySequence sequence,
  ) {
    if (_capability != TerminalNoteAuthorityCapability.ready) {
      return _result(TerminalNoteAuthorityMutationDisposition.unavailable);
    }
    if (sequence.authorityGeneration != authorityGeneration ||
        sequence.value <= _lastIngressSequence ||
        sequence.value >= _nextAuthoritySequence) {
      return _result(TerminalNoteAuthorityMutationDisposition.stale);
    }
    return null;
  }

  void _pump() {
    if (_inFlight != null || _pending.isEmpty) return;
    final _PendingAuthorityMutation pending = _pending.removeFirst();
    if (pending.countsTowardUserIntentLimit) {
      _pendingUserIntentCount--;
    }
    _inFlight = pending;
    unawaited(
      _runMutation(pending).whenComplete(() {
        _pendingBodyBytes -= pending.bodyUtf8Bytes;
        pending.finish();
        _inFlight = null;
        if (_capability == TerminalNoteAuthorityCapability.ready ||
            _capability == TerminalNoteAuthorityCapability.draining) {
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
    if (pending.exportDestination != null) {
      await _runExport(pending);
      return;
    }
    TerminalNoteAuthorityMutationPlan plan;
    try {
      plan = pending.transition!(_document.snapshot);
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
        pending.onBeforePublication?.call();
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
    if (_discardLateCommit) {
      pending.complete(
        _result(TerminalNoteAuthorityMutationDisposition.unavailable),
      );
      return;
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
    pending.onBeforePublication?.call();
    _publish(TerminalNoteAuthorityPublicationKind.durable);
    pending.complete(
      _result(TerminalNoteAuthorityMutationDisposition.committed),
    );
  }

  Future<void> _runExport(_PendingAuthorityMutation pending) async {
    final BigInt expectedStoreRevision = pending.exportExpectedStoreRevision!;
    if (_document.snapshot.storeRevision != expectedStoreRevision) {
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.rejected,
          mutationFailure: TerminalNoteMutationFailure.revisionConflict,
        ),
      );
      return;
    }
    final TerminalNoteAuthorityStorePort? store = _store;
    if (store == null) {
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.unavailable,
          storeFailure: TerminalNoteStoreFailure.invalidState,
        ),
      );
      return;
    }
    TerminalNoteStoreResult exported;
    try {
      exported = await store.exportToApprovedPath(pending.exportDestination!);
    } on Object {
      exported = _storeFailureResult(TerminalNoteStoreFailure.unknown);
    }
    if (_discardLateCommit) {
      pending.complete(
        _result(TerminalNoteAuthorityMutationDisposition.unavailable),
      );
      return;
    }
    if (exported.disposition != TerminalNoteStoreDisposition.exported ||
        exported.failure != null ||
        exported.storeRevision != expectedStoreRevision) {
      pending.complete(
        _result(
          TerminalNoteAuthorityMutationDisposition.failed,
          storeFailure:
              exported.failure ?? TerminalNoteStoreFailure.invariantViolation,
        ),
      );
      return;
    }
    pending.complete(
      _result(TerminalNoteAuthorityMutationDisposition.runtimeApplied),
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
    await _disposeAllSurfaces();
    final TerminalNoteAuthorityStorePort? store = _store;
    late TerminalNoteStoreResult result;
    try {
      result = store == null ? _stoppedStoreResult() : await store.stop();
    } on Object {
      result = _storeFailureResult(TerminalNoteStoreFailure.unknown);
    }
    _clearRuntimeOwnership();
    _capability = TerminalNoteAuthorityCapability.stopped;
    _stopResult = result;
    _retireDebugHandle();
    return result;
  }

  Future<TerminalNoteAuthorityShutdownResult> _runApplicationShutdown({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    required Duration drainTimeout,
  }) async {
    if (drainTimeout <= Duration.zero) {
      throw ArgumentError.value(
        drainTimeout,
        'drainTimeout',
        'must be positive',
      );
    }
    if (_capability == TerminalNoteAuthorityCapability.stopped) {
      return TerminalNoteAuthorityShutdownResult(
        disposition: TerminalNoteAuthorityShutdownDisposition.storeStopFailed,
        persistence: null,
        storeDisposition:
            _stopResult?.disposition ?? TerminalNoteStoreDisposition.stopped,
        surfaceDisposeCount: 0,
      );
    }
    _capability = TerminalNoteAuthorityCapability.draining;
    var drained = true;
    try {
      await whenIdle().timeout(drainTimeout);
    } on TimeoutException {
      drained = false;
      _discardLateCommit = true;
      _capability = TerminalNoteAuthorityCapability.stopping;
      _failPending();
    }

    TerminalNoteOrderedPersistenceResult? persistence;
    var preparationFailed = false;
    if (drained) {
      try {
        final TerminalNoteShutdownCandidate candidate =
            const TerminalNoteShutdownCandidateBuilder().prepare(
              stored: _document,
              capture: capture,
              bindings: _bindings,
              updatedAtUtcMicros: updatedAtUtcMicros,
            );
        persistence = await TerminalNoteOrderedPersistenceCoordinator(
          commitRestoration: commitRestoration,
          commitNoteDocument: (TerminalNoteStoreDocument document) async {
            final TerminalNoteAuthorityStorePort? store = _store;
            if (store == null) return false;
            try {
              final TerminalNoteStoreResult result = await store
                  .commitCandidate(document);
              if (!_isMatchingCommit(result, document)) return false;
              _document = document;
              return true;
            } on Object {
              return false;
            }
          },
        ).commit(candidate);
      } on Object {
        preparationFailed = true;
      }
    }

    _capability = TerminalNoteAuthorityCapability.stopping;
    final int surfaceDisposeCount = await _disposeAllSurfaces();
    TerminalNoteStoreResult stopResult;
    try {
      stopResult = _store == null ? _stoppedStoreResult() : await _store.stop();
    } on Object {
      stopResult = _storeFailureResult(TerminalNoteStoreFailure.unknown);
    }
    _stopResult = stopResult;
    _clearRuntimeOwnership();
    _capability = TerminalNoteAuthorityCapability.stopped;
    _retireDebugHandle();

    final TerminalNoteAuthorityShutdownDisposition disposition;
    if (!drained) {
      disposition = TerminalNoteAuthorityShutdownDisposition.drainTimedOut;
    } else if (preparationFailed) {
      disposition = TerminalNoteAuthorityShutdownDisposition.preparationFailed;
    } else if (persistence == null || !persistence.isSuccess) {
      disposition = TerminalNoteAuthorityShutdownDisposition.persistenceFailed;
    } else if (stopResult.disposition != TerminalNoteStoreDisposition.stopped) {
      disposition = TerminalNoteAuthorityShutdownDisposition.storeStopFailed;
    } else {
      disposition = TerminalNoteAuthorityShutdownDisposition.committed;
    }
    return TerminalNoteAuthorityShutdownResult(
      disposition: disposition,
      persistence: persistence,
      storeDisposition: stopResult.disposition,
      surfaceDisposeCount: surfaceDisposeCount,
    );
  }

  Future<int> _disposeAllSurfaces() async {
    final List<_LiveNoteSurface> surfaces = <_LiveNoteSurface>[
      for (final _LiveNotePane pane in _livePanes.values)
        if (pane.surface != null) pane.surface!,
    ];
    for (final _LiveNotePane pane in _livePanes.values) {
      pane.surface = null;
    }
    for (final _LiveNoteSurface surface in surfaces) {
      await _disposeSurface(surface);
    }
    return surfaces.length;
  }

  void _clearRuntimeOwnership() {
    for (final _LivePromptSession session in _liveSessions.values) {
      session
        ..retired = true
        ..promptEvents.clear();
    }
    for (final _LiveNotePane pane in _livePanes.values) {
      pane
        ..retired = true
        ..focusEdges.clear()
        ..promptSession = null;
    }
    _liveSessions.clear();
    _livePanes.clear();
    _sourceEventHighWatermarks.clear();
  }

  void _retireDebugHandle() {
    if (_debugRetired) return;
    _debugRetired = true;
    _debugLiveAuthorityCount--;
  }

  void _failPending() {
    while (_pending.isNotEmpty) {
      final _PendingAuthorityMutation pending = _pending.removeFirst();
      if (pending.countsTowardUserIntentLimit) {
        _pendingUserIntentCount--;
      }
      _pendingBodyBytes -= pending.bodyUtf8Bytes;
      pending.complete(
        _result(TerminalNoteAuthorityMutationDisposition.unavailable),
      );
      pending.finish();
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
    final TerminalNoteSnapshot snapshot = _document.snapshot;
    if (observer != null) {
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
    _refreshAllSurfaces();
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
    required this.countsTowardUserIntentLimit,
    this.onBeforePublication,
    this.onResult,
    this.onFinished,
  }) : exportDestination = null,
       exportExpectedStoreRevision = null;

  _PendingAuthorityMutation.export({
    required TerminalNoteApprovedExportPath destination,
    required BigInt expectedStoreRevision,
  }) : transition = null,
       bodyUtf8Bytes = 0,
       countsTowardUserIntentLimit = true,
       onBeforePublication = null,
       onResult = null,
       onFinished = null,
       exportDestination = destination,
       exportExpectedStoreRevision = expectedStoreRevision;

  final TerminalNoteAuthorityTransition? transition;
  final int bodyUtf8Bytes;
  final bool countsTowardUserIntentLimit;
  final void Function()? onBeforePublication;
  final void Function(TerminalNoteAuthorityMutationResult result)? onResult;
  final void Function()? onFinished;
  final TerminalNoteApprovedExportPath? exportDestination;
  final BigInt? exportExpectedStoreRevision;
  final Completer<TerminalNoteAuthorityMutationResult> completer =
      Completer<TerminalNoteAuthorityMutationResult>();
  var _finished = false;

  void complete(TerminalNoteAuthorityMutationResult result) {
    if (completer.isCompleted) return;
    onResult?.call(result);
    completer.complete(result);
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    onFinished?.call();
  }
}

final class _LiveNotePane {
  _LiveNotePane({
    required this.paneId,
    required this.contextId,
    required this.kind,
    required int initialSurfaceGeneration,
  }) : nextSurfaceGeneration = initialSurfaceGeneration;

  final PaneId paneId;
  final TerminalNoteContextId contextId;
  final TerminalNoteContextKind kind;
  final List<bool> focusEdges = <bool>[];
  _LivePromptSession? promptSession;
  _LiveNoteSurface? surface;
  bool? lastObservedEligibility;
  bool? lastDrainedEligibility;
  var eligibleVisitGeneration = 0;
  int nextSurfaceGeneration;
  var lifecycleQueued = false;
  var retired = false;
}

final class _LiveNoteSurface {
  _LiveNoteSurface({
    required this.generation,
    required this.intentSourceGeneration,
    required this.port,
  });

  final int generation;
  final int intentSourceGeneration;
  final TerminalNoteSurfacePort port;
  TerminalNoteSurfaceVisibility visibility =
      TerminalNoteSurfaceVisibility.collapsed;
  var foreground = false;
  var occluded = false;
  var automaticPresentation = false;
  var lastAutomaticPresentationVisit = 0;
  var pendingAutomaticPresentationVisit = 0;
  var nextProjectionGeneration = 1;
  var section = TerminalNoteCollectionSection.current;
  var pageStart = 0;
  NoteId? selectedNoteId;
  var editorMode = TerminalNoteEditorMode.inactive;
  var draftGeneration = 0;
  var nextDraftGeneration = 1;
  var retired = false;
  TerminalNoteSurfaceProjection? latest;
  Map<TerminalNoteCardToken, NoteId> noteIdsByToken =
      <TerminalNoteCardToken, NoteId>{};
  final Set<TerminalNoteCardToken> acknowledgedTokens =
      <TerminalNoteCardToken>{};
}

final class _LivePromptSession {
  _LivePromptSession({
    required this.sessionId,
    required this.instanceId,
    required this.semanticGeneration,
  });

  final TerminalSessionId sessionId;
  final ShellIntegrationInstanceId instanceId;
  final BigInt semanticGeneration;
  final List<TerminalNotePromptEvent> promptEvents =
      <TerminalNotePromptEvent>[];
  var lastObservedEventSequence = BigInt.zero;
  var overflowPending = false;
  var overflowed = false;
  var retired = false;

  NoteTriggerRuntimeBinding get runtimeBinding => NoteTriggerRuntimeBinding(
    sessionGeneration: BigInt.from(sessionId.generation),
    instanceId: instanceId,
    semanticGeneration: semanticGeneration,
    lastEventSequence: lastObservedEventSequence,
  );
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
