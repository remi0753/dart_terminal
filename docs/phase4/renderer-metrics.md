# Phase 4 — Renderer metrics

- Status: complete
- Date: 2026-09-06
- Scope: final Phase 4 roadmap item
- Related: ADR-002, ADR-003, ADR-004, REN-03, REN-04, REN-05, REN-06, REN-09

## Purpose

Expose bounded, deterministic renderer observations for frame timing, glyph
atlas hit rate, and native atlas upload bytes. The metrics must diagnose the
newest-frame/atlas pipeline without changing scheduling decisions, retaining
per-frame objects, using wall-clock time, or making cell-level FFI calls.

## Background

The frame scheduler already owns cumulative accepted/stale/backpressure/build
counters. The Dart glyph atlas already counts lookups that hit or miss. The
Metal atlas bridge copies every reset/incremental upload but currently records
only queue depth and native resource generation. These facts are exposed
separately and do not yet form one immutable snapshot suitable for runtime
diagnostics or tests.

## Scope

- Measure synchronous frame build and native submission durations with an
  injected monotonic microsecond source, and successful native GPU command
  duration from Metal command-buffer timestamps.
- Publish bounded cumulative frame counts/timing totals and maxima without
  retaining timing samples or changing newest-only scheduling.
- Snapshot atlas lookup hits/misses and derive a zero-safe hit rate from integer
  counters.
- Count accepted full/incremental native atlas upload bytes, excluding work
  rejected by backpressure or stale generation.
- Combine the three ownership domains into one immutable product snapshot and
  exercise it through focused tests and Developer JIT/Release AOT integration.

## Out of scope

- Histograms, percentiles, telemetry export, logging cadence, user-facing UI,
  remote collection, signposts, display-link cadence, or multi-pane fairness
  policy.
- Resetting production counters, changing frame admission/pacing decisions, or
  counting bytes merely queued/copied on the Dart side as native uploads.

## Dependencies and boundaries

- Scheduler timing uses a synchronous monotonic source owned by the render
  coordinator. Tests inject exact values; production uses `Stopwatch` monotonic
  elapsed microseconds.
- Atlas hit/miss ownership remains in `TerminalGlyphAtlas`; metrics only read a
  copied snapshot.
- Upload bytes are credited by the native renderer only when an atlas upload is
  accepted. Full renderer attachment/recovery therefore counts the exact live
  page snapshot payloads; incremental updates count their accepted dirty
  rectangle payloads. Reset texture clears do not masquerade as Dart upload
  traffic.
- All counters and accumulated microseconds saturate at signed 64-bit maximum.
  Maximum duration fields are monotonic, and no sample list is retained.

## Initial completion criteria

- Exact fake-clock tests distinguish build and submit duration, totals, maxima,
  attempts, and accepted/stale/backpressured outcomes without extra frames.
- Atlas snapshots report hit/miss counts and a defined hit rate for both zero and
  nonzero lookup totals.
- Full and incremental upload byte/count metrics advance exactly once after
  native acceptance and remain unchanged for rejected work.
- One aggregate snapshot proves internally consistent scheduler, atlas, bridge,
  and renderer generations after the real app smoke.
- Full format/analyze/tests, source audit, both bundle audits, and Developer
  JIT/Release AOT AppKit/Metal smoke pass.

## Verification plan

- Focused scheduler fake-time, glyph-atlas, Metal-pipeline, and aggregate metrics
  tests.
- `make test`, `make runtime-source-check`, `make runtime-bundle-audit`, and
  `make runtime-integration`.
- Review product, adjacent `dart_appkit`, and official SDK worktrees before the
  completion commit.

## Ordered subtasks

1. **Native GPU completion timing and accepted atlas upload counters**
   - Extend the versioned native renderer state with saturating successful GPU
     sample count/total/maximum nanoseconds and accepted atlas upload
     count/bytes.
   - Decode and validate the fields through the adjacent Dart facade and cover
     real command completion, full/incremental uploads, failure behavior, ABI
     layout, and malformed state.
2. **Dart frame timing, atlas hit rate, and aggregate metrics snapshot**
   - Add injected monotonic build/submit timings and immutable atlas hit-rate
     snapshots with saturating counters.
   - Join scheduler, atlas/bridge, and native renderer values into one strict
     snapshot and verify Developer JIT/Release AOT product observations.

The aggregate child depends on the versioned native counters. Both children
must be committed before the parent metrics item and Phase 4 can complete.

## Investigation log

- 2026-09-06: after commit `63e0956`, reread the Phase 4 roadmap. All preceding
  Phase 4 items are complete and both product and adjacent worktrees are clean;
  renderer metrics is the first unchecked item and completing it will close the
  phase.
- 2026-09-06: Phase 0 evidence reports CPU encode/copy and GPU duration, while
  ADR-004 explicitly assigns GPU status and duration recording to native command
  completion. Measuring only Dart build/submit would therefore leave the frame
  timing contract incomplete. The task was split before code changes into a
  versioned native metrics child followed by a product aggregation child.
- 2026-09-06: the current native state has successful completion and atlas
  generation counters but no durations or upload traffic. `MTLCommandBuffer`
  completion already runs under the renderer's narrow state lock and exposes
  GPU start/end timestamps, making that boundary the authoritative place to
  accumulate successful GPU timing without another callback or FFI call per
  frame.
- 2026-09-06: implemented adjacent renderer ABI 9/state version 3. Successful
  command completion records a Metal GPU timestamp duration in nanoseconds;
  missing/invalid timestamps do not create samples. Accepted upload calls
  record exact payload count/bytes after texture replacement. Backpressure,
  stale/invalid uploads, resets, drawable misses, and command failures do not
  advance the corresponding success metrics. All new totals and related
  existing runtime counters saturate at signed 64-bit maximum.
- 2026-09-06: adjacent focused native and Dart tests pass, including the
  176-byte C11/C++20/Dart FFI state layout, two initial uploads totaling 20
  bytes, rejected upload invariance, a third accepted upload totaling 24 bytes,
  one positive GPU sample with consistent total/maximum, and zero successful
  samples on command encoding/completion faults. The complete adjacent
  `make test` passes. Adjacent commit: `e56554d Expose bounded Metal renderer
  metrics`.
- 2026-09-06: adopted renderer ABI 9 in the product manifest and public feature
  documentation. Product `make test` passes with 98 formatted files and no
  analyzer issues; `make runtime-source-check` passes with
  `tracked=181 native_sources=0`. Developer JIT and Release AOT bundle audits
  pass with one helper, one native-asset set, and one capability. Their real
  AppKit/Metal smokes pass in 2,240 ms and 1,785 ms using state version 3.

## Verification results

### Native GPU completion timing and accepted atlas upload counters

- Renderer ABI 9/state version 3 is exactly 176 bytes across C11, C++20, and
  Dart FFI, with strict version/reserved/invariant validation.
- Successful GPU completion publishes a positive duration sample and consistent
  cumulative/maximum nanoseconds. Encoding and completion failures publish no
  successful GPU timing sample.
- Accepted full/incremental atlas payloads alone advance count/bytes. Invalid,
  stale, and backpressured uploads plus reset clears do not.
- Related native counters and all new metric totals saturate at signed 64-bit
  maximum and retain constant memory.
- Adjacent and product full tests, source/bundle audits, and both product runtime
  modes pass. This first child is complete; Dart timing/hit-rate aggregation is
  next.

## Product aggregation design

- `TerminalNewestFrameScheduler` will accept an optional synchronous metric
  clock. The default is one process-monotonic `Stopwatch`; exact tests inject a
  sequence. Only actual build and submit callback boundaries read it. Idle,
  paused, coalesced damage, and pre-submit supersession cannot manufacture
  timing samples.
- Build and submit callback attempts each contribute one duration even when the
  callback throws, because the owner did spend that synchronous time. Existing
  outcome counts remain separate. Counts/totals saturate, maxima never regress,
  and an immutable scheduler snapshot retains no frame or sample list.
- Atlas hit rate remains strictly lookup-based: ingesting a new or duplicate
  raster is not relabeled as a lookup. An immutable atlas metrics snapshot
  carries hit/miss counts and computes `0.0` for no lookups.
- The aggregate snapshot copies scheduler, atlas, bridge, and native state once
  and rejects an abandoned/unsynchronized bridge or mismatched renderer/atlas
  generation. It exposes current native GPU and accepted upload totals without
  adding a new FFI call or mutating retirement/pin state.

## Product implementation findings

- `TerminalNewestFrameScheduler` now measures each actual synchronous build and
  submission callback attempt. The snapshot contains saturating count/total/max
  values and existing accepted/stale/backpressure/superseded outcomes; idle and
  paused polling do not read the metric clock or create a sample.
- Both build and submission timing are recorded in `finally`, so a callback
  failure remains observable while the newest pending marker is preserved.
  A regressing, negative, or signed-64-bit-overflowing injected clock is rejected
  instead of publishing an invalid duration.
- `TerminalGlyphAtlasMetrics` copies saturating lookup hit/miss counts. Its
  derived lookup total saturates, while hit rate divides normalized `double`
  operands so two saturated counters still produce `0.5` rather than overflowing
  an integer sum. No-lookups and no-hits both produce `0.0`.
- `TerminalRendererMetricsSnapshot.capture` accepts only a live, synchronized
  atlas bridge with no pending Dart or bridge uploads and matching native
  renderer/atlas generations. It then copies scheduler, atlas, bridge ownership,
  and the versioned native state into one immutable observation.
- The real AppKit/Metal exercise deliberately performs one atlas hit and miss,
  then validates four build/submission samples, three accepted and one stale
  frame, the recovered renderer generation, one 4,096-byte full atlas upload,
  and zero pending uploads.
- The first format attempt exposed that the timing-clock typedef had been placed
  inside a factory declaration. Moving it to library scope fixed the parse
  failure; formatting and analysis then completed without changes or findings.

## Final verification results

- Focused `frame_scheduler_test.dart`, `glyph_atlas_test.dart`,
  `renderer_metrics_test.dart`, and `metal_pipeline_test.dart` all pass. Exact
  fake-clock cases cover accepted, stale, backpressured, build-failure, and
  submit-failure attempts plus idle no-sample behavior; aggregate tests cover
  immutable copies and abandoned-bridge rejection.
- Product `make test` passes: 100 Dart files format cleanly, analysis reports no
  issues, and the complete test runner succeeds.
- `make runtime-source-check` passes with `tracked=182 native_sources=0`.
  Developer JIT and Release AOT bundle audits each report one helper, one native
  asset set, and one capability.
- Developer JIT and Release AOT real AppKit/Metal integration both report the
  expected aggregate metrics and pass in 2,211 ms and 1,774 ms respectively.
- `git diff --check` passes. The adjacent `dart_appkit` and official SDK trees
  remain clean after their already committed native metrics work.
- Every Phase 4 roadmap deliverable is now implemented. The existing golden,
  fixed-slot/newest-only, rebuild, animation pause, recovery, and metrics tests
  collectively preserve the Phase exit contracts: deterministic 1x/2x output,
  refresh-rate-independent state, bounded pending work, stale-frame rejection,
  resize recovery, and no idle/occluded frame creation. Multi-pane fairness and
  quantitative vsync benchmarking remain explicitly assigned to a later phase.
