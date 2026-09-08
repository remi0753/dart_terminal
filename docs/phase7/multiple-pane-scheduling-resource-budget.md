# Phase 7 — multiple-pane scheduling and resource budget

- Status: in progress
- Started: 2026-09-08
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `multiple pane の scheduling/resource budget`
- Related: REN-09, PERF-02, RT-02, PTY-04,
  `docs/phase1/unmodified-dart-engine-hosting.md`,
  `docs/phase2/persistent-pane-lifecycle.md`,
  `docs/phase4/damage-frame-coordinator.md`,
  `docs/phase4/product-metal-surface-integration.md`, and
  `docs/phase7/native-tabs-split-layout-focus.md`

## Purpose

Bound aggregate live-pane resource admission and make render turns fair across
multiple panes. Prove with real AppKit, PTYs, Metal, and both supported runtime
modes that a 100 MiB output burst in one pane neither grows application-owned
queues without bound nor starves input and presentation in another pane.

## Background and confirmed starting state

- The preceding Close/Quit parent completed at terminal commit `84f84bc Verify
  Close and Quit across runtimes`. The terminal and adjacent `dart_appkit`
  worktrees were clean when this task started. `ROADMAP.md` was reread after
  that commit and this item is the first unfinished item.
- `TerminalApplicationStateLimits` bounds 32 windows, 64 tabs per window, and
  64 panes per tab, but does not bound total live panes. Restoration separately
  refuses more than 64 total panes. Live mutation can therefore create a state
  that its own bounded restoration format cannot accept and can multiply PTY,
  text-input, CoreText, Metal, and native-window resources far beyond the
  intended product budget.
- Each `TerminalLiveMetalSurface` coalesces its own newest damage and retains
  constant-size transfer/frame state, but each surface independently owns a
  zero-delay/retry timer. There is no window/application owner that guarantees
  round-robin service, one pending entry per pane, or a maximum number of
  expensive surface turns before yielding to AppKit and terminal input.
- The reusable PTY reactor already emits at most 64 KiB per output callback,
  processes at most eight read batches per reactor turn, wakes itself when work
  remains, and uses native read high/low watermarks. Terminal parsing remains
  synchronous for one bounded callback, while Metal damage capture/composition
  is deferred outside AppKit callbacks and is the missing cross-pane scheduling
  owner.
- Existing runtime traffic proves a 64-request worker IPC bound and a GUI close
  timer; resource stress proves stable native Window/View handle churn. The
  hierarchy suite proves four independent PTYs/Metal surfaces and exact cleanup.
  No current gate combines a 100 MiB real PTY burst with latency measured in a
  separate pane.

## Scope

- One application-wide live-pane admission bound aligned with restoration and
  downstream scheduling capacity. Refused creation must allocate no pane/session
  and consume no identity.
- A bounded shared pane-work scheduler with one registration and at most one
  pending entry per live pane, deterministic round-robin order, explicit
  per-event-loop-turn work/time budgets, delayed retry promotion, fault
  isolation, metrics, unregister, and shutdown.
- Adoption of that shared scheduler by all Metal surfaces in the multi-pane
  native hierarchy product path while preserving the existing single-surface
  automatic scheduler as the compatibility default.
- Developer JIT and Release AOT acceptance with two native tabs/four live
  panes, one 100 MiB PTY output burst, timed input/output in a distinct pane,
  newest-only rendering, bounded scheduler counters, clean PTY/Metal/text-input/
  native-handle/worker teardown, and identical content-free semantic summaries.

## Out of scope

- Moving the parser or renderer to new isolates, changing Dart Engine
  scheduling, or redesigning the reusable PTY event/acknowledgement ABI.
- A general process-wide CPU quota, operating-system memory-pressure handling,
  configurable pane limits, or per-user quality-of-service controls.
- 60/120 Hz display-link benchmarking, power profiling, multi-window soak, or
  the longer Phase 11 performance campaign. This task establishes bounded
  fairness and latency under the Phase 7 four-pane product graph.
- AppKit unit/integration/UI coverage unrelated to the multi-pane performance
  boundary; that remains the next ordered Phase 7 roadmap item.

## Dependencies and ownership

- `TerminalApplicationState` remains the sole hierarchy and pane/session
  admission owner. It must reject over-budget mutations before calling the pane
  owner or advancing identities.
- Every `TerminalLiveMetalSurface` continues to own its screen damage outbox,
  newest-frame marker, atlas pins, and native renderer domain. The shared
  scheduler owns only which registered pane callback may run next and when.
- A scheduled pane callback must be synchronous and bounded. Re-requesting
  during its callback adds only that pane's one pending identity at the tail.
  Exceptions are reported but cannot prevent other due panes from running.
- Surface disposal unregisters before releasing render resources. Scheduler
  disposal cancels its sole timer and rejects future admission/work without
  disposing pane-owned resources itself.

## Ordered subtasks

### 1. Application-wide live-pane resource admission

- Add one total live-pane limit aligned with the existing restoration cap and
  enforce it before `createWindow`, `createTab`, and `splitPane` allocate a
  pane/session or consume identity.
- Validate the aggregate bound and reuse it from restoration so live and
  persisted state cannot drift.
- Completion: model tests reach the exact bound through multiple windows/tabs,
  prove all three over-budget mutations are allocation-free and deterministic,
  prove capacity is reusable after removal, and pass focused/full checks before
  an independent commit.

### 2. Bounded round-robin pane render scheduling

- Add a shared scheduler with at most one pending record per registered pane,
  fixed pane/work/time caps, immediate and delayed requests, round-robin
  requeue, failure isolation, metrics, and exact cancel/dispose semantics.
- Allow `TerminalLiveMetalSurface` to delegate its immediate and retry work to
  the shared scheduler; keep local scheduling as the default. Adopt one shared
  owner in the four-pane hierarchy and verify zero registered/pending work after
  disposal.
- Completion: deterministic unit tests cover admission limits, coalescing,
  round-robin order, reentrant requests, delayed promotion, turn yielding,
  faults, unregister/dispose, and surface delegation; focused/full checks pass
  before an independent commit.

### 3. Cross-pane flood/input dual-runtime acceptance and parent completion

- Extend the existing hierarchy product fixture rather than duplicate its
  resource graph. Measure an idle-pane baseline and a second-pane response while
  a distinct pane emits exactly 100 MiB, requiring no more than 2x latency and
  positive scheduler yields without losing the flood completion marker.
- Require bounded scheduler registrations/pending/turn work, newest-only frame
  state, four clean PTY and Metal owners, zero text-input/native handles, and a
  reaped worker in Developer JIT and Release AOT. Update the runtime driver,
  README, feature evidence, full verification, roadmap child/parent, and commit.
- Completion: both modes emit the same exact semantic/count summary, all
  focused and aggregate checks pass, and no untracked Phase 7 work remains.

## Acceptance conditions

1. Live hierarchy creation never exceeds the same 64-pane aggregate accepted
   by restoration; refusal occurs before allocation or identity advancement.
2. Scheduler memory is proportional to the fixed admitted pane set: one entry
   and at most one pending identity per pane plus one timer, with no notification
   queue.
3. A continuously re-requesting pane cannot run twice before another already-
   due pane receives its turn. Work/time exhaustion yields back to the Dart
   event loop and increments explicit metrics.
4. A pane fault, delayed retry, removal, or stale callback cannot lose, duplicate,
   or indefinitely defer another pane's due work.
5. Under an exact 100 MiB burst, a separate pane's timed input-to-visible-output
   latency is no more than twice its same-launch idle baseline; both outputs and
   the final newest frame are observed without AppKit hang.
6. Final teardown leaves no PTY session, scheduler registration/pending work,
   atlas pin, text-input client, native handle, or runtime worker.

## Verification plan

- Focused application-state tests for the aggregate live admission boundary.
- Focused pure scheduler and live-surface tests with fake/manual turns before
  real native resources.
- Developer JIT then Release AOT hierarchy/fairness acceptance using real PTY
  output, AppKit event scheduling, Metal surfaces, and process cleanup.
- After each child: format/analyze, relevant direct tests, documentation and
  feature evidence, compatibility evidence regeneration when needed, complete
  `make test`, source audit, staged-diff review, and one child commit.
- Final child additionally runs the complete arm64 `runtime-verify` matrix.

## Investigation and decision log

- 2026-09-08: after commit `84f84bc Verify Close and Quit across runtimes`,
  `ROADMAP.md` was reread and this task was confirmed as the first unfinished
  item. README, FEATURE_MATRIX, hierarchy/application/session ownership,
  restoration limits, PTY native reactor budgets, damage outbox, newest-frame
  scheduler, live Metal surface timer ownership, metrics, runtime drivers,
  Make targets, tests, and both worktrees were inspected before code changes.
- 2026-09-08: unifying the live total-pane cap with restoration's 64-pane cap
  is selected over raising restoration toward the current theoretical
  32×64×64 hierarchy. One pane owns a PTY, parser/grid/scrollback, CoreText
  catalog/cache, glyph atlas, Metal renderer, text-input client, and native
  view; admitting the theoretical product is neither measured nor recoverably
  persistent.
- 2026-09-08: changing the reusable PTY ABI is not selected. Its native read
  and control fairness is already bounded, and each Dart callback contains at
  most 64 KiB. The missing cross-pane contract begins after parsing, where
  separate zero-delay surface timers have no shared order or turn budget.
- 2026-09-08: the task is split into three ordered children because live-state
  admission, reusable scheduling semantics, and real 100 MiB cross-pane
  measurement have independent failure modes and completion evidence. Later
  AppKit test work is not pulled forward.
- 2026-09-08: the first child adds `maximumTotalPanes = 64` to the live
  application owner and makes restoration reference that same constant. All
  three pane-producing mutations check capacity before allocating a session or
  advancing window/tab/split/pane identity; invariant validation independently
  rejects an impossible retained overage. The focused fixture fills 31 windows
  and 64 total tabs/panes, refuses new-window/new-tab/split paths without a
  factory call, removes one tab, and requires the replacement pane to use the
  immediately next identity.
- 2026-09-08: focused formatting changed only the new test layout. Focused
  analysis passed with zero issues and the direct application-state test
  completed successfully, including shutdown of all 65 session generations
  created before and after capacity reuse.
- 2026-09-08: complete `make test` passed every generated/freshness contract,
  formatting of 205 Dart files with zero changes, whole-package analysis,
  native-asset hooks, and the aggregate runner. Compatibility coverage remains
  nine fix families, 417 split runs, eight owned gaps, and zero known P0 silent
  corruption. The source audit passed with 388 tracked files, zero product
  native sources, and one reviewed test-native source; both repository
  worktrees are clean outside this child. The first child is complete and its
  roadmap item is marked before the task-local commit.
- 2026-09-08: after commit `3c74950 Bound aggregate live pane admission`, the
  roadmap and task record were reread. The bounded round-robin scheduler is now
  the first unfinished child; the flood acceptance and broad AppKit test item
  remain untouched.
- 2026-09-08: the shared scheduler uses one insertion-ordered pending set and
  one timer. A pane present at turn start is eligible once, while callback-time
  requests append to a later turn. The default limits admit 64 registrations
  and run at most four callbacks or four milliseconds per event-loop turn.
  Immediate requests can promote a delayed retry, counters saturate, callback
  and observer faults cannot stop peers, and unregister/dispose remove pending
  identities without taking ownership of pane resources.
- 2026-09-08: `TerminalLiveMetalSurface` now optionally registers its existing
  bounded `processPending` callback with that owner. All damage/outbox/frame/
  atlas state remains pane-local; only immediate/retry timer selection is
  delegated. The historical per-surface timer remains the default when no
  shared owner is supplied. The four-pane product hierarchy supplies one shared
  scheduler, requires four exact registrations, and proves hierarchy disposal
  unregisters every surface before scheduler disposal.
- 2026-09-08: the first focused format changed the new scheduler, surface,
  hierarchy, and test layouts. Analysis found only three unnecessary null-aware
  reads of the scheduler in the success path, where the non-null local owner is
  already in scope. Those reads now use that exact owner; no scheduler or native
  API type error was reported.
- 2026-09-08: after the nullability cleanup, focused formatting required no
  changes, analysis passed with zero issues, and the direct scheduler suite
  passed admission, coalescing, round-robin/reentrant order, delayed promotion,
  work/time yielding, callback and observer fault isolation, exact pending-work
  cancellation, unregister/dispose, and the one-timer automatic path. A final
  focused rerun after adding those two edge assertions again required no format
  changes, reported zero analyzer issues, and exited successfully.
- 2026-09-08: Developer JIT and Release AOT hierarchy launches passed with all
  four real Metal surfaces delegated to the shared owner, completing in 1944
  ms and 1180 ms. Existing focus/key/IME/Close/Quit assertions remained green,
  and teardown proved all four registrations and pending identities were gone
  before the scheduler was disposed. README and REN-09 now describe this
  substrate without claiming the later 100 MiB latency gate.
- 2026-09-08: compatibility coverage was regenerated after the README and
  feature-evidence edits and remained at nine fix families, 417 split runs,
  eight owned gaps, and zero known P0 silent corruption. Complete `make test`
  then passed freshness/compatibility/application/terminfo gates, formatting of
  207 Dart files with no changes, whole-package analysis, and the aggregate
  runner. The source audit passed with 389 tracked files, zero product native
  sources, and one reviewed test-native source. `git diff --check` passed and
  the adjacent `dart_appkit` worktree is clean. The second child therefore meets
  its acceptance conditions; the exact 100 MiB dual-runtime gate remains the
  next ordered child.
