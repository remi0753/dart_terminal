# Phase 4 — Product Metal surface and live viewport integration

- Status: in progress
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
