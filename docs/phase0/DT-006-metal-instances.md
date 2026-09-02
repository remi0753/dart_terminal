# DT-006 — 100,000-instance Metal rendering spike

- Status: accepted historical evidence; embedded-worker build/run target
  retired on 2026-09-03
- Date: 2026-09-01
- Scope: Phase 0 feasibility gate
- Related decisions: ADR-001, ADR-002, and input evidence for ADR-004

> The rendering measurements remain feasibility evidence. The build/run
> commands below used the retired in-process worker host and are not current
> instructions; any new renderer validation must use the selected official
> process-worker topology.

## Question

Can a release-AOT Dart worker prepare a coarse packed frame containing 100,000
glyph-like instances, submit it to native Metal without involving the AppKit
root isolate in per-instance work, and sustain continuous `MTKView` drawing
without violating the 4 ms main-run-loop ceiling or reusing GPU-owned memory?

This spike validates an implementation boundary for a Dart terminal emulator.
It does not embed, link, or reproduce Ghostty renderer code.

## Acceptance criteria

1. A release-AOT app continuously draws exactly 100,000 instances in an
   `MTKView` for at least 120 completed frames.
2. Dart creates one versioned, bounds-checkable packed submission rather than
   issuing per-glyph FFI calls.
3. Frame preparation and native submission run on a worker isolate, not the
   AppKit/root-isolate thread.
4. Native owns three Metal buffers, rejects submission when all are occupied,
   and never reuses an in-flight buffer before command completion.
5. The renderer selects the newest ready generation and can discard stale
   generations.
6. Copy p95 is below 4 ms; CPU encode and GPU p95 are each below the 60 Hz
   frame budget used by this spike (11,667 us).
7. No Metal draw callback runs off the main thread and no measured Dart
   message-pump turn reaches 4,000 us.
8. Five consecutive repeat runs pass on real hardware.

## Implementation

The Dart render-coordinator isolate constructs one 3,200,032-byte typed array:
a 32-byte versioned header followed by 100,000 fixed 32-byte instances. Each
instance contains four geometry floats and four packed 32-bit fields. The
worker lends the typed-data address to one leaf FFI call; native validates the
complete header and length synchronously, then copies the payload into an
available shared `MTLBuffer`. Native does not retain the Dart pointer.

The renderer has three explicit slot states: free, ready, and in flight. A
submission is rejected with backpressure when no slot is free. At each
`MTKView` draw, the newest ready generation is selected and older ready
generations are dropped. The selected slot becomes reusable only in the Metal
command buffer completion handler. Each frame uses one instanced draw call of
six vertices by 100,000 instances.

The procedural shader is intentionally only a workload surrogate. CoreText
shaping and glyph-atlas construction are separate concerns; this spike tests
the renderer submission boundary and lifetime rules, not visual text fidelity.

## Reproduction

```sh
make phase0-metal-build
make phase0-metal-run
```

The generated app is ad-hoc signed, and strict deep signature verification
passes. Tested hardware is an 8-core Apple M1 GPU with Metal support.

Artifact SHA-256 values for the accepted build:

| Artifact | SHA-256 |
| --- | --- |
| native host | `cf1b857aa6db5558e9e28f2d8e79a7fc702d696e711d137a93fe60e021ee1adb` |
| Dart AOT snapshot | `2cd2c56d67959ceb127a6d84f2b008c42bd0f92ce92defd9b26e692d19efa26c` |
| patched ProductARM64 engine | `be9e6aed1505991cdac3fd9cf940de4f2ede7a8cf66f399786b8923e984bc8d1` |

## Real-hardware result

| Run | Frames | Accepted | Backpressure | Stale | Copy p95 (us) | Encode p95 (us) | GPU p95 (us) | Root max turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 120 | 351 | 17 | 231 | 392 | 178 | 1,575 | 703 |
| 1 | 121 | 350 | 19 | 229 | 408 | 171 | 1,749 | 306 |
| 2 | 120 | 351 | 14 | 231 | 416 | 177 | 1,565 | 455 |
| 3 | 121 | 354 | 17 | 233 | 379 | 179 | 1,571 | 384 |
| 4 | 120 | 349 | 17 | 229 | 408 | 175 | 1,685 | 395 |
| 5 | 120 | 355 | 13 | 235 | 393 | 178 | 1,599 | 452 |

All six accepted runs had zero main-thread violations. Worst p95 copy was
**416 us**, worst p95 CPU encoding was **179 us**, and worst p95 GPU duration
was **1,749 us**. The worst measured Dart root turn was **703 us**, 17.6% of
the hard 4,000 us ceiling. Stale drops are expected: the worker intentionally
publishes at roughly 250 Hz while the view consumes at 60 Hz, proving the
latest-generation policy. Backpressure was also exercised in every run.

Frame construction took 826–1,126 us after warm-up. A cold first run spent
about 84 ms creating the renderer because this spike compiles Metal source at
runtime; subsequent process runs observed 4.4–6.5 ms with driver caches. The
product path must ship a precompiled `.metallib` and create pipelines outside
an input or draw handler. Runtime shader compilation is not accepted as a
main-loop operation.

An earlier otherwise-passing run measured a 3,871 us root turn while releasing
the renderer synchronously during the final Dart call. Renderer teardown was
moved to the host's native-finalization point after the AppKit run loop stops.
The accepted runs above verify the corrected ownership boundary; teardown is
not charged to an interactive Dart turn.

## Decision

Accepted. A Dart-owned packed render model with coarse native submission is
feasible for this hardware and workload. Native must own the Metal objects and
GPU-visible buffer pool; Dart owns logical frame construction and generation.
Submission is a synchronous copy into a free native slot, while slot release is
asynchronous and tied to GPU completion. These measured rules are the basis
for ADR-004.

Phase 3 must replace the surrogate shader with atlas-backed glyph rendering,
precompile shaders, make the in-flight limit configurable per window, measure
120 Hz separately, and add device-loss/resize/occlusion behavior. None of those
changes require adopting Ghostty or `libghostty`.
