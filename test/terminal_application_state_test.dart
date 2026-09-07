import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalApplicationStateTests();

void runTerminalApplicationStateTests() {
  _testTypedIdentityValues();
  _testSplitTraversalAndLookup();
  _testSplitPlacementAndCollapse();
  _testSplitTopologyValidationAndBounds();
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
