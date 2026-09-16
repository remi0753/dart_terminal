# Phase 7 — Close all tabs in the logical window

- Status: in progress
- Started: 2026-09-17
- Environment: macOS / Apple M1, stock Dart Developer JIT and Release AOT
- Starting state: clean `main` at `1efd606`

## Purpose and background

The native red window button must close every tab and split pane belonging to
that logical window, not only its selected tab's focused pane. The previous
focus-race fix preserved the older pane-only mapping; this follow-up implements
the user's explicit window-wide policy. Command-W/menu/palette Close remains
the existing focused-pane operation. Explicit application Quit is independent.

## Scope, exclusions, dependencies, and risks

- Close exactly one logical window's whole bounded hierarchy; do not close
  other windows, change their sessions, or terminate an empty application.
- Check risks in all tabs before any destructive action. Preserve aggregate
  identity/process-bound confirmation, cancellation on interaction, duplicate
  request exclusion, stale-target rejection, and deterministic owner teardown.
- Reuse the previous native-event deferral across asynchronous model mutation;
  retain notifications only for surviving tabs.
- Exclude tab shortcuts, Settings, Context Dock features, PTY ownership policy,
  native bridge changes, and unrelated planned low-priority follow-ups.
- Depends on state reverse indexes, pane owner shutdown, Close/Quit admission,
  native tab-group projection, and the deferred AppKit Close protocol.
- Risks: hidden tab processes missed by selected-pane admission; sequential
  confirmations partially closing a window; native focus moving to another
  window and accidentally retargeting the remaining removals; reentrant Close
  or Quit during disposal; stale confirmation after process/hierarchy changes.
- Architecture: product semantics remain Dart-owned (ADR-001/002/005); no native
  dependency mutation is required.

## Ordered subtasks and acceptance

1. Model/Close admission: one mutation disposes all panes in the captured window
   and removes its identities afterward, leaving other owners live. One
   window-wide confirmation captures every pane/session/process identity before
   removal. Pane Close and Quit share exclusion with window Close. Cover idle,
   hidden foreground, unavailable, cancellation, stale snapshots, duplicate
   requests, cleanup failure, focus notifications, and final-window reuse with
   deterministic fake sessions. Verify focused tests, analysis/format, update
   checked evidence as needed, document and commit before product wiring.
2. Product/native routing: red button/native deferred request targets its logical
   window without needing to activate its tab; Command-W retains focused-pane
   behavior. Provide a visible window-wide warning for risky admission, keeping
   confirmation distinct from pane Close. Real JIT/AOT acceptance must close a
   multi-tab/split window with one request, keep a separate window intact, close
   the final single-pane window without app termination, reopen, and explicitly
   Quit cleanly. Run existing Close/Quit tests and the complete project gate;
   update docs/progress and commit independently.

## Investigation

- `routeWindowEvent(WindowCloseRequestedEvent)` currently activates/selects the
  native tab, then calls `closePaneRequest(tab.focusedPaneId)`.
- `TerminalApplicationState.removePane` collapses one pane at a time;
  no window-wide removal transaction currently exists.
- `TerminalPaneCloseCoordinator` already excludes concurrent pane removal and
  aggregate Quit; use its same gate for window-wide removal rather than a
  separate coordinator that could race with existing action admission.
- Quit's immutable snapshots compare content-free process identity, excluding
  ECHO/input-content details. Window confirmation should likewise avoid paths,
  argv, environment, terminal text, and unrelated process content.

## Verification and remaining work

### Model/Close admission implementation and checks

- Added `removeWindow` under one mutation reservation, with whole-window reverse
  index removal and neighbor selection only after all sessions have shut down.
  The app is not disposed. Added pane-owner batch disposal that retains the
  owned registry through every awaited shutdown; simply calling `disposePane`
  successively would temporarily leave the owner/model indexes inconsistent.
- Added window Close to the existing pane coordinator gate. Immutable records
  capture pane/session, disposition, child/owning/foreground identities and OS
  errors, excluding input/ECHO and process content. Repeated window Close admits
  only an unchanged snapshot with all window notice markers still pending.
- Mark all target panes so ordinary interaction in any tab cancels admission;
  pane Close/explicit cancel/Quit clear those markers. A dedicated optional
  session presentation names the window button and closing all tabs; fake/older
  session implementations retain their existing generic notice capability.
- Pre-removal input cancellation is applied to every captured pane before model
  teardown. Recheck the whole snapshot after these asynchronous callbacks so a
  newly created/replaced session is not accidentally admitted by an old request.
- First analysis found a result-field typo (`shutdown.panes` instead of
  `shutdown.sessions`); corrected to the existing immutable shutdown contract.
- Focused state tests passed: three tabs including a split (four panes), a
  separate two-tab window, owner/model consistency after one pane has already
  finished, busy duplicate/pane/Quit admission, stale target, deferred surviving
  focus, classified cleanup failure, final-window reuse, hidden foreground/
  unavailable evidence, interaction/cancel/membership invalidation, and pane
  Close not consuming a pending window-wide confirmation.
- `dart run test/terminal_native_hierarchy_test.dart`,
  `dart run test/terminal_product_hierarchy_actions_test.dart`, and complete
  `dart run test/run_tests.dart` passed (`dart_terminal tests passed`). Actual
  session tests confirm the all-tabs warning never writes to the PTY.
- Full static analysis passed; seven changed Dart files passed formatting with
  zero changes; `git diff --check` passed. Four evidence artifacts were regenerated
  in dependency order; Phase 7 acceptance and daily-use freshness checks passed.
- Model/Close admission subtask is complete. No native dependency/user changes
  were modified. The remaining native product routing subtask follows its
  completion commit; the parent task remains incomplete.

Native product wiring and JIT/AOT acceptance are not started until the first
subtask is verified and committed.
