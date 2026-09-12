import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalRestorationTests();

Future<void> runTerminalRestorationTests() async {
  _testWindowPlacementPolicy();
  _testStrictCodecRejection();
  await _testBoundedFileStore();
  await _testQuickTerminalRestorationExclusion();
  await _testHierarchyRoundTripAndFreshOwnership();
  await _testRestoreFailureIsAtomic();
}

Future<void> _testQuickTerminalRestorationExclusion() async {
  final List<_RestorationFakeSession> sessions = <_RestorationFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState standard = await state.createWindow(
    _configuration(sessions, '/private/tmp/standard'),
  );
  final TerminalWindowState quick = await state.createWindow(
    _configuration(sessions, '/private/tmp/quick'),
    role: TerminalWindowRole.quickTerminal,
  );
  final List<TerminalWindowId> placementRequests = <TerminalWindowId>[];
  final TerminalRestorationSnapshot snapshot =
      TerminalApplicationRestorationCapture.capture(
        state,
        placementForWindow: (TerminalWindowId id) {
          placementRequests.add(id);
          return _minimalPlacement();
        },
        workingDirectoryForPane: (PaneId id) => null,
      );
  _expect(
    snapshot.windows.length == 1 &&
        snapshot.activeWindowIndex == 0 &&
        placementRequests.length == 1 &&
        placementRequests.single == standard.id,
    'restoration excludes the active Quick Terminal and its placement',
  );

  await state.removePane(standard.selectedTab.focusedPaneId);
  _expect(
    identical(state.quickTerminalWindow, quick) && state.windowCount == 1,
    'Quick Terminal remains live after the last standard window closes',
  );
  _expectThrows<StateError>(
    () => TerminalApplicationRestorationCapture.capture(
      state,
      placementForWindow: (TerminalWindowId id) => _minimalPlacement(),
      workingDirectoryForPane: (PaneId id) => null,
    ),
    'restoration refuses to serialize an application with no standard window',
  );
  await state.shutdown();
  _expect(
    sessions.every(
      (_RestorationFakeSession session) => session.shutdownCount == 1,
    ),
    'restoration exclusion fixture releases standard and Quick Terminal panes',
  );
}

Future<void> _testBoundedFileStore() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'dart-terminal-restoration-',
  );
  final String path = '${directory.path}/nested/state.json';
  try {
    final FileTerminalRestorationStore store = FileTerminalRestorationStore(
      path,
    );
    _expect(await store.read() == null, 'a missing restoration file is absent');

    await store.write('{"generation":1}');
    _expect(
      await store.read() == '{"generation":1}' &&
          !await File('$path.pending').exists(),
      'the first bounded file write is readable without a pending artifact',
    );
    await store.write('{"generation":2}');
    _expect(
      await store.read() == '{"generation":2}',
      'same-directory replacement overwrites an existing restoration file',
    );

    final List<int> oversized = List<int>.filled(
      TerminalRestorationLimits.maximumSerializedUtf8Bytes + 1,
      0x61,
    );
    await _expectFutureThrows<TerminalRestorationLimitException>(() async {
      await store.write(String.fromCharCodes(oversized));
    }, 'the file store rejects oversized output before writing');
    await File(path).writeAsBytes(oversized, flush: true);
    await _expectFutureThrows<TerminalRestorationLimitException>(() async {
      await store.read();
    }, 'the file store rejects oversized input before decoding it');
    await File(path).writeAsBytes(const <int>[0xff], flush: true);
    await _expectFutureThrows<FormatException>(() async {
      await store.read();
    }, 'the file store rejects malformed UTF-8');

    _expectThrows<ArgumentError>(
      () => FileTerminalRestorationStore('relative.json'),
      'the file store rejects relative paths',
    );
    _expectThrows<ArgumentError>(
      () => FileTerminalRestorationStore('${directory.path}/'),
      'the file store rejects directory-shaped paths',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

void _testWindowPlacementPolicy() {
  final TerminalScreenPlacement source = TerminalScreenPlacement(
    displayId: 41,
    frame: TerminalWindowFrame(left: -1920, top: 0, width: 1920, height: 1080),
    visibleFrame: TerminalWindowFrame(
      left: -1920,
      top: 25,
      width: 1920,
      height: 1055,
    ),
  );
  final TerminalScreenPlacement destination = TerminalScreenPlacement(
    displayId: 77,
    frame: TerminalWindowFrame(left: 0, top: 0, width: 1512, height: 982),
    visibleFrame: TerminalWindowFrame(
      left: 0,
      top: 23,
      width: 1512,
      height: 959,
    ),
  );
  final TerminalWindowPlacement saved = TerminalWindowPlacement(
    windowedFrame: TerminalWindowFrame(
      left: -1800,
      top: 100,
      width: 960,
      height: 500,
    ),
    screen: source,
    fullscreen: true,
  );
  final TerminalWindowPlacement migrated =
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        saved,
        <TerminalScreenPlacement>[destination],
      );
  _expect(
    migrated.screen == destination &&
        migrated.fullscreen &&
        migrated.windowedFrame.left >= destination.visibleFrame.left &&
        migrated.windowedFrame.top >= destination.visibleFrame.top &&
        migrated.windowedFrame.right <= destination.visibleFrame.right &&
        migrated.windowedFrame.bottom <= destination.visibleFrame.bottom &&
        migrated.windowedFrame.width == 960 &&
        migrated.windowedFrame.height == 500,
    'display migration preserves intent and clamps into a new visible frame',
  );

  final TerminalScreenPlacement tiny = TerminalScreenPlacement(
    displayId: 88,
    frame: TerminalWindowFrame(left: 4000, top: -800, width: 240, height: 160),
    visibleFrame: TerminalWindowFrame(
      left: 4000,
      top: -780,
      width: 240,
      height: 140,
    ),
  );
  final TerminalWindowPlacement clamped =
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        TerminalWindowPlacement(
          windowedFrame: TerminalWindowFrame(
            left: -9999,
            top: 9999,
            width: 2000,
            height: 1800,
          ),
          screen: null,
          fullscreen: false,
        ),
        <TerminalScreenPlacement>[destination, tiny],
        fallbackDisplayId: tiny.displayId,
      );
  _expect(
    clamped.screen == tiny &&
        clamped.windowedFrame == tiny.visibleFrame &&
        !clamped.fullscreen,
    'missing display state uses the explicit fallback and its entire tiny area',
  );
  _expect(
    identical(
      TerminalWindowPlacementPolicy.resolveForAvailableScreens(
        saved,
        const <TerminalScreenPlacement>[],
      ),
      saved,
    ),
    'absent screen inventory does not invent replacement coordinates',
  );
}

void _testStrictCodecRejection() {
  final TerminalRestorationSnapshot snapshot = _minimalSnapshot();
  final String encoded = TerminalRestorationCodec.encode(snapshot);
  final TerminalRestorationSnapshot decoded = TerminalRestorationCodec.decode(
    encoded,
  );
  _expect(
    decoded.windows.length == 1 &&
        decoded.tabCount == 1 &&
        decoded.paneCount == 1 &&
        TerminalRestorationCodec.encode(decoded) == encoded,
    'the versioned restoration codec is deterministic',
  );

  final Map<String, Object?> unexpected =
      jsonDecode(encoded) as Map<String, Object?>;
  unexpected['extra'] = true;
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(unexpected)),
    'unexpected semantic keys are rejected',
  );

  final Map<String, Object?> unsupported =
      jsonDecode(encoded) as Map<String, Object?>;
  unsupported['version'] = 2;
  _expectThrows<FormatException>(
    () => TerminalRestorationCodec.decode(jsonEncode(unsupported)),
    'unsupported restoration versions are rejected',
  );

  final Map<String, Object?> unsafe =
      jsonDecode(encoded) as Map<String, Object?>;
  final List<Object?> windows = unsafe['windows']! as List<Object?>;
  final Map<String, Object?> window = windows.single as Map<String, Object?>;
  final List<Object?> tabs = window['tabs']! as List<Object?>;
  final Map<String, Object?> tab = tabs.single as Map<String, Object?>;
  final Map<String, Object?> tree = tab['tree']! as Map<String, Object?>;
  tree['cwd'] = 'relative/or/control\u0000';
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(unsafe)),
    'unsafe launch cwd is rejected before session allocation',
  );

  final Map<String, Object?> invalidZoom =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> invalidZoomWindow =
      (invalidZoom['windows']! as List<Object?>).single as Map<String, Object?>;
  final Map<String, Object?> invalidZoomTab =
      (invalidZoomWindow['tabs']! as List<Object?>).single
          as Map<String, Object?>;
  invalidZoomTab['zoomedPane'] = 1;
  _expectThrows<Object>(
    () => TerminalRestorationCodec.decode(jsonEncode(invalidZoom)),
    'zoom must refer to the focused pane',
  );

  _expectThrows<TerminalRestorationLimitException>(
    () => TerminalRestorationCodec.decode(
      List<String>.filled(
        TerminalRestorationLimits.maximumSerializedUtf8Bytes + 1,
        'x',
      ).join(),
    ),
    'oversized serialized input is rejected before JSON parsing',
  );

  final TerminalRestorableTab onePane = _minimalTab();
  _expectThrows<TerminalRestorationLimitException>(
    () => TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        TerminalRestorableWindow(
          placement: _minimalPlacement(),
          tabs: List<TerminalRestorableTab>.filled(64, onePane),
          selectedTabIndex: 0,
        ),
        TerminalRestorableWindow(
          placement: _minimalPlacement(),
          tabs: <TerminalRestorableTab>[onePane],
          selectedTabIndex: 0,
        ),
      ],
      activeWindowIndex: 0,
    ),
    'global pane admission is bounded below structural maxima',
  );
}

Future<void> _testHierarchyRoundTripAndFreshOwnership() async {
  final List<_RestorationFakeSession> originalSessions =
      <_RestorationFakeSession>[];
  final TerminalApplicationState original = TerminalApplicationState();
  final Map<PaneId, String?> workingDirectories = <PaneId, String?>{};
  TerminalPaneConfiguration originalConfiguration(String? cwd) =>
      _configuration(originalSessions, cwd);

  final TerminalWindowState firstWindow = await original.createWindow(
    originalConfiguration('/private/tmp/one'),
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  workingDirectories[firstPane] = '/private/tmp/one';
  final TerminalPane secondPane = await original.splitPane(
    firstPane,
    originalConfiguration('/private/tmp/two'),
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.3,
  );
  workingDirectories[secondPane.id] = '/private/tmp/two';
  final TerminalPane thirdPane = await original.splitPane(
    secondPane.id,
    originalConfiguration('/private/tmp/three'),
    axis: TerminalSplitAxis.vertical,
    placement: TerminalSplitPlacement.before,
    fraction: 0.7,
  );
  workingDirectories[thirdPane.id] = '/private/tmp/three';
  final TerminalPane fourthPane = await original.splitPane(
    thirdPane.id,
    originalConfiguration('/private/tmp/four'),
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.4,
  );
  workingDirectories[fourthPane.id] = '/private/tmp/four';
  original
    ..focusPane(firstTab.id, fourthPane.id)
    ..setPaneZoom(firstTab.id, fourthPane.id)
    ..renameTab(firstTab.id, 'Restored four-pane tab')
    ..setTabColor(firstTab.id, TerminalTabColor.greenMarker);

  final TerminalTabState secondTab = await original.createTab(
    firstWindow.id,
    originalConfiguration('/private/tmp/five'),
  );
  workingDirectories[secondTab.focusedPaneId] = '/private/tmp/five';
  original.selectTab(firstWindow.id, firstTab.id);
  final TerminalWindowState secondWindow = await original.createWindow(
    originalConfiguration('/private/tmp/six'),
  );
  workingDirectories[secondWindow.selectedTab.focusedPaneId] =
      '/private/tmp/six';
  original.activateWindow(firstWindow.id);

  final Map<TerminalWindowId, TerminalWindowPlacement> placements =
      <TerminalWindowId, TerminalWindowPlacement>{
        firstWindow.id: TerminalWindowPlacement(
          windowedFrame: TerminalWindowFrame(
            left: -1200,
            top: 80,
            width: 920,
            height: 580,
          ),
          screen: TerminalScreenPlacement(
            displayId: 41,
            frame: TerminalWindowFrame(
              left: -1920,
              top: 0,
              width: 1920,
              height: 1080,
            ),
            visibleFrame: TerminalWindowFrame(
              left: -1920,
              top: 25,
              width: 1920,
              height: 1055,
            ),
          ),
          fullscreen: true,
        ),
        secondWindow.id: _minimalPlacement(),
      };
  final TerminalRestorationSnapshot captured =
      TerminalApplicationRestorationCapture.capture(
        original,
        placementForWindow: (TerminalWindowId id) => placements[id]!,
        workingDirectoryForPane: (PaneId id) => workingDirectories[id],
      );
  final String encoded = TerminalRestorationCodec.encode(captured);
  final TerminalRestorationSnapshot decoded = TerminalRestorationCodec.decode(
    encoded,
  );

  final List<_RestorationFakeSession> restoredSessions =
      <_RestorationFakeSession>[];
  final TerminalApplicationState seeded = TerminalApplicationState(
    paneOwner: TerminalPaneOwner(initialPaneId: 400),
    initialWindowId: 100,
    initialTabId: 200,
    initialSplitNodeId: 300,
  );
  final TerminalRestorationResult restored =
      await TerminalApplicationRestorer.restore(
        decoded,
        into: seeded,
        configurationForPane: (TerminalRestorablePane pane) =>
            _configuration(restoredSessions, pane.workingDirectory),
      );
  final TerminalApplicationState restoredState = restored.applicationState;
  _expect(
    restoredState.windowCount == 2 &&
        restoredState.tabCount == 3 &&
        restoredState.paneCount == 6 &&
        restoredState.windowIds.first.value == 101 &&
        restoredState.windows.first.tabIds.first.value == 201 &&
        restoredState.paneIds.first.value == 401 &&
        restoredState.activeWindowId == restoredState.windowIds.first &&
        restoredSessions.length == 6 &&
        restoredSessions.every(
          (_RestorationFakeSession session) =>
              !originalSessions.contains(session),
        ),
    'restore creates a fresh bounded owner graph and preserves active order',
  );
  final TerminalTabState restoredFirstTab =
      restoredState.windows.first.tabs.first;
  _expect(
    restoredFirstTab.paneIds.length == 4 &&
        restoredFirstTab.isZoomed &&
        restoredFirstTab.zoomedPaneId == restoredFirstTab.focusedPaneId &&
        restoredFirstTab.customTitle == 'Restored four-pane tab' &&
        restoredFirstTab.color == TerminalTabColor.greenMarker &&
        restoredState.windows.first.selectedTabId == restoredFirstTab.id &&
        restored.placements[restoredState.windows.first.id]?.fullscreen ==
            true &&
        restored.launchWorkingDirectories.values.toSet().containsAll(<String>{
          '/private/tmp/one',
          '/private/tmp/two',
          '/private/tmp/three',
          '/private/tmp/four',
          '/private/tmp/five',
          '/private/tmp/six',
        }),
    'restore preserves split presentation, focus, metadata, placement, and cwd',
  );

  final TerminalRestorationSnapshot recaptured =
      TerminalApplicationRestorationCapture.capture(
        restoredState,
        placementForWindow: (TerminalWindowId id) => restored.placements[id]!,
        workingDirectoryForPane: (PaneId id) =>
            restored.launchWorkingDirectories[id],
      );
  _expect(
    TerminalRestorationCodec.encode(recaptured) == encoded,
    'multi-window, multi-tab, four-pane hierarchy round-trips exactly',
  );

  await restoredState.shutdown();
  await original.shutdown();
  _expect(
    restoredSessions.every(
          (_RestorationFakeSession session) => session.shutdownCount == 1,
        ) &&
        originalSessions.every(
          (_RestorationFakeSession session) => session.shutdownCount == 1,
        ),
    'original and restored fresh sessions each shut down exactly once',
  );
}

Future<void> _testRestoreFailureIsAtomic() async {
  final List<_RestorationFakeSession> sessions = <_RestorationFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  var configurations = 0;
  await _expectFutureThrows<StateError>(
    () => TerminalApplicationRestorer.restore(
      TerminalRestorationSnapshot(
        windows: <TerminalRestorableWindow>[
          TerminalRestorableWindow(
            placement: _minimalPlacement(),
            tabs: <TerminalRestorableTab>[
              TerminalRestorableTab(
                splitTree: TerminalRestorableSplitBranch(
                  axis: TerminalSplitAxis.horizontal,
                  fraction: 0.5,
                  first: TerminalRestorableSplitLeaf(
                    TerminalRestorablePane(workingDirectory: '/private/tmp'),
                  ),
                  second: TerminalRestorableSplitLeaf(
                    TerminalRestorablePane(workingDirectory: '/private/tmp'),
                  ),
                ),
                focusedPaneIndex: 0,
                zoomedPaneIndex: null,
                customTitle: null,
                color: null,
              ),
            ],
            selectedTabIndex: 0,
          ),
        ],
        activeWindowIndex: 0,
      ),
      into: state,
      configurationForPane: (TerminalRestorablePane pane) {
        configurations++;
        if (configurations == 2) throw StateError('injected restore failure');
        return _configuration(sessions, pane.workingDirectory);
      },
    ),
    'injected restore failure is surfaced',
  );
  _expect(
    state.isDisposed &&
        state.windowCount == 0 &&
        state.paneCount == 0 &&
        sessions.single.shutdownCount == 1,
    'partial restoration shuts down its admitted owner graph atomically',
  );
}

TerminalRestorationSnapshot _minimalSnapshot() => TerminalRestorationSnapshot(
  windows: <TerminalRestorableWindow>[
    TerminalRestorableWindow(
      placement: _minimalPlacement(),
      tabs: <TerminalRestorableTab>[_minimalTab()],
      selectedTabIndex: 0,
    ),
  ],
  activeWindowIndex: 0,
);

TerminalRestorableTab _minimalTab() => TerminalRestorableTab(
  splitTree: TerminalRestorableSplitLeaf(
    TerminalRestorablePane(workingDirectory: '/private/tmp'),
  ),
  focusedPaneIndex: 0,
  zoomedPaneIndex: null,
  customTitle: null,
  color: null,
);

TerminalWindowPlacement _minimalPlacement() => TerminalWindowPlacement(
  windowedFrame: TerminalWindowFrame(
    left: 100,
    top: 90,
    width: 920,
    height: 580,
  ),
  screen: null,
  fullscreen: false,
);

TerminalPaneConfiguration _configuration(
  List<_RestorationFakeSession> sessions,
  String? workingDirectory,
) => TerminalPaneConfiguration(
  sessionFactory:
      (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) {
        final _RestorationFakeSession session = _RestorationFakeSession(
          id,
          workingDirectory,
        );
        sessions.add(session);
        return session;
      },
  onChanged: () {},
  onExitRequested: () {},
);

final class _RestorationFakeSession implements TerminalPaneSession {
  _RestorationFakeSession(this.id, this.workingDirectory);

  @override
  final TerminalSessionId id;
  final String? workingDirectory;
  var shutdownCount = 0;

  @override
  bool get isLive => shutdownCount == 0;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;

  @override
  TerminalPaneProcessSnapshot processSnapshot() => shutdownCount == 0
      ? TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: id.paneId.value,
          owningProcessGroup: id.paneId.value,
          foregroundProcessGroup: id.paneId.value,
        )
      : TerminalPaneProcessSnapshot.nonLive(id);

  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();

  @override
  bool get bracketedPasteMode => false;

  @override
  bool get pasteInProgress => false;

  @override
  Future<void> start() async {}

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
    shutdownCount++;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError(message);
}

Future<void> _expectFutureThrows<T extends Object>(
  Future<void> Function() body,
  String message,
) async {
  try {
    await body();
  } on T {
    return;
  }
  throw StateError(message);
}
