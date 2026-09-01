# DT-007 — CoreText glyph-run shaping spike

- Status: accepted
- Date: 2026-09-01
- Scope: Phase 0 feasibility gate
- Related decisions: ADR-001 and ADR-002

## Question

Can a release-AOT Dart terminal worker pass complete UTF-8 text runs through a
coarse native boundary and obtain valid CoreText glyph-run evidence for Latin,
CJK fallback, color emoji sequences, and ligatures without doing shaping on
the AppKit/root-isolate thread?

This validates macOS text shaping for an independently implemented Dart
terminal emulator. It does not use Ghostty or `libghostty` code.

## Acceptance criteria

1. Latin, CJK, emoji, and ligature corpora each produce nonempty CoreText runs,
   glyphs, finite positions/metrics, nonzero advances, and no missing glyph.
2. UTF-8 input round-trips to the expected UTF-16 and Unicode-scalar counts.
3. CJK exercises a real fallback face from the requested monospace face.
4. Emoji exercises a color-glyph fallback and shapes ZWJ/modifier/flag
   sequences as clusters.
5. Ligature shaping reduces glyph count and exposes a multi-character string
   index span rather than only accepting a font attribute.
6. The ABI is one synchronous call per text run, not one call per glyph.
7. Shaping runs on a worker isolate; CoreText/CF object ownership remains
   native and no borrowed Dart pointer survives the call.
8. No measured Dart root message-pump turn reaches 4,000 us.
9. Five consecutive repeat runs pass on real hardware.

## Implementation

Dart sends a whole UTF-8 run plus a 384-byte output area to one native leaf FFI
call. Borrowed typed-data addresses are valid only for that synchronous call.
The call is leaf because it never enters Dart or waits on Dart resources, and
it is invoked only by the shaping worker isolate, never by the root isolate.

Native creates a CoreText attributed line, enumerates `CTRun` objects, and
copies a versioned fixed-size summary back before releasing every CoreText and
Core Foundation object. The summary contains run/glyph/font counts, fallback
and color-run counts, ligature cluster spans, missing-glyph and index checks,
typographic metrics, deterministic hashes, duration, and the actual
PostScript face names. The fixed summary is a feasibility-test contract; the
product contract will use a bounded packed glyph-run buffer with the same
version/length validation.

Each process shapes all four cases 64 times. Dart validates every one of the
256 results and computes native and end-to-end FFI p95 values. The root isolate
only owns AppKit lifecycle, heartbeat, worker lifecycle, and final reporting.

## Corpus and actual shaping

| Case | Input | UTF-16 / scalars | Runs | Glyphs | Evidence | Faces |
| --- | --- | ---: | ---: | ---: | --- | --- |
| Latin | `Hello, terminal!` | 16 / 16 | 1 | 16 | requested face, no fallback | Menlo-Regular |
| CJK | `日本語漢字かなカナ` | 9 / 9 | 1 | 9 | one fallback run | HiraginoSans-W3 |
| Emoji | `A👩🏽‍💻🧑‍🚀🇯🇵B` | 18 / 11 | 3 | 5 | color fallback; ZWJ/modifier/flag clusters | AppleColorEmoji, Menlo-Regular |
| Ligature | `office ffi affluent` | 19 / 19 | 1 | 16 | three multi-character clusters | Times-Roman |

The first ligature attempt used `TimesNewRomanPSMT`; even with the ligature
attribute and an explicit OpenType `liga` setting it returned 19 glyphs for 19
scalars on this system. `Times-Roman` with the same explicit feature contract
returned 16 glyphs and three cluster spans. The test therefore rejects the
former instead of treating a requested attribute as proof. Product shaping
and cache keys must include the resolved font descriptor and feature settings.

## Reproduction

```sh
make phase0-coretext-build
make phase0-coretext-run
```

The ProductARM64 AOT app is ad-hoc signed; strict deep signature verification
passes.

Artifact SHA-256 values for the accepted build:

| Artifact | SHA-256 |
| --- | --- |
| native host | `a35c9847f29c740ed2294bce37fdd3bbb0f0ec6fde7826b1e0e08fb205b227da` |
| Dart AOT snapshot | `d32432b3aa27cdccdbd1e9c04746abd9b63b7a4bb2d6fd57e1c660a0486dbd65` |
| patched ProductARM64 engine | `be9e6aed1505991cdac3fd9cf940de4f2ede7a8cf66f399786b8923e984bc8d1` |

## Real-hardware result

The values below are the native shaping p95 in microseconds for 64 iterations
per case.

| Run | Latin | CJK | Emoji | Ligature | Worker total (us) | Root max turn (us) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 13 | 16 | 32 | 31 | 9,949 | 168 |
| 1 | 14 | 17 | 33 | 86 | 15,992 | 146 |
| 2 | 13 | 17 | 32 | 28 | 8,850 | 123 |
| 3 | 14 | 17 | 29 | 29 | 8,873 | 119 |
| 4 | 14 | 16 | 30 | 28 | 8,864 | 176 |
| 5 | 14 | 17 | 31 | 29 | 9,070 | 123 |

All six accepted runs produced identical run/glyph topology, face names,
widths, and glyph/font hashes. The worst native shaping p95 was **86 us** and
the corresponding end-to-end FFI p95 was **88 us**. The worst root turn was
**176 us**, 4.4% of the 4,000 us hard ceiling. Maximum root heartbeat gaps were
12.2–14.0 ms; those include scheduling between timer firings and are not
synchronous handler durations.

The shared host's optional finalizer was also corrected from an unresolved
weak import to a weak no-op definition. A rebuilt Metal app proved that its
strong GPU finalizer overrides the default and still passes at 100,000
instances, with a 741 us maximum root turn.

## Decision

Accepted. CoreText shaping belongs behind a coarse, worker-only native service.
Dart owns terminal text, style selection, logical clusters, cache policy, and
the eventual packed run data; native owns CoreText calls and object lifetimes.
The product boundary must batch at least a full changed row/run, return
resolved font/feature identity, preserve UTF-16-to-terminal-cell cluster
mapping, and place hard bounds on output sizes.

CoreText does not need to move more terminal logic into native code. If later
font fallback or atlas workloads miss their budgets, only shaping/raster batch
size and native cache placement should move across the boundary.
