# DT-011 — Benchmark baseline and regression output contract

- Status: accepted
- Date: 2026-09-01
- Scope: Phase 0 parser/render/input performance gate
- Related: ROADMAP sections 7, 8, and 9; DT-005, DT-006, DT-009, DT-010

## Question

Can the project establish a release-AOT benchmark contract before product
feature work begins, detect both absolute-budget failures and machine-relative
regressions, and keep correctness evidence separate from timing samples?

This harness measures original Dart Terminal probes. It does not link Ghostty
or `libghostty`, and its parser, packed grid, and key encoder are Phase 0
workload scaffolds rather than the eventual terminal implementation.

## Acceptance criteria

1. One release-AOT executable measures parser throughput, full and sparse
   damage packing, isolate transfer, and key-to-bounded-queue latency.
2. Every metric records unit, better direction, sample count, min, p50, p95,
   p99, max, a hard gate, an optional baseline gate, and final pass/fail.
3. Correctness hashes, counts, packet sizes, and queue bounds are emitted under
   `integrity`, never mixed into latency samples.
4. Stdout contains exactly one versioned JSON result; stderr contains one
   concise human status; a failed gate exits nonzero.
5. Baseline comparison rejects incompatible OS/ABI, Dart SDK, build mode,
   parser corpus, workload, packed-damage version, input-probe version,
   measurement policy, or Ghostty comparison-build provenance.
6. The physical baseline machine, exact corpus, measurement method, hard
   budgets, regression tolerances, and artifacts are source controlled.
7. Six consecutive runs pass, and an intentionally impossible temporary
   baseline is observed to fail before the accepted baseline is restored.

## Measurement contract

Run the checked comparison with:

```sh
make phase0-benchmark-build
make phase0-benchmark-run
```

`benchmark/phase0_benchmark.dart` writes
`dart-terminal-benchmark-result` version 1. It warms every workload and uses
Dart's monotonic `Stopwatch`. Timed work runs in release AOT. Percentiles use
nearest-rank selection so the recorded value is always an observed sample.

The workloads are:

- seven 32 MiB samples of a repeated mixed printable/UTF-8/CSI/OSC/DCS stream;
- 64 full 100,000-cell damage packs and 256 representative sparse packs;
- 64 ordered 1,704,880-byte `TransferableTypedData` deliveries with receiver
  acknowledgement and generation/checksum validation;
- 100,000 mode-aware key encodes followed by bounded byte-queue insertion.

The input setup also checks seven byte-exact key fixtures and a small queue
fixture that exercises wraparound, FIFO ordering, full capacity, and rejection.
These correctness operations are outside the timed sample.

The release result embeds the pinned Ghostty reference commit
`d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. Its own `build.zig.zon` requires
Zig 0.16.0; the frozen comparison command is
`zig build -Doptimize=ReleaseFast`, producing the macOS `ReleaseLocal` app with
no project-local patch. These values follow Ghostty's commit-matched build and
packaging files plus its official macOS build documentation. The comparator
was not built or linked in Phase 0, and no Ghostty timing is claimed. Relative
performance requires comparable end-to-end product builds and remains a later
release gate.

## Frozen baseline

Baseline ID `phase0-macos-arm64-m1` identifies a MacBookPro17,1 with an
8-core Apple M1 and 16 GB RAM, macOS 26.6.2 build 25G83, and Dart 3.13.2. The
executable ABI is `macos_arm64` and build mode is `release-aot`.

The Ghostty comparator metadata is the commit, Zig 0.16.0, ReleaseFast command,
and ReleaseLocal configuration above. The reviewed parser corpus is format version 1 with SHA-256
`37414501d31cede8a3e39f70fceaae5ae2500e0be40ce5b10178e6e4ce2fb8be`.
The benchmark workload is `phase0-mixed-v1`; packed damage, input probe, and
measurement policy are all version 1.

| Metric | Compared stat | Reference | Regression threshold | Absolute hard gate |
| --- | ---: | ---: | ---: | ---: |
| parser mixed throughput | p50 | 174 MiB/s | >= 147.9 MiB/s | min >= 100 MiB/s |
| full damage pack | p95 | 260 us | <= 438 us | p95 < 4,000 us |
| sparse damage pack | p95 | 28 us | <= 67 us | p95 < 1,000 us |
| isolate damage transfer | p95 | 210 us | <= 515 us | p95 < 4,000 us |
| key to bounded queue | p95 | 42 ns | <= 334 ns | p95 < 2,000,000 ns |

The regression threshold is computed from the reviewed reference, relative
tolerance, and absolute scheduling/clock slack. The much wider hard gate is an
architecture feasibility budget. Updating either requires reviewed evidence;
a failing baseline must never be moved merely to make a run green.

## Real-hardware result

Parser values are p50 MiB/s; all render values are p95 microseconds; input is
p95 nanoseconds.

| Run | Parser | Full pack | Sparse pack | Transfer | Input | Suite (ms) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 174.59 | 254 | 27 | 201 | 42 | 1,352 |
| 1 | 173.36 | 252 | 26 | 205 | 42 | 1,355 |
| 2 | 174.76 | 251 | 27 | 214 | 42 | 1,328 |
| 3 | 174.90 | 253 | 27 | 203 | 42 | 1,326 |
| 4 | 174.35 | 248 | 28 | 200 | 42 | 1,329 |
| 5 | 174.35 | 252 | 27 | 205 | 42 | 1,330 |

All runs passed every hard and baseline gate with stable parser action hash
1,649,929,183, damage checksum 40,739,393, transfer checksum 2,687,552, and
input checksum 7,551,689. The slowest individual parser sample was 156.58
MiB/s, still 56.6% above the architecture gate. Input p95 remained 42 ns even
when isolated maxima reflected scheduler interruption, which is why the result
retains p99/max without turning a single interrupt into a regression verdict.

A final provenance-only rebuild added the frozen Ghostty Zig/build fields
without changing any timed workload or threshold. It also passed: parser p50
174.17 MiB/s, full/sparse/transfer p95 249/27/198 us, and input p95 42 ns.

To test the negative path, the checked parser reference was temporarily changed
from 174 to 1,000 MiB/s with zero additional slack. The executable returned
exit code 1, emitted `status: fail`, calculated an 850 MiB/s threshold, marked
only `parser.mixed.throughput` failed, and retained valid JSON. The accepted
174 MiB/s reference was then restored and rechecked successfully.

Artifact SHA-256 values:

| Artifact | SHA-256 |
| --- | --- |
| release-AOT benchmark | `488cd7ed2b55fd33eb29ce4d2e4fae49a9f882902a0483a15e757dc49cd51e42` |
| benchmark source | `546d939055b6b9fb1e8ca816779964ae93dd42727a33a07a455e95480d3e56be` |
| accepted baseline | `11f9b3dfc1ea5dab3677b87a9a816ca392da39584db22afae9667123a2793a2d` |
| input probe source | `b32ce3b382bcde61933053069267dd4f09e0bd07a52d6fb70c7c4cd9859cd80f` |

## Decision

Accepted. Phase 0 has a machine-readable parser/render/input regression format
and a real-hardware release-AOT baseline. CI may archive the JSON and fail on
its process status without scraping prose.

The numbers authorize the selected Dart ownership boundaries, not completion
of terminal semantics or end-to-end key-to-photon performance. Product phases
must replace probes with real parser/grid/input paths while preserving metric
IDs or explicitly versioning them. Frame presentation, glyph atlas behavior,
PTY echo, memory/power, 120 Hz, and Ghostty-relative parity remain separate
future measurements.
