# Developer JIT and release AOT runtime paths

- Status: historical initial implementation; runtime topology and provenance
  contract superseded on 2026-09-03
- Date: 2026-09-01
- Scope: first Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, `FEATURE_MATRIX.md` RT-01 and DIST-01,
  `docs/phase0/DT-012-build-ci-design.md`, ADR-001, and ADR-002

> Current product builds use the stock-Engine root plus official Dart child
> process contract in `stock-dart-runtime-migration-plan.md`. References below
> to an Engine modification or retired Phase 0 aggregate are preserved only as
> evidence of the implementation that this task originally validated; they are
> not current build instructions.

## Purpose

Replace the Phase 0 spike-oriented build entry points as the product workflow
with explicit developer-JIT and release-AOT paths. Both paths must run the same
`bin/main.dart` application and the same integration smoke contract while
remaining mechanically non-interchangeable build products.

## Background

Phase 0 proved that a full linked Kernel can run in the `dart_appkit` JIT
Runner and that a Product AOT Engine can host an AOT snapshot on the AppKit
main thread. It also froze the rule that developer JIT is never distributed
and that no Kernel, JIT Engine, or VM-service asset may enter a release bundle.

The current product launch instructions use `dart run dart_appkit:run`, which
assembles and immediately launches an internal `DartAppKitRunner.app`. The
current `phase0-release-*` targets build AOT feasibility probes, not the
product `bin/main.dart`. Therefore the repository does not yet have two
explicit product artifacts which can be built, audited, and exercised by one
integration suite.

## Scope

- Add product-facing Make targets for building, running, auditing, and smoke
  testing the developer-JIT application.
- Add the corresponding product-facing release-AOT targets.
- Build both products from `bin/main.dart` and the current package graph.
- Reuse the pinned `dart_appkit` AppKit bridge and bounded message pump.
- Give each mode a separate build directory, payload kind, Engine dylib, and
  bundle metadata marker.
- Add one mode-parameterized bundle auditor and one mode-parameterized
  integration smoke runner, then run the same checks for both modes.
- Preserve the accepted Phase 0 spike targets as historical feasibility and
  regression gates; product verification must not depend on invoking them.
- Update the product launch and verification documentation.

## Out of scope

- ProductX64 or ReleaseX64 Engine work.
- An arm64/x86_64 matrix, `lipo`, or Universal Binary assembly.
- Developer ID signing, hardened runtime, notarization, stapling, updates, or
  Phase 11 distribution work.
- The next Phase 1 lifecycle/error/shutdown-contract roadmap item beyond the
  behavior already required to launch and cleanly stop this application.
- Moving terminal semantics, the command-console backend, or AppKit bridge
  ownership across the boundaries accepted by ADR-001 and ADR-002.

## Dependencies and confirmed facts

- The worktree was clean on `main` at task start.
- The host is arm64 and Dart 3.13.2 stable (`macos_arm64`).
- The adjacent pinned `dart_appkit` checkout has both the matching
  `ReleaseARM64/libdart_engine_jit_shared.dylib` and
  `ProductARM64/libdart_engine_aot_shared.dylib`.
- `dart_appkit`'s JIT launcher uses its Engine build's
  `bootstrap_gen_kernel.exe` and development `vm_platform.dill`; using the
  released SDK's product platform Kernel with that JIT Engine is invalid.
- `dart_appkit`'s bridge resolves through `DynamicLibrary.process()`, so the
  product host must link and export the same bridge symbols.
- The Phase 0 AOT host is probe-specific: it invokes a zero-argument `main`,
  exposes `dt_phase0_*` ABI calls, and treats a probe success report as the
  application result. It is not a product host for `TerminalApplication`.
- Product release AOT therefore needs a small repository-owned AppKit host
  which loads `application.aot`, forwards application arguments, installs the
  existing bridge event poster, and follows the existing bounded pump and
  bridge shutdown order.

## Options considered

### Keep using `phase0-debug-*` and `phase0-release-*`

Rejected. The former does not leave a named product artifact as its contract,
and the latter compiles spike entrypoints rather than `bin/main.dart`. Passing
both groups would not prove equivalent product behavior.

### Extend the adjacent `dart_appkit` launcher in this task

Rejected for this repository task. It would require a separate-repository
change and release cadence. The existing bridge sources and message pump are
already suitable build inputs; only the AOT-specific product host belongs
here under the boundary described by ADR-001.

### Use one executable or silently select payload type at runtime

Rejected. Separate hosts, Engine names, resource names, output directories,
and mode metadata make accidental JIT/release mixing auditable and prevent a
release target from falling back to Kernel execution.

## Acceptance criteria

1. `developer-jit-build` creates a product-branded `.app` from
   `bin/main.dart`, a full linked `application.dill`, and only the matching JIT
   Engine.
2. `release-aot-build` creates a product-branded `.app` from the same
   `bin/main.dart`, `application.aot`, and only the matching Product AOT Engine.
3. Build and run targets are explicit and do not infer or fall back to the
   other mode's payload, Engine, or bundle.
4. A bundle audit verifies the declared mode, exact host architecture,
   deployment target, executable, bundle-relative Engine dependency, ad-hoc
   signature, required payload, and absence of the incompatible payload,
   Engine, and VM-service artifacts.
5. The same integration smoke program launches each mode with
   `--auto-close-after=1`, requires the attach/scheduled-close/clean-shutdown
   observations, rejects unexpected stderr, enforces a timeout, and requires
   exit status 0.
6. Formatting, static analysis, unit tests, both builds, both audits, and both
   common integration runs pass on the host architecture.
7. The release bundle passes the existing architecture/layout/signature audit
   extended or invoked with product-specific resource expectations.
8. README and Make help identify developer JIT as the normal development path
   and release AOT as the non-distributable thin host-architecture release
   product. No documentation calls it Universal.
9. The work does not implement or claim x86_64/Universal support.

## Validation plan

- Run `dart format --output=none --set-exit-if-changed` on Dart sources.
- Run `dart analyze` and `dart run test/run_tests.dart`.
- Build and audit developer JIT and release AOT separately.
- Run the identical integration smoke harness once per mode.
- Run the combined runtime verification target from a clean-enough incremental
  state and review all generated bundle contents with `find`, `file`, `otool`,
  `lipo`, `plutil`, and `codesign` through the auditor.
- Exercise at least one negative audit case proving an incompatible payload is
  rejected without modifying a signed accepted bundle in place.
- Review `git diff`, generated/untracked files, staged diff, and final status
  before committing only this task.

## Risks and open checks

- AOT invocation must pass a typed `List<String>` to the async product `main`
  and allow the existing scheduler to service its returned Future.
- The Product AOT Engine retains the accepted worker-isolate patch. The build
  must apply it idempotently without introducing Phase 1 x86_64 work.
- App termination is asynchronous. The delegate must disable bridge posting,
  stop the message pump, and shut down the Engine only after Dart has released
  its window/view handles.
- Bundle signing must occur after every copied input; audit must not mutate the
  artifact it validates.

## Investigation log

### 2026-09-01 — repository and contract review

- Read `AGENTS.md`, `README.md`, all of `ROADMAP.md`, all of
  `FEATURE_MATRIX.md`, all four ADRs, and Phase 0 reports DT-002, DT-003,
  DT-011, and DT-012.
- Inspected the complete repository file inventory, current product Dart code,
  tests, Makefile, Phase 0 AOT host, bundle auditor, and the adjacent pinned
  `dart_appkit` Runner/launcher/bridge implementation.
- Confirmed this is the first incomplete roadmap item. The next
  arm64/x86_64/Universal item remains strictly out of scope.
- The task is one coherent build-contract change with shared host/audit/smoke
  dependencies and does not need roadmap subdivision before implementation.

## Implementation log

### 2026-09-01 — product runtime paths added

- Added separate `build/runtime/developer-jit` and
  `build/runtime/release-aot` products. Both compile `bin/main.dart`; their
  executable names, Engine dylibs, payload names, Info.plist identifiers, and
  `DTRuntimeMode` values are intentionally different.
- The developer build follows the pinned `dart_appkit` launcher contract: it
  compiles a full linked Kernel with the Release JIT Engine's own
  `bootstrap_gen_kernel.exe` and development `vm_platform.dill`, then packages
  the existing tested Runner and JIT Engine.
- Added `native/macos/runtime/ReleaseAotRunner.mm`. It links the existing
  `dart_appkit` bridge sources and bounded `DartMessagePump`, loads only the
  bundled `application.aot`, creates the Product AOT root isolate on the main
  thread, builds and forwards `List<String>` arguments, installs immutable
  native event posting, and invokes the same product `main`.
- The release delegate checks for fatal Dart errors and leaked bridge handles.
  Its termination order is bridge shutdown (which disables event posting and
  releases any remaining native objects), message-pump stop, then Dart Engine
  shutdown. A nonzero live-handle count is reported as a product integration
  failure even though forced bridge cleanup still runs.
- Added `tool/runtime_bundle_audit.dart`. It requires an explicit mode and
  checks mode metadata, exact host architecture, deployment target, one
  matching Engine, one matching payload, incompatible asset absence,
  bundle-relative dependencies, executable permissions, and ad-hoc signing.
  Release mode additionally rejects all `.dill` and VM-service-named assets.
- Added `tool/runtime_integration_smoke.dart`. The same harness adapts only the
  unavoidable host launch syntax, then applies identical timeout, exit,
  stderr, attach, scheduled-close, and clean-shutdown assertions to both
  products.
- Product targets were added without removing the historical `phase0-*`
  feasibility targets. The worker patch now also has the product-facing
  `dart-engine-worker-support` name; the old target remains an alias.

### 2026-09-01 — first audit failure and correction

- The first developer-JIT build completed, including the revision/architecture
  Engine validation and full linked Kernel compilation.
- Its strict signature audit then failed with `a sealed resource is missing or
  invalid`. The build had signed the bundle and subsequently touched a build
  stamp under `Contents/`, changing the signed resource set.
- Moved both runtime-mode stamps outside their `.app` directories. Bundle
  assembly now copies every input, signs last, and makes no later mutation to
  the accepted artifact. The failed bundle is a generated ignored artifact and
  is replaced by the corrected rebuild; no source or user data was lost.

### 2026-09-01 — first release launch failure and correction

- The first release product compiled, linked, signed, and passed its AOT-only
  bundle audit. On launch the embedder's explicit one-argument `Dart_Invoke`
  could not resolve the product `main(List<String>)` after AOT precompilation;
  the process exited nonzero and the common smoke harness reported the stderr.
- Phase 0's zero-argument probe main did not expose this product-argument
  boundary. Marked the product `bin/main.dart` function with
  `@pragma('vm:entry-point')`, which is the explicit contract required when a
  native embedder invokes a Dart function by name after tree shaking. The JIT
  path continues to use the same source function.

### 2026-09-01 — mode isolation negative checks

- Copied the accepted release bundle to a unique `/private/tmp` directory and
  added `Contents/Resources/application.dill`. The release audit exited 1 and
  reported `bundle contains incompatible payload: application.dill` before
  signature validation. The temporary copy was then removed; the signed
  accepted bundle was never modified.
- Audited the unmodified release-AOT bundle while claiming
  `--mode=developer-jit`. The audit exited 1 and rejected the release bundle
  identifier instead of inferring or falling back to its actual mode.
- These failures confirm both content mixing and caller-declared mode mismatch
  are closed fail-safe paths.

### 2026-09-01 — format validation correction

- The first Dart formatting command changed the two new Dart tools, then the
  sandbox blocked Dart's unrelated telemetry-session timestamp update outside
  the workspace. Re-running the same formatter with the normal tool runtime
  permissions reported zero additional source changes.
- A dry-run of `clang-format` against `dart_appkit`'s checked style rejected
  several line wraps in the new Objective-C++ host. Applied that exact
  formatter and added its dry-run plus both plist lints to
  `runtime-source-check`, so native/source metadata formatting is now part of
  the repeatable product gate.

### 2026-09-01 — final dependency and audit review

- The final diff review found that the outer developer-JIT target named the
  bridge and message-pump inputs but not every source/header used by the
  adjacent Runner target. Added the full Runner input set so a change in the
  pinned checkout cannot leave a stale product host merely because the outer
  binary already exists.
- Extended the release asset-name check to reject `vm-service` as well as
  `vmservice` and `vm_service` spellings. This is intentionally independent of
  signature validation, so forbidden content fails with a direct policy error.
- The first commit invocation ran with read-only Git metadata permissions and
  failed before writing with `Unable to create .git/index.lock`. The complete
  staged change set remained intact; the same non-history-rewriting commit was
  retried with repository metadata write permission after recording this
  environment-only failure.

## Verification results

All commands below ran on the arm64 host on 2026-09-01.

### Product source, build, audit, and integration gate

Final `make runtime-verify` result: pass.

- `dart format --output=none --set-exit-if-changed bin lib test tool benchmark`:
  22 files checked, 0 changed.
- Objective-C++ `clang-format --dry-run --Werror`: pass for
  `ReleaseAotRunner.mm` using the pinned `dart_appkit` style.
- `plutil -lint`: both product Info.plists pass.
- `dart analyze`: no issues found.
- `dart run test/run_tests.dart`: `dart_terminal tests passed`.
- The release host compiled with `-Wall -Wextra -Wpedantic -Werror` after the
  final formatting change.
- Developer-JIT bundle audit: pass; arm64 executable and JIT Engine, only
  `Resources/application.dill`, deployment target 14.0, bundle-relative Engine
  dependency, and strict ad-hoc signature all accepted.
- Release-AOT bundle audit: pass; arm64 executable, Product AOT Engine, and AOT
  snapshot, only `Resources/application.aot`, deployment target 14.0,
  bundle-relative Engine dependency, and strict ad-hoc signature all accepted.
- The common integration harness passed in developer-JIT mode in 1,951 ms and
  release-AOT mode in 1,624 ms. Each observed main-thread attachment, the
  one-second scheduled close, clean Dart/application shutdown, no stderr, and
  status 0 within the 12-second bound.
- The documented direct run paths also passed with
  `RUNTIME_ARGUMENTS=--auto-close-after=1` in both modes.
- `make help` lists the product runtime targets separately from the historical
  Phase 0 targets.

### Fail-safe negative checks

- A fresh temporary copy of the accepted release bundle was given
  `Contents/Resources/application.dill`. The release audit exited 1 with
  `bundle contains incompatible payload: application.dill`.
- The unmodified release bundle was audited with `--mode=developer-jit`. The
  audit exited 1 with the exact release/developer bundle-identifier mismatch;
  it did not infer the actual mode or fall back to release execution.
- The first final negative-check invocation was blocked before the auditor ran
  because Dart attempted to update its telemetry session timestamp outside the
  restricted workspace. Re-running with the normal Dart tool permissions
  produced the policy failures above. The temporary copied bundle was removed
  afterward and the accepted signed artifact remained unchanged.

### Historical regression gates

- `make phase0-debug-check`: pass.
- `make phase0-debug-smoke`: pass.
- `make phase0-verify`: pass in full. This included the root-isolate AOT,
  worker lifecycle/transfer, PTY/job control/batching, Metal, CoreText, IME,
  packed-grid, parser, benchmark, and all six Phase 0 bundle audits. The six
  bundles remained accepted as arm64 artifacts. Representative bounded-pump
  maxima remained below the existing acceptance limits (root AOT 193 us,
  worker 988 us, PTY 601 us, Metal 534 us, CoreText 160 us, IME 163 us).

## Remaining risks and handoff

- This task intentionally produces host-architecture thin artifacts. Only
  arm64 was built and accepted here. ProductX64, ReleaseX64, the architecture
  matrix, `lipo`, and Universal assembly remain the next roadmap item and were
  not started.
- Bundles are ad-hoc signed development artifacts. Developer ID, hardened
  runtime, notarization, and distribution acceptance remain Phase 11 work.
- The release host compiles the bridge and message pump from the pinned
  adjacent `dart_appkit` checkout. Their complete current input set is tracked
  by Make, but a future pin change still requires both runtime modes and the
  Phase 0 regressions to be rerun.
- The common smoke proves valid launch, argument forwarding, automatic window
  close, handle release, pump stop, and Engine shutdown. Fault injection and a
  broader VM/isolate error and uncaught-exception contract belong to the later
  Phase 1 lifecycle item.
- No blocker or newly discovered prerequisite remains, and no additional
  roadmap item was added.
