# Quick Terminal and global shortcut

## Status

- Phase: 10
- Task: Quick Terminal and global shortcut
- Started: 2026-09-12
- State: active
- Current subtask: exclusive global shortcut registration/event substrate
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Provide one singleton, session-preserving Quick Terminal that can be shown or
hidden from another application with an explicitly configured global shortcut.
It must appear on the selected screen, preserve terminal resolution and owner
boundaries, support bounded enter/exit animation and focus-loss autohide, and
fail visibly without acquiring broader keyboard-monitoring authority.

## Background

- Phase 7 completed normal window/tab/split ownership, native fullscreen,
  screen migration, restoration, reopen, actions, menus, and command palette.
- The Phase 10 roadmap item maps to Feature Matrix UI-06, whose acceptance unit
  includes Quick Terminal, global shortcut, screen selection, and animation.
- The current product has no Quick Terminal role, no global shortcut API, and
  no overlay-window presentation primitive. Normal terminal windows are all
  restorable and native event protocol v7 has no application-scoped shortcut
  event.
- The pinned comparison behavior describes a singleton whose terminal state is
  retained while hidden, is not restored across application launches on macOS,
  and has no default global binding. The screen selector supports the keyboard-
  focus screen, mouse screen, and menu-bar screen; animation duration can be
  zero and macOS defaults to focus-loss autohide.

## Scope

- Add a stable toggle action plus typed, generated Settings/configuration
  controls for opt-in shortcut registration, screen selection, animation
  duration, and focus-loss autohide.
- Give the logical hierarchy an explicit singleton Quick Terminal window role,
  while preserving one UI-root owner, pane/session limits, and deterministic
  teardown.
- Add reusable `dart_appkit` mechanisms for an exclusive system hot key, its
  asynchronous immutable event, current-screen selection, overlay window
  behavior, ordering, and bounded frame animation.
- Lazily create one Quick Terminal pane, retain it while hidden, exclude it from
  restoration, route the native/global and menu/palette toggle through the same
  serialized action, and keep menu/settings state observable.
- Verify conflict, unsupported, registration/reload/unregistration, repeated
  toggle, stale transition, selected-screen geometry, reduced/zero animation,
  autohide, ordinary-window independence, and teardown paths in unit, native,
  Developer JIT, and Release AOT tests.

## Out of scope

- General event taps, observation or rewriting of arbitrary system keyboard
  input, Accessibility permission prompting, multiple global bindings, or
  global bindings for arbitrary pane actions.
- Multiple Quick Terminal instances, Quick Terminal tabs on macOS, native
  fullscreen, restoration across launch, or changes to normal window/tab/split
  behavior.
- Secure Keyboard Entry, Quick Look, Services, drag/drop, context menus,
  AppleScript, App Intents, notifications, the complete accessibility pass,
  localization, or diagnostics work from later Phase 10 roadmap items.

## Dependencies

- `TerminalApplicationState`, `TerminalNativeHierarchyAdapter`, the product
  pane factory, close/quit coordinators, action catalog, configuration reload,
  Settings editor, restoration lifecycle, and shipped-runtime harness.
- `dart_appkit` generation-checked handles, main-thread-only synchronous calls,
  immutable versioned events, native `Window`, screen metadata, and explicit
  disposal.
- ADR-001 keeps product/session policy in Dart and OS registration/window
  mechanisms in `dart_appkit`; ADR-002 keeps the UI root on AppKit's main
  thread and forbids synchronous native-to-Dart reentry.

## Completion conditions

1. No shortcut is registered by default. A configured shortcut can be enabled,
   changed, disabled, and unregistered; unsupported keys and OS conflicts are
   typed, observable failures that leave no partial registration or keyboard
   monitor.
2. Exactly one non-restorable Quick Terminal logical window may exist. Its
   pane/session survives hide/show, normal windows remain independent, and all
   native/pane/global-shortcut owners are released once at shutdown.
3. The selected screen is resolved at every show, geometry is clamped to its
   current visible frame, backing scale is projected before the first frame,
   and enter/exit animation is bounded and disableable.
4. Menu, command palette, Settings/effective configuration, safe live reload,
   focus-loss autohide, shortcut conflict/failure feedback, and both shipped
   runtime paths are covered without expanding terminal-byte or native-handle
   authority.
5. Generated references/evidence, README/FEATURE_MATRIX, focused tests,
   `dart_appkit` gates for dependency changes, exact `CI=true
   DART_SUPPRESS_ANALYTICS=true make test`, diff review, roadmap completion,
   and one standalone commit per subtask pass.

## Validation approach

- Keep key parsing, window-role invariants, lifecycle transitions, screen/frame
  policy, and configuration reload deterministic and fake-testable.
- Native tests cover OSStatus mapping, duplicate/exclusive registration,
  event routing/version negotiation, main-thread ownership, screen fallbacks,
  window collection behavior, animation endpoints, and cleanup.
- Product acceptance uses a conflict-free test shortcut and synthetic local
  invocation where necessary, records content-free machine lines only, and
  verifies both Developer JIT and Release AOT bundle paths.
- Run focused format/analyze/tests after each layer, then every repository gate
  required by the owning project. Record failures and reruns below.

## Ordered subtasks

The parent crosses typed product policy, a public native ABI/event protocol,
AppKit window presentation, restoration, and two shipped runtime modes. It is
therefore split before implementation; each child consumes only committed
contracts from the previous child.

1. **Typed configuration, action, and logical lifecycle contract**
   - Add the stable toggle action, opt-in shortcut/screen/animation/autohide
     settings, immutable product projection, and singleton/non-restorable
     Quick Terminal window role.
   - Complete when grammar/default/recovery/live-policy, generated references,
     action search/menu metadata, hierarchy invariants, and exact repository
     gate pass without adding native behavior.
2. **Reusable exclusive global shortcut substrate**
   - Add a generation-owned `dart_appkit` hot-key resource backed by the
     system registration API, asynchronous application event, typed OS failure,
     live replacement safety, and deterministic unregister/shutdown behavior.
   - Complete when C header, native implementation, FFI facade, fake/native
     tests, legacy event negotiation, Developer/Release host tests,
     `dart_appkit` full gate, and the consuming terminal full gate pass.
3. **Reusable Quick Terminal window/screen/presentation substrate**
   - Add typed current-screen selection and generic overlay window presentation
     controls for level/Spaces/focus/show/hide/frame animation, with no terminal
     policy in `dart_appkit`.
   - Complete when multi-screen coordinates, missing-screen fallback,
     collection behavior, animation endpoints/interruptions, reduced/zero
     duration, close/hide, and cleanup pass native/Dart/host tests plus both
     repositories' gates.
4. **Product integration, shipped-runtime acceptance, and closure**
   - Lazily create and retain one Quick Terminal pane/window, connect the toggle
     action and configured global shortcut, update live configuration safely,
     exclude the role from restoration, implement autohide and user-visible
     failure state, and exercise real terminal ownership in both runtime modes.
   - Complete when focused and full validation, source/resource/bundle audits,
     README/FEATURE_MATRIX/reference/evidence updates, final diff review,
     parent completion, and its standalone commit pass.

## Findings and decision log

- 2026-09-12: After commit `e02dc61` (`Add keyboard controls for split
  dividers`), the worktree and adjacent `dart_appkit` dependency are clean.
  ROADMAP reread selects the first Phase 10 item; Secure Keyboard Entry and all
  later native-polish work remain out of scope until this parent is committed.
- 2026-09-12: The supplied split-pane regression work is complete in commits
  `7dedc83`, `77ea375`, and `e02dc61`; it does not block the new task.
- 2026-09-12: Local architecture inventory confirms reusable AppKit mechanisms
  belong in `dart_appkit`, while Quick Terminal role, configuration, geometry,
  action availability, restoration exclusion, and session lifetime belong in
  this repository.
- 2026-09-12: The official Ghostty action/configuration reference confirms a
  retained singleton, no default binding, `main|mouse|macos-menu-bar` screen
  selection, zero-disableable animation, macOS autohide default, and no macOS
  Quick Terminal tabs. These are behavior references only; implementation and
  wording remain independent.
- 2026-09-12: Apple documents `NSScreen.mainScreen` as the screen containing the
  keyboard-focus window, `NSEvent.mouseLocation` as global screen coordinates,
  the first `NSScreen.screens` entry as the menu-bar screen, and `visibleFrame`
  as the current safe content area that must not be cached.
- 2026-09-12: The installed macOS SDK documents `RegisterEventHotKey` as a
  virtual-key/modifier registration and `kEventHotKeyExclusive` as the mode
  that reports `eventHotKeyExistsErr` on an exclusive conflict. The API is not
  thread safe, so registration and removal stay on the AppKit owner. In
  contrast, the SDK states that global `NSEvent` key monitors require
  Accessibility trust. The exclusive hot-key API is adopted because this task
  needs one explicit chord, consumption, conflict reporting, and no broad key
  observation or permission prompt.
- 2026-09-12: Safe product defaults are adopted before code changes: shortcut
  `none` (feature disabled), screen `main`, animation duration `0.2` seconds,
  and autohide `true`. Position and extent use a fixed top-edge presentation in
  this acceptance unit; adding a larger size/position grammar is not required
  by UI-06 and would expand the task beyond the documented roadmap scope.
- 2026-09-12: The first subtask adds four live options to the typed schema:
  `quick-terminal-shortcut` (`none` by default and at least one modifier),
  `quick-terminal-screen` (`main` by default),
  `quick-terminal-animation-duration` (`0.2`, bounded to 0 through 5 seconds),
  and `quick-terminal-autohide` (`true`). The immutable product projection now
  carries all four values, and generated Settings/configuration output grows
  from 38 to 42 options.
- 2026-09-12: `application.toggle-quick-terminal` is a stable searchable
  application action with no local menu shortcut. Leaving the action unbound
  avoids a duplicate local dispatch when an eventual system-wide registration
  fires and preserves the opt-in default.
- 2026-09-12: The application hierarchy now distinguishes ordinary and Quick
  Terminal windows. It rejects a second Quick Terminal and any tab creation in
  that role before allocating a pane. Restoration filters the role before
  requesting placement or pane launch state; if no ordinary window remains,
  capture fails instead of serializing the Quick Terminal accidentally.
- 2026-09-12: The pure presentation lifecycle tracks hidden/showing/visible/
  hiding/disposed states with immutable generation tokens. A repeated toggle
  supersedes in-flight work, and completion for an older token is ignored.
  Autohide uses the same serialized hide path; reset and disposal invalidate
  outstanding native completions.
- 2026-09-12: Initial `dart format` changed the intended files but exited 1
  because analytics attempted to touch
  `~/.dart-tool/dart-flutter-telemetry-session.json` outside the sandbox.
  Rerunning with `CI=true DART_SUPPRESS_ANALYTICS=true` completed with exit 0.
  The first focused test attempt similarly failed before test execution when
  the Metal hook could not write its clang module cache under `~/.cache`.
  The approved cache-writing rerun passed, and subsequent focused action,
  hierarchy, lifecycle, restoration, configuration-reference, and
  action-reference tests all exited 0.
- 2026-09-12: Generated configuration/action references and Phase 7 source
  hashes were refreshed. `dart analyze lib test tool` reported no issues.
  The exact required gate `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  passed: configuration reference reported 42 options (6 live, 36
  new-session), the action reference reported 26 application actions, all
  compatibility/evidence checks passed, formatting changed 0 files, analysis
  found no issues, Phase 9 stress passed, and the unified Dart test runner
  printed `dart_terminal tests passed`.
- 2026-09-12: The second subtask adds `dart_appkit` event protocol v8 and an
  owned `GlobalHotKey` resource using exclusive `RegisterEventHotKey`. The
  public boundary accepts physical macOS key codes 0..127 with a nonempty
  Shift/Control/Option/Command mask, maps an occupied chord separately from
  other OS registration failures, posts a payload-free generation-checked
  pressed event, and unregisters before handle reuse on explicit, finalizer,
  and shutdown release paths. It does not install a global event monitor or
  request Accessibility/Input Monitoring authority.
- 2026-09-12: `dart_appkit` focused native/encoder/Dart/current+legacy FFI tests
  and exact full `make test` passed. Both generic runtime binaries also linked
  the updated bridge warning-clean via `make runtime-jit-runner
  runtime-aot-runner`. The reusable dependency is committed independently as
  `f6721af` (`Add exclusive global hot keys`).
- 2026-09-12: Advancing the dependency protocol from v7 to v8 required the
  consuming shipped-runtime assertions to expect the negotiated current
  version while retaining theme's minimum requirement at v7. Product theme
  and scroll evidence now print the negotiated value rather than freezing the
  current version. The Phase 7 acceptance source hashes were regenerated; the
  first sandbox run was blocked only by the Metal compiler's user cache, and
  the approved rerun completed successfully.
- 2026-09-12: The first terminal full-gate run stopped during parser-trace
  compilation because the new sealed `GlobalHotKeyPressedEvent` made two
  application-event switches non-exhaustive. The product does not register or
  act on the event until the final integration subtask, so both current sinks
  explicitly ignore it while preserving exhaustive compile-time coverage.
  Phase 7 source hashes were regenerated once more from that final source.
- 2026-09-12: The exact consuming gate `CI=true
  DART_SUPPRESS_ANALYTICS=true make test` then passed. All generated-reference,
  compatibility, differential, application-matrix, terminfo, shell-integration,
  format, and analyze checks passed; the Phase 9 stress harness completed and
  the unified runner printed `dart_terminal tests passed`. The exclusive
  registration substrate is therefore complete without prematurely adding
  Quick Terminal window presentation or product registration behavior.
