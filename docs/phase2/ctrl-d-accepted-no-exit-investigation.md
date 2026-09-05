# Control-D accepted without native exit investigation

- Status: complete
- Started: 2026-09-05
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 2 `Ctrl-D write受理後のPTY停止原因を分離する`
- Predecessor: `docs/phase2/ctrl-d-pty-shutdown-recovery.md`

## Purpose

Determine why an interactive terminal can stop visible progress after one or
more accepted Control-D writes even though bounded shutdown now guarantees the
application process returns with a classified result.

## Confirmed failing observation

- One production Developer JIT run started PTY process `14976` and reached the
  normal running state.
- The run logged the InputMethodKit `IMKCFRunLoopWakeUpReliable` message before
  the first Control-D. This is correlation only; Dart subsequently processed all
  three Control-D events and two window-close requests.
- Three attempts each emitted `eofRequested` followed by `eofWriteAccepted`.
  No `nativeExitObserved`, output-drain, or termination event followed.
- Confirmed close began graceful shutdown, timed out, requested force close,
  exceeded the final deadline, cancelled Dart output, skipped native process
  disposal, and completed classified recovery with status 75.
- `eofWriteAccepted` currently means the bounded native write queue admitted
  `0x04`; it does not prove the reactor wrote that byte to the PTY master or that
  the active terminal discipline/foreground process interpreted it as EOF.
- `forceCloseRequested` similarly proves the Dart capability call returned
  without failure, but the supplied log has no later exit/reap notification.
  This makes a reactor/write/reap notification stall a live possibility in
  addition to ordinary zsh/foreground-process EOF semantics.

## Required investigation, in order

1. Add privacy-safe native PTY observations for write enqueue, reactor dequeue,
   write completion/error, force-close dequeue, signal delivery result, waitpid
   result, and exit callback publication. Do not log bytes or terminal content.
2. Record bounded snapshots of session state, queued byte count, foreground
   process group, and relevant termios flags/control-character identity without
   recording commands, environment, cwd, or user text.
3. Add a GUI-key-path regression that synthesizes Control-D through the AppKit
   event route rather than calling `TerminalSession.sendEndOfFile` directly.
4. Add deterministic real-PTY cases for an empty clean zsh prompt, `IGNORE_EOF`,
   a nonempty line, foreground stdin reader, changed/raw terminal mode, suspended
   jobs, and suppressed exit notification.
5. Reproduce the accepted-write plus missing-exit path under deadlines and use
   the last native observation to isolate queue starvation, TTY semantics,
   signal delivery, waitpid, callback publication, or display-only stalling.

## Implementation split and acceptance

The work is kept as one roadmap item but is implemented and verified in the
following dependency order:

1. Add an opt-in, content-free diagnostic stream with bounded emission per
   tracked operation to
   `dart_pty_macos`. A record carries only lifecycle stage, counters, process
   group/signal results, and terminal-mode metadata; it never carries input or
   output bytes.
2. Subscribe from `TerminalSession`, correlate the native write identifier with
   the Control-D request, and publish stable `TERMINAL_PTY_NATIVE` machine
   lines. The normal application enables this diagnostic stream; generic
   library consumers retain an off-by-default policy.
3. Add deterministic native/Dart tests for queue admission versus reactor
   flush, force-close dequeue, signal result, waitpid result, exit publication,
   bounded event emission, and privacy allowlisting.
4. Exercise Control-D through the product key dispatcher and cover the required
   real-zsh terminal states. Each case must assert whether exit is expected or
   whether the byte is validly consumed by line editing/terminal discipline.
5. Fix only a reproduced transport/reactor defect. Expected zsh behavior such
   as `IGNORE_EOF`, a nonempty edit buffer, or raw-mode consumers remains
   observable but must not be rewritten into unconditional application exit.
6. Re-run package, application, bundle, lifecycle, fault, and orphan checks,
   then close the roadmap item only if the observations distinguish all stated
   boundaries.

There is no native diagnostic backlog: fixed-size scalar observations use the
existing asynchronous event callback, and only explicitly tracked writes plus
close/reap boundaries emit them. Signal and `waitpid` results include `errno`
but no command, environment, cwd, terminal text, or byte content. Write
observations use counts and opaque monotonically increasing identifiers only.

## Investigation findings

### 2026-09-05 — task start and current boundary audit

- Native `dpty_session_write` copies a request into a bounded queue and returns;
  it does not wait for the reactor's `write(2)`. Therefore the existing
  `eofWriteAccepted` observation proves admission only.
- `dpty_session_force_close` likewise sets a flag and wakes the reactor. Signal
  delivery, `waitpid`, and EXIT callback publication currently have no public
  observations, and their system-call results are discarded or only consumed
  internally.
- The reactor uses edge-cleared read/write filters and drains each ready FD in
  an unbounded loop. A continuously readable or writable PTY can therefore
  monopolize a reactor turn before queued control work is processed. This is a
  concrete fairness risk to be covered by a deterministic regression before a
  fix is accepted.
- Control-D is byte `0x04`, not a process signal. At an interactive zsh prompt
  it is interpreted by ZLE; with a nonempty edit buffer it normally performs an
  editing action, and with `IGNORE_EOF` it intentionally does not exit. In
  canonical foreground readers it is interpreted through the current `VEOF`
  character, while raw-mode readers receive an ordinary byte. Those expected
  semantics must be separated from queue or reactor failure.

### 2026-09-05 — native observations and product correlation

- `dart_pty_macos` ABI v3 now provides tracked writes and opt-in scalar
  diagnostics. Dart Terminal uses tracked writes only for Control-D and adds the
  returned opaque request ID to `eofWriteAccepted`; ordinary typed text does not
  create diagnostic traffic.
- `TERMINAL_PTY_NATIVE` records write enqueue/dequeue/completion/error, queued
  byte count, foreground process group, session flags, `c_lflag`, `VEOF`,
  force-close dequeue, signal target/result/errno, kqueue process-exit readiness,
  `waitpid` result/status/errno, and native exit publication. Every field is a
  fixed numeric value or enum name. Native event pointers are null and no byte,
  command, environment, cwd, or terminal text crosses this diagnostic path.
- The reusable library keeps diagnostics disabled by default. TerminalSession
  explicitly enables and consumes them, cancels that subscription within the
  same final cleanup boundary as output, and isolates observer failures from PTY
  ownership.
- The AppKit key-down mapping is now a small shared `TerminalKeyEventRouter`.
  The product event listener and regression use the same decoded
  `AppKitKeyEvent` path; a synthetic control-modified key code 2 reaches exactly
  one pane EOF action without calling `sendEndOfFile` directly from the test.

### 2026-09-05 — reproduced transport defect and bounded fix

- The pre-change `dart_appkit` commit `6fa96b8` was extracted and built in a
  temporary clean tree. A real `/usr/bin/yes x` child continuously produced PTY
  output while the callback immediately acknowledged every batch. A force-close
  request issued after 100 ms did not complete within the 1-second bound. The
  probe had to send an external SIGKILL and reported
  `bounded=false elapsed_ms=1007`.
- This reproduced a reactor fairness defect: the old `ReadAvailable` drained a
  continuously readable nonblocking FD until `EAGAIN`, with no per-turn budget.
  It could remain inside that loop and never return to `ProcessControl`, so an
  accepted write and a later force-close flag could both wait indefinitely.
  This matches the important boundary missing from the supplied log, although
  that historical run did not record output rate and therefore cannot be
  retroactively proven to be this case rather than shell state.
- The reactor now reads at most eight 64 KiB batches per turn, wakes itself when
  read work may remain, and returns to control/reap processing. Write draining
  is also limited to eight calls or 512 KiB per turn. The same continuous-output
  probe then recorded `forceCloseDequeued` and `exitPublished` and completed in
  6 ms. The permanent native regression uses the same output-flood condition.
- Close signaling now derives the child's real process group, records each
  `kill(2)` result, and falls back to its PID when successful group delivery does
  not cover the child. This removes the previous unobserved group-only failure
  edge without changing foreground job-control behavior.

### 2026-09-05 — expected Control-D semantics matrix

Real PTY tests distinguish transport completion from shell exit:

- Empty clean `zsh -f` prompt with `IGNORE_EOF` unset: all 24 repeated sessions
  wrote the tracked byte, observed process-exit readiness, reaped the child,
  published exit 0, destroyed the native session, and left zero live sessions.
- `IGNORE_EOF` set: the tracked byte completed, but zsh intentionally remained
  live.
- Nonempty ZLE edit buffer: the tracked byte completed as a line-editing action;
  it was not shell EOF and zsh remained live.
- Foreground canonical `cat`: Control-D completed and ended the foreground
  reader, then zsh regained its prompt and remained live.
- Foreground raw-mode one-byte reader: Control-D was ordinary data, completed
  that reader, restored termios, and left zsh live.
- Suspended foreground job: zsh regained its prompt but refused the first EOF
  while the stopped job existed, then remained live for explicit cleanup.
- Suppressed Dart exit notification: both runtime modes observed native signal,
  process-exit readiness, reap, and `exitPublished`, while intentionally lacking
  `nativeExitObserved`; the application still reached its final deadline and
  exited with classified status 75. This proves the native-published versus
  Dart-observed distinction.

`writeCompleted` means `write(2)` accepted the byte at the PTY master. It does
not claim that ZLE, the line discipline, or a foreground process interprets the
byte as a request to exit.

### Classification using the new log

- `eofWriteAccepted` / `writeEnqueued` without `writeDequeued`: queued reactor
  work is stalled.
- `writeDequeued` without `writeCompleted` or `writeError`: native write
  processing is the last boundary.
- `writeCompleted` followed by `waitpidResult=0`, with no process-exit-ready
  event: the byte reached the PTY but the foreground process/shell remains live;
  inspect the accompanying foreground/termios snapshot as expected semantics.
- `processExitReady` without a reaped child PID in `waitpidResult`: exit was
  reported by kqueue but reaping did not complete.
- A child PID in `waitpidResult` without `exitPublished`: reaping completed but
  native callback publication did not.
- `exitPublished` without `nativeExitObserved`: the native callback boundary or
  its Dart consumer is stalled/suppressed.
- `nativeExitObserved` with a stale window: process lifecycle completed and the
  remaining defect is display/event projection rather than PTY termination.
- A force timeout can be placed at the same precision using
  `forceCloseDequeued`, the subsequent SIGKILL target/result, process-exit-ready,
  `waitpidResult`, and `exitPublished` observations.

### Verification and closure

- `dart_appkit make dpty-native-test dpty-dart-test` and the complete
  `dart_appkit make test` passed, including warning-clean C11/C++20 builds,
  output-flood fairness, tracked diagnostics, real FFI delivery, and all existing
  AppKit/runtime/renderer regressions.
- Dart Terminal `make test` passed format, analysis, fake lifecycle, the decoded
  AppKit Control-D route, the five non-exiting real-PTY semantics cases, and all
  24 clean-prompt natural exits with write/reap/publication assertions.
- `make RUNTIME_ARCH=arm64 runtime-verify` passed. The source audit found 80
  tracked application files and zero native application sources. Fresh
  Developer JIT and Release AOT normal integrations passed in 2,452 ms and
  1,814 ms. All lifecycle statuses, 384 deterministic traffic backpressure
  observations per mode, and 1,000-iteration resource suites (baseline 12,
  peak 14) remained stable.
- Shutdown fault suites passed in both modes. Suppressed PTY exit notification
  remained bounded and classified as status 75 in 1,962 ms (Developer JIT) and
  1,829 ms (Release AOT), with the new native publication evidence required.
- The user separately confirmed the key-routing change removed the audible
  per-key beep. The InputMethodKit wake message remains correlation only and is
  not on the accepted-write/reactor/reap chain established here.

## Completion criteria

- Every accepted Control-D can be classified as not yet flushed, flushed but
  consumed without shell exit, shell/child exited but not reaped, reaped but not
  published, or display-only delay.
- Force close either produces signal/reap/exit observations within its deadline
  or records the exact native boundary that failed.
- The reproduced root cause has a minimal regression and a bounded fix; expected
  shell semantics remain distinct from a transport/reactor defect.
- Developer JIT and Release AOT fault and normal integrations retain their
  classified shutdown and zero-orphan guarantees.

## Post-closure correction — concurrent Dart process reaper

A subsequent real application log proved an additional exit-ownership race
which the original test matrix did not exercise. The PTY received and wrote
Control-D, kqueue reported `NOTE_EXIT`, and the following `waitpid` returned
`ECHILD`. The long-lived worker started through Dart `Process.start` was active
at the same time. The stock Dart macOS exit handler uses process-wide `wait()`
and can therefore reap the native `forkpty` child before `dart_pty_macos` does;
because that PID is absent from Dart's private `ProcessInfoList`, its status is
discarded. Details and remediation acceptance are recorded in
`pty-child-reap-ownership-conflict.md`. The earlier reactor-starvation finding
and fix remain valid, but do not cover this distinct failure.
