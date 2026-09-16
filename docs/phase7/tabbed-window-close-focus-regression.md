# Phase 7 — Tabbed window Close and focus regression

- Status: complete
- Started: 2026-09-17
- Environment: Apple M1/arm64, macOS, stock Dart Developer JIT / Release AOT

## Purpose and background

Normal window Close must not terminate the Dart isolate when native tabs transfer
focus during asynchronous pane shutdown. Single-pane and tabbed windows must
share the existing macOS lifetime contract: Close removes the targeted pane and
its empty tab/window; closing the last window leaves the application running.
Application Quit remains a separate explicit operation.

The reported stack identifies `routeWindowEvent` calling `activateWindow` while
`TerminalApplicationState.removePane` holds its mutation guard across awaited
session disposal. Initial inspection confirms that focus events directly mutate
the model and synchronous subscription callback exceptions escape the stream's
`onError` handler. The worktree was clean at start, on `main` at `6720347`.

## Scope, exclusions, and dependencies

- Scope: product window-event ordering during asynchronous hierarchy mutation,
  stale identity rejection, normal Close lifetime, deterministic regression tests
  and real AppKit acceptance in both runtime modes.
- Preserve foreground-process confirmation, split collapse, neighboring focus,
  owner cleanup, and aggregate Quit admission.
- Exclude tab shortcut changes, unrelated Settings/Context Dock behavior, new
  close policies, and global relaxation of the model mutation guard.
- Dependencies: current application state, native hierarchy projection, pane
  Close coordinator, product action dispatch, and AppKit deferred Close events.
- Architecture: Dart owns product policy and model mutation; native adapters
  remain reusable OS boundaries (ADR-001/002/005).

## Acceptance and verification plan

1. Deterministically hold an asynchronous hierarchy mutation and deliver native
   focus/Close events. No reentrant mutation or uncaught isolate error occurs.
2. Retained tabs receive the correct focus; removed identities cannot reactivate.
   Duplicate Close requests do not remove an unintended neighbor.
3. Real native Close works with one and multiple tabs, including closing the last
   pane. The application remains attached and can create a new window afterward.
4. Existing confirmation, explicit Quit, and zero-resource cleanup tests pass.
5. Run focused model/hierarchy/action tests, formatting/static analysis, both
   runtime integration suites appropriate to this lifecycle, and full project
   tests/evidence freshness gates. Record exact results before completion.

## Investigation

- `terminal_application_state.dart`: `_ensureCanMutate` protects all model writes;
  `removePane` reserves it until pane disposal and identity removal complete.
- `terminal_application.dart`: the local `routeWindowEvent` currently writes
  active/selected identities on every focus-gained event without coordinating
  with the asynchronous Close path.

## Implementation decisions and verification history

- `macos_application.json` already sets `terminateAfterLastWindowClosed: false`;
  the generic JIT/AOT delegates honor this. No native lifetime policy change is
  needed. The normal product `closed` completer is completed by explicit Quit
  or fatal error, not empty hierarchy.
- Adopted a Dart-owned bounded notification coordinator rather than removing
  the state guard or swallowing the reported error. The model exposes a
  content-free completion boundary, resolved even on failed transactions.
  Notifications coalesce by live tab/type; removed tabs are rejected on replay;
  input is not retained; busy native Close is refused immediately without later
  closing a neighbor. Synchronous callback errors use the existing fatal-error
  recorder rather than becoming unhandled stream callback exceptions.
- A first application patch assumed window-subscription synchronization was a
  declared function; inspection showed an assigned closure. The patch failed
  atomically with no application changes and was reapplied to the actual form.
- The first focused test compile revealed that deferred Close requires an
  operation ID and zero modifiers use `ModifierKeys(0)` rather than `.none`.
  Fixed the fixture, retaining the real API contract.

The attempts below are chronological. The final verification result at the end
supersedes the pending states recorded during earlier attempts.

### Focused checks and real-product fixture

- `dart run test/terminal_application_state_test.dart`: passed. A shutdown
  completer holds the exact mutation guard while 100 focus gains coalesce to one
  final notification per tab. A later focus loss replaces the stale gain;
  removed-tab gains are discarded; busy Close is refused; mouse input is not
  replayed. Disposal cancels pending notifications. Last-pane removal leaves
  the state reusable, and a fresh window can be created.
- `dart run test/terminal_native_hierarchy_test.dart` and
  `dart run test/terminal_product_hierarchy_actions_test.dart`: passed, including
  existing confirmation, cleanup, native projection, and action admission paths.
- Focused `dart analyze`: no issues after sorting the new import into the
  existing alphabetized directive section. Focused format completed.
- Extended the ordinary product actions fixture to issue real native deferred
  Close requests until the current multi-window/tab/split hierarchy is empty.
  A bounded 1 ms timer injects one native-protocol focus gain only while real
  asynchronous removal is active. This complements actual native Close events
  with deterministic evidence that the reported router path is exercised.
- The fixture requires tabbed and final-single Close, empty application staying
  alive, successful Command-N/menu creation afterward, then normal explicit
  Quit. Total created/clean sessions become six (five initial plus one reopened),
  and the final aggregate Quit owns only that one reopened pane. The integration
  driver validates the new marker and exact shutdown counts.
- Native boundary inspection confirms `da_window_request_close` calls the same
  `windowShouldClose:` admission delegate used by the red window button; normal
  request deferral and operation-ID replies are exercised rather than bypassed
  via programmatic `close()`.
- Developer JIT actions integration: passed, `elapsed_ms=3353`, including the
  required Close/focus/empty-app/reopen marker and all six clean session
  shutdowns. Release AOT build and remaining gates are still pending.
- Release AOT actions integration: passed, `elapsed_ms=8131`, with the same
  native deferred Close/focus/empty-app/reopen assertions and six clean session
  shutdowns. Existing native hierarchy Close/Quit integration and full gates
  remain pending.
- Added the new coordinator to the existing Phase 7 cleanup criterion's source
  audit. The reviewed exact source-reference total increases from 19 to 20;
  updated the corresponding test expectation, without weakening any criterion
  or removing existing evidence.
- `make RUNTIME_ARCH=arm64 runtime-user-actions-integration
  runtime-native-hierarchy-integration`: passed in both modes. The existing
  four-pane hierarchy/foreground Close confirmation/aggregate Quit/resource
  suite passed (`developer-jit elapsed_ms=59911`, `release-aot
  elapsed_ms=64484`), including flood/input fairness and deterministic cleanup.
- All four checked evidence artifacts were regenerated in dependency order.
  Seven changed Dart files passed focused formatting; `git diff --check` passed.
  No native source or adjacent-repository user modifications were changed.
- First `make test` stopped at the unchanged `dart_pty_macos` case `live Dart
  child cannot steal native PTY completion` (`test/run_tests.dart:900`,
  `diagnostics.firstWhere` for `externalReapObserved`: `Bad state: No element`).
  Its prior exit-code-37 check had passed. The fixture expects an external Dart
  reap on every run, while native/Dart child reap is inherently competing; no
  root cause is asserted beyond the missing diagnostic event. The same failure
  is recorded in earlier task memos (e.g. Settings effective config and Context
  Dock process input privacy). Runtime builds/suites had already finished, so
  concurrency with those builds is not a proven explanation here.
- A read-only process-list check was denied by the sandbox; it made no changes.
  Runtime drivers themselves had already returned success with clean owners.
  Retry the untouched PTY gate alone, then the full gate; do not weaken or edit
  the competing-reaper fixture to make this unrelated Close task pass.
- `make dpty-dart-test` immediately passed unchanged in isolation, including
  the competing-reaper case. Full gate rerun remains required. Track the
  repeatedly observed fixture nondeterminism as a separate low-priority item,
  not a scope expansion into PTY production implementation here.

## Final verification and handoff

- The second full `make test` passed: all native capability tests, Dart facade
  tests, source/compatibility/privacy/distribution audits, generated evidence
  freshness, formatting of 348 Dart files (zero changes), clean static analysis,
  and the complete `test/run_tests.dart` suite (`dart_terminal tests passed`).
  The original competing-reaper fixture also passed unchanged in this run.
- Both arm64 bundles were rebuilt and passed ordinary product actions and the
  existing native hierarchy suite. Deferred focus during real Close, tabbed and
  single Close, application retained with no windows, new-window creation, exact
  six-session cleanup, process-risk confirmation, and explicit Quit passed.
- Final diff review and whitespace checks passed. Only task-owned product,
  tests, checked evidence, documentation, and progress files are included;
  adjacent repository's three pre-existing user changes remain untouched.
- No required Close work remains. Reload the product by restarting the existing
  developer command or the rebuilt application; running sessions were not killed
  or restarted automatically.
- Separate low-priority follow-up added for the repeatedly observed, unrelated
  PTY fixture nondeterminism. Its investigation and acceptance plan are in
  `../phase2/pty-competing-reaper-fixture-determinism.md`; no PTY production or
  test source was changed by this task.
