# Phase 11 — Release candidate daily-use program matrix

## Status

- Phase: 11
- Task: release candidate daily-use program matrix
- Started: 2026-09-14
- State: in progress
- Current subtask: bounded aggregate implementation and Phase 11 closure

## Purpose

Turn the completed Phase 11 distribution, performance, reliability, safety,
and pinned-parity work into one reproducible release-candidate decision. The
decision must cover representative daily terminal programs and ordinary product
workflows, fail closed on stale evidence or a release-blocking result, and state
exactly which physical, credentialed, and duration-only observations it does
not claim.

## Background and current position

- Commit `5df1831` completed the pinned Ghostty P0/P1 aggregate gate. The
  mandatory post-commit roadmap reread found a clean worktree and identified
  this matrix as the only remaining Phase 11 item.
- The existing Phase 6 real-application matrix has eight controlled programs:
  Emacs, fzf, lazygit, mosh, ncurses, Neovim, OpenSSH, and tmux. Its version-2
  acceptance replays 57,737 captured PTY bytes and 32 snapshots. Seven cells
  are clean agreements; mosh has only the owned DEC mode 1001 hilite-mouse
  difference, which is explicitly unsupported, non-screen-mutating, and not a
  matrix blocker.
- `runtime-verify` already composes 22 bounded product suite families across
  Developer JIT and Release AOT: base lifecycle, display/input/render, native
  hierarchy, system recovery, shared actions, automation, native content,
  Quick Terminal, Secure Input, diagnostics, configuration/theme/localization,
  shell/desktop/OSC 52, restoration/clipboard/lifecycle, traffic/resource, and
  shutdown faults. It uses the ordinary AppKit window, real zsh PTYs, Metal,
  and shipped runtime ownership paths.
- `release-aot-distribution-verify`, `product-performance-regression-gate`,
  `product-sanitizer-fuzz-fault-gate`, and
  `ghostty-p0-p1-gap-closure` already provide the independently completed
  distribution, absolute/relative performance, native sanitizer/fuzz/fault,
  and pinned P0/P1 authorities. Their results must be referenced or recomposed;
  this task must not create weaker duplicate semantics.
- The user explicitly permits Apple notarization and long-duration-only tests
  to be skipped. ROADMAP already tracks real Developer ID/notary service,
  Intel-native no-rebuild execution, and physical 24/72-hour soak as
  post-goal follow-ups. They remain visible exclusions and are not blockers for
  the bounded M1 release-candidate decision.
- The adjacent `dart_appkit` repository is clean and generic. No product policy,
  product identifier, fixture, or code/path containing `terminal` may be added
  there; this final product matrix belongs wholly to `dart_terminal`.

## Scope

- Define a bounded, versioned daily-use matrix covering all eight reviewed
  programs and the product workflow families a person relies on during normal
  terminal use.
- Bind each program/workflow cell to an existing checked-in evidence source,
  exact gate owner, expected fixed marker, classification, and known limitation.
- Produce a checked-in, content-free release-candidate verdict that rejects
  stale source hashes, missing coverage, unexpected classifications, any
  actionable P0/P1 or silent behavior, and nonzero blocker/crash/data-loss/
  security-bug counts.
- Add one named aggregate target which composes the existing ordinary,
  distribution, performance, sanitizer/fuzz/fault, pinned parity, and
  Developer JIT/Release AOT product authorities without running shared build
  outputs concurrently.
- Update README and `FEATURE_MATRIX.md` only with claims observed by the final
  matrix and gate, then decide the Phase 11 parent.

## Out of scope

- Claiming that an automated bounded matrix is 30 days of human daily use, or
  waiting 24/72 hours solely for elapsed time.
- Physically sleeping the user's Mac, attaching/detaching a display, forcing OS
  memory pressure, accessing remote credentials, or changing system security.
- Performing real Developer ID signing, Apple notarization/stapling/Gatekeeper
  acceptance, or Intel-native no-rebuild execution.
- Recapturing third-party programs, accessing live SSH/mosh remote systems, or
  silently treating a missing external program as a passing live run.
- New product features, weakened thresholds, a new Ghostty revision, or any
  change in the generic `dart_appkit` repository.

## Dependencies and ownership boundaries

- `test/corpus/applications/matrix_v1.json` owns the eight-program scenario
  identity and bounds. `compatibility/application_matrix_acceptance.json` owns
  replay acceptance and the documented hilite-mouse difference.
- `compatibility/ghostty_p0_p1_gap_inventory.json` owns the exhaustive P0/P1
  row classifications and approved external follow-ups.
- `benchmark/evidence/product-performance-regression-macos-arm64-m1.json` and
  its generator/checker own performance thresholds and relative parity.
- The distribution policy, Universal build/audit/integration targets, native
  sanitizer/fuzz/fault targets, and 22 runtime suite families remain their own
  behavioral authorities. The daily-use matrix records their identities and
  composes them; it does not reinterpret raw output.
- Checked-in matrix/report data may contain only fixed IDs, counts, booleans,
  classifications, source-relative paths, and SHA-256 values. It must not retain
  terminal text, commands, cwd/path values from a session, PID, timestamp,
  environment, credentials, clipboard, or raw diagnostics.

## Completion conditions

1. Every reviewed application appears exactly once, every cell is accepted,
   and every non-clean result is linked to a non-mutating, non-blocking,
   explicitly owned limitation.
2. The workflow matrix covers startup/shell, input/editor, multiplexer/remote,
   hierarchy/content, configuration/appearance, automation/integration,
   lifecycle/recovery/resource, and distribution/performance/security/parity.
3. A strict generated-evidence checker rejects stale hashes, schema/order/count
   drift, missing/duplicate coverage, unknown gate owners, a false duration or
   notarization claim, nonzero release-blocker classes, actionable P0/P1, silent
   misbehavior, or an unowned program gap.
4. One named aggregate target runs the exact required authorities sequentially
   and emits a fixed content-free success marker only after all pass.
5. README, matrix, and this memo distinguish bounded M1 evidence from the three
   post-goal follow-ups; final diff review and the adjacent generic-library audit
   are clean; no known blocker/crash/data-loss/security bug remains.

## Verification approach

- Add focused parser/generator tests with positive checked-in freshness plus
  hostile schema, hash, program, workflow, gap, blocker, and unsupported-claim
  mutations.
- Register the focused test in the aggregate Dart runner and the checker in the
  ordinary Make gate so stale release-candidate evidence fails normal CI.
- Run the named release-candidate target on the Apple M1/arm64 baseline. Reuse
  deterministic bounded reliability rather than waiting for duration alone;
  retain exact child and final markers in this memo.
- Run formatting, analysis, the exact ordinary repository gate, `git diff
  --check`, tracked-artifact review, and the adjacent `dart_appkit` status plus
  case-insensitive tracked path/content audit before each completion commit.

## Ordered subtasks

1. **Contract, program/evidence inventory, and bounded-duration boundary**
   - Freeze this memo, the eight reviewed programs, workflow families,
     evidence/gate ownership, privacy rules, release-blocker criteria, and the
     three explicit external/duration exclusions.
   - Completion: the documentation-only split is complete and `git diff
     --check` passes; commit it and reread ROADMAP before implementation.
2. **Versioned daily-use matrix and fail-closed checker**
   - Add the strict schema, deterministic generated report, focused hostile
     tests, aggregate test registration, Make generate/check targets, and
     ordinary-gate freshness integration.
   - Completion: focused and exact ordinary gates pass; the report is bounded,
     content-free, and rejects every prohibited release claim; commit it and
     reread ROADMAP.
3. **Bounded release-candidate aggregate and Phase 11 closure**
   - Compose and run the existing distribution, performance, safety, parity,
     and complete two-mode product authorities; update public/matrix wording,
     audit the generic boundary, and close the parent only on complete success.
   - Completion: the named aggregate and exact full gate pass, evidence and
     exclusions are documented, the worktree is clean after the task commit,
     and all Phase 11 roadmap items are complete.

## Investigation log

- 2026-09-14: Repository inventory found no existing release-candidate or
  daily-use matrix artifact/tool. Reusing only the Phase 6 application matrix
  would omit normal product UI, configuration, recovery, distribution,
  performance, and safety ownership; running only `runtime-verify` would omit
  the reviewed third-party program classification and release evidence.
- 2026-09-14: The final gate must therefore combine two axes: eight pinned
  program replay cells and eight bounded product workflow families. Checked-in
  evidence decides coverage/classification; live bounded gates decide current
  product behavior. These axes are related but must not be collapsed into a
  false claim that captured external applications were freshly launched.
- 2026-09-14: Recursive aggregate targets used earlier are safe only when run
  sequentially. The final composition will avoid parallel `make` and reuse
  shared build/runtime outputs deliberately. Exact prerequisite selection is
  deferred to subtask 3 after the versioned matrix fixes the required gate IDs.
- 2026-09-14: The documentation-only contract records all eight programs,
  eight workflow families, evidence owners, release-blocker/privacy rules, and
  explicit notarization/Intel/duration exclusions. The ROADMAP split and link
  resolve correctly, `git diff --check` passes, and no source, generated
  evidence, runtime output, or adjacent repository file changed. The first
  child is complete; the versioned matrix/checker is the next ordered child.
- 2026-09-14: The first matrix generation failed before writing output because
  the new checker treated `resources/DartTerminal.entitlements` as JSON. The
  product entitlement is correctly an XML property list containing one empty
  `<dict/>`; the existing distribution policy decodes it before applying its
  empty-map assertion. This checker only needs to bind the reviewed product
  source, so it will compare the exact canonical empty-plist text instead of
  adding a second partial plist parser or weakening the empty-entitlement rule.
- 2026-09-14: Review of the first generated report found that marker discovery
  concatenated every Dart evidence source, including the new generator which
  declares the expected marker catalog. That would let the catalog prove
  itself even if an owning gate stopped emitting a marker. The generator and
  its test remain hash-bound evidence but are excluded from marker discovery;
  each marker must occur in the pre-existing owner/Make sources. A source that
  constructs `..._PASS` dynamically may declare the exact stem, while the
  report and semantic validator still require the full fixed success marker.
- 2026-09-14: Version 1 now generates a 20-source, content-free matrix with all
  eight ordered program cells, eight workflow families, 31 exact Make gate/
  marker owners, five non-blocking limitations, and seven zero-valued release
  blocker classes. It validates the existing application replay, zero-actionable
  Ghostty inventory, passing M1 Release AOT absolute/relative performance,
  four covered AppKit criteria, five additional Phase 11 fuzz seeds, exact empty
  entitlement plist, target declarations, and marker ownership before writing.
  The focused test passes positive freshness and hostile status/hash/program/
  workflow/gate/limitation/blocker/actionable/unsupported-claim mutations.
- 2026-09-14: The standalone checker passes with 8 programs, 7 clean program
  agreements, 1 documented program gap, 8 workflows, 31 gates, 5 known
  limitations, and zero release blockers. Static analysis reports no issues.
  The exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate also passes
  after ordinary integration: it emits the same matrix marker, checks 338 Dart
  files with zero formatting changes, reports no analysis issue, and ends with
  `dart_terminal tests passed` after all native, compatibility, security,
  update, recovery, and aggregate Dart suites.
- 2026-09-14: Final diff validation is clean. The adjacent `dart_appkit`
  worktree remains clean, with zero case-insensitive `terminal` match in
  tracked paths or tracked Dart/native/script/manifest/Makefile content. No
  adjacent or runtime artifact is part of this change. The versioned matrix,
  fail-closed checker, hostile tests, runner registration, Make generate/check
  targets, and ordinary-gate integration meet the second child's completion
  conditions. The bounded release-candidate aggregate remains deliberately
  unimplemented until the next ordered child.
- 2026-09-14: Before changing the final gate, Make dependency review found
  that the distribution, performance, and `runtime-verify` authorities already
  use ordinary prerequisites, while the sanitizer/fuzz/fault and Ghostty parity
  aggregates invoke overlapping child `make` processes from recipes. Naively
  calling all five aggregate targets would run the ordinary gate four times and
  repeat display/shutdown suites. The final implementation will preserve every
  child target, child marker, and validation boundary, convert only those two
  recursive recipes to equivalent dependency declarations, and invoke the six
  reviewed authorities in one `make -j1` dependency graph. This makes shared
  phony prerequisites execute once and guarantees that build/runtime outputs
  are not produced concurrently. The final marker remains withheld until that
  complete graph succeeds; credentialed notarization, Intel-native execution,
  and physical/duration-only evidence remain explicit non-blocking exclusions.
- 2026-09-14: The first final aggregate run stopped in the ordinary gate at
  `terminal-renderer-native-test`. PTY native/Dart tests passed first, then the
  renderer reported that its precompiled Metal renderer was not created and
  every dependent view/readback/accessibility/input/frame assertion failed;
  `release-candidate-daily-use-gate` correctly withheld all later child and
  final markers. No product source, threshold, or evidence was changed in
  response. Because the same native renderer gate passed immediately before
  this child and this failure shape begins at the shared Metal fixture rather
  than an aggregate dependency, the next diagnostic is one unchanged focused
  rerun to distinguish transient GUI/GPU state from a reproducible regression.
- 2026-09-14: The unchanged focused rerun failed identically inside the file
  sandbox, while the same command passed immediately outside it with
  `Terminal renderer capability contract passed`. The first intentional
  device-failure injection had passed in the sandbox and the subsequent real
  device creation was the first failure, confirming that WindowServer/Metal
  access—not product behavior or the aggregate graph—caused the cascade. The
  final GUI/Metal aggregate must therefore run outside the filesystem sandbox;
  this grants no credential, signing, notary, network, or destructive action.
- 2026-09-14: The sandbox-independent aggregate then passed the ordinary gate
  and all three Release AOT build/audit paths, but its first arm64 smoke stopped
  on a stale duplicated action-menu count. Product output is derived from the
  standard catalog and correctly reported all 33 `TerminalActionId` values
  present at that checkpoint (the later directional-focus work raises the
  current catalog to 37);
  registry/localization/reference unit gates already require exact enum
  coverage, while `runtime_integration_smoke.dart` still hard-coded 30 from the
  earlier Universal-bundle task. The four divider actions were added later and
  the smoke had not been rerun by the display-only parity aggregate. Rather
  than replace one fragile number with another, the runtime oracle will derive
  its exact expected section/action counts from the same public enums while
  still requiring one and only one bundled-product observation. This is an
  acceptance-oracle repair discovered by the current final aggregate, not a
  product behavior or threshold change.
- 2026-09-14: A standalone `dart format` reported zero changed files, then
  returned failure only because unified analytics tried to update the
  sandbox-external Dart telemetry session timestamp. No file was reformatted.
  All normative formatter/analyzer invocations use `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true`; this failed invocation is not treated as code
  validation and will not weaken or replace the exact repository gate.
- 2026-09-14: After deriving the runtime expectation from
  `TerminalActionMenu.values` and `TerminalActionId.values`, the unchanged
  product bundle was rebuilt and the focused arm64 Release AOT smoke passed
  with `RUNTIME_INTEGRATION_PASS ... launch_architecture=arm64
  elapsed_ms=1741`. The affected Ghostty inventory and release-candidate matrix
  hashes were regenerated in dependency order before the rerun.
- 2026-09-14: The next full aggregate passed the ordinary gate, all three
  distribution audits/smokes, absolute/baseline/fairness/relative performance,
  1,296 fuzz executions, nine sanitizer artifacts, four fault boundaries, and
  both shutdown-fault modes. The following Developer JIT display suite then
  timed out only while waiting for the final content-free accessibility
  acceptance to settle. Its preceding PTY, Metal, text input, graphics, search,
  P3 color, glyph, pointer, selection, scroll, hyperlink, title, and cursor
  observations all passed, and teardown remained clean. The final marker was
  withheld. A focused unchanged display rerun will determine whether this was
  transient load/UI interference; the aggregate ordering will be reconsidered
  before any timing bound or acceptance behavior is changed.
- 2026-09-14: The immediate unchanged focused Developer JIT display rerun
  passed all real AppKit/PTY/Metal/accessibility behavior with
  `RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS ... scale_16_16=131072
  elapsed_ms=11915`. This confirms a transient settle failure rather than a
  deterministic regression. The aggregate order and accessibility deadline
  remain unchanged; one complete unchanged aggregate retry is required before
  acceptance.
- 2026-09-14: The unchanged aggregate retry passed both display modes and the
  Ghostty parity aggregate, then `runtime-source-check` rejected the existing
  `tool/macos_ghostty_performance_capture.swift`. That Phase 11 comparator
  capture is a test/tool-only, product-owned ScreenCaptureKit/Apple Event
  harness; it is not linked, bundled, imported by `bin/` or `lib/`, or owned by
  generic `dart_appkit`. The source audit already has an exact reviewed-tool
  boundary for `tool/terminal_differential_macos_activation.swift`, while the
  comparator's ordinary tests bind its SHA-256 and content-free capture
  contract. The correct repair is to add this one exact path to that closed
  reviewed-tool set—not to permit arbitrary native sources or misclassify a
  non-shipping comparator as a runtime native package.
- 2026-09-14: After isolating the current-process POSIX FFI in the generic
  product-owned `dart_process_resource_macos` package, its standalone analysis
  and live CPU/RSS/file-descriptor test passed. The first root focused test and
  source-audit attempts did not reach Dart code because the sandbox denied the
  renderer build hook access to `/Users/remi/.cache/clang/ModuleCache`. As with
  WindowServer/Metal access above, normative root verification must run outside
  that sandbox; the package result itself is valid and no threshold changed.
- 2026-09-14: With both ownership repairs applied, the aggregate passed the
  generic sampler, ordinary, distribution, performance, sanitizer/fuzz/fault,
  parity, source/bundle, smoke, display, hierarchy, bounded reliability, user
  actions, AppleScript, system automation, native content, and Quick Terminal
  authorities. Developer JIT Secure Keyboard Entry then began while the app
  remained `application_active=false` and failed only to acquire its focused
  target; no secure-input ownership was acquired, and PTY/worker/native teardown
  was clean. This is a focus precondition failure compatible with external UI
  interaction, not a permission/release leak. After an unchanged focused rerun,
  the final graph should place the complete focus-sensitive runtime authority
  before the long noninteractive performance/sanitizer work so elapsed load does
  not unnecessarily widen the interference window.
- 2026-09-14: The focused Secure Keyboard Entry rerun failed identically, so
  ordering alone is insufficient. The suite launches the `.app` executable
  directly even though its acceptance requires the app to become frontmost;
  macOS may refuse a background executable's activation request. The existing
  runtime harness already has a bounded Launch Services path (`open -W -n -F`)
  that captures output, preserves environment/arguments, resolves the real
  diagnostic PID, and is used by restoration. Secure Keyboard Entry will use
  that user-equivalent launch path so its active/focused precondition is
  explicit. Product policy remains fail-closed when inactive, the test-only
  synthetic active/inactive transitions remain unchanged, and no Accessibility
  permission or secure-input entitlement is introduced.
- 2026-09-14: Launching the acceptance through `open -W -n -F` still left the
  product inactive. A second discarded approach precompiled the existing
  reviewed `NSRunningApplication.activate` helper before launch and invoked it
  against the runtime diagnostic PID (rather than the `/usr/bin/arch` wrapper
  PID); macOS still rejected background activation. Injecting both active and
  focused protocol events let the scenario advance, but real Secure Event
  Input correctly remained unavailable to the actually inactive application,
  so that synthetic-focus approach was also removed. These failures confirm
  that the product's fail-closed ownership policy is working and must not be
  weakened to accommodate an external foreground-app race.
- 2026-09-14: The retained solution waits up to three seconds for the
  owner-only runtime diagnostic PID record, waits another 500 ms for window
  creation, and asks Launch Services to reopen the already running exact bundle
  identifier. The helper command has five-second exit and two-second stream
  drain bounds, discards output, and fails the acceptance if activation cannot
  be requested. This occurs while the product is live, unlike its normal
  pre-window launch activation, and preserves real AppKit active/focus events
  plus real Carbon Secure Event Input acquisition/release.
- 2026-09-14: The first Developer JIT run with delayed Launch Services
  activation passed active/focus and then transiently missed the initial PTY
  ECHO-on settle. An immediate unchanged rerun completed every automatic,
  manual, menu, palette, keybind, Settings, app-lifecycle, Quick Terminal,
  indication, and cleanup assertion with
  `RUNTIME_SECURE_KEYBOARD_ENTRY_INTEGRATION_PASS mode=developer-jit
  elapsed_ms=3003`. The focused Release AOT run also passed with the same
  marker and `elapsed_ms=2077`. No wait bound, Secure Input policy, or product
  threshold changed. Regression coverage, Ghostty gap inventory, and the
  release-candidate matrix were then regenerated in dependency order; the
  matrix checker again reports 8 programs, 8 workflows, 31 gates, and zero
  release blockers.
- 2026-09-14: The final single-process Make DAG now schedules the existing
  two-mode Secure Keyboard Entry target immediately after the matrix check.
  Its later `runtime-verify` prerequisite is deduplicated by Make, so no gate or
  assertion is skipped or repeated; only the focus-sensitive suite's position
  moves ahead of distribution, performance, sanitizer, fuzz, and fault work.
- 2026-09-14: The next aggregate passed Secure Input, the ordinary gate,
  Universal distribution, performance, fuzz/sanitizers/faults, display parity,
  source/bundle audits, smoke, both hierarchy/fairness modes, bounded
  reliability, and Developer JIT user actions. Release AOT user actions then
  received a real display-recovery event while pane 1 removal was awaiting its
  PTY shutdown. `TerminalApplicationState.removePane` intentionally retains the
  pane in the logical split tree until owned cleanup finishes, so recovery
  reconciled its layout after `TerminalPane` had entered `closing`; the native
  reactor correctly rejected that resize with wrong-state status 3. All five
  PTYs still reached clean teardown, but the asynchronous error prevented the
  application from completing and the 45-second harness bound stopped it.
- 2026-09-14: A closing pane remains in the model only to preserve atomic
  removal and shutdown ownership; it must no longer accept interaction or PTY
  geometry. `TerminalPane.resize` now ignores only `closing` and `closed`
  states, while running/starting/exited layout behavior remains unchanged. A
  focused owner test proves a running resize delegates exactly once and a
  display-recovery-style resize after close admission does not reach the
  session. This fixes the race at the product lifecycle boundary without
  weakening native PTY wrong-state enforcement or swallowing unrelated native
  errors.
- 2026-09-14: The first focused aggregate Dart-runner invocation after the
  lifecycle fix stopped at the release-candidate freshness assertion before
  reaching later tests. This is the intended fail-closed response because the
  new source/test hashes had not yet been regenerated; evidence will be
  regenerated in coverage, Ghostty, release-candidate dependency order before
  rerunning the unchanged owner test.
- 2026-09-14: The first regeneration attempt again hit the documented sandbox
  denial for clang's Metal module cache and was rerun unchanged outside the
  sandbox. After release-candidate freshness was restored, the Dart runner
  reached the older Phase 7 AppKit acceptance hash and correctly reported that
  it was stale as well. The complete regeneration order is therefore Phase 7
  AppKit acceptance, compatibility coverage, Ghostty inventory, then the final
  release-candidate matrix; no checker or source hash will be bypassed.
- 2026-09-14: After the full dependency-ordered regeneration, the aggregate
  Dart runner passed through `dart_terminal tests passed`, including the new
  running-versus-closing resize ownership assertion. The exact failed runtime
  target then passed unchanged with
  `RUNTIME_USER_ACTIONS_INTEGRATION_PASS mode=release-aot windows=2 tabs=3
  panes=4 elapsed_ms=1512`. The focused evidence confirms the recovery/close
  race is repaired before the complete release-candidate graph is retried.
- 2026-09-14: The aggregate retry passed Developer JIT Secure Input but the
  Release AOT run again stopped at the initial ECHO-on setup. The PTY teardown
  snapshot showed ECHO off despite the preceding `stty echo`: the interactive
  zsh had already returned to its ZLE prompt and restored raw/no-echo mode
  before the polling oracle sampled it. This explains the earlier intermittent
  Developer JIT miss and the faster AOT recurrence; it is a deterministic-test
  race rather than a product Secure Input failure.
- 2026-09-14: The acceptance fixture now executes `stty echo`, prints the
  content-free readiness marker, and blocks in portable shell `read` while
  ECHO remains enabled. After the controller proves released ownership, the
  test submits an explicit handshake; the same shell command then applies
  `stty -echo` and prints the existing automatic-acquisition marker. This
  removes timing dependence on prompt/ZLE transitions without changing any
  deadline, product policy, or assertion, and still observes real PTY termios
  plus real Carbon Secure Event Input transitions.
- 2026-09-14: With the explicit PTY handshake, the two modes passed back to
  back in one target: Developer JIT emitted the Secure Keyboard Entry marker at
  `elapsed_ms=3057`, and Release AOT emitted it at `elapsed_ms=2027`. This
  focused result covers the exact sequence that had intermittently failed and
  is the prerequisite for another full aggregate attempt.
- 2026-09-14: That aggregate passed both Secure Input modes, the ordinary,
  distribution, performance, sanitizer/fuzz/fault, and Developer JIT display
  gates. Release AOT display then reached every terminal behavior marker but
  timed out at the final accessibility-publication settle; teardown was clean
  and the release-candidate marker was withheld. This is the same isolated
  settle symptom previously observed once in Developer JIT, now reproduced in
  the other runtime mode only after the long aggregate workload.
- 2026-09-14: Inspection found that the acceptance waits for the selection
  product owner to advance, then relies solely on a shared pane-scheduler timer
  to publish that selection into the native accessibility snapshot. Earlier
  frame retries can validly remain coalesced in that scheduler, making the
  three-second oracle depend on timer ordering rather than the publication it
  is intended to inspect. The acceptance now advances the already requested
  target surface once before polling, matching the existing text-input and
  viewport-geometry acceptance pattern. It retains the normal coalesced request,
  every visible/selection/cursor/native assertion, and all existing time bounds;
  the focused two-mode display gate must prove the repair before another full
  aggregate run.
- 2026-09-14: The focused display authority passed consecutively in both modes
  after dependency-ordered evidence regeneration. Developer JIT emitted
  `RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS` at `elapsed_ms=11839`; Release
  AOT emitted the same complete marker at `elapsed_ms=10434`. Both exercised
  the real PTY, native AppKit window/view, Metal renderer, native accessibility
  client, and clean teardown. The complete release-candidate graph remains the
  required load-order regression proof.
- 2026-09-14: The complete sandbox-independent release-candidate graph then
  passed from a clean matrix check through its fixed final marker. It covered
  all eight reviewed programs (seven clean agreements and the one owned
  `less` hilite-mouse gap), eight workflow families, 31 gates, both runtime
  modes, arm64/x86_64/Universal distribution audits and smokes, M1 performance,
  1,296 fuzz executions, nine sanitizer artifacts, four fault boundaries, and
  the complete two-mode runtime authority. Under aggregate load the repaired
  display stages passed at `elapsed_ms=11287` for Developer JIT and
  `elapsed_ms=10367` for Release AOT. The final result was
  `RELEASE_CANDIDATE_DAILY_USE_PASS programs=8 clean=7
  documented_program_gaps=1 workflows=8 gates=31 runtime_modes=2
  release_blockers=0 bounded=true duration_claim=false
  notarization_claim=false intel_native_claim=false`.
- 2026-09-14: This bounded result does not claim a duration-only soak, Apple
  notarization, or Intel-native hardware execution. Per the approved scope,
  those remain lower-priority/post-goal external follow-ups and are not release
  blockers. The aggregate found no crash, data-loss, security, silent P0/P1,
  or other owned release-blocker class.
- 2026-09-14: The exact ordinary repository gate was rerun independently after
  the aggregate and passed. It analyzed the generic process sampler and root
  package with no issues, reported 338 formatted files with zero changes,
  passed every native/package/evidence/security/update/symbol and aggregate
  Dart suite, and ended with `dart_terminal tests passed`. `git diff --check`
  also passes.
- 2026-09-14: The adjacent `/Users/remi/dart/dart_appkit` audit is clean:
  `git status --short` has no entry, case-insensitive `terminal` matching has
  zero tracked path results, and the same search across tracked Dart,
  C/C++/Objective-C/Swift, shell, YAML/JSON/plist, and Make sources has zero
  content results. No adjacent generic-library file changed. The one new FFI
  boundary is the product-owned, generic `dart_process_resource_macos` package;
  root application Dart imports only its typed API.
- 2026-09-14: The final package-format check covered its three Dart files with
  zero changes. A combined sandboxed freshness/source check then stopped at the
  already documented clang Metal module-cache write denial before Dart code;
  its unchanged sandbox-independent rerun passed with 8 programs, 8 workflows,
  31 gates, zero release blockers, 703 audited files, zero application native
  sources, and exactly one generic process-resource FFI package.
- 2026-09-14: The first explicit staging command was denied only because the
  filesystem sandbox exposes `.git` read-only and could not create
  `index.lock`. The unchanged, explicit 24-path staging command succeeded with
  repository write access. Its staged whitespace check is clean, and the
  staged inventory contains only this final child’s product, generic package,
  tests, generated evidence, documentation, and two ROADMAP state changes.
