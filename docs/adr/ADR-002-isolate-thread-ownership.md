# ADR-002: isolate, thread, and ownership model

- Status: Accepted for Phase 0
- Date: 2026-08-31
- Decision owners: Dart Terminal project
- Related: `ROADMAP.md` sections 4, 6, 7, and 9; ADR-001; DT-002; DT-003

## Context

Dart Terminal is an independent terminal emulator implemented in Dart. It does
not embed Ghostty or use Ghostty as its terminal core. The macOS process must
keep AppKit responsive while terminal parsing, grid mutation, damage
generation, shaping preparation, and large byte transfers continue.

Dart isolates do not share mutable Dart objects. AppKit requires main-thread
access. Dart VM worker isolates are scheduled on VM-managed worker threads and
must not be assumed to retain one operating-system thread. Native PTY, font,
and render resources have their own thread-domain constraints. Treating an
isolate, an OS thread, and a native resource queue as the same ownership unit
would therefore be incorrect.

The pinned `dart_engine` embedder used by `dart_appkit` initially exposed a
further feasibility risk: its root isolate did not publish `Platform.script`,
and it did not register the callback that initializes a child in the existing
isolate group. Consequently, release AOT `Isolate.spawn` failed with
`Unsupported operation: Isolate.spawn` even though the Dart VM supports it.

## Decision

Use **single-writer isolate ownership** for Dart mutable state and explicit
native execution domains for OS resources. Only the root UI isolate is bound
to an OS thread. Worker isolates are concurrency domains, not thread-affinity
domains.

```text
AppKit process main thread
└─ root UI isolate
   ├─ immutable commands → terminal-engine isolate per pane
   ├─ immutable damage  ← terminal-engine isolate per pane
   └─ immutable frames  ↔ render-coordinator isolate per window

VM worker pool
├─ terminal-engine isolates (single writer for pane state)
└─ render-coordinator isolates (single writer for pending frame state)

Native domains
├─ AppKit main domain
├─ PTY reactor domain
└─ Metal/CoreText render domain
```

### Domain responsibilities

| Domain | Owns | Does not own |
| --- | --- | --- |
| root UI isolate on AppKit main | window/tab/split model, focus/input routing, worker handles, user-visible lifecycle | terminal grid, parser loop, PTY wait, font shaping, GPU waits |
| terminal-engine isolate per pane | UTF-8/VT parser, modes, grid, scrollback, replies, selection/search, damage generation | AppKit objects, another pane's state, native FD/GPU objects |
| render-coordinator isolate per window | damage coalescing, latest-generation policy, packed frame construction, atlas request ordering | authoritative grid, AppKit, Metal object lifetime |
| native PTY reactor | master FD, child/process group, readiness, bounded read/write queues, resize/signal/wait | VT semantics or Dart state |
| native render/font domain | CoreText and Metal objects, buffers, fences, command encoding/presentation | terminal semantics or frame-generation policy |

Multiple logical domains may temporarily execute on the same physical core or
VM worker thread. Correctness never depends on that coincidence.

## Embedded VM contract

The root isolate uses the custom AppKit-backed message scheduler proven by
DT-002. It is explicitly assigned to the root after creation, and all of its
scheduled Dart messages are serviced on the process main thread with a hard
per-turn cap of 64 messages or 4,000 us.

Same-group workers use `Isolate.spawn`. They are initialized through the Dart
embedder's `initialize_isolate` callback and then owned by the VM's asynchronous
run loop. The callback prepares core/async/isolate/IO hooks but does not install
the root's AppKit message callback. Therefore worker work cannot be routed onto
the AppKit scheduler accidentally.

The pinned embedder needs two narrow changes, recorded in
`patches/dart-engine-worker-isolates.patch` and applied idempotently by the
Phase 0 build:

1. pass the root snapshot URI to `DartIoSettings.script_uri`, so
   `Platform.script` is available to `Isolate.spawn`;
2. register an `initialize_isolate` callback that prepares core libraries for
   children created inside the existing isolate group.

`create_group` remains unset. `Isolate.spawnUri` and arbitrary new isolate
groups are intentionally unsupported in the terminal application. All product
workers execute the already-loaded, signed AOT program in the root group.

This patch changes runtime hosting capability only. It does not move terminal
semantics into native code and has no dependency on Ghostty.

## Ownership invariants

1. A mutable Dart object graph has exactly one owning isolate.
2. A pane ID maps to at most one live terminal-engine generation.
3. Messages contain immutable values, copied typed data, or
   `TransferableTypedData`; no raw pointer crosses isolates.
4. A native handle records its native domain and generation. Possessing the
   integer handle does not grant permission to call it from the current thread.
5. AppKit is called only by the root/main domain. A worker sends a request to
   the root or a native domain queue instead of calling AppKit through FFI.
6. Worker correctness cannot depend on `pthread` identity, thread-local caches,
   or an autorelease pool surviving between messages.
7. Root handlers enqueue bounded work and return. They do not wait
   synchronously for a worker, PTY, GPU fence, or child process.

## Message envelope and ordering

Every product message will carry, directly or in its packed header:

```text
wire_version
message_kind
owner_id (window or pane)
owner_generation
sequence
operation_id
payload length / payload
```

The receiver rejects an unsupported version, stale owner generation, duplicate
terminal sequence, or payload above its configured cap. A pane's PTY batches
are ordered. UI-only notifications may coalesce. Render damage may skip stale
intermediate generations but cannot reorder resources ahead of their defining
generation.

Send ports are capabilities. They are distributed during a ready handshake,
not stored globally. Closing the owning receive port revokes that command
path. Native ports and FFI handles follow the generation rules in ADR-001.

## Worker lifecycle

Each worker follows this state machine:

```text
creating → ready → running → draining → stopped
                    └───────────────→ crashed
```

### Start

1. The root creates dedicated command, error, and exit channels.
2. It calls `Isolate.spawn` with `errorsAreFatal: true`, `onError`, and
   `onExit` before publishing the worker to application state.
3. The worker creates its command receive port and sends `ready` containing
   protocol version and its send capability.
4. The root validates the handshake and only then assigns the pane/window
   generation and sends work.
5. Startup has a deadline. On expiry, the root kills the isolate, closes all
   ports, records a failure, and does not leave a half-owned pane.

### Normal stop

1. The root stops admitting new payloads for the owner generation.
2. It sends `drain/stop` after the last accepted sequence.
3. The worker finishes or rejects queued work, releases Dart-owned state,
   replies with its final accepted sequence, and closes its receive ports.
4. The root waits asynchronously for `onExit` with a deadline, closes its
   receive ports, and invalidates the generation.
5. Deadline expiry invokes `Isolate.kill(priority: Isolate.immediate)` and is
   reported as forced cleanup, not normal success.

Cancellation and close are idempotent. A late reply from an older generation
is discarded but still completes any sender-side resource release.

### Crash

`onError` is diagnostic evidence; `onExit` is the authoritative lifecycle
completion. The root must handle either arrival order and must not block the
AppKit thread while waiting. A terminal-engine crash closes that pane's PTY
through the native owner and surfaces a pane-local error. It does not mutate or
restart from potentially corrupt grid state. A fresh pane may be created with a
new generation. Repeated render-coordinator failure falls back to the last
committed native frame while the window reports the failure.

An embedder/VM fatal error is process-fatal because isolate containment can no
longer be trusted. It follows the ordered application teardown in ADR-001.

## Bulk transfer and backpressure

For Phase 0, cross-isolate byte and packed-damage payloads use
`TransferableTypedData`. DT-003 tested 256 KiB messages, well above the planned
64 KiB PTY delivery floor. The sender loses access to a transferred payload;
the receiver materializes it once and treats it as immutable input.

The product queue policy is bounded by both message count and byte count:

- PTY reactor → engine: per-pane high/low water marks; suspend FD read interest
  or retain bounded native pages when the isolate is behind;
- engine → renderer: keep required resources and the newest generation, drop
  superseded unsent damage;
- paste → PTY: chunk before enqueue, pause admission at the high-water mark,
  resume below the low-water mark;
- root coordination: small scalar messages only; bulk data bypasses the root
  whenever sender and final owner can communicate directly.

No producer may use an unbounded Dart `List`, native queue, or one-Future-per-
byte/cell structure as flow control.

`TransferableTypedData` remains the default while its measured transfer cost is
within budget. A native double/triple buffer may replace it only for renderer
submission or bounded PTY pages after a benchmark demonstrates a material
benefit. Such a buffer requires fixed capacity, owner generation, lease token,
completion/fence, cancellation, and timeout; a raw pointer still never crosses
isolates.

## Scheduling and fairness

- Root/AppKit turn target: p95 below 1 ms; hard ceiling below 4 ms.
- A root continuation performs at most one bounded coordination unit before
  yielding. Bulk loops are acknowledged/windowed and periodically yield.
- Parser and grid work execute only in the pane's engine isolate.
- A pane flood cannot share mutable state with another pane. Per-pane queue and
  work budgets are required before multiple panes are enabled.
- Worker OS thread migration is permitted. Native thread-affine work is sent to
  its native domain queue with an operation ID.
- Synchronous FFI from a worker is limited to bounded, thread-neutral enqueue or
  query operations documented by ADR-001.

## Phase 0 evidence

DT-003 ran in the signed ProductARM64 AOT AppKit bundle on real arm64 hardware.
Each run performed:

- root-main ownership checks throughout the test;
- long-lived worker ready/ping/data/stop/onExit lifecycle;
- 128 MiB transfer as 512 transferable 256 KiB batches with content and order
  validation;
- a second worker that throws intentionally, with both `onError` and `onExit`
  observed;
- a 1 ms root heartbeat and native main-pump occupancy measurement.

Six consecutive runs passed. Transfer throughput ranged from 1,056.65 to
2,702.08 MiB/s, above the provisional 100 MiB/s parser target. The worst native
root message-pump turn was 1,567 us, below the 4,000 us hard ceiling. The
maximum heartbeat gap was 30,941 us during cold startup; it is not a measured
single handler duration and remains a DT-011 latency-distribution item.

## Alternatives rejected

### Run UI, parser, and renderer in the root isolate

Rejected because output or glyph work can monopolize AppKit and violate the
hard scheduling ceiling.

### Pin every Dart worker to a dedicated pthread

Rejected as an ownership assumption. The VM owns worker scheduling. Native
thread affinity is represented by native queues, while Dart state affinity is
represented by isolate ownership.

### Use shared raw native memory between isolates

Rejected as the default because lifetime, bounds, cancellation, and mutation
races become implicit. A tokenized bounded native buffer remains a measured
fallback for specific transfer paths.

### Start a helper process instead of enabling worker isolates

Rejected for normal terminal panes because it adds IPC, duplicated runtime
state, signing/sandbox lifecycle, and crash semantics without solving the
in-process architecture required by the roadmap.

## Consequences

- Terminal state has an auditable single writer and can be tested headlessly.
- AppKit ownership is explicit and worker crashes are observable without a
  synchronous cross-isolate wait.
- Cross-isolate data incurs controlled transfer/envelope overhead and requires
  deliberate queue limits.
- The pinned Dart embedder carries a small, revision-specific patch until the
  equivalent capability is accepted upstream or exposed by `dart_appkit`.
- `Isolate.spawnUri` is unavailable by design; workers must be entry points in
  the signed AOT snapshot.
- Phase 1 must add repeated create/destroy, forced-timeout, and leak testing;
  Phase 0 proves feasibility and fixes the ownership contract.
