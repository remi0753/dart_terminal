# ADR-001: Dart/native boundary

- Status: Accepted for Phase 0
- Date: 2026-08-31
- Decision owners: Dart Terminal project
- Related: `ROADMAP.md` sections 2, 4, 6, 7; `FEATURE_MATRIX.md`

## Context

Dart Terminal is an independent terminal emulator whose terminal semantics are implemented in
Dart. It is not a Dart wrapper around Ghostty and does not link Ghostty or `libghostty`.

A daily-driver macOS terminal still requires APIs that cannot be implemented correctly as a
portable Dart package: AppKit lifecycle and subclassing, PTY creation after `fork`, CoreText,
Metal, `NSTextInputClient`, pasteboard/accessibility/Secure Input, and embedding a release AOT
snapshot. Calling Objective-C runtime functions directly for every operation would not remove
the native dependency; it would move fragile ABI, thread, and ownership rules into untyped Dart
FFI code.

The boundary must also preserve these performance properties:

- AppKit is never blocked waiting for terminal parsing, PTY I/O, glyph generation, or a worker
  isolate.
- Cell, glyph, and byte hot paths cross FFI in batches, not one element at a time.
- A slow consumer applies backpressure or drops superseded render frames; no queue is unbounded.
- The child side of a PTY spawn never calls Dart, Objective-C, a heap allocator, or code that can
  acquire a lock inherited across `fork`.

## Decision

Use a small, versioned C ABI as an **OS adapter**. Dart owns product logic and all terminal
meaning. Native code owns only OS objects and operations whose correctness depends on a macOS ABI,
thread affinity, process semantics, or GPU lifetime.

### Dart owns

- application/window/tab/split state and action routing;
- terminal session state and pane ownership;
- streaming UTF-8 and VT parsing;
- primary/alternate grid, cursor, modes, scrollback, reflow, selection, search, hyperlinks, and
  protocol replies;
- key/mouse/paste encoding after native input normalization;
- configuration schema, themes, keybinds, and shell-integration policy;
- damage calculation, frame generation ordering, and stale-frame policy;
- glyph/style/resource cache policy expressed in stable IDs;
- security policy for OSC/DCS/APC, clipboard, links, images, and paste;
- lifecycle orchestration, deadlines, telemetry aggregation, and user-visible diagnostics.

### Native macOS code owns

- `NSApplication`, main run loop integration, windows, views, menus, pasteboard, accessibility,
  Secure Input, and state restoration adapters;
- release AOT Dart VM embedding and bounded root-isolate message scheduling;
- `openpty`/`forkpty`, controlling terminal setup, `execve`, nonblocking FD readiness,
  `ioctl`, signals, process groups, and `waitpid`;
- `MTKView`/`CAMetalLayer`, Metal device/queue/pipeline/command-buffer/drawable objects, fences,
  and presentation;
- CoreText font descriptors/faces/runs, glyph rasterization, color glyph extraction, and macOS
  fallback resolution;
- the `NSTextInputClient` subclass and candidate-window geometry response;
- conversion from OS-specific events and failures to stable C wire values.

Native code does **not** interpret VT sequences, mutate terminal modes, choose key protocol bytes,
decide selection semantics, or own the authoritative terminal grid.

### Package placement

Reusable AppKit primitives remain in `dart_appkit`: application/window/view/menu/pasteboard/screen,
focus, backing-scale, and a generic IME-capable custom-view lifecycle.

Terminal-specific adapters live in this repository:

```text
packages/terminal_platform_macos/   Dart FFI facade and wire codecs
native/macos/runtime/               AOT host integration used by the app bundle
native/macos/pty/                   PTY/process reactor
native/macos/renderer/              CoreText/Metal adapter and MSL
native/macos/integration/           terminal view, IME, accessibility, pasteboard
```

PTY functions, terminal draw formats, terminal shaders, and VT policy must not be added to the
generic `dart_appkit` API.

## ABI shape

The public headers must compile as C11 and C++20. Objective-C/Swift/Zig/Dart layouts never cross
the ABI.

### Allowed wire types

- exact-width integers (`uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`, signed equivalents);
- IEEE `float`/`double` only where coordinates or metrics require them;
- opaque 64-bit generation-checked handles; zero is invalid;
- `(pointer, byte_length)` spans whose lifetime is stated explicitly;
- fixed-layout structs with a `struct_size` and `abi_version` prefix;
- integer status, event, flag, and discriminant values.

Do not expose `bool`, `long`, `size_t` in persistent wire records, C bitfields, Objective-C object
pointers, Dart handles, STL/Swift/Zig containers, or compiler-dependent enums.

### Versioning

- The top-level ABI has a monotonically increasing `DT_ABI_VERSION`.
- Every asynchronous event starts with
  `[abi_version, event_type, source_handle, generation, monotonic_ns, operation_id]`.
- Every packed binary batch starts with magic, format version, header byte length, total byte
  length, and reserved-zero fields.
- Additive fields require a larger `struct_size`; readers ignore a known record's trailing bytes.
- A changed interpretation, alignment, ownership rule, or removed field requires a new format
  version. Unknown mandatory versions are rejected, never guessed.
- Debug and release builds run the same ABI conformance fixtures.

## Call direction and scheduling

### Dart to native

Synchronous FFI is allowed only for bounded, nonblocking operations such as handle creation,
updating cached view geometry, enqueueing a PTY write, leasing a render slot, or submitting an
already prepared batch. A synchronous call must not:

- wait for a child, worker thread, isolate, GPU fence, drawable, display link, or user response;
- run a nested AppKit event loop;
- invoke a Dart closure or post back into the calling isolate synchronously;
- parse unbounded input or allocate proportional to attacker-controlled lengths without a cap.

Operations that can wait return an operation ID immediately and complete through an event.

### Native to Dart

Native code posts immutable messages to a `Dart_Port` with `Dart_PostCObject` or its supported
typed-data form. It never enters an isolate, invokes Dart synchronously, or holds a native mutex
while posting. A failed post is counted and handled by the owning subsystem's failure policy; it
does not block AppKit or a PTY readiness source.

The root UI isolate receives AppKit events. Each engine isolate receives only its pane's ordered
PTY batches and control messages. The render coordinator receives generation-tagged damage from
engine isolates. Cross-domain messages use immutable scalars or `TransferableTypedData` until a
measured native double-buffer alternative proves better.

## Subsystem contracts

### PTY/process

The parent prepares all argv/env/cwd bytes, FD actions, signal policy, and error-report pipe before
the fork operation. In the child branch the permitted sequence is restricted to async-signal-safe
syscalls needed to establish the session/controlling TTY, set file descriptors and cwd, reset
signals, and call `execve`. Error reporting writes a fixed record to the pre-opened pipe and calls
`_exit`.

The child branch must not call Dart VM APIs, Objective-C/Swift, logging frameworks, `malloc`/`new`,
locale APIs, dynamic loader APIs, dispatch/GCD, locks, or callbacks. Code review and a symbol-level
child-path audit are release gates.

The native reactor owns the master FD and process identity. It preserves byte order and batches
read output. The Dart session owns terminal state. PTY events carry pane handle, session
generation, sequence number, monotonic timestamp, and byte payload. Stale generations are dropped.

Initial limits:

- read delivery target: at least 64 KiB per batch when a burst is available;
- bounded per-pane write queue with explicit high/low water marks;
- large paste is chunked above the queue, never copied into an unbounded native list;
- resize events coalesce to the newest cell/pixel size;
- exit is emitted once, only after status is known or EOF/error is terminal.

### Renderer

The engine emits changed row ranges and resource IDs, not object graphs. The render coordinator
creates a versioned packed frame with a monotonic terminal generation. One frame crosses Dart →
native with a small constant number of FFI calls.

The initial implementation copies a submitted packed batch into one native-owned in-flight Metal
slot. A submit returns a token. The slot remains unavailable until command-buffer completion.
Triple buffering is the default for the Phase 0 spike. If this copy violates the frame budget, a
native slot lease may expose a bounded caller-writable byte span; the lease must still have a
token, capacity, owner thread, cancel operation, and timeout. A raw pointer is never sent between
Dart isolates.

The native renderer may reject stale generations before encoding. The Dart coordinator may drop
unsent intermediate generations. A full snapshot is reserved for first frame, resize/scale/font
change, atlas reset, or device recovery.

### CoreText/font

Dart requests shaping/raster work per text run or glyph set, never per cell. Native returns packed
glyph IDs, positions, cluster indices, face IDs, metrics, presentation kind, and explicit buffer
lengths. CoreText objects remain behind generation-checked handles in their font domain. Dart owns
cache keys and the relationship between terminal graphemes and returned runs.

### IME and AppKit input

The custom native view implements `NSTextInputClient`. AppKit callbacks update native marked-text
state and post normalized immutable events containing replacement/selection ranges and UTF-8 text.
Physical key data and text-composition data are separate event types.

Methods such as candidate-rect lookup must answer synchronously from the latest geometry cached in
the native view. They must never wait for Dart. Dart submits caret/preedit geometry whenever the
authoritative terminal cursor or backing scale changes. A sequence/generation field makes stale
geometry observable in diagnostics.

## Ownership rules

| Resource | Owner | Borrow/transfer rule | Destruction domain |
| --- | --- | --- | --- |
| AppKit object | native generation registry; Dart owns one handle lease | attaching a view borrows, never consumes | AppKit main thread, asynchronously if requested elsewhere |
| PTY master/process | native PTY reactor | Dart refers by pane/session handle only | PTY reactor; child always reaped |
| terminal mutable state | one Dart engine isolate | immutable messages only | owning engine isolate |
| packed damage before submit | Dart render coordinator | borrowed for call; native copies in initial design | render coordinator |
| Metal in-flight slot | native renderer | submit token is a lease; no reuse before completion | render domain after fence/callback |
| CoreText object | native font registry | opaque generation handle | font/render domain with autorelease pool |
| posted event payload | sender until `Dart_PostCObject` returns; VM thereafter | immutable copy/typed-data contract | automatic after post |

Every create/lease/submit operation has exactly one release/cancel/complete path. Double release,
unknown handle, wrong generation, wrong thread, and use-after-shutdown return deterministic status
and are covered by tests.

## Errors, cancellation, and shutdown

- No exception, `NSError`, C++ exception, Swift error, or Dart exception crosses the C ABI.
- Sync calls return a stable status enum and optionally fill a caller-provided diagnostic record.
- Async completion includes operation ID and status. Human-readable text is diagnostic, not parsed
  for behavior.
- `EINTR` is retried where safe; `EAGAIN` is readiness/backpressure, not a fatal error.
- Cancellation is idempotent. A late completion is ignored by generation and still releases its
  native resources.

Ordered app shutdown:

1. stop accepting new windows, panes, paste, and native input posts;
2. cancel IME composition and disable Secure Input;
3. tell engine isolates to stop accepting PTY data and await bounded acknowledgements;
4. close PTY writes, send HUP/TERM, apply the grace deadline, KILL if required, and reap every child;
5. stop render submission, wait for or abandon in-flight buffers using the documented device-loss
   path, then release Metal/CoreText/view handles on their domains;
6. close native ports and drop all late generation-tagged events;
7. shut down worker isolates, root AOT isolate/VM, then return control to AppKit termination.

Timeout expiry is a recorded failure and proceeds to the subsystem's forced-cleanup path; it never
leaves an unbounded wait on the main thread.

## Thread-domain rules

| Domain | May do | Must not do |
| --- | --- | --- |
| AppKit main + Dart UI root | UI state coordination, short action routing, enqueue coarse work | PTY wait, parser loops, shaping/raster loops, GPU waits, large copies |
| native PTY reactor | FD readiness, bounded queues, resize/signal/waitpid | AppKit, terminal semantics, Dart synchronous entry |
| Dart engine isolate per pane | parse bytes, mutate grid/modes, emit replies/damage | AppKit calls, another pane's mutable state |
| Dart render coordinator per window | coalesce damage, pack latest frame/resources | own terminal state, block on GPU |
| native render/font domain | CoreText/Metal resources, encode/present, completion | VT semantics, wait for Dart while holding resource locks |

No design may intentionally occupy one AppKit/main-run-loop turn for 4 ms or more. The target is
p95 below 1 ms; 4 ms is the hard scheduling ceiling before work must be split or moved.

## When native expansion is allowed

Failure to meet a benchmark does not automatically authorize moving terminal semantics to native.
First remove avoidable allocation/copying, object-per-cell structures, unbounded work, and wrong
isolate boundaries. If a release-AOT, typed-data implementation still misses a Phase gate on the
baseline machine, the following bounded expansions may be proposed in a new ADR with before/after
profiles:

| Symptom after Dart optimization | Native candidate | Semantic owner remains |
| --- | --- | --- |
| parser below 100 MiB/s | SIMD UTF-8 validation or byte-classification scan returning action spans | Dart parser/state machine |
| damage transfer exceeds frame budget | tokenized native double/triple-buffer slot lease | Dart damage/generation policy |
| glyph preparation exceeds frame budget | batched CoreText shape/raster and atlas upload | Dart grapheme/style/resource mapping |
| large paste/PTY burst causes copies | native bounded ring pages posted as immutable external typed data | Dart ordering/backpressure policy |
| AppKit callback approaches 1 ms p95 | native cache of already-computed geometry/display data | Dart application and terminal state |

Moving VT dispatch, grid mutation, selection rules, protocol security policy, or key encoding to
native requires revisiting the project's defining constraint and is a feasibility failure, not a
routine optimization.

## Alternatives rejected

### All Objective-C runtime calls directly from Dart FFI

Rejected because AppKit subclassing, callback lifetime, thread affinity, autorelease pools, fork
safety, and ABI evolution would remain native concerns without a typed adapter.

### Put terminal adapters into `dart_appkit`

Rejected because PTY policy, packed terminal frames, terminal shaders, and IME semantics are not
generic AppKit primitives and would couple two projects' release cadence.

### Link Ghostty or `libghostty`

Rejected because it would replace the requested Dart terminal core rather than validate it.

### One root isolate for UI, parser, and rendering

Rejected because an output burst or shaping miss would block AppKit and violate the Phase 0 main
run loop gate.

## Consequences

- Native code is unavoidable but narrow, auditable, and testable without terminal semantics.
- Wire formats and lifecycle contracts require more up-front work than ad hoc FFI calls.
- There is one extra copy in the initial render path and potentially in PTY delivery; Phase 0
  measures both before introducing pointer leases.
- Generation handles and operation IDs make late callbacks and asynchronous destruction explicit.
- The pure Dart terminal core can run headless, fuzzed, benchmarked, and compared independently of
  AppKit and Metal.

## Phase 0 validation

This decision is accepted only if the following spikes pass on real hardware:

- release AOT root isolate on the AppKit main thread;
- long-lived worker isolate start/transfer/stop/error lifecycle;
- safe PTY spawn, interactive zsh, resize, signals, exit, and at least 64 KiB output batches;
- 100,000 packed Metal instances with tokenized in-flight buffers;
- batched CoreText Latin/CJK/emoji/ligature runs;
- `NSTextInputClient` marked text and candidate rect without synchronous Dart re-entry;
- parser/render/input benchmark output proving no planned main-loop turn is 4 ms or longer.

If any item fails, this ADR returns to Proposed and production feature work does not begin.
