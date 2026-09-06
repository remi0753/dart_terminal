# Phase 6 — Black-box terminal differential harness

## Task identity

- Date started: 2026-09-07
- Scope: second Phase 6 compatibility-hardening roadmap item
- Status: subtask 1 complete; subtasks 2–3 pending

## Purpose and background

Build a bounded, reproducible harness that sends identical byte streams to
Dart Terminal and independently installed xterm, Ghostty, and Kitty processes,
then compares observations without linking, importing, or translating their
implementation source. The preceding inventory defines the selectors and gaps;
this task provides observable evidence for later implementation decisions.

The word "black-box" means that a comparator is invoked as an external product
process through a documented adapter. Checked-in recordings may preserve a
reviewed result, but a fixture that merely echoes a Dart-produced expectation
is never comparator evidence.

## Ordered subtasks

1. **Versioned case, observation, and driver contract**
   - Define strict bounded manifests for byte-exact inputs, dimensions,
     observation fields, comparator provenance, and expected agreement policy.
   - Add a Dart Terminal in-process backend plus a subprocess driver protocol
     and deterministic comparison/reporting layer.
   - Exercise timeout, output-size, malformed response, crash, unavailable,
     and semantic mismatch paths with hermetic test drivers.
   - Complete when the contract is documented, freshness/validation checks are
     in the normal test gate, and the full repository suite passes.
2. **Pinned xterm, Ghostty, and Kitty adapters**
   - Implement product-specific launch/capture adapters using only documented
     product interfaces, with exact executable/version/config provenance.
   - Keep GUI/display dependencies explicit and classify an absent comparator
     as unavailable rather than agreement or failure.
   - Complete when each adapter has a bounded self-test and at least one genuine
     black-box capture on a compatible host, or a concrete documented upstream
     impossibility that requires roadmap replanning.
3. **Reviewed differential corpus and acceptance report**
   - Select high-value inventory cases, execute the available comparators, and
     check in content-safe normalized observations with exact provenance.
   - Produce deterministic mismatch reports and reduce actionable differences
     to byte-level cases assigned to later ordered tasks; do not silently
     rewrite accepted output.
   - Complete when the corpus covers core editing/rendition/mode/query families,
     every result is agreement, accepted quirk, explicit gap, or unavailable,
     and all focused/full checks pass.

Each subtask is documented, verified, committed independently, and followed by
a ROADMAP reread. The parent remains incomplete until all three are complete.

## Scope

- Host-to-terminal byte streams selected from the Phase 6 inventory.
- Deterministic dimensions, initial/reset state, terminal replies, cursor/mode
  state, visible text/style observations where an external product exposes them,
  and explicit normalization that does not erase semantic differences.
- External process deadlines, stdout/stderr/record caps, exact version/config
  capture, safe temporary directories, and classified failure results.
- macOS M1/arm64 as the primary acceptance host.

## Out of scope

- Importing or linking Ghostty, Kitty, or xterm parser/terminal libraries.
- Treating source-level tests or a copied algorithm as black-box evidence.
- Implementing compatibility gaps found by the harness before their ordered
  roadmap task.
- The `vttest` adoption decision and real-application matrix, which are the next
  separate roadmap items.
- Long-duration operation. Per the user-requested global ROADMAP policy,
  duration-only evidence is lower priority and omission is not a blocker;
  deterministic hangs, crashes, data corruption, and unbounded resources are.

## Dependencies and initial facts

- `compatibility/sequence_mode_inventory.json` revision 2 is the source of
  selector identity and support classification; 85 implementation records
  reconcile exactly with product declarations.
- `TerminalSnapshotFormatter` already provides a bounded deterministic product
  state oracle, and `tool/product_parser_corpus.dart` provides strict hex input,
  dimensions, limits, and non-rewriting snapshot precedents.
- The current host has no `xterm`, `ghostty`, or `kitty` executable on `PATH` or
  under `/Applications` at task start. Absence is an adapter availability state,
  not proof of compatibility and not yet a severe blocker for the contract
  subtask.
- Official Kitty documentation exposes remote launch/send-text/get-text
  controls; official xterm documentation exposes Media Copy text/ANSI and
  XHTML/SVG screen dumps. A stable externally observable Ghostty capture
  interface still requires primary-source investigation.

## Completion conditions

- Inputs and observations are byte/version exact, schema validated, bounded,
  deterministically ordered, and safe to inspect in review.
- Dart Terminal and external drivers implement the same documented contract;
  timeouts, crashes, malformed output, missing tools, and mismatches cannot be
  mistaken for agreement.
- Comparator provenance includes product, exact version/build identity,
  executable identity, normalized configuration, host architecture, and capture
  method without terminal content leaking into diagnostics.
- Reviewed results trace to inventory records and later roadmap ownership.
- ROADMAP/FEATURE_MATRIX/docs, focused tests, and the full gate are synchronized.

## Verification plan

- Focused schema tests for unknown fields, invalid IDs/hex, unsafe paths,
  duplicate cases, unsupported observation versions, excessive dimensions,
  input/output limits, and inconsistent agreement policies.
- Hermetic subprocess-driver tests for partial JSON-line reads, exact success,
  timeout, nonzero/signal exit, output overflow, malformed response, duplicate
  result, and missing executable.
- Product-backend replay through whole input, every single split, and bytewise
  delivery for selected cases.
- Adapter self-tests and version/provenance checks on hosts that provide each
  comparator, followed by `CI=true make test` per subtask.

## Investigation log

- 2026-09-07: after commit `62800e4`, reread ROADMAP and confirmed this is the
  first unchecked item. The worktree was clean. README, FEATURE_MATRIX, the
  inventory/support summary, snapshot formatter, product corpus harness/tests,
  and earlier parser-oracle design notes were reviewed before changes.
- 2026-09-07: the item combines a reusable protocol, three product-specific GUI
  capture paths, and a reviewed differential corpus. It was split before code
  changes so an adapter or host dependency cannot blur the contract acceptance
  or cause later corpus work to be implemented out of order.
- 2026-09-07: official Kitty remote-control documentation supports launching a
  controlled child, sending base64/text input, and retrieving window text.
  Official xterm documentation supports configured printer/Media Copy output and
  UTF-8 XHTML/SVG dumps. These preserve more semantic state than raw PTY logging,
  which records input bytes but not the emulator's final screen.
- 2026-09-07: adopted a single-request/single-observation JSON subprocess
  protocol rather than a shell pipeline. Cases use exact hexadecimal input,
  power-on initial state, bounded rows/columns, inventory IDs, canonically
  ordered comparison fields, and either `agree` or a `documented-gap` with a
  safe docs owner. The contract-smoke manifest contains cursor/edit/SGR and
  DEC-mode-query cases only; it is infrastructure coverage, not reference
  product evidence or the later reviewed corpus.
- 2026-09-07: observation version 1 records every visible cell's grapheme/width,
  style flags and logical colors, row soft-wrap, cursor presentation, ten
  relevant modes, exact reply bytes, active screen, and product provenance.
  Provenance requires product/version/revision, capture method, OS/architecture,
  normalized config ID and SHA-256; an external product must also provide an
  executable SHA-256. The in-process contract smoke uses the SHA-256 of an empty
  isolated configuration to mean product defaults.
- 2026-09-07: the comparator evaluates only the case's explicitly listed fields
  and reports bounded content-free coordinates such as `text@0,0`. `agree`
  accepts only equality; `documented-gap` accepts only an actual mismatch, so a
  later accidental/stale gap is visible rather than silently retained. Mode
  comparison is key-based and therefore independent of JSON object ordering.
- 2026-09-07: the external driver runner requires an absolute executable path,
  never invokes a shell, bounds arguments/stdout/stderr, sends one bounded
  request, enforces a two-minute maximum deadline plus bounded pipe drain, and
  uses SIGKILL after timeout/overflow. Missing executable, start failure,
  timeout, signal/nonzero crash, output overflow, malformed/duplicate response,
  and success are distinct states; none except parsed success contains an
  observation or can be treated as agreement.
- 2026-09-07: the Dart backend builds a fresh canonical screen, captures bounded
  replies, validates screen/history topology, and emits the common observation.
  Both contract cases are identical for whole input, all 26 single-split plans,
  and two bytewise plans (`cases=2 input_bytes=24 split_runs=28`). The first
  focused driver test failed because its privacy assertion incorrectly rejected
  the safe public case ID in a machine line; the assertion was corrected to ban
  input/stderr content while retaining the case ID. The subsequent focused test
  passed partial response, malformed/duplicate response, nonzero/signal exit,
  timeout, stdout/stderr caps, start failure, and unavailable cases.
- 2026-09-07: subtask 1 final verification passed the standalone normal-gate
  target and `CI=true make test`: parser/inventory/implementation freshness,
  the differential contract's 28 split runs, formatting of 150 files, full
  static analysis, all focused subprocess classifications, and the complete
  Dart Terminal test runner. No external comparator was installed or claimed in
  this contract-only subtask.
