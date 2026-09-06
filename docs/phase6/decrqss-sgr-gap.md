# Phase 6 — DECRQSS SGR reply gap

## Identity and status

- Date recorded: 2026-09-07
- Owner: ordered `focus/mouse/bracketed paste/query reports` roadmap item
- Current status: resolved by bounded current-SGR reporting in its ordered
  owner

## Purpose and evidence

The reviewed black-box differential corpus originally found one reply
difference in the rendition family. Kitty 0.48.2 and xterm 411 replied to
`DECRQSS` for SGR while Dart Terminal consumed the complete DCS string and
emitted no reply. That historical result agreed with the then-current
`safe-ignore` classification; it was not parser corruption or an unbounded
string path.

The original styled case is reduced to the complete seven-byte sequence below.
It contains only the introducer, `$q` selector, `m` request payload, and ST
terminator. Removing any byte no longer represents a complete DECRQSS SGR
request, so the reduction is byte-level minimal for this protocol difference.

```text
hex: 1b 50 24 71 6d 1b 5c
     ESC P  $  q  m  ESC \
```

Pinned Kitty and xterm raw captures and the Dart observation are validated by
the differential acceptance gate. Dart now matches xterm's pinned form
byte-for-byte. Kitty uses a different valid serialization; it is accepted as a
semantic agreement only after both replies independently parse to the same
style and colors. The differing raw bytes remain in the acceptance report.

## Scope and non-goals

- This record preserves the minimized regression and documents its resolution
  by the ordered query-report task.
- Only the complete unparameterized SGR payload `m` is implemented.
- It does not weaken malformed/incomplete DCS bounds or classify arbitrary DCS
  payloads as supported.
- Screen, style, and mode state were not observed through the PTY probe and are
  not covered by this accepted reply gap.

## Resolution

`TerminalReplyEncoder.decrqssSgr` emits the current rendition in a stable
xterm-compatible order. The default reply is 9 bytes and the largest supported
state is 63 bytes, within the existing 64-byte reply limit. The parser accepts
only `DCS $ q m ST`; other payloads and parameterized requests remain bounded
unsupported. The minimized regression moved from `mismatches/` to
`regressions/decrqss_sgr_v1.json`, and the real-application replay no longer
counts Neovim's query as a reject.

## Verification

- Reply/parser tests pass exact default/styled/maximal bytes, invalid input,
  immutability, and every split/bytewise request plan.
- Differential acceptance passes 12 cells: 8 agreements, including one
  semantic Kitty agreement, no documented gaps, and 4 unavailable results.
- After the enclosing query-report closure, application acceptance passes 71
  replayed unsupported increments, 12 unique variants, and 8 remaining owned
  gaps.
- Real-PTY Developer JIT and Release AOT product runs observe the exact 9-byte
  default reply.
