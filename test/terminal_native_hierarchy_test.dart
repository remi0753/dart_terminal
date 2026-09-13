import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/src/api.dart' show attachApplicationForTesting;
import 'package:dart_appkit/src/native/native_bindings.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_appkit_policy.dart';
import 'package:dart_terminal/src/terminal_application_theme.dart';

Future<void> main() => runTerminalNativeHierarchyTests();

Future<void> runTerminalNativeHierarchyTests() async {
  await _testApplicationThemeProjectionLifecycle();
  await _testOsc52ConfirmationPresenterLifecycle();
  await _testSettingsInspectorPresenterLifecycle();
  await _testDiagnosticsPresenterLifecycle();
  await _testIncidentPresenterLifecycle();
  await _testUpdatePresenterLifecycle();
  await _testRtlApplicationComposition();
  await _testConfiguredWindowAndPaddingProjection();
  await _testPerWindowCreationFrameProjection();
  await _testRoleAwareWindowProjection();
  await _testInitialNativeContentLayoutProjection();
  await _testNewSplitInheritsNativeBackingScale();
  await _testDisplayRecoveryMigratesOneLogicalTabGroup();
  await _testNativeDividerGestureSynchronizesLayout();
  await _testFocusedDividerCommandsUseCellGeometry();
  await _testRepeatedMultiWindowRestoredProjection();
  await _testNativeHierarchyProjectionAndLifecycle();
  await _testRestorationPersistenceAndReopenLifecycle();
  await _testNativeTerminationReplyAndHierarchyCleanup();
}

Future<void> _testDisplayRecoveryMigratesOneLogicalTabGroup() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  late final TerminalPaneConfiguration configuration;
  configuration = TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState logicalWindow = await state.createWindow(
    configuration,
  );
  final TerminalPane secondPane = await state.splitPane(
    logicalWindow.selectedTab.focusedPaneId,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalTabState secondTab = await state.createTab(
    logicalWindow.id,
    configuration,
  );
  state.selectTab(logicalWindow.id, secondTab.id);
  final Map<PaneId, List<double>> scales = <PaneId, List<double>>{};
  final TerminalScreenPlacement originalScreen = TerminalScreenPlacement(
    displayId: 41,
    frame: TerminalWindowFrame(left: -1920, top: 0, width: 1920, height: 1080),
    visibleFrame: TerminalWindowFrame(
      left: -1920,
      top: 24,
      width: 1920,
      height: 1056,
    ),
  );
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onBackingScale: (double scale) {
        scales.putIfAbsent(pane.id, () => <double>[]).add(scale);
      },
    ),
    windowFrame: const Rect.fromLTWH(-1500, 100, 920, 580),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
    windowPlacements: <TerminalWindowId, TerminalWindowPlacement>{
      logicalWindow.id: TerminalWindowPlacement(
        windowedFrame: TerminalWindowFrame(
          left: -1500,
          top: 100,
          width: 920,
          height: 580,
        ),
        screen: originalScreen,
        fullscreen: false,
      ),
    },
  );
  const AppKitScreen destination = AppKitScreen(
    displayId: 77,
    frame: Rect.fromLTWH(0, 0, 1512, 982),
    visibleFrame: Rect.fromLTWH(0, 23, 800, 577),
  );
  try {
    adapter.reconcile();
    final Window selected = adapter.windowForTab(secondTab.id)!;
    final int handle = bindings.handleFor(selected);
    rawEvents.add(<Object?>[
      15,
      7,
      handle,
      handle >> 32,
      100000,
      0,
      true,
      destination.displayId,
      destination.frame.left,
      destination.frame.top,
      destination.frame.width,
      destination.frame.height,
      destination.visibleFrame.left,
      destination.visibleFrame.top,
      destination.visibleFrame.width,
      destination.visibleFrame.height,
    ]);
    rawEvents.add(<Object?>[15, 6, handle, handle >> 32, 100001, 0, 2.0]);
    _expect(
      selected.screen == destination && selected.backingScaleFactor == 2,
      'display recovery fixture did not update native screen/scale snapshots',
    );
    final TerminalNativeDisplayRecoveryResult result = adapter
        .recoverDisplaySet(
          fallbackScreen: const AppKitResolvedScreen(
            screen: destination,
            backingScaleFactor: 2,
          ),
        );
    final TerminalWindowPlacement migrated = adapter.placementForWindow(
      logicalWindow.id,
    );
    final Rect migratedFrame = Rect.fromLTWH(
      migrated.windowedFrame.left,
      migrated.windowedFrame.top,
      migrated.windowedFrame.width,
      migrated.windowedFrame.height,
    );
    _expect(
      result.windowCount == 1 &&
          result.migratedWindowCount == 1 &&
          result.adjustedFrameCount == 1 &&
          result.paneCount == 3 &&
          migrated.screen?.displayId == destination.displayId &&
          logicalWindow.tabIds.every(
            (TerminalTabId tabId) =>
                adapter.windowForTab(tabId)!.frame == migratedFrame,
          ) &&
          scales.values.every((List<double> values) => values.last == 2),
      'display recovery did not migrate, converge, and scale the tab group',
    );

    const AppKitResolvedScreen unrelatedAttached = AppKitResolvedScreen(
      screen: AppKitScreen(
        displayId: 99,
        frame: Rect.fromLTWH(1512, 0, 1920, 1080),
        visibleFrame: Rect.fromLTWH(1512, 24, 1920, 1056),
      ),
      backingScaleFactor: 1,
    );
    final TerminalNativeDisplayRecoveryResult unchanged = adapter
        .recoverDisplaySet(fallbackScreen: unrelatedAttached);
    _expect(
      unchanged.migratedWindowCount == 0 &&
          unchanged.adjustedFrameCount == 0 &&
          adapter.placementForWindow(logicalWindow.id) == migrated &&
          identical(state.paneForId(secondPane.id), secondPane),
      'attaching an unrelated display moved or replaced retained ownership',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testIncidentPresenterLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 920, 580),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);
  final Directory root = await Directory.systemTemp.createTemp(
    'dart-terminal-incident-presenter-test-',
  );
  final Directory reports = Directory('${root.path}/reports')..createSync();
  final Directory temporary = Directory('${root.path}/temporary')..createSync();
  File('${reports.path}/fixture.ips').writeAsStringSync(
    '${jsonEncode(<String, Object?>{'bundleID': terminalUpdateProduct, 'app_name': terminalIncidentApplicationName})}\n__INCIDENT_TEST_PRIVATE_CRASH__\n',
    flush: true,
  );
  final _RecordingIncidentStore store = _RecordingIncidentStore(
    TerminalAppleCrashReportStore(diagnosticReportsDirectory: reports),
  );
  final _PresenterIncidentProcessRunner processRunner =
      _PresenterIncidentProcessRunner();
  final TerminalIncidentController controller = TerminalIncidentController(
    service: TerminalLocalIncidentService(
      reportStore: store,
      temporaryParent: temporary,
      processRunner: processRunner,
      currentProcessId: 5150,
    ),
  );
  SavePanelResult nextSelection = SavePanelResult.cancelled();
  SavePanelConfiguration? lastConfiguration;
  var consentCount = 0;
  final TerminalIncidentPresenter presenter = TerminalIncidentPresenter(
    application: application,
    controller: controller,
    focusTarget: () =>
        TerminalIncidentFocusTarget(window: terminalWindow, view: terminalView),
    localization: TerminalLocalization.japanese,
    chooseSaveDestination: (SavePanelConfiguration configuration) {
      consentCount++;
      lastConfiguration = configuration;
      return nextSelection;
    },
  );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(
      localization: TerminalLocalization.japanese,
    ),
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.exportLatestCrashReport,
        isAvailable: () => presenter.canStart,
        handler: presenter.exportLatestCrashReport,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.captureHangSample,
        isAvailable: () => presenter.canStart,
        handler: presenter.captureHangSample,
      ),
    ],
  );
  try {
    _expect(
      dispatcher.search('クラッシュ').first.definition.id ==
              TerminalActionId.exportLatestCrashReport &&
          dispatcher.search('ハング サンプル').first.definition.id ==
              TerminalActionId.captureHangSample,
      'localized catalog does not expose both incident actions',
    );
    final TerminalActionDispatchResult cancelled = await dispatcher.dispatch(
      TerminalActionId.exportLatestCrashReport,
    );
    _expect(
      cancelled.disposition == TerminalActionDispatchDisposition.executed &&
          presenter.lastOperationResult?.disposition ==
              TerminalIncidentOperationDisposition.cancelled &&
          !presenter.isOpen &&
          consentCount == 1 &&
          store.accessCount == 0 &&
          processRunner.runCount == 0 &&
          lastConfiguration?.message.contains('スタックトレース') == true &&
          lastConfiguration?.message.contains('ファイルパス') == true &&
          lastConfiguration?.message.contains('プロセス情報') == true,
      'cancelled consent accessed raw data or omitted the localized warning',
    );

    final File crash = File('${root.path}/selected-crash.ips');
    nextSelection = SavePanelResult.selected(crash.path);
    await dispatcher.dispatch(TerminalActionId.exportLatestCrashReport);
    _expect(
      crash.readAsStringSync().contains('__INCIDENT_TEST_PRIVATE_CRASH__') &&
          store.discoverCount == 1 &&
          store.exportCount == 1 &&
          presenter.isOpen &&
          presenter.activeWindow!.title == 'ローカル障害診断' &&
          controller.status == TerminalIncidentStatus.exported &&
          controller.snapshot.matchingReportCount == 1 &&
          controller.snapshot.completedOperationCount == 1 &&
          presenter.renderedText!.contains(root.path) == false &&
          presenter.renderedText!.contains('__INCIDENT_TEST_PRIVATE_CRASH__') ==
              false,
      'consented crash export or content-free status is invalid',
    );
    final Window incidentWindow = presenter.activeWindow!;
    final int incidentWindowHandle = bindings.handleFor(incidentWindow);
    final int incidentViewHandle = bindings.handleFor(presenter.activeView!);
    final int handleCount = application.debugLiveObjectCount;
    await presenter.open();
    _expect(
      identical(presenter.activeWindow, incidentWindow) &&
          application.debugLiveObjectCount == handleCount &&
          bindings.firstResponders[incidentWindowHandle] ==
              incidentViewHandle &&
          bindings.windowKeyEventRoutings[incidentWindowHandle] == 1,
      'incident status did not retain one Dart-only native owner pair',
    );

    final File sample = File('${root.path}/selected-hang.sample.txt');
    nextSelection = SavePanelResult.selected(sample.path);
    await dispatcher.dispatch(TerminalActionId.captureHangSample);
    _expect(
      sample.readAsStringSync().contains('__INCIDENT_TEST_PRIVATE_SAMPLE__') &&
          processRunner.runCount == 1 &&
          processRunner.lastArguments?.take(4).join(',') == '5150,1,1,-file' &&
          controller.status == TerminalIncidentStatus.sampled &&
          controller.snapshot.completedOperationCount == 2 &&
          controller.snapshot.unsuccessfulOperationCount == 0 &&
          presenter.renderedText!.contains(root.path) == false &&
          presenter.renderedText!.contains(
                '__INCIDENT_TEST_PRIVATE_SAMPLE__',
              ) ==
              false &&
          lastConfiguration?.message.contains('1秒間') == true,
      'sample action leaked raw state or violated its fixed process contract',
    );

    _injectHierarchyKey(
      rawEvents,
      application,
      incidentWindowHandle,
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () => !presenter.isOpen,
      'Escape did not close incident status',
    );
    _expect(
      presenter.terminalResponderRestoreCount == 1 &&
          bindings.firstResponders[bindings.handleFor(terminalWindow)] ==
              bindings.handleFor(terminalView) &&
          !bindings.objects.containsKey(incidentWindowHandle) &&
          !bindings.objects.containsKey(incidentViewHandle),
      'incident close did not restore focus and release native owners',
    );

    final File lateSample = File('${root.path}/late.sample.txt');
    nextSelection = SavePanelResult.selected(lateSample.path);
    processRunner.delayNext = true;
    final Future<TerminalIncidentOperationResult> late = presenter
        .captureHangSample();
    await _waitForHierarchy(
      () => processRunner.waiting,
      'delayed sample did not reach the injected process boundary',
    );
    final int consentBeforeBusy = consentCount;
    final TerminalIncidentOperationResult busy = await presenter
        .exportLatestCrashReport();
    _expect(
      busy.disposition == TerminalIncidentOperationDisposition.busy &&
          consentCount == consentBeforeBusy &&
          store.accessCount == 2,
      'overlapping action bypassed single-flight before native consent',
    );
    final TerminalIncidentOperationResult? retained =
        presenter.lastOperationResult;
    await presenter.dispose();
    processRunner.release();
    final TerminalIncidentOperationResult lateResult = await late;
    _expect(
      lateResult.disposition == TerminalIncidentOperationDisposition.cancelled,
      'dispose did not classify the delayed service result as cancelled',
    );
    _expect(
      presenter.isDisposed &&
          !presenter.isOpen &&
          identical(presenter.lastOperationResult, retained) &&
          controller.status == TerminalIncidentStatus.disposed,
      'dispose accepted a late result into retained UI state',
    );
    _expect(
      !lateSample.existsSync(),
      'dispose retained a cancelled raw artifact',
    );
  } finally {
    await presenter.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

Future<void> _testUpdatePresenterLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 920, 580),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);
  final _PresenterUpdateService service = _PresenterUpdateService();
  final TerminalUpdateController controller = TerminalUpdateController(
    service: service,
  );
  final TerminalUpdatePresenter presenter = TerminalUpdatePresenter(
    controller: controller,
    focusTarget: () =>
        TerminalUpdateFocusTarget(window: terminalWindow, view: terminalView),
    localization: TerminalLocalization.japanese,
  );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(
      localization: TerminalLocalization.japanese,
    ),
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.checkForUpdates,
        handler: presenter.openAndCheck,
      ),
    ],
  );
  try {
    _expect(
      dispatcher.search('アップデート').first.definition.id ==
          TerminalActionId.checkForUpdates,
      'localized palette does not expose the shared update action',
    );
    final TerminalActionDispatchResult result = await dispatcher.dispatch(
      TerminalActionId.checkForUpdates,
    );
    _expect(
      result.disposition == TerminalActionDispatchDisposition.executed &&
          presenter.isOpen &&
          controller.status == TerminalUpdateStatus.available &&
          presenter.activeWindow!.title == 'ソフトウェアアップデート' &&
          presenter.renderedText!.contains('バージョン 0.2.0（ビルド 2）') &&
          presenter.renderedText!.contains('<b>plain text only</b>') &&
          service.checkCount == 1,
      'shared action did not project authenticated plain-text release notes',
    );
    final int updateWindowHandle = bindings.handleFor(presenter.activeWindow!);
    final int updateViewHandle = bindings.handleFor(presenter.activeView!);
    _expect(
      bindings.windowKeyEventRoutings[updateWindowHandle] == 1 &&
          bindings.firstResponders[updateWindowHandle] == updateViewHandle,
      'update presenter did not own one Dart-only read-only surface',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      updateWindowHandle,
      keyCode: 36,
      characters: '\r',
    );
    await _waitForHierarchy(
      () => controller.status == TerminalUpdateStatus.restartRequired,
      'Return did not prepare the verified candidate',
    );
    _expect(
      service.installCount == 1 &&
          presenter.renderedText!.contains('再起動して完了してください') &&
          !presenter.renderedText!.contains('https://'),
      'prepared status leaked transport metadata or did not render',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      updateWindowHandle,
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () => !presenter.isOpen,
      'Escape did not close the update presenter',
    );
    _expect(
      presenter.terminalResponderRestoreCount == 1 &&
          bindings.firstResponders[bindings.handleFor(terminalWindow)] ==
              bindings.handleFor(terminalView) &&
          !bindings.objects.containsKey(updateWindowHandle) &&
          !bindings.objects.containsKey(updateViewHandle),
      'update close did not restore focus and release native owners',
    );
  } finally {
    await presenter.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
  }
  _expect(
    service.disposeCount == 1,
    'update service ownership was not disposed exactly once',
  );
}

Future<void> _testRoleAwareWindowProjection() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  final List<_HierarchyFakeSession> sessions = <_HierarchyFakeSession>[];
  final TerminalWindowState ordinary = await state.createWindow(
    _configuration(sessions),
  );
  final TerminalWindowState quick = await state.createWindow(
    _configuration(sessions),
    role: TerminalWindowRole.quickTerminal,
  );
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
    ),
    windowFrame: const Rect.fromLTWH(100, 90, 920, 580),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    windowConfigurationBuilder: (TerminalWindowState window) =>
        window.role == TerminalWindowRole.quickTerminal
        ? const WindowConfiguration(
            titled: false,
            closable: false,
            miniaturizable: false,
            resizable: false,
          )
        : terminalWindowConfiguration,
    automaticPresentationPolicy: (TerminalWindowState window) =>
        window.role == TerminalWindowRole.standard,
  );
  try {
    adapter.reconcile();
    final Window ordinaryNative = adapter.windowForTab(ordinary.selectedTabId)!;
    final Window quickNative = adapter.windowForTab(quick.selectedTabId)!;
    final int ordinaryHandle = bindings.handleFor(ordinaryNative);
    final int quickHandle = bindings.handleFor(quickNative);
    _expect(
      ordinaryNative.configuration == terminalWindowConfiguration &&
          quickNative.configuration ==
              const WindowConfiguration(
                titled: false,
                closable: false,
                miniaturizable: false,
                resizable: false,
              ) &&
          bindings.windowShowCounts[ordinaryHandle] == 1 &&
          bindings.windowShowCounts[quickHandle] == null,
      'logical roles select native style and automatic presentation policy',
    );

    const Rect moved = Rect.fromLTWH(-720, 420, 640, 480);
    adapter.updateWindowedFrame(quick.id, moved);
    _expect(
      quickNative.frame == moved &&
          adapter.placementForWindow(quick.id).windowedFrame ==
              TerminalWindowFrame(
                left: -720,
                top: 420,
                width: 640,
                height: 480,
              ),
      'custom presentation geometry updates native and authoritative frames',
    );
    adapter.present();
    _expect(
      bindings.windowShowCounts[ordinaryHandle] == 2 &&
          bindings.windowShowCounts[quickHandle] == null,
      'generic reopen presentation excludes product-managed windows',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testFocusedDividerCommandsUseCellGeometry() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState window = await state.createWindow(configuration);
  final TerminalTabState tab = window.selectedTab;
  final PaneId firstPane = tab.focusedPaneId;
  final TerminalPane second = await state.splitPane(
    firstPane,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalPane third = await state.splitPane(
    second.id,
    configuration,
    axis: TerminalSplitAxis.vertical,
  );
  final TerminalPane fourth = await state.splitPane(
    third.id,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final TerminalSplitBranch root = tab.splitTree.root as TerminalSplitBranch;
  final TerminalSplitBranch vertical = root.second as TerminalSplitBranch;
  final TerminalSplitBranch inner = vertical.second as TerminalSplitBranch;
  final Map<PaneId, TerminalPaneLayoutRect> layouts =
      <PaneId, TerminalPaneLayoutRect>{};
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onLayout: (TerminalPaneLayoutRect? rectangle, {required bool visible}) {
        if (visible) layouts[pane.id] = rectangle!;
      },
    ),
    windowFrame: const Rect.fromLTWH(100, 90, 801, 481),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
  );
  try {
    adapter.reconcile();
    final double initialFirstWidth = layouts[firstPane]!.width;
    final double initialThirdWidth = layouts[third.id]!.width;
    final double initialFourthWidth = layouts[fourth.id]!.width;
    _expect(
      adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.right) &&
          adapter.moveFocusedDivider(TerminalSplitDividerDirection.right),
      'focused pane did not expose its nearest horizontal divider',
    );
    adapter.reconcile();
    _expect(
      layouts[firstPane]!.width == initialFirstWidth &&
          layouts[third.id]!.width == initialThirdWidth + 8 &&
          layouts[fourth.id]!.width == initialFourthWidth - 8,
      'right command did not move only the nearest horizontal divider by '
      'one cell',
    );

    final double initialSecondHeight = layouts[second.id]!.height;
    final double initialThirdHeight = layouts[third.id]!.height;
    _expect(
      adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.down) &&
          adapter.moveFocusedDivider(TerminalSplitDividerDirection.down),
      'focused pane did not expose its nearest vertical divider',
    );
    adapter.reconcile();
    _expect(
      layouts[second.id]!.height == initialSecondHeight + 16 &&
          layouts[third.id]!.height == initialThirdHeight - 16 &&
          layouts[fourth.id]!.height == initialThirdHeight - 16,
      'down command did not move the nearest vertical divider by one cell',
    );

    state.resizeSplit(tab.id, inner.id, 0.000001);
    adapter.reconcile();
    _expect(
      !adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.left) &&
          !adapter.moveFocusedDivider(TerminalSplitDividerDirection.left) &&
          adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.right),
      'horizontal command did not stop at the descendant minimum extent',
    );
    state.resizeSplit(tab.id, inner.id, 0.999999);
    adapter.reconcile();
    _expect(
      !adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.right) &&
          adapter.canMoveFocusedDivider(TerminalSplitDividerDirection.left),
      'horizontal command did not clamp at the opposite descendant minimum',
    );
    state.setPaneZoom(tab.id, fourth.id);
    adapter.reconcile();
    _expect(
      TerminalSplitDividerDirection.values.every(
        (TerminalSplitDividerDirection direction) =>
            !adapter.canMoveFocusedDivider(direction),
      ),
      'divider commands remained available while split dividers were hidden',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testNativeDividerGestureSynchronizesLayout() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState window = await state.createWindow(configuration);
  final TerminalTabId tabId = window.selectedTabId;
  await state.splitPane(
    window.selectedTab.focusedPaneId,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  final Map<PaneId, TerminalPaneLayoutRect> layouts =
      <PaneId, TerminalPaneLayoutRect>{};
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onLayout: (TerminalPaneLayoutRect? rectangle, {required bool visible}) {
        if (visible) layouts[pane.id] = rectangle!;
      },
    ),
    windowFrame: const Rect.fromLTWH(100, 90, 801, 480),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
  );
  var reconciliations = 0;
  final TerminalNativeSplitDividerGestureController gestures =
      TerminalNativeSplitDividerGestureController(
        hierarchy: adapter,
        reconcile: () {
          reconciliations++;
          adapter.reconcile();
        },
      );
  try {
    adapter.reconcile();
    final TerminalSplitNodeId rootId = window.selectedTab.splitTree.root.id;
    final TwoPaneSplitView split = adapter.splitViewForNode(rootId)!;
    final int splitHandle = bindings.handleFor(split);
    final PaneId firstPane = window.selectedTab.paneIds.first;
    final PaneId secondPane = window.selectedTab.paneIds.last;
    final TerminalPaneLayoutRect initialFirst = layouts[firstPane]!;
    final TerminalPaneLayoutRect initialSecond = layouts[secondPane]!;
    final double dividerX = initialFirst.left + initialFirst.width;

    _expect(
      gestures.route(
        tabId,
        _hierarchyMouse(AppKitMouseEventKind.down, x: dividerX, y: 20),
      ),
      'left mouse down on the native divider was not consumed',
    );
    bindings.splitViewFractions[splitHandle] = 0.75;
    _expect(
      gestures.route(
        tabId,
        _hierarchyMouse(AppKitMouseEventKind.dragged, x: 600, y: 20),
      ),
      'active native divider drag was not consumed',
    );
    final TerminalSplitBranch resized =
        window.selectedTab.splitTree.root as TerminalSplitBranch;
    _expect(
      resized.fraction == 0.75 &&
          reconciliations == 1 &&
          layouts[firstPane]!.width > initialFirst.width &&
          layouts[secondPane]!.width < initialSecond.width &&
          layouts[firstPane]!.height == initialFirst.height &&
          layouts[secondPane]!.height == initialSecond.height,
      'native drag fraction did not persist and relayout both panes without '
      'changing the orthogonal cell geometry',
    );

    bindings.splitViewFractions[splitHandle] = 0.7;
    _expect(
      gestures.route(
            tabId,
            _hierarchyMouse(AppKitMouseEventKind.up, x: 560, y: 20),
          ) &&
          reconciliations == 2 &&
          !gestures.hasActiveGesture &&
          (window.selectedTab.splitTree.root as TerminalSplitBranch).fraction ==
              0.7,
      'mouse up did not commit the final constrained fraction and end drag',
    );
    _expect(
      !gestures.route(
            tabId,
            _hierarchyMouse(AppKitMouseEventKind.dragged, x: 400, y: 20),
          ) &&
          !gestures.route(
            tabId,
            _hierarchyMouse(AppKitMouseEventKind.down, x: 20, y: 20),
          ),
      'ordinary terminal mouse events were mistaken for divider gestures',
    );
  } finally {
    gestures.dispose();
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

AppKitMouseEvent _hierarchyMouse(
  AppKitMouseEventKind kind, {
  required double x,
  required double y,
}) => AppKitMouseEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  x: x,
  y: y,
  button: 0,
  modifiers: const ModifierKeys(0),
  clickCount: 1,
);

Future<void> _testNewSplitInheritsNativeBackingScale() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  late final TerminalPaneConfiguration configuration;
  configuration = TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState logicalWindow = await state.createWindow(
    configuration,
  );
  final Map<PaneId, List<double>> scales = <PaneId, List<double>>{};
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onBackingScale: (double scale) {
        scales.putIfAbsent(pane.id, () => <double>[]).add(scale);
      },
    ),
    windowFrame: const Rect.fromLTWH(100, 90, 920, 580),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
  );
  try {
    adapter.reconcile();
    final TerminalTabId tabId = logicalWindow.selectedTabId;
    final Window nativeWindow = adapter.windowForTab(tabId)!;
    final int handle = bindings.handleFor(nativeWindow);
    rawEvents.add(<Object?>[3, 6, handle, handle >> 32, 300000, 0, 2.0]);
    _expect(
      nativeWindow.backingScaleFactor == 2,
      'native window did not cache the injected Retina scale',
    );

    final TerminalPane added = await state.splitPane(
      logicalWindow.selectedTab.focusedPaneId,
      configuration,
      axis: TerminalSplitAxis.horizontal,
    );
    adapter.reconcile();
    final PaneId retained = logicalWindow.selectedTab.paneIds.first;
    _expect(
      scales[retained]!.last == 2 &&
          scales[added.id]!.length == 1 &&
          scales[added.id]!.single == 2,
      'new split did not receive the owning window Retina scale on its first '
      'layout',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testOsc52ConfirmationPresenterLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 640, 480),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);
  final _NativeOsc52Clipboard clipboard = _NativeOsc52Clipboard('seed');
  final List<Uint8List> replies = <Uint8List>[];
  late final TerminalOsc52ConfirmationPresenter presenter;
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
    onPendingChanged: (TerminalOsc52PendingRequest? pending) {
      unawaited(
        pending == null ? presenter.dismiss() : presenter.show(pending),
      );
    },
  );
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: PaneId(701),
    generation: 1,
  );
  final TerminalOsc52SessionProjection projection = coordinator.registerSession(
    sessionId: sessionId,
    readPolicy: TerminalConfiguredClipboardAccess.ask,
    writePolicy: TerminalConfiguredClipboardAccess.ask,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  coordinator.focusSession(sessionId);
  presenter = TerminalOsc52ConfirmationPresenter(
    focusTarget: () => TerminalOsc52ConfirmationFocusTarget(
      window: terminalWindow,
      view: terminalView,
    ),
    approve: coordinator.approve,
    deny: coordinator.deny,
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onOsc52Request: projection.handle,
  );
  final VtParser parser = VtParser(sink: sink);
  try {
    const String requestedText = 'line\n\u202e';
    parser.parse(
      _nativeOsc52('52;c;${base64Encode(utf8.encode(requestedText))}'),
    );
    await _waitForHierarchy(
      () => presenter.isOpen && bindings.objects.length == 4,
      'OSC 52 write confirmation did not acquire bounded native owners',
    );
    final String rendered = presenter.renderedText!;
    _expect(
      rendered.contains('Selection: "c"') &&
          rendered.contains('Operation: Write clipboard') &&
          rendered.contains('"line\\n\\u202e"') &&
          !rendered.contains('\u202e'),
      'OSC 52 confirmation did not render exact spoof-safe request text',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      bindings.handleFor(presenter.activeWindow!),
      keyCode: 36,
      characters: '\r',
    );
    await _waitForHierarchy(
      () =>
          coordinator.pendingRequest == null &&
          !presenter.isOpen &&
          clipboard.text == requestedText &&
          bindings.objects.length == 2,
      'Return did not approve exactly one request and release native owners',
    );
    _expect(
      presenter.terminalResponderRestoreCount == 1 &&
          bindings.firstResponders[bindings.handleFor(terminalWindow)] ==
              bindings.handleFor(terminalView),
      'OSC 52 approval did not restore the live terminal responder',
    );

    parser.parse(_nativeOsc52('52;c;?'));
    await _waitForHierarchy(
      () => presenter.isOpen,
      'OSC 52 read confirmation did not open',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      bindings.handleFor(presenter.activeWindow!),
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () =>
          coordinator.pendingRequest == null &&
          !presenter.isOpen &&
          replies.length == 1,
      'Escape did not deny the exact read and release native owners',
    );
    _expect(
      ascii.decode(replies.single) == '\x1b]52;c;\x07' &&
          clipboard.readCount == 0 &&
          presenter.terminalResponderRestoreCount == 2,
      'OSC 52 read denial accessed data or omitted its unavailable reply',
    );
  } finally {
    projection.close();
    coordinator.dispose();
    await presenter.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testSettingsInspectorPresenterLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final _SettingsMemoryFileSystem fileSystem = _SettingsMemoryFileSystem(
    const <String, String>{'/settings.conf': 'font-size = 15\n'},
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(
    fileSystem: fileSystem,
  );
  const List<String> configurationArguments = <String>[
    '--config=/settings.conf',
  ];
  final TerminalConfigSnapshot initial = loader
      .resolve(configurationArguments, environment: const <String, String>{})
      .snapshot;
  final TerminalConfigReloadController reloadController =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => loader.resolve(
          configurationArguments,
          environment: const <String, String>{},
        ),
      );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 640, 480),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);
  late final TerminalCommandPalettePresenter palette;
  late final TerminalSettingsInspectorPresenter settings;
  final TerminalActionCatalog catalog = TerminalActionCatalog.standard();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.openCommandPalette,
        handler: () => palette.open(),
      ),
      TerminalActionRegistration(
        id: TerminalActionId.openSettings,
        handler: () => settings.open(),
      ),
      TerminalActionRegistration(
        id: TerminalActionId.reloadConfiguration,
        handler: () async {
          final TerminalConfigReloadResult result = await reloadController
              .reload();
          if (result.disposition == TerminalConfigReloadDisposition.failed) {
            Error.throwWithStackTrace(result.error!, result.stackTrace!);
          }
        },
      ),
    ],
  );
  palette = TerminalCommandPalettePresenter(
    dispatcher: dispatcher,
    terminalWindow: terminalWindow,
    terminalView: terminalView,
  );
  settings = TerminalSettingsInspectorPresenter(
    controller: reloadController,
    documentSession: TerminalSettingsDocumentSession(
      loader: loader,
      arguments: configurationArguments,
      environment: const <String, String>{},
      writer: fileSystem,
    ),
    focusTarget: () => TerminalSettingsInspectorFocusTarget(
      window: terminalWindow,
      view: terminalView,
    ),
    reload: () => dispatcher.dispatch(TerminalActionId.reloadConfiguration),
    runtimeStatus: () => 'Quick Terminal shortcut: disabled',
  );
  try {
    _expect(
      (await dispatcher.dispatch(TerminalActionId.openCommandPalette))
              .disposition ==
          TerminalActionDispatchDisposition.executed,
      'shared command-palette action did not open under fake AppKit',
    );
    palette
      ..refresh()
      ..state.setQuery('settings')
      ..refresh();
    final Window paletteWindow = palette.activeWindow!;
    _injectHierarchyKey(
      rawEvents,
      application,
      bindings.handleFor(paletteWindow),
      keyCode: 36,
      characters: '\r',
    );
    await _waitForHierarchy(
      () => settings.isOpen && !palette.isOpen,
      'command palette did not transfer ownership to Settings',
    );
    final Window settingsWindow = settings.activeWindow!;
    final TextEditor settingsView = settings.activeView!;
    final TwoPaneSplitView rootSplit = settings.activeRootSplit!;
    final TwoPaneSplitView editorStatusSplit =
        settings.activeEditorStatusSplit!;
    final int settingsWindowHandle = bindings.handleFor(settingsWindow);
    final int settingsViewHandle = bindings.handleFor(settingsView);
    final int statusViewHandle = bindings.handleFor(settings.activeStatusView!);
    final int detailViewHandle = bindings.handleFor(settings.activeDetailView!);
    final int rootSplitHandle = bindings.handleFor(rootSplit);
    final int editorStatusSplitHandle = bindings.handleFor(editorStatusSplit);
    _expect(
      settings.activeStatusView!.text.contains(
        'Quick Terminal shortcut: disabled',
      ),
      'Settings did not surface bounded product runtime status',
    );
    final List<NativeTextEditorStyleRun> normalStyles =
        List<NativeTextEditorStyleRun>.from(
          bindings.textEditorStyleRuns[settingsViewHandle]!,
        );
    final TerminalSettingsOptionOccurrence disabled = settings.state.occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option.name == 'working-directory',
        );
    final List<TerminalSettingsSyntaxSpan> disabledSpans = settings
        .state
        .syntaxSpans
        .where(
          (TerminalSettingsSyntaxSpan span) =>
              span.start < disabled.lineEnd && span.end > disabled.lineStart,
        )
        .toList(growable: false);
    final NativeTextEditorLineHighlight? initialLineHighlight =
        bindings.textEditorLineHighlights[settingsViewHandle];
    _expect(
      palette.terminalResponderRestoreCount == 0 &&
          bindings.firstResponders[settingsWindowHandle] ==
              settingsViewHandle &&
          bindings.windowTitles[settingsWindowHandle] == 'settings.conf' &&
          bindings.contentViews[settingsWindowHandle] == rootSplitHandle &&
          bindings.splitViewAxes[rootSplitHandle] == 0 &&
          bindings.splitViewAxes[editorStatusSplitHandle] == 1 &&
          bindings.splitViewChildren[rootSplitHandle]!.first ==
              editorStatusSplitHandle &&
          bindings
                  .textViewConfigurations[statusViewHandle]!
                  .view
                  .acceptsFirstResponder ==
              false &&
          bindings
                  .textViewConfigurations[detailViewHandle]!
                  .view
                  .acceptsFirstResponder ==
              false &&
          settings.state.occurrences.length == 47 &&
          settings.state.syntaxSpans.isNotEmpty &&
          disabled.isCommented &&
          disabledSpans.length == 1 &&
          disabledSpans.single.kind == TerminalSettingsSyntaxKind.comment &&
          disabledSpans.single.start == disabled.lineStart &&
          disabledSpans.single.end == disabled.lineEnd &&
          bindings.texts[settingsViewHandle] == settings.state.text &&
          bindings.textEditorSelectionStarts[settingsViewHandle] ==
              settings.state.selection.start &&
          normalStyles.isNotEmpty &&
          initialLineHighlight?.location == settings.state.selection.start &&
          initialLineHighlight?.red == terminalSettingsCurrentLineColor.red &&
          initialLineHighlight?.green ==
              terminalSettingsCurrentLineColor.green &&
          initialLineHighlight?.blue == terminalSettingsCurrentLineColor.blue &&
          bindings.textEditorSelectionRevealCounts[settingsViewHandle] == 0 &&
          settings.activeStatusView!.text.contains('NORMAL') &&
          settings.activeDetailView!.text.contains('Current value') &&
          !settings.renderedText!.contains('Config Lens') &&
          !settings.renderedText!.contains('SOURCE') &&
          bindings.objects.length == 8,
      'Settings did not publish the initial document before key input',
    );

    final int initialCaret = settings.state.selection.start;
    final int initialRevealCount =
        bindings.textEditorSelectionRevealCounts[settingsViewHandle]!;
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 125,
      characters: '',
    );
    await _waitForHierarchy(
      () =>
          settings.state.selection.start != initialCaret &&
          bindings.textEditorLineHighlights[settingsViewHandle]?.location ==
              settings.state.selection.start &&
          bindings.textEditorSelectionRevealCounts[settingsViewHandle] ==
              initialRevealCount + 1,
      'NORMAL navigation did not move and reveal the current-line highlight',
    );

    final Window firstSettingsWindow = settingsWindow;
    _expect(
      (await dispatcher.dispatch(TerminalActionId.openSettings)).disposition ==
              TerminalActionDispatchDisposition.executed &&
          identical(settings.activeWindow, firstSettingsWindow) &&
          bindings.objects.length == 8,
      'reopening Settings created a duplicate native owner',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 44,
      characters: '/',
    );
    final int beforeSearchRevealCount =
        bindings.textEditorSelectionRevealCounts[settingsViewHandle]!;
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 3,
      characters: 'font-size',
    );
    await _waitForHierarchy(
      () =>
          settings.state.query == 'font-size' &&
          settings.state.selectedOccurrence?.option.name == 'font-size' &&
          bindings.textEditorLineHighlights[settingsViewHandle]?.location ==
              settings.state.selection.start &&
          bindings.textEditorSelectionRevealCounts[settingsViewHandle]! >
              beforeSearchRevealCount,
      'explicit Settings search was not routed through its native window',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 36,
      characters: '\r',
    );
    await _waitForHierarchy(
      () => settings.state.mode == TerminalSettingsEditorMode.normal,
      'Settings search did not commit back to NORMAL',
    );
    final List<TerminalSettingsSyntaxSpan> normalSyntax =
        settings.state.syntaxSpans;
    final int normalRevealCount =
        bindings.textEditorSelectionRevealCounts[settingsViewHandle]!;
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 34,
      characters: 'i',
    );
    await _waitForHierarchy(
      () =>
          settings.state.mode == TerminalSettingsEditorMode.insert &&
          bindings.textEditorEditable[settingsViewHandle] == true &&
          bindings.windowKeyEventRoutings[settingsWindowHandle] == 0,
      'Settings did not enter native INSERT routing on the same surface',
    );
    _expect(
      identical(normalSyntax, settings.state.syntaxSpans) &&
          _sameNativeTextEditorStyles(
            normalStyles,
            bindings.textEditorStyleRuns[settingsViewHandle]!,
          ) &&
          bindings.textEditorLineHighlights[settingsViewHandle]?.location ==
              settings.state.selection.start &&
          bindings.textEditorSelectionRevealCounts[settingsViewHandle] ==
              normalRevealCount,
      'NORMAL to INSERT changed styles/highlight or requested native reveal',
    );

    final String invalidText = bindings.texts[settingsViewHandle]!.replaceFirst(
      'font-size = 15',
      'font-size = enormous',
    );
    final int invalidCaret = invalidText.indexOf('enormous');
    bindings
      ..texts[settingsViewHandle] = invalidText
      ..textEditorSelectionStarts[settingsViewHandle] = invalidCaret
      ..textEditorSelectionLengths[settingsViewHandle] = 0;
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 7,
      characters: 'x',
    );
    await _waitForHierarchy(
      () =>
          settings.state.text == invalidText &&
          bindings.textEditorLineHighlights[settingsViewHandle]?.location ==
              invalidCaret &&
          bindings.textEditorSelectionRevealCounts[settingsViewHandle] ==
              normalRevealCount,
      'native INSERT text was not synchronized into the Settings draft',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 1,
      characters: 's',
      modifiers: ModifierKeys.commandBit,
    );
    await _waitForHierarchy(
      () =>
          settings.saveRequestCount == 1 &&
          settings.state.saveState == TerminalSettingsSaveState.invalid,
      'invalid Settings Command-S did not finish validation once',
    );
    _expect(
      settings.lastSaveResult?.disposition ==
              TerminalSettingsDocumentSaveDisposition.rejected &&
          settings.reloadRequestCount == 0 &&
          reloadController.acceptedGeneration == 0 &&
          fileSystem.readText('/settings.conf') == 'font-size = 15\n' &&
          bindings.textEditorStyleRuns[settingsViewHandle]!.any(
            (NativeTextEditorStyleRun run) => run.underlineStyle == 1,
          ) &&
          settings.activeDetailView!.text.contains('Fix:'),
      'invalid Settings draft was not underlined or was persisted/reloaded',
    );

    final String editedText = bindings.texts[settingsViewHandle]!.replaceFirst(
      'font-size = enormous',
      'font-size = 19',
    );
    final int editedCaret = editedText.indexOf('19');
    bindings
      ..texts[settingsViewHandle] = editedText
      ..textEditorSelectionStarts[settingsViewHandle] = editedCaret
      ..textEditorSelectionLengths[settingsViewHandle] = 0;
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 7,
      characters: 'x',
    );
    await _waitForHierarchy(
      () => settings.state.text == editedText,
      'corrected native INSERT text was not synchronized into the draft',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 1,
      characters: 's',
      modifiers: ModifierKeys.commandBit,
    );
    await _waitForHierarchy(
      () =>
          settings.saveRequestCount == 2 &&
          settings.reloadRequestCount == 1 &&
          reloadController.acceptedGeneration == 1,
      'corrected Settings Command-S did not persist and reload once',
    );
    _expect(
      settings.lastReloadResult?.id == TerminalActionId.reloadConfiguration &&
          settings.lastReloadResult?.disposition ==
              TerminalActionDispatchDisposition.executed &&
          settings.lastSaveResult?.isSaved == true &&
          fileSystem.readText('/settings.conf').contains('font-size = 19') &&
          reloadController.effectiveSnapshot.value(
                TerminalProductConfigSchema.fontSize,
              ) ==
              19 &&
          settings.state.saveState == TerminalSettingsSaveState.saved &&
          settings.activeDetailView!.text.contains('19'),
      'Settings did not persist and refresh the accepted controller snapshot',
    );

    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () =>
          settings.state.mode == TerminalSettingsEditorMode.normal &&
          bindings.textEditorEditable[settingsViewHandle] == false &&
          bindings.windowKeyEventRoutings[settingsWindowHandle] == 1,
      'Settings Escape did not return INSERT to NORMAL',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 30,
      characters: ']',
    );
    await _waitForHierarchy(
      () =>
          !settings.state.detailsExpanded &&
          bindings.splitViewFractions[rootSplitHandle] == 0.965,
      'Settings did not collapse detail into its visible edge rail',
    );
    _expect(
      settings.activeDetailView!.text.startsWith('›') &&
          settings.activeDetailView!.text.contains('D\nE\nT\nA\nI\nL'),
      'collapsed Settings detail did not retain a discoverable rail',
    );
    final String retainedDraft = settings.state.text;
    final TerminalSettingsTextSelection retainedSelection =
        settings.state.selection;
    final TextEditor standardEditor = settings.activeView!;
    final TextView standardStatus = settings.activeStatusView!;
    final TextView standardDetail = settings.activeDetailView!;
    final TwoPaneSplitView standardEditorStatus =
        settings.activeEditorStatusSplit!;
    final TwoPaneSplitView standardRoot = settings.activeRootSplit!;
    _expect(
      settings.updateAccessibilityPresentation(
        const TerminalAccessibilityPresentation(
          reduceMotion: false,
          increaseContrast: true,
          differentiateWithoutColor: true,
        ),
      ),
      'Settings did not accept a live accessibility presentation change',
    );
    final int accessibleEditorHandle = bindings.handleFor(settings.activeView!);
    final int accessibleRootHandle = bindings.handleFor(
      settings.activeRootSplit!,
    );
    _expect(
      identical(settings.activeWindow, settingsWindow) &&
          settings.state.text == retainedDraft &&
          settings.state.selection == retainedSelection &&
          settings.state.mode == TerminalSettingsEditorMode.normal &&
          settings.activeView!.configuration ==
              terminalSettingsHighContrastPresentation.editorConfiguration &&
          settings.activeStatusView!.configuration ==
              terminalSettingsHighContrastPresentation.statusConfiguration &&
          settings.activeDetailView!.configuration ==
              terminalSettingsHighContrastPresentation.detailConfiguration &&
          settings.activeView!.lineHighlight?.color ==
              terminalSettingsHighContrastPresentation.currentLineColor &&
          bindings.contentViews[settingsWindowHandle] == accessibleRootHandle &&
          bindings.splitViewFractions[accessibleRootHandle] == 0.965 &&
          bindings.firstResponders[settingsWindowHandle] ==
              accessibleEditorHandle &&
          standardEditor.isDisposed &&
          standardStatus.isDisposed &&
          standardDetail.isDisposed &&
          standardEditorStatus.isDisposed &&
          standardRoot.isDisposed &&
          bindings.objects.length == 8,
      'live high-contrast replacement did not retain the Settings window, '
      'draft, selection, mode, detail state, focus, or bounded ownership',
    );
    _injectHierarchyKey(
      rawEvents,
      application,
      settingsWindowHandle,
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () => !settings.isOpen && bindings.objects.length == 2,
      'Settings Escape did not release every native editor/detail owner',
    );
    _expect(
      settings.terminalResponderRestoreCount == 1 &&
          bindings.firstResponders[bindings.handleFor(terminalWindow)] ==
              bindings.handleFor(terminalView),
      'closing Settings did not restore the live terminal first responder',
    );
  } finally {
    await settings.dispose();
    await palette.dispose();
    reloadController.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testDiagnosticsPresenterLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 640, 480),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);

  final TerminalScreenSet firstScreens = TerminalScreenSet(rows: 3, columns: 8);
  final TerminalScreenParserSink firstSink =
      TerminalScreenParserSink.forScreenSet(firstScreens);
  final VtParserInspector firstInspector = VtParserInspector(
    downstream: firstSink,
    captureEnabled: false,
  );
  final TerminalScreenSet secondScreens = TerminalScreenSet(
    rows: 4,
    columns: 10,
  );
  final TerminalScreenParserSink secondSink =
      TerminalScreenParserSink.forScreenSet(secondScreens);
  final VtParserInspector secondInspector = VtParserInspector(
    downstream: secondSink,
    captureEnabled: false,
  );
  TerminalDiagnosticsFocusTarget target(
    String identity,
    VtParserInspector inspector,
    TerminalScreenParserSink sink,
  ) => TerminalDiagnosticsFocusTarget(
    identity: identity,
    window: terminalWindow,
    view: terminalView,
    isLive: () => true,
    beginCapture: (VtParserInspectionObserver observer) {
      inspector.beginCapture(onEvent: observer);
    },
    endCapture: inspector.endCapture,
    snapshot: () => _diagnosticsPresenterSnapshot(inspector, sink),
  );

  TerminalDiagnosticsFocusTarget active = target(
    'first',
    firstInspector,
    firstSink,
  );
  final _DiagnosticsMemoryFiles files = _DiagnosticsMemoryFiles();
  final TerminalDiagnosticsPresenter presenter = TerminalDiagnosticsPresenter(
    application: application,
    focusTarget: () => active,
    localization: TerminalLocalization.japanese,
    writer: TerminalDiagnosticsAtomicWriter(files: files),
  );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(
      localization: TerminalLocalization.japanese,
    ),
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.openTerminalInspector,
        handler: presenter.open,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.exportDiagnostics,
        handler: () async {
          await presenter.export();
        },
      ),
    ],
  );
  try {
    _expect(
      dispatcher.search('インスペクタ').first.definition.id ==
              TerminalActionId.openTerminalInspector &&
          dispatcher.search('診断 書き出す').first.definition.id ==
              TerminalActionId.exportDiagnostics,
      'localized Command Palette search does not expose both shared actions',
    );
    _expect(
      (await dispatcher.dispatch(TerminalActionId.openTerminalInspector))
                  .disposition ==
              TerminalActionDispatchDisposition.executed &&
          presenter.isOpen &&
          presenter.captureHandoffCount == 1 &&
          presenter.capturedTargetIdentity == 'first' &&
          firstInspector.captureEnabled &&
          presenter.activeWindow!.title == 'ターミナルインスペクタ' &&
          presenter.renderedText!.contains('"format":') &&
          presenter.renderedText!.contains('Escで閉じる'),
      'shared action did not open one localized read-only inspector',
    );
    final int inspectorWindowHandle = bindings.handleFor(
      presenter.activeWindow!,
    );
    final int inspectorViewHandle = bindings.handleFor(presenter.activeView!);
    _expect(
      bindings.firstResponders[inspectorWindowHandle] == inspectorViewHandle &&
          bindings.windowKeyEventRoutings[inspectorWindowHandle] == 1,
      'inspector did not own its Dart-only keyboard surface',
    );

    firstInspector.execute(0x07);
    await Future<void>.delayed(Duration.zero);
    _expect(
      presenter.renderedText!.contains('"events_total": 1'),
      'parser notifications did not coalesce into an immutable refresh',
    );
    active = target('second', secondInspector, secondSink);
    presenter.synchronizeFocus();
    _expect(
      presenter.captureHandoffCount == 2 &&
          presenter.capturedTargetIdentity == 'second' &&
          !firstInspector.captureEnabled &&
          firstInspector.snapshot().events.isEmpty &&
          secondInspector.captureEnabled,
      'focus handoff did not clear the previous capture before enabling next',
    );

    bindings.savePanelResult =
        const NativeValueResult<NativeSavePanelResult>.success(
          NativeSavePanelResult.cancelled(),
        );
    await dispatcher.dispatch(TerminalActionId.exportDiagnostics);
    _expect(
      presenter.lastExportResult?.disposition ==
              TerminalDiagnosticsPresentationExportDisposition.cancelled &&
          presenter.lastExportResult!.isSuccess &&
          files.destinations.isEmpty,
      'save-panel cancellation was not a successful no-write outcome',
    );
    bindings.savePanelResult =
        const NativeValueResult<NativeSavePanelResult>.success(
          NativeSavePanelResult.selected('/tmp/terminal-diagnostics.json'),
        );
    await dispatcher.dispatch(TerminalActionId.exportDiagnostics);
    final Uint8List written =
        files.destinations['/tmp/terminal-diagnostics.json']!;
    _expect(
      presenter.lastExportResult?.disposition ==
              TerminalDiagnosticsPresentationExportDisposition.written &&
          presenter.lastExportResult?.byteCount == written.length &&
          utf8.decode(written).contains('"capture_enabled": true') &&
          bindings.lastSavePanelConfiguration?.title == '診断情報を書き出す' &&
          bindings.lastSavePanelConfiguration?.defaultFileName ==
              'dart-terminal-diagnostics.json' &&
          bindings.lastSavePanelConfiguration?.allowedFileExtension == 'json' &&
          files.temporaryFiles.isEmpty,
      'localized save panel did not feed one bounded atomic JSON write',
    );
    files.failReplace = true;
    await presenter.export();
    _expect(
      presenter.lastExportResult?.disposition ==
              TerminalDiagnosticsPresentationExportDisposition.writeFailure &&
          files.temporaryFiles.isEmpty,
      'atomic writer failure was not cleaned and classified without a path',
    );
    files.failReplace = false;
    bindings.savePanelResult =
        const NativeValueResult<NativeSavePanelResult>.failure(9, 'injected');
    await presenter.export();
    _expect(
      presenter.lastExportResult?.disposition ==
          TerminalDiagnosticsPresentationExportDisposition.nativeFailure,
      'native save failure did not remain path-free and classified',
    );

    _injectHierarchyKey(
      rawEvents,
      application,
      inspectorWindowHandle,
      keyCode: 53,
      characters: '\u001b',
    );
    await _waitForHierarchy(
      () => !presenter.isOpen,
      'Escape did not close the diagnostics inspector',
    );
    _expect(
      !secondInspector.captureEnabled &&
          secondInspector.snapshot().events.isEmpty &&
          presenter.terminalResponderRestoreCount == 1 &&
          bindings.firstResponders[bindings.handleFor(terminalWindow)] ==
              bindings.handleFor(terminalView) &&
          !bindings.objects.containsKey(inspectorWindowHandle) &&
          !bindings.objects.containsKey(inspectorViewHandle),
      'close did not clear capture, restore terminal focus, or release owners',
    );
  } finally {
    await presenter.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
  }
}

TerminalDiagnosticsSnapshot _diagnosticsPresenterSnapshot(
  VtParserInspector inspector,
  TerminalScreenParserSink sink,
) => TerminalDiagnosticsSnapshot(
  application: TerminalDiagnosticsApplicationSnapshot(
    runtimeKind: TerminalDiagnosticsRuntimeKind.developerJit,
    appKitEventProtocol: 14,
    language: TerminalDiagnosticsLanguage.japanese,
    direction: TerminalDiagnosticsDirection.leftToRight,
    reduceMotion: false,
    increaseContrast: false,
    differentiateWithoutColor: false,
  ),
  hierarchy: TerminalDiagnosticsHierarchySnapshot(
    windowCount: 1,
    tabCount: 1,
    paneCount: 1,
    livePaneCount: 1,
    activeWindowRole: TerminalDiagnosticsWindowRole.standard,
  ),
  focusedPane: TerminalDiagnosticsFocusedPaneSnapshot.unavailable(),
  parser: TerminalDiagnosticsParserSnapshot.capture(
    inspector: inspector,
    sink: sink,
  ),
  renderer: TerminalDiagnosticsRendererSnapshot.unavailable(),
  configuration: TerminalDiagnosticsConfigurationSnapshot(
    schemaOptionCount: 47,
    effectiveGeneration: 0,
    attemptGeneration: 0,
    warningCount: 0,
    errorCount: 0,
    liveOptionCount: 11,
    newSessionOptionCount: 36,
  ),
  features: TerminalDiagnosticsFeaturesSnapshot(
    secureInput: TerminalDiagnosticsFeatureState.disabled,
    quickWindowShortcut: TerminalDiagnosticsFeatureState.disabled,
    notifications: TerminalDiagnosticsFeatureState.disabled,
    appIntents: TerminalDiagnosticsFeatureState.disabled,
    appleScript: TerminalDiagnosticsFeatureState.disabled,
    osc52: TerminalDiagnosticsFeatureState.disabled,
    pendingOsc52Requests: 0,
    pendingNotificationRequests: 0,
    localIncidentState: TerminalDiagnosticsIncidentState.idle,
    localIncidentMatchingReports: 0,
    localIncidentCompletedOperations: 0,
    localIncidentFailures: 0,
  ),
);

final class _DiagnosticsMemoryFiles
    implements TerminalDiagnosticsFileOperations {
  final Map<String, Uint8List> destinations = <String, Uint8List>{};
  final Map<String, Uint8List> temporaryFiles = <String, Uint8List>{};
  bool failReplace = false;

  @override
  Future<void> writeExclusive(String path, Uint8List bytes) async {
    if (temporaryFiles.containsKey(path)) {
      throw StateError('temporary path was reused');
    }
    temporaryFiles[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> replace(String sourcePath, String destinationPath) async {
    if (failReplace) throw StateError('injected replace failure');
    destinations[destinationPath] = temporaryFiles.remove(sourcePath)!;
  }

  @override
  Future<void> remove(String path) async {
    temporaryFiles.remove(path);
  }
}

Future<void> _testRtlApplicationComposition() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalLocalization rtl = TerminalLocalization.resolve('ar-EG');
  final _SettingsMemoryFileSystem fileSystem = _SettingsMemoryFileSystem(
    const <String, String>{'/settings.conf': 'font-size = 15\n'},
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(
    fileSystem: fileSystem,
  );
  const List<String> arguments = <String>['--config=/settings.conf'];
  final TerminalConfigSnapshot initial = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () =>
            loader.resolve(arguments, environment: const <String, String>{}),
      );
  final View terminalView = View(configuration: terminalBaseViewConfiguration);
  final Window terminalWindow = Window(
    frame: const Rect.fromLTWH(100, 90, 640, 480),
    title: 'Terminal',
    configuration: terminalWindowConfiguration,
  )..contentView = terminalView;
  terminalWindow
    ..show()
    ..makeFirstResponder(terminalView);
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(localization: rtl),
  );
  final TerminalCommandPalettePresenter palette =
      TerminalCommandPalettePresenter(
        dispatcher: dispatcher,
        terminalWindow: terminalWindow,
        terminalView: terminalView,
        localization: rtl,
      );
  final TerminalSettingsInspectorPresenter settings =
      TerminalSettingsInspectorPresenter(
        controller: controller,
        documentSession: TerminalSettingsDocumentSession(
          loader: loader,
          arguments: arguments,
          environment: const <String, String>{},
          writer: fileSystem,
        ),
        focusTarget: () => TerminalSettingsInspectorFocusTarget(
          window: terminalWindow,
          view: terminalView,
        ),
        reload: () async => const TerminalActionDispatchResult(
          id: TerminalActionId.reloadConfiguration,
          disposition: TerminalActionDispatchDisposition.unavailable,
        ),
        localization: rtl,
      );
  try {
    await palette.open();
    _expect(
      palette.activeWindow!.title == 'Command Palette' &&
          palette.renderedText!.contains('‹ Settings…'),
      'RTL fallback did not retain English copy and reverse the palette marker',
    );
    await palette.dismiss();

    await settings.open();
    final int root = bindings.handleFor(settings.activeRootSplit!);
    final int detail = bindings.handleFor(settings.activeDetailView!);
    final int editorStatus = bindings.handleFor(
      settings.activeEditorStatusSplit!,
    );
    _expect(
      bindings.splitViewChildren[root]!.first == detail &&
          bindings.splitViewChildren[root]!.last == editorStatus &&
          bindings.splitViewFractions[root] == 0.3 &&
          settings.activeDetailView!.text.contains('Current value'),
      'RTL Settings did not place detail before editor without changing copy fallback',
    );
    settings.state.toggleDetails();
    settings.refresh();
    _expect(
      bindings.splitViewFractions[root] == 0.035 &&
          settings.activeDetailView!.text.startsWith('‹'),
      'RTL Settings collapsed detail did not stay on the leading edge',
    );
    _expect(
      settings.updateAccessibilityPresentation(
        const TerminalAccessibilityPresentation(
          reduceMotion: false,
          increaseContrast: true,
          differentiateWithoutColor: true,
        ),
      ),
      'RTL Settings did not accept presentation replacement',
    );
    final int replacedRoot = bindings.handleFor(settings.activeRootSplit!);
    _expect(
      bindings.splitViewChildren[replacedRoot]!.first ==
              bindings.handleFor(settings.activeDetailView!) &&
          bindings.splitViewChildren[replacedRoot]!.last ==
              bindings.handleFor(settings.activeEditorStatusSplit!) &&
          bindings.splitViewFractions[replacedRoot] == 0.035,
      'RTL ordering or collapsed fraction was lost during live replacement',
    );
  } finally {
    await settings.dispose();
    await palette.dispose();
    controller.dispose();
    if (!terminalWindow.isClosed) terminalWindow.close();
    terminalWindow.dispose();
    terminalView.dispose();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testApplicationThemeProjectionLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  TerminalApplicationThemeProjection<int>? projection;
  TerminalConfigReloadController? reloadController;
  try {
    rawEvents.add(<Object?>[7, 33, 0, 0, 100000, 0, false]);
    _expect(
      application.effectiveAppearance == AppKitAppearance.light,
      'fake AppKit initial light appearance was not cached',
    );

    final List<Object> errors = <Object>[];
    projection = TerminalApplicationThemeProjection<int>(
      application: application,
      onError: (Object error, StackTrace _) => errors.add(error),
    );
    final TerminalConfigSnapshot systemSnapshot = TerminalConfigLoader()
        .resolve(const <String>[
          '--no-config',
          '--theme=system',
        ], environment: const <String, String>{})
        .snapshot;
    final TerminalConfigSnapshot fixedLightSnapshot = TerminalConfigLoader()
        .resolve(const <String>[
          '--no-config',
          '--theme=light',
        ], environment: const <String, String>{})
        .snapshot;
    final TerminalProductConfigurationAuthority authority =
        TerminalProductConfigurationAuthority(
          TerminalProductConfiguration.fromSnapshot(systemSnapshot),
        );
    reloadController = TerminalConfigReloadController(
      initialSnapshot: systemSnapshot,
      resolver: () => TerminalConfigResolution(
        snapshot: fixedLightSnapshot,
        remainingArguments: const <String>[],
      ),
    );

    var systemNotifications = 0;
    var removedNotifications = 0;
    var fixedNotifications = 0;
    var systemAppearanceNotifications = 0;
    var fixedAppearanceNotifications = 0;
    late final TerminalScreenParserSink systemSink;
    late final TerminalScreenParserSink fixedSink;
    final List<String> systemReplies = <String>[];
    final List<String> fixedReplies = <String>[];
    final TerminalPalette systemPalette = projection.createPaletteForPane(
      key: 1,
      configuration: authority.newSessionConfiguration,
      onChanged: () => systemNotifications++,
      onAppearanceChanged: (TerminalThemeBrightness brightness) {
        systemAppearanceNotifications++;
        systemSink.projectColorScheme(switch (brightness) {
          TerminalThemeBrightness.light => TerminalColorScheme.light,
          TerminalThemeBrightness.dark => TerminalColorScheme.dark,
        });
      },
    );
    final TerminalPalette removedPalette = projection.createPaletteForPane(
      key: 2,
      configuration: authority.newSessionConfiguration,
      onChanged: () => removedNotifications++,
    );
    final TerminalScreenSet systemScreens = TerminalScreenSet(
      rows: 2,
      columns: 2,
      palette: systemPalette,
      initialColorScheme: TerminalColorScheme.light,
    );
    final TerminalScreenSet removedScreens = TerminalScreenSet(
      rows: 2,
      columns: 2,
      palette: removedPalette,
      initialColorScheme: TerminalColorScheme.light,
    );
    systemSink = TerminalScreenParserSink.forScreenSet(
      systemScreens,
      onReply: (Uint8List bytes) {
        systemReplies.add(ascii.decode(bytes));
        return true;
      },
    );
    VtParser(sink: systemSink).parse(ascii.encode('\x1b[?2031h'));
    systemScreens.primary.clearDamage();
    systemScreens.alternate.clearDamage();
    removedScreens.primary.clearDamage();
    removedScreens.alternate.clearDamage();
    final int systemScreenGeneration = systemScreens.primary.generation;
    final int removedPaletteGeneration = removedPalette.generation;
    _expect(
      systemPalette.defaultBackground ==
              TerminalBuiltInTheme.dartLight.background &&
          removedPalette.defaultBackground ==
              TerminalBuiltInTheme.dartLight.background &&
          projection.systemAppearance == TerminalThemeBrightness.light &&
          projection.registeredPaneCount == 2,
      'system panes capture the cached initial light appearance',
    );

    final TerminalConfigReloadResult reload = await reloadController.reload();
    authority.applyReload(reload);
    final TerminalPalette fixedPalette = projection.createPaletteForPane(
      key: 3,
      configuration: authority.newSessionConfiguration,
      onChanged: () => fixedNotifications++,
      onAppearanceChanged: (TerminalThemeBrightness brightness) {
        fixedAppearanceNotifications++;
        fixedSink.projectColorScheme(switch (brightness) {
          TerminalThemeBrightness.light => TerminalColorScheme.light,
          TerminalThemeBrightness.dark => TerminalColorScheme.dark,
        });
      },
    );
    final TerminalScreenSet fixedScreens = TerminalScreenSet(
      rows: 2,
      columns: 2,
      palette: fixedPalette,
      initialColorScheme: TerminalColorScheme.light,
    );
    fixedSink = TerminalScreenParserSink.forScreenSet(
      fixedScreens,
      onReply: (Uint8List bytes) {
        fixedReplies.add(ascii.decode(bytes));
        return true;
      },
    );
    VtParser(sink: fixedSink).parse(ascii.encode('\x1b[?2031h'));
    _expect(
      reload.disposition == TerminalConfigReloadDisposition.applied &&
          fixedPalette.defaultBackground ==
              TerminalBuiltInTheme.dartLight.background &&
          projection.removePane(2) &&
          projection.registeredPaneCount == 2,
      'accepted reload affects only later pane policy and removal unregisters',
    );

    final TerminalPalette systemPaletteIdentity = systemScreens.palette;
    final TerminalStyleTable systemStyleIdentity = systemScreens.styleTable;
    final TerminalScrollback systemScrollbackIdentity =
        systemScreens.scrollback;
    rawEvents.add(<Object?>[7, 33, 0, 0, 101000, 0, true]);
    _expect(
      application.effectiveAppearance == AppKitAppearance.dark &&
          projection.systemAppearance == TerminalThemeBrightness.dark &&
          systemPalette.defaultBackground ==
              TerminalBuiltInTheme.dartDark.background &&
          fixedPalette.defaultBackground ==
              TerminalBuiltInTheme.dartLight.background &&
          removedPalette.defaultBackground ==
              TerminalBuiltInTheme.dartLight.background &&
          systemNotifications == 1 &&
          systemAppearanceNotifications == 1 &&
          fixedNotifications == 0 &&
          fixedAppearanceNotifications == 0 &&
          removedNotifications == 0 &&
          systemScreens.colorScheme == TerminalColorScheme.dark &&
          fixedScreens.colorScheme == TerminalColorScheme.light &&
          systemReplies.length == 1 &&
          systemReplies.single == '\x1b[?997;1n' &&
          fixedReplies.isEmpty &&
          systemScreens.primary.generation == systemScreenGeneration + 1 &&
          systemScreens.primary.isRowDirty(0) &&
          systemScreens.alternate.isRowDirty(0) &&
          removedPalette.generation == removedPaletteGeneration &&
          identical(systemScreens.palette, systemPaletteIdentity) &&
          identical(systemScreens.styleTable, systemStyleIdentity) &&
          identical(systemScreens.scrollback, systemScrollbackIdentity),
      'live dark projection updates only registered system panes in place',
    );
    final int darkGeneration = systemPalette.generation;
    rawEvents.add(<Object?>[7, 33, 0, 0, 101500, 0, true]);
    _expect(
      systemPalette.generation == darkGeneration &&
          systemNotifications == 1 &&
          systemAppearanceNotifications == 1 &&
          fixedNotifications == 0,
      'duplicate appearance is idempotent even if the native edge repeats',
    );

    final TerminalPalette laterSystemPalette = projection.createPaletteForPane(
      key: 4,
      configuration: TerminalProductConfiguration.fromSnapshot(systemSnapshot),
      onChanged: () {},
    );
    _expect(
      laterSystemPalette.defaultBackground ==
              TerminalBuiltInTheme.dartDark.background &&
          projection.registeredPaneCount == 3,
      'a later system pane captures the current dark appearance',
    );

    await projection.dispose();
    final int notificationsBeforeDisposedEvent = systemNotifications;
    rawEvents.add(<Object?>[7, 33, 0, 0, 102000, 0, false]);
    _expect(
      projection.isDisposed &&
          projection.registeredPaneCount == 0 &&
          application.effectiveAppearance == AppKitAppearance.light &&
          systemPalette.defaultBackground ==
              TerminalBuiltInTheme.dartDark.background &&
          laterSystemPalette.defaultBackground ==
              TerminalBuiltInTheme.dartDark.background &&
          systemNotifications == notificationsBeforeDisposedEvent &&
          errors.isEmpty,
      'disposed projection releases every target and ignores later AppKit events',
    );
    _expectThrows<StateError>(
      () => projection!.createPaletteForPane(
        key: 5,
        configuration: authority.newSessionConfiguration,
        onChanged: () {},
      ),
      'disposed projection rejects later pane registration',
    );
  } finally {
    reloadController?.dispose();
    await projection?.dispose();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testPerWindowCreationFrameProjection() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  TerminalPaneConfiguration configuration() => TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState first = await state.createWindow(configuration());
  final TerminalWindowState second = await state.createWindow(configuration());
  const Rect firstFrame = Rect.fromLTWH(100, 90, 700, 500);
  const Rect secondFrame = Rect.fromLTWH(100, 90, 1100, 720);
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
    ),
    windowFrame: firstFrame,
    windowFrameBuilder: (TerminalWindowState window) =>
        window.id == first.id ? firstFrame : secondFrame,
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
  );
  try {
    adapter.reconcile();
    _expect(
      adapter.windowForTab(first.selectedTabId)!.frame == firstFrame &&
          adapter.windowForTab(second.selectedTabId)!.frame == secondFrame &&
          adapter.placementForWindow(first.id).windowedFrame.width == 700 &&
          adapter.placementForWindow(second.id).windowedFrame.width == 1100,
      'new logical windows capture their creation-time frame provider value',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testInitialNativeContentLayoutProjection() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings()
    ..windowContentLayoutHeightInset = 69;
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalPaneConfiguration configuration = TerminalPaneConfiguration(
    sessionFactory: (
      TerminalSessionId id, {
      required void Function() onChanged,
      required void Function() onTerminated,
    }) => _HierarchyFakeSession(id),
    onChanged: () {},
    onExitRequested: () {},
  );
  final TerminalWindowState logicalWindow = await state.createWindow(
    configuration,
  );
  await state.createTab(logicalWindow.id, configuration);
  final Map<PaneId, TerminalPaneLayoutRect> layouts =
      <PaneId, TerminalPaneLayoutRect>{};
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onLayout: (TerminalPaneLayoutRect? rectangle, {required bool visible}) {
        if (visible) layouts[pane.id] = rectangle!;
      },
    ),
    windowFrame: const Rect.fromLTWH(100, 90, 920, 580),
    cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
    presentWindows: false,
  );
  try {
    adapter.reconcile();
    _expect(
      layouts.length == 2 &&
          layouts.values.every(
            (TerminalPaneLayoutRect rectangle) =>
                rectangle.width == 920 && rectangle.height == 511,
          ) &&
          bindings.windowContentLayoutQueryCounts.values.every(
            (int count) => count == 1,
          ),
      'initial tab layouts use native content height before any resize event',
    );
    final TerminalTabId resizedTabId = logicalWindow.selectedTabId;
    final PaneId resizedPaneId = logicalWindow.selectedTab.focusedPaneId;
    final int resizedWindowHandle = bindings.handleFor(
      adapter.windowForTab(resizedTabId)!,
    );
    adapter.resizeTab(
      resizedTabId,
      TerminalSplitLayoutSize(width: 640.5, height: 360.25),
    );
    _expect(
      layouts[resizedPaneId]!.width == 640.5 &&
          layouts[resizedPaneId]!.height == 360.25 &&
          bindings.windowContentLayoutRects[resizedWindowHandle]!.width ==
              920 &&
          bindings.windowContentLayoutRects[resizedWindowHandle]!.height ==
              511 &&
          bindings.windowContentLayoutQueryCounts[resizedWindowHandle] == 1,
      'an explicit resize event owns one reconciliation even while the native '
      'content-layout query is stale',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testConfiguredWindowAndPaddingProjection() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(
        TerminalConfigLoader().resolve(const <String>[
          '--no-config',
          '--window-width=1110',
          '--window-height=710',
          '--window-padding-horizontal=18',
          '--window-padding-vertical=11',
        ], environment: const <String, String>{}).snapshot,
      );
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState logicalWindow = await state.createWindow(
    TerminalPaneConfiguration(
      sessionFactory: (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) => _HierarchyFakeSession(id),
      onChanged: () {},
      onExitRequested: () {},
    ),
  );
  final List<TerminalPaneLayoutRect> layouts = <TerminalPaneLayoutRect>[];
  final Rect frame = Rect.fromLTWH(
    100,
    90,
    profile.windowWidth,
    profile.windowHeight,
  );
  final TerminalNativeHierarchyAdapter adapter = TerminalNativeHierarchyAdapter(
    state: state,
    paneResourcesFactory: (TerminalPane pane) => TerminalNativePaneResources(
      paneId: pane.id,
      view: View(configuration: terminalBaseViewConfiguration),
      onLayout: (TerminalPaneLayoutRect? rectangle, {required bool visible}) {
        if (visible) layouts.add(rectangle!);
      },
    ),
    windowFrame: frame,
    cellSize: TerminalSplitLayoutSize(
      width: 8 + profile.windowPaddingHorizontal * 2,
      height: 16 + profile.windowPaddingVertical * 2,
    ),
    presentWindows: false,
  );
  try {
    adapter.reconcile();
    final TerminalTabState tab = logicalWindow.selectedTab;
    final TerminalPaneLayoutRect layout = layouts.single;
    final Window nativeWindow = adapter.windowForTab(tab.id)!;
    _expect(
      nativeWindow.frame == frame &&
          layout.width == profile.windowWidth &&
          layout.height == profile.windowHeight &&
          layout.width - profile.windowPaddingHorizontal * 2 ==
              profile.terminalContentWidth &&
          layout.height - profile.windowPaddingVertical * 2 ==
              profile.terminalContentHeight,
      'configured window frame and padded terminal extent project through '
      'fake AppKit',
    );
  } finally {
    adapter.dispose();
    await state.shutdown();
    await application.terminate();
    await rawEvents.close();
  }
}

Future<void> _testRepeatedMultiWindowRestoredProjection() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final List<_HierarchyFakeSession> allSessions = <_HierarchyFakeSession>[];
  final Set<int> priorPaneIds = <int>{};
  final Set<int> priorWindowIds = <int>{};
  final Set<int> priorTabIds = <int>{};
  final Set<int> priorSplitIds = <int>{};
  String? canonicalSnapshot;

  TerminalPaneConfiguration configuration(String? workingDirectory) =>
      TerminalPaneConfiguration(
        sessionFactory:
            (
              TerminalSessionId id, {
              required void Function() onChanged,
              required void Function() onTerminated,
            }) {
              final _HierarchyFakeSession session = _HierarchyFakeSession(
                id,
                workingDirectory: workingDirectory,
              );
              allSessions.add(session);
              return session;
            },
        onChanged: () {},
        onExitRequested: () {},
      );

  var state = TerminalApplicationState();
  var workingDirectories = <PaneId, String?>{};
  for (var windowIndex = 0; windowIndex < 2; windowIndex++) {
    final String cwd = '/private/tmp/phase7-window-${windowIndex + 1}';
    final TerminalWindowState window = await state.createWindow(
      configuration(cwd),
    );
    final TerminalTabState firstTab = window.selectedTab;
    workingDirectories[firstTab.focusedPaneId] = cwd;
    final TerminalPane firstSibling = await state.splitPane(
      firstTab.focusedPaneId,
      configuration(cwd),
      axis: TerminalSplitAxis.horizontal,
      fraction: 0.4,
    );
    workingDirectories[firstSibling.id] = cwd;
    final TerminalTabState secondTab = await state.createTab(
      window.id,
      configuration(cwd),
    );
    workingDirectories[secondTab.focusedPaneId] = cwd;
    final TerminalPane secondSibling = await state.splitPane(
      secondTab.focusedPaneId,
      configuration(cwd),
      axis: TerminalSplitAxis.vertical,
      fraction: 0.6,
    );
    workingDirectories[secondSibling.id] = cwd;
    state
      ..focusPane(firstTab.id, firstSibling.id)
      ..focusPane(secondTab.id, secondSibling.id)
      ..renameTab(secondTab.id, 'Phase 7 restored window ${windowIndex + 1}')
      ..setTabColor(secondTab.id, TerminalTabColor.blueMarker)
      ..selectTab(window.id, secondTab.id);
  }
  state.activateWindow(state.windowIds.first);
  var placements = <TerminalWindowId, TerminalWindowPlacement>{
    for (var index = 0; index < state.windowIds.length; index++)
      state.windowIds[index]: TerminalWindowPlacement(
        windowedFrame: TerminalWindowFrame(
          left: 80 + index * 120,
          top: 70 + index * 90,
          width: 760,
          height: 520,
        ),
        screen: null,
        fullscreen: false,
      ),
  };

  for (var generation = 0; generation < 3; generation++) {
    final Set<int> paneIds = state.paneIds.map((PaneId id) => id.value).toSet();
    final Set<int> windowIds = state.windowIds
        .map((TerminalWindowId id) => id.value)
        .toSet();
    final Set<int> tabIds = state.windows
        .expand((TerminalWindowState window) => window.tabIds)
        .map((TerminalTabId id) => id.value)
        .toSet();
    final Set<int> splitIds = state.windows
        .expand((TerminalWindowState window) => window.tabs)
        .expand((TerminalTabState tab) => tab.splitTree.nodeIds)
        .map((TerminalSplitNodeId id) => id.value)
        .toSet();
    _expect(
      paneIds.intersection(priorPaneIds).isEmpty &&
          windowIds.intersection(priorWindowIds).isEmpty &&
          tabIds.intersection(priorTabIds).isEmpty &&
          splitIds.intersection(priorSplitIds).isEmpty,
      'restored fake-AppKit generations reuse runtime identities',
    );
    priorPaneIds.addAll(paneIds);
    priorWindowIds.addAll(windowIds);
    priorTabIds.addAll(tabIds);
    priorSplitIds.addAll(splitIds);

    final TerminalNativeHierarchyAdapter adapter =
        TerminalNativeHierarchyAdapter(
          state: state,
          paneResourcesFactory: (TerminalPane pane) =>
              TerminalNativePaneResources(
                paneId: pane.id,
                view: View(configuration: terminalBaseViewConfiguration),
              ),
          windowFrame: const Rect.fromLTWH(80, 70, 760, 520),
          cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
          dividerThickness: 1,
          windowPlacements: placements,
          presentWindows: false,
        );
    adapter.reconcile(
      tabSizes: <TerminalTabId, TerminalSplitLayoutSize>{
        for (final TerminalWindowState window in state.windows)
          for (final TerminalTabState tab in window.tabs)
            tab.id: TerminalSplitLayoutSize(width: 760, height: 520),
      },
    );
    _expect(
      state.windowCount == 2 &&
          state.tabCount == 4 &&
          state.paneCount == 8 &&
          state.windows.every(
            (TerminalWindowState window) =>
                window.tabs.length == 2 &&
                window.tabs.every(
                  (TerminalTabState tab) => tab.paneIds.length == 2,
                ),
          ) &&
          adapter.nativeWindowCount == 4 &&
          adapter.splitViewCount == 4 &&
          adapter.paneResourceCount == 8 &&
          bindings.objects.length == 16 &&
          bindings.windowTabGroups.length == 2 &&
          bindings.windowTabGroups.every(
            (List<int> group) => group.length == 2,
          ) &&
          bindings.selectedTabWindows.length == 2 &&
          bindings.firstResponders.length == 2,
      'generation $generation did not project two four-pane tabbed windows',
    );

    final TerminalRestorationSnapshot snapshot =
        TerminalApplicationRestorationCapture.capture(
          state,
          placementForWindow: (TerminalWindowId id) => placements[id]!,
          workingDirectoryForPane: (PaneId id) => workingDirectories[id],
        );
    final String encoded = TerminalRestorationCodec.encode(snapshot);
    canonicalSnapshot ??= encoded;
    _expect(
      encoded == canonicalSnapshot,
      'fresh fake-AppKit identities changed the content-free snapshot',
    );

    adapter.dispose();
    await state.shutdown();
    final List<_HierarchyFakeSession> generationSessions = allSessions.sublist(
      generation * 8,
      (generation + 1) * 8,
    );
    _expect(
      generationSessions.length == 8 &&
          generationSessions.every(
            (_HierarchyFakeSession session) => session.shutdownCount == 1,
          ) &&
          bindings.objects.isEmpty &&
          bindings.windowTabGroups.isEmpty &&
          bindings.selectedTabWindows.isEmpty &&
          bindings.firstResponders.isEmpty,
      'generation $generation retained fake sessions or native handles',
    );

    if (generation < 2) {
      final int seed = (generation + 1) * 1000;
      final TerminalRestorationResult restored =
          await TerminalApplicationRestorer.restore(
            TerminalRestorationCodec.decode(encoded),
            into: TerminalApplicationState(
              paneOwner: TerminalPaneOwner(initialPaneId: seed + 300),
              initialWindowId: seed,
              initialTabId: seed + 100,
              initialSplitNodeId: seed + 200,
            ),
            configurationForPane: (TerminalRestorablePane pane) =>
                configuration(pane.workingDirectory),
          );
      state = restored.applicationState;
      placements = restored.placements;
      workingDirectories = restored.launchWorkingDirectories;
    }
  }

  _expect(
    allSessions.length == 24 &&
        allSessions.every(
          (_HierarchyFakeSession session) => session.shutdownCount == 1,
        ),
    'three fake-AppKit generations do not own 24 exact sessions',
  );
  await application.terminate();
  await rawEvents.close();
}

Future<void> _testNativeTerminationReplyAndHierarchyCleanup() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  application.defersTerminationRequests = true;
  final List<String> lifecycle = <String>[];
  final List<_HierarchyFakeSession> sessions = <_HierarchyFakeSession>[];
  final TerminalApplicationState state = TerminalApplicationState();
  final TerminalWindowState window = await state.createWindow(
    TerminalPaneConfiguration(
      sessionFactory:
          (
            TerminalSessionId id, {
            required void Function() onChanged,
            required void Function() onTerminated,
          }) {
            final _HierarchyFakeSession session = _HierarchyFakeSession(
              id,
              onShutdown: () => lifecycle.add('session'),
            );
            sessions.add(session);
            return session;
          },
      onChanged: () {},
      onExitRequested: () {},
    ),
  );
  await state.paneForId(window.selectedTab.focusedPaneId)!.start();
  final TerminalNativeHierarchyAdapter hierarchy =
      TerminalNativeHierarchyAdapter(
        state: state,
        paneResourcesFactory: (TerminalPane pane) =>
            TerminalNativePaneResources(
              paneId: pane.id,
              view: View(configuration: terminalBaseViewConfiguration),
              onDisposeAdapters: () => lifecycle.add('native'),
            ),
        windowFrame: const Rect.fromLTWH(40, 50, 800, 600),
        cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
        presentWindows: false,
      );
  hierarchy.reconcile();
  var programmaticTerminationCount = 0;
  final TerminalPaneCloseCoordinator paneClose = TerminalPaneCloseCoordinator(
    state: state,
    onHierarchyChanged: hierarchy.reconcile,
  );
  final TerminalApplicationQuitCoordinator quit =
      TerminalApplicationQuitCoordinator(
        state: state,
        paneCloseCoordinator: paneClose,
        replyToTerminationRequest:
            (
              ApplicationTerminateRequestedEvent request, {
              required bool allow,
            }) {
              lifecycle.add('reply');
              application.replyToTerminationRequest(request, allow: allow);
            },
        onPreShutdown: () async {
          hierarchy.dispose();
        },
        terminateProgrammatically: () async {
          programmaticTerminationCount++;
        },
      );
  const ApplicationTerminateRequestedEvent request =
      ApplicationTerminateRequestedEvent(monotonicMicros: 77, operationId: 77);
  final TerminalApplicationQuitResult result = await quit
      .handleTerminationRequest(request);
  _expect(
    result.disposition == TerminalApplicationQuitDisposition.terminated &&
        result.nativeOperationId == 77 &&
        bindings.terminationDeferralEnabled &&
        bindings.terminationReplies.join(',') == '77:true' &&
        lifecycle.join(',') == 'native,session,reply' &&
        sessions.single.shutdownCount == 1 &&
        hierarchy.paneResourceCount == 0 &&
        hierarchy.splitViewCount == 0 &&
        hierarchy.nativeWindowCount == 0 &&
        bindings.objects.isEmpty &&
        state.isDisposed &&
        programmaticTerminationCount == 0,
    'native Quit replies allow once and only after hierarchy/session cleanup',
  );
  _expect(
    (await quit.handleTerminationRequest(request)).disposition ==
            TerminalApplicationQuitDisposition.stale &&
        bindings.terminationReplies.length == 1 &&
        sessions.single.shutdownCount == 1,
    'completed duplicate native Quit neither replies nor tears down twice',
  );
  await application.terminate();
  await rawEvents.close();
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
      final View view = View(configuration: terminalBaseViewConfiguration);
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
    windowPlacements: <TerminalWindowId, TerminalWindowPlacement>{
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
        fullscreen: false,
      ),
    },
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
  final TwoPaneSplitView firstRoot = adapter.splitViewForNode(firstRootId)!;
  final int firstRootHandle = bindings.handleFor(firstRoot);
  final int secondPaneViewHandle = bindings.handleFor(secondResources.view);
  final int selectedWindowHandle = bindings.handleFor(
    adapter.windowForTab(secondTab.id)!,
  );
  final int fourthPaneViewHandle = bindings.handleFor(
    adapter.resourcesForPane(fourthPane.id)!.view,
  );
  final List<StreamSubscription<WindowEvent>> placementSubscriptions = adapter
      .windows
      .entries
      .map(
        (MapEntry<TerminalTabId, Window> entry) => entry.value.events.listen(
          (WindowEvent event) => adapter.handleWindowEvent(entry.key, event),
        ),
      )
      .toList(growable: false);
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
        bindings.firstResponders[selectedWindowHandle] ==
            fourthPaneViewHandle &&
        bindings.presentationCalls.length == 3 &&
        bindings.presentationCalls[0] == 'show:$selectedWindowHandle' &&
        bindings.presentationCalls[1] == 'select:$selectedWindowHandle' &&
        bindings.presentationCalls[2] ==
            'responder:$selectedWindowHandle:$fourthPaneViewHandle',
    'two logical tabs project to one selected native tab group and four panes',
  );
  _expect(
    bindings.windowTitles[firstWindowHandle] == 'First live title' &&
        bindings.windowRepresentedFilePaths[firstWindowHandle] ==
            '/private/tmp/first' &&
        bindings.windowTitles[selectedWindowHandle] == 'Pinned second tab' &&
        bindings.windowRepresentedFilePaths[selectedWindowHandle] ==
            '/private/tmp/second' &&
        bindings.windowStyleMasks.values.every(
          (int mask) => mask == dartAppKitDefaultWindowStyleMask,
        ) &&
        bindings.viewConfigurations.values.every(
          (NativeViewConfiguration configuration) =>
              configuration.isCompatibilityDefault,
        ) &&
        bindings.windowTabAccessoryShapes[selectedWindowHandle] ==
            dartAppKitWindowTabAccessoryShapeEllipse &&
        bindings.windowTabAccessoryExtents[selectedWindowHandle]![0] == 8 &&
        bindings.windowTabAccessoryExtents[selectedWindowHandle]![1] == 8 &&
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
  final Map<PaneId, int> layoutCountsBeforePresentationRefresh = <PaneId, int>{
    for (final MapEntry<PaneId, List<String>> entry in layouts.entries)
      entry.key: entry.value.length,
  };
  final int presentationCallCountBeforeRefresh =
      bindings.presentationCalls.length;
  adapter.refreshPresentation();
  _expect(
    bindings.windowTitles[firstWindowHandle] == 'Updated first title' &&
        !bindings.windowRepresentedFilePaths.containsKey(firstWindowHandle) &&
        bindings.windowTitles[selectedWindowHandle] == 'Second live title' &&
        !bindings.windowTabColors.containsKey(selectedWindowHandle) &&
        bindings.windowContentViewSetCounts[firstWindowHandle] == 1 &&
        bindings.windowContentViewSetCounts[selectedWindowHandle] == 1 &&
        bindings.splitViewChildrenSetCounts.length == 2 &&
        bindings.splitViewChildrenSetCounts.values.every(
          (int count) => count == 1,
        ) &&
        layouts.entries.every(
          (MapEntry<PaneId, List<String>> entry) =>
              entry.value.length ==
              layoutCountsBeforePresentationRefresh[entry.key],
        ) &&
        bindings.presentationCalls.length == presentationCallCountBeforeRefresh,
    'presentation refresh updates retained metadata without layout or focus',
  );
  _expect(
    firstWindow.tabIds.every(
          (TerminalTabId tabId) =>
              bindings.windowFrames[bindings.handleFor(
                adapter.windowForTab(tabId)!,
              )] ==
              const Rect.fromLTWH(-1200, 80, 920, 580),
        ) &&
        bindings.windowShowCounts[selectedWindowHandle] == 1,
    'one logical placement is projected to every native tab and shown once',
  );

  adapter.requestFullscreen(firstWindow.id, true);
  _expect(
    bindings.windowFullscreenRequests[selectedWindowHandle] == true &&
        adapter.placementForWindow(firstWindow.id).fullscreen,
    'fullscreen intent targets only the selected native tab',
  );
  final int selectedGeneration = selectedWindowHandle >> 32;
  rawEvents.add(<Object?>[
    6,
    9,
    selectedWindowHandle,
    selectedGeneration,
    500000,
    0,
    -1920.0,
    0.0,
    1920.0,
    1080.0,
  ]);
  rawEvents.add(<Object?>[
    6,
    15,
    selectedWindowHandle,
    selectedGeneration,
    500001,
    0,
    true,
  ]);
  rawEvents.add(<Object?>[
    6,
    7,
    selectedWindowHandle,
    selectedGeneration,
    500002,
    0,
    true,
    77,
    0.0,
    0.0,
    1512.0,
    982.0,
    0.0,
    23.0,
    1512.0,
    959.0,
  ]);
  final TerminalWindowPlacement migratedFullscreen = adapter.placementForWindow(
    firstWindow.id,
  );
  _expect(
    migratedFullscreen.fullscreen &&
        migratedFullscreen.screen?.displayId == 77 &&
        migratedFullscreen.windowedFrame.width == 920 &&
        migratedFullscreen.windowedFrame !=
            TerminalWindowFrame(left: -1920, top: 0, width: 1920, height: 1080),
    'fullscreen transition frames are ignored while safe placement migrates',
  );
  rawEvents.add(<Object?>[
    6,
    15,
    selectedWindowHandle,
    selectedGeneration,
    500003,
    0,
    false,
  ]);
  final Rect migratedFrame = Rect.fromLTWH(
    migratedFullscreen.windowedFrame.left,
    migratedFullscreen.windowedFrame.top,
    migratedFullscreen.windowedFrame.width,
    migratedFullscreen.windowedFrame.height,
  );
  bindings.windowFrames[selectedWindowHandle] = const Rect.fromLTWH(
    0,
    0,
    1618,
    1020,
  );
  rawEvents.add(<Object?>[
    6,
    9,
    selectedWindowHandle,
    selectedGeneration,
    500004,
    0,
    0.0,
    0.0,
    1618.0,
    1020.0,
  ]);
  _expect(
    !adapter.placementForWindow(firstWindow.id).fullscreen &&
        adapter.placementForWindow(firstWindow.id).windowedFrame ==
            migratedFullscreen.windowedFrame &&
        firstWindow.tabIds.every(
          (TerminalTabId tabId) =>
              bindings.windowFrames[bindings.handleFor(
                adapter.windowForTab(tabId)!,
              )] ==
              migratedFrame,
        ),
    'fullscreen exit ignores its completion frame and restores the migrated '
    'safe frame to the native tab group',
  );
  final Rect settledWindowedFrame = Rect.fromLTWH(
    migratedFrame.left + 12,
    migratedFrame.top + 8,
    migratedFrame.width,
    migratedFrame.height,
  );
  bindings.windowFrames[selectedWindowHandle] = settledWindowedFrame;
  rawEvents.add(<Object?>[
    6,
    9,
    selectedWindowHandle,
    selectedGeneration,
    500005,
    0,
    settledWindowedFrame.left,
    settledWindowedFrame.top,
    settledWindowedFrame.width,
    settledWindowedFrame.height,
  ]);
  _expect(
    adapter.placementForWindow(firstWindow.id).windowedFrame ==
            TerminalWindowFrame(
              left: settledWindowedFrame.left,
              top: settledWindowedFrame.top,
              width: settledWindowedFrame.width,
              height: settledWindowedFrame.height,
            ) &&
        firstWindow.tabIds.every(
          (TerminalTabId tabId) =>
              bindings.windowFrames[bindings.handleFor(
                adapter.windowForTab(tabId)!,
              )] ==
              settledWindowedFrame,
        ),
    'an authoritative windowed frame converges every native tab',
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

  final TerminalPaneCloseCoordinator closeCoordinator =
      TerminalPaneCloseCoordinator(
        state: state,
        onHierarchyChanged: adapter.reconcile,
      );
  final TerminalPaneCloseResult splitClose = await closeCoordinator
      .requestClose(paneId: secondPane.id);
  _expect(
    splitClose.disposition == TerminalPaneCloseDisposition.removed &&
        firstRoot.isDisposed &&
        secondResources.isDisposed &&
        identical(adapter.resourcesForPane(firstPane), firstResources) &&
        adapter.splitViewForNode(firstRootId) == null &&
        lifecycle.contains('adapters:${secondPane.id}') &&
        bindings.releaseOrder.indexOf(firstRootHandle) <
            bindings.releaseOrder.indexOf(secondPaneViewHandle),
    'collapsed split disposes pane adapters, then split, then removed pane view',
  );

  final TwoPaneSplitView secondRoot = adapter.splitViews.values.single;
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
  for (final StreamSubscription<WindowEvent> subscription
      in placementSubscriptions) {
    await subscription.cancel();
  }
  _expect(
    bindings.objects.isEmpty &&
        bindings.windowTabGroups.isEmpty &&
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

Future<void> _testRestorationPersistenceAndReopenLifecycle() async {
  final StreamController<Object?> rawEvents =
      StreamController<Object?>.broadcast(sync: true);
  final _HierarchyNativeBindings bindings = _HierarchyNativeBindings();
  final AppKitApplication application = await attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
  final _LifecycleMemoryStore store = _LifecycleMemoryStore('{invalid');
  final List<_HierarchyFakeSession> sessions = <_HierarchyFakeSession>[];
  final Map<PaneId, String?> workingDirectories = <PaneId, String?>{};
  final List<String> nativeDisposal = <String>[];
  final List<String> disposalOrder = <String>[];
  final List<TerminalRestorationDiagnostic> diagnostics =
      <TerminalRestorationDiagnostic>[];

  TerminalPaneConfiguration configurationForPane(
    TerminalRestorablePane saved,
  ) => TerminalPaneConfiguration(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          final _HierarchyFakeSession session = _HierarchyFakeSession(
            id,
            workingDirectory: saved.workingDirectory,
            onShutdown: () => disposalOrder.add('session:${id.paneId}'),
          );
          sessions.add(session);
          workingDirectories[id.paneId] = saved.workingDirectory;
          return session;
        },
    onChanged: () {},
    onExitRequested: () {},
  );

  final TerminalRestorationLifecycle lifecycle = TerminalRestorationLifecycle(
    persistence: TerminalRestorationPersistence(store),
    configurationForPane: configurationForPane,
    hierarchyFactory:
        ({
          required TerminalApplicationState state,
          required Map<TerminalWindowId, TerminalWindowPlacement> placements,
        }) => TerminalNativeHierarchyAdapter(
          state: state,
          paneResourcesFactory: (TerminalPane pane) {
            final View view = View(
              configuration: terminalBaseViewConfiguration,
            );
            return TerminalNativePaneResources(
              paneId: pane.id,
              view: view,
              onDisposeAdapters: () {
                nativeDisposal.add('adapters:${pane.id}');
                disposalOrder.add('native:${pane.id}');
              },
            );
          },
          windowFrame: const Rect.fromLTWH(100, 90, 920, 580),
          cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
          windowPlacements: placements,
          presentWindows: false,
        ),
    defaultPlacement: TerminalWindowPlacement(
      windowedFrame: TerminalWindowFrame(
        left: 100,
        top: 90,
        width: 920,
        height: 580,
      ),
      screen: null,
      fullscreen: false,
    ),
    defaultWorkingDirectory: '/private/tmp/default',
    workingDirectoryForPane: (PaneId paneId) => workingDirectories[paneId],
    onDiagnostic: diagnostics.add,
  );

  _expect(
    await lifecycle.start() ==
            TerminalRestorationStartDisposition.defaultCreated &&
        lifecycle.current!.state.windowCount == 1 &&
        lifecycle.current!.state.paneCount == 1 &&
        diagnostics.map((value) => value.kind).toSet().containsAll(
          const <TerminalRestorationDiagnosticKind>[
            TerminalRestorationDiagnosticKind.rejected,
            TerminalRestorationDiagnosticKind.defaultCreated,
          ],
        ),
    'malformed persistence falls back to one usable default generation',
  );

  final TerminalRestorationGeneration initial = lifecycle.current!;
  final TerminalApplicationState state = initial.state;
  final TerminalWindowState window = state.windows.single;
  final TerminalTabState firstTab = window.selectedTab;
  final PaneId firstPane = firstTab.focusedPaneId;
  final TerminalPane secondPane = await state.splitPane(
    firstPane,
    configurationForPane(
      TerminalRestorablePane(workingDirectory: '/private/tmp/second'),
    ),
    axis: TerminalSplitAxis.horizontal,
    fraction: 0.35,
  );
  final TerminalTabState secondTab = await state.createTab(
    window.id,
    configurationForPane(
      TerminalRestorablePane(workingDirectory: '/private/tmp/third'),
    ),
  );
  final TerminalPane fourthPane = await state.splitPane(
    secondTab.focusedPaneId,
    configurationForPane(
      TerminalRestorablePane(workingDirectory: '/private/tmp/fourth'),
    ),
    axis: TerminalSplitAxis.vertical,
    fraction: 0.65,
  );
  state
    ..focusPane(firstTab.id, secondPane.id)
    ..renameTab(secondTab.id, 'Restored lifecycle tab')
    ..setTabColor(secondTab.id, TerminalTabColor.greenMarker)
    ..focusPane(secondTab.id, fourthPane.id)
    ..setPaneZoom(secondTab.id, fourthPane.id)
    ..selectTab(window.id, secondTab.id);
  lifecycle.reconcile();
  initial.hierarchy.requestFullscreen(window.id, true);
  final Set<int> oldPaneIds = state.paneIds
      .map((PaneId id) => id.value)
      .toSet();
  final Set<int> oldWindowIds = state.windowIds
      .map((TerminalWindowId id) => id.value)
      .toSet();
  final int originalSessionCount = sessions.length;
  final TerminalRestorationSaveResult saved = await lifecycle.persistCurrent();
  _expect(
    state.tabCount == 2 &&
        state.paneCount == 4 &&
        saved.disposition == TerminalRestorationSaveDisposition.saved,
    'multi-tab/four-pane state is persisted before teardown',
  );

  store.failWrites = true;
  final Future<TerminalPaneOwnerShutdownResult?> firstSuspend = lifecycle
      .suspendForReopen();
  final Future<TerminalPaneOwnerShutdownResult?> secondSuspend = lifecycle
      .suspendForReopen();
  _expect(
    identical(firstSuspend, secondSuspend),
    'concurrent close suspension shares one teardown future',
  );
  final TerminalPaneOwnerShutdownResult suspended = (await firstSuspend)!;
  _expect(
    suspended.sessions.length == 4 &&
        suspended.isClean &&
        lifecycle.current == null &&
        bindings.objects.isEmpty &&
        sessions
            .take(originalSessionCount)
            .every((_HierarchyFakeSession value) => value.shutdownCount == 1) &&
        diagnostics.last.kind == TerminalRestorationDiagnosticKind.suspended &&
        diagnostics.any(
          (TerminalRestorationDiagnostic value) =>
              value.kind == TerminalRestorationDiagnosticKind.saveUnavailable,
        ) &&
        disposalOrder
            .take(4)
            .every((String value) => value.startsWith('native:')) &&
        disposalOrder
            .skip(4)
            .take(4)
            .every((String value) => value.startsWith('session:')),
    'native projection is released before exact session shutdown even when '
    'the persistence target is unavailable',
  );

  final Future<TerminalRestorationReopenDisposition> firstReopen = lifecycle
      .handleReopenRequest(
        const ApplicationReopenRequestedEvent(
          monotonicMicros: 500100,
          operationId: 8,
          hasVisibleWindows: false,
        ),
      );
  final Future<TerminalRestorationReopenDisposition> secondReopen = lifecycle
      .handleReopenRequest(
        const ApplicationReopenRequestedEvent(
          monotonicMicros: 500101,
          operationId: 9,
          hasVisibleWindows: false,
        ),
      );
  _expect(
    identical(firstReopen, secondReopen) &&
        await firstReopen == TerminalRestorationReopenDisposition.restored,
    'concurrent Dock reopen requests create one restored generation',
  );
  final TerminalRestorationGeneration restored = lifecycle.current!;
  final TerminalApplicationState restoredState = restored.state;
  final TerminalWindowState restoredWindow = restoredState.windows.single;
  final int restoredSelectedHandle = bindings.handleFor(
    restored.hierarchy.windowForTab(restoredWindow.selectedTabId)!,
  );
  _expect(
    restoredState.windowCount == 1 &&
        restoredState.tabCount == 2 &&
        restoredState.paneCount == 4 &&
        restoredState.paneIds.every(
          (PaneId id) => !oldPaneIds.contains(id.value),
        ) &&
        restoredState.windowIds.every(
          (TerminalWindowId id) => !oldWindowIds.contains(id.value),
        ) &&
        restoredState.windows.single.tabs.last.customTitle ==
            'Restored lifecycle tab' &&
        restoredState.windows.single.tabs.last.color ==
            TerminalTabColor.greenMarker &&
        restoredState.windows.single.tabs.last.isZoomed &&
        restored.launchWorkingDirectories.values.toSet().containsAll(
          const <String>{
            '/private/tmp/default',
            '/private/tmp/second',
            '/private/tmp/third',
            '/private/tmp/fourth',
          },
        ) &&
        sessions.length == originalSessionCount * 2 &&
        bindings.windowSelectCounts[restoredSelectedHandle] == 1 &&
        bindings.windowFirstResponderCounts[restoredSelectedHandle] == 1 &&
        bindings.windowShowCounts[restoredSelectedHandle] == 1,
    'reopen restores topology and trusted cwd values into fresh owners',
  );

  final int sessionsBeforeVisibleReopen = sessions.length;
  _expect(
    await lifecycle.reopen(hasVisibleWindows: true) ==
            TerminalRestorationReopenDisposition.ignoredVisible &&
        sessions.length == sessionsBeforeVisibleReopen,
    'a reopen notification reporting visible windows is ignored',
  );
  final Future<TerminalRestorationReopenDisposition> presentOnce = lifecycle
      .reopen(hasVisibleWindows: false);
  final Future<TerminalRestorationReopenDisposition> presentDuplicate =
      lifecycle.reopen(hasVisibleWindows: false);
  _expect(
    identical(presentOnce, presentDuplicate) &&
        await presentOnce ==
            TerminalRestorationReopenDisposition.presentedExisting &&
        sessions.length == sessionsBeforeVisibleReopen &&
        bindings.windowSelectCounts[restoredSelectedHandle] == 2 &&
        bindings.windowFirstResponderCounts[restoredSelectedHandle] == 2 &&
        bindings.windowShowCounts[restoredSelectedHandle] == 2,
    'repeated hidden-window reopen presents existing owners without duplication',
  );

  await lifecycle.shutdown(persist: false);
  _expect(
    lifecycle.isDisposed &&
        lifecycle.current == null &&
        bindings.objects.isEmpty &&
        sessions.every(
          (_HierarchyFakeSession value) => value.shutdownCount == 1,
        ) &&
        nativeDisposal.length == sessions.length &&
        diagnostics.every(
          (TerminalRestorationDiagnostic value) =>
              !value.machineLine().contains('/private/tmp') &&
              !value.machineLine().contains('{invalid'),
        ),
    'final lifecycle teardown is exact and diagnostics remain content-free',
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
  _HierarchyFakeSession(this.id, {this.workingDirectory, this.onShutdown});

  @override
  final TerminalSessionId id;
  final String? workingDirectory;
  final void Function()? onShutdown;

  var live = false;
  var shutdownCount = 0;

  @override
  bool get isLive => live;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;

  @override
  TerminalPaneProcessSnapshot processSnapshot() => !live
      ? TerminalPaneProcessSnapshot.nonLive(id)
      : TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: id.paneId.value,
          owningProcessGroup: id.paneId.value,
          foregroundProcessGroup: id.paneId.value,
        );

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
    onShutdown?.call();
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}

final class _LifecycleMemoryStore implements TerminalRestorationStore {
  _LifecycleMemoryStore(this.encoded);

  String? encoded;
  bool failWrites = false;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    readCount++;
    return encoded;
  }

  @override
  Future<void> write(String value) async {
    writeCount++;
    if (failWrites) throw StateError('injected restoration write failure');
    encoded = value;
  }
}

var _hierarchyEventNanoseconds = 200000;

Uint8List _nativeOsc52(String payload) =>
    Uint8List.fromList(<int>[0x1b, 0x5d, ...ascii.encode(payload), 0x07]);

final class _NativeOsc52Clipboard implements TerminalOsc52ClipboardPort {
  _NativeOsc52Clipboard(this.text);

  String? text;
  int _changeCount = 1;
  int readCount = 0;

  @override
  int get changeCount => _changeCount;

  @override
  TerminalOsc52ClipboardText readText() {
    readCount++;
    return TerminalOsc52ClipboardText(text: text, changeCount: _changeCount);
  }

  @override
  int writeText(String value) {
    text = value;
    return ++_changeCount;
  }

  @override
  int clear() {
    text = null;
    return ++_changeCount;
  }
}

void _injectHierarchyKey(
  StreamController<Object?> events,
  AppKitApplication application,
  int windowHandle, {
  required int keyCode,
  required String characters,
  int modifiers = 0,
}) {
  _hierarchyEventNanoseconds += 1000;
  events.add(<Object?>[
    application.eventProtocolVersion,
    20,
    windowHandle,
    windowHandle >> 32,
    _hierarchyEventNanoseconds,
    0,
    keyCode,
    modifiers,
    false,
    characters,
    characters,
  ]);
}

Future<void> _waitForHierarchy(
  bool Function() predicate,
  String description,
) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (!predicate() && timeout.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(Duration.zero);
  }
  _expect(predicate(), description);
}

final class _SettingsMemoryFileSystem
    implements TerminalConfigFileSystem, TerminalSettingsDocumentWriter {
  _SettingsMemoryFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

  final Map<String, List<int>> _files;

  String readText(String path) => utf8.decode(_files[path]!);

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => _files.containsKey(absolutePath(path));

  @override
  List<int> readBytes(String path) =>
      List<int>.from(_files[absolutePath(path)]!);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      includedPath.startsWith('/') ? includedPath : '/$includedPath';

  @override
  void writeAtomically(String path, List<int> bytes) {
    _files[absolutePath(path)] = List<int>.from(bytes);
  }
}

bool _sameNativeTextEditorStyles(
  List<NativeTextEditorStyleRun> left,
  List<NativeTextEditorStyleRun> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final NativeTextEditorStyleRun a = left[index];
    final NativeTextEditorStyleRun b = right[index];
    if (a.start != b.start ||
        a.length != b.length ||
        a.foregroundColorKind != b.foregroundColorKind ||
        a.foregroundRed != b.foregroundRed ||
        a.foregroundGreen != b.foregroundGreen ||
        a.foregroundBlue != b.foregroundBlue ||
        a.foregroundAlpha != b.foregroundAlpha ||
        a.underlineStyle != b.underlineStyle ||
        a.underlineColorKind != b.underlineColorKind ||
        a.underlineRed != b.underlineRed ||
        a.underlineGreen != b.underlineGreen ||
        a.underlineBlue != b.underlineBlue ||
        a.underlineAlpha != b.underlineAlpha) {
      return false;
    }
  }
  return true;
}

final class _PresenterUpdateService implements TerminalUpdateProductService {
  var checkCount = 0;
  var installCount = 0;
  var disposeCount = 0;

  @override
  Future<TerminalUpdateRelease?> check() async {
    checkCount++;
    return TerminalUpdateRelease(
      version: TerminalSemanticVersion.parse('0.2.0'),
      build: 2,
      minimumMacos: const TerminalMacosVersion(14, 0),
      archiveUrl: Uri.parse('https://updates.example.test/DartTerminal.zip'),
      archiveSize: 4096,
      archiveSha256: List<String>.filled(64, 'e').join(),
      releaseNotes: const <String>['<b>plain text only</b>'],
    );
  }

  @override
  Future<void> prepareInstall(TerminalUpdateRelease release) async {
    installCount++;
  }

  @override
  void cancel() {}

  @override
  void dispose() {
    disposeCount++;
  }
}

final class _RecordingIncidentStore
    implements TerminalIncidentCrashReportStore {
  _RecordingIncidentStore(this.delegate);

  final TerminalIncidentCrashReportStore delegate;
  int discoverCount = 0;
  int exportCount = 0;
  int get accessCount => discoverCount + exportCount;

  @override
  Future<TerminalIncidentReportSelection> discover({
    required TerminalIncidentCancellation cancellation,
  }) async {
    discoverCount++;
    return delegate.discover(cancellation: cancellation);
  }

  @override
  Future<void> export(
    TerminalIncidentReportSelection selection,
    File destination, {
    required TerminalIncidentCancellation cancellation,
  }) async {
    exportCount++;
    await delegate.export(selection, destination, cancellation: cancellation);
  }
}

final class _PresenterIncidentProcessRunner
    implements TerminalIncidentProcessRunner {
  int runCount = 0;
  List<String>? lastArguments;
  bool delayNext = false;
  bool waiting = false;
  Completer<void>? _release;

  void release() => _release?.complete();

  @override
  Future<TerminalIncidentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required int maximumOutputBytes,
    required TerminalIncidentCancellation cancellation,
  }) async {
    runCount++;
    lastArguments = List<String>.unmodifiable(arguments);
    if (delayNext) {
      delayNext = false;
      waiting = true;
      _release = Completer<void>();
      await _release!.future;
      waiting = false;
      if (cancellation.isCancelled) {
        return const TerminalIncidentProcessResult(
          TerminalIncidentProcessDisposition.cancelled,
        );
      }
    }
    if (cancellation.isCancelled ||
        executable != '/usr/bin/sample' ||
        arguments.length != 5 ||
        arguments[0] != '5150' ||
        arguments[1] != '1' ||
        arguments[2] != '1' ||
        arguments[3] != '-file') {
      return const TerminalIncidentProcessResult(
        TerminalIncidentProcessDisposition.failed,
      );
    }
    File(arguments[4])
        .writeAsStringSync('__INCIDENT_TEST_PRIVATE_SAMPLE__\n', flush: true);
    return const TerminalIncidentProcessResult(
      TerminalIncidentProcessDisposition.completed,
    );
  }
}

final class _HierarchyNativeBindings
    implements
        NativeBindings,
        NativeTextEditorBindings,
        NativeSavePanelBindings,
        NativeSplitViewPositionBindings {
  int _nextHandle = (1 << 32) | 100;
  final Map<int, String> objects = <int, String>{};
  final Map<Object, int> _handles = Map<Object, int>.identity();
  final Map<int, String> windowTitles = <int, String>{};
  final Map<int, Rect> windowFrames = <int, Rect>{};
  final Map<int, NativeRect> windowContentLayoutRects = <int, NativeRect>{};
  final Map<int, int> windowContentLayoutQueryCounts = <int, int>{};
  double windowContentLayoutHeightInset = 0;
  final Map<int, int> windowStyleMasks = <int, int>{};
  final Map<int, bool> windowFullscreenRequests = <int, bool>{};
  final Map<int, int> windowShowCounts = <int, int>{};
  final Map<int, int> windowSelectCounts = <int, int>{};
  final Map<int, int> windowFirstResponderCounts = <int, int>{};
  final Map<int, String> windowRepresentedFilePaths = <int, String>{};
  final Map<int, List<double>> windowTabColors = <int, List<double>>{};
  final Map<int, int> windowTabAccessoryShapes = <int, int>{};
  final Map<int, List<double>> windowTabAccessoryExtents =
      <int, List<double>>{};
  final Map<int, NativeViewConfiguration> viewConfigurations =
      <int, NativeViewConfiguration>{};
  final Map<int, NativeTextViewConfiguration> textViewConfigurations =
      <int, NativeTextViewConfiguration>{};
  final Map<int, NativeTextEditorConfiguration> textEditorConfigurations =
      <int, NativeTextEditorConfiguration>{};
  final Map<int, List<NativeTextEditorStyleRun>> textEditorStyleRuns =
      <int, List<NativeTextEditorStyleRun>>{};
  final Map<int, NativeTextEditorLineHighlight?> textEditorLineHighlights =
      <int, NativeTextEditorLineHighlight?>{};
  final Map<int, int> textEditorSelectionStarts = <int, int>{};
  final Map<int, int> textEditorSelectionLengths = <int, int>{};
  final Map<int, bool> textEditorEditable = <int, bool>{};
  final Map<int, bool> textEditorHasMarkedText = <int, bool>{};
  final Map<int, int> textEditorSelectionRevealCounts = <int, int>{};
  final Map<int, String> texts = <int, String>{};
  final Map<int, int> contentViews = <int, int>{};
  final Map<int, int> windowContentViewSetCounts = <int, int>{};
  final Map<int, int> firstResponders = <int, int>{};
  final Map<int, int> windowKeyEventRoutings = <int, int>{};
  final List<String> presentationCalls = <String>[];
  final List<List<int>> windowTabGroups = <List<int>>[];
  final Map<int, int> selectedTabWindows = <int, int>{};
  final Map<int, int> splitViewAxes = <int, int>{};
  final Map<int, List<int>> splitViewChildren = <int, List<int>>{};
  final Map<int, int> splitViewChildrenSetCounts = <int, int>{};
  final Map<int, double> splitViewFractions = <int, double>{};
  final Map<int, int> splitViewZoomedChildren = <int, int>{};
  final List<int> releaseOrder = <int>[];
  final List<String> terminationReplies = <String>[];
  NativeValueResult<NativeSavePanelResult> savePanelResult =
      const NativeValueResult<NativeSavePanelResult>.success(
        NativeSavePanelResult.cancelled(),
      );
  NativeSavePanelConfiguration? lastSavePanelConfiguration;
  int savePanelRunCount = 0;
  var terminationDeferralEnabled = false;

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
  NativeValueResult<NativeSavePanelResult> runSavePanel(
    NativeSavePanelConfiguration configuration,
  ) {
    if (savePanelResult.isSuccess) {
      lastSavePanelConfiguration = configuration;
      savePanelRunCount++;
    }
    return savePanelResult;
  }

  @override
  NativeCallResult applicationTerminate() => const NativeCallResult.success();

  @override
  NativeCallResult applicationSetTerminationRequestDeferral(bool enabled) {
    terminationDeferralEnabled = enabled;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult applicationReplyToTerminationRequest({
    required int operationId,
    required bool allow,
  }) {
    terminationReplies.add('$operationId:$allow');
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
    required int styleMask,
  }) {
    final NativeValueResult<int> result = _create('window');
    windowTitles[result.value!] = title;
    windowFrames[result.value!] = Rect.fromLTWH(x, y, width, height);
    windowContentLayoutRects[result.value!] = NativeRect(
      x: 0,
      y: 0,
      width: width,
      height: height - windowContentLayoutHeightInset,
    );
    windowStyleMasks[result.value!] = styleMask;
    return result;
  }

  @override
  NativeCallResult windowSetFrame({
    required int handle,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    windowFrames[handle] = Rect.fromLTWH(x, y, width, height);
    windowContentLayoutRects[handle] = NativeRect(
      x: 0,
      y: 0,
      width: width,
      height: height - windowContentLayoutHeightInset,
    );
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<NativeRect> windowGetContentLayoutRect(int handle) {
    windowContentLayoutQueryCounts[handle] =
        (windowContentLayoutQueryCounts[handle] ?? 0) + 1;
    final NativeRect? rect = windowContentLayoutRects[handle];
    return rect == null
        ? const NativeValueResult<NativeRect>.failure(2, 'unknown window')
        : NativeValueResult<NativeRect>.success(rect);
  }

  @override
  NativeCallResult windowSetFullscreen(int handle, bool enabled) {
    windowFullscreenRequests[handle] = enabled;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowShow(int handle) {
    windowShowCounts[handle] = (windowShowCounts[handle] ?? 0) + 1;
    presentationCalls.add('show:$handle');
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowClose(int handle) => const NativeCallResult.success();

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
  NativeCallResult windowSetTabAccessory({
    required int handle,
    required bool hasAccessory,
    required int shape,
    required double width,
    required double height,
    required double red,
    required double green,
    required double blue,
    required double alpha,
  }) {
    if (hasAccessory) {
      windowTabColors[handle] = <double>[red, green, blue, alpha];
      windowTabAccessoryShapes[handle] = shape;
      windowTabAccessoryExtents[handle] = <double>[width, height];
    } else {
      windowTabColors.remove(handle);
      windowTabAccessoryShapes.remove(handle);
      windowTabAccessoryExtents.remove(handle);
    }
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle) {
    contentViews[windowHandle] = viewHandle;
    windowContentViewSetCounts[windowHandle] =
        (windowContentViewSetCounts[windowHandle] ?? 0) + 1;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult windowSetKeyEventRouting(int handle, int routing) {
    windowKeyEventRoutings[handle] = routing;
    return const NativeCallResult.success();
  }

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
    _removeWindowFromTabGroups(handle);
    return const NativeCallResult.success();
  }

  void _removeWindowFromTabGroups(int handle) {
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
  }

  @override
  NativeCallResult windowSelectTab(int handle) {
    windowSelectCounts[handle] = (windowSelectCounts[handle] ?? 0) + 1;
    presentationCalls.add('select:$handle');
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
    presentationCalls.add('responder:$handle:$viewHandle');
    windowFirstResponderCounts[handle] =
        (windowFirstResponderCounts[handle] ?? 0) + 1;
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<int> viewCreate(NativeViewConfiguration configuration) {
    final NativeValueResult<int> result = _create('view');
    viewConfigurations[result.value!] = configuration;
    return result;
  }

  @override
  NativeValueResult<int> textViewCreate(
    NativeTextViewConfiguration configuration,
  ) {
    final NativeValueResult<int> result = _create('text-view');
    viewConfigurations[result.value!] = configuration.view;
    textViewConfigurations[result.value!] = configuration;
    texts[result.value!] = '';
    return result;
  }

  @override
  NativeCallResult textViewSetText(int handle, String text) {
    texts[handle] = text;
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<int> textEditorCreate(
    NativeTextEditorConfiguration configuration,
  ) {
    final NativeValueResult<int> result = _create('text-editor');
    final int handle = result.value!;
    viewConfigurations[handle] = configuration.presentation.view;
    textEditorConfigurations[handle] = configuration;
    textEditorStyleRuns[handle] = const <NativeTextEditorStyleRun>[];
    textEditorLineHighlights[handle] = null;
    textEditorSelectionStarts[handle] = 0;
    textEditorSelectionLengths[handle] = 0;
    textEditorEditable[handle] = configuration.initiallyEditable;
    textEditorHasMarkedText[handle] = false;
    textEditorSelectionRevealCounts[handle] = 0;
    texts[handle] = '';
    return result;
  }

  @override
  NativeCallResult textEditorSetDocument(
    int handle,
    NativeTextEditorDocument document,
  ) {
    texts[handle] = document.text;
    textEditorSelectionStarts[handle] = document.selectionStart;
    textEditorSelectionLengths[handle] = document.selectionLength;
    textEditorStyleRuns[handle] = List<NativeTextEditorStyleRun>.unmodifiable(
      document.styleRuns,
    );
    textEditorLineHighlights[handle] = null;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult textEditorSetStyleRuns(
    int handle,
    List<NativeTextEditorStyleRun> styleRuns,
  ) {
    textEditorStyleRuns[handle] = List<NativeTextEditorStyleRun>.unmodifiable(
      styleRuns,
    );
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult textEditorSetLineHighlight(
    int handle,
    NativeTextEditorLineHighlight? highlight,
  ) {
    textEditorLineHighlights[handle] = highlight;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult textEditorSetEditable(int handle, bool editable) {
    textEditorEditable[handle] = editable;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult textEditorSetSelection(
    int handle, {
    required int start,
    required int length,
  }) {
    textEditorSelectionStarts[handle] = start;
    textEditorSelectionLengths[handle] = length;
    return const NativeCallResult.success();
  }

  @override
  NativeCallResult textEditorScrollSelectionToVisible(int handle) {
    textEditorSelectionRevealCounts[handle] =
        textEditorSelectionRevealCounts[handle]! + 1;
    return const NativeCallResult.success();
  }

  @override
  NativeValueResult<NativeTextEditorSnapshot> textEditorSnapshot(int handle) =>
      NativeValueResult<NativeTextEditorSnapshot>.success(
        NativeTextEditorSnapshot(
          text: texts[handle]!,
          selectionStart: textEditorSelectionStarts[handle]!,
          selectionLength: textEditorSelectionLengths[handle]!,
          isEditable: textEditorEditable[handle]!,
          hasMarkedText: textEditorHasMarkedText[handle]!,
        ),
      );

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
    splitViewChildrenSetCounts[splitViewHandle] =
        (splitViewChildrenSetCounts[splitViewHandle] ?? 0) + 1;
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
  NativeValueResult<double> splitViewGetFraction(int handle) {
    final double? fraction = splitViewFractions[handle];
    if (fraction == null) {
      return const NativeValueResult<double>.failure(
        3,
        'split view handle is invalid',
      );
    }
    return NativeValueResult<double>.success(fraction);
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
    _removeWindowFromTabGroups(handle);
    objects.remove(handle);
    windowTitles.remove(handle);
    windowFrames.remove(handle);
    windowContentLayoutRects.remove(handle);
    windowContentLayoutQueryCounts.remove(handle);
    windowStyleMasks.remove(handle);
    windowFullscreenRequests.remove(handle);
    windowShowCounts.remove(handle);
    windowSelectCounts.remove(handle);
    windowFirstResponderCounts.remove(handle);
    windowRepresentedFilePaths.remove(handle);
    windowTabColors.remove(handle);
    windowTabAccessoryShapes.remove(handle);
    windowTabAccessoryExtents.remove(handle);
    viewConfigurations.remove(handle);
    textViewConfigurations.remove(handle);
    textEditorConfigurations.remove(handle);
    textEditorStyleRuns.remove(handle);
    textEditorLineHighlights.remove(handle);
    textEditorSelectionStarts.remove(handle);
    textEditorSelectionLengths.remove(handle);
    textEditorEditable.remove(handle);
    textEditorHasMarkedText.remove(handle);
    textEditorSelectionRevealCounts.remove(handle);
    texts.remove(handle);
    contentViews.remove(handle);
    firstResponders.remove(handle);
    windowKeyEventRoutings.remove(handle);
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
