import 'terminal_pane.dart';

/// Hard bounds for the UI-root application hierarchy.
abstract final class TerminalApplicationStateLimits {
  static const int maximumWindows = 32;
  static const int maximumTabsPerWindow = 64;
  static const int maximumPanesPerTab = 64;
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

final class _TerminalSplitTreeInventory {
  const _TerminalSplitTreeInventory({
    required this.nodeIds,
    required this.paneIds,
  });

  final List<TerminalSplitNodeId> nodeIds;
  final List<PaneId> paneIds;
}
