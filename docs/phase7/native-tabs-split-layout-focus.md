# Native tabs and split layout/focus

- Status: in progress
- Started: 2026-09-07
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `native tabs と split layout/focus/resize/zoom`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`, and
  `docs/phase7/application-state-model.md`

## Purpose

Project the application-owned window/tab/split/pane hierarchy onto native
AppKit windows, native window tab groups, recursive split views, and per-pane
first responders. Keep split ratios, selected tabs, focused panes, and zoom
state deterministic in Dart while AppKit owns native presentation and input
dispatch.

## Background and confirmed starting state

- Phase 6 and the first Phase 7 application-state item are complete. The first
  unchecked roadmap item is native tabs and split layout/focus/resize/zoom.
- `TerminalApplicationState` owns stable window/tab/split-node/pane identities,
  an immutable bounded binary split tree, selected tabs, focused panes, and
  ordered pane lifecycle. Branch fractions already express layout intent, but
  the model has no fraction mutation, equalize operation, zoom state, or
  cell-aware geometry projection.
- The product bootstrap still binds one AppKit `Window`, one renderer `View`,
  one text-input client, and one Metal surface to the selected logical pane.
  Its callbacks close over those single adapters.
- `dart_appkit` exposes generic windows/views and assigns the content view as
  first responder. It has no public native-tab, `NSSplitView`, explicit
  first-responder, or child-view composition API. The checked path dependency
  is the reusable layer where those generic AppKit primitives belong.
- The adjacent `dart_appkit` worktree was clean at task start on `main`, one
  commit ahead of its origin at `82827a6 Preserve PTY stdin after parent input
  closes`. The `dart_terminal` worktree was clean on `main`, 31 commits ahead
  of its origin at `4f98502 Route product startup through application state`.
- Native tab presentation maps one logical terminal window to an AppKit tab
  group containing one native `NSWindow` per logical tab. A logical window is
  not replaced by a native handle in the model.
- Each split branch maps to one native `NSSplitView`; each leaf maps to the
  existing terminal renderer view. Selecting a tab and focusing a pane map to
  selecting its native window and making its terminal view first responder.

## Ordered subtasks

1. Extend the pure application model with immutable split-fraction updates,
   recursive equalization, per-tab zoom identity, focus traversal, and bounded
   cell-aware geometry projection. Verify model invariants and minimum-cell
   rejection without introducing native handles.
2. Add reusable native tab grouping, recursive two-child split view, constrained
   divider sizing, zoom presentation, and explicit first-responder primitives
   to `dart_appkit`. Cover its Dart API/fake bindings and Objective-C++ bridge
   contract, then commit the dependency independently.
3. Add a terminal-native hierarchy adapter that binds logical identities to
   native windows, split views, renderer views, and text-input clients. It must
   rebuild or update layout transactionally, route tab/pane focus exactly, and
   dispose obsolete native adapters in reverse ownership order.
4. Exercise two native tabs and four live terminal panes through a gated
   product-runtime scenario, including resize, equalize, zoom/unzoom, focus,
   key/IME isolation, close, and native/resource cleanup in Developer JIT and
   Release AOT. Update product documentation and close the parent item only
   after full regression acceptance.

Each subtask is verified, documented, marked complete, and committed before
the next subtask begins. Menu/action registry work remains the next roadmap
item; this task exposes callable layout operations and a gated product
acceptance path without defining the final command palette.

## State and native ownership contract

```text
TerminalApplicationState                 AppKit presentation adapter
window ID                                native tab group
└─ selected tab ID             <------>  selected NSWindow tab
   └─ zoomed/focused pane ID   <------>  first-responder terminal View
      └─ split branch fraction <------>  NSSplitView divider position
         └─ pane ID            <------>  renderer View + input client
```

- Dart owns stable identity, branch axis/fraction, selection, focus, zoom, and
  logical pane rectangles. Native objects never become model identity.
- AppKit owns native tab chrome, window ordering, split divider interaction,
  view containment, and responder-chain dispatch.
- A tab may zoom only its focused pane. Changing focus clears zoom unless the
  caller explicitly unzooms first; this prevents hidden first-responder state.
- Equalization sets every branch in the selected subtree to one half. Resizing
  one branch changes only that branch and preserves all IDs and descendants.
- Geometry uses logical points and positive cell width/height. Every visible
  leaf must receive at least one whole cell in both axes; impossible geometry
  is rejected before native mutation.
- Native split minimum extents are derived from descendant cell minima, so a
  divider drag cannot shrink a visible descendant below one cell.
- Reprojection installs a complete new native hierarchy before obsolete split
  containers are disposed. Pane views, input clients, Metal surfaces, and
  sessions remain stable across a pure layout change.
- Disposal order is event subscriptions, text-input client, Metal surface,
  split containers, native tab windows, renderer views, then logical pane
  shutdown. Later per-pane close work may refine confirmation policy but must
  not bypass this ownership order.

## Scope

- Pure-Dart split ratio/equalize/zoom/focus traversal and cell-aware layout.
- Generic reusable `dart_appkit` native window tab group, `NSSplitView`, child
  constraint/zoom, and first-responder APIs.
- Terminal adapter maps, projection, focus selection, and native-object
  lifecycle for multiple tabs and panes.
- Gated product runtime creation of at least two tabs and four live panes plus
  deterministic machine-readable acceptance observations.
- Focused unit/native tests and M1 Developer JIT / Release AOT regression gates.

## Out of scope

- Final menu/action registry, command palette UI, or default shortcuts; these
  are the immediately following roadmap item.
- User-visible tab/pane title and color customization, working-directory
  inheritance, or proxy icon.
- Fullscreen, screen migration/restoration/reopen, active-process close policy,
  or app-level quit confirmation.
- Fair multi-pane renderer scheduling/resource budgeting beyond proving that
  all four adapters stay live and independently routed; the dedicated later
  roadmap item owns load/fairness policy.
- Event-protocol expansion for continuous divider-drag telemetry. AppKit may
  constrain and present a native drag locally; the model-changing resize action
  remains explicit until a later action/UI task requires persisted drag ratios.

## Acceptance criteria

1. Split resize changes only the addressed branch; recursive equalize produces
   one-half ratios; zoom is confined to the focused pane and unzoom restores
   the same topology and fractions.
2. Focus traversal follows deterministic visual leaf order with wrapping, is
   isolated per tab/window, and never targets a hidden pane while zoomed.
3. Cell-aware layout either produces non-overlapping bounded pane rectangles
   with at least one cell each or rejects impossible size before mutation.
4. `dart_appkit` can group/ungroup/select native window tabs, compose two
   generic/specialized child views in `NSSplitView`, constrain/equalize/zoom
   children, and make an attached terminal view first responder. Wrong-kind,
   cross-application, disposed, and invalid numeric inputs fail safely.
5. The terminal adapter maps every live logical tab, split branch, and pane to
   exactly one live native adapter, preserves pane views across layout edits,
   and leaves no stale tab/split/focus handle after reconciliation or shutdown.
6. A gated real product scenario creates two native tabs and four live panes,
   selects/focuses them, exercises resize/equalize/zoom/unzoom, proves key and
   IME delivery reaches only the focused pane, and closes with no PTY, Metal,
   text-input, split-view, window, or other native handle leak.
7. Formatting, analysis, complete tests, source audit, native bridge tests, and
   relevant M1 Developer JIT / Release AOT runtime gates pass.

## Validation strategy

- Add direct model tests for ratio replacement, recursive equalization, zoom
  invariants, wrapped traversal, nested horizontal/vertical geometry, minimum
  cells, fractional point sizes, and impossible layouts.
- Extend `dart_appkit` fake bindings/API tests and native bridge tests for exact
  tab relationships, split subview order/axis/divider bounds/zoom, responder
  success, kind checks, main-thread checks, disposal, and legacy-symbol errors.
- Test the terminal adapter with fake AppKit bindings and fake pane sessions,
  asserting exact handle/ID inventories before and after each reconciliation.
- Run the gated product scenario with real zsh, renderer, AppKit, text input,
  and native-handle audit in both runtime modes. Then repeat `make test`, source
  audit, ordinary runtime smoke, display smoke, and lifecycle checks needed by
  changed ownership paths.

## Risks and decisions

- Native tabs are multiple `NSWindow` objects even though the application
  model calls them tabs under one logical window. The adapter owns that mapping
  explicitly instead of pretending an `NSWindow` is a logical window.
- Reparenting a renderer view can disrupt first-responder state. Reconciliation
  therefore restores tab selection first and the focused terminal view last.
- Recursive split minima depend on branch axis. The model computes subtree
  minima from cell metrics and passes per-child extents to native split views;
  it does not infer geometry from native frames.
- Product callbacks currently capture a single pane/session/surface. The
  adapter refactor must use identity-indexed owners before enabling the gated
  four-pane scenario, otherwise events could leak across panes.
- Continuous native divider telemetry would require a new versioned event
  envelope and downstream compatibility work. It is intentionally excluded
  from this item because explicit resize/equalize operations cover persistent
  model mutation and the later action/UI work can introduce telemetry only if
  required.

## Findings and verification log

- 2026-09-07: reread `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, the Phase 7
  state-model record, application bootstrap/cleanup, state ownership, AppKit
  window/view APIs, FFI bindings, fake bindings, native object registry, bridge
  header/implementation, and existing native/Dart test entry points before
  implementation.
- 2026-09-07: confirmed there are no existing native-tab or split APIs in
  `dart_appkit`; generic and renderer-specific views already share the bridge's
  `kView` lookup contract. New split views can therefore remain substitutable
  `View` handles without exposing renderer details through the reusable layer.
- 2026-09-07: the existing `da_window_set_content_view` implicitly makes the
  content view first responder. Multiple panes require an explicit window/view
  operation so focus restoration does not depend on replacing the content
  view. This is part of the reusable AppKit subtask.
- 2026-09-07: event protocol version 5 has window/input/application/menu events
  but no view-layout event. A protocol bump solely for live divider telemetry
  would expand compatibility scope and is not needed for model-owned resize
  actions, so it is explicitly out of scope for this item.
- 2026-09-07: the first subtask added immutable branch-fraction replacement,
  subtree-scoped recursive equalization, previous/next visual focus traversal,
  and per-tab focused-pane zoom state. Application mutations validate typed
  tab/branch/pane ownership, preserve stable topology identities, clear zoom
  before moving focus to a hidden pane, and keep traversal on the only visible
  pane while zoomed.
- 2026-09-07: split layout now computes recursive subtree minima from positive
  logical cell dimensions and non-negative divider thickness. Horizontal
  branches add child widths and vertical branches add child heights; the
  orthogonal minimum is the larger child. Projection clamps every divider to
  both descendant minima, emits immutable pane rectangles and branch geometry,
  accepts fractional logical sizes, and rejects impossible unzoomed geometry
  before producing partial output. Zoomed layout requires only one cell for the
  sole visible pane and leaves the underlying tree and ratios unchanged.
- 2026-09-07: focused formatting changed both implementation and test files.
  Focused analysis reported no issues and the direct state-model test exited
  successfully. Full `make test` passed generated-data freshness, compatibility,
  formatting of 190 files with zero further changes, package analysis with no
  issues, and the aggregate runner with `dart_terminal tests passed`.
