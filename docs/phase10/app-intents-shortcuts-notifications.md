# App Intents, Shortcuts, and Notifications

## Status

- Phase: 10
- Task: App Intents/Shortcuts and notifications
- Started: 2026-09-12
- State: in progress
- Current subtask: consumer declaration, dependency gates, and bundle audit
  (complete)
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Expose a small, safe set of terminal actions to Shortcuts, and finish the
desktop-notification lifecycle with explicit authorization, delivery failure,
and user-response handling. Both surfaces must reuse Dart's authoritative
action, hierarchy, configuration, and teardown policy rather than introduce a
second application-state owner.

## Background and source references

- The Phase 10 ROADMAP and Feature Matrix UI-08 leave App Intents/Shortcuts as
  the first unfinished native-polish feature. Phase 9 CAP-12 already parses and
  bounds terminal-origin OSC 9/99 notifications and progress, but its AppKit
  projection does not report authorization, scheduling failure, or selection.
- Apple's
  [AppIntent documentation](https://developer.apple.com/documentation/AppIntents/AppIntent)
  defines discoverable app actions, and the official
  [App Shortcuts overview](https://developer.apple.com/documentation/appintents/app-shortcuts)
  says a compiler extracts static provider metadata from Swift code in an app,
  extension, package, or library. The WWDC22
  [implementation session](https://developer.apple.com/videos/play/wwdc2022/10170/)
  explicitly describes App Intents as a Swift-only framework.
- Apple's
  [notification authorization API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization%28options%3Acompletionhandler%3A%29)
  requires authorization before interactive local notifications, returns on an
  arbitrary background thread, and directs applications to inspect current
  settings because users can later change them. The
  [notification-center documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
  provides the asynchronous settings query. The
  [delegate documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
  requires delegate installation before launch completion to avoid missing
  responses.
- The installed Xcode toolchain provides Swift 6.3.3 and
  `appintentsmetadataprocessor`. The current generic runtime compiles an
  Objective-C++ host and copies declared native dylibs into `Frameworks`, but
  has no Swift compilation or App Intents metadata staging contract.

## Scope

- Extend generic `dart_appkit` UserNotifications support with bounded explicit
  authorization/status outcomes, scheduling outcomes, default-selection
  responses, and deterministic disable/shutdown cleanup. All asynchronous
  callbacks become immutable native events; no callback may enter Dart on the
  native stack.
- Define a closed runtime manifest entry for exactly one dependency-owned App
  Intents module, compile/stage its Swift image and compiler-extracted metadata,
  and record enough build-manifest evidence to audit both shipped bundles.
- Add terminal-specific foreground App Intents for a minimal self-contained
  action set: new window, new tab, and Quick Terminal toggle. They contain no
  shell command, terminal text, cwd, environment, stable object ID, arbitrary
  action string, or user-supplied parameter.
- Deliver intent invocations through a bounded exactly-once native command
  queue to the existing shared action dispatcher. Reject overflow, disabled
  state, stale generation, timeout, and shutdown without mutating hierarchy.
- Add typed live configuration for App Intents admission and desktop
  notifications; reflect enabled state, notification authorization, last
  bounded failure, and Shortcuts availability in Settings.
- Map the default click on a live terminal notification back through an opaque
  internal token to its still-live session, activate the application, and focus
  the owning window/tab/pane. Never trust a notification identifier as an
  externally supplied hierarchy ID.
- Validate fake/native/package/product behavior, both Developer JIT and Release
  AOT bundles, metadata and native-image audits, permission/failure paths,
  teardown, and documentation.

## Out of scope

- Arbitrary shell execution or text input, terminal-content/entity queries,
  custom AppEntity records, destructive close/quit actions, AppleScript object
  targeting, or user-defined App Intent parameters. These add authority or
  content exposure that is unnecessary for this Phase item.
- Remote notifications, APNs registration, notification attachments, sounds,
  reply fields, custom destructive actions, or persistent notification
  history.
- Granting/resetting notification permission, editing Shortcuts, invoking Siri,
  or automating System Settings. External permission and discovery observations
  belong in a manual checklist.
- Localization work beyond the source/default locale required to compile and
  validate App Shortcuts. Complete product localization remains the next
  ROADMAP item with Reduce Motion/Contrast.

## Dependencies and constraints

- ADR-001 keeps action meaning, hierarchy, focus, and lifecycle decisions in
  Dart. Objective-C/Swift owns only framework objects, copied inputs, cached
  status, compiler metadata, and bounded transport.
- ADR-002 keeps one responsive root isolate. UserNotifications callbacks and
  App Intent `perform()` must never synchronously re-enter or wait on Dart from
  an AppKit callback stack. Queue admission and eventual completion are bounded.
- Existing CAP-12 coalescing, global 3/10-second admission, session live-ID cap,
  active/focused suppression, and reset/close cancellation remain authoritative.
- Notification response tokens and App Intent operation IDs are monotonic,
  process-local, bounded values. Raw notification text, identifiers, errors, or
  intent inputs are not copied into diagnostics without an explicit safe bound.
- Native terminal-specific Swift code belongs in a dependency package under
  `dart_appkit`; Dart Terminal must not acquire product Objective-C/Swift files.

## Completion conditions

1. Notification permission is never treated as a synchronous success. Current
   status, request result, scheduling result, selection, denial, error,
   cancellation, disable, and shutdown each have deterministic bounded paths.
2. App Shortcuts advertise only the scoped shared actions, compiler metadata is
   present in both bundles, and each accepted invocation dispatches exactly one
   existing product action. Disabled, overflow, timeout, and shutdown paths fail
   closed and release all owners.
3. Live configuration and Settings expose enable/disable, permission, and a
   content-free bounded failure/status view without bypassing system policy.
4. Focused Dart tests, native/header/package tests, runtime manifest/build tests,
   exact JIT/AOT acceptance, source/bundle audits, full gates, manual checklist,
   documentation, and final diff review pass with no untracked residue.

## Validation approach

- Generic `dart_appkit` fake/native tests cover protocol versioning, async
  settings and authorization results, schedule success/failure, response token,
  callback thread handoff, cancellation, delegate ownership, and shutdown.
- Runtime/package tests compile a minimal Swift provider, reject malformed or
  duplicated manifest declarations, inspect extracted metadata and the exact
  staged image/resource/build-manifest records, and exercise the bounded command
  queue without Dart reentry.
- Product tests use fake notification and intent ports to prove shared action,
  live configuration, focused-session re-resolution, stale response rejection,
  Settings state, disable/re-enable, and complete disposal.
- Runtime acceptance exercises an internal deterministic invocation seam in
  Developer JIT and Release AOT. A separate manual checklist covers Shortcuts
  discovery/run and notification prompt/deny/allow/change/click behavior without
  mutating those user-owned settings automatically.

## Ordered subtasks

1. **`dart_appkit` notification permission/result/response substrate**
   - Add a versioned native event contract and Dart API for explicit settings,
     authorization, schedule result, and default-response tokens. Install the
     notification delegate before launch completion and preserve bounded
     cancellation/shutdown behavior.
   - Complete with C/C++ header checks, native and fake Dart lifecycle tests,
     dependency full gate, consuming full gate, documentation, ROADMAP progress,
     and standalone dependency and consumer commits.
2. **App Intents native capability and runtime metadata packaging**
   - Extend `dart_macos_runtime` with one closed optional App Intents declaration,
     Swift build inputs, compiler metadata extraction/staging, exact bundle and
     build-manifest evidence, then add the terminal-specific Swift capability
     and its bounded command queue.
   - This is split into three ordered review units: runtime manifest/build
     substrate; terminal Swift capability; consumer declaration and complete
     dependency/bundle audits. Each unit receives focused tests, documentation,
     ROADMAP progress, and its own commit before the next starts.
3. **Product configuration, shared-action, Settings, and lifecycle integration**
   - Connect only new-window, new-tab, and Quick Terminal toggle to the shared
     dispatcher; connect notification status/click focus to current live
     sessions; add live options and content-free Settings status.
   - Complete with deterministic policy/configuration/UI/lifecycle tests, full
     gate, documentation, ROADMAP progress, and a standalone commit.
4. **Both shipped runtimes, manual checklist, and documentation closure**
   - Add deterministic self-acceptance for App Intent admission and notification
     outcomes, audit exact JIT/AOT metadata and owners, document external system
     observations, reconcile README/Feature Matrix/security/configuration
     evidence, and decide the parent item only after all conditions pass.

## Findings and decision log

- 2026-09-12: Commit `750044d` closed AppleScript documentation/evidence. A
  complete ROADMAP reread selected this item as the first unfinished Phase 10
  work, and both the terminal and dependency worktrees were clean.
- The current `HandleUserNotificationWithSystem` calls
  `requestAuthorizationWithOptions:` for every post and immediately reports
  native submission success. It discards authorization errors, denied results,
  scheduling errors, and default-selection responses, so the caller cannot
  distinguish permission or delivery failure. Removal already cancels pending
  and delivered identifiers and must remain compatible.
- The current desktop signal coordinator already maps parser requests to opaque
  `dt.p*.s*.n*` native identifiers and removes them on replacement, reset,
  session close, and disposal. Response routing can add a separate opaque token
  map without weakening these existing limits.
- App Shortcuts are compiler-extracted static declarations rather than a runtime
  registration API. A generic JSON-only declaration or dynamic action list
  would be false integration; the runtime must execute Swift compilation and
  metadata extraction from dependency-owned source/module inputs.
- Only foreground, parameterless, non-destructive shared actions are selected
  for the initial App Intents surface. This is the smallest useful Shortcuts
  contract and avoids granting Shortcuts a shell/input or object-targeting path.
- The generic notification substrate now negotiates event protocol 13 and adds
  application event type 46. Its four-field payload is deliberately
  content-free: lifecycle kind, positive opaque token, stable authorization
  status, and stable failure class. Default responses require an unknown
  authorization field and no failure; both native and Dart decoders reject
  malformed enum/token combinations.
- Three additive C calls query settings, explicitly request alert permission,
  and submit a tracked notification. The old fire-and-forget call remains for
  source/binary compatibility. Dart exposes the additive surface through the
  optional `NativeUserNotificationLifecycleBindings`, so an older bridge fails
  with `unsupportedVersion` instead of creating a mandatory ABI break.
- Native settings/authorization requests, tracked deliveries, and response
  ownership are independently bounded to 256 live records. Native callbacks
  dispatch immutable results onto the AppKit main queue; an epoch and owned
  dictionaries suppress late callbacks after replacement, removal, or bridge
  shutdown. Removal emits a cancellation for an admitted tracked delivery and
  clears any later response token.
- Both generic runners install the `UNUserNotificationCenterDelegate` in
  `applicationWillFinishLaunching:`. Foreground presentation is suppressed at
  this substrate boundary, while a default user selection consumes exactly one
  stored opaque response token. Product focus/session re-resolution remains a
  later subtask and no notification text or identifier is returned to Dart.
- `UNAuthorizationStatusEphemeral` is not available to a macOS-targeted switch
  in the installed SDK even though the cross-platform stable protocol reserves
  the value. The native mapping therefore returns the four macOS statuses and
  maps future/unrecognized values to `unknown`; the Dart decoder retains the
  reserved `ephemeral` value for protocol stability.
- A raw native test executable initially crashed when shutdown asked
  `UNUserNotificationCenter` for its singleton outside an application bundle.
  Delegate shutdown now returns before that framework access when no delegate
  was installed, while actual runners still install and release their delegate.
- A full-file `clang-format` trial reformatted legacy Objective-C/C test layout
  far beyond the notification change. The noise was removed by deriving the
  inverse legacy-layout patch from a formatted HEAD image; each recovered file
  was accepted only when formatting the recovered result reproduced the exact
  semantic implementation image. Remaining diffs are task-scoped.
- The installed Xcode 26.6 build `17F113` exposes Swift 6.3.3 and
  `appintentsmetadataprocessor`. A local minimal provider experiment established
  that `swiftc -emit-const-values` alone produces no usable constant-value file;
  the compile must also pass a const-gather protocol list containing
  `AppIntent` and `AppShortcutsProvider`. Linking that object as an `@rpath`
  dylib and processing its source/constant-value lists produces exactly
  `Metadata.appintents/version.json` and `extract.actionsdata` with the intent
  type and automatic shortcut declaration.
- The runtime manifest now has one optional closed `appIntents` object:
  dependency package, normalized `.swift` source, Swift module name, and unique
  dylib filename. It requires macOS 13 or later, bounds the path/source/output
  sizes, resolves the package exactly once from `package_config.json`, rejects
  symlink escape and native-image collisions, and reserves the complete
  `Metadata.appintents` resource namespace even when the declaration is absent.
- The runtime compiles the dependency source for the bundle architecture and
  minimum deployment target, verifies the metadata tools version against the
  selected Xcode build, and accepts only the two expected metadata files. The
  Swift image is linked directly into both generic hosts and given an `@rpath`
  install name so dyld loads the declarations before application startup; a
  late dynamic load was rejected because system discovery must not depend on a
  Dart-side timing path.
- Both bundle modes stage the image in `Contents/Frameworks` and the compiler
  output in `Contents/Resources/Metadata.appintents`. The build manifest records
  package/source/module/image, byte counts, target triple, Xcode build, and the
  exact metadata file set. An omitted declaration preserves the legacy bundle
  shape. Missing/oversized source, engine-image collision, processor failure,
  absent output, and tools-version mismatch all fail before bundle signing.
- The terminal capability is a dependency-owned Swift image rather than a Dart
  native-asset hook. The runtime already links that same image into the host for
  static App Intents discovery; the Dart facade therefore opens the staged
  Frameworks image explicitly and validates its versioned C ABI instead of
  producing a duplicate native image.
- The Swift source declares exactly three macOS 14 foreground, parameterless
  intents: new window, new tab, and Quick Terminal toggle. Its shortcuts
  provider advertises exactly those three actions. Compiler metadata tests parse
  the generated action model and require three `openAppWhenRun` actions with
  empty parameter lists and three matching automatic shortcuts; source-text
  matching alone was rejected as insufficient discovery evidence.
- One `NSLock`-protected process queue owns only action enum, positive monotonic
  operation token, generation, timeout, and an optional Swift continuation. It
  is disabled at session start and capped at 16 pending operations. App Intent
  execution may admit from framework threads, while start/configuration/poll/
  completion/shutdown C calls require the AppKit main thread. Dart never runs on
  the App Intent callback stack.
- Enable-state transitions advance the generation; disable and shutdown drain
  all queue/pending ownership before resuming callers. `take` is FIFO and marks
  an operation taken, `complete` requires the exact current generation and a
  taken live token, and timeout removes both queued and pending ownership.
  Invalid action/disposition, disabled, overflow, untaken, duplicate, stale,
  timeout, and post-shutdown paths have explicit stable statuses.
- The exported deterministic self-automation seam accepts only the same three
  enum codes into the same admission path. It cannot carry parameters or invoke
  Siri/Shortcuts, and is exposed to Dart only from the package testing library.
  A Swift async test invokes the real `AppIntent.perform()` methods and proves
  completion success plus disabled, timeout, and shutdown error resumption.
- Final ownership review found that the first timeout closure captured the whole
  pending-command object, which would have retained an already-resumed Swift
  continuation until the deadline. The closure now captures only operation and
  generation integers plus a weak queue reference; completion/disable/shutdown
  therefore release the continuation immediately while the harmless stale timer
  later observes no matching owner.
- The Dart facade dynamically resolves and ABI-checks the already-linked Swift
  image. A real dylib FFI test pins all typedefs and verifies that standalone
  Dart preserves the native wrong-main-thread and not-started statuses; fake
  bindings separately cover typed bounds, enum decoding, exact opaque
  completion, retryable shutdown failure, and self-automation rejection.

## Validation log

- 2026-09-12, `/Users/remi/dart/dart_appkit`, Apple M1/arm64, Xcode 26.5,
  Swift 6.3.3: `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed after
  final diff cleanup. This covers scaffold/header checks, native bridge and
  event encoder tests, both runner contracts, all package analysis/tests,
  native capability/asset hooks, FFI smoke, and the legacy event fixture.
- The dependency tests exercise protocol-12 suppression/protocol-13 admission,
  exact event encoding, independent settings/authorization/delivery tokens,
  default-response correlation, invalid output/response arguments, native
  refusal, wrong-thread rejection, Dart enum decoding/cache behavior, failure
  propagation, range checks, legacy-symbol fallback, and post-termination
  rejection.
- Dependency commit `aa9c027` (`Report notification permission and responses`)
  contains the task-scoped generic substrate after the complete gate passed.
- The consuming full gate initially exposed two integration requirements:
  terminal event switches must explicitly ignore the new substrate event until
  product wiring, and Phase 7 acceptance fingerprints must be regenerated for
  the consumer source change. Both consumer updates are present.
- `CI=true DART_SUPPRESS_ANALYTICS=true make phase7-appkit-acceptance` first
  failed only because the sandbox denied the Metal compiler's existing module
  cache under `~/.cache/clang`; the authorized identical rerun succeeded and
  regenerated `test/corpus/appkit/phase7_acceptance_v1.json`.
- 2026-09-12, `/Users/remi/dart/dart_terminal`, Apple M1/arm64:
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed after regeneration.
  It reported 280 formatted files with zero changes, no analyzer issues, fixed
  Phase 9 stress seed `0x509a1171`, all freshness/compatibility gates, and the
  complete Dart Terminal test suite.
- Consumer commit `9ff23d8` (`Adopt notification lifecycle events`) records the
  event-switch compatibility, regenerated evidence, task memo, and completed
  first ROADMAP child. The post-commit ROADMAP reread selected the runtime App
  Intents declaration/build/metadata substrate as the next ordered unit.
- 2026-09-12, `/Users/remi/dart/dart_appkit`, Apple M1/arm64, Xcode 26.6 build
  `17F113`, Swift 6.3.3: focused `dart analyze` and
  `dart run test/run_tests.dart` passed. The real-toolchain test compiled the
  minimal provider, extracted discoverable intent/automatic-shortcut metadata,
  and verified its dylib install name and AppIntents framework dependency.
  Fake-builder coverage verified strict declaration parsing, legacy omission,
  all closed failure paths, direct JIT/AOT host-link inputs, exact bundle
  staging, and complete build-manifest evidence.
- The exact dependency gate `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  passed after the final runtime review. It includes native bridge/runner/
  lifecycle/capability tests, every package analysis and test suite, build-hook
  checks, examples, and FFI/legacy-event smoke tests.
- Dependency commit `f76c331` (`Package App Intents metadata in runtime
  bundles`) contains the closed manifest, Swift build/extraction/staging path,
  JIT/AOT host link input, audit evidence, public documentation, and focused
  coverage. The post-commit ROADMAP reread confirmed this nested unit as the
  current item pending only its consumer-side progress record.
- 2026-09-12, `/Users/remi/dart/dart_terminal`, Apple M1/arm64: the exact
  consuming gate `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed after
  the dependency commit and ROADMAP update. It reported 280 formatted files
  with zero changes, no analyzer issues, fixed Phase 9 stress seed
  `0x509a1171`, and all freshness, compatibility, integration, and product
  tests passing.
- Focused dependency validation passed for the new capability:
  `make terminal-app-intents-native-test terminal-app-intents-dart-test` builds
  the strict C/C++ headers, Swift 6 dylib, native queue test, real async
  `perform()` lifecycle test, Dart facade tests, and real Xcode compiler metadata
  audit. `swift-format lint --strict`, Xcode `clang-format --dry-run --Werror`,
  Dart format, and package analysis also pass.
- The first formatting probe used `/usr/bin/clang-format`, which is absent on
  this Xcode installation. `xcrun --find clang-format` resolved the toolchain
  binary; the initial in-place run was sandbox-blocked and the authorized rerun
  formatted only the four new C/C++ files. A later focused `make` invocation
  from the package directory had no local Makefile; rerunning the same targets
  from the repository root passed. Neither failed attempt changed product
  semantics or weakened a test.
- The first exact dependency `make test` run passed every App Intents test but
  encountered the previously documented race in the unrelated PTY
  `live Dart child cannot steal native PTY completion` case: the exit status was
  correct but `externalReapObserved` had not reached the diagnostic listener
  before `firstWhere`. No source was changed. The immediate focused
  `make dpty-dart-test` rerun passed all PTY cases, including that event.
- The unchanged exact dependency gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed completely,
  including both App Intents native tests, compiler metadata extraction, all
  package/native/runtime/runner tests, build hooks, examples, and smoke tests.
- After the continuation-capture fix and real Dart FFI boundary coverage, the
  same exact dependency `make test` gate was run once more and passed without a
  retry. This is the final validation image for the capability commit.
- Dependency commit `9a2a014` (`Add bounded terminal App Intents capability`)
  contains only the new Swift/C ABI/Dart package, its focused metadata and
  lifecycle tests, documentation, and Make integration. The post-commit
  ROADMAP reread confirmed this nested child as the current unit pending its
  consumer-side progress record; the next implementation goal remains consumer
  declaration, dependency gates, and exact bundle audit.
- 2026-09-12, `/Users/remi/dart/dart_terminal`, Apple M1/arm64: the exact
  consuming `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed after
  the capability commit and ROADMAP update. It reported 280 formatted files
  with zero changes, no analyzer issues, fixed Phase 9 stress seed
  `0x509a1171`, and every freshness, compatibility, integration, and product
  test passing.
- The consumer now declares `dart_terminal_app_intents_macos` as a direct path
  dependency and names its package-owned Swift source, module, and staged dylib
  in `macos_application.json`. The source audit rejects a missing, indirect,
  empty, oversized, or mismatched declaration before any product build.
- The first real Developer JIT bundle build exposed a runtime integration bug:
  `_xcrunFind` resolved Xcode tool symlinks before execution. On this Xcode,
  `swiftc` is a multi-call driver symlink, so invoking its resolved
  `swift-frontend` path selected the wrong command mode and rejected
  `-emit-const-values` and `-Xfrontend`. The runtime now validates but preserves
  the exact path returned by `xcrun`; its fixture makes `swiftc` a symlink so a
  future eager resolution fails the existing manifest-driven assembly tests.
- The focused runtime test and the exact dependency gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` pass with that fix. The gate
  includes the real installed-Xcode metadata extraction test, both fake JIT/AOT
  assembly paths, every native/package test, examples, and smoke tests.
- The next Developer JIT audit compiled and signed the complete app but rejected
  the App Intents image byte evidence: the runtime recorded the Swift linker's
  image size before the bundle's deep ad-hoc signing replaced its signature.
  An isolated signing probe confirmed that one explicit signature changes the
  image from 186120 to 203168 bytes for the product library name, while a second
  signature is size-stable. The runtime therefore signs the package image before
  recording its bounded size and copying it into the bundle; the final deep app
  signature retains that evidence. Fake assembly now requires the image-specific
  signing command as well as final bundle signing.
- One focused-test command used repository-relative paths while already inside
  the package directory, and a second used the package-local test path from the
  repository root; neither found the intended files. The corrected root-level
  `CI=true DART_SUPPRESS_ANALYTICS=true dart run
  packages/dart_macos_runtime/test/run_tests.dart` invocation passed every
  runtime builder test.
- Dependency commits `d4984c2` (`Preserve Xcode tool invocation names`) and
  `0526a9e` (`Record signed App Intents image evidence`) contain the two minimal
  runtime integration corrections. Each was committed only after the exact
  dependency `make test` gate passed, and each post-commit ROADMAP reread kept
  the consumer declaration/audit child as the current ordered unit.
- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-source-check` passes with
  `tracked=516`, no product-native source, and the one reviewed native test
  fixture. It validates the direct package-graph dependency and the exact
  bounded package-owned Swift declaration.
- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-bundle-audit` passes for
  both Developer JIT and Release AOT on arm64. Each signed bundle contains the
  exact three parameterless, foreground action declarations and three matching
  automatic shortcuts, the two-file `Metadata.appintents` bundle, and the
  directly linked `@rpath/libdart_terminal_app_intents_macos.dylib`. The image
  has the expected install identity and AppIntents framework dependency; source,
  signed-image, metadata sizes, Xcode build version, architecture, and target
  triple agree with the build manifest.
- The final consumer gate `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  passes. It formatted 280 files with zero changes, reported no analyzer issues,
  used fixed Phase 9 stress seed `0x509a1171`, and passed all freshness,
  compatibility, integration, security, and product tests.

## Handoff and remaining work

- The first ordered subtask is complete in dependency and consumer commits.
  The generic runtime App Intents declaration/build/metadata unit is implemented,
  fully validated, committed as `f76c331`, and marked complete in the ROADMAP.
  Its consuming full gate also passes. The terminal-specific Swift capability
  and bounded command queue is implemented, fully validated, committed as
  `9a2a014`, marked complete in the ROADMAP, and its consuming full gate passes.
  Its consumer-side progress record is committed as `19b6e61`. Consumer
  declaration and exact bundle auditing are complete, including both runtime
  corrections and both signed bundle modes. Product polling, action dispatch,
  and Settings wiring have not started early.

### Completed capability unit boundary

- One dependency-owned terminal App Intents package contains parameterless new
  window, new tab, and Quick Terminal toggle declarations plus their static App
  Shortcuts provider. No product manifest declaration belongs in this unit.
- Its closed native/Dart capability contract admits only those three
  action codes into a fixed-capacity FIFO. Each accepted operation has one
  positive process-local token and one terminal result; disabled, overflow,
  timeout, stale-generation, and shutdown states reject without queue growth.
- Native and package tests prove Swift-to-native admission without direct Dart
  reentry, main-isolate polling/drain semantics, exact-once completion, bounded
  ownership, and teardown. The next consumer-declaration unit will decide how
  the product loads, polls, and dispatches these commands.
