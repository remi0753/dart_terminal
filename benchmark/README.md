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
