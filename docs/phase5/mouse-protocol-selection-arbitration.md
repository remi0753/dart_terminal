# Phase 5 — mouse protocol and local-selection arbitration

- Status: in progress
- Date: 2026-09-06
- Scope: fourth Phase 5 production-input roadmap item
- Related: CAP-03, IN-05, IN-06, SCR-07, REN-02

## Purpose

Route one normalized AppKit pointer event either to a terminal application's
active mouse protocol or to local selection, never both. Terminal applications
must receive bounded xterm-compatible coordinates and button/modifier state,
while a normal shell and an explicit Shift override retain local-selection
ownership.

## Background

`dart_appkit` already emits immutable mouse down/up/moved/dragged events with
content-view-local logical coordinates, AppKit button number, modifiers, click
count, generation, and monotonic time. The terminal core already owns stable
viewport anchors and cell/word/logical-line selection semantics, but product UI
does not yet consume pointer events. The parser also does not retain DEC mouse
tracking or coordinate-encoding modes.

Precision/momentum scroll, concrete multi-click/drag selection, drag
autoscroll, clipboard copy, and hyperlink hover are later ordered roadmap
items. This task establishes the protocol and ownership boundary they consume.

## Ordered subtasks

1. **Terminal modes and encoder**
   - Add terminal-owned tracking state for DECSET 9/1000/1002/1003 and encoding
     state for 1005/1006/1015.
   - Reset and DECRQM-report the modes, with deterministic exclusivity rules.
   - Encode X10/default, UTF-8, URXVT, and SGR press/release/motion packets with
     bounded 1-based cell coordinates, AppKit-to-xterm button mapping, and
     Shift/Option/Control modifier bits.
   - Completion: exhaustive pure-Dart mode/parser/encoder tests and full suite
     pass; commit only this subtask and reread the roadmap.
2. **Normalization and arbitration**
   - Convert finite logical view coordinates to clamped terminal cells using
     current CoreText cell metrics and grid size.
   - Choose `terminalReport`, `localSelection`, or `ignore` from mode, event
     kind, and Shift override. A single event cannot produce both outcomes.
   - Expose a bounded local-selection intent containing cell, button, click
     count, and gesture phase for the next roadmap item; do not implement
     selection mutation early.
   - Completion: boundary, invalid-input, mode/event, and exclusivity tests pass;
     commit only this subtask and reread the roadmap.
3. **Product and real-PTY acceptance**
   - Connect window mouse events to the live pane router while preserving the
     existing AppKit text-input and Metal ownership boundaries.
   - Add a test-gated deterministic native pointer operation only if ordinary
     AppKit event construction cannot provide stable end-to-end automation.
   - Prove protocol transitions and exact bytes in a real PTY for Developer JIT
     and Release AOT, and prove normal/Shift pointer input selects the local path
     without a PTY write.
   - Completion: product tests, source and bundle audits, real-window display,
     smoke, and resource checks pass; then complete the parent item.

Dependencies are strictly ordered: subtask 2 consumes the state/encoder from
subtask 1, and subtask 3 consumes both. No later roadmap task is implemented
inside these commits.

## Scope

- DEC private tracking modes: X10 press-only (9), normal press/release (1000),
  button-motion (1002), and any-motion (1003).
- Coordinate encodings: default/X10 bytes, UTF-8 extended coordinates (1005),
  SGR decimal (1006), and URXVT decimal (1015).
- Left, middle, and right press/release plus dragged/hover motion; wheel/scroll
  is explicitly deferred to the precision-trackpad roadmap item.
- Shift bypass to local selection whenever a terminal mouse mode is active.
- AppKit logical point to 1-based terminal cell mapping using the current grid
  and cell dimensions.
- Bounded immutable packet/event/result types and privacy-safe diagnostics.

## Out of scope

- Mutating or rendering a character/word/line selection, click-count policy,
  drag autoscroll, selection extraction, or copy action.
- Scroll wheel, precision delta, momentum phase, alternate-screen scroll-key
  emulation, or scrollback viewport movement.
- Focus reporting, Kitty keyboard, Kitty mouse extensions, touch/gesture APIs,
  drag and drop, hyperlink hover/open, accessibility, or paste.
- Supporting cell coordinates beyond the selected protocol's representable
  bound by wrapping, truncating, or emitting malformed packets.

## Decisions and invariants

- Dart terminal state owns all DEC mode semantics and encoding. Native AppKit
  remains an event normalizer and never decides terminal protocol behavior.
- Tracking modes and coordinate encodings each have one active enum value.
  Enabling one replaces the previous value; disabling a non-current value is a
  no-op, matching independent DECSET/DECRST streams without an ambiguous bitset.
- AppKit button numbers map as left `0 -> 0`, right `1 -> 2`, middle `2 -> 1`.
  Unsupported auxiliary buttons are ignored until explicitly specified.
- Default/UTF-8/URXVT releases use legacy release button 3. SGR releases retain
  the physical button and use final `m`; all presses and motion use `M`.
- X10 mode reports presses only. Normal mode adds releases, button-event mode
  adds dragged motion, and any-event mode also adds no-button movement.
- Shift is reserved as the local-selection override and is not simultaneously
  reported to the terminal. Without active reporting, down/drag/up are local
  selection intents and plain movement is ignored.

## Completion criteria

- All tracking/encoding DECSET, DECRST, reset, and DECRQM behavior is typed and
  tested without changing existing keyboard modes.
- Every supported encoder yields byte-exact packets at normal and boundary
  coordinates and fails closed outside its limit.
- Product routing proves mutually exclusive remote/local/ignored outcomes and
  maps current AppKit logical coordinates to the intended grid cell.
- Developer JIT and Release AOT prove exact mouse bytes through a real PTY and
  content-free local-selection arbitration through a real AppKit window.
- Full tests, documentation, source audit, both bundle audits, and relevant
  display/resource acceptance pass with both repositories clean.

## Verification plan

- Focused parser/screen-set and mouse encoder unit tests for every mode,
  protocol, button, modifier, event kind, coordinate edge, and invalid value.
- Router tests with real `AppKitMouseEvent` values and fixed grid/cell metrics.
- Existing full Dart/native test suites after each subtask.
- Real raw/no-echo PTY fixture with shell-side exact comparison in both runtime
  modes, retaining existing key, IME, input matrix, Metal, and prompt checks.

## Investigation log

- 2026-09-06: input-source matrix commit `fcf2931` completed the preceding
  roadmap item; project and dependency worktrees were clean before this task.
- 2026-09-06: existing `AppKitMouseEvent` supplies logical content-view `x/y`,
  AppKit `button`, modifiers, click count, and down/up/moved/dragged kind. The
  product currently ignores it in `TerminalApplication`.
- 2026-09-06: the native window already posts mouse events regardless of the
  key routing policy, so this task needs no general AppKit mouse API redesign.
- 2026-09-06: stable viewport anchors and bounded cell/word/logical-line text
  extraction exist from Phase 3. This task must emit local intent only so the
  immediately following selection-gesture task retains its own scope.
- 2026-09-06: terminal keyboard modes currently store DECCKM/DECPAM only in
  `TerminalScreenSet`; mouse state belongs alongside them but must remain a
  separate typed contract so key encoding does not acquire pointer concerns.
- 2026-09-06: completed ordered subtask 1. `TerminalScreenSet` now owns one
  tracking enum and one coordinate-encoding enum. DECSET selects a family
  member, DECRST only clears the matching current member, RIS clears both, and
  resize/alternate-screen transitions retain both.
- 2026-09-06: DECRQM recognizes all seven implemented DEC mouse modes. Query
  status is derived from the same immutable `TerminalMouseModes` snapshot used
  by input encoding, preventing parser and router state from diverging.
- 2026-09-06: the encoder supports press/release/button-motion/any-motion
  eligibility plus default six-byte, UTF-8 extended, SGR decimal, and URXVT
  decimal packets. Default coordinates fail above 223, UTF-8 above 2015, and
  decimal formats share the 4096-cell terminal-screen bound; no value wraps or
  truncates.
- 2026-09-06: AppKit button numbers are mapped explicitly to xterm's
  left/middle/right order. Only Shift, Option, and Control occupy xterm modifier
  bits; Command and platform-only flags cannot leak into the protocol.

## Verification results

### Terminal modes and encoder

- Focused analyzer and `test/terminal_mouse_encoder_test.dart`: passed. Tests
  cover mode exclusivity, non-current reset, DECRQM replies, alternate/resize
  retention, RIS, tracking eligibility, button mapping, all modifiers, all four
  encodings, release/motion forms, exact edge bytes, and invalid bounds.
- `CI=true make test`: passed with parser-table freshness, 122-file format
  check (zero changes), whole-package analysis, native asset hooks, and the full
  Dart runner.
- Remaining parent work is tracked by ordered subtasks 2 and 3; the parent item
  intentionally remains incomplete.
