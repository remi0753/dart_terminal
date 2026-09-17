# Context Dock boundary shifted Control-arrow defaults

- Status: complete
- Started: 2026-09-17
- Environment: macOS / Apple M1 / arm64
- Starting worktree: clean main at feaa838

## Purpose and background

The user reports macOS consumes Control+Left/Right before application delivery.
Change only the default Context Dock boundary shortcuts to
Control+Shift+Left/Right, preserving the existing shared actions and resize
behavior. Do not capture system-wide keyboard events or change OS preferences.

## Scope, exclusions, and dependencies

- Shift is required for both default chords, not an additional alias. Old
  Control-arrow chords no longer invoke boundary movement by default.
- Left still widens the right Dock and Right narrows it by one logical cell.
  Terminal/Navigator ownership, query/selection, fixed font/scale, viewport/grid/
  PTY updates, clamps, hidden-Dock availability, and drag opt-out remain intact.
- Preserve explicit user keybind overrides/unbind/passthrough and stable action
  IDs, default binding count, terminal split shortcuts, and native API behavior.
- Update keybinding, terminal router, Navigator, and real runtime acceptance
  tests, current user references/manual checklist, and generated evidence.
- No new native dependency change, global keyboard capture, Control-Tab fix,
  SSH functionality, or pre-existing low-priority follow-up work is included.
- Dependencies: shared typed keybind engine and action dispatch, Navigator live
  keybind resolver, generated reference/evidence gates, JIT/AOT bundles.
- Risk: updating only terminal input leaves Navigator or runtime tests using the
  old chord; a non-exact match could keep consuming plain Control-arrow.

## Completion criteria and verification plan

- Both default chords require Control and Shift; plain Control-arrow has no
  default boundary action. Existing Command/Shift-Command split chords remain.
- Terminal down/release keys invoke once with no Kitty key bytes; Navigator
  preserves query/selection/focus and obeys unbinding/alternate configured chord.
- Rebuilt JIT/AOT native-content integration exercises the new chords with its
  existing fixed-font/scale, viewport/grid, stty winsize, focus and cleanup gates.
- Regenerated reference/evidence, format, static analysis, focused tests and
  full `make test` pass; review scoped diff and commit this single bounded task.

## Investigation log

- Rechecked AGENTS, README, ROADMAP and FEATURE_MATRIX goals/current Phase 7
  boundaries, prior boundary-resize record, repository structure and tests/build
  entry points. Only remaining unchecked tasks are deferred low-priority work;
  registered this requested shortcut correction above them before implementation.
- Shared standardDefinitions contains exactly two Control-arrow Dock bindings.
  Both terminal and Navigator resolve that same live engine, so no native policy
  change is necessary. Runtime acceptance injects modifier bits explicitly and
  must add Shift in both terminal-owned and Navigator-owned fixtures.
- Initial bulk source/doc and broad regex outputs were truncated; selected
  relevant sections were reread with bounded queries. A guessed generator name
  did not exist; use the existing Makefile generation targets rather than a
  guessed path. No implementation or verification ran from these probes.
- The earlier resize memo retains historical Control-arrow validation results;
  add a superseding-default note rather than rewriting past verification.
- Added Shift to exactly the two standard boundary chords. No action ID,
  binding-count limit, native API, geometry, focus or renderer policy changed.
  Updated terminal down/release and both runtime input fixtures; Navigator tests
  also verify plain Control-arrow does not resize, and unbinding the shifted
  default plus an alternate Control-K binding still uses the live resolver.
- Current README, feature matrix and manual checklist use the shifted chord;
  generated keybind/evidence references will be refreshed through Make targets.
  Five in-scope Dart files formatted with zero changes; static analysis passed.
- Focused keybinding, Context Dock and native hierarchy test commands all
  completed with exit 0. Regenerated configuration/action, Phase 7 acceptance,
  compatibility regression coverage, gap inventory and daily-use references;
  configuration reference has no diff because binding counts did not change.
  Generated keybind table now lists shift+control+left/right as defaults.
- Rebuilding both runtime bundles, then running native-content integration and
  full `make test` sequentially to avoid unnecessary PTY/build contention.
- First rebuilt JIT native-content run reached the exact resize success marker:
  shifted keys in terminal/Navigator, fixed font/scale, viewport/grid, actual PTY
  winsize, focus and zero key writes all passed. The later existing process argv
  reveal assertion timed out (`revealing process argv did not obtain a fresh
  native document`, terminal_application.dart wait at ~9350); the shell/session
  then shut down cleanly. AOT and full gate had not run because `&&` stopped.
  No process-observation code was changed. Inspect the existing bounded wait/
  fixture and rerun the same integration unchanged; do not weaken its assertion
  or widen this shortcut task into process implementation.
- An unchanged rebuilt rerun again passed the resize marker and timed out at
  argv reveal. A direct JIT smoke run without rebuild passed argv reveal but
  later found a null process snapshot after its 1100 ms elapsed check (~9365).
  Existing eligibility requires an active application and focused native window;
  opening/dismissing the palette can clear retained process content. The pipeline
  fixture also only sleeps 4 seconds. Neither cause is established yet; do not
  claim a product regression or increase/skip assertions on this evidence alone.
- Independently attempted full `make test`; it stopped at dpty-native-test with
  multiple pipeline/UTF-8/burst/exit timeout expectations, before terminal tests.
  AOT is still pending. Inspect process/build contention safely and rerun the
  unmodified gate; process listings require escalation in this sandbox. A read
  probe accidentally used the adjacent repository cwd and was corrected without
  edits. Native dependency retains exactly its three pre-existing user edits.
- Process inventory found no surviving test app, make/compiler, pipeline or
  runtime test jobs; only unrelated existing Dart processes remained. Nothing
  was terminated. The unmodified full `make test` rerun exited 0: native/package,
  freshness/privacy/localization/compatibility/distribution gates, formatting
  348 files with zero changes, no static-analysis issues, and complete terminal
  runner (including shifted down/release routing) all passed.
- Prior foreground-inspector memo (~657 onward) documents direct/headless launch
  needing explicit active/focus events to establish observation authority. Current
  harness injects those initially (~8582) but process eligibility also checks
  native focus after palette dismissal. No source beyond shortcut fixture
  modifier bits/messages has changed; native-content failure is still recorded,
  not hidden by the successful full gate. Running AOT native-content independently
  because the combined target stops after the JIT failure.
- Rebuilt Release AOT native-content integration passed unchanged, including
  the shifted terminal/Navigator keys, fixed font/scale/grid/PTY gates, process
  inspector and four clean sessions (9958 ms). JIT full integration is rerunning
  with its same already-rebuilt bundle; no assertion, timeout, process fixture
  lifetime, product focus or observation policy has been modified.
- The unchanged direct JIT rerun then passed the entire native-content suite
  (10398 ms), including process argv reveal/elapsed, four sessions and all
  cleanup gates. Both runtimes and full `make test` now have successful final
  verification results. No diagnostic or assertion-weakening source changes
  were needed; the only production behavior change is two shifted default chords.

## Final review and follow-up

- Requested shortcut behavior, references and tests are complete. Shift is now
  required in both default directions; explicit existing user overrides remain
  authoritative. Rebuild/restart via `make RUNTIME_ARCH=arm64 developer-jit-run`.
- Native-content JIT had three failures before the unchanged successful run.
  Track the independent existing process/palette observation-fixture instability
  in [its follow-up memo](native-content-process-fixture-stability.md) and ROADMAP,
  without implementing process/focus changes in this keyboard-default task.
  The transient native PTY full-gate failure and clean rerun are retained above;
  the already-planned competing-reaper fixture investigation remains unchanged.
- Diff review and `git diff --check` passed: no temporary debug code, native
  generated binaries, private process data or unrelated edits are included.
  No dependency edits are made in this task; its pre-existing user changes
  remain untouched. Commit only this task's source/tests/docs/evidence records.
