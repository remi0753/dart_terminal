# Phase 4 — larger zero-config default font size

- Status: complete
- Date: 2026-09-06
- Scope: Phase 4 zero-config readability follow-up
- Related: TXT-05, REN-01–03, CFG-03

## Purpose

Increase the normal terminal's zero-config macOS system monospace size from 13
points to 14 points, then verify that the resulting live Metal window remains
upright, correctly laid out, and more comfortably readable.

## Background

The preceding repairs selected AppKit's system monospace family, pinned the
platform-standard 13-point size, and corrected vertically inverted glyph
rasters. The user confirmed the orientation repair and requested a slightly
larger default. In the absence of a requested numeric size, this task interprets
"slightly larger" as a one-point increase to 14 points (about 7.7%).

## Scope

- Change the product-owned live-surface default from 13 to 14 logical points.
- Update focused and packaged real-PTY acceptance to require 14 points.
- Preserve the symbolic macOS system-monospace family and top-down CoreText
  glyph publication.
- Rebuild, test, launch, and visually inspect the normal product at the new
  default.

## Out of scope

- Font family selection, adjustable font-size preferences, zoom actions,
  settings UI, and live configuration reload; these remain later roadmap work.
- Changing the reusable renderer package's independent default configuration.
- Changing terminal grid, wrapping, scrollback, or Metal sampling rules beyond
  the metric-driven effects of the larger font.

## Dependencies and ownership

- `TerminalLiveMetalSurface` owns the zero-config product font policy.
- CoreText metrics continue to determine cell dimensions and baseline; the
  existing resize path derives rows and columns from those metrics.
- `dart_appkit` already accepts arbitrary valid point sizes and needs no source
  change unless verification exposes a defect.

## Completion criteria

- The product constant, focused native-backed test, and packaged display
  acceptance consistently require 14 points.
- Full product tests, analysis, formatting, runtime source audit, Developer JIT
  and Release AOT display integration, and bundle audits pass.
- A normal Developer JIT Metal/PTY window screenshot is inspected at original
  resolution and shows upright, readable 14-point text and a visible prompt.
- ROADMAP, README, FEATURE_MATRIX, and this memo accurately describe the new
  default; the task is committed with both worktrees clean.

## Verification plan

- Run the focused live-surface font test first.
- Run `make test` and `make runtime-source-check`.
- Run `make RUNTIME_ARCH=arm64 runtime-terminal-display-integration` and
  `make RUNTIME_ARCH=arm64 runtime-bundle-audit`.
- Launch the normal Developer JIT application with a bounded auto-close period,
  capture only its window, and inspect the retained screenshot.

## Investigation log

- 2026-09-06: `dart_terminal` was clean at `145c40a`; adjacent `dart_appkit`
  was clean at `d55bd6e`. Phase 5 was the first unchecked phase before this
  user-requested Phase 4 readability follow-up was registered.
- 2026-09-06: the product default is isolated as
  `TerminalLiveMetalSurface.defaultFontPointSize = 13`. The focused live font
  test asserts 13 points and the packaged display integration requires
  `font_size=13.0`; these are the only executable product contracts that need
  updating. `TerminalRenderFontConfiguration` has an unrelated reusable
  14-point default and is not the live zero-config policy.

## Design decision

Use 14 points: it is the smallest whole-point increase, keeps the current
system family and all renderer ownership unchanged, and satisfies the request
without anticipating Phase 8 font-size or zoom controls.

## Verification results

- 2026-09-06: `TerminalLiveMetalSurface.defaultFontPointSize`, the focused
  native-backed assertion, and the packaged display acceptance were changed
  together from 13 to 14 points. The empty-family system-monospace policy and
  top-down glyph orientation remain unchanged.
- 2026-09-06: the first sandboxed focused-test attempt reached the Metal build
  hook but could not write macOS Clang/Dart caches outside the workspace. The
  same test was rerun with host cache access and passed; this was an environment
  restriction, not a product failure.
- 2026-09-06: full `make test` passed: the generated VT table was current, 104
  Dart files required no formatting changes, static analysis reported no
  issues, and the complete product test suite passed.
- 2026-09-06: `make runtime-source-check` passed with `tracked=192` and
  `native_sources=0`.
- 2026-09-06: `make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`
  passed the real-PTY Metal acceptance with `font_size=14.0` in Developer JIT
  (1306 ms) and Release AOT (736 ms).
- 2026-09-06: `make RUNTIME_ARCH=arm64 runtime-bundle-audit` passed both modes
  with one helper, one renderer asset, and one capability each.
- 2026-09-06: the normal Developer JIT product was launched with a bounded,
  fixed diagnostic shell profile. Logs confirmed the dependency-owned Metal
  view, real PTY, worker lifecycle, and clean automatic shutdown.
- 2026-09-06: the retained 2064x1448 RGBA window capture is
  `docs/phase4/evidence/larger-default-font-size-14pt.png`, SHA-256
  `793b9617653ed8ceb604ffd14e98b71af691ed9dcb34ed60b8f94cec9fc8a317`.
  Original-resolution inspection confirms that `14 point CoreText`,
  `Readable0O1l ABC xyz`, the system-monospace label, prompt, and cursor are
  upright, correctly aligned, and readable at the enlarged default. The image
  contains no personal shell prompt or path.
- 2026-09-06: README and FEATURE_MATRIX now publish the 14-point current
  default. No `dart_appkit` change was required, and all completion criteria are
  satisfied.
