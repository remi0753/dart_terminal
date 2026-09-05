# Phase 4 — Product damage capture performance gate

- Status: complete
- Date: 2026-09-06
- Scope: prerequisite discovered during the damage-transfer subtask
- Related: ADR-003, ADR-004, SCR-09, REN-04

## Superseded format note

The measurements below are the accepted version-1 wire evidence from this
completed prerequisite. The later cursor/BEL presentation task deliberately
introduced version 2 with a 104-byte header and a 1,704,904-byte full fixture;
its replacement measurements are recorded in
[`cursor-bell-occlusion.md`](cursor-bell-occlusion.md). The cell payload,
ownership boundary, and 4-millisecond gates remain unchanged.

## Purpose

Make the newly integrated product damage path satisfy the accepted Release AOT
performance contract before completing its transferable outbox. Preserve the
strict copied-ownership and canonical wire invariants while removing repeated
per-field logical-to-physical row lookup from full capture.

## Background

The first 100,000-cell Release AOT measurement used the real product
`TerminalDamageOutbox`, a direct isolate port, `TransferableTypedData`, and the
strict decoder. The 1,704,880-byte packet measured:

- end-to-end capture, transfer, decode, and ACK p95: 7,200 us;
- capture and transferable construction p95: 5,986 us;
- isolate transfer, strict decode, and ACK p95: 1,283 us.

The accepted ADR-003 full-pack gate is below 4 ms, while ADR-004's TTD gate is
also below 4 ms. Transfer already passes, but product capture does not. This is
a blocking prerequisite at the current roadmap position rather than a reason
to weaken the gate or continue to frame scheduling.

## Scope

- Add one bounds-checked `TerminalScreen` bulk-copy operation that copies a
  logical row span into caller-owned typed columns without exposing private
  authoritative arrays.
- Make the damage codec use aligned typed views and the bulk-copy operation,
  computing the physical source row once per span instead of once per field and
  cell.
- Add a reproducible 200 × 500 product Release AOT benchmark covering full
  capture plus the canonical direct-isolate TTD/strict-decode/ACK boundary.
- Require both capture p95 and transfer/decode/ACK p95 below 4 ms and retain the
  exact 1,704,880-byte packet contract.

## Out of scope

- Changing damage wire bytes, loosening validation, using shared mutable data,
  skipping the receiver copy/semantic checks, or introducing a raw pointer.
- Frame building, Metal submission, resize, or resource wire formats.
- General `TerminalScreen` mutation optimization outside the new bounded copy
  boundary.

## Dependencies and risks

- `TerminalScreen` remains the sole authoritative writer. The new method must
  validate every source/destination bound before copying any column.
- Destination arrays are caller-owned; each of the six columns must reproduce
  the existing scalar accessor result exactly, including ring-row mapping.
- Timing gates run only in Release AOT. Warmup and a fixed 64-sample workload
  reduce JIT/first-run noise, but p95 and max are both reported.

## Completion criteria

- Existing damage malformed/ownership/model tests remain unchanged and pass.
- Dedicated bulk-copy tests cover every column, subspans, ring rows, and atomic
  destination-bound rejection.
- The Release AOT benchmark reports the exact packet size and both p95 values
  below 4 ms on the M1/arm64 baseline.
- Full product tests and Dart-only source audit pass; no unrelated worktree is
  included in the completion commit.

## Investigation log

- 2026-09-06: an initial temporary benchmark source outside the package failed
  to resolve `package:dart_terminal`; the compile command was then retried with
  its supported `compile exe --packages=...` option position. A preceding
  attempt placed the global option before `compile`, which this Dart CLI
  rejected. Neither attempt changed product source.
- 2026-09-06: the corrected Release AOT benchmark established that transport
  plus strict decode is already well within its gate. Profiling by boundary
  points to capture's six public cell accessor calls per cell, each repeating
  logical-to-physical row mapping, as the avoidable cost. A bounded row-span
  copy retains ownership while enabling six typed-array range copies.
- 2026-09-06: the first whole-package validation after adding the dedicated
  copy test reported only a directive-ordering lint in `test/run_tests.dart`;
  the imports were sorted before repeating the gate. An earlier validation
  wrapper also mistakenly passed the Markdown task memo to `dart format`; its
  parser diagnostics did not run or change product source, and the corrected
  source-only command passed.

## Verification results

- `dart analyze` reports no issues for the screen bulk-copy API, optimized
  codec, dedicated test, unchanged codec/model test, and benchmark source.
- `test/terminal_damage_copy_test.dart` passes every-column, subspan,
  logical-ring-row, source-bound, destination-bound, and all-or-nothing
  validation cases. `test/terminal_damage_test.dart` remains unchanged and
  passes after the capture implementation switched to bulk range copies.
- `make product-damage-benchmark` compiles and runs Release AOT successfully:
  the packet remains exactly 1,704,880 bytes; capture plus TTD construction is
  650 us p95 / 1,034 us max; isolate transfer plus strict decode and ACK is
  1,832 us p95 / 2,155 us max; end-to-end is 2,441 us p95; transfer throughput
  is 1,174.40 MiB/s. Both required p95 values are below 4 ms.
- `make test` passes with 90 formatted files, no analysis issues, and
  `dart_terminal tests passed`.
- `make runtime-source-check` passes after staging with
  `tracked=168 native_sources=0`. The adjacent `dart_appkit` and bundled Dart
  SDK worktrees remain clean.
