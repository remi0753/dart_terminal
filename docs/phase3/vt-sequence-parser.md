# Phase 3 — C0/ESC/CSI/OSC/DCS/APC parser

- Status: completed
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after the UTF-8/table task
- Related: `ROADMAP.md` Phase 3; `FEATURE_MATRIX.md` PAR-02 through PAR-05,
  QA-01, SEC-01; `docs/phase0/DT-010-parser-corpus-snapshot.md`;
  `docs/phase3/streaming-utf8-parser-table.md`

## Purpose and background

Turn the generated VT state/action table and streaming UTF-8 decoder into the
product's incremental byte-to-action parser. The parser must preserve behavior
across arbitrary PTY chunk boundaries, recover deterministically after invalid
UTF-8 and cancelled/malformed sequences, and enforce fixed memory/numeric
limits before later screen/grid semantics consume its actions.

The Phase 0 probe remains the reviewed byte/snapshot oracle but is not product
code. The product parser must expose typed, synchronous actions without a Dart
object allocation per input byte and without importing AppKit, Metal, or FFI.

## Scope

- A public Dart-only incremental `VtParser` and validated `VtParserLimits`.
- A typed sink contract for printable scalars, C0/C1 execution, ESC and CSI
  dispatch, bounded OSC/DCS/SOS/PM/APC payload completion, cancellation,
  resource-limit rejection, malformed-sequence recovery, and incomplete EOF.
- CSI/DCS private marker, intermediate bytes, parameters, subparameters,
  omitted values, and numeric overflow handling.
- CAN/SUB/ESC/C1 restart behavior driven by the generated transition table.
- UTF-8 continuation precedence over byte values that also represent 8-bit C1
  controls when no UTF-8 scalar is pending.
- Fixed parser-owned typed buffers and copies only at dispatched sequence
  boundaries; no input-chunk retention or per-byte event objects.
- Product parser corpus tests using whole input, every split, empty edge chunks,
  and bytewise delivery, plus focused limit/recovery tests.

## Out of scope

- Applying actions to a terminal grid, cursor, margins, modes, SGR, palette,
  alternate screen, scrollback, selection, or search state.
- Encoding terminal query replies or connecting them to the PTY write queue.
- Application-specific compatibility quirks, parser inspector UI, fuzz runner,
  or recorded shell/application stream snapshots owned by later roadmap items.
- Changing the Phase 0 corpus oracle without a separately reviewed reason.

## Dependencies and constraints

- `StreamingUtf8Decoder` owns only partial Unicode state and must be flushed
  before a non-continuation control/introducer is parsed as VT syntax.
- The generated table is the transition source of truth; parser code may not
  duplicate a hand-written state switch.
- Limits must be applied before growing or indexing buffers, report at most one
  rejection for a logical sequence, and return to ground at a bounded
  terminator/cancel boundary.
- Sink callbacks are synchronous. Dispatched typed payload/header values must
  be safe for a sink to retain after the parser continues.
- The core source remains independent from platform packages and `dart:ffi`.

## Completion criteria

- Reviewed product snapshots match for one chunk, every split point, empty
  first/last chunks, and one-byte chunks.
- Printable ASCII/UTF-8, C0/C1, ESC, CSI including colon subparameters,
  OSC BEL/ST, DCS ST, and APC/SOS/PM ST produce ordered typed actions.
- Invalid UTF-8, CAN/SUB/ESC restart, malformed headers, parameter/intermediate,
  numeric, payload, and total-sequence limits recover to later printable text.
- `finish()` emits replacement/incomplete observations exactly once and leaves
  the parser reusable in ground state.
- Generator freshness, formatting, analysis, the complete unit suite, focused
  Release AOT execution, source-boundary audit, and final diff checks pass.

## Verification plan

1. Add deterministic recorder snapshots and exhaustive chunk plans for a
   product corpus spanning each parser family and recovery class.
2. Add direct assertions for typed parameters/subparameters, retained copies,
   lifecycle restarts, all configured limits, malformed ignore states, EOF,
   reset, and slice validation.
3. Run `make test`, then compile/run the focused terminal-core suite as Release
   AOT.
4. Stage the new core files so `make runtime-source-check` audits them, and run
   whitespace/final-diff checks.
5. Record results, update feature status and `ROADMAP.md`, then create one
   completion commit without a task number.

## Investigation log

- The worktree was clean on `main` at `b00dcb8` when this task started.
- `ROADMAP.md` still identifies the parser as the first unchecked item; the
  following typed-array grid task must not be started before this commit.
- The existing table has 14 states with transition, entry/exit, and same-state
  re-entry information. Consuming it exposed one contract refinement: a parser
  also needs to distinguish a new ESC/C1 introducer from an intra-sequence
  state change so it can reset byte/limit ownership at the correct point. This
  will be represented as generated transition metadata rather than a duplicate
  byte switch in parser code.
- CAN/SUB are executable controls in ground but cancel an active sequence. The
  generated table currently applies the global cancel action in both contexts;
  the parser implementation and table specification must make the ground case
  explicit and test it before acceptance.
- The first `dart format` run formatted four of seven requested files but
  returned exit code 1 when Dart attempted to update
  `~/.dart-tool/dart-flutter-telemetry-session.json` outside the writable
  workspace. This is an environment-only failure after formatting; rerun the
  same check with the required filesystem permission before acceptance.
- A later focused format command accidentally included three Markdown files.
  `dart format` correctly rejected them as non-Dart syntax (exit 65), changed
  no files, and still reported the Dart test file unchanged. Restrict all
  formatter reruns to `bin`, `lib`, `test`, and `tool`; review Markdown with
  diff/whitespace checks instead.
- The first task-scoped `git add` attempt failed before changing the index
  because the managed sandbox denied creation of `.git/index.lock`. Retry the
  same explicit file list with Git metadata permission; do not broaden the
  staged scope.

## Decisions and alternatives

- Considered splitting table-contract refinement, typed action API, parser
  lifecycle, and tests into separate roadmap subtasks. They are mutually
  dependent parts of one parser acceptance boundary: the table refinement has
  no standalone consumer, and committing the API without lifecycle/limit tests
  would leave the current roadmap item knowingly incomplete. Kept one atomic
  task and one completion commit, with focused sections and verification.
- Added explicit generated `startsSequence` metadata instead of asking parser
  code to recognize introducer byte values. This keeps transition ownership in
  the declarative table while distinguishing a new ESC/C1 sequence from a
  normal state change and from a printable self-loop.
- Added one `malformed` table action and state-local global-rule overrides.
  Ground CAN/SUB therefore execute as controls, active header CAN/SUB cancel,
  active-header ESC/C1 introducers cancel and restart, and CSI/DCS grammar
  violations enter their ignore states after one typed malformed callback.
- Used a synchronous `VtParserSink` with scalar callbacks for hot print/control
  actions and retainable typed snapshots only at complete ESC/CSI/string
  boundaries. A per-byte event hierarchy was rejected because it would violate
  the allocation constraint; exposing parser-owned mutable buffers was rejected
  because a later screen sink could accidentally retain corrupted data.
- Represented CSI/DCS parameter segments as parallel `Uint32List` and
  `Uint8List` snapshots. The metadata distinguishes omitted values and `:`
  subparameters without encoding punctuation into strings or interpreting SGR
  semantics inside the parser.
- Kept OSC/DCS/SOS/PM/APC payloads as raw bounded bytes. Decoding or applying
  protocol semantics belongs to later terminal-core tasks, and retaining raw
  bytes avoids accepting malformed protocol text prematurely.
- Treated ESC inside a string as a pending possible `ESC \\` terminator. A
  following backslash completes the original string without emitting an ESC
  action; any other byte cancels the original string and is processed in the
  already-entered escape state. This preserves arbitrary chunk boundaries
  without buffering an input chunk.
- Validated limits before allocating fixed typed buffers. Header/payload
  overflow marks the current sequence rejected, emits only the first limit
  callback for that logical sequence, consumes through a bounded recovery
  boundary, and does not weaken later parser reuse.

## Verification results

- Generated-table freshness passed after regeneration; the table has 14 states,
  21 actions, explicit sequence-start flags, and checked coverage for all
  `14 × 256` byte transitions.
- `dart analyze` passed with no issues.
- The focused JIT parser suite passed for all typed sequence families, every
  single split (including empty first/last chunks), bytewise delivery,
  UTF-8/C1 precedence and malformed UTF-8 recovery, cancellation, malformed
  headers, all five limit classes, exact limit boundaries, incomplete EOF,
  reset/reuse, input slices, retainable copies, and invalid configuration.
- Final `make test` passed: dependency resolution, generated-table freshness,
  formatting of 40 Dart files with zero changes, analysis with no issues, and
  the complete repository test entry point all succeeded.
- The final focused parser test compiled to a Release AOT executable and that
  executable exited successfully with no output.
- `make runtime-source-check` passed with `tracked=90` and
  `native_sources=0`; the new core stays inside the Dart-only boundary.
- Final `git diff --check` passed. The staged diff contains only the parser,
  generated-table contract, public export, focused/aggregate tests, task and
  status documentation, and the single roadmap completion checkbox; there are
  no unrelated or unstaged changes.

## Risks and handoff

- Parameter and payload models are intentionally syntax-only inputs to later
  grid/protocol semantics; consumers must continue to keep SGR/OSC/DCS policy
  out of this parser.
- The product parser is not connected to `TerminalSession` or the existing
  plain-text `TerminalBuffer`; that integration depends on the immediately
  following typed-array grid task.
- Throughput is structurally protected by dense typed tables, fixed buffers,
  and no event allocation per byte, but the Phase 3 provisional throughput gate
  remains owned by the later corpus/performance work after the screen sink is
  available.
