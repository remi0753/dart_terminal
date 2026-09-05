# Phase 4 — headless/reference renderer and golden image format

- Status: in progress
- Date: 2026-09-05
- Scope: first Phase 4 roadmap item
- Related: ADR-003, ADR-004, REN-02, REN-07, TXT-01, TXT-06

## Purpose

Create a deterministic, Dart-only correctness oracle before CoreText and Metal
become product dependencies. The oracle must render the same prepared visual
layers that the native renderer will consume, preserve exact RGBA pixels in a
bounded versioned artifact, and report the first useful mismatch without
silently accepting truncated data.

## Background

Phase 3 owns terminal meaning in private Struct-of-Arrays grids. ADR-003 keeps
selection, cursor, search, hover, and IME state as overlays rather than cell
fields. ADR-004 requires Dart to retain the applied logical render model, build
only the newest frame, and submit packed work to native Metal through coarse
calls. A reference renderer therefore belongs on the Dart side and must not
depend on AppKit, Metal, CoreText, FFI, a filesystem, a clock, or locale.

The existing `TerminalMetalView` capability is a paused, on-demand view shell.
It has no shader, draw submission, glyph atlas, or frame lifecycle yet. Phase 0
proved a packed Metal submission and coarse CoreText shaping boundary, but its
native spike source was intentionally retired and is historical evidence only.

## Scope

- A bounded RGBA8 sRGB image with exact dimensions, scale, stride, and owned
  pixel storage.
- Integer, source-over compositing for ordered solid rectangles, monochrome
  coverage masks, and color bitmap layers.
- Explicit terminal draw order: base background, cell backgrounds, selection,
  glyphs, decorations, cursor.
- Clipping, scale conversion, input validation, and deterministic rendering.
- A versioned bounded golden image codec with checksum and strict decoder.
- Source-controlled fixtures and bounded first-pixel comparison diagnostics.

## Out of scope

- Font discovery, fallback, shaping, rasterization, and glyph caching; these
  are the next Phase 4 roadmap item.
- Atlas allocation and Metal resources, shaders, drawables, scheduling, or
  product view attachment.
- Image protocol layers, hyperlink/search/IME overlays, P3 conversion, and
  antialiasing policy beyond accepting prepared 8-bit coverage or RGBA data.
- Updating golden artifacts automatically from a passing/failing test.

## Dependencies and ownership

- Terminal core remains the sole owner of semantic grid state and resources.
- A future frame builder will convert terminal state, shaping results, and
  overlay state into the reference layer types and the native packed draw list.
- The reference compositor owns its output bytes and never mutates caller
  layer data.
- The golden decoder owns decoded bytes and rejects malformed dimensions,
  lengths, flags, checksum, trailing data, and configured-limit violations
  before exposing an image.

## Ordered subtasks

1. **Bounded headless RGBA surface and reference layer compositor**
   - Define immutable geometry/color/layer inputs and owned image output.
   - Implement clipped integer source-over blending for solid, mask, and color
     layers in the terminal presentation order.
   - Cover 1x/2x scale, overlapping alpha, clipping, input immutability,
     ordering, and every configured bound.
   - Complete after focused and full tests, analysis, formatting, source audit,
     documentation update, roadmap child update, and an individual commit.
2. **Versioned golden codec, fixture, and bounded comparison diagnostics**
   - Define and document a deterministic binary format with exact checksum.
   - Add strict encode/decode and first-pixel comparison diagnostics.
   - Check in a reviewed fixture produced from fixed layer input, but never add
     an in-test rewrite path.
   - Complete after corruption/limit/fixture round-trip tests, focused Release
     AOT execution, full verification, parent roadmap/matrix/readme updates,
     and an individual commit.

The second subtask depends on the stable image and compositor contract from the
first. The CoreText roadmap item must not begin until both are committed.

## Acceptance criteria

- The same scene produces byte-identical RGBA pixels at repeated 1x and 2x
  renders with exact scaled dimensions.
- Base, background, selection, glyph, decoration, and cursor order is enforced
  independent of caller list order.
- Alpha blending and coverage use documented integer rounding and do not vary
  with platform floating-point behavior.
- All dimensions, pixel products, primitive counts, mask/bitmap strides, and
  encoded bytes have hard limits and checked arithmetic.
- A golden round trip is byte exact; malformed/corrupt/oversized input is
  rejected and trailing bytes are never ignored.
- Comparison identifies the first differing `(x, y)` and expected/actual RGBA
  values using bounded output.
- The implementation is Dart-only and has no AppKit, Metal, CoreText, FFI,
  filesystem, clock, locale, or mutable-global dependency.

## Verification plan

- Focused unit tests for layer ordering, clipping, 1x/2x scaling, alpha and mask
  rounding, color glyph pixels, immutability, invalid data, and limits.
- Codec tests for exact bytes, round trip, header/version/field/checksum/trailing
  corruption, configured limits, comparison equality, and useful mismatch.
- A checked-in fixture compared both as exact encoded bytes and decoded pixels.
- `dart analyze`, `make test`, focused Release AOT execution,
  `git diff --cached --check`, and `make runtime-source-check`.

## Investigation log

- 2026-09-05: reread `README.md`, the complete roadmap and feature matrix,
  ADR-003/004, Phase 0 Metal/CoreText evidence, current terminal screen/style/
  palette/grapheme APIs, the custom test runner, and the dependency-owned
  `dart_terminal_renderer_macos` package. The worktrees were clean. The first
  unchecked roadmap task is the Phase 4 reference renderer/golden format.
- 2026-09-05: confirmed no production render model or golden image format
  exists. The native capability currently creates only a paused flipped
  `MTKView`, so this task can remain entirely Dart-only and avoid prematurely
  coupling the oracle to CoreText or Metal object lifetimes.
- 2026-09-05: selected prepared visual layers rather than a hard-coded bitmap
  font. Font fallback, ligature clusters, color glyphs, and synthetic glyphs
  have distinct later contracts; a layer oracle can validate their placement,
  blending, clipping, scale, and draw order without inventing a competing font
  implementation.
- 2026-09-05: the first implementation review found that materializing an
  arbitrary primitive `Iterable` before checking its length could retain
  unbounded input. Admission now stops on the first excess item and checks
  cumulative source bytes while enumerating. A generator regression test
  confirms the renderer does not request further values.

## Verification results

### Bounded headless RGBA surface and reference layer compositor

- Added public immutable inputs for straight-alpha sRGB colors, solid
  rectangles, monochrome coverage masks, and color RGBA bitmaps. Mask and
  bitmap constructors copy caller data and require exact bounded stride/length
  relationships.
- Added an owned `TerminalReferenceImage` and a deterministic compositor. It
  uses only integer source-over arithmetic with documented divide-by-255
  rounding, clips logical coordinates, expands source pixels exactly at 1x–4x,
  and enforces the terminal presentation order regardless of caller list order.
- Image dimensions, logical dimensions, scale, pixel count, primitive count,
  source bytes, clipping domain, packed colors, opacity, and source shapes are
  validated before use. Output access returns copies or a bounds-checked packed
  pixel, so neither source nor result can be mutated through a retained buffer.
- Focused tests cover independent layer ordering, stable same-layer ordering,
  mask and color-bitmap blending, transparent destination arithmetic, negative
  clipping, 2x output, ownership, lazy iterable admission, and every public
  limit/shape validation path.
- `dart analyze` passed with no issues. The focused JIT test passed. `make test`
  passed dependency resolution, generated VT table freshness, formatting of 77
  Dart files with zero changes, full analysis, all unit/integration tests, and
  the real PTY suite. `make runtime-source-check` passed with 144 tracked files
  and zero native source files. The focused test compiled and passed as a
  Release AOT executable at
  `/private/tmp/dart-terminal-reference-renderer-test`.

This completes ordered subtask 1. The versioned golden codec, checked-in
fixture, and comparison diagnostics are now the first unchecked child.
