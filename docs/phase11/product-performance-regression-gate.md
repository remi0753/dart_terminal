# Phase 11 — Product performance regression gate

## Purpose

Replace Phase 0 feasibility probes with a reproducible Release AOT performance
gate over the actual Dart Terminal parser, damage pipeline, input path, native
product startup, Metal presentation, bounded memory, and non-privileged idle
power proxies. Preserve hard architecture budgets and compare compatible runs
without moving a baseline merely to make a regression pass.

## Background and current position

- ROADMAP, README, FEATURE_MATRIX, the Phase 0 benchmark contract, current
  product parser/damage tools, runtime integration launcher, four-pane 100 MiB
  fairness acceptance, renderer metrics, and existing build targets were
  reread after commit `cffef9f`. Local incident diagnostics is complete; this
  benchmark parent is now the first incomplete Phase 11 item. Soak,
  sanitizer/fuzz, parity gap burn-down, and daily-use work remain later items.
- `benchmark/phase0_benchmark.dart` already defines versioned JSON, percentile,
  hard-gate, compatible-baseline, integrity, and negative-gate semantics, but
  its parser/grid/input workloads are Phase 0 probes rather than product paths.
- `tool/product_parser_benchmark.dart` is a real `VtParser` Release AOT gate at
  100 MiB/s, and `tool/terminal_damage_benchmark.dart` exercises the real
  100,000-cell damage codec and isolate transfer at 4 ms p95. They emit separate
  machine lines and do not yet share a product benchmark schema or compatible
  baseline policy.
- The ordinary hierarchy acceptance already sends exactly 100 MiB through a
  real PTY in one visible pane while measuring a second pane's input-to-visible
  response, requiring no more than 2x its same-launch idle baseline, bounded
  scheduling/frame state, and full cleanup in Developer JIT and Release AOT.
- Current renderer diagnostics expose accepted/rejected/pending frames,
  scheduling, damage, atlas, and resource ownership. They prove no idle or
  occluded frame creation in focused tests, but there is no aggregate startup,
  frame-work, RSS, or CPU-time regression artifact.
- The pinned Ghostty comparator is not installed on this machine and Zig 0.16.0
  is not present. No Ghostty timing is currently claimed. A relative comparator
  result must therefore be an explicit, provenance-bound input; absence cannot
  silently become a pass or weaken the absolute product budgets.

## Scope

- Define one deterministic `dart-terminal-product-benchmark-result` schema with
  exact environment/provenance/workload compatibility, observed samples,
  nearest-rank p50/p95/p99, hard gates, optional accepted-product baseline,
  optional pinned-comparator gate, integrity evidence, and aggregate status.
- Measure the real product parser, damage capture/copy/isolate decode, and real
  key encoder plus bounded PTY-write admission in a Release AOT executable.
- Add an isolated ordinary-product benchmark scenario for launch to first
  accepted Metal frame, injected AppKit key to PTY admission, PTY echo to
  accepted visible frame, frame work, idle/occluded frame suppression, and the
  existing exact 100 MiB cross-pane fairness contract.
- Measure process resident memory and monotonic process CPU-time deltas around
  fixed short idle/occluded and workload windows. Use accepted frames and CPU
  time as reproducible non-privileged power proxies; do not require root,
  `powermetrics`, private Apple APIs, or claim electrical energy measurement.
- Provide one aggregate Make target that builds Release AOT artifacts, validates
  schema/baseline/comparator compatibility, runs negative fixtures, and fails on
  any required hard or relative regression.
- Update benchmark documentation, README, FEATURE_MATRIX, generated evidence,
  and ROADMAP only after the exact main gate and final product gate pass.

## Out of scope

- 24/72-hour soak, 30-day daily use, sleep/wake, display attach/detach, memory
  pressure, sanitizers, fuzz expansion, and application compatibility burn-down.
  They remain ordered later tasks. Long-duration runs are non-blocking by user
  direction.
- Privileged electrical power measurement, changing system power settings,
  disabling security controls, or treating CPU/frame proxies as watts/joules.
- Network installation or unpinned execution of a comparator. Comparator
  evidence must name the exact executable/build provenance and workload.
- Measuring build, code signing, notarization, dependency resolution, first-time
  shader compilation, Save panels, personal data, or background network work.
  Apple notarization is also explicitly skipped by user direction because its
  external turnaround is not suitable for this ordered implementation run.

## Metric and gate contract

All timed samples use monotonic clocks after warmup; correctness and ownership
checks remain outside timing. Hard budgets are the ROADMAP architecture limits:

| Area | Required product metric | Hard/relative gate |
| --- | --- | --- |
| Startup | process launch to first accepted visible Metal frame | bounded fixed p95; compatible baseline and comparator workload required |
| Input | AppKit key to bounded PTY admission | p95 < 2 ms |
| Visible echo | PTY echo observed and accepted by a visible frame | p95 <= one measured refresh interval + 4 ms |
| Parser | real `VtParser`, mixed reviewed corpus | minimum >= 100 MiB/s; comparator throughput >= 0.75x |
| Damage | 100,000-cell capture/copy/transfer/decode | p95 < 4 ms per existing boundary |
| Frame | CPU frame preparation/submission work | p95 < 70% of measured refresh budget |
| Burst isolation | exact 100 MiB in one pane, response in another | flood latency <= 2x same-launch idle baseline; queues/frames bounded |
| Memory | idle and workload RSS with exact resource counts | fixed cap plus compatible-baseline/comparator ratio <= 1.5x |
| Idle power proxy | process CPU time and accepted-frame delta while unchanged | aggregate CPU < 0.5%; no idle/occluded GPU submit |

The startup absolute cap and memory cap will be frozen only after a clean
measurement inventory establishes the current product magnitude. They must be
conservative architecture budgets, not the observed value rounded upward.
Baseline thresholds require repeated same-machine Release AOT evidence and a
documented tolerance. A failing run is investigated; it does not authorize
editing the reference.

## Privacy, safety, and reproducibility

- Results contain metric IDs, units, distributions, fixed environment/build
  provenance, counts, sizes, hashes, and pass/fail classifications only. They
  contain no terminal text, command, cwd, username, absolute path, PID,
  timestamp, machine serial, hardware UUID, environment, or raw error.
- Runtime workloads use generated fixed markers in isolated temporary storage
  and delete it. The launcher records only bounded stdout machine lines and
  rejects malformed, duplicated, missing, or extra fields.
- Memory/CPU sampling is limited to the launched product process tree and uses
  public local APIs. Failure to collect a required sample fails closed.
- Results from different CPU architecture, OS family, Dart SDK, runtime mode,
  product workload/schema, renderer/damage protocol, refresh tier, or comparator
  provenance are incompatible rather than compared.

## Ordered subtasks

1. **Contract, inventory, and baseline/comparator policy**
   - Freeze this memo, metric ownership, privacy boundary, ordered children,
     hard budgets, and unavailable-comparator behavior.
   - Completion: docs and ROADMAP agree and `git diff --check` passes in a
     documentation-only commit.
2. **Release AOT product microbenchmarks**
   - Unify the real parser, damage/transfer, and key-to-write-admission paths
     under the versioned result codec, compatible product baseline, hostile
     baseline tests, negative threshold test, and Make target.
   - Completion: product integrity fixtures and repeated M1 Release AOT hard and
     accepted-product baseline runs pass.
3. **Ordinary-product latency and frame acceptance**
   - Measure startup, key admission, visible echo, frame work, refresh tier,
     idle/occluded frame suppression, and reuse the exact 100 MiB fairness gate.
   - Completion: isolated launcher validation and final Developer JIT/Release
     AOT product ownership teardown pass; Release AOT supplies gate values.
4. **Memory, idle-power proxy, and pinned relative comparison**
   - Add short fixed-window RSS/CPU/frame measurements, freeze conservative
     caps, and implement fail-closed accepted-product/comparator comparison.
   - Completion: memory and CPU/frame proxy gates pass without privileged APIs;
     compatible pinned comparator evidence passes every required relative gate.
5. **Aggregate gate and parent closure**
   - Run repeated release measurements, aggregate target, negative checks,
     exact main gate, docs/reference/matrix/generated evidence, and worktree
     audits.
   - Completion: all children and parent are checked and committed before soak
     work begins.

Subtasks are strictly ordered. Later Phase 11 items cannot start until all five
children and this parent are complete.

## Progress log

### 2026-09-13 — Contract and inventory

- Recorded the current product and Phase 0 measurement authorities and retained
  the ROADMAP's absolute budgets without treating old probe values as current
  product evidence.
- Chose short process CPU-time plus accepted-frame deltas as a portable power
  regression proxy. This is sufficient to enforce idle work suppression but is
  explicitly not an electrical-energy claim.
- Kept missing Ghostty/Zig timing evidence fail-closed and separated from the
  accepted-product baseline. Product implementation and absolute measurements
  can proceed, but the relative-comparison child cannot complete without exact
  compatible comparator evidence.

### 2026-09-13 — Release AOT product microbenchmarks

- Added `tool/product_performance_benchmark.dart` as the version-1
  `product-micro` result authority. It calls the real `VtParser`, the existing
  100,000-cell `TerminalDamageCodec` capture/copy/isolate-decode path, and
  `TerminalKeyEventRouter` through `TerminalPane.sendInput` into a bounded
  write-admission fixture. The earlier standalone damage command now delegates
  to a reusable result object without changing its machine-line contract.
- Result JSON contains fixed environment/workload provenance, distributions,
  gates, and content-free integrity counts only. It retains no raw samples,
  terminal bytes/text, command, path, PID, timestamp, serial number, or hardware
  UUID. Baselines are capped at 64 KiB and reject extra schema keys, invalid
  numbers/tolerances, missing/extra metrics, or exact environment/provenance
  incompatibility.
- Six clean Release AOT runs on `MacBookPro17,1`, macOS arm64, 16 GiB, Dart
  3.13.2 all passed the hard gates. Across runs, parser minimum was
  108.94–110.44 MiB/s; damage capture p95 was 454–467 us; transfer/decode/ACK
  p95 was 1,337–1,369 us; end-to-end p95 was 1,768–1,840 us; and key-to-write
  p95 was 375–417 ns. The checked reference uses representative run-level
  medians with explicit noise margins: parser p50 110.28 MiB/s (-8%); capture
  p95 456 us (+25% + 100 us); transfer p95 1,351 us (+20% + 100 us);
  end-to-end p95 1,815 us (+20% + 200 us); and input p95 375 ns (+50% +
  250 ns). These relative gates do not replace the fixed hard budgets.
- The first sandboxed executable attempt failed before result emission because
  macOS denied read-only `sysctl` access. Re-running outside that sandbox
  supplied only hardware model and physical-memory class and passed. This is an
  execution-environment restriction, not a product benchmark failure.
- The checked-baseline Make run passed with parser p50 109.79 MiB/s, damage
  capture/transfer/end-to-end p95 467/1,354/1,809 us, and input p95 375 ns.
  Integrity remained exact: 134,264,777 parsed bytes per sample, 1,704,904
  damage bytes per iteration, 100,000 accepted key events/writes, 119-byte peak
  in the 65,536-byte bounded queue, and zero rejection.
- Final validation passed:
  - `dart format --output=none --set-exit-if-changed bin lib test tool`
  - `dart analyze` with no issues
  - `dart run test/product_performance_benchmark_test.dart`, covering exact
    result encoding, accepted and impossible baselines, unknown/oversized input,
    invalid tolerance, environment/metric mismatch, and short real workloads
  - `make product-parser-benchmark product-damage-benchmark`, preserving both
    standalone Release AOT gates
  - `make product-performance-benchmark`; the final accepted run observed
    parser p50 109.97 MiB/s, damage capture/transfer/end-to-end p95
    507/1,358/1,849 us, and input p95 375 ns
  - exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  - `git diff --check`; adjacent `dart_appkit` remained clean and its tracked
    Dart/native source and filenames contain no case-insensitive `terminal`

### 2026-09-13 — Ordinary-product latency/frame acceptance start

- Goal: add an integration-test-only scenario to the same
  `_runInteractiveHierarchyProduct` path used by an ordinary zero-config
  launch. Measure process launch to the first accepted visible Metal frame,
  native `NSTextInputClient` raw-key delivery to bounded PTY write admission,
  that PTY response through parser/damage to a later accepted visible frame,
  and CPU frame composition/submission work. Verify unchanged-visible and
  occluded output do not create frames.
- Reuse, rather than duplicate, the existing native-hierarchy exact 100 MiB
  fairness acceptance. Its real four-pane PTY run already proves response
  during flood, <=2x same-launch idle latency, scheduler yielding, one pending
  frame per pane, and clean four-session/native teardown.
- Scope is `dart_terminal`, its product-owned renderer capability, the runtime
  integration driver, focused tests, Make targets, and this memo. The generic
  adjacent `dart_appkit` repository remains out of scope and must stay clean;
  no terminal-named or terminal-specific code will be added there.
- Completion requires strict option/environment gating and mutual exclusion,
  bounded content-free machine lines, negative parser/threshold tests, clean
  Developer JIT and Release AOT ordinary-product teardown, the exact fairness
  reuse in both modes, and final format/analyze/main tests. Startup and frame
  budgets will be frozen from clean observed magnitudes; Release AOT is the
  release gate authority while Developer JIT remains an ownership check.
- The first Developer JIT attempt reached its first visible frame and cleanly
  released the one ordinary pane, but the input probe timed out. Investigation
  showed that the PTY's `writeEnqueued` diagnostic is intentionally emitted
  only for tracked paste/EOF writes, while ordinary key input correctly uses
  the untracked bounded `process.write` path. The probe now completes at the
  synchronous return of the real key router/PTY write and also requires the
  exact three-byte encoded route. This retains the intended key-to-admission
  boundary without changing product input semantics merely for measurement.
- The second Developer JIT attempt reached bounded PTY admission but the shell
  fixture rejected the bytes as non-exact. The live zsh line editor can
  legitimately select either application-cursor `ESC O A` or normal-cursor
  `ESC [ A`, so the fixture accepts exactly those two three-byte encodings.
  Repeating the run exposed the actual false failure: ready, visible, and
  mismatch markers appeared literally in the shell's echoed command line, so
  the screen searches could settle before command execution. Marker output now
  uses `%s` placeholders; none of the completed marker strings occurs in the
  submitted command. The measured route still requires one exact three-byte
  admitted key and accepts no arbitrary bytes.
- After the Developer ownership run passed, the first Release AOT gate failed
  only the visible-response budget. The reused correctness helper deliberately
  requested and waited for an additional full redraw after finding a marker,
  so the timer included two presentations rather than the required response
  presentation. The performance probe now snapshots accepted frames before
  input and succeeds only when the marker exists and an accepted frame has
  advanced after that snapshot. It neither requests nor counts an artificial
  second frame.
- The Release latency/frame process then passed its hard gates, but its reused
  100 MiB hierarchy process twice exceeded the old 90-second flood-completion
  wait (once through the combined target and once through the hierarchy target
  alone). Both runs had already completed the timed sibling-pane response and
  remained live; only total producer completion was pending. Because total
  flood duration is not a performance threshold, the fixed 100 MiB workload,
  `<=2x` response ratio, queue/frame bounds, and cleanup checks remain exact;
  only the completion/launcher safety deadlines are raised to 180/240 seconds.
- A subsequent Release sample quantified startup/input/refresh/frame work at
  0.56 s, 1.510 ms p95, 16.668 ms, and 0.773 ms p95 respectively, while idle
  and occluded build/submit deltas stayed zero. Visible response was still two
  refreshes (32.964 ms): the untimed ready marker was found in the screen model
  before its frame had settled, leaving that ready frame in flight when the
  timed key began. The probe now waits for the ready marker's accepted frame
  before taking the input baseline; the measured interval therefore begins
  from an idle, visible surface and cannot count pre-existing work.
- The corrected Release AOT run passed every hard gate: launch to first
  accepted frame 723.428 ms, measured refresh 16.610 ms, native key through
  bounded PTY admission 1.842 ms p95, input-to-visible accepted response
  12.065 ms p95 (20.610 ms budget), and CPU frame build/submit 0.775 ms p95
  (11.627 ms budget). Visible idle and occluded-output build/frame deltas were
  all zero, pending frames stayed bounded, unocclusion resumed presentation,
  and the one-session product process released all owners.
- Its separately launched exact 100 MiB/four-pane acceptance also passed:
  23.974 ms same-launch baseline, 28.165 ms response during flood, ratio 1.175,
  326 scheduler yields, bounded frames, four clean sessions, and 69.649 s total
  hierarchy runtime.

### 2026-09-13 — Ordinary-product latency/frame acceptance completion

- The launcher freezes a conservative 5-second per-launch startup cap for
  Release AOT. Current clean Release samples are below 0.75 seconds, leaving
  broad cold-start variance without turning the observed value into the gate.
  The aggregate child will form the repeated p95; this child fails every
  individual Release sample above the cap. Developer JIT validates the same
  schema, exact routes, suppression, fairness, and ownership but does not act
  as a release latency authority.
- `RuntimeProductPerformanceResult` rejects missing, duplicated, malformed, or
  extra result fields and independently recomputes visible/frame budgets. Its
  negative fixtures fail startup above 5 seconds, input at the strict 2 ms
  boundary, visible response beyond one measured refresh plus 4 ms, and frame
  work at the strict 70% boundary.
- The final `make runtime-product-performance-integration` passed both modes.
  The final Developer run observed startup 1.240896 s, refresh 16.932 ms, input
  11.202 ms p95, visible response 24.724 ms p95, and frame work 1.039 ms p95;
  its exact fairness run was 27.304/30.563 ms (ratio 1.120) with 2,131 yields
  and four clean sessions. The final Release run observed startup 736.103 ms,
  refresh 16.656 ms, input 1.484 ms p95, visible response 12.431 ms p95, and
  frame work 0.771 ms p95; its exact fairness run was 24.978/27.734 ms (ratio
  1.111) with 1,381 yields and four clean sessions. Both ordinary one-pane
  runs had zero idle/occluded frames and complete native-owner teardown.
- Final verification passed:
  - `make terminal-renderer-native-test terminal-renderer-dart-test`
  - `dart run test/product_performance_benchmark_test.dart`, including strict
    runtime-result negative thresholds and Developer-only structural parsing
  - `make runtime-product-performance-integration`
  - exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  - `git diff --check`
  - adjacent `dart_appkit` clean status, no case-insensitive `terminal` in its
    Dart/native source or filenames, and
    `dart run tool/generic_repository_audit.dart --check` with 140 paths and
    139 text files
- The first exact main-gate attempt correctly rejected stale Phase 7 evidence
  after `terminal_application.dart` changed. Regeneration changed only its two
  deterministic source hashes; the second exact main-gate run passed. Apple
  notarization and long-duration endurance work were not run by user direction
  and are not completion dependencies for this child.

### 2026-09-13 — Memory and idle-power proxy start

- Goal: extend the isolated ordinary-product scenario with fixed short-window
  resident-memory, monotonic process CPU-time, and accepted-frame samples. The
  Release AOT run is the absolute performance authority; Developer JIT checks
  the same schema, public-API sampling, lifecycle, and fail-closed ownership.
- Scope: the `dart_terminal` product process, its existing one-pane visible and
  occluded scenario, a bounded content-free result line, strict launcher codec,
  focused negative tests, and Make acceptance. No source or API is added to the
  adjacent generic `dart_appkit` repository.
- Out of scope: watts/joules, privileged `powermetrics`, private Apple APIs,
  changing system settings, long-duration endurance work, signing, and Apple
  notarization. Long-duration work and notarization are explicitly non-blocking
  by user direction.
- Dependencies and risks: the metric must sample only the current launched
  product, use monotonic CPU time, distinguish idle and occluded fixed windows,
  retain no PID/path/environment/raw terminal data, and avoid counting setup or
  teardown. Cursor animation or in-flight presentation would invalidate an
  unchanged-window sample, so each window begins only after the existing
  visible-frame settling checks and also requires zero accepted-frame delta.
- Completion: strict positive and boundary-negative codec tests pass; Release
  AOT remains below a conservative fixed RSS cap, uses less than 0.5% aggregate
  process CPU in unchanged visible and occluded windows, submits no frame in
  either window, and releases every ordinary product owner. The exact main gate
  and adjacent generic-library audit must pass before this child is checked.
- The combined memory/comparator child was split before implementation because
  they have independent evidence and completion conditions. Short-window
  absolute gates run first. Compatible pinned comparator evidence and relative
  gates remain strictly next and cannot be marked complete merely because the
  executable is absent.
- Inventory confirmed no `ghostty` or `zig` command and no
  `/Applications/Ghostty.app` executable on this host. The repository contains
  only the accepted-product micro baseline and differential fixtures, not a
  compatible pinned performance result. This matches the earlier contract and
  is not yet recorded as a blocker for the preceding absolute-gate subtask.
- The adjacent `dart_appkit` worktree is clean. Its first official audit attempt
  was prevented before execution when the sandbox denied Dart analytics-session
  metadata access; the audit will be rerun with analytics suppressed during
  final verification. This is an execution-environment issue, not a repository
  audit failure.
- Added a product-owned sampler using the public POSIX `getrusage(RUSAGE_SELF)`
  CPU clock and Dart `ProcessInfo.currentRss`/`maxRss`. It retains only integer
  CPU microseconds and resident bytes; allocation, unavailable data, regressed
  CPU time, or malformed `timeval` values fail closed. No process identifier or
  terminal data enters the result.
- The ordinary-product probe first selects a steady non-blinking cursor, then
  measures separate two-second visible and occluded unchanged windows. It also
  emits 11,024 fixed two-byte lines (22,048 bytes) to fill bounded scrollback,
  records exact page/line/allocation counts and root-process RSS, and resumes an
  accepted frame after occlusion. Release AOT gates aggregate CPU strictly below
  0.5%, zero accepted frames in both unchanged windows, and idle/workload/peak
  RSS below a conservative 512 MiB cap.
- The first Developer JIT product run exposed that scrollback evicts a complete
  256-row page when its 10,000-line limit is crossed. The correct bounded full
  state is therefore 9,745–10,000 retained lines with a mathematically matching
  page count, not exactly 10,000 lines/40 pages. The observed 9,769 lines,
  39 pages, and 21,275,904 allocated bytes were within both line and 64 MiB byte
  caps. CPU sampling was also moved before the workload so pending parser/damage
  work cannot contaminate an unchanged occluded window.
- The first corrected Release AOT measurement passed memory and frame
  suppression (127.0 MiB peak and zero accepted-frame deltas) but truthfully
  failed the CPU gate at 1.75%. Read-only tracing found two product automation
  timers polling native App Intents and AppleScript queues every 16 ms. Empty
  App Intents polls also toggled transient status and refreshed diagnostics on
  every tick. Empty polls now avoid that UI/status work, and both product queue
  intervals are fixed at 250 ms, still far inside their 30-second command
  timeout while bounding idle wakeups to four per second per integration.
- After this correction, a clean direct Release AOT run passed with 109.2 MiB
  idle RSS, 124.0 MiB workload RSS, 127.0 MiB peak RSS, 0.16% visible-idle CPU,
  0.18% occluded CPU, 0.17% aggregate CPU, zero accepted frames in both windows,
  exact bounded scrollback resources, and a successful resume frame. The same
  strict machine result recomputes every ratio/claim and rejects missing,
  duplicate, extra, inconsistent, over-cap, or 0.5%-boundary fixtures.

### 2026-09-13 — Memory and idle-power proxy absolute-gate completion

- The final combined runtime performance suite passed in both modes. Developer
  JIT retained 144.1/174.8/177.4 MiB idle/workload/peak RSS and 0.45%/0.40%/
  0.42% visible/occluded/aggregate CPU. Release AOT retained 109.4/129.2/
  131.7 MiB and 0.19%/0.11%/0.15% respectively. Both modes held accepted-frame
  deltas at zero in both fixed windows, resumed exactly through the ordinary
  presentation path, retained 9,769 scrollback rows in 39 bounded pages, and
  released every session, Metal surface, text client, worker, and native owner.
- The exact 100 MiB sibling-pane fairness reuse also passed: Developer JIT was
  28.187/30.020 ms (ratio 1.066, 922 scheduler yields, 75.065 s total) and
  Release AOT was 25.766/26.151 ms (ratio 1.015, 1,784 yields, 151.839 s total).
  Total transfer duration remains only a safety deadline, not a weakened
  performance threshold.
- Functional regression validation for the reduced polling wakeups passed
  separately: AppleScript completed all ten commands in Developer JIT and
  Release AOT, while App Intents retained three actions/three shortcuts and
  exact shared-action delivery in both modes. Unit coverage fixes the 250 ms
  interval and proves an empty App Intents poll emits no transient UI status.
- Final validation passed:
  - `dart analyze`
  - `dart run test/product_performance_benchmark_test.dart`
  - `dart run test/terminal_system_automation_product_test.dart`
  - `make runtime-applescript-integration runtime-system-automation-integration`
  - `make runtime-product-performance-integration`
  - exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  - `git diff --check`
  - adjacent `dart_appkit` clean status and its official
    `dart run tool/generic_repository_audit.dart --check` result of 140 paths and
    139 text files
- The first exact main-gate run correctly rejected stale Phase 7 evidence.
  Regeneration changed only the two reviewed `terminal_application.dart`
  SHA-256 entries, and the repeated exact gate passed. One generic audit command
  was also initially invoked with the product directory as its working
  directory and therefore correctly reported the product's terminal-specific
  files; rerunning from `dart_appkit` passed. Neither failed attempt changed the
  generic repository.
- Apple notarization and long-duration endurance work were not run by explicit
  user direction and are not dependencies of this completed absolute-gate
  subtask. The compatible pinned comparator evidence subtask remains next.

### 2026-09-13 — Pinned comparator codec start

- Goal: define a strict, bounded, content-free codec for an independently
  captured Ghostty comparator result and a deterministic relative evaluator for
  the ROADMAP parity rules. This child establishes fail-closed logic only; it
  does not claim that a real comparator was run.
- Scope: exact Ghostty revision/Zig/build/config/no-patch/executable-hash
  provenance; same Mac/architecture/memory/refresh tier and fixed workload
  compatibility; input-to-visible p95, parser/output throughput, idle root RSS,
  and idle process CPU observations; typed relative outcomes; hostile and
  boundary fixtures; and this memo/ROADMAP.
- Out of scope: downloading or installing an unpinned executable, modifying or
  linking Ghostty, fabricating measurements, and treating a synthetic unit
  fixture as release evidence. The next ordered child alone owns a real pinned
  build/capture and checked passing result.
- Dependencies and risk: product and comparator measurements must use the same
  hardware, OS family, architecture, memory class, refresh tier, shell/config,
  generated input/output corpus, animation-disabled idle policy, and sampling
  windows. Any missing/extra key, invalid number, oversized source, provenance
  drift, or compatibility mismatch must fail before comparison.
- Relative rules are the ROADMAP authority: input-to-visible p95 must be no more
  than the larger of comparator +4 ms or comparator ×1.25; parser/output
  throughput must be at least 0.75× comparator; refresh tier must match; and
  idle root RSS and process CPU must each be no more than 1.5× comparator.
- Completion: exact round-trip and every threshold boundary have positive and
  negative tests; provenance/workload/environment mismatch and unknown schema
  fail closed; formatting, analysis, focused tests, exact main gate, and the
  adjacent generic-library audit pass; then only this codec child is checked.
- Local inventory found no `ghostty`/`zig` command, Ghostty app, Homebrew Cask,
  cached archive, Downloads artifact, compatible benchmark result, or alternate
  repository branch containing one. Therefore the subsequent real-capture child
  currently has an external-artifact blocker, but that does not prevent this
  evaluator child from being completed first.

### 2026-09-13 — Pinned comparator codec result

- Implemented `tool/product_performance_comparator.dart`. Its decoder accepts no
  more than 64 KiB and requires an exact schema for the macOS arm64 environment,
  fixed workload, metrics, and unpatched Ghostty provenance. The authority is
  revision `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`, Zig `0.16.0`, command
  `zig build -Doptimize=ReleaseFast`, and configuration `ReleaseLocal`; exact
  executable and harness SHA-256 values remain capture inputs rather than
  hard-coded synthetic claims.
- The evaluator first requires exact environment and workload equality, including
  the 60/120 Hz refresh tier. It then applies all four relative gates: input p95
  at `max(comparator + 4 ms, comparator × 1.25)`, parser/output throughput at
  `>= 0.75×`, and idle root RSS and process CPU at `<= 1.5×`. Its bounded result
  contains only provenance, aggregate metrics, thresholds, and decisions; raw
  samples and command-line/user content are not retained.
- Added `test/product_performance_comparator_test.dart` to the main test runner.
  Tests cover both input-threshold branches, every exact passing boundary and
  first failing value, strict key inventory, revision/patch/workload drift,
  invalid metrics, oversized evidence, and refresh/workload incompatibility.
- Considered allowing a partially compatible environment or a locally patched
  comparator, but rejected both: either would make a relative result
  irreproducible and permit an invalid parity claim. Synthetic fixtures are used
  only to prove codec/evaluator behavior and are never accepted as release
  evidence.

Validation on 2026-09-13:

- `dart analyze`: passed with no issues.
- `dart run test/product_performance_comparator_test.dart`: passed.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed (exit 0), including
  dependency capability checks, generated/reference audits, formatting of 315
  files with zero changes, analysis, and the complete product test runner.
- In adjacent `../dart_appkit`,
  `DART_SUPPRESS_ANALYTICS=true dart run tool/generic_repository_audit.dart --check`:
  `GENERIC_REPOSITORY_AUDIT_PASS paths=140 text_files=139`; its worktree was
  clean. No terminal-named or terminal-specific code was added there.
- Apple notarization and long-duration verification were not run by explicit
  user direction and are not dependencies of this codec child.

The codec child is complete. The next ordered child, a real pinned Ghostty build,
capture, and passing relative result, is blocked in the current environment:
neither the exact source/build artifact nor Zig `0.16.0` is locally available.
Substituting another revision, downloading an unverified binary, or manufacturing
measurements would violate the recorded comparator policy. A verified source at
the pinned revision plus the exact Zig toolchain (or a provenance-complete,
workload-compatible capture from this Mac) is required before that child can be
completed; aggregate-gate closure must not proceed first.
