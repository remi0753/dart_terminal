import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalApplicationStateTests();

Future<void> runTerminalApplicationStateTests() async {
  _testTypedIdentityValues();
  _testSplitTraversalAndLookup();
  _testSplitPlacementAndCollapse();
  _testSplitTopologyValidationAndBounds();
  await _testApplicationHierarchyFocusAndIndexes();
  await _testPaneRemovalAndOrderedShutdown();
  await _testApplicationLimitsAndDisposedState();
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

  @override
  bool get isLive => live;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;

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
