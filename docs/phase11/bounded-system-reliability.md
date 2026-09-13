# Phase 11 — Bounded system reliability and duration follow-up

## Purpose

Prove that the ordinary macOS product preserves terminal state, owner identity,
render correctness, and bounded resources across sleep/wake, display-set
changes, and memory pressure. Replace duration-only 24/72-hour waiting in the
normal roadmap with deterministic bounded repetitions, while retaining the real
long-duration campaign as an explicit low-priority follow-up.

## Background and current position

- README, ROADMAP, FEATURE_MATRIX, the completed Phase 1 resource/fault work,
  Phase 7 screen migration/restoration work, Phase 10 display-preference work,
  and the Phase 11 performance gate were reread after commit `7d37503`.
  Product performance is complete; this reliability parent is now the first
  incomplete Phase 11 item. Sanitizer/fuzz/fault expansion, pinned parity
  burn-down, and the release-candidate program remain later work.
- ROADMAP's repository-wide policy explicitly classifies elapsed-time-only
  24/72-hour soak and long continuous use as low-priority follow-up. It permits
  omission or bounded deterministic substitution, but does not exempt a failure
  that reproduces quickly in correctness, safety, resource caps, or data loss.
- The clean adjacent `dart_appkit` revision is
  `a895dfbe446f83902f7d57a874151a9afcf3a957`. Its generic event protocol is
  version 14. It exposes per-window screen, backing-scale, frame, visibility,
  occlusion, fullscreen, and focus events plus current-screen resolution.
  It does not yet expose application sleep/wake, global display-set change, or
  operating-system memory-pressure events.
- Dart Terminal already treats `WindowScreenChangedEvent` and
  `WindowBackingScaleChangedEvent` as product inputs: window placement is
  clamped to an available display and every visible pane re-resolves layout/
  backing scale without changing PTY/session ownership. The existing Release
  AOT restoration acceptance injects a bounded screen migration and verifies
  tab convergence, scale, restored window geometry, eight PTYs, and teardown.
- `TerminalLiveMetalSurface` already suppresses hidden/occluded work, retires
  submissions before scale-atlas reset, requests a full screen snapshot after
  reset, and has bounded failure recovery. Scrollback, Kitty image storage,
  glyph atlas, shaping cache, parser inspector, queues, and resource owners all
  have hard limits, but there is no coordinated product memory-pressure policy.

## Scope

- Extend `dart_appkit` only with generic, application-neutral system-state
  observation: sleep/wake, global screen-set change, and bounded memory-pressure
  severity. No Dart Terminal name, policy, configuration, metric, or fixture may
  enter the generic repository.
- Inject those generic events into a Dart Terminal-owned controller that applies
  product policy to existing pane/session, renderer, placement, cache, and
  resource owners.
- On sleep: stop presentation deadlines/animation and invalidate transient
  interaction state without closing PTYs or changing canonical terminal data.
  On wake: re-resolve current screens/scales, rebuild or redraw newest state,
  and resume only visible/non-occluded owners.
- On display-set change: resolve each live native window from current AppKit
  screen snapshots, clamp windows whose display disappeared, converge all tab
  windows, rebuild scale-dependent resources once, and retain pane/session
  identity.
- On warning/critical memory pressure: synchronously bound admission, then
  perform staged owner-safe shedding outside the native callback. Drop only
  reproducible/transient caches first; never silently discard canonical screen,
  scrollback, selection, active preedit, PTY bytes, or unsent replies. A pinned
  resource or in-flight frame must defer rather than be invalidated.
- Add deterministic codec/controller unit tests and short repeated real-product
  Developer JIT/Release AOT acceptance with exact owner/resource baselines and
  content-free machine summaries.

## Out of scope

- Waiting 24 or 72 wall-clock hours, or claiming 30-day daily-driver evidence.
  The real duration campaign is retained under the major-goal follow-up section
  and is explicitly non-blocking by user direction.
- Programmatically putting the user's Mac to sleep, physically attaching or
  detaching a display, changing system memory limits, using private Apple APIs,
  privileged pressure injection, or disabling macOS safety/security settings.
- The next ordered sanitizer/fuzz/fault-injection expansion, compatibility
  parity burn-down, and release-candidate application program.
- Terminal-specific code or any identifier/path containing `terminal` inside
  `dart_appkit`. Product policy and test parameters remain in `dart_terminal`.

## Dependencies and architecture boundary

- Generic AppKit event transport owns only public macOS notification/source
  observation, versioned scalar encoding, stream lifetime, deduplication where
  the OS repeats an identical state, and test injection. It must remain useful
  to any macOS GUI application.
- Dart Terminal owns state transitions, pause/resume decisions, cache-shedding
  order, renderer refresh, window migration policy, privacy-safe diagnostics,
  repetition counts, timeouts, and acceptance thresholds. Those values are
  injected at the product boundary and never hard-coded in `dart_appkit`.
- Production uses `NSWorkspace` sleep/wake notifications, AppKit screen-set
  change notification/current `NSScreen` resolution, and public dispatch memory
  pressure flags. Tests inject the same typed generic events through the
  existing versioned event test boundary; synthetic events are never presented
  as evidence that physical hardware was changed.
- All application callbacks are observation-only and bounded. Product work is
  coalesced onto a later Dart turn so native callbacks never synchronously run
  renderer rebuild, PTY I/O, persistence, or bulk eviction.

## Ordered subtasks

1. **Contract, inventory, and duration boundary**
   - Freeze this memo, generic/product ownership, public-API constraints,
     duration follow-up, acceptance invariants, and ROADMAP subdivision.
   - Completion: documentation-only diff is internally consistent and
     `git diff --check` passes.
2. **Generic AppKit system-state event transport**
   - Add neutral protocol events and streams for power state, screen-set change,
     and memory pressure with native/Dart codec, malformed/legacy/dedup/lifetime
     tests, and the generic repository audit.
   - Completion: `dart_appkit` native and Dart gates pass; its filenames,
     identifiers, fixtures, and documentation contain no product terminology.
3. **Product sleep/wake and display recovery policy**
   - Coalesce injected generic signals, pause/resume presentation safely,
     re-resolve windows/scales, clamp missing displays, redraw newest canonical
     state, and preserve pane/session/input/selection/preedit ownership.
   - Completion: deterministic unit tests and both ordinary runtime modes pass
     bounded sleep/wake plus attach/detach-equivalent transitions with no stale
     frame or owner leak.
4. **Product memory-pressure shedding and recovery**
   - Define warning/critical stages over reproducible caches and renderer
     resources, reject unsafe pinned/in-flight reclamation, coalesce storms, and
     recover lazily from canonical data.
   - Completion: bounded pressure storms, allocation failure, in-flight frame,
     data-preservation, cap, and full-teardown tests pass.
5. **Bounded aggregate acceptance and parent closure**
   - Repeat the combined transitions for a fixed short count in Developer JIT
     and Release AOT, verify PTY/FD/isolate/GPU/native-handle baselines, update
     README/FEATURE_MATRIX/generated evidence, and close the parent while
     retaining honest duration limitations.
   - Completion: exact main gate, bounded aggregate product gate, worktree/audit
     checks, docs/matrix, and ROADMAP pass before sanitizer work begins.

Subtasks are strictly ordered. The actual duration campaign is not silently
marked as executed; it remains separately visible after the major goal.

## Invariants and acceptance contract

- Sequence numbers and owner generations are monotonic. Duplicate or stale
  generic events do not repeat product work or resurrect disposed owners.
- Sleep never closes a PTY, mutates canonical cells/history, submits a new frame,
  or leaves an animation deadline active. Wake publishes at most one coalesced
  recovery request and the first accepted frame uses current scale/viewport and
  the newest screen generation.
- A removed display cannot remain in persisted current placement. Every native
  window belonging to one tab group converges to the same clamped frame; an
  attached display does not move a window unless current policy selects it.
- Warning pressure may clear shaping/search/hover and unused atlas entries.
  Critical pressure may additionally rebuild fully reproducible render
  resources, but it cannot remove canonical terminal history or live Kitty
  image semantics merely to claim a lower resident value. If a resource cannot
  be reclaimed safely, the result explicitly reports deferred work.
- The pressure controller has fixed queue/event/generation bounds, never retains
  raw terminal content, paths, PIDs, timestamps, environment, or OS error text,
  and becomes inert after disposal.
- Each bounded product iteration proves one live window/tab/pane/session/Metal
  domain before the transition and exact zero application-owned resources after
  shutdown. Any quick failure remains a blocker even though elapsed-time soak is
  deferred.

## Verification plan

- Generic native header/bridge/runner tests, Dart event codec/API tests, analyzer,
  formatter, and `generic_repository_audit.dart --check` in `dart_appkit`.
- Product controller/cache/renderer/window-placement unit tests including
  duplicate, stale, malformed, storm, pinned, disposed, and recovery cases.
- Existing fullscreen/screen migration, scale rebuild, renderer recovery,
  resource stress, shutdown fault, performance memory/idle, restoration, and
  lifecycle regression suites.
- A short bounded real-product scenario in Developer JIT and Release AOT using
  injected typed equivalents plus current real screen resolution; it must not
  claim a physical sleep or cable operation.
- Exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, task-specific product
  Make gate, generated-artifact checks, `git diff --check`, clean worktrees, and
  adjacent generic audit.

## Progress log

### 2026-09-13 — Contract and inventory

- Confirmed the existing generic/product boundaries and selected a protocol
  extension instead of placing reusable macOS notification code in a
  terminal-specific library or placing product policy in `dart_appkit`.
- Kept system-event capture separate from product reaction. This allows the
  native bridge to remain neutral while Dart Terminal injects all reclamation,
  repetition, timeout, and acceptance parameters.
- Moved only elapsed-time evidence to a visible follow-up. Bounded transition,
  correctness, data-preservation, and resource checks remain mandatory in the
  normal Phase 11 order.

### 2026-09-13 — Generic AppKit event transport implementation

- Advanced the adjacent generic event protocol from v14 to v15 without changing
  the C ABI. Added application-scoped events for `willSleep`/`didWake`, global
  screen-set change, and normal/warning/critical public memory pressure. All
  records keep zero source identity, zero operation ID, and monotonic time; v14
  and older sinks reject the new event types before posting.
- The native observer uses `NSWorkspaceWillSleepNotification`,
  `NSWorkspaceDidWakeNotification`,
  `NSApplicationDidChangeScreenParametersNotification`, and a main-queue
  `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` source. Consecutive identical power and
  pressure values are deduplicated. Screen-set notifications remain distinct so
  the consuming product, rather than the generic bridge, owns coalescing.
- Observer replacement occurs before every event-port registration and teardown
  occurs before the event poster is disabled at bridge shutdown. No fabricated
  initial power, display, or pressure state is emitted. A test-only internal
  hook injects public dispatch flags into the same pressure mapping method.
- Dart exposes closed generic enums, strict v15 decoding, and typed application
  streams. The decoder rejects pre-v15 types, malformed lengths/enums, nonzero
  source identity, and nonzero operation IDs; it performs no product reaction.
- Focused verification first found two test-harness compatibility gaps: the
  encoder's former out-of-range protocol probe still treated newly valid v15 as
  invalid, and typed test subscriptions did not consume deliberately injected
  decoder errors. Both probes were updated without weakening production
  validation. Native bridge, shared encoder, Dart analysis, and Dart API tests
  then passed.
- The adjacent exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate
  passed after documentation and formatting. It covered the generic repository
  audit, header contracts, warnings-as-errors bridge/Runner builds, runtime and
  package analysis/tests, application builders/publishers, examples, and
  current/legacy FFI smoke. No duration-only test was needed for this transport.
- The first consuming-product exact gate then correctly failed analysis because
  its two exhaustive `AppKitEvent` switches did not yet enumerate the three new
  sealed event types. The legacy fixture and ordinary hierarchy now accept them
  explicitly without applying recovery behavior; this is the minimum transport
  compatibility change, while the next ordered subtask remains the sole owner
  of product sleep/wake and display policy.
- With those switches exhaustive, the next exact-gate run reached the generated
  Phase 7 AppKit acceptance freshness check and stopped because both recorded
  instances of the changed `terminal_application.dart` source hash were stale.
  This is expected provenance invalidation rather than a behavior failure;
  regeneration changed only those two reviewed hashes and did not change any
  criterion, fixture, or assertion.
- The repeated consuming exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed: all native
  capability suites, generated evidence checks, 319-file format check, analyzer,
  aggregate Dart tests, security stress, compatibility/differential/application
  matrices, distribution checks, and current dependency builds completed with
  exit 0. The adjacent implementation is committed at `bbc834b` with message
  `Expose generic macOS system state events`; its worktree is clean.
- This subtask is complete with transport only. The next ROADMAP item owns
  product sleep/wake and display recovery; memory-pressure shedding remains the
  following independent item.

### 2026-09-13 — Product sleep/wake and display recovery task start

- Re-read README, ROADMAP, FEATURE_MATRIX, this memo, the generic v15 event
  contract, native hierarchy projection, newest-frame scheduler, live Metal
  surface scheduling, and the existing Release AOT restoration acceptance.
  The first incomplete item remains product sleep/wake and display recovery;
  memory-pressure reclamation is deliberately left for the following ordered
  subtask.
- The implementation will remain entirely in `dart_terminal`. The completed
  `dart_appkit` layer already supplies application-neutral power and screen-set
  events plus each live `Window`'s current screen/backing scale, so this product
  policy requires no generic-library edit and introduces no product identifier
  there.
- A fixed-state product controller will retain only monotonic timestamps and
  pending booleans. It will coalesce native notifications onto a later Dart
  turn, reject stale transitions, become inert after disposal, and never retain
  terminal content or owner objects.
- The renderer contract will gain an explicit system-suspension state. Entering
  it pauses presentation/animation, cancels pending timers or shared-pane work,
  clears only transient hover state, and keeps at most the existing newest
  damage marker. Leaving it resumes only when the current window is visible and
  non-occluded, requesting exactly one full redraw from canonical state.
- Display recovery will read the current native screen/backing-scale snapshots,
  resolve a fresh main-screen fallback, clamp a placement only when its display
  is no longer represented, project every tab window in the logical group to
  one placement, and apply the resolved scale before layout. It must not create
  or close a pane, session, PTY, view, renderer domain, or native window.
- Unit acceptance will cover stale/duplicate/coalesced/disposed controller
  input, suspend/resume visibility semantics, deadline suppression, missing and
  unchanged display placement, tab convergence, and backing-scale projection.
  The existing bounded restoration product scenario will be extended in both
  Developer JIT and Release AOT modes with synthetic v15 transitions; this is
  evidence of product reaction, not a claim that the Mac slept or a cable was
  physically attached or removed.

### 2026-09-13 — Product sleep/wake and display recovery implementation

- Added a constant-space `TerminalSystemRecoveryController` in the product
  repository. Power and screen-set events retain only two last-observed
  timestamps, pending booleans, state flags, and saturating counters. One later
  Dart microtask coalesces synchronous native delivery after the callback
  returns; screen work remains pending while asleep, stale signals are rejected
  per source, and disposal makes an already scheduled callback inert.
- Wired the ordinary application to the controller without changing
  `dart_appkit`. Sleep cancels divider/context/hyperlink gestures, ends only the
  active selection drag while preserving its stable selected range, cancels
  autoscroll, and suspends every live Metal surface. PTYs, screen/scrollback,
  selection, preedit, pane/session identity, and native owners remain intact.
- Added an explicit system-suspension dimension to the newest-frame scheduler
  and live Metal surface. Suspension pauses the presentation and Kitty
  animation clocks, exposes no presentation deadline, cancels a surface timer
  or shared pane-scheduler request, refuses manual render turns, and retains at
  most the existing newest damage/full-redraw marker. Resume first publishes
  current visibility/occlusion and therefore restarts only presentable panes;
  the next accepted frame is a full redraw of the latest canonical revision.
- Display recovery uses each logical window's selected native tab as the
  authoritative current AppKit screen/scale and a freshly resolved main screen
  only as the no-screen fallback. The existing placement policy migrates or
  clamps the durable windowed frame, every native tab in the logical window is
  converged, and the chosen backing scale is applied to every pane before its
  layout. Attaching an unrelated display leaves an already valid placement
  unchanged. A later per-window screen/scale event remains authoritative if
  AppKit publishes it after the global notification.
- The restoration acceptance now injects the same generic v15 power and
  screen-set records used by production routing. It writes a marker through the
  real PTY while suspended, proves accepted-frame count and scheduled work stay
  unchanged, wakes, and requires the accepted renderer revision to equal the
  latest applied revision while retaining the exact pane/session/surface and
  tab-group geometry. Machine output contains counts only and never the marker
  or persistence path.

### 2026-09-13 — Product recovery verification and corrected trials

- Focused controller, frame-scheduler, native-hierarchy, selection-gesture, and
  autoscroll test runners passed. They cover later-turn ordering, duplicate and
  stale input, disposal, hidden/occluded resume, no build while suspended,
  newest full redraw, tab convergence, Retina scale projection, unrelated
  display attach, stable selection preservation, and deadline cancellation.
- An initial `dart test` invocation was unsuitable because this repository's
  tests are executable Dart scripts and intentionally do not depend on
  `package:test`; rerunning the same focused case with `dart run` passed.
  A formatter invocation also accidentally included this Markdown memo and
  failed parsing before code was affected. Subsequent formatter runs were
  limited to Dart sources.
- Two build-hook-backed focused tests were initially started concurrently.
  They raced on the shared `.dart_tool/lib` native-asset output, and one saw an
  incomplete non-Mach-O file. Both passed when rerun serially; native-asset
  tests in this repository must not share that output concurrently.
- The first real-product runs exposed that genuine AppKit screen-set events can
  precede the synthetic sequence. Absolute lifetime counters and small fixture
  timestamps therefore made the acceptance fail even though suspension,
  redraw, owner retention, and teardown were correct. The test now compares
  event/recovery deltas from a pre-sequence baseline and uses bounded positive
  monotonic timestamps above any practical machine uptime. No production
  policy or acceptance invariant was weakened.
- `make runtime-restoration-integration` passed in both Developer JIT and
  Release AOT. Each mode reported `system_recovery=true`; sleep admitted no
  scheduled/accepted frame, wake accepted the newest canonical revision, both
  restoration generations retained the required identities, all 16 real PTY
  sessions shut down cleanly, and final text-client/native-handle counts were
  zero.
- A later confirmation attempt twice reached the pre-existing fullscreen step
  with the application inactive and timed out before any injected system event.
  This did not reproduce in the prior complete Developer JIT/Release AOT run,
  did not execute the changed recovery path, and still cleaned the PTY, worker,
  text client, and native handles. It is recorded as a foreground-focus
  limitation of the fullscreen harness, not as sleep/wake evidence or a product
  recovery failure; no acceptance result from either incomplete run is counted.
- The exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed after
  regenerating only the reviewed Phase 7 source hashes. It formatted 321 files,
  reported no analyzer issue, passed all native/package/unit/security/
  compatibility/differential/application/distribution checks, and ended with
  `dart_terminal tests passed`. Full-source analysis and `git diff --check`
  also passed. No elapsed-time-only soak or physical sleep/display claim was
  used.

### 2026-09-13 — Product memory-pressure task start

- Re-read README, ROADMAP, FEATURE_MATRIX, this reliability contract, the
  generic v15 event transport, the ordinary application event switch, live
  Metal surface ownership, shaping LRU, CPU glyph/image atlas, native atlas
  bridge, failure recovery, and the existing restoration acceptance after
  commit `0b1e9c4`. The first incomplete ROADMAP item is product
  memory-pressure shedding/recovery; aggregate repetition and parent closure
  remain later work.
- The purpose is to admit warning/critical pressure in constant space during
  the generic callback, coalesce a synchronous storm to its highest severity,
  and perform owner-safe work on a later Dart turn. The implementation remains
  entirely in `dart_terminal`; `dart_appkit` already supplies the neutral typed
  pressure event and needs no product-specific edit.
- Scope is limited to reproducible or transient state: derived hyperlink
  hover, the bounded whole-run shaping LRU, and the CPU/native glyph plus Kitty
  tile atlas. Search does not retain a result cache in the current product, so
  there is no search allocation to clear. The canonical screen, scrollback,
  selection, active preedit, Kitty image stores/placements/animation state,
  PTY input/output, queued replies, panes, sessions, views, and windows are
  explicitly outside the shedding boundary.
- Warning pressure will clear hover and shaping entries and request an
  owner-safe atlas reclamation. Critical pressure uses the same data-preserving
  path but requires a complete reproducible atlas reset and full redraw. A
  submission/build pin or native backpressure must return a deferred result;
  the product keeps one pending severity and retries from an ordinary render
  turn instead of invalidating live resources.
- The controller retains only a last monotonic timestamp, one pending severity,
  one scheduled flag, and saturating content-free counters. It rejects stale
  input, treats lower/equal queued severity as coalesced, permits a later normal
  signal to close the pressure episode without recreating resources eagerly,
  reports failures through the existing asynchronous error boundary, and is
  inert after disposal.
- Completion requires deterministic controller storms/stale/dispose/failure
  tests; surface tests for shaping/hover reclamation, pinned deferral, lazy
  redraw, canonical Kitty/selection/preedit/screen preservation, resource caps,
  and teardown; both ordinary Developer JIT and Release AOT product acceptance;
  formatting, analysis, generated-evidence checks, and the exact repository
  gate. Wall-clock soak and privileged OS pressure injection remain out of
  scope and non-blocking by user direction.

### 2026-09-13 — Product memory-pressure implementation

- Added `TerminalMemoryPressureController` in the product repository and wired
  both the ordinary hierarchy and restoration acceptance to the existing
  generic v15 AppKit event stream. Native delivery records only the latest
  monotonic timestamp, highest pending severity, retry count, and saturating
  content-free counters. One later Dart microtask performs policy work; a
  same-turn warning/critical storm is reduced to critical, stale records are
  rejected, a normal record closes the episode without eager allocation, and
  disposal makes already-scheduled work inert.
- Callback/allocation failure is retried through the same single bounded slot.
  The attempt budget is fixed and validated in the range 1–16; exhaustion
  publishes one error through the application's existing asynchronous-failure
  boundary rather than growing a work or error queue.
- Extended `TerminalGlyphAtlas` with deterministic unpinned-resource
  reclamation. An active build lease defers the whole operation, native
  submission pins retain exactly their live entries, and independent unpinned
  entries are evicted in stable entry-ID order. The result exposes counts and
  released bytes only.
- Added owner-safe warning and critical stages to
  `TerminalLiveMetalSurface`. Both clear the reproducible shaping LRU and
  transient hyperlink hover. Warning reclaims unpinned atlas entries; critical
  resets the fully reproducible glyph/Kitty tile atlas at the current catalog
  generation and backing scale. Atlas work remains pending while suspended,
  without a current renderer domain, during a build lease, or while a native
  submission pin is live, and is retried from an ordinary bounded render turn.
- Successful shedding requests a fresh snapshot and full redraw. Resources are
  recreated lazily from canonical owners without replacing the Metal surface
  or renderer identity. Screen cells, scrollback pages, stable selection,
  active preedit, PTY state, Kitty image stores/placements/animation data, and
  queued protocol replies are never part of the reclamation operation.
- Extended the ordinary performance acceptance with real AppKit event routing,
  PTY/session/surface owners, warmed shaping/atlas resources, warning and
  critical storms, normal recovery, lazy accepted frames, exact canonical
  screen digest and scrollback allocation retention, active-preedit retention,
  identity checks, and atlas caps. Its driver now rejects a missing or duplicate
  content-free memory-pressure summary. The restoration scenario has the same
  canonical Kitty/preedit/screen checks, although its independent fullscreen
  prerequisite can require a foreground desktop before those checks begin.
- No file in `dart_appkit` changed for this subtask. All severity choices,
  eviction policy, retry budget, fixtures, diagnostics, and acceptance values
  remain injected or owned by `dart_terminal`.

### 2026-09-13 — Product memory-pressure verification and corrected trials

- `dart run test/terminal_memory_pressure_test.dart` passed storm coalescing,
  stale/unrelated/normal handling, three-attempt transient allocation recovery,
  two-attempt persistent failure exhaustion with one error, and disposed
  scheduled-work suppression. `dart run test/glyph_atlas_test.dart` passed
  active-build deferral, submission-pin retention, independent unpinned
  eviction, retirement, released-byte accounting, zero-owner cleanup, and its
  existing golden cases. Both are also included in the aggregate runner.
- The first ordinary performance run exposed a real reentrant hierarchy bug:
  an AppKit screen-set notification could call display recovery, whose pane
  resize callback recursively entered hierarchy reconciliation. Product display
  recovery now uses the existing reconciliation guard and refreshes presentation
  after leaving it. This short correctness failure was fixed rather than waived
  as duration-only evidence.
- The next acceptance trial incorrectly treated screen generation as canonical
  content identity. Memory shedding deliberately requests a full snapshot, so
  that generation must advance. The test now uses a content-only digest over
  dimensions, cursor, cell scalar/style/color/hyperlink data, and width flags;
  it proves unchanged canonical content without rejecting the required redraw.
- `CI=true DART_SUPPRESS_ANALYTICS=true make developer-jit-performance` and
  `CI=true DART_SUPPRESS_ANALYTICS=true make release-aot-performance` both
  passed. Each also passed its native-hierarchy fairness prerequisite, required
  exactly one memory-pressure summary, exercised warning and critical storms,
  accepted the lazy newest frame, retained canonical/session/surface owners,
  respected caps, and completed exact PTY/worker/native cleanup.
- A separate `make runtime-restoration-integration` confirmation stopped before
  the pressure sequence at its pre-existing real fullscreen activation step:
  the test window was not foreground and fullscreen remained inactive for its
  eight-second bound. The locked desktop could not be foregrounded through UI
  automation. The attempt cleaned all PTY/worker/native owners, but it is not
  counted as pressure evidence; the two ordinary real-product modes above are
  the executed product acceptance for this subtask.
- The first exact main-gate attempt stopped at the expected stale Phase 7 source
  hash for `terminal_application.dart`. Regeneration changed only the two
  recorded occurrences of that SHA-256. A following attempt correctly found
  one unformatted Dart source; the checker uses `--output=none`, so the file was
  then explicitly formatted and the two hashes regenerated once more.
- The final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed
  with exit 0: generated evidence, 323-file format check, analyzer, aggregate
  Dart tests, native capabilities, security stress, compatibility and
  differential suites, application matrix, shell/terminfo, and distribution
  checks all passed. `git diff --check` passed, the adjacent worktree is clean,
  and its independent generic repository audit passed with 140 paths and 139
  text files.
- No real operating-system pressure was forced, no physical sleep/display
  transition was claimed, and no 24/72-hour wall-clock soak was run. Those
  duration-only or privileged activities remain the documented low-priority
  follow-up and do not mask any reproducible correctness, ownership, teardown,
  or cap failure in the completed bounded checks.

### 2026-09-13 — Bounded aggregate and parent-closure task start

- Re-read README, ROADMAP, FEATURE_MATRIX, this memo, the ordinary product
  performance/restoration launchers, current-process resource sampler, runtime
  integration driver, bundle/resource gates, and the committed pressure and
  system-recovery controllers after commit `ffabaa0`. The final child of the
  reliability parent is now the first incomplete ROADMAP item; sanitizer/fuzz
  expansion remains strictly later.
- Purpose: execute sleep, screen-set recovery, memory pressure, redraw, and
  recovery together for a fixed short count in one ordinary product lifetime,
  prove stable owners/resources at every boundary and exact zero cleanup, then
  publish the bounded-vs-duration limitation in README/FEATURE_MATRIX and close
  the parent.
- Scope: extend the existing isolated performance product launch because it
  already owns one real AppKit window/view, PTY/session, Metal surface, runtime
  worker, process resource sampler, strict content-free driver, and exact
  teardown assertions. A separately named reliability Make gate will reuse the
  same launch rather than add another hidden product CLI mode or duplicate the
  owner graph.
- The combined scenario will use eight deterministic iterations. Every
  iteration queues sleep plus duplicate screen-set events, applies alternating
  warning/critical pressure while presentation is suspended, verifies no
  sleeping frame/deadline, wakes, waits for display recovery and one newest
  lazy redraw, returns pressure to normal, and checks canonical screen,
  scrollback, active preedit, window/tab/pane/session/surface/renderer identity,
  bounded queues/atlas, retired GPU submission pins, native-handle and text
  client baselines, and a live PTY.
- Current-process file descriptors are not presently part of
  `TerminalProcessResourceSnapshot`. The sampler will gain a bounded macOS
  descriptor-count query used only at settled aggregate boundaries. It will
  retain and emit only a count, not descriptor numbers, paths, sockets, or
  command data. Worker topology provides the isolate/process boundary: the
  AppKit root remains the same product isolate and the existing exact worker
  process contract must remain one start/ready/exit lifecycle.
- Out of scope: physical sleep, real display cable changes, privileged OS
  pressure injection, 24/72-hour waiting, resident-memory monotonicity, and
  Apple notarization. The deterministic typed events exercise the production
  routing and policy but will be described as bounded equivalents, never as
  physical or duration evidence.
- Dependencies: the committed generic v15 transport, product recovery and
  pressure controllers, live surface pin/cap snapshots, Phase 1 process/worker
  cleanup, and the existing Developer JIT/Release AOT application bundles.
  `dart_appkit` requires no edit; all repetition counts, fixtures, thresholds,
  and result strings remain in `dart_terminal`.
- Completion: descriptor-sampler tests, aggregate driver validation, both
  runtime modes through the named reliability target, exact main gate,
  README/FEATURE_MATRIX and generated Phase 7 evidence freshness, generic
  repository audit, clean reviewed worktrees, child and parent ROADMAP checks,
  and one completion commit. Any quick correctness/data/ownership/cap failure
  remains a blocker; only elapsed-time evidence is deferred.

### 2026-09-13 — Bounded aggregate implementation

- Added a content-free current-process descriptor count to the existing macOS
  resource sampler. It obtains the bounded descriptor-table size and applies
  `F_GETFD` without reading or retaining descriptor numbers, paths, socket
  addresses, or contents. A hard 65,536-descriptor scan ceiling fails closed
  instead of silently undercounting an unexpected table.
- Extended the ordinary performance product lifetime with a separate bounded
  reliability phase after its single warning/critical checks. It establishes
  one settled AppKit/PTY/Metal baseline, retains an active preedit, and performs
  exactly eight combined iterations. Even iterations use warning pressure and
  odd iterations use critical pressure.
- Each iteration sends sleep, two screen-set events, and two identical pressure
  events before wake. It waits until presentation is suspended and pressure is
  explicitly deferred, then proves accepted/build frame counts stay unchanged
  and no deadline remains. Wake must perform display recovery, apply the
  pending pressure stage, accept the newest redraw, retire every GPU submission
  pin, and accept a normal pressure recovery before the next iteration.
- Every settled boundary requires unchanged canonical screen digest,
  scrollback length/page/allocation, active preedit, window/tab/pane/session/
  surface/renderer identities, native window frame, live PTY, root/worker
  generation and worker PID, one outstanding worker process, AppKit handle and
  text-client baselines, exact file-descriptor baseline, empty pending queues,
  and atlas entry/byte caps. Existing ordinary shutdown then requires one clean
  PTY and zero Metal/text-client/native owners; the external driver also
  requires the exact worker spawn/reap contract.
- Added `developer-jit-reliability`, `release-aot-reliability`, and the public
  aggregate `runtime-bounded-reliability-integration` Make targets. The runtime
  driver requires one strict content-free eight-iteration marker per launch and
  prints one mode-specific reliability PASS. `runtime-verify` now includes the
  aggregate target.
- Updated README with the generic v15 event contract, product recovery/shedding
  semantics, new gate, verified resources, and the explicit bounded-equivalent
  limitation. Updated FEATURE_MATRIX `REL-01` from “sleep/soak later” to the
  completed generic/product/bounded coverage while retaining physical events
  and 24/72-hour elapsed-time evidence as low-priority follow-up.

### 2026-09-13 — Bounded aggregate verification and gate correction

- The descriptor sampler test opened and closed exactly one `/dev/null`
  descriptor and observed baseline, baseline+1, then baseline without exposing
  its identity. The focused product-performance test and static analysis passed.
- Initial individual `developer-jit-reliability` and
  `release-aot-reliability` executions both passed eight iterations, all
  per-iteration baselines, canonical retention, lazy redraw, and exact cleanup.
  Their existing hierarchy-fairness prerequisites also passed because the
  first Make aliases reused the full performance target.
- The first aggregate Make invocation passed the Developer JIT reliability
  sequence and the Release AOT reliability sequence itself, including teardown,
  but exited nonzero because the alias also imposed an unrelated performance
  p95 gate. That run measured key admission at 2.350 ms against the strict
  2 ms performance threshold; the preceding Release run measured 1.008 ms and
  passed. The reliability result was sound, but coupling its completion to a
  noisy independent latency sample was incorrect.
- Added a dedicated `reliability` driver suite. It launches the same ordinary
  product and retains all correctness, RSS/CPU sanity, queue/cap, resource,
  canonical, and teardown assertions, but does not claim or enforce the separate
  performance/fairness acceptance. The existing `performance` suite keeps its
  strict Release latency budgets unchanged. A subsequent output review also
  removed the misleading performance PASS from reliability-only runs.
- The final named
  `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-bounded-reliability-integration`
  passed with exit 0. Developer JIT completed its eight iterations in 7,535 ms
  and Release AOT in 6,524 ms; each emitted exactly one reliability PASS with
  sleep=8, wake=8, pressure=8, descriptor/root/worker/GPU/native baselines true,
  and canonical retention true.
- Phase 7 generated acceptance changed only the two recorded
  `terminal_application.dart` hashes. README/FEATURE_MATRIX then intentionally
  invalidated the compatibility coverage report; its regeneration changed only
  those two documentation SHA-256 values. The exact main gate passed after the
  reviewed regeneration and is repeated once more after final documentation and
  driver cleanup before ROADMAP closure.
- That final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` repetition
  passed with exit 0: all generated checks, 323-file formatting, analysis,
  aggregate Dart/native/security/compatibility/differential/application/
  distribution tests completed successfully. `git diff --check` remained
  clean. The adjacent `dart_appkit` worktree remained unchanged and its final
  generic audit again passed for 140 paths and 139 text files.
- The parent is complete under its documented bounded acceptance contract.
  Real 24/72-hour duration evidence remains visibly unchecked in the
  post-major-goal follow-up and was not used to claim physical sleep, display,
  or operating-system pressure coverage.
