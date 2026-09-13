# Phase 11 pinned Ghostty P0/P1 gap burn-down

## Status

- Phase: 11
- Task: Ghostty pinned matrix P0/P1 gap burn-down
- Started: 2026-09-13
- State: in progress
- Current subtask: native Option-click and semantic selection gesture integration

## Current P1 child — Option-click cursor and semantic selection

### Active ordered subtask 2 — native gesture integration

- **Purpose:** Connect the already-bounded semantic range and cursor-movement
  core to the ordinary product mouse path exactly once, without moving terminal
  policy into generic AppKit code.
- **Background:** Commit `c7fce01` completed only the content-free screen and
  viewport planning core. The post-commit clean-tree and roadmap reread on
  2026-09-14 confirms that native gesture integration is now the first
  unchecked ordered item and that `IN-10` must remain open until later
  dual-runtime evidence exists.
- **Scope:** Add one terminal-local Option-click sequence owner downstream of
  `TerminalMouseRouter`; encode accepted primary/live prompt movements with the
  current normal/application cursor mode; clear and redraw local selection at
  gesture ownership transfer; make ordinary triple-click use a semantic-clamped
  line and Control-or-Command triple-click/drag use retained output blocks; add
  focused unit and product-owner integration checks.
- **Out of scope:** Generic `dart_appkit` changes, OSC 133 producer option
  negotiation, SGR click-event emission, README/feature-matrix acceptance
  claims, generated gap closure, dual-runtime product evidence, notarization,
  and duration-only soak.
- **Dependencies:** AppKit v15 already supplies modifier/button/cell data;
  `TerminalMouseRouter` already gives active mouse reporting precedence unless
  Shift explicitly selects local ownership; the first child supplies stable
  range queries and movement plans; the existing pane write queue remains the
  sole PTY input owner.
- **Completion conditions:** Exact-Option undragged primary clicks are consumed
  once and emit at most 255 normal or application-cursor arrow bytes only for an
  accepted plan; drag, stale state, wrong gesture, alternate/history/no-input,
  and active mouse reporting fail closed without duplicate selection or write.
  Ordinary triple-click clamps to a retained semantic segment; Control-or-
  Command triple-click and drag select complete output blocks and ignore
  non-output expansion targets. Selection surface updates, cancellation, and
  disposal are deterministic, focused tests and the exact repository gate pass,
  and the adjacent generic library remains unchanged and terminal-free.
- **Verification approach:** Add focused controller/router/selection/product
  tests for ownership, bytes, cap, clearing, rendering observation, cancellation,
  and cleanup; run formatting, analysis, generated freshness, the exact full
  `make test` gate, diff review, and the adjacent tracked-path/content audit.
  Only this ordered subtask is marked and committed after all checks pass.
- 2026-09-14: Integration inventory found that changing only triple-click's
  initial range is insufficient: the existing drag path re-expands its raw
  endpoints as complete logical lines and would cross a prompt/input/output
  boundary after movement. This child therefore also needs one content-free
  stable-range combiner for two already-clamped semantic line selections. It
  does not add new semantic storage or text retention. Exact Option ownership
  is restricted to left-button single-click begin/update/end with only the
  Option modifier and an inside-grid undragged release. Once begun, a drag or
  changed release is consumed as cancellation; otherwise ordinary selection
  retains ownership. Active mouse reporting without Shift never reaches this
  local arbiter because `TerminalMouseRouter` already owns and reports it.
- 2026-09-14: The first formatter invocation mistakenly included this Markdown
  memo in the Dart source list. Dart formatted the four changed Dart files, then
  rejected the memo at its first heading as non-Dart input; no memo bytes were
  changed. Later formatter invocations use Dart files only.
- 2026-09-14: The first focused prompt-click compile found two direct-import
  omissions: product code does not see a type merely because the package barrel
  exports it, and the new controller needs `terminal_mouse_event.dart` for the
  button enum rather than relying on a sibling import to re-export it. Adding
  those two internal imports resolved every compile error. The prompt-click and
  semantic-selection focused executables now both pass, including normal CSI
  left/right, application-cursor SS3 left, no-op/rejection, 85-arrow/255-byte
  acceptance, 86-arrow rejection, selection clearing, reporting exclusion,
  drag/mode-generation cancellation, exact modifier ownership, ordinary word
  fallback, prompt/input/output clamping, Control/Command output selection,
  reverse and non-output drag, and stale-screen cancellation.
- 2026-09-14: Final product-path review found that the pre-existing OSC 8
  hyperlink owner treated exact Command clicks with every positive click count
  as an open gesture. That would consume Command triple-click before semantic
  output selection. Hyperlink activation is now restricted to exact Command
  single-click; a focused regression proves Command triple down/up passes to
  the local selection owner and opens nothing, while the existing single-click,
  unsafe target, stale target, and drag-cancellation checks still pass.
- 2026-09-14: The final focused suite passes for prompt click, semantic
  selection, hyperlink ownership, autoscroll, mouse routing, semantic ranges,
  and selection/search. Static analysis reports no issues. The exact full
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate was run again after the
  last ownership change and passes: all generated checks are fresh, formatting
  covers 336 files with zero changes, analysis is clean, and the aggregate ends
  with `dart_terminal tests passed`. The regenerated Phase 7 acceptance evidence
  retains four covered criteria; the Ghostty inventory deliberately remains 102
  rows / 96 accepted / zero actionable P0 / one actionable P1 / zero silent
  misbehavior because dual-runtime closure is the next child. `git diff
  --check` is clean. The adjacent `dart_appkit` worktree remains clean, its
  tracked paths contain no case-insensitive `terminal`, and its tracked Dart,
  native source, script, manifest, and Makefile content has zero such match.
  No adjacent file changed. Notarization and duration-only campaigns remain
  skipped as authorized. This native gesture integration child meets its
  recorded scope and completion conditions without prematurely closing
  `IN-10`.

- **Purpose:** Close the final actionable pinned P1 input row by adding
  terminal-local Option-click cursor positioning and bounded semantic
  prompt/output selection to the existing AppKit mouse/selection ownership
  path.
- **Background:** The post-commit roadmap reread after `4460b61` identifies
  `Option-click cursor／semantic prompt-output selection` as the first unchecked
  item. Drag/drop, Services, Quick Look, character/word/line selection,
  autoscroll, mouse-report arbitration, and stable semantic prompt/command/
  output ranges already pass. The generated inventory now contains one and
  only one actionable P1 row, `IN-10`.
- **Scope:** Re-read pinned Ghostty mouse/semantic selection behavior; inventory
  current native pointer modifier transport, product mouse arbitration,
  viewport/stable-anchor selection, shell integration markers, PTY mode and
  bounded write queues; define exact Option-click movement and semantic
  prompt/output gestures; implement them without bypassing existing focus,
  mouse-report, paste, or selection owners; add unit, native/product-runtime,
  documentation, matrix, and generated evidence.
- **Out of scope:** Drag/drop, Services, Quick Look, arbitrary shell command
  parsing, shell-specific command text retention, public accessibility
  automation, generic `dart_appkit` terminal policy, Apple notarization,
  Intel-host evidence, and duration-only soak.
- **Dependencies:** AppKit event protocol v15 modifier/button coordinates;
  `TerminalMouseRouter` and native view gesture ownership; canonical grid and
  viewport coordinate conversion; `TerminalSelectionGestureController` and
  content-free `TerminalSemanticRangeSnapshot`; existing OSC 133 shell
  integration; focused-pane PTY output queue and runtime display scenario.
- **Completion conditions:** Option-click on a focused primary-screen shell
  emits one bounded, mode-aware cursor movement without changing canonical
  cells or duplicating local selection/mouse reports; stale/out-of-grid,
  alternate-screen, active mouse-report, unsafe distance, and unavailable
  targets fail closed. Semantic prompt/output selection resolves only current
  retained stable ranges, distinguishes prompt/input/output boundaries, handles
  history/reflow/wide cells, and becomes the ordinary non-mutating Metal local
  selection with exact copy text. Native/product JIT/AOT evidence proves focus,
  arbitration, exact PTY bytes, selection pixels, cleanup, and zero owner leak;
  `IN-10` and the generated inventory close only after all checks pass.
- **Verification approach:** Inventory before splitting or coding; document
  exact choices and failures here; run focused mouse/selection/semantic/native
  tests, Developer JIT and Release AOT product acceptance, generated freshness,
  formatter/analyzer, exact full repository gate, and the adjacent generic
  library audit. Commit every ordered subtask separately if the implementation
  is divided.
- 2026-09-14: The first resumed inventory command used the misspelled working
  directory `/Users/remstehenden/dart/dart_terminal` and was rejected before a
  process or filesystem mutation existed. The same read-only inventory was
  rerun from the repository root; no source consequence remains.
- 2026-09-14: The clean pinned Ghostty checkout at exact revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4` now supplies direct behavior
  evidence. `Surface.zig` invokes prompt clicking only after an undragged left
  release with no selection, requires click support, a prompt-resident cursor,
  and a click no earlier than the current prompt. `Screen.zig` counts only OSC
  133 input cells over one logical soft-wrapped line and returns left/right
  movements; application-cursor mode selects `SS3 D/C`, otherwise `CSI D/C`.
  The newer `click_events=1/2` path emits one SGR press with absolute/relative
  coordinates, but the product's deliberately privacy-safe OSC 133 subset does
  not currently retain those producer options. The roadmap's Option-click
  contract will therefore use the bounded arrow-key subset and must not invent
  unsupported shell-event negotiation.
- 2026-09-14: Pinned semantic selection evidence is independent of prompt
  clicking. Ordinary single/double/triple click remains cell/word/line, while
  Control-or-Super triple-click selects the complete semantic output block;
  dragging expands only across other output blocks. Prompt and input cells do
  not become output selection. The product already transports native Option,
  Control, and Command/Super modifier bits through `TerminalMouseRouter`, owns
  stable end-exclusive semantic prompt/command/output ranges, and has a single
  viewport selection owner, but the gesture controller currently discards all
  modifiers and maps every triple-click to logical-line selection.
- **Ordered subtasks and individual completion conditions:**
  1. **Bounded semantic click and cursor-movement core.** Add content-free
     retained-range queries that resolve the semantic segment under one
     viewport cell, clamp ordinary logical-line selection to prompt/input/
     output boundaries, select a complete output block, and combine same-kind
     blocks without exposing text. Add a primary/live-input cursor movement
     plan over stable logical anchors with a hard encoded-byte-derived movement
     cap and explicit rejection reasons. Unit tests must cover prompt/input/
     output separation, hard/soft wrapping, history/reflow/wide cells, stale
     anchors, alternate/history viewport, both directions, no-op, and bounds.
     This child does not activate a native gesture or send PTY bytes.
  2. **Native Option-click and semantic selection gesture integration.** Add a
     single terminal-local gesture arbiter downstream of the existing generic
     AppKit event decoder. An undragged exact-Option left click may encode one
     accepted movement plan as ordinary/application-cursor left/right bytes;
     all other gestures retain mouse-report/Shift override ownership. Ordinary
     triple-click uses the clamped semantic line, and Control-or-Command
     triple-click plus drag selects whole output blocks. Tests must prove
     exactly-once routing, selection clearing/rendering, mode bytes, drag and
     stale cancellation, reporting exclusion, the 256-byte input bound, and
     cleanup without any `dart_appkit` change.
  3. **Dual-runtime evidence, documentation/matrix update, and parent
     decision.** Drive OSC 133, native modifiers/click counts, exact PTY bytes,
     semantic selection pixels/copy text, reporting arbitration, and cleanup
     through the ordinary product in Developer JIT and Release AOT. Update the
     README/input reference and `IN-10`, regenerate the gap inventory and all
     dependent evidence, run the exact full repository gate and adjacent
     generic-library audit, then close only this child and parent when every
     preceding completion condition passes.
- 2026-09-14: The pinned source SHA-256 identities for this child are
  `Surface.zig`
  `2095e33bc2d4c914275076f031bd512d3d988e6036e9c5124bf3a08c62aaa136`,
  `Screen.zig`
  `6f72245f66e38afc3222bee6d108f79509dfeb3025f01c0e906eabbc66e6c5d9`,
  `SelectionGesture.zig`
  `f40dcfc77bf10cc68116612b2e3386dd00779b66cee35a9ad585884708e8ecca`,
  and `semantic_prompt.zig`
  `04935466b4fd8b9e0e41e7d69bb72fc6ff6141111d9274d8bda927dcb41488ff`.
  A combined hash/inventory read was launched from the Ghostty checkout, so its
  repository-relative `compatibility/ghostty_p0_p1_gap_inventory.json` lookup
  failed and stopped the later read-only clauses. Rerunning from Dart Terminal
  confirms `IN-10` alone is `actionable-p1` with gap
  `option-click-and-semantic-selection`; no mutation resulted.
- 2026-09-14: Product input writes have a strict 256-byte per-event cap. Both
  normal `CSI D/C` and application-cursor `SS3 D/C` arrows are three bytes, so
  the click plan must cap one atomic movement at 85 arrows (255 bytes). The
  active viewport already exposes stable one-cell anchors that normalize wide
  continuations, live-grid cursor anchors independent of history navigation,
  and retained-range availability after reflow/eviction. These are sufficient
  for the first child without adding cell-semantic storage or changing the
  generic AppKit wire protocol.
- 2026-09-14: A cleanup patch initially used context that assumed a duplicated
  semantic-kind parameter shown by overlapping inspection output. The actual
  file contained one parameter, so `apply_patch` rejected the patch before any
  write. A scoped reread confirmed the implementation and a later minimal patch
  removed only the genuinely unused resolved-range payload.
- 2026-09-14: Sandboxed `dart format` formatted the changed sources but then
  could not update the user telemetry timestamp; sandboxed focused execution
  also failed while the Metal build hook tried to create Clang module-cache
  files under `~/.cache`. The test was rerun with the repository's established
  external build-cache permission. Its first compile found the intentionally
  exhaustive product-observation switch missing the new `semanticOutput` unit;
  adding the observation case restored exhaustive handling. The next run found
  that a semantic output beginning with the shell's CR/LF boundary selected a
  leading newline. Pinned `selectOutput` begins at the first output cell and
  trims the trailing unwritten area, so the resolver now uses the first and
  last retained content cells inside the stable semantic range. The focused
  test then passed.
- 2026-09-14: The first child now exposes three content-free viewport
  operations: a logical-line selection intersected with its current retained
  prompt/input/output segment, a first-to-last-content-cell output-block
  selection, and a stable combination of two output selections that records
  reverse direction. No selected text is stored by these contracts; ordinary
  extraction and Metal projection remain the only consumers. A distinct
  `semanticOutput` unit makes exhaustive product observation possible without
  changing selection rendering.
- 2026-09-14: Prompt cursor planning requires primary ownership, bottom/live
  viewport, OSC 133 input state, the newest incomplete command range, and one
  shared stable logical-line identity for command start, cursor, and target.
  It rejects prompt cells, stale/unavailable anchors, history, alternate,
  different lines, and more than 85 movements; same-position clicks are an
  explicit silent result. The plan contains only direction/count and source
  generations. Native modifier arbitration and PTY byte emission remain
  intentionally absent until the second child.
- 2026-09-14: The non-writing formatter check was initially read as if it had
  applied its reported change. A direct formatter pass was then run once,
  followed by a non-writing check reporting seven files and zero changes. The
  final focused semantic test passes after formatting; the stable selection/
  search regression also passes. Coverage includes same-row prompt/input/
  output separation, two hard-line output blocks and reverse combination,
  reflow retention, soft-wrap, wide lead/continuation normalization, both
  cursor directions, no-op, 85/86 boundary, out-of-grid, unmarked input,
  alternate ownership, history navigation, and evicted-range rejection.
- 2026-09-14: The first exact full gate passed PTY, renderer, AppleScript,
  App Intents, generated references, localization, and privacy checks, then
  correctly rejected the stale Phase 7 AppKit acceptance source hashes.
  Regenerating only `test/corpus/appkit/phase7_acceptance_v1.json` restored its
  deterministic four-criterion evidence. The resumed gate passed through the
  application, terminfo, shell-integration, and differential gates, then
  correctly rejected the stale Ghostty gap inventory hash. Regenerating only
  `compatibility/ghostty_p0_p1_gap_inventory.json` retains 102 rows, 96
  accepted, zero actionable P0, one actionable P1, and zero silent
  misbehavior; `IN-10` deliberately remains actionable until native/runtime
  integration is complete.
- 2026-09-14: The exact full gate passes in the final first-child state:
  deterministic generated evidence is fresh, formatting covers 334 files with
  zero changes, analysis reports no issues, the complete aggregate Dart suite
  ends with `dart_terminal tests passed`, and the Ghostty inventory remains
  intentionally at 96 accepted / one actionable P1. `git diff --check` is
  clean. The adjacent `/Users/remi/dart/dart_appkit` worktree is clean; its
  tracked path inventory has no terminal-named path and its tracked executable
  source/script/manifest/Makefile grep has zero case-insensitive `terminal`
  match. Apple notarization and duration-only campaigns remain skipped as
  authorized. The bounded semantic click/cursor-movement core child satisfies
  all recorded completion conditions; native gesture activation is the next
  ordered child.

## Current P1 child — remaining overlays and P3 conversion

- **Purpose:** Close the remaining renderer parity row by composing terminal
  image, search, and inspector overlays through the existing bounded screen and
  Metal ownership model, and by making extended-color input reach the renderer
  through one explicit sRGB conversion policy.
- **Background:** `REN-08` currently accepts the viewport hyperlink hit test
  and non-mutating underline overlay, but explicitly leaves image, search,
  inspector, and Display P3/sRGB behavior open. The synthetic-cell item is now
  committed, leaving this and the following input item as the two actionable
  P1 gaps.
- **Scope:** Re-read pinned Ghostty image/overlay/color evidence; inventory
  existing Kitty image placement, search, inspector, palette, reference
  renderer, packed Metal instances, shaders, diagnostics/privacy, and product
  runtime acceptance; define bounded non-mutating overlay and color contracts;
  implement and verify each independent responsibility in roadmap order;
  update public/matrix/generated evidence only after observed closure.
- **Out of scope:** Option-click cursor positioning, semantic prompt/output
  selection, arbitrary image protocols beyond the accepted Kitty subset,
  transparency/background blur, HDR/wide-gamut output promises, duration-only
  campaigns, Apple notarization, and every `terminal`-named file/symbol/content
  addition to generic `dart_appkit`.
- **Dependencies:** Existing bounded Kitty image storage and compositor image
  layers; search model and inspector capture/export privacy contract; hyperlink,
  selection, cursor, preedit, and synthetic-cell overlays; CPU reference and
  real Metal golden/readback infrastructure; packed instance/shader ABI;
  renderer resource generations; pinned Ghostty revision `d4d8f62`; `REN-08`
  and the current 95-accepted/two-actionable gap inventory.
- **Completion conditions:** Every accepted overlay has a single bounded state
  owner, deterministic viewport projection and documented layer order; no
  overlay mutates canonical terminal cells or leaks captured text; P3 input is
  converted to the documented sRGB representation before blending with exact
  alpha semantics; 1x/2x CPU/Metal and both product runtime modes cover the
  feature; generated evidence is fresh; no silent renderer gap remains; the
  adjacent `dart_appkit` worktree stays clean and generic.
- **Verification approach:** Inventory before choosing the split; record all
  decisions and failed attempts here; add ordered roadmap subtasks with isolated
  completion gates; for each subtask run focused unit/native/Metal tests,
  formatting and analysis, then the exact repository gate; commit it alone and
  re-read the roadmap before advancing. Runtime/golden and documentation
  closure are deferred to the final subtask so earlier implementation children
  do not claim matrix acceptance prematurely.
- **Ordered subtasks and individual completion conditions:**
  1. **Bounded overlay projection and P3-to-sRGB color contract.** Add immutable
     typed grid-overlay spans/projections with an aggregate hard cap, explicit
     precedence, truncation metadata, and no text payload; add a straight-alpha
     RGBA8 color-space value that converts Display P3 to canonical clipped sRGB
     while leaving sRGB and alpha exact. Unit tests must cover bounds,
     immutability, ordering/precedence metadata, published conversion vectors,
     clipping, and alpha preservation. No compositor or product activation is
     claimed in this child.
  2. **Three-band Kitty image layer ordering.** Complete the already-bounded
     image path by separating extreme-negative under-background placements,
     ordinary negative under-text placements, and nonnegative over-text
     placements without changing store/protocol ownership. CPU/native order,
     clipping, z/generation ordering, atlas pins, and failure behavior must pass
     at 1x/2x.
  3. **Search-result projection and Metal highlight overlay.** Project bounded
     stable search ranges into the current viewport, distinguish the selected
     match, coalesce overlap deterministically, reject/stale-drop invalid input,
     and compose non-mutating fills/borders without changing terminal cells or
     PTY input.
  4. **Privacy-safe inspector overlay.** Derive only contiguous hyperlink and
     semantic prompt/input geometry from current metadata while the existing
     inspector owner is active; skip semantic output, retain no text, clear on
     focus/close/stale generation, and compose the bounded top overlay with
     accessible differentiation.
  5. **Canonical sRGB and alpha-blending parity.** Convert tagged Display P3
     input once before packing/upload, use sRGB texture/target decoding and
     linear source-over blending in Metal, and make the CPU oracle exactly model
     the same straight-alpha contract. Native ABI/source audits and color-vector,
     translucent-solid/mask/image, and 1x/2x readback tests must pass.
  6. **Runtime evidence, documentation/matrix update, and parent decision.**
     Exercise all three image bands plus search/inspector overlays and P3 input
     through the real product in Developer JIT and Release AOT; add checked-in
     1x/2x evidence, update README/rendering reference and `REN-08`, regenerate
     dependent reports, pass the exact full gate and adjacent-library audit,
     then close only this parent if every preceding child is complete.

### Current child — three-band Kitty image layer ordering

- **Purpose:** Preserve Ghostty's accepted Kitty z semantics by placing extreme
  negative images below cell backgrounds, ordinary negative images below text,
  and nonnegative images above text in both the deterministic CPU oracle and
  the real Metal frame.
- **Background:** The store and viewport already preserve signed 32-bit z and
  sort placements by z then immutable placement generation, but both renderers
  currently collapse that value to `z < 0` versus `z >= 0`. The pinned Ghostty
  boundary is `minInt(i32) / 2`, or `-0x40000000`.
- **Scope:** Add one shared three-band classification to immutable viewport
  placements; add a below-background reference layer; extend the terminal Metal
  instance vocabulary and native validation/shader sampling for three ordered
  color-atlas image kinds; retain all visible image tiles through the existing
  build/submission leases; cover exact boundaries, stable z/generation order,
  clipping, atlas pins, native acceptance, and pixels at 1x/2x.
- **Out of scope:** Kitty store/parser/decode/animation semantics, search and
  inspector projection, color-space/alpha changes, file/shared-memory image
  transport, virtual/relative placement, runtime screenshots, matrix claims,
  and any change to generic `dart_appkit`.
- **Dependencies:** Signed z validation in the Kitty command/store path;
  generation-bound viewport snapshots; color atlas and dirty upload bridge;
  terminal renderer frame ABI v1; CPU reference layer grouping; existing 64
  image/256 placement and viewport clipping bounds.
- **Completion conditions:** `z < -0x40000000`,
  `-0x40000000 <= z < 0`, and `z >= 0` map to distinct ordered bands; equal-z
  placements retain generation order; CPU and Metal produce the same visible
  layer result at 1x/2x; offscreen placements allocate no tile; every encoded
  tile remains submission-pinned; malformed/order-violating native input still
  fails closed; all focused and exact repository gates pass.
- **Verification approach:** Add contract, reference, compositor, package, and
  native capability assertions; run focused Dart/native tests at both scales;
  run format/analyze and the exact repository gate; audit the adjacent generic
  library; record results before changing only this roadmap child to complete.
- 2026-09-14: The existing frame clear supplies the default background before
  all instances. Per-cell non-default backgrounds are explicit solid instances,
  so an extreme-negative color-atlas image can be drawn after the clear but
  before those solids. The current renderer ABI treats every color image as a
  normal color glyph (kind 4), and both Dart and native validators infer layer
  order from that kind. Distinct image kinds are therefore required; merely
  reordering the product list would be rejected natively and would not preserve
  fail-closed direct-FFI validation.
- 2026-09-14: An initial focused format/analyze command formatted the three
  changed Dart implementation files, then analysis could not update the
  sandbox-external Dart telemetry-session timestamp and exited before analyzing
  sources. This was an environment write restriction, not an analyzer finding;
  subsequent focused commands use the accepted CI/analytics-suppressed
  environment outside that restriction.
- 2026-09-14: The first analyzer run with the accepted environment found 15
  test-surface errors, all in the new CPU test: it had referred to private
  fixture helpers from another library and the new public layer enum was not in
  the package's explicit `show` export. The product implementation files had no
  analyzer finding. The test now owns its small store/place helpers and the
  enum is added to the existing viewport export; private test helpers are not
  made public merely for reuse.
- 2026-09-14: A direct `clang-format -i` attempt stopped before any file change
  because the available executable is Chromium's checkout-discovery wrapper
  and this repository is not a Chromium tree. The subsequent Dart commands in
  that shell chain therefore did not run. Native edits remain the small manual
  `apply_patch` diff and are checked with `git diff --check`; the repository's
  own full gate remains the authoritative native formatting/build check.
- 2026-09-14: After clean focused analysis, the renderer-package test passed,
  but the first CPU three-band pixel assertion failed at 1x and stopped the
  chained run before the screen compositor test. The ordering/classification
  assertions had passed. The pixel assertion is being reduced by reporting the
  three exact output pixels; no expected value will be relaxed without locating
  the layer or fixture error.
- 2026-09-14: Exact output was red/green/red instead of blue/green/red. The
  renderer order was correct: all three placements had resolved to column zero
  because the test's otherwise-empty logical line had no distinct cell anchors,
  so the final above-text image legitimately covered the first pixel. Seeding
  the fixture with bounded visible cells before taking anchors fixed the
  geometry without changing expected colors. The CPU test then passed at both
  1x and 2x with the original blue/green/red expectation.
- 2026-09-14: Focused Dart analysis is clean. The renderer package contract,
  CPU reference compositor, and screen Metal compositor tests pass; the latter
  renders all three image bands through the real native readback at both 1x and
  2x and retains all three color-atlas entries in the scheduled frame. The
  focused native capability target rebuilt the Metal shader and Objective-C
  plugin/test with warnings as errors, accepted all nine visual kinds in exact
  order, preserved readback pixels, and continued to reject out-of-order,
  malformed, out-of-range, and stale frames.
- 2026-09-14: The first exact full gate after implementation passed every
  native/package/compatibility/differential/application/shell check reached,
  then correctly failed at `GHOSTTY_P0_P1_GAP_INVENTORY_FAIL` because the
  checked-in inventory hashes renderer evidence changed by this child. This is
  an expected freshness failure, not an implementation failure; the dependent
  Ghostty reports must be regenerated in their declared order before rerunning
  the gate.
- 2026-09-14: The canonical Ghostty generator changed only five evidence
  digests for the compositor, compositor test, native header/plugin, and native
  capability test. The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed: the native
  renderer contract and shader build passed, all package/root analyses reported
  no issues, 334 Dart files were already formatted, every generated-evidence
  check was fresh, the inventory remained 95 accepted with the same two parent
  P1 gaps, and aggregate/security tests ended with `dart_terminal tests passed`.
- 2026-09-14: Final adjacent-library audit found a clean
  `/Users/remi/dart/dart_appkit` worktree, no tracked path containing
  `terminal`, and no terminal-specific content in its tracked native,
  `dart_appkit`, runtime, script, example, tool, or test source. This child made
  no adjacent-library change. `git diff --check` is clean.

### Current child — search-result projection and Metal highlight overlay

- **Purpose:** Make the existing bounded exact-search result visible without
  mutating canonical terminal cells, selection state, PTY input, or retained
  query/text content.
- **Background:** Search already returns at most 1,000 immutable matches over
  stable end-exclusive logical anchors with scan/match truncation metadata.
  Selection already projects the same range type into the current navigated
  viewport, while the compositor has only selection/preedit/bell fills. The
  new metadata-only overlay contract has explicit normal-then-selected search
  precedence but is not yet produced or consumed.
- **Scope:** Add a bounded projector from `TerminalSearchResult` to current
  viewport overlay spans; prioritize and visually distinguish one selected
  match; coalesce overlapping spans within each kind; mark scan/match/cap/stale
  drops as truncated; accept monotonic content-free search generations on the
  live surface; recompute on viewport/content changes; render normal/selected
  fills plus a selected outline through ordinary solid Metal instances; expose
  only counts/generations in snapshots.
- **Out of scope:** Search query editing/UI/menu commands, replacement,
  case/regex/fuzzy search, inspector overlays, P3/linear blending, accessibility
  announcement copy, runtime screenshots, feature-matrix acceptance, and any
  `dart_appkit` change.
- **Dependencies:** Stable `TerminalSelectionRange` anchors and
  `TerminalViewport.projectSelection`; `TerminalSearchResult` hard caps;
  `TerminalGridOverlayProjection` 4,096-span cap and paint precedence; live
  newest-frame redraw scheduling; existing selection/decorations Metal layers.
- **Completion conditions:** Selected geometry is retained before ordinary
  matches under cap pressure but paints after ordinary geometry; overlaps
  coalesce deterministically; invalid selected indexes fail before state change;
  unavailable anchors are dropped and reported via truncation; viewport changes
  reproject without retaining text; compositor rejects out-of-grid or unsupported
  overlay kinds; 1x/2x real Metal geometry/pixels and live monotonic generation,
  clear, stale-drop, and diagnostics counts pass; exact full gate passes.
- **Verification approach:** Extend the overlay contract test for projection
  bounds, overlap, selection priority, scrolling, stale anchors, and invalid
  indexes; add compositor 1x/2x instance/pixel tests; add live-surface state and
  redraw tests; run focused format/analyze/tests followed by the exact gate and
  adjacent-library audit; record failures before marking only this child done.
- 2026-09-14: No product code currently calls terminal document search; only
  the core API and tests do. This child therefore introduces a renderer/live
  surface publication boundary but does not invent a query UI ahead of the
  final runtime-evidence child. The projector will use the current viewport
  generation as its source identity, allowing scroll/reflow reprojection while
  stable anchors remain valid and stale-dropping only anchors that have actually
  been evicted or switched to another screen.
- 2026-09-14: Initial focused overlay and core-search tests passed, while the
  1x compositor geometry assertion failed before pixel comparison. The test had
  incorrectly assumed `round(cellWidth) * 2`; production correctly rounds each
  grid boundary independently, so a fractional CoreText cell width makes that
  assumption differ by a pixel. The assertion now derives the first and second
  boundaries independently, matching the canonical compositor rule rather than
  weakening the geometry check.
- 2026-09-14: After the fixture correction, focused analysis and all three
  focused suites pass. Contract coverage fixes four overlapping matches into
  one normal span plus one selected span, reserves the selected span under a
  one-span cap, rejects invalid selection indexes without mutation, rejects
  conflicting/regressed live generations, clears on a newer generation, and
  stale-drops a result after its source content changes. Existing exact-search
  tests remain green. The compositor emits normal then selected fills and four
  selected outline edges at independently rounded grid boundaries; real Metal
  readback distinguishes them at both 1x and 2x, and unsupported kinds or
  out-of-grid spans fail before a frame escapes.
- 2026-09-14: The first exact full gate passed every preceding native,
  compatibility, differential, application, terminfo, and shell check, then
  stopped at the expected stale Ghostty inventory because its hashed compositor
  evidence changed. Compatibility regression coverage remained fresh. The
  Ghostty report therefore needs only its canonical regeneration before the
  final rerun.
- 2026-09-14: Canonical Ghostty regeneration updated only the expected hashed
  renderer evidence. The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed with 334 files
  already formatted, no analysis issues, fresh generated reports, all native
  capability and Dart suites, security stress, and the final aggregate marker.
  The inventory remains 95 accepted and two parent P1 gaps because matrix-level
  acceptance is intentionally deferred to the runtime-evidence child.
- 2026-09-14: Final adjacent audit found no `dart_appkit` worktree change, no
  tracked terminal-named path, and no terminal-specific content in its tracked
  generic source/test/tool surfaces. `git diff --check` is clean. The search
  owner retains only stable ranges, scalar/count flags, one selected index, and
  generations; query and terminal text never enter the overlay or diagnostics.

### Current child — privacy-safe inspector overlay

- **Purpose:** Show the focused pane's current hyperlink and semantic
  prompt/input geometry while the existing Terminal Inspector owns capture,
  without retaining terminal text, URL targets, command content, or parser
  payload in renderer state.
- **Background:** The diagnostics presenter already owns exactly one read-only
  Inspector window, follows hierarchy focus by stopping the previous parser
  capture before starting the next, and clears capture when unavailable or
  closed. Visible cells already expose integer hyperlink IDs, while the bounded
  semantic tracker exposes stable prompt/command/output ranges. The generic
  grid-overlay contract reserves three inspector kinds, but neither the live
  surface nor compositor currently consumes them.
- **Scope:** Add a bounded projector that groups contiguous visible hyperlink
  IDs and projects prompt/command stable ranges while excluding output; add a
  monotonic content-free activation state on each live surface; connect that
  state to the existing diagnostics focus/capture lifecycle; clear the old
  surface before focus handoff and clear on unavailable/close/dispose; reproject
  on viewport or semantic generation changes; combine search and inspector
  projections without exceeding the shared 4,096-span cap; render an
  above-text differentiated outline/underline vocabulary; expose only
  generations, counts, kinds, and truncation in diagnostic snapshots.
- **Out of scope:** Inspector capture/export contents, parser event taxonomy,
  hyperlink navigation/URL storage, semantic output highlighting, search UI,
  P3/linear blending, runtime evidence or matrix acceptance, arbitrary debug
  painting, and every change to generic `dart_appkit`.
- **Dependencies:** `TerminalDiagnosticsPresenter` focus and close ownership;
  `TerminalDiagnosticsFocusTarget`; viewport hyperlink metadata and stable
  selection projection; bounded semantic snapshots; grid-overlay precedence and
  cap; existing live-surface redraw scheduling and Metal decoration instances.
- **Completion conditions:** Only the captured focused pane publishes an
  inspector overlay; focus handoff and close clear the former pane before any
  new publication; semantic output is absent; same-ID hyperlink runs and
  overlapping/adjacent same-kind semantic spans coalesce deterministically;
  stale or unavailable geometry is dropped and marked truncated; scan and span
  work is hard-bounded; combined overlay remains capped; compositor produces
  visibly distinct hyperlink/prompt/input top decorations at 1x/2x and honors
  increase-contrast/differentiate-without-color; state retains no text/URL;
  focused tests and the exact repository gate pass.
- **Verification approach:** Extend overlay contract tests for grouping,
  projection, output exclusion, truncation, stale/monotonic/clear behavior, and
  combined-cap precedence; add compositor real-Metal 1x/2x geometry/readback
  assertions; extend diagnostics product acceptance for open, focus handoff,
  metadata-only snapshot counts, and close clearing; run focused format,
  analysis, and tests, then regenerate declared evidence if stale, run the exact
  full gate, audit the adjacent generic library, and record all results here.
- 2026-09-14: Targeted inventory confirms `TerminalViewport.hyperlinkAt`
  resolves current visible history or active-screen cell metadata without
  resolving the hyperlink table's URI. `TerminalSemanticRangeSnapshot` is
  bounded to 4,096 ranges and carries generation plus unavailable/evicted/limit
  truncation metadata; its `command` kind is the shell input range required by
  this child, while `output` must be skipped. Selection projection already
  drops anchors that cannot resolve in the current viewport.
- 2026-09-14: The diagnostics presenter is the correct activation authority:
  `_synchronizeTarget` stops the old capture before starting the new one,
  `synchronizeFocus` stops on unavailable focus, and `_close` stops capture
  before disposing its native owners. The focus target will therefore carry
  product callbacks that enable/refresh and clear its own live surface; the
  presenter will invoke them in the same order as parser capture. This avoids a
  second inspector owner in the renderer and makes focus/close clearing
  deterministic.
- 2026-09-14: The compositor currently receives one search-only projection and
  rejects all inspector kinds. Search fills are intentionally beneath glyphs;
  inspector geometry must instead add decoration instances after glyph/image
  construction so it remains a top overlay without altering cells or text.
- 2026-09-14: The first focused format pass changed only four of the eight Dart
  files. Static analysis then found one test-only constructor error: the
  accessibility value's named flags belong to its primary constructor, while
  the `standard` constructor accepts no overrides. The fixture will use the
  explicit three-flag constructor; no production accessibility API needs to be
  widened.
- 2026-09-14: After that correction, focused analysis passed. The first
  sandboxed test run stopped before test code because Metal's compiler could
  not write its user clang module cache; the required rerun with normal cache
  access passed the overlay contract and native-hierarchy suites, then the real
  Metal inspector pixel assertion failed at 1x. Instance count/order/color
  assertions had already passed. The pixel fixture sampled the viewport's last
  allocated row, which may be one pixel below the independently rounded cell
  boundary when `ceil` sizes the viewport; exact pixels are being inspected
  before correcting only that sampling geometry.
- 2026-09-14: The corrected focused suites all pass, including exact inspector
  decoration readback at 1x and 2x. The first Developer JIT diagnostics product
  run then reached the Inspector and processed the private OSC 8 command, but
  timed out on the newly combined hyperlink-plus-semantic-input predicate. Its
  own machine output records `shell=unknown integrated=false`; this fixture
  deliberately has no semantic shell integration, so it cannot produce prompt
  or input ranges. Product acceptance will assert the explicitly emitted OSC 8
  hyperlink plus activation/focus/close clearing; prompt/input classification
  and output exclusion remain covered by the direct parser/projector contract.
- 2026-09-14: The second Developer JIT run completed the in-app diagnostics
  assertions and emitted the strengthened `overlay=true` acceptance marker,
  but the outer smoke verifier rejected it because its anchored regular
  expression still expected `inspector=true singleton=true` adjacently. The
  verifier must include the new explicit overlay field; this is evidence-schema
  freshness, not a runtime failure or a reason to remove the new assertion.
- 2026-09-14: With the smoke marker synchronized, both real product modes pass:
  Developer JIT reports `RUNTIME_DIAGNOSTICS_INTEGRATION_PASS` with two
  diagnostics and two incident exports in 1,829 ms, and Release AOT reports the
  same owned results in 958 ms. The exercised path opens one Inspector, derives
  an OSC 8 overlay without publishing its URI, clears the old surface before a
  pane focus handoff, activates the new surface, clears on close, restores
  terminal focus, and releases every native/parser/PTY owner.
- 2026-09-14: Final focused format and analysis are clean. Overlay contract,
  diagnostics presenter lifecycle, and real Metal compositor suites pass; the
  latter verifies 1x/2x colored hyperlink/prompt/input geometry plus opaque
  thick background-contrasting geometry under Increase Contrast. The
  diagnostics privacy audit passes with 190 schema keys, seven owners, and 11
  top-level keys; the new live snapshot contains counts and generations only.
- 2026-09-14: The first exact full repository gate passed native PTY, renderer,
  AppleScript, App Intents, generated parser/config/keybinding/localization, and
  diagnostics privacy checks, then correctly stopped at the Phase 7 AppKit
  acceptance freshness guard. This child changed the product application,
  diagnostics presenter lifecycle test, and runtime smoke marker hashed by that
  inventory. Its canonical generator must run before continuing the gate; no
  functional test failure remains at this point.
- 2026-09-14: Canonical Phase 7 regeneration changed only its expected source
  identities. The next exact gate stopped early in the unchanged
  `dart_pty_macos` package: `live Dart child cannot steal native PTY completion`
  observed no matching element, while every preceding PTY case passed. This is
  outside the Inspector change set and is consistent with the previously
  observed timing-sensitive test; the exact gate will be rerun unchanged before
  treating it as a blocker or modifying PTY behavior.
- 2026-09-14: The unchanged rerun passed that PTY case and every native,
  analysis, generated AppKit/compatibility/differential/application, terminfo,
  and shell-integration gate through the final Ghostty check. That check then
  reported the expected stale inventory because this child changes hashed
  overlay/compositor/application evidence. The canonical Ghostty generator is
  now the only required freshness update before the final exact rerun.
- 2026-09-14: Ghostty regeneration changed only the four expected hashes for
  the screen compositor, compositor test, product application, and runtime
  smoke verifier. The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passes in the reviewed
  state: all native capability packages and generated evidence are fresh, 334
  Dart files require no formatting changes, package/root analysis reports no
  issues, Ghostty remains 95 accepted with two parent P1 gaps, all security and
  aggregate suites pass, and the run ends with `dart_terminal tests passed`.
- 2026-09-14: Final adjacent-library audit reports a clean
  `/Users/remi/dart/dart_appkit` worktree, no tracked path containing
  `terminal`, and no terminal-specific string in tracked Dart/native/script or
  manifest code. No generic-library file changed. `git diff --check` is clean.
  Apple notarization and duration-only soak were not required for this child.
- 2026-09-14: The first staging attempt was blocked before changing the index
  because the workspace sandbox exposes `.git/index.lock` read-only. Source and
  validation state are intact; staging/commit must be retried with repository
  metadata write permission rather than changing the worktree.

### Current child — canonical sRGB and alpha-blending parity

- **Purpose:** Make the renderer's declared straight-alpha sRGB contract true
  at every CPU/native/Metal boundary, while accepting explicitly tagged Display
  P3 input through exactly one clipped conversion before packing or upload.
- **Background:** Terminal palette, OSC colors, glyph masks, reference images,
  and Kitty RGBA bytes are currently treated as sRGB values, but the native
  color atlas, offscreen target, and `MTKView` use untagged `RGBA8Unorm`.
  Fragment output is therefore blended in encoded component space. The first
  overlay child added reviewed P3-to-sRGB conversion values, but no renderer
  producer consumes them yet and the CPU oracle must be audited against the
  eventual Metal source-over semantics.
- **Scope:** Inventory every color/bitmap producer and pixel-format creation;
  introduce one explicit canonical-sRGB packing/upload boundary for tagged
  colors and buffers; switch sampled color resources and render targets to sRGB
  formats where required for linear-light fixed-function blending; preserve
  alpha-mask semantics and straight-alpha public inputs; align the CPU oracle's
  decode/blend/encode rounding with Metal; strengthen native fail-closed source
  and ABI audits; add exact conversion, translucent solid/mask/image, and
  overlapping-layer 1x/2x CPU/real-Metal tests.
- **Out of scope:** HDR or wide-gamut output, Display P3 framebuffer claims,
  ICC/profile negotiation, transparency/background blur, arbitrary image
  formats, runtime screenshots and matrix acceptance (next child), changes to
  generic `dart_appkit`, Apple notarization, and duration-only soak.
- **Dependencies:** `TerminalRenderColor` conversion contract; palette/style and
  Kitty upload paths; alpha/color atlas page ownership; packed Metal instance
  ABI; Objective-C++ renderer texture/target setup and blend descriptor; Metal
  shaders; deterministic reference compositor and golden/readback fixtures;
  existing native capability/source audits.
- **Completion conditions:** All accepted RGBA inputs are straight alpha in
  canonical sRGB before native packing/upload; tagged P3 converts exactly once
  with alpha unchanged; sRGB resources decode before shader math and the sRGB
  destination encodes after linear source-over; alpha masks tint in the same
  space; CPU/reference output matches real Metal within an explicitly reviewed
  byte tolerance for translucent solid, mask, and image overlaps at 1x/2x;
  opaque pixels remain exact; malformed or ABI/source format drift fails
  closed; exact full gate and adjacent generic-library audit pass.
- **Verification approach:** Record the complete format/blend inventory before
  editing; add narrow conversion/packing tests first, then native format/source
  assertions and CPU/Metal pixel vectors; run focused native and Dart suites,
  format/analyze, the exact full gate, canonical evidence regeneration only when
  declared stale, and the adjacent `dart_appkit` tracked path/content audit.
- 2026-09-14: Pre-edit color inventory confirms one canonical public model:
  palette/default/OSC/style colors, packed Metal instance colors, reference
  colors, CoreText color glyph rasters, and Kitty-decoded RGBA are straight-alpha
  RGBA8 sRGB. Alpha glyph pages are coverage-only `R8Unorm`. Color glyph and
  Kitty pages share the color atlas and do not carry a runtime profile. The
  explicit `TerminalRenderColor`/buffer converter is the sole accepted tagged
  Display P3 input contract; no live terminal protocol claims that Kitty bytes
  are P3.
- 2026-09-14: Every native format creation was enumerated before editing. The
  packed pipeline attachment, color-atlas array, bound `MTKView`, and synchronous
  readback target are all `MTLPixelFormatRGBA8Unorm`; only the alpha atlas is
  `MTLPixelFormatR8Unorm`. Both presentation and readback passes convert packed
  clear bytes directly to normalized values. `TerminalShaders.metal` likewise
  forwards normalized packed RGB and sampled color-atlas RGB without transfer
  conversion. The blend descriptor correctly implements straight-alpha
  source-over (`sourceAlpha`/`oneMinusSourceAlpha` for RGB and
  `one`/`oneMinusSourceAlpha` for alpha), so changing the color resources to
  sRGB plus decoding packed/clear colors is sufficient to move blending into
  linear light without changing the packed ABI.
- 2026-09-14: The CPU reference renderer currently quantizes mask coverage into
  an 8-bit effective alpha and performs integer source-over on encoded channel
  bytes. Its reference-layer 1x/2x goldens and the real-Metal parity suite
  therefore encode the same gamma-space behavior. The new oracle will retain
  straight alpha and final RGBA8 storage, but calculate coverage and source-over
  in doubles after sRGB decode, unpremultiply by the resulting alpha, then sRGB
  encode and round once at storage. Real-Metal comparison already permits one
  byte of implementation rounding tolerance.
- 2026-09-14: CoreText color glyph rasterization is the remaining producer-side
  ambiguity: it creates a device RGB context while publishing bytes as sRGB.
  It will use an explicit named sRGB color space. The bound `CAMetalLayer` will
  also carry an explicit sRGB color space, while the public frame/instance
  layout and version remain unchanged because no field or interpretation of
  the already-declared sRGB byte contract changes.
- 2026-09-14: The first focused reference-test launch did not reach test code:
  the sandbox denied Dart's attempt to update
  `~/.dart-tool/dart-flutter-telemetry-session.json` despite `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true`. Formatting had completed successfully. This
  is an execution-environment write restriction, not a renderer failure; rerun
  the identical test with the already established test-command permission.
- 2026-09-14: The permitted focused reference run then reached the expected
  stale gamma-space assertion: 50% white mask coverage over opaque black is no
  longer encoded `0x80`; linear-light composition stores sRGB `0xbc`. This
  confirms the new path is active. Update the assertion as a reviewed semantic
  change and continue to the transparent-over-transparent vector.
- 2026-09-14: The next stale vector was the low-valued translucent bitmap:
  linear-light half blending maps encoded `(10,20,30)` over black to
  `(5,12,19)`, not the former encoded-space `(5,10,15)`. The reviewed
  straight-alpha transparent overlap is `(213,0,156,192)` for 50%-alpha red
  over 50%-alpha blue. Both expectations retain final sRGB encoding and round
  only the stored RGBA8 result.
- 2026-09-14: Focused reference tests pass after those reviewed vectors, and
  the canonical reference-layer 1x/2x fixtures were explicitly regenerated;
  their exact codec test passes. The first atlas test then correctly reported
  its checked-in text golden stale at `(18,11)`: expected gamma-space
  `0x383c41ff`, actual linear-light `0x737475ff`. Because the oracle is shared,
  regenerate the text, synthetic-cell, and Kitty reference golden families
  through their existing explicit writers before rerunning exact comparisons.
- 2026-09-14: Explicit golden writers regenerated reference layers, text atlas,
  synthetic cell glyphs, and Kitty static/animation families at 1x/2x. The
  animation fixtures were byte-stable; the other families changed only where
  translucent coverage or layers exercise the shared oracle. The first native
  test attempt stopped during Metal compilation because sandbox policy denied
  Clang's module cache under `~/.cache/clang`; no test ran and no source changed.
  Rerun the same bounded Make target with native build-cache permission.
- 2026-09-14: The permitted native build compiles the sRGB Metal shader and
  Objective-C implementation cleanly. Its two pixel assertions then report the
  expected stale gamma-space constants (`nine visual kinds` and unchanged
  color-atlas slice); all other native capability checks continue. Add bounded
  per-channel diagnostics to `PixelNear`, capture the actual sRGB bytes, and
  replace only those reviewed pixel vectors.
- 2026-09-14: A diagnostic-only attempt to force all `PixelNear` calls with
  boolean bitwise `&` was rejected at compile time by the repository's
  `-Wbitwise-instead-of-logical -Werror` policy. No executable ran. Preserve
  the useful packed-pixel diagnostic but invoke each check in a separate
  statement so every vector is observed without suppressing the warning.
- 2026-09-14: Warning-clean packed diagnostics captured the three changed
  native vectors: translucent blue `0x1414bdff`, translucent red
  `0xbd1414ff`, and the layered straight-alpha color-atlas sample
  `0x06f106ff`. Opaque background, decoration, and cursor vectors remain byte
  exact. These values are the sRGB encoding of linear-light Metal source-over;
  retain the existing one-byte tolerance and update both the base and
  post-atlas-generation assertions.
- 2026-09-14: The updated native capability suite passes, including explicit
  `RGBA8Unorm_sRGB`/`CAMetalLayer` color-space inspection and linear readback
  vectors. Root real-Metal parity then passes at both 1x and 2x within the
  existing one-byte tolerance; reference, codec, atlas/P3, synthetic-cell, and
  Kitty focused suites also pass with regenerated fixtures.
- 2026-09-14: A padded-row audit found that whole-buffer P3 conversion would
  incorrectly interpret reference-bitmap stride padding as pixels. The
  boundary now validates shape first, copies all bytes, and converts exactly
  `width * height` pixels by row while leaving padding untouched; the focused
  test uses a five-byte stride. A subsequent `dart format` formatted zero files
  but again exited nonzero only while touching the sandboxed telemetry-session
  file, so whitespace validation is rerun independently and tests use the
  established permitted environment.
- 2026-09-14: Root analysis is clean, and the strengthened focused Metal test
  passes a fail-closed native source audit plus a tagged Display P3 tile through
  atlas synchronization and real readback (`ff 77 00 ff`). The renderer-package
  analysis/build hook passed, after which its facade readback test exposed two
  remaining stale gamma-space constants (`0x880808ff`/`0x088808ff`); linear
  source-over of 50% red/green over `0x101010` is the reviewed
  `0xbc0909ff`/`0x09bc09ff` vector (with the existing one-byte GPU tolerance).
- 2026-09-14: The renderer package rerun passes clean analysis, build-hook
  asset validation, facade tests, and linear readback vectors. The first exact
  repository gate passed all native renderer and preceding checks, then stopped
  at `terminal-compatibility-regression-coverage-check` because its generated
  report hashes the deliberately changed renderer/golden evidence and is now
  stale. This is the expected freshness guard, not a behavioral failure;
  regenerate that canonical report with its dedicated Make target, review the
  diff, then rerun the exact gate from the start.
- 2026-09-14: Compatibility regression coverage regeneration changed only the
  recorded `README.md` digest. The second exact gate passed that freshness
  check and all intervening compatibility/differential/application evidence,
  then stopped at the later `ghostty-p0-p1-gap-inventory-check`: this report
  intentionally hashes the renderer sources, reference document, and golden
  corpus changed by this child. Regenerate it while retaining the still-open
  overlay runtime-evidence classification, review, and rerun the exact gate.
- 2026-09-14: Ghostty inventory regeneration changed only the expected digests
  for compatibility coverage, the rendering reference, atlas/native sources,
  and 1x/2x synthetic corpus; it deliberately retains two actionable P1 rows
  because runtime overlay acceptance is the next child. The final exact gate
  then passes every dependency/native/package/generated-evidence/distribution
  check, formats 334 files with zero changes, reports clean root/package
  analysis, passes all real-Metal and security/integration suites, and ends
  with `dart_terminal tests passed`.
- 2026-09-14: Final review confirms `git diff --check` is clean. The adjacent
  `/Users/remi/dart/dart_appkit` worktree is clean; no tracked path contains
  `terminal`, and the audited Dart/native/script/manifest code contains no
  terminal-specific string. This child did not change the generic dependency.
  Apple notarization and duration-only soak remain explicitly excluded. The
  canonical sRGB/linear-light parity child is complete; the next ordered work
  is the overlay/P3 1x/2x real-Metal runtime evidence and matrix-closure child.

### Current child — overlay/P3 runtime evidence and parent closure

- **Purpose:** Prove that all completed image/search/inspector/color children
  are connected through the ordinary product owner rather than only isolated
  contracts, then close `REN-08` and its roadmap parent without overstating
  unrelated semantic-selection work.
- **Background:** Three image bands, search and privacy-safe inspector
  projections, and canonical P3-to-sRGB linear-light Metal rendering now pass
  focused CPU/native tests. The checked-in Ghostty inventory intentionally
  still classifies `REN-08` as actionable until one bounded product scenario
  exercises these paths in Developer JIT and Release AOT and publishes reviewed
  1x/2x evidence.
- **Scope:** Inventory the existing runtime integration entrypoint and evidence
  generators; extend the smallest existing renderer/product acceptance
  scenario to create all three Kitty bands, active search and inspector spans,
  and an explicitly tagged P3 atlas input; verify accepted real-Metal frames at
  1x/2x with content-free counters/markers; run the same contract in Developer
  JIT and Release AOT; update rendering docs, README, `REN-08`, generated
  reports, and only this overlay parent; run exact full and adjacent-library
  gates.
- **Out of scope:** Option-click cursor positioning, semantic prompt/output
  selection gestures, HDR/P3 framebuffer output, arbitrary screenshots or
  captured terminal content, generic `dart_appkit` changes, Apple notarization,
  and duration-only soak.
- **Dependencies:** Product runtime smoke and evidence writers, live Metal
  surface/compositor ownership, Kitty image store/controller, bounded
  search/inspector overlay states, renderer metrics/diagnostics, DTGI codec,
  Ghostty gap inventory and compatibility coverage freshness gates.
- **Completion conditions:** One ordinary product scenario proves three image
  bands, both overlay producers, a tagged P3 input, accepted real-Metal output,
  exact 1x/2x scale identity, focus/close cleanup, and zero leaked PTY/renderer/
  atlas/native ownership in Developer JIT and Release AOT; evidence is bounded,
  checked in, content-free, and freshness-checked; `REN-08` is accepted; all six
  children and the overlay/P3 parent are checked; exact full gate and adjacent
  generic-library audit pass.
- **Verification approach:** Preserve existing runtime markers unless a new
  content-free field is necessary; add source/negative tests before evidence
  generation; run focused scenario tests, Developer JIT, Release AOT, generated
  report checks, format/analyze, exact `make test`, `git diff --check`, and the
  tracked path/content audit for `/Users/remi/dart/dart_appkit`.
- 2026-09-14: Previous child committed as `2a9f2a9` (`Use linear-light sRGB
  rendering`). The post-commit worktree is clean. ROADMAP reread confirms this
  runtime/matrix child is the first unchecked item; Option-click/semantic
  selection remains the next independent P1 task and must not be included.
- 2026-09-14: Runtime inventory found the ordinary terminal-display scenario
  already drives Kitty multipart RGBA/PNG, scrolling/history, erase/delete,
  animation, eviction, atlas cleanup, and accepted Metal frames, but its two
  initial placements use only `z=-1` and `z=1`. It must add the exact
  extreme-negative threshold band and update the later image/placement counts
  without weakening cleanup checks. The same scenario already exposes
  content-free live-surface search counters but never calls
  `updateSearchResults`.
- 2026-09-14: The diagnostics product scenario already proves inspector
  activation, nonzero hyperlink/prompt/input overlay geometry, focus handoff,
  close clear, zero PTY writes, two-session cleanup, and zero text-client/native
  handles in both runtime modes. It should remain the inspector authority
  rather than bypassing its presenter from the display scenario. No current
  runtime scenario exercises a tagged Display P3 admission; this belongs in a
  small bounded real-Metal color probe inside the ordinary product process
  because Kitty protocol bytes themselves are defined as sRGB.
- 2026-09-14: Existing 1x/2x goldens separately cover three image bands and
  other reference layers, while search and inspector real-Metal tests are
  transient only. Add one compact `overlay-color` DTGI pair that combines all
  three image layers, normal/selected search fills, all inspector decoration
  shapes, and a tagged P3 image at both scales. Its generator must compare the
  CPU oracle to real Metal before writing, and ordinary tests must require
  exact checked-in bytes plus the existing one-byte GPU tolerance.
- 2026-09-14: The first focused `dart analyze` attempt after adding the runtime
  probes did not reach source analysis because Dart tried to update
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`, outside the
  writable workspace. This is an environment/sandbox failure rather than a
  diagnostic. Retry with `CI=true DART_SUPPRESS_ANALYTICS=true`; the failed
  attempt made no source change beyond the preceding successful formatter run.
- 2026-09-14: The suppressed focused analyzer then reached source analysis and
  found one missing import for the product-local `TerminalRenderColorSpace`
  enum used by the P3 runtime probe. The enum remains owned by the terminal
  renderer overlay contract; importing that existing module fixes the wiring
  without widening a package or generic-library API.
- 2026-09-14: The first Developer-JIT product run stopped at the new third
  Kitty band as intended by the strict counter check. Image id 94 was decoded
  and retained (`images=3`) but the `a=T,z=-2147483648` command produced no
  placement (`placements=2`, with two matching Metal images/placements/tiles).
  Thus the failure precedes layer composition and is specific to the
  transmit-and-place boundary input. Use `-1073741825`, the first value below
  the accepted `-0x40000000` below-background threshold, to exercise the exact
  classification boundary without depending on the i32-min command edge.
- 2026-09-14: Retrying `a=T` with `z=-1073741825` retained the image but again
  produced no placement, excluding the numeric threshold as the cause. The
  existing successful fixture uses separate transmit and `a=p` commands for
  ids 91/92, while the later `a=T` fixture is positioned only after an explicit
  cursor move. Change id 94 to the same already-proven separate transmit/place
  form so this test isolates layer classification rather than compound-action
  cursor behavior.
- 2026-09-14: Separate transmit/place failed identically and source inspection
  located the actual blocker: `TerminalKittyGraphicsController._placeImage`
  still returned `ENOTSUP` for every `z < -0x40000000`. Parsing, storage,
  viewport classification, CPU composition, and Metal already accept the full
  signed range, so this obsolete product-boundary guard made the completed
  below-background band unreachable from the ordinary PTY path. Remove only
  that guard; convert its controller negative test into exact acceptance of a
  `belowBackground` placement while preserving virtual, relative, invalid
  cursor, and missing-image rejection. Update the generated compatibility
  source wording from unsupported to the three explicit bands.
- 2026-09-14: Focused analysis of the controller change found that the mutable
  store placement deliberately exposes only its signed `z`; `layer` belongs to
  the immutable viewport projection. The acceptance assertion now compares the
  stored z against `TerminalKittyViewportPlacement.backgroundLayerZLimit`,
  while existing viewport/compositor tests remain the authority for its derived
  layer. No production API was widened.
- 2026-09-14: Focused analysis is now clean, and both the Kitty controller suite
  and the combined 1x/2x CPU-versus-real-Metal overlay/color suite pass. The
  ordinary terminal-display product scenario then passed in Developer JIT
  (`scale_16_16=131072`, 11.900 s) and Release AOT
  (`scale_16_16=131072`, 10.519 s). Those launches exercise the real PTY,
  signed-z controller/store/viewport path, native window/live surface, normal
  and selected search projections plus clear, and tagged P3 atlas conversion
  with exact real-Metal pixels at both scales. Inspector activation/cleanup is
  intentionally verified by the separate existing diagnostics product scenario
  and is the next focused runtime rerun.
- 2026-09-14: Both Developer-JIT and Release-AOT diagnostics product scenarios
  pass (`diagnostics_exports=2`, `incident_exports=2`), retaining inspector
  overlay activation, focus handoff/clear, redaction, atomic export, zero PTY
  writes, and complete two-session owner cleanup. The first compatibility
  inventory regeneration then wrote its canonical JSON but its summary parser
  rejected the updated Kitty note at the existing 1,024-character cap. Shorten
  only that prose to state the same three signed-z bands; do not raise the cap.
- 2026-09-14: The shortened inventory and generated Phase 6 summary pass. The
  first regression-coverage regeneration then stopped because its input
  `compatibility/differential_baseline_report.json` still hashes the preceding
  sequence inventory. Regenerate the reviewed in-process baseline first (its
  ordinary no-argument mode), then retry coverage; this is a declared freshness
  dependency and does not require an external Ghostty capture.
- 2026-09-14: Reviewed baseline regeneration and compatibility coverage then
  pass. The first Ghostty inventory generation reached the new closure audit
  and rejected its combined atlas/reference/compositor condition because the
  audit guessed `_srgbToLinear`, `_linearToSrgb`, and `_blendLinearStraight`;
  the actual reviewed CPU oracle names are `_decodeSrgbByte`,
  `_encodeSrgbByte`, and `_blendLinearSrgbChannel`. Correct the audit to those
  exact existing symbols rather than changing implementation names.
- 2026-09-14: The corrected closure audit, its two negative fixtures, all
  compatibility freshness checks, and the generated Ghostty inventory pass at
  102 rows, 96 accepted, zero actionable P0, and one actionable P1. The sole
  remaining actionable row is the separately ordered Option-click/semantic
  selection task; `REN-08` has no residual gap. The current CAP-11 matrix row
  was also corrected from the obsolete Phase 9 extreme-z exclusion to the
  product's three signed-z bands, then dependent coverage and gap reports were
  regenerated again.
- 2026-09-14: The exact final
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes every native package,
  generated/freshness, compatibility/differential/application/distribution,
  formatting (334 files, zero changes), full analysis, real-Metal, security,
  updater/rollback/symbol, and aggregate Dart test, ending with
  `dart_terminal tests passed`. `git diff --check` is clean. Apple notarization
  and duration-only campaigns remain skipped as authorized.
- 2026-09-14: Final code review after that pass strengthened search acceptance
  to require `acceptedFrameCount` to advance from the pre-overlay baseline, not
  merely publish bounded projection counters. Both Developer JIT (11.852 s)
  and Release AOT (10.556 s) pass the stricter real-Metal assertion. Phase 7 and
  Ghostty source-hash evidence were regenerated and the focused gap suite
  passes; because product source changed after the first aggregate run, one
  second exact full gate is required before commit.
- 2026-09-14: The second exact full gate passes in the strengthened final
  source/evidence state, again formatting 334 files with zero changes,
  reporting no analysis issues, retaining the 96 accepted / one actionable P1
  inventory, and ending with `dart_terminal tests passed`. The final adjacent
  `dart_appkit` status is clean and its tracked executable-code/content grep
  again returns no terminal-named match. `git diff --check` is clean.
- 2026-09-14: The first final `git add` attempt was denied before index mutation
  because this session exposes `.git/index.lock` read-only inside the workspace
  sandbox. Product files remain intact and unstaged. Retry only the requested
  Git index/commit operations with the approved repository-level permission;
  this is an environment constraint, not a source or verification failure.
- 2026-09-14: The adjacent `/Users/remi/dart/dart_appkit` worktree is clean.
  Its tracked path list has no terminal-named path, and a case-insensitive grep
  over tracked Dart/native/script/manifest/Makefile code has zero `terminal`,
  `dart_terminal`, or `dart-terminal` occurrence. This task changed no generic
  library file. The runtime-evidence child and overlay/P3 parent satisfy every
  recorded completion condition and may be closed.
- 2026-09-14: The pinned checkout remains clean at exact revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. Relevant source identities are
  `src/renderer/image.zig`
  `96562bf9b0a6a4fd2104586076768a7d15db34957cffbb0417b78371658fb3ad`,
  `Overlay.zig`
  `8b4fd865afd5202d8e519e91c29d62e0d9af6d94b2f77be6c1c73c3d6437bf84`,
  `generic.zig`
  `ccdcca8ef11c3d94fe6823b836a1ed9fd57089c00879fd45b32f72aab8c7c0d5`,
  `shaders.metal`
  `8c261d95c1d951cc47aa18bb39343a1cfd9057cc19dce987b4b1c3367f5d8d85`,
  and `Metal.zig`
  `596686cd2e7666ed5f19108b18ee79ad8a7280305712b1a70dfe45f77457e1c9`.
  Ghostty sorts Kitty placements by z and divides them at `minInt(i32)/2` and
  zero into below-background, below-text, and above-text bands. Search selected
  matches precede other matches and both precede normal cell colors. Its debug
  overlay is a full transparent CPU image derived only from hyperlink and
  semantic prompt/input metadata, uploaded through the image path above text.
- 2026-09-14: Product inventory found that Kitty decoding/storage, immutable
  viewport snapshots, color-atlas tiling, animation content generations,
  eviction, pins, and negative/nonnegative text bracketing are already complete.
  Phase 9 explicitly excluded the extreme-negative under-background band, and
  the compositor currently reduces all z values to only `z < 0` or `z >= 0`.
  Exact search over stable anchors is complete with query/scalar/match caps, but
  only selection ranges can currently project to visible spans and no search
  result reaches the compositor. The existing Terminal Inspector owns a
  bounded content-free parser capture and separate read-only window; it does not
  yet project hyperlink/semantic metadata onto its focused live surface.
- 2026-09-14: All terminal palette, OSC, reference-image, glyph, and Kitty
  bitmap inputs are currently documented as straight-alpha sRGB. The native
  color atlas, offscreen target, and `MTKView` use untagged
  `RGBA8Unorm`; the shader returns gamma-encoded channel values and fixed-function
  blending therefore performs source-over in that encoded space. There is no
  Display P3 tag or conversion boundary. This product will keep sRGB as its one
  canonical output space, convert explicit Display P3 inputs to clipped sRGB
  before packing, and use sRGB texture/target formats so blending occurs in
  linear light while readback/goldens remain encoded RGBA8 sRGB.
- 2026-09-14: The first contract child now provides an immutable
  `TerminalGridOverlayProjection` whose spans contain only kind, viewport row,
  and end-exclusive columns. Construction copies and canonically orders at most
  4,096 spans by explicit paint precedence, binds them to one positive source
  generation, and carries producer truncation metadata; it cannot retain search
  query, terminal text, URL, command, or parser payload. The separate
  `TerminalRenderColor` preserves straight-alpha sRGB bytes exactly and converts
  tagged Display P3 through the fixed D65 linear matrix, destination-gamut
  clipping, and sRGB transfer function while leaving alpha untouched. Bounded
  buffer conversion validates complete RGBA pixels and a 64 MiB hard maximum.
- 2026-09-14: Focused formatting changed only the two new Dart files. Focused
  analysis reported no issues, and the standalone contract test exited zero
  after checking immutable/canonical precedence, invalid geometry/generation,
  aggregate span caps, neutral/clipped/orange conversion vectors, alpha
  preservation, buffer copying, malformed length, non-byte input, and byte-cap
  rejection. No compositor, Metal ABI, terminal cell, or product activation was
  changed by this child.
- 2026-09-14: The first exact repository gate completed successfully, including
  every native capability suite, generated-evidence freshness check, 334-file
  zero-change format pass, security stress, and aggregate Dart tests. Its root
  analysis emitted one `directives_ordering` info for the new public export;
  the export was moved into the existing renderer section and the exact gate
  was rerun rather than accepting an informational diagnostic as clean.
- 2026-09-14: The final exact gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed with 334 files already
  formatted, root and package analyses reporting no issues, generated evidence
  fresh, all native/plugin/security suites passing, and the final
  `dart_terminal tests passed` marker. `git diff --check` was also clean.
- 2026-09-14: The adjacent `/Users/remi/dart/dart_appkit` worktree is clean.
  Its tracked-file inventory has no `terminal`-named path, and a tracked-source
  search has no terminal-specific executable content. Ignored `build/` outputs
  produced by earlier product builds and the vendored SDK cache contain product
  binary/test names, but are untracked generated artifacts, were not modified
  by this child, and are not part of the generic library source or publication.
  No `dart_appkit` file was changed.

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

### Current P1 child — variable axes, codepoint override, fallback diagnostics

- **Purpose:** Close the actionable `TXT-08` remainder with one bounded,
  immutable font request that applies validated OpenType variation axes,
  chooses explicit font families for ordered Unicode scalar ranges, and
  exposes content-free fallback/missing/override decisions to the product
  diagnostics surface.
- **Background:** The renderer package currently creates one regular CoreText
  face plus actual/synthetic trait faces from a family, point size, and policy.
  CoreText performs implicit fallback and copied shaped results already expose
  per-face fallback, color, synthetic, missing, and monospace flags, but the
  catalog cannot accept axes or explicit scalar mappings and does not retain
  bounded aggregate resolution diagnostics. Product config projects only
  family, size, and synthetic-style policy.
- **Scope:** Define immutable typed axis tags/values, style-specific variation
  sets, inclusive Unicode scalar-range font overrides with deterministic later
  precedence, and content-free counters/face identities under hard entry/byte
  caps; encode them through a versioned native boundary; apply axes to CoreText
  descriptors; apply available override fonts to exact scalar spans before
  normal CoreText fallback; fall back normally when an override family or
  glyph is unavailable while reporting that outcome; add repeatable typed
  product options and new-session projection; expose bounded counts and safe
  PostScript identities in Settings/diagnostics; verify package, product,
  configuration, rebuild, native Metal, and both runtime paths; bind the
  sources and regressions into the Ghostty inventory.
- **Out of scope:** Font download/install, arbitrary file paths, PostScript or
  family-name logging from terminal output, glyph or codepoint text in exported
  diagnostics, HarfBuzz, global font discovery redesign, synthetic box/block/
  braille/Powerline drawing (the next ordered child), per-cell metric changes,
  live mutation of an existing catalog, copying Ghostty configuration names or
  structures, and every change or `terminal`-named symbol in generic
  `dart_appkit`.
- **Dependencies:** `TerminalFontCatalog` and its generation-owned CoreText
  faces, version-one shape/raster copies, `TerminalShapingCache`, atomic render
  resource rebuild, typed repeated config/provenance, Settings inspector,
  privacy-safe renderer diagnostics, product hierarchy configuration, and
  pinned Ghostty `font/CodepointMap.zig`, `font/face/coretext.zig`, and
  `font/SharedGridSet.zig` at `d4d8f622...`.
- **Completion conditions:** Invalid tags, nonfinite/out-of-range values,
  surrogate/out-of-Unicode ranges, excessive counts/bytes, duplicate axis tags
  in one style, and malformed native buffers fail before publication; accepted
  axes change the requested CoreText face identity/variation state without
  changing point size or cell ownership; later overlapping mappings win,
  available mapped fonts are used only for covered scalars, and unavailable or
  glyph-missing mappings return to normal fallback without tofu or silent
  substitution; diagnostics remain bounded/content-free and distinguish
  requested, applied, unavailable, normal fallback, and missing-glyph counts;
  all configuration is immutable per catalog generation and a product reload
  follows new-session policy; `TXT-08` becomes accepted only after focused,
  native/runtime, freshness, and exact repository gates pass.
- **Verification approach:** Add malformed/cap tests before native use; use a
  macOS-installed variable system face and disjoint/overlapping family maps for
  exact CoreText face and shaping assertions; cover fallback-to-default and
  missing glyphs without retaining input text; exercise config file/include/
  CLI/repeat order, Settings rendering, render rebuild, real Metal output, and
  M1 Developer JIT/Release AOT; regenerate compatibility and Ghostty evidence
  in dependency order; run exact `CI=true DART_SUPPRESS_ANALYTICS=true make
  test`, review the diff, and repeat the clean `dart_appkit` audit. Apple
  notarization and duration-only campaigns remain skipped as authorized.

#### Ordered implementation subtasks

1. **Bounded immutable font request/diagnostic contract:** Freeze typed
   four-byte axis tags, values, style ownership, scalar ranges, ordered
   override descriptors, and diagnostic fields/caps as immutable Dart-owned
   values. No configuration is exposed to native creation until malformed,
   duplicate, range, count, and byte-bound tests pass.
2. **Versioned native ABI and CoreText variable axes/ordered codepoint
   resolution:** Copy the complete validated contract across one native
   boundary, apply it to base/trait/override faces, keep point/cell ownership
   stable, implement later-entry precedence and safe default fallback, and
   cover resolve/shape/raster behavior, diagnostics, malformed native input,
   and resource cleanup.
3. **Typed config, Settings, and product diagnostics projection:** Add bounded
   repeatable options and provenance, immutable new-session configuration,
   rebuild/catalog injection, safe Settings presentation, and content-free
   diagnostics with no terminal text/codepoint disclosure.
4. **Runtime evidence and closure:** Run real Metal and Developer JIT/Release
   AOT acceptance, regenerate dependent reports, update public/matrix text,
   move `TXT-08` from actionable to accepted, pass the exact repository gate,
   audit `dart_appkit`, and complete the parent child.

#### Current implementation subtask — typed product projection

- **Purpose:** Make the validated renderer font request reachable from typed
  product configuration, immutable for each new session, visible in Settings,
  and observable through bounded content-free product diagnostics.
- **Background:** The completed contract and native/CoreText children accept
  immutable variation and scalar-range override requests and copy bounded
  resolution diagnostics. The product schema still exposes only family, size,
  and synthetic-style policy, while application-created catalogs always use
  the renderer's empty request.
- **Scope:** Add bounded repeatable product-owned variation and override value
  types with source provenance; resolve layered duplicate axes by the final
  occurrence; project them into the renderer DTO; include the immutable request
  in render resource identity and every production catalog creation path; show
  syntax/current values and a bounded runtime resolution summary in Settings;
  add content-free fields to the exported diagnostics snapshot; update generated
  configuration references and focused regressions.
- **Out of scope:** Changing native ABI/CoreText policy, accepting font file
  paths, displaying terminal text or configured scalar values in diagnostics,
  synthetic cell glyph drawing, marking `TXT-08` accepted, runtime JIT/AOT
  evidence, matrix regeneration, and all `dart_appkit` changes or
  `terminal`-named generic-library code.
- **Dependencies:** `TerminalConfigRepeatedOption` precedence/provenance,
  `TerminalProductConfiguration`, `TerminalRenderFontConfiguration`,
  `TerminalLiveMetalSurface`, the Settings inspector runtime-status provider,
  `TerminalDiagnosticsSnapshot`, and the completed renderer
  `TerminalFontCatalogConfiguration`/diagnostic contract.
- **Completion conditions:** File/include/CLI values parse under explicit
  entry/byte/range bounds; later duplicate style/tag occurrences win before the
  duplicate-free renderer request is constructed; reloads affect only newly
  created sessions; resource matching rebuilds on any request change; Settings
  and exported diagnostics expose bounded counts/safe face identities without
  terminal text or scalar disclosure; focused and exact repository gates pass.
- **Verification approach:** Add parser/precedence/provenance, change-plan,
  Settings/reference, product projection, rebuild/catalog, runtime snapshot,
  and privacy-schema tests; run formatting and analysis, focused suites,
  generated reference freshness, native sanitizer where ownership is crossed,
  then exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` and a clean
  `dart_appkit` content/name audit. Apple notarization and duration-only
  campaigns remain skipped as authorized.

#### Current closure subtask — runtime evidence and matrix decision

- **Purpose:** Prove that configured variation axes, ordered codepoint
  overrides, and bounded fallback diagnostics operate through the ordinary
  packaged product in both supported runtime modes, then close `TXT-08` only
  against that executed evidence.
- **Background:** The typed product projection is complete and its exact
  repository gate passes, but the current Ghostty inventory correctly keeps
  `TXT-08` actionable. The existing configuration integration launcher builds
  and opens the normal Developer JIT and Release AOT applications and already
  drives configuration reload plus fresh window/tab/split creation.
- **Scope:** Extend or tighten the bounded configuration runtime observation so
  it explicitly proves the configured font request, immutable old-pane/new-pane
  boundary, native CoreText availability/unavailability diagnostics, and safe
  diagnostics projection; run both arm64 runtime modes; update README,
  `FEATURE_MATRIX.md`, generated compatibility evidence, task status, and the
  parent font item; rerun focused/freshness and exact repository gates.
- **Out of scope:** Duration-based daily use or soak, Apple notarization,
  arbitrary installed third-party-font coverage, synthetic cell glyphs,
  subsequent overlay/input gaps, and all changes or `terminal`-named code in
  generic `dart_appkit`.
- **Dependencies:** The committed product projection (`d9c662a`), the versioned
  native font request/diagnostic ABI, `runtime-configuration-integration`, the
  `TXT-08` matrix row, regression-coverage and Ghostty inventory generators,
  and the existing privacy audit.
- **Completion conditions:** Developer JIT and Release AOT both prove an
  available override and an unavailable axis without changing old-pane font
  state, the bounded product diagnostic contains no terminal text or configured
  scalar value, `TXT-08` moves to accepted with fresh source/test/runtime
  ownership, exact `make test` passes, `dart_appkit` remains clean, and the font
  roadmap parent has no remaining child.
- **Verification approach:** Run the bounded arm64 configuration integration
  first, correct only failures that exercise this contract, then run focused
  config/diagnostic/inventory checks, regenerate evidence in dependency order,
  execute exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, review the
  complete diff, and repeat the content/name boundary audit. Authorized
  notarization and duration-only campaigns are recorded as skipped, not as
  blockers or positive evidence.

### Current P1 child — synthetic cell glyphs

- **Purpose:** Render the reviewed box-drawing, block-element, braille, and
  Powerline scalar families with cell-owned deterministic geometry so adjacent
  cells meet without font side-bearing or raster seam gaps.
- **Background:** CoreText/atlas fallback and the 1x/2x golden corpus are
  complete, but `TXT-10` remains actionable and `TXT-06` explicitly defers
  these families. The current compositor sends printable cells through font
  resolve/shape/raster; no product synthetic-cell primitive owner has yet been
  identified.
- **Scope:** Re-read the pinned Ghostty sprite classification/drawing evidence;
  inventory the product model/compositor/frame/native Metal pipeline; define a
  bounded scalar-to-primitive contract and exact pixel rounding; implement only
  the accepted families; preserve style/color/damage/selection/cursor behavior;
  add 1x/2x and runtime evidence; update public/matrix/generated gap evidence.
- **Out of scope:** General vector graphics, arbitrary Nerd Font private-use
  glyphs outside the accepted Powerline set, image/search/inspector overlays,
  P3 conversion, font-file parsing, terminal layout changes, and every change
  or `terminal`-named symbol in generic `dart_appkit`.
- **Dependencies:** Unicode scalar/cell-width ownership, compositor compatible
  runs, glyph atlas/frame primitives, Metal encoding/shaders, color/style
  projection, cursor/selection overlays, scale-aware metrics, existing 1x/2x
  golden infrastructure, pinned Ghostty `font/sprite/draw/`, and the 94/3 gap
  inventory produced after `TXT-08` closure.
- **Completion conditions:** Every explicitly accepted scalar maps to bounded
  deterministic cell geometry at 1x and 2x, adjacent fill/line edges have no
  transparent seam, unsupported scalars continue through normal font fallback,
  rendering remains cell-clipped and resource-safe across scale/rebuild, real
  Metal Developer JIT/Release AOT evidence passes, `TXT-10` and the deferred
  portion of `TXT-06` are updated only after exact evidence, and `dart_appkit`
  remains generic and clean.
- **Verification approach:** Establish the exact scalar/primitive inventory and
  layer boundary first, record all subtask dependencies in this memo and
  `ROADMAP.md` before implementation, then use table-driven geometry/raster
  tests, existing golden comparisons, sanitizer/fault gates where native
  ownership changes, bounded two-runtime application acceptance, ordered report
  regeneration, exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, and the
  generic-library content/name audit. Apple notarization and duration-only
  campaigns remain skipped as authorized.

#### Ordered implementation split

This child crosses Unicode classification, deterministic geometry, atlas
ownership, the screen compositor, source-controlled images, and real Metal.
It is therefore split before implementation into the following ordered,
independently committed subtasks. A later subtask must not start until the
preceding subtask is verified and committed.

1. **Bounded scalar classification/device-pixel raster contract.** Define the
   exact accepted scalar sets, immutable raster request/result types, dimension
   and byte limits, clipping and rounding rules, and exhaustive boundary tests.
   Complete when all accepted and adjacent unsupported scalars classify
   deterministically and invalid dimensions fail closed; no compositor or atlas
   behavior changes in this subtask.
2. **Box-drawing deterministic raster geometry.** Implement U+2500..U+257F on
   the bounded raster surface, including light/heavy/double, dashed, arc,
   diagonal, and half-line variants. Complete when the whole range is
   table-tested at representative odd/even 1x/2x device grids and every joining
   edge required by the scalar reaches the exact cell boundary.
3. **Block-element and braille deterministic raster geometry.** Implement
   U+2580..U+259F and U+2800..U+28FF, including fractional, shade, quadrant, and
   empty/full patterns. Complete when exhaustive scalar tests prove bounded
   output and edge-filled blocks have no transparent cell seam at 1x/2x.
4. **Accepted geometric Powerline deterministic raster geometry.** Implement
   exactly the pinned geometric subset U+E0B0, E0B1, E0B2, E0B3, E0B4, E0B5,
   E0B6, E0B7, E0B8, E0B9, E0BA, E0BB, E0BC, E0BD, E0BE, E0BF, E0D2, and
   E0D4. Complete when filled/stroked geometry is bounded and adjacent stylized
   private-use scalars remain classified as unsupported for normal-font
   fallback.
5. **Glyph-atlas/screen-compositor integration.** Add a collision-free,
   scale-scoped alpha-atlas identity for product-owned cell rasters; divert only
   supported single-cell scalars from CoreText runs; retain color, selection,
   cursor, decoration, clipping, damage, reset, eviction, and frame lifetime
   semantics. Complete when focused atlas/compositor tests prove font fallback
   is bypassed only for accepted scalars and Metal/reference instances agree.
6. **1x/2x/real-Metal evidence and closure.** Add source-controlled 1x/2x
   corpus evidence, run Developer JIT and Release AOT Metal acceptance, update
   README/rendering documentation, `FEATURE_MATRIX.md`, TXT-10/TXT-06, coverage,
   and Ghostty gap reports in dependency order, run the exact repository gate,
   and repeat the adjacent-library audit. Complete only when fresh evidence
  supports closing this child and its parent.

#### Synthetic-cell investigation findings

- 2026-09-14: The pinned source remains revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. Relevant SHA-256 identities are
  `font/sprite.zig`
  `14876b4b92965dc342da974d7c02350d7ed9341d009436fe88256edad376eb15`,
  `draw/box.zig`
  `ee10346fb261a2cc104352ff235664f32204e845ff98772c48f3b6a63053a951`,
  `draw/block.zig`
  `b3f03cfffea07eb950517eecfe9b4ec396414decb5966e6bd4465f72612d12a5`,
  `draw/braille.zig`
  `8093913ed854b6d46a8b627c465d7f1ac7b2deedd35c208603f06c05bf9a6a8c`,
  `draw/powerline.zig`
  `91f897300bb8324c7f05da713d453d93624c4de89a9149e386bc7ace46c2a072`,
  `draw/common.zig`
  `e9715d969a60c109a4eea7f081ca8b6114e6d8126896ae13e9cbbcddba704319`,
  and `canvas.zig`
  `66d2dc1b99b2dc53e2ca9654e1ff45e1c271af3dc13ed169799dc87cf1492c6e`.
- 2026-09-14: Ghostty registers the complete Box Drawing, Block Elements, and
  Braille ranges, but only the 18 explicitly enumerated geometric Powerline
  functions above. The remaining U+E0B0..U+E0D4 private-use scalars are
  deliberately font-owned. Block fractions round against device-pixel cell
  extents; full blocks cover the complete cell; braille derives dot width,
  spacing, and margins from that same device grid.
- 2026-09-14: Product inspection found no existing synthetic-cell owner. The
  second compositor pass currently groups every visible printable cell into
  compatible CoreText runs, rasterizes missing font glyphs, ingests them into
  the alpha atlas, then places atlas masks on canonical grid origins. The atlas
  and Metal bridge already support scale-scoped alpha coverage, dirty-page
  synchronization, frame build leases, clipping, and reference rendering.
  A product-owned bounded alpha raster can therefore reuse this pipeline; no
  `dart_appkit` or shader change is required. Synthetic identities must be kept
  distinct from native face/glyph IDs and existing negative Kitty image IDs.
- 2026-09-14: The first scalar-contract formatting command completed its four
  requested files, then the Dart CLI attempted to update
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json` despite
  `DART_SUPPRESS_ANALYTICS=true` and was sandbox-denied. The chained analysis
  and focused test therefore did not run. This telemetry failure is not test
  evidence; verification is rerun with the normal local Dart cache permission.
- 2026-09-14: The first ordered subtask now defines an exact 434-scalar
  classifier: 128 Box Drawing, 32 Block Elements, 256 Braille Patterns, and the
  18 pinned geometric Powerline scalars. Its immutable request contract bounds
  width/height to 4096 device pixels, alpha storage to 16 MiB, line thickness
  to the cell, and rejects unsupported scalars before allocation. Complementary
  integer half-up fraction helpers intentionally overlap adjoining odd-sized
  regions by one pixel, matching the reviewed no-gap rule. The raster result
  owns a defensive, tightly packed alpha copy. Focused analysis reported
  `No issues found!`; exhaustive classification, invalid-boundary, rounding,
  and ownership tests passed with exit status zero.
- 2026-09-14: The first exact repository gate ran all functional suites through
  the final `dart_terminal tests passed` marker, but the analysis phase reported
  one `directives_ordering` info because the new public export followed the
  damage exports instead of preceding them alphabetically. This run is not
  accepted as a passing gate. The export was moved to its canonical position;
  no API or behavior changed, and the exact full gate is rerun.
- 2026-09-14: The corrected exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed: all native
  packages, generated and compatibility evidence, distribution/security/update
  suites, 332-file zero-change formatting, clean analysis, the exhaustive new
  scalar contract test through the aggregate runner, and the final
  `dart_terminal tests passed` marker completed successfully. This establishes
  the first subtask only; no raster geometry or compositor behavior is claimed.
- 2026-09-14: Final review found only the intended roadmap/memo, public export,
  aggregate runner registration, scalar contract, and its focused test.
  `git diff --check` passed. The adjacent `dart_appkit` worktree is clean; a
  case-insensitive executable-source/content audit outside docs/build/cache/git
  and a filename audit both found zero `terminal` matches. No generic-library
  file changed.
- 2026-09-14: The first staging attempt was sandbox-denied while creating
  `.git/index.lock`; no index or worktree content was changed. Staging and the
  required task commit are retried with Git metadata write permission and the
  same explicit six-file scope.

#### Current raster subtask — Box Drawing

- **Purpose:** Produce deterministic alpha geometry for every U+2500..U+257F
  scalar on the validated device-pixel cell so horizontally and vertically
  joined glyphs reach their shared cell edge without a transparent seam.
- **Background:** Commit `92b2632` established the exact scalar, dimension,
  thickness, byte-ownership, and complementary-rounding contract. No geometry
  exists yet, so every classified Box Drawing scalar still needs a bounded
  raster implementation before atlas integration can begin.
- **Scope:** Port the pinned light/heavy/double edge topology and dash fallback;
  implement clipped rectangle, diagonal-stroke, and curved-corner primitives;
  cover arcs, diagonals, and half-lines; exhaustively test all 128 scalars at
  odd/even representative 1x/2x grids and assert encoded edge ownership.
- **Out of scope:** Block, braille, Powerline, atlas/compositor diversion,
  golden files, real Metal acceptance, font metrics/configuration changes, and
  all `dart_appkit` changes.
- **Dependencies:** The committed raster request/result contract, pinned
  `draw/box.zig` and `draw/common.zig` identities recorded above, Ghostty's
  center/thickness formulas, and the existing aggregate test runner.
- **Completion conditions:** All 128 scalars return exact-size alpha rasters;
  light/heavy/double/dashed/arc/diagonal/half-line classes are nonempty; each
  declared line direction owns a nonzero pixel on the exact corresponding cell
  edge; joining representatives agree at both sides of a shared boundary; odd
  and even dimensions stay clipped and deterministic; focused and exact full
  repository gates pass; no generic-library content changes.
- **Verification approach:** Use the pinned topology as a compact reviewed
  table, table-drive exhaustive per-scalar/dimension determinism and edge tests,
  add targeted thickness/double/dash/arc/diagonal assertions, run focused
  format/analyze/tests, run the exact repository gate, inspect the final diff,
  and repeat the adjacent-library audit before marking only this subtask done.
- 2026-09-14: The first Box Drawing format/analyze/test command mistakenly
  included this Markdown memo in the `dart format` arguments. Both intended
  Dart files were formatted, then the formatter correctly rejected Markdown
  as non-Dart input; chained analysis and tests did not run. No documentation
  content was modified by the formatter. Verification is rerun with only the
  two Dart paths.
- 2026-09-14: The first focused analysis then found four static type errors at
  the diagonal primitive calls: the validated integer line thickness had not
  been converted to the canvas method's `double` distance domain. All four
  calls now convert explicitly; tests did not run in the failed command and no
  type contract was weakened.
- 2026-09-14: After clean analysis, the first focused raster run failed a newly
  added curved-corner join assertion. Inspection showed that the curve and
  straight glyph owned the same nontransparent boundary pixel, but the test
  incorrectly required their alpha magnitudes to be identical: the clipped
  anti-aliased curve endpoint is partial coverage while the rectangle is fully
  opaque. The assertion now compares the boundary ink mask, which is the seam
  prevention contract, while retaining separate deterministic byte checks.
- 2026-09-14: That binary-mask equality was also stricter than the join
  contract: a curved stroke can cover additional boundary pixels as it becomes
  tangent to the edge. The test now requires the arc boundary to contain every
  straight-line join pixel, permitting additional deterministic curve
  coverage. The curve itself was aligned more closely with the pinned cubic
  contract using its two center-biased quarter-curve control points and 0.25
  radius fraction.
- 2026-09-14: The completed Box Drawing raster owns all 128 scalars. A compact
  two-bit up/right/down/left table drives the pinned 109 straight/intersection
  topologies; dedicated bounded branches cover twelve dashed glyphs, four
  center-biased cubic arcs, and three anti-aliased diagonals. Light/heavy/double
  rectangles preserve pinned center and intersection joins, dash sizing falls
  back to a solid light center line when a device cell cannot hold every dash
  and gap, every primitive clips to the validated cell, and internal raster
  construction transfers its sole alpha allocation without a second 16 MiB
  worst-case copy. A read-only validator compared all 128 committed topology
  entries to the pinned Zig switch and reported
  `BOX_TOPOLOGY_PINNED_MATCH_PASS entries=128 line_entries=109`.
- 2026-09-14: Final focused formatting changed zero files, focused analysis
  reported `No issues found!`, and the raster suite passed. It exhaustively
  renders each scalar twice at 7x15/1px and 14x30/2px; checks exact dimensions,
  nonempty/deterministic bytes, all 109 exact direction-edge masks, shared
  light/heavy/double joins, thickness and double gaps, dashed gaps, curved
  corner shape and straight-edge containment, diagonal corners, family
  rejection, and the preceding scalar/limit/ownership contract.
- 2026-09-14: The exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` repository gate passed in
  the reviewed Box Drawing state. It covered every native capability package,
  generated/compatibility/distribution evidence, 332-file zero-change format,
  clean whole-product analysis, security/update/recovery suites, the aggregate
  raster invocation, and ended with `dart_terminal tests passed`.
- 2026-09-14: Final diff review and `git diff --check` passed with only the Box
  Drawing raster/test, this memo, and its roadmap state pending. The adjacent
  `dart_appkit` worktree is clean; both the case-insensitive executable-source
  content audit outside docs/build/cache/git and filename audit returned no
  `terminal` matches. No generic-library file changed.

#### Current raster subtask — Block Elements and Braille

- **Purpose:** Produce deterministic device-pixel alpha geometry for every
  U+2580..U+259F Block Element and U+2800..U+28FF Braille Pattern while keeping
  filled adjoining regions seam-free and braille dots legible within the cell.
- **Background:** Commits `92b2632` and `a426749` establish the bounded raster
  contract and complete Box Drawing. The next roadmap item is the remaining two
  complete public Unicode families; neither may be sent to the atlas until its
  pure raster behavior is exhaustively verified.
- **Scope:** Port pinned device-pixel fractional block rounding/alignment,
  four fixed shade coverage values, quadrant overlap rules, Unicode braille bit
  mapping, and pinned dot sizing/spacing/margin redistribution; add exhaustive
  1x/2x-equivalent deterministic and geometry tests for all 288 scalars.
- **Out of scope:** Powerline, atlas/compositor integration, source-controlled
  image goldens, real Metal, font configuration or layout changes, arbitrary
  Unicode geometric symbols, and every `dart_appkit` change.
- **Dependencies:** The committed request/result and clipped rectangle canvas,
  complementary fraction helpers, pinned `draw/block.zig`, `draw/braille.zig`,
  and `draw/common.zig` identities, and the aggregate raster test registration.
- **Completion conditions:** All 32 blocks have exact-size deterministic output
  with full/shade/fraction/quadrant semantics; half/quadrant complements cover
  odd and even cells without transparent seams; blank braille is empty and all
  other 255 patterns encode exactly their Unicode dot bits with bounded,
  nonoverlapping device-pixel dots at 1x/2x; invalid family calls fail closed;
  focused and exact full gates pass; `dart_appkit` remains untouched and clean.
- **Verification approach:** Implement each family behind a family-checking
  raster entry point, exhaustively render twice at 7x15/1px and 14x30/2px,
  assert exact coverage and edge/complement behavior for representative blocks,
  assert braille bit-to-position/count behavior for every scalar, run focused
  format/analyze/tests and the exact repository gate, review the diff, and
  repeat the adjacent generic-library audit before marking this item complete.
- 2026-09-14: Block Elements now use the pinned device-grid rules for
  top/bottom/left/right eighths and halves, exact full-cell alpha shades 0x40,
  0x80, 0xc0, and 0xff, plus complementary min/max quadrant boundaries that
  overlap by one pixel on odd extents instead of leaving a seam. The ten
  U+2596..U+259F quadrant masks match the pinned top-left/top-right/bottom-left/
  bottom-right combinations; the family entry point rejects every other
  classified family.
- 2026-09-14: Braille now maps the low Unicode pattern byte in standard dot
  order (left 1/2/3, right 4/5/6, then left/right 7/8). Dot width, spacing, and
  margins follow the pinned redistribution sequence derived solely from the
  device cell. U+2800 remains an exact empty alpha raster; every other pattern
  owns only its selected nonoverlapping square dots. No font, atlas, compositor,
  native, or generic-library behavior changed.
- 2026-09-14: Focused formatting ended with zero changes, analysis reported
  `No issues found!`, and the aggregate raster suite passed. It renders all 32
  Block Elements and 256 Braille Patterns twice at 7x15/1px and 14x30/2px;
  checks byte determinism and bounds; exact full/shade coverage; every eighth's
  rounded area and anchored edge; half and quadrant complement seam coverage;
  all 256 popcount-derived dot areas; exact eight 1x positions and eight 3x3
  2x positions; blank/full patterns; and wrong-family rejection.
- 2026-09-14: Final code review removed unused center alignment variants, added
  the pinned braille layout inequality as a fail-closed runtime invariant, and
  strengthened exhaustive Block Element tests to admit only the exact alpha
  domain `{0, 0x40, 0x80, 0xc0, 0xff}`. Formatting, clean focused analysis, and
  the raster suite passed again. Because executable code changed after the
  preceding repository gate, that gate is rerun before completion.
- 2026-09-14: The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` rerun passed with every
  native package and generated/compatibility/distribution check, 332-file
  zero-change formatting, clean whole-product analysis, aggregate raster,
  security/update/recovery suites, and `dart_terminal tests passed`. Final
  `git diff --check` passed with only this raster subtask's code, tests, memo,
  and roadmap state pending.
- 2026-09-14: The adjacent `dart_appkit` worktree is clean. A case-insensitive
  executable-source/content audit outside docs/build/cache/git and a filename
  audit both found zero `terminal` matches. No generic-library file changed.

#### Current raster subtask — geometric Powerline subset

- **Purpose:** Produce deterministic device-pixel alpha geometry for exactly the
  18 pinned Powerline scalars while ensuring the unimplemented stylized private
  use glyphs remain font-owned fallback.
- **Background:** The bounded contract and all public Box/Block/Braille ranges
  are committed. Pinned `draw/powerline.zig` deliberately exposes only U+E0B0
  through U+E0BF plus U+E0D2 and U+E0D4; classification already matches that
  boundary, but these accepted scalars have no raster geometry yet.
- **Scope:** Implement filled and stroked chevrons, four triangular corners and
  paired diagonals, filled/stroked rounded separators, and the paired two-piece
  trapezoid separators; add bounded polygon/polyline primitives and exhaustive
  1x/2x determinism, mirror, edge, fill/stroke, and fallback-boundary tests.
- **Out of scope:** Every other Powerline/Nerd Font PUA scalar, atlas/compositor
  integration, image goldens, real Metal evidence, font/layout/configuration
  changes, other geometric-symbol ranges, and all `dart_appkit` changes.
- **Dependencies:** Commits `92b2632`, `a426749`, and `a4bd787`; the clipped
  alpha canvas and anti-aliased line primitive; pinned Powerline source identity
  above; the classifier's exact 18-scalar allow-list; aggregate raster tests.
- **Completion conditions:** Each accepted scalar returns nonempty exact-size
  deterministic output at odd/even 1x/2x grids; all nine mirrored pairs match
  byte-for-byte after horizontal reflection; filled separators own their
  intended complete boundary and open separators remain unfilled; no adjacent
  stylized PUA scalar becomes product-owned; invalid family calls fail closed;
  focused and exact full gates pass; `dart_appkit` remains untouched and clean.
- **Verification approach:** Port only the reviewed functions onto bounded
  polygon/polyline/cubic helpers, table-drive all 18 accepted scalars at both
  device grids, assert every mirror pair and representative boundary/center
  behavior, retain classifier negatives, run focused format/analyze/tests and
  the exact repository gate, inspect the diff, and repeat the generic-library
  audit before marking this subtask complete.
- 2026-09-14: The Powerline raster entry point implements only the allow-listed
  functions. Filled chevrons/corner triangles use scanline polygon coverage and
  explicitly own their complete flat joining edge; open chevrons and rounded
  separators reuse the bounded anti-aliased polyline; filled rounded separators
  use the pinned two cubic arcs; diagonals reuse the Box Drawing line contract;
  the extra separators use two independently filled trapezoids around the
  requested line-thickness gap. Right-facing counterparts are produced by an
  in-place bounded horizontal reflection, preventing parity drift between a
  pair. Polygon scanlines compute per-device-column alpha overlap without an
  unbounded supersampling multiplier.
- 2026-09-14: A read-only source validator extracted every `pub fn drawE0...`
  declaration from the pinned Powerline file and compared it with the committed
  test allow-list, reporting
  `POWERLINE_PINNED_SET_MATCH_PASS scalars=18 first=U+e0b0 last=U+e0d4`.
  This confirms that stylized gaps in U+E0C0..U+E0D4 were not silently claimed.
- 2026-09-14: Focused formatting and analysis passed with `No issues found!`;
  the aggregate raster suite passed. It renders all 18 scalars twice at
  7x15/1px and 14x30/2px, proves exact size/nonempty byte determinism, verifies
  all nine horizontal mirror pairs byte-for-byte, asserts complete flat join
  edges for eight filled separators, distinguishes filled/open chevron and
  rounded forms, preserves the two-piece center gap, rechecks adjacent PUA
  fallback, and rejects wrong-family requests.
- 2026-09-14: The exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` repository gate passed in
  the reviewed Powerline state, including native/generated/compatibility/
  distribution evidence, 332-file zero-change format, clean whole-product
  analysis, aggregate raster coverage, security/update/recovery suites, and
  the final `dart_terminal tests passed` marker. `git diff --check` passed.
- 2026-09-14: Final review found only this Powerline raster/test, memo, and
  roadmap state. The adjacent `dart_appkit` worktree is clean; the executable
  source/content audit outside docs/build/cache/git and the filename audit both
  found zero case-insensitive `terminal` matches. No generic-library file
  changed.

#### Current integration subtask — glyph atlas and screen compositor

- **Purpose:** Route each supported, plain single-cell scalar through its
  completed product-owned alpha raster and the ordinary Metal atlas/frame path,
  bypassing CoreText only for the exact 434-scalar allow-list.
- **Background:** All four pure-raster families are committed, but the screen
  compositor still shapes every printable cell with CoreText. The existing
  atlas has native font keys and a separate negative Kitty image identity; it
  needs a typed, collision-free cell-raster namespace before compositor use.
- **Scope:** Add a domain/scale/dimension/thickness-aware cell-atlas key and
  index; share alpha page allocation, dirty upload, eviction, reset, build lease,
  reference, and Metal bridge behavior; split compatible text runs at supported
  scalar cells; rasterize/ingest unique misses; position masks at exact rounded
  cell rectangles; expose a composition count; verify fallback, styles/colors,
  clipping/insets, reset/eviction/pins, and native/reference parity.
- **Out of scope:** New raster geometry, multi-scalar grapheme replacement,
  preedit rewriting, source-controlled 1x/2x corpus artifacts, runtime JIT/AOT
  acceptance, README/matrix/gap closure, image/search/inspector overlays,
  terminal layout changes, and all `dart_appkit` changes.
- **Dependencies:** Commits `92b2632`, `a426749`, `a4bd787`, and `51c41ea`;
  `TerminalGlyphAtlas` alpha page ownership and Metal bridge; canonical
  per-column/per-row rounding; style/color and cursor/selection layering;
  compatible-run cluster boundaries; current compositor and atlas tests.
- **Completion conditions:** The exact supported scalar in a plain narrow cell
  becomes one cell-owned alpha glyph at exact device cell bounds and is absent
  from CoreText shaping; adjacent unsupported PUA and multi-scalar graphemes
  remain font-shaped; unique keys cannot collide with native or Kitty entries;
  multiple rounded widths/heights, scale/reset, eviction, pins, clipping/inset,
  foreground/style/overlay order, reference and real native Metal rendering
  remain correct; focused and exact repository gates pass; `dart_appkit` stays
  untouched and clean.
- **Verification approach:** Refactor native insertion through one raw bounded
  allocator, add typed cell-key unit tests for identity/reinsertion/reset/
  eviction/pin/bridge behavior, add mixed supported/unsupported compositor
  cases at 1x/2x and inset/native render assertions, run focused format/analyze/
  atlas/compositor/raster tests, run the exact repository gate, review the diff,
  and repeat the adjacent-library audit before marking this item complete.
- 2026-09-14: Atlas integration now uses a typed key containing catalog and
  fixed-scale domains plus scalar, exact rounded device width/height, and line
  thickness. Its internal storage identity uses the reserved `faceId == -2`
  namespace and a bounded mixed-radix encoding of the raster geometry; native
  CoreText faces remain positive and Kitty tiles remain `faceId == -1`.
  Cell masks reuse the ordinary alpha-page allocator, dirty uploads, LRU,
  build/submission pins, reset invalidation, reference primitive, and Metal
  bridge instead of adding a second resource lifetime.
- 2026-09-14: The compositor now removes only supported plain width-one scalar
  cells from CoreText runs. It computes the left/right and top/bottom edges with
  the same per-grid-line rounding used by backgrounds, selections, and cursors,
  so fractional metrics may select distinct width/height-aware atlas entries
  without stretching one raster. The product raster line thickness is derived
  from the scaled catalog underline thickness and clamped to the exact cell.
  Styled foreground color and the existing decoration/selection/cursor/image
  layer order remain independent. Supported bases inside interned multi-scalar
  graphemes, wide cells, preedit text, unsupported private-use glyphs, and all
  other text remain font-owned.
- 2026-09-14: The first focused atlas test attempt reached the native Metal
  build hook but the workspace sandbox denied writes below the user Clang
  module cache (`~/.cache/clang/ModuleCache`). No test assertion ran and no
  source changed. Repeating the same test with the required cache/device access
  succeeded. Focused formatting and static analysis then completed with zero
  issues; the atlas lifecycle test passed reinsertion, exact bytes, reference
  masks, dimension-key separation, native/Kitty namespace coexistence, shared
  LRU eviction, build-pin retention, index cleanup, reset, and stale-domain
  rejection.
- 2026-09-14: The focused screen compositor suite passed at both 1x and 2x.
  Its new mixed row proves Box, Block, Braille, and accepted Powerline cells
  produce four `faceId == -2` alpha entries at their exact independently
  rounded cell rectangles, split two ordinary CoreText runs around them, keep
  adjacent U+E0C0 in the positive native-face namespace, preserve an RGB
  foreground and underline, apply content insets, and render through the real
  native Metal path. A separate combining-mark case proves a classified base
  inside an interned grapheme never enters the cell atlas.
- 2026-09-14: The first exact repository gate stopped at the deterministic
  Ghostty inventory stale check after all preceding native, generated,
  compatibility, differential, application, terminfo, and shell-integration
  checks had passed. The changed compositor and compositor test are hashed
  evidence sources, so regenerating
  `compatibility/ghostty_p0_p1_gap_inventory.json` is required even though this
  integration subtask deliberately leaves `TXT-10` actionable until the
  following runtime/evidence closure. The first generator attempt was again
  sandbox-blocked only at the Clang module cache; the same generator completed
  with cache access, and the checked-in hash now describes the reviewed
  implementation and test.
- 2026-09-14: After regenerating the deterministic inventory, the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` repository gate passed. It
  includes native capability/assets, generated references, compatibility and
  differential evidence, application/terminfo/shell contracts, the synchronized
  102-row Ghostty inventory, distribution policy, 332-file zero-change format,
  whole-product analysis, all aggregate Dart/native/security/update/recovery
  suites, the new atlas/compositor assertions, and the final
  `dart_terminal tests passed` marker. `git diff --check` also passed.
- 2026-09-14: Final boundary review found only this task's cell raster
  dispatcher, typed atlas integration, compositor diversion, focused tests,
  generated inventory hash update, memo, and roadmap state. The adjacent
  `/Users/remi/dart/dart_appkit` worktree is clean. Case-insensitive content
  and filename audits outside its docs/build/cache/git areas both found zero
  `terminal` matches, so no product-specific code or named source artifact was
  introduced into the generic library.

#### Current closure subtask — synthetic-cell runtime evidence and parity records

- **Purpose:** Bind the completed synthetic Box, Block, Braille, and accepted
  Powerline implementation to reproducible 1x/2x image evidence and both
  supported product runtimes, then close only the corresponding matrix gap and
  roadmap parent.
- **Background:** Commits `92b2632`, `a426749`, `a4bd787`, `51c41ea`, and
  `bcd22b6` complete the bounded contract, all four raster families, and the
  shared atlas/compositor path. The current gap inventory must remain open
  until fresh source-controlled corpus evidence, Developer JIT, and Release AOT
  acceptance all exercise that path.
- **Scope:** Add deterministic 1x/2x source-controlled render fixtures and a
  freshness/visual comparison test; extend the bounded runtime integration
  acceptance with exact synthetic-cell and adjacent-font-fallback assertions;
  run both product modes; update README and rendering reference documentation,
  `FEATURE_MATRIX.md` rows TXT-06/TXT-10, compatibility coverage and the
  generated Ghostty gap inventory in dependency order; mark this child and its
  synthetic-glyph parent complete only after all gates pass.
- **Out of scope:** Image/search/inspector overlays, P3 conversion,
  Option-click/semantic selection, arbitrary geometric symbols or Nerd Font
  PUA, font/layout/config changes, duration-only campaigns, Apple-service
  notarization, and every change or `terminal`-named artifact in generic
  `dart_appkit`.
- **Dependencies:** The five committed implementation subtasks; existing DTGI
  codec/comparator and Metal golden conventions; the product runtime smoke
  launcher and exact-marker policy; matrix/gap/coverage generators; canonical
  per-grid-line rounding; the pinned Ghostty revision and scalar inventory
  already recorded in this memo.
- **Completion conditions:** Checked-in 1x/2x images cover all four families
  plus unsupported PUA fallback and compare exactly in the ordinary suite;
  Developer JIT and Release AOT product runs each report and render the same
  bounded feature without weakening existing assertions; docs and generated
  reports state only observed coverage; TXT-10 and the synthetic portion of
  TXT-06 become accepted with zero new silent gap; focused and exact full gates
  pass; `dart_appkit` stays clean and generic.
- **Verification approach:** Inventory existing golden/runtime/report ownership
  before edits; implement the smallest deterministic corpus and runtime marker;
  run focused image freshness/reference/Metal and runtime tests at 1x/2x, then
  the bounded two-mode application target; update narrative sources before
  regenerating dependent reports; run the exact repository gate, inspect all
  source and binary fixture diffs, and repeat the adjacent-library content/name
  audit before completion and commit.
- 2026-09-14: Closure inventory found three existing version-one DTGI fixture
  families: CPU reference layers, CoreText/atlas text, and Kitty CPU
  composition. `TerminalScreenMetalCompositor` already exposes every retained
  glyph entry and packed instance needed to reconstruct a device-pixel CPU
  reference frame, while `TerminalMetalRenderer.renderRgba` supplies the same
  frame's real Metal readback. The new fixture will therefore be compositor-
  owned: exact checked-in CPU bytes remain deterministic, and the native result
  must remain within the established one-channel-value Metal tolerance at 1x
  and 2x. Its four rows will distinguish all four families by color, cover
  representative Box/Block/Braille forms, all 18 accepted Powerline scalars,
  blank Braille, and adjacent unsupported U+E0C0 through CoreText fallback.
- 2026-09-14: The ordinary product `runtime-terminal-display-integration`
  already launches the real AppKit window, live screen/session, CoreText atlas,
  and Metal surface in Developer JIT and Release AOT. A bounded ASCII shell
  command can emit the five relevant UTF-8 scalars by octal bytes so only its
  output—not its command echo—contains them. Runtime acceptance can then bind
  canonical screen positions to exact device-cell atlas keys, require all four
  accepted family entries and a later accepted Metal frame, and prove adjacent
  U+E0C0 remains classifier-unsupported. This extends the existing display gate
  without adding another runtime option or external dependency.
- 2026-09-14: Public parity ownership is concentrated in README's renderer and
  local-check sections plus matrix rows `TXT-06` and `TXT-10`; no current
  rendering reference page describes the synthetic allow-list or font-fallback
  boundary. Closure will add one focused reference and link it from README.
  The Ghostty inventory generator already owns exact matrix classification,
  evidence hashes, completion lists, remaining actionable totals, and negative
  source validation; it—not the unrelated parser sequence coverage report—is
  the correct compatibility coverage owner for this renderer gap.
- 2026-09-14: The checked-in compositor corpus is now 71,624 bytes at 1x
  (SHA-256
  `dfe94356493b698b6a2d4b916a7d340d0efb3e6492b6804385d0d752292d3930`)
  and 285,995 bytes at 2x (SHA-256
  `d104ea9df96eb2e2c4ab0fbd4694b8dda7b718f7494d47f00c862d8e6da8a58b`).
  The focused compositor program regenerated both through its explicit writer,
  then passed in ordinary non-writing mode: four colored rows yield 42
  synthetic placements (Box 10, Block 8, Braille 6, Powerline 18), one
  CoreText run for adjacent U+E0C0/ASCII fallback, byte-exact CPU-reference
  DTGI comparison, and real Metal readback within the established per-channel
  tolerance at both scales.
- 2026-09-14: The first focused closure analysis found two missing type imports
  in `terminal_application.dart`: the new runtime assertion referenced
  `TerminalGlyphAtlasEntry` and `TerminalCellGlyphAtlasKey` but had imported
  only the cell contract and live surface. Importing the existing atlas module
  fixed both errors; the repeated focused format/analysis completed with zero
  issues. No runtime or acceptance condition was weakened.
- 2026-09-14: The bounded arm64 product display target passed on the real M1
  window/PTY/CoreText/Metal path in both modes. Developer JIT reported
  `RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS ... scale_16_16=131072
  elapsed_ms=11674`; Release AOT reported the same accepted 2x scale and
  `elapsed_ms=10449`. Each application emitted the exact content-free
  `TERMINAL_CELL_GLYPH_TEST` marker after locating Box, Block, Braille,
  Powerline, and adjacent U+E0C0 cells, resolving the four accepted cells to
  exact rounded atlas keys, observing a current accepted Metal frame, and
  retaining U+E0C0 on the normal fallback boundary. Existing display checks
  and clean shutdown also passed.
- 2026-09-14: README now links a focused rendering reference that records the
  434-scalar allow-list, cell/atlas/layer ownership, fallback boundary, fixture
  hashes, and reproduction commands. Matrix `TXT-06` now records the expanded
  1x/2x corpus and `TXT-10` records the bounded implementation and executed
  evidence. The fail-closed Ghostty closure validator binds classifier,
  geometry families, atlas/compositor, exhaustive tests, both DTGI files, and
  both runtime markers. After ordered regeneration its report has 102 rows,
  95 accepted, zero actionable P0, two actionable P1 rows, seven reviewed gaps,
  and no silent misbehavior; the focused report test and three new negative
  drift cases passed.
- 2026-09-14: The first final full-gate attempt stopped in the pre-existing
  `dart_pty_macos` live-child completion test with a one-off `Bad state: No
  element`; the same test had passed in both preceding full runs. The immediate
  exact rerun passed that PTY test, confirming no repeat, then correctly stopped
  because the Phase 7 AppKit acceptance artifact hashes the changed product
  application/runtime display sources. Regenerating only
  `test/corpus/appkit/phase7_acceptance_v1.json` restored that deterministic
  dependency. Neither stop indicated a cell raster, compositor, Metal, or
  runtime acceptance failure.
- 2026-09-14: The resumed exact gate again passed the previously intermittent
  live-child PTY case and the refreshed Phase 7 artifact, then stopped at the
  compatibility regression coverage freshness check. The underlying nine-case
  parser corpus still passed (`input_bytes=390`, `split_runs=417`); the report
  includes `FEATURE_MATRIX.md` in its reviewed source identities, so closing
  `TXT-06`/`TXT-10` intentionally made it stale. This is a generated-evidence
  dependency, not a synthetic-cell or compatibility behavior failure. The
  report must be regenerated before the focused freshness checks and exact gate
  are repeated.
- 2026-09-14: Regenerating the compatibility coverage report in the normal
  macOS context succeeded. A sandboxed attempt had first failed before running
  the generator because the Dart CLI could not update its home-directory
  telemetry timestamp; no product or report file was changed by that failed
  attempt. The focused coverage check then passed all nine cases and correctly
  showed that its new report hash made the downstream Ghostty inventory stale,
  so the inventory is regenerated next in dependency order.
- 2026-09-14: Dependency-ordered regeneration completed with the compatibility
  coverage report passing nine cases/417 split runs and the Ghostty inventory
  passing 102 rows, 95 accepted rows, zero actionable P0, two actionable P1,
  seven reviewed gaps, and zero silent misbehavior. The final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed in the reviewed
  source/evidence state: all native/package and generated-evidence gates,
  332-file zero-change formatting, clean analysis, security/update/symbol
  suites, the real Metal compositor regression, and the aggregate
  `dart_terminal tests passed` marker completed successfully. `git diff
  --check` passed; both checked-in fixture sizes and SHA-256 values match this
  memo and the rendering reference.
- 2026-09-14: Final adjacent-library audit found the `dart_appkit` worktree
  clean. Case-insensitive executable-source/content and filename searches,
  excluding docs/build/cache/git, returned zero `terminal` matches. This task
  changed no generic-library file. Apple notarization and duration-only
  campaigns remain skipped as authorized. All synthetic-cell child completion
  conditions are met, so both the runtime-evidence child and its parent can be
  marked complete; the next ordered item is image/search/inspector overlay and
  P3-to-sRGB conversion.

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
- 2026-09-14: After commit `c86e7dc` and the mandatory roadmap, README,
  feature-matrix, and clean-worktree reread, `TXT-08` is the first unchecked
  item. Its three visible features share the font-catalog owner but cross the
  native ABI, CoreText, config/Settings, product rebuild, diagnostics, and
  runtime evidence boundaries, so it is split into the four ordered subtasks
  above before implementation. The current contract subtask must not apply
  axes or mappings ahead of its own validation, and no synthetic-glyph work is
  included.
- 2026-09-14: Current native creation accepts only family UTF-8, point size,
  and synthetic-style policy. A catalog owns four requested/trait faces and a
  name-keyed fallback face registry; CoreText resolves fallback inside
  attributed strings. Dart already copies fallback/color/synthetic/missing/
  monospace flags per resolved face and shape run, but no bounded aggregate is
  retained for Settings or diagnostics. Product config contains only
  `font-family`, `font-size`, and `font-synthetic-style`, all immutable for new
  sessions.
- 2026-09-14: Pinned source identities are SHA-256
  `282a2fa6f350ac60570e40b59cc0809efbba830f8986c196c69b89cd11c8dbf3`
  for `font/CodepointMap.zig`,
  `367be97710c61c81a07eb08e7106a7fdaa2c53714f188756fec750ff001eff05`
  for `font/face/coretext.zig`, and
  `27d0e0734e1e19952ad87edab3afdfaa56059c2ced3b7bdc368d9b391977c880`
  for `font/SharedGridSet.zig`. The observable policies adopted here are
  four-byte axis identifiers, immutable configured faces, inclusive scalar
  mappings, later-entry precedence, and normal fallback when a mapped
  descriptor cannot supply a usable face. Ghostty names and internal storage
  are not copied.
- 2026-09-14: A read-only Swift probe intended to identify a deterministic
  installed variable system face was sandbox-blocked while creating the shared
  Clang module cache; it made no product change or acceptance claim. The probe
  will be repeated in the normal macOS execution context before choosing the
  native test fixture.
- 2026-09-14: The initial layer split was refined before code changes so a
  valid nonempty request is never exposed to a native constructor that cannot
  yet honor it. The first child now completes only immutable Dart request and
  diagnostic values with fail-before-publication limits; the second child adds
  and implements the copied ABI atomically.
- 2026-09-14: The first focused analyzer run found that Dart's
  `RangeError.range` accepts integer bounds even though variation coordinates
  are doubles. Axis validation now uses `RangeError.value` after its explicit
  finite and `-65536...65536` check; the rerun reported `No issues found!`.
  The first package test then exposed a fixture arithmetic typo: `Menlo` plus
  `Times-Roman` is 16 UTF-8 bytes, not 17. The implementation's recorded byte
  count was correct; the assertion is corrected and an independent 65 KiB
  aggregate-family negative was added before rerunning the full package.
- 2026-09-14: A sandboxed package-test attempt stopped in the native build hook
  because Metal could not write the shared Clang module cache. It did not reach
  product tests and is not accepted as verification. All native/build-hook
  reruns use the normal macOS execution context, consistent with earlier
  renderer children.
- 2026-09-14: The completed Dart-owned contract accepts at most 16 unique
  printable four-byte OpenType tags per requested style (64 total), finite
  coordinates in `-65536...65536`, 256 inclusive non-surrogate Unicode scalar
  mappings, 1,024 UTF-8 bytes per family, and 64 KiB across mapped families.
  Style lists and mappings are immutable; overlapping mappings resolve from
  last to first. Diagnostic snapshots cap signed counters and 256 unique
  `(resolution source, face ID)` records, require consistent applied/
  unavailable totals, and contain only source class, flags, safe PostScript
  identity, and occurrence count—never input text or scalar values.
- 2026-09-14: Focused package formatting and analysis passed, and the complete
  renderer package test runner passed its native asset hook plus all Dart
  tests. Final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed all
  native packages, generated/freshness and compatibility evidence, application
  and distribution gates, 330-file zero-change root formatting, clean root and
  renderer-package analysis, security/update/symbol coverage, and aggregate
  Dart tests ending with `dart_terminal tests passed`. `git diff --check`
  passed. The adjacent `dart_appkit` worktree is clean and its case-insensitive
  executable content/name audit outside docs/build/cache/git found zero
  `terminal`, `dart_terminal`, or `dart-terminal` matches. Apple notarization
  and duration-only campaigns remain skipped as authorized. The next ordered
  subtask is the copied native ABI plus CoreText axis/override application.
- 2026-09-14: A read-only Swift probe in the normal macOS execution context
  confirmed a deterministic variable-font fixture. The system monospaced face
  `.AppleSystemUIFontMonospaced-Regular` exposes hidden `YAXS` plus public
  `wght`; its weight axis range is approximately `294.673...900`. The system
  `.SFNS-Regular` exposes four axes, while Menlo exposes none. Native and Dart
  acceptance therefore use the empty-family system-monospaced request with a
  `wght` coordinate, without depending on a separately installed font.
- 2026-09-14: The first native build of the version-one configuration and
  diagnostics ABI stopped at compile time under the existing pedantic warning
  gate. New uses of Foundation's `MIN` macro expand to GNU statement
  expressions, and an empty C initializer is a C23 extension. These are source
  portability errors rather than runtime failures: metric additions now reuse
  the existing saturating helper, the glyph chunk uses an explicit ternary,
  and the legacy empty configuration uses the portable `{0}` initializer
  before rerunning the same gate.
- 2026-09-14: The native implementation keeps legacy catalog creation as an
  empty-config wrapper and adds one version-one copied request. Exact record
  sizes/strides, reserved fields, pointer/count pairs, canonical style order,
  unique tags, scalar ranges, contiguous family slices, and all entry/byte
  limits are rejected before handle publication. CoreText descriptors apply
  supported axes to base, trait, and override faces; face identity includes the
  variation dictionary so raster lookup cannot alias two configured faces.
  Scalar overrides are selected last-to-first, cover the complete UTF-16
  scalar span, and are applied only when the requested face itself supplies the
  glyph. An unavailable family or glyph leaves the base attributes intact for
  normal CoreText fallback.
- 2026-09-14: The pedantic native gate then compiled and linked the new ABI and
  passed. Its capability regression rejects unknown versions, wrong strides,
  duplicate tags, and noncanonical family slices without a live handle; proves
  system `wght` application plus one unknown axis; proves later overlapping
  Menlo over Times precedence; proves unavailable-family fallback and
  Times-to-color-emoji missing-glyph fallback; carries all selected faces
  through resolve, shape, raster, and release; and copies bounded diagnostics
  containing only source, flags, face ID, PostScript name, and count.
- 2026-09-14: A direct Dart formatter run changed only the FFI source and then
  failed while updating the SDK's global telemetry timestamp outside the
  repository sandbox. The same files were formatted in the normal macOS
  context. Focused package analysis reported `No issues found!`, and the full
  renderer package runner passed its native asset hook plus all Dart tests.
  Dart coverage additionally proves immutable configuration retention,
  visible heavier `wght=800` raster ink at unchanged point size, exact native
  diagnostic decoding, and disposed-generation rejection. The package README
  now documents the catalog-level configuration, precedence/fallback policy,
  and content-free diagnostic boundary; product configuration and Settings
  remain deliberately deferred to the next ordered subtask.
- 2026-09-14: `DART_SUPPRESS_ANALYTICS=true make product-native-sanitizer`
  passed all four isolated native suites and all nine artifacts. The renderer
  library and harness were both instrumented by AddressSanitizer and
  UndefinedBehaviorSanitizer; the aggregate marker was
  `PRODUCT_NATIVE_SANITIZER_PASS`. This is a bounded ownership/ABI check, not a
  duration-based soak.
- 2026-09-14: Final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed in the reviewed
  source state. It covered every native capability, package analysis/test,
  generated and compatibility freshness, differential and real-application
  evidence, terminfo and shell integration, the Ghostty inventory (102 rows,
  93 accepted, four actionable P1), distribution policy, 330-file zero-change
  formatting, clean root analysis, security/update/symbol coverage, and the
  aggregate `dart_terminal tests passed` marker. `git diff --check` passed.
  The adjacent `dart_appkit` worktree is clean; a case-insensitive content and
  filename audit of its native, packages, scripts, test, tool, examples, and
  Makefile surfaces found zero `terminal`, `dart_terminal`, or
  `dart-terminal` matches. No generic-library file changed. Apple notarization
  and duration-only campaigns were skipped as authorized. The next ordered
  subtask is typed product configuration, Settings, and product diagnostic
  projection.
- 2026-09-14: Product inspection found that the existing repeatable-option
  collector already preserves include/root/CLI order, per-occurrence source,
  a fixed cap, and one deterministic discard warning. The product schema uses
  four separate 16-occurrence variation options (regular, bold, italic, and
  bold italic) plus one 256-occurrence scalar-range override option. This makes
  the renderer's per-style cap structural; repeated tags are normalized by
  final occurrence before constructing the renderer's duplicate-free request,
  while every raw accepted occurrence and its provenance remains visible to
  Settings.
- 2026-09-14: A first sandboxed `dart format` mechanically formatted the two
  changed Dart files that needed it, then exited nonzero only while trying to
  update the SDK's global telemetry-session timestamp outside the repository.
  No validation result is claimed from that invocation; formatting and all
  focused checks will be rerun in the normal macOS execution context.
- 2026-09-14: The product schema now has 52 options: four repeatable style-
  specific variation coordinates (16 occurrences each) and one repeatable
  inclusive scalar-range family override (256 occurrences). Tags are exactly
  four printable ASCII bytes, coordinates are finite in
  `-65536...65536`, ranges exclude surrogates and values above `U+10FFFF`, and
  configured families are control-free UTF-8 within 256 bytes. The existing
  repeat collector bounds aggregate mapped-family input at exactly 64 KiB.
  Product projection walks each style in reverse to retain only the final
  occurrence of a tag, then restores precedence order before constructing the
  renderer's immutable, duplicate-free catalog request. Overlapping scalar
  mappings remain ordered and later-wins in the renderer.
- 2026-09-14: Normal product pane creation now injects that immutable request;
  the render-resource configuration includes it in both catalog matching and
  same-generation comparison. A config-only generation change therefore opens
  a new catalog/cache/atlas domain even when family and point size are
  unchanged. Existing panes retain their captured request after reload, while
  subsequent split/tab/window panes receive the accepted new-session request.
- 2026-09-14: Settings receives the five options, syntax, occurrence values,
  provenance, Japanese descriptions, and new-session policy from the shared
  schema. Its bounded runtime line requests font diagnostics only while
  Settings is rendered, shows applied/configured/unavailable axis and override
  counts, match/fallback/missing counts, and at most four 32-scalar face-name
  projections. Ordinary high-frequency surface snapshots do not call the
  native diagnostic copier. The diagnostics export requests it explicitly and
  adds a reviewed `font_diagnostics` object with 190-key privacy audit coverage;
  exported resolution records contain only class, flags, PostScript identity,
  and occurrence count—never face handles, terminal text, or configured scalar
  values.
- 2026-09-14: Normal-context formatting completed with zero residual changes
  and full `dart analyze` reported `No issues found!`. Focused product config,
  Settings document/inspector/editor, effective-config, generated-reference,
  localization, renderer diagnostics/privacy, and config-only CoreText/Metal
  rebuild tests all exited 0. The generated configuration/CLI reference now
  lists all 52 options. `DART_SUPPRESS_ANALYTICS=true make
  product-native-sanitizer` passed four suites and nine artifacts, including
  ASan+UBSan coverage of the renderer library and harness. Runtime
  Developer-JIT/Release-AOT evidence remains reserved for the next ordered
  closure subtask.
- 2026-09-14: The first exact repository gate reached all native/package,
  configuration-reference, localization, and 190-key diagnostics privacy
  checks successfully, then stopped because the checked-in Phase 7 AppKit
  acceptance hashes were stale after the intentional application and native-
  hierarchy test edits. Regeneration changed only the repeated reviewed hashes
  for those two files. A direct next-owner freshness check then confirmed the
  compatibility regression coverage report was also stale; its parser corpus
  still passed 9 cases, 390 input bytes, and 417 split runs. These are expected
  evidence dependencies, not product failures; both reports are regenerated
  before rerunning the exact gate.
- 2026-09-14: The second exact gate passed the refreshed Phase 7 and
  compatibility coverage reports, all configuration/localization/privacy
  checks, differential evidence, application matrix/evidence/acceptance,
  terminfo, and shell integration. It then stopped at the Ghostty P0/P1 gap
  inventory freshness check because this task's reviewed README and
  implementation/test hashes changed. The `TXT-08` classification must remain
  actionable until the next runtime-closure subtask; only deterministic source
  identities are regenerated here before another exact rerun.
- 2026-09-14: After regenerating the Ghostty inventory with the unchanged
  actionable `TXT-08` classification, the final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed in the reviewed
  source/evidence state. It covered all native capability packages,
  configuration/reference/localization and 190-key diagnostics privacy
  checks, Phase 7 and compatibility freshness, differential and real-
  application evidence, terminfo and shell integration, the 102-row Ghostty
  inventory with 93 accepted and four actionable P1 rows, distribution,
  330-file zero-change formatting, clean analysis, security/update/symbol
  suites, and the aggregate `dart_terminal tests passed` marker.
  `git diff --check` passed. The adjacent `dart_appkit` worktree remains clean;
  case-insensitive executable content and filename audits of its native,
  packages, scripts, test, tool, examples, and Makefile surfaces found no
  `terminal`, `dart_terminal`, or `dart-terminal` occurrence. Apple
  notarization and duration-only campaigns remain skipped as authorized. The
  next ordered subtask is bounded Developer-JIT/Release-AOT runtime evidence,
  documentation/matrix closure, and the parent completion decision.
- 2026-09-14: The first bounded runtime-configuration run built, signed, and
  launched the normal Developer JIT bundle, and the application itself exited
  successfully after its font request/diagnostic assertions. The outer
  launcher then rejected the accepted-reload line because it still required
  the pre-font-schema totals `changes=17 new_session=15`; the application now
  correctly reports two live plus 16 new-session changes, or 18 total. Release
  AOT was not reached. This is a stale exact-output assertion, not an
  application reload or font-resolution failure. The launcher will be updated
  to the current totals and both application and launcher markers will state
  the new font-configuration/diagnostic coverage explicitly before rerunning
  both modes.
- 2026-09-14: The corrected bounded
  `make RUNTIME_ARCH=arm64 runtime-configuration-integration` run passed the
  ordinary arm64 Developer JIT application in 1,408 ms and Release AOT
  application in 754 ms. Both exact markers reported four independent panes,
  configuration save/reload, Settings visuals, normal CoreText fallback,
  `font_configuration=true`, and `font_diagnostics=true`. Inside each product
  run, the original pane retained its configured `wght=450`/Menlo override
  catalog while three fresh window/tab/split panes received the accepted
  Menlo request with an intentionally unavailable `wght` axis and an available
  box-drawing override; diagnostics reported one configured/unavailable axis
  and one configured/available override without exposing scalar values. The
  invalid save still caused no reload, and the accepted transaction reported
  exactly two live plus 16 new-session changes.
- 2026-09-14: The `TXT-08` closure evidence is bound to the immutable renderer
  contract, versioned native ABI/CoreText implementation, native and Dart
  regressions, product projection/diagnostics, and the exact two-runtime
  acceptance markers. The matrix now states only the implemented bounds and
  executed behavior. Its actionable gap is removed, leaving three actionable
  P1 rows; generator totals become 94 accepted and three actionable with eight
  reviewed gap records. Generated reports and the exact repository gate must
  still be refreshed and pass before the roadmap parent is complete.
- 2026-09-14: Focused static analysis reported `No issues found!`; the font
  closure inventory test passed both exact-source validation and negatives for
  a weakened override cap and missing runtime marker. Phase 7 AppKit,
  compatibility regression coverage (9 cases, 417 split runs), and Ghostty
  inventory freshness checks all passed after ordered regeneration. The final
  exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed every native
  package, generated/reference/localization and 190-key diagnostics privacy
  check, compatibility/differential/application/terminfo/shell/distribution
  gate, 330-file zero-change formatting, clean root analysis,
  security/update/symbol suites, and aggregate tests, ending with
  `dart_terminal tests passed`. The inventory reports 102 rows, 94 accepted,
  zero actionable P0, and three actionable P1 rows.
- 2026-09-14: Final `git diff --check` passed. The adjacent `dart_appkit`
  worktree is clean; case-insensitive executable content and filename audits
  across native, packages, scripts, test, tool, examples, and Makefile found no
  `terminal`, `dart_terminal`, or `dart-terminal` occurrence outside excluded
  docs/build/cache/git surfaces. No generic-library file changed. Apple
  notarization and duration-only campaigns were skipped as authorized. All
  four font children now pass, so the `TXT-08` roadmap parent is complete; the
  next ordered P1 child is synthetic box/block/braille/Powerline glyphs.

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
