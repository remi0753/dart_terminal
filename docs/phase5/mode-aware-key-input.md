# Phase 5 — mode-aware key encoding and configurable keybindings

- Status: in progress
- Date: 2026-09-06
- Scope: first Phase 5 production-input roadmap item
- Related: IN-01, IN-02, IN-09, UI-05, CAP-08

## Purpose

Replace the current ad-hoc AppKit key-code switch with a typed, bounded input
pipeline that preserves physical key, produced text, modifiers, and repeat;
encodes legacy xterm input according to terminal modes; and resolves explicit
configurable bindings without duplicate terminal or menu delivery.

## Background

The live application currently recognizes a small set of macOS virtual key
codes directly in `TerminalKeyEventRouter`. Cursor keys always emit normal CSI,
Control-C/Z/backslash call signal helpers, Control-D calls the tracked EOF path,
Command-modified events are discarded, and remaining printable `characters`
are written as UTF-8. This supports a basic shell but cannot represent DEC
application cursor/keypad modes, modified function/navigation keys, binding
conflicts, explicit unbinding, or passthrough policy.

The AppKit v4 event already transports the required independent fields:
`keyCode`, `characters`, `charactersIgnoringModifiers`, stable modifier bits,
and `isRepeat`. Dart-only per-window routing gives native menu key equivalents
priority before non-menu key events reach Dart, so terminal input must not
re-dispatch menu commands.

## Scope

- Track DEC application cursor-key and application keypad modes, including
  parser transitions and reset behavior.
- Define a typed physical-key/modifier/event model independent of AppKit.
- Encode bounded UTF-8/control/escape/navigation/function/keypad byte sequences
  with xterm legacy modifier parameters and DEC mode awareness.
- Define immutable configurable bindings, a stable action registry, exact
  modifier matching, duplicate/conflict rejection, explicit unbound and
  passthrough outcomes, and deterministic precedence.
- Adapt AppKit events once at the application boundary and send encoded bytes or
  resolved actions once to the owning live pane/PTY.
- Preserve the special tracked Control-D lifecycle observation while making
  ordinary control/navigation input byte-correct.

## Out of scope

- `NSTextInputClient`, dead-key/IME composition ownership, candidate placement,
  and the full US/JIS/manual input matrix; these are the next roadmap items.
- Kitty keyboard, modifyOtherKeys, and progressive enhancement, which remain
  Phase 9 work.
- Mouse, selection, scrolling, clipboard, hyperlink, accessibility, and the
  Phase 8 config-file loader or settings UI.
- A command palette or the full Phase 7 application action/menu surface.

## Ordered subtasks

1. Add DEC keyboard-mode state and a pure-Dart bounded xterm key encoder with
   table-driven unit coverage for normal/application modes, modifiers,
   navigation/function/keypad keys, UTF-8, control mappings, and invalid input.
2. Add a typed immutable keybind engine with a stable minimal action registry,
   exact matching, deterministic precedence, duplicate/conflict rejection,
   explicit unbound/passthrough semantics, and bounded configuration size.
3. Replace the product router's key-code switch with one AppKit adapter and the
   new resolver/encoder, add a generic bounded pane input write, retain tracked
   Control-D behavior, and prove the Developer JIT/Release AOT real-PTY path.

The parent roadmap item remains incomplete until all three commits and the
combined product verification succeed.

## Dependencies and ownership

- `TerminalScreenSet` owns terminal modes derived from PTY output; input reads a
  synchronous immutable snapshot from the same application isolate.
- The pure input model and keybind engine remain Dart-owned and have no AppKit
  or PTY dependency. AppKit virtual-key mapping is isolated to the application
  adapter.
- `TerminalPane` records user interaction and delegates exactly one bounded byte
  write to its `TerminalPaneSession`; `TerminalSession` remains the sole PTY
  writer and backpressure observer.
- Native menus remain authoritative for recognized Command key equivalents
  because `dart_appkit` consumes those before publishing terminal key events.

## Completion criteria

- DECCKM and DECPAM/DECPNM transitions change emitted cursor/keypad bytes and
  reset deterministically.
- The encoder covers Return/Tab/Backspace/Escape, navigation, Insert/Delete,
  Page Up/Down, F1–F12, keypad, Unicode text, Control mappings, Alt prefix, and
  xterm modifier parameters without an unbounded output path.
- Keybind definitions are typed, bounded, immutable, conflict-checked, and can
  express action, unbound, and passthrough behavior with documented precedence.
- Physical key, produced text, modifiers, and repeat remain distinct through
  AppKit adaptation; a handled event reaches the pane/PTY at most once.
- Focused tests, full tests/analysis/format, source audit, Developer JIT and
  Release AOT integrations, bundle audits, and proportional real-PTY keyboard
  acceptance pass.
- ROADMAP, README, FEATURE_MATRIX, and this memo reproduce the final behavior;
  each ordered subtask has its own commit and both repositories are clean.

## Verification plan

- Add table-driven unit tests for every encoder family and mode/modifier branch.
- Add parser/screen-set tests for DECCKM, DECPAM, DECPNM, reset, and mode query
  where applicable.
- Add keybind construction/resolution boundary, conflict, and precedence tests.
- Add fake-session product routing tests that assert exact bytes and no duplicate
  action/write; extend packaged real-PTY acceptance with mode-sensitive input.
- Run `make test`, `make runtime-source-check`, targeted real-PTY tests,
  `runtime-terminal-display-integration`, and `runtime-bundle-audit` in both
  product modes as appropriate to each subtask.

## Investigation log

- 2026-09-06: `dart_terminal` was clean at `e609b88`; adjacent `dart_appkit`
  was clean at `d55bd6e`. The first unchecked roadmap item is this Phase 5
  keyboard/keybind task.
- 2026-09-06: the current router is embedded at the end of
  `terminal_application.dart`. It switches directly on macOS virtual key codes,
  always emits normal cursor CSI, drops Command and Function input, filters
  AppKit private-use characters, and has no independent resolver result.
- 2026-09-06: `AppKitKeyEvent` already exposes key code, produced and
  modifier-independent text, seven stable modifier bits, and repeat. No native
  ABI change is required for the first integration target.
- 2026-09-06: the screen model currently tracks origin, insert, auto-wrap,
  reverse-video, and horizontal-margin modes. DEC private mode 1 and ESC `=`/`>`
  are currently counted as unsupported, so application cursor/keypad state must
  be added before the encoder can be meaningfully mode-aware.
- 2026-09-06: pane/session APIs expose individual legacy movement methods but no
  generic encoded input write. The session already has a bounded private `_write`
  path with PTY backpressure accounting, so integration should expose that path
  rather than duplicate queue ownership.

## Design decisions

- Use legacy xterm encoding for Phase 5 and keep Kitty/modifyOtherKeys out of the
  version-one encoder. Modified special keys use the conventional xterm
  `1 + Shift + 2*Alt + 4*Control` parameter.
- Match keybindings by physical key plus an exact Shift/Control/Option/Command
  subset; Caps Lock, numeric-pad classification, Function provenance, produced
  text, and repeat remain event data rather than silently changing a binding.
- Native menu handling remains ahead of Dart keybinding resolution. Unrecognized
  Command combinations default to consumed unless explicitly configured for
  passthrough, preventing shell input from receiving accidental menu chords.

## Verification results

### 2026-09-06 — DEC modes and bounded xterm encoder

- `TerminalScreenSet` now owns immutable snapshots of DECCKM application-cursor
  and DECPAM/DECPNM application-keypad state. Parser handling for DEC private
  mode 1, ESC `=`, ESC `>`, DECRQM mode 1, and RIS is implemented. The modes
  survive alternate-screen activation and grid resize and reset together on
  RIS; mode-only transitions increment the screen-set transition generation
  without fabricating cell damage.
- The new platform-independent input event keeps physical key, produced text,
  unmodified text, seven modifier facts, and repeat separate. The initial key
  domain includes US positions, navigation, F1–F20, keypad, and JIS-specific
  physical positions needed by the later platform adapter/matrix.
- `TerminalKeyEncoder` produces at most 256 bytes per event or throws a typed
  limit exception. It covers printable UTF-8, traditional Control mappings,
  Option escape-prefix text, Return/Tab/Backspace/Escape, cursor/application
  cursor, Home/End, edit/navigation keys, F1–F20, normal/application keypad, and
  xterm Shift/Alt/Control modifier parameters. Command input has no implicit
  PTY bytes; Kitty keyboard and modifyOtherKeys remain out of scope.
- The first sandboxed `dart format` formatted the two new files successfully but
  returned nonzero when Dart telemetry could not update its home-directory
  session file. The host-access `make test` format gate later confirmed all 108
  Dart files were already formatted.
- The first full regression exposed intentional corpus differences rather than
  encoder failures: four formerly unsupported keyboard-mode sequences became
  supported in each of the recorded less and Vim streams. Recorded shell's four
  unrelated unsupported sequences remained unchanged after a trial update was
  reverted. The reviewed snapshots now record less `4 -> 0` and Vim `19 -> 15`.
- The parser corpus again passes all 8 cases, 1,421 input bytes, and 1,437 split
  runs with aggregate hash `780471851`. The unchanged 837 property/fuzz
  executions and 66,675 parsed bytes now have deterministic state hash
  `1721827890`, reflecting the new supported-sequence counts.
- The focused encoder/parser test passed. Final `make test` passed VT table
  freshness, formatting of 108 files with zero changes, static analysis with no
  issues, and the complete test suite. `make runtime-source-check` passed with
  `tracked=194` and `native_sources=0`.
- The first ordered subtask is complete. The parent remains in progress pending
  the typed keybind engine and AppKit-to-PTY integration commits.

### 2026-09-06 — typed configurable keybind engine

- Added four stable action IDs with explicit configuration names for the
  existing EOF, interrupt, suspend, and quit-signal pane operations. Unknown
  names return no action instead of falling back to a different command.
- A binding chord contains one non-unknown physical key and the exact
  Shift/Control/Option/Command subset. Caps Lock, numeric-pad and Function
  provenance, produced text, and repeat remain available on the event but do not
  silently alter chord identity.
- The engine copies default and override iterables, rejects an unknown physical
  key, detects duplicate chords within either layer with the exact layer and
  indices, and stops iteration at 1,024 total definitions. Its resulting map is
  immutable and bounded.
- Override actions and explicit passthrough replace defaults. `unbind` removes
  an inherited binding and produces `noMatch`, while passthrough remains a
  distinct matched result for the application router. This keeps config-layer
  semantics observable without coupling the engine to PTY writes.
- The standard zero-config binding contains only Control-D -> tracked EOF.
  Ordinary Control sequences remain encoder input, which preserves terminal
  termios/application semantics rather than forcing signals from the UI layer.
- Focused tests passed action-name uniqueness/round-trip, exact matching,
  non-binding event fields, deterministic override/unbind/passthrough,
  per-layer conflicts, unknown-key rejection, immutable construction, and the
  1,025th-definition failure.
- Final `make test` passed VT table freshness, formatting of 110 Dart files with
  zero changes, static analysis with no issues, and the complete test suite.
  `make runtime-source-check` passed with `tracked=199` and
  `native_sources=0`.
- The second ordered subtask is complete. The parent remains in progress pending
  AppKit physical-key adaptation and the single-write PTY integration.
