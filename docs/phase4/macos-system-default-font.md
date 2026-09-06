# Phase 4 — macOS system default terminal font repair

- Status: complete
- Date: 2026-09-06
- Scope: Phase 4 zero-config readability repair
- Related: TXT-03, TXT-05, REN-01–03, CFG-03

Follow-up: the family-selection decision remains current, while the product
point size was subsequently increased from 13 to 14 points in
`larger-default-font-size.md` at the user's request.

## Purpose

Use the macOS system monospaced font at the macOS standard system font size for
the zero-config live Metal terminal. A newly launched terminal must start with
a legible platform-native default without waiting for Phase 8 customization.

## Background

The live surface currently calls `TerminalFontCatalog.open()` without an
explicit product policy. The renderer package default is the named `Menlo`
family at 14 points. The product therefore does not exercise the existing
empty-family contract that delegates font selection to
`NSFont.monospacedSystemFontOfSize`.

The user confirmed that SGR styling and bottom-prompt visibility now work, but
reported that the rendered font is not practically legible. Font family,
font-size, and zoom controls remain correctly scheduled for Phase 8; this task
only repairs the zero-config default required by Phase 4 rendering correctness.

## Scope

- Define one explicit product default for the live Metal surface.
- Select the system monospaced face through the renderer package's empty-family
  contract instead of naming a bundled/system face.
- Use the current macOS standard system font size on the baseline OS.
- Add native-backed regression coverage proving the selected face is
  monospaced, non-fallback Latin at the expected point size.
- Preserve current CoreText fallback, shaping, glyph-atlas, backing-scale, grid,
  and renderer ownership behavior.

## Out of scope

- Font family or size preferences, zoom actions, configuration files, settings
  UI, live font reload, or per-pane font choices; these remain Phase 8.
- Changing the renderer package's reusable `Menlo 14pt` API default or its
  source-controlled Phase 4 golden corpus.
- Redesigning font smoothing, shader sampling, fallback policy, or synthetic
  glyphs unless focused verification proves they block this repair.

## Dependencies and ownership

- `TerminalLiveMetalSurface` owns the zero-config product font policy and opens
  its generation-owned `TerminalFontCatalog` before shaping/atlas creation.
- In `dart_terminal_renderer_macos`, an empty family already maps to
  `NSFont.monospacedSystemFontOfSize(..., NSFontWeightRegular)`. No adjacent
  repository change is required.
- CoreText metrics remain the sole source for terminal row/column sizing and
  baseline placement. Point size is expressed in logical points; the existing
  atlas scale maps it to backing pixels.

## Completion criteria

- The normal product live surface opens the empty-family macOS system monospace
  catalog at 13 points.
- Latin resolves to a non-fallback monospaced system face and finite positive
  cell/baseline metrics.
- CJK/emoji fallback, 1x/2x raster ownership, grid sizing, and live Metal display
  integration do not regress.
- Product tests, analysis, format, source audit, both application bundles, and
  real-PTY live-display acceptance pass.
- ROADMAP, README, FEATURE_MATRIX, and this record accurately describe the
  resulting default and the Phase 8 customization boundary.

## Verification plan

- Add a focused native-backed product test for the live-surface default catalog
  policy and metrics.
- Run `make test` and `make runtime-source-check`.
- Run `make runtime-terminal-display-integration` for Developer JIT and Release
  AOT; run the broader proportional runtime gate if focused results expose an
  ownership or packaging risk.
- Review the full diff, whitespace, worktree ownership, and generated artifacts
  before marking the task complete.

## Investigation log

- 2026-09-06: both `dart_terminal` at `d0a6e12` and adjacent `dart_appkit` at
  `e050c05` were clean before the task. Phase 5 was the first unchecked roadmap
  phase, so this user-requested rendering repair was registered at the end of
  Phase 4 before implementation.
- 2026-09-06: `TerminalLiveMetalSurface.attach` opens
  `TerminalFontCatalog.open()` with no arguments. The renderer package defaults
  that reusable API to `Menlo` at 14 points.
- 2026-09-06: the renderer's existing native empty-family path calls
  `NSFont.monospacedSystemFontOfSize` with regular weight. Its test already
  proves that the resulting face is monospaced, so changing the product call
  does not require modifying `dart_appkit`.
- 2026-09-06: a sandboxed `xcrun swift` probe could not write Swift's module
  cache. Repeating the same read-only AppKit query with approved host access
  reported `NSFont.systemFontSize == 13.0` and
  `.AppleSystemUIFontMonospaced-Regular` on the current baseline host.

## Design decision

Keep the platform font family symbolic (`''`) and pin the observed standard
size to 13 points in the product policy. Naming the private PostScript result
would bypass AppKit's platform selection, while changing the renderer package's
general default would rewrite existing API expectations and goldens unrelated
to the product repair. Phase 8 may later replace the product policy with typed
user configuration without changing the native font boundary.

## Verification results

- 2026-09-06: `TerminalLiveMetalSurface.attach` now explicitly opens the font
  catalog with an empty family and 13-point size. The empty family reaches the
  renderer package's AppKit system-monospace path; the generic renderer package
  default and its Menlo-based goldens remain unchanged.
- 2026-09-06: the content-free live-surface snapshot publishes only whether the
  system-monospace path is active and the effective point size. The packaged
  real-PTY display acceptance now requires `system_font=true` and
  `font_size=13.0` in addition to the existing SGR, wrap, bottom-prompt,
  newest-frame, and bounded-frame invariants.
- 2026-09-06: the focused test initially hit the same sandbox-only Clang module
  cache restriction as the AppKit probe. With approved host cache access, its
  first source revision then exposed a missing standalone `main` entry point;
  adding that test entry point corrected the harness rather than weakening an
  assertion.
- 2026-09-06: the final focused native-backed test passed. It opens the exact
  product policy, resolves `Readable0O1l` as non-fallback monospaced Latin with
  no missing glyph, validates finite positive grid metrics, and verifies every
  unique glyph produces nonempty nonzero CoreText alpha pixels at 2x.
- 2026-09-06: final `make test` passed: the generated VT table was current, 104
  Dart files were formatted, analysis reported no issues, and the complete
  native-backed test runner passed.
- 2026-09-06: `make runtime-source-check` passed with `tracked=188` and
  `native_sources=0`.
- 2026-09-06: `make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`
  rebuilt and passed the real-PTY live Metal acceptance in Developer JIT
  (1256 ms) and Release AOT (733 ms), including the new system-font/size
  contract.
- 2026-09-06: `make RUNTIME_ARCH=arm64 runtime-bundle-audit` rebuilt and passed
  both Dart-only arm64 bundles with one helper, one native asset, and one
  capability each. No adjacent `dart_appkit` source change was needed.
- 2026-09-06: README and FEATURE_MATRIX now expose the zero-config default while
  retaining font family/size selection and zoom in Phase 8. All completion
  criteria are satisfied and Phase 4 is closed again.
