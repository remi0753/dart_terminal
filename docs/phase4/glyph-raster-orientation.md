# Phase 4 — CoreText glyph raster orientation repair

- Status: complete
- Date: 2026-09-06
- Scope: Phase 4 live glyph correctness repair
- Related: TXT-03, TXT-05–06, REN-02–03, REN-07

## Purpose

Render every CoreText glyph upright through the Dart atlas and live Metal
surface. Complete the repair only after an asymmetric-glyph pixel regression
passes and a screenshot of the rebuilt product is visually legible.

## Background

After the product switched from the named Menlo default to macOS system
monospace, the user supplied a live-window screenshot showing that text became
less legible. Inspection established that this is not a font-family preference:
the glyphs are vertically mirrored while row order, horizontal text order,
colors, cursor, and cell positions remain intact.

Vertically flipping a cropped copy of the supplied screenshot makes its text
readable (`remi@MacBook pro: ~/dart/dart_terminal ...` and
`zsh: command not found ...`). The native rasterizer currently reverses every
Core Graphics bitmap scanline before publishing nominally top-down atlas bytes.
The observed product output proves that this orientation contract is wrong for
the live Metal path.

## Scope

- Establish the actual Core Graphics bitmap-memory and Metal atlas sampling
  orientation with a deliberately asymmetric glyph.
- Correct the shared alpha8 and straight-RGBA8 raster publication path at the
  earliest ownership boundary that can provide one top-down contract.
- Add a pixel regression that fails when an asymmetric Latin glyph is vertically
  mirrored; retain the existing bounds, stride, ownership, and scale checks.
- Regenerate only source-controlled glyph/reference goldens whose pixels change
  because the prior orientation was incorrect.
- Rebuild and test Developer JIT and Release AOT live Metal applications.
- Launch the corrected product, capture its actual window, inspect the image at
  original resolution, and retain the safe screenshot evidence in this task's
  documentation path.

## Out of scope

- Font family, font size, zoom, smoothing, hinting, or theme configuration.
- Parser, terminal screen, row wrapping, scrolling interaction, and input work.
- Shader filtering or atlas allocation redesign unless orientation evidence
  demonstrates that the raster publication boundary is already correct.

## Dependencies and ownership

- `dart_terminal_renderer_macos` owns CoreText/Core Graphics raster production
  and publishes copied device-pixel rows through the version-one raster ABI.
- `dart_terminal` owns atlas storage, CPU reference composition, packed Metal
  instances, live surface integration, goldens, and GUI acceptance.
- The public raster contract must expose row zero as the top of the glyph.
  Consumers must not apply per-backend compensating flips.
- Native and product changes require separate commits. The adjacent repository's
  roadmap is intentionally not consulted under the user's project instruction.

## Completion criteria

- An asymmetric glyph raster has the expected top/bottom coverage relationship
  and the regression fails against the former scanline order.
- Existing Latin/CJK/emoji/combining/ligature raster and 1x/2x golden coverage
  passes after intentional fixture updates.
- Developer JIT and Release AOT real-PTY Metal display acceptance passes with no
  ownership, atlas, or packaging regression.
- A screenshot captured from the rebuilt normal product shows upright,
  human-readable prompt/output at original resolution.
- Both repositories are clean after their scoped commits; ROADMAP and this memo
  accurately reflect completion and Phase 5 remains unstarted.

## Verification plan

- Run the focused renderer native/Dart raster tests and full adjacent package
  tests after correcting the producer.
- Run the focused product atlas/compositor tests, regenerate reviewed goldens if
  required, then run `make test` and `make runtime-source-check`.
- Run `make RUNTIME_ARCH=arm64 runtime-terminal-display-integration` and bundle
  audits for both application modes.
- Launch the normal Developer JIT application with a bounded auto-close period,
  capture its visible window with macOS screenshot tooling, and inspect the
  resulting PNG with the image viewer.

## Investigation log

- 2026-09-06: `dart_terminal` was clean at `cb52396` and adjacent `dart_appkit`
  was clean at `e050c05`. Phase 5 was again the first unchecked roadmap item, so
  this user-confirmed Phase 4 rendering defect was registered before changes.
- 2026-09-06: the supplied 1846×1238 screenshot shows individually inverted
  glyph shapes without reversing row order or horizontal character order. A
  900×120 top crop becomes legible after a vertical image flip, confirming a
  glyph bitmap Y-axis defect rather than an unsuitable font face.
- 2026-09-06: `RasterizeGlyph` draws into a Core Graphics bitmap, then copies
  source row `height - 1 - y` into output row `y` for both alpha and color
  glyphs. Existing tests only require nonzero coverage and compare checked-in
  pixels produced by the same contract; the live acceptance checks state and
  frame submission but not glyph orientation.

## Design decision

Publish the `CGBitmapContext` rows in their existing memory order. The former
producer copied source row `height - 1 - y` into published row `y`, which
introduced the inversion seen by both atlas consumers. Removing that reversal
at the producer establishes one top-down alpha8/straight-RGBA8 contract for the
Dart atlas, CPU reference renderer, live Metal renderer, and future consumers.
No Metal-only shader or texture-coordinate compensation is used.

## Verification results

- A focused adjacent-package test rasterizes the asymmetric capital `L` and
  compares top- and bottom-third alpha coverage. It failed before the repair at
  `top-down capital L raster keeps its horizontal foot at the bottom`, then
  passed after the native row-copy correction.
- The adjacent package's focused `dart run test/run_tests.dart`, combined
  `make terminal-renderer-native-test terminal-renderer-dart-test`, and full
  `make test` all passed. The package change was committed as
  `d55bd6ea8cc42a79c45fa8adcca47f54e1170e73` (`Correct CoreText glyph row
  orientation`).
- The old 1x text golden failed at pixel `(18, 11)`, demonstrating that the
  product fixture recorded the former orientation. The official
  `dart run test/glyph_atlas_test.dart --write-goldens` path regenerated only
  the 1x/2x text atlas fixtures; the read-only rerun passed.
- Product-focused `terminal_live_metal_surface_font_test.dart`,
  `glyph_atlas_test.dart`, and `terminal_screen_metal_compositor_test.dart`
  passed. The live-surface font test now checks the capital `L` bottom/top
  coverage relationship in addition to system-family, 13-point, 2x, and
  non-missing-pixel assertions.
- Full `make test` passed, including formatting of 104 Dart files, static
  analysis, and the complete product test suite. `make runtime-source-check`
  passed with `tracked=190 native_sources=0`.
- `make RUNTIME_ARCH=arm64 runtime-terminal-display-integration` passed in both
  Developer JIT (1547 ms) and Release AOT (728 ms). The corresponding
  `runtime-bundle-audit` passed for both modes with one runtime helper, one
  renderer asset, and one renderer capability.
- The first 45-second GUI evidence attempt auto-closed before capture; no image
  was produced. The corrected Developer JIT product was relaunched with a
  120-second bound, its normal Metal view and real PTY were confirmed in the
  runtime log, and only its application window was captured.
- The retained 2064x1448 RGBA screenshot is
  `docs/phase4/evidence/glyph-raster-orientation-fixed.png` with SHA-256
  `52be3b21277238e00bcfcba4503a59deb5807272a2b79afcbc2ac243781c6560`.
  Inspection at original resolution confirms upright baselines and readable
  asymmetric text (`Upright CoreText: Readable0O1l ABC xyz`), the macOS system
  monospace 13-point sample, correct SGR colors, and the final prompt. It
  contains fixed diagnostic text rather than a personal shell prompt. The app
  then auto-closed cleanly.
