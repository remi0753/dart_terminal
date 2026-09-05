# Phase 4 — Metal failure recovery

- Status: in progress
- Date: 2026-09-06
- Scope: eighth Phase 4 roadmap item
- Related: ADR-002, ADR-004, REN-01, REN-03, REN-04, REN-05, REL-01

## Purpose

Recover the terminal presentation path from Metal device/pipeline creation
failure, asynchronous command failure, and transient drawable unavailability
without publishing partial renderer state, leaking atlas pins, or losing the
newest terminal model. A successful replacement must use a new native renderer
generation, republish the complete current atlas, and request one full redraw.

## Background

The native renderer currently creates its device, command queue, precompiled
shader library/pipeline, textures, and three slots atomically before returning a
handle. Runtime state reports submission and retirement counters, but it does
not distinguish why creation failed, record a missing drawable, or publish a
command/device fault. The draw callback releases a failed in-flight slot but
leaves Dart unable to decide whether to retry the drawable or replace the
renderer.

The product bridge owns copied pending atlas uploads and atlas pins keyed by a
renderer-local submission token. Replacing a renderer therefore cannot be a
raw handle swap: old pins must be retired or abandoned exactly once, a fresh
bridge must upload a full atlas snapshot, and the retained model/damage path
must request recovery redraw state.

## Scope

- Add a versioned, typed native Metal health/failure surface that separates
  device creation, shader/pipeline creation, drawable unavailability, command
  encoding, and command completion failures.
- Keep drawable unavailability transient: retain the newest READY frame, do
  not consume a new slot, and allow a later draw/resume request to present it.
- Make command/device faults stop admission, retire/drop owned slots safely,
  and remain observable until renderer release.
- Add deterministic one-shot native test injection for otherwise impractical
  device/shader/drawable/command fault paths without enabling it through the
  product facade.
- Add a bounded Dart recovery coordinator that recreates the renderer, binds
  it through the existing opaque view operation, republishes a full current
  atlas snapshot, releases old renderer-local pins, and schedules one full
  redraw/full damage recovery request.
- Exercise successful recovery and bounded repeated-failure behavior through
  focused tests and the real Developer JIT/Release AOT AppKit/Metal smoke.

## Out of scope

- General AppKit window/view recreation, display-link policy, cross-GPU
  migration, user-facing diagnostics UI, crash reporting, or process restart.
- Font/catalog rebuild, scale/resize changes, or changing the Dart-owned atlas
  generation solely because the native renderer changed.
- Frame timing, atlas hit-rate, uploaded-byte metrics; they remain the next
  roadmap item.
- Retrying a permanently invalid/corrupt application bundle indefinitely.

## Dependencies and ownership

- Native owns Metal device/pipeline/texture/slot lifetimes and is the only
  layer that can classify draw/command outcomes. Its state snapshot is copied
  under the existing lock and never contains `NSError` text or pointers.
- Drawable absence is not device loss. The READY frame and atlas pins remain
  live until it is presented, superseded, or the renderer is explicitly
  abandoned.
- A faulted renderer accepts no new atlas or frame work. Release detaches the
  view and lets Metal retain resources still needed by already committed work.
- Dart owns recovery attempt limits, renderer generation replacement, complete
  atlas republish, old bridge pin abandonment, and the one newest full-redraw
  marker. Terminal screen content remains owned by the engine.
- Counters, failure generations, and attempt counters are bounded signed or
  fixed-width values and never wrap.

## Ordered subtasks

1. **Typed native Metal failure state and drawable retry contract**
   - Version creation/state outputs with typed failure reasons and bounded
     drawable/command counters.
   - Keep a missing drawable retryable; make command/device faults terminal for
     that renderer generation; add deterministic native and Dart facade tests.
2. **Renderer recreation, atlas republish, and full-redraw coordination**
   - Abandon old renderer-local pins exactly once, open/bind a replacement,
     publish a complete atlas snapshot, and replace dependent submission
     ownership atomically.
   - Retain at most one recovery request with a bounded attempt budget, request
     full damage/redraw only after successful replacement, and cover repeated
     failure plus Developer JIT/Release AOT product integration.

The recreation child depends on the typed native health contract. The metrics
roadmap item must not begin until both recovery children are committed.

## Completion criteria

- Device and shader creation failures are distinguishable and publish no live
  renderer handle. A runtime command/device fault stops admission and is
  visible in a strict copied state snapshot.
- Drawable unavailability does not fault or drop the newest READY frame; a
  later explicit draw/resume presents it without creating an unbounded retry
  queue.
- Replacement uses a strictly newer renderer generation, old renderer-local
  pins are released once, and the new native atlas exactly matches the current
  Dart atlas before frames resume.
- Recovery requests one full damage/redraw of the newest model and never
  submits a frame from the retired renderer/resource domain.
- Repeated creation/synchronization failures retain bounded retry state and do
  not leak native renderer, slots, bridge uploads, or atlas pins.

## Verification plan

- Native ABI layout/symbol and deterministic fault-injection tests covering
  device, shader, drawable, encoder, and completion paths.
- Dart facade malformed-state/classification tests plus product recovery state,
  pin abandonment, complete atlas republish, full damage/redraw, and retry-cap
  tests.
- `dart format`, `dart analyze`, adjacent and product `make test`, focused
  Release AOT, `make runtime-source-check`, and Developer JIT/Release AOT
  bundle audits/integrations.
- Review product, adjacent `dart_appkit`, and official SDK worktrees before
  every completion commit.

## Investigation log

- 2026-09-06: after product commit `c5cdf12`, reread `ROADMAP.md`, `README.md`,
  `FEATURE_MATRIX.md`, Phase 4 renderer/rebuild/animation notes, native Metal
  ABI/implementation/tests, Dart facade, atlas bridge/pin ownership, resource
  rebuilder, and frame scheduler. Both repositories and the official SDK
  checkout were clean; this is the first unchecked Phase 4 item.
- 2026-09-06: native creation currently collapses missing device, command
  queue, embedded shader library/function/pipeline, texture, and slot buffer
  failures into status 6. Runtime state has no failure field. A command or
  encoder allocation failure frees only the selected slot; a non-completed
  command also frees it but leaves the renderer admitting, so Dart cannot
  distinguish retryable backpressure from a broken renderer generation.
- 2026-09-06: a missing `currentRenderPassDescriptor`/`currentDrawable` leaves
  READY work intact, which is the correct ownership baseline, but the event is
  neither counted nor explicitly retriggerable. An unbounded timer retry was
  rejected because it would spin while hidden/occluded. The selected contract
  retains one READY frame and relies on a later explicit draw/resume request.
- 2026-09-06: native submission tokens restart at one for each renderer while
  Dart atlas pins are keyed by token. Recreating a bridge without abandoning
  old pins would either leak pins or collide with new tokens. After old native
  renderer invalidation, those Dart CPU-atlas pins can be released: Metal owns
  independent textures/buffers for any already committed old command.
- 2026-09-06: the task crosses two independent failure domains and was split
  before implementation. Native classification/draw ownership is prerequisite
  to making a product-level recreate-versus-retry decision.
- 2026-09-06: the first focused native build found one remaining call to the
  strengthened pipeline initializer in the standalone custom view constructor.
  That view owns its initial unbound pipeline separately from any product
  renderer; it now supplies the same failure out-parameter and still aborts
  view construction atomically when setup fails.
- 2026-09-06: the first native fault run exposed two test/release boundary
  issues. Its post-fault probe accidentally changed the atlas generation
  instead of the frame generation and was correctly rejected as stale. More
  importantly, shutdown used `admitting == false` as an idempotence guard, so a
  faulted renderer skipped view detachment. Shutdown now owns a separate
  one-way guard and always detaches a first-time release, including after a
  fault; the corrected probe advances only the frame generation.
- 2026-09-06: the corrected native suite passed. The following Dart static
  pass then found that the package test's local debug FFI declaration lacked
  its direct `dart:ffi` import. The import was added only to the test; fault
  injection remains absent from the public product facade.
- 2026-09-06: committed the adjacent failure contract as `2a7035a` (`Expose
  typed Metal failure state`), reread the product roadmap, and confirmed the
  renderer recreation/atlas/full-redraw child remains next. The dependency
  worktree is clean.

## Verification results

### Typed native Metal failure state and drawable retry child

- Native ABI 8 uses creation-summary version 2 and 136-byte state version 2.
  C11/C++20 layout and symbol checks pass for the typed failure enum, creation
  failure field, runtime fault fields/counters, explicit draw request, and
  test-only one-shot injection entry point.
- The real native Metal capability test passes device and embedded shader
  creation failure without handle publication, transient drawable absence
  with all three READY slots retained, explicit retry and successful newest
  presentation, terminal command-encoding and command-completion faults,
  post-fault admission rejection, retirement, main/worker release, and zero
  live renderer/view counts.
- Renderer Dart analysis and tests pass, including exact device/shader
  exception classification, strict version-2 state decoding, zero healthy
  fault fields, and rejection of a presentation request while unbound.
- The complete adjacent `make test` passes all native bridge, runtime,
  capability, PTY, renderer, package, launcher, and example suites.
- Product `make test` passes with 96 formatted files and no analysis issues;
  `make runtime-source-check` passes with `tracked=178 native_sources=0`.
- ABI-8 Developer JIT and Release AOT bundle audits pass with one helper, one
  native-asset set, and one capability. Their real AppKit/Metal integrations
  pass in 2,274 ms and 1,764 ms respectively.
- Adjacent dependency commit: `2a7035a Expose typed Metal failure state`.

The first child is complete. Renderer recreation, atlas republish, and recovery
full-redraw ownership remain unimplemented and keep the parent in progress.
