import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_sha256.dart';

import '../tool/terminal_restoration_rollback_guard.dart';

Future<void> main() => runTerminalRestorationTests();

Future<void> runTerminalRestorationTests() async {
  _testSecureContextIdentity();
  _testExactRestorationArtifact();
  _testQuickTerminalContextInvariant();
  _testContextRestorationReconciliation();
  await _testOrderedContextPersistence();
  _testWindowPlacementPolicy();
  _testStrictCodecRejection();
  await _testBoundedFileStore();
  await _testInteractiveRestorationTrust();
  await _testQuickTerminalRestorationExclusion();
  await _testHierarchyRoundTripAndFreshOwnership();
  await _testMaximumPaneTraversal();
  await _testRestoreFailureIsAtomic();
}

Future<void> _testInteractiveRestorationTrust() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-interactive-restoration-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  try {
    final String path = TerminalInteractiveRestorationLocation.fromEnvironment(
      <String, String>{'XDG_STATE_HOME': root.path},
    ).path;
    _expect(
      path == '${root.path}/dart-terminal/restoration.json' &&
          TerminalInteractiveRestorationLocation.fromEnvironment(
                <String, String>{'HOME': root.path},
              ).path ==
              '${root.path}/Library/Application Support/Dart Terminal/restoration.json',
      'ordinary restoration uses one safe product state location',
    );
    final TerminalInteractiveRestorationPersistence persistence =
        TerminalInteractiveRestorationPersistence(path);
    _expect(
      (await persistence.loadAndConsumeTrusted()).disposition ==
          TerminalInteractiveRestorationLoadDisposition.missing,
      'first ordinary launch has no trusted restoration',
    );
    const String exact =
        '{"version":1,"activeWindow":0,"windows":[{"placement":'
        '{"windowedFrame":[100.0,90.0,920.0,580.0],"screen":null,'
        '"fullscreen":false},"selectedTab":0,"tabs":[{"focusedPane":0,'
        '"zoomedPane":null,"title":null,"color":null,"tree":'
        '{"kind":"pane","cwd":"/private/tmp"}}]}]}';
    _expect(await persistence.saveTrusted(exact), 'trusted save succeeds');
    _expect(
      await persistence.clearUntrustedAfterNoteCommit(),
      'the first ordered Note commit establishes a trusted binding',
    );
    final TerminalInteractiveRestorationLoad loaded = await persistence
        .loadAndConsumeTrusted();
    _expect(
      loaded.disposition ==
              TerminalInteractiveRestorationLoadDisposition.restored &&
          loaded.exactEncoded == exact &&
          loaded.snapshot!.paneCount == 1 &&
          (await persistence.loadAndConsumeTrusted()).disposition ==
              TerminalInteractiveRestorationLoadDisposition.untrusted,
      'ordinary launch receives exact v1 bytes and topology',
    );
    _expect(await persistence.saveTrusted(exact), 'off save after claim');
    final TerminalInteractiveRestorationLoad offLoaded = await persistence
        .loadAndConsumeTrusted();
    _expect(
      offLoaded.disposition ==
              TerminalInteractiveRestorationLoadDisposition.untrusted &&
          offLoaded.snapshot?.paneCount == 1 &&
          offLoaded.exactEncoded == exact,
      'off launch restores terminal topology but cannot reactivate the old Note binding',
    );
    _expect(await persistence.saveTrusted(exact), 'ordered save after off');
    _expect(
      await persistence.clearUntrustedAfterNoteCommit(),
      'ordered Note commit clears the untrusted sentinel',
    );
    await File(path).writeAsString('\n$exact\n', flush: true);
    _expect(
      (await persistence.loadAndConsumeTrusted()).disposition ==
          TerminalInteractiveRestorationLoadDisposition.untrusted,
      'valid v1 bytes with a different exact hash do not attach Notes',
    );
    _expect(await persistence.saveTrusted(exact), 'trusted save repairs pair');
    _expect(await persistence.invalidateTrust(), 'rollback guard succeeds');
    _expect(
      await File(path).readAsString() == exact &&
          (await persistence.loadAndConsumeTrusted()).disposition ==
              TerminalInteractiveRestorationLoadDisposition.untrusted,
      'pre-Notes rollback invalidates trust without deleting v1 data',
    );
    parseTerminalRestorationRollbackGuardArguments(const <String>[
      '--prepare-pre-notes-rollback',
      '--acknowledge-app-closed-and-store-backed-up',
    ]);
    _expectThrows<FormatException>(
      () => parseTerminalRestorationRollbackGuardArguments(const <String>[
        '--prepare-pre-notes-rollback',
      ]),
      'rollback tool rejects a missing safety acknowledgement',
    );
    _expect(
      await prepareTerminalRestorationPreNotesRollback(<String, String>{
        'XDG_STATE_HOME': root.path,
      }),
      'rollback tool derives the same ordinary restoration location',
    );
    _expect(await persistence.saveTrusted(exact), 'off save after rollback');
    final TerminalInteractiveRestorationLoad rollbackOffLoaded =
        await persistence.loadAndConsumeTrusted();
    _expect(
      rollbackOffLoaded.disposition ==
              TerminalInteractiveRestorationLoadDisposition.untrusted &&
          rollbackOffLoaded.snapshot?.paneCount == 1,
      'rollback guard survives a later off launch with identical bytes while retaining terminal topology',
    );
    _expect(
      await persistence.saveTrusted(exact),
      'ordered save after rollback',
    );
    _expect(
      await persistence.clearUntrustedAfterNoteCommit(),
      'new Note binding can establish fresh trust',
    );
    await File('$path.trusted').writeAsString('invalid\n', flush: true);
    _expect(
      (await persistence.loadAndConsumeTrusted()).disposition ==
          TerminalInteractiveRestorationLoadDisposition.untrusted,
      'malformed trust marker fails closed',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

void _testSecureContextIdentity() {
  final TerminalNoteContextIdGenerator secure =
      TerminalNoteContextIdGenerator.secure();
  final Set<String> issued = <String>{};
  for (var index = 0; index < 64; index++) {
    final TerminalNoteContextId id = secure.next();
    _expect(
      RegExp(r'^[0-9a-f]{32}$').hasMatch(id.canonicalValue) &&
          issued.add(id.canonicalValue) &&
          !id.toString().contains(id.canonicalValue),
      'secure context IDs are unique canonical opaque 128-bit values',
    );
  }

  final TerminalNoteContextId reserved = TerminalNoteContextId.fromHex(
    List<String>.filled(16, '11').join(),
  );
  var collisionCalls = 0;
  final TerminalNoteContextIdGenerator recovering =
      TerminalNoteContextIdGenerator.forTesting(() {
        collisionCalls++;
        return List<int>.filled(16, collisionCalls == 1 ? 0x11 : 0x22);
      });
  _expect(
    recovering.next(excluding: <TerminalNoteContextId>[reserved]) ==
            TerminalNoteContextId.fromHex(
              List<String>.filled(16, '22').join(),
            ) &&
        collisionCalls == 2,
    'context ID generation retries a collision without reusing an identity',
  );

  var exhaustedCalls = 0;
  final TerminalNoteContextIdGenerator exhausted =
      TerminalNoteContextIdGenerator.forTesting(() {
        exhaustedCalls++;
        return List<int>.filled(16, 0x11);
      });
  try {
    exhausted.next(excluding: <TerminalNoteContextId>[reserved]);
    throw StateError('context ID collision bound was not enforced');
  } on TerminalNoteContextIdentityException catch (error) {
    _expect(
      error.failure == TerminalNoteContextIdentityFailure.collisionLimit &&
          exhaustedCalls ==
              TerminalNoteContextIdentityLimits.maximumCollisionAttempts &&
          !error.toString().contains(reserved.canonicalValue),
      'collision exhaustion is bounded and content-free',
    );
  }
  try {
    const TerminalNoteContextIdGenerator.forTesting(_invalidContextEntropy)
        .next();
    throw StateError('invalid entropy was not rejected');
  } on TerminalNoteContextIdentityException catch (error) {
    _expect(
      error.failure == TerminalNoteContextIdentityFailure.entropyRejected,
      'invalid entropy shape is rejected before ID construction',
    );
  }
}

List<int> _invalidContextEntropy() => const <int>[1, 2, 3];

void _testExactRestorationArtifact() {
  const String preNotesVersionOne =
      '{"version":1,"activeWindow":0,"windows":[{"placement":'
      '{"windowedFrame":[100.0,90.0,920.0,580.0],"screen":null,'
      '"fullscreen":false},"selectedTab":0,"tabs":[{"focusedPane":0,'
      '"zoomedPane":null,"title":null,"color":null,"tree":'
      '{"kind":"pane","cwd":"/private/tmp"}}]}]}';
  final TerminalNoteRestorationArtifact artifact =
      TerminalNoteRestorationArtifact.fromExactEncoded(preNotesVersionOne);
  _expect(
    artifact.snapshot.paneCount == 1 &&
        artifact.snapshot.windows.length == 1 &&
        artifact.exactEncoded == preNotesVersionOne &&
        utf8.decode(artifact.exactUtf8Bytes) == preNotesVersionOne &&
        artifact.restorationSha256 ==
            terminalSha256(utf8.encode(preNotesVersionOne)) &&
        TerminalRestorationCodec.encode(artifact.snapshot) ==
            preNotesVersionOne,
    'pre-Notes restoration v1 bytes and schema remain exactly unchanged',
  );
  _expectThrows<UnsupportedError>(
    () => artifact.exactUtf8Bytes[0] = 0,
    'exact restoration bytes are immutable',
  );

  final String padded = '\n$preNotesVersionOne\n';
  final TerminalNoteRestorationArtifact exactPadded =
      TerminalNoteRestorationArtifact.fromExactEncoded(padded);
  _expect(
    exactPadded.snapshot.paneCount == 1 &&
        exactPadded.exactEncoded == padded &&
        exactPadded.restorationSha256 == terminalSha256(utf8.encode(padded)) &&
        exactPadded.restorationSha256 != artifact.restorationSha256,
    'binding digest uses loaded exact UTF-8 rather than re-encoded JSON',
  );
}

void _testQuickTerminalContextInvariant() {
  final TerminalNoteContextId quick = _contextId(900);
  final TerminalNoteContextId duplicate = _contextId(901);
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _acceptedNoteSnapshot(
    snapshot.createContext(
      id: quick,
      kind: TerminalNoteContextKind.quickTerminal,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  final NoteContextRecord context = snapshot.contextFor(quick)!;
  _expect(
    snapshot
                .createContext(
                  id: duplicate,
                  kind: TerminalNoteContextKind.quickTerminal,
                  expectedStoreRevision: snapshot.storeRevision,
                )
                .failure ==
            TerminalNoteMutationFailure.invalidState &&
        snapshot
                .setContextState(
                  contextId: quick,
                  state: TerminalNoteContextState.restorable,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedContextRevision: context.revision,
                )
                .failure ==
            TerminalNoteMutationFailure.invalidState &&
        snapshot
                .detachContext(
                  contextId: quick,
                  reason: TerminalNoteDetachReason.contextUnavailable,
                  updatedAtUtcMicros: 0,
                  expectedStoreRevision: snapshot.storeRevision,
                  expectedContextRevision: context.revision,
                )
                .failure ==
            TerminalNoteMutationFailure.invalidState,
    'Quick Terminal context is one always-active non-detachable singleton',
  );
  _expectThrows<TerminalNoteValidationException>(
    () => TerminalNoteSnapshot.fromRecords(
      storeRevision: BigInt.one,
      nextDeliverySequence: BigInt.one,
      contexts: <TerminalNoteContextId, NoteContextRecord>{
        quick: NoteContextRecord(
          id: quick,
          kind: TerminalNoteContextKind.quickTerminal,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        ),
        duplicate: NoteContextRecord(
          id: duplicate,
          kind: TerminalNoteContextKind.quickTerminal,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        ),
      },
      notes: const <NoteId, NoteRecord>{},
      triggers: const <NoteId, NoteTriggerRecord>{},
      deliveries: const <NoteId, NoteDeliveryRecord>{},
    ),
    'decoded snapshots reject multiple Quick Terminal contexts',
  );
}

void _testContextRestorationReconciliation() {
  final TerminalNoteRestorationArtifact oldRestoration =
      TerminalNoteRestorationArtifact.fromSnapshot(
        _twoPaneRestoration('/private/tmp/old'),
      );
  final TerminalNoteRestorationArtifact newRestoration =
      TerminalNoteRestorationArtifact.fromSnapshot(
        _twoPaneRestoration('/private/tmp/new'),
      );
  final TerminalNoteRestorationArtifact changedLayout =
      TerminalNoteRestorationArtifact.fromSnapshot(_minimalSnapshot());
  final TerminalNoteContextId first = _contextId(100);
  final TerminalNoteContextId second = _contextId(101);
  final TerminalNoteContextId quick = _contextId(102);
  final TerminalNoteStoreDocument stored = _restorableNoteDocument(
    contextIds: <TerminalNoteContextId>[first, second],
    quickTerminalContextId: quick,
    bindingSha256: oldRestoration.restorationSha256,
    bindingContextIds: <TerminalNoteContextId>[first, second],
  );
  final List<PaneId> panes = <PaneId>[const PaneId(70), const PaneId(80)];
  final TerminalNoteContextReconciler reconciler =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0x80));

  final TerminalNoteContextReconciliationResult current = reconciler.reconcile(
    stored: stored,
    restoration: oldRestoration,
    paneIdsInTraversalOrder: panes,
    ensureQuickTerminalContext: true,
    updatedAtUtcMicros: 1000,
  );
  _expect(
    current.disposition ==
            TerminalNoteContextReconciliationDisposition.matched &&
        current.freshReason == null &&
        current.requiresCommit &&
        current.bindings.contextForPane(panes[0]) == first &&
        current.bindings.contextForPane(panes[1]) == second &&
        current.bindings.quickTerminalContextId == quick &&
        current.document.snapshot.contextFor(first)!.state ==
            TerminalNoteContextState.active &&
        current.document.snapshot.contextFor(second)!.state ==
            TerminalNoteContextState.active &&
        current.document.snapshot.noteFor(_noteId(100))!.attachment.contextId ==
            first &&
        current.document.restorationBinding!.paneContextIds.length == 2 &&
        !current.document.restorationBinding!.paneContextIds.contains(quick),
    'B-01 exact current restoration attaches only ordered standard contexts',
  );
  _expect(
    !current.bindings.toString().contains(first.canonicalValue) &&
        !current.bindings.toString().contains(quick.canonicalValue),
    'runtime binding diagnostics do not expose durable context IDs',
  );
  _expectThrows<UnsupportedError>(
    () => current.bindings.standardPaneContexts.clear(),
    'runtime pane bindings are immutable',
  );

  final TerminalNoteContextReconciliationResult rollbackUnchanged = reconciler
      .reconcile(
        stored: current.document,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1001,
      );
  _expect(
    rollbackUnchanged.disposition ==
            TerminalNoteContextReconciliationDisposition.matched &&
        !rollbackUnchanged.requiresCommit &&
        rollbackUnchanged.bindings.contextForPane(panes[0]) == first &&
        rollbackUnchanged.bindings.quickTerminalContextId == quick,
    'B-04 pre-Notes launch with unchanged v1 layout reattaches exact IDs',
  );

  final TerminalNoteContextReconciliationResult restorationOnlyNew = reconciler
      .reconcile(
        stored: stored,
        restoration: newRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1002,
      );
  _expectFreshDetached(
    restorationOnlyNew,
    TerminalNoteContextFreshReason.hashMismatch,
    <TerminalNoteContextId>[first, second],
    panes,
    'B-02 restoration-only new',
  );

  final TerminalNoteStoreDocument bindingOnlyNew = TerminalNoteStoreDocument(
    snapshot: stored.snapshot,
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: newRestoration.restorationSha256,
      paneContextIds: <TerminalNoteContextId>[first, second],
    ),
  );
  final TerminalNoteContextReconciliationResult bindingNew = reconciler
      .reconcile(
        stored: bindingOnlyNew,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1003,
      );
  _expectFreshDetached(
    bindingNew,
    TerminalNoteContextFreshReason.hashMismatch,
    <TerminalNoteContextId>[first, second],
    panes,
    'B-03 binding-only new',
  );

  final TerminalNoteContextReconciliationResult rollbackChanged = reconciler
      .reconcile(
        stored: stored,
        restoration: changedLayout,
        paneIdsInTraversalOrder: <PaneId>[const PaneId(90)],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1004,
      );
  _expectFreshDetached(
    rollbackChanged,
    TerminalNoteContextFreshReason.hashMismatch,
    <TerminalNoteContextId>[first, second],
    <PaneId>[const PaneId(90)],
    'B-05 rollback layout change',
  );

  final TerminalNoteStoreDocument legacy = TerminalNoteStoreDocument(
    snapshot: stored.snapshot,
  );
  final TerminalNoteContextReconciliationResult legacyResult = reconciler
      .reconcile(
        stored: legacy,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1005,
      );
  _expectFreshDetached(
    legacyResult,
    TerminalNoteContextFreshReason.bindingMissing,
    <TerminalNoteContextId>[first, second],
    panes,
    'legacy missing binding',
  );

  final TerminalNoteStoreDocument countMismatch = TerminalNoteStoreDocument(
    snapshot: stored.snapshot,
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: oldRestoration.restorationSha256,
      paneContextIds: <TerminalNoteContextId>[first],
    ),
  );
  final TerminalNoteContextReconciliationResult countResult = reconciler
      .reconcile(
        stored: countMismatch,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1006,
      );
  _expectFreshDetached(
    countResult,
    TerminalNoteContextFreshReason.countMismatch,
    <TerminalNoteContextId>[first, second],
    panes,
    'binding count mismatch',
  );

  final TerminalNoteStoreDocument detachedBinding = _detachedBoundDocument(
    restorationSha256: changedLayout.restorationSha256,
  );
  final TerminalNoteContextReconciliationResult detachedResult = reconciler
      .reconcile(
        stored: detachedBinding,
        restoration: changedLayout,
        paneIdsInTraversalOrder: <PaneId>[const PaneId(91)],
        ensureQuickTerminalContext: false,
        updatedAtUtcMicros: 1007,
      );
  _expect(
    detachedResult.freshReason ==
            TerminalNoteContextFreshReason.bindingStateMismatch &&
        detachedResult.bindings.contextForPane(const PaneId(91)) !=
            _contextId(500),
    'detached binding context invalidates the whole binding',
  );

  final TerminalNoteContextReconciliationResult noRestoration = reconciler
      .reconcile(
        stored: stored,
        restoration: null,
        paneIdsInTraversalOrder: <PaneId>[const PaneId(92)],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1008,
      );
  _expect(
    noRestoration.freshReason ==
            TerminalNoteContextFreshReason.restorationMissing &&
        noRestoration.document.restorationBinding == null &&
        noRestoration.bindings.standardPaneContexts.length == 1,
    'missing restoration creates fresh contexts without a guessed binding',
  );

  final TerminalNoteStoreDocument noQuick = _restorableNoteDocument(
    contextIds: <TerminalNoteContextId>[first, second],
    bindingSha256: oldRestoration.restorationSha256,
    bindingContextIds: <TerminalNoteContextId>[first, second],
  );
  final TerminalNoteContextReconciliationResult quickCreated = reconciler
      .reconcile(
        stored: noQuick,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1009,
      );
  final TerminalNoteContextReconciliationResult quickRestart = reconciler
      .reconcile(
        stored: quickCreated.document,
        restoration: oldRestoration,
        paneIdsInTraversalOrder: panes,
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 1010,
      );
  _expect(
    quickCreated.bindings.quickTerminalContextId != null &&
        quickRestart.bindings.quickTerminalContextId ==
            quickCreated.bindings.quickTerminalContextId &&
        !quickRestart.document.restorationBinding!.paneContextIds.contains(
          quickCreated.bindings.quickTerminalContextId,
        ),
    'Quick Terminal hide/show/restart reuses one context outside binding',
  );

  _expectThrows<TerminalNoteContextReconciliationException>(
    () => reconciler.reconcile(
      stored: stored,
      restoration: oldRestoration,
      paneIdsInTraversalOrder: <PaneId>[panes.first, panes.first],
      ensureQuickTerminalContext: true,
      updatedAtUtcMicros: 1011,
    ),
    'duplicate runtime pane IDs reject the reconciliation input',
  );
  _expectThrows<TerminalNoteCodecException>(
    () => TerminalNoteRestorationBinding(
      restorationSha256: oldRestoration.restorationSha256,
      paneContextIds: <TerminalNoteContextId>[first, first],
    ),
    'duplicate durable context IDs reject the binding',
  );
}

Future<void> _testOrderedContextPersistence() async {
  final TerminalNoteRestorationArtifact oldRestoration =
      TerminalNoteRestorationArtifact.fromSnapshot(
        _twoPaneRestoration('/private/tmp/old'),
      );
  final String paddedNewEncoded =
      '\n${TerminalRestorationCodec.encode(_twoPaneRestoration('/private/tmp/new'))}\n';
  final TerminalNoteRestorationArtifact newRestoration =
      TerminalNoteRestorationArtifact.fromExactEncoded(paddedNewEncoded);
  final List<PaneId> panes = <PaneId>[const PaneId(70), const PaneId(80)];
  final TerminalNoteContextId first = _contextId(200);
  final TerminalNoteContextId second = _contextId(201);
  final TerminalNoteContextId extra = _contextId(202);
  final TerminalNoteContextId quick = _contextId(203);
  final TerminalNoteStoreDocument baseStored = _activeNoteDocument(
    contextIds: <TerminalNoteContextId>[first, second, extra],
    quickTerminalContextId: quick,
    bindingSha256: oldRestoration.restorationSha256,
    bindingContextIds: <TerminalNoteContextId>[first, second],
  );
  TerminalNoteSnapshot shutdownSnapshot = baseStored.snapshot;
  shutdownSnapshot = _acceptedNoteSnapshot(
    shutdownSnapshot.createNote(
      id: _noteId(110),
      contextId: first,
      body: 'passive shutdown fixture',
      color: NoteColorKey.blue,
      utcMicros: 110,
      expectedStoreRevision: shutdownSnapshot.storeRevision,
    ),
  );
  shutdownSnapshot = _acceptedNoteSnapshot(
    shutdownSnapshot.createNote(
      id: _noteId(111),
      contextId: first,
      body: 'due shutdown fixture',
      color: NoteColorKey.green,
      utcMicros: 111,
      expectedStoreRevision: shutdownSnapshot.storeRevision,
    ),
  );
  shutdownSnapshot = _acceptedNoteSnapshot(
    shutdownSnapshot.createNote(
      id: _noteId(112),
      contextId: quick,
      body: 'quick shutdown fixture',
      color: NoteColorKey.pink,
      utcMicros: 112,
      expectedStoreRevision: shutdownSnapshot.storeRevision,
    ),
  );
  for (final (NoteId noteId, bool isEligible) in <(NoteId, bool)>[
    (_noteId(100), true),
    (_noteId(101), false),
    (_noteId(111), false),
  ]) {
    final NoteRecord note = shutdownSnapshot.noteFor(noteId)!;
    shutdownSnapshot = _acceptedNoteSnapshot(
      shutdownSnapshot.armOnReturn(
        noteId: noteId,
        isEligible: isEligible,
        expectedStoreRevision: shutdownSnapshot.storeRevision,
        expectedNoteRevision: note.revision,
      ),
    );
  }
  shutdownSnapshot = _acceptedNoteSnapshot(
    shutdownSnapshot.observeEligibleFocus(
      contextId: first,
      isEligible: true,
      expectedStoreRevision: shutdownSnapshot.storeRevision,
    ),
  );
  final NoteRecord quickNote = shutdownSnapshot.noteFor(_noteId(112))!;
  shutdownSnapshot = _acceptedNoteSnapshot(
    shutdownSnapshot.armOnReturn(
      noteId: quickNote.id,
      isEligible: true,
      expectedStoreRevision: shutdownSnapshot.storeRevision,
      expectedNoteRevision: quickNote.revision,
    ),
  );
  final TerminalNoteStoreDocument stored = TerminalNoteStoreDocument(
    snapshot: shutdownSnapshot,
    restorationBinding: baseStored.restorationBinding,
  );
  final NoteDeliveryRecord dueBeforeShutdown = stored.snapshot.deliveryFor(
    _noteId(111),
  )!;
  final TerminalNoteRestorationCaptureArtifact capture =
      TerminalNoteRestorationCaptureArtifact.fromArtifact(
        restoration: newRestoration,
        paneIdsInTraversalOrder: panes,
      );
  final TerminalNoteContextBindings bindings = TerminalNoteContextBindings(
    standardPaneContexts: <PaneId, TerminalNoteContextId>{
      panes[0]: first,
      panes[1]: second,
    },
    quickTerminalContextId: quick,
  );
  final TerminalNoteShutdownCandidate candidate =
      const TerminalNoteShutdownCandidateBuilder().prepare(
        stored: stored,
        capture: capture,
        bindings: bindings,
        updatedAtUtcMicros: 2000,
      );
  _expect(
    candidate.requiresNoteCommit &&
        candidate.restoration.exactEncoded == paddedNewEncoded &&
        candidate.document.restorationBinding!.restorationSha256 ==
            newRestoration.restorationSha256 &&
        candidate.document.restorationBinding!.paneContextIds[0] == first &&
        candidate.document.restorationBinding!.paneContextIds[1] == second &&
        candidate.document.snapshot.contextFor(first)!.state ==
            TerminalNoteContextState.restorable &&
        candidate.document.snapshot.contextFor(second)!.state ==
            TerminalNoteContextState.restorable &&
        candidate.document.snapshot.contextFor(extra)!.state ==
            TerminalNoteContextState.detached &&
        candidate.document.snapshot.contextFor(quick)!.state ==
            TerminalNoteContextState.active &&
        candidate.document.snapshot.triggerFor(_noteId(100))!.phase ==
            NoteTriggerPhase.onReturnArmedAway &&
        candidate.document.snapshot.triggerFor(_noteId(101))!.phase ==
            NoteTriggerPhase.onReturnArmedAway &&
        candidate.document.snapshot.triggerFor(_noteId(111))!.phase ==
            NoteTriggerPhase.due &&
        candidate.document.snapshot.deliveryFor(_noteId(111))!.sequence ==
            dueBeforeShutdown.sequence &&
        candidate.document.snapshot
                .deliveryFor(_noteId(111))!
                .triggerGeneration ==
            dueBeforeShutdown.triggerGeneration &&
        candidate.document.snapshot.triggerFor(_noteId(110)) == null &&
        candidate.document.snapshot.triggerFor(_noteId(112))!.phase ==
            NoteTriggerPhase.onReturnArmedAway &&
        stored.snapshot.triggerFor(_noteId(100))!.phase ==
            NoteTriggerPhase.onReturnArmedHere &&
        stored.snapshot.triggerFor(_noteId(112))!.phase ==
            NoteTriggerPhase.onReturnArmedHere &&
        candidate.document.snapshot
                .noteFor(_noteId(102))!
                .attachment
                .detachReason ==
            TerminalNoteDetachReason.contextUnavailable &&
        !candidate.toString().contains(first.canonicalValue) &&
        !candidate.toString().contains(newRestoration.restorationSha256),
    'shutdown candidate binds exact bytes, marks retained On Return contexts '
    'away without mutating the source, preserves due/passive state and the '
    'Quick singleton, and detaches stale contexts',
  );

  _expectThrows<TerminalNoteShutdownPreparationException>(
    () => const TerminalNoteShutdownCandidateBuilder().prepare(
      stored: stored,
      capture: capture,
      bindings: TerminalNoteContextBindings(
        standardPaneContexts: <PaneId, TerminalNoteContextId>{
          panes.first: first,
        },
        quickTerminalContextId: quick,
      ),
      updatedAtUtcMicros: 2001,
    ),
    'shutdown preparation rejects a partial traversal binding',
  );
  _expectThrows<TerminalNoteShutdownPreparationException>(
    () => const TerminalNoteShutdownCandidateBuilder().prepare(
      stored: stored,
      capture: capture,
      bindings: TerminalNoteContextBindings(
        standardPaneContexts: <PaneId, TerminalNoteContextId>{
          panes[0]: first,
          panes[1]: second,
        },
        quickTerminalContextId: null,
      ),
      updatedAtUtcMicros: 2002,
    ),
    'shutdown preparation rejects a missing Quick singleton binding',
  );

  final List<String> restorationFailureTrace = <String>[];
  final TerminalNoteOrderedPersistenceResult restorationFailure =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact _) async {
          restorationFailureTrace.add('restoration');
          return false;
        },
        commitNoteDocument: (TerminalNoteStoreDocument _) async {
          restorationFailureTrace.add('note');
          return true;
        },
      ).commit(candidate);
  _expect(
    restorationFailure.disposition ==
            TerminalNoteOrderedPersistenceDisposition.restorationCommitFailed &&
        !restorationFailure.restorationCommitAcknowledged &&
        !restorationFailure.noteCommitAttempted &&
        restorationFailureTrace.join(',') == 'restoration',
    'restoration rejection prevents the Note binding commit',
  );
  TerminalNoteRestorationArtifact publishedBeforeRestorationFailure =
      oldRestoration;
  var noteCalledAfterRestorationException = false;
  final TerminalNoteOrderedPersistenceResult ambiguousRestorationFailure =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact artifact) async {
          publishedBeforeRestorationFailure = artifact;
          throw StateError('injected restoration acknowledgement loss');
        },
        commitNoteDocument: (TerminalNoteStoreDocument _) async {
          noteCalledAfterRestorationException = true;
          return true;
        },
      ).commit(candidate);
  final TerminalNoteContextReconciliationResult ambiguousRestorationRestart =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0x90))
          .reconcile(
            stored: stored,
            restoration: publishedBeforeRestorationFailure,
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2001,
          );
  _expect(
    ambiguousRestorationFailure.disposition ==
            TerminalNoteOrderedPersistenceDisposition.restorationCommitFailed &&
        !noteCalledAfterRestorationException &&
        ambiguousRestorationRestart.disposition ==
            TerminalNoteContextReconciliationDisposition.fresh &&
        ambiguousRestorationRestart.freshReason ==
            TerminalNoteContextFreshReason.hashMismatch,
    'restoration publication followed by acknowledgement loss still skips '
    'the Note commit and fails closed on restart',
  );

  final List<String> noteFailureTrace = <String>[];
  final TerminalNoteOrderedPersistenceResult noteFailure =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact _) async {
          noteFailureTrace.add('restoration');
          return true;
        },
        commitNoteDocument: (TerminalNoteStoreDocument _) async {
          noteFailureTrace.add('note');
          return false;
        },
      ).commit(candidate);
  _expect(
    noteFailure.disposition ==
            TerminalNoteOrderedPersistenceDisposition.noteCommitFailed &&
        noteFailure.restorationCommitAcknowledged &&
        noteFailure.noteCommitAttempted &&
        !noteFailure.noteCommitAcknowledged &&
        noteFailureTrace.join(',') == 'restoration,note',
    'Note rejection occurs only after the restoration commit',
  );
  TerminalNoteStoreDocument publishedBeforeNoteFailure = stored;
  final TerminalNoteOrderedPersistenceResult ambiguousNoteFailure =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact _) async => true,
        commitNoteDocument: (TerminalNoteStoreDocument document) async {
          publishedBeforeNoteFailure = document;
          throw StateError('injected Note acknowledgement loss');
        },
      ).commit(candidate);
  final TerminalNoteContextReconciliationResult ambiguousNoteRestart =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0x98))
          .reconcile(
            stored: publishedBeforeNoteFailure,
            restoration: newRestoration,
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2002,
          );
  _expect(
    ambiguousNoteFailure.disposition ==
            TerminalNoteOrderedPersistenceDisposition.noteCommitFailed &&
        !ambiguousNoteFailure.noteCommitAcknowledged &&
        ambiguousNoteRestart.disposition ==
            TerminalNoteContextReconciliationDisposition.matched &&
        !ambiguousNoteFailure.toString().contains('acknowledgement loss'),
    'Note publication followed by acknowledgement loss remains a matching '
    'generation without exposing the injected failure',
  );

  final List<String> successTrace = <String>[];
  final TerminalNoteOrderedPersistenceResult success =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact _) async {
          successTrace.add('restoration');
          return true;
        },
        commitNoteDocument: (TerminalNoteStoreDocument _) async {
          successTrace.add('note');
          return true;
        },
      ).commit(candidate);
  _expect(
    success.isSuccess &&
        success.restorationCommitAcknowledged &&
        success.noteCommitAcknowledged &&
        successTrace.join(',') == 'restoration,note',
    'successful shutdown commits restoration before its Note binding',
  );

  final TerminalNoteShutdownCandidate unchanged =
      const TerminalNoteShutdownCandidateBuilder().prepare(
        stored: candidate.document,
        capture: capture,
        bindings: bindings,
        updatedAtUtcMicros: 2003,
      );
  var unexpectedNoChangeNoteCommit = false;
  final TerminalNoteOrderedPersistenceResult noChange =
      await TerminalNoteOrderedPersistenceCoordinator(
        commitRestoration: (TerminalNoteRestorationArtifact _) async => true,
        commitNoteDocument: (TerminalNoteStoreDocument _) async {
          unexpectedNoChangeNoteCommit = true;
          return true;
        },
      ).commit(unchanged);
  _expect(
    !unchanged.requiresNoteCommit &&
        noChange.isSuccess &&
        !noChange.noteCommitAttempted &&
        !unexpectedNoChangeNoteCommit,
    'an unchanged binding rewrites restoration without a stale Note commit',
  );

  final TerminalNoteContextReconciliationResult noteFailureRestart =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0xa0))
          .reconcile(
            stored: stored,
            restoration: newRestoration,
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2004,
          );
  _expect(
    noteFailureRestart.disposition ==
            TerminalNoteContextReconciliationDisposition.fresh &&
        noteFailureRestart.freshReason ==
            TerminalNoteContextFreshReason.hashMismatch,
    'crash after restoration commit and before Note commit fails closed',
  );
  final TerminalNoteContextReconciliationResult committedRestart =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0xb0))
          .reconcile(
            stored: candidate.document,
            restoration: newRestoration,
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2005,
          );
  _expect(
    committedRestart.disposition ==
            TerminalNoteContextReconciliationDisposition.matched &&
        committedRestart.bindings.contextForPane(panes.first) == first,
    'both committed files reopen with the exact ordered context generation',
  );
  final TerminalNoteContextReconciliationResult rollbackUnchanged =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0xc0))
          .reconcile(
            stored: candidate.document,
            restoration: TerminalNoteRestorationArtifact.fromExactEncoded(
              paddedNewEncoded,
            ),
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2006,
          );
  _expect(
    rollbackUnchanged.disposition ==
        TerminalNoteContextReconciliationDisposition.matched,
    'pre-Notes rewrite without layout change preserves exact binding',
  );
  final TerminalNoteContextReconciliationResult rollbackChanged =
      TerminalNoteContextReconciler(_sequentialContextGenerator(0xd0))
          .reconcile(
            stored: candidate.document,
            restoration: oldRestoration,
            paneIdsInTraversalOrder: panes,
            ensureQuickTerminalContext: true,
            updatedAtUtcMicros: 2007,
          );
  _expect(
    rollbackChanged.disposition ==
            TerminalNoteContextReconciliationDisposition.fresh &&
        rollbackChanged.freshReason ==
            TerminalNoteContextFreshReason.hashMismatch,
    'pre-Notes layout change after rollback detaches instead of guessing',
  );

  await _testRealOrderedContextPersistence(
    stored: stored,
    capture: capture,
    bindings: bindings,
    panes: panes,
    expectedContext: first,
  );
}

Future<void> _testRealOrderedContextPersistence({
  required TerminalNoteStoreDocument stored,
  required TerminalNoteRestorationCaptureArtifact capture,
  required TerminalNoteContextBindings bindings,
  required List<PaneId> panes,
  required TerminalNoteContextId expectedContext,
}) async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-context-persistence-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  TerminalNoteStoreTransactionEngine? engine;
  TerminalNoteStoreTransactionEngine? reopened;
  try {
    final String restorationPath = '${root.path}/restoration.json';
    final TerminalRestorationPersistence restorationPersistence =
        TerminalRestorationPersistence(
          FileTerminalRestorationStore(restorationPath),
        );
    engine = TerminalNoteStoreTransactionEngine.open(
      location: TerminalNoteStoreLocation.fromAbsolutePath(
        '${root.path}/notes',
      ),
    );
    _expect(
      engine.load().disposition == TerminalNoteStoreDisposition.empty,
      'real Note store starts empty',
    );
    final TerminalNoteShutdownCandidate realCandidate =
        const TerminalNoteShutdownCandidateBuilder().prepare(
          stored: stored,
          capture: capture,
          bindings: bindings,
          updatedAtUtcMicros: 3000,
        );
    final TerminalNoteOrderedPersistenceResult persisted =
        await TerminalNoteOrderedPersistenceCoordinator(
          commitRestoration: (TerminalNoteRestorationArtifact artifact) async =>
              (await restorationPersistence.saveExactEncoded(
                artifact.exactEncoded,
              )).disposition ==
              TerminalRestorationSaveDisposition.saved,
          commitNoteDocument: (TerminalNoteStoreDocument document) async =>
              engine!.commitCandidate(document).disposition ==
              TerminalNoteStoreDisposition.committed,
        ).commit(realCandidate);
    _expect(persisted.isSuccess, 'real ordered persistence commits both files');
    final List<int> diskRestoration = await File(restorationPath).readAsBytes();
    _expectBytesEqual(
      diskRestoration,
      realCandidate.restoration.exactUtf8Bytes,
      'real restoration store commits the exact bytes used by the binding',
    );
    final TerminalRestorationLoadResult loadedRestoration =
        await restorationPersistence.load();
    _expect(
      loadedRestoration.disposition ==
              TerminalRestorationLoadDisposition.restored &&
          loadedRestoration.exactEncoded ==
              realCandidate.restoration.exactEncoded,
      'real restoration load retains exact encoded bytes',
    );
    _expect(
      engine.stop().disposition == TerminalNoteStoreDisposition.stopped,
      'real Note writer releases its lock',
    );
    engine = null;
    reopened = TerminalNoteStoreTransactionEngine.open(
      location: TerminalNoteStoreLocation.fromAbsolutePath(
        '${root.path}/notes',
      ),
    );
    final TerminalNoteStoreResult loadedNote = reopened.load();
    final TerminalNoteRestorationArtifact reopenedArtifact =
        TerminalNoteRestorationArtifact.fromExactEncoded(
          loadedRestoration.exactEncoded!,
        );
    final TerminalNoteContextReconciliationResult reconciled =
        TerminalNoteContextReconciler(_sequentialContextGenerator(0xe0))
            .reconcile(
              stored: loadedNote.document!,
              restoration: reopenedArtifact,
              paneIdsInTraversalOrder: panes,
              ensureQuickTerminalContext: true,
              updatedAtUtcMicros: 3001,
            );
    _expect(
      loadedNote.disposition == TerminalNoteStoreDisposition.loaded &&
          reconciled.disposition ==
              TerminalNoteContextReconciliationDisposition.matched &&
          reconciled.bindings.contextForPane(panes.first) == expectedContext,
      'real files reopen as one exact matching generation',
    );
  } finally {
    engine?.stop();
    reopened?.stop();
    await temporary.delete(recursive: true);
  }
}

void _expectFreshDetached(
  TerminalNoteContextReconciliationResult result,
  TerminalNoteContextFreshReason reason,
  List<TerminalNoteContextId> oldContextIds,
  List<PaneId> panes,
  String scenario,
) {
  _expect(
    result.disposition == TerminalNoteContextReconciliationDisposition.fresh &&
        result.freshReason == reason &&
        result.requiresCommit &&
        result.bindings.standardPaneContexts.length == panes.length &&
        panes.every(
          (PaneId paneId) =>
              !oldContextIds.contains(result.bindings.contextForPane(paneId)),
        ) &&
        oldContextIds.every(
          (TerminalNoteContextId contextId) =>
              result.document.snapshot.contextFor(contextId)!.state ==
              TerminalNoteContextState.detached,
        ) &&
        oldContextIds.every(
          (TerminalNoteContextId contextId) => result
              .document
              .snapshot
              .notes
              .values
              .where(
                (NoteRecord note) =>
                    note.attachment.previousContextId == contextId,
              )
              .every(
                (NoteRecord note) =>
                    note.attachment.detachReason ==
                    TerminalNoteDetachReason.restorationMismatch,
              ),
        ),
    '$scenario uses fresh contexts and detaches every old Note',
  );
}

TerminalNoteStoreDocument _restorableNoteDocument({
  required List<TerminalNoteContextId> contextIds,
  TerminalNoteContextId? quickTerminalContextId,
  required String bindingSha256,
  required List<TerminalNoteContextId> bindingContextIds,
}) {
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  for (var index = 0; index < contextIds.length; index++) {
    final TerminalNoteContextId contextId = contextIds[index];
    snapshot = _acceptedNoteSnapshot(
      snapshot.createContext(
        id: contextId,
        kind: TerminalNoteContextKind.standard,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
    snapshot = _acceptedNoteSnapshot(
      snapshot.createNote(
        id: _noteId(100 + index),
        contextId: contextId,
        body: 'private fixture ${index + 1}',
        color: NoteColorKey.yellow,
        utcMicros: 100 + index,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
    final NoteContextRecord context = snapshot.contextFor(contextId)!;
    snapshot = _acceptedNoteSnapshot(
      snapshot.setContextState(
        contextId: contextId,
        state: TerminalNoteContextState.restorable,
        expectedStoreRevision: snapshot.storeRevision,
        expectedContextRevision: context.revision,
      ),
    );
  }
  if (quickTerminalContextId != null) {
    snapshot = _acceptedNoteSnapshot(
      snapshot.createContext(
        id: quickTerminalContextId,
        kind: TerminalNoteContextKind.quickTerminal,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );
  }
  return TerminalNoteStoreDocument(
    snapshot: snapshot,
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: bindingSha256,
      paneContextIds: bindingContextIds,
    ),
  );
}

TerminalNoteStoreDocument _activeNoteDocument({
  required List<TerminalNoteContextId> contextIds,
  TerminalNoteContextId? quickTerminalContextId,
  required String bindingSha256,
  required List<TerminalNoteContextId> bindingContextIds,
}) {
  final TerminalNoteStoreDocument restorable = _restorableNoteDocument(
    contextIds: contextIds,
    quickTerminalContextId: quickTerminalContextId,
    bindingSha256: bindingSha256,
    bindingContextIds: bindingContextIds,
  );
  TerminalNoteSnapshot snapshot = restorable.snapshot;
  for (final TerminalNoteContextId contextId in contextIds) {
    final NoteContextRecord context = snapshot.contextFor(contextId)!;
    snapshot = _acceptedNoteSnapshot(
      snapshot.setContextState(
        contextId: contextId,
        state: TerminalNoteContextState.active,
        expectedStoreRevision: snapshot.storeRevision,
        expectedContextRevision: context.revision,
      ),
    );
  }
  return TerminalNoteStoreDocument(
    snapshot: snapshot,
    restorationBinding: restorable.restorationBinding,
  );
}

TerminalNoteStoreDocument _detachedBoundDocument({
  required String restorationSha256,
}) {
  final TerminalNoteContextId contextId = _contextId(500);
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _acceptedNoteSnapshot(
    snapshot.createContext(
      id: contextId,
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _acceptedNoteSnapshot(
    snapshot.detachContext(
      contextId: contextId,
      reason: TerminalNoteDetachReason.contextUnavailable,
      updatedAtUtcMicros: 0,
      expectedStoreRevision: snapshot.storeRevision,
      expectedContextRevision: snapshot.contextFor(contextId)!.revision,
    ),
  );
  return TerminalNoteStoreDocument(
    snapshot: snapshot,
    restorationBinding: TerminalNoteRestorationBinding(
      restorationSha256: restorationSha256,
      paneContextIds: <TerminalNoteContextId>[contextId],
    ),
  );
}

TerminalNoteSnapshot _acceptedNoteSnapshot(TerminalNoteMutationResult result) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.accepted,
    'Note fixture mutation is accepted',
  );
  return result.snapshot;
}

TerminalNoteContextIdGenerator _sequentialContextGenerator(int start) {
  var value = start;
  return TerminalNoteContextIdGenerator.forTesting(
    () => List<int>.filled(16, value++),
  );
}

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalNoteContextId _contextId(int value) =>
    TerminalNoteContextId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalRestorationSnapshot _twoPaneRestoration(String workingDirectory) =>
    TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        TerminalRestorableWindow(
          placement: _minimalPlacement(),
          tabs: <TerminalRestorableTab>[
            TerminalRestorableTab(
              splitTree: TerminalRestorableSplitBranch(
                axis: TerminalSplitAxis.horizontal,
                fraction: 0.5,
                first: TerminalRestorableSplitLeaf(
                  TerminalRestorablePane(workingDirectory: workingDirectory),
                ),
                second: TerminalRestorableSplitLeaf(
                  TerminalRestorablePane(workingDirectory: workingDirectory),
                ),
              ),
              focusedPaneIndex: 0,
              zoomedPaneIndex: null,
              customTitle: null,
              color: null,
            ),
          ],
          selectedTabIndex: 0,
        ),
      ],
      activeWindowIndex: 0,
    );

Future<void> _testQuickTerminalRestorationExclusion() async {
  final List<_RestorationFakeSession> sessions = <_RestorationFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState standard = await state.createWindow(
    _configuration(sessions, '/private/tmp/standard'),
  );
  final TerminalWindowState quick = await state.createWindow(
    _configuration(sessions, '/private/tmp/quick'),
    role: TerminalWindowRole.quickTerminal,
  );
  final List<TerminalWindowId> placementRequests = <TerminalWindowId>[];
  final TerminalRestorationCaptureResult captured =
      TerminalApplicationRestorationCapture.captureWithTraversal(
        state,
        placementForWindow: (TerminalWindowId id) {
          placementRequests.add(id);
          return _minimalPlacement();
        },
        workingDirectoryForPane: (PaneId id) => null,
      );
  final TerminalRestorationSnapshot snapshot = captured.snapshot;
  _expect(
    snapshot.windows.length == 1 &&
        snapshot.activeWindowIndex == 0 &&
        captured.paneIdsInTraversalOrder.length == 1 &&
        captured.paneIdsInTraversalOrder.single ==
            standard.selectedTab.focusedPaneId &&
        placementRequests.length == 1 &&
        placementRequests.single == standard.id,
    'restoration excludes the active Quick Terminal and its placement',
  );

  await state.removePane(standard.selectedTab.focusedPaneId);
  _expect(
    identical(state.quickTerminalWindow, quick) && state.windowCount == 1,
    'Quick Terminal remains live after the last standard window closes',
  );
  _expectThrows<StateError>(
    () => TerminalApplicationRestorationCapture.capture(
      state,
      placementForWindow: (TerminalWindowId id) => _minimalPlacement(),
      workingDirectoryForPane: (PaneId id) => null,
    ),
    'restoration refuses to serialize an application with no standard window',
  );
  await state.shutdown();
  _expect(
    sessions.every(
      (_RestorationFakeSession session) => session.shutdownCount == 1,
    ),
    'restoration exclusion fixture releases standard and Quick Terminal panes',
  );
}

Future<void> _testBoundedFileStore() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'dart-terminal-restoration-',
  );
  final String path = '${directory.path}/nested/state.json';
  try {
    final FileTerminalRestorationStore store = FileTerminalRestorationStore(
      path,
    );
    _expect(await store.read() == null, 'a missing restoration file is absent');

    await store.write('{"generation":1}');
    _expect(
      await store.read() == '{"generation":1}' &&
          !await File('$path.pending').exists(),
      'the first bounded file write is readable without a pending artifact',
    );
    await store.write('{"generation":2}');
    _expect(
      await store.read() == '{"generation":2}',
      'same-directory replacement overwrites an existing restoration file',
    );

    final List<int> oversized = List<int>.filled(
      TerminalRestorationLimits.maximumSerializedUtf8Bytes + 1,
      0x61,
    );
    await _expectFutureThrows<TerminalRestorationLimitException>(() async {
      await store.write(String.fromCharCodes(oversized));
    }, 'the file store rejects oversized output before writing');
    await File(path).writeAsBytes(oversized, flush: true);
    await _expectFutureThrows<TerminalRestorationLimitException>(() async {
      await store.read();
    }, 'the file store rejects oversized input before decoding it');
    await File(path).writeAsBytes(const <int>[0xff], flush: true);
    await _expectFutureThrows<FormatException>(() async {
      await store.read();
    }, 'the file store rejects malformed UTF-8');

    _expectThrows<ArgumentError>(
      () => FileTerminalRestorationStore('relative.json'),
      'the file store rejects relative paths',
    );
    _expectThrows<ArgumentError>(
      () => FileTerminalRestorationStore('${directory.path}/'),
      'the file store rejects directory-shaped paths',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

void _testWindowPlacementPolicy() {
  final TerminalScreenPlacement source = TerminalScreenPlacement(
    displayId: 41,
    frame: TerminalWindowFrame(left: -1920, top: 0, width: 1920, height: 1080),
    visibleFrame: TerminalWindowFrame(
      left: -1920,
      top: 25,
      width: 1920,
      height: 1055,
    ),
  );
  final TerminalScreenPlacement destination = TerminalScreenPlacement(
    displayId: 77,
    frame: TerminalWindowFrame(left: 0, top: 0, width: 1512, height: 982),
    visibleFrame: TerminalWindowFrame(
      left: 0,
      top: 23,
      width: 1512,
      height: 959,
    ),
  );
  final TerminalWindowPlacement saved = TerminalWindowPlacement(
    windowedFrame: TerminalWindowFrame(
      left: -1800,
      top: 100,
      width: 960,
      height: 500,
    ),
    screen: source,
    fullscreen: true,
  );
  final TerminalWindowPlacement migrated =
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        saved,
        <TerminalScreenPlacement>[destination],
      );
  _expect(
    migrated.screen == destination &&
        migrated.fullscreen &&
        migrated.windowedFrame.left >= destination.visibleFrame.left &&
        migrated.windowedFrame.top >= destination.visibleFrame.top &&
        migrated.windowedFrame.right <= destination.visibleFrame.right &&
        migrated.windowedFrame.bottom <= destination.visibleFrame.bottom &&
        migrated.windowedFrame.width == 960 &&
        migrated.windowedFrame.height == 500,
    'display migration preserves intent and clamps into a new visible frame',
  );

  final TerminalScreenPlacement tiny = TerminalScreenPlacement(
    displayId: 88,
    frame: TerminalWindowFrame(left: 4000, top: -800, width: 240, height: 160),
    visibleFrame: TerminalWindowFrame(
      left: 4000,
      top: -780,
      width: 240,
      height: 140,
    ),
  );
  final TerminalWindowPlacement clamped =
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        TerminalWindowPlacement(
          windowedFrame: TerminalWindowFrame(
            left: -9999,
            top: 9999,
            width: 2000,
            height: 1800,
          ),
          screen: null,
          fullscreen: false,
        ),
        <TerminalScreenPlacement>[destination, tiny],
        fallbackDisplayId: tiny.displayId,
      );
  _expect(
    clamped.screen == tiny &&
        clamped.windowedFrame == tiny.visibleFrame &&
        !clamped.fullscreen,
    'missing display state uses the explicit fallback and its entire tiny area',
  );
  _expect(
    identical(
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        saved,
        const <TerminalScreenPlacement>[],
      ),
      saved,
    ),
    'absent screen inventory does not invent replacement coordinates',
  );
}

void _testStrictCodecRejection() {
  final TerminalRestorationSnapshot snapshot = _minimalSnapshot();
  final String encoded = TerminalRestorationCodec.encode(snapshot);
  final TerminalRestorationSnapshot decoded = TerminalRestorationCodec.decode(
    encoded,
  );
  _expect(
    decoded.windows.length == 1 &&
        decoded.tabCount == 1 &&
        decoded.paneCount == 1 &&
        TerminalRestorationCodec.encode(decoded) == encoded,
    'the versioned restoration codec is deterministic',
  );

  final Map<String, Object?> unexpected =
      jsonDecode(encoded) as Map<String, Object?>;
  unexpected['extra'] = true;
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(unexpected)),
    'unexpected semantic keys are rejected',
  );

  final Map<String, Object?> unsupported =
      jsonDecode(encoded) as Map<String, Object?>;
  unsupported['version'] = 2;
  _expectThrows<FormatException>(
    () => TerminalRestorationCodec.decode(jsonEncode(unsupported)),
    'unsupported restoration versions are rejected',
  );

  final Map<String, Object?> unsafe =
      jsonDecode(encoded) as Map<String, Object?>;
  final List<Object?> windows = unsafe['windows']! as List<Object?>;
  final Map<String, Object?> window = windows.single as Map<String, Object?>;
  final List<Object?> tabs = window['tabs']! as List<Object?>;
  final Map<String, Object?> tab = tabs.single as Map<String, Object?>;
  final Map<String, Object?> tree = tab['tree']! as Map<String, Object?>;
  tree['cwd'] = 'relative/or/control\u0000';
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(unsafe)),
    'unsafe launch cwd is rejected before session allocation',
  );

  final Map<String, Object?> invalidZoom =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> invalidZoomWindow =
      (invalidZoom['windows']! as List<Object?>).single as Map<String, Object?>;
  final Map<String, Object?> invalidZoomTab =
      (invalidZoomWindow['tabs']! as List<Object?>).single
          as Map<String, Object?>;
  invalidZoomTab['zoomedPane'] = 1;
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(invalidZoom)),
    'zoom must refer to the focused pane',
  );

  _expectThrows<TerminalRestorationLimitException>(
    () => TerminalRestorationCodec.decode(
      List<String>.filled(
        TerminalRestorationLimits.maximumSerializedUtf8Bytes + 1,
        'x',
      ).join(),
    ),
    'oversized serialized input is rejected before JSON parsing',
  );

  final TerminalRestorableTab onePane = _minimalTab();
  _expectThrows<TerminalRestorationLimitException>(
    () => TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        TerminalRestorableWindow(
          placement: _minimalPlacement(),
          tabs: List<TerminalRestorableTab>.filled(64, onePane),
          selectedTabIndex: 0,
        ),
        TerminalRestorableWindow(
          placement: _minimalPlacement(),
          tabs: <TerminalRestorableTab>[onePane],
          selectedTabIndex: 0,
        ),
      ],
      activeWindowIndex: 0,
    ),
    'global pane admission is bounded below structural maxima',
  );
}

Future<void> _testHierarchyRoundTripAndFreshOwnership() async {
  final List<_RestorationFakeSession> originalSessions =
      <_RestorationFakeSession>[];
  final TerminalApplicationState original = TerminalApplicationState();
  final Map<PaneId, String?> workingDirectories = <PaneId, String?>{};
  TerminalPaneConfiguration originalConfiguration(String? cwd) =>
      _configuration(originalSessions, cwd);

  final TerminalWindowState firstWindow = await original.createWindow(
    originalConfiguration('/private/tmp/one'),
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  workingDirectories[firstPane] = '/private/tmp/one';
  final TerminalPane secondPane = await original.splitPane(
    firstPane,
    originalConfiguration('/private/tmp/two'),
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.3,
  );
  workingDirectories[secondPane.id] = '/private/tmp/two';
  final TerminalPane thirdPane = await original.splitPane(
    secondPane.id,
    originalConfiguration('/private/tmp/three'),
    axis: TerminalSplitAxis.vertical,
    placement: TerminalSplitPlacement.before,
    fraction: 0.7,
  );
  workingDirectories[thirdPane.id] = '/private/tmp/three';
  final TerminalPane fourthPane = await original.splitPane(
    thirdPane.id,
    originalConfiguration('/private/tmp/four'),
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.4,
  );
  workingDirectories[fourthPane.id] = '/private/tmp/four';
  original
    ..focusPane(firstTab.id, fourthPane.id)
    ..setPaneZoom(firstTab.id, fourthPane.id)
    ..renameTab(firstTab.id, 'Restored four-pane tab')
    ..setTabColor(firstTab.id, TerminalTabColor.greenMarker);

  final TerminalTabState secondTab = await original.createTab(
    firstWindow.id,
    originalConfiguration('/private/tmp/five'),
  );
  workingDirectories[secondTab.focusedPaneId] = '/private/tmp/five';
  original.selectTab(firstWindow.id, firstTab.id);
  final TerminalWindowState secondWindow = await original.createWindow(
    originalConfiguration('/private/tmp/six'),
  );
  workingDirectories[secondWindow.selectedTab.focusedPaneId] =
      '/private/tmp/six';
  original.activateWindow(firstWindow.id);

  final Map<TerminalWindowId, TerminalWindowPlacement> placements =
      <TerminalWindowId, TerminalWindowPlacement>{
        firstWindow.id: TerminalWindowPlacement(
          windowedFrame: TerminalWindowFrame(
            left: -1200,
            top: 80,
            width: 920,
            height: 580,
          ),
          screen: TerminalScreenPlacement(
            displayId: 41,
            frame: TerminalWindowFrame(
              left: -1920,
              top: 0,
              width: 1920,
              height: 1080,
            ),
            visibleFrame: TerminalWindowFrame(
              left: -1920,
              top: 25,
              width: 1920,
              height: 1055,
            ),
          ),
          fullscreen: true,
        ),
        secondWindow.id: _minimalPlacement(),
      };
  final TerminalRestorationCaptureResult capture =
      TerminalApplicationRestorationCapture.captureWithTraversal(
        original,
        placementForWindow: (TerminalWindowId id) => placements[id]!,
        workingDirectoryForPane: (PaneId id) => workingDirectories[id],
      );
  final TerminalRestorationSnapshot captured = capture.snapshot;
  _expect(
    capture.paneIdsInTraversalOrder
            .map((PaneId id) => id.value)
            .toList()
            .join(',') ==
        '1,3,4,2,5,6',
    'capture exposes window/tab/first-second DFS pane order exactly',
  );
  final String encoded = TerminalRestorationCodec.encode(captured);
  final TerminalRestorationSnapshot decoded = TerminalRestorationCodec.decode(
    encoded,
  );

  final List<_RestorationFakeSession> restoredSessions =
      <_RestorationFakeSession>[];
  final TerminalApplicationState seeded = TerminalApplicationState(
    paneOwner: TerminalPaneOwner(initialPaneId: 400),
    initialWindowId: 100,
    initialTabId: 200,
    initialSplitNodeId: 300,
  );
  final TerminalRestorationResult restored =
      await TerminalApplicationRestorer.restore(
        decoded,
        into: seeded,
        configurationForPane: (TerminalRestorablePane pane) =>
            _configuration(restoredSessions, pane.workingDirectory),
      );
  final TerminalApplicationState restoredState = restored.applicationState;
  _expect(
    restoredState.windowCount == 2 &&
        restoredState.tabCount == 3 &&
        restoredState.paneCount == 6 &&
        restoredState.windowIds.first.value == 101 &&
        restoredState.windows.first.tabIds.first.value == 201 &&
        restoredState.paneIds.first.value == 401 &&
        restored.paneIdsInTraversalOrder
                .map((PaneId id) => id.value)
                .toList()
                .join(',') ==
            '401,402,404,403,405,406' &&
        restoredState.activeWindowId == restoredState.windowIds.first &&
        restoredSessions.length == 6 &&
        restoredSessions.every(
          (_RestorationFakeSession session) =>
              !originalSessions.contains(session),
        ),
    'restore creates a fresh bounded owner graph and preserves active order',
  );
  final TerminalTabState restoredFirstTab =
      restoredState.windows.first.tabs.first;
  _expect(
    restoredFirstTab.paneIds.length == 4 &&
        restoredFirstTab.isZoomed &&
        restoredFirstTab.zoomedPaneId == restoredFirstTab.focusedPaneId &&
        restoredFirstTab.customTitle == 'Restored four-pane tab' &&
        restoredFirstTab.color == TerminalTabColor.greenMarker &&
        restoredState.windows.first.selectedTabId == restoredFirstTab.id &&
        restored.placements[restoredState.windows.first.id]?.fullscreen ==
            true &&
        restored.launchWorkingDirectories.values.toSet().containsAll(<String>{
          '/private/tmp/one',
          '/private/tmp/two',
          '/private/tmp/three',
          '/private/tmp/four',
          '/private/tmp/five',
          '/private/tmp/six',
        }),
    'restore preserves split presentation, focus, metadata, placement, and cwd',
  );

  final TerminalRestorationSnapshot recaptured =
      TerminalApplicationRestorationCapture.capture(
        restoredState,
        placementForWindow: (TerminalWindowId id) => restored.placements[id]!,
        workingDirectoryForPane: (PaneId id) =>
            restored.launchWorkingDirectories[id],
      );
  _expect(
    TerminalRestorationCodec.encode(recaptured) == encoded,
    'multi-window, multi-tab, four-pane hierarchy round-trips exactly',
  );

  await restoredState.shutdown();
  await original.shutdown();
  _expect(
    restoredSessions.every(
          (_RestorationFakeSession session) => session.shutdownCount == 1,
        ) &&
        originalSessions.every(
          (_RestorationFakeSession session) => session.shutdownCount == 1,
        ),
    'original and restored fresh sessions each shut down exactly once',
  );
}

Future<void> _testMaximumPaneTraversal() async {
  final List<_RestorationFakeSession> sessions = <_RestorationFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState window = await state.createWindow(
    _configuration(sessions, null),
  );
  PaneId target = window.selectedTab.focusedPaneId;
  for (
    var index = 1;
    index < TerminalRestorationLimits.maximumTotalPanes;
    index++
  ) {
    target = (await state.splitPane(
      target,
      _configuration(sessions, null),
      axis: index.isEven
          ? TerminalSplitAxis.horizontal
          : TerminalSplitAxis.vertical,
    )).id;
  }
  final TerminalNoteRestorationCaptureArtifact captured =
      TerminalNoteRestorationCaptureArtifact.capture(
        state,
        placementForWindow: (TerminalWindowId id) => _minimalPlacement(),
        workingDirectoryForPane: (PaneId id) => null,
      );
  _expect(
    captured.restoration.snapshot.paneCount == 64 &&
        captured.paneIdsInTraversalOrder.length == 64 &&
        captured.paneIdsInTraversalOrder.toSet().length == 64 &&
        captured.restoration.exactEncoded ==
            TerminalRestorationCodec.encode(captured.restoration.snapshot),
    'exact maximum 64-pane capture preserves a unique bounded traversal',
  );
  await state.shutdown();
  _expect(
    sessions.length == 64 &&
        sessions.every(
          (_RestorationFakeSession session) => session.shutdownCount == 1,
        ),
    'maximum traversal fixture releases every pane session',
  );
}

Future<void> _testRestoreFailureIsAtomic() async {
  final List<_RestorationFakeSession> sessions = <_RestorationFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  var configurations = 0;
  await _expectFutureThrows<StateError>(
    () => TerminalApplicationRestorer.restore(
      TerminalRestorationSnapshot(
        windows: <TerminalRestorableWindow>[
          TerminalRestorableWindow(
            placement: _minimalPlacement(),
            tabs: <TerminalRestorableTab>[
              TerminalRestorableTab(
                splitTree: TerminalRestorableSplitBranch(
                  axis: TerminalSplitAxis.horizontal,
                  fraction: 0.5,
                  first: TerminalRestorableSplitLeaf(
                    TerminalRestorablePane(workingDirectory: '/private/tmp'),
                  ),
                  second: TerminalRestorableSplitLeaf(
                    TerminalRestorablePane(workingDirectory: '/private/tmp'),
                  ),
                ),
                focusedPaneIndex: 0,
                zoomedPaneIndex: null,
                customTitle: null,
                color: null,
              ),
            ],
            selectedTabIndex: 0,
          ),
        ],
        activeWindowIndex: 0,
      ),
      into: state,
      configurationForPane: (TerminalRestorablePane pane) {
        configurations++;
        if (configurations == 2) throw StateError('injected restore failure');
        return _configuration(sessions, pane.workingDirectory);
      },
    ),
    'injected restore failure is surfaced',
  );
  _expect(
    state.isDisposed &&
        state.windowCount == 0 &&
        state.paneCount == 0 &&
        sessions.single.shutdownCount == 1,
    'partial restoration shuts down its admitted owner graph atomically',
  );
}

TerminalRestorationSnapshot _minimalSnapshot() => TerminalRestorationSnapshot(
  windows: <TerminalRestorableWindow>[
    TerminalRestorableWindow(
      placement: _minimalPlacement(),
      tabs: <TerminalRestorableTab>[_minimalTab()],
      selectedTabIndex: 0,
    ),
  ],
  activeWindowIndex: 0,
);

TerminalRestorableTab _minimalTab() => TerminalRestorableTab(
  splitTree: TerminalRestorableSplitLeaf(
    TerminalRestorablePane(workingDirectory: '/private/tmp'),
  ),
  focusedPaneIndex: 0,
  zoomedPaneIndex: null,
  customTitle: null,
  color: null,
);

TerminalWindowPlacement _minimalPlacement() => TerminalWindowPlacement(
  windowedFrame: TerminalWindowFrame(
    left: 100,
    top: 90,
    width: 920,
    height: 580,
  ),
  screen: null,
  fullscreen: false,
);

TerminalPaneConfiguration _configuration(
  List<_RestorationFakeSession> sessions,
  String? workingDirectory,
) => TerminalPaneConfiguration(
  sessionFactory:
      (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) {
        final _RestorationFakeSession session = _RestorationFakeSession(
          id,
          workingDirectory,
        );
        sessions.add(session);
        return session;
      },
  onChanged: () {},
  onExitRequested: () {},
);

final class _RestorationFakeSession implements TerminalPaneSession {
  _RestorationFakeSession(this.id, this.workingDirectory);

  @override
  final TerminalSessionId id;
  final String? workingDirectory;
  var shutdownCount = 0;

  @override
  bool get isLive => shutdownCount == 0;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;

  @override
  TerminalPaneProcessSnapshot processSnapshot() => shutdownCount == 0
      ? TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: id.paneId.value,
          owningProcessGroup: id.paneId.value,
          foregroundProcessGroup: id.paneId.value,
        )
      : TerminalPaneProcessSnapshot.nonLive(id);

  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();

  @override
  bool get bracketedPasteMode => false;

  @override
  bool get pasteInProgress => false;

  @override
  Future<void> start() async {}

  @override
  String render() => '';

  @override
  void insertText(String value) {}

  @override
  void deleteBackward() {}

  @override
  void deleteForward() {}

  @override
  void moveLeft() {}

  @override
  void moveRight() {}

  @override
  void moveToStart() {}

  @override
  void moveToEnd() {}

  @override
  void previousHistory() {}

  @override
  void nextHistory() {}

  @override
  Future<void> submit() async {}

  @override
  void interrupt() {}

  @override
  void suspend() {}

  @override
  void quitForegroundProcess() {}

  @override
  void sendEndOfFile() {}

  @override
  void sendInput(Uint8List bytes) {}

  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async =>
      const TerminalPasteTransferResult(
        disposition: TerminalPasteTransferDisposition.completed,
        encodedBytes: 0,
        completedChunks: 0,
        backpressureCount: 0,
        maximumQueuedBytes: 0,
        concurrentInputRejections: 0,
      );

  @override
  void resize({required int rows, required int columns}) {}

  @override
  void showClipboardNotice(TerminalClipboardNotice notice) {}

  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {}

  @override
  void showCloseConfirmation() {}

  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    shutdownCount++;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectBytesEqual(List<int> left, List<int> right, String message) {
  _expect(
    left.length == right.length &&
        List<int>.generate(
          left.length,
          (int index) => index,
        ).every((int index) => left[index] == right[index]),
    message,
  );
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError(message);
}

Future<void> _expectFutureThrows<T extends Object>(
  Future<void> Function() body,
  String message,
) async {
  try {
    await body();
  } on T {
    return;
  }
  throw StateError(message);
}
