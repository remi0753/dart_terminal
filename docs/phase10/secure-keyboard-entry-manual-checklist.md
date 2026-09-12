# Phase 10 — Secure Keyboard Entry manual checklist

This checklist covers system-wide focus and abnormal-process behavior that the
bounded runtime suite must not trigger on a shared desktop. Use only disposable,
non-sensitive text. Never enter a real password, token, recovery code, or other
secret while collecting evidence.

## Preparation

1. Record the date, macOS version, architecture, and runtime mode.
2. Confirm no other application is intentionally holding Secure Event Input.
   If one is, stop instead of changing that application's state.
3. Launch the app normally with default secure-input settings. Open Settings
   and confirm `macos-secure-input-auto` and
   `macos-secure-input-indication` are both `true`.
4. Use `printf` markers or the literal word `sample` only. Evidence must record
   state booleans and optional sanitized screenshot paths, not terminal input or
   command history.

## Cases

| Case | Setup and action | Expected behavior |
| --- | --- | --- |
| Automatic acquire/release | In a disposable shell run `stty -echo; sleep 3; stty echo`. Do not type during the sleep. | The focused terminal shows the automatic secure indicator only while this process owns Secure Event Input, then removes it after ECHO returns. Settings reports `automatic (owned)` during the interval and `disabled (released)` after it. |
| Manual menu state | Choose **Secure Keyboard Entry** from the Application menu twice. | The first invocation checks the menu and shows the manual indicator; the second unchecks it and removes manual intent. If automatic policy is independently active, the second invocation returns to the automatic indicator rather than disabling it. |
| Shared actions | Toggle once through Shift-Command-P by searching for **Secure Keyboard Entry**, then toggle through a configured local keybinding such as `control+shift+s`. | Menu, palette, and keybinding all change the same checked manual intent exactly once. No characters or escape bytes appear in the terminal. |
| Settings and live policy | While manual mode is on, open Settings, inspect its secure status, set `macos-secure-input-indication = false`, save, then restore `true`. Repeat with `macos-secure-input-auto`. | Settings reports mode plus `owned`, `yielded`, or `released`. Disabling indication hides only the overlay; disabling automatic policy releases automatic ownership without clearing manual intent. Restoring each option applies live. |
| IME independence | With automatic or manual secure input owned, compose a harmless Japanese candidate, commit it once, then start another composition and cancel it. | Preedit, candidate placement, single commit, and empty cancel match normal operation. Secure policy does not inspect or log composition text, and raw input is not duplicated. |
| Pane/window handoff | Create two panes and two ordinary windows. Move focus between them while manual mode is on, then close the focused pane and window. | Exactly one focused live terminal shows the manual indicator. The previous target hides it. Closing owners never leaves an indicator or native secure owner attached to the removed view. |
| Quick Terminal handoff | Turn on manual mode, show Quick Terminal, hide it, and return to the ordinary window. | Ownership remains balanced; the indicator moves to Quick Terminal while focused and returns to the ordinary terminal after hide. Hidden Quick Terminal never retains a visible indicator. |
| Application yield/reacquire | Turn on manual mode, switch to another application, then switch back. | Dart Terminal hides its indicator and yields its owned reference while inactive. It reacquires and restores the manual indicator only after becoming active again. Manual intent remains checked throughout. |
| Normal quit cleanup | Quit from the Application menu while manual mode is on, then relaunch. | Quit completes without a confirmation loop caused by Secure Input. The relaunched app starts unchecked with no inherited manual intent or owner. |
| Abnormal process cleanup | With only disposable terminal state present and manual mode on, Force Quit the app once, then relaunch it. | macOS releases the dead process's Secure Event Input reference. Other applications accept keyboard input normally, and the relaunched app starts unchecked. If input remains captured, stop testing and record a blocking defect. |
| External owner/failure | If a controlled test application can hold Secure Event Input, hold it before toggling Dart Terminal; otherwise record `not available`. | Dart Terminal never disables the external owner's reference. An acquisition failure is visible as `failed` in Settings, the indicator stays hidden, and a later toggle/reconcile can retry after the external owner releases. |

## Restoration

1. Restore both secure-input options to their values recorded at preparation.
2. Remove only the temporary local keybinding added for this checklist.
3. Confirm the Secure Keyboard Entry menu item is unchecked, quit normally,
   and verify keyboard input works in another application.
4. Delete disposable shell history only if the tester's normal policy requires
   it; do not alter unrelated history or system input settings.

## Evidence record

Record one row per case with only these content-free fields:

- date, macOS version, architecture, runtime mode;
- case name and `pass` / `fail` / `not available`;
- automatic/manual/checked/indicator/owned/yielded/released booleans as
  applicable;
- terminal input duplicated, app input restored, and cleanup completed
  booleans;
- optional sanitized screenshot path and defect link.

The automated Developer JIT and Release AOT suite covers real PTY ECHO
transitions, native menu/palette/local-key action routes, Settings status, IME,
Quick Terminal target handoff, and owned normal-Quit cleanup. The system focus
switch, Force Quit, and controlled external-owner rows remain intentional
release checklist observations.
