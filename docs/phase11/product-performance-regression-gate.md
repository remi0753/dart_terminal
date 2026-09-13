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
