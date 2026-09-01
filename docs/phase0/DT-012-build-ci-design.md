# DT-012 — Debug, release, and Universal bundle CI design

- Status: accepted design; arm64 local path verified
- Date: 2026-09-01
- Scope: Phase 0 build/release boundary and final integrated acceptance
- Related: ROADMAP Phase 0, Phase 1 runtime substrate, and Phase 11 distribution

## Question

Can development JIT, per-architecture release AOT, and future Universal
distribution be kept as explicit, non-interchangeable build products, with a
CI handoff that cannot silently omit an architecture, mix Engine revisions, or
ship an invalid app layout?

Yes for the design and the complete arm64 path. This report does **not** claim
that a Universal application already exists: only ProductARM64 and ReleaseARM64
Engine outputs are present on the Phase 0 machine. Building ProductX64,
producing both thin release artifacts, and assembling the first Universal
application remain Phase 1 work exactly as specified by the roadmap.

## Frozen inputs

| Input | Phase 0 value |
| --- | --- |
| Dart SDK | 3.13.2 stable, revision `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` |
| Dart Engine source | same revision as the released SDK |
| worker-isolate patch | SHA-256 `0fe32a3c03976891ddd6bbf237aad599d8396e3747fedacdf952ab165100e2f5` |
| `dart_appkit` | `5613950f15cf9837e5a025a9943c5b8010be4218` |
| deployment target | macOS 14.0 |
| Phase 0 host | arm64 Apple M1, macOS 26.6.2 build 25G83, Xcode 26.6 |

The Engine checkout contains the reviewed worker-isolate patch as one tracked
local modification. CI must apply that same patch with its idempotent Make
target and fail if it no longer applies cleanly; it must not consume an
unidentified prebuilt Engine.

## Build modes are separate products

| Product | Dart payload | Engine | Purpose | Distribution status |
| --- | --- | --- | --- | --- |
| developer JIT | full linked Kernel | matching `ReleaseARM64` or `ReleaseX64` JIT Engine | rapid development, assertions/diagnostics, AppKit smoke | never distributed |
| thin release AOT | architecture-specific AOT snapshot | matching `ProductARM64` or `ProductX64` AOT Engine | performance, hardware gates, one-architecture artifact | CI intermediate |
| Universal release AOT | lipo-combined host, AOT Engine, and AOT snapshot | both exact thin Product outputs | signed user application | Phase 1 implementation, Phase 11 distribution |

The word “debug” in local targets means the developer JIT workflow. Its native
JIT Engine is built in Dart's Release configuration because that is the tested
embedding combination; this does not turn the Kernel application into the AOT
release product. No Kernel, JIT Engine, or VM service asset may enter a release
bundle.

## CI graph

```text
source/contract checks
├─ developer-JIT arm64 smoke
├─ developer-JIT x86_64 smoke
├─ release-AOT arm64 build → thin audit → hardware spikes → artifact + report
└─ release-AOT x86_64 build → thin audit → hardware spikes → artifact + report
                                  │
                    matching thin artifacts only
                                  ▼
                       Universal assembly job
                                  │
              exact arm64+x86_64 audit + fresh signing
                         ┌────────┴────────┐
                         ▼                 ▼
                 arm64 hardware smoke   Intel hardware smoke
```

The two release lanes use native hardware. Rosetta is useful as an additional
compatibility smoke but is not evidence that an x86_64 host, Engine, snapshot,
or native code path works on Intel hardware. Performance comparison runs only
on a named baseline machine; arbitrary shared CI hosts run hard correctness
gates but do not rewrite the checked performance baseline.

## Lane contract

### Source and developer JIT

Every change runs formatting without mutation, static analysis, Dart unit
tests, and full Kernel compilation. A macOS UI lane launches the generated JIT
AppKit bundle and requires its automated close and clean VM/native shutdown.

The local entry points are:

```sh
make phase0-debug-check
make phase0-debug-smoke
```

### Thin release AOT

Each architecture starts from a clean architecture-specific build directory,
compiles all native objects with deployment target 14.0, compiles every Dart
snapshot with the matching SDK architecture, and links only the matching
Product AOT Engine. It then runs the AOT, worker, PTY, Metal, CoreText, IME,
grid, parser, and benchmark gates.

`make phase0-bundle-audit` emits `dart-terminal-bundle-audit` version-1 JSON.
For every app it requires:

- `Info.plist` type `APPL`, expected deployment target, and a unique project
  bundle identifier;
- an executable file named by `CFBundleExecutable`;
- `Frameworks/libdart_engine_aot_shared.dylib` and
  `Resources/phase0_app.aot`;
- the exact expected architecture set in the host, Engine, and AOT snapshot;
- only bundle-relative or system dynamic dependencies, including the Engine at
  `@rpath/libdart_engine_aot_shared.dylib`;
- a valid strict/deep signature, optionally constrained to ad-hoc or Developer
  ID by the selected policy.

The audit is deliberately architecture-set based. An arm64-only Phase 0 app
passed `--expected-architectures=arm64` and failed exit 1 with
`executable architectures arm64 != arm64,x86_64` when tested as Universal.

### Universal assembly

The merge job receives immutable arm64 and x86_64 artifacts plus their JSON
reports. Before merging it verifies identical SDK/Engine revision, source
revision, worker patch, deployment target, bundle identifier/version,
entitlements, and non-Mach resources. It discards input signatures and uses a
fresh staging directory; modifying one signed thin app in place is forbidden.

The merge algorithm is:

1. copy one verified app layout into staging without `_CodeSignature`;
2. compare every non-Mach file byte-for-byte between thin artifacts;
3. use `lipo -create` on every architecture-bearing file, currently the host
   executable, Product AOT Engine, and Dart AOT snapshot;
4. reject any missing, extra, or duplicate slice and require the exact set
   `{arm64, x86_64}` for every merged Mach-O;
5. re-run dependency/install-name and bundle-layout audits;
6. sign nested code and then the outer app with fresh CI credentials;
7. re-run strict signature verification and both native-hardware smoke lanes.

Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper,
update metadata, and third-party notices are Phase 11 release gates. Phase 0
uses ad-hoc signatures only to verify bundle integrity and launchability.

Cache keys must include architecture, Dart version and revision, Engine
configuration, worker-patch hash, Xcode/SDK identity, deployment target, and
all native/Dart inputs. A cache hit is accepted only after the same audits; a
cache is never provenance.

## Local orchestration

The Makefile now exposes:

| Target | Contract |
| --- | --- |
| `phase0-debug-check` | format, analyze, unit test, full Kernel compile |
| `phase0-debug-smoke` | developer JIT AppKit launch and clean auto-close |
| `phase0-release-build` | all release-AOT spikes and benchmark artifacts |
| `phase0-release-run` | all release-AOT hardware/correctness gates in order |
| `phase0-bundle-audit` | all six local thin AOT bundles, host architecture |
| `phase0-universal-bundle-audit` | caller-supplied app, exact arm64+x86_64 |
| `phase0-verify` | complete local Phase 0 debug + release + bundle path |

The Universal target requires an explicit absolute `UNIVERSAL_BUNDLE`; it does
not guess a path or silently fall back to the current thin bundle.

## Final integrated real-hardware result

Two consecutive `make phase0-verify` executions passed from source checks
through all hardware gates and six bundle audits. The second, final-state run
reported:

| Gate | Latest integrated evidence |
| --- | --- |
| developer JIT | format clean, analyzer clean, tests pass, Kernel compiled, AppKit attach/auto-close clean |
| AOT root | main thread true, Timer true, max root turn 235 us |
| worker | 128 MiB / 512 ordered chunks, 2,876.40 MiB/s, expected fault observed, max root turn 223 us |
| PTY | interactive zsh, tty/resize/SIGINT/exit 37, 10,487,013 bytes / 161 batches, max root turn 466 us |
| Metal | 100,000 instances, 121 frames, copy p95 449 us, encode p95 306 us, GPU p95 1,569 us, max root turn 567 us |
| CoreText | Latin/CJK/emoji/ligature all pass; shaping native p95 at most 32 us |
| IME | marked/commit/unmark/raw ordering and candidate screen rect pass; native p95 27 us |
| packed grid | full p95 238 us, sparse p95 29 us, transfer p95 164 us |
| parser corpus | 9 cases / 190 split runs / 32 snapshot lines, 157.29 MiB/s |
| regression suite | all five hard and machine-relative metrics pass |
| bundle audit | six apps; host, Engine, snapshot all arm64; rpath/layout/signature pass |

The largest measured AppKit/root turn across both integrated runs was **742
us**, 18.6% of the 4,000 us Phase 0 ceiling. The post-fork PTY object audit again
found only `__error`, `_exit`, `close`, `execve`, and `write` dependencies; it
found no Dart runtime or Objective-C allocation path.

Artifacts added for this contract:

| Artifact | SHA-256 |
| --- | --- |
| bundle audit source | `ec9050e023d323ed3e81a4ac820609b00c13a37400ece60b18dd6e6990717574` |
| integrated debug Kernel | `8272362e8ed569c69424a43f29f0bc29837869de2b42bfa29593a153f7afc3e7` |

## Decision

Accepted. Phase 0 now has distinct developer-JIT and release-AOT paths, one
command for complete local acceptance, a machine-readable app-bundle auditor,
and an exact Universal CI handoff that rejects thin artifacts.

Phase 1 must implement and exercise the x86_64 lane and Universal merge; Phase
11 must add distribution signing/notarization. Until both thin native-hardware
lanes and the exact-slice audit pass, the project must describe its generated
apps as arm64 release-AOT—not Universal.
