import 'terminal_action_registry.dart';
import 'terminal_application_state.dart';
import 'terminal_pane.dart';

typedef TerminalProductPaneConfigurationFactory =
    TerminalPaneConfiguration Function(
      PaneId? inheritanceSourcePaneId, {
      String? workingDirectoryOverride,
    });
typedef TerminalProductHierarchyReconciler = void Function();
typedef TerminalProductHierarchyMutationAdmission = bool Function();
typedef TerminalProductDividerMovementAvailability = bool Function(
  TerminalSplitDividerDirection direction,
);
typedef TerminalProductDividerMover = bool Function(
  TerminalSplitDividerDirection direction,
);
typedef TerminalProductPaneFocusAvailability = bool Function(
  TerminalPaneFocusDirection direction,
);
typedef TerminalProductPaneFocuser = bool Function(
  TerminalPaneFocusDirection direction,
);

/// Terminal-owned user actions over the logical and native hierarchy.
///
/// The coordinator contains no AppKit types. The product supplies a
/// reconciliation callback backed by [TerminalNativeHierarchyAdapter], while
/// tests can use a deterministic counter.
final class TerminalProductHierarchyActionCoordinator {
  TerminalProductHierarchyActionCoordinator({
    required this.state,
    required TerminalProductPaneConfigurationFactory configurationFactory,
    required TerminalProductHierarchyReconciler reconcile,
    required TerminalProductDividerMovementAvailability canMoveDivider,
    required TerminalProductDividerMover moveDivider,
    required TerminalProductPaneFocusAvailability canFocusPane,
    required TerminalProductPaneFocuser focusPane,
    TerminalProductHierarchyMutationAdmission? canMutate,
    void Function()? onChanged,
  }) : _configurationFactory = configurationFactory,
       _reconcile = reconcile,
       _canMoveDivider = canMoveDivider,
       _moveDivider = moveDivider,
       _canFocusPane = canFocusPane,
       _focusPane = focusPane,
       _canMutate = canMutate,
       _onChanged = onChanged;

  final TerminalApplicationState state;
  final TerminalProductPaneConfigurationFactory _configurationFactory;
  final TerminalProductHierarchyReconciler _reconcile;
  final TerminalProductDividerMovementAvailability _canMoveDivider;
  final TerminalProductDividerMover _moveDivider;
  final TerminalProductPaneFocusAvailability _canFocusPane;
  final TerminalProductPaneFocuser _focusPane;
  final TerminalProductHierarchyMutationAdmission? _canMutate;
  final void Function()? _onChanged;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Creates as many fresh tabs as current product limits admit.
  Future<int> createTabsAtWorkingDirectories(
    Iterable<String> workingDirectories,
  ) async {
    var created = 0;
    for (final String workingDirectory in workingDirectories) {
      if (!_canCreateTab()) break;
      final TerminalWindowState window = _requireActiveWindow();
      final TerminalTabState tab = await state.createTab(
        window.id,
        _configurationFactory(
          window.selectedTab.focusedPaneId,
          workingDirectoryOverride: workingDirectory,
        ),
      );
      await _startAndProject(tab.focusedPaneId);
      created++;
    }
    return created;
  }

  /// Creates as many fresh windows as current product limits admit.
  Future<int> createWindowsAtWorkingDirectories(
    Iterable<String> workingDirectories,
  ) async {
    var created = 0;
    for (final String workingDirectory in workingDirectories) {
      if (!_canCreateWindow()) break;
      final TerminalWindowState window = await state.createWindow(
        _configurationFactory(
          _focusedPaneId,
          workingDirectoryOverride: workingDirectory,
        ),
      );
      await _startAndProject(window.selectedTab.focusedPaneId);
      created++;
    }
    return created;
  }

  List<TerminalActionRegistration> registrations() =>
      <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.newWindow,
          isAvailable: _canCreateWindow,
          handler: _createWindow,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.newTab,
          isAvailable: _canCreateTab,
          handler: _createTab,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.splitPaneRight,
          isAvailable: _canSplitPane,
          handler: () => _splitPane(TerminalSplitAxis.horizontal),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.splitPaneDown,
          isAvailable: _canSplitPane,
          handler: () => _splitPane(TerminalSplitAxis.vertical),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.togglePaneZoom,
          isAvailable: _hasSplitPane,
          handler: _togglePaneZoom,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.equalizeSplits,
          isAvailable: _hasSplitPane,
          handler: _equalizeSplits,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveDividerLeft,
          isAvailable: () =>
              _canMoveSplitDivider(TerminalSplitDividerDirection.left),
          handler: () => _moveSplitDivider(TerminalSplitDividerDirection.left),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveDividerRight,
          isAvailable: () =>
              _canMoveSplitDivider(TerminalSplitDividerDirection.right),
          handler: () => _moveSplitDivider(TerminalSplitDividerDirection.right),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveDividerUp,
          isAvailable: () =>
              _canMoveSplitDivider(TerminalSplitDividerDirection.up),
          handler: () => _moveSplitDivider(TerminalSplitDividerDirection.up),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveDividerDown,
          isAvailable: () =>
              _canMoveSplitDivider(TerminalSplitDividerDirection.down),
          handler: () => _moveSplitDivider(TerminalSplitDividerDirection.down),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusPaneLeft,
          isAvailable: () =>
              _canFocusPaneDirection(TerminalPaneFocusDirection.left),
          handler: () => _focusPaneDirection(TerminalPaneFocusDirection.left),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusPaneRight,
          isAvailable: () =>
              _canFocusPaneDirection(TerminalPaneFocusDirection.right),
          handler: () => _focusPaneDirection(TerminalPaneFocusDirection.right),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusPaneUp,
          isAvailable: () =>
              _canFocusPaneDirection(TerminalPaneFocusDirection.up),
          handler: () => _focusPaneDirection(TerminalPaneFocusDirection.up),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusPaneDown,
          isAvailable: () =>
              _canFocusPaneDirection(TerminalPaneFocusDirection.down),
          handler: () => _focusPaneDirection(TerminalPaneFocusDirection.down),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusPreviousPane,
          isAvailable: _hasSplitPane,
          handler: () => _traversePane(TerminalPaneFocusTraversal.previous),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusNextPane,
          isAvailable: _hasSplitPane,
          handler: () => _traversePane(TerminalPaneFocusTraversal.next),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.selectPreviousTab,
          isAvailable: _hasMultipleTabs,
          handler: () => _selectAdjacentTab(-1),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.selectNextTab,
          isAvailable: _hasMultipleTabs,
          handler: () => _selectAdjacentTab(1),
        ),
      ];

  void dispose() {
    _disposed = true;
  }

  bool _canCreateWindow() =>
      _isMutable &&
      state.windowCount < TerminalApplicationStateLimits.maximumWindows &&
      _hasPaneCapacity;

  bool _canCreateTab() {
    final TerminalWindowState? window = _activeWindow;
    return window != null &&
        window.tabs.length <
            TerminalApplicationStateLimits.maximumTabsPerWindow &&
        _hasPaneCapacity;
  }

  bool _canSplitPane() {
    final TerminalTabState? tab = _activeTab;
    return tab != null &&
        tab.paneIds.length <
            TerminalApplicationStateLimits.maximumPanesPerTab &&
        _hasPaneCapacity;
  }

  bool _hasSplitPane() => _isMutable && (_activeTab?.paneIds.length ?? 0) > 1;

  bool _hasMultipleTabs() =>
      _isMutable && (_activeWindow?.tabs.length ?? 0) > 1;

  bool _canMoveSplitDivider(TerminalSplitDividerDirection direction) =>
      _isMutable && _canMoveDivider(direction);

  bool _canFocusPaneDirection(TerminalPaneFocusDirection direction) =>
      _isMutable && _canFocusPane(direction);

  bool get _isMutable =>
      !_disposed && !state.isDisposed && (_canMutate?.call() ?? true);
  bool get _hasPaneCapacity =>
      state.paneCount < TerminalApplicationStateLimits.maximumTotalPanes;
  TerminalWindowState? get _activeWindow =>
      _isMutable ? state.activeWindow : null;
  TerminalTabState? get _activeTab => _activeWindow?.selectedTab;
  PaneId? get _focusedPaneId => _activeTab?.focusedPaneId;

  Future<void> _createWindow() async {
    final PaneId? source = _focusedPaneId;
    final TerminalWindowState window = await state.createWindow(
      _configurationFactory(source),
    );
    await _startAndProject(window.selectedTab.focusedPaneId);
  }

  Future<void> _createTab() async {
    final TerminalWindowState window = _requireActiveWindow();
    final PaneId source = window.selectedTab.focusedPaneId;
    final TerminalTabState tab = await state.createTab(
      window.id,
      _configurationFactory(source),
    );
    await _startAndProject(tab.focusedPaneId);
  }

  Future<void> _splitPane(TerminalSplitAxis axis) async {
    final PaneId source = _requireFocusedPane();
    final TerminalPane pane = await state.splitPane(
      source,
      _configurationFactory(source),
      axis: axis,
    );
    await _startAndProject(pane.id);
  }

  Future<void> _startAndProject(PaneId paneId) async {
    final TerminalPane pane = state.paneForId(paneId)!;
    try {
      await pane.start();
      _project();
    } on Object catch (error, stackTrace) {
      if (state.paneForId(paneId) != null) {
        await state.removePane(paneId);
        _reconcile();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _togglePaneZoom() {
    final TerminalTabState tab = _requireActiveTab();
    state.setPaneZoom(tab.id, tab.isZoomed ? null : tab.focusedPaneId);
    _project();
  }

  void _equalizeSplits() {
    final TerminalTabState tab = _requireActiveTab();
    state.equalizeSplits(tab.id);
    _project();
  }

  void _moveSplitDivider(TerminalSplitDividerDirection direction) {
    if (!_moveDivider(direction)) {
      throw StateError('split divider is no longer movable');
    }
    _project();
  }

  void _focusPaneDirection(TerminalPaneFocusDirection direction) {
    if (!_focusPane(direction)) {
      throw StateError('directional pane focus is no longer available');
    }
    _project();
  }

  void _traversePane(TerminalPaneFocusTraversal direction) {
    final TerminalTabState tab = _requireActiveTab();
    state.traversePaneFocus(tab.id, direction: direction);
    _project();
  }

  void _selectAdjacentTab(int delta) {
    final TerminalWindowState window = _requireActiveWindow();
    final List<TerminalTabId> tabIds = window.tabIds;
    final int selected = tabIds.indexOf(window.selectedTabId);
    state.selectTab(window.id, tabIds[(selected + delta) % tabIds.length]);
    _project();
  }

  void _project() {
    _reconcile();
    _onChanged?.call();
  }

  TerminalWindowState _requireActiveWindow() =>
      _activeWindow ?? (throw StateError('no active terminal window'));

  TerminalTabState _requireActiveTab() =>
      _activeTab ?? (throw StateError('no active terminal tab'));

  PaneId _requireFocusedPane() =>
      _focusedPaneId ?? (throw StateError('no focused terminal pane'));
}
