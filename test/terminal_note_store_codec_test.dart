import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_sha256.dart';

void main() => runTerminalNoteStoreCodecTests();

void runTerminalNoteStoreCodecTests() {
  _testCanonicalEnvelopeAndRoundTrip();
  _testStrictInputRejection();
  _testWaitingTriggerLoadAndMigration();
  _testRestorationBindingBoundaries();
  _testDeletionJournalBoundaries();
  _testRecordAndCounterBoundaries();
  _testHardCapacityFixtures();
  _testFileLimitAndArbitraryBytes();
  _testFixedSeedMutationRoundTrips();
  _testPrivacyAndDependencyBoundary();
}

void _testCanonicalEnvelopeAndRoundTrip() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final String emptyPayload =
      '{"storeRevision":0,"nextDeliverySequence":1,"contexts":[],"notes":[],"triggers":[],"deliveries":[],"restorationBinding":null}';
  final String emptyChecksum = terminalSha256(utf8.encode(emptyPayload));
  final String expectedEmpty =
      '{"format":"dart-terminal-notes","version":1,"payloadSha256":"$emptyChecksum","payload":$emptyPayload}\n';
  final Uint8List encodedEmpty = codec.encode(
    TerminalNoteStoreDocument(snapshot: TerminalNoteSnapshot.empty()),
  );
  _expect(
    utf8.decode(encodedEmpty) == expectedEmpty,
    'empty store has exact field order, integer form, checksum, and one LF',
  );

  final TerminalNoteStoreDocument source = _sampleDocument();
  final Uint8List first = codec.encode(source);
  final Uint8List second = codec.encode(source);
  _expectBytesEqual(first, second, 'same document has byte-identical output');
  _expect(
    first.last == 0x0a && first[first.length - 2] != 0x0a,
    'store has exactly one trailing LF',
  );

  final String text = utf8.decode(first);
  _expectOrdered(text, <String>[
    '"storeRevision"',
    '"nextDeliverySequence"',
    '"contexts"',
    '"notes"',
    '"triggers"',
    '"deliveries"',
    '"restorationBinding"',
  ], 'payload fields use the frozen order');
  _expect(
    text.indexOf(_contextId(1).canonicalValue) <
            text.indexOf(_contextId(2).canonicalValue) &&
        text.indexOf(_noteId(1).canonicalValue) <
            text.indexOf(_noteId(2).canonicalValue),
    'record arrays are ordered by canonical persistent identity',
  );

  final TerminalNoteStoreDocument decoded = codec.decode(first);
  _expectBytesEqual(
    codec.encode(decoded),
    first,
    'decode and re-encode preserves canonical bytes',
  );
  _expect(
    decoded.restorationBinding!.paneContextIds[0] == _contextId(2) &&
        decoded.restorationBinding!.paneContextIds[1] == _contextId(1),
    'restoration pane traversal order is preserved rather than sorted',
  );
  _expect(
    decoded.snapshot.deliveryFor(_noteId(2))!.sequence.value == BigInt.one &&
        decoded.snapshot.noteFor(_noteId(3))!.attachment.isDetached,
    'delivery and detached attachment variants round-trip',
  );
}

void _testStrictInputRejection() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final Uint8List canonical = codec.encode(_sampleDocument());
  final String source = utf8.decode(canonical);

  _expectThrowsCodec(
    () => codec.decode(
      utf8.encode(
        source.replaceFirst(
          '"format":"dart-terminal-notes",',
          '"format":"dart-terminal-notes","format":"dart-terminal-notes",',
        ),
      ),
    ),
    TerminalNoteCodecFailure.duplicateKey,
    'duplicate root key is rejected before map overwrite',
  );
  final String firstContextId = _contextId(1).canonicalValue;
  _expectThrowsCodec(
    () => codec.decode(
      utf8.encode(
        source.replaceFirst(
          '"id":"$firstContextId",',
          '"id":"$firstContextId","id":"$firstContextId",',
        ),
      ),
    ),
    TerminalNoteCodecFailure.duplicateKey,
    'duplicate entity key is rejected before schema decode',
  );

  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        root: (Map<String, dynamic> root) {
          root['unknown'] = true;
        },
      ),
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'unknown root field is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        payload: (Map<String, dynamic> payload) {
          payload['unknown'] = true;
        },
      ),
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'unknown payload field is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        payload: (Map<String, dynamic> payload) {
          final List<dynamic> notes = payload['notes'] as List<dynamic>;
          (notes.first as Map<String, dynamic>)['unknown'] = true;
        },
      ),
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'unknown entity field is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        payload: (Map<String, dynamic> payload) {
          (payload['contexts'] as List<dynamic>).reverseRangeForTest();
        },
      ),
    ),
    TerminalNoteCodecFailure.nonCanonical,
    'out-of-order context array is rejected',
  );

  _expectThrowsCodec(
    () => codec.decode(utf8.encode(source.substring(0, source.length - 1))),
    TerminalNoteCodecFailure.nonCanonical,
    'missing trailing LF is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(utf8.encode('$source\n')),
    TerminalNoteCodecFailure.nonCanonical,
    'a second trailing LF is rejected as trailing data',
  );
  _expectThrowsCodec(
    () => codec.decode(
      utf8.encode('${source.substring(0, source.length - 1)} \n'),
    ),
    TerminalNoteCodecFailure.nonCanonical,
    'otherwise-valid JSON whitespace is not canonical',
  );
  _expectThrowsCodec(
    () => codec.decode(
      utf8.encode(
        source.replaceFirst(
          'dart-terminal-notes',
          r'dart\u002dterminal\u002dnotes',
        ),
      ),
    ),
    TerminalNoteCodecFailure.nonCanonical,
    'equivalent escaped string spelling is not canonical',
  );
  _expectThrowsCodec(
    () => codec.decode(<int>[0xff, 0x0a]),
    TerminalNoteCodecFailure.invalidUtf8,
    'invalid UTF-8 is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(utf8.encode('{"format":\n')),
    TerminalNoteCodecFailure.malformedJson,
    'malformed JSON is rejected with a fixed class',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        root: (Map<String, dynamic> root) {
          root['payloadSha256'] = _repeat('0', 64);
        },
        refreshChecksum: false,
      ),
    ),
    TerminalNoteCodecFailure.checksumMismatch,
    'checksum mismatch is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        root: (Map<String, dynamic> root) {
          root['format'] = 'other';
        },
        refreshChecksum: false,
      ),
    ),
    TerminalNoteCodecFailure.unknownFormat,
    'unknown store format is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        root: (Map<String, dynamic> root) {
          root['version'] = 2;
        },
        refreshChecksum: false,
      ),
    ),
    TerminalNoteCodecFailure.upgradeRequired,
    'newer version is rejected before checksum or payload interpretation',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        root: (Map<String, dynamic> root) {
          root['version'] = 0;
        },
        refreshChecksum: false,
      ),
    ),
    TerminalNoteCodecFailure.migrationUnavailable,
    'older version without a registered step is not guessed',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        payload: (Map<String, dynamic> payload) {
          final List<dynamic> notes = payload['notes'] as List<dynamic>;
          (notes.first as Map<String, dynamic>)['color'] = 'orange';
        },
      ),
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'unknown enum is rejected rather than mapped to a fallback',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        canonical,
        payload: (Map<String, dynamic> payload) {
          final List<dynamic> notes = payload['notes'] as List<dynamic>;
          (notes.first as Map<String, dynamic>)['body'] = 'line one\rline two';
        },
      ),
    ),
    TerminalNoteCodecFailure.nonCanonical,
    'persisted body must already use normalized LF newlines',
  );
}

void _testWaitingTriggerLoadAndMigration() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteContextId contextId = _contextId(20);
  final NoteId noteId = _noteId(20);
  final TerminalNoteSnapshot waiting = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.from(3),
    nextDeliverySequence: BigInt.one,
    contexts: <TerminalNoteContextId, NoteContextRecord>{
      contextId: NoteContextRecord(
        id: contextId,
        kind: TerminalNoteContextKind.standard,
        state: TerminalNoteContextState.active,
        revision: BigInt.one,
      ),
    },
    notes: <NoteId, NoteRecord>{
      noteId: _note(
        noteId,
        TerminalNoteAttachment.attached(contextId),
        'waiting',
      ),
    },
    triggers: <NoteId, NoteTriggerRecord>{
      noteId: NoteTriggerRecord(
        noteId: noteId,
        generation: BigInt.one,
        kind: NoteTriggerKind.atNextPrompt,
        phase: NoteTriggerPhase.atNextPromptWaitingEnd,
        suspendReason: null,
        armedAtRevision: BigInt.from(3),
      ),
    },
    deliveries: const <NoteId, NoteDeliveryRecord>{},
    runtimeBindings: <NoteId, NoteTriggerRuntimeBinding>{
      noteId: NoteTriggerRuntimeBinding(
        sessionGeneration: BigInt.one,
        instanceId: ShellIntegrationInstanceId.fromHex(
          '30000000000000000000000000000001',
        ),
        semanticGeneration: BigInt.one,
        lastEventSequence: BigInt.one,
      ),
    },
  );
  final Uint8List persisted = codec.encode(
    TerminalNoteStoreDocument(snapshot: waiting),
  );
  _expect(
    !utf8.decode(persisted).contains('30000000000000000000000000000001'),
    'memory-only shell instance identity is not persisted',
  );
  final TerminalNoteStoreDocument loaded = codec.decode(persisted);
  final NoteTriggerRecord trigger = loaded.snapshot.triggerFor(noteId)!;
  _expect(
    trigger.phase == NoteTriggerPhase.suspended &&
        trigger.suspendReason == NoteTriggerSuspendReason.sessionEnded &&
        loaded.snapshot.runtimeBindingFor(noteId) == null,
    'waiting S3 trigger becomes suspended(sessionEnded) on load',
  );
  final Uint8List stabilized = codec.encode(loaded);
  _expectBytesEqual(
    codec.encode(codec.decode(stabilized)),
    stabilized,
    'load-time S3 suspension has a stable canonical representation',
  );

  const TerminalNoteStoreMigrator migrator = TerminalNoteStoreMigrator();
  _expectBytesEqual(
    codec.encode(migrator.migrate(stabilized)),
    stabilized,
    'version 1 migration entrypoint is a validated no-op',
  );
  _expectThrowsCodec(
    () => migrator.migrate(stabilized, targetVersion: 2),
    TerminalNoteCodecFailure.migrationUnavailable,
    'migration entrypoint cannot fabricate an unregistered future version',
  );
}

void _testRestorationBindingBoundaries() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final Map<TerminalNoteContextId, NoteContextRecord> contexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  final List<TerminalNoteContextId> ids = <TerminalNoteContextId>[];
  for (
    var index = 0;
    index < TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts;
    index++
  ) {
    final TerminalNoteContextId id = _contextId(100 + index);
    ids.add(id);
    contexts[id] = NoteContextRecord(
      id: id,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.restorable,
      revision: BigInt.one,
    );
  }
  final TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: BigInt.one,
    contexts: contexts,
    notes: const <NoteId, NoteRecord>{},
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  final TerminalNoteStoreDocument exact = TerminalNoteStoreDocument(
    snapshot: snapshot,
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: _repeat('a', 64),
      paneContextIds: ids.reversed,
    ),
  );
  final TerminalNoteStoreDocument decoded = codec.decode(codec.encode(exact));
  _expect(
    decoded.restorationBinding!.paneContextIds.length == 64 &&
        decoded.restorationBinding!.paneContextIds.first == ids.last,
    'exact 64-entry restoration binding is accepted and ordered',
  );
  _expectThrowsCodec(
    () => TerminalNoteRestorationBinding(
      restorationSha256: _repeat('a', 64),
      paneContextIds: <TerminalNoteContextId>[...ids, _contextId(999)],
    ),
    TerminalNoteCodecFailure.schemaViolation,
    '65-entry restoration binding is rejected',
  );
  _expectThrowsCodec(
    () => TerminalNoteRestorationBinding(
      restorationSha256: _repeat('A', 64),
      paneContextIds: const <TerminalNoteContextId>[],
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'restoration checksum must be 64 lowercase hex',
  );
  _expectThrowsCodec(
    () => TerminalNoteRestorationBinding(
      restorationSha256: _repeat('a', 64),
      paneContextIds: <TerminalNoteContextId>[ids.first, ids.first],
    ),
    TerminalNoteCodecFailure.schemaViolation,
    'restoration binding IDs must be unique',
  );
  _expectThrowsCodec(
    () => TerminalNoteStoreDocument(
      snapshot: snapshot,
      restorationBinding: TerminalNoteRestorationBinding(
        restorationSha256: _repeat('a', 64),
        paneContextIds: <TerminalNoteContextId>[_contextId(999)],
      ),
    ),
    TerminalNoteCodecFailure.invariantViolation,
    'restoration binding cannot reference an unknown context',
  );

  final TerminalNoteContextId quickId = _contextId(1000);
  final TerminalNoteSnapshot quickSnapshot = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.one,
    nextDeliverySequence: BigInt.one,
    contexts: <TerminalNoteContextId, NoteContextRecord>{
      quickId: NoteContextRecord(
        id: quickId,
        kind: TerminalNoteContextKind.quickTerminal,
        state: TerminalNoteContextState.active,
        revision: BigInt.one,
      ),
    },
    notes: const <NoteId, NoteRecord>{},
    triggers: const <NoteId, NoteTriggerRecord>{},
    deliveries: const <NoteId, NoteDeliveryRecord>{},
  );
  _expectThrowsCodec(
    () => TerminalNoteStoreDocument(
      snapshot: quickSnapshot,
      restorationBinding: TerminalNoteRestorationBinding(
        restorationSha256: _repeat('a', 64),
        paneContextIds: <TerminalNoteContextId>[quickId],
      ),
    ),
    TerminalNoteCodecFailure.invariantViolation,
    'Quick Terminal context cannot enter a restoration pane binding',
  );
}

void _testDeletionJournalBoundaries() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final List<TerminalNoteDeletionTombstone> entries =
      <TerminalNoteDeletionTombstone>[
        for (
          var index =
              TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries;
          index >= 1;
          index--
        )
          TerminalNoteDeletionTombstone(
            noteId: _noteId(100000 + index),
            deletionRevision: BigInt.from((index % 7) + 1),
          ),
      ];
  final Uint8List encoded = codec.encodeDeletionJournal(
    TerminalNoteDeletionJournal(entries: entries),
  );
  final TerminalNoteDeletionJournal decoded = codec.decodeDeletionJournal(
    encoded,
  );
  _expect(
    decoded.entries.length ==
        TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries,
    'exact deletion journal entry cap is accepted',
  );
  _expectBytesEqual(
    codec.encodeDeletionJournal(decoded),
    encoded,
    'deletion journal canonical ordering is byte stable',
  );
  _expectThrowsCodec(
    () => TerminalNoteDeletionJournal(
      entries: <TerminalNoteDeletionTombstone>[
        ...entries,
        TerminalNoteDeletionTombstone(
          noteId: _noteId(200000),
          deletionRevision: BigInt.one,
        ),
      ],
    ),
    TerminalNoteCodecFailure.limitExceeded,
    'deletion journal cap plus one is rejected',
  );
  _expectThrowsCodec(
    () => TerminalNoteDeletionJournal(
      entries: <TerminalNoteDeletionTombstone>[
        entries.first,
        TerminalNoteDeletionTombstone(
          noteId: entries.first.noteId,
          deletionRevision: BigInt.from(99),
        ),
      ],
    ),
    TerminalNoteCodecFailure.invariantViolation,
    'duplicate deletion identity is rejected',
  );
  _expectThrowsCodec(
    () => codec.decodeDeletionJournal(
      _rewrite(
        encoded,
        payload: (Map<String, dynamic> payload) {
          (payload['entries'] as List<dynamic>).reverseRangeForTest();
        },
      ),
    ),
    TerminalNoteCodecFailure.nonCanonical,
    'out-of-order deletion journal is rejected',
  );
  _expectThrowsCodec(
    () => TerminalNoteDeletionTombstone(
      noteId: _noteId(1),
      deletionRevision: BigInt.zero,
    ),
    TerminalNoteCodecFailure.limitExceeded,
    'zero deletion revision is rejected',
  );
}

void _testRecordAndCounterBoundaries() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final BigInt maximum = TerminalNoteLimits.maximumUnsigned64;
  final TerminalNoteContextId contextId = _contextId(30);
  final NoteId noteId = _noteId(30);
  final TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.fromRecords(
    storeRevision: maximum,
    nextDeliverySequence: maximum,
    contexts: <TerminalNoteContextId, NoteContextRecord>{
      contextId: NoteContextRecord(
        id: contextId,
        kind: TerminalNoteContextKind.standard,
        state: TerminalNoteContextState.active,
        revision: maximum,
      ),
    },
    notes: <NoteId, NoteRecord>{
      noteId: NoteRecord(
        id: noteId,
        attachment: TerminalNoteAttachment.attached(contextId),
        body: NoteBody.fromText(_repeat('x', 4096)),
        color: NoteColorKey.purple,
        status: NoteStatus.active,
        order: 0,
        createdAtUtcMicros: 0,
        updatedAtUtcMicros: 0,
        revision: maximum,
      ),
    },
    triggers: <NoteId, NoteTriggerRecord>{
      noteId: NoteTriggerRecord(
        noteId: noteId,
        generation: maximum,
        kind: NoteTriggerKind.onReturn,
        phase: NoteTriggerPhase.due,
        suspendReason: null,
        armedAtRevision: maximum,
      ),
    },
    deliveries: <NoteId, NoteDeliveryRecord>{
      noteId: NoteDeliveryRecord(
        noteId: noteId,
        triggerGeneration: maximum,
        sequence: DeliverySequence(maximum - BigInt.one),
      ),
    },
  );
  final Uint8List exact = codec.encode(
    TerminalNoteStoreDocument(snapshot: snapshot),
  );
  _expectBytesEqual(
    codec.encode(codec.decode(exact)),
    exact,
    'maximum unsigned counters and exact 4096-byte body round-trip',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _replaceRawPayload(
        exact,
        '"storeRevision":$maximum',
        '"storeRevision":${maximum + BigInt.one}',
      ),
    ),
    TerminalNoteCodecFailure.limitExceeded,
    'unsigned counter maximum plus one is rejected',
  );
  _expectThrowsCodec(
    () => codec.decode(
      _replaceRawPayload(
        exact,
        '"nextDeliverySequence":$maximum',
        '"nextDeliverySequence":0',
      ),
    ),
    TerminalNoteCodecFailure.limitExceeded,
    'positive sequence minimum minus one is rejected',
  );
  final Uint8List ordinary = codec.encode(_sampleDocument());
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        ordinary,
        payload: (Map<String, dynamic> payload) {
          final List<dynamic> notes = payload['notes'] as List<dynamic>;
          (notes.first as Map<String, dynamic>)['body'] = _repeat('x', 4097);
        },
      ),
    ),
    TerminalNoteCodecFailure.invariantViolation,
    '4097-byte body is rejected without truncation',
  );
  final String sixtyFourLines = List<String>.filled(64, 'x').join('\n');
  final Uint8List lineExact = _rewrite(
    ordinary,
    payload: (Map<String, dynamic> payload) {
      final List<dynamic> notes = payload['notes'] as List<dynamic>;
      (notes.first as Map<String, dynamic>)['body'] = sixtyFourLines;
    },
  );
  codec.decode(lineExact);
  _expectThrowsCodec(
    () => codec.decode(
      _rewrite(
        lineExact,
        payload: (Map<String, dynamic> payload) {
          final List<dynamic> notes = payload['notes'] as List<dynamic>;
          (notes.first as Map<String, dynamic>)['body'] = '$sixtyFourLines\nx';
        },
      ),
    ),
    TerminalNoteCodecFailure.invariantViolation,
    '65-line body is rejected',
  );
}

void _testHardCapacityFixtures() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final Map<TerminalNoteContextId, NoteContextRecord> allContexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  for (var index = 0; index < TerminalNoteLimits.maximumContexts; index++) {
    final TerminalNoteContextId id = _contextId(2000 + index);
    allContexts[id] = NoteContextRecord(
      id: id,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.restorable,
      revision: BigInt.one,
    );
  }
  final Uint8List contextExact = codec.encode(
    TerminalNoteStoreDocument(
      snapshot: TerminalNoteSnapshot.fromRecords(
        storeRevision: BigInt.one,
        nextDeliverySequence: BigInt.one,
        contexts: allContexts,
        notes: const <NoteId, NoteRecord>{},
        triggers: const <NoteId, NoteTriggerRecord>{},
        deliveries: const <NoteId, NoteDeliveryRecord>{},
      ),
    ),
  );
  _expect(
    codec.decode(contextExact).snapshot.contexts.length ==
        TerminalNoteLimits.maximumContexts,
    'exact context record cap is accepted',
  );

  final Uint8List empty = codec.encode(
    TerminalNoteStoreDocument(snapshot: TerminalNoteSnapshot.empty()),
  );
  for (final MapEntry<String, int> boundary in <MapEntry<String, int>>[
    MapEntry<String, int>('contexts', TerminalNoteLimits.maximumContexts + 1),
    MapEntry<String, int>('notes', TerminalNoteLimits.maximumNotes + 1),
    MapEntry<String, int>('triggers', TerminalNoteLimits.maximumTriggers + 1),
    MapEntry<String, int>(
      'deliveries',
      TerminalNoteLimits.maximumDeliveries + 1,
    ),
  ]) {
    _expectThrowsCodec(
      () => codec.decode(
        _rewrite(
          empty,
          payload: (Map<String, dynamic> payload) {
            payload[boundary.key] = List<dynamic>.filled(boundary.value, null);
          },
        ),
      ),
      TerminalNoteCodecFailure.limitExceeded,
      '${boundary.key} cap plus one is rejected before entity decode',
    );
  }

  final Map<TerminalNoteContextId, NoteContextRecord> contexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  for (var index = 0; index < 16; index++) {
    final TerminalNoteContextId id = _contextId(7000 + index);
    contexts[id] = NoteContextRecord(
      id: id,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.active,
      revision: BigInt.one,
    );
  }
  final NoteBody maximumBody = NoteBody.fromText(_repeat('b', 4096));
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{};
  final Map<NoteId, NoteTriggerRecord> triggers = <NoteId, NoteTriggerRecord>{};
  final Map<NoteId, NoteDeliveryRecord> deliveries =
      <NoteId, NoteDeliveryRecord>{};
  final List<TerminalNoteContextId> contextIds = contexts.keys.toList();
  for (var index = 0; index < TerminalNoteLimits.maximumNotes; index++) {
    final NoteId id = _noteId(300000 + index);
    final TerminalNoteContextId contextId = contextIds[index ~/ 128];
    notes[id] = NoteRecord(
      id: id,
      attachment: TerminalNoteAttachment.attached(contextId),
      body: maximumBody,
      color: NoteColorKey.yellow,
      status: NoteStatus.active,
      order: index % 128,
      createdAtUtcMicros: index,
      updatedAtUtcMicros: index,
      revision: BigInt.one,
    );
    triggers[id] = NoteTriggerRecord(
      noteId: id,
      generation: BigInt.one,
      kind: NoteTriggerKind.onReturn,
      phase: NoteTriggerPhase.due,
      suspendReason: null,
      armedAtRevision: BigInt.one,
    );
    deliveries[id] = NoteDeliveryRecord(
      noteId: id,
      triggerGeneration: BigInt.one,
      sequence: DeliverySequence(BigInt.from(index + 1)),
    );
  }
  final TerminalNoteSnapshot hardCap = TerminalNoteSnapshot.fromRecords(
    storeRevision: BigInt.from(TerminalNoteLimits.maximumNotes),
    nextDeliverySequence: BigInt.from(TerminalNoteLimits.maximumNotes + 1),
    contexts: contexts,
    notes: notes,
    triggers: triggers,
    deliveries: deliveries,
  );
  _expect(
    hardCap.aggregateBodyUtf8Bytes ==
        TerminalNoteLimits.maximumAggregateBodyUtf8Bytes,
    'fixture reaches the exact aggregate 8 MiB body cap',
  );
  final Uint8List hardCapBytes = codec.encode(
    TerminalNoteStoreDocument(snapshot: hardCap),
  );
  final TerminalNoteSnapshot hardCapDecoded = codec
      .decode(hardCapBytes)
      .snapshot;
  _expect(
    hardCapDecoded.notes.length == TerminalNoteLimits.maximumNotes &&
        hardCapDecoded.triggers.length == TerminalNoteLimits.maximumTriggers &&
        hardCapDecoded.deliveries.length ==
            TerminalNoteLimits.maximumDeliveries &&
        hardCapDecoded.aggregateBodyUtf8Bytes ==
            TerminalNoteLimits.maximumAggregateBodyUtf8Bytes &&
        hardCapBytes.length < TerminalNoteStoreCodecLimits.maximumFileBytes,
    'exact note/trigger/delivery/body/per-context caps decode below file cap',
  );

  _expectThrowsCodec(
    () => codec.decode(_storeWithAttachedNoteCount(129)),
    TerminalNoteCodecFailure.invariantViolation,
    'attached context note cap plus one is rejected at decode',
  );
}

void _testFileLimitAndArbitraryBytes() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  for (final int length in <int>[
    TerminalNoteStoreCodecLimits.maximumFileBytes - 1,
    TerminalNoteStoreCodecLimits.maximumFileBytes,
  ]) {
    final Uint8List bytes = Uint8List(length)..[length - 1] = 0x0a;
    _expectThrowsCodec(
      () => codec.decode(bytes),
      TerminalNoteCodecFailure.malformedJson,
      'input at or below file cap reaches bounded parser validation',
    );
  }
  _expectThrowsCodec(
    () => codec.decode(
      Uint8List(TerminalNoteStoreCodecLimits.maximumFileBytes + 1),
    ),
    TerminalNoteCodecFailure.fileTooLarge,
    'file cap plus one is rejected before decode',
  );

  var state = 0x6d2b79f5;
  var processed = 0;
  for (var sample = 0; sample < 1024; sample++) {
    final Uint8List bytes = Uint8List(1024);
    for (var index = 0; index < bytes.length; index++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >>> 17;
      state ^= (state << 5) & 0xffffffff;
      bytes[index] = state & 0xff;
    }
    processed += bytes.length;
    try {
      codec.decode(bytes);
      throw StateError('arbitrary bytes unexpectedly decoded');
    } on TerminalNoteCodecException catch (error) {
      _expect(
        error.toString() == 'Terminal note codec failed: ${error.failure.name}',
        'arbitrary-byte failure remains fixed and content-free',
      );
    }
  }
  _expect(processed >= 1024 * 1024, 'at least 1 MiB arbitrary bytes checked');
}

void _testFixedSeedMutationRoundTrips() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  final List<TerminalNoteContextId> contexts = <TerminalNoteContextId>[];
  for (var index = 0; index < 4; index++) {
    final TerminalNoteContextId id = _contextId(9000 + index);
    contexts.add(id);
    snapshot = _accepted(
      snapshot.createContext(
        id: id,
        kind: TerminalNoteContextKind.standard,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
  }
  var seed = 0x13579bdf;
  var nextId = 500000;
  var clock = 1;
  var accepted = 0;
  for (var iteration = 0; iteration < 10000; iteration++) {
    seed = (seed * 1664525 + 1013904223) & 0xffffffff;
    final List<NoteRecord> current = snapshot.notes.values.toList()
      ..sort(
        (NoteRecord left, NoteRecord right) => left.id.compareTo(right.id),
      );
    TerminalNoteMutationResult result;
    if (current.isEmpty || (seed & 7) == 0 && current.length < 24) {
      result = snapshot.createNote(
        id: _noteId(nextId++),
        contextId: contexts[(seed >>> 8) % contexts.length],
        body: 'mutation $iteration',
        color: NoteColorKey.values[(seed >>> 16) % NoteColorKey.values.length],
        utcMicros: clock++,
        expectedStoreRevision: snapshot.storeRevision,
      );
    } else {
      final NoteRecord note = current[(seed >>> 8) % current.length];
      switch ((seed >>> 16) % 7) {
        case 0:
          result = snapshot.editNote(
            noteId: note.id,
            body: 'edited $iteration',
            color: NoteColorKey.values[iteration % NoteColorKey.values.length],
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 1:
          result = snapshot.resolveNote(
            noteId: note.id,
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 2:
          result = snapshot.reopenNote(
            noteId: note.id,
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 3:
          result = snapshot.detachNote(
            noteId: note.id,
            reason: TerminalNoteDetachReason.explicitDetach,
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 4:
          result = snapshot.reattachNote(
            noteId: note.id,
            contextId: contexts[seed % contexts.length],
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
        case 5:
          result =
              note.status == NoteStatus.active && note.attachment.isAttached
              ? (snapshot.triggerFor(note.id) == null
                    ? snapshot.armOnReturn(
                        noteId: note.id,
                        isEligible: (seed & 1) == 0,
                        expectedStoreRevision: snapshot.storeRevision,
                        expectedNoteRevision: note.revision,
                      )
                    : snapshot.cancelTrigger(
                        noteId: note.id,
                        expectedStoreRevision: snapshot.storeRevision,
                        expectedNoteRevision: note.revision,
                      ))
              : snapshot.reopenNote(
                  noteId: note.id,
                  updatedAtUtcMicros: clock++,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedNoteRevision: note.revision,
                );
        default:
          result = snapshot.deleteNote(
            noteId: note.id,
            updatedAtUtcMicros: clock++,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          );
      }
    }
    if (result.disposition == TerminalNoteMutationDisposition.accepted) {
      snapshot = result.snapshot;
      accepted++;
    }
    final Uint8List bytes = codec.encode(
      TerminalNoteStoreDocument(snapshot: snapshot),
    );
    _expectBytesEqual(
      codec.encode(codec.decode(bytes)),
      bytes,
      'fixed-seed accepted snapshot remains byte canonical',
    );
  }
  _expect(accepted > 4000, 'fixed-seed run exercised thousands of mutations');
}

void _testPrivacyAndDependencyBoundary() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  const String bodySentinel = 'PRIVATE-CODEC-BODY-SENTINEL';
  const String idSentinel = 'deadbeefdeadbeefdeadbeefdeadbeef';
  const String timeSentinel = '777777777777';
  final Uint8List canonical = codec.encode(_sampleDocument());
  final Uint8List invalid = _rewrite(
    canonical,
    payload: (Map<String, dynamic> payload) {
      final Map<String, dynamic> note =
          (payload['notes'] as List<dynamic>).first as Map<String, dynamic>;
      note['id'] = idSentinel;
      note['body'] = bodySentinel;
      note['createdAtUtcMicros'] = 777777777777;
      note['updatedAtUtcMicros'] = 1;
    },
  );
  try {
    codec.decode(invalid);
    throw StateError('privacy sentinel fixture unexpectedly decoded');
  } on TerminalNoteCodecException catch (error) {
    final String message = error.toString();
    _expect(
      !message.contains(bodySentinel) &&
          !message.contains(idSentinel) &&
          !message.contains(timeSentinel) &&
          !message.contains('yellow') &&
          !message.contains('onReturn'),
      'codec exception does not echo content, identity, time, color, or trigger',
    );
  }

  final String implementation = File('lib/src/terminal_note_store_codec.dart')
      .readAsStringSync();
  for (final String forbidden in <String>[
    "import 'dart:io'",
    'dart_appkit',
    'dart_pty',
    'AppKit',
  ]) {
    _expect(
      !implementation.contains(forbidden),
      'pure codec must not depend on $forbidden',
    );
  }
}

TerminalNoteStoreDocument _sampleDocument() {
  final TerminalNoteContextId context1 = _contextId(1);
  final TerminalNoteContextId context2 = _contextId(2);
  final TerminalNoteContextId context3 = _contextId(3);
  final NoteId note1 = _noteId(1);
  final NoteId note2 = _noteId(2);
  final NoteId note3 = _noteId(3);
  return TerminalNoteStoreDocument(
    snapshot: TerminalNoteSnapshot.fromRecords(
      storeRevision: BigInt.from(9),
      nextDeliverySequence: BigInt.from(2),
      contexts: <TerminalNoteContextId, NoteContextRecord>{
        context3: NoteContextRecord(
          id: context3,
          kind: TerminalNoteContextKind.quickTerminal,
          state: TerminalNoteContextState.active,
          revision: BigInt.from(3),
        ),
        context2: NoteContextRecord(
          id: context2,
          kind: TerminalNoteContextKind.standard,
          state: TerminalNoteContextState.restorable,
          revision: BigInt.from(2),
        ),
        context1: NoteContextRecord(
          id: context1,
          kind: TerminalNoteContextKind.standard,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        ),
      },
      notes: <NoteId, NoteRecord>{
        note3: _note(
          note3,
          TerminalNoteAttachment.detached(
            previousContextId: context1,
            reason: TerminalNoteDetachReason.paneClosed,
          ),
          'detached',
          status: NoteStatus.resolved,
        ),
        note2: _note(
          note2,
          TerminalNoteAttachment.attached(context2),
          '二番目 👩‍💻',
          color: NoteColorKey.blue,
        ),
        note1: _note(
          note1,
          TerminalNoteAttachment.attached(context1),
          ' first\nsecond ',
        ),
      },
      triggers: <NoteId, NoteTriggerRecord>{
        note2: NoteTriggerRecord(
          noteId: note2,
          generation: BigInt.from(3),
          kind: NoteTriggerKind.onReturn,
          phase: NoteTriggerPhase.due,
          suspendReason: null,
          armedAtRevision: BigInt.from(4),
        ),
      },
      deliveries: <NoteId, NoteDeliveryRecord>{
        note2: NoteDeliveryRecord(
          noteId: note2,
          triggerGeneration: BigInt.from(3),
          sequence: DeliverySequence(BigInt.one),
        ),
      },
    ),
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: _repeat('a', 64),
      paneContextIds: <TerminalNoteContextId>[context2, context1],
    ),
  );
}

NoteRecord _note(
  NoteId id,
  TerminalNoteAttachment attachment,
  String body, {
  NoteColorKey color = NoteColorKey.yellow,
  NoteStatus status = NoteStatus.active,
}) => NoteRecord(
  id: id,
  attachment: attachment,
  body: NoteBody.fromText(body),
  color: color,
  status: status,
  order: 0,
  createdAtUtcMicros: 1,
  updatedAtUtcMicros: 2,
  revision: BigInt.one,
);

Uint8List _storeWithAttachedNoteCount(int count) {
  final String contextId = _contextId(50).canonicalValue;
  final Map<String, dynamic> payload = <String, dynamic>{
    'storeRevision': 1,
    'nextDeliverySequence': 1,
    'contexts': <dynamic>[
      <String, dynamic>{
        'id': contextId,
        'kind': 'standard',
        'state': 'active',
        'revision': 1,
      },
    ],
    'notes': <dynamic>[
      for (var index = 0; index < count; index++)
        <String, dynamic>{
          'id': _noteId(600000 + index).canonicalValue,
          'attachment': <String, dynamic>{
            'kind': 'attached',
            'contextId': contextId,
          },
          'body': 'x',
          'color': 'yellow',
          'status': 'active',
          'order': index,
          'createdAtUtcMicros': 0,
          'updatedAtUtcMicros': 0,
          'revision': 1,
        },
    ],
    'triggers': <dynamic>[],
    'deliveries': <dynamic>[],
    'restorationBinding': null,
  };
  return _envelope(payload, TerminalNoteStoreCodec.storeFormat);
}

Uint8List _rewrite(
  List<int> source, {
  void Function(Map<String, dynamic> root)? root,
  void Function(Map<String, dynamic> payload)? payload,
  bool refreshChecksum = true,
}) {
  final Map<String, dynamic> decoded =
      jsonDecode(utf8.decode(source).trimRight()) as Map<String, dynamic>;
  root?.call(decoded);
  payload?.call(decoded['payload'] as Map<String, dynamic>);
  if (refreshChecksum) {
    decoded['payloadSha256'] = terminalSha256(
      utf8.encode(jsonEncode(decoded['payload'])),
    );
  }
  return Uint8List.fromList(utf8.encode('${jsonEncode(decoded)}\n'));
}

Uint8List _replaceRawPayload(
  List<int> source,
  String original,
  String replacement,
) {
  var text = utf8.decode(source);
  final int payloadStart = text.indexOf('"payload":') + 10;
  final String payload = text.substring(payloadStart, text.length - 2);
  final String replaced = payload.replaceFirst(original, replacement);
  _expect(replaced != payload, 'raw payload fault target exists');
  final String checksum = terminalSha256(utf8.encode(replaced));
  text = text
      .replaceFirst(payload, replaced)
      .replaceFirst(
        RegExp(r'"payloadSha256":"[0-9a-f]{64}"'),
        '"payloadSha256":"$checksum"',
      );
  return Uint8List.fromList(utf8.encode(text));
}

Uint8List _envelope(Map<String, dynamic> payload, String format) {
  final String payloadSource = jsonEncode(payload);
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, dynamic>{
            'format': format,
            'version': 1,
            'payloadSha256': terminalSha256(utf8.encode(payloadSource)),
            'payload': payload,
          }) +
          '\n',
    ),
  );
}

TerminalNoteSnapshot _accepted(TerminalNoteMutationResult result) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.accepted,
    'setup mutation is accepted',
  );
  return result.snapshot;
}

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalNoteContextId _contextId(int value) => TerminalNoteContextId.fromHex(
  (0x100000 + value).toRadixString(16).padLeft(32, '0'),
);

String _repeat(String value, int count) =>
    List<String>.filled(count, value, growable: false).join();

void _expectThrowsCodec(
  void Function() callback,
  TerminalNoteCodecFailure failure,
  String description,
) {
  try {
    callback();
  } on TerminalNoteCodecException catch (error) {
    _expect(error.failure == failure, description);
    return;
  }
  throw StateError('expected TerminalNoteCodecException: $description');
}

void _expectOrdered(String source, List<String> values, String description) {
  var previous = -1;
  for (final String value in values) {
    final int current = source.indexOf(value, previous + 1);
    if (current <= previous) throw StateError(description);
    previous = current;
  }
}

void _expectBytesEqual(List<int> left, List<int> right, String description) {
  if (left.length != right.length) throw StateError(description);
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) throw StateError(description);
  }
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

extension on List<dynamic> {
  void reverseRangeForTest() {
    setRange(0, length, reversed);
  }
}
