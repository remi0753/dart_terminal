# PTY child reap ownership conflict

- Status: diagnosis complete; remediation pending
- Started: 2026-09-05
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 2 `Dart Process.start workerとnative PTY childのreap ownership競合を解消する`
- Predecessor: `docs/phase2/ctrl-d-accepted-no-exit-investigation.md`

## Purpose

Explain the deterministic Control-D freeze observed while a Dart-owned runtime
worker and a native `forkpty` child are alive in the same application process,
then define the boundary and regression needed for a safe remediation.

## Background

The prior investigation added content-free observations for tracked PTY writes,
kqueue process-exit readiness, `waitpid`, and exit publication. A subsequent
Developer JIT run supplied all of those observations and showed a different
failure than the previously fixed output-flood reactor starvation.

The observed processes were:

- application parent PID `58840`;
- native PTY/login-zsh PID `58843`;
- long-lived worker PID `58872`, started through Dart `Process.start`.

The worker was ready and remained active when Control-D was sent to zsh.

## Scope

- Classify the supplied event sequence and determine whether zsh exited.
- Inspect the native PTY reaping path and the pinned stock Dart macOS process
  implementation used by the application.
- Identify why existing tests did not reproduce the ownership conflict.
- Record a bounded remediation and its acceptance conditions.

## Out of scope

- This diagnosis does not implement or claim the reap-ownership fix.
- It does not modify the stock Dart Engine or depend on its private symbols.
- The unrelated InputMethodKit wake warning and terminal rendering work remain
  outside this task.

## Dependencies

- `dart_appkit` commit `35ac3b0`, which added ABI v3 PTY diagnostics.
- The stock Dart Engine source staged under
  `dart_appkit/.dart_tool/dart-engine/sdk` for the Developer JIT host.
- macOS `EVFILT_PROC`, `NOTE_EXIT`, and `NOTE_EXITSTATUS` behavior.

## Supplied-log classification

The event sequence establishes the following facts in order:

1. `eofWriteAccepted request_id=1`, `writeEnqueued`, `writeDequeued`, and
   `writeCompleted byte_count=1 queued_bytes=0` prove that byte `0x04` crossed
   the Dart API and was written successfully to the PTY master. This is not the
   previous queue/reactor starvation failure.
2. The correlated snapshot reported foreground process group `58843`, the
   login-zsh process group. `terminal_lflag=1219` has `IEXTEN`, `ISIG`,
   `ECHOCTL`, `ECHOE`, and `ECHOKE` set but not `ICANON`; this is consistent
   with zsh ZLE reading the byte itself at the interactive prompt. `VEOF=4`
   remains the configured canonical EOF character.
3. The first `waitpidResult waitpid_result=0` means the PTY reactor polled just
   before the child became waitable.
4. `processExitReady child_process_id=58843` is a kqueue `NOTE_EXIT`
   notification and proves that zsh then exited.
5. The immediately following `waitpidResult waitpid_result=-1 errno=10` is
   `ECHILD` on macOS: PID `58843` was no longer a waitable child of this
   process because another thread had already reaped it.
6. `dart_pty_macos` only marks `child_reaped_` and publishes `EXIT` after its
   own `waitpid(child, ..., WNOHANG)` returns the child PID. The `ECHILD` branch
   only logs the error, so no `exitPublished` or Dart `nativeExitObserved`
   follows and the session remains logically live.
7. During later close, state flags `11` mean `closing`, `close_started`, and
   `master_eof`; the `child_reaped` bit is absent. Master EOF is additional
   evidence that the slave side disappeared. SIGHUP and SIGKILL both fail with
   `errno=3` (`ESRCH`), confirming that PID `58843` no longer exists.
8. The graceful and final deadlines therefore expire only because the PTY
   state machine missed completion, not because zsh survived Control-D.

The later `queued_bytes=1` snapshot indicates a subsequent unflushed input byte
after master EOF. It should be cleared during terminal completion, but it does
not explain the missing exit: kqueue `NOTE_EXIT`, master EOF, `ECHILD`, and
`ESRCH` already establish that the process was gone.

## Root cause

The application has two independent child-process reapers in one Unix parent:

- `dart_pty_macos` starts zsh with native `forkpty` and calls
  `waitpid(child_pid, ...)` from its reactor thread.
- The stock Dart macOS runtime starts an `ExitCodeHandler` whenever a Dart
  `Process.start` child exists. Its thread calls PID-unrestricted
  `wait(&status)`, then looks up the returned PID in Dart's private
  `ProcessInfoList`.

When the runtime worker is alive, Dart's exit-handler thread is blocked in
`wait()` for any child. If zsh exits first, that thread may reap the PTY child.
The PID is not in `ProcessInfoList`, because it was created by `dart_pty_macos`,
so Dart discards the exit status. The PTY reactor then receives `NOTE_EXIT` but
gets `ECHILD` from `waitpid` and has no status from which to publish its exit.

This explains why the failure is now effectively deterministic in the real
application: the long-lived Dart worker keeps the broad Dart reaper active
throughout the interactive shell session. It also explains the older
intermittency: which waiter wins is a scheduling race.

## Why the existing verification missed it

- Native PTY tests do not embed the Dart VM, so no Dart reaper competes.
- Real-PTY Dart tests start zsh without keeping a separate Dart
  `Process.start` child alive at the instant zsh exits.
- Runtime integration shuts down and reaps the Dart worker before it begins
  normal PTY disposal. It therefore verifies both lifecycles sequentially,
  not a natural PTY exit while the Dart worker is still active.
- The suppressed-exit fault test suppresses the Dart-facing PTY callback after
  successful native publication; it does not model native `waitpid(ECHILD)`.

## Remediation design to verify

The smallest macOS-specific fix which preserves an unmodified Dart runtime is:

1. Register the PTY child kqueue filter with `NOTE_EXIT | NOTE_EXITSTATUS`, and
   retain the valid exit status delivered with the matching `NOTE_EXIT` event.
2. Prefer the PTY owner's successful `waitpid(child_pid, ...)` result. If and
   only if a verified matching `NOTE_EXIT` carrying exit status is followed by
   `ECHILD`, classify it as externally reaped, retain the kqueue status, mark
   child completion, drain the master, and publish exactly one exit event.
3. Do not treat a bare `ECHILD` as a successful exit. Without a matching
   kernel exit observation and valid status it remains a lifecycle error.
4. Rename or split internal `child_reaped_` state so diagnostics distinguish
   “reaped by this PTY owner” from “exit observed after external reap”.
5. Clear or reject pending writes once master EOF/child completion is known.

An architectural alternative is a single native process broker which owns and
reaps every child in the host. That is substantially larger and would also
replace the currently working Dart worker lifecycle. Modifying the Dart Engine
or binding to its private `ProcessInfoList` is not an acceptable library
boundary. The kqueue fallback is therefore the first design to validate.

## Completion conditions

- A deterministic test keeps a Dart `Process.start` child alive while a real
  clean `zsh -f` prompt receives Control-D.
- At least 24 repetitions observe write completion, kernel exit readiness,
  either PTY-owned reap or explicitly classified external reap, exactly one
  exit publication, output drain, and zero live native sessions.
- Separate normal-exit and signal-exit cases preserve their actual status.
- Developer JIT and Release AOT exercise natural PTY exit while the runtime
  worker is still alive, rather than only sequential worker/PTY shutdown.
- Existing worker exit/replacement, force-close, deadline, output-flood, and
  zero-orphan regressions remain green.
- No stock Dart Engine modification or private-runtime symbol dependency is
  introduced.

## Verification performed for this diagnosis

- Matched every supplied machine event to the ABI v3 field contract and native
  `PtySession.cc` state transition.
- Confirmed macOS errno values through the observed syscall context:
  `waitpid` error 10 is `ECHILD`; `kill` error 3 is `ESRCH`.
- Inspected the pinned stock Dart macOS `ExitCodeHandler`; it calls global
  `wait(&status)` and silently ignores a reaped PID absent from
  `ProcessInfoList`.
- Confirmed the application starts worker PID `58872` through `Process.start`
  and that the worker was active before Control-D in the supplied log.
- Ran a temporary minimal reproduction which kept a Dart-owned `/bin/cat`
  child alive, started a real native `zsh -f` PTY, and sent one tracked
  Control-D at its prompt. It deterministically produced
  `waitpid=0`, `processExitReady`, then `waitpid=-1 errno=10`; no
  `exitPublished` arrived within one second. The probe was removed after the
  run and left no product source or generated artifact in the task diff.
- Confirmed the macOS SDK exposes `NOTE_EXITSTATUS` specifically for returning
  child exit status with `NOTE_EXIT`; remediation suitability still requires a
  permanent concurrent regression satisfying the conditions above.

No executable code changed during this diagnosis, so implementation tests were
not rerun. Documentation syntax and repository diffs are checked before commit.
