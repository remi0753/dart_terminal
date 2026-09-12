# dart_pty_macos

`dart_pty_macos` is an AppKit-independent PTY/process capability for Dart macOS
applications. Native code owns only `forkpty`, the audited child `execve` path,
master-FD readiness, bounded byte queues, resize/signals, close escalation, and
child reaping. Dart owns session policy and terminal semantics.

The v6 `dpty_*` C ABI provides:

- copied argv, environment, working directory, and initial size before fork;
- an isolated C child branch using only audited async-signal-safe operations;
- one kqueue reactor thread per session;
- output chunks no larger than 64 KiB retained until ordered ACK, with a
  consumer-selectable smaller per-command delivery bound;
- configurable read high/low watermarks and bounded write admission;
- foreground process-group signals, `TIOCSWINSZ`, SIGHUP/grace/SIGKILL close;
- a content-free on-demand child/owning/foreground process-group and terminal
  echo-mode snapshot;
- idempotent, nonblocking immediate force close before or during graceful close;
- opt-in, content-free write/control/reap diagnostics with tracked-write IDs;
- bounded reactor turns so continuous output cannot starve writes or close;
- exactly one started/error and exit lifecycle, `waitpid` reaping or verified
  external-reap recovery from `NOTE_EXITSTATUS`, and generation-checked session
  handles.

The Dart facade uses a listener-style native callback so reactor threads enqueue
events without entering the UI isolate synchronously. `FakePtyBackend` provides
the same public process surface for deterministic product tests.

`PtyCommand.readBatchBytes` can lower one command's OUTPUT delivery bound from
the 64 KiB default when its synchronous consumer has a tighter event-loop
budget. The size-prefixed C config treats an absent suffix or zero as 64 KiB, so
older ABI-v5 clients retain their established batching behavior. Read
high/low-watermark backpressure and ordered ACK ownership are unchanged.
The Dart native facade acknowledges a copied OUTPUT event only after its
synchronous stream delivery returns, so a consumer can make the configured
watermarks represent work it has actually accepted rather than merely a queued
listener message.
`PtyCommand.readBatchesPerEventLoopTurn` accepts zero or a limit from one to
eight. Zero is the default and preserves immediate ACK and existing native read
behavior. With a nonzero limit, native delivery retains at most one unacknowledged
batch; the Dart facade immediately acknowledges the first `limit - 1`
synchronously consumed batches and schedules the limit-th ACK on a later event
turn. Consumers can therefore choose their own fairness/throughput budget
without imposing terminal-specific scheduling on other applications.

`PtyProcess.close()` starts the graceful SIGHUP/deadline policy.
`PtyProcess.forceClose()` is a separate lifecycle operation that remains valid
after graceful close starts and asks the reactor to send SIGKILL immediately;
neither call waits for exit or `waitpid` on the caller thread. Consumers still
await `exit` when they need proof that reaping completed.

`PtyProcess.processSnapshot()` copies only numeric child/process-group identity,
per-field syscall errors, and exit state. It never inspects process names,
arguments, environment, working directories, or terminal content. A consumer
can distinguish the owning shell group from a foreground job while treating
an unavailable field conservatively.

`PtyProcess.writeTracked()` returns an opaque request ID for correlating queue
admission, reactor dequeue, and `write(2)` completion. Passing
`enableDiagnostics: true` exposes those stages, foreground process-group and
termios/VEOF snapshots, signal results, `waitpid` results, and exit publication
through `PtyProcess.diagnostics`. Diagnostics are off by default and contain no
input/output bytes, commands, environment values, working directories, or
terminal text. `externalReapObserved` identifies the macOS case where another
process-wide waiter reaped the child after a matching kernel exit notification;
the retained kernel status still produces exactly one normal exit event.

`MacosPtyBackend.shared` uses the official native-assets mapping in ordinary
Dart tools. A custom application host can instead call
`MacosPtyBackend.open(absoluteBundleLibraryPath)` using the path supplied by its
bundle runtime; the same facade then retains and resolves that staged image.

The package contains no AppKit dependency, Objective-C source, VT parser,
renderer, pane model, or application policy.
