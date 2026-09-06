# Phase 4 — Product Metal surface and live viewport integration

- Status: complete
- Date: 2026-09-06
- Scope: Phase 4 completion repair discovered after the initial closeout
- Related: ADR-002, ADR-003, ADR-004, SCR-05, SCR-07–09, TXT-01–07,
  REN-01–07, REN-09

## Purpose

Make the production terminal window render the canonical parsed terminal screen
through CoreText and Metal by default. ANSI/DEC control sequences must affect
cell state rather than appear as text, terminal wrapping/reflow must determine
visible rows, and a viewport that has not been moved into history must always
show the newest output and prompt.

## Background

The Phase 3 terminal core and Phase 4 renderer are individually complete, but
the normal application entry point still creates a `TextView`. Each PTY byte
batch is parsed into `TerminalScreenSet` and independently decoded into the
legacy `TerminalBuffer`; only that raw projection is assigned to the visible
view. The custom Metal view, scheduler, atlas, recovery, and metrics are reached
only by `DT_RUNTIME_CUSTOM_VIEW_TEST=1`, where they render a synthetic fixture
rather than the live pane.

This explains two product symptoms reported after Phase 4 closeout:

- the ESC byte is not printable but the remaining `[0m`, `[27m`, `[24m`, and
  similar SGR bytes appear in the `TextView`;
- the legacy projection selects newline-delimited rows without accounting for
  terminal autowrap/reflow or the `TextView`'s visual wrapping, and it does not
  own a live-bottom viewport, so the final prompt can be clipped below the
  window after large output.

These are not Phase 5 interactive-scrolling features. Phase 3 already owns a
bounded reflowing screen/scrollback/viewport, and Phase 4 owns the presentation
pipeline. Leaving their live product connection behind a test flag is a Phase 4
integration defect.

## Scope

- Convert a validated retained terminal screen into ordered Metal background,
  glyph, decoration, cursor, and visual-bell instances using shared style,
  palette, grapheme, CoreText, shaping-cache, and glyph-atlas resources.
- Shape contiguous compatible terminal cells in coarse runs, map UTF-16 glyph
  clusters back to cell positions, batch missing glyph rasterization, and keep
  all cache/atlas/instance work within existing hard limits.
- Preserve terminal-owned hard/soft wrapping, wide/continuation topology,
  grapheme clusters, SGR foreground/background/inverse/conceal/bold/italic/
  underline/strike semantics, cursor shape, and default palette resolution.
- Add a single product surface owner that binds the live `TerminalSession` screen
  to damage capture, newest-frame scheduling, atlas synchronization, Metal
  submission/retirement, resize/backing-scale rebuild, visibility/occlusion,
  on-demand presentation retry, bounded animation deadlines, recovery, and
  deterministic teardown.
- Make `TerminalMetalView` the unconditional normal content view. Keep synthetic
  probes gated as tests, but remove `TextView` and raw `TerminalBuffer.render`
  from the product display path.
- Prove with parser/compositor tests and Developer JIT/Release AOT real-PTY GUI
  integration that SGR bytes are never rendered as cells, wrapped output follows
  the canonical grid, and the newest prompt remains in the last visible row.

## Out of scope

- User-driven wheel/trackpad history navigation, selection gestures,
  autoscroll-during-selection, terminal mouse reporting, or scrollbar chrome;
  those remain Phase 5.
- IME/preedit, clipboard policy, configurable font/theme UI, multiple panes,
  shell prompt markers, hyperlinks, images, or synchronized-output protocol.
- Moving the render coordinator to a separate isolate in this repair. The
  synchronous owner must remain bounded and is structured so that the existing
  damage transfer boundary can move later without changing screen semantics.

## Dependencies and ownership

- `TerminalSession.terminalScreenSet` is the sole terminal semantic source.
  `TerminalBuffer` may remain temporarily for content-free lifecycle fixtures,
  but it cannot influence visible rows or pixels.
- The live-bottom projection is the active screen at viewport offset zero.
  Terminal autowrap and resize reflow already materialize physical rows in the
  core. Future history scrolling may change the viewport offset; new output then
  preserves its stable anchor until the user returns to the bottom.
- The surface owner lives on the current application/render domain. It owns and
  disposes the font catalog, shaping cache, atlas, bridge, renderer, scheduler,
  rebuild/recovery coordinators, animation timer, and damage relationship.
- AppKit callbacks only update bounded state and request work. No unbounded
  queue or per-cell FFI call is introduced; CoreText operates on contiguous text
  runs and rasterizes missing glyph keys in bounded batches.
- A submitted frame pins every referenced atlas entry until the native retired
  watermark releases its token. Atlas upload and renderer/resource generations
  must match before frame encoding.

## Ordered subtasks

1. **Canonical screen-to-Metal composition and wrap-aware regression**
   - Add a bounded compositor from `TerminalDamageRenderModel` plus canonical
     style/palette/grapheme resources to CoreText shaping, atlas entries, and
     ordered Metal instances.
   - Test SGR state, control-sequence exclusion, terminal soft wrap, wide and
     grapheme cells, colors/decorations/cursor, atlas synchronization, and a
     newest prompt in the final grid row after overflow.
2. **Default live Metal surface ownership and application connection**
   - Add the product surface owner and connect live session damage, resize,
     backing scale, visibility/occlusion, presentation deadlines, submission
     retirement/retry, recovery, and teardown.
   - Make the custom Metal view unconditional and remove normal `TextView`
     rendering without weakening lifecycle/fault behavior.
3. **Real-PTY GUI acceptance and legacy display removal**
   - Add an integration-only shell/display scenario whose content is checked
     inside the process and reported only as booleans/counters.
   - Verify SGR exclusion, wrap/reflow, latest-row prompt visibility, default
     Metal attachment, bounded frame state, Developer/Release bundles, source
     boundary, and cleanup; then update public status documents and close Phase
     4 again.

Each child receives focused/full verification, documentation and ROADMAP state
updates, and its own commit. The parent remains incomplete until all three are
committed.

## Completion criteria

- Normal application startup always creates and binds `TerminalMetalView`; no
  environment variable is required to reach the production renderer.
- Raw CSI/SGR bytes cannot enter visible text. Styled cells produce the expected
  font style, colors, background, inverse/conceal, decorations, and cursor.
- Terminal autowrap and resize reflow, not host text-layout wrapping, determine
  row placement. With viewport offset zero, overflow scrolls old rows into
  bounded history and the newest prompt occupies a visible final screen row.
- The live pipeline remains newest-only and bounded under atlas/native
  backpressure, pauses while hidden/occluded, requests one full redraw on
  resume/rebuild/recovery, and leaves no pins, renderer, font, view, or timer at
  teardown.
- Unit, parser/compositor, full product, source/bundle audit, and real Developer
  JIT/Release AOT integration tests pass. The regression fails if the product
  returns to `TextView`, displays raw SGR suffixes, or clips the final prompt.

## Verification plan

- Focused compositor and live-surface tests with exact small grids, fake clocks,
  and real CoreText/Metal offscreen output where pixel ownership matters.
- Existing terminal reflow/viewport, damage, scheduler, atlas, recovery, and
  renderer metrics suites.
- `make test`, `make runtime-source-check`, `make runtime-bundle-audit`, and
  `make runtime-integration` for both runtime modes.
- Review product, adjacent `dart_appkit`, and official SDK worktrees before each
  completion commit.

## Investigation log

- 2026-09-06: the worktree was clean at `12647bf`. ROADMAP showed Phase 5 as the
  first unchecked phase before this repair was registered.
- 2026-09-06: `TerminalApplication.run` selects `TextView` unless
  `DT_RUNTIME_CUSTOM_VIEW_TEST=1`; its `onChanged` callback assigns
  `createdPane.render()`. The Metal branch runs `_exerciseBoundMetalFrameScheduler`
  before the live session exists and never consumes live PTY damage.
- 2026-09-06: `TerminalSession` already feeds every raw PTY batch to
  `VtParser(TerminalScreenParserSink.forScreenSet(...))`, but the same bytes are
  UTF-8-decoded and appended to `TerminalBuffer`. `TerminalSession.render`
  returns only `TerminalBuffer.renderOutput`, proving that the parser is not the
  visible source.
- 2026-09-06: `TerminalBuffer.renderOutput` keeps the last N newline-delimited
  strings. It neither interprets CSI/SGR nor counts visual wrapping. In contrast,
  `TerminalScreenSet.resize` already reflows primary history, preserves a stable
  viewport anchor, and restores bottom-follow when the viewport was at bottom.
- 2026-09-06: existing Phase 4 components are reusable but not yet composed for
  arbitrary live cells. The damage model contains cell content/color/style IDs;
  canonical shared tables remain accessible from the same session owner. A new
  compositor is required before the application can safely switch its default
  view.

## Verification results

- 2026-09-06: the first `make runtime-terminal-display-integration` built the
  Developer JIT bundle and launched its real PTY GUI, but the in-process
  acceptance exited with software-failure status 70. The harness originally
  omitted captured output from this assertion, so it was extended with
  content-free stdout/stderr failure context before diagnosing the invariant;
  the task remains incomplete.
- 2026-09-06: the repeated Developer JIT launch showed every product invariant
  true (`sgr_stripped`, styled marker, two soft-wrapped rows, bottom prompt,
  newest accepted revision, bounded frame/pins), but still timed out because a
  redundant completion clause inspected the legacy diagnostic
  `TerminalBuffer`. The acceptance was corrected to wait for and inspect only
  `TerminalScreenSet.activeScreen`; this also prevents future tests from making
  the removed display projection an accidental dependency.
- 2026-09-06: Developer JIT then passed. The first Release AOT repetition also
  emitted every true display invariant, but a scheduled surface drain ran while
  pane shutdown was mutating its screen and rejected a delta as
  `needsFullSnapshot`. Review found a teardown ownership inversion: the pane/
  session owner was awaited before its dependent render surface cancelled its
  timer and closed the damage relationship. Cleanup now disposes the live Metal
  surface before shutting down the pane owner, and the display fixture begins a
  deterministic forced pane close before closing its window. No render retry is
  allowed to outlive the canonical screen owner.
- 2026-09-06: the next Release AOT repetition still ended at the
  `shutdown-started` diagnostic phase with status 70. Because runtime diagnostic
  validation happened before `_ProcessObservation` was returned, its failure
  hid the already-captured application output; the harness now appends that
  content-free context to diagnostic validation failures for precise teardown
  diagnosis. The task remains incomplete pending the repeated launch.
- 2026-09-06: captured output proved the failure occurred during the display
  loop, before its acceptance line. `TerminalDamageRenderModel` correctly
  requires an incremental row version to be the retained logical row's exact
  successor, but a terminal scroll rotates or copies physical rows between
  logical coordinates. With different row histories their versions are not
  comparable; the earlier ring test used equal versions and masked this case.
  Row versions now belong to damage packet logical coordinates rather than
  physical ring slots; dirty marking maps a physical storage slot back to its
  current logical row before advancing. A regression deliberately gives rows
  different versions before ring rotation and proves the incremental packet
  advances every retained logical row exactly once. Normal scroll therefore
  keeps the Phase 4 incremental-damage contract without a full snapshot per
  output line.
- 2026-09-06: the first real-PTY repetition after moving row versions to
  logical coordinates still hit `needsFullSnapshot` intermittently in Release
  AOT. Content-free structural diagnostics showed consecutive damage/resource/
  bell generations and equal dimensions, but one dirty logical row retained
  the same version. Its dirty interval was still stored by physical ring slot,
  so a scroll could move the already-dirty marker to a different logical row.
  Dirty spans now use the same logical coordinate domain as row versions;
  cell/style/line payload remains in the optimized physical ring. The regression
  dirties a row immediately before rotation and checks both its moved content
  and each destination row's single version advance.
- 2026-09-06: after scroll snapshots were corrected, Release AOT reached and
  printed the complete display acceptance. Teardown then exposed the other half
  of the dependency-order fix: `TerminalPane` publishes its final `closed`
  state through `onChanged`, which still referenced the already-disposed
  surface. The callback now snapshots the nullable surface and ignores it once
  disposed, so late owner state notification cannot restart render work.
- 2026-09-06: the first complete `make runtime-verify` reached the pre-existing
  Release smoke abnormal-shell case and observed the valid competing-reaper
  sequence `processExitReady`, `externalReapObserved`, `exitPublished`. Its
  assertion nevertheless required a later `waitpidResult`, which is exclusive
  to the PTY-owned reap branch and contradicted the Phase 2 documented contract.
  The harness now first classifies the reap owner and then checks the ordered
  boundary for that branch. No PTY acceptance condition was weakened: both
  branches still require a valid raw kernel status and one decoded exit.

- 2026-09-06: `dart run test/terminal_screen_metal_compositor_test.dart`
  reached restored CoreText/Metal build hooks and native execution, then failed
  the initial combined SGR-layer assertion. This is not an Xcode/component
  blocker; the individual run/count/color/decoration/cursor observations must
  be separated and the compositor or expectation corrected before completion.
- 2026-09-06: separating the assertion identified a compositor accounting bug:
  the run collector advanced past compatible cells before their background,
  decoration, and rendered-cell accounting ran. The implementation now scans
  cell visuals and shaped text runs independently; the focused native test
  passes, including inverse/direct colors and concealed glyph suppression.
- 2026-09-06: the first full `make test` completed all tests but reported one
  analyzer info for import ordering in `test/run_tests.dart`; the import was
  moved to canonical order before the completion gate was repeated.
- 2026-09-06: canonical composition is implemented by
  `TerminalScreenMetalCompositor`. It consumes only a validated
  `TerminalDamageRenderModel`, batches compatible cells into whole CoreText
  runs, resolves shared style/palette/grapheme resources, rasterizes missing
  glyphs in bounded batches, synchronizes the Dart/native atlas, and emits
  layer-ordered backgrounds, bell overlay, glyphs, decorations, and cursor.
  Atlas upload pressure raises a typed retryable exception without returning a
  partially synchronized frame.
- 2026-09-06: `dart run test/terminal_screen_metal_compositor_test.dart`
  passed after the correction. It covers raw SGR exclusion, bold/underline,
  direct colors, inverse, conceal, strike, whole-run shaping, wide and combining
  cells, native offscreen Metal rendering, and the newest prompt/cursor in the
  final row after soft-wrap overflow.
- 2026-09-06: repeated `make test` passed: generated VT table current, 102 Dart
  files formatted, analyzer clean, and the complete native-backed product test
  runner reported `dart_terminal tests passed`.
- 2026-09-06: a first live-owner test attempted to create the registered
  `TerminalMetalView` from a plain `dart run` executable. It correctly stopped
  at `MacosNativeCapability.load` because custom-view providers are declared and
  initialized only by the packaged `.app` capability manifest. The test was
  removed rather than substituting a plain/fake `View` that could not prove
  renderer binding. Grid/damage/composition logic remains in normal unit tests;
  actual live-view ownership is verified through packaged Developer JIT and
  Release AOT integration launches.
- 2026-09-06: `TerminalLiveMetalSurface` now owns the product relationship:
  one coalesced drain timer, canonical damage outbox/ACK, newest-frame
  scheduler, presentation clock, CoreText catalog/cache, atlas and pins,
  active/replacement Metal domains, and typed recovery. AppKit callbacks only
  update desired viewport/scale/visibility state or flag screen damage; shaping,
  rasterization, upload, and submission happen in the later drain turn.
- 2026-09-06: normal startup unconditionally creates `TerminalMetalView` and
  connects the live `TerminalSession.terminalScreenSet`. Rows and columns are
  derived from CoreText cell metrics, resize rebinds the reflowed active screen,
  backing-scale change resets and republishes the atlas after pin retirement,
  and visible/occluded window state controls the newest-only presentation loop.
- 2026-09-06: the final acceptance uses a gated real zsh PTY rather than a
  synthetic frame fixture. It emits more physical and soft-wrapped rows than
  the current grid, an SGR bold/direct-color marker, and a final prompt. The
  process inspects the canonical `TerminalScreen` for stripped control bytes,
  style state, soft-wrap flags, cursor/prompt placement on the bottom row, and
  verifies that Metal accepted the newest damage revision with at most one
  pending frame and the native submission-slot pin bound.
- 2026-09-06: review of the first acceptance draft found two test defects before
  execution: the zsh loop variable had an extra Dart escape, and the result
  matcher rejected ordinary row counts beginning with 1–3. Both were corrected;
  option parsing now also rejects missing gates, duplicate display scenarios,
  and combinations with other runtime fixtures.
- 2026-09-06: the previous application-local synthetic Metal scheduler probe
  and its `DT_RUNTIME_CUSTOM_VIEW_TEST` startup path were removed. Source audit
  now requires the unconditional custom view/live-screen binding and rejects
  `TextView`, `TerminalPane.render`, or the old gate in the product application.
- 2026-09-06: hidden/occluded state applies damage while suppressing frame
  builds. Recovery retries also tolerate the interval where a failed activation has
  abandoned the old domain but has not yet prepared its replacement; no stale
  renderer is dereferenced between bounded attempts.
- 2026-09-06: `make test` passed with 103 formatted files, clean analysis, a
  current generated VT table, and all product tests. `make
  runtime-source-check` passed with 187 tracked files and zero native sources.
- 2026-09-06: `make runtime-integration` rebuilt and passed both packaged modes
  (`developer-jit` in 2341 ms, `release-aot` in 1829 ms). A separate `make
  developer-jit-run RUNTIME_ARGUMENTS=--auto-close-after=1` launch omitted
  `DT_RUNTIME_CUSTOM_VIEW_TEST` and still reported the registered Metal view as
  attached/bound, started a real PTY, processed close ownership, released the
  session, and shut down cleanly.
- 2026-09-06: after hardening the no-current-domain recovery retry, the final
  repeated `make test` again passed format, clean analysis, generated-table
  verification, and the complete test runner.
- 2026-09-06: final `make runtime-verify` passed without exclusions. It verified
  103 formatted files, clean analysis, the complete native-backed test runner,
  source audit (`tracked=188`, `native_sources=0`), Developer JIT and Release AOT
  bundle audits, ordinary real-PTY GUI smoke (2413/1866 ms), live Metal display
  acceptance (558/353 ms), all 16 lifecycle cases per mode, bounded traffic
  (`backpressured=384`), 1,000-iteration resource stress (`baseline=12`,
  `peak=14`), shutdown faults, and PTY deadline recovery. The adjacent
  `dart_appkit` and bundled official Dart SDK worktrees remained clean.
