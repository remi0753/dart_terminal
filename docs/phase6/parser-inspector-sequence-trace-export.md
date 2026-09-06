# Phase 6 — Parser inspector and sequence trace export

## Identity and status

- Date started: 2026-09-07
- Scope: eighth Phase 6 compatibility-hardening roadmap item
- Current status: complete; both implementation units and the parent roadmap
  item passed their required gates

## Purpose and background

The parser and semantic sink already expose aggregate counters, snapshots, and
special-purpose compatibility replay tools. They do not expose a bounded,
ordered explanation of which terminal sequences were observed or how parser
recovery classified them. Semantic acceptance is currently available only from
special-purpose counters and replay tools. This makes a real compatibility
failure harder to reduce without adding temporary content-logging code.

This task adds a content-conscious parser inspector boundary and a deterministic
sequence trace export suitable for tests and local diagnostics. It is a Phase 6
developer/diagnostic facility, not the user-facing terminal inspector settings
UI owned by later phases.

## Ordered implementation units

1. **Bounded parser inspector event foundation**
   - Define immutable, typed parser-action observations with explicit caps and
     monotonic ordering.
   - Attach the observer without changing normal parser behavior or requiring
     it in production.
   - Record parser classification and only bounded sequence metadata needed to
     reproduce state-machine behavior; do not persist printable terminal text.
   - Verify every action family, recovery/limit conditions, eviction, observer
     failure isolation, and chunk-boundary independence.
2. **Versioned sequence trace export and normal gate**
   - Export deterministic, versioned JSON with escaped bounded byte evidence,
     aggregate classifications, truncation/eviction disclosure, and no wall
     clock, path, environment, or terminal text fields.
   - Provide a bounded CLI/replay path and committed regression fixture with a
     freshness checker in the normal test gate.
   - Update README/FEATURE_MATRIX/Phase 6 records and close the parent roadmap
     item only after focused tests, static analysis, and the full gate pass.

Each implementation unit is documented, verified, marked complete, and
committed before the next unit starts.

## Scope

- Parser action/recovery observations at the existing Dart-only VT parser
  boundary.
- Fixed record/byte limits, deterministic FIFO eviction, sequence numbering,
  and explicit dropped-record accounting.
- Versioned, deterministic diagnostic export from supplied byte streams.
- Unit, all-split/bytewise, fixture freshness, and full-gate verification.

## Out of scope

- Logging printable shell/application content, OSC/DCS payload contents,
  clipboard data, titles, paths, commands, environment variables, or PTY bytes
  outside a caller-supplied diagnostic replay.
- Always-on file I/O, telemetry, crash upload, or application-session trace
  retention.
- A native inspector window, settings UI, command palette integration, or
  remote diagnostic transport.
- Semantic compatibility fixes found by the inspector; those belong to the
  following ordered regression-corpus task unless required to make this trace
  contract correct.
- Duration-only soak. The roadmap classifies long-duration evidence as a
  lower-priority, nonblocking follow-up; bounded correctness and memory limits
  remain required.

## Dependencies and initial facts

- `VtParser` already emits typed actions to `VtParserSink`, owns bounded CSI and
  string buffers, and classifies cancel, malformed, limit, incomplete, and
  unsupported outcomes through the semantic sink and snapshot counters.
- The application-matrix unsupported tracer is a specialized post-parse
  minimizer. It does not provide a general parser-action chronology and must
  remain independently reproducible.
- Existing terminal-state snapshots deliberately contain only aggregate parser
  counters; live content must not be duplicated into this diagnostic surface.
- User-facing terminal inspector UI remains a later-phase feature, so this task
  will expose a reusable Dart diagnostic model and CLI rather than adding
  AppKit UI ahead of the roadmap.

## Completion conditions

- The inspector is optional, bounded, deterministic, and cannot change parser
  or terminal semantics when enabled or disabled.
- Normal text content and control-string payload data are absent from exported
  traces; sequence metadata is sufficient to distinguish action families and
  recovery classifications.
- Trace overflow and observer failures are visible without making untrusted
  parser input throw into the product path.
- Whole, every-single-split, and bytewise replay produce the same exported
  trace for the committed fixture.
- The export schema, CLI, fixture, freshness checker, documentation, analyzer,
  formatter, and complete test gate pass.

## Verification plan

- Focused unit tests for all parser action families and every recovery outcome.
- Small-cap stress tests for byte/record bounds, FIFO eviction, monotonic IDs,
  and observer exception isolation.
- Whole/split/bytewise deterministic trace comparison and committed fixture
  freshness validation.
- `dart analyze`, `git diff --check`, and `CI=true make test` for each unit.

## Investigation and decision log

- 2026-09-07: after commit `73f01b6`, ROADMAP was reread with a clean worktree.
  The first incomplete item is parser inspector and sequence trace export; the
  compatibility regression corpus remains ordered after it.
- 2026-09-07: reread README, FEATURE_MATRIX, Phase 3 parser/snapshot records,
  Phase 6 inventory and application tracing references, and the repository
  layout. Existing product UI ownership confirms that this item is a bounded
  developer diagnostic substrate, not an AppKit inspector screen.
- 2026-09-07: split the item before implementation because parser observation
  and persisted export/freshness are independently reviewable boundaries. Both
  remain children of the current roadmap item and neither begins the following
  compatibility-bug corpus early.
- 2026-09-07: selected an optional `VtParserSink` decorator instead of adding
  callbacks to the parser or production screen sink. Disabled product parsing
  therefore has no new branch or allocation, while an enabled inspector still
  preserves the downstream ASCII batch fast path and forwards every action
  before diagnostic bookkeeping.
- 2026-09-07: printable scalars are counted but never retained. CSI/DCS header
  syntax, C0/C1 bytes, parser state, recovery reason, string kind, terminator,
  and payload length are sufficient for state-machine diagnosis; OSC/DCS/APC
  payload bytes are deliberately unavailable through the event API.
- 2026-09-07: retained events use a deterministic 48-byte base accounting cost
  plus copied parameter/intermediate metadata. Record and metadata caps evict
  oldest entries FIFO; an individually oversized event is dropped and counted.
  Aggregate kind counts include evicted events. Optional observer exceptions
  are counted and suppressed only after the downstream action succeeds.
- 2026-09-07: the first analyzer run after the focused test reported only a
  directive-ordering info in the aggregate runner. Moving the new inspector
  test import before the parser test restored a clean analyzer; no behavior or
  acceptance condition changed.
- 2026-09-07: the version 1 export uses ordered JSON maps and canonical 7-bit
  `ESC` introducers. This intentionally describes the typed action rather than
  claiming whether its original introducer was an equivalent 8-bit C1 byte.
  Complete non-string controls/headers have canonical hex; string families
  separate canonical prefix and terminator hex around a redacted payload byte
  count.
- 2026-09-07: the report includes the exact parser, inspector, input, and
  serialized-output limits required to reproduce it, plus total/retained/
  evicted/oversized/observer-failure counts. A chunked JSON UTF-8 sink checks
  the output bound before retaining each encoded chunk instead of constructing
  an unbounded serialized string and checking afterward.
- 2026-09-07: the local CLI accepts one explicit lowercase hex input or one
  bounded input file without including that path in the report. Its reviewed
  fixture covers all ten event families in 97 bytes and produces 11 events;
  printable text and OSC/APC payload markers are absent in both text and hex
  form from the 3,211-byte trace.
- 2026-09-07: `terminal-parser-trace-check` was added before the other
  compatibility freshness gates in the normal `make test` dependency graph.
  The source case remains reviewable while generated JSON drift fails the gate
  with an explicit regeneration command.

## Verification results — bounded inspector foundation

- `dart run test/vt_parser_inspector_test.dart`: passed typed observations for
  execute, ESC, CSI, OSC, DCS, APC, cancel, malformed, limit, and incomplete
  actions; printable-content aggregation; payload redaction; copied header
  metadata; downstream ASCII batching; semantic equivalence; every single
  split; bytewise replay; FIFO eviction; oversized-event disclosure; observer
  exception isolation; aggregate counts; and invalid-limit rejection.
- `dart analyze`: passed with no issues after the import-order correction.
- `CI=true make test`: passed all generated artifact, inventory,
  differential, application, and terminfo freshness/acceptance gates;
  formatting of 181 Dart files with no changes; static analysis with no issues;
  and the complete Dart test runner.
- `git diff --check`: run in the final pre-commit review.
- The final compatibility coverage gate independently regenerates the same
  97-byte/11-event redacted fixture before accepting Phase 6 closure, and pins
  both trace-case and expected-trace hashes in its deterministic report.

## Verification results — trace export and closure

- `dart run tool/terminal_parser_trace.dart --generate` and `--check`: generated
  and then accepted the 97-byte, 11-event version 1 fixture. A separate
  `--input-hex=1b5b3f323568` replay exported the exact canonical DECSET 25 CSI
  metadata without printable content.
- `dart run test/vt_parser_trace_test.dart`: passed deterministic schema,
  privacy fields, reproduction limits, exact aggregate/event metadata, payload
  absence in text and hex form, all 98 single split positions, bytewise replay,
  committed fixture equality, eviction disclosure, streaming output overflow,
  input overflow, and invalid-limit rejection.
- `dart analyze`: passed with no issues before final documentation sync.
- `CI=true make test`: passed the new parser-trace freshness check and every
  existing generated artifact, inventory, differential, application, and
  terminfo gate; formatting of 184 Dart files with no changes; static analysis
  with no issues; and the complete Dart test runner.
- `git diff --check`: run in the final pre-commit review.
