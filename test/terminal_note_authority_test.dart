import 'dart:async';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNoteAuthorityTests();

Future<void> runTerminalNoteAuthorityTests() async {
  await _testStartupAndSerialDurablePublication();
  await _testDuplicateRevisionAndAdmissionBounds();
  await _testBoundedTopologyAndFocusIngress();
  await _testPromptOverflowAndSessionReplacement();
  await _testProjectionAcknowledgementAndClose();
  await _testExpandedProjectionHardBounds();
  await _testSurfaceSemanticMutationContract();
  await _testOnReturnSurfaceMutationContract();
  await _testOnReturnAutomaticRailContract();
  await _testDetachedPagingReorderAndExplicitReattach();
  await _testSixtyFourPaneAndSessionBound();
  await _testApplicationShutdownAndReopen();
  await _testRealWorkerAuthorityReopen();
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

Future<void> _testProjectionAcknowledgementAndClose() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteContextId contextId = authority.contextForPane(
    const PaneId(1),
  )!;
  await _mutate(
    authority,
    source: 56,
    event: 1,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(56),
      body: 'projected-private-body',
      timestamp: 90,
    ),
  );
  await _armOnReturn(
    authority,
    noteId: _noteId(56),
    source: 56,
    event: 2,
    isEligible: false,
  );
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  await authority.whenIdle();

  final _FakeNoteSurface surface = _FakeNoteSurface();
  final TerminalNoteSurfaceResult attached = authority.attachSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    port: surface,
  );
  _expect(
    attached.disposition == TerminalNoteSurfaceDisposition.applied &&
        attached.projection!.visibility ==
            TerminalNoteSurfaceVisibility.collapsed &&
        attached.projection!.cards.isEmpty &&
        attached.projection!.activeCount == 1 &&
        attached.projection!.dueCount == 1 &&
        !attached.projection!.toString().contains('projected-private-body'),
    'collapsed projection is content-free while retaining exact badge counts',
  );

  final TerminalNoteSurfaceResult background = authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: attached.projection!.surfaceGeneration,
    visibility: TerminalNoteSurfaceVisibility.expanded,
    foreground: false,
    occluded: false,
  );
  final TerminalNoteCardToken backgroundToken =
      background.projection!.cards.single.token;
  final TerminalNoteAuthorityMutationResult backgroundAck = await authority
      .acknowledgePresentation(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: background.projection!.surfaceGeneration,
        projectionGeneration: background.projection!.projectionGeneration,
        cardToken: backgroundToken,
        visiblyLaidOut: true,
      );
  _expect(
    background.disposition == TerminalNoteSurfaceDisposition.applied &&
        background.projection!.cards.single.body == 'projected-private-body' &&
        !background.projection!.presentationEligible &&
        backgroundAck.disposition ==
            TerminalNoteAuthorityMutationDisposition.stale &&
        authority.document.snapshot.deliveryFor(_noteId(56)) != null,
    'background expanded content cannot acknowledge a due delivery',
  );

  final TerminalNoteSurfaceResult foreground = authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: background.projection!.surfaceGeneration,
    visibility: TerminalNoteSurfaceVisibility.expanded,
    foreground: true,
    occluded: false,
  );
  surface.rejectNext = true;
  final TerminalNoteSurfaceResult rejected = authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: foreground.projection!.surfaceGeneration,
    visibility: TerminalNoteSurfaceVisibility.expanded,
    foreground: true,
    occluded: false,
  );
  _expect(
    rejected.disposition == TerminalNoteSurfaceDisposition.rejected &&
        identical(rejected.projection, foreground.projection),
    'surface apply rejection preserves the latest accepted projection',
  );

  final TerminalNoteCardToken token = foreground.projection!.cards.single.token;
  final Completer<void> ackGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> acceptedAck = authority
      .acknowledgePresentation(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: foreground.projection!.surfaceGeneration,
        projectionGeneration: foreground.projection!.projectionGeneration,
        cardToken: token,
        visiblyLaidOut: true,
      );
  final TerminalNoteAuthorityMutationResult duplicateAck = await authority
      .acknowledgePresentation(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: foreground.projection!.surfaceGeneration,
        projectionGeneration: foreground.projection!.projectionGeneration,
        cardToken: token,
        visiblyLaidOut: true,
      );
  ackGate.complete();
  final TerminalNoteAuthorityMutationResult ackResult = await acceptedAck;
  await authority.whenIdle();
  _expect(
    ackResult.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        duplicateAck.disposition ==
            TerminalNoteAuthorityMutationDisposition.duplicate &&
        authority.document.snapshot.deliveryFor(_noteId(56)) == null &&
        surface.applied.last.storeRevision ==
            authority.document.snapshot.storeRevision,
    'visible current acknowledgement commits once and republishes the latest '
    'store revision',
  );

  await _mutate(
    authority,
    source: 56,
    event: 3,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(57),
      body: 'late-ack',
      timestamp: 91,
    ),
  );
  await _armOnReturn(
    authority,
    noteId: _noteId(57),
    source: 56,
    event: 4,
    isEligible: false,
  );
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  await authority.whenIdle();
  final TerminalNoteSurfaceProjection beforeClose = surface.applied.last;
  final TerminalNoteCardProjection lateCard = beforeClose.cards.firstWhere(
    (TerminalNoteCardProjection card) => card.due,
  );
  final Completer<void> closeGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> closing = authority
      .closePane(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        updatedAtUtcMicros: 92,
      );
  final TerminalNoteAuthorityMutationResult lateAck = await authority
      .acknowledgePresentation(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: beforeClose.surfaceGeneration,
        projectionGeneration: beforeClose.projectionGeneration,
        cardToken: lateCard.token,
        visiblyLaidOut: true,
      );
  closeGate.complete();
  await closing;
  _expect(
    lateAck.disposition == TerminalNoteAuthorityMutationDisposition.stale &&
        surface.disposeCount == 1 &&
        authority.liveSurfaceCount == 0,
    'O-03 pane close invalidates the surface before durable detach and rejects '
    'a late native acknowledgement',
  );
  await authority.stop();
}

Future<void> _testExpandedProjectionHardBounds() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteContextId contextId = authority.contextForPane(
    const PaneId(1),
  )!;
  final String maximumBody = List<String>.filled(
    TerminalNoteLimits.maximumBodyUtf8Bytes,
    'x',
  ).join();
  final TerminalNoteAuthorityMutationResult created = await _mutate(
    authority,
    source: 58,
    event: 1,
    transition: (TerminalNoteSnapshot original) {
      TerminalNoteSnapshot working = original;
      late TerminalNoteMutationResult last;
      for (var index = 0; index < 65; index++) {
        last = working.createNote(
          id: _noteId(100 + index),
          contextId: contextId,
          body: maximumBody,
          color: NoteColorKey.yellow,
          utcMicros: 100 + index,
          expectedStoreRevision: working.storeRevision,
        );
        working = last.snapshot;
      }
      return TerminalNoteAuthorityMutationPlan(mutation: last);
    },
  );
  final _FakeNoteSurface surface = _FakeNoteSurface();
  final TerminalNoteSurfaceResult collapsed = authority.attachSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    port: surface,
  );
  final TerminalNoteSurfaceResult expanded = authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: collapsed.projection!.surfaceGeneration,
    visibility: TerminalNoteSurfaceVisibility.expanded,
    foreground: true,
    occluded: false,
  );
  _expect(
    created.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        collapsed.projection!.cards.isEmpty &&
        expanded.projection!.activeCount == 65 &&
        expanded.projection!.cards.length ==
            TerminalNoteProjectionLimits.maximumExpandedCards &&
        expanded.projection!.aggregateBodyUtf8Bytes ==
            TerminalNoteProjectionLimits.maximumExpandedBodyUtf8Bytes &&
        expanded.projection!.cards
                .map((TerminalNoteCardProjection card) => card.token)
                .toSet()
                .length ==
            TerminalNoteProjectionLimits.maximumExpandedCards,
    'expanded projection stops at exactly 64 cards and 256 KiB with unique '
    'ephemeral tokens',
  );
  await authority.stop();
  _expect(surface.disposeCount == 1, 'stop disposes the bounded surface once');
}

Future<void> _testSurfaceSemanticMutationContract() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  var nextIdentity = 1;
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    noteIdGenerator: TerminalNoteIdGenerator.forTesting(() {
      final List<int> bytes = List<int>.filled(16, 0);
      bytes[15] = nextIdentity++;
      return bytes;
    }),
  );
  final List<bool> committedBeforeProjection = <bool>[];
  final _FakeNoteSurface surface = _FakeNoteSurface(
    onApply: (TerminalNoteSurfaceProjection projection) {
      committedBeforeProjection.add(
        store.current.snapshot.storeRevision >= projection.storeRevision,
      );
    },
  );
  TerminalNoteSurfaceProjection projection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        port: surface,
      )
      .projection!;
  var event = 0;

  Future<TerminalNoteSurfaceIntentResult> intent(
    TerminalNoteSurfaceIntentKind kind, {
    TerminalNoteCardToken? cardToken,
    String? body,
    NoteColorKey? color,
    int? timestamp,
    TerminalNoteApprovedExportPath? exportDestination,
  }) async {
    final TerminalNoteSurfaceIntentResult result = await authority
        .submitSurfaceIntent(
          sequence: authority.nextSequence(),
          paneId: const PaneId(1),
          surfaceGeneration: projection.surfaceGeneration,
          projectionGeneration: projection.projectionGeneration,
          eventGeneration: ++event,
          draftGeneration: projection.draftGeneration,
          cardToken: cardToken,
          expectedStoreRevision: projection.storeRevision,
          kind: kind,
          updatedAtUtcMicros: timestamp,
          body: body,
          color: color,
          exportDestination: exportDestination,
        );
    if (result.projection != null) projection = result.projection!;
    return result;
  }

  Future<TerminalNoteSurfaceIntentResult> applicationAction(
    TerminalNoteApplicationSurfaceAction action,
  ) async {
    final TerminalNoteSurfaceIntentResult result = await authority
        .submitApplicationSurfaceAction(
          sequence: authority.nextSequence(),
          paneId: const PaneId(1),
          surfaceGeneration: projection.surfaceGeneration,
          projectionGeneration: projection.projectionGeneration,
          expectedStoreRevision: projection.storeRevision,
          action: action,
        );
    if (result.projection != null) projection = result.projection!;
    return result;
  }

  final int commitsBeforeApplicationActions = store.commitCount;
  final TerminalNoteSurfaceIntentResult actionOpened = await applicationAction(
    TerminalNoteApplicationSurfaceAction.toggleNotes,
  );
  final TerminalNoteSurfaceIntentResult actionClosed = await applicationAction(
    TerminalNoteApplicationSurfaceAction.toggleNotes,
  );
  final TerminalNoteSurfaceIntentResult actionCreated = await applicationAction(
    TerminalNoteApplicationSurfaceAction.newNote,
  );
  final int applicationDraftGeneration = projection.draftGeneration;
  final TerminalNoteSurfaceIntentResult blockedWhileEditing =
      await applicationAction(TerminalNoteApplicationSurfaceAction.toggleNotes);
  _expect(
    actionOpened.isAccepted &&
        actionClosed.isAccepted &&
        actionCreated.isAccepted &&
        blockedWhileEditing.disposition ==
            TerminalNoteAuthorityMutationDisposition.rejected &&
        projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.editorMode == TerminalNoteEditorMode.creating &&
        projection.draftGeneration > 0 &&
        store.commitCount == commitsBeforeApplicationActions &&
        !actionCreated.toString().contains('body'),
    'application actions toggle visibility and create a volatile draft without durable content',
  );
  final TerminalNoteSurfaceIntentResult actionCancelled = await intent(
    TerminalNoteSurfaceIntentKind.cancelEditor,
  );
  _expect(
    actionCancelled.isAccepted &&
        projection.editorMode == TerminalNoteEditorMode.inactive,
    'native cancellation resolves an application-created draft',
  );

  final TerminalNoteSurfaceIntentResult opened = await intent(
    TerminalNoteSurfaceIntentKind.open,
  );
  final TerminalNoteSurfaceIntentResult creating = await intent(
    TerminalNoteSurfaceIntentKind.beginCreate,
  );
  _expect(
    opened.disposition ==
            TerminalNoteAuthorityMutationDisposition.runtimeApplied &&
        creating.disposition ==
            TerminalNoteAuthorityMutationDisposition.runtimeApplied &&
        projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.editorMode == TerminalNoteEditorMode.creating &&
        projection.draftGeneration == applicationDraftGeneration + 1 &&
        projection.selectedToken == null,
    'surface navigation is authority-owned and starts a bounded create draft',
  );

  final TerminalNoteSurfaceProjection createProjection = projection;
  final TerminalNoteSurfaceIntentResult staleSave = await authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        projectionGeneration: projection.projectionGeneration - 1,
        eventGeneration: ++event,
        draftGeneration: projection.draftGeneration,
        cardToken: null,
        expectedStoreRevision: projection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.save,
        updatedAtUtcMicros: 100,
        body: 'alpha',
        color: NoteColorKey.yellow,
      );
  _expect(
    staleSave.disposition == TerminalNoteAuthorityMutationDisposition.stale &&
        identical(staleSave.projection, createProjection) &&
        projection.editorMode == TerminalNoteEditorMode.creating,
    'stale projection rejection preserves the authority draft state',
  );

  final Completer<void> competingGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> competingMutation =
      authority.bindPane(
        sequence: authority.nextSequence(),
        paneId: const PaneId(2),
      );
  final Future<TerminalNoteSurfaceIntentResult> conflictingSave = intent(
    TerminalNoteSurfaceIntentKind.save,
    body: 'alpha',
    color: NoteColorKey.yellow,
    timestamp: 100,
  );
  await Future<void>.delayed(Duration.zero);
  competingGate.complete();
  await competingMutation;
  final TerminalNoteSurfaceIntentResult conflict = await conflictingSave;
  _expect(
    conflict.disposition == TerminalNoteAuthorityMutationDisposition.rejected &&
        conflict.mutationFailure ==
            TerminalNoteMutationFailure.revisionConflict &&
        projection.editorMode == TerminalNoteEditorMode.creating &&
        projection.draftGeneration == createProjection.draftGeneration,
    'a racing durable revision preserves the create draft and reports conflict',
  );

  final Completer<void> createGate = store.blockNextCommit();
  final Future<TerminalNoteSurfaceIntentResult> creatingNote = intent(
    TerminalNoteSurfaceIntentKind.save,
    body: 'alpha',
    color: NoteColorKey.yellow,
    timestamp: 100,
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    authority.document.snapshot.notes.isEmpty &&
        surface.applied.last.editorMode == TerminalNoteEditorMode.creating,
    'a pending create is not projected before its durable commit',
  );
  createGate.complete();
  final TerminalNoteSurfaceIntentResult created = await creatingNote;
  final NoteId firstNoteId = authority.document.snapshot.notes.keys.single;
  _expect(
    created.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        projection.editorMode == TerminalNoteEditorMode.inactive &&
        projection.selectedToken != null &&
        projection.cards.single.body == 'alpha' &&
        committedBeforeProjection.every((bool value) => value) &&
        !projection.toString().contains(firstNoteId.canonicalValue) &&
        !projection.selectedToken.toString().contains(
          firstNoteId.canonicalValue,
        ),
    'create commits before projection and never exposes its persistent ID',
  );

  final TerminalNoteCardToken firstToken = projection.selectedToken!;
  final int commitsBeforeCopy = store.commitCount;
  final int projectionsBeforeCopy = surface.applied.length;
  final TerminalNoteSurfaceIntentResult copied = await intent(
    TerminalNoteSurfaceIntentKind.copy,
    cardToken: firstToken,
    body: 'alpha',
  );
  final TerminalNoteSurfaceIntentResult mismatchedCopy = await intent(
    TerminalNoteSurfaceIntentKind.copy,
    cardToken: firstToken,
    body: 'different body',
  );
  _expect(
    copied.disposition ==
            TerminalNoteAuthorityMutationDisposition.runtimeApplied &&
        identical(copied.projection, projection) &&
        store.commitCount == commitsBeforeCopy &&
        surface.applied.length == projectionsBeforeCopy &&
        mismatchedCopy.disposition ==
            TerminalNoteAuthorityMutationDisposition.rejected &&
        mismatchedCopy.mutationFailure ==
            TerminalNoteMutationFailure.invalidState &&
        !copied.toString().contains('alpha'),
    'copy validates the exact projected body without mutation or content result',
  );
  store.events.clear();
  final Completer<void> exportGate = store.blockNextExport();
  final TerminalNoteApprovedExportPath exportDestination =
      TerminalNoteApprovedExportPath.fromAbsolutePath(
        '/private/tmp/dart-terminal-authority-export.json',
      );
  final Future<TerminalNoteSurfaceIntentResult> exporting = authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        projectionGeneration: projection.projectionGeneration,
        eventGeneration: ++event,
        draftGeneration: projection.draftGeneration,
        cardToken: null,
        expectedStoreRevision: projection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.export,
        exportDestination: exportDestination,
      );
  await Future<void>.delayed(Duration.zero);
  final Future<TerminalNoteAuthorityMutationResult> queuedMutation = authority
      .bindPane(sequence: authority.nextSequence(), paneId: const PaneId(3));
  _expect(
    store.events.join(',') == 'export' &&
        store.exportCount == 1 &&
        store.commitCount == commitsBeforeCopy,
    'portable export occupies the same serial authority queue as mutations',
  );
  exportGate.complete();
  final TerminalNoteSurfaceIntentResult exported = await exporting;
  final TerminalNoteAuthorityMutationResult mutationAfterExport =
      await queuedMutation;
  projection = surface.applied.last;
  _expect(
    exported.disposition ==
            TerminalNoteAuthorityMutationDisposition.runtimeApplied &&
        mutationAfterExport.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        store.events.join(',') == 'export,commit' &&
        !exported.toString().contains('dart-terminal-authority-export') &&
        !exportDestination.toString().contains(
          'dart-terminal-authority-export',
        ),
    'export completes content-free before the following durable mutation',
  );
  store.failNextExport = TerminalNoteStoreFailure.permissionDenied;
  final TerminalNoteSurfaceIntentResult failedExport = await intent(
    TerminalNoteSurfaceIntentKind.export,
    exportDestination: exportDestination,
  );
  _expect(
    failedExport.disposition ==
            TerminalNoteAuthorityMutationDisposition.failed &&
        failedExport.storeFailure ==
            TerminalNoteStoreFailure.permissionDenied &&
        authority.capability == TerminalNoteAuthorityCapability.ready &&
        failedExport.storeRevision == projection.storeRevision &&
        !failedExport.toString().contains('dart-terminal-authority-export'),
    'export failure is fixed and content-free without poisoning Note authority',
  );
  final TerminalNoteSurfaceIntentResult editing = await intent(
    TerminalNoteSurfaceIntentKind.beginEdit,
    cardToken: projection.cards.single.token,
  );
  final TerminalNoteSurfaceIntentResult edited = await intent(
    TerminalNoteSurfaceIntentKind.save,
    cardToken: projection.selectedToken,
    body: 'alpha edited',
    color: NoteColorKey.blue,
    timestamp: 101,
  );
  _expect(
    editing.isAccepted &&
        edited.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        projection.cards.single.body == 'alpha edited' &&
        projection.cards.single.color == NoteColorKey.blue &&
        projection.editorMode == TerminalNoteEditorMode.inactive,
    'edit closes only after the durable body and color commit',
  );

  final TerminalNoteSurfaceIntentResult recolored = await intent(
    TerminalNoteSurfaceIntentKind.changeColor,
    cardToken: projection.selectedToken,
    color: NoteColorKey.green,
    timestamp: 102,
  );
  await intent(TerminalNoteSurfaceIntentKind.beginCreate);
  final TerminalNoteSurfaceIntentResult secondCreated = await intent(
    TerminalNoteSurfaceIntentKind.save,
    body: 'second',
    color: NoteColorKey.pink,
    timestamp: 103,
  );
  final TerminalNoteCardToken secondTokenBeforeMove = projection.selectedToken!;
  final TerminalNoteSurfaceIntentResult moved = await intent(
    TerminalNoteSurfaceIntentKind.moveEarlier,
    cardToken: secondTokenBeforeMove,
    timestamp: 104,
  );
  _expect(
    recolored.isAccepted &&
        secondCreated.isAccepted &&
        moved.isAccepted &&
        projection.cards.first.body == 'second' &&
        projection.selectedToken != secondTokenBeforeMove,
    'color, second create, and reorder are durable and rotate card tokens',
  );

  final TerminalNoteSurfaceIntentResult oldToken = await intent(
    TerminalNoteSurfaceIntentKind.changeColor,
    cardToken: secondTokenBeforeMove,
    color: NoteColorKey.purple,
    timestamp: 105,
  );
  _expect(
    oldToken.disposition == TerminalNoteAuthorityMutationDisposition.rejected &&
        oldToken.mutationFailure == TerminalNoteMutationFailure.invalidState &&
        projection.cards.first.color == NoteColorKey.pink,
    'a token from an older projection cannot mutate a persistent Note',
  );

  final TerminalNoteSurfaceIntentResult resolved = await intent(
    TerminalNoteSurfaceIntentKind.resolve,
    cardToken: projection.selectedToken,
    timestamp: 106,
  );
  final TerminalNoteSurfaceIntentResult reopened = await intent(
    TerminalNoteSurfaceIntentKind.reopen,
    cardToken: projection.selectedToken,
    timestamp: 107,
  );
  await intent(
    TerminalNoteSurfaceIntentKind.beginEdit,
    cardToken: projection.selectedToken,
  );
  final int commitsBeforeCancel = store.commitCount;
  final TerminalNoteSurfaceIntentResult cancelled = await intent(
    TerminalNoteSurfaceIntentKind.cancelEditor,
    cardToken: projection.selectedToken,
  );
  _expect(
    resolved.isAccepted &&
        reopened.isAccepted &&
        cancelled.disposition ==
            TerminalNoteAuthorityMutationDisposition.runtimeApplied &&
        projection.editorMode == TerminalNoteEditorMode.inactive &&
        store.commitCount == commitsBeforeCancel,
    'resolve/reopen commit while cancel is a projection-only transition',
  );

  final int duplicateEvent = event;
  final TerminalNoteSurfaceIntentResult duplicate = await authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        projectionGeneration: projection.projectionGeneration,
        eventGeneration: duplicateEvent,
        draftGeneration: projection.draftGeneration,
        cardToken: projection.selectedToken,
        expectedStoreRevision: projection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.delete,
        updatedAtUtcMicros: 108,
      );
  final TerminalNoteSurfaceIntentResult deleted = await intent(
    TerminalNoteSurfaceIntentKind.delete,
    cardToken: projection.selectedToken,
    timestamp: 108,
  );
  _expect(
    duplicate.disposition ==
            TerminalNoteAuthorityMutationDisposition.duplicate &&
        deleted.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        authority.document.snapshot.notes.length == 1 &&
        projection.selectedToken == null &&
        store.committedDeletions.last.length == 1 &&
        store.committedDeletions.last.single.deletionRevision ==
            projection.storeRevision,
    'duplicate events are rejected and delete commits one exact tombstone',
  );

  await intent(
    TerminalNoteSurfaceIntentKind.selectCard,
    cardToken: projection.cards.single.token,
  );
  surface.rejectNext = true;
  final TerminalNoteSurfaceIntentResult projectionFailure = await intent(
    TerminalNoteSurfaceIntentKind.changeColor,
    cardToken: projection.selectedToken,
    color: NoteColorKey.purple,
    timestamp: 109,
  );
  _expect(
    projectionFailure.disposition ==
            TerminalNoteAuthorityMutationDisposition.unavailable &&
        authority.document.snapshot.noteFor(firstNoteId)!.color ==
            NoteColorKey.purple &&
        projection.cards.single.color == NoteColorKey.green,
    'a committed mutation is not reported successful until native accepts its '
    'new projection',
  );
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      )
      .projection!;
  _expect(
    projection.cards.single.color == NoteColorKey.purple,
    'a later projection reconciliation exposes the already committed state',
  );

  final TerminalNoteSurfaceIntentResult closed = await intent(
    TerminalNoteSurfaceIntentKind.close,
  );
  _expect(
    closed.isAccepted &&
        projection.visibility == TerminalNoteSurfaceVisibility.collapsed &&
        projection.cards.isEmpty &&
        projection.totalCount == 1,
    'closing removes content from the projection without deleting the Note',
  );
  await authority.stop();
}

Future<void> _testOnReturnSurfaceMutationContract() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    noteIdGenerator: TerminalNoteIdGenerator.forTesting(
      () => List<int>.filled(16, 0x71),
    ),
  );
  final _FakeNoteSurface surface = _FakeNoteSurface();
  TerminalNoteSurfaceProjection projection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        port: surface,
      )
      .projection!;
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      )
      .projection!;
  var event = 0;

  Future<TerminalNoteSurfaceIntentResult> intent(
    TerminalNoteSurfaceIntentKind kind, {
    TerminalNoteCardToken? cardToken,
    String? body,
    NoteColorKey? color,
    int? timestamp,
  }) async {
    final TerminalNoteSurfaceIntentResult result = await authority
        .submitSurfaceIntent(
          sequence: authority.nextSequence(),
          paneId: const PaneId(1),
          surfaceGeneration: projection.surfaceGeneration,
          projectionGeneration: projection.projectionGeneration,
          eventGeneration: ++event,
          draftGeneration: projection.draftGeneration,
          cardToken: cardToken,
          expectedStoreRevision: projection.storeRevision,
          kind: kind,
          updatedAtUtcMicros: timestamp,
          body: body,
          color: color,
        );
    if (result.projection != null) projection = result.projection!;
    return result;
  }

  await intent(TerminalNoteSurfaceIntentKind.beginCreate);
  final int commitsBeforeCreate = store.commitCount;
  final BigInt revisionBeforeCreate = authority.document.snapshot.storeRevision;
  final TerminalNoteSurfaceIntentResult created = await intent(
    TerminalNoteSurfaceIntentKind.saveOnReturn,
    body: 'return to this',
    color: NoteColorKey.yellow,
    timestamp: 300,
  );
  final NoteId noteId = authority.document.snapshot.notes.keys.single;
  final NoteTriggerRecord createdTrigger = authority.document.snapshot
      .triggerFor(noteId)!;
  _expect(
    created.disposition == TerminalNoteAuthorityMutationDisposition.committed &&
        store.commitCount == commitsBeforeCreate + 1 &&
        authority.document.snapshot.storeRevision ==
            revisionBeforeCreate + BigInt.two &&
        createdTrigger.kind == NoteTriggerKind.onReturn &&
        createdTrigger.phase == NoteTriggerPhase.onReturnArmedHere &&
        authority.document.snapshot.deliveryFor(noteId) == null &&
        projection.cards.single.triggerKind == NoteTriggerKind.onReturn &&
        projection.editorMode == TerminalNoteEditorMode.inactive,
    'create and On Return arm publish through one physical durable commit',
  );

  await intent(
    TerminalNoteSurfaceIntentKind.beginEdit,
    cardToken: projection.cards.single.token,
  );
  final int commitsBeforeAlways = store.commitCount;
  final TerminalNoteSurfaceIntentResult madeAlways = await intent(
    TerminalNoteSurfaceIntentKind.saveAlwaysAvailable,
    cardToken: projection.selectedToken,
    body: 'always available',
    color: NoteColorKey.blue,
    timestamp: 301,
  );
  _expect(
    madeAlways.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        store.commitCount == commitsBeforeAlways + 1 &&
        authority.document.snapshot.triggerFor(noteId) == null &&
        authority.document.snapshot.deliveryFor(noteId) == null &&
        projection.cards.single.triggerKind == null,
    'edit and Always Available cancel the trigger in one physical commit',
  );

  final int commitsBeforeArm = store.commitCount;
  final TerminalNoteSurfaceIntentResult armed = await intent(
    TerminalNoteSurfaceIntentKind.armOnReturn,
    cardToken: projection.cards.single.token,
  );
  final BigInt legacyGeneration = authority.document.snapshot
      .triggerFor(noteId)!
      .generation;
  _expect(
    armed.isAccepted &&
        store.commitCount == commitsBeforeArm + 1 &&
        authority.document.snapshot.triggerFor(noteId)!.phase ==
            NoteTriggerPhase.onReturnArmedHere,
    'selected passive card can be armed explicitly',
  );

  await intent(
    TerminalNoteSurfaceIntentKind.beginEdit,
    cardToken: projection.selectedToken,
  );
  final TerminalNoteSurfaceIntentResult legacySaved = await intent(
    TerminalNoteSurfaceIntentKind.save,
    cardToken: projection.selectedToken,
    body: 'legacy save preserves timing',
    color: NoteColorKey.green,
    timestamp: 302,
  );
  _expect(
    legacySaved.isAccepted &&
        authority.document.snapshot.triggerFor(noteId)!.generation ==
            legacyGeneration &&
        authority.document.snapshot.triggerFor(noteId)!.phase ==
            NoteTriggerPhase.onReturnArmedHere,
    'legacy S1 Save preserves an existing trigger exactly',
  );

  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  await authority.whenIdle();
  projection = surface.applied.last;
  _expect(
    authority.document.snapshot.deliveryFor(noteId) != null &&
        projection.cards.first.due,
    'fixture reaches durable due before explicit re-arm',
  );

  final int commitsBeforeRearm = store.commitCount;
  final TerminalNoteSurfaceIntentResult rearmed = await intent(
    TerminalNoteSurfaceIntentKind.armOnReturn,
    cardToken: projection.cards.first.token,
  );
  _expect(
    rearmed.isAccepted &&
        store.commitCount == commitsBeforeRearm + 1 &&
        authority.document.snapshot.deliveryFor(noteId) == null &&
        authority.document.snapshot.triggerFor(noteId)!.phase ==
            NoteTriggerPhase.onReturnArmedHere,
    'due On Return card is atomically re-armed without an intermediate publish',
  );

  final int commitsBeforeCancel = store.commitCount;
  final TerminalNoteSurfaceIntentResult cancelled = await intent(
    TerminalNoteSurfaceIntentKind.makeAlwaysAvailable,
    cardToken: projection.cards.single.token,
  );
  _expect(
    cancelled.isAccepted &&
        store.commitCount == commitsBeforeCancel + 1 &&
        authority.document.snapshot.triggerFor(noteId) == null &&
        authority.document.snapshot.deliveryFor(noteId) == null,
    'selected armed card becomes Always Available in one durable commit',
  );
  await authority.stop();
}

Future<void> _testOnReturnAutomaticRailContract() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteContextId contextId = authority.contextForPane(
    const PaneId(1),
  )!;
  final _FakeNoteSurface firstSurface = _FakeNoteSurface();
  var projection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        port: firstSurface,
      )
      .projection!;
  final TerminalNoteLifecycleResult initialEligible = authority
      .observeEligibleFocus(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        isEligible: true,
      );
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      )
      .projection!;
  await authority.whenIdle();
  await _mutate(
    authority,
    source: 91,
    event: 1,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(91),
      body: 'automatic return rail',
      timestamp: 400,
    ),
  );
  await _mutate(
    authority,
    source: 91,
    event: 2,
    transition: (TerminalNoteSnapshot snapshot) {
      final NoteRecord note = snapshot.noteFor(_noteId(91))!;
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
  projection = firstSurface.applied.last;
  _expect(
    initialEligible.isAccepted &&
        projection.visibility == TerminalNoteSurfaceVisibility.collapsed &&
        !projection.automaticPresentation &&
        projection.dueCount == 0,
    'arming during the current eligible visit does not present or deliver',
  );

  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: projection.surfaceGeneration,
    visibility: projection.visibility,
    foreground: false,
    occluded: false,
  );
  await authority.whenIdle();
  projection = firstSurface.applied.last;
  _expect(
    authority.document.snapshot.triggerFor(_noteId(91))!.phase ==
            NoteTriggerPhase.onReturnArmedAway &&
        projection.visibility == TerminalNoteSurfaceVisibility.collapsed,
    'an exact away edge durably arms away without opening the rail',
  );

  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: projection.surfaceGeneration,
    visibility: projection.visibility,
    foreground: true,
    occluded: false,
  );
  await authority.whenIdle();
  projection = firstSurface.applied.last;
  _expect(
    projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.automaticPresentation &&
        projection.section == TerminalNoteCollectionSection.current &&
        projection.pageStart == 0 &&
        projection.cards.first.due &&
        projection.selectedToken == projection.cards.first.token &&
        authority.document.snapshot.deliveryFor(_noteId(91)) != null,
    'away-to-return durably becomes due and opens one FIFO Current rail',
  );
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      )
      .projection!;
  _expect(
    projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.automaticPresentation &&
        projection.cards.first.due,
    'duplicate layout updates preserve the automatic rail until a user intent',
  );

  final TerminalNoteSurfaceIntentResult closed = await authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        projectionGeneration: projection.projectionGeneration,
        eventGeneration: 1,
        draftGeneration: 0,
        cardToken: null,
        expectedStoreRevision: projection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.close,
      );
  projection = closed.projection!;
  final TerminalNoteLifecycleResult duplicate = authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: projection.visibility,
        foreground: true,
        occluded: false,
      )
      .projection!;
  _expect(
    closed.isAccepted &&
        duplicate.disposition == TerminalNoteLifecycleDisposition.duplicate &&
        projection.visibility == TerminalNoteSurfaceVisibility.collapsed &&
        !projection.automaticPresentation &&
        authority.document.snapshot.deliveryFor(_noteId(91)) != null,
    'manual close suppresses duplicate re-open for the same eligible visit',
  );

  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: false,
  );
  authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: projection.surfaceGeneration,
    visibility: projection.visibility,
    foreground: false,
    occluded: true,
  );
  await authority.whenIdle();
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    isEligible: true,
  );
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: projection.visibility,
        foreground: true,
        occluded: false,
      )
      .projection!;
  _expect(
    projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.automaticPresentation &&
        projection.cards.first.due,
    'a later eligible visit may re-present the still-unacknowledged due card',
  );

  final TerminalNoteSurfaceResult detached = await authority.detachSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    surfaceGeneration: projection.surfaceGeneration,
  );
  final _FakeNoteSurface replacement = _FakeNoteSurface();
  projection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        port: replacement,
      )
      .projection!;
  projection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        surfaceGeneration: projection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      )
      .projection!;
  _expect(
    detached.disposition == TerminalNoteSurfaceDisposition.applied &&
        projection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        projection.automaticPresentation &&
        projection.cards.first.due &&
        firstSurface.disposeCount == 1,
    'a replacement surface re-presents unacknowledged due without a new edge',
  );

  final TerminalNoteAuthorityMutationResult secondPane = await authority
      .bindPane(sequence: authority.nextSequence(), paneId: const PaneId(2));
  final TerminalNoteContextId secondContext = authority.contextForPane(
    const PaneId(2),
  )!;
  final _FakeNoteSurface draftSurface = _FakeNoteSurface();
  var draftProjection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(2),
        port: draftSurface,
      )
      .projection!;
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    isEligible: true,
  );
  draftProjection = authority
      .updateSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(2),
        surfaceGeneration: draftProjection.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      )
      .projection!;
  await authority.whenIdle();
  await _mutate(
    authority,
    source: 92,
    event: 1,
    transition: _createNote(
      contextId: secondContext,
      noteId: _noteId(92),
      body: 'deferred behind active draft',
      timestamp: 410,
    ),
  );
  await _mutate(
    authority,
    source: 92,
    event: 2,
    transition: (TerminalNoteSnapshot snapshot) {
      final NoteRecord note = snapshot.noteFor(_noteId(92))!;
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
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    isEligible: false,
  );
  authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    surfaceGeneration: draftProjection.surfaceGeneration,
    visibility: TerminalNoteSurfaceVisibility.collapsed,
    foreground: false,
    occluded: false,
  );
  await authority.whenIdle();
  draftProjection = draftSurface.applied.last;
  final TerminalNoteSurfaceIntentResult draftStarted = await authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(2),
        surfaceGeneration: draftProjection.surfaceGeneration,
        projectionGeneration: draftProjection.projectionGeneration,
        eventGeneration: 1,
        draftGeneration: 0,
        cardToken: null,
        expectedStoreRevision: draftProjection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.beginCreate,
      );
  draftProjection = draftStarted.projection!;
  authority.observeEligibleFocus(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    isEligible: true,
  );
  authority.updateSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(2),
    surfaceGeneration: draftProjection.surfaceGeneration,
    visibility: draftProjection.visibility,
    foreground: true,
    occluded: false,
  );
  await authority.whenIdle();
  draftProjection = draftSurface.applied.last;
  _expect(
    secondPane.isAccepted &&
        draftStarted.isAccepted &&
        draftProjection.editorMode == TerminalNoteEditorMode.creating &&
        !draftProjection.automaticPresentation &&
        draftProjection.dueCount == 1 &&
        authority.document.snapshot.deliveryFor(_noteId(92)) != null,
    'an active draft defers automatic due presentation without losing delivery',
  );
  final TerminalNoteSurfaceIntentResult draftCancelled = await authority
      .submitSurfaceIntent(
        sequence: authority.nextSequence(),
        paneId: const PaneId(2),
        surfaceGeneration: draftProjection.surfaceGeneration,
        projectionGeneration: draftProjection.projectionGeneration,
        eventGeneration: 2,
        draftGeneration: draftProjection.draftGeneration,
        cardToken: null,
        expectedStoreRevision: draftProjection.storeRevision,
        kind: TerminalNoteSurfaceIntentKind.cancelEditor,
      );
  draftProjection = draftCancelled.projection!;
  _expect(
    draftCancelled.isAccepted &&
        draftProjection.editorMode == TerminalNoteEditorMode.inactive &&
        !draftProjection.automaticPresentation &&
        draftProjection.visibility == TerminalNoteSurfaceVisibility.expanded &&
        draftProjection.cards.first.due &&
        draftProjection.selectedToken == null,
    'cancelling the draft reveals the due card in the existing user-owned rail',
  );
  await authority.stop();
}

Future<void> _testDetachedPagingReorderAndExplicitReattach() async {
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(store);
  final TerminalNoteAuthorityMutationResult secondPane = await authority
      .bindPane(sequence: authority.nextSequence(), paneId: const PaneId(2));
  final TerminalNoteContextId sourceContext = authority.contextForPane(
    const PaneId(2),
  )!;
  var mutationEvent = 0;
  for (var index = 0; index < 65; index++) {
    final NoteId noteId = _noteId(1000 + index);
    final int createdAt = 1000 + index * 2;
    final TerminalNoteAuthorityMutationResult created = await _mutate(
      authority,
      source: 63,
      event: ++mutationEvent,
      transition: _createNote(
        contextId: sourceContext,
        noteId: noteId,
        body: 'detached-$index',
        timestamp: createdAt,
      ),
    );
    final TerminalNoteAuthorityMutationResult detached = await _mutate(
      authority,
      source: 63,
      event: ++mutationEvent,
      transition: (TerminalNoteSnapshot snapshot) {
        final NoteRecord note = snapshot.noteFor(noteId)!;
        return TerminalNoteAuthorityMutationPlan(
          mutation: snapshot.detachNote(
            noteId: note.id,
            reason: TerminalNoteDetachReason.explicitDetach,
            updatedAtUtcMicros: createdAt + 1,
            expectedStoreRevision: snapshot.storeRevision,
            expectedNoteRevision: note.revision,
          ),
        );
      },
    );
    _expect(
      created.isAccepted && detached.isAccepted,
      'the global Detached fixture is committed durably',
    );
  }

  final _FakeNoteSurface surface = _FakeNoteSurface();
  TerminalNoteSurfaceProjection projection = authority
      .attachSurface(
        sequence: authority.nextSequence(),
        paneId: const PaneId(1),
        port: surface,
      )
      .projection!;
  var event = 0;
  Future<TerminalNoteSurfaceIntentResult> intent(
    TerminalNoteSurfaceIntentKind kind, {
    TerminalNoteCardToken? cardToken,
    int? timestamp,
  }) async {
    final TerminalNoteSurfaceIntentResult result = await authority
        .submitSurfaceIntent(
          sequence: authority.nextSequence(),
          paneId: const PaneId(1),
          surfaceGeneration: projection.surfaceGeneration,
          projectionGeneration: projection.projectionGeneration,
          eventGeneration: ++event,
          draftGeneration: projection.draftGeneration,
          cardToken: cardToken,
          expectedStoreRevision: projection.storeRevision,
          kind: kind,
          updatedAtUtcMicros: timestamp,
        );
    if (result.projection != null) projection = result.projection!;
    return result;
  }

  await intent(TerminalNoteSurfaceIntentKind.open);
  final TerminalNoteSurfaceIntentResult detachedSection = await intent(
    TerminalNoteSurfaceIntentKind.showDetached,
  );
  final Set<TerminalNoteCardToken> firstPageTokens = projection.cards
      .map((TerminalNoteCardProjection card) => card.token)
      .toSet();
  _expect(
    secondPane.isAccepted &&
        detachedSection.isAccepted &&
        projection.section == TerminalNoteCollectionSection.detached &&
        projection.pageStart == 0 &&
        projection.totalCount == 65 &&
        projection.cards.length == 64 &&
        projection.cards.first.body == 'detached-0' &&
        projection.cards.last.body == 'detached-63' &&
        projection.activeCount == 0 &&
        projection.dueCount == 0,
    'Detached is a global exact-total collection excluded from pane badges',
  );

  final TerminalNoteSurfaceIntentResult next = await intent(
    TerminalNoteSurfaceIntentKind.nextPage,
  );
  final TerminalNoteCardToken lastPageToken = projection.cards.single.token;
  _expect(
    next.isAccepted &&
        projection.pageStart == 64 &&
        projection.totalCount == 65 &&
        projection.cards.single.body == 'detached-64' &&
        !firstPageTokens.contains(lastPageToken),
    'Detached advances in exact 64-item pages without reusing card tokens',
  );
  final TerminalNoteSurfaceIntentResult previous = await intent(
    TerminalNoteSurfaceIntentKind.previousPage,
  );
  _expect(
    previous.isAccepted &&
        projection.pageStart == 0 &&
        projection.cards.length == 64 &&
        projection.cards.every(
          (TerminalNoteCardProjection card) =>
              !firstPageTokens.contains(card.token) &&
              card.token != lastPageToken,
        ),
    'returning to a page rotates every ephemeral token',
  );

  await intent(
    TerminalNoteSurfaceIntentKind.selectCard,
    cardToken: projection.cards[1].token,
  );
  final TerminalNoteSurfaceIntentResult reordered = await intent(
    TerminalNoteSurfaceIntentKind.moveEarlier,
    cardToken: projection.selectedToken,
    timestamp: 2000,
  );
  _expect(
    reordered.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        projection.cards.first.body == 'detached-1' &&
        projection.cards[1].body == 'detached-0',
    'Earlier reorders only the global Detached collection durably',
  );

  final TerminalNoteSurfaceIntentResult reattached = await intent(
    TerminalNoteSurfaceIntentKind.reattach,
    cardToken: projection.selectedToken,
    timestamp: 2001,
  );
  final NoteRecord attached = authority.document.snapshot.notes.values
      .singleWhere((NoteRecord note) => note.body.value == 'detached-1');
  _expect(
    reattached.disposition ==
            TerminalNoteAuthorityMutationDisposition.committed &&
        attached.attachment.contextId ==
            authority.contextForPane(const PaneId(1)) &&
        projection.section == TerminalNoteCollectionSection.detached &&
        projection.totalCount == 64 &&
        projection.selectedToken == null,
    'explicit reattach moves only the selected Note to this terminal context',
  );
  final TerminalNoteSurfaceIntentResult current = await intent(
    TerminalNoteSurfaceIntentKind.showCurrent,
  );
  _expect(
    current.isAccepted &&
        projection.section == TerminalNoteCollectionSection.current &&
        projection.totalCount == 1 &&
        projection.cards.single.body == 'detached-1',
    'the reattached Note appears in Current only after its durable commit',
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
  final List<_FakeNoteSurface> surfaces = <_FakeNoteSurface>[];
  for (
    var pane = 1;
    pane <= TerminalNoteAuthorityLimits.maximumLiveContexts;
    pane++
  ) {
    final _FakeNoteSurface surface = _FakeNoteSurface();
    surfaces.add(surface);
    final TerminalNoteSurfaceResult result = authority.attachSurface(
      sequence: authority.nextSequence(),
      paneId: PaneId(pane),
      port: surface,
    );
    _expect(
      result.disposition == TerminalNoteSurfaceDisposition.applied,
      'every surface through the 64-pane bound is attached',
    );
  }
  _expect(
    authority.livePaneCount == 64 &&
        authority.liveSessionCount == 64 &&
        authority.liveSurfaceCount == 64 &&
        extraPane.disposition == TerminalNoteAuthorityMutationDisposition.busy,
    'topology, session, and surface ownership stop exactly at 64',
  );
  final Completer<void> focusPressureGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> focusPressureHead = _mutate(
    authority,
    source: 93,
    event: 1,
    transition: _createNote(
      contextId: authority.contextForPane(const PaneId(1))!,
      noteId: _noteId(93),
      body: 'focus pressure gate',
      timestamp: 79,
    ),
  );
  var coalescedFinalEdges = 0;
  for (
    var pane = 1;
    pane <= TerminalNoteAuthorityLimits.maximumLiveContexts;
    pane++
  ) {
    authority.observeEligibleFocus(
      sequence: authority.nextSequence(),
      paneId: PaneId(pane),
      isEligible: true,
    );
    authority.observeEligibleFocus(
      sequence: authority.nextSequence(),
      paneId: PaneId(pane),
      isEligible: false,
    );
    final TerminalNoteLifecycleResult finalEdge = authority
        .observeEligibleFocus(
          sequence: authority.nextSequence(),
          paneId: PaneId(pane),
          isEligible: true,
        );
    if (finalEdge.disposition == TerminalNoteLifecycleDisposition.coalesced) {
      coalescedFinalEdges++;
    }
  }
  _expect(
    authority.pendingFocusEdgeCount == 128 && coalescedFinalEdges == 64,
    '64-context pressure retains two ordered edges per context and coalesces '
    'each final state',
  );
  focusPressureGate.complete();
  await focusPressureHead;
  await authority.whenIdle();
  _expect(
    authority.pendingFocusEdgeCount == 0,
    '64-context focus pressure drains every final eligibility state',
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
        authority.liveSurfaceCount == 63 &&
        surfaces.last.disposeCount == 1 &&
        late.disposition == TerminalNoteLifecycleDisposition.stale,
    'structural close releases both hard-bound registries and rejects late '
    'session input',
  );
  await authority.stop();
  _expect(
    surfaces.every((_FakeNoteSurface surface) => surface.disposeCount == 1),
    'full teardown disposes all 64 surface ports exactly once',
  );
}

Future<void> _testApplicationShutdownAndReopen() async {
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final _FakeAuthorityStore store = _FakeAuthorityStore();
  final TerminalNoteAuthority authority = await _startAuthority(
    store,
    authorityGeneration: 30,
  );
  final TerminalNoteContextId contextId = authority.contextForPane(
    const PaneId(1),
  )!;
  await _mutate(
    authority,
    source: 59,
    event: 1,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(59),
      body: 'shutdown-note',
      timestamp: 200,
    ),
  );
  final _FakeNoteSurface surface = _FakeNoteSurface();
  authority.attachSurface(
    sequence: authority.nextSequence(),
    paneId: const PaneId(1),
    port: surface,
  );
  final TerminalNoteRestorationArtifact restoration =
      TerminalNoteRestorationArtifact.fromSnapshot(_onePaneRestoration());
  final TerminalNoteRestorationCaptureArtifact capture =
      TerminalNoteRestorationCaptureArtifact.fromArtifact(
        restoration: restoration,
        paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
      );

  store.events.clear();
  final Completer<void> drainGate = store.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> drainingMutation = _mutate(
    authority,
    source: 59,
    event: 2,
    transition: _createNote(
      contextId: contextId,
      noteId: _noteId(60),
      body: 'drained-note',
      timestamp: 201,
    ),
  );
  TerminalNoteRestorationArtifact? persistedRestoration;
  final Future<TerminalNoteAuthorityShutdownResult> shuttingDown = authority
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 202,
        commitRestoration: (TerminalNoteRestorationArtifact artifact) async {
          store.events.add('restoration');
          persistedRestoration = artifact;
          return true;
        },
      );
  final TerminalNoteAuthorityMutationResult frozen = await authority
      .submitMutation(
        sequence: authority.nextSequence(),
        token: _token(authority, source: 59, event: 3),
        bodyUtf8Bytes: 0,
        transition: _noChangeContext(contextId),
      );
  drainGate.complete();
  await drainingMutation;
  final TerminalNoteAuthorityShutdownResult shutdown = await shuttingDown;
  _expect(
    frozen.disposition ==
            TerminalNoteAuthorityMutationDisposition.unavailable &&
        shutdown.isSuccess &&
        shutdown.persistence!.isSuccess &&
        shutdown.surfaceDisposeCount == 1 &&
        surface.disposeCount == 1 &&
        authority.capability == TerminalNoteAuthorityCapability.stopped &&
        authority.livePaneCount == 0 &&
        authority.liveSessionCount == 0 &&
        authority.liveSurfaceCount == 0 &&
        store.events.indexOf('restoration') > store.events.indexOf('commit') &&
        store.events.last == 'stop' &&
        TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline,
    'application shutdown freezes ingress, drains admitted work, persists '
    'restoration before its Note binding, disposes surfaces, and stops',
  );

  final _FakeAuthorityStore reopenedStore = _FakeAuthorityStore()
    ..current = store.current;
  final TerminalNoteAuthority reopened = await TerminalNoteAuthority.start(
    authorityGeneration: 31,
    store: reopenedStore,
    loadResult: reopenedStore.loadResult,
    restoration: persistedRestoration,
    paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
    ensureQuickTerminalContext: false,
    updatedAtUtcMicros: 203,
    idGenerator: _contextGenerator(31),
  );
  _expect(
    reopened.capability == TerminalNoteAuthorityCapability.ready &&
        reopened.document.snapshot.noteFor(_noteId(59)) != null &&
        reopened.document.snapshot.noteFor(_noteId(60)) != null &&
        reopened.contextForPane(const PaneId(1)) == contextId,
    'a new authority generation reopens the exact bound context and both '
    'pre-freeze mutations',
  );
  final _FakeNoteSurface reopenedSurface = _FakeNoteSurface();
  final TerminalNoteSurfaceResult reopenedProjection = reopened.attachSurface(
    sequence: reopened.nextSequence(),
    paneId: const PaneId(1),
    port: reopenedSurface,
  );
  _expect(
    reopenedProjection.projection!.surfaceGeneration !=
            surface.applied.first.surfaceGeneration &&
        reopenedProjection.projection!.surfaceGeneration == 31,
    'reopen derives a fresh surface generation from the new authority '
    'generation',
  );
  final TerminalNoteAuthorityShutdownResult reopenedShutdown = await reopened
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 204,
        commitRestoration: (_) async => true,
      );
  _expect(
    reopenedShutdown.isSuccess &&
        reopenedSurface.disposeCount == 1 &&
        TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline,
    'reopened authority performs a complete second teardown',
  );

  final _FakeAuthorityStore failedStore = _FakeAuthorityStore();
  final TerminalNoteAuthority failed = await _startAuthority(
    failedStore,
    authorityGeneration: 32,
  );
  failedStore.events.clear();
  final TerminalNoteAuthorityShutdownResult persistenceFailure = await failed
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 205,
        commitRestoration: (_) async => false,
      );
  _expect(
    persistenceFailure.disposition ==
            TerminalNoteAuthorityShutdownDisposition.persistenceFailed &&
        !persistenceFailure.persistence!.noteCommitAttempted &&
        failedStore.events.where((String event) => event == 'commit').isEmpty &&
        failedStore.events.last == 'stop',
    'restoration failure skips Note commit but still releases the store',
  );

  final _FakeAuthorityStore timeoutStore = _FakeAuthorityStore();
  final TerminalNoteAuthority timedOut = await _startAuthority(
    timeoutStore,
    authorityGeneration: 33,
  );
  final TerminalNoteContextId timeoutContext = timedOut.contextForPane(
    const PaneId(1),
  )!;
  final Completer<void> timeoutGate = timeoutStore.blockNextCommit();
  final Future<TerminalNoteAuthorityMutationResult> lateMutation = _mutate(
    timedOut,
    source: 60,
    event: 1,
    transition: _createNote(
      contextId: timeoutContext,
      noteId: _noteId(61),
      body: 'timeout-candidate',
      timestamp: 206,
    ),
  );
  final TerminalNoteAuthorityShutdownResult timeout = await timedOut
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 207,
        commitRestoration: (_) async => true,
        drainTimeout: const Duration(milliseconds: 1),
      );
  timeoutGate.complete();
  final TerminalNoteAuthorityMutationResult lateResult = await lateMutation;
  _expect(
    timeout.disposition ==
            TerminalNoteAuthorityShutdownDisposition.drainTimedOut &&
        lateResult.disposition ==
            TerminalNoteAuthorityMutationDisposition.unavailable &&
        timedOut.capability == TerminalNoteAuthorityCapability.stopped &&
        TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline,
    'drain deadline discards a late candidate and still completes teardown',
  );
}

Future<void> _testRealWorkerAuthorityReopen() async {
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int clientBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-authority-reopen-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final TerminalNoteStoreLocation location =
      TerminalNoteStoreLocation.fromAbsolutePath('${root.path}/notes');
  final TerminalNoteRestorationArtifact restoration =
      TerminalNoteRestorationArtifact.fromSnapshot(_onePaneRestoration());
  final TerminalNoteRestorationCaptureArtifact capture =
      TerminalNoteRestorationCaptureArtifact.fromArtifact(
        restoration: restoration,
        paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
      );
  TerminalNoteAuthority? first;
  TerminalNoteAuthority? reopened;
  try {
    first = await TerminalNoteAuthority.startWorker(
      location: location,
      authorityGeneration: 40,
      restoration: restoration,
      paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
      ensureQuickTerminalContext: false,
      updatedAtUtcMicros: 300,
      idGenerator: _contextGenerator(40),
    );
    final TerminalNoteContextId contextId = first.contextForPane(
      const PaneId(1),
    )!;
    await _mutate(
      first,
      source: 61,
      event: 1,
      transition: _createNote(
        contextId: contextId,
        noteId: _noteId(62),
        body: 'real-worker-reopen',
        timestamp: 301,
      ),
    );
    final TerminalNoteAuthorityShutdownResult firstShutdown = await first
        .shutdownApplication(
          capture: capture,
          updatedAtUtcMicros: 302,
          commitRestoration: (_) async => true,
        );
    _expect(
      firstShutdown.isSuccess &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount == clientBaseline,
      'real worker shutdown releases its isolate client and store lock',
    );

    reopened = await TerminalNoteAuthority.startWorker(
      location: location,
      authorityGeneration: 41,
      restoration: restoration,
      paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
      ensureQuickTerminalContext: false,
      updatedAtUtcMicros: 303,
      idGenerator: _contextGenerator(41),
    );
    _expect(
      reopened.capability == TerminalNoteAuthorityCapability.ready &&
          reopened.contextForPane(const PaneId(1)) == contextId &&
          reopened.document.snapshot.noteFor(_noteId(62))!.body.value ==
              'real-worker-reopen',
      'real worker reopen loads and reattaches the exact committed context',
    );
    final TerminalNoteAuthorityShutdownResult reopenedShutdown = await reopened
        .shutdownApplication(
          capture: capture,
          updatedAtUtcMicros: 304,
          commitRestoration: (_) async => true,
        );
    _expect(
      reopenedShutdown.isSuccess &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              clientBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline,
      'full real close/reopen leaves authority and worker handles at zero',
    );
  } finally {
    if (first != null &&
        first.capability != TerminalNoteAuthorityCapability.stopped) {
      await first.stop();
    }
    if (reopened != null &&
        reopened.capability != TerminalNoteAuthorityCapability.stopped) {
      await reopened.stop();
    }
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  }
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
  TerminalNoteIdGenerator? noteIdGenerator,
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
  noteIdGenerator: noteIdGenerator,
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

Future<TerminalNoteAuthorityMutationResult> _armOnReturn(
  TerminalNoteAuthority authority, {
  required NoteId noteId,
  required int source,
  required int event,
  required bool isEligible,
}) => _mutate(
  authority,
  source: source,
  event: event,
  transition: (TerminalNoteSnapshot snapshot) {
    final NoteRecord note = snapshot.noteFor(noteId)!;
    return TerminalNoteAuthorityMutationPlan(
      mutation: snapshot.armOnReturn(
        noteId: note.id,
        isEligible: isEligible,
        expectedStoreRevision: snapshot.storeRevision,
        expectedNoteRevision: note.revision,
      ),
    );
  },
);

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
  final List<Completer<void>> _exportGates = <Completer<void>>[];
  final List<String> events = <String>[];
  final List<List<TerminalNoteDeletionTombstone>> committedDeletions =
      <List<TerminalNoteDeletionTombstone>>[];
  TerminalNoteStoreFailure? failNextCommit;
  TerminalNoteStoreFailure? failNextExport;
  var commitCount = 0;
  var exportCount = 0;
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

  Completer<void> blockNextExport() {
    final Completer<void> gate = Completer<void>();
    _exportGates.add(gate);
    return gate;
  }

  @override
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) async {
    events.add('commit');
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
      committedDeletions.add(
        List<TerminalNoteDeletionTombstone>.unmodifiable(deletions),
      );
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
  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath destination,
  ) async {
    events.add('export');
    exportCount++;
    if (_exportGates.isNotEmpty) await _exportGates.removeAt(0).future;
    final TerminalNoteStoreFailure? failure = failNextExport;
    failNextExport = null;
    if (failure != null || stopped) {
      return TerminalNoteStoreResult(
        disposition: TerminalNoteStoreDisposition.unavailable,
        failure: failure ?? TerminalNoteStoreFailure.invalidState,
        storeRevision: current.snapshot.storeRevision,
        metrics: TerminalNoteStoreMetrics.zero,
      );
    }
    return TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.exported,
      failure: null,
      storeRevision: current.snapshot.storeRevision,
      metrics: TerminalNoteStoreMetrics.zero,
    );
  }

  @override
  Future<TerminalNoteStoreResult> stop() async {
    events.add('stop');
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

final class _FakeNoteSurface implements TerminalNoteSurfacePort {
  _FakeNoteSurface({this.onApply});

  final void Function(TerminalNoteSurfaceProjection projection)? onApply;
  final List<TerminalNoteSurfaceProjection> applied =
      <TerminalNoteSurfaceProjection>[];
  var rejectNext = false;
  var disposed = false;
  var disposeCount = 0;

  @override
  bool applyProjection(TerminalNoteSurfaceProjection projection) {
    if (disposed) return false;
    if (rejectNext) {
      rejectNext = false;
      return false;
    }
    onApply?.call(projection);
    applied.add(projection);
    return true;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    disposeCount++;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
