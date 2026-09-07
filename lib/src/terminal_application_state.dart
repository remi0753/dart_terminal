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
       _focusedPaneId = focusedPaneId;

  final TerminalTabId id;
  TerminalSplitTree _splitTree;
  PaneId _focusedPaneId;

  TerminalSplitTree get splitTree => _splitTree;
  PaneId get focusedPaneId => _focusedPaneId;
  List<PaneId> get paneIds => _splitTree.paneIds;
}

/// Application-owned state for one window and its non-empty ordered tabs.
final class TerminalWindowState {
  TerminalWindowState._({
    required this.id,
    required TerminalTabState initialTab,
  }) : _selectedTabId = initialTab.id {
    _tabs[initialTab.id] = initialTab;
  }

  final TerminalWindowId id;
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
  TerminalPaneOwnerShutdownResult? get shutdownResult => _shutdownResult;
  bool get isDisposed => _disposed;

  TerminalWindowState? windowForId(TerminalWindowId windowId) =>
      _windows[windowId];

  TerminalTabState? tabForId(TerminalTabId tabId) => _tabs[tabId];

  TerminalPane? paneForId(PaneId paneId) => _panes[paneId];

  TerminalPaneLocation? locationForPane(PaneId paneId) =>
      _paneLocations[paneId];

  Future<TerminalWindowState> createWindow(
    TerminalPaneConfiguration configuration,
  ) async {
    _beginMutation();
    TerminalPane? pane;
    try {
      if (_windows.length >= TerminalApplicationStateLimits.maximumWindows) {
        throw StateError('terminal application window limit is exhausted');
      }
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
      _mutationInProgress = false;
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
      if (window._tabs.length >=
          TerminalApplicationStateLimits.maximumTabsPerWindow) {
        throw StateError('terminal window tab limit is exhausted');
      }
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
      _mutationInProgress = false;
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
        .._focusedPaneId = pane.id;
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
      _mutationInProgress = false;
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

  void focusPane(TerminalTabId tabId, PaneId paneId) {
    _ensureCanMutate();
    final TerminalTabState tab = _requireTab(tabId);
    if (!tab._splitTree.containsPane(paneId)) {
      throw StateError('pane $paneId does not belong to tab $tabId');
    }
    final TerminalPaneLocation location = _requirePaneLocation(paneId);
    final TerminalWindowState window = _requireWindow(location.windowId);
    tab._focusedPaneId = paneId;
    window._selectedTabId = tabId;
    _activeWindowId = window.id;
    validate();
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
      _mutationInProgress = false;
    }
  }

  Future<TerminalPaneOwnerShutdownResult> shutdown() {
    final Future<TerminalPaneOwnerShutdownResult>? existing = _shutdownFuture;
    if (existing != null) {
      return existing;
    }
    _ensureCanMutate();
    _disposed = true;
    _mutationInProgress = true;
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
      _mutationInProgress = false;
    }
  }

  /// Throws when any retained hierarchy or reverse-index invariant is broken.
  void validate() {
    if (_windows.length > TerminalApplicationStateLimits.maximumWindows) {
      throw StateError('terminal application exceeds its window limit');
    }
    if (_windows.isEmpty != (_activeWindowId == null)) {
      throw StateError('active-window identity does not match window state');
    }
    if (_activeWindowId != null && !_windows.containsKey(_activeWindowId)) {
      throw StateError('active window $_activeWindowId is not retained');
    }
    final Set<TerminalTabId> hierarchyTabs = <TerminalTabId>{};
    final Set<PaneId> hierarchyPanes = <PaneId>{};
    for (final MapEntry<TerminalWindowId, TerminalWindowState> windowEntry
        in _windows.entries) {
      final TerminalWindowState window = windowEntry.value;
      if (window.id != windowEntry.key || window._tabs.isEmpty) {
        throw StateError('window ${windowEntry.key} has invalid ownership');
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
