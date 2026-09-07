import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';
import 'terminal_pane.dart';
import 'terminal_tab_metadata.dart';
import 'terminal_tab_presentation.dart';

typedef TerminalNativePaneLayoutCallback = void Function(
  TerminalPaneLayoutRect? rectangle, {
  required bool visible,
});

typedef TerminalNativePaneResourcesFactory =
    TerminalNativePaneResources Function(TerminalPane pane);

typedef TerminalNativeTabTitleBuilder = String Function(
  TerminalWindowState window,
  TerminalTabState tab,
);

typedef TerminalNativeTabPresentationBuilder = TerminalTabPresentation Function(
  TerminalWindowState window,
  TerminalTabState tab,
);

/// Native resources with one-to-one ownership by a logical terminal pane.
final class TerminalNativePaneResources {
  TerminalNativePaneResources({
    required this.paneId,
    required this.view,
    this.onLayout,
    this.onDisposeAdapters,
  });

  final PaneId paneId;
  final View view;
  final TerminalNativePaneLayoutCallback? onLayout;

  /// Disposes input-client, renderer, and other view adapters, but not [view].
  final void Function()? onDisposeAdapters;

  bool _adaptersDisposed = false;
  bool _viewDisposed = false;

  bool get isDisposed => _viewDisposed;

  void applyLayout(TerminalPaneLayoutRect? rectangle, {required bool visible}) {
    if (_adaptersDisposed || _viewDisposed) {
      throw StateError('native resources for pane $paneId are disposed');
    }
    onLayout?.call(rectangle, visible: visible);
  }

  void _disposeAdapters() {
    if (_adaptersDisposed) return;
    onDisposeAdapters?.call();
    _adaptersDisposed = true;
  }

  void _disposeView() {
    if (_viewDisposed) return;
    if (!_adaptersDisposed) {
      throw StateError('pane adapters must be disposed before their view');
    }
    if (!view.isDisposed) {
      view.dispose();
    }
    _viewDisposed = true;
  }
}

/// Projects logical terminal hierarchy identities onto owned AppKit resources.
final class TerminalNativeHierarchyAdapter {
  TerminalNativeHierarchyAdapter({
    required TerminalApplicationState state,
    required TerminalNativePaneResourcesFactory paneResourcesFactory,
    required Rect windowFrame,
    required TerminalSplitLayoutSize cellSize,
    this.dividerThickness = 1,
    this.keyEventRouting = KeyEventRouting.appKitOnly,
    this.defersCloseRequests = true,
    this.presentWindows = true,
    TerminalNativeTabTitleBuilder? titleBuilder,
    TerminalNativeTabPresentationBuilder? presentationBuilder,
  }) : _state = state,
       _paneResourcesFactory = paneResourcesFactory,
       _windowFrame = windowFrame,
       _cellSize = cellSize,
       _presentationBuilder =
           presentationBuilder ??
           (titleBuilder == null
               ? _defaultPresentation
               : (TerminalWindowState window, TerminalTabState tab) =>
                     TerminalTabPresentation(
                       title: titleBuilder(window, tab),
                       color: null,
                       representedFilePath: null,
                     )) {
    if (!dividerThickness.isFinite || dividerThickness < 0) {
      throw ArgumentError.value(
        dividerThickness,
        'dividerThickness',
        'must be finite and non-negative',
      );
    }
    if (titleBuilder != null && presentationBuilder != null) {
      throw ArgumentError(
        'titleBuilder and presentationBuilder are mutually exclusive',
      );
    }
  }

  final TerminalApplicationState _state;
  final TerminalNativePaneResourcesFactory _paneResourcesFactory;
  final Rect _windowFrame;
  final TerminalSplitLayoutSize _cellSize;
  final TerminalNativeTabPresentationBuilder _presentationBuilder;
  final double dividerThickness;
  final KeyEventRouting keyEventRouting;
  final bool defersCloseRequests;
  final bool presentWindows;

  final Map<TerminalTabId, Window> _windows = <TerminalTabId, Window>{};
  final Map<TerminalSplitNodeId, SplitView> _splitViews =
      <TerminalSplitNodeId, SplitView>{};
  final Map<PaneId, TerminalNativePaneResources> _paneResources =
      <PaneId, TerminalNativePaneResources>{};
  final Map<TerminalTabId, TerminalSplitLayoutSize> _tabSizes =
      <TerminalTabId, TerminalSplitLayoutSize>{};
  final Map<TerminalWindowId, TerminalTabId> _selectedTabs =
      <TerminalWindowId, TerminalTabId>{};
  final Map<TerminalTabId, PaneId> _focusedPanes = <TerminalTabId, PaneId>{};

  bool _reconciling = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  int get nativeWindowCount => _windows.length;
  int get splitViewCount => _splitViews.length;
  int get paneResourceCount => _paneResources.length;

  Map<TerminalTabId, Window> get windows =>
      Map<TerminalTabId, Window>.unmodifiable(_windows);
  Map<TerminalSplitNodeId, SplitView> get splitViews =>
      Map<TerminalSplitNodeId, SplitView>.unmodifiable(_splitViews);
  Map<PaneId, TerminalNativePaneResources> get paneResources =>
      Map<PaneId, TerminalNativePaneResources>.unmodifiable(_paneResources);

  Window? windowForTab(TerminalTabId tabId) => _windows[tabId];

  SplitView? splitViewForNode(TerminalSplitNodeId nodeId) =>
      _splitViews[nodeId];

  TerminalNativePaneResources? resourcesForPane(PaneId paneId) =>
      _paneResources[paneId];

  void resizeTab(TerminalTabId tabId, TerminalSplitLayoutSize size) {
    _ensureCanReconcile();
    if (_state.tabForId(tabId) == null) {
      throw StateError('unknown terminal tab $tabId');
    }
    _tabSizes[tabId] = size;
    reconcile();
  }

  void reconcile({Map<TerminalTabId, TerminalSplitLayoutSize>? tabSizes}) {
    _ensureCanReconcile();
    _reconciling = true;
    try {
      if (tabSizes != null) {
        for (final MapEntry<TerminalTabId, TerminalSplitLayoutSize> entry
            in tabSizes.entries) {
          if (_state.tabForId(entry.key) == null) {
            throw StateError('unknown terminal tab ${entry.key}');
          }
          _tabSizes[entry.key] = entry.value;
        }
      }
      _state.validate();
      final List<TerminalWindowState> logicalWindows = _state.windows;
      final Map<TerminalTabId, TerminalTabState> logicalTabs =
          <TerminalTabId, TerminalTabState>{};
      final Map<TerminalTabId, TerminalWindowState> tabOwners =
          <TerminalTabId, TerminalWindowState>{};
      final Map<TerminalTabId, TerminalSplitLayout> layouts =
          <TerminalTabId, TerminalSplitLayout>{};
      final Set<PaneId> livePaneIds = <PaneId>{};
      for (final TerminalWindowState window in logicalWindows) {
        for (final TerminalTabState tab in window.tabs) {
          logicalTabs[tab.id] = tab;
          tabOwners[tab.id] = window;
          livePaneIds.addAll(tab.paneIds);
          layouts[tab.id] = tab.splitTree.layout(
            availableSize:
                _tabSizes[tab.id] ??
                TerminalSplitLayoutSize(
                  width: _windowFrame.width,
                  height: _windowFrame.height,
                ),
            cellSize: _cellSize,
            dividerThickness: dividerThickness,
            zoomedPaneId: tab.zoomedPaneId,
          );
        }
      }

      final Map<PaneId, TerminalNativePaneResources> nextPaneResources =
          <PaneId, TerminalNativePaneResources>{};
      for (final PaneId paneId in livePaneIds) {
        final TerminalNativePaneResources resources =
            _paneResources[paneId] ??
            _paneResourcesFactory(_state.paneForId(paneId)!);
        if (resources.paneId != paneId) {
          throw StateError(
            'pane resource ${resources.paneId} does not match $paneId',
          );
        }
        if (resources.isDisposed || resources.view.isDisposed) {
          throw StateError('pane resources for $paneId are already disposed');
        }
        nextPaneResources[paneId] = resources;
      }
      if (nextPaneResources.values.map((value) => value.view).toSet().length !=
          nextPaneResources.length) {
        throw StateError('terminal panes must not share one native view');
      }

      final Set<TerminalTabId> createdTabWindows = <TerminalTabId>{};
      final Map<TerminalTabId, Window> nextWindows = <TerminalTabId, Window>{};
      for (final MapEntry<TerminalTabId, TerminalTabState> entry
          in logicalTabs.entries) {
        final TerminalWindowState owner = tabOwners[entry.key]!;
        final TerminalTabPresentation presentation = _presentationBuilder(
          owner,
          entry.value,
        );
        Window? window = _windows[entry.key];
        if (window == null) {
          window = Window(frame: _windowFrame, title: presentation.title)
            ..keyEventRouting = keyEventRouting
            ..defersCloseRequests = defersCloseRequests;
          createdTabWindows.add(entry.key);
        } else if (window.title != presentation.title) {
          window.title = presentation.title;
        }
        if (window.representedFilePath != presentation.representedFilePath) {
          window.representedFilePath = presentation.representedFilePath;
        }
        final WindowTabColor? tabColor = _appKitColor(presentation.color);
        if (window.tabColor != tabColor) {
          window.tabColor = tabColor;
        }
        nextWindows[entry.key] = window;
      }

      final Map<TerminalSplitNodeId, SplitView> nextSplitViews =
          <TerminalSplitNodeId, SplitView>{};
      for (final MapEntry<TerminalTabId, TerminalTabState> entry
          in logicalTabs.entries) {
        final TerminalTabState tab = entry.value;
        final View root = _buildNode(
          tab.splitTree.root,
          tab.zoomedPaneId,
          layouts[tab.id]!,
          nextPaneResources,
          nextSplitViews,
        );
        nextWindows[tab.id]!.contentView = root;
      }

      for (final TerminalWindowState logicalWindow in logicalWindows) {
        final List<TerminalTabId> tabIds = logicalWindow.tabIds;
        if (tabIds.length > 1) {
          final Window anchor = nextWindows[tabIds.first]!;
          for (final TerminalTabId tabId in tabIds.skip(1)) {
            if (createdTabWindows.contains(tabId) ||
                createdTabWindows.contains(tabIds.first)) {
              anchor.addTabbedWindow(nextWindows[tabId]!);
            }
          }
        }
      }

      final List<TerminalWindowState> presentationOrder =
          List<TerminalWindowState>.of(logicalWindows);
      final TerminalWindowId? activeWindowId = _state.activeWindowId;
      presentationOrder.sort((
        TerminalWindowState first,
        TerminalWindowState second,
      ) {
        if (first.id == activeWindowId) return 1;
        if (second.id == activeWindowId) return -1;
        return 0;
      });
      for (final TerminalWindowState logicalWindow in presentationOrder) {
        final TerminalTabState selected = logicalWindow.selectedTab;
        final Window selectedWindow = nextWindows[selected.id]!;
        if (presentWindows || _selectedTabs[logicalWindow.id] != selected.id) {
          selectedWindow.selectTab();
        }
        selectedWindow.makeFirstResponder(
          nextPaneResources[selected.focusedPaneId]!.view,
        );
      }

      for (final TerminalTabState tab in logicalTabs.values) {
        final TerminalSplitLayout layout = layouts[tab.id]!;
        for (final PaneId paneId in tab.paneIds) {
          final TerminalPaneLayoutRect? rectangle = layout.panes[paneId];
          nextPaneResources[paneId]!.applyLayout(
            rectangle,
            visible: rectangle != null,
          );
        }
      }

      final List<TerminalNativePaneResources> removedPaneResources =
          _paneResources.entries
              .where(
                (MapEntry<PaneId, TerminalNativePaneResources> entry) =>
                    !nextPaneResources.containsKey(entry.key),
              )
              .map((entry) => entry.value)
              .toList(growable: false);
      final List<SplitView> removedSplitViews = _splitViews.entries
          .where(
            (MapEntry<TerminalSplitNodeId, SplitView> entry) =>
                !nextSplitViews.containsKey(entry.key),
          )
          .map((entry) => entry.value)
          .toList(growable: false);
      final List<Window> removedWindows = _windows.entries
          .where(
            (MapEntry<TerminalTabId, Window> entry) =>
                !nextWindows.containsKey(entry.key),
          )
          .map((entry) => entry.value)
          .toList(growable: false);

      for (final TerminalNativePaneResources resources
          in removedPaneResources.reversed) {
        resources._disposeAdapters();
      }
      for (final SplitView split in removedSplitViews.reversed) {
        if (!split.isDisposed) split.dispose();
      }
      for (final Window window in removedWindows.reversed) {
        if (!window.isDisposed) {
          window.removeFromTabGroup();
          window.dispose();
        }
      }
      for (final TerminalNativePaneResources resources
          in removedPaneResources.reversed) {
        resources._disposeView();
      }

      _paneResources
        ..clear()
        ..addAll(nextPaneResources);
      _splitViews
        ..clear()
        ..addAll(nextSplitViews);
      _windows
        ..clear()
        ..addAll(nextWindows);
      _selectedTabs
        ..clear()
        ..addEntries(
          logicalWindows.map(
            (TerminalWindowState window) =>
                MapEntry<TerminalWindowId, TerminalTabId>(
                  window.id,
                  window.selectedTabId,
                ),
          ),
        );
      _focusedPanes
        ..clear()
        ..addEntries(
          logicalTabs.values.map(
            (TerminalTabState tab) =>
                MapEntry<TerminalTabId, PaneId>(tab.id, tab.focusedPaneId),
          ),
        );
      _tabSizes.removeWhere(
        (TerminalTabId tabId, TerminalSplitLayoutSize _) =>
            !logicalTabs.containsKey(tabId),
      );
    } finally {
      _reconciling = false;
    }
  }

  String machineLine() {
    _ensureAlive();
    return 'TERMINAL_NATIVE_HIERARCHY logical_windows=${_state.windowCount} '
        'native_windows=$nativeWindowCount tabs=${_state.tabCount} '
        'splits=$splitViewCount panes=$paneResourceCount '
        'active_window=${_state.activeWindowId ?? 0}';
  }

  void dispose() {
    if (_disposed) return;
    if (_reconciling) {
      throw StateError('terminal native hierarchy is reconciling');
    }
    _disposed = true;
    for (final TerminalNativePaneResources resources
        in _paneResources.values.toList(growable: false).reversed) {
      resources._disposeAdapters();
    }
    for (final SplitView split
        in _splitViews.values.toList(growable: false).reversed) {
      if (!split.isDisposed) split.dispose();
    }
    for (final Window window
        in _windows.values.toList(growable: false).reversed) {
      if (!window.isDisposed) {
        window.removeFromTabGroup();
        window.dispose();
      }
    }
    for (final TerminalNativePaneResources resources
        in _paneResources.values.toList(growable: false).reversed) {
      resources._disposeView();
    }
    _paneResources.clear();
    _splitViews.clear();
    _windows.clear();
    _tabSizes.clear();
    _selectedTabs.clear();
    _focusedPanes.clear();
  }

  View _buildNode(
    TerminalSplitNode node,
    PaneId? zoomedPaneId,
    TerminalSplitLayout layout,
    Map<PaneId, TerminalNativePaneResources> paneResources,
    Map<TerminalSplitNodeId, SplitView> splitViews,
  ) => switch (node) {
    TerminalSplitLeaf() => paneResources[node.paneId]!.view,
    TerminalSplitBranch() => _buildBranch(
      node,
      zoomedPaneId,
      layout,
      paneResources,
      splitViews,
    ),
  };

  SplitView _buildBranch(
    TerminalSplitBranch branch,
    PaneId? zoomedPaneId,
    TerminalSplitLayout layout,
    Map<PaneId, TerminalNativePaneResources> paneResources,
    Map<TerminalSplitNodeId, SplitView> splitViews,
  ) {
    final SplitViewAxis axis = branch.axis == TerminalSplitAxis.horizontal
        ? SplitViewAxis.horizontal
        : SplitViewAxis.vertical;
    final SplitView split = _splitViews[branch.id] ?? SplitView(axis: axis);
    if (split.axis != axis) {
      throw StateError('split ${branch.id} changed its native axis');
    }
    final View first = _buildNode(
      branch.first,
      zoomedPaneId,
      layout,
      paneResources,
      splitViews,
    );
    final View second = _buildNode(
      branch.second,
      zoomedPaneId,
      layout,
      paneResources,
      splitViews,
    );
    split.setChildren(first: first, second: second);
    final TerminalSplitBranchLayout? geometry = layout.branches[branch.id];
    final _TerminalNativeMinimumSize firstMinimum = _minimumSize(branch.first);
    final _TerminalNativeMinimumSize secondMinimum = _minimumSize(
      branch.second,
    );
    split.setPosition(
      fraction: branch.fraction,
      firstMinimumExtent:
          geometry?.firstMinimumExtent ??
          (branch.axis == TerminalSplitAxis.horizontal
              ? firstMinimum.width
              : firstMinimum.height),
      secondMinimumExtent:
          geometry?.secondMinimumExtent ??
          (branch.axis == TerminalSplitAxis.horizontal
              ? secondMinimum.width
              : secondMinimum.height),
    );
    split.zoomedChild = zoomedPaneId == null
        ? null
        : _containsPane(branch.first, zoomedPaneId)
        ? SplitViewChild.first
        : _containsPane(branch.second, zoomedPaneId)
        ? SplitViewChild.second
        : null;
    splitViews[branch.id] = split;
    return split;
  }

  void _ensureCanReconcile() {
    _ensureAlive();
    if (_reconciling) {
      throw StateError('terminal native hierarchy is already reconciling');
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('terminal native hierarchy is disposed');
    }
  }

  static bool _containsPane(TerminalSplitNode node, PaneId paneId) =>
      switch (node) {
        TerminalSplitLeaf() => node.paneId == paneId,
        TerminalSplitBranch() =>
          _containsPane(node.first, paneId) ||
              _containsPane(node.second, paneId),
      };

  _TerminalNativeMinimumSize _minimumSize(TerminalSplitNode node) =>
      switch (node) {
        TerminalSplitLeaf() => _TerminalNativeMinimumSize(
          width: _cellSize.width,
          height: _cellSize.height,
        ),
        TerminalSplitBranch() => _combineMinimumSizes(
          node.axis,
          _minimumSize(node.first),
          _minimumSize(node.second),
        ),
      };

  _TerminalNativeMinimumSize _combineMinimumSizes(
    TerminalSplitAxis axis,
    _TerminalNativeMinimumSize first,
    _TerminalNativeMinimumSize second,
  ) => switch (axis) {
    TerminalSplitAxis.horizontal => _TerminalNativeMinimumSize(
      width: first.width + dividerThickness + second.width,
      height: first.height > second.height ? first.height : second.height,
    ),
    TerminalSplitAxis.vertical => _TerminalNativeMinimumSize(
      width: first.width > second.width ? first.width : second.width,
      height: first.height + dividerThickness + second.height,
    ),
  };

  static TerminalTabPresentation _defaultPresentation(
    TerminalWindowState window,
    TerminalTabState tab,
  ) => TerminalTabPresentation(
    title: 'Dart Terminal — ${window.id}:${tab.id}',
    color: null,
    representedFilePath: null,
  );

  static WindowTabColor? _appKitColor(TerminalTabColor? color) => color == null
      ? null
      : WindowTabColor(
          red: color.red / 255,
          green: color.green / 255,
          blue: color.blue / 255,
          alpha: color.alpha / 255,
        );
}

final class _TerminalNativeMinimumSize {
  const _TerminalNativeMinimumSize({required this.width, required this.height});

  final double width;
  final double height;
}
