# Architecture matrix and Universal release-AOT assembly

- Status: complete — Apple M1/arm64 baseline gates passed; Intel-native
  evidence is a post-goal follow-up
- Started: 2026-09-01
- Last validated: 2026-09-02
- Scope: second Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, `FEATURE_MATRIX.md` DIST-01,
  `docs/phase0/DT-012-build-ci-design.md`,
  `docs/phase1/debug-release-runtime-paths.md`, and ADR-001–004

## 2026-09-02 — runtime recipe/provenance variable audit reopening

A new independent review found one remaining P1 provenance boundary. GNU Make
command-line assignments can replace several runtime product recipe variables,
including repository source/header lists, tool scripts, the release host source,
message-pump inputs, and snapshotter runner. The compile or generation recipe
can then consume an attacker-selected source or tool while the fingerprint
continues to inventory the repository-owned default files, or records only a
runner command string. A successful bundle can therefore carry false or stale
provenance even though the existing output-path and compiler-flag protections
remain intact.

This task is reopened without changing the roadmap or creating a commit. Before
implementation, every Make variable consumed by the developer-JIT/release-AOT
product path will be classified as one of:

| Class | Contract | Planned treatment |
| --- | --- | --- |
| User-configurable semantic input | An intentional product choice whose exact effective value must be bound to the build | Validate its allowed domain and record canonical value, relevant content hash, version, and arguments in the fingerprint |
| Repository-owned/internal input | Source/header/tool/plist/patch/path list or derived output owned by this repository/build contract | Make command-line replacement impossible with `override` or remove the indirection |
| External executable/tool input | Executable outside the repository that actually runs a build step | Record and validate canonical executable identity, content hash/version, and fixed arguments, and ensure the recipe uses that same identity |

The audit must cover all recipe prerequisites and command expansions, not only
the examples in the review. In particular, the release host source and every
bridge/runner/message-pump input must be repository-owned and fixed; the
snapshotter runner must be split into an executable plus arguments and bound by
identity/hash; and the Dart executable that launches fingerprint/manifest/audit
tools must match the configured SDK revision and be recorded rather than being
an ambient `dart` lookup. A table-driven hostile-override regression will cover
the complete internal-variable inventory, prove substitute paths never appear
in dry-run or real build execution, keep sentinels unchanged, and verify the
resulting fingerprints/artifacts. Runner replacement at a stable path must
either change the fingerprint or be rejected. Focused checks, source/freshness/
negative suites, the full matrix, Phase 0, slice/signature/generation inspection,
and diff hygiene are all required again on the final tree.

### Variable inventory and classification decision

The complete runtime Make section and every prerequisite/recipe expansion were
audited before implementation. Phase 0-only variables are outside this product
path except where they are shared by runtime recipes.

| Class | Variables / families | Binding decision |
| --- | --- | --- |
| Intentional user configuration | `MACOSX_DEPLOYMENT_TARGET`, `DART_APPKIT_ROOT`, `DART_ENGINE_ROOT`, `DART_EXECUTABLE` as the default-SDK selector, `DART_SDK_ROOT`, `CLANGXX`, `SDKROOT`, exact-validated `NATIVE_FLAGS`, `RUNTIME_BUILD_DIR`, `RUNTIME_ARCH`, `RUNTIME_PACKAGE_CONFIG`, `RUNTIME_EXTRA_BUILD_INPUT`, `RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE`, `RUNTIME_ARGUMENTS`, and the `INTEL_*` handoff values | Preserve configuration only where the existing domain/content/containment validation or the new executable identity record binds the value. `RUNTIME_ARGUMENTS` affects launching only; `INTEL_*` is validated by the no-rebuild handoff and does not build a product. |
| Repository-owned or derived internal | `SHELL`, recursive `MAKE`, `PROJECT_ROOT`, `HOST_ARCH`, derived SDK version/revision/hash, Engine Ninja/GN and patch paths, `RUNTIME_DEFAULT_PACKAGE_CONFIG`, every `RUNTIME_DART_SOURCES`, bridge, JIT runner, message-pump, tool-script, plist, release-host, and support-source variable, bundle version, native flag fragments, architecture-to-Engine/runner-argument mappings, all Engine output/input paths, the derived runtime Dart executable, every thin/universal bundle/intermediate/stamp/receipt path, and the four fixed thin handoff paths used by assembly | Convert to `override` assignments so command-line input cannot replace a recipe source, tool, list, mapping, shell, recursive verifier, or derived output independently of its validated root. |
| Executed external tool/input | Runtime Dart executable; Clang and SDK; fixed `/usr/bin/python3` interpreter plus Engine GN script; bundled Ninja; fixed recursive Make; Engine library, Kernel compiler, platform dill, AOT snapshotter; release snapshotter runner executable and arguments | Recipe and fingerprint receive the same explicit path. Record canonical path, SHA-256, version where meaningful, architecture where applicable, and the exact fixed invocation arguments in the lane/common evidence. Existing Engine/repository/GN configuration records remain in force. |

Ambient `dart` was removed from all runtime targets. The runtime executable is
an override-proof `DART_SDK_ROOT/bin/dart` derivation. A shell-only preflight
checks its executable/version contract before any Dart validator can run, and
the fingerprint independently checks that same filesystem identity against
its current process and SDK version/revision. It is then reused for manifest,
audit, assembly, smoke, freshness, negative, and Intel-handoff tools. Engine
Ninja remains fixed below the selected Engine root but gains hash/version/target
arguments in provenance. The GN script gains hash and mode/architecture
arguments, and is explicitly interpreted by fixed `/usr/bin/python3`, whose
hash/version/architecture and complete invocation are also lane evidence. The
snapshotter runner option accepts only a filesystem alias of `/usr/bin/arch`;
its architecture argument is internal, and both executable hash and argument
are lane evidence. A stable-path substitute is rejected both before and after
its contents change.

### Findings, failures, and focused verification

- A systematic expansion audit found that `MAKE` itself was command-line
  replaceable. `MAKE=/usr/bin/true runtime-matrix-verify` returned zero while
  skipping every recursive gate. `SHELL` had the equivalent recipe execution
  boundary. Both are now fixed with GNU Make `override`; the fixture checks all
  87 internal variables in Make's resolved database, not merely the variables
  reached by one target.
- The first Dart design still accepted `DART_EXECUTABLE=/usr/bin/true`. Because
  the proposed identity check lived inside the selected Dart process, `true`
  could skip that check and every Dart-based gate. The rejected design was
  self-authenticating. The selected SDK root is now the only SDK location
  choice, its `bin/dart` path is internally derived, and the non-Dart preflight
  prevents this circular bypass. A real developer/release build with hostile
  `DART_EXECUTABLE=/usr/bin/true` still used the selected SDK Dart and matched a
  forced canonical rebuild byte-for-byte for all five produced binaries.
- Directly executing Engine `gn.py` would have left its `#!/usr/bin/env
  python3` interpreter outside provenance. Runtime recipes now invoke the fixed
  `/usr/bin/python3` path explicitly; Python, GN script, Ninja, runtime Dart,
  recursive Make, and release `/usr/bin/arch` form six verified tool evidence
  roles (the JIT lane omits only the release runner).
- The first focused analysis reported `No issues found` but then attempted to
  update a telemetry session file outside the sandbox and emitted a permission
  exception. No project file was affected. Repeating with `CI=true` disabled
  telemetry and completed cleanly with `No issues found`.
- The focused freshness gate completed with exit zero. It proved all 87 hostile
  internal assignments inert in the resolved Make database, found zero hostile
  paths in canonical dry-run recipes, preserved the bundle/receipt/file
  sentinels, verified identical real products, rejected the Dart `true` bypass,
  accepted one real `/usr/bin/arch` alias, rejected two contents at one stable
  fake-runner path without changing nine existing artifacts, and verified all
  six evidence roles. The prior space-containing toolchain (nine outputs), 28
  external flag rejections with zero stale reuse, effective/package input
  regeneration (nine each), stable no-op (nine), and forged/missing package
  failures also passed.
- The first focused negative run reached valid schema-v5 thin and Universal
  assembly, then failed because four older wrapper fixtures still expected a
  command-line `UNIVERSAL_RELEASE_BUILD_DIR` override to reach the assembler.
  That expectation contradicts the newly selected internal-variable contract.
  The wrapper cases now require the override to be ignored while preserving
  thin inputs, and direct assembler cases retain the canonical, containment,
  case-folding, and Unicode alias rejection coverage. A subsequent sandboxed
  direct rerun passed those revised cases through immutable-receipt checks, then
  stopped only when its nested Make attempted to rewrite the adjacent Engine
  `ProductX64/args.gn` outside the workspace sandbox. No artifact policy failed;
  the same suite must be rerun with normal Engine build access.
- The first normal-access rerun then failed at the immutable-receipt boundary:
  the saved thin receipts correctly described the prior source inventory, while
  the runtime recipe/provenance edits had changed that inventory. Reusing those
  receipts would have accepted a stale baseline, so the failure was expected
  and no receipt was overwritten. Both thin release lanes and the Universal
  publication were rebuilt and freshly audited on the final source inventory.
- The dedicated negative suite then completed with exit zero. Every hostile
  Make override remained inert, direct path/identity/containment checks passed,
  and the suite covered malformed FAT data, strict dependency/entitlement/
  signature policy, immutable receipts, competing publishers, staging-entry
  replacement, sync failures, and pre/post-publication crash injection. It
  ended with `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`; the full matrix still needs
  to repeat this result on the same tree.
- The exact-tree `make runtime-matrix-verify` gate completed with exit zero.
  Source format/lint/analyze/unit checks passed; the full freshness suite
  repeated all 87 internal-override, six tool-identity, spaced-path, 28
  external-input, effective-input, package-config, and forged/missing package
  cases. All four thin lanes built and audited, Universal publication and its
  complete negative suite passed, and native arm64 plus Rosetta x86_64 smokes
  passed for the thin and Universal products. The published generation is
  `8551975ead0b1a348e5c6a7f22bea9b6378a5a5be8a235d03888224e96c74654`.
  The gate ended honestly with `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED`; Phase 0
  and final independent artifact checks remain before local findings close.
- The exact-tree `make phase0-verify` regression gate also completed with exit
  zero. Format, analysis, unit, developer launch, AOT, worker, PTY, Metal,
  CoreText, IME, grid/parser/benchmark, and all six arm64 bundle audits passed.
  The worker measured 2940.43 MiB/s with `resignaled=2` and
  `max_turn_us=203`, satisfying the existing scheduler/time-budget gate. No
  Phase 0 regression was observed; independent final artifact/diff inspection
  remains.
- Independent artifact inspection found five arm64-only and five x86_64-only
  thin Mach-O products. The Universal launcher, Engine, and AOT snapshot each
  report exactly `x86_64 arm64`. Strict individual signature verification
  passed for all three nested Mach-O files, deep strict verification passed for
  the outer app, and its plist lint passed. All five saved audit receipts are
  schema-v3 PASS reports with the expected mode/architecture, and every lane
  records the fixed Dart, Engine GN/Ninja/Python, and Make identities; release
  lanes additionally record the snapshotter runner.
- The assembly report, saved Universal audit receipt, and embedded manifest all
  agree on publication generation
  `8551975ead0b1a348e5c6a7f22bea9b6378a5a5be8a235d03888224e96c74654`.
  The Universal parent contains only the persistent publisher lock and the
  current release generation.
- The first per-file whitespace loop used `path` as its zsh loop variable. In
  zsh that special array also controls `PATH`, so the loop temporarily made
  `rg` unreachable and produced no useful check result. No file was modified.
  Repeating with a neutral variable and an absolute `rg` path produced no
  whitespace diagnostics for any untracked task file; tracked
  `git diff --check` also exited zero.

### Final independent-review findings and selected correction

The independent post-gate review found three related P1 provenance holes, so
the preceding green gates do not yet close the local implementation:

1. `DART_SDK_ROOT` remained command-line selectable, and the non-Dart
   preflight compared that root's `version` file only with the `--version`
   claim from that same root's `bin/dart`. A fabricated SDK root can therefore
   provide matching text and a Dart-shaped executable that returns success
   without running any fingerprint, manifest, audit, freshness, negative, or
   handoff script. The in-script process-identity check is unreachable in that
   attack. The selected correction is a command-line-immutable bootstrap Dart
   resolved before the runtime contract, used for every runtime Dart tool.
   `DART_SDK_ROOT` may name only the same SDK/tool identity (including a genuine
   filesystem alias); an unrelated or self-authenticating root is rejected by
   the shell preflight and again by the real fingerprint process.
2. Schema-v5 `build_tools` validation checked shape, hash syntax, and parts of
   each argument list but did not bind the Dart/GN/Ninja records to the lane's
   resolved project/SDK/Engine roots. In particular, Dart used `endsWith`, GN
   and Python could name different scripts, Ninja could live elsewhere, and
   its `-C` path only needed a matching path segment. The build environment
   also accepted extra/missing resolved-path keys. The selected correction is
   to validate the exact resolved-path schema first, then require canonical
   equality for Dart=`SDK/bin/dart`, its fingerprint script under the project,
   GN=`Engine/tools/gn.py`, Python argument zero=that GN path,
   Ninja=`Engine/buildtools/ninja/ninja`, and Ninja `-C`=the exact Engine output
   directory for the lane.
3. The source inventory generator records every runtime policy/generator tool,
   but the saved-manifest validator's required source-role list did not require
   all of them. A forged manifest could omit the fingerprint, manifest,
   freshness, or negative-test roles and still receive a new audit receipt.
   The exact tool source-role set will be required, with a manifest-mutation
   fixture covering both path coherence and omitted required roles.

These are one trust-chain correction, not separate roadmap subtasks. Focused
format/analyze, hostile SDK and manifest-mutation fixtures, full freshness and
negative suites, the complete matrix, Phase 0, artifact inspection, and diff
hygiene must be rerun on the corrected tree. The roadmap and commit remain
untouched.

The trusted-bootstrap boundary is the Dart executable selected by the ambient
`PATH` before GNU Make evaluates the runtime contract. `DART_EXECUTABLE` cannot
replace it on the Make command line, and every runtime Dart invocation uses its
resolved filesystem identity. Selecting another installed SDK therefore means
selecting that SDK in the invoking environment before starting Make;
`DART_SDK_ROOT` is only an explicit root/alias consistency input, not a second
executable trust root. A caller who controls the entire process environment and
the executable found on its ambient `PATH` already controls the build process;
that is the outer build-host trust boundary, not a provenance claim this
repository can authenticate. Inside that boundary, the selected executable's
path, content hash, version, revision, architecture, and invocation arguments
remain recorded and cross-checked against the SDK root and manifest lane.

The first focused format invocation accidentally included `Makefile` in the
Dart formatter argument list. Dart correctly rejected that non-Dart input,
while still formatting the four Dart files; no Make content was modified. The
focused format command is rerun below with Dart sources only, and Make syntax is
checked through its database/source gates.

The corrected focused format checked four Dart files with zero changes, and
focused plus whole-project analysis reported no issues. The source gate's
Objective-C++ format, plist lint, and unit tests passed. An explicit
`DART_EXECUTABLE=/usr/bin/true` invocation still ran the fixed trusted
bootstrap. The expanded freshness suite then completed with exit zero: all 88
internal variables ignored hostile command-line replacements, a genuine SDK
alias was accepted, the self-authenticating fake SDK was rejected without
executing its marker or changing existing artifacts, six tool evidence roles
were verified, and the prior spaced-path, 28 external-input, effective-input,
package-config, forged-root, and missing-override cases all passed.

The expanded release negative suite was then rerun from freshly rebuilt arm64
and x86_64 release lanes and completed with exit zero and
`RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`. In addition to the existing alias,
containment, Mach-O, signing, and publication-fault cases, it accepted a
semantically identical relocated-root fixture and rejected all nine hostile
cross-field mutations: an extra resolved-path role, mismatched Dart executable,
Dart script, GN script, Python/GN argument, Ninja executable, Ninja output
directory, Engine input, and package root. Removing each required runtime tool
source role in turn was also rejected. Concurrent publisher, replacement,
sync-failure, pre-publication crash, and publication-window crash cases all
retained a complete last-good or competing generation rather than deleting an
unverified directory. The full matrix still has to repeat these results on the
same final tree.

The final exact-tree `make runtime-matrix-verify` completed with exit zero.
Source formatting, lint, analysis, and unit tests passed; the complete
freshness suite repeated all 88 internal-override and tool/input identity
checks; all four architecture/mode thin lanes built and audited; and the
expanded negative suite ended with `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`.
Native arm64 and Rosetta x86_64 smoke tests passed for their thin products, and
both explicit launch architectures passed against the Universal release-AOT
bundle. The published generation is
`79785dd33321066b9f1f43c44586fd85ab6afd3dd0362ea0ae38d9779765e20d`.
The gate ended with the required
`RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED: no Intel-native handoff was run`;
Phase 0 and independent artifact inspection remain before local closure.

The final `make phase0-verify` regression gate then completed with exit zero.
Formatting, analysis, unit tests, developer launch, basic AOT, worker, PTY,
Metal, CoreText, IME, grid/parser/benchmark, and the six-bundle arm64 audit all
passed. The worker observation reported 2923.58 MiB/s, `resignaled=0`, and
`max_turn_us=216`; no completed Phase 0 behavior regressed. Independent
artifact, signature, generation, repository, and diff inspection remains.

Independent inspection then confirmed five arm64-only and five x86_64-only
thin Mach-O products, exact `x86_64 arm64` slices in all three Universal Mach-O
files, strict individual signatures for those three files, a deep strict outer
app signature, and a valid plist. All five saved audit receipts are schema-v3
PASS records with the expected mode/slices. The assembly report, its nested
result, saved Universal receipt, its nested manifest, and embedded manifest all
carry generation
`79785dd33321066b9f1f43c44586fd85ab6afd3dd0362ea0ae38d9779765e20d`.
The Universal parent contains only its cooperative lock and current release
directory. Tracked and untracked whitespace checks passed; `ROADMAP.md` has no
diff, AppKit is clean, and Engine has only the expected worker patch.

A final independent provenance rereview confirmed that the trusted-Dart,
cross-field root/tool coherence, and shared required-source inventory findings
are closed. It then found one narrower schema-v5 P2: build-tool architecture
lists require only non-empty strings, while the host Clang architecture field
requires only a non-empty list. A re-signed manifest can therefore claim a
forged architecture or even a non-string Clang entry while every path/hash/arg
relationship remains valid. This does not bypass the exact product slice
audit, but it falsifies tool provenance and must be fixed before local closure.
The selected correction is one exact architecture-list validator shared by all
tool and host-tool records: non-empty, strings only, no duplicates, and only
the Mach-O names this contract can legitimately record (`arm64`, `arm64e`, and
`x86_64`). The negative fixture will mutate every architecture-bearing tool
role plus Clang to forged, non-string, and duplicate values. Because the shared
support and negative-test sources are inventoried, focused and complete gates
must be rerun afterward.

The common validator now covers every architecture-bearing schema-v5 list:
five executable tool roles, three Engine input-binary roles, host Clang, and
the Universal top-level architecture set. It permits only `arm64`, `arm64e`,
and `x86_64`, requires a non-empty unique list, and requires the same sorted
canonical order emitted by `runtimeArchitectures`. The table-driven negative
fixture mutates every role with an unknown value and exercises null,
duplicate, and reversed-order values in every schema category. Focused Dart
formatting changed the two edited sources as expected; focused analysis then
reported `No issues found`.

The focused `make runtime-release-negative-tests` run rebuilt and audited both
thin release lanes, republished the Universal artifact on the new source
inventory, and completed with exit zero and
`RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`. All 22 new architecture-metadata cases
were rejected at the intended validator: unknown values in every tool/input/
host/Universal role, plus null, duplicate, and noncanonical-order values in
each schema category. Every pre-existing provenance, Mach-O, signature,
publisher-race, sync-failure, and crash-injection case also remained green.

## 2026-09-02 — post-gate SDK path invocation reopening

A final read-only review found no remaining P1 safety or provenance defect,
but found one P2 mismatch between the documented input contract and the actual
compiler invocation. The fingerprint correctly compares the complete native
flag string and therefore accepts an identity-valid SDK path containing spaces,
such as an Xcode installation named `Xcode Beta.app`. The runtime compile
recipes still expand the shared `NATIVE_FLAGS` unquoted, however, so the shell
splits that SDK path and the build fails safely. It cannot publish stale output
or delete data, but the task must not claim local completion while its accepted
configuration cannot build. The same quoting boundary applies to the selected
Clang executable when the Xcode application path itself contains spaces.

The selected correction is to separate the runtime warning/language flags from
the path-bearing SDK option. Runtime host recipes will invoke the selected
compiler as one quoted path and pass `-isysroot` plus the SDK path as an
explicitly quoted argument pair, while the fingerprint receives both tool paths
as single option values and keeps the same canonical semantic flag sequence.
Phase 0's existing flags remain unchanged. The freshness fixture will build the
runtime through temporary compiler and SDK symlinks below an `Xcode Beta.app`
pathname and require all nine developer/release derived outputs. Focused checks,
the full matrix, Phase 0, artifact inspection, and diff hygiene are required
again before the status can return to Intel-only blocked.

The first focused freshness run reached the fingerprint with both quoted paths,
but failed before the build. GNU Make automatically exports command-line
variables to recipes, so the fixture's `SDKROOT=<spaced alias>` leaked into
`/usr/bin/git`; Apple's developer-tool shim then tried to locate Git through
that synthetic SDK and failed. This was an environment-coupling failure, not a
compiler quoting failure, and it published no fixture artifact. `SDKROOT` and
`CLANGXX` are explicit recipe arguments rather than supported ambient child
environment, so the Makefile will `unexport` both. This also prevents a caller's
tool selection from silently changing unrelated subprocess lookup while the
explicit fingerprint and compiler arguments retain the selected identities.

After `unexport`, focused formatting reported zero changed files and focused
analysis reported `No issues found`. The dedicated freshness rerun completed
with exit status zero: all 22 hostile derived-path overrides remained inert,
the real developer/release build through space-containing compiler and SDK
aliases produced all nine expected outputs, all 28 external-input forms were
rejected without stale reuse, effective-input and package-config changes each
regenerated nine outputs, the no-op run kept nine stable, and forged/missing
package configurations were rejected. The complete matrix and Phase 0 gates
remain required on this exact tree.

The exact-tree `make runtime-matrix-verify` rerun then completed with exit
status zero. Source checks, the expanded freshness suite including the
space-containing toolchain build, all four thin build/audit lanes, Universal
assembly/audit, every alias/provenance/Mach-O/signature/publication negative
case, native arm64 smoke, and Rosetta x86_64 thin/Universal smoke passed. It
ended with the required honest
`RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED: no Intel-native handoff was run`.
Phase 0 and independent artifact inspection were next rerun before closing the
local finding, as recorded below.

The final `make phase0-verify` rerun completed with exit status zero. Format,
analysis, unit tests, developer launch, AOT, worker throughput with
`resignaled=0`, PTY, Metal, CoreText, IME, grid/parser/performance gates, and
the six-bundle arm64 audit all passed. Independent artifact inspection then
confirmed five exact arm64-only and five exact x86_64-only thin Mach-O products,
plus exact `x86_64 arm64` slices in the Universal launcher, Engine, and AOT
snapshot. Strict individual verification passed for all three nested Universal
Mach-O signatures, and deep strict verification passed for the outer app. The
assembly report, runtime audit receipt, and embedded manifest all record
publication generation
`8d5150e61f8dda51c6cadf90a74d2d5b2ed1614e0dc9c06a89884fe6c6ec0afe`;
the Universal parent contains only its persistent publisher lock and current
release generation. The SDK/compiler path finding is closed. The unavailable
Intel-native handoff remains the sole blocker. Final `git diff --check` passed,
and per-file no-index whitespace checks produced no diagnostics for every
untracked task file.
The reviewer that identified the space-path issue rechecked the final Make
expansion, fingerprint arguments, real fixture, and diff, confirmed the P2 is
closed, and reported no new finding.

## 2026-09-02 — final cleanup and input-policy self-review reopening

An independent read-only review after the preceding green gates found four
additional P1 boundary failures. Those pass records remain useful execution
history but no longer accept the current task. The roadmap item remains
unchecked and no commit or later lifecycle work is authorized until these
findings and every local gate are closed again.

1. The compiler-input parser is still a denylist. Relative forwarding forms
   such as `-Wp,-include,forced-header.h`, `-Wa,-I,relative-dir`,
   `-Xassembler=-Irelative-dir`, `--config=relative.cfg`, and
   `-fprofile-sample-use=relative.prof` contain no slash or response marker and
   can evade that list while causing Clang to read un-inventoried files. The
   selected correction is an exact product-native flag sequence: only the
   repository's warning/language/ARC/deployment/blocks/visibility flags and
   the exact selected SDK identity in the separate `-isysroot` pair are
   accepted. Kernel and snapshot flag sequences are likewise mode-specific
   exact semantic inputs. Relative forwarding/config/profile fixtures must
   fail before writing any fingerprint or derived artifact, both before and
   after input-content mutation.
2. The assembler creates a predictable staging pathname with non-exclusive
   `Directory.create()` and records cleanup permission only as a boolean. A
   precreated directory can therefore be adopted, or a safe staging pathname
   can be replaced before `finally`, after which recursive cleanup can delete
   an unverified generation. Staging will instead use an exclusively created
   sibling temporary directory, capture its device/inode immediately, and
   carry an explicit safe-cleanup identity. Immediately before recursive
   deletion, the current leaf must still be a real directory with exactly that
   identity; otherwise it is retained and reported, never deleted.
3. Publication snapshots compare followed target identities but do not always
   require a real directory leaf and exact canonical entry. During the test
   barrier, a writer can move the owned staging directory and replace its old
   pathname with a symlink to that directory. The target inode still matches,
   so the current code can publish the symlink and clean the displaced output.
   Every capture, install, displacement, rollback, and cleanup observation
   must require the expected requested/canonical pathname, a directory leaf,
   and the exact device/inode identity. A barrier fixture will replace the
   staging entry with a symlink and prove publication fails without damaging
   either generation.
4. The sync-failure rollback for a previously absent destination snapshots
   the published output and then uses one-way exclusive rename back to the
   private staging name. A non-cooperating writer can replace the public entry
   in that window, causing an unknown generation to be moved away and leaving
   the public path empty before the identity mismatch is noticed. Rollback
   must never one-way move an unknown public entry. A private swap slot was
   considered, but restoring filesystem absence would still require a
   pathname-based removal window. The safer selected behavior is no rollback
   in this branch: the fully staged complete pair, or a competing public
   generation that replaced it, remains untouched and the command fails with
   an explicit durability error. A deterministic sync-failure competition
   fixture will prove that the competing generation remains published and no
   unknown directory is cleaned.

These changes form one publication/provenance correction rather than
independently shippable roadmap subtasks. Focused format/analyze, expanded
freshness and publication-negative fixtures, the complete matrix, Phase 0,
independent artifact inspection, and diff hygiene are all required again.

### 2026-09-02 — final self-review implementation log

- Native, Kernel, and snapshot effective flags now use mode-specific exact
  product token sequences. The native sequence permits one path-bearing pair
  only: separate `-isysroot` followed by a directory with the selected SDK's
  filesystem identity, normalized to the semantic SDK placeholder. Relative
  preprocessor/assembler forwarding, Clang config, sample profile, absolute
  forced-header, and response-file forms can no longer reach a fingerprint.
- The freshness fixture now hashes all nine fingerprint/host/Kernel/snapshot/
  manifest outputs, rejects five relative forwarding/config/profile forms in
  addition to the earlier absolute header/response cases before and after
  their external contents change, and requires every existing hash to remain
  unchanged.
- Universal staging now uses the parent's exclusive random `createTemp`
  primitive and captures the new real-directory identity immediately. Capture,
  pre-publication readiness, installed output, displaced output, and rollback
  observations require exact canonical entry, real directory leaf, and
  device/inode identity where the state is owned. Cleanup is permitted only
  for an explicitly tracked safe identity and rechecks that exact real entry
  immediately before recursive removal; ambiguous or replaced entries are
  retained with a diagnostic.
- A previously absent output is no longer moved back after a post-publication
  sync error. The complete pair or competing public directory remains in
  place, while an existing-output rollback still requires exact owned-new and
  captured-old directory identities before and after its atomic swap. New
  barriers expose the staging pathname and post-publication window only to
  deterministic tests. Fixtures replace staging with both a foreign directory
  and a symlink, and replace a newly published output immediately before an
  injected sync failure.
- Focused `dart --suppress-analytics format` formatted the four edited tools,
  and focused static analysis reported `No issues found`. Dedicated freshness
  and publication-negative suites run next; all earlier full-gate records are
  superseded until they and the complete gates pass on this tree.
- The expanded `make runtime-build-freshness-test` completed with exit status
  zero. It again proved eight hostile Make path overrides harmless; rejected
  all 28 absolute header/response and relative forwarding/config/profile
  mode/content combinations with `stale_artifacts_reused=0`; regenerated all
  nine outputs for each effective-input and package-config change; kept nine
  stable on the no-op run; and rejected forged package roots and a missing
  explicit package-config override. The long quiet interval was expected work:
  every rejected form traverses both public build modes and their Engine
  configuration prerequisite before failing at the fingerprint boundary.
- The first expanded release-negative rerun passed every case through common
  provenance mismatch, then failed the positive relocated-root fixture before
  publication with `Universal artifact directory changed before publication
  capture`. The output was under macOS's `/var` temporary spelling; the guard
  had correctly canonicalized it to `/private/var`, but the new missing-entry
  helper compared the original requested spelling as well as the canonical
  path. This was an over-strict alias comparison, not an artifact mutation.
  Missing entries will compare canonical path/type/absence only; existing
  staging/output entries continue to require their exact canonical requested
  pathname, real leaf, and filesystem identity. The failed run published no
  relocated output.
- After that correction, focused format/analyze passed and the complete
  `make runtime-release-negative-tests` rerun finished with exit status zero.
  In addition to all earlier alias, containment, handoff identity, provenance,
  Mach-O policy, signature/entitlement, malformed FAT, immutable-receipt,
  replacement, publisher-lock, and SIGKILL cases, it passed foreign-directory
  and symlink staging replacement, new-output sync failure with both an
  untouched complete pair and a competing pair, existing-output sync rollback,
  existing sync competition with all three generations retained, and cleanup
  replacement retention. The run ended with
  `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`; the real Universal parent contained
  only its persistent lock and current published generation afterward.
- A post-pass test review expanded the hostile Make invocation from the eight
  directly destructive build/bundle/stamp/receipt variables to all 22 thin
  derived output variables. It also removed whitespace tokenization from the
  native flag check: the complete expected product string is compared before
  substituting the SDK placeholder, so an Xcode/SDK path containing spaces is
  accepted when it is the already toolchain-validated selected SDK. Focused
  format/analyze remains clean after both refinements; the full matrix supplies
  their exact-tree freshness rerun.
- The formal concurrent-publisher contract is the nonblocking advisory lock;
  every repository-owned publisher must hold it from staging through cleanup.
  The identity state machine additionally detects and preserves the single
  non-cooperating mutations exercised at each deterministic boundary. macOS
  pathname rename APIs do not provide an expected-inode compare-and-swap, so a
  continuously malicious same-UID process that deliberately rewrites an entry
  in the instruction window immediately after every check is outside this
  cooperative publisher contract. Ambiguous observed states are never selected
  for cleanup. This boundary is explicit rather than claiming that advisory
  locking is a security sandbox against arbitrary same-user processes.
- The final-tree `make runtime-matrix-verify` completed with exit status zero.
  Its source gate passed format, Objective-C++ format, plist lint, repository-
  wide analysis, and unit tests. Its freshness gate proved all 22 hostile Make
  derived-output overrides harmless, rejected 28 external compiler-input
  variants without reusing a stale artifact, regenerated all nine dependent
  outputs for both effective-input and package-config changes, kept all nine
  stable on a no-op run, and rejected forged or missing package configuration.
  All four arm64/x86_64 developer-JIT/release-AOT thin builds and audits passed;
  the expanded release-negative suite ended in
  `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`; native arm64 and Rosetta x86_64 smoke
  passed for both thin modes; and arm64 plus Rosetta x86_64 smoke passed for the
  Universal release bundle. The gate truthfully ended with
  `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED`, so Intel-native evidence remains a
  completion blocker despite the successful local matrix.
- The final-tree `make phase0-verify` completed with exit status zero. Format,
  analysis, unit tests, developer launch, AOT, worker-isolate throughput, PTY,
  Metal, CoreText, IME, grid/parser benchmarks, the performance baseline, and
  the six-bundle arm64 audit all passed.
- Independent inspection after both gates found exact arm64-only slices in all
  five arm64 release/developer Mach-O products, exact x86_64-only slices in all
  five x86_64 products, and exact `x86_64 arm64` slices in the Universal
  launcher, Engine, and AOT snapshot. Strict individual signature verification
  passed for those three Universal Mach-O files, and deep strict verification
  passed for the outer app. The assembly report, published runtime audit
  receipt, and embedded manifest all record the same publication generation
  `fb781c99a7d5a0b8e670ef0fa70d1934142a424931bdcd63183b37e0cbab72bf`.
  The Universal parent contains only its persistent publisher lock and current
  release generation.
- Final `git diff --check` passed, and per-file `git diff --no-index --check`
  produced no whitespace diagnostics for every untracked task file. The
  roadmap remains intentionally unchanged, and the implementation/docs diff is
  preserved without a commit because the required Intel-native audit and smoke
  evidence cannot be produced on this arm64 host or substituted by Rosetta.

## 2026-09-02 — deletion, publication-race, and compiler-input reopening

The locally complete result was reopened by a further independent review. The
following three P1 findings are part of this same Universal matrix task and are
open until the implementation and every local gate have been rerun. The
roadmap item remains unchecked and no commit or later lifecycle task is
authorized.

1. Thin-bundle recipes delete their configured bundle and audit-receipt paths.
   GNU Make command-line variables override ordinary `:=` assignments, so a
   caller can currently redirect those deletions to a sentinel or another
   lane's receipt. `RUNTIME_BUILD_DIR` remains the intentional isolated build
   root override, while every developer-JIT and release-AOT path derived below
   it will become an `override` assignment that command-line input cannot
   replace. A public-Make-path regression must force both recipes and prove
   that bundle, receipt, and unrelated sentinel overrides remain byte-for-byte
   unchanged.
2. The assembler revalidates its output guard before expensive final input
   seal checks, leaving a publisher race before `RENAME_SWAP`; cleanup then
   assumes that the displaced directory is the generation it observed. The
   selected design is a filesystem-identity compare-and-swap protocol: finish
   all expensive checks first, revalidate and capture the destination identity
   immediately before rename, then require the displaced directory to have
   exactly that captured device/inode identity. A mismatch is swapped back,
   synced, and rejected, and an unproven displaced directory is never cleaned.
   This also protects against non-cooperating writers, unlike an advisory lock
   alone. A deterministic barrier fixture must replace the destination after
   capture but before swap and prove the competing generation survives.
3. Compiler flag provenance normalizes absolute roots as raw substrings and
   does not inventory path-bearing flags such as `-I`, `-F`, response files,
   or `-include`. Flags will be tokenized. Only the selected SDK root supplied
   as the exact `-isysroot` value is a permitted path input; all other
   path-bearing and response-file forms fail before a fingerprint can bless or
   reuse derived artifacts. Freshness regressions must prove that external
   header and response-file inputs are rejected both before and after their
   contents change and that an existing host remains untouched.

These fixes are mutually part of the same publication/provenance boundary and
do not create independently shippable roadmap subtasks. After focused checks,
the dedicated negative and freshness suites, the full runtime matrix, Phase 0,
artifact generation/slice/signature inspection, and diff hygiene must all pass
again. Only then may the status become `blocked — local gates complete;
awaiting Intel-native evidence`.

### 2026-09-02 — focused-remediation log

- Thin developer-JIT and release-AOT build directories, intermediates,
  bundles, stamps, and audit reports are now `override` assignments strictly
  derived from the caller-selected `RUNTIME_BUILD_DIR` and `RUNTIME_ARCH`.
  The isolated root remains configurable; command-line variables can no
  longer redirect either recipe's invalidation commands to individual paths.
- The assembler now captures both destination and staging device/inode
  identities after final thin-seal and destination revalidation. After a swap,
  it compares the displaced and installed identities to that capture. A
  mismatch is swapped back and synced; cleanup remains disabled unless the
  staging path is proven to contain this process's own generation or a
  successfully published, captured old generation.
- Compiler flags are now parsed as tokens. The exact selected SDK directory is
  the sole path accepted through the separate `-isysroot` pair. Positional
  inputs, response files, include/framework/library/search paths, compiler or
  linker forwarding, and any other slash-bearing token fail before the
  effective fingerprint is written.
- The first focused format pass formatted the four edited Dart tools. Dart's
  post-command telemetry timestamp was denied outside the workspace, so the
  formatter reported exit 1 after completing the files; a later
  `--suppress-analytics` format gate is required. The first focused analyzer
  then found one source error in the new race fixture: generic syntax was
  applied to the `Future` class instead of the static `Future.any` method. No
  tests were run from that invalid state; the call is corrected next.
- The corrected focused format/analyze and `make runtime-source-check` passed,
  including 29 Dart files, Objective-C++ format, plist lint, repository-wide
  analysis, and unit tests. A dry Make database check also proved six hostile
  per-lane build/bundle/report overrides resolve under the selected isolated
  root rather than to caller paths.
- The first dedicated freshness run failed before compiling its isolated lane.
  The token policy correctly rejected positional input but also rejected the
  developer-JIT semantic snapshot marker `not-applicable`. That exact marker is
  not a compiler file input and is the existing truthful representation for a
  mode with no snapshotter; it will be explicitly allowed while every other
  positional token remains rejected. No freshness assertion ran in this failed
  attempt.
- After that correction, focused format/analyze passed. The next Make entry
  invocation did not reach the freshness program because the outer plain
  `dart run` tried to update its telemetry session timestamp outside the
  workspace and the sandbox denied it. This is an execution-environment
  failure rather than a product result; the same program is next exercised
  with Dart's supported `--suppress-analytics` switch, and the public Make gate
  must still be rerun in an environment permitted to maintain Dart's local
  telemetry state.
- The permitted direct freshness run passed every assertion: eight hostile
  Make internal-path overrides left the bundle sentinel, other-lane receipt,
  and file sentinel unchanged; an effective-input change and a package-config
  change each regenerated all nine derived artifacts; a stable rerun rewrote
  none; forged package roots and missing configs failed; and `-include` plus
  `@response` inputs were rejected before and after their contents changed in
  both modes while both existing host hashes stayed fixed.
- The first rebuilt dedicated release-negative suite passed all prior cases and
  the new capture-to-swap competing-generation fixture. During the following
  diff review, a stricter multi-writer interleaving was identified: without a
  cooperative lock, two sanctioned assemblers could both capture the same old
  generation, and a second external replacement between swap and rollback
  could make a blind swap-back later clean an unverified directory. The
  assembler therefore now also takes a nonblocking OS advisory file lock held
  through publication and cleanup (automatically released on process death),
  and verifies identities both before and after every rollback. A second
  assembler must fail on that lock inside the deterministic race fixture. An
  uncooperative mutation is still detected by the device/inode compare/swap;
  any ambiguous rollback retains staging rather than deleting it. Focused
  format/analyze and diff hygiene pass after this strengthening; the dedicated
  suite must be rerun because the assembler source identity changed.
- The exact-tree `make runtime-matrix-verify` rerun then completed with exit
  status zero. Its source gate passed format, Objective-C++ format, plist lint,
  whole-project analysis, and unit tests. Freshness again proved eight hostile
  internal-path overrides harmless, rejected eight external header/response
  configurations without changing either host, regenerated all nine derived
  outputs for each effective-input and package-config mutation, and kept all
  nine stable on a no-op rerun. The complete negative suite passed, including
  the advisory-lock rejection and capture-to-swap competing-generation
  preservation cases. Both architecture-specific developer-JIT/release-AOT
  lanes built and strictly audited; native arm64, Rosetta x86_64, and both
  Universal launch modes smoked successfully. The final line remained the
  truthful `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED`, so this local pass does not
  satisfy the still-required Intel hardware acceptance condition. Phase 0 is
  rerun next on this exact tree.
- The exact-tree `make phase0-verify` regression then completed with exit
  status zero. Format, whole-project analysis, unit tests, developer launch,
  basic and worker AOT, PTY, Metal, CoreText, IME, grid/parser/benchmark, and
  all six arm64 bundle audits passed. The worker observation reported
  `resignaled=0` and 2909.95 MiB/s; no Phase 0 regression remains on the
  available Apple M1 host.
- Independent post-gate inspection found every arm64 thin launcher/Engine/AOT
  Mach-O contains only `arm64` and every x86_64 thin equivalent contains only
  `x86_64`. The Universal launcher, Product Engine, and AOT snapshot each
  report exactly `x86_64 arm64`. Strict individual signature verification
  passed for those three Universal Mach-O files and deep strict verification
  passed for the outer app. The assembly report, its nested result, saved
  runtime-audit receipt, its nested manifest, and the embedded manifest agree
  on publication generation
  `05b1c534195832f1cd2ec597ebca929d7b133d02228c2575dff85725c975e4b6`.
  The Universal parent contains only the persistent cooperative lock and the
  single published `release-aot` generation; no staging directory remains.

## 2026-09-02 — final independent-review reopening

The preceding remediation passed every locally available gate, but a final
independent review found seven additional fail-closed gaps. They remain inside
this same first unchecked roadmap item. No VM/isolate lifecycle work, roadmap
completion, or task commit is authorized while they or the Intel-native gate
remain open.

Confirmed findings and required outcomes, in dependency order:

1. Existing inputs and outputs are compared mainly as canonical path strings.
   On a case-insensitive or normalization-insensitive macOS volume, spelling
   variants can identify the same object; hard-linked receipts can also alias
   with different paths. Validation must compare resolved targets and stable
   filesystem identity, cover all bundle/report input/output pairs, and repeat
   immediately before publication to close the mutable-path window.
2. The Make Universal wrapper creates its configured output directory before
   assembler validation. The wrapper must perform no write. The assembler must
   resolve the nearest existing ancestor of a not-yet-created destination,
   prove non-alias/non-containment first, and only then create staging parents.
3. Audit and Intel evidence destinations can be placed inside artifacts or
   receipts they attest. A shared, testable destination validator must reject
   existing and prospective containment/identity across every input and output
   before the first write, independent of the Intel hardware gate.
4. Publishing a bundle, assembly report, and later runtime audit receipt in
   separate renames is not a crash-consistent artifact/receipt transaction.
   Universal output must instead be a complete artifact directory containing
   the app plus both reports, prepared and synced in a sibling staging
   directory and published/swapped once. The public audit target must validate
   that immutable receipt rather than overwrite it. Fault injection must prove
   that no interruption before the single publish changes the last-good pair.
5. Intel handoff trusts the supplied smoke script by output substring. It must
   validate the smoke harness, handoff tool, and shared audit support against
   the exact source hashes bound into all three receipts, and record those
   identities in evidence. A fake harness must be rejected before execution.
6. Common provenance currently contains checkout/build/tool absolute paths,
   preventing semantically identical lanes from independent hosts from
   matching. Common comparison must retain revisions, versions, hashes, flags,
   and semantic configuration while moving raw/resolved paths to lane-local
   diagnostics. Fixtures must accept relocated equivalent roots and still
   reject every substantive mismatch.
7. Kernel compilation directly consumes `.dart_tool/package_config.json`, but
   it is absent from the effective input inventory. Its exact bytes and parsed
   generator/language/package mapping must be fingerprinted. Package roots must
   resolve only to the recorded SDK, AppKit, project, or explicitly accepted
   dependency roots. Content changes must invalidate all derived artifacts,
   and a forged root must fail closed.

### Remediation sizing and order

This remains one inseparable release transaction rather than shippable
subtasks: package/source identity produces truthful lane manifests and
receipts; cross-host normalization permits the two lanes to meet; identity and
destination checks protect those inputs; and one atomic artifact-directory
publish makes the checked bundle/receipt set durable. Completing only one layer
would leave the same Universal output unsafe. No roadmap subitems are added.

Implementation order is: shared filesystem identity/destination primitives;
single-directory Universal publication and validation-only Make audit entry;
audit/handoff destination guards; handoff source identity; normalized common
provenance and package-config validation; focused negative/freshness tests;
then the complete matrix and Phase 0 gates. Each discovery, failed trial, and
verification result is recorded below before moving to the next layer.

Local remediation is complete only when case, Unicode where the active volume
aliases it, hard-link, wrapper pre-write, report/evidence containment,
publication interruption, fake harness, relocated-root, substantive mismatch,
package-config freshness, and forged-root regressions pass alongside all prior
negative cases. The roadmap item nevertheless remains incomplete until the
same no-rebuild Intel-native evidence required by DT-012 is obtained.

### 2026-09-02 — final-review implementation findings

- The selected Xcode `clang++` is a thin arm64 host executable, not a
  cross-host-stable binary. ProductARM64 and ProductX64 bootstrap Kernel
  compilers are also arm64 host tools, while `gen_snapshot` and the Engine
  library follow the target architecture. Raw compiler/tool hashes therefore
  moved to lane-local build evidence. Common provenance retains Xcode/SDK
  versions, SDK settings hash, compiler version/driver, normalized invocations,
  and repository/source identities. Engine and snapshotter still require the
  exact target slice; a host compiler is not incorrectly required to match it.
- AOT intermediate Kernel files contain checkout-local `file:` URIs even with
  `--no-embed-sources`. Their raw hashes remain lane evidence rather than a
  cross-host equality condition. The architecture-neutral platform dill is
  currently byte-identical and is the explicit common binary invariant.
- Package configuration is parsed before recording a fingerprint. Schema 2,
  `pub`, exact SDK generator version, the exact two-package set, language
  version, `lib/` package URI, and canonical project/AppKit root roles are
  required. Raw config bytes, resolved roots, and `pubCache` remain lane-local;
  a path-independent parsed package graph is common. AppKit's package
  `pubspec.yaml` is now part of the source inventory.
- Universal publication is being raised from three independent output writes
  to one directory containing fixed `DartTerminal.app`,
  `assembly-report.json`, and `universal-audit.json`. The complete directory is
  synced before one exclusive rename or directory swap and synced again before
  success. Both reports and the signed manifest share a generation digest.
- A shared nearest-existing-ancestor guard records canonical target and
  filesystem device/inode identity, detects containment through ancestor
  identities, rejects symbolic-link leaves, and is re-evaluated before write or
  publish. This deliberately lets the volume decide case and Unicode aliasing
  instead of applying an incorrect unconditional lowercase/normalization rule.
- The first attempt to replace the assembler publication block as one large
  patch failed because an exact context line had already changed. `apply_patch`
  made no partial edit. The change was reapplied in small reviewed sections to
  avoid losing or duplicating the existing entitlement/resource checks.
- Focused formatting changed six files as expected. Focused static analysis
  initially found three implementation errors: a static call to the instance
  `resolveSymbolicLinks` API and a nullable list promotion at the Mach-O role
  validator. Both were corrected. The next analysis reported `No issues
  found`; its process exit was nevertheless 1 because the sandbox blocked a
  post-analysis Dart telemetry timestamp outside the workspace. A final
  permitted exit-status run remains required after the test migration.

## 2026-09-01 — review reopening and remediation plan

The first implementation passed its local gates but an independent review
found release-contract gaps that must be fixed before Intel hardware is the
only blocker. The task remains the same unchecked roadmap item; no later Phase
1 work is authorized.

Confirmed gaps, in implementation order:

1. Build-derived host, Kernel, and snapshot files can remain stale while a
   forced manifest claims a newer Engine/GN/toolchain/source context. A
   deterministic effective-input fingerprint must invalidate every derived
   artifact, and a regression must prove invalidation.
2. The public Universal Make wrapper deletes its configured output before the
   assembler can canonicalize it. Output validation, staging, replacement,
   rollback, and cleanup must be owned by the assembler; a wrapper-level alias
   fixture must prove thin inputs cannot be deleted.
3. Mach-O policy currently inspects only launcher dependencies and permits any
   `@`-relative entry. Launcher, Engine, and AOT snapshot dependencies,
   install IDs, and `LC_RPATH` commands must use role-specific exact
   allowlists for every slice.
4. Provenance lacks architecture, effective overrides, actual build-tool/input
   hashes, and reproducible dirty-tree identity. The manifest and assembler
   comparison must bind these to each lane without letting architecture hide
   any other mismatch.
5. Thin audit JSON is not persisted or digest-bound to immutable artifacts,
   and there is no no-rebuild Intel-native audit/smoke entry point for
   transferred artifacts. Both handoff and evidence output are required.
6. Actual malformed/extra fat-slice handling, dependency policy, entitlements,
   nested signatures, wrapper aliasing, and stale rebuild behavior need
   negative coverage. If duplicate CPU slices cannot be emitted by supported
   Apple tools, that limitation and a direct parser regression must replace an
   impossible end-to-end fixture.
7. Existing-output publication must be atomic and preserve the last valid
   Universal artifact on every pre-publication failure.

The final P2 review also requires thin entitlement equality plus an explicit
allowlist before merge, and individual strict/ad-hoc verification of launcher,
Engine, AOT snapshot, and outer app after signing.

### Updated provenance decision

Architecture is recorded directly in each thin manifest, not only in audit
JSON. Investigation proved that removing only the top-level architecture is
insufficient: ProductARM64 and ProductX64 necessarily use different GN
architecture fields and have different Engine/compiler/snapshotter binary
hashes. Manifest schema v3 therefore has two explicit parts:

- common provenance must compare exactly across lanes. It contains runtime
  mode/configuration, SDK/Engine/AppKit and source tree identities, normalized
  non-architecture GN configuration, toolchain, bundle/deployment settings,
  effective overrides, and the complete relevant source/recipe inventory;
- `architecture_inputs` must identify the corresponding `arm64` or `x86_64`
  lane and records exact architecture GN values, resolved build-input paths,
  actual Engine/compiler/platform/snapshotter hashes, runner selection,
  fingerprint hash, intermediate Kernel hash, and pre-sign product hashes.

The assembler normalizes only the documented top-level `architecture` and
whole `architecture_inputs` sections, compares the remaining common
provenance exactly, and separately validates each lane against its expected
architecture and role schema. The Universal manifest embeds the common record
plus both complete thin lane records. This is the final formal provenance
choice and replaces both the byte-identical-manifest design and the interim
"remove architecture only" proposal.

Saved audit JSON is the separate signed-artifact handoff receipt. It binds the
manifest digest, policy version, exact slices, role metadata, canonical bundle
seal, and digest including signatures. The assembler accepts both thin bundle
and receipt paths, resolves them canonically, recomputes the full audit/seal,
and rejects stale, altered, aliased, or mismatched pairs. Pre-sign hashes in
the manifest describe build inputs/products; they cannot be compared as raw
bytes to launcher/Engine files after code signing changes those bytes. The
receipt binds the exact signed bytes. Thus neither an unsigned report nor an
unverifiable manifest alone is treated as complete provenance.

### Sizing re-evaluation

The remediation remains one task. The findings are one fail-closed chain:
fingerprints create truthful manifests and immutable thin receipts; receipts
feed the assembler; the stricter Mach-O/entitlement/signature policy applies
both before and after merge; atomic publication depends on all preceding gates.
No intermediate subset is safe to ship or mark complete. The ordered units
above will nevertheless be validated separately before the full matrix and
Phase 0 gates. The roadmap parent stays unchecked throughout because Intel
native evidence and the final completion commit remain unavailable.

## Purpose

Turn the current host-only runtime build into an architecture-explicit
`arm64`/`x86_64` matrix and assemble a release-AOT Universal application only
from two independently audited thin applications. The result must fail closed
when a slice, provenance field, configuration value, or non-Mach resource does
not match.

## Background

The first Phase 1 item separated developer JIT and release AOT into distinct
products but derives every architecture and Engine path from `uname -m`.
Consequently an Apple Silicon host can currently build only the arm64-named
product path, and no repository-owned Universal assembler exists. Phase 0's
DT-012 design already forbids calling a host-only bundle Universal, changing a
signed thin input in place, or merging artifacts whose revisions, settings,
and non-Mach assets have not been compared.

## Scope

- Make runtime architecture an explicit validated input, independent of host
  architecture, for `arm64` and `x86_64` thin products.
- Select the matching Product/Release Engine outputs and compile native hosts
  and Dart AOT snapshots for the requested target architecture.
- Keep developer-JIT and release-AOT payload, Engine, metadata, output, audit,
  and run contracts mechanically separate.
- Emit deterministic provenance for each thin product and compare the two
  release-AOT inputs before assembly.
- Compare bundle layout and every non-Mach file byte-for-byte, merge only the
  architecture-bearing executable, Product AOT Engine, and AOT snapshot in a
  fresh staging tree, remove inherited signatures, and sign the staged result
  only after assembly.
- Audit the Universal bundle for the exact architecture set
  `{arm64, x86_64}`, bundle-relative dependencies, release-only assets,
  provenance, resource equality, and a fresh valid signature.
- Add automated positive and fail-closed negative coverage for matrix
  selection, provenance mismatch, missing/extra slices, and resource drift.
- Document what native Apple Silicon and Intel hardware prove, and what
  cross-compilation and Rosetta do not prove.

## Out of scope

- The following Phase 1 VM/isolate error, uncaught-exception, and shutdown
  contract item.
- Developer ID signing, hardened runtime, notarization, stapling, update
  metadata, and other Phase 11 distribution work.
- A Universal developer-JIT product; developer JIT remains a thin,
  architecture-specific development artifact.
- Changing terminal semantics, AppKit ownership, worker-isolate lifecycle, or
  renderer/PTY contracts.
- Treating Rosetta or an emulated guest as Intel hardware evidence.

## Dependencies and initial confirmed facts

- The worktree was clean on `main` at task start, with HEAD
  `3f392fa Separate developer JIT and release AOT paths`.
- The first unchecked roadmap item is the architecture matrix and Universal
  Binary assembly. No later Phase 1 item is in scope.
- The host is arm64 Darwin (`RELEASE_ARM64_T8103`), macOS 26.6.2 build 25G83,
  with Xcode 26.6 and macOS SDK 26.5.
- Dart is 3.13.2 stable revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` and the adjacent
  `dart_appkit` checkout is clean at
  `5613950f15cf9837e5a025a9943c5b8010be4218`.
- The adjacent Engine checkout is at the same Dart revision with the reviewed
  worker-isolate modification in `runtime/engine/engine.cc`.
- Only `ProductARM64` and `ReleaseARM64` outputs existed at investigation
  start. No ProductX64/ReleaseX64 output was present.
- Rosetta is installed: `arch -x86_64 /usr/bin/uname -m` returned `x86_64`.
  This permits an additional compatibility launch but is not an Intel-native
  hardware gate.
- The installed Dart compiler's help exposes `--target-os` and
  `--target-arch` vocabulary, but the real x86_64 invocation later proved that
  this SDK does not support macOS cross-target AOT through the `dart` CLI.
  Dart Engine's own `gn.py` does recognize both architectures on an arm64 Mac
  and names their outputs `ProductARM64`/`ProductX64` and
  `ReleaseARM64`/`ReleaseX64`.
- Approximately 82 GiB was free before producing x86_64 Engine outputs.

## Task sizing decision

This remains one roadmap task rather than being subdivided. Architecture
selection, provenance, thin audit, assembly, exact-slice audit, and negative
tests form one fail-closed release contract: none is independently shippable,
and splitting them would temporarily create a path that could emit an
unverified or falsely labelled Universal artifact. The implementation stays
within build orchestration, release tooling, tests, and this task memo.

## Completion criteria

1. Both target architectures can be selected explicitly; unsupported or
   omitted architecture inputs cannot silently fall back to the host.
2. Thin developer-JIT and release-AOT builds select the matching Engine,
   native compiler architecture, and payload architecture and pass their
   existing mode-separation audits.
3. Thin release-AOT evidence records architecture in both manifest and audit.
   Manifest common provenance records source, SDK/Engine/AppKit tree identity,
   worker patch, Xcode/SDK/compiler, deployment, mode, bundle contract,
   effective configuration, and recipe/source hashes; lane provenance records
   architecture GN values plus actual Engine/compiler/platform/snapshotter and
   product hashes. The assembler compares common provenance exactly and only
   normalizes the documented architecture-specific sections.
4. Universal assembly accepts only matching independently audited arm64 and
   x86_64 release-AOT bundles, operates in a fresh staging/output location,
   never changes a thin input, and produces exactly the three expected Mach-O
   files with exact slices `{arm64, x86_64}`.
5. Non-Mach layout/assets are identical before merge; mismatched revision,
   configuration, resource bytes, missing/extra Mach files, missing slices,
   duplicate slices, or unexpected assets fail before output publication.
6. Thin entitlements are empty and equal before merge. Nested code and the
   outer app are freshly ad-hoc signed after merge; launcher, Engine, AOT
   snapshot, and outer app each pass individual strict signature checks, and
   every expected Mach-O slice passes exact dependency/install-name/RPATH,
   layout, payload-mode, provenance, and slice audits.
7. Format, analysis, unit tests, both architecture thin build/audit lanes,
   provenance/resource comparison, Universal assembly/audit, fail-closed
   negative tests, available native/Rosetta smokes, and existing runtime and
   Phase 0 regressions pass.
8. DT-012's native-hardware distinction is preserved: Apple Silicon proves the
   arm64 lane, Intel hardware proves the x86_64 lane, and Rosetta is recorded
   only as supplementary evidence. If the required Intel-native evidence is
   unavailable, that is a blocker rather than grounds to weaken the gate.

## Validation plan

- Run Dart formatting without mutation, static analysis, and unit tests.
- Build and audit thin developer-JIT and release-AOT products for `arm64` and
  `x86_64` using explicit architecture arguments.
- Inspect every host, Engine, and snapshot with `file`/`lipo`; inspect dynamic
  dependencies and install names with `otool`; verify plist and signatures.
- Compare provenance and non-Mach assets, assemble Universal release AOT in a
  new staging directory, and rerun the complete exact-slice/dependency/signing
  audit.
- Run negative fixtures for unsupported/omitted architecture selection,
  fingerprint staleness, stale receipts, revision/configuration/lane mismatch,
  resource drift, dependency/RPATH/install-name drift, entitlement/signature
  violations, malformed/extra/duplicate slices, input/output/report aliasing,
  and failed replacement preservation.
- Run arm64 products natively and x86_64 products/Universal application under
  Rosetta on this host. Record Intel-native execution separately if such a
  host is actually available.
- Run `runtime-verify`, appropriate matrix verification, and `phase0-verify`,
  then review unstaged/staged diffs and generated artifacts.

## Investigation log

### 2026-09-01 — repository, roadmap, and architecture review

- Read `AGENTS.md`, `README.md`, all of `ROADMAP.md`, all of
  `FEATURE_MATRIX.md`, all four ADRs, DT-012, and the preceding Phase 1 task
  memo in full.
- Inspected the repository inventory, full Makefile, runtime host, bundle
  audit/integration tools, product Dart code/tests, and both runtime plists.
- Read the adjacent `dart_appkit` README, architecture, Engine build contract,
  Makefile, and Runner contract. Its host-default Makefile maps arm64 to
  `ReleaseARM64` and Intel to `ReleaseX64`; this task must not reuse that
  host-default selection for an explicit cross-architecture lane.
- Confirmed that the existing product Makefile uses one global `HOST_ARCH` for
  Engine paths, compiler output, audit expectation, and build directory. A
  target architecture must therefore be threaded through all of those points
  rather than changed only at the final `lipo` step.

## Decisions, failures, and validation results

### 2026-09-01 — initial formatter sandbox failure

- The first formatter invocation formatted the five new/changed release-tool
  Dart files, then Dart attempted to update its telemetry-session timestamp
  outside the writable workspace. The sandbox rejected that unrelated update,
  so the command returned failure after formatting completed.
- This is the same environment-only failure recorded by the preceding Phase 1
  task. No source was lost. Formatting and all subsequent Dart gates must be
  rerun with the normal tool runtime permissions; the failed exit is not
  accepted as validation evidence.

### 2026-09-01 — first analyzer correction

- The first analyzer run reached the new sources and reported two diagnostics
  at one expression: the negative-test harness called `isAbsolute` as though
  it were a static `FileSystemEntity` member. Replaced it with the `File`
  instance property. This was a source error, not a suppressed warning; the
  analyzer must pass on the corrected tree before any build is accepted.

### 2026-09-01 — first manifest-generation correction

- The first real manifest-generation attempt rejected the valid Engine
  worker-only modification. The generator trims command output, while its
  expected porcelain-status string still contained Git's leading status
  column space. Corrected the comparison to the trimmed form
  `M runtime/engine/engine.cc`; the reverse patch check remains the
  authoritative content check and was not weakened.

### 2026-09-01 — explicit matrix interface and x86_64 Engine toolchain

- Selected `RUNTIME_ARCH=arm64|x86_64` as the only thin-runtime build
  interface. The existing developer-JIT, release-AOT, audit, integration, and
  verification target names remain available, but they now fail with status
  64 when the variable is omitted or unsupported. No target substitutes
  `uname -m`, so an omitted value cannot create a host-only artifact under a
  matrix or Universal label.
- Each lane has a separate `build/runtime/<architecture>/<mode>` output and
  selects `ProductARM64`/`ReleaseARM64` with `clang_arm64_shared`, or
  `ProductX64`/`ReleaseX64` with `clang_x64_shared`. Native launchers are
  compiled with the matching explicit `clang -arch` value. Release snapshots
  use the matching Product platform dill and target-native Product
  `gen_snapshot`, launched through explicit `arch -arm64|-x86_64`; no Dart CLI
  macOS cross-target path or host-architecture fallback remains.
- Generated the missing ProductX64 and ReleaseX64 Engine configurations from
  the pinned local Engine checkout and built `dart_engine_aot_shared` and
  `dart_engine_jit_shared` without network access. The resulting Engine
  libraries are thin x86_64 Mach-O files. `bootstrap_gen_kernel.exe` is a
  host-executed arm64 build tool, while its selected
  `clang_x64_shared/vm_platform.dill` input defines the x86_64 target Kernel;
  this host/target split is intentional and will be checked by the real thin
  build and runtime smoke.
- The ProductX64 build completed 1,062 Ninja actions and the ReleaseX64 build
  completed 1,194. These build counts describe this checkout only and are not
  release acceptance evidence by themselves.

### 2026-09-01 — source gate after matrix implementation

- `make runtime-source-check` passed on the changed tree: Dart formatter
  checked 26 files with zero changes, clang-format accepted the release host,
  both plists passed `plutil`, static analysis reported no issues, and
  `test/run_tests.dart` passed.
- The first arm64 matrix build/audit run also completed for developer-JIT and
  release-AOT. Both audits found the expected single arm64 slice, the correct
  mode-specific Engine and payload, bundle-relative Engine dependency, valid
  strict ad-hoc signatures, and a valid deterministic build manifest. These
  results will be rerun as part of the complete matrix gate after Universal
  tooling is exercised.

### 2026-09-01 — first x86_64 thin-build correction required

- The explicit x86_64 developer-JIT bundle built and passed the complete thin
  audit, including exact x86_64 launcher/Engine slices. The host arm64 Kernel
  compiler successfully produced the target Kernel against
  `clang_x64_shared/vm_platform.dill`, confirming the intended host/target
  tool split for JIT.
- The first x86_64 release-AOT attempt correctly produced an x86_64 native
  host but failed before bundle publication when the installed Dart CLI
  rejected `dart compile aot-snapshot --target-os=macos --target-arch=x64` as
  an unsupported cross target (exit 128; only Linux cross targets were listed
  by this SDK command). The earlier help output showed the option vocabulary,
  not actual macOS cross-target availability, so it was insufficient evidence.
  No fallback to an arm64 snapshot is permitted. The pinned Engine's native
  `gen_snapshot` and cross-architecture snapshot build products must be
  inspected and the release recipe corrected to use the supported
  revision-matched toolchain.

### 2026-09-01 — revision-matched macOS AOT pipeline correction

- The pinned Product Engine configurations expose the supported lower-level
  macOS AOT pipeline: a host-executed `bootstrap_gen_kernel.exe`, the
  architecture-specific Product platform dill, and a target-native
  `gen_snapshot` producing `app-aot-macho-dylib`. The runtime recipe now builds
  and checks those tools from the same Engine revision/configuration, generates
  a product AOT Kernel, and runs the target snapshotter explicitly through
  `/usr/bin/arch -arm64|-x86_64`. It no longer asks the installed Dart CLI for
  an unsupported macOS cross target.
- Built ProductX64 `gen_snapshot`, `bootstrap_gen_kernel.exe`, and
  `clang_x64_shared/vm_platform.dill` locally (1,149 additional Ninja actions).
  The snapshotter reports Dart 3.13.2 on `macos_x64`; the bootstrap compiler is
  host arm64 and the snapshotter is x86_64, which is the Engine-supported
  cross-build division on this Apple Silicon machine.
- The first sandboxed Rosetta snapshotter probe aborted in
  `cpuinfo_macos.cc` because the sandbox denied the process's `sysctl` CPU
  query. Repeating the exact invocation with the normal build permissions
  succeeded; no Engine source or CPU-detection bypass was introduced. The
  output was a thin x86_64 Mach-O dylib with macOS build metadata.
- With the corrected recipe, the x86_64 release-AOT host, Product Engine, and
  AOT snapshot all have the exact x86_64 slice. Bundle layout, mode separation,
  dependency/install-name policy, deterministic manifest, and strict ad-hoc
  signature all passed the thin audit.

### 2026-09-01 — first Universal staging-name correction

- Before assembly, both thin inputs independently passed again and their
  deterministic provenance manifests were byte-identical. The first assembler
  run copied into fresh hidden staging and then failed closed before merge
  because the temporary directory suffix no longer ended in `.app`, while the
  shared bundle auditor intentionally accepts only app bundles. No output was
  published and the staging directory was removed by the failure cleanup.
- Changed only the hidden staging name shape so it remains unique and ends in
  `.app`; the final output and both signed thin inputs remain untouched.

### 2026-09-01 — fat-binary dependency parser correction

- The second assembler run compared provenance/layout/non-Mach bytes, merged
  all three expected files, verified their exact slices, and freshly signed
  nested code and the app. Its final staging audit then failed closed because
  `otool -L` prints one image-header line per architecture for a fat Mach-O;
  the thin-only parser skipped only the first header and treated the second as
  an absolute dependency. Again, no final output was published and staging was
  cleaned.
- The dependency parser now recognizes only the exact inspected-image header
  forms emitted by `otool` (thin and architecture-labelled fat forms). It does
  not broaden the allowed dependency policy: every remaining entry must still
  be `@`-relative or an approved system absolute path.

### 2026-09-01 — Universal assembly and exact-slice audit pass

- The corrected assembler independently re-audited both thin inputs, compared
  their complete deterministic manifest, identical file layout, and every
  non-Mach byte outside signatures. It copied the arm64 app into a fresh hidden
  `.app` staging tree, removed the inherited signature, and merged only the
  launcher, Product AOT Engine, and AOT snapshot.
- Each staged Mach-O was checked immediately after `lipo` for exactly
  `{arm64, x86_64}`. The assembler then signed the snapshot, Engine, launcher,
  and outer app in nesting order, passed the complete shared staging audit,
  and atomically renamed staging to the final output. Neither thin input was
  modified in place.
- `make universal-release-aot-audit` passed. The published bundle's three and
  only three Mach-O files each contain the exact arm64/x86_64 slice set;
  release-only layout, Product Engine dependency, build provenance, deployment
  target, and strict/deep ad-hoc signature checks all passed.

### 2026-09-01 — fail-closed negative suite pass

- `make runtime-release-negative-tests` initially passed all ten cases. It
  confirmed omitted and unsupported `RUNTIME_ARCH` values fail, duplicate
  expected slices are rejected, output/input aliasing is rejected, and an
  x86_64 lane with the slice removed cannot assemble. Source-revision and
  Engine-configuration manifest mismatches fail, non-Mach resource drift
  fails, an unexpected Mach-O fails, and a thin bundle cannot pass as
  Universal.
- The suite also re-audited the accepted Universal control and compared hashes
  plus strict signatures of accepted thin inputs before and after every
  mutation. All mutations occurred only in a temporary directory, all expected
  commands failed without publishing an output, and both signed thin inputs
  remained unchanged.

### 2026-09-01 — architecture-explicit smoke formatting correction

- Extended the existing smoke harness with an optional explicit launch
  architecture so matrix tests can prove which thin or Universal slice was
  selected. Two `--output=none --set-exit-if-changed` probes reported that the
  new code needed normalization; `--output=none` deliberately does not write,
  so the repeated result was expected but not a pass. Ran the writing formatter
  once, then the no-output check passed with zero changes. No smoke result was
  accepted before that final pass.

### 2026-09-01 — Apple Silicon native and Rosetta smoke pass

- The smoke harness now launches through `/usr/bin/arch` when the build target
  supplies an architecture, so a Universal launch proves the requested slice
  instead of merely accepting the host default.
- `make runtime-matrix-integration` passed developer-JIT and release-AOT thin
  launches for arm64 natively, then passed both x86_64 thin launches under
  Rosetta. Each app attached to AppKit's main thread, scheduled its automated
  close, exited within the timeout, wrote no unexpected stderr, and reported a
  clean shutdown.
- `make universal-release-aot-integration` passed the same release-AOT smoke
  first with the Universal arm64 slice explicitly selected and then with the
  x86_64 slice explicitly selected under Rosetta. These x86_64 results are
  supplementary compatibility/cross-build evidence only, not Intel-native
  hardware evidence.

### 2026-09-01 — final fail-closed hardening before regression gates

- Preserved the raw `lipo -archs` list and made exact-set comparison reject
  duplicate values on either side instead of normalizing duplicates away.
  The CLI duplicate-expectation fixture and actual artifact validation now
  enforce the same rule.
- The deterministic manifest now requires the installed Dart SDK and checked
  out Engine revisions to be identical and records stable Xcode version/build,
  macOS SDK version, and Apple Clang version. The shared auditor requires those
  fields, verifies SDK/Engine revision equality, and cross-checks the manifest
  SDK version/revision against `Info.plist`.
- Manifest generation is intentionally forced for every thin build request.
  Git HEAD, Engine/AppKit revisions, toolchain identity, or worktree state can
  change without updating a source-file timestamp, so a cached manifest would
  otherwise be capable of describing an earlier build context.
- Universal output resolution now canonicalizes its already-existing parent
  directory before input-alias/containment checks. A symlinked parent cannot
  hide publication inside either signed thin input; an eleventh negative case
  exercises that exact alias shape.
- The negative harness now seals every file, directory, mode, size, and link in
  accepted thin inputs, rather than a selected file list, and checks that every
  intentionally failed assembly leaves its proposed output unpublished.

### 2026-09-01 — final matrix and regression verification

- `make runtime-matrix-verify` passed on the final tree. Its source gate found
  26 Dart files already formatted, accepted the native clang format and both
  plists, reported no analyzer issues, and passed `test/run_tests.dart`.
- The gate regenerated and independently audited arm64 and x86_64
  developer-JIT and release-AOT thin bundles. Every expected host, matching
  Release/Product Engine, and AOT snapshot had exactly one requested slice;
  layout, runtime-mode separation, SDK/plist/manifest agreement, normalized GN
  settings, dependencies, and strict/deep ad-hoc signatures passed.
- Both release thin manifests were byte-identical after their architecture
  fields in `args.gn` were validated and excluded from the normalized settings.
  The common manifest records Dart SDK/Engine revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`, `dart_appkit` revision
  `5613950f15cf9837e5a025a9943c5b8010be4218`, worker patch hash, all normalized
  Product GN arguments, Xcode 26.6 build 17F113, macOS SDK 26.5, Apple Clang
  21.0.0, deployment target 14.0, bundle contract, source revision, and
  relevant input hashes.
- Fresh Universal assembly and the independent audit passed. Direct `file` and
  `lipo -archs` checks found exactly `x86_64 arm64` on the launcher,
  `libdart_engine_aot_shared.dylib`, and `application.aot`; no other Mach-O was
  accepted. Direct `cmp` confirmed the two thin manifests are identical.
  `otool -L` showed the Engine only as
  `@rpath/libdart_engine_aot_shared.dylib` and all other dependencies under
  approved system locations. Direct `codesign --verify --deep --strict` and
  `plutil -lint` passed.
- All eleven negative cases passed: omitted and unsupported architecture,
  duplicate expected slice, direct output/input alias, output alias hidden by a
  symlinked parent, missing x86_64 slice, source revision mismatch, Engine
  configuration mismatch, resource drift, unexpected Mach-O, and thin claimed
  as Universal. Every assembly failure left the proposed output absent, and a
  full bundle seal plus strict signatures proved both accepted thin inputs were
  unchanged.
- Final smoke timings were arm64 thin developer JIT 2,052 ms, arm64 thin
  release AOT 1,608 ms, x86_64 thin developer JIT under Rosetta 4,387 ms,
  x86_64 thin release AOT under Rosetta 2,668 ms, Universal explicit arm64
  1,677 ms, and Universal explicit x86_64 under Rosetta 2,315 ms. Every process
  attached to AppKit's main thread, auto-closed, produced no unexpected stderr,
  and shut down cleanly.
- `make phase0-verify` passed on the final Makefile. The historical debug/JIT,
  AOT, worker throughput, PTY, Metal, CoreText, IME, packed-grid, parser
  corpus, performance baseline, PTY child-symbol audit, and all six arm64
  bundle audits passed. This task introduced no Phase 0 regression.
- `git diff --check` passed. The main worktree contains only this task's
  implementation/docs changes; generated `build/` artifacts remain ignored.
  The adjacent `dart_appkit` checkout remains clean. The Engine checkout still
  contains exactly the expected tracked worker change
  `M runtime/engine/engine.cc`, whose content is verified by reverse-applying
  the repository patch during manifest generation.

The preceding "final" results describe the first implementation before the
independent review at the top of this memo. They remain useful investigation
history but are superseded as acceptance evidence by the remediation results
below.

### 2026-09-01 — review remediation implementation

- Every JIT and AOT Engine target now converges the explicit GN configuration
  and completes Ninja before reevaluating a content-addressed lane
  fingerprint. The fingerprint is written only when its content changes and
  is a normal prerequisite of the native host, Kernel, snapshot, and manifest.
  It includes actual Engine/tool binary hashes, GN common/lane settings,
  toolchain, effective flags/paths/override, source and recipe hashes, and
  HEAD/dirty identities for all three repositories. A forced manifest can no
  longer claim new inputs while older derived artifacts remain cached.
- The first real v3 thin audit exposed an important signing boundary: launcher
  and Engine hashes recorded before signing differ from their bytes after
  bundle signing. Comparing those fields directly made a truthful bundle fail.
  Manifest validation now checks the pre-sign role schema and internal
  fingerprint consistency, while the saved audit receipt binds the exact
  signed role hashes and complete canonical bundle seal. The distinction is
  explicit rather than weakening either record.
- Thin audit reports are atomically saved next to each architecture/mode
  artifact. Receipt validation requires a pass report, performs a fresh audit,
  and compares every recorded result field except the transfer-dependent
  absolute bundle path. The complete signed seal/digest must match.
- Mach-O policy is now role- and slice-specific. `otool -arch ... -l` is parsed
  for every launcher, Engine, and AOT snapshot slice; dependency command kinds,
  exact dependency/install-name sets, and exact `LC_RPATH` sets are allowlisted.
  Arbitrary `@...`, absolute external paths, weak/re-export commands, and a
  substring Engine-name match are no longer accepted.
- Entitlement extraction is performed for every thin role/slice and outer app.
  The current explicit allowlist is empty. Both thin lanes must have the same
  role set and empty entitlements before merge. After assembly, launcher,
  Engine, AOT snapshot, and outer app are individually verified as strict
  ad-hoc signatures; the outer app also receives deep strict verification.
- The Make Universal wrapper no longer deletes output or redirects the report.
  The assembler resolves output and receipt paths canonically, rejects bundle
  alias/containment and output-report/thin-receipt aliasing before writes, and
  revalidates both immutable input pairs. It merges in a fresh sibling `.app`,
  signs and audits there, then publishes by same-volume rename or
  `renamex_np(RENAME_SWAP)`. A report-publication error rolls the bundle back;
  no non-atomic fallback is allowed. Old output cleanup happens only after a
  successful publish.
- `intel-native-runtime-verify` has no build prerequisites. It consumes
  transferred x86_64 JIT/AOT thin bundles, the Universal bundle, and their
  saved audit receipts. Before audit or smoke it rejects non-x86_64,
  `sysctl.proc_translated=1`, or `hw.optional.arm64=1`; on genuine Intel it
  records a supplied hardware label, model/CPU/OS identity, receipt hashes,
  fresh audits, and three direct native smokes to an immutable evidence JSON.
  The local matrix gate reports this evidence as unverified rather than
  silently treating Rosetta as completion.

### 2026-09-01 — remediation validation and corrected failures

- Formatting completed for all nine release tools. Static analysis reported
  `No issues found` with exit 0. Sandboxed invocations first finished their
  actual format/analysis work but then could not update Dart's telemetry
  session timestamp outside the workspace; the same commands were rerun with
  normal tool permissions for reliable successful exit status.
- `make runtime-build-freshness-test` passed with
  `regenerated=9 stable_noop=9`. Changing a synthetic effective input changed
  both lane fingerprints and regenerated JIT host/Kernel/manifest plus AOT
  host/Kernel/snapshot/manifest. Repeating with identical content changed none
  of those mtimes.
- The first expanded negative run passed every case through actual arm64e
  extra-slice rejection, then stopped because the malformed duplicate FAT
  fixture was rejected as a missing expected Mach-O in the strict layout gate,
  while the test expected the lower-level text `lipo failed`. The artifact was
  fail-closed; only the over-specific expectation was wrong. It now expects
  the actual strict layout boundary.
- The corrected run passed omitted/unsupported architecture, duplicate CLI
  and direct exact-set parser, Make wrapper bundle alias, stale receipt,
  common provenance/configuration drift, unexpected Mach-O, launcher
  dependency/RPATH, AOT install-name, forbidden entitlement, missing nested
  signature, actual arm64e extra slice, malformed duplicate FAT header, thin
  claimed Universal, pre-publication last-good preservation, and successful
  existing-output atomic replacement. It ended with
  `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`.
- A final manual review then found two additional fail-closed opportunities:
  an output report could alias a thin receipt, and decoded lane GN/input roles
  were shape-checked but not matched exactly to the claimed architecture.
  Canonical receipt-alias rejection, exact lane GN/role/path/hash validation,
  and corresponding wrapper/lane-mismatch negative fixtures were added. These
  last changes require the final dedicated and full gates recorded below.
- The documented `make intel-native-runtime-verify` target was invoked on this
  Apple Silicon host as a negative control. It failed before reading artifacts
  with `uname=arm64 translated=0 hw.optional.arm64=1`, emitted
  `RUNTIME_INTEL_NATIVE_HANDOFF_FAIL`, and did not create the requested
  evidence file. This proves the public handoff does not convert Rosetta or an
  ARM host into Intel-native evidence; a positive Intel run remains required.

### 2026-09-02 — final local remediation gates

- The final dedicated `make runtime-release-negative-tests` run passed all 21
  cases, including the newly added Make-wrapper output-receipt alias and exact
  lane-GN mismatch cases, and ended with
  `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`.
- The final `make runtime-matrix-verify` run completed with exit 0. Its source
  gate formatted 29 Dart files with zero changes, reported no static-analysis
  issues, and passed the unit suite. The embedded freshness test again reported
  `regenerated=9 stable_noop=9`. All four architecture/mode thin builds and
  saved-receipt audits passed, as did Universal assembly/audit and the complete
  negative suite.
- Final integration smoke durations were: arm64 developer-JIT 2,133 ms, arm64
  release-AOT 1,627 ms, x86_64 developer-JIT under Rosetta 4,669 ms, x86_64
  release-AOT under Rosetta 2,782 ms, Universal arm64 1,680 ms, and Universal
  x86_64 under Rosetta 2,343 ms. Every smoke completed successfully. The matrix
  ended with the deliberately truthful
  `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED` status.
- The final `make phase0-verify` run completed with exit 0. Format, analysis,
  unit, debug/JIT launch, AOT, worker throughput, PTY, Metal, CoreText, IME,
  grid, parser, performance baseline, symbol audit, and all six bundle audits
  passed. No Phase 0 regression was observed.
- An independent post-gate artifact check found exactly `x86_64 arm64` on each
  Universal launcher, Engine, and AOT snapshot. Strict individual signature
  verification passed for all three, deep strict verification passed for the
  outer app, and its `Info.plist` passed `plutil -lint`. All four thin audit
  receipts and the Universal assembly receipt exist at their documented build
  paths.
- `git diff --check` passed both before and after the final memo update.
  `ROADMAP.md` has no diff, HEAD remains
  `3f392fa7f46a426a4d687d7eacd24434cdcdbe86`, adjacent `dart_appkit` remains
  clean, and the Engine checkout still has only the expected worker patch.
  A final marker scan found no debug-only TODO/FIXME changes in the task files.

### 2026-09-02 — second final-review implementation decisions

- The seven new findings reopen the local implementation gates; all preceding
  pass records remain investigation history, not acceptance for the current
  tree. The roadmap item and commit remain intentionally untouched.
- Path safety is centralized in a filesystem-identity guard. It resolves the
  nearest existing ancestor, records device/inode identities for the target
  and ancestor chain, rejects symlink leaves, compares containment and identity
  across every thin bundle/receipt and write destination, and repeats the same
  checks immediately before publication. This covers case-folding and Unicode
  normalization when the volume aliases those names, as well as hard-linked
  receipt aliases.
- The Make Universal wrapper performs no directory creation or deletion. The
  assembler validates a prospective output first, creates a sibling staging
  directory only afterward, and publishes one directory containing the app,
  assembly report, and Universal runtime-audit receipt. A single same-volume
  exclusive rename or swap makes the three artifacts one generation. A sync
  barrier precedes and follows publication; deliberate SIGKILL fault points
  exist immediately before publish and immediately after the atomic swap.
- Common provenance is now a deliberately enumerated semantic projection.
  Repository revisions/dirty-tree identities, SDK and Engine versions,
  semantic GN/configuration, architecture-neutral platform dill, normalized
  package roles, source hashes, and Xcode/SDK/compiler versions remain common.
  Checkout/build/SDK paths, raw package-config bytes and pub cache, raw host
  compiler hash/architecture, and target-lane binary paths remain diagnostic
  lane data. JSON comparison and semantic digests use recursively sorted keys.
  This allows independent ARM and Intel checkout roots without weakening
  revision, content, mode, deployment, or toolchain agreement.
- Architecture is retained in the build manifest as formal provenance, rather
  than existing only in the audit receipt. A saved receipt binds the exact
  signed bundle seal and is also required, but the manifest is the build-time
  source for the lane architecture/mode/configuration and real Engine,
  compiler, snapshotter, and platform input hashes. This keeps build and audit
  claims independently inspectable and resolves the earlier design ambiguity.
- `.dart_tool/package_config.json` is now a normal fingerprint prerequisite.
  The default package-config generation rule is separate from command-line
  overrides, so an override is consumed as an input and cannot accidentally
  cause `dart pub get` to update a different file. Generation/version, exact
  package set and entry schema, language version, package URI, local file URI,
  and project/AppKit root filesystem identities are checked fail-closed.
  Package semantic data is common; raw bytes, resolved roots, and pub cache are
  lane-local diagnostics.
- The selected compiler must identify `xcrun --find clang++` by filesystem
  identity and also use the exact `clang++` driver basename. SDK identity must
  match the selected `xcrun` macOS SDK. Raw compiler hashes remain lane-local
  because the host executable is legitimately architecture-specific.
- The handoff validates its smoke harness, its own source, the bundle auditor,
  and shared audit support against hashes present and equal in all three saved
  receipts before the Intel hardware gate. Evidence destination containment is
  also checked first, so a fake harness or output inside any input fails on the
  available ARM host without weakening the genuine Intel-only positive gate.
- The first focused format command completed, then Dart failed only while
  updating its telemetry timestamp outside the sandbox. Static analysis was
  rerun with normal tool access and reported `No issues found` for all eight
  changed runtime tools. The earlier freshness run passed; after strengthening
  the forged-root fixture to use a byte-identical AppKit package copy, that
  dedicated test and all build/matrix regressions must be rerun below.
- The first strengthened freshness rerun failed before compilation because the
  URI check treated the empty authority marker in a normal `file:///...` URI as
  a remote authority. The policy now permits an empty file-URI authority while
  continuing to reject a non-empty authority, query, or fragment. This was a
  validator defect; no artifact was accepted or published by the failed run.
- After that correction, `make runtime-build-freshness-test` passed with
  `regenerated=9 stable_noop=9` and
  `forged_package_root_rejected=1`. Changing only raw package-config/pub-cache
  data changed both fingerprints and regenerated all nine JIT/AOT derived
  outputs; repeating the same input rewrote none. A byte-identical AppKit
  package at a different filesystem identity was rejected.
- The first full negative rerun rebuilt and audited both thin release lanes and
  the Universal artifact, then passed architecture, wrapper, case, Unicode,
  and hard-link cases. Its report-inside-bundle case was safely rejected, but
  the auditor replaced the useful containment diagnostic with a null-guard
  error while formatting the failure. Report-path validation is now a separate
  pre-audit gate: on failure it performs no write and preserves the concrete
  containment error. No input bundle changed during the failed attempt.
- The corrected `make runtime-release-negative-tests` run rebuilt and strictly
  audited both thin release lanes, published and revalidated the Universal
  generation, then passed all 30 cases. This includes case-folding and Unicode
  aliases on this volume, hard-linked receipts, Make pre-write containment,
  audit/evidence containment, fake handoff smoke source, stale receipts,
  substantive provenance mismatch, semantically equivalent relocated roots,
  strict dependency/install-name/RPATH/entitlement/signature policy, actual
  extra and malformed duplicate FAT records, failed replacement, existing
  output replacement, and both pre-publication and post-swap SIGKILL faults.
  It ended with `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`; both fault cases left a
  freshly auditable app/assembly-report/runtime-receipt generation pair.
- A post-pass consistency review found that thin audit targets still rewrote an
  existing receipt even though the documented handoff calls it immutable.
  Bundle rebuild recipes now invalidate their own old receipt, the first audit
  creates a missing receipt with an exclusive filesystem link, and subsequent
  audit targets perform only fresh read-only receipt validation. Validation
  also rejects symlink, alias, or containment between the receipt and bundle.
  This change requires another dedicated and full gate below.
- The freshness fixture now also supplies a missing command-line package-config
  override and requires Make to report it as an input with no generation rule.
  This distinguishes the project default `dart pub get` target from an explicit
  transferred/test configuration and prevents updating the wrong file.
- The strengthened freshness suite passed again with
  `regenerated=9 stable_noop=9`, `forged_package_root_rejected=1`, and
  `missing_override_rejected=1`.
- The first immutable-receipt negative rerun safely rejected an attempt to
  reuse an existing receipt path, but reported the generic disallowed-file-type
  diagnostic before its more precise immutable-path diagnostic. The shared
  destination guard now checks the missing/immutable contract first. No receipt
  or bundle changed in the failed run.
- Focused formatting remained clean and static analysis again reported
  `No issues found` for all eight changed runtime tools after the destination
  guard correction.
- The corrected immutable-receipt rerun rebuilt and strictly audited current
  arm64 and x86_64 release lanes, atomically published and revalidated the
  Universal artifact directory, and passed all 32 negative cases. The two new
  cases prove that an existing thin receipt cannot be overwritten and that the
  public Make audit target performs fresh, read-only validation of an existing
  receipt. It ended with `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`; the complete
  alias, containment, handoff identity, provenance, Mach-O policy, FAT parser,
  immutable receipt, replacement, and fault-injection suite is green.
- The final `make runtime-matrix-verify` gate completed with exit status zero.
  Dart formatting checked 29 files with no changes; Objective-C++ formatting,
  plist lint, whole-project static analysis, and unit tests passed. The gate
  repeated the freshness suite and all 32 negative cases, built and strictly
  audited developer-JIT and release-AOT thin bundles for both architectures,
  and reassembled/revalidated the Universal publication. Native arm64 and
  Rosetta x86_64 smoke tests passed for their thin lanes, and both explicit
  launch architectures passed against the Universal bundle. The gate ended
  honestly with
  `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED: no Intel-native handoff was run`;
  this is the remaining acceptance blocker, not a downgraded local pass.
- The final `make phase0-verify` regression gate completed with exit status
  zero. Formatting, analysis, unit tests, developer launch, Phase 0 AOT,
  worker throughput, PTY, Metal, CoreText, IME, grid/parser/benchmark gates,
  and the six-bundle arm64 audit all passed. This confirms that the stricter
  matrix and publication contracts did not regress the completed Phase 0
  runtime path on the available Apple M1 host.
- Final diff review found that the package-config regression added in this
  review had displaced the earlier synthetic effective-input mutation in the
  freshness fixture. Both are required: the effective input represents a
  content-addressed recipe/config/source override, while package config is a
  direct Kernel input. The test now performs each mutation independently and
  requires all nine JIT/AOT derived outputs to regenerate after each, followed
  by a stable no-op run. Its focused format/analyze gate passed, and the
  dedicated rerun reported
  `effective_input_regenerated=9 package_config_regenerated=9 stable_noop=9`,
  `forged_package_root_rejected=1`, and `missing_override_rejected=1`.
  Because the test source is itself inventoried provenance, final matrix and
  Phase 0 gates are rerun on this exact tree below.
- The exact-tree matrix rerun completed with exit status zero: all source,
  dual-freshness, four thin-lane build/audit, 32 negative, native arm64,
  Rosetta x86_64, and dual-slice Universal gates passed, followed by the
  explicit Intel-native-unverified status. The first subsequent Phase 0 rerun
  passed format/analyze/unit, developer launch, and the basic AOT gate, but
  stopped in the worker hardware test with
  `PHASE0_AOT_NATIVE_FAIL ... resignaled=3` (throughput remained
  1014.04 MiB/s and the worker otherwise reported pass). The previous complete
  Phase 0 run on this implementation had `resignaled=0`; the only intervening
  source change was the isolated freshness fixture. This failure is preserved
  as evidence and must be rerun after the sustained matrix load to determine
  whether it is transient scheduling pressure or reproducible regression.
- An immediate focused `make phase0-worker-run` then passed with
  `resignaled=0` and 2304.56 MiB/s. The complete `make phase0-verify` rerun
  also finished with exit status zero; its worker observation had
  `resignaled=0` at 1113.39 MiB/s and every remaining Phase 0 hardware,
  performance, and six-bundle audit gate passed. The one post-matrix failure
  was therefore not reproducible in either the focused or complete rerun. It
  remains recorded above as a scheduling-sensitive observation rather than
  being omitted or used to weaken the scheduler turn-time acceptance gate;
  zero resignals were the successful rerun observations, not a separate
  acceptance criterion.
- Independent post-gate artifact inspection confirmed that the Universal
  launcher, Product Engine, and AOT snapshot each report exactly
  `x86_64 arm64` from `lipo -archs`. Strict individual signature verification
  passed for all three Mach-O files and deep strict verification passed for the
  outer app. The assembly report, its result, the saved runtime receipt, and
  the embedded manifest all carry the same publication generation
  `18042fd1fc1523e79b51c8b0e28d505a198634dd4f91e3c53d9fd668545a9603`.
  `git diff --check` passed. `ROADMAP.md` has no diff, adjacent `dart_appkit`
  remains clean, and the Engine checkout contains only the expected
  `runtime/engine/engine.cc` worker patch.
- After the architecture-metadata correction, the exact-tree
  `make runtime-matrix-verify` gate completed with exit status zero. Source
  format/lint/analyze/unit checks, the complete freshness suite, all four thin
  lane builds and audits, Universal assembly/audit, the expanded negative
  suite, native arm64 smoke, and Rosetta x86_64 thin and Universal smokes all
  passed. The negative suite included the 22 new unknown, null, duplicate, and
  noncanonical-order architecture cases and ended with
  `RUNTIME_RELEASE_NEGATIVE_TESTS_PASS`. The published generation is
  `0185324b6b67cda2b9ba89e5dd256d1c964120f1bccecadb3ec8ebc7c7e70cfb`.
  The matrix ended honestly with the Intel-native handoff unverified.
- The first final Phase 0 invocation after that matrix ran under the restricted
  workspace environment. Format, analysis, and unit tests passed, but the
  developer GUI launch stopped with exit status 250 immediately after the
  Engine compatibility report. This is consistent with the local GUI/process
  access boundary used by these hardware tests; it did not publish or mutate a
  runtime matrix artifact. The failure is retained here, and the complete gate
  is rerun below with the same local-machine access used by prior successful
  Phase 0 verification rather than being omitted.
- The local-machine `make phase0-verify` rerun completed with exit status zero.
  Format, analysis, unit, developer launch, AOT, worker, PTY, Metal, CoreText,
  IME, grid/parser/benchmark, and all six arm64 bundle audits passed. The
  worker observation was 2810.35 MiB/s with `resignaled=0`; the restricted
  environment's exit 250 was not reproducible.
- The first post-gate slice-inspection command used the release bundle name for
  the developer lanes and consequently reported four missing files. It did not
  mutate any artifact. Repeating the complete inspection with the actual
  `DartTerminalDeveloper.app` path confirmed two arm64-only developer Mach-O,
  three arm64-only release Mach-O, two x86_64-only developer Mach-O, three
  x86_64-only release Mach-O, and exact `x86_64 arm64` slices for the Universal
  launcher, Engine, and AOT snapshot.
- Strict individual signature verification passed for all three Universal
  Mach-O files, deep strict verification passed for the outer app, and its
  plist is valid. All four thin receipts and the Universal receipt are
  schema-v3 PASS records with their exact expected mode and architecture set.
  The assembly report's outer generation, result generation, nested audit
  generation, saved audit receipt generation, and embedded manifest generation
  are identical at
  `0185324b6b67cda2b9ba89e5dd256d1c964120f1bccecadb3ec8ebc7c7e70cfb`.
  The Universal parent contains only the cooperative lock and current release
  directory. Tracked `git diff --check` and per-file untracked no-index checks
  reported no whitespace errors.
- The final independent read-only rereview confirmed that the common validator
  closes the architecture-metadata finding across all five architecture-bearing
  build tools, all three Engine input-binary roles, host Clang, and the
  Universal top-level set. It also confirmed that the 22 table-driven cases
  cover every role/category requested and that the generator's sorted output
  matches the validator's canonical-order contract. The earlier trusted-Dart,
  cross-field root/path, and shared required-source-set fixes remain intact;
  the reviewer reported no new P1, P2, or P3 finding. No source was changed by
  that review.

### Blocker and exact resumption condition

- Hardware inspection identifies the available machine as an Apple M1 MacBook
  Pro. This environment exposes no Intel Mac or connected Intel-native test
  destination. Rosetta successfully executes x86_64 code but, per DT-012, is
  not Intel hardware evidence.
- Resume this same roadmap item only when an Intel Mac is available. Transfer
  the immutable x86_64 developer-JIT thin bundle/receipt, release-AOT thin
  bundle/receipt, and Universal bundle/receipt produced by the final local
  matrix. On an identical tooling checkout invoke the documented
  `make intel-native-runtime-verify` entry with absolute input paths, a named
  hardware label, and a new evidence path. It performs no rebuild and records
  the fresh audits and three direct native smokes. Record and review that JSON
  here without treating Rosetta or emulation as native.
- If those native gates pass, rerun source/matrix/Phase 0 regressions as needed
  on the final tree, change only this roadmap item to checked, and create its
  completion commit. If any native gate fails, keep the item blocked and record
  the failure. Do not start the following VM/isolate lifecycle task first.
- Because this completion condition is unmet, `ROADMAP.md` is intentionally
  unchanged, no task commit exists, and the uncommitted worktree preserves the
  implementation and evidence for resumption.

## Remaining risks and handoff

- The only available host is this Apple M1 machine. No Intel-native host or
  connected Intel test destination is available. Rosetta is installed and all
  x86_64 compatibility smokes pass, but it cannot close DT-012's Intel-native
  hardware gate. Until evidence from an Intel Mac is recorded, this roadmap
  item remains blocked, unchecked, and uncommitted.
- The required ProductX64, ReleaseX64, and architecture-specific snapshot tools
  were built successfully from the pinned local Engine checkout without
  network access. The initially anticipated build-size risk did not become a
  blocker; generated Engine outputs remain outside this repository's tracked
  changes.

## 2026-09-02 — Apple M1 baseline priority and acceptance change

### Purpose

Adopt Apple M1/arm64 as the primary development and release-acceptance
baseline so the project can continue through its main product goals without
waiting for scarce Intel hardware. Close this Phase 1 task using the already
verified M1-native arm64 lane, M1 cross-built x86_64 lane exercised through
Rosetta, and strict Universal artifact audit. Preserve the no-rebuild
Intel-native handoff as a low-priority post-goal compatibility follow-up.

### Background

The previous acceptance policy required a positive Intel-native handoff before
this task could close. The user explicitly changed that product priority:
Apple M1/arm64 is now the principal baseline, while an Intel Mac is a
low-priority compatibility destination rather than a prerequisite for the
main roadmap. This changes the evidence required for completion, not any
artifact-safety claim. Rosetta remains labelled as Rosetta and is not renamed
or represented as Intel-native execution.

The implementation already creates explicit arm64 and x86_64 thin lanes,
rejects implicit host fallback, assembles only exact two-slice release-AOT
artifacts, and exposes a genuine Intel-only no-rebuild verifier. Keeping that
verifier and its immutable receipts makes later Intel evidence possible
without holding the current product sequence open.

### Scope

- Make Apple M1/arm64 native execution the principal runtime and Phase 0
  hardware baseline.
- Treat M1 cross-build plus Rosetta execution as the required x86_64
  compatibility evidence for this Phase 1 matrix task.
- Keep exact arm64/x86_64 slice, provenance, dependency, resource, signature,
  receipt, atomic-publication, freshness, and fail-closed negative audits as
  mandatory completion evidence.
- Mark the current roadmap item complete and move positive Intel-native
  no-rebuild evidence to a separately visible, low-priority item after the
  Phase 11 main goal.
- Align `README.md`, `ROADMAP.md`, and `FEATURE_MATRIX.md` with this priority
  and completion definition.

### Out of scope

- Changing runtime implementation, build recipes, audit tools, or tests.
- Weakening the x86_64 thin-build, Rosetta smoke, Universal exact-slice,
  provenance, signing, or failure-preservation requirements.
- Claiming that Rosetta is an Intel-native hardware run or fabricating an
  Intel evidence record.
- Starting the following VM/isolate lifecycle task or any later feature task.
- Developer ID signing, hardened runtime, notarization, updates, and other
  Phase 11 release work.

### Dependencies and ordering

- The user's priority change is the authority for the revised hardware
  acceptance boundary.
- The final implementation and test sources are unchanged from the exact-tree
  local gates recorded above. The adjacent AppKit checkout remains at
  `5613950f15cf9837e5a025a9943c5b8010be4218`; the Engine remains at Dart
  revision `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` with only the reviewed
  worker patch.
- The Intel target remains implemented and documented. Its roadmap follow-up
  is placed after Phase 11's exit criteria, so it neither becomes the first
  unchecked item after this task nor blocks Phase 1 through Phase 11 or the
  main completion definition.

### Revised completion criteria

1. `RUNTIME_ARCH=arm64|x86_64` remains mandatory for thin products; omitted or
   unsupported architecture values fail closed without host fallback.
2. M1-native arm64 developer-JIT and release-AOT products build, audit, launch,
   and shut down cleanly.
3. x86_64 developer-JIT and release-AOT products cross-build on M1, contain
   exactly the x86_64 slice, pass the same strict audits, and launch under
   Rosetta as explicitly labelled compatibility evidence.
4. Universal release AOT is assembled only from immutable audited thin pairs;
   its launcher, Engine, and AOT snapshot contain exactly arm64 and x86_64,
   all common provenance/non-Mach/signature policies pass, and publication is
   an atomic bundle/report/receipt generation.
5. Source, freshness, fail-closed negative, matrix integration, Phase 0
   regression, artifact, signature, and generation-consistency gates pass on
   the M1 baseline.
6. No unresolved P1/P2/P3 implementation finding remains in the final
   independent review.
7. A positive Intel-native run is not required for this task or the project's
   main completion definition. It remains a separately tracked post-goal
   follow-up and must still use the genuine Intel-only no-rebuild target when
   eventually performed.

### Validation policy

- Recheck documentation links, Markdown structure, roadmap ordering and
  checkbox state, `git diff --check`, staged scope, and repository status.
- Run `make runtime-source-check` after the documentation changes to retain a
  current format/analyze/unit source gate.
- Do not rerun the expensive matrix or Phase 0 gates solely for this policy
  edit: no build, runtime, audit, fixture, package configuration, native source,
  or Dart source changes are permitted. Reuse is allowed only after confirming
  that the current diff adds policy/status documentation and does not change
  the implementation and test bytes that produced the recorded results.
- Retain the `RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED` matrix line as truthful
  diagnostic output. Under the revised policy it reports deferred coverage;
  it is no longer a failure or blocker for the main roadmap.

### Existing evidence under the revised criteria

- The last exact-tree `make runtime-matrix-verify` completed with exit zero.
  It passed source checks, all four thin lane build/audits, freshness, the full
  negative suite including the 22 architecture-metadata cases, M1-native arm64
  smokes, Rosetta x86_64 thin/Universal smokes, and Universal assembly/audit.
- The published generation
  `0185324b6b67cda2b9ba89e5dd256d1c964120f1bccecadb3ec8ebc7c7e70cfb`
  is shared by the assembly report, its result/audit, the saved Universal
  receipt, and the embedded manifest. Ten thin Mach-O files were confirmed as
  their exact single lane; all three Universal Mach-O files were confirmed as
  exact `x86_64 arm64` binaries with valid individual and outer signatures.
- The final local-machine `make phase0-verify` completed with exit zero. All
  format, analysis, unit, developer launch, AOT, worker, PTY, Metal, CoreText,
  IME, grid/parser/benchmark, and six arm64 bundle-audit gates passed on the
  Apple M1 baseline.
- The final independent read-only review confirmed the architecture validator
  and every earlier provenance/publication correction, with no new P1, P2, or
  P3 finding.
- The post-gate edits are limited to this memo and the project planning/user
  documentation named above. These Markdown files are not build or test inputs
  in the embedded runtime source inventory; the Makefile, runtime tools,
  native/Dart product sources, package configuration, and tests remain
  byte-identical to the exact-tree gate. A commit changes repository history as
  every verified task commit does, but does not change those tested inputs.
  Therefore the recorded matrix and Phase 0 execution evidence directly meets
  the revised criteria and need not be invalidated by this policy-only edit.

### Superseded blocker and remaining follow-up

This section supersedes the earlier status and blocker/resumption paragraphs,
which remain above as decision history. Lack of an Intel Mac is no longer a
blocker, the current roadmap item may be completed, and its implementation and
documentation may be committed. The remaining Intel-native handoff is the
post-Phase-11 low-priority follow-up recorded in `ROADMAP.md`; its execution
must continue to distinguish genuine Intel hardware from Rosetta.

### Documentation-change validation log

- The policy-alignment edit changed only this memo, `README.md`,
  `ROADMAP.md`, and `FEATURE_MATRIX.md`; no implementation, build recipe,
  fixture, package configuration, or product/test source was edited in this
  step.
- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-source-check` completed
  with exit zero. Dart format checked 29 files with no changes, Objective-C++
  format and both runtime plists passed, static analysis reported no issues,
  and the unit suite passed.
- The first Markdown link-check wrapper used a nonexistent `/usr/bin/rg` and
  consequently performed no link checks even though its shell loop returned
  zero. This result was rejected. Repeating with the resolved `rg` executable
  checked every local Markdown link in the four changed documents and reported
  `MARKDOWN_LINK_CHECK failures=0`.
- The first final `git diff --check` found trailing spaces on three edited
  metadata lines that had retained the documents' older two-space Markdown
  line-break style. Those edited lines now use an explicit `<br>` instead;
  the whitespace check is rerun below.
- Comparing every current `dart_terminal:` source-inventory entry with the
  final Universal manifest checked 21 files and found zero hash mismatches.
  This directly confirms that the policy edit did not alter any runtime source
  input represented by the accepted generation.
- After the metadata correction, `git diff --check` passed and per-file
  no-index checks reported `UNTRACKED_DIFF_CHECK failures=0`. The repeated
  Markdown link check again reported zero broken local links.
- Roadmap inspection confirmed that the completed matrix item links here, the
  first unchecked item is now the Phase 1 VM/isolate lifecycle contract, and
  the Intel handoff appears only after the Phase 11 exit criteria. The final
  completion definition explicitly excludes that follow-up as a prerequisite.
- The assembly report, saved Universal receipt, and embedded manifest still
  agree on generation
  `0185324b6b67cda2b9ba89e5dd256d1c964120f1bccecadb3ec8ebc7c7e70cfb`
  after the documentation-only edit.
- The unstaged scope contains the existing runtime-matrix implementation and
  its documentation plus the intentional `README.md`, `FEATURE_MATRIX.md`, and
  `ROADMAP.md` policy updates. HEAD remains
  `3f392fa7f46a426a4d687d7eacd24434cdcdbe86`; adjacent repository changes are
  not part of this commit.
- The explicit staging review contains exactly 14 task files: the runtime
  Make/tool implementation, this memo, README/feature-matrix alignment, and the
  minimal roadmap progress/order update. There is no remaining unstaged diff,
  `git diff --cached --check` passes, and no generated `build/` artifact is
  staged. The adjacent AppKit checkout is clean; the Engine checkout still has
  only its separately owned reviewed `runtime/engine/engine.cc` worker patch.
- The first `git commit` attempt and the following ordinary memo restage were
  rejected before changing the index because the restricted workspace
  environment could not create `.git/index.lock`. The existing index and all
  14 task files remained intact. This is a repository metadata permission
  failure, not a validation or content failure; the memo was then staged and
  the same reviewed commit retried with repository-write permission.

## 2026-09-02 — DT-012 hardware-evidence contract alignment

### Independent-review finding

The M1-baseline policy was aligned in `ROADMAP.md`, `README.md`, this memo, and
`FEATURE_MATRIX.md`, but the accepted Phase 0 DT-012 design still said that
both native-hardware smoke lanes, including Intel hardware, were mandatory
before the Universal/Phase 1 work could complete. Because DT-012 is a linked
acceptance authority, leaving that statement unqualified created a P2
documentation contradiction even though the implementation, tests, and
roadmap ordering were correct.

### Decision and correction

DT-012 receives a prominent dated addendum immediately after its status. The
addendum is the controlling policy only for the hardware evidence needed to
complete Phase 1 and the project's main goals: Apple M1-native arm64,
M1-cross-built x86_64 with explicitly labelled Rosetta compatibility, and the
strict Universal audit are sufficient under the user-selected priority.

The correction does not delete or reinterpret the historical CI graph.
Rosetta remains non-native evidence. The genuine-Intel-only no-rebuild target,
immutable receipts, fresh audits/smokes, and evidence JSON remain implemented
and documented for the post-Phase-11 low-priority follow-up. The addendum also
enumerates the DT-012 contracts that remain mandatory: product separation,
explicit architecture/no fallback, exact lane provenance, exact Universal
slices and non-Mach equality, immutable thin inputs, fresh signing/audit and
atomic publication, cache revalidation, Phase 11 distribution requirements,
and Phase 0 M1 regression gates.

No runtime implementation, test, roadmap, README, or feature-matrix change is
needed for this follow-up. Validation is limited to both changed documents:
local Markdown links, whitespace/diff checks, an explicit search for the old
and new evidence language, and staged-scope review. `runtime-source-check` is
not repeated because the follow-up changes no source or source-facing contract;
the successful source check in the immediately preceding completion commit
remains applicable.

### Follow-up validation

- `git diff --name-only` listed exactly the two intended documents:
  `docs/phase0/DT-012-build-ci-design.md` and this memo. `ROADMAP.md`,
  `README.md`, `FEATURE_MATRIX.md`, build/runtime sources, and tests have no
  follow-up diff.
- The local Markdown-link check covered both changed documents and reported
  `MARKDOWN_LINK_CHECK failures=0`. The new links resolve from the Phase 0
  document to the repository roadmap and this Phase 1 memo.
- The explicit consistency check confirmed that the dated addendum is at line
  9, before the original question at line 67, and contains the four controlling
  assertions: Rosetta is compatibility-only, Intel evidence is post-Phase-11,
  all other contracts remain mandatory, and the addendum governs conflicting
  Intel-completion language below it.
- `git diff --check` passed. A source check was intentionally not rerun because
  the diff is documentation-only and the preceding task commit's successful
  source check covers the unchanged implementation; running it would add no
  source-facing evidence.
- Staged-scope review contains exactly these two documents, has no unstaged
  diff, and passes `git diff --cached --check`. No runtime source, roadmap,
  user-facing README, feature matrix, generated artifact, or adjacent-repository
  change is included.
