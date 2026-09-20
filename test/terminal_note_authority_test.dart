import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNoteAuthorityTests();

Future<void> runTerminalNoteAuthorityTests() async {
  await _testStartupAndSerialDurablePublication();
  await _testDuplicateRevisionAndAdmissionBounds();
  await _testBoundedTopologyAndFocusIngress();
  await _testPromptOverflowAndSessionReplacement();
  await _testSixtyFourPaneAndSessionBound();
  await _testCommitFailurePreservesPublishedDocument();
  await _testStartupFailureStates();
}

Future<void> _testStartupAndSerialDurablePublication() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final List<TerminalNoteAuthorityPublication> publications =
      <TerminalNoteAuthorityPublication>[];
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    onPublished: publications.add,
  );
  final TerminalNoteContextId contextId = authority.bindings.contextForPane(
    const PaneId(1),
  )!;
  _expect(
    authority.capability == TerminalNoteAuthorityCapability.ready &&
        authority.document.snapshot.contexts.length == 1 &&
        store.commitCount == 1 &&
        publications.length == 1 &&
        publications.single.kind ==
            TerminalNoteAuthorityPublicationKind.startup,
    'startup reconciliation is committed before the authority becomes ready',
  );

  final Completer<void> firstGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> first = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 1, event: 1),
        bodyUtf8Bytes: 5,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(1),
          body: 'alpha',
          timestamp: 10,
        ),
      );
  final Future<TerminalNoteAuthorityMutationResult> second = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 2, event: 1),
        bodyUtf8Bytes: 4,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(2),
          body: 'beta',
          timestamp: 11,
        ),
      );
  _expect(
    authority.hasInFlightMutation &&
        authority.pendingIntentCount == 1 &&
        authority.pendingBodyBytes == 9 &&
        store.maximumConcurrentCommits == 1 &&
        authority.document.snapshot.notes.isEmpty,
    'O-01 keeps one durable mutation in flight and does not publish a '
    'candidate before commit',
  );
  firstGate.complete();
  final List<TerminalNoteAuthorityMutationResult> results = await Future.wait(
    <Future<TerminalNoteAuthorityMutationResult>>[first, second],
  );
  _expect(
    results.every(
          (TerminalNoteAuthorityMutationResult result) =>
              result.disposition ==
              TerminalNoteAuthorityMutationDisposition.committed,
        ) &&
        authority.document.snapshot.noteFor(_noteId(1))!.body.value ==
            'alpha' &&
        authority.document.snapshot.noteFor(_noteId(2))!.body.value == 'beta' &&
        store.maximumConcurrentCommits == 1 &&
        store.commitCount == 3 &&
        publications.length == 3 &&
        publications[1].storeRevision < publications[2].storeRevision,
    'O-01 publishes different-window mutations in durable revision order',
  );
  _expect(
    !publications.last.toString().contains('alpha') &&
        !publications.last.toString().contains(_noteId(1).canonicalValue),
    'authority publication diagnostics exclude body and persistent identity',
  );
  _expect(
    (await authority.stop()).disposition ==
            TerminalNoteStoreDisposition.stopped &&
        authority.capability == TerminalNoteAuthorityCapability.stopped &&
        store.stopCount == 1,
    'authority owns and stops its store port exactly once',
  );
}

Future<void> _testDuplicateRevisionAndAdmissionBounds() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteContextId contextId = authority.bindings.contextForPane(
    const PaneId(1),
  )!;
  final Completer<void> duplicateGate = store.blockNextCommit();
  final TerminalNoteAuthorityIntentToken duplicateToken = _token(
    authority,
    source: 10,
    event: 1,
  );
  final int beforeDuplicateCommit = store.commitCount;
  final Future<TerminalNoteAuthorityMutationResult> original = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: duplicateToken,
        bodyUtf8Bytes: 9,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(10),
          body: 'duplicate',
          timestamp: 20,
        ),
      );
  final TerminalNoteAuthorityMutationResult duplicate = await authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: duplicateToken,
        bodyUtf8Bytes: 9,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(10),
          body: 'duplicate',
          timestamp: 20,
        ),
      );
  duplicateGate.complete();
  final TerminalNoteAuthorityMutationResult originalResult = await original;
  await authority.whenIdle();
  _expect(
    duplicate.disposition ==
            TerminalNoteAuthorityMutationDisposition.duplicate &&
        originalResult.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        store.commitCount == beforeDuplicateCommit + 1 &&
        authority.document.snapshot.noteFor(_noteId(10))!.revision ==
            BigInt.one,
    'O-02 drops a duplicate editor event while committing the original once',
  );

  final int beforeRevisionConflict = store.commitCount;
  final TerminalNoteAuthorityMutationResult conflict = await authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 10, event: 2),
        bodyUtf8Bytes: 0,
        transition: (TerminalNoteSnapshot snapshot) =>
            TerminalNoteAuthorityMutationPlan(
              mutation: snapshot.editNote(
                noteId: _noteId(10),
                body: 'changed',
                color: NoteColorKey.blue,
                updatedAtUtcMicros: 21,
                expectedStoreRevision: BigInt.zero,
                expectedNoteRevision: BigInt.one,
              ),
            ),
      );
  await authority.whenIdle();
  _expect(
    conflict.disposition == TerminalNoteAuthorityMutationDisposition.rejected &&
        conflict.mutationFailure ==
            TerminalNoteMutationFailure.revisionConflict &&
        store.commitCount == beforeRevisionConflict,
    'revision conflict is rejected without a filesystem request',
  );

  final Completer<void> queueGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> queueHead = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 20, event: 1),
        bodyUtf8Bytes: 1,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(20),
          body: 'q',
          timestamp: 30,
        ),
      );
  final List<Future<TerminalNoteAuthorityMutationResult>> queued =
      <Future<TerminalNoteAuthorityMutationResult>>[];
  for (
    var index = 0;
    index < TerminalNoteAuthorityLimits.maximumPendingIntents;
    index++
  ) {
    queued.add(
      authority.submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 20, event: index + 2),
        bodyUtf8Bytes: 0,
        transition: _noChangeContext(contextId),
      ),
    );
  }
  final TerminalNoteAuthorityMutationResult queueOverflow = await authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 20, event: 34),
        bodyUtf8Bytes: 0,
        transition: _noChangeContext(contextId),
      );
  _expect(
    authority.pendingIntentCount ==
            TerminalNoteAuthorityLimits.maximumPendingIntents &&
        queueOverflow.disposition ==
            TerminalNoteAuthorityMutationDisposition.busy,
    'pending intent admission rejects item 33 without changing state',
  );
  queueGate.complete();
  await queueHead;
  final List<TerminalNoteAuthorityMutationResult> queuedResults =
      await Future.wait(queued);
  await authority.whenIdle();
  _expect(
    queuedResults.every(
      (TerminalNoteAuthorityMutationResult result) =>
          result.disposition ==
          TerminalNoteAuthorityMutationDisposition.noChange,
    ),
    'all admitted FIFO no-change intents drain without store writes',
  );

  final Completer<void> bodyGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> bodyHead = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 30, event: 1),
        bodyUtf8Bytes: TerminalNoteLimits.maximumBodyUtf8Bytes,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(30),
          body: 'body-head',
          timestamp: 40,
        ),
      );
  final List<Future<TerminalNoteAuthorityMutationResult>> bodyQueued =
      <Future<TerminalNoteAuthorityMutationResult>>[];
  for (var index = 0; index < 31; index++) {
    bodyQueued.add(
      authority.submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 30, event: index + 2),
        bodyUtf8Bytes: TerminalNoteLimits.maximumBodyUtf8Bytes,
        transition: _noChangeContext(contextId),
      ),
    );
  }
  final TerminalNoteAuthorityMutationResult bodyOverflow = await authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 30, event: 33),
        bodyUtf8Bytes: 1,
        transition: _noChangeContext(contextId),
      );
  _expect(
    authority.pendingBodyBytes ==
            TerminalNoteAuthorityLimits.maximumPendingBodyBytes &&
        bodyOverflow.disposition ==
            TerminalNoteAuthorityMutationDisposition.busy,
    'pending body admission is bounded at exactly 128 KiB',
  );
  bodyGate.complete();
  await bodyHead;
  await Future.wait(bodyQueued);
  await authority.whenIdle();
  _expect(
    authority.outstandingIntentCount == 0 && authority.pendingBodyBytes == 0,
    'queue accounting returns to zero after drain',
  );
  await authority.stop();
}

Future<void> _testBoundedTopologyAndFocusIngress() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteContextId contextId = authority.contextForPane(
    const PaneId(1),
  )!;
  var event = 1;
  await _mutate(
    authority,
    source: 41,
    event: event++,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(41),
      body: 'focus-note',
      timestamp: 60,
    ),
  );
  await _mutate(
    authority,
    source: 41,
    event: event++,
    transition: (TerminalNoteSnapshot snapshot) {
      final NoteRecord note = snapshot.noteFor(_noteId(41))!;
      return TerminalNoteAuthorityMutationPlan(
        mutation: snapshot.armOnReturn(
          noteId: note.id,
          isEligible: true,
          expectedStoreRevision: snapshot.storeRevision,
          expectedNoteRevision: note.revision,
        ),
      );
    },
  );

  final Completer<void> gate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> head = _mutate(
    authority,
    source: 41,
    event: event++,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(42),
      body: 'queue-head',
      timestamp: 61,
    ),
  );
  final TerminalNoteLifecycleResult away = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  final TerminalNoteLifecycleResult returned = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  final TerminalNoteLifecycleResult awayAgain = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  final TerminalNoteLifecycleResult duplicate = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  _expect(
    away.disposition == TerminalNoteLifecycleDisposition.accepted &&
        returned.disposition == TerminalNoteLifecycleDisposition.accepted &&
        awayAgain.disposition == TerminalNoteLifecycleDisposition.coalesced &&
        duplicate.disposition == TerminalNoteLifecycleDisposition.duplicate &&
        authority.pendingFocusEdgeCount == 2,
    'focus ingress keeps one ordered away and return edge and drops a '
    'consecutive duplicate',
  );
  gate.complete();
  await head;
  await authority.whenIdle();
  _expect(
    authority.document.snapshot.triggerFor(_noteId(41))!.phase ==
            NoteTriggerPhase.due &&
        authority.document.snapshot.deliveryFor(_noteId(41)) != null &&
        authority.pendingFocusEdgeCount == 0,
    'coalesced away then return becomes one durable due candidate',
  );

  final TerminalNoteAuthorityMutationResult bound = await authority.bindPane(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
  );
  final TerminalNoteContextId secondContext = authority.contextForPane(
    const PaneId(2),
  )!;
  _expect(
    bound.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        authority.livePaneCount == 2 &&
        authority.bindings.contextForPane(const PaneId(2)) == secondContext,
    'a new standard pane receives a durable context and runtime binding',
  );
  final TerminalNoteAuthorityMutationResult closed = await authority.closePane(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    updatedAtUtcMicros: 62,
  );
  final TerminalNoteLifecycleResult lateFocus = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    isEligible: true,
  );
  _expect(
    closed.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        authority.contextForPane(const PaneId(2)) == null &&
        authority.document.snapshot.contextFor(secondContext)!.state ==
            TerminalNoteContextState.detached &&
        lateFocus.disposition == TerminalNoteLifecycleDisposition.stale,
    'pane close supersedes ingress, removes its binding, and rejects late '
    'focus',
  );
  await authority.stop();
}

Future<void> _testPromptOverflowAndSessionReplacement() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteAuthorityMutationResult secondBound = await authority
      .bindPane(sequence: authority.nextSequence(), paneId: const PaneId(2));
  _expect(
    secondBound.disposition ==
        TerminalNoteAuthorityMutationDisposition.committed,
    'second prompt context is bound',
  );
  const TerminalSessionId firstSession = TerminalSessionId(
    paneId: PaneId(1),
    generation: 1,
  );
  const TerminalSessionId secondSession = TerminalSessionId(
    paneId: PaneId(2),
    generation: 1,
  );
  final ShellIntegrationInstanceId firstInstance = _instanceId(1);
  final ShellIntegrationInstanceId secondInstance = _instanceId(2);
  await authority.startPromptSession(
    sequence: authority.nextSequence(),
    sessionId: firstSession,
    instanceId: firstInstance,
    semanticGeneration: BigInt.one,
  );
  await authority.startPromptSession(
    sequence: authority.nextSequence(),
    sessionId: secondSession,
    instanceId: secondInstance,
    semanticGeneration: BigInt.one,
  );
  var userEvent = 1;
  await _createAndArmPromptNote(
    authority,
    paneId: const PaneId(1),
    sessionId: firstSession,
    noteId: _noteId(51),
    source: 51,
    firstEvent: userEvent,
    timestamp: 70,
  );
  userEvent += 2;
  await _createAndArmPromptNote(
    authority,
    paneId: const PaneId(2),
    sessionId: secondSession,
    noteId: _noteId(52),
    source: 51,
    firstEvent: userEvent,
    timestamp: 71,
  );
  userEvent += 2;

  final Completer<void> gate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> head = _mutate(
    authority,
    source: 51,
    event: userEvent++,
    transition: _createNote(
      contextId: authority.contextForPane(const PaneId(1))!,
      noteId: _noteId(53),
      body: 'prompt-head',
      timestamp: 72,
    ),
  );
  TerminalNoteLifecycleResult firstResult = const TerminalNoteLifecycleResult(
    TerminalNoteLifecycleDisposition.accepted,
    pendingFocusEdgeCount: 0,
    pendingPromptEventCount: 0,
  );
  for (
    var index = 1;
    index <= TerminalNoteAuthorityLimits.maximumPromptEventsPerSession + 1;
    index++
  ) {
    firstResult = authority.observePromptEvent(
      sequence: authority.nextSequence(),
      sessionId: firstSession,
      instanceId: firstInstance,
      semanticGeneration: BigInt.one,
      eventSequence: BigInt.from(index),
      action: TerminalNotePromptAction.commandOutputBegins,
    );
  }
  final List<TerminalNotePromptAction> dueCycle = <TerminalNotePromptAction>[
    TerminalNotePromptAction.commandOutputBegins,
    TerminalNotePromptAction.commandEnds,
    TerminalNotePromptAction.promptBegins,
    TerminalNotePromptAction.primaryInputReady,
  ];
  for (var index = 0; index < dueCycle.length; index++) {
    authority.observePromptEvent(
      sequence: authority.nextSequence(),
      sessionId: secondSession,
      instanceId: secondInstance,
      semanticGeneration: BigInt.one,
      eventSequence: BigInt.from(index + 1),
      action: dueCycle[index],
    );
  }
  _expect(
    firstResult.disposition == TerminalNoteLifecycleDisposition.overflowed &&
        authority.pendingPromptEventCount == dueCycle.length,
    'O-05 event 33 suspends only the overflowing ring and preserves the '
    'other session ring',
  );
  final TerminalNoteLifecycleResult duplicatePrompt = authority
      .observePromptEvent(
        sequence: authority.nextSequence(),
        sessionId: firstSession,
        instanceId: firstInstance,
        semanticGeneration: BigInt.one,
        eventSequence: BigInt.from(33),
        action: TerminalNotePromptAction.commandOutputBegins,
      );
  final TerminalNoteLifecycleResult outOfOrderPrompt = authority
      .observePromptEvent(
        sequence: authority.nextSequence(),
        sessionId: firstSession,
        instanceId: firstInstance,
        semanticGeneration: BigInt.one,
        eventSequence: BigInt.from(32),
        action: TerminalNotePromptAction.commandEnds,
      );
  _expect(
    duplicatePrompt.disposition == TerminalNoteLifecycleDisposition.duplicate &&
        outOfOrderPrompt.disposition == TerminalNoteLifecycleDisposition.stale,
    'duplicate and out-of-order prompt events are dropped before model input',
  );
  final TerminalNoteMutationResult overflowProbe = authority.document.snapshot
      .observeLifecycleBatch(
        contextId: authority.contextForPane(const PaneId(1))!,
        expectedStoreRevision: authority.document.snapshot.storeRevision,
        promptBinding: authority.promptBindingForSession(firstSession),
        promptEventOverflow: true,
      );
  _expect(
    overflowProbe.disposition == TerminalNoteMutationDisposition.accepted,
    'the coalesced overflow candidate matches the armed runtime binding '
    '(disposition=${overflowProbe.disposition.name})',
  );
  gate.complete();
  await head;
  await authority.whenIdle();
  final NoteTriggerRecord overflowedTrigger = authority.document.snapshot
      .triggerFor(_noteId(51))!;
  _expect(
    overflowedTrigger.phase == NoteTriggerPhase.suspended &&
        overflowedTrigger.suspendReason ==
            NoteTriggerSuspendReason.eventOverflow &&
        authority.document.snapshot.deliveryFor(_noteId(51)) == null,
    'O-05 overflow suspends its trigger without a false delivery '
    '(phase=${overflowedTrigger.phase.name}, '
    'reason=${overflowedTrigger.suspendReason?.name}, '
    'delivery=${authority.document.snapshot.deliveryFor(_noteId(51)) != null})',
  );
  _expect(
    authority.document.snapshot.triggerFor(_noteId(52))!.phase ==
            NoteTriggerPhase.due &&
        authority.document.snapshot.deliveryFor(_noteId(52)) != null,
    'O-05 overflow does not affect another session reaching due',
  );

  await _createAndArmPromptNote(
    authority,
    paneId: const PaneId(2),
    sessionId: secondSession,
    noteId: _noteId(54),
    source: 51,
    firstEvent: userEvent,
    timestamp: 73,
  );
  userEvent += 2;
  final Completer<void> restartGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> restartHead = _mutate(
    authority,
    source: 51,
    event: userEvent,
    transition: _createNote(
      contextId: authority.contextForPane(const PaneId(2))!,
      noteId: _noteId(55),
      body: 'restart-head',
      timestamp: 74,
    ),
  );
  authority.observePromptEvent(
    sequence: authority.nextSequence(),
    sessionId: secondSession,
    instanceId: secondInstance,
    semanticGeneration: BigInt.one,
    eventSequence: BigInt.from(5),
    action: TerminalNotePromptAction.commandOutputBegins,
  );
  final ShellIntegrationInstanceId replacementInstance = _instanceId(3);
  final Future<TerminalNoteAuthorityMutationResult> replaced = authority
      .startPromptSession(
        sequence: authority.nextSequence(),
        sessionId: secondSession,
        instanceId: replacementInstance,
        semanticGeneration: BigInt.two,
      );
  restartGate.complete();
  await restartHead;
  await replaced;
  await authority.whenIdle();
  final TerminalNoteLifecycleResult lateOld = authority.observePromptEvent(
    sequence: authority.nextSequence(),
    sessionId: secondSession,
    instanceId: secondInstance,
    semanticGeneration: BigInt.one,
    eventSequence: BigInt.from(6),
    action: TerminalNotePromptAction.commandEnds,
  );
  _expect(
    authority.document.snapshot.triggerFor(_noteId(54))!.phase ==
            NoteTriggerPhase.suspended &&
        authority.document.snapshot.triggerFor(_noteId(54))!.suspendReason ==
            NoteTriggerSuspendReason.instanceChanged &&
        authority.document.snapshot.deliveryFor(_noteId(54)) == null &&
        lateOld.disposition == TerminalNoteLifecycleDisposition.stale,
    'O-04 session replacement supersedes queued old events, suspends only '
    'the old binding, and rejects late events',
  );
  await authority.stop();
}

Future<void> _testSixtyFourPaneAndSessionBound() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    authorityGeneration: 20,
  );
  for (
    var pane = 2;
    pane <= TerminalNoteAuthorityLimits.maximumLiveContexts;
    pane++
  ) {
    final TerminalNoteAuthorityMutationResult result = await authority.bindPane(
      sequence: authority.nextSequence(),
      paneId: PaneId(pane),
    );
    _expect(
      result.disposition == TerminalNoteAuthorityMutationDisposition.committed,
      'every pane through the hard context bound is admitted',
    );
  }
  final TerminalNoteAuthorityMutationResult extraPane = await authority
      .bindPane(sequence: authority.nextSequence(), paneId: const PaneId(65));
  for (
    var pane = 1;
    pane <= TerminalNoteAuthorityLimits.maximumLiveSessions;
    pane++
  ) {
    await authority.startPromptSession(
      sequence: authority.nextSequence(),
      sessionId: TerminalSessionId(paneId: PaneId(pane), generation: 1),
      instanceId: _instanceId(pane),
      semanticGeneration: BigInt.one,
    );
  }
  _expect(
    authority.livePaneCount == 64 &&
        authority.liveSessionCount == 64 &&
        extraPane.disposition == TerminalNoteAuthorityMutationDisposition.busy,
    'topology and prompt session ownership stop exactly at 64',
  );
  final TerminalNoteAuthorityMutationResult closed = await authority.closePane(
    sequence: authority.nextSequence(),
    paneId: const PaneId(64),
    updatedAtUtcMicros: 80,
  );
  final TerminalNoteLifecycleResult late = authority.observePromptEvent(
    sequence: authority.nextSequence(),
    sessionId: const TerminalSessionId(paneId: PaneId(64), generation: 1),
    instanceId: _instanceId(64),
    semanticGeneration: BigInt.one,
    eventSequence: BigInt.one,
    action: TerminalNotePromptAction.commandOutputBegins,
  );
  _expect(
    closed.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        authority.livePaneCount == 63 &&
        authority.liveSessionCount == 63 &&
        late.disposition == TerminalNoteLifecycleDisposition.stale,
    'structural close releases both hard-bound registries and rejects late '
    'session input',
  );
  await authority.stop();
}

Future<void> _testCommitFailurePreservesPublishedDocument() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final List<TerminalNoteAuthorityPublication> publications =
      <TerminalNoteAuthorityPublication>[];
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    onPublished: publications.add,
  );
  final TerminalNoteContextId contextId = authority.bindings.contextForPane(
    const PaneId(1),
  )!;
  final BigInt publishedRevision = authority.document.snapshot.storeRevision;
  final Completer<void> failureGate = store.blockNextCommit();
  store.failNextCommit = TerminalNoteStoreFailure.workerCrashed;
  final Future<TerminalNoteAuthorityMutationResult> failed = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 40, event: 1),
        bodyUtf8Bytes: 7,
        transition: _createNote(
          contextId: contextId,
          noteId: _noteId(40),
          body: 'private',
          timestamp: 50,
        ),
      );
  final Future<TerminalNoteAuthorityMutationResult> queued = authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 40, event: 2),
        bodyUtf8Bytes: 0,
        transition: _noChangeContext(contextId),
      );
  failureGate.complete();
  final TerminalNoteAuthorityMutationResult failure = await failed;
  final TerminalNoteAuthorityMutationResult discarded = await queued;
  _expect(
    failure.disposition == TerminalNoteAuthorityMutationDisposition.failed &&
        failure.storeFailure == TerminalNoteStoreFailure.workerCrashed &&
        discarded.disposition ==
            TerminalNoteAuthorityMutationDisposition.unavailable &&
        authority.capability == TerminalNoteAuthorityCapability.unavailable &&
        authority.document.snapshot.storeRevision == publishedRevision &&
        authority.document.snapshot.noteFor(_noteId(40)) == null &&
        publications.length == 1 &&
        !failure.toString().contains('private'),
    'R-01 worker crash discards candidate and queued work while preserving '
    'the last published document',
  );
  await authority.stop();
}

Future<void> _testStartupFailureStates() async {
  final TerminalNoteAuthority unavailable = await TerminalNoteAuthority.start(
    authorityGeneration: 10,
    store: null,
    loadResult: _failureLoad(TerminalNoteStoreFailure.workerCrashed),
    restoration: null,
    paneIdsInTraversalOrder: const <PaneId>[],
    ensureQuickTerminalContext: false,
    updatedAtUtcMicros: 0,
  );
  _expect(
    unavailable.capability == TerminalNoteAuthorityCapability.unavailable &&
        unavailable.failure == TerminalNoteAuthorityFailure.invalidStartup &&
        unavailable.storeFailure == TerminalNoteStoreFailure.workerCrashed,
    'worker-unavailable startup leaves only Notes unavailable',
  );

  final _FakeAuthorityStore recoveryStore = _FakeAuthorityStore();
  final TerminalNoteAuthority recovery = await TerminalNoteAuthority.start(
    authorityGeneration: 11,
    store: recoveryStore,
    loadResult: TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.recoveryPreview,
      failure: TerminalNoteStoreFailure.recoveryRequired,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
      document: TerminalNoteStoreDocument(
        snapshot: TerminalNoteSnapshot.empty(),
      ),
    ),
    restoration: null,
    paneIdsInTraversalOrder: const <PaneId>[],
    ensureQuickTerminalContext: false,
    updatedAtUtcMicros: 0,
  );
  _expect(
    recovery.capability == TerminalNoteAuthorityCapability.recoveryRequired &&
        recovery.failure == TerminalNoteAuthorityFailure.recoveryRequired &&
        recoveryStore.commitCount == 0,
    'recovery preview is never reconciled or automatically committed',
  );

  final _FakeAuthorityStore failedReconciliationStore = _FakeAuthorityStore();
  failedReconciliationStore.failNextCommit =
      TerminalNoteStoreFailure.writeFailed;
  final TerminalNoteAuthority failedReconciliation = await _startAuthority(
    failedReconciliationStore,
    authorityGeneration: 12,
  );
  _expect(
    failedReconciliation.capability ==
            TerminalNoteAuthorityCapability.unavailable &&
        failedReconciliation.failure ==
            TerminalNoteAuthorityFailure.commitRejected &&
        failedReconciliation.document.snapshot.contexts.isEmpty,
    'failed startup reconciliation does not publish its fresh context',
  );
  await unavailable.stop();
  await recovery.stop();
  await failedReconciliation.stop();
}

Future<TerminalNoteAuthority> _startAuthority(
  _FakeAuthorityStore store, {
  int authorityGeneration = 1,
  TerminalNoteAuthorityPublicationObserver? onPublished,
}) => TerminalNoteAuthority.start(
  authorityGeneration: authorityGeneration,
  store: store,
  loadResult: store.loadResult,
  restoration: TerminalNoteRestorationArtifact.fromSnapshot(
    _onePaneRestoration(),
  ),
  paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
  ensureQuickTerminalContext: false,
  updatedAtUtcMicros: 1,
  idGenerator: _contextGenerator(authorityGeneration),
  onPublished: onPublished,
);

Future<TerminalNoteAuthorityMutationResult> _mutate(
  TerminalNoteAuthority authority, {
  required int source,
  required int event,
  required TerminalNoteAuthorityTransition transition,
}) => authority.submitMutation(
  sequence: authority.nextSequence(),
  token: _token(authority, source: source, event: event),
  bodyUtf8Bytes: 0,
  transition: transition,
);

Future<void> _createAndArmPromptNote(
  TerminalNoteAuthority authority, {
  required PaneId paneId,
  required TerminalSessionId sessionId,
  required NoteId noteId,
  required int source,
  required int firstEvent,
  required int timestamp,
}) async {
  final TerminalNoteContextId contextId = authority.contextForPane(paneId)!;
  final TerminalNoteAuthorityMutationResult created = await _mutate(
    authority,
    source: source,
    event: firstEvent,
    transition: _createNote(
      contextId: contextId,
      noteId: noteId,
      body: 'prompt-note',
      timestamp: timestamp,
    ),
  );
  final TerminalNoteAuthorityMutationResult armed = await _mutate(
    authority,
    source: source,
    event: firstEvent + 1,
    transition: (TerminalNoteSnapshot snapshot) {
      final NoteRecord note = snapshot.noteFor(noteId)!;
      return TerminalNoteAuthorityMutationPlan(
        mutation: snapshot.armAtNextPrompt(
          noteId: note.id,
          capability: TerminalNotePromptCapability.available,
          currentSemanticState: TerminalNoteSemanticState.unknown,
          binding: authority.promptBindingForSession(sessionId)!,
          expectedStoreRevision: snapshot.storeRevision,
          expectedNoteRevision: note.revision,
        ),
      );
    },
  );
  _expect(
    created.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        armed.disposition == TerminalNoteAuthorityMutationDisposition.committed,
    'prompt fixture creates and arms a note durably',
  );
}

TerminalNoteAuthorityTransition _createNote({
  required TerminalNoteContextId contextId,
  required NoteId noteId,
  required String body,
  required int timestamp,
}) =>
    (TerminalNoteSnapshot snapshot) => TerminalNoteAuthorityMutationPlan(
      mutation: snapshot.createNote(
        id: noteId,
        contextId: contextId,
        body: body,
        color: NoteColorKey.yellow,
        utcMicros: timestamp,
        expectedStoreRevision: snapshot.storeRevision,
      ),
    );

TerminalNoteAuthorityTransition _noChangeContext(
  TerminalNoteContextId contextId,
) => (TerminalNoteSnapshot snapshot) {
  final NoteContextRecord context = snapshot.contextFor(contextId)!;
  return TerminalNoteAuthorityMutationPlan(
    mutation: snapshot.setContextState(
      contextId: contextId,
      state: context.state,
      expectedStoreRevision: snapshot.storeRevision,
      expectedContextRevision: context.revision,
    ),
  );
};

TerminalNoteAuthorityIntentToken _token(
  TerminalNoteAuthority authority, {
  required int source,
  required int event,
}) => TerminalNoteAuthorityIntentToken(
  authorityGeneration: authority.authorityGeneration,
  sourceGeneration: source,
  eventSequence: event,
);

TerminalNoteContextIdGenerator _contextGenerator(int seed) {
  var value = seed;
  return TerminalNoteContextIdGenerator.forTesting(
    () => List<int>.filled(16, value++),
  );
}

TerminalRestorationSnapshot _onePaneRestoration() =>
    TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        TerminalRestorableWindow(
          placement: TerminalWindowPlacement(
            windowedFrame: TerminalWindowFrame(
              left: 100,
              top: 100,
              width: 800,
              height: 500,
            ),
            screen: null,
            fullscreen: false,
          ),
          tabs: <TerminalRestorableTab>[
            TerminalRestorableTab(
              splitTree: TerminalRestorableSplitLeaf(
                TerminalRestorablePane(workingDirectory: null),
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

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

ShellIntegrationInstanceId _instanceId(int value) =>
    ShellIntegrationInstanceId.fromHex(
      value.toRadixString(16).padLeft(32, '0'),
    );

TerminalNoteStoreResult _failureLoad(TerminalNoteStoreFailure failure) =>
    TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.unavailable,
      failure: failure,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );

final class _FakeAuthorityStore implements TerminalNoteAuthorityStorePort {
  TerminalNoteStoreDocument current = TerminalNoteStoreDocument(
    snapshot: TerminalNoteSnapshot.empty(),
  );
  final List<TerminalNoteStoreDocument> committed =
      <TerminalNoteStoreDocument>[];
  final List<Completer<void>> _gates = <Completer<void>>[];
  TerminalNoteStoreFailure? failNextCommit;
  var commitCount = 0;
  var stopCount = 0;
  var concurrentCommits = 0;
  var maximumConcurrentCommits = 0;
  var stopped = false;

  TerminalNoteStoreResult get loadResult => TerminalNoteStoreResult(
    disposition: current.snapshot.storeRevision == BigInt.zero
        ? TerminalNoteStoreDisposition.empty
        : TerminalNoteStoreDisposition.loaded,
    failure: null,
    storeRevision: current.snapshot.storeRevision,
    metrics: TerminalNoteStoreMetrics.zero,
    document: current,
  );

  Completer<void> blockNextCommit() {
    final Completer<void> gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) async {
    commitCount++;
    concurrentCommits++;
    if (concurrentCommits > maximumConcurrentCommits) {
      maximumConcurrentCommits = concurrentCommits;
    }
    try {
      if (_gates.isNotEmpty) await _gates.removeAt(0).future;
      final TerminalNoteStoreFailure? failure = failNextCommit;
      failNextCommit = null;
      if (failure != null) {
        return TerminalNoteStoreResult(
          disposition: TerminalNoteStoreDisposition.unavailable,
          failure: failure,
          storeRevision: current.snapshot.storeRevision,
          metrics: TerminalNoteStoreMetrics.zero,
        );
      }
      if (stopped ||
          candidate.snapshot.storeRevision <= current.snapshot.storeRevision) {
        return TerminalNoteStoreResult(
          disposition: TerminalNoteStoreDisposition.rejected,
          failure: TerminalNoteStoreFailure.revisionConflict,
          storeRevision: current.snapshot.storeRevision,
          metrics: TerminalNoteStoreMetrics.zero,
        );
      }
      current = candidate;
      committed.add(candidate);
      return TerminalNoteStoreResult(
        disposition: TerminalNoteStoreDisposition.committed,
        failure: null,
        storeRevision: candidate.snapshot.storeRevision,
        metrics: TerminalNoteStoreMetrics.zero,
      );
    } finally {
      concurrentCommits--;
    }
  }

  @override
  Future<TerminalNoteStoreResult> stop() async {
    stopCount++;
    stopped = true;
    return TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.stopped,
      failure: null,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
