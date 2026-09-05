# Phase 4 — Metal terminal pipelines

- Status: complete
- Date: 2026-09-06
- Scope: fourth Phase 4 roadmap item
- Related: ADR-001, ADR-002, ADR-004, ADR-005, REN-01, REN-02, REN-03,
  REN-05, REN-07

## Purpose

Replace the Phase 0 procedural workload surrogate with product-owned Metal
pipelines that render the terminal background, cell backgrounds, monochrome
and color glyphs, decorations, cursor, and selection from one bounded packed
frame. Preserve the CPU reference renderer as the correctness oracle and keep
all terminal meaning and frame construction in Dart.

## Background

The preceding Phase 4 tasks provide a deterministic CPU compositor, versioned
1x/2x goldens, generation-owned CoreText shaping/rasterization, and a bounded
Dart-owned alpha/color atlas. The adjacent
`dart_terminal_renderer_macos` capability is currently ABI 4. It owns a paused,
on-demand `DtrTerminalMetalView`, font catalogs, shaping, and rasterization, but
the view has no delegate, shaders, texture resources, packed draw ABI, renderer
handle, or submission path.

ADR-004 accepts a coarse synchronous Dart-to-native copy and native-owned
triple-buffer lifetime. It also requires product bundles to use a precompiled
Metal library; runtime source compilation measured about 84 ms in the Phase 0
spike and is explicitly not an accepted product path.

## Scope

- Define a fixed-width, versioned, little-endian packed draw format with exact
  viewport, frame, atlas-resource, section, count, stride, and reserved-field
  validation.
- Add precompiled Metal vertex/fragment functions and pipeline states for
  ordered solid quads, alpha8 glyph masks, and straight-RGBA8 color glyphs.
- Cover background, cell background, glyph, underline/strike decoration,
  cursor, and selection kinds without moving terminal semantics into shaders.
- Add bounded alpha/color texture-array upload and generation validation using
  the preceding atlas page and dirty-rectangle contracts.
- Establish generation-owned native renderer/view identity and copied
  offscreen/readback coverage sufficient to compare GPU output with the CPU
  oracle. Any required generic AppKit custom-view association stays minimal and
  contains no terminal policy.
- Add a strict Dart encoder/facade and product integration tests. No call may
  retain a Dart pointer or perform per-cell/per-glyph FFI.

## Out of scope

- Logical damage coalescing, application of ordered deltas, or the newest-frame
  scheduling policy; those belong to the next roadmap item.
- Resize/scale/font orchestration, animation/occlusion policy, failure
  recovery, and final metrics, which retain their later roadmap positions.
- Image protocols, overlays beyond selection/cursor, P3/HDR, blur, or arbitrary
  custom shaders.
- Runtime MSL compilation as a product fallback.

## Dependencies and ownership

- Dart owns terminal cells, layer ordering, packed frame bytes, atlas page
  allocation, resource generation, and the CPU oracle.
- The renderer capability owns `MTLDevice`, precompiled `MTLLibrary`, pipeline
  states, textures, GPU-visible copied buffers, commands, and native view
  lifetime. It never owns terminal semantic state.
- AppKit main-thread constraints remain separate from the render coordinator.
  No AppKit handler waits for a drawable, compiler, GPU fence, or Dart callback.
- The product repository remains Dart-only. Objective-C and MSL belong only to
  the adjacent terminal renderer capability and are staged as a native code
  asset.

## Ordered subtasks

1. **Packed native pipeline and precompiled shader capability**
   - Add exact C/C++ ABI layouts, renderer/resource handles, bounded atlas
     uploads, precompiled shader embedding/loading, pipeline creation, and
     native GPU/readback tests for all six terminal visual kinds.
   - Prove malformed/stale/capped inputs, straight-alpha blending, resource
     ownership, no partial publication, and exact release.
   - Complete with focused and adjacent full validation plus an adjacent
     dependency commit.
2. **View-bound triple-buffer submission and presentation**
   - Associate a renderer generation with exactly one terminal view without
     exposing an Objective-C object or forgeable AppKit handle through Dart.
   - Add three fixed native frame slots, immediate accepted/backpressure/stale
     results, newest-ready selection, drawable presentation, command-completion
     ownership, and exact detach/release behavior required by ADR-004.
   - Prove the synchronous submission call only validates/copies, never waits
     for a drawable or GPU fence, and never reuses an in-flight slot.
3. **Dart encoder, facade, atlas bridge, and product GPU goldens**
   - Encode immutable packed frames and uploads with strict limits and layer
     ordering, bridge `TerminalGlyphAtlas` snapshots/deltas, and expose bounded
     renderer operations without raw native objects.
   - Compare representative 1x/2x GPU readback against the existing CPU oracle,
     then run product/full/AOT/bundle validation and commit the product task.

The parent remains incomplete until all children are independently validated
and committed. The following damage/frame task must not begin earlier.

## Acceptance criteria

- A checked-in MSL source is compiled before application launch and the native
  capability loads only the embedded/prepackaged Metal library in normal use.
- One packed frame represents every required terminal visual kind and is
  completely rejected on any invalid version, length, count, stride, reserved
  field, coordinate, kind, atlas slot, or stale generation.
- Alpha8 glyphs tint coverage with the supplied color; straight-RGBA8 glyphs
  retain color; ordered source-over blending and top-down coordinates agree
  with the CPU oracle at 1x and 2x within an explicitly justified pixel policy.
- Texture dimensions/pages/bytes and frame instances/bytes are bounded. Native
  retains no caller pointer, and renderer/resource handles reject stale or
  double release.
- Pipeline/library construction occurs outside AppKit input and draw handlers.

## Verification plan

- Compile public headers as C11 and C++20 and run Objective-C++ native tests on
  a real Metal device, including offscreen readback and lifetime/error cases.
- Run adjacent package analysis/Dart tests and the complete adjacent suite.
- Run product encoder/atlas/reference/golden tests, `make test`, and the
  Dart-only source audit.
- Compile and execute a focused Release AOT public-facade test, then run
  Developer JIT and Release AOT bundle audits/integration because the renderer
  capability ABI and staged native asset will change.
- Review staged/unstaged diffs, both repositories, and the official SDK state
  before each child commit.

## Investigation log

- 2026-09-06: after product commit `d37c75d`, reread `ROADMAP.md`. The dual
  atlas parent and both children are complete, both worktrees are clean, and
  Metal terminal pipelines are the first unchecked Phase 4 item.
- 2026-09-06: reread the product goals/matrix, ADR-001/002/004/005, the Phase 0
  100,000-instance report, current reference/atlas APIs, product build/tests,
  and the adjacent renderer header, Objective-C implementation, Dart facade,
  build hook, native tests, and package documentation.
- 2026-09-06: the current capability has no MSL or metallib artifact. Repository
  and Xcode searches found only unrelated system/Xcode framework metallibs; no
  Phase 0 shader artifact remains available for a reproducible product build.
- 2026-09-06: `xcrun --find metal` resolves Xcode's driver, but invoking it
  reports `missing Metal Toolchain` and instructs use of
  `xcodebuild -downloadComponent MetalToolchain`. `xcrun --find metallib` also
  fails. An Xcode component query then fails while loading
  `IDESimulatorFoundation` because `/Library/Developer/PrivateFrameworks/
  CoreSimulator.framework` is absent, indicating the local Xcode component
  installation also needs repair/first-launch completion.
- 2026-09-06: runtime `newLibraryWithSource` was considered and rejected. It
  would bypass the missing build dependency but violate the accepted ADR and
  known cold-start result rather than complete this task. Implementing an
  untestable packed/native path or proceeding to later roadmap work is also not
  acceptable.
- 2026-09-06: after the environment was repaired, both required `xcrun`
  checks succeeded and the Metal compiler printed its normal help. The trailing
  broken-pipe diagnostic came only from intentionally truncating help output;
  the missing-toolchain error is gone. Resume ordered subtask 1.
- 2026-09-06: the first real MSL compile reached the installed compiler but the
  sandbox denied its Clang module-cache writes under `~/.cache/clang`. No
  shader diagnostic was emitted. Re-run the identical compile with explicit
  host filesystem approval rather than changing compiler/cache policy.
- 2026-09-06: the first native link build embedded the precompiled metallib but
  failed because this SDK does not expose `DISPATCH_DATA_DESTRUCTOR_NONE`.
  Pipeline setup now makes one bounded heap copy of the embedded 11.7 KiB
  library and transfers it to dispatch data with the supported FREE destructor;
  runtime shader compilation remains absent.
- 2026-09-06: the first post-resumption capability compile caught use of the
  mutable-data allocation selector on immutable `NSData`. The retained
  zero-page buffers now use `NSMutableData` only for construction and remain
  exposed internally as immutable `NSData`; this keeps atlas generation/page
  clears allocation-free after renderer creation and prevents partial
  generation publication on an allocation failure.
- 2026-09-06: review against accepted ADR-004 found that deterministic
  synchronous offscreen readback is necessary but cannot stand in for the
  production submission lifetime. The roadmap and this memo now track a
  separate ordered native child for one-view ownership, three fixed copied
  slots, immediate backpressure, newest-ready selection, drawable presentation,
  and GPU-completion release before the Dart facade child. This first child
  remains limited to the packed format, precompiled pipelines, bounded atlas
  resources, and deterministic GPU correctness surface.
- 2026-09-06: native ABI version 5 now defines fixed 48-byte renderer config,
  64-byte summary, 80-byte atlas upload/header, and 48-byte instance layouts.
  Renderer creation enforces 4,096-pixel dimensions, 131,072 instances, 16
  pages per format, 64 MiB aggregate atlas storage, and 8 MiB packed frames.
  Inputs are copied only after their size/version prefix is accepted; output is
  published only after device, queue, library, pipelines, textures, generation
  tables, and allocation-free zero pages all exist.
- 2026-09-06: the MSL vertex path maps top-left device pixels to Metal NDC and
  the fragment path handles solid quads, tinted alpha8 masks, and straight
  RGBA8 glyphs. One ordered draw covers cell background, selection, alpha/color
  glyph, decoration, and cursor layers. RGBA8 source-over blending is explicit.
- 2026-09-06: atlas dirty uploads validate exact tight row/byte layout, page
  bounds, renderer/atlas/page generations, and the 32-bit page-generation field
  consumed by packed instances. New atlas generations clear all page identity
  and contents; a new page generation clears that slice before accepting dirty
  rectangles. Old frames/uploads fail closed.
- 2026-09-06: a clang-format dry-run was investigated but is not a repository
  gate: it reports hundreds of pre-existing style differences throughout the
  previously committed renderer source and tests. Applying it would rewrite
  unrelated historical code, so the task retained the established local style
  and used compiler warnings-as-errors plus `git diff --check` instead.
- 2026-09-06: after product commit `7a48f64`, reread the Phase 4 roadmap and
  ADR-004. The view-bound triple-buffer child is now the first unchecked item;
  both repositories are clean. Its non-negotiable boundary is an immediate
  validated copy into three fixed native slots, with drawable/GPU work only in
  the native view callback and slot retirement only after drop or command
  completion.
- 2026-09-06: reviewed ways to bind the independent renderer handle to the
  registered terminal view. A public Dart/AppKit handle accessor and a global
  pending-view singleton were rejected as forgeable or order-dependent. The
  selected minimal generic extension is a provider-owned opaque custom-view
  operation: `dart_appkit` validates the view handle/provider on the AppKit main
  thread and invokes the registered native callback with the `NSView` pointer
  entirely inside native code. The renderer binding payload carries only a
  versioned renderer handle/generation and will later be hidden by the Dart
  facade.
- 2026-09-06: submission tokens will be monotonic per renderer. A bounded state
  snapshot reports the greatest token below every still-ready/in-flight token,
  allowing Dart to retire atlas pins without an unbounded completion queue.
  Every atlas upload is backpressured while any slot references the texture;
  this conservative first implementation prevents CPU replacement from racing
  a GPU read even when a same-generation dirty rectangle is logically disjoint.
  Dart atlas allocation and pin policy still determine entry lifetime.
- 2026-09-06: the first object-lifetime assertion exposed that a command
  completion block strongly capturing its renderer could keep the renderer,
  command queue, and completed command alive beyond explicit detach. The
  completion now promotes a weak renderer reference only while updating live
  state. Metal itself retains the encoded pipeline, textures, drawable, and
  slot buffer for command lifetime, so worker release can invalidate/detach the
  renderer without either a retain cycle or premature GPU resource reuse.
- 2026-09-06: splitting the detach and live-object assertions showed that the
  view detached correctly while transient Objective-C references survived in
  the caller's outer autorelease pool. Converting the registry lookup from an
  object-returning C function to an explicit ARC strong out-parameter removed
  one possible implicit autorelease but did not alone clear the assertion.
  Temporary retain-count/deallocation diagnostics showed that synthesized
  reads of the view's strong `terminalRenderer` property and normal Metal/
  Objective-C autorelease scopes may keep the detached object alive until the
  surrounding pool drains, even though its handle is already invalid and its
  view is detached. Runtime identity checks now read a scalar generation and
  registry lookup uses an ARC strong out-parameter, eliminating avoidable
  implicit object returns. The public debug count deliberately remains the
  live registry-handle count; temporary diagnostics confirmed detached objects
  deallocate when their legitimate command/autorelease ownership drains, and
  were then removed.
- 2026-09-06: after product commit `e06848b`, reread `README.md`,
  `FEATURE_MATRIX.md`, the Phase 4 roadmap, this task memo, the native ABI, the
  existing Dart CoreText facade, `TerminalGlyphAtlas`, reference/golden tests,
  manifest, and both build systems. Both repositories are clean and the Dart
  encoder/facade/atlas-bridge child is now the first unchecked item.
- 2026-09-06: the native atlas uses format-local zero-based texture slices,
  while the Dart atlas deliberately exposes monotonic global page IDs. The
  product bridge therefore needs stable per-format page-ID-to-slice maps; page
  IDs must never be passed as native slice indexes or compacted when another
  page is removed. Monotonic page generations make safe slot reuse possible.
- 2026-09-06: `TerminalGlyphAtlas.takePendingUploads()` clears its dirty set,
  so a bridge must retain copied uploads across native backpressure. Advancing
  the atlas resource generation for an ordinary dirty rectangle must preserve
  unchanged native slices; clearing every texture on each resource-generation
  advance would erase valid pages that have no new dirty rectangle. Native
  generation handling will therefore advance the whole-snapshot identity while
  only a newer page generation clears its own reused slice.
- 2026-09-06: selected a strict immutable little-endian Dart encoder in the
  renderer package, typed create/upload/submit/state/readback outcomes, and a
  generic `View` custom-operation method that exposes copied bytes but neither
  an Objective-C object nor a native handle. The product-owned atlas bridge
  will validate atlas ownership/generation, hold backpressured uploads, map
  stable slices, and pin accepted glyph entries until the native retirement
  watermark passes their submission tokens.
- 2026-09-06: the first Dart facade test run caught a test-only offset error:
  the packed instance color begins at byte 32 of the 48-byte record (absolute
  frame offset 112), not byte 36. The encoder itself matched the native ABI;
  the exact-layout assertion was corrected to the documented field offset.

## Blocker and resumption

Resolved on 2026-09-06. The required Apple Metal Toolchain is installed and
invocable. The original failure and its safe resumption checks remain recorded
above for reproducibility.

The historical resumption gate was both commands succeeding:

```sh
xcrun --find metal
xcrun -sdk macosx metal -help
```

The second command now prints compiler help rather than the missing-component
error. All three ordered subtasks are complete; this gate remains documented so
the precompiled shader build can be diagnosed reproducibly.

## Verification results

- All three ordered subtasks and the Metal pipeline parent are complete.
- Both `xcrun --find metal` and `xcrun -sdk macosx metal -help` succeed after
  Xcode component repair. The checked-in MSL compiles to an 11,736-byte
  `MetalLib executable (MacOS), version 1.2.7`; the built renderer has an exact
  11,736-byte `__DATA,__dtrlib` section and exports the seven renderer ABI
  symbols. Source audit finds no `newLibraryWithSource` runtime compiler path.
- `make terminal-renderer-native-test` passes C11/C++20 layout/symbol checks and
  the real arm64 Metal contract. Readback checks all six visual kinds,
  top-down placement, alpha/color atlas sampling, and straight-alpha blending
  against exact expected bytes with a one-code-value GPU rounding tolerance.
  It also passes malformed length/order/reserved/page/layout/cap tests, stale
  renderer/atlas/page rejection, undersized-buffer non-publication, generation
  replacement, stale/double release, and zero live resources.
- `make terminal-renderer-dart-test` passes analyzer, build-hook Metal compile
  and embedding, native asset loading, ABI version 5, and zero-live-resource
  checks.
- The final adjacent `make test` passes scaffold/header checks, every native
  bridge/runtime/capability/PTY/renderer test, every Dart package analyzer and
  test, Developer JIT and Release AOT manifest assembly tests, launcher/example
  compilation, and both FFI smoke paths. `git diff --check` passes.
- Adjacent dependency commit: `3966419 Add bounded precompiled Metal renderer`.
- Ordered subtask 2 is complete. Native ABI 6 adds exactly three preallocated
  frame slots, monotonic submission tokens, immediate stale/backpressure
  results, newest-ready selection, and a bounded retirement snapshot. The
  synchronous submit path validates and copies only; drawable acquisition,
  command encoding, presentation, and slot retirement remain in the native
  view callback/GPU completion path. An idle callback returns before acquiring
  a drawable.
- A provider-owned custom-view operation binds one renderer generation to one
  validated terminal view without exposing an Objective-C object or AppKit
  registry handle to Dart. Main-thread and provider identity checks, malformed
  payloads, stale handles, rebinding after detach, main/worker release, and
  exact view delegate detachment are covered by native tests.
- The real Metal view test fills all three slots, observes immediate fourth
  submission backpressure, presents only the newest generation through an
  `NSWindow` drawable, waits for GPU completion, verifies two stale-ready
  drops and all token retirement, and proves atlas uploads remain blocked until
  no slot owns the texture. `make terminal-renderer-native-test` passes after
  the final idle-draw guard; the preceding full adjacent `make test` also
  passes with the same submission implementation. Source audit finds no debug
  logging or runtime shader compiler path, and `git diff --check` passes.
- Adjacent dependency commit: `6a7a23d Bind renderer views to triple-buffer
  submission`.
- Ordered subtask 3 adds a typed `TerminalMetalRenderer` lifecycle with strict
  bounded configuration, renderer-aware immutable little-endian frame encoding,
  copied atlas uploads, accepted/stale/backpressured outcomes, locked state
  snapshots, synchronous RGBA oracle readback, and opaque public view binding.
  Dart checks all fixed FFI layouts and validates native summaries/results
  before publishing them.
- The product-owned `TerminalGlyphAtlasMetalBridge` maps monotonic global atlas
  page IDs to stable format-local native slices, retains copied dirty uploads
  across backpressure, rejects unsynchronized frame construction, and connects
  accepted submission tokens to atlas pins and the native retirement watermark.
  Full page snapshot copies provide a bounded first-attachment/recovery path
  without consuming incremental dirty state.
- The 1x/2x product GPU test incrementally publishes alpha then color pages,
  proving that a newer complete atlas generation preserves unchanged slices.
  It renders all six visual kinds and compares every RGBA channel to the
  existing checked-in CPU reference goldens with a maximum one-code-value
  tolerance for Metal blend rounding. Focused atlas and GPU tests pass.
- The renderer package analyzer/Dart tests and complete adjacent `make test`
  pass. Product `make test` passes all 84 formatted files, analysis, native
  build hooks, GPU goldens, and the existing full suite. The focused public
  facade test compiles and passes as a Release AOT executable with the tested
  renderer dylib preloaded.
- `make runtime-source-check` passes with `tracked=162` and
  `native_sources=0`. Developer JIT and Release AOT arm64 bundle audits pass
  with renderer ABI 6. Their real custom-view smokes bind a renderer generation
  through the public Dart facade and exit cleanly in 2241 ms and 1822 ms.
- Adjacent dependency commit: `465ff2d Expose typed Metal renderer facade`.
