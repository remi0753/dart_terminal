# Context Dock keyboard boundary resize

- Status: complete
- Started: 2026-09-17
- Environment: macOS / Apple M1 / arm64 Developer JIT and Release AOT
- Starting terminal state: clean main at 919ccf4

Current defaults were superseded by Control+Shift+Left/Right; see
[shifted-shortcut correction](context-dock-boundary-shift-shortcut.md). The
Control-arrow entries below describe this original implementation's history.

## Purpose and background

Remove mouse dragging of the boundary between the terminal and Context Dock.
Control+Left/Right moves that boundary instead. Changing the available terminal
width must recompute viewport, columns, reflow, and PTY winsize at unchanged
font point size, cell metrics, and backing scale, never stretch an old frame.

## Scope, exclusions, dependencies, and risks

- Disable only the outer Dock divider's mouse interaction, preserving its
  visible color and normal window resize. Terminal split dividers and the
  Navigator/details split are not changed.
- Provide shared keyboard actions usable with terminal or Navigator input,
  preserving focus, query, selected rows, and native resource identities.
- Move the boundary by one logical terminal cell per invocation; Left widens
  the right Dock and Right narrows it. Clamp to existing 220–640 pt Dock and
  240 pt terminal geometry bounds. Hidden/unprojected Dock is not resized.
- Keep configuration width live reload and new-window semantics unchanged;
  keyboard width remains window-owned until a changed configured width.
- Exclude SSH, filesystem/process observation changes, tab/pane shortcuts,
  typography zoom, native event protocol changes, and low-priority follow-ups.
- Dependencies: generic dart_appkit TwoPaneSplitView, Dock state/presenter,
  action/keybind/localization/reference, hierarchy viewport projection, live
  Metal surface, terminal worker reflow, and PTY resize coordination.
- Risks: old native fraction overwriting keyboard state; layout applied after
  native drawable resize causing stretched frames; routing keys into PTY or
  editing Navigator text; focus/resource loss; narrow-window or endpoint drift.
- Boundaries follow ADR-001/002/005: native generic interaction opt-out only,
  Dart product-owned width and input policy, no synchronous worker/GPU waits.

## Ordered subtasks and completion criteria

1. Add an opt-in generic native split-divider interaction property to the
   adjacent dart_appkit dependency. Default retains existing draggable behavior;
   disabled dividers do not track mouse gestures or advertise a resize cursor,
   while programmatic position/layout remains supported. Cover Dart/fake/native
   contracts and full dependency gate; preserve its three pre-existing user
   edits. Commit dependency implementation, then record/commit this subtask.
2. Remove outer Dock native-width capture; disable its drag interaction. Add
   localized discoverable boundary-left/right actions and Control-arrow defaults
   with correct input ownership. Relayout all affected terminal surfaces at
   fixed typography/backing scale with bounded grid/PTY convergence. Cover
   state/action/keybind/fake hierarchy and real JIT/AOT Dock resizing, including
   terminal/Navigator focus, no PTY key writes, clamping, hide/show, unchanged
   split behavior, native owner cleanup. Update references/evidence/docs, run
   full terminal gate, then commit and close the parent task.

Each subtask is verified and committed before the next is implemented.

## Investigation and verification log

- Read project rules, README, ROADMAP, FEATURE_MATRIX, relevant Phase 7 Dock
  configuration and split-resize records, native hierarchy/presenter/input
  boundaries, tests/build entry points, and current worktrees before changes.
- Only unchecked items at start are explicitly low-priority follow-ups; this
  requested regression is registered above them as the current task.
- Presenter resolveTerminalLayoutSize currently calls _captureNativeWidth on
  every existing visible layout. It refreshes the outer native split fraction
  and writes the observed width to Dock state, potentially overwriting explicit
  keyboard/config width and depending on stale prior-frame native geometry.
- The outer TwoPaneSplitView is currently always draggable. Its public API has
  no interaction opt-out; minimum extents alone would retain resize cursors and
  mouse tracking, so use a narrow generic native property rather than locking
  both minima to current sizes or inventing terminal semantics in the bridge.
- Existing split-resize record confirms a native drawable can resize while an
  old renderer viewport/frame is retained, producing stretched presentation.
  Investigate the Dock reconciliation ordering and reuse the normal surface,
  grid, and PTY resize path rather than adjusting font size or raster scale.
- Adjacent dependency has existing user edits only in
  docs/BUILDING_DART_ENGINE.md, scripts/bootstrap_dart_engine.sh, and
  scripts/build_dart_engine.sh. They are outside this task and must not change.

- Added optional NativeSplitViewInteractionBindings and additive C setter,
  TwoPaneSplitView.dividerDraggable (default true). False skips mouseDown
  tracking, native resize cursor rects, and the effective divider hit rect;
  programmatic position and normal native resize still work.
- Focused dependency native-test and dart-test passed: warnings-as-errors native
  bridge build, Dart static analysis/API/launcher suites. Tests cover default,
  disable/restore, unchanged nested split, failed-call cached policy, native
  no-tracking mouseDown, empty effective rect, programmatic resize, strict bool,
  wrong handle/thread and stale handle. Dart format changed only two of five
  in-scope files. No native bulk formatting was used.
- An initial shell probe for named exports matched nothing and short-circuited
  before format/test; no test had run or failed. The explicit test command then
  completed successfully. Full dependency gate is now running.
- First dependency full gate stopped at generic-repository-audit: the new
  generic memo contained the forbidden consumer word terminal. Reworded only
  its two consumer-specific phrases to product/caller language and retained
  the audit unchanged; the full gate is rerunning. Two probes also used wrong
  guessed audit filenames; rg --files identified generic_repository_audit.dart.

- Corrected full dependency gate passed, including ownership audit, native
  bridge/Runner/runtime contracts, package static analysis/API/launcher/builders,
  examples, and current/legacy FFI. No version/event/struct changes required.
- Dependency committed as 80ef799, Allow callers to disable split divider
  dragging. Its three pre-existing user edits remain unchanged and unstaged.
  The first subtask is complete; terminal keyboard/layout integration follows
  this progress-record completion commit. Parent remains incomplete.

## Keyboard/layout integration

- First subtask recorded in terminal commit c99b2c1 before integration started.
- Removed unconditional native-width capture and its positioned flag. Width is
  explicit Dock state; reconciliation always computes terminal content width
  from it, projects native divider position, and calls every affected surface's
  resizeViewport/pane.resize at unchanged cell metrics and window backing scale.
  No renderer font/zoom/scale algorithm change is needed.
- Disabled only the outer native split's dividerDraggable. Navigator/details
  and terminal split dividers keep their existing interaction policy.
- Added two localized stable boundary actions with false focus-restoration
  metadata and overrideable Control-arrow defaults. Navigator consults the live
  keybind engine for only these actions; query/tree keys remain unchanged.
  Releases do not repeat the action or emit unmatched Kitty release bytes.
- Movement is one focused terminal logical cell, based on effective projected
  width and finite viewport bounds. Hidden/small-window/unprojected Dock and
  mutation states are unavailable; endpoints are consumed without PTY writes.
- Initial analysis reported import order, then test-helper missing required
  characters and a terminal handle declared later; corrected only those test/
  directive mistakes. One patch included an absent trailing context and was
  rejected atomically; reapplied the intended chunks without that context.
- Focused Dock/hierarchy/keybind tests passed, then action catalog test caught
  its explicit View menu order missing the new actions. Updated that expected
  ordered list without removing the order assertion. Static analysis is clean.
- Real native-content acceptance now exercises terminal raw-key routing and
  Navigator window routing, exact one-cell steps, fixed typography/scale,
  native root identities/focus, fresh narrower Metal frame/grid, shell-observed
  stty winsize, then restored wider columns. A fixed exact marker is required
  by the outer driver. The explicit test command has its own PTY-write baseline,
  separate from zero-write keyboard operations.
- System-wide macOS Spaces Control-arrow may be consumed before delivery to
  the application. Do not install a global key monitor or alter user system
  preferences; document system unbinding or alternate configured application
  chord. Test injection verifies application delivery, not system interception.

- First rebuilt JIT native-content acceptance passed (11432 ms), including
  exact required Dock resize marker, fixed font/scale/frame/grid, shell-observed
  PTY winsize, Navigator ownership and four clean sessions.
- Final boundary review found 240 pt alone can be less than a large/padded
  split subtree's required width. Added a read-only hierarchy minimum-size query
  sharing its existing recursive geometry policy. Dock effective width, native
  minimum, hide-for-small-window admission and keyboard clamp use that bound;
  zoom uses one leaf's minimum. This is necessary for safe width-following, not
  a change to terminal split semantics. Added large-subtree clamp/hide tests.
  Rebuild and repeat both runtimes after this final source adjustment. A first
  patch attempt had out-of-order repeated context; rejected without changes,
  then reapplied with exact selected source and task-specific chunks.
- Pre-final-minimum Release AOT native-content acceptance also passed (10043 ms).
  Added exact nested-subtree (26x33 pt) and zoomed-leaf (8x16 pt) minimum-query
  assertions to the existing split geometry test. Focused large-subtree Dock
  clamp/hide tests and clean static analysis passed. Evidence is regenerated and
  native-content runtimes rebuilt again for the final source, not reused from
  the earlier bundles.
- Final-source native-content integration passed after rebuilding both bundles:
  Developer JIT 11197 ms, Release AOT 10014 ms. Each required the exact new
  resize marker plus all existing filesystem/process/native-content/privacy
  assertions, four clean session shutdowns, zero text clients/native handles.
  One-cell terminal and Navigator keys, fixed cell/font/scale, viewport/grid,
  fresh frame and actual stty winsize converged without keyboard PTY writes.
  Existing user-action and configuration integrations, then full make test,
  follow sequentially to avoid unnecessary PTY/build contention.
- Existing user-action and configuration smoke suites passed in both JIT and
  AOT: the sequential `&&` command advanced through all four suites to the full
  terminal gate. The first full gate then stopped at configuration-reference-
  check: adding two standard keybindings changes the maximum custom declaration
  count, and configuration-and-command-line.md had not yet been regenerated.
  Regenerate that reference without changing its freshness check, then rerun
  the full gate. Earlier native/parser/static gates reached before it passed.

## Final verification and handoff

- Focused `dart analyze`, Context Dock, native hierarchy, keybinding, and action
  registry tests passed after the final subtree-minimum adjustment. The router
  regression in the full runner checks exactly-once down/release dispatch and
  no unmatched Kitty key bytes; existing Kitty release behavior stays covered.
- Rebuilt `make RUNTIME_ARCH=arm64 runtime-native-content-integration` passed
  both runtimes at final source as recorded above. Existing smoke driver suites
  `--suite=actions` and `--suite=configuration` also passed for developer-jit and
  release-aot, including normal split, aggregate window Close, and live width
  configuration behavior. Bundles are under build/runtime/arm64/{developer-jit,
  release-aot}/DartTerminal.app. These are application-delivered key tests, not
  a claim that macOS system-wide Spaces shortcuts have been intercepted.
- Regenerated configuration/action references and acceptance/regression/gap/
  daily-use evidence. After correcting the stale configuration reference,
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` exited 0: native capability
  and package suites, generated freshness/privacy/localization/compatibility/
  distribution gates, formatting of 348 files with zero changes, static analysis
  with no issues, and the complete dart_terminal regression runner all passed.
- Final diff review and `git diff --check` passed. Only this task's source,
  tests, references/evidence, manual checklist, and progress records are included;
  no temporary debug files or generated native binaries are tracked. The adjacent
  dependency still has exactly its three pre-existing user edits, untouched.
- Both ordered subtasks and parent acceptance are satisfied. There is no new
  required follow-up or blocker; previously scheduled low-priority work is not
  part of this request. Physical keyboard/manual accessibility checks remain
  explicit in the existing manual checklist rather than claimed as automated.
- Restart/rebuild with `make RUNTIME_ARCH=arm64 developer-jit-run` to use the
  updated product. If macOS consumes Control-arrow for Spaces, remove that
  system assignment or bind these two stable actions to another exact chord.
