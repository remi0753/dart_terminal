# Persistent pane lifecycle

- Status: complete
- Started: 2026-09-05
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 2 `session ID と pane ownership、close confirmation state`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`, and
  `docs/adr/ADR-005-dart-only-macos-application-packaging.md`

## Purpose

Replace the per-command PTY adapter with one persistent interactive login shell
owned by one explicit Dart pane. Give every pane and its PTY session a stable,
typed identity, make lifecycle transitions deterministic, and prevent a user
close request from silently killing a live shell.

This task completes the Phase 2 persistent PTY vertical slice. The terminal
display remains a temporary plain-text projection until the Phase 3 VT model
and Phase 4 renderer are available.

## Background and confirmed starting state

- The first unchecked `ROADMAP.md` item is the Phase 2 pane/session ownership
  and close-confirmation task. The native PTY ABI, safe spawn, kqueue reactor,
  resize/signals/reaping, bounded queues, fake backend, and Dart-only product
  packaging preceding it are complete.
- `TerminalSession` currently starts `/bin/zsh -lc` for each submitted command,
  disposes that PTY after exit, and keeps command editing/history in
  `TerminalBuffer`. It has no logical pane or session identity.
- `TerminalApplication` owns a nullable `TerminalSession` directly. Every
  `WindowCloseRequestedEvent` is currently answered with `allow: true`.
- The public `dart_pty_macos` API already supports one long-lived process with
  raw ordered output, bounded writes, resize, foreground signals, bounded
  close escalation, exit status, and deterministic fake equivalents. Setting
  `loginShell: true` changes `argv[0]` to the conventional `-zsh` form.
- `dart_appkit` protocol v4 supports asynchronous close request replies but has
  no reusable alert API. Close confirmation can therefore be expressed in the
  Dart pane state and current terminal view without adding native code.
- The existing runtime lifecycle helper is a product/runtime fault-containment
  probe. It is not the Phase 3 terminal-engine worker and will remain separately
  owned until parser/grid state exists to move into a pane worker.

## Ordered subtasks

1. Freeze this purpose, scope, state model, risks, and validation contract.
2. Add typed monotonically allocated pane/session identities and a single
   `TerminalPaneOwner`. Implement deterministic pane lifecycle and close-policy
   transitions independently of AppKit and native PTY timing.
3. Make the pane own exactly one persistent login-shell PTY. Route text, Enter,
   editing/navigation keys, EOF, foreground signals, and resize to that same
   process; stream its output into the temporary text projection; close and
   reap it exactly once.
4. Connect deferred AppKit close requests to the pane policy, add real-PTY and
   application integration observations, run Developer JIT and Release AOT
   acceptance, update current documentation, and close the parent roadmap item.

Each subtask is validated, documented, marked complete, and committed before
the next begins.

## State and ownership contract

### Identities

- `PaneId` is stable for the lifetime of a logical pane and is allocated
  monotonically by the application-owned pane owner.
- `TerminalSessionId` contains its `PaneId` and a positive generation. A pane
  publishes at most one live generation. A future shell restart must increment
  the generation and cannot reuse callbacks or process state from its predecessor.
- Identity values are product metadata only. Native PTY handles and pointers are
  never exposed as pane or session IDs.

### Owners

- `TerminalApplication` owns one `TerminalPaneOwner`.
- The owner creates and retains panes, allocates identities, and is the only
  component that removes/disposes them.
- A `TerminalPane` owns one `TerminalSession`; the session owns at most one
  `PtyProcess`, its output subscription, decoder, exit observation, and resize
  state. UI code talks to the pane rather than retaining the PTY process.
- Native PTY output is accepted only while its session identity is current.
  Late output after close/replacement is ignored and cannot mutate a pane.

### Lifecycle

```text
created -> starting -> running -> exited
                    \-> failed
running -> confirmation-pending -> running       (cancel)
running -> confirmation-pending -> closing       (confirm)
created/starting/running/exited/failed -> closing -> closed
```

Start, close, and dispose are idempotent. A pane cannot publish two PTY
processes. Natural shell exit is recorded before requesting its window close,
so that close does not require confirmation.

### Close policy

- A first user close request while the persistent shell is live is denied and
  changes the pane to `confirmation-pending`. The view explains that repeating
  Close/Quit will terminate the shell.
- A second close request with no intervening terminal interaction is allowed
  and changes the pane to `closing`.
- Any key or paste interaction cancels the pending confirmation. A later close
  is again treated as the first request.
- A shell that has exited, a failed start, or an already closing/closed pane
  does not require confirmation.
- Test automation and application-fatal cleanup may force close, but normal
  Window/File/Quit user paths use the same pane policy.

## Scope

- One application window and one pane; the model must permit later multiple
  panes without relying on native handle values.
- Persistent interactive `/bin/zsh` login shell using inherited user
  environment plus explicit `TERM` and `COLORTERM` defaults.
- Raw terminal input sequences needed for text, Enter, Backspace/Delete,
  arrows, Home/End, Ctrl-C, Ctrl-D, Ctrl-Z, and Ctrl-\\.
- Current window-size propagation to the one live PTY.
- Temporary bounded plain-text output projection suitable for prompt, `tty`,
  `stty size`, jobs, and test markers before the VT parser exists.
- Deterministic fake tests, real PTY integration, and both application modes.

## Out of scope

- ANSI/VT parsing, screen grids, alternate screen, scrollback/reflow semantics,
  or correct TUI rendering. Those begin in Phase 3.
- Terminal-engine worker protocol and recovery. The current runtime helper does
  not become a fake pane worker in this task.
- Foreground-process/cwd detection and a process-aware confirmation message;
  that remains `PTY-08` in `FEATURE_MATRIX.md`.
- Multiple panes, tabs, splits, native alert sheets, session restoration, or
  reconnectable sessions.
- Unbounded paste buffering. Phase 5 owns chunking and user-facing paste safety.

## Acceptance criteria

1. Two allocated panes cannot share a `PaneId`; session identity includes its
   owning pane and positive generation.
2. The owner publishes at most one session per pane and reaches zero live panes
   after idempotent disposal, including start failure and natural exit.
3. A pane starts one login-shell PTY and multiple submitted commands use that
   same PID/process rather than spawning `zsh -lc` repeatedly.
4. Text/control input, resize, interrupt/suspend/quit, EOF, output, and exit are
   routed only through the current session and do not block the AppKit isolate.
5. First live-shell close is denied, interaction cancels it, second consecutive
   close is allowed, and exited/failed panes close immediately.
6. A real shell proves pseudo-terminal `tty`, resized `stty size`, multiple
   commands, background job plus `jobs`/`fg`, foreground interrupt, and clean
   `exit`/reap within bounded time.
7. Existing runtime lifecycle, native event, resource, diagnostics, bundle,
   source, and shutdown-fault gates continue to pass in Developer JIT and
   Release AOT. No native source or direct FFI returns to this repository.

## Validation strategy

- Model tests use `FakePtyBackend` to assert identity uniqueness, one-process
  ownership, exact writes/signals/resizes, confirmation/cancellation, start
  failure, natural exit, forced close, and idempotent teardown.
- Real-PTY tests run an interactive login zsh with startup files disabled only
  in the deterministic harness. They wait on observable output instead of
  sleeps where possible and require bounded completion.
- Application smoke emits identity and close-decision observations, requires
  one denied then one accepted deferred close, and checks all child PIDs are
  absent after process exit.
- Run format, analysis, Dart tests, source audit, `git diff --check`, and the
  complete arm64 `runtime-verify` target. Record exact results below.

## Risks

- Without a VT parser, prompt/output projection is necessarily approximate;
  it must remain bounded and must not become an accidental parser design.
- Shell startup files can alter prompts or emit control sequences. Product
  behavior must respect them, while deterministic tests use `zsh -f`.
- PTY write admission is bounded and can reject input. This task must surface
  rejection without creating an unbounded retry queue; Phase 5 will add
  paste-specific chunking and flow control.
- Close request events and shell exit may race. State transitions must make
  either order idempotent and guarantee one PTY close/reap path.

## Work log

### 2026-09-05 — contract freeze

- Re-read the repository goals, Phase 2 order, feature matrix, ownership ADRs,
  current Dart-only packaging record, product session/UI code, tests, Makefile,
  and public AppKit/PTY APIs. The worktree was clean at `09e96a1`.
- Chose an application-owned Dart pane model rather than adding identity or
  confirmation policy to `dart_pty_macos`: native PTY code owns mechanics,
  while logical pane/session identity and user close decisions are product
  semantics under ADR-001 and ADR-005.
- Chose repeat-to-confirm in the terminal view because protocol v4 already
  supplies deferred close replies and no native alert is necessary. This keeps
  the application Dart-only and gives deterministic behavior to tests.

### 2026-09-05 — identity, ownership, and close-policy model

- Added typed `PaneId` and `TerminalSessionId` values. The application-owned
  `TerminalPaneOwner` allocates monotonically increasing pane IDs, assigns one
  initial session generation, retains each pane, rejects foreign removal, and
  disposes every owned pane exactly once.
- Added `TerminalPaneSession` as the narrow product-session contract and made
  `TerminalPane` the only component that retains one implementation. App/UI
  operations are forwarded through the pane, leaving no reason for later
  AppKit code to retain a `PtyProcess` or mutable session independently.
- Implemented idempotent start/dispose, explicit
  `created/starting/running/confirmationPending/exited/failed/closing/closed`
  state, natural-termination handling, and the repeat-to-confirm policy. Any
  terminal interaction cancels a pending close before it is forwarded.
- Deterministic tests prove monotonic unique IDs, pane/session binding, one
  start, first-close rejection, interaction cancellation, second-close allow,
  natural exit, start failure, foreign-pane rejection, and zero owned panes
  after repeated teardown. `dart analyze`, the complete Dart test runner,
  Dart-only source audit (`tracked=76`, `native_sources=0`), formatting, and
  `git diff --check` pass.

### 2026-09-05 — pane-owned persistent login shell

- Replaced the per-command `zsh -lc` adapter with one `TerminalSession` that
  implements `TerminalPaneSession` and owns one interactive login-shell
  `PtyProcess` for its full generation. `TerminalApplication` now creates the
  session only through `TerminalPaneOwner`, forwards all view/input/resize
  operations through the pane, and disposes the owner rather than retaining a
  session or PTY independently.
- The session starts `/bin/zsh` with login-shell `argv[0]`, preserves the
  inherited environment, supplies `TERM=xterm-256color` and
  `COLORTERM=truecolor` only when absent, and starts at the current pane size.
  Text and Enter now write bytes to the live shell. Backspace/Delete, arrows,
  Home/End, history keys, EOF, Ctrl-C, Ctrl-Z, Ctrl-\\, and later resizes route
  to the same process and foreground process group.
- Added a bounded pre-VT text projection that preserves UTF-8 across native
  chunks and handles only CR/LF/Backspace. It intentionally does not interpret
  escape sequences or terminal modes. Input rejected by the native write cap
  is surfaced once and is not retained in an unbounded retry queue.
- Session start, output/exit observation, close escalation, and disposal are
  idempotent. The output subscription is drained before natural termination is
  published, and owner callbacks from a closing pane cannot republish it.
- Fake tests prove one process across multiple submitted commands, exact input
  bytes and control sequences, all foreground signals, resize, split UTF-8,
  bounded write rejection/recovery, natural exit, and one close path. A real
  `zsh -f` test proves two commands, `/dev/tty*`, `stty size` = `37 111`, clean
  exit, and reap through the public native asset.
- `make test`, `make runtime-source-check`, and `git diff --check` pass; the
  source audit reports `tracked=77`, `native_sources=0`. A fresh arm64 Developer
  JIT application build also succeeds with the manifest-staged PTY and renderer
  assets.

### 2026-09-05 — close integration trial

- Connected protocol-v4 `WindowCloseRequestedEvent` to the pane close policy.
  The normal Developer JIT smoke passed with two deferred requests for the same
  `pane=1 session=1:1`: the first was rejected as `confirmation-required` and
  the second was accepted in `closing` state.
- The first complete `runtime-verify` attempt then exposed a fatal-cleanup edge
  case. In the `root-uncaught` scenario the generic host requested a window
  close after the root error, but the pane classified it as an ordinary user
  close and denied it, so the process reached the 12-second integration
  timeout. Fatal root cleanup now marks the close as forced before raising the
  error. It bypasses confirmation while normal Window/File/Quit paths retain
  the two-step policy. The complete suite must be rerun before closeout.

### 2026-09-05 — AppKit integration and Phase 2 closeout

- Normal protocol-v4 window close requests now call `TerminalPane.requestClose`.
  The first request for a live shell is replied to with `allow: false`, records
  `confirmation-required`, and renders the repeat-to-close notice. The next
  consecutive request is replied to with `allow: true` in `closing` state.
  Text, editing/control keys, or pasted text cancel a pending confirmation.
- Automated smoke schedules the second close after the first reply rather than
  issuing overlapping native operations. Its assertions require two deferred
  close events and exact ordered decisions for the same typed pane/session.
  Root-fatal cleanup explicitly forces the pane close, preserving the ordered
  PTY shutdown without allowing confirmation policy to trap a failed root.
- Strengthened the real PTY product test: one login zsh disables echo, proves
  `/dev/tty*` and resized `stty size` (`37 111`), runs multiple commands, starts
  a background `sleep`, observes it through `jobs`, returns it with `fg`, sends
  Ctrl-C to the foreground process group, then runs another command and exits
  cleanly. The test completes through callback-driven exit and native reap.
- The final `make RUNTIME_ARCH=arm64 runtime-verify` completed with exit 0.
  It passed format, analysis, all Dart/fake/real-PTY tests, Dart-only source
  audit (`tracked=77`, `native_sources=0`), fresh Developer JIT and Release AOT
  builds, deep bundle/architecture/dependency/signature audits, and normal GUI
  smoke in 2,194 / 1,814 ms.
- Both modes passed all lifecycle/failure/replacement/usage scenarios with the
  expected 0/64/70/75 statuses. Bounded traffic rejected 384 requests at the
  64-request in-flight ceiling and completed in 984 / 993 ms. The 1,000-cycle
  Window/View stress returned from baseline 12 and peak 14 to final 12 in
  5,787 / 5,629 ms. Shutdown-fault containment completed in 445 / 284 ms with
  final native handles at zero. `git diff --check` passed.

All subtasks and acceptance criteria in this note are complete. Phase 2 now
has one pane-owned persistent PTY with deterministic identity, lifecycle,
job-control input, resize, close confirmation, and teardown. Phase 3 may begin
with the first unchecked streaming UTF-8 decoder/parser task; the current
plain-text output projection is intentionally not treated as a VT core.
