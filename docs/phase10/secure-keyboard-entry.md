# Secure Keyboard Entry

## Status

- Phase: 10
- Task: Secure Keyboard Entry and automatic/manual indication
- Started: 2026-09-12
- State: active
- Current subtask: terminal policy, configuration, action, and lifecycle integration
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Protect sensitive terminal keyboard input with macOS Secure Event Input while
keeping the operating-system-global state balanced, observable, and temporary.
The user must be able to enable protection manually, automatic password-prompt
detection must apply only to the focused terminal, and the UI must clearly say
whether active protection is manual or automatic.

## Background

- Phase 5 completed physical key, IME, selection, paste, and read-only
  accessibility routing. Phase 7 completed pane/window/application ownership,
  menu/action projection, focus events, and deterministic Close/Quit. Phase 8
  added typed live configuration and Settings status. Phase 10 Quick Terminal
  added a retained hidden-window role and an exclusive global shortcut.
- Feature Matrix UI-07 and SEC-04 require a clear Secure Keyboard Entry
  indication and guaranteed release after abnormal pane/window/application
  teardown. ROADMAP also makes clean Secure Input release a Phase 10 exit
  condition.
- The current PTY dependency exposes content-free process-group snapshots but
  not current terminal echo mode. The AppKit dependency exposes focus and
  lifecycle events but has no Secure Event Input or per-surface indication API.

## Scope

- Add a content-free, same-call PTY terminal-mode observation that reports
  whether echo is enabled, with typed availability/error state and no terminal
  bytes, prompt text, command, environment, or process-name inspection.
- Add a main-thread-owned AppKit Secure Event Input resource that balances the
  Carbon API exactly once, yields whenever the application is inactive, can
  reacquire on activation, surfaces typed failure, and releases during normal,
  failed, finalizer, and application shutdown paths.
- Add a reusable native visual indicator attachable to a terminal content view,
  with distinct automatic/manual states and bounded accessible explanatory
  text. The indicator must not capture terminal input or change terminal grid
  geometry.
- Add typed live configuration for automatic detection and indication, a
  stable manual toggle action, checked native menu state, shared command-
  palette/keybind dispatch, focused-pane arbitration, Settings status, and
  deterministic ownership across ordinary and Quick Terminal windows.
- Verify automatic echo-off/on transitions, manual precedence, focus/window/
  application loss, reload, PTY exit, close/quit/failure cleanup, IME input,
  and Developer JIT/Release AOT product paths.

## Out of scope

- Reading password prompts or terminal contents, process names, command lines,
  environment variables, shell history, or accessibility text to infer secrets.
- Secure input on non-macOS platforms, arbitrary keyboard monitoring, password
  storage, credential entry UI, or permission prompting.
- Quick Look, Services, drag/drop, context menus, AppleScript, App Intents,
  complete accessibility audit, localization, and diagnostics bundle work from
  later Phase 10 items.
- Treating every no-echo TUI as certainly a password prompt. Automatic mode is
  a documented heuristic and remains user-disableable.

## Dependencies

- `dart_pty_macos` native session ownership and FFI process snapshot boundary.
- `dart_appkit` main-thread application lifecycle, generation-checked handles,
  native/fake bindings, `View`, menu projection, and deterministic shutdown.
- Terminal `TerminalSession`, hierarchy focus projection, action catalog,
  configuration authority/reload, Settings presenter, pane close/quit
  coordinators, and shipped-runtime harness.
- ADR-001 keeps native OS mechanisms in dependencies and product policy in
  Dart; ADR-002 forbids synchronous native-to-Dart reentry and keeps AppKit on
  the root main thread.

## Completion conditions

1. Automatic mode is enabled by default but only requests protection when the
   application and one live terminal pane are focused and that pane reports
   echo disabled. It releases on echo enabled/unavailable, focus loss, app
   deactivation, pane exit/removal, and shutdown.
2. Manual mode is toggled through one stable application action and remains
   desired across pane focus changes while the app is active. It yields on app
   deactivation and reacquires on activation until explicitly toggled off or
   final teardown.
3. Native Secure Event Input enable/disable calls are balanced exactly once per
   owned transition. Failures are typed and visible; external system state is
   observed but never cleared unless this process owns the matching enable.
4. Menu checked state, command palette, local keybind, Settings status, and a
   non-interactive terminal overlay expose disabled/automatic/manual/failure
   state without leaking terminal content or changing PTY bytes/grid geometry.
5. Focused/native/dependency tests, IME regression coverage, both shipped
   runtime paths, source/resource/bundle audits, exact `CI=true
   DART_SUPPRESS_ANALYTICS=true make test`, README/FEATURE_MATRIX/reference/
   evidence updates, final diff review, roadmap completion, and one standalone
   commit per ordered subtask pass.

## Validation approach

- Use fake PTY/AppKit bindings to exhaustively test unavailable/error, repeated
  transitions, manual/automatic precedence, inactive yielding, stale owners,
  and cleanup without mutating real global keyboard state.
- Native dependency tests exercise actual terminal flags and actual balanced
  Secure Event Input only inside short-lived, cleanup-guarded processes. Never
  leave a test-owned enable active after an assertion or failure.
- Product acceptance uses a deterministic real PTY that changes `ECHO`, native
  focus/application events, menu/shared action dispatch, the real Metal text
  input client, content-free counters, and bounded cleanup assertions.
- Run each dependency's focused and full gates before committing it, then the
  consuming terminal gate. Record failures and reruns below.

## Ordered subtasks

The item spans two dependency ABIs, asynchronous product policy, native visual
state, configuration/action surfaces, and shipped runtime acceptance. It is
split before code changes so each layer consumes only committed contracts.

1. **Content-free PTY terminal-mode observation substrate**
   - Extend `dart_pty_macos` with a versioned echo-mode observation in its
     same-call process snapshot and update public/fake/native tests.
   - Complete when echo on/off/unavailable, ABI/header/FFI, lifecycle safety,
     and the dependency plus consuming repository full gates pass.
2. **Balanced AppKit Secure Event Input and indication substrate**
   - Add one owned main-thread Secure Event Input controller plus generic
     per-view disabled/automatic/manual indication projection.
   - Complete when balance/failure/inactive/shutdown/finalizer, non-interactive
     accessible overlay, fake/native/legacy/public API, both host builds, and
     dependency plus consuming repository full gates pass.
3. **Terminal policy, configuration, action, and lifecycle integration**
   - Aggregate focused echo state with manual intent, connect live settings and
     shared action/menu/palette/keybind routes, and cover pane/window/Quick
     Terminal/application teardown.
   - Complete when deterministic controller, UI status/checked/overlay state,
     reload, IME/non-writing behavior, and focused product tests pass.
4. **Shipped-runtime acceptance and closure**
   - Exercise automatic/manual transitions and all cleanup paths with real
     PTY/AppKit/Metal in Developer JIT and Release AOT, then update docs and
     generated evidence and close the parent.
   - Complete when both runtime modes, full gates/audits, manual checklist,
     final diff review, roadmap state, and its standalone commit pass.

## Findings and decision log

- 2026-09-12: After commit `2cbeba3` (`Integrate retained Quick Terminal`),
  both terminal and adjacent `dart_appkit` worktrees are clean. ROADMAP reread
  selects Secure Keyboard Entry as the first remaining Phase 10 item; later
  native polish remains out of scope until this parent is committed.
- 2026-09-12: The installed macOS SDK states that Secure Event Input restricts
  keyboard delivery to the focused application, maintains a call count that
  requires exactly balanced disables, is not thread safe, must be disabled on
  application deactivation, and is automatically released on process crash
  only when no other application owns it. This makes a single main-thread
  process owner safer than independent pane-level native acquisitions.
- 2026-09-12: The pinned comparison implementation aggregates a manual global
  desire with focused per-surface desires, yields on app deactivation, and
  reacquires on activation. Its graphical indicator distinguishes active
  protection but its implementation is only a behavioral reference; this task
  additionally requires typed failures, strict owner balance, and abnormal
  teardown acceptance.
- 2026-09-12: The comparison configuration exposes automatic detection and
  indication as separate booleans. Automatic detection is explicitly heuristic
  and can interfere with accessibility software, so this product will likewise
  keep it live-disableable and will never infer from terminal text.
- 2026-09-12: Existing native PTY shutdown diagnostics already sample `termios`
  without terminal content, but the public same-call process snapshot omits it.
  Appending typed echo availability to that versioned snapshot is the smallest
  reusable boundary and lets the product refresh only on output/focus changes
  instead of polling or examining prompt contents.
- 2026-09-12: `dart_pty_macos` ABI v6 appends `terminal_echo_enabled` and a
  separate terminal-attribute error to the versioned process snapshot. The
  public Dart value uses nullable echo plus `hasTerminalAttributes`, while the
  fake can deterministically model enabled, disabled, and unavailable states.
  Exited sessions report `ENXIO`; no terminal local flags or other attributes
  need to cross the public boundary.
- 2026-09-12: Native capability tests observe default echo-on and live
  `stty -echo` from a real interactive PTY. Dart tests cover fake transitions,
  typed failure, real FFI echo-on, and ABI v6. Focused PTY contract/native/Dart
  tests, the exact `dart_appkit make test`, and the consuming exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` all passed. The dependency
  is committed as `1490829` (`Expose content-free terminal echo state`).
- 2026-09-12: `dart_appkit` now owns a singleton, generation-checked
  `SecureEventInput` resource on the AppKit main thread. It records retained
  desire independently from one successfully acquired Carbon reference,
  yields only that owned reference on application resignation, reacquires on
  activation, and routes explicit/finalizer/shutdown disposal through one
  prepare path. The observational global enabled bit is snapshot-only and is
  never treated as proof that this process may call disable.
- 2026-09-12: The additive ABI exposes a size-prefixed, content-free snapshot
  with desired/owned/system/last-OSStatus fields and a dedicated failure
  status. The public Dart facade maps unavailable, duplicate-owner, and system
  failure cases to typed `SecureEventInputException` values. All new FFI
  lookups are optional, so an older bridge returns unsupported rather than
  failing library initialization.
- 2026-09-12: `View.secureInputIndicatorState` projects hidden, automatic, or
  manual to one top/trailing native overlay. The overlay is accessible, never
  accepts first responder or hit testing, and constrains only itself inside the
  target view; native tests verify unchanged target bounds and a stable single
  overlay when changing modes. This keeps terminal grid and Metal drawable
  geometry under the product layout owner.
- 2026-09-12: The first Dart focused run found that promotion from the core
  `NativeBindings` interface to the independent optional secure interface was
  not retained at the call site, and a test referenced a nonexistent generic
  view handle hook. Explicit interface casts and inspection through the fake's
  single indicator value fixed those issues; the rerun passed analysis and all
  API tests.
- 2026-09-12: Native injection coverage passed idempotent acquisition,
  inactive yield, active reacquisition, typed disable failure/retry, external
  owner preservation, singleton enforcement, wrong thread/type/size, and
  shutdown balancing. Current/legacy FFI, C11/C++20 headers, public Dart API,
  accessible non-interactive indication, and cache-on-success tests passed.
  Exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed in both
  `dart_appkit` and this consuming repository; Developer JIT and Release AOT
  generic hosts also linked the changed bridge warning-clean. The dependency
  is committed as `8688a2f` (`Add balanced Secure Event Input ownership`).

## Next-subtask objective

Aggregate the focused live pane's content-free echo observation with explicit
manual intent in one product controller. Add live configuration defaults and
Settings status, a stable manual toggle action shared by menu, command palette,
and keybindings, and project automatic/manual/failure indication only to the
active terminal view. All pane/window/Quick Terminal/application loss and
reload/exit/quit paths must deterministically clear product desire; no terminal
text or PTY bytes may be inspected or written.
