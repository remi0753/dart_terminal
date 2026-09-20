import 'dart:collection';
import 'dart:convert';

/// Hard bounds shared by the pure Note model and its future codecs.
abstract final class TerminalNoteLimits {
  static const int maximumNotes = 2048;
  static const int maximumNotesPerAttachedContext = 128;
  static const int maximumContexts = 4096;
  static const int maximumTriggers = 2048;
  static const int maximumDeliveries = 2048;
  static const int maximumBodyUtf8Bytes = 4096;
  static const int maximumBodyLines = 64;
  static const int maximumAggregateBodyUtf8Bytes = 8 * 1024 * 1024;
  static const int maximumPromptEventsPerBatch = 32;
  static const int maximumCoalescedFocusEdges = 2;
  static final BigInt maximumUnsigned64 = (BigInt.one << 64) - BigInt.one;
}

enum TerminalNoteValidationFailure {
  invalidId,
  invalidBody,
  invalidCounter,
  invalidTimestamp,
  invalidRecord,
  invariantViolation,
}

/// A privacy-safe validation error which never echoes content or identity.
final class TerminalNoteValidationException implements Exception {
  const TerminalNoteValidationException(this.failure);

  final TerminalNoteValidationFailure failure;

  @override
  String toString() => 'Terminal note validation failed: ${failure.name}';
}

bool _isCanonicalOpaqueId(String value) {
  if (value.length != 32) return false;
  for (final int unit in value.codeUnits) {
    final bool digit = unit >= 0x30 && unit <= 0x39;
    final bool lowerHex = unit >= 0x61 && unit <= 0x66;
    if (!digit && !lowerHex) return false;
  }
  return true;
}

/// Persistent opaque identity for a Note.
final class NoteId implements Comparable<NoteId> {
  factory NoteId.fromHex(String value) {
    if (!_isCanonicalOpaqueId(value)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidId,
      );
    }
    return NoteId._(value);
  }

  const NoteId._(this._canonicalValue);

  final String _canonicalValue;

  /// Explicit codec boundary. Do not use for diagnostics or presentation.
  String get canonicalValue => _canonicalValue;

  @override
  int compareTo(NoteId other) =>
      _canonicalValue.compareTo(other._canonicalValue);

  @override
  bool operator ==(Object other) =>
      other is NoteId && other._canonicalValue == _canonicalValue;

  @override
  int get hashCode => _canonicalValue.hashCode;

  @override
  String toString() => 'NoteId(<redacted>)';
}

/// Persistent opaque identity for one logical terminal context.
final class TerminalNoteContextId implements Comparable<TerminalNoteContextId> {
  factory TerminalNoteContextId.fromHex(String value) {
    if (!_isCanonicalOpaqueId(value)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidId,
      );
    }
    return TerminalNoteContextId._(value);
  }

  const TerminalNoteContextId._(this._canonicalValue);

  final String _canonicalValue;

  /// Explicit codec boundary. Do not use for diagnostics or presentation.
  String get canonicalValue => _canonicalValue;

  @override
  int compareTo(TerminalNoteContextId other) =>
      _canonicalValue.compareTo(other._canonicalValue);

  @override
  bool operator ==(Object other) =>
      other is TerminalNoteContextId &&
      other._canonicalValue == _canonicalValue;

  @override
  int get hashCode => _canonicalValue.hashCode;

  @override
  String toString() => 'TerminalNoteContextId(<redacted>)';
}

/// Memory-only correlation identity for one shell integration instance.
final class ShellIntegrationInstanceId
    implements Comparable<ShellIntegrationInstanceId> {
  factory ShellIntegrationInstanceId.fromHex(String value) {
    if (!_isCanonicalOpaqueId(value)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidId,
      );
    }
    return ShellIntegrationInstanceId._(value);
  }

  const ShellIntegrationInstanceId._(this._canonicalValue);

  final String _canonicalValue;

  String get canonicalValue => _canonicalValue;

  @override
  int compareTo(ShellIntegrationInstanceId other) =>
      _canonicalValue.compareTo(other._canonicalValue);

  @override
  bool operator ==(Object other) =>
      other is ShellIntegrationInstanceId &&
      other._canonicalValue == _canonicalValue;

  @override
  int get hashCode => _canonicalValue.hashCode;

  @override
  String toString() => 'ShellIntegrationInstanceId(<redacted>)';
}

/// Validated, normalized, bounded Note plain text.
final class NoteBody {
  factory NoteBody.fromText(String text) {
    final String normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (!_hasValidSurrogates(normalized)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidBody,
      );
    }
    var hasNonWhitespace = false;
    var lineCount = 1;
    for (final int scalar in normalized.runes) {
      if (scalar == 0x0a) ++lineCount;
      final bool allowedSpacingControl = scalar == 0x09 || scalar == 0x0a;
      final bool forbiddenControl =
          (scalar <= 0x1f || (scalar >= 0x7f && scalar <= 0x9f)) &&
          !allowedSpacingControl;
      final bool forbiddenBidi =
          scalar == 0x200e ||
          scalar == 0x200f ||
          (scalar >= 0x202a && scalar <= 0x202e) ||
          (scalar >= 0x2066 && scalar <= 0x2069);
      if (forbiddenControl || forbiddenBidi) {
        throw const TerminalNoteValidationException(
          TerminalNoteValidationFailure.invalidBody,
        );
      }
      if (!_isUnicodeWhitespace(scalar)) hasNonWhitespace = true;
    }
    final int utf8Length = utf8.encode(normalized).length;
    if (!hasNonWhitespace ||
        utf8Length < 1 ||
        utf8Length > TerminalNoteLimits.maximumBodyUtf8Bytes ||
        lineCount > TerminalNoteLimits.maximumBodyLines) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidBody,
      );
    }
    return NoteBody._(normalized, utf8Length, lineCount);
  }

  const NoteBody._(this.value, this.utf8Length, this.lineCount);

  final String value;
  final int utf8Length;
  final int lineCount;

  @override
  bool operator ==(Object other) => other is NoteBody && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NoteBody(<redacted>)';

  static bool _hasValidSurrogates(String value) {
    for (var index = 0; index < value.length; index++) {
      final int unit = value.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index >= value.length) return false;
        final int low = value.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  static bool _isUnicodeWhitespace(int scalar) =>
      (scalar >= 0x09 && scalar <= 0x0d) ||
      scalar == 0x20 ||
      scalar == 0x85 ||
      scalar == 0xa0 ||
      scalar == 0x1680 ||
      (scalar >= 0x2000 && scalar <= 0x200a) ||
      scalar == 0x2028 ||
      scalar == 0x2029 ||
      scalar == 0x202f ||
      scalar == 0x205f ||
      scalar == 0x3000;
}

enum NoteColorKey { neutral, yellow, blue, green, pink, purple }

enum NoteStatus { active, resolved }

enum TerminalNoteContextKind { standard, quickTerminal }

enum TerminalNoteContextState { active, restorable, detached }

enum TerminalNoteDetachReason {
  paneClosed,
  restorationMismatch,
  contextUnavailable,
  explicitDetach,
}

enum TerminalNoteAttachmentKind { attached, detached }

/// Exactly-one attachment variant for a Note.
final class TerminalNoteAttachment {
  const TerminalNoteAttachment.attached(TerminalNoteContextId contextId)
    : kind = TerminalNoteAttachmentKind.attached,
      contextId = contextId,
      previousContextId = null,
      detachReason = null;

  const TerminalNoteAttachment.detached({
    required TerminalNoteContextId previousContextId,
    required TerminalNoteDetachReason reason,
  }) : kind = TerminalNoteAttachmentKind.detached,
       contextId = null,
       previousContextId = previousContextId,
       detachReason = reason;

  final TerminalNoteAttachmentKind kind;
  final TerminalNoteContextId? contextId;
  final TerminalNoteContextId? previousContextId;
  final TerminalNoteDetachReason? detachReason;

  bool get isAttached => kind == TerminalNoteAttachmentKind.attached;
  bool get isDetached => kind == TerminalNoteAttachmentKind.detached;

  @override
  bool operator ==(Object other) =>
      other is TerminalNoteAttachment &&
      other.kind == kind &&
      other.contextId == contextId &&
      other.previousContextId == previousContextId &&
      other.detachReason == detachReason;

  @override
  int get hashCode =>
      Object.hash(kind, contextId, previousContextId, detachReason);
}

final class NoteRecord {
  NoteRecord({
    required this.id,
    required this.attachment,
    required this.body,
    required this.color,
    required this.status,
    required this.order,
    required this.createdAtUtcMicros,
    required this.updatedAtUtcMicros,
    required this.revision,
  }) {
    _validateBoundedInt(order, allowZero: true);
    _validateBoundedInt(createdAtUtcMicros, allowZero: true);
    _validateBoundedInt(updatedAtUtcMicros, allowZero: true);
    _validateCounter(revision);
    if (updatedAtUtcMicros < createdAtUtcMicros) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidTimestamp,
      );
    }
  }

  final NoteId id;
  final TerminalNoteAttachment attachment;
  final NoteBody body;
  final NoteColorKey color;
  final NoteStatus status;
  final int order;
  final int createdAtUtcMicros;
  final int updatedAtUtcMicros;
  final BigInt revision;

  NoteRecord copyWith({
    TerminalNoteAttachment? attachment,
    NoteBody? body,
    NoteColorKey? color,
    NoteStatus? status,
    int? order,
    int? updatedAtUtcMicros,
    BigInt? revision,
  }) => NoteRecord(
    id: id,
    attachment: attachment ?? this.attachment,
    body: body ?? this.body,
    color: color ?? this.color,
    status: status ?? this.status,
    order: order ?? this.order,
    createdAtUtcMicros: createdAtUtcMicros,
    updatedAtUtcMicros: updatedAtUtcMicros ?? this.updatedAtUtcMicros,
    revision: revision ?? this.revision,
  );
}

final class NoteContextRecord {
  NoteContextRecord({
    required this.id,
    required this.kind,
    required this.state,
    required this.revision,
  }) {
    _validateCounter(revision);
  }

  final TerminalNoteContextId id;
  final TerminalNoteContextKind kind;
  final TerminalNoteContextState state;
  final BigInt revision;

  NoteContextRecord copyWith({
    TerminalNoteContextState? state,
    BigInt? revision,
  }) => NoteContextRecord(
    id: id,
    kind: kind,
    state: state ?? this.state,
    revision: revision ?? this.revision,
  );
}

enum NoteTriggerKind { onReturn, atNextPrompt }

enum NoteTriggerPhase {
  onReturnArmedHere,
  onReturnArmedAway,
  atNextPromptWaitingCommand,
  atNextPromptWaitingEnd,
  atNextPromptWaitingPromptStart,
  atNextPromptWaitingInput,
  due,
  suspended,
}

enum NoteTriggerSuspendReason {
  sessionEnded,
  instanceChanged,
  semanticReset,
  adapterDisabled,
  versionMismatch,
  eventOverflow,
}

final class NoteTriggerRecord {
  NoteTriggerRecord({
    required this.noteId,
    required this.generation,
    required this.kind,
    required this.phase,
    required this.suspendReason,
    required this.armedAtRevision,
  }) {
    _validateCounter(generation);
    _validateCounter(armedAtRevision);
    if (!_phaseMatchesKind(kind, phase) ||
        (phase == NoteTriggerPhase.suspended) != (suspendReason != null)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidRecord,
      );
    }
  }

  final NoteId noteId;
  final BigInt generation;
  final NoteTriggerKind kind;
  final NoteTriggerPhase phase;
  final NoteTriggerSuspendReason? suspendReason;
  final BigInt armedAtRevision;

  NoteTriggerRecord copyWith({
    NoteTriggerPhase? phase,
    NoteTriggerSuspendReason? suspendReason,
    bool clearSuspendReason = false,
  }) => NoteTriggerRecord(
    noteId: noteId,
    generation: generation,
    kind: kind,
    phase: phase ?? this.phase,
    suspendReason: clearSuspendReason
        ? null
        : suspendReason ?? this.suspendReason,
    armedAtRevision: armedAtRevision,
  );

  static bool _phaseMatchesKind(NoteTriggerKind kind, NoteTriggerPhase phase) =>
      switch (kind) {
        NoteTriggerKind.onReturn =>
          phase == NoteTriggerPhase.onReturnArmedHere ||
              phase == NoteTriggerPhase.onReturnArmedAway ||
              phase == NoteTriggerPhase.due,
        NoteTriggerKind.atNextPrompt =>
          phase == NoteTriggerPhase.atNextPromptWaitingCommand ||
              phase == NoteTriggerPhase.atNextPromptWaitingEnd ||
              phase == NoteTriggerPhase.atNextPromptWaitingPromptStart ||
              phase == NoteTriggerPhase.atNextPromptWaitingInput ||
              phase == NoteTriggerPhase.due ||
              phase == NoteTriggerPhase.suspended,
      };
}

final class DeliverySequence implements Comparable<DeliverySequence> {
  DeliverySequence(this.value) {
    _validateCounter(value);
  }

  final BigInt value;

  @override
  int compareTo(DeliverySequence other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is DeliverySequence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DeliverySequence(<redacted>)';
}

final class NoteDeliveryRecord {
  NoteDeliveryRecord({
    required this.noteId,
    required this.triggerGeneration,
    required this.sequence,
  }) {
    _validateCounter(triggerGeneration);
  }

  final NoteId noteId;
  final BigInt triggerGeneration;
  final DeliverySequence sequence;
}

enum TerminalNotePromptCapability { available, probing, suspended, unavailable }

enum TerminalNoteSemanticState { prompt, input, commandOutput, unknown }

/// Memory-only binding which prevents S3 transfer across shell generations.
final class NoteTriggerRuntimeBinding {
  NoteTriggerRuntimeBinding({
    required this.sessionGeneration,
    required this.instanceId,
    required this.semanticGeneration,
    required this.lastEventSequence,
  }) {
    _validateCounter(sessionGeneration);
    _validateCounter(semanticGeneration);
    _validateCounter(lastEventSequence, allowZero: true);
  }

  final BigInt sessionGeneration;
  final ShellIntegrationInstanceId instanceId;
  final BigInt semanticGeneration;
  final BigInt lastEventSequence;

  NoteTriggerRuntimeBinding copyWith({required BigInt lastEventSequence}) =>
      NoteTriggerRuntimeBinding(
        sessionGeneration: sessionGeneration,
        instanceId: instanceId,
        semanticGeneration: semanticGeneration,
        lastEventSequence: lastEventSequence,
      );

  bool matches(NoteTriggerRuntimeBinding other) =>
      sessionGeneration == other.sessionGeneration &&
      instanceId == other.instanceId &&
      semanticGeneration == other.semanticGeneration;
}

enum TerminalNotePromptAction {
  commandOutputBegins,
  commandEnds,
  promptBegins,
  freshPromptBegins,
  primaryInputReady,
  secondaryPrompt,
  inputLineEnds,
}

final class TerminalNotePromptEvent {
  TerminalNotePromptEvent({required this.sequence, required this.action}) {
    _validateCounter(sequence);
  }

  final BigInt sequence;
  final TerminalNotePromptAction action;
}

enum TerminalNoteMutationDisposition {
  accepted,
  runtimeOnly,
  noChange,
  rejected,
}

enum TerminalNoteMutationFailure {
  invalidInput,
  revisionConflict,
  noteNotFound,
  contextNotFound,
  invalidState,
  capacityExceeded,
  counterExhausted,
  capabilityUnavailable,
}

/// Mutation outcome with fixed, content-free diagnostics.
final class TerminalNoteMutationResult {
  const TerminalNoteMutationResult._({
    required this.snapshot,
    required this.disposition,
    required this.failure,
  });

  final TerminalNoteSnapshot snapshot;
  final TerminalNoteMutationDisposition disposition;
  final TerminalNoteMutationFailure? failure;

  bool get isAccepted =>
      disposition == TerminalNoteMutationDisposition.accepted ||
      disposition == TerminalNoteMutationDisposition.runtimeOnly;

  @override
  String toString() => failure == null
      ? 'TerminalNoteMutationResult(${disposition.name})'
      : 'TerminalNoteMutationResult(${disposition.name}, ${failure!.name})';
}

/// Deterministic context projection; UI protocols replace persistent IDs later.
final class TerminalNoteContextProjection {
  TerminalNoteContextProjection({
    required this.contextId,
    required this.activeCount,
    required this.dueCount,
    required Iterable<NoteRecord> orderedNotes,
  }) : orderedNotes = List<NoteRecord>.unmodifiable(orderedNotes);

  final TerminalNoteContextId contextId;
  final int activeCount;
  final int dueCount;
  final List<NoteRecord> orderedNotes;
}

/// Immutable in-memory truth for persistent records and memory-only S3 binding.
final class TerminalNoteSnapshot {
  factory TerminalNoteSnapshot.empty() => TerminalNoteSnapshot._(
    storeRevision: BigInt.zero,
    nextDeliverySequence: BigInt.one,
    contexts: const <TerminalNoteContextId, NoteContextRecord>{},
    notes: const <NoteId, NoteRecord>{},
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
    runtimeBindings: const <NoteId, NoteTriggerRuntimeBinding>{},
  );

  /// Builds a fully validated snapshot for strict codecs and bounded fixtures.
  factory TerminalNoteSnapshot.fromRecords({
    required BigInt storeRevision,
    required BigInt nextDeliverySequence,
    required Map<TerminalNoteContextId, NoteContextRecord> contexts,
    required Map<NoteId, NoteRecord> notes,
    required Map<NoteId, NoteTriggerRecord> triggers,
    required Map<NoteId, NoteDeliveryRecord> deliveries,
    Map<NoteId, NoteTriggerRuntimeBinding> runtimeBindings =
        const <NoteId, NoteTriggerRuntimeBinding>{},
  }) => TerminalNoteSnapshot._(
    storeRevision: storeRevision,
    nextDeliverySequence: nextDeliverySequence,
    contexts: contexts,
    notes: notes,
    triggers: triggers,
    deliveries: deliveries,
    runtimeBindings: runtimeBindings,
  );

  TerminalNoteSnapshot._({
    required this.storeRevision,
    required this.nextDeliverySequence,
    required Map<TerminalNoteContextId, NoteContextRecord> contexts,
    required Map<NoteId, NoteRecord> notes,
    required Map<NoteId, NoteTriggerRecord> triggers,
    required Map<NoteId, NoteDeliveryRecord> deliveries,
    required Map<NoteId, NoteTriggerRuntimeBinding> runtimeBindings,
  }) : contexts = UnmodifiableMapView<TerminalNoteContextId, NoteContextRecord>(
         Map<TerminalNoteContextId, NoteContextRecord>.of(contexts),
       ),
       notes = UnmodifiableMapView<NoteId, NoteRecord>(
         Map<NoteId, NoteRecord>.of(notes),
       ),
       triggers = UnmodifiableMapView<NoteId, NoteTriggerRecord>(
         Map<NoteId, NoteTriggerRecord>.of(triggers),
       ),
       deliveries = UnmodifiableMapView<NoteId, NoteDeliveryRecord>(
         Map<NoteId, NoteDeliveryRecord>.of(deliveries),
       ),
       _runtimeBindings =
           UnmodifiableMapView<NoteId, NoteTriggerRuntimeBinding>(
             Map<NoteId, NoteTriggerRuntimeBinding>.of(runtimeBindings),
           ) {
    validate();
  }

  final BigInt storeRevision;
  final BigInt nextDeliverySequence;
  final Map<TerminalNoteContextId, NoteContextRecord> contexts;
  final Map<NoteId, NoteRecord> notes;
  final Map<NoteId, NoteTriggerRecord> triggers;
  final Map<NoteId, NoteDeliveryRecord> deliveries;
  final Map<NoteId, NoteTriggerRuntimeBinding> _runtimeBindings;

  int get aggregateBodyUtf8Bytes => notes.values.fold<int>(
    0,
    (int total, NoteRecord note) => total + note.body.utf8Length,
  );

  NoteRecord? noteFor(NoteId id) => notes[id];
  NoteContextRecord? contextFor(TerminalNoteContextId id) => contexts[id];
  NoteTriggerRecord? triggerFor(NoteId id) => triggers[id];
  NoteDeliveryRecord? deliveryFor(NoteId id) => deliveries[id];
  NoteTriggerRuntimeBinding? runtimeBindingFor(NoteId id) =>
      _runtimeBindings[id];

  TerminalNoteMutationResult createContext({
    required TerminalNoteContextId id,
    required TerminalNoteContextKind kind,
    TerminalNoteContextState state = TerminalNoteContextState.active,
    required BigInt expectedStoreRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    if (contexts.containsKey(id)) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (kind == TerminalNoteContextKind.quickTerminal &&
        (state != TerminalNoteContextState.active ||
            contexts.values.any(
              (NoteContextRecord context) =>
                  context.kind == TerminalNoteContextKind.quickTerminal,
            ))) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (contexts.length >= TerminalNoteLimits.maximumContexts) {
      return _reject(TerminalNoteMutationFailure.capacityExceeded);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<TerminalNoteContextId, NoteContextRecord> next =
        Map<TerminalNoteContextId, NoteContextRecord>.of(contexts)
          ..[id] = NoteContextRecord(
            id: id,
            kind: kind,
            state: state,
            revision: BigInt.one,
          );
    return _accepted(_copy(storeRevision: revision, contexts: next));
  }

  TerminalNoteMutationResult setContextState({
    required TerminalNoteContextId contextId,
    required TerminalNoteContextState state,
    required BigInt expectedStoreRevision,
    required BigInt expectedContextRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final NoteContextRecord? context = contexts[contextId];
    if (context == null) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    if (context.revision != expectedContextRevision) {
      return _reject(TerminalNoteMutationFailure.revisionConflict);
    }
    if (context.kind == TerminalNoteContextKind.quickTerminal &&
        state != TerminalNoteContextState.active) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (context.state == state) return _noChange;
    if (state == TerminalNoteContextState.detached ||
        context.state == TerminalNoteContextState.detached) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    final BigInt? store = _nextStoreRevision;
    if (store == null ||
        context.revision == TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<TerminalNoteContextId, NoteContextRecord> next =
        Map<TerminalNoteContextId, NoteContextRecord>.of(contexts)
          ..[contextId] = context.copyWith(
            state: state,
            revision: context.revision + BigInt.one,
          );
    return _accepted(_copy(storeRevision: store, contexts: next));
  }

  TerminalNoteMutationResult createNote({
    required NoteId id,
    required TerminalNoteContextId contextId,
    required String body,
    required NoteColorKey color,
    required int utcMicros,
    required BigInt expectedStoreRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final NoteContextRecord? context = contexts[contextId];
    if (context == null) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    if (context.state != TerminalNoteContextState.active ||
        notes.containsKey(id)) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    NoteBody noteBody;
    try {
      noteBody = NoteBody.fromText(body);
      _validateBoundedInt(utcMicros, allowZero: true);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    if (notes.length >= TerminalNoteLimits.maximumNotes ||
        _attachedNoteCount(contextId) >=
            TerminalNoteLimits.maximumNotesPerAttachedContext ||
        aggregateBodyUtf8Bytes + noteBody.utf8Length >
            TerminalNoteLimits.maximumAggregateBodyUtf8Bytes) {
      return _reject(TerminalNoteMutationFailure.capacityExceeded);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> next = Map<NoteId, NoteRecord>.of(notes)
      ..[id] = NoteRecord(
        id: id,
        attachment: TerminalNoteAttachment.attached(contextId),
        body: noteBody,
        color: color,
        status: NoteStatus.active,
        order: _attachedNoteCount(contextId),
        createdAtUtcMicros: utcMicros,
        updatedAtUtcMicros: utcMicros,
        revision: BigInt.one,
      );
    return _accepted(_copy(storeRevision: revision, notes: next));
  }

  TerminalNoteMutationResult editNote({
    required NoteId noteId,
    required String body,
    required NoteColorKey color,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    final NoteRecord note = check.note!;
    NoteBody nextBody;
    try {
      nextBody = NoteBody.fromText(body);
      _validateUpdateTime(note, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    if (note.body == nextBody && note.color == color) return _noChange;
    if (aggregateBodyUtf8Bytes - note.body.utf8Length + nextBody.utf8Length >
        TerminalNoteLimits.maximumAggregateBodyUtf8Bytes) {
      return _reject(TerminalNoteMutationFailure.capacityExceeded);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null ||
        note.revision == TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> next = Map<NoteId, NoteRecord>.of(notes)
      ..[noteId] = note.copyWith(
        body: nextBody,
        color: color,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    return _accepted(_copy(storeRevision: revision, notes: next));
  }

  TerminalNoteMutationResult resolveNote({
    required NoteId noteId,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) => _setNoteStatus(
    noteId: noteId,
    status: NoteStatus.resolved,
    updatedAtUtcMicros: updatedAtUtcMicros,
    expectedStoreRevision: expectedStoreRevision,
    expectedNoteRevision: expectedNoteRevision,
  );

  TerminalNoteMutationResult reopenNote({
    required NoteId noteId,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) => _setNoteStatus(
    noteId: noteId,
    status: NoteStatus.active,
    updatedAtUtcMicros: updatedAtUtcMicros,
    expectedStoreRevision: expectedStoreRevision,
    expectedNoteRevision: expectedNoteRevision,
  );

  TerminalNoteMutationResult _setNoteStatus({
    required NoteId noteId,
    required NoteStatus status,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    final NoteRecord note = check.note!;
    try {
      _validateUpdateTime(note, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    if (note.status == status) return _noChange;
    final BigInt? revision = _nextStoreRevision;
    if (revision == null ||
        note.revision == TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> nextNotes = Map<NoteId, NoteRecord>.of(notes)
      ..[noteId] = note.copyWith(
        status: status,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers);
    final Map<NoteId, NoteDeliveryRecord> nextDeliveries =
        Map<NoteId, NoteDeliveryRecord>.of(deliveries);
    final Map<NoteId, NoteTriggerRuntimeBinding> nextRuntime =
        Map<NoteId, NoteTriggerRuntimeBinding>.of(_runtimeBindings);
    if (status == NoteStatus.resolved) {
      nextTriggers.remove(noteId);
      nextDeliveries.remove(noteId);
      nextRuntime.remove(noteId);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        notes: nextNotes,
        triggers: nextTriggers,
        deliveries: nextDeliveries,
        runtimeBindings: nextRuntime,
      ),
    );
  }

  TerminalNoteMutationResult deleteNote({
    required NoteId noteId,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    final NoteRecord note = check.note!;
    try {
      _validateUpdateTime(note, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> nextNotes = Map<NoteId, NoteRecord>.of(notes)
      ..remove(noteId);
    try {
      _normalizeOrders(nextNotes, note.attachment, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    } on _TerminalNoteCounterExhausted {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        notes: nextNotes,
        triggers: Map<NoteId, NoteTriggerRecord>.of(triggers)..remove(noteId),
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..remove(noteId),
      ),
    );
  }

  TerminalNoteMutationResult detachNote({
    required NoteId noteId,
    required TerminalNoteDetachReason reason,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    final NoteRecord note = check.note!;
    if (note.attachment.isDetached) return _noChange;
    try {
      _validateUpdateTime(note, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null ||
        note.revision == TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final TerminalNoteAttachment oldAttachment = note.attachment;
    final Map<NoteId, NoteRecord> nextNotes = Map<NoteId, NoteRecord>.of(notes)
      ..[noteId] = note.copyWith(
        attachment: TerminalNoteAttachment.detached(
          previousContextId: oldAttachment.contextId!,
          reason: reason,
        ),
        order: _detachedNoteCount,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    try {
      _normalizeOrders(nextNotes, oldAttachment, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    } on _TerminalNoteCounterExhausted {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        notes: nextNotes,
        triggers: Map<NoteId, NoteTriggerRecord>.of(triggers)..remove(noteId),
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..remove(noteId),
      ),
    );
  }

  TerminalNoteMutationResult reattachNote({
    required NoteId noteId,
    required TerminalNoteContextId contextId,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    final NoteRecord note = check.note!;
    final NoteContextRecord? context = contexts[contextId];
    if (context == null) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    if (!note.attachment.isDetached ||
        context.state != TerminalNoteContextState.active) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (_attachedNoteCount(contextId) >=
        TerminalNoteLimits.maximumNotesPerAttachedContext) {
      return _reject(TerminalNoteMutationFailure.capacityExceeded);
    }
    try {
      _validateUpdateTime(note, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null ||
        note.revision == TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final TerminalNoteAttachment oldAttachment = note.attachment;
    final Map<NoteId, NoteRecord> nextNotes = Map<NoteId, NoteRecord>.of(notes)
      ..[noteId] = note.copyWith(
        attachment: TerminalNoteAttachment.attached(contextId),
        order: _attachedNoteCount(contextId),
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    try {
      _normalizeOrders(nextNotes, oldAttachment, updatedAtUtcMicros);
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    } on _TerminalNoteCounterExhausted {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(_copy(storeRevision: revision, notes: nextNotes));
  }

  TerminalNoteMutationResult detachContext({
    required TerminalNoteContextId contextId,
    required TerminalNoteDetachReason reason,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    required BigInt expectedContextRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final NoteContextRecord? context = contexts[contextId];
    if (context == null) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    if (context.revision != expectedContextRevision) {
      return _reject(TerminalNoteMutationFailure.revisionConflict);
    }
    if (context.kind == TerminalNoteContextKind.quickTerminal) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (context.state == TerminalNoteContextState.detached) return _noChange;
    final List<NoteRecord> attached =
        notes.values
            .where((NoteRecord note) => note.attachment.contextId == contextId)
            .toList()
          ..sort(_compareUserOrder);
    try {
      _validateBoundedInt(updatedAtUtcMicros, allowZero: true);
      if (attached.any(
        (NoteRecord note) => updatedAtUtcMicros < note.createdAtUtcMicros,
      )) {
        throw const TerminalNoteValidationException(
          TerminalNoteValidationFailure.invalidTimestamp,
        );
      }
      if (context.revision == TerminalNoteLimits.maximumUnsigned64 ||
          attached.any(
            (NoteRecord note) =>
                note.revision == TerminalNoteLimits.maximumUnsigned64,
          )) {
        throw const _TerminalNoteCounterExhausted();
      }
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    } on _TerminalNoteCounterExhausted {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> nextNotes = Map<NoteId, NoteRecord>.of(notes);
    var detachedOrder = _detachedNoteCount;
    for (final NoteRecord note in attached) {
      nextNotes[note.id] = note.copyWith(
        attachment: TerminalNoteAttachment.detached(
          previousContextId: contextId,
          reason: reason,
        ),
        order: detachedOrder++,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    }
    final Map<TerminalNoteContextId, NoteContextRecord> nextContexts =
        Map<TerminalNoteContextId, NoteContextRecord>.of(contexts)
          ..[contextId] = context.copyWith(
            state: TerminalNoteContextState.detached,
            revision: context.revision + BigInt.one,
          );
    final Set<NoteId> detachedIds = attached
        .map((NoteRecord note) => note.id)
        .toSet();
    return _accepted(
      _copy(
        storeRevision: revision,
        contexts: nextContexts,
        notes: nextNotes,
        triggers: Map<NoteId, NoteTriggerRecord>.of(triggers)
          ..removeWhere((NoteId id, _) => detachedIds.contains(id)),
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..removeWhere((NoteId id, _) => detachedIds.contains(id)),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..removeWhere((NoteId id, _) => detachedIds.contains(id)),
      ),
    );
  }

  TerminalNoteMutationResult reorderAttachedNotes({
    required TerminalNoteContextId contextId,
    required Iterable<NoteId> orderedNoteIds,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
  }) => _reorderNotes(
    attachment: TerminalNoteAttachment.attached(contextId),
    orderedNoteIds: orderedNoteIds,
    updatedAtUtcMicros: updatedAtUtcMicros,
    expectedStoreRevision: expectedStoreRevision,
  );

  TerminalNoteMutationResult reorderDetachedNotes({
    required Iterable<NoteId> orderedNoteIds,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
  }) => _reorderNotes(
    attachment: null,
    orderedNoteIds: orderedNoteIds,
    updatedAtUtcMicros: updatedAtUtcMicros,
    expectedStoreRevision: expectedStoreRevision,
    matchAllDetached: true,
  );

  TerminalNoteMutationResult _reorderNotes({
    required TerminalNoteAttachment? attachment,
    required Iterable<NoteId> orderedNoteIds,
    required int updatedAtUtcMicros,
    required BigInt expectedStoreRevision,
    bool matchAllDetached = false,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final List<NoteId> requested = List<NoteId>.of(orderedNoteIds);
    final List<NoteRecord> current =
        notes.values
            .where(
              (NoteRecord note) => matchAllDetached
                  ? note.attachment.isDetached
                  : note.attachment == attachment!,
            )
            .toList()
          ..sort(_compareUserOrder);
    if (requested.length != current.length ||
        requested.toSet().length != requested.length ||
        !requested.toSet().containsAll(
          current.map((NoteRecord note) => note.id),
        )) {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    if (_sameOrder(current, requested)) return _noChange;
    try {
      _validateBoundedInt(updatedAtUtcMicros, allowZero: true);
      for (final NoteRecord note in current) {
        if (updatedAtUtcMicros < note.createdAtUtcMicros) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invalidTimestamp,
          );
        }
        if (note.revision == TerminalNoteLimits.maximumUnsigned64) {
          throw const _TerminalNoteCounterExhausted();
        }
      }
    } on TerminalNoteValidationException {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    } on _TerminalNoteCounterExhausted {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteRecord> next = Map<NoteId, NoteRecord>.of(notes);
    for (var order = 0; order < requested.length; order++) {
      final NoteRecord note = next[requested[order]]!;
      next[note.id] = note.copyWith(
        order: order,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    }
    return _accepted(_copy(storeRevision: revision, notes: next));
  }

  TerminalNoteMutationResult armOnReturn({
    required NoteId noteId,
    required bool isEligible,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkActiveAttachedNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    if (deliveries.containsKey(noteId)) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers)
          ..[noteId] = NoteTriggerRecord(
            noteId: noteId,
            generation: revision,
            kind: NoteTriggerKind.onReturn,
            phase: isEligible
                ? NoteTriggerPhase.onReturnArmedHere
                : NoteTriggerPhase.onReturnArmedAway,
            suspendReason: null,
            armedAtRevision: revision,
          );
    return _accepted(
      _copy(
        storeRevision: revision,
        triggers: nextTriggers,
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..remove(noteId),
      ),
    );
  }

  TerminalNoteMutationResult armAtNextPrompt({
    required NoteId noteId,
    required TerminalNotePromptCapability capability,
    required TerminalNoteSemanticState currentSemanticState,
    required NoteTriggerRuntimeBinding binding,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkActiveAttachedNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    if (deliveries.containsKey(noteId)) {
      return _reject(TerminalNoteMutationFailure.invalidState);
    }
    if (capability != TerminalNotePromptCapability.available) {
      return _reject(TerminalNoteMutationFailure.capabilityUnavailable);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers)
          ..[noteId] = NoteTriggerRecord(
            noteId: noteId,
            generation: revision,
            kind: NoteTriggerKind.atNextPrompt,
            phase:
                currentSemanticState == TerminalNoteSemanticState.commandOutput
                ? NoteTriggerPhase.atNextPromptWaitingEnd
                : NoteTriggerPhase.atNextPromptWaitingCommand,
            suspendReason: null,
            armedAtRevision: revision,
          );
    return _accepted(
      _copy(
        storeRevision: revision,
        triggers: nextTriggers,
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..[noteId] = binding,
      ),
    );
  }

  TerminalNoteMutationResult cancelTrigger({
    required NoteId noteId,
    required BigInt expectedStoreRevision,
    required BigInt expectedNoteRevision,
  }) {
    final _TerminalNoteCheck check = _checkNote(
      noteId,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    if (check.failure != null) return check.failure!;
    if (!triggers.containsKey(noteId)) return _noChange;
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        triggers: Map<NoteId, NoteTriggerRecord>.of(triggers)..remove(noteId),
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..remove(noteId),
      ),
    );
  }

  TerminalNoteMutationResult observeEligibleFocus({
    required TerminalNoteContextId contextId,
    required bool isEligible,
    required BigInt expectedStoreRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    if (!contexts.containsKey(contextId)) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers);
    final List<NoteId> becameDue = <NoteId>[];
    var changed = false;
    for (final MapEntry<NoteId, NoteTriggerRecord> entry in triggers.entries) {
      final NoteRecord? note = notes[entry.key];
      final NoteTriggerRecord trigger = entry.value;
      if (note?.attachment.contextId != contextId ||
          trigger.kind != NoteTriggerKind.onReturn) {
        continue;
      }
      NoteTriggerPhase? phase;
      if (!isEligible && trigger.phase == NoteTriggerPhase.onReturnArmedHere) {
        phase = NoteTriggerPhase.onReturnArmedAway;
      } else if (isEligible &&
          trigger.phase == NoteTriggerPhase.onReturnArmedAway) {
        phase = NoteTriggerPhase.due;
        becameDue.add(entry.key);
      }
      if (phase != null) {
        nextTriggers[entry.key] = trigger.copyWith(
          phase: phase,
          clearSuspendReason: true,
        );
        changed = true;
      }
    }
    if (!changed) return _noChange;
    return _commitTriggerTransition(
      nextTriggers: nextTriggers,
      becameDue: becameDue,
      runtimeBindings: _runtimeBindings,
    );
  }

  TerminalNoteMutationResult observePromptEvents({
    required TerminalNoteContextId contextId,
    required NoteTriggerRuntimeBinding binding,
    required Iterable<TerminalNotePromptEvent> events,
    required BigInt expectedStoreRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    if (!contexts.containsKey(contextId)) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    final List<TerminalNotePromptEvent> batch =
        List<TerminalNotePromptEvent>.of(events);
    if (batch.length > TerminalNoteLimits.maximumPromptEventsPerBatch) {
      return _suspendPromptTriggers(
        contextId: contextId,
        matchingBinding: binding,
        reason: NoteTriggerSuspendReason.eventOverflow,
      );
    }
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers);
    final Map<NoteId, NoteTriggerRuntimeBinding> nextRuntime =
        Map<NoteId, NoteTriggerRuntimeBinding>.of(_runtimeBindings);
    final Set<NoteId> becameDue = <NoteId>{};
    var persistentChanged = false;
    var runtimeChanged = false;
    for (final TerminalNotePromptEvent event in batch) {
      for (final MapEntry<NoteId, NoteTriggerRecord> entry
          in List<MapEntry<NoteId, NoteTriggerRecord>>.of(
            nextTriggers.entries,
          )) {
        final NoteRecord? note = notes[entry.key];
        final NoteTriggerRecord trigger = entry.value;
        final NoteTriggerRuntimeBinding? runtime = nextRuntime[entry.key];
        if (note?.attachment.contextId != contextId ||
            trigger.kind != NoteTriggerKind.atNextPrompt ||
            runtime == null ||
            !runtime.matches(binding) ||
            event.sequence <= runtime.lastEventSequence) {
          continue;
        }
        nextRuntime[entry.key] = runtime.copyWith(
          lastEventSequence: event.sequence,
        );
        runtimeChanged = true;
        final NoteTriggerPhase nextPhase = _nextPromptPhase(
          trigger.phase,
          event.action,
        );
        if (nextPhase != trigger.phase) {
          nextTriggers[entry.key] = trigger.copyWith(
            phase: nextPhase,
            clearSuspendReason: true,
          );
          persistentChanged = true;
        }
        if (nextPhase == NoteTriggerPhase.due) {
          becameDue.add(entry.key);
          nextRuntime.remove(entry.key);
        }
      }
    }
    if (!persistentChanged) {
      if (!runtimeChanged) return _noChange;
      return TerminalNoteMutationResult._(
        snapshot: _copy(runtimeBindings: nextRuntime),
        disposition: TerminalNoteMutationDisposition.runtimeOnly,
        failure: null,
      );
    }
    return _commitTriggerTransition(
      nextTriggers: nextTriggers,
      becameDue: becameDue.toList(),
      runtimeBindings: nextRuntime,
    );
  }

  /// Applies a coalesced focus/prompt ingress batch as one store transaction.
  ///
  /// The authority can use this when both event families are drained together;
  /// delivery sequences remain unique and deterministic while store revision is
  /// incremented at most once.
  TerminalNoteMutationResult observeLifecycleBatch({
    required TerminalNoteContextId contextId,
    required BigInt expectedStoreRevision,
    bool? isEligible,
    Iterable<bool> eligibleFocusEdges = const <bool>[],
    NoteTriggerRuntimeBinding? promptBinding,
    Iterable<TerminalNotePromptEvent> promptEvents =
        const <TerminalNotePromptEvent>[],
    bool promptEventOverflow = false,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final List<bool> focusEdges = List<bool>.of(eligibleFocusEdges);
    if (isEligible != null) {
      if (focusEdges.isNotEmpty) {
        return _reject(TerminalNoteMutationFailure.invalidInput);
      }
      focusEdges.add(isEligible);
    }
    if (focusEdges.length > TerminalNoteLimits.maximumCoalescedFocusEdges ||
        (promptBinding == null &&
            (promptEvents.isNotEmpty || promptEventOverflow)) ||
        (promptEventOverflow && promptEvents.isNotEmpty)) {
      return _reject(TerminalNoteMutationFailure.invalidInput);
    }
    if (focusEdges.isEmpty && promptBinding == null) return _noChange;
    TerminalNoteSnapshot working = this;
    var persistentChanged = false;
    var runtimeChanged = false;

    TerminalNoteMutationResult apply(TerminalNoteMutationResult result) {
      if (result.disposition == TerminalNoteMutationDisposition.rejected) {
        return TerminalNoteMutationResult._(
          snapshot: this,
          disposition: result.disposition,
          failure: result.failure,
        );
      }
      persistentChanged |=
          result.disposition == TerminalNoteMutationDisposition.accepted;
      runtimeChanged |=
          result.disposition == TerminalNoteMutationDisposition.runtimeOnly;
      final TerminalNoteSnapshot candidate = result.snapshot;
      working = TerminalNoteSnapshot._(
        storeRevision: storeRevision,
        nextDeliverySequence: candidate.nextDeliverySequence,
        contexts: candidate.contexts,
        notes: candidate.notes,
        triggers: candidate.triggers,
        deliveries: candidate.deliveries,
        runtimeBindings: candidate._runtimeBindings,
      );
      return result;
    }

    for (final bool eligible in focusEdges) {
      final TerminalNoteMutationResult result = apply(
        working.observeEligibleFocus(
          contextId: contextId,
          isEligible: eligible,
          expectedStoreRevision: storeRevision,
        ),
      );
      if (result.disposition == TerminalNoteMutationDisposition.rejected) {
        return TerminalNoteMutationResult._(
          snapshot: this,
          disposition: result.disposition,
          failure: result.failure,
        );
      }
    }
    if (promptBinding != null) {
      final TerminalNoteMutationResult result = apply(
        promptEventOverflow
            ? working.suspendAtNextPrompt(
                contextId: contextId,
                reason: NoteTriggerSuspendReason.eventOverflow,
                expectedStoreRevision: storeRevision,
                matchingBinding: promptBinding,
              )
            : working.observePromptEvents(
                contextId: contextId,
                binding: promptBinding,
                events: promptEvents,
                expectedStoreRevision: storeRevision,
              ),
      );
      if (result.disposition == TerminalNoteMutationDisposition.rejected) {
        return TerminalNoteMutationResult._(
          snapshot: this,
          disposition: result.disposition,
          failure: result.failure,
        );
      }
    }
    if (persistentChanged) {
      final BigInt? committedRevision = _nextStoreRevision;
      if (committedRevision == null) {
        return _reject(TerminalNoteMutationFailure.counterExhausted);
      }
      final List<NoteId> newlyDue =
          working.deliveries.keys
              .where((NoteId id) => !deliveries.containsKey(id))
              .toList()
            ..sort();
      final Map<NoteId, NoteDeliveryRecord> orderedDeliveries =
          Map<NoteId, NoteDeliveryRecord>.of(working.deliveries);
      var sequence = nextDeliverySequence;
      for (final NoteId id in newlyDue) {
        final NoteTriggerRecord trigger = working.triggers[id]!;
        orderedDeliveries[id] = NoteDeliveryRecord(
          noteId: id,
          triggerGeneration: trigger.generation,
          sequence: DeliverySequence(sequence),
        );
        sequence += BigInt.one;
      }
      return _accepted(
        TerminalNoteSnapshot._(
          storeRevision: committedRevision,
          nextDeliverySequence: sequence,
          contexts: working.contexts,
          notes: working.notes,
          triggers: working.triggers,
          deliveries: orderedDeliveries,
          runtimeBindings: working._runtimeBindings,
        ),
      );
    }
    if (runtimeChanged) {
      return TerminalNoteMutationResult._(
        snapshot: working,
        disposition: TerminalNoteMutationDisposition.runtimeOnly,
        failure: null,
      );
    }
    return _noChange;
  }

  TerminalNoteMutationResult suspendAtNextPrompt({
    required TerminalNoteContextId contextId,
    required NoteTriggerSuspendReason reason,
    required BigInt expectedStoreRevision,
    NoteTriggerRuntimeBinding? matchingBinding,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    if (!contexts.containsKey(contextId)) {
      return _reject(TerminalNoteMutationFailure.contextNotFound);
    }
    return _suspendPromptTriggers(
      contextId: contextId,
      matchingBinding: matchingBinding,
      reason: reason,
    );
  }

  TerminalNoteMutationResult _suspendPromptTriggers({
    required TerminalNoteContextId contextId,
    required NoteTriggerRuntimeBinding? matchingBinding,
    required NoteTriggerSuspendReason reason,
  }) {
    final Map<NoteId, NoteTriggerRecord> nextTriggers =
        Map<NoteId, NoteTriggerRecord>.of(triggers);
    final Map<NoteId, NoteTriggerRuntimeBinding> nextRuntime =
        Map<NoteId, NoteTriggerRuntimeBinding>.of(_runtimeBindings);
    var changed = false;
    for (final MapEntry<NoteId, NoteTriggerRecord> entry in triggers.entries) {
      final NoteRecord? note = notes[entry.key];
      final NoteTriggerRuntimeBinding? runtime = _runtimeBindings[entry.key];
      if (note?.attachment.contextId != contextId ||
          entry.value.kind != NoteTriggerKind.atNextPrompt ||
          entry.value.phase == NoteTriggerPhase.due ||
          entry.value.phase == NoteTriggerPhase.suspended ||
          (matchingBinding != null &&
              (runtime == null || !runtime.matches(matchingBinding)))) {
        continue;
      }
      nextTriggers[entry.key] = entry.value.copyWith(
        phase: NoteTriggerPhase.suspended,
        suspendReason: reason,
      );
      nextRuntime.remove(entry.key);
      changed = true;
    }
    if (!changed) return _noChange;
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        triggers: nextTriggers,
        runtimeBindings: nextRuntime,
      ),
    );
  }

  TerminalNoteMutationResult acknowledgePresentation({
    required NoteId noteId,
    required BigInt triggerGeneration,
    required BigInt expectedStoreRevision,
  }) {
    final TerminalNoteMutationResult? conflict = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (conflict != null) return conflict;
    final NoteTriggerRecord? trigger = triggers[noteId];
    final NoteDeliveryRecord? delivery = deliveries[noteId];
    if (trigger == null || delivery == null) {
      return _noChange;
    }
    if (trigger.generation != triggerGeneration ||
        delivery.triggerGeneration != triggerGeneration) {
      return _reject(TerminalNoteMutationFailure.revisionConflict);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        triggers: Map<NoteId, NoteTriggerRecord>.of(triggers)..remove(noteId),
        deliveries: Map<NoteId, NoteDeliveryRecord>.of(deliveries)
          ..remove(noteId),
        runtimeBindings: Map<NoteId, NoteTriggerRuntimeBinding>.of(
          _runtimeBindings,
        )..remove(noteId),
      ),
    );
  }

  TerminalNoteContextProjection projectionFor(TerminalNoteContextId contextId) {
    if (!contexts.containsKey(contextId)) {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invalidRecord,
      );
    }
    final List<NoteRecord> attached = notes.values
        .where((NoteRecord note) => note.attachment.contextId == contextId)
        .toList();
    final List<NoteRecord> due =
        attached
            .where((NoteRecord note) => deliveries.containsKey(note.id))
            .toList()
          ..sort((NoteRecord left, NoteRecord right) {
            final int sequence = deliveries[left.id]!.sequence.compareTo(
              deliveries[right.id]!.sequence,
            );
            return sequence == 0 ? left.id.compareTo(right.id) : sequence;
          });
    final List<NoteRecord> passive =
        attached
            .where((NoteRecord note) => !deliveries.containsKey(note.id))
            .toList()
          ..sort(_compareUserOrder);
    return TerminalNoteContextProjection(
      contextId: contextId,
      activeCount: attached
          .where((NoteRecord note) => note.status == NoteStatus.active)
          .length,
      dueCount: due.length,
      orderedNotes: <NoteRecord>[...due, ...passive],
    );
  }

  /// Checks every hard bound and cross-record invariant without exposing data.
  void validate() {
    try {
      _validateCounter(storeRevision, allowZero: true);
      _validateCounter(nextDeliverySequence);
      if ((storeRevision == BigInt.zero &&
              (contexts.isNotEmpty ||
                  notes.isNotEmpty ||
                  triggers.isNotEmpty ||
                  deliveries.isNotEmpty ||
                  _runtimeBindings.isNotEmpty)) ||
          contexts.length > TerminalNoteLimits.maximumContexts ||
          notes.length > TerminalNoteLimits.maximumNotes ||
          triggers.length > TerminalNoteLimits.maximumTriggers ||
          deliveries.length > TerminalNoteLimits.maximumDeliveries ||
          aggregateBodyUtf8Bytes >
              TerminalNoteLimits.maximumAggregateBodyUtf8Bytes) {
        throw const TerminalNoteValidationException(
          TerminalNoteValidationFailure.invariantViolation,
        );
      }
      final Map<Object, List<NoteRecord>> collections =
          <Object, List<NoteRecord>>{};
      final Object detachedCollection = Object();
      var quickTerminalContextCount = 0;
      for (final MapEntry<TerminalNoteContextId, NoteContextRecord> entry
          in contexts.entries) {
        if (entry.key != entry.value.id ||
            entry.value.revision > storeRevision &&
                storeRevision != BigInt.zero) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
        if (entry.value.kind == TerminalNoteContextKind.quickTerminal &&
            (entry.value.state != TerminalNoteContextState.active ||
                ++quickTerminalContextCount > 1)) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
      }
      for (final MapEntry<NoteId, NoteRecord> entry in notes.entries) {
        final NoteRecord note = entry.value;
        if (entry.key != note.id ||
            note.revision > storeRevision && storeRevision != BigInt.zero) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
        final Object collection;
        if (note.attachment.isAttached) {
          final NoteContextRecord? context =
              contexts[note.attachment.contextId];
          if (context == null ||
              context.state == TerminalNoteContextState.detached) {
            throw const TerminalNoteValidationException(
              TerminalNoteValidationFailure.invariantViolation,
            );
          }
          collection = note.attachment.contextId!;
        } else {
          if (note.attachment.previousContextId == null ||
              note.attachment.detachReason == null ||
              !contexts.containsKey(note.attachment.previousContextId)) {
            throw const TerminalNoteValidationException(
              TerminalNoteValidationFailure.invariantViolation,
            );
          }
          collection = detachedCollection;
        }
        (collections[collection] ??= <NoteRecord>[]).add(note);
        if ((note.status == NoteStatus.resolved ||
                note.attachment.isDetached) &&
            (triggers.containsKey(note.id) ||
                deliveries.containsKey(note.id))) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
      }
      for (final MapEntry<Object, List<NoteRecord>> entry
          in collections.entries) {
        final List<NoteRecord> collection = entry.value
          ..sort(_compareUserOrder);
        if (entry.key != detachedCollection &&
            collection.length >
                TerminalNoteLimits.maximumNotesPerAttachedContext) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
        for (var index = 0; index < collection.length; index++) {
          if (collection[index].order != index) {
            throw const TerminalNoteValidationException(
              TerminalNoteValidationFailure.invariantViolation,
            );
          }
        }
      }
      final Set<BigInt> deliverySequences = <BigInt>{};
      for (final MapEntry<NoteId, NoteTriggerRecord> entry
          in triggers.entries) {
        final NoteRecord? note = notes[entry.key];
        final NoteTriggerRecord trigger = entry.value;
        if (entry.key != trigger.noteId ||
            note == null ||
            note.status != NoteStatus.active ||
            !note.attachment.isAttached ||
            trigger.armedAtRevision > storeRevision) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
        final bool isDue = trigger.phase == NoteTriggerPhase.due;
        if (isDue != deliveries.containsKey(entry.key)) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
        final bool requiresRuntime =
            trigger.kind == NoteTriggerKind.atNextPrompt &&
            trigger.phase != NoteTriggerPhase.due &&
            trigger.phase != NoteTriggerPhase.suspended;
        if (requiresRuntime != _runtimeBindings.containsKey(entry.key)) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
      }
      for (final MapEntry<NoteId, NoteDeliveryRecord> entry
          in deliveries.entries) {
        final NoteTriggerRecord? trigger = triggers[entry.key];
        final NoteDeliveryRecord delivery = entry.value;
        if (entry.key != delivery.noteId ||
            trigger == null ||
            trigger.phase != NoteTriggerPhase.due ||
            trigger.generation != delivery.triggerGeneration ||
            delivery.sequence.value >= nextDeliverySequence ||
            !deliverySequences.add(delivery.sequence.value)) {
          throw const TerminalNoteValidationException(
            TerminalNoteValidationFailure.invariantViolation,
          );
        }
      }
      if (_runtimeBindings.keys.any((NoteId id) => !triggers.containsKey(id))) {
        throw const TerminalNoteValidationException(
          TerminalNoteValidationFailure.invariantViolation,
        );
      }
    } on TerminalNoteValidationException {
      rethrow;
    } on Object {
      throw const TerminalNoteValidationException(
        TerminalNoteValidationFailure.invariantViolation,
      );
    }
  }

  TerminalNoteMutationResult _commitTriggerTransition({
    required Map<NoteId, NoteTriggerRecord> nextTriggers,
    required Iterable<NoteId> becameDue,
    required Map<NoteId, NoteTriggerRuntimeBinding> runtimeBindings,
  }) {
    final List<NoteId> orderedDue = becameDue.toSet().toList()..sort();
    if (orderedDue.isNotEmpty &&
        nextDeliverySequence + BigInt.from(orderedDue.length) >
            TerminalNoteLimits.maximumUnsigned64) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final BigInt? revision = _nextStoreRevision;
    if (revision == null) {
      return _reject(TerminalNoteMutationFailure.counterExhausted);
    }
    final Map<NoteId, NoteDeliveryRecord> nextDeliveries =
        Map<NoteId, NoteDeliveryRecord>.of(deliveries);
    var sequence = nextDeliverySequence;
    for (final NoteId id in orderedDue) {
      final NoteTriggerRecord trigger = nextTriggers[id]!;
      nextDeliveries[id] = NoteDeliveryRecord(
        noteId: id,
        triggerGeneration: trigger.generation,
        sequence: DeliverySequence(sequence),
      );
      sequence += BigInt.one;
    }
    return _accepted(
      _copy(
        storeRevision: revision,
        nextDeliverySequence: sequence,
        triggers: nextTriggers,
        deliveries: nextDeliveries,
        runtimeBindings: runtimeBindings,
      ),
    );
  }

  _TerminalNoteCheck _checkNote(
    NoteId id,
    BigInt expectedStoreRevision,
    BigInt expectedNoteRevision,
  ) {
    final TerminalNoteMutationResult? storeFailure = _checkStoreRevision(
      expectedStoreRevision,
    );
    if (storeFailure != null) {
      return _TerminalNoteCheck.failure(storeFailure);
    }
    final NoteRecord? note = notes[id];
    if (note == null) {
      return _TerminalNoteCheck.failure(
        _reject(TerminalNoteMutationFailure.noteNotFound),
      );
    }
    if (note.revision != expectedNoteRevision) {
      return _TerminalNoteCheck.failure(
        _reject(TerminalNoteMutationFailure.revisionConflict),
      );
    }
    return _TerminalNoteCheck.note(note);
  }

  _TerminalNoteCheck _checkActiveAttachedNote(
    NoteId id,
    BigInt expectedStoreRevision,
    BigInt expectedNoteRevision,
  ) {
    final _TerminalNoteCheck check = _checkNote(
      id,
      expectedStoreRevision,
      expectedNoteRevision,
    );
    final NoteRecord? note = check.note;
    if (note == null) return check;
    if (note.status != NoteStatus.active || !note.attachment.isAttached) {
      return _TerminalNoteCheck.failure(
        _reject(TerminalNoteMutationFailure.invalidState),
      );
    }
    return check;
  }

  TerminalNoteMutationResult? _checkStoreRevision(BigInt expected) =>
      expected == storeRevision
      ? null
      : _reject(TerminalNoteMutationFailure.revisionConflict);

  BigInt? get _nextStoreRevision =>
      storeRevision >= TerminalNoteLimits.maximumUnsigned64
      ? null
      : storeRevision + BigInt.one;

  int _attachedNoteCount(TerminalNoteContextId contextId) => notes.values
      .where((NoteRecord note) => note.attachment.contextId == contextId)
      .length;

  int get _detachedNoteCount => notes.values
      .where((NoteRecord note) => note.attachment.isDetached)
      .length;

  TerminalNoteMutationResult get _noChange => TerminalNoteMutationResult._(
    snapshot: this,
    disposition: TerminalNoteMutationDisposition.noChange,
    failure: null,
  );

  TerminalNoteMutationResult _accepted(TerminalNoteSnapshot snapshot) =>
      TerminalNoteMutationResult._(
        snapshot: snapshot,
        disposition: TerminalNoteMutationDisposition.accepted,
        failure: null,
      );

  TerminalNoteMutationResult _reject(TerminalNoteMutationFailure failure) =>
      TerminalNoteMutationResult._(
        snapshot: this,
        disposition: TerminalNoteMutationDisposition.rejected,
        failure: failure,
      );

  TerminalNoteSnapshot _copy({
    BigInt? storeRevision,
    BigInt? nextDeliverySequence,
    Map<TerminalNoteContextId, NoteContextRecord>? contexts,
    Map<NoteId, NoteRecord>? notes,
    Map<NoteId, NoteTriggerRecord>? triggers,
    Map<NoteId, NoteDeliveryRecord>? deliveries,
    Map<NoteId, NoteTriggerRuntimeBinding>? runtimeBindings,
  }) => TerminalNoteSnapshot._(
    storeRevision: storeRevision ?? this.storeRevision,
    nextDeliverySequence: nextDeliverySequence ?? this.nextDeliverySequence,
    contexts: contexts ?? this.contexts,
    notes: notes ?? this.notes,
    triggers: triggers ?? this.triggers,
    deliveries: deliveries ?? this.deliveries,
    runtimeBindings: runtimeBindings ?? _runtimeBindings,
  );

  static NoteTriggerPhase _nextPromptPhase(
    NoteTriggerPhase phase,
    TerminalNotePromptAction action,
  ) {
    if (phase == NoteTriggerPhase.due || phase == NoteTriggerPhase.suspended) {
      return phase;
    }
    return switch (phase) {
      NoteTriggerPhase.atNextPromptWaitingCommand =>
        action == TerminalNotePromptAction.commandOutputBegins
            ? NoteTriggerPhase.atNextPromptWaitingEnd
            : phase,
      NoteTriggerPhase.atNextPromptWaitingEnd => switch (action) {
        TerminalNotePromptAction.commandOutputBegins ||
        TerminalNotePromptAction.secondaryPrompt ||
        TerminalNotePromptAction.inputLineEnds => phase,
        TerminalNotePromptAction.commandEnds =>
          NoteTriggerPhase.atNextPromptWaitingPromptStart,
        _ => NoteTriggerPhase.atNextPromptWaitingCommand,
      },
      NoteTriggerPhase.atNextPromptWaitingPromptStart => switch (action) {
        TerminalNotePromptAction.commandEnds ||
        TerminalNotePromptAction.secondaryPrompt ||
        TerminalNotePromptAction.inputLineEnds => phase,
        TerminalNotePromptAction.promptBegins ||
        TerminalNotePromptAction.freshPromptBegins =>
          NoteTriggerPhase.atNextPromptWaitingInput,
        TerminalNotePromptAction.commandOutputBegins =>
          NoteTriggerPhase.atNextPromptWaitingEnd,
        _ => NoteTriggerPhase.atNextPromptWaitingCommand,
      },
      NoteTriggerPhase.atNextPromptWaitingInput => switch (action) {
        TerminalNotePromptAction.promptBegins ||
        TerminalNotePromptAction.freshPromptBegins ||
        TerminalNotePromptAction.secondaryPrompt ||
        TerminalNotePromptAction.inputLineEnds => phase,
        TerminalNotePromptAction.primaryInputReady => NoteTriggerPhase.due,
        TerminalNotePromptAction.commandOutputBegins =>
          NoteTriggerPhase.atNextPromptWaitingEnd,
        _ => NoteTriggerPhase.atNextPromptWaitingCommand,
      },
      _ => phase,
    };
  }

  static int _compareUserOrder(NoteRecord left, NoteRecord right) {
    final int order = left.order.compareTo(right.order);
    return order == 0 ? left.id.compareTo(right.id) : order;
  }

  static bool _sameOrder(List<NoteRecord> current, List<NoteId> requested) {
    for (var index = 0; index < current.length; index++) {
      if (current[index].id != requested[index]) return false;
    }
    return true;
  }

  static void _normalizeOrders(
    Map<NoteId, NoteRecord> records,
    TerminalNoteAttachment attachment,
    int updatedAtUtcMicros,
  ) {
    final bool detached = attachment.isDetached;
    final List<NoteRecord> collection =
        records.values
            .where(
              (NoteRecord note) => detached
                  ? note.attachment.isDetached
                  : note.attachment.contextId == attachment.contextId,
            )
            .toList()
          ..sort(_compareUserOrder);
    for (var order = 0; order < collection.length; order++) {
      final NoteRecord note = collection[order];
      if (note.order == order) continue;
      if (note.revision == TerminalNoteLimits.maximumUnsigned64) {
        throw const _TerminalNoteCounterExhausted();
      }
      records[note.id] = note.copyWith(
        order: order,
        updatedAtUtcMicros: updatedAtUtcMicros,
        revision: note.revision + BigInt.one,
      );
    }
  }
}

void _validateUpdateTime(NoteRecord note, int value) {
  _validateBoundedInt(value, allowZero: true);
  if (value < note.createdAtUtcMicros) {
    throw const TerminalNoteValidationException(
      TerminalNoteValidationFailure.invalidTimestamp,
    );
  }
}

void _validateCounter(BigInt value, {bool allowZero = false}) {
  if (value < (allowZero ? BigInt.zero : BigInt.one) ||
      value > TerminalNoteLimits.maximumUnsigned64) {
    throw const TerminalNoteValidationException(
      TerminalNoteValidationFailure.invalidCounter,
    );
  }
}

void _validateBoundedInt(int value, {bool allowZero = false}) {
  if (value < (allowZero ? 0 : 1)) {
    throw const TerminalNoteValidationException(
      TerminalNoteValidationFailure.invalidCounter,
    );
  }
}

final class _TerminalNoteCounterExhausted implements Exception {
  const _TerminalNoteCounterExhausted();
}

final class _TerminalNoteCheck {
  const _TerminalNoteCheck.note(this.note) : failure = null;
  const _TerminalNoteCheck.failure(this.failure) : note = null;

  final NoteRecord? note;
  final TerminalNoteMutationResult? failure;
}
