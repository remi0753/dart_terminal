# Handle registry thread domains and asynchronous destruction

- Status: completed
- Started: 2026-09-03
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, ADR-001, ADR-002, `dart_appkit` native
  object registry

## Purpose

Make native handle ownership enforceable rather than documentary. Every
registered object must carry a destruction thread domain, synchronous access
must validate that domain, and a release requested from another thread must
invalidate the handle once and complete native teardown on its owning domain
without blocking the caller or racing shutdown.

## Background

The current registry encodes a slot index and positive generation in each
64-bit handle and rejects stale or wrong-kind handles. It does not record a
thread domain and is not synchronized. All public AppKit operations guard the
main thread before lookup, while `NativeFinalizer` uses a separate best-effort
`dispatch_async` block. That finalizer path neither claims the handle before
enqueue nor exposes a reusable asynchronous-release contract. Two finalizers,
an explicit release, or shutdown can therefore enqueue competing work whose
ordering is implicit rather than represented by registry state.

ADR-001 requires a native handle to record its domain and generation, exactly
one release path, deterministic double-release/wrong-thread/use-after-shutdown
errors, and AppKit destruction on the main thread when release is requested
elsewhere. ADR-002 additionally forbids treating a handle value as permission
to call it from another thread or process.

## Scope

- Add an internal thread-domain identity to every registry slot. The only
  concrete product domain in this task is the AppKit main thread; the type and
  registry contract remain extensible for later render/font/PTY domains.
- Synchronize registry metadata so an off-domain release request can safely
  claim a live generation while main-thread access or shutdown is occurring.
- Model live, release-pending, free, and permanently retired slot states.
- Keep synchronous `da_release` main-thread-only and add an additive,
  any-thread asynchronous release API.
- Invalidate a handle when its async release is accepted, retain the native
  object until its domain executor runs, then perform window preparation and
  drop the registry reference on the AppKit main thread.
- Route `NativeFinalizer` through the same claim-and-complete path.
- Reject duplicate, stale, wrong-domain, invalid, and post-shutdown operations
  deterministically. Shutdown must own every accepted-but-not-yet-completed
  release and leave queued callbacks harmless.
- Retire a slot instead of wrapping its positive signed generation and making
  an ancient stale handle valid again.
- Add native churn, race, domain, deallocation-thread, and shutdown tests; keep
  Dart facade behavior and the current product lifecycle unchanged.
- Update consuming product provenance and both M1/arm64 runtime modes if the
  reusable bridge source contract changes.

## Out of scope

- The following generic `View`, focus, visibility, occlusion, backing-scale,
  and screen-event task.
- Introducing Metal, CoreText, PTY, render, or worker-domain objects and their
  executors before their roadmap positions.
- Changing window close into handle release, transferring a view handle when
  attaching it, or changing AppKit retain relationships.
- A public Dart API that permits worker processes or isolates to call AppKit.
- The later full native/Dart resource-leak and shutdown fault-injection task.
  This task adds bounded registry-specific churn/race coverage only.
- Changing the top-level C ABI or native-event protocol version for additive
  release functionality that does not alter an event record.
- x86_64, Rosetta, Universal, or Intel-native follow-up work.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `a56b2e6` and clean pinned
  `dart_appkit` HEAD `a70e5e4`.
- This is the first unchecked roadmap item. The later generic-view and broad
  leak/fault-injection items remain explicitly out of scope.
- Current handles use a one-based 32-bit slot index and a positive signed
  32-bit generation. Version-2 native events expose that generation from the
  high 32 bits, so domain metadata must remain registry-side rather than
  changing the accepted handle layout.
- Current registry access and native object release happen on the AppKit main
  thread. The finalizer callback may run on an arbitrary Dart runtime thread.
- `dispatch_async` to the main queue is nonblocking and is the existing AppKit
  domain executor. The queued block currently captures only the handle.
- `ShutdownBridge` runs on the main thread, stops accepting finalizers, then
  releases all live handles and clears the registry.
- An `NSWindow` may retain its content view after the view's registry lease is
  released. Registry destruction releases the handle lease; it does not claim
  ownership over independent AppKit retainers.

## Design decision

Use a mutex-protected registry state machine. A synchronous domain-owned
release validates and completes in one main-thread call. An asynchronous
request checks the shutdown admission flag, atomically changes exactly one
matching live slot to release-pending, and enqueues only its opaque handle.
Once pending, ordinary lookups and any second release reject the handle, while
the slot continues retaining the object and is not reusable. The main-queue
completion validates the same generation/domain, performs kind-specific
teardown, clears the strong reference, advances the generation, and only then
returns the slot to the free list.

Shutdown first closes admission and then enumerates both live and pending
slots. It performs all remaining AppKit teardown on the main thread and clears
the registry. A callback already queued before shutdown observes closed
admission and becomes a no-op, so it cannot access a cleared or subsequently
reused generation.

This is one coherent registry invariant rather than independent deliverables,
so the roadmap item does not need subdivision. The native state machine,
public additive entry point, finalizer routing, and tests must land and be
verified together; none is useful or safe to mark complete alone.

## Acceptance criteria

1. Every occupied slot records object kind, generation, and AppKit-main domain;
   lookup and synchronous release reject a mismatched requested domain.
2. A valid async request from a worker thread returns without waiting, makes
   subsequent lookup/release fail immediately, and keeps the slot counted and
   unreusable until main-thread completion.
3. Window preparation and the final registry-owned strong-reference release
   occur on the AppKit main thread. The same path is used by `NativeFinalizer`.
4. Concurrent async requests for one handle admit exactly one winner. All
   duplicate, stale, invalid, zero, and wrong-domain attempts return stable
   status and do not mutate another slot.
5. Shutdown rejects new requests, drains both live and pending handles on the
   main thread, and makes already queued callbacks harmless without a hang or
   use-after-clear.
6. A generation never wraps to an earlier valid value; an exhausted slot is
   retired and never reused.
7. At least 1,000 create/release/reuse iterations return the registry live
   count to zero and never make a stale handle valid.
8. Existing Dart `dispose`, double-dispose, finalizer attachment, event routing,
   and Developer JIT/Release AOT lifecycle behavior remain compatible.
9. Formatting, analysis, native/Dart tests, M1/arm64 builds, audits, relevant
   integration suites, clean SDK checks, and final diff/artifact hygiene pass.
10. The roadmap is checked only after accepted implementation and verification
    are recorded here, followed by task-scoped commits.

## Validation plan

- Extend native registry fixtures with domain mismatch, pending-state,
  concurrent claim, main-thread deallocation, shutdown race, stale-generation,
  and 1,000-iteration churn checks.
- Compile the public header as C11 and C++20 and run the full `dart_appkit`
  local suite, including real FFI and Dart facade compatibility tests.
- Run Dart Terminal source checks, both arm64 product builds and bundle audits,
  normal and lifecycle integration suites, and focused clean-SDK freshness
  checks when provenance changes.
- Inspect current and adjacent worktrees, generated SDK state, staged diffs,
  exported symbols, and final commits.

## Risks and open checks

- Returning an Objective-C object from a locked lookup must establish a strong
  local reference before another thread can clear the slot.
- Registry mutexes must never be held while AppKit teardown, dispatch, or event
  posting occurs.
- Pending slots must be included in shutdown enumeration but excluded from
  normal lookup and free-slot reuse.
- Thread-local diagnostics from an asynchronous callback are not observable by
  the requesting thread; admission errors must therefore be returned before
  enqueue, while completion is intentionally fire-and-forget.
- The additive symbol must be included in product source fingerprints so a
  stale bridge binary cannot satisfy a new build.

## Investigation log

### 2026-09-03 — repository and ownership review

- Re-read the repository rules, README, roadmap, feature matrix, Phase 1 exit
  conditions, ADR-001, ADR-002, current event-versioning record, repository
  inventory, and both clean worktrees.
- Traced all registry insertion, lookup, synchronous release, finalizer,
  shutdown, Dart `dispose`, and product integration paths.
- Confirmed that public AppKit calls correctly reject non-main callers but the
  registry itself has no domain metadata or synchronization.
- Confirmed that the existing finalizer schedules a later `da_release` without
  claiming the handle first. Its behavior is best-effort and safe in the common
  case, but duplicate and shutdown ordering are not represented by registry
  state and it cannot serve future domain-owned objects.
- Selected registry-side domain metadata to preserve the existing handle/event
  layout. Encoding domain bits into the handle was rejected because it would
  change the generation extraction contract introduced by the immediately
  preceding roadmap task.

## Implementation log

### 2026-09-03 — registry state machine and AppKit executor

- Added an AppKit-main thread domain to each slot and changed ordinary lookup
  to validate both the recorded domain and the current execution domain.
- Protected slot/generation/free-list/live-count metadata with one registry
  mutex. No AppKit method, dispatch operation, event post, or object
  deallocation runs while that mutex is held.
- Replaced the occupied bit with free, live, release-pending, and retired
  states. Accepted release claims move live to pending immediately; pending
  slots retain their object, remain counted, reject lookups and duplicate
  release, and cannot reenter the free list before completion.
- Added the any-thread `da_release_async` entry point. It claims a live AppKit
  handle synchronously, schedules completion on the main queue, and returns a
  stable shutting-down status after admission closes. `NativeFinalizer` now
  delegates to the same entry point.
- Synchronous release uses the same pending/completion state transition on the
  main thread. Window delegate/handle clearing and close preparation happen
  before the registry drops its strong reference.
- Shutdown closes async admission, includes both live and pending handles in
  its snapshot, completes their AppKit teardown on the main thread, and clears
  empty registry storage. Previously queued callbacks observe closed admission
  and do nothing. A monotonically increasing release epoch also prevents an
  old queued callback from acting on a numerically reused fixture handle after
  test-only bridge reset reopens admission.
- A slot reaching the largest positive signed generation is retired rather
  than wrapping to generation one.

## Failed attempts and corrections

- The first bridge patch orchestration referenced the wrong local script
  variable and stopped before invoking the patch command. No file was changed;
  the identical scoped patch was rerun with the correct variable and applied.
- The first documentation patch embedded Markdown backticks directly in its
  script template and failed JavaScript parsing before invoking the patch
  command. No file was changed; the command was rerun with a neutral placeholder
  converted to backticks inside the script and succeeded.
- The unused-API cleanup patch matched and removed the header declaration but
  missed the formatter-adjusted implementation context. The partial state was
  inspected immediately, the exact implementation block was removed in a
  second patch, and the focused native suite passed afterward.
- A combined final stage/check command was denied when the managed sandbox
  blocked creation of Git's index lock. It changed no repository data. The
  scoped task memo was then staged with explicit repository permission, and
  the checks were run separately.

## Validation record

### Focused native check

- `make native-test`: passed warning-as-error Objective-C++ compilation and all
  bridge contract tests after the initial implementation.
- New fixtures cover off-main and mismatched-domain lookup, immediate pending
  invalidation, main-thread deallocation, sixteen concurrent async claimers
  with exactly one winner, shutdown ownership of a queued window release, a
  harmless post-shutdown callback across reset and numeric handle reuse, and
  1,000 generations of slot churn.
- `make native-test` passed again after adding the release-epoch defense and
  its reused-handle regression fixture.
- Native and Dart format checks passed with zero changes, and
  `git diff --check` reported no whitespace errors.
- The final reusable-boundary `make test` run passed C11/C++20 header checks,
  warning-as-error bridge and Runner builds, registry/event/message-pump
  fixtures, Dart analysis/API/launcher tests, example Kernel compilation, real
  dylib FFI smoke, and the legacy-native fallback fixture.
- The native bridge suite passed 25 consecutive executions after its final
  concurrency changes. The built arm64 dylib exports all 18 expected `da_*`
  symbols, including `da_release_async`, which the real FFI smoke resolves.

### Reusable dependency checkpoint

- The reusable implementation and its tests/documents were committed in the
  adjacent `dart_appkit` repository as
  `9815e77e8a3a1e9f6c2958e03424eb1c78a62571` (`Enforce handle destruction
  domains`). The repository and official Dart SDK checkout were clean after
  that commit.
- Dart Terminal's existing build inventory already includes every changed
  bridge header/source and the clean `dart_appkit` Git identity. No fingerprint
  schema change is required; the dependency revision and source hashes force
  both product hosts to rebuild.

### Dart Terminal product

- `make runtime-source-check` passed Dart formatting, native formatting,
  lifecycle-header C/C++ compilation, plist lint, repository analysis, and
  unit tests.
- `make RUNTIME_ARCH=arm64 developer-jit-build release-aot-build` rebuilt both
  native hosts and bundles from clean `dart_appkit` revision `9815e77`. Both
  fingerprint v7 and manifest v9 generation paths passed with the official
  clean Engine/SDK evidence.
- Developer JIT and Release AOT bundle audits passed with arm64 slices, expected
  payload separation, strict ad-hoc signatures, and the exact clean dependency
  revision and changed registry source hashes in provenance.
- Normal integration smoke passed in 2278 ms for Developer JIT and 1671 ms for
  Release AOT. Both still observed the real version-2 native close event and
  completed handle release, worker collection, and process exit.
- All 16 lifecycle scenarios passed in both modes, including worker uncaught
  errors/exits, startup failure, replacement, shutdown timeout, late
  completion, double shutdown, root/host failures, and usage rejection.
- Bounded traffic passed in both modes with 384 backpressured admissions;
  Developer transferred in 1040 ms with 1380 ms application lifetime, and
  Release transferred in 979 ms with 1175 ms application lifetime.
- Developer clean-SDK freshness passed 9 stable no-op and 9 regeneration
  cases. Release clean-SDK freshness passed 19 stable no-op and 19 regeneration
  cases plus worker layout, executable, tamper, signature, launcher, and
  override rejection gates.
- The adjacent `dart_appkit` repository and official Dart SDK checkout remained
  clean after all builds, audits, integration suites, and freshness tests.

## Completion review

- All ten acceptance criteria are satisfied. Domain and generation checks are
  enforced in registry state, exactly one concurrent async requester can claim
  a handle, completion and object release stay on AppKit main, pending entries
  are shutdown-owned, reset-stale callbacks are epoch-rejected, and generation
  exhaustion retires rather than wraps a slot.
- Registry-specific 1,000-cycle coverage returns the live count to zero. The
  broader native/Dart leak and shutdown fault-injection roadmap item remains
  intentionally unstarted.
- Existing Dart dispose/finalizer/event behavior and all Developer JIT/Release
  AOT product suites remain compatible. No generic View, Metal, CoreText, PTY,
  menu, or other later-roadmap implementation was introduced.
- Final staged-diff inspection contains only this task's README, feature-matrix,
  roadmap, and task-record updates. There is no unstaged change; the adjacent
  dependency and generated SDK worktrees are clean.
- No additional roadmap item is required. The existing generic `View`, focus,
  visibility, occlusion, backing-scale, and screen-event task remains the next
  unchecked item.
