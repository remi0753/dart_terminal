# Benchmark contract

Phase 0 benchmarks are compiled and run in release AOT mode. The executable
writes one `dart-terminal-benchmark-result` version-1 JSON document to stdout
and a one-line human status to stderr.

Every distribution metric records its unit, better direction, sample count,
minimum, p50, p95, p99, maximum, hard gate, optional baseline gate, and final
pass/fail value. Correctness hashes/counts and bounded-queue sizes live under
`integrity`; they are never treated as latency samples.

Run the checked baseline with:

```sh
make phase0-benchmark-run
```

The baseline ID names the physical reference machine. Automatic comparison
checks OS family, ABI, Dart SDK, AOT build mode, parser corpus, benchmark
workload, packed-damage version, input-probe version, measurement-policy
version, and pinned Ghostty comparison-build metadata. The Ghostty comparator
is commit `d4d8f622...`, Zig 0.16.0, command
`zig build -Doptimize=ReleaseFast`, macOS configuration `ReleaseLocal`, and no
project-local patches. Ghostty is not linked into or used to implement this
project. The operator/CI configuration is responsible for selecting the
matching host label; the exact OS build is recorded for diagnosis but may
receive compatible point updates. A new baseline requires repeated clean
release-AOT runs, an explanation in the related feasibility report, and review
of both hard gates and regression tolerances. Do not update a baseline merely
to make a regression pass.

## Phase 11 product microbenchmarks

Run the real product parser, damage transport, and key-to-bounded-write path
against the checked M1 baseline with:

```sh
make product-performance-benchmark
```

The pinned Ghostty relative evidence is checked without launching an external
application:

```sh
make product-performance-comparator-check
```

Run the complete Release AOT regression gate with:

```sh
make product-performance-regression-gate
```

This target builds the product microbenchmark and ordinary Release AOT app,
runs the strict negative comparator/aggregate fixtures, captures fresh
microbenchmark and runtime results under ignored `build/benchmarks/` storage,
and binds their SHA-256 values to the checked pinned comparator. It fails if a
product hard gate, accepted-product baseline, startup/input/visible/frame/
memory/CPU gate, exact 100 MiB cross-pane fairness gate, compatibility check,
or any of the four relative gates fails. The resulting aggregate document is
content-free; the reviewed M1 acceptance artifact is
[`evidence/product-performance-regression-macos-arm64-m1.json`](evidence/product-performance-regression-macos-arm64-m1.json).

Its two JSON documents under `benchmark/evidence/` bind the exact upstream
revision and Zig version to separate GUI-app, official benchmark, and local
capture-source SHA-256 values. They also freeze the synthetic parser corpus,
seven input observations, public ScreenCaptureKit pixel boundary, two short
process-resource windows, and four relative gates. Raw samples, terminal text,
commands, paths, process IDs, and timestamps are not retained.

Regeneration is intentionally separate from the offline check. First build the
unmodified pinned comparator and its `+terminal-parser` benchmark as documented
in `docs/phase11/product-performance-regression-gate.md`, then collect fresh
passing Release AOT product microbenchmark and runtime outputs. Run
`tool/ghostty_performance_capture.dart` with absolute paths for
`--ghostty-app`, `--ghostty-benchmark`, `--capture-source`, `--product-micro`,
`--product-runtime`, `--output-evidence`, and `--output-relative`. The capture
refuses an existing Ghostty instance, isolates configuration/cache/shell state,
requires Screen Recording and Automation access, terminates its owned app, and
fails closed on any identity, diagnostic, workload, or result mismatch.

The Release AOT executable writes one
`dart-terminal-product-benchmark-result` version-1 JSON document to stdout and
one bounded status line to stderr. It records only fixed workload/environment
provenance, p50/p95/p99 distributions, hard and baseline gates, and content-free
integrity counts. Raw samples, terminal content, commands, paths, process IDs,
timestamps, serial numbers, and hardware UUIDs are not retained.

[`baselines/product-micro-macos-arm64-m1.json`](baselines/product-micro-macos-arm64-m1.json)
was frozen from six clean Release AOT runs on the named hardware class. Baseline
loading rejects unknown keys, invalid or unbounded tolerances, oversized input,
different metric inventories, and any environment or workload mismatch. Parser
throughput must also remain at least 100 MiB/s; both damage stages must remain
under 4 ms p95; and key routing through pane write admission must remain under
2 ms p95 independently of the relative baseline.
