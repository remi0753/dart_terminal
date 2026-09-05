# Persistent pane lifecycle

- Status: contract frozen; identity and ownership model not yet implemented
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
