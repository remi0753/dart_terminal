# Phase 5 — preserve scroll position on window close request

## Task identity

- Date started: 2026-09-06
- Scope: Phase 5 daily-driver interaction regression reported after alpha audit
- Status: complete
- Date completed: 2026-09-06

## Purpose and background

When primary history is scrollable, clicking the native window close button
once must request the existing live-shell confirmation without changing the
terminal viewport position. The user reports that the first click is rejected
as expected but the visible terminal content unexpectedly scrolls upward.

This is registered after the completed CJK selection correction and before
Phase 6 because a native close interaction must not mutate unrelated terminal
navigation state in the Phase 5 daily-driver alpha.

## Scope

- Reproduce a scrollable real-PTY terminal, record the viewport anchor/state,
  inject one native window close request, and compare the viewport afterward.
- Trace the AppKit close-button request through deferred window close routing,
  pane close confirmation, terminal surface synchronization, input/scroll
  routing, and any synthetic menu action.
- Remove the unintended viewport mutation while retaining the established
  first-request confirmation, second-request force-close, clean-shell close,
  abnormal-shell retention, and deterministic resource teardown contracts.
- Add focused unit/integration coverage and Developer JIT/Release AOT real
  AppKit/PTY product acceptance.

## Out of scope

- Phase 7 active-process detection or redesigning the close/quit UX.
- Adding scrollbars, changing trackpad/wheel behavior, or changing the
  bottom-follow policy for actual terminal output.
- Multiple windows, tabs, panes, restoration, or new confirmation UI.

## Dependencies and initial facts

- `TerminalViewport` owns primary-history position; window/pane lifecycle must
  not mutate that position merely because a close request is refused.
- `Window.defersCloseRequests`, the application event listener, and
  `TerminalPane.requestClose` own the current two-step live-shell close policy.
- The normal product uses a dependency-owned `TerminalMetalView`; any native
  click or window event must remain within the accepted Dart/AppKit ownership
  and asynchronous-destruction boundaries.
- Both repositories were clean at task start. `dart_terminal` started at
  `9097631`; no `dart_appkit` change is assumed until the event trace proves it
  is necessary.

## Questions and hypotheses

1. The first close path may invoke an unrelated menu action that routes a
   synthetic scroll or changes first-responder state.
2. Window visibility/occlusion notifications may rebuild the viewport with a
   stale or default scroll anchor when AppKit refuses close.
3. A confirmation/status line may be written through a path that changes
   bottom-follow or content position.
4. A window-chrome mouse event may leak into terminal drag/autoscroll routing.

## Completion conditions

- With retained history at bottom, middle, and top, one refused close request
  preserves the exact viewport offset/visible-row identity and selection.
- Close confirmation behavior and its bounded expiry remain unchanged; a
  second authorized request still closes and tears down all owners.
- Clean and abnormal shell-exit close policies retain their existing behavior.
- A real AppKit/PTY acceptance proves scroll-position preservation in both
  supported runtime modes.
- Formatting, analysis, full tests, source/bundle audits, focused runtime
  acceptance, and proportional aggregate verification pass.
- ROADMAP and relevant product documentation are updated, a task-specific
  commit is created, and both repositories are clean.

## Verification plan

- Focused viewport/lifecycle tests around a refused close request and immutable
  scroll state.
- Extend the gated real-AppKit lifecycle or display suite with scrollable PTY
  output, native close request, pre/post viewport observations, and subsequent
  confirmed teardown.
- Run `CI=true make test`, both runtime modes for the focused suite, source and
  bundle audits, then `make RUNTIME_ARCH=arm64 runtime-verify` if the affected
  lifecycle/rendering surface warrants the complete gate.

## Investigation log

- 2026-09-06: README, ROADMAP, FEATURE_MATRIX, repository structure, current
  worktrees, and Phase 5 placement were reviewed before source changes. The
  new regression is ordered at the end of Phase 5 so Phase 6 remains untouched.
- 2026-09-06: the deferred close implementation itself does not mutate
  `TerminalViewport`. A refused `WindowCloseRequestedEvent` changes the pane to
  `confirmationPending`, appends only a legacy diagnostic status line, replies
  `allow: false`, and leaves the canonical terminal screen and viewport alone.
- 2026-09-06: the native `DaWindow.sendEvent:` hook observes window-level mouse
  events before AppKit dispatch and converts every mouse location to content
  coordinates. A title-bar close-button press is therefore exposed to Dart as
  a mouse-down above the content view (negative terminal-local `y`) before
  AppKit enters the close button's own tracking/action path.
- 2026-09-06: `TerminalMouseRouter` clamped that out-of-grid down to row zero
  and emitted a local-selection `begin`. `_TerminalSelectionProductOwner` then
  armed its normal 50 ms above-edge autoscroller. AppKit's title-bar control can
  consume the corresponding mouse-up in its nested tracking loop, leaving that
  unrelated selection active and repeatedly moving the retained viewport
  upward. This explains why the mutation appears only when history is
  scrollable and why it follows the first close click rather than the refused
  close decision.
- 2026-09-06: rejecting every out-of-grid mouse event was considered and
  rejected because drag selection deliberately continues above/below the view
  to provide bounded autoscroll. The terminal boundary will instead reject
  only a gesture/reporting press that starts outside the current grid; dragged
  and release events remain clamped so a pointer capture that started inside
  can finish correctly outside.
- 2026-09-06: a focused router regression covering all four grid edges and
  both local and remote mouse ownership was added first. It failed against the
  existing implementation because the first outside press was returned as
  `localSelection`, confirming the erroneous ownership transfer before the
  fix.
- 2026-09-06: `TerminalMouseRouter` now returns the typed
  `outsideViewportPress` ignore reason before constructing either a local
  selection intent or an xterm report when `mouseDown` starts outside the
  current rows-by-columns pixel grid. It still clamps dragged/up coordinates,
  preserving pointer continuation and the existing above/below selection
  autoscroll contract for gestures that began inside the terminal.
- 2026-09-06: changing `dart_appkit` to suppress all window-chrome events was
  considered but was not needed. Its window event is documented in
  content-view coordinates and the terminal must already distinguish valid
  content starts from captured continuations; keeping this policy in the
  terminal router also protects test injection and compatible older bridge
  builds. No dependency worktree change was made.
- 2026-09-06: the real-product display acceptance now combines a raw AppKit
  mouse-down at `y = -1` with the actual deferred `Window.requestClose()` path.
  It repeats this at bottom, middle, and top primary-history offsets, waits
  three autoscroll intervals, and compares offset, viewport generation,
  visible logical-row anchors, Metal viewport offset, and the pre-existing
  selection snapshot before cancelling each confirmation.

## Verification results

- Focused regression was observed failing before the router change, then
  `dart test/terminal_mouse_router_test.dart` passed after it. Existing coverage
  still begins a gesture inside, drags above the view, and releases below it.
- Focused analysis of the application, router, test, and runtime smoke gate:
  passed with no issues.
- `CI=true make RUNTIME_ARCH=arm64 developer-jit-display`: passed in 2864 ms.
  The runtime smoke gate accepted all three refused close requests plus exact
  viewport/row/selection preservation while retaining every existing display,
  selection, scroll, hyperlink, accessibility, and teardown invariant.
- `CI=true make RUNTIME_ARCH=arm64 release-aot-display`: passed in 2092 ms with
  the same three-position close-scroll and pre-existing display invariants.
- `CI=true make test`: passed parser-table freshness, formatting of 141 files
  with zero changes, whole-package analysis with no issues, native asset hooks,
  and the full Dart test runner.
- `CI=true make RUNTIME_ARCH=arm64 runtime-source-check
  runtime-bundle-audit runtime-integration runtime-resource-integration`:
  passed. The source audit found 242 tracked files and no native source; both
  bundles retained one helper, one native asset, and one capability; both
  ordinary smoke modes passed; both 1,000-iteration resource runs remained
  bounded at baseline 13 and peak 15 descriptors.
- Final `CI=true make RUNTIME_ARCH=arm64 runtime-verify`: passed the complete
  aggregate again, including both display/clipboard modes, every lifecycle and
  traffic scenario, both 1,000-iteration resource modes, both injected
  shutdown-fault modes, and both PTY deadline recoveries. This retains the
  existing first/second close ownership and clean teardown behavior beyond the
  new refused-close viewport fixture.
- Final diff review found only the Phase 5 roadmap state, this task memo, the
  bounded router policy/test, and content-free product/runtime acceptance.
  `dart_appkit` remained clean and no generated build output was tracked.
