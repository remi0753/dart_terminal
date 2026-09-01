# DT-005 — PTY kqueue batching and backpressure spike

- Status: accepted
- Date: 2026-08-31
- Scope: Phase 0 feasibility gate
- Related decisions: ADR-001 and ADR-002
- Uses process substrate: DT-004

## Question

Can fine-grained nonblocking PTY reads be coalesced into 64 KiB deliveries and
posted directly to the owning Dart worker isolate with bounded in-flight bytes,
ordered acknowledgement, and no AppKit/root-isolate stall?

## Acceptance criteria

1. A native kqueue reactor drains the nonblocking PTY master to `EAGAIN`.
2. A 10 MiB shell burst is delivered without loss, duplication, or reordering.
3. Full Dart-port deliveries are at least 64 KiB; only the EOF tail may be
   smaller.
4. Messages go directly to the terminal worker's native Dart port, not through
   the root UI isolate.
5. Every batch has a monotonic sequence and exact byte acknowledgement.
6. Native in-flight data is capped at 1 MiB and resumes only at or below the
   512 KiB low-water mark.
7. The high/low-water path is actually exercised by fault injection.
8. Failed post, wrong/duplicate acknowledgement, timeout, and stream-close
   paths are deterministic.
9. No measured root/AppKit message-pump turn reaches 4,000 us.
10. Five consecutive repeat runs pass on real hardware.

## Implementation

The PTY in DT-004 emits exactly 10 MiB of `x` bytes between unique markers.
Native reads are commonly around 1 KiB on this PTY, so the bridge accumulates
them in a bounded staging vector. It posts each complete 65,536-byte chunk as
a `Dart_CObject_kTypedData` payload:

```text
[event_kind=1, sequence, Uint8List payload]
```

The final partial chunk is flushed only after EOF/exit. The worker validates
sequence and size, scans every byte, tracks all interactive/burst markers, and
calls the coarse native acknowledgement ABI with `(sequence, byte_length)`.

The bridge tracks an ordered deque of outstanding batches and total in-flight
bytes. Before posting a batch that would exceed 1,048,576 bytes, the producer
waits off the AppKit thread until acknowledgements reduce occupancy to 524,288
bytes or less. A five-second deadline turns a stalled consumer into a recorded
failure. No queue is allowed to grow past the high-water mark.

The normal worker is faster than PTY production, so the first batch's ACK is
delayed by 250 ms in the worker as explicit fault injection. The delay is in
the terminal worker only. It lets native production reach exactly the 1 MiB
ceiling, enter the wait path once, consume ACKs down to the low-water mark, and
resume. This proves the branch rather than merely inspecting it.

After all batch ACKs, native posts one fixed summary containing byte/batch
counts, min/max batch, maximum in-flight bytes, wait count, PTY assertions,
read count, max post-call duration, and failure counters. Dart compares that
summary with independently accumulated worker values before reporting success
to root.

## Reproduction

```sh
make phase0-pty-build
make phase0-pty-run
```

The app is a signed ProductARM64 AOT bundle. `dart analyze`, the existing Dart
tests, child-path audit, and strict code-signature verification also pass.

## Real-hardware result

Every accepted run produced the same integrity result:

| Metric | Value |
| --- | ---: |
| zsh payload | 10,485,760 `x` bytes |
| total PTY bytes delivered | 10,487,013 bytes |
| deliveries | 161 |
| complete deliveries | 160 × 65,536 bytes |
| EOF tail | 1,253 bytes |
| minimum complete delivery | 65,536 bytes |
| maximum delivery | 65,536 bytes |
| maximum in flight | 1,048,576 bytes |
| backpressure waits | 1 |
| post failures | 0 |
| acknowledgement failures | 0 |
| shell exit | 37 |

The total includes setup/result markers in addition to the exact 10 MiB burst.
The Dart worker independently counted all 10,485,760 `x` bytes and found TTY,
resize, Ctrl-C, burst-start, and burst-end markers.

| Run | Native reads | Scenario (us) | Max native post (us) | Root heartbeat max gap (us) | Root max turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| Initial | 10,295 | 1,400,259 | 25 | 34,147 | 154 |
| 1 | 10,291 | 1,406,338 | 25 | 29,915 | 476 |
| 2 | 10,296 | 1,427,277 | 100 | 33,376 | 499 |
| 3 | 10,294 | 1,414,520 | 29 | 31,764 | 488 |
| 4 | 10,293 | 1,423,818 | 49 | 35,183 | 810 |
| 5 | 10,289 | 1,429,851 | 27 | 28,903 | 486 |

All six accepted runs passed. The worst synchronous native post call was
**100 us**. The worst measured root turn was **810 us**, 20.25% of the 4,000 us
hard ceiling and below the provisional 1 ms AppKit-handler target in this
scenario. The root never receives PTY payloads; its messages are heartbeat,
worker lifecycle, and final summary coordination.

The heartbeat maximum includes VM scheduling and the intentionally delayed
worker ACK and is not a single root handler duration. DT-011 will report its
distribution separately.

## Decision

Accepted. kqueue read aggregation into 64 KiB typed-data messages, direct
worker-port delivery, and byte-credit backpressure are viable. This removes
per-read/per-byte pressure from the Dart boundary while keeping queue memory
explicitly bounded.

The Product PTY reactor in Phase 2 must preserve this contract but add per-pane
fairness, generation IDs, configurable high/low water marks, read-interest
suspension, write-side backpressure, and external-typed-data/native-page
comparison. PTY ordering and terminal semantics remain owned by Dart; native
only transports bounded byte batches.
