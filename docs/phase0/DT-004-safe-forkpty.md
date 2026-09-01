# DT-004 — safe forkpty, exec, and job-control spike

- Status: accepted
- Date: 2026-08-31
- Scope: Phase 0 feasibility gate
- Related decisions: ADR-001 and ADR-002

## Question

Can a native adapter create a real interactive PTY from the multi-threaded Dart
VM process, immediately exec zsh through an auditable post-fork child path, and
correctly handle controlling-TTY behavior, resize, terminal-generated signals,
exit status, and child reaping?

This is process substrate for an independently implemented Dart terminal
emulator. No Ghostty code or terminal core is linked.

## Acceptance criteria

1. `forkpty` starts `/bin/zsh -f -i` with a real controlling terminal.
2. All argv, environment, window size, and exec-error resources are prepared
   before `forkpty`.
3. After `forkpty` returns zero, project child code calls only
   `close`, `execve`, errno access, one fixed-size `write`, and `_exit`.
4. Child code has no Dart, Objective-C, C++, allocator, logging, dispatch, or
   lock dependency.
5. The shell observes interactive TTY stdin/stdout.
6. `TIOCSWINSZ` changes `stty size` from 24x80 to 43x132.
7. PTY byte `0x03` interrupts a foreground `sleep`, and zsh reports status 130.
8. `exit 37` is returned by `waitpid`; no zombie is left to global SIGCHLD
   handling.
9. Every operation has a deadline and the failure path sends HUP, escalates to
   KILL if needed, closes descriptors, and reaps the exact child PID.
10. Five consecutive real-hardware repeat runs pass.

## Implementation

The boundary is split so the critical child object can be audited separately:

- `native/macos/phase0/pty/PtySpawn.c` prepares an `FD_CLOEXEC` error pipe,
  calls `forkpty`, and handles only the parent branch after the child dispatch.
- `native/macos/phase0/pty/PtyExecChild.c` is compiled as C11 with
  `-fno-stack-protector`. Its no-return child function closes the read end,
  calls `execve`, writes a four-byte errno only if exec fails, and calls
  `_exit(127)`.
- `native/macos/phase0/pty/PtyPortBridge.cc` owns parent-side kqueue readiness,
  nonblocking reads/writes, resize, marker validation, deadlines, and exact-PID
  `waitpid`.

The child receives pointers to already prepared stack/vector storage copied by
`fork`; it does not build strings, inspect Objective-C state, enter Dart, log,
or allocate. `forkpty` itself performs the platform's PTY/session setup. The
project-controlled branch after it returns zero is a single call into the
audited C child object followed by no return.

An `FD_CLOEXEC` pipe distinguishes successful exec (EOF) from a failed exec
(fixed errno record). The master FD is nonblocking and registered with kqueue
using `EVFILT_READ`; the exact child is also registered with `EVFILT_PROC` and
`NOTE_EXIT`.

The interactive scenario disables echo before sending markers, preventing the
shell's input echo from falsely satisfying an output assertion. It then checks:

```text
[[ -t 0 && -t 1 && -o interactive ]]
TIOCSWINSZ → stty size == "43 132"
sleep 30 → PTY VINTR byte 0x03 → $? == 130
exit 37 → waitpid exit status == 37
```

## Child-path audit

`tool/phase0/audit_pty_child.dart` rejects every undefined symbol outside a
small allowlist and verifies the expected child entry symbol. The accepted
object reports exactly:

```text
___error
__exit
_close
_execve
_write
```

`___error` is macOS thread-local errno access. The object has no stack-canary,
allocator, Objective-C runtime, Dart, dispatch, pthread-lock, locale, dynamic
loader, or logging symbol.

Disassembly also confirms that the `forkpty` zero-result branch in
`dt_pty_spawn` loads the five prebuilt arguments and calls
`dt_pty_exec_child`; it does no intervening project work. The child object then
has the call sequence `close → execve → errno → write → _exit`.

Reproduction:

```sh
make phase0-pty-child-audit
make phase0-pty-build
make phase0-pty-run
```

## Real-hardware result

All six accepted runs (one initial plus five consecutive repeats) passed on the
DT-002 Apple arm64 baseline.

| Run | TTY | Resize | Ctrl-C | zsh exit | waitpid | Scenario (us) | Root max turn (us) |
| ---: | :---: | :---: | :---: | ---: | :---: | ---: | ---: |
| Initial | pass | pass | pass | 37 | pass | 1,400,259 | 154 |
| 1 | pass | pass | pass | 37 | pass | 1,406,338 | 476 |
| 2 | pass | pass | pass | 37 | pass | 1,427,277 | 499 |
| 3 | pass | pass | pass | 37 | pass | 1,414,520 | 488 |
| 4 | pass | pass | pass | 37 | pass | 1,423,818 | 810 |
| 5 | pass | pass | pass | 37 | pass | 1,429,851 | 486 |

No exec error, post error, acknowledgement error, timeout, unexpected signal,
or forced cleanup occurred. Every run reaped the shell and observed exit 37.

The AOT host was also changed so test failure propagates to the build process:
AppKit's run loop is stopped and awakened explicitly, final validation runs,
and the host returns its own status. A forced-failure run emitted the expected
native FAIL record and exited with **code 70**, instead of being hidden by
AppKit's normal zero-status `terminate:` path.

Artifact hashes:

```text
PtyExecChild.o
  8b8233e14ff5676c3064f6421f6655494719f6fe73b658dcc735d29f4076a13d
pty_port.aot
  a0eae377f81ea1041b6796e60f5b30df6559f40e437474ca893c105810a9664f
```

## Decision

Accepted. A `forkpty`/immediate-`execve` adapter is feasible inside the running
Dart AOT process, with an auditable async-signal-safe project child branch and
correct interactive zsh job-control behavior.

This does not yet create the product PTY API. Phase 2 must retain the audited
child split, add precomputed cwd/argv/env/FD actions and generation handles,
and test close/HUP/TERM/KILL policies. DT-005 separately records the output
batching and backpressure evidence exercised by the same integrated scenario.
