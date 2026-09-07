# Application window/tab/split state model

- Status: complete
- Started: 2026-09-07
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `window → tab → split tree → terminal session の state model`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`, and
  `docs/phase2/persistent-pane-lifecycle.md`

## Purpose

Introduce the application-owned hierarchy required to grow the current
single-window, single-pane product into multiple windows, tabs, and split
panes. Keep stable logical identity, focus/selection state, split topology,
and terminal-pane lifecycle independent from native AppKit handles so later UI
and restoration work can consume one deterministic model.

## Background and confirmed starting state

- Phase 6 is complete. The first unchecked roadmap item is the Phase 7
  application state model.
- `TerminalApplication.run` currently creates and retains one `Window`, one
  `TerminalMetalView`, one `TerminalPaneOwner`, one `TerminalPane`, and one
  `TerminalSession` in local variables. Input, selection, resize, title, and
  close callbacks close over those single instances.
- `TerminalPaneOwner` already allocates monotonically increasing `PaneId`
  values and is the sole creator/remover of `TerminalPane` objects. Each pane
  owns one typed `TerminalSessionId` generation and performs idempotent,
  classified shutdown.
- No application-level `WindowId` or `TabId` exists. There is no Dart split
  topology, selected-tab state, or pane-to-tab/window index.
- `dart_appkit` exposes a generic `Window.contentView`, lifecycle events, and
  deferred close requests. It does not currently expose native tab groups or
  split-view primitives; those belong to the next roadmap item and must not be
  pulled into this task.
- ADR-002 assigns the application/window/tab/split model and lightweight focus
  coordination to the AppKit main-thread Dart root. Mutable terminal state
  remains owned by exactly one pane/session domain.
- The worktree was clean at task start. `main` was 27 commits ahead of
  `origin/main` at `c6efab4 Reconcile terminal compatibility regression coverage`.

## Ordered subtasks

1. Add typed window/tab/split-node identities and an immutable, bounded binary
   split topology with deterministic traversal, lookup, replacement, and
   structural invariants.
2. Add the application/window/tab owner model, selected-tab and focused-pane
   state, pane creation/split/removal operations, reverse ownership indexes,
   and ordered pane teardown using `TerminalPaneOwner`.
3. Route the current single-window product bootstrap and shutdown ownership
   through the new hierarchy without changing observable one-pane behavior;
   add focused regression coverage and close the parent roadmap item.

Each subtask is verified, documented, marked complete, and committed before
the next subtask begins. Native tabs, split views, and user actions remain in
the following roadmap item.

## State and ownership contract

### Identity

- `TerminalWindowId`, `TerminalTabId`, and `TerminalSplitNodeId` are positive,
  stable logical identities allocated monotonically by the application model.
- Logical identities never reuse AppKit handles, native pointers, process IDs,
  collection indexes, or visible titles.
- `PaneId` and `TerminalSessionId` retain their Phase 2 meanings. A split leaf
  refers to one `PaneId`; terminal session identity remains owned by the pane.

### Hierarchy

```text
application
└─ window (selected tab)
   └─ tab (focused pane)
      └─ split node
         ├─ branch(axis, fraction, first, second)
         └─ leaf(pane ID)
```

- Every retained window contains at least one tab.
- Every retained tab contains one non-empty binary split tree and exactly one
  focused pane that appears in that tree.
- A pane appears in exactly one split leaf across the application.
- A branch has two children, a horizontal or vertical axis, and a finite split
  fraction strictly between zero and one.
- Closing a leaf collapses its parent into the surviving sibling. Removing the
  last pane removes its tab; removing the last tab removes its window.
- Public collection and traversal results are immutable snapshots. Mutations
  cannot expose a partially updated hierarchy.

### Ownership and teardown

- The application model owns one `TerminalPaneOwner` and is the only hierarchy
  component allowed to create, index, remove, or dispose panes.
- A hierarchy mutation installs a newly created pane only after all identity
  and topology preconditions pass.
- Pane removal performs terminal shutdown exactly once through
  `TerminalPaneOwner.disposePane`. The structural result and reverse indexes
  must agree even when the session reports a failed shutdown result.
- Application shutdown stops further admission, walks windows/tabs/leaves in a
  deterministic order, and delegates final pane cleanup to the pane owner.
- Native `Window`, `View`, `TerminalTextInputClient`, and Metal surface objects
  are adapters owned outside this pure model. The next task binds them to model
  identities and layout.

## Scope

- Pure Dart typed identities and split-tree value types.
- Application/window/tab aggregate state and pane reverse indexes.
- Create-window, create-tab, split-pane, select-tab, focus-pane, remove-pane,
  and all-pane shutdown semantics needed by later native UI work.
- Current single-window product bootstrap and shutdown through the model.
- Unit/invariant tests, including multiple windows, multiple tabs, four panes,
  focus preservation, parent collapse, invalid cross-owner operations, and
  idempotent teardown.

## Out of scope

- Native AppKit tab groups, `NSSplitView`, split layout rendering, focus-ring or
  first-responder routing, resize/equalize/zoom, and keyboard traversal.
- User-facing window/tab/split creation actions or command palette entries.
- Titles, colors, current-working-directory inheritance, proxy icons,
  fullscreen, screen migration, persisted restoration, reopen behavior, or
  process-aware close confirmation.
- Multi-pane renderer scheduling and resource budgets.
- Any change to terminal parser, grid, PTY ABI, Metal ABI, or worker topology.

## Acceptance criteria

1. Typed IDs are monotonic and stable, and invalid/exhausted allocations fail
   without mutating retained state.
2. Split construction/replacement/removal preserves binary-tree invariants,
   deterministic visual traversal, unique node IDs, unique pane leaves, and a
   valid focused pane.
3. Two windows with multiple tabs and at least four panes can be created,
   selected, focused, split, and collapsed without cross-window leakage.
4. Every pane is indexed by exactly one tab/window and remains owned by the
   single `TerminalPaneOwner`; unknown and foreign IDs are rejected.
5. Removing a pane and shutting down the application terminate each fake
   session once, leave no pane owner entries, and are idempotent.
6. The normal product still starts one window/tab/pane/session and retains its
   existing key, IME, selection, renderer, title, close, and shutdown behavior.
7. Formatting, analysis, full Dart tests, source audit, and relevant M1
   Developer JIT / Release AOT application gates pass.

## Validation strategy

- Add direct model tests with fake pane sessions. Check exact hierarchy
  snapshots and reverse lookups after every mutation, then deliberately probe
  duplicate IDs, invalid fractions, wrong-window focus, last-leaf collapse,
  and calls after shutdown.
- Reuse the Phase 2 fake session contract to count starts and shutdowns and to
  verify that model disposal does not bypass `TerminalPaneOwner`.
- Run focused tests and `dart analyze` after each subtask, then `make test` for
  every completion commit.
- After product integration, run `runtime-source-check`, both ordinary runtime
  smokes, and the lifecycle/display gates that exercise window close and
  resource cleanup. Record exact results here.

## Risks and decisions

- A mutable tree with parent pointers would make accidental cross-tab aliasing
  and partially applied edits hard to detect. The topology will use immutable
  nodes and whole-root replacement; the application aggregate owns mutable
  selection and lookup indexes.
- Fractions are layout intent, not pixels. Pixel rounding and minimum-cell
  enforcement belong to native split layout in the next task.
- Product integration must not rewrite the existing single-pane event router
  prematurely. This task replaces lifecycle/topology ownership first; per-pane
  adapter routing follows with native tabs and split layout.

## Findings and verification log

- 2026-09-07: repository, roadmap, feature matrix, application bootstrap,
  pane/session ownership, AppKit window surface, relevant Phase 2/5 notes, and
  ADR-002 were reviewed before implementation. The existing single-pane
  closures confirm that the logical hierarchy can be introduced without a
  native dependency change, while UI adapter multiplexing belongs to the next
  roadmap task.
- 2026-09-07: the hierarchy is explicitly bounded at 32 windows, 64 tabs per
  window, and 64 panes/127 split nodes per tab. The first subtask added typed
  window/tab/split-node IDs plus immutable leaf/branch/tree values. Tree
  construction inventories node IDs in pre-order and panes in visual
  first-to-second order, rejects duplicate identities and invalid fractions,
  and refuses the 65th pane before allocating a replacement topology.
- 2026-09-07: splitting replaces one leaf with a branch and preserves the
  existing leaf identity. Removal collapses the parent into the sibling and
  returns `null` only for the last leaf. Before/after placement and branch axis
  remain model data; no pixel geometry or AppKit primitive was introduced.
- 2026-09-07: the initial focused compile exposed that the base split-node ID
  constructor is positional while the subclass super parameter had been
  declared named. The leaf/branch constructors now accept a named public `id`
  and forward it explicitly to `super(id)`; the repeated focused test passed.
- 2026-09-07: Dart CLI telemetry cleanup outside the workspace was denied by
  the sandbox after otherwise successful commands. Validation was repeated
  with normal host permission and `DART_SUPPRESS_ANALYTICS=true`; this was an
  environment-only failure and no repository workaround was added.
- 2026-09-07: `dart test/terminal_application_state_test.dart` passed. Focused
  analysis passed with no issues. The first full `make test` found only an
  export directive ordering info; the export was reordered, focused analysis
  then passed, and the complete repeated `make test` passed all freshness
  checks, formatted 190 files with zero changes, analyzed the package with no
  issues, and completed the aggregate Dart test runner.
- 2026-09-07: the second subtask added `TerminalApplicationState` as the sole
  logical owner of windows, tabs, split roots, pane reverse indexes, and one
  transferred empty `TerminalPaneOwner`. Window, tab, and split-node IDs are
  globally monotonic; window/tab/pane admission is bounded; public window/tab
  lists are immutable snapshots; a model validates the full hierarchy against
  both reverse indexes and the underlying pane owner after every mutation.
- 2026-09-07: creating a window installs one tab/leaf/pane, creating a tab
  selects it, and splitting a pane selects and focuses the new sibling. Explicit
  tab selection, window activation, and pane focus validate ownership before
  changing state, so cross-window tabs and cross-tab panes are rejected without
  disturbing another tab's retained focus.
- 2026-09-07: pane removal first obtains the post-removal immutable topology,
  then awaits the pane owner's classified shutdown, then atomically updates the
  hierarchy and indexes. It selects the next visual sibling (or the previous
  final sibling), removes empty tabs/windows, and preserves the active-window
  target. Whole-application shutdown rejects concurrent admission, disposes
  panes in reverse window/tab/visual order, and memoizes its aggregate result.
  `TerminalPaneOwner.disposePane` now returns the existing typed shutdown result
  so no lifecycle classification is lost at the hierarchy boundary.
- 2026-09-07: the first owner-model test run failed because the test expected a
  newly inserted before-leaf to be the last pre-order node. The implementation
  correctly emitted branch/new-leaf/existing-leaf order; the assertion was
  changed to verify the branch ID and the new pane's leaf lookup directly.
- 2026-09-07: focused owner-model tests passed for 2 windows, 3 tabs, 4 retained
  panes, reverse lookup, isolated focus, branch/tab/window collapse, identity
  exhaustion, transferred-owner rejection, calls after disposal, reverse-order
  cleanup, and idempotent shutdown. Focused analysis reported no issues. The
  full `make test` passed every freshness/compatibility gate, formatted 190
  files with zero changes, and analyzed the package with no issues; a direct
  aggregate `dart run test/run_tests.dart` completed with
  `dart_terminal tests passed`.
- 2026-09-07: the product bootstrap now creates its initial pane through
  `TerminalApplicationState.createWindow`, resolves the selected tab's focused
  pane through the model index, and retains all existing per-pane input,
  renderer, selection, title, and close adapters. Final teardown calls the
  application model rather than retaining a separate pane owner.
- 2026-09-07: `TERMINAL_APPLICATION_MODEL` exposes only counts and stable
  window/tab/split-leaf/pane/session identities plus active/selected/focused
  booleans. The ordinary runtime smoke requires exactly one consistent
  1/1/1/1 hierarchy before accepting the existing pane lifecycle and close
  sequence.
- 2026-09-07: the first product acceptance attempt exposed a pre-existing
  source-audit conflict caused by the Phase 6 reviewed ncurses C fixture. The
  blocker, decision, failed attempt, verification, and independent completion
  are recorded in `docs/phase7/test-fixture-source-audit.md`; commit `a8f5d0e`
  restored the gate before product acceptance resumed.
- 2026-09-07: final focused model tests and analysis passed. `make test` passed
  all generated-data freshness, compatibility, format (190 files), analysis,
  and aggregate Dart test gates. `runtime-source-check` passed with 367 tracked
  files, zero product native sources, and one reviewed test-only native source.
- 2026-09-07: fresh M1/arm64 product builds passed ordinary runtime smoke in
  Developer JIT (2468 ms) and Release AOT (1827 ms), including the new hierarchy
  assertion. Live Metal display/close/shutdown passed in Developer JIT
  (2096 ms) and Release AOT (1669 ms). Both bundle audits retained one helper,
  one native asset, and one native capability. The complete 16-case lifecycle
  matrix passed in both modes, including expected status 75 timeout cases and
  status 70 startup/root failures.
- 2026-09-07: final diff review found only the state-model product wiring,
  content-free smoke assertion, current README/feature-matrix descriptions,
  generated coverage hashes, this task record, and roadmap progress. No native
  dependency, ABI, parser, renderer, PTY, or generated build artifact changed.
