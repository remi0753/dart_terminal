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

### 3. Bounded PTY/parser dispatch and Developer JIT flood regression

- Preserve the reusable PTY's 64 KiB default while adding a backward-compatible
  size-prefixed per-command delivery bound, and select 4 KiB for synchronous
  terminal parsing so one callback cannot monopolize the UI isolate for the
  observed 162 ms.
- Keep aggregate throughput bounded and prove the reusable PTY native/Dart
  suites plus the Developer JIT 100 MiB hierarchy gate before an independent
  prerequisite commit. Record the reusable package change in its worklog.
- Completion: one callback is demonstrably bounded below the measured input
  budget, PTY package/full terminal tests pass, and the Developer JIT flood
  response is no more than 2x its same-launch idle baseline.

### 4. Cooperative PTY batch turn yielding and full-matrix starvation regression

- Keep ordinary reusable PTY consumers on immediate ordered ACK, but let a
  command opt into acknowledging a synchronously consumed batch on a later
  Dart event-loop turn. Combine that option with the terminal's one-batch
  high/low watermark so the flood port cannot enqueue its successor before
  already-ready timers and other PTY ports receive service.
- Pin the public default/opt-in contract, timer-before-next-batch behavior, and
  lifecycle/cleanup semantics in the reusable package. Select the option only
  for terminal sessions and retain the existing native ABI, reactor, byte
  order, and bounded credit ownership.
- Completion: reusable PTY focused/full tests pass, repeated sequential
  hierarchy runs no longer reproduce the full-matrix Release AOT starvation,
  and the change is committed independently before returning to final evidence.

### 5. Cross-pane flood/input dual-runtime acceptance and parent completion

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
- 2026-09-08: after commit `86812b9 Schedule pane rendering fairly`, the clean
  worktree, roadmap, and this record were reread. The cross-pane 100 MiB
  flood/input dual-runtime acceptance is now the first unfinished item. Its
  scope is limited to extending the existing four-pane hierarchy fixture,
  enforcing the latency and bounded-state contract, updating its driver and
  evidence, and completing the scheduling/resource parent; the later general
  AppKit test task remains out of scope.
- 2026-09-08: the existing hierarchy fixture is selected because it already
  owns two visible sibling panes, two hidden-tab panes, four real PTYs and Metal
  surfaces, native text-input routers, a shared scheduler, a runtime worker,
  and exact Close/Quit teardown. The flood will be exactly 104857600 bytes of
  alternating `X` and carriage return, produced by bounded external pipeline
  output. This repeatedly damages one on-screen cell while keeping the legacy
  transcript line and scrollback bounded; NUL-only traffic was rejected because
  it would not exercise visible render work, and newline traffic was rejected
  because it would add irrelevant million-row scroll churn.
- 2026-09-08: the response metric starts at a scheduled event-loop deadline,
  routes a generated command through the pane's existing text-input router,
  and ends only after its distinct marker is parsed and a forced full snapshot
  containing that screen state is accepted by Metal. Three idle samples are
  taken in the same launch and their maximum is the conservative baseline; the
  flood sample must be no more than twice it and must complete before the flood
  marker. Dynamic microseconds and scheduler counters are separated from an
  exact content-free semantic summary so Developer JIT and Release AOT can
  share the same stable contract without pretending timings are identical.
- 2026-09-08: the first implementation extends only the hierarchy application
  path and its integration driver, raises that suite's outer timeout from 30 to
  120 seconds, and keeps every existing gate enabled. Focused formatting changed
  only the application layout; focused analysis reported zero issues and the
  aggregate Dart runner passed before launching native product acceptance.
- 2026-09-08: the first Developer JIT launch generated and drained the full
  flood and then cleaned all four PTYs, surfaces, text clients, native handles,
  and the worker, but exited 70 at the new compound fairness assertion. The
  measurement line was still located after that assertion, so the failing
  predicate could not be distinguished from the safe log. This diagnostic
  ordering is corrected before rerunning; no acceptance bound is weakened.
- 2026-09-08: the diagnostic rerun isolated the failure to latency: idle was
  23476 microseconds and flood response was 162070 microseconds (6.904x).
  Every other predicate passed: input completed before the flood marker,
  scheduler registration/pending peaks were 4, observed work was at most 4,
  yields advanced from 12 to 14, the flood frame advanced, and all per-pane
  frame queues stayed at one or less. Cleanup again reaped all resources.
- 2026-09-08: the failure shows the prior assumption that a 64 KiB native PTY
  delivery is a sufficient UI-isolate parser bound is false in Developer JIT
  for the repeated visible-cell workload. This newly required prerequisite is
  split into an ordered roadmap child before further implementation: tune only
  the reusable package's fixed read delivery unit (no ABI/queue/ACK change),
  verify its package contracts and the Developer JIT flood gate, commit it,
  then return to Release AOT and parent completion.
- 2026-09-09: repository ADR and Phase 0 evidence require burst deliveries of
  at least 64 KiB by default, so the global 8 KiB constant edit was rejected
  before commit. The adopted compatibility design appends `read_batch_bytes`
  to the existing size-prefixed ABI-v5 config. Old struct prefixes and zero use
  64 KiB; `PtyCommand` validates a consumer-selected 1..64 KiB bound; the
  terminal session selects 4 KiB. Ordered ACKs, high/low watermarks, native
  queue caps, reactor-turn count, and default throughput semantics do not
  change. Native tests cover default 64 KiB, selected 4 KiB, and an old prefix.
- 2026-09-09: the PATH `clang-format` was Chromium's checkout-dependent wrapper
  and exited before changing the adjacent native files. Xcode's concrete
  formatter is used instead; Dart formatting of the PTY API/tests and terminal
  consumer/acceptance required no changes.
- 2026-09-09: the first focused native run failed only because the new test
  incorrectly required an observed callback to equal 64 KiB. PTY reads may
  return less than their requested maximum, so default coverage now requires a
  positive callback no larger than 64 KiB. The result also means an 8 KiB cap
  need not reduce the platform's natural delivery; the terminal-specific cap
  is 4 KiB and the configured native fixture pins that bound.
- 2026-09-09: after correction, the warning-clean native contract passed along
  with package analysis and the first seven Dart PTY cases. The existing
  competing-reaper test then retained exit 37 but its race chose the normal
  reap path, so `firstWhere(externalReapObserved)` found no element. No changed
  line participates in reap ordering; the focused Dart suite is rerun once to
  determine whether this is the known nondeterministic system-reaper race.
- 2026-09-09: the immediate Dart PTY rerun passed all ten cases, including the
  exact external-reap diagnostic, without a source change. The assertion is
  retained. Focused package contracts and terminal analysis are now green; the
  512-byte consumer proceeds to the Developer JIT 100 MiB gate.
- 2026-09-09: the first 512-byte Developer JIT run still failed the unchanged
  latency gate at 168436 microseconds versus a 28246-microsecond baseline
  (5.964x); all other boundedness, overlap, yield, presentation, and cleanup
  predicates passed. Inspection showed the listener facade ACKed before its
  synchronous output stream delivered to the parser, allowing native credit to
  refill while Dart messages remained queued. ACK is moved after synchronous
  delivery and the terminal selects a 4 KiB high watermark with zero low
  watermark, so at most the current consumer callback is admitted. Other PTY
  consumers retain their existing default batch and watermark settings.
- 2026-09-09: warning-clean native and Dart PTY focused suites pass after the
  ACK/watermark correction. The Developer JIT hierarchy then passed the exact
  100 MiB gate in 16626 ms, including the 2x response bound, input-before-flood
  completion, positive scheduler yields, bounded scheduler/frame state, all
  prior hierarchy/IME/metadata/Close/Quit checks, four clean sessions/surfaces,
  zero text/native handles, and a reaped worker. The assertion is tightened to
  require the scheduler yield count to increase during the flood (not merely be
  positive from setup), and the integration summary now exposes content-free
  timing/yield values for the final confirmation rerun.
- 2026-09-09: the adjacent `dart_appkit` complete `make test` passed scaffold,
  bridge/Runner, message-pump/event, runtime/capability/renderer/PTY native
  contracts, all Dart package analysis/tests, launcher/Kernel, FFI, and legacy
  fallback gates after the backward-compatible PTY change. That prerequisite
  is ready for its own dependency-repository commit before the terminal child
  is finalized.
- 2026-09-09: the reusable PTY prerequisite was committed independently in
  `dart_appkit` as `b229bf4 Bound PTY delivery by consumer work`. The terminal
  roadmap and this task record were reread immediately afterward; bounded
  PTY/parser dispatch remains the first unfinished child. Its final tightened
  Developer JIT rerun passed in 16818 ms: the conservative idle baseline was
  25159 microseconds, the concurrent-flood response was 6049 microseconds
  (0.241x), and scheduler yields reached 32 after increasing during the exact
  104857600-byte flood. All existing hierarchy and cleanup gates also passed.
- 2026-09-09: terminal-side unit coverage now pins the 4 KiB default delivered
  to `PtyCommand` and rejects zero or larger-than-64-KiB session overrides.
  Focused format checked four changed Dart files with zero rewrites, focused
  analysis reported no issues, and the direct aggregate Dart runner passed.
- 2026-09-09: terminal `make test` passed all generated/freshness,
  compatibility, differential, application, terminfo, formatting of 207 Dart
  files, whole-project analysis, and aggregate runner gates. Compatibility
  evidence remains nine fix families, 417 split runs, eight owned gaps, and
  zero known P0 silent corruption. `make runtime-source-check` passed with 391
  tracked files, zero product native sources, and one reviewed test-native
  source. The terminal and dependency diffs pass whitespace checks, the
  dependency worktree is clean, and final diff review found no temporary
  diagnostic or unrelated file. This third child is complete; Release AOT and
  the final dual-runtime/evidence pass remain ordered next.
- 2026-09-09: after commit `415ea54 Bound PTY parsing between pane turns`, the
  clean terminal and dependency worktrees, roadmap, and this record were reread.
  The dual-runtime acceptance/evidence child is the first unfinished item.
  Release AOT passed the identical exact-flood hierarchy contract in 17031 ms:
  its same-launch idle baseline was 27557 microseconds, concurrent-flood
  response was 5607 microseconds (0.204x), and scheduler yields reached 455
  after increasing during the flood. Together with Developer JIT's 0.241x
  result, both supported runtime modes satisfy the stable semantic/count line,
  mode-local 2x latency gate, bounded scheduling/frame state, and full cleanup.
- 2026-09-09: the first complete `runtime-verify` invalidated that provisional
  conclusion by exposing an intermittent Release AOT starvation that the
  isolated launch did not reproduce. Developer JIT passed at 27600/8801
  microseconds (0.319x), but the immediately following Release AOT hierarchy
  measured 1022984 microseconds against a 23901-microsecond idle baseline
  (42.801x) and exited 70. Input still completed before the flood marker,
  scheduler yields advanced from 6 to 264, registrations/pending/work/frame
  state remained bounded, and teardown was clean. The failure is therefore a
  real latency blocker, not growth, marker loss, or cleanup failure. The parent
  and final child remain incomplete while native-listener/ACK event-turn
  fairness is investigated; no acceptance threshold is weakened.
- 2026-09-09: the first reusable-package cooperative-ACK test failed and
  sharpened the missing bound. It received 1025 callbacks with a natural
  1024-byte maximum before enforcing exact payload setup, and consecutive
  callbacks could precede the timer barrier: a 4 KiB byte high-water can hold
  several partial `read(2)` results. The compatibility config is extended once
  more with an opt-in native pause after each batch, while retaining both the
  original prefix and the prior read-batch suffix. Terminal sessions combine
  one native batch in flight with a later-event-turn Dart ACK; ordinary PTY
  commands retain immediate ACK and existing native read behavior.
- 2026-09-09: the corrected reusable native/Dart suites pass, but yielding
  every single native batch is too slow for the product gate. The first
  hierarchy attempt met fairness at 27502 versus 34428 microseconds (0.799x)
  and the 4 KiB nonblocking-read aggregation rerun met it at 8186 versus 25606
  microseconds (0.320x); both then exceeded the 120-second outer deadline before
  the remaining Close/Quit teardown scenario completed. Timeout termination
  caused the recorded status-23 child and destroy-status-3 cleanup errors; they
  occurred after the fairness summary and are not accepted as clean teardown.
- A maximum-four-callback Dart turn is the next bounded correction: native
  still admits only one batch, the first three consumer-completed ACKs resume
  one successor each, and the fourth ACK is deferred so another ready event is
  serviced before any fifth callback. Automated edit review rejected applying
  this interaction without explicit user approval due to potential deadlock
  risk. The cooperative child remains incomplete and both worktrees retain the
  documented, passing-package but throughput-blocked implementation.
- 2026-09-09: the user explicitly approved proceeding with the four-callback
  limit while requiring the adjacent package to remain general-purpose and
  opt-in. `PtyCommand.readBatchesPerEventLoopTurn` now uses zero as the unchanged
  default and accepts caller-selected limits one through eight. Only terminal
  sessions pass a nonzero value, currently two. Nonzero consumers receive one
  native batch in flight, immediate ACK for the first `limit - 1` completed
  callbacks, and a deferred limit-th ACK; package callers can independently
  choose fairness or retain prior throughput behavior.
- 2026-09-09: the first four-callback Developer JIT rerun restored throughput
  and met the latency gate at 27115 versus 26539 microseconds (1.022x), then
  exited 70 because pane teardown observed native destroy status 3. Inspection
  traced this to the reusable reactor's EOF condition: a final partial batch
  made in-flight bytes lower than the high-water mark even though its ordered
  ACK was still pending, so exit was published before `outstanding_` became
  empty and destroy correctly refused the handle. The current child now also
  requires exact outstanding-empty exit; cooperative delivery's existing
  read-paused watermark ACK supplies the required wake.
- 2026-09-09: after the outstanding-empty correction, all four sessions and
  native resources cleaned up exactly, but a subsequent Developer JIT sample
  measured 57337 microseconds against a 24357-microsecond baseline (2.355x).
  Four callbacks is therefore a valid package ceiling but not a sufficiently
  stable terminal selection. The product selects two callbacks per Dart event
  turn, still within the user-approved maximum-four design; the package keeps
  its caller-configurable zero-through-eight contract and unchanged zero
  default. This trades additional bounded turns for margin under the strict 2x
  gate without changing the 4 KiB parser batch.
- 2026-09-09: two consecutive dual-runtime samples with the terminal's
  two-callback selection passed the exact 100 MiB four-pane hierarchy and clean
  teardown. The first pair measured Developer JIT 27210/26221 microseconds
  (1.038x) and Release AOT 23723/25299 microseconds (0.938x); the second pair
  remained below the gate at 1.624x and 0.999x respectively. Every run observed
  the input before flood completion, positive scheduler yields, bounded
  registrations/pending/work/frame state, and four clean PTY/Metal owners.
- The adjacent package's complete `make test` passed warning-clean native
  capability coverage, every Dart package analyzer/test, AppKit and launcher
  coverage, and FFI smoke tests. The generic change was committed separately as
  `02a13d7 Schedule bounded PTY read turns`; its default remains zero and the
  terminal-specific value remains solely in this repository.
- Terminal `make test` passed compatibility, differential, application,
  terminfo, formatting of 207 Dart files, whole-project analysis, and the
  aggregate runner. `make runtime-source-check` passed with 391 tracked files,
  zero product native sources, and one reviewed test-native source. This
  cooperative-turn child is complete; final dual-runtime aggregate evidence
  remains the next ordered child.
