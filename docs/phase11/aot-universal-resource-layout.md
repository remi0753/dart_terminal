# Phase 11 — AOT release, Universal Binary, and resource layout

## Purpose

Complete the first ordered Phase 11 roadmap item by producing a reproducible
Release AOT application for each macOS architecture, combining those verified
thin products into one Universal application, and proving that executable and
resource placement follows one strict bundle contract. The distribution path
must remain generic in `dart_macos_runtime`; this repository supplies only its
application manifest, product resources, and product-specific acceptance.

## Background and current position

- Phase 10 completed in commit `8f9d70e`. ROADMAP was reread from a clean
  worktree; this is the first incomplete Phase 11 item.
- The current stock-runtime builder already produces and ad-hoc signs a working
  host-architecture Release AOT `.app`. It compiles the application snapshot,
  helper, native assets, native capabilities, and App Intents image for the
  detected architecture and records a schema-version-1 build manifest.
- The adjacent generic `dart_appkit` repository is clean. Its
  `dart_macos_runtime` package owns generic JIT/AOT bundle construction and
  resource lookup. It currently has no target-architecture option and no
  Universal assembler.
- The configured official Engine checkout contains `ProductARM64` and
  `ProductX64` outputs. The x86_64 `gen_snapshot` executes through Rosetta on
  the M1 baseline, while the selected Dart SDK executable itself is arm64-only.
  Cross-building must therefore remain in the arm64 builder process and pass a
  target architecture to compilers and hook-aware Dart builds; it cannot
  relaunch the builder as x86_64.
- The historical Phase 1 Universal implementation predates the stock-runtime
  migration and is evidence, not reusable current tooling. Its containment,
  immutable-input, all-Mach-O, resource-equality, signing-order, and atomic
  publication lessons remain applicable.

## Scope

- Freeze the thin and Universal bundle inventory, target-architecture,
  resource-equality, manifest, ownership, signing-order, and publication
  contracts.
- Add a generic, release-only target-architecture option to
  `dart_macos_runtime`, including native host, AOT snapshot, helper, build-hook
  assets/capabilities, and App Intents compilation.
- Add a generic Universal assembler that consumes two independently verified
  arm64/x86_64 Release AOT bundles, merges every executable Mach-O entry,
  rejects mismatched or unexpected layout/resources, records deterministic
  evidence, and publishes only a complete ad-hoc-signed bundle.
- Wire product Make targets and audits for both thin applications and the
  Universal result. Exercise arm64 thin, x86_64 thin under Rosetta, and the
  Universal application's native arm64 slice on the M1 baseline.
- Reconcile README, FEATURE_MATRIX, reference/manual evidence, and the parent
  completion state.

## Out of scope

- Developer ID identity selection, hardened-runtime options, entitlements,
  notarization, stapling, and Gatekeeper distribution acceptance. Those belong
  to the immediately following Phase 11 roadmap item. This task uses only the
  existing ad-hoc signature required for local execution.
- Update feeds, update signatures, rollback, crash/hang collection,
  performance gates, sanitizers, parity burn-down, and release-candidate daily
  use, which retain their later roadmap positions.
- Product names, terminal behavior, product resource defaults, or
  product-specific acceptance logic in the adjacent generic repository.
- Intel-native physical-hardware evidence and long-duration use. The roadmap
  explicitly makes Intel-native evidence a lower-priority follow-up; Rosetta
  thin execution and structural two-slice verification are the bounded local
  acceptance for this item.

## Dependencies and risks

- Depends on the pinned Dart 3.13.2/Engine revision, matching Product ARM64 and
  X64 outputs, Xcode command-line tools, Rosetta for local x86_64 snapshot and
  runtime execution, Dart build hooks, and the existing manifest-owned bundle
  layout.
- Every executable code file must contain exactly the expected slice(s): main
  host, AOT snapshot, helper executables, Engine, declared native assets,
  declared native capabilities, and App Intents libraries. Merging only the
  launcher would create a silently architecture-incomplete application.
- Architecture-neutral files must be byte-identical between thin inputs.
  `Info.plist`, localization, terminfo, shell integration, scripting
  dictionary, SDK license, and App Intents metadata cannot be silently chosen
  from one slice when they differ.
- The per-thin build manifests necessarily differ in architecture and
  architecture-derived evidence. Universal evidence must preserve both inputs
  without pretending their bytes are equal.
- Code signatures cover nested code and resources. Universal assembly must
  merge into an isolated staging sibling, remove no last-good output, sign
  nested/outer code only after all content is final, verify strictly, and then
  atomically publish.
- The build currently accepts host architecture implicitly. Adding an explicit
  target must fail closed for Developer JIT, unknown values, launch requests for
  a foreign thin target, missing Engine inputs, and compiler output with the
  wrong architecture.

## Completion conditions

- A target-architecture contract builds both Release AOT thin applications
  from the ordinary manifest using the official stock runtime and records the
  exact target in generic build evidence.
- Every required thin code entry is exactly arm64 or x86_64 as requested; every
  declared resource is present, non-empty where required, correctly located,
  and byte-identical to its reviewed source.
- Universal assembly accepts only matching schema/application/runtime/resource
  contracts, rejects missing/extra/symlinked/mismatched or wrongly shaped
  inputs, merges every executable Mach-O into exactly `arm64 x86_64`, and
  records the two thin evidence owners in a deterministic Universal manifest.
- Failed validation, merge, signing, or publication never exposes a partial new
  result or removes a previously verified result. No build-machine absolute
  dependency path appears in the product.
- Thin arm64, thin x86_64 through Rosetta, and Universal native-arm64 product
  acceptance prove launch, the ordinary terminal path, helper/native
  capability loading, and clean teardown. Structural audit covers both
  Universal slices; Intel-native hardware remains an explicit follow-up.
- Focused generic and product tests, exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`, relevant runtime gates,
  documentation, generated evidence, roadmap state, and one commit per child
  all pass. Long-duration tests are not required for this item.

## Validation plan

- Generic option/parser/builder tests for default host behavior, explicit
  arm64/x86_64 Release AOT selection, foreign Developer JIT/run rejection,
  compiler target propagation, missing/wrong-arch inputs, and path bounds.
- Generic Universal fixture tests for exact inventory, both slice orders,
  resource and plist mismatch, missing/extra code/resources, symlinks,
  malformed Mach-O, failed `lipo`, signing failure, existing-output
  preservation, and deterministic manifest bytes.
- Product thin and Universal audits with `file`, `lipo`, `otool`, `plutil`, and
  strict `codesign`; verify the reviewed localization, terminfo, shell,
  scripting, App Intents, helper, native assets/capabilities, payload, and SDK
  license layout.
- Product smoke integration for arm64 thin, x86_64 thin under Rosetta, and the
  Universal native slice, followed by the full repository gate. The adjacent
  generic repository receives its own complete gate for each generic child.

## Ordered subtasks

1. **Distribution inventory and frozen bundle contract**
   - Record the current stock-runtime inputs, all code/resource classes,
     architecture/signing boundaries, failure policy, and test matrix before
     changing executable code.
   - Completion: this memo and all later children are present in ROADMAP,
     `git diff --check` passes, and the documentation-only contract is
     committed.
2. **Generic target-architecture thin Release AOT build**
   - Extend `dart_macos_runtime` with a bounded release-only target option and
     propagate it through Engine selection, native compilation, snapshots,
     helpers, hook assets/capabilities, App Intents, evidence, and signing.
   - Completion: generic positive/negative tests and the adjacent full gate
     pass; forbidden product-name audit is clean; the generic commit and this
     repository's dependency milestone are recorded before proceeding.
3. **Generic atomic Universal release assembly**
   - Add a generic two-thin-bundle assembler with exact layout/resource
     comparison, all-code `lipo` merge, deterministic evidence, nested/outer
     ad-hoc signing, strict verification, and atomic last-good publication.
   - Completion: generic fixture/fault tests and the adjacent full gate pass;
     forbidden product-name audit is clean; the generic commit and dependency
     milestone are recorded before product integration.
4. **Product thin/Universal integration and closure**
   - Add product build/audit/acceptance targets, validate every declared
     resource and executable slice, exercise bounded product paths, update
     public/manual/generated evidence, and decide the parent state.
   - Completion: both thin bundles and the Universal bundle pass structural and
     runtime acceptance, the exact main gate passes, Intel-native and skipped
     duration-only scope are explicit, docs/matrix are reconciled, and the
     child and parent are committed complete.

Subtasks are strictly ordered. The signing/notarization roadmap item cannot
begin until all four children and this parent are complete.

## Inventory and decisions

### Current code and resource owners

| Bundle entry class | Current source owner | Universal rule |
| --- | --- | --- |
| `Contents/MacOS/<executable>` | generic AppKit/Dart AOT host | merge verified arm64 and x86_64 thin images |
| `Contents/Resources/application.aot` | product entrypoint compiled by generic runtime | merge verified AOT Mach-O snapshots |
| `Contents/Helpers/*` | manifest-declared product Dart entrypoints | merge every exact matching helper name |
| Engine image | configured official Engine output | merge same basename and pinned SDK/Engine contract |
| native assets/capabilities | manifest-declared dependency build hooks | merge every declared matching library |
| App Intents image | manifest-declared dependency Swift source | merge matching library after per-thin metadata validation |
| `Info.plist` | generic runtime plus application manifest | require byte equality before final signing |
| localization `.lproj` files | product manifest resources | require byte equality and reviewed-source equality |
| terminfo and shell integration | product manifest resources | require byte equality and existing content/hash contracts |
| scripting dictionary | product manifest declaration | require byte equality and DTD-valid reviewed source |
| App Intents metadata | generic extraction from one manifest declaration | require exact inventory and byte equality between thin inputs |
| Dart SDK license | configured official Engine checkout | require byte equality |
| thin build manifest | generic runtime | validate each separately; replace with Universal evidence preserving both thin contracts |
| code signatures | generic local build/distribution step | never merge; rebuild nested then outer signature after final bytes |

### Selected architecture and publication contract

- `--target-architecture` is a generic explicit build input accepting only
  `arm64` or `x86_64`. Omission retains host-architecture behavior. A foreign
  target is allowed only for build-only Release AOT; Developer JIT and `--run`
  retain host execution semantics and reject it.
- The target selects Product Engine output, platform Kernel, AOT snapshotter,
  compiler target triple, helper/native-hook target, and all build evidence.
  The builder process itself remains the trusted installed host Dart process.
- Universal assembly consumes two already built Release AOT `.app` paths and a
  distinct bounded destination. Thin inputs and existing destination are
  immutable. Paths must be canonical local directories without overlap,
  symlink entries, traversal, or case-folded aliasing.
- Exact relative inventories are derived from both thin bundles. Known code
  positions are merged, `_CodeSignature` is ignored/recreated, the thin build
  manifest is validated/replaced, and every other regular file must have
  identical bytes. Unknown executable/Mach-O placement or an extra/missing
  entry is rejected rather than copied.
- The final evidence is ordered JSON with a trailing newline, format/version,
  `release-aot`, exact architectures `[arm64, x86_64]`, bundle identity,
  executable code paths, architecture-neutral resource paths/hashes, and
  cryptographic hashes of both validated thin manifests. Absolute input/output
  paths, timestamps, usernames, and signing identities are absent.
- Publication stages a unique sibling directory, verifies every merged image,
  updates permissions, ad-hoc signs nested code then the outer app, performs
  strict deep verification, flushes evidence/content as supported, and renames
  into place. A preexisting verified result is replaced only at the final
  publication boundary and remains intact on every earlier failure.

## Progress and findings

- 2026-09-13: after commit `8f9d70e` (`Verify diagnostics privacy across
  product runtimes`), reread ROADMAP from a clean worktree and identified this
  parent as the first incomplete item. Reconfirmed README's distribution goal,
  FEATURE_MATRIX `DIST-01`, Phase 1 stock-runtime migration guidance, current
  Make/runtime manifests, product audit, adjacent generic builder/tests, Engine
  outputs, and the existing arm64 Release AOT bundle.
- 2026-09-13: the current product bundle has seven executable Mach-O owners:
  host, AOT snapshot, worker helper, Engine, PTY asset, renderer and AppleScript
  capabilities, plus the linked App Intents image. Its reviewed resources
  include eight localized files, compiled terminfo, five shell-integration
  files plus contract, scripting dictionary, two App Intents metadata files,
  SDK license, plist, and build manifest. The existing audit verifies content
  and dependency paths but only requires that each image *contains* one
  requested architecture; a Universal exact-slice audit is still required.
- 2026-09-13: confirmed the official Engine checkout has Product ARM64/X64
  libraries, platform Kernel inputs, and snapshotters; the x86_64 snapshotter
  runs on the M1 host. The installed Dart CLI is arm64-only, ruling out an
  x86_64 relaunch design. Selected explicit cross-target propagation within the
  generic arm64 builder because it preserves the trusted SDK process and uses
  the supported `dart build cli --target-arch` hook path.
- 2026-09-13: considered product-owned assembly, merging only the launcher,
  copying one thin bundle's resources without comparison, and restoring the
  retired Phase 1 tooling. Product-owned assembly would violate the generic
  runtime boundary; launcher-only merge leaves six other code owners thin;
  blind resource selection hides drift; the retired implementation targets a
  superseded runtime. Selected a new bounded generic thin/Universal contract
  with product-injected manifest and product-owned acceptance.
- 2026-09-13: split this cross-repository parent into four ordered children
  before executable implementation. Developer ID/hardened/notarization remains
  the next roadmap item and is deliberately not pulled into the ad-hoc local
  signing boundary.
- 2026-09-13: the documentation-only contract changed no executable behavior.
  `git diff --check` passed, the adjacent generic worktree remained clean, and
  the complete code/resource inventory, risks, failure policy, acceptance
  matrix, and ordered ownership boundaries are now reproducible for the next
  child.
- 2026-09-13: implemented the generic target-architecture Release AOT path in
  adjacent `dart_macos_runtime`. `--target-architecture=arm64|x86_64` now
  selects the Product Engine output, platform Kernel, snapshotter, native host
  compiler architecture, helper/build-hook Dart target, App Intents target
  triple, and build-manifest architecture. Developer JIT rejects an explicit
  target and a foreign target rejects `--run`, retaining the builder's clear
  host-execution boundary.
- 2026-09-13: an arm64 Dart executable cannot emit a macOS x64 helper through
  `dart build cli`; it rejects `macos_x64` as an unsupported host platform.
  Selected the same-revision target Dart SDK from Engine `ReleaseX64` for
  foreign helper and build-hook compilation. The builder now validates exact
  SDK version/revision, the target executable's Mach-O architecture, and every
  VM/compiler/platform artifact used by `dart build cli` before starting work.
  A first broad `create_sdk` Ninja invocation included unrelated cross-platform
  outputs and was stopped; targeted SDK phony outputs supplied the bounded
  macOS SDK instead. Missing platform dill and `dartvm` artifacts had produced
  opaque front-end failures, motivating the explicit preflight allowlist.
- 2026-09-13: the first real x86_64 native compile exposed three Objective-C
  `BOOL` to C++ `bool` narrowing errors in generic accessibility preference
  snapshots. Explicit `!= NO` conversion fixes both architectures without
  changing API behavior. A later sandboxed x86_64 snapshot attempt failed at
  Dart's Rosetta CPU feature query because `machdep.cpu.*` sysctls were denied;
  the identical bounded build succeeded outside that sandbox. This is an
  execution-environment constraint, not a missing build input.
- 2026-09-13: final generic validation passed: formatter (no changes),
  `dart analyze`, all 14 `dart_macos_runtime` tests, `git diff --check`, the
  added-line forbidden-name audit, and exact adjacent
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`. The generic repository
  audit reported `GENERIC_REPOSITORY_AUDIT_PASS`; no product or `terminal`
  naming was added to the generic repository.
- 2026-09-13: the final generic code built the actual product manifest as an
  x86_64 thin Release AOT application outside the CPU-info-restricted sandbox.
  Product structural audit passed with one helper, one plain native asset, two
  native capabilities, one scripting definition, three App Intents entries,
  and eight localization files; strict deep ad-hoc signature verification also
  passed. Direct Rosetta execution exited zero and proved AppKit startup, one
  PTY, worker and native-capability loading, menu dispatch, diagnostics, and
  clean teardown. The existing product smoke expects 28 menu actions while the
  freshly built source correctly publishes 30 (the two divider-movement
  actions added earlier); updating that product-owned assertion remains in the
  ordered product integration child rather than this generic child.
- 2026-09-13: committed the adjacent generic implementation as `e22aec9`
  (`Add generic cross-architecture AOT builds`). Both the adjacent and main
  exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gates passed after the
  commit. The dependency milestone is therefore complete; no duration-only
  validation was needed or used as a blocker.
- 2026-09-13: after main milestone commit `67ce838`, reread ROADMAP with both
  worktrees clean. The first incomplete item is the generic atomic Universal
  assembler child. Reconfirmed that its scope is only two-thin validation,
  architecture-neutral equality, all-code merging, deterministic evidence,
  nested/outer ad-hoc signing, strict verification, and atomic last-good
  publication; product build targets and product assertions remain in the
  following child.
- 2026-09-13: implemented the adjacent generic Universal CLI with exactly two
  repeated thin inputs and one distinct `.app` output. It identifies slice
  roles from schema-1 Release AOT evidence rather than argument order, rejects
  input/output overlap and every symlink, compares exact case-fold-safe entry
  inventories, permissions, neutral file sizes and SHA-256 hashes, and rejects
  executable or Mach-O files outside the manifest-derived code inventory.
- 2026-09-13: the assembler validates each thin signature and exact single
  architecture, normalizes only the architecture-derived App Intents triple
  and code byte count when comparing application contracts, then merges every
  declared host, AOT payload, helper, Engine, asset, capability, and App
  Intents image. It revalidates exact `arm64 x86_64` slices and non-system
  dependency paths, writes path-free deterministic schema-2 evidence, signs
  all nested code before the outer app, verifies deeply and strictly, and uses
  same-directory staging plus a restoration backup for atomic last-good
  publication.
- 2026-09-13: added standalone fixture/fault coverage for both thin input
  orders, deterministic evidence, successful old-output replacement, distinct
  and non-overlapping paths, output symlinks, resource/plist/manifest drift,
  missing/extra entries, input symlinks, undeclared Mach-O, wrong thin/merged
  slices, invalid thin signatures, merge failure, absolute dependency, signing
  failure, and preservation of an existing output. Package analysis and all
  nine assembler test groups passed.
- 2026-09-13: bounded real-input validation built a fresh arm64 thin product
  after the sandboxed Metal compiler cache write was correctly retried outside
  the sandbox. The first real Universal attempt exposed that `otool -L` emits
  one absolute-path heading per architecture for a fat image; dependency
  parsing now considers only indented load-command rows, with a two-heading
  fixture regression. The corrected assembler merged and signed all eight
  real code entries successfully. Reversing thin input order and replacing the
  existing output reproduced the exact Universal manifest SHA-256
  `ed0e340e635fd152c3d6bee4001ab40677325625e89c0625bc7ddf4c0a533d9b`;
  strict signature/plist checks passed and no staging/backup directory remained.
- 2026-09-13: the adjacent exact full gate passed with
  `GENERIC_REPOSITORY_AUDIT_PASS` and no forbidden product/`terminal` name in
  any added line or new file. Committed the generic assembler as `f3e7715`
  (`Add atomic Universal application assembly`). The exact main
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate also passed against
  that committed dependency, completing the generic Universal milestone.
