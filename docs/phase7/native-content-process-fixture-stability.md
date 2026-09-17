# Native-content process observation fixture stability

- Status: complete
- Identified: 2026-09-17
- Environment: macOS / Apple M1 / arm64
- Related: [shifted boundary shortcut verification](context-dock-boundary-shift-shortcut.md)

## Purpose and background

Investigate intermittent failures in the existing Developer JIT native-content
process argv reveal/elapsed acceptance fixture. Do not treat rerunning until a
pass as a long-term stabilization strategy, or assume the new Dock shortcut
caused a process-observation regression.

## Scope, dependencies, and exclusions

- Reproduce with the smoke driver and fresh developer-jit/release-aot bundles;
  record content-free observation timings, active/focus authority and job lifetime.
- Inspect the existing pipeline's 4-second sleep, palette open/invoke/dismiss,
  process poll/activation/inventory intervals and native event ordering.
- Determine whether the defect is harness authority/lifetime or product focus/
  observation policy before choosing a fix. Preserve inactive/focus privacy
  clearing, stable identity, argument hiding, no PTY key writes and all assertions.
- Dependencies: Phase 7 native-content harness, command palette focus restore,
  Context Dock process coordinator, native application/window event state.
- Exclude SSH, shortcut remapping, global keyboard interception and unrelated
  native PTY competing-reaper work. Do not weaken timeout/argv/elapsed expectations
  merely to obtain a green run. Split work if distinct product fixes are required.

## Confirmed evidence and unresolved hypotheses

- During the shifted-shortcut task, two rebuilt JIT runs passed the new resize
  marker but timed out at argv reveal (~9350 of terminal_application.dart).
- An unchanged direct JIT run passed reveal then null-checked a missing process
  snapshot after the 1100 ms elapsed wait (~9365). A fourth unchanged direct JIT
  run passed the full suite (10398 ms); rebuilt AOT also passed (9958 ms).
- The complete `make test` rerun passed. No process/focus implementation, fixture
  lifetime, timeout or assertion was modified in the shortcut task.
- Coordinator eligibility requires active application plus visible/focused native
  window. The direct/headless harness injects initial active/focus events; prior
  foreground-inspector notes explain this requirement. Palette transitions and
  the short pipeline lifetime are hypotheses, not established causes.

## Completion criteria and verification plan

- Establish a reproducible cause with safe metadata, not private argv/path dumps.
- Apply a justified minimal fix, keep all process/privacy/elapsed/cleanup checks,
  and document why alternatives were rejected. Repeat both runtimes across focus
  transitions and measured scheduling variation with bounded attempts/time.
- Pass focused tests, formatting/static analysis, rebuilt runtime integration and
  full gate; refresh evidence if sources change, then commit this separate task.

## Investigation plan and current evidence

- User authorized reordering and explicitly requested both tasks. Divider task
  and its two ordered subtasks are committed; this is now the first unchecked
  roadmap item. Rechecked both worktrees, product docs/build/test boundaries and
  prior process-inspector/focus authority records. Adjacent Engine user edits
  remain untouched; product worktree is clean at ba4542b.
- Divider verification rebuilt both runtimes and passed process checks once
  each, but these successes do not explain or fix the recorded nondeterminism.
- Current fixture has a 4-second pipeline lifetime, up to 10-second argv wait
  and another fixed 1100 ms elapsed wait. Reveal waits for a fresh inventory
  (at most one request/second), while palette window open/close can change focus
  eligibility. Initial headless active/focus authority is injected only once.
- Diagnose first with bounded baseline and scheduling-variation runs, logging
  only stage-relative time, active/visible/focus booleans, disposition/mode/status,
  operations and argv-display preference. No argv, path, input or document text
  is logged. Keep production privacy/eligibility policy unchanged.
- Choose a minimal fixture lifecycle/authority fix only after measured evidence;
  retain all hide/reveal/elapsed/zero-write/return-to-Navigator/cleanup assertions.
  This is one bounded fixture task; split and register further subtasks before
  any independent product/palette/native fix if the investigation requires one.
- Baseline rebuilt JIT/AOT just passed without scheduling variation. Add a
  deterministic 3500 ms harness pause between hiding argv and opening the
  palette, preserving all assertions. This models a slow UI/scheduled turn
  within the existing 10-second acceptance budget, while measuring the original
  4-second fixture deadline and focus eligibility separately. Diagnostic stage
  traces are test-mode only and content-free.
- A guessed historical doc filename did not exist; rg --files identified the
  actual context-dock-foreground-process-inspector.md. No implementation decision
  used the absent document; selected recorded focus-authority sections apply.
- Delayed original JIT fixture reproduced argv reveal failure with unchanged
  focus policy: ready at 28 ms, inspected 147 ms, hidden 156 ms; after pause at
  3657 ms still foreground/ready, palette restored at 3720 ms still active,
  visible and focused. At the 10-second reveal deadline (13727 ms) the pane was
  idleShell and Dock directoryNavigator with no process. Focus remained true
  throughout. This confirms independent fixture lifetime vs fresh-refresh race,
  not a shortcut regression or evidence that privacy clearing is defective.
  Failed product teardown reaped its worker and shut down pane ownership cleanly.
- Unit process refresh/privacy/elapsed tests are part of
  terminal_context_dock_test.dart, not a separate guessed process test filename.
- Reject simply increasing sleep/deadline (still competing timers), retrying
  until pass, forcing stale argv, or weakening inactive/focus clearing. Keep the
  real pipeline alive with POSIX read until the harness explicitly sends its
  fixed release token after every zero-key-write/identity/elapsed assertion.
  The existing 60-second driver bound and pane-owned failure teardown remain
  the watchdog/cleanup mechanism; no temporary-file polling, helper process,
  product policy change or new input command is required.
- Implemented a two-member /bin/sh read | /bin/cat pipeline, released with a
  fixed input token only after zero-key-write checks. Retained the 3500 ms
  scheduling pause and 1100 ms elapsed wait; smoke requires exactly one strict
  controlled-lifetime marker and measured hold >=4600 ms. Strengthened reveal
  and elapsed assertions to the same process identity and retained metadata-only
  failure diagnostics instead of an uninformative null-check crash. No privacy,
  coordinator interval, palette focus restore or normal product behavior changed.
- Rebuilt runtime-native-content-integration passed JIT (13035 ms) and AOT
  (11608 ms) including all four clean sessions and zero handles/text clients.
  dart analyze and focused Context Dock/process/privacy and command-palette
  tests passed. Refreshed generated references/evidence in dependency order.
  Continue bounded sequential repeats before the final full gate; do not launch
  simultaneous GUI fixtures that would invalidate each other's focus authority.
- First sequential JIT repeat failed the newly added full-identity equality
  while the read-held job remained foreground/ready at 13708 ms and the app was
  active/visible/focused. Failure cleanup sent HUP to its foreground/owning groups,
  reaped worker/session and released pane ownership cleanly. This is distinct
  from the original 4-second expiry and must not be hidden by retries.
- Code inspection: TerminalContextDockForegroundJobIdentity.epoch is a transient
  observation authority epoch, not OS process identity. Removing window eligibility
  cancels observation; reacquiring the same real job legitimately gets a new
  epoch. Equality across native palette focus transitions is therefore an
  overconstrained new harness assertion. Verify the physical job with session,
  foreground PGID plus primary PID/start seconds/microseconds/absolute time;
  allow a new authority epoch only with fresh argv and unchanged OS identity.
  Keep/strengthen content-free failure fields and expose epoch-change boolean
  in acceptance output to measure this distinction rather than guessing it.
- Add deterministic model regression: revoke window eligibility while argv is
  hidden, advance five seconds and assert content/operations/timers cleared;
  reveal while ineligible, reacquire and assert new authority epoch/loading with
  no stale argv; only a fresh inventory can show argv again for identical primary
  PID/start times and PGID/session. This distinguishes valid reacquisition from
  stale content without forcing native OS focus or relaxing privacy policy.
- Final rebuilt suites pass JIT/AOT with holds 5435/5413 ms. Sequential repeats
  pass JIT 5339 ms and AOT 5417 ms (observed epoch unchanged in those runs).
  The earlier failed repeat's individual predicate flags were not yet logged,
  so epoch mismatch in that particular run remains an inference, not a directly
  measured fact. The identity-definition/model regression establishes why full
  transient-epoch equality must not be the physical job lifetime assertion.
- Third final JIT run passed with hold 4916 ms and
  observation_epoch_changed=true while every OS identity/fresh-argv/elapsed/
  zero-write assertion passed. This directly confirms the valid native palette
  reacquisition case, independently of the earlier repeat's incomplete flags.

## Final bounded runtime repetitions

All six final runs used the 3500 ms scheduling pause, unchanged 10-second
reveal budget/1100 ms elapsed wait, exact release-output marker and complete
four-session shutdown. Final apps were rebuilt; repeats used those same apps.
Fixtures ran sequentially to preserve independent native focus authority.

| Runtime/run | Hold (ms) | Whole suite (ms) | Observation epoch changed |
| --- | ---: | ---: | --- |
| JIT rebuilt | 5435 | 12991 | false |
| AOT rebuilt | 5413 | 11685 | false |
| JIT repeat | 5339 | 12087 | false |
| AOT repeat | 5417 | 11261 | false |
| JIT repeat | 4916 | 11604 | true |
| AOT repeat | 5363 | 11308 | false |

- Three consecutive final passes per runtime without retrying failures. Native
  reacquisition with changed epoch also passed physical identity/fresh argv.
- Deterministic model focus-loss/reacquisition regression passed. Final full
  product gate passed without retry.

## Final verification and handoff

- CI=true DART_SUPPRESS_ANALYTICS=true make test passed: process-resource,
  PTY, renderer, AppleScript and App Intents native/Dart suites, parser tables,
  generated configuration/keybind/AppKit/compatibility/gap/daily-use evidence,
  localization/privacy/distribution checks, format (348 files, zero changes),
  static analysis and complete Dart test runner including the new epoch test.
- Focused Context Dock and command-palette tests plus standalone dart analyze
  passed. Rebuilt final native-content JIT/AOT and four sequential repeated runs
  are recorded above; all require exact process/Navigator/input/cleanup markers.
- Reviewed final diff and git diff --check; no diagnostic-only stage tracing,
  personal argv/path/input, temporary binary, unrelated product change, stale
  generated evidence or adjacent Engine edits are included. Only metadata-only
  failure observation remains, useful for classifying a future failure.
- Normal Process Inspector/privacy/focus policy is unchanged. Replaced the
  competing 4-second fixture timer with explicit release, rather than widening
  budgets or weakening acceptance; same OS identity is stricter than the original
  document-only reveal and unchecked elapsed snapshot. Driver remains bounded
  at 60 seconds; observed held-job failure teardown also released its owners.
- No remaining blocker or added follow-up for this scoped task. Existing
  low-priority PTY competing-reaper, Intel-native, real signing/notarization and
  real-time soak items remain unchanged and were not implemented out of order.
