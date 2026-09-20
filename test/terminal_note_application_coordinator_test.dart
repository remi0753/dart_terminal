import 'dart:async';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalNoteApplicationCoordinatorTests();

Future<void> runTerminalNoteApplicationCoordinatorTests() async {
  await _testDisabledCompositionOwnsNoRuntime();
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
  final TerminalWindowNoteInteractionAdapter standardInteraction = coordinator
      .interactionForPane(standardPane)!;
  final TerminalWindowInteractionTransferResult noteFocus = standardInteraction
      .requestRailFocus();
  _expect(
    attached.isAccepted &&
        coordinator.liveSurfaceCount == 1 &&
        coordinator.liveInteractionAdapterCount == 1 &&
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount ==
            interactionBaseline + 1 &&
        standardInteraction
                .confirmNativeFocus(noteFocus.request!)
                .disposition ==
            TerminalWindowInteractionTransferDisposition.confirmed,
    'attached surface joins the sole window interaction authority',
  );
  final TerminalWindowInteractionTransferResult editorFocus =
      standardInteraction.requestEditorFocus(draftGeneration: 1);
  _expect(
    standardInteraction.confirmNativeFocus(editorFocus.request!).disposition ==
            TerminalWindowInteractionTransferDisposition.confirmed &&
        standardInteraction.synchronizeEditorPhase(
          dirty: true,
          confirmingDiscard: false,
        ),
    'dirty Note editor becomes the window input owner',
  );
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
    standardInteraction.synchronizeEditorPhase(
      dirty: false,
      confirmingDiscard: false,
    ),
    'clean Note editor releases destructive-operation admission',
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

  final Future<TerminalNoteCompositionShutdownDisposition> first = coordinator
      .shutdown();
  final Future<TerminalNoteCompositionShutdownDisposition> second = coordinator
      .shutdown();
  _expect(
    identical(first, second),
    'application Note shutdown is single-flight',
  );
  _expect(
    await first == TerminalNoteCompositionShutdownDisposition.stopped &&
        runtime.isStopped &&
        coordinator.liveBindingCount == 0 &&
        coordinator.liveSurfaceCount == 0 &&
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount ==
            interactionBaseline,
    'shutdown releases interaction, surfaces, topology, and runtime owners',
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
  final List<TerminalNoteFeatureConfiguration> configurations =
      <TerminalNoteFeatureConfiguration>[];
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
    return const TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
    );
  }

  @override
  Future<TerminalNoteProductTopologyResult> pumpSurfaceIntent(
    PaneId paneId,
  ) async => TerminalNoteProductTopologyResult(
    TerminalNoteProductTopologyDisposition.noChange,
    surfaceGeneration: surfaces[paneId],
  );

  @override
  bool prepareSurfaceForHostTeardown(PaneId paneId) {
    prepared.add(paneId);
    return true;
  }

  @override
  Future<void> shutdown() async {
    _stopped = true;
    bindings.clear();
    surfaces.clear();
  }
}

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
