# Phase 3 — Paged scrollback, viewport, selection, and search primitives

- Status: in progress
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after Unicode resize/reflow
- Related: `ROADMAP.md` sections 5.3, 5.12, 6, and Phase 3;
  `FEATURE_MATRIX.md` SCR-07, SCR-08, SCR-11, SEC-01;
  `docs/adr/ADR-002-isolate-thread-ownership.md`;
  `docs/adr/ADR-003-packed-cell-grid-format.md`;
  `docs/phase3/wide-grapheme-resize-reflow.md`

## Purpose and background

Retain primary-screen rows that leave the visible grid in a bounded fixed-page
deque, expose a deterministic history-plus-screen viewport, extend reflow to
that retained history, and provide stable primitives for selection and bounded
search. These facilities remain authoritative Dart-owned terminal state and do
not introduce renderer, AppKit, PTY, or native dependencies.

The preceding resize task deliberately reflows only visible rows and documents
that older content is lost when the target height cannot retain it. ADR-003
specifies 256-row fixed SoA pages, O(1) page eviction, independent line/byte
caps, viewport offsets, and logical-line IDs as the basis for reflow and
selection. The current screen already provides canonical wide/grapheme cells,
row flags, and logical-line IDs, but discards full-screen scroll output.

## Scope

- A fixed-page Struct-of-Arrays history deque retaining all six cell fields,
  row flags, logical-line IDs, and the source column width of each page.
- Independent hard limits for retained rows and allocated typed-storage bytes;
  eviction removes complete oldest pages without shifting retained rows.
- Capture only from primary full-screen/full-width upward scrolling. Alternate
  screens and partial scroll regions do not contaminate primary history.
- A viewport over retained history plus the active grid, with a bounded offset,
  bottom-follow behavior, stable accessors, and deterministic response to new
  output, eviction, clear, and screen switching.
- Resize/reflow across retained primary logical lines and the visible grid,
  including wide/grapheme topology and stable logical anchors.
- Ordered selection endpoints, cell/word/logical-line expansion, text
  extraction across soft wraps and hard breaks, and bounded forward/backward
  plain-scalar search over retained logical content.

## Out of scope

- Scrollback compression, disk persistence, spill files, or memory-pressure
  callbacks. Page-granular eviction is the P0 baseline.
- Renderer wire messages, scroll bars, mouse gestures, clipboard integration,
  selection drawing, search UI, or AppKit integration.
- Regex, locale-sensitive word breaking, normalization, case folding, or fuzzy
  search. Search is exact scalar-sequence matching with explicit limits.
- Hyperlink table/refcount implementation and OSC 8 parsing. Existing bounded
  hyperlink cell IDs are retained and available to later hyperlink work.
- Semantic prompt range tables beyond current row classification flags.
- Alternate-screen scrollback or merging alternate contents into primary
  history.

## Dependencies and constraints

- All mutable grid, history, viewport, selection, and search state stays under
  one terminal worker's single-writer ownership from ADR-002.
- Page eviction must be O(1) in retained row/cell count. No removal may shift
  every remaining history row.
- Pages contain at most 256 rows and do not mix source column widths. A column
  change closes the current tail page so retained rows remain self-describing
  until the history-aware reflow subtask replaces them.
- The byte cap counts allocated typed-list payload bytes. Dart object overhead
  is not exactly measurable, so a separate bounded page-count consequence of
  the row cap prevents unbounded container objects.
- Wide leads and continuations remain atomic in history, viewport, reflow,
  selection, and search. Cursor/selection anchors normalize away from
  continuation cells.
- Visible screen damage remains independent of viewport/history generation.
  History and viewport state need their own monotonically increasing revisions.
- A failed allocation or invalid configuration must leave the currently
  published screen set and retained history usable.

## Ordered subtasks

1. **Fixed-page bounded storage and primary capture**
   - Implement a 256-row maximum SoA page and linked page deque, exact typed-
     storage accounting, independent line/byte caps, page-granular eviction,
     row access, clearing, and topology validation.
   - Attach one store to the primary screen and capture outgoing rows only for
     full-screen/full-width upward scroll. Preserve the store across screen
     replacement; alternate and partial-region operations remain isolated.
   - Complete when page boundaries, mixed source widths, both caps, very wide
     rows, repeated eviction, metadata/cell fidelity, reset/resize ownership,
     and full/partial/alternate scrolling are covered in JIT, Release AOT, and
     the full test suite.
2. **History/screen viewport and alternate isolation**
   - Add a bounded viewport offset and row projection over primary history plus
     visible rows, with bottom follow, stable revision, new-output and eviction
     clamping, clear behavior, and alternate-screen projection rules.
   - Depends on subtask 1. Complete when scrolling by rows/pages/to-edge,
     history/screen boundaries, output while scrolled back, eviction, resize,
     and DEC 47/1047/1049 transitions are deterministic.
3. **Scrollback-aware resize/reflow and stable logical anchors**
   - Reflow retained primary history together with visible logical lines,
     repaginate under the same caps, preserve content/metadata/resource IDs,
     and remap viewport plus stable logical positions.
   - Depends on subtasks 1 and 2. Complete when narrower/wider and
     shorter/taller round trips, cross-page logical lines, eviction under a new
     width, cursor/viewport/anchor mapping, both screens, and atomic failure
     behavior pass.
4. **Selection and bounded search primitives**
   - Define stable ordered anchors, cell/word/logical-line ranges, extraction
     rules for soft wraps/hard breaks/wide/grapheme cells, and exact bounded
     forward/backward search over logical scalars.
   - Depends on stable anchors from subtask 3. Complete when reversed/end-
     exclusive selections, evicted anchors, Unicode graphemes, wide cells,
     wrapped lines, semantic row flags, match/result limits, and adversarial
     input remain deterministic and bounded.

Each subtask receives focused tests, verification notes, a roadmap state
update, and one completion commit. The parent remains unchecked until all four
subtasks pass.

## Completion criteria

- Primary history retains canonical cell/row data within both configured hard
  caps and evicts only complete oldest pages in O(1).
- Viewport navigation never reads outside retained history or the visible grid,
  follows new output only when already at the bottom, and is isolated from the
  alternate screen.
- Resize reflows the complete retained primary logical stream possible under
  the target caps and maps cursor, viewport, and public anchors to valid cells.
- Selection extraction and search respect soft-wrap/logical-line semantics,
  wide/grapheme topology, eviction, direction, and explicit work/result limits.
- All code is Dart-only, formatted, analyzed, covered by focused and full
  tests, compiled in Release AOT, source-boundary audited, and committed once
  per ordered subtask.

## Verification plan

1. Test page fill/rollover, mixed-width page rollover, oldest-page eviction,
   line and byte caps, clear, exact counters/revisions, metadata, every cell
   field, and topology after every append/eviction.
2. Test primary capture through direct screen operations and parser actions;
   prove insert/delete/partial-margin/alternate operations do not capture.
3. Test viewport offsets and projections at every history/screen boundary,
   during output, eviction, clear, resize, and screen switches.
4. Test history-inclusive reflow and anchor remapping across page/width/height
   matrices with wide and grapheme content.
5. Test selection/search semantics and hard caps, then run focused JIT and
   Release AOT tests, `make test`, `make runtime-source-check`, whitespace and
   full-diff review before each completion commit.

## Investigation log

- Resize/reflow completed in `c3dccc1`. The worktree was clean, and rereading
  the roadmap made this combined scrollback/viewport/selection/search item the
  first unchecked task.
- The legacy `TerminalBuffer` stores bounded plain strings for the current UI;
  it is not canonical terminal-core history and will not be reused for packed
  cells.
- `TerminalScreen` stores the six ADR-003 cell fields plus row flags and
  logical-line IDs in private typed arrays. A full-screen upward scroll rotates
  its visible row ring and clears outgoing rows, which is the capture point.
- Insert/delete lines and partial-margin scrolls share internal movement
  helpers with ordinary output scrolling. Capture therefore needs an explicit
  full-screen history policy rather than being an unconditional side effect of
  every row-copy operation.
- `TerminalScreenSet` owns shared style, palette, and grapheme resources and
  now atomically replaces both fixed grids on resize. Primary history belongs
  at this ownership boundary and must survive replacement; alternate grids
  must never append to it.
- ADR-003 fixes the initial maximum page size at 256 rows and requires line and
  byte caps independently. Dart `List.removeAt(0)` would shift remaining page
  references, so it cannot satisfy the eviction requirement.
- The scrollback is now attached through a screen-set ownership token. Resize
  activates the replacement primary only after both replacement grids have
  been constructed; a caller retaining the superseded primary cannot append
  rows through the shared history attachment. The store claims exactly one
  attachment, so accidentally supplying it to a second screen set fails while
  leaving the original owner usable.
- Full-screen `scrollUp` is the only capture-enabled screen operation. Index at
  the bottom and parser CSI scroll-up reach that path, while delete-line uses
  the same internal movement helper with capture disabled. Partial vertical or
  horizontal regions fail the full-grid check, and alternate screens have no
  attachment.
- Typed page accounting initially used 17 bytes per allocated cell plus 5
  bytes per row for flags and logical-line ID. Stable reflow anchors require a
  retained `Uint64` logical-cell offset and a `Uint64` logical-line reuse epoch
  per row, bringing current metadata to 21 bytes per row. Page capacity is the
  minimum of configured
  page rows, line cap, and rows affordable under the byte cap. A single row
  larger than the cap clears older history rather than retaining a
  discontinuous suffix with the newest row missing.
- Fixed-page storage/capture completed in `b8e04a4`. The clean-worktree
  roadmap review makes history/screen viewport offset and alternate isolation
  the current child.
- Viewport navigation completed in `09c651b`. The clean-worktree roadmap
  review made scrollback-aware resize/reflow and stable logical anchors the
  current child.
- The existing resize path already extracted and wrapped canonical visible
  cells, but discarded reflowed rows outside the cursor-containing target
  window. History-aware resize must treat retained pages and the primary grid
  as one chronological source, then route rows before that window back into a
  replacement history store.
- ADR-003 explicitly treats 32-bit logical-line IDs as reusable cache aids.
  An anchor containing only that ID and an offset could therefore alias new
  content after screen reset or ID rollover. A 64-bit reuse epoch is retained
  with each screen/history row and included in every public anchor.

## Decisions and alternatives

- Split storage/capture, viewport, history-aware reflow/anchors, and
  selection/search because they have distinct invariants and later pieces
  depend on the earlier state model. None of the later children will be
  implemented before the current child commits.
- Use linked fixed-capacity pages rather than a growable list or per-row
  objects. Linked head/tail removal is O(1); page cells and row metadata remain
  compact typed arrays, and the row cap also bounds the maximum number of page
  objects.
- Count allocated typed payload, not only used cells, against the byte cap. A
  page may choose fewer than 256 rows when the remaining byte allowance or line
  cap cannot fund a full page, but its capacity is fixed for its lifetime.
- Keep source column width per page and start a new page after a width change.
  This avoids rewriting retained content during the storage child and provides
  complete input for the later history-aware reflow child.
- Define viewport offset as rows above the bottom: zero projects the active
  grid, and the primary maximum equals retained history rows. Positive
  navigation moves toward older rows. While scrolled back, each successfully
  appended history row increases the offset so the top projected row remains
  stable; page eviction or clear clamps to the oldest retained row.
- Keep the primary offset while an alternate screen is active, but project the
  alternate grid with an effective offset and maximum of zero. Returning to
  primary restores its clamped position. This keeps application-owned
  alternate contents isolated without discarding an explicit user viewport
  choice.
- During the viewport child, expose raw source columns per projected row so a
  pre-reflow mixed-width history never clips a wide pair. History-aware resize
  now replaces every retained page at the current primary width, while the
  accessor remains self-describing for rows captured between resizes.
- Represent a stable position as screen kind, logical-line ID, logical-line
  epoch, and lead-cell ordinal. Counting canonical lead cells rather than
  display columns keeps the position stable when a width-two cell must become
  a one-column replacement glyph. Continuation coordinates normalize to their
  lead.
- Persist each retained row's logical-cell offset from the beginning of its
  logical line. If page eviction removes only the prefix of a soft-wrapped
  line, its first retained row keeps a non-zero offset; an anchor in the
  removed prefix then fails resolution instead of aliasing the suffix.
- Build the complete replacement history and both replacement screens before
  publishing any state. Only after all validation/allocation succeeds does the
  screen set transfer replacement pages, activate primary ownership, publish
  both grids, and restore either bottom-follow or the anchored viewport top.
- Resolve public anchors only when their row is currently projected by the
  active viewport. An intact off-screen anchor remains stable and resolves
  after navigation brings its physical row into view; an evicted or wrong-
  screen anchor returns no position.

## Verification results

### Fixed-page bounded storage and primary capture

- Focused tests passed exact copying of content, foreground, background,
  style, hyperlink, width/protection flags, wide continuations, grapheme IDs,
  row flags, and logical-line IDs into fixed typed pages.
- Two-row test pages passed fill, rollover, mixed-width rollover, exact
  allocated-byte accounting, independent line- and byte-cap eviction, reduced
  page capacity under a small byte cap, clear/no-op clear revisions, and access
  bound checks. An unrepresentable wide row safely cleared older history.
- A deterministic 4,096-row run repeatedly evicted linked four-row pages while
  remaining at 16 rows/four pages, retaining the ordered newest suffix and
  passing page/counter/cell topology validation throughout.
- Direct and parser-driven tests passed primary full-screen single/multi-row
  capture. Partial vertical/horizontal regions, delete-line movement, reverse
  scrolling, and DEC 47/1049 alternate output did not append. Screen reset and
  atomic resize preserved store identity, and a superseded primary reference
  could no longer mutate history. Conflicting attachment reuse was rejected
  without disrupting the first screen set.
- The first full-suite run exposed one analyzer import-order info in the test
  aggregator while all executable tests passed. The import was sorted; the
  final focused analysis and `make test` passed with no issues, including VT
  table freshness, formatting of 58 files, full analysis, and all tests.
- The focused suite compiled to a Release AOT executable and completed
  successfully.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 114 tracked files and zero native source files, including the new page
  store and focused test.

This completes ordered subtask 1. The parent remains open; viewport state and
alternate-screen projection are now the first unchecked child.

### History/screen viewport and alternate isolation

- Focused tests passed bottom projection, row and page navigation, top/bottom
  jumps, offset clamping, history/screen boundary mapping, raw source column
  widths, row metadata, all six cell fields, wide-pair topology, and cursor
  visibility inside or outside the projected rows.
- While scrolled back, new output increased the offset and retained the same
  top row. Page-granular eviction preserved the anchor while retained and
  clamped to the new oldest row after eviction. Explicit history clear reset
  to bottom, including when more output arrived before the viewport next
  observed the clear; a separate continuity generation prevents reviving the
  invalidated old offset.
- DEC 47, 1047, and 1049 tests projected alternate contents only at offset
  zero, made alternate navigation a no-op, and restored the preserved primary
  offset on return. Screen-set resize retained the same viewport object,
  updated its dimensions/revision, and exposed old-history/current-screen
  source widths without clipping a wide pair.
- Viewport generation stayed unchanged for repeated reads and advanced for
  navigation, active-grid/history changes, screen transitions, and resize.
  Invalid projected rows and source columns were rejected.
- `make test` passed VT table freshness, formatting of 60 files, full static
  analysis with no issues, and the complete test runner. The focused viewport
  suite compiled to a Release AOT executable and completed successfully.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 116 tracked files and zero native source files, including the viewport
  projection and its focused test.

This completes ordered subtask 2. The parent remains open; scrollback-aware
resize/reflow and stable logical anchors are now the first unchecked child.

### Scrollback-aware resize/reflow and stable logical anchors

- Focused tests passed narrower/shorter and wider/taller round trips over a
  logical line spanning one-row page boundaries and the history/screen
  boundary. Reflow repaginated every retained row at the target width under
  the original line/byte/page caps, moved content between history and the
  visible grid, and preserved cursor and viewport-top mappings.
- Wide cells, continuations, interned graphemes, colors, styles, hyperlinks,
  protection flags, semantic row flags, and logical identities survived
  history-inclusive reflow. A one-column target produced narrow U+FFFD while
  its lead-cell ordinal anchors remained stable.
- Page-prefix eviction retained non-zero logical offsets for the remaining
  suffix and made removed anchors unresolved. Separate hard-line cap tests
  also proved reflow eviction does not exceed allocated-byte or row limits.
- Logical-line reuse epochs prevented an anchor made before `resetScreen()`
  from resolving to a new row with the same 32-bit logical-line ID. Epochs are
  copied through row movement, scrollback capture, reflow, and public viewport
  metadata.
- Primary history remained isolated while alternate mode was active. Resize
  preserved alternate ownership/content and the hidden primary viewport
  anchor. Invalid dimensions left both screen objects, history bytes/content,
  viewport offset, and transition generation unchanged; same-size resize was
  a no-op.
- During test development, an initial wide/grapheme expectation omitted the
  cursor-retained blank row, and a shortened viewport expectation attempted to
  resolve an intact but off-screen anchor. Both tests were corrected to match
  the existing cursor-preserving reflow and visible-only resolution contracts.
  An attempted all-ones unsigned Dart integer bound evaluated as negative, so
  public 64-bit values use the native signed maximum. The first sandboxed
  analyzer retry also required the approved environment because Dart tried to
  update its home-directory telemetry timestamp.
- Focused static analysis and the history/reflow/scrollback/viewport/screen
  suites passed. `make test` passed VT table freshness, formatting of 61 files,
  full static analysis with no issues, and the complete test runner. The new
  focused suite compiled to a Release AOT executable and completed
  successfully.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 117 tracked files and zero native source files.

This completes ordered subtask 3. The parent remains open; selection
extraction, word/logical-line semantics, and bounded search are now the first
unchecked child.

## Risks and handoff

- Whole-page eviction can retain fewer than the nominal line cap when the
  oldest page must be removed to satisfy one additional row. Tests and public
  counters must make this deliberate page-granular behavior explicit.
- Very wide rows can make a 256-row page too large for the byte cap. Page
  capacity must be reduced deterministically or the row must be declined
  without allocating beyond the cap.
- History-aware reflow temporarily requires old plus replacement storage and
  an intermediate bounded-by-input cell model. All fallible construction now
  precedes publication, so allocation failure leaves the old state reachable;
  peak memory can still exceed the configured steady-state history cap during
  a resize and remains a performance consideration for future profiling.
