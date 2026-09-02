# Unmodified Dart Engine hosting migration

- Status: in progress; public-only child hosting rejected, option comparison next
- Started: 2026-09-02
- Scope: corrective Phase 1 task inserted immediately after the completed
  VM/isolate lifecycle contract
- Related: `ROADMAP.md` Phase 1, `FEATURE_MATRIX.md` RT-01--RT-03 and
  REL-01, ADR-001, ADR-002, `docs/phase1/vm-isolate-lifecycle-contract.md`

## Purpose

Remove the product's requirement to patch the Dart SDK checkout. Preserve the
accepted root/worker lifecycle behavior by using Dart in a form its maintainers
publish and support, even when that requires a less direct hosting topology or
additional product-owned integration code.

The migration is not complete merely when the two patch files disappear. A
clean, revision-pinned SDK checkout must build both product modes, individual
worker failure and shutdown must remain well-defined, and build provenance must
prove that no SDK source mutation was hidden elsewhere.

## Background

The preceding lifecycle task added two patches to
`runtime/engine/engine.cc` in the adjacent Dart SDK checkout. One installs the
VM isolate-initialization callback and platform script needed by
`Isolate.spawn`; the other adds VM-wide `Dart_Cleanup` during Engine shutdown.
They made the desired same-group worker lifecycle work, but they also changed
the semantics and ownership rules of an upstream helper library for a product
requirement that upstream has not accepted.

That trade-off is no longer accepted. The governing rule for this task is:

> Product needs do not authorize a product-only mutation of the Dart SDK. Use
> a documented public API or an official executable/tool boundary where one
> exists. Where `dart_engine` itself lacks a generally useful lifecycle
> facility, design and validate that change as an upstream Engine improvement,
> not as an undocumented permanent product patch.

## Scope

- Define an auditable boundary for supported Dart use.
- Test the least invasive official option first: one
  `DartEngine_CreateIsolate` call per execution domain, using an unmodified
  `dart_engine`.
- Require the prototype to cover creation, cross-domain request/reply,
  contained error, individual retirement/replacement, and final shutdown; a
  startup-only demonstration is insufficient.
- If multiple roots cannot satisfy that lifecycle through public ownership
  rules, evaluate a repository-owned embedder built only on the public Dart
  Embedder API.
- If the public embedding surface still cannot provide the required boundary,
  compare a general-purpose `dart_engine` API/implementation improvement with
  an official Dart executable in a child process with explicit IPC.
- Migrate developer JIT and release AOT to the first option that meets the full
  contract through an already published official boundary. An Engine change
  may be developed and proposed in parallel, but the product will consume it
  as an upstream revision rather than silently carrying a private fork.
- Remove patch files, patch application targets, patch-specific manifests and
  fingerprints, and all documentation that presents a patched Engine as the
  product contract.
- Prepare a minimal upstream report for any confirmed `dart_engine` capability
  gap, with a clean-SDK reproducer and without claiming that the product's
  preferred design must become a Dart language feature.

## Out of scope

- The next Phase 1 native-event wire-format task and all later roadmap work.
- Adding a new Dart language feature or maintaining a permanent downstream
  Dart fork. A general `dart_engine` API/implementation change with upstream
  quality, tests, and review material is explicitly in scope.
- Copying private Dart runtime implementation into this repository and calling
  it a public embedder.
- Sending an upstream issue, pull request, or code review before the local
  evidence and selected product fallback are complete.
- Weakening the already accepted observable lifecycle behavior only to make an
  otherwise inadequate hosting option pass.

## Dependencies

- The adjacent SDK is pinned at revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- The SDK working tree currently contains exactly the two product Engine patch
  effects; those changes are evidence under examination, not a permitted final
  build input.
- The existing JIT and AOT products share `bin/main.dart` and
  `lib/src/runtime_lifecycle.dart` but enter Dart through different native
  hosts.
- The root isolate must remain on the AppKit main thread. Worker execution must
  not monopolize that thread.
- `onExit` (or the selected topology's equally authoritative termination
  event) remains the worker completion boundary; an error notification alone
  is not proof that resources were released.
- The accepted build and Universal provenance machinery must be updated rather
  than bypassed.

## Supported-hosting policy

An option is considered supported for the product when all Dart-runtime calls
it uses are declared in installed public headers or the behavior is supplied
by an official Dart command (`dart run`, `dart compile`, or its produced
executable). Merely exporting an internal symbol from a dynamic library does
not make it a supported API. Product-owned scheduling, IPC, lifecycle state,
and native adapters are allowed; depending on private headers, copying VM
internals, or relying on stale private pointers is not.

Editing `dart_engine` is a valid design candidate when the change expresses a
runtime-embedding capability independent of Dart Terminal, preserves existing
API compatibility, includes upstream-level documentation and tests, and is
prepared for Dart maintainers to review. Until such a change is accepted in a
pinned upstream revision, it is evidence/proposal work rather than an accepted
product build dependency.

The order of preference is:

1. unmodified `dart_engine` with multiple root isolates;
2. a product-owned embedder using only public Dart Embedder API contracts;
3. a general-purpose `dart_engine` improvement suitable for upstream review,
   compared with process isolation using official Dart-produced executables
   and explicit product IPC;
4. the first presently published product path that meets the contract.

An upstream-quality Engine modification may be implemented and tested in its
own SDK checkout. It is not automatically permission to ship that unaccepted
diff as a hidden product prerequisite. If no presently published route meets
the contract, the dependent product feature remains blocked or uses the
process fallback until Dart exposes the accepted Engine solution.

## Ordered subtasks and completion conditions

### 1. Freeze the policy and comparison contract

Complete when this memo and the ordered roadmap items exist, the current SDK
state is recorded, and every later option is judged by the same acceptance
criteria. This subtask changes no runtime implementation.

### 2. Probe unmodified `dart_engine` multiple roots

Build a disposable, repository-owned probe against a clean SDK revision. It
must create at least two roots, prove scheduling and request/reply behavior,
exercise an uncaught worker-domain error, retire and replace one domain, then
perform bounded global shutdown. Inspect both documented API ownership and
runtime behavior. Record rejection as a valid completed result if any required
operation needs a private API, leaked/stale Engine bookkeeping, process exit as
cleanup, or an SDK edit.

Status: complete; rejected as the product's dynamic worker lifecycle, while
retained as a supported option for a fixed set of app-lifetime roots.

### 3. Probe a public-API product embedder if needed

First determine whether a product-owned host can initialize core libraries,
create the required isolate topology, schedule it, retire it, and call
`Dart_Cleanup` using public headers alone. Reject a design that quietly reaches
into `runtime/bin` or another private SDK component.

Status: complete; rejected for the product contract at the pinned revision.
The public low-level lifecycle is usable, but an Engine-owned VM cannot have
its child core-library initialization completed by the product through a
supported public hook.

### 4. Compare an Engine improvement with process isolation if needed

If the public-API host is insufficient, design the smallest general
`dart_engine` change that closes the confirmed gap, including compatibility,
ownership, shutdown, and upstream test requirements. In parallel at the design
level, prototype the minimum child-process control and data channel using an
official Dart-produced executable. Record the preferred long-term Engine API
and select a presently usable product path without conflating those decisions.

### 5. Migrate the product lifecycle

Move developer JIT and release AOT to the selected topology. Preserve the
semantic scenario inventory and stable outcome classes, while allowing wire
details internal to the runtime host to change. Do not retain a dormant patched
path as an undocumented fallback.

### 6. Remove patching and verify a clean SDK

Delete both patch inputs and every application, freshness, manifest, receipt,
or audit rule that assumes a modified Engine. Replace them with a fail-closed
check that the pinned Engine inputs are pristine. Run all focused lifecycle,
runtime, architecture, Universal, and Phase 0 regressions affected by the
hosting change.

### 7. Package the upstream evidence

Write a concise reproducer, expected/actual behavior, product-independent
motivation, proposed API/ownership contract, compatibility analysis, and tests
for the general Engine improvement. An implementation may be included and
validated in a separate SDK checkout. Keep submission as a local draft unless
a separate action explicitly publishes it. The task is complete when the
proposal can be reviewed and submitted without private project context.

## Acceptance criteria

1. The adjacent pinned SDK checkout is clean before and after every accepted
   build; no build step edits it.
2. No repository patch file, patch-application command, or patch-derived
   Engine-diff hash remains in the product build graph or provenance schema.
3. The selected path uses only the supported-hosting policy above and states
   who owns each isolate/process, scheduler, IPC endpoint, and teardown step.
4. Root UI execution remains AppKit-main-thread-bound and bounded; worker work
   runs outside that domain.
5. A worker can become ready, accept a request, stop normally, report an
   uncaught synchronous or asynchronous failure without killing the UI, and be
   replaced without retaining stale runtime ownership.
6. Graceful and forced shutdown are bounded, repeated shutdown is idempotent,
   late replies are harmless, and final VM/process cleanup has an authoritative
   completion signal.
7. Developer JIT and release AOT produce the same semantic lifecycle outcomes
   and stable exit classifications for the shared scenario inventory.
8. The arm64 baseline, x86_64 cross-build/Rosetta lane, Universal assembly and
   audits, affected freshness tests, and historical Phase 0 gates pass.
9. README, feature matrix, ADRs, task records, manifests, and audit messages no
   longer imply that a downstream Engine modification is required or endorsed.
10. Any capability Dart does not publicly expose is represented by an
    upstream-quality Engine proposal (and, where useful, implementation), not
    recreated through an undocumented product dependency.

## Validation strategy

- Start each option from the pinned SDK revision with `git status --porcelain`
  empty and validate that it remains empty after configure, build, and test.
- Use a small probe before changing product code, including negative and
  teardown cases under an outer timeout.
- Review public headers and official source documentation in addition to
  observing runtime success; accidental ABI availability is not acceptance.
- Run formatting, static analysis, unit tests, the shared JIT/AOT lifecycle
  suite, strict bundle audits, both thin architecture lanes, Universal
  assembly/integration, build-freshness regressions, and `phase0-verify` after
  migration.
- Inspect final source/staged diffs, generated artifacts, SDK status, manifest
  schemas, code-signing receipts, and repository secrets before completion.

## Risks and decision rules

- Multiple roots are explicitly within `dart_engine`'s creation purpose, but
  the current public Engine header exposes only global shutdown. Creating a
  second root is therefore not proof of safe pane-local retirement.
- Root isolates belong to separate isolate groups. Port messages may cross
  groups, but transferable values and error/lifecycle semantics differ from
  same-group `Isolate.spawn`; the product contract must be revalidated.
- The low-level Embedder API is public, but `dart_engine` currently performs
  some core-library setup through internal SDK helpers. A host that depends on
  those helpers would violate this task even if it links successfully.
- Modifying `dart_engine` can be the cleanest long-term result if isolate
  initialization and owned shutdown belong at that layer. The design must be
  justified for embedders generally and reviewed independently of this
  product's preferred topology; local success alone is not sufficient.
- Process isolation has the clearest crash and cleanup boundary but replaces
  Dart ports with explicit IPC and changes packaging, startup, buffering, and
  signing responsibilities. Those costs are acceptable only after the less
  invasive supported options fail.
- If no supported route satisfies pane-local recovery, correctness wins over
  the Phase 1 schedule: record a blocker and do not restore the patches.

## Multiple-root comparison and decision

The pinned, unmodified `dart_engine` genuinely supports multiple root isolate
groups. This is not an accidental symbol or an invented use: its README says a
caller may start one or several isolates, and the upstream
`run_two_programs_aot` sample demonstrates that path. The product probe extends
that evidence rather than disputing it.

The approach passes these parts of the contract:

- AOT and JIT can each create three independent roots from one snapshot.
- Simple Dart messages and 256 KiB `TransferableTypedData` chunks cross isolate
  groups correctly through public SendPort APIs.
- A worker-root uncaught callback reaches
  `DartEngine_SetHandleMessageErrorCallback` without killing the UI root; the
  same worker root can process another request afterward.
- A replacement root can be created and scheduled off the process main thread.
- Global Engine shutdown is fast and completes under the outer timeout when
  all created domains remain registered until that point.

The performance probe transfers 128 MiB as 512 acknowledged 256 KiB chunks.
Five direct repeats per mode produced:

| Mode | Transfer MiB/s | First root us | Worker root us | Replacement us | Global shutdown us |
| --- | ---: | ---: | ---: | ---: | ---: |
| release AOT | 3,361.70--3,737.44 | 527--3,770 | 277--513 | 303--322 | 41--79 |
| developer JIT | 1,248.43--1,446.97 | 31,829--37,238 | 30,188--31,277 | 30,184--31,268 | 284--461 |

Both transfer ranges exceed the 100 MiB/s gate. The earlier same-group Phase 0
probe measured 1,056.65--2,702.08 MiB/s, but its AppKit pump, instrumentation,
and workload differ, so this is only a no-bottleneck comparison and not a claim
that separate groups are intrinsically faster.

The approach fails the ownership part of the contract:

1. Closing the worker root's application `ReceivePort` makes
   `Dart_HasLivePorts` false, but does not release the root isolate.
2. `dart_engine.h` offers creation and global shutdown, but no individual root
   shutdown/unregister call and no authoritative individual-exit callback.
3. `Engine::StartIsolate` retains every root plus two persistent handles in
   private `isolates_`/`isolate_data_` structures. Only global `Shutdown`
   iterates that list; no public operation removes an entry.
4. Calling low-level `Dart_ShutdownIsolate` behind the Engine's back is not a
   valid composition. The caller cannot remove the Engine's persistent handles
   or stale vector/map entry, and the documented Engine acquire/release pair
   cannot bracket a call that destroys the current isolate. A later global
   shutdown would still try to enter the stale pointer.
5. Therefore pane close/restart would accumulate retired isolate groups until
   application exit, and a worker error supplies a diagnostic without the
   authoritative termination/replacement boundary required by RT-02 and
   REL-01. It would also invalidate the later 1,000 create/destroy leak gate.

Decision: do not migrate the product to the current multiple-root API. This is
a narrow lifecycle/ownership rejection, not a rejection of separate isolate
groups or their performance. A fixed number of roots that all live until
global shutdown is an intended use of the existing API; dynamic pane-owned
workers are not safely expressible. Proceed to the public low-level Embedder
API probe as ordered. The missing individual Engine lifecycle is also a strong
candidate for a general upstream `dart_engine` improvement.

## Investigation log

### 2026-09-02 — corrective task initialization

- Re-read `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, the lifecycle task
  memo, ADR-001, ADR-002, Engine patch inputs, runtime hosts, Dart coordinator,
  build targets, provenance code, and adjacent pinned Engine sources.
- Confirmed that the repository worktree started clean at commit
  `1f969e07b770a35de1b555a14114abbc70972688`.
- Confirmed that the adjacent SDK source is pinned at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` and has one modified file,
  `runtime/engine/engine.cc`, whose diff is the ordered result of the two
  repository patch files.
- The unmodified Engine API documents creation of one or several root
  isolates. Its implementation tracks roots in an internal vector and its
  public header exposes global `DartEngine_Shutdown`, but no per-root destroy
  or unregister operation.
- The low-level public `dart_api.h` exposes isolate initialization and
  `Dart_Cleanup`. The ordinary Dart runner installs isolate-initialization and
  cleanup callbacks, whereas unmodified `dart_engine` does not install the
  callback needed by the current same-group `Isolate.spawn` path.
- Symbol inspection of the built Engine library found public
  `Dart_Initialize`, `Dart_Cleanup`, and `DartEngine_*` entry points, but not
  the private `runtime/bin` core-library setup helper used internally by
  `dart_engine`. Export presence will not be used to broaden the public API.
- Registered this corrective task before the next Phase 1 item and split it
  into ordered, independently verifiable subtasks. No runtime code or SDK
  checkout has been changed in this subtask.
- Clarified from user direction that a principled change to `dart_engine`
  itself is allowed and must be considered. The prohibited outcome is an
  unexplained permanent downstream patch for product convenience, not Engine
  evolution backed by a general contract, tests, and upstream review.

## Validation log

### 2026-09-02 — policy subtask

- Reviewed the roadmap insertion and complete task memo against the repository
  work rules. `git diff --check` passed, and the worktree contains only the
  roadmap update and this new memo. Runtime sources and the adjacent SDK were
  not changed by this subtask.

### 2026-09-02 — multiple-root probe, first build attempt

- Reversed the lifecycle patch and then the worker-initialization patch only
  after both exact reverse checks passed. The adjacent SDK now has empty
  `git status --porcelain`, remains at the pinned revision, and its unmodified
  `runtime/engine/engine.cc` SHA-256 is
  `8834b16201a567040010545c90d209360bd88164cae477a85adafd126a38d370`.
- Rebuilt the Product ARM64 Engine directly through the SDK's GN/Ninja targets,
  bypassing the product Make targets that apply patches. The official
  `run_two_programs_aot` example then started two roots, passed a value between
  them through native code, printed the expected value, and completed global
  shutdown with status zero.
- Added a repository-owned probe for cross-group Dart ports, an intentionally
  uncaught worker-root callback, logical retirement, replacement-root creation,
  and global shutdown. Its first native compilation failed before linking
  because `dart_engine.h` intentionally uses GNU anonymous structs while the
  probe enables `-Wpedantic -Werror`. This is not an Engine defect and changed
  no SDK source. The probe build now uses the same two narrow warning
  suppressions as the existing product hosts and will be repeated.

### 2026-09-02 — multiple-root functional result

- The corrected probe passed against the unmodified Product ARM64 Engine. It
  created three separate root isolate groups, exchanged a ping/pong over Dart
  ports, delivered one intentional worker-root uncaught error to the Engine
  callback, processed another request in that root after the error, closed its
  application `ReceivePort`, created a replacement root, and exchanged a final
  ping/pong before global shutdown.
- All asynchronous Dart messages were handled on the probe's non-main scheduler
  thread. Timings for this run were 4,920 us for the first root, 1,198 us for
  the second, 713 us for the replacement, and 116 us for global shutdown.
- After logical retirement, `Dart_HasLivePorts` was false. Nevertheless, the
  public Engine header had no individual destroy/remove/shutdown operation and
  the implementation had no corresponding removal from `isolates_`; the
  retired root remained owned by the Engine until global shutdown. This is the
  central lifecycle gap to judge after adding a directly comparable bulk-data
  measurement.
- The runner verified the SDK was clean both before and after the build/run and
  enforced a 12-second outer timeout, zero exit status, empty stderr, and exact
  semantic markers.

### 2026-09-02 — dual-mode bulk result and option decision

- Extended the payload to perform an acknowledged 128 MiB transfer with
  per-chunk order, length, and edge-marker validation. The runner requires at
  least 100 MiB/s and exact lifecycle markers.
- Rebuilt both Product ARM64 AOT and Release ARM64 JIT Engine libraries from
  the clean source. The combined Make target passed in both modes: AOT reported
  3,311.34 MiB/s and JIT reported 1,425.61 MiB/s for that run. Five additional
  direct runs per mode all passed; the ranges are recorded in the comparison
  table above.
- Rechecked C++ formatting with the SDK clang-format binary, Dart formatting,
  source whitespace, the 12-second runner timeout, empty stderr, and Engine
  cleanliness. The SDK remained byte-clean at the pinned revision.
- Rejected the current multiple-root interface only because individual
  ownership cannot be completed through its public contract. No unsafe direct
  `Dart_ShutdownIsolate` experiment was used as product evidence: leaving
  private persistent handles and a stale Engine pointer would already violate
  the stated supported-hosting policy, regardless of whether one particular
  process happened to survive it.
- Final validation passed: Dart formatting reported zero changes, SDK
  clang-format reported no violations, `git diff --check` passed, repository
  `dart analyze` reported no issues, and `dart run test/run_tests.dart` passed.
  The final combined clean-Engine gate passed again at 3,392.17 MiB/s AOT and
  1,460.79 MiB/s JIT, with exact communication/error/replacement markers,
  bounded global shutdown, empty stderr, and a clean SDK before and after.

### 2026-09-03 — public lightweight-isolate API discovery

- The next option does not need to begin by replacing all of `dart_engine`.
  The public low-level header exposes `Dart_CreateIsolateInGroup`,
  `Dart_RunLoopAsync`, and `Dart_KillIsolate`. Together they allow a
  product-owned native adapter to create a child in the already initialized
  root group, invoke its Dart entry point, transfer its run-loop ownership to
  the VM with error/exit ports, and request immediate termination.
- This is not an inferred combination. The pinned SDK's
  `dart_api_create_lightweight_isolate_test.dart` and
  `ffi_test_functions_vmspecific.cc` use this exact public sequence through
  FFI: temporarily exit the current parent, create the child, re-enter the
  parent, then enter the child, invoke its entry point, call
  `Dart_RunLoopAsync`, and re-enter the parent. The test also supplies native
  shutdown/cleanup callbacks and Dart error/exit ports.
- Because an Engine message handler already holds the parent Engine lock while
  a Dart-to-native FFI call runs, that official temporary-exit pattern also
  prevents a concurrent Engine entry into the parent. The child itself is not
  inserted into Engine-private bookkeeping; the product adapter can retain its
  public `Dart_Isolate` handle, call `Dart_KillIsolate`, and use cleanup plus
  the Dart exit port as the teardown barrier before global Engine shutdown.
- This hybrid is now the concrete public-API probe. It avoids the two known
  full-embedder problems: the shared Engine library does not export the C++
  `dart::embedder::InitOnce` helper, and per-isolate
  `DartUtils::SetupCoreLibraries` remains a private `runtime/bin` API. No
  private helper is needed when the lightweight child shares the Engine-
  initialized root isolate group.

### 2026-09-03 — public lightweight-isolate probe, first build attempt

- Added a standalone dual-mode probe whose root remains owned by unmodified
  `dart_engine` and whose four lightweight children are owned by a
  repository-native adapter. The Dart side covers normal exit, fatal uncaught
  error, forced kill, replacement, off-main-thread execution, and an
  acknowledged 128 MiB `TransferableTypedData` path. The native side treats
  the cleanup callback, not merely the Dart error or exit message, as the
  permission to release each opaque handle.
- The first native compilation stopped before linking because `DART_EXPORT`
  already expands to C linkage in `dart_api.h`; the probe redundantly prefixed
  each exported FFI function with `extern "C"`, and `-Werror` promoted the
  duplicate declaration warning. This was a probe declaration error, not an
  Engine limitation, and changed no SDK file. The redundant prefix was
  removed before repeating the same gate.
- The next build linked the native AOT host, then the Dart AOT compiler
  rejected the source because it had only native-invoked entry points and no
  conventional `main`. Added an empty compilation entry point while retaining
  `vm:entry-point` annotations on the two functions invoked by name. This is an
  AOT artifact requirement and does not alter the worker ownership design.
- The first AOT execution created and started a lightweight child, but its
  ready event reported the main thread. `Dart_Invoke` runs a Dart entry point
  synchronously through its first suspension; the original async entry point
  created its port and sent ready before its first `await`. No payload work ran
  there. The probe next attempted to make the entry point schedule one
  microtask and return, so even initialization would occur after
  `Dart_RunLoopAsync` transferred the child to the VM-owned run loop.
- The attempted microtask handoff then failed at `Dart_Invoke` with the exact
  VM diagnostic `Unsupported operation: Microtasks are not supported`.
  Source inspection explains the difference from the SDK's official
  lightweight-isolate test: the ordinary Dart runner registers an
  `initialize_isolate` callback and calls private
  `DartUtils::SetupCoreLibraries` for each child, while unmodified
  `dart_engine` sets that callback to null and calls the helper only for roots
  created through `DartEngine_CreateIsolate`. The probe was narrowed to
  demonstrate the otherwise valid public lifecycle with synchronous port
  callbacks while retaining microtask unavailability as an explicit negative
  result; that subset cannot satisfy the product's existing asynchronous-error
  contract.
- A synchronous callback then completed the normal 128 MiB path and cleanup,
  but an intentional uncaught worker exception was replaced on the error port
  by another `Microtasks are not supported` error. The stack shows
  `_RootZone.handleUncaughtError` trying to schedule its priority error
  callback. Thus the initialization gap affects both ordinary async code and
  the accuracy of uncaught-error reporting; preserving only synchronous
  message throughput would weaken two existing acceptance conditions.

### 2026-09-03 — public lightweight-isolate option decision

The combined clean-Engine gate passed as an expected negative capability test
in release AOT and developer JIT. In both modes it created four children,
completed normal exit, observed a fatal worker exit, forced a spinning worker,
created a replacement, received all four native shutdown and cleanup
callbacks, released all four handles, retained no outstanding child, and
returned from Engine shutdown. All command callbacks and bulk work ran off the
main thread; only the deliberately minimal `Dart_Invoke` bootstrap ran on the
calling main thread.

The 128 MiB path measured 2,191.29 MiB/s AOT and 1,637.56 MiB/s JIT in the
combined run. Five direct repeats per mode all reproduced the same positive
lifecycle markers and the same two negative markers. AOT ranged from
3,091.86 to 3,179.41 MiB/s; JIT ranged from 1,528.07 to 1,695.21 MiB/s. Every
repeat reported four shutdown callbacks, four cleanup callbacks, four released
handles, zero outstanding children, microtasks unavailable, and loss of the
original fault diagnostic.

Decision: reject the public-only hybrid as the product path at this pinned
revision. `Dart_CreateIsolateInGroup`, `Dart_RunLoopAsync`, and
`Dart_KillIsolate` provide the desired ownership and teardown mechanics, so
the underlying Dart VM model is not the problem. The gap is specifically
`dart_engine` initialization: it owns `Dart_Initialize`, supplies no child
initializer, and exposes no supported way to install one later. Reimplementing
`DartUtils::SetupCoreLibraries`, reaching into private Dart fields, or limiting
workers to synchronous callbacks would each violate the supported-hosting or
existing lifecycle contract. The next ordered comparison must therefore judge
a general Engine fix against an official Dart process boundary.

### 2026-09-03 — public lightweight-isolate final validation

- Dart formatting reported zero changes, SDK-style C++ formatting reported no
  violations, `git diff --check` passed, repository `dart analyze` reported no
  issues, and `dart run test/run_tests.dart` passed.
- The final combined Make gate and all ten direct repeats required a clean SDK
  before and after execution. The adjacent checkout remained empty under
  `git status --porcelain` at the pinned revision; this subtask did not apply,
  generate, or consume an Engine patch.
