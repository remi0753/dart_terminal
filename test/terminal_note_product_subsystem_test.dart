import 'dart:collection';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalNoteProductSubsystemTests();

Future<void> runTerminalNoteProductSubsystemTests() async {
  await _testProductionAuthorityAndTopologyLifecycle();
  await _testStartupFailureStaysContentFree();
}

Future<void> _testProductionAuthorityAndTopologyLifecycle() async {
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int workerBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-product-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final List<_FakeProductNativeChannel> channels =
      <_FakeProductNativeChannel>[];
  final Queue<TerminalNotesAttachDisposition> initialAttachments =
      Queue<TerminalNotesAttachDisposition>();
  final List<String> copiedBodies = <String>[];
  var copyAttempts = 0;
  var failCopy = false;
  var clockMicros = 3000;
  _FakeProductNativeChannel createChannel() {
    final _FakeProductNativeChannel channel = _FakeProductNativeChannel(
      nextAttachment: initialAttachments.isEmpty
          ? TerminalNotesAttachDisposition.attached
          : initialAttachments.removeFirst(),
    );
    channels.add(channel);
    return channel;
  }

  const TerminalNoteFeatureConfiguration configuration =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );
  try {
    final TerminalNoteSubsystemStartResult start =
        await TerminalNoteProductSubsystem.start(
          configuration: configuration,
          environment: <String, String>{'XDG_STATE_HOME': root.path},
          authorityGeneration: 101,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1), PaneId(2)],
          ensureQuickTerminalContext: true,
          updatedAtUtcMicros: 1000,
          copyEffect: (String body) {
            copyAttempts++;
            if (failCopy) throw StateError('injected pasteboard failure');
            copiedBodies.add(body);
            return true;
          },
          clock: () => clockMicros++,
          initializeNativeCapability: () {},
          surfaceFactory: createChannel,
        );
    _expect(
      start.capability == TerminalNoteApplicationCapability.available &&
          start.runtime is TerminalNoteProductSubsystem,
      'production factory starts one available authority',
    );
    final TerminalNoteProductSubsystem subsystem =
        start.runtime! as TerminalNoteProductSubsystem;
    PaneId? notifiedPane;
    subsystem.setSurfaceEventHandler((PaneId paneId) {
      notifiedPane = paneId;
    });
    _expect(
      subsystem.livePaneCount == 2 &&
          subsystem.liveSurfaceCount == 0 &&
          subsystem.nativeSurfaceCount == 0 &&
          channels.isEmpty &&
          TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
              productBaseline + 1 &&
          TerminalNoteAuthority.debugLiveAuthorityCount ==
              authorityBaseline + 1 &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              workerBaseline + 1,
      'store and authority are eager only after admission while native surfaces stay lazy',
    );

    final TerminalNoteProductTopologyResult quick = await subsystem.bindPane(
      paneId: const PaneId(90),
      kind: TerminalNoteContextKind.quickTerminal,
    );
    final List<TerminalNoteProductTopologyResult> standardAdds =
        await Future.wait(<Future<TerminalNoteProductTopologyResult>>[
          subsystem.bindPane(paneId: const PaneId(3)),
          subsystem.bindPane(paneId: const PaneId(4)),
        ]);
    _expect(
      quick.disposition == TerminalNoteProductTopologyDisposition.noChange &&
          standardAdds.every(
            (TerminalNoteProductTopologyResult value) =>
                value.disposition ==
                TerminalNoteProductTopologyDisposition.applied,
          ) &&
          subsystem.livePaneCount == 5,
      'Quick Terminal and concurrent standard pane binds serialize exactly',
    );

    final TerminalNoteProductTopologyResult attached = await subsystem
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 11,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    final _FakeProductNativeChannel first = channels.single;
    _expect(
      attached.disposition == TerminalNoteProductTopologyDisposition.applied &&
          attached.surfaceGeneration == 101 &&
          subsystem.surfaceGenerationForPane(const PaneId(1)) == 101 &&
          subsystem.liveSurfaceCount == 1 &&
          subsystem.nativeSurfaceCount == 1 &&
          first.operations.take(2).join(',') == 'attach,layout' &&
          first.attachments.single == (11, 11) &&
          first.projections.length == 2 &&
          first.projections.first.visibility ==
              TerminalNotesVisibility.collapsed &&
          first.projections.last.visibility ==
              TerminalNotesVisibility.expanded &&
          first.projections.last.presentationEligible &&
          first.projections.last.bodyFontMilliPoints == 15000 &&
          subsystem.surfaceContainsPoint(const PaneId(1), x: 500, y: 100) &&
          subsystem.focusSurface(
            const PaneId(1),
            TerminalNoteProductFocusTarget.rail,
          ),
      'surface attach orders native host and layout before authority projection',
    );
    first.notify();
    _expect(
      notifiedPane == const PaneId(1) &&
          first.focusTargets.single == TerminalNotesNativeFocusTarget.rail,
      'native wake-up and focus remain pane-local and content-free',
    );
    final TerminalNoteProductTopologyResult duplicate = await subsystem
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(handle: 11),
        );
    _expect(
      duplicate.disposition ==
              TerminalNoteProductTopologyDisposition.duplicate &&
          channels.length == 1,
      'duplicate surface admission creates no second native owner',
    );

    final TerminalNoteProductTopologyResult rebound = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 12,
            width: 900,
            height: 600,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    _expect(
      rebound.isAccepted &&
          first.detachCount == 1 &&
          first.attachments.last == (12, 12) &&
          first.layout == (900.0, 600.0, 2.0, 320.0),
      'renderer recovery reattaches the same surface generation to the new host',
    );
    first.nextAttachment = TerminalNotesAttachDisposition.rendererUnavailable;
    final TerminalNoteProductTopologyResult unavailable = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(handle: 13),
        );
    _expect(
      unavailable.disposition ==
              TerminalNoteProductTopologyDisposition.nativeUnavailable &&
          subsystem.liveSurfaceCount == 1 &&
          subsystem.nativeSurfaceCount == 0 &&
          first.projections.last.visibility ==
              TerminalNotesVisibility.collapsed &&
          !first.projections.last.presentationEligible,
      'failed recovery keeps one retryable adapter but hides its projection',
    );
    first.nextAttachment = TerminalNotesAttachDisposition.attached;
    final TerminalNoteProductTopologyResult retried = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 13,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    _expect(
      retried.isAccepted && subsystem.nativeSurfaceCount == 1,
      'a later topology epoch can reattach the retained native surface',
    );

    subsystem.applyLiveConfiguration(
      const TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 24,
      ),
    );
    _expect(
      first.projections.last.bodyFontMilliPoints == 24000 &&
          first.layoutCount == 3,
      'live Note font reprojects cards without terminal layout ownership',
    );
    var rejectedLaunchFixedChange = false;
    try {
      subsystem.applyLiveConfiguration(
        const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: true,
          notesNextPrompt: false,
          fontSize: 23,
        ),
      );
    } on ArgumentError {
      rejectedLaunchFixedChange = true;
    }
    _expect(
      rejectedLaunchFixedChange &&
          first.projections.last.bodyFontMilliPoints == 24000,
      'direct injection cannot mutate launch-fixed Note flags',
    );
    _expect(
      subsystem.prepareSurfaceForHostTeardown(const PaneId(1)) &&
          subsystem.nativeSurfaceCount == 0 &&
          first.projections.last.visibility == TerminalNotesVisibility.expanded,
      'host teardown detaches composition without converting it into user Close',
    );
    final TerminalNoteProductTopologyResult preparedReattach = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 14,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    _expect(
      preparedReattach.isAccepted && subsystem.nativeSurfaceCount == 1,
      'a prepared live surface can attach to a replacement host',
    );

    final TerminalNotesProjection beforeCreate = first.projections.last;
    first.intents.add(
      _nativeIntent(
        beforeCreate,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    _expect(
      first.takeIntentCount == 0 && first.results.isEmpty,
      'surface intents have no idle polling owner',
    );
    final int beforeCreateOperations = first.operations.length;
    final TerminalNoteProductTopologyResult beganCreate = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection creating = first.projections.last;
    final TerminalNotesNativeResult createResult = first.results.last;
    _expect(
      beganCreate.isAccepted &&
          creating.editorMode == TerminalNotesEditorMode.creating &&
          creating.draftGeneration > 0 &&
          creating.storeRevision == beforeCreate.storeRevision &&
          creating.projectionGeneration > beforeCreate.projectionGeneration &&
          createResult.disposition == TerminalNotesResultDisposition.accepted &&
          createResult.newProjectionGeneration ==
              creating.projectionGeneration &&
          first.operations.skip(beforeCreateOperations).take(3).join(',') ==
              'take,projection,result',
      'explicit pump applies authority create projection before accepted result',
    );
    final TerminalNoteProductTopologyResult preserved = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 14,
            visibility: TerminalNoteSurfaceVisibility.collapsed,
            foreground: true,
            occluded: false,
          ),
        );
    final TerminalNoteProductInteractionSnapshot? creatingInteraction =
        subsystem.interactionSnapshotForPane(const PaneId(1));
    final TerminalNotesProjection creatingAfterRefresh = first.projections.last;
    _expect(
      preserved.isAccepted &&
          first.projections.last.visibility ==
              TerminalNotesVisibility.expanded &&
          creatingInteraction?.editorMode == TerminalNoteEditorMode.creating &&
          creatingInteraction?.draftGeneration == creating.draftGeneration,
      'layout refresh preserves authority-owned expanded editor state',
    );

    first.intents.add(
      _nativeIntent(
        creatingAfterRefresh,
        eventGeneration: 2,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.yellow,
        body: 'remember the build command',
      ),
    );
    final TerminalNoteProductTopologyResult saved = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection savedProjection = first.projections.last;
    _expect(
      saved.isAccepted &&
          savedProjection.editorMode == TerminalNotesEditorMode.inactive &&
          savedProjection.draftGeneration == 0 &&
          savedProjection.cards.length == 1 &&
          savedProjection.cards.single.body == 'remember the build command' &&
          savedProjection.selectedToken == savedProjection.cards.single.token &&
          savedProjection.storeRevision > creatingAfterRefresh.storeRevision &&
          first.results.last.newStoreRevision == savedProjection.storeRevision,
      'Save commits durably before publishing the selected card and result',
    );

    final int selectedToken = savedProjection.selectedToken!;
    first.intents.add(
      _nativeIntent(
        savedProjection,
        eventGeneration: 3,
        kind: TerminalNotesIntentKind.beginEdit,
        cardToken: selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult beganEdit = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection editing = first.projections.last;
    final int editingToken = editing.selectedToken!;
    first.intents.add(
      _nativeIntent(
        editing,
        eventGeneration: 4,
        kind: TerminalNotesIntentKind.cancel,
        cardToken: editingToken,
      ),
    );
    final TerminalNoteProductTopologyResult cancelled = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection afterCancel = first.projections.last;
    _expect(beganEdit.isAccepted, 'Edit intent is accepted');
    _expect(
      editing.editorMode == TerminalNotesEditorMode.editing &&
          editing.draftGeneration > 0,
      'Edit projects one volatile draft generation',
    );
    _expect(cancelled.isAccepted, 'Cancel intent is accepted');
    _expect(
      afterCancel.editorMode == TerminalNotesEditorMode.inactive &&
          afterCancel.draftGeneration == 0 &&
          afterCancel.storeRevision == savedProjection.storeRevision,
      'Cancel clears volatile editor state without a store commit',
    );

    first.intents.add(
      _nativeIntent(
        afterCancel,
        eventGeneration: 5,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    final TerminalNoteProductTopologyResult beganSecondCreate = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection creatingSecond = first.projections.last;
    first.intents.add(
      _nativeIntent(
        creatingSecond,
        eventGeneration: 6,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.green,
        body: 'check the release artifact',
      ),
    );
    final TerminalNoteProductTopologyResult savedSecond = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection twoNotes = first.projections.last;
    _expect(
      beganSecondCreate.isAccepted &&
          savedSecond.isAccepted &&
          twoNotes.cards.map((TerminalNotesCard card) => card.body).join('|') ==
              'remember the build command|check the release artifact',
      'a second New and Save produces two durable ordered cards',
    );

    first.intents.add(
      _nativeIntent(
        twoNotes,
        eventGeneration: 7,
        kind: TerminalNotesIntentKind.moveEarlier,
        cardToken: twoNotes.selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult movedEarlier = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection earlierProjection = first.projections.last;
    first.intents.add(
      _nativeIntent(
        earlierProjection,
        eventGeneration: 8,
        kind: TerminalNotesIntentKind.moveLater,
        cardToken: earlierProjection.selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult movedLater = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection laterProjection = first.projections.last;
    _expect(
      movedEarlier.isAccepted &&
          earlierProjection.cards.first.body == 'check the release artifact' &&
          movedLater.isAccepted &&
          laterProjection.cards.last.body == 'check the release artifact',
      'Earlier and Later commit exact authority order before native results',
    );

    first.intents.add(
      _nativeIntent(
        laterProjection,
        eventGeneration: 9,
        kind: TerminalNotesIntentKind.changeColor,
        cardToken: laterProjection.selectedToken,
        color: TerminalNotesColor.blue,
      ),
    );
    final TerminalNoteProductTopologyResult changedColor = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection blueProjection = first.projections.last;
    first.intents.add(
      _nativeIntent(
        blueProjection,
        eventGeneration: 10,
        kind: TerminalNotesIntentKind.resolve,
        cardToken: blueProjection.selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult resolved = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection resolvedProjection = first.projections.last;
    first.intents.add(
      _nativeIntent(
        resolvedProjection,
        eventGeneration: 11,
        kind: TerminalNotesIntentKind.reopen,
        cardToken: resolvedProjection.selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult reopened = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection reopenedProjection = first.projections.last;
    final TerminalNotesCard selectedReopened = reopenedProjection.cards
        .singleWhere(
          (TerminalNotesCard card) =>
              card.token == reopenedProjection.selectedToken,
        );
    _expect(
      changedColor.isAccepted &&
          blueProjection.cards
                  .singleWhere(
                    (TerminalNotesCard card) =>
                        card.token == blueProjection.selectedToken,
                  )
                  .color ==
              TerminalNotesColor.blue &&
          resolved.isAccepted &&
          resolvedProjection.cards
                  .singleWhere(
                    (TerminalNotesCard card) =>
                        card.token == resolvedProjection.selectedToken,
                  )
                  .status ==
              TerminalNotesStatus.resolved &&
          reopened.isAccepted &&
          selectedReopened.status == TerminalNotesStatus.active,
      'color, Resolve, and Reopen flow through durable authority mutations',
    );

    final TerminalNoteProductTopologyResult attachedSource = await subsystem
        .attachSurface(
          paneId: const PaneId(3),
          configuration: _surfaceConfiguration(
            handle: 31,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: false,
            occluded: false,
          ),
        );
    final _FakeProductNativeChannel source = channels[1];
    final TerminalNotesProjection sourceEmpty = source.projections.last;
    source.intents.add(
      _nativeIntent(
        sourceEmpty,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    final TerminalNoteProductTopologyResult sourceCreate = await subsystem
        .pumpSurfaceIntent(const PaneId(3));
    final TerminalNotesProjection sourceDraft = source.projections.last;
    source.intents.add(
      _nativeIntent(
        sourceDraft,
        eventGeneration: 2,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.pink,
        body: 'detached from another terminal',
      ),
    );
    final TerminalNoteProductTopologyResult sourceSave = await subsystem
        .pumpSurfaceIntent(const PaneId(3));
    final TerminalNoteProductTopologyResult sourceClose = await subsystem
        .closePane(paneId: const PaneId(3), updatedAtUtcMicros: 4000);
    final TerminalNotesProjection refreshedCurrent = first.projections.last;
    _expect(
      attachedSource.isAccepted &&
          sourceCreate.isAccepted &&
          sourceSave.isAccepted &&
          sourceClose.isAccepted &&
          source.disposeCount == 1 &&
          refreshedCurrent.section == TerminalNotesCollectionSection.current,
      'closing another terminal moves its Note into the global Detached collection',
    );

    final int detachedStart = first.operations.length;
    first.intents.add(
      _nativeIntent(
        refreshedCurrent,
        eventGeneration: 12,
        kind: TerminalNotesIntentKind.showDetached,
      ),
    );
    final TerminalNoteProductTopologyResult showedDetached = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection detachedProjection = first.projections.last;
    final int projectionsBeforeDetachedCopy = first.projections.length;
    first.intents.add(
      _nativeIntent(
        detachedProjection,
        eventGeneration: 13,
        kind: TerminalNotesIntentKind.copy,
        cardToken: detachedProjection.cards.single.token,
        body: detachedProjection.cards.single.body,
      ),
    );
    final TerminalNoteProductTopologyResult copiedDetached = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      copiedDetached.isAccepted &&
          first.projections.length == projectionsBeforeDetachedCopy &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.accepted &&
          copiedBodies.single == 'detached from another terminal',
      'Detached copy writes only its exact body without a projection mutation',
    );
    first.intents.add(
      _nativeIntent(
        detachedProjection,
        eventGeneration: 14,
        kind: TerminalNotesIntentKind.reattach,
        cardToken: detachedProjection.cards.single.token,
      ),
    );
    final TerminalNoteProductTopologyResult reattached = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection emptyDetached = first.projections.last;
    first.intents.add(
      _nativeIntent(
        emptyDetached,
        eventGeneration: 15,
        kind: TerminalNotesIntentKind.showCurrent,
      ),
    );
    final TerminalNoteProductTopologyResult showedCurrent = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    TerminalNotesProjection currentAfterDetachedRoundTrip =
        first.projections.last;
    _expect(
      showedDetached.isAccepted &&
          detachedProjection.section ==
              TerminalNotesCollectionSection.detached &&
          detachedProjection.totalCount == 1 &&
          detachedProjection.cards.single.body ==
              'detached from another terminal' &&
          reattached.isAccepted &&
          emptyDetached.totalCount == 0 &&
          showedCurrent.isAccepted &&
          currentAfterDetachedRoundTrip.section ==
              TerminalNotesCollectionSection.current &&
          currentAfterDetachedRoundTrip.cards.length == 3 &&
          first.operations.skip(detachedStart).take(3).join(',') ==
              'take,projection,result',
      'section navigation and explicit reattach publish projection before result',
    );
    final TerminalNotesCard currentSelection = currentAfterDetachedRoundTrip
        .cards
        .singleWhere(
          (TerminalNotesCard card) => card.body == 'check the release artifact',
        );
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 16,
        kind: TerminalNotesIntentKind.selectCard,
        cardToken: currentSelection.token,
      ),
    );
    final TerminalNoteProductTopologyResult selectedAgain = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    currentAfterDetachedRoundTrip = first.projections.last;
    _expect(selectedAgain.isAccepted, 'Current card is selected again');

    final int projectionsBeforeCopy = first.projections.length;
    failCopy = true;
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 17,
        kind: TerminalNotesIntentKind.copy,
        cardToken: currentAfterDetachedRoundTrip.selectedToken,
        body: currentSelection.body,
      ),
    );
    final TerminalNoteProductTopologyResult failedCopy = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      failedCopy.disposition ==
              TerminalNoteProductTopologyDisposition.unavailable &&
          first.projections.length == projectionsBeforeCopy &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.unavailable &&
          first.results.last.newProjectionGeneration ==
              currentAfterDetachedRoundTrip.projectionGeneration &&
          copyAttempts == 2 &&
          copiedBodies.length == 1,
      'pasteboard failure stays content-free and advances no authority state',
    );
    failCopy = false;
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 18,
        kind: TerminalNotesIntentKind.copy,
        cardToken: currentAfterDetachedRoundTrip.selectedToken,
        body: currentSelection.body,
      ),
    );
    final TerminalNoteProductTopologyResult copiedCurrent = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      copiedCurrent.isAccepted &&
          first.projections.length == projectionsBeforeCopy &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.accepted &&
          first.results.last.newStoreRevision ==
              currentAfterDetachedRoundTrip.storeRevision &&
          first.results.last.newProjectionGeneration ==
              currentAfterDetachedRoundTrip.projectionGeneration &&
          copyAttempts == 3 &&
          copiedBodies.length == 2 &&
          copiedBodies.last == 'check the release artifact' &&
          !copiedCurrent.toString().contains(currentSelection.body),
      'Current copy writes the exact body once without metadata or mutation',
    );

    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 19,
        kind: TerminalNotesIntentKind.delete,
        cardToken: currentAfterDetachedRoundTrip.selectedToken,
      ),
    );
    final TerminalNoteProductTopologyResult deleted = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection afterDelete = first.projections.last;
    _expect(
      deleted.isAccepted,
      'Delete is accepted: topology=${deleted.disposition.name}, '
      'native=${first.results.last.disposition.name}',
    );
    _expect(
      afterDelete.cards.length == 2,
      'Delete removes exactly one of three Current cards',
    );
    _expect(
      afterDelete.cards.any(
            (TerminalNotesCard card) =>
                card.body == 'remember the build command',
          ) &&
          afterDelete.cards.any(
            (TerminalNotesCard card) =>
                card.body == 'detached from another terminal',
          ),
      'Delete preserves the other Current cards',
    );
    _expect(
      afterDelete.selectedToken == null,
      'Delete clears the authority selection',
    );
    final TerminalNoteProductTopologyResult emptyPump = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      emptyPump.disposition == TerminalNoteProductTopologyDisposition.noChange,
      'one explicit pump drains at most one delivered native intent',
    );

    initialAttachments.add(TerminalNotesAttachDisposition.rendererUnavailable);
    final TerminalNoteProductTopologyResult failedSurface = await subsystem
        .attachSurface(
          paneId: const PaneId(2),
          configuration: _surfaceConfiguration(handle: 21),
        );
    final _FakeProductNativeChannel failed = channels.last;
    _expect(
      failedSurface.disposition ==
              TerminalNoteProductTopologyDisposition.nativeUnavailable &&
          subsystem.liveSurfaceCount == 1 &&
          failed.disposeCount == 1 &&
          failed.detachCount == 1,
      'failed first attach releases native ownership without touching authority topology',
    );

    first.nextResultApply = TerminalNotesResultApplyDisposition.failed;
    first.intents.add(
      _nativeIntent(
        afterDelete,
        eventGeneration: 20,
        kind: TerminalNotesIntentKind.export,
      ),
    );
    final TerminalNoteProductTopologyResult faultedPump = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNoteProductTopologyResult detached = await subsystem
        .detachSurface(const PaneId(1));
    final TerminalNoteProductTopologyResult invalidClose = await subsystem
        .closePane(paneId: const PaneId(4), updatedAtUtcMicros: -1);
    final TerminalNoteProductTopologyResult closedStandard = await subsystem
        .closePane(paneId: const PaneId(2), updatedAtUtcMicros: 2000);
    final TerminalNoteProductTopologyResult closedQuick = await subsystem
        .closePane(paneId: const PaneId(90), updatedAtUtcMicros: 2001);
    _expect(
      faultedPump.disposition ==
              TerminalNoteProductTopologyDisposition.nativeUnavailable &&
          detached.disposition ==
              TerminalNoteProductTopologyDisposition.stale &&
          invalidClose.disposition ==
              TerminalNoteProductTopologyDisposition.rejected &&
          subsystem.hasPane(const PaneId(4)) &&
          closedStandard.isAccepted &&
          closedQuick.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          first.disposeCount == 1 &&
          subsystem.liveSurfaceCount == 0 &&
          subsystem.livePaneCount == 2,
      'native result fault retires the surface before pane lifecycle continues',
    );

    final Future<void> firstShutdown = subsystem.shutdown();
    final Future<void> secondShutdown = subsystem.shutdown();
    _expect(
      identical(firstShutdown, secondShutdown),
      'product subsystem shutdown is single-flight',
    );
    await firstShutdown;
    _expect(
      subsystem.isStopped &&
          subsystem.livePaneCount == 0 &&
          subsystem.liveSurfaceCount == 0 &&
          TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
              productBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount == workerBaseline,
      'shutdown returns product, authority, worker, pane, and surface owners to baseline',
    );
  } finally {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  }
}

Future<void> _testStartupFailureStaysContentFree() async {
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  var initializerCalls = 0;
  final TerminalNoteSubsystemStartResult result =
      await TerminalNoteProductSubsystem.start(
        configuration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        environment: const <String, String>{},
        authorityGeneration: 1,
        restoration: null,
        initialPaneIdsInTraversalOrder: const <PaneId>[],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 0,
        copyEffect: (_) => true,
        initializeNativeCapability: () => initializerCalls++,
      );
  _expect(
    result.capability == TerminalNoteApplicationCapability.unavailable &&
        result.runtime == null &&
        initializerCalls == 1 &&
        TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
            productBaseline,
    'invalid store environment exposes one fixed failure and no product owner',
  );

  final TerminalNoteSubsystemStartResult invalidConfiguration =
      await TerminalNoteProductSubsystem.start(
        configuration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 25,
        ),
        environment: const <String, String>{'XDG_STATE_HOME': '/unused'},
        authorityGeneration: 1,
        restoration: null,
        initialPaneIdsInTraversalOrder: const <PaneId>[],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 0,
        copyEffect: (_) => true,
        initializeNativeCapability: () => initializerCalls++,
      );
  _expect(
    invalidConfiguration.capability ==
            TerminalNoteApplicationCapability.unavailable &&
        invalidConfiguration.runtime == null &&
        initializerCalls == 1,
    'out-of-schema launch input fails before native or store ownership',
  );
}

TerminalNoteProductSurfaceConfiguration _surfaceConfiguration({
  required int handle,
  double width = 800,
  double height = 500,
  TerminalNoteSurfaceVisibility visibility =
      TerminalNoteSurfaceVisibility.collapsed,
  bool foreground = false,
  bool occluded = true,
}) => TerminalNoteProductSurfaceConfiguration(
  rendererIdentity: TerminalMetalRendererCompositionIdentity(
    handle: handle,
    generation: handle,
  ),
  paneWidth: width,
  paneHeight: height,
  backingScale: 2,
  requestedRailWidth: 320,
  visibility: visibility,
  foreground: foreground,
  occluded: occluded,
);

final class _FakeProductNativeChannel
    implements TerminalNoteNativeSurfaceChannel {
  _FakeProductNativeChannel({required this.nextAttachment});

  final List<String> operations = <String>[];
  final List<(int, int)> attachments = <(int, int)>[];
  final List<TerminalNotesProjection> projections = <TerminalNotesProjection>[];
  final Queue<TerminalNotesNativeIntent> intents =
      Queue<TerminalNotesNativeIntent>();
  final List<TerminalNotesNativeResult> results = <TerminalNotesNativeResult>[];
  TerminalNotesAttachDisposition nextAttachment;
  TerminalNotesResultApplyDisposition nextResultApply =
      TerminalNotesResultApplyDisposition.accepted;
  (double, double, double, double)? layout;
  int layoutCount = 0;
  int detachCount = 0;
  int disposeCount = 0;
  int takeIntentCount = 0;
  int discardConfirmationCount = 0;
  bool editorDirty = false;
  bool confirmingDiscard = false;
  void Function()? notificationHandler;
  final List<TerminalNotesNativeFocusTarget> focusTargets =
      <TerminalNotesNativeFocusTarget>[];

  @override
  TerminalNotesNativeSnapshot get snapshot {
    final TerminalNotesProjection projection = projections.last;
    return TerminalNotesNativeSnapshot(
      paneId: projection.paneId,
      surfaceGeneration: projection.surfaceGeneration,
      projectionGeneration: projection.projectionGeneration,
      storeRevision: projection.storeRevision,
      acceptedProjectionCount: projections.length,
      rejectedProjectionCount: 0,
      draftGeneration: projection.draftGeneration,
      activeCount: projection.activeCount,
      dueCount: projection.dueCount,
      projectedCardCount: projection.cards.length,
      materializedCardCount: projection.cards.length,
      packetBytes: 0,
      visibility: projection.visibility,
      presentationEligible: projection.presentationEligible,
      initialized: true,
      readyCue: projection.readyCue,
      darkAppearance: projection.darkAppearance,
      increaseContrast: projection.increaseContrast,
      differentiateWithoutColor: projection.differentiateWithoutColor,
      reduceMotion: projection.reduceMotion,
      systemBadgeVisible: projection.systemBadgeVisible,
      featureState: projection.featureState,
      surfaceState: projection.surfaceState,
      section: projection.section,
      editorMode: projection.editorMode,
      messageKey: projection.messageKey,
      pageStart: projection.pageStart,
      totalCount: projection.totalCount,
      bodyFontMilliPoints: projection.bodyFontMilliPoints,
      outstandingIntent: intents.isNotEmpty,
      emittedIntentCount: takeIntentCount,
      appliedResultCount: results.length,
      editorDirty: editorDirty,
      confirmingDiscard: confirmingDiscard,
      focusTarget: focusTargets.isEmpty
          ? TerminalNotesNativeFocusTarget.none
          : focusTargets.last,
    );
  }

  @override
  TerminalNotesNativePresentation get presentation {
    final TerminalNotesProjection projection = projections.last;
    final bool expanded =
        projection.visibility == TerminalNotesVisibility.expanded;
    return TerminalNotesNativePresentation(
      projectionGeneration: projection.projectionGeneration,
      paneWidth: layout?.$1 ?? 800,
      paneHeight: layout?.$2 ?? 500,
      backingScale: layout?.$3 ?? 2,
      badgeHit: const TerminalNotesRect(x: 744, y: 228, width: 44, height: 44),
      badgeVisual: const TerminalNotesRect(
        x: 744,
        y: 236,
        width: 44,
        height: 28,
      ),
      rail: const TerminalNotesRect(x: 468, y: 12, width: 320, height: 476),
      firstCard: const TerminalNotesRect(x: 480, y: 74, width: 284, height: 88),
      flags: expanded ? 2 : 1,
      materializedCardCount: projection.cards.length,
      accessibilityNodeCount: 1,
      accessibilityBodyCount: projection.cards.length,
      visibleAcknowledgementEligibleGeneration: projection.projectionGeneration,
      accessibilityAnnouncementCount: 0,
      animationMilliseconds: 0,
      bodyFontMilliPoints: projection.bodyFontMilliPoints,
      badgeDisplayCount: projection.activeCount,
    );
  }

  @override
  void setNotificationHandler(void Function()? handler) {
    notificationHandler = handler;
  }

  void notify() => notificationHandler?.call();

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    operations.add('projection');
    projections.add(projection);
    return TerminalNotesApplyDisposition.accepted;
  }

  @override
  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) {
    operations.add('attach');
    attachments.add((rendererHandle, rendererGeneration));
    final TerminalNotesAttachDisposition result = nextAttachment;
    nextAttachment = TerminalNotesAttachDisposition.attached;
    return result;
  }

  @override
  void detachFromHost() {
    operations.add('detach');
    detachCount++;
  }

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    operations.add('layout');
    layout = (paneWidth, paneHeight, backingScale, requestedRailWidth);
    layoutCount++;
  }

  @override
  TerminalNotesNativeIntent? takeIntent() {
    operations.add('take');
    takeIntentCount++;
    return intents.isEmpty ? null : intents.removeFirst();
  }

  @override
  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) {
    operations.add('result');
    results.add(result);
    final TerminalNotesResultApplyDisposition disposition = nextResultApply;
    nextResultApply = TerminalNotesResultApplyDisposition.accepted;
    return disposition;
  }

  @override
  bool focus(TerminalNotesNativeFocusTarget target) {
    focusTargets.add(target);
    return true;
  }

  @override
  bool presentDiscardConfirmation() {
    discardConfirmationCount++;
    return true;
  }

  @override
  void dispose() {
    operations.add('dispose');
    disposeCount++;
  }
}

TerminalNotesNativeIntent _nativeIntent(
  TerminalNotesProjection projection, {
  required int eventGeneration,
  required TerminalNotesIntentKind kind,
  int? cardToken,
  TerminalNotesColor? color,
  String? body,
}) => TerminalNotesNativeIntent(
  surfaceGeneration: projection.surfaceGeneration,
  projectionGeneration: projection.projectionGeneration,
  eventGeneration: eventGeneration,
  draftGeneration: projection.draftGeneration,
  cardToken: cardToken,
  expectedStoreRevision: projection.storeRevision,
  kind: kind,
  color: color,
  body: body,
);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
