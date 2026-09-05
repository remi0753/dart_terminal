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

### Live application capture contract

The four recordings are captured from the existing `dart_pty_macos` backend at
a fixed 8-by-40 cell size with a parent-independent `TERM=xterm-256color`, C
locale, and fixed `PATH`, shell/prompt, and pager settings. Capture has a 16 KiB
hard output cap, bounded quiet waits, bounded exit waits, and explicit input
scripts. Shell, less, and vim bytes are retained exactly. Their scripts avoid
filenames, version screens, user configuration, and parent environment values.

macOS `top` necessarily renders live clock, process, CPU, memory, network, and
disk status. It is captured in one-shot zero-process mode so no process names,
PIDs, commands, or user values enter the stream. The capture tool then requires
the known C-locale header categories and replaces every complete dynamic header
line with a fixed same-category review line while preserving the captured line
terminators. Missing, duplicate, unknown nonempty lines or control bytes make
capture fail. This intentionally narrow sanitizer prevents an application or
OS format change from being mistaken for reviewed fixture data.

### Property and fuzz execution contract

The property runner uses a locally implemented 32-bit xorshift generator with
a named fixed seed; it does not depend on `Random` implementation details. It
generates 96 bounded mixed byte streams from printable, C0, arbitrary, UTF-8,
and structured VT fragments. Each case is run whole, bytewise, with a generated
chunk plan, and by repeating that plan. Zero to two resize events are applied at
exact byte offsets independently of chunk boundaries. Exact terminal snapshots,
reply count/hash/maximum size, and topology/cap assertions form the result.

A separate strict versioned manifest holds seven reviewed fuzz seeds spanning
parser limits/recovery, malformed and valid UTF-8, palette/resource queries,
alternate-screen/string cancellation, wide/grapheme resize-reflow, and bounded
scrollback/editing. Each is replayed through the same plans and 16 same-length
deterministic mutations. Seed files are limited to 32 cases, 4 KiB per case,
16 KiB aggregate input, eight ordered resize events, and a bounded grid.

Every arbitrary generated case also receives CAN, RIS, and a printable recovery
sentinel in a fresh bounded screen, proving return to printable ground state
without allowing the reset to hide topology/cap behavior in the original run.
Failure messages contain the fixed seed, case index or reviewed seed ID, plan,
and the existing bounded first-difference diagnostic; they do not dump arbitrary
input or complete snapshots.

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
- 2026-09-05: inspected the native PTY API before application capture. It accepts
  an absolute executable, explicit argument/environment vectors, fixed initial
  size, bounded read/write queues, output stream, tracked exit, and force-close
  cleanup. The application recordings can therefore use the production native
  transport without adding a shell-command/file capture dependency to tests.
- 2026-09-05: shell, less, and vim were captured twice; their respective byte
  counts/hashes were stable at `220/255135843`, `164/772262715`, and
  `673/1876375118`. Sanitized top was stable at `207/1717483541`. Piping the
  verbose hexadecimal review output into `head` produced an expected broken-pipe
  exception after the summary line; subsequent review consumes the complete
  output and does not use early-closing pipes.
- 2026-09-05: the first generated property run reached a product invariant
  failure while resizing after arbitrary input:
  `TerminalScrollback.validateCellTopology` reported an invalid logical cell
  offset from `resizeTerminalScreenWithHistory`. The harness initially lacked
  the promised seed/case context for execution exceptions; that diagnostic is
  being added before minimizing and fixing the reproducible product defect.
- 2026-09-05: the failure reproduced as generated seed `0xe0d632c8`, case 7,
  at byte offset 20 while narrowing an 8-by-13 screen to 3-by-4. Reduction
  showed that cursor-addressed canonical blanks preceding five printable cells
  were retained by reflow but became indistinguishable from unused blanks after
  entering scrollback. The following soft-wrapped row therefore expected an
  offset of zero instead of four. A two-byte per-row logical-cell-count field is
  selected over converting blanks to spaces because it preserves terminal text
  semantics while keeping page allocation and eviction accounting explicit.
- 2026-09-05: the fix stores the retained logical-cell count in a bounded
  `Uint16List` per scrollback page, includes its two bytes per row in allocation
  and eviction accounting, validates it against visible topology and page
  width, and uses it when later reflow extracts cursor-significant canonical
  padding. The minimized 11-byte cursor-addressing case is now the seventh
  reviewed fuzz seed and has a direct narrow/widen history regression test.

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

### Recorded shell, less, top, and vim streams

- Added a bounded review-only PTY capture tool using the production
  `dart_pty_macos` backend. It fixes the terminal at 8 rows by 40 columns,
  excludes the parent environment, supplies only C locale/TERM/PATH and
  application-specific stable settings, caps output at 16 KiB, bounds every
  start/quiet/exit/dispose step, and fails on write backpressure or abnormal
  exit. Capture is never invoked by corpus replay or the normal test suite.
- Recorded zsh 5.9, less 668, macOS top, and Vim 9.1 (patches 1–1752). Shell,
  less, and vim recordings reproduced exactly across two captures. Top uses
  one-shot `-l 1 -n 0`; its strict ASCII sanitizer requires one ordered line
  for each known header category, rejects unknown/duplicate/control-bearing or
  incomplete output, and replaces all live values with category-labelled
  `sanitized` text. Sanitizer success and rejection paths have unit coverage.
- Reviewed manifest inputs contain 220 shell bytes, 164 less bytes, 207
  sanitized top bytes, and 673 vim bytes. Searches found no username, home path,
  hostname, date, PID/process row, application version banner, or live CPU,
  memory, network, disk, and load value in the committed inputs or snapshots.
- The expanded corpus passed with 8 cases, 1,421 input bytes, 1,437 exhaustive
  all-single-split/bytewise runs, and snapshot hash `169861547`. Focused tests
  and static analysis passed. The focused executable compiled and passed in
  Release AOT at `/private/tmp/dart-terminal-application-corpus-test`.
  `make product-parser-corpus` passed, and `make test` passed generated-table
  freshness, formatting of 72 files with zero changes, full analysis, every
  unit/integration test, and the real PTY suite.
- The first standalone runtime-source audit attempt was prevented before the
  audit by sandbox denial of Dart's telemetry session-file timestamp update.
  Retrying with the required narrow execution permission passed; this was an
  execution-environment issue, not a source or test failure.
- Final staged-diff whitespace validation passed. The staged-source Dart-only
  audit passed with 140 tracked files and zero native source files.

This completes ordered subtask 2. Deterministic property tests and the fuzz seed
corpus are now the first unchecked child.

### Deterministic property tests and fuzz seed corpus

- Added a dependency-free xorshift32 property runner with fixed root seed
  `0x4d595df4`. Its 96 generated cases mix printable/C0/arbitrary bytes, valid
  and malformed UTF-8, and structured CSI/OSC/DCS/alternate-screen/query
  fragments. Whole, bytewise, generated chunks including empty chunks, and a
  repeated generated plan produce exact matching snapshots and reply digests;
  zero to two resize events are applied at byte-exact boundaries.
- Every generated input is separately followed by CAN, RIS, and `RECOVER` on a
  fresh 4-by-20 bounded terminal. The sentinel is verified in primary row zero
  after bytewise feed. Every run finishes in parser ground, validates primary,
  alternate, and scrollback topology, and checks the 8-line/32-KiB history,
  256-style, 64-grapheme/512-scalar, 64-byte reply, 4,096-cell, and 512-KiB
  snapshot caps.
- Added a strict `dart-terminal-product-fuzz-seeds` version 1 manifest. It
  rejects unknown schema, duplicate/invalid IDs, malformed/empty/over-4-KiB
  hex, over-16-KiB aggregate input, more than 32 seeds or eight resizes, and
  unordered/out-of-range/oversized resize grids. Seven reviewed seeds cover
  parser limits, UTF-8, resources/replies, strings/alternate ownership,
  wide/grapheme reflow, history/editing/eviction, and the minimized
  cursor-padding defect. Sixteen same-length deterministic mutations per seed
  retain resize offsets and exercise the same whole/generated/bytewise oracle.
- The initial property run found a real history-reflow defect at generated seed
  `0xe0d632c8`, case 7, byte 20. Scrollback now retains each row's logical cell
  count in a two-byte typed field, validates it, includes it in byte-cap/page
  allocation, and uses it to recover cursor-significant canonical padding on
  later reflow. Existing allocation expectations were updated, and the minimal
  11-byte narrow/widen test proves both valid offsets and restored padding.
- The stable result is 96 generated cases, 7 reviewed seeds, 112 mutations,
  837 parser executions, 66,675 parsed bytes, and state hash `1724998591`.
  Static analysis passed and two consecutive dedicated Make target runs emitted
  the identical machine line. The focused suite compiled and passed in Release
  AOT at `/private/tmp/dart-terminal-property-fuzz-test`. `make test` passed
  table freshness, formatting of 73 files with zero changes, full analysis,
  all unit/integration tests, and the real PTY suite.
- Final staged-diff whitespace validation passed. The staged-source Dart-only
  audit passed with 142 tracked files and zero native source files.

This completes ordered subtask 3. The product parser Release AOT throughput and
Phase 3 exit audit are now the first unchecked child.

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
