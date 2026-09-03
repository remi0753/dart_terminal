# Native/Dart resource-leak and shutdown fault injection

- Status: in progress
- Started: 2026-09-04
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1 exit conditions, ADR-001, ADR-002,
  `docs/phase1/handle-registry-domains-async-destruction.md`,
  `docs/phase1/vm-isolate-lifecycle-contract.md`

## Purpose

Turn the existing ownership and orderly-shutdown contracts into a product-level
stress gate. Both M1/arm64 runtime modes must prove that repeated Dart-owned
window/view lifetimes return the native registry to its baseline and that
malformed or late native events, duplicate disposal, and a crashed worker do
not hang the application or leave child processes behind.

## Background

The native registry already uses generation-checked handles, records the
AppKit-main destruction domain, rejects stale handles, and has a focused
1,000-generation native churn fixture. Dart wrappers make `dispose` idempotent,
and the shared product lifecycle suite covers worker crash, late worker
completion, double shutdown, forced termination, replacement, and final worker
reaping. The product hosts report live handles during final termination, while
the Dart `AppKitApplication` API can read the live registry count before
termination.

Those checks do not yet create and destroy 1,000 real window/view pairs through
the product Dart API, and the product integration suite does not inject a
malformed event into the live Dart event decoder. A host-only leak warning also
does not provide a positive, machine-readable before/after invariant for both
runtime modes.

## Scope

- Add an integration-only resource stress path which creates, attaches, and
  explicitly disposes 1,000 native window/view pairs through Dart.
- Compare the native live-handle count before and after every bounded stress
  run and after final product-resource cleanup.
- Add an integration-only event fault path for one malformed raw native event
  and one generation-valid late event addressed to an already disposed Dart
  owner.
- Exercise duplicate disposal and a contained worker crash in the same bounded
  fault suite.
- Require each invocation to exit within the existing deadline, reap every
  observed worker PID, preserve privacy-safe completion metadata, and pass in
  both Developer JIT and Release AOT.
- Keep every fault selector unavailable to ordinary application launches.

## Out of scope

- PTY, terminal grid/parser, renderer submission, GPU recovery, CoreText, and
  production multi-window policy from later phases.
- Process RSS or allocator-byte leak thresholds; this task uses authoritative
  native registry handles and operating-system process reaping.
- x86_64, Rosetta, Universal, and Intel-native reruns, which remain the existing
  low-priority follow-up after the M1 baseline.
- Long-duration 24/72-hour soak, sleep/wake, display migration, crash upload,
  symbolication, or user-consent workflows.
- Treating finalizers as the primary cleanup mechanism; the application must
  continue to dispose owned resources explicitly.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `a9f6dd3`, clean adjacent
  `dart_appkit` HEAD `c19071e`, and a clean official Dart SDK checkout.
- This is the first unchecked roadmap item. Phase 2 work must not begin before
  it is complete or explicitly recorded as blocked.
- `AppKitApplication.debugLiveObjectCount` is an existing main-thread API over
  `da_debug_live_object_count`; no new native counting mechanism is needed.
- `Window.dispose` unregisters Dart routing before releasing the native handle,
  clears its borrowed content-view reference, and is idempotent. `View.dispose`
  releases the separate registry lease.
- Native window-to-view attachment borrows rather than consumes the view
  handle. Correct loop cleanup therefore disposes the window and then the view.
- The native registry's focused 1,000-iteration fixture churns one text-view
  slot, but does not cover 1,000 product Dart `Window` plus `View` pairs.
- Malformed raw events are decoded into a `FormatException` on the application
  event stream. Unknown or disposed window owners are excluded from per-window
  delivery while application-level observation remains possible.
- Existing product lifecycle scenarios already provide contained worker crash,
  late worker completion, double shutdown, forced kill/reap, and replacement
  evidence. The integration launcher enforces a 12-second app deadline,
  verifies every observed worker PID is absent, and validates isolated local
  diagnostics metadata after each launch.
- The Developer host comes from `dart_appkit`; the Release host is terminal
  owned. Both link the same bridge sources and export the existing debug count.

## Task split and order

1. **Product resource-leak stress gate**
   - Add the gated 1,000-pair Dart churn path and machine-readable count.
   - Add the shared integration runner/Make targets for both runtime modes.
   - Complete when each run observes an unchanged native baseline, final
     product cleanup reports zero handles, all workers are reaped, and focused
     source/unit/integration checks pass.
2. **Bounded shutdown fault injection**
   - Add the smallest reusable raw-event injection seam needed for malformed
     and late-event product tests, with unit coverage and a normal-launch gate.
   - Combine malformed event, late disposed-owner event, duplicate disposal,
     and contained worker crash cases under the same shared mode-independent
     integration contract.
   - Complete when every case observes its intended fault exactly once, exits
     within deadline, reports zero final handles, and leaves no worker process.
3. **M1/arm64 acceptance and Phase 1 closeout**
   - Run source checks, dependency tests when its seam changes, both builds and
     audits, the same leak/fault suites in both modes, and relevant freshness
     checks.
   - Update product/feature documentation and close the parent roadmap item
     only after the evidence and final diff/worktree review are recorded.

The split is required because the native-resource stress contract and the
event-fault seam are independently reviewable deliverables, while the final
M1 matrix is an acceptance checkpoint that depends on both.

## Acceptance criteria

1. A gated product run creates, attaches, and destroys exactly 1,000 real
   `Window`/`View` pairs without showing them or changing production UI policy.
2. The live native registry count returns to the pre-loop baseline and does not
   drift at any checked iteration boundary.
3. After ordinary product cleanup and before host bridge shutdown, the Dart
   side reports zero live native handles; either host still treats a nonzero
   count as failure.
4. One malformed raw event is surfaced and contained without closing the event
   stream or blocking subsequent valid work.
5. One valid late event for a disposed Dart owner reaches no per-owner listener
   and cannot revive or mutate the disposed object.
6. Calling `dispose` twice performs only one native release and remains
   nonblocking.
7. A worker crash remains contained, is observed and reaped, and does not
   prevent native/Dart cleanup or application exit.
8. Fault options are rejected without the explicit integration-test gate.
9. Developer JIT and Release AOT execute the same stress/fault scenario list,
   use the same acceptance assertions, and finish inside the bounded launcher
   deadline with valid completion diagnostics.
10. All affected format, analysis, unit/native tests, builds, audits, clean-SDK
    gates, and final worktree/diff checks pass on M1/arm64.

## Validation plan

- Extend option and application tests for gate enforcement and deterministic
  resource/fault observations.
- Run the affected `dart_appkit` Dart/native suite if the reusable event seam
  changes, including malformed and disposed-owner routing fixtures.
- Run `make runtime-source-check` after each implementation slice.
- Build and audit both arm64 product bundles, then run the same dedicated
  resource and shutdown-fault integration targets in each mode.
- Run normal smoke/lifecycle/traffic regressions and focused clean-SDK
  freshness checks before final acceptance.
- Inspect native exported symbols/provenance if the reusable bridge changes,
  all staged diffs, both repositories, and the official SDK checkout.

## Risks and open checks

- AppKit may retain a content view through its window after the view registry
  lease is released. The stress loop must destroy the window owner first and
  assert at the registry boundary, rather than infer Objective-C retain counts.
- A tight loop must stay within the app-launch deadline and periodically yield
  if the main-run-loop scheduler requires it, without admitting unbounded work.
- A malformed-event test must observe the error deliberately; routing it to an
  unhandled stream error would test process failure rather than containment.
- A late event can be syntactically valid while its Dart owner is gone. The
  injection seam must preserve the event generation fields so the test covers
  routing, not merely decoder rejection.
- Test-only selectors and injection methods must be explicit, narrowly scoped,
  and unreachable from an ordinary launch.

## Investigation log

### 2026-09-04 — repository and contract review

- Re-read the repository rules, README, complete roadmap, feature matrix,
  Phase 1 exit conditions, ADR-001/ADR-002, lifecycle and handle-registry task
  records, current source/test/build inventory, and all relevant worktrees.
- Traced the Dart application ownership cleanup, native registry debug count,
  Developer and Release host termination checks, lifecycle coordinator process
  accounting, integration launch deadline/PID checks, and diagnostic metadata
  validation.
- Confirmed that current lifecycle coverage already supplies most shutdown
  process faults. Reusing those scenarios is preferable to creating a second
  worker supervisor or weakening their exact observation sequences.
- Selected native registry live-count stability as the leak oracle. Raw process
  RSS was rejected because allocator caches and framework initialization make
  it nondeterministic and it cannot identify an ownership-contract violation.
- Selected sequential invisible `Window`/generic `View` pairs for the required
  1,000-cycle gate. Repeated `TerminalMetalView` construction was rejected for
  this task because it would mix future Metal resource policy into an AppKit
  handle-lifetime acceptance test; custom-view attachment remains covered by
  the normal smoke suite.
