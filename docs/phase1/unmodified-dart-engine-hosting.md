# Unmodified Dart Engine hosting migration

- Status: in progress; policy and ordered decision gates fixed
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

### 3. Probe a public-API product embedder if needed

First determine whether a product-owned host can initialize core libraries,
create the required isolate topology, schedule it, retire it, and call
`Dart_Cleanup` using public headers alone. Reject a design that quietly reaches
into `runtime/bin` or another private SDK component.

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
