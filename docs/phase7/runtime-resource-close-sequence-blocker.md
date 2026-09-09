# Phase 7 full-matrix Release AOT resource close blocker

- Status: resolved on 2026-09-09
- Parent: `multiple pane の scheduling/resource budget`
- Ordered position: after cooperative PTY turn yielding and before final
  cross-pane evidence

## Purpose

Recover deterministic Release AOT resource-fixture shutdown after the complete
runtime matrix without weakening foreground-process confirmation, aggregate
Quit behavior, or resource ownership checks.

## Confirmed reproduction

Two consecutive `make RUNTIME_ARCH=arm64 runtime-verify` attempts passed normal
tests, analysis, source and bundle audits, smoke/display integration, the exact
100 MiB four-pane fairness hierarchy, both real fullscreen restoration modes,
clipboard, lifecycle, traffic, and Developer JIT resource stress. Both then
timed out in the Release AOT resource fixture at the same point.

The Release process completed its native churn with exactly
`iterations=1000 baseline=33 peak=35 final=33`, scheduled auto-close after one
second, and emitted one pane transition to `confirmationPending` plus one
`decision=confirmation-required`. It emitted neither the intended second close
decision nor session/worker/native shutdown before the outer 60-second limit.
Timeout cleanup left no DartTerminal or runtime-worker process.

A focused `make RUNTIME_ARCH=arm64 release-aot-resource` between the aggregate
attempts passed with the same counts in 14571 ms. The defect is therefore
sequence-sensitive; it is not a failed native-resource bound, a persistent PTY
leak, the resolved fullscreen foreground condition, or a focused Release AOT
failure.

A subsequent `make RUNTIME_ARCH=arm64 runtime-resource-integration` also passed
Developer JIT and Release AOT sequentially (18318 ms and 17604 ms). The
immediate Developer-resource predecessor is therefore insufficient to trigger
the failure; an earlier full-matrix side effect or timing condition is required.

## Root cause and correction

The normal product fixture schedules one auto-close timer. Its callback invokes
the close menu action, then creates a 100 ms timer intended to invoke aggregate
Quit if the window remains open. In the failing output the first action reaches
the pane confirmation state, but no evidence from the second request appears.
Inspection identifies an ordering race. If the first menu and native
close-request events have not reached Dart before that timer fires, the second
menu action reaches native while its first close operation is still pending.
The native bridge correctly suppresses a duplicate pending close, so only one
Dart close event is eventually published and the pane remains at its first
confirmation. The failing log ending after that decision and the absence of a
leak are consistent with this ordering.

Resource-gated, content-free milestones cover the initial timer, both native
menu action requests, each close-request decision, the native close reply, and
the confirmation timer. The correction starts the 100 ms confirmation delay
only after Dart has handled the first event and returned `allow=false` to
native, when no pending native operation remains. The runtime driver requires
the exact milestone order, including the first decision before the second
action and the allow decision after it.

Do not make resource tests force-close unconditionally, disable the real
foreground-risk snapshot, lengthen the outer timeout as a substitute for the
missing second event, or accept a focused-only pass.

## Resume and completion conditions

1. Reproduce the minimal preceding sequence that distinguishes the aggregate
   failure from focused success and capture content-free timer/menu milestones.
2. Add deterministic coverage for the missing second close request and preserve
   the existing confirmation-required then allow transition.
3. Pass focused Release AOT resource coverage and sequential Developer
   JIT/Release AOT resource integration.
4. Pass the complete arm64 `runtime-verify`, including both 100 MiB hierarchy
   and real fullscreen restoration modes, with zero retained owners.
5. Update the main task record, generated evidence, roadmap state, and commit
   this recovery independently before final parent acceptance.

## Verification result

- `make test` passed all compatibility/freshness gates, formatting of 207 Dart
  files, whole-project analysis, and the aggregate Dart runner.
- `make RUNTIME_ARCH=arm64 runtime-resource-integration` passed with the exact
  close-milestone assertion in both modes: Developer JIT completed in 17969 ms
  and Release AOT in 17890 ms, with `baseline=33 peak=35 final=33`.
- The corrected complete `make RUNTIME_ARCH=arm64 runtime-verify` passed. Its
  hierarchy measured Developer JIT 26156/31536 microseconds (0.830x) and
  Release AOT 20491/25153 microseconds (0.815x). Both fullscreen restoration
  modes, the formerly blocked Release AOT resource case (17913 ms), and all
  final shutdown-fault/deadline cases completed with clean ownership.
- The runtime driver now rejects any resource run that does not report the
  exact initial timer, first request/decision/reply, confirmation timer, second
  request/decision/reply sequence. The fixed delay therefore cannot regress to
  wall-clock timing before native has cleared its pending operation.
