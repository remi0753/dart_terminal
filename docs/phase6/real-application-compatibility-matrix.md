# Phase 6 — Real-application compatibility matrix

## Task identity

- Date started: 2026-09-07
- Scope: fourth Phase 6 compatibility-hardening roadmap item
- Status: complete; all three ordered children committed or ready for the
  current completion commit

## Purpose and background

Replace anecdotal application launches with a versioned, bounded matrix for
tmux, ssh, mosh, Neovim, Emacs, ncurses, fzf, and lazygit. Each result must
identify the exact application/runtime/scenario, retain observable evidence,
and distinguish pass, compatibility gap, unavailable dependency, and harness
failure. A process exit alone is not proof that the screen, input, modes, or
resize behavior was correct.

## Ordered subtasks

1. **Versioned matrix contract and hermetic runner**
   - Define strict application/scenario/provenance/result schemas and bounded
     process/PTY observation rules.
   - Add deterministic validation, failure classification, and normal-gate
     tests without claiming that any external application has passed.
   - Complete when the contract is documented and focused/full checks pass.
2. **Pinned application execution and normalized evidence**
   - Resolve exact versions and safe launch scenarios for all eight matrix
     applications, using current-host tools where valid and pinned temporary
     artifacts or explicit unavailable records otherwise.
   - Execute bounded scenarios through the product PTY/terminal-core boundary,
     retaining only reviewed content-safe evidence and exact provenance.
   - Complete when all required matrix cells are captured or explicitly
     unavailable; a missing optional product is not agreement.
3. **Acceptance classification, gap reduction, and matrix closure**
   - Classify every result, reduce compatibility failures to byte-level
     regressions, assign later ROADMAP owners, and reject silent/unowned cells.
   - Synchronize ROADMAP/FEATURE_MATRIX/docs and close the parent only after
     focused/full verification passes.

The children are ordered and committed independently. ROADMAP is reread after
each commit before the next child starts.

## Scope

- One or more bounded representative workflows for each named application.
- Exact executable/version/config/environment provenance and deterministic
  dimensions, deadlines, input steps, output caps, and cleanup ownership.
- Terminal replies and canonical Dart screen/mode/cursor state where the
  product boundary can observe them.
- M1/arm64 Developer JIT or Release AOT as the product acceptance baseline;
  a headless core replay may supplement but not replace product-path evidence.

## Out of scope

- Implementing gaps before they are minimized and assigned in ROADMAP order.
- Contacting arbitrary external ssh/mosh hosts or using user credentials.
- Importing application terminal implementations into the product.
- Treating long-duration use as a normal blocker. Duration-only soak is lower
  priority per ROADMAP; deterministic crash, corruption, data loss, security,
  or unbounded-resource failures remain blockers.

## Dependencies and initial facts

- The black-box terminal differential contract already provides strict
  versioned JSON, bounded subprocess behavior, provenance, and mismatch
  classification patterns that can be reused without conflating applications
  with terminal comparators.
- Phase 3 product corpus contains reviewed shell, less, top, and vim streams,
  but those recordings are not evidence for the eight named application
  versions or the current live product boundary.
- Runtime integration tools already launch both Developer JIT and Release AOT
  application bundles; their support for scripted child applications and
  canonical screen observation must be inspected before choosing the runner.
- The current host exposes `/usr/bin/ssh` as OpenSSH 10.3p1 with LibreSSL
  3.3.6 and Homebrew ncurses 6.6 at `/opt/homebrew/opt/ncurses`. The system
  ncurses reports 6.0.20150808. tmux, mosh, Neovim, Emacs, fzf, and lazygit are
  absent from `PATH`; Homebrew itself is 6.0.22, and the inspected prefix has
  OpenSSL 3.6.3 but no libevent or protobuf installation.
- Persistent package installation is unnecessary for the matrix contract and
  would mutate the developer host. The execution child therefore prefers
  official pinned arm64 archives or source builds under `/private/tmp`, uses a
  current-host binary only with exact provenance, and emits an explicit
  unavailable record when a safe bounded artifact cannot be resolved.

## Completion conditions

- The matrix contract is strict, bounded, versioned, content-safe, and cannot
  turn unavailable/crash/timeout/malformed evidence into a pass.
- All eight named applications have exact provenance and reviewed results for
  their required scenarios, or a documented nonblocking unavailable state.
- Each visible/input/mode/resize assertion is tied to an observable boundary;
  unobserved properties are not implied by process success.
- Every failure is either fixed with a minimized byte regression, assigned to a
  later ordered owner, or reported as a serious blocker.
- Normal focused and full repository gates pass for every child.

## Verification plan

- Schema and runner negative tests for unknown fields, unsafe paths, duplicate
  IDs, excessive commands/output/deadlines, absent executables, timeout, crash,
  malformed evidence, content leakage, and incomplete cleanup.
- Deterministic replay/capture tests for exact scenario order and observations.
- Product-path runs where automation supports reliable visible-state evidence.
- `CI=true make test`, format/analyze, diff review, and process/resource cleanup
  before each completion commit.

## Acceptance-child implementation plan

The final child replays each immutable raw PTY stream through the product parser
and a tool-only tracing delegate. For every parser action, the delegate compares
the product sink's unsupported counter before and after dispatch and reconstructs
the shortest equivalent 7-bit control sequence from the parser's typed action.
Raw-evidence parser counters remain immutable capture-time provenance. The
acceptance report pins the current implementation manifest, records both the
captured and current replay count for every cell, and derives current gaps from
the replay. Other parser diagnostics must remain identical to capture. This
allows an implemented selector to close a pinned byte regression without
rewriting the original capture, while any new current reject still requires an
exact owned variant in the report.

Unique reconstructed sequences are recorded with per-application occurrence and
counter-increment totals. Each must be classified against the versioned
sequence/mode inventory as implemented, safe-ignore, or explicit unsupported,
with a concrete existing or later ROADMAP owner. A sequence that mutates visible
state before being rejected, lacks an owner, cannot be reproduced from immutable
evidence, or produces cancel/limit/malformed/incomplete state is a matrix blocker.
The checked-in acceptance report pins all source evidence and minimized gap
artifacts. A normal Make gate replays and validates it; summary documentation and
`FEATURE_MATRIX.md` are synchronized only after that gate and the full suite pass.

## Versioned contract

The reviewed manifest is
`test/corpus/applications/matrix_v1.json`. It uses format
`dart-terminal-real-application-matrix`, version 1, observation version 1, and
scope `phase6-reviewed`. The contract requires the exact sorted application set
`emacs`, `fzf`, `lazygit`, `mosh`, `ncurses`, `neovim`, `ssh`, and `tmux`.
Each currently has one bounded scenario; adding scenarios requires sorted,
globally unique IDs and a reviewed manifest change.

The schema caps the manifest at 1 MiB, 16 applications, 64 aggregate scenarios,
256 rows, 512 columns, 65,536 cells, 30 seconds per application operation,
1 MiB of PTY output, 32 semantic checks per scenario, and fixed canonical
observation-field order. Every scenario must observe at least stream, canonical
screen, and process exit. The initial matrix also requires cursor, mode, and
resize evidence, giving 48 required fields and 48 named checks across 8
scenarios.

An external driver receives one JSON request containing only application and
scenario IDs, geometry, limits, required field names, and check IDs. It does
not receive a shell command or prose description from the manifest. One valid
response contains:

- exact application/scenario/driver identity;
- product version, executable/config hashes, capture method, OS, and
  architecture provenance;
- the exact required observed-field list;
- bounded PTY output byte count/hash and a raw evidence artifact hash;
- all named semantic checks in canonical order, each retaining true or false.

Semantic failure is a valid observation with a false check, not a harness
crash. The subprocess runner separately classifies `ok`, `unavailable`,
`startFailure`, `timedOut`, `crashed`, `outputLimit`, and `protocolError`.
It never invokes a shell, requires an absolute driver executable, limits
arguments/stdout/stderr/deadline, kills only its child on timeout or overflow,
and exposes only scalar identifiers/counts in its machine line. A missing
driver cannot become a pass.

## Pinned execution evidence

`tool/terminal_application_capture_driver.dart` executes each reviewed recipe
through `dart_pty_macos`, `VtParser`, and `TerminalScreenSet`. It records the
bounded raw PTY byte stream, terminal replies, two resize observations, parser
counters, process exit, and four canonical screen snapshots. The driver owns
all child processes and temporary directories. Recipes use only controlled
content: an isolated Emacs buffer, fixed fzf candidates, an isolated lazygit
repository, a local mosh client/server pair, the reviewed ncurses fixture, an
isolated Neovim buffer, an ephemeral-key loopback sshd, and an isolated tmux
socket/session. No user credentials or remote hosts are used.

`tool/generate_terminal_application_evidence.dart` generated the checked-in
index at `compatibility/application_matrix_evidence.json` and one raw capture
plus normalized observation per scenario under
`test/corpus/applications/external/`. The exact sources are:

- GNU Emacs 31.1 source, SHA-256
  `1da5790d9580c81932b5bf700633114468da7b3412d69faa767daebf974f4586`,
  built terminal-only without NS/X/native compilation;
- fzf 0.74.3 Darwin arm64 archive, SHA-256
  `1f8501cea4f9c0c2d6110d0ff75d0ec9451cd9d7524d9a26244a154ea89f3bd5`;
- lazygit 0.65.0 Darwin arm64 archive, SHA-256
  `d8ea1cade9e4279e45cbb58652e84edb07e98a9f8ec0604099c8b0a8f709e63a`;
- mosh 1.4.0 upstream universal macOS package, SHA-256
  `14d3ef7e0a0dfff7b284102d44da91f88a24921bbb07ff2ac6875e7075a4b207`;
- Homebrew ncurses 6.6.20251230 plus
  `test/corpus/applications/support/ncurses_resize_fixture.c`;
- Neovim 0.12.2 macOS arm64 archive, SHA-256
  `eeddee1009734f9071266e6b1b8a70308cb60cbcc45f5e1c1023adc471450fee`;
- macOS `/usr/bin/ssh` 10.3p1 with LibreSSL 3.3.6, executable SHA-256
  `17542914a3fb55e7efeb35a90d594a21c84bf6a4cfe1fc8ddff5606dc2658fc3`;
- tmux 3.6b source, SHA-256
  `390759d25fdba016887ec982b808927e637070fd7d03a8021f8ef3102b9ae3c7`,
  built with libevent 2.1.13-stable source SHA-256
  `f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c`
  and Homebrew ncurses.

All eight cells were captured. The aggregate is 57,737 PTY bytes and 32
snapshots. All cells exited cleanly, kept the cursor bounded, displayed the
controlled marker, restored the primary screen, and observed both resizes.
SSH also had a clean parser result. The other seven retain `parser-clean=false`
because they emitted unsupported sequences: Emacs 3, fzf 28, lazygit 42, mosh
7, ncurses 297, Neovim 124, and tmux 25. None recorded cancel, size-limit,
malformed, incomplete, or rejected-reply events. These are intentionally not
called accepted here; the ordered acceptance child must identify the exact
bytes, collapse duplicates, and classify each sequence before the matrix can
close.

`tool/terminal_application_evidence.dart` is the normal-gate validator. It
pins source identities and hashes, matrix and driver freshness, exact cell
membership, relative evidence paths, raw/normalized artifact hashes, bounded
output and snapshot hashes, required stages/resizes/parser counters, semantic
check derivation, and content safety. It rejects home-directory paths, user
names, mosh keys, private keys, authorized-key paths, or unresolved random
temporary paths. Its success line is `TERMINAL_APPLICATION_EVIDENCE_PASS
cells=8 output_bytes=57737 samples=32 passed_checks=41 failed_checks=7`.

## Acceptance classification

`tool/terminal_application_unsupported_trace.dart` replays the immutable raw
stream while applying both recorded resizes at their original byte offsets. A
tool-only `VtParserSink` delegate records an action only when the product sink's
unsupported counter increases, then reconstructs the equivalent 7-bit bytes
from the typed parser action. The capture-time surface accounted for all 526
unsupported increments as 28 unique observed variants; the current OSC-title
closure replay accounts for 92 increments as 20 variants. It does not infer
bytes from documentation or scan arbitrary escape-looking text inside
printable payloads.

`compatibility/application_matrix_acceptance.json` groups those variants into
13 minimized, owned gaps. Each `minimal_hex` is the shortest variant actually
present in evidence. Replaying each minimal sequence produces exactly one
bounded reject, no cancel/limit/malformed/incomplete result, and no standalone
screen-state mutation. The remaining DECRQSS DCS query matches an inventory
`safe-ignore` record; the other 12 remain explicit unsupported rather than
being silently normalized into success.

| Gap | Observed applications | Current impact/disposition | Ordered owner |
| --- | --- | --- | --- |
| focus reporting | Emacs, lazygit, mosh, Neovim, tmux | input events; explicit unsupported | Phase 6 focus/mouse/query task |
| highlight/pixel mouse | mosh, lazygit | input events/coordinates; explicit unsupported | Phase 6 focus/mouse/query task |
| XTVERSION and window-size report | Emacs, lazygit, tmux | query fallback; explicit unsupported | Phase 6 focus/mouse/query task |
| DECRQSS | Neovim | query fallback; safe-ignore | existing DECRQSS gap/query owner |
| Kitty query, XTMODKEYS, XTQMODKEYS, application escape | lazygit, Neovim, tmux | input protocol; explicit unsupported | Phase 9 Kitty keyboard task |
| synchronized output | fzf, lazygit | presentation atomicity; explicit unsupported | Phase 9 synchronized-output task |
| theme report/update | tmux | query/notification fallback; explicit unsupported | Phase 9 light/dark reports task |

Character-set designation was a visible rather than safe-ignore gap: ignoring
`ESC ( 0` left following ACS bytes with the wrong glyph meaning. The terminfo
closure now implements per-screen G0/G1 state, SO/SI invocation, and DEC
Special Graphics, so those variants are no longer listed. The captured
XTGETTCAP `Ms` query now receives an explicit unavailable response consistent
with the audited database's OSC 52 cancellation. Other owned protocol gaps are
not claimed as implemented.

The OSC title policy subsequently implemented the four captured title-stack
variants with a bounded session-owned stack. Those variants also disappeared:
lazygit now has 38 current increments, ncurses has zero and is a clean
agreement, and tmux has 10. The remaining XTWINOPS variants are window-size
queries owned by the following focus/mouse/query task; they stay explicit
unsupported parameter variants of the partially implemented selector.

The final OSC-policy child recognizes bounded OSC 52 and enforces an explicit
default denial. None of the 57,737 immutable application bytes contains OSC 52
itself; the captured `Ms` XTGETTCAP query still receives unavailable because
the bundled terminfo must not advertise unusable opt-in clipboard access.
Replaying all eight cells therefore retains 92 unsupported increments, 20
variants, and 13 owned gaps; only the implementation-manifest provenance pin
changes.

The cell outcome is two clean agreements (ncurses and SSH) and six accepted documented-gap
cells. “Accepted” means the captured workflow completed, every non-parser
semantic check passed, all rejected bytes are explicit and owned, and no
matrix-level crash/corruption/unbounded-resource blocker remains. It does not
turn any false `parser-clean` check into true. The normal gate reports
`TERMINAL_APPLICATION_ACCEPTANCE_PASS accepted=8 clean=2
documented_gap_cells=6 gaps=13 unique_sequences=20
unsupported_increments=92`.

The version-2 acceptance report pins the current product implementation
manifest. It retains the original capture counters per cell while recording
the current replay counters, so compatibility fixes are demonstrated against
immutable PTY bytes rather than by rewriting their provenance.

## Investigation log

- 2026-09-07: OSC title/title-stack closure replay retained the same 57,737
  immutable PTY bytes and resize offsets. Current unsupported counts fell from
  98 to 92: lazygit 40→38, ncurses 2→0, and tmux 12→10. Four title-stack
  variants and their owned gap disappeared; ncurses became the second clean
  agreement. No capture provenance or original counter was rewritten.
- 2026-09-07: the terminfo closure replay used the same 57,737 immutable PTY
  bytes and original resize offsets. Current unsupported counts fell from 526
  to 98: lazygit 42→40, ncurses 297→2, Neovim 124→6, and tmux 25→12; Emacs,
  fzf, mosh, and SSH were unchanged. All three observed character-set variants
  and the single `Ms` XTGETTCAP variant disappeared from the reject trace.
- 2026-09-07: rewriting original capture counters would misrepresent the
  product version that produced those snapshots, while requiring equality
  forever would prevent a pinned regression corpus from proving a fix. The
  acceptance contract therefore advances to version 2, pins the current
  implementation manifest, and records captured/current counts per cell. It
  still rejects any current unowned variant and still requires cancel, limit,
  malformed, incomplete, and unsupported-control diagnostics to match the
  immutable capture.

- 2026-09-07: after commit `fdc56f7`, ROADMAP was reread with a clean worktree.
  README, FEATURE_MATRIX, vttest decisions, differential evidence, and Phase 6
  exit conditions were reviewed. The eight-product item spans reusable
  infrastructure, external dependency execution, and semantic acceptance, so
  it was split before implementation.
- 2026-09-07: the first focused contract run stopped in a negative fixture,
  before any external application execution. Replacing only the `emacs`
  application ID correctly triggered the scenario-prefix invariant before the
  intended required-eight-products invariant. The fixture now replaces the
  final `tmux` application and its scenario with a still-sorted, prefix-valid
  unknown ID so it isolates the exact set check; no validator was weakened.
- 2026-09-07: the first full gate reached and passed the complete test runner,
  but static analysis reported one directive-ordering info because the new
  application-matrix test import preceded the lexically earlier AppKit import.
  The import order was corrected; the gate is not treated as clean until the
  repeated analyzer and full run pass.
- 2026-09-07: the repeated analyzer reported no issues. Focused tests pass
  manifest/observation round trips and negative bounds plus partial JSON writes,
  semantic false, malformed/duplicate responses, nonzero/signal exit, timeout,
  stdout/stderr overflow, missing executable, and non-executable start failure.
  The standalone normal target reports `applications=8 scenarios=8
  required_fields=48 checks=48`.
- 2026-09-07: the repeated `CI=true make test` passed every compatibility
  freshness gate, formatted 163 files without changes, completed clean static
  analysis, and passed the full Dart Terminal test runner. This child records
  no external application pass; exact tools and evidence belong to the next
  ordered child.
- 2026-09-07: execution-child discovery found OpenSSH 10.3p1 at
  `/usr/bin/ssh`, Homebrew ncurses 6.6.20251230, and system ncurses
  6.0.20150808. The other six matrix programs are not on `PATH`. libevent and
  protobuf, needed by local tmux/mosh source builds respectively, are also
  absent. This is a provenance fact rather than an application failure; safe
  temporary artifacts are investigated before any cell may be classified
  unavailable.
- 2026-09-07: upstream release inspection identified tmux 3.6b and its
  libevent/ncurses build dependencies, Neovim 0.12.2 with an official macOS
  arm64 archive, and lazygit 0.62.0. fzf's upstream installer confirms the
  Darwin arm64 archive naming convention. Exact archive URLs and hashes are
  retained in the eventual backend catalog rather than inferred from mutable
  `latest` URLs.
- 2026-09-07: exact current artifacts were resolved as fzf 0.74.3
  (`1f8501ce…f3bd5`), lazygit 0.65.0 (`d8ea1cad…9e63a`), Neovim 0.12.2
  (`eeddee10…50fee`), and tmux 3.6b (`390759d2…ae3c7`). The official mosh
  1.4.0 macOS package is universal arm64/x86_64, and its client/server link
  only macOS system ncurses, zlib, libc++, and libSystem; it can therefore run
  from a temporary package expansion without installing protobuf.
- 2026-09-07: the first formatter invocation did format the new capture
  driver, then returned nonzero because Dart telemetry attempted to update
  `<HOME>/.dart-tool/dart-flutter-telemetry-session.json` outside the
  workspace sandbox. This is an environment permission failure after the
  formatting operation, not a source-format failure; Dart verification is
  rerun with the already-approved external cache access rather than ignored.
- 2026-09-07: the first live Emacs cell exited before resize with
  `standard input is not a tty`. The cause was not Emacs: after the driver
  consumed and closed its request pipe, the native exec-error pipe could reuse
  fd 0; the forked child then closed that numeric pipe descriptor after
  `forkpty` had rebound fd 0 to the slave, accidentally closing PTY stdin.
  `dart_pty_macos` now moves both internal pipe descriptors above stderr before
  forking. A subprocess regression closes its parent stdin, launches
  `/usr/bin/tty`, and requires a `/dev/ttys…` result. The complete package test
  passed all ten cases, including the new regression and async exec failure.
- 2026-09-07: the short-lived diagnostic which exposed controlled Emacs bytes
  as base64 was removed once the fd collision was identified. Normal driver
  failure diagnostics remain content-free (byte count and lifecycle error).
- 2026-09-07: after the PTY fix, Emacs completed its real interaction with all
  expected evidence, but the contract rejected the observation because the OS
  identifier `macos-26.6.2` used dots where the versioned identifier grammar
  allows hyphens. The producer was corrected to `macos-26-6-2`; the parser
  contract was not relaxed.
- 2026-09-07: Emacs, fzf, and lazygit then produced valid observations. The
  first mosh attempt stopped before launching its client because the
  content-free canonical-config helper constructed a validating `PtyCommand`
  with the placeholder working directory `<TMP>`, which is not absolute. Both
  mosh and SSH canonical templates now use the valid stable placeholder base
  `/private/tmp`; runtime temporary paths remain excluded from their hashes.
- 2026-09-07: the first evidence-validator regression run reached the intended
  private-path negative case, but the test appended its sentinel after the
  canonical snapshot `end` marker. Snapshot-envelope validation correctly
  rejected that malformed fixture before content-safety validation. The test
  now inserts the sentinel immediately before `end`, recomputes the hash, and
  preserves every earlier invariant so the negative case isolates the intended
  safety check; production validation was not relaxed.
- 2026-09-07: the focused evidence regression and
  `make terminal-application-evidence-check` passed. `CI=true make test` then
  passed every compatibility freshness gate, formatted 167 files without
  changes, completed static analysis with no issues, and passed the complete
  test runner. A post-run process check found no matrix application or sshd
  alive. Two orphan tmux sockets left by earlier failed attempts were removed
  by exact path, and a repeated socket search was empty. The pinned artifact
  build root remains under `/private/tmp/dart-terminal-app-matrix.9gNqAD` only
  to support the immediately following acceptance child; it is not a committed
  runtime dependency.
- 2026-09-07: the first unsupported-sequence replay matched the committed
  parser count for seven applications, but reported 29 rather than 25 for
  tmux. The four extra rejects were valid scroll-region changes whose bottom
  rows only exist after the captured resize. Replaying bytes at the fixed
  initial geometry had lost that causal event. The tracer now applies each
  recorded resize at its exact `output_bytes_before` offset before parsing the
  following redraw; exact counter agreement is required rather than editing
  the evidence or ignoring the discrepancy.
- 2026-09-07: the first acceptance-report check rejected one unobserved
  sequence variant. The report had used the specification-shorter
  `CSI > 4 m` as the XTMODKEYS minimal case, while immutable Neovim evidence
  contains only `CSI > 4 ; 0 m` and `CSI > 4 ; 2 m`. The report now uses the
  shortest actually observed form. No synthetic variant can satisfy the
  evidence coverage gate, and the reviewed unique-sequence total is 28.
- 2026-09-07: eleven gap groups map to existing inventory records. Five newer
  extensions are absent from the four-source inventory rather than being
  mislabeled as an older xterm/DEC control: Kitty `CSI ? u`, synchronized
  output 2026, theme report 996, theme updates 2031, and application Escape
  mode 7727. The official Kitty keyboard specification confirms the query and
  bounded mode-stack requirements; inspected tmux 3.6b `tty.c`/`CHANGES`
  identifies its theme requests, and the captured source itself proves the
  emitted bytes. These remain explicit rejects with existing Phase 9 owners;
  extending their normative inventory belongs to those protocol tasks.
- 2026-09-07: focused acceptance tests passed the exact baseline and negative
  freshness, unowned-sequence, screen-mutation, and unknown-owner cases.
  `make terminal-application-acceptance-check` reported eight accepted cells,
  one clean agreement, seven documented-gap cells, 16 gaps, 28 unique
  sequences, and 526 unsupported increments. Full `CI=true make test` passed
  every freshness gate, formatted 170 Dart files without changes, reported no
  analyzer issues, and passed the complete test runner.
- 2026-09-07: after verification, the exact 699 MiB temporary artifact/build
  root `/private/tmp/dart-terminal-app-matrix.9gNqAD` was deleted. No matrix
  sockets remained. The acceptance Make target passed again after deletion,
  proving the checked-in hashes, raw captures, normalized observations, and
  acceptance report have no runtime dependency on the temporary binaries.

## Verification results

- `dart analyze`: passed with no issues.
- `dart run test/terminal_application_acceptance_test.dart`: passed all normal
  and negative cases.
- `make terminal-application-acceptance-check`: passed before and after
  temporary build cleanup with the exact reviewed totals above.
- `CI=true make test`: passed all compatibility freshness checks, formatting,
  static analysis, and the complete Dart test runner.
- OSC title closure replay: passed with 92 current unsupported increments, 20
  variants, and 13 owned gaps; captured/current counts are exact in every cell.
- `git diff --check`, staged-scope review, and final worktree review are run
  immediately before the completion commit.
- Remaining work is not hidden: the 13 gap owners are pinned in the acceptance
  report and linked from ROADMAP. Character-set and XTGETTCAP gaps are closed;
  later Phase 6/9 owners retain the remaining query, metadata, input,
  presentation, and theme gaps.
