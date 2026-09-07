import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart'
    show ApplicationReopenRequestedEvent, Window, WindowEvent;

import 'terminal_application_state.dart';
import 'terminal_native_hierarchy.dart';
import 'terminal_pane.dart';
import 'terminal_restoration.dart';

/// Content-free persistence boundary for one encoded restoration snapshot.
abstract interface class TerminalRestorationStore {
  Future<String?> read();

  Future<void> write(String encoded);
}

/// Bounded same-directory replacement store for a local restoration file.
final class FileTerminalRestorationStore implements TerminalRestorationStore {
  FileTerminalRestorationStore(String path) : path = _validatePath(path);

  static const int maximumPathUtf8Bytes = 4096;

  final String path;

  @override
  Future<String?> read() async {
    final File file = File(path);
    if (!await file.exists()) return null;
    final RandomAccessFile opened = await file.open();
    try {
      final List<int> bytes = await opened.read(
        TerminalRestorationLimits.maximumSerializedUtf8Bytes + 1,
      );
      if (bytes.length > TerminalRestorationLimits.maximumSerializedUtf8Bytes) {
        throw const TerminalRestorationLimitException(
          'restoration file exceeds its serialized input limit',
        );
      }
      return utf8.decode(bytes, allowMalformed: false);
    } finally {
      await opened.close();
    }
  }

  @override
  Future<void> write(String encoded) async {
    final int encodedBytes = utf8.encode(encoded).length;
    if (encodedBytes > TerminalRestorationLimits.maximumSerializedUtf8Bytes) {
      throw const TerminalRestorationLimitException(
        'restoration file exceeds its serialized output limit',
      );
    }
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    final String parentPath = separator == 0
        ? Platform.pathSeparator
        : path.substring(0, separator);
    await Directory(parentPath).create(recursive: true);
    final File pending = File('$path.pending');
    try {
      await pending.writeAsString(encoded, flush: true);
      await pending.rename(path);
    } on Object {
      try {
        if (await pending.exists()) await pending.delete();
      } on Object {
        // The owned pending file is best-effort cleanup after the primary error.
      }
      rethrow;
    }
  }

  static String _validatePath(String path) {
    if (!File(path).isAbsolute ||
        path.contains('\u0000') ||
        utf8.encode(path).length > maximumPathUtf8Bytes) {
      throw ArgumentError.value(
        path,
        'path',
        'must be an absolute local path within the UTF-8 bound',
      );
    }
    if (path.endsWith(Platform.pathSeparator)) {
      throw ArgumentError.value(path, 'path', 'must identify a file');
    }
    return path;
  }
}

enum TerminalRestorationLoadDisposition {
  restored,
  missing,
  rejected,
  unavailable,
}

final class TerminalRestorationLoadResult {
  const TerminalRestorationLoadResult({
    required this.disposition,
    this.snapshot,
  });

  final TerminalRestorationLoadDisposition disposition;
  final TerminalRestorationSnapshot? snapshot;
}

enum TerminalRestorationSaveDisposition { saved, captureRejected, unavailable }

final class TerminalRestorationSaveResult {
  const TerminalRestorationSaveResult(this.disposition);

  final TerminalRestorationSaveDisposition disposition;
}

/// Converts persistence errors into path- and content-free recovery outcomes.
final class TerminalRestorationPersistence {
  const TerminalRestorationPersistence(this.store);

  final TerminalRestorationStore store;

  Future<TerminalRestorationLoadResult> load() async {
    try {
      final String? encoded = await store.read();
      if (encoded == null) {
        return const TerminalRestorationLoadResult(
          disposition: TerminalRestorationLoadDisposition.missing,
        );
      }
      return TerminalRestorationLoadResult(
        disposition: TerminalRestorationLoadDisposition.restored,
        snapshot: TerminalRestorationCodec.decode(encoded),
      );
    } on FormatException catch (_) {
      return const TerminalRestorationLoadResult(
        disposition: TerminalRestorationLoadDisposition.rejected,
      );
    } on ArgumentError catch (_) {
      return const TerminalRestorationLoadResult(
        disposition: TerminalRestorationLoadDisposition.rejected,
      );
    } on TerminalRestorationLimitException catch (_) {
      return const TerminalRestorationLoadResult(
        disposition: TerminalRestorationLoadDisposition.rejected,
      );
    } on Object catch (_) {
      return const TerminalRestorationLoadResult(
        disposition: TerminalRestorationLoadDisposition.unavailable,
      );
    }
  }

  Future<TerminalRestorationSaveResult> save(
    TerminalRestorationSnapshot snapshot,
  ) async {
    try {
      await store.write(TerminalRestorationCodec.encode(snapshot));
      return const TerminalRestorationSaveResult(
        TerminalRestorationSaveDisposition.saved,
      );
    } on Object catch (_) {
      return const TerminalRestorationSaveResult(
        TerminalRestorationSaveDisposition.unavailable,
      );
    }
  }
}

enum TerminalRestorationDiagnosticKind {
  loaded,
  missing,
  rejected,
  unavailable,
  restoreFailed,
  defaultCreated,
  saved,
  captureRejected,
  saveUnavailable,
  suspended,
  presentedExisting,
  reopened,
  disposed,
}

/// Deliberately excludes paths, terminal content, process data, and errors.
final class TerminalRestorationDiagnostic {
  const TerminalRestorationDiagnostic(
    this.kind, {
    this.windows = 0,
    this.tabs = 0,
    this.panes = 0,
  });

  final TerminalRestorationDiagnosticKind kind;
  final int windows;
  final int tabs;
  final int panes;

  String machineLine() =>
      'TERMINAL_RESTORATION event=${kind.name} windows=$windows '
      'tabs=$tabs panes=$panes';
}

typedef TerminalRestorationHierarchyFactory =
    TerminalNativeHierarchyAdapter Function({
      required TerminalApplicationState state,
      required Map<TerminalWindowId, TerminalWindowPlacement> placements,
    });
typedef TerminalRestorationStateFactory = TerminalApplicationState Function({
  required int initialPaneId,
  required int initialWindowId,
  required int initialTabId,
  required int initialSplitNodeId,
});
typedef TerminalRestorationScreensProvider =
    Iterable<TerminalScreenPlacement> Function();
typedef TerminalRestorationDiagnosticObserver = void Function(
  TerminalRestorationDiagnostic diagnostic,
);

final class TerminalRestorationGeneration {
  TerminalRestorationGeneration._({
    required this.state,
    required this.hierarchy,
    required Map<PaneId, String?> launchWorkingDirectories,
    required Map<TerminalTabId, StreamSubscription<WindowEvent>> subscriptions,
  }) : launchWorkingDirectories = Map<PaneId, String?>.unmodifiable(
         launchWorkingDirectories,
       ),
       _subscriptions = subscriptions;

  final TerminalApplicationState state;
  final TerminalNativeHierarchyAdapter hierarchy;
  final Map<PaneId, String?> launchWorkingDirectories;
  final Map<TerminalTabId, StreamSubscription<WindowEvent>> _subscriptions;
  bool _disposed = false;

  bool get isDisposed => _disposed;
}

enum TerminalRestorationStartDisposition { restored, defaultCreated }

enum TerminalRestorationReopenDisposition {
  ignoredVisible,
  presentedExisting,
  restored,
  defaultCreated,
}

/// Owns replaceable logical/native generations across close and Dock reopen.
final class TerminalRestorationLifecycle {
  TerminalRestorationLifecycle({
    required this.persistence,
    required this.configurationForPane,
    required this.hierarchyFactory,
    required this.defaultPlacement,
    required this.workingDirectoryForPane,
    this.defaultWorkingDirectory,
    this.stateFactory = _defaultStateFactory,
    this.availableScreens = _noScreens,
    this.fallbackDisplayId,
    this.onDiagnostic,
    this.onEventError,
  });

  final TerminalRestorationPersistence persistence;
  final TerminalRestoredPaneConfigurationFactory configurationForPane;
  final TerminalRestorationHierarchyFactory hierarchyFactory;
  final TerminalWindowPlacement defaultPlacement;
  final TerminalRestorationWorkingDirectoryProvider workingDirectoryForPane;
  final String? defaultWorkingDirectory;
  final TerminalRestorationStateFactory stateFactory;
  final TerminalRestorationScreensProvider availableScreens;
  final int? fallbackDisplayId;
  final TerminalRestorationDiagnosticObserver? onDiagnostic;
  final void Function(Object error, StackTrace stackTrace)? onEventError;

  TerminalRestorationGeneration? _current;
  TerminalRestorationSnapshot? _lastSnapshot;
  Future<TerminalPaneOwnerShutdownResult?>? _suspendFuture;
  Future<TerminalRestorationReopenDisposition>? _reopenFuture;
  bool _started = false;
  bool _disposed = false;
  int _lastPaneId = 0;
  int _lastWindowId = 0;
  int _lastTabId = 0;
  int _lastSplitNodeId = 0;

  TerminalRestorationGeneration? get current => _current;
  bool get isDisposed => _disposed;

  /// Reprojects mutations and subscribes each newly created native tab once.
  void reconcile() {
    _ensureStarted();
    final TerminalRestorationGeneration? generation = _current;
    if (generation == null) {
      throw StateError('restoration lifecycle has no active generation');
    }
    generation.hierarchy.reconcile();
    _subscribeWindows(generation.hierarchy, generation._subscriptions);
    _rememberIdentities(generation.state);
  }

  Future<TerminalRestorationStartDisposition> start() async {
    _ensureAlive();
    if (_started) throw StateError('restoration lifecycle already started');
    _started = true;
    final TerminalRestorationLoadResult loaded = await persistence.load();
    _emitLoad(loaded.disposition);
    final TerminalRestorationSnapshot? snapshot = loaded.snapshot;
    if (snapshot != null) {
      _lastSnapshot = snapshot;
      try {
        _current = await _activate(snapshot);
        return TerminalRestorationStartDisposition.restored;
      } on Object {
        _emit(TerminalRestorationDiagnosticKind.restoreFailed);
      }
    }
    _current = await _activate(null);
    _emitCurrent(TerminalRestorationDiagnosticKind.defaultCreated);
    return TerminalRestorationStartDisposition.defaultCreated;
  }

  Future<TerminalRestorationSaveResult> persistCurrent() async {
    _ensureStarted();
    final TerminalRestorationGeneration? generation = _current;
    if (generation == null) {
      return const TerminalRestorationSaveResult(
        TerminalRestorationSaveDisposition.captureRejected,
      );
    }
    late final TerminalRestorationSnapshot snapshot;
    try {
      snapshot = TerminalApplicationRestorationCapture.capture(
        generation.state,
        placementForWindow: generation.hierarchy.placementForWindow,
        workingDirectoryForPane: workingDirectoryForPane,
      );
    } on Object {
      _emitCurrent(TerminalRestorationDiagnosticKind.captureRejected);
      return const TerminalRestorationSaveResult(
        TerminalRestorationSaveDisposition.captureRejected,
      );
    }
    _lastSnapshot = snapshot;
    final TerminalRestorationSaveResult result = await persistence.save(
      snapshot,
    );
    _emitCurrent(
      result.disposition == TerminalRestorationSaveDisposition.saved
          ? TerminalRestorationDiagnosticKind.saved
          : TerminalRestorationDiagnosticKind.saveUnavailable,
    );
    return result;
  }

  Future<TerminalPaneOwnerShutdownResult?> suspendForReopen() {
    _ensureStarted();
    final Future<TerminalRestorationReopenDisposition>? pendingReopen =
        _reopenFuture;
    return _suspendFuture ??=
        (pendingReopen == null
                ? _suspendForReopen()
                : pendingReopen.then((_) => _suspendForReopen()))
            .whenComplete(() {
              _suspendFuture = null;
            });
  }

  Future<TerminalRestorationReopenDisposition> reopen({
    required bool hasVisibleWindows,
  }) {
    _ensureStarted();
    if (hasVisibleWindows) {
      return Future<TerminalRestorationReopenDisposition>.value(
        TerminalRestorationReopenDisposition.ignoredVisible,
      );
    }
    return _reopenFuture ??= _reopen().whenComplete(() {
      _reopenFuture = null;
    });
  }

  /// Routes AppKit's Dock reopen signal through the coalesced generation path.
  Future<TerminalRestorationReopenDisposition> handleReopenRequest(
    ApplicationReopenRequestedEvent event,
  ) => reopen(hasVisibleWindows: event.hasVisibleWindows);

  Future<TerminalPaneOwnerShutdownResult?> shutdown({
    bool persist = true,
  }) async {
    if (_disposed) return null;
    _ensureStarted();
    _disposed = true;
    await _reopenFuture;
    await _suspendFuture;
    final TerminalRestorationGeneration? generation = _current;
    if (generation == null) {
      _emit(TerminalRestorationDiagnosticKind.disposed);
      return null;
    }
    if (persist) await _persistGeneration(generation);
    _current = null;
    final TerminalPaneOwnerShutdownResult result = await _deactivate(
      generation,
    );
    _emit(TerminalRestorationDiagnosticKind.disposed);
    return result;
  }

  Future<TerminalPaneOwnerShutdownResult?> _suspendForReopen() async {
    await _reopenFuture;
    final TerminalRestorationGeneration? generation = _current;
    if (generation == null) return null;
    await _persistGeneration(generation);
    _current = null;
    final TerminalPaneOwnerShutdownResult result = await _deactivate(
      generation,
    );
    _emit(TerminalRestorationDiagnosticKind.suspended);
    return result;
  }

  Future<TerminalRestorationReopenDisposition> _reopen() async {
    await _suspendFuture;
    final TerminalRestorationGeneration? live = _current;
    if (live != null) {
      live.hierarchy.present();
      _emitCurrent(TerminalRestorationDiagnosticKind.presentedExisting);
      return TerminalRestorationReopenDisposition.presentedExisting;
    }
    final TerminalRestorationSnapshot? snapshot = _lastSnapshot;
    if (snapshot != null) {
      try {
        _current = await _activate(snapshot);
        _emitCurrent(TerminalRestorationDiagnosticKind.reopened);
        return TerminalRestorationReopenDisposition.restored;
      } on Object {
        _emit(TerminalRestorationDiagnosticKind.restoreFailed);
      }
    }
    _current = await _activate(null);
    _emitCurrent(TerminalRestorationDiagnosticKind.defaultCreated);
    return TerminalRestorationReopenDisposition.defaultCreated;
  }

  Future<TerminalRestorationGeneration> _activate(
    TerminalRestorationSnapshot? snapshot,
  ) async {
    TerminalApplicationState? state;
    TerminalNativeHierarchyAdapter? hierarchy;
    final Map<TerminalTabId, StreamSubscription<WindowEvent>> subscriptions =
        <TerminalTabId, StreamSubscription<WindowEvent>>{};
    try {
      late final Map<TerminalWindowId, TerminalWindowPlacement> placements;
      late final Map<PaneId, String?> workingDirectories;
      if (snapshot == null) {
        state = _newState();
        final TerminalRestorablePane pane = TerminalRestorablePane(
          workingDirectory: defaultWorkingDirectory,
        );
        final TerminalWindowState window = await state.createWindow(
          configurationForPane(pane),
        );
        placements = <TerminalWindowId, TerminalWindowPlacement>{
          window.id: defaultPlacement,
        };
        workingDirectories = <PaneId, String?>{
          window.selectedTab.focusedPaneId: defaultWorkingDirectory,
        };
      } else {
        state = _newState();
        final TerminalRestorationResult restored =
            await TerminalApplicationRestorer.restore(
              snapshot,
              into: state,
              configurationForPane: configurationForPane,
            );
        state = restored.applicationState;
        placements = Map<TerminalWindowId, TerminalWindowPlacement>.of(
          restored.placements,
        );
        workingDirectories = Map<PaneId, String?>.of(
          restored.launchWorkingDirectories,
        );
      }
      _rememberIdentities(state);
      final List<TerminalScreenPlacement> screens = availableScreens().toList(
        growable: false,
      );
      for (final TerminalWindowId windowId in placements.keys.toList()) {
        placements[windowId] =
            TerminalWindowPlacementPolicy.resolveForAvailableScreens(
              placements[windowId]!,
              screens,
              fallbackDisplayId: fallbackDisplayId,
            );
      }
      hierarchy = hierarchyFactory(state: state, placements: placements);
      hierarchy.reconcile();
      _subscribeWindows(hierarchy, subscriptions);
      for (final TerminalWindowState window in state.windows) {
        for (final TerminalTabState tab in window.tabs) {
          for (final PaneId paneId in tab.paneIds) {
            await state.paneForId(paneId)!.start();
          }
        }
      }
      // Reconcile already restored selection/focus on the new native tree.
      hierarchy.present(restoreSelectionAndFocus: false);
      return TerminalRestorationGeneration._(
        state: state,
        hierarchy: hierarchy,
        launchWorkingDirectories: workingDirectories,
        subscriptions: subscriptions,
      );
    } on Object catch (error, stackTrace) {
      for (final StreamSubscription<WindowEvent> subscription
          in subscriptions.values.toList(growable: false).reversed) {
        await subscription.cancel();
      }
      if (hierarchy != null && !hierarchy.isDisposed) hierarchy.dispose();
      if (state != null) _rememberIdentities(state);
      if (state != null && !state.isDisposed) await state.shutdown();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<TerminalRestorationSaveResult> _persistGeneration(
    TerminalRestorationGeneration generation,
  ) async {
    late final TerminalRestorationSnapshot snapshot;
    try {
      snapshot = TerminalApplicationRestorationCapture.capture(
        generation.state,
        placementForWindow: generation.hierarchy.placementForWindow,
        workingDirectoryForPane: workingDirectoryForPane,
      );
    } on Object {
      _emitCurrent(TerminalRestorationDiagnosticKind.captureRejected);
      return const TerminalRestorationSaveResult(
        TerminalRestorationSaveDisposition.captureRejected,
      );
    }
    _lastSnapshot = snapshot;
    final TerminalRestorationSaveResult result = await persistence.save(
      snapshot,
    );
    _emitCurrent(
      result.disposition == TerminalRestorationSaveDisposition.saved
          ? TerminalRestorationDiagnosticKind.saved
          : TerminalRestorationDiagnosticKind.saveUnavailable,
    );
    return result;
  }

  Future<TerminalPaneOwnerShutdownResult> _deactivate(
    TerminalRestorationGeneration generation,
  ) async {
    if (generation._disposed) {
      return generation.state.shutdownResult ??
          TerminalPaneOwnerShutdownResult(
            const <TerminalPaneSessionShutdownResult>[],
          );
    }
    generation._disposed = true;
    for (final StreamSubscription<WindowEvent> subscription
        in generation._subscriptions.values.toList(growable: false).reversed) {
      await subscription.cancel();
    }
    generation.hierarchy.dispose();
    return generation.state.shutdown();
  }

  void _emitLoad(TerminalRestorationLoadDisposition disposition) {
    _emit(switch (disposition) {
      TerminalRestorationLoadDisposition.restored =>
        TerminalRestorationDiagnosticKind.loaded,
      TerminalRestorationLoadDisposition.missing =>
        TerminalRestorationDiagnosticKind.missing,
      TerminalRestorationLoadDisposition.rejected =>
        TerminalRestorationDiagnosticKind.rejected,
      TerminalRestorationLoadDisposition.unavailable =>
        TerminalRestorationDiagnosticKind.unavailable,
    });
  }

  void _subscribeWindows(
    TerminalNativeHierarchyAdapter hierarchy,
    Map<TerminalTabId, StreamSubscription<WindowEvent>> subscriptions,
  ) {
    for (final MapEntry<TerminalTabId, Window> entry
        in hierarchy.windows.entries) {
      subscriptions.putIfAbsent(
        entry.key,
        () => entry.value.events.listen(
          (WindowEvent event) {
            hierarchy.handleWindowEvent(entry.key, event);
          },
          onError: (Object error, StackTrace stackTrace) {
            onEventError?.call(error, stackTrace);
          },
        ),
      );
    }
  }

  void _emitCurrent(TerminalRestorationDiagnosticKind kind) {
    final TerminalApplicationState? state = _current?.state;
    _emit(
      kind,
      windows: state?.windowCount ?? 0,
      tabs: state?.tabCount ?? 0,
      panes: state?.paneCount ?? 0,
    );
  }

  void _emit(
    TerminalRestorationDiagnosticKind kind, {
    int windows = 0,
    int tabs = 0,
    int panes = 0,
  }) {
    onDiagnostic?.call(
      TerminalRestorationDiagnostic(
        kind,
        windows: windows,
        tabs: tabs,
        panes: panes,
      ),
    );
  }

  void _ensureStarted() {
    _ensureAlive();
    if (!_started) throw StateError('restoration lifecycle is not started');
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('restoration lifecycle is disposed');
  }

  TerminalApplicationState _newState() => stateFactory(
    initialPaneId: _lastPaneId,
    initialWindowId: _lastWindowId,
    initialTabId: _lastTabId,
    initialSplitNodeId: _lastSplitNodeId,
  );

  void _rememberIdentities(TerminalApplicationState state) {
    for (final TerminalWindowState window in state.windows) {
      if (window.id.value > _lastWindowId) _lastWindowId = window.id.value;
      for (final TerminalTabState tab in window.tabs) {
        if (tab.id.value > _lastTabId) _lastTabId = tab.id.value;
        for (final TerminalSplitNodeId nodeId in tab.splitTree.nodeIds) {
          if (nodeId.value > _lastSplitNodeId) {
            _lastSplitNodeId = nodeId.value;
          }
        }
      }
    }
    for (final PaneId paneId in state.paneIds) {
      if (paneId.value > _lastPaneId) _lastPaneId = paneId.value;
    }
  }

  static TerminalApplicationState _defaultStateFactory({
    required int initialPaneId,
    required int initialWindowId,
    required int initialTabId,
    required int initialSplitNodeId,
  }) => TerminalApplicationState(
    paneOwner: TerminalPaneOwner(initialPaneId: initialPaneId),
    initialWindowId: initialWindowId,
    initialTabId: initialTabId,
    initialSplitNodeId: initialSplitNodeId,
  );

  static Iterable<TerminalScreenPlacement> _noScreens() =>
      const <TerminalScreenPlacement>[];
}
