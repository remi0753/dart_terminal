# Phase 3 — Typed-array grid, cursor, margins, tab stops, and modes

- Status: in progress
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after the product VT parser
- Related: `ROADMAP.md` sections 5.3, 6, and Phase 3;
  `FEATURE_MATRIX.md` SCR-01 through SCR-04, SCR-09, CAP-01, CAP-02;
  `docs/adr/ADR-003-packed-cell-grid-format.md`;
  `docs/phase0/DT-009-packed-grid-benchmark.md`;
  `docs/phase3/vt-sequence-parser.md`

## Purpose and background

Introduce the authoritative, renderer-independent visible terminal screen that
consumes the completed parser's typed actions. The screen must use the accepted
Struct-of-Arrays cell contract, keep cursor/margin/tab/mode state explicit, and
apply narrow-cell VT editing operations deterministically without per-cell Dart
objects.

The current `TerminalBuffer` remains the application-facing bounded plain-text
projection until the grid is complete enough to replace it safely. This task
does not connect live PTY output or change the AppKit `TextView` path.

## Scope

- Product SoA cell storage matching ADR-003: content, foreground, background,
  style, hyperlink, and width/flags typed arrays with fixed validated bounds.
- Typed row version, dirty interval, row flags, and logical-line identity
  metadata, plus a monotonic screen generation.
- Cursor position, saved cursor, visibility/blink/shape, wrap-pending state,
  default tab stops, and validated tab-stop mutation.
- Top/bottom and left/right margins, origin/insert/replace/autowrap/reverse-video
  screen modes, reset behavior, and cursor clamping invariants.
- Narrow-scalar printing and the current item's C0/ESC/CSI screen operations:
  movement, tab, BS, CR, LF/IND/RI/NEL, erase, insert/delete characters and
  lines, scroll up/down, margin changes, save/restore, tab-stop changes, and
  relevant mode changes.
- A `VtParserSink` adapter that applies supported screen actions, ignores
  syntactically valid but unsupported sequences without corrupting state, and
  records parser rejection counters without retaining input chunks.
- Deterministic unit/integration tests for typed storage, damage coalescing,
  bounds, reset, modes/margins, screen editing, scrolling, parser chunk
  independence, and invariants.

## Out of scope

- SGR/style interning, palette/default color mutation, and primary/alternate
  screen switching; these are the next roadmap item.
- Wide cells, combining marks, grapheme interning, Unicode-width policy,
  resize, and reflow; these belong to the following roadmap item. This task
  accepts only printable width-one scalars into grid mutation APIs.
- Scrollback pages, viewport, selection, search, hyperlinks, semantic marks,
  query/reply encoding, PTY connection, snapshot formatter infrastructure, or
  renderer damage wire packing.
- Live application integration or removal of `TerminalBuffer`.
- Legacy charset translation and application input-mode encoding.

## Dependencies and constraints

- The terminal-engine owner is the only writer; the grid exposes scalar/cold
  inspection APIs but not mutable authoritative typed arrays outside the core.
- ADR-003 fixes the six-array 17-byte logical cell layout and row metadata.
  Default style/color/link values remain zero until later tasks implement their
  semantics.
- Initial hard limits are 4,096 rows, 4,096 columns, and 1,048,576 visible
  cells. Multiplication and bounds are validated before allocations.
- Erased blanks use content zero with narrow width flags. This task must not
  create continuation, wide, or grapheme cells owned by later tasks.
- All cursor/margin/edit operations preserve coordinates within the active
  grid and prevent partial mutations on invalid public arguments.
- Dirty ranges are half-open and coalesce per physical row. A clean row is
  `(columns, 0)`; its row version increments only when first made dirty after a
  damage clear. Generation is monotonic for each effective state mutation.
- Parser callbacks are synchronous and must not recursively call the parser.
  Unsupported final bytes are safe no-ops, not exceptions from the hot stream.
- Core source imports only Dart SDK libraries and remains independent of
  AppKit, Metal, PTY FFI, and native packages.

## Ordered subtasks

1. **SoA storage, row damage, cursor, and tab-stop foundation**
   - Add validated dimensions/limits, six private typed cell arrays, row
     metadata, monotonic generation, narrow-cell inspection/mutation, cursor
     and saved cursor state, default every-eight-column tab stops, damage
     clear/full-mark APIs, and invariant-focused tests.
   - Complete when exact storage sizes/defaults, row damage/version semantics,
     cursor/save/restore, tab-stop behavior, argument rejection, and Dart-only
     source checks pass.
2. **Margins and screen modes**
   - Add top/bottom and left/right margin contracts, origin/insert/autowrap/
     reverse-video and cursor presentation modes, reset behavior, home/clamp
     rules, and state-transition tests.
   - Depends on subtask 1. Complete when invalid margin updates are atomic,
     mode/reset/save invariants pass, and no editing/parser semantics are
     prematurely embedded.
3. **Editing operations and parser action sink**
   - Add narrow printing, wrapping, movement, erase/insert/delete/scroll,
     C0/ESC/CSI dispatch, supported mode/margin/tab operations, safe unknown
     handling, rejection counters, and whole/split/bytewise integration tests.
   - Depends on subtasks 1 and 2. Complete when supported VT streams produce
     chunk-independent grid/cursor state, boundary/invariant tests and Release
     AOT execution pass, the parent roadmap item is checked, and one final
     subtask commit leaves a clean worktree.

Each subtask receives its own verification, documentation/roadmap progress
update, and completion commit. The parent remains incomplete until all three
subtasks pass. The split is necessary because the item spans independent
storage/state, policy, and parser-integration review surfaces; committing them
in dependency order avoids an unreviewable single change.

## Completion criteria

- Every authoritative cell and row field is typed storage with no per-cell
  object identity, bounded before allocation, and consistent with ADR-003.
- Cursor, saved cursor, margins, tab stops, and supported modes retain valid
  state through resets and every operation.
- Narrow printing and editing cover SCR-04 without implementing later SGR,
  wide/grapheme, reflow, scrollback, or protocol-query work.
- Supported parser streams are deterministic for whole, every split, empty
  edge chunks, and bytewise delivery; malformed/rejected input cannot corrupt
  or grow grid state.
- Row damage/version and screen generation are monotonic/coalesced according to
  their documented scopes.
- Formatting, analysis, full tests, focused Release AOT, source-boundary audit,
  diff review, documentation, roadmap progress, and three completion commits
  pass.

## Verification plan

1. Test exact typed storage/default state and every public argument boundary.
2. Test damage merging/version increments and monotonic generation using
   multiple edits before and after damage consumption.
3. Test cursor/save/tab/margin/mode invariants independently of parser input.
4. Test every editing family at first/last row/column and partial/full margins.
5. Replay a representative VT stream as one chunk, every split, and bytewise;
   compare typed grid state, cursor, modes, and damage metadata.
6. Run focused JIT and Release AOT tests, `make test`,
   `make runtime-source-check`, whitespace/diff/scope review, and commit each
   ordered subtask separately.

## Investigation log

- The parser task completed at `0822d4e`; the worktree was clean when this task
  started.
- Re-reading `ROADMAP.md` after that commit confirms this grid item is the first
  unchecked task. The SGR/palette/primary-alternate task must not be started
  until the parent and all three subtasks complete.
- `TerminalBuffer` owns application input/history and a bounded plain-text PTY
  projection using growable Dart lists/strings. Replacing or wiring it now
  would mix UI migration with the core state-machine task, so it remains
  unchanged.
- The accepted ADR-003 and Phase 0 benchmark establish six SoA cell arrays,
  fixed row metadata, half-open dirty intervals, zero canonical blanks,
  logical-line IDs, and bounded dimensions. The Phase 0 `PackedGrid` is a
  performance/wire prototype, not product code; this task may reuse the frozen
  contract but must implement product invariants and operations in `lib/`.
- ADR-003 assigns resize/reflow, wide/grapheme cells, intern resources,
  scrollback pages, and the damage wire codec to later work. Current storage
  reserves the fields but must keep their later-only values at defaults.
- The first subtask implements the accepted 17-byte-per-cell six-array layout,
  13-byte-per-row metadata, a byte per tab stop, logical-to-physical ring
  addressing reserved for later scroll operations, and no mutable typed-array
  escape hatch. Canonical blank cells are zero content with narrow flags.
- A new screen begins with clean row intervals but requires a full snapshot;
  renderer acknowledgement is explicit and does not mutate terminal content.
  Row-version rollover marks every row fully dirty and restores nonzero
  versions so later renderer work can resynchronize without ambiguous wrap.
- The second subtask adds typed mode/presentation fields without interpreting
  parser bytes. Vertical margins remain the always-defined scroll region;
  horizontal margins have stored values but their active bounds expand to the
  full row unless the dedicated mode is enabled.
- Origin-mode and successful margin changes home the cursor through one
  internal mutation path that also clears wrap-pending. Disabling horizontal
  margins restores the full-width stored range, and disabling autowrap clears
  an otherwise impossible pending wrap.
- Reverse-video changes presentation of every existing cell, so it marks every
  row dirty without rewriting color tokens. Cursor presentation affects only
  overlay state and advances the screen generation without cell damage.

## Decisions and alternatives

- Use one product `TerminalScreen` owner for the visible SoA grid and its
  cursor/tab state. Splitting every field into separately mutable public
  objects was rejected because it would weaken the single-writer invariant;
  exposing raw typed arrays was rejected because callers could bypass damage
  and generation tracking.
- Keep ADR-003's six cell arrays and five row arrays private, with scalar
  inspection and validated mutation methods. Cold snapshots/renderer packing
  can copy logical spans later without turning cells into objects.
- Use a factory to validate rows, columns, and cell-count limits before any
  typed-array allocation. This prevents an invalid dimension request from
  becoming a memory allocation attempt.
- Start each row with a nonzero logical-line ID, zero content/style/color/link,
  narrow width flags, and clean damage `(columns, 0)`. Default tab stops occupy
  zero-based columns 8, 16, and so on; column zero is not a tab stop.
- Track a monotonic screen mutation generation separately from row versions.
  A row version advances only when a clean row first becomes dirty, while
  repeated pre-publication edits only widen its half-open dirty interval.
- Represent screen modes with a typed enum and keep cursor presentation as a
  typed shape plus visibility/blink booleans. A single `insert` boolean defines
  insert versus default replace behavior; no separate contradictory replace
  flag is stored.
- Store vertical and horizontal margin pairs independently. Vertical margins
  are always the scroll region; horizontal margins become active only while
  the horizontal-margin mode is enabled. Successful margin/origin-mode changes
  home the cursor, while invalid ranges are validated before any state change.
- Make state reset explicitly non-destructive to cells. It restores cursor,
  saved cursor, margins, tab stops, wrap-pending, presentation, and screen modes
  in one generation step; the later editing subtask composes this with screen
  clearing for the RIS parser action.

## Verification results

### SoA storage, cursor, tab-stop, and damage foundation

- Focused JIT tests passed for exact storage byte accounting, default cell/row
  state, pre-allocation dimension/cell-count rejection, all field token bounds,
  atomic invalid mutations, canonical narrow/protected cells, and private-state
  scalar inspection.
- Damage tests passed for half-open interval coalescing, row metadata full-row
  damage, one row-version step per clean-to-dirty cycle, damage clearing,
  mark-all idempotence, logical-line and row-flag validation, and monotonic
  effective-mutation generation.
- Cursor position/save/restore tests passed at valid and invalid boundaries.
  Default/custom/cleared/restored tab-stop queries and no-op generation behavior
  passed, including edge clamping when no further stop exists.
- Final `make test` passed for 42 formatted Dart files, generated-parser-table
  freshness, analysis with no issues, and the complete repository test entry
  point.
- The focused screen suite compiled to Release AOT and exited successfully.
- `make runtime-source-check` passed with `tracked=93` and
  `native_sources=0` after staging the new product source.
- Final whitespace/staged-scope/diff review passed, and the first subtask was
  committed as `a76b9a8 Add typed-array terminal screen storage`.

### Margins and screen modes

- Focused JIT tests passed for default and custom top/bottom and left/right
  margins, inactive versus active horizontal bounds, origin homes, explicit
  margin clamp, full-range reset, and atomic rejection of every invalid range.
- Typed origin/insert/replace/autowrap/reverse-video/horizontal-margin mode
  defaults and transitions passed. Disabling autowrap clears pending wrap,
  setting pending wrap while disabled is rejected, and reverse-video dirties
  all rows without modifying cell values.
- Cursor block/underline/bar shape, visibility, and blink state passed. The
  non-cell reset restores cursor/saved cursor, margins, modes, presentation,
  wrap state, and default tab stops while preserving existing cell content;
  resetting an already-default state is generation-idempotent.
- Final `make test` passed for 42 formatted Dart files, parser table freshness,
  analysis with no issues, and all repository tests.
- The updated focused screen suite compiled and passed in Release AOT.
- `make runtime-source-check` passed with `tracked=93` and
  `native_sources=0`.
- Final whitespace, staged-scope, and diff review passed; only the second
  subtask completion commit remains.

## Risks and handoff

- Later SGR and wide/grapheme work will extend cell mutation but must preserve
  the storage and damage invariants frozen here.
- A parser sink implemented before the direct screen operations are stable
  could conceal incorrect VT semantics behind integration snapshots; it is
  therefore the last subtask.
