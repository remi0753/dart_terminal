# dart_appkit generic ownership boundary

## Status

- Phase: 10
- Task: remove product-specific implementation from `dart_appkit`
- Started: 2026-09-12
- State: in progress
- Current subtask: genericize Finder folder Service actions
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Restore the intended repository boundary: `dart_appkit` and
`dart_macos_runtime` own reusable AppKit/runtime mechanisms only, while this
application owns its PTY, renderer, automation, and product presentation
policy. Generic mechanisms may remain in the dependency only when product
meaning, identifiers, and visible text are injected by the application.

## Background and confirmed facts

- Both worktrees were clean at the start. The application was at `e79580f` and
  the adjacent dependency was at `c65a2ef`.
- The existing architecture documents already say that PTY behavior, renderer
  policy, application text/style, and product decisions do not belong in the
  generic host. Package placement and two later APIs contradict that rule.
- The application root manifest and `pubspec.yaml` already identify all four
  product packages. Relocating them changes package ownership and relative path
  declarations, not their public package/library/capability identifiers.
- Current wire event 45 encodes two folder-Service choices as integer 0/1.
  Those integers are reusable; only the generic API's `newTabs/newWindows`
  meaning and fixed Objective-C `openTab/openWindow` selectors are product
  leakage.
- Secure Event Input acquisition itself is a macOS mechanism and remains
  generic. Its current native overlay is not generic because the dependency
  chooses the visible `SECURE AUTO/MANUAL` strings and accessibility wording.

## Complete pre-change inventory

The inventory command was:

```shell
git ls-files packages/dart_terminal_renderer_macos \
  packages/dart_terminal_applescript_macos \
  packages/dart_terminal_app_intents_macos packages/dart_pty_macos
git grep -Il -i terminal
rg -l 'FolderService|newTabAtFolder|newWindowAtFolder|openTab|openWindow' \
  native packages
rg -l 'SecureInputIndicator|secureInputIndicator|Secure Keyboard Entry' \
  native packages
```

### Product package trees in the generic repository

Every tracked file below the following roots is misplaced; the count includes
source, public headers/facades, hooks, tests, package metadata, and README files.

| Root | Tracked files | Owner after correction |
| --- | ---: | --- |
| `packages/dart_pty_macos/` | 19 | `dart_terminal` |
| `packages/dart_terminal_renderer_macos/` | 26 | `dart_terminal` |
| `packages/dart_terminal_applescript_macos/` | 17 | `dart_terminal` |
| `packages/dart_terminal_app_intents_macos/` | 16 | `dart_terminal` |

This is 78 tracked files in total. Treating each complete root as the inventory
unit ensures that no hook, lockfile, test, native source, or metadata file is
left behind during relocation.

### Product build ownership outside those trees

- `dart_appkit/Makefile`: variables, ABI/header checks, native builds/tests,
  Dart tests, help entries, and aggregate-test dependencies for all four
  product packages.
- `dart_appkit/README.md`, `ROADMAP.md`, `docs/ARCHITECTURE.md`,
  `docs/C_ABI.md`, and `docs/VERIFICATION.md`: active ownership/layout,
  contract, and verification claims for those packages.
- `dart_appkit/docs/WORKLOG.md`: append-only historical evidence referring to
  the consuming application and former package placement. It is historical
  documentation rather than executable code; a final migration entry will
  make the ownership change explicit without rewriting past evidence.

### Product semantics embedded in otherwise generic code

Finder folder Services leak tab/window meaning through all of these files:

- `native/bridge/include/dart_appkit.h`
- `native/bridge/src/AppKitBridge.mm`
- `native/bridge/src/BridgeInternal.h`
- `native/bridge/test/BridgeTests.mm`
- `native/bridge/test/header_compile.c`
- `native/bridge/test/header_compile.cc`
- `native/runner/DartEventEncoder.cc`
- `native/runner/test/DartEventEncoderTests.cc`
- `packages/dart_appkit/lib/dart_appkit.dart`
- `packages/dart_appkit/lib/src/api/application.dart`
- `packages/dart_appkit/lib/src/api/events.dart`
- `packages/dart_appkit/lib/src/native/ffi_native_bindings.dart`
- `packages/dart_appkit/lib/src/native/native_bindings.dart`
- `packages/dart_appkit/test/fake_native_bindings.dart`
- `packages/dart_appkit/test/ffi_bridge_smoke.dart`
- `packages/dart_appkit/test/legacy_event_bridge_smoke.dart`
- `packages/dart_appkit/test/run_tests.dart`
- `packages/dart_macos_runtime/README.md`
- `packages/dart_macos_runtime/lib/src/application_manifest.dart`
- `packages/dart_macos_runtime/lib/src/tool/builder.dart`
- `packages/dart_macos_runtime/test/run_tests.dart`

The fixed Secure Input indicator presentation crosses these files:

- `native/bridge/include/dart_appkit.h`
- `native/bridge/src/AppKitBridge.mm`
- `native/bridge/test/BridgeTests.mm`
- `native/bridge/test/header_compile.c`
- `native/bridge/test/header_compile.cc`
- `packages/dart_appkit/lib/dart_appkit.dart`
- `packages/dart_appkit/lib/src/api/secure_event_input.dart`
- `packages/dart_appkit/lib/src/api/view.dart`
- `packages/dart_appkit/lib/src/native/ffi_native_bindings.dart`
- `packages/dart_appkit/lib/src/native/native_bindings.dart`
- `packages/dart_appkit/test/fake_native_bindings.dart`
- `packages/dart_appkit/test/ffi_bridge_smoke.dart`
- `packages/dart_appkit/test/legacy_event_bridge_smoke.dart`
- `packages/dart_appkit/test/run_tests.dart`

### Product-named generic test fixtures

- `native/bridge/test/BridgeTests.mm` and
  `packages/dart_appkit/test/run_tests.dart` use a `terminal—日本語` string for
  generic UTF-8/UTF-16 coverage.
- `packages/dart_macos_runtime/test/run_tests.dart` uses Terminal menu/image
  text and `dart_pty_macos` native-asset identifiers for generic manifest and
  bundling tests.

## Ordered subtasks and individual completion conditions

1. Move `dart_pty_macos` intact, change the root dependency to the local path,
   transfer its contract/audit/native/Dart gates, pass them, remove the generic
   repository copy and gates, then commit both repositories.
2. Repeat that ownership transfer and verification for
   `dart_terminal_renderer_macos`.
3. Repeat for `dart_terminal_applescript_macos`.
4. Repeat for `dart_terminal_app_intents_macos`.
5. Rename the reusable two-choice folder-Service boundary to generic
   primary/secondary actions and selectors. The application manifest and event
   handling inject and interpret tab/window meaning. Preserve the existing
   integer wire layout and prove old protocol filtering still works.
6. Replace the state-specific Secure Input overlay API with a generic bounded
   view badge whose visible text and accessibility label/help are supplied by
   this application. Secure Event Input ownership stays unchanged.
7. Remove product targets from the generic Makefile; replace product-named
   generic fixtures; update current README/architecture/ABI/verification and
   roadmap claims; add a tracked audit that rejects product-named code or paths
   in the generic repository. Preserve `WORKLOG.md` as chronological evidence
   and append the completed migration instead of falsifying history.
8. Run both exact `make test` gates, source audits, Developer JIT and Release AOT
   build/audit/integration suites needed to prove the relocated hooks/assets and
   injected policies. Only then close the parent ROADMAP item.

Each completed relocation/refactor receives its own commit in each affected
repository. After every application commit, reread `ROADMAP.md` and this memo
before starting the next subtask.

## Out of scope

- Renaming the four public product package/library/ABI identifiers after they
  are moved into this product repository.
- Removing reusable native-capability, native-asset, App Intents metadata,
  scripting-definition, custom-view, Secure Event Input, or folder/file URL
  transport mechanisms from the generic libraries.
- Rewriting historical commits or deleting append-only evidence that accurately
  records where work occurred at the time.
- Reduce Motion/Contrast, localization, or terminal inspector work.

## Dependencies and risks

- Package hooks resolve dependencies relative to each package. Moving the
  package roots requires updating their paths to the adjacent generic packages
  and regenerating lockfiles without changing package identity.
- The runtime builder discovers hook output from the application package graph;
  the local roots must therefore be proven in both Developer JIT and Release
  AOT bundles.
- A folder-Service selector rename changes generated `Info.plist` metadata and
  native provider methods in lockstep. The payload type and integer action
  values remain stable to avoid an unnecessary event-protocol revision.
- The generic badge must keep bounded copy-in strings, main-thread ownership,
  no hit testing, no layout resizing, and accessible output without retaining
  application objects in native code.

## Overall completion conditions

- No tracked path in `dart_appkit` contains case-insensitive `terminal` or the
  product-only `dart_pty_macos` root.
- Executable/build/test code in `dart_appkit` contains no product package IDs,
  product UI strings, terminal-specific types, selectors, or policies.
- All four product packages and their complete verification ownership live in
  `dart_terminal`; root package resolution uses those local copies.
- Folder Services and the view badge are generic parameterized mechanisms;
  all tab/window and automatic/manual secure-input meaning is supplied here.
- Both repositories pass their exact full gates, and both runtime modes pass
  bundle/audit/integration coverage for the moved packages and refactored APIs.

## Validation log

- 2026-09-12: completed the pre-change tracked-file and semantic-name inventory
  above. No production bridge/runtime code contained a literal `terminal`
  outside the four package roots, but the Services and indicator APIs exposed
  product meaning under names that did not contain that literal; they are
  therefore explicitly included rather than relying on a string-only audit.
- 2026-09-12: moved all 19 tracked `dart_pty_macos` files from dependency commit
  `102d23e` into this repository without source differences, changed the root
  path dependency to `packages/dart_pty_macos`, and transferred C11/C++20 ABI
  compile checks, the child-symbol audit, warning-clean native build/test, and
  Dart analysis/real+fake lifecycle tests into this root `Makefile` and its
  aggregate `test` target. `CI=true DART_SUPPRESS_ANALYTICS=true make
  dpty-native-test dpty-dart-test` passed, including interactive/login TTY,
  process lifecycle, bounded scheduling/write diagnostics, force close, and
  the build-hook native asset. The dependency copy and ignored build outputs
  were removed; its `make validate`, dry-run aggregate test plan, absence check,
  and no-stale-PTY-target check passed.
- 2026-09-12: moved all 26 tracked renderer package files into this repository,
  switched the root and package-local generic dependencies to their new paths,
  and transferred the C/C++ ABI checks, Metal shader/plugin build, AppKit-backed
  native capability suite, Dart analysis, native-asset hook, and facade tests to
  this root Makefile and aggregate `test`. The first sandboxed run failed only
  because Metal could not write its user module cache; the required rerun in the
  normal environment passed native compilation and tests. That rerun exposed a
  real relocation assumption in `hook/build.dart`: its old `../../native`
  include resolved inside the product repository. Pointing the product hook at
  the adjacent generic dependency's public native headers fixed it, and the
  unchanged focused rerun passed all renderer Dart/hook tests. The dependency
  package, ignored outputs, targets, and variables were then removed; dependency
  `make validate`, stale-target dry-run audit, path absence, and diff check
  passed.
- 2026-09-12: moved all 17 AppleScript capability files here and transferred
  SDEF validity, C/C++ header compatibility, warning-clean plugin/test builds,
  native queue/lifecycle tests, Dart analysis/facade tests, and the direct
  native-asset hook smoke into this root Makefile and aggregate test. The
  package-local runtime dependency and native-extension header include now
  resolve the adjacent generic repository from the product-owned package.
  `make dependencies terminal-applescript-native-test
  terminal-applescript-dart-test` passed in the normal environment. The generic
  repository copy, ignored outputs, and all associated Makefile ownership were
  removed; its validation, stale-target dry-run audit, path absence, and diff
  check passed.
- 2026-09-12: moved all 16 App Intents capability files here, changed root and
  package-local paths, and transferred Swift compilation, C/C++ ABI checks,
  native queue/perform lifecycle suites, Dart analysis/facade/FFI coverage, and
  compiler-extracted metadata verification into this root Makefile and
  aggregate gate. `make dependencies terminal-app-intents-native-test
  terminal-app-intents-dart-test` passed. The dependency package and ignored
  output plus every capability-specific Makefile target were removed; its
  validation, dry-run stale-reference audit, path absence, and diff check
  passed. All 78 pre-change product package files now have the product
  repository as their sole source owner.
- 2026-09-12: replaced the generic bridge/runtime's tab/window-shaped folder
  Service contract with closed `primary` and `secondary` actions. The wire
  integer values and protocol version remain unchanged, while native provider
  selectors are now `performPrimaryFolderService` and
  `performSecondaryFolderService`; arbitrary selector injection remains
  impossible. This application injects the existing tab/window menu labels in
  `macos_application.json` and maps primary to tab creation and secondary to
  window creation in `TerminalApplication`.
- The focused generic contract/native/event/runtime/Dart/FFI gate first failed
  in the sandbox only because the linker could not write the adjacent generic
  repository's build output. Its normal-environment rerun passed all bridge,
  event encoder, runtime manifest/builder, Dart API, launcher, and current/
  legacy FFI tests. The product's first exact `make test` run then found only a
  stale generated AppKit acceptance hash caused by the intentional application
  source change. `make phase7-appkit-acceptance` regenerated that evidence, and
  the second exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` run passed,
  including all four relocated package gates, format of 283 files, analysis,
  compatibility, and security stress coverage.

## Secure Input display genericization

Replace the Secure Input-specific overlay in the generic bridge with a bounded
generic badge whose visible and accessibility strings are copied from an
application-owned configuration. This repository must inject every secure-
input label and map its existing coordinator state to show, update, or hide the
badge. The native mechanism must preserve main-thread ownership, no hit
testing, no layout resizing, and bounded accessible output.

- 2026-09-13: replaced `DaSecureInputIndicatorState`,
  `da_view_set_secure_input_indicator`, `SecureInputIndicatorState`, and
  `View.secureInputIndicatorState` with the unrelated generic
  `DaViewBadgeConfiguration`, `da_view_set_badge`, `ViewBadge`, and
  `View.badge` surfaces. A non-null badge requires copied non-empty,
  display-safe visible, accessibility-label, and accessibility-help strings,
  each at most 256 UTF-8 bytes; null removes it. The overlay remains
  non-interactive, top/trailing anchored, and outside target layout sizing.
- The old display symbol was optional under ABI version 1, as is the new badge
  symbol. Both old and new Dart/native image combinations therefore fail this
  optional display feature as unsupported rather than dereferencing a missing
  symbol; the generic bridge ABI and event protocol versions do not change.
  Secure Event Input acquisition and ownership remain a separate generic
  resource and are unaffected.
- All product strings now live in `terminal_secure_keyboard_entry.dart`:
  `SECURE AUTO`, `SECURE MANUAL`, both accessibility labels, and the help text.
  The product maps hidden to null and automatic/manual states to immutable
  product-owned badges before assigning `View.badge`.
- Generic `make contract-check native-test dart-test ffi-smoke` passed,
  covering C/C++ headers, native copy/bounds/UTF-8/display-safety/layout/a11y,
  Dart cache/failure/validation, and current/legacy FFI. The first sandboxed
  product unit run and acceptance-evidence generation were blocked only by the
  Metal compiler's user module-cache write; normal-environment reruns passed.
  After regenerating the intentional source hashes, the exact product
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed. Both
  Developer JIT and Release AOT real-application Secure Keyboard Entry suites
  passed through acquire, automatic/manual transitions, badge handoff/hide,
  IME isolation, and clean teardown.

## Generic source closure

Remove remaining product examples, identifiers, tests, build descriptions, and
current documentation from the generic repository. Add an executable source
audit that rejects future product words and package identities in tracked paths
or executable/build/test sources while retaining explicitly historical worklog
evidence.

- 2026-09-13: the post-move inventory found no remaining tracked path with a
  product name. Non-historical content was limited to two generic definition
  fixtures using terminal text, an App Intents image name, two runtime fixture
  declarations using `dart_pty_macos`/`dpty_*`, and current generic repository
  README, ROADMAP, architecture, ABI, and verification descriptions of the
  former product packages. The fixtures now use editor/example-native-asset
  values, and all current documents describe only generic capability and
  native-asset ownership. Historical worklog evidence is deliberately retained.
- Added `tool/generic_repository_audit.dart` and integrated it into the generic
  root `make validate`. It scans tracked and non-ignored untracked paths plus
  every decodable UTF-8 source, rejects English/Japanese terminal terms and the
  old PTY symbol prefix, and exempts only the chronological worklog's content.
  The clean scan passed with 131 paths/130 text files; a temporary forbidden
  content probe was rejected and removed, after which the scan passed again.
- Generic `make validate native-test dart-test runtime-dart-test` passed after
  the cleanup, including C/C++ contracts, native bridge fixtures, public Dart
  API/launcher tests, and strict runtime manifest/builder tests.

## Current subtask

Run the exact full gates in both repositories, then rebuild, audit, and execute
the consuming application in Developer JIT and Release AOT modes. Re-run the
generic ownership audit on the committed source, inspect both diffs/worktrees,
and close the parent only if every ownership and runtime acceptance condition
passes with no residual untracked output or serious blocker.

- 2026-09-13: the generic repository's exact `make test` passed, including its
  committed 131-path ownership audit. The product repository's exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` also passed with all four
  package gates, 283-file format, analysis, compatibility, and security stress.
- The first final `make runtime-verify` then passed the repeated product full
  gate but correctly stopped at `runtime-source-check`: the audit still encoded
  the pre-transfer rule that no native source could exist anywhere in the
  product repository. The four newly product-owned package roots were therefore
  all reported. This was an audit ownership update omitted during relocation,
  not a build or runtime failure.
- Updated the audit to allow native source only below the four exact declared
  product package roots while continuing to require zero native source in the
  application layer. Swift is now included in the native-source extensions;
  this exposed the existing macOS differential activation helper, which is now
  tracked as a separate exact reviewed tool source alongside the exact ncurses
  test fixture. Generic host implementation source remains forbidden in the
  product Makefile, and `bin/`/`lib/` still reject direct FFI/image loading.
- The audit now checks non-ignored untracked files as well as tracked files. A
  temporary C source under `lib/` was rejected and removed. The clean rerun
  passed with 601 paths, zero application native sources, 25 package native
  sources, one reviewed test source, and one reviewed tool source.
- After committing that correction and rereading the ROADMAP, the next complete
  `runtime-verify` advanced past the source audit and stopped because the
  compatibility coverage report hashes `README.md`; the ownership-boundary
  wording update had intentionally changed that source. Regenerating with
  `make terminal-compatibility-regression-coverage` passed its nine-case/417-
  split prerequisite and updated only the generated report. This is expected
  evidence synchronization rather than a compatibility failure.
- After synchronizing that evidence, the next complete `runtime-verify` passed
  the repeated full product gate, source audit, Developer JIT and Release AOT
  builds, and both bundle audits, then stopped at the first Developer JIT smoke
  assertion. A focused rerun failed identically. Directly launching the same
  built application with the event-wire fixture showed valid negotiated and
  emitted protocol version 13 records for the close, application, window-state,
  and menu events; the integration tool still hard-coded version 12 in those
  checks and in its scroll and theme acceptance records. This is a stale test
  expectation rather than user interaction or a runtime regression.
- `dart_appkit` already exports `dartAppKitCurrentEventProtocolVersion` from its
  public package entrypoint. The integration tool now imports that public
  generic contract and derives every current-protocol assertion from it, so a
  future generic protocol increment cannot leave scattered product test
  literals behind. No generic repository source change was required. `dart
  format` reported the edited file already formatted; its subsequent analytics
  timestamp write was sandbox-denied, so all remaining Dart validation is run
  with analytics suppressed as used by the repository gates.
- The first focused Developer JIT rerun inside the restricted command sandbox
  aborted before Dart startup in AppKit's `_RegisterApplication`, leaving a
  macOS crash report and host-starting diagnostics with no application output.
  This was a WindowServer registration restriction, not the earlier assertion
  or a product execution failure. The identical command rerun in the normal GUI
  environment passed with `RUNTIME_INTEGRATION_PASS`, including the version 13
  event-wire observations through the new public-constant expectations.
- Focused validation also passed `dart analyze
  tool/runtime_integration_smoke.dart` with no issues and the ownership-aware
  `make runtime-source-check` with 601 paths, zero application native sources,
  25 product-package native sources, and the two exact reviewed native test/tool
  sources.
- The final normal-environment `CI=true DART_SUPPRESS_ANALYTICS=true make
  runtime-verify` passed from start to finish. It repeated the complete product
  gate (all four relocated package gates, generated-contract checks, 283-file
  formatting, analysis, compatibility, and security stress), repeated the
  601-path ownership audit, built and audited both arm64 Developer JIT and
  Release AOT bundles, and passed both runtime variants for smoke, display,
  native hierarchy/splits, user actions, AppleScript, system automation,
  Services/native content, Quick Terminal, Secure Keyboard Entry,
  configuration, theme, shell integration, desktop signals, OSC 52,
  restoration, clipboard, lifecycle failure/replacement paths, backpressure,
  1,000-iteration resource stress, shutdown fault injection, and PTY deadline
  handling. Both bundle audits reported one helper, one native-asset directory,
  two native capabilities, one scripting definition, and three App Intents.
- The generic repository was then retested at its unchanged committed source
  with the exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate. It passed
  the 131-path/130-text-file product-word audit, scaffold and native bridge/
  runner/runtime contracts, runtime builder tests, example native asset, Dart
  API and launcher tests, current FFI smoke, and legacy event fallback. No
  residual product source, path, test fixture, or current documentation remains
  in the generic repository; the historical worklog remains the sole explicit
  audit exemption. The ownership correction and its final acceptance criteria
  are complete, with no blocker or deferred subtask.
