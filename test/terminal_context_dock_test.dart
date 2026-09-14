import 'dart:async';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalContextDockTests();

Future<void> runTerminalContextDockTests() async {
  await _testWindowPaneStateAndBounds();
  await _testActionFocusOwnershipAndAvailability();
  await _testNavigatorKeyRoutingNeverFallsThrough();
  await _testDirectoryTreeFollowsPaneAndCancelsHiddenWork();
}

Future<void> _testWindowPaneStateAndBounds() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId firstPane = window.selectedTab.focusedPaneId;
  final TerminalContextDockState dock = TerminalContextDockState();
  _expect(dock.synchronize(harness.state), 'initial hierarchy is retained');
  TerminalContextDockWindowSnapshot snapshot = dock.snapshotForWindow(
    window.id,
  )!;
  _expect(
    dock.windowCount == 1 &&
        snapshot.targetPaneId == firstPane &&
        !snapshot.isVisible &&
        snapshot.width == TerminalContextDockLimits.defaultWidth &&
        snapshot.inputOwner == TerminalContextDockInputOwner.terminal,
    'a new window starts hidden while terminal retains input',
  );

  final TerminalContextDockFocusRequest request = dock.requestSearchFocus(
    window.id,
    firstPane,
  );
  _expect(
    dock.snapshotForWindow(window.id)!.isVisible &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput &&
        dock.confirmNavigatorInput(request),
    'search visibility precedes generation-bound navigator ownership',
  );
  dock
    ..setQuery(window.id, 'alpha', requireNavigatorInput: true)
    ..setResultCount(window.id, 4)
    ..moveSelection(window.id, 2)
    ..setWidth(window.id, 412);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    snapshot.pane.query == 'alpha' &&
        snapshot.pane.resultCount == 4 &&
        snapshot.pane.selectedResultIndex == 2 &&
        snapshot.width == 412,
    'bounded query and result selection belong to the target pane',
  );

  final TerminalPane second = await harness.state.splitPane(
    firstPane,
    harness.configuration(),
    axis: TerminalSplitAxis.horizontal,
  );
  await second.start();
  _expect(dock.synchronize(harness.state), 'new focused pane is reconciled');
  _expect(
    dock.snapshotForWindow(window.id)!.targetPaneId == second.id &&
        dock.snapshotForWindow(window.id)!.pane.query.isEmpty,
    'the window follows its selected tab focused pane',
  );
  harness.state.focusPane(window.selectedTab.id, firstPane);
  dock.synchronize(harness.state);
  _expect(
    dock.snapshotForWindow(window.id)!.pane.query == 'alpha',
    'pane-local navigation state survives focus round trips',
  );

  _expectThrows<TerminalContextDockLimitException>(
    () => dock.setQuery(
      window.id,
      'x' * (TerminalContextDockLimits.maximumQueryUnits + 1),
    ),
    'oversize query is rejected atomically',
  );
  _expectThrows<ArgumentError>(
    () => dock.setWidth(window.id, TerminalContextDockLimits.maximumWidth + 1),
    'oversize Dock width is rejected',
  );
  _expectThrows<ArgumentError>(
    () => dock.setQuery(window.id, 'bad\nquery'),
    'control-bearing query is rejected',
  );
  _expectThrows<TerminalContextDockLimitException>(
    () => dock.setResultCount(
      window.id,
      TerminalContextDockLimits.maximumResults + 1,
    ),
    'oversize result count is rejected',
  );
  _expect(
    dock.snapshotForWindow(window.id)!.pane.query == 'alpha',
    'invalid mutations leave the retained pane state unchanged',
  );

  await harness.state.removePane(second.id);
  dock.synchronize(harness.state);
  _expect(
    dock.snapshotForWindow(window.id)!.targetPaneId == firstPane,
    'closed pane state is removed without losing the surviving target',
  );
  final TerminalWindowState secondWindow = await harness.createWindow();
  dock.synchronize(harness.state);
  _expect(
    dock.windowCount == 2 &&
        dock.snapshotForWindow(window.id)!.pane.query == 'alpha' &&
        dock.snapshotForWindow(secondWindow.id)!.pane.query.isEmpty,
    'each standard window owns isolated pane navigation state',
  );
  harness.state.activateWindow(window.id);
  await harness.state.removePane(secondWindow.selectedTab.focusedPaneId);
  dock.synchronize(harness.state);
  _expect(
    dock.windowCount == 1 && dock.snapshotForWindow(secondWindow.id) == null,
    'closing a window releases only its Context Dock state',
  );
  await harness.state.shutdown();
  dock.synchronize(harness.state);
  _expect(dock.windowCount == 0, 'shutdown removes all window-owned state');
  dock.dispose();
  dock.dispose();
  _expect(dock.isDisposed, 'state disposal is idempotent');
}

Future<void> _testDirectoryTreeFollowsPaneAndCancelsHiddenWork() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId firstPane = window.selectedTab.focusedPaneId;
  final TerminalContextDockState dock = TerminalContextDockState()
    ..synchronize(harness.state)
    ..toggleVisibility(window.id, firstPane);
  final _ContextDockDirectoryFileSystem files =
      _ContextDockDirectoryFileSystem();
  const TerminalWorkingDirectoryResolver workingDirectoryResolver =
      TerminalWorkingDirectoryResolver();
  String root = '/root';
  bool remote = false;
  final TerminalContextDockDirectoryController controller =
      TerminalContextDockDirectoryController(
        applicationState: harness.state,
        dockState: dock,
        snapshotService: TerminalDirectorySnapshotService(fileSystem: files),
        resolveWorkingDirectory: (PaneId paneId, int generation) {
          final TerminalPaneProcessSnapshot process = harness.state
              .paneForId(paneId)!
              .processSnapshot();
          return workingDirectoryResolver.resolve(
            sessionId: process.sessionId,
            generation: generation,
            processSnapshot: process,
            reportedWorkingDirectory: remote
                ? Uri.parse('file://host.example/remote')
                : null,
            processWorkingDirectory: null,
            launchWorkingDirectory: root,
          );
        },
      );

  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  TerminalContextDockDirectorySnapshot snapshot = controller.snapshotForWindow(
    window.id,
  )!;
  _expect(
    snapshot.status == TerminalContextDockDirectoryStatus.ready &&
        snapshot.workingDirectory == '/root' &&
        snapshot.rows.map((value) => value.entry.name).join(',') ==
            'folder,.hidden,readme.md' &&
        dock.snapshotForWindow(window.id)!.pane.resultCount == 3,
    'root tree is folder-first, includes dotfiles, and publishes selection bounds',
  );
  _expect(
    controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.expand,
    ),
    'selected folder accepts a lazy expansion intent',
  );
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.rows.map((value) => value.entry.name).join(',') ==
            'folder,nested.txt,.hidden,readme.md' &&
        snapshot.rows[1].depth == 1 &&
        snapshot.rows[1].entry.metadata.size == 7,
    'expanded folder loads one child level and retains metadata',
  );

  final TerminalPane secondPane = await harness.state.splitPane(
    firstPane,
    harness.configuration(),
    axis: TerminalSplitAxis.horizontal,
  );
  await secondPane.start();
  root = '/other';
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.paneId == secondPane.id &&
        snapshot.workingDirectory == '/other' &&
        snapshot.rows.single.entry.name == 'other.txt',
    'focused pane change cancels the old owner and projects the new pane cwd',
  );

  remote = true;
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.status == TerminalContextDockDirectoryStatus.remoteUnavailable &&
        snapshot.rows.isEmpty,
    'remote authority never falls back to the local launch directory',
  );

  remote = false;
  root = '/slow';
  controller.synchronize();
  await files.slowListStarted.future;
  _expect(
    controller.activeOperationCount == 1,
    'new cwd starts one owned snapshot operation',
  );
  dock.toggleVisibility(window.id, secondPane.id);
  controller.synchronize();
  _expect(
    controller.activeOperationCount == 0 &&
        controller.snapshotForWindow(window.id) == null,
    'hiding the Dock cancels and releases its filesystem operation',
  );
  files.releaseSlowList.complete();
  await Future<void>.delayed(Duration.zero);

  controller.dispose();
  dock.dispose();
  await harness.state.shutdown();
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('timed out waiting for Context Dock operation');
}

final class _ContextDockDirectoryFileSystem
    implements TerminalDirectoryFileSystem {
  final Completer<void> slowListStarted = Completer<void>();
  final Completer<void> releaseSlowList = Completer<void>();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    if (rootPath == '/slow') {
      slowListStarted.complete();
      await releaseSlowList.future;
      return;
    }
    if (rootPath == '/root') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'readme.md',
        path: '/root/readme.md',
        kind: TerminalDirectoryEntryKind.file,
      );
      yield const TerminalDirectoryFileSystemEntry(
        name: '.hidden',
        path: '/root/.hidden',
        kind: TerminalDirectoryEntryKind.file,
      );
      yield const TerminalDirectoryFileSystemEntry(
        name: 'folder',
        path: '/root/folder',
        kind: TerminalDirectoryEntryKind.directory,
      );
      return;
    }
    if (rootPath == '/root/folder') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'nested.txt',
        path: '/root/folder/nested.txt',
        kind: TerminalDirectoryEntryKind.file,
      );
      return;
    }
    if (rootPath == '/other') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'other.txt',
        path: '/other/other.txt',
        kind: TerminalDirectoryEntryKind.file,
      );
    }
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => TerminalDirectoryFileSystemMetadata(
    mode: entry.kind == TerminalDirectoryEntryKind.directory ? 0x1ed : 0x1a4,
    size: entry.name == 'nested.txt' ? 7 : 3,
    modifiedMicrosecondsSinceEpoch: 1,
  );
}

Future<void> _testActionFocusOwnershipAndAvailability() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final TerminalContextDockState dock = TerminalContextDockState();
  final List<TerminalContextDockFocusRequest> navigatorFocus =
      <TerminalContextDockFocusRequest>[];
  final List<TerminalContextDockFocusRequest> terminalFocus =
      <TerminalContextDockFocusRequest>[];
  var canFocusNavigator = true;
  var failNavigatorFocus = false;
  var failTerminalFocus = false;
  var changed = 0;
  final TerminalContextDockActionCoordinator coordinator =
      TerminalContextDockActionCoordinator(
        applicationState: harness.state,
        dockState: dock,
        focusNavigator: (TerminalContextDockFocusRequest request) {
          if (failNavigatorFocus) {
            throw StateError('injected navigator focus failure');
          }
          navigatorFocus.add(request);
        },
        focusTerminal: (TerminalContextDockFocusRequest request) {
          if (failTerminalFocus) {
            throw StateError('injected terminal focus failure');
          }
          terminalFocus.add(request);
        },
        canFocusNavigator: () => canFocusNavigator,
        onChanged: () => changed++,
      );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: coordinator.registrations(),
  );

  _expect(
    dispatcher.snapshot(TerminalActionId.searchFilesAndFolders).isEnabled &&
        dispatcher.snapshot(TerminalActionId.toggleContextDock).isEnabled &&
        !dispatcher.snapshot(TerminalActionId.focusTerminal).isEnabled,
    'only valid initial Context Dock actions are available',
  );
  await _expectExecuted(dispatcher, TerminalActionId.searchFilesAndFolders);
  TerminalContextDockWindowSnapshot snapshot = dock.snapshotForWindow(
    window.id,
  )!;
  _expect(
    snapshot.isVisible &&
        snapshot.navigatorOwnsInput &&
        navigatorFocus.length == 1 &&
        navigatorFocus.single.windowId == window.id &&
        navigatorFocus.single.paneId == paneId &&
        dispatcher.snapshot(TerminalActionId.focusTerminal).isEnabled,
    'search action makes the Dock visible and transfers input exactly once',
  );
  dock.setQuery(window.id, 'retained', requireNavigatorInput: true);
  final int firstSelectionGeneration = snapshot.pane.querySelectionGeneration;
  await _expectExecuted(dispatcher, TerminalActionId.searchFilesAndFolders);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    navigatorFocus.length == 2 &&
        snapshot.navigatorOwnsInput &&
        snapshot.pane.query == 'retained' &&
        snapshot.pane.querySelectionGeneration > firstSelectionGeneration,
    'repeated search reselects the retained query without toggling focus',
  );

  failTerminalFocus = true;
  _expect(
    (await dispatcher.dispatch(TerminalActionId.focusTerminal)).disposition ==
            TerminalActionDispatchDisposition.failed &&
        dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'terminal focus failure leaves navigator ownership unchanged',
  );
  failTerminalFocus = false;
  await _expectExecuted(dispatcher, TerminalActionId.focusTerminal);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    snapshot.isVisible &&
        !snapshot.navigatorOwnsInput &&
        snapshot.pane.query == 'retained' &&
        terminalFocus.length == 1,
    'focus-terminal preserves Dock visibility and query state',
  );
  await _expectExecuted(dispatcher, TerminalActionId.toggleContextDock);
  _expect(
    !dock.snapshotForWindow(window.id)!.isVisible,
    'toggle hides a terminal-owned Dock',
  );
  await _expectExecuted(dispatcher, TerminalActionId.toggleContextDock);
  _expect(
    dock.snapshotForWindow(window.id)!.isVisible &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'toggle shows the Dock without stealing terminal input',
  );

  canFocusNavigator = false;
  _expect(
    !dispatcher.snapshot(TerminalActionId.searchFilesAndFolders).isEnabled &&
        (await dispatcher.dispatch(TerminalActionId.searchFilesAndFolders))
                .disposition ==
            TerminalActionDispatchDisposition.unavailable,
    'navigator admission failure disables search without changing ownership',
  );
  canFocusNavigator = true;
  failNavigatorFocus = true;
  _expect(
    (await dispatcher.dispatch(TerminalActionId.searchFilesAndFolders))
                .disposition ==
            TerminalActionDispatchDisposition.failed &&
        dock.snapshotForWindow(window.id)!.isVisible &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'navigator focus failure may reveal the Dock but never claims input',
  );
  coordinator.dispose();
  _expect(
    !dispatcher.snapshot(TerminalActionId.toggleContextDock).isEnabled &&
        changed >= 5,
    'disposed coordinator fails every retained registration closed',
  );
  dock.dispose();
  await harness.state.shutdown();
}

Future<void> _testNavigatorKeyRoutingNeverFallsThrough() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final TerminalContextDockState dock = TerminalContextDockState();
  final List<TerminalContextDockFocusRequest> terminalFocus =
      <TerminalContextDockFocusRequest>[];
  final TerminalContextDockActionCoordinator coordinator =
      TerminalContextDockActionCoordinator(
        applicationState: harness.state,
        dockState: dock,
        focusNavigator: (_) {},
        focusTerminal: terminalFocus.add,
      );
  final Completer<void> busyGate = Completer<void>();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: <TerminalActionRegistration>[
      ...coordinator.registrations(),
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        handler: () => busyGate.future,
      ),
    ],
  );
  await _expectExecuted(dispatcher, TerminalActionId.searchFilesAndFolders);
  var changed = 0;
  final TerminalContextDockKeyController keys =
      TerminalContextDockKeyController(
        state: dock,
        dispatcher: dispatcher,
        onChanged: () => changed++,
      );
  var terminalWriteCount = 0;

  Future<TerminalContextDockKeyResult> route(AppKitKeyEvent event) async {
    final TerminalContextDockKeyResult result = await keys.handle(
      window.id,
      event,
    );
    if (!result.isConsumed) terminalWriteCount++;
    return result;
  }

  _expect(
    (await route(_key(keyCode: 0, characters: 'ab'))).disposition ==
            TerminalContextDockKeyDisposition.queryUpdated &&
        dock.snapshotForWindow(window.id)!.pane.query == 'ab',
    'printable input updates only the navigator query',
  );
  await route(_key(keyCode: 51));
  _expect(
    dock.snapshotForWindow(window.id)!.pane.query == 'a',
    'Backspace edits the query by one scalar',
  );
  _expect(
    (await route(
          _key(
            keyCode: 0,
            characters: 'a',
            modifiers: const ModifierKeys(ModifierKeys.commandBit),
          ),
        )).disposition ==
        TerminalContextDockKeyDisposition.querySelectionRequested,
    'Command-A requests whole-query selection',
  );

  dock.setResultCount(window.id, 30);
  await route(_key(keyCode: 125));
  final int selectedBeforeShiftArrow = dock
      .snapshotForWindow(window.id)!
      .pane
      .selectedResultIndex;
  final TerminalContextDockKeyResult shiftArrow = await route(
    _key(keyCode: 125, modifiers: const ModifierKeys(ModifierKeys.shiftBit)),
  );
  _expect(
    shiftArrow.disposition == TerminalContextDockKeyDisposition.consumed &&
        dock.snapshotForWindow(window.id)!.pane.selectedResultIndex ==
            selectedBeforeShiftArrow,
    'modified arrows are consumed without borrowing navigator movement',
  );
  await route(_key(keyCode: 121));
  await route(_key(keyCode: 126));
  await route(_key(keyCode: 116));
  _expect(
    dock.snapshotForWindow(window.id)!.pane.selectedResultIndex == 0,
    'arrow and page keys move a clamped result selection',
  );
  _expect(
    (await route(
              _key(
                keyCode: 123,
                modifiers: const ModifierKeys(ModifierKeys.commandBit),
              ),
            )).treeIntent ==
            TerminalContextDockTreeIntent.collapse &&
        (await route(
              _key(
                keyCode: 124,
                modifiers: const ModifierKeys(ModifierKeys.commandBit),
              ),
            )).treeIntent ==
            TerminalContextDockTreeIntent.expand,
    'Command-Left and Command-Right remain navigator tree intents',
  );
  await route(
    _key(
      keyCode: 7,
      characters: 'x',
      modifiers: const ModifierKeys(ModifierKeys.commandBit),
    ),
  );
  await route(_key(keyCode: 0, characters: 'a', kind: AppKitKeyEventKind.up));
  _expect(
    terminalWriteCount == 0,
    'unsupported and release events remain consumed while navigator owns input',
  );

  final Future<TerminalActionDispatchResult> busy = dispatcher.dispatch(
    TerminalActionId.copy,
  );
  await Future<void>.delayed(Duration.zero);
  final TerminalContextDockKeyResult busyEscape = await route(
    _key(keyCode: 53, characters: '\u001b'),
  );
  _expect(
    busyEscape.dispatchResult?.disposition ==
            TerminalActionDispatchDisposition.busy &&
        dock.snapshotForWindow(window.id)!.navigatorOwnsInput &&
        terminalFocus.isEmpty &&
        terminalWriteCount == 0,
    'busy focus action is consumed and leaves navigator ownership intact',
  );
  busyGate.complete();
  await busy;

  final TerminalContextDockKeyResult escape = await route(
    _key(keyCode: 53, characters: '\u001b'),
  );
  _expect(
    escape.dispatchResult?.disposition ==
            TerminalActionDispatchDisposition.executed &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput &&
        dock.snapshotForWindow(window.id)!.pane.query == 'a' &&
        terminalFocus.length == 1 &&
        terminalWriteCount == 0,
    'Escape dispatches shared terminal focus once without clearing query',
  );
  final TerminalContextDockKeyResult terminalOwned = await route(
    _key(keyCode: 125),
  );
  _expect(
    terminalOwned.disposition == TerminalContextDockKeyDisposition.notOwned &&
        terminalWriteCount == 1 &&
        changed >= 7,
    'only a later terminal-owned key may reach the terminal route',
  );

  coordinator.dispose();
  dock.dispose();
  await harness.state.shutdown();
}

final class _Harness {
  final TerminalApplicationState state = TerminalApplicationState();

  TerminalPaneConfiguration configuration() => TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _FakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );

  Future<TerminalWindowState> createWindow() async {
    final TerminalWindowState window = await state.createWindow(
      configuration(),
    );
    await state.paneForId(window.selectedTab.focusedPaneId)!.start();
    return window;
  }
}

final class _FakeSession implements TerminalPaneSession {
  _FakeSession(this.id);

  @override
  final TerminalSessionId id;
  bool live = false;

  @override
  bool get isLive => live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() => live
      ? TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: id.paneId.value,
          owningProcessGroup: id.paneId.value,
          foregroundProcessGroup: id.paneId.value,
        )
      : TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => live = true;
  @override
  String render() => '';
  @override
  void insertText(String value) {}
  @override
  void deleteBackward() {}
  @override
  void deleteForward() {}
  @override
  void moveLeft() {}
  @override
  void moveRight() {}
  @override
  void moveToStart() {}
  @override
  void moveToEnd() {}
  @override
  void previousHistory() {}
  @override
  void nextHistory() {}
  @override
  Future<void> submit() async {}
  @override
  void interrupt() {}
  @override
  void suspend() {}
  @override
  void quitForegroundProcess() {}
  @override
  void sendEndOfFile() {}
  @override
  void sendInput(Uint8List bytes) {}
  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async =>
      const TerminalPasteTransferResult(
        disposition: TerminalPasteTransferDisposition.completed,
        encodedBytes: 0,
        completedChunks: 0,
        backpressureCount: 0,
        maximumQueuedBytes: 0,
        concurrentInputRejections: 0,
      );
  @override
  void resize({required int rows, required int columns}) {}
  @override
  void showClipboardNotice(TerminalClipboardNotice notice) {}
  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {}
  @override
  void showCloseConfirmation() {}
  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    live = false;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

Future<void> _expectExecuted(
  TerminalActionDispatcher dispatcher,
  TerminalActionId id,
) async {
  final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
  _expect(
    result.disposition == TerminalActionDispatchDisposition.executed,
    '${id.stableName} should execute: ${result.disposition}',
  );
}

AppKitKeyEvent _key({
  required int keyCode,
  String characters = '',
  ModifierKeys modifiers = const ModifierKeys(0),
  AppKitKeyEventKind kind = AppKitKeyEventKind.down,
}) => AppKitKeyEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  keyCode: keyCode,
  modifiers: modifiers,
  isRepeat: false,
  characters: characters,
  charactersIgnoringModifiers: characters,
);

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal Context Dock expectation failed: $description');
  }
}
