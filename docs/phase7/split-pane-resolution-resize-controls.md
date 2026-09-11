# Split pane resolution, resize, and controls

- Status: in progress
- Started: 2026-09-12
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 follow-up `split paneのRetina表示、drag resize同期、keyboard divider操作`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`,
  `docs/phase7/native-tabs-split-layout-focus.md`, and
  `docs/phase7/user-facing-window-tab-split-actions.md`

## Purpose

Keep every pane at the configured font and native backing resolution from its
first frame through interactive divider movement. Make the same divider
movement available as stable application actions with Command+arrow defaults.

## Background and confirmed starting state

- Phase 9 is complete and Phase 10 was the first unchecked phase before this
  explicitly requested Phase 7 regression follow-up was inserted immediately
  before it.
- The supplied 2026-09-12 screenshots show two distinct failures. A newly
  split right pane is rendered at a lower apparent resolution than the
  original pane. After dragging the vertical divider, the left terminal image
  is enlarged and the right image is reduced instead of preserving the same
  glyph/cell size and changing each terminal's column count.
- The normal product creates each additional `TerminalLiveMetalSurface` with
  its default backing scale of 1. The initial pane later receives the native
  window's backing-scale event, but splitting does not cause another window
  scale transition, so the new pane can remain at 1x on a 2x display.
- `DaSplitView` updates its private fraction and child frames during native
  drag. No corresponding Dart-side layout callback is emitted. Consequently
  the `MTKView` drawable changes size while `TerminalLiveMetalSurface`, the
  terminal logical viewport, grid, and PTY winsize retain their old geometry;
  the submitted terminal image is scaled to the new drawable.
- `TerminalApplicationState` already owns immutable split fractions and
  `TerminalNativeHierarchyAdapter` already projects model layout into every
  pane. The missing contract is native drag fraction observation followed by
  the same bounded reconciliation path.
- The action catalog currently exposes split creation, equalize, and zoom, but
  has no directional divider movement action or Command+arrow shortcut.
- Both `dart_terminal` and the adjacent path dependency `dart_appkit` were
  clean at investigation start. The terminal repository started at `dd20a4d`
  and the dependency at `0615817`.

## Scope

- Project the owning native window's finite positive backing scale whenever a
  pane layout is applied, including the first reconciliation of a new split.
- Add a reusable, read-only native split-fraction query to `dart_appkit` and
  use it only while an actual native divider drag is active.
- Persist the observed fraction into the application-owned split tree and
  reconcile logical pane rectangles, renderer viewport pixels, screen rows and
  columns, and PTY winsize without changing font metrics.
- Prevent divider gestures from leaking as terminal mouse or selection input.
- Add left/right/up/down divider actions, Command+arrow native menu shortcuts,
  dynamic availability, bounded movement, generated action/keybinding
  reference updates, and product-level acceptance.

## Out of scope

- Font zoom, pane zoom semantics, split creation shortcuts, or equalize
  behavior changes.
- Changing the configured font family/point size, terminal padding, renderer
  scaling algorithm, or terminal reflow rules.
- Arbitrary view-layout telemetry or an event-protocol version bump; the
  reusable dependency addition is a bounded synchronous fraction query and the
  existing window mouse stream remains the drag trigger.
- Phase 10 Quick Terminal, global shortcuts, and unrelated native polish.

## Dependencies and boundaries

- Dart remains the authoritative owner of split identity and persisted
  fraction. AppKit remains the authority for the instantaneous divider
  position during a native gesture.
- Backing scale is sourced from the owning `Window`; it is never inferred from
  pane width or from a sibling surface.
- The drag path may update only the addressed split branch and must reuse
  normal hierarchy reconciliation so renderer, terminal core, and PTY geometry
  advance together.
- Divider commands operate on the nearest matching-axis ancestor of the
  focused pane, move by one configured terminal cell per invocation, and clamp
  to existing descendant minimum extents.
- No terminal content, mouse payload, or native handle enters persistent
  application state.

## Ordered subtasks

1. Extend pane-layout projection with the owning window backing scale and prove
   that an added split surface receives the same 2x scale as its retained
   sibling before rendering. Keep scale changes idempotent and reject invalid
   values at the existing surface boundary.
2. Add the reusable native split-fraction query, detect/consume native divider
   gestures, mirror the observed fraction into `TerminalApplicationState`, and
   reconcile every affected pane's logical/pixel viewport, grid, and PTY size
   while font metrics remain unchanged.
3. Add four stable directional divider actions and Command+arrow shortcuts,
   move the nearest matching-axis split by one cell with minimum clamping, add
   menu/palette/config-reference and product acceptance coverage, reconcile
   README/FEATURE_MATRIX evidence, and close the parent item.

Each subtask is verified, documented, marked complete, and committed before
the next begins. After every commit, reread `ROADMAP.md` and this memo.

## Completion criteria

1. A newly created pane on a 2x window publishes 2x raster scale on its first
   visible layout and matches the original pane's font/cell resolution.
2. Native divider dragging updates the model fraction and both pane layouts;
   font point size and logical cell metrics do not change, while rows/columns,
   pixel viewport, and PTY winsize follow the new extents.
3. A divider drag is not delivered as terminal mouse reporting or local
   selection input.
4. Command+Left/Right moves the nearest horizontal divider and
   Command+Up/Down moves the nearest vertical divider by one cell, clamps at
   subtree minima, and is unavailable without a matching split.
5. Native menu, command palette, configuration vocabulary, and generated
   action/keybinding reference agree on the four actions and shortcuts.
6. Focused Dart/native tests and the exact full gate
   `CI=true DART_SUPPRESS_ANALYTICS=true make test` pass for every child; final
   M1 Developer JIT and Release AOT acceptance proves real PTY/Metal behavior
   and complete resource cleanup.

## Validation strategy

- Fake-AppKit hierarchy tests for scale projection, split-fraction observation,
  nested divider selection, movement clamping, and exact relayout callbacks.
- `dart_appkit` Dart API and Objective-C++ bridge tests for fraction queries,
  wrong-handle/main-thread errors, and drag-updated values.
- Action catalog/coordinator, menu shortcut, keybind/config reference, and
  normal product acceptance tests for exactly-once dispatch and availability.
- Focused formatting/static analysis followed by the exact full gate after
  each child. The final child also runs the existing M1 user-action acceptance
  in Developer JIT and Release AOT with added split geometry assertions.

## Investigation and implementation log

- 2026-09-12: reread `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, the Phase 7
  split/action records, application state/native hierarchy/product bootstrap,
  live Metal surface, action/keybinding surfaces, `dart_appkit` split API and
  Objective-C++ implementation, relevant tests, and both worktrees before
  implementation.
- 2026-09-12: the screenshots are consistent with stale scale and viewport
  inputs rather than a CoreText font-size mutation. `TerminalMetalView` uses
  `autoResizeDrawable = YES`, so AppKit changes its drawable with the native
  child frame; without a matching `resizeViewport`, Metal presents the old
  logical frame scaled into that drawable.
- 2026-09-12: the earlier Phase 7 record explicitly deferred continuous native
  divider telemetry. The newly requested behavior therefore requires closing
  that documented gap rather than weakening the existing model-ownership
  contract.
- 2026-09-12: selected a bounded read-only split-fraction query triggered by
  the existing window mouse stream instead of a native event-protocol bump.
  On the AppKit main isolate, Dart receives the posted mouse event after native
  `NSSplitView` handling has updated the divider, so the query observes the
  authoritative constrained value. A divider hit/drag token prevents ordinary
  terminal mouse/selection routing during the gesture.

## Verification log

- 2026-09-12: formatted the scale-projection implementation and hierarchy
  regression. The first focused test attempt did not enter test source because
  the sandbox denied modification of
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`; this is an
  environment-only analytics timestamp failure. Retry the identical command
  outside that sandbox boundary rather than changing product code or tests.
- 2026-09-12: the approved focused hierarchy test completed with exit 0. The
  regression injects a 2x cached native-window scale, creates a new horizontal
  split, and proves the new pane receives exactly one initial 2x projection
  while the retained sibling remains at 2x.
- 2026-09-12: the first exact full gate stopped at the intended Phase 7 AppKit
  evidence freshness check after all preceding generator checks passed. The
  acceptance inventory hashes `terminal_native_hierarchy.dart`, so this
  in-scope source change requires regenerating the deterministic reviewed
  report before rerunning the gate; no test assertion failed.
- 2026-09-12: regenerated
  `test/corpus/appkit/phase7_acceptance_v1.json`; the generator completed with
  exit 0 and retained the reviewed totals of four criteria, thirteen source
  references, ten unit tests, four integration tests, and eight UI assertions.
- 2026-09-12: the exact full gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then completed with exit 0.
  All deterministic freshness/compatibility/application gates passed, Dart
  formatting changed zero files, static analysis reported no issues, the
  Phase 9 stress gate passed, and the complete suite ended with
  `dart_terminal tests passed`.
