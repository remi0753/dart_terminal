import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalNoteModelTests();

void runTerminalNoteModelTests() {
  _testOpaqueIdsAndBodyPolicy();
  _testLifecycleAndRevisionTransactions();
  _testQuotaAndCounterBoundaries();
  _testOnReturnReviewVectors();
  _testAtNextPromptReviewVectors();
  _testDuplicateResetOverflowAndCombinedOrdering();
  _testPrivacyAndDependencySentinel();
  _testFixedSeedStateSequences();
}

void _testOpaqueIdsAndBodyPolicy() {
  final NoteId id = _noteId(1);
  final TerminalNoteContextId contextId = _contextId(1);
  final ShellIntegrationInstanceId instanceId = _instanceId(1);
  _expect(
    !id.toString().contains(id.canonicalValue) &&
        !contextId.toString().contains(contextId.canonicalValue) &&
        !instanceId.toString().contains(instanceId.canonicalValue),
    'opaque identity string formatting is redacted',
  );
  _expectThrowsValidation(
    () => NoteId.fromHex('ABCDEF0123456789ABCDEF0123456789'),
    TerminalNoteValidationFailure.invalidId,
    'uppercase persistent identity is non-canonical',
  );
  _expectThrowsValidation(
    () => TerminalNoteContextId.fromHex(_repeat('0', 31)),
    TerminalNoteValidationFailure.invalidId,
    'short persistent identity is rejected',
  );

  final NoteBody normalized = NoteBody.fromText(' first\r\nsecond\rthird\t ');
  _expect(
    normalized.value == ' first\nsecond\nthird\t ' && normalized.lineCount == 3,
    'body admission normalizes only CRLF and CR',
  );
  _expect(
    NoteBody.fromText(_repeat('x', TerminalNoteLimits.maximumBodyUtf8Bytes))
            .utf8Length ==
        TerminalNoteLimits.maximumBodyUtf8Bytes,
    'exact UTF-8 body limit is accepted',
  );
  _expectThrowsValidation(
    () => NoteBody.fromText(
      _repeat('x', TerminalNoteLimits.maximumBodyUtf8Bytes + 1),
    ),
    TerminalNoteValidationFailure.invalidBody,
    'body byte limit plus one is rejected',
  );
  final String sixtyFourLines = List<String>.filled(64, 'x').join('\n');
  _expect(
    NoteBody.fromText(sixtyFourLines).lineCount == 64,
    'exact body line limit is accepted',
  );
  _expectThrowsValidation(
    () => NoteBody.fromText('$sixtyFourLines\nx'),
    TerminalNoteValidationFailure.invalidBody,
    'body line limit plus one is rejected',
  );
  for (final String invalid in <String>[
    ' \t\n',
    'before\u0000after',
    'before\u0085after',
    'before\u202eafter',
    'before\u2066after',
    'before\ud800after',
  ]) {
    _expectThrowsValidation(
      () => NoteBody.fromText(invalid),
      TerminalNoteValidationFailure.invalidBody,
      'invalid control, bidi, whitespace-only, or surrogate body is rejected',
    );
  }
  final NoteBody unicode = NoteBody.fromText('مرحبا אבג 👩‍💻 é');
  _expect(
    unicode.value.contains('👩‍💻') &&
        unicode.toString() == 'NoteBody(<redacted>)',
    'ordinary RTL text, emoji ZWJ, and combining text are retained',
  );
}

void _testLifecycleAndRevisionTransactions() {
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: _contextId(1),
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  for (var value = 1; value <= 3; value++) {
    snapshot = _accept(
      snapshot.createNote(
        id: _noteId(value),
        contextId: _contextId(1),
        body: 'note $value',
        color: NoteColorKey.yellow,
        utcMicros: value,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
  }
  _expectThrowsUnsupported(
    () => snapshot.notes.clear(),
    'published record maps are immutable',
  );
  final TerminalNoteSnapshot beforeConflict = snapshot;
  final TerminalNoteMutationResult conflict = snapshot.editNote(
    noteId: _noteId(1),
    body: 'private changed body',
    color: NoteColorKey.blue,
    updatedAtUtcMicros: 10,
    expectedStoreRevision: snapshot.storeRevision,
    expectedNoteRevision: BigInt.from(99),
  );
  _expectRejectedSame(
    conflict,
    beforeConflict,
    TerminalNoteMutationFailure.revisionConflict,
    'stale editor revision leaves the snapshot unchanged',
  );

  snapshot = _accept(
    snapshot.editNote(
      noteId: _noteId(1),
      body: 'edited',
      color: NoteColorKey.blue,
      updatedAtUtcMicros: 10,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(1))!.body.value == 'edited' &&
        snapshot.noteFor(_noteId(1))!.revision == BigInt.from(2),
    'edit atomically changes body, color, and Note revision',
  );

  snapshot = _accept(
    snapshot.reorderAttachedNotes(
      contextId: _contextId(1),
      orderedNoteIds: <NoteId>[_noteId(3), _noteId(1), _noteId(2)],
      updatedAtUtcMicros: 11,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  _expect(
    snapshot
            .projectionFor(_contextId(1))
            .orderedNotes
            .map((NoteRecord note) => note.id.canonicalValue)
            .join(',') ==
        <NoteId>[
          _noteId(3),
          _noteId(1),
          _noteId(2),
        ].map((NoteId id) => id.canonicalValue).join(','),
    'reorder normalizes the whole attached collection',
  );

  snapshot = _accept(
    snapshot.armOnReturn(
      noteId: _noteId(1),
      isEligible: false,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  snapshot = _accept(
    snapshot.observeEligibleFocus(
      contextId: _contextId(1),
      isEligible: true,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.resolveNote(
      noteId: _noteId(1),
      updatedAtUtcMicros: 12,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(1))!.status == NoteStatus.resolved &&
        snapshot.triggerFor(_noteId(1)) == null &&
        snapshot.deliveryFor(_noteId(1)) == null,
    'resolve retains the Note and atomically removes trigger and delivery',
  );
  snapshot = _accept(
    snapshot.reopenNote(
      noteId: _noteId(1),
      updatedAtUtcMicros: 13,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(1))!.status == NoteStatus.active &&
        snapshot.triggerFor(_noteId(1)) == null,
    'reopen returns to active passive state without restoring old trigger',
  );

  snapshot = _accept(
    snapshot.detachNote(
      noteId: _noteId(2),
      reason: TerminalNoteDetachReason.explicitDetach,
      updatedAtUtcMicros: 14,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(2))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(2))!.attachment.isDetached &&
        snapshot.projectionFor(_contextId(1)).orderedNotes.length == 2,
    'detach removes a Note from its pane projection without deleting content',
  );
  snapshot = _accept(
    snapshot.reattachNote(
      noteId: _noteId(2),
      contextId: _contextId(1),
      updatedAtUtcMicros: 15,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(2))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(2))!.attachment.contextId == _contextId(1) &&
        snapshot.noteFor(_noteId(2))!.order == 2,
    'explicit reattach appends to the target context',
  );

  snapshot = _accept(
    snapshot.deleteNote(
      noteId: _noteId(1),
      updatedAtUtcMicros: 16,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  _expect(
    snapshot.noteFor(_noteId(1)) == null &&
        snapshot
                .projectionFor(_contextId(1))
                .orderedNotes
                .map((NoteRecord note) => note.order)
                .join(',') ==
            '0,1',
    'delete removes all Note state and normalizes collection order',
  );

  final NoteContextRecord context = snapshot.contextFor(_contextId(1))!;
  snapshot = _accept(
    snapshot.detachContext(
      contextId: _contextId(1),
      reason: TerminalNoteDetachReason.paneClosed,
      updatedAtUtcMicros: 17,
      expectedStoreRevision: snapshot.storeRevision,
      expectedContextRevision: context.revision,
    ),
  );
  _expect(
    snapshot.contextFor(_contextId(1))!.state ==
            TerminalNoteContextState.detached &&
        snapshot.notes.values.every(
          (NoteRecord note) => note.attachment.isDetached,
        ) &&
        snapshot.triggers.isEmpty &&
        snapshot.deliveries.isEmpty,
    'context close detaches all Notes and clears delivery state atomically',
  );
  snapshot.validate();
}

void _testQuotaAndCounterBoundaries() {
  final NoteBody oneByte = NoteBody.fromText('x');
  final NoteBody maximum = NoteBody.fromText(
    _repeat('x', TerminalNoteLimits.maximumBodyUtf8Bytes),
  );
  final Map<TerminalNoteContextId, NoteContextRecord> contexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{};
  for (var context = 0; context < 16; context++) {
    final TerminalNoteContextId contextId = _contextId(context + 1);
    contexts[contextId] = NoteContextRecord(
      id: contextId,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.active,
      revision: BigInt.one,
    );
    for (
      var order = 0;
      order < TerminalNoteLimits.maximumNotesPerAttachedContext;
      order++
    ) {
      final int value =
          context * TerminalNoteLimits.maximumNotesPerAttachedContext +
          order +
          1;
      final NoteId id = _noteId(value);
      notes[id] = NoteRecord(
        id: id,
        attachment: TerminalNoteAttachment.attached(contextId),
        body: maximum,
        color: NoteColorKey.neutral,
        status: NoteStatus.active,
        order: order,
        createdAtUtcMicros: 0,
        updatedAtUtcMicros: 0,
        revision: BigInt.one,
      );
    }
  }
  final TerminalNoteSnapshot full = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: BigInt.one,
    contexts: contexts,
    notes: notes,
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  _expect(
    full.notes.length == TerminalNoteLimits.maximumNotes &&
        full.aggregateBodyUtf8Bytes ==
            TerminalNoteLimits.maximumAggregateBodyUtf8Bytes,
    'simultaneous exact total Note and aggregate body limits are accepted',
  );
  final Map<NoteId, NoteTriggerRecord> maximumTriggers =
      <NoteId, NoteTriggerRecord>{};
  final Map<NoteId, NoteDeliveryRecord> maximumDeliveries =
      <NoteId, NoteDeliveryRecord>{};
  var deliverySequence = BigInt.one;
  for (final NoteId id in notes.keys) {
    maximumTriggers[id] = NoteTriggerRecord(
      noteId: id,
      generation: BigInt.one,
      kind: NoteTriggerKind.onReturn,
      phase: NoteTriggerPhase.due,
      suspendReason: null,
      armedAtRevision: BigInt.one,
    );
    maximumDeliveries[id] = NoteDeliveryRecord(
      noteId: id,
      triggerGeneration: BigInt.one,
      sequence: DeliverySequence(deliverySequence),
    );
    deliverySequence += BigInt.one;
  }
  final TerminalNoteSnapshot allDue = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: deliverySequence,
    contexts: contexts,
    notes: notes,
    triggers: maximumTriggers,
    deliveries: maximumDeliveries,
  );
  _expect(
    allDue.triggers.length == TerminalNoteLimits.maximumTriggers &&
        allDue.deliveries.length == TerminalNoteLimits.maximumDeliveries,
    'exact trigger and delivery record limits are accepted',
  );
  _expectRejectedSame(
    full.createNote(
      id: _noteId(TerminalNoteLimits.maximumNotes + 1),
      contextId: _contextId(1),
      body: oneByte.value,
      color: NoteColorKey.neutral,
      utcMicros: 1,
      expectedStoreRevision: full.storeRevision,
    ),
    full,
    TerminalNoteMutationFailure.capacityExceeded,
    'total/per-context/aggregate capacity plus one does not evict records',
  );

  final Map<TerminalNoteContextId, NoteContextRecord> resolvedContexts =
      Map<TerminalNoteContextId, NoteContextRecord>.of(contexts)
        ..[_contextId(17)] = NoteContextRecord(
          id: _contextId(17),
          kind: TerminalNoteContextKind.standard,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        );
  final Map<NoteId, NoteRecord> resolvedNotes = <NoteId, NoteRecord>{
    for (final MapEntry<NoteId, NoteRecord> entry in notes.entries)
      entry.key: entry.value.copyWith(status: NoteStatus.resolved),
  };
  final TerminalNoteSnapshot resolvedFull = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: BigInt.one,
    contexts: resolvedContexts,
    notes: resolvedNotes,
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  _expectRejectedSame(
    resolvedFull.createNote(
      id: _noteId(TerminalNoteLimits.maximumNotes + 1),
      contextId: _contextId(17),
      body: 'x',
      color: NoteColorKey.neutral,
      utcMicros: 1,
      expectedStoreRevision: resolvedFull.storeRevision,
    ),
    resolvedFull,
    TerminalNoteMutationFailure.capacityExceeded,
    'resolved Notes still count toward capacity and are never auto-evicted',
  );

  final Map<NoteId, NoteRecord> tooManyInContext =
      Map<NoteId, NoteRecord>.of(notes)
        ..[_noteId(TerminalNoteLimits.maximumNotes + 1)] = NoteRecord(
          id: _noteId(TerminalNoteLimits.maximumNotes + 1),
          attachment: TerminalNoteAttachment.attached(_contextId(1)),
          body: oneByte,
          color: NoteColorKey.neutral,
          status: NoteStatus.active,
          order: TerminalNoteLimits.maximumNotesPerAttachedContext,
          createdAtUtcMicros: 0,
          updatedAtUtcMicros: 0,
          revision: BigInt.one,
        );
  _expectThrowsValidation(
    () => TerminalNoteSnapshot.fromRecords(
      storeRevision: BigInt.one,
      nextDeliverySequence: BigInt.one,
      contexts: contexts,
      notes: tooManyInContext,
      triggers: const <NoteId, NoteTriggerRecord>{},
      deliveries: const <NoteId, NoteDeliveryRecord>{},
    ),
    TerminalNoteValidationFailure.invariantViolation,
    'per-context and total record limit plus one is rejected on restore',
  );

  final Map<TerminalNoteContextId, NoteContextRecord> maximumContexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  for (var value = 1; value <= TerminalNoteLimits.maximumContexts; value++) {
    final TerminalNoteContextId id = _contextId(value);
    maximumContexts[id] = NoteContextRecord(
      id: id,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.active,
      revision: BigInt.one,
    );
  }
  final TerminalNoteSnapshot contextFull = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: BigInt.one,
    contexts: maximumContexts,
    notes: const <NoteId, NoteRecord>{},
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  _expectRejectedSame(
    contextFull.createContext(
      id: _contextId(TerminalNoteLimits.maximumContexts + 1),
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: contextFull.storeRevision,
    ),
    contextFull,
    TerminalNoteMutationFailure.capacityExceeded,
    'context limit plus one is rejected without mutation',
  );

  final TerminalNoteSnapshot exhausted = TerminalNoteSnapshot.fromRecords(
    storeRevision: TerminalNoteLimits.maximumUnsigned64,
    nextDeliverySequence: BigInt.one,
    contexts: <TerminalNoteContextId, NoteContextRecord>{
      _contextId(1): NoteContextRecord(
        id: _contextId(1),
        kind: TerminalNoteContextKind.standard,
        state: TerminalNoteContextState.active,
        revision: BigInt.one,
      ),
    },
    notes: const <NoteId, NoteRecord>{},
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  _expectRejectedSame(
    exhausted.createNote(
      id: _noteId(1),
      contextId: _contextId(1),
      body: 'x',
      color: NoteColorKey.neutral,
      utcMicros: 0,
      expectedStoreRevision: exhausted.storeRevision,
    ),
    exhausted,
    TerminalNoteMutationFailure.counterExhausted,
    'unsigned store revision exhaustion is read-only',
  );

  final NoteId deliveryId = _noteId(1);
  final NoteTriggerRecord armed = NoteTriggerRecord(
    noteId: deliveryId,
    generation: BigInt.one,
    kind: NoteTriggerKind.onReturn,
    phase: NoteTriggerPhase.onReturnArmedAway,
    suspendReason: null,
    armedAtRevision: BigInt.one,
  );
  final TerminalNoteSnapshot deliveryExhausted =
      TerminalNoteSnapshot.fromRecords(
        storeRevision: BigInt.one,
        nextDeliverySequence: TerminalNoteLimits.maximumUnsigned64,
        contexts: <TerminalNoteContextId, NoteContextRecord>{
          _contextId(1): NoteContextRecord(
            id: _contextId(1),
            kind: TerminalNoteContextKind.standard,
            state: TerminalNoteContextState.active,
            revision: BigInt.one,
          ),
        },
        notes: <NoteId, NoteRecord>{
          deliveryId: NoteRecord(
            id: deliveryId,
            attachment: TerminalNoteAttachment.attached(_contextId(1)),
            body: oneByte,
            color: NoteColorKey.neutral,
            status: NoteStatus.active,
            order: 0,
            createdAtUtcMicros: 0,
            updatedAtUtcMicros: 0,
            revision: BigInt.one,
          ),
        },
        triggers: <NoteId, NoteTriggerRecord>{deliveryId: armed},
        deliveries: const <NoteId, NoteDeliveryRecord>{},
      );
  _expectRejectedSame(
    deliveryExhausted.observeEligibleFocus(
      contextId: _contextId(1),
      isEligible: true,
      expectedStoreRevision: deliveryExhausted.storeRevision,
    ),
    deliveryExhausted,
    TerminalNoteMutationFailure.counterExhausted,
    'delivery sequence overflow rejects the whole transition',
  );
}

void _testOnReturnReviewVectors() {
  TerminalNoteSnapshot snapshot = _oneNoteSnapshot();
  snapshot = _accept(
    snapshot.armOnReturn(
      noteId: _noteId(1),
      isEligible: true,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(_noteId(1))!.revision,
    ),
  );
  final BigInt armedRevision = snapshot.storeRevision;
  final TerminalNoteMutationResult sameVisit = snapshot.observeEligibleFocus(
    contextId: _contextId(1),
    isEligible: true,
    expectedStoreRevision: snapshot.storeRevision,
  );
  _expect(
    sameVisit.disposition == TerminalNoteMutationDisposition.noChange &&
        identical(sameVisit.snapshot, snapshot) &&
        snapshot.triggerFor(_noteId(1))!.phase ==
            NoteTriggerPhase.onReturnArmedHere,
    'F1 same-pane Note UI activity does not create an away/return edge',
  );
  snapshot = _accept(
    snapshot.observeEligibleFocus(
      contextId: _contextId(1),
      isEligible: false,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.observeEligibleFocus(
      contextId: _contextId(1),
      isEligible: true,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  _expect(
    snapshot.storeRevision == armedRevision + BigInt.from(2) &&
        snapshot.deliveryFor(_noteId(1)) != null &&
        snapshot.projectionFor(_contextId(1)).dueCount == 1,
    'F2 one away-to-return edge creates one durable due delivery',
  );
  final TerminalNoteMutationResult duplicate = snapshot.observeEligibleFocus(
    contextId: _contextId(1),
    isEligible: true,
    expectedStoreRevision: snapshot.storeRevision,
  );
  _expect(
    duplicate.disposition == TerminalNoteMutationDisposition.noChange &&
        snapshot.deliveries.length == 1,
    'F2 duplicate focus notification creates no duplicate delivery',
  );

  TerminalNoteSnapshot restored = _oneNoteSnapshot();
  restored = _accept(
    restored.armOnReturn(
      noteId: _noteId(1),
      isEligible: false,
      expectedStoreRevision: restored.storeRevision,
      expectedNoteRevision: restored.noteFor(_noteId(1))!.revision,
    ),
  );
  restored = _accept(
    restored.observeEligibleFocus(
      contextId: _contextId(1),
      isEligible: true,
      expectedStoreRevision: restored.storeRevision,
    ),
  );
  _expect(
    restored.deliveries.length == 1,
    'F3 restored armed-away context is due on first eligible visit',
  );

  TerminalNoteSnapshot closed = _oneNoteSnapshot();
  closed = _accept(
    closed.armOnReturn(
      noteId: _noteId(1),
      isEligible: true,
      expectedStoreRevision: closed.storeRevision,
      expectedNoteRevision: closed.noteFor(_noteId(1))!.revision,
    ),
  );
  closed = _accept(
    closed.detachContext(
      contextId: _contextId(1),
      reason: TerminalNoteDetachReason.paneClosed,
      updatedAtUtcMicros: 10,
      expectedStoreRevision: closed.storeRevision,
      expectedContextRevision: closed.contextFor(_contextId(1))!.revision,
    ),
  );
  _expect(
    closed.noteFor(_noteId(1))!.attachment.isDetached &&
        closed.triggers.isEmpty &&
        closed.deliveries.isEmpty,
    'F4 closing an armed context detaches the Note and clears the trigger',
  );
}

void _testAtNextPromptReviewVectors() {
  final NoteTriggerRuntimeBinding binding = _binding(1);

  TerminalNoteSnapshot p1 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  p1 = _accept(
    p1.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.promptBegins,
        TerminalNotePromptAction.primaryInputReady,
      ]),
      expectedStoreRevision: p1.storeRevision,
    ),
  );
  _expect(p1.deliveries.length == 1, 'P1 C D A B becomes due at B');

  TerminalNoteSnapshot p2 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.commandOutput,
  );
  p2 = _accept(
    p2.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.promptBegins,
        TerminalNotePromptAction.primaryInputReady,
      ]),
      expectedStoreRevision: p2.storeRevision,
    ),
  );
  _expect(
    p2.deliveries.length == 1,
    'P2 arm during command output begins by waiting for D',
  );

  TerminalNoteSnapshot p3 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  p3 = _apply(
    p3.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.promptBegins,
        TerminalNotePromptAction.primaryInputReady,
      ]),
      expectedStoreRevision: p3.storeRevision,
    ),
  );
  _expect(
    p3.deliveries.isEmpty &&
        p3.triggerFor(_noteId(1))!.phase ==
            NoteTriggerPhase.atNextPromptWaitingCommand,
    'P3 the current prompt does not satisfy a newly armed trigger',
  );
  p3 = _accept(
    p3.observePromptEvents(
      contextId: _contextId(1),
      binding: binding.copyWith(lastEventSequence: BigInt.zero),
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.freshPromptBegins,
        TerminalNotePromptAction.primaryInputReady,
      ], firstSequence: 3),
      expectedStoreRevision: p3.storeRevision,
    ),
  );
  _expect(p3.deliveries.length == 1, 'P3 a later full cycle becomes due');

  TerminalNoteSnapshot p4 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  p4 = _accept(
    p4.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
      ]),
      expectedStoreRevision: p4.storeRevision,
    ),
  );
  p4 = _accept(
    p4.suspendAtNextPrompt(
      contextId: _contextId(1),
      reason: NoteTriggerSuspendReason.sessionEnded,
      expectedStoreRevision: p4.storeRevision,
      matchingBinding: binding,
    ),
  );
  _expect(
    p4.triggerFor(_noteId(1))!.phase == NoteTriggerPhase.suspended &&
        p4.deliveries.isEmpty,
    'P4 a session generation change suspends instead of transferring',
  );

  TerminalNoteSnapshot p5 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  p5 = _accept(
    p5.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.promptBegins,
        TerminalNotePromptAction.secondaryPrompt,
        TerminalNotePromptAction.primaryInputReady,
      ]),
      expectedStoreRevision: p5.storeRevision,
    ),
  );
  _expect(
    p5.deliveries.length == 1,
    'P5 secondary prompt does not qualify or break primary A-to-B',
  );

  TerminalNoteSnapshot p6 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  p6 = _accept(
    p6.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.promptBegins,
        TerminalNotePromptAction.primaryInputReady,
      ]),
      expectedStoreRevision: p6.storeRevision,
    ),
  );
  final BigInt dueRevision = p6.storeRevision;
  _expect(
    p6.projectionFor(_contextId(1)).dueCount == 1 &&
        p6.storeRevision == dueRevision,
    'P6 due is retained without a presentation acknowledgement',
  );

  TerminalNoteSnapshot p7 = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  final TerminalNoteMutationResult mismatch = p7.observePromptEvents(
    contextId: _contextId(1),
    binding: _binding(2),
    events: _events(<TerminalNotePromptAction>[
      TerminalNotePromptAction.commandOutputBegins,
      TerminalNotePromptAction.commandEnds,
      TerminalNotePromptAction.promptBegins,
      TerminalNotePromptAction.primaryInputReady,
    ]),
    expectedStoreRevision: p7.storeRevision,
  );
  _expect(
    mismatch.disposition == TerminalNoteMutationDisposition.noChange &&
        mismatch.snapshot.deliveries.isEmpty,
    'P7 mismatched integration binding is ignored without false delivery',
  );

  final TerminalNoteMutationResult unavailable = _oneNoteSnapshot()
      .armAtNextPrompt(
        noteId: _noteId(1),
        capability: TerminalNotePromptCapability.probing,
        currentSemanticState: TerminalNoteSemanticState.prompt,
        binding: binding,
        expectedStoreRevision: BigInt.from(2),
        expectedNoteRevision: BigInt.one,
      );
  _expectRejectedSame(
    unavailable,
    unavailable.snapshot,
    TerminalNoteMutationFailure.capabilityUnavailable,
    'available is the only capability that admits S3 arming',
  );
}

void _testDuplicateResetOverflowAndCombinedOrdering() {
  final NoteTriggerRuntimeBinding binding = _binding(1);
  TerminalNoteSnapshot snapshot = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  snapshot = _accept(
    snapshot.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
      ]),
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  final BigInt afterC = snapshot.storeRevision;
  final TerminalNoteMutationResult duplicate = snapshot.observePromptEvents(
    contextId: _contextId(1),
    binding: binding,
    events: _events(<TerminalNotePromptAction>[
      TerminalNotePromptAction.commandOutputBegins,
    ]),
    expectedStoreRevision: snapshot.storeRevision,
  );
  _expect(
    duplicate.disposition == TerminalNoteMutationDisposition.noChange &&
        duplicate.snapshot.storeRevision == afterC,
    'duplicate event sequence is an exact no-op',
  );
  snapshot = _accept(
    snapshot.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.primaryInputReady,
      ], firstSequence: 2),
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  _expect(
    snapshot.triggerFor(_noteId(1))!.phase ==
            NoteTriggerPhase.atNextPromptWaitingCommand &&
        snapshot.deliveries.isEmpty,
    'out-of-order input-ready resets the candidate to waitingCommand',
  );

  TerminalNoteSnapshot overflow = _armPrompt(
    _oneNoteSnapshot(),
    binding,
    TerminalNoteSemanticState.prompt,
  );
  overflow = _accept(
    overflow.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: List<TerminalNotePromptEvent>.generate(
        TerminalNoteLimits.maximumPromptEventsPerBatch + 1,
        (int index) => TerminalNotePromptEvent(
          sequence: BigInt.from(index + 1),
          action: TerminalNotePromptAction.commandOutputBegins,
        ),
      ),
      expectedStoreRevision: overflow.storeRevision,
    ),
  );
  _expect(
    overflow.triggerFor(_noteId(1))!.phase == NoteTriggerPhase.suspended &&
        overflow.triggerFor(_noteId(1))!.suspendReason ==
            NoteTriggerSuspendReason.eventOverflow &&
        overflow.deliveries.isEmpty,
    '33-event prompt batch atomically suspends with no inferred delivery',
  );

  TerminalNoteSnapshot combined = _threeNoteSnapshot();
  combined = _accept(
    combined.armOnReturn(
      noteId: _noteId(3),
      isEligible: false,
      expectedStoreRevision: combined.storeRevision,
      expectedNoteRevision: combined.noteFor(_noteId(3))!.revision,
    ),
  );
  combined = _accept(
    combined.armOnReturn(
      noteId: _noteId(2),
      isEligible: false,
      expectedStoreRevision: combined.storeRevision,
      expectedNoteRevision: combined.noteFor(_noteId(2))!.revision,
    ),
  );
  combined = _armPrompt(
    combined,
    binding,
    TerminalNoteSemanticState.prompt,
    noteId: _noteId(1),
  );
  combined = _accept(
    combined.observePromptEvents(
      contextId: _contextId(1),
      binding: binding,
      events: _events(<TerminalNotePromptAction>[
        TerminalNotePromptAction.commandOutputBegins,
        TerminalNotePromptAction.commandEnds,
        TerminalNotePromptAction.promptBegins,
      ]),
      expectedStoreRevision: combined.storeRevision,
    ),
  );
  final BigInt beforeCombined = combined.storeRevision;
  combined = _accept(
    combined.observeLifecycleBatch(
      contextId: _contextId(1),
      expectedStoreRevision: combined.storeRevision,
      isEligible: true,
      promptBinding: binding,
      promptEvents: <TerminalNotePromptEvent>[
        TerminalNotePromptEvent(
          sequence: BigInt.from(4),
          action: TerminalNotePromptAction.primaryInputReady,
        ),
      ],
    ),
  );
  final TerminalNoteContextProjection projection = combined.projectionFor(
    _contextId(1),
  );
  _expect(
    combined.storeRevision == beforeCombined + BigInt.one &&
        projection.dueCount == 3 &&
        projection.orderedNotes
                .map((NoteRecord note) => note.id.canonicalValue)
                .join(',') ==
            <NoteId>[
              _noteId(1),
              _noteId(2),
              _noteId(3),
            ].map((NoteId id) => id.canonicalValue).join(',') &&
        combined.deliveries.values
                .map((NoteDeliveryRecord delivery) => delivery.sequence.value)
                .toSet()
                .length ==
            3,
    'C1 coalesces S2/S3 due records in one revision with stable ID FIFO',
  );
  final BigInt generation = combined.triggerFor(_noteId(1))!.generation;
  combined = _accept(
    combined.acknowledgePresentation(
      noteId: _noteId(1),
      triggerGeneration: generation,
      expectedStoreRevision: combined.storeRevision,
    ),
  );
  _expect(
    combined.noteFor(_noteId(1))!.status == NoteStatus.active &&
        combined.triggerFor(_noteId(1)) == null &&
        combined.deliveryFor(_noteId(1)) == null,
    'presentation acknowledgement consumes only trigger/delivery state',
  );
  final TerminalNoteMutationResult duplicateAck = combined
      .acknowledgePresentation(
        noteId: _noteId(1),
        triggerGeneration: generation,
        expectedStoreRevision: combined.storeRevision,
      );
  _expect(
    duplicateAck.disposition == TerminalNoteMutationDisposition.noChange &&
        identical(duplicateAck.snapshot, combined),
    'duplicate presentation acknowledgement is an exact no-op',
  );
  combined = _accept(
    combined.armOnReturn(
      noteId: _noteId(1),
      isEligible: true,
      expectedStoreRevision: combined.storeRevision,
      expectedNoteRevision: combined.noteFor(_noteId(1))!.revision,
    ),
  );
  _expect(
    combined.triggerFor(_noteId(1))!.generation > generation,
    'explicit re-arm always advances the per-Note trigger generation',
  );
}

void _testPrivacyAndDependencySentinel() {
  const String bodySentinel = 'PRIVATE_BODY_SENTINEL_9347';
  const String idSentinel = 'deadbeefdeadbeefdeadbeefdeadbeef';
  Object? error;
  try {
    NoteBody.fromText('$bodySentinel\u0000');
  } on Object catch (caught) {
    error = caught;
  }
  final TerminalNoteSnapshot snapshot = _oneNoteSnapshot();
  final TerminalNoteMutationResult duplicate = snapshot.createNote(
    id: NoteId.fromHex(idSentinel),
    contextId: _contextId(1),
    body: bodySentinel,
    color: NoteColorKey.neutral,
    utcMicros: 0,
    expectedStoreRevision: snapshot.storeRevision - BigInt.one,
  );
  final String diagnostic = '$error $duplicate ${NoteId.fromHex(idSentinel)}';
  _expect(
    !diagnostic.contains(bodySentinel) && !diagnostic.contains(idSentinel),
    'validation and mutation diagnostics never echo body or persistent ID',
  );

  final String source = File('lib/src/terminal_note_model.dart')
      .readAsStringSync();
  for (final String forbidden in <String>[
    "import 'dart:io'",
    'dart_appkit',
    'dart_pty',
    'ArgumentError.value',
  ]) {
    _expect(
      !source.contains(forbidden),
      'pure model source excludes I/O, native, PTY, and value-echoing errors',
    );
  }
}

void _testFixedSeedStateSequences() {
  final String first = _runFixedSequence(0x5eed1234, 10000);
  final String second = _runFixedSequence(0x5eed1234, 10000);
  _expect(
    first == second,
    'fixed-seed 10,000-step mutation sequence is deterministic',
  );
}

String _runFixedSequence(int seed, int steps) {
  var random = seed;
  int nextRandom() {
    random = (random * 1664525 + 1013904223) & 0xffffffff;
    return random;
  }

  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: _contextId(1),
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  var nextIdentity = 1;
  final List<NoteId> live = <NoteId>[];
  final NoteTriggerRuntimeBinding binding = _binding(1);
  for (var step = 0; step < steps; step++) {
    final int operation = nextRandom() % 12;
    TerminalNoteMutationResult result;
    final int now = step + 1;
    if ((operation == 0 || live.isEmpty) && live.length < 16) {
      final NoteId id = _noteId(nextIdentity++);
      result = snapshot.createNote(
        id: id,
        contextId: _contextId(1),
        body: 'state $step',
        color: NoteColorKey.values[nextRandom() % NoteColorKey.values.length],
        utcMicros: now,
        expectedStoreRevision: snapshot.storeRevision,
      );
      if (result.isAccepted) live.add(id);
    } else {
      final NoteId id = live[nextRandom() % live.length];
      final NoteRecord note = snapshot.noteFor(id)!;
      switch (operation) {
        case 1:
          result = snapshot.editNote(
            noteId: id,
            body: 'edited $step',
            color:
                NoteColorKey.values[nextRandom() % NoteColorKey.values.length],
            updatedAtUtcMicros: now,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 2:
          result = note.status == NoteStatus.active
              ? snapshot.resolveNote(
                  noteId: id,
                  updatedAtUtcMicros: now,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                )
              : snapshot.reopenNote(
                  noteId: id,
                  updatedAtUtcMicros: now,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                );
        case 3:
          result = note.attachment.isAttached
              ? snapshot.detachNote(
                  noteId: id,
                  reason: TerminalNoteDetachReason.explicitDetach,
                  updatedAtUtcMicros: now,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                )
              : snapshot.reattachNote(
                  noteId: id,
                  contextId: _contextId(1),
                  updatedAtUtcMicros: now,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                );
        case 4:
          result = snapshot.armOnReturn(
            noteId: id,
            isEligible: nextRandom().isEven,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 5:
          result = snapshot.observeEligibleFocus(
            contextId: _contextId(1),
            isEligible: nextRandom().isEven,
            expectedStoreRevision: snapshot.storeRevision,
          );
        case 6:
          result = snapshot.armAtNextPrompt(
            noteId: id,
            capability: TerminalNotePromptCapability.available,
            currentSemanticState: TerminalNoteSemanticState
                .values[nextRandom() % TerminalNoteSemanticState.values.length],
            binding: binding,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 7:
          result = snapshot.observePromptEvents(
            contextId: _contextId(1),
            binding: binding,
            events: <TerminalNotePromptEvent>[
              TerminalNotePromptEvent(
                sequence: BigInt.from(step + 1),
                action:
                    TerminalNotePromptAction.values[nextRandom() %
                        TerminalNotePromptAction.values.length],
              ),
            ],
            expectedStoreRevision: snapshot.storeRevision,
          );
        case 8:
          final NoteDeliveryRecord? delivery = snapshot.deliveryFor(id);
          result = delivery == null
              ? snapshot.cancelTrigger(
                  noteId: id,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                )
              : snapshot.acknowledgePresentation(
                  noteId: id,
                  triggerGeneration: delivery.triggerGeneration,
                  expectedStoreRevision: snapshot.storeRevision,
                );
        case 9:
          final List<NoteId> attached =
              snapshot.notes.values
                  .where(
                    (NoteRecord candidate) =>
                        candidate.attachment.contextId == _contextId(1),
                  )
                  .map((NoteRecord candidate) => candidate.id)
                  .toList()
                ..sort((NoteId left, NoteId right) => left.compareTo(right));
          if (attached.length > 1 && nextRandom().isEven) {
            final NoteId first = attached.removeAt(0);
            attached.add(first);
          }
          result = snapshot.reorderAttachedNotes(
            contextId: _contextId(1),
            orderedNoteIds: attached,
            updatedAtUtcMicros: now,
            expectedStoreRevision: snapshot.storeRevision,
          );
        case 10:
          result = snapshot.editNote(
            noteId: id,
            body: 'stale $step',
            color: note.color,
            updatedAtUtcMicros: now,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision + BigInt.one,
          );
        default:
          result = snapshot.deleteNote(
            noteId: id,
            updatedAtUtcMicros: now,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
          if (result.isAccepted) live.remove(id);
      }
    }
    if (result.disposition == TerminalNoteMutationDisposition.rejected) {
      _expect(
        identical(result.snapshot, snapshot),
        'rejected random mutation preserves snapshot identity',
      );
    }
    snapshot = result.snapshot;
    snapshot.validate();
  }
  final List<NoteRecord> records = snapshot.notes.values.toList()
    ..sort((NoteRecord left, NoteRecord right) => left.id.compareTo(right.id));
  return <Object>[
    snapshot.storeRevision,
    snapshot.nextDeliverySequence,
    snapshot.contexts.length,
    snapshot.notes.length,
    snapshot.triggers.length,
    snapshot.deliveries.length,
    for (final NoteRecord note in records) ...<Object>[
      note.id.canonicalValue,
      note.revision,
      note.status.name,
      note.attachment.kind.name,
      note.order,
      note.body.value,
    ],
  ].join('|');
}

TerminalNoteSnapshot _oneNoteSnapshot() {
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: _contextId(1),
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  return _accept(
    snapshot.createNote(
      id: _noteId(1),
      contextId: _contextId(1),
      body: 'one',
      color: NoteColorKey.yellow,
      utcMicros: 0,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
}

TerminalNoteSnapshot _threeNoteSnapshot() {
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: _contextId(1),
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  for (var value = 1; value <= 3; value++) {
    snapshot = _accept(
      snapshot.createNote(
        id: _noteId(value),
        contextId: _contextId(1),
        body: 'note $value',
        color: NoteColorKey.yellow,
        utcMicros: 0,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
  }
  return snapshot;
}

TerminalNoteSnapshot _armPrompt(
  TerminalNoteSnapshot snapshot,
  NoteTriggerRuntimeBinding binding,
  TerminalNoteSemanticState state, {
  NoteId? noteId,
}) {
  final NoteId id = noteId ?? _noteId(1);
  return _accept(
    snapshot.armAtNextPrompt(
      noteId: id,
      capability: TerminalNotePromptCapability.available,
      currentSemanticState: state,
      binding: binding,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(id)!.revision,
    ),
  );
}

List<TerminalNotePromptEvent> _events(
  List<TerminalNotePromptAction> actions, {
  int firstSequence = 1,
}) => <TerminalNotePromptEvent>[
  for (var index = 0; index < actions.length; index++)
    TerminalNotePromptEvent(
      sequence: BigInt.from(firstSequence + index),
      action: actions[index],
    ),
];

NoteTriggerRuntimeBinding _binding(int value) => NoteTriggerRuntimeBinding(
  sessionGeneration: BigInt.from(value),
  instanceId: _instanceId(value),
  semanticGeneration: BigInt.from(value),
  lastEventSequence: BigInt.zero,
);

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalNoteContextId _contextId(int value) => TerminalNoteContextId.fromHex(
  (0x100000 + value).toRadixString(16).padLeft(32, '0'),
);

ShellIntegrationInstanceId _instanceId(int value) =>
    ShellIntegrationInstanceId.fromHex(
      (0x200000 + value).toRadixString(16).padLeft(32, '0'),
    );

String _repeat(String value, int count) =>
    List<String>.filled(count, value, growable: false).join();

TerminalNoteSnapshot _accept(TerminalNoteMutationResult result) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.accepted,
    'mutation is durably accepted',
  );
  return result.snapshot;
}

TerminalNoteSnapshot _apply(TerminalNoteMutationResult result) {
  _expect(result.isAccepted, 'persistent or runtime-only transition applies');
  return result.snapshot;
}

void _expectRejectedSame(
  TerminalNoteMutationResult result,
  TerminalNoteSnapshot original,
  TerminalNoteMutationFailure failure,
  String description,
) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.rejected &&
        result.failure == failure &&
        identical(result.snapshot, original),
    description,
  );
}

void _expectThrowsValidation(
  void Function() callback,
  TerminalNoteValidationFailure failure,
  String description,
) {
  try {
    callback();
  } on TerminalNoteValidationException catch (error) {
    _expect(error.failure == failure, description);
    return;
  }
  throw StateError('expected TerminalNoteValidationException: $description');
}

void _expectThrowsUnsupported(void Function() callback, String description) {
  try {
    callback();
  } on UnsupportedError {
    return;
  }
  throw StateError('expected UnsupportedError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
