import 'dart:async';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalNoteApplicationCoordinatorTests();

Future<void> runTerminalNoteApplicationCoordinatorTests() async {
  await _testDisabledCompositionOwnsNoRuntime();
  await _testAutomaticRailPreservesTerminalOwner();
  await _testTopologySurfaceInteractionAndShutdown();
}

Future<void> _testDisabledCompositionOwnsNoRuntime() async {
  var factoryCalls = 0;
  final TerminalNoteApplicationCoordinator coordinator =
      await TerminalNoteApplicationCoordinator.start(
        launchConfiguration: const TerminalNoteFeatureConfiguration(
          notes: false,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        initialBindings: const <TerminalNoteApplicationPaneBinding>[],
        factory: (_) {
          factoryCalls++;
          throw StateError('disabled composition invoked its factory');
        },
      );
  await coordinator.synchronizeTopology(
    const <TerminalNoteApplicationPaneBinding>[],
  );
  _expect(
    coordinator.capability == TerminalNoteApplicationCapability.disabled &&
        !coordinator.ownsRuntime &&
        coordinator.liveBindingCount == 0 &&
        coordinator.liveSurfaceCount == 0 &&
        factoryCalls == 0,
    'disabled composition allocates no Note runtime, binding, or surface',
  );
  await coordinator.shutdown();
}

Future<void> _testAutomaticRailPreservesTerminalOwner() async {
  final int interactionBaseline =
      TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount;
  final List<_CoordinatorFakeSession> sessions = <_CoordinatorFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState window = await state.createWindow(
    _configuration(sessions),
  );
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final _FakeNoteTopologyRuntime runtime = _FakeNoteTopologyRuntime(<PaneId>{
    paneId,
  });
  final TerminalNoteApplicationCoordinator coordinator =
      await TerminalNoteApplicationCoordinator.start(
        launchConfiguration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: true,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        initialBindings: <TerminalNoteApplicationPaneBinding>[
          TerminalNoteApplicationPaneBinding(
            paneId: paneId,
            windowId: window.id,
          ),
        ],
        factory: (_) => TerminalNoteSubsystemStartResult.available(runtime),
      );
  final TerminalWindowInteractionAuthority authority =
      TerminalWindowInteractionAuthority(state);
  final TerminalWindowInteractionRouter router =
      TerminalWindowInteractionRouter(authority);
  var terminalFocusRequests = 0;
  final TerminalNoteProductTopologyResult attached = await coordinator
      .synchronizeSurface(
        paneId: paneId,
        windowId: window.id,
        configuration: _surfaceConfiguration(31),
        interactionAuthority: authority,
        interactionRouter: router,
        focusTerminal: () {
          terminalFocusRequests++;
          return true;
        },
      );
  final int generation = runtime.surfaces[paneId]!;
  runtime.notify(
    paneId,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      automaticPresentation: true,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  await coordinator.synchronizeSurface(
    paneId: paneId,
    windowId: window.id,
    configuration: _surfaceConfiguration(32),
    interactionAuthority: authority,
    interactionRouter: router,
    focusTerminal: () {
      terminalFocusRequests++;
      return true;
    },
  );
  _expect(
    attached.isAccepted &&
        coordinator.notesVisibleForPane(paneId) &&
        runtime.pumpCount == 1 &&
        runtime.focusRequests.isEmpty &&
        terminalFocusRequests == 0 &&
        authority.snapshotForWindow(window.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal,
    'automatic due rail and renderer refresh preserve terminal input owner',
  );

  final bool down = coordinator.handlePointerEvent(
    paneId: paneId,
    phase: TerminalNoteApplicationPointerPhase.down,
    x: 750,
    y: 250,
  );
  final bool up = coordinator.handlePointerEvent(
    paneId: paneId,
    phase: TerminalNoteApplicationPointerPhase.up,
    x: 750,
    y: 250,
  );
  _expect(
    down &&
        up &&
        runtime.focusRequests.single ==
            (paneId, TerminalNoteProductFocusTarget.rail) &&
        authority.snapshotForWindow(window.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.noteRail &&
        terminalFocusRequests == 0,
    'explicit pointer interaction transfers the automatic rail normally',
  );

  runtime.notify(
    paneId,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.creating,
      draftGeneration: 1,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  runtime.notify(
    paneId,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      automaticPresentation: true,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  _expect(
    runtime.focusRequests.length == 3 &&
        runtime.focusRequests[1] ==
            (paneId, TerminalNoteProductFocusTarget.editor) &&
        runtime.focusRequests.last ==
            (paneId, TerminalNoteProductFocusTarget.rail) &&
        authority.snapshotForWindow(window.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.noteRail &&
        terminalFocusRequests == 0,
    'automatic projection resolves an already-owned editor to its rail without touching terminal focus',
  );

  await coordinator.shutdown();
  router.dispose();
  authority.dispose();
  await state.shutdown();
  _expect(
    TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount ==
        interactionBaseline,
    'automatic rail fixture releases its interaction ownership',
  );
}

Future<void> _testTopologySurfaceInteractionAndShutdown() async {
  final int interactionBaseline =
      TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount;
  final List<_CoordinatorFakeSession> sessions = <_CoordinatorFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState standard = await state.createWindow(
    _configuration(sessions),
  );
  final PaneId standardPane = standard.selectedTab.focusedPaneId;
  final _FakeNoteTopologyRuntime runtime = _FakeNoteTopologyRuntime(<PaneId>{
    standardPane,
  });
  var clock = 1000;
  final TerminalNoteApplicationCoordinator coordinator =
      await TerminalNoteApplicationCoordinator.start(
        launchConfiguration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        initialBindings: <TerminalNoteApplicationPaneBinding>[
          TerminalNoteApplicationPaneBinding(
            paneId: standardPane,
            windowId: standard.id,
          ),
        ],
        factory: (_) => TerminalNoteSubsystemStartResult.available(runtime),
        clock: () => clock++,
      );
  final TerminalWindowInteractionAuthority authority =
      TerminalWindowInteractionAuthority(state);
  final TerminalWindowInteractionRouter router =
      TerminalWindowInteractionRouter(authority);
  var standardFocusCount = 0;
  final TerminalNoteProductTopologyResult attached = await coordinator
      .synchronizeSurface(
        paneId: standardPane,
        windowId: standard.id,
        configuration: _surfaceConfiguration(11),
        interactionAuthority: authority,
        interactionRouter: router,
        focusTerminal: () {
          standardFocusCount++;
          return true;
        },
      );
  _expect(
    attached.isAccepted &&
        coordinator.liveSurfaceCount == 1 &&
        coordinator.liveInteractionAdapterCount == 1 &&
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount ==
            interactionBaseline + 1,
    'attached surface joins the sole window interaction authority',
  );
  _expect(
    coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.down,
          x: 750,
          y: 250,
        ) &&
        coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.drag,
          x: 100,
          y: 100,
        ) &&
        coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.up,
          x: 100,
          y: 100,
        ) &&
        router.activeConsumedGestureCount == 0 &&
        authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.noteRail &&
        runtime.focusRequests.last ==
            (standardPane, TerminalNoteProductFocusTarget.rail),
    'collapsed badge owns its complete pointer sequence without terminal replay',
  );
  final int pumpsBeforeCreate = runtime.pumpCount;
  final int generation = runtime.surfaces[standardPane]!;
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.creating,
      draftGeneration: 1,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  runtime.surfaceEventHandler?.call(standardPane);
  await _drainSurfaceEvents();
  _expect(
    runtime.pumpCount == pumpsBeforeCreate + 1 &&
        runtime.focusRequests.last ==
            (standardPane, TerminalNoteProductFocusTarget.editor) &&
        authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.noteEditor,
    'coalesced native wake-up pumps once then transfers focus to the editor',
  );
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.creating,
      draftGeneration: 1,
      editorDirty: true,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  final TerminalPaneCloseCoordinator close = TerminalPaneCloseCoordinator(
    state: state,
    canRemovePane: (PaneId paneId) =>
        authority.permitsHierarchyMutation(standard.id),
    canRemoveWindow: authority.permitsHierarchyMutation,
    canBeginApplicationQuit: () =>
        authority.permitsHierarchyMutation(standard.id),
  );
  _expect(
    (await close.requestClose(paneId: standardPane)).disposition ==
            TerminalPaneCloseDisposition.busy &&
        (await close.requestWindowClose(standard.id)).disposition ==
            TerminalWindowCloseDisposition.busy &&
        !close.beginApplicationQuit() &&
        state.paneCount == 1,
    'dirty Note ownership blocks pane, window, and application destruction',
  );
  _expect(
    coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.down,
          x: 100,
          y: 100,
        ) &&
        runtime.discardConfirmationCount == 1 &&
        standardFocusCount == 0 &&
        authority.snapshotForWindow(standard.id)?.noteEditorPhase ==
            TerminalWindowNoteEditorPhase.confirmDiscard,
    'outside dirty click opens native confirmation and is never replayed',
  );
  await _drainSurfaceEvents();
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.creating,
      draftGeneration: 1,
      editorDirty: true,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  _expect(
    authority.snapshotForWindow(standard.id)?.noteEditorPhase ==
        TerminalWindowNoteEditorPhase.dirty,
    'Keep Editing restores the dirty editor phase',
  );
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  _expect(
    authority.snapshotForWindow(standard.id)?.owner.kind ==
        TerminalWindowInteractionOwnerKind.noteRail,
    'resolved editor returns focus ownership to the expanded rail',
  );
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.collapsed,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  _expect(
    authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal &&
        standardFocusCount == 1 &&
        !coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.down,
          x: 100,
          y: 100,
        ) &&
        !coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.drag,
          x: 750,
          y: 250,
        ) &&
        !coordinator.handlePointerEvent(
          paneId: standardPane,
          phase: TerminalNoteApplicationPointerPhase.up,
          x: 750,
          y: 250,
        ),
    'collapsed surface returns the input owner and preserves terminal-started pointer sequences',
  );

  final TerminalWindowState quick = await state.createWindow(
    _configuration(sessions),
    role: TerminalWindowRole.quickTerminal,
  );
  final PaneId quickPane = quick.selectedTab.focusedPaneId;
  await coordinator.synchronizeTopology(<TerminalNoteApplicationPaneBinding>[
    TerminalNoteApplicationPaneBinding(
      paneId: standardPane,
      windowId: standard.id,
    ),
    TerminalNoteApplicationPaneBinding(
      paneId: quickPane,
      windowId: quick.id,
      kind: TerminalNoteContextKind.quickTerminal,
    ),
  ]);
  await coordinator.synchronizeSurface(
    paneId: quickPane,
    windowId: quick.id,
    configuration: _surfaceConfiguration(21),
    interactionAuthority: authority,
    interactionRouter: router,
    focusTerminal: () => true,
  );
  _expect(
    runtime.bindings[quickPane] == TerminalNoteContextKind.quickTerminal &&
        coordinator.liveBindingCount == 2 &&
        coordinator.liveSurfaceCount == 2,
    'Quick Terminal receives the singleton kind and one lazy surface',
  );

  final TerminalNoteLiveConfigurationDisposition live = coordinator
      .applyLiveConfiguration(
        const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 24,
        ),
      );
  _expect(
    live == TerminalNoteLiveConfigurationDisposition.applied &&
        runtime.configurations.single.fontSize == 24,
    'live Note font reaches only the admitted runtime',
  );

  _expect(
    coordinator.preparePaneForViewTeardown(standardPane) &&
        standardFocusCount == 1 &&
        authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal &&
        runtime.prepared.contains(standardPane),
    'interaction ownership and native host detach precede view teardown',
  );
  final TerminalNoteProductTopologyResult reattached = await coordinator
      .synchronizeSurface(
        paneId: standardPane,
        windowId: standard.id,
        configuration: _surfaceConfiguration(12),
        interactionAuthority: authority,
        interactionRouter: router,
        focusTerminal: () => true,
      );
  _expect(
    reattached.isAccepted &&
        coordinator.interactionForPane(standardPane) != null &&
        !coordinator.interactionForPane(standardPane)!.isDisposed &&
        coordinator.liveInteractionAdapterCount == 2,
    'renderer host replacement recreates the released interaction adapter',
  );
  _expect(
    coordinator.canPerformAction(
          standardPane,
          TerminalNoteApplicationActionKind.toggleNotes,
        ) &&
        coordinator.canPerformAction(
          standardPane,
          TerminalNoteApplicationActionKind.newNote,
        ) &&
        !coordinator.canPerformAction(
          standardPane,
          TerminalNoteApplicationActionKind.focusTerminal,
        ),
    'collapsed idle surface exposes only create and visibility actions',
  );
  final TerminalNoteProductTopologyResult actionOpened = await coordinator
      .performAction(
        standardPane,
        TerminalNoteApplicationActionKind.toggleNotes,
      );
  final TerminalNoteProductTopologyResult actionCreated = await coordinator
      .performAction(standardPane, TerminalNoteApplicationActionKind.newNote);
  _expect(
    actionOpened.isAccepted &&
        actionCreated.isAccepted &&
        runtime.actionRequests.join(',') ==
            '${TerminalNoteProductActionKind.toggleNotes},${TerminalNoteProductActionKind.newNote}' &&
        authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.noteEditor &&
        !coordinator.canPerformAction(
          standardPane,
          TerminalNoteApplicationActionKind.toggleNotes,
        ) &&
        !coordinator.canPerformAction(
          standardPane,
          TerminalNoteApplicationActionKind.focusTerminal,
        ),
    'application action routing opens the rail then transfers the new draft to the editor',
  );
  runtime.notify(
    standardPane,
    TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: runtime.surfaces[standardPane]!,
      visibility: TerminalNoteSurfaceVisibility.expanded,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    ),
  );
  await _drainSurfaceEvents();
  final TerminalNoteProductTopologyResult actionFocused = await coordinator
      .performAction(
        standardPane,
        TerminalNoteApplicationActionKind.focusTerminal,
      );
  _expect(
    actionFocused.isAccepted &&
        authority.snapshotForWindow(standard.id)?.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal,
    'Focus Terminal transfers ownership without hiding the expanded Notes rail',
  );
  await state.removeWindow(quick.id);
  await coordinator.synchronizeTopology(<TerminalNoteApplicationPaneBinding>[
    TerminalNoteApplicationPaneBinding(
      paneId: standardPane,
      windowId: standard.id,
    ),
  ]);
  _expect(
    !runtime.bindings.containsKey(quickPane) &&
        runtime.closed[quickPane] == 1000 &&
        coordinator.liveBindingCount == 1 &&
        coordinator.liveSurfaceCount == 1,
    'removed Quick Terminal retires its surface before its durable binding',
  );

  final TerminalNoteRestorationArtifact restoration =
      TerminalNoteRestorationArtifact.fromSnapshot(_onePaneRestoration());
  final TerminalNoteRestorationCaptureArtifact capture =
      TerminalNoteRestorationCaptureArtifact.fromArtifact(
        restoration: restoration,
        paneIdsInTraversalOrder: <PaneId>[standardPane],
      );
  final List<String> committedRestoration = <String>[];
  final Future<TerminalNoteApplicationShutdownResult> first = coordinator
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 1001,
        commitRestoration: (TerminalNoteRestorationArtifact artifact) async {
          committedRestoration.add(artifact.exactEncoded);
          return true;
        },
      );
  final Future<TerminalNoteApplicationShutdownResult> second = coordinator
      .shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: 1002,
        commitRestoration: (_) async => false,
      );
  _expect(
    identical(first, second),
    'ordered application Note shutdown is single-flight',
  );
  final TerminalNoteApplicationShutdownResult shutdown = await first;
  _expect(
    shutdown.isSuccess &&
        shutdown.compositionDisposition ==
            TerminalNoteCompositionShutdownDisposition.stopped &&
        shutdown.authorityResult?.isSuccess == true &&
        committedRestoration.single == restoration.exactEncoded &&
        runtime.applicationShutdownCount == 1 &&
        runtime.isStopped &&
        coordinator.liveBindingCount == 0 &&
        coordinator.liveSurfaceCount == 0 &&
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount ==
            interactionBaseline,
    'ordered shutdown commits exact restoration once and releases every owner',
  );
  router.dispose();
  authority.dispose();
  await state.shutdown();
}

TerminalNoteProductSurfaceConfiguration _surfaceConfiguration(int identity) =>
    TerminalNoteProductSurfaceConfiguration(
      rendererIdentity: TerminalMetalRendererCompositionIdentity(
        handle: identity,
        generation: identity,
      ),
      paneWidth: 800,
      paneHeight: 500,
      backingScale: 2,
      requestedRailWidth: 320,
      visibility: TerminalNoteSurfaceVisibility.collapsed,
      foreground: true,
      occluded: false,
    );

Future<void> _drainSurfaceEvents() async {
  for (var turn = 0; turn < 6; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeNoteTopologyRuntime
    implements TerminalNoteProductTopologyPort {
  _FakeNoteTopologyRuntime(Set<PaneId> initialPanes) {
    for (final PaneId paneId in initialPanes) {
      bindings[paneId] = TerminalNoteContextKind.standard;
    }
  }

  final Map<PaneId, TerminalNoteContextKind> bindings =
      <PaneId, TerminalNoteContextKind>{};
  final Map<PaneId, int> surfaces = <PaneId, int>{};
  final Map<PaneId, int> closed = <PaneId, int>{};
  final Set<PaneId> prepared = <PaneId>{};
  final Map<PaneId, TerminalNoteProductInteractionSnapshot> interactions =
      <PaneId, TerminalNoteProductInteractionSnapshot>{};
  final List<(PaneId, TerminalNoteProductFocusTarget)> focusRequests =
      <(PaneId, TerminalNoteProductFocusTarget)>[];
  final List<TerminalNoteProductActionKind> actionRequests =
      <TerminalNoteProductActionKind>[];
  final List<TerminalNoteFeatureConfiguration> configurations =
      <TerminalNoteFeatureConfiguration>[];
  TerminalNoteProductSurfaceEventHandler? surfaceEventHandler;
  int pumpCount = 0;
  int discardConfirmationCount = 0;
  int applicationShutdownCount = 0;
  var _nextSurfaceGeneration = 10;
  var _stopped = false;

  @override
  bool get isStopped => _stopped;
  @override
  int get livePaneCount => bindings.length;
  @override
  int get liveSurfaceCount => surfaces.length;
  @override
  int get nativeSurfaceCount => surfaces.length;
  @override
  bool hasPane(PaneId paneId) => bindings.containsKey(paneId);
  @override
  int? surfaceGenerationForPane(PaneId paneId) => surfaces[paneId];

  @override
  void applyLiveConfiguration(TerminalNoteFeatureConfiguration configuration) {
    configurations.add(configuration);
  }

  @override
  void updatePresentation(TerminalNoteNativePresentationState presentation) {}

  @override
  Future<TerminalNoteProductTopologyResult> bindPane({
    required PaneId paneId,
    TerminalNoteContextKind kind = TerminalNoteContextKind.standard,
  }) async {
    bindings[paneId] = kind;
    return const TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
    );
  }

  @override
  Future<TerminalNoteProductTopologyResult> closePane({
    required PaneId paneId,
    required int updatedAtUtcMicros,
  }) async {
    bindings.remove(paneId);
    surfaces.remove(paneId);
    interactions.remove(paneId);
    closed[paneId] = updatedAtUtcMicros;
    return const TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
    );
  }

  @override
  Future<TerminalNoteProductTopologyResult> attachSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  }) async {
    final int generation = _nextSurfaceGeneration++;
    surfaces[paneId] = generation;
    interactions[paneId] = TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: generation,
      visibility: TerminalNoteSurfaceVisibility.collapsed,
      editorMode: TerminalNoteEditorMode.inactive,
      draftGeneration: 0,
      editorDirty: false,
      confirmingDiscard: false,
    );
    return TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
      surfaceGeneration: generation,
    );
  }

  @override
  Future<TerminalNoteProductTopologyResult> updateSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  }) async => TerminalNoteProductTopologyResult(
    TerminalNoteProductTopologyDisposition.applied,
    surfaceGeneration: surfaces[paneId],
  );

  @override
  Future<TerminalNoteProductTopologyResult> detachSurface(PaneId paneId) async {
    surfaces.remove(paneId);
    interactions.remove(paneId);
    return const TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
    );
  }

  @override
  Future<TerminalNoteProductTopologyResult> pumpSurfaceIntent(
    PaneId paneId,
  ) async {
    pumpCount++;
    return TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.noChange,
      surfaceGeneration: surfaces[paneId],
    );
  }

  @override
  bool canPerformAction(PaneId paneId, TerminalNoteProductActionKind action) {
    final TerminalNoteProductInteractionSnapshot? current =
        interactions[paneId];
    return current != null &&
        current.editorMode == TerminalNoteEditorMode.inactive &&
        current.draftGeneration == 0;
  }

  @override
  Future<TerminalNoteProductTopologyResult> performAction(
    PaneId paneId,
    TerminalNoteProductActionKind action,
  ) async {
    if (!canPerformAction(paneId, action)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.unavailable,
      );
    }
    actionRequests.add(action);
    final TerminalNoteProductInteractionSnapshot current =
        interactions[paneId]!;
    interactions[paneId] = TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: current.surfaceGeneration,
      visibility: action == TerminalNoteProductActionKind.toggleNotes
          ? current.visibility == TerminalNoteSurfaceVisibility.collapsed
                ? TerminalNoteSurfaceVisibility.expanded
                : TerminalNoteSurfaceVisibility.collapsed
          : TerminalNoteSurfaceVisibility.expanded,
      editorMode: action == TerminalNoteProductActionKind.newNote
          ? TerminalNoteEditorMode.creating
          : TerminalNoteEditorMode.inactive,
      draftGeneration: action == TerminalNoteProductActionKind.newNote ? 1 : 0,
      editorDirty: false,
      confirmingDiscard: false,
    );
    return TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
      surfaceGeneration: current.surfaceGeneration,
    );
  }

  @override
  void setSurfaceEventHandler(TerminalNoteProductSurfaceEventHandler? handler) {
    surfaceEventHandler = handler;
  }

  @override
  TerminalNoteProductInteractionSnapshot? interactionSnapshotForPane(
    PaneId paneId,
  ) => interactions[paneId];

  @override
  bool focusSurface(PaneId paneId, TerminalNoteProductFocusTarget target) {
    if (!surfaces.containsKey(paneId)) return false;
    focusRequests.add((paneId, target));
    return true;
  }

  @override
  bool presentDiscardConfirmation(PaneId paneId) {
    if (!surfaces.containsKey(paneId)) return false;
    discardConfirmationCount++;
    final TerminalNoteProductInteractionSnapshot current =
        interactions[paneId]!;
    interactions[paneId] = TerminalNoteProductInteractionSnapshot(
      surfaceGeneration: current.surfaceGeneration,
      visibility: current.visibility,
      editorMode: current.editorMode,
      draftGeneration: current.draftGeneration,
      editorDirty: current.editorDirty,
      confirmingDiscard: true,
    );
    surfaceEventHandler?.call(paneId);
    return true;
  }

  @override
  bool surfaceContainsPoint(
    PaneId paneId, {
    required double x,
    required double y,
  }) => surfaces.containsKey(paneId) && x >= 700 && y >= 200 && y < 300;

  void notify(PaneId paneId, TerminalNoteProductInteractionSnapshot snapshot) {
    interactions[paneId] = snapshot;
    surfaceEventHandler?.call(paneId);
  }

  @override
  bool prepareSurfaceForHostTeardown(PaneId paneId) {
    prepared.add(paneId);
    return true;
  }

  @override
  Future<TerminalNoteAuthorityShutdownResult> shutdownApplication({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    Duration drainTimeout = const Duration(seconds: 3),
  }) async {
    applicationShutdownCount++;
    final bool committed = await commitRestoration(capture.restoration);
    await shutdown();
    return TerminalNoteAuthorityShutdownResult(
      disposition: committed
          ? TerminalNoteAuthorityShutdownDisposition.committed
          : TerminalNoteAuthorityShutdownDisposition.persistenceFailed,
      persistence: null,
      storeDisposition: TerminalNoteStoreDisposition.stopped,
      surfaceDisposeCount: surfaces.length,
    );
  }

  @override
  Future<void> shutdown() async {
    _stopped = true;
    bindings.clear();
    surfaces.clear();
    interactions.clear();
    surfaceEventHandler = null;
  }
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

TerminalPaneConfiguration _configuration(
  List<_CoordinatorFakeSession> sessions,
) => TerminalPaneConfiguration(
  sessionFactory:
      (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) {
        final _CoordinatorFakeSession session = _CoordinatorFakeSession(id);
        sessions.add(session);
        return session;
      },
  onChanged: () {},
  onExitRequested: () {},
);

final class _CoordinatorFakeSession implements TerminalPaneSession {
  _CoordinatorFakeSession(this.id);

  @override
  final TerminalSessionId id;
  var _live = false;

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() =>
      TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => _live = true;
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
    _live = false;
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
