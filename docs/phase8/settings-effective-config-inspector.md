# Settings UI and effective-configuration inspector

- Status: in progress
- Started: 2026-09-11 after commit `dc5603a`
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `settings UI と effective-config inspector`
- Feature-matrix owners: UI-09 and CFG-07
- Depends on: `docs/phase8/typed-config-schema-diagnostics.md`,
  `docs/phase8/product-option-families.md`,
  `docs/phase8/safe-configuration-reload.md`, and
  `docs/phase8/declarative-keybind-action-reference.md`

## Purpose

Make the typed configuration authority observable from both automation and the
normal native product. Users must be able to inspect every effective option,
its provenance and application policy, see actionable diagnostics, discover
canonical schema/CLI syntax, and migrate the existing compatibility spelling
without duplicating configuration knowledge across help, documentation, and UI.

## Background

- The product schema now owns 36 scalar/repeatable options, typed defaults,
  decoding, precedence, provenance, and live/new-session policy.
- Safe reload retains last-known-good effective state and the diagnostics from
  the most recent rejected candidate, but there is no normal UI that exposes
  either snapshot.
- Runtime usage lists only the original working-directory option, while the
  generated keybinding/action reference deliberately covers only its narrower
  vocabulary. There is no full configuration reference or `--show-config`
  equivalent.
- `theme = default` is retained as a source-compatibility alias for `system`,
  but is silently normalized and provides no migration warning.
- `dart_appkit` already provides bounded generic `Window`, display-only
  `TextView`, Dart-only key routing, native menu ownership, and exact cleanup.
  A searchable keyboard-owned inspector can reuse these public boundaries; no
  new native control or adjacent-package change is presently required.

## Scope

- Give every schema option bounded presentation metadata and a canonical value
  formatter shared by effective output, help/reference generation, and UI.
- Emit a stable warning and repair hint when the accepted `theme = default`
  compatibility spelling is used, without changing its resolved `system`
  behavior or rejecting startup/reload.
- Add a deterministic, bounded effective-config formatter that includes every
  scalar and retained repeatable occurrence with canonical values, provenance,
  and live/new-session policy; diagnostics remain a separate bounded section.
- Add ordinary `--help` and `--show-config` process modes that do not start
  AppKit panes, plus a generated full configuration reference and freshness
  gate sourced from the same schema/action authorities.
- Add a shared Settings action and one transient native Settings window. It is
  a searchable, keyboard-navigable read-only inspector over the accepted
  snapshot and last reload diagnostics, can request the existing serialized
  reload action, restores terminal focus on close, and owns/reclaims exactly
  one Window/TextView pair.
- Add gated real-product acceptance for menu/palette/action ownership,
  effective values and provenance, rejected/accepted reload refresh, terminal
  isolation, and cleanup in Developer JIT and Release AOT.
- Reconcile README/feature evidence and require the full Phase 8 regression,
  source, bundle, and runtime matrix before completion.

## Out of scope

- Editing or rewriting user configuration files, filesystem watching, SIGHUP,
  per-pane overrides, importing remote configuration, secrets, terminal
  content/history, a general-purpose form-widget toolkit, or arbitrary AppKit
  controls.
- Terminal protocol inspector/diagnostics bundles, accessibility audit beyond
  the existing display-only native text surface, localization, Secure Input,
  updater/distribution work, or any Phase 9+ capability.
- Removing the `default` theme enum compatibility case for programmatic
  callers; only config text receives a migration warning.

## Dependencies and boundaries

- `TerminalConfigSchema` remains the only option-name, default, decoder,
  canonical formatter, policy, repeatability, and migration authority.
- Effective output is local and explicitly requested. It may expose the config
  source path needed for debugging, but never reads or includes terminal text,
  command history, the ambient environment, or file contents.
- Formatter/reference/UI output has explicit character, row, result, and
  diagnostic bounds. Values and paths are escaped so one option cannot forge
  another line or UI row.
- Settings UI reads the reload controller's accepted snapshot and last-attempt
  diagnostics. A rejected reload never becomes effective; an accepted reload
  refreshes the same presenter without replacing pane/PTY/render owners.
- AppKit resources remain on the root isolate/main thread and are disposed
  before application shutdown. Menu, palette, keybinding, and Settings all
  dispatch the same stable action identities exactly once.

## Completion conditions

1. Every schema option round-trips to one canonical bounded presentation and
   appears exactly once in generated help/reference and the Settings catalog;
   repeatable keybindings preserve ordered occurrences.
2. `theme = default` continues to resolve as `system` while producing one
   stable warning with a `theme = system` migration hint in file and reload
   paths; canonical effective output never prints the deprecated spelling.
3. `--help` and `--show-config` exit successfully without creating application,
   PTY, renderer, worker, or native-window owners. Effective output is stable,
   complete, escaped, and identifies value source and application policy.
4. The normal Settings action opens one native searchable inspector, exposes
   accepted effective state plus current diagnostics, runs existing Reload
   Configuration without a second reload path, refreshes after acceptance or
   rejection, restores terminal focus, and releases every resource.
5. Invalid configuration still launches and is visible with file/line/hint;
   rejected reload preserves every pane/session. Shell-integration `none`
   remains an ordinary working terminal configuration.
6. Focused tests, generators/freshness, formatting, analysis, complete tests,
   source/bundle audits, and M1 Developer JIT/Release AOT product acceptance
   pass. All Phase 8 exit conditions are rechecked before stopping the session.

## Ordered subtasks

1. Add schema-owned canonical presentation, bounded effective snapshot and
   diagnostic formatting, and the `theme = default` migration warning. Cover
   every type, escaping, provenance, repetition, bounds, reload acceptance,
   and deterministic ordering without adding UI or process modes.
2. Add ordinary `--help`/`--show-config` early-exit modes and generate the full
   configuration/CLI reference from the same schema. Add freshness and
   completeness tests and update user documentation; no native Settings window
   yet.
3. Add the shared Settings action and searchable native inspector presenter,
   wire it to accepted/rejected reload state and exact cleanup, and cover
   pure/fake-AppKit/product action ownership. Do not add a second reload
   controller or write configuration files.
4. Add one gated real-product Settings/effective-config scenario, pass both M1
   runtime modes and the complete regression/source/bundle/runtime matrix,
   reconcile UI-09/CFG-07 and Phase 8 exit evidence, and close the parent.

Each child is independently verified, documented, marked complete, and
committed. After every commit, reread `ROADMAP.md` and this memo before starting
the next child.

## Current subtask: schema presentation and migration diagnostics

- Status: complete
- Purpose: make the existing typed snapshot self-describing and canonically
  printable before any CLI or native UI consumes it.
- Background: values are currently typed and provenance-aware but option
  definitions expose no stable syntax/formatter, and compatibility theme text
  is normalized without a warning.
- Scope: presentation metadata and formatter callbacks on option definitions;
  one bounded effective-config model/formatter; one schema-declared deprecated
  raw-value warning for `theme = default`; pure loader/snapshot/reload tests.
- Out of scope: process exit modes, generated files, new actions, AppKit
  resources, settings interaction, and runtime integration.
- Dependencies: the immutable schema, collector precedence and diagnostic cap,
  repeated keybinding occurrence model, reload last-known-good transaction, and
  existing public value types.
- Completion conditions: every current option has a validated canonical
  representation; scalar/repeatable output and provenance are deterministic
  and escaped within hard bounds; migration warnings remain non-fatal and do
  not change semantic diff/reload behavior; focused and complete repository
  checks pass.
- Validation: exhaustive focused config/formatter/reload tests, format,
  analysis, complete `make test`, source audit, diff review, roadmap update,
  and one task-scoped commit.

## Findings and decisions

- The post-`dc5603a` reread found both repositories clean. The semantic-shell
  parent is complete and this is the sole remaining Phase 8 roadmap item.
- Existing `TextView` is intentionally display-only and does not scroll, but a
  bounded presenter can render a searchable selected option plus a small result
  window and route keys in Dart, following the command-palette ownership model.
  This satisfies the inspection/settings boundary without expanding
  `dart_appkit`; the user-authorized adjacent repository remains available only
  if later product evidence proves a missing generic capability.
- A writable form was rejected for this phase: it would require file merge,
  comment preservation, atomic-write, authorization, and conflict semantics not
  present in the roadmap. The requested UI is an inspector and reload surface,
  while configuration editing remains in the documented file/CLI workflow.
- The existing `theme = default` spelling is the only real compatibility alias
  in the current schema. Treating it as the migration case avoids inventing a
  deprecated option name or expanding the compatibility surface.
- Presentation metadata is now an enforced schema contract: every option owns
  a bounded `valueSyntax` and typed formatter, while schema construction checks
  syntax/description bounds and every scalar default formatter. Formatters use
  explicit stable spellings rather than enum `toString`; notably programmatic
  `defaultTheme` and decoded `default` both present as canonical `system`.
- Successful decodes can now carry one structured warning. The collector emits
  that warning only when publishing the already validated file or command-line
  value, so the CLI prevalidation pass does not duplicate diagnostics. File
  migration warnings point at the value column, remain warnings, and therefore
  follow the existing reload acceptance transaction without changing semantic
  diff behavior.
- The effective view is a separate immutable, schema-ordered projection. It
  contains one row per scalar, ordered rows for retained repeatable values, and
  one explicit zero-occurrence placeholder when a repeatable option is empty.
  It never reads the environment or configuration contents beyond the accepted
  typed snapshot.
- The line-oriented formatter JSON-escapes every canonical value, source path,
  syntax, diagnostic message, and hint. It reports policy, source kind,
  line/column, and repeat occurrence, and fails with a typed exception rather
  than returning partial output when entry, canonical-character, diagnostic,
  or output bounds are exceeded.
- Path values previously had no CLI length cap even though shell paths and
  configuration lines were bounded. Path decoding now admits only control-free
  UTF-8 up to 4096 bytes, ensuring every accepted path has a bounded canonical
  presentation; the same rule consistently applies to root and include paths.
- Unrelated configuration acceptance fixtures were changed from deprecated
  `theme = default` to canonical `theme = system`. Dedicated tests retain the
  alias coverage so exact diagnostic counts in broader product/runtime
  scenarios continue to describe their intended failures.

## Validation log

- `dart format` completed for every changed Dart source and test file.
- The first `dart analyze` attempt was blocked after formatting by the managed
  sandbox denying deletion of `~/.dart-tool/dart-flutter-telemetry.log`; no
  analyzer result was produced. Re-running with `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true` outside that filesystem restriction completed
  with only two directive-ordering infos.
- The new focused effective-config test passed, covering all 36 schema options,
  default round trips, alias normalization, ordered repeatables, absent-repeat
  projection, JSON escaping, deterministic output, typed bounds, precise file
  and CLI warnings, and accepted semantic-no-op reload.
- Existing config, reload, and product-configuration focused tests passed after
  adding presentation metadata to their deliberately custom schemas.
- The two analyzer directive-ordering infos identified the new export/import as
  being placed before the existing `terminal_core` group; they were corrected
  before the clean analysis rerun.
- The first complete `make test` reached the Phase 7 AppKit freshness gate and
  correctly rejected its stale source hash after the product configuration
  fixture changed to canonical `theme = system`. Regenerating
  `test/corpus/appkit/phase7_acceptance_v1.json` changed only the two expected
  `terminal_application.dart` hashes; the gate then passed. The aggregate test
  runner change itself did not alter the generated inventory.
- A final focused pass added direct coverage for diagnostic-count rejection and
  JSON escaping of newline-bearing path/message/hint fixtures. The first
  no-output format check reported that this new test still needed formatting;
  writing the formatter result and repeating the check resolved it.
- Final `make test` passed every generated freshness gate, formatted 235 files
  with zero changes, reported no analyzer issues, and completed the aggregate
  `dart_terminal tests passed` run.
- Final `make runtime-source-check` passed with 436 tracked files, zero product
  native sources, and the one reviewed test-only native source.
- `git diff --check` passed. Final review found only task-scoped schema,
  formatter, tests, canonicalized acceptance fixtures, refreshed evidence,
  roadmap, and memo changes. The adjacent `dart_appkit` worktree remained
  clean; no generic native capability was needed for this child.

## Current subtask: CLI inspection and generated reference

- Status: complete
- Started: 2026-09-11 after commit `631cff2`
- Purpose: expose the schema and effective snapshot through ordinary bounded
  process modes, and make the committed full configuration reference reject
  drift from the same authority.
- Background: `bin/main.dart` currently validates the runtime host, parses a
  full `TerminalOptions`, prints startup diagnostics, and immediately creates
  `TerminalApplication`. Its hand-written `terminalUsage` lists only four
  options. The repository already has a proven generate/check/test/Makefile
  pattern for the narrower keybinding/action reference.
- Scope: schema-generated usage text; exclusive `--help` and `--show-config`
  early-mode resolution; bounded stdout/stderr projections; an exact generated
  Markdown configuration/CLI reference; freshness/completeness tests; Makefile
  gates; README links and migration/output documentation.
- Out of scope: new product actions, Settings/AppKit UI resources, writing
  config, changing reload behavior, or runtime GUI acceptance. The discovered
  generic clean-exit defect in `dart_appkit` is a separately committed runtime
  dependency correction, not terminal UI scope.
- Dependencies: the schema presentation contract, effective-config formatter,
  loader precedence/diagnostics, existing runtime termination API, and the
  keybinding/action reference for detailed key/action vocabulary.
- Completion conditions: help and reference contain every schema option exactly
  once; `--show-config` accepts normal config selectors/overrides and emits the
  exact bounded effective document; both modes terminate before options,
  application, PTY, renderer, worker, and native-window ownership; invalid mode
  combinations remain usage errors; generated content is freshness-gated and
  documented.
- Validation: pure mode/output tests, actual entrypoint contract checks where
  possible without launching AppKit, generator generate/check/freshness,
  format, analysis, full `make test`, source audit, diff review, roadmap update,
  and one task-scoped commit.

### Initial findings and decisions

- Early modes must be selected before `TerminalOptions.parse`, because normal
  parsing creates a reload controller and resolves integration-only runtime
  arguments. `--show-config` will call the config loader directly; `--help`
  will not touch a config file, so a broken user config cannot prevent help.
- Both early flags are single-use and mutually exclusive. `--help` is a
  standalone discovery mode. `--show-config` may be combined only with
  configuration selectors and schema overrides; unrelated runtime options are
  rejected instead of being silently ignored.
- The embedded host validation/diagnostic bootstrap may run before dispatch,
  but early branches will request termination without constructing
  `TerminalOptions` or `TerminalApplication`. This preserves the runtime host
  lifecycle while keeping all AppKit/PTY/renderer/worker owners absent.
- Generated usage and Markdown will consume `TerminalConfigSchema` directly.
  The full reference will link to the independently generated
  `keybindings-and-actions.md` authority rather than duplicating its physical
  key and action tables.
- The first generator run found an unescaped `$XDG_CONFIG_HOME` in a Dart
  string and failed at compile time before creating the reference. Escaping the
  documentation’s literal dollar sign fixes the source without changing the
  intended generated text.
- The first entrypoint-order test incorrectly rejected the type annotation in
  the statement immediately after the early branch, even though the
  `TerminalOptions.parse` call was correctly outside and after that branch.
  Tightening the assertion to forbid the parse call itself preserves the
  ownership contract without depending on substring boundaries around the
  following declaration.

### Runtime dependency correction

- The first real Developer JIT `--help` run generated the complete help text
  and took the early branch, but the embedded runner then failed with status 2
  while requesting application termination. Inspection of adjacent
  `dart_appkit` found that `dmr_runtime_request_termination` delegated every
  result to the failure-only `RecordExitCode`, which intentionally rejects
  zero. The public header likewise described only non-zero termination even
  though clean process modes need an ordinary successful exit.
- The user explicitly authorized correcting `dart_appkit` in this session.
  The generic runtime API now accepts the full process-status range 0 through
  255 on the main thread. Zero schedules idempotent application termination
  without inventing a failure or replacing a previously recorded non-zero
  result; non-zero behavior and the ABI signature are unchanged. Native tests
  cover invalid, clean, worker-thread, and prior-failure preservation cases,
  and the Dart facade documents the same contract. No ABI revision is needed
  because this is a compatible behavioral expansion of the existing call.
- The dependency correction was committed in adjacent `dart_appkit` as
  `2b36186` (`Allow clean runtime termination requests`); its worktree was
  clean after the commit.
- `make runtime-lifecycle-test runtime-dart-test` passed after the correction.
  The first aggregate adjacent-repository `make test` attempt later failed once
  in the unrelated `dart_pty_macos` race case `live Dart child cannot steal
  native PTY completion` with `Bad state: No element`. No PTY source was
  changed. Its isolated 11-test suite passed immediately, and a complete
  aggregate rerun passed all native, package, launcher, asset, and smoke tests.
  After strengthening the lifecycle test with worker-thread and preserved
  failure assertions, the focused lifecycle/runtime suites passed again.
- With that runtime correction, the real Developer JIT `--help` process exited
  successfully without pane, PTY, renderer, worker, or window lifecycle output.
  A real `--show-config --no-config --theme=default --font-size=17.5` process
  also exited successfully and emitted the versioned 36-entry document plus
  one migration warning: `theme` was canonicalized to `system` at CLI argument
  3, `font-size` retained `17.5` at argument 4, and the empty repeatable
  `keybind` placeholder was present.

### Validation log

- `dart format` formatted 239 files with zero source changes, but its first
  invocation returned failure only because sandboxing denied a Dart telemetry
  timestamp write under the user home. Re-running with `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true` completed with zero changes.
- The focused configuration-reference test passed. It covers exact one-row and
  one-flag schema completeness for all 36 options, committed reference
  freshness and stale rejection, help without filesystem access, canonical
  effective values and provenance, warning/error recovery, early-mode
  conflicts, entrypoint ownership order, and typed output bounds.
- The generator check passed with 36 options, 2 live policies, 34 new-session
  policies, and 1 repeatable option. `dart analyze` reported no issues.
- The first aggregate `make test` correctly stopped at the Phase 7 AppKit
  freshness gate after replacing the hand-written `terminalUsage`. Regenerating
  its evidence changed only the two expected `terminal_application.dart`
  hashes. The next aggregate run reached the compatibility coverage freshness
  gate; regenerating that report changed only its tracked README hash at that
  point. No acceptance expectation or compatibility classification changed.
- After updating CFG-07 in `FEATURE_MATRIX.md`, the same coverage report was
  regenerated once more so its tracked feature-matrix hash reflects the
  completed CLI surface. The final aggregate gate passed generated-reference,
  Phase 7, compatibility, application, terminfo, and shell-integration
  freshness checks; formatted all 239 files with zero changes; reported no
  analyzer issues; and completed `dart_terminal tests passed`.
- `make runtime-source-check` passed with 439 tracked files, zero product native
  sources, and the one reviewed test-only native source.
- `git diff --check` passed. Final review found only the CLI resolver,
  schema-generated presenters/reference, exact tests, docs/README/matrix,
  Makefile freshness gate, exports/entrypoint integration, and automatically
  refreshed source-hash evidence. Adjacent `dart_appkit` remained clean at
  `2b36186`.

## Current subtask: shared Settings action and native inspector

- Status: complete
- Started: 2026-09-11 after commits `967ce02` and the progress-status
  correction `950e0ed`
- Purpose: expose the accepted typed configuration and its diagnostics through
  a keyboard-searchable native product surface reached by the same shared
  application-action path as menus, command palette, and keybindings.
- Background: the command palette already provides bounded native keyboard
  interaction and first-responder restoration, while reload owns the current
  accepted snapshot and most recent diagnostics. The remaining work must join
  those authorities without copying schema rows or creating a second reload
  controller.
- Scope: one catalogued Settings/effective-config action; native menu and
  command-palette discovery; a Dart-owned bounded inspector presenter with
  option search/selection, canonical value/provenance/policy/detail,
  diagnostics, reload, and close interaction; product coordinator lifecycle;
  fake-AppKit and focused product tests.
- Out of scope: editing or writing configuration files, a general-purpose
  preferences form, Phase 10 terminal/parser diagnostics, changing schema or
  reload semantics, and M1 Developer JIT/Release AOT acceptance (the next
  child).
- Dependencies: `TerminalEffectiveConfigSnapshot`, the schema presentation
  contract, `TerminalConfigReloadController`, shared application action
  catalog/dispatch, native menu availability projection, command-palette
  keyboard model, and generic `dart_appkit` Window/TextView/key-event APIs.
- Completion conditions: the action is generated from the shared catalog and
  reachable by menu/palette/keybind; a single inspector instance searches all
  schema-derived entries, displays canonical source/policy/repetition plus
  bounded diagnostic details, reloads through the existing controller without
  pane/PTY replacement, restores focus and frees native handles on close, and
  cannot create duplicate config or action authority.
- Validation: source/ownership inspection, presenter/model unit tests,
  fake-AppKit product interaction and cleanup tests, generated action-reference
  refresh if required, format/analyze/full `make test`, source audit, diff
  review, roadmap update, and one task-scoped commit.

### Initial findings and decisions

- `TerminalActionCatalog.standard()` is already the single authority for
  native menu order, command-palette search, stable keybinding targets, and the
  generated action reference. Settings will therefore be a new
  `application.open-settings` ID in that catalog, with the conventional native
  Command-comma shortcut; no side-channel menu item or direct key handler will
  be added.
- The ordinary interactive hierarchy already owns exactly one
  `TerminalConfigReloadController` and applies accepted results through
  `TerminalProductConfigurationAuthority`. The inspector will retain only a
  reference to that controller and request reload through the existing shared
  `application.reload-configuration` dispatcher registration.
- `dart_appkit` already supplies all generic primitives required here:
  configurable native `Window`, read-only `TextView`, Dart-only key routing,
  deferred close events, and first-responder control. The inspector can follow
  the command-palette lifecycle without another adjacent-repository change.
- `TextView` is intentionally non-scrolling. The state will search the complete
  bounded effective-entry collection but render only a small selected result
  window, one full selected-entry detail, and a bounded diagnostic preview with
  explicit remaining counts. Long fields are visibly clipped and total output
  remains capped rather than creating an unbounded native string.
- Opening Settings from the command palette reveals a focus edge: the palette
  currently restores terminal focus after every executed action, which would
  steal first responder from the newly opened inspector. Focus restoration
  policy will be catalog metadata, defaulting to the existing behavior and
  disabled only for actions that intentionally establish a new native focus
  target.
- Fake-AppKit coverage can reuse the repository’s existing in-memory
  `NativeBindings` harness by adding its missing `TextView` calls. This permits
  exact assertions for one settings window/view, rerendering, first responder,
  close restoration, release order, and zero leaked handles without production
  test hooks.
- The first focused model-test invocation was blocked in the sandbox because
  the existing renderer build hook could not write Clang’s user module cache;
  rerunning outside that filesystem restriction reached the test. That run
  exposed an incorrect fixture assumption: invalid CLI values are deliberate
  usage errors and throw before producing a recoverable snapshot. The rejected
  reload case now uses an invalid in-memory config file, matching the product’s
  diagnostic-recovery contract without weakening CLI validation.
- The first typed-config regression run rejected the new conventional native
  `Command-,` shortcut because the collision checker previously assumed an
  AppKit key equivalent was already a physical-key config name. Existing
  shortcuts were letters, so the latent punctuation boundary was untested.
  Native punctuation equivalents are now mapped to their stable physical names
  before collision checks and generated keybinding documentation; the AppKit
  menu continues to receive the literal punctuation character.

### Validation log

- The focused inspector model test passed with all 36 schema-derived effective
  entries, deprecated startup diagnostics, canonical value/source/policy and
  empty-repeatable projection, rejected last-known-good reload, accepted
  generation update, keyboard ownership, Unicode-safe clipping, query limits,
  and typed total-render bounds.
- The fake-AppKit hierarchy test passed the complete native interaction:
  command palette search and dispatch opened Settings without restoring focus
  to the terminal, reopening reused the same window/view owners, native text
  input searched `font-size`, Command-R dispatched the shared reload action and
  refreshed generation/value, and Escape restored the terminal responder while
  reducing the live handle count from four to the original two.
- Focused action-registry, command-palette, config/keybinding, generated
  keybinding-reference, and AppKit-policy tests passed. The generated authority
  now reports 19 application actions and 10 reserved native shortcuts.
- `dart format` checked all 241 Dart files with zero changes and `dart analyze`
  reported no issues.
- The first complete `make test` reached the Phase 7 AppKit freshness gate and
  correctly rejected hashes affected by the product Settings integration and
  fake-native acceptance. Regenerating
  `test/corpus/appkit/phase7_acceptance_v1.json` changed only the expected
  application and native-hierarchy source evidence. Regenerating the aggregate
  compatibility report changed only the README and feature-matrix source
  hashes.
- The final `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed every
  freshness gate, format and analysis, and the aggregate `dart_terminal tests
  passed` run. `make runtime-source-check` also passed with 444 tracked files,
  zero product native sources, and the one reviewed test-only native source.
- `git diff --check` passed. Final review found only the inspector, shared
  action/focus/key-equivalent integration, focused tests, generated evidence,
  README/feature/roadmap progress, and this task record. The adjacent
  `dart_appkit` worktree remained clean.
