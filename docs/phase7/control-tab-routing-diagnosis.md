# Control+Tab routing diagnosis

- Status: complete (diagnosis only)
- Date/environment: 2026-09-17, macOS arm64, main

## Purpose and scope

Identify why configured `control+tab=tab.select-next` does not switch tabs,
although the shared command-palette action does. This is a diagnosis request;
changing the terminal input path is not authorized by this task. The following
Settings navigation implementation is independent and must start after this
diagnosis is documented and committed.

## Dependencies, risks, acceptance and verification

Read README, ROADMAP, FEATURE_MATRIX, modal Settings and input ownership docs;
follow the configuration loader, exact physical chord resolver, application
action scheduler, and native first-responder event delivery. Preserve IME,
menu priority, exactly-once PTY input, and the existing working tree (clean at
start). Acceptance requires a reproducible causal distinction between raw
key delivery and palette dispatch, not just a parser-level assertion. Use
focused existing tests and a non-mutating native event diagnostic if needed.

## Findings

- `TerminalKeyBindingChord.fromEvent` ignores Function/CapsLock/NumericPad
  provenance, and recognizes physical Tab. The product key router resolves
  configured application actions before terminal encoding and schedules them
  through the shared dispatcher. The palette and tab actions share that
  dispatcher, so a valid chord reaching this router should switch tabs.
- The renderer view passes keyDown through `NSTextInputContext.handleEvent`.
  `doCommandBySelector` forwards the original raw key, but `insertText` posts
  committed text without original modifiers/key code. Committed text goes
  directly to `pane.insertText`, bypassing configurable key bindings.
- Settings NORMAL/SEARCH are Dart-only; INSERT delegates native editing.
  Their fast-navigation change is tracked separately, not a terminal routing fix.

## Confirmed cause

- The user's default root config contains exactly the two recommended Tab
  bindings. Only matching `keybind` lines were inspected; unrelated values
  and private content were not printed or recorded.
- `TerminalNativeHierarchy` creates terminal windows with
  `KeyEventRouting.appKitOnly`. Generic `DaWindow.sendEvent` in adjacent
  `native/bridge/src/TextView.mm` calls `super sendEvent` in that mode. AppKit
  consumes Control+Tab / Shift+Control+Tab as key-view navigation before the
  first responder receives `keyDown`. The renderer input context is therefore
  not reached at all for these chords. Its commit-versus-raw distinction is
  a related constraint, but **not the cause observed in this reproduction**.
- A standalone AppKit probe used a key-capable NSView as the NSWindow's first
  responder and sent native keyDown events through `NSWindow.sendEvent`.
  For each case the responder was restored first; the window had no menus or
  product action bindings. Output:

  | chord | hardware code | flags | view keyDown deliveries |
  | --- | --- | --- | --- |
  | Tab | 48 | 0 | 1 |
  | Control+Tab | 48 | 262144 | 0 |
  | Shift+Control+Tab | 48 | 393216 | 0 |
  | Control+K | 40 | 262144 | 1 |

  Probe command was `swift -e` importing AppKit, subclassing NSView with
  `acceptsFirstResponder = true` and a counted `keyDown`, creating a titled
  NSWindow, and passing `NSEvent.keyEvent` to `window.sendEvent`. It exited 0
  and closed its temporary window. No repository source or user config was
  changed. This reproduces the native pre-delivery boundary independently
  of resolver/parser/scheduler behavior.
- The previous advice that these bindings alone would work was incorrect.
  The palette succeeds because its action bypasses that native key boundary.

## Fix boundary and alternatives

Repair requires an explicit pre-AppKit delivery path for configured shortcuts
(or a generic opt-in native equivalent) while preserving normal native/IME
handling, menu priority, and exactly-once delivery. Globally making terminal
windows Dart-only would break first-responder text input; it is not a safe
workaround. A non-Tab chord that reaches the view avoids this particular
AppKit interception, but has not been claimed as a manually tested user setup.
The user was asked asynchronously whether to authorize the routing fix.
Until authorized, this task changes diagnosis records only; terminal behavior
is unchanged.

## Verification

- Native AppKit event probe: reproduced the four-case table above, exit 0.
- `dart run test/terminal_key_binding_test.dart`,
  `test/terminal_session_configuration_test.dart`, and
  `test/terminal_native_hierarchy_test.dart`: all exit 0. Existing parser,
  shared tab actions, config and fake event delivery pass; fake injected events
  bypass `NSWindow.sendEvent` and cannot detect this interception.
- Reviewed docs-only diff; no product/config/dependency changes in this task.
