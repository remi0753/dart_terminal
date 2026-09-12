import 'dart:async';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalApplicationStateTests();

Future<void> runTerminalApplicationStateTests() async {
  _testTypedIdentityValues();
  _testSplitTraversalAndLookup();
  _testSplitPlacementAndCollapse();
  _testSplitTopologyValidationAndBounds();
  _testSplitResizeEqualizeTraversalAndLayout();
  await _testApplicationHierarchyFocusAndIndexes();
  await _testQuickTerminalWindowRole();
  await _testTabPresentationAndCwdPolicy();
  await _testApplicationLayoutMutations();
  await _testPaneRemovalAndOrderedShutdown();
  await _testPaneCloseCoordinator();
  await _testApplicationQuitCoordinator();
  await _testApplicationTotalPaneAdmission();
  await _testApplicationLimitsAndDisposedState();
}

Future<void> _testQuickTerminalWindowRole() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState standard = await state.createWindow(configuration);
  final TerminalWindowState quick = await state.createWindow(
    configuration,
    role: TerminalWindowRole.quickTerminal,
  );
  final int admittedSessions = sessions.length;
  _expect(
    standard.role == TerminalWindowRole.standard &&
        quick.role == TerminalWindowRole.quickTerminal &&
        identical(state.quickTerminalWindow, quick) &&
        state.windowCount == 2,
    'the hierarchy exposes one explicit singleton Quick Terminal role',
  );
  await _expectFutureThrows<StateError>(
    () => state.createWindow(
      configuration,
      role: TerminalWindowRole.quickTerminal,
    ),
    'a second Quick Terminal must be rejected before pane allocation',
  );
  await _expectFutureThrows<StateError>(
    () => state.createTab(quick.id, configuration),
    'Quick Terminal tabs must be rejected on macOS before pane allocation',
  );
  _expect(
    sessions.length == admittedSessions && state.windowCount == 2,
    'rejected Quick Terminal mutations consume no pane or window identity',
  );
  final TerminalPaneRemovalResult removal = await state.removePane(
    quick.selectedTab.focusedPaneId,
  );
  _expect(
    removal.removedWindow &&
        state.quickTerminalWindow == null &&
        state.windowCount == 1 &&
        identical(state.activeWindow, standard),
    'tearing down the Quick Terminal releases its singleton role exactly',
  );
  final TerminalPaneOwnerShutdownResult shutdown = await state.shutdown();
  _expect(
    shutdown.isClean &&
        sessions.every(
          (_StateFakeSession session) => session.shutdownCount == 1,
        ),
    'Quick Terminal role fixture releases every admitted pane exactly once',
  );
}

Future<void> _testApplicationTotalPaneAdmission() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalApplicationState state = TerminalApplicationState();
  final List<TerminalWindowState> windows = <TerminalWindowState>[];
  for (
    var index = 0;
    index < TerminalApplicationStateLimits.maximumWindows - 1;
    index++
  ) {
    windows.add(await state.createWindow(configuration));
  }
  final TerminalWindowState firstWindow = windows.first;
  while (state.paneCount < TerminalApplicationStateLimits.maximumTotalPanes) {
    await state.createTab(firstWindow.id, configuration);
  }
  final int allocationCountAtLimit = sessions.length;
  final int maximumPaneIdentity = state.paneIds.last.value;
  final PaneId splitTarget = windows.last.selectedTab.focusedPaneId;
  _expect(
    state.windowCount == TerminalApplicationStateLimits.maximumWindows - 1 &&
        state.tabCount == TerminalApplicationStateLimits.maximumTotalPanes &&
        state.paneCount == TerminalApplicationStateLimits.maximumTotalPanes &&
        allocationCountAtLimit ==
            TerminalApplicationStateLimits.maximumTotalPanes,
    'live application reaches the aggregate pane budget exactly',
  );

  await _expectFutureThrows<StateError>(
    () => state.createWindow(configuration),
    'aggregate pane budget refuses a new window before allocation',
  );
  await _expectFutureThrows<StateError>(
    () => state.createTab(firstWindow.id, configuration),
    'aggregate pane budget refuses a new tab before allocation',
  );
  await _expectFutureThrows<StateError>(
    () => state.splitPane(
      splitTarget,
      configuration,
      axis: TerminalSplitAxis.horizontal,
    ),
    'aggregate pane budget refuses a split before allocation',
  );
  _expect(
    sessions.length == allocationCountAtLimit &&
        state.windowCount ==
            TerminalApplicationStateLimits.maximumWindows - 1 &&
        state.tabCount == TerminalApplicationStateLimits.maximumTotalPanes &&
        state.paneCount == TerminalApplicationStateLimits.maximumTotalPanes,
    'over-budget live mutations consume no session or hierarchy resource',
  );

  final TerminalTabState removableTab = firstWindow.selectedTab;
  final PaneId removablePane = removableTab.focusedPaneId;
  final TerminalPaneRemovalResult removal = await state.removePane(
    removablePane,
  );
  final TerminalTabState replacement = await state.createTab(
    firstWindow.id,
    configuration,
  );
  _expect(
    removal.removedTab &&
        !removal.removedWindow &&
        replacement.focusedPaneId.value == maximumPaneIdentity + 1 &&
        sessions.length == allocationCountAtLimit + 1 &&
        state.paneCount == TerminalApplicationStateLimits.maximumTotalPanes,
    'released aggregate capacity is reusable without failed identity gaps',
  );
  final TerminalPaneOwnerShutdownResult shutdown = await state.shutdown();
  _expect(
    shutdown.sessions.length ==
            TerminalApplicationStateLimits.maximumTotalPanes &&
        shutdown.isClean &&
        sessions.every(
          (_StateFakeSession session) => session.shutdownCount == 1,
        ),
    'aggregate-budget fixture releases every admitted and removed session',
  );
}

Future<void> _testApplicationQuitCoordinator() async {
  final List<String> emptyReplies = <String>[];
  final TerminalApplicationState emptyState = TerminalApplicationState();
  final TerminalApplicationQuitCoordinator emptyCoordinator =
      TerminalApplicationQuitCoordinator(
        state: emptyState,
        replyToTerminationRequest:
            (
              ApplicationTerminateRequestedEvent request, {
              required bool allow,
            }) {
              emptyReplies.add('${request.operationId}:$allow');
            },
      );
  const ApplicationTerminateRequestedEvent emptyRequest =
      ApplicationTerminateRequestedEvent(monotonicMicros: 1, operationId: 1);
  final TerminalApplicationQuitResult emptyResult = await emptyCoordinator
      .handleTerminationRequest(emptyRequest);
  _expect(
    emptyResult.disposition == TerminalApplicationQuitDisposition.terminated &&
        emptyResult.snapshot!.panes.isEmpty &&
        emptyReplies.join(',') == '1:true' &&
        emptyState.isDisposed &&
        (await emptyCoordinator.handleTerminationRequest(emptyRequest))
                .disposition ==
            TerminalApplicationQuitDisposition.stale &&
        emptyReplies.length == 1,
    'empty application quits immediately and replies once to one native ID',
  );

  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState firstWindow = await state.createWindow(
    configuration,
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final TerminalPane first = state.paneForId(firstTab.focusedPaneId)!;
  final TerminalPane second = await state.splitPane(
    first.id,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalTabState secondTab = await state.createTab(
    firstWindow.id,
    configuration,
  );
  final TerminalPane third = state.paneForId(secondTab.focusedPaneId)!;
  final TerminalWindowState secondWindow = await state.createWindow(
    configuration,
  );
  final TerminalPane fourth = state.paneForId(
    secondWindow.selectedTab.focusedPaneId,
  )!;
  for (final TerminalPane pane in <TerminalPane>[
    first,
    second,
    third,
    fourth,
  ]) {
    await pane.start();
  }
  sessions[0].processDisposition =
      TerminalPaneProcessDisposition.owningShellCommand;
  sessions[1].processDisposition =
      TerminalPaneProcessDisposition.foregroundProcess;
  sessions[2].live = false;
  sessions[3].failProcessSnapshot = true;
  state
    ..focusPane(firstTab.id, second.id)
    ..activateWindow(firstWindow.id);

  final TerminalPaneCloseCoordinator paneClose = TerminalPaneCloseCoordinator(
    state: state,
  );
  final TerminalPaneCloseResult paneConfirmation = await paneClose
      .requestClose();
  final List<String> replies = <String>[];
  var preShutdownCount = 0;
  var programmaticTerminationCount = 0;
  final TerminalApplicationQuitCoordinator coordinator =
      TerminalApplicationQuitCoordinator(
        state: state,
        paneCloseCoordinator: paneClose,
        replyToTerminationRequest:
            (
              ApplicationTerminateRequestedEvent request, {
              required bool allow,
            }) {
              replies.add('${request.operationId}:$allow');
            },
        onPreShutdown: () async {
          preShutdownCount++;
          throw StateError('injected pre-shutdown failure');
        },
        terminateProgrammatically: () async {
          programmaticTerminationCount++;
        },
      );
  const ApplicationTerminateRequestedEvent firstNative =
      ApplicationTerminateRequestedEvent(monotonicMicros: 41, operationId: 41);
  final TerminalApplicationQuitResult firstRequest = await coordinator
      .handleTerminationRequest(firstNative);
  final TerminalApplicationQuitConfirmation firstConfirmation =
      firstRequest.confirmation!;
  final TerminalApplicationQuitSnapshot firstSnapshot =
      firstConfirmation.snapshot;
  _expect(
    paneConfirmation.disposition ==
            TerminalPaneCloseDisposition.confirmationRequired &&
        !second.closeConfirmationPending &&
        paneClose.applicationQuitInProgress &&
        firstRequest.disposition ==
            TerminalApplicationQuitDisposition.confirmationRequired &&
        firstSnapshot.panes
                .map((TerminalApplicationQuitPaneSnapshot pane) => pane.paneId)
                .join(',') ==
            '${first.id},${second.id},${third.id},${fourth.id}' &&
        firstSnapshot.count(TerminalPaneProcessDisposition.idleShell) == 0 &&
        firstSnapshot.count(
              TerminalPaneProcessDisposition.owningShellCommand,
            ) ==
            1 &&
        firstSnapshot.count(TerminalPaneProcessDisposition.foregroundProcess) ==
            1 &&
        firstSnapshot.count(TerminalPaneProcessDisposition.nonLive) == 1 &&
        firstSnapshot.count(TerminalPaneProcessDisposition.unavailable) == 1 &&
        firstSnapshot.machineLine() ==
            'TERMINAL_APPLICATION_QUIT_SNAPSHOT panes=4 non_live=1 idle=0 '
                'shell_command=1 foreground=1 unavailable=1 confirmation=true' &&
        state.paneCount == 4 &&
        replies.isEmpty,
    'native Quit atomically snapshots mixed panes and cancels pane Close',
  );
  _expect(
    (await paneClose.requestClose()).disposition ==
            TerminalPaneCloseDisposition.busy &&
        (await coordinator.handleTerminationRequest(firstNative))
                .confirmation ==
            firstConfirmation &&
        replies.isEmpty &&
        state.paneCount == 4,
    'pending Quit blocks partial pane removal and coalesces its native ID',
  );

  const ApplicationTerminateRequestedEvent competingNative =
      ApplicationTerminateRequestedEvent(monotonicMicros: 42, operationId: 42);
  _expect(
    (await coordinator.handleTerminationRequest(competingNative)).disposition ==
        TerminalApplicationQuitDisposition.busy,
    'competing native Quit is refused while one confirmation is pending',
  );
  _expect(
    (await coordinator.handleTerminationRequest(competingNative)).disposition ==
        TerminalApplicationQuitDisposition.stale,
    'a duplicate refused native operation is stale',
  );
  sessions[1].processDisposition = TerminalPaneProcessDisposition.idleShell;
  _expect(
    (await coordinator.confirmQuit(firstConfirmation)).disposition ==
            TerminalApplicationQuitDisposition.stale &&
        replies.join(',') == '42:false,41:false' &&
        !paneClose.applicationQuitInProgress &&
        state.paneCount == 4,
    'changed process identity invalidates the aggregate and refuses its ID',
  );

  const ApplicationTerminateRequestedEvent retryNative =
      ApplicationTerminateRequestedEvent(monotonicMicros: 43, operationId: 43);
  final TerminalApplicationQuitResult retryRequest = await coordinator
      .handleTerminationRequest(retryNative);
  _expect(
    retryRequest.disposition ==
            TerminalApplicationQuitDisposition.confirmationRequired &&
        coordinator.cancelQuit(retryRequest.confirmation!) &&
        !coordinator.cancelQuit(retryRequest.confirmation!) &&
        replies.join(',') == '42:false,41:false,43:false' &&
        state.paneCount == 4,
    'aggregate cancellation refuses one native request and preserves all panes',
  );

  sessions[0].failShutdown = true;
  final TerminalApplicationQuitResult menuRequest = await coordinator
      .requestQuit();
  final TerminalApplicationQuitConfirmation menuConfirmation =
      menuRequest.confirmation!;
  final TerminalApplicationQuitResult completed = await coordinator
      .requestQuit();
  _expect(
    menuRequest.disposition ==
            TerminalApplicationQuitDisposition.confirmationRequired &&
        completed.disposition ==
            TerminalApplicationQuitDisposition.terminatedWithCleanupFailure &&
        completed.preShutdownFailed &&
        completed.shutdown!.disposition ==
            TerminalSessionShutdownDisposition.failed &&
        completed.snapshot == menuConfirmation.snapshot &&
        preShutdownCount == 1 &&
        programmaticTerminationCount == 1 &&
        sessions.every(
          (_StateFakeSession session) => session.shutdownCount == 1,
        ) &&
        state.isDisposed &&
        state.paneCount == 0 &&
        state.windowCount == 0 &&
        identical(await coordinator.requestQuit(), completed) &&
        (await coordinator.confirmQuit(menuConfirmation)).disposition ==
            TerminalApplicationQuitDisposition.stale &&
        completed.machineLine() ==
            'TERMINAL_APPLICATION_QUIT '
                'disposition=terminatedWithCleanupFailure operation_id=0 '
                'native_operation_id=0 panes=4 cleanup=failed '
                'pre_shutdown_failed=true',
    'confirmed menu Quit tears down all panes once and reports cleanup faults',
  );
}

Future<void> _testPaneCloseCoordinator() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState firstWindow = await state.createWindow(
    configuration,
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final TerminalPane first = state.paneForId(firstTab.focusedPaneId)!;
  final TerminalPane second = await state.splitPane(
    first.id,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalPane third = await state.splitPane(
    second.id,
    configuration,
    axis: TerminalSplitAxis.vertical,
  );
  final TerminalTabState secondTab = await state.createTab(
    firstWindow.id,
    configuration,
  );
  final TerminalPane fourth = state.paneForId(secondTab.focusedPaneId)!;
  final TerminalWindowState secondWindow = await state.createWindow(
    configuration,
  );
  final TerminalPane fifth = state.paneForId(
    secondWindow.selectedTab.focusedPaneId,
  )!;
  for (final TerminalPane pane in <TerminalPane>[
    first,
    second,
    third,
    fourth,
    fifth,
  ]) {
    await pane.start();
  }
  state
    ..focusPane(firstTab.id, third.id)
    ..activateWindow(firstWindow.id);
  sessions[2].processDisposition =
      TerminalPaneProcessDisposition.foregroundProcess;
  var hierarchyChanges = 0;
  final List<PaneId> preRemovedPaneIds = <PaneId>[];
  final Map<PaneId, _StateFakeSession> sessionByPaneId =
      <PaneId, _StateFakeSession>{
        first.id: sessions[0],
        second.id: sessions[1],
        third.id: sessions[2],
        fourth.id: sessions[3],
        fifth.id: sessions[4],
      };
  final TerminalPaneCloseCoordinator coordinator = TerminalPaneCloseCoordinator(
    state: state,
    onBeforePaneRemoved: (PaneId paneId) async {
      _expect(
        sessionByPaneId[paneId]!.shutdownCount == 0,
        'pre-removal callback runs before session shutdown',
      );
      await Future<void>.delayed(Duration.zero);
      preRemovedPaneIds.add(paneId);
    },
    onHierarchyChanged: () => hierarchyChanges++,
  );

  final TerminalPaneCloseResult firstRequest = await coordinator.requestClose();
  final TerminalPaneCloseConfirmation firstConfirmation =
      firstRequest.confirmation!;
  _expect(
    firstRequest.disposition ==
            TerminalPaneCloseDisposition.confirmationRequired &&
        firstConfirmation.paneId == third.id &&
        firstConfirmation.sessionId == third.sessionId &&
        state.paneCount == 5 &&
        hierarchyChanges == 0 &&
        third.closeConfirmationPending,
    'focused foreground pane requires an identity-bound confirmation',
  );
  final TerminalPaneCloseConfirmation wrongConfirmation =
      TerminalPaneCloseConfirmation(
        operationId: firstConfirmation.operationId + 1,
        paneId: third.id,
        sessionId: third.sessionId,
        processDisposition: TerminalPaneProcessDisposition.foregroundProcess,
      );
  _expect(
    (await coordinator.confirmClose(wrongConfirmation)).disposition ==
            TerminalPaneCloseDisposition.stale &&
        coordinator.pendingConfirmation == firstConfirmation &&
        state.paneCount == 5,
    'wrong operation identity cannot consume a valid confirmation',
  );
  third.insertText('cancel');
  _expect(
    (await coordinator.confirmClose(firstConfirmation)).disposition ==
            TerminalPaneCloseDisposition.stale &&
        state.paneCount == 5 &&
        coordinator.pendingConfirmation == null &&
        !third.closeConfirmationPending,
    'terminal interaction invalidates a pending close without mutation',
  );

  final TerminalPaneCloseResult repeatedRequest = await coordinator
      .requestClose();
  final TerminalPaneCloseConfirmation repeatedConfirmation =
      repeatedRequest.confirmation!;
  final TerminalPaneCloseResult foregroundRemoval = await coordinator
      .requestClose();
  _expect(
    repeatedConfirmation.operationId > firstConfirmation.operationId &&
        foregroundRemoval.disposition == TerminalPaneCloseDisposition.removed &&
        foregroundRemoval.removal?.paneId == third.id &&
        !foregroundRemoval.removal!.removedTab &&
        !foregroundRemoval.removal!.removedWindow &&
        state.paneCount == 4 &&
        firstTab.focusedPaneId == second.id &&
        sessions[2].shutdownCount == 1 &&
        preRemovedPaneIds.join(',') == '${third.id}' &&
        hierarchyChanges == 1,
    'repeating the exact focused request confirms one nested split removal',
  );

  sessions[1].processDisposition =
      TerminalPaneProcessDisposition.owningShellCommand;
  final TerminalPaneCloseResult shellCommandRequest = await coordinator
      .requestClose(paneId: second.id);
  _expect(
    shellCommandRequest.disposition ==
            TerminalPaneCloseDisposition.confirmationRequired &&
        shellCommandRequest.confirmation!.processDisposition ==
            TerminalPaneProcessDisposition.owningShellCommand &&
        coordinator.cancelClose(shellCommandRequest.confirmation!) &&
        state.paneCount == 4 &&
        hierarchyChanges == 1,
    'owning-shell semantic command requires cancellable pane confirmation',
  );
  sessions[1].processDisposition = TerminalPaneProcessDisposition.idleShell;
  final TerminalPaneCloseResult idleRemoval = await coordinator.requestClose(
    paneId: second.id,
  );
  _expect(
    idleRemoval.disposition == TerminalPaneCloseDisposition.removed &&
        firstTab.paneIds.single == first.id &&
        firstTab.focusedPaneId == first.id &&
        sessions[1].shutdownCount == 1 &&
        hierarchyChanges == 2,
    'idle shell closes immediately and selects the structural neighbor',
  );

  sessions[3].failProcessSnapshot = true;
  final TerminalPaneCloseResult failedSnapshotRequest = await coordinator
      .requestClose(paneId: fourth.id);
  _expect(
    failedSnapshotRequest.disposition ==
            TerminalPaneCloseDisposition.confirmationRequired &&
        failedSnapshotRequest.confirmation!.processDisposition ==
            TerminalPaneProcessDisposition.unavailable &&
        coordinator.cancelClose(failedSnapshotRequest.confirmation!) &&
        state.paneCount == 3,
    'thrown pane snapshot is converted to conservative confirmation',
  );
  sessions[3]
    ..failProcessSnapshot = false
    ..processDisposition = TerminalPaneProcessDisposition.unavailable;
  final TerminalPaneCloseResult unavailableRequest = await coordinator
      .requestClose(paneId: fourth.id);
  _expect(
    unavailableRequest.disposition ==
            TerminalPaneCloseDisposition.confirmationRequired &&
        coordinator.cancelClose(unavailableRequest.confirmation!) &&
        !coordinator.cancelClose(unavailableRequest.confirmation!) &&
        state.paneCount == 3 &&
        !fourth.closeConfirmationPending,
    'unavailable live process state is conservative and explicitly cancellable',
  );
  sessions[3].live = false;
  final TerminalPaneCloseResult nonLiveRemoval = await coordinator.requestClose(
    paneId: fourth.id,
  );
  _expect(
    nonLiveRemoval.disposition == TerminalPaneCloseDisposition.removed &&
        nonLiveRemoval.removal!.removedTab &&
        !nonLiveRemoval.removal!.removedWindow &&
        firstWindow.tabs.length == 1 &&
        hierarchyChanges == 3,
    'non-live background-tab pane removes its empty tab without confirmation',
  );

  sessions[4].shutdownBarrier = Completer<void>();
  final Future<TerminalPaneCloseResult> pendingRemoval = coordinator
      .requestClose(paneId: fifth.id);
  await Future<void>.delayed(Duration.zero);
  _expect(
    coordinator.removalInProgress &&
        (await coordinator.requestClose(paneId: first.id)).disposition ==
            TerminalPaneCloseDisposition.busy &&
        state.paneCount == 2,
    'one in-flight removal excludes concurrent hierarchy mutation',
  );
  sessions[4].shutdownBarrier!.complete();
  final TerminalPaneCloseResult windowRemoval = await pendingRemoval;
  _expect(
    windowRemoval.disposition == TerminalPaneCloseDisposition.removed &&
        windowRemoval.removal!.removedTab &&
        windowRemoval.removal!.removedWindow &&
        state.windowCount == 1 &&
        state.activeWindowId == firstWindow.id &&
        hierarchyChanges == 4,
    'last pane closes its window and selects the neighboring logical window',
  );

  sessions[0].failShutdown = true;
  final TerminalPaneCloseResult failedCleanup = await coordinator.requestClose(
    paneId: first.id,
  );
  _expect(
    failedCleanup.disposition ==
            TerminalPaneCloseDisposition.removedWithCleanupFailure &&
        failedCleanup.removal!.shutdown.disposition ==
            TerminalSessionShutdownDisposition.failed &&
        state.paneCount == 0 &&
        state.windowCount == 0 &&
        preRemovedPaneIds.join(',') ==
            '${third.id},${second.id},${fourth.id},${fifth.id},${first.id}' &&
        hierarchyChanges == 5 &&
        (await coordinator.requestClose()).disposition ==
            TerminalPaneCloseDisposition.noTarget &&
        failedCleanup.machineLine() ==
            'TERMINAL_PANE_CLOSE_TRANSACTION '
                'disposition=removedWithCleanupFailure operation_id=0 '
                'pane=${first.id} session=${first.sessionId} '
                'removed_tab=true removed_window=true cleanup=failed',
    'cleanup failure remains classified after deterministic structural removal',
  );
  await state.shutdown();
}

Future<void> _testTabPresentationAndCwdPolicy() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState window = await state.createWindow(configuration);
  final TerminalTabState tab = window.selectedTab;
  final PaneId firstPaneId = tab.focusedPaneId;
  final TerminalPane secondPane = await state.splitPane(
    firstPaneId,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final Map<PaneId, TerminalSessionMetadata> metadata =
      <PaneId, TerminalSessionMetadata>{
        firstPaneId: TerminalSessionMetadata(),
        secondPane.id: TerminalSessionMetadata(),
      };
  final TerminalTabPresentationResolver resolver =
      TerminalTabPresentationResolver(
        metadataForPane: (PaneId paneId) => metadata[paneId],
      );

  state.focusPane(tab.id, firstPaneId);
  TerminalTabPresentation presentation = resolver.resolve(
    tab,
    fallbackTitle: 'Dart Terminal',
  );
  _expect(
    presentation.title == 'Dart Terminal' &&
        presentation.color == null &&
        presentation.representedFilePath == null,
    'tab presentation starts from the trusted product fallback',
  );

  metadata[firstPaneId]!
    ..setWorkingDirectory(Uri.parse('file://localhost/private/tmp/Project%20A'))
    ..setWindowTitle('live 日本語');
  presentation = resolver.resolve(tab, fallbackTitle: 'Dart Terminal');
  _expect(
    presentation.title == 'live 日本語' &&
        presentation.representedFilePath == '/private/tmp/Project A' &&
        resolver.inheritedWorkingDirectoryForPane(firstPaneId) ==
            '/private/tmp/Project A',
    'focused session title and decoded local OSC 7 cwd drive presentation',
  );

  metadata[firstPaneId]!
    ..reset()
    ..setWorkingDirectory(
      Uri.parse('file://localhost/private/tmp/Project%20A'),
    );
  _expect(
    resolver.resolve(tab, fallbackTitle: 'Dart Terminal').title == 'Project A',
    'local cwd basename supplies a title only when the session title is absent',
  );
  metadata[firstPaneId]!.setWindowTitle('live 日本語');

  _expect(
    state.renameTab(tab.id, 'Pinned tab') &&
        !state.renameTab(tab.id, 'Pinned tab') &&
        state.setTabColor(tab.id, TerminalTabColor.blueMarker) &&
        !state.setTabColor(tab.id, TerminalTabColor.blueMarker),
    'tab rename and color mutations report only actual state changes',
  );
  presentation = resolver.resolve(tab, fallbackTitle: 'Dart Terminal');
  _expect(
    presentation.title == 'Pinned tab' &&
        presentation.color == TerminalTabColor.blueMarker &&
        presentation.representedFilePath == '/private/tmp/Project A',
    'user rename overrides live title without discarding cwd or color',
  );

  metadata[secondPane.id]!.setWorkingDirectory(
    Uri.parse('file://remote.example/private/remote'),
  );
  state
    ..focusPane(tab.id, secondPane.id)
    ..renameTab(tab.id, null)
    ..setTabColor(tab.id, null);
  presentation = resolver.resolve(tab, fallbackTitle: 'Dart Terminal');
  _expect(
    presentation.title == 'Dart Terminal' &&
        presentation.color == null &&
        presentation.representedFilePath == null &&
        resolver.inheritedWorkingDirectoryForPane(
              secondPane.id,
              fallback: '/trusted/fallback',
            ) ==
            '/trusted/fallback',
    'remote OSC 7 authority cannot become a title path, proxy, or launch cwd',
  );

  metadata[secondPane.id]!.setWindowTitle('');
  _expect(
    resolver.resolve(tab, fallbackTitle: 'Dart Terminal').title.isEmpty,
    'an explicitly accepted empty OSC title is not rewritten',
  );
  _expect(
    TerminalTabPresentationResolver.localFilePath(
          Uri.parse('file:///private/tmp/%00unsafe'),
        ) ==
        null,
    'percent-decoded control data cannot become filesystem authority',
  );
  _expect(
    TerminalTabPresentationResolver.localFilePath(
              Uri.parse('file:///private/tmp/Project%20B'),
            ) ==
            '/private/tmp/Project B' &&
        TerminalTabPresentationResolver.localFilePath(
              Uri.parse('file://LOCALHOST/'),
            ) ==
            '/',
    'empty-authority and localhost absolute file URIs map deterministically',
  );

  _expectThrows<ArgumentError>(
    () => state.renameTab(tab.id, ''),
    'empty user tab title is rejected instead of hiding native identity',
  );
  _expectThrows<ArgumentError>(
    () => state.renameTab(tab.id, 'unsafe\u202etitle'),
    'bidirectional formatting controls are rejected from user tab titles',
  );
  _expectThrows<ArgumentError>(
    () => state.renameTab(
      tab.id,
      List<String>.filled(
        TerminalTabMetadataLimits.maximumCustomTitleUtf8Bytes + 1,
        'a',
      ).join(),
    ),
    'oversized user tab title is rejected atomically',
  );
  _expect(
    tab.customTitle == null && tab.color == null,
    'failed mutations preserve prior tab metadata state',
  );
  _expectThrows<RangeError>(
    () => TerminalTabColor(red: 256, green: 0, blue: 0),
    'tab color channels are byte bounded',
  );
  _expectThrows<ArgumentError>(
    () => TerminalTabColor(red: 0, green: 0, blue: 0, alpha: 0),
    'fully transparent tab colors are rejected',
  );
  _expectThrows<ArgumentError>(
    () => resolver.resolve(tab, fallbackTitle: 'unsafe\u0000fallback'),
    'unsafe fallback titles fail before native presentation',
  );

  state.validate();
  await state.shutdown();
}

void _testTypedIdentityValues() {
  _expect(
    const TerminalWindowId(7) == const TerminalWindowId(7) &&
        const TerminalWindowId(7) != const TerminalWindowId(8) &&
        const TerminalTabId(7) == const TerminalTabId(7) &&
        const TerminalSplitNodeId(7) == const TerminalSplitNodeId(7) &&
        const TerminalWindowId(7).toString() == '7' &&
        const TerminalTabId(8).toString() == '8' &&
        const TerminalSplitNodeId(9).toString() == '9',
    'window, tab, and split identities are typed stable values',
  );
}

void _testSplitTraversalAndLookup() {
  final TerminalSplitTree tree = TerminalSplitTree(
    root: TerminalSplitBranch(
      id: const TerminalSplitNodeId(1),
      axis: TerminalSplitAxis.horizontal,
      fraction: 0.4,
      first: const TerminalSplitLeaf(
        id: TerminalSplitNodeId(2),
        paneId: PaneId(10),
      ),
      second: TerminalSplitBranch(
        id: const TerminalSplitNodeId(3),
        axis: TerminalSplitAxis.vertical,
        fraction: 0.6,
        first: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(4),
          paneId: PaneId(11),
        ),
        second: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(5),
          paneId: PaneId(12),
        ),
      ),
    ),
  );

  _expect(
    _paneValues(tree.paneIds).join(',') == '10,11,12' &&
        _nodeValues(tree.nodeIds).join(',') == '1,2,3,4,5' &&
        tree.paneCount == 3 &&
        tree.nodeCount == 5,
    'split inventory follows deterministic first-to-second pre-order',
  );
  _expect(
    tree.leafForPane(const PaneId(11))?.id == const TerminalSplitNodeId(4) &&
        tree.nodeForId(const TerminalSplitNodeId(3)) is TerminalSplitBranch &&
        tree.leafForPane(const PaneId(99)) == null &&
        tree.nodeForId(const TerminalSplitNodeId(99)) == null,
    'split lookup resolves typed node and pane identities',
  );
  _expectThrows<UnsupportedError>(
    () => tree.paneIds.add(const PaneId(13)),
    'pane traversal is an immutable snapshot',
  );
  _expectThrows<UnsupportedError>(
    () => tree.nodeIds.clear(),
    'node traversal is an immutable snapshot',
  );
}

void _testSplitPlacementAndCollapse() {
  final TerminalSplitTree single = TerminalSplitTree.single(
    nodeId: const TerminalSplitNodeId(1),
    paneId: const PaneId(1),
  );
  final TerminalSplitTree horizontal = single.splitPane(
    targetPaneId: const PaneId(1),
    newPaneId: const PaneId(2),
    branchNodeId: const TerminalSplitNodeId(2),
    newLeafNodeId: const TerminalSplitNodeId(3),
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalSplitTree nested = horizontal.splitPane(
    targetPaneId: const PaneId(1),
    newPaneId: const PaneId(3),
    branchNodeId: const TerminalSplitNodeId(4),
    newLeafNodeId: const TerminalSplitNodeId(5),
    axis: TerminalSplitAxis.vertical,
    placement: TerminalSplitPlacement.before,
    fraction: 0.25,
  );

  _expect(
    _paneValues(single.paneIds).join(',') == '1' &&
        _paneValues(horizontal.paneIds).join(',') == '1,2' &&
        _paneValues(nested.paneIds).join(',') == '3,1,2',
    'split replacement is immutable and placement controls visual order',
  );
  final TerminalSplitBranch root = nested.root as TerminalSplitBranch;
  final TerminalSplitBranch first = root.first as TerminalSplitBranch;
  _expect(
    root.axis == TerminalSplitAxis.horizontal &&
        first.axis == TerminalSplitAxis.vertical &&
        first.fraction == 0.25,
    'nested split axes and fractions remain attached to their branches',
  );

  final TerminalSplitTree afterFirst = nested.removePane(const PaneId(1))!;
  _expect(
    _paneValues(afterFirst.paneIds).join(',') == '3,2' &&
        afterFirst.nodeCount == 3 &&
        afterFirst.nodeForId(const TerminalSplitNodeId(4)) == null,
    'removing one leaf collapses its parent into the sibling',
  );
  final TerminalSplitTree afterSecond = afterFirst.removePane(const PaneId(3))!;
  _expect(
    _paneValues(afterSecond.paneIds).join(',') == '2' &&
        afterSecond.root is TerminalSplitLeaf &&
        afterSecond.nodeCount == 1,
    'removing a nested leaf preserves the surviving stable leaf identity',
  );
  _expect(
    afterSecond.removePane(const PaneId(2)) == null,
    'removing the last leaf returns an empty-tree result',
  );
}

void _testSplitTopologyValidationAndBounds() {
  _expectThrows<ArgumentError>(
    () => TerminalSplitBranch(
      id: const TerminalSplitNodeId(1),
      axis: TerminalSplitAxis.horizontal,
      fraction: double.nan,
      first: const TerminalSplitLeaf(
        id: TerminalSplitNodeId(2),
        paneId: PaneId(1),
      ),
      second: const TerminalSplitLeaf(
        id: TerminalSplitNodeId(3),
        paneId: PaneId(2),
      ),
    ),
    'non-finite fractions are rejected',
  );
  _expectThrows<StateError>(
    () => TerminalSplitTree(
      root: TerminalSplitBranch(
        id: const TerminalSplitNodeId(1),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.5,
        first: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(2),
          paneId: PaneId(1),
        ),
        second: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(2),
          paneId: PaneId(2),
        ),
      ),
    ),
    'duplicate node identities are rejected',
  );
  _expectThrows<StateError>(
    () => TerminalSplitTree(
      root: TerminalSplitBranch(
        id: const TerminalSplitNodeId(1),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.5,
        first: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(2),
          paneId: PaneId(1),
        ),
        second: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(3),
          paneId: PaneId(1),
        ),
      ),
    ),
    'duplicate pane identities are rejected',
  );

  TerminalSplitTree bounded = TerminalSplitTree.single(
    nodeId: const TerminalSplitNodeId(1),
    paneId: const PaneId(1),
  );
  int nextNode = 2;
  for (
    int pane = 2;
    pane <= TerminalApplicationStateLimits.maximumPanesPerTab;
    pane++
  ) {
    bounded = bounded.splitPane(
      targetPaneId: PaneId(pane - 1),
      newPaneId: PaneId(pane),
      branchNodeId: TerminalSplitNodeId(nextNode++),
      newLeafNodeId: TerminalSplitNodeId(nextNode++),
      axis: pane.isEven
          ? TerminalSplitAxis.horizontal
          : TerminalSplitAxis.vertical,
    );
  }
  _expect(
    bounded.paneCount == TerminalApplicationStateLimits.maximumPanesPerTab &&
        bounded.nodeCount ==
            TerminalApplicationStateLimits.maximumSplitNodesPerTab,
    'split construction reaches the explicit tab bound exactly',
  );
  _expectThrows<StateError>(
    () => bounded.splitPane(
      targetPaneId: const PaneId(1),
      newPaneId: const PaneId(1000),
      branchNodeId: const TerminalSplitNodeId(1000),
      newLeafNodeId: const TerminalSplitNodeId(1001),
      axis: TerminalSplitAxis.horizontal,
    ),
    'split construction refuses a pane beyond the fixed bound',
  );
  _expectThrows<StateError>(
    () => bounded.removePane(const PaneId(1000)),
    'removing an unknown pane is rejected without mutation',
  );
}

void _testSplitResizeEqualizeTraversalAndLayout() {
  final TerminalSplitTree original = TerminalSplitTree(
    root: TerminalSplitBranch(
      id: const TerminalSplitNodeId(1),
      axis: TerminalSplitAxis.horizontal,
      fraction: 0.1,
      first: const TerminalSplitLeaf(
        id: TerminalSplitNodeId(2),
        paneId: PaneId(1),
      ),
      second: TerminalSplitBranch(
        id: const TerminalSplitNodeId(3),
        axis: TerminalSplitAxis.vertical,
        fraction: 0.9,
        first: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(4),
          paneId: PaneId(2),
        ),
        second: const TerminalSplitLeaf(
          id: TerminalSplitNodeId(5),
          paneId: PaneId(3),
        ),
      ),
    ),
  );
  final TerminalSplitTree resized = original.resizeBranch(
    const TerminalSplitNodeId(1),
    0.7,
  );
  final TerminalSplitTree equalized = resized.equalize(
    subtreeRootId: const TerminalSplitNodeId(3),
  );
  final TerminalSplitBranch originalRoot = original.root as TerminalSplitBranch;
  final TerminalSplitBranch resizedRoot = resized.root as TerminalSplitBranch;
  final TerminalSplitBranch equalizedRoot =
      equalized.root as TerminalSplitBranch;
  _expect(
    originalRoot.fraction == 0.1 &&
        resizedRoot.fraction == 0.7 &&
        equalizedRoot.fraction == 0.7 &&
        (equalizedRoot.second as TerminalSplitBranch).fraction == 0.5,
    'resize changes one immutable branch and subtree equalize stays scoped',
  );
  _expect(
    original.traversePane(
              const PaneId(3),
              direction: TerminalPaneFocusTraversal.next,
            ) ==
            const PaneId(1) &&
        original.traversePane(
              const PaneId(1),
              direction: TerminalPaneFocusTraversal.previous,
            ) ==
            const PaneId(3),
    'visual focus traversal wraps in both directions',
  );

  final TerminalSplitLayout layout = original.layout(
    availableSize: TerminalSplitLayoutSize(width: 100, height: 80),
    cellSize: TerminalSplitLayoutSize(width: 10, height: 20),
    dividerThickness: 2,
  );
  final TerminalSplitBranchLayout rootLayout =
      layout.branches[const TerminalSplitNodeId(1)]!;
  final TerminalSplitBranchLayout nestedLayout =
      layout.branches[const TerminalSplitNodeId(3)]!;
  final TerminalPaneLayoutRect first = layout.panes[const PaneId(1)]!;
  final TerminalPaneLayoutRect second = layout.panes[const PaneId(2)]!;
  final TerminalPaneLayoutRect third = layout.panes[const PaneId(3)]!;
  _expect(
    rootLayout.firstExtent == 10 &&
        rootLayout.secondExtent == 88 &&
        rootLayout.firstMinimumExtent == 10 &&
        nestedLayout.firstExtent == 58 &&
        nestedLayout.secondExtent == 20 &&
        first.left == 0 &&
        first.width == 10 &&
        first.height == 80 &&
        second.left == 12 &&
        second.top == 0 &&
        second.width == 88 &&
        second.height == 58 &&
        third.left == 12 &&
        third.top == 60 &&
        third.width == 88 &&
        third.height == 20,
    'layout clamps nested fractions to one-cell descendant minima',
  );
  final TerminalSplitLayout zoomed = original.layout(
    availableSize: TerminalSplitLayoutSize(width: 10.5, height: 20.25),
    cellSize: TerminalSplitLayoutSize(width: 10, height: 20),
    dividerThickness: 2,
    zoomedPaneId: const PaneId(2),
  );
  _expect(
    zoomed.panes.length == 1 &&
        zoomed.branches.isEmpty &&
        zoomed.panes[const PaneId(2)]?.width == 10.5 &&
        zoomed.panes[const PaneId(2)]?.height == 20.25,
    'zoom requires only the visible pane minimum and preserves topology',
  );
  _expectThrows<StateError>(
    () => original.layout(
      availableSize: TerminalSplitLayoutSize(width: 21, height: 42),
      cellSize: TerminalSplitLayoutSize(width: 10, height: 20),
      dividerThickness: 2,
    ),
    'geometry rejects a viewport narrower than the recursive cell minimum',
  );
  _expectThrows<StateError>(
    () => original.resizeBranch(const TerminalSplitNodeId(2), 0.5),
    'resize rejects a leaf identity',
  );
  _expectThrows<StateError>(
    () => original.equalize(subtreeRootId: const TerminalSplitNodeId(99)),
    'equalize rejects an unknown subtree identity',
  );
  _expectThrows<ArgumentError>(
    () => TerminalSplitLayoutSize(width: 0, height: 20),
    'layout size rejects a non-positive dimension',
  );
}

Future<void> _testApplicationHierarchyFocusAndIndexes() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState(
    initialWindowId: 10,
    initialTabId: 20,
    initialSplitNodeId: 30,
  );
  final TerminalPaneConfiguration configuration = _configuration(sessions);

  final TerminalWindowState firstWindow = await state.createWindow(
    configuration,
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  final TerminalTabState secondTab = await state.createTab(
    firstWindow.id,
    configuration,
  );
  final PaneId secondPane = secondTab.focusedPaneId;
  final TerminalPane third = await state.splitPane(
    secondPane,
    configuration,
    axis: TerminalSplitAxis.vertical,
    placement: TerminalSplitPlacement.before,
    fraction: 0.4,
  );
  final TerminalWindowState secondWindow = await state.createWindow(
    configuration,
  );
  final PaneId fourthPane = secondWindow.selectedTab.focusedPaneId;

  _expect(
    firstWindow.id == const TerminalWindowId(11) &&
        secondWindow.id == const TerminalWindowId(12) &&
        firstTab.id == const TerminalTabId(21) &&
        secondTab.id == const TerminalTabId(22) &&
        secondWindow.selectedTab.id == const TerminalTabId(23) &&
        firstTab.splitTree.root.id == const TerminalSplitNodeId(31) &&
        secondTab.splitTree.root.id == const TerminalSplitNodeId(33) &&
        secondTab.splitTree.leafForPane(third.id)?.id ==
            const TerminalSplitNodeId(34) &&
        secondWindow.selectedTab.splitTree.root.id ==
            const TerminalSplitNodeId(35),
    'application allocates monotonic stable identities across windows and tabs',
  );
  _expect(
    state.windowCount == 2 &&
        state.tabCount == 3 &&
        state.paneCount == 4 &&
        state.activeWindowId == secondWindow.id &&
        secondTab.focusedPaneId == third.id &&
        _paneValues(secondTab.paneIds).join(',') ==
            '${third.id.value},${secondPane.value}',
    'application retains two windows, multiple tabs, and four indexed panes',
  );
  _expect(
    state.machineLineForPane(fourthPane) ==
        'TERMINAL_APPLICATION_MODEL windows=2 tabs=3 panes=4 '
            'window=12 tab=23 split_leaf=35 pane=4 session=4:1 '
            'active=true selected=true focused=true',
    'product model diagnostics contain only stable hierarchy identity',
  );
  _expect(
    state.locationForPane(firstPane) ==
            TerminalPaneLocation(
              windowId: firstWindow.id,
              tabId: firstTab.id,
            ) &&
        state.locationForPane(third.id) ==
            TerminalPaneLocation(
              windowId: firstWindow.id,
              tabId: secondTab.id,
            ) &&
        identical(state.paneForId(third.id), third) &&
        state.locationForPane(fourthPane)?.windowId == secondWindow.id,
    'pane reverse indexes resolve one owning tab and window',
  );

  state.focusPane(firstTab.id, firstPane);
  _expect(
    state.activeWindowId == firstWindow.id &&
        firstWindow.selectedTabId == firstTab.id &&
        firstTab.focusedPaneId == firstPane &&
        secondTab.focusedPaneId == third.id,
    'focusing one pane selects only its owning tab and window',
  );
  state.selectTab(firstWindow.id, secondTab.id);
  _expect(
    firstWindow.selectedTabId == secondTab.id &&
        state.activeWindowId == firstWindow.id &&
        secondTab.focusedPaneId == third.id,
    'tab selection preserves independent per-tab focus',
  );
  state.activateWindow(secondWindow.id);
  _expect(
    state.activeWindowId == secondWindow.id &&
        firstWindow.selectedTabId == secondTab.id &&
        secondWindow.selectedTab.focusedPaneId == fourthPane,
    'window activation preserves each window tab and pane selection',
  );
  _expectThrows<StateError>(
    () => state.selectTab(secondWindow.id, firstTab.id),
    'cross-window tab selection is rejected',
  );
  _expectThrows<StateError>(
    () => state.focusPane(firstTab.id, fourthPane),
    'cross-tab pane focus is rejected',
  );
  state.validate();
  await state.shutdown();
}

Future<void> _testApplicationLayoutMutations() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState window = await state.createWindow(configuration);
  final TerminalTabState tab = window.selectedTab;
  final PaneId first = tab.focusedPaneId;
  final TerminalPane second = await state.splitPane(
    first,
    configuration,
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.25,
  );
  final TerminalSplitNodeId rootId = tab.splitTree.root.id;
  final TerminalPane third = await state.splitPane(
    second.id,
    configuration,
    axis: TerminalSplitAxis.vertical,
    fraction: 0.75,
  );
  final TerminalSplitNodeId nestedId =
      (tab.splitTree.root as TerminalSplitBranch).second.id;

  state.resizeSplit(tab.id, rootId, 0.6);
  state.equalizeSplits(tab.id, subtreeRootId: nestedId);
  final TerminalSplitBranch root = tab.splitTree.root as TerminalSplitBranch;
  _expect(
    root.fraction == 0.6 &&
        (root.second as TerminalSplitBranch).fraction == 0.5 &&
        tab.focusedPaneId == third.id,
    'application layout mutations preserve focus and address typed branches',
  );

  state.setPaneZoom(tab.id, third.id);
  _expect(
    tab.isZoomed &&
        tab.zoomedPaneId == third.id &&
        state.traversePaneFocus(
              tab.id,
              direction: TerminalPaneFocusTraversal.next,
            ) ==
            third.id &&
        tab.focusedPaneId == third.id,
    'zoom is confined to the visible focused pane during traversal',
  );
  state.focusPane(tab.id, first);
  _expect(
    !tab.isZoomed && tab.focusedPaneId == first,
    'changing focus clears zoom before targeting another pane',
  );
  _expect(
    state.traversePaneFocus(
              tab.id,
              direction: TerminalPaneFocusTraversal.previous,
            ) ==
            third.id &&
        tab.focusedPaneId == third.id,
    'application focus traversal wraps in visual order',
  );
  _expectThrows<StateError>(
    () => state.setPaneZoom(tab.id, second.id),
    'application rejects zooming an unfocused pane',
  );
  _expectThrows<StateError>(
    () => state.resizeSplit(tab.id, const TerminalSplitNodeId(999), 0.5),
    'application rejects resizing an unknown branch',
  );
  state.validate();
  await state.shutdown();
}

Future<void> _testPaneRemovalAndOrderedShutdown() async {
  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState firstWindow = await state.createWindow(
    configuration,
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  final TerminalPane second = await state.splitPane(
    firstPane,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalPane third = await state.splitPane(
    second.id,
    configuration,
    axis: TerminalSplitAxis.vertical,
  );
  final TerminalTabState secondTab = await state.createTab(
    firstWindow.id,
    configuration,
  );
  final PaneId fourthPane = secondTab.focusedPaneId;
  final TerminalWindowState secondWindow = await state.createWindow(
    configuration,
  );
  final PaneId fifthPane = secondWindow.selectedTab.focusedPaneId;

  final TerminalPaneRemovalResult nestedRemoval = await state.removePane(
    third.id,
  );
  _expect(
    !nestedRemoval.removedTab &&
        !nestedRemoval.removedWindow &&
        nestedRemoval.shutdown.isClean &&
        firstTab.focusedPaneId == second.id &&
        _paneValues(firstTab.paneIds).join(',') ==
            '${firstPane.value},${second.id.value}' &&
        sessions[2].shutdownCount == 1 &&
        state.paneForId(third.id) == null,
    'focused nested pane removal collapses its branch and picks its neighbor',
  );
  final TerminalPaneRemovalResult tabRemoval = await state.removePane(
    fourthPane,
  );
  _expect(
    tabRemoval.removedTab &&
        !tabRemoval.removedWindow &&
        firstWindow.tabs.length == 1 &&
        firstWindow.selectedTabId == firstTab.id &&
        state.tabForId(secondTab.id) == null,
    'last pane removal deletes its tab and selects the remaining neighbor',
  );
  final TerminalPaneRemovalResult windowRemoval = await state.removePane(
    fifthPane,
  );
  _expect(
    windowRemoval.removedTab &&
        windowRemoval.removedWindow &&
        state.windowCount == 1 &&
        state.activeWindowId == firstWindow.id &&
        state.windowForId(secondWindow.id) == null,
    'last tab removal deletes its window and selects the remaining neighbor',
  );

  final TerminalPaneOwnerShutdownResult shutdown = await state.shutdown();
  final TerminalPaneOwnerShutdownResult repeated = await state.shutdown();
  _expect(
    identical(shutdown, repeated) &&
        shutdown.sessions.length == 2 &&
        shutdown.sessions[0].sessionId.paneId == second.id &&
        shutdown.sessions[1].sessionId.paneId == firstPane &&
        sessions.every(
          (_StateFakeSession session) => session.shutdownCount == 1,
        ) &&
        state.windowCount == 0 &&
        state.tabCount == 0 &&
        state.paneCount == 0 &&
        state.activeWindowId == null &&
        state.isDisposed,
    'application shutdown is reverse-visual, idempotent, and releases all panes',
  );
}

Future<void> _testApplicationLimitsAndDisposedState() async {
  var sessionFactoryCalls = 0;
  final TerminalPaneConfiguration configuration = TerminalPaneConfiguration(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          sessionFactoryCalls++;
          return _StateFakeSession(id);
        },
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalApplicationState exhausted = TerminalApplicationState(
    initialWindowId: TerminalApplicationState.maximumIdentityValue,
  );
  await _expectFutureThrows<StateError>(
    () => exhausted.createWindow(configuration),
    'exhausted window identity fails before pane creation',
  );
  _expect(
    sessionFactoryCalls == 0 && exhausted.windowCount == 0,
    'identity exhaustion leaves application and pane ownership unchanged',
  );
  await exhausted.shutdown();

  final TerminalPaneOwner nonEmptyOwner = TerminalPaneOwner();
  nonEmptyOwner.createPane(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _StateFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  _expectThrows<ArgumentError>(
    () => TerminalApplicationState(paneOwner: nonEmptyOwner),
    'application state refuses a pane owner with pre-existing ownership',
  );
  await nonEmptyOwner.shutdown();

  final List<_StateFakeSession> sessions = <_StateFakeSession>[];
  final TerminalApplicationState disposed = TerminalApplicationState();
  final TerminalWindowState window = await disposed.createWindow(
    _configuration(sessions),
  );
  final TerminalTabId tabId = window.selectedTabId;
  final PaneId paneId = window.selectedTab.focusedPaneId;
  await disposed.shutdown();
  await _expectFutureThrows<StateError>(
    () => disposed.createWindow(_configuration(sessions)),
    'disposed application rejects window admission',
  );
  _expectThrows<StateError>(
    () => disposed.selectTab(window.id, tabId),
    'disposed application rejects tab selection',
  );
  _expectThrows<StateError>(
    () => disposed.focusPane(tabId, paneId),
    'disposed application rejects pane focus',
  );
  await _expectFutureThrows<StateError>(
    () => disposed.removePane(paneId),
    'disposed application rejects pane removal',
  );
}

Iterable<int> _paneValues(Iterable<PaneId> ids) =>
    ids.map((PaneId id) => id.value);

Iterable<int> _nodeValues(Iterable<TerminalSplitNodeId> ids) =>
    ids.map((TerminalSplitNodeId id) => id.value);

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}

Future<void> _expectFutureThrows<T extends Object>(
  Future<void> Function() action,
  String message,
) async {
  try {
    await action();
  } on T {
    return;
  }
  throw StateError(message);
}

TerminalPaneConfiguration _configuration(List<_StateFakeSession> sessions) =>
    TerminalPaneConfiguration(
      sessionFactory:
          (
            TerminalSessionId id, {
            required void Function() onChanged,
            required void Function() onTerminated,
          }) {
            final _StateFakeSession session = _StateFakeSession(id);
            sessions.add(session);
            return session;
          },
      onChanged: () {},
      onExitRequested: () {},
    );

final class _StateFakeSession implements TerminalPaneSession {
  _StateFakeSession(this.id);

  @override
  final TerminalSessionId id;

  var live = false;
  var shutdownCount = 0;
  var failShutdown = false;
  var failProcessSnapshot = false;
  Completer<void>? shutdownBarrier;
  TerminalPaneProcessDisposition processDisposition =
      TerminalPaneProcessDisposition.idleShell;

  @override
  bool get isLive => live;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;

  @override
  TerminalPaneProcessSnapshot processSnapshot() {
    if (failProcessSnapshot) {
      throw StateError('injected process snapshot failure');
    }
    return !live
        ? TerminalPaneProcessSnapshot.nonLive(id)
        : processDisposition == TerminalPaneProcessDisposition.unavailable
        ? TerminalPaneProcessSnapshot.unavailable(sessionId: id)
        : TerminalPaneProcessSnapshot.available(
            sessionId: id,
            childProcessId: id.paneId.value,
            owningProcessGroup: id.paneId.value,
            foregroundProcessGroup:
                processDisposition ==
                    TerminalPaneProcessDisposition.foregroundProcess
                ? id.paneId.value + 1000
                : id.paneId.value,
            owningShellCommandActive:
                processDisposition ==
                TerminalPaneProcessDisposition.owningShellCommand,
          );
  }

  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();

  @override
  bool get bracketedPasteMode => false;

  @override
  bool get pasteInProgress => false;

  @override
  Future<void> start() async {
    live = true;
  }

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
    await shutdownBarrier?.future;
    live = false;
    if (failShutdown) {
      throw StateError('requested state fake shutdown failure');
    }
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}
