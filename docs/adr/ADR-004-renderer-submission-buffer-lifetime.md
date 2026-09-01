# ADR-004: Renderer submission and buffer lifetime

- Status: Accepted for Phase 0
- Date: 2026-09-01
- Decision owners: Dart Terminal project
- Related: ROADMAP sections 4, 6, 7, 9, and 10; ADR-001–003; DT-003; DT-006; DT-009

## Context

Rendering crosses two ownership boundaries:

1. a terminal-engine isolate sends packed logical damage to its window's Dart
   render-coordinator isolate;
2. the render coordinator submits a packed draw list to native Metal buffers
   whose lifetime extends until GPU command completion.

Dart isolates cannot share mutable objects. A Dart typed-data address is only
borrowed during a synchronous native call. Metal may retain a submitted buffer
for multiple display intervals, and `MTKView`/drawable/command completion have
native thread and lifetime requirements. Conflating either boundary would
create a raw-pointer race, an unbounded frame queue, or GPU reuse before
completion.

Damage deltas also cannot simply be dropped. If generation N changed row 4 and
generation N+1 changed only row 8, discarding N before applying it loses row 4.
What may be dropped is redundant frame construction/presentation after logical
damage has been applied, or a stale message already superseded by an explicit
full snapshot.

Phase 0 measured both paths on an Apple M1:

- DT-009 moved a 1,704,880-byte packed grid packet between Dart isolates with
  `TransferableTypedData` at 164–184 us p95 and 12.8–14.0 GiB/s;
- DT-006 synchronously copied a 3,200,032-byte 100,000-instance frame into a
  free native Metal slot at 379–435 us p95, encoded at 171–231 us p95, and
  completed GPU work at 1,565–1,749 us p95;
- DT-006 exercised native backpressure, stale ready-frame removal, 120+
  completed 60 Hz frames, and zero buffer reuse before completion;
- all measured root/AppKit Dart turns remained below 1 ms in the accepted
  renderer runs.

This renderer architecture is original to Dart Terminal. Ghostty is a parity
reference only; no Ghostty or `libghostty` renderer is linked or copied.

## Decision

Use `TransferableTypedData` with acknowledgement for the
terminal-engine-to-render-coordinator boundary. Use a synchronous validated
copy from the render coordinator into three native-owned Metal submission
slots for the Dart-to-GPU boundary. Native releases a slot only after the
associated command buffer completes or follows an explicit failure/device-loss
cleanup path.

```text
terminal-engine isolate (authoritative pane grid)
  │ one ordered TTD damage in flight; later dirty state remains coalesced
  ▼
render-coordinator isolate (applied window render model, newest frame policy)
  │ borrowed packed-frame pointer for one bounded FFI call
  ▼
native renderer: FREE → READY → IN_FLIGHT → command completion → FREE
                                         └→ failure/device-loss cleanup
```

There is no shared raw pointer between Dart isolates and no Dart-owned memory
referenced by an asynchronous Metal command.

## Engine-to-render damage protocol

Each pane has a direct engine-to-render port capability. Bulk damage never
passes through the root/UI isolate. Messages use ADR-003's packed format and
carry pane handle/generation, strictly increasing damage generation, required
resource generation, byte length, and full-snapshot flag.

### Admission and acknowledgement

- At most one transferred damage packet per pane is awaiting renderer ACK.
- The engine materializes and transfers that packet, losing access to its
  backing data as required by `TransferableTypedData` ownership.
- Parser/grid mutations that arrive before ACK mark a separate pending dirty
  union in the authoritative grid. They do not append packet Futures or retain
  an unbounded list.
- The renderer ACKs after validating and applying the logical damage/resource
  references to its retained render model, not after GPU presentation.
- After ACK, the engine may package the accumulated pending dirty state as the
  next generation. If none exists, it sends nothing.
- ACK contains pane generation, damage generation, accepted byte count, and
  status. Duplicate, wrong-byte, future, and stale ACKs are deterministic
  errors; an old pane generation is ignored after releasing sender bookkeeping.
- A deadline or closed port ends the render relationship and forces a later
  full resync. It never blocks parsing or AppKit.

This one-in-flight rule makes the previous applied generation implicit and
bounds both queue size and delta ordering. More than one in flight may only be
introduced by a later ADR that adds an explicit base-generation field and
proves a benefit.

### Coalescing and dropping

The render coordinator applies ordered deltas even when it chooses not to
build a Metal frame for each one. It may coalesce many applied generations into
one newest draw list. It may reject/drop:

- duplicate or older-than-applied damage;
- damage for a stale pane/window generation;
- a queued delta explicitly superseded by a validated newer full snapshot;
- a prepared but not native-accepted draw frame when newer model state exists.

It must not drop an unapplied incremental delta solely because a numerically
newer incremental delta arrived. Resource definitions are applied before any
damage that references their resource generation.

For multiple panes, the coordinator applies bounded per-pane work and yields;
one flooding pane cannot monopolize the window's coordinator.

## Render-coordinator-to-native submission

The coordinator creates one versioned packed draw list per chosen window frame.
It contains a generation, exact byte length/stride/count, resource/atlas
generation, viewport/scale metadata, and fixed-layout instances. One frame may
use a small constant number of calls for resource uploads plus one instance
submission; per-glyph or per-cell FFI is prohibited.

The initial submission ABI borrows `(pointer, byteLength)` only until the call
returns. Native performs, in order:

1. verify renderer handle/generation and caller domain;
2. copy and validate the fixed header without unaligned dereference;
3. check magic/version/header/total/stride/count/reserved fields and configured
   capacity with overflow-safe arithmetic;
4. reject stale generation or return `BACKPRESSURE` if no slot is free;
5. copy payload into one free native buffer;
6. publish that slot as ready and return `ACCEPTED` with its 64-bit submission
   token/generation.

The call does not wait for a drawable, display link, command queue, GPU fence,
or Dart callback. On any rejection it retains neither the pointer nor a partial
submission. Dart may release/reuse its packed frame immediately after return.

Submission token zero is invalid. A token is unique within a renderer-handle
generation and identifies metrics/completion; it does not grant Dart access to
native memory. The Phase 0 spike used the monotonic frame generation as this
slot identity internally. The product ABI returns it explicitly alongside the
status.

## Native slot state machine

Three slots are the Phase 0 default:

```text
FREE
  └─ validated synchronous copy ─→ READY(generation, token)
READY
  ├─ newer READY selected; older READY ─→ FREE (stale, never encoded)
  └─ selected by draw callback ─────────→ IN_FLIGHT(command buffer)
IN_FLIGHT
  ├─ command completed ─────────────────→ FREE
  └─ encode/commit/device failure ──────→ failure cleanup → FREE/renderer lost
```

The newest ready generation is selected for a draw. Older ready slots may be
freed because their bytes were never given to Metal. An in-flight slot is never
stale-freed or overwritten. The command-buffer completion handler captures the
slot identity, verifies its token/renderer generation, records GPU status and
duration, then returns it to free state exactly once.

Native state transitions are protected by the renderer's narrow lock. No lock
is held while calling Dart, posting an event, acquiring a drawable, or waiting
for GPU work. A slot's `MTLBuffer` and every atlas/image resource referenced by
its command buffer remain strongly owned for command lifetime.

When all slots are ready or in flight, native returns backpressure immediately.
The render coordinator retains its newest logical model, not a queue of packed
frames. On a later slot-available/display signal it rebuilds or submits only the
newest generation. Backpressure therefore has a fixed native memory cost.

## Drawable, refresh, and thread rules

- `MTKView` lifecycle and its delegate remain native/AppKit responsibilities.
- No Dart isolate waits for `currentDrawable` or a display callback.
- A nil render-pass descriptor/drawable skips presentation without consuming a
  ready frame unless native can safely retry it.
- Occlusion/minimization stops GPU submission while engine state and bounded
  renderer-model application continue.
- Resize, backing-scale, color-space, font/atlas reset, and device recovery
  increment generations and request a full snapshot as appropriate.
- Display refresh controls presentation cadence; it does not cause Dart to
  manufacture identical frames when no damage/animation exists.

The M1 spike used shared-storage Metal buffers. Universal/x86_64 and discrete
GPU paths may require managed/private staging and explicit synchronization, but
must preserve this ownership state machine and be benchmarked in Phase 1/3.

## Shader and resource lifetime

Metal source compilation is not an input/draw-loop operation. DT-006 observed
about 84 ms on a cold runtime shader compilation versus 4–7 ms with caches.
Product bundles ship a precompiled `.metallib`; device, library, pipelines, and
fixed buffer pools are created during bounded renderer setup outside event
handlers.

CoreText shaping/raster requests are coarse run/glyph-set batches. Atlas
entries have resource IDs, generations, refcounts, and last-use submission
tokens. Eviction is legal only when no ready/in-flight submission can reference
the entry. Repacking/resetting an atlas increments resource generation and
requires definitions/full damage before new frames.

## Shutdown and failure

Renderer shutdown proceeds as follows:

1. stop admitting Dart submissions and invalidate the renderer generation;
2. detach/pause the `MTKView` delegate on the AppKit main thread;
3. cancel/free ready but unencoded slots;
4. wait asynchronously up to a bounded deadline for committed command buffers,
   or use the documented device-loss abandonment path where Metal retains its
   command resources;
5. resolve each token once, release atlas/buffer/pipeline/view objects on their
   required native domains, and ignore late callbacks by generation;
6. report completion to lifecycle orchestration without blocking AppKit.

DT-006 found that synchronously releasing the renderer inside the final Dart
turn raised root occupancy to 3,871 us. Moving release to native finalization
after the AppKit run loop stopped reduced accepted root turns to 306–741 us.
Product teardown therefore cannot be hidden inside a normal input/frame FFI
call.

An encode failure releases a selected slot only if no command owns it. A commit
or GPU error completes through the command callback and is recorded against the
token. Device loss invalidates every renderer/resource generation and retains
the last safely committed presentation or a diagnostic fallback until resync.

## Limits and performance gates

Initial limits are three native slots per active window, one unacknowledged TTD
damage packet per pane, one coalesced pending dirty state per pane, and one
prepared/accepted newest frame policy per window. Byte capacities are fixed at
renderer creation and checked on every call.

Phase gates on the baseline machine:

- engine-to-render damage TTD p95 below 4 ms for the 1.7 MB/100,000-cell case;
- native submission-copy p95 below 1 ms for the 3.2 MB/100,000-instance case;
- CPU encode and GPU p95 each below 70% of the active refresh interval in the
  product workload;
- AppKit handler p95 below 1 ms and no intentional turn at or above 4 ms;
- queue/slot byte counts never exceed configured limits.

The 60 Hz M1 spike passes. Phase 3 must measure real atlas glyphs, 120 Hz,
Retina scale, multiple displays, resize/occlusion, and device failure.

## When a native lease may replace the copy

The current copy is accepted. A writable native-slot lease is not authorized
merely because a copy exists. It may be proposed only if release-AOT profiling
after dirty-only packing, allocation reduction, and resource caching shows the
copy materially violates the active frame budget on a supported baseline.

Any lease design requires fixed capacity, renderer and owner generation, slot
token, one writer, exact committed length, cancel, timeout, guard validation,
and completion/fence semantics. The lease is acquired and consumed by the
render coordinator only; its raw pointer is never sent between isolates or
retained after cancel/commit. VT/grid meaning remains Dart-owned.

## Alternatives rejected

### Native double buffer between Dart isolates

Rejected as the default. TTD already moves full damage in 164–184 us p95 while
preserving isolate ownership. Native sharing would introduce acquire/release
races and still leave the required native Metal lifetime boundary.

### Retain a Dart typed-data pointer until GPU completion

Rejected because borrowed Dart memory is not pinned for asynchronous native
use and its lifetime cannot be tied safely to Metal callbacks.

### Allocate one native buffer for every frame

Rejected because allocation and queued command memory become unbounded under a
slow GPU or occluded window.

### Block until a Metal slot or drawable is available

Rejected because it can stall the render worker and, if called from the wrong
domain, AppKit. Backpressure is an immediate status plus asynchronous progress.

### Drop every older damage message

Rejected because incremental deltas are not necessarily supersets. Apply
ordered logical damage, then drop redundant frame work.

## Consequences

- Both cross-domain lifetimes have one explicit owner and bounded memory.
- The design incurs one accepted native copy but avoids pinned/shared Dart
  memory and is well within Phase 0 budgets.
- Renderer state must retain an applied logical model so it can coalesce frame
  construction safely.
- ACK, resource generation, token completion, backpressure, and shutdown add
  protocol complexity that must be covered by fault injection.
- Phase 1/3 must expose these status/event contracts in the terminal-specific
  macOS package, precompile shaders, and add completion/device-loss tests before
  product rendering begins.
