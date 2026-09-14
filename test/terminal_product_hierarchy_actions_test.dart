import 'dart:async';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalProductHierarchyActionTests();

Future<void> runTerminalProductHierarchyActionTests() async {
  await _testCreationAndExistingMutations();
  await _testExplicitWorkingDirectoryCreation();
  await _testSerializationFailureAndDisposal();
  await _testAggregatePaneAvailabilityBound();
}

Future<void> _testExplicitWorkingDirectoryCreation() async {
  final _Harness harness = _Harness();
  await harness.createInitialWindow();
  final int tabs = await harness.coordinator.createTabsAtWorkingDirectories(
    const <String>['/private/tmp/first', '/private/tmp/second'],
  );
  final int windows = await harness.coordinator
      .createWindowsAtWorkingDirectories(const <String>['/private/tmp/third']);
  _expect(
    tabs == 2 &&
        windows == 1 &&
        harness.configurationWorkingDirectories.join('|') ==
            '/private/tmp/first|/private/tmp/second|/private/tmp/third' &&
        harness.sessions.values.every((_FakeSession session) => session.live),
    'folder requests create fresh started panes with exact cwd overrides',
  );
  harness.coordinator.dispose();
  _expect(
    await harness.coordinator.createTabsAtWorkingDirectories(const <String>[
          '/private/tmp/ignored',
        ]) ==
        0,
    'disposed folder creation fails closed before configuration or startup',
  );
  await harness.state.shutdown();
}

Future<void> _testCreationAndExistingMutations() async {
  final _Harness harness = _Harness();
  final TerminalWindowState initial = await harness.createInitialWindow();
  final PaneId firstPane = initial.selectedTab.focusedPaneId;
  final TerminalActionDispatcher dispatcher = harness.dispatcher();

  _expectEnabled(dispatcher, TerminalActionId.newWindow, true);
  _expectEnabled(dispatcher, TerminalActionId.newTab, true);
  _expectEnabled(dispatcher, TerminalActionId.splitPaneRight, true);
  _expectEnabled(dispatcher, TerminalActionId.togglePaneZoom, false);
  _expectEnabled(dispatcher, TerminalActionId.moveDividerRight, false);
  _expectEnabled(dispatcher, TerminalActionId.focusPaneRight, false);
  _expectEnabled(dispatcher, TerminalActionId.focusNextPane, false);
  _expectEnabled(dispatcher, TerminalActionId.selectNextTab, false);

  await _expectExecuted(dispatcher, TerminalActionId.splitPaneRight);
  final TerminalTabState firstTab = initial.selectedTab;
  final PaneId secondPane = firstTab.focusedPaneId;
  _expect(
    firstTab.splitTree.root is TerminalSplitBranch &&
        (firstTab.splitTree.root as TerminalSplitBranch).axis ==
            TerminalSplitAxis.horizontal &&
        secondPane != firstPane &&
        harness.sessions[secondPane]!.live &&
        harness.configurationSources.last == firstPane &&
        harness.reconcileCount == 1,
    'right split starts one inherited pane and reconciles once',
  );

  harness.focusablePaneDirections.add(TerminalPaneFocusDirection.left);
  _expectEnabled(dispatcher, TerminalActionId.focusPaneRight, false);
  _expectEnabled(dispatcher, TerminalActionId.focusPaneLeft, true);
  await _expectExecuted(dispatcher, TerminalActionId.focusPaneLeft);
  _expect(
    harness.focusedPaneDirections.single == TerminalPaneFocusDirection.left,
    'directional focus action invokes the matching projected mutation once',
  );

  harness.movableDividerDirections.add(TerminalSplitDividerDirection.right);
  _expectEnabled(dispatcher, TerminalActionId.moveDividerLeft, false);
  _expectEnabled(dispatcher, TerminalActionId.moveDividerRight, true);
  await _expectExecuted(dispatcher, TerminalActionId.moveDividerRight);
  _expect(
    harness.movedDividerDirections.join(',') ==
        TerminalSplitDividerDirection.right.toString(),
    'directional divider action invokes the matching geometry mutation once',
  );

  harness.state.resizeSplit(firstTab.id, firstTab.splitTree.root.id, 0.3);
  await _expectExecuted(dispatcher, TerminalActionId.equalizeSplits);
  _expect(
    (firstTab.splitTree.root as TerminalSplitBranch).fraction == 0.5,
    'equalize uses the existing model mutation',
  );
  await _expectExecuted(dispatcher, TerminalActionId.togglePaneZoom);
  _expect(
    firstTab.zoomedPaneId == secondPane,
    'zoom targets only the focused pane',
  );
  await _expectExecuted(dispatcher, TerminalActionId.togglePaneZoom);
  await _expectExecuted(dispatcher, TerminalActionId.focusPreviousPane);
  _expect(
    firstTab.focusedPaneId == firstPane && firstTab.zoomedPaneId == null,
    'focus traversal wraps through the selected split tree',
  );

  await _expectExecuted(dispatcher, TerminalActionId.splitPaneDown);
  _expect(
    harness.configurationSources.last == firstPane &&
        firstTab.focusedPaneId != firstPane &&
        harness.sessions[firstTab.focusedPaneId]!.live,
    'down split inherits from the previously focused pane',
  );

  await _expectExecuted(dispatcher, TerminalActionId.newTab);
  final TerminalTabId secondTab = initial.selectedTabId;
  _expect(
    secondTab != firstTab.id &&
        harness.configurationSources.last == firstTab.focusedPaneId &&
        harness.sessions[initial.selectedTab.focusedPaneId]!.live,
    'new tab starts and selects an inherited pane',
  );
  await _expectExecuted(dispatcher, TerminalActionId.selectPreviousTab);
  _expect(initial.selectedTabId == firstTab.id, 'previous tab selects exactly');
  await _expectExecuted(dispatcher, TerminalActionId.selectNextTab);
  _expect(initial.selectedTabId == secondTab, 'next tab selects exactly');

  final PaneId newWindowSource = initial.selectedTab.focusedPaneId;
  await _expectExecuted(dispatcher, TerminalActionId.newWindow);
  _expect(
    harness.state.windowCount == 2 &&
        harness.state.activeWindowId != initial.id &&
        harness.configurationSources.last == newWindowSource &&
        harness
            .sessions[harness.state.activeWindow!.selectedTab.focusedPaneId]!
            .live,
    'new window starts one inherited pane and activates its window',
  );
  _expect(
    harness.reconcileCount == 12 && harness.changedCount == 12,
    'every successful action projects and publishes exactly once',
  );
  await harness.state.shutdown();
}

Future<void> _testSerializationFailureAndDisposal() async {
  final _Harness harness = _Harness();
  await harness.createInitialWindow();
  final TerminalActionDispatcher dispatcher = harness.dispatcher();
  final Completer<void> startBarrier = Completer<void>();
  harness.nextStartBarrier = startBarrier;
  final Future<TerminalActionDispatchResult> first = dispatcher.dispatch(
    TerminalActionId.newTab,
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    (await dispatcher.dispatch(TerminalActionId.newWindow)).disposition ==
        TerminalActionDispatchDisposition.busy,
    'a second hierarchy mutation is busy while pane start is in flight',
  );
  startBarrier.complete();
  _expect(
    (await first).disposition == TerminalActionDispatchDisposition.executed &&
        harness.reconcileCount == 1,
    'the serialized mutation finishes with one projection',
  );

  final int panesBeforeFailure = harness.state.paneCount;
  harness.failNextStart = true;
  final TerminalActionDispatchResult failed = await dispatcher.dispatch(
    TerminalActionId.splitPaneRight,
  );
  _expect(
    failed.disposition == TerminalActionDispatchDisposition.failed &&
        harness.state.paneCount == panesBeforeFailure &&
        harness.reconcileCount == 2 &&
        harness.sessions.values.last.shutdownCount == 1,
    'failed pane start rolls logical state back and reconciles cleanup once',
  );

  harness.mutationAllowed = false;
  _expect(
    dispatcher
        .snapshotsForMenu(TerminalActionMenu.shell)
        .every((snapshot) => !snapshot.isEnabled),
    'an external close/quit transaction gates hierarchy mutations',
  );
  harness.mutationAllowed = true;

  harness.coordinator.dispose();
  _expect(
    dispatcher
        .snapshotsForMenu(TerminalActionMenu.shell)
        .every((snapshot) => !snapshot.isEnabled),
    'disposed coordinator fails every retained registration closed',
  );
  await harness.state.shutdown();
}

Future<void> _testAggregatePaneAvailabilityBound() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createInitialWindow();
  while (harness.state.paneCount <
      TerminalApplicationStateLimits.maximumTotalPanes) {
    await harness.state.splitPane(
      window.selectedTab.focusedPaneId,
      harness.configuration(window.selectedTab.focusedPaneId),
      axis: TerminalSplitAxis.horizontal,
    );
  }
  final TerminalActionDispatcher dispatcher = harness.dispatcher();
  for (final TerminalActionId id in <TerminalActionId>[
    TerminalActionId.newWindow,
    TerminalActionId.newTab,
    TerminalActionId.splitPaneRight,
    TerminalActionId.splitPaneDown,
  ]) {
    _expectEnabled(dispatcher, id, false);
  }
  _expect(
    harness.sessions.length ==
            TerminalApplicationStateLimits.maximumTotalPanes &&
        harness.reconcileCount == 0,
    'availability reaches the aggregate pane bound without projection',
  );
  await harness.state.shutdown();
}

final class _Harness {
  final TerminalApplicationState state = TerminalApplicationState();
  final Map<PaneId, _FakeSession> sessions = <PaneId, _FakeSession>{};
  final List<PaneId?> configurationSources = <PaneId?>[];
  final List<String> configurationWorkingDirectories = <String>[];
  late final TerminalProductHierarchyActionCoordinator coordinator =
      TerminalProductHierarchyActionCoordinator(
        state: state,
        configurationFactory: configuration,
        reconcile: () => reconcileCount++,
        canMoveDivider: movableDividerDirections.contains,
        moveDivider: (TerminalSplitDividerDirection direction) {
          movedDividerDirections.add(direction);
          return true;
        },
        canFocusPane: focusablePaneDirections.contains,
        focusPane: (TerminalPaneFocusDirection direction) {
          focusedPaneDirections.add(direction);
          return true;
        },
        canMutate: () => mutationAllowed,
        onChanged: () => changedCount++,
      );
  int reconcileCount = 0;
  int changedCount = 0;
  Completer<void>? nextStartBarrier;
  bool failNextStart = false;
  bool mutationAllowed = true;
  final Set<TerminalSplitDividerDirection> movableDividerDirections =
      <TerminalSplitDividerDirection>{};
  final List<TerminalSplitDividerDirection> movedDividerDirections =
      <TerminalSplitDividerDirection>[];
  final Set<TerminalPaneFocusDirection> focusablePaneDirections =
      <TerminalPaneFocusDirection>{};
  final List<TerminalPaneFocusDirection> focusedPaneDirections =
      <TerminalPaneFocusDirection>[];

  Future<TerminalWindowState> createInitialWindow() async {
    final TerminalWindowState window = await state.createWindow(
      configuration(null),
    );
    await state.paneForId(window.selectedTab.focusedPaneId)!.start();
    configurationSources.clear();
    return window;
  }

  TerminalActionDispatcher dispatcher() => TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: coordinator.registrations(),
  );

  TerminalPaneConfiguration configuration(
    PaneId? source, {
    String? workingDirectoryOverride,
  }) {
    configurationSources.add(source);
    if (workingDirectoryOverride != null) {
      configurationWorkingDirectories.add(workingDirectoryOverride);
    }
    return TerminalPaneConfiguration(
      sessionFactory:
          (
            TerminalSessionId id, {
            required void Function() onChanged,
            required void Function() onTerminated,
          }) {
            final _FakeSession session = _FakeSession(
              id,
              startBarrier: nextStartBarrier,
              failStart: failNextStart,
            );
            nextStartBarrier = null;
            failNextStart = false;
            sessions[id.paneId] = session;
            return session;
          },
      onChanged: () {},
      onExitRequested: () {},
    );
  }
}

final class _FakeSession implements TerminalPaneSession {
  _FakeSession(this.id, {this.startBarrier, this.failStart = false});

  @override
  final TerminalSessionId id;
  final Completer<void>? startBarrier;
  final bool failStart;
  bool live = false;
  int shutdownCount = 0;

  @override
  bool get isLive => live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalPaneProcessSnapshot processSnapshot() => live
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
  Future<void> start() async {
    await startBarrier?.future;
    if (failStart) throw StateError('injected pane start failure');
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
    live = false;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

Future<void> _expectExecuted(
  TerminalActionDispatcher dispatcher,
  TerminalActionId id,
) async {
  final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
  _expect(
    result.disposition == TerminalActionDispatchDisposition.executed,
    '${id.stableName} should execute: ${result.disposition}',
  );
}

void _expectEnabled(
  TerminalActionDispatcher dispatcher,
  TerminalActionId id,
  bool expected,
) {
  _expect(
    dispatcher.snapshot(id).isEnabled == expected,
    '${id.stableName} enabled state should be $expected',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
