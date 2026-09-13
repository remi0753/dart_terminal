# Phase 4 — headless/reference renderer and golden image format

- Status: complete
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
- Deterministic linear-light source-over compositing for ordered solid
  rectangles, monochrome coverage masks, and color bitmap layers, with sRGB
  decode/encode at the RGBA8 boundary.
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
- Image protocol layers, hyperlink/search/IME overlays, and antialiasing policy
  beyond accepting prepared 8-bit coverage or RGBA data. Tagged Display P3
  admission was added later by the Phase 11 color-contract revision below.
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

## Golden image format version 1

Artifacts use the `.dtgi` extension and exactly ten newline-terminated ASCII
lines in this order:

```text
dart-terminal-golden-image
version=1
width=<device pixels>
height=<device pixels>
scale=<integer backing scale>
pixel-format=rgba8-srgb-straight
row-stride=<width times four>
payload-length=<stride times height>
checksum=fnv1a32:<eight lowercase hexadecimal digits>
pixels=<canonical Base64>
```

The checksum starts with the FNV-1a-32 offset basis and covers the canonical
NUL-separated format name, version, dimensions, scale, pixel format, stride,
and payload length followed by the exact RGBA bytes. Every multiplication,
decoded allocation, and ASCII envelope is bounded independently. Version 1
allows no reordered/unknown fields, alternate number spelling, omitted final
newline, Base64 whitespace, noncanonical padding, or trailing bytes.

## Acceptance criteria

- The same scene produces byte-identical RGBA pixels at repeated 1x and 2x
  renders with exact scaled dimensions.
- Base, background, selection, glyph, decoration, and cursor order is enforced
  independent of caller list order.
- Alpha blending and coverage decode sRGB to linear light, apply straight-alpha
  source-over, encode sRGB, and round only final RGBA8 storage.
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

### Phase 11 color-contract revision (2026-09-14)

The original Phase 4 oracle blended encoded component bytes with integer
arithmetic. Phase 11 corrected that historical limitation: tagged Display P3
colors and bitmaps convert exactly once to clipped canonical sRGB, while sRGB
inputs remain byte exact; composition decodes canonical sRGB, calculates
straight-alpha source-over in linear light, unpremultiplies transparent output,
and encodes final RGBA8 sRGB. Reference bitmaps convert only active pixels and
preserve row-stride padding. Metal uses matching sRGB atlas/target formats and
allows one output-byte of GPU rounding tolerance.

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
- 2026-09-05: the first checksum prototype used a nominal 64-bit FNV value.
  Fixture generation exposed a negative hexadecimal result because the current
  Dart VM represents that bit pattern as a signed machine integer. The final
  format uses an explicitly masked 32-bit FNV-1a value, avoiding signed/backend
  formatting differences while still covering metadata and pixels.

## Verification results

### Bounded headless RGBA surface and reference layer compositor

- Added public immutable inputs for straight-alpha sRGB colors, solid
  rectangles, monochrome coverage masks, and color RGBA bitmaps. Mask and
  bitmap constructors copy caller data and require exact bounded stride/length
  relationships.
- Added an owned `TerminalReferenceImage` and a deterministic compositor. Its
  original integer source-over implementation was superseded by the Phase 11
  linear-light contract above; clipping, exact 1x–4x expansion, and terminal
  presentation order remain unchanged.
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

### Versioned golden codec, fixture, and bounded comparison diagnostics

- Added a strict `.dtgi` version 1 codec with fixed ASCII field order,
  canonical unsigned decimals/Base64, exact RGBA stride and payload length, and
  metadata-plus-pixel FNV-1a-32 checksum. Encode checks the final envelope size
  before copying or Base64-encoding pixels; decode rejects non-ASCII,
  malformed/reordered fields, unsupported format/version/checksum, corrupt
  length/checksum, noncanonical payload, missing final newline, and trailing
  data.
- Codec limits independently bound encoded bytes and reuse the renderer's
  logical dimension, scale, and pixel caps before payload decoding. Both the
  encoded input and decoded image own their storage.
- Added exact geometry/scale/pixel comparison. A mismatch reports only the
  first coordinate and expected/actual `0xRRGGBBAA` under a hard diagnostic
  cap; the typed assertion exception never embeds either full image and also
  bounds its caller-provided description.
- Checked in reviewed fixed-scene 1x and 2x artifacts under
  `test/goldens/reference/`. Ordinary tests regenerate bytes only in memory,
  compare them exactly to the source-controlled artifacts, decode them, and
  compare pixels. A deliberate reviewed update uses the explicit
  `--write-goldens` argument.

- Focused tests cover byte-exact repeat encoding and ownership-preserving round
  trip; corrupt format/version/order/numeric spelling/pixel format/stride/
  length/checksum/Base64/trailing data; non-ASCII and out-of-byte input; encode,
  decode, pixel, and scale limits; equal, geometry-mismatch, pixel-mismatch,
  bounded diagnostic, typed assertion, and bounded description paths; and
  exact 1x/2x checked-in fixtures.
- `dart analyze` passed with no issues. `make test` passed dependency
  resolution, VT table freshness, formatting of 79 Dart files with zero
  changes, full analysis, all unit/integration tests, and the real PTY suite.
  `make runtime-source-check` passed with 147 tracked files and zero native
  source files. The focused codec/fixture test compiled and passed as a Release
  AOT executable at `/private/tmp/dart-terminal-golden-image-test`.
- `git diff --check` passed. README and feature matrix now expose the completed
  reference/golden oracle; no CoreText, Metal, FFI, runtime package, or adjacent
  repository source changed in this roadmap item.

This completes ordered subtask 2 and the parent reference renderer/golden
image task. The CoreText font catalog, fallback, metrics, and shaping cache is
the next Phase 4 roadmap item.
