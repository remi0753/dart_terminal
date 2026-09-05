# Phase 3 — Product parser corpus, properties, fuzz seeds, and exit gate

- Status: in progress
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after snapshot diagnostics
- Related: ROADMAP Phase 3; FEATURE_MATRIX PAR-01–05, SCR-01–12, QA-01,
  PERF-01; `docs/phase0/DT-010-parser-corpus-snapshot.md`;
  `docs/phase0/DT-011-benchmark-baseline.md`;
  `docs/phase3/snapshot-formatter-test-diagnostics.md`

## Purpose and background

Phase 3 now has a Dart-only streaming parser, terminal screen state machine,
bounded replies/history/resources, and a versioned readable final-state oracle.
The remaining Phase 3 work must turn those pieces into repeatable compatibility
evidence: reviewed byte fixtures, recorded representative application streams,
deterministic property exploration, regression-oriented fuzz seeds, and a
Release AOT throughput gate.

Phase 0 accepted the principles for this work—hexadecimal byte input,
source-controlled expected snapshots, all single splits plus bytewise replay,
fixed limits, no automatic oracle rewrite, and a provisional parser target of
100 MiB/s—but its probe is historical and does not mutate the product screen.
This task applies those principles to the product parser and formatter while
retaining the Phase 0 corpus and measurements as independent evidence.

## Scope

- Add a strictly validated, bounded product-corpus manifest and reusable replay
  harness using `VtParser`, `TerminalScreenParserSink`,
  `TerminalScreenSet`, `TerminalSnapshotFormatter`, and
  `TerminalSnapshotComparator`.
- Store arbitrary input as exact hexadecimal bytes and reviewed expected state
  in separate UTF-8 snapshot files. The harness may print actual snapshots for
  review but never writes or blesses them.
- Cover core screen semantics with small fixtures, replaying whole input, every
  single split (including empty ends), and bytewise chunks.
- Capture and review deterministic terminal byte streams representing a shell
  prompt and `less`, `top`, and `vim`, then replay them to expected product-state
  snapshots. Record the capture environment and sanitization rules; fixtures
  must not contain user paths, environment values, or nondeterministic status.
- Add deterministic generated properties for arbitrary byte/chunk plans,
  final-state repeatability, parser recovery, screen/history topology, and hard
  limits.
- Add a small source-controlled fuzz seed corpus selected around parser, UTF-8,
  screen, resource, resize/reflow, and reply boundaries, plus deterministic
  mutation tests suitable for later coverage-guided fuzzing.
- Benchmark the product `VtParser` capture-disabled path in Release AOT using
  the Phase 0 mixed-workload protocol and enforce the provisional 100 MiB/s
  baseline-machine gate.
- Close the Phase 3 exit conditions and document remaining P1/Phase 6 work
  without weakening failures or silently skipping unavailable validation.

## Out of scope

- Black-box differential execution against xterm, Ghostty, or Kitty; this is a
  later Phase 6 roadmap item.
- New terminal protocol semantics discovered while building fixtures. Missing
  semantics must be added to ROADMAP at their proper position rather than
  smuggled into the corpus task.
- A persistent snapshot restore format, renderer goldens, native fuzz target,
  coverage service, or CI infrastructure beyond repository-local commands.
- Nondeterministic live application assertions. Real applications are used only
  to produce reviewed, immutable byte recordings; tests replay repository data.

## Dependencies and confirmed facts

- `test/corpus/parser/phase0.json` contains nine probe-action cases in
  `dart-terminal-parser-corpus` version 1. It remains historical evidence and is
  not silently rewritten into final screen state.
- The Phase 0 harness uses a separate `VtStreamProbe`; the product harness must
  exercise `lib/src/terminal_core/vt_parser.dart` and the real screen sink.
- Version 1 state snapshots are multiline UTF-8 strings with a required trailing
  newline. Sidecar files avoid embedding thousands of JSON escapes while
  retaining readable version-control diffs.
- The package has no external test framework. `test/run_tests.dart` invokes
  library-style test entrypoints, so the corpus runner must be reusable from
  both tests and a review CLI.
- Current host tools are zsh 5.9, less 668, Vim 9.1 (patches 1–1752), and macOS
  `/usr/bin/top`. Direct `top` help execution was denied by the sandbox; actual
  recording must use the existing bounded PTY path and request only any narrow
  execution permission that proves necessary.
- Repository `make test` already checks formatting, analysis, generated VT table
  freshness, all Dart tests, and a real PTY session. The Makefile currently has
  no product parser-corpus or product parser-benchmark target.

## Options and decisions

### Inline snapshots versus sidecar snapshot files

Inline JSON preserves the Phase 0 envelope literally but makes the version 1
state format hard to review and repeats escaping inside already escaped row
text. A new product manifest with `input_hex` plus a relative `snapshot` sidecar
is selected. The underlying Phase 0 contracts remain: bytes are exact and
diffable, expectations are source-controlled, changes require manual review,
and the runner never blesses output.

### One monolithic test versus ordered evidence layers

Corpus schema/validation, live fixture capture, generated properties, and
hardware performance have different failure modes and review costs. They are
split below and committed in dependency order. Each child must leave the full
suite passing before the next starts.

### Exhaustive splits for large recordings

Every compact semantic fixture will run all single splits and bytewise. Recorded
application streams must also retain this contract unless measured test cost
requires a separately documented bounded split-plan change. No sampling
exception is assumed in advance.

### Random package versus fixed local generator

Property and mutation cases require exact reproducibility across Dart SDK runs.
A small explicitly seeded integer generator will be used instead of ambient
randomness; every failure must report its seed, case index, and bounded snapshot
diagnostic, and the minimized byte input becomes a permanent fuzz seed.

## Ordered subtasks

1. **Bounded product corpus manifest and replay harness**
   - Define strict format/version/path/size/limit validation, small reviewed
     semantic fixtures, whole/all-split/bytewise execution, readable failure
     diagnostics, a review-only print mode, test-runner integration, and a
     Makefile target.
   - Complete when malformed manifest/hex/path/snapshot bounds are tested and
     the initial product fixtures pass in JIT and Release AOT.
2. **Recorded shell, less, top, and vim streams**
   - Capture deterministic bounded PTY output, document environment and
     sanitization, add reviewed bytes/snapshots, and replay each through the same
     harness without runtime dependence on installed applications.
   - Complete when all four recordings satisfy the accepted chunk plans and no
     fixture contains host/user-specific or unstable content.
3. **Deterministic property tests and fuzz seed corpus**
   - Exercise arbitrary byte/chunk sequences, recovery, repeatability,
     topology/caps, and fixed seed mutations; preserve minimized boundary cases
     as reviewed source fixtures.
   - Complete when runs are deterministic, bounded, diagnosable, and pass in
     JIT and Release AOT.
4. **Product parser Release AOT throughput and Phase 3 exit audit**
   - Add the capture-disabled mixed workload, warm-up/result validation, stable
     machine-readable output, and the 100 MiB/s gate; run the complete Phase 3
     suite and core dependency/source audit.
   - Complete when the baseline-machine gate passes, every Phase 3 exit condition
     has recorded evidence, parent progress is checked, and the child is
     committed.

## Acceptance criteria

- Corpus loading is deterministic and rejects unknown format/version, duplicate
  IDs, unsafe paths, invalid/oversized hex, invalid dimensions/limits, missing or
  oversized snapshots, trailing-newline violations, empty cases, and aggregate
  budget overflow.
- Expected snapshots are never generated or changed by a normal test command.
- Every accepted compact fixture produces exact final state for whole, all
  single splits, and bytewise chunks, with bounded first-difference diagnostics.
- Shell prompt, `less`, `top`, and `vim` recordings replay without consulting
  host locale, time, process state, filesystem, installed app versions, or PTY.
- Fixed property/fuzz runs always reproduce from their reported seed and never
  exceed parser, screen, history, reply, diagnostic, or test-work limits.
- Release AOT product parser throughput is at least 100 MiB/s on the M1 baseline
  and publishes parsed bytes, elapsed time, rate, action counters, and stable
  consumption evidence.
- Terminal core remains free of AppKit, Metal, FFI, native source, and hidden
  network dependencies.

## Verification plan

- Focused corpus loader/replay, malformed-fixture, application recording,
  property, fuzz, and benchmark tests as each child is implemented.
- `dart analyze`, `make test`, dedicated corpus target, focused Release AOT
  executables, benchmark repeated runs, `git diff --cached --check`, and
  `make runtime-source-check`.
- Final source/dependency inspection plus explicit mapping from results to all
  five Phase 3 exit conditions.

## Investigation log

- 2026-09-05: after snapshot diagnostics commit `b34d016`, reread the clean
  worktree, README, ROADMAP, FEATURE_MATRIX, Phase 0 parser corpus and benchmark
  decisions, historical probe/harness, current Makefile, and available host
  applications. This parent is the first unchecked roadmap item and the final
  implementation item before the Phase 3 exit conditions.
- 2026-09-05: confirmed the historical corpus loader accepts unchecked casts,
  unbounded filesystem input, and probe-only action snapshots. It is useful
  evidence but cannot be reused directly as the product final-state harness
  without adding strict cold-path validation and a screen-aware oracle.
- 2026-09-05: direct `top -h` was blocked by the sandbox, while executable
  discovery succeeded. This is not yet a task blocker because live capture is
  ordered subtask 2 and can use the established PTY integration path.
- 2026-09-05: the first focused corpus test passed. Static analysis then found
  only an alphabetic directive-order info in `test/run_tests.dart`; the new
  corpus-test import was moved before the runtime test import. No product or
  fixture behavior changed.

## Verification results

### Bounded product corpus manifest and replay harness

- Added `dart-terminal-product-parser-corpus` version 1. Its manifest keeps
  byte-exact hexadecimal input and points to a reviewed UTF-8 version 1 terminal
  snapshot sidecar. The four initial semantic cases cover Unicode width and
  combining graphemes with SGR, bounded history plus insert/delete editing,
  palette/default mutation with alternate/1049 ownership and query replies, and
  parameter/string/malformed/UTF-8/incomplete recovery.
- The cold-path loader strictly checks the exact root/case/nested key sets,
  format/version, 1–128 cases, unique safe IDs, bounded control-free
  descriptions, exact hex digits, nonempty 16 KiB-per-case input, 64 KiB
  aggregate input, 65,536 aggregate split runs, rows/columns/cells, every parser
  limit, scrollback limits, the fixed `snapshots/<id>.snapshot` relative path,
  existence, valid UTF-8, versioned header, trailing newline, and 16 MiB
  snapshot-file cap.
- Each accepted case creates the product `VtParser`, screen-set sink, bounded
  scrollback, and reply callback; finishes to ground; validates primary,
  alternate, and history topology; and compares the shared final-state snapshot
  for whole input, every single split including empty ends, and bytewise chunks.
  The aggregate FNV-style consumption hash is also stable.
- Review mode prints delimited actual snapshots through a supplied `StringSink`
  and deliberately performs no expected-file write. Tests preserve and compare
  the source-controlled bytes before/after review mode. The Makefile exposes
  `make product-parser-corpus` for normal replay.
- Loader regression tests reject unknown format/version/keys, empty and 129-case
  manifests, duplicate IDs, invalid/odd/empty/over-16-KiB hex, unsafe snapshot
  paths, invalid dimensions/parser limits, missing/non-regular snapshots,
  missing or duplicate trailing newline, wrong snapshot header, and a sparse
  16,777,217-byte snapshot.
- The reviewed corpus passed with 4 cases, 156 input bytes, 164 exhaustive
  split/bytewise runs, and snapshot hash `1242323160`. The focused test and
  dedicated Make target passed. `dart analyze` reported no issues. `make test`
  passed dependency resolution, generated table freshness, formatting of 71
  files with zero changes, full analysis, all unit/integration tests, and the
  real PTY suite. The focused test compiled and passed as Release AOT at
  `/private/tmp/dart-terminal-product-corpus-test`.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 135 tracked files and zero native source files.

This completes ordered subtask 1. Recorded shell, less, top, and vim streams are
now the first unchecked child.

## Risks and handoff

- Application recordings can encode host paths, usernames, timestamps, process
  identifiers, locale-dependent glyphs, or version banners. Capture tooling and
  review must reject or normalize those before committing fixtures.
- Exhaustive split replay cost grows quadratically when each run formats a large
  final state. If an actual measured recording exceeds a practical local-test
  budget, record the measurement and split contract decision here before
  changing the accepted plan.
- A throughput failure is a real Phase 3 blocker. It may motivate profiling and
  Dart optimization but does not authorize moving parser semantics native or
  lowering the 100 MiB/s gate.
