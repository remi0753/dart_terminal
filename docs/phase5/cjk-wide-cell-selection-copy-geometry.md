# Phase 5 — CJK wide-cell selection, copy, and geometry consistency

## Task identity

- Date started: 2026-09-06
- Scope: Phase 5 correctness regression reported after daily-driver alpha audit
- Status: complete

## Purpose and background

Make a CJK/full-width grapheme occupy the same two terminal cells in the
canonical grid, CoreText/Metal presentation, pointer hit testing, selection
overlay, stable selection anchors, clipboard extraction, and accessibility
geometry. The user reports that `cat ROADMAP.md` appears readable, but dragging
over Japanese text selects and copies different characters and the apparent
full-width/narrow-width proportions look inconsistent. In particular, each of
the three graphemes in `日本語` cannot be selected independently.

This is a Phase 5 selection/copy correctness regression, so it is registered
after the completed Phase 5 accessibility item and before Phase 6. The phase is
open again until this regression is fixed and committed.

## Scope

- Reproduce Japanese mixed-width text through the canonical screen, renderer,
  pointer-to-cell route, character drag selection, extraction, Copy action,
  and native pasteboard boundary.
- Audit Unicode width classification and wide/continuation cell invariants.
- Audit CoreText shaping positions, glyph placement/scaling, and the chosen
  macOS system-monospace CJK fallback metrics against terminal cell geometry.
- Ensure a pointer over either half of one wide grapheme resolves to that same
  indivisible grapheme and that adjacent Japanese graphemes remain separately
  selectable.
- Ensure the Metal selection overlay covers the same cells whose exact Unicode
  text is copied, for forward and reverse drags in mixed ASCII/CJK rows.
- Add focused unit/native/renderer tests and real AppKit/PTY/clipboard product
  acceptance in Developer JIT and Release AOT.

## Out of scope

- User-selectable font family, font size, zoom, font fallback configuration, or
  ambiguous-width preferences; these remain in their existing later phases.
- Rectangular selection, multiple disjoint ranges, primary selection, or
  changing terminal applications' standard wcwidth semantics.
- Replacing CoreText, the macOS system monospace default, or the Metal renderer
  unless investigation proves its current fallback placement violates the
  terminal cell contract.

## Dependencies and initial facts

- The canonical screen already stores a width-two lead cell and a continuation
  cell for Unicode-wide graphemes. Stable selection uses terminal-cell anchors
  and clipboard extraction reads those anchors, while pointer normalization
  derives a column from logical CoreText cell metrics.
- The live product uses AppKit's symbolic system-monospace family at 14 points.
  CJK normally resolves through ordered CoreText fallback, so a visual-width
  defect may be fallback glyph placement rather than the family choice itself.
- Renderer, selection, clipboard, and accessibility must continue to share one
  canonical terminal-cell geometry. Fixing only copied text or only the
  selection rectangle would leave the other path inconsistent.
- Accepted ADR ownership remains unchanged: Dart owns Unicode width, cells,
  selection, extraction, and frame placement; the native capability owns
  CoreText/Metal objects and batched shaping/raster operations.

## Initial hypotheses to verify

1. Pointer hit testing may treat a continuation column as a separate character
   boundary instead of normalizing it to the wide lead cell.
2. Stable anchor creation or end-exclusive drag logic may count the two cells
   of a wide grapheme inconsistently between selection overlay and extraction.
3. CoreText fallback glyph advances or raster bearings may be scaled/placed as
   if a CJK glyph occupied one cell, even though its terminal span is two.
4. The macOS system-monospace choice itself is not assumed faulty; actual
   resolved fallback faces and shaped/raster bounds must decide that question.

## Completion conditions

- `日本語` renders as three non-overlapping width-two graphemes, with each
  grapheme independently selectable from either visual half.
- Forward/reverse drag across mixed `A日本語B` text produces an overlay over
  exactly the selected terminal cells and copies the exact expected string.
- A real Copy menu action writes the exact selected Japanese UTF-8/UTF-16 text
  through the native pasteboard boundary in both supported runtime modes.
- Tests establish whether the default font/fallback path is correct and guard
  the relevant CoreText glyph bounds/placement without replacing the default
  font unnecessarily.
- Formatting, analysis, full tests, both runtime display/clipboard acceptance,
  source/bundle audit, and proportional full runtime verification pass.
- ROADMAP, FEATURE_MATRIX, README, and this memo contain the final evidence and
  both repositories are clean after a task-specific commit.

## Verification plan

- Focused screen/viewport/gesture tests for CJK width flags, lead/continuation
  normalization, forward/reverse selection, overlay spans, and exact extraction.
- Renderer/native-backed tests for resolved CJK fallback, shaped advance,
  raster bounds, and 1x/2x placement inside a two-cell terminal span.
- Real product fixture using PTY output, injected AppKit drag events over both
  halves of Japanese graphemes, Copy menu invocation, and an isolated in-memory
  clipboard so automated verification never overwrites the user's pasteboard.
- Final `CI=true make test`, both-runtime focused integration, and
  `make RUNTIME_ARCH=arm64 runtime-verify` after implementation.

## Investigation log

- 2026-09-06: both `dart_terminal` at `8bb92f7` and adjacent `dart_appkit` at
  `cffd1da` were clean at task start. README, ROADMAP, FEATURE_MATRIX, the five
  accepted ADRs, and the Phase 4 font plus Phase 5 selection/clipboard records
  were reviewed before source changes.
- 2026-09-06: the first sandboxed focused-test attempt could not update Dart's
  telemetry session or Clang's Metal module cache outside the workspace. The
  same commands were rerun with access to those host build caches; this was an
  execution-environment restriction and did not require a product workaround.
- 2026-09-06: pointer routing divides logical view coordinates by the same
  `TerminalFontCatalogMetrics.cellWidth` used for screen columns. Viewport
  anchor creation already normalizes a continuation cell to its width-two lead
  cell, and selection projection expands the lead through the continuation.
  Existing viewport coverage proved that core extraction does not split a wide
  grapheme, but the gesture layer lacked direct CJK coverage.
- 2026-09-06: the Metal compositor grouped compatible screen cells into a
  CoreText string while retaining only the run's first terminal column. Every
  later glyph was placed at `runLeft + glyph.positionX`, so a CJK fallback
  face's natural typographic advance—not the canonical width-two terminal-cell
  allocation—controlled its visible position. Selection overlays continued to
  use exact terminal columns. This is an unintended compositor/grid mismatch,
  not a defect caused by selecting the symbolic macOS system-monospace family.
- 2026-09-06: focused regression coverage was added before the repair for (a)
  selecting each lead or continuation half of `日本語`, forward/reverse exact
  extraction and projection, and (b) asserting that mixed `A日本語B` glyph
  origins match columns `0,1,3,5,7` at both 1x and 2x.
- 2026-09-06: the new gesture regression passed before the renderer repair,
  confirming that lead/continuation normalization and exact Unicode extraction
  were already correct. The renderer regression failed as intended at 1x:
  CoreText natural origins were `[0,8,22,36,50]`, while canonical cell origins
  were `[0,8,25,42,59]`. Each successive 14-point CJK fallback advance lost
  roughly three pixels relative to its allocated two system-monospace cells.
- 2026-09-06: the repair records each source grapheme's UTF-16 span and terminal
  column span in a compatible text run. Each CoreText glyph cluster is rebased
  to its grapheme's canonical lead column while relative positions among
  multiple glyphs inside one grapheme remain intact. Glyph ink is not stretched
  or font-substituted: the fallback face keeps its natural shape inside the
  width-one or width-two terminal allocation.
- 2026-09-06: the existing gated real-AppKit clipboard acceptance was extended
  without touching the user's pasteboard. It now emits `日本語` through the real
  PTY, injects native drag events over continuation and lead halves, invokes the
  native Copy menu, and requires exact isolated clipboard results for `日`,
  `本`, `語`, and `日本語` in addition to the original ASCII case.
- 2026-09-06: the first Developer JIT clipboard run reached the updated product
  behavior but the outer smoke harness still required the old ASCII-only
  machine line (`local_only=true bytes=13`). The harness was updated to require
  the new CJK evidence (`cjk_individual=true cjk_wide=true bytes=9`); no runtime
  selection or clipboard correction was needed for that failed attempt.
- 2026-09-06: a native CoreText probe of the actual 14-point product catalog
  resolved Latin to `.AppleSystemUIFontMonospaced-Regular` (monospaced, not a
  fallback) and Japanese to `.HiraKakuInterface-W4` (proportional fallback).
  The terminal cell width was 8.65625 points while the Japanese shaped advance
  was about 12.927 points, rather than the canonical 17.3125-point two-cell
  span. This confirms that fallback is expected but its natural advance cannot
  define terminal placement. The temporary probe initially failed outside the
  package root because package resolution was absent; rerunning it with the
  repository package configuration succeeded, and the temporary source was
  removed.
- 2026-09-06: after updating the smoke-harness evidence, real Developer JIT and
  Release AOT clipboard runs passed. They selected and copied each Japanese
  grapheme and the full three-grapheme range through injected AppKit events,
  the native Copy menu, real PTY output, and the isolated clipboard adapter.
  Elapsed times were 3,908 ms and 3,110 ms respectively.
- 2026-09-06: `dart analyze` and `CI=true make test` passed with no analyzer,
  formatting, generated-table, or test failures. The real-PTY Metal display
  suite then passed in Developer JIT (2,190 ms) and Release AOT (1,494 ms),
  retaining SGR, wrap, bottom-prompt, system-font, input, mouse, selection,
  hyperlink, and VoiceOver acceptance while using the corrected placement.
- 2026-09-06: README now states the implemented standard clipboard and
  canonical CJK placement, and FEATURE_MATRIX records the renderer, font,
  selection, and exact-copy contracts. No adjacent `dart_appkit` change was
  required because CoreText already returns the necessary UTF-16 cluster and
  fallback-face metadata; the defect was in this repository's frame placement.
- 2026-09-06: the first aggregate `make RUNTIME_ARCH=arm64 runtime-verify`
  attempt passed tests, source audit, both bundle audits, and both basic smoke
  runs, then an existing Developer JIT mouse fixture timed out waiting five
  seconds for `__DT_MOUSE_SGR_EXACT__`. The application shut down cleanly and
  the same Developer JIT display suite passed immediately when rerun alone in
  2,084 ms. This was a transient fixture timeout rather than a repeatable CJK,
  frame-placement, or ownership failure; aggregate verification was rerun
  instead of weakening its acceptance condition.
- 2026-09-06: the complete aggregate rerun passed. It covered formatting,
  analyzer, all Dart tests, VT table freshness, `tracked=241 native_sources=0`
  source audit, both arm64 bundle audits, both normal smoke runs, both live
  Metal display runs, both CJK clipboard runs, all lifecycle scenarios,
  bounded worker traffic, 1,000-iteration resource stress, shutdown faults,
  and PTY final-deadline recovery in Developer JIT and Release AOT. The final
  display runs completed in 1,450/1,124 ms and clipboard runs in 2,986/2,630
  ms. All task completion conditions are satisfied and no follow-up roadmap
  item or `dart_appkit` change is required.
