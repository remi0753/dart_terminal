# Product theme, palette, font, window, input, and scrollback options

- Status: complete
- Started: 2026-09-10
- Completed: 2026-09-10
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
- The configured runtime acceptance reuses the ordinary interactive hierarchy,
  but has its own environment-gated application flag and integration suite.
  The harness writes one isolated real config file and supplies it through
  `--config`, so the test covers local file I/O, schema decoding, snapshot
  resolution, and product projection rather than constructing a profile in
  test code.
- The scenario will retain the existing `zsh -f` deterministic prompt and
  create a split, tab, and window through the shared action dispatcher. It will
  compare all resulting session palettes/scrollback caps/cursor defaults and
  surface font/padding state, assert their mutable resources are pairwise
  distinct, and verify the configured native frame before clean application
  quit.
- Option-as-text is verified across the PTY boundary: an `od` command reads the
  first two bytes of an Option-modified `å` key event and must report `c3a5`,
  not an Escape-prefixed byte sequence. A bounded output fixture must append
  more history rows than the configured line cap while retained history stays
  at or below that cap.
- The first Developer JIT configured-product launch built and signed the bundle
  successfully, but the host stopped at `host-starting` with status 70 because
  AppKit rejected the requested regular activation policy. No application Dart
  code or scenario assertion ran. This is treated as a launch-environment
  failure pending a process-state check and retry, not as a passing or failing
  configuration result.
- The process-state check found an independently started
  `make RUNTIME_ARCH=arm64 developer-jit-run` with a live DartTerminal root and
  worker using the same bundle. It is not terminated or modified because it is
  outside this task. The acceptance is retried directly against the completed
  bundle to distinguish a transient launch failure from same-bundle
  coexistence.
- The direct retry failed at the same host-starting activation-policy boundary,
  confirming coexistence rather than a transient Dart assertion. The
  configured suite now launches the `.app` through LaunchServices with a new
  instance, using the same environment/output/diagnostics transport already
  exercised by restoration acceptance; this preserves the unrelated running
  application and tests the packaged product entry point.
- A temporary accessory-policy diagnostic copy reached the full Dart product
  and exposed one scenario bug: the first palette search matched zsh's echoed
  command text, which correctly retained the default foreground, before the
  colored command result. The command now builds the marker through a `%s`
  substitution so only the output contains the complete searched marker; no
  product palette logic was changed.
- The next diagnostic proved that Option-as-text delivered UTF-8 `c3a5` through
  the PTY. The terminal's normal input echo placed the visible `å` between the
  prefix and the `od` result, so the original contiguous marker expectation was
  invalid. The stable assertion now searches for the result-only
  `c3a5__END__`, which is absent from the echoed command and still
  distinguishes the Escape-prefixed `1bc3` behavior. Temporary screen-content
  diagnostics were removed after identifying the cause.
- After both scenario corrections, the temporary accessory-policy Developer
  JIT bundle passes the complete configured-product suite with four panes and
  clean owner/worker/native-handle teardown. This diagnostic is useful evidence
  that the Dart scenario and product projection work, but it does not satisfy
  the required regular-policy Developer JIT/Release AOT gate.
- At the first blocked checkpoint, an unrelated Terminal-owned
  `make RUNTIME_ARCH=arm64 developer-jit-run` process and its worker remained
  live. Direct launch, LaunchServices `-n`, and a temporary bundle with a
  distinct identifier and name all returned the same
  `AppKit rejected the configured activation policy` host-starting failure.
  The existing process was not terminated because it was not started by this
  task and might have been user-owned. A later resumption found no DartTerminal
  process but reproduced the failure, disproving process coexistence as the
  cause.
- Running the generic runtime builder with `--run`, including from Terminal.app
  with inherited stdio, also reproduced the same failure. This disproves the
  harness `Process.start`/pipe transport hypothesis and places the failure in
  the native host policy application before Dart starts.
- A minimal Objective-C AppKit probe launched outside an application bundle
  began with `NSApplicationActivationPolicyProhibited (-1)` and could not
  transition to regular or accessory from this process context. The same probe
  packaged as a signed `APPL` bundle and launched through LaunchServices began
  with `NSApplicationActivationPolicyRegular (0)`. Calling
  `setActivationPolicy:NSApplicationActivationPolicyRegular` nevertheless
  returned false while the effective policy remained regular on macOS 26.6.2
  (25G83).
- Adjacent `../dart_appkit/native/runner/RunnerConfiguration.mm` treated that
  false return as a fatal startup error without first accepting an
  already-matching effective policy. After the user explicitly expanded the
  task scope to the adjacent repository, its bounded correction accepts
  `application.activationPolicy == policy` and calls `setActivationPolicy:`
  only when a transition is required. The native regression uses an
  already-effective prohibited CLI policy to exercise the same generic branch.
  The complete adjacent `make test` matrix passes, and the correction is
  committed there as `f892bb8 Make activation policy application idempotent`.
- Rebuilding the product hosts from that adjacent commit unblocked normal
  regular-policy startup without weakening Dart Terminal's application policy.
  The configured-product scenario passes independently in Developer JIT and
  Release AOT with four panes and clean teardown.

## Subtask 3 verification

- Focused formatting of the three changed Dart files succeeds.
- Focused analysis of the application, runtime harness, and config test reports
  no issues.
- `dart run test/terminal_config_test.dart` passes with the new gate admission,
  missing-gate rejection, and cross-runtime-test conflict cases.
- The Developer JIT and Release AOT bundles build and sign successfully. Their
  regular-policy configured suites pass with four panes after the adjacent
  idempotence correction.
- A temporary, ad-hoc-signed accessory-policy diagnostic copy passes with
  `RUNTIME_CONFIGURATION_INTEGRATION_PASS mode=developer-jit ... panes=4`.
- On resumption, no DartTerminal process remained, but the regular-policy
  LaunchServices attempt still failed at `host-starting`. This disproves the
  earlier coexistence hypothesis for that path: the configuration suite does
  not require LaunchServices semantics, so it returns to the same direct
  packaged-executable launch used by display, hierarchy, action, and clipboard
  acceptance. Restoration alone retains LaunchServices because reopen is part
  of its contract.
- The generic builder's direct `--run` path and a Terminal.app-launched
  `--run` path both fail at the same boundary, so inherited stdio does not
  resolve the failure. A signed minimal AppKit probe launched through
  LaunchServices records `initial=0`, `regular_accepted=0`, and
  `after_regular=0`, demonstrating the adjacent runner's missing idempotent
  already-effective-policy case.
- `make RUNTIME_ARCH=arm64 developer-jit-configuration` passes in 2700 ms, and
  `make RUNTIME_ARCH=arm64 release-aot-configuration` passes in 1263 ms. Both
  validate the configured palette/ANSI rendering, Menlo 18-point font with
  synthetic rejection, 1110×710 frame, 18×11 padding, bar/nonblinking cursor,
  Option-as-text UTF-8 bytes, 8-line/1 MiB scrollback bounds, independent pane
  resources, and zero remaining session/text-client/native handles.
- The first aggregate `runtime-verify` attempts correctly rejected stale Phase
  7 AppKit and compatibility coverage evidence. Their checked-in generators
  updated only reviewed source/document hashes before the next attempt.
- One aggregate attempt reached the existing Developer JIT user-actions gate
  and observed a transient Quit completion/confirmation race. An immediate
  isolated `developer-jit-actions` rerun passed without source changes, and the
  next complete aggregate run passed that gate in both runtimes. No assertion
  was weakened and no unrelated lifecycle code was changed.
- The final `make RUNTIME_ARCH=arm64 runtime-verify` passes formatting,
  analysis, all Dart and native tests, source/bundle audits, and every
  Developer JIT/Release AOT integration family: ordinary launch, display,
  hierarchy/fairness, actions, configuration, restoration, clipboard,
  lifecycle failures, traffic backpressure, resource stress, and shutdown/PTY
  deadline faults.
- After updating the user-facing configuration command and CFG-03 evidence,
  the deterministic compatibility coverage generator refreshed the two
  document hashes. `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed
  all freshness gates, formatting of 218 files with zero changes, analysis, and
  the complete Dart suite.

## Result

The first product configuration family is complete. Zero-config behavior is
preserved, while every new ordinary pane receives the same bounded resolved
theme/palette/font/window/input/scrollback/cursor profile through independent
mutable resources. Both supported M1 runtime modes verify the configuration at
the real AppKit, Metal, PTY, and cleanup boundaries. Declarative keybinds,
reload policy, appearance-aware themes, shell integration, and the effective
configuration inspector remain ordered Phase 8 work.

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
