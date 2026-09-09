# Phase 7 fullscreen runtime acceptance recovery record

- Status: resolved again on 2026-09-09

## Resurfaced condition

The 2026-09-09 scheduling/resource-budget `runtime-verify` passed its exact
100 MiB four-pane hierarchy in Developer JIT and Release AOT, then failed the
following Developer JIT restoration suite at the same external foreground
boundary described below. Two focused retries reported a visible window on a
concrete screen but `active=false`; real fullscreen entry produced no callback
within eight seconds, while PTY, worker, and native cleanup remained clean.

System Events access is authorized and can read the current frontmost process,
but a one-shot DartTerminal frontmost request did not change the application
snapshot. A bounded request-and-confirm loop never observed the test process as
frontmost before it exited. The multiple-pane final child therefore remains
incomplete. Resume with the existing recovery procedure when the managed
desktop can grant the launched bundle genuine foreground ownership.

The user then foregrounded the test window during retry. Focused Developer JIT
and Release AOT restoration passed, followed by two complete matrices in which
both restoration modes also passed. The foreground condition is therefore
cleared for this session. The later aggregate failure is tracked in
[`runtime-resource-close-sequence-blocker.md`](runtime-resource-close-sequence-blocker.md).

## Prior resolution

The user granted the required `System Events` desktop-automation permission in
the interactive session. A frontmost query then succeeded, both runtime bundles
reported active state, and real AppKit fullscreen enter/exit callbacks arrived.
The first successful transition exposed a separate consumer-ordering defect:
the completion frame after exit replaced the retained safe windowed frame. The
hierarchy adapter now consumes exactly one completion frame for a genuine
fullscreen transition, reprojects the application-owned safe frame on exit,
and continues to accept the following ordinary windowed frame.

Focused analysis and hierarchy coverage pass. The complete Developer JIT and
Release AOT restoration scenarios also pass with two generations, two tabs,
four panes, eight clean PTY owners, and zero retained Metal, text-input, native,
or lifecycle-worker resources. The final aggregate runtime gate subsequently
passed through its last resource and fault suites; the main task record and
roadmap parent are complete.

## Current ordered task

The completed `fullscreen、screen migration、restoration、reopen` parent remains
valid. Its transition gate briefly blocked aggregate verification for
`multiple pane の scheduling/resource budget`, then passed in both focused and
complete-matrix retries after the test window received foreground ownership.
The current ordered work is the final cross-pane evidence child in
`ROADMAP.md`.

## Historical blocking condition

The managed desktop session does not grant the launched application
active/frontmost ownership. The real AppKit window is visible and reports a
concrete screen, but a public fullscreen request never produces the native
enter-completion event within eight seconds.

The same condition is reproducible with direct executable launch and a fresh
LaunchServices bundle launch. Moving modern `NSApplication.activate` before
Dart startup and repeating it at window presentation did not produce active
state. A bundle-targeted activate Apple event returned success without changing
the result. Reading or setting the frontmost process through `System Events`
blocked on desktop-automation permission and was interrupted.

The installed macOS 26.5 SDK rejects the legacy force option under the required
warning-as-error build because `NSApplicationActivateIgnoringOtherApps` was
deprecated in macOS 14 and explicitly has no effect. A test-only bridge gate
using that option was therefore discarded rather than weakening warnings or
claiming a false acceptance.

## Historical impact

The fixture, parser gate, persistence path isolation, hierarchy convergence,
safe windowed-frame correction, cleanup correction, and focused Dart analysis
are implemented. The adjacent outer-frame contract fix is committed as
`3be1317 Honor outer frames during window creation` and its focused and complete
AppKit test gates passed.

However, a successful real fullscreen enter/exit is mandatory before the
fixture can validate screen migration, two-tab/four-pane persistence, Dock
reopen, fresh PTY/native/Metal/text-input ownership, and both runtime modes as
one product scenario. Developer JIT has not passed end to end and Release AOT
has not been attempted. The roadmap child and parent must remain unchecked.

## Recovery procedure used

Resume only in an interactive macOS desktop or UI-test runner that can make the
test bundle genuinely frontmost without deprecated no-op APIs. Then:

1. Run `DART_SUPPRESS_ANALYTICS=true CI=true make developer-jit-restoration`
   and require the real enter/exit milestones and complete restoration summary.
2. Run `DART_SUPPRESS_ANALYTICS=true CI=true make release-aot-restoration` and
   require the identical semantic summary and clean resource counts.
3. Run the focused/direct Dart suites, complete `make test`, runtime source and
   architecture audits, and `make runtime-verify` as specified in the main task
   memo.
4. Update README/feature evidence, mark only the final child and parent complete,
   review the exact diff, and create the per-task commit.

Do not replace the real fullscreen requirement with injected completion events;
typed injection is already used only for the synthetic destination-screen
observation after a real enter/exit cycle.
