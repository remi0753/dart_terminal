# AppleScript Dictionary and Object Lifecycle

## Status

- Phase: 10
- Task: AppleScript dictionary and object lifecycle
- Started: 2026-09-12
- State: active
- Current subtask: native AppleScript capability and runtime dictionary
  packaging
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Expose a native macOS scripting dictionary whose stable object hierarchy is
`application -> windows -> tabs -> terminals`, and let authorized automation
create, split, input to, focus, and close those objects without bypassing Dart's
authoritative hierarchy, paste safety, or teardown rules.

## Background and source pins

- ROADMAP Phase 10 and Feature Matrix UI-08 identify the dictionary and object
  lifecycle as the first unfinished work. The Phase exit requires AppleScript
  control of window/tab/split/input/focus/close.
- The comparison source is Ghostty commit
  [`e2e53f861482e080bf45054ba49ef471f9849937`](https://github.com/ghostty-org/ghostty/tree/e2e53f861482e080bf45054ba49ef471f9849937),
  pinned from `refs/heads/main` on 2026-09-12. Its
  [`Ghostty.sdef`](https://github.com/ghostty-org/ghostty/blob/e2e53f861482e080bf45054ba49ef471f9849937/macos/Ghostty.sdef)
  defines application/windows/tabs/terminals with stable text IDs, selected and
  focused relationships, and create/split/input/focus/close commands. The
  official [AppleScript feature guide](https://ghostty.org/docs/features/applescript)
  describes the same observable hierarchy and TCC-protected external control.
- Apple's Cocoa scripting model resolves object specifiers through native
  objects and KVC. `NSScriptCommand` is synchronous by default, but
  [`NSAppleEventManager`](https://developer.apple.com/documentation/foundation/nsappleeventmanager)
  provides `suspendCurrentAppleEvent` and reply/resume operations. The latter is
  required here so a native handler can enqueue an immutable Dart request and
  complete later without synchronously re-entering the root isolate.
- The product already owns monotonic window/tab/pane IDs, ordered hierarchy
  mutation, native reconciliation, close/Quit confirmation, bounded paste
  admission, current title/cwd metadata, and complete teardown. No existing
  repository or `dart_appkit` source contains an AppleScript/sdef bridge.

## Scope

- Add `macos-applescript` as a typed live boolean option, enabled by default.
  Disabling it empties native scripting collections, rejects new commands,
  resolves every pending command exactly once, and does not request or reset
  macOS Automation permission.
- Define immutable, content-free application/window/tab/terminal snapshots
  from current standard windows only. Expose stable type-prefixed text IDs,
  titles, trusted local cwd metadata, selected tab, focused terminal, and
  front-window state. Never expose terminal screen/history contents.
- Provide new-window, new-tab, four-direction split, input-text, focus,
  close-terminal, close-tab, and close-window commands. All targets are
  re-resolved by stable ID immediately before mutation; stale or wrong-kind
  references fail closed.
- Route scripted input as bounded paste-style external content through the
  ordinary confirmation and transport path. Route structural close through the
  existing risk/confirmation coordinators rather than directly dropping pane
  owners.
- Add a native scripting capability with a generated/canonical `.sdef`, cached
  snapshot wrappers, bounded pending Apple Events, asynchronous command events,
  typed completion, timeout, disable, and shutdown behavior.
- Extend `dart_macos_runtime` with a closed optional scripting-definition
  manifest entry, deterministic resource staging, exact Info.plist declaration,
  and build-manifest audit.
- Integrate the product, test fake/native/current/legacy boundaries, accept both
  Developer JIT and Release AOT bundles, provide a TCC/manual checklist, and
  reconcile README/Feature Matrix/evidence.

## Out of scope

- App Intents/Shortcuts and notification work in the following ROADMAP item.
- Reading terminal contents, arbitrary action strings, synthetic key/mouse
  injection, mutable tab names, custom command/environment launch records, or
  scripting Quick Terminal. These exceed the Phase exit requirement and expose
  additional content/authority without a current product contract.
- Automating System Settings, clearing or granting another process's TCC
  database entry, or claiming an `osascript` permission prompt was accepted.
- Synchronous native-to-Dart callbacks, nested AppKit loops, unbounded Apple
  Event descriptors, reusable IDs, or a second hierarchy owner.

## Dependencies and constraints

- ADR-001 keeps hierarchy, terminal meaning, input safety, and lifecycle policy
  in Dart while native code owns Apple Event descriptors, Cocoa scripting
  wrappers, and suspension IDs. ADR-002 keeps the one root isolate responsive;
  no command handler may wait for Dart on the AppKit stack.
- The scripting native surface belongs in a separate terminal-specific native
  capability package rather than adding terminal classes to generic
  `dart_appkit`. Generic `.sdef` packaging belongs in `dart_macos_runtime`.
- Snapshot packet size, string bytes, object count, pending operations, and
  command text must have hard maxima. Publishing is atomic: invalid or
  oversized replacement leaves the last accepted snapshot intact.
- The dictionary remains discoverable in the bundle while runtime enablement
  controls actual access. macOS grants Automation/TCC authority to the sending
  process; the app documents that boundary and offers no self-grant path.
- Current product IDs are monotonic and never reused. External IDs will be
  `window:<n>`, `tab:<n>`, and `terminal:<n>` so wrong-kind references cannot
  accidentally resolve.

## Completion conditions

1. `sdef`/Script Editor exposes the declared application -> windows -> tabs ->
   terminals hierarchy, stable IDs, selection/focus relations, and only the
   scoped commands.
2. Snapshot queries are bounded and synchronous from native cached state.
   Mutations suspend and asynchronously resume Apple Events without native-to-
   Dart reentry; reply, error, timeout, disable, and shutdown are exactly once.
3. Create/tab/four-direction split/focus manipulate the authoritative hierarchy
   and reconcile native ownership. Scripted text uses ordinary paste
   confirmation/transport and exact PTY bytes; close uses existing risk policy
   and completely tears down affected objects.
4. Default-enabled/live-disabled configuration, wrong-kind/stale objects,
   malformed/oversized input, busy mutation, missing permission/failure
   documentation, and Quick Terminal exclusion all fail predictably.
5. Focused/fake/native/package tests, exact sdef/plist/build-manifest audits,
   both shipped runtime modes, source/bundle audits, exact full terminal gate,
   manual checklist, documentation, final diff review, and standalone commits
   pass.

## Validation approach

- Pure Dart tests cover snapshot ordering/limits, stable IDs, configuration,
  request validation, stale targets, four split directions, paste confirmation,
  close decisions, command serialization, disable, timeout, and disposal.
- Native/package tests load and validate the sdef, exercise KVC collections and
  object specifiers from immutable snapshots, dispatch every command through a
  test Apple Event, and verify suspension/reply/error/timeout/lifecycle counts.
- Runtime tests compare exact Developer JIT/Release AOT `Info.plist`, resource,
  and build-manifest declarations and reject missing/remote/oversized paths.
- Product acceptance uses a deterministic self-automation boundary in both
  shipped apps to avoid modifying the user's TCC database. It compares exact
  hierarchy IDs, PTY bytes, focus, close collapse, stale-reference failure,
  disable/re-enable state, and final zero owner counts.
- A manual checklist covers `sdef`, Script Editor, external `osascript`, first-
  use TCC prompt/denial/retry, System Settings visibility, and disabled-mode
  behavior without changing permissions automatically.

## Ordered subtasks

1. **Typed configuration, snapshot, command, and lifecycle contract**
   - Add the live option and native-neutral immutable model, bounded codec,
     request/result state machine, and product command executor interfaces.
   - Complete when limits, ordering, stable/wrong-kind/stale identity, timeout,
     disable/dispose, generated config docs, focused tests, exact full gate,
     documentation, ROADMAP progress, and a standalone commit pass.
2. **Native AppleScript capability and runtime dictionary packaging**
   - Add the terminal-specific native capability package, canonical sdef,
     cached native wrappers, suspended command delivery/completion, and closed
     runtime manifest/plist/resource support.
   - Complete when public/fake/native/header/lifecycle/sdef/runtime tests, both
     generic host builds, dependency full gate, consuming full gate, audits,
     documentation, ROADMAP progress, and standalone dependency/product commits
     pass.

   This work is further ordered into three reviewable units because generic
   bundle packaging, the terminal-specific native ABI, and the consuming
   declaration have separate ownership and validation boundaries:

   1. Extend only `dart_macos_runtime` with a closed optional
      scripting-definition manifest object, bounded validated staging, exact
      plist keys, and build-manifest evidence. Complete with runtime focused
      tests and a standalone dependency commit.
   2. Add `dart_terminal_applescript_macos` as an optional native capability
      package. It owns the cached Cocoa wrappers, application category,
      bounded command queue, suspend/resume lifecycle, C ABI, Dart facade,
      headers, native/fake/lifecycle tests, and a standalone dependency commit.
   3. Declare both the dictionary and capability in Dart Terminal, update
      dependency locks/audits, prove both generic host builds plus dependency
      and consuming full gates, then complete the second parent child in a
      standalone consuming commit.
3. **Product integration, both shipped runtimes, and manual checklist**
   - Connect snapshots and commands to live hierarchy, paste, focus, close, and
     configuration; add deterministic self-automation acceptance and manual TCC
     coverage.
   - Complete when focused product tests, JIT/AOT exact behavior, source/bundle
     audits, full gate, manual checklist, review, progress, and a standalone
     commit pass.
4. **Documentation/evidence closure and parent completion decision**
   - Reconcile README, Feature Matrix UI-08/security/configuration status,
     dictionary reference, acceptance evidence, remaining manual observations,
     and every parent completion condition.
   - Complete when freshness/full gates and final review pass, then the child,
     integration parent, and top-level item are checked and committed.

## Findings and decision log

- 2026-09-12: Commit `a79bc3b` closed the preceding native-content item. Both
  the terminal and adjacent `dart_appkit` worktrees were clean, and the required
  ROADMAP reread selected AppleScript as the first unfinished Phase 10 item.
- The current state model already provides ordered standard window/tab/pane
  enumeration, reverse lookup, four-direction split placement, active/selected/
  focused mutation, and monotonic identities. Product integration should adapt
  those methods rather than create parallel native state.
- Current external text uses one bounded admission and paste controller with a
  ten-second repeat confirmation. AppleScript input will add a distinct source
  identity so it cannot accidentally confirm a Service or drop request.
- Cocoa scripting query callbacks must return immediately. They can read a
  copied native snapshot just like existing Services and accessibility caches.
  Commands require Dart-owned mutation and therefore adopt Apple Event
  suspension/reply rather than calling Dart or waiting on the AppKit stack.
- Quick Terminal is excluded from the first public dictionary: it is singleton,
  retained while hidden, rejects tabs, and has Close-as-hide semantics unlike a
  standard script window. A later explicit API may expose it without making
  ordinary window lifecycle ambiguous.
- The first contract implementation adds `macos-applescript` as the 45th typed
  option. It defaults to `true`, is live-applied, and is projected into the
  immutable product configuration without creating a native owner at config
  parse time. Invalid file values recover to the default; invalid CLI values
  remain usage errors through the shared boolean codec.
- External object IDs are closed to `window:<positive>`, `tab:<positive>`, and
  `terminal:<positive>` with the product's 63-bit monotonic upper bound. Leading
  zeros, wrong kinds, extra separators, missing/negative/overflow values, and
  cross-kind command targets are rejected before a mutation can be scheduled.
- The version-one snapshot codec is deterministic JSON capped at 4 MiB. It
  accepts at most 32 standard windows, 64 tabs per window, and 64 total
  terminals; validates unique IDs and selected/focused references; bounds safe
  titles and absolute POSIX cwd strings; and atomically represents disabled
  scripting as an empty hierarchy. It contains no terminal cell/history text.
- The native-neutral command controller accepts at most 16 pending operations,
  runs one executor future at a time, preserves operation identity, turns
  exception/mismatched reply/timeout into typed failure, rejects queued/new work
  on live disable, and resolves active/queued/future work once on disposal.
  Script text shares the 64 MiB paste hard cap but has a distinct confirmation
  source identity from Services and drop, preventing one authority path from
  confirming another.
- Focused static analysis reports no issues. The standalone AppleScript model/
  codec/lifecycle test, product configuration test, and effective-config test
  all pass through their normal native build hooks. Tests cover strict identity,
  snapshot round-trip and malformed/oversized rejection, typed command shapes,
  serial ordering, pending cap, disable, timeout, disposal, and the 45-option
  live/recovery/default projection.
- The generated configuration reference adds exactly the canonical
  `macos-applescript = true|false` row in schema order. A review found four
  additional Settings/native-hierarchy tests with intentional schema-count
  assertions; these were updated from 44 to 45 rather than weakening the
  completeness checks.
- Snapshot construction now requires `selectedTabId` to agree with exactly one
  selected-tab flag, so cached KVC relationships cannot publish contradictory
  selection state. Focused tests also distinguish duplicate-operation rejection
  from queue saturation and verify that risky AppleScript text cannot reuse a
  pending Services confirmation token.
- A direct `dart format` pass formatted all six targeted files with zero
  changes, then the Dart CLI reported that its user-level telemetry session
  timestamp was not writable in the sandbox. This did not affect source bytes;
  subsequent validation uses `CI=true DART_SUPPRESS_ANALYTICS=true` (the normal
  repository convention) so the unrelated telemetry write is disabled.
- The first sandboxed rerun of the focused AppleScript test could not write
  Clang's user cache while the renderer build hook compiled Metal modules
  (`~/.cache/clang/ModuleCache`, `Operation not permitted`). This is an
  environment-only failure before tests ran; the same exact test is rerun with
  the already-required build/cache permission rather than changing code or
  weakening coverage.
- The first sandboxed generated-reference freshness check hit the same Clang
  module-cache permission failure in the renderer build hook before either
  checker ran. It is likewise rerun unchanged with cache permission; dependency
  resolution itself succeeded and made no manifest change.
- The first exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` reached and
  passed parser/configuration/action freshness, then stopped at the expected
  stale Phase 7 AppKit acceptance artifact because the intentional Settings
  schema-count assertions changed. No runtime assertion failed. The dedicated
  Phase 7 generator is used next, followed by a hash/scope review and a full
  gate rerun.
- Phase 7 evidence regeneration changed only the recorded SHA-256 values for
  `terminal_application.dart` and `terminal_native_hierarchy_test.dart` in the
  existing scenarios; scenario inputs, UI assertions, runtime modes, and all
  other sources remained byte-for-byte unchanged.
- The second exact full gate passed Phase 7 acceptance and all preceding
  freshness/regression checks, then reported the compatibility coverage report
  stale because README and Feature Matrix intentionally changed. The dedicated
  compatibility generator is used; its output is reviewed before the third
  exact full-gate run.
- Compatibility coverage regeneration changed only the README and Feature
  Matrix SHA-256 fields. The nine regression cases, 417 split runs, fix-family
  mapping, and all executable evidence stayed unchanged.
- The third exact full gate completed successfully, including the aggregate
  test runner and security stress, but `dart analyze` emitted one non-fatal
  `directives_ordering` info for the newly added aggregate-test import. The
  import is reordered; analysis and the exact full gate are rerun so the task
  closes with zero diagnostics rather than relying on the command's exit code.
- Final contract hardening requires one-based tab/window indexes to match their
  immutable collection order, converts executor exceptions and mismatched
  operation replies to typed `failed` results, and exercises both cases. The
  focused formatter reports zero changes, focused analysis reports no issues,
  and the focused AppleScript test passes.
- The final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all
  freshness, compatibility, differential, application, terminfo, and shell
  integration checks; formats 278 files with zero changes; analyzes with no
  issues; passes the Phase 9 security stress; and ends with
  `dart_terminal tests passed`. `make runtime-source-check` also passes with
  507 tracked files, zero product native sources, and one reviewed test-native
  source. The adjacent `dart_appkit` worktree remains clean.

## Subtask completion record

- 2026-09-12: **Typed configuration, snapshot, command, and lifecycle
  contract — complete.** The live/default setting, immutable bounded hierarchy,
  strict codec, kind-safe identities, typed serialized command lifecycle,
  distinct AppleScript paste authority, generated settings reference, focused
  tests, source audit, and exact full gate meet subtask 1's completion
  conditions. Native Cocoa scripting and bundle packaging remain exclusively in
  ordered subtask 2.
- 2026-09-12: The required post-commit ROADMAP reread selected native
  capability/runtime packaging next. It is split before implementation into
  generic runtime packaging, the terminal-specific capability, and consumer
  declaration/gates. The first unit changes `dart_macos_runtime` only; no
  application hierarchy or later product integration is allowed yet.
- The first generic-runtime format pass identified two Dart files needing
  formatting but could not overwrite the adjacent dependency worktree under
  the terminal repository's sandbox (`Operation not permitted`). No partial
  rewrite occurred. The same formatter is rerun with explicit permission for
  the already-scoped dependency files.
- The generic runtime now accepts only an optional
  `scriptingDefinition: {path}` object. Its normalized project-relative `.sdef`
  path is capped at 1024 UTF-8 bytes; the source must exist, be non-empty, and
  be at most 1 MiB. The builder runs system-DTD validation before copying the
  basename to the Resources root, emits only `NSAppleScriptEnabled=true` and
  `OSAScriptingDefinition=<basename>`, and records source, basename, and byte
  count. Legacy manifests emit none of these fields. A direct resource name
  collision is rejected during manifest parsing.
- Runtime tests cover default/valid/unknown/malformed/absolute/remote/
  traversing/oversized-path declarations, missing/oversized/DTD-invalid files,
  collision rejection, exact JIT/AOT resource/plist/build-manifest output, and
  legacy absence. The test dictionary passes the installed system DTD.
- One follow-up formatter invocation used a repository-relative path while its
  working directory was already the runtime package and therefore found no
  file; it changed nothing. The corrected package-relative invocation formatted
  the test file. `make runtime-dart-test` then resolves dependencies, analyzes
  with no issues, and passes all ten runtime test groups.
- Dependency commit `41d6a75` (`Package validated scripting definitions`)
  records the generic runtime unit. Its required post-commit ROADMAP reread
  confirms the terminal-specific cached hierarchy/suspended-command package is
  now the first unfinished unit; product wiring remains later and untouched.
- Native-package design keeps the scripting surface dependency-owned and
  singleton because Cocoa Scripting is process/application global. ABI version
  1 is main-thread-only, accepts one atomically validated snapshot packet,
  exposes synchronous cached KVC wrappers through an `NSApplication` category,
  and returns queued versioned command packets only when Dart polls. It never
  invokes Dart from an AppKit callback.
- Custom `NSScriptCommand` subclasses validate and resolve only cached wrapper
  IDs, call `suspendExecution`, and are retained in a 16-entry pending table.
  Dart completion calls `resumeExecutionWithResult:` exactly once; 30-second
  native timeout, live-disabled snapshot replacement, and shutdown resume all
  remaining commands with typed errors. Product state is deliberately not
  mutated in this unit.
- The dictionary will expose application -> windows -> tabs -> terminals;
  stable text IDs, bounded title/cwd, selected/focused/frontmost relationships;
  new window, new tab, four-direction split, input text, focus, and standard
  close. It declares no terminal contents/history, arbitrary action, key/mouse,
  mutable title, launch-record, or Quick Terminal surface.
- The first strict Objective-C syntax pass failed only on five uses of the GNU
  omitted-middle `?:` convenience syntax, which the repository's `-Wpedantic
  -Werror` policy rejects. They are replaced with explicit nil conditionals;
  no ABI or lifecycle design is changed before rerunning the same compiler.
- After those replacements, Objective-C and C/C++ header checks pass. The first
  combined native-test compile then failed before compilation because
  `clang++ -std=c++20` cannot apply a C++ language standard to the separate
  `.m` translation unit. The capability source is compiled as Objective-C to
  its own test object, then linked with the Objective-C++ test, matching the
  repository's established per-language build boundaries.
- The first package-test run found two test-harness assumptions, not native
  implementation faults: the fake intentionally consumed its command buffer
  before the assertion inspected it, and standalone `dart run` executes outside
  the AppKit main-thread host so the native session correctly returned
  `WRONG_THREAD` rather than `NOT_INITIALIZED`. The fake retains a separate
  source buffer for copy verification, while the native-asset hook test now
  asserts the main-thread rejection; the Objective-C++ host test remains the
  owner/lifecycle proof on the process main thread.
- Final native review found that `DtasEnqueuePacket` and the AppleScript error
  adapter both incremented the rejected-command counter for the same failed
  enqueue. Counting is now owned by the public boundary: Cocoa command errors
  increment in `DtasRejectCommand`, while the test-only direct enqueue wrapper
  increments its own failures. Each rejected request is therefore observable
  exactly once without changing queue or suspension semantics.
- `make terminal-applescript-native-test` passes the C11/C++20 header checks,
  system-DTD SDEF validation, strict Objective-C dylib build, and process-main
  Objective-C++ hierarchy/queue/lifecycle tests. `make
  terminal-applescript-dart-test` resolves the package, analyzes with no
  issues, passes the deterministic facade/fake suite, and loads the compiled
  build-hook native asset with the expected non-AppKit-thread guard.
- The exact dependency full gate `CI=true DART_SUPPRESS_ANALYTICS=true make
  test` passes after the package and aggregate target are added. This includes
  scaffold validation, all bridge/runtime/renderer/PTy native suites, all Dart
  package analyses and tests, hello-window Kernel compilation, and current plus
  legacy FFI smoke tests; no existing regression failed.
- The rejected-command ownership fix is locked by summary assertions: the
  malformed/duplicate/disabled sequence records four rejections, and two queue
  cap failures record two. The focused native suite passes again after adding
  these exact-count checks.
- Completion review also found that the raw ABI could return an arbitrary
  cached object for an object-producing dictionary command, or no object at
  all. Native completion now derives the command kind from its retained packet:
  new-window/new-tab/split require a cached window/tab/terminal ID of the exact
  declared result kind, while input/focus/close reject object results. Wrong,
  missing, and correct object plus boolean-result cases are tested; the strict
  native suite passes after the hardening.
- The exact dependency full gate is rerun after the completion-type hardening
  and passes again end to end. The committed package candidate is therefore the
  same source exercised by both the focused native contract and the aggregate
  dependency regression matrix.
- Dependency commit `d15f4aa` (`Add bounded terminal AppleScript capability`)
  records the terminal-specific package, dictionary, native cache/command
  lifecycle, Dart facade, build hook, documentation, and focused plus aggregate
  verification. The adjacent dependency worktree is clean after the commit.
- The required post-commit ROADMAP reread selects dependency gates, terminal
  consumer declaration, and bundle audit as the next unfinished unit. That unit
  may declare and package the dependency/SDEF in terminal bundles and prove
  generic host behavior, but it must not initialize or connect live product
  state until the following product-integration item.
