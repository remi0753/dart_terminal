# Cwd, title, prompt marks, jump-to-prompt, and close hints

- Status: complete
- Started: 2026-09-11 after commit `d901085`
- Completed: 2026-09-11
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `cwd/title/prompt mark/jump-to-prompt/close hint`
- Feature-matrix owner: CFG-06 (semantic metadata and actions portion)
- Depends on: `docs/phase8/shell-integration.md`,
  `docs/phase7/title-tab-metadata-cwd-proxy-icon.md`,
  `docs/phase7/per-pane-close-app-quit-confirmation.md`, and
  `docs/phase8/declarative-keybind-action-reference.md`

## Purpose

Turn the bounded shell-integration channel into useful, privacy-safe terminal
semantics: authoritative local cwd and title metadata, prompt/command marks,
user actions that move between prompts, and a close hint that improves process
risk classification without weakening the existing confirmation policy.

## Background

- The preceding Phase 8 item now injects a validated, versioned bootstrap into
  zsh, supported bash/fish/nushell launch contracts, and projects each immutable
  launch plan into new ordinary panes. Its resources intentionally publish only
  an execution marker and defer all semantic escape sequences to this item.
- Phase 7 already parses OSC 0/2 titles and local OSC 7 cwd into bounded terminal
  metadata, projects title/cwd to tabs and native proxy icons, inherits cwd for
  later panes, and classifies foreground process-group risk before close.
- The action registry, declarative keybindings, native menu, and command palette
  already share one bounded catalog, but no prompt-navigation actions exist.

## Scope

- Define one versioned, bounded shell-to-terminal semantic protocol for cwd,
  title, prompt start/end, command start/end, and close-relevant shell state.
- Emit that protocol from independently authored zsh/bash/fish/nushell resources
  without recording command text, history, prompt text, or arbitrary environment
  values.
- Parse and retain prompt marks with explicit scrollback/memory bounds and expose
  deterministic previous/next prompt navigation through the existing action
  catalog and pane viewport.
- Reuse the existing local OSC 7/title projection and close coordinator, adding
  only validated semantic inputs that materially improve correctness.
- Add unit/fake-PTY/real installed-shell coverage and M1 Developer JIT/Release
  AOT product acceptance, then update user/evidence documentation.

## Out of scope

- Settings UI/effective-config inspector, which is the following roadmap item.
- Shell command contents, command history, prompt rendering customization,
  telemetry, remote cwd trust, arbitrary URL opening, desktop notifications,
  progress reporting, or Phase 9 protocol extensions.
- Installing optional shells or editing user startup files.
- Weakening existing foreground-process close confirmation or making semantic
  hints authoritative when OS process evidence disagrees.

## Dependencies and boundaries

- Shell output remains untrusted terminal input. OSC/semantic payloads require
  byte/field limits, local-host validation where applicable, and fail-closed
  behavior.
- Mutable prompt marks belong to the pane's terminal model/scrollback owner;
  AppKit receives only product actions and already-bounded presentation state.
- Shell resources and their hash contract must be updated transactionally; any
  mismatch disables the entire integration generation.
- Close hints may refine presentation or avoid a false positive only when
  corroborated by safe process/session state. They may never hide a known live
  foreground process group.

## Initial completion conditions

1. All four shell resources emit the same versioned semantic contract while
   preserving ordinary startup and integration disablement.
2. Local cwd/title metadata remains bounded and drives the existing tab/window,
   proxy-icon, and new-pane inheritance paths without trusting remote origins.
3. Prompt marks survive parsing, wrapping, scrolling, resize, and bounded
   scrollback eviction; previous/next actions move only the intended pane.
4. Close hints compose conservatively with OS foreground-process evidence and
   never reduce an active-process warning incorrectly.
5. Focused tests, resource/source/bundle audits, complete tests, and M1
   Developer JIT/Release AOT product acceptance pass before parent completion.

## Validation approach

- Compare the pinned reference behavior, then document an independent protocol
  and threat model before authoring resources.
- Pure-Dart parser/model/action/close-policy tests, fake PTY launch/output tests,
  and real zsh plus conditional installed-shell execution.
- Generated resource freshness and manifest/bundle audit.
- Focused runtime scenarios, `make test`, and
  `make RUNTIME_ARCH=arm64 runtime-verify` at the final boundary.

## Ordered subtasks

1. Add a bounded OSC 133 `A`/`B`/`C`/`D`/`P` protocol model and parser
   projection. Mark existing screen rows without retaining options, command
   lines, prompt text, or exit status, and expose only a small shell-state hint.
2. Extend all four versioned shell resources to emit prompt/command lifecycle,
   local OSC 7 cwd, and bounded cwd-derived OSC 2 title updates. Regenerate the
   resource contract transactionally and cover startup, opt-out, hook
   coexistence, hostile cwd, and installed-shell behavior.
3. Add deterministic previous/next prompt scanning to the viewport and expose
   focused-pane actions through the shared action catalog, keybinding
   vocabulary, native menu, and command palette. Alternate screens and missing
   marks remain no-ops.
4. Compose the semantic shell-state hint with process snapshots and pane/app
   close admission. A known foreground process or unavailable OS evidence
   always confirms; an idle owning shell executing a builtin/function gains an
   additional confirmation, while unknown/forged semantic bytes can never make
   the pre-existing policy less conservative.
5. Add a gated real-product scenario, pass M1 Developer JIT and Release AOT plus
   the complete regression/resource/source audit matrix, reconcile README and
   feature evidence, and close the parent only after every prior subtask passes.

Each subtask is independently verified, documented, marked complete, and
committed. `ROADMAP.md` and this memo are reread after every commit before the
next subtask begins.

## Current subtask: bounded semantic protocol and row projection

- Status: complete
- Started: 2026-09-11
- Completed: 2026-09-11
- Purpose: convert the already bounded OSC channel into a privacy-safe semantic
  state machine and populate the existing row flags before any shell resource
  starts emitting the protocol.
- Scope: accept only OSC 133 actions `A`, `B`, `C`, `D`, and `P`; reject malformed
  action forms and oversize payloads; ignore all optional fields without
  decoding or retaining them; mark primary/alternate active rows consistently;
  reset transient state at the terminal reset boundary; expose a bounded
  unknown/prompt/input/command-output hint from `TerminalScreenSet`.
- Out of scope: resource changes, navigation actions, close-policy changes,
  runtime UI scenarios, settings UI, command text, exit codes, and OSC 133
  extensions `I`, `L`, or `N`.
- Dependencies: the VT parser's bounded OSC buffer, compatibility surface and
  generated manifest, row damage/generation ownership, scrollback copy/reflow,
  and screen-set reset/alternate-screen semantics.
- Completion conditions: valid markers change only the intended semantic state
  and row flags; malformed/oversize/unknown forms are safely unsupported;
  wrapping, line feed, scrolling, resize/reflow, reset, and alternate-screen
  tests preserve the documented ownership; existing parser compatibility and
  privacy guarantees remain intact.
- Validation: focused parser/screen/viewport/snapshot tests, generated
  compatibility freshness, formatting, analysis, complete tests, source audit,
  diff review, roadmap update, and one task-scoped commit.

## Current subtask: four-shell lifecycle and metadata resources

- Status: complete
- Started: 2026-09-11 after commit `19eb963`
- Completed: 2026-09-11
- Purpose: make each validated integration resource emit the semantic protocol
  consumed by the preceding parser and refresh safe local metadata without
  collecting command or prompt content.
- Background: the five-file version-one bundle currently publishes only marker
  environment variables. Its immutable launch plans, bundle validation,
  ordinary product projection, fake PTY coverage, and installed zsh/bash probes
  are complete and must remain compatible.
- Scope: independently author idempotent zsh/bash/fish/nushell hook composition;
  emit OSC 133 lifecycle markers, a local `file://localhost` OSC 7 cwd, and a
  bounded cwd-basename OSC 2 title; reject control-bearing metadata at the
  source; regenerate the exact byte/hash contract; extend resource/source,
  startup, opt-out, hook-coexistence, fake/parser, and installed-shell tests.
- Out of scope: prompt navigation actions, close policy, runtime GUI acceptance,
  settings UI, command-derived titles, command/history/prompt capture, shell
  installation, or editing user startup files.
- Dependencies: shell hook APIs and startup ordering, the existing injection
  cleanup contract, 32 KiB per-resource/128 KiB total caps, OSC title/cwd parser
  bounds and local-authority rules, optional-shell absence, and the version-one
  manifest paths.
- Completion conditions: all four resources express the same lifecycle and
  metadata intent with shell-native safe encoding; disabled/unsupported paths
  emit none; user hooks/startup remain once-only; hostile/oversize cwd cannot
  inject controls; resource validation and real/fake shell/parser evidence pass
  without changing immutable launch-plan behavior.
- Validation: resource/source assertions, fake semantic stream replay, real zsh
  and forced non-Apple bash PTYs, conditional installed fish/nu tests, resource
  generation/check, focused integration/projection/metadata/parser tests,
  formatting, analysis, complete tests, source/bundle audit, diff review,
  roadmap update, and one independent commit.

## Current subtask: viewport prompt navigation and shared actions

- Status: complete
- Started: 2026-09-11 after commit `071fa18`
- Completed: 2026-09-11
- Purpose: turn retained prompt row semantics into deterministic previous/next
  navigation for the focused pane through the same action catalog used by
  keybindings, native menus, and the command palette.
- Background: the primary scrollback and active grid already preserve prompt
  flags plus logical-line identity through wrapping, scroll, eviction, and
  reflow. `TerminalViewport` is the sole mutable scroll-position owner, while
  the standard product catalog currently exposes 16 actions and the normal
  hierarchy resolves all pane-scoped product state from the focused pane ID.
- Scope: add previous/next prompt target discovery and movement to the viewport;
  collapse soft-wrapped rows from one prompt logical line into one target; add
  stable catalog definitions and focused-pane product registrations; refresh
  selection/surface projection after a move; regenerate the keybinding/action
  reference and update exact catalog tests and runtime expectations.
- Out of scope: shell protocol/resource changes, default shortcuts, prompt text
  selection, cursor relocation, PTY input, alternate-screen scrolling, close
  policy, final real-product semantic-shell acceptance, and settings UI.
- Dependencies: semantic row flags, scrollback eviction/reflow identity,
  viewport offset synchronization, action dispatcher serialization, product
  focus authority, command palette/menu dynamic availability, keybinding
  reference generation, and existing AppKit surface viewport notification.
- Completion conditions: previous/next choose only distinct retained prompt
  logical starts in deterministic order; repeated navigation moves between
  available targets; alternate screens, missing/evicted marks, boundaries, and
  already-bottom next operations are no-ops; only the focused pane changes;
  menu/palette/keybinding catalogs expose both stable actions with no default
  shortcut or PTY write; all derived references and exact action counts agree.
- Validation: focused viewport/action/menu/palette/reference/product tests,
  formatting and analysis, generated-reference freshness, complete tests,
  source/bundle audit, diff review, roadmap update, and one independent commit.

## Current subtask: conservative close-hint/process-snapshot composition

- Status: complete
- Started: 2026-09-11 after commit `a2b9344`
- Completed: 2026-09-11
- Purpose: cover shell builtins and functions that execute in the owning shell
  without weakening the OS-backed foreground-process close policy.
- Background: the existing pane and application close transactions classify a
  content-free child/owning/foreground process-group snapshot. That detects a
  distinct foreground job but can regard a builtin/function running in the
  owning shell as idle; the bounded OSC 133 model now exposes only an
  unknown/prompt/input/command-output lifecycle hint.
- Scope: compose the focused pane's semantic shell state with its existing
  process snapshot at the pane-owned close-decision boundary; add confirmation
  for an otherwise idle owning shell in command-output state; retain all known
  foreground and unavailable-evidence confirmations; project the same policy
  through per-pane Close and aggregate Quit; cover stale/forged markers and
  snapshot failure without retaining command content.
- Out of scope: process names or command lines, exit status, new shell protocol
  fields, prompt-navigation changes, confirmation UI redesign, final real-
  product semantic-shell acceptance, settings UI, or any reduction of an
  existing warning.
- Dependencies: `TerminalSemanticShellState`, session-owned `TerminalScreenSet`,
  the typed process snapshot/disposition model, pane close decision, aggregate
  quit transaction, and existing exactly-once confirmation invalidation.
- Completion conditions: known distinct foreground work and unavailable OS
  evidence still require confirmation regardless of terminal bytes; idle
  owning-shell command output additionally requires confirmation; prompt,
  input, unknown, reset, and absent-session hints preserve existing decisions;
  per-pane and aggregate callers use the same immutable classification without
  reading process or terminal content.
- Validation: focused semantic/pane/close/quit tests including forged-marker and
  failure matrices, formatting and analysis, complete tests, source/bundle
  audit, diff review, roadmap update, and one independent commit.

## Current subtask: M1 dual-runtime semantic-shell acceptance and parent closure

- Status: complete
- Started: 2026-09-11 after commit `d3ac388`
- Completed: 2026-09-11
- Purpose: prove the complete shell semantic path in packaged Developer JIT and
  Release AOT products, reconcile durable evidence, and close the parent only
  if every preceding child and Phase 8 boundary remains satisfied.
- Background: unit/fake/installed-shell coverage now owns the bounded parser,
  version-two four-shell resources, cwd/title projection, prompt navigation,
  and warning-only close hint. The existing gated shell-integration product
  suite still checks only version-one marker/startup/cleanup behavior for zsh
  plus explicit disablement and must be advanced transactionally.
- Scope: extend the gated real-AppKit/PTY/Metal zsh scenario to verify version
  two lifecycle markers, local cwd/title metadata, retained prompt marks,
  previous/next shared-action navigation, an owning-shell blocking builtin
  close confirmation, idle aggregate Quit, and full resource cleanup; keep an
  explicit `none` run proving semantic disablement; update driver assertions,
  README/feature evidence, and all generated pins; run both arm64 modes and the
  complete repository audit matrix.
- Out of scope: installing fish/nushell/new bash, changing user startup files,
  command/prompt/process content in machine output, new protocol fields or
  shortcuts, settings UI/effective-config inspector, x86_64/Rosetta/Universal,
  or any Phase 9 capability.
- Dependencies: the existing environment-gated shell integration CLI option,
  normal hierarchy dispatcher/menu/close/quit ownership, bundled zsh resource,
  session metadata and semantic model, viewport actions, runtime integration
  driver, generated acceptance/coverage evidence, and M1 build toolchain.
- Completion conditions: detect mode proves the complete semantic lifecycle and
  one additive builtin warning without leaking content; none mode proves zero
  semantic projection; both modes exit cleanly with one session each and zero
  text/native owners; Developer JIT and Release AOT emit the same bounded
  acceptance contract; complete tests, runtime-verify, source/bundle audits,
  docs/evidence, and parent checks all pass.
- Validation: focused application/driver tests, both shell-integration runtime
  modes, full `make test`, `make RUNTIME_ARCH=arm64 runtime-verify`, source and
  bundle audits, final diff/privacy review, roadmap parent/child update, and one
  independent commit.

### M1 semantic-shell acceptance implementation log

- The existing gated product path can own the final proof without another CLI
  option or test suite. It now receives the already-product-owned pane close
  coordinator so the scenario can inspect and cancel the same confirmation
  transaction used by native Close.
- Detect mode is extended in one session from initial semantic input through
  version-two environment validation, local cwd/title projection, bounded
  retained row flags, shared previous/next prompt actions, and a blocking zsh
  `read` builtin classified as `owningShellCommand`. The confirmation is
  cancelled before input completes the builtin; the shell must return to idle
  before aggregate Quit. None mode retains the same startup check while
  requiring unknown semantic state, absent metadata, unavailable prompt
  actions, and an idle owning shell.
- The runtime driver creates an isolated directory whose basename contains a
  space, passes it only through a dedicated acceptance environment variable,
  and checks content-free boolean summaries. No cwd, command, prompt, or
  process content is added to machine output.
- The first `dart analyze` attempt on 2026-09-11 stopped before analysis because
  the sandbox denied a modification-time write to
  `~/.dart-tool/dart-flutter-telemetry-session.json`. This is an environment
  boundary rather than a diagnostic; retry with `DART_SUPPRESS_ANALYTICS=true`
  in the established approved execution boundary.
- The telemetry-suppressed analyzer reports no issues. The first complete
  semantic-shell runtime target passes without product changes in both arm64
  modes: Developer JIT reports the two-policy contract in 2,106 ms and Release
  AOT in 1,004 ms. Each mode proves detect and none, version-two bundle/startup
  cleanup, semantic state and row flags, local metadata, shared prompt
  navigation, the cancellable builtin close warning, idle Quit, two clean
  sessions, and zero remaining text clients or native handles.
- README and CFG-06 now describe the completed version-two semantic contract
  and dual-runtime proof. Deterministic evidence regeneration changes only the
  two expected `terminal_application.dart` hashes in Phase 7 AppKit acceptance
  and the README/FEATURE_MATRIX hashes in compatibility coverage; the latter
  retains 9 fix families, 9 cases, and 417 split runs. `git diff --check`
  remains clean.
- The complete `make test` gate passes every generated contract and evidence
  freshness check, formats 233 Dart files without changes, reports no analyzer
  issues, and completes the aggregate test runner with `dart_terminal tests
  passed`.
- The first full arm64 `runtime-verify` attempt passes the repeated complete
  test gate, source audit (436 tracked, zero product-native, one reviewed
  test-native source), both bundle audits, ordinary display/hierarchy/actions/
  configuration/theme integrations, and the new semantic-shell integration in
  both modes. It then stops in the unchanged Developer JIT restoration scenario:
  fullscreen-enter completion does not arrive within its existing eight-second
  timeout at `terminal_application.dart:5383`. The pane, worker, and native
  resources still shut down cleanly. Run restoration alone next to distinguish
  transient AppKit timing from a reproducible blocker; do not weaken its
  acceptance condition.
- The immediate focused `developer-jit-restoration` retry reproduces the same
  external boundary: the native window is visible on a concrete screen but the
  product reports `active=false`, and no real fullscreen-enter event arrives
  within eight seconds. PTY, worker, pane, and AppKit-owned resources again
  clean up successfully. This exactly matches the previously resolved and
  documented managed-desktop condition in
  [`../phase7/fullscreen-runtime-acceptance-blocker.md`](../phase7/fullscreen-runtime-acceptance-blocker.md),
  whose safe recovery requires the launched DartTerminal test window to receive
  genuine foreground ownership.
- No timeout, injected fullscreen event, deprecated force-activation path, or
  weakened assertion is accepted as a fix. The semantic-shell implementation,
  focused dual-runtime acceptance, complete unit gate, and evidence updates are
  retained uncommitted, while the final child and its parent remain unchecked.
  On resume in a usable interactive desktop, rerun focused Developer JIT and
  Release AOT restoration, then the complete arm64 `runtime-verify`; only a
  clean matrix permits final review, roadmap completion, and the required
  independent commit.
- 2026-09-11 resume: the next focused Developer JIT restoration run receives
  genuine foreground ownership and passes its real fullscreen enter/exit,
  migration, reopen, two-generation 2-window/4-tab/8-pane contract, and clean
  resource release in 4,968 ms. The external foreground blocker is cleared for
  this resumed run; confirm the same Release AOT contract before repeating the
  full matrix.
- The focused Release AOT restoration contract also passes, including both
  real fullscreen transitions and clean ownership across two generations, in
  3,861 ms. Both modes are green at the previously blocked boundary; repeat the
  complete arm64 matrix without omitting any suite.
- The repeated full arm64 `runtime-verify` completes successfully. It repeats
  all freshness, formatting, analysis, aggregate tests, the 436-file Dart-only
  source audit, both bundle audits, and every Developer JIT/Release AOT runtime
  suite through display, hierarchy, actions, configuration, theme,
  semantic-shell, restoration, clipboard, lifecycle faults, traffic, 1,000
  resource iterations, shutdown faults, and PTY deadlines. The hierarchy
  latency ratios are 0.814x and 1.085x, both restoration modes observe real
  fullscreen transitions, and both semantic-shell summaries report lifecycle,
  metadata, prompt navigation, close hint, disablement, and clean ownership.
- Final diff and privacy review finds only the gated application scenario,
  runtime driver contract, README/feature reconciliation, deterministic hash
  pins, and this memo/roadmap state. Success output contains booleans and counts
  only; cwd, command, prompt, startup-file content, and environment values are
  absent. `git diff --check` passes, generated build products are untracked by
  Git, and the authorized adjacent `dart_appkit` worktree is clean. All five
  ordered children and every parent completion condition are satisfied.
- The first explicit eight-file staging attempt could not create
  `.git/index.lock` inside the workspace sandbox and staged nothing. Retry the
  identical task-scoped path list with repository-metadata permission before
  the required independent commit.

## Findings and decisions

- The required post-`a2b9344` reread found both repositories clean and confirms
  conservative close-hint composition as the first unchecked roadmap child.
  The final dual-runtime semantic-shell scenario and settings remain ordered
  later work.
- `TerminalSession.processSnapshot()` is already the single shared capture
  boundary used by both focused Close and aggregate Quit. Composing the current
  bounded semantic state there avoids separate policy paths in AppKit, pane
  close, and quit coordination; no `dart_appkit` change is needed.
- The selected representation adds one content-free combined disposition,
  `owningShellCommand`: the OS reports the owning shell process group in the
  foreground and the bounded semantic state is `commandOutput`. Distinct
  foreground and unavailable OS evidence take precedence, while non-live,
  prompt, input, unknown, and reset retain their prior classifications.
- The composition is monotonic relative to the existing policy. A forged `C`
  can only add an unnecessary confirmation. A forged `D`, prompt marker, or
  reset cannot turn a distinct foreground or unavailable snapshot into an idle
  one because those OS classifications are evaluated first. No terminal text,
  command, process name, option, or exit status enters the snapshot.
- The first focused format pass changed only `test/run_tests.dart`; analysis
  then stopped on one import-boundary error because importing the screen-set
  library does not make `TerminalSemanticShellState` visible to another
  library. `terminal_session.dart` now imports the semantic model explicitly;
  no runtime test had started and no policy change was needed.
- After the explicit import, focused analysis reports no issues. The first test
  entrypoint then stopped in the renderer build hook because the workspace
  sandbox again denied Clang's `~/.cache` module writes; the tests are rerun
  unchanged with the established cache permission.
- With that permission, the focused application-state Close/Quit test passes.
  The following aggregate runner reaches and rejects stale Phase 7 AppKit
  evidence because `terminal_application_state_test.dart` is a pinned unit-test
  source. Its generated hash is refreshed and reviewed before rerunning.
- Phase 7 evidence regeneration changes only the expected hashes for the pane
  model, terminal session, and application-state test. Its semantic totals stay
  fixed at 4 criteria, 13 source references, 10 unit tests, 4 integration tests,
  and 8 UI assertions, and the dedicated freshness check passes.
- The refreshed aggregate runner passes. Focused coverage now traverses
  unknown, prompt, input, command-output, and RIS-reset semantic states against
  an idle owning group, then proves distinct foreground remains authoritative
  after a forged command-end marker. Pane Close separately converts a thrown
  session snapshot to unavailable confirmation; aggregate Quit captures the
  new disposition in stable visual order and includes only scalar counts in its
  machine line.
- README and PTY-08/CFG-06 evidence now describe the warning-only composition
  and the version-two lifecycle resources without claiming final runtime
  acceptance. Compatibility coverage regeneration changes only the expected
  README/FEATURE_MATRIX pins and passes with the same 9 fix families, 417 split
  runs, 8 owned gaps, and zero known P0 silent-corruption cases.
- The final complete `make test` passes every generated freshness gate, formats
  233 files without changes, reports no analyzer issues, and passes the
  aggregate Dart runner. The source audit passes with 436 tracked files, zero
  product-native sources, and one reviewed test-native source. Both arm64
  Developer JIT and Release AOT bundles rebuild and pass audit with one helper,
  one native asset, and one declared capability each.
- Final review confirms the generated Phase 7 evidence changes only the pane,
  session, and application-state-test hashes, while compatibility coverage
  changes only README/FEATURE_MATRIX pins. The task contains no debug artifact
  or unrelated file, `git diff --check` passes, and the authorized adjacent
  `dart_appkit` worktree remains clean because no dependency change is needed.
- The required post-`071fa18` reread found both repositories clean and confirms
  prompt navigation is the first unchecked roadmap child; close composition,
  final runtime acceptance, and settings remain ordered later work.
- `TerminalViewport` already synchronizes history append/eviction and owns the
  primary offset. Its combined row helpers expose flags, logical line ID/epoch,
  and soft-wrap continuity across scrollback and the active grid, so navigation
  needs no duplicate mark index or mutable store.
- A target is the first physical row carrying `TerminalRowFlags.prompt` in one
  retained logical line. A following prompt-flag row is the same target only
  when the preceding row soft-wraps into the same logical ID/epoch; consecutive
  hard-broken prompts remain distinct.
- Previous search starts above the visible top while scrolled, and above the
  cursor row at bottom. It skips prompt rows in the live grid that cannot change
  the current offset and continues to the newest movable retained target. Next
  starts below the visible top and may return to offset zero when the next mark
  is in the live grid. Both searches are bounded by retained rows and return a
  boolean movement result; alternate ownership and missing targets return false.
- The shared catalog currently has 16 stable actions. The selected additions
  are `pane.jump-to-previous-prompt` and `pane.jump-to-next-prompt`, titled
  “Jump to Previous Prompt” and “Jump to Next Prompt” in the View section,
  without default native shortcuts. The generated keybinding action reference
  will make both available as configurable action targets.
- The normal hierarchy already maps the active window/tab to focused pane,
  session, selection owner, and render surface. Successful navigation will
  synchronize the focused selection projection and notify that one surface;
  it will not write to the PTY or mutate application hierarchy. Availability
  is derived from whether that focused primary viewport has a movable target.
- The shared action implementation is an AppKit- and PTY-independent
  `TerminalPromptNavigationActionCoordinator`. It resolves the active viewport
  for every availability check and dispatch, publishes only successful moves,
  and lets the normal product cancel stale hyperlink interaction, synchronize
  selection, and invalidate exactly the still-focused matching surface.
- The first combined format/analyze/test invocation formatted all ten requested
  files (two changed) but analysis did not start because Dart attempted to
  update `~/.dart-tool/dart-flutter-telemetry-session.json`, which the workspace
  sandbox forbids. This is a validation-environment restriction rather than a
  source failure; the identical checks are rerun with `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true`.
- The first telemetry-suppressed analysis reached source checking and found
  five test-fixture API spelling errors (`maxRows`, a private logical-identity
  setter, and convenience alternate-screen names that do not exist). Existing
  viewport tests establish the public equivalents: `maxLines`/`pageRows`,
  `setLogicalLineId`, and DEC mode 47 setters. The fixture now uses those
  public APIs; no product implementation changed in response.
- Focused analysis then passed, while the coordinator test exposed an invalid
  fixture expectation: one history prompt alone has no later prompt target, so
  Next is correctly unavailable rather than an implicit scroll-to-bottom. A
  distinct prompt in the live grid was added to model the intended history-to-
  current navigation case; the viewport contract remains unchanged.
- The corrected focused analyzer and all three viewport/coordinator/registry
  test entrypoints pass. The first reference-regeneration attempt then reached
  the renderer build hook but Clang could not create Metal module-cache files
  below `~/.cache` in the workspace sandbox. As with the earlier semantic test,
  this is an external build-cache permission constraint; regeneration is
  retried unchanged with the established build permission.
- With the established cache permission, reference generation, its freshness
  check, and the standalone reference test pass. The generated inventory now
  reports 105 physical keys, 4 pane actions, 18 application actions, 1 standard
  binding, and 9 reserved shortcuts; both prompt actions appear in the View
  menu with no native shortcut. README and IN-09 evidence are reconciled from
  their stale 16/15 action counts to the current 18-action catalog.
- The first complete `make test` passes parser-table, parser-trace, and the
  regenerated 18-action reference gate, then rejects stale Phase 7 AppKit
  acceptance evidence. The current action/test additions changed a hashed
  source inventory; the evidence generator and resulting semantic diff must be
  reviewed before the complete gate is rerun.
- Regenerating the Phase 7 evidence changes only the two expected SHA-256 pins
  for `terminal_application.dart`; all 4 criteria, 13 source references, 10
  unit tests, 4 integration tests, and 8 UI assertions remain unchanged and
  the dedicated freshness check passes.
- The second complete gate passes that refreshed evidence and all 9 byte-level
  compatibility regressions (390 input bytes, 417 split runs), then rejects
  stale top-level compatibility-regression coverage. Its generator inputs are
  inspected next so only justified derived pins or reconciliations are updated.
- Coverage regeneration changes only the expected README and FEATURE_MATRIX
  SHA-256 source pins. Its semantic boundary remains 9 fix families/cases, 417
  split runs, 8 owned gaps, and zero known P0 silent-corruption cases; generation
  and the dedicated freshness check both pass.
- The final complete `make test` passes every generated freshness gate, formats
  233 files without changes, reports a clean analyzer, and passes the aggregate
  Dart test runner including the new viewport/coordinator coverage. The
  Dart-only source audit reports 436 tracked files, zero product-native sources,
  and one reviewed test-native source; both arm64 Developer JIT and Release AOT
  bundles rebuild and pass the bundle audit with one helper, one native asset,
  and one declared capability each.
- Final review finds only prompt navigation model/actions/product wiring,
  focused tests, generated references/pins, and current task documentation.
  No debug artifact or unrelated change is present, `git diff --check` passes,
  and the adjacent authorized `dart_appkit` worktree remains clean.
- The post-`19eb963` worktree check found only this task memo modified in
  `dart_terminal`; the adjacent `dart_appkit` repository remains clean. The
  roadmap still identifies four-shell lifecycle and metadata emission as the
  first unfinished subtask.
- The installed-shell inventory for this host contains `/bin/zsh` and
  `/bin/bash`; `fish` and `nu` are absent. zsh and bash therefore receive real
  PTY evidence, while fish and nushell retain static contract checks and run
  syntax/execution probes conditionally when their executables are available.
- The current generation-one resources are marker-only: five files total 4,545
  bytes, and the runtime, contract, and focused tests all pin integration
  version 1. Adding lifecycle and metadata behavior is a material protocol
  revision, so the bundle's integration version becomes 2 while the JSON
  contract schema and resource-header contract version remain 1.
- One broad search of the official Nushell documentation returned more output
  than the tool could retain and was unusable as evidence. Narrow direct reads
  were used instead. The official hook reference confirms that `pre_prompt`,
  `pre_execution`, and `env_change` are interactive-REPL hooks, that `PWD`
  change hooks receive before/after values, and that hook lists can be extended
  without replacing existing entries. The official command references confirm
  byte-counting via `str length`, literal all-occurrence replacement via
  `str replace --all`, and cwd-basename derivation via `path basename`.
- The shared source policy is content-minimal: emit OSC 133 `A` and `B` before
  input, `C` before execution, and `D` on the next prompt (plus post-execution
  where a shell exposes it); emit OSC 7 only as `file://localhost` and OSC 2
  only from the cwd basename. Never inspect or serialize command lines, prompt
  text, history, or arbitrary environment values.
- Metadata emission fails closed before writing: cwd is capped at 1,000 shell
  characters (Nushell counts UTF-8 bytes), title at 256 shell characters
  (Nushell bytes), and any C0/C1 control rejects the refresh. Four-byte UTF-8
  worst cases still fit the parser's 4,096/1,024-byte cwd/title ceilings once
  the fixed URI prefix is included; the parser remains the authoritative byte
  boundary.
  Percent, space, number-sign, and question-mark bytes are percent-escaped in
  the local file URI. The terminal's existing 4,096-byte cwd and 1,024-byte
  title validators remain the second boundary and additionally reject bidi
  controls and malformed/remote URIs.
- Zsh uses additive `add-zsh-hook` handlers for `precmd`, `preexec`, and `chpwd`;
  bash preserves `PS0` and scalar/array `PROMPT_COMMAND`; fish uses named event
  handlers for prompt, pre-execution, post-execution, and `PWD`; nushell appends
  blocks to all three documented hook lists. Every resource retains its
  existing once-only load guard and startup-cleanup behavior.
- The first generation attempt passed `/bin/zsh -n` and `/bin/bash -n`, then
  stopped before rewriting the contract because the Dart build hook could not
  write Clang's Metal module cache under `~/.cache` in the workspace sandbox.
  This is the same environment restriction seen in the preceding subtask; the
  unchanged generation command must run with the established cache permission.
- The first two-file `dart format` invocation formatted both edited tests, but
  Dart then failed while updating its telemetry-session timestamp outside the
  workspace; because the shell command stopped there, its subsequent syntax and
  diff checks did not run. The checks must be repeated with analytics disabled.
- The first focused gate passed resource validation and launch-plan tests, then
  the real-zsh hostile-cwd case timed out because completion was coupled to an
  exact echoed command string. ZLE/PTY redraw is not a stable completion
  oracle. The test now snapshots and waits for an additional preserved user
  `precmd` hook event, while retaining the substantive assertions that cwd and
  title metadata remain unchanged and the hostile title fragment never reaches
  terminal output.
- With the stable completion oracle, the real-zsh hostile-cwd safety assertion
  fails, proving at least one expected rejection invariant is not yet met. The
  next reproduction adds escaped, test-only cwd/title/output context to
  distinguish a source filter failure from an over-broad transcript assertion;
  the task remains incomplete until this is fixed at the emitting boundary.
- Escaped diagnostics show the source filter did reject the hostile cwd:
  terminal cwd and title stayed on `safe project`. The failing clause was the
  broader substring check: zsh's own default prompt safely rendered the
  filename controls as visible `^[`/`^G` text, which legitimately retained the
  word `injected`. The assertion now rejects the actual raw OSC 2 byte sequence;
  visible shell-escaped filename text is outside the integration boundary and
  is not control-sequence injection.
- The next focused rerun passed the corrected hostile-cwd case but found no
  `A`/`B`/`D` bytes in the Apple Bash 3.2 manual-opt-in transcript. Its initial
  prompt ran the user `PROMPT_COMMAND`, while the test exited in that same input
  line before a subsequent prompt could observe the integration's appended
  handler. The probe now sends the report and `exit` as separate input lines so
  one post-command prompt exercises both preserved and appended handlers. Apple
  Bash remains outside automatic integration and is not used to claim PS0/C
  support.
- The corrected focused gate passes resource/contract validation, immutable
  launch planning, fake semantic stream replay, real shell projection, semantic
  parser, and metadata tests. Focused analysis of the runtime contract and both
  resource/projection tests reports no issues. The generated version-two bundle
  contains the same five resources across four shells and totals 10,575 bytes,
  within both per-file and 128 KiB aggregate limits.
- The real zsh probe observes initial metadata/input state, command output,
  local cwd and cwd-basename title refresh, all three row classes, and additive
  user `precmd` execution. Its control-bearing cwd leaves the last safe
  metadata unchanged and cannot form a raw OSC 2 injection. Disabled zsh emits
  no integration OSC families. Apple Bash 3.2 manual opt-in preserves its user
  prompt command and emits `D`/metadata/`A`/`B` at the following prompt.
- This host still has no fish or nushell executable, so their documented
  conditional syntax probes are skipped rather than installing optional
  shells. Both resources are covered by exact hashes, shared source-policy
  assertions, launch-plan projection, and official hook/command syntax review.
- Transactional regeneration and the subsequent freshness check both pass for
  integration version 2 with four shells, five files, and 10,575 total bytes.
  The complete `make test` gate passes all compatibility/resource generators,
  formatting across 231 files, analysis, and aggregate Dart tests.
- `make runtime-source-check` passes with 434 tracked files, zero product native
  sources, and one reviewed test-native source. Both arm64 Developer JIT and
  Release AOT bundles build and pass the bundle audit with one helper, one
  native asset set, and one declared capability each. These audits created no
  additional source changes, and `dart_appkit` remains clean.
- Final diff review contains only the version-two runtime constant, four
  integration resources, regenerated exact contract, focused tests, and this
  memo/roadmap progress update. `git diff --check` passes; no command content,
  prompt content, user startup files, optional shell installation, or unrelated
  product behavior entered the change.
- The first explicit-path staging attempt could not create `.git/index.lock`
  under the workspace sandbox, and staged no files. The identical ten-path list
  is retried with repository-metadata write permission before the required
  independent commit.
- The required post-commit reread confirms `d901085` left both repositories
  clean. The completed shell-integration parent is followed immediately by this
  semantic item; settings/effective-config inspection remains later and must not
  be implemented early.
- The existing terminal model already defines bounded per-row `prompt`,
  `command`, and `output` flags. Scrollback copies them, reflow aggregates them,
  snapshots expose them, and selection/search preserve their aggregate meaning.
  Parser input does not currently set those semantic flags; tests only exercise
  them by assigning flags directly.
- `TerminalScreen.lineFeed()` records hard breaks, wrapping retains semantic
  flags, and the viewport already exposes combined history/screen rows plus
  bounded top/bottom/relative scrolling. Prompt navigation can therefore reuse
  the owning viewport rather than introducing a second history store.
- OSC 0/1/2 title and OSC 7 cwd parsing are already bounded by
  `TerminalSessionMetadata` (1,024 and 4,096 UTF-8 bytes respectively) and reject
  control/bidirectional-control input. Product projection accepts only local
  `file:` authorities (empty host or `localhost`) for inherited paths and native
  represented URLs.
- Existing pane-close policy uses an on-demand, content-free OS process snapshot:
  non-live/idle owning shells close immediately, while a distinct foreground
  process group or unavailable evidence requires confirmation. Semantic terminal
  bytes are untrusted and must never suppress either latter case.
- The exact pinned Ghostty zsh integration at commit
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4` uses OSC 133 `A` for prompt start,
  `B` for input start, `C` for command/output start, `D` for command completion,
  and `P` for secondary/initial prompts. It refreshes OSC 7 cwd at startup,
  directory changes, and prompts. This is behavioral reference only; the bundled
  implementation will be independently authored and substantially smaller.
- The browser cache could not open exact raw files at the pinned revision. A
  direct read of the pinned zsh resource succeeded. One combined attempt to read
  the fish, nushell, and semantic-parser sources produced truncated output and
  was not usable as evidence; those files will be inspected separately with
  scoped pattern output.
- Separate scoped reads confirmed that the pinned fish integration emits
  `A`, `C`, and `D` around `fish_prompt`, `fish_preexec`, and `fish_postexec`,
  while the pinned nushell resource at that revision contains no semantic
  prompt hooks. The independent four-shell contract therefore cannot merely
  copy reference coverage; nushell needs its own tested hook composition.
- The pinned semantic parser accepts `A`, `B`, `C`, `D`, `I`, `L`, `N`, and
  `P` and can decode command-line options. This product deliberately selects
  only the five lifecycle actions needed by the roadmap and never decodes or
  stores `cmdline`/`cmdline_url`, avoiding a command-history side channel.
- A later scoped source fetch initially failed DNS resolution inside the
  workspace sandbox and succeeded unchanged with approved read-only network
  access. The pinned zsh source confirms cwd refresh at startup, `chpwd`, and
  every prompt; title-on-command includes command text and is therefore
  explicitly rejected for this product's privacy boundary.
- The close-hint design will add warnings only: when the OS reports the owning
  shell as the foreground process group, semantic `C` through `D` may classify
  a same-process shell builtin/function as active. Distinct foreground groups
  and unavailable snapshots retain unconditional confirmation, and an unknown
  hint retains today's behavior.
- The first focused semantic test attempt did not reach Dart tests because the
  renderer build hook tried to create Clang Metal module-cache files under
  `~/.cache`, which the workspace sandbox forbids. Formatting completed (eight
  files checked, three changed). The identical test must be rerun with the
  already-established build-cache write permission; this is an environment
  restriction, not a semantic test failure.
- The permitted rerun reached the new tests and failed the malformed-marker
  count: DEL (`0x7f`) is discarded by the VT parser while inside OSC, so it
  never reaches the semantic payload validator. The case now uses retained
  non-ASCII byte `0x80`, which directly verifies that the selected option
  grammar is printable ASCII only; DEL filtering remains covered by the core
  parser tests.
- After correcting that fixture, the focused semantic, compatibility-surface,
  screen-set, reflow, scrollback, and snapshot tests pass, and focused analysis
  reports no issues. The generated implementation manifest changed only by one
  declared `osc:133` execute selector (82 to 83 total selectors).
- Compatibility inventory freshness then failed as expected because its
  separately reviewed OSC metadata table did not yet describe newly declared
  command 133. This is a real generated-authority update, not a product test
  regression; the metadata and generated inventory/summary must be reconciled
  before completion.
- The first inventory regeneration wrote the updated JSON but summary
  validation rejected the new pinned `ghostty` source family. The inventory
  decoder has an explicit family enum independent of the generator; it must be
  extended transactionally before rerunning generation. No summary file was
  changed by the failed second step.
- The decoder now recognizes the exact pinned Ghostty semantic-parser source as
  a fifth bounded source family, including verified byte count and SHA-256.
  Regeneration and both manifest/inventory freshness gates pass with 261
  records, 15 OSC records, 20 partial records, and 105 reconciled implemented
  selectors/modes.
- Row marking initially bracketed every ASCII scalar to catch autowrap. It was
  tightened to one mark per parser-provided ASCII run plus a destination-row
  mark only when the cursor row actually changes; non-ASCII scalar dispatch
  similarly marks again only after a row transition. This retains wrap
  correctness without repeated row-flag writes in steady output.
- Focused semantic, compatibility-surface, compatibility-inventory, screen-set,
  reflow, scrollback, and snapshot tests pass after regeneration. The tests
  cover lifecycle rows, ignored options, excluded actions, the 256-byte cap,
  malformed bytes, chunk/BEL/ST independence, autowrap, bounded scrollback,
  resize/reflow, alternate-screen ownership, and RIS reset.
- The first complete `make test` progressed through parser-table, trace,
  keybinding/action reference, AppKit evidence, and regression replay, then
  correctly rejected stale compatibility-regression coverage because the
  reviewed inventory boundary gained OSC 133. The coverage reconciliation must
  be regenerated and reviewed before rerunning the complete gate.
- Updating the reviewed inventory/manifest totals let coverage proceed to its
  nested application-acceptance check, which then rejected the old
  implementation-manifest hash. The application evidence generator must be
  refreshed first; only after that dependency can the top-level regression
  coverage report be regenerated.
- Refreshing the manifest pin makes application acceptance pass unchanged
  (8 accepted cells, 3 clean, 5 documented-gap cells). Differential corpus
  checking still reports its baseline stale because that report also hashes
  the changed inventory/manifest inputs; its explicit generator must refresh
  those derived source pins before coverage can close.
- Explicit differential-baseline regeneration passes with the same four cases,
  202 input bytes, and 210 split runs; its observations did not change.
  Differential acceptance then rejected its own stale hash of that regenerated
  baseline, so that next derived report must also be refreshed in dependency
  order.
- Regenerated differential acceptance also retains its prior 12 accepted
  results (8 agreements, 4 unavailable pinned comparators, no documented or
  unexpected gaps), and the top-level regression coverage report now generates
  successfully. The first complete suite then passed every freshness/test
  stage, but analysis reported two non-fatal directive-ordering infos introduced
  by the new export/test import; those directives were reordered before the
  final clean rerun.
- The final analyzer rerun reports no issues. `make runtime-source-check`
  passes with 431 tracked files, zero product native sources, and one reviewed
  test-native source. The final complete `make test` rerun passes all
  freshness, format, analysis, and aggregate Dart tests across 231 formatted
  files.
- Because semantic row projection touches the printable hot path, the Release
  AOT parser benchmark was also rerun: 134,264,777 parsed bytes completed at
  107.84 MiB/s against the 100 MiB/s minimum, with the expected integrity hash
  and no cancel/limit/malformed/incomplete events.
- Final diff review found only the task memo/roadmap split, semantic
  parser/model/tests, the OSC 133 compatibility declaration and its generated
  evidence dependency chain. No `dart_appkit` change was required for this
  pure terminal-model subtask, and `git diff --check` passes.
- The first staging attempt was blocked because the workspace sandbox could not
  create `.git/index.lock`; no paths were staged. The exact explicit path list
  is retried with repository-metadata write permission before commit.
