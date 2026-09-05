# Exclusive key event routing

- Status: complete
- Started: 2026-09-05
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 2 `AppKit key event routing policy とterminal専有入力`
- Related decisions: `docs/adr/ADR-001-dart-native-boundary.md` and
  `docs/phase2/persistent-pane-lifecycle.md`

## Purpose

Remove the system beep produced for every terminal key press while keeping key
delivery policy reusable and explicit in `dart_appkit`. A consuming application
must be able to choose whether unhandled key events continue through AppKit's
normal responder path after Dart event routing.

## Background and confirmed observations

- `DaWindow.sendEvent:` currently posts every key event to Dart and then always
  calls `[super sendEvent:event]`.
- The temporary terminal `DaView` accepts first-responder status but does not
  implement an editing or key-command responder. Normal AppKit dispatch therefore
  reaches an unhandled responder path and produces the system beep.
- The reported failing Control-D run emitted three ordered pairs of
  `eofRequested` and `eofWriteAccepted`. The GUI key event was recognized and
  each `0x04` write was admitted by the PTY. No `nativeExitObserved` followed.
  This rules out the beep-producing duplicate responder dispatch as the direct
  cause of that particular EOF failure and locates it after PTY write admission,
  in foreground-process, zsh, or terminal-mode behavior.
- The repeated real-PTY Control-D test bypasses AppKit key dispatch and uses
  `zsh -f`, an empty prompt, and `unsetopt ignoreeof`. It proves the controlled
  PTY EOF path, not the production login-shell state or GUI input path.

## Scope

1. Add a public, typed, per-window key-event routing policy to `dart_appkit`.
2. Preserve the existing Dart-and-AppKit behavior as the compatibility default.
3. Add a Dart-exclusive mode that preserves native menu key-equivalent handling,
   posts remaining key events to Dart, and does not forward them to the ordinary
   AppKit responder chain.
4. Adopt the exclusive mode in Dart Terminal before showing its window.
5. Cover native dispatch, Dart API/failure caching, legacy-symbol behavior, and
   product bundle behavior with automated tests.

## Out of scope

- Changing Control-D into an unconditional application-exit command.
- Changing zsh options, user startup files, job-control behavior, or foreground
  application terminal modes.
- `NSTextInputClient`, marked text, IME candidate placement, terminal key
  encoding, or general keybinding arbitration scheduled for later phases.
- VT parsing, screen-grid correctness, scrolling, or renderer work.

## Ordered subtasks

1. Implement and verify the reusable `dart_appkit` routing capability, including
   its C ABI, native policy, public Dart enum/property, compatibility fallback,
   tests, and library documentation.
2. Set the Dart Terminal window to exclusive Dart routing, add product-level
   assertions/audits, update user-facing documentation and the feature matrix,
   then run the proportional Developer JIT and Release AOT verification.

## Completion criteria

1. A new window defaults to routing key events to both Dart and normal AppKit
   responder processing.
2. A caller can select Dart-exclusive routing through a typed public interface.
3. In exclusive mode, a non-menu key event is posted exactly once to Dart and is
   not delivered to the content view's normal key responder.
4. AppKit main-menu key equivalents remain functional in exclusive mode and are
   not also emitted as terminal input.
5. Invalid native policy values, wrong handles, wrong threads, missing legacy
   symbols, and failed setters are deterministic and do not corrupt cached state.
6. Dart Terminal selects exclusive routing and its normal menu, keyboard, PTY,
   close, Developer JIT, and Release AOT regressions pass.
7. Both repositories contain only task-related changes and complete the ordered
   subtasks in separate commits.

## Verification plan

- `dart_appkit`: native C/C++ header checks, bridge dispatch tests, Dart format,
  analysis, API/fake-binding tests, legacy FFI smoke, and full `make test`.
- `dart_terminal`: format, static analysis, unit/real-PTY tests, source audit,
  Developer JIT and Release AOT bundle audits and GUI integration.
- Manual follow-up: type ordinary text and Control-D in the interactive product
  to confirm the system beep is absent. Automated tests verify the underlying
  responder suppression because audible output is not a stable test interface.

## Findings and decisions

### 2026-09-05 — task start

- The routing choice belongs to `dart_appkit`, not terminal application native
  code, because `DaWindow` currently owns both Dart event publication and AppKit
  responder dispatch.
- The policy is per window. Different windows in one application may contain a
  conventional AppKit editor or a raw terminal surface and require different
  responder behavior.
- The compatibility default remains dual routing. Exclusive behavior must be an
  explicit application choice so existing AppKit controls do not silently lose
  native key handling.
- An asynchronous Dart event cannot return a synchronous handled/unhandled value
  to AppKit. The routing choice must therefore be configured before dispatch,
  rather than pretending each Dart listener can acknowledge an individual key.

### 2026-09-05 — reusable AppKit capability

- `dart_appkit` added a per-window `KeyEventRouting` enum and property backed by
  the additive `DaKeyEventRouting` / `da_window_set_key_event_routing` C ABI.
  Dual Dart/AppKit routing is the explicit native and Dart default.
- In Dart-exclusive mode the native main menu receives key-equivalent priority.
  Remaining key-down/up events are posted once to Dart and return before the
  ordinary `NSWindow` responder path.
- Native tests proved default pass-through, exclusive responder suppression,
  menu consumption, invalid values, handle/type/thread validation, and stale
  handles. Dart tests proved cached state, idempotence, failure preservation,
  public export, and the older-bridge unsupported result.
- Focused contract/native and Dart/FFI tests passed, followed by the complete
  `dart_appkit make test` regression. The capability was committed in the
  adjacent repository as `6fa96b8 Add configurable key event routing`.

### 2026-09-05 — terminal adoption and focused verification

- The terminal window now selects `KeyEventRouting.dartOnly` after content-view
  attachment and before close deferral or showing the window. No terminal-owned
  native source was introduced.
- Startup emits the fixed, content-free
  `NATIVE_KEY_EVENT_ROUTING mode=dart-only` observation only after the native
  setter succeeds. The normal integration harness requires it in both runtime
  modes, so a stale bridge or missing symbol fails before acceptance.
- `make test` passed formatting, static analysis, unit tests, fake PTY tests, and
  the repeated real-PTY suite. The Dart-only source audit passed with 78 tracked
  application files and zero native application sources.
- Fresh M1/arm64 Developer JIT and Release AOT bundles passed their Dart-only
  bundle audits. Their normal GUI integrations passed in 2,402 ms and 1,866 ms,
  including custom-view attachment, menu actions, close confirmation, clean PTY
  shutdown, worker reaping, and the new routing observation.
- Automated tests establish the exact responder suppression that removes the
  beep. Human audible confirmation remains useful because CI has no stable
  interface for observing system sound output.

### 2026-09-05 — final regression

- `make RUNTIME_ARCH=arm64 runtime-verify` passed after the final documentation
  and product changes. Format, analysis, Dart tests, the 24-generation real-PTY
  Control-D regression, the 78-file Dart-only source audit, and both bundle
  audits remained clean.
- Developer JIT and Release AOT normal GUI integrations passed in 2,390 ms and
  1,826 ms. Both required the `dart-only` routing observation and retained the
  custom-view, menu/pasteboard, deferred close, clean PTY, worker-reap, and
  root-exit contracts.
- All lifecycle scenarios retained their expected 0/64/70/75 statuses. Bounded
  traffic retained 384 deterministic backpressure observations per mode, and
  both 1,000-iteration resource suites retained the 12-handle baseline with a
  peak of 14.
- Shutdown-fault suites passed in both modes. The deliberately missing PTY exit
  notification remained bounded and classified as status 75 in 1,964 ms and
  1,792 ms.
- Final diff review found no application native source or unrelated change. The
  accepted-no-exit Control-D observation remains separately tracked in
  `docs/phase2/ctrl-d-accepted-no-exit-investigation.md` and is intentionally
  not hidden by completing the beep/routing task.

### 2026-09-05 — manual audible acceptance

- The user confirmed after running the product that the per-key system beep is
  gone. This closes the manual audible follow-up; the accepted-but-no-exit
  Control-D behavior remains the separate investigation task linked above.
