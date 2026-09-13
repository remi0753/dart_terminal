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
