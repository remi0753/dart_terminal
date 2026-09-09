# Typed configuration schema and diagnostics

- Status: complete
- Started: 2026-09-10
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `typed config schema と diagnostics`
- Feature-matrix owners: CFG-01 and CFG-02
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md` and
  `docs/phase7/application-state-model.md`

## Purpose

Create the bounded, typed configuration substrate used by the rest of Phase 8.
The zero-config product must preserve its current behavior, while a user config
can be discovered or selected explicitly, included files can be composed, and
invalid input produces actionable source diagnostics without preventing launch.

## Background

- `TerminalOptions.parse` currently parses two ordinary command-line options
  together with gated integration-only switches.
- There is no user configuration location, file grammar, include mechanism,
  typed schema, source provenance, or diagnostic model.
- Phase 5 already owns immutable runtime key bindings and Phase 7 owns logical
  application state. This task must provide configuration input without moving
  either ownership boundary.
- Later Phase 8 roadmap items own theme, font, window, input, scrollback,
  keybind, reload, appearance, shell-integration, and settings behavior. Their
  values must not be partially implemented here.

## Scope

- Define immutable typed option definitions and an immutable schema registry.
- Establish a bounded `key = value` grammar with comments and quoted strings.
- Resolve the macOS user configuration location, an explicit `--config=PATH`,
  and `--no-config` without making a missing default file an error.
- Support bounded relative/absolute `include` directives with cycle and depth
  detection.
- Retain source path, line, column, stable diagnostic code, severity, message,
  and optional correction hint for parse/schema/read failures.
- Resolve values in `default < included file < including file < CLI` order and
  retain the winning source for effective-config inspection later in Phase 8.
- Connect the existing `working-directory` product option to the schema while
  keeping automatic-close and all integration-only controls CLI-only.
- Print configuration diagnostics before application startup but continue with
  the last valid value or schema default. Invalid application arguments remain
  usage errors with exit status 64.
- Add focused deterministic tests for parsing, precedence, diagnostics, bounds,
  include behavior, and the zero-config path.

## Out of scope

- Theme, palette, font, padding, window, input, cursor, scrollback, shell, and
  keybind option definitions.
- File watching, reload transactions, per-option reload policy, settings UI,
  generated help/reference documents, and deprecation migrations.
- Reading terminal content, command history, environment values other than the
  bounded configuration-location inputs, or any remote configuration source.
- Changing the behavior or availability of integration-test-only switches.

## Dependencies and boundaries

- Configuration parsing and resolution stay in Dart product code; AppKit and
  PTY packages receive only already-resolved typed values.
- The schema is the sole authority for user-configurable names and decoders.
- Configuration input is bounded by file count, include depth, file bytes,
  line bytes, diagnostic count, and assignment count.
- Diagnostics never contain file content or an expanded environment dump.
- Tests use an injected file reader and deterministic environment, so a
  developer's real configuration can never affect the test suite.

## Completion conditions

1. Zero-config startup resolves the existing defaults and produces no
   diagnostics when the default file is absent.
2. File values and CLI overrides are decoded through the same typed schema,
   with immutable winner provenance and deterministic precedence.
3. Unknown keys, malformed lines, invalid values, unreadable explicit files,
   include cycles/depth overflow, and configured bounds yield stable file/line/
   column diagnostics plus a correction hint where one is available.
4. Configuration errors do not throw from ordinary product resolution and do
   not prevent startup; invalid CLI syntax and gated internal options remain
   fatal argument errors.
5. Formatting, analysis, focused tests, complete `make test`, source audit, and
   a manifest-driven Developer JIT build pass.

## Verification plan

1. Run focused configuration and option-parser tests.
2. Run `dart format --output=none --set-exit-if-changed` and `dart analyze` with
   analytics disabled.
3. Run `make runtime-source-check` and the complete `make test` gate.
4. Build the arm64 Developer JIT bundle to verify the production entry point.
5. Review `git diff --check`, the staged diff, and configuration-related source
   searches before committing only this task.

## Findings and decisions

- The worktree was clean on `main` at `40f7bb2`; the branch was one commit ahead
  of `origin/main` before this task began.
- The existing ordinary product values are `working-directory` and the
  smoke-only `auto-close-after`. Only `working-directory` is an appropriate
  initial schema member. Treating test automation controls as user config would
  bypass their environment gates and is explicitly rejected.
- The loader will use dependency injection for file reads instead of embedding
  test-only filesystem branches in the parser.
- A small line grammar is selected over adding a serialization dependency. It
  preserves exact source positions and keeps parsing, bounds, and correction
  behavior product-owned and deterministic.
- Added `terminal_config.dart` with an immutable heterogeneous schema, typed
  lookup, winner provenance, local/injected filesystem boundaries, bounded
  include traversal, UTF-8/scalar parsing, and stable diagnostics. The product
  schema initially contains only `working-directory`; later Phase 8 options can
  extend the same registry without changing loader precedence.
- The default location is `$XDG_CONFIG_HOME/dart-terminal/config` when XDG is
  explicitly selected, otherwise
  `$HOME/Library/Application Support/Dart Terminal/config`. A missing default
  file is silent; a missing explicitly selected file is an error diagnostic but
  does not abort startup. `--no-config` provides deterministic opt-out.
- `TerminalOptions.parse` now consumes the configuration-only arguments first,
  then applies its existing smoke/fault arguments and mutual-exclusion gates.
  Configuration diagnostics and the effective snapshot are retained on the
  options object, and the entry point prints diagnostics before starting the
  application. CLI syntax remains a fatal `FormatException`.
- Initial analysis found an unused import, one missing test import, and import
  ordering. All were corrected; `dart analyze` then reported no issues.
- The first focused test invocation reached the renderer build hook but could
  not write the Clang module cache under `~/.cache` in the restricted workspace.
  The identical command in the approved environment ran successfully. The
  focused suite covers zero-config resolution, both standard locations,
  includes, quoted values/comments, default/file/CLI precedence, provenance,
  schema rejection, invalid syntax/value/unknown-key recovery, suggested
  corrections, duplicate warning, include cycle, byte and diagnostic bounds,
  explicit missing-file recovery, opt-out, and `TerminalOptions` integration.
- `make runtime-source-check` passes with `tracked=402`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- The first complete `make test` correctly rejected the Phase 7 acceptance
  inventory because it pins `terminal_application.dart`. Regenerating it with
  `make phase7-appkit-acceptance` changed only the two expected hashes.
- README now documents the location, grammar, include/precedence rules,
  diagnostics, and current schema surface. FEATURE_MATRIX records CFG-01 and
  CFG-02 as implemented. Their expected hashes were refreshed with
  `make terminal-compatibility-regression-coverage`.
- The final `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes every
  generated-evidence freshness check, formats 215 files with zero changes,
  reports no analyzer issues, and completes the aggregate Dart test runner.
- `make RUNTIME_ARCH=arm64 developer-jit-build` validates the stock Engine,
  compiles the application and worker, stages both native assets, signs the
  bundle, and produces `build/runtime/arm64/developer-jit/DartTerminal.app`.
- `git diff --check` passes. The final diff contains only this configuration
  substrate, its tests/docs, and deterministic evidence hashes; no unrelated
  source or generated output is present.

## Result

The product now has one bounded typed configuration authority with deterministic
location, include, precedence, diagnostics, and recovery behavior. Zero-config
startup is unchanged, invalid file content cannot prevent launch, and later
Phase 8 option families can extend the schema without reopening the loader or
the application-argument boundary.
