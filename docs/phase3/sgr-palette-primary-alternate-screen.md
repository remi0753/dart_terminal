# Phase 3 — SGR, palette, and primary/alternate screen

- Status: in progress
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after the typed-array screen
- Related: `ROADMAP.md` sections 5.3, 5.5, 6, and Phase 3;
  `FEATURE_MATRIX.md` SCR-01, SCR-05, SCR-09, CAP-05;
  `docs/adr/ADR-003-packed-cell-grid-format.md`;
  `docs/phase3/typed-array-grid-screen-state.md`;
  `docs/phase3/vt-sequence-parser.md`

## Purpose and background

Complete the visible screen's color and rendition state, then introduce the
primary/alternate screen owner required by full-screen terminal applications.
The completed parser already retains semicolon and colon parameters and the
screen action sink already handles narrow-cell editing, but SGR and OSC color
actions are still counted as unsupported and only one visible grid exists.

The implementation must preserve ADR-003's logical color-token and interned
style-ID contracts. Mutable cells remain typed arrays; resource definitions and
screen switching remain Dart-owned, bounded, renderer-independent state.

## Scope

- A bounded style table with stable nonzero IDs for bold, faint, italic,
  underline variants, blink, inverse, conceal, and strike attributes.
- Current and saved rendition state on each screen. Narrow printing stores the
  current foreground, background, and style ID without allocating a cell
  object; reset and cursor save/restore preserve documented invariants.
- SGR application for reset/set/unset attributes, ANSI 16-color foreground and
  background, indexed 256-color, direct RGB, default colors, and valid colon
  forms including underline variants.
- A typed 256-entry xterm-compatible palette plus default foreground/background
  state, monotonic palette generation, validated mutation/reset, and screen
  damage when logical color resolution changes.
- Bounded OSC color mutation for palette entries and default foreground/
  background, including safe rejection of malformed, query, and unsupported
  payloads.
- Primary and alternate `TerminalScreen` ownership with shared immutable style
  definitions and shared palette/default colors, explicit active-screen state,
  deterministic full-snapshot damage on switches, and DEC 47/1047/1048/1049
  mode dispatch.
- Focused unit and whole/split/bytewise parser integration tests.

## Out of scope

- Wide/continuation/grapheme cells, Unicode width policy, resize, and reflow;
  these are the next roadmap item. Both screens have the same fixed dimensions
  in this task.
- Underline color, overline, protected/selective erase, hyperlinks, semantic
  marks, and style/font-feature configuration; these are later P1 tasks.
- OSC palette/default-color query replies and PTY writes; query/reply encoding
  and the PTY write connection remain a later Phase 3 item. Query payloads are
  recognized but do not mutate state.
- Scrollback, viewport, selection/search, renderer resource deltas, snapshot
  wire packing, live application integration, and `TerminalBuffer` removal.
- Theme/configuration loading and system light/dark appearance.

## Dependencies and constraints

- `TerminalScreen` remains a single-writer object. A screen set owns exactly two
  fixed-size screens; callers cannot replace either authoritative grid.
- ADR-003 color tokens remain: zero default, `1..256` palette index plus one,
  and `0x80rrggbb` direct sRGB. Palette entries/default colors contain tagged
  direct sRGB values and never become per-cell resolved pixels.
- Style ID zero remains the default. Nonzero IDs are bounded to `1..65534`, are
  never silently reused, and map to packed immutable attributes in a shared
  table. Current SGR combinations must fit without an attacker-controlled
  unbounded resource table.
- Parser callbacks are synchronous. Malformed/unsupported SGR and OSC input is
  a bounded no-op with an observable counter, never a partial mutation or an
  exception escaping into the byte stream.
- A palette/default change advances resource generation and dirties affected
  visible presentation without rewriting every cell token. Screen switching
  requires a full snapshot because logical rows now refer to another grid.
- Core source imports only Dart SDK libraries and remains independent of
  AppKit, Metal, PTY FFI, and native packages.

## Ordered subtasks

1. **Style table, rendition state, and SGR application**
   - Add bounded packed style definitions, current/saved rendition, rendition-
     aware narrow printing and erase behavior, and SGR parsing for attributes,
     16/256/direct/default colors, and colon forms.
   - Complete when style IDs remain stable/bounded, every supported set/unset
     and color form passes, malformed groups are atomic safe no-ops, cursor
     save/restore/reset invariants pass, and Release AOT/source checks pass.
2. **Palette and default-color mutation**
   - Add the typed xterm-256 default palette, default foreground/background,
     logical color resolution, mutation/reset and resource generation, then
     apply bounded OSC 4/10/11/104/110/111 actions.
   - Depends on subtask 1. Complete when exact palette families, color syntax,
     multi-entry mutation atomicity, reset, malformed/query behavior, damage,
     and whole/split/bytewise input tests pass.
3. **Primary/alternate screen ownership and DEC switching**
   - Add a fixed-size screen set with shared style/palette resources and
     independent grids/state, then dispatch DEC 47/1047/1048/1049 save/switch/
     clear/restore semantics through the active-screen sink.
   - Depends on subtasks 1 and 2. Complete when content/state isolation,
     resource sharing, reset/snapshot/generation behavior, nested/idempotent
     transitions, chunk-independent parser streams, Release AOT, and the parent
     roadmap item all pass.

Each subtask receives its own verification, documentation/roadmap update, and
completion commit. The parent remains incomplete until all three pass. The
split keeps immutable resource identity, mutable color resources, and buffer
ownership as independently reviewable state boundaries.

## Completion criteria

- Supported SGR streams produce stable style IDs and exact logical color tokens
  for both semicolon and colon syntax, independent of parser chunking.
- Every printed narrow cell captures the current rendition. Erase operations
  follow the documented background-color erase policy without retaining text
  attributes accidentally.
- Palette/default changes are bounded, atomic, resettable, generation-tracked,
  and reflected through logical tokens without rewriting authoritative cells.
- Primary and alternate grids never leak content, cursor, margins, wrap, or
  damage state into each other; shared resource IDs/colors resolve identically.
- DEC 47/1047/1048/1049 transitions have deterministic clear/save/restore and
  idempotence behavior and always make the active presentation publishable.
- Formatting, analysis, full tests, focused Release AOT, source-boundary audit,
  diff review, documentation, roadmap progress, and three completion commits
  pass.

## Verification plan

1. Exhaustively test packed style validation/interning and every SGR attribute
   set/unset group, including omitted, zero, semicolon, colon, and invalid
   extended-color parameters.
2. Verify current/saved rendition, print/insert/erase/reset behavior and stable
   per-cell color/style tokens without per-cell objects.
3. Verify all 256 default palette entries by family, default colors, mutation/
   reset/generation/damage, malformed/query no-op behavior, and configured
   limits.
4. Verify primary/alternate isolation and DEC modes using direct transitions
   and representative parser streams as one chunk, every split, and bytewise.
5. Run focused JIT and Release AOT tests, `make test`,
   `make runtime-source-check`, whitespace/diff/scope review, and commit each
   ordered subtask separately.

## Investigation log

- The typed-array screen parent completed at `c5a408f`; the worktree was clean
  when this task started.
- Re-reading `ROADMAP.md` after that commit confirms this combined
  SGR/palette/screen-set item is the first unchecked task. Wide/grapheme and
  resize/reflow must not start until all three ordered subtasks complete.
- ADR-003 fixes logical cell colors and stable interned style IDs but does not
  prescribe a concrete style-table or palette owner. Both screens must share
  these resources so a cell ID/token has one meaning after a buffer switch.
- The parser exposes flattened typed parameter segments with colon-origin
  metadata and raw bounded OSC bytes. SGR/OSC semantics therefore belong in the
  action sink rather than the generated state table.
- The current screen already stores foreground/background/style fields, but
  printing and erase paths always write zero defaults. Cursor save/restore
  currently preserves position only, and the sink counts all SGR/OSC as
  unsupported.
- The first subtask now uses ten packed style bits: bold, faint, italic, a
  three-bit underline kind, blink, inverse, conceal, and strike. The supported
  state space has at most 768 combinations, below the default 4,096-entry hard
  cap; a deliberately smaller injected table is still contained safely by the
  stream sink if exhausted.

## Decisions and alternatives

- Split the roadmap item into style/SGR, mutable palette, and screen-set work in
  dependency order. Implementing both grids before resource ownership is fixed
  would either duplicate IDs or require a migration of existing cell tokens.
- Keep style definitions packed and immutable in a bounded shared table. Store
  only the interned ID in cells and keep current rendition as scalar screen
  state, so printable output does not allocate a style or cell object.
- Keep palette indexes logical in cells and resolve them through shared palette
  state. Rewriting every cell to direct RGB on palette change was rejected
  because it loses palette semantics and makes mutation proportional to the
  entire retained grid.
- Treat erased cells as canonical blank/narrow cells with default foreground
  and style but the current background token. This implements background-color
  erase without accidentally preserving bold, underline, conceal, or other
  text attributes on blank cells.
- Apply one complete SGR sequence to local scalar rendition values and commit
  once. Invalid extended-color or underline groups leave that group unchanged;
  other recognized parameters in the same sequence still apply and every
  rejected group is counted.

## Verification results

### Style table, rendition state, and SGR application

- Focused JIT tests passed for stable default/nondefault style IDs, packed
  attribute and underline round trips, configurable and 16-bit capacity bounds,
  generation idempotence, invalid-bit rejection, and atomic exhaustion.
- Current rendition printing stores exact foreground/background/style IDs.
  Cursor save/restore now restores rendition with position; non-cell reset
  clears current and saved rendition without invalidating immutable definitions.
- BCE tests passed: erase clears content, foreground, and text style while
  retaining the current logical background token.
- SGR tests passed for every P0 attribute set/unset, all six underline values,
  normal/bright 16-color families, indexed colors, direct RGB, defaults, empty
  reset, SGR 21, semicolon and colon forms, and both accepted colon RGB shapes.
- Invalid/short/out-of-range groups are atomic no-ops and counted; supported
  parameters around an unknown parameter still apply. An injected one-entry
  style-table exhaustion remains contained by the sink without stream failure.
- A representative mixed SGR stream produced identical content, logical color
  tokens, resolved style attributes, current rendition, and rejection counts
  as one chunk, at every split including empty edges, and bytewise.
- Final `make test` passed for 45 formatted Dart files, generated-parser-table
  freshness, analysis with no issues, and all repository tests.
- The focused style/rendition/SGR suite compiled and exited successfully as a
  Release AOT executable.
- `make runtime-source-check` passed after staging the new product/test files
  with `tracked=97` and `native_sources=0`.

## Risks and handoff

- Exact compatibility for rarely used SGR/OSC forms will continue in the Phase
  6 differential program; this task must still reject unsupported forms safely
  and cover the P0 forms used by common applications.
- The following resize/reflow task must resize both grids atomically while
  preserving active-screen/resource identity established here.
- Renderer resource-delta encoding must publish style and palette generations
  before cell damage that references them; wire packing remains out of scope.
