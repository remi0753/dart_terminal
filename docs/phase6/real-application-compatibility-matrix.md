# Phase 6 — Real-application compatibility matrix

## Task identity

- Date started: 2026-09-07
- Scope: fourth Phase 6 compatibility-hardening roadmap item
- Status: in progress; contract child complete, application execution child
  pending

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
- Local availability, exact versions, and network-independent scenarios for all
  eight applications remain to be determined.

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

## Investigation log

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
