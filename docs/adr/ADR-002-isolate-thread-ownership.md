# ADR-002: isolate, process, thread, and ownership model

- Status: Accepted; revised for the Phase 1 stock-Dart migration
- Date: 2026-09-03
- Decision owners: Dart Terminal project
- Supersedes: the 2026-08-31 same-group worker portion of this ADR
- Related: `ROADMAP.md` sections 4, 6, 7, and 9; ADR-001;
  `docs/phase1/stock-dart-runtime-migration-plan.md`

## Context

Dart Terminal is an independent terminal emulator implemented in Dart. It does
not embed Ghostty or use Ghostty as its terminal core. AppKit must own the
macOS process main thread while terminal parsing, grid mutation, damage
generation, shaping preparation, and large byte transfers continue outside the
UI domain.

The Phase 0 implementation used ordinary `Isolate.spawn` workers inside the
AppKit process, enabled by two downstream Dart Engine patches. The first
installed child core-library initialization; the second added VM-wide cleanup
to Engine shutdown. Although the resulting behavior passed the Phase 0 and
Phase 1 lifecycle tests, modifying Dart or Dart Engine is no longer an allowed
product input.

Every unmodified same-process alternative was tested before revising this ADR:

- multiple stock `DartEngine_CreateIsolate` roots can run and communicate, but
  the public Engine API cannot retire or unregister one root, so pane-owned
  roots accumulate until global shutdown;
- a public lightweight child under stock `dart_engine` lacks the initializer
  required for microtasks and correct error behavior;
- a complete VM host built only with public `dart_api.h` interfaces can create
  and clean up an ARM64 JIT/AOT root, but cannot initialize
  `Platform.script`, microtasks, or normal worker lifecycle without unexported
  Dart `runtime/bin` bootstrap;
- the official Dart JIT and AOT runners execute Dart away from the process main
  thread and do not service its main dispatch queue, so they cannot replace the
  AppKit GUI host;
- official Dart JIT and self-contained AOT child processes passed ready,
  request/reply, bulk transfer, graceful exit, uncaught failure, forced
  termination, replacement, and final-reaping tests on M1/arm64.

The immutable execution contract and exact evidence are in
`docs/phase1/stock-dart-runtime-migration-plan.md` and
`docs/phase1/unmodified-dart-engine-hosting.md`.

## Decision

Retain **single-writer ownership** for mutable Dart state, but place every
independently recoverable non-UI worker domain in an official Dart child
process. The AppKit process contains exactly one stock-Engine Dart root for its
lifetime. Terminal panes are the first process-owned domains; a future render
coordinator follows the same boundary if it remains a separate worker.

```text
macOS UI process
└─ AppKit process main thread
   ├─ one stock Dart Engine root isolate
   │  ├─ application/window/tab/split model
   │  ├─ focus, input, and lightweight coordination
   │  └─ asynchronous worker-process supervision
   ├─ bounded AppKit/Dart message pump
   └─ native AppKit, PTY, CoreText, and Metal domains

official Dart worker processes
├─ pane process, generation A
│  └─ terminal parser/grid/scrollback/damage single writer
├─ pane process, generation B
│  └─ terminal parser/grid/scrollback/damage single writer
└─ future independently recoverable worker domain, if required
```

Developer workers use the exact configured official Dart SDK executable.
Release workers use one reusable, self-contained arm64 executable produced by
that SDK with `dart compile exe`; each worker launch is a separate process of
that executable. No worker links a private Dart library or a modified Engine.

### Domain responsibilities

| Domain | Owns | Does not own |
| --- | --- | --- |
| UI root on AppKit main | window/tab/split model, focus/input routing, worker PID/stream handles, owner generations, user-visible lifecycle | terminal grid/parser loop, blocking IPC, PTY wait, font shaping, GPU waits |
| terminal worker process per pane | UTF-8/VT parser, modes, grid, scrollback, replies, selection/search, damage generation for exactly one pane generation | AppKit objects, another pane's state, native UI/GPU objects, parent lifecycle policy |
| future render worker process, if retained | damage coalescing, latest-generation policy, packed-frame preparation | authoritative grid, AppKit, Metal object lifetime |
| native PTY reactor | master FD, child/process group, readiness, bounded read/write queues, resize/signal/wait | VT semantics or Dart state |
| native render/font domain | CoreText and Metal objects, buffers, fences, command encoding/presentation | terminal semantics or frame-generation policy |

A logical Dart owner and an operating-system thread are not interchangeable.
Only the UI root has a thread-affinity contract. A child process may schedule
its Dart root on any thread chosen by the official runtime because it never
calls AppKit.

## Stock UI-host contract

The UI process uses the exact published Dart 3.13.2 revision
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. Its checkout must be clean before
and after every accepted build. No patch, local SDK commit, fork, private Dart
header/symbol, or copied runtime helper is permitted.

The AppKit Runner creates one root through stock `dart_engine`. The root uses
the custom AppKit-backed scheduler and is serviced on the process main thread
with a hard per-turn limit of 64 messages or 4,000 microseconds. It does not
create application workers with `Isolate.spawn`, create additional Engine
roots, or reinitialize Dart after shutdown.

Final UI shutdown is process-lifetime:

1. stop admitting new UI, PTY, and worker requests;
2. stop and reap every worker process;
3. release product native resources, disable event posting, and stop the
   AppKit/Dart message pump;
4. call stock `DartEngine_Shutdown` for the one root;
5. return immediately from the application executable so OS process exit is
   the final VM-resource boundary.

The product does not claim that stock `DartEngine_Shutdown` performs
`Dart_Cleanup`, and it must not continue or restart the VM after that call.

## Worker transport and ownership

Dart Terminal owns child-process creation, its PID, stdin/stdout/stderr, binary
framing, buffering, deadlines, signals, exit status, and stream closure. A
worker's stdout is protocol-only, stdin is command/data-only, and stderr is
diagnostic-only. Shell command strings are not used to launch workers.

The final versioned envelope must carry, directly or in a typed payload:

```text
wire magic and version
message kind
owner ID and generation
sequence or operation ID
payload length and payload
```

Frames have a fixed maximum payload. Larger transfers are chunked, ordered,
bounded by byte and message watermarks, and acknowledged in windows. Unknown
versions/types, oversized payloads, invalid lengths, duplicate identifiers,
and stale generations fail the affected worker connection without being
interpreted as terminal data. Logs may never be written to protocol stdout.

The transport layout may be refined during implementation, but changing these
semantic fields, stream roles, or boundedness requires a new ADR decision.

## Worker lifecycle

Each worker generation follows this state model:

```text
creating → ready → running → draining → stopped
   │          │        └──────────────→ crashed
   │          └───────────────────────→ timed-out
   └──────────────────────────────────→ startup-failed
```

### Start

1. The UI owner allocates a new monotonically changing generation and starts
   the explicit Developer or Release executable with an argument vector.
2. It immediately begins bounded reads of stdout and stderr and observes the
   process exit future. Partial frames are retained only within the configured
   input cap.
3. The worker sends a versioned ready frame containing its role and identity.
4. The UI validates the handshake before publishing the worker to pane state
   or sending terminal input.
5. A startup deadline covers both process creation and ready. Expiry starts
   forced termination and never exposes a half-owned pane.

### Normal stop

1. The owner stops admitting new work for that generation and sends a
   drain/stop request after the last accepted sequence.
2. The worker finishes or rejects queued work, releases Dart-owned state,
   replies with its final accepted sequence, flushes protocol output, and exits
   zero.
3. The acknowledgement is progress evidence only. The UI waits asynchronously
   for process exit and drains stderr before classifying cleanup as complete.
4. It closes/cancels all stream state, invalidates the generation, and proves
   no process or subscription remains outstanding.
5. Deadline expiry escalates through termination to `SIGKILL`, waits for the
   exit status, and reports forced cleanup rather than normal success.

Stop, cancellation, and close are idempotent. A late frame from an invalidated
generation is discarded after completing any transport-buffer release.

### Crash and replacement

An IPC error or stderr line is diagnostic evidence; the observed child exit is
the authoritative lifecycle boundary. The owner drains bounded stderr,
classifies the nonzero status/signal, closes that pane's PTY through its native
owner, and surfaces a pane-local failure. It does not reuse potentially corrupt
terminal state. A replacement receives a new generation and new process and
stream ownership; no port, PID, subscription, or queued frame is reused.

A UI-root or AppKit-host fatal error remains application-fatal. It triggers the
ordered all-worker shutdown above without synchronously waiting on the AppKit
thread.

## Bulk transfer, backpressure, and fairness

The process proof moved 128 MiB as ordered 1 MiB binary frames and verified
content markers. Five M1/arm64 runs measured 659.62--677.87 MiB/s for JIT and
762.52--797.12 MiB/s for AOT, above the provisional 100 MiB/s parser target.
Those figures validate transport feasibility, not the final UI-fairness or
pane-count budget.

Every producer has count and byte watermarks:

- PTY reactor to pane worker: suspend read interest or retain only bounded
  native pages above the high watermark and resume below the low watermark;
- pane worker to UI/render domain: coalesce replaceable damage and preserve
  required resources plus the newest generation;
- paste/input to pane worker: chunk before enqueue and stop admission at the
  high watermark;
- UI coordination: process only bounded frame work per Dart callback and yield
  to the AppKit run loop before its 4 ms ceiling.

No producer may use an unbounded Dart list, native queue, pipe write, stderr
capture, or one-Future-per-byte/cell structure as flow control. The Developer
and Release migration tasks measured AppKit heartbeat/fairness, startup,
backpressure, and lifecycle behavior before removing the old Engine
modification path. Worker RSS and multiple-pane budgets remain product-scale
follow-up measurements.

## Ownership invariants

1. A mutable Dart object graph has exactly one process/isolate writer.
2. A pane ID maps to at most one published live worker generation.
3. Messages contain copied immutable values or typed bytes; a raw pointer never
   crosses the process boundary.
4. A native handle records its native domain and generation. Its integer value
   does not grant permission to call it from another process or thread.
5. AppKit is called only by the UI root/main domain. Workers request UI changes
   through the versioned protocol.
6. Correctness cannot depend on child Dart pthread identity, parent/child
   scheduling coincidence, or pipe callbacks running immediately.
7. Root handlers never synchronously wait for a worker, PTY, GPU fence, or
   process exit.
8. Process exit plus stream cleanup, not a protocol acknowledgement, is the
   authoritative worker-resource boundary.

## Evidence

The original Phase 0 same-group proof remains useful historical evidence for
the semantic scenarios and throughput target, but its patched Engine topology
is superseded and may not be restored. The accepted unmodified process proof
ran the same official source in JIT and self-contained AOT modes and verified:

- ready identity from a distinct child PID;
- ping/pong and ordered 128 MiB transfer;
- graceful stop with exit zero;
- uncaught Dart failure with a nonzero exit and preserved stderr diagnostic;
- acknowledged hang followed by forced kill and observed nonzero exit;
- successful replacements after both failure classes;
- zero outstanding worker processes after final cleanup;
- exact clean Dart Engine checkout before and after the run.

M1 mean ready time was 148--152 ms in JIT and 12--17 ms in AOT. The reusable
arm64 AOT helper measured 5,978,960 bytes and had no dynamic Dart runtime
dependency. These measurements must be repeated against the product
implementation; they are not a claim about final pane-scale RSS or latency.

## Alternatives rejected

### Run terminal work in the UI root

Rejected because parser, grid, and shaping work can monopolize AppKit and
violate the hard scheduling ceiling.

### Keep the Phase 0 same-group Engine patches

Rejected because all Dart and Dart Engine source is an immutable upstream
input. Storing the same edit as a local SDK commit or fork is equally
prohibited.

### Use multiple stock Engine roots as dynamic workers

Rejected because the public API has global shutdown but no individual root
retirement/unregistration. Closed panes would retain Engine bookkeeping until
application exit.

### Build the GUI host directly on public `dart_api.h`

Rejected by ARM64 JIT/AOT evidence. The public surface lacks the complete
platform, async, IO, and isolate bootstrap needed for ordinary Dart semantics;
using private `runtime/bin` code is prohibited.

### Let the official Dart executable own AppKit

Rejected because both JIT and AOT Dart entrypoints ran away from the process
main thread and the main dispatch queue was unserviced during bounded probes.

### Share raw native memory between UI and workers

Rejected as the default because lifetime, bounds, cancellation, and mutation
races become implicit. A separately designed tokenized shared buffer remains a
future measured transport optimization only if framed pipes fail a performance
gate; it may not weaken process ownership or generation checks.

## Consequences

- Dart and Dart Engine remain official, reproducible, and unmodified.
- AppKit keeps its proven one-root main-thread host while worker crashes and
  hangs have an OS-authoritative containment and cleanup boundary.
- Terminal state retains an auditable single writer, but every independent
  worker pays process startup and runtime-memory costs.
- Dart ports and `TransferableTypedData` across UI/worker ownership are
  replaced by explicit serializable framing, bounded buffering, stderr, and
  exit-status handling.
- Release packaging gains one reusable self-contained helper executable;
  Developer mode depends on the exact official Dart toolchain and must not
  package the full SDK as a release dependency.
- macOS x86_64 compilation requires an official x64 SDK/host rather than ARM64
  cross-compilation. That remains a lower-priority Rosetta/Universal follow-up
  after the M1 migration and cannot reopen this topology decision.
- The former product Engine modification files and all related build,
  provenance, audit, and fixture machinery were deleted after both M1
  Developer JIT and Release AOT passed this contract.
