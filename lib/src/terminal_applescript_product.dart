import 'dart:async';
import 'dart:typed_data';

import 'package:dart_terminal_applescript_macos/dart_terminal_applescript_macos.dart'
    as native;
import 'package:dart_terminal_applescript_macos/testing.dart' as native_testing;

import 'terminal_applescript.dart';
import 'terminal_application_state.dart';
import 'terminal_native_content.dart';
import 'terminal_pane.dart';
import 'terminal_pane_close_coordinator.dart';
import 'terminal_product_hierarchy_actions.dart';

typedef TerminalAppleScriptPaneStarter = Future<void> Function(PaneId paneId);
typedef TerminalAppleScriptTabTitleResolver = String Function(
  TerminalTabState tab,
);
typedef TerminalAppleScriptTerminalTitleResolver = String Function(
  PaneId paneId,
);
typedef TerminalAppleScriptWorkingDirectoryResolver = String? Function(
  PaneId paneId,
);
typedef TerminalAppleScriptErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Narrow native boundary used by the product session and deterministic tests.
abstract interface class TerminalAppleScriptNativePort {
  void publishSnapshot(Uint8List bytes);
  Uint8List? takeCommand();
  void completeCommand(
    int operationId,
    TerminalAppleScriptCommandDisposition disposition, {
    String? objectId,
  });
  void dispose();
}

/// Production adapter over the terminal-specific macOS capability package.
final class TerminalAppleScriptMacosNativePort
    implements TerminalAppleScriptNativePort {
  TerminalAppleScriptMacosNativePort._(this._session);

  static void initialize() => native.TerminalAppleScriptMacos.initialize();

  factory TerminalAppleScriptMacosNativePort.open({
    int maximumPendingCommands =
        TerminalAppleScriptLimits.maximumPendingCommands,
    Duration commandTimeout = const Duration(seconds: 30),
  }) => TerminalAppleScriptMacosNativePort._(
    native.TerminalAppleScriptMacos.open(
      maximumPendingCommands: maximumPendingCommands,
      commandTimeout: commandTimeout,
    ),
  );

  final native.TerminalAppleScriptMacosSession _session;

  TerminalAppleScriptNativeSummary get summary {
    final native.TerminalAppleScriptMacosSummary value = _session.summary;
    return TerminalAppleScriptNativeSummary(
      generation: value.generation,
      windowCount: value.windowCount,
      tabCount: value.tabCount,
      terminalCount: value.terminalCount,
      queuedCommandCount: value.queuedCommandCount,
      pendingCommandCount: value.pendingCommandCount,
      resumedCommandCount: value.resumedCommandCount,
      rejectedCommandCount: value.rejectedCommandCount,
      started: value.started,
      enabled: value.enabled,
    );
  }

  int enqueueSelfAutomationCommand(Uint8List bytes) {
    try {
      native_testing.TerminalAppleScriptMacosSelfAutomation.enqueueCommand(
        bytes,
      );
      return 0;
    } on native.TerminalAppleScriptMacosException catch (error) {
      return error.status;
    }
  }

  @override
  void publishSnapshot(Uint8List bytes) => _session.publishSnapshot(bytes);

  @override
  Uint8List? takeCommand() => _session.takeCommand();

  @override
  void completeCommand(
    int operationId,
    TerminalAppleScriptCommandDisposition disposition, {
    String? objectId,
  }) => _session.completeCommand(operationId, switch (disposition) {
    TerminalAppleScriptCommandDisposition.completed =>
      native.TerminalAppleScriptMacosCommandDisposition.completed,
    TerminalAppleScriptCommandDisposition.confirmationRequired =>
      native.TerminalAppleScriptMacosCommandDisposition.confirmationRequired,
    TerminalAppleScriptCommandDisposition.disabled =>
      native.TerminalAppleScriptMacosCommandDisposition.disabled,
    TerminalAppleScriptCommandDisposition.notFound =>
      native.TerminalAppleScriptMacosCommandDisposition.notFound,
    TerminalAppleScriptCommandDisposition.busy =>
      native.TerminalAppleScriptMacosCommandDisposition.busy,
    TerminalAppleScriptCommandDisposition.rejected =>
      native.TerminalAppleScriptMacosCommandDisposition.rejected,
    TerminalAppleScriptCommandDisposition.failed =>
      native.TerminalAppleScriptMacosCommandDisposition.failed,
    TerminalAppleScriptCommandDisposition.timedOut =>
      native.TerminalAppleScriptMacosCommandDisposition.timedOut,
    TerminalAppleScriptCommandDisposition.disposed =>
      native.TerminalAppleScriptMacosCommandDisposition.disposed,
  }, objectId: objectId);

  @override
  void dispose() => _session.dispose();
}

final class TerminalAppleScriptNativeSummary {
  const TerminalAppleScriptNativeSummary({
    required this.generation,
    required this.windowCount,
    required this.tabCount,
    required this.terminalCount,
    required this.queuedCommandCount,
    required this.pendingCommandCount,
    required this.resumedCommandCount,
    required this.rejectedCommandCount,
    required this.started,
    required this.enabled,
  });

  final int generation;
  final int windowCount;
  final int tabCount;
  final int terminalCount;
  final int queuedCommandCount;
  final int pendingCommandCount;
  final int resumedCommandCount;
  final int rejectedCommandCount;
  final bool started;
  final bool enabled;
}

/// Applies dictionary commands to the same Dart-owned hierarchy and safety
/// controllers used by menus, shortcuts, Services, drag/drop, and close UI.
final class TerminalAppleScriptProductCommandExecutor
    implements TerminalAppleScriptCommandExecutor {
  TerminalAppleScriptProductCommandExecutor({
    required this.state,
    required TerminalProductPaneConfigurationFactory configurationFactory,
    required TerminalAppleScriptPaneStarter startPane,
    required TerminalProductHierarchyReconciler reconcile,
    required TerminalExternalPasteController<PaneId> pasteController,
    required TerminalPaneCloseCoordinator paneCloseCoordinator,
    TerminalProductHierarchyMutationAdmission? canMutate,
  }) : _configurationFactory = configurationFactory,
       _startPane = startPane,
       _reconcile = reconcile,
       _pasteController = pasteController,
       _paneCloseCoordinator = paneCloseCoordinator,
       _canMutate = canMutate;

  final TerminalApplicationState state;
  final TerminalProductPaneConfigurationFactory _configurationFactory;
  final TerminalAppleScriptPaneStarter _startPane;
  final TerminalProductHierarchyReconciler _reconcile;
  final TerminalExternalPasteController<PaneId> _pasteController;
  final TerminalPaneCloseCoordinator _paneCloseCoordinator;
  final TerminalProductHierarchyMutationAdmission? _canMutate;

  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) async {
    if (state.isDisposed) return _result(request, _disposed);
    if (!(_canMutate?.call() ?? true)) return _result(request, _busy);
    return switch (request.kind) {
      TerminalAppleScriptCommandKind.newWindow => _newWindow(request),
      TerminalAppleScriptCommandKind.newTab => _newTab(request),
      TerminalAppleScriptCommandKind.split => _split(request),
      TerminalAppleScriptCommandKind.inputText => _inputText(request),
      TerminalAppleScriptCommandKind.focus => _focus(request),
      TerminalAppleScriptCommandKind.closeTerminal => _closeTerminal(request),
      TerminalAppleScriptCommandKind.closeTab => _closeTab(request),
      TerminalAppleScriptCommandKind.closeWindow => _closeWindow(request),
    };
  }

  Future<TerminalAppleScriptCommandResult> _newWindow(
    TerminalAppleScriptCommandRequest request,
  ) async {
    if (state.windowCount >= TerminalApplicationStateLimits.maximumWindows ||
        state.paneCount >= TerminalApplicationStateLimits.maximumTotalPanes) {
      return _result(request, _rejected);
    }
    final TerminalWindowState? active = state.activeWindow;
    final PaneId? source = active?.role == TerminalWindowRole.standard
        ? active!.selectedTab.focusedPaneId
        : null;
    final TerminalWindowState window = await state.createWindow(
      _configurationFactory(source),
    );
    await _startCreatedPane(window.selectedTab.focusedPaneId);
    return _result(request, _completed, object: _windowObject(window.id));
  }

  Future<TerminalAppleScriptCommandResult> _newTab(
    TerminalAppleScriptCommandRequest request,
  ) async {
    final TerminalWindowState? window = _window(request.target!);
    if (window == null) return _result(request, _notFound);
    if (window.tabs.length >=
            TerminalApplicationStateLimits.maximumTabsPerWindow ||
        state.paneCount >= TerminalApplicationStateLimits.maximumTotalPanes) {
      return _result(request, _rejected);
    }
    final TerminalTabState tab = await state.createTab(
      window.id,
      _configurationFactory(window.selectedTab.focusedPaneId),
    );
    await _startCreatedPane(tab.focusedPaneId);
    return _result(request, _completed, object: _tabObject(tab.id));
  }

  Future<TerminalAppleScriptCommandResult> _split(
    TerminalAppleScriptCommandRequest request,
  ) async {
    final PaneId? target = _paneId(request.target!);
    if (target == null) return _result(request, _notFound);
    final TerminalPaneLocation location = state.locationForPane(target)!;
    final TerminalTabState tab = state.tabForId(location.tabId)!;
    if (tab.paneIds.length >=
            TerminalApplicationStateLimits.maximumPanesPerTab ||
        state.paneCount >= TerminalApplicationStateLimits.maximumTotalPanes) {
      return _result(request, _rejected);
    }
    final TerminalAppleScriptSplitDirection direction = request.direction!;
    final TerminalPane pane = await state.splitPane(
      target,
      _configurationFactory(target),
      axis:
          direction == TerminalAppleScriptSplitDirection.left ||
              direction == TerminalAppleScriptSplitDirection.right
          ? TerminalSplitAxis.horizontal
          : TerminalSplitAxis.vertical,
      placement:
          direction == TerminalAppleScriptSplitDirection.left ||
              direction == TerminalAppleScriptSplitDirection.up
          ? TerminalSplitPlacement.before
          : TerminalSplitPlacement.after,
    );
    await _startCreatedPane(pane.id);
    return _result(request, _completed, object: _terminalObject(pane.id));
  }

  Future<TerminalAppleScriptCommandResult> _focus(
    TerminalAppleScriptCommandRequest request,
  ) async {
    final PaneId? paneId = _paneId(request.target!);
    if (paneId == null) return _result(request, _notFound);
    final TerminalPaneLocation location = state.locationForPane(paneId)!;
    state.focusPane(location.tabId, paneId);
    _reconcile();
    return _result(request, _completed);
  }

  Future<TerminalAppleScriptCommandResult> _inputText(
    TerminalAppleScriptCommandRequest request,
  ) async {
    final PaneId? paneId = _paneId(request.target!);
    if (paneId == null) return _result(request, _notFound);
    final TerminalPaneLocation location = state.locationForPane(paneId)!;
    state.focusPane(location.tabId, paneId);
    _reconcile();
    final TerminalExternalContentResult admission =
        TerminalExternalContentAdmission.text(
          request.text!,
          source: TerminalExternalTextSource.appleScript,
        );
    if (!admission.isAdmitted) return _result(request, _rejected);
    final TerminalExternalPasteResult paste = await _pasteController.submit(
      paneId,
      admission.content!,
    );
    return _result(request, switch (paste.disposition) {
      TerminalExternalPasteDisposition.completed => _completed,
      TerminalExternalPasteDisposition.confirmationRequired =>
        _confirmationRequired,
      TerminalExternalPasteDisposition.staleTarget => _notFound,
      TerminalExternalPasteDisposition.busy => _busy,
      TerminalExternalPasteDisposition.tooLarge => _rejected,
      TerminalExternalPasteDisposition.transferIncomplete => _failed,
      TerminalExternalPasteDisposition.disposed => _disposed,
    });
  }

  Future<TerminalAppleScriptCommandResult> _closeTerminal(
    TerminalAppleScriptCommandRequest request,
  ) async {
    final PaneId? paneId = _paneId(request.target!);
    if (paneId == null) return _result(request, _notFound);
    return _result(
      request,
      _closeDisposition(
        await _paneCloseCoordinator.requestClose(paneId: paneId),
      ),
    );
  }

  Future<TerminalAppleScriptCommandResult> _closeTab(
    TerminalAppleScriptCommandRequest request,
  ) => _closeAggregate(request, tabId: TerminalTabId(request.target!.value));

  Future<TerminalAppleScriptCommandResult> _closeWindow(
    TerminalAppleScriptCommandRequest request,
  ) => _closeAggregate(
    request,
    windowId: TerminalWindowId(request.target!.value),
  );

  Future<TerminalAppleScriptCommandResult> _closeAggregate(
    TerminalAppleScriptCommandRequest request, {
    TerminalTabId? tabId,
    TerminalWindowId? windowId,
  }) async {
    while (true) {
      final TerminalTabState? tab = tabId == null ? null : _tabById(tabId);
      final TerminalWindowState? window = windowId == null
          ? null
          : _windowById(windowId);
      if (tabId != null && tab == null || windowId != null && window == null) {
        return _result(request, _notFound);
      }
      final List<PaneId> paneIds =
          tab?.paneIds ??
          window!.tabs
              .expand((TerminalTabState item) => item.paneIds)
              .toList(growable: false);
      if (paneIds.isEmpty) return _result(request, _completed);
      final TerminalAppleScriptCommandDisposition disposition =
          _closeDisposition(
            await _paneCloseCoordinator.requestClose(paneId: paneIds.last),
          );
      if (disposition != _completed) return _result(request, disposition);
      if (tabId != null && state.tabForId(tabId) == null ||
          windowId != null && state.windowForId(windowId) == null) {
        return _result(request, _completed);
      }
    }
  }

  Future<void> _startCreatedPane(PaneId paneId) async {
    try {
      await _startPane(paneId);
      _reconcile();
    } on Object {
      if (state.paneForId(paneId) != null) await state.removePane(paneId);
      _reconcile();
      rethrow;
    }
  }

  TerminalWindowState? _window(TerminalAppleScriptObjectId object) =>
      _windowById(TerminalWindowId(object.value));

  TerminalWindowState? _windowById(TerminalWindowId id) {
    final TerminalWindowState? window = state.windowForId(id);
    return window?.role == TerminalWindowRole.standard ? window : null;
  }

  TerminalTabState? _tabById(TerminalTabId id) {
    final TerminalTabState? tab = state.tabForId(id);
    if (tab == null) return null;
    final TerminalPaneLocation? location = state.locationForPane(
      tab.focusedPaneId,
    );
    return location != null && _windowById(location.windowId) != null
        ? tab
        : null;
  }

  PaneId? _paneId(TerminalAppleScriptObjectId object) {
    final PaneId paneId = PaneId(object.value);
    final TerminalPaneLocation? location = state.locationForPane(paneId);
    return location != null && _windowById(location.windowId) != null
        ? paneId
        : null;
  }

  static TerminalAppleScriptCommandDisposition _closeDisposition(
    TerminalPaneCloseResult result,
  ) => switch (result.disposition) {
    TerminalPaneCloseDisposition.confirmationRequired => _confirmationRequired,
    TerminalPaneCloseDisposition.removed => _completed,
    TerminalPaneCloseDisposition.removedWithCleanupFailure => _failed,
    TerminalPaneCloseDisposition.noTarget ||
    TerminalPaneCloseDisposition.stale => _notFound,
    TerminalPaneCloseDisposition.busy => _busy,
  };

  static TerminalAppleScriptCommandResult _result(
    TerminalAppleScriptCommandRequest request,
    TerminalAppleScriptCommandDisposition disposition, {
    TerminalAppleScriptObjectId? object,
  }) => TerminalAppleScriptCommandResult(
    operationId: request.operationId,
    disposition: disposition,
    object: object,
  );

  static TerminalAppleScriptObjectId _windowObject(TerminalWindowId id) =>
      TerminalAppleScriptObjectId(
        TerminalAppleScriptObjectKind.window,
        id.value,
      );
  static TerminalAppleScriptObjectId _tabObject(TerminalTabId id) =>
      TerminalAppleScriptObjectId(TerminalAppleScriptObjectKind.tab, id.value);
  static TerminalAppleScriptObjectId _terminalObject(PaneId id) =>
      TerminalAppleScriptObjectId(
        TerminalAppleScriptObjectKind.terminal,
        id.value,
      );

  static const TerminalAppleScriptCommandDisposition _completed =
      TerminalAppleScriptCommandDisposition.completed;
  static const TerminalAppleScriptCommandDisposition _confirmationRequired =
      TerminalAppleScriptCommandDisposition.confirmationRequired;
  static const TerminalAppleScriptCommandDisposition _notFound =
      TerminalAppleScriptCommandDisposition.notFound;
  static const TerminalAppleScriptCommandDisposition _busy =
      TerminalAppleScriptCommandDisposition.busy;
  static const TerminalAppleScriptCommandDisposition _rejected =
      TerminalAppleScriptCommandDisposition.rejected;
  static const TerminalAppleScriptCommandDisposition _failed =
      TerminalAppleScriptCommandDisposition.failed;
  static const TerminalAppleScriptCommandDisposition _disposed =
      TerminalAppleScriptCommandDisposition.disposed;
}

/// Keeps the immutable scripting cache and native command queue synchronized
/// from the UI isolate without exposing live Dart objects to Cocoa Scripting.
final class TerminalAppleScriptProductSession {
  TerminalAppleScriptProductSession({
    required this.state,
    required bool enabled,
    required TerminalAppleScriptNativePort nativePort,
    required TerminalAppleScriptCommandExecutor executor,
    required TerminalAppleScriptTabTitleResolver titleForTab,
    required TerminalAppleScriptTerminalTitleResolver titleForTerminal,
    required TerminalAppleScriptWorkingDirectoryResolver workingDirectoryFor,
    TerminalAppleScriptErrorHandler? onError,
    this.pollInterval = const Duration(milliseconds: 16),
    this.maximumCommandsPerPoll = 4,
    Duration commandTimeout = const Duration(seconds: 30),
    bool startPolling = true,
  }) : _enabled = enabled,
       _nativePort = nativePort,
       _titleForTab = titleForTab,
       _titleForTerminal = titleForTerminal,
       _workingDirectoryFor = workingDirectoryFor,
       _onError = onError,
       _controller = TerminalAppleScriptCommandController(
         enabled: enabled,
         executor: executor,
         commandTimeout: commandTimeout,
       ) {
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    RangeError.checkValueInInterval(
      maximumCommandsPerPoll,
      1,
      TerminalAppleScriptLimits.maximumPendingCommands,
      'maximumCommandsPerPoll',
    );
    reconcile();
    if (startPolling) {
      _pollTimer = Timer.periodic(pollInterval, (_) => _pollSafely());
    }
  }

  final TerminalApplicationState state;
  final TerminalAppleScriptNativePort _nativePort;
  final TerminalAppleScriptCommandController _controller;
  final TerminalAppleScriptTabTitleResolver _titleForTab;
  final TerminalAppleScriptTerminalTitleResolver _titleForTerminal;
  final TerminalAppleScriptWorkingDirectoryResolver _workingDirectoryFor;
  final TerminalAppleScriptErrorHandler? _onError;
  final Duration pollInterval;
  final int maximumCommandsPerPoll;
  Timer? _pollTimer;
  int _generation = 0;
  int _commandEpoch = 0;
  bool _enabled;
  bool _disposed = false;
  bool _reconcileScheduled = false;

  bool get isEnabled => _enabled;
  bool get isDisposed => _disposed;

  void reconcile() {
    if (_disposed) return;
    if (_generation >= TerminalApplicationState.maximumIdentityValue) {
      throw StateError('AppleScript snapshot generation is exhausted');
    }
    _nativePort.publishSnapshot(
      TerminalAppleScriptSnapshotCodec.encode(
        _snapshot(generation: ++_generation, enabled: _enabled),
      ),
    );
  }

  /// Coalesces high-frequency terminal metadata notifications to one cache
  /// replacement per event-loop turn.
  void scheduleReconcile() {
    if (_disposed || _reconcileScheduled) return;
    _reconcileScheduled = true;
    scheduleMicrotask(() {
      _reconcileScheduled = false;
      if (_disposed) return;
      try {
        reconcile();
      } on Object catch (error, stackTrace) {
        _reportAsynchronousError(error, stackTrace);
      }
    });
  }

  void applyEnabled(bool value) {
    if (_disposed || _enabled == value) return;
    _commandEpoch++;
    _enabled = value;
    if (value) _controller.setEnabled(true);
    reconcile();
    if (!value) _controller.setEnabled(false);
  }

  int pollOnce() {
    if (_disposed || !_enabled) return 0;
    var taken = 0;
    while (taken < maximumCommandsPerPoll) {
      final Uint8List? bytes = _nativePort.takeCommand();
      if (bytes == null) break;
      taken++;
      final TerminalAppleScriptCommandRequest request =
          TerminalAppleScriptCommandCodec.decode(bytes);
      final int commandEpoch = _commandEpoch;
      unawaited(
        _controller
            .submit(request)
            .then<void>(
              (TerminalAppleScriptCommandResult result) =>
                  _complete(result, commandEpoch),
              onError: _reportAsynchronousError,
            ),
      );
    }
    return taken;
  }

  void _pollSafely() {
    try {
      pollOnce();
    } on Object catch (error, stackTrace) {
      _reportAsynchronousError(error, stackTrace);
    }
  }

  void _complete(TerminalAppleScriptCommandResult result, int commandEpoch) {
    if (_disposed || !_enabled || commandEpoch != _commandEpoch) return;
    try {
      reconcile();
      _nativePort.completeCommand(
        result.operationId,
        result.disposition,
        objectId: result.isCompleted ? result.object?.externalValue : null,
      );
    } on Object catch (error, stackTrace) {
      _reportAsynchronousError(error, stackTrace);
    }
  }

  TerminalAppleScriptApplicationSnapshot _snapshot({
    required int generation,
    required bool enabled,
  }) {
    final List<TerminalWindowState> windows = enabled
        ? state.windows
              .where(
                (TerminalWindowState window) =>
                    window.role == TerminalWindowRole.standard,
              )
              .toList(growable: false)
        : const <TerminalWindowState>[];
    return TerminalAppleScriptApplicationSnapshot(
      generation: generation,
      enabled: enabled,
      windows: <TerminalAppleScriptWindowSnapshot>[
        for (var windowIndex = 0; windowIndex < windows.length; windowIndex++)
          _windowSnapshot(windows[windowIndex], windowIndex + 1),
      ],
    );
  }

  TerminalAppleScriptWindowSnapshot _windowSnapshot(
    TerminalWindowState window,
    int index,
  ) {
    final List<TerminalTabState> tabs = window.tabs;
    return TerminalAppleScriptWindowSnapshot(
      id: TerminalAppleScriptProductCommandExecutor._windowObject(window.id),
      title: _titleForTab(window.selectedTab),
      index: index,
      frontmost: state.activeWindowId == window.id,
      selectedTabId: TerminalAppleScriptProductCommandExecutor._tabObject(
        window.selectedTabId,
      ),
      tabs: <TerminalAppleScriptTabSnapshot>[
        for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++)
          _tabSnapshot(tabs[tabIndex], tabIndex + 1, window.selectedTabId),
      ],
    );
  }

  TerminalAppleScriptTabSnapshot _tabSnapshot(
    TerminalTabState tab,
    int index,
    TerminalTabId selectedTabId,
  ) => TerminalAppleScriptTabSnapshot(
    id: TerminalAppleScriptProductCommandExecutor._tabObject(tab.id),
    title: _titleForTab(tab),
    index: index,
    selected: tab.id == selectedTabId,
    focusedTerminalId:
        TerminalAppleScriptProductCommandExecutor._terminalObject(
          tab.focusedPaneId,
        ),
    terminals: <TerminalAppleScriptTerminalSnapshot>[
      for (final PaneId paneId in tab.paneIds)
        TerminalAppleScriptTerminalSnapshot(
          id: TerminalAppleScriptProductCommandExecutor._terminalObject(paneId),
          title: _titleForTerminal(paneId),
          workingDirectory: _workingDirectoryFor(paneId),
        ),
    ],
  );

  void dispose() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    _commandEpoch++;
    _enabled = false;
    try {
      reconcile();
    } on Object catch (error, stackTrace) {
      _reportAsynchronousError(error, stackTrace);
    }
    _controller.dispose();
    _disposed = true;
    _nativePort.dispose();
  }

  void _reportAsynchronousError(Object error, StackTrace stackTrace) {
    _onError?.call(error, stackTrace);
  }
}
