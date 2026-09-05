# Phase 3 — Wide/grapheme cells and resize/reflow

- Status: complete
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after SGR/palette/screens
- Related: `ROADMAP.md` sections 5.3, 5.6, 6, 8, and Phase 3;
  `FEATURE_MATRIX.md` SCR-06, SCR-07, TXT-01, TXT-02, QA-01;
  `docs/adr/ADR-003-packed-cell-grid-format.md`;
  `docs/phase0/DT-007-coretext-runs.md`;
  `docs/phase0/DT-009-packed-grid-benchmark.md`;
  `docs/phase3/sgr-palette-primary-alternate-screen.md`

## Purpose and background

Extend the narrow-scalar screen into a Unicode terminal grid that maintains
wide-lead/continuation and extended-grapheme invariants, then allow both screen
buffers to resize and reflow without losing cursor or logical-line identity.

ADR-003 already reserves width flags and grapheme IDs, and rows already carry
soft-wrap plus logical-line metadata. Product code still classifies every
printable scalar as narrow, has no grapheme resource table, and fixes screen
dimensions and typed arrays for life.

Unicode behavior is pinned to Unicode 17.0.0 for deterministic generated data.
The Unicode Consortium publishes `EastAsianWidth.txt`,
`GraphemeBreakProperty.txt`, emoji `Extended_Pictographic`, and conformance
data for that release. The relevant primary references are
[Unicode 17.0.0](https://unicode.org/versions/Unicode17.0.0/),
[UAX #11](https://www.unicode.org/reports/tr11/), and
[UAX #29](https://www.unicode.org/reports/tr29/).

## Scope

- Generated, reviewed Unicode 17 scalar-property tables for terminal width and
  extended grapheme boundaries, with pinned source URLs/checksums and a
  deterministic regeneration tool.
- A streaming extended-grapheme breaker covering CR/LF/control, Hangul,
  Extend/ZWJ, spacing marks, prepend, regional-indicator pairs, extended-
  pictographic ZWJ sequences, and Unicode 17 Indic conjunct rules.
- A bounded immutable grapheme table with stable nonzero IDs, scalar-count and
  cluster-length caps, generation tracking, exact-value interning, and no
  unbounded attacker-controlled retention.
- Width-one and width-two printing over the six SoA arrays, atomic lead/
  continuation writes, grapheme extension, last-column wrapping, and editing/
  erase/scroll operations that never leave orphan leads or continuations.
- A narrow-by-default ambiguous-width policy for the product baseline;
  combining/control/format behavior comes from generated properties, and emoji
  presentation has deterministic terminal width.
- Fixed-resource resize/reflow that returns/replaces bounded typed grids,
  groups soft-wrapped rows by logical-line identity, preserves cells and
  rendition, maps cursor/saved cursor, resets margins safely, and requests full
  snapshots.
- Atomic primary/alternate screen-set resize with shared style/palette/grapheme
  resources and independent content/state.

## Out of scope

- Scrollback pages and reflow beyond currently retained visible rows; paged
  scrollback is the next roadmap item and will extend the same logical-line
  algorithm.
- Configurable East Asian ambiguous width, Unicode version negotiation,
  locale-sensitive width, font measurement, and renderer shaping. The initial
  policy is pinned and renderer-independent.
- Bidirectional terminal layout; terminal columns remain left-to-right even
  when graphemes contain RTL scalars.
- Unicode normalization. Grapheme resources preserve the exact scalar stream;
  canonically equivalent sequences are not silently rewritten.
- Selection/search anchors, hyperlink refcounts, semantic ranges, snapshots,
  PTY resize wiring, and live AppKit integration.
- CoreText glyph/fallback decisions and visual golden images, which remain
  Phase 4 work.

## Dependencies and constraints

- Cell content continues to follow ADR-003: a scalar when the grapheme bit is
  clear, a nonzero shared grapheme ID when set, and zero for continuation.
  Continuations copy lead style/color/link state.
- A wide lead and its continuation are one atomic mutation. No operation may
  expose a wide lead in the last active column, a continuation without an
  immediately preceding wide lead, or a half-overwritten pair.
- Grapheme definitions are immutable shared resources and use weak screen
  observation where resource changes require damage. IDs are never silently
  reused while cells can reference them.
- Unicode source data and generated arrays are development inputs only. The
  product hot path performs binary/range lookup over static typed-compatible
  constants and does not parse files, use regex, or allocate per input byte.
- Ambiguous (`A`) and neutral (`N`) East Asian Width scalars are width one in
  this baseline. `W`/`F` and emoji-presentation clusters are width two;
  combining components alone do not add columns.
- Resize validates target dimensions before allocating or changing either
  screen. Failure leaves the current screen set fully usable.
- Core source remains Dart-only and independent of AppKit, Metal, PTY FFI, and
  native packages.

## Ordered subtasks

1. **Unicode properties, grapheme breaker, and bounded intern table**
   - Pin/generate Unicode 17 tables, implement width/property lookup and
     extended-grapheme boundary state, and add bounded exact scalar-sequence
     interning with resource generation.
   - Complete when generated freshness, representative width policy, official
     grapheme conformance data, invalid scalar rejection, resource caps,
     stable IDs, full tests, Release AOT, and source audit pass.
2. **Wide/continuation/grapheme screen mutation invariants**
   - Replace narrow-only parser printing with classified scalar/grapheme
     application, add atomic wide pairs and combining extension, and repair
     pairs around erase/insert/delete/scroll boundaries.
   - Depends on subtask 1. Complete when edge wrapping, emoji/ZWJ/RI/Hangul/
     Indic/combining cases, style/color propagation, damage, malformed input,
     and whole/split/bytewise streams cannot create invalid cell topology.
3. **Primary/alternate resize and visible-line reflow**
   - Add deterministic grid reflow and atomic screen-set replacement for new
     dimensions while preserving shared resources, logical lines, content,
     active identity, and cursor mappings.
   - Depends on subtasks 1 and 2. Complete when grow/shrink/round-trip and both-
     screen cases preserve invariants, allocation failure is atomic, all new
     grids require full snapshots, Release AOT passes, and the parent roadmap
     item is checked.

Each subtask receives its own verification, documentation/roadmap update, and
completion commit. The parent remains incomplete until all three pass.

## Completion criteria

- Unicode version and width policy are explicit, generated from pinned primary
  data, reproducible, and covered by conformance and boundary tests.
- Every grid row satisfies the scalar/grapheme/wide/continuation contract after
  printing, wrapping, every editing family, scrolling, reset, and screen switch.
- Grapheme/resource memory is capped and malformed or adversarial scalar
  streams cannot throw out of the parser sink or grow state without bound.
- Resize/reflow never publishes partial state, preserves all retained visible
  logical content possible within the target grid, and maps cursors to valid
  cells rather than continuations.
- Both primary and alternate grids resize to the same dimensions atomically and
  continue sharing style, palette, and grapheme meanings.
- Formatting, generated freshness, analysis, full tests, official conformance,
  focused Release AOT, source-boundary audit, diff review, documentation,
  roadmap progress, and three completion commits pass.

## Verification plan

1. Regenerate Unicode tables from pinned files and compare exact output; test
   property range boundaries and all official extended-grapheme cases.
2. Test grapheme table identity/copy isolation, maximum cluster/count/scalar
   storage, no-op reuse, exhaustion, and invalid scalar rejection.
3. Exercise wide/grapheme printing and every editing boundary directly and via
   whole/every-split/bytewise parser input; scan the entire grid invariant after
   every operation.
4. Exercise resize/reflow across narrower/wider and shorter/taller grids,
   wrapped logical lines, wide/grapheme cells, both screen buffers, active and
   saved cursors, margins, damage, and invalid target dimensions.
5. Run focused JIT and Release AOT tests, `make test`, official conformance,
   `make runtime-source-check`, whitespace/diff/scope review, and commit each
   ordered subtask separately.

## Investigation log

- The SGR/palette/primary-alternate parent completed at `0e4a716`; the worktree
  was clean when this task started.
- Unicode properties, breaker, and the bounded grapheme table completed in
  `f9232b6`. The roadmap was reread from a clean worktree; wide/grapheme screen
  mutation is now the first unchecked subtask, while resize/reflow remains
  blocked on canonical cell topology.
- Wide/continuation/grapheme mutation completed in `c2dc78a`. A second clean-
  worktree roadmap review makes atomic primary/alternate resize and visible
  logical-line reflow the current and final child of this parent.
- Re-reading `ROADMAP.md` confirms this Unicode/resize item is the first
  unchecked task. Scrollback must not be implemented before this parent closes.
- The package currently has no Unicode segmentation dependency. `dart:core`
  exposes scalar iteration but not the terminal width or extended-grapheme
  property tables required by this task.
- Unicode 17.0.0 is the current stable release and publishes the required UCD,
  auxiliary, emoji, and conformance files at versioned URLs. Generated product
  tables will pin those inputs rather than follow an unversioned latest URL.
- Existing width flags, logical-line IDs, row flags, ring scrolling, shared
  style/palette resources, and full-snapshot contract provide the required
  storage hooks. Dimensions and all cell/row arrays are currently final, so
  resize must construct validated replacement grids rather than mutate array
  lengths.
- The versioned Unicode inputs were downloaded from the four primary-data URLs
  named above. Their SHA-256 values are pinned in the generator: East Asian
  Width `ea7ce50f...70a33`, Grapheme Break `d6b51d1d...bae89`, emoji data
  `2cb2bb94...7b72b`, and Derived Core Properties `24c7fed1...22c08`.
- Unicode 17 `GraphemeBreakTest.txt` is retained as a test-only conformance
  fixture under its upstream terms-of-use header. The checked-in file has
  SHA-256 `e2d134d2...793ec` and declares 766 executable cases.
- The upstream fixture contains two trailing spaces in its documentation
  header. A path-specific Git whitespace attribute preserves the byte-exact
  source/hash while excluding only those upstream-authored spaces from the
  repository whitespace check.
- The first conformance run reached the end without a boundary mismatch, then
  failed because the local assertion incorrectly expected 770 cases. The
  upstream footer confirms 766; the assertion was corrected without changing
  the breaker.
- Screen mutation currently exposes only caller-classified narrow writes. Raw
  character insertion/deletion and partial rectangular row copies operate cell
  by cell, so each can bisect a future wide pair unless mutation ranges are
  expanded or repaired at their boundaries.
- The first legacy screen test used emoji U+1F600 as a caller-classified narrow
  cell. Enforcing the new width contract correctly rejected it; the storage
  fixture now uses narrow supplementary U+10400 and separately asserts that a
  wide emoji cannot enter through the narrow API.

## Decisions and alternatives

- Split Unicode data/resource work, cell-topology mutation, and resize/reflow
  because each has an independently testable invariant surface. Reflow must not
  begin until wide/grapheme rows are canonical.
- Generate compact range tables from Unicode's versioned primary data instead
  of adding a general string-segmentation dependency. Generic string APIs would
  require rebuilding strings around a streaming parser and would not supply the
  terminal-width policy.
- Preserve exact scalar sequences without normalization. This keeps byte-stream
  behavior deterministic and defers font shaping/normalization choices to the
  renderer.
- Use compact half-open ranges and binary lookup in product code. The
  development generator validates every source file hash, merges only adjacent
  equal-property ranges, and supports an exact `--check`; product code never
  opens or parses Unicode data files.
- Keep grapheme definitions immutable and ID-stable. Capacity, total retained
  scalar count, and per-cluster length are separate hard limits; exact existing
  definitions remain available after exhaustion, while new definitions return
  `null` through the non-throwing path.
- Print a base scalar immediately, then replace its lead content with an
  immutable grapheme ID as later scalars extend it. A fixed pending buffer holds
  zero-width prefixes; exhaustion drops only the unrepresentable extension and
  closes the streaming cluster without throwing from the parser sink.
- Expand erase ranges across any touched wide pair, and run a row-level repair
  after shifting or partial row copies. This keeps cell moves simple while
  ensuring clipping at either horizontal-margin edge cannot publish an orphan.
- A two-column glyph that cannot fit at the current edge wraps before writing.
  If the active region itself has only one column, or auto-wrap is disabled at
  the edge, store narrow U+FFFD as an explicit containment policy.
- Treat every non-print parser callback and every screen-buffer transition as a
  streaming grapheme boundary. This prevents controls, malformed sequences, or
  a return to a previously active buffer from extending a stale cell; grapheme
  components inherit the presentation fields of their existing lead.
- Reflow will construct replacement fixed-length grids and publish them only
  after both primary and alternate builds succeed. Logical lines are consecutive
  rows linked by both soft-wrap metadata and logical-line ID; canonical unused
  trailing blanks are omitted, while cursor positions force enough blank units
  to remain addressable.
- When the new visible height cannot retain every reflowed row, choose a window
  containing the active cursor and otherwise anchor it toward the newest bottom
  rows. The active cursor has priority; a saved cursor outside that window is
  clamped because scrollback is not yet available to retain its row.
- Resize resets vertical/horizontal margins and origin/horizontal-margin modes
  to full-screen-safe defaults, while preserving rendition, cursor presentation,
  insert/auto-wrap/reverse-video modes, compatible tab stops, and shared resource
  identity. Every replacement starts with full-row damage and a required full
  snapshot.

## Verification results

### Unicode properties, breaker, and grapheme table

- The generator accepted all four pinned Unicode 17 inputs only after its
  built-in SHA-256 implementation reproduced the independently measured
  hashes. Regeneration followed by `--check` and a no-change formatter check
  passed; the checked-in table is deterministic and fresh.
- The focused JIT test passed all 766 official Unicode 17 extended-grapheme
  conformance cases. Representative range edges, East Asian ambiguous narrow
  width, W/F width, text/emoji presentation, regional flags, keycaps,
  zero-width components, invalid scalars, reset behavior, immutable copies,
  stable IDs, generation behavior, and all three resource limits also passed.
- The focused test compiled to a Release AOT executable and that executable
  completed successfully from the repository root, including the external
  conformance fixture.
- `make test` passed: dependency resolution, VT generated-table freshness,
  formatting of 53 files, full static analysis, and the complete test runner
  all succeeded.
- `git diff --cached --check` passed after generated output was corrected to
  avoid trailing spaces. The staged-source Dart-only audit passed with 108
  tracked files and zero native source files, so the new product files were
  included in the boundary check.

This completes ordered subtask 1. The parent remains open; screen mutation must
now consume these properties and resources before resize/reflow begins.

### Wide/continuation/grapheme screen mutation

- Focused JIT tests passed direct atomic scalar/grapheme writes, presentation
  field propagation, half-pair overwrite and erase, insert/delete character,
  insert/delete line, full and partial-width scrolling, reset, screen switching,
  one-column/no-wrap containment, and VS16 width growth at the last column.
- Parser integration formed the expected combining, CJK, emoji ZWJ, regional-
  indicator, Hangul, and Indic cells. The final state was identical for a whole
  UTF-8 batch, every byte split position, and one-byte chunks.
- Grapheme table exhaustion, an overlong combining stream, malformed UTF-8, and
  control-separated components completed without an exception or invalid
  topology. A deterministic 768-operation mutation sweep validated the entire
  grid after every operation.
- The dedicated suite compiled to and passed as a Release AOT executable.
  `make test` also passed dependency resolution, VT table freshness, formatting
  of 54 files, full analysis, and the combined test runner.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 109 tracked files and zero native source files, including the new focused
  test and every changed product path.

This completes ordered subtask 2. The parent stays open until atomic primary/
alternate resize and visible logical-line reflow pass.

### Primary/alternate resize and visible-line reflow

- Focused JIT tests passed narrower/wider logical-line reflow, retained styled
  blanks, wide and grapheme cells, logical-line and semantic row metadata,
  active/saved cursor mapping, one-column wide-cell containment, margin reset,
  mode/rendition/cursor/tab preservation, and full-snapshot damage.
- A 7-by-12 resize matrix exercised 84 valid target dimensions, including
  shorter/taller and one-column grids. Every replacement preserved shared
  resources, passed full-grid topology validation, kept both cursor positions
  off continuation cells, dirtied every row, and left its source unchanged.
- Screen-set tests passed independent primary/alternate content reflow, active
  alternate ownership, DEC 1049 restore after resize, palette observation by
  both replacements, and lookup through a parser sink created before resize.
  Invalid row, column, and total-cell bounds left both published screen
  references, contents, and the transition generation unchanged; same-size
  resize was a no-op.
- The focused suite compiled to and passed as a Release AOT executable.
  `make test` passed dependency resolution, VT table freshness, formatting of
  56 files, full analysis, and the combined test runner.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 111 tracked files and zero native source files, including both new
  resize/reflow files. Its first sandboxed invocation stopped before the audit
  when Dart could not update its home-directory telemetry timestamp; rerunning
  with the required filesystem permission completed successfully and did not
  reveal a product failure.

This completes ordered subtask 3 and the parent wide/grapheme resize/reflow
roadmap item. Scrollback remains intentionally absent from visible-only reflow
and is the next ordered task.

## Risks and handoff

- Unicode grapheme conformance does not by itself define terminal column width;
  the explicit narrow-ambiguous/wide-emoji policy must remain separately tested.
- Visible-only reflow necessarily drops logical content that does not fit the
  new visible grid. The next scrollback task must extend reflow input before
  claiming history preservation.
- The renderer will need grapheme resource deltas before damage referencing new
  IDs, following ADR-003 resource-generation ordering.
