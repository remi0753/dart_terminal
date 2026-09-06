# Phase 6 — Black-box terminal differential harness

## Task identity

- Date started: 2026-09-07
- Scope: second Phase 6 compatibility-hardening roadmap item
- Status: subtasks 1–2 complete; subtask 3 baseline child complete, external
  capture and acceptance children pending

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

The third subtask is itself ordered into three independently verified commits:

1. define the reviewed case manifest, immutable Dart baseline observations, and
   deterministic bounded report/freshness gate;
2. execute the pinned external comparators and check in normalized evidence
   without claiming fields their capture boundary cannot observe;
3. reduce mismatches to byte-level cases, classify every result in a reviewed
   acceptance report, and close the parent harness only when no result is
   silently ignored.

The split is required because case selection/report mechanics, GUI/X11 product
capture, and semantic acceptance have different dependencies and failure modes.
The parent and original corpus item remain incomplete through the first two
commits.

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
- 2026-09-07: subtask 2 started after commit `8507b65` and a ROADMAP reread.
  The worktree was clean. The host still had no `xterm`, `ghostty`, or `kitty`
  on `PATH` or in `/Applications`; Homebrew itself was present but none of
  XQuartz, xterm, Ghostty, or Kitty was installed. Two unrelated stopped Lima
  guests were deliberately left untouched. Docker Desktop was present, though
  access to its socket from the restricted build environment still required a
  separate read-only availability check.
- 2026-09-07: selected official comparator pins before writing adapter code.
  Ghostty uses the upstream tip build at source revision
  `492300cad104195411d12217dd22f1cd05f31376`: the universal zip is 33,716,154
  bytes with SHA-256 `50ef638569c8381f9288066cffeb4c9c3ce69d4e702cd5760a65bc046013d0cc`,
  and the DMG is 33,808,577 bytes with SHA-256
  `629e994b85a6c7e224183ca202f2da62ae742a4671b36ad3904d7ca600da78d5`.
  Its reported identity is `Ghostty 1.3.2-main-+492300cad`; the DMG executable
  SHA-256 is `7f8474bf1d5d169a7b0645d19c82ea57ee1ab3c1f43d0f587a6c2be7c5e4fefd`.
  Kitty uses release 0.48.2: its 49,397,324-byte official DMG has SHA-256
  `f804f58ee4b69c76f84eb3281e140748269a63f3f4a816015a8dec2a06d2b195`
  and the contained executable has SHA-256
  `4e58d3cbd3fd2749fd20232602c26c2b7672dfe605760804d55bdcd1b42e6b7c`.
  These values were obtained from the official GitHub release APIs and checked
  again on the downloaded artifacts. Exact source/archive/build pins will be
  used for xterm because upstream distributes source rather than a macOS app.
- 2026-09-07: both read-only DMGs were mounted under `/private/tmp`. Initial
  sandboxed `codesign --verify` calls misleadingly reported inaccessible bundle
  files and invalid signatures. Repeating the checks outside the filesystem
  sandbox made the distinction explicit: both mounted application bundles pass
  `codesign --verify --deep --strict` and satisfy their designated
  requirements. This failure mode must not be converted into a provenance
  rejection by the self-test.
- 2026-09-07: CLI inspection confirmed two different macOS launch boundaries.
  Kitty accepts a child program directly, isolated configuration via
  `--config`, a bounded remote-control socket via `--listen-on`, and a hidden
  startup mode. Ghostty explicitly rejects launching its macOS GUI from its
  executable; the documented CLI directs callers to `open -na Ghostty.app
  --args ...`, while the special `-e` argument supplies the child command.
  Therefore a shared adapter may normalize observations and provenance, but
  product launch/capture must remain product-specific. A real PTY probe will be
  used for query/reply self-tests so executable presence alone cannot be
  reported as black-box capture evidence.
- 2026-09-07: the first formatter pass on the new adapter stopped at an invalid
  attempted pattern-expression spelling around `Uri.tryParse`; the URI is now
  parsed into an explicitly nullable local before validating its HTTPS scheme
  and host. The same command also exposed the restricted environment's known
  inability to update Dart's user telemetry timestamp after formatting the
  independently parseable probe file; subsequent checks use the repository's
  established build environment rather than interpreting telemetry write
  failure as a source failure.
- 2026-09-07: the first genuine Kitty query capture returned the exact expected
  eight-byte DECRQM response, but the live self-test classified the enclosing
  process as crashed because Kitty's macOS default intentionally keeps the app
  process alive after its last window closes; the bounded adapter then killed
  it during cleanup. Rather than accepting a self-inflicted signal as product
  success, the isolated checked-in Kitty configuration now enables the official
  `macos_quit_when_last_window_closed` option. The configuration hash was
  refreshed so a persistent or user-configured process cannot be mistaken for
  the pinned comparator.
- 2026-09-07: Ghostty repeatedly booted as a healthy but childless, windowless
  process when launched through its documented macOS `open -na ... --args -e`
  path, so no probe file appeared. This exactly reproduces upstream discussion
  #13287: command-bearing launches only create the initial surface from
  `applicationDidBecomeActive` and can lose the LaunchServices activation race.
  A direct `NSRunningApplication.activate` call made the window materialize and
  produced the exact eight-byte response. The adapter therefore identifies the
  just-launched PID by its unique probe-result argument and exact executable,
  waits for AppKit launch initialization, and invokes that OS API through a
  minimal checked-in Swift helper. `osascript activate`, `open` reactivation,
  JXA, and a System Events frontmost request either did not deliver the required
  event or waited on Accessibility automation, so they were rejected. The
  isolated config also disables the short-command abnormal-exit hold before
  requiring clean process shutdown.
- 2026-09-07: the implemented adapter catalog pins one profile for each product
  and rejects unknown keys, unsafe paths, non-HTTPS artifacts, missing files,
  unexpected versions, architectures, executable hashes, configuration hashes,
  and capture-support-file hashes. The launchers do not invoke a shell. They use
  private temporary result paths, bounded input/reply/diagnostic sizes and
  deadlines, drain both child pipes, and terminate only the exact process they
  launched. The common observation deliberately marks screen/cursor/mode fields
  as unobserved placeholders for the query-only self-test and asks the
  comparator to evaluate `replies` only; the later corpus must not present
  those placeholders as screen evidence.
- 2026-09-07: official Kitty 0.48.2 passed again through the finished macOS
  direct launcher. With a 4-row by 10-column PTY it returned
  `1b5b3f313b312479` for `DECCKM set; DECRQM DECCKM`, and the adapter exited
  normally after the checked configuration closed the last window. No Kitty
  process remained. The raw capture is checked in unchanged with SHA-256
  `e19afac078faf37132d59156e919faf1bad64251c12aacd6dee78af325fc28ad`.
- 2026-09-07: xterm 411 was built and tested in the dedicated aarch64 Lima guest
  running Debian 13.6 (`gcc` 14.2.0, glibc 2.41, libX11 1.8.12, libXt 1.2.1,
  Xvfb 21.1.16). The exact configure command was
  `/tmp/xterm-411/configure --prefix=/opt/dart-terminal-xterm-411
  --enable-wide-chars --enable-256-color --disable-setuid --disable-setgid
  --with-app-defaults=/opt/dart-terminal-xterm-411/share/X11/app-defaults`,
  followed by `make -j2`. An initial repeat in a different build directory and
  with a different prefix produced different executable hashes because the
  default `-g` build embeds paths; it was rejected rather than changing the
  ledger. Repeating at the original `/tmp/xterm-411` path reproduced executable
  SHA-256 `ee6478dc8355834516557106f7384b4e4f63373fe6019d09a468d25209673426`.
  The Xvfb/PTY self-test then passed with the same eight reply bytes, and its
  regenerated raw file reproduced SHA-256
  `04169e641b696c077296df46650547f1e2161ee43e752827fb1a9200bd67a7ca`.
- 2026-09-07: Ghostty produced a genuine 4-by-10 PTY capture with the same exact
  reply after `NSRunningApplication.activate` delivered its initial-window
  activation on this host. Its checked raw capture has the same SHA-256 as the
  Kitty raw capture. Repeat automation is not available in the current login
  context: `NSWorkspace.frontmostApplication` is `com.apple.loginwindow`, and
  although `activate` can return true, Ghostty does not become active before the
  two-second bound. This matches upstream discussion #13287 rather than a
  terminal crash. The live command now reports that specific activation
  unavailability and kills the exact launched Ghostty PID. The self-test ledger
  therefore records `status=passed` for the genuine capture separately from
  `automation_status=activation-unavailable`; it does not turn the unavailable
  repeat into agreement. No Ghostty process remained after the check.
- 2026-09-07: Swift type-check initially warned that
  `activateIgnoringOtherApps` is deprecated since macOS 14 and has no effect.
  The helper now requests only `activateAllWindows`, waits for the observable
  `isActive` transition, and returns a distinct bounded failure when the login
  context cannot yield activation; the support-file hash was refreshed.
- 2026-09-07: `compatibility/differential_self_tests.json` binds the version 1
  input and expected reply to all three profile IDs, host versions and
  architectures, executable/configuration hashes, immutable raw capture files,
  runner identities, and this decision record. `--check` validates that ledger
  plus every configured support file. Focused validation covers stale config,
  helper and capture hashes, unsafe paths, insecure URLs, malformed versions,
  incomplete capture state, invalid dates, and the two standard SHA-256 test
  vectors. The focused Dart test and the normal adapter target pass.
- 2026-09-07: subtask 2 final verification passed Python bytecode compilation
  for both POSIX tools, warning-free Swift type-check, the focused Dart schema
  tests, `make terminal-differential-adapters-check`, genuine Kitty and xterm
  live self-tests, and `CI=true make test`. The full gate validated generated
  parser/inventory/implementation data, 28 differential contract split runs,
  three pinned profiles and captures, formatting of 154 files, clean static
  analysis, and the complete Dart Terminal test runner. The Ghostty repeat
  ended in the expected bounded `activation-unavailable` state; its earlier
  genuine capture remains validated byte/hash exact and is not counted as a
  successful repeat. Final process inspection found no Ghostty or Kitty child;
  both read-only DMGs were detached, and the dedicated xterm VM was stopped but
  retained for the next ordered corpus subtask.
- 2026-09-07: the staged whitespace check found one surplus blank line in the
  xterm configuration and POSIX probe. Removing them changed both pinned
  support hashes, so the xterm result was not assumed transferable: xterm was
  rebuilt once more at the reproducible path, the updated configuration hash
  `7e5c90b1850b520baaf2f65ecf850c673111cad8c953a7641921b470bc84d411`
  was enforced by the runner, and the live self-test passed. The binary and raw
  result again matched the ledger hashes exactly. The VM was stopped again.
- 2026-09-07: after commit `3458fbd`, ROADMAP was reread and the clean worktree
  confirmed that the reviewed corpus is the next item. It was split before code
  changes into case/baseline/report infrastructure, pinned external capture,
  and mismatch acceptance. This prevents a GUI/X11 dependency from allowing an
  unreviewed or Dart-only fixture to be presented as completed black-box
  evidence. The first child item will cover editing, rendition, mode, and query
  families using inventory-traceable byte streams; external results and their
  acceptance remain explicitly out of scope until the next ordered children.
- 2026-09-07: the reviewed version 1 case manifest now contains four sorted,
  inventory-traceable agreement candidates. Editing exercises CUP/ICH/DCH/ECH;
  rendition preserves bold, underline, direct foreground and indexed background
  before independent reset; mode transitions cover DECCKM, DECOM, DECAWM,
  normal/SGR mouse, and bracketed paste; query combines DSR status/CPR and three
  ordered DECRQM replies. The 146 input bytes are stable for whole input, every
  single split, and bytewise delivery, totaling 154 runs.
- 2026-09-07: the baseline generator records one full common-contract Dart
  observation per case and a deterministic report tied to exact SHA-256 values
  for the case manifest, sequence inventory, implementation manifest, inputs,
  and observation files. The implementation manifest hash is embedded in the
  Dart provenance rather than using an ambiguous working-tree label. The report
  states `external_captures=0` globally and `external_evidence=pending` per case,
  so this child cannot be mistaken for black-box product evidence. The corpus
  check also rejects a missing/stale report, missing/stale observations, extra
  JSON observation files, duplicated/missing required families, chunk-sensitive
  behavior, or a manifest with the wrong scope.
- 2026-09-07: baseline-child verification passed the focused corpus test,
  standalone freshness target, static analysis, and `CI=true make test`. The
  full gate formatted 156 files without changes, revalidated all earlier
  generated compatibility and adapter evidence, ran the 154 reviewed baseline
  splits, and completed the full Dart Terminal test runner.

## Primary product references for adapter execution

- Kitty remote control and protocol:
  <https://sw.kovidgoyal.net/kitty/remote-control/> and
  <https://sw.kovidgoyal.net/kitty/rc_protocol/>
- Kitty launch/configuration options:
  <https://sw.kovidgoyal.net/kitty/launch/> and
  <https://sw.kovidgoyal.net/kitty/conf/>
- xterm manual and official patch archive:
  <https://www.invisible-island.net/xterm/manpage/xterm.html> and
  <https://invisible-island.net/archives/xterm/xterm-411.tgz>
- Ghostty binary installation/configuration and AppleScript boundaries:
  <https://ghostty.org/docs/install/binary>,
  <https://ghostty.org/docs/config/reference>, and
  <https://ghostty.org/docs/features/applescript>
- Ghostty upstream activation-race report used to classify the current-host
  limitation: <https://github.com/ghostty-org/ghostty/discussions/13287>
