# User-facing window, tab, and split actions

- Status: in progress
- Started: 2026-09-09
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `通常起動でwindow/tab/splitのuser actionを有効にする`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`,
  `docs/phase7/native-tabs-split-layout-focus.md`, and
  `docs/phase7/menu-action-registry-command-palette.md`

## Purpose

Make every application action whose terminal-side mutation is already
implemented usable from the zero-config normal product. In particular, route
New Window, New Tab, Split Pane Right/Down, pane focus, tab selection, split
equalize, and pane zoom through one product-owned hierarchy and expose their
true availability in both the native menus and command palette.

## Background

- Phase 7 completed the bounded logical hierarchy, generic AppKit tab/split
  primitives, `TerminalNativeHierarchyAdapter`, action catalog, native menu,
  and command palette.
- The ordinary `developer-jit-run` path still constructs one `Window`, one
  terminal `View`, and one set of pane adapters directly. It does not use the
  native hierarchy adapter.
- New Window, New Tab, Split Pane Right/Down, Toggle Pane Zoom, Equalize
  Splits, and tab-selection actions have catalog metadata but no registration
  in the ordinary product dispatcher, so dynamic validation correctly marks
  them unavailable.
- Opening the command palette is itself an asynchronous dispatcher action.
  The initial render occurs while that action is in flight, which temporarily
  disables every snapshot; no post-dispatch refresh currently corrects the
  visible result.
- `FEATURE_MATRIX.md` records UI-01 as Phase 7 but says user actions are later,
  while the roadmap had no later owner. This task repairs that planning and
  completion gap before Phase 8.
- At task start `dart_terminal` was clean at `d4592ca`. The adjacent
  `dart_appkit` worktree contained an existing uncommitted `ROADMAP.md` change;
  it is outside this task and will not be modified or committed.

## Scope

- Refresh an open command palette after the action that opened it finishes.
- Add a terminal-owned action coordinator over `TerminalApplicationState` and
  `TerminalNativeHierarchyAdapter`, including bounded availability and
  transactional reconcile after successful mutation.
- Move the zero-config ordinary product onto the already implemented native
  hierarchy and create one complete independent PTY/Metal/text-input resource
  set for each pane.
- Route the standard creation, focus, selection, equalize, and zoom actions
  from the native menu and palette to the active logical context.
- Route native window focus, resize, close, termination, and Dock reopen to the
  correct logical window/tab/pane while preserving the existing confirmation
  and ordered cleanup contracts.
- Preserve current single-pane input, IME, mouse, selection, scroll,
  hyperlink, clipboard, title/cwd, diagnostics, and runtime fault acceptance.
- Add deterministic unit/fake-AppKit coverage and M1 Developer JIT/Release AOT
  user-driven product acceptance.

## Out of scope

- Config-file keybind overrides and generated action documentation (Phase 8).
- Quick Terminal, global shortcuts, AppleScript, App Intents, and UI polish
  assigned to Phase 10.
- Terminal-specific policy or types in `dart_appkit`. Existing generic
  Window/tab/SplitView/menu/event primitives are sufficient; all product
  action semantics remain in `dart_terminal`.
- Changing resource limits, close-risk classification, or the generic
  `dart_appkit` and `dart_pty_macos` defaults.

## Dependencies and boundaries

- `TerminalApplicationState` remains the sole logical hierarchy owner.
- `TerminalNativeHierarchyAdapter` remains a presentation projection and does
  not acquire terminal action policy.
- Each new pane receives a fresh `TerminalSession`, renderer view, text-input
  client, live Metal surface, and interaction state. No resource is shared
  between panes except the existing bounded pane-work scheduler.
- Action dispatch is serialized by `TerminalActionDispatcher`; availability
  must reject limit exhaustion, absent active context, disposed owners, and
  incompatible state before allocation.
- A failed logical mutation or native reconcile must not leave an advertised
  enabled action with a partially created pane or leaked native adapter.

## Ordered subtasks

1. Refresh the palette after its opening dispatch reaches idle, prove that
   already registered actions are enabled on the initial rendered frame, and
   retain unavailable status only for genuinely unregistered actions.
2. Implement a terminal product hierarchy action coordinator with registrations
   for window/tab/split creation, focus traversal, tab selection, equalize, and
   zoom. Unit tests must cover availability bounds, exact target selection,
   reconcile count, async serialization, and failure without mutation.
3. Adopt the coordinator and native hierarchy in the ordinary zero-config
   product. Create and start complete per-pane resources, maintain active
   context, and preserve the existing interaction features without changing
   gated compatibility scenarios.
4. Connect native window lifecycle, focused-pane/window close confirmation,
   aggregate application quit, and reopen to the ordinary hierarchy. Removed
   panes must cancel subscriptions before hierarchy reconciliation and release
   PTY/Metal/text-input/native resources exactly once.
5. Add a gated real-product scenario that invokes native menu shortcuts and
   command-palette actions to create multiple windows, tabs, and four panes in
   both Developer JIT and Release AOT. Run the complete regression/audit gates,
   reconcile README/FEATURE_MATRIX evidence, and close Phase 7 only when the
   normal product and test scenario use the same action path.

Each subtask is verified, documented, marked complete, and committed before
the next subtask begins. After every commit, reread `ROADMAP.md` and this memo
to confirm the next target.

## Completion criteria

1. A plain `make RUNTIME_ARCH=arm64 developer-jit-run` starts with one pane and
   enables New Window, New Tab, Split Pane Right/Down, focus traversal, tab
   selection, equalize, and zoom whenever their context permits.
2. The native menu and command palette expose the same enabled state and route
   one user gesture to exactly one logical mutation with zero terminal-input
   leakage.
3. Each created pane is independently usable through physical key input and
   IME, owns a fresh PTY/Metal/text-input resource set, inherits only a trusted
   local cwd, and follows the existing total-pane bound.
4. Native focus/tab/window events update logical active context, and native
   resize projects valid cell geometry to every visible pane.
5. Pane/window close and application Quit preserve confirmation semantics and
   leave no PTY, worker, Metal surface, text-input client, menu/palette, split,
   view, or window handle after teardown.
6. Focused tests, formatting, analysis, complete tests, source/bundle audits,
   and M1 Developer JIT/Release AOT user-action acceptance pass.

## Verification plan

- Focused pure-Dart action/palette tests after the first two subtasks.
- Fake-AppKit hierarchy and application-state tests for every mutation and
  cleanup path.
- Existing `make test` after each product ownership change.
- Gated Developer JIT and Release AOT real-AppKit action scenario, followed by
  `make RUNTIME_ARCH=arm64 runtime-verify` for final acceptance.

## Investigation and implementation log

- 2026-09-09: reproduced the planning/implementation gap by inspection. The
  normal dispatcher registers palette, quit/close, copy/paste, and pane-focus
  handlers only. The catalog includes all 15 actions, and absent registrations
  are deliberately disabled. Multi-tab/four-pane creation currently occurs
  only in the gated native-hierarchy acceptance path.
- 2026-09-09: identified the command-palette initial-state defect. Its `open`
  handler is still the dispatcher's running action when `state.open()` captures
  snapshots, so all results render unavailable. Typing refreshes them after the
  opening dispatch completes, but an untouched palette remains stale.
- 2026-09-09: selected a terminal-owned coordinator and per-pane product owner
  rather than adding terminal-specific callbacks or policy to `dart_appkit`.
  The dependency's generic primitives and defaults remain unchanged.
- 2026-09-09: the first format invocation accidentally included Markdown
  inputs. Dart formatted the three Dart sources but correctly rejected the
  Markdown files as non-Dart syntax; it also could not update its analytics
  session timestamp outside the workspace sandbox. Subsequent formatting is
  restricted to Dart sources, and sandboxed command results are checked
  independently of the irrelevant analytics write failure.
- 2026-09-09: implemented a presenter-level post-dispatch refresh and wired
  both ordinary and hierarchy product menu observers to use it. The initial
  rendered palette now enables registered actions as soon as the opening
  action leaves the dispatcher, while catalog-only actions remain unavailable.
  A focused state regression reproduces the busy opening snapshot and proves
  the corrected idle refresh. The first focused run was blocked by sandboxed
  Clang module-cache and Dart analytics paths; the identical approved run
  completed with exit 0.
- 2026-09-09: the first complete `make test` correctly stopped at the Phase 7
  acceptance freshness gate because `terminal_application.dart` is a pinned
  source. Regenerated `test/corpus/appkit/phase7_acceptance_v1.json`, then
  repeated `make test`; all generators/freshness checks, formatting of 209
  files with zero changes, whole-package analysis, native build hooks, and the
  aggregate Dart test runner passed with exit 0.
