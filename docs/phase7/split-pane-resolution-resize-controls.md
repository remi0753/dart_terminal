# Split pane resolution, resize, and controls

- Status: complete
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
   - Implement and commit the reusable `dart_appkit` query first, including
     Dart/fake/native bridge coverage.
   - Then implement and commit terminal gesture detection, model persistence,
     complete relayout, and mouse-input isolation.
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
- 2026-09-12: after completing the Retina child, reread the roadmap and this
  memo. Split the drag child into a dependency query commit and a terminal
  integration commit because they are independently testable changes in two
  repositories; the parent drag child remains incomplete until both pass.
- 2026-09-12: implemented the dependency half as an optional
  `NativeSplitViewPositionBindings` surface and
  `TwoPaneSplitView.refreshFraction()`. The additive C symbol validates the
  output pointer, AppKit-main thread, handle kind, and a finite native value in
  `[0, 1]`; older bridges fail explicitly with unsupported status 8. The Dart
  object updates its cached fraction only after a successful query, preserving
  the last known value on failure. Fake/API and Objective-C++ tests cover a
  native drag mutation, failure retention, null output, wrong handle, and
  wrong-thread access.
- 2026-09-12: Dart formatting completed for all five changed dependency Dart
  files and changed only the FFI binding layout. The first native formatting
  attempt resolved `clang-format` to the Chromium `depot_tools` wrapper, which
  refused to run outside a Chromium checkout. No native source was rewritten;
  use the repository's available non-wrapper formatter or verify the existing
  style with its build/test gate.
- 2026-09-12: Xcode's direct `clang-format` binary formatted the three native
  files successfully. The first focused dependency run passed every native
  bridge test, then static analysis rejected the new Dart API before Dart test
  execution: `AppKitNativeException` requires named arguments and interface
  type promotion does not expose the optional method through a local declared
  as `NativeBindings`. Correct the exception construction and use the same
  explicit optional-interface cast pattern as `TextEditor`.
- 2026-09-12: after that correction, the focused dependency gate
  `DART_SUPPRESS_ANALYTICS=true make native-test dart-test` completed with exit
  0: all native bridge tests passed, static analysis reported no issues, all
  Dart API tests passed, and all launcher tests passed.
- 2026-09-12: the dependency's complete
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate completed with exit 0,
  including native bridge/runner/runtime/renderer/PTY contracts, static
  analysis for every package, Dart API and launcher suites, the hello-window
  build, current FFI smoke, and legacy-event fallback smoke.
- 2026-09-12: review found that Xcode's formatter version had rewritten 519
  lines in `AppKitBridge.mm`, 617 lines in `BridgeTests.mm`, and unrelated
  header declarations despite the semantic change being small. Because the
  dependency was verified clean at task start and every current edit was made
  by this task, restored exactly those native files to `HEAD` with explicit
  approval, then reapplied only the 7-line declaration, 27-line bridge
  implementation, and 24-line test addition. The resulting dependency diff is
  175 insertions and 3 deletions across nine in-scope files, with no whitespace
  errors or unrelated native formatting churn.
- 2026-09-12: reran the complete dependency gate on that final minimal diff;
  it completed with exit 0 and the same full native/package/FFI coverage. The
  terminal repository's exact full gate was then rerun against the final path
  dependency and also completed with exit 0: freshness gates, formatting,
  static analysis, Phase 9 stress, and the entire Dart suite passed.
- 2026-09-12: after commit `ba9cd0f` in the dependency, reread the roadmap and
  task memo and implemented terminal integration. The hierarchy now retains
  its last successful immutable layout, hit-tests the deepest visible divider
  with a three-point native interaction slop, and reads only that split's
  current native fraction. A changed open-interval fraction is persisted
  through `TerminalApplicationState.resizeSplit`; ordinary reconciliation then
  applies both pane rectangles to `TerminalLiveMetalSurface.resizeViewport`
  and `TerminalPane.resize`, keeping fixed font/cell metrics while updating
  renderer pixels, terminal rows/columns, and PTY winsize.
- 2026-09-12: added a bounded per-tab divider gesture controller. Only a
  primary-button down inside a divider starts a gesture; its drag and final up
  are consumed and synchronized, while off-divider down, hover, and drags
  without an active token remain ordinary terminal input. Window close,
  resize, focus loss, visibility loss, tab subscription removal, and product
  disposal cancel stale tokens.
- 2026-09-12: the focused hierarchy test completed with exit 0. It starts a
  divider gesture, substitutes native fractions of 0.75 and 0.70, proves each
  is persisted with exactly one reconciliation, verifies both pane widths
  change while their heights stay fixed, confirms mouse-up ends the gesture,
  and confirms later/off-divider mouse events are not consumed.
- 2026-09-12: regenerated the deterministic Phase 7 AppKit acceptance report;
  the reviewed totals remained unchanged. The exact full terminal gate then
  completed with exit 0: all freshness, compatibility, application, terminfo,
  and shell-integration checks passed; formatting changed zero files; static
  analysis found no issues; Phase 9 stress and the complete Dart suite passed.
- 2026-09-12: after commit `77ea375`, reread the roadmap and this memo. For the
  final child, selected four stable application actions in the View menu with
  AppKit function-key equivalents U+F700..U+F703 and exact Command modifiers.
  The configurable-keybinding collision vocabulary will translate those
  native equivalents to `arrow-up`, `arrow-down`, `arrow-left`, and
  `arrow-right`, so menu reservation, command-palette discovery, and config
  validation share one physical-key identity.
- 2026-09-12: divider direction describes movement of the divider itself,
  independent of which child contains focus. The hierarchy adapter will find
  the nearest focused-pane ancestor whose axis matches the command, derive one
  movement step from the configured logical cell width or height, clamp the
  first-child extent to the existing descendant minima, persist the resulting
  fraction through application state, and run the ordinary reconciliation
  path. A zoomed, unprojected, absent, or already-clamped matching divider is
  unavailable rather than falling through to terminal input.
- 2026-09-12: the initial focused test compile found that a nullable branch
  local was not promoted through a conditional map lookup; replaced it with
  an explicit null return before accessing the branch ID. The next action
  registry run exposed an intentional search-overlap: the old abbreviated
  query `SPLTRGHT` now matches both “Split Pane Right” and “Move Split Divider
  Right”. Updated the assertion to verify deterministic catalog-first ordering
  and added an exact divider-action query instead of assuming one result.
- 2026-09-12: the first Developer JIT product acceptance reached and executed
  Command+Right, but the new assertion required both panes' integer column
  counts to change after one integer-point cell step. Native pane extents and
  renderer viewports are measured in points/pixels while the resolved system
  font cell width is fractional, so a valid relayout can leave one side in the
  same integer column bucket. Retained the strict opposite viewport movement,
  unchanged row/font/scale checks, and required both column counts to be
  monotonic with at least one changing. This verifies recomputation without
  assuming an invalid symmetric rounding result.
- 2026-09-12: a diagnostic rerun measured the immediate post-command
  snapshots as left viewport `919 -> 935` pixels and right viewport
  `919 -> 903` pixels at unchanged 2x scale, while both snapshots still
  reported their prior 62 columns. This confirmed that native/model/renderer
  geometry was already correct and that the assertion raced the asynchronous
  terminal/PTY resize path. Added a bounded wait for monotonic column
  convergence before evaluating the final fixed-metric invariant; retained
  the numeric failure context for future diagnosis.
- 2026-09-12: the corrected M1/arm64 Developer JIT product acceptance passed
  in 1,732 ms and the Release AOT acceptance passed in 1,058 ms. Both used the
  ordinary native menu dispatcher and real PTY/Metal hierarchy, verified the
  new pane reached 2x scale, invoked Command+Right exactly once without a
  terminal write, observed opposite viewport/grid resizing after bounded PTY
  convergence, kept both font catalogs' point/cell metrics and raster scale
  unchanged, exercised the existing palette/window/tab/split/input-isolation
  path, and cleanly released all five created sessions plus native owners.
- 2026-09-12: added the four stable IDs
  `pane.move-divider-left|right|up|down`. They are dynamically available only
  when the focused pane has a visible matching-axis divider that can move,
  appear in the View menu and command palette, accept additional non-reserved
  configured chords through the existing `keybind` option, and reserve the
  native Command+arrow defaults. Updated the generated action/keybinding
  reference, README product summary, and `FEATURE_MATRIX.md` UI/input/render
  evidence; no new Settings option or Settings-screen control is introduced.

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
- 2026-09-12: final-child focused action registry, key vocabulary, hierarchy
  coordinator, and fake-AppKit hierarchy tests all completed with exit 0 after
  the recorded assertion corrections. The fake hierarchy constructs nested
  horizontal/vertical/horizontal branches, proves nearest-axis selection and
  exact 8-point/16-point cell steps, clamps both horizontal ends, and disables
  all divider commands while zoom hides the split tree.
- 2026-09-12: final M1 product acceptance commands:
  `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 developer-jit-actions`
  and the corresponding `release-aot-actions`; both completed with exit 0 and
  emitted `RUNTIME_USER_ACTIONS_INTEGRATION_PASS`.
- 2026-09-12: the first final full gate passed the key/action reference
  (`application_actions=25`, `reserved_shortcuts=14`), Phase 7 AppKit evidence,
  and preceding freshness checks, then stopped at the Phase 6 compatibility
  coverage freshness check. That derived report hashes shared runtime sources
  and README/FEATURE evidence, so this follow-up's in-scope changes require its
  normal regeneration; no compatibility behavior assertion failed.
- 2026-09-12: regenerated
  `compatibility/regression_coverage_report.json` from the final shared source
  and documentation hashes. The exact final gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then completed with exit 0:
  all generated/reference/Phase 7/compatibility/application/terminfo/shell
  freshness gates passed, Dart formatting covered 270 files with zero changes,
  static analysis found no issues, Phase 9 security stress passed at seed
  `0x509a1171`, and the full suite ended with `dart_terminal tests passed`.
- 2026-09-12: all three requested outcomes and all six completion criteria are
  satisfied. The follow-up has no remaining task or blocker; Phase 10 remains
  untouched and is the next roadmap phase after this session stops.
