import 'dart:async';

import 'terminal_pane.dart';
import 'terminal_tab_metadata.dart';

/// Hard bounds for the UI-root application hierarchy.
abstract final class TerminalApplicationStateLimits {
  static const int maximumWindows = 32;
  static const int maximumTabsPerWindow = 64;
  static const int maximumPanesPerTab = 64;
  static const int maximumTotalPanes = 64;
  static const int maximumSplitNodesPerTab = maximumPanesPerTab * 2 - 1;
}

/// Stable application identity for one logical window.
final class TerminalWindowId {
  const TerminalWindowId(this.value) : assert(value > 0);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is TerminalWindowId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// Stable application identity for one logical tab.
final class TerminalTabId {
  const TerminalTabId(this.value) : assert(value > 0);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is TerminalTabId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// Stable identity for one node in a tab's split tree.
final class TerminalSplitNodeId {
  const TerminalSplitNodeId(this.value) : assert(value > 0);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is TerminalSplitNodeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

enum TerminalSplitAxis { horizontal, vertical }

enum TerminalSplitPlacement { before, after }

enum TerminalSplitDividerDirection { left, right, up, down }

enum TerminalPaneFocusDirection { left, right, up, down }

enum TerminalPaneFocusTraversal { previous, next }

/// Product role of one logical terminal window.
enum TerminalWindowRole { standard, quickTerminal }

/// Positive logical-point dimensions used to project a split tree.
final class TerminalSplitLayoutSize {
  TerminalSplitLayoutSize({required this.width, required this.height}) {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be finite and positive');
    }
    if (!height.isFinite || height <= 0) {
      throw ArgumentError.value(
        height,
        'height',
        'must be finite and positive',
      );
    }
  }

  final double width;
  final double height;
}

/// One pane's bounded logical-point rectangle in a projected split tree.
final class TerminalPaneLayoutRect {
  const TerminalPaneLayoutRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Geometry and child minima for one projected split branch.
final class TerminalSplitBranchLayout {
  const TerminalSplitBranchLayout({
    required this.nodeId,
    required this.axis,
    required this.dividerOffset,
    required this.firstExtent,
    required this.secondExtent,
    required this.firstMinimumExtent,
    required this.secondMinimumExtent,
  });

  final TerminalSplitNodeId nodeId;
  final TerminalSplitAxis axis;
  final double dividerOffset;
  final double firstExtent;
  final double secondExtent;
  final double firstMinimumExtent;
  final double secondMinimumExtent;
}

/// Complete immutable layout projection for one visible terminal tab.
final class TerminalSplitLayout {
  TerminalSplitLayout._({
    required Map<PaneId, TerminalPaneLayoutRect> panes,
    required Map<TerminalSplitNodeId, TerminalSplitBranchLayout> branches,
  }) : panes = Map<PaneId, TerminalPaneLayoutRect>.unmodifiable(panes),
       branches =
           Map<TerminalSplitNodeId, TerminalSplitBranchLayout>.unmodifiable(
             branches,
           );

  final Map<PaneId, TerminalPaneLayoutRect> panes;
  final Map<TerminalSplitNodeId, TerminalSplitBranchLayout> branches;
}

/// An immutable node in a binary terminal split tree.
sealed class TerminalSplitNode {
  const TerminalSplitNode(this.id);

  final TerminalSplitNodeId id;
}

/// A split-tree leaf referring to exactly one application-owned pane.
final class TerminalSplitLeaf extends TerminalSplitNode {
  const TerminalSplitLeaf({
    required TerminalSplitNodeId id,
    required this.paneId,
  }) : super(id);

  final PaneId paneId;
}

/// A split-tree branch whose [fraction] is the first child's layout share.
final class TerminalSplitBranch extends TerminalSplitNode {
  TerminalSplitBranch({
    required TerminalSplitNodeId id,
    required this.axis,
    required this.fraction,
    required this.first,
    required this.second,
  }) : super(id) {
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'must be finite and strictly between zero and one',
      );
    }
  }

  final TerminalSplitAxis axis;
  final double fraction;
  final TerminalSplitNode first;
  final TerminalSplitNode second;
}

/// Immutable, validated topology for all panes in one terminal tab.
final class TerminalSplitTree {
  factory TerminalSplitTree({required TerminalSplitNode root}) {
    final _TerminalSplitTreeInventory inventory = _inventory(root);
    return TerminalSplitTree._(
      root,
      nodeIds: inventory.nodeIds,
      paneIds: inventory.paneIds,
    );
  }

  factory TerminalSplitTree.single({
    required TerminalSplitNodeId nodeId,
    required PaneId paneId,
  }) => TerminalSplitTree(
    root: TerminalSplitLeaf(id: nodeId, paneId: paneId),
  );

  TerminalSplitTree._(
    this.root, {
    required List<TerminalSplitNodeId> nodeIds,
    required List<PaneId> paneIds,
  }) : nodeIds = List<TerminalSplitNodeId>.unmodifiable(nodeIds),
       paneIds = List<PaneId>.unmodifiable(paneIds);

  final TerminalSplitNode root;

  /// Node identities in deterministic pre-order.
  final List<TerminalSplitNodeId> nodeIds;

  /// Pane identities in deterministic first-to-second visual order.
  final List<PaneId> paneIds;

  int get paneCount => paneIds.length;
  int get nodeCount => nodeIds.length;

  bool containsPane(PaneId paneId) => paneIds.contains(paneId);

  TerminalSplitLeaf? leafForPane(PaneId paneId) {
    final List<TerminalSplitNode> pending = <TerminalSplitNode>[root];
    while (pending.isNotEmpty) {
      final TerminalSplitNode node = pending.removeLast();
      switch (node) {
        case TerminalSplitLeaf():
          if (node.paneId == paneId) {
            return node;
          }
        case TerminalSplitBranch():
          pending
            ..add(node.second)
            ..add(node.first);
      }
    }
    return null;
  }

  TerminalSplitNode? nodeForId(TerminalSplitNodeId nodeId) {
    final List<TerminalSplitNode> pending = <TerminalSplitNode>[root];
    while (pending.isNotEmpty) {
      final TerminalSplitNode node = pending.removeLast();
      if (node.id == nodeId) {
        return node;
      }
      if (node case TerminalSplitBranch()) {
        pending
          ..add(node.second)
          ..add(node.first);
      }
    }
    return null;
  }

  TerminalSplitTree splitPane({
    required PaneId targetPaneId,
    required PaneId newPaneId,
    required TerminalSplitNodeId branchNodeId,
    required TerminalSplitNodeId newLeafNodeId,
    required TerminalSplitAxis axis,
    TerminalSplitPlacement placement = TerminalSplitPlacement.after,
    double fraction = 0.5,
  }) {
    if (!containsPane(targetPaneId)) {
      throw StateError('pane $targetPaneId is not in this split tree');
    }
    if (containsPane(newPaneId)) {
      throw StateError('pane $newPaneId is already in this split tree');
    }
    if (paneCount >= TerminalApplicationStateLimits.maximumPanesPerTab) {
      throw StateError('terminal tab pane limit is exhausted');
    }
    if (branchNodeId == newLeafNodeId ||
        nodeIds.contains(branchNodeId) ||
        nodeIds.contains(newLeafNodeId)) {
      throw StateError('new split node identities must be unique');
    }
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'must be finite and strictly between zero and one',
      );
    }

    final TerminalSplitNode replacement = _replacePane(root, targetPaneId, (
      TerminalSplitLeaf existing,
    ) {
      final TerminalSplitLeaf added = TerminalSplitLeaf(
        id: newLeafNodeId,
        paneId: newPaneId,
      );
      return TerminalSplitBranch(
        id: branchNodeId,
        axis: axis,
        fraction: fraction,
        first: placement == TerminalSplitPlacement.before ? added : existing,
        second: placement == TerminalSplitPlacement.before ? existing : added,
      );
    });
    return TerminalSplitTree(root: replacement);
  }

  TerminalSplitTree resizeBranch(TerminalSplitNodeId nodeId, double fraction) {
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'must be finite and strictly between zero and one',
      );
    }
    final TerminalSplitNode? target = nodeForId(nodeId);
    if (target == null) {
      throw StateError('unknown split node $nodeId');
    }
    if (target is! TerminalSplitBranch) {
      throw StateError('split node $nodeId is not a branch');
    }
    return TerminalSplitTree(
      root: _replaceNode(root, nodeId, (TerminalSplitNode node) {
        final TerminalSplitBranch branch = node as TerminalSplitBranch;
        return TerminalSplitBranch(
          id: branch.id,
          axis: branch.axis,
          fraction: fraction,
          first: branch.first,
          second: branch.second,
        );
      }),
    );
  }

  TerminalSplitTree equalize({TerminalSplitNodeId? subtreeRootId}) {
    final TerminalSplitNodeId targetId = subtreeRootId ?? root.id;
    final TerminalSplitNode? target = nodeForId(targetId);
    if (target == null) {
      throw StateError('unknown split node $targetId');
    }
    if (target is! TerminalSplitBranch) {
      throw StateError('split node $targetId is not a branch');
    }
    return TerminalSplitTree(
      root: _replaceNode(root, targetId, _equalizedNode),
    );
  }

  PaneId traversePane(
    PaneId current, {
    required TerminalPaneFocusTraversal direction,
  }) {
    final int index = paneIds.indexOf(current);
    if (index < 0) {
      throw StateError('pane $current is not in this split tree');
    }
    final int offset = direction == TerminalPaneFocusTraversal.next ? 1 : -1;
    return paneIds[(index + offset) % paneIds.length];
  }

  TerminalSplitLayout layout({
    required TerminalSplitLayoutSize availableSize,
    required TerminalSplitLayoutSize cellSize,
    double dividerThickness = 1,
    PaneId? zoomedPaneId,
  }) {
    if (!dividerThickness.isFinite || dividerThickness < 0) {
      throw ArgumentError.value(
        dividerThickness,
        'dividerThickness',
        'must be finite and non-negative',
      );
    }
    if (zoomedPaneId != null && !containsPane(zoomedPaneId)) {
      throw StateError('pane $zoomedPaneId is not in this split tree');
    }
    final _TerminalSplitMinimumSize minimum = zoomedPaneId == null
        ? _minimumSize(root, cellSize, dividerThickness)
        : _TerminalSplitMinimumSize(
            width: cellSize.width,
            height: cellSize.height,
          );
    if (minimum.width > availableSize.width ||
        minimum.height > availableSize.height) {
      throw StateError(
        'split tree requires at least ${minimum.width}x${minimum.height} '
        'logical points but only ${availableSize.width}x'
        '${availableSize.height} are available',
      );
    }
    final Map<PaneId, TerminalPaneLayoutRect> panes =
        <PaneId, TerminalPaneLayoutRect>{};
    final Map<TerminalSplitNodeId, TerminalSplitBranchLayout> branches =
        <TerminalSplitNodeId, TerminalSplitBranchLayout>{};
    if (zoomedPaneId != null) {
      panes[zoomedPaneId] = TerminalPaneLayoutRect(
        left: 0,
        top: 0,
        width: availableSize.width,
        height: availableSize.height,
      );
    } else {
      _layoutNode(
        root,
        const _TerminalSplitOrigin(left: 0, top: 0),
        availableSize,
        cellSize,
        dividerThickness,
        panes,
        branches,
      );
    }
    return TerminalSplitLayout._(panes: panes, branches: branches);
  }

  /// Returns a tree without [paneId], or `null` when it was the only leaf.
  TerminalSplitTree? removePane(PaneId paneId) {
    if (!containsPane(paneId)) {
      throw StateError('pane $paneId is not in this split tree');
    }
    final TerminalSplitNode? replacement = _removePane(root, paneId);
    return replacement == null ? null : TerminalSplitTree(root: replacement);
  }

  static _TerminalSplitTreeInventory _inventory(TerminalSplitNode root) {
    final Set<TerminalSplitNodeId> uniqueNodeIds = <TerminalSplitNodeId>{};
    final Set<PaneId> uniquePaneIds = <PaneId>{};
    final List<TerminalSplitNodeId> nodeIds = <TerminalSplitNodeId>[];
    final List<PaneId> paneIds = <PaneId>[];
    final List<TerminalSplitNode> pending = <TerminalSplitNode>[root];
    while (pending.isNotEmpty) {
      final TerminalSplitNode node = pending.removeLast();
      if (node.id.value <= 0) {
        throw ArgumentError.value(node.id.value, 'node.id', 'must be positive');
      }
      if (!uniqueNodeIds.add(node.id)) {
        throw StateError('duplicate split node identity ${node.id}');
      }
      nodeIds.add(node.id);
      if (nodeIds.length >
          TerminalApplicationStateLimits.maximumSplitNodesPerTab) {
        throw StateError('terminal tab split-node limit is exhausted');
      }
      switch (node) {
        case TerminalSplitLeaf():
          if (node.paneId.value <= 0) {
            throw ArgumentError.value(
              node.paneId.value,
              'paneId',
              'must be positive',
            );
          }
          if (!uniquePaneIds.add(node.paneId)) {
            throw StateError('duplicate pane identity ${node.paneId}');
          }
          paneIds.add(node.paneId);
          if (paneIds.length >
              TerminalApplicationStateLimits.maximumPanesPerTab) {
            throw StateError('terminal tab pane limit is exhausted');
          }
        case TerminalSplitBranch():
          if (!node.fraction.isFinite ||
              node.fraction <= 0 ||
              node.fraction >= 1) {
            throw StateError('split node ${node.id} has an invalid fraction');
          }
          pending
            ..add(node.second)
            ..add(node.first);
      }
    }
    if (paneIds.isEmpty) {
      throw StateError('terminal split tree must contain a pane');
    }
    return _TerminalSplitTreeInventory(nodeIds: nodeIds, paneIds: paneIds);
  }

  static TerminalSplitNode _replacePane(
    TerminalSplitNode node,
    PaneId targetPaneId,
    TerminalSplitNode Function(TerminalSplitLeaf leaf) replace,
  ) => switch (node) {
    TerminalSplitLeaf() => node.paneId == targetPaneId ? replace(node) : node,
    TerminalSplitBranch() => TerminalSplitBranch(
      id: node.id,
      axis: node.axis,
      fraction: node.fraction,
      first: _replacePane(node.first, targetPaneId, replace),
      second: _replacePane(node.second, targetPaneId, replace),
    ),
  };

  static TerminalSplitNode _replaceNode(
    TerminalSplitNode node,
    TerminalSplitNodeId targetId,
    TerminalSplitNode Function(TerminalSplitNode node) replace,
  ) {
    if (node.id == targetId) {
      return replace(node);
    }
    return switch (node) {
      TerminalSplitLeaf() => node,
      TerminalSplitBranch() => TerminalSplitBranch(
        id: node.id,
        axis: node.axis,
        fraction: node.fraction,
        first: _replaceNode(node.first, targetId, replace),
        second: _replaceNode(node.second, targetId, replace),
      ),
    };
  }

  static TerminalSplitNode _equalizedNode(TerminalSplitNode node) =>
      switch (node) {
        TerminalSplitLeaf() => node,
        TerminalSplitBranch() => TerminalSplitBranch(
          id: node.id,
          axis: node.axis,
          fraction: 0.5,
          first: _equalizedNode(node.first),
          second: _equalizedNode(node.second),
        ),
      };

  static _TerminalSplitMinimumSize _minimumSize(
    TerminalSplitNode node,
    TerminalSplitLayoutSize cellSize,
    double dividerThickness,
  ) => switch (node) {
    TerminalSplitLeaf() => _TerminalSplitMinimumSize(
      width: cellSize.width,
      height: cellSize.height,
    ),
    TerminalSplitBranch() => _combineMinimumSizes(
      node.axis,
      _minimumSize(node.first, cellSize, dividerThickness),
      _minimumSize(node.second, cellSize, dividerThickness),
      dividerThickness,
    ),
  };

  static _TerminalSplitMinimumSize _combineMinimumSizes(
    TerminalSplitAxis axis,
    _TerminalSplitMinimumSize first,
    _TerminalSplitMinimumSize second,
    double dividerThickness,
  ) => switch (axis) {
    TerminalSplitAxis.horizontal => _TerminalSplitMinimumSize(
      width: first.width + dividerThickness + second.width,
      height: first.height > second.height ? first.height : second.height,
    ),
    TerminalSplitAxis.vertical => _TerminalSplitMinimumSize(
      width: first.width > second.width ? first.width : second.width,
      height: first.height + dividerThickness + second.height,
    ),
  };

  static void _layoutNode(
    TerminalSplitNode node,
    _TerminalSplitOrigin origin,
    TerminalSplitLayoutSize size,
    TerminalSplitLayoutSize cellSize,
    double dividerThickness,
    Map<PaneId, TerminalPaneLayoutRect> panes,
    Map<TerminalSplitNodeId, TerminalSplitBranchLayout> branches,
  ) {
    switch (node) {
      case TerminalSplitLeaf():
        panes[node.paneId] = TerminalPaneLayoutRect(
          left: origin.left,
          top: origin.top,
          width: size.width,
          height: size.height,
        );
      case TerminalSplitBranch():
        final _TerminalSplitMinimumSize firstMinimum = _minimumSize(
          node.first,
          cellSize,
          dividerThickness,
        );
        final _TerminalSplitMinimumSize secondMinimum = _minimumSize(
          node.second,
          cellSize,
          dividerThickness,
        );
        final bool horizontal = node.axis == TerminalSplitAxis.horizontal;
        final double axisExtent = horizontal ? size.width : size.height;
        final double usableExtent = axisExtent - dividerThickness;
        final double firstMinimumExtent = horizontal
            ? firstMinimum.width
            : firstMinimum.height;
        final double secondMinimumExtent = horizontal
            ? secondMinimum.width
            : secondMinimum.height;
        final double desiredFirstExtent = usableExtent * node.fraction;
        final double firstExtent = desiredFirstExtent.clamp(
          firstMinimumExtent,
          usableExtent - secondMinimumExtent,
        );
        final double secondExtent = usableExtent - firstExtent;
        branches[node.id] = TerminalSplitBranchLayout(
          nodeId: node.id,
          axis: node.axis,
          dividerOffset: firstExtent,
          firstExtent: firstExtent,
          secondExtent: secondExtent,
          firstMinimumExtent: firstMinimumExtent,
          secondMinimumExtent: secondMinimumExtent,
        );
        _layoutNode(
          node.first,
          origin,
          TerminalSplitLayoutSize(
            width: horizontal ? firstExtent : size.width,
            height: horizontal ? size.height : firstExtent,
          ),
          cellSize,
          dividerThickness,
          panes,
          branches,
        );
        _layoutNode(
          node.second,
          _TerminalSplitOrigin(
            left: horizontal
                ? origin.left + firstExtent + dividerThickness
                : origin.left,
            top: horizontal
                ? origin.top
                : origin.top + firstExtent + dividerThickness,
          ),
          TerminalSplitLayoutSize(
            width: horizontal ? secondExtent : size.width,
            height: horizontal ? size.height : secondExtent,
          ),
          cellSize,
          dividerThickness,
          panes,
          branches,
        );
    }
  }

  static TerminalSplitNode? _removePane(
    TerminalSplitNode node,
    PaneId paneId,
  ) => switch (node) {
    TerminalSplitLeaf() => node.paneId == paneId ? null : node,
    TerminalSplitBranch() => _removeFromBranch(node, paneId),
  };

  static TerminalSplitNode? _removeFromBranch(
    TerminalSplitBranch branch,
    PaneId paneId,
  ) {
    final TerminalSplitNode? first = _removePane(branch.first, paneId);
    final TerminalSplitNode? second = _removePane(branch.second, paneId);
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    if (identical(first, branch.first) && identical(second, branch.second)) {
      return branch;
    }
    return TerminalSplitBranch(
      id: branch.id,
      axis: branch.axis,
      fraction: branch.fraction,
      first: first,
      second: second,
    );
  }
}

/// Callbacks and factory needed to create one application-owned pane.
final class TerminalPaneConfiguration {
  const TerminalPaneConfiguration({
    required this.sessionFactory,
    required this.onChanged,
    required this.onExitRequested,
    this.lifecycleObserver,
    this.exitObserver,
  });

  final TerminalPaneSessionFactory sessionFactory;
  final void Function() onChanged;
  final void Function() onExitRequested;
  final TerminalPaneLifecycleObserver? lifecycleObserver;
  final TerminalPaneExitObserver? exitObserver;
}

/// Stable reverse lookup for one pane's owning window and tab.
final class TerminalPaneLocation {
  const TerminalPaneLocation({required this.windowId, required this.tabId});

  final TerminalWindowId windowId;
  final TerminalTabId tabId;

  @override
  bool operator ==(Object other) =>
      other is TerminalPaneLocation &&
      other.windowId == windowId &&
      other.tabId == tabId;

  @override
  int get hashCode => Object.hash(windowId, tabId);
}

/// Application-owned state for one tab and its non-empty split tree.
final class TerminalTabState {
  TerminalTabState._({
    required this.id,
    required TerminalSplitTree splitTree,
    required PaneId focusedPaneId,
  }) : _splitTree = splitTree,
       _focusedPaneId = focusedPaneId,
       _zoomedPaneId = null,
       _customTitle = null,
       _color = null;

  final TerminalTabId id;
  TerminalSplitTree _splitTree;
  PaneId _focusedPaneId;
  PaneId? _zoomedPaneId;
  String? _customTitle;
  TerminalTabColor? _color;

  TerminalSplitTree get splitTree => _splitTree;
  PaneId get focusedPaneId => _focusedPaneId;
  PaneId? get zoomedPaneId => _zoomedPaneId;
  String? get customTitle => _customTitle;
  TerminalTabColor? get color => _color;
  bool get isZoomed => _zoomedPaneId != null;
  List<PaneId> get paneIds => _splitTree.paneIds;
}

/// Application-owned state for one window and its non-empty ordered tabs.
final class TerminalWindowState {
  TerminalWindowState._({
    required this.id,
    required TerminalTabState initialTab,
    required this.role,
  }) : _selectedTabId = initialTab.id {
    _tabs[initialTab.id] = initialTab;
  }

  final TerminalWindowId id;
  final TerminalWindowRole role;
  final Map<TerminalTabId, TerminalTabState> _tabs =
      <TerminalTabId, TerminalTabState>{};
  TerminalTabId _selectedTabId;

  List<TerminalTabState> get tabs =>
      List<TerminalTabState>.unmodifiable(_tabs.values);
  List<TerminalTabId> get tabIds =>
      List<TerminalTabId>.unmodifiable(_tabs.keys);
  TerminalTabId get selectedTabId => _selectedTabId;
  TerminalTabState get selectedTab => _tabs[_selectedTabId]!;

  TerminalTabState? tabForId(TerminalTabId tabId) => _tabs[tabId];
}

/// Result of one pane teardown and its structural collapse.
final class TerminalPaneRemovalResult {
  const TerminalPaneRemovalResult({
    required this.paneId,
    required this.tabId,
    required this.windowId,
    required this.removedTab,
    required this.removedWindow,
    required this.shutdown,
  });

  final PaneId paneId;
  final TerminalTabId tabId;
  final TerminalWindowId windowId;
  final bool removedTab;
  final bool removedWindow;
  final TerminalPaneSessionShutdownResult shutdown;
}

/// Sole owner of the logical application/window/tab/split/pane hierarchy.
final class TerminalApplicationState {
  TerminalApplicationState({
    TerminalPaneOwner? paneOwner,
    int initialWindowId = 0,
    int initialTabId = 0,
    int initialSplitNodeId = 0,
  }) : _paneOwner = paneOwner ?? TerminalPaneOwner(),
       _nextWindowId = _checkedInitialIdentity(
         initialWindowId,
         'initialWindowId',
       ),
       _nextTabId = _checkedInitialIdentity(initialTabId, 'initialTabId'),
       _nextSplitNodeId = _checkedInitialIdentity(
         initialSplitNodeId,
         'initialSplitNodeId',
       ) {
    if (_paneOwner.livePaneCount != 0) {
      throw ArgumentError.value(
        _paneOwner.livePaneCount,
        'paneOwner',
        'must not already own panes',
      );
    }
  }

  static const int maximumIdentityValue = 0x7fffffffffffffff;

  final TerminalPaneOwner _paneOwner;
  final Map<TerminalWindowId, TerminalWindowState> _windows =
      <TerminalWindowId, TerminalWindowState>{};
  final Map<TerminalTabId, TerminalTabState> _tabs =
      <TerminalTabId, TerminalTabState>{};
  final Map<PaneId, TerminalPane> _panes = <PaneId, TerminalPane>{};
  final Map<PaneId, TerminalPaneLocation> _paneLocations =
      <PaneId, TerminalPaneLocation>{};

  int _nextWindowId;
  int _nextTabId;
  int _nextSplitNodeId;
  TerminalWindowId? _activeWindowId;
  bool _mutationInProgress = false;
  Completer<void>? _mutationCompletion;
  bool _disposed = false;
  Future<TerminalPaneOwnerShutdownResult>? _shutdownFuture;
  TerminalPaneOwnerShutdownResult? _shutdownResult;

  List<TerminalWindowState> get windows =>
      List<TerminalWindowState>.unmodifiable(_windows.values);
  List<TerminalWindowId> get windowIds =>
      List<TerminalWindowId>.unmodifiable(_windows.keys);
  List<PaneId> get paneIds => List<PaneId>.unmodifiable(_panes.keys);
  int get windowCount => _windows.length;
  int get tabCount => _tabs.length;
  int get paneCount => _panes.length;
  TerminalWindowId? get activeWindowId => _activeWindowId;
  TerminalWindowState? get activeWindow =>
      _activeWindowId == null ? null : _windows[_activeWindowId];
  TerminalWindowState? get quickTerminalWindow {
    for (final TerminalWindowState window in _windows.values) {
      if (window.role == TerminalWindowRole.quickTerminal) return window;
    }
    return null;
  }

  TerminalPaneOwnerShutdownResult? get shutdownResult => _shutdownResult;
  bool get isDisposed => _disposed;
  bool get mutationInProgress => _mutationInProgress;

  /// Completes after the current hierarchy transaction, including failed ones.
  /// Consumers must recheck liveness and admission after awaiting this boundary.
  Future<void> get mutationSettled =>
      _mutationCompletion?.future ?? Future<void>.value();

  TerminalWindowState? windowForId(TerminalWindowId windowId) =>
      _windows[windowId];

  TerminalTabState? tabForId(TerminalTabId tabId) => _tabs[tabId];

  TerminalPane? paneForId(PaneId paneId) => _panes[paneId];

  TerminalPaneLocation? locationForPane(PaneId paneId) =>
      _paneLocations[paneId];

  /// Content-free hierarchy identity for product integration diagnostics.
  String machineLineForPane(PaneId paneId) {
    validate();
    final TerminalPaneLocation location = _requirePaneLocation(paneId);
    final TerminalWindowState window = _requireWindow(location.windowId);
    final TerminalTabState tab = _requireTab(location.tabId);
    final TerminalSplitLeaf leaf = tab._splitTree.leafForPane(paneId)!;
    final TerminalPane pane = _panes[paneId]!;
    return 'TERMINAL_APPLICATION_MODEL windows=$windowCount tabs=$tabCount '
        'panes=$paneCount window=${window.id} tab=${tab.id} '
        'split_leaf=${leaf.id} pane=$paneId session=${pane.sessionId} '
        'active=${_activeWindowId == window.id} '
        'selected=${window._selectedTabId == tab.id} '
        'focused=${tab._focusedPaneId == paneId}';
  }

  Future<TerminalWindowState> createWindow(
    TerminalPaneConfiguration configuration, {
    TerminalWindowRole role = TerminalWindowRole.standard,
  }) async {
    _beginMutation();
    TerminalPane? pane;
    try {
      if (_windows.length >= TerminalApplicationStateLimits.maximumWindows) {
        throw StateError('terminal application window limit is exhausted');
      }
      if (role == TerminalWindowRole.quickTerminal &&
          quickTerminalWindow != null) {
        throw StateError('terminal application already has a Quick Terminal');
      }
      _requirePaneCapacity();
      final TerminalWindowId windowId = TerminalWindowId(
        _nextIdentity(_nextWindowId, count: 1, name: 'window'),
      );
      final TerminalTabId tabId = TerminalTabId(
        _nextIdentity(_nextTabId, count: 1, name: 'tab'),
      );
      final TerminalSplitNodeId leafId = TerminalSplitNodeId(
        _nextIdentity(_nextSplitNodeId, count: 1, name: 'split node'),
      );
      pane = _createPane(configuration);
      final TerminalTabState tab = TerminalTabState._(
        id: tabId,
        splitTree: TerminalSplitTree.single(nodeId: leafId, paneId: pane.id),
        focusedPaneId: pane.id,
      );
      final TerminalWindowState window = TerminalWindowState._(
        id: windowId,
        initialTab: tab,
        role: role,
      );
      _nextWindowId = windowId.value;
      _nextTabId = tabId.value;
      _nextSplitNodeId = leafId.value;
      _windows[windowId] = window;
      _tabs[tabId] = tab;
      _indexPane(pane, windowId: windowId, tabId: tabId);
      _activeWindowId = windowId;
      validate();
      return window;
    } on Object {
      if (pane != null && !_panes.containsKey(pane.id)) {
        await _paneOwner.disposePane(pane);
      }
      rethrow;
    } finally {
      _endMutation();
    }
  }

  Future<TerminalTabState> createTab(
    TerminalWindowId windowId,
    TerminalPaneConfiguration configuration,
  ) async {
    _beginMutation();
    TerminalPane? pane;
    try {
      final TerminalWindowState window = _requireWindow(windowId);
      if (window.role == TerminalWindowRole.quickTerminal) {
        throw StateError('Quick Terminal does not support tabs on macOS');
      }
      if (window._tabs.length >=
          TerminalApplicationStateLimits.maximumTabsPerWindow) {
        throw StateError('terminal window tab limit is exhausted');
      }
      _requirePaneCapacity();
      final TerminalTabId tabId = TerminalTabId(
        _nextIdentity(_nextTabId, count: 1, name: 'tab'),
      );
      final TerminalSplitNodeId leafId = TerminalSplitNodeId(
        _nextIdentity(_nextSplitNodeId, count: 1, name: 'split node'),
      );
      pane = _createPane(configuration);
      final TerminalTabState tab = TerminalTabState._(
        id: tabId,
        splitTree: TerminalSplitTree.single(nodeId: leafId, paneId: pane.id),
        focusedPaneId: pane.id,
      );
      _nextTabId = tabId.value;
      _nextSplitNodeId = leafId.value;
      window._tabs[tabId] = tab;
      window._selectedTabId = tabId;
      _tabs[tabId] = tab;
      _indexPane(pane, windowId: windowId, tabId: tabId);
      _activeWindowId = windowId;
      validate();
      return tab;
    } on Object {
      if (pane != null && !_panes.containsKey(pane.id)) {
        await _paneOwner.disposePane(pane);
      }
      rethrow;
    } finally {
      _endMutation();
    }
  }

  Future<TerminalPane> splitPane(
    PaneId targetPaneId,
    TerminalPaneConfiguration configuration, {
    required TerminalSplitAxis axis,
    TerminalSplitPlacement placement = TerminalSplitPlacement.after,
    double fraction = 0.5,
  }) async {
    _beginMutation();
    TerminalPane? pane;
    try {
      final TerminalPaneLocation location = _requirePaneLocation(targetPaneId);
      final TerminalWindowState window = _requireWindow(location.windowId);
      final TerminalTabState tab = _requireTab(location.tabId);
      if (tab._splitTree.paneCount >=
          TerminalApplicationStateLimits.maximumPanesPerTab) {
        throw StateError('terminal tab pane limit is exhausted');
      }
      _requirePaneCapacity();
      if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
        throw ArgumentError.value(
          fraction,
          'fraction',
          'must be finite and strictly between zero and one',
        );
      }
      final int firstNodeValue = _nextIdentity(
        _nextSplitNodeId,
        count: 2,
        name: 'split node',
      );
      final TerminalSplitNodeId branchId = TerminalSplitNodeId(firstNodeValue);
      final TerminalSplitNodeId leafId = TerminalSplitNodeId(
        firstNodeValue + 1,
      );
      pane = _createPane(configuration);
      final TerminalSplitTree replacement = tab._splitTree.splitPane(
        targetPaneId: targetPaneId,
        newPaneId: pane.id,
        branchNodeId: branchId,
        newLeafNodeId: leafId,
        axis: axis,
        placement: placement,
        fraction: fraction,
      );
      _nextSplitNodeId = leafId.value;
      tab
        .._splitTree = replacement
        .._focusedPaneId = pane.id
        .._zoomedPaneId = null;
      window._selectedTabId = tab.id;
      _indexPane(pane, windowId: window.id, tabId: tab.id);
      _activeWindowId = window.id;
      validate();
      return pane;
    } on Object {
      if (pane != null && !_panes.containsKey(pane.id)) {
        await _paneOwner.disposePane(pane);
      }
      rethrow;
    } finally {
      _endMutation();
    }
  }

  void selectTab(TerminalWindowId windowId, TerminalTabId tabId) {
    _ensureCanMutate();
    final TerminalWindowState window = _requireWindow(windowId);
    if (!window._tabs.containsKey(tabId)) {
      throw StateError('tab $tabId does not belong to window $windowId');
    }
    window._selectedTabId = tabId;
    _activeWindowId = windowId;
    validate();
  }

  void activateWindow(TerminalWindowId windowId) {
    _ensureCanMutate();
    _requireWindow(windowId);
    _activeWindowId = windowId;
    validate();
  }

  /// Sets a bounded user-facing tab title, or clears the override with null.
  bool renameTab(TerminalTabId tabId, String? title) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    if (title != null && !TerminalTabMetadataPolicy.isSafeCustomTitle(title)) {
      throw ArgumentError.value(
        title,
        'title',
        'must be non-empty safe text within '
            '${TerminalTabMetadataLimits.maximumCustomTitleUtf8Bytes} UTF-8 bytes',
      );
    }
    if (tab._customTitle == title) return false;
    tab._customTitle = title;
    validate();
    return true;
  }

  /// Sets a native tab marker color, or clears it with null.
  bool setTabColor(TerminalTabId tabId, TerminalTabColor? color) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    if (tab._color == color) return false;
    tab._color = color;
    validate();
    return true;
  }

  void focusPane(TerminalTabId tabId, PaneId paneId) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    if (!tab._splitTree.containsPane(paneId)) {
      throw StateError('pane $paneId does not belong to tab $tabId');
    }
    final TerminalPaneLocation location = _requirePaneLocation(paneId);
    final TerminalWindowState window = _requireWindow(location.windowId);
    if (tab._focusedPaneId != paneId) {
      tab
        .._focusedPaneId = paneId
        .._zoomedPaneId = null;
    }
    window._selectedTabId = tabId;
    _activeWindowId = window.id;
    validate();
  }

  void resizeSplit(
    TerminalTabId tabId,
    TerminalSplitNodeId nodeId,
    double fraction,
  ) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    tab._splitTree = tab._splitTree.resizeBranch(nodeId, fraction);
    validate();
  }

  void equalizeSplits(
    TerminalTabId tabId, {
    TerminalSplitNodeId? subtreeRootId,
  }) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    tab._splitTree = tab._splitTree.equalize(subtreeRootId: subtreeRootId);
    validate();
  }

  void setPaneZoom(TerminalTabId tabId, PaneId? paneId) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    if (paneId != null) {
      if (!tab._splitTree.containsPane(paneId)) {
        throw StateError('pane $paneId does not belong to tab $tabId');
      }
      if (tab._focusedPaneId != paneId) {
        throw StateError('only the focused pane may be zoomed');
      }
    }
    tab._zoomedPaneId = paneId;
    validate();
  }

  PaneId traversePaneFocus(
    TerminalTabId tabId, {
    required TerminalPaneFocusTraversal direction,
  }) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    final PaneId focused = tab._focusedPaneId;
    if (tab._zoomedPaneId != null) {
      return focused;
    }
    final PaneId next = tab._splitTree.traversePane(
      focused,
      direction: direction,
    );
    focusPane(tabId, next);
    return next;
  }

  Future<TerminalPaneRemovalResult> removePane(PaneId paneId) async {
    _beginMutation();
    try {
      final TerminalPaneLocation location = _requirePaneLocation(paneId);
      final TerminalPane pane = _panes[paneId]!;
      final TerminalWindowState window = _requireWindow(location.windowId);
      final TerminalTabState tab = _requireTab(location.tabId);
      final List<PaneId> previousPaneIds = tab._splitTree.paneIds;
      final int removedPaneIndex = previousPaneIds.indexOf(paneId);
      final TerminalSplitTree? replacement = tab._splitTree.removePane(paneId);
      final TerminalPaneSessionShutdownResult shutdown = await _paneOwner
          .disposePane(pane);

      _panes.remove(paneId);
      _paneLocations.remove(paneId);
      var removedTab = false;
      var removedWindow = false;
      if (replacement != null) {
        tab._splitTree = replacement;
        if (tab._focusedPaneId == paneId) {
          final int focusIndex = removedPaneIndex < replacement.paneIds.length
              ? removedPaneIndex
              : replacement.paneIds.length - 1;
          tab._focusedPaneId = replacement.paneIds[focusIndex];
        }
        if (tab._zoomedPaneId == paneId) {
          tab._zoomedPaneId = null;
        }
      } else {
        removedTab = true;
        final List<TerminalTabId> previousTabIds = window.tabIds;
        final int removedTabIndex = previousTabIds.indexOf(tab.id);
        window._tabs.remove(tab.id);
        _tabs.remove(tab.id);
        if (window._tabs.isEmpty) {
          removedWindow = true;
          final List<TerminalWindowId> previousWindowIds = windowIds;
          final int removedWindowIndex = previousWindowIds.indexOf(window.id);
          _windows.remove(window.id);
          if (_activeWindowId == window.id) {
            _activeWindowId = _neighborAt(
              previousWindowIds,
              removedWindowIndex,
              removed: window.id,
            );
          }
        } else if (window._selectedTabId == tab.id) {
          window._selectedTabId = _neighborAt(
            previousTabIds,
            removedTabIndex,
            removed: tab.id,
          )!;
        }
      }
      validate();
      return TerminalPaneRemovalResult(
        paneId: paneId,
        tabId: location.tabId,
        windowId: location.windowId,
        removedTab: removedTab,
        removedWindow: removedWindow,
        shutdown: shutdown,
      );
    } finally {
      _endMutation();
    }
  }

  Future<TerminalPaneOwnerShutdownResult> shutdown() {
    final Future<TerminalPaneOwnerShutdownResult>? existing = _shutdownFuture;
    if (existing != null) {
      return existing;
    }
    _beginMutation();
    _disposed = true;
    return _shutdownFuture = _shutdown();
  }

  Future<TerminalPaneOwnerShutdownResult> _shutdown() async {
    final List<TerminalPane> panes = <TerminalPane>[];
    for (final TerminalWindowState window in _windows.values) {
      for (final TerminalTabState tab in window._tabs.values) {
        for (final PaneId paneId in tab._splitTree.paneIds) {
          panes.add(_panes[paneId]!);
        }
      }
    }
    final List<TerminalPaneSessionShutdownResult> results =
        <TerminalPaneSessionShutdownResult>[];
    try {
      for (final TerminalPane pane in panes.reversed) {
        results.add(await _paneOwner.disposePane(pane));
      }
      await _paneOwner.shutdown();
      final TerminalPaneOwnerShutdownResult result =
          TerminalPaneOwnerShutdownResult(results);
      _shutdownResult = result;
      return result;
    } finally {
      _panes.clear();
      _paneLocations.clear();
      _tabs.clear();
      _windows.clear();
      _activeWindowId = null;
      _endMutation();
    }
  }

  /// Throws when any retained hierarchy or reverse-index invariant is broken.
  void validate() {
    if (_windows.length > TerminalApplicationStateLimits.maximumWindows) {
      throw StateError('terminal application exceeds its window limit');
    }
    if (_panes.length > TerminalApplicationStateLimits.maximumTotalPanes) {
      throw StateError('terminal application exceeds its total pane limit');
    }
    if (_windows.isEmpty != (_activeWindowId == null)) {
      throw StateError('active-window identity does not match window state');
    }
    if (_activeWindowId != null && !_windows.containsKey(_activeWindowId)) {
      throw StateError('active window $_activeWindowId is not retained');
    }
    final Set<TerminalTabId> hierarchyTabs = <TerminalTabId>{};
    final Set<PaneId> hierarchyPanes = <PaneId>{};
    var quickTerminalWindowCount = 0;
    for (final MapEntry<TerminalWindowId, TerminalWindowState> windowEntry
        in _windows.entries) {
      final TerminalWindowState window = windowEntry.value;
      if (window.id != windowEntry.key || window._tabs.isEmpty) {
        throw StateError('window ${windowEntry.key} has invalid ownership');
      }
      if (window.role == TerminalWindowRole.quickTerminal &&
          ++quickTerminalWindowCount > 1) {
        throw StateError('application retains multiple Quick Terminals');
      }
      if (window._tabs.length >
          TerminalApplicationStateLimits.maximumTabsPerWindow) {
        throw StateError('window ${window.id} exceeds its tab limit');
      }
      if (!window._tabs.containsKey(window._selectedTabId)) {
        throw StateError('window ${window.id} has no selected tab');
      }
      for (final MapEntry<TerminalTabId, TerminalTabState> tabEntry
          in window._tabs.entries) {
        final TerminalTabState tab = tabEntry.value;
        if (tab.id != tabEntry.key || !hierarchyTabs.add(tab.id)) {
          throw StateError('tab ${tabEntry.key} has invalid ownership');
        }
        if (!identical(_tabs[tab.id], tab)) {
          throw StateError('tab ${tab.id} is absent from the reverse index');
        }
        if (!tab._splitTree.containsPane(tab._focusedPaneId)) {
          throw StateError('tab ${tab.id} has no valid focused pane');
        }
        if (tab._zoomedPaneId != null &&
            (tab._zoomedPaneId != tab._focusedPaneId ||
                !tab._splitTree.containsPane(tab._zoomedPaneId!))) {
          throw StateError('tab ${tab.id} has invalid zoom state');
        }
        if (tab._customTitle != null &&
            !TerminalTabMetadataPolicy.isSafeCustomTitle(tab._customTitle!)) {
          throw StateError('tab ${tab.id} has invalid custom title state');
        }
        for (final PaneId paneId in tab._splitTree.paneIds) {
          if (!hierarchyPanes.add(paneId)) {
            throw StateError('pane $paneId appears in multiple split leaves');
          }
          if (!_panes.containsKey(paneId) ||
              _paneLocations[paneId] !=
                  TerminalPaneLocation(windowId: window.id, tabId: tab.id)) {
            throw StateError('pane $paneId has an invalid reverse index');
          }
        }
      }
    }
    if (hierarchyTabs.length != _tabs.length ||
        hierarchyPanes.length != _panes.length ||
        hierarchyPanes.length != _paneLocations.length) {
      throw StateError('application hierarchy and reverse index counts differ');
    }
    final Set<PaneId> ownerPaneIds = _paneOwner.paneIds.toSet();
    if (ownerPaneIds.length != hierarchyPanes.length ||
        !ownerPaneIds.containsAll(hierarchyPanes)) {
      throw StateError('pane owner and application hierarchy differ');
    }
    for (final MapEntry<PaneId, TerminalPane> paneEntry in _panes.entries) {
      if (paneEntry.value.id != paneEntry.key) {
        throw StateError('pane ${paneEntry.key} has mismatched identity');
      }
    }
  }

  TerminalPane _createPane(TerminalPaneConfiguration configuration) =>
      _paneOwner.createPane(
        sessionFactory: configuration.sessionFactory,
        onChanged: configuration.onChanged,
        onExitRequested: configuration.onExitRequested,
        lifecycleObserver: configuration.lifecycleObserver,
        exitObserver: configuration.exitObserver,
      );

  void _indexPane(
    TerminalPane pane, {
    required TerminalWindowId windowId,
    required TerminalTabId tabId,
  }) {
    if (_panes.containsKey(pane.id) || _paneLocations.containsKey(pane.id)) {
      throw StateError('pane ${pane.id} is already indexed');
    }
    _panes[pane.id] = pane;
    _paneLocations[pane.id] = TerminalPaneLocation(
      windowId: windowId,
      tabId: tabId,
    );
  }

  TerminalWindowState _requireWindow(TerminalWindowId windowId) {
    final TerminalWindowState? window = _windows[windowId];
    if (window == null) {
      throw StateError('unknown terminal window $windowId');
    }
    return window;
  }

  TerminalTabState _requireTab(TerminalTabId tabId) {
    final TerminalTabState? tab = _tabs[tabId];
    if (tab == null) {
      throw StateError('unknown terminal tab $tabId');
    }
    return tab;
  }

  TerminalPaneLocation _requirePaneLocation(PaneId paneId) {
    final TerminalPaneLocation? location = _paneLocations[paneId];
    if (location == null) {
      throw StateError('unknown terminal pane $paneId');
    }
    return location;
  }

  void _beginMutation() {
    _ensureCanMutate();
    _mutationInProgress = true;
    _mutationCompletion = Completer<void>();
  }

  void _endMutation() {
    _mutationInProgress = false;
    final Completer<void>? completion = _mutationCompletion;
    _mutationCompletion = null;
    completion?.complete();
  }

  void _ensureCanMutate() {
    if (_disposed) {
      throw StateError('terminal application state is disposed');
    }
    if (_mutationInProgress) {
      throw StateError('terminal application mutation is already in progress');
    }
  }

  static int _checkedInitialIdentity(int value, String name) {
    if (value < 0 || value > maximumIdentityValue) {
      throw ArgumentError.value(
        value,
        name,
        'must be between zero and $maximumIdentityValue',
      );
    }
    return value;
  }

  void _requirePaneCapacity() {
    if (_panes.length >= TerminalApplicationStateLimits.maximumTotalPanes) {
      throw StateError('terminal application total pane limit is exhausted');
    }
  }

  static int _nextIdentity(
    int current, {
    required int count,
    required String name,
  }) {
    if (count <= 0 || current > maximumIdentityValue - count) {
      throw StateError('terminal $name identity space is exhausted');
    }
    return current + 1;
  }

  static T? _neighborAt<T>(List<T> previous, int index, {required T removed}) {
    final List<T> remaining = previous
        .where((T candidate) => candidate != removed)
        .toList(growable: false);
    if (remaining.isEmpty) {
      return null;
    }
    return remaining[index < remaining.length ? index : remaining.length - 1];
  }
}

final class _TerminalSplitTreeInventory {
  const _TerminalSplitTreeInventory({
    required this.nodeIds,
    required this.paneIds,
  });

  final List<TerminalSplitNodeId> nodeIds;
  final List<PaneId> paneIds;
}

final class _TerminalSplitOrigin {
  const _TerminalSplitOrigin({required this.left, required this.top});

  final double left;
  final double top;
}

final class _TerminalSplitMinimumSize {
  const _TerminalSplitMinimumSize({required this.width, required this.height});

  final double width;
  final double height;
}
