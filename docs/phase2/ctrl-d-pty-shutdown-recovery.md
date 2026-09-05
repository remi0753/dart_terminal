# Ctrl-D and bounded PTY shutdown recovery

- Status: in progress
- Started: 2026-09-05
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 2 `Ctrl-D / PTY shutdown hang の bounded recovery`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`, and
  `docs/phase2/persistent-pane-lifecycle.md`

## Purpose

Eliminate the intermittent shutdown path in which Control-D stops visible
terminal progress, a subsequent confirmed window close removes the window, and
the application process remains alive. Preserve the existing pane ownership
contract while making shell EOF, PTY close escalation, child reaping, and final
application termination observable and bounded.

## Background and confirmed incident

- A user-observed Developer JIT run used application PID `40399`. Control-D did
  not close the terminal and the visible view stopped progressing. Two later
  window close requests were both delivered: the first was rejected as
  `confirmation-required` and the second was allowed in `closing` state.
- After the window closed, the runtime worker received its stop request,
  acknowledged it, and was reaped. The run did not emit the later `root-exit`
  or `Dart Terminal shut down cleanly.` records. The privacy-safe local metadata
  for the same PID was preserved as `outcome=running` and
  `phase=shutdown-started` on the next launch.
- This ordering rules out loss of the two close requests and narrows the stall
  to cleanup after runtime-worker shutdown. The first materially blocking owner
  in that section is `TerminalPaneOwner.dispose`, which awaits the terminal
  session and native PTY.
- Control-D is currently written as byte `0x04`; it is not a signal. Whether it
  exits an interactive shell depends on the foreground program and shell input
  state. Regardless of whether the shell accepts EOF, a confirmed window close
  must still complete within a fixed deadline.
- `TerminalSession.dispose` currently waits three seconds, tries to send
  `PtySignal.kill`, and then calls `PtyProcess.dispose`. Native `SendSignal`
  rejects every signal after `Close` has set `closing_`, while Dart's final
  `PtyProcess.dispose` awaits `exit` without a deadline. The combination leaves
  a concrete unbounded recovery path.
- The InputMethodKit `IMKCFRunLoopWakeUpReliable` message appeared in the
  incident, but later close and worker lifecycle events were still processed.
  It is therefore correlation evidence only, not an established cause.

## Ordered subtasks

1. Add a repeated real-PTY Control-D natural-exit regression test. It must use
   an interactive `zsh -f`, wait for a deterministic ready prompt, send exactly
   one `0x04`, require exit/reap within a per-iteration deadline, and leave zero
   native sessions across repeated generations.
2. Add privacy-safe pane/PTY shutdown-stage diagnostics. They must identify the
   pane/session and lifecycle stage without recording terminal text, commands,
   environment, cwd, or exception detail, and make a future stall's last
   completed boundary visible.
3. Add a reusable `dart_pty_macos` force-close API that remains valid after
   graceful close has begun, is idempotent, and causes the reactor to request
   immediate SIGKILL/reap without synchronous waiting.
4. Give terminal session exit/reap and native process disposal a final bounded
   deadline. Timeout paths must stop awaiting the unresolved `exit` future and
   publish a typed shutdown result rather than silently claiming a clean reap.
5. Make application termination deterministic after that deadline. A confirmed
   close must reach host termination even if the PTY callback never arrives;
   the run must be classified as forced/failed, preserve diagnostic evidence,
   and pass Developer JIT and Release AOT integration gates.

Every subtask is implemented in this order and receives its own documentation,
roadmap update, focused validation, and completion commit. The parent remains
open until all five are complete.

## Scope

- Real interactive zsh EOF regression coverage in the reusable PTY package and
  product session boundary.
- Privacy-safe stdout lifecycle observations suitable for integration tests.
- Additive C ABI and Dart facade support for asynchronous forced PTY close.
- Bounded session teardown and application-level forced-shutdown
  classification in both runtime modes.
- Focused native, Dart, fake-backend, real-PTY, GUI integration, bundle, and
  source-boundary validation.

## Out of scope

- VT parsing, screen grids, scrollback, renderer scheduling, and correction of
  the temporary TextView projection; those remain in Phases 3 through 5.
- Changing zsh's standard Control-D semantics or forcing EOF to mean exit while
  another foreground application owns the terminal.
- Foreground-process-aware confirmation UI, multiple panes, tabs, or splits.
- General crash reports, hang sampling, telemetry upload, or long-duration
  soak infrastructure from Phase 11.

## Dependencies and ownership

- `dart_terminal` owns pane policy, shutdown deadlines, application outcome,
  and product integration diagnostics.
- `dart_pty_macos` owns nonblocking PTY mechanics, process-group signals,
  reactor state, `waitpid`, and its public Dart/native capability contract.
- `dart_macos_runtime` owns final host exit status and existing local-run
  metadata. No application-native source is added to `dart_terminal`.
- AppKit main-thread code must never synchronously wait for PTY I/O or reaping.

## Acceptance criteria

1. Repeated real interactive zsh sessions accept an empty-prompt Control-D and
   reach exit, stream completion, destroy, and zero live native sessions within
   fixed deadlines.
2. Normal EOF, natural exit, confirmed close, graceful close, force close,
   timeout, and final application termination have ordered privacy-safe stage
   records in tests and product integration.
3. Force close is accepted before or after graceful close, is idempotent, and
   never performs a synchronous join on the caller thread.
4. No Dart future in the pane-owned shutdown path can wait indefinitely for a
   missing PTY exit/reap callback. Clean and forced/unreaped outcomes remain
   distinguishable.
5. A confirmed window close reaches process termination within the integration
   deadline in Developer JIT and Release AOT, including a deterministic missing
   PTY-exit fault. The non-clean case has a nonzero classified status and the
   runtime worker is still reaped.
6. Existing persistent-shell, job-control, native lifecycle, resource,
   packaging, source-audit, and shutdown-fault contracts continue to pass.

## Validation strategy

- Add focused real-PTY repetitions and native capability tests with short,
  explicit per-iteration deadlines; never use an unbounded test wait.
- Extend deterministic fake PTY behavior to model delayed/missing exit and
  assert graceful-close/force-close ordering without sleeps.
- Add integration-only fault admission behind an existing-style environment
  gate so production command-line users cannot select it.
- Validate format, analysis, package tests, product tests, native header/source
  audits, `git diff --check`, and the complete arm64 `runtime-verify` suite.
- Inspect both repositories before each commit and include only the current
  subtask's files. Cross-repository changes receive corresponding commits in
  each owning repository.

## Risks and design constraints

- A timeout cannot prove that an OS process has been reaped. Diagnostics and
  exit status must describe this honestly; they must not report clean shutdown.
- Force-closing only the direct child is insufficient when foreground or shell
  process groups differ. Native mechanics must preserve current group handling
  and make escalation repeatable after close begins.
- Destroying a native session while its reactor can still callback would cause
  use-after-free. Bounded Dart waiting therefore cannot simply free an
  unfinished native session; ownership must be detached safely or left to a
  host-level final teardown contract.
- Repeated real shell tests must disable user startup files and use a controlled
  environment so they test EOF transport rather than local shell policy.
- Diagnostic events must not include terminal output or user command content.

## Work log

### 2026-09-05 — contract and incident triage

- Re-read the repository goals, Phase 2/3 boundary, feature matrix, ownership
  ADRs, persistent-pane record, both repository trees, current worktrees, PTY
  public API/native reactor, application cleanup order, and existing tests.
  Both worktrees were clean at `890d39b` (`dart_terminal`) and `05042a5`
  (`dart_appkit`).
- Confirmed from the supplied event sequence that AppKit delivered both close
  decisions and that the application entered its `finally` cleanup. The
  runtime worker completed before the stall, so parser/render work cannot by
  itself repair this lifecycle failure.
- Selected a Phase 2 regression task before the first Phase 3 item because the
  completed Phase 2 contract already requires deterministic EOF, close, and
  reaping. The user-requested order is retained as five explicit subtasks.
- No product or dependency implementation was changed during this planning
  step.

### 2026-09-05 — repeated Control-D regression test

- Added a product-level real-PTY regression that creates 24 sequential
  interactive `zsh -f` generations. Each uses a controlled environment, turns
  terminal echo off, explicitly clears `ignoreeof`, waits for a unique executed
  ready marker, sends exactly one `0x04`, and places independent deadlines on
  start, termination, and post-exit disposal.
- Every generation requires exit code zero, exactly one owner termination
  notification, and `dpty_debug_live_session_count() == 0` before the next
  generation. This covers the public native-asset mapping and the same
  `TerminalSession.sendEndOfFile` path used by the GUI.
- The first `make test` attempt did not reach project validation because the
  sandbox denied Dart's attempt to update its user-level analytics session
  timestamp. This is an environment write restriction rather than a product or
  test failure; rerun validation with analytics suppressed in the environment.
- The first analytics-suppressed analysis found that a marker string used
  `$iteration__`, which Dart correctly parsed as the nonexistent identifier
  `iteration__`. Delimiting the interpolation as `${iteration}` fixes the test
  source without changing its behavior.
- A second sandboxed run still attempted the same user-level analytics
  timestamp update even with analytics-suppression and CI environment flags.
  The repository format step itself passed. The focused suite therefore needs
  to run with the already-installed Dart toolchain outside that filesystem
  restriction; no network access or dependency change is required.
- The unrestricted `make test` rerun completed in 9.7 seconds: dependency
  resolution, formatting of 33 Dart files, static analysis, existing fake and
  real PTY coverage, and all 24 Control-D generations passed. Each generation
  reached clean exit and zero live native sessions inside its deadline.
- The normal repeated EOF path did not reproduce the intermittent stall. That
  is useful negative evidence: later subtasks must retain deterministic
  missing/delayed-exit fault coverage rather than relying on random repetition
  to exercise the recovery path.

### 2026-09-05 — pane and PTY lifecycle diagnostics

- Added typed, optional lifecycle observers for pane state and terminal-session
  shutdown stages. Observer failures are contained and cannot change pane
  ownership, PTY state, or close decisions.
- Product output now records `TERMINAL_PANE_LIFECYCLE` with pane/session identity
  and state, plus `TERMINAL_PTY_LIFECYCLE` with pane/session identity, process
  ID, and a fixed stage name. No terminal bytes, input text, command,
  environment, cwd, or exception description is included.
- PTY observations distinguish start request/process start, EOF request and
  accepted/backpressured/ignored write, native exit, output drain,
  owner-notification, dispose start, graceful close, termination wait outcome,
  output cancellation, process disposal, and completed disposal. A future hang
  therefore leaves a precise last-completed boundary; the reported incident
  would distinguish an unreceived native exit from an uncompleted process
  dispose.
- Pane tests assert the complete first-pane state order and exact privacy-safe
  machine line. Session tests assert ordered stages across fake natural exit and
  every real Control-D generation. The GUI smoke now requires the pane and PTY
  diagnostic subsequences through `closed` / `disposeCompleted` for the same
  typed identity.
- `make test` completed in 11.9 seconds with format, analysis, fake tests, real
  persistent PTY, and 24 Control-D generations passing. Fresh arm64 Developer
  JIT and Release AOT builds then passed their GUI integration smoke in 2,180
  ms and 1,773 ms respectively, including the new exact lifecycle assertions.
