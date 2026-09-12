# dart_appkit generic ownership boundary

## Status

- Phase: 10
- Task: remove product-specific implementation from `dart_appkit`
- Started: 2026-09-12
- State: in progress
- Current subtask: move the App Intents capability package
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
