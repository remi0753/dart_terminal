import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalAppleScriptProductTests();

Future<void> runTerminalAppleScriptProductTests() async {
  await _testSnapshotProjectionExcludesQuickTerminal();
  await _testHierarchyInputAndTargetPolicies();
  await _testSplitDirectionAndClosePolicies();
  await _testNativeQueueLifecycle();
}

Future<void> _testSnapshotProjectionExcludesQuickTerminal() async {
  final _Harness harness = _Harness();
  final TerminalWindowState standard = await harness.createWindow();
  final TerminalTabState secondTab = await harness.state.createTab(
    standard.id,
    harness.configuration(standard.selectedTab.focusedPaneId),
  );
  await harness.startPane(secondTab.focusedPaneId);
  final TerminalPane split = await harness.state.splitPane(
    secondTab.focusedPaneId,
    harness.configuration(secondTab.focusedPaneId),
    axis: TerminalSplitAxis.horizontal,
  );
  await harness.startPane(split.id);
  final TerminalWindowState quick = await harness.createWindow(
    role: TerminalWindowRole.quickTerminal,
  );
  final _FakeNativePort port = _FakeNativePort();
  final TerminalAppleScriptProductSession session =
      TerminalAppleScriptProductSession(
        state: harness.state,
        enabled: true,
        nativePort: port,
        executor: _ImmediateExecutor(),
        titleForTab: (TerminalTabState tab) => 'tab-${tab.id.value}',
        titleForTerminal: (PaneId paneId) => 'terminal-${paneId.value}',
        workingDirectoryFor: (PaneId paneId) => '/tmp/${paneId.value}',
        startPolling: false,
      );
  final TerminalAppleScriptApplicationSnapshot snapshot =
      TerminalAppleScriptSnapshotCodec.decode(port.snapshots.single);
  _expect(
    snapshot.windows.length == 1 &&
        snapshot.windows.single.id.externalValue ==
            'window:${standard.id.value}' &&
        !snapshot.windows.single.frontmost &&
        snapshot.windows.single.tabs.length == 2 &&
        snapshot.windows.single.tabs.last.selected &&
        snapshot.windows.single.tabs.last.terminals.length == 2 &&
        snapshot.windows.single.tabs.last.focusedTerminalId.externalValue ==
            'terminal:${split.id.value}' &&
        snapshot.windows.single.tabs.last.terminals.last.workingDirectory ==
            '/tmp/${split.id.value}' &&
        snapshot.windows.single.title == 'tab-${secondTab.id.value}' &&
        quick.role == TerminalWindowRole.quickTerminal,
    'snapshot must retain stable ordering and selection while excluding Quick Terminal',
  );
  session.dispose();
  await harness.dispose();
}

Future<void> _testHierarchyInputAndTargetPolicies() async {
  final _Harness harness = _Harness();
  final TerminalWindowState initial = await harness.createWindow();
  final PaneId initialPane = initial.selectedTab.focusedPaneId;
  var operation = 0;

  final TerminalAppleScriptCommandResult newWindow = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.newWindow,
    ),
  );
  _expect(
    newWindow.isCompleted &&
        newWindow.object?.kind == TerminalAppleScriptObjectKind.window &&
        harness.state.windowCount == 2,
    'new-window must create, start, and return one cached standard window',
  );
  final TerminalAppleScriptCommandResult newTab = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.newTab,
      target: _window(initial.id),
    ),
  );
  _expect(
    newTab.isCompleted &&
        newTab.object?.kind == TerminalAppleScriptObjectKind.tab &&
        initial.tabs.length == 2 &&
        harness.state.activeWindowId == initial.id,
    'new-tab must honor its explicit standard-window target',
  );

  final TerminalAppleScriptCommandResult focus = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.focus,
      target: _terminal(initialPane),
    ),
  );
  final TerminalAppleScriptCommandResult safeInput = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.inputText,
      target: _terminal(initialPane),
      text: 'echo safe',
    ),
  );
  _expect(
    focus.isCompleted &&
        safeInput.isCompleted &&
        harness.sessions[initialPane]!.pasteCount == 1 &&
        initial.selectedTab.focusedPaneId == initialPane,
    'focus and safe input must route through the live targeted terminal',
  );

  final TerminalAppleScriptCommandResult riskyFirst = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.inputText,
      target: _terminal(initialPane),
      text: 'first\nsecond',
    ),
  );
  final TerminalAppleScriptCommandResult riskySecond = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.inputText,
      target: _terminal(initialPane),
      text: 'first\nsecond',
    ),
  );
  _expect(
    riskyFirst.disposition ==
            TerminalAppleScriptCommandDisposition.confirmationRequired &&
        riskySecond.isCompleted &&
        harness.sessions[initialPane]!.pasteCount == 2 &&
        harness.sessions[initialPane]!.lastPasteWasMultiline,
    'AppleScript input must use the ordinary paste confirmation gate',
  );

  final TerminalWindowState quick = await harness.createWindow(
    role: TerminalWindowRole.quickTerminal,
  );
  final TerminalAppleScriptCommandResult hiddenTarget = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.focus,
      target: _terminal(quick.selectedTab.focusedPaneId),
    ),
  );
  harness.mutationAllowed = false;
  final TerminalAppleScriptCommandResult gated = await harness.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.newWindow,
    ),
  );
  _expect(
    hiddenTarget.disposition ==
            TerminalAppleScriptCommandDisposition.notFound &&
        gated.disposition == TerminalAppleScriptCommandDisposition.busy,
    'hidden Quick Terminal objects and active mutation transactions must fail closed',
  );
  await harness.dispose();
}

Future<void> _testSplitDirectionAndClosePolicies() async {
  var operation = 100;
  for (final TerminalAppleScriptSplitDirection direction
      in TerminalAppleScriptSplitDirection.values) {
    final _Harness harness = _Harness();
    final TerminalWindowState window = await harness.createWindow();
    final PaneId original = window.selectedTab.focusedPaneId;
    final TerminalAppleScriptCommandResult result = await harness.execute(
      TerminalAppleScriptCommandRequest(
        operationId: ++operation,
        kind: TerminalAppleScriptCommandKind.split,
        target: _terminal(original),
        direction: direction,
      ),
    );
    final TerminalSplitBranch root =
        window.selectedTab.splitTree.root as TerminalSplitBranch;
    final PaneId created = PaneId(result.object!.value);
    final bool before =
        direction == TerminalAppleScriptSplitDirection.left ||
        direction == TerminalAppleScriptSplitDirection.up;
    final bool horizontal =
        direction == TerminalAppleScriptSplitDirection.left ||
        direction == TerminalAppleScriptSplitDirection.right;
    _expect(
      result.isCompleted &&
          root.axis ==
              (horizontal
                  ? TerminalSplitAxis.horizontal
                  : TerminalSplitAxis.vertical) &&
          window.selectedTab.paneIds.indexOf(created) == (before ? 0 : 1),
      'split direction $direction did not retain its axis and placement',
    );
    await harness.dispose();
  }

  final _Harness risky = _Harness();
  final TerminalWindowState riskyWindow = await risky.createWindow();
  final PaneId riskyPane = riskyWindow.selectedTab.focusedPaneId;
  risky.sessions[riskyPane]!.requiresCloseConfirmation = true;
  final TerminalAppleScriptCommandRequest closeRisky =
      TerminalAppleScriptCommandRequest(
        operationId: ++operation,
        kind: TerminalAppleScriptCommandKind.closeTerminal,
        target: _terminal(riskyPane),
      );
  final TerminalAppleScriptCommandResult confirmation = await risky.execute(
    closeRisky,
  );
  final TerminalAppleScriptCommandResult confirmed = await risky.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.closeTerminal,
      target: _terminal(riskyPane),
    ),
  );
  _expect(
    confirmation.disposition ==
            TerminalAppleScriptCommandDisposition.confirmationRequired &&
        confirmed.isCompleted &&
        risky.state.paneForId(riskyPane) == null,
    'repeating a risky close must confirm through the shared close coordinator',
  );
  await risky.dispose();

  final _Harness aggregate = _Harness();
  final TerminalWindowState aggregateWindow = await aggregate.createWindow();
  final TerminalTabState aggregateTab = aggregateWindow.selectedTab;
  final TerminalPane extra = await aggregate.state.splitPane(
    aggregateTab.focusedPaneId,
    aggregate.configuration(aggregateTab.focusedPaneId),
    axis: TerminalSplitAxis.horizontal,
  );
  await aggregate.startPane(extra.id);
  final TerminalAppleScriptCommandResult closeTab = await aggregate.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.closeTab,
      target: _tab(aggregateTab.id),
    ),
  );
  final TerminalAppleScriptCommandResult stale = await aggregate.execute(
    TerminalAppleScriptCommandRequest(
      operationId: ++operation,
      kind: TerminalAppleScriptCommandKind.closeWindow,
      target: _window(aggregateWindow.id),
    ),
  );
  _expect(
    closeTab.isCompleted &&
        aggregate.state.windowForId(aggregateWindow.id) == null &&
        stale.disposition == TerminalAppleScriptCommandDisposition.notFound,
    'aggregate tab close must drain its panes and stale objects must not retarget',
  );
  await aggregate.dispose();
}

Future<void> _testNativeQueueLifecycle() async {
  final _Harness harness = _Harness();
  await harness.createWindow();
  final _FakeNativePort port = _FakeNativePort();
  final List<Object> errors = <Object>[];
  final TerminalAppleScriptProductSession session =
      TerminalAppleScriptProductSession(
        state: harness.state,
        enabled: true,
        nativePort: port,
        executor: _ImmediateExecutor(),
        titleForTab: (TerminalTabState tab) => 'tab',
        titleForTerminal: (PaneId paneId) => 'terminal',
        workingDirectoryFor: (PaneId paneId) => null,
        onError: (Object error, StackTrace stackTrace) => errors.add(error),
        maximumCommandsPerPoll: 2,
        startPolling: false,
      );
  port.commands.addAll(<Uint8List>[
    _commandPacket(1),
    _commandPacket(2),
    _commandPacket(3),
  ]);
  _expect(session.pollOnce() == 2, 'one poll exceeded its fairness bound');
  await _flushMicrotasks();
  _expect(
    port.completions.map((item) => item.operationId).join(',') == '1,2' &&
        session.pollOnce() == 1,
    'native commands were not completed exactly once in queue order',
  );
  await _flushMicrotasks();
  session.applyEnabled(false);
  final TerminalAppleScriptApplicationSnapshot disabled =
      TerminalAppleScriptSnapshotCodec.decode(port.snapshots.last);
  port.commands.add(_commandPacket(4));
  _expect(
    !disabled.enabled &&
        disabled.windows.isEmpty &&
        session.pollOnce() == 0 &&
        port.commands.length == 1,
    'disabled scripting did not publish an empty cache and stop queue intake',
  );
  session.applyEnabled(true);
  _expect(
    session.pollOnce() == 1,
    're-enabled scripting did not resume intake',
  );
  await _flushMicrotasks();
  port.commands.add(Uint8List.fromList(utf8.encode('{}')));
  _expectThrows<FormatException>(
    session.pollOnce,
    'malformed native command bypassed strict product decoding',
  );
  session.dispose();
  final TerminalAppleScriptApplicationSnapshot disposed =
      TerminalAppleScriptSnapshotCodec.decode(port.snapshots.last);
  _expect(
    port.disposed &&
        !disposed.enabled &&
        disposed.windows.isEmpty &&
        errors.isEmpty,
    'session disposal did not clear the cache and close the native port',
  );

  final _FakeNativePort epochPort = _FakeNativePort();
  final _ControlledExecutor controlled = _ControlledExecutor();
  final TerminalAppleScriptProductSession epochSession =
      TerminalAppleScriptProductSession(
        state: harness.state,
        enabled: true,
        nativePort: epochPort,
        executor: controlled,
        titleForTab: (TerminalTabState tab) => 'tab',
        titleForTerminal: (PaneId paneId) => 'terminal',
        workingDirectoryFor: (PaneId paneId) => null,
        startPolling: false,
      );
  epochPort.commands.add(_commandPacket(5));
  _expect(epochSession.pollOnce() == 1, 'controlled command was not admitted');
  await _flushMicrotasks();
  epochSession
    ..applyEnabled(false)
    ..applyEnabled(true);
  controlled.complete();
  await _flushMicrotasks();
  _expect(
    epochPort.completions.isEmpty,
    'a command invalidated by disable was completed after re-enable',
  );
  epochSession.dispose();
  await harness.dispose();
}

final class _Harness {
  final TerminalApplicationState state = TerminalApplicationState();
  final Map<PaneId, _FakeSession> sessions = <PaneId, _FakeSession>{};
  var reconcileCount = 0;
  var clock = 0;
  bool mutationAllowed = true;

  late final TerminalExternalPasteController<PaneId> pasteController =
      TerminalExternalPasteController<PaneId>(
        resolveTarget: (PaneId paneId) {
          final TerminalPane? pane = state.paneForId(paneId);
          final TerminalWindowState? active = state.activeWindow;
          if (pane == null ||
              !pane.isLive ||
              active?.selectedTab.focusedPaneId != paneId) {
            return null;
          }
          return TerminalExternalPasteTarget(
            identity: pane,
            bracketedPasteMode: pane.bracketedPasteMode,
            pasteInProgress: pane.pasteInProgress,
            showNotice: pane.showClipboardNotice,
            paste: pane.paste,
          );
        },
        monotonicMicros: () => ++clock,
      );
  late final TerminalPaneCloseCoordinator closeCoordinator =
      TerminalPaneCloseCoordinator(
        state: state,
        onHierarchyChanged: () => reconcileCount++,
      );
  late final TerminalAppleScriptProductCommandExecutor executor =
      TerminalAppleScriptProductCommandExecutor(
        state: state,
        configurationFactory: configuration,
        startPane: startPane,
        reconcile: () => reconcileCount++,
        pasteController: pasteController,
        paneCloseCoordinator: closeCoordinator,
        canMutate: () => mutationAllowed,
      );

  Future<TerminalWindowState> createWindow({
    TerminalWindowRole role = TerminalWindowRole.standard,
  }) async {
    final TerminalWindowState window = await state.createWindow(
      configuration(null),
      role: role,
    );
    await startPane(window.selectedTab.focusedPaneId);
    return window;
  }

  TerminalPaneConfiguration configuration(
    PaneId? source, {
    String? workingDirectoryOverride,
  }) => TerminalPaneConfiguration(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          final _FakeSession session = _FakeSession(id);
          sessions[id.paneId] = session;
          return session;
        },
    onChanged: () {},
    onExitRequested: () {},
  );

  Future<void> startPane(PaneId paneId) => state.paneForId(paneId)!.start();

  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) => executor.execute(request);

  Future<void> dispose() async {
    pasteController.dispose();
    await state.shutdown();
  }
}

final class _FakeSession implements TerminalPaneSession {
  _FakeSession(this.id);

  @override
  final TerminalSessionId id;
  bool live = false;
  bool requiresCloseConfirmation = false;
  int pasteCount = 0;
  bool lastPasteWasMultiline = false;

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
          foregroundProcessGroup: requiresCloseConfirmation
              ? id.paneId.value + 1000
              : id.paneId.value,
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
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async {
    pasteCount++;
    lastPasteWasMultiline = plan.analysis.logicalNewlineCount > 0;
    return const TerminalPasteTransferResult(
      disposition: TerminalPasteTransferDisposition.completed,
      encodedBytes: 0,
      completedChunks: 0,
      backpressureCount: 0,
      maximumQueuedBytes: 0,
      concurrentInputRejections: 0,
    );
  }

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

final class _ImmediateExecutor implements TerminalAppleScriptCommandExecutor {
  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) async => TerminalAppleScriptCommandResult(
    operationId: request.operationId,
    disposition: TerminalAppleScriptCommandDisposition.completed,
  );
}

final class _ControlledExecutor implements TerminalAppleScriptCommandExecutor {
  final Completer<TerminalAppleScriptCommandResult> _completion =
      Completer<TerminalAppleScriptCommandResult>();
  TerminalAppleScriptCommandRequest? _request;

  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) {
    _request = request;
    return _completion.future;
  }

  void complete() {
    final TerminalAppleScriptCommandRequest request = _request!;
    _completion.complete(
      TerminalAppleScriptCommandResult(
        operationId: request.operationId,
        disposition: TerminalAppleScriptCommandDisposition.completed,
      ),
    );
  }
}

final class _FakeNativeCompletion {
  const _FakeNativeCompletion(
    this.operationId,
    this.disposition,
    this.objectId,
  );

  final int operationId;
  final TerminalAppleScriptCommandDisposition disposition;
  final String? objectId;
}

final class _FakeNativePort implements TerminalAppleScriptNativePort {
  final List<Uint8List> snapshots = <Uint8List>[];
  final List<Uint8List> commands = <Uint8List>[];
  final List<_FakeNativeCompletion> completions = <_FakeNativeCompletion>[];
  bool disposed = false;

  @override
  void publishSnapshot(Uint8List bytes) =>
      snapshots.add(Uint8List.fromList(bytes));
  @override
  Uint8List? takeCommand() => commands.isEmpty ? null : commands.removeAt(0);
  @override
  void completeCommand(
    int operationId,
    TerminalAppleScriptCommandDisposition disposition, {
    String? objectId,
  }) => completions.add(
    _FakeNativeCompletion(operationId, disposition, objectId),
  );
  @override
  void dispose() => disposed = true;
}

Uint8List _commandPacket(int operationId) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'version': 1,
      'operationId': operationId,
      'kind': 'newWindow',
      'target': null,
      'direction': null,
      'text': null,
    }),
  ),
);

TerminalAppleScriptObjectId _window(TerminalWindowId id) =>
    TerminalAppleScriptObjectId(TerminalAppleScriptObjectKind.window, id.value);
TerminalAppleScriptObjectId _tab(TerminalTabId id) =>
    TerminalAppleScriptObjectId(TerminalAppleScriptObjectKind.tab, id.value);
TerminalAppleScriptObjectId _terminal(PaneId id) => TerminalAppleScriptObjectId(
  TerminalAppleScriptObjectKind.terminal,
  id.value,
);

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() callback, String message) {
  try {
    callback();
  } on T {
    return;
  }
  throw StateError(message);
}
