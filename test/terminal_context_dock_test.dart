import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalContextDockTests();

Future<void> runTerminalContextDockTests() async {
  await _testWindowPaneStateAndBounds();
  await _testActionFocusOwnershipAndAvailability();
  await _testNavigatorKeyRoutingNeverFallsThrough();
  await _testDirectoryTreeFollowsPaneAndCancelsHiddenWork();
  await _testDirectoryRevealRejectsExpansionCap();
  await _testProcessCoordinatorRefreshPrivacyAndCancellation();
  _testPrivacyPolicyDistinguishesIdleLineEditing();
  await _testPathHandoffPolicyAndExactPayload();
}

Future<void> _testDirectoryRevealRejectsExpansionCap() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final TerminalContextDockState dock = TerminalContextDockState()
    ..synchronize(harness.state)
    ..toggleVisibility(window.id, paneId);
  final TerminalDirectorySnapshotService snapshots =
      TerminalDirectorySnapshotService(fileSystem: _CapDirectoryFileSystem());
  const TerminalWorkingDirectoryResolver workingDirectoryResolver =
      TerminalWorkingDirectoryResolver();
  final TerminalContextDockDirectoryController controller =
      TerminalContextDockDirectoryController(
        applicationState: harness.state,
        dockState: dock,
        snapshotService: snapshots,
        searchService: TerminalFileSearchService(
          directorySnapshots: snapshots,
          systemIndex: const _ContextDockSystemIndex(),
        ),
        resolveWorkingDirectory: (PaneId candidate, int generation) {
          final TerminalPaneProcessSnapshot process = harness.state
              .paneForId(candidate)!
              .processSnapshot();
          return workingDirectoryResolver.resolve(
            sessionId: process.sessionId,
            generation: generation,
            processSnapshot: process,
            reportedWorkingDirectory: null,
            processWorkingDirectory: null,
            launchWorkingDirectory: '/cap',
          );
        },
      );
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  for (
    var index = 0;
    index <
        TerminalContextDockDirectoryLimits.maximumExpandedDirectoriesPerPane;
    index++
  ) {
    dock.setSelectedResultIndex(window.id, index);
    _expect(
      controller.handleTreeIntent(
        window.id,
        TerminalContextDockTreeIntent.expand,
      ),
      'fixture directory $index fills one bounded expansion slot',
    );
    await _waitUntil(() => controller.activeOperationCount == 0);
  }
  _expect(
    dock.confirmNavigatorInput(
      dock.requestNavigatorFocus(
        window.id,
        paneId,
        TerminalContextDockNavigatorMode.search,
      ),
    ),
    'cap test transfers input to Search',
  );
  dock.setQuery(window.id, 'target');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  final TerminalContextDockDirectorySnapshot before = controller
      .snapshotForWindow(window.id)!;
  _expect(
    before.isSearch &&
        before.rows.single.entry.path == '/cap/zz-branch/target.txt' &&
        !controller.handleTreeIntent(
          window.id,
          TerminalContextDockTreeIntent.toggle,
        ),
    'reveal beyond the expansion cap is rejected before changing mode',
  );
  final TerminalContextDockDirectorySnapshot after = controller
      .snapshotForWindow(window.id)!;
  _expect(
    dock.snapshotForWindow(window.id)!.pane.navigatorMode ==
            TerminalContextDockNavigatorMode.search &&
        after.isSearch &&
        after.rows.single.entry.path == '/cap/zz-branch/target.txt',
    'cap rejection retains Search result, selection, and tree authority',
  );
  controller.dispose();
  dock.dispose();
  await harness.state.shutdown();
}

void _testPrivacyPolicyDistinguishesIdleLineEditing() {
  const PaneId paneId = PaneId(1);
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: paneId,
    generation: 1,
  );
  TerminalPaneProcessSnapshot process({required bool foreground}) =>
      TerminalPaneProcessSnapshot.available(
        sessionId: sessionId,
        childProcessId: 10,
        owningProcessGroup: 10,
        foregroundProcessGroup: foreground ? 11 : 10,
        terminalEchoEnabled: false,
      );
  TerminalSecureKeyboardEntryStatus secure({required bool manual}) =>
      TerminalSecureKeyboardEntryStatus(
        mode: manual
            ? TerminalSecureKeyboardEntryMode.manual
            : TerminalSecureKeyboardEntryMode.automatic,
        manualRequested: manual,
        automaticEnabled: true,
        indicationEnabled: true,
        applicationActive: true,
        desired: true,
        ownedEnabled: true,
        systemEnabled: true,
        lastOsStatus: 0,
        targetIdentity: paneId,
        terminalEchoEnabled: false,
        failure: null,
      );

  _expect(
    TerminalContextDockPrivacyPolicy.canObserve(
      paneId: paneId,
      process: process(foreground: false),
      secureInput: secure(manual: false),
    ),
    'automatic ECHO-off from idle shell line editing keeps Navigator usable',
  );
  _expect(
    !TerminalContextDockPrivacyPolicy.canObserve(
      paneId: paneId,
      process: process(foreground: true),
      secureInput: secure(manual: false),
    ),
    'automatic ECHO-off with a foreground process hides filesystem context',
  );
  _expect(
    !TerminalContextDockPrivacyPolicy.canObserve(
      paneId: paneId,
      process: process(foreground: false),
      secureInput: secure(manual: true),
    ),
    'manual secure input hides filesystem context even at an idle shell',
  );
  _expect(
    !TerminalContextDockPrivacyPolicy.canObserve(
      paneId: paneId,
      process: TerminalPaneProcessSnapshot.unavailable(
        sessionId: sessionId,
        terminalEchoEnabled: true,
      ),
    ),
    'unavailable process identity fails closed for filesystem observation',
  );
}

Future<void> _testProcessCoordinatorRefreshPrivacyAndCancellation() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId firstPane = window.selectedTab.focusedPaneId;
  final TerminalSessionId firstSession = TerminalSessionId(
    paneId: firstPane,
    generation: 1,
  );
  final TerminalContextDockState dock = TerminalContextDockState()
    ..synchronize(harness.state)
    ..toggleVisibility(window.id, firstPane);
  final _ProcessScheduler scheduler = _ProcessScheduler();
  var foregroundGroup = firstPane.value;
  var owningShellCommand = false;
  var privacyAllowed = true;
  var canPresent = true;
  var activeSession = firstSession;
  var focusCount = 0;
  var changedCount = 0;
  final List<Completer<PtyForegroundJobSnapshot?>> richRequests =
      <Completer<PtyForegroundJobSnapshot?>>[];

  TerminalPaneProcessSnapshot resolveProcess(PaneId paneId) {
    _expect(
      paneId == activeSession.paneId,
      'process resolver targets the current focused pane',
    );
    return TerminalPaneProcessSnapshot.available(
      sessionId: activeSession,
      childProcessId: paneId.value,
      owningProcessGroup: paneId.value,
      foregroundProcessGroup: foregroundGroup,
      owningShellCommandActive: owningShellCommand,
      terminalEchoEnabled: privacyAllowed ? true : false,
    );
  }

  final TerminalContextDockProcessController controller =
      TerminalContextDockProcessController(
        applicationState: harness.state,
        dockState: dock,
        resolveProcessSnapshot: resolveProcess,
        resolveForegroundJob: (PaneId paneId, TerminalSessionId sessionId) {
          _expect(
            paneId == activeSession.paneId && sessionId == activeSession,
            'rich resolver receives the current session authority',
          );
          final Completer<PtyForegroundJobSnapshot?> request =
              Completer<PtyForegroundJobSnapshot?>();
          richRequests.add(request);
          return request.future;
        },
        canPresentWindow: (_) => canPresent,
        canObserveProcess: (_, _) => privacyAllowed,
        focusTerminal: (TerminalContextDockFocusRequest request) {
          focusCount++;
          return request.windowId == window.id &&
              request.paneId == activeSession.paneId;
        },
        scheduleTask: scheduler.schedule,
        monotonicMicros: () => scheduler.nowMicros,
        onChanged: () => changedCount++,
      );

  controller.synchronize();
  _expect(
    controller.snapshotForWindow(window.id)!.mode ==
            TerminalContextDockContentMode.directoryNavigator &&
        controller.canObserveDirectoryPane(firstPane) &&
        controller.activeOperationCount == 0 &&
        controller.activeTimerCount == 1,
    'idle visible shell selects Directory Navigator with one bounded poll',
  );
  final TerminalContextDockFocusRequest navigator = dock.requestSearchFocus(
    window.id,
    firstPane,
  );
  _expect(
    dock.confirmNavigatorInput(navigator),
    'process test starts with Navigator input ownership',
  );

  foregroundGroup = firstPane.value + 10;
  controller.scheduleSynchronize();
  scheduler.elapse(TerminalContextDockProcessLimits.terminalChangeDebounce);
  _expect(
    controller.snapshotForWindow(window.id)!.directorySuspended &&
        richRequests.isEmpty &&
        dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'foreground candidate immediately suspends directory work without rich observation',
  );
  foregroundGroup = firstPane.value;
  controller.scheduleSynchronize();
  scheduler.elapse(TerminalContextDockProcessLimits.terminalChangeDebounce);
  _expect(
    controller.snapshotForWindow(window.id)!.mode ==
            TerminalContextDockContentMode.directoryNavigator &&
        controller.canObserveDirectoryPane(firstPane) &&
        richRequests.isEmpty &&
        focusCount == 0,
    'short command returns to Directory Navigator without Process Inspector flicker',
  );

  foregroundGroup = firstPane.value + 10;
  scheduler.elapse(const Duration(milliseconds: 100));
  _expect(
    controller.snapshotForWindow(window.id)!.directorySuspended &&
        richRequests.isEmpty,
    'silent foreground command is discovered by the 250 ms state poll',
  );
  scheduler.elapse(TerminalContextDockProcessLimits.foregroundActivationDelay);
  TerminalContextDockContentSnapshot content = controller.snapshotForWindow(
    window.id,
  )!;
  _expect(
    content.mode == TerminalContextDockContentMode.foregroundJob &&
        content.process?.status == TerminalContextDockProcessStatus.loading &&
        controller.activeOperationCount == 1 &&
        richRequests.length == 1 &&
        focusCount == 1 &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'stable foreground command enters Process Inspector and returns input to Terminal',
  );
  final int firstEpoch = content.process!.identity!.epoch;
  richRequests[0].complete(
    _foregroundJobFixture(
      sessionId: firstSession,
      foregroundProcessGroup: foregroundGroup,
      memberCount: 2,
      elapsedMicroseconds: 1000,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  content = controller.snapshotForWindow(window.id)!;
  _expect(
    content.process?.status == TerminalContextDockProcessStatus.ready &&
        content.process?.members.length == 2 &&
        content.process?.executablePath == '/bin/process-0' &&
        content.process?.arguments.join(' ') == 'process-0 --fixture' &&
        controller.activeOperationCount == 0,
    'matching rich result becomes one immutable ready projection',
  );

  scheduler.elapse(const Duration(milliseconds: 500));
  _expect(
    richRequests.length == 1 &&
        controller.snapshotForWindow(window.id)!.process!.elapsedMicroseconds >=
            501000,
    'elapsed advances from cached monotonic time without another rich call',
  );
  scheduler.elapse(const Duration(milliseconds: 750));
  _expect(
    richRequests.length == 2 && controller.activeOperationCount == 1,
    'member inventory refresh starts no more than once per second',
  );
  richRequests[1].complete(
    _foregroundJobFixture(
      sessionId: firstSession,
      foregroundProcessGroup: foregroundGroup,
      memberCount: 3,
      elapsedMicroseconds: 1250000,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    controller.snapshotForWindow(window.id)!.process!.members.length == 3,
    'one-second refresh replaces a changed pipeline member inventory',
  );

  scheduler.elapse(const Duration(seconds: 1));
  _expect(
    richRequests.length == 3 && controller.activeOperationCount == 1,
    'only one refresh request may be in flight for a window',
  );
  foregroundGroup = firstPane.value + 20;
  controller.synchronize();
  _expect(
    controller.activeOperationCount == 0 &&
        controller.snapshotForWindow(window.id)!.directorySuspended &&
        controller.snapshotForWindow(window.id)!.process == null,
    'PGID replacement cancels and clears the prior content generation',
  );
  richRequests[2].complete(
    _foregroundJobFixture(
      sessionId: firstSession,
      foregroundProcessGroup: firstPane.value + 10,
      memberCount: 1,
      elapsedMicroseconds: 1,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    controller.snapshotForWindow(window.id)!.process == null,
    'late result from a replaced foreground group is ignored',
  );
  scheduler.elapse(TerminalContextDockProcessLimits.foregroundActivationDelay);
  _expect(
    richRequests.length == 4 && controller.activeOperationCount == 1,
    'replacement foreground group receives a fresh epoch and observation',
  );
  privacyAllowed = false;
  controller.synchronize();
  content = controller.snapshotForWindow(window.id)!;
  _expect(
    content.mode == TerminalContextDockContentMode.protected &&
        content.process == null &&
        controller.activeOperationCount == 0 &&
        !controller.canObserveDirectoryPane(firstPane),
    'ECHO-off privacy transition synchronously clears all process and directory content',
  );
  richRequests[3].complete(
    _foregroundJobFixture(
      sessionId: firstSession,
      foregroundProcessGroup: foregroundGroup,
      memberCount: 1,
      elapsedMicroseconds: 1,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    controller.snapshotForWindow(window.id)!.process == null,
    'protected state rejects a late content-bearing result',
  );

  privacyAllowed = true;
  controller.synchronize();
  scheduler.elapse(TerminalContextDockProcessLimits.foregroundActivationDelay);
  richRequests[4].complete(
    _foregroundJobFixture(
      sessionId: firstSession,
      foregroundProcessGroup: foregroundGroup,
      memberCount: 1,
      elapsedMicroseconds: 2000,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  content = controller.snapshotForWindow(window.id)!;
  _expect(
    content.process!.identity!.epoch > firstEpoch &&
        content.process!.identity!.foregroundProcessGroup == foregroundGroup,
    'privacy recovery starts a new foreground identity instead of reviving stale content',
  );

  foregroundGroup = firstPane.value;
  owningShellCommand = true;
  controller.synchronize();
  content = controller.snapshotForWindow(window.id)!;
  _expect(
    content.mode == TerminalContextDockContentMode.shellOwnedCommand &&
        content.process?.status ==
            TerminalContextDockProcessStatus.shellOwned &&
        content.process?.executablePath == null &&
        !controller.canObserveDirectoryPane(firstPane),
    'shell-owned command has observed elapsed status without invented argv',
  );
  scheduler.elapse(const Duration(seconds: 1));
  _expect(
    controller.snapshotForWindow(window.id)!.process!.elapsedMicroseconds >=
        Duration.microsecondsPerSecond,
    'shell-owned elapsed time advances from observation time',
  );
  owningShellCommand = false;
  controller.synchronize();
  _expect(
    controller.canObserveDirectoryPane(firstPane) &&
        controller.snapshotForWindow(window.id)!.process == null,
    'idle transition clears shell status before resuming directory work',
  );

  final TerminalPane secondPane = await harness.state.splitPane(
    firstPane,
    harness.configuration(),
    axis: TerminalSplitAxis.horizontal,
  );
  await secondPane.start();
  activeSession = secondPane.sessionId;
  foregroundGroup = secondPane.id.value;
  controller.synchronize();
  _expect(
    controller.snapshotForWindow(window.id)!.paneId == secondPane.id &&
        controller.canObserveDirectoryPane(secondPane.id) &&
        !controller.canObserveDirectoryPane(firstPane),
    'focused pane replacement discards the previous pane projection',
  );
  activeSession = TerminalSessionId(
    paneId: secondPane.id,
    generation: activeSession.generation + 1,
  );
  controller.synchronize();
  _expect(
    controller.snapshotForWindow(window.id)!.sessionId == activeSession &&
        controller.canObserveDirectoryPane(secondPane.id),
    'same-pane session replacement starts a fresh content generation',
  );
  canPresent = false;
  controller.synchronize();
  _expect(
    controller.snapshotForWindow(window.id) == null &&
        controller.activeOperationCount == 0 &&
        controller.activeTimerCount == 0,
    'non-presentable window stops polling and drops retained content',
  );
  canPresent = true;
  controller.synchronize();
  dock.toggleVisibility(window.id, secondPane.id);
  controller.synchronize();
  _expect(
    controller.snapshotForWindow(window.id) == null &&
        controller.activeTimerCount == 0,
    'hidden Context Dock owns no process timer or snapshot',
  );

  dock.toggleVisibility(window.id, secondPane.id);
  controller.synchronize();
  foregroundGroup = secondPane.id.value + 10;
  controller.scheduleSynchronize();
  scheduler.elapse(TerminalContextDockProcessLimits.terminalChangeDebounce);
  scheduler.elapse(TerminalContextDockProcessLimits.foregroundActivationDelay);
  _expect(
    controller.activeOperationCount == 1 && richRequests.length == 6,
    'dispose fixture has one generation-bound rich operation',
  );
  controller.dispose();
  controller.dispose();
  _expect(
    controller.isDisposed &&
        controller.activeOperationCount == 0 &&
        controller.activeTimerCount == 0 &&
        controller.snapshotForWindow(window.id) == null,
    'dispose cancels every logical operation and timer idempotently',
  );
  richRequests[5].complete(null);
  await Future<void>.delayed(Duration.zero);
  _expect(changedCount > 0, 'content transitions notify their presenter');
  dock.dispose();
  await harness.state.shutdown();
}

PtyForegroundJobSnapshot _foregroundJobFixture({
  required TerminalSessionId sessionId,
  required int foregroundProcessGroup,
  required int memberCount,
  required int elapsedMicroseconds,
}) {
  final List<PtyForegroundProcessSnapshot> members =
      <PtyForegroundProcessSnapshot>[
        for (var index = 0; index < memberCount; ++index)
          PtyForegroundProcessSnapshot(
            processId: foregroundProcessGroup + index,
            startTimeSeconds: 1,
            startTimeMicroseconds: index,
            startAbsoluteTime: 100 + index,
            elapsedMicroseconds: elapsedMicroseconds,
            name: 'process-$index',
          ),
      ];
  return PtyForegroundJobSnapshot(
    disposition: PtyForegroundJobDisposition.available,
    childProcessId: sessionId.paneId.value,
    owningProcessGroup: sessionId.paneId.value,
    foregroundProcessGroup: foregroundProcessGroup,
    sampledAbsoluteTime: 1000,
    jobElapsedMicroseconds: elapsedMicroseconds,
    members: members,
    totalMemberCount: memberCount,
    omittedMemberCount: 0,
    memberIssueCount: 0,
    primaryIndex: 0,
    observationSystemError: 0,
    executablePath: '/bin/process-0',
    executablePathSystemError: 0,
    arguments: const <String>['process-0', '--fixture'],
    totalArgumentCount: 2,
    omittedArgumentCount: 0,
    argumentsTruncated: false,
    argumentsSystemError: 0,
    hasExited: false,
  );
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
        TerminalContextDockLimits.defaultWidth == 380 &&
        snapshot.width == TerminalContextDockLimits.defaultWidth &&
        snapshot.pane.showHiddenEntries &&
        snapshot.inputOwner == TerminalContextDockInputOwner.terminal,
    'a new window starts hidden with dotfiles shown while terminal retains input',
  );

  final TerminalContextDockFocusRequest request = dock.requestSearchFocus(
    window.id,
    firstPane,
  );
  _expect(
    dock.snapshotForWindow(window.id)!.isVisible &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput &&
        dock.confirmNavigatorInput(request) &&
        dock.snapshotForWindow(window.id)!.pane.navigatorMode ==
            TerminalContextDockNavigatorMode.search,
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

  final TerminalContextDockFocusRequest goToRequest = dock
      .requestNavigatorFocus(
        window.id,
        firstPane,
        TerminalContextDockNavigatorMode.goTo,
      );
  _expect(dock.confirmNavigatorInput(goToRequest), 'Go To focus is current');
  dock.setQuery(window.id, 'beta', requireNavigatorInput: true);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    snapshot.pane.navigatorMode == TerminalContextDockNavigatorMode.goTo &&
        snapshot.pane.query == 'beta' &&
        snapshot.pane.searchQuery == 'alpha' &&
        snapshot.pane.goToQuery == 'beta',
    'Search and Go To retain independent pane-local queries',
  );
  final TerminalContextDockFocusRequest moveRequest = dock
      .requestNavigatorFocus(
        window.id,
        firstPane,
        TerminalContextDockNavigatorMode.move,
      );
  _expect(dock.confirmNavigatorInput(moveRequest), 'Move focus is current');
  _expect(
    dock.snapshotForWindow(window.id)!.pane.query.isEmpty,
    'Move exposes no editable query',
  );
  _expectThrows<StateError>(
    () => dock.setQuery(window.id, 'not accepted'),
    'Move rejects direct query mutation',
  );
  final TerminalContextDockFocusRequest restoredSearch = dock
      .requestNavigatorFocus(
        window.id,
        firstPane,
        TerminalContextDockNavigatorMode.search,
      );
  _expect(
    dock.confirmNavigatorInput(restoredSearch) &&
        dock.snapshotForWindow(window.id)!.pane.query == 'alpha',
    'returning to Search restores its retained query',
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
        dock.snapshotForWindow(window.id)!.pane.query.isEmpty &&
        dock.snapshotForWindow(window.id)!.pane.showHiddenEntries,
    'the window follows its selected tab focused pane with a visible-dotfile default',
  );
  dock.toggleHiddenEntries(window.id, second.id);
  _expect(
    !dock.snapshotForWindow(window.id)!.pane.showHiddenEntries,
    'hidden-entry visibility can be toggled for the focused pane',
  );
  harness.state.focusPane(window.selectedTab.id, firstPane);
  dock.synchronize(harness.state);
  _expect(
    dock.snapshotForWindow(window.id)!.pane.query == 'alpha' &&
        dock.snapshotForWindow(window.id)!.pane.showHiddenEntries,
    'pane-local navigation and hidden-entry visibility survive focus round trips',
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
  final TerminalDirectorySnapshotService snapshots =
      TerminalDirectorySnapshotService(fileSystem: files);
  const TerminalWorkingDirectoryResolver workingDirectoryResolver =
      TerminalWorkingDirectoryResolver();
  String root = '/root';
  bool remote = false;
  bool canObserve = true;
  var resolutionCount = 0;
  final TerminalContextDockDirectoryController controller =
      TerminalContextDockDirectoryController(
        applicationState: harness.state,
        dockState: dock,
        snapshotService: snapshots,
        searchService: TerminalFileSearchService(
          directorySnapshots: snapshots,
          systemIndex: const _ContextDockSystemIndex(),
          pathSnapshot: (String path) async => TerminalDirectoryEntrySnapshot(
            name: path.substring(path.lastIndexOf('/') + 1),
            path: path,
            kind: TerminalDirectoryEntryKind.file,
            isHidden: false,
            metadata:
                const TerminalDirectoryEntryMetadataSnapshot.unavailable(),
          ),
        ),
        resolveWorkingDirectory: (PaneId paneId, int generation) {
          resolutionCount++;
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
        canObservePane: (_) => canObserve,
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
            'folder,.secret,deep,nested.txt,.hidden,readme.md' &&
        snapshot.rows
                .firstWhere(
                  (TerminalContextDockDirectoryRow row) =>
                      row.entry.path == '/root/folder/.secret',
                )
                .depth ==
            1 &&
        snapshot.rows
                .firstWhere(
                  (TerminalContextDockDirectoryRow row) =>
                      row.entry.path == '/root/folder/nested.txt',
                )
                .entry
                .metadata
                .size ==
            7,
    'expanded folder loads hidden and visible children while retaining metadata',
  );
  _expect(
    controller.handleTreeIntent(
          window.id,
          TerminalContextDockTreeIntent.toggle,
        ) &&
        controller.snapshotForWindow(window.id)!.rows.length == 3 &&
        !controller.snapshotForWindow(window.id)!.rows.first.isExpanded &&
        dock.snapshotForWindow(window.id)!.pane.selectedResultIndex == 0,
    'Return toggle closes an expanded folder and retains its row selection',
  );
  _expect(
    controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.toggle,
    ),
    'Return toggle reopens a collapsed folder',
  );
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  dock.setSelectedResultIndex(window.id, snapshot.rows.length - 1);
  _expect(
    !controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.toggle,
    ),
    'Return toggle leaves a selected file unchanged',
  );
  dock.setSelectedResultIndex(window.id, 0);
  _expect(
    dock.confirmNavigatorInput(
      dock.requestNavigatorFocus(
        window.id,
        firstPane,
        TerminalContextDockNavigatorMode.search,
      ),
    ),
    'Search takes generation-checked Navigator input ownership',
  );
  dock.setQuery(window.id, 'readme');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.isSearch &&
        snapshot.rows.length == 2 &&
        snapshot.rows.map((value) => value.searchSource).toSet().containsAll(
          const <TerminalFileSearchSource>{
            TerminalFileSearchSource.currentSubtree,
            TerminalFileSearchSource.systemIndex,
          },
        ),
    'non-empty query progressively replaces tree rows with merged search rows',
  );
  final int externalResult = snapshot.rows.indexWhere(
    (TerminalContextDockDirectoryRow row) =>
        row.entry.path == '/indexed/readme-global.md',
  );
  dock.setSelectedResultIndex(window.id, externalResult);
  _expect(
    !controller.handleTreeIntent(
          window.id,
          TerminalContextDockTreeIntent.toggle,
        ) &&
        dock.snapshotForWindow(window.id)!.pane.navigatorMode ==
            TerminalContextDockNavigatorMode.search,
    'an external Search result cannot replace the working-directory root',
  );
  dock.setQuery(window.id, '');
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    !snapshot.isSearch &&
        snapshot.rows.length == 6 &&
        snapshot.rows.first.isExpanded,
    'clearing query restores the retained tree expansion context',
  );
  dock.setNavigatorMode(
    window.id,
    TerminalContextDockNavigatorMode.goTo,
    requireNavigatorInput: true,
  );
  dock.setQuery(window.id, 'readme');
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    !snapshot.isSearch &&
        snapshot
                .rows[dock
                    .snapshotForWindow(window.id)!
                    .pane
                    .selectedResultIndex]
                .entry
                .name ==
            'readme.md',
    'Go To moves selection to a visible match without replacing the tree',
  );
  dock.setSelectedResultIndex(window.id, 0);
  _expect(
    controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.collapse,
    ),
    'the visible folder can be collapsed before a deep Go To',
  );
  dock.setQuery(window.id, 'target');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  final int deepTarget = dock
      .snapshotForWindow(window.id)!
      .pane
      .selectedResultIndex;
  _expect(
    !snapshot.isSearch &&
        snapshot.rows[deepTarget].entry.path ==
            '/root/folder/deep/target.txt' &&
        snapshot.rows
            .firstWhere(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == '/root/folder',
            )
            .isExpanded &&
        snapshot.rows
            .firstWhere(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == '/root/folder/deep',
            )
            .isExpanded,
    'deep Go To lazily expands observed ancestors and reveals the match',
  );
  _expect(
    controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.collapse,
    ),
    'collapse on the selected deep file closes its nearest expanded ancestor',
  );
  dock.setNavigatorMode(
    window.id,
    TerminalContextDockNavigatorMode.search,
    requireNavigatorInput: true,
  );
  dock.setQuery(window.id, 'deep');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  _expect(
    controller.handleTreeIntent(
      window.id,
      TerminalContextDockTreeIntent.toggle,
    ),
    'Return activates a current-root Search directory in the tree',
  );
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  final int revealedDirectory = dock
      .snapshotForWindow(window.id)!
      .pane
      .selectedResultIndex;
  _expect(
    dock.snapshotForWindow(window.id)!.pane.navigatorMode ==
            TerminalContextDockNavigatorMode.move &&
        snapshot.rows[revealedDirectory].entry.path == '/root/folder/deep' &&
        snapshot.rows[revealedDirectory].isExpanded &&
        snapshot.rows.any(
          (TerminalContextDockDirectoryRow row) =>
              row.entry.path == '/root/folder/deep/target.txt',
        ),
    'Search activation enters Move, selects the directory, and expands it',
  );
  dock.setNavigatorMode(
    window.id,
    TerminalContextDockNavigatorMode.move,
    requireNavigatorInput: true,
  );
  _expect(
    dock.snapshotForWindow(window.id)!.pane.searchQuery == 'deep' &&
        dock.snapshotForWindow(window.id)!.pane.goToQuery == 'target' &&
        !controller.snapshotForWindow(window.id)!.isSearch,
    'Move retains mode queries while exposing only the current tree',
  );

  dock.setNavigatorMode(
    window.id,
    TerminalContextDockNavigatorMode.search,
    requireNavigatorInput: true,
  );
  dock.setQuery(window.id, 'inside');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.isSearch &&
        snapshot.rows.length == 1 &&
        snapshot.rows.single.entry.path == '/root/folder/.secret/inside.txt',
    'Search includes a file below a dot-prefixed directory while hidden entries are shown',
  );
  dock.toggleHiddenEntries(window.id, firstPane);
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    !dock.snapshotForWindow(window.id)!.pane.showHiddenEntries &&
        snapshot.isSearch &&
        snapshot.rows.isEmpty &&
        dock.snapshotForWindow(window.id)!.pane.query == 'inside' &&
        controller.activeOperationCount == 0,
    'hiding dot entries immediately filters Search without discarding its query',
  );
  dock.setNavigatorMode(
    window.id,
    TerminalContextDockNavigatorMode.goTo,
    requireNavigatorInput: true,
  );
  dock.setQuery(window.id, 'inside');
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    !snapshot.isSearch &&
        snapshot.rows.every(
          (TerminalContextDockDirectoryRow row) =>
              !row.entry.path.contains('/.'),
        ),
    'Go To neither exposes nor reveals a hidden-directory descendant while hidden entries are off',
  );
  dock.toggleHiddenEntries(window.id, firstPane);
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);
  snapshot = controller.snapshotForWindow(window.id)!;
  final int hiddenTarget = dock
      .snapshotForWindow(window.id)!
      .pane
      .selectedResultIndex;
  _expect(
    dock.snapshotForWindow(window.id)!.pane.showHiddenEntries &&
        snapshot.rows[hiddenTarget].entry.path ==
            '/root/folder/.secret/inside.txt' &&
        snapshot.rows
            .firstWhere(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == '/root/folder/.secret',
            )
            .isExpanded,
    're-enabling hidden entries lets Go To expand and select a hidden subtree',
  );
  dock.toggleHiddenEntries(window.id, firstPane);
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    !snapshot.rows.any(
          (TerminalContextDockDirectoryRow row) =>
              row.entry.path.contains('/.'),
        ) &&
        dock.snapshotForWindow(window.id)!.pane.selectedResultIndex <
            snapshot.rows.length,
    'hiding a selected hidden target clamps selection to the visible tree',
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
        snapshot.rows.single.entry.name == 'other.txt' &&
        dock.snapshotForWindow(window.id)!.pane.showHiddenEntries,
    'focused pane change projects the new pane cwd with independent hidden visibility',
  );

  final int resolutionBaseline = resolutionCount;
  canObserve = false;
  controller.synchronize();
  snapshot = controller.snapshotForWindow(window.id)!;
  _expect(
    snapshot.status == TerminalContextDockDirectoryStatus.privacyUnavailable &&
        snapshot.workingDirectory == null &&
        snapshot.rows.isEmpty &&
        controller.activeOperationCount == 0 &&
        resolutionCount == resolutionBaseline,
    'protected input cancels work and exposes neither cwd nor retained rows',
  );
  canObserve = true;
  controller.synchronize();
  await _waitUntil(() => controller.activeOperationCount == 0);

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
  dock.focusTerminal(window.id, secondPane.id);
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
        name: '.secret',
        path: '/root/folder/.secret',
        kind: TerminalDirectoryEntryKind.directory,
      );
      yield const TerminalDirectoryFileSystemEntry(
        name: 'deep',
        path: '/root/folder/deep',
        kind: TerminalDirectoryEntryKind.directory,
      );
      yield const TerminalDirectoryFileSystemEntry(
        name: 'nested.txt',
        path: '/root/folder/nested.txt',
        kind: TerminalDirectoryEntryKind.file,
      );
      return;
    }
    if (rootPath == '/root/folder/.secret') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'inside.txt',
        path: '/root/folder/.secret/inside.txt',
        kind: TerminalDirectoryEntryKind.file,
      );
      return;
    }
    if (rootPath == '/root/folder/deep') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'target.txt',
        path: '/root/folder/deep/target.txt',
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

final class _CapDirectoryFileSystem implements TerminalDirectoryFileSystem {
  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    if (rootPath == '/cap') {
      for (
        var index = 0;
        index <
            TerminalContextDockDirectoryLimits
                .maximumExpandedDirectoriesPerPane;
        index++
      ) {
        final String name = 'dir${index.toString().padLeft(2, '0')}';
        yield TerminalDirectoryFileSystemEntry(
          name: name,
          path: '/cap/$name',
          kind: TerminalDirectoryEntryKind.directory,
        );
      }
      yield const TerminalDirectoryFileSystemEntry(
        name: 'zz-branch',
        path: '/cap/zz-branch',
        kind: TerminalDirectoryEntryKind.directory,
      );
      return;
    }
    if (rootPath == '/cap/zz-branch') {
      yield const TerminalDirectoryFileSystemEntry(
        name: 'target.txt',
        path: '/cap/zz-branch/target.txt',
        kind: TerminalDirectoryEntryKind.file,
      );
    }
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1, mode: 0x1ed);
}

final class _ContextDockSystemIndex implements TerminalSystemFileIndex {
  const _ContextDockSystemIndex();

  @override
  TerminalSystemFileIndexOperation start(TerminalFileSearchQuery query) =>
      const _ContextDockSystemIndexOperation();
}

final class _ContextDockSystemIndexOperation
    implements TerminalSystemFileIndexOperation {
  const _ContextDockSystemIndexOperation();

  @override
  Future<TerminalSystemFileIndexSnapshot> get result async =>
      TerminalSystemFileIndexSnapshot(
        disposition: TerminalSystemFileIndexDisposition.complete,
        paths: const <String>['/indexed/readme-global.md'],
      );

  @override
  void cancel() {}
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
  var mutateDuringProjection = false;
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
        onChanged: () {
          changed++;
          if (mutateDuringProjection) {
            mutateDuringProjection = false;
            dock.setResultCount(window.id, 3);
          }
        },
      );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: coordinator.registrations(),
  );

  _expect(
    dispatcher.snapshot(TerminalActionId.searchFilesAndFolders).isEnabled &&
        dispatcher.snapshot(TerminalActionId.goToFileOrFolder).isEnabled &&
        dispatcher
            .snapshot(TerminalActionId.moveInDirectoryNavigator)
            .isEnabled &&
        dispatcher.snapshot(TerminalActionId.toggleHiddenFiles).isEnabled &&
        dispatcher.snapshot(TerminalActionId.toggleContextDock).isEnabled &&
        !dispatcher.snapshot(TerminalActionId.focusTerminal).isEnabled,
    'only valid initial Context Dock actions are available',
  );
  await _expectExecuted(dispatcher, TerminalActionId.toggleHiddenFiles);
  _expect(
    !dock.snapshotForWindow(window.id)!.pane.showHiddenEntries &&
        navigatorFocus.isEmpty &&
        terminalFocus.isEmpty,
    'hidden-entry toggle targets the active pane without moving terminal input',
  );
  mutateDuringProjection = true;
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
        snapshot.pane.resultCount == 3 &&
        dispatcher.snapshot(TerminalActionId.focusTerminal).isEnabled,
    'search refreshes a benign projection generation before transferring '
    'input exactly once',
  );
  dock.setQuery(window.id, 'retained', requireNavigatorInput: true);
  await _expectExecuted(dispatcher, TerminalActionId.toggleHiddenFiles);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    snapshot.pane.showHiddenEntries &&
        snapshot.navigatorOwnsInput &&
        snapshot.pane.query == 'retained' &&
        navigatorFocus.length == 1 &&
        terminalFocus.isEmpty,
    'hidden-entry toggle preserves Navigator ownership and its retained query',
  );
  final int firstSelectionGeneration = snapshot.pane.querySelectionGeneration;
  await _expectExecuted(dispatcher, TerminalActionId.searchFilesAndFolders);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    navigatorFocus.length == 2 &&
        snapshot.navigatorOwnsInput &&
        snapshot.pane.query == 'retained' &&
        snapshot.pane.querySelectionGeneration == firstSelectionGeneration,
    'repeated search preserves the retained query and caret without toggling focus',
  );
  await _expectExecuted(dispatcher, TerminalActionId.goToFileOrFolder);
  dock.setQuery(window.id, 'folder', requireNavigatorInput: true);
  await _expectExecuted(dispatcher, TerminalActionId.moveInDirectoryNavigator);
  snapshot = dock.snapshotForWindow(window.id)!;
  _expect(
    navigatorFocus.length == 4 &&
        snapshot.navigatorOwnsInput &&
        snapshot.pane.navigatorMode == TerminalContextDockNavigatorMode.move &&
        snapshot.pane.query.isEmpty &&
        snapshot.pane.searchQuery == 'retained' &&
        snapshot.pane.goToQuery == 'folder',
    'Go To and Move switch modes while retaining their pane-local queries',
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
        snapshot.pane.searchQuery == 'retained' &&
        snapshot.pane.goToQuery == 'folder' &&
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
        !dispatcher.snapshot(TerminalActionId.goToFileOrFolder).isEnabled &&
        !dispatcher
            .snapshot(TerminalActionId.moveInDirectoryNavigator)
            .isEnabled &&
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
        !dispatcher.snapshot(TerminalActionId.toggleHiddenFiles).isEnabled &&
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
  var holdCopy = false;
  var copyCount = 0;
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: <TerminalActionRegistration>[
      ...coordinator.registrations(),
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        handler: () {
          copyCount++;
          return holdCopy ? busyGate.future : null;
        },
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

  await _expectExecuted(dispatcher, TerminalActionId.goToFileOrFolder);
  await route(_key(keyCode: 5, characters: 'g'));
  _expect(
    dock.snapshotForWindow(window.id)!.pane.navigatorMode ==
            TerminalContextDockNavigatorMode.goTo &&
        dock.snapshotForWindow(window.id)!.pane.searchQuery == 'a' &&
        dock.snapshotForWindow(window.id)!.pane.goToQuery == 'g',
    'Go To input edits only its independent query',
  );
  await _expectExecuted(dispatcher, TerminalActionId.moveInDirectoryNavigator);
  final TerminalContextDockKeyResult moveText = await route(
    _key(keyCode: 6, characters: 'z'),
  );
  final TerminalContextDockKeyResult moveBackspace = await route(
    _key(keyCode: 51),
  );
  final TerminalContextDockKeyResult moveSelectAll = await route(
    _key(
      keyCode: 0,
      characters: 'a',
      modifiers: const ModifierKeys(ModifierKeys.commandBit),
    ),
  );
  _expect(
    moveText.disposition == TerminalContextDockKeyDisposition.consumed &&
        moveBackspace.disposition ==
            TerminalContextDockKeyDisposition.consumed &&
        moveSelectAll.disposition ==
            TerminalContextDockKeyDisposition.consumed &&
        dock.snapshotForWindow(window.id)!.pane.query.isEmpty &&
        dock.snapshotForWindow(window.id)!.pane.searchQuery == 'a' &&
        dock.snapshotForWindow(window.id)!.pane.goToQuery == 'g',
    'Move consumes editing keys without mutating either query or the PTY',
  );
  await _expectExecuted(dispatcher, TerminalActionId.searchFilesAndFolders);

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
  _expect(
    (await route(
              _key(
                keyCode: 8,
                characters: 'c',
                modifiers: const ModifierKeys(ModifierKeys.commandBit),
              ),
            )).disposition ==
            TerminalContextDockKeyDisposition.pathCopyDispatched &&
        copyCount == 1,
    'Command-C dispatches the shared Copy action exactly once',
  );
  _expect(
    (await route(_key(keyCode: 36, characters: '\r'))).treeIntent ==
            TerminalContextDockTreeIntent.toggle &&
        (await route(
              _key(
                keyCode: 36,
                characters: '\r',
                modifiers: const ModifierKeys(ModifierKeys.optionBit),
              ),
            )).disposition ==
            TerminalContextDockKeyDisposition.pathInsertionRequested,
    'Return toggles a folder and Option-Return requests explicit insertion',
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

  holdCopy = true;
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

Future<void> _testPathHandoffPolicyAndExactPayload() async {
  final _Harness harness = _Harness();
  final TerminalWindowState window = await harness.createWindow();
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final TerminalContextDockState dock = TerminalContextDockState()
    ..synchronize(harness.state);
  void focusNavigator() {
    final TerminalContextDockFocusRequest request = dock.requestSearchFocus(
      window.id,
      paneId,
    );
    _expect(dock.confirmNavigatorInput(request), 'navigator focus is current');
    dock.setResultCount(window.id, 1);
  }

  focusNavigator();
  final _PathHandoffHarness handoff = _PathHandoffHarness(
    windowId: window.id,
    paneId: paneId,
  );
  final TerminalExternalPasteController<PaneId> paste =
      TerminalExternalPasteController<PaneId>(
        resolveTarget: handoff.resolvePasteTarget,
      );
  final TerminalContextDockPathHandoffController controller =
      TerminalContextDockPathHandoffController(
        dockState: dock,
        resolveSelection: handoff.resolveSelection,
        resolveTarget: handoff.resolveTarget,
        writeClipboard: handoff.writeClipboard,
        pasteController: paste,
        focusTerminal: (TerminalWindowId windowId, PaneId targetPaneId) async {
          if (windowId != window.id || targetPaneId != paneId) return false;
          handoff.focusCount++;
          dock.focusTerminal(windowId, targetPaneId);
          return true;
        },
        onClipboardWritten: () => handoff.clipboardResetCount++,
      );

  final TerminalContextDockPathHandoffSnapshot ready = controller
      .snapshotForWindow(window.id);
  _expect(
    ready.canCopy &&
        ready.canInsert &&
        ready.block == TerminalContextDockPathInsertionBlock.none,
    'one selected local path is ready for both explicit actions',
  );
  _expect(
    controller.copyPath(window.id).disposition ==
            TerminalContextDockPathHandoffDisposition.copied &&
        handoff.clipboardText == handoff.path &&
        handoff.clipboardResetCount == 1 &&
        handoff.writes.isEmpty &&
        dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'copy writes only the raw path and neither writes PTY bytes nor changes focus',
  );
  final TerminalContextDockPathHandoffResult inserted = await controller
      .insertPath(window.id);
  _expect(
    inserted.disposition ==
            TerminalContextDockPathHandoffDisposition.inserted &&
        handoff.writes.single == "'/tmp/a b'\\''c'" &&
        handoff.focusCount == 1 &&
        !dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
    'insert sends one shell-quoted word without whitespace and restores terminal focus',
  );

  for (final TerminalContextDockPathInsertionBlock expected
      in <TerminalContextDockPathInsertionBlock>[
        TerminalContextDockPathInsertionBlock.secureInput,
        TerminalContextDockPathInsertionBlock.alternateScreen,
        TerminalContextDockPathInsertionBlock.foregroundProcess,
        TerminalContextDockPathInsertionBlock.remote,
      ]) {
    focusNavigator();
    handoff
      ..secure = expected == TerminalContextDockPathInsertionBlock.secureInput
      ..alternate =
          expected == TerminalContextDockPathInsertionBlock.alternateScreen
      ..processDisposition =
          expected == TerminalContextDockPathInsertionBlock.foregroundProcess
          ? TerminalPaneProcessDisposition.foregroundProcess
          : TerminalPaneProcessDisposition.idleShell
      ..local = expected != TerminalContextDockPathInsertionBlock.remote;
    final int writeBaseline = handoff.writes.length;
    final TerminalContextDockPathHandoffResult blocked = await controller
        .insertPath(window.id);
    _expect(
      blocked.disposition ==
              TerminalContextDockPathHandoffDisposition.unavailable &&
          blocked.block == expected &&
          handoff.writes.length == writeBaseline &&
          dock.snapshotForWindow(window.id)!.navigatorOwnsInput,
      '$expected blocks insertion with zero PTY bytes and retains navigator focus',
    );
    if (expected == TerminalContextDockPathInsertionBlock.secureInput) {
      _expect(
        !controller.snapshotForWindow(window.id).canCopy,
        'secure input also hides retained path copy authority',
      );
    }
  }

  handoff
    ..secure = false
    ..alternate = false
    ..processDisposition = TerminalPaneProcessDisposition.idleShell
    ..local = true
    ..blockPaste = true;
  final Completer<void> release = Completer<void>();
  handoff.pasteRelease = release;
  final Future<TerminalContextDockPathHandoffResult> first = controller
      .insertPath(window.id);
  await handoff.pasteStarted.future;
  _expect(
    controller.snapshotForWindow(window.id).block ==
            TerminalContextDockPathInsertionBlock.busy &&
        (await controller.insertPath(window.id)).disposition ==
            TerminalContextDockPathHandoffDisposition.busy,
    'one in-flight insertion rejects a concurrent request before transport',
  );
  release.complete();
  _expect(
    (await first).disposition ==
        TerminalContextDockPathHandoffDisposition.inserted,
    'the admitted in-flight insertion completes exactly once',
  );

  controller.dispose();
  controller.dispose();
  _expect(
    controller.isDisposed &&
        controller.copyPath(window.id).disposition ==
            TerminalContextDockPathHandoffDisposition.disposed,
    'disposed path handoff rejects retained actions',
  );
  dock.dispose();
  await harness.state.shutdown();
}

final class _PathHandoffHarness {
  _PathHandoffHarness({required this.windowId, required this.paneId});

  final TerminalWindowId windowId;
  final PaneId paneId;
  final Object identity = Object();
  final String path = "/tmp/a b'c";
  final List<String> writes = <String>[];
  String? clipboardText;
  int clipboardResetCount = 0;
  int focusCount = 0;
  bool local = true;
  bool secure = false;
  bool alternate = false;
  bool blockPaste = false;
  TerminalPaneProcessDisposition processDisposition =
      TerminalPaneProcessDisposition.idleShell;
  Completer<void> pasteStarted = Completer<void>();
  Completer<void>? pasteRelease;

  TerminalContextDockPathSelection? resolveSelection(
    TerminalWindowId candidate,
  ) => candidate == windowId
      ? TerminalContextDockPathSelection(
          windowId: windowId,
          paneId: paneId,
          generation: 1,
          entry: TerminalDirectoryEntrySnapshot(
            name: "a b'c",
            path: path,
            kind: TerminalDirectoryEntryKind.file,
            isHidden: false,
            metadata:
                const TerminalDirectoryEntryMetadataSnapshot.unavailable(),
          ),
        )
      : null;

  TerminalContextDockPathTarget? resolveTarget(
    TerminalWindowId candidateWindow,
    PaneId candidatePane,
  ) => candidateWindow == windowId && candidatePane == paneId
      ? TerminalContextDockPathTarget(
          paneId: paneId,
          identity: identity,
          isLocal: local,
          secureInputActive: secure,
          usingAlternateScreen: alternate,
          processDisposition: processDisposition,
        )
      : null;

  TerminalExternalPasteTarget? resolvePasteTarget(PaneId candidate) {
    final TerminalContextDockPathTarget? target = resolveTarget(
      windowId,
      candidate,
    );
    if (target == null ||
        target.insertionBlock != TerminalContextDockPathInsertionBlock.none) {
      return null;
    }
    return TerminalExternalPasteTarget(
      identity: identity,
      bracketedPasteMode: false,
      pasteInProgress: false,
      showNotice: (_) {},
      paste: (TerminalPastePlan plan) async {
        if (blockPaste) {
          if (pasteStarted.isCompleted) {
            pasteStarted = Completer<void>();
          }
          pasteStarted.complete();
          await pasteRelease?.future;
        }
        final List<int> bytes = <int>[];
        final TerminalPasteChunkEncoder encoder = plan.encoder();
        for (
          Uint8List? chunk = encoder.nextChunk();
          chunk != null;
          chunk = encoder.nextChunk()
        ) {
          bytes.addAll(chunk);
        }
        writes.add(utf8.decode(bytes));
        return TerminalPasteTransferResult(
          disposition: TerminalPasteTransferDisposition.completed,
          encodedBytes: bytes.length,
          completedChunks: 1,
          backpressureCount: 0,
          maximumQueuedBytes: bytes.length,
          concurrentInputRejections: 0,
        );
      },
    );
  }

  int writeClipboard(String text) {
    clipboardText = text;
    return 1;
  }
}

final class _ProcessScheduler {
  int nowMicros = 0;
  final List<_ProcessScheduledTask> _tasks = <_ProcessScheduledTask>[];

  TerminalContextDockScheduledTask schedule(
    Duration delay,
    void Function() callback,
  ) {
    final _ProcessScheduledTask task = _ProcessScheduledTask(
      deadlineMicros: nowMicros + delay.inMicroseconds,
      callback: callback,
    );
    _tasks.add(task);
    return task;
  }

  void elapse(Duration duration) {
    final int target = nowMicros + duration.inMicroseconds;
    while (true) {
      _ProcessScheduledTask? next;
      for (final _ProcessScheduledTask candidate in _tasks) {
        if (candidate.isCancelled || candidate.deadlineMicros > target) {
          continue;
        }
        if (next == null || candidate.deadlineMicros < next.deadlineMicros) {
          next = candidate;
        }
      }
      if (next == null) break;
      nowMicros = next.deadlineMicros;
      next.fire();
      _tasks.removeWhere((task) => task.isCancelled);
    }
    nowMicros = target;
    _tasks.removeWhere((task) => task.isCancelled);
  }
}

final class _ProcessScheduledTask implements TerminalContextDockScheduledTask {
  _ProcessScheduledTask({required this.deadlineMicros, required this.callback});

  final int deadlineMicros;
  final void Function() callback;
  var _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void fire() {
    if (_cancelled) return;
    _cancelled = true;
    callback();
  }

  @override
  void cancel() => _cancelled = true;
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
