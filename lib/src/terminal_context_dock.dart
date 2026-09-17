import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_action_registry.dart';
import 'terminal_application_state.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_pane.dart';

abstract final class TerminalContextDockLimits {
  static const int maximumQueryUnits = 256;
  static const int maximumResults = 512;
  static const int defaultPageStep = 10;
  static const double minimumWidth = 220;
  static const double defaultWidth = 380;
  static const double maximumWidth = 640;
}

final class TerminalContextDockLimitException implements Exception {
  const TerminalContextDockLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final String kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalContextDockLimitException: $kind has $actual units; maximum is '
      '$maximum';
}

enum TerminalContextDockInputOwner { terminal, navigator }

enum TerminalContextDockNavigatorMode { search, goTo, move }

enum TerminalContextDockTreeIntent { collapse, expand, toggle }

enum TerminalContextDockBoundaryDirection { left, right }

/// Immutable search/list state retained independently for one terminal pane.
final class TerminalContextDockPaneSnapshot {
  const TerminalContextDockPaneSnapshot({
    required this.paneId,
    required this.navigatorMode,
    required this.showHiddenEntries,
    required this.searchQuery,
    required this.goToQuery,
    required this.resultCount,
    required this.selectedResultIndex,
    required this.querySelectionGeneration,
  });

  final PaneId paneId;
  final TerminalContextDockNavigatorMode navigatorMode;
  final bool showHiddenEntries;
  final String searchQuery;
  final String goToQuery;
  final int resultCount;
  final int selectedResultIndex;
  final int querySelectionGeneration;

  String get query => switch (navigatorMode) {
    TerminalContextDockNavigatorMode.search => searchQuery,
    TerminalContextDockNavigatorMode.goTo => goToQuery,
    TerminalContextDockNavigatorMode.move => '',
  };

  bool get acceptsQuery =>
      navigatorMode != TerminalContextDockNavigatorMode.move;
}

/// Immutable window-owned Context Dock presentation and input state.
final class TerminalContextDockWindowSnapshot {
  const TerminalContextDockWindowSnapshot({
    required this.windowId,
    required this.targetPaneId,
    required this.isVisible,
    required this.width,
    required this.inputOwner,
    required this.generation,
    required this.pane,
  });

  final TerminalWindowId windowId;
  final PaneId targetPaneId;
  final bool isVisible;
  final double width;
  final TerminalContextDockInputOwner inputOwner;
  final int generation;
  final TerminalContextDockPaneSnapshot pane;

  bool get navigatorOwnsInput =>
      inputOwner == TerminalContextDockInputOwner.navigator;
}

/// Generation-bound request which a native presenter must revalidate.
final class TerminalContextDockFocusRequest {
  const TerminalContextDockFocusRequest({
    required this.windowId,
    required this.paneId,
    required this.stateGeneration,
    required this.querySelectionGeneration,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int stateGeneration;
  final int querySelectionGeneration;
}

/// Pure Dart authority for every window's Context Dock state.
///
/// A visible Dock may leave terminal input active. Navigator ownership always
/// implies visibility, but visibility never implies navigator ownership.
final class TerminalContextDockState {
  TerminalContextDockState({
    bool initiallyVisible = false,
    double initialWidth = TerminalContextDockLimits.defaultWidth,
  }) : _initiallyVisible = initiallyVisible,
       _initialWidth = initialWidth {
    _validateWidth(initialWidth);
  }

  bool _initiallyVisible;
  double _initialWidth;
  final Map<TerminalWindowId, _TerminalContextDockWindowState> _windows =
      <TerminalWindowId, _TerminalContextDockWindowState>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get windowCount => _windows.length;

  /// Updates future window defaults without undoing manual visibility choices.
  /// A changed configured width also supersedes window-owned keyboard widths.
  void configureDefaults({
    required bool initiallyVisible,
    required double width,
  }) {
    _ensureAlive();
    _validateWidth(width);
    final bool widthChanged = _initialWidth != width;
    _initiallyVisible = initiallyVisible;
    _initialWidth = width;
    if (widthChanged) {
      for (final _TerminalContextDockWindowState window in _windows.values) {
        setWidth(window.windowId, width);
      }
    }
  }

  static void _validateWidth(double width) {
    if (!width.isFinite ||
        width < TerminalContextDockLimits.minimumWidth ||
        width > TerminalContextDockLimits.maximumWidth) {
      throw ArgumentError.value(
        width,
        'width',
        'must be within the Dock width bounds',
      );
    }
  }

  TerminalContextDockWindowSnapshot? snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed) return null;
    final _TerminalContextDockWindowState? window = _windows[windowId];
    return window == null ? null : _snapshot(window);
  }

  /// Reconciles retained state with standard application windows and panes.
  bool synchronize(TerminalApplicationState applicationState) {
    _ensureAlive();
    if (applicationState.isDisposed) {
      final bool changed = _windows.isNotEmpty;
      _windows.clear();
      return changed;
    }
    final List<TerminalWindowState> applicationWindows = applicationState
        .windows
        .where(
          (TerminalWindowState window) =>
              window.role == TerminalWindowRole.standard,
        )
        .toList(growable: false);
    final Set<TerminalWindowId> retainedWindowIds = applicationWindows
        .map((TerminalWindowState window) => window.id)
        .toSet();
    var changed = false;
    for (final TerminalWindowId stale
        in _windows.keys
            .where((TerminalWindowId id) => !retainedWindowIds.contains(id))
            .toList(growable: false)) {
      _windows.remove(stale);
      changed = true;
    }
    for (final TerminalWindowState applicationWindow in applicationWindows) {
      final Set<PaneId> paneIds = <PaneId>{
        for (final TerminalTabState tab in applicationWindow.tabs)
          ...tab.paneIds,
      };
      final PaneId targetPaneId = applicationWindow.selectedTab.focusedPaneId;
      final _TerminalContextDockWindowState? existing =
          _windows[applicationWindow.id];
      if (existing == null) {
        _windows[applicationWindow.id] = _TerminalContextDockWindowState(
          windowId: applicationWindow.id,
          targetPaneId: targetPaneId,
          paneIds: paneIds,
          isVisible: _initiallyVisible,
          width: _initialWidth,
        );
        changed = true;
        continue;
      }
      var windowChanged = false;
      for (final PaneId stale
          in existing.panes.keys
              .where((PaneId id) => !paneIds.contains(id))
              .toList(growable: false)) {
        existing.panes.remove(stale);
        windowChanged = true;
      }
      for (final PaneId paneId in paneIds) {
        if (!existing.panes.containsKey(paneId)) {
          existing.panes[paneId] = _TerminalContextDockPaneState(paneId);
          windowChanged = true;
        }
      }
      if (existing.targetPaneId != targetPaneId) {
        existing.targetPaneId = targetPaneId;
        windowChanged = true;
      }
      if (windowChanged) {
        existing.generation++;
        changed = true;
      }
    }
    _validate();
    return changed;
  }

  /// Makes the Dock visible and requests native focus for one navigator mode.
  ///
  /// Input remains with its current owner until [confirmNavigatorInput]
  /// proves that the generation-bound native focus request succeeded.
  TerminalContextDockFocusRequest requestNavigatorFocus(
    TerminalWindowId windowId,
    PaneId paneId,
    TerminalContextDockNavigatorMode mode,
  ) {
    final _TerminalContextDockWindowState window = _requireTarget(
      windowId,
      paneId,
    );
    final _TerminalContextDockPaneState pane = window.panes[paneId]!;
    window.isVisible = true;
    _setNavigatorMode(pane, mode);
    window.generation++;
    _validate();
    return TerminalContextDockFocusRequest(
      windowId: windowId,
      paneId: paneId,
      stateGeneration: window.generation,
      querySelectionGeneration: pane.querySelectionGeneration,
    );
  }

  TerminalContextDockFocusRequest requestSearchFocus(
    TerminalWindowId windowId,
    PaneId paneId,
  ) => requestNavigatorFocus(
    windowId,
    paneId,
    TerminalContextDockNavigatorMode.search,
  );

  /// Switches an already-focused Navigator without another native focus hop.
  void setNavigatorMode(
    TerminalWindowId windowId,
    TerminalContextDockNavigatorMode mode, {
    bool requireNavigatorInput = false,
  }) {
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    if (requireNavigatorInput && !window.navigatorOwnsInput) {
      throw StateError('Context Dock navigator does not own input');
    }
    if (!_setNavigatorMode(window.targetPane, mode)) return;
    window.generation++;
    _validate();
  }

  /// Transfers input only when no hierarchy or Dock mutation made the request
  /// stale while native focus was being acquired.
  bool confirmNavigatorInput(TerminalContextDockFocusRequest request) {
    _ensureAlive();
    final _TerminalContextDockWindowState? window = _windows[request.windowId];
    if (window == null ||
        window.targetPaneId != request.paneId ||
        window.generation != request.stateGeneration ||
        window.panes[request.paneId]?.querySelectionGeneration !=
            request.querySelectionGeneration ||
        !window.isVisible) {
      return false;
    }
    if (window.inputOwner != TerminalContextDockInputOwner.navigator) {
      window.inputOwner = TerminalContextDockInputOwner.navigator;
      window.generation++;
    }
    _validate();
    return true;
  }

  void focusTerminal(TerminalWindowId windowId, PaneId paneId) {
    final _TerminalContextDockWindowState window = _requireTarget(
      windowId,
      paneId,
    );
    if (window.inputOwner == TerminalContextDockInputOwner.terminal) return;
    window.inputOwner = TerminalContextDockInputOwner.terminal;
    window.generation++;
    _validate();
  }

  void toggleVisibility(TerminalWindowId windowId, PaneId paneId) {
    final _TerminalContextDockWindowState window = _requireTarget(
      windowId,
      paneId,
    );
    if (window.navigatorOwnsInput) {
      throw StateError('terminal must own input before hiding Context Dock');
    }
    window.isVisible = !window.isVisible;
    window.generation++;
    _validate();
  }

  void toggleHiddenEntries(TerminalWindowId windowId, PaneId paneId) {
    final _TerminalContextDockWindowState window = _requireTarget(
      windowId,
      paneId,
    );
    window.targetPane.showHiddenEntries = !window.targetPane.showHiddenEntries;
    window.generation++;
    _validate();
  }

  /// Retains one bounded explicit width for this logical window.
  void setWidth(TerminalWindowId windowId, double width) {
    if (!width.isFinite ||
        width < TerminalContextDockLimits.minimumWidth ||
        width > TerminalContextDockLimits.maximumWidth) {
      throw ArgumentError.value(width, 'width', 'must be in Dock bounds');
    }
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    if ((window.width - width).abs() <= 1e-9) return;
    window.width = width;
    window.generation++;
    _validate();
  }

  void setQuery(
    TerminalWindowId windowId,
    String value, {
    bool requireNavigatorInput = false,
  }) {
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    if (requireNavigatorInput && !window.navigatorOwnsInput) {
      throw StateError('Context Dock navigator does not own input');
    }
    _validateQuery(value);
    final _TerminalContextDockPaneState pane = window.targetPane;
    if (!pane.acceptsQuery) {
      throw StateError('Move mode does not accept a query');
    }
    if (pane.query == value) return;
    pane
      ..setQuery(value)
      ..resultCount = 0
      ..selectedResultIndex = -1;
    window.generation++;
    _validate();
  }

  void appendQuery(TerminalWindowId windowId, String value) {
    final _TerminalContextDockWindowState window = _requireNavigator(windowId);
    setQuery(
      windowId,
      '${window.targetPane.query}$value',
      requireNavigatorInput: true,
    );
  }

  bool deleteLastQueryScalar(TerminalWindowId windowId) {
    final _TerminalContextDockWindowState window = _requireNavigator(windowId);
    final List<int> scalars = window.targetPane.query.runes.toList();
    if (scalars.isEmpty) return false;
    scalars.removeLast();
    setQuery(
      windowId,
      String.fromCharCodes(scalars),
      requireNavigatorInput: true,
    );
    return true;
  }

  void requestQuerySelection(TerminalWindowId windowId) {
    final _TerminalContextDockWindowState window = _requireNavigator(windowId);
    if (!window.targetPane.acceptsQuery) return;
    window.targetPane.querySelectionGeneration++;
    window.generation++;
    _validate();
  }

  void setResultCount(TerminalWindowId windowId, int resultCount) {
    if (resultCount < 0 ||
        resultCount > TerminalContextDockLimits.maximumResults) {
      throw TerminalContextDockLimitException(
        kind: 'result count',
        actual: resultCount,
        maximum: TerminalContextDockLimits.maximumResults,
      );
    }
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    final _TerminalContextDockPaneState pane = window.targetPane;
    final int selected = resultCount == 0
        ? -1
        : pane.selectedResultIndex.clamp(0, resultCount - 1);
    if (pane.resultCount == resultCount &&
        pane.selectedResultIndex == selected) {
      return;
    }
    pane
      ..resultCount = resultCount
      ..selectedResultIndex = selected;
    window.generation++;
    _validate();
  }

  bool moveSelection(TerminalWindowId windowId, int delta) {
    final _TerminalContextDockWindowState window = _requireNavigator(windowId);
    final _TerminalContextDockPaneState pane = window.targetPane;
    if (pane.resultCount == 0 || delta == 0) return false;
    final int selected = (pane.selectedResultIndex + delta).clamp(
      0,
      pane.resultCount - 1,
    );
    if (selected == pane.selectedResultIndex) return false;
    pane.selectedResultIndex = selected;
    window.generation++;
    _validate();
    return true;
  }

  void setSelectedResultIndex(TerminalWindowId windowId, int index) {
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    final _TerminalContextDockPaneState pane = window.targetPane;
    if (index < 0 || index >= pane.resultCount) {
      throw RangeError.range(
        index,
        0,
        pane.resultCount == 0 ? 0 : pane.resultCount - 1,
        'index',
      );
    }
    if (pane.selectedResultIndex == index) return;
    pane.selectedResultIndex = index;
    window.generation++;
    _validate();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _windows.clear();
  }

  _TerminalContextDockWindowState _requireNavigator(TerminalWindowId windowId) {
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    if (!window.navigatorOwnsInput) {
      throw StateError('Context Dock navigator does not own input');
    }
    return window;
  }

  _TerminalContextDockWindowState _requireTarget(
    TerminalWindowId windowId,
    PaneId paneId,
  ) {
    final _TerminalContextDockWindowState window = _requireWindow(windowId);
    if (window.targetPaneId != paneId || !window.panes.containsKey(paneId)) {
      throw StateError('pane $paneId is not the Context Dock target');
    }
    return window;
  }

  _TerminalContextDockWindowState _requireWindow(TerminalWindowId windowId) {
    _ensureAlive();
    return _windows[windowId] ??
        (throw StateError('window $windowId has no Context Dock state'));
  }

  TerminalContextDockWindowSnapshot _snapshot(
    _TerminalContextDockWindowState window,
  ) {
    final _TerminalContextDockPaneState pane = window.targetPane;
    return TerminalContextDockWindowSnapshot(
      windowId: window.windowId,
      targetPaneId: window.targetPaneId,
      isVisible: window.isVisible,
      width: window.width,
      inputOwner: window.inputOwner,
      generation: window.generation,
      pane: TerminalContextDockPaneSnapshot(
        paneId: pane.paneId,
        navigatorMode: pane.navigatorMode,
        showHiddenEntries: pane.showHiddenEntries,
        searchQuery: pane.searchQuery,
        goToQuery: pane.goToQuery,
        resultCount: pane.resultCount,
        selectedResultIndex: pane.selectedResultIndex,
        querySelectionGeneration: pane.querySelectionGeneration,
      ),
    );
  }

  static bool _setNavigatorMode(
    _TerminalContextDockPaneState pane,
    TerminalContextDockNavigatorMode mode,
  ) {
    if (pane.navigatorMode == mode) return false;
    pane
      ..navigatorMode = mode
      ..resultCount = 0
      ..selectedResultIndex = -1;
    return true;
  }

  void _validateQuery(String value) {
    if (value.length > TerminalContextDockLimits.maximumQueryUnits) {
      throw TerminalContextDockLimitException(
        kind: 'query',
        actual: value.length,
        maximum: TerminalContextDockLimits.maximumQueryUnits,
      );
    }
    if (value.runes.any((int scalar) => scalar < 0x20 || scalar == 0x7f)) {
      throw ArgumentError.value(value, 'value', 'must not contain controls');
    }
  }

  void _validate() {
    if (_windows.length > TerminalApplicationStateLimits.maximumWindows) {
      throw StateError('Context Dock window bound exceeded');
    }
    var paneCount = 0;
    for (final _TerminalContextDockWindowState window in _windows.values) {
      paneCount += window.panes.length;
      if (!window.panes.containsKey(window.targetPaneId)) {
        throw StateError('Context Dock target pane is not retained');
      }
      if (window.navigatorOwnsInput && !window.isVisible) {
        throw StateError('hidden Context Dock cannot own input');
      }
      if (!window.width.isFinite ||
          window.width < TerminalContextDockLimits.minimumWidth ||
          window.width > TerminalContextDockLimits.maximumWidth) {
        throw StateError('Context Dock width is outside policy bounds');
      }
      for (final _TerminalContextDockPaneState pane in window.panes.values) {
        _validateQuery(pane.searchQuery);
        _validateQuery(pane.goToQuery);
        if (pane.resultCount < 0 ||
            pane.resultCount > TerminalContextDockLimits.maximumResults ||
            (pane.resultCount == 0 && pane.selectedResultIndex != -1) ||
            (pane.resultCount > 0 &&
                (pane.selectedResultIndex < 0 ||
                    pane.selectedResultIndex >= pane.resultCount))) {
          throw StateError('Context Dock result selection is inconsistent');
        }
      }
    }
    if (paneCount > TerminalApplicationStateLimits.maximumTotalPanes) {
      throw StateError('Context Dock pane bound exceeded');
    }
  }

  void _ensureAlive() {
    if (_isDisposed) throw StateError('Context Dock state is disposed');
  }
}

final class _TerminalContextDockWindowState {
  _TerminalContextDockWindowState({
    required this.windowId,
    required this.targetPaneId,
    required Set<PaneId> paneIds,
    required this.isVisible,
    required this.width,
  }) : panes = <PaneId, _TerminalContextDockPaneState>{
         for (final PaneId paneId in paneIds)
           paneId: _TerminalContextDockPaneState(paneId),
       };

  final TerminalWindowId windowId;
  final Map<PaneId, _TerminalContextDockPaneState> panes;
  PaneId targetPaneId;
  bool isVisible;
  double width;
  TerminalContextDockInputOwner inputOwner =
      TerminalContextDockInputOwner.terminal;
  int generation = 1;

  bool get navigatorOwnsInput =>
      inputOwner == TerminalContextDockInputOwner.navigator;
  _TerminalContextDockPaneState get targetPane => panes[targetPaneId]!;
}

final class _TerminalContextDockPaneState {
  _TerminalContextDockPaneState(this.paneId);

  final PaneId paneId;
  TerminalContextDockNavigatorMode navigatorMode =
      TerminalContextDockNavigatorMode.move;
  bool showHiddenEntries = true;
  String searchQuery = '';
  String goToQuery = '';
  int resultCount = 0;
  int selectedResultIndex = -1;
  int querySelectionGeneration = 0;

  String get query => switch (navigatorMode) {
    TerminalContextDockNavigatorMode.search => searchQuery,
    TerminalContextDockNavigatorMode.goTo => goToQuery,
    TerminalContextDockNavigatorMode.move => '',
  };

  bool get acceptsQuery =>
      navigatorMode != TerminalContextDockNavigatorMode.move;

  void setQuery(String value) {
    switch (navigatorMode) {
      case TerminalContextDockNavigatorMode.search:
        searchQuery = value;
        return;
      case TerminalContextDockNavigatorMode.goTo:
        goToQuery = value;
        return;
      case TerminalContextDockNavigatorMode.move:
        throw StateError('Move mode does not accept a query');
    }
  }
}

typedef TerminalContextDockFocusRequester = void Function(
  TerminalContextDockFocusRequest request,
);

/// Binds shared application actions to the Context Dock state authority.
final class TerminalContextDockActionCoordinator {
  TerminalContextDockActionCoordinator({
    required this.applicationState,
    required this.dockState,
    required TerminalContextDockFocusRequester focusNavigator,
    required TerminalContextDockFocusRequester focusTerminal,
    bool Function()? canFocusNavigator,
    bool Function()? shouldConsumeNavigatorRequest,
    bool Function(TerminalContextDockBoundaryDirection direction)?
    canMoveBoundary,
    bool Function(TerminalContextDockBoundaryDirection direction)? moveBoundary,
    void Function()? onChanged,
  }) : _focusNavigator = focusNavigator,
       _focusTerminal = focusTerminal,
       _canFocusNavigator = canFocusNavigator ?? _alwaysTrue,
       _shouldConsumeNavigatorRequest =
           shouldConsumeNavigatorRequest ?? _alwaysFalse,
       _canMoveBoundary = canMoveBoundary,
       _moveBoundary = moveBoundary,
       _onChanged = onChanged {
    synchronize();
  }

  final TerminalApplicationState applicationState;
  final TerminalContextDockState dockState;
  final TerminalContextDockFocusRequester _focusNavigator;
  final TerminalContextDockFocusRequester _focusTerminal;
  final bool Function() _canFocusNavigator;
  final bool Function() _shouldConsumeNavigatorRequest;
  final bool Function(TerminalContextDockBoundaryDirection direction)?
  _canMoveBoundary;
  final bool Function(TerminalContextDockBoundaryDirection direction)?
  _moveBoundary;
  final void Function()? _onChanged;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  List<TerminalActionRegistration> registrations() =>
      <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.searchFilesAndFolders,
          isAvailable: _canEnterNavigator,
          handler: _search,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.goToFileOrFolder,
          isAvailable: _canEnterNavigator,
          handler: _goTo,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveInDirectoryNavigator,
          isAvailable: _canEnterNavigator,
          handler: _moveInNavigator,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.focusTerminal,
          isAvailable: _canReturnToTerminal,
          handler: _returnToTerminal,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.toggleContextDock,
          isAvailable: _canToggle,
          handler: _toggle,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.toggleHiddenFiles,
          isAvailable: _canToggle,
          handler: _toggleHiddenEntries,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveContextDockBoundaryLeft,
          isAvailable: () =>
              _canMove(TerminalContextDockBoundaryDirection.left),
          handler: () =>
              _moveBoundaryIn(TerminalContextDockBoundaryDirection.left),
        ),
        TerminalActionRegistration(
          id: TerminalActionId.moveContextDockBoundaryRight,
          isAvailable: () =>
              _canMove(TerminalContextDockBoundaryDirection.right),
          handler: () =>
              _moveBoundaryIn(TerminalContextDockBoundaryDirection.right),
        ),
      ];

  void synchronize() {
    if (_isDisposed || dockState.isDisposed) return;
    if (dockState.synchronize(applicationState)) _onChanged?.call();
  }

  void dispose() {
    _isDisposed = true;
  }

  bool _canEnterNavigator() =>
      _activeTarget() != null &&
      (_readCanFocusNavigator() || _readShouldConsumeNavigatorRequest());

  bool _canReturnToTerminal() {
    final _TerminalContextDockTarget? target = _activeTarget();
    if (target == null) return false;
    final TerminalContextDockWindowSnapshot? snapshot = dockState
        .snapshotForWindow(target.windowId);
    return snapshot?.targetPaneId == target.paneId &&
        snapshot!.navigatorOwnsInput;
  }

  bool _canToggle() => _activeTarget() != null;

  bool _canMove(TerminalContextDockBoundaryDirection direction) =>
      !applicationState.mutationInProgress &&
      _activeTarget() != null &&
      _moveBoundary != null &&
      (_canMoveBoundary?.call(direction) ?? false);

  void _moveBoundaryIn(TerminalContextDockBoundaryDirection direction) {
    if (!_canMove(direction)) return;
    if (_moveBoundary!(direction)) _onChanged?.call();
  }

  void _search() => _focusMode(TerminalContextDockNavigatorMode.search);

  void _goTo() => _focusMode(TerminalContextDockNavigatorMode.goTo);

  void _moveInNavigator() => _focusMode(TerminalContextDockNavigatorMode.move);

  void _focusMode(TerminalContextDockNavigatorMode mode) {
    synchronize();
    final _TerminalContextDockTarget target = _requireActiveTarget();
    if (!_readCanFocusNavigator()) {
      if (_readShouldConsumeNavigatorRequest()) {
        _onChanged?.call();
        return;
      }
      throw StateError('Context Dock navigator focus is unavailable');
    }
    final TerminalContextDockFocusRequest requested = dockState
        .requestNavigatorFocus(target.windowId, target.paneId, mode);
    _onChanged?.call();
    final _TerminalContextDockTarget? projected = _activeTarget();
    final TerminalContextDockWindowSnapshot? projectedDock = dockState
        .snapshotForWindow(target.windowId);
    if (projected == null ||
        projected.windowId != requested.windowId ||
        projected.paneId != requested.paneId ||
        projectedDock == null ||
        !projectedDock.isVisible ||
        projectedDock.targetPaneId != requested.paneId ||
        projectedDock.pane.navigatorMode != mode ||
        projectedDock.pane.querySelectionGeneration !=
            requested.querySelectionGeneration) {
      throw StateError('Context Dock navigator projection became stale');
    }
    final TerminalContextDockFocusRequest request = _focusRequest(
      projectedDock,
    );
    _focusNavigator(request);
    final _TerminalContextDockTarget? current = _activeTarget();
    if (current == null ||
        current.windowId != request.windowId ||
        current.paneId != request.paneId ||
        !dockState.confirmNavigatorInput(request)) {
      throw StateError('Context Dock navigator focus request became stale');
    }
    _onChanged?.call();
  }

  void _returnToTerminal() {
    synchronize();
    final _TerminalContextDockTarget target = _requireActiveTarget();
    final TerminalContextDockWindowSnapshot snapshot =
        dockState.snapshotForWindow(target.windowId) ??
        (throw StateError('Context Dock window state is unavailable'));
    if (!snapshot.navigatorOwnsInput) {
      throw StateError('Context Dock navigator does not own input');
    }
    final TerminalContextDockFocusRequest request = _focusRequest(snapshot);
    _focusTerminal(request);
    final _TerminalContextDockTarget? current = _activeTarget();
    if (current == null ||
        current.windowId != request.windowId ||
        current.paneId != request.paneId) {
      throw StateError('terminal focus request became stale');
    }
    dockState.focusTerminal(target.windowId, target.paneId);
    _onChanged?.call();
  }

  void _toggle() {
    synchronize();
    final _TerminalContextDockTarget target = _requireActiveTarget();
    TerminalContextDockWindowSnapshot snapshot =
        dockState.snapshotForWindow(target.windowId) ??
        (throw StateError('Context Dock window state is unavailable'));
    if (snapshot.navigatorOwnsInput) {
      final TerminalContextDockFocusRequest request = _focusRequest(snapshot);
      _focusTerminal(request);
      final _TerminalContextDockTarget? current = _activeTarget();
      if (current == null ||
          current.windowId != request.windowId ||
          current.paneId != request.paneId) {
        throw StateError('terminal focus request became stale');
      }
      dockState.focusTerminal(target.windowId, target.paneId);
      snapshot = dockState.snapshotForWindow(target.windowId)!;
    }
    dockState.toggleVisibility(snapshot.windowId, snapshot.targetPaneId);
    _onChanged?.call();
  }

  void _toggleHiddenEntries() {
    synchronize();
    final _TerminalContextDockTarget target = _requireActiveTarget();
    dockState.toggleHiddenEntries(target.windowId, target.paneId);
    _onChanged?.call();
  }

  TerminalContextDockFocusRequest _focusRequest(
    TerminalContextDockWindowSnapshot snapshot,
  ) => TerminalContextDockFocusRequest(
    windowId: snapshot.windowId,
    paneId: snapshot.targetPaneId,
    stateGeneration: snapshot.generation,
    querySelectionGeneration: snapshot.pane.querySelectionGeneration,
  );

  _TerminalContextDockTarget _requireActiveTarget() =>
      _activeTarget() ??
      (throw StateError('no live standard terminal owns Context Dock'));

  _TerminalContextDockTarget? _activeTarget() {
    if (_isDisposed || dockState.isDisposed || applicationState.isDisposed) {
      return null;
    }
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) {
      return null;
    }
    final PaneId paneId = window.selectedTab.focusedPaneId;
    if (applicationState.paneForId(paneId)?.isLive != true) return null;
    return _TerminalContextDockTarget(window.id, paneId);
  }

  bool _readCanFocusNavigator() {
    try {
      return _canFocusNavigator();
    } on Object {
      return false;
    }
  }

  bool _readShouldConsumeNavigatorRequest() {
    try {
      return _shouldConsumeNavigatorRequest();
    } on Object {
      return false;
    }
  }

  static bool _alwaysTrue() => true;
  static bool _alwaysFalse() => false;
}

final class _TerminalContextDockTarget {
  const _TerminalContextDockTarget(this.windowId, this.paneId);

  final TerminalWindowId windowId;
  final PaneId paneId;
}

enum TerminalContextDockKeyDisposition {
  notOwned,
  consumed,
  queryUpdated,
  querySelectionRequested,
  selectionChanged,
  treeIntentRequested,
  pathCopyDispatched,
  pathInsertionRequested,
  terminalFocusDispatched,
  boundaryMoveDispatched,
  overflow,
}

final class TerminalContextDockKeyResult {
  const TerminalContextDockKeyResult({
    required this.disposition,
    this.treeIntent,
    this.dispatchResult,
  });

  final TerminalContextDockKeyDisposition disposition;
  final TerminalContextDockTreeIntent? treeIntent;
  final TerminalActionDispatchResult? dispatchResult;

  bool get isConsumed =>
      disposition != TerminalContextDockKeyDisposition.notOwned;
}

/// Owns all key events delivered while the navigator is first responder.
///
/// Native application key equivalents run before this controller. Every
/// remaining navigator-owned event is consumed, including unsupported keys,
/// and therefore cannot fall through to the terminal encoder.
final class TerminalContextDockKeyController {
  TerminalContextDockKeyController({
    required this.state,
    required this.dispatcher,
    this.onChanged,
    this.pageStep = TerminalContextDockLimits.defaultPageStep,
    TerminalKeyBindingEngine Function()? keyBindings,
  }) : _keyBindings = keyBindings ?? TerminalKeyBindingEngine.standard {
    if (pageStep <= 0 || pageStep > TerminalContextDockLimits.maximumResults) {
      throw ArgumentError.value(pageStep, 'pageStep', 'must be in bounds');
    }
  }

  final TerminalContextDockState state;
  final TerminalActionDispatcher dispatcher;
  final void Function()? onChanged;
  final int pageStep;
  final TerminalKeyBindingEngine Function() _keyBindings;

  Future<TerminalContextDockKeyResult> handle(
    TerminalWindowId windowId,
    AppKitKeyEvent event,
  ) async {
    final TerminalContextDockWindowSnapshot? snapshot = state.snapshotForWindow(
      windowId,
    );
    if (snapshot == null || !snapshot.navigatorOwnsInput) {
      return const TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.notOwned,
      );
    }
    if (event.kind != AppKitKeyEventKind.down) {
      return const TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.consumed,
      );
    }
    final TerminalKeyEvent key = TerminalAppKitKeyAdapter.adapt(event);
    final TerminalActionId? boundAction = _keyBindings()
        .resolve(key)
        .applicationAction;
    if (boundAction == TerminalActionId.moveContextDockBoundaryLeft ||
        boundAction == TerminalActionId.moveContextDockBoundaryRight) {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(
        boundAction!,
      );
      return TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.boundaryMoveDispatched,
        dispatchResult: result,
      );
    }
    if (key.physicalKey == TerminalPhysicalKey.escape) {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(
        TerminalActionId.focusTerminal,
      );
      return TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.terminalFocusDispatched,
        dispatchResult: result,
      );
    }
    if (_hasNoRoutingModifiers(key)) {
      switch (key.physicalKey) {
        case TerminalPhysicalKey.backspace:
          if (!snapshot.pane.acceptsQuery) {
            return const TerminalContextDockKeyResult(
              disposition: TerminalContextDockKeyDisposition.consumed,
            );
          }
          if (state.deleteLastQueryScalar(windowId)) onChanged?.call();
          return const TerminalContextDockKeyResult(
            disposition: TerminalContextDockKeyDisposition.queryUpdated,
          );
        case TerminalPhysicalKey.arrowUp:
          return _move(windowId, -1);
        case TerminalPhysicalKey.arrowDown:
          return _move(windowId, 1);
        case TerminalPhysicalKey.pageUp:
          return _move(windowId, -pageStep);
        case TerminalPhysicalKey.pageDown:
          return _move(windowId, pageStep);
        case TerminalPhysicalKey.enter:
          return const TerminalContextDockKeyResult(
            disposition: TerminalContextDockKeyDisposition.treeIntentRequested,
            treeIntent: TerminalContextDockTreeIntent.toggle,
          );
        default:
          break;
      }
    }
    if (key.modifiers.command &&
        !key.modifiers.control &&
        !key.modifiers.option &&
        !key.modifiers.shift) {
      switch (key.physicalKey) {
        case TerminalPhysicalKey.keyA:
          if (!snapshot.pane.acceptsQuery) {
            return const TerminalContextDockKeyResult(
              disposition: TerminalContextDockKeyDisposition.consumed,
            );
          }
          state.requestQuerySelection(windowId);
          onChanged?.call();
          return const TerminalContextDockKeyResult(
            disposition:
                TerminalContextDockKeyDisposition.querySelectionRequested,
          );
        case TerminalPhysicalKey.keyC:
          final TerminalActionDispatchResult result = await dispatcher.dispatch(
            TerminalActionId.copy,
          );
          return TerminalContextDockKeyResult(
            disposition: TerminalContextDockKeyDisposition.pathCopyDispatched,
            dispatchResult: result,
          );
        case TerminalPhysicalKey.arrowLeft:
          return const TerminalContextDockKeyResult(
            disposition: TerminalContextDockKeyDisposition.treeIntentRequested,
            treeIntent: TerminalContextDockTreeIntent.collapse,
          );
        case TerminalPhysicalKey.arrowRight:
          return const TerminalContextDockKeyResult(
            disposition: TerminalContextDockKeyDisposition.treeIntentRequested,
            treeIntent: TerminalContextDockTreeIntent.expand,
          );
        default:
          break;
      }
    }
    if (key.physicalKey == TerminalPhysicalKey.enter &&
        key.modifiers.option &&
        !key.modifiers.command &&
        !key.modifiers.control &&
        !key.modifiers.shift) {
      return const TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.pathInsertionRequested,
      );
    }
    if (!key.modifiers.command &&
        !key.modifiers.control &&
        snapshot.pane.acceptsQuery &&
        key.text.isNotEmpty &&
        key.text.runes.every(
          (int scalar) => scalar >= 0x20 && scalar != 0x7f,
        )) {
      try {
        state.appendQuery(windowId, key.text);
      } on TerminalContextDockLimitException {
        return const TerminalContextDockKeyResult(
          disposition: TerminalContextDockKeyDisposition.overflow,
        );
      }
      onChanged?.call();
      return const TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.queryUpdated,
      );
    }
    return const TerminalContextDockKeyResult(
      disposition: TerminalContextDockKeyDisposition.consumed,
    );
  }

  TerminalContextDockKeyResult _move(TerminalWindowId windowId, int delta) {
    if (!state.moveSelection(windowId, delta)) {
      return const TerminalContextDockKeyResult(
        disposition: TerminalContextDockKeyDisposition.consumed,
      );
    }
    onChanged?.call();
    return const TerminalContextDockKeyResult(
      disposition: TerminalContextDockKeyDisposition.selectionChanged,
    );
  }

  bool _hasNoRoutingModifiers(TerminalKeyEvent key) =>
      !key.modifiers.command &&
      !key.modifiers.control &&
      !key.modifiers.option &&
      !key.modifiers.shift;
}
