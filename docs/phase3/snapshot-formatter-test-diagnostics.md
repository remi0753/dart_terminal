# Phase 3 — Snapshot formatter and readable test diagnostics

- Status: complete
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after query/reply encoding
  and PTY write integration
- Related: ROADMAP Phase 3; FEATURE_MATRIX SCR-12 and QA-01;
  `docs/phase0/DT-010-parser-corpus-snapshot.md`;
  `docs/adr/ADR-003-packed-cell-grid-format.md`

## Purpose and background

The product parser and terminal screen now have enough semantics for recorded
byte streams to be judged by their final state. Existing tests build private,
incompatible lists of strings or integer keys, so a failure usually reports a
test description rather than the row, cell, mode, resource, or parser counter
that differed. Phase 0 accepted a byte-exact corpus and readable action
snapshots, but explicitly left product screen snapshots to Phase 3.

This task provides one deterministic, reviewable terminal-state text format and
bounded comparison diagnostics. The next parser-corpus task can then store
expected product-state snapshots without inventing another formatter.

## Scope

- Define and document a versioned, deterministic text format for a
  `TerminalScreenSet` and for a standalone `TerminalScreen`.
- Include final semantic state needed to diagnose parser-to-screen behavior:
  dimensions, active buffer and 1049 state, viewport/history, cursor and saved
  rendition, margins, modes, tab stops, row/logical-line metadata, exact cell
  content and resources, shared style/grapheme/palette definitions, and optional
  parser-sink counters.
- Render control and non-ASCII content unambiguously while retaining a readable
  row projection.
- Bound rows, cells, resource definitions, and generated output before walking
  caller-controlled terminal state. Refuse an incomplete oracle instead of
  silently truncating it.
- Compare expected and actual snapshots with a bounded, line-oriented diagnostic
  that identifies the first differing line/column and shows nearby escaped
  context.
- Replace the product screen test's private snapshot formatting with the shared
  formatter where doing so validates chunk-independent final state.
- Add focused tests and integrate them into the repository test runner.

## Out of scope

- Snapshot restore or a renderer transfer/wire packet. Restore remains the
  unimplemented part of FEATURE_MATRIX SCR-12 and requires a separate state
  import/invariant design.
- The recorded shell/`less`/`top`/`vim` corpus, property tests, fuzz seeds, or
  the Phase 3 throughput gate. They are the following roadmap task.
- Mutation of damage acknowledgement, viewport position, parser counters, or
  terminal ownership while formatting.
- A user-facing terminal inspector, crash diagnostic bundle, or logging of live
  terminal content.

## Dependencies and confirmed facts

- `TerminalScreen` exposes canonical logical-row accessors for content, colors,
  style/hyperlink IDs, width flags, row flags, logical-line identity, cursor,
  modes, margins, tab stops, and damage metadata without exposing its private
  Struct-of-Arrays storage.
- `TerminalScreenSet` exposes both grids, shared style/palette/grapheme tables,
  bounded primary scrollback, active-buffer state, and one viewport. History
  rows can have a stored width different from the current grid width.
- Alternate projection intentionally reports effective viewport offset zero,
  while a primary offset is retained for later restoration. The formatter needs
  both values, so `TerminalViewport.primaryOffset` exposes that read-only state.
- A grapheme cell stores an interned ID rather than a scalar; exact text requires
  resolving it through the shared `TerminalGraphemeTable`. Continuation cells
  must remain explicit so a wide cell cannot compare equal to a narrow string.
- Generation and dirty ranges describe the mutation path, not only final
  terminal semantics. Including them in the default oracle would make otherwise
  equivalent chunk plans fragile, so the canonical format omits those values.
- Phase 0 uses source-controlled expected text and never rewrites it
  automatically. The Phase 3 comparison API will preserve that review model.
- The repository uses a custom Dart test runner and no external test framework;
  reusable comparison behavior therefore belongs in the terminal-core utility,
  with assertion policy remaining in tests.

## Options and decisions

### One JSON object versus a line-oriented text protocol

JSON is easy to parse but makes a single cell difference noisy and requires a
large nested object before rendering. A versioned line-oriented protocol is
selected: stable section/key ordering and one row or resource per line make
source review and local mismatch context direct. JSON string escaping is reused
for row text and scalar sequences so controls, quotes, combining marks, and
non-ASCII text remain unambiguous.

### Silent truncation versus explicit rejection

Silent truncation could let two different terminal states compare equal. The
formatter instead validates configured row/cell/resource/output limits and
throws a typed snapshot-limit error before returning an oracle. Comparison
diagnostics may truncate their explanatory context because the equality result
is already known and the marker is explicit.

### Full cell arrays versus only readable row text

Readable text alone loses blank-cell colors/styles, hyperlinks, wide
continuations, and interned grapheme identity. The format will emit both a
readable row projection and exact non-default cell records. Default blank cells
are implied by the versioned format. Row metadata is emitted independently.

## Ordered subtasks

1. **Bounded versioned terminal-state formatter**
   - Add the format/options/error API and deterministic screen/screen-set output.
   - Cover primary history, primary/alternate grids, shared resources, Unicode,
     wide/continuation cells, state metadata, optional parser counters, limits,
     and observation-only behavior.
   - Complete when focused tests, analysis, formatting, and the full test suite
     pass and the first child is committed.
2. **Bounded comparison diagnostics and shared test oracle**
   - Add exact comparison plus first-difference/context formatting under a hard
     diagnostic limit.
   - Migrate the existing parser-to-screen chunk-independence snapshot helper to
     the shared formatter and assert useful mismatch output.
   - Complete when focused/all-split tests and the full verification suite pass,
     documentation/matrix are updated, the parent roadmap item is checked, and
     the second child is committed.

The second subtask depends on the stable text emitted by the first. Work on the
later parser-corpus roadmap item must not begin until both are complete.

## Acceptance criteria

- Equal final state produces byte-identical UTF-8 text regardless of parser byte
  chunking.
- A snapshot distinguishes active buffer, history, cursor/saved state, modes,
  tabs, row semantics, wide/grapheme topology, cell resources, and shared
  resource definitions.
- Default formatting has finite documented limits and cannot return a silently
  incomplete oracle.
- A mismatch diagnostic names the first differing line and column, includes
  bounded nearby expected/actual context, and makes control/whitespace changes
  visible.
- Formatting/comparison has no AppKit, Metal, FFI, filesystem, clock, locale, or
  terminal mutation dependency.
- `dart analyze`, focused tests, `make test`, Release AOT execution of the
  focused test, staged diff checks, and Dart-only source audit pass.

## Verification plan

- Focused formatter/diagnostic tests covering empty/default state, styled
  Unicode/grapheme/wide content, history and alternate buffer state, parser
  counters, deterministic ordering, configured limit boundaries, and
  non-mutation.
- Whole-input, every single split, and bytewise parser feeds producing the same
  canonical product-state snapshot.
- Full `make test`, focused Release AOT compilation/execution,
  `git diff --cached --check`, and `make runtime-source-check`.

## Investigation log

- 2026-09-05: reread README, ROADMAP, FEATURE_MATRIX, the Phase 0 parser corpus
  decision, ADR-003, terminal-core ownership/storage APIs, existing screen/parser
  test helpers, package exports, and the custom test runner after commit
  `82238d5`. The worktree was clean and this roadmap item was the first unchecked
  task.
- 2026-09-05: confirmed existing private snapshots are deliberately narrow:
  `vt_parser_test.dart` formats action events, while `terminal_screen_test.dart`
  formats only visible scalar rows and a subset of screen state. Neither can
  faithfully distinguish current shared resources, wide/grapheme topology,
  history, or both buffers.
- 2026-09-05: the first formatting command mistakenly included Markdown files;
  `dart format` correctly rejected them after formatting the new Dart source.
  The chained analysis then reached an SDK telemetry write outside the
  workspace and was denied by the sandbox. Disabling analytics did not suppress
  that SDK session update, so subsequent Dart execution explicitly requests
  that narrow access and formats only Dart paths; no product or document
  content was damaged.
- 2026-09-05: the first focused formatter test expected a protected blank to
  appear as a visible marker in the readable row projection. The formatter
  correctly renders every blank as a space and records protection in the exact
  cell line; the test expectation was corrected to preserve this two-layer
  contract.
- 2026-09-05: migration of the legacy parser-to-screen test initially copied
  its old scalar-row assumptions into new semantic row expectations. The shared
  formatter exposed the real soft-wrap/hard-break relationship and the second
  row's retained logical-line offset. The reviewed expectations now assert
  those stronger values; temporary full-snapshot failure output was removed.
- 2026-09-05: formatter subtask completed in `69bb2d3`. The clean-worktree
  ROADMAP, README, feature matrix, task memo, formatter, and legacy screen test
  reread confirmed bounded comparison diagnostics and shared oracle migration
  as the next unchecked child.

## Verification results

### Bounded versioned terminal-state formatter

- Added a public, Dart-only `TerminalSnapshotFormatter` with format name
  `dart-terminal-state-snapshot` and version 1. It emits stable ordered sections
  for shared style/grapheme/palette resources, primary history, standalone or
  primary/alternate grids, active/1049/viewport state, cursor/rendition,
  margins/modes/tabs, row/logical identity, readable row text, exact non-default
  cells, and optionally an owning parser sink's counters.
- A final pre-commit review found that effective viewport offset alone loses the
  retained primary offset while alternate is active. A read-only
  `TerminalViewport.primaryOffset` accessor and a separate snapshot field now
  preserve both values; the alternate/history test enforces the distinction.
- Default limits admit 20,000 rows, 4,194,304 cells, 4,096 style definitions,
  4,096 grapheme definitions, and 16 Mi UTF-16 output code units. Callers may
  lower each limit. Rows/cells/resources are preflighted and output is checked
  before every appended line; an over-limit snapshot throws
  `TerminalSnapshotLimitException` and no truncated oracle is returned.
- Default blank cells are implied, while any content/resource/protection or
  non-narrow topology produces an exact cell line. The parallel JSON-escaped row
  projection resolves interned grapheme scalars and represents a wide
  continuation with `·`, making ordinary review compact without losing exact
  state.
- Focused tests cover style and grapheme definitions, palette/direct color
  tokens, wide continuation, protected blank cells, row semantics,
  current/saved rendition, custom tabs, retained history, both buffers,
  alternate ownership, parser counters and ownership validation, every limit
  class, deterministic repetition, and preservation of generation, damage,
  full-snapshot, and viewport state.
- A mixed ASCII/CJK/combining/SGR/newline/alternate-screen byte stream produced
  byte-identical version 1 state at every single input split and with one byte
  per parser chunk.
- `dart analyze` passed with no issues. The focused Dart test passed. `make test`
  passed dependency resolution, VT table freshness, formatting of 68 files with
  zero changes, full analysis, every existing unit/integration test, and the real
  PTY suite. The focused formatter test also compiled and passed as a Release
  AOT executable at `/private/tmp/dart-terminal-snapshot-formatter-test`.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 126 tracked files and zero native source files.

This completes ordered subtask 1. Bounded comparison diagnostics and migration
of the shared product-state test oracle are now the first unchecked child.

### Bounded comparison diagnostics and shared test oracle

- Added a public `TerminalSnapshotComparator` that performs exact UTF-16 string
  comparison under a default 16 Mi-character input cap. A match has an empty
  diagnostic; a mismatch records the zero-based offset and one-based line and
  UTF-16 column of the first differing code unit.
- The diagnostic identifies the expected/actual next code unit, JSON-escapes
  nearby lines so spaces, tabs, quotes, and newlines are reviewable, and bounds
  context depth, per-line capture, and total output. Diagnostic truncation is
  explicitly marked and never changes the equality result.
- `TerminalSnapshotComparison.requireMatch` raises a typed
  `TerminalSnapshotMismatchException` containing only the caller description,
  first location, and bounded diagnostic—not either complete snapshot. This is
  independent of an external test framework and can be reused by the next
  corpus harness.
- Focused comparison tests cover exact equality, a tab-versus-space mismatch,
  trailing-newline and end-of-snapshot differences, one-based location, escaped
  expected/actual context, total diagnostic truncation, comparison input caps,
  and the typed assertion path.
- The existing parser-to-screen integration no longer constructs its private
  nine-line state approximation. It uses the shared version 1 formatter,
  verifies reviewed semantic lines, then uses the comparator for every single
  byte split and bytewise input. The migration strengthened coverage by
  preserving soft-wrap, hard-break, and logical cell offset state that the old
  scalar-row projection omitted.
- Focused formatter/comparator and migrated screen suites passed. `dart analyze`
  passed with no issues. `make test` passed dependency resolution, VT table
  freshness, formatting of 69 files with zero changes, full analysis, all unit
  and integration tests, and the real PTY suite. The focused diagnostic test
  compiled and passed as a Release AOT executable at
  `/private/tmp/dart-terminal-snapshot-diagnostics-test`.
- `git diff --cached --check` passed. The final staged-source Dart-only audit
  passed with 127 tracked files and zero native source files.

This completes ordered subtask 2 and its parent. Parser corpus, property tests,
and fuzz seeds are now the first unchecked roadmap item.

## Risks and handoff

- Snapshot format changes are oracle changes. Once parser corpus fixtures adopt
  version 1, incompatible changes require a format-version increment and
  explicit fixture review.
- Exact restore remains unimplemented; formatter output must not be described as
  a persistence or renderer wire format.
- Comparison diagnostics intentionally use UTF-16 columns because Dart string
  offsets use UTF-16 code units. The escaped context remains the preferred way
  to inspect differences adjacent to supplementary-plane scalars.
