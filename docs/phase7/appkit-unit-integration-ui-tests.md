# Phase 7 — AppKit unit, integration, and UI tests

- Status: in progress
- Started: 2026-09-09
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `AppKit unit、integration、UI tests`
- Related: UI-01 through UI-05, PERF-02, REL-01, and every preceding
  `docs/phase7/` task record

## Purpose

Close Phase 7 with one reviewable test contract that proves the completed
window, tab, split, input, menu, restoration, close/quit, scheduling, and
resource behavior at the pure-Dart, fake-AppKit integration, and real-AppKit UI
layers. Make loss of a required layer or Phase 7 exit-condition assertion fail
the normal gate instead of relying on prose or a previous manual run.

## Background and confirmed starting state

- The preceding multi-pane scheduling/resource item is complete at terminal
  commit `c87afc4 Verify cross-pane fairness under flood`. The terminal and
  adjacent `dart_appkit` worktrees were clean when this item started.
- `make test` imports every current standalone Dart test. Phase 7 already has
  focused unit coverage for bounded application topology, focus/index
  ownership, action/menu dispatch, close/quit transactions, restoration
  encoding/ownership, pane scheduling, and resource cleanup.
- `test/terminal_native_hierarchy_test.dart` supplies a fake-AppKit integration
  layer. It projects two tabs/four panes, exercises split geometry, focus,
  metadata, fullscreen state, restoration/reopen, Close/Quit, and exact native
  handle/session cleanup. The restoration unit test covers two logical windows,
  three tabs, six panes, and a four-pane nested split with fresh ownership.
- The gated real-AppKit hierarchy suite creates two native tabs/four real PTYs
  and four Metal/text-input surfaces. It sends raw key plus marked/committed IME
  input to every focused pane, rejects wrong-pane or wrong-byte delivery, runs
  exact Close/Quit behavior, measures a 100 MiB cross-pane flood, and requires
  zero final resources in Developer JIT and Release AOT.
- The gated restoration suite creates and restores two generations of one
  logical window/two native tabs/four panes, verifies fullscreen/display/cwd,
  and reclaims eight exact PTY/Metal/text-input owners. Thus repeated real
  restoration is covered, but real AppKit does not yet prove more than one
  logical window in the restored graph.
- The real command-palette acceptance injects Shift-Command-P, dispatches
  `pane.focus-next` exactly once, observes zero terminal writes, and restores
  first responder. The hierarchy suite proves per-pane raw/IME isolation, but
  its final summary does not explicitly bind menu-shortcut non-leakage to the
  four-pane graph.
- There is no versioned Phase 7 coverage inventory. A test file, runtime marker,
  or required exit-condition assertion could be removed while the aggregate
  runner still succeeds.

## Scope

- A deterministic, versioned Phase 7 acceptance inventory that assigns every
  exit criterion to unit, fake-AppKit integration, and real-AppKit UI evidence,
  checks implementation/test references for freshness, and rejects missing or
  duplicate ownership.
- Repeated fake-AppKit projection/restoration of a bounded multi-window,
  multi-tab graph with four panes per logical window, fresh identities, exact
  first-responder selection, and zero retained session/native resources.
- Real-AppKit dual-runtime acceptance with two logical windows, multiple native
  tabs, four panes per logical window, two fresh restoration generations, and
  exact PTY/Metal/text-input/native/worker cleanup.
- An explicit four-pane menu-shortcut isolation assertion that combines the
  native shortcut path with focused-pane traversal and proves no terminal write
  or unfocused-pane input.
- Final formatting, analysis, source/bundle audits, all runtime suites,
  documentation/feature evidence reconciliation, and Phase 7 completion.

## Out of scope

- New user-visible window/tab/split actions, configuration files, themes, shell
  integration, settings UI, Quick Terminal, or any Phase 8+ product feature.
- Replacing the generic `dart_appkit` action or text-input policy with
  terminal-specific behavior. Test hooks remain gated; terminal policy remains
  in this repository.
- System input-source changes, destructive display reconfiguration, long soak,
  x86_64/Rosetta/Universal, or Intel-native evidence before the M1 contract.
- Weakening existing byte, timing, confirmation, or resource bounds to make a
  UI run pass.

## Dependencies

- The completed Phase 7 application state, native hierarchy, action/menu,
  restoration, close/quit, and shared pane scheduler contracts.
- `dart_appkit` protocol v6 test hooks and generic menu/window/tab/split APIs.
- The existing M1 Developer JIT and Release AOT bundle/integration harness.

## Ordered subtasks

### 1. Deterministic coverage contract and repeated fake-AppKit topology

- Add a versioned Phase 7 acceptance inventory and a normal-gate checker that
  maps every exit criterion to concrete source, unit, integration, and UI
  evidence without storing terminal content.
- Add a bounded repeated fake-AppKit create/capture/restore/project/dispose test
  for two logical windows, two tabs and four panes per window. Require fresh
  identities, exact selected tab/focused first responder, one shutdown per
  session, and zero native handles after every generation.
- Completion: focused tests, formatting, analysis, and complete `make test`
  pass; findings and results are recorded; the child is committed before the
  real-AppKit child starts.

### 2. Multi-window dual-runtime UI and menu-shortcut isolation

- Extend the gated product restoration acceptance to two logical windows, two
  tabs and four live panes per window, then restore the same graph into fresh
  owners. Preserve existing fullscreen, migration, reopen, cwd, and cleanup
  assertions while updating exact counts.
- Bind the native Shift-Command-P command-palette shortcut result to the
  four-pane hierarchy acceptance: one application action, zero terminal write,
  focused-pane change only, and no unfocused-pane raw/IME marker.
- Completion: focused Developer JIT and Release AOT hierarchy/restoration UI
  suites expose exact content-free summaries and pass with all resources at
  zero; complete terminal gates pass and the child is committed.

### 3. Full regression, evidence reconciliation, and Phase 7 closeout

- Run `make test`, source audit, both bundle audits, and the complete
  Developer JIT/Release AOT runtime matrix after the final UI changes.
- Reconcile README and FEATURE_MATRIX evidence with the versioned inventory,
  record exact results and any residual risk, and mark the child and parent
  roadmap items complete only if every Phase 7 exit condition is independently
  supported.
- Completion: all checks pass, both worktrees are clean except for this child,
  one final task-local commit is created, and no Phase 8 work is started.

## Acceptance criteria

1. The normal test gate fails if a Phase 7 exit criterion, required layer, test
   entry point, runtime summary, or implementation reference is missing, stale,
   duplicated, or assigned no owner.
2. Three bounded fake-AppKit generations and two real-AppKit generations each
   exercise two logical windows, two tabs and four panes per logical window.
3. Every restored pane/window/tab/split receives a fresh runtime identity while
   visual order, selected tab, focused pane, split geometry, metadata, cwd, and
   placement semantics remain stable.
4. A real native menu shortcut changes only application focus/action state. It
   dispatches exactly once, writes zero bytes to terminal input, restores the
   correct first responder, and does not complete input in another pane.
5. Raw key and IME commit remain exact and isolated for all four hierarchy
   panes in both runtimes.
6. Every generation and close/quit path ends with zero PTY, Metal atlas pin,
   text-input client, native handle, shared scheduling work, and worker process.
7. The 100 MiB cross-pane bound remains at most twice the same-launch idle
   baseline, with input visible before flood completion and bounded queues.
8. No terminal text, command, path, environment secret, or clipboard content is
   added to persistence or ordinary machine summaries.

## Verification plan

- Focused Dart tests for the inventory checker and repeated fake hierarchy.
- Full `make test` after each source/test child.
- Focused `runtime-native-hierarchy-integration` and
  `runtime-restoration-integration` for Developer JIT and Release AOT.
- Final `runtime-source-check`, both runtime bundle audits, and `runtime-verify`.
- Exact diff/staged-diff review and worktree checks before every commit.

## Investigation and decision log

- 2026-09-09: reread `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, the complete
  Phase 7 roadmap section, all Phase 7 task records, repository/test inventory,
  aggregate test runner, Makefile runtime gates, fake hierarchy/restoration
  tests, product hierarchy/restoration implementations, and runtime smoke
  assertions. No later Phase work was started.
- 2026-09-09: existing coverage is substantive enough that this is a closure
  and gap-hardening task, not a replacement UI framework. The selected design
  preserves current focused tests and adds a small explicit inventory so
  removal of an evidence layer becomes observable.
- 2026-09-09: the two concrete gaps are (a) no real-AppKit multi-logical-window
  restoration graph and (b) no four-pane summary that explicitly binds the
  native menu-shortcut zero-write assertion to pane isolation. Both are test
  scope and require no generic-library terminal policy.
- 2026-09-09: the task is divided into three ordered commits because the first
  child changes deterministic/fake test infrastructure, the second runs and
  may debug real AppKit in two runtime modes, and the third is an evidence-only
  full-matrix closeout. Phase 8 remains untouched.
- 2026-09-09: the first inventory generation correctly failed because its
  fairness source needle looked for a call-site literal while the product uses
  the named `defaultReadBatchesPerEventLoopTurn` constant. The requirement now
  pins the public terminal policy declaration (`2`) rather than formatting of
  one constructor call.
- 2026-09-09: the first repeated fake-AppKit run failed its generation-0
  cleanup assertion because the test recorded the session-list start after the
  initial eight sessions had already been constructed. This was test
  bookkeeping, not a retained owner: the assertion now addresses each exact
  eight-session generation by its bounded index range. The rerun passed all
  three generations.
- 2026-09-09: the hierarchy UI test now counts product text-input deliveries
  around the native Shift-Command-P menu item, opens the real command palette,
  selects `pane.focus-next`, and restores the view for the newly focused pane.
  The accepted action count is one and the delivery delta is zero. The existing
  four-pane raw-key/IME exact-marker sequence continues to reject an unfocused
  or malformed delivery.
- 2026-09-09: the restoration UI graph now contains two logical windows. Each
  owns two native tabs and four panes across two splits, for eight concurrent
  real PTY/Metal/text-input owners. Both windows and all presentation/cwd/split
  state are persisted, the Dock reopen reconstructs eight fresh owners, and
  both generations contribute sixteen exact clean shutdown results.

## Verification log

- Focused formatting and analysis of the coverage tool/test and fake hierarchy
  test passed with no issues after generation.
- Direct `phase7_appkit_acceptance_test.dart` and
  `terminal_native_hierarchy_test.dart` runs passed. The current deterministic
  inventory covers 4 exit criteria, 12 implementation references, 9 unit-test
  references, 4 fake-AppKit integration references, and 6 real-UI assertions.
- The first complete `make test` reached its format gate and formatted the two
  newly added untracked coverage files in its comparison output, then
  intentionally exited nonzero because `--output=none
  --set-exit-if-changed` observed that formatting was still required. That
  check does not write files. The two files were then formatted explicitly.
- The complete `make test` rerun passed dependency resolution, all generated
  data/inventory freshness checks, formatting of 209 files with zero changes,
  analysis with no issues, and the aggregate runner with
  `dart_terminal tests passed`.
- After the UI changes, `make test` again passed all freshness, formatting,
  analysis, and aggregate test gates.
- `make RUNTIME_ARCH=arm64 runtime-native-hierarchy-integration` passed in
  both modes. Developer JIT measured 26,923 us idle versus 28,776 us under
  flood (1.069x, 102 scheduler yields); Release AOT measured 22,467 us versus
  22,463 us (1.000x, 76 yields). Both runs also accepted the four-pane native
  command-palette shortcut with zero terminal delivery.
- `make RUNTIME_ARCH=arm64 runtime-restoration-integration` passed in both
  modes with `generations=2 windows=2 tabs=4 panes=8`: Developer JIT completed
  in 4,386 ms and Release AOT in 3,716 ms. Each mode validated 16 exact clean
  PTY shutdowns, 16 disposed Metal owners, zero text-input clients, zero native
  handles, one worker lifecycle, bounded content-free persistence, and
  duplicate-reopen coalescing.
