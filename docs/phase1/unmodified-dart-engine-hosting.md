# Unmodified Dart Engine hosting migration

- Status: in progress; same-process Engine/AppKit integration selected
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
- The SDK working tree began this investigation with the two product Engine
  patch effects. It is now clean at the pinned revision; the repository patch
  inputs and build rules that can reapply them remain to be removed after the
  selected product migration.
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

This comparison is split before implementation because it has two independent
artifacts and a separate selection decision:

1. In a disposable SDK checkout, implement the smallest product-independent
   Engine correction, add an upstream-style regression to the existing
   embedder sample suite, and validate AOT/JIT without changing the pinned
   product checkout.
2. Build a repository-owned IPC probe around the official revision-matched
   Dart executable or a Dart-produced executable. It must exercise the same
   normal, error, forced-stop, replacement, and bulk-transfer boundaries.
3. Compare ownership, feature fidelity, performance, packaging, and dependency
   on unmerged upstream work. Select the presently shippable product path
   separately from the preferred long-term Engine design.

The first item is complete only when its implementation can explain every
changed Engine responsibility, passes the upstream embedder test route in AOT
and JIT, and leaves the product SDK checkout clean. The second is complete only
when no private SDK library or source is linked into the product side. The
third is complete only when the choice does not make an unaccepted Engine diff
a hidden build input.

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

### 2026-09-03 — Engine scope and history before improvement design

- `dart_engine` is a recent optional embedding helper, introduced on
  2025-01-28 by Dart SDK commit
  [`6e33c95463bd3bc71da5a35e571d6e8c596c4edd`](https://dart.googlesource.com/sdk.git/+/6e33c95463bd3bc71da5a35e571d6e8c596c4edd).
  Its initial regression route was `tests/standalone/embedder_samples_test.dart`.
  The samples cover root async work and multiple root snapshots, but no
  same-group child creation, so the missing child initializer had no test.
- The Engine README explicitly says the helper is not a full-featured API and
  describes starting one or several isolates *from snapshots*. That explains
  why `Isolate.spawnUri` and arbitrary group creation are outside its current
  scope. The same README also lists full VM/core-library initialization as an
  Engine responsibility. A same-group child created by `Isolate.spawn` or the
  public `Dart_CreateIsolateInGroup` inherits code from an Engine-created root;
  initializing its per-isolate core-library hooks is therefore a completion of
  that stated responsibility, not a new Dart language semantic.
- The public VM contract already models this operation through
  `Dart_InitializeParams.initialize_isolate`; the ordinary Dart runner has long
  installed that callback. The Engine passes null. The smallest general fix is
  to install an Engine-owned callback that invokes the same existing
  `DartUtils::SetupCoreLibraries` routine the Engine already uses for roots.
  No new public C API is required for child creation or termination.
- Shutdown is a second independent correctness issue. The Engine header says
  shutdown stops all isolates and frees all resources, while the implementation
  stops only roots it created, frees snapshot storage, and omits both public
  `Dart_Cleanup` and its paired embedder cleanup. Once children are supported,
  snapshot storage must remain alive until VM-wide cleanup has terminated any
  surviving child. Repeated shutdown must also avoid revisiting freed state.
- The upstream prototype will therefore test two behaviors together:
  microtask/async work inside a same-group child, and Engine shutdown while a
  second child still owns a live port. It will pair `Dart_Cleanup` with
  `dart::embedder::Cleanup`, clear owned containers, and make shutdown
  idempotent. It will not add `Isolate.spawnUri`, expose Engine-private child
  handles, or change Dart language/library semantics.

### 2026-09-03 — upstream prototype design before source changes

The prototype is intentionally limited to completing contracts that already
exist in the SDK:

- `CreateInitializeParams` will register an Engine-owned
  `initialize_isolate` callback. The callback will enter a Dart scope and call
  the existing `DartUtils::SetupCoreLibraries` helper with the same settings
  class used for Engine roots. It will not duplicate private Dart-library
  setup or add a new public API.
- Each Engine-created root group will use its Engine-owned `script_uri` as the
  VM's opaque isolate-group data. The child callback can then give
  `Platform.script` the same value as its parent. The pointer remains valid
  until after VM-wide cleanup because the Engine already owns and frees the
  snapshot record. This uses the public group-data lifetime contract instead
  of adding a second map or exposing the pointer to product code.
- Root setup will also pass `script_uri` to `DartIoSettings`; the current empty
  settings leave `Platform.script` incomplete even in the root.
- Shutdown will first prevent new message scheduling, then stop Engine-owned
  roots and delete their persistent handles. If the VM was initialized, it
  will call `Dart_Cleanup` while all snapshot code and group data are still
  valid; only then will it call the matching `dart::embedder::Cleanup`, unload
  AOT libraries, free snapshot buffers and URIs, and clear all containers.
- A one-way shutdown state will make repeated shutdown a no-op and make later
  initialization fail with an owned error string. Reinitializing the Dart VM
  in the same process remains outside the existing Engine contract.

The regression is added to the existing `run_futures` sample so the official
`embedder_samples_test.dart` route exercises it in kernel/JIT and AOT, with
both shared and static Engine linkage on supported host architectures. Dart
will (1) run a `Future.microtask` inside `Isolate.run` and return an exact
integer to native code, and (2) start a child with a permanently live
`ReceivePort`. Native code will require the exact result, shut the Engine down
while that second child is live, and call shutdown a second time. The expected
baseline failure is the current child-core initialization error; after the
Engine change all four sample variants must exit zero without a timeout.

The callback failure path follows the SDK runner's actual convention: it
returns a malloc-owned diagnostic after leaving its scope, and the VM's
lightweight-spawn path shuts the just-created isolate down. Although one
paragraph in `dart_api.h` says the callback owns that shutdown, the same API
implementation immediately performs it and both official runner callbacks
return false without doing so. Calling it inside the Engine callback would
therefore risk a double shutdown and is deliberately avoided.

The first formatting command used the conventional
`xcodebuild/ReleaseARM64/dart-sdk/bin/dart` path inside the disposable clone,
but that particular copied output directory does not yet contain a built SDK
executable. C++ formatting completed; Dart formatting did not run. This is an
environment-path mistake rather than a source failure. The source will be
formatted with the pinned adjacent SDK executable before the disposable output
is regenerated.

The replacement Dart formatter found the file already formatted, then exited
nonzero only because the workspace sandbox prevented it from updating Dart's
user-level telemetry-session timestamp. No source formatting failed. The
formatter check will be repeated with the already approved host access used by
the repository's other Dart validation commands.

### 2026-09-03 — regression-first baseline

- Added the regression only in the disposable SDK checkout and built the
  official Release ARM64 `run_futures_kernel` shared and static targets against
  the unchanged Engine implementation. The checkout copy required a full
  1,197-action rebuild because generated dependency timestamps no longer
  matched; the build itself completed successfully.
- Both executables completed all pre-existing future/stream checks, then exited
  with status 1 at the new exact assertion:
  `runInChildIsolate returned -1 instead of 512`. Dart deliberately maps the
  caught child-spawn initialization failure to `-1`, so this is a bounded,
  deterministic reproduction rather than a timeout or crash.
- The identical failure under shared and static Engine linkage establishes
  that the new upstream test fails before the proposed Engine source change.
  AOT will be built after the fix so the final four-variant matrix also checks
  tree shaking and precompiled child startup.

### 2026-09-03 — first Engine prototype run

The first Engine implementation compiled in both JIT linkage modes, but the
shared sample did not complete the new `Isolate.run` future within 40 seconds
and was interrupted. All five pre-existing checks still passed, and no child
initialization error was printed, so installing `initialize_isolate` removed
the original immediate failure but did not yet provide a complete scheduling
path. This run is not accepted. The next investigation will distinguish child
entry execution, child microtask completion, and delivery of the result back
to the Engine-owned root before changing the design.

Debugger inspection then localized the stall after the Engine child
initializer had completed successfully. The spawn worker was inside the
sample's `ScheduleDartMessage`, destroying the temporary `std::future`
returned by `std::async`; libc++ waits in that destructor. Its async task had
entered the root and was waiting for a group safepoint that included the
blocked spawn worker, producing a cycle. This is a sample scheduler defect
exposed by the new child path, not another child-initialization failure. The
existing timer messages happened after the root was released and therefore did
not expose it. The regression sample will use a queue-backed scheduler thread,
matching the API requirement that the callback schedule work without
synchronously waiting for it.

Final lifecycle review found one related pre-existing lock leak in
`Engine::NotifyMessage`: if `TryLock` succeeded after `is_running_` became
false, the combined condition returned without releasing `engine_lifecycle_`.
The prototype separates those checks and explicitly unlocks the successful
late-notification case. This matters once shutdown is idempotent and later API
calls are expected to fail cleanly rather than block.

The first direct invocation of the newly built `xcodebuild/ReleaseARM64/dart`
to run `embedder_samples_test.dart` exited 255 with `Unable to locate the Dart
VM executable`. The `dart` target is the dartdev launcher and expects the VM in
an SDK layout; it is not itself the standalone VM executable required by this
test. Inspection identified the standalone `dartvm` target, which was then
built and used for the successful official test-suite run recorded below.

### 2026-09-03 — general Engine improvement result

The isolated prototype now satisfies the proposed Engine contract without
adding a Dart language feature or a product-only API:

- Engine registers the existing VM `initialize_isolate` callback and applies
  the same `DartUtils::SetupCoreLibraries` routine to same-group children.
  Engine-owned group handles map to the parent snapshot URI, while groups
  created independently through `dart_api.h` safely receive default settings
  rather than having their opaque group data reinterpreted.
- Root and child `Platform.script` values are initialized consistently. The
  regression checks this inside an actual `Isolate.run` child after both a
  zero-delay future and a child microtask.
- Engine shutdown is one-way and idempotent. It shuts tracked roots, invokes
  `Dart_Cleanup` to terminate a still-live same-group child, then performs the
  paired embedder cleanup, unloads AOT snapshot libraries, frees buffers/URIs,
  and clears all retained containers. A late message-notification lock leak is
  also fixed. Reinitialization after shutdown returns a malloc-owned error.
- The `run_futures` sample now has a genuinely asynchronous queue-backed
  scheduler. This removes the `std::async` temporary-future wait cycle found by
  the debugger and is required for the spawn regression to be valid.

Validation in the disposable checkout at SDK base
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`:

- Release ARM64 JIT shared and static samples: exit 0, exact child result 512,
  matching `Platform.script`, live-child shutdown, second shutdown, and
  post-shutdown initialization rejection.
- Release ARM64 AOT shared and static samples: the same checks passed.
- Product ARM64 AOT shared and static samples: the same checks passed.
- Five consecutive executions of each of those six binary configurations
  completed successfully before the final lock-review adjustment; the full
  official route and both Product variants passed again after that adjustment.
- `xcodebuild/ReleaseARM64/dartvm
  tests/standalone/embedder_samples_test.dart` passed, covering every existing
  Engine sample plus the new kernel/AOT, shared/static regression variants.
- Dart format, SDK-style clang-format, and `git diff --check` passed. The final
  six-file candidate diff SHA-256 before its isolated commit is
  `8d98a31a2042df252f0da55536150a20a46ddc75407fd35ef98acd0751286e00`.

This proves that a coherent upstream Engine correction is technically viable.
It does **not** authorize the product to ship this unaccepted source delta: the
fixed product SDK checkout remains untouched. The ordered comparison must
still prove the official Dart executable/process fallback and account for the
time until any Engine change is reviewed and released.

The candidate was committed only inside the disposable SDK checkout as
`28462f0fb37` (`Complete Dart Engine isolate lifecycle`). Its parent is the
pinned clean SDK revision, its post-commit worktree is clean, and the commit's
diff SHA-256 matches the value above. This preserves an auditable upstream
candidate without altering or patching the product SDK.

Repository closeout for this comparison subtask also passed `git diff
--check`, `dart analyze` with no issues, and `dart run test/run_tests.dart`.
The only repository changes are this decision record and the ordered roadmap
state; no runtime source, build rule, product SDK file, or patch artifact was
changed.

The first repository commit attempt was blocked before staging because the
workspace sandbox denied creation of `.git/index.lock`. No index or worktree
content was changed by that attempt. The same narrowly scoped add/commit will
be repeated with Git metadata write access.

### 2026-09-03 — process/IPC fallback design before implementation

Purpose: determine whether the currently published Dart toolchain can provide
the required dynamic worker ownership without any Engine change while keeping
the AppKit/root process independent.

The probe has the following bounded design:

- Developer JIT launches the selected, revision-matched official `dart`
  executable with the probe source and `--worker`. Release AOT uses `dart
  compile exe` on that same source with a compile-time self-exec flag; the
  resulting official Dart-produced executable launches itself with
  `--worker`. Neither mode links `dart_engine`, a VM library, a private header,
  or an SDK source file.
- The supervisor owns the child `Process`, its stdin/stdout endpoints, stderr
  capture, and the authoritative `exitCode` future. The worker owns only its
  command loop. A process exit, rather than an error message, is the resource
  release boundary.
- Binary stdio IPC uses a small fixed header (message type, request/sequence
  id, payload length) and bounded 1 MiB frames. Protocol logging stays on
  stderr so stdout remains exclusively framed. This probe framing is local to
  the hosting comparison and does not pre-implement the later product
  native-event versioning task.
- The positive path requires ready, ping/pong, ordered and marker-validated
  128 MiB transfer, graceful stop acknowledgement, and exit zero. Negative
  paths require an intentionally uncaught worker exception with preserved
  stderr and nonzero exit, an unresponsive worker terminated with `SIGKILL`,
  and successful replacement after each failure.
- The runner imposes an outer timeout, validates exact semantic markers and
  empty supervisor stderr, builds/runs both JIT and AOT, and records startup,
  bulk throughput, and termination classifications. A threshold is not chosen
  until the first measurement; the comparison will report the measured cost
  rather than weakening the existing lifecycle semantics to meet a number.

Out of scope for this probe are product bundle placement, code signing,
Universal assembly, and replacing `RuntimeLifecycleController`; those belong
to the later ordered migration only if this option is selected. This subtask
is complete when both modes pass the lifecycle matrix and inspection proves
that the child executable is the only Dart runtime dependency on the worker
side.

The first formatting/analysis invocation formatted both new Dart sources, but
the analyzer itself did not start: Dart attempted to update
`~/.dart-tool/dart-flutter-telemetry-session.json`, which the workspace sandbox
does not permit. This is an execution-environment failure rather than an
analyzer result. The unchanged analysis command will be rerun with the narrow
filesystem access needed by the selected Dart tool.

With that access, the first analyzer run reached the sources and reported two
type errors in the runner: the validated nullable `mode` and architecture
option values had not been copied to non-null locals before being passed to a
function and a typed marker map. No probe process had run yet. The runner will
make the post-validation narrowing explicit and be analyzed again.

The next analyzer run showed that assignment alone was not enough: flow
analysis did not promote values checked inside the compound invalid-argument
condition, even though `_usage` returns `Never`. The two post-validation
assignments therefore need explicit non-null assertions. This remains a
compile-time typing correction; no runtime probe was started by either run.

The first `make process-worker-probe` built the official AOT executable, then
stopped before launching any worker because the runner's source-boundary audit
matched the formatted `bool.fromEnvironment` declaration with a
whitespace-sensitive multiline literal. Formatting had placed the opening
parenthesis and define name differently. The audit will check the API call and
define name as independent tokens so it continues to reject a missing
compile-time mode switch without depending on formatter layout.

After that correction, formatting and targeted static analysis passed. The
first complete `make process-worker-probe` then passed in both modes against
the clean pinned Engine checkout:

- JIT: 128 MiB in 198,508 us (644.81 MiB/s), with 151,537 us mean ready time
  across the five processes.
- AOT: 128 MiB in 169,285 us (756.12 MiB/s), with 14,141 us mean ready time.
- Both modes reported graceful exit 0, intentional uncaught-exception exit
  255 with the exact stderr diagnostic preserved, forced exit -9 after
  `SIGKILL`, two successful replacements, distinct supervisor/worker PIDs,
  and zero outstanding child processes.
- Before either run and after each run, the runner confirmed that the pinned
  Engine checkout remained clean. It also confirmed the executed arm64 slice;
  for AOT it rejected any separate `libdart_engine`, `libdart_jit`,
  `libdart_aotruntime`, or `libdart` dependency using Mach-O inspection.

These are first-run measurements, not yet the repeated evidence used for the
comparison decision.

An attempted five-run repetition did not start the runner or any worker in any
iteration. Each top-level `dart run` was denied while updating the same
telemetry session file under `~/.dart-tool`; the shell loop continued and
reported all five identical environment failures. These attempts add no
runtime samples. The five repetitions will be rerun with the same narrow Dart
tool filesystem access already required by analysis.

The controlled five-run repetition then passed all five JIT executions and
all five AOT executions. Every execution repeated the graceful, uncaught
exception, forced kill, and two replacement paths and ended with zero
outstanding processes. Across those repetitions:

- JIT bulk throughput was 659.62--677.87 MiB/s and mean worker-ready time was
  148,405--152,372 us.
- AOT bulk throughput was 762.52--797.12 MiB/s and mean worker-ready time was
  12,307--16,709 us.

The final artifact audit identified the executable as arm64. Its complete
dynamic dependency list contained only macOS `libSystem`, Security,
CoreFoundation, `libobjc`, Foundation, and CoreServices; there is no separate
Dart Engine/VM dylib. The selected Engine checkout remained clean at
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. Full-repository `dart analyze`,
`dart run test/run_tests.dart`, and `git diff --check` all passed.

Conclusion for this subtask: process separation is a viable published-Dart
fallback in both developer JIT and release AOT. It preserves a hard ownership
and cleanup boundary without an Engine source change. This conclusion does
not yet select it for product migration; the next ordered subtask compares it
with the general Engine correction, including packaging and upstream wait.

The first repository staging attempt was blocked before modifying the index
because the workspace sandbox denied creation of `.git/index.lock`. The five
task files remain only as worktree changes. Their narrowly scoped staging and
commit will be retried with Git metadata write access.

### 2026-09-03 — comparison and product-path selection plan

Purpose: choose the presently shippable runtime-hosting path independently of
the preferred long-term Engine design now that both candidates have executable
evidence.

Background and dependencies: the general Engine correction is isolated at SDK
commit `28462f0fb37` but is not an accepted Dart revision; the official-process
probe is repository commit `28496bb`. The product SDK remains clean at the
pinned published revision. The current product still applies one patch for
same-group worker initialization and one for VM-wide cleanup, so selection must
explain how both leave the product build rather than considering only worker
creation.

Scope is a recorded comparison of ownership/fault containment, lifecycle
fidelity, measured performance, arm64/x86_64/Universal packaging, and reliance
on unmerged upstream work. It also fixes the migration constraints for the UI
root: the unmodified Engine may continue to own the single AppKit-bound root,
but its final VM resources must be bounded by immediate application-process
exit after `DartEngine_Shutdown`; there may be no in-process reinitialization
or claim that the unmodified helper performed `Dart_Cleanup`. Worker processes
must expose ready, stderr, and exit status as authoritative boundaries.

Out of scope are changes to the product runner, lifecycle coordinator, bundle,
manifest, or patch graph; those are the next ordered migration and removal
subtasks. Publishing the Engine proposal is also later. This selection is
complete when the memo distinguishes current and long-term choices and records
remaining migration risks. Validation uses the arm64 M1 path as the current
gate and must leave both repository and product SDK sources unchanged. The
x86_64 and Universal lanes remain required by the later migration/full-matrix
work, but they do not block this selection decision.

The first packaging experiment exposed a real toolchain constraint. Running
the selected arm64 Dart 3.13.2 executable with `dart compile exe
--target-os=macos --target-arch=x64` failed before producing an artifact with
`Unsupported target platform macos_x64`; that executable listed only Linux
cross-target combinations. The generic `--target-arch` help text therefore
does not establish macOS cross-architecture support. Universal packaging for
this option requires running an official x86_64 Dart SDK under Rosetta or on
the Intel validation host, then combining separately built thin helpers. The
next check will look for such an official SDK locally before considering any
download; the failed command changed no source checkout.

Local inspection found only the selected arm64 Homebrew SDK; its `dart` binary
has one arm64 slice. The existing `xcodebuild/ReleaseX64` directory is a source
build output rather than a published SDK and will not be substituted for the
official-boundary test. Dart's [official SDK
archive](https://dart.dev/get-dart/archive) documents per-version macOS x64
downloads, and the stable 3.13.2 x64 archive responded successfully with
content length 228,742,095 bytes.

User direction then clarified the priority: macOS on M1/arm64 is the primary
product environment and Intel x86_64 is lower priority. Accordingly, the x64
archive was downloaded to the disposable directory but was not unpacked or
executed. The macOS cross-compilation limitation remains a recorded packaging
risk for the existing later x86_64/Universal matrix item; it will not delay
the arm64 selection or migration.

### 2026-09-03 — comparison result and selection

The two choices solve different time horizons:

| Criterion | General Engine correction | Official process worker | Selection impact |
| --- | --- | --- | --- |
| Supported today | Local upstream-quality implementation only; not reviewed, merged, or released | Uses published `dart run`, `dart compile exe`, `Process`, stdio, stderr, and exit status | Only the process path is a supported product input today |
| Ownership | Root Dart isolate owns same-group children; Engine owns VM initialization and final cleanup | UI owns a child PID and three streams; OS process exit is the worker cleanup boundary | Process ownership is explicit and independently recoverable |
| Fault containment | Dart isolate errors are containable, but a VM/native fatal fault shares the UI process | Worker exception or fatal process exit does not destroy the UI process; a hung worker accepts `SIGKILL` | Process path has the stronger pane-worker failure boundary |
| Feature fidelity | Native ports and `TransferableTypedData`; current lifecycle coordinator maps directly | Requires a product IPC adapter and serializable frames | Engine is simpler; process migration has more product code |
| Measured arm64 bulk | The candidate regression validates lifecycle, not bulk; existing same-group evidence was 1,056.65--2,702.08 MiB/s and is only indicative | 659.62--677.87 MiB/s JIT and 762.52--797.12 MiB/s AOT across five controlled repeats | Process path is slower but remains over six times the 100 MiB/s gate |
| Measured arm64 startup | Candidate did not collect a comparable product startup metric | Mean ready time 148--152 ms JIT and 12--17 ms AOT | Acceptable for the proof; pane-scale latency/RSS remain migration measurements |
| arm64 packaging | Would reuse the existing root Engine dylib after an upstream release | Self-contained AOT helper is 5,978,960 bytes and adds no Dart dylib; existing root AOT Engine remains 5,951,824 bytes | About 5.7 MiB of release helper payload plus per-process memory |
| Developer JIT | No extra runtime payload after upstream adoption | The local selected SDK is the official JIT worker runtime; bundling the entire 624 MiB installed SDK is not accepted by this decision | Developer packaging needs a narrow build-time/runtime contract in migration |
| Intel/Universal | Existing Engine build machinery already has thin lanes | macOS cross-architecture `compile exe` is unsupported; a separate official x64 SDK/host is needed, as the [official compile documentation](https://dart.dev/tools/dart-compile) limits cross-compilation to Linux targets | Recorded for the lower-priority later full matrix; does not block M1 |
| Upstream wait | Unknown review/API/release time and outcome | None for the APIs used | Product cannot wait on or predict acceptance |

Product decision at comparison closeout (superseded below): migrate pane-owned
workers to official Dart child processes, starting with M1/arm64. Keep the one AppKit-main-thread UI root in
the clean, unmodified `dart_engine`. Release workers use a self-contained AOT
helper; developer-JIT workers use the selected revision-matched official Dart
toolchain while the migration determines the smallest non-distributable
developer dependency contract. No build may silently fall back to the local
Engine candidate or reapply either patch.

The root cleanup contract is intentionally narrower than the proposed Engine
fix. After every worker process has an observed exit, product shutdown releases
the native bridge, stops the message pump, calls the unmodified documented
`DartEngine_Shutdown`, and immediately returns from the application main
process. OS process exit is the final VM-resource boundary. The product does
not claim `Dart_Cleanup` occurred, may not reinitialize Dart in that process,
and may not keep running after Engine shutdown. The clean-Engine multiple-root
probe already established bounded Engine shutdown followed by process exit; the
next migration must establish the same result in the actual one-root product.
If that fails, migration is blocked rather than restoring the cleanup patch.

Long-term decision: retain SDK commit `28462f0fb37` as the preferred upstream
Engine direction because child core-library initialization and complete
Engine-owned VM cleanup belong naturally at that helper boundary. Prepare it
for maintainer review in the later upstream-proposal subtask. The product may
reconsider same-group workers only after an accepted change appears in the
pinned Dart revision; acceptance does not force an automatic topology change.

The product migration must now verify these unresolved costs and constraints:

1. Preserve every existing ready, request, graceful stop, sync/async uncaught
   error, unexpected exit, startup failure, timeout/forced cleanup, late
   completion, double shutdown, and root failure classification through a
   process transport.
2. Treat child `exitCode` plus drained stderr as authoritative; an IPC error or
   acknowledgement alone is not cleanup. Bound graceful stop and escalate to
   `SIGKILL`, then prove replacement has no stale generation or open stream.
3. Package and sign one reusable arm64 AOT helper, record it in manifests and
   freshness inputs, and measure worker RSS, pane-scale startup, and queue
   backpressure. No unmeasured memory claim is made by this selection.
4. Keep JIT and AOT semantic results equal while allowing their startup and
   packaging mechanics to differ. Do not package the full development SDK as
   an accidental production dependency.
5. Run M1 lifecycle, integration, audit, and performance gates first. Preserve
   the already planned x86_64 and Universal verification as lower-priority
   later matrix work rather than allowing it to delay arm64 migration.

This selection changes no product source or build graph. The main repository
contains only this updated decision record, and the product SDK checkout is
still clean at the pinned revision.

Selection closeout passed `git diff --check`, full-repository `dart analyze`,
and `dart run test/run_tests.dart`. A final SDK check again reported the exact
pinned revision and an empty worktree. The only repository changes for this
subtask are this memo and the two comparison checkboxes in `ROADMAP.md`.

### 2026-09-03 — decision revision: `dart_appkit` owns same-process adoption

User direction prioritizes the best long-term architecture over the previously
selected immediately published fallback. Since the Engine candidate keeps
native Dart ports, avoids a VM process per pane, and fits the existing
AppKit-main-thread host naturally, same-process workers are now the primary
product path. The process implementation/probe remains evidence and a bounded
fallback, not the planned product migration.

Inspection of `../dart_appkit` confirms that it is the correct integration
owner: its native Runner initializes `dart_engine`, owns the AppKit run loop,
sets the message scheduler, and performs final Engine shutdown. It must own the
supported worker contract and regression tests rather than making each product
rediscover Engine behavior.

Changing `dart_appkit` alone, however, cannot implement the two missing Engine
responsibilities safely:

1. `Dart_InitializeParams.initialize_isolate` is fixed when
   `DartEngine_Init` calls `Dart_Initialize`. The caller cannot install it
   afterward. The callback's `dart:io`/core setup uses the private helper that
   `dart_engine` already encapsulates; copying that helper into `dart_appkit`
   would create a new private-SDK dependency.
2. Calling `Dart_Cleanup` outside `DartEngine_Shutdown` cannot be ordered
   safely around Engine-owned root isolates, persistent handles, snapshots,
   and loaded AOT libraries. Calling before shutdown invalidates state Engine
   still uses; calling after shutdown is too late for live same-group children
   and released snapshot memory.

The adopted design is therefore coordinated but has one responsibility per
repository:

- Dart SDK: carry the already validated product-independent Engine commit that
  initializes same-group children and completes Engine-owned VM cleanup. It is
  an actual commit based on the exact upstream revision, with upstream sample
  regressions—not a patch file applied by a product build.
- `dart_appkit`: declare this Engine behavior as a host capability, add a real
  same-group worker conformance example/test, preserve AppKit main-thread and
  bounded scheduling, and fail closed when its configured Engine does not meet
  the contract.
- Dart Terminal: consume the `dart_appkit` contract using ordinary
  `Isolate.spawn`/ports, remove its own patch/provenance machinery, and retain
  the existing lifecycle classifications.

This explicitly supersedes the “published process worker as current product
path” decision recorded in `0d26e58`. It also refines, rather than reverses,
the no-product-patch rule: a general Dart Engine source change with its own
commit, tests, and upstream review path is allowed by the user's earlier
clarification; an opaque `.patch` reapplied for Dart Terminal remains
forbidden. Until the Engine commit is accepted upstream, the dependency must
be identified honestly as a maintained candidate revision and cannot be
misrepresented as stock Dart 3.13.2.

The revised ordered migration is:

1. Register a new active task and design/acceptance record in `dart_appkit`.
2. Integrate the general Engine candidate as a commit, then add and pass
   `dart_appkit` worker/future/microtask/error/shutdown conformance tests.
3. Point Dart Terminal's M1 Developer JIT and Release AOT paths at that
   explicit contract, removing product-owned patch application only after
   both modes pass.
4. Close the M1 lifecycle/performance/shutdown matrix first. Intel/Universal
   remains lower-priority follow-up as directed by the user.

The first migration unit is documentation/task registration in
`../dart_appkit`; no adjacent source will change before its roadmap and
worklog state the purpose, scope, exclusions, dependency boundary, completion
conditions, and verification plan.

That registration is complete in `dart_appkit` commit `a2149ff` (`Define
same-group Engine contract`). Its roadmap now has one active task covering the
general Engine commit, fail-closed capability validation, hosted worker
conformance, and documentation; its worklog records the Engine/AppKit/
application ownership split and explicitly forbids copying private SDK helpers
or presenting the candidate as stock Dart. No `dart_appkit` runtime source was
changed in this registration unit.

Registration closeout passed `git diff --check`, full `dart analyze`, and
`dart run test/run_tests.dart`. The adjacent `dart_appkit` worktree was clean
at `a2149ff` after its commit. This repository unit changes only the roadmap
route and this decision record; product runtime code remains unchanged.

### 2026-09-03 — constraint correction: no Dart Engine modification

The user clarified that Dart Engine itself must not be modified, including
when `dart_appkit` owns the integration. This supersedes the candidate-commit
adoption decision above. Storing the change as a normal SDK commit instead of
applying a `.patch` does not satisfy the constraint because both alter Engine
source and runtime behavior.

The temporary candidate checkout in `../dart_appkit/.dart_tool/dart-engine/sdk`
was never built or consumed there. It was returned immediately to the exact
official Dart 3.13.2 revision
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`; `git status --short --branch`
then showed a detached official HEAD with no source changes. The candidate
remains historical experimental evidence only and is not an allowed product or
host dependency.

The current ordered route is now constrained to changes in `dart_appkit` and
Dart Terminal:

1. Re-evaluate stock `dart_engine` multiple-root hosting and a native bridge
   between isolate groups using only its published C interface.
2. Re-evaluate a `dart_appkit`-owned host composed solely from public Dart
   Embedder APIs, without copying any private SDK setup or cleanup helper.
3. Probe an official Dart/AOT executable topology in which Dart performs its
   normal VM/isolate initialization, the native bridge holds the process main
   thread in AppKit, and standard Dart worker isolates own application work.
4. If none of the same-process options has a complete supported lifecycle, expose
   the already measured official Dart executable/AOT worker process through a
   `dart_appkit` contract rather than modifying the VM or Engine.

The first satisfactory route will be implemented and tested on M1/arm64 first.
x86_64 and Universal remain lower-priority compatibility checks. No Engine
source file, Engine commit, patch application, generated Engine diff, or
private runtime helper is permitted in the resulting build.

### 2026-09-03 — roadmap normalization after architecture drift

The preceding log is retained as evidence, but its successive selection
paragraphs are no longer the execution plan. The public-API subtask was marked
complete after testing a lightweight child inside stock `dart_engine`; that did
not actually implement the originally proposed full product-owned embedder
that calls `Dart_Initialize` and owns initialization, scheduling, snapshots,
and cleanup. Treating the hybrid result as closure of the full-host option was
incorrect.

The supplementary official-runner main-thread probe is now complete and
closed. In both JIT and AOT, synchronous Dart startup, a microtask, and a timer
reported that they were not on the macOS process main thread. A second bounded
probe posted to the main dispatch queue; it timed out after one second in both
modes (`main_dispatch=0`). The published Dart executable therefore cannot host
the required AppKit main loop from Dart code in this architecture.

[`stock-dart-runtime-migration-plan.md`](stock-dart-runtime-migration-plan.md)
is now the normative, frozen plan. It restores the full public `dart_api.h`
embedder as the one missing first-choice proof, treats multiple roots and the
lightweight hybrid as already rejected evidence, prohibits every Engine
modification, and names the previously validated official process worker as
the sole fallback. No additional topology will be introduced during this
migration.

Normalization validation passed `git diff --check`, full-repository
`dart analyze`, and `dart run test/run_tests.dart`. The adjacent `dart_appkit`
package analysis, API tests, and launcher tests also passed, and its nested SDK
remained clean at the official revision. This checkpoint changes planning and
evidence documents only; the next and only active implementation item is the
full public-host proof.
