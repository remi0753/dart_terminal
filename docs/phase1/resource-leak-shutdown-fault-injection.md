# Native/Dart resource-leak and shutdown fault injection

- Status: completed
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
     source/unit/integration checks pass within a dedicated bounded deadline.
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
   use the same acceptance assertions, and finish inside a bounded launcher
   deadline appropriate to each workload with valid completion diagnostics.
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
- A tight loop must stay within a declared app-launch deadline and periodically
  yield if the main-run-loop scheduler requires it, without admitting
  unbounded work. The general 12-second smoke deadline is not assumed to fit
  1,000 real `NSWindow` constructions.
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

### 2026-09-04 — event fault-injection seam decision

- The native Runner deliberately installs a typed `NativeEvent` poster whose
  encoder rejects invalid records before `Dart_PostCObject`. Making that
  production encoder emit malformed records would weaken its contract and add
  a second untyped native callback solely for tests.
- The Dart application already centralizes every delivered port message in
  `AppKitApplication._handleRawEvent`; unit fixtures inject into that exact
  method through a provided event stream. The smallest reusable integration
  seam is therefore a separate `package:dart_appkit/testing.dart` library which
  forwards a raw object to the same decoder/routing method and can reveal a
  window handle only to test code.
- Adding the seam to the main `dart_appkit.dart` export was rejected because
  raw events and handles are not production application concepts. Keeping it
  in an explicitly imported testing library avoids broadening the ordinary API
  while still compiling the exercised path into both product modes.
- A product fault run will create a temporary window, subscribe to its stream,
  save its generation-checked handle through test support, dispose it twice,
  inject a valid window-closed envelope for that disposed handle, then inject a
  non-list malformed record. It will observe one application stream error, no
  per-window late delivery, an unchanged native baseline, and successful
  worker-crash containment before closing normally.

## Failed attempts and corrections

- The first focused `dart format` invocation formatted its one changed file but
  then failed while Dart tried to update a telemetry session timestamp outside
  the permitted workspace. No product operation or dependency state changed.
  Subsequent Dart commands use the repository's `--suppress-analytics` form.
- The first Developer resource integration run proved all 1,000 handle pairs
  returned from `baseline=12` through `peak=14` to `final=12`, and final product
  cleanup reported zero. It nevertheless exceeded the general 12-second smoke
  deadline before the one-second auto-close could complete. The launcher then
  sent termination signals, which explains the observed forced worker cleanup;
  this was test-harness interruption rather than a leaked resource. The stress
  suite now records its inner duration and uses a dedicated 60-second hard
  deadline while all ordinary smoke/fault launches retain 12 seconds.
- The source-check rerun after both resource applications passed formatting,
  compilation, analysis, Dart tests, and diagnostics tests, but its final
  TerminalMetalView fixture could not create the registered Metal view and
  returned status 7. The same fixture had passed before the product stress run;
  this is being retried with the GUI/Metal execution permission used for app
  integration before it is classified as a product regression.
- The immediate permission-matched rerun of `make terminal-metal-view-test`
  passed. The earlier status-7 result is therefore recorded as a constrained
  Metal execution-environment failure, not a persistent product regression.
- The first adjacent `dart_appkit` `make dart-test` run reported an
  `unnecessary_import` because the new testing library was imported without a
  prefix in its own API fixture. Importing it as `testing` made the test-only
  surface explicit; the corrected run and the subsequent full dependency
  suite passed without changing runtime behavior.

## Implementation log

### 2026-09-04 — product resource stress path

- Added an integration-gated application option which cannot be combined with
  a lifecycle fault and is rejected on ordinary launches.
- The product root creates 1,000 invisible generic `View`/`Window` pairs,
  attaches each view, asserts exactly two temporary registry handles, destroys
  the window before the view, and asserts the exact native baseline after every
  iteration.
- Added machine-readable iteration, baseline, peak, final, and duration output.
  After all normal menus, session, main window, and content view are cleaned up,
  the gated run also asserts and reports zero live native handles before
  requesting host termination.
- Added one shared integration implementation plus Developer JIT, Release AOT,
  and both-mode Make targets. The launcher continues to validate worker PID
  reaping and private completion metadata for the stress invocation.

### 2026-09-04 — bounded shutdown fault injection

- Added `package:dart_appkit/testing.dart`, a deliberately separate test-only
  export with raw-event delivery and generation-checked window-handle access.
  The ordinary `dart_appkit.dart` surface and native ABI are unchanged.
- The reusable seam rejects detached/terminated applications and forwards into
  the exact decoder, application broadcast, weak owner lookup, cached-state,
  and owner-routing path used after native port delivery.
- Added dependency tests which dispose a window twice, inject its valid late
  close event, inject malformed non-list data, and then inject a valid
  application event. They prove no late owner delivery, one surfaced format
  error, and continued stream/state handling.
- Added an integration-gated terminal option tied to the existing
  `worker-unexpected-exit` scenario. The live product repeats the same late,
  malformed, continued-event, and double-dispose checks, asserts that its
  native handle baseline is unchanged, then crashes and reaps the official
  worker before ordinary application teardown.
- The main application event handler contains `FormatException` only while the
  explicit shutdown-fault gate is active. Other event errors and all ordinary
  launches retain the existing fail-closed behavior.
- Added one shared fault-suite implementation and Developer, Release, and
  both-mode Make targets. Each run requires the exact lifecycle sequence, zero
  final native handles, no stderr, bounded exit, worker PID absence, and valid
  completion diagnostics.

## Validation record

### Focused source checks

- `make runtime-source-check` passed Dart formatting, native formatting,
  lifecycle/diagnostics header compilation, plist lint, analysis, all Dart
  unit/lifecycle tests, runtime diagnostics native tests, and TerminalMetalView
  native tests.

### Product resource integration

- `make RUNTIME_ARCH=arm64 runtime-resource-integration` rebuilt both products
  from the clean pinned inputs and passed the same 1,000-pair suite in both
  modes after the deadline correction.
- Developer JIT observed `baseline=12`, `peak=14`, `final=12`, zero final
  product handles, 5,450 ms stress time, and 13,191 ms total application time.
- Release AOT observed `baseline=12`, `peak=14`, `final=12`, zero final product
  handles, 5,447 ms stress time, and 10,012 ms total application time.
- Both invocations spawned one official Dart worker with a distinct PID,
  observed its in-process reap, verified that PID was absent after app exit,
  emitted no stderr, completed within the dedicated 60-second deadline, and
  produced valid owner-only `root-stopped` local diagnostics metadata.
- The product resource-leak stress subtask is complete. The bounded shutdown
  fault-injection subtask remains next; no Phase 2 work has started.

### Reusable event seam

- `make dart-test` passed analysis, raw-event/late-owner coverage, every other
  Dart API fixture, and launcher tests before the dependency checkpoint.
- The reusable seam was committed in the adjacent `dart_appkit` repository as
  `52ddd2c` (`Add raw event testing hooks`).
- `make test` passed scaffold/header validation, all native bridge tests,
  Runner argument/shell/message-pump/event-encoder tests, Dart analysis/API and
  launcher tests, example analysis/Kernel compilation, real FFI smoke, and
  legacy event fallback after that commit.

### Product shutdown fault integration

- `make runtime-source-check` passed after the product changes: all formatting,
  C/C++ header checks, plist lint, Dart analysis/unit/lifecycle tests, runtime
  diagnostics native tests, and TerminalMetalView native tests.
- `make RUNTIME_ARCH=arm64 runtime-shutdown-fault-integration` rebuilt both
  products with dependency revision `52ddd2c` and passed the identical fault
  suite in both modes.
- Each run observed exactly one malformed error, zero disposed-owner late
  deliveries, one valid event after the malformed record, an idempotent double
  dispose, `baseline=12` and unchanged fault-local handle count, then zero
  handles after full product cleanup.
- Developer JIT contained/reaped the distinct-PID crashed worker and exited in
  1,211 ms. Release AOT did the same in 659 ms. Both emitted no stderr, stayed
  inside the 12-second deadline, left every recorded worker PID absent, and
  produced valid owner-only `root-stopped` completion metadata.
- The bounded shutdown fault-injection subtask is complete. M1/arm64 acceptance
  and Phase 1 closeout is now the first unchecked subtask.

### M1/arm64 final acceptance

- `make RUNTIME_ARCH=arm64 runtime-verify` passed the source checks, both bundle
  audits, normal smoke, all 16 lifecycle scenarios per mode, bounded traffic,
  the resource suite, and the shutdown-fault suite.
- Normal smoke completed in 2,229 ms for Developer JIT and 1,675 ms for Release
  AOT. Both modes passed all expected nonzero lifecycle outcomes as well as
  normal, contained worker-fault, replacement, late-completion, and
  double-shutdown outcomes.
- Bounded traffic passed in both modes with 384 explicitly backpressured
  requests. Developer JIT completed the traffic section in 1,052 ms and the
  application in 1,405 ms; Release AOT completed them in 972 ms and 1,179 ms.
- The repeated resource gate again passed 1,000 pairs with `baseline=12`,
  `peak=14`, and no drift. Developer JIT recorded 5,570 ms stress / 9,942 ms
  application time; Release AOT recorded 5,461 ms / 9,676 ms. Both reported
  zero handles after full product cleanup.
- The shutdown-fault gate again observed exactly one malformed error, no late
  owner delivery, successful continued event delivery and duplicate disposal,
  unchanged `baseline=12`, contained/reaped worker crash, and zero handles
  after cleanup. Developer JIT exited in 353 ms and Release AOT in 209 ms.
- `make RUNTIME_ARCH=arm64 developer-jit-clean-sdk-test` and
  `make RUNTIME_ARCH=arm64 release-aot-clean-sdk-test` passed from clean
  official SDK inputs. Developer JIT proved official-engine and
  source-inventory provenance, worker execution, rejection gates, 9 stable
  no-op cases, and 9 required regenerations. Release AOT additionally proved
  its self-contained signed worker and launcher rejection cases, with 19
  stable no-op cases and 19 required regenerations.
- Every product invocation stayed within its suite deadline, emitted no
  unexpected stderr, produced valid owner-only local completion metadata, and
  left every observed worker PID absent. The adjacent `dart_appkit` repository
  and official Dart SDK checkout remained clean after validation.
- README and feature-matrix status now describe the resource/fault gates. All
  three ordered subtasks and their parent roadmap item are complete; no new
  roadmap work was discovered, and Phase 2 has not been started.
- Final `git diff --check` passed. The root worktree review found only the four
  intended closeout documents pending this final commit; the adjacent
  dependency and official SDK worktrees were clean.
