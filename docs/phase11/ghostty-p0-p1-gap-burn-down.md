# Phase 11 pinned Ghostty P0/P1 gap burn-down

## Status

- Phase: 11
- Task: Ghostty pinned matrix P0/P1 gap burn-down
- Started: 2026-09-13
- State: in progress
- Current subtask: P1 gap burn-down — cursor-cell ligature shaping break
  (completed)

## Purpose

Turn the feature matrix's pinned Ghostty comparison into a reproducible release
closure: every P0/P1 acceptance unit must have an exact product result and
traceable pinned evidence, and every remaining difference must be either fixed
or explicitly demonstrated to be a non-blocking, non-silent limitation with an
owner and bounded acceptance. No blocker, crash, data-loss, security, or silent
misbehavior gap may remain.

## Background

Earlier phases implemented the product feature rows and added parser,
differential, real-application, performance, distribution, accessibility, and
reliability evidence. The matrix still contains evidence gathered at different
times and at more than one pinned Ghostty revision, including one documented
application behavior difference and deliberately deferred physical-duration,
credential, and Intel-host observations. This task must reconcile those facts
systematically instead of treating the prose claim of feature completeness as
an executable parity decision.

The adjacent `dart_appkit` repository is a generic macOS GUI library. Any work
found here remains in Dart Terminal unless a genuinely generic substrate is
strictly necessary. No Dart Terminal implementation, product identifier, or
code/name containing `terminal` may be added to `dart_appkit`.

## Scope

- Inventory every `FEATURE_MATRIX.md` row whose priority contains P0 or P1,
  including its phase, pinned evidence, current product evidence, explicit gap,
  and gate ownership.
- Validate the accepted pinned revisions, local/captured artifact identities,
  checked-in evidence provenance, and freshness relationships without silently
  substituting a newer upstream behavior.
- Classify each remaining difference as actionable product gap, intentional
  product policy, unavailable external observation, or already-approved
  low-priority follow-up. P0/P1 product gaps are completed in roadmap order.
- Add the smallest deterministic tests and product-side implementation needed
  for confirmed P0 then P1 gaps, preserving owner/resource/security bounds.
- Provide one aggregate matrix gate and public/matrix documentation whose
  claims are limited to evidence actually executed.

## Out of scope

- P2-only parity polish and copying Ghostty UI, configuration names, or internal
  architecture where the product acceptance behavior already passes.
- Updating the pinned Ghostty revision merely because upstream has moved.
- Live network capture, unbounded differential fuzzing, or real-time 24/72-hour
  and 30-day campaigns.
- Real Developer ID credentials, Apple notarization service acceptance, and an
  Intel-native host run; those are already-approved follow-ups and cannot mask
  a product correctness gap.
- Product-specific changes or naming in `dart_appkit`.

## Dependencies

- `FEATURE_MATRIX.md` and the pinned revision declared at its top.
- `compatibility/sequence_mode_inventory.json`, implemented surface,
  differential contracts/evidence/acceptance, real-application matrix, and the
  Phase 6 regression coverage report.
- Phase 11 pinned performance comparator provenance and aggregate performance
  gate.
- Existing distribution, diagnostics, accessibility, reliability, and runtime
  acceptance notes and their Make targets.

## Completion conditions

1. Every P0/P1 row has a machine-readable, deterministic classification bound
   to its exact matrix text and applicable checked-in evidence.
2. Every actionable P0 then P1 product gap is fixed with a focused regression;
   no blocker/crash/data-loss/security issue or silent misbehavior remains.
3. Intentional differences and unavailable/deferred external observations are
   narrowly documented and cannot be reported as passing product behavior.
4. A named aggregate gate rejects stale matrix/evidence and passes the focused,
   ordinary repository, and relevant Developer JIT/Release AOT checks.
5. Public documentation and `FEATURE_MATRIX.md` match executed evidence, the
   final diff contains no unrelated/generated runtime artifact, and the
   adjacent generic-library boundary remains clean.

## Verification approach

- Build the inventory from parsed matrix rows rather than hand-maintained row
  counts, with exact allowed priority/classification vocabularies and bounded
  checked-in JSON.
- Reuse existing canonical generators and acceptance tools where possible;
  add negative freshness/ownership tests before accepting aggregate output.
- Run focused tests after each gap, then the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate for every completed
  child. Run bounded product runtime checks where behavior crosses the native
  application boundary.
- Record commands, expected markers, actual results, failures, and residual
  risks here as they are discovered.

## Ordered subtasks

1. **Contract, pinned evidence, and P0/P1 gap inventory**
   - Parse every in-scope matrix row, reconcile all existing pinned sources and
     evidence stores, and assign gap class plus gate owner.
   - Fix the versioned inventory contract and ordered implementation children.
2. **P0 gap burn-down**
   - Resolve every actionable P0 behavior/evidence gap in inventory order with
     focused regressions and no weakened acceptance.
3. **P1 gap burn-down**
   - Resolve every actionable P1 behavior/evidence gap in inventory order and
     preserve explicit policy/deferred distinctions. The order is extended
     rendition/selective erase; semantic ranges; snapshot restore; cursor-cell
     shaping break; variable axes/overrides/diagnostics; synthetic cell glyphs;
     remaining overlays/P3 conversion; then Option-click/semantic selection.
     Renderer and input consumers follow the semantic/font owners they depend
     on rather than introducing duplicate state.
4. **Aggregate closure**
   - Compose freshness and product gates, run ordinary and relevant runtime
     acceptance, update public/matrix documentation, audit `dart_appkit`, and
     close the parent only when all conditions pass.

### Current P1 child — bounded semantic ranges

- **Purpose:** Close the actionable `SCR-11` remainder by turning the existing
  OSC 133 point-in-time prompt state and row hints into bounded, queryable
  prompt/command/output regions that remain correct across scrolling, history,
  resize/reflow, alternate-screen changes, reset, and eviction.
- **Background:** OSC 8 hyperlink identity, selection/search, row semantic
  flags, and previous/next prompt navigation already exist. The gap inventory
  still classifies `SCR-11` as actionable because callers cannot obtain exact
  command/output boundaries or a stable semantic range from the retained
  logical terminal model.
- **Scope:** Inspect the pinned Ghostty semantic prompt lifecycle; define a
  bounded typed range/query contract over stable logical anchors; project OSC
  133 A/B/C/D transitions into exact prompt, command, and output ownership;
  preserve or deliberately invalidate ranges through history, reflow, screen
  switches, reset, and eviction; add deterministic core, parser, selection,
  and navigation regressions; update the machine-readable gap closure and
  public/matrix documentation.
- **Out of scope:** Option-click and semantic selection gestures (a later
  ordered child), search-index redesign, shell integration changes unrelated
  to OSC 133, persisted snapshot restore, copying Ghostty internals, unbounded
  command text retention, and every change or `terminal`-named symbol in the
  generic `dart_appkit` repository.
- **Dependencies:** `TerminalSemanticPromptModel`, screen row flags and stable
  logical anchors, screen-set history/reflow ownership, OSC 133 parser and
  desktop-signal projection, selection/search/navigation consumers, the
  pinned Ghostty revision `d4d8f622...`, and the current 102-row gap inventory.
- **Completion conditions:** Every accepted OSC 133 lifecycle yields exact,
  end-exclusive prompt/command/output ranges without retaining command text;
  malformed/out-of-order input is bounded and deterministic; range identity
  survives valid scroll/reflow operations and cannot alias evicted or reset
  content; no regression occurs in selection, navigation, snapshot, or desktop
  notification semantics; `SCR-11` moves from actionable to accepted only
  after focused tests, regenerated evidence, and the exact repository gate.
- **Verification approach:** Add table-driven lifecycle and malformed-order
  tests, anchor/history/reflow/eviction tests, and consumer integration tests;
  run focused format/analyze and relevant suites, regenerate compatibility and
  Ghostty evidence in dependency order, then run exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`. Apple notarization and
  duration-only long-running campaigns remain explicitly skipped, not blockers.

### Current P1 child — versioned snapshot restore oracle

- **Purpose:** Close the actionable `SCR-12` remainder by accepting the exact
  current readable snapshot format into a fresh terminal model, so tests and
  debugging can prove `format → restore → format` identity and replay a
  reviewed state without executing terminal input.
- **Background:** `TerminalSnapshotFormatter` version 4 already emits bounded,
  deterministic screen or screen-set state and the comparator reports a
  bounded first difference. There is no decoder, so checked-in snapshots can
  only be compared as text and cannot validate model invariants after import.
- **Scope:** Define a typed restore result and typed syntax/version/limit
  failure; preflight input and declared allocation bounds; parse the exact
  version 4 grammar in canonical order; rebuild resources, cells, row/logical
  identity, current/saved cursor and rendition, character sets, margins,
  modes, tabs, history, metadata, buffer ownership, and viewport state into
  fresh objects; preserve optional parser counters for byte-identical
  reformatting; reject unknown, duplicate, noncanonical, truncated, and
  invariant-breaking input atomically; add whole/split-like corpus round trips
  and adversarial limit/topology regressions.
- **Out of scope:** Restoring a live PTY/process, renderer/native handles,
  notifications, Kitty decoded image bytes, application window/session
  persistence, accepting historical formats before version 4, silently
  migrating corrupt snapshots, or adding any Dart Terminal code/name to the
  generic `dart_appkit` repository.
- **Dependencies:** `TerminalSnapshotFormatter` version 4, the shared
  style/grapheme/hyperlink/palette owners, packed screen and paged history
  invariants, `TerminalScreenSet` ownership/viewport rules, parser diagnostic
  counters, reviewed parser corpus snapshots, pinned Ghostty
  `src/terminal/snapshot/` and `formatter.zig` behavior, and the current
  Ghostty gap inventory.
- **Completion conditions:** Every formatter-produced standalone and screen-set
  snapshot within configured limits restores into fresh independent ownership
  and reformats byte-for-byte; all eight checked-in product parser snapshots
  restore and reformat exactly; malformed/version/limit/resource/topology and
  trailing-data cases fail with bounded typed diagnostics before a result is
  published; restore never mutates an existing terminal or performs I/O/native
  work; `SCR-12` becomes accepted only after focused tests, evidence
  regeneration, and the exact repository gate.
- **Verification approach:** Add canonical round-trip tests for all represented
  resources and state, parser-counter and corpus tests, mutation-independence
  checks, and table-driven malformed/over-limit inputs; run format/analyze,
  focused tests, generator freshness in dependency order, the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`, diff review, and a clean
  `dart_appkit` content/name audit. Apple notarization and duration-only
  campaigns remain skipped as authorized.

### Current P1 child — cursor-cell ligature shaping break

- **Purpose:** Close the actionable `TXT-07` remainder by splitting the
  visible cursor cell from otherwise compatible CoreText text runs, preventing
  a ligature from hiding the individual character being edited while keeping
  terminal cell geometry stable.
- **Background:** The renderer package already shapes bounded whole runs with
  ligatures on/off and a generation/style/feature/text-keyed LRU. The product
  compositor groups adjacent nonblank cells by font style and foreground, but
  does not currently treat the visible cursor as a run boundary, so a cursor
  inside a ligature-capable sequence may leave the combined glyph intact.
- **Scope:** Resolve the visible cursor to its owning canonical lead cell;
  split a compatible text run immediately before and after that one scalar
  cell (including its whole width when wide); preserve an atomic interned
  grapheme rather than splitting inside it; keep the behavior independent of
  cursor blink phase; exercise first/middle/last/invisible/other-row and
  grapheme/wide boundaries through the real CoreText, atlas, frame encoder, and
  native Metal acceptance path; bind the product source and regression to the
  Ghostty gap inventory.
- **Out of scope:** New user-facing font-shaping configuration, disabling
  ligatures globally, changes to CoreText/native renderer ABI, variable font
  axes, codepoint overrides, fallback diagnostics, synthetic glyphs, bidi
  terminal layout, selection-run policy, IME model changes, or any change to
  generic `dart_appkit`.
- **Dependencies:** `TerminalRenderModel` cursor projection,
  `TerminalScreenMetalCompositor` compatible-run construction,
  `TerminalShapingCache`, canonical wide/continuation and grapheme flags,
  cursor damage/frame scheduling, the existing real CoreText/Metal test
  fixture, and pinned Ghostty `font/shaper/run.zig`, CoreText shaping tests,
  renderer run options, and default cursor shaping-break policy.
- **Completion conditions:** A visible cursor over the first, middle, or last
  scalar cell yields two, three, or two bounded runs respectively and prevents
  ligature formation across both cursor boundaries; hidden/off-row cursors
  retain the original whole run; wide cells remain atomic and interned
  graphemes are not internally divided; cursor motion changes only derived
  shaping/frame output and never cell content, metrics, selection, PTY input,
  or native ownership; `TXT-07` moves to accepted only after focused/native
  regressions, regenerated evidence, and the exact repository gate.
- **Verification approach:** Add direct compositor run-count and glyph-cluster
  assertions using a ligature-capable baseline font, plus wide/grapheme and
  visibility controls; run focused formatting/analysis and compositor/renderer
  suites, regenerate compatibility and Ghostty evidence in dependency order,
  run exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, review the diff,
  and confirm a clean code/name audit of `dart_appkit`. Apple notarization and
  duration-only campaigns remain skipped as authorized.

## Inventory and decisions

- 2026-09-13: The pinned Ghostty matrix revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4` was re-read for this child.
  `src/font/shaper/run.zig` (SHA-256
  `db733c86a1c4454ee17bb838f6af889d3bffa0d693b6e09f22ab3765695462b7`)
  passes the cursor column only for the visible viewport row and yields two
  runs when the cursor is first/last or three when it is in the middle;
  `src/font/shaper/coretext.zig` (SHA-256
  `f5e541e4da646d9c972ee5e385da3aaa048c9003901e4dbda6969a68684652de`)
  consumes those bounded runs; and `src/config/Config.zig` (SHA-256
  `aa0d42cdab217728ef502ed7b36e681fca3c9ecd3232ae299cecdbefa27c0332`)
  enables cursor shaping breaks by default. Ghostty deliberately leaves an
  interned grapheme atomic. This product adopts the observable default without
  copying Ghostty configuration or ownership into the renderer package.
- 2026-09-13: Product inspection confirmed that the CoreText renderer package
  already owns ligature features and a bounded text/style/feature/generation
  cache. Only `TerminalScreenMetalCompositor` lacked the presentation-aware
  run boundary. The implementation therefore resolves the visible cursor to a
  canonical lead cell, isolates one scalar cell (or the complete two-column
  wide cell), skips interned graphemes, and otherwise leaves text, cell
  metrics, parser state, PTY input, cache policy, and the native ABI unchanged.
  Blink-off presentation continues to use the same shaping boundaries because
  terminal cursor visibility, not the current paint phase, owns the edit
  location.
- 2026-09-13: The first focused analyzer run found that the per-row boundary
  variable had been inserted into the compositor's earlier background loop
  instead of the text-run loop. Moving the declaration to the text-run owner
  fixed the undefined reference; the following focused analysis passed with
  `No issues found!`. The first native compositor regression then failed only
  because a Times-Roman CJK fallback glyph exceeded that fixture's unusually
  narrow canonical cell. Ligature assertions continue to use Times-Roman,
  while wide/grapheme atomicity uses the product monospace catalog; the rerun
  passed real CoreText shaping, atlas construction, frame encoding, and native
  Metal readback.
- 2026-09-13: Focused format reported four Dart files already formatted and
  focused analysis again reported `No issues found!`. A later sandboxed rerun
  of the compositor test could not acquire a Metal device and exited with the
  typed `deviceUnavailable` status before any case executed. The identical
  command was rerun in the normal macOS execution context and exited 0; this
  environmental denial is not counted as a product failure or as acceptance by
  itself.
- 2026-09-13: Regression coverage and the Ghostty inventory were regenerated
  in dependency order. Their freshness gates passed, and the inventory now
  reports 102 rows, 93 accepted, zero actionable P0, four actionable P1, two
  documented differences, and three external follow-ups. The focused inventory
  test passed exact generated/committed identity and fail-closed negatives for
  both the implementation boundary and wide/grapheme regression evidence.
- 2026-09-13: Final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed all native package,
  generated/freshness, compatibility, differential, application, terminfo,
  shell, distribution, format (330 files, zero changes), analysis (no issues),
  security, update, symbol, and aggregate Dart tests, ending with
  `dart_terminal tests passed`. `git diff --check` passed. The adjacent
  `dart_appkit` worktree is clean; case-insensitive executable content and
  filename audits excluding docs/build/cache/git found zero `terminal`,
  `dart_terminal`, or `dart-terminal` matches. No generic-library file changed.
  Apple notarization and duration-only campaigns were skipped as authorized.
  The next ordered child is variable font axes, codepoint override, and
  fallback diagnostics.

- 2026-09-13: The first focused analyzer rerun passed with `No issues found!`,
  and `dart run test/terminal_semantic_prompt_test.dart` exited 0 after its
  native build hooks. The new regression covers exact same-row boundaries,
  incomplete and repeated lifecycle markers, fixed storage/query caps,
  history/reflow identity, history eviction, primary/alternate ownership, and
  RIS cleanup.
- 2026-09-13: The range store is a fixed ring of stable logical anchors plus a
  monotonic, content-free command ID. It retains neither OSC option payload nor
  a copy of prompt, command, or output text. Query resolves both end-exclusive
  anchors against the current history/screen document and omits a whole range
  if either endpoint has been evicted, preventing recycled-row aliasing.
- 2026-09-13: Compatibility evidence keeps OSC 133 classified `partial`
  because option fields remain deliberately unretained, while recording the
  completed A/B/C/D/I/L/N/P range projection. The Ghostty inventory binds the
  generated record, implementation source, regression source, and updated
  `SCR-11` matrix text before changing that row from actionable to accepted.
- 2026-09-13: A repository-sandbox `dart format` invocation formatted the Dart
  inputs successfully but then exited 1 while attempting to update the global
  Dart telemetry-session timestamp. No source formatting failed. The command
  will be repeated with analytics suppressed and the required permission;
  this environmental failure is not accepted as verification.
- 2026-09-13: The first Ghostty gap-inventory focused test failed only in its
  negative fixture: `replaceFirst` renamed the test registration while leaving
  the function declaration, so the source-presence validator correctly still
  found the required regression name. The fixture now uses `replaceAll` to
  remove both occurrences; product code and generated evidence were not
  implicated.
- 2026-09-13: An attempted parallel freshness check exposed a build-hook race:
  `compatibility-inventory-check` and the Ghostty inventory check concurrently
  rewrote the same `.dart_tool/lib` native-asset bundle, and the former could
  not find the renderer dylib while applying install names. The Ghostty check
  passed independently. Generator concurrency is outside this child; all Dart
  build-hook checks are now run sequentially, and the failed freshness check
  must pass on rerun before completion.
- 2026-09-13: The first exact `make test` progressed through native capability,
  parser/reference, localization, diagnostics, AppKit, and compatibility
  regression checks, then correctly rejected the Phase 6 regression-coverage
  report as stale because the regenerated OSC 133 inventory hash changed. This
  is a required evidence dependency, not a product failure. Regenerate the
  coverage report, then regenerate the Ghostty inventory that hashes it before
  rerunning the exact gate.

- 2026-09-13: Work began immediately after commit `db54f89` and a mandatory
  roadmap reread. The sanitizer/fuzz/fault parent is complete, the worktree is
  clean, and this is the first unchecked Phase 11 item. The next item, release
  candidate daily-use matrix, will not be implemented early.
- 2026-09-13: Initial search confirmed that pinned evidence is distributed
  across the feature matrix, sequence/mode inventory, differential backend and
  capture files, application acceptance, regression coverage, and the Phase 11
  performance comparator. A complete row-by-row classification is therefore
  required before choosing any product implementation change.
- 2026-09-13: Matrix parsing found 102 in-scope rows: 69 `P0`, six `P0/P1`,
  26 `P1`, and one `P1/P2`. The reviewed classification has no actionable P0
  product gap, eight actionable P1 units (`SCR-10`, `SCR-11`, `SCR-12`,
  `TXT-07`, `TXT-08`, `TXT-10`, `REN-08`, and the P1 portion of `IN-10`), two
  rows with explicit non-silent differences, and three rows with approved
  external follow-ups. This inventory does not reinterpret the supplemental
  Ghostty query capture revision as the matrix/performance revision.
- 2026-09-13: A direct `dart format` formatted the new inventory tool and test,
  then emitted a sandbox-denied telemetry timestamp exception under
  `/Users/remi/.dart-tool`. The requested files were formatted successfully;
  subsequent Dart commands use `DART_SUPPRESS_ANALYTICS=true`, and this
  incidental analytics write is not a product or test dependency.
- 2026-09-13: The first focused verification incorrectly ran the Make check
  and direct Dart test concurrently. Both build hooks attempted the same Metal
  module-cache output under `/Users/remi/.cache/clang` and were sandbox-denied;
  the concurrently run focused `dart analyze` still reported no issues. This
  is an orchestration failure, not accepted evidence. Native/build-hook Dart
  commands will be rerun sequentially with the required local cache access,
  matching the repository's shared-output policy.
- 2026-09-13: The first exact `make test` completed with exit status zero and
  every test passed, including the new inventory marker, but `dart analyze`
  reported one informational `directives_ordering` issue in the aggregate test
  runner. The run is not the final warning-clean acceptance; the import order
  was corrected before the required rerun.
- 2026-09-13: Added a deterministic version 1 inventory at
  `compatibility/ghostty_p0_p1_gap_inventory.json` and a generator/checker at
  `tool/ghostty_p0_p1_gap_inventory.dart`. It requires the exact ordered set of
  102 P0/P1 rows, hashes each acceptance/evidence/current field, binds ten
  existing evidence files, and distinguishes the matrix/performance Ghostty
  revision `d4d8f622...` from the separately pinned supplemental differential
  revision `492300ca...`; neither may silently substitute for the other.
- 2026-09-13: Reviewed totals are 89 accepted rows, two accepted rows with
  documented differences, three accepted rows with approved external
  follow-ups, eight actionable P1 rows, zero actionable P0 gaps, and zero
  silent-misbehavior gaps. The 13 gap records carry exact row IDs, kind,
  priority, owner, actionability, and reason. P1 was split into eight ordered
  roadmap children because style/state, shaping/font, renderer, and input work
  cannot be implemented or reviewed safely as one commit.
- 2026-09-13: Focused validation passed
  `make ghostty-p0-p1-gap-inventory-check` with
  `GHOSTTY_P0_P1_GAP_INVENTORY_PASS rows=102 accepted=89 actionable_p0=0
  actionable_p1=8 documented_differences=2 external_follow_ups=3
  pinned_revision=d4d8f62`. Direct unit tests passed exact committed/generated
  equality plus stale total, pin drift, and duplicate-row negatives. Focused
  analysis reported no issues.
- 2026-09-13: After correcting the one import-order info from the first run,
  the exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` rerun passed all
  native/package, generated/freshness, compatibility/application/distribution,
  format (326 files, zero changes), analysis (no issues), and Dart tests,
  ending with `dart_terminal tests passed`. No runtime or sanitizer artifact is
  tracked by this child; the next ordered child is the zero-actionable-P0
  closure, not P1 implementation.
- 2026-09-13: After commit `42c2f7e` and the mandatory roadmap reread, the P0
  child began from a clean worktree. The only P0-classified difference is
  xterm mode 1001 in the mosh application cell: the captured sequence is reset
  only, inventory support is `unsupported`/`reject`, acceptance records exactly
  one variant, and both `screen_mutation` and `matrix_blocker` are false. The
  other P0 row carrying a follow-up is `DIST-01`; its arm64/x86_64/Universal and
  Rosetta product behavior is accepted, while an Intel-native host observation
  remains separately and explicitly unverified. Neither item authorizes
  inventing an enable handshake or treating external evidence as executed.
- 2026-09-13: The first P0 negative test removed the exact mode-1001 inventory
  owner and exposed an untyped `StateError` from `singleWhere` rather than the
  inventory's bounded validation exception. Positive data still passed. The
  validator now checks candidate cardinality first so missing or duplicate P0
  ownership fails with the task-specific, content-free classification.
- 2026-09-13: The next exact repository gate reached its format check after all
  prerequisite evidence checks passed, then stopped because the cardinality
  fix had not been run through focused format. `dart format` changed only the
  expected wrapping in the inventory tool. This procedural failure is not
  accepted as final evidence; the formatted source is retained for a clean
  rerun.
- 2026-09-13: The inventory checker now parses the canonical sequence record,
  application acceptance, and regression coverage instead of relying only on
  their hashes. It requires mode 1001 to remain one private rejected record
  with no claimed implementation/test evidence; the application gap must be
  exact, explicit, input-only, one-variant, non-mutating, and non-blocking; and
  aggregate coverage must retain zero known P0 silent corruption and zero
  blocking failures. The generated report exposes these facts under
  `p0_closure` and keeps the Intel-native observation in an explicit external
  follow-up list.
- 2026-09-13: Focused positive and negative tests passed after the typed-error
  correction. Mutating screen impact, removing the exact inventory owner, or
  changing known P0 silent corruption to one now fails closed. Focused format,
  analysis, generation freshness, and the marker with `actionable_p0=0` all
  passed.
- 2026-09-13: Final
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed all ordinary native,
  package, generated/freshness, compatibility, application, distribution,
  format (326 files, zero changes), analysis (no issues), and Dart tests,
  ending with `dart_terminal tests passed`. Diff validation before the roadmap
  status update found only the four intended implementation/evidence/memo
  files and no whitespace issue; the roadmap is the fifth final file. The
  adjacent `dart_appkit` worktree is clean and its case-insensitive code/name
  audit contains no `terminal` or `dart_terminal` occurrence. P0 closure has
  no remaining product work; the next ordered task is the first P1
  implementation child, extended rendition and protected selective erase.
- 2026-09-13: After commit `6dd8c00` and the mandatory roadmap reread, the
  first P1 child began from a clean worktree. Its purpose is to close `SCR-10`
  without changing the 17-byte cell payload: underline color and overline
  belong to immutable style definitions, while DEC character protection is
  already reserved as width/flag bit 3 by ADR-003. Scope is SGR 53/55/58/59,
  DECSCA, DECSED/DECSEL, style identity, current/saved rendition, snapshots,
  damage/render projection, and deterministic parser/render regressions.
  Semantic ranges, persisted sessions, shaping/font work, unrelated erase
  families such as DECSERA, and every change to generic `dart_appkit` remain
  outside this child. Completion requires bounded style interning, atomic
  wide/grapheme selective erase, ordinary erase overriding protection, reset
  and save/restore correctness, visible underline-color/overline output, fresh
  generated compatibility evidence, and the exact repository gate.
- 2026-09-13: Initial code inspection found that `TerminalCellFlags.protected`
  already survives packed copy, scrollback, reflow, snapshots, and topology
  validation, but parser printing hard-codes `isProtected: false` and exposes
  no current protection state. DECSCA, DECSED, and DECSEL are still declared
  unsupported in the sequence inventory and absent from the compatibility
  selector surface. `TerminalStyleTable` currently interns only a 16-bit
  attribute word; it has no underline-color column, and the compositor draws
  supported underline shapes with the resolved foreground while overline has
  no attribute or drawing operation. Therefore protection will stay a cell
  flag, whereas underline color and overline will extend the bounded style
  resource so style identity and renderer projection cannot diverge.
- 2026-09-13: The focused formatter changed only the expected Dart files, then
  the SDK again attempted to update its home-directory telemetry session file
  despite `DART_SUPPRESS_ANALYTICS=true` and exited after formatting. Analysis
  therefore did not run in that chained sandbox command. It was rerun with
  the same `CI=true`/suppression environment and the required cache access;
  focused analysis reported no issues. This is a tool telemetry restriction,
  not a source or product failure, and the final repository gate remains
  required.
- 2026-09-13: The first focused style test stopped on its fixture's old
  `definitionCount == 2` assertion after the bounded table fixture had been
  deliberately expanded to four definitions to cover underline-color
  identity and overline. The table correctly rejected the fifth definition;
  only the stale expected count was wrong. The assertion now expects four,
  and the entire focused sequence must be rerun from the beginning.
- 2026-09-13: The next focused run passed style, screen, and screen-set tests,
  then exposed another test expectation error: the maximum DECRQSS rendition
  is 84 bytes, not the estimated 87. The encoder remained below its new
  96-byte fixed cap and did not overflow; the exact expected length was
  corrected before another full focused rerun.
- 2026-09-13: The subsequent six-test focused run passed style, screen,
  screen-set, reply, compatibility-surface, and native Metal compositor
  coverage. A separate snapshot test then stopped because the readable style
  definition expectation still described the former attribute-only resource;
  the formatter correctly emitted the new `underline_color=default` field.
  The fixture now carries a palette underline color and overline so the exact
  snapshot assertion proves both additions instead of merely accepting the
  default serialization.
- 2026-09-13: The corrected standalone snapshot test passed. Regenerating the
  four deterministic differential baselines then passed with 202 input bytes
  and 210 split runs, and differential acceptance remained 12 accepted cells
  with eight agreements, zero undocumented gaps, and four unavailable external
  comparisons. The first regression-coverage regeneration was sandbox-blocked
  when the Dart native-assets hook attempted to write Clang's shared Metal
  module cache under `/Users/remi/.cache/clang`; it made no accepted report
  claim and must be rerun with the repository's already-required cache access.
- 2026-09-13: With shared-cache access, the regression prerequisite correctly
  failed closed on the reviewed `decrqss-current-sgr` observation: reply bytes,
  state, counters, and projected screen were identical, while only the full
  snapshot hash and UTF-8 size changed because every non-default style resource
  now serializes its underline-color token. This is an intentional snapshot
  contract extension; the reviewed corpus will be regenerated through its
  canonical `--generate` path and then checked before coverage is rebuilt.
- 2026-09-13: The pinned Ghostty sources were re-read at matrix revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. `Terminal.zig` (downloaded
  source SHA-256
  `f3c68cde1d7e871b2f901f50c85cc87a76360ff1fb56111d08f5269a9e5de602`)
  retains DEC-protected cursor state and distinguishes selective erase;
  `style.zig` (SHA-256
  `b26507489473b7b2158adf3e70c9aac2665417e582eb5c3cab5a491e6d2cf5c9`)
  carries underline color and overline in style state. This child implements
  the DEC DECSCA/DECSED/DECSEL contract; Ghostty's separately modeled ISO
  protection mode and DECSERA remain outside the matrix row and this scope.
- 2026-09-13: Canonical regeneration updated all nine reviewed compatibility
  observations and replayed 390 input bytes over 417 whole/split/bytewise
  plans. Regression coverage then regenerated successfully. Application
  acceptance still passed eight cells (seven clean and one explicit gap), so
  no external capture was rewritten. The final Ghostty inventory generation
  and freshness check passed with 102 rows, 90 accepted, zero actionable P0,
  seven remaining actionable P1, two documented differences, and three
  external follow-ups. Its positive and malformed-evidence unit tests also
  passed after formatting all 324 Dart files (one expected wrapping change).
- 2026-09-13: The first exact repository gate passed every native package,
  generated/freshness, compatibility, application, distribution, formatting,
  and analyzer prerequisite, then the aggregate Dart runner failed closed on
  the reviewed `screen-semantics` product-parser snapshot. As with the reviewed
  regression observation, line 5 differed only by the intentional appended
  `underline_color=default` style field. The product corpus snapshot must be
  refreshed through its canonical review flow before the exact gate is rerun;
  this failed run is not completion evidence.
- 2026-09-13: After reviewing and updating the sole affected parser snapshot,
  its direct harness passed all eight cases, 1,421 input bytes, and 1,437 split
  runs with aggregate snapshot hash `697844072`. The next exact gate reached
  the aggregate runner and correctly exposed that the unit test still pinned
  the former aggregate hash `995854368`; the per-case oracle was already exact.
  Both the numeric assertion and machine-readable line are updated to the
  directly observed new hash before another clean full-gate rerun.
- 2026-09-13: The following exact gate passed the corrected parser corpus and
  progressed deep into the aggregate Dart suite, where the inventory test
  exposed one remaining stale total: the reconciliation itself had already
  reported the correct 122 implementation selectors, while its unit assertion
  still expected 119. The three newly implemented DECSCA/DECSED/DECSEL
  selectors account exactly for the delta; the fixed cardinality assertion is
  retained and updated to 122 before rerunning focused and full checks.
- 2026-09-13: The next exact gate passed the corrected 122-selector inventory
  assertion and all earlier checks, then the deterministic property/fuzz gate
  reported its intentional snapshot-oracle delta: the execution budget stayed
  1,296, parsed bytes stayed 95,388, and only the state hash changed from
  `733442573` to `1691336757`. Because the accumulator hashes the complete
  snapshot, the serialized underline-color field accounts for this change;
  the fixed expected hash is updated and must reproduce in focused and full
  reruns.
- 2026-09-13: The focused property/fuzz rerun reproduced the new exact hash.
  The next full gate then stopped early in an unrelated real-PTY lifecycle
  test (`live Dart child cannot steal native PTY completion`) because its event
  lookup found no element. This same test passed in each of the three preceding
  full-gate attempts, while no PTY source changed in this child, so it is
  treated as a transient runtime observation rather than accepted evidence.
  The exact PTY target and then the complete gate will be rerun; a repeat would
  require investigation instead of being ignored.
- 2026-09-13: The isolated PTY target and subsequent complete gate both passed,
  confirming the one-off missing event was transient. Pre-commit review then
  found a real state-oracle omission: protected cell flags were readable, but
  the current and saved DECSCA attributes for future prints were not serialized.
  Because the style resource schema also gained underline color, retaining
  snapshot version 3 would silently change an exact format in place. The
  formatter therefore advances to version 4 and writes both protection booleans;
  historical application evidence versions 1–3 remain accepted, while a unit
  case proves current version 4 can coexist with immutable version-one captures.
- 2026-09-13: Focused snapshot validation passed with current/saved protection
  set true, and all eight reviewed product snapshots replayed exactly under
  version 4 with aggregate hash `915933130`. The first application-evidence
  unit rerun exposed that its former unsupported-version negative used version
  4; now that 4 is valid, the fixture correctly moves to version 5. No captured
  application snapshot or external observation is rewritten.
- 2026-09-13: The immediate rerun failed at the positive coexistence case
  because the mechanical one-token patch had changed its first `version=4`
  replacement to 5 while leaving the later negative at 4. Inspection showed
  the branches were inverted; the positive now explicitly uses version 4 and
  the unsupported negative explicitly uses 5 before rerunning the entire file.
- 2026-09-13: The corrected application-evidence file passed. Differential
  baselines/acceptance, all nine compatibility observations, regression
  coverage, and the Ghostty inventory were then regenerated in dependency
  order for version 4. The deterministic property/fuzz run preserved all
  budgets and produced the expected new snapshot-derived state hash
  `984263293`; its prior version-3 hash assertion is updated before a confirming
  rerun.
- 2026-09-13: The version-4 full gate passed every prerequisite and reached the
  Phase 9 protocol property suite, whose complete-snapshot digest intentionally
  changed from `2246715040` to `2980607666`. Its fixed workload remained eight
  anchors, 64 mutations, 64 generated cases, 680 executions, and 731,150 parsed
  bytes. The exact digest assertion is updated and will be reproduced directly
  before another full run.
- 2026-09-13: The focused Phase 9 property rerun reproduced state hash
  `2980607666`. Final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed all native
  packages, generated/freshness, compatibility, differential, application,
  terminfo, shell, Ghostty inventory, distribution, format (326 files, zero
  changes), analysis (no issues), and aggregate Dart tests, ending with
  `dart_terminal tests passed`. The accepted inventory is 102 rows with 90
  accepted and seven remaining actionable P1 units. `git diff --check` passed.
  The adjacent `dart_appkit` worktree is clean, and a case-insensitive audit of
  its native/packages/scripts/test/tool/examples trees and Makefile found zero
  `terminal` or `dart_terminal` occurrences. Apple notarization and
  duration-only long-running tests were not executed, as explicitly authorized;
  neither is used to claim this product behavior. The next ordered child is
  bounded semantic prompt/command/output ranges.
- 2026-09-13: After commit `41ad988` and the mandatory roadmap reread, the
  semantic-range child began from a clean worktree. Current code keeps one
  transient OSC 133 shell state and bounded per-row prompt/command/output bits;
  those bits survive scrollback and are unioned across reflow, but they cannot
  express a boundary within a row, correlate prompt/input/output segments, or
  distinguish two commands sharing one physical/logical row. Selection already
  provides end-exclusive `TerminalLogicalAnchor` resolution over history plus
  live grids, including eviction rejection, so a second content store is neither
  needed nor allowed.
- 2026-09-13: The pinned Ghostty semantic parser was re-read at revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`; its exact source SHA-256 is the
  already-pinned
  `04935466b4fd8b9e0e41e7d69bb72fc6ff6141111d9274d8bda927dcb41488ff`.
  It recognizes A/B/C/D/I/L/N/P and exposes options including command-line
  decoding, click behavior, and prompt kinds. This product continues to reject
  command-text retention and option authority. The selected design stores only
  bounded typed marker ranges over stable logical anchors, groups segments with
  a content-free command ID, filters unresolved/evicted endpoints at query time,
  and keeps existing row flags as the cheap rendering/navigation hint.
- 2026-09-13: The first formatter invocation mistakenly included this Markdown
  memo despite the earlier recorded warning about Dart-only inputs. It formatted
  the six actual Dart files (two changed) and rejected only the memo as
  non-Dart; no Markdown content changed. Subsequent formatting commands list
  Dart paths or Dart directories only.
- 2026-09-13: After regenerating the reviewed differential baseline report,
  regression coverage, and Ghostty inventory in dependency order, final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed. It covered all native
  capability packages, generated/freshness checks, compatibility and
  differential evidence, application evidence, terminfo and shell integration,
  the Ghostty inventory (`accepted=91`, `actionable_p1=6`), distribution policy,
  formatter (327 files, zero changes), analyzer (`No issues found!`), security
  stress, updater/rollback/symbol cases, and the aggregate suite ending with
  `dart_terminal tests passed`. Focused semantic, compatibility-inventory, and
  gap-inventory tests also exited 0; `git diff --check` passed.
- 2026-09-13: The adjacent `dart_appkit` worktree remained clean. A
  case-insensitive content audit outside documentation/build/cache/git paths and
  a filename audit outside those same paths found no `terminal`,
  `dart_terminal`, or `dart-terminal` occurrence. Historical consumer notes in
  `docs/WORKLOG.md` were observed but are not executable code or product API and
  were not modified. No Dart Terminal code or naming was added to the generic
  library. Apple notarization and duration-only long-running campaigns were
  skipped as authorized. The next ordered child is the versioned snapshot
  restore oracle.
- 2026-09-13: Final review corrected the matrix capacity wording from an
  ambiguous "maximum 1024" to the implemented default 1024 and hard maximum
  65,536. After regenerating the matrix-dependent coverage and Ghostty reports,
  the exact full gate passed again in the final source/evidence state, including
  327-file zero-change formatting, clean analysis, Ghostty totals 91 accepted
  and six actionable P1 rows, and `dart_terminal tests passed`.
- 2026-09-13: Snapshot-restore investigation found one versioned canonical
  format (`dart-terminal-state-snapshot`, version 4) with separate standalone
  screen and screen-set grammars. The formatter bounds aggregate rows, packed
  cells, style/grapheme/hyperlink resources, hyperlink bytes, and output
  characters. It serializes shared palette/resources, sparse non-default
  cells, logical row identity/offsets, current/saved screen state, history
  policy, metadata stacks, active-buffer/viewport ownership, and optional
  parser counters; generation/damage, live PTY/process/native ownership,
  notification/image state, and the palette override layer below the visible
  values are intentionally absent. Restore is therefore a strict test/debug
  oracle for represented semantic state, not live-session continuation.
- 2026-09-13: The pinned Ghostty revision was re-read from
  `src/terminal/snapshot/main.zig`, `src/terminal/formatter.zig`, and
  `src/terminal/snapshot/terminal.zig`. The locally retained source identities
  are respectively SHA-256
  `98d896cbabd9c7a76fb67bfb6b7f32a90ba329b190b16b01194ed8d174ddb29a`,
  `9164d79db2362538176f6dd59274fbbec5520051e05e217b7b12024802dbbff4`,
  and `dc4a6a4846450aa4251d3787670dc2f1879071ebd33315994c59e02367137dd4`.
  Ghostty treats its snapshot as documented terminal state rather than generic
  replay, decodes into owned empty screens, releases partial resources on
  failure, validates exact ordering and trailing input, and resets derived
  presentation/cache state. This supports a fresh-owner, exact, fail-closed
  decoder rather than mutation of an existing session.
- 2026-09-13: Chosen implementation uses a bounded lazy newline reader instead
  of splitting the whole input, exact current-version/order parsing, typed
  syntax/version/limit/invariant/noncanonical failures without source excerpts,
  and a final canonical reformat comparison. Resources and rows are fully
  staged before construction of a fresh `TerminalScreen` or
  `TerminalScreenSet`; package-internal helpers restore packed arrays,
  scrollback pages, metadata stacks, active-buffer state, and retained primary
  viewport offset. Optional parser counts use an immutable value object so a
  restored oracle never fabricates or owns a live parser sink.
- 2026-09-13: History's formatter-visible logical offset is retained, but its
  internal per-row logical-cell count is not serialized. Restore derives joined
  soft-wrap counts from the following row offset (including the history/grid
  boundary) and otherwise from the last explicit non-default cell. This is
  sufficient for byte-exact v4 reformatting and current represented semantics;
  changing the wire format to expose unrepresented mutation-only state would
  require a later version and is deliberately outside this compatibility task.
- 2026-09-13: A first direct `dart format` changed only the requested Dart
  files, then the Dart CLI failed to update its global analytics timestamp
  under the repository sandbox. The same issue recurred with the analytics
  environment flag. Static analysis was rerun with the repository's required
  local cache permission and passed with `No issues found!`; neither telemetry
  failure is accepted as validation evidence.
- 2026-09-13: The first focused restore test stopped before decoding because
  its new hyperlink fixture used a literal space, which the existing safe URI
  contract correctly rejects. The fixture now uses `%20`. The second run found
  a decoder typo (`gl=` versus the canonical `gl:` character-set field), and
  the third exposed that a valid one-row screen has canonical margins `0,0`
  while the normal margin mutator requires a strictly ordered multi-row range.
  The parser typo and the single-row/single-column restore boundary were fixed;
  no existing formatter or screen contract was weakened.
- 2026-09-13: Focused snapshot tests now pass standalone state with style,
  grapheme, hyperlink, wide-cell, cursor/save, mode, presentation, tab, and
  parser counters; screen-set state with history, both buffers, mode 1049,
  retained viewport, cwd/title stacks; independent post-restore mutation; all
  eight checked-in parser corpus snapshots; and typed rejection of unsupported
  version, noncanonical numeric text, truncation, trailing input, unknown flags,
  input limit, and line limit. The decoder performs no I/O; corpus file access
  belongs only to the test harness.
- 2026-09-13: After regenerating regression coverage and the Ghostty inventory
  in dependency order, the first combined focused run passed the snapshot
  suite and then stopped because the inventory validator still asserted the
  preceding 91/6 accepted/actionable totals even though its generator correctly
  emitted 92/5. The validator and its negative fixtures now require 92 accepted,
  five actionable P1, ten gap records, and the snapshot restore completion
  marker. The rerun passed exact generated/committed equality and both new
  restore-evidence negatives.
- 2026-09-13: The first complete repository gate passed every native,
  compatibility, evidence, distribution, format (330 files, zero changes),
  analysis, security, updater, and aggregate Dart test, ending with
  `dart_terminal tests passed`. Final code review then identified one missing
  early check: input could satisfy the decoder's input cap while exceeding the
  formatter output cap used for the mandatory canonical comparison. Restore
  now rejects that case as a typed limit failure before parsing and validates
  every nested formatter limit. The focused suite passed the new case and the
  Ghostty evidence was regenerated; because product source changed after the
  first full pass, a second exact full gate is required for completion.
- 2026-09-13: The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` rerun passed in the reviewed
  source/evidence state. It included all native capability packages, generated
  and compatibility freshness, differential/application/distribution gates,
  330-file zero-change formatting, clean analysis, typed restore resource and
  topology negatives, all eight snapshot corpus round trips, security stress,
  updater/rollback/symbol tests, and the aggregate marker
  `dart_terminal tests passed`. `git diff --check` passed. The adjacent
  `dart_appkit` worktree is clean; a case-insensitive executable-source/content
  and filename audit excluding docs/build/cache/git found zero `terminal`,
  `dart_terminal`, or `dart-terminal` matches. No generic-library file changed.
  Apple notarization and duration-only campaigns were skipped as authorized.
