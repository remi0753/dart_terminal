# ADR-003: Packed cell/grid and damage format

- Status: Accepted for Phase 0
- Date: 2026-09-01
- Decision owners: Dart Terminal project
- Related: ROADMAP sections 4, 6, 7, 9, and 10; ADR-001; ADR-002; DT-009

## Context

The terminal-engine isolate is the single writer for a pane's parser, grid,
scrollback, and modes. A realistic terminal workload repeatedly updates cells,
scrolls rows, marks damage, and sends only the latest changed state to a render
coordinator. One Dart object per cell would make memory, allocation, traversal,
serialization, and GC behavior depend on VM object layout and would turn frame
transfer into object-graph copying.

The representation must cover Unicode scalars and interned graphemes, style,
foreground/background color, wide-cell continuity, protected cells,
hyperlinks, row wrapping, semantic marks, reflow identity, and renderer cache
invalidation. It must also reject malformed or future wire data rather than
guessing its layout.

DT-009 compared a 100,000-cell Struct-of-Arrays grid with mutable cell objects.
Cell objects were faster for a synthetic full-field sweep in most runs. SoA,
however, used about 1.74 MB versus 8.01 MB retained RSS, packed a full renderer
message in 237–272 us p95 versus 622–672 us, and transferred in 164–184 us p95.
The choice therefore rests on bounded ownership and the actual transfer path,
not on a claim that every typed-array loop is faster.

This is an original Dart terminal-core format. It does not copy Ghostty's grid
or expose Ghostty/`libghostty` structures.

## Decision

Use a Dart-owned **Struct of Arrays** for mutable cells, fixed metadata arrays
for rows, fixed-page/ring ownership for scrolling, intern tables for variable
resources, and a little-endian versioned **columnar damage message** between
the terminal-engine and render-coordinator isolates.

No authoritative terminal cell is a Dart object. A short-lived object may
represent a command, range, test fixture, or cold-path API result, but hot grid
storage and damage are typed data.

## Mutable cell layout

The six arrays have identical `rows × columns` lengths and are indexed by the
same physical cell offset.

| Field | Type | Bytes | Version-1 meaning |
| --- | --- | ---: | --- |
| `content` | `Uint32List` | 4 | Unicode scalar, zero blank/continuation, or grapheme intern ID |
| `foreground` | `Uint32List` | 4 | logical foreground color token |
| `background` | `Uint32List` | 4 | logical background color token |
| `style` | `Uint16List` | 2 | style-table ID; zero is default |
| `hyperlink` | `Uint16List` | 2 | hyperlink-table ID; zero is none |
| `widthFlags` | `Uint8List` | 1 | width kind and cell flags |

The deterministic payload is 17 bytes per cell. Selection, cursor, search
matches, hover, IME preedit, and renderer animation are overlay state and are
not copied into every cell.

### Content and width invariants

`widthFlags` version 1 uses:

| Bits | Meaning |
| --- | --- |
| 0–1 | `0` continuation, `1` narrow/blank, `2` wide lead, `3` invalid |
| 2 | `content` is a nonzero grapheme-table ID rather than a scalar |
| 3 | DEC protected cell |
| 4–7 | reserved and zero |

When bit 2 is clear, nonzero `content` must be a Unicode scalar and never a
surrogate. Zero in a narrow cell is the canonical erased blank; the renderer
treats it as a space without inventing a stored object. A continuation has
zero content, follows a wide lead, and carries matching style/color/link state
so row slicing and selection do not require a leader lookup for decoration.
The last column cannot contain a wide lead unless the active terminal mode's
wrap operation also creates the corresponding next-row state atomically.

Grapheme entries hold immutable scalar sequences and measured terminal width.
They are interned by value. A grapheme ID is not a CoreText handle and never
crosses the native boundary without its resource definition.

### Color and intern IDs

A color token is logical terminal state, not a premultiplied Metal color:

- `0` means the active default color;
- `1..256` means ANSI palette index `token - 1`;
- bit 31 set means direct sRGB in bits 0–23, with bits 24–30 zero;
- all other values are invalid in format version 1.

Style ID zero is the default style. Style entries contain terminal decoration
and font-feature state such as bold/faint, italic, underline kind/color,
strike, overline, blink, inverse, and invisible. Hyperlink ID zero means none.
IDs `1..65534` are valid; `65535` is reserved as invalid/overflow. Table
exhaustion triggers compaction or a new resource generation and full snapshot,
never silent ID reuse.

Images are sparse placement/resources with refcounts and generations; they are
not another field in every cell. The same is true for semantic prompt metadata
that spans rows.

## Row and scrollback layout

Each physical row has parallel metadata:

| Field | Type | Meaning |
| --- | --- | --- |
| version | `Uint32List` | increments when a clean row first becomes dirty |
| dirty start/end | two `Uint16List`s | half-open changed interval; clean is `(columns, 0)` |
| flags | `Uint8List` | wrapping and semantic row classification |
| logical-line ID | `Uint32List` | groups physical rows for reflow/selection |

Row flag bits are: bit 0 soft-wraps to the next row, bit 1 prompt, bit 2
command, bit 3 output, and bit 4 hard break. Bits 5–7 are reserved and zero.
Detailed semantic ranges remain a separate bounded table; these bits are fast
classification hints.

Multiple mutations before damage publication coalesce into one dirty interval
and one row-version step. Disjoint edits may include unchanged cells between
them; version 1 prefers a bounded single interval over allocating a range list.
Wrap, logical-line, or row-flag changes also dirty the affected row.

Visible rows are a logical-to-physical ring. Scrolling rotates the first-row
slot and clears only newly exposed rows. Scrollback is a deque of fixed-size
SoA pages (initially 256 rows per page); page eviction is O(1) and never shifts
all retained lines. Scrollback line/byte caps are configured independently.

Row version and logical-line ID rollover force a generation reset and full
snapshot. They are cache aids, not globally unique identities; the 64-bit pane
and damage generations remain authoritative.

## Damage wire format version 1

All integers are little-endian. All section starts are 8-byte aligned. The
format magic is `DTGD` (`0x44475444` when read little-endian).

### 80-byte header

| Offset | Type | Field |
| ---: | --- | --- |
| 0 | `u32` | magic |
| 4 | `u16` | format version (`1`) |
| 6 | `u16` | header bytes (`80`) |
| 8 | `u64` | monotonic damage generation; zero invalid |
| 16 | `u64` | required resource generation; zero invalid |
| 24 | `u32` | grid columns |
| 28 | `u32` | grid rows |
| 32 | `u32` | damaged row-record count |
| 36 | `u32` | packed damaged-cell count |
| 40 | `u32` | row-record offset (`80`) |
| 44 | `u32` | content section offset |
| 48 | `u32` | foreground section offset |
| 52 | `u32` | background section offset |
| 56 | `u32` | style section offset |
| 60 | `u32` | hyperlink section offset |
| 64 | `u32` | width/flags section offset |
| 68 | `u32` | exact total bytes |
| 72 | `u32` | bit 0 full snapshot; other bits zero |
| 76 | `u32` | reserved zero |

### 24-byte row record

| Offset | Type | Field |
| ---: | --- | --- |
| 0 | `u32` | logical viewport row |
| 4 | `u32` | row version |
| 8 | `u32` | logical-line ID |
| 12 | `u32` | first cell in packed sections |
| 16 | `u16` | first grid column |
| 18 | `u16` | cell count |
| 20 | `u8` | row flags |
| 21 | `u8[3]` | reserved zero |

Records are in strictly increasing logical-row order. Cell offsets are
contiguous and their final sum equals the header cell count. Following the row
records are aligned `u32 content[]`, `u32 foreground[]`, `u32 background[]`,
`u16 style[]`, `u16 hyperlink[]`, and `u8 widthFlags[]` sections. Alignment
padding is zero.

The decoder recomputes every offset and total length; it does not accept merely
non-overlapping sections. It rejects truncation, unsupported version/flags,
nonzero reserved data, zero/out-of-range dimensions, duplicate/reordered rows,
out-of-range spans, noncontiguous cell offsets, unknown row flags, and resource
generation mismatch before using the arrays. Cell semantic flags are checked
while the renderer consumes the arrays.

## Resource and generation ordering

Variable graphemes, styles, hyperlinks, images, and font-feature keys travel as
separate versioned resource deltas. The render coordinator must apply and
acknowledge resource generation `N` before accepting damage that requires `N`.
It may keep resources required by a newer queued generation while dropping an
older visual damage message. Unknown IDs trigger a deterministic resync/full
snapshot, not replacement glyph guessing.

Damage generation is strictly increasing per pane. A receiver rejects stale or
duplicate generation. Full snapshots are reserved for first attach, resize or
reflow, palette/font/resource-table reset, renderer recovery, and explicit
resync. Normal output sends dirty rows only.

## Limits

Wire widths are not allocation permission. Initial product hard limits are:

- columns at most 4,096 and rows at most 4,096;
- visible grid at most 1,048,576 cells;
- one damage message at most 32 MiB;
- cell/row count multiplication and every aligned offset checked before
  allocation or typed-view creation;
- style and hyperlink IDs at most 65,534, with lower configurable table caps;
- grapheme/resource bytes, image bytes, and scrollback bytes separately
  bounded.

The wire's `u16` column fields support up to 65,534 columns so an additive
increase within that range does not change layout, but runtime caps may only be
raised with memory and latency evidence.

## Evidence and performance contract

DT-009's final release-AOT runs on the Phase 0 M1 baseline measured:

- full 100,000-cell SoA packet: 237–272 us p95, 1,704,880 bytes;
- 4,096-cell sparse update plus packet: 27–30 us p95, 70,480 bytes;
- one-row ring scroll: 1 us p95;
- object-to-wire packet: 622–672 us p95;
- transferable full packet: 164–184 us p95, 12.8–14.0 GiB/s.

The release gate remains p95 below 4 ms for a 100,000-cell full pack and below
1 ms for the representative sparse packet on the baseline machine. DT-011 also
records p99/max because allocation/scheduling outliers were observed during
exploratory runs.

## Alternatives rejected

### One mutable Dart object per cell

Rejected despite its favorable synthetic sweep result. It retained roughly
4.6× the memory and required scalar object-to-wire serialization, while cell
identity provides no terminal semantic value.

### Native authoritative grid

Rejected because it moves parser/grid semantics across the project's defining
Dart boundary, adds shared-state synchronization, and does not remove the need
for versioned renderer data.

### Padded AoS as the mutable and wire layout

Rejected for version 1 because fixed alignment expands every cell and prevents
bulk copies of individual fields. A measured array-of-small-SoA-blocks may be
proposed later if cache profiles show repeated SoA traversal misses the parser
or render budget; wire versioning and single-writer ownership must remain.

### Multiple dirty ranges per row

Rejected initially because range-list allocation and message overhead cost more
than copying the occasional unchanged span. It requires corpus evidence and a
new/additive wire representation.

## Consequences

- Grid memory and transfer size are deterministic and independent of Dart
  object layout.
- Parser and grid tests can snapshot typed state without native code.
- Packing copies changed fields once; `TransferableTypedData` then transfers
  ownership to the renderer.
- Intern tables and resource-generation recovery are required complexity.
- Some full-field Dart loops may be slower than object loops; benchmark-driven
  block grouping/vectorization is allowed without restoring cell objects.
- Phase 2 must move the prototype into `packages/terminal_core`, add invariant,
  chunk-split, resize/reflow, snapshot, property, and malformed-wire tests, and
  keep this wire format behind an explicit codec rather than exposing arrays
  throughout the app.
