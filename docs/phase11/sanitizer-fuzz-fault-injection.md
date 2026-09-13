# Phase 11 sanitizer, fuzz corpus, and fault-injection validation

## Status

- Phase: 11
- Task: native ASan/UBSan, fuzz corpus, and fault injection
- Started: 2026-09-13
- State: in progress
- Current subtask: deterministic Dart fuzz corpus/property expansion (complete)

## Purpose

Close the remaining memory-safety and recovery evidence gap with a reproducible
gate that instruments every product-owned native implementation, expands the
reviewed deterministic Dart corpus at uncovered boundaries, and proves that
injected native and Dart failures recover or fail closed without corrupting
owner state. The gate must complement, not replace, the normal warning-clean,
unit, product-runtime, resource, and reliability gates.

## Background

The product already has extensive parser properties, modern-protocol stress,
native capability tests, renderer failure injection, runtime-worker shutdown
faults, exact owner/handle cleanup checks, and bounded system recovery. Those
tests run without AddressSanitizer or UndefinedBehaviorSanitizer, and their
fuzz/fault inputs were created for earlier feature phases. The Phase 11 roadmap
therefore requires an explicit cross-boundary closure rather than treating
ordinary successful tests as sanitizer evidence.

`dart_appkit` remains a generic macOS GUI library. This task owns only the four
native packages inside the Dart Terminal repository and product-side Dart test
infrastructure. It must not add product-specific code, identifiers, targets, or
files to `dart_appkit`, and it must not add any code whose name contains
`terminal` there.

## Scope

- Compile and execute the native PTY, renderer, AppleScript, and App Intents
  capability suites with AddressSanitizer and the compiler's supported
  undefined-behavior checks, strict non-recovering runtime options, isolated
  outputs, and a bounded timeout.
- Preserve the existing ordinary native targets and build-hook flags. Sanitizer
  artifacts must not be mistaken for application/bundle or distributable
  artifacts.
- Extend the versioned, reviewed, deterministic Dart fuzz corpus and fixed-seed
  property runner at boundaries not already represented by the Phase 3 and
  Phase 9 suites. Every failing case must report a reproducible case identity
  and bounded, content-free diagnostics.
- Add focused fault injection for native allocation/ABI and Dart queue/parser/
  renderer ownership boundaries where existing tests only cover malformed input
  or one-way failure. Assert post-fault forward progress, exact cleanup, and
  unaffected peer ownership.
- Compose sanitizer, fuzz, fault, ordinary repository, and relevant shipped-
  runtime evidence into one documented aggregate gate.

## Out of scope

- Nondeterministic or internet-scale fuzzing, continuous fuzz infrastructure,
  and long-duration campaigns.
- Replacing normal native tests, performance gates, 24/72-hour soak, or real
  user/application acceptance with sanitizer runs.
- Shipping sanitizer runtimes or instrumented dynamic libraries inside a
  release application.
- Changes to the generic `dart_appkit` repository or its public/native API.
- New terminal protocol, UI, automation, or compatibility features.
- ThreadSanitizer, which is not requested by this roadmap item and has different
  scheduling and runtime requirements.

## Dependencies

- The warning-clean native recipes and capability executables in `Makefile`.
- The four product-owned native packages under `packages/`.
- Phase 3 `test/terminal_property_fuzz_test.dart` and
  `test/corpus/fuzz/product_v1.json`.
- Phase 9 parser/state properties and authority/resource stress suites.
- Phase 1 shutdown-fault integration, Phase 4 Metal fault injection, Phase 11
  bounded reliability, and their exact owner/cleanup diagnostics.
- Apple Clang/Swift toolchains selected through `xcrun` on the macOS host.

## Completion conditions

1. Every in-repository native implementation is represented by an executed
   ASan/UBSan-capable test binary or library path; instrumentation/link/runtime
   failures fail the gate and normal targets remain unchanged.
2. The deterministic Dart corpus adds reviewed uncovered inputs with a versioned
   bounded manifest, fixed seed, chunk/recovery equivalence, exact caps, and a
   stable reproduction identity.
3. Fault injection covers selected native and Dart ownership boundaries and
   proves rejection or typed failure, subsequent valid work, no peer poisoning,
   idempotent cleanup, and zero retained product owners.
4. The aggregate target passes together with focused normal tests and
   `CI=true DART_SUPPRESS_ANALYTICS=true make test`; documentation and
   `FEATURE_MATRIX.md` describe only evidence actually executed.
5. The final diff contains no generated sanitizer artifact, no release-policy
   weakening, and no Dart Terminal code or naming added to `dart_appkit`.

## Verification approach

- Use a dedicated build directory and force rebuilds so stale ordinary objects
  cannot satisfy a sanitizer target.
- Use strict ASan/UBSan settings that stop on the first report and make missing
  sanitizer instrumentation/runtime linkage observable before accepting suite
  output.
- Keep fuzz budgets fixed and synchronous. Compare whole, deterministic chunk,
  bytewise where bounded, recovery, and repeat observations using canonical
  digests rather than dumping attacker-controlled content.
- Prefer explicit injectable test seams over global environment mutation. Keep
  them test-only or default-inert and validate the invalid/consumed-once cases.
- Record exact commands, expected markers, results, defects, and residual risks
  in this memo as each ordered child completes.

## Ordered subtasks

1. **Contract and inventory**
   - Map every product-owned native source/test/build path, existing corpus and
     property surface, and existing fault/recovery seam.
   - Fix sanitizer/fuzz/fault ownership, exclusions, completion conditions, and
     the ordered children in this memo and `ROADMAP.md`.
   - Complete with a documentation-only commit after diff validation.
2. **Product-owned native ASan/UBSan capability gate**
   - Add isolated sanitizer build/test recipes for PTY, renderer, AppleScript,
     and App Intents, including instrumentation/runtime assertions and strict
     diagnostics.
   - Complete when every sanitizer suite and the exact repository gate pass in
     a standalone commit.
3. **Deterministic Dart fuzz corpus/property expansion**
   - Reconcile Phase 3/9 coverage, add only missing reviewed seeds and mutations,
     and strengthen deterministic recovery/cap/chunk invariants.
   - Complete when focused fuzz/property suites and the exact repository gate
     pass in a standalone commit.
4. **Bounded native/Dart fault injection and recovery**
   - Add the smallest test seams needed for uncovered native allocation/ABI and
     Dart owner/queue recovery cases, then assert valid subsequent work and
     complete cleanup.
   - Complete when focused native/Dart/runtime checks and the exact repository
     gate pass in a standalone commit.
5. **Aggregate closure**
   - Compose named gates, run relevant normal/shipped-runtime validation, audit
     the adjacent generic-library boundary, update public/matrix documentation,
     and close the parent only when all evidence is passing.

## Inventory and decisions

### Product-owned native boundary

| Owner | Production source | Ordinary capability path | Sanitizer gap |
| --- | --- | --- | --- |
| PTY | `packages/dart_pty_macos/native/PtySession.cc`, `PtySpawn.c`, `PtyExecChild.c` | `dpty-native-test`; C/C++ header checks, child-object audit, dylib loaded by `PtyCapabilityTests.cc` | No instrumented objects, dylib, test executable, or strict sanitizer runtime gate |
| Renderer | `packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m` and compiled Metal shader | `terminal-renderer-native-test`; plugin dylib plus AppKit/Metal capability executable | Manual `malloc`/`calloc` buffers and Objective-C++ bridge execution are not instrumented by a dedicated gate |
| AppleScript | `packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.m` | `terminal-applescript-native-test`; public dylib plus testing object/capability executable | Queue/snapshot native ownership has no sanitizer build/run |
| App Intents | `packages/dart_terminal_app_intents_macos/native/TerminalAppIntents.swift` | `terminal-app-intents-native-test`; Swift dylib, C++ ABI executable, and Swift perform executable | Swift unsafe-pointer ABI and the C++ caller have no sanitizer build/run |

The native build hooks are production packaging inputs and intentionally retain
normal compiler flags. The sanitizer gate will be Make-owned test
infrastructure under this repository. Generic AppKit bridge sources are linked
into the renderer capability executable as a dependency, but are not owned or
modified by this task and cannot be claimed as complete generic-library
sanitizer coverage.

### Existing deterministic fuzz/corpus evidence

- Phase 3 has a versioned seven-seed manifest, 96 generated inputs, 112 bounded
  mutations, whole/generated-chunk/bytewise/recovery runs, and a fixed xorshift
  seed in `test/terminal_property_fuzz_test.dart`.
- Phase 9 adds eight modern-protocol anchors, 64 bit mutations, 64 generated
  programs, 680 protocol executions, and authority/resource state-machine
  stress for OSC 52, desktop signals, synchronized output, and Kitty graphics.
- The product corpus separately replays reviewed shell, `less`, `top`, and `vim`
  streams. Compatibility and application matrices cover externally pinned
  behavior, not arbitrary mutation ownership.
- The expansion must first reconcile seed bytes against parser actions and
  retained resource families. Increasing a case count alone is not acceptable
  evidence of a new boundary.

### Existing fault evidence

- Phase 1 injects malformed/late native events, double dispose, a crashed
  official Dart worker, and bounded shutdown failures, then checks surviving
  work, PID reaping, handles, and diagnostics in both runtime modes.
- Renderer capability/Dart tests have consume-once Metal device, shader,
  drawable, encoding, and completion failures plus renderer recreation.
- PTY tests cover real nonblocking/backpressure/exit behavior, but there is no
  explicit native allocation/ABI fault seam.
- AppleScript and App Intents tests cover malformed packets, disabled/timeout/
  shutdown/overflow and typed failure projection, but not an injected native
  allocation failure followed by successful reuse.
- Dart scheduling, transfer, restoration, update, diagnostics, and automation
  tests contain focused thrown/native/write failure fakes. The closure child
  must select unproven recovery boundaries rather than duplicating these cases.

### Risks and invariants

- A sanitizer executable can appear to pass if only the harness, not the loaded
  dylib, is instrumented. Build and runtime markers must establish coverage of
  both sides of each dynamic boundary.
- macOS framework internals and Metal drivers are outside product ownership.
  Reports must be attributed before changing product code, but no real product
  report may be suppressed from the gate.
- Swift and Clang sanitizer flag/runtime compatibility must be probed with the
  selected Xcode toolchain. Unsupported combinations must be split explicitly;
  they must not silently turn UBSan into an ASan-only claim.
- ASan leak detection availability on macOS is not assumed. Exact product owner,
  handle, and allocation counters remain required independently of address
  safety reports.
- Fuzz and fault output must stay content-free and bounded. Reproduction uses
  suite/seed/case/operation identity, not raw terminal, clipboard, path,
  environment, or notification content.

## Findings and decision log

- 2026-09-13: Post-commit ROADMAP reread after bounded system reliability found
  this parent as the first incomplete item and the worktree clean. The task has
  native instrumentation, deterministic corpus, fault-recovery, and aggregate
  outputs that can be reviewed and committed independently, so it is split
  before implementation as required by repository policy.
- 2026-09-13: Repository inventory found exactly four product-owned native
  package families and no package-local Makefiles. The root `Makefile` is the
  authoritative ordinary capability build/run path. Three packages use Dart
  native-asset build hooks; App Intents is compiled directly by the root Make
  recipes.
- 2026-09-13: The ordinary native flags enforce warnings, hidden visibility,
  the macOS 14 deployment target, and appropriate C/C++/Objective-C/Swift
  language modes, but contain no sanitizer instrumentation. All sanitizer
  outputs therefore require a separate build directory and target family.
- 2026-09-13: `swiftc -help` exposes sanitizer instrumentation and recovery
  options. Exact supported checks and safe C++/Swift runtime composition remain
  an implementation-time probe for the native-sanitizer child; the contract
  does not overclaim Swift UBSan support before an executed compile/link/run.
- 2026-09-13: Existing Phase 3 and Phase 9 properties already make substantial
  deterministic claims. The new fuzz child will begin from a coverage
  reconciliation and will not inflate execution counts merely to close the
  roadmap wording.
- 2026-09-13: This contract introduces no code or naming into `dart_appkit`.
  Its bridge remains an unchanged dependency of the renderer capability test.
- 2026-09-13: Contract/inventory validation passed `git diff --check` and the
  exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate. The latter ran
  all four ordinary native capability families, freshness/compatibility/
  application/distribution checks, formatted 323 Dart files with zero changes,
  reported no analysis issues, and ended with `dart_terminal tests passed`.
  No build artifact is part of the task diff.
- 2026-09-13: Commit `cf03966` (`Define sanitizer fuzz and fault boundaries`)
  recorded the first child. The required post-commit ROADMAP and memo reread
  found a clean worktree and selected the product-owned native sanitizer child;
  fuzz expansion remains its next ordered successor.
- 2026-09-13: The first sanitizer execution compiled and passed the PTY suite,
  then the Metal compiler tried to write its implicit module cache under the
  user cache directory, which the task sandbox intentionally cannot modify.
  This was a build-runner isolation defect, not a product or sanitizer report.
  The runner now assigns both Clang and Metal module caches to the same bounded
  temporary sanitizer directory, which is deleted after every success/failure.
- 2026-09-13: The isolated retry reached the renderer but every Metal-dependent
  expectation failed without an ASan/UBSan diagnostic. Exact section audits
  proved that the embedded `__DATA,__dtrlib` length and bytes matched the normal
  artifact. An optimization hypothesis was tested with local address/lifetime
  changes, but did not change the result and those experimental product/test
  edits were removed.
- 2026-09-13: A fresh ordinary, uninstrumented renderer capability run then
  failed at the same device-creation boundary, and an independent Swift probe
  returned `MTLCreateSystemDefaultDevice() == nil` while `system_profiler`
  continued to report the Apple M1 GPU and Metal support. This establishes a
  transient host/display/device-availability condition, not a sanitizer report
  or source regression. The sanitizer gate will always exercise a device-
  independent renderer ABI/CoreText/allocation subset and accept only the typed
  device-unavailable result when no device exists. The ordinary full Metal gate
  remains mandatory and will be retried before this child can complete. The
  final host sanitizer acceptance also requires real Metal renderer allocation;
  typed unavailability is diagnostic coverage, not a passing substitute.
- 2026-09-13: Re-running the ordinary renderer target outside the restricted
  task sandbox rebuilt it and passed the complete Metal capability contract.
  This confirms the earlier device absence was sandbox visibility. The first
  host sanitizer retry then passed PTY, renderer with a real Metal allocation,
  AppleScript, and both App Intents executables without an ASan/UBSan report.
- 2026-09-13: Final `make product-native-sanitizer` acceptance passed on the
  arm64 host with strict abort/halt runtime options and real Metal allocation.
  All four owners and five executable suites passed. The audit found ASan
  runtime linkage and instrumentation in all nine inspected dylib/executable
  artifacts, and UBSan symbols in seven artifacts with at least one in each of
  the PTY, renderer, AppleScript, and App Intents owners. Swift accepted both
  sanitizer compile flags but emitted no UBSan symbol for its dylib or perform
  executable; its C++ ABI harness emitted three while both Swift artifacts had
  24 ASan markers. This is recorded as toolchain behavior, not misrepresented as
  per-artifact UBSan instrumentation.
- 2026-09-13: The dedicated renderer sanitizer harness exercises public ABI,
  malformed UTF-8 rejection, CoreText catalog/shape/raster allocations and
  exact release, real Metal create/release, and duplicate-release behavior. It
  avoids duplicating the large ordinary AppKit/Metal test, which was separately
  rebuilt and passed in full on the same host.
- 2026-09-13: Final validation passed the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate outside the restricted
  GPU sandbox: all four ordinary native families, freshness/compatibility/
  application/distribution checks, formatting of 324 Dart files with zero
  changes, analysis with no issues, and the complete Dart suite passed. The
  sanitizer runner deletes its isolated temporary build on both success and
  failure, and `git diff --check` reports no whitespace errors.
- 2026-09-13: The first final full-gate invocation had one pre-existing PTY
  Dart race symptom: `live Dart child cannot steal native PTY completion`
  observed no matching completion and raised `Bad state: No element`; adjacent
  PTY cases and native capability had passed. No timeout, assertion, source, or
  test input was changed. The required identical full-gate retry passed that
  case and every subsequent stage. This single non-reproduced observation is
  retained here rather than hidden; recurrence must be treated as a defect in a
  later task, not as evidence against the sanitizer results.
- 2026-09-13: Commit `8d9b920` (`Gate product native code with sanitizers`)
  recorded the sanitizer child. The required post-commit ROADMAP and memo reread
  found a clean worktree and selected deterministic Dart fuzz corpus/property
  expansion; fault injection remains its next ordered successor.
- 2026-09-13: Reconciliation of the seven Phase 3 reviewed seeds and the Phase 9
  protocol property anchors found five boundaries without a reviewed fuzz seed:
  raw C1 control/string dispatch, sequence re-entry and cancellation, exact and
  one-over configured parser limits, UTF-8 scalars whose continuation bytes
  resemble C1 controls, and resize boundaries inside UTF-8/control sequences.
  The existing generated inputs exercise arbitrary bytes, but do not give these
  cases stable review identities.
- 2026-09-13: The existing reviewed seed and bit-mutation path compares whole,
  deterministic-chunk, and bytewise results but does not apply the recovery
  sentinel used by generated cases. The expansion will retain the historical
  manifest unchanged, add a separate versioned Phase 11 manifest, enforce
  uniqueness and aggregate bounds across both manifests, and run CAN/RIS plus a
  printable recovery sentinel after every reviewed input and mutation. This
  adds an invariant rather than increasing counts alone.
- 2026-09-13: The first focused run was blocked before test execution because
  the Dart tool attempted to update its user-level telemetry-session metadata
  outside the repository sandbox despite analytics suppression. Running the
  same command on the host reached all 1,296 executions without a property
  failure; it stopped only at the intentionally stale deterministic digest
  placeholder and reported 95,388 parsed bytes with state hash `733442573`.
  Those observed values are now the pinned expectation.
- 2026-09-13: `phase11_v1.json` adds five reviewed identities without changing
  the historical seven-seed manifest or its mutation ordering:
  `c1-controls-and-strings`, `sequence-reentry-and-cancel`,
  `exact-and-over-parser-limits`, `utf8-c1-precedence`, and
  `resize-inside-streaming-sequences`. Both manifests use the existing strict
  version 1 decoder. The runner additionally rejects duplicate IDs, more than
  32 total reviewed seeds, or more than 32 KiB of aggregate input across the
  pair; the cross-manifest duplicate path has a direct negative test.
- 2026-09-13: Every one of the 12 reviewed originals and 192 deterministic
  one-bit mutations now proves bytewise CAN/RIS recovery in addition to whole,
  generated-chunk, and bytewise equivalence. Together with the unchanged 96
  generated properties, the focused gate passed 1,296 executions and 95,388
  parsed bytes with the pinned state hash `733442573`. Failure diagnostics use
  fixed seed/case/mutation/offset identities and do not print input content.
- 2026-09-13: Final validation passed `git diff --check`, the focused
  `CI=true DART_SUPPRESS_ANALYTICS=true dart run
  test/terminal_property_fuzz_test.dart`, and the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate. The full gate passed
  all ordinary native capability, generated/freshness, compatibility,
  application, distribution, format (324 files, zero changes), analysis (no
  issues), and Dart tests, ending with `dart_terminal tests passed`.
- 2026-09-13: The adjacent `dart_appkit` worktree remains clean. A case-
  insensitive repository audit found `terminal` only in historical
  `docs/WORKLOG.md` prose and no Dart/native/build source name or content; this
  child made no change to the generic library.
