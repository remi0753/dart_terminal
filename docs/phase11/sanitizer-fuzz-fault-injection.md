# Phase 11 sanitizer, fuzz corpus, and fault-injection validation

## Status

- Phase: 11
- Task: native ASan/UBSan, fuzz corpus, and fault injection
- Started: 2026-09-13
- State: in progress
- Current subtask: contract and inventory (complete)

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
