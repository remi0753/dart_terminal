# VM and isolate lifecycle contract

- Status: complete; post-serialization regression and independent re-review passed
- Started: 2026-09-02
- Scope: third Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, `FEATURE_MATRIX.md` RT-01–RT-03 and
  REL-01, ADR-001, ADR-002, DT-002, and DT-003

## Purpose

Turn the Phase 0 root-isolate and worker-isolate feasibility spikes into one
product runtime contract. Developer JIT and release AOT must expose the same
deterministic startup, ready, failure, and bounded-shutdown observations while
the AppKit main thread remains responsive.

## Background

Phase 0 proved that a Product AOT root isolate can attach to the AppKit main
thread and that same-group workers can start, exchange bulk data, stop, and
report one intentional crash. The current product runtime paths, however, only
prove successful window attachment and automatic close. They do not yet define
the product behavior for startup failure, synchronous or asynchronous worker
errors, unexpected worker exit, root uncaught error, late completion, repeated
shutdown, or shutdown timeout.

ADR-001 assigns lifecycle orchestration, deadlines, and user-visible
diagnostics to Dart while native code owns VM embedding and the AppKit message
pump. ADR-002 makes `onExit` authoritative, treats `onError` as diagnostic,
requires bounded asynchronous shutdown, and distinguishes isolate-contained
failure from an embedder/VM fatal error.

## Scope

- Add a repository-owned Dart lifecycle coordinator with an explicit root and
  long-lived worker state contract.
- Cover root start/ready/normal exit and worker
  start/ready/request/drain-or-stop/exit observations.
- Cover worker synchronous uncaught error, asynchronous uncaught error,
  unexpected exit, startup failure, and root uncaught error.
- Make graceful shutdown bounded, use forced isolate cleanup after timeout,
  make repeated shutdown idempotent, and ignore late replies from an invalid
  generation without leaking pending work.
- Map lifecycle outcomes to deterministic process exit codes and stable
  machine-checkable diagnostics.
- Extend the product release-AOT host only as needed to report root message or
  VM/embedder fatal failure and to preserve bounded AppKit scheduling.
- Run one observable lifecycle integration/fault suite against both the
  developer-JIT and release-AOT product bundles on the Apple M1/arm64 baseline.
- Add focused Dart unit tests, Make entry points, build provenance inputs, and
  user/project documentation required by this contract.

## Out of scope

- The next Phase 1 native-event wire-format versioning task.
- The following handle-registry, thread-domain destruction, generic view,
  menu, logging, or resource-leak roadmap tasks.
- PTY ownership, renderer recovery, per-pane restart policy, or terminal
  protocol work.
- `Isolate.spawnUri`, arbitrary isolate groups, or assigning a stable pthread
  identity to a Dart worker.
- Changing the Apple M1/arm64 primary baseline or making Intel-native evidence
  a gate for this task.

## Dependencies and confirmed facts

- The task started from clean HEAD
  `b704dcbfa9fd6ccc57240ba66f150a350b54246d`.
- This is the first unchecked `ROADMAP.md` item. No later item has been started.
- Developer JIT and release AOT already build the same `bin/main.dart`, use
  separate Engine/payload products, and pass the same normal-close smoke.
- The Product AOT embedder patch supplies `Platform.script` and the
  `initialize_isolate` callback needed by same-group `Isolate.spawn`; it
  deliberately leaves new isolate-group creation unsupported.
- Only the root isolate is main-thread-bound. Workers are VM scheduling
  domains and may migrate between operating-system threads.
- The release host currently treats a Dart message-handler error as fatal,
  requests AppKit termination asynchronously, disables event posting, and
  shuts down the Engine after bridge cleanup.
- The product currently has no long-lived worker or lifecycle coordinator; the
  worker behavior exists only in the Phase 0 spike.

## Task sizing decision

Do not subdivide the roadmap item. The root contract, worker state machine,
native fatal boundary, shared JIT/AOT harness, and fault assertions are one
acceptance unit: landing only part would let a runtime claim lifecycle support
without the same observable behavior in both product modes. Work will be
implemented and verified in ordered layers, but completed in one task commit.

## Acceptance criteria

1. Developer JIT and release AOT run the same lifecycle scenario inventory and
   produce the same ordered semantic observations and outcome classification.
2. Normal root startup reports start then ready; normal worker startup reports
   start then ready, accepts a request, acknowledges bounded stop, and produces
   one authoritative exit observation.
3. Worker synchronous and asynchronous uncaught errors record deterministic
   diagnostics; `onError` and `onExit` may arrive in either order without a
   hang or duplicate completion.
4. Worker unexpected exit and startup failure invalidate the owner generation,
   reject later work, close ports, and remain isolate-contained rather than
   terminating the whole application.
5. Root uncaught error produces a stable process-fatal classification and
   nonzero exit status. Embedder/VM fatal failure remains a separate native
   process-fatal boundary and is never presented as a recoverable worker
   failure.
6. Graceful shutdown has an explicit deadline. Timeout uses forced cleanup,
   reports that fact deterministically, and never blocks AppKit or the root
   isolate synchronously.
7. Repeated shutdown is idempotent. Late worker replies or delayed completions
   after generation invalidation are harmless and cannot change the final
   outcome or complete an operation twice.
8. The root/AppKit message pump remains bounded by its existing 64-message /
   4,000-us turn contract, and every integration/fault scenario terminates
   within a harness timeout.
9. Exit-code and diagnostic mapping is stable and asserted for every normal,
   isolate-contained, startup, timeout/forced-cleanup, root-uncaught, and
   native-fatal class exercised by the suite.
10. Formatting, static analysis, focused unit tests, both arm64 product
    build/audit paths, the shared JIT/AOT lifecycle suite, M1 runtime
    verification, relevant matrix/freshness/Phase 0 regressions, and final
    artifact/diff hygiene pass.
11. README and FEATURE_MATRIX describe the implemented contract without
    claiming later event-wire, handle-registry, PTY, renderer, or leak work.

## Validation plan

- Run Dart formatting, repository-wide static analysis, and unit tests.
- Add table-driven lifecycle state/diagnostic tests, including arrival-order,
  double-shutdown, timeout, and late-completion cases.
- Build and strictly audit the arm64 developer-JIT and release-AOT products.
- Execute the identical normal and fault scenario set in both modes with an
  outer timeout, exact exit status, ordered observation, and stderr policy.
- Exercise an explicit native-fatal test seam without weakening production
  behavior, and require the host to terminate instead of treating it as a
  worker-contained error.
- Rerun `runtime-verify` for arm64, build-freshness/provenance checks affected
  by new inputs, the relevant runtime matrix gate, and `phase0-verify` in
  proportion to the native/embedder risk.
- Inspect signed bundle contents, fingerprints/manifests/receipts, process
  architecture, generated artifacts, links, secrets, whitespace, and staged
  scope before marking this item complete.

## Risks and open checks

- A Dart root uncaught asynchronous error reaches the embedder message-error
  callback, whereas an awaited startup error may be returned directly from
  `Dart_Invoke`; both paths need stable but distinct handling.
- `onError` payload shape and ordering relative to `onExit` must not be parsed
  from human-readable stack text for behavioral decisions.
- `Isolate.kill` does not itself prove all ports and pending completers were
  closed; coordinator generation invalidation must make cleanup observable.
- A deliberately unresponsive worker must be killed without waiting on the
  AppKit thread or leaving a timer/receive port that keeps the process alive.
- Test-only fault selection must be explicit, unavailable in ordinary launch,
  content-addressed by the runtime build, and unable to weaken release bundle
  audit policy.

## Investigation log

### 2026-09-02 — repository and contract review

- Read the repository work rules, product overview, complete roadmap, complete
  feature matrix, ADR-001, ADR-002, DT-002, DT-003, the preceding two Phase 1
  task memos, the Engine worker patch, and the complete runtime Make section.
- Inspected current product entrypoint, application/session/buffer code, unit
  harness, release-AOT host, runtime paths, audit/integration hooks, and
  architecture/provenance constraints.
- Confirmed that the current normal smoke requires only AppKit attachment,
  scheduled close, clean shutdown, exit zero, and empty stderr. It does not
  instantiate or fault a product worker.
- Started read-only reviews of the adjacent `dart_appkit` Engine API and the
  existing build/test insertion points. No product code has been changed.

### 2026-09-02 — Engine/API and build-chain findings

- The Engine public API creates and directly tracks the root isolate only.
  Product workers are created by Dart `Isolate.spawn`; their lifecycle is
  observable only through the spawn-time `onError` and `onExit` ports.
- Spawn registers `onError`, `onExit`, and `errorsAreFatal` before executing
  the worker entry point. This closes the ready-before-listener race and makes
  a dedicated error port plus authoritative exit port the selected worker
  contract.
- `DartEngine_SetHandleMessageErrorCallback` receives errors returned by
  embedder-driven `Dart_HandleMessage`. It is the existing process-fatal path
  for an uncaught root-isolate asynchronous error; it is not the worker error
  channel.
- `Dart_Invoke(main)` does not await an async Dart `main` result. Root
  application readiness therefore cannot be inferred from native invocation
  success; Dart must explicitly emit ready only after AppKit attachment and
  worker ready handshake complete.
- The AppKit message pump remains a main-thread FIFO bounded to 64 messages or
  4,000 us per turn. The bound cannot preempt one long Dart callback, so all
  coordinator handlers perform one constant-size state transition and never
  wait synchronously.
- Both native executables return their AppKit delegate's status, not Dart
  `dart:io`'s `exitCode`. The current invalid-argument path sets only the Dart
  value and does not request AppKit termination; deterministic product status
  therefore requires a repository-owned native status/termination control.
- The adjacent `dart_appkit` checkout must remain clean. The developer bundle
  can retain its AppDelegate, DartHost, and message pump while replacing only
  the small native `main` source with a repository-owned equivalent that reads
  the shared lifecycle status after AppKit returns.
- One read-only launch experiment intended to confirm the invalid-argument
  hang was inconclusive: an initial zsh wrapper accidentally assigned its
  read-only `status` variable, and a corrected alarm-wrapped GUI launch exited
  134 under the restricted environment without product diagnostics. It made
  no repository change and is not accepted as behavioral evidence; the
  source-level exit-code mismatch above remains the actionable fact.

### Engine shutdown decision

A Dart-coordinator-only correction is insufficient. Normal stop, worker
failure, and forced kill can and will await authoritative worker `onExit`
before asking AppKit to terminate. An uncaught root error or VM/embedder fatal
condition, however, can bypass Dart's ordered coordinator shutdown while a
worker is still alive.

The current Engine `Shutdown` implementation iterates only isolates created by
`DartEngine_CreateIsolate`, which is the root, calls `Dart_ShutdownIsolate` on
that list, and then frees snapshot storage. VM-created same-group workers are
not in that list. Relying on every root fatal to happen only after a test worker
was pre-stopped would make the test safe while leaving the production failure
path unsafe. That option is rejected.

A second revision-pinned Engine patch is therefore required. It will be
separate from the already-applied worker-initialization patch because extending
that patch in place would break the current whole-patch idempotence test when
old hunks are applied and new hunks are not. The ordered lifecycle patch will:

1. stop new Engine scheduling and detach message notification from directly
   tracked roots;
2. release Engine-owned persistent handles and synchronously shut down each
   main-thread-bound root before entering VM-wide cleanup;
3. invoke VM-wide `Dart_Cleanup` from the native/main thread so remaining
   isolate groups and VM worker threads, including surviving spawned workers,
   are stopped before snapshot storage is released;
4. report cleanup failure through the Engine's native diagnostic path rather
   than silently treating it as a successful normal shutdown;
5. clear Engine bookkeeping only after VM cleanup.

The Make target will apply both patches idempotently in order. Fingerprint and
manifest schemas will bind both patch hashes and the exact combined Engine
diff; the lifecycle patch variable itself will be command-line immutable and
covered by hostile-override/freshness checks. Existing Engine build products
must rebuild from this input. Rollback is removal of the second patch through
its exact reverse check; no history rewrite or adjacent-repository commit is
part of this task. Full JIT/AOT matrix and Phase 0 hardware regressions are
mandatory because the same Engine shutdown implementation serves all those
bundles.

The patch retains the existing `Dart_ShutdownIsolate` call for directly tracked
roots and clears `first_isolate_started_` after `Dart_Cleanup`. This makes
an accidental repeated Engine shutdown skip the VM cleanup API after the VM has
transitioned to terminated. `Dart_Cleanup` itself disables isolate creation,
sends internal kill messages to every remaining application isolate, waits for
all isolate shutdown, and joins the VM thread pool before returning success;
this is the authoritative VM-wide worker barrier missing from the original
root-only loop.

The first draft of the lifecycle patch used incorrect unified-diff hunk counts,
so `git apply --check` reported a corrupt patch. No source was changed by that
failed check. The hunk headers were corrected, the exact patch then passed
`git apply --check`, and it applied cleanly after the existing worker patch.
An immediate follow-up reverse-check initially used a path relative to the
Engine checkout rather than an absolute project path and therefore could not
open the patch; both exact reverse checks passed after using canonical absolute
paths.

### 2026-09-02 — first real bundle failure and Engine correction

- The first arm64 developer-JIT bundle build succeeded, including recompiling
  `engine.cc`, generating fingerprint version 4 and manifest version 6,
  linking the repository-owned native lifecycle sources, compiling the Kernel,
  signing, and packaging.
- Its first normal smoke timed out after 12 seconds. A diagnostic rerun captured
  every Dart observation through worker stop acknowledgement, authoritative
  worker exit, root exit, and the existing clean-shutdown line with empty
  stderr. The failure was therefore after Dart application teardown, inside
  native application termination.
- The first patch revision had replaced root `Dart_ShutdownIsolate` with
  `Dart_ExitIsolate` before calling `Dart_Cleanup`. That leaves the root isolate
  alive while VM cleanup, itself running on the AppKit main thread, sends the
  root a kill and waits for it. The main-thread-bound root cannot run its kill
  message while that same thread is blocked in cleanup. This created the
  observed shutdown deadlock.
- Rejected correction: removing VM-wide cleanup would restore the old normal
  path but leave a surviving worker unsafe on root/native fatal teardown.
- Adopted correction: preserve the original synchronous root
  `Dart_ShutdownIsolate`, then call `Dart_Cleanup` as the barrier for any
  remaining VM-created workers before freeing snapshots. The first lifecycle
  patch was reversed exactly, rewritten without the `Dart_ExitIsolate` change,
  syntax-checked, reapplied, and both patch reverse-checks now pass. A rebuild
  and both normal/fault suites are required before accepting this correction.

### 2026-09-02 — nonzero AppKit termination status correction

- The corrected JIT normal smoke passed in 2.06 seconds with status 0. The
  lifecycle suite then passed normal, worker synchronous/async uncaught,
  unexpected exit, and startup failure before the shutdown-timeout case
  returned status 0 instead of the requested 75. Its full ordered lifecycle
  observations, including forced kill and root exit, were otherwise correct
  and stderr was empty.
- A read-only LLDB run stopped in the exported FFI setter on the AppKit main
  thread with argument 75 and return value 0, proving the request was accepted.
  The process then exited 0 without reaching the breakpoint in C++ `main`
  after `[NSApplication run]`. `-[NSApplication terminate:]` performs process
  termination after `applicationWillTerminate`; it does not normally return to
  the caller's `main`, so reading the requested code only after `run` was too
  late.
- The selected correction preserves orderly AppKit delegate teardown, bridge
  cleanup, message-pump stop, root shutdown, and VM-wide cleanup. At the very
  end of `applicationWillTerminate`, a shared native helper gives delegate
  fatal status precedence, flushes stdio, and uses `_Exit` only for a requested
  nonzero status. JIT uses a repository-owned subclass around the unchanged
  adjacent delegate; release AOT calls the same helper in its owned delegate.
  Normal status 0 remains on AppKit's ordinary termination path.

### Selected failure classification and test seam

- Worker uncaught errors are isolate-contained. Behavioral classification uses
  only the presence of `onError` plus authoritative `onExit`, never the human
  error/stack text or arrival order.
- A root synchronous startup throw is observed by native `Dart_Invoke` and is
  process-fatal with software status 70. A root asynchronous uncaught error is
  observed by the existing Engine message-error callback and is also
  process-fatal with status 70.
- A genuine VM fatal error is not forged as a worker event and is never
  declared recoverable. It stays in the native process-fatal domain; the new
  VM-wide cleanup path protects teardown when the Engine can still run it.
  An unrecoverable VM abort for which no callback can execute remains an OS
  abnormal termination, not an invented deterministic worker outcome.
- The explicit native fault seam exercises a real host-startup failure before
  Dart invocation in both repository-owned native `main` paths and returns 70
  with a stable host-failure diagnostic. It is enabled only by a dedicated
  integration-test environment variable; ordinary launches never select it.
  This verifies the native process-fatal mapping without pretending to induce
  or recover a genuine VM abort.
- A small C ABI, implemented in repository-owned runtime native code and
  linked into both products, accepts only the documented application outcome
  codes, records the first requested nonzero code, and asynchronously requests
  AppKit termination. Native delegate fatal status takes precedence. This is a
  lifecycle control call, not the following task's asynchronous native-event
  wire format.

### Selected implementation shape

- A Dart lifecycle coordinator owns one same-group long-lived worker,
  dedicated command/error/exit ports, owner generation, bounded deadlines,
  pending scalar operation IDs, and one cached shutdown future.
- Normal product startup performs ready and one request/reply handshake, then
  retains the worker until window/application shutdown.
- Integration-only scenarios cover worker synchronous and asynchronous
  uncaught error, ready-before-failure, unexpected exit, ignored stop/forced
  cleanup, delayed reply after generation invalidation, double shutdown, root
  startup throw, root asynchronous uncaught error, and native host startup
  failure. The same scenario table is applied to both built bundles.
- Stable lifecycle observations are normalized after authoritative exit, so
  permitted `onError`/`onExit` arrival-order variation cannot make JIT and AOT
  output differ semantically.
- A new Dart library under `lib/` and new native files under
  `native/macos/runtime/` are automatically included by the existing recursive
  source inventory. The existing integration tool will be extended rather
  than adding an unbound tool entry. Unit tests will be split into a new test
  source imported by the existing `test/run_tests.dart` entry point.

All auxiliary reviews were read-only. Product implementation started only
after the decision above was recorded: the standalone lifecycle patch has
been created, syntax-checked, and applied after the worker patch in the pinned
Engine checkout. Make, product, test, and user-documentation changes follow.

### 2026-09-02 — focused source validation after exit-status correction

- The lifecycle integration table originally applied the empty-stderr policy
  to the intentional usage-error case. That expectation was incorrect because
  the product contract deliberately prints a stable argument diagnostic and
  usage text for status 64. The case now requires the stable argument-error
  prefix; normal and isolate-contained failures continue to require empty
  stderr, while process-fatal cases require their stable fatal marker.
- `make runtime-source-check` passed after the AppKit termination correction:
  Dart formatting covered 32 files with zero changes, Objective-C++ formatting
  and both plists passed, repository analysis reported no issues, and the
  complete Dart unit harness passed.
- A first sandboxed direct `dart format` verified zero source changes but
  returned failure after it could not update the user's telemetry-session
  timestamp. Repeating the same read/format check with the required host
  access succeeded; this was an environment-side telemetry write, not a source
  or formatter failure.
- The corrected arm64 developer-JIT bundle rebuilt, linked the repository
  lifecycle bridge/delegate subclass, regenerated fingerprint version 4 and
  manifest version 6, packaged, and signed successfully. The normal smoke
  passed with status 0 in 2,081 ms.
- The complete developer-JIT lifecycle suite passed all 12 process cases:
  normal; synchronous and asynchronous worker uncaught error; unexpected
  worker exit; worker startup failure; shutdown timeout/forced cleanup with
  status 75; late completion; double shutdown; root startup and asynchronous
  uncaught failures with status 70; native host startup failure with status
  70; and usage error with status 64. Every case completed within the 12-second
  outer bound; the slowest lifecycle case was normal at 1,343 ms and the
  shutdown-timeout case completed in 609 ms.
- The arm64 release-AOT Engine/library, host, Kernel, and application snapshot
  rebuilt successfully with the same two Engine patches. Fingerprint version
  4 and manifest version 6 passed, and the bundle packaged and signed. Its
  normal smoke passed with status 0 in 1,755 ms.
- The identical 12-case release-AOT lifecycle table passed with the same
  observable event order and outcome mapping as developer JIT. In particular,
  forced shutdown returned 75 in 533 ms, both root failures and native startup
  failure returned 70, usage error returned 64, isolate-contained failures
  returned 0, and all processes completed within the outer deadline. This is
  the required primary Apple arm64 JIT/AOT parity evidence.
- Strict signed-bundle audits then passed for both final-source arm64 bundles.
  Each audit validated a single arm64 slice, deployment target 14.0, ad-hoc
  signatures and bundle seal, the mode-specific Engine/payload policy, and
  fingerprint/manifest schemas. Both manifests contain the worker and
  lifecycle patch SHA-256 values and the exact combined Engine diff identity;
  the adjacent `dart_appkit` repository remains recorded as clean.
- The final-source `make RUNTIME_ARCH=arm64 runtime-verify` aggregate passed:
  source checks and unit tests, both strict bundle audits, both normal smokes,
  and both complete lifecycle suites. Its repeated forced-shutdown cases
  returned 75 in 613 ms for JIT and 531 ms for AOT; all other mappings and
  ordered observations remained stable.
- The runtime freshness regression is in progress. Its completed gates report
  that all 92 protected Make internals ignored hostile overrides, no hostile
  path was consumed, Dart-tool bypass was rejected, SDK/runner alias and
  replacement policies behaved as specified, six tool-evidence classes were
  verified, and nine builds using space-containing toolchain paths succeeded.
  The later derived-artifact mutation/rebuild cases were still actively
  producing temporary arm64 JIT builds at the time of this checkpoint.
- A sandboxed read-only process-list query was denied by the host policy. The
  approved read-only repeat showed the parent freshness Dart process and its
  current temporary Make/fingerprint child active, confirming this long quiet
  interval was work in progress rather than a stopped process.
- The freshness regression completed successfully. Its remaining gates
  rejected 28 external header/response-file/forwarding attacks, reused zero
  stale artifacts, regenerated all nine effective-input and all nine package
  configuration cases, preserved all nine stable no-op cases, and rejected a
  forged package root and a missing required override. The new lifecycle patch
  and all three repository-owned native source variables participate in the
  protected-input checks.
- `make runtime-matrix-verify` completed successfully. It repeated the source
  and freshness gates, passed both arm64 and x86_64 thin signed-bundle audits,
  assembled and strictly audited the exact two-slice Universal release bundle,
  and passed the complete release-negative suite.
- All matrix normal-launch probes passed without a GUI-permission interruption:
  arm64 JIT in 1,333 ms, arm64 AOT in 1,216 ms, Rosetta x86_64 JIT in
  5,731 ms, Rosetta x86_64 AOT in 2,793 ms, Universal AOT selected as arm64 in
  1,709 ms, and the same Universal bundle selected as x86_64 in 2,319 ms.
  The matrix correctly emitted `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED`; an
  Intel-native-machine handoff remains the explicitly low-priority follow-up
  and is not an Apple arm64 completion blocker.
- `make phase0-verify` completed with status 0 against the Engine lifecycle
  patch. Formatting, analysis, the Dart unit harness, the debug/JIT AppKit
  launch, AOT root and worker probes, PTY transport/child audit, Metal,
  CoreText, IME, benchmark hard and baseline gates, and the six-bundle arm64
  audit all passed. The debug launch also exercised the normal product
  root/worker start, ready, request, graceful stop, authoritative exit, and
  root-exit path without hanging the AppKit main thread.

### 2026-09-02 — final review preparation

- Both revision-pinned patch reverse checks pass in the Engine checkout. Its
  only modification is `runtime/engine/engine.cc`, exactly as required by the
  combined worker and lifecycle patches. The adjacent `dart_appkit` repository
  remains clean.
- The project worktree contains only the files listed by this task memo's
  implementation scope; build outputs remain ignored. `git diff --check`
  passes, there are no file-mode changes, and scans of the tracked diff and
  new task files found no TODO/FIXME/debug placeholders, private keys, or
  common credential-token signatures.
- All acceptance criteria are satisfied on the primary Apple M1/arm64
  baseline. Cross-built and Rosetta compatibility evidence also passed. The
  deliberately deferred Intel-native hardware handoff is the only unexecuted
  environment variant, is explicitly low priority in the roadmap policy, and
  does not require a new roadmap item.
- No later native-event, handle-registry, PTY, renderer, or leak-test roadmap
  implementation was started. The current roadmap item is marked complete for
  review because all implementation and validation gates pass; the task commit
  remains intentionally pending until the independent diff review finds no
  blocking issue.

### 2026-09-02 — independent-review lifecycle blocker

- Independent review found that the first coordinator revision reconciled a
  worker termination only from a pending `start` or `request`. An idle worker
  that crashed after ready therefore completed its `onError`/`onExit`
  completers but left the coordinator in `running`. A later shutdown waited for
  a stop acknowledgement that could never arrive, mislabeled the already-dead
  worker as a shutdown timeout, attempted a redundant force kill, and omitted
  the worker-error observation. A worker throwing while processing stop had
  the same misclassification. This is a commit blocker, not a deferred task.
- The same revision used a 20 ms delay after `onExit` to allow a separately
  delivered `onError` to arrive. The public isolate API does not guarantee an
  upper wall-clock delay between different receive ports, and ADR-002 requires
  either handler arrival order to be correct. Passing repeated JIT/AOT runs is
  empirical evidence but cannot make that timer a deterministic contract.
- Pinned VM source establishes the usable causal boundary: unhandled-error
  processing calls `NotifyErrorListeners` before isolate low-level shutdown
  calls `NotifyExitListeners`; both normal messages are appended to the root
  isolate's one message-handler FIFO. The SDK's own `Isolate.run`
  implementation likewise routes `onError` and `onExit` to one result port and
  distinguishes their payloads. ADR-002 intentionally retains dedicated
  command, error, and exit channels, so collapsing the two product channels
  was considered but rejected. This is deliberately a pinned-VM fact, not a
  claim about the public `SendPort` cross-port or cross-sender API. The existing
  exact SDK/Engine revision checks, repository identity, patch reverse checks,
  and content-addressed fingerprint make an SDK revision change fail closed
  until this causal dependency is reviewed again.
- Selected correction: every first `onExit` starts one authoritative
  asynchronous reconciliation, regardless of whether startup, a request, or
  shutdown is currently awaiting it. After observing exit, root posts private
  drain markers to its event and error ports. The worker/VM posted every
  pre-exit reply, stop acknowledgement, and error before the exit; each marker
  is therefore queued after that evidence. Reconciliation waits for both
  markers rather than elapsed time, classifies startup/uncaught/unexpected/
  graceful/forced termination once, invalidates response admission, closes all
  ports, and completes one termination future used by every caller.
- Shutdown will race the stop acknowledgement with that reconciled termination
  under one deadline. Termination first is a completed contained outcome, not
  a timeout; acknowledgement first continues waiting only for authoritative
  termination. Only absence of both termination and completion by the deadline
  triggers force kill. A pure termination-evidence unit seam will exercise
  error-before-exit and exit-before-error, plus idle, graceful-stop,
  stop-crash, and forced classifications. Real JIT/AOT scenarios will add
  post-ready idle uncaught failure, post-ready idle clean/unexpected exit, and
  uncaught failure while processing stop.
- Review also reproduced a C ABI header violation: compiling
  `RuntimeLifecycleBridge.h` as C11 fails because it included C++ `<cstdint>`
  and exposed an unconditional namespace with `inline constexpr` values.
  ADR-001 requires public bridge declarations to remain valid C11 as well as
  C++20. The selected fix uses `<stdint.h>` for the exported ABI and guards the
  C++-only constants/helpers with `__cplusplus`. The permanent source gate will
  syntax-check this header explicitly in both C11 and C++20 modes in addition
  to formatting and the two Objective-C++ product builds.
- Review raised a further provenance question: two independent successful
  patch reverse checks plus a one-file Engine status do not by themselves
  exclude an unrelated, non-overlapping hand edit in `engine.cc`. The current
  fingerprint records the resulting combined diff hash but must also prove the
  diff is exactly the composition of the two pinned patches. The fingerprint
  implementation and negative suite will be checked for that equality; if it
  is not already enforced, this task will add an exact combined-diff gate and
  a non-overlapping extra-edit rejection before revalidating freshness.
- The first post-review `runtime-source-check` stopped at its intended dry-run
  format gate because the rewritten coordinator and lifecycle unit file needed
  formatting. The explicit formatter then changed exactly those two files; no
  analysis, native syntax, or unit result was claimed from the interrupted
  run. A clean repeat was required before focused runtime execution.
- Re-review found a stopped-state publication race in the first reducer
  rewrite. Reconciliation set `_state` to stopped, then yielded while
  cancelling port subscriptions, and only afterwards published its
  termination result. A concurrent first `shutdown()` could enter the stopped
  branch during that interval and cache a false graceful fallback. Spawn
  failure had the analogous state-before-result interval. The stopped branch
  must await the single termination future whenever a worker start allocated
  one; only a coordinator that was never started may synthesize graceful
  shutdown. This preserves both classification and completed port cleanup
  across the idle-crash/window-close race.
- Re-review also found that the barrier interval initially left new request
  admission open after authoritative `onExit`. A caller could therefore send a
  new operation to an already-dead worker before reconciliation closed ports;
  a simultaneous shutdown could also emit a redundant stop request. Admission
  now rejects as soon as exit is observed, while already-posted replies remain
  eligible for the event-channel drain. Shutdown detects an already-observed
  exit and awaits its existing reconciliation without sending stop.

### 2026-09-02 — review corrections and focused verification

- The corrected coordinator now routes every first `onExit` through one
  reducer and one termination future. Post-ready idle uncaught failure and
  clean exit are reconciled without another request; a throw while handling
  stop produces an uncaught worker outcome without timeout or redundant kill.
  Stop acknowledgement and exit race under the original shutdown deadline,
  and already-observed exit prevents new requests and stop sends while the
  event/error barriers drain prior evidence.
- Unit coverage now drives real isolates through idle uncaught, idle exit, and
  stop-processing crash. The pure evidence reducer additionally exercises
  error-before-exit and exit-before-delayed-error sequences and proves no
  classification is available until both event and error channel barriers,
  followed by uncaught, graceful, unexpected, stop-crash, and forced results.
- The C bridge header now uses C `<stdint.h>` and places all namespace,
  `constexpr`, and helper declarations behind `__cplusplus`. The permanent
  source target compiles it with strict C11 and strict C++20 syntax checks.
- Provenance inspection confirmed that the former actual-diff hash was only a
  receipt, not an exact allowlist. The new shared verifier reconstructs
  `engine.cc` from pinned `HEAD`, applies worker then lifecycle patches in a
  temporary repository, and requires its SHA-256 to equal the checkout file.
  The freshness fixture proves a non-overlapping extra edit still passes both
  individual reverse checks but is rejected by this exact composition gate;
  it never modifies the real Engine checkout.
- The clean post-review `runtime-source-check` passed: 32 Dart files required
  no formatting changes, all four native lifecycle sources passed formatting,
  both public-header syntax modes passed, both plists passed, analysis found no
  issue, and the complete unit harness passed.
- Rebuilt Apple arm64 developer JIT passed the expanded 15-case lifecycle
  suite. The three review cases completed as contained status-0 outcomes:
  idle uncaught in 253 ms, idle unexpected exit in 252 ms, and stop-processing
  uncaught in 236 ms. Forced shutdown remained status 75 in 526 ms; root/host
  fatal status 70 and usage status 64 remained stable.
- Rebuilt Apple arm64 release AOT passed the identical 15-case inventory and
  observation mapping. The three review cases completed in 190, 188, and
  179 ms respectively, and forced shutdown remained status 75 in 421 ms.
  Both builds first passed the new exact Engine patch-composition check.
- The full freshness regression passed with the new
  `extra_engine_edit_rejected=1` gate, then repeated every existing protected
  override, tool identity, spaced path, external path/response-file rejection,
  derived-input regeneration, stable no-op, forged package-root, and missing
  override gate without a stale artifact or hostile input execution.
- The complete post-review Apple arm64 `runtime-verify` gate passed. It
  repeated source formatting, strict C11/C++20 header syntax, static analysis,
  unit tests, exact-composition fingerprints, signed bundle audits, and normal
  AppKit smoke for developer JIT (1,285 ms) and release AOT (1,213 ms). It then
  repeated all 15 lifecycle scenarios in both modes: the new idle-uncaught,
  idle-exit, and stop-uncaught cases stayed contained, forced cleanup remained
  deterministic at status 75, fatal root/host paths stayed status 70, usage
  error stayed status 64, and every expected case passed.
- A second provenance review found that exact content composition still did
  not cover Git file mode. The verifier compared the reconstructed and actual
  `engine.cc` byte hashes, while the existing porcelain allowlist collapses a
  content modification and `chmod +x` into the same `M` status. Thus a
  mode-only hand edit could pass both patch reverse checks and the content
  equality gate even though the checkout was not the exact combined patch
  result. The selected correction will compare the tracked executable mode in
  addition to bytes and add a fixture that demonstrates a mode-only mutation
  is rejected. The already-running architecture matrix will be allowed to
  finish and recorded as a pre-correction result; source and provenance gates
  plus affected runtime validation will be repeated after this correction.
- The architecture matrix already in flight when that file-mode finding
  arrived completed successfully as a pre-correction reference. It passed the
  complete freshness and release-negative inventories, arm64 and x86_64 thin
  signed-bundle audits, Universal assembly/audit, arm64 developer JIT and
  release AOT smoke, Rosetta x86_64 developer JIT and release AOT smoke, and
  Universal arm64/x86_64 smoke. Intel-native handoff remained intentionally
  unverified under the Apple-Silicon-first priority. These results do not close
  the new provenance finding; affected gates will be rerun after its fix.
- The mode correction reconstructs the base file with its pinned Git mode,
  applies both patches, and compares both content SHA-256 and the normalized
  Git owner-executable mode (`100644`/`100755`) against the real checkout. The
  fixture restores byte-identical patched content, changes only its executable
  bit, proves the content hash and both patch reverse checks still pass, and
  requires the combined verifier to reject it. A focused fixture option avoids
  rerunning the expensive unrelated freshness inventory before re-review.
- The first direct formatter invocation reported zero changed files but then
  could not update Dart's user telemetry session outside the sandbox. That
  invocation is not counted as a clean gate; it will be repeated with analytics
  suppressed before analysis, unit, and the focused provenance fixture.
- The environment-only analytics suppression repeat encountered the same
  telemetry-session permission warning, so it was likewise not counted. The
  formal `runtime-source-check` was rerun with the established build
  permissions and passed cleanly: 32 Dart files unchanged, all native format
  checks, strict C11/C++20 header syntax, plist validation, static analysis,
  and the complete unit harness passed.
- The focused Engine patch-composition fixture passed. It reported
  `extra_engine_edit_rejected=1` for a non-overlapping byte edit and
  `engine_mode_edit_rejected=1` for byte-identical executable-bit drift. Both
  negative states first retained successful individual patch reverse checks;
  the latter also retained the exact patched content SHA-256.
- Independent re-review repeated that focused fixture, confirmed both negative
  rejections, and found no further issue in the base-mode reconstruction or
  normalized mode comparison. A final local source check and focused repeat
  also passed after normalizing the owner executable bit exactly as Git tracks
  it. Full final regression may now proceed.
- The final full freshness regression passed after the mode fix. Both exact
  composition negatives passed first, followed by all 92 protected Make
  overrides, hostile-input non-execution, SDK/runner/tool-identity checks,
  nine spaced-toolchain builds, 28 external/header/response/forwarding
  rejections with zero stale reuse, nine repetitions each of effective-input
  regeneration, package-config regeneration and stable no-op, plus forged-root
  and missing-override rejection. The several-minute quiet interval was
  inspected read-only and confirmed to be active isolated negative builds, not
  a hang.
- The final Apple arm64 `runtime-verify` passed with the post-mode-fix source
  inventory embedded in fresh JIT/AOT manifests. Source, exact fingerprints,
  signed audits, and normal AppKit smoke passed (developer JIT 2,090 ms;
  release AOT 1,675 ms), followed by the identical 15-case lifecycle suite in
  both modes. Idle and stop-time crashes remained contained, shutdown timeout
  remained status 75, root/host fatal paths remained status 70, usage remained
  status 64, and every case matched its expected ordered observations.
- The final post-mode-fix architecture matrix passed. It repeated source and
  full freshness gates, audited fresh arm64 and x86_64 developer JIT and
  release AOT thin bundles, assembled and audited both Universal bundles, and
  passed the release-negative inventory. AppKit smoke passed for arm64 JIT
  (1,375 ms), arm64 AOT (1,270 ms), Rosetta x86_64 JIT (5,023 ms), Rosetta
  x86_64 AOT (2,799 ms), Universal arm64 (1,813 ms), and Universal x86_64
  (2,403 ms). Intel-native handoff remains explicitly unverified and is the
  documented low-priority follow-up; it is not part of the Apple-Silicon-first
  baseline for this task.
- The final Phase 0 regression passed after all lifecycle and provenance
  corrections. It covered formatting, analysis, unit tests, developer JIT,
  root AOT main-thread attachment, worker throughput/fault containment, PTY,
  Metal, CoreText, IME, grid/parser performance, the Apple-M1 benchmark
  baseline, and the six-bundle arm64 signing/architecture audit. No Phase 0
  contract regressed.
- Final hygiene found only the intended task files in the root checkout and no
  staged changes. `git diff --check` passed; generated `.dart_tool/` and
  `build/` content remained ignored; no leftover freshness temporary
  directories, reject/original/profile files, debug markers, or credential-like
  material were found. The adjacent `dart_appkit` checkout remained clean at
  its original revision. The pinned Engine checkout still contained only the
  expected `engine.cc` modification, retained mode `100644`, passed whitespace
  inspection, and accepted reverse checks for both revision-pinned patches.
  The final exact-composition freshness run already proved its bytes and mode
  match precisely those two patches. Independent re-review closed with no
  remaining implementation, validation, documentation, or hygiene finding.
- The first staged-diff audit exposed one patch-serialization issue that an
  unstaged diff cannot see for a new file: the lifecycle patch contained two
  mandatory unified-diff context markers for otherwise empty source lines, so
  the outer repository diff reported those marker spaces as trailing
  whitespace. The Engine result itself had no whitespace issue. The patch was
  rewritten to delete and re-add the first empty source line and to use narrow
  non-empty context around both hunks, preserving the exact resulting
  `engine.cc` bytes and mode while leaving no whitespace-only patch-file line.
- The first narrowed hunk declaration undercounted one trailing context line;
  `git apply --reverse --check` rejected it as a fragment without a header.
  Correcting the source/target counts to four and seventeen made the patch
  valid. The real pinned Engine reverse check then passed, and the focused
  composition fixture reconstructed the pinned base, applied both patches
  forward, matched the exact expected bytes/mode, and again rejected both a
  non-overlapping byte edit and a mode-only edit. Its first sandboxed Dart
  invocation was blocked only by the external telemetry-session permission;
  the established authorized invocation passed. Because the patch file hash
  changed even though its applied result did not, source, freshness, arm64
  runtime, and complete architecture-matrix gates will be repeated before
  commit. Phase 0 need not be repeated after that exact-result proof: it does
  not fingerprint patch serialization, its Engine/runtime bytes are unchanged,
  and its immediately preceding complete run passed.
- The post-serialization `runtime-source-check` passed: 32 Dart files required
  no formatting change, all four native lifecycle files passed the project
  formatter, the public bridge header passed strict C11 and C++20 syntax,
  both plists passed, static analysis found no issue, and the full unit harness
  passed. Both cached and uncached whitespace checks then passed.
- The post-serialization full freshness regression passed. It repeated both
  exact-composition negative fixtures, all 92 protected Make overrides,
  hostile-input non-execution, SDK/runner/tool identity, nine spaced-toolchain
  builds, all 28 external/header/response/forwarding rejections with zero stale
  reuse, nine repetitions each of effective-input regeneration,
  package-config regeneration and stable no-op, and the forged-root and
  missing-override rejections.
- The post-serialization Apple arm64 `runtime-verify` passed. Fresh JIT and AOT
  fingerprints recorded lifecycle patch SHA-256
  `8f168b5b4334daa0a1d5765328e6d6d0b47946e780b26d85717ef3ce5e745161`;
  both signed bundle audits passed, as did normal AppKit smoke (JIT 2,220 ms;
  AOT 1,657 ms). The identical 15-case lifecycle inventory passed in both
  modes, including contained idle/stop crashes, timeout status 75, fatal
  root/host status 70, usage status 64, late-completion suppression, and
  idempotent shutdown.
- At 2026-09-02 22:57 JST, the post-serialization architecture matrix
  completed successfully. It repeated source and full freshness gates, fresh
  arm64/x86_64 JIT and AOT thin builds and audits, Universal assembly/audit,
  and every release-negative case. Smoke passed for arm64 JIT (2,822 ms),
  arm64 AOT (1,691 ms), Rosetta x86_64 JIT (6,605 ms), Rosetta x86_64 AOT
  (2,963 ms), Universal arm64 (1,829 ms), and Universal x86_64 (2,484 ms).
  Intel-native remained explicitly unverified under the documented
  Apple-Silicon-first priority. No post-serialization regression failed.
- The post-serialization final hygiene audit passed. Exactly the intended 21
  task files were staged; the cached and uncached whitespace checks were
  clean, with no unstaged or untracked file. The staged-name scan found no
  generated artifact and the staged-content scan found no credential-like
  material. Ignored build output remained outside the commit, and no
  freshness temporary directory or reject/original/profile artifact remained.
  `dart_appkit` was still clean; the pinned Engine still had only the expected
  mode-`100644` `engine.cc` modification, passed its own whitespace check, and
  accepted both patch reverse checks. The staged lifecycle patch hash exactly
  matched the value audited in every rebuilt manifest. `ROADMAP.md` still
  changed only this lifecycle item to complete and left the following native
  event wire-format task untouched.
- Independent re-review of the final staged patch serialization, validation
  record, and 21-file scope closed with no finding; the task is ready to
  commit.
