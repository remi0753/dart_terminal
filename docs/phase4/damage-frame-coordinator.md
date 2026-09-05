# Phase 4 — Damage and newest-frame coordinator

- Status: complete
- Date: 2026-09-06
- Scope: fifth Phase 4 roadmap item
- Related: ADR-001, ADR-002, ADR-003, ADR-004, ADR-005, SCR-09, REN-04,
  REN-05, REN-09

## Purpose

Move authoritative terminal changes to a retained render model through the
accepted bounded, versioned damage contract, then generate and submit only the
newest useful Metal frame. Preserve every unapplied incremental delta while
allowing redundant frame work to be discarded when rendering falls behind.

## Background

`TerminalScreen` already owns private SoA cell arrays, coalesced half-open row
damage, one row-version increment per clean-to-dirty cycle, monotonic screen
generation, and explicit full-snapshot state. The just-completed Metal boundary
owns three fixed copied native slots, rejects stale frame generations, and
selects the newest READY frame. What is still absent is ADR-003's exact damage
wire codec, a render-side retained grid, the ADR-004 one-unacknowledged-packet
ownership rule, and a Dart policy that never accumulates packed frames.

## Scope

- Encode and strictly decode ADR-003's 80-byte header, 24-byte row records,
  aligned columnar arrays, zero padding/reserved fields, and 32 MiB limit.
- Capture either all rows for an explicit full snapshot or only coalesced dirty
  intervals, without exposing authoritative typed arrays.
- Apply validated full/incremental packets to a bounded retained render model
  with strict pane, damage, dimension, row-version, and resource ordering.
- Transfer damage with `TransferableTypedData`, keep at most one packet awaiting
  ACK, preserve mutations made during that wait as the next coalesced capture,
  and validate every ACK scalar before releasing sender bookkeeping.
- Track logical model revision separately from native frame generation. On
  native backpressure retain one newest-dirty marker, not a queue or a stale
  prepared-frame list; after an accepted frame, later applied damage schedules
  exactly one newer frame.

## Out of scope

- Turning grid cells into CoreText runs/atlas entries/Metal instances; this
  task accepts an injected bounded frame builder so damage ownership and newest
  frame policy can be proven independently.
- Resize/backing-scale/font rebuild, cursor animation/occlusion, failure
  recovery, and metrics, which retain their later roadmap positions.
- Resource-definition wire formats. The coordinator exposes and validates the
  required/applied resource generation boundary, while style/grapheme/palette
  payload codecs remain owned by their corresponding later integration.
- Passing damage through the AppKit/root UI isolate or retaining mutable data
  across isolates.

## Dependencies and ownership

- The terminal engine is the only writer of `TerminalScreen` and its damage
  state. Capture copies packed bytes and then clears only the captured damage;
  later mutations begin a separate pending union.
- The outbox owns one transferred generation until an exact ACK. A full
  snapshot is acknowledged on the authoritative screen only after the render
  model accepts it.
- The render model owns independent typed arrays and applies all incremental
  deltas in order. A newer full snapshot may explicitly supersede an older
  retained model, but a newer incremental packet never licenses dropping an
  earlier unapplied delta.
- The frame scheduler owns monotonic nonzero frame generations and one dirty
  logical-model marker. Native owns copied READY/IN_FLIGHT slot bytes.

## Ordered subtasks

1. **Strict damage codec and retained render model**
   - Encode full/dirty rows from `TerminalScreen` into the exact little-endian
     columnar layout and decode only canonical offsets, padding, values, and
     bounds.
   - Apply full snapshots and consecutive deltas to an independently owned
     retained grid; reject stale/duplicate/future/resource/dimension/version
     violations without partial mutation.
   - Complete with malformed corpus, ownership, sparse/full, wrap/ring-row, and
     32 MiB/cell-limit tests plus a dedicated commit.
2. **One-in-flight transferable outbox and exact ACKs**
   - Capture into `TransferableTypedData`, allow only one unacknowledged packet,
     leave later screen changes coalesced, and emit the next packet only after
     an exact accepted ACK.
   - Cover full-snapshot acknowledgement timing, invalid/duplicate/future ACK,
     stale pane replacement, closed/deadline resync, and bounded bookkeeping.
3. **Newest-model frame scheduler and native outcome connection**
   - Coalesce any number of applied model revisions into one pending frame,
     allocate strict frame generations, expose accepted/stale/backpressure
     outcomes, and never retain more than one prepared frame/newest marker.
   - Prove an unapplied delta is never dropped, backpressure does not grow a
     queue, stale prepared work is replaced by a newer model, and accepted
     submission advances exactly once.

The parent remains incomplete until all three children are independently
validated and committed. The resize/full-rebuild task must not begin earlier.

## Acceptance criteria

- Canonical packets reproduce every captured field and reject every malformed
  header, offset, alignment, padding, row, cell, flag, color/scalar, ID,
  generation, length, and configured-cap violation before publication.
- Normal output transfers only dirty intervals. First attach and explicit
  resync transfer a full snapshot. Damage created while one packet awaits ACK
  remains pending and is neither merged into transferred ownership nor lost.
- The render model applies incremental generations consecutively and
  atomically. Duplicate/old packets do not mutate; gaps require resync; a valid
  newer full snapshot can replace the prior model.
- Queue state is constant-size: one transferred packet per pane, one coalesced
  authoritative dirty state, one newest frame marker, and three native slots.
- No AppKit handler, drawable callback, or GPU completion waits for Dart or
  participates in logical damage application.

## Verification plan

- Focused codec/model/outbox/scheduler tests with handcrafted corruption at
  every section boundary and exact before/after snapshots for atomic rejection.
- Transferable materialization tests, delayed/out-of-order ACK tests, sustained
  mutation/backpressure stress, and fixed-cap counters.
- `dart format`, `dart analyze`, product `make test`, focused Release AOT, and
  `make runtime-source-check` after each child as appropriate.
- Review staged/unstaged diffs and all three worktrees before every commit.

## Investigation log

- 2026-09-06: after product commit `0240102`, reread the Phase 4 roadmap,
  README/matrix, ADR-001/002/003/004/005, `TerminalScreen` damage/version
  internals, renderer facade/atlas bridge, current tests, and both worktrees.
  The Metal parent is complete and both repositories are clean; damage
  coalescing/frame generation is the first unchecked item.
- 2026-09-06: the task contains three independently reviewable ownership
  boundaries and is too large for one safe commit. It is split above before
  implementation as required. The exact order follows the data flow: canonical
  copied bytes and atomic application first, transferable sender ownership
  second, latest-only frame policy third.
- 2026-09-06: resource tables currently expose separate style, grapheme, and
  palette generations but no accepted aggregate resource packet. The damage
  codec therefore requires an explicit positive `requiredResourceGeneration`
  supplied by the future resource owner; inventing an aggregate or serializing
  definitions inside the damage packet would violate ADR-003 and this task's
  position.
- 2026-09-06: the Xcode resumption gate was rechecked before continuing.
  `xcrun --find metal` resolves the installed compiler and
  `xcrun -sdk macosx metal -help` prints normal compiler help, so the prior
  missing-component blocker remains resolved. An exploratory standalone
  `xcrun --find metallib` lookup is still unavailable, but it is neither one of
  the two accepted resumption checks nor used by the checked-in precompiled
  shader build.
- 2026-09-06: subtask 1 uses one canonical allocation/copy boundary in each
  direction. Capture copies private `TerminalScreen` fields into a versioned
  byte packet before clearing only captured dirty intervals; decode copies
  transport bytes and creates independent validated SoA columns. No mutable
  authoritative array or transport backing store escapes either owner.
- 2026-09-06: incremental application is staged per affected whole row and all
  staged rows are topology-checked before any row is published. This costs a
  bounded row-sized copy but makes row-version, wide/continuation, dimension,
  resource-generation, and damage-generation rejection atomic. A validated
  newer full snapshot may bridge a damage-generation gap; retained resource
  generation is never allowed to move backward.
- 2026-09-06: initial screen rows legitimately have row version zero until
  first dirtied. The codec therefore accepts zero row versions in a full
  snapshot while incremental application still requires exactly the retained
  row version plus one. Logical-line IDs remain strictly nonzero as ADR-003
  requires.
- 2026-09-06: the first transfer-generation exhaustion test exposed signed
  native-integer wrap from `0x7fffffffffffffff` to the minimum value when the
  counter was incremented. The outbox now records an explicit exhausted bit
  after publishing the last valid generation and closes before another capture
  instead of relying on an already-overflowed comparison. Replacement with a
  newer pane generation resets this bit together with the damage sequence.
- 2026-09-06: while validating subtask 2, the first 100,000-cell product
  measurement found the preceding capture implementation above ADR-003's 4 ms
  gate even though TTD transfer plus strict decode already passed. The newly
  inserted prerequisite is completed independently in
  [`damage-capture-performance.md`](damage-capture-performance.md) at commit
  `068c3bc`: full capture plus TTD construction is now 650 us p95 and direct
  isolate transfer plus strict decode/ACK is 1,832 us p95.
- 2026-09-06: the first real-renderer scheduler probe opened the renderer
  without a view and received native status 3 (`not found`) when seeding the
  stale-frame floor. Source inspection confirmed that frame admission requires
  both an admitting renderer and its bound custom view. This is an ownership
  boundary, not a scheduler failure: the pure scheduler cases remain in the
  focused test, while the typed adapter's real stale/accepted outcomes are now
  exercised by the existing test-gated AppKit smoke path after
  `bindToView` and window content attachment.

## Verification results

### Strict codec and retained model

- Focused JIT and Release AOT executions of `test/terminal_damage_test.dart`
  pass. They cover full and sparse capture, disjoint interval coalescing,
  copied ownership, all six cell columns, grapheme references, row metadata,
  ring-row rotation, clean no-op capture, exact resource/damage/row ordering,
  atomic topology rejection, full replacement, configured bounds, truncation,
  noncanonical offsets/counts, reserved fields, padding, colors, IDs, scalars,
  and width flags.
- `make test` passes: 86 Dart files are already formatted, whole-package
  analysis reports no issues, and the combined product suite completes with
  `dart_terminal tests passed`.
- `make runtime-source-check` passes with `tracked=165 native_sources=0` after
  staging the new source and test.
- The adjacent `dart_appkit` worktree and its bundled Dart SDK worktree remain
  clean; this subtask changes only the product repository.

### One-in-flight transferable outbox and exact ACKs

- The transfer envelope is a one-shot primitive list with fixed magic/version,
  exact pane/damage/resource generations, byte length, full flag, and one
  `TransferableTypedData`. The receiver validates all envelope scalars before
  materialization, materializes once, and cross-checks every duplicated scalar
  against the strict ADR-003 payload header.
- The outbox retains only three in-flight scalars and never the transferred
  payload. While one packet awaits ACK, 1,000 test mutations remain in one
  screen-owned dirty interval and every attempted publication returns no new
  transfer. Exact acceptance releases the packet; full-snapshot state clears
  only then, leaving changes made during the wait ready for the next delta.
- ACK decoding validates fixed count, magic/version, pane identity/generation,
  damage generation, byte count, and status/byte consistency. Malformed,
  wrong-pane, stale/future-pane, duplicate, stale/future-damage, and wrong-byte
  ACKs have distinct deterministic outcomes and cannot release the active
  packet. An exact renderer rejection closes the relationship and requests a
  full resync.
- Pane replacement releases old bookkeeping, restarts damage generation at one,
  and requires a full snapshot. Late ACK/port/deadline events from the retired
  pane are ignored. Port close, the exact active deadline token, and generation
  exhaustion close without blocking and force the next relationship to resync.
- Focused JIT and Release AOT executions of
  `test/terminal_damage_transfer_test.dart` pass, including a real direct
  `SendPort`/`ReceivePort` isolate round trip, delayed mutation, exact two-step
  full/delta application, all scalar corruptions, close/deadline/replacement,
  renderer rejection, and signed-generation exhaustion.
- `make test` passes with 90 formatted files, no analysis issues, and
  `dart_terminal tests passed` after the asynchronous transfer suite is added
  to the combined runner.
- `make runtime-source-check` passes after staging with
  `tracked=170 native_sources=0`; the adjacent `dart_appkit` and bundled Dart
  SDK worktrees remain clean.

### Newest-model frame scheduler and native outcome connection

- Applied damage revisions are retained in the render model in strict order,
  but frame work is represented by one boolean newest-model marker. A submit
  attempt builds one ephemeral value; a newer revision arriving during that
  build supersedes it before the native boundary. Backpressure and stale
  results retain the marker and rebuild later with a fresh frame generation.
- Native stale results carry the renderer's accepted-generation floor back to
  the scheduler. The next attempt advances above that floor without reusing or
  wrapping a signed generation. Accepted results validate both the exact frame
  generation and a nonzero submission token before advancing scheduler
  watermarks.
- Focused JIT and Release AOT executions of `test/frame_scheduler_test.dart`
  pass. They cover ordered missing-delta recovery, five-revision coalescing,
  two rounds of backpressure with rebuild, build-time supersession, 1,025
  applied revisions with one pending marker, idle polling, and terminal signed
  frame-generation exhaustion without wrap.
- `make test` passes with 92 formatted files, no analysis issues, and
  `dart_terminal tests passed`. The new suite is part of the combined product
  runner.
- M1/arm64 Developer JIT and Release AOT bundle builds, Dart-only bundle
  audits, and AppKit smoke integrations pass. The test-gated custom-view path
  seeds native frame 10, observes scheduler frame 1 as stale, then rebuilds and
  accepts frame 11 with a nonzero native submission token in both modes.
- `make runtime-source-check` passes after staging with
  `tracked=172 native_sources=0`; the adjacent `dart_appkit` and bundled Dart
  SDK worktrees remain clean.
