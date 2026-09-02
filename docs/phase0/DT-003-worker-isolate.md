# DT-003 — worker isolate lifecycle and throughput spike

- Status: accepted historical evidence; embedded-worker reproduction target
  retired on 2026-09-03
- Date: 2026-08-31
- Scope: Phase 0 feasibility gate
- Related decision: `docs/adr/ADR-002-isolate-thread-ownership.md`

> This spike depended on the former modified-Engine topology. Its measurements
> remain evidence, but the build/run commands and modification instructions
> below are no longer present and must not be recreated. The product replacement
> is the official Dart child-process contract in the related ADR.

## Question

Can the Product AOT root isolate hosted on the AppKit main thread create,
communicate with, stop, and recover the failure of long-lived Dart worker
isolates without blocking AppKit for 4 ms or more?

This tests the concurrency substrate for a Dart-owned terminal engine. It does
not run Ghostty code or move terminal parsing into native code.

## Acceptance criteria

The spike passes only when all of the following are true:

1. The root isolate remains on the process main thread before, during, and
   after worker activity.
2. A worker created by root completes ready, ping, bulk transfer, stop, and
   `onExit` handshakes.
3. Every observed worker callback runs off the process main thread; no stable
   pthread identity is assumed.
4. At least 64 MiB crosses isolates as batches of at least 64 KiB with order,
   length, and marker validation.
5. Transfer throughput is above the roadmap's provisional 100 MiB/s parser
   target, so the transport does not become the first bottleneck.
6. An intentionally crashing worker reports both `onError` and `onExit`, and
   the root/application do not hang.
7. The root heartbeat remains live and no measured AppKit/root message-pump
   turn reaches 4,000 us.
8. Five consecutive repeat runs and the existing DT-002 regression pass on
   real hardware.

## Initial feasibility failure

The first real AOT run failed immediately:

```text
PHASE0_WORKER_FAIL Unsupported operation: Isolate.spawn
```

The Dart VM supported same-group workers, but the pinned lightweight
`dart_engine` host did not expose enough initialization state:

- root `DartIoSettings` omitted the snapshot URI, leaving `Platform.script`
  unset;
- `Dart_InitializeParams.initialize_isolate` was null, so a child in the
  existing group could not prepare its core libraries.

The resolution is the narrow source patch in
`patches/dart-engine-worker-isolates.patch`. The Make target verifies that the
patch matches the pinned Dart SDK revision, applies it idempotently, and builds
the Product AOT engine. It registers the documented same-group child callback
and supplies the root script URI. It deliberately leaves `create_group` null,
so `Isolate.spawnUri` remains out of scope.

This was treated as a real Phase 0 finding, not hidden by replacing isolates
with a helper process or a native terminal core.

## Implementation

- `tool/phase0/worker_isolate.dart` contains the AOT root test and two worker
  entry points.
- `native/macos/phase0/AotHost.mm` exposes thread/metric checks and retains the
  bounded AppKit root message pump from DT-002.
- `native/macos/phase0/Worker-Info.plist` defines a separate signed test app.
- `Makefile` provides the patch, Product AOT build, bundle, and run targets.

The long-lived worker receives 128 MiB as 512
`TransferableTypedData` messages of 256 KiB. Every message carries a sequence
marker; the worker materializes it once, validates both end markers, updates
cumulative byte/chunk counts, and acknowledges the sequence. Root validates
every acknowledgement before admitting the next message.

After a graceful stop and `onExit`, a second worker reports its non-main thread
identity and throws a known error. Root validates the error payload and exit
notification. A 1 ms root timer records its maximum scheduling gap while
native code measures the actual duration of each root message-pump turn.

## Reproduction

```sh
make phase0-aot-engine
make phase0-worker-build
make phase0-worker-run
```

The first command also verifies/applies the revision-specific embedder patch.
The worker target is safe to repeat; an already applied patch is detected with
`git apply --reverse --check`.

Additional validation:

```sh
dart analyze
dart run test/run_tests.dart
codesign --verify --deep --strict \
  build/phase0/worker/DartTerminalPhase0Worker.app
```

All passed. The signed bundle and its embedded engine satisfied their
designated requirements.

Artifact hashes for the accepted run:

```text
worker_isolate.aot
  0ecedcb801090c59cd7a236e03832ddfe3101a4c0aa1b1f57f0662cb723162ce
libdart_engine_aot_shared.dylib
  be9e6aed1505991cdac3fd9cf940de4f2ede7a8cf66f399786b8923e984bc8d1
```

## Real-hardware result

Environment is the DT-002 baseline: Apple arm64, macOS 26.6.2, Xcode 26.6,
Dart 3.13.2 stable, and the pinned ProductARM64 Dart Engine.

| Run | Transfer (MiB/s) | Ping (us) | Max heartbeat gap (us) | Root messages | Root turns | Max root turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 1,056.65 | 70 | 30,941 | 808 | 564 | 1,567 |
| 1 | 2,673.07 | 124 | 20,616 | 808 | 532 | 272 |
| 2 | 2,600.36 | 45 | 21,331 | 812 | 530 | 239 |
| 3 | 2,672.51 | 148 | 20,367 | 811 | 530 | 202 |
| 4 | 2,620.91 | 904 | 22,385 | 811 | 532 | 211 |
| 5 | 2,702.08 | 925 | 22,372 | 808 | 528 | 198 |

Every run transferred exactly 134,217,728 bytes in 512 ordered chunks and
observed normal worker exit plus expected worker error/exit. The minimum
throughput was **1,056.65 MiB/s**, 10.57 times the provisional 100 MiB/s gate.
The worst measured root turn was **1,567 us**, 39.18% of the 4,000 us hard
ceiling.

The heartbeat maximum includes cold isolate creation, VM scheduling, and OS
timer coalescing; it is not the duration of one root handler. Its 20–31 ms tail
must be characterized with p50/p95/p99 in DT-011. The direct occupancy metric
is the applicable Phase 0 hard gate and passed every run.

DT-002 was rebuilt against the worker-capable engine and rerun. The AOT root
and Timer remained on the main thread; its maximum turn was 204 us.

## Decision

Accepted. Same-group release AOT workers are viable with the pinned embedder
patch. Root/AppKit ownership, bulk transfer, graceful stop, and worker fault
observation all work without a 4 ms root turn.

ADR-002 fixes the product model: isolate ownership is single-writer, only root
is main-thread-bound, and VM worker pthread identity is not an API. The next
Phase 0 work moves to the native process boundary: safe `forkpty`/`execve`, job
control, resize/signals/exit, followed by 64 KiB-or-larger PTY delivery with
backpressure.
