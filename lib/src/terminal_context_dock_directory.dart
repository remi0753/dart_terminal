import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';
import 'terminal_context_dock.dart';
import 'terminal_context_dock_path_handoff.dart';
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
        (window.searchOperation == null ? 0 : 1),
  );

  TerminalContextDockDirectorySnapshot? snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed) return null;
    final _TerminalContextDockDirectoryWindowState? window = _windows[windowId];
    if (window == null) return null;
    return _project(window);
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

  /// Coalesces high-frequency terminal output into one cwd observation.
  void scheduleSynchronize() {
    if (_isDisposed || _scheduledSynchronization != null) return;
    _scheduledSynchronization = Timer(
      TerminalContextDockDirectoryLimits.terminalChangeDebounce,
      () {
        _scheduledSynchronization = null;
        synchronize();
      },
    );
  }

  /// Re-resolves cwd on terminal output/focus changes and cancels stale work.
  void synchronize() {
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
          _replacePrivacyUnavailable(logicalWindow.id, dock.targetPaneId);
          continue;
        }
        TerminalWorkingDirectoryResolution? resolution;
        try {
          resolution = _resolveWorkingDirectory(
            dock.targetPaneId,
            ++_generation,
          );
        } on Object {
          _replaceUnavailable(logicalWindow.id, dock.targetPaneId);
          continue;
        }
        final _TerminalContextDockDirectoryWindowState? retained =
            _windows[logicalWindow.id];
        if (retained != null && retained.matches(dock, resolution)) {
          retained.resolution = resolution;
          if (resolution.isAvailable) _recordRecentRoot(resolution.path!);
          _ensureExpandedLoads(retained);
          _ensureSearch(retained, dock);
          _publishResultCount(retained);
          continue;
        }
        retained?.cancel();
        final _TerminalContextDockDirectoryWindowState next =
            _TerminalContextDockDirectoryWindowState(
              windowId: logicalWindow.id,
              paneId: dock.targetPaneId,
              generation: ++_generation,
              resolution: resolution,
            );
        _windows[logicalWindow.id] = next;
        if (resolution.isAvailable) {
          _recordRecentRoot(resolution.path!);
          _startLoad(next, resolution.path!, isRoot: true);
          _ensureSearch(next, dock);
        }
        _publishResultCount(next);
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
    if (dock == null || window == null || dock.pane.query.isNotEmpty) {
      return false;
    }
    final TerminalContextDockDirectorySnapshot projection = _project(window);
    final int selected = dock.pane.selectedResultIndex;
    if (selected < 0 || selected >= projection.rows.length) return false;
    final TerminalContextDockDirectoryRow row = projection.rows[selected];
    final Set<String> expanded = _expandedByPane.putIfAbsent(
      window.paneId,
      () => <String>{},
    );
    switch (intent) {
      case TerminalContextDockTreeIntent.expand:
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
        _collapse(window, collapsePath);
        _publishResultCount(window);
        final List<TerminalContextDockDirectoryRow> rows = _project(window)
            .rows;
        final int parentIndex = rows.indexWhere(
          (TerminalContextDockDirectoryRow value) =>
              value.entry.path == collapsePath,
        );
        if (parentIndex >= 0 && rows.isNotEmpty) {
          dockState.setSelectedResultIndex(windowId, parentIndex);
        }
        _onChanged?.call();
        return true;
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _scheduledSynchronization?.cancel();
    _scheduledSynchronization = null;
    _clearWindows();
    _expandedByPane.clear();
    _recentRoots.clear();
  }

  void _replaceUnavailable(TerminalWindowId windowId, PaneId paneId) {
    _windows.remove(windowId)?.cancel();
    final _TerminalContextDockDirectoryWindowState next =
        _TerminalContextDockDirectoryWindowState(
          windowId: windowId,
          paneId: paneId,
          generation: ++_generation,
          resolution: null,
          privacyRestricted: false,
        );
    _windows[windowId] = next;
    _publishResultCount(next);
    _onChanged?.call();
  }

  void _replacePrivacyUnavailable(TerminalWindowId windowId, PaneId paneId) {
    final _TerminalContextDockDirectoryWindowState? retained =
        _windows[windowId];
    if (retained?.paneId == paneId && retained?.privacyRestricted == true) {
      _publishResultCount(retained!);
      return;
    }
    retained?.cancel();
    final _TerminalContextDockDirectoryWindowState next =
        _TerminalContextDockDirectoryWindowState(
          windowId: windowId,
          paneId: paneId,
          generation: ++_generation,
          resolution: null,
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
      _startLoad(window, path, isRoot: false);
    }
  }

  void _ensureSearch(
    _TerminalContextDockDirectoryWindowState window,
    TerminalContextDockWindowSnapshot dock,
  ) {
    final String queryText = dock.pane.query;
    if (queryText.isEmpty || window.resolution?.isAvailable != true) {
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
      dockState.snapshotForWindow(window.windowId)?.pane.query == query;

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
  }

  TerminalContextDockDirectorySnapshot _project(
    _TerminalContextDockDirectoryWindowState window,
  ) {
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.windowId,
    );
    final TerminalWorkingDirectoryResolution? resolution = window.resolution;
    final TerminalDirectorySnapshot? root = window.rootSnapshot;
    final String query = dock?.pane.query ?? '';
    if (resolution?.isAvailable == true &&
        query.isNotEmpty &&
        !TerminalFileSearchQuery.parse(query).isEmpty) {
      final TerminalFileSearchSnapshot? search = window.searchSnapshot;
      final List<TerminalContextDockDirectoryRow> searchRows =
          <TerminalContextDockDirectoryRow>[
            for (final TerminalFileSearchResult result
                in search?.results ?? const <TerminalFileSearchResult>[])
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
    this.privacyRestricted = false,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int generation;
  TerminalWorkingDirectoryResolution? resolution;
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

  bool matches(
    TerminalContextDockWindowSnapshot dock,
    TerminalWorkingDirectoryResolution next,
  ) =>
      paneId == dock.targetPaneId &&
      resolution?.disposition == next.disposition &&
      resolution?.path == next.path;

  void cancel() {
    cancelSearch();
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
  }) : _windowForTab = windowForTab,
       _terminalViewForPane = terminalViewForPane,
       _pathHandoffSnapshot = pathHandoffSnapshot ?? _noPathHandoffSnapshot;

  final TerminalApplicationState applicationState;
  final TerminalContextDockState dockState;
  final TerminalContextDockDirectoryController directoryController;
  final TerminalLocalization localization;
  final Window? Function(TerminalTabId tabId) _windowForTab;
  final View? Function(PaneId paneId) _terminalViewForPane;
  final TerminalContextDockPathHandoffSnapshotResolver _pathHandoffSnapshot;
  final Map<TerminalWindowId, _TerminalContextDockNativeResources> _resources =
      <TerminalWindowId, _TerminalContextDockNativeResources>{};
  final Map<TerminalWindowId, TerminalSplitLayoutSize> _fullSizes =
      <TerminalWindowId, TerminalSplitLayoutSize>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get resourceCount => _resources.length;

  TextEditorSnapshot? nativeEditorSnapshotForWindow(TerminalWindowId windowId) {
    if (_isDisposed) return null;
    final TextEditor? editor = _resources[windowId]?.editor;
    return editor == null || editor.isDisposed ? null : editor.snapshot;
  }

  String? nativeDetailsTextForWindow(TerminalWindowId windowId) {
    if (_isDisposed) return null;
    final TextView? details = _resources[windowId]?.details;
    return details == null || details.isDisposed ? null : details.text;
  }

  bool get canFocusNavigator {
    if (_isDisposed || applicationState.isDisposed || dockState.isDisposed) {
      return false;
    }
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) {
      return false;
    }
    final TerminalSplitLayoutSize? fullSize = _fullSizes[window.id];
    return fullSize == null || _hasRoom(fullSize);
  }

  TerminalSplitLayoutSize resolveTerminalLayoutSize(
    TerminalWindowState window,
    TerminalTabState tab,
    TerminalSplitLayoutSize fullSize,
  ) {
    _ensureAlive();
    _fullSizes[window.id] = fullSize;
    TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
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
    final _TerminalContextDockNativeResources? resources =
        _resources[window.id];
    if (resources != null && resources.positioned) {
      _captureNativeWidth(window.id, resources, fullSize);
      dock = dockState.snapshotForWindow(window.id);
    }
    final double dockWidth = _effectiveDockWidth(dock!.width, fullSize);
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
    final bool rootAttachmentChanged =
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
    final double dockWidth = _effectiveDockWidth(visibleDock.width, fullSize);
    resources.split.setPosition(
      fraction: (usable - dockWidth) / usable,
      firstMinimumExtent:
          TerminalContextDockDirectoryLimits.minimumTerminalWidth,
      secondMinimumExtent: TerminalContextDockLimits.minimumWidth,
    );
    resources
      ..positioned = true
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
    window
      ..keyEventRouting = KeyEventRouting.dartOnly
      ..makeFirstResponder(resources.editor);
    final _TerminalContextDockDocument document = resources.document!;
    resources.editor.setSelection(document.querySelection);
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
    _resources[request.windowId]?.navigatorTabId = null;
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
    final _TerminalContextDockDocument document =
        _TerminalContextDockDocument.build(
          localization,
          dock,
          directory,
          _pathHandoffSnapshot(dock.windowId),
        );
    if (resources.document?.navigatorText != document.navigatorText ||
        resources.document?.selection != document.selection) {
      resources.editor.setDocument(
        TextEditorDocument(
          text: document.navigatorText,
          selection: document.selection,
        ),
      );
    }
    if (resources.document?.detailsText != document.detailsText) {
      resources.details.text = document.detailsText;
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
    if (resources.document?.selectedResultIndex !=
            document.selectedResultIndex &&
        dock.navigatorOwnsInput &&
        resources.lastAppliedQuerySelectionGeneration ==
            dock.pane.querySelectionGeneration) {
      resources.editor.scrollSelectionToVisible();
    }
    resources.document = document;
  }

  void _captureNativeWidth(
    TerminalWindowId windowId,
    _TerminalContextDockNativeResources resources,
    TerminalSplitLayoutSize fullSize,
  ) {
    try {
      final double fraction = resources.split.refreshFraction();
      final double usable =
          fullSize.width - TerminalContextDockDirectoryLimits.dividerThickness;
      final double observed = usable * (1 - fraction);
      if (observed >= TerminalContextDockLimits.minimumWidth &&
          observed <= TerminalContextDockLimits.maximumWidth) {
        dockState.setWidth(windowId, observed);
      }
    } on AppKitNativeException catch (error) {
      if (error.status != 8) rethrow;
    }
  }

  static bool _shouldShow(
    TerminalWindowState window,
    TerminalTabState tab,
    TerminalSplitLayoutSize fullSize,
    TerminalContextDockWindowSnapshot? dock,
  ) =>
      window.role == TerminalWindowRole.standard &&
      window.selectedTabId == tab.id &&
      dock?.isVisible == true &&
      _hasRoom(fullSize);

  static bool _hasRoom(TerminalSplitLayoutSize fullSize) =>
      fullSize.width >=
          TerminalContextDockDirectoryLimits.minimumTerminalWidth +
              TerminalContextDockLimits.minimumWidth +
              TerminalContextDockDirectoryLimits.dividerThickness &&
      fullSize.height >=
          TerminalContextDockDirectoryLimits.minimumNavigatorHeight +
              TerminalContextDockDirectoryLimits.minimumDetailsHeight +
              TerminalContextDockDirectoryLimits.dividerThickness;

  static double _effectiveDockWidth(
    double requested,
    TerminalSplitLayoutSize fullSize,
  ) => requested
      .clamp(
        TerminalContextDockLimits.minimumWidth,
        fullSize.width -
            TerminalContextDockDirectoryLimits.minimumTerminalWidth -
            TerminalContextDockDirectoryLimits.dividerThickness,
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
      details = TextView(
        configuration: const TextViewConfiguration(
          view: ViewConfiguration(
            acceptsFirstResponder: false,
            autoresizesWidth: true,
            autoresizesHeight: true,
          ),
          font: TextViewFont.monospacedSystem(size: 12),
          padding: TextViewPadding.all(10),
        ),
      ),
      contentSplit = TwoPaneSplitView(axis: SplitViewAxis.vertical),
      split = TwoPaneSplitView(axis: SplitViewAxis.horizontal);

  final TextEditor editor;
  final TextView details;
  final TwoPaneSplitView contentSplit;
  final TwoPaneSplitView split;
  _TerminalContextDockDocument? document;
  TerminalTabId? attachedTabId;
  PaneId? attachedPaneId;
  TerminalTabId? navigatorTabId;
  int lastAppliedQuerySelectionGeneration = -1;
  bool positioned = false;
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

final class _TerminalContextDockDocument {
  const _TerminalContextDockDocument({
    required this.navigatorText,
    required this.detailsText,
    required this.selection,
    required this.querySelection,
    required this.selectedLineStart,
    required this.selectedResultIndex,
  });

  final String navigatorText;
  final String detailsText;
  final TextEditorSelection selection;
  final TextEditorSelection querySelection;
  final int? selectedLineStart;
  final int selectedResultIndex;

  static _TerminalContextDockDocument build(
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
    final int queryStart = navigator.length;
    navigator.write('${localization.contextDockSearch}: ');
    final int queryValueStart = navigator.length;
    navigator.write(dock.pane.query);
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
    final TextEditorSelection selection =
        dock.navigatorOwnsInput && selectedLineStart != null
        ? TextEditorSelection(start: selectedLineStart)
        : TextEditorSelection(start: queryStart);
    return _TerminalContextDockDocument(
      navigatorText: navigator.toString(),
      detailsText: details.toString(),
      selection: selection,
      querySelection: querySelection,
      selectedLineStart: selectedLineStart,
      selectedResultIndex: selectedIndex,
    );
  }

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
