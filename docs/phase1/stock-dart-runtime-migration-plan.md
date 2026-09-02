# Stock Dart Runtime Migration Plan

- Status: frozen execution contract; steps 1–6 complete, M1 closeout next
- Primary environment: macOS on Apple Silicon (M1/arm64)
- SDK baseline: Dart 3.13.2 revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`
- Evidence log: [`unmodified-dart-engine-hosting.md`](unmodified-dart-engine-hosting.md)

## Goal

Replace the current Dart Engine patch-dependent worker implementation with the
best implementation that uses published, unmodified Dart inputs. After the
replacement passes its gates, delete the patch files and every build,
provenance, audit, and test path that treats a patched Engine as valid.

## Non-negotiable invariants

1. Dart SDK and Dart Engine source are immutable. The selected build may not
   apply a patch, carry a local SDK commit, depend on a fork, or edit generated
   or checked-in Dart source.
2. A custom embedder may use documented public C interfaces from the published
   SDK. It may not include `runtime/bin` or other private implementation
   headers, call private symbols, or copy private setup/cleanup routines into a
   product repository.
3. The configured SDK checkout must be the exact published revision with an
   empty worktree before and after every accepted build and test.
4. AppKit owns the macOS process main thread. Dart work outside the UI domain
   must not call AppKit directly.
5. Correct lifecycle ownership is mandatory: ready, request/reply, graceful
   stop, uncaught error, forced stop, replacement, late-message safety, and
   bounded final cleanup must all have authoritative outcomes.
6. M1/arm64 Developer JIT and Release AOT are the primary acceptance lanes.
   x86_64 and Universal are retained as lower-priority compatibility work and
   may not delay the arm64 replacement.
7. The task order and decision rule below are fixed. New observations are
   added to the evidence log; they do not create a new implementation branch.

## Current evidence, normalized

| Route | Actual validation state | Fixed disposition |
| --- | --- | --- |
| Full product-owned embedder through public `dart_api.h`-family interfaces | Implemented in `dart_appkit` as a complete public-only VM owner and exercised on M1/arm64 in both JIT and AOT. Root creation, synchronous Dart, and cleanup passed; `Platform.script`, microtasks, and worker lifecycle could not be initialized without unexported `runtime/bin` bootstrap. | **Closed/rejected.** The actual full-host proof is complete; do not replace the missing bootstrap with private code. |
| Multiple stock `DartEngine_CreateIsolate` roots | JIT/AOT creation, ports, errors, replacement creation, bulk transfer, and global shutdown passed. The public Engine API cannot retire/unregister one root, so dynamic workers accumulate until process exit. | **Closed/rejected** for pane-owned workers. Do not repeat. |
| Public `Dart_CreateIsolateInGroup` hybrid under stock `dart_engine` | JIT/AOT lifecycle mechanics worked, but child microtasks and original uncaught-error diagnostics failed because the Engine installed no child initializer. | **Closed/rejected.** Do not use private setup helpers or weaken semantics. |
| Modified Engine, whether patch or normal SDK commit | A general prototype passed broad Engine tests. | **Prohibited by invariant**, regardless of technical quality. |
| Official Dart/AOT executable as the same-process AppKit host | JIT/AOT Dart entrypoints were not on the process main thread; the process main dispatch queue was not serviced during bounded probes. | **Closed/rejected.** |
| Official Dart executable/AOT worker process | JIT/AOT ready, IPC, 128 MiB transfer, graceful exit, uncaught failure, forced termination, and replacement passed on arm64. | **Accepted fallback** if the full public embedder fails. |

## Fixed decision rule

1. Implement a minimal, complete `dart_appkit` host that owns VM
   initialization, isolate initialization, scheduling, snapshots, and cleanup
   through documented public SDK C interfaces only.
2. Accept that host only if it passes every required M1/arm64 JIT and AOT gate:
   AppKit-main-thread root; ordinary `Isolate.spawn`; `Future`, microtasks, and
   `Platform.script`; normal/error/forced/replacement lifecycle; bounded
   shutdown with a live child; repeated shutdown safety; and a clean SDK.
3. If any required behavior needs a private Dart helper or cannot be completed
   through the published interface, record the exact missing contract and
   reject the host. Do not partially adopt it and do not reduce the acceptance
   criteria.
4. On rejection, select the already validated official Dart/AOT process worker.
   No further architecture candidates are introduced.

## Applied selection

The full public host failed mandatory JIT and AOT gates, so the fixed rule was
applied once on 2026-09-03. The selected topology is:

- the macOS UI process keeps one process-lifetime root isolate in the stock,
  unmodified `dart_appkit` Engine host;
- every independently recoverable terminal worker domain runs in a distinct
  official Dart child process;
- Developer workers use the exact official Dart SDK executable, while Release
  workers use a reusable self-contained AOT executable produced by that SDK;
- Dart Terminal owns PID and stdio streams, versioned binary framing,
  generation checks, buffering/backpressure, diagnostics, deadlines, signals,
  process reaping, and replacement;
- a protocol acknowledgement is not cleanup. Drained diagnostics plus observed
  process exit is the authoritative worker-resource boundary;
- after every worker is reaped, the UI host shuts down its one stock Engine
  root and immediately exits the containing process. It neither claims
  VM-wide `Dart_Cleanup` nor reinitializes Dart in that process.

This selection is final for the migration. A future upstream Dart release may
motivate a separately planned review, but it does not reopen a rejected route
or allow a local Dart modification here.

The selected generic host contract is fixed at adjacent `dart_appkit` commit
`77e355387a0ea50034632d9e3d4b35f629155c35`. That commit keeps the production
Runner on one stock Engine root, makes the SDK clean-tree check fail closed,
adds the public-host JIT/AOT decision probe without linking it into production,
and assigns all terminal worker supervision to Dart Terminal.

## Ownership after selection

| Responsibility | Owner |
| --- | --- |
| AppKit process-main-thread loop, native UI objects/events, one stock Engine root and process-lifetime shutdown contract | `dart_appkit` |
| Generic public-host conformance and stock-SDK cleanliness checks | `dart_appkit` |
| Terminal worker program, terminal request protocol, pane recovery policy, application packaging | Dart Terminal |
| Worker process supervision, framing, backpressure, diagnostics, termination and reaping | Dart Terminal |
| Dart VM, SDK, Engine, public headers and published artifacts | Upstream Dart, consumed without modification |

## Fixed implementation order

1. **Public embedder proof in `dart_appkit`.** Build the smallest full host and
   run the complete M1/arm64 JIT/AOT gate. End with one explicit accept/reject
   decision.
2. **Architecture lock.** Apply the fixed decision rule once and record the
   selected topology and ownership. No rejected route is reopened.
3. **Host implementation.** Complete the selected `dart_appkit` changes. If the
   process fallback was selected, limit AppKit changes to the stock-Engine
   contract and put terminal-specific process ownership in Dart Terminal.
4. **Developer migration.** Move the Dart Terminal M1 Developer JIT path to the
   selected host and pass lifecycle/integration gates.
5. **Release migration.** Move the M1 Release AOT path to the same semantic
   contract and pass bundle/runtime audits.
6. **Patch removal.** Delete both patch files and remove patch application,
   hashes, composition checks, patched-Engine status allowances, manifest
   fields, freshness fixtures, and documentation that prescribes patches.
7. **M1 closeout.** Run cross-mode lifecycle, failure, shutdown, performance,
   source-diff, package, and clean-SDK gates. Record exact results.
8. **Compatibility follow-up.** Run x86_64/Rosetta/Universal work after the M1
   path is complete; retain any unavailable lane as an explicit later item.

## Completion condition

The immediate migration is complete only when both M1 modes use the selected
unmodified-Dart topology, the two patch files and all operational patch
machinery are gone, the SDK checkout is pristine, and all affected tests and
audits pass. Historical documents may retain past evidence, but must be marked
as superseded where they previously prescribed a patched Engine.
