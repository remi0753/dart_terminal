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
