# Phase 6 — DECRQSS SGR reply gap

## Identity and status

- Date recorded: 2026-09-07
- Owner: ordered `focus/mouse/bracketed paste/query reports` roadmap item
- Current status: explicit bounded safe-ignore; implementation deferred to its
  ordered owner

## Purpose and evidence

The reviewed black-box differential corpus found one reply difference in the
rendition family. Kitty 0.48.2 and xterm 411 reply to `DECRQSS` for SGR, while
Dart Terminal consumes the complete DCS string and emits no reply. This agrees
with the existing `dec:dcs:decrqss` inventory classification of `safe-ignore`;
it is not parser corruption or an unbounded string path.

The original styled case is reduced to the complete seven-byte sequence below.
It contains only the introducer, `$q` selector, `m` request payload, and ST
terminator. Removing any byte no longer represents a complete DECRQSS SGR
request, so the reduction is byte-level minimal for this protocol difference.

```text
hex: 1b 50 24 71 6d 1b 5c
     ESC P  $  q  m  ESC \
```

Pinned Kitty and xterm raw captures and the Dart observation are validated by
the differential acceptance gate. Their exact SGR serialization is
product-specific; acceptance depends on both external products producing a
bounded valid success reply while Dart produces none, not on rewriting one
product's bytes into the other's.

## Scope and non-goals

- This record makes the omission visible and gives it a later roadmap owner.
- It does not implement DCS reply semantics ahead of the ordered query-report
  task.
- It does not weaken malformed/incomplete DCS bounds or classify arbitrary DCS
  payloads as supported.
- Screen, style, and mode state were not observed through the PTY probe and are
  not covered by this accepted reply gap.

## Future completion conditions

The owning query-report task must either implement bounded DECRQSS SGR replies
with byte-level regression coverage, or retain safe-ignore with application
evidence that no P0 compatibility path depends on the reply. If implemented,
this `documented-gap` expectation must become `agree`; the acceptance gate is
designed to fail when the gap becomes stale.

## Verification

- `dart run test/terminal_differential_acceptance_test.dart` passed.
- `make terminal-differential-acceptance-check` passed with 12 accepted matrix
  cells: 6 agreements, 2 documented gaps, and 4 unavailable results.
- `CI=true make test` passed formatting, static analysis, all compatibility
  freshness checks, and the full Dart Terminal test runner.
