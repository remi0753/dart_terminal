# Control-D accepted without native exit investigation

- Status: pending
- Recorded: 2026-09-05
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
