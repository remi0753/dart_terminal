# DT-009 — Packed cell/grid and damage-transfer microbenchmark

- Status: accepted
- Date: 2026-09-01
- Scope: Phase 0 feasibility gate and evidence for ADR-003/ADR-004

## Question

Can a Dart-owned terminal grid avoid per-cell objects, generate bounded packed
damage quickly enough for rendering, and transfer full damage between isolates
without requiring shared mutable native state?

This prototype is original Dart code for this terminal project. Ghostty is only
a feature/parity reference; no Ghostty or `libghostty` implementation is used.

## Acceptance criteria

1. A 200 × 500 grid stores 100,000 cells in fixed typed arrays with no cell
   object allocation.
2. Row version, dirty interval, wrap/semantic flags, and logical-line identity
   are separate fixed metadata.
3. Scrolling rotates physical row ownership and clears only reused rows rather
   than moving the full grid.
4. Damage has a versioned, fully length/offset-checked wire envelope and sends
   only dirty row spans.
5. A 100,000-cell full packet packs at p95 below 4 ms; representative sparse
   damage packs at p95 below 1 ms.
6. A full packet moves through `TransferableTypedData` to a render isolate at
   p95 below 4 ms and at least 500 MiB/s.
7. SoA and per-cell-object sweeps produce the same logical checksum; neither
   comparison is discarded if it contradicts the proposed design.
8. Fresh-process retained-memory measurements distinguish grid storage from
   temporary benchmark packets.
9. Five consecutive release-AOT runs pass.

## Prototype formats

The mutable grid uses six Struct-of-Arrays fields per cell:

| Field | Dart storage | Bytes/cell | Meaning |
| --- | --- | ---: | --- |
| content | `Uint32List` | 4 | Unicode scalar or interned grapheme ID |
| foreground | `Uint32List` | 4 | default/palette/direct-RGB token |
| background | `Uint32List` | 4 | default/palette/direct-RGB token |
| style | `Uint16List` | 2 | interned style ID |
| hyperlink | `Uint16List` | 2 | interned link ID, zero for none |
| width/flags | `Uint8List` | 1 | continuation/narrow/wide and cell flags |

That is exactly 17 bytes per cell. Row metadata adds 13 bytes per physical row:
version, dirty start/end, row flags, and logical-line ID. The complete 100,000
cell prototype therefore owns **1,702,600 deterministic bytes**.

The damage message is columnar rather than a padded per-cell struct. Its
80-byte header contains magic/version/length, generation, resource generation,
dimensions, row/cell counts, all section offsets, total length, and flags.
Each 24-byte row record contains logical row, version, logical-line ID, packed
cell offset, start column, count, and row flags. Six aligned typed sections
then hold only the damaged cells. A full packet is **1,704,880 bytes**; the
representative 32 × 128-cell damage is **70,480 bytes**.

## Benchmark method

```sh
make phase0-grid-build
make phase0-grid-run
build/phase0/grid/grid_benchmark --memory-grid
build/phase0/grid/grid_benchmark --memory-objects
```

The benchmark is a native release-AOT executable compiled by Dart 3.13.2 for
macOS arm64. It uses 64 full-grid iterations, 256 sparse iterations, 2,048
single-row ring scrolls, and 64 ordered full-packet transfers to a second
isolate with acknowledgement and sampled checksum. The baseline machine is a
MacBookPro17,1 with an 8-core Apple M1 and 16 GB RAM, running macOS 26.6.2.

Artifact SHA-256:

`b8386a38e928c0250f505598b39313f664973a853fb708ba4c45aeb2a0f2d35e`

## Real-hardware result

All durations below are microseconds; throughput is MiB/s.

| Run | Full pack p95 | Sparse p95 | Scroll p95 | SoA sweep p95 | Object sweep p95 | Object pack p95 | TTD p95 | TTD MiB/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 243 | 30 | 1 | 828 | 301 | 659 | 168 | 13,897 |
| 1 | 272 | 30 | 1 | 460 | 249 | 642 | 184 | 12,762 |
| 2 | 251 | 29 | 1 | 421 | 246 | 655 | 178 | 13,574 |
| 3 | 240 | 29 | 1 | 408 | 246 | 630 | 167 | 13,608 |
| 4 | 248 | 29 | 1 | 406 | 249 | 672 | 164 | 13,969 |
| 5 | 237 | 29 | 1 | 405 | 252 | 622 | 170 | 13,685 |

The worst accepted full-pack p95 was **272 us**, sparse update-plus-pack p95
was **30 us**, and ordered `TransferableTypedData` p95 was **184 us**. Every
run transferred 64 × 1,704,880 bytes with matching sequence, generation,
length, and checksum. The transfer result is consistent with ownership-moving
typed data rather than a Dart object graph.

The object result is intentionally not hidden: in five of six runs a mutable
object sweep was faster than touching six separate typed arrays. That synthetic
operation favors nearby object fields. However, producing the actual wire
packet from objects took 622–672 us p95 versus 237–272 us from SoA because SoA
uses bulk typed-array copies. Fresh release-AOT processes measured:

| Retained structure | RSS increase | Deterministic/lower-bound payload |
| --- | ---: | ---: |
| SoA grid | 1,736,704 bytes | 1,702,600 bytes exact |
| 100,000 cell objects | 8,011,776 bytes | 5,600,000 bytes lower bound |

The SoA RSS increase closely tracks its explicit storage. Object RSS was about
4.6× the SoA increase and remains subject to object/GC layout changes.

An exploratory run before the final strict decoder had isolated maxima of
9,672 us for a full packet and 14,971 us for a sparse packet even though its
p95 values were 263 us and 28 us. Another exploratory run had a 1,771 us
object-sweep p95. These are consistent with allocation, GC, or OS scheduling
outliers. They occur on benchmark/engine isolates, not the AppKit thread, but
they are real: DT-011 must retain p50/p95/p99/max and memory fields, and the
product should reuse scratch structures where ownership allows.

## Transfer comparison

DT-006 copied a larger 3,200,032-byte Dart frame into a free native Metal slot
at 379–435 us p95 and held the slot until GPU completion. This benchmark moved
a 1,704,880-byte damage packet between Dart isolates at 164–184 us p95 without
shared mutable memory. The workloads are not identical, but both are far below
4 ms and show a clean two-boundary design:

```text
terminal-engine isolate
  -- TransferableTypedData ownership --> render-coordinator isolate
  -- synchronous bounded copy --------> native triple Metal buffers → GPU
```

A native double buffer between the two Dart isolates would require native
shared-state arbitration or an external-memory view and would not eliminate
the renderer-to-GPU copy. Its semantic cost is not justified by these numbers.

## Decision input

Accepted. The benchmark supports SoA as the mutable/transfer representation,
with the caveat that arbitrary full-field traversal is not automatically
faster than objects. The reason to choose it is bounded storage, no per-cell GC
identity, bulk damage packing, validation, and transferable ownership.

ADR-003 must freeze the exact logical and wire fields, limits, and invariants.
ADR-004 must choose `TransferableTypedData` for engine-to-render ownership and
native completion-fenced slots for render-to-GPU lifetime. Later profiling may
change field grouping to an array-of-small-SoA-blocks, but not reintroduce one
Dart object per cell or unversioned native sharing.
