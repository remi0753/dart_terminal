import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_appkit_policy.dart';
import 'terminal_application_state.dart';
import 'terminal_localization.dart';
import 'terminal_pane.dart';
import 'terminal_restoration.dart';
import 'terminal_tab_presentation.dart';

typedef TerminalNativePaneLayoutCallback = void Function(
  TerminalPaneLayoutRect? rectangle, {
  required bool visible,
});

typedef TerminalNativePaneBackingScaleCallback = void Function(
  double backingScaleFactor,
);

typedef TerminalNativePaneResourcesFactory =
    TerminalNativePaneResources Function(TerminalPane pane);

typedef TerminalNativeWindowFrameBuilder = Rect Function(
  TerminalWindowState window,
);

typedef TerminalNativeWindowConfigurationBuilder = WindowConfiguration Function(
  TerminalWindowState window,
);

typedef TerminalNativeWindowAutomaticPresentationPolicy = bool Function(
  TerminalWindowState window,
);

typedef TerminalNativeTabTitleBuilder = String Function(
  TerminalWindowState window,
  TerminalTabState tab,
);

typedef TerminalNativeTabPresentationBuilder = TerminalTabPresentation Function(
  TerminalWindowState window,
  TerminalTabState tab,
);

/// Resolves the terminal-owned layout inside a possibly decorated tab root.
typedef TerminalNativeTabLayoutSizeResolver = TerminalSplitLayoutSize Function(
  TerminalWindowState window,
  TerminalTabState tab,
  TerminalSplitLayoutSize fullSize,
);

/// Wraps one terminal tree in a product-owned sibling surface.
typedef TerminalNativeTabRootDecorator = View Function(
  TerminalWindowState window,
  TerminalTabState tab,
  View terminalRoot,
  TerminalSplitLayoutSize fullSize,
);

/// Native resources with one-to-one ownership by a logical terminal pane.
final class TerminalNativePaneResources {
  TerminalNativePaneResources({
    required this.paneId,
    required this.view,
    this.onLayout,
    this.onBackingScale,
    this.onDisposeAdapters,
  });

  final PaneId paneId;
  final View view;
  final TerminalNativePaneLayoutCallback? onLayout;
  final TerminalNativePaneBackingScaleCallback? onBackingScale;

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

  void applyBackingScale(double backingScaleFactor) {
    if (_adaptersDisposed || _viewDisposed) {
      throw StateError('native resources for pane $paneId are disposed');
    }
    if (!backingScaleFactor.isFinite || backingScaleFactor <= 0) {
      throw ArgumentError.value(
        backingScaleFactor,
        'backingScaleFactor',
        'must be finite and positive',
      );
    }
    onBackingScale?.call(backingScaleFactor);
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

/// Content-free result of re-projecting live windows after a screen-set change.
final class TerminalNativeDisplayRecoveryResult {
  const TerminalNativeDisplayRecoveryResult({
    required this.windowCount,
    required this.migratedWindowCount,
    required this.adjustedFrameCount,
    required this.paneCount,
  });

  final int windowCount;
  final int migratedWindowCount;
  final int adjustedFrameCount;
  final int paneCount;
}

/// Mirrors an AppKit-owned divider gesture into the authoritative split tree.
///
/// A consumed gesture never reaches terminal mouse reporting or selection.
final class TerminalNativeSplitDividerGestureController {
  TerminalNativeSplitDividerGestureController({
    required this.hierarchy,
    required void Function() reconcile,
  }) : _reconcile = reconcile;

  final TerminalNativeHierarchyAdapter hierarchy;
  final void Function() _reconcile;
  final Map<TerminalTabId, TerminalSplitNodeId> _activeDividers =
      <TerminalTabId, TerminalSplitNodeId>{};

  bool get hasActiveGesture => _activeDividers.isNotEmpty;

  bool route(TerminalTabId tabId, AppKitMouseEvent event) {
    switch (event.kind) {
      case AppKitMouseEventKind.down:
        _activeDividers.remove(tabId);
        if (event.button != 0) return false;
        final TerminalSplitNodeId? divider = hierarchy.dividerAt(
          tabId,
          x: event.x,
          y: event.y,
        );
        if (divider == null) return false;
        _activeDividers[tabId] = divider;
        return true;
      case AppKitMouseEventKind.dragged:
        final TerminalSplitNodeId? divider = _activeDividers[tabId];
        if (divider == null || event.button != 0) return false;
        if (hierarchy.synchronizeNativeSplitFraction(tabId, divider)) {
          _reconcile();
        }
        return true;
      case AppKitMouseEventKind.up:
        final TerminalSplitNodeId? divider = _activeDividers.remove(tabId);
        if (divider == null || event.button != 0) return false;
        if (hierarchy.synchronizeNativeSplitFraction(tabId, divider)) {
          _reconcile();
        }
        return true;
      case AppKitMouseEventKind.moved:
        return false;
    }
  }

  void cancel(TerminalTabId tabId) {
    _activeDividers.remove(tabId);
  }

  void cancelAll() {
    _activeDividers.clear();
  }

  void dispose() {
    _activeDividers.clear();
  }
}

/// Projects logical terminal hierarchy identities onto owned AppKit resources.
final class TerminalNativeHierarchyAdapter {
  TerminalNativeHierarchyAdapter({
    required TerminalApplicationState state,
    required TerminalNativePaneResourcesFactory paneResourcesFactory,
    required Rect windowFrame,
    required TerminalSplitLayoutSize cellSize,
    TerminalNativeWindowFrameBuilder? windowFrameBuilder,
    TerminalNativeWindowConfigurationBuilder? windowConfigurationBuilder,
    TerminalNativeWindowAutomaticPresentationPolicy?
    automaticPresentationPolicy,
    Map<TerminalWindowId, TerminalWindowPlacement> windowPlacements =
        const <TerminalWindowId, TerminalWindowPlacement>{},
    this.dividerThickness = 1,
    this.keyEventRouting = KeyEventRouting.appKitOnly,
    this.defersCloseRequests = true,
    this.presentWindows = true,
    TerminalNativeTabTitleBuilder? titleBuilder,
    TerminalNativeTabPresentationBuilder? presentationBuilder,
    TerminalNativeTabLayoutSizeResolver? tabLayoutSizeResolver,
    TerminalNativeTabRootDecorator? tabRootDecorator,
  }) : _state = state,
       _paneResourcesFactory = paneResourcesFactory,
       _windowFrame = windowFrame,
       _windowFrameBuilder = windowFrameBuilder,
       _windowConfigurationBuilder =
           windowConfigurationBuilder ?? _defaultWindowConfiguration,
       _automaticPresentationPolicy =
           automaticPresentationPolicy ?? _alwaysPresentWindow,
       _cellSize = cellSize,
       _windowPlacements = Map<TerminalWindowId, TerminalWindowPlacement>.of(
         windowPlacements,
       ),
       _presentationBuilder =
           presentationBuilder ??
           (titleBuilder == null
               ? _defaultPresentation
               : (TerminalWindowState window, TerminalTabState tab) =>
                     TerminalTabPresentation(
                       title: titleBuilder(window, tab),
                       color: null,
                       representedFilePath: null,
                     )),
       _tabLayoutSizeResolver = tabLayoutSizeResolver,
       _tabRootDecorator = tabRootDecorator {
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
    for (final TerminalWindowId windowId in _windowPlacements.keys) {
      if (_state.windowForId(windowId) == null) {
        throw ArgumentError.value(
          windowId,
          'windowPlacements',
          'contains a window not retained by the application state',
        );
      }
    }
  }

  final TerminalApplicationState _state;
  final TerminalNativePaneResourcesFactory _paneResourcesFactory;
  final Rect _windowFrame;
  final TerminalNativeWindowFrameBuilder? _windowFrameBuilder;
  final TerminalNativeWindowConfigurationBuilder _windowConfigurationBuilder;
  final TerminalNativeWindowAutomaticPresentationPolicy
  _automaticPresentationPolicy;
  final TerminalSplitLayoutSize _cellSize;
  final Map<TerminalWindowId, TerminalWindowPlacement> _windowPlacements;
  final TerminalNativeTabPresentationBuilder _presentationBuilder;
  final TerminalNativeTabLayoutSizeResolver? _tabLayoutSizeResolver;
  final TerminalNativeTabRootDecorator? _tabRootDecorator;
  final double dividerThickness;
  final KeyEventRouting keyEventRouting;
  final bool defersCloseRequests;
  final bool presentWindows;

  final Map<TerminalTabId, Window> _windows = <TerminalTabId, Window>{};
  final Map<TerminalSplitNodeId, TwoPaneSplitView> _splitViews =
      <TerminalSplitNodeId, TwoPaneSplitView>{};
  final Map<PaneId, TerminalNativePaneResources> _paneResources =
      <PaneId, TerminalNativePaneResources>{};
  final Map<TerminalTabId, TerminalSplitLayoutSize> _tabSizes =
      <TerminalTabId, TerminalSplitLayoutSize>{};
  final Map<TerminalTabId, TerminalSplitLayout> _layouts =
      <TerminalTabId, TerminalSplitLayout>{};
  final Set<TerminalTabId> _explicitTabSizeReconciliations = <TerminalTabId>{};
  final Map<TerminalWindowId, TerminalTabId> _selectedTabs =
      <TerminalWindowId, TerminalTabId>{};
  final Map<TerminalTabId, PaneId> _focusedPanes = <TerminalTabId, PaneId>{};
  final Map<TerminalWindowId, bool> _fullscreenRequests =
      <TerminalWindowId, bool>{};
  final Map<TerminalWindowId, bool> _fullscreenCompletionFrames =
      <TerminalWindowId, bool>{};

  bool _reconciling = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  int get nativeWindowCount => _windows.length;
  int get splitViewCount => _splitViews.length;
  int get paneResourceCount => _paneResources.length;

  Map<TerminalTabId, Window> get windows =>
      Map<TerminalTabId, Window>.unmodifiable(_windows);
  Map<TerminalSplitNodeId, TwoPaneSplitView> get splitViews =>
      Map<TerminalSplitNodeId, TwoPaneSplitView>.unmodifiable(_splitViews);
  Map<PaneId, TerminalNativePaneResources> get paneResources =>
      Map<PaneId, TerminalNativePaneResources>.unmodifiable(_paneResources);
  Map<TerminalWindowId, TerminalWindowPlacement> get windowPlacements =>
      Map<TerminalWindowId, TerminalWindowPlacement>.unmodifiable(
        _windowPlacements,
      );

  Window? windowForTab(TerminalTabId tabId) => _windows[tabId];

  TwoPaneSplitView? splitViewForNode(TerminalSplitNodeId nodeId) =>
      _splitViews[nodeId];

  TerminalNativePaneResources? resourcesForPane(PaneId paneId) =>
      _paneResources[paneId];

  /// Pure geometry bound shared with external sibling-layout decorators.
  TerminalSplitLayoutSize minimumLayoutSizeForTab(TerminalTabId tabId) {
    _ensureAlive();
    final TerminalTabState? tab = _state.tabForId(tabId);
    if (tab == null) throw StateError('tab $tabId is not live');
    if (tab.zoomedPaneId != null) return _cellSize;
    final _TerminalNativeMinimumSize minimum = _minimumSize(tab.splitTree.root);
    return TerminalSplitLayoutSize(
      width: minimum.width,
      height: minimum.height,
    );
  }

  /// Returns the deepest visible divider whose native hit area contains a
  /// window-content point.
  TerminalSplitNodeId? dividerAt(
    TerminalTabId tabId, {
    required double x,
    required double y,
    double hitSlop = 3,
  }) {
    _ensureAlive();
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('divider point must be finite');
    }
    if (!hitSlop.isFinite || hitSlop < 0) {
      throw ArgumentError.value(
        hitSlop,
        'hitSlop',
        'must be finite and non-negative',
      );
    }
    final TerminalTabState? tab = _state.tabForId(tabId);
    if (tab == null) throw StateError('unknown terminal tab $tabId');
    final TerminalSplitLayout? layout = _layouts[tabId];
    if (layout == null || layout.branches.isEmpty) return null;
    final List<TerminalSplitNodeId> candidates = layout.branches.keys
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    for (final TerminalSplitNodeId nodeId in candidates) {
      final TerminalSplitNode node = tab.splitTree.nodeForId(nodeId)!;
      final TerminalSplitBranchLayout geometry = layout.branches[nodeId]!;
      final TerminalPaneLayoutRect? bounds = _nodeBounds(node, layout);
      if (bounds == null) continue;
      final bool horizontal = geometry.axis == TerminalSplitAxis.horizontal;
      final double dividerStart = horizontal
          ? bounds.left + geometry.dividerOffset
          : bounds.top + geometry.dividerOffset;
      final double axisPoint = horizontal ? x : y;
      final double crossPoint = horizontal ? y : x;
      final double crossStart = horizontal ? bounds.top : bounds.left;
      final double crossEnd =
          crossStart + (horizontal ? bounds.height : bounds.width);
      if (axisPoint >= dividerStart - hitSlop &&
          axisPoint <= dividerStart + dividerThickness + hitSlop &&
          crossPoint >= crossStart &&
          crossPoint <= crossEnd) {
        return nodeId;
      }
    }
    return null;
  }

  /// Reads one native drag result into the application-owned branch fraction.
  bool synchronizeNativeSplitFraction(
    TerminalTabId tabId,
    TerminalSplitNodeId nodeId,
  ) {
    _ensureCanReconcile();
    final TerminalTabState? tab = _state.tabForId(tabId);
    if (tab == null) throw StateError('unknown terminal tab $tabId');
    final TerminalSplitNode? node = tab.splitTree.nodeForId(nodeId);
    if (node is! TerminalSplitBranch) {
      throw StateError('split node $nodeId is not a branch in tab $tabId');
    }
    final TwoPaneSplitView? split = _splitViews[nodeId];
    if (split == null || split.isDisposed) {
      throw StateError('split node $nodeId is not projected');
    }
    final double fraction = split.refreshFraction();
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw StateError('native split fraction must remain strictly bounded');
    }
    if ((fraction - node.fraction).abs() <= 1e-9) return false;
    _state.resizeSplit(tabId, nodeId, fraction);
    return true;
  }

  /// Whether the nearest focused-pane divider on [direction]'s axis can move.
  bool canMoveFocusedDivider(TerminalSplitDividerDirection direction) =>
      _focusedDividerMove(direction) != null;

  /// Moves the nearest matching focused-pane divider by one logical cell.
  ///
  /// The caller reconciles after a successful mutation so native frames,
  /// renderer viewports, terminal grids, and PTY winsizes advance together.
  bool moveFocusedDivider(TerminalSplitDividerDirection direction) {
    _ensureCanReconcile();
    final _TerminalFocusedDividerMove? movement = _focusedDividerMove(
      direction,
    );
    if (movement == null) return false;
    _state.resizeSplit(movement.tabId, movement.nodeId, movement.fraction);
    return true;
  }

  /// Whether the selected tab has a projected pane in [direction].
  bool canFocusPane(TerminalPaneFocusDirection direction) =>
      _focusedPaneTarget(direction) != null;

  /// Focuses the closest projected pane in [direction] without wrapping.
  ///
  /// The caller reconciles after a successful mutation so first responder,
  /// Metal focus presentation, menus, and the command palette advance once.
  bool focusPane(TerminalPaneFocusDirection direction) {
    _ensureCanReconcile();
    final TerminalTabState? tab = _state.activeWindow?.selectedTab;
    if (tab == null) return false;
    final PaneId? target = _focusedPaneTarget(direction);
    if (target == null) return false;
    _state.focusPane(tab.id, target);
    return true;
  }

  PaneId? _focusedPaneTarget(TerminalPaneFocusDirection direction) {
    if (_disposed || _reconciling || _state.isDisposed) return null;
    final TerminalTabState? tab = _state.activeWindow?.selectedTab;
    if (tab == null || tab.isZoomed) return null;
    final TerminalSplitLayout? layout = _layouts[tab.id];
    final TerminalPaneLayoutRect? focused = layout?.panes[tab.focusedPaneId];
    if (layout == null || focused == null) return null;

    _TerminalDirectionalPaneCandidate? best;
    for (var index = 0; index < tab.paneIds.length; index++) {
      final PaneId paneId = tab.paneIds[index];
      if (paneId == tab.focusedPaneId) continue;
      final TerminalPaneLayoutRect? candidate = layout.panes[paneId];
      if (candidate == null) continue;
      final _TerminalDirectionalPaneCandidate? scored =
          _directionalPaneCandidate(
            direction,
            focused,
            candidate,
            paneId,
            index,
          );
      if (scored != null && (best == null || scored.isBetterThan(best))) {
        best = scored;
      }
    }
    return best?.paneId;
  }

  static _TerminalDirectionalPaneCandidate? _directionalPaneCandidate(
    TerminalPaneFocusDirection direction,
    TerminalPaneLayoutRect focused,
    TerminalPaneLayoutRect candidate,
    PaneId paneId,
    int visualIndex,
  ) {
    const double epsilon = 1e-9;
    final double focusedRight = focused.left + focused.width;
    final double focusedBottom = focused.top + focused.height;
    final double candidateRight = candidate.left + candidate.width;
    final double candidateBottom = candidate.top + candidate.height;
    late final double primaryDistance;
    late final double focusedCrossStart;
    late final double focusedCrossEnd;
    late final double candidateCrossStart;
    late final double candidateCrossEnd;
    switch (direction) {
      case TerminalPaneFocusDirection.left:
        if (candidateRight > focused.left + epsilon) return null;
        primaryDistance = focused.left - candidateRight;
        focusedCrossStart = focused.top;
        focusedCrossEnd = focusedBottom;
        candidateCrossStart = candidate.top;
        candidateCrossEnd = candidateBottom;
      case TerminalPaneFocusDirection.right:
        if (candidate.left < focusedRight - epsilon) return null;
        primaryDistance = candidate.left - focusedRight;
        focusedCrossStart = focused.top;
        focusedCrossEnd = focusedBottom;
        candidateCrossStart = candidate.top;
        candidateCrossEnd = candidateBottom;
      case TerminalPaneFocusDirection.up:
        if (candidateBottom > focused.top + epsilon) return null;
        primaryDistance = focused.top - candidateBottom;
        focusedCrossStart = focused.left;
        focusedCrossEnd = focusedRight;
        candidateCrossStart = candidate.left;
        candidateCrossEnd = candidateRight;
      case TerminalPaneFocusDirection.down:
        if (candidate.top < focusedBottom - epsilon) return null;
        primaryDistance = candidate.top - focusedBottom;
        focusedCrossStart = focused.left;
        focusedCrossEnd = focusedRight;
        candidateCrossStart = candidate.left;
        candidateCrossEnd = candidateRight;
    }
    final bool crossOverlaps =
        candidateCrossEnd > focusedCrossStart + epsilon &&
        focusedCrossEnd > candidateCrossStart + epsilon;
    final double crossGap = crossOverlaps
        ? 0
        : candidateCrossEnd <= focusedCrossStart
        ? focusedCrossStart - candidateCrossEnd
        : candidateCrossStart - focusedCrossEnd;
    final double crossCenterDistance =
        ((candidateCrossStart + candidateCrossEnd) / 2 -
                (focusedCrossStart + focusedCrossEnd) / 2)
            .abs();
    return _TerminalDirectionalPaneCandidate(
      paneId: paneId,
      crossOverlaps: crossOverlaps,
      primaryDistance: primaryDistance,
      crossGap: crossGap,
      crossCenterDistance: crossCenterDistance,
      visualIndex: visualIndex,
    );
  }

  _TerminalFocusedDividerMove? _focusedDividerMove(
    TerminalSplitDividerDirection direction,
  ) {
    if (_disposed || _reconciling || _state.isDisposed) return null;
    final TerminalTabState? tab = _state.activeWindow?.selectedTab;
    if (tab == null || tab.isZoomed) return null;
    final TerminalSplitAxis axis = switch (direction) {
      TerminalSplitDividerDirection.left ||
      TerminalSplitDividerDirection.right => TerminalSplitAxis.horizontal,
      TerminalSplitDividerDirection.up ||
      TerminalSplitDividerDirection.down => TerminalSplitAxis.vertical,
    };
    final TerminalSplitBranch? branch = _nearestMatchingBranch(
      tab.splitTree.root,
      tab.focusedPaneId,
      axis,
    );
    if (branch == null) return null;
    final TerminalSplitBranchLayout? geometry =
        _layouts[tab.id]?.branches[branch.id];
    if (geometry == null) return null;
    final double usableExtent = geometry.firstExtent + geometry.secondExtent;
    if (!usableExtent.isFinite || usableExtent <= 0) return null;
    final bool negative =
        direction == TerminalSplitDividerDirection.left ||
        direction == TerminalSplitDividerDirection.up;
    final double step = axis == TerminalSplitAxis.horizontal
        ? _cellSize.width
        : _cellSize.height;
    final double nextFirstExtent =
        (geometry.firstExtent + (negative ? -step : step))
            .clamp(
              geometry.firstMinimumExtent,
              usableExtent - geometry.secondMinimumExtent,
            )
            .toDouble();
    if ((nextFirstExtent - geometry.firstExtent).abs() <= 1e-9) {
      return null;
    }
    return _TerminalFocusedDividerMove(
      tabId: tab.id,
      nodeId: branch.id,
      fraction: nextFirstExtent / usableExtent,
    );
  }

  static TerminalSplitBranch? _nearestMatchingBranch(
    TerminalSplitNode node,
    PaneId paneId,
    TerminalSplitAxis axis,
  ) {
    if (node is! TerminalSplitBranch) return null;
    final TerminalSplitNode? child = _containsPane(node.first, paneId)
        ? node.first
        : _containsPane(node.second, paneId)
        ? node.second
        : null;
    if (child == null) return null;
    return _nearestMatchingBranch(child, paneId, axis) ??
        (node.axis == axis ? node : null);
  }

  TerminalWindowPlacement placementForWindow(TerminalWindowId windowId) {
    _ensureAlive();
    if (_state.windowForId(windowId) == null) {
      throw StateError('unknown terminal window $windowId');
    }
    return _windowPlacements.putIfAbsent(
      windowId,
      () => _defaultPlacement(_state.windowForId(windowId)!),
    );
  }

  /// Updates one authoritative windowed frame before a custom presentation.
  ///
  /// [project] may be disabled when [Window.present] will apply the native
  /// animation endpoints itself. The model still advances immediately so a
  /// later reconciliation cannot snap the window back to stale geometry.
  void updateWindowedFrame(
    TerminalWindowId windowId,
    Rect frame, {
    AppKitScreen? screen,
    bool project = true,
  }) {
    _ensureCanReconcile();
    final TerminalWindowState? logicalWindow = _state.windowForId(windowId);
    if (logicalWindow == null) {
      throw StateError('unknown terminal window $windowId');
    }
    _validateWindowFrame(frame);
    final TerminalWindowPlacement current = placementForWindow(windowId);
    _windowPlacements[windowId] = current.copyWith(
      windowedFrame: _terminalFrame(frame),
      screen: screen == null ? null : _terminalScreen(screen),
      fullscreen: false,
    );
    if (project) _projectPlacement(logicalWindow);
  }

  /// Requests fullscreen for the selected native tab of one logical window.
  void requestFullscreen(TerminalWindowId windowId, bool enabled) {
    _ensureCanReconcile();
    final TerminalWindowState? logicalWindow = _state.windowForId(windowId);
    if (logicalWindow == null) {
      throw StateError('unknown terminal window $windowId');
    }
    final Window? selected = _windows[logicalWindow.selectedTabId];
    if (selected == null) {
      throw StateError('terminal window $windowId is not projected');
    }
    _setFullscreen(windowId, selected, enabled);
    _windowPlacements[windowId] = placementForWindow(windowId)
        .copyWith(fullscreen: enabled);
  }

  /// Reconciles one already-routed native event into logical placement state.
  void handleWindowEvent(TerminalTabId sourceTabId, WindowEvent event) {
    _ensureCanReconcile();
    final TerminalWindowState logicalWindow = _windowForTab(sourceTabId);
    final TerminalWindowId windowId = logicalWindow.id;
    final TerminalWindowPlacement current = placementForWindow(windowId);
    switch (event) {
      case WindowFrameChangedEvent(:final frame):
        final bool? completionFullscreen = _fullscreenCompletionFrames.remove(
          windowId,
        );
        if (completionFullscreen != null) {
          if (!completionFullscreen) _projectPlacement(logicalWindow);
          return;
        }
        if (!current.fullscreen) {
          _windowPlacements[windowId] = current.copyWith(
            windowedFrame: _terminalFrame(frame),
          );
          _projectPlacement(logicalWindow);
        }
      case WindowFullscreenChangedEvent(:final isFullscreen):
        final bool requestedTransition =
            _fullscreenRequests.remove(windowId) != null;
        if (requestedTransition || current.fullscreen != isFullscreen) {
          _fullscreenCompletionFrames[windowId] = isFullscreen;
        }
        _windowPlacements[windowId] = current.copyWith(
          fullscreen: isFullscreen,
        );
        if (!isFullscreen) _projectPlacement(logicalWindow);
      case WindowScreenChangedEvent(:final screen):
        if (screen == null) {
          _windowPlacements[windowId] = current.copyWith(clearScreen: true);
          return;
        }
        final TerminalScreenPlacement observed = _terminalScreen(screen);
        final TerminalWindowPlacement resolved =
            TerminalWindowPlacementPolicy.resolveForAvailableScreens(
              current,
              <TerminalScreenPlacement>[observed],
              fallbackDisplayId: observed.displayId,
            );
        _windowPlacements[windowId] = resolved;
        if (!resolved.fullscreen) _projectPlacement(logicalWindow);
      case WindowClosedEvent() ||
          WindowCloseRequestedEvent() ||
          WindowResizedEvent() ||
          WindowFocusChangedEvent() ||
          WindowVisibilityChangedEvent() ||
          WindowOcclusionChangedEvent() ||
          WindowBackingScaleChangedEvent() ||
          AppKitKeyEvent() ||
          AppKitScrollEvent() ||
          AppKitMouseEvent():
        break;
    }
  }

  /// Shows every logical window, optionally restoring selection/focus once.
  void present({bool restoreSelectionAndFocus = true}) {
    _ensureCanReconcile();
    for (final TerminalWindowState logicalWindow in _presentationOrder()) {
      if (!_automaticPresentationPolicy(logicalWindow)) continue;
      _presentWindow(logicalWindow, force: restoreSelectionAndFocus);
    }
  }

  void resizeTab(TerminalTabId tabId, TerminalSplitLayoutSize size) {
    _ensureCanReconcile();
    if (_state.tabForId(tabId) == null) {
      throw StateError('unknown terminal tab $tabId');
    }
    reconcile(tabSizes: <TerminalTabId, TerminalSplitLayoutSize>{tabId: size});
  }

  /// Refreshes retained native title, tab color, and represented URL only.
  void refreshPresentation() {
    _ensureCanReconcile();
    for (final TerminalWindowState logicalWindow in _state.windows) {
      for (final TerminalTabState tab in logicalWindow.tabs) {
        final Window? window = _windows[tab.id];
        if (window == null) continue;
        final TerminalTabPresentation presentation = _presentationBuilder(
          logicalWindow,
          tab,
        );
        if (window.title != presentation.title) {
          window.title = presentation.title;
        }
        if (window.representedFilePath != presentation.representedFilePath) {
          window.representedFilePath = presentation.representedFilePath;
        }
        final WindowTabAccessory? tabAccessory = terminalTabAccessory(
          presentation.color,
        );
        if (window.tabAccessory != tabAccessory) {
          window.tabAccessory = tabAccessory;
        }
      }
    }
  }

  void reconcile({
    Map<TerminalTabId, TerminalSplitLayoutSize>? tabSizes,
    Map<TerminalWindowId, double>? windowBackingScales,
  }) {
    _ensureCanReconcile();
    _reconciling = true;
    final Set<TerminalTabId> explicitTabSizeIds = tabSizes == null
        ? const <TerminalTabId>{}
        : tabSizes.keys.toSet();
    _explicitTabSizeReconciliations.addAll(explicitTabSizeIds);
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
      final Map<TerminalTabId, TerminalSplitLayoutSize> fullContentSizes =
          <TerminalTabId, TerminalSplitLayoutSize>{};
      final Set<PaneId> livePaneIds = <PaneId>{};
      for (final TerminalWindowState window in logicalWindows) {
        _windowPlacements.putIfAbsent(
          window.id,
          () => _defaultPlacement(window),
        );
        for (final TerminalTabState tab in window.tabs) {
          logicalTabs[tab.id] = tab;
          tabOwners[tab.id] = window;
          livePaneIds.addAll(tab.paneIds);
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
        final TerminalWindowPlacement placement = placementForWindow(owner.id);
        final Rect nativeFrame = _appKitFrame(placement.windowedFrame);
        Window? window = _windows[entry.key];
        if (window == null) {
          window =
              Window(
                  frame: nativeFrame,
                  title: presentation.title,
                  configuration: _windowConfigurationBuilder(owner),
                )
                ..keyEventRouting = keyEventRouting
                ..defersCloseRequests = defersCloseRequests;
          createdTabWindows.add(entry.key);
        } else if (window.title != presentation.title) {
          window.title = presentation.title;
        }
        if (!window.isFullscreen && window.frame != nativeFrame) {
          window.frame = nativeFrame;
        }
        if (window.representedFilePath != presentation.representedFilePath) {
          window.representedFilePath = presentation.representedFilePath;
        }
        final WindowTabAccessory? tabAccessory = terminalTabAccessory(
          presentation.color,
        );
        if (window.tabAccessory != tabAccessory) {
          window.tabAccessory = tabAccessory;
        }
        nextWindows[entry.key] = window;
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

      for (final MapEntry<TerminalTabId, TerminalTabState> entry
          in logicalTabs.entries) {
        final TerminalTabState tab = entry.value;
        final TerminalWindowState owner = tabOwners[tab.id]!;
        final TerminalWindowPlacement placement = placementForWindow(owner.id);
        final TerminalSplitLayoutSize fullSize = _contentLayoutSize(
          tab.id,
          nextWindows[tab.id]!,
          placement,
        );
        fullContentSizes[tab.id] = fullSize;
        final TerminalSplitLayoutSize availableSize =
            _tabLayoutSizeResolver?.call(owner, tab, fullSize) ?? fullSize;
        _validateDecoratedLayoutSize(availableSize, fullSize, tab.id);
        layouts[tab.id] = tab.splitTree.layout(
          availableSize: availableSize,
          cellSize: _cellSize,
          dividerThickness: dividerThickness,
          zoomedPaneId: tab.zoomedPaneId,
        );
      }

      final Map<TerminalSplitNodeId, TwoPaneSplitView> nextSplitViews =
          <TerminalSplitNodeId, TwoPaneSplitView>{};
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
        final View decoratedRoot =
            _tabRootDecorator?.call(
              tabOwners[tab.id]!,
              tab,
              root,
              fullContentSizes[tab.id]!,
            ) ??
            root;
        if (decoratedRoot.isDisposed) {
          throw StateError('decorated tab root for ${tab.id} is disposed');
        }
        final Window window = nextWindows[tab.id]!;
        if (!identical(window.contentView, decoratedRoot)) {
          window.contentView = decoratedRoot;
        }
      }

      for (final TerminalWindowState logicalWindow in _presentationOrder()) {
        final bool created = logicalWindow.tabIds.any(
          createdTabWindows.contains,
        );
        _presentWindow(
          logicalWindow,
          windows: nextWindows,
          paneResources: nextPaneResources,
          force: created,
          show:
              presentWindows &&
              created &&
              _automaticPresentationPolicy(logicalWindow),
        );
      }

      for (final TerminalTabState tab in logicalTabs.values) {
        final TerminalSplitLayout layout = layouts[tab.id]!;
        final TerminalWindowState owner = tabOwners[tab.id]!;
        final double backingScaleFactor =
            windowBackingScales?[owner.id] ??
            nextWindows[tab.id]!.backingScaleFactor ??
            1;
        for (final PaneId paneId in tab.paneIds) {
          final TerminalPaneLayoutRect? rectangle = layout.panes[paneId];
          nextPaneResources[paneId]!.applyBackingScale(backingScaleFactor);
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
      final List<TwoPaneSplitView> removedSplitViews = _splitViews.entries
          .where(
            (MapEntry<TerminalSplitNodeId, TwoPaneSplitView> entry) =>
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
      for (final TwoPaneSplitView split in removedSplitViews.reversed) {
        if (!split.isDisposed) split.dispose();
      }
      for (final Window window in removedWindows.reversed) {
        if (!window.isDisposed) {
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
      _layouts
        ..clear()
        ..addAll(layouts);
      _windowPlacements.removeWhere(
        (TerminalWindowId windowId, TerminalWindowPlacement _) =>
            _state.windowForId(windowId) == null,
      );
      _fullscreenRequests.removeWhere(
        (TerminalWindowId windowId, bool _) =>
            _state.windowForId(windowId) == null,
      );
      _fullscreenCompletionFrames.removeWhere(
        (TerminalWindowId windowId, bool _) =>
            _state.windowForId(windowId) == null,
      );
    } finally {
      _explicitTabSizeReconciliations.removeAll(explicitTabSizeIds);
      _reconciling = false;
    }
  }

  /// Re-resolves every logical window from its current native screen snapshot.
  ///
  /// AppKit owns which screen a native window currently occupies. The product
  /// owns migration/clamping and applies one authoritative placement and scale
  /// to every tab/pane in that logical window.
  TerminalNativeDisplayRecoveryResult recoverDisplaySet({
    required AppKitResolvedScreen fallbackScreen,
  }) {
    _ensureCanReconcile();
    final Map<TerminalWindowId, double> backingScales =
        <TerminalWindowId, double>{};
    var migrated = 0;
    var adjusted = 0;
    for (final TerminalWindowState logicalWindow in _state.windows) {
      final Window? selected = _windows[logicalWindow.selectedTabId];
      if (selected == null || selected.isDisposed) {
        throw StateError(
          'terminal window ${logicalWindow.id} is not projected for recovery',
        );
      }
      final AppKitScreen observedScreen =
          selected.screen ?? fallbackScreen.screen;
      final double observedScale =
          selected.backingScaleFactor ?? fallbackScreen.backingScaleFactor;
      final TerminalWindowPlacement current = placementForWindow(
        logicalWindow.id,
      );
      final TerminalWindowPlacement resolved =
          TerminalWindowPlacementPolicy.resolveForAvailableScreens(
            current,
            <TerminalScreenPlacement>[_terminalScreen(observedScreen)],
            fallbackDisplayId: observedScreen.displayId,
          );
      if (current.screen?.displayId != resolved.screen?.displayId) migrated++;
      if (current.windowedFrame != resolved.windowedFrame) adjusted++;
      _windowPlacements[logicalWindow.id] = resolved;
      backingScales[logicalWindow.id] = observedScale;
    }
    reconcile(windowBackingScales: backingScales);
    return TerminalNativeDisplayRecoveryResult(
      windowCount: _state.windowCount,
      migratedWindowCount: migrated,
      adjustedFrameCount: adjusted,
      paneCount: _state.paneCount,
    );
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
    for (final TwoPaneSplitView split
        in _splitViews.values.toList(growable: false).reversed) {
      if (!split.isDisposed) split.dispose();
    }
    for (final Window window
        in _windows.values.toList(growable: false).reversed) {
      if (!window.isDisposed) {
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
    _layouts.clear();
    _explicitTabSizeReconciliations.clear();
    _selectedTabs.clear();
    _focusedPanes.clear();
    _windowPlacements.clear();
    _fullscreenRequests.clear();
    _fullscreenCompletionFrames.clear();
  }

  void _presentWindow(
    TerminalWindowState logicalWindow, {
    Map<TerminalTabId, Window>? windows,
    Map<PaneId, TerminalNativePaneResources>? paneResources,
    required bool force,
    bool show = true,
  }) {
    final Map<TerminalTabId, Window> projectedWindows = windows ?? _windows;
    final Map<PaneId, TerminalNativePaneResources> projectedPanes =
        paneResources ?? _paneResources;
    final TerminalTabState selected = logicalWindow.selectedTab;
    final Window selectedWindow = projectedWindows[selected.id]!;
    final bool selectionChanged =
        _selectedTabs[logicalWindow.id] != selected.id;
    final bool focusChanged =
        _focusedPanes[selected.id] != selected.focusedPaneId;
    if (show) selectedWindow.show();
    if (force || selectionChanged) selectedWindow.selectTab();
    if (force || selectionChanged || focusChanged) {
      selectedWindow.makeFirstResponder(
        projectedPanes[selected.focusedPaneId]!.view,
      );
    }
    final bool desiredFullscreen = placementForWindow(logicalWindow.id)
        .fullscreen;
    if (selectedWindow.isFullscreen != desiredFullscreen) {
      _setFullscreen(logicalWindow.id, selectedWindow, desiredFullscreen);
    }
  }

  void _setFullscreen(
    TerminalWindowId windowId,
    Window selectedWindow,
    bool enabled,
  ) {
    final bool startsTransition = selectedWindow.isFullscreen != enabled;
    selectedWindow.setFullscreen(enabled);
    if (startsTransition) _fullscreenRequests[windowId] = enabled;
  }

  void _projectPlacement(TerminalWindowState logicalWindow) {
    final Rect frame = _appKitFrame(
      placementForWindow(logicalWindow.id).windowedFrame,
    );
    for (final TerminalTabId tabId in logicalWindow.tabIds) {
      final Window? window = _windows[tabId];
      if (window != null && !window.isFullscreen && window.frame != frame) {
        window.frame = frame;
      }
    }
  }

  List<TerminalWindowState> _presentationOrder() {
    final List<TerminalWindowState> result = List<TerminalWindowState>.of(
      _state.windows,
    );
    final TerminalWindowId? activeWindowId = _state.activeWindowId;
    result.sort((TerminalWindowState first, TerminalWindowState second) {
      if (first.id == activeWindowId) return 1;
      if (second.id == activeWindowId) return -1;
      return 0;
    });
    return result;
  }

  TerminalWindowState _windowForTab(TerminalTabId tabId) {
    for (final TerminalWindowState window in _state.windows) {
      if (window.tabIds.contains(tabId)) return window;
    }
    throw StateError('unknown terminal tab $tabId');
  }

  TerminalWindowPlacement _defaultPlacement(TerminalWindowState window) {
    final Rect frame = _windowFrameBuilder?.call(window) ?? _windowFrame;
    _validateWindowFrame(frame);
    return TerminalWindowPlacement(
      windowedFrame: _terminalFrame(frame),
      screen: null,
      fullscreen: false,
    );
  }

  static Rect _appKitFrame(TerminalWindowFrame frame) =>
      Rect.fromLTWH(frame.left, frame.top, frame.width, frame.height);

  static TerminalWindowFrame _terminalFrame(Rect frame) => TerminalWindowFrame(
    left: frame.left,
    top: frame.top,
    width: frame.width,
    height: frame.height,
  );

  static TerminalScreenPlacement _terminalScreen(AppKitScreen screen) =>
      TerminalScreenPlacement(
        displayId: screen.displayId,
        frame: _terminalFrame(screen.frame),
        visibleFrame: _terminalFrame(screen.visibleFrame),
      );

  static void _validateWindowFrame(Rect frame) {
    if (!frame.left.isFinite ||
        !frame.top.isFinite ||
        !frame.width.isFinite ||
        !frame.height.isFinite ||
        frame.width <= 0 ||
        frame.height <= 0) {
      throw ArgumentError.value(frame, 'frame', 'invalid window frame');
    }
  }

  static WindowConfiguration _defaultWindowConfiguration(
    TerminalWindowState _,
  ) => terminalWindowConfiguration;

  static bool _alwaysPresentWindow(TerminalWindowState _) => true;

  TerminalSplitLayoutSize _contentLayoutSize(
    TerminalTabId tabId,
    Window window,
    TerminalWindowPlacement placement,
  ) {
    if (_explicitTabSizeReconciliations.contains(tabId)) {
      return _tabSizes[tabId]!;
    }
    try {
      final Rect content = window.contentLayoutRect;
      if (!content.width.isFinite ||
          !content.height.isFinite ||
          content.width <= 0 ||
          content.height <= 0) {
        throw StateError(
          'native content layout for $tabId is not finite and positive',
        );
      }
      final TerminalSplitLayoutSize resolved = TerminalSplitLayoutSize(
        width: content.width,
        height: content.height,
      );
      _tabSizes[tabId] = resolved;
      return resolved;
    } on AppKitNativeException catch (error) {
      if (error.status != 8) rethrow;
    }
    return _tabSizes[tabId] ??
        TerminalSplitLayoutSize(
          width: placement.windowedFrame.width,
          height: placement.windowedFrame.height,
        );
  }

  static void _validateDecoratedLayoutSize(
    TerminalSplitLayoutSize value,
    TerminalSplitLayoutSize fullSize,
    TerminalTabId tabId,
  ) {
    if (!value.width.isFinite ||
        !value.height.isFinite ||
        value.width <= 0 ||
        value.height <= 0 ||
        value.width > fullSize.width ||
        value.height > fullSize.height) {
      throw StateError(
        'decorated terminal layout for $tabId must be finite, positive, and '
        'contained by the native content size',
      );
    }
  }

  View _buildNode(
    TerminalSplitNode node,
    PaneId? zoomedPaneId,
    TerminalSplitLayout layout,
    Map<PaneId, TerminalNativePaneResources> paneResources,
    Map<TerminalSplitNodeId, TwoPaneSplitView> splitViews,
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

  TwoPaneSplitView _buildBranch(
    TerminalSplitBranch branch,
    PaneId? zoomedPaneId,
    TerminalSplitLayout layout,
    Map<PaneId, TerminalNativePaneResources> paneResources,
    Map<TerminalSplitNodeId, TwoPaneSplitView> splitViews,
  ) {
    final SplitViewAxis axis = branch.axis == TerminalSplitAxis.horizontal
        ? SplitViewAxis.horizontal
        : SplitViewAxis.vertical;
    final TwoPaneSplitView split =
        _splitViews[branch.id] ?? TwoPaneSplitView(axis: axis);
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
    if (!identical(split.firstView, first) ||
        !identical(split.secondView, second)) {
      split.setChildren(first: first, second: second);
    }
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

  static TerminalPaneLayoutRect? _nodeBounds(
    TerminalSplitNode node,
    TerminalSplitLayout layout,
  ) {
    switch (node) {
      case TerminalSplitLeaf():
        return layout.panes[node.paneId];
      case TerminalSplitBranch():
        final TerminalPaneLayoutRect? first = _nodeBounds(node.first, layout);
        final TerminalPaneLayoutRect? second = _nodeBounds(node.second, layout);
        if (first == null) return second;
        if (second == null) return first;
        final double left = first.left < second.left ? first.left : second.left;
        final double top = first.top < second.top ? first.top : second.top;
        final double right =
            first.left + first.width > second.left + second.width
            ? first.left + first.width
            : second.left + second.width;
        final double bottom =
            first.top + first.height > second.top + second.height
            ? first.top + first.height
            : second.top + second.height;
        return TerminalPaneLayoutRect(
          left: left,
          top: top,
          width: right - left,
          height: bottom - top,
        );
    }
  }

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
    title:
        '${TerminalLocalization.english.applicationName} — '
        '${window.id}:${tab.id}',
    color: null,
    representedFilePath: null,
  );
}

final class _TerminalDirectionalPaneCandidate {
  const _TerminalDirectionalPaneCandidate({
    required this.paneId,
    required this.crossOverlaps,
    required this.primaryDistance,
    required this.crossGap,
    required this.crossCenterDistance,
    required this.visualIndex,
  });

  final PaneId paneId;
  final bool crossOverlaps;
  final double primaryDistance;
  final double crossGap;
  final double crossCenterDistance;
  final int visualIndex;

  bool isBetterThan(_TerminalDirectionalPaneCandidate other) {
    if (crossOverlaps != other.crossOverlaps) return crossOverlaps;
    final int primary = _compare(primaryDistance, other.primaryDistance);
    if (primary != 0) return primary < 0;
    final int gap = _compare(crossGap, other.crossGap);
    if (gap != 0) return gap < 0;
    final int center = _compare(crossCenterDistance, other.crossCenterDistance);
    if (center != 0) return center < 0;
    return visualIndex < other.visualIndex;
  }

  static int _compare(double left, double right) {
    if ((left - right).abs() <= 1e-9) return 0;
    return left < right ? -1 : 1;
  }
}

final class _TerminalFocusedDividerMove {
  const _TerminalFocusedDividerMove({
    required this.tabId,
    required this.nodeId,
    required this.fraction,
  });

  final TerminalTabId tabId;
  final TerminalSplitNodeId nodeId;
  final double fraction;
}

final class _TerminalNativeMinimumSize {
  const _TerminalNativeMinimumSize({required this.width, required this.height});

  final double width;
  final double height;
}
