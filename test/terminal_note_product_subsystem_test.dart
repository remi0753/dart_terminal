import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalNoteProductSubsystemTests();

Future<void> runTerminalNoteProductSubsystemTests() async {
  await _testProductionAuthorityAndTopologyLifecycle();
  await _testOnReturnProductIntentBridge();
  await _testVisibleOnReturnAcknowledgement();
  await _testOrderedShutdownAndExactContextRestart();
  await _testStartupFailureStaysContentFree();
}

Future<void> _testOrderedShutdownAndExactContextRestart() async {
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int workerBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-ordered-shutdown-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final TerminalRestorationPersistence restorationPersistence =
      TerminalRestorationPersistence(
        FileTerminalRestorationStore('${root.path}/restoration.json'),
      );
  final TerminalNoteRestorationArtifact restoration =
      TerminalNoteRestorationArtifact.fromSnapshot(_onePaneRestoration());
  final TerminalNoteRestorationCaptureArtifact firstCapture =
      TerminalNoteRestorationCaptureArtifact.fromArtifact(
        restoration: restoration,
        paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
      );
  const TerminalNoteFeatureConfiguration configuration =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );
  TerminalNoteProductSubsystem? first;
  TerminalNoteProductSubsystem? reopened;
  try {
    final _FakeProductNativeChannel firstChannel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final TerminalNoteSubsystemStartResult firstStart =
        await TerminalNoteProductSubsystem.start(
          configuration: configuration,
          environment: <String, String>{'XDG_STATE_HOME': root.path},
          authorityGeneration: 201,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 5000,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => firstChannel,
          clock: () => 5001,
        );
    first = firstStart.runtime! as TerminalNoteProductSubsystem;
    await first.attachSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 31,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      ),
    );
    TerminalNotesProjection projection = firstChannel.projections.last;
    firstChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    await first.pumpSurfaceIntent(const PaneId(1));
    projection = firstChannel.projections.last;
    firstChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 2,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.blue,
        body: 'exact-context-note',
      ),
    );
    await first.pumpSurfaceIntent(const PaneId(1));

    Future<bool> commitRestoration(
      TerminalNoteRestorationArtifact artifact,
    ) async =>
        (await restorationPersistence.saveExactEncoded(artifact.exactEncoded))
            .disposition ==
        TerminalRestorationSaveDisposition.saved;

    final Future<TerminalNoteAuthorityShutdownResult> firstShutdown = first
        .shutdownApplication(
          capture: firstCapture,
          updatedAtUtcMicros: 5002,
          commitRestoration: commitRestoration,
        );
    _expect(
      identical(
        firstShutdown,
        first.shutdownApplication(
          capture: firstCapture,
          updatedAtUtcMicros: 5003,
          commitRestoration: (_) async => false,
        ),
      ),
      'ordered product shutdown is single-flight',
    );
    final TerminalNoteAuthorityShutdownResult firstResult = await firstShutdown;
    final TerminalRestorationLoadResult loaded = await restorationPersistence
        .load();
    _expect(
      firstResult.isSuccess &&
          firstResult.persistence?.isSuccess == true &&
          loaded.disposition == TerminalRestorationLoadDisposition.restored &&
          loaded.exactEncoded == restoration.exactEncoded &&
          first.isStopped &&
          first.livePaneCount == 0 &&
          first.liveSurfaceCount == 0 &&
          firstChannel.disposeCount == 1,
      'product shutdown commits exact restoration before retiring all owners',
    );

    final _FakeProductNativeChannel reopenedChannel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final TerminalNoteSubsystemStartResult reopenedStart =
        await TerminalNoteProductSubsystem.start(
          configuration: configuration,
          environment: <String, String>{'XDG_STATE_HOME': root.path},
          authorityGeneration: 202,
          restoration: TerminalNoteRestorationArtifact.fromExactEncoded(
            loaded.exactEncoded!,
          ),
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(11)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 5004,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => reopenedChannel,
          clock: () => 5005,
        );
    reopened = reopenedStart.runtime! as TerminalNoteProductSubsystem;
    await reopened.attachSurface(
      paneId: const PaneId(11),
      configuration: _surfaceConfiguration(
        handle: 32,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      ),
    );
    _expect(
      reopenedChannel.projections.last.cards.single.body ==
          'exact-context-note',
      'restart reattaches the durable Note only to the exact restored context',
    );
    final TerminalNoteAuthorityShutdownResult reopenedResult = await reopened
        .shutdownApplication(
          capture: TerminalNoteRestorationCaptureArtifact.fromArtifact(
            restoration: restoration,
            paneIdsInTraversalOrder: const <PaneId>[PaneId(11)],
          ),
          updatedAtUtcMicros: 5006,
          commitRestoration: commitRestoration,
        );
    _expect(
      reopenedResult.isSuccess &&
          reopenedChannel.disposeCount == 1 &&
          TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
              productBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount == workerBaseline,
      'exact restart and second ordered shutdown leave every owner at baseline',
    );
  } finally {
    if (first != null && !first.isStopped) await first.shutdown();
    if (reopened != null && !reopened.isStopped) await reopened.shutdown();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<void> _testProductionAuthorityAndTopologyLifecycle() async {
  final englishPanel = TerminalNoteExportPanel.configuration(
    TerminalNotesLocale.english,
  );
  final japanesePanel = TerminalNoteExportPanel.configuration(
    TerminalNotesLocale.japanese,
  );
  _expect(
    englishPanel.title == 'Export Notes' &&
        englishPanel.message.contains('full text of all notes') &&
        englishPanel.prompt == 'Export' &&
        englishPanel.defaultFileName == 'Dart Terminal Notes.json' &&
        englishPanel.allowedFileExtension == 'json' &&
        japanesePanel.title == 'ノートを書き出す' &&
        japanesePanel.message.contains('すべてのノート本文') &&
        japanesePanel.message.contains('保管や共有') &&
        japanesePanel.prompt == '書き出す' &&
        japanesePanel.defaultFileName == 'Dart Terminal ノート.json' &&
        japanesePanel.allowedFileExtension == 'json',
    'English and Japanese save panels warn before portable content export',
  );
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
  var failExportChoice = false;
  TerminalNoteApprovedExportPath? nextExportDestination;
  final List<TerminalNotesLocale> exportLocales = <TerminalNotesLocale>[];
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
          exportDestinationChooser: (TerminalNotesLocale locale) {
            exportLocales.add(locale);
            if (failExportChoice) {
              throw StateError('injected save-panel failure');
            }
            return nextExportDestination;
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

    final File exported = File('${root.path}/portable-notes.json');
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 19,
        kind: TerminalNotesIntentKind.export,
      ),
    );
    final TerminalNoteProductTopologyResult cancelledExport = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      cancelledExport.disposition ==
              TerminalNoteProductTopologyDisposition.rejected &&
          !exported.existsSync() &&
          exportLocales.length == 1 &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.rejected,
      'save-panel cancellation completes without any portable export write',
    );
    nextExportDestination = TerminalNoteApprovedExportPath.fromAbsolutePath(
      exported.path,
    );
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 20,
        kind: TerminalNotesIntentKind.export,
      ),
    );
    final TerminalNoteProductTopologyResult exportedNotes = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final Map<String, dynamic> portable =
        jsonDecode(exported.readAsStringSync().trim()) as Map<String, dynamic>;
    final List<dynamic> portableNotes = portable['notes'] as List<dynamic>;
    _expect(
      exportedNotes.isAccepted &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.accepted &&
          first.results.last.newStoreRevision ==
              currentAfterDetachedRoundTrip.storeRevision &&
          first.results.last.newProjectionGeneration ==
              currentAfterDetachedRoundTrip.projectionGeneration &&
          exportLocales.length == 2 &&
          exportLocales.every(
            (TerminalNotesLocale locale) =>
                locale == TerminalNotesLocale.english,
          ) &&
          portable.keys.join(',') == 'format,version,notes' &&
          portable['format'] == TerminalNotePortableExportCodec.format &&
          portable['version'] == TerminalNotePortableExportCodec.version &&
          portableNotes.length == 3 &&
          portableNotes.every(
            (dynamic value) =>
                (value as Map<String, dynamic>).keys.join(',') ==
                'body,color,status,order,trigger',
          ) &&
          !exportedNotes.toString().contains(exported.path) &&
          !exportedNotes.toString().contains(currentSelection.body),
      'approved export writes only portable fields and returns no path or content',
    );
    failExportChoice = true;
    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 21,
        kind: TerminalNotesIntentKind.export,
      ),
    );
    final TerminalNoteProductTopologyResult failedExportChoice = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      failedExportChoice.disposition ==
              TerminalNoteProductTopologyDisposition.unavailable &&
          first.results.last.disposition ==
              TerminalNotesResultDisposition.unavailable &&
          first.results.last.newStoreRevision ==
              currentAfterDetachedRoundTrip.storeRevision &&
          first.results.last.newProjectionGeneration ==
              currentAfterDetachedRoundTrip.projectionGeneration &&
          !failedExportChoice.toString().contains(exported.path),
      'save-panel or path-validation failure is fixed and content-free',
    );
    failExportChoice = false;

    first.intents.add(
      _nativeIntent(
        currentAfterDetachedRoundTrip,
        eventGeneration: 22,
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

    final TerminalNoteProductTopologyResult actionClosed = await subsystem
        .performAction(
          const PaneId(1),
          TerminalNoteProductActionKind.toggleNotes,
        );
    final TerminalNoteProductTopologyResult actionOpened = await subsystem
        .performAction(
          const PaneId(1),
          TerminalNoteProductActionKind.toggleNotes,
        );
    final TerminalNoteProductTopologyResult actionCreated = await subsystem
        .performAction(const PaneId(1), TerminalNoteProductActionKind.newNote);
    final TerminalNotesProjection actionDraft = first.projections.last;
    _expect(
      actionClosed.isAccepted &&
          actionOpened.isAccepted &&
          actionCreated.isAccepted &&
          actionDraft.visibility == TerminalNotesVisibility.expanded &&
          actionDraft.editorMode == TerminalNotesEditorMode.creating &&
          !subsystem.canPerformAction(
            const PaneId(1),
            TerminalNoteProductActionKind.toggleNotes,
          ),
      'product actions route toggle and new through the authority without native synthesis',
    );
    first.intents.add(
      _nativeIntent(
        actionDraft,
        eventGeneration: 23,
        kind: TerminalNotesIntentKind.cancel,
      ),
    );
    final TerminalNoteProductTopologyResult actionCancelled = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    final TerminalNotesProjection afterActionCancel = first.projections.last;
    _expect(
      actionCancelled.isAccepted &&
          afterActionCancel.editorMode == TerminalNotesEditorMode.inactive,
      'native cancellation resolves an action-created volatile draft',
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
        afterActionCancel,
        eventGeneration: 24,
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

Future<void> _testOnReturnProductIntentBridge() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-on-return-product-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  TerminalNoteProductSubsystem? enabled;
  TerminalNoteProductSubsystem? disabled;
  try {
    final _FakeProductNativeChannel enabledChannel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final _FakeProductNativeChannel quickChannel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final Queue<_FakeProductNativeChannel> enabledChannels =
        Queue<_FakeProductNativeChannel>.of(<_FakeProductNativeChannel>[
          enabledChannel,
          quickChannel,
        ]);
    final TerminalNoteSubsystemStartResult enabledStart =
        await TerminalNoteProductSubsystem.start(
          configuration: const TerminalNoteFeatureConfiguration(
            notes: true,
            notesOnReturn: true,
            notesNextPrompt: false,
            fontSize: 15,
          ),
          environment: <String, String>{
            'XDG_STATE_HOME': '${root.path}/enabled',
          },
          authorityGeneration: 301,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: true,
          updatedAtUtcMicros: 6000,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: enabledChannels.removeFirst,
          clock: () => 6001,
        );
    enabled = enabledStart.runtime! as TerminalNoteProductSubsystem;
    await enabled.attachSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 61,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      ),
    );
    TerminalNotesProjection projection = enabledChannel.projections.last;
    _expect(
      projection.onReturnEnabled,
      'effective On Return capability reaches the native projection',
    );
    enabledChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    await enabled.pumpSurfaceIntent(const PaneId(1));
    projection = enabledChannel.projections.last;
    enabledChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 2,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.yellow,
        body: 'return product note',
      ),
    );
    final TerminalNoteProductTopologyResult saved = await enabled
        .pumpSurfaceIntent(const PaneId(1));
    projection = enabledChannel.projections.last;
    _expect(
      saved.isAccepted &&
          projection.cards.single.triggerKind ==
              TerminalNotesTriggerKind.onReturn &&
          projection.cards.single.triggerPhase ==
              TerminalNotesTriggerPhase.onReturnArmedHere &&
          enabledChannel.results.last.disposition ==
              TerminalNotesResultDisposition.accepted,
      'native Save On Return maps to one durable armed product projection',
    );

    enabledChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 3,
        kind: TerminalNotesIntentKind.makeAlwaysAvailable,
        cardToken: projection.cards.single.token,
      ),
    );
    final TerminalNoteProductTopologyResult madeAlways = await enabled
        .pumpSurfaceIntent(const PaneId(1));
    projection = enabledChannel.projections.last;
    enabledChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 4,
        kind: TerminalNotesIntentKind.armOnReturn,
        cardToken: projection.cards.single.token,
      ),
    );
    final TerminalNoteProductTopologyResult rearmed = await enabled
        .pumpSurfaceIntent(const PaneId(1));
    projection = enabledChannel.projections.last;
    _expect(
      madeAlways.isAccepted &&
          rearmed.isAccepted &&
          projection.cards.single.triggerKind ==
              TerminalNotesTriggerKind.onReturn &&
          projection.cards.single.triggerPhase ==
              TerminalNotesTriggerPhase.onReturnArmedHere,
      'standalone Always and Re-arm intents round-trip through the product',
    );

    final BigInt armedRevision = projection.storeRevision;
    for (final (bool foreground, bool occluded) in <(bool, bool)>[
      (true, false),
      (true, false),
    ]) {
      await enabled.updateSurface(
        paneId: const PaneId(1),
        configuration: _surfaceConfiguration(
          handle: 61,
          visibility: TerminalNoteSurfaceVisibility.collapsed,
          foreground: foreground,
          occluded: occluded,
        ),
      );
    }
    projection = enabledChannel.projections.last;
    _expect(
      projection.storeRevision == armedRevision &&
          projection.dueCount == 0 &&
          projection.visibility == TerminalNotesVisibility.expanded,
      'same-pane Note UI and duplicate presentation updates create no edge',
    );

    for (final (bool foreground, bool occluded) in <(bool, bool)>[
      (false, false),
      (false, true),
      (true, true),
    ]) {
      await enabled.updateSurface(
        paneId: const PaneId(1),
        configuration: _surfaceConfiguration(
          handle: 61,
          visibility: TerminalNoteSurfaceVisibility.collapsed,
          foreground: foreground,
          occluded: occluded,
        ),
      );
    }
    projection = await _waitForNativeProjection(
      enabledChannel,
      (TerminalNotesProjection candidate) =>
          candidate.cards.length == 1 &&
          candidate.cards.single.triggerPhase ==
              TerminalNotesTriggerPhase.onReturnArmedAway,
    );
    _expect(
      projection.storeRevision == armedRevision + BigInt.one &&
          projection.dueCount == 0,
      'app/window/tab/pane loss and occlusion variants collapse to one away edge',
    );

    await enabled.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 61,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    projection = await _waitForNativeProjection(
      enabledChannel,
      (TerminalNotesProjection candidate) =>
          candidate.dueCount == 1 &&
          candidate.visibility == TerminalNotesVisibility.expanded &&
          candidate.cards.first.due,
    );
    final TerminalNoteProductInteractionSnapshot automatic = enabled
        .interactionSnapshotForPane(const PaneId(1))!;
    _expect(
      projection.storeRevision == armedRevision + BigInt.from(2) &&
          automatic.automaticPresentation &&
          automatic.visibility == TerminalNoteSurfaceVisibility.expanded &&
          enabledChannel.focusTargets.isEmpty,
      'one eligible return commits due and presents one non-focusing rail',
    );
    final TerminalNoteProductTopologyResult duplicateLayout = await enabled
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 61,
            visibility: TerminalNoteSurfaceVisibility.collapsed,
            foreground: true,
            occluded: false,
          ),
        );
    projection = enabledChannel.projections.last;
    _expect(
      duplicateLayout.isAccepted &&
          projection.visibility == TerminalNotesVisibility.expanded &&
          enabled
              .interactionSnapshotForPane(const PaneId(1))!
              .automaticPresentation &&
          enabledChannel.focusTargets.isEmpty,
      'duplicate layout updates preserve the automatic rail and terminal focus',
    );

    enabledChannel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 5,
        kind: TerminalNotesIntentKind.close,
      ),
    );
    final TerminalNoteProductTopologyResult closed = await enabled
        .pumpSurfaceIntent(const PaneId(1));
    projection = enabledChannel.projections.last;
    await enabled.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 61,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    projection = enabledChannel.projections.last;
    _expect(
      closed.isAccepted &&
          projection.visibility == TerminalNotesVisibility.collapsed &&
          projection.dueCount == 1 &&
          !enabled
              .interactionSnapshotForPane(const PaneId(1))!
              .automaticPresentation,
      'manual close stays collapsed for duplicate updates in the same visit',
    );

    await enabled.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 61,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: false,
        occluded: true,
      ),
    );
    await enabled.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 61,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    projection = enabledChannel.projections.last;
    _expect(
      projection.visibility == TerminalNotesVisibility.expanded &&
          projection.cards.first.due &&
          enabled
              .interactionSnapshotForPane(const PaneId(1))!
              .automaticPresentation,
      'a later eligible visit re-presents the unacknowledged due once',
    );

    final TerminalNoteProductTopologyResult quickBound = await enabled.bindPane(
      paneId: const PaneId(90),
      kind: TerminalNoteContextKind.quickTerminal,
    );
    final TerminalNoteProductTopologyResult quickAttached = await enabled
        .attachSurface(
          paneId: const PaneId(90),
          configuration: _surfaceConfiguration(
            handle: 90,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    TerminalNotesProjection quickProjection = quickChannel.projections.last;
    quickChannel.intents.add(
      _nativeIntent(
        quickProjection,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.beginCreate,
      ),
    );
    await enabled.pumpSurfaceIntent(const PaneId(90));
    quickProjection = quickChannel.projections.last;
    quickChannel.intents.add(
      _nativeIntent(
        quickProjection,
        eventGeneration: 2,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.blue,
        body: 'quick terminal return note',
      ),
    );
    final TerminalNoteProductTopologyResult quickSaved = await enabled
        .pumpSurfaceIntent(const PaneId(90));
    await enabled.updateSurface(
      paneId: const PaneId(90),
      configuration: _surfaceConfiguration(
        handle: 90,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: false,
        occluded: true,
      ),
    );
    quickProjection = await _waitForNativeProjection(
      quickChannel,
      (TerminalNotesProjection candidate) =>
          candidate.cards.length == 1 &&
          candidate.cards.single.triggerPhase ==
              TerminalNotesTriggerPhase.onReturnArmedAway,
    );
    await enabled.updateSurface(
      paneId: const PaneId(90),
      configuration: _surfaceConfiguration(
        handle: 90,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    quickProjection = await _waitForNativeProjection(
      quickChannel,
      (TerminalNotesProjection candidate) =>
          candidate.dueCount == 1 &&
          candidate.visibility == TerminalNotesVisibility.expanded &&
          candidate.cards.first.due,
    );
    _expect(
      quickBound.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          quickAttached.isAccepted &&
          quickSaved.isAccepted &&
          quickProjection.cards.single.body == 'quick terminal return note' &&
          enabled
              .interactionSnapshotForPane(const PaneId(90))!
              .automaticPresentation &&
          quickChannel.focusTargets.isEmpty,
      'Quick Terminal hide and eligible return reuse its context and present without focus transfer',
    );

    final _FakeProductNativeChannel disabledChannel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final TerminalNoteSubsystemStartResult disabledStart =
        await TerminalNoteProductSubsystem.start(
          configuration: const TerminalNoteFeatureConfiguration(
            notes: true,
            notesOnReturn: false,
            notesNextPrompt: false,
            fontSize: 15,
          ),
          environment: <String, String>{
            'XDG_STATE_HOME': '${root.path}/disabled',
          },
          authorityGeneration: 302,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(2)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 6100,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => disabledChannel,
          clock: () => 6101,
        );
    disabled = disabledStart.runtime! as TerminalNoteProductSubsystem;
    await disabled.attachSurface(
      paneId: const PaneId(2),
      configuration: _surfaceConfiguration(
        handle: 62,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      ),
    );
    final TerminalNotesProjection disabledProjection =
        disabledChannel.projections.last;
    disabledChannel.intents.add(
      _nativeIntent(
        disabledProjection,
        eventGeneration: 1,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.yellow,
        body: 'must not enter authority',
      ),
    );
    final TerminalNoteProductTopologyResult rejected = await disabled
        .pumpSurfaceIntent(const PaneId(2));
    _expect(
      !disabledProjection.onReturnEnabled &&
          rejected.disposition ==
              TerminalNoteProductTopologyDisposition.rejected &&
          disabledChannel.projections.last.storeRevision ==
              disabledProjection.storeRevision &&
          disabledChannel.results.last.disposition ==
              TerminalNotesResultDisposition.rejected,
      'disabled On Return has no native entry and rejects injected intents',
    );
  } finally {
    if (enabled != null && !enabled.isStopped) await enabled.shutdown();
    if (disabled != null && !disabled.isStopped) await disabled.shutdown();
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Future<void> _testVisibleOnReturnAcknowledgement() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-visible-ack-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  TerminalNoteProductSubsystem? subsystem;
  try {
    final _FakeProductNativeChannel channel = _FakeProductNativeChannel(
      nextAttachment: TerminalNotesAttachDisposition.attached,
    );
    final List<String> copiedBodies = <String>[];
    final TerminalNoteSubsystemStartResult started =
        await TerminalNoteProductSubsystem.start(
          configuration: const TerminalNoteFeatureConfiguration(
            notes: true,
            notesOnReturn: true,
            notesNextPrompt: false,
            fontSize: 15,
          ),
          environment: <String, String>{'XDG_STATE_HOME': root.path},
          authorityGeneration: 303,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 6200,
          copyEffect: (String body) {
            copiedBodies.add(body);
            return true;
          },
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => channel,
          clock: () => 6201,
        );
    subsystem = started.runtime! as TerminalNoteProductSubsystem;
    var scheduledAcknowledgementRechecks = 0;
    subsystem.setSurfaceEventHandler((PaneId paneId) {
      if (paneId == const PaneId(1)) scheduledAcknowledgementRechecks++;
    });
    await subsystem.attachSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: false,
      ),
    );

    Future<void> createOnReturn(String body, int firstEvent) async {
      var projection = channel.projections.last;
      channel.intents.add(
        _nativeIntent(
          projection,
          eventGeneration: firstEvent,
          kind: TerminalNotesIntentKind.beginCreate,
        ),
      );
      await subsystem!.pumpSurfaceIntent(const PaneId(1));
      projection = channel.projections.last;
      channel.intents.add(
        _nativeIntent(
          projection,
          eventGeneration: firstEvent + 1,
          kind: TerminalNotesIntentKind.saveOnReturn,
          color: TerminalNotesColor.yellow,
          body: body,
        ),
      );
      await subsystem!.pumpSurfaceIntent(const PaneId(1));
    }

    await createOnReturn('first visible FIFO', 1);
    await createOnReturn('second visible FIFO', 3);
    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: false,
        occluded: true,
      ),
    );
    await _waitForNativeProjection(
      channel,
      (TerminalNotesProjection candidate) =>
          candidate.cards.length == 2 &&
          candidate.cards.every(
            (TerminalNotesCard card) =>
                card.triggerPhase ==
                TerminalNotesTriggerPhase.onReturnArmedAway,
          ),
    );
    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    var projection = await _waitForNativeProjection(
      channel,
      (TerminalNotesProjection candidate) =>
          candidate.presentationEligible &&
          candidate.visibility == TerminalNotesVisibility.expanded &&
          candidate.dueCount == 2 &&
          candidate.cards.length == 2 &&
          candidate.cards.first.due,
    );
    final List<String> fifoBodies = projection.cards
        .map((TerminalNotesCard card) => card.body)
        .toList(growable: false);
    _expect(
      fifoBodies.toSet().containsAll(<String>{
            'first visible FIFO',
            'second visible FIFO',
          }) &&
          fifoBodies.length == 2,
      'simultaneous product due exposes both notes in durable FIFO order',
    );

    final BigInt dueRevision = projection.storeRevision;
    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: false,
        occluded: false,
      ),
    );
    final TerminalNoteProductTopologyResult background = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    projection = channel.projections.last;
    _expect(
      background.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          !projection.presentationEligible &&
          projection.storeRevision == dueRevision &&
          projection.dueCount == 2,
      'background layout cannot consume a due delivery',
    );

    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    projection = await _waitForNativeProjection(
      channel,
      (TerminalNotesProjection candidate) =>
          candidate.presentationEligible &&
          candidate.dueCount == 2 &&
          candidate.cards.first.due,
    );

    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.expanded,
        foreground: true,
        occluded: true,
      ),
    );
    final TerminalNoteProductTopologyResult occluded = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    _expect(
      occluded.disposition == TerminalNoteProductTopologyDisposition.noChange &&
          channel.projections.last.storeRevision == dueRevision &&
          channel.projections.last.dueCount == 2,
      'occluded layout cannot consume a due delivery',
    );
    await subsystem.updateSurface(
      paneId: const PaneId(1),
      configuration: _surfaceConfiguration(
        handle: 63,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: true,
        occluded: false,
      ),
    );
    projection = await _waitForNativeProjection(
      channel,
      (TerminalNotesProjection candidate) =>
          candidate.presentationEligible &&
          candidate.dueCount == 2 &&
          candidate.cards.first.due,
    );

    channel.smallPane = true;
    final TerminalNoteProductTopologyResult small = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.smallPane = false;
    channel.presentationProjectionGeneration =
        projection.projectionGeneration - 1;
    final TerminalNoteProductTopologyResult stale = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.presentationProjectionGeneration = null;
    channel.firstCard = const TerminalNotesRect(
      x: 480,
      y: 74,
      width: 0,
      height: 88,
    );
    final TerminalNoteProductTopologyResult zeroGeometry = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.firstCard = const TerminalNotesRect(
      x: -1000,
      y: -1000,
      width: 284,
      height: 88,
    );
    final TerminalNoteProductTopologyResult outsideGeometry = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.firstCard = null;
    channel.railVisible = false;
    final TerminalNoteProductTopologyResult hiddenRail = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.railVisible = true;
    projection = channel.projections.last;
    _expect(
      small.disposition == TerminalNoteProductTopologyDisposition.noChange &&
          stale.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          zeroGeometry.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          outsideGeometry.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          hiddenRail.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          projection.storeRevision == dueRevision &&
          projection.dueCount == 2,
      'small, stale, invalid-geometry, and hidden-rail wakes consume nothing',
    );

    final int resultsBeforeCopy = channel.results.length;
    channel.intents.add(
      _nativeIntent(
        projection,
        eventGeneration: 5,
        kind: TerminalNotesIntentKind.copy,
        cardToken: projection.cards.first.token,
        body: projection.cards.first.body,
      ),
    );
    final TerminalNoteProductTopologyResult copied = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    projection = channel.projections.last;
    _expect(
      copied.isAccepted &&
          copiedBodies.single == fifoBodies.first &&
          channel.results.length == resultsBeforeCopy + 1 &&
          scheduledAcknowledgementRechecks == 1 &&
          projection.storeRevision == dueRevision &&
          projection.dueCount == 2,
      'pending user intent wins over an otherwise eligible visible ack',
    );

    final int firstAcknowledgedGeneration = projection.projectionGeneration;
    final int nativeResultsBeforeAck = channel.results.length;
    final TerminalNoteProductTopologyResult firstAcknowledged = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    projection = channel.projections.last;
    _expect(
      firstAcknowledged.disposition ==
              TerminalNoteProductTopologyDisposition.applied &&
          projection.storeRevision == dueRevision + BigInt.one &&
          projection.projectionGeneration > firstAcknowledgedGeneration &&
          projection.dueCount == 1 &&
          projection.cards.first.body == fifoBodies[1] &&
          projection.cards.first.due &&
          channel.results.length == nativeResultsBeforeAck,
      'one visible wake commits only one due and republishes the next FIFO head',
    );

    channel.presentationProjectionGeneration = firstAcknowledgedGeneration;
    channel.visibleAcknowledgementEligibleGeneration =
        firstAcknowledgedGeneration;
    final TerminalNoteProductTopologyResult duplicateOldWake = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    channel.presentationProjectionGeneration = null;
    channel.visibleAcknowledgementEligibleGeneration = null;
    projection = channel.projections.last;
    _expect(
      duplicateOldWake.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          projection.storeRevision == dueRevision + BigInt.one &&
          projection.dueCount == 1,
      'a duplicate wake for the old generation cannot consume the next due',
    );

    final TerminalNoteProductTopologyResult secondAcknowledged = await subsystem
        .pumpSurfaceIntent(const PaneId(1));
    projection = channel.projections.last;
    _expect(
      secondAcknowledged.disposition ==
              TerminalNoteProductTopologyDisposition.applied &&
          projection.storeRevision == dueRevision + BigInt.from(2) &&
          projection.dueCount == 0,
      'the next projection wake commits the second due separately',
    );
  } finally {
    if (subsystem != null && !subsystem.isStopped) await subsystem.shutdown();
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
        exportDestinationChooser: (_) => null,
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
        exportDestinationChooser: (_) => null,
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
  bool smallPane = false;
  bool railVisible = true;
  int? snapshotProjectionGeneration;
  int? presentationProjectionGeneration;
  int? visibleAcknowledgementEligibleGeneration;
  TerminalNotesRect? firstCard;
  void Function()? notificationHandler;
  final List<TerminalNotesNativeFocusTarget> focusTargets =
      <TerminalNotesNativeFocusTarget>[];

  @override
  TerminalNotesNativeSnapshot get snapshot {
    final TerminalNotesProjection projection = projections.last;
    return TerminalNotesNativeSnapshot(
      paneId: projection.paneId,
      surfaceGeneration: projection.surfaceGeneration,
      projectionGeneration:
          snapshotProjectionGeneration ?? projection.projectionGeneration,
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
      onReturnEnabled: projection.onReturnEnabled,
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
    final bool visibleRail = expanded && railVisible && !smallPane;
    final bool visibleDue =
        visibleRail &&
        projection.presentationEligible &&
        projection.editorMode == TerminalNotesEditorMode.inactive &&
        projection.dueCount > 0 &&
        projection.cards.isNotEmpty &&
        projection.cards.first.due;
    return TerminalNotesNativePresentation(
      projectionGeneration:
          presentationProjectionGeneration ?? projection.projectionGeneration,
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
      firstCard:
          firstCard ??
          const TerminalNotesRect(x: 480, y: 74, width: 284, height: 88),
      flags: (visibleRail ? 2 : 1) | (smallPane ? 4 : 0),
      materializedCardCount: projection.cards.length,
      accessibilityNodeCount: 1,
      accessibilityBodyCount: projection.cards.length,
      visibleAcknowledgementEligibleGeneration:
          visibleAcknowledgementEligibleGeneration ??
          (visibleDue ? projection.projectionGeneration : 0),
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

Future<TerminalNotesProjection> _waitForNativeProjection(
  _FakeProductNativeChannel channel,
  bool Function(TerminalNotesProjection projection) predicate,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (channel.projections.isNotEmpty) {
      final TerminalNotesProjection projection = channel.projections.last;
      if (predicate(projection)) return projection;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('timed out waiting for native Note projection');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
