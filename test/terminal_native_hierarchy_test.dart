import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/src/api.dart' show attachApplicationForTesting;
import 'package:dart_appkit/src/native/native_bindings.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNativeHierarchyTests();

Future<void> runTerminalNativeHierarchyTests() async {
  await _testNativeHierarchyProjectionAndLifecycle();
}

Future<void> _testNativeHierarchyProjectionAndLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final List<_HierarchyFakeSession> sessions = <_HierarchyFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalWindowState firstWindow = await state.createWindow(
    configuration,
  );
  final TerminalTabState firstTab = firstWindow.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  final TerminalPane secondPane = await state.splitPane(
    firstPane,
    configuration,
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.25,
  );
  final TerminalSplitNodeId firstRootId = firstTab.splitTree.root.id;
  final TerminalTabState secondTab = await state.createTab(
    firstWindow.id,
    configuration,
  );
  final PaneId thirdPane = secondTab.focusedPaneId;
  final TerminalPane fourthPane = await state.splitPane(
    thirdPane,
    configuration,
    axis: TerminalSplitAxis.vertical,
    fraction: 0.75,
  );
  final Map<PaneId, TerminalSessionMetadata> metadata =
      <PaneId, TerminalSessionMetadata>{
        firstPane: TerminalSessionMetadata(),
        secondPane.id: TerminalSessionMetadata()
          ..setWindowTitle('First live title')
          ..setWorkingDirectory(Uri.parse('file:///private/tmp/first')),
        thirdPane: TerminalSessionMetadata(),
        fourthPane.id: TerminalSessionMetadata()
          ..setWindowTitle('Second live title')
          ..setWorkingDirectory(
            Uri.parse('file://localhost/private/tmp/second'),
          ),
      };
  final TerminalTabPresentationResolver presentationResolver =
      TerminalTabPresentationResolver(
        metadataForPane: (PaneId paneId) => metadata[paneId],
      );
  state
    ..renameTab(secondTab.id, 'Pinned second tab')
    ..setTabColor(secondTab.id, TerminalTabColor.purpleMarker);

  final List<String> lifecycle = <String>[];
  final Map<PaneId, List<String>> layouts = <PaneId, List<String>>{};
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) {
      final View view = View();
      return TerminalNativePaneResources(
        paneId: pane.id,
        view: view,
        onLayout: (TerminalPaneLayoutRect? rectangle, {required bool visible}) {
          layouts
              .putIfAbsent(pane.id, () => <String>[])
              .add(
                visible
                    ? '${rectangle!.left},${rectangle.top},'
                          '${rectangle.width},${rectangle.height}'
                    : 'hidden',
              );
        },
        onDisposeAdapters: () {
          lifecycle.add('adapters:${pane.id}');
        },
      );
    },
    windowFrame: const Rect.fromLTWH(40, 50, 800, 600),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    dividerThickness: 2,
    presentationBuilder: (TerminalWindowState window, TerminalTabState tab) =>
        presentationResolver.resolve(
          tab,
          fallbackTitle: 'Window ${window.id} / Tab ${tab.id}',
        ),
  );
  adapter.reconcile(
    tabSizes: <TerminalTabId, TerminalSplitLayoutSize>{
      firstTab.id: TerminalSplitLayoutSize(width: 400, height: 240),
      secondTab.id: TerminalSplitLayoutSize(width: 500, height: 300),
    },
  );

  final TerminalNativePaneResources firstResources = adapter.resourcesForPane(
    firstPane,
  )!;
  final TerminalNativePaneResources secondResources = adapter.resourcesForPane(
    secondPane.id,
  )!;
  final SplitView firstRoot = adapter.splitViewForNode(firstRootId)!;
  final int firstRootHandle = bindings.handleFor(firstRoot);
  final int secondPaneViewHandle = bindings.handleFor(secondResources.view);
  final int selectedWindowHandle = bindings.handleFor(
    adapter.windowForTab(secondTab.id)!,
  );
  final int fourthPaneViewHandle = bindings.handleFor(
    adapter.resourcesForPane(fourthPane.id)!.view,
  );
  final int firstWindowHandle = bindings.handleFor(
    adapter.windowForTab(firstTab.id)!,
  );
  final List<double> secondTabColor =
      bindings.windowTabColors[selectedWindowHandle]!;
  _expect(
    adapter.nativeWindowCount == 2 &&
        adapter.splitViewCount == 2 &&
        adapter.paneResourceCount == 4 &&
        bindings.windowTabGroups.length == 1 &&
        bindings.windowTabGroups.single.length == 2 &&
        bindings.selectedTabWindows.values.single == selectedWindowHandle &&
        bindings.firstResponders[selectedWindowHandle] == fourthPaneViewHandle,
    'two logical tabs project to one selected native tab group and four panes',
  );
  _expect(
    bindings.windowTitles[firstWindowHandle] == 'First live title' &&
        bindings.windowRepresentedFilePaths[firstWindowHandle] ==
            '/private/tmp/first' &&
        bindings.windowTitles[selectedWindowHandle] == 'Pinned second tab' &&
        bindings.windowRepresentedFilePaths[selectedWindowHandle] ==
            '/private/tmp/second' &&
        secondTabColor[0] == TerminalTabColor.purpleMarker.red / 255 &&
        secondTabColor[1] == TerminalTabColor.purpleMarker.green / 255 &&
        secondTabColor[2] == TerminalTabColor.purpleMarker.blue / 255 &&
        secondTabColor[3] == 1,
    'resolved session title, rename, cwd proxy, and color reach native tabs',
  );
  _expect(
    layouts.length == 4 &&
        layouts.values.every(
          (List<String> values) => values.single != 'hidden',
        ) &&
        adapter.machineLine() ==
            'TERMINAL_NATIVE_HIERARCHY logical_windows=1 native_windows=2 '
                'tabs=2 splits=2 panes=4 active_window=1',
    'initial projection emits one visible bounded layout per pane',
  );
  state
    ..renameTab(secondTab.id, null)
    ..setTabColor(secondTab.id, null);
  metadata[secondPane.id]!
    ..setWindowTitle('Updated first title')
    ..setWorkingDirectory(Uri.parse('file://remote.example/private/ignored'));
  adapter.reconcile();
  _expect(
    bindings.windowTitles[firstWindowHandle] == 'Updated first title' &&
        !bindings.windowRepresentedFilePaths.containsKey(firstWindowHandle) &&
        bindings.windowTitles[selectedWindowHandle] == 'Second live title' &&
        !bindings.windowTabColors.containsKey(selectedWindowHandle),
    'retained windows update live title and clear remote proxy/rename/color',
  );
  state
    ..selectTab(firstWindow.id, firstTab.id)
    ..focusPane(firstTab.id, firstPane)
    ..resizeSplit(firstTab.id, firstRootId, 0.65)
    ..setPaneZoom(firstTab.id, firstPane);
  adapter.reconcile();
  _expect(
    identical(adapter.resourcesForPane(firstPane), firstResources) &&
        identical(adapter.splitViewForNode(firstRootId), firstRoot) &&
        bindings.splitViewFractions[firstRootHandle] == 0.65 &&
        bindings.splitViewZoomedChildren[firstRootHandle] == 0 &&
        layouts[firstPane]!.last != 'hidden' &&
        layouts[secondPane.id]!.last == 'hidden' &&
        bindings.firstResponders[bindings.handleFor(
              adapter.windowForTab(firstTab.id)!,
            )] ==
            bindings.handleFor(firstResources.view),
    'reconciliation preserves stable resources and routes zoomed focus exactly',
  );

  state
    ..setPaneZoom(firstTab.id, null)
    ..equalizeSplits(firstTab.id);
  adapter.resizeTab(
    firstTab.id,
    TerminalSplitLayoutSize(width: 640.5, height: 360.25),
  );
  _expect(
    bindings.splitViewFractions[firstRootHandle] == 0.5 &&
        bindings.splitViewZoomedChildren[firstRootHandle] == -1 &&
        layouts[secondPane.id]!.last != 'hidden',
    'equalize, unzoom, and fractional resize update the existing native tree',
  );

  final TerminalWindowState secondWindow = await state.createWindow(
    configuration,
  );
  adapter.reconcile();
  _expect(
    adapter.nativeWindowCount == 3 &&
        bindings.windowTabGroups.length == 1 &&
        state.activeWindowId == secondWindow.id,
    'a second logical window remains outside the first native tab group',
  );

  await state.removePane(secondPane.id);
  adapter.reconcile();
  _expect(
    firstRoot.isDisposed &&
        secondResources.isDisposed &&
        identical(adapter.resourcesForPane(firstPane), firstResources) &&
        adapter.splitViewForNode(firstRootId) == null &&
        lifecycle.contains('adapters:${secondPane.id}') &&
        bindings.releaseOrder.indexOf(firstRootHandle) <
            bindings.releaseOrder.indexOf(secondPaneViewHandle),
    'collapsed split disposes pane adapters, then split, then removed pane view',
  );

  final SplitView secondRoot = adapter.splitViews.values.single;
  final Window removedTabWindow = adapter.windowForTab(secondTab.id)!;
  await state.removePane(fourthPane.id);
  adapter.reconcile();
  _expect(secondRoot.isDisposed, 'nested split disposal follows tree collapse');
  await state.removePane(thirdPane);
  adapter.reconcile();
  _expect(
    removedTabWindow.isDisposed &&
        adapter.windowForTab(secondTab.id) == null &&
        adapter.nativeWindowCount == 2 &&
        firstWindow.selectedTabId == firstTab.id,
    'last pane removal detaches and disposes its native tab window',
  );

  adapter.dispose();
  adapter.dispose();
  _expect(
    bindings.objects.isEmpty &&
        bindings.windowRepresentedFilePaths.isEmpty &&
        bindings.windowTabColors.isEmpty &&
        firstResources.isDisposed &&
        adapter.nativeWindowCount == 0 &&
        adapter.splitViewCount == 0 &&
        adapter.paneResourceCount == 0,
    'adapter shutdown releases all remaining native handles exactly once',
  );
  _expectThrows<StateError>(adapter.reconcile, 'disposed adapter rejects work');
  await state.shutdown();
  _expect(
    sessions.every(
      (_HierarchyFakeSession session) => session.shutdownCount == 1,
    ),
    'native teardown remains separate from exact logical session shutdown',
  );
  await application.terminate();
  await rawEvents.close();
}

TerminalPaneConfiguration _configuration(
  List<_HierarchyFakeSession> sessions,
) => TerminalPaneConfiguration(
  sessionFactory:
      (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) {
        final _HierarchyFakeSession session = _HierarchyFakeSession(id);
        sessions.add(session);
        return session;
      },
  onChanged: () {},
  onExitRequested: () {},
);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}

final class _HierarchyFakeSession implements TerminalPaneSession {
  _HierarchyFakeSession(this.id);

  @override
  final TerminalSessionId id;

  var live = false;
  var shutdownCount = 0;

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
  Future<void> start() async {
    live = true;
  }

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

final class _HierarchyNativeBindings implements NativeBindings {
  int _nextHandle = 100;
  final Map<int, String> objects = <int, String>{};
  final Map<Object, int> _handles = Map<Object, int>.identity();
  final Map<int, String> windowTitles = <int, String>{};
  final Map<int, String> windowRepresentedFilePaths = <int, String>{};
  final Map<int, List<double>> windowTabColors = <int, List<double>>{};
  final Map<int, int> contentViews = <int, int>{};
  final Map<int, int> firstResponders = <int, int>{};
  final List<List<int>> windowTabGroups = <List<int>>[];
  final Map<int, int> selectedTabWindows = <int, int>{};
  final Map<int, int> splitViewAxes = <int, int>{};
  final Map<int, List<int>> splitViewChildren = <int, List<int>>{};
  final Map<int, double> splitViewFractions = <int, double>{};
  final Map<int, int> splitViewZoomedChildren = <int, int>{};
  final List<int> releaseOrder = <int>[];

  int handleFor(Object resource) => _handles[resource]!;

  NativeValueResult<int> _create(String kind) {
    final int handle = _nextHandle++;
    objects[handle] = kind;
    return NativeValueResult<int>.success(handle);
  }

  @override
  int abiVersion() => dartAppKitAbiVersion;

  @override
  NativeValueResult<int> applicationSetEventPortVersioned({
    required int port,
    required int minimumVersion,
    required int maximumVersion,
  }) => NativeValueResult<int>.success(maximumVersion);

  @override
  NativeCallResult applicationSetEventPort(int port) =>
      const NativeCallResult.success();

  @override
  NativeValueResult<int> debugIsMainThread() =>
      const NativeValueResult<int>.success(1);

  @override
  NativeCallResult applicationTerminate() => const NativeCallResult.success();

  @override
  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
  }) {
    final NativeValueResult<int> result = _create('window');
    windowTitles[result.value!] = title;
    return result;
  }

  @override
  NativeCallResult windowSetTitle(int handle, String title) {
    windowTitles[handle] = title;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetRepresentedFilePath(int handle, String? path) {
    if (path == null) {
      windowRepresentedFilePaths.remove(handle);
    } else {
      windowRepresentedFilePaths[handle] = path;
    }
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetTabColor({
    required int handle,
    required bool hasColor,
    required double red,
    required double green,
    required double blue,
    required double alpha,
  }) {
    if (hasColor) {
      windowTabColors[handle] = <double>[red, green, blue, alpha];
    } else {
      windowTabColors.remove(handle);
    }
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle) {
    contentViews[windowHandle] = viewHandle;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetKeyEventRouting(int handle, int routing) =>
      const NativeCallResult.success();

  @override
  NativeCallResult windowSetCloseRequestDeferral(int handle, bool enabled) =>
      const NativeCallResult.success();

  @override
  NativeCallResult windowAddTabbedWindow(int handle, int tabbedWindowHandle) {
    for (final List<int> group in windowTabGroups.toList()) {
      if (group.remove(tabbedWindowHandle) && group.length < 2) {
        windowTabGroups.remove(group);
      }
    }
    List<int>? group;
    for (final List<int> candidate in windowTabGroups) {
      if (candidate.contains(handle)) {
        group = candidate;
        break;
      }
    }
    group ??= <int>[handle];
    if (!windowTabGroups.contains(group)) windowTabGroups.add(group);
    group.add(tabbedWindowHandle);
    selectedTabWindows[group.first] = handle;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowRemoveFromTabGroup(int handle) {
    for (final List<int> group in windowTabGroups.toList()) {
      final int oldKey = group.first;
      if (!group.remove(handle)) continue;
      final int? selected = selectedTabWindows.remove(oldKey);
      if (group.length < 2) {
        windowTabGroups.remove(group);
      } else {
        selectedTabWindows[group.first] = selected == handle
            ? group.first
            : selected!;
      }
      break;
    }
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSelectTab(int handle) {
    for (final List<int> group in windowTabGroups) {
      if (group.contains(handle)) selectedTabWindows[group.first] = handle;
    }
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowMakeFirstResponder(int handle, int viewHandle) {
    final int? root = contentViews[handle];
    if (root == null || !_containsView(root, viewHandle)) {
      return const NativeCallResult.failure(1, 'view is not attached');
    }
    firstResponders[handle] = viewHandle;
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<int> viewCreate() => _create('view');

  @override
  NativeValueResult<int> splitViewCreate(int axis) {
    final NativeValueResult<int> result = _create('split');
    splitViewAxes[result.value!] = axis;
    splitViewFractions[result.value!] = 0.5;
    splitViewZoomedChildren[result.value!] = -1;
    return result;
  }

  @override
  NativeCallResult splitViewSetChildren(
    int splitViewHandle,
    int firstViewHandle,
    int secondViewHandle,
  ) {
    splitViewChildren[splitViewHandle] = <int>[
      firstViewHandle,
      secondViewHandle,
    ];
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult splitViewSetPosition({
    required int handle,
    required double fraction,
    required double firstMinimumExtent,
    required double secondMinimumExtent,
  }) {
    splitViewFractions[handle] = fraction;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult splitViewEqualize(int handle) {
    splitViewFractions[handle] = 0.5;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult splitViewSetZoomedChild(int handle, int child) {
    splitViewZoomedChildren[handle] = child;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult release(int handle) {
    releaseOrder.add(handle);
    objects.remove(handle);
    windowTitles.remove(handle);
    windowRepresentedFilePaths.remove(handle);
    windowTabColors.remove(handle);
    contentViews.remove(handle);
    firstResponders.remove(handle);
    splitViewAxes.remove(handle);
    splitViewChildren.remove(handle);
    splitViewFractions.remove(handle);
    splitViewZoomedChildren.remove(handle);
    return const NativeCallResult.success();
  }

  bool _containsView(int root, int target) {
    if (root == target) return true;
    return splitViewChildren[root]?.any(
          (int child) => _containsView(child, target),
        ) ??
        false;
  }

  @override
  NativeValueResult<int> debugLiveObjectCount() =>
      NativeValueResult<int>.success(objects.length);

  @override
  void attachFinalizer(Finalizable value, int handle, Object detachKey) {
    _handles[value] = handle;
  }

  @override
  void detachFinalizer(Object detachKey) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('unexpected native call ${invocation.memberName}');
  }
}
