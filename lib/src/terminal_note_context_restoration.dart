import 'dart:convert';
import 'dart:math';

import 'terminal_application_state.dart';
import 'terminal_note_model.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_pane.dart';
import 'terminal_restoration.dart';
import 'terminal_sha256.dart';

abstract final class TerminalNoteContextIdentityLimits {
  static const int byteLength = 16;
  static const int maximumCollisionAttempts = 32;
}

enum TerminalNoteContextIdentityFailure { entropyRejected, collisionLimit }

/// Fixed, content-free context identity generation failure.
final class TerminalNoteContextIdentityException implements Exception {
  const TerminalNoteContextIdentityException(this.failure);

  final TerminalNoteContextIdentityFailure failure;

  @override
  String toString() => 'Terminal note context identity failed: ${failure.name}';
}

typedef TerminalNoteContextEntropySource = List<int> Function();

/// Issues opaque 128-bit Note context identities.
///
/// Product code uses [secure]. Tests may inject deterministic bytes through
/// [forTesting] without weakening the production constructor.
final class TerminalNoteContextIdGenerator {
  factory TerminalNoteContextIdGenerator.secure() {
    final Random random = Random.secure();
    return TerminalNoteContextIdGenerator._(
      () => List<int>.generate(
        TerminalNoteContextIdentityLimits.byteLength,
        (_) => random.nextInt(256),
        growable: false,
      ),
    );
  }

  const TerminalNoteContextIdGenerator.forTesting(
    TerminalNoteContextEntropySource source,
  ) : _source = source;

  const TerminalNoteContextIdGenerator._(this._source);

  final TerminalNoteContextEntropySource _source;

  TerminalNoteContextId next({
    Iterable<TerminalNoteContextId> excluding = const <TerminalNoteContextId>[],
  }) {
    final Set<TerminalNoteContextId> reserved = excluding.toSet();
    for (
      var attempt = 0;
      attempt < TerminalNoteContextIdentityLimits.maximumCollisionAttempts;
      attempt++
    ) {
      final List<int> bytes = _source();
      if (bytes.length != TerminalNoteContextIdentityLimits.byteLength ||
          bytes.any((int value) => value < 0 || value > 0xff)) {
        throw const TerminalNoteContextIdentityException(
          TerminalNoteContextIdentityFailure.entropyRejected,
        );
      }
      final StringBuffer encoded = StringBuffer();
      for (final int byte in bytes) {
        encoded.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      final TerminalNoteContextId candidate = TerminalNoteContextId.fromHex(
        encoded.toString(),
      );
      if (!reserved.contains(candidate)) return candidate;
    }
    throw const TerminalNoteContextIdentityException(
      TerminalNoteContextIdentityFailure.collisionLimit,
    );
  }
}

/// One version-1 restoration snapshot and the exact bytes used for binding.
final class TerminalNoteRestorationArtifact {
  factory TerminalNoteRestorationArtifact.fromSnapshot(
    TerminalRestorationSnapshot snapshot,
  ) => TerminalNoteRestorationArtifact._(
    snapshot: snapshot,
    exactEncoded: TerminalRestorationCodec.encode(snapshot),
  );

  factory TerminalNoteRestorationArtifact.fromExactEncoded(String encoded) =>
      TerminalNoteRestorationArtifact._(
        snapshot: TerminalRestorationCodec.decode(encoded),
        exactEncoded: encoded,
      );

  TerminalNoteRestorationArtifact._({
    required this.snapshot,
    required this.exactEncoded,
  }) : exactUtf8Bytes = List<int>.unmodifiable(utf8.encode(exactEncoded)),
       restorationSha256 = terminalSha256(utf8.encode(exactEncoded));

  final TerminalRestorationSnapshot snapshot;
  final String exactEncoded;
  final List<int> exactUtf8Bytes;
  final String restorationSha256;
}

/// Captured restoration bytes plus live standard panes in exact codec order.
final class TerminalNoteRestorationCaptureArtifact {
  factory TerminalNoteRestorationCaptureArtifact.fromArtifact({
    required TerminalNoteRestorationArtifact restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
  }) => TerminalNoteRestorationCaptureArtifact._(
    restoration: restoration,
    paneIdsInTraversalOrder: paneIdsInTraversalOrder,
  );

  TerminalNoteRestorationCaptureArtifact._({
    required this.restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
  }) : paneIdsInTraversalOrder = List<PaneId>.unmodifiable(
         paneIdsInTraversalOrder,
       ) {
    if (this.paneIdsInTraversalOrder.length != restoration.snapshot.paneCount ||
        this.paneIdsInTraversalOrder.toSet().length !=
            this.paneIdsInTraversalOrder.length) {
      throw StateError('restoration pane traversal is inconsistent');
    }
  }

  factory TerminalNoteRestorationCaptureArtifact.capture(
    TerminalApplicationState state, {
    required TerminalRestorationPlacementProvider placementForWindow,
    required TerminalRestorationWorkingDirectoryProvider
    workingDirectoryForPane,
  }) {
    final TerminalRestorationCaptureResult captured =
        TerminalApplicationRestorationCapture.captureWithTraversal(
          state,
          placementForWindow: placementForWindow,
          workingDirectoryForPane: workingDirectoryForPane,
        );
    return TerminalNoteRestorationCaptureArtifact._(
      restoration: TerminalNoteRestorationArtifact.fromSnapshot(
        captured.snapshot,
      ),
      paneIdsInTraversalOrder: captured.paneIdsInTraversalOrder,
    );
  }

  final TerminalNoteRestorationArtifact restoration;
  final List<PaneId> paneIdsInTraversalOrder;
}

enum TerminalNoteContextReconciliationDisposition { matched, fresh }

enum TerminalNoteContextFreshReason {
  restorationMissing,
  bindingMissing,
  hashMismatch,
  countMismatch,
  bindingStateMismatch,
}

enum TerminalNoteContextReconciliationFailure {
  invalidTraversal,
  invalidTimestamp,
  mutationRejected,
}

/// Fixed, content-free reconciliation failure.
final class TerminalNoteContextReconciliationException implements Exception {
  const TerminalNoteContextReconciliationException(this.failure);

  final TerminalNoteContextReconciliationFailure failure;

  @override
  String toString() =>
      'Terminal note context reconciliation failed: ${failure.name}';
}

/// Immutable runtime lookup from fresh pane IDs to durable Note contexts.
final class TerminalNoteContextBindings {
  TerminalNoteContextBindings({
    required Map<PaneId, TerminalNoteContextId> standardPaneContexts,
    required this.quickTerminalContextId,
  }) : standardPaneContexts = Map<PaneId, TerminalNoteContextId>.unmodifiable(
         standardPaneContexts,
       ) {
    if (this.standardPaneContexts.length >
            TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts ||
        this.standardPaneContexts.values.toSet().length !=
            this.standardPaneContexts.length ||
        (quickTerminalContextId != null &&
            this.standardPaneContexts.values.contains(
              quickTerminalContextId,
            ))) {
      throw const TerminalNoteContextReconciliationException(
        TerminalNoteContextReconciliationFailure.invalidTraversal,
      );
    }
  }

  final Map<PaneId, TerminalNoteContextId> standardPaneContexts;
  final TerminalNoteContextId? quickTerminalContextId;

  TerminalNoteContextId? contextForPane(PaneId paneId) =>
      standardPaneContexts[paneId];

  @override
  String toString() =>
      'TerminalNoteContextBindings('
      'standard=${standardPaneContexts.length}, '
      'quick=${quickTerminalContextId != null})';
}

final class TerminalNoteContextReconciliationResult {
  const TerminalNoteContextReconciliationResult({
    required this.document,
    required this.bindings,
    required this.disposition,
    required this.freshReason,
    required this.requiresCommit,
  });

  final TerminalNoteStoreDocument document;
  final TerminalNoteContextBindings bindings;
  final TerminalNoteContextReconciliationDisposition disposition;
  final TerminalNoteContextFreshReason? freshReason;
  final bool requiresCommit;
}

enum TerminalNoteShutdownPreparationFailure {
  invalidTraversal,
  invalidTimestamp,
  bindingMismatch,
  mutationRejected,
}

/// Fixed, content-free shutdown candidate failure.
final class TerminalNoteShutdownPreparationException implements Exception {
  const TerminalNoteShutdownPreparationException(this.failure);

  final TerminalNoteShutdownPreparationFailure failure;

  @override
  String toString() =>
      'Terminal note shutdown preparation failed: ${failure.name}';
}

/// Exact restoration bytes and the Note document that binds to those bytes.
final class TerminalNoteShutdownCandidate {
  const TerminalNoteShutdownCandidate({
    required this.restoration,
    required this.document,
    required this.requiresNoteCommit,
  });

  final TerminalNoteRestorationArtifact restoration;
  final TerminalNoteStoreDocument document;
  final bool requiresNoteCommit;

  @override
  String toString() =>
      'TerminalNoteShutdownCandidate('
      'panes=${restoration.snapshot.paneCount}, '
      'noteCommit=$requiresNoteCommit)';
}

/// Produces one fail-closed shutdown candidate without performing I/O.
final class TerminalNoteShutdownCandidateBuilder {
  const TerminalNoteShutdownCandidateBuilder();

  TerminalNoteShutdownCandidate prepare({
    required TerminalNoteStoreDocument stored,
    required TerminalNoteRestorationCaptureArtifact capture,
    required TerminalNoteContextBindings bindings,
    required int updatedAtUtcMicros,
  }) {
    if (updatedAtUtcMicros < 0 ||
        BigInt.from(updatedAtUtcMicros) >
            TerminalNoteLimits.maximumUnsigned64) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.invalidTimestamp,
      );
    }
    final List<PaneId> paneIds = capture.paneIdsInTraversalOrder;
    if (bindings.standardPaneContexts.length != paneIds.length ||
        !bindings.standardPaneContexts.keys.toSet().containsAll(paneIds)) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.invalidTraversal,
      );
    }
    final List<TerminalNoteContextId> contextIds = <TerminalNoteContextId>[];
    for (final PaneId paneId in paneIds) {
      final TerminalNoteContextId? contextId = bindings.contextForPane(paneId);
      final NoteContextRecord? context = contextId == null
          ? null
          : stored.snapshot.contextFor(contextId);
      if (contextId == null ||
          context == null ||
          context.kind != TerminalNoteContextKind.standard ||
          context.state == TerminalNoteContextState.detached) {
        throw const TerminalNoteShutdownPreparationException(
          TerminalNoteShutdownPreparationFailure.bindingMismatch,
        );
      }
      contextIds.add(contextId);
    }
    if (contextIds.toSet().length != contextIds.length) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.bindingMismatch,
      );
    }
    final TerminalNoteContextId? storedQuickContextId = stored
        .snapshot
        .contexts
        .values
        .where(
          (NoteContextRecord context) =>
              context.kind == TerminalNoteContextKind.quickTerminal,
        )
        .firstOrNull
        ?.id;
    if (storedQuickContextId != bindings.quickTerminalContextId) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.bindingMismatch,
      );
    }

    TerminalNoteSnapshot working = stored.snapshot;
    final int safeUpdatedAt = working.notes.values.fold<int>(
      updatedAtUtcMicros,
      (int current, NoteRecord note) =>
          note.updatedAtUtcMicros > current ? note.updatedAtUtcMicros : current,
    );
    final Set<TerminalNoteContextId> retainedIds = contextIds.toSet();
    final List<NoteContextRecord> existingStandard =
        working.contexts.values
            .where(
              (NoteContextRecord context) =>
                  context.kind == TerminalNoteContextKind.standard,
            )
            .toList()
          ..sort(
            (NoteContextRecord left, NoteContextRecord right) =>
                left.id.compareTo(right.id),
          );
    for (final NoteContextRecord original in existingStandard) {
      if (retainedIds.contains(original.id) ||
          original.state == TerminalNoteContextState.detached) {
        continue;
      }
      final NoteContextRecord current = working.contextFor(original.id)!;
      working = _acceptedShutdownSnapshot(
        working.detachContext(
          contextId: current.id,
          reason: TerminalNoteDetachReason.contextUnavailable,
          updatedAtUtcMicros: safeUpdatedAt,
          expectedStoreRevision: working.storeRevision,
          expectedContextRevision: current.revision,
        ),
      );
    }
    for (final TerminalNoteContextId contextId in contextIds) {
      final NoteContextRecord context = working.contextFor(contextId)!;
      if (context.state == TerminalNoteContextState.active) {
        working = _acceptedShutdownSnapshot(
          working.setContextState(
            contextId: contextId,
            state: TerminalNoteContextState.restorable,
            expectedStoreRevision: working.storeRevision,
            expectedContextRevision: context.revision,
          ),
        );
      }
    }
    final TerminalNoteRestorationBinding nextBinding =
        TerminalNoteRestorationBinding(
          restorationSha256: capture.restoration.restorationSha256,
          paneContextIds: contextIds,
        );
    final bool snapshotChanged =
        working.storeRevision != stored.snapshot.storeRevision;
    final bool bindingChanged = !_sameRestorationBinding(
      stored.restorationBinding,
      nextBinding,
    );
    if (bindingChanged && !snapshotChanged) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.mutationRejected,
      );
    }
    return TerminalNoteShutdownCandidate(
      restoration: capture.restoration,
      document: TerminalNoteStoreDocument(
        snapshot: working,
        restorationBinding: nextBinding,
      ),
      requiresNoteCommit: snapshotChanged || bindingChanged,
    );
  }

  static TerminalNoteSnapshot _acceptedShutdownSnapshot(
    TerminalNoteMutationResult result,
  ) {
    if (result.disposition == TerminalNoteMutationDisposition.rejected) {
      throw const TerminalNoteShutdownPreparationException(
        TerminalNoteShutdownPreparationFailure.mutationRejected,
      );
    }
    return result.snapshot;
  }
}

typedef TerminalNoteRestorationCommit = Future<bool> Function(
  TerminalNoteRestorationArtifact restoration,
);
typedef TerminalNoteDocumentCommit = Future<bool> Function(
  TerminalNoteStoreDocument document,
);

enum TerminalNoteOrderedPersistenceDisposition {
  committed,
  restorationCommitFailed,
  noteCommitFailed,
}

/// Content-free outcome for the restoration-first two-file commit sequence.
final class TerminalNoteOrderedPersistenceResult {
  const TerminalNoteOrderedPersistenceResult._({
    required this.disposition,
    required this.restorationCommitAcknowledged,
    required this.noteCommitAttempted,
    required this.noteCommitAcknowledged,
  });

  final TerminalNoteOrderedPersistenceDisposition disposition;
  final bool restorationCommitAcknowledged;
  final bool noteCommitAttempted;
  final bool noteCommitAcknowledged;

  bool get isSuccess =>
      disposition == TerminalNoteOrderedPersistenceDisposition.committed;

  @override
  String toString() =>
      'TerminalNoteOrderedPersistenceResult(${disposition.name})';
}

/// Commits exact restoration bytes before the Note document that binds them.
final class TerminalNoteOrderedPersistenceCoordinator {
  const TerminalNoteOrderedPersistenceCoordinator({
    required this.commitRestoration,
    required this.commitNoteDocument,
  });

  final TerminalNoteRestorationCommit commitRestoration;
  final TerminalNoteDocumentCommit commitNoteDocument;

  Future<TerminalNoteOrderedPersistenceResult> commit(
    TerminalNoteShutdownCandidate candidate,
  ) async {
    try {
      if (!await commitRestoration(candidate.restoration)) {
        return const TerminalNoteOrderedPersistenceResult._(
          disposition:
              TerminalNoteOrderedPersistenceDisposition.restorationCommitFailed,
          restorationCommitAcknowledged: false,
          noteCommitAttempted: false,
          noteCommitAcknowledged: false,
        );
      }
    } on Object {
      return const TerminalNoteOrderedPersistenceResult._(
        disposition:
            TerminalNoteOrderedPersistenceDisposition.restorationCommitFailed,
        restorationCommitAcknowledged: false,
        noteCommitAttempted: false,
        noteCommitAcknowledged: false,
      );
    }
    if (!candidate.requiresNoteCommit) {
      return const TerminalNoteOrderedPersistenceResult._(
        disposition: TerminalNoteOrderedPersistenceDisposition.committed,
        restorationCommitAcknowledged: true,
        noteCommitAttempted: false,
        noteCommitAcknowledged: false,
      );
    }
    try {
      if (await commitNoteDocument(candidate.document)) {
        return const TerminalNoteOrderedPersistenceResult._(
          disposition: TerminalNoteOrderedPersistenceDisposition.committed,
          restorationCommitAcknowledged: true,
          noteCommitAttempted: true,
          noteCommitAcknowledged: true,
        );
      }
    } on Object {
      // Failure classification is intentionally content-free.
    }
    return const TerminalNoteOrderedPersistenceResult._(
      disposition: TerminalNoteOrderedPersistenceDisposition.noteCommitFailed,
      restorationCommitAcknowledged: true,
      noteCommitAttempted: true,
      noteCommitAcknowledged: false,
    );
  }
}

/// Produces one all-or-nothing startup reconciliation candidate without I/O.
final class TerminalNoteContextReconciler {
  const TerminalNoteContextReconciler(this.idGenerator);

  final TerminalNoteContextIdGenerator idGenerator;

  TerminalNoteContextReconciliationResult reconcile({
    required TerminalNoteStoreDocument stored,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
    required bool ensureQuickTerminalContext,
    required int updatedAtUtcMicros,
  }) {
    if (updatedAtUtcMicros < 0 ||
        BigInt.from(updatedAtUtcMicros) >
            TerminalNoteLimits.maximumUnsigned64) {
      throw const TerminalNoteContextReconciliationException(
        TerminalNoteContextReconciliationFailure.invalidTimestamp,
      );
    }
    final List<PaneId> paneIds = paneIdsInTraversalOrder.toList(
      growable: false,
    );
    if (paneIds.length >
            TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts ||
        paneIds.toSet().length != paneIds.length ||
        (restoration != null &&
            restoration.snapshot.paneCount != paneIds.length)) {
      throw const TerminalNoteContextReconciliationException(
        TerminalNoteContextReconciliationFailure.invalidTraversal,
      );
    }

    final _TerminalNoteBindingDecision decision = _decideBinding(
      stored,
      restoration,
      paneIds.length,
    );
    TerminalNoteSnapshot working = stored.snapshot;
    final int safeUpdatedAt = working.notes.values.fold<int>(
      updatedAtUtcMicros,
      (int current, NoteRecord note) =>
          note.updatedAtUtcMicros > current ? note.updatedAtUtcMicros : current,
    );
    final Set<TerminalNoteContextId> attachedIds = decision.matched
        ? decision.contextIds.toSet()
        : const <TerminalNoteContextId>{};
    final List<NoteContextRecord> existingStandard =
        working.contexts.values
            .where(
              (NoteContextRecord context) =>
                  context.kind == TerminalNoteContextKind.standard,
            )
            .toList()
          ..sort(
            (NoteContextRecord left, NoteContextRecord right) =>
                left.id.compareTo(right.id),
          );
    for (final NoteContextRecord original in existingStandard) {
      if (attachedIds.contains(original.id) ||
          original.state == TerminalNoteContextState.detached) {
        continue;
      }
      final NoteContextRecord current = working.contextFor(original.id)!;
      working = _acceptedSnapshot(
        working.detachContext(
          contextId: current.id,
          reason: decision.matched
              ? TerminalNoteDetachReason.contextUnavailable
              : TerminalNoteDetachReason.restorationMismatch,
          updatedAtUtcMicros: safeUpdatedAt,
          expectedStoreRevision: working.storeRevision,
          expectedContextRevision: current.revision,
        ),
      );
    }

    final List<TerminalNoteContextId> orderedContextIds =
        <TerminalNoteContextId>[];
    if (decision.matched) {
      for (final TerminalNoteContextId id in decision.contextIds) {
        final NoteContextRecord context = working.contextFor(id)!;
        if (context.state == TerminalNoteContextState.restorable) {
          working = _acceptedSnapshot(
            working.setContextState(
              contextId: id,
              state: TerminalNoteContextState.active,
              expectedStoreRevision: working.storeRevision,
              expectedContextRevision: context.revision,
            ),
          );
        }
        orderedContextIds.add(id);
      }
    } else {
      for (var index = 0; index < paneIds.length; index++) {
        final TerminalNoteContextId id = idGenerator.next(
          excluding: working.contexts.keys,
        );
        working = _acceptedSnapshot(
          working.createContext(
            id: id,
            kind: TerminalNoteContextKind.standard,
            expectedStoreRevision: working.storeRevision,
          ),
        );
        orderedContextIds.add(id);
      }
    }

    TerminalNoteContextId? quickTerminalContextId = working.contexts.values
        .where(
          (NoteContextRecord context) =>
              context.kind == TerminalNoteContextKind.quickTerminal,
        )
        .firstOrNull
        ?.id;
    if (ensureQuickTerminalContext && quickTerminalContextId == null) {
      quickTerminalContextId = idGenerator.next(
        excluding: working.contexts.keys,
      );
      working = _acceptedSnapshot(
        working.createContext(
          id: quickTerminalContextId,
          kind: TerminalNoteContextKind.quickTerminal,
          expectedStoreRevision: working.storeRevision,
        ),
      );
    }

    final Map<PaneId, TerminalNoteContextId> standardPaneContexts =
        <PaneId, TerminalNoteContextId>{};
    for (var index = 0; index < paneIds.length; index++) {
      standardPaneContexts[paneIds[index]] = orderedContextIds[index];
    }
    final TerminalNoteRestorationBinding? nextBinding = restoration == null
        ? null
        : TerminalNoteRestorationBinding(
            restorationSha256: restoration.restorationSha256,
            paneContextIds: orderedContextIds,
          );
    final TerminalNoteStoreDocument document = TerminalNoteStoreDocument(
      snapshot: working,
      restorationBinding: nextBinding,
    );
    return TerminalNoteContextReconciliationResult(
      document: document,
      bindings: TerminalNoteContextBindings(
        standardPaneContexts: standardPaneContexts,
        quickTerminalContextId: quickTerminalContextId,
      ),
      disposition: decision.matched
          ? TerminalNoteContextReconciliationDisposition.matched
          : TerminalNoteContextReconciliationDisposition.fresh,
      freshReason: decision.freshReason,
      requiresCommit:
          working.storeRevision != stored.snapshot.storeRevision ||
          !_sameRestorationBinding(stored.restorationBinding, nextBinding),
    );
  }

  static _TerminalNoteBindingDecision _decideBinding(
    TerminalNoteStoreDocument stored,
    TerminalNoteRestorationArtifact? restoration,
    int paneCount,
  ) {
    if (restoration == null) {
      return const _TerminalNoteBindingDecision.fresh(
        TerminalNoteContextFreshReason.restorationMissing,
      );
    }
    final TerminalNoteRestorationBinding? binding = stored.restorationBinding;
    if (binding == null) {
      return const _TerminalNoteBindingDecision.fresh(
        TerminalNoteContextFreshReason.bindingMissing,
      );
    }
    if (binding.restorationSha256 != restoration.restorationSha256) {
      return const _TerminalNoteBindingDecision.fresh(
        TerminalNoteContextFreshReason.hashMismatch,
      );
    }
    if (binding.paneContextIds.length != paneCount) {
      return const _TerminalNoteBindingDecision.fresh(
        TerminalNoteContextFreshReason.countMismatch,
      );
    }
    for (final TerminalNoteContextId id in binding.paneContextIds) {
      final NoteContextRecord? context = stored.snapshot.contextFor(id);
      if (context == null ||
          context.kind != TerminalNoteContextKind.standard ||
          context.state == TerminalNoteContextState.detached) {
        return const _TerminalNoteBindingDecision.fresh(
          TerminalNoteContextFreshReason.bindingStateMismatch,
        );
      }
    }
    return _TerminalNoteBindingDecision.matched(binding.paneContextIds);
  }

  static TerminalNoteSnapshot _acceptedSnapshot(
    TerminalNoteMutationResult result,
  ) {
    if (result.disposition == TerminalNoteMutationDisposition.rejected) {
      throw const TerminalNoteContextReconciliationException(
        TerminalNoteContextReconciliationFailure.mutationRejected,
      );
    }
    return result.snapshot;
  }
}

bool _sameRestorationBinding(
  TerminalNoteRestorationBinding? left,
  TerminalNoteRestorationBinding? right,
) {
  if (left == null || right == null) return left == null && right == null;
  if (left.restorationSha256 != right.restorationSha256 ||
      left.paneContextIds.length != right.paneContextIds.length) {
    return false;
  }
  for (var index = 0; index < left.paneContextIds.length; index++) {
    if (left.paneContextIds[index] != right.paneContextIds[index]) return false;
  }
  return true;
}

final class _TerminalNoteBindingDecision {
  const _TerminalNoteBindingDecision.matched(
    List<TerminalNoteContextId> contextIds,
  ) : matched = true,
      contextIds = contextIds,
      freshReason = null;

  const _TerminalNoteBindingDecision.fresh(this.freshReason)
    : matched = false,
      contextIds = const <TerminalNoteContextId>[];

  final bool matched;
  final List<TerminalNoteContextId> contextIds;
  final TerminalNoteContextFreshReason? freshReason;
}
