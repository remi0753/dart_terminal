# DT-010 — Parser corpus format and snapshot harness

- Status: accepted
- Date: 2026-09-01
- Scope: Phase 0 test/performance infrastructure for the Phase 3 Dart VT core
- Related: ROADMAP sections 5.2, 7, 8, and 9; FEATURE_MATRIX PAR-01/02/03/05, QA-01, PERF-01

## Question

Can the project freeze a byte-exact, chunk-independent, human-readable parser
test contract before implementing the complete Dart VT terminal core, and can
a no-per-byte-object streaming probe meet the provisional 100 MiB/s AOT gate?

The answer must not depend on Ghostty source code. Ghostty remains a pinned
feature/parity reference; this corpus, probe, and harness are original Dart
Terminal code.

## Scope boundary

This is a **harness and workload probe**, not the Phase 3 product parser. It
classifies streaming UTF-8, C0, ESC, CSI, OSC, DCS, and APC actions; preserves
sequence bytes; applies cancel/recovery and fixed limits; and records action
snapshots. It deliberately does not mutate a terminal screen, implement SGR or
mode semantics, answer queries, emulate compatibility quirks, or replace the
future generated dispatch table.

Phase 3 may replace the probe implementation, but the replacement must consume
the same corpus format, produce the same reviewed snapshots (or an explicitly
reviewed corpus change), and run through this benchmark protocol.

## Corpus format

`test/corpus/parser/phase0.json` is a UTF-8 JSON document with this envelope:

```json
{
  "format": "dart-terminal-parser-corpus",
  "version": 1,
  "cases": [
    {
      "id": "stable-unique-id",
      "description": "human intent",
      "input_hex": "byte-exact hexadecimal input",
      "limits": {
        "max_sequence_bytes": 32,
        "max_string_bytes": 8,
        "max_parameters": 4,
        "max_numeric_value": 99
      },
      "snapshot": ["ordered readable action lines"]
    }
  ]
}
```

`limits` is optional and otherwise uses the probe defaults: 8,192 sequence
bytes, 4,096 string payload bytes, 32 parameters/subparameters, and numeric
value 1,000,000. Case IDs must be unique. Input is hex rather than an escaped
text field so NUL, malformed UTF-8, C0, ESC, and arbitrary future bytes remain
unambiguous and diffable.

Expected snapshots are source-controlled oracles. `--print-snapshots` assists
review, but the harness never rewrites them. A behavior change requires reading
the old/new action diff and editing the corpus deliberately.

## Phase 0 corpus

The nine fixtures cover:

1. ASCII plus split three-byte CJK and four-byte emoji;
2. ordered CR/LF execution and simple ESC dispatch;
3. semicolon parameters and byte-preserved colon-form SGR;
4. OSC with BEL/ST plus DCS/APC with ST;
5. CAN/SUB cancellation and printable recovery;
6. invalid UTF-8 starts/continuations and incomplete-tail replacement;
7. parameter-count, numeric-value, and string-payload limits with recovery;
8. incomplete CSI at EOF;
9. ESC cancellation/restart into a new CSI.

The formatter coalesces adjacent Unicode scalars into `TEXT` lines and renders
controls/sequences as readable escaped bytes, for example:

```text
CSI "\e[38:2::1:2:3m"
TEXT "X"
CANCEL state=csi byte=ESC
LIMIT state=osc
INCOMPLETE state=csi
```

Every case is parsed as one chunk, at every possible single split including
empty first/last chunks, and one byte per chunk. The final corpus performs 190
split/bytewise runs and compares both formatted actions and a deterministic
action hash. Every run must finish in ground state after explicit EOF handling.

## Probe design

The probe accepts `Uint8List` plus start/end indices and keeps only integer
state, indices, fixed counters, a fixed sequence byte buffer, and incremental
UTF-8 state. Its capture-disabled benchmark path creates no event object,
`String`, `RegExp`, or exception per byte. Printable ASCII has a dedicated
ground-state fast loop. The correctness path records numeric action tuples and
raw sequence spans in preallocated typed arrays; only the cold snapshot
formatter creates strings.

Malformed input does not throw from the hot parser. It emits deterministic
replacement/cancel/limit actions and returns to printable ground state. Corpus
loading and invalid API arguments may throw because they are test/cold paths.

During development, the first malformed-UTF-8 snapshot exposed a real harness
bug: when an ASCII byte interrupted a partial multibyte scalar, the outer fast
path correctly declined it but the ground handler emitted ASCII before routing
through the pending decoder. The snapshot byte order made the misplaced
replacement visible. The handler now flushes/reprocesses through the decoder,
and the reviewed result is `A��B�(�C�`. This is direct evidence that the
snapshot/chunk harness finds state-boundary errors rather than only measuring a
loop.

## Reproduction

```sh
make phase0-parser-build
make phase0-parser-run

# Review actual snapshots without changing the oracle:
build/phase0/parser/parser_harness \
  --corpus=test/corpus/parser/phase0.json \
  --print-snapshots
```

The benchmark seed is a repeated 65,591-byte mixed stream containing printable
ASCII, colon-form CSI, Japanese/emoji UTF-8, CR/LF, OSC, and DCS. Each run parses
134,264,777 bytes (about 128 MiB) in one release-AOT parser session after
warm-up and verifies nonzero text/control/sequence counts and a stable hash.

Artifacts:

| Artifact | SHA-256 |
| --- | --- |
| release-AOT harness | `e44e53b40c0d7fadbd8e13d0ad1ee6d24622240739b25488ead3631f7718ff7e` |
| reviewed corpus | `37414501d31cede8a3e39f70fceaae5ae2500e0be40ce5b10178e6e4ce2fb8be` |
| streaming probe source | `3d60b0b0d87b77a874ed20b1a9e8dc1be7d018ba1ce19593497769c1350968f4` |

## Real-hardware result

| Run | Parsed bytes | Elapsed (us) | MiB/s | Corpus hash | Action hash |
| ---: | ---: | ---: | ---: | ---: | ---: |
| Initial accepted | 134,264,777 | 813,801 | 157.34 | 849,202,531 | 1,260,906,479 |
| 1 | 134,264,777 | 801,670 | 159.72 | 849,202,531 | 1,260,906,479 |
| 2 | 134,264,777 | 798,795 | 160.30 | 849,202,531 | 1,260,906,479 |
| 3 | 134,264,777 | 799,999 | 160.06 | 849,202,531 | 1,260,906,479 |
| 4 | 134,264,777 | 797,788 | 160.50 | 849,202,531 | 1,260,906,479 |
| 5 | 134,264,777 | 799,502 | 160.16 | 849,202,531 | 1,260,906,479 |

All six runs passed the 100 MiB/s provisional gate. The slowest was **157.34
MiB/s**, 57.3% above the gate. Every run also passed all 190 chunk plans and 32
snapshot lines with identical hashes. The timed benchmark processed 58,976,117
text scalars, 2,509,622 C0 controls, and 5,019,244 sequences.

## Decision

Accepted. The corpus envelope, byte-exact hex input, reviewed action snapshot,
all-split/bytewise execution, stable hash, explicit limits, and release-AOT
throughput workload become Phase 3 infrastructure requirements.

The result does not authorize moving parser semantics native: a Dart streaming
state machine already exceeds the first throughput target. Phase 3 must add the
generated transition table, parameter/intermediate typed action contract,
screen/grid snapshots, shell/less/top/vim recorded streams, property/fuzz
seeds, memory caps, and differential oracles while retaining this harness.
