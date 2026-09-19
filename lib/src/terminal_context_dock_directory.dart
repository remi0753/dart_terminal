import 'dart:async';
import 'dart:math' as math;

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';
import 'terminal_context_dock.dart';
import 'terminal_context_dock_path_handoff.dart';
import 'terminal_context_dock_process.dart';
import 'terminal_directory_snapshot.dart';
import 'terminal_file_search.dart';
import 'terminal_localization.dart';
import 'terminal_pane.dart';

abstract final class TerminalContextDockDirectoryLimits {
  static const int maximumExpandedDirectoriesPerPane = 32;
  static const int maximumRootEntries =
      TerminalContextDockLimits.maximumResults;
  static const int maximumChildEntries = 128;
  static const int maximumRetainedChildSnapshotsPerWindow = 32;
  static const int maximumRootPathBytes = 512 * 1024;
  static const int maximumChildPathBytes = 128 * 1024;
  static const double dividerThickness = 1;
  static const double minimumTerminalWidth = 240;
  static const double preferredDetailsHeight = 210;
  static const double minimumNavigatorHeight = 120;
  static const double minimumDetailsHeight = 140;
  static const Duration terminalChangeDebounce = Duration(milliseconds: 75);
}

typedef TerminalContextDockWorkingDirectoryResolver =
    TerminalWorkingDirectoryResolution Function(PaneId paneId, int generation);
typedef TerminalContextDockPaneObservationPolicy = bool Function(PaneId paneId);
typedef TerminalContextDockPathHandoffSnapshotResolver =
    TerminalContextDockPathHandoffSnapshot? Function(TerminalWindowId windowId);
typedef TerminalContextDockContentSnapshotResolver =
    TerminalContextDockContentSnapshot? Function(TerminalWindowId windowId);
typedef TerminalContextDockAppearanceResolver =
    TerminalContextDockAppearance? Function(PaneId paneId);

/// Presentation borrowed from the focused terminal, never from process data.
final class TerminalContextDockAppearance {
  factory TerminalContextDockAppearance.fromTerminal({
    required int foreground,
    required int background,
    required String fontFamily,
    required double fontSize,
    required double backgroundOpacity,
    required double horizontalPadding,
    required double verticalPadding,
    Iterable<TextEditorFontVariation> fontVariations =
        const <TextEditorFontVariation>[],
  }) {
    TextViewColor color(int rgb, {double alpha = 1}) => TextViewColor.sRgb(
      red: ((rgb >> 16) & 0xff) / 255,
      green: ((rgb >> 8) & 0xff) / 255,
      blue: (rgb & 0xff) / 255,
      alpha: alpha,
    );
    final double backdrop = _luminance(background);
    final double text = _luminance(foreground);
    final double contrast =
        (math.max(backdrop, text) + 0.05) / (math.min(backdrop, text) + 0.05);
    final int divider = contrast >= 3
        ? foreground
        : ((1.05 / (backdrop + 0.05)) >= ((backdrop + 0.05) / 0.05)
              ? 0xffffff
              : 0x000000);
    return TerminalContextDockAppearance._(
      font: fontFamily.isEmpty
          ? TextViewFont.monospacedSystem(size: fontSize)
          : TextViewFont.named(fontFamily, size: fontSize),
      foregroundColor: color(foreground),
      backgroundColor: color(background, alpha: backgroundOpacity),
      dividerColor: color(divider),
      padding: TextViewPadding(
        top: verticalPadding,
        bottom: verticalPadding,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      fontVariations: List<TextEditorFontVariation>.unmodifiable(
        fontVariations,
      ),
    );
  }

  const TerminalContextDockAppearance._({
    required this.font,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.dividerColor,
    required this.padding,
    required this.fontVariations,
  });
  final TextViewFont font;
  final TextViewColor foregroundColor;
  final TextViewColor backgroundColor;
  final TextViewColor dividerColor;
  final TextViewPadding padding;
  final List<TextEditorFontVariation> fontVariations;

  static double _luminance(int rgb) {
    double channel(int shift) {
      final double value = ((rgb >> shift) & 0xff) / 255;
      return value <= 0.04045
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }
}

enum TerminalContextDockDirectoryStatus {
  loading,
  ready,
  partial,
  empty,
  unavailable,
  remoteUnavailable,
  privacyUnavailable,
}

final class TerminalContextDockDirectoryRow {
  const TerminalContextDockDirectoryRow({
    required this.entry,
    required this.depth,
    required this.isExpanded,
    required this.isLoadingChildren,
    required this.childUnavailable,
    this.searchSource,
  });

  final TerminalDirectoryEntrySnapshot entry;
  final int depth;
  final bool isExpanded;
  final bool isLoadingChildren;
  final bool childUnavailable;
  final TerminalFileSearchSource? searchSource;

  bool get isDirectory => entry.kind == TerminalDirectoryEntryKind.directory;
}

/// One immutable projection of the visible pane's bounded local tree.
final class TerminalContextDockDirectorySnapshot {
  TerminalContextDockDirectorySnapshot({
    required this.windowId,
    required this.paneId,
    required this.generation,
    required this.status,
    required this.workingDirectory,
    required this.workingDirectorySource,
    required Iterable<TerminalContextDockDirectoryRow> rows,
    required this.omittedEntryCount,
    required this.issueCount,
    this.searchCoverage = const <TerminalFileSearchCoverage>[],
    this.isSearch = false,
  }) : rows = List<TerminalContextDockDirectoryRow>.unmodifiable(rows);

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int generation;
  final TerminalContextDockDirectoryStatus status;
  final String? workingDirectory;
  final TerminalWorkingDirectorySource? workingDirectorySource;
  final List<TerminalContextDockDirectoryRow> rows;
  final int omittedEntryCount;
  final int issueCount;
  final List<TerminalFileSearchCoverage> searchCoverage;
  final bool isSearch;
}

/// Owns generation-safe local cwd and lazy one-level snapshot operations.
final class TerminalContextDockDirectoryController {
  TerminalContextDockDirectoryController({
    required this.applicationState,
    required this.dockState,
    required TerminalContextDockWorkingDirectoryResolver
    resolveWorkingDirectory,
    TerminalDirectorySnapshotService snapshotService =
        const TerminalDirectorySnapshotService(),
    TerminalFileSearchService searchService = const TerminalFileSearchService(),
    Iterable<String> Function()? explicitSearchRoots,
    TerminalContextDockPaneObservationPolicy? canObservePane,
    void Function()? onChanged,
  }) : _resolveWorkingDirectory = resolveWorkingDirectory,
       _snapshotService = snapshotService,
       _searchService = searchService,
       _explicitSearchRoots = explicitSearchRoots ?? _noSearchRoots,
       _canObservePane = canObservePane ?? _alwaysObservePane,
       _onChanged = onChanged;

  final TerminalApplicationState applicationState;
  final TerminalContextDockState dockState;
  final TerminalContextDockWorkingDirectoryResolver _resolveWorkingDirectory;
  final TerminalDirectorySnapshotService _snapshotService;
  final TerminalFileSearchService _searchService;
  final Iterable<String> Function() _explicitSearchRoots;
  final TerminalContextDockPaneObservationPolicy _canObservePane;
  final void Function()? _onChanged;
  final Map<TerminalWindowId, _TerminalContextDockDirectoryWindowState>
  _windows = <TerminalWindowId, _TerminalContextDockDirectoryWindowState>{};
  final Map<PaneId, Set<String>> _expandedByPane = <PaneId, Set<String>>{};
  final List<String> _recentRoots = <String>[];
  final Set<PaneId> _pendingRefreshPaneIds = <PaneId>{};
  int _generation = 0;
  Timer? _scheduledSynchronization;
  bool _synchronizing = false;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get activeOperationCount => _windows.values.fold<int>(
    0,
    (int count, _TerminalContextDockDirectoryWindowState window) =>
        count +
        window.operations.length +
        (window.searchOperation == null ? 0 : 1) +
        (window.goToOperation == null ? 0 : 1),
  );

  TerminalContextDockDirectorySnapshot? snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed) return null;
    final _TerminalContextDockDirectoryWindowState? window = _windows[windowId];
    if (window == null) return null;
    return _project(window);
  }

  bool canRefreshWindow(TerminalWindowId windowId, PaneId paneId) {
    if (_isDisposed || applicationState.isDisposed || dockState.isDisposed) {
      return false;
    }
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      windowId,
    );
    final _TerminalContextDockDirectoryWindowState? window = _windows[windowId];
    return dock != null &&
        dock.isVisible &&
        dock.targetPaneId == paneId &&
        window != null &&
        window.paneId == paneId &&
        window.resolution?.isAvailable == true &&
        _readCanObservePane(paneId);
  }

  bool refreshWindow(TerminalWindowId windowId, PaneId paneId) {
    if (!canRefreshWindow(windowId, paneId)) return false;
    final _TerminalContextDockDirectoryWindowState? before = _windows[windowId];
    synchronize(refreshPaneIds: <PaneId>{paneId});
    final _TerminalContextDockDirectoryWindowState? after = _windows[windowId];
    return after != null &&
        !identical(before, after) &&
        after.paneId == paneId &&
        after.resolution?.isAvailable == true;
  }

  TerminalContextDockPathSelection? selectedPathForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed || dockState.isDisposed) return null;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      windowId,
    );
    final _TerminalContextDockDirectoryWindowState? window = _windows[windowId];
    if (dock == null ||
        window == null ||
        dock.targetPaneId != window.paneId ||
        !dock.navigatorOwnsInput) {
      return null;
    }
    final TerminalContextDockDirectorySnapshot projection = _project(window);
    final int selected = dock.pane.selectedResultIndex;
    if (selected < 0 || selected >= projection.rows.length) return null;
    return TerminalContextDockPathSelection(
      windowId: windowId,
      paneId: window.paneId,
      generation: projection.generation,
      entry: projection.rows[selected].entry,
    );
  }

  /// Coalesces high-frequency terminal activity into one cwd observation and
  /// refreshes the visible snapshot owned by the pane that changed.
  void scheduleSynchronize({PaneId? changedPaneId}) {
    if (_isDisposed) return;
    if (changedPaneId != null) _pendingRefreshPaneIds.add(changedPaneId);
    if (_scheduledSynchronization != null) return;
    _scheduledSynchronization = Timer(
      TerminalContextDockDirectoryLimits.terminalChangeDebounce,
      () {
        _scheduledSynchronization = null;
        final Set<PaneId> refreshPaneIds = Set<PaneId>.of(
          _pendingRefreshPaneIds,
        );
        _pendingRefreshPaneIds.clear();
        synchronize(refreshPaneIds: refreshPaneIds);
      },
    );
  }

  /// Re-resolves cwd on terminal output/focus changes and cancels stale work.
  void synchronize({Set<PaneId> refreshPaneIds = const <PaneId>{}}) {
    if (_isDisposed || _synchronizing) return;
    _synchronizing = true;
    try {
      if (applicationState.isDisposed || dockState.isDisposed) {
        _clearWindows();
        return;
      }
      dockState.synchronize(applicationState);
      final Set<PaneId> livePaneIds = <PaneId>{
        for (final TerminalWindowState window in applicationState.windows)
          for (final TerminalTabState tab in window.tabs) ...tab.paneIds,
      };
      _expandedByPane.removeWhere(
        (PaneId paneId, Set<String> _) => !livePaneIds.contains(paneId),
      );
      final List<TerminalWindowState> standardWindows = applicationState.windows
          .where(
            (TerminalWindowState window) =>
                window.role == TerminalWindowRole.standard,
          )
          .toList(growable: false);
      final Set<TerminalWindowId> liveWindowIds = standardWindows
          .map((TerminalWindowState window) => window.id)
          .toSet();
      for (final TerminalWindowId stale
          in _windows.keys
              .where(
                (TerminalWindowId windowId) =>
                    !liveWindowIds.contains(windowId),
              )
              .toList(growable: false)) {
        _windows.remove(stale)!.cancel();
      }
      for (final TerminalWindowState logicalWindow in standardWindows) {
        final TerminalContextDockWindowSnapshot? dock = dockState
            .snapshotForWindow(logicalWindow.id);
        if (dock == null || !dock.isVisible) {
          _windows.remove(logicalWindow.id)?.cancel();
          continue;
        }
        if (!_readCanObservePane(dock.targetPaneId)) {
          _replacePrivacyUnavailable(
            logicalWindow.id,
            dock.targetPaneId,
            dock.pane.showHiddenEntries,
          );
          continue;
        }
        TerminalWorkingDirectoryResolution? resolution;
        try {
          resolution = _resolveWorkingDirectory(
            dock.targetPaneId,
            ++_generation,
          );
        } on Object {
          _replaceUnavailable(
            logicalWindow.id,
            dock.targetPaneId,
            dock.pane.showHiddenEntries,
          );
          continue;
        }
        final _TerminalContextDockDirectoryWindowState? retained =
            _windows[logicalWindow.id];
        final bool refreshAvailableSnapshot =
            resolution.isAvailable &&
            refreshPaneIds.contains(dock.targetPaneId);
        if (retained != null &&
            retained.matches(dock, resolution) &&
            !refreshAvailableSnapshot) {
          retained.resolution = resolution;
          _synchronizeHiddenVisibility(retained, dock.pane.showHiddenEntries);
          if (resolution.isAvailable) _recordRecentRoot(resolution.path!);
          _ensureExpandedLoads(retained);
          _ensureSearch(retained, dock);
          _publishResultCount(retained);
          _ensureGoTo(retained, dock);
          continue;
        }
        retained?.cancel();
        final _TerminalContextDockDirectoryWindowState next =
            _TerminalContextDockDirectoryWindowState(
              windowId: logicalWindow.id,
              paneId: dock.targetPaneId,
              generation: ++_generation,
              resolution: resolution,
              showHiddenEntries: dock.pane.showHiddenEntries,
            );
        _windows[logicalWindow.id] = next;
        if (resolution.isAvailable) {
          _recordRecentRoot(resolution.path!);
          _startLoad(next, resolution.path!, isRoot: true);
          _ensureSearch(next, dock);
        }
        _publishResultCount(next);
        _ensureGoTo(next, dock);
        _onChanged?.call();
      }
    } finally {
      _synchronizing = false;
    }
  }

  bool handleTreeIntent(
    TerminalWindowId windowId,
    TerminalContextDockTreeIntent intent,
  ) {
    if (_isDisposed) return false;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      windowId,
    );
    final _TerminalContextDockDirectoryWindowState? window = _windows[windowId];
    if (dock == null || window == null) {
      return false;
    }
    if (dock.pane.navigatorMode == TerminalContextDockNavigatorMode.search &&
        dock.pane.searchQuery.isNotEmpty) {
      return intent != TerminalContextDockTreeIntent.collapse &&
          _activateSearchResult(window, dock);
    }
    final TerminalContextDockDirectorySnapshot projection = _project(window);
    final int selected = dock.pane.selectedResultIndex;
    if (selected < 0 || selected >= projection.rows.length) return false;
    final TerminalContextDockDirectoryRow row = projection.rows[selected];
    final Set<String> expanded = _expandedByPane.putIfAbsent(
      window.paneId,
      () => <String>{},
    );
    bool collapse(String path) {
      _collapse(window, path);
      _publishResultCount(window);
      final List<TerminalContextDockDirectoryRow> rows = _project(window).rows;
      final int parentIndex = rows.indexWhere(
        (TerminalContextDockDirectoryRow value) => value.entry.path == path,
      );
      if (parentIndex >= 0 && rows.isNotEmpty) {
        dockState.setSelectedResultIndex(windowId, parentIndex);
      }
      _onChanged?.call();
      return true;
    }

    switch (intent) {
      case TerminalContextDockTreeIntent.expand:
      case TerminalContextDockTreeIntent.toggle:
        if (intent == TerminalContextDockTreeIntent.toggle &&
            row.isDirectory &&
            expanded.contains(row.entry.path)) {
          return collapse(row.entry.path);
        }
        if (!row.isDirectory || expanded.contains(row.entry.path)) {
          return false;
        }
        if (expanded.length >=
            TerminalContextDockDirectoryLimits
                .maximumExpandedDirectoriesPerPane) {
          return false;
        }
        expanded.add(row.entry.path);
        _startLoad(window, row.entry.path, isRoot: false);
        _publishAndNotify(window);
        return true;
      case TerminalContextDockTreeIntent.collapse:
        String? collapsePath;
        if (row.isDirectory && expanded.contains(row.entry.path)) {
          collapsePath = row.entry.path;
        } else {
          collapsePath = _nearestExpandedAncestor(row.entry.path, expanded);
        }
        if (collapsePath == null) return false;
        return collapse(collapsePath);
    }
  }

  bool _activateSearchResult(
    _TerminalContextDockDirectoryWindowState window,
    TerminalContextDockWindowSnapshot dock,
  ) {
    if (!dock.navigatorOwnsInput) return false;
    final TerminalContextDockDirectorySnapshot projection = _project(window);
    final int selected = dock.pane.selectedResultIndex;
    if (selected < 0 || selected >= projection.rows.length) return false;
    final TerminalContextDockDirectoryRow row = projection.rows[selected];
    final _TerminalContextDockPendingReveal? reveal = _prepareReveal(
      window,
      row.entry,
      expectedMode: TerminalContextDockNavigatorMode.move,
      sourceQuery: dock.pane.searchQuery,
      expandTarget: row.isDirectory,
    );
    if (reveal == null) return false;
    dockState.setNavigatorMode(
      window.windowId,
      TerminalContextDockNavigatorMode.move,
      requireNavigatorInput: true,
    );
    window
      ..cancelSearch()
      ..pendingReveal = reveal;
    _publishAndNotify(window);
    return true;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _scheduledSynchronization?.cancel();
    _scheduledSynchronization = null;
    _pendingRefreshPaneIds.clear();
    _clearWindows();
    _expandedByPane.clear();
    _recentRoots.clear();
  }

  void _replaceUnavailable(
    TerminalWindowId windowId,
    PaneId paneId,
    bool showHiddenEntries,
  ) {
    _windows.remove(windowId)?.cancel();
    final _TerminalContextDockDirectoryWindowState next =
        _TerminalContextDockDirectoryWindowState(
          windowId: windowId,
          paneId: paneId,
          generation: ++_generation,
          resolution: null,
          showHiddenEntries: showHiddenEntries,
          privacyRestricted: false,
        );
    _windows[windowId] = next;
    _publishResultCount(next);
    _onChanged?.call();
  }

  void _replacePrivacyUnavailable(
    TerminalWindowId windowId,
    PaneId paneId,
    bool showHiddenEntries,
  ) {
    final _TerminalContextDockDirectoryWindowState? retained =
        _windows[windowId];
    if (retained?.paneId == paneId && retained?.privacyRestricted == true) {
      _synchronizeHiddenVisibility(retained!, showHiddenEntries);
      _publishResultCount(retained);
      return;
    }
    retained?.cancel();
    final _TerminalContextDockDirectoryWindowState next =
        _TerminalContextDockDirectoryWindowState(
          windowId: windowId,
          paneId: paneId,
          generation: ++_generation,
          resolution: null,
          showHiddenEntries: showHiddenEntries,
          privacyRestricted: true,
        );
    _windows[windowId] = next;
    _publishResultCount(next);
    _onChanged?.call();
  }

  bool _readCanObservePane(PaneId paneId) {
    try {
      return _canObservePane(paneId);
    } on Object {
      return false;
    }
  }

  void _synchronizeHiddenVisibility(
    _TerminalContextDockDirectoryWindowState window,
    bool showHiddenEntries,
  ) {
    if (window.showHiddenEntries == showHiddenEntries) return;
    window
      ..showHiddenEntries = showHiddenEntries
      ..cancelGoTo()
      ..appliedGoToQuery = null;
    if (showHiddenEntries) return;
    final String? root = window.resolution?.path;
    if (root == null) return;
    for (final String path
        in window.operations.keys
            .where(
              (String path) =>
                  path != root && _hasHiddenPathComponent(path, root),
            )
            .toList(growable: false)) {
      window.operations.remove(path)?.cancel();
    }
  }

  void _startLoad(
    _TerminalContextDockDirectoryWindowState window,
    String path, {
    required bool isRoot,
  }) {
    if (_isDisposed || window.operations.containsKey(path)) return;
    if (!isRoot && window.childSnapshots.containsKey(path)) return;
    if (!isRoot &&
        window.childSnapshots.length >=
            TerminalContextDockDirectoryLimits
                .maximumRetainedChildSnapshotsPerWindow) {
      return;
    }
    final int generation = ++_generation;
    final TerminalDirectorySnapshotOperation operation = _snapshotService.start(
      TerminalDirectorySnapshotRequest(
        rootPath: path,
        generation: generation,
        maximumEntries: isRoot
            ? TerminalContextDockDirectoryLimits.maximumRootEntries
            : TerminalContextDockDirectoryLimits.maximumChildEntries,
        maximumTotalPathUtf8Bytes: isRoot
            ? TerminalContextDockDirectoryLimits.maximumRootPathBytes
            : TerminalContextDockDirectoryLimits.maximumChildPathBytes,
      ),
    );
    window.operations[path] = operation;
    unawaited(
      operation.result.then<void>(
        (TerminalDirectorySnapshot result) {
          if (_isDisposed ||
              result.generation != generation ||
              !identical(_windows[window.windowId], window) ||
              !identical(window.operations[path], operation)) {
            return;
          }
          window.operations.remove(path);
          if (result.disposition ==
              TerminalDirectorySnapshotDisposition.cancelled) {
            return;
          }
          if (isRoot) {
            window.rootSnapshot = result;
          } else if (_expandedByPane[window.paneId]?.contains(path) == true) {
            window.childSnapshots[path] = result;
          }
          _ensureExpandedLoads(window);
          _publishAndNotify(window);
        },
        onError: (Object _, StackTrace _) {
          if (_isDisposed ||
              !identical(_windows[window.windowId], window) ||
              !identical(window.operations[path], operation)) {
            return;
          }
          window.operations.remove(path);
          _publishAndNotify(window);
        },
      ),
    );
  }

  void _ensureExpandedLoads(_TerminalContextDockDirectoryWindowState window) {
    if (window.rootSnapshot == null) return;
    final Set<String> expanded = _expandedByPane[window.paneId] ?? const {};
    for (final String path in expanded) {
      if (!_isWithinRoot(path, window.resolution?.path)) continue;
      if (!window.showHiddenEntries &&
          _hasHiddenPathComponent(path, window.resolution!.path!)) {
        continue;
      }
      _startLoad(window, path, isRoot: false);
    }
  }

  void _ensureSearch(
    _TerminalContextDockDirectoryWindowState window,
    TerminalContextDockWindowSnapshot dock,
  ) {
    final String queryText = dock.pane.searchQuery;
    if (dock.pane.navigatorMode != TerminalContextDockNavigatorMode.search ||
        queryText.isEmpty ||
        window.resolution?.isAvailable != true) {
      window.cancelSearch();
      return;
    }
    if (window.searchQuery == queryText &&
        (window.searchOperation != null || window.searchSnapshot != null)) {
      return;
    }
    window.cancelSearch();
    final TerminalFileSearchQuery query = TerminalFileSearchQuery.parse(
      queryText,
    );
    if (query.isEmpty) return;
    final int generation = ++_generation;
    window
      ..searchQuery = queryText
      ..searchGeneration = generation;
    late final TerminalFileSearchOperation operation;
    operation = _searchService.start(
      TerminalFileSearchRequest(
        query: query,
        currentRoot: window.resolution!.path!,
        generation: generation,
        recentRoots: _recentRoots,
        explicitRoots: _explicitSearchRoots(),
      ),
      onProgress: (TerminalFileSearchSnapshot snapshot) {
        if (!_acceptsSearch(window, operation, generation, queryText)) return;
        window.searchSnapshot = snapshot;
        _publishAndNotify(window);
      },
    );
    window.searchOperation = operation;
    unawaited(
      operation.result.then<void>(
        (TerminalFileSearchSnapshot snapshot) {
          if (!_acceptsSearch(window, operation, generation, queryText)) {
            return;
          }
          window.searchOperation = null;
          window.searchSnapshot = snapshot;
          _publishAndNotify(window);
        },
        onError: (Object _, StackTrace _) {
          if (!_acceptsSearch(window, operation, generation, queryText)) {
            return;
          }
          window.searchOperation = null;
          _publishAndNotify(window);
        },
      ),
    );
  }

  bool _acceptsSearch(
    _TerminalContextDockDirectoryWindowState window,
    TerminalFileSearchOperation operation,
    int generation,
    String query,
  ) =>
      !_isDisposed &&
      identical(_windows[window.windowId], window) &&
      identical(window.searchOperation, operation) &&
      window.searchGeneration == generation &&
      window.searchQuery == query &&
      dockState.snapshotForWindow(window.windowId)?.pane.navigatorMode ==
          TerminalContextDockNavigatorMode.search &&
      dockState.snapshotForWindow(window.windowId)?.pane.searchQuery == query;

  void _ensureGoTo(
    _TerminalContextDockDirectoryWindowState window,
    TerminalContextDockWindowSnapshot dock,
  ) {
    final String queryText = dock.pane.goToQuery;
    if (dock.pane.navigatorMode != TerminalContextDockNavigatorMode.goTo ||
        queryText.isEmpty ||
        window.resolution?.isAvailable != true) {
      window
        ..cancelGoTo()
        ..appliedGoToQuery = null;
      return;
    }
    if (window.appliedGoToQuery == queryText ||
        (window.pendingReveal?.expectedMode ==
                TerminalContextDockNavigatorMode.goTo &&
            window.pendingReveal?.sourceQuery == queryText) ||
        (window.goToQuery == queryText && window.goToOperation != null)) {
      return;
    }
    window
      ..cancelGoTo()
      ..appliedGoToQuery = null;
    final TerminalFileSearchQuery query = TerminalFileSearchQuery.parse(
      queryText,
    );
    if (query.isEmpty) return;
    final int generation = ++_generation;
    window
      ..goToQuery = queryText
      ..goToGeneration = generation;
    late final TerminalFileSearchOperation operation;
    operation = _searchService.start(
      TerminalFileSearchRequest(
        query: query,
        currentRoot: window.resolution!.path!,
        generation: generation,
        scope: TerminalFileSearchScope.currentSubtree,
      ),
    );
    window.goToOperation = operation;
    unawaited(
      operation.result.then<void>(
        (TerminalFileSearchSnapshot snapshot) {
          if (!_acceptsGoTo(window, operation, generation, queryText)) return;
          window.goToOperation = null;
          TerminalFileSearchResult? match;
          for (final TerminalFileSearchResult candidate in snapshot.results) {
            if (_showsSearchResult(window, candidate)) {
              match = candidate;
              break;
            }
          }
          if (match == null) {
            window.appliedGoToQuery = queryText;
          } else {
            final _TerminalContextDockPendingReveal? reveal = _prepareReveal(
              window,
              match.entry,
              expectedMode: TerminalContextDockNavigatorMode.goTo,
              sourceQuery: queryText,
              expandTarget: false,
            );
            if (reveal == null) {
              window.appliedGoToQuery = queryText;
            } else {
              window.pendingReveal = reveal;
            }
          }
          _publishAndNotify(window);
        },
        onError: (Object _, StackTrace _) {
          if (!_acceptsGoTo(window, operation, generation, queryText)) return;
          window
            ..goToOperation = null
            ..appliedGoToQuery = queryText;
          _publishAndNotify(window);
        },
      ),
    );
  }

  bool _acceptsGoTo(
    _TerminalContextDockDirectoryWindowState window,
    TerminalFileSearchOperation operation,
    int generation,
    String query,
  ) {
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    return !_isDisposed &&
        identical(_windows[window.windowId], window) &&
        identical(window.goToOperation, operation) &&
        window.goToGeneration == generation &&
        window.goToQuery == query &&
        dock?.targetPaneId == window.paneId &&
        dock?.pane.navigatorMode == TerminalContextDockNavigatorMode.goTo &&
        dock?.pane.goToQuery == query;
  }

  void _recordRecentRoot(String path) {
    _recentRoots.remove(path);
    _recentRoots.insert(0, path);
    if (_recentRoots.length > TerminalFileSearchLimits.maximumAdditionalRoots) {
      _recentRoots.removeRange(
        TerminalFileSearchLimits.maximumAdditionalRoots,
        _recentRoots.length,
      );
    }
  }

  void _collapse(_TerminalContextDockDirectoryWindowState window, String path) {
    final Set<String>? expanded = _expandedByPane[window.paneId];
    if (expanded == null) return;
    for (final String candidate
        in expanded
            .where(
              (String value) => value == path || _isDescendant(value, path),
            )
            .toList(growable: false)) {
      expanded.remove(candidate);
      window.operations.remove(candidate)?.cancel();
      window.childSnapshots.remove(candidate);
    }
  }

  void _publishAndNotify(_TerminalContextDockDirectoryWindowState window) {
    _publishResultCount(window);
    _onChanged?.call();
  }

  void _publishResultCount(_TerminalContextDockDirectoryWindowState window) {
    if (_isDisposed || dockState.isDisposed) return;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    if (dock == null || dock.targetPaneId != window.paneId) return;
    final int count = _project(window).rows.length;
    if (dock.pane.resultCount != count) {
      dockState.setResultCount(window.windowId, count);
    }
    _applyVisibleGoTo(window);
    _advancePendingReveal(window);
  }

  void _applyVisibleGoTo(_TerminalContextDockDirectoryWindowState window) {
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    if (dock == null ||
        dock.pane.navigatorMode != TerminalContextDockNavigatorMode.goTo) {
      window.appliedGoToQuery = null;
      return;
    }
    final String queryText = dock.pane.goToQuery;
    if (queryText.isEmpty ||
        window.appliedGoToQuery == queryText ||
        (window.pendingReveal?.expectedMode ==
                TerminalContextDockNavigatorMode.goTo &&
            window.pendingReveal?.sourceQuery == queryText)) {
      return;
    }
    final TerminalFileSearchQuery query = TerminalFileSearchQuery.parse(
      queryText,
    );
    if (query.isEmpty) return;
    final List<TerminalContextDockDirectoryRow> rows = _project(window).rows;
    final int match = rows.indexWhere(
      (TerminalContextDockDirectoryRow row) =>
          query.matches(row.entry.name, row.entry.path),
    );
    if (match < 0) return;
    if (dock.pane.selectedResultIndex != match) {
      dockState.setSelectedResultIndex(window.windowId, match);
    }
    window
      ..cancelGoTo()
      ..appliedGoToQuery = queryText;
  }

  _TerminalContextDockPendingReveal? _prepareReveal(
    _TerminalContextDockDirectoryWindowState window,
    TerminalDirectoryEntrySnapshot entry, {
    required TerminalContextDockNavigatorMode expectedMode,
    required String sourceQuery,
    required bool expandTarget,
  }) {
    final String? root = window.resolution?.path;
    if (root == null ||
        sourceQuery.isEmpty ||
        TerminalLocalPathPolicy.normalizeAbsolute(entry.path) != entry.path ||
        (!window.showHiddenEntries &&
            _hasHiddenPathComponent(entry.path, root)) ||
        !_isDescendant(entry.path, root)) {
      return null;
    }
    final List<String> ancestors = _directoryAncestors(root, entry.path);
    final Set<String> expanded =
        _expandedByPane[window.paneId] ?? const <String>{};
    final Set<String> requiredExpansions = <String>{...ancestors};
    if (expandTarget && entry.kind == TerminalDirectoryEntryKind.directory) {
      requiredExpansions.add(entry.path);
    }
    final int additional = requiredExpansions
        .where((String path) => !expanded.contains(path))
        .length;
    if (expanded.length + additional >
        TerminalContextDockDirectoryLimits.maximumExpandedDirectoriesPerPane) {
      return null;
    }
    return _TerminalContextDockPendingReveal(
      rootPath: root,
      target: entry,
      ancestorDirectories: ancestors,
      expectedMode: expectedMode,
      sourceQuery: sourceQuery,
      expandTarget: expandTarget,
    );
  }

  void _advancePendingReveal(_TerminalContextDockDirectoryWindowState window) {
    final _TerminalContextDockPendingReveal? reveal = window.pendingReveal;
    if (reveal == null) return;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    final String? retainedQuery = switch (reveal.expectedMode) {
      TerminalContextDockNavigatorMode.search => dock?.pane.searchQuery,
      TerminalContextDockNavigatorMode.goTo => dock?.pane.goToQuery,
      TerminalContextDockNavigatorMode.move => dock?.pane.searchQuery,
    };
    if (dock == null ||
        dock.targetPaneId != window.paneId ||
        dock.pane.navigatorMode != reveal.expectedMode ||
        retainedQuery != reveal.sourceQuery ||
        window.resolution?.path != reveal.rootPath ||
        (!dock.pane.showHiddenEntries &&
            _hasHiddenPathComponent(reveal.target.path, reveal.rootPath))) {
      window.pendingReveal = null;
      return;
    }

    final List<TerminalContextDockDirectoryRow> rows = _project(window).rows;
    final Set<String> expanded = _expandedByPane.putIfAbsent(
      window.paneId,
      () => <String>{},
    );
    for (final String ancestor in reveal.ancestorDirectories) {
      if (expanded.contains(ancestor)) {
        final TerminalDirectorySnapshot? snapshot =
            window.childSnapshots[ancestor];
        if (snapshot == null) {
          _startLoad(window, ancestor, isRoot: false);
          if (!window.operations.containsKey(ancestor)) {
            _failPendingReveal(window, reveal);
          }
          return;
        }
        if (snapshot.disposition ==
            TerminalDirectorySnapshotDisposition.unavailable) {
          _failPendingReveal(window, reveal);
          return;
        }
        continue;
      }
      final int rowIndex = rows.indexWhere(
        (TerminalContextDockDirectoryRow row) => row.entry.path == ancestor,
      );
      if (rowIndex < 0 || !rows[rowIndex].isDirectory) {
        final TerminalDirectorySnapshot? parent = _snapshotContaining(
          window,
          ancestor,
          reveal.rootPath,
        );
        if (parent != null) _failPendingReveal(window, reveal);
        return;
      }
      if (expanded.length >=
          TerminalContextDockDirectoryLimits
              .maximumExpandedDirectoriesPerPane) {
        _failPendingReveal(window, reveal);
        return;
      }
      expanded.add(ancestor);
      _startLoad(window, ancestor, isRoot: false);
      if (!window.operations.containsKey(ancestor) &&
          !window.childSnapshots.containsKey(ancestor)) {
        expanded.remove(ancestor);
        _failPendingReveal(window, reveal);
      }
      return;
    }

    final int targetIndex = rows.indexWhere(
      (TerminalContextDockDirectoryRow row) =>
          row.entry.path == reveal.target.path,
    );
    if (targetIndex < 0) {
      final TerminalDirectorySnapshot? parent = _snapshotContaining(
        window,
        reveal.target.path,
        reveal.rootPath,
      );
      if (parent != null) _failPendingReveal(window, reveal);
      return;
    }
    final TerminalContextDockDirectoryRow targetRow = rows[targetIndex];
    if (reveal.expandTarget) {
      if (!targetRow.isDirectory) {
        _failPendingReveal(window, reveal);
        return;
      }
      if (!expanded.contains(reveal.target.path)) {
        if (expanded.length >=
            TerminalContextDockDirectoryLimits
                .maximumExpandedDirectoriesPerPane) {
          _failPendingReveal(window, reveal);
          return;
        }
        expanded.add(reveal.target.path);
        _startLoad(window, reveal.target.path, isRoot: false);
        if (!window.operations.containsKey(reveal.target.path) &&
            !window.childSnapshots.containsKey(reveal.target.path)) {
          expanded.remove(reveal.target.path);
          _failPendingReveal(window, reveal);
          return;
        }
      }
    }
    dockState.setSelectedResultIndex(window.windowId, targetIndex);
    window.pendingReveal = null;
    if (reveal.expectedMode == TerminalContextDockNavigatorMode.goTo) {
      window.appliedGoToQuery = reveal.sourceQuery;
    }
  }

  void _failPendingReveal(
    _TerminalContextDockDirectoryWindowState window,
    _TerminalContextDockPendingReveal reveal,
  ) {
    if (!identical(window.pendingReveal, reveal)) return;
    window.pendingReveal = null;
    if (reveal.expectedMode == TerminalContextDockNavigatorMode.goTo) {
      window.appliedGoToQuery = reveal.sourceQuery;
    }
  }

  static TerminalDirectorySnapshot? _snapshotContaining(
    _TerminalContextDockDirectoryWindowState window,
    String path,
    String root,
  ) {
    final String parent = _parentPath(path);
    return parent == root ? window.rootSnapshot : window.childSnapshots[parent];
  }

  static List<String> _directoryAncestors(String root, String target) {
    final String relative = root == '/'
        ? target.substring(1)
        : target.substring(root.length + 1);
    final List<String> components = relative.split('/');
    final List<String> ancestors = <String>[];
    var current = root;
    for (var index = 0; index < components.length - 1; index++) {
      current = current == '/'
          ? '/${components[index]}'
          : '$current/${components[index]}';
      ancestors.add(current);
    }
    return ancestors;
  }

  static String _parentPath(String path) {
    final int separator = path.lastIndexOf('/');
    return separator <= 0 ? '/' : path.substring(0, separator);
  }

  TerminalContextDockDirectorySnapshot _project(
    _TerminalContextDockDirectoryWindowState window,
  ) {
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    final TerminalWorkingDirectoryResolution? resolution = window.resolution;
    final TerminalDirectorySnapshot? root = window.rootSnapshot;
    final String query = dock?.pane.searchQuery ?? '';
    if (resolution?.isAvailable == true &&
        dock?.pane.navigatorMode == TerminalContextDockNavigatorMode.search &&
        query.isNotEmpty &&
        !TerminalFileSearchQuery.parse(query).isEmpty) {
      final TerminalFileSearchSnapshot? search = window.searchSnapshot;
      final List<TerminalContextDockDirectoryRow> searchRows =
          <TerminalContextDockDirectoryRow>[
            for (final TerminalFileSearchResult result
                in search?.results ?? const <TerminalFileSearchResult>[])
              if (_showsSearchResult(window, result))
                TerminalContextDockDirectoryRow(
                  entry: result.entry,
                  depth: 0,
                  isExpanded: false,
                  isLoadingChildren: false,
                  childUnavailable: false,
                  searchSource: result.source,
                ),
          ];
      final bool coverageIssue =
          search?.coverage.any(
            (TerminalFileSearchCoverage value) =>
                value.disposition ==
                    TerminalFileSearchCoverageDisposition.partial ||
                value.disposition ==
                    TerminalFileSearchCoverageDisposition.unavailable,
          ) ??
          false;
      return TerminalContextDockDirectorySnapshot(
        windowId: window.windowId,
        paneId: window.paneId,
        generation: window.generation,
        status: search == null || (!search.isComplete && searchRows.isEmpty)
            ? TerminalContextDockDirectoryStatus.loading
            : coverageIssue
            ? TerminalContextDockDirectoryStatus.partial
            : searchRows.isEmpty
            ? TerminalContextDockDirectoryStatus.empty
            : TerminalContextDockDirectoryStatus.ready,
        workingDirectory: resolution?.path,
        workingDirectorySource: resolution?.source,
        rows: searchRows,
        omittedEntryCount: search?.omittedResultCount ?? 0,
        issueCount:
            search?.coverage
                .where(
                  (TerminalFileSearchCoverage value) =>
                      value.disposition ==
                      TerminalFileSearchCoverageDisposition.unavailable,
                )
                .length ??
            0,
        searchCoverage:
            search?.coverage ?? const <TerminalFileSearchCoverage>[],
        isSearch: true,
      );
    }
    final List<TerminalContextDockDirectoryRow> rows =
        <TerminalContextDockDirectoryRow>[];
    var omitted = 0;
    var issues = resolution?.issues.length ?? 1;
    if (root != null) {
      final Set<String> expanded = _expandedByPane[window.paneId] ?? const {};
      void append(TerminalDirectorySnapshot snapshot, int depth) {
        omitted += snapshot.omittedEntryCount;
        issues += snapshot.issues.length;
        for (final TerminalDirectoryEntrySnapshot entry in snapshot.entries) {
          if (!window.showHiddenEntries && entry.isHidden) continue;
          if (rows.length >= TerminalContextDockLimits.maximumResults) {
            omitted++;
            return;
          }
          final bool isExpanded = expanded.contains(entry.path);
          final TerminalDirectorySnapshot? child = isExpanded
              ? window.childSnapshots[entry.path]
              : null;
          rows.add(
            TerminalContextDockDirectoryRow(
              entry: entry,
              depth: depth,
              isExpanded: isExpanded,
              isLoadingChildren:
                  isExpanded && window.operations.containsKey(entry.path),
              childUnavailable:
                  child?.disposition ==
                  TerminalDirectorySnapshotDisposition.unavailable,
              searchSource: null,
            ),
          );
          if (isExpanded &&
              child != null &&
              child.disposition !=
                  TerminalDirectorySnapshotDisposition.unavailable) {
            append(child, depth + 1);
          }
        }
      }

      append(root, 0);
    }
    return TerminalContextDockDirectorySnapshot(
      windowId: window.windowId,
      paneId: window.paneId,
      generation: window.generation,
      status: _status(window, rows),
      workingDirectory: resolution?.path,
      workingDirectorySource: resolution?.source,
      rows: rows,
      omittedEntryCount: omitted,
      issueCount: issues,
    );
  }

  static TerminalContextDockDirectoryStatus _status(
    _TerminalContextDockDirectoryWindowState window,
    List<TerminalContextDockDirectoryRow> rows,
  ) {
    if (window.privacyRestricted) {
      return TerminalContextDockDirectoryStatus.privacyUnavailable;
    }
    final TerminalWorkingDirectoryResolution? resolution = window.resolution;
    if (resolution == null ||
        resolution.disposition ==
            TerminalWorkingDirectoryDisposition.unavailable) {
      return TerminalContextDockDirectoryStatus.unavailable;
    }
    if (resolution.disposition ==
        TerminalWorkingDirectoryDisposition.remoteUnavailable) {
      return TerminalContextDockDirectoryStatus.remoteUnavailable;
    }
    final TerminalDirectorySnapshot? root = window.rootSnapshot;
    if (root == null) return TerminalContextDockDirectoryStatus.loading;
    if (root.disposition == TerminalDirectorySnapshotDisposition.unavailable) {
      return TerminalContextDockDirectoryStatus.unavailable;
    }
    final bool partial =
        root.disposition == TerminalDirectorySnapshotDisposition.partial ||
        window.childSnapshots.values.any(
          (TerminalDirectorySnapshot snapshot) =>
              snapshot.disposition ==
              TerminalDirectorySnapshotDisposition.partial,
        );
    if (partial) return TerminalContextDockDirectoryStatus.partial;
    return rows.isEmpty
        ? TerminalContextDockDirectoryStatus.empty
        : TerminalContextDockDirectoryStatus.ready;
  }

  static String? _nearestExpandedAncestor(String path, Set<String> expanded) {
    String? best;
    for (final String candidate in expanded) {
      if (_isDescendant(path, candidate) &&
          (best == null || candidate.length > best.length)) {
        best = candidate;
      }
    }
    return best;
  }

  static bool _isWithinRoot(String path, String? root) =>
      root != null && (path == root || _isDescendant(path, root));

  static bool _showsSearchResult(
    _TerminalContextDockDirectoryWindowState window,
    TerminalFileSearchResult result,
  ) {
    if (window.showHiddenEntries) return true;
    final String? root = window.resolution?.path;
    return root == null || !_hasHiddenPathComponent(result.entry.path, root);
  }

  static bool _hasHiddenPathComponent(String path, String root) {
    final String relative;
    if (path == root) {
      return false;
    } else if (_isDescendant(path, root)) {
      relative = root == '/'
          ? path.substring(1)
          : path.substring(root.length + 1);
    } else {
      relative = path.startsWith('/') ? path.substring(1) : path;
    }
    return relative
        .split('/')
        .any((String component) => component.startsWith('.'));
  }

  static bool _isDescendant(String path, String parent) => parent == '/'
      ? path.startsWith('/') && path != '/'
      : path.startsWith('$parent/');

  void _clearWindows() {
    for (final _TerminalContextDockDirectoryWindowState window
        in _windows.values) {
      window.cancel();
    }
    _windows.clear();
  }

  static Iterable<String> _noSearchRoots() => const <String>[];
  static bool _alwaysObservePane(PaneId _) => true;
}

final class _TerminalContextDockDirectoryWindowState {
  _TerminalContextDockDirectoryWindowState({
    required this.windowId,
    required this.paneId,
    required this.generation,
    required this.resolution,
    required this.showHiddenEntries,
    this.privacyRestricted = false,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int generation;
  TerminalWorkingDirectoryResolution? resolution;
  bool showHiddenEntries;
  final bool privacyRestricted;
  TerminalDirectorySnapshot? rootSnapshot;
  final Map<String, TerminalDirectorySnapshot> childSnapshots =
      <String, TerminalDirectorySnapshot>{};
  final Map<String, TerminalDirectorySnapshotOperation> operations =
      <String, TerminalDirectorySnapshotOperation>{};
  String? searchQuery;
  int? searchGeneration;
  TerminalFileSearchOperation? searchOperation;
  TerminalFileSearchSnapshot? searchSnapshot;
  String? goToQuery;
  int? goToGeneration;
  TerminalFileSearchOperation? goToOperation;
  String? appliedGoToQuery;
  _TerminalContextDockPendingReveal? pendingReveal;

  bool matches(
    TerminalContextDockWindowSnapshot dock,
    TerminalWorkingDirectoryResolution next,
  ) =>
      paneId == dock.targetPaneId &&
      resolution?.disposition == next.disposition &&
      resolution?.path == next.path;

  void cancel() {
    cancelSearch();
    cancelGoTo();
    pendingReveal = null;
    appliedGoToQuery = null;
    for (final TerminalDirectorySnapshotOperation operation
        in operations.values) {
      operation.cancel();
    }
    operations.clear();
    childSnapshots.clear();
    rootSnapshot = null;
  }

  void cancelSearch() {
    searchOperation?.cancel();
    searchOperation = null;
    searchSnapshot = null;
    searchQuery = null;
    searchGeneration = null;
  }

  void cancelGoTo() {
    goToOperation?.cancel();
    goToOperation = null;
    goToQuery = null;
    goToGeneration = null;
    if (pendingReveal?.expectedMode == TerminalContextDockNavigatorMode.goTo) {
      pendingReveal = null;
    }
  }
}

final class _TerminalContextDockPendingReveal {
  _TerminalContextDockPendingReveal({
    required this.rootPath,
    required this.target,
    required Iterable<String> ancestorDirectories,
    required this.expectedMode,
    required this.sourceQuery,
    required this.expandTarget,
  }) : ancestorDirectories = List<String>.unmodifiable(ancestorDirectories);

  final String rootPath;
  final TerminalDirectoryEntrySnapshot target;
  final List<String> ancestorDirectories;
  final TerminalContextDockNavigatorMode expectedMode;
  final String sourceQuery;
  final bool expandTarget;
}

/// Native sibling Dock projection. The terminal hierarchy retains ownership of
/// terminal pane/split views; this presenter owns only the outer/inner Dock
/// splits and its navigator/details views.
final class TerminalContextDockDirectoryPresenter {
  TerminalContextDockDirectoryPresenter({
    required this.applicationState,
    required this.dockState,
    required this.directoryController,
    required this.localization,
    required Window? Function(TerminalTabId tabId) windowForTab,
    required View? Function(PaneId paneId) terminalViewForPane,
    TerminalContextDockPathHandoffSnapshotResolver? pathHandoffSnapshot,
    TerminalContextDockContentSnapshotResolver? contentSnapshot,
    TerminalContextDockAppearanceResolver? appearanceForPane,
    double Function(PaneId paneId)? cellWidthForPane,
    TerminalSplitLayoutSize Function(TerminalTabId tabId)?
    minimumTerminalSizeForTab,
  }) : _windowForTab = windowForTab,
       _terminalViewForPane = terminalViewForPane,
       _pathHandoffSnapshot = pathHandoffSnapshot ?? _noPathHandoffSnapshot,
       _contentSnapshot = contentSnapshot ?? _noContentSnapshot,
       _appearanceForPane = appearanceForPane,
       _cellWidthForPane = cellWidthForPane ?? _defaultCellWidth,
       _minimumTerminalSizeForTab = minimumTerminalSizeForTab;

  final TerminalApplicationState applicationState;
  final TerminalContextDockState dockState;
  final TerminalContextDockDirectoryController directoryController;
  final TerminalLocalization localization;
  final Window? Function(TerminalTabId tabId) _windowForTab;
  final View? Function(PaneId paneId) _terminalViewForPane;
  final TerminalContextDockPathHandoffSnapshotResolver _pathHandoffSnapshot;
  final TerminalContextDockContentSnapshotResolver _contentSnapshot;
  final TerminalContextDockAppearanceResolver? _appearanceForPane;
  final double Function(PaneId paneId) _cellWidthForPane;
  final TerminalSplitLayoutSize Function(TerminalTabId tabId)?
  _minimumTerminalSizeForTab;
  final Map<TerminalWindowId, _TerminalContextDockNativeResources> _resources =
      <TerminalWindowId, _TerminalContextDockNativeResources>{};
  final Map<TerminalWindowId, TerminalSplitLayoutSize> _fullSizes =
      <TerminalWindowId, TerminalSplitLayoutSize>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get resourceCount => _resources.length;

  TerminalContextDockAppearance? nativeAppearanceForWindow(
    TerminalWindowId windowId,
  ) => _isDisposed ? null : _resources[windowId]?.appearance;

  /// Theme/OSC/live-opacity updates do not need a geometry or focus handoff.
  void refreshAppearance() {
    if (_isDisposed) return;
    for (final MapEntry<TerminalWindowId, _TerminalContextDockNativeResources>
        entry
        in _resources.entries) {
      final TerminalContextDockWindowSnapshot? dock = dockState
          .snapshotForWindow(entry.key);
      if (dock?.isVisible == true)
        _applyAppearance(entry.value, dock!.targetPaneId);
    }
  }

  void _applyAppearance(
    _TerminalContextDockNativeResources resources,
    PaneId paneId,
  ) {
    final TerminalContextDockAppearance? appearance = _appearanceForPane?.call(
      paneId,
    );
    if (appearance == null) return;
    for (final TextEditor editor in <TextEditor>[
      resources.editor,
      resources.details,
    ]) {
      editor.updatePresentation(
        font: appearance.font,
        foregroundColor: appearance.foregroundColor,
        backgroundColor: appearance.backgroundColor,
        padding: appearance.padding,
        fontVariations: appearance.fontVariations,
      );
    }
    resources.split.dividerColor = appearance.dividerColor;
    resources.contentSplit.dividerColor = appearance.dividerColor;
    resources.appearance = appearance;
  }

  TextEditorSnapshot? nativeEditorSnapshotForWindow(TerminalWindowId windowId) {
    if (_isDisposed) return null;
    final TextEditor? editor = _resources[windowId]?.editor;
    return editor == null || editor.isDisposed ? null : editor.snapshot;
  }

  String? nativeDetailsTextForWindow(TerminalWindowId windowId) {
    if (_isDisposed) return null;
    final TextEditor? details = _resources[windowId]?.details;
    return details == null || details.isDisposed ? null : details.snapshot.text;
  }

  bool nativeProcessUsesFullHeightForWindow(TerminalWindowId windowId) =>
      !_isDisposed &&
      _resources[windowId]?.document?.kind ==
          _TerminalContextDockDocumentKind.process &&
      _resources[windowId]?.contentSplit.zoomedChild == SplitViewChild.first;

  bool get canFocusNavigator {
    if (_isDisposed || applicationState.isDisposed || dockState.isDisposed) {
      return false;
    }
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) {
      return false;
    }
    final TerminalContextDockContentSnapshot? content = _contentSnapshot(
      window.id,
    );
    if (content != null &&
        content.mode != TerminalContextDockContentMode.directoryNavigator) {
      return false;
    }
    final TerminalSplitLayoutSize? fullSize = _fullSizes[window.id];
    return fullSize == null || _hasRoom(fullSize, window.selectedTab);
  }

  /// Whether a Navigator shortcut should be consumed while another Context
  /// Dock document is active instead of moving focus to a hidden editor.
  bool get shouldConsumeNavigatorRequest {
    if (_isDisposed || applicationState.isDisposed || dockState.isDisposed) {
      return false;
    }
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) {
      return false;
    }
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    final TerminalContextDockContentSnapshot? content = _contentSnapshot(
      window.id,
    );
    return dock?.isVisible == true &&
        content != null &&
        (content.mode == TerminalContextDockContentMode.foregroundJob ||
            content.mode == TerminalContextDockContentMode.shellOwnedCommand);
  }

  TerminalSplitLayoutSize resolveTerminalLayoutSize(
    TerminalWindowState window,
    TerminalTabState tab,
    TerminalSplitLayoutSize fullSize,
  ) {
    _ensureAlive();
    _fullSizes[window.id] = fullSize;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    if (!_shouldShow(window, tab, fullSize, dock)) {
      final _TerminalContextDockNativeResources? resources =
          _resources[window.id];
      if (resources?.attachedTabId == tab.id) {
        resources!.projectedVisible = false;
      }
      return fullSize;
    }
    final double dockWidth = _effectiveDockWidth(dock!.width, fullSize, tab);
    return TerminalSplitLayoutSize(
      width:
          fullSize.width -
          dockWidth -
          TerminalContextDockDirectoryLimits.dividerThickness,
      height: fullSize.height,
    );
  }

  View decorateRoot(
    TerminalWindowState window,
    TerminalTabState tab,
    View terminalRoot,
    TerminalSplitLayoutSize fullSize,
  ) {
    _ensureAlive();
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    if (!_shouldShow(window, tab, fullSize, dock)) return terminalRoot;
    final TerminalContextDockWindowSnapshot visibleDock = dock!;
    final _TerminalContextDockNativeResources resources = _resources
        .putIfAbsent(window.id, _TerminalContextDockNativeResources.new);
    resources.attachContent();
    _applyAppearance(resources, visibleDock.targetPaneId);
    final bool rootAttachmentChanged =
        !resources.projectedVisible ||
        !identical(resources.split.firstView, terminalRoot) ||
        !identical(resources.split.secondView, resources.contentSplit);
    final bool inputOwnerProjectionChanged =
        !resources.projectedVisible ||
        resources.attachedTabId != tab.id ||
        resources.attachedPaneId != visibleDock.targetPaneId ||
        rootAttachmentChanged;
    _publishDocument(
      resources,
      visibleDock,
      directoryController.snapshotForWindow(window.id),
    );
    final SplitViewChild? zoomedChild =
        resources.document!.kind == _TerminalContextDockDocumentKind.process
        ? SplitViewChild.first
        : null;
    if (resources.contentSplit.zoomedChild != zoomedChild) {
      resources.contentSplit.zoomedChild = zoomedChild;
    }
    if (rootAttachmentChanged) {
      resources.split.setChildren(
        first: terminalRoot,
        second: resources.contentSplit,
      );
    }
    final double contentUsableHeight =
        fullSize.height - TerminalContextDockDirectoryLimits.dividerThickness;
    final double detailsHeight = _effectiveDetailsHeight(fullSize);
    resources.contentSplit.setPosition(
      fraction: (contentUsableHeight - detailsHeight) / contentUsableHeight,
      firstMinimumExtent:
          TerminalContextDockDirectoryLimits.minimumNavigatorHeight,
      secondMinimumExtent:
          TerminalContextDockDirectoryLimits.minimumDetailsHeight,
    );
    final double usable =
        fullSize.width - TerminalContextDockDirectoryLimits.dividerThickness;
    final double dockWidth = _effectiveDockWidth(
      visibleDock.width,
      fullSize,
      tab,
    );
    resources.split.setPosition(
      fraction: (usable - dockWidth) / usable,
      firstMinimumExtent: _minimumTerminalWidth(tab),
      secondMinimumExtent: TerminalContextDockLimits.minimumWidth,
    );
    resources
      ..projectedVisible = true
      ..attachedTabId = tab.id
      ..attachedPaneId = visibleDock.targetPaneId
      ..inputOwnerProjectionPending |= inputOwnerProjectionChanged;
    return resources.split;
  }

  void focusNavigator(TerminalContextDockFocusRequest request) {
    _ensureAlive();
    final TerminalWindowState? logicalWindow = applicationState.windowForId(
      request.windowId,
    );
    final _TerminalContextDockNativeResources? resources =
        _resources[request.windowId];
    if (logicalWindow == null ||
        logicalWindow.selectedTab.focusedPaneId != request.paneId ||
        resources == null ||
        resources.attachedTabId != logicalWindow.selectedTabId) {
      throw StateError('Context Dock native target is not projected');
    }
    final Window? window = _windowForTab(logicalWindow.selectedTabId);
    if (window == null || window.isDisposed || window.isClosed) {
      throw StateError('Context Dock native window is unavailable');
    }
    final TerminalContextDockWindowSnapshot dock =
        dockState.snapshotForWindow(request.windowId) ??
        (throw StateError('Context Dock state is unavailable'));
    final TerminalContextDockContentSnapshot? content = _contentSnapshot(
      request.windowId,
    );
    if (content != null &&
        content.mode != TerminalContextDockContentMode.directoryNavigator) {
      throw StateError('Context Dock navigator document is not active');
    }
    _setEditorEditable(resources, dock.pane.acceptsQuery);
    window
      ..keyEventRouting = KeyEventRouting.dartOnly
      ..makeFirstResponder(resources.editor);
    final _TerminalContextDockDocument document = resources.document!;
    resources.editor.setSelection(document.queryCaret);
    resources.editor.scrollSelectionToVisible();
    resources.lastAppliedQuerySelectionGeneration =
        request.querySelectionGeneration;
    resources.navigatorTabId = logicalWindow.selectedTabId;
  }

  void focusTerminal(TerminalContextDockFocusRequest request) {
    _ensureAlive();
    final TerminalWindowState? logicalWindow = applicationState.windowForId(
      request.windowId,
    );
    final Window? window = logicalWindow == null
        ? null
        : _windowForTab(logicalWindow.selectedTabId);
    final View? terminalView = _terminalViewForPane(request.paneId);
    if (logicalWindow == null ||
        logicalWindow.selectedTab.focusedPaneId != request.paneId ||
        window == null ||
        window.isDisposed ||
        window.isClosed ||
        terminalView == null ||
        terminalView.isDisposed) {
      throw StateError('terminal native focus target is unavailable');
    }
    window
      ..keyEventRouting = KeyEventRouting.appKitOnly
      ..makeFirstResponder(terminalView);
    final _TerminalContextDockNativeResources? resources =
        _resources[request.windowId];
    if (resources != null) {
      _setEditorEditable(resources, false);
      resources.navigatorTabId = null;
    }
  }

  /// Repairs tab reparenting/key routing after the hierarchy has reconciled.
  void afterHierarchyReconcile() {
    if (_isDisposed) return;
    final Set<TerminalWindowId> live = applicationState.windows
        .where(
          (TerminalWindowState window) =>
              window.role == TerminalWindowRole.standard,
        )
        .map((TerminalWindowState window) => window.id)
        .toSet();
    for (final TerminalWindowId stale
        in _resources.keys
            .where((TerminalWindowId id) => !live.contains(id))
            .toList(growable: false)) {
      _resources.remove(stale)!.dispose();
      _fullSizes.remove(stale);
    }
    for (final TerminalWindowState logicalWindow in applicationState.windows) {
      if (logicalWindow.role != TerminalWindowRole.standard) continue;
      final _TerminalContextDockNativeResources? resources =
          _resources[logicalWindow.id];
      final TerminalContextDockWindowSnapshot? dock = dockState
          .snapshotForWindow(logicalWindow.id);
      for (final TerminalTabState tab in logicalWindow.tabs) {
        final Window? nativeWindow = _windowForTab(tab.id);
        if (nativeWindow == null || nativeWindow.isDisposed) continue;
        if (tab.id != logicalWindow.selectedTabId) {
          nativeWindow.keyEventRouting = KeyEventRouting.appKitOnly;
        }
      }
      if (resources == null) continue;
      if (dock?.isVisible != true) {
        _setEditorEditable(resources, false);
        resources
          ..projectedVisible = false
          ..navigatorTabId = null
          ..inputOwnerProjectionPending = false;
        continue;
      }
      final TerminalTabId selectedTabId = logicalWindow.selectedTabId;
      final bool navigatorOwnsInput = dock!.navigatorOwnsInput;
      final bool navigatorTargetChanged =
          navigatorOwnsInput && resources.navigatorTabId != selectedTabId;
      if (!resources.inputOwnerProjectionPending && !navigatorTargetChanged) {
        continue;
      }
      final Window? selectedWindow = _windowForTab(selectedTabId);
      if (selectedWindow == null || selectedWindow.isDisposed) continue;
      if (navigatorOwnsInput) {
        _setEditorEditable(resources, dock.pane.acceptsQuery);
        selectedWindow
          ..keyEventRouting = KeyEventRouting.dartOnly
          ..makeFirstResponder(resources.editor);
        resources.navigatorTabId = selectedTabId;
      } else {
        final View? terminalView = _terminalViewForPane(dock.targetPaneId);
        if (terminalView == null || terminalView.isDisposed) continue;
        selectedWindow
          ..keyEventRouting = KeyEventRouting.appKitOnly
          ..makeFirstResponder(terminalView);
        _setEditorEditable(resources, false);
        resources.navigatorTabId = null;
      }
      resources.inputOwnerProjectionPending = false;
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final _TerminalContextDockNativeResources resources
        in _resources.values) {
      resources.dispose();
    }
    _resources.clear();
    _fullSizes.clear();
  }

  void _publishDocument(
    _TerminalContextDockNativeResources resources,
    TerminalContextDockWindowSnapshot dock,
    TerminalContextDockDirectorySnapshot? directory,
  ) {
    final TerminalContextDockContentSnapshot? content = _contentSnapshot(
      dock.windowId,
    );
    final bool showsDirectory =
        content == null ||
        content.mode == TerminalContextDockContentMode.directoryNavigator;
    final _TerminalContextDockDocument document = showsDirectory
        ? _TerminalContextDockDocument.buildDirectory(
            localization,
            dock,
            directory,
            _pathHandoffSnapshot(dock.windowId),
          )
        : _TerminalContextDockDocument.buildProcess(localization, content);
    _setEditorEditable(
      resources,
      showsDirectory && dock.navigatorOwnsInput && dock.pane.acceptsQuery,
    );
    if (resources.document?.navigatorText != document.navigatorText ||
        resources.document?.selection != document.selection) {
      final TextEditorSelection publicationSelection =
          !showsDirectory && resources.document?.kind == document.kind
          ? _retainedSelection(
              resources.editor.snapshot.selection,
              document.navigatorText.length,
            )
          : document.selection;
      resources.editor.setDocument(
        TextEditorDocument(
          text: document.navigatorText,
          selection: publicationSelection,
        ),
      );
    }
    if (resources.document?.detailsText != document.detailsText) {
      final TextEditorSelection retained =
          resources.document?.kind == document.kind
          ? _retainedSelection(
              resources.details.snapshot.selection,
              document.detailsText.length,
            )
          : const TextEditorSelection(start: 0);
      resources.details.setDocument(
        TextEditorDocument(text: document.detailsText, selection: retained),
      );
    }
    final int? selectedLine = document.selectedLineStart;
    resources.editor.setLineHighlight(
      selectedLine == null
          ? null
          : TextEditorLineHighlight(
              location: selectedLine,
              color: TextViewColor.sRgb(
                red: 0.22,
                green: 0.45,
                blue: 0.82,
                alpha: 0.28,
              ),
            ),
    );
    if (showsDirectory &&
        resources.document?.selectedResultIndex !=
            document.selectedResultIndex &&
        dock.navigatorOwnsInput) {
      if (dock.pane.acceptsQuery && document.selectedLineStart != null) {
        final TextEditorSelection retained =
            resources.editor.snapshot.selection;
        resources.editor
          ..setSelection(
            TextEditorSelection(start: document.selectedLineStart!),
          )
          ..scrollSelectionToVisible()
          ..setSelection(retained);
      } else {
        resources.editor.scrollSelectionToVisible();
      }
    }
    if (showsDirectory &&
        dock.navigatorOwnsInput &&
        dock.pane.acceptsQuery &&
        resources.lastAppliedQuerySelectionGeneration !=
            dock.pane.querySelectionGeneration) {
      resources.editor
        ..setSelection(document.querySelection)
        ..scrollSelectionToVisible();
      resources.lastAppliedQuerySelectionGeneration =
          dock.pane.querySelectionGeneration;
    }
    resources.document = document;
  }

  static TextEditorSelection _retainedSelection(
    TextEditorSelection selection,
    int textLength,
  ) {
    final int start = selection.start.clamp(0, textLength);
    final int length = selection.length.clamp(0, textLength - start);
    return TextEditorSelection(start: start, length: length);
  }

  static void _setEditorEditable(
    _TerminalContextDockNativeResources resources,
    bool editable,
  ) {
    if (resources.editorEditable == editable) return;
    resources.editor.isEditable = editable;
    resources.editorEditable = editable;
  }

  bool canMoveBoundary(TerminalContextDockBoundaryDirection direction) =>
      _boundaryMovement(direction) != null;

  bool moveBoundary(TerminalContextDockBoundaryDirection direction) {
    final (TerminalWindowId, double)? movement = _boundaryMovement(direction);
    if (movement == null) return false;
    dockState.setWidth(movement.$1, movement.$2);
    return true;
  }

  (TerminalWindowId, double)? _boundaryMovement(
    TerminalContextDockBoundaryDirection direction,
  ) {
    if (_isDisposed ||
        applicationState.isDisposed ||
        dockState.isDisposed ||
        applicationState.mutationInProgress)
      return null;
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard)
      return null;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    final TerminalSplitLayoutSize? fullSize = _fullSizes[window.id];
    final _TerminalContextDockNativeResources? resources =
        _resources[window.id];
    if (dock?.isVisible != true ||
        fullSize == null ||
        !_hasRoom(fullSize, window.selectedTab) ||
        resources?.projectedVisible != true ||
        resources!.attachedTabId != window.selectedTabId)
      return null;
    final double step = _cellWidthForPane(dock!.targetPaneId);
    if (!step.isFinite || step <= 0) return null;
    final double current = _effectiveDockWidth(
      dock.width,
      fullSize,
      window.selectedTab,
    );
    final double maximum =
        (fullSize.width -
                _minimumTerminalWidth(window.selectedTab) -
                TerminalContextDockDirectoryLimits.dividerThickness)
            .clamp(
              TerminalContextDockLimits.minimumWidth,
              TerminalContextDockLimits.maximumWidth,
            )
            .toDouble();
    final double next =
        (current +
                (direction == TerminalContextDockBoundaryDirection.left
                    ? step
                    : -step))
            .clamp(TerminalContextDockLimits.minimumWidth, maximum)
            .toDouble();
    return (next - current).abs() <= 1e-9 ? null : (window.id, next);
  }

  static double _defaultCellWidth(PaneId _) => 8;

  bool _shouldShow(
    TerminalWindowState window,
    TerminalTabState tab,
    TerminalSplitLayoutSize fullSize,
    TerminalContextDockWindowSnapshot? dock,
  ) =>
      window.role == TerminalWindowRole.standard &&
      window.selectedTabId == tab.id &&
      dock?.isVisible == true &&
      _hasRoom(fullSize, tab);

  bool _hasRoom(TerminalSplitLayoutSize fullSize, TerminalTabState tab) =>
      fullSize.width >=
          _minimumTerminalWidth(tab) +
              TerminalContextDockLimits.minimumWidth +
              TerminalContextDockDirectoryLimits.dividerThickness &&
      fullSize.height >=
          (_minimumTerminalSizeForTab?.call(tab.id).height ?? 0) &&
      fullSize.height >=
          TerminalContextDockDirectoryLimits.minimumNavigatorHeight +
              TerminalContextDockDirectoryLimits.minimumDetailsHeight +
              TerminalContextDockDirectoryLimits.dividerThickness;

  double _effectiveDockWidth(
    double requested,
    TerminalSplitLayoutSize fullSize,
    TerminalTabState tab,
  ) => requested
      .clamp(
        TerminalContextDockLimits.minimumWidth,
        fullSize.width -
            _minimumTerminalWidth(tab) -
            TerminalContextDockDirectoryLimits.dividerThickness,
      )
      .toDouble();

  double _minimumTerminalWidth(TerminalTabState tab) =>
      (_minimumTerminalSizeForTab?.call(tab.id).width ?? 0)
          .clamp(
            TerminalContextDockDirectoryLimits.minimumTerminalWidth,
            double.infinity,
          )
          .toDouble();

  static double _effectiveDetailsHeight(TerminalSplitLayoutSize fullSize) =>
      TerminalContextDockDirectoryLimits.preferredDetailsHeight
          .clamp(
            TerminalContextDockDirectoryLimits.minimumDetailsHeight,
            fullSize.height -
                TerminalContextDockDirectoryLimits.minimumNavigatorHeight -
                TerminalContextDockDirectoryLimits.dividerThickness,
          )
          .toDouble();

  void _ensureAlive() {
    if (_isDisposed) throw StateError('Context Dock presenter is disposed');
  }

  static TerminalContextDockPathHandoffSnapshot? _noPathHandoffSnapshot(
    TerminalWindowId _,
  ) => null;

  static TerminalContextDockContentSnapshot? _noContentSnapshot(
    TerminalWindowId _,
  ) => null;
}

final class _TerminalContextDockNativeResources {
  _TerminalContextDockNativeResources()
    : editor = TextEditor(
        configuration: const TextEditorConfiguration(
          font: TextViewFont.monospacedSystem(size: 12),
          padding: TextViewPadding.all(10),
          initiallyEditable: false,
        ),
      ),
      details = TextEditor(
        configuration: const TextEditorConfiguration(
          view: ViewConfiguration(
            acceptsFirstResponder: false,
            autoresizesWidth: true,
            autoresizesHeight: true,
          ),
          font: TextViewFont.monospacedSystem(size: 12),
          padding: TextViewPadding.all(10),
          initiallyEditable: false,
        ),
      ),
      contentSplit = TwoPaneSplitView(axis: SplitViewAxis.vertical),
      split = (TwoPaneSplitView(axis: SplitViewAxis.horizontal)
        ..dividerDraggable = false);

  final TextEditor editor;
  final TextEditor details;
  final TwoPaneSplitView contentSplit;
  final TwoPaneSplitView split;
  _TerminalContextDockDocument? document;
  TerminalContextDockAppearance? appearance;
  TerminalTabId? attachedTabId;
  PaneId? attachedPaneId;
  TerminalTabId? navigatorTabId;
  int lastAppliedQuerySelectionGeneration = -1;
  bool editorEditable = false;
  bool projectedVisible = false;
  bool inputOwnerProjectionPending = false;

  void attachContent() {
    if (contentSplit.firstView == null && contentSplit.secondView == null) {
      contentSplit.setChildren(first: editor, second: details);
    }
  }

  void dispose() {
    if (!split.isDisposed) split.dispose();
    if (!contentSplit.isDisposed) contentSplit.dispose();
    if (!details.isDisposed) details.dispose();
    if (!editor.isDisposed) editor.dispose();
  }
}

enum _TerminalContextDockDocumentKind { directory, process }

final class _TerminalContextDockDocument {
  const _TerminalContextDockDocument({
    required this.kind,
    required this.navigatorText,
    required this.detailsText,
    required this.selection,
    required this.queryCaret,
    required this.querySelection,
    required this.selectedLineStart,
    required this.selectedResultIndex,
  });

  final _TerminalContextDockDocumentKind kind;
  final String navigatorText;
  final String detailsText;
  final TextEditorSelection selection;
  final TextEditorSelection queryCaret;
  final TextEditorSelection querySelection;
  final int? selectedLineStart;
  final int selectedResultIndex;

  static _TerminalContextDockDocument buildDirectory(
    TerminalLocalization localization,
    TerminalContextDockWindowSnapshot dock,
    TerminalContextDockDirectorySnapshot? directory,
    TerminalContextDockPathHandoffSnapshot? handoff,
  ) {
    final StringBuffer navigator = StringBuffer();
    void line([String value = '']) => navigator.writeln(value);
    line(localization.contextDockTitle);
    line(
      dock.navigatorOwnsInput
          ? localization.contextDockNavigatorOwnsInput
          : localization.contextDockTerminalOwnsInput,
    );
    line(
      '${localization.contextDockWorkingDirectory}: '
      '${directory?.workingDirectory ?? localization.contextDockUnknown}',
    );
    final String displayedMode = dock.navigatorOwnsInput
        ? switch (dock.pane.navigatorMode) {
            TerminalContextDockNavigatorMode.search =>
              localization.contextDockModeSearch,
            TerminalContextDockNavigatorMode.goTo =>
              localization.contextDockModeGoTo,
            TerminalContextDockNavigatorMode.move =>
              localization.contextDockModeMove,
          }
        : localization.contextDockModeTerminal;
    line('${localization.contextDockMode}: $displayedMode');
    line(
      '${localization.contextDockHiddenEntries}: '
      '${dock.pane.showHiddenEntries ? localization.contextDockHiddenEntriesShown : localization.contextDockHiddenEntriesHidden}',
    );
    final int queryStart = navigator.length;
    navigator.write(switch (dock.pane.navigatorMode) {
      TerminalContextDockNavigatorMode.search =>
        '${localization.contextDockSearch}: ',
      TerminalContextDockNavigatorMode.goTo =>
        '${localization.contextDockGoTo}: ',
      TerminalContextDockNavigatorMode.move => localization.contextDockMoveHint,
    });
    final int queryValueStart = navigator.length;
    if (dock.pane.acceptsQuery) navigator.write(dock.pane.query);
    line();
    line();
    final List<TerminalContextDockDirectoryRow> rows =
        directory?.rows ?? const <TerminalContextDockDirectoryRow>[];
    final int selectedIndex = dock.pane.selectedResultIndex;
    int? selectedLineStart;
    TerminalFileSearchSource? previousSource;
    for (var index = 0; index < rows.length; index++) {
      final TerminalContextDockDirectoryRow row = rows[index];
      if (directory?.isSearch == true &&
          row.searchSource != previousSource &&
          row.searchSource != null) {
        if (previousSource != null) line();
        line(_searchSource(localization, row.searchSource!));
        previousSource = row.searchSource;
      }
      if (index == selectedIndex) selectedLineStart = navigator.length;
      final String marker = switch (row.entry.kind) {
        TerminalDirectoryEntryKind.directory => row.isExpanded ? '▾' : '▸',
        TerminalDirectoryEntryKind.file => '·',
        TerminalDirectoryEntryKind.symbolicLink => '↗',
        TerminalDirectoryEntryKind.other => '◇',
      };
      final String suffix =
          row.entry.kind == TerminalDirectoryEntryKind.directory ? '/' : '';
      final String childStatus = row.isLoadingChildren
          ? ' ${localization.contextDockLoadingInline}'
          : row.childUnavailable
          ? ' ${localization.contextDockUnavailableInline}'
          : '';
      final String indentation = List<String>.filled(row.depth, '  ').join();
      line('$indentation$marker ${row.entry.name}$suffix$childStatus');
    }
    if (rows.isEmpty) {
      line(_statusText(localization, directory?.status));
    } else if (directory?.status ==
        TerminalContextDockDirectoryStatus.partial) {
      line();
      line(localization.contextDockPartial(directory!.omittedEntryCount));
    }
    if (directory?.isSearch == true && directory!.searchCoverage.isNotEmpty) {
      line();
      line(localization.contextDockCoverage);
      for (final TerminalFileSearchCoverage coverage
          in directory.searchCoverage) {
        line(
          '${_searchSource(localization, coverage.source)}: '
          '${_coverage(localization, coverage.disposition)}',
        );
      }
    }
    final StringBuffer details = StringBuffer();
    void detailLine([String value = '']) => details.writeln(value);
    if (handoff != null) {
      detailLine(localization.contextDockPathActions);
      if (handoff.canCopy) detailLine(localization.contextDockCopyPathHint);
      if (handoff.canInsert) {
        detailLine(localization.contextDockInsertPathHint);
      }
      if (!handoff.canInsert) {
        detailLine(_pathBlock(localization, handoff.block));
      }
      detailLine();
    }
    detailLine(localization.contextDockDetails);
    final TerminalContextDockDirectoryRow? selected =
        selectedIndex >= 0 && selectedIndex < rows.length
        ? rows[selectedIndex]
        : null;
    if (selected == null) {
      detailLine(localization.contextDockNoSelection);
    } else {
      final TerminalDirectoryEntrySnapshot entry = selected.entry;
      detailLine('${localization.contextDockName}: ${entry.name}');
      detailLine(
        '${localization.contextDockKind}: ${_kind(localization, entry.kind)}',
      );
      detailLine('${localization.contextDockPath}: ${entry.path}');
      final TerminalDirectoryEntryMetadataSnapshot metadata = entry.metadata;
      if (metadata.disposition ==
          TerminalDirectoryMetadataDisposition.unavailable) {
        detailLine(localization.contextDockMetadataUnavailable);
      } else {
        if (metadata.mode != null) {
          detailLine(
            '${localization.contextDockPermissions}: '
            '${_permissions(metadata.mode!)}',
          );
        }
        if (metadata.size != null) {
          detailLine('${localization.contextDockSize}: ${metadata.size} B');
        }
        if (metadata.modifiedMicrosecondsSinceEpoch != null) {
          detailLine(
            '${localization.contextDockModified}: '
            '${DateTime.fromMicrosecondsSinceEpoch(metadata.modifiedMicrosecondsSinceEpoch!).toLocal().toIso8601String()}',
          );
        }
        if (metadata.ownerUserId != null || metadata.ownerGroupId != null) {
          detailLine(
            '${localization.contextDockOwner}: '
            '${metadata.ownerUserId ?? '-'}:${metadata.ownerGroupId ?? '-'}',
          );
        }
        if (metadata.symlinkTarget != null) {
          detailLine(
            '${localization.contextDockLinkTarget}: '
            '${metadata.symlinkTarget}',
          );
        }
      }
    }
    final TextEditorSelection querySelection = TextEditorSelection(
      start: queryValueStart,
      length: dock.pane.query.length,
    );
    final TextEditorSelection queryCaret = TextEditorSelection(
      start: queryValueStart + dock.pane.query.length,
    );
    final TextEditorSelection selection =
        dock.navigatorOwnsInput && dock.pane.acceptsQuery
        ? queryCaret
        : dock.navigatorOwnsInput && selectedLineStart != null
        ? TextEditorSelection(start: selectedLineStart)
        : TextEditorSelection(start: queryStart);
    return _TerminalContextDockDocument(
      kind: _TerminalContextDockDocumentKind.directory,
      navigatorText: navigator.toString(),
      detailsText: details.toString(),
      selection: selection,
      queryCaret: queryCaret,
      querySelection: querySelection,
      selectedLineStart: selectedLineStart,
      selectedResultIndex: selectedIndex,
    );
  }

  static _TerminalContextDockDocument buildProcess(
    TerminalLocalization localization,
    TerminalContextDockContentSnapshot content,
  ) {
    final StringBuffer navigator = StringBuffer();
    void line([String value = '']) => navigator.writeln(value);
    line(localization.processInspectorTitle);
    line(
      '${localization.processInspectorView}: '
      '${localization.processInspectorTitle}',
    );
    line(
      '${localization.processInspectorInput}: '
      '${localization.processInspectorTerminal}',
    );

    final TerminalContextDockProcessSnapshot? process = content.process;
    switch (content.mode) {
      case TerminalContextDockContentMode.foregroundJob:
        if (process == null ||
            process.status == TerminalContextDockProcessStatus.loading) {
          line(localization.processInspectorLoading);
        } else {
          line(
            '${localization.processInspectorRunning} · '
            '${_elapsed(process.elapsedMicroseconds)}',
          );
          line(
            localization.processInspectorForegroundJob(
              process.totalMemberCount,
            ),
          );
          if (process.status == TerminalContextDockProcessStatus.partial ||
              process.status == TerminalContextDockProcessStatus.unavailable) {
            line(localization.processInspectorPartial);
          }
          line();
          line(localization.processInspectorProcessList);
          for (var index = 0; index < process.members.length; index++) {
            final TerminalContextDockProcessMember member =
                process.members[index];
            final String marker = index == process.primaryIndex ? '●' : ' ';
            final String name = _displayValue(
              member.name.isEmpty
                  ? localization.processInspectorFieldUnavailable
                  : member.name,
            );
            line(
              '$marker $name  ${localization.processInspectorPid} '
              '${member.processId} · ${_elapsed(member.elapsedMicroseconds)}',
            );
          }
          if (process.omittedMemberCount > 0) {
            line(
              localization.processInspectorOmittedProcesses(
                process.omittedMemberCount,
              ),
            );
          }
          if (process.members.isEmpty) {
            line(localization.processInspectorUnavailable);
          }
        }
        break;
      case TerminalContextDockContentMode.shellOwnedCommand:
        line(
          '${localization.processInspectorObservedRunning} · '
          '${_elapsed(process?.elapsedMicroseconds ?? 0)}',
        );
        line(localization.processInspectorShellCommand);
        break;
      case TerminalContextDockContentMode.protected:
        line(localization.processInspectorProtected);
        line(localization.processInspectorProtectedHelp);
        break;
      case TerminalContextDockContentMode.unavailable:
        line(localization.processInspectorUnavailable);
        break;
      case TerminalContextDockContentMode.directoryNavigator:
        throw StateError('Directory content requires the directory document');
    }

    // Process metadata belongs to the same scrollable document as the job
    // summary. Only Directory Navigator keeps a pinned details document.
    if (content.mode == TerminalContextDockContentMode.foregroundJob &&
        process != null &&
        process.status != TerminalContextDockProcessStatus.loading) {
      line();
      line(localization.processInspectorExecutable);
      line(
        process.executablePath == null
            ? localization.processInspectorFieldUnavailable
            : _displayValue(process.executablePath!),
      );
      line();
      line(localization.processInspectorCommandArgv);
      if (!content.argumentsVisible) {
        line(localization.processInspectorArgumentsHidden);
      } else if (process.argumentsHidden) {
        line(localization.processInspectorArgumentsRefreshing);
      } else if (process.arguments.isEmpty) {
        line(localization.processInspectorFieldUnavailable);
      } else {
        line(process.arguments.map(_argumentToken).join('  '));
      }
      if (content.argumentsVisible &&
          !process.argumentsHidden &&
          process.omittedArgumentCount > 0) {
        line(
          localization.processInspectorOmittedArguments(
            process.omittedArgumentCount,
          ),
        );
      }
      if (content.argumentsVisible &&
          !process.argumentsHidden &&
          process.argumentsTruncated) {
        line(localization.processInspectorArgumentsTruncated);
      }
      line();
      final TerminalContextDockForegroundJobIdentity? identity =
          process.identity;
      final TerminalContextDockProcessMember? primary = process.primaryProcess;
      line(
        '${localization.processInspectorPid} '
        '${primary?.processId ?? '-'} · '
        '${localization.processInspectorPgid} '
        '${identity?.foregroundProcessGroup ?? '-'}',
      );
    } else if (content.mode ==
        TerminalContextDockContentMode.shellOwnedCommand) {
      line();
      line(localization.processInspectorShellDetailsUnavailable);
    }
    return _TerminalContextDockDocument(
      kind: _TerminalContextDockDocumentKind.process,
      navigatorText: navigator.toString(),
      detailsText: '',
      selection: const TextEditorSelection(start: 0),
      queryCaret: const TextEditorSelection(start: 0),
      querySelection: const TextEditorSelection(start: 0),
      selectedLineStart: null,
      selectedResultIndex: -1,
    );
  }

  static String _elapsed(int microseconds) {
    final int totalSeconds = microseconds < 0
        ? 0
        : microseconds ~/ Duration.microsecondsPerSecond;
    final int hours = totalSeconds ~/ Duration.secondsPerHour;
    final int minutes = (totalSeconds ~/ Duration.secondsPerMinute) % 60;
    final int seconds = totalSeconds % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return hours == 0
        ? '$mm:$ss'
        : '${hours.toString().padLeft(2, '0')}:$mm:$ss';
  }

  static String _argumentToken(String value) =>
      '"${_displayValue(value, escapeQuote: true)}"';

  static String _displayValue(String value, {bool escapeQuote = false}) {
    final StringBuffer output = StringBuffer();
    for (final int scalar in value.runes) {
      switch (scalar) {
        case 0x09:
          output.write(r'\t');
        case 0x0a:
          output.write(r'\n');
        case 0x0d:
          output.write(r'\r');
        case 0x5c:
          output.write(r'\\');
        case 0x22 when escapeQuote:
          output.write(r'\"');
        default:
          if (_isUnsafeDisplayScalar(scalar)) {
            output.write('\\u{${scalar.toRadixString(16)}}');
          } else {
            output.writeCharCode(scalar);
          }
      }
    }
    return output.toString();
  }

  static bool _isUnsafeDisplayScalar(int scalar) =>
      scalar < 0x20 ||
      (scalar >= 0x7f && scalar <= 0x9f) ||
      (scalar >= 0x202a && scalar <= 0x202e) ||
      (scalar >= 0x2066 && scalar <= 0x2069);

  static String _statusText(
    TerminalLocalization localization,
    TerminalContextDockDirectoryStatus? status,
  ) => switch (status) {
    TerminalContextDockDirectoryStatus.loading =>
      localization.contextDockLoading,
    TerminalContextDockDirectoryStatus.empty => localization.contextDockEmpty,
    TerminalContextDockDirectoryStatus.remoteUnavailable =>
      localization.contextDockRemoteUnavailable,
    TerminalContextDockDirectoryStatus.privacyUnavailable =>
      localization.contextDockPrivacyUnavailable,
    TerminalContextDockDirectoryStatus.partial =>
      localization.contextDockPartial(0),
    TerminalContextDockDirectoryStatus.ready => localization.contextDockEmpty,
    TerminalContextDockDirectoryStatus.unavailable ||
    null => localization.contextDockUnavailable,
  };

  static String _kind(
    TerminalLocalization localization,
    TerminalDirectoryEntryKind kind,
  ) => switch (kind) {
    TerminalDirectoryEntryKind.directory => localization.contextDockFolder,
    TerminalDirectoryEntryKind.file => localization.contextDockFile,
    TerminalDirectoryEntryKind.symbolicLink =>
      localization.contextDockSymbolicLink,
    TerminalDirectoryEntryKind.other => localization.contextDockOther,
  };

  static String _searchSource(
    TerminalLocalization localization,
    TerminalFileSearchSource source,
  ) => switch (source) {
    TerminalFileSearchSource.currentSubtree =>
      localization.contextDockSearchCurrentSubtree,
    TerminalFileSearchSource.recent => localization.contextDockSearchRecent,
    TerminalFileSearchSource.explicit => localization.contextDockSearchExplicit,
    TerminalFileSearchSource.systemIndex =>
      localization.contextDockSearchSystemIndex,
  };

  static String _coverage(
    TerminalLocalization localization,
    TerminalFileSearchCoverageDisposition disposition,
  ) => switch (disposition) {
    TerminalFileSearchCoverageDisposition.searching =>
      localization.contextDockCoverageSearching,
    TerminalFileSearchCoverageDisposition.complete =>
      localization.contextDockCoverageComplete,
    TerminalFileSearchCoverageDisposition.partial =>
      localization.contextDockCoveragePartial,
    TerminalFileSearchCoverageDisposition.unavailable =>
      localization.contextDockCoverageUnavailable,
  };

  static String _pathBlock(
    TerminalLocalization localization,
    TerminalContextDockPathInsertionBlock block,
  ) => switch (block) {
    TerminalContextDockPathInsertionBlock.none =>
      localization.contextDockPathActionsReady,
    TerminalContextDockPathInsertionBlock.navigatorInactive =>
      localization.contextDockPathActionsNavigatorInactive,
    TerminalContextDockPathInsertionBlock.noSelection =>
      localization.contextDockPathActionsNoSelection,
    TerminalContextDockPathInsertionBlock.staleTarget =>
      localization.contextDockPathActionsStale,
    TerminalContextDockPathInsertionBlock.remote =>
      localization.contextDockPathActionsRemote,
    TerminalContextDockPathInsertionBlock.secureInput =>
      localization.contextDockPathActionsSecure,
    TerminalContextDockPathInsertionBlock.alternateScreen =>
      localization.contextDockPathActionsAlternate,
    TerminalContextDockPathInsertionBlock.foregroundProcess =>
      localization.contextDockPathActionsForeground,
    TerminalContextDockPathInsertionBlock.busy =>
      localization.contextDockPathActionsBusy,
    TerminalContextDockPathInsertionBlock.disposed =>
      localization.contextDockPathActionsStale,
  };

  static String _permissions(int mode) {
    const List<int> bits = <int>[
      0x100,
      0x80,
      0x40,
      0x20,
      0x10,
      0x8,
      0x4,
      0x2,
      0x1,
    ];
    const List<String> labels = <String>[
      'r',
      'w',
      'x',
      'r',
      'w',
      'x',
      'r',
      'w',
      'x',
    ];
    return <String>[
      for (var index = 0; index < bits.length; index++)
        (mode & bits[index]) == 0 ? '-' : labels[index],
    ].join();
  }
}
