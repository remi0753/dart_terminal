# Phase 4 — Monochrome/color glyph raster and atlas

- Status: in progress
- Date: 2026-09-06
- Scope: third Phase 4 roadmap item
- Related: ADR-001, ADR-004, TXT-01, TXT-03, TXT-05–07, REN-03, REN-07

## Purpose

Turn generation-owned CoreText face/glyph identities into bounded copied alpha
or color bitmaps, then retain them in Dart-owned monochrome and color atlas
pages with deterministic generation, growth, lookup, and eviction behavior.
Connect those bitmaps to the CPU reference renderer so the required 1x/2x text
corpus has actual checked-in pixel goldens before Metal consumes the atlas.

## Background

The preceding task established ABI-v3 whole-run shaping. Each glyph now has a
catalog generation, face ID, glyph ID, position, advance, and UTF-16 cluster.
The native catalog intentionally owns `CTFont` objects while Dart owns cache
and terminal meaning. ADR-004 requires atlas resource IDs/generations and
prohibits eviction while ready/in-flight submissions reference an entry. The
Metal submission lifetime does not exist yet, so this task establishes explicit
pin tokens that the later frame task can bind to command completion.

The first Phase 4 task already provides a deterministic straight-alpha RGBA CPU
compositor and versioned image codec. Raster output must therefore distinguish
alpha masks from straight RGBA color glyphs and expose baseline-relative pixel
bounds without leaking Core Graphics or CoreText objects.

## Scope

- Add an ABI-v4 coarse batch raster call on the existing font catalog handle.
- Resolve shaped face IDs back to catalog-owned `CTFont` instances and render
  glyph IDs at a fixed-point backing scale.
- Return a strictly versioned, contiguous, size-query-first buffer containing
  copied glyph descriptors and tightly packed alpha8 or straight RGBA8 pixels.
- Bound request count, glyph dimensions, per-batch pixels/bytes, and output
  before publishing bytes; retain no Dart pointer or native bitmap cache.
- Decode immutable raster results in Dart and reject corrupt metadata, padding,
  overlap/gaps, generation/scale/key mismatches, and invalid pixels.
- Build separate bounded alpha/color atlas page sets with stable entry IDs,
  resource generations, deterministic shelf placement, bounded growth, LRU
  eviction, pin/unpin submission tokens, reset, and stale-key rejection.
- Render the version-one text corpus through atlas entries into the reference
  renderer and check in exact 1x/2x golden images.

## Out of scope

- Metal textures, upload calls, shaders, packed cell instances, draw submission,
  command buffers, or actual GPU reference pinning; these begin in the next
  roadmap item.
- Frame/damage queues, display timing, cursor animation, occlusion, resize/font
  rebuild orchestration, or device/shader/drawable recovery.
- Synthetic box/block/Powerline art, Nerd Font installation, font configuration
  UI, arbitrary fractional subpixel placement, or per-glyph FFI calls.

## Dependencies and ownership

- Native catalogs own fonts and synchronously create temporary Core Graphics
  contexts. Output bytes are copied before return and no raster survives native
  completion.
- Dart owns immutable raster objects, atlas pages, eviction policy, entry and
  resource generations, pin tokens, and reference-render primitives.
- Raster and atlas keys include catalog generation, face ID, glyph ID, and
  fixed-point scale. A catalog/scale/reset change cannot alias prior pixels.
- Alpha and color pages never mix pixel formats. Atlas pages and bytes are
  independently capped; zero-area glyphs consume an entry but no page pixels.
- The later Metal frame owner must pin referenced entries until its submission
  token completes. This task tests that contract without inventing GPU work.

## Ordered subtasks

1. **Bounded batched CoreText monochrome/color glyph raster ABI**
   - Add fixed-width request/header/record definitions and ABI-v4 symbol.
   - Store reverse face-ID lookup in each catalog and render complete batches at
     an exact 16.16 pixels-per-point scale.
   - Decode into immutable Dart alpha/RGBA glyphs and test Latin, CJK, emoji,
     combining/ligature glyphs, whitespace, invalid/stale keys, size retry,
     corruption, caps, thread safety, and exact release.
   - Complete after focused/full adjacent tests, product ABI integration and
     source/bundle/AOT checks, documentation/roadmap child update, and separate
     commits in both repositories.
2. **Dart-owned dual atlas pages, eviction, generation, and text goldens**
   - Implement deterministic per-format page allocation, growth, lookup,
     upload deltas, pin tokens, LRU eviction, reset, and stale generation checks.
   - Prove byte/page/entry caps, no pinned eviction, recovery when all candidates
     are pinned, monotonic generations, and color/alpha isolation.
   - Compose corpus glyphs at cell/baseline positions with the reference
     renderer and check in exact version-one 1x/2x goldens.
   - Complete after product/full/AOT validation, parent roadmap/matrix/readme
     updates, and a task commit.

The atlas subtask depends on the raster descriptor and pixel ownership contract.
Metal pipelines must not begin until both children are committed.

## Acceptance criteria

- One bounded synchronous native batch returns every requested glyph in request
  order with exact key, format, device-pixel bounds, stride, and copied bytes.
- Latin/CJK/combining/ligature glyphs produce alpha masks; Apple Color Emoji
  produces nonempty straight-alpha RGBA pixels; whitespace is a valid zero-area
  entry. No record crosses a section or exceeds a declared cap.
- Alpha/color atlas pages never exceed configured dimensions, page counts,
  entry count, or retained bytes. Eviction is deterministic LRU among unpinned
  entries and cannot invalidate a live pin token.
- Every reset/repack increments resource generation. Lookups and pin operations
  reject a catalog, scale, entry, resource, or token generation mismatch.
- Latin, CJK, emoji, combining, wide-cell, and ligature corpus images match
  checked-in 1x/2x golden artifacts through the CPU oracle.

## Verification plan

- C11/C++20 header checks and Objective-C++ native capability tests for format,
  pixels, bounds, size retry, stale handles, release races, and concurrency.
- Renderer package analysis/Dart tests for strict decode and public facade.
- Product atlas/reference/golden tests plus complete `make test` and source
  audit.
- Adjacent full test suite, focused Release AOT facade test, Developer JIT and
  Release AOT bundle audits/integration after every capability ABI change.
- Final staged diff review, both worktrees, and clean official SDK audit.

## Investigation log

- 2026-09-06: after commits `9a60857` and `7168e15`, reread the roadmap and
  confirmed monochrome/color glyph atlas is the first unchecked item. Both
  repositories and the official SDK checkout were clean.
- 2026-09-06: reviewed ADR-004 resource/command lifetime, the ABI-v3 catalog and
  shaping records, Phase 4 reference compositor/golden codec, the version-one
  text corpus, feature matrix gates, package build/test paths, and product
  manifest. Split raster production from atlas retention because they have
  separate owners, failure modes, caps, tests, and commits.
- 2026-09-06: the first native raster compile rejected C++'s empty aggregate
  initializer in the Objective-C C11 source as a C23 extension under the
  package warning-as-error policy. The local copied request now uses the C11
  `{0}` initializer; warning settings were not weakened.
- 2026-09-06: after that compile succeeded, the focused test stopped on its
  intentional exact ABI assertion because it still expected shaping ABI 3.
  Rasterization adds a public symbol and therefore advances the renderer
  capability to ABI 4; the exact assertion is updated with the raster tests.
- 2026-09-06: the first facade analysis invocation used repository-relative
  formatter paths after already changing into the package, so formatting found
  no files. Analysis still ran and identified two API mismatches: this SDK's
  `RangeError.range` signature does not accept a fractional lower bound, and
  indexed FFI struct pointers already return the struct view rather than a
  pointer needing `.ref`. The code now uses `RangeError.value` and direct
  indexed fields; the correct package-local paths are used on rerun.
- 2026-09-06: the first raster behavior-test compile rejected `{0}` for the
  two-field request records under C++'s missing-field-initializer warning. The
  Objective-C C11 copy keeps `{0}`, while C++ test records now spell `{0, 0}`;
  both targets retain their strict warning policies.
- 2026-09-06: completed the first child as renderer ABI 4. Catalogs now retain
  a lock-protected reverse face-ID map, and one request rasterizes up to 4,096
  unique face/glyph keys at an exact 16.16 scale. The 64-byte header and 48-byte
  glyph records cap dimensions at 4,096 and total output at 64 MiB.
- 2026-09-06: monochrome contexts disable font smoothing and copy top-down
  alpha8 coverage. Color-font contexts render premultiplied RGBA internally,
  reverse rows, unpremultiply with clamping, and clear RGB under zero alpha to
  publish straight RGBA8. Both paths add one device-pixel bounds padding and
  report left/top bearings relative to the CoreText baseline. Whitespace is an
  explicit zero-area record; glyph zero is explicitly marked missing.
- 2026-09-06: native input records are copied with `memcpy` before validation,
  and all output is assembled in aligned temporary storage before one final
  copy. This avoids unaligned caller dereference and prevents partial output on
  insufficient buffers or late internal failures.

## Verification results

### Batched CoreText raster subtask

- C11/C++20 public headers passed exact 8-byte request, 64-byte header, and
  48-byte result record checks. Focused native tests passed ABI/version,
  required-size retry, untouched undersized output, request order, exact
  sections, duplicate/unknown/invalid/capped inputs, stale generation, alpha,
  straight color, transparent RGB clearing, whitespace, 1x/2x storage, and 40
  concurrent mixed batches across four threads.
- Renderer package analysis and Dart tests passed strict handcrafted-buffer
  corruption, immutable copy ownership, live Latin/CJK/emoji/combining/
  ligature/missing/whitespace rasters, 1x/2x scaling, deduplication, request and
  dimension caps, catalog liveness, and cross-generation rejection.
- The complete adjacent `make test` suite passed, including the native bridge,
  runtime assembly, AppKit, PTY, examples, FFI, and renderer package.
- Dart Terminal `make test` passed with every version-one text corpus case
  rasterized at 1x and 2x. `make runtime-source-check` passed with
  `tracked=154` and `native_sources=0`.
- Developer JIT and Release AOT arm64 bundle audits passed with renderer ABI 4;
  GUI integration smokes passed in 2287 ms and 1800 ms respectively.
- The focused renderer facade compiled to Release AOT and passed with the
  tested renderer dylib preloaded. Both diffs passed whitespace checks and the
  official SDK checkout remained clean.
- Adjacent dependency commit: `729685c Add batched CoreText glyph
  rasterization`.
- The raster child is complete. Dart-owned atlas retention, generation,
  eviction/pinning, and checked-in text image goldens remain the next child.
