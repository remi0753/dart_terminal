# AppleScript manual acceptance checklist

## Purpose

Validate the user-visible AppleScript dictionary, macOS Automation consent,
command behavior, and cleanup paths that the in-process Developer JIT and
Release AOT self-automation suite intentionally cannot exercise. Run this
checklist against both packaged runtimes after the automated
`runtime-applescript-integration` gate passes.

## Preconditions

- Build the Developer JIT and Release AOT application bundles for the current
  architecture.
- Use an ordinary macOS user session with Script Editor and `osascript`
  available. Do not reset or edit the TCC database as part of this checklist.
- In Dart Terminal settings, keep **Enable AppleScript automation** enabled for
  the initial checks.
- Open one standard window with one tab and one terminal. Quick Terminal must
  not be the only visible surface.
- Use disposable shell content. Close operations act on real tabs, terminals,
  and windows.

Record the bundle mode, macOS version, architecture, and result for every
section. A failure blocks acceptance; preserve the exact script, visible state,
and error message in the Phase 10 task memo.

## Dictionary discovery

- [ ] Open the built application dictionary in Script Editor.
- [ ] Confirm the application suite exposes `window`, `tab`, and `terminal`
      classes with stable integer `id` properties.
- [ ] Confirm the six commands are `new window`, `new tab`, `split`, `input
      text`, `focus`, and `close`.
- [ ] Confirm `split` accepts only `right` or `down` and targets a terminal.
- [ ] Confirm Quick Terminal is absent from the scriptable standard-window
      hierarchy.
- [ ] Run `sdef "/absolute/path/to/Dart Terminal.app"` and confirm it reports
      the same reviewed class and command surface without XML errors.

## First-use consent and command behavior

- [ ] From Script Editor, request the application window count. On a fresh
      consent state, confirm macOS presents the normal Automation prompt.
- [ ] Allow access and confirm System Settings > Privacy & Security >
      Automation shows the requesting host and Dart Terminal relationship.
- [ ] Confirm `osascript` can read the standard window/tab/terminal hierarchy
      and that repeated reads preserve object IDs.
- [ ] Create a window, create a tab in the original window, and split its first
      terminal right. Confirm the objects appear in the requested containers
      and retain stable IDs.
- [ ] Send a safe marker with `input text` to the new terminal and confirm the
      exact text appears once in its real PTY.
- [ ] Focus a terminal, then close the new terminal, tab, and window. Confirm
      the visible hierarchy and subsequent script queries agree.
- [ ] Retain a terminal reference, close that terminal, and then focus the
      retained reference. Confirm a stale-object AppleScript error is returned
      and no other terminal is affected.

## Denial, settings, and recovery

- [ ] On an environment where consent is denied by the user, confirm a command
      fails with the macOS Automation-denied error and Dart Terminal remains
      responsive. Do not change consent programmatically.
- [ ] Restore permission through System Settings only, retry, and confirm
      commands work without restarting unrelated applications.
- [ ] Disable **Enable AppleScript automation** while Dart Terminal is running.
      Confirm hierarchy queries expose no standard objects and commands are
      rejected without changing terminal state.
- [ ] Re-enable the setting while the application remains running. Confirm the
      current standard hierarchy is republished and commands work again with
      the same surviving object IDs.
- [ ] Confirm Quick Terminal remains excluded before and after the setting
      toggle.

## Cleanup and runtime parity

- [ ] Close scripted objects, quit Dart Terminal, and confirm no orphaned
      process, window, prompt, or hung Script Editor command remains.
- [ ] Repeat every applicable section with the other packaged runtime.
- [ ] Confirm Developer JIT and Release AOT produce the same dictionary,
      consent behavior, object IDs, command results, errors, settings response,
      and cleanup behavior.

## Automated companion evidence

`make runtime-applescript-integration` exercises both packaged runtimes without
sending external Apple Events or changing TCC state. It verifies the bundled
dictionary metadata, the real native snapshot/queue/completion ABI, stable IDs,
window/tab/split creation, exact PTY input, focus, close, stale references,
live disable/re-enable, exactly-once completion counters, and clean ownership
teardown. The manual checklist above owns only the external discovery, consent,
host-visible scripting, and user-facing parity evidence.
