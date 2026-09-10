# Product theme, palette, font, window, input, and scrollback options

- Status: in progress
- Started: 2026-09-10
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8
  `theme/palette/font/window/input/scrollback options`
- Feature-matrix owner: CFG-03
- Depends on: `docs/phase8/typed-config-schema-diagnostics.md`

## Purpose

Expose the first complete set of user-facing presentation and terminal-session
preferences through the typed configuration authority, and project one
immutable resolved profile into every newly created pane without changing
zero-config behavior.

## Background

- The configuration loader now owns deterministic location, include,
  precedence, provenance, diagnostics, and recovery, but its product schema
  contains only `working-directory`.
- Terminal defaults currently live at their consumers: xterm palette values in
  `TerminalPalette`, 14-point system monospace in `TerminalLiveMetalSurface`,
  a 920 by 580 AppKit frame in `TerminalApplication`, Option-as-Escape in
  `TerminalKeyEncoder`, and 10,000 lines/64 MiB in `TerminalScrollback`.
- The ordinary product creates every pane through one hierarchy resource
  factory. This is the correct new-session projection boundary; test/fault
  scenarios must continue to receive the same defaults unless their resolved
  profile explicitly differs.
- Reload policy, light/dark appearance switching, declarative keybinds, shell
  selection/integration, and settings UI have later Phase 8 owners and are not
  implemented by this task.

## Scope

- Add bounded typed schema entries and codecs for:
  - theme selector and default foreground/background/cursor plus ANSI 0–15;
  - font family, size, and synthetic-style policy;
  - initial window width/height and horizontal/vertical terminal padding;
  - macOS Option-key behavior (`escape` or `text`);
  - scrollback line and byte caps;
  - initial cursor shape and blink preference.
- Resolve the heterogeneous snapshot into one immutable
  `TerminalProductConfiguration` with coherent cross-field validation and
  current zero-config defaults.
- Give `TerminalSession` explicit initial palette, scrollback, and cursor
  preferences, and give the live Metal surface explicit font preferences.
- Apply configured window geometry and terminal padding at the native hierarchy
  boundary without changing split math, cell minima, or content ownership.
- Apply input behavior through `TerminalKeyEncoder` while preserving Command
  arbitration, IME ownership, terminal mode encoding, and bounded writes.
- Ensure every new tab/split/window receives the same resolved new-session
  profile and owns independent palette/scrollback/render resources.
- Add pure-Dart option/profile tests, focused consumer tests, fake-AppKit
  projection tests, and gated real-product Developer JIT/Release AOT evidence.

## Out of scope

- Theme catalog discovery, light/dark pairs, and live system-appearance updates.
- Declarative keybind overrides or generated action/configuration reference.
- Watching or reloading configuration and mutating existing sessions.
- Shell executable, arguments, environment integration, prompt marks, or close
  hints.
- Arbitrary 256-color replacement, background opacity/blur, ligature feature
  controls, per-window/per-pane overrides, and settings UI.

## Dependencies and boundaries

- The schema remains the only decoder and bounds authority. Consumer
  constructors accept already validated typed values and do no file I/O.
- `TerminalProductConfiguration` is immutable and contains no source paths;
  provenance remains in `TerminalConfigSnapshot` for the later inspector.
- Palette and scrollback objects are created per session. Font resources remain
  owned and disposed by each live surface. Native views remain owned by the
  hierarchy adapter.
- Padding is presentation geometry only: PTY rows/columns are derived from the
  padded content extent, and pointer/caret coordinates use the same local
  terminal origin. The existing VoiceOver text/selection/cursor contract is
  preserved; padding-aware native accessibility geometry is tracked at the
  complete Phase 10 accessibility pass because the current renderer packet has
  no content-origin fields.
- All option values have explicit finite/range/UTF-8 bounds no wider than the
  receiving component's existing hard caps.

## Ordered subtasks

1. Add all 33 option definitions, decoders, the immutable resolved profile, and
   exhaustive pure-Dart validation/default/provenance tests. No consumer or
   runtime behavior changes in this commit.
2. Project the profile into session palette/scrollback/cursor state, surface
   font resources, key encoding, window geometry, and padded pane layout. Add
   focused unit and fake-AppKit tests; preserve all default snapshots.
3. Add a gated real-product scenario that loads a deterministic configuration,
   verifies visible palette/font/geometry plus PTY input and bounded scrollback,
   runs in Developer JIT and Release AOT, refreshes user docs/evidence, and
   closes the parent item only after the full regression suite passes.

Each subtask is documented, marked complete, verified, and committed before the
next begins. After each commit, reread `ROADMAP.md` and this memo.

## Completion conditions

1. Every listed option is decoded through the typed schema with stable bounds,
   actionable invalid-value diagnostics, deterministic default/file/CLI
   precedence, and an immutable effective value.
2. Zero-config session, screen, renderer, input, and window behavior is
   byte/pixel/geometry compatible with the current defaults.
3. A configured new pane owns the selected initial palette, cursor, scrollback,
   font, Option-key behavior, window size, and padding; new windows/tabs/splits
   inherit the resolved profile without sharing mutable resources.
4. Invalid or mutually inconsistent values recover independently and cannot
   prevent startup or weaken a downstream hard limit.
5. Focused tests, fake-AppKit integration, formatting, analysis, complete
   tests, source/bundle audits, and M1 Developer JIT/Release AOT configured
   product acceptance pass.

## Verification plan

- Pure-Dart schema/profile tests after subtask 1.
- Session, palette, scrollback, key encoder, live-surface, and native-hierarchy
  focused tests after subtask 2.
- Manifest-driven configured product scenario in both runtime modes after
  subtask 3, followed by `make RUNTIME_ARCH=arm64 runtime-verify`.
- `make test`, source audit, formatting, analysis, diff review, and a separate
  commit after every subtask.

## Findings and decisions

- The worktree was clean on `main` at `43cffef`; the branch was two commits
  ahead of `origin/main` before this parent task began.
- The parent crosses independent schema, terminal-core, renderer, input, and
  AppKit ownership layers, so it is split before implementation as required by
  the repository work rules.
- The first focused formatter command accidentally included this Markdown file.
  Dart formatted neither Markdown nor additional source and exited with parse
  diagnostics. Subsequent formatting commands are restricted to Dart files.
- The first profile test exposed that the initial line grammar treated the
  leading `#` of an unquoted `#RRGGBB` value as a comment. The lexer now retains
  exactly six-digit hexadecimal color tokens and continues to treat every other
  unquoted `#` as a comment; a regression test covers colors followed by a
  comment.
- The product schema now has 33 unique documented entries: working directory,
  base theme, three logical colors, ANSI 0–15, three font controls, four window
  geometry controls, Option-key behavior, two scrollback caps, and two cursor
  controls. All numbers are finite and no wider than the existing renderer,
  screen, or scrollback hard limits.
- `TerminalProductConfiguration` resolves one snapshot into immutable palette,
  font, window, input, history, and cursor values. Its zero-config defaults are
  byte-for-byte equal to the current scattered product defaults; no consumer
  reads the profile in this subtask.
- The renderer provider's versioned accessibility snapshot encodes cell width
  and height but no content-origin offset. Visual/pointer/IME padding can be
  projected entirely in this repository, while exact VoiceOver hit/range
  geometry for a nonzero inset needs a provider ABI addition. That correction
  is deliberately tracked in the Phase 10 complete accessibility pass instead
  of changing the sibling `dart_appkit` repository from this task.
- Consumer projection uses the ordinary hierarchy's single pane-resource
  factory: the immutable profile is captured once, while each invocation
  creates independent palette, scrollback, screen, font catalog, atlas, and
  input encoder ownership. Runtime fault/restoration acceptance paths retain
  their existing defaults.
- `TerminalSession` now accepts already validated palette, scrollback, and
  initial cursor values. Both primary and alternate screens retain the cursor
  reset defaults across resize/reflow, so RIS returns to the configured shape
  and blink policy rather than hard-coded block/blinking state.
- The product profile materializes a complete 256-color palette per session:
  configured ANSI slots 0–15 replace the base entries while slots 16–255 retain
  the audited xterm cube/grayscale. Scrollback and palette instances are never
  shared between new panes.
- `TerminalLiveMetalSurface` owns configured family, point size, synthetic
  style policy, and horizontal/vertical padding. The grid and XTWINOPS logical
  viewport use the inset content extent; the compositor clips in content
  coordinates, translates every Metal layer once, and clears the whole pane
  with the configured background. Caret and pointer routing use the identical
  logical inset.
- An AppKit window may be interactively resized below twice a configured
  padding value. In that transient state each inset contracts symmetrically to
  leave one positive logical point, avoiding a fatal resize; it returns to the
  configured value as soon as the extent permits. Split minima include both
  insets and preserve the existing base cell minima.
- Option-key `text` policy removes Option only at the terminal byte-encoding
  boundary. AppKit-produced/composed text is retained, Shift/Control still use
  the legacy xterm modifier contract, and Command arbitration remains ahead of
  terminal encoding.
- The first formatter pass changed the requested Dart files successfully but
  exited after failing to update the sandbox-external Dart analytics session
  timestamp. Re-running with `CI=true DART_SUPPRESS_ANALYTICS=true` avoided the
  telemetry write; this was an environment-side exit rather than a source
  parse or formatting failure.
- The first analyzer pass found that `TerminalSession` needed the direct
  `terminal_screen.dart` import for the new palette/scrollback/cursor types.
  Adding that import resolved all four undefined-type diagnostics.
- The first complete `make test` correctly rejected the Phase 7 AppKit
  acceptance inventory as stale after application and fake-AppKit test source
  changes. `make phase7-appkit-acceptance` refreshed only the reviewed source
  hashes; the subsequent freshness check and complete suite pass.
- Focused profile tests pass after the color-token correction. They cover all
  33 defaults, uniqueness/documentation, immutable ANSI storage, every valid
  option family, file-to-CLI precedence, capacity suffixes, and 15 independent
  invalid-value diagnostics with default recovery.
- `make runtime-source-check` passes with `tracked=405`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all freshness gates,
  formats 217 files with zero changes, reports no analyzer issues, and completes
  the aggregate Dart suite.
- ANSI customization is intentionally limited to slots 0–15 plus logical
  foreground/background/cursor. The remaining xterm-256 cube and grayscale
  retain their audited generated defaults.
- The initial theme selector is bounded and names `default`; catalog lookup and
  appearance-dependent pairs remain assigned to the later light/dark task.
- Window padding must be projected through one explicit pane-local geometry
  value rather than by changing canonical terminal cells or adding padding to
  native package defaults.

## Subtask 2 verification

- `terminal_product_configuration_test.dart`: consumer factories preserve the
  configured colors/caps, retain xterm slots 16–255, map all consumer enums,
  and return independent mutable palette/scrollback objects.
- `terminal_session_configuration_test.dart`: two sessions do not share
  resources; primary/alternate configured cursor defaults and RIS/reflow
  behavior pass.
- `terminal_key_encoder_test.dart`: Option `text` preserves composed `å`,
  removes Alt from special-key parameters, and does not bypass Command.
- `terminal_screen_metal_compositor_test.dart`: glyph, selection, and cursor
  instances translate by the exact inset while the encoded viewport remains
  the complete pane.
- `terminal_live_metal_surface_font_test.dart`: configured Menlo 18pt with
  synthetic-style rejection is accepted and retained.
- `terminal_native_hierarchy_test.dart`: fake AppKit projects a configured
  1110×710 window and the exact 18×11 content insets.
- All six focused test entrypoints pass with build hooks enabled.
- Final `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all generated
  freshness/compatibility/application/terminfo gates, formats 218 files with
  zero changes, reports no analyzer issues, and ends with
  `dart_terminal tests passed`.
- `make runtime-source-check` passes with `tracked=408`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- `make developer-jit-build` produces the signed arm64 app, and
  `make developer-jit-audit` passes with one helper, one asset set, and one
  capability declaration. Configured real-product behavior in both runtime
  modes remains the explicitly ordered third subtask.
