# Phase 7 — per-pane close and application quit confirmation

- Status: complete
- Started: 2026-09-08
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `per-pane close と app quit confirmation`
- Related: UI-04, PTY-08,
  `docs/phase2/persistent-pane-lifecycle.md`,
  `docs/phase2/pty-child-reap-ownership-conflict.md`,
  `docs/phase5/window-close-scroll-position.md`, and
  `docs/phase7/application-state-model.md`

## Purpose

Make Close operate on the focused terminal pane rather than implicitly on the
whole application, collapse its split/tab/window ownership only after an
accepted decision, and coordinate an application Quit across every retained
pane. Detect whether a live PTY currently has a foreground process distinct
from its owning shell so confirmation decisions are based on bounded process
metadata rather than terminal text, titles, or timing. Preserve deterministic
PTY, renderer, text-input, native-handle, and worker teardown.

## Background and confirmed starting state

- The preceding fullscreen/migration/restoration/reopen item is complete at
  terminal commit `1c285de Verify fullscreen restoration across runtimes`.
  Both this repository and the adjacent `dart_appkit` worktree were clean when
  this task started.
- `TerminalPane.requestClose` implements a pane-local two-step policy: a live
  session asks once for confirmation and accepts the next request; a non-live
  session accepts immediately. Any normal terminal interaction cancels the
  pending state. It does not distinguish an idle owning shell from a distinct
  foreground process.
- The ordinary single-pane bootstrap routes both Close and Quit menu actions
  through one native window close request. An application termination request
  is always refused first and translated into that same window request. This
  cannot express focused-pane removal, a multi-pane window close, or one
  aggregate decision spanning several windows.
- `TerminalApplicationState.removePane` already performs ordered session
  shutdown and deterministic split collapse, removes an empty tab/window, and
  selects the nearest retained pane/tab/window. `TerminalNativeHierarchyAdapter`
  releases removed pane adapters/view, split view, and native tab window during
  reconciliation.
- The reusable PTY boundary already reads `tcgetpgrp` for content-free debug
  diagnostics and uses it for signal delivery, but the public product API has
  no on-demand process snapshot. `PtyStats.childPid` is available only as final
  statistics and cannot drive a live close decision.
- AppKit protocol v6 provides independently deferred, operation-ID-checked
  window close and application termination requests. Programmatic close and
  termination bypass user deferral for deterministic teardown.

## Scope

- A content-free, bounded, on-demand PTY process snapshot containing only the
  identities/state required to distinguish an idle owning shell from a
  distinct foreground process, with typed failure/unavailable handling.
- A deterministic close-risk classification and confirmation transaction tied
  to pane/session identity and invalidated by state changes or interaction.
- Focused-pane Close, split collapse, tab/window removal, post-removal
  selection/focus restoration, and exact resource cleanup.
- Aggregate Quit admission across all retained panes, one explicit
  confirmation boundary, stale/duplicate request rejection, cancellation, and
  exactly one reply to each deferred AppKit termination request.
- M1/arm64 Developer JIT and Release AOT product acceptance using real AppKit,
  PTYs, Metal, text input, menu/window/application requests, and final owner
  audits.

## Out of scope

- Inspecting terminal output, shell prompts, titles, cwd, command lines,
  executable paths, arguments, environment, or process names to decide risk.
- Killing arbitrary unrelated processes, reconnecting a session, or retaining
  a live process after its pane is removed.
- Configurable confirmation preferences or new visual sheet/dialog styling;
  typed configuration and broader UI polish remain later phases.
- Fair multi-pane scheduling/resource budgets and the final broad AppKit UI
  suite, which are the next ordered Phase 7 items.
- x86_64, Rosetta, Universal, Intel-native, or long-duration soak evidence
  before the M1 correctness contract is complete.

## Ordered subtasks

### 1. Bounded foreground-process snapshot and close-risk classification

- Add the smallest reusable PTY capability needed to query the live child PID,
  owning process group, foreground process group, and availability/error state
  without enabling diagnostic event streams or reading process content.
- Expose an immutable terminal-session/pane snapshot and classify non-live,
  idle-shell, distinct-foreground, and unavailable states conservatively.
- Completion: native, Dart facade/fake, and terminal unit tests cover normal,
  child-group foreground, distinct foreground group, exited/disposed, syscall
  failure, ownership, and stale-use cases; the reusable and terminal focused
  gates pass; documentation and roadmap child are updated; each repository's
  task-local change is committed before the next child.

### 2. Application-owned per-pane close transaction and hierarchy collapse

- Add a main-root coordinator that targets the currently focused pane, creates
  at most one identity-bound confirmation transaction, rejects stale or wrong
  confirmations, and invokes `TerminalApplicationState.removePane` only after
  admission.
- Reconcile native resources after accepted removal and preserve deterministic
  neighboring focus/tab/window selection. Natural clean exit and abnormal
  retained-pane one-step close remain unchanged.
- Completion: model/fake-native tests cover nested split collapse, selected and
  background tabs/windows, repeated/cancelled requests, concurrent mutation,
  shutdown failure classification, and zero leaked pane/native resources; the
  focused terminal gates pass and the child is committed.

### 3. Aggregate application quit confirmation and deferred native lifecycle
coordination

- Compute one content-free aggregate over all retained panes, require a single
  explicit confirmation when any live/risky pane remains, and never partially
  remove panes before the aggregate decision.
- Coordinate menu Quit and `ApplicationTerminateRequestedEvent` separately
  from focused-pane Close. Reply exactly once to the matching native operation,
  reject stale/duplicate requests, and after acceptance perform bounded global
  shutdown followed by programmatic termination.
- Completion: direct and fake-AppKit tests cover zero/one/many panes, mixed
  idle/foreground/non-live states, cancel/retry, close-vs-quit overlap,
  duplicate/stale native requests, teardown faults, and exact reply/cleanup;
  focused gates pass and the child is committed.

### 4. M1 dual-runtime regression acceptance and parent completion

- Add an integration-only product scenario with multiple tabs/four panes that
  proves focused-pane Close affects only its target, foreground activity
  requires confirmation, non-live cleanup is immediate, Quit is aggregate and
  atomic before acceptance, and every retained resource is reclaimed after it.
- Run focused Developer JIT and Release AOT acceptance, complete tests,
  format/analyze, source and bundle audits, and the aggregate runtime gate.
- Completion: both modes expose the same content-free semantic summary and
  exact cleanup counts; README and feature evidence are current; all checks
  pass; the final child and parent are checked and committed.

## Acceptance conditions

1. A close/quit decision never depends on terminal content or unbounded
   process inspection and fails conservatively when live process state cannot
   be established.
2. Close targets one focused pane. Refusal changes no split, tab, window,
   focus, viewport, or ownership state; acceptance removes exactly that pane.
3. Split/tab/window collapse and next focus selection remain deterministic, and
   removed pane resources are reclaimed before the mutation reports complete.
4. Quit evaluates all panes as one transaction and performs no partial close
   before confirmation. One accepted transaction shuts down every owner once.
5. Deferred AppKit close/termination operations receive exactly one matching
   reply. Stale, duplicate, cross-window, or wrong-generation decisions cannot
   close a pane or terminate the application.
6. Natural clean shell exit still auto-closes its pane; abnormal or failed exit
   remains visible and is removable in one step without live-process warning.
7. M1 Developer JIT and Release AOT cover real PTY foreground activity,
   multiple panes, native requests, and zero remaining PTY/Metal/text-input/
   split/window/native-handle/worker resources.

## Verification plan

- Extend `dart_pty_macos` native capability, Dart API/fake backend, and real FFI
  tests before using it in terminal policy.
- Add pure policy/coordinator tests with fake pane sessions and fake AppKit
  bindings, including deterministic interleavings and failure injection.
- Add a gated product runtime suite and Makefile targets for both supported
  modes; require content-free exact summaries and child-process absence.
- Run each child’s focused format/analyze/tests, then `make test`, source and
  bundle audits, and the proportional runtime matrix before committing it.

## Investigation and decision log

- 2026-09-08: after the preceding task commit, `ROADMAP.md` was reread and this
  item was confirmed as the first unfinished work. README, FEATURE_MATRIX,
  repository structure, related Phase 1/2/5/7 records, current application
  event handling, pane/session ownership, application-state removal, native
  hierarchy reconciliation, action registry, and reusable PTY API/native
  implementation were inspected before executable changes.
- 2026-09-08: the current Close and Quit registrations both call the same
  single `Window.requestClose`; the application termination listener refuses
  every native Quit request and requests that window close. This is suitable
  only for the historical one-pane bootstrap and cannot be generalized by
  changing a menu label or force flag.
- 2026-09-08: `TerminalApplicationState.removePane` already owns the correct
  structural mutation and ordered pane shutdown. The missing layer is an
  admission transaction above it; duplicating split/tab/window collapse inside
  AppKit callbacks would create two ownership authorities and is rejected.
- 2026-09-08: PTY diagnostics contain `tcgetpgrp` observations only when the
  session is launched with diagnostics and events happen. Reusing that stream
  for product policy would be stale, test-oriented, and timing-dependent. The
  selected direction is a small on-demand typed snapshot at the PTY boundary,
  with conservative unavailable classification and no command/process text.
- 2026-09-08: the task is divided into four sequential children because it
  spans a reusable native package, pure application coordination, deferred
  AppKit lifecycle, and real two-mode acceptance. No scheduling or broad UI
  work from later roadmap items is included.
- 2026-09-08: the first adjacent-package format/test command stopped before
  tests because the managed sandbox denied both the formatter overwrite in
  `dart_appkit` and Dart telemetry timestamp access. The formatter reported no
  successful file update. The same scoped command must be rerun with telemetry
  disabled and adjacent-worktree permission; this is not a source/test failure.
- 2026-09-08: the reusable PTY design advances its independent ABI to v5 and
  adds a size/version-prefixed same-call snapshot. Native access serializes
  child/master descriptor identity with closure; successful fields are
  positive IDs, individual `getpgid`/`tcgetpgrp` failures retain typed errno,
  and exited state returns no fabricated group. The Dart value derives only
  availability and whether the foreground group differs from the owning shell
  group. Fake inputs can deterministically select idle, distinct, and
  unavailable observations.
- 2026-09-08: focused `dpty-native-test` and `dpty-dart-test` passed warning-
  clean C11/C++20 headers, the audited child symbol allowlist, native idle zsh
  and distinct `sleep` process groups, exited/stale cases, Dart FFI and fake
  snapshots, lifecycle, force-close, diagnostics, and competing-reaper cases.
  The complete adjacent `make test` then passed every bridge, Runner, runtime,
  renderer, PTY, Dart package, launcher, Kernel, FFI, and legacy-event gate.
  No unrelated adjacent file is modified.
- 2026-09-08: the first Terminal-side focused format invocation successfully
  formatted the selected sources but returned nonzero afterward when Dart
  telemetry could not update its external session timestamp. Because the
  command used `&&`, focused analysis did not start. No test failure occurred;
  the format/analyze sequence is repeated with telemetry disabled.
- 2026-09-08: telemetry suppression did not prevent this installed Dart CLI
  from touching the external timestamp; the second format reported zero source
  changes and then returned the same permission error, again before analysis.
  Verification therefore requires the scoped Dart commands to run with that
  external metadata permission rather than further source changes.
- 2026-09-08: the permitted focused format and analysis passed, but the direct
  aggregate runner then found one compile-time API conformance gap in the
  application fault fixture: `_ExitNotificationSuppressingPtyProcess` did not
  delegate the new snapshot operation. A repository-wide implementation search
  found only the native facade, fake backend, and this wrapper. The wrapper now
  delegates the content-free snapshot exactly while continuing to suppress
  only its exit future; no production shutdown semantics are changed.
- 2026-09-08: after the wrapper correction, focused formatting required zero
  changes, focused analysis reported no issues, and the direct aggregate runner
  ended with `dart_terminal tests passed`. Complete Terminal `make test` also
  passed every generated/freshness gate, formatting of 203 Dart files with zero
  changes, whole-package analysis, native asset hooks, and the aggregate
  runner. README and PTY-08/UI-04 now describe the completed substrate without
  claiming the later close/quit transactions.
- 2026-09-08: the reusable dependency result is independently committed as
  adjacent `dart_appkit` commit `5fc05c2 Expose PTY foreground process
  snapshots`. The first ordered child has no remaining implementation or test
  work and is marked complete; the next child begins only after this Terminal
  progress/documentation commit.
- 2026-09-08: updating README and feature evidence changed their pinned hashes,
  so the deterministic compatibility coverage report was regenerated. Its
  freshness check passed all nine fix families, 417 split runs, eight owned
  gaps, and zero known P0 silent-corruption cases. Final whitespace checks are
  clean and the adjacent dependency worktree is clean.
- 2026-09-08: the second child keeps `TerminalApplicationState.removePane` as
  the sole structural and session-shutdown authority. A new main-root
  coordinator owns at most one monotonic operation, binds it to exact
  pane/session identity, and invokes hierarchy reconciliation only after the
  accepted removal completes. Reimplementing split/tab/window collapse in
  native callbacks was rejected because it would create a second owner.
- 2026-09-08: idle-shell and non-live snapshots admit immediate removal.
  Distinct foreground or unavailable live snapshots create a content-free
  confirmation; repeating that exact focused Close confirms it. Wrong tokens,
  interaction-cancelled pane state, missing targets, and concurrent removal
  return typed stale/no-target/busy results without hierarchy mutation.
  Cleanup failure remains explicit even though the already-owned structural
  removal completes deterministically.
- 2026-09-08: the first focused coordinator analysis stopped before tests on
  three local static errors: a const token assertion invoked the non-const
  `PaneId.operator==`, and the state test lacked the `dart:async` import for two
  `Completer` uses. The assertion now compares the const integer identities and
  the test imports its owning library; no runtime behavior was exercised by the
  failed attempt.
- 2026-09-08: a second analysis showed that even the public `PaneId.value`
  getter is not a Dart const expression, leaving two errors on the same token
  assert. The token constructor is now non-const and performs explicit runtime
  validation of positive operation ID, matching pane/session identity, and a
  confirmation-requiring process disposition. This is stricter in release
  builds than the discarded assert-only approach.
- 2026-09-08: focused review after the first green tests found that an exact
  token whose pane confirmation had already been cancelled returned `stale`
  but left the bounded token cached until another request. Confirmation and
  cancellation now retire that exact stale token immediately; a wrong token
  still cannot consume the valid pending one. The regression asserts both
  properties.
- 2026-09-08: after the stale-token correction, formatting, focused analysis,
  direct application-state tests, and direct fake-native hierarchy tests all
  passed. Complete `make test` then passed generated/freshness checks,
  formatting of 204 Dart files with zero changes, whole-package analysis,
  native asset hooks, and the aggregate test runner.
- 2026-09-08: coverage now includes foreground refusal without mutation,
  wrong-token preservation, interaction invalidation, monotonic repeated-action
  confirmation, idle/non-live immediate removal, unavailable-state cancel,
  nested split and background-tab collapse, last-window selection, in-flight
  exclusion, cleanup-failure classification, and adapter-driven release of the
  removed pane view and split. The second ordered child has no remaining work
  and is marked complete; aggregate Quit remains the next child.
- 2026-09-08: README/feature evidence hashes were regenerated and the
  compatibility freshness gate passed with zero known P0 silent-corruption
  cases. The Dart-only source audit passed with 386 tracked files, zero product
  native sources, and one reviewed test-native source. Whitespace checks and
  both repository worktrees' task boundaries are clean.
- 2026-09-08: the aggregate Quit coordinator captures panes in deterministic
  window/tab/split visual order and binds the confirmation token to every
  pane/session identity plus the same-call process IDs, groups, disposition,
  and lookup errors. Any foreground or unavailable pane makes the whole
  transaction conservative; idle and non-live panes do not. Snapshot lookup
  exceptions and session-identity mismatches are converted to unavailable
  rather than weakening admission.
- 2026-09-08: Quit reserves pane mutation through the existing Close
  coordinator. The reservation cancels a pending pane confirmation, refuses
  to interrupt an in-flight removal, and makes later pane Close requests busy
  until Quit is cancelled, becomes stale, or is accepted. This preserves the
  no-partial-removal boundary without adding a second hierarchy owner.
- 2026-09-08: menu and native Quit share one transaction but retain separate
  lifecycle completion: menu acceptance invokes programmatic termination only
  after hierarchy/session shutdown, while a deferred native request receives
  its matching allow reply after shutdown. Duplicate pending operations
  coalesce, competing operations receive one refusal, and a bounded 64-entry
  reply ledger prevents recent duplicate replies. Pre-shutdown cleanup faults
  are classified while application pane shutdown and termination continue.
- 2026-09-08: the first focused format changed only the new coordinator. The
  subsequent analysis reported an async return inside a `try` block and one
  export-order lint; no type or API error was found. The begin path was reshaped
  so reservation release covers only synchronous snapshot/setup failure and
  cannot accidentally encompass accepted asynchronous teardown; the export
  was sorted.
- 2026-09-08: the first direct application-state run reached the final cached
  completion assertion, then failed because `confirmQuit` checked the retained
  completion future before the completed result and classified an already-used
  token as busy rather than stale. Teardown itself completed. Completed-state
  precedence now makes old confirmation tokens unambiguously stale.
- 2026-09-08: after that correction, focused formatting, analysis, the direct
  application-state test, and the direct fake-AppKit hierarchy test passed.
  Coverage includes zero-pane immediate native Quit; four panes across two
  windows and two tabs with idle, foreground, non-live, and unavailable states;
  aggregate stale/cancel/retry; Close exclusion; native duplicate/competition;
  teardown faults; and native allow only after hierarchy and session cleanup.
- 2026-09-08: final child verification regenerated the documentation-bound
  compatibility report, then passed all nine regression families with 417
  split runs, eight owned gaps, and zero known P0 silent-corruption cases. The
  Dart-only source audit passed with 387 tracked files, zero product native
  sources, and one reviewed test-native source. Complete `make test` passed
  every generated/freshness gate, formatting of 205 Dart files with zero
  changes, whole-package analysis, native asset hooks, and the aggregate test
  runner. `git diff --check` is clean and the adjacent dependency worktree has
  no changes. Product menu/event/runtime wiring intentionally remains in the
  next ordered child.
- 2026-09-08: after commit `2a3d24a Coordinate aggregate application quit`,
  `ROADMAP.md` was reread. The fourth child is the first unfinished item; the
  parent and later scheduling/UI-test items remain untouched. README,
  FEATURE_MATRIX, repository inventory, the normal bootstrap, existing
  four-pane hierarchy acceptance, integration driver, Make targets, AppKit
  event API/native implementation, and both worktrees were rechecked before
  executable changes.
- 2026-09-08: the existing gated hierarchy acceptance already owns the exact
  real resource graph required here: two native tabs, four PTYs, four Metal
  surfaces, four text-input clients, and one runtime worker in Developer JIT
  and Release AOT. Extending that scenario is selected over duplicating a
  second large fixture. Its direct forced removals will be replaced by the
  actual menu/native-window Close route, non-live immediate removal, one real
  deferred application-termination refusal, and menu-driven aggregate Quit.
- 2026-09-08: `Window.requestClose` already creates a real deferred native
  request, but the reusable AppKit testing surface has no way to request normal
  NSApplication termination: its public `terminate` deliberately marks the
  request programmatic and bypasses deferral. A minimal test-only bridge hook
  that calls ordinary `[NSApp terminate:nil]` is required to exercise the real
  delegate/event/reply path without synthesizing a Dart event whose operation
  ID the native bridge does not own. The hook will remain outside the ordinary
  `dart_appkit.dart` export and will not expose product data.
- 2026-09-08: the AppKit hook now enters the existing native termination
  state machine, requires terminate-later, and is optional at the FFI lookup
  boundary. Warning-clean native bridge tests, whole `dart_appkit` analysis/API
  tests, launcher tests, real FFI loading, and legacy fallback all passed in
  the focused `make native-test dart-test ffi-smoke` run.
- 2026-09-08: complete adjacent `make test` also passed scaffold/header
  validation, warning-clean bridge/Runner/runtime/renderer/PTy compilation,
  all native capability and lifecycle suites, every Dart package analysis and
  test, launcher/Kernel compilation, real FFI loading, and legacy fallback.
  The dependency change is ready for its own commit before terminal wiring.
- 2026-09-08: adjacent commit `ab5a78e Expose deferred termination test hook`
  contains only that reusable test boundary, and the adjacent worktree is
  clean. `ROADMAP.md` was reread after the dependency commit; the dual-runtime
  acceptance child remains the first unfinished item.
- 2026-09-08: the hierarchy fixture now reserves structural mutation through
  the product Close/Quit coordinators. Each menu Close asks the selected native
  tab window for a real deferred close; the matching native callback refuses
  window ownership transfer and lets the application coordinator remove only
  the focused pane. Text-input ownership is cancelled immediately before an
  accepted removal so hierarchy reconciliation can release the pane adapters
  synchronously without weakening the first confirmation boundary.
- 2026-09-08: the planned runtime sequence is exact and content-free: a
  distinct `sleep` process group requires two Close invocations with no first-
  request structural change; an exited status-23 pane closes once; two real
  native termination requests are separately refused to prove native pending
  state is cleared; and two menu Quit invocations capture then accept the same
  remaining two-pane visual-order snapshot. Accepted Quit cancels native event
  and text-input routes, reaps the worker, disposes the hierarchy, shuts both
  PTYs, and only then calls programmatic application termination.
- 2026-09-08: the first focused analysis found no type error but rejected the
  single nullable application-event subscription as potentially uncancelled.
  Both window and application native subscriptions are now kept in explicit
  owned lists that are cancelled and cleared in accepted teardown and the
  failure cleanup path; this makes route ownership mechanically auditable.
- 2026-09-08: after that ownership correction, focused formatting made no
  further changes and analysis passed with zero issues. The Developer JIT
  hierarchy launch then passed through the real application bundle in 2250 ms,
  including all four PTYs, native menu/window requests, native deferred
  termination hook, Metal/text-input cleanup, and the runtime worker contract.
  The integration driver now requires the exact Close/Quit route counts and
  zero-resource summary in addition to the established hierarchy summary.
- 2026-09-08: focused formatting and analysis of both the product fixture and
  strengthened integration driver passed with zero changes/issues. Release
  AOT then passed the same exact route and owner assertions in 1441 ms. Both
  modes therefore prove three menu/native Close requests, two separately
  refused real native Quit requests, two menu Quit invocations, one final
  programmatic termination, four clean PTY shutdowns, four disposed zero-pin
  Metal surfaces, zero text-input clients/native handles, and one gracefully
  reaped runtime worker. Full repository and runtime verification remain
  required before marking the child or parent complete.
- 2026-09-08: documentation-bound compatibility evidence was regenerated after
  the README and feature-matrix updates. Generation passed nine regression
  families, 390 input bytes, and 417 split runs; the resulting report remains
  part of this task diff for the subsequent freshness and full-suite checks.
- 2026-09-08: complete `make test` passed every generated/freshness contract,
  all compatibility/differential/application/terminfo gates, formatting of 205
  Dart files with zero changes, whole-package analysis with zero issues,
  native-asset hooks, and the aggregate test runner. The coverage freshness
  result remains nine fix families, 417 split runs, eight owned gaps, and zero
  known P0 silent-corruption cases.
- 2026-09-08: the Dart-only source audit passed with 388 tracked files, zero
  product native sources, and one reviewed test-native fixture. The new native
  bridge hook remains owned and committed in the reusable AppKit dependency,
  not copied into this product repository.
- 2026-09-08: final `make RUNTIME_ARCH=arm64 runtime-verify` passed the complete
  matrix in both Developer JIT and Release AOT: bundle audits, smoke, real-PTY
  display, the strengthened hierarchy/Close/Quit acceptance, restoration,
  clipboard, all 16 lifecycle scenarios, bounded traffic, 1000-iteration
  resource stress, shutdown fault, and PTY-deadline handling. Resource stress
  stayed at baseline 33 and peak 35 native handles in both modes. The parent
  objective and all four ordered children now satisfy their completion
  criteria; no blocker or untracked follow-up was found, so the roadmap child
  and parent are marked complete.
