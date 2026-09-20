import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalWindowInteractionTests();

Future<void> runTerminalWindowInteractionTests() async {
  await _testRequestConfirmCancelAndPriority();
  await _testHierarchyStaleFallbackAndWindowLifecycle();
  await _testBoundedDeterministicOwnerSequence();
}

Future<void> _testRequestConfirmCancelAndPriority() async {
  final List<_InteractionFakeSession> sessions = <_InteractionFakeSession>[];
  final TerminalApplicationState application = TerminalApplicationState();
  final TerminalWindowState window = await application.createWindow(
    _configuration(sessions),
  );
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final TerminalWindowInteractionAuthority authority =
      TerminalWindowInteractionAuthority(application);
  final TerminalWindowInteractionSnapshot initial = authority.snapshotForWindow(
    window.id,
  )!;
  _expect(
    authority.windowCount == 1 &&
        initial.owner ==
            TerminalWindowInteractionOwner.terminal(
              windowId: window.id,
              paneId: paneId,
            ) &&
        !initial.transferPending &&
        authority.permitsHierarchyMutation(window.id),
    'each admitted window starts with exactly one focused terminal owner',
  );

  final TerminalWindowInteractionTransferResult dockRequest = authority
      .requestOwner(
        TerminalWindowInteractionOwner.contextDock(
          windowId: window.id,
          paneId: paneId,
        ),
      );
  final TerminalWindowInteractionTransferRequest dockToken =
      dockRequest.request!;
  _expect(
    dockRequest.disposition ==
            TerminalWindowInteractionTransferDisposition.requested &&
        authority.snapshotForWindow(window.id)!.owner == initial.owner &&
        authority.snapshotForWindow(window.id)!.transferPending &&
        !authority.permitsHierarchyMutation(window.id) &&
        authority
                .requestOwner(
                  TerminalWindowInteractionOwner.noteRail(
                    windowId: window.id,
                    paneId: paneId,
                    surfaceGeneration: 1,
                  ),
                )
                .disposition ==
            TerminalWindowInteractionTransferDisposition.busy,
    'request retains the old owner and admits only one native focus hop',
  );
  _expect(
    authority.cancel(dockToken).disposition ==
            TerminalWindowInteractionTransferDisposition.cancelled &&
        authority.snapshotForWindow(window.id)!.owner == initial.owner &&
        authority.confirm(dockToken).disposition ==
            TerminalWindowInteractionTransferDisposition.stale,
    'cancel preserves the old owner and makes the old native result stale',
  );

  final TerminalWindowInteractionTransferRequest confirmedDock = authority
      .requestOwner(
        TerminalWindowInteractionOwner.contextDock(
          windowId: window.id,
          paneId: paneId,
        ),
      )
      .request!;
  _expect(
    authority.confirm(confirmedDock).disposition ==
            TerminalWindowInteractionTransferDisposition.confirmed &&
        authority.snapshotForWindow(window.id)!.owner.kind ==
            TerminalWindowInteractionOwnerKind.contextDock,
    'native confirmation commits one Context Dock owner',
  );

  final TerminalWindowInteractionTransferRequest rail = authority
      .requestOwner(
        TerminalWindowInteractionOwner.noteRail(
          windowId: window.id,
          paneId: paneId,
          surfaceGeneration: 7,
        ),
      )
      .request!;
  authority.confirm(rail);
  final TerminalWindowInteractionTransferRequest editor = authority
      .requestOwner(
        TerminalWindowInteractionOwner.noteEditor(
          windowId: window.id,
          paneId: paneId,
          surfaceGeneration: 7,
          draftGeneration: 3,
        ),
      )
      .request!;
  authority.confirm(editor);
  _expect(
    authority.setNoteEditorPhase(
          window.id,
          TerminalWindowNoteEditorPhase.dirty,
        ) &&
        !authority.permitsHierarchyMutation(window.id) &&
        authority
                .requestOwner(
                  TerminalWindowInteractionOwner.systemSurface(
                    windowId: window.id,
                    surfaceGeneration: 9,
                  ),
                )
                .disposition ==
            TerminalWindowInteractionTransferDisposition.rejected,
    'dirty future Note editor blocks owner exit and hierarchy mutation',
  );
  authority.setNoteEditorPhase(window.id, TerminalWindowNoteEditorPhase.clean);
  final TerminalWindowInteractionTransferRequest system = authority
      .requestOwner(
        TerminalWindowInteractionOwner.systemSurface(
          windowId: window.id,
          surfaceGeneration: 9,
        ),
      )
      .request!;
  authority.confirm(system);
  _expect(
    authority.snapshotForWindow(window.id)!.owner.kind ==
            TerminalWindowInteractionOwnerKind.systemSurface &&
        authority
                .requestOwner(
                  TerminalWindowInteractionOwner.contextDock(
                    windowId: window.id,
                    paneId: paneId,
                  ),
                )
                .disposition ==
            TerminalWindowInteractionTransferDisposition.rejected,
    'system owner does not stack or restore an arbitrary previous UI owner',
  );
  final TerminalWindowInteractionTransferRequest terminal = authority
      .requestTerminal(window.id)
      .request!;
  authority.confirm(terminal);
  _expect(
    authority.snapshotForWindow(window.id)!.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal &&
        authority.requestTerminal(window.id).disposition ==
            TerminalWindowInteractionTransferDisposition.noChange,
    'system dismissal returns explicitly to the focused terminal',
  );
  authority.dispose();
  await application.shutdown();
}

Future<void> _testHierarchyStaleFallbackAndWindowLifecycle() async {
  final List<_InteractionFakeSession> sessions = <_InteractionFakeSession>[];
  final TerminalPaneConfiguration configuration = _configuration(sessions);
  final TerminalApplicationState application = TerminalApplicationState();
  final TerminalWindowState first = await application.createWindow(
    configuration,
  );
  final TerminalWindowState second = await application.createWindow(
    configuration,
  );
  final TerminalWindowInteractionAuthority authority =
      TerminalWindowInteractionAuthority(application);
  final TerminalWindowInteractionTransferRequest firstDock = authority
      .requestOwner(
        TerminalWindowInteractionOwner.contextDock(
          windowId: first.id,
          paneId: first.selectedTab.focusedPaneId,
        ),
      )
      .request!;

  final TerminalTabState newTab = await application.createTab(
    first.id,
    configuration,
  );
  authority.synchronize();
  final TerminalWindowInteractionSnapshot changed = authority.snapshotForWindow(
    first.id,
  )!;
  _expect(
    authority.confirm(firstDock).disposition ==
            TerminalWindowInteractionTransferDisposition.stale &&
        changed.owner ==
            TerminalWindowInteractionOwner.terminal(
              windowId: first.id,
              paneId: newTab.focusedPaneId,
            ) &&
        !changed.transferPending &&
        changed.topologyGeneration > 1,
    'hierarchy mutation invalidates pending focus and falls back without replay',
  );

  final TerminalWindowInteractionTransferRequest secondDock = authority
      .requestOwner(
        TerminalWindowInteractionOwner.contextDock(
          windowId: second.id,
          paneId: second.selectedTab.focusedPaneId,
        ),
      )
      .request!;
  authority.confirm(secondDock);
  await application.splitPane(
    newTab.focusedPaneId,
    configuration,
    axis: TerminalSplitAxis.horizontal,
  );
  authority.synchronize();
  _expect(
    authority.snapshotForWindow(second.id)!.owner.kind ==
        TerminalWindowInteractionOwnerKind.contextDock,
    'unrelated window topology mutation retains a live confirmed owner',
  );

  final TerminalWindowState quick = await application.createWindow(
    configuration,
    role: TerminalWindowRole.quickTerminal,
  );
  authority.synchronize();
  _expect(
    authority.windowCount == 3 &&
        authority.snapshotForWindow(quick.id)!.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal,
    'Quick Terminal participates in the same exactly-one owner authority',
  );
  await application.removeWindow(second.id);
  authority.synchronize();
  final TerminalWindowState reopened = await application.createWindow(
    configuration,
  );
  authority.synchronize();
  _expect(
    authority.snapshotForWindow(second.id) == null &&
        authority.snapshotForWindow(reopened.id)!.owner.kind ==
            TerminalWindowInteractionOwnerKind.terminal,
    'closed owner state is removed and a reopened window gets fresh identity',
  );
  await application.shutdown();
  authority.synchronize();
  _expect(
    authority.windowCount == 0,
    'application shutdown releases every interaction owner',
  );
  authority.dispose();
}

Future<void> _testBoundedDeterministicOwnerSequence() async {
  final List<_InteractionFakeSession> sessions = <_InteractionFakeSession>[];
  final TerminalApplicationState application = TerminalApplicationState();
  final TerminalWindowState window = await application.createWindow(
    _configuration(sessions),
  );
  final PaneId paneId = window.selectedTab.focusedPaneId;
  final TerminalWindowInteractionAuthority authority =
      TerminalWindowInteractionAuthority(application);
  var random = 0x7a1107;
  var lastGeneration = 0;
  for (var step = 0; step < 10000; step++) {
    random = (random * 1103515245 + 12345) & 0x7fffffff;
    final TerminalWindowInteractionSnapshot before = authority
        .snapshotForWindow(window.id)!;
    if (before.noteEditorPhase != null && random % 7 == 0) {
      authority.setNoteEditorPhase(
        window.id,
        TerminalWindowNoteEditorPhase.clean,
      );
    }
    final TerminalWindowInteractionOwner target = switch (random % 5) {
      0 => TerminalWindowInteractionOwner.terminal(
        windowId: window.id,
        paneId: paneId,
      ),
      1 => TerminalWindowInteractionOwner.contextDock(
        windowId: window.id,
        paneId: paneId,
      ),
      2 => TerminalWindowInteractionOwner.noteRail(
        windowId: window.id,
        paneId: paneId,
        surfaceGeneration: 1 + random % 31,
      ),
      3 => TerminalWindowInteractionOwner.noteEditor(
        windowId: window.id,
        paneId: paneId,
        surfaceGeneration: 1 + random % 31,
        draftGeneration: 1 + random % 127,
      ),
      _ => TerminalWindowInteractionOwner.systemSurface(
        windowId: window.id,
        surfaceGeneration: 1 + random % 31,
      ),
    };
    final TerminalWindowInteractionTransferResult result = authority
        .requestOwner(target);
    final TerminalWindowInteractionTransferRequest? request = result.request;
    if (request != null) {
      if (random.isEven) {
        authority.confirm(request);
      } else {
        authority.cancel(request);
      }
    } else if (before.owner.kind ==
        TerminalWindowInteractionOwnerKind.systemSurface) {
      final TerminalWindowInteractionTransferRequest? terminal = authority
          .requestTerminal(window.id)
          .request;
      if (terminal != null) authority.confirm(terminal);
    }
    final TerminalWindowInteractionSnapshot after = authority.snapshotForWindow(
      window.id,
    )!;
    _expect(
      after.owner.windowId == window.id &&
          !after.transferPending &&
          after.generation >= lastGeneration &&
          (after.owner.kind == TerminalWindowInteractionOwnerKind.noteEditor) ==
              (after.noteEditorPhase != null),
      'fixed-seed sequence preserves one bounded owner and monotonic generation',
    );
    lastGeneration = after.generation;
  }
  authority.dispose();
  await application.shutdown();
}

TerminalPaneConfiguration _configuration(
  List<_InteractionFakeSession> sessions,
) => TerminalPaneConfiguration(
  sessionFactory:
      (
        TerminalSessionId id, {
        required void Function() onChanged,
        required void Function() onTerminated,
      }) {
        final _InteractionFakeSession session = _InteractionFakeSession(id);
        sessions.add(session);
        return session;
      },
  onChanged: () {},
  onExitRequested: () {},
);

final class _InteractionFakeSession implements TerminalPaneSession {
  _InteractionFakeSession(this.id);

  @override
  final TerminalSessionId id;
  var _live = false;

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() =>
      TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => _live = true;
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
    _live = false;
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
