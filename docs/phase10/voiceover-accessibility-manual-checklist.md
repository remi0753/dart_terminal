# VoiceOver, Accessibility Inspector, and Full Keyboard Access checklist

## Purpose

Validate the macOS-owned assistive surfaces that deterministic Developer JIT
and Release AOT acceptance cannot drive: spoken VoiceOver navigation,
Accessibility Inspector presentation, and system Full Keyboard Access focus.
Run this checklist only after `make runtime-configuration-integration` passes.
Display-preference and locale observations are tracked separately in the
[accessibility display/localization checklist](accessibility-display-localization-manual-checklist.md).

## Preconditions and safety

- Build both packaged runtimes for the current architecture. Record bundle
  path, runtime mode, macOS version, Xcode version, architecture, display scale,
  and configured horizontal/vertical terminal padding.
- Use a normal interactive macOS session. Enable VoiceOver, Accessibility
  Inspector, and Full Keyboard Access only through their standard UI or normal
  system shortcuts. Do not edit accessibility databases or script System
  Settings.
- Use disposable, non-sensitive terminal text containing ASCII, one wide CJK
  character, and one emoji grapheme. Do not capture shell history, environment,
  credentials, or private terminal output in the evidence record.
- Start with one standard terminal window. A failure blocks release acceptance
  and must be recorded in the Phase 10 task memo with content-free state and an
  optional sanitized screenshot path.

## VoiceOver terminal text area

- [ ] With zero configured padding, move VoiceOver focus into the terminal and
      confirm it is announced as one read-only text area labelled **Terminal**.
- [ ] Confirm VoiceOver can read the visible prompt and output in display order,
      including the wide CJK character and emoji once each, without exposing
      off-screen scrollback as current visible text.
- [ ] Create a forward selection and a reverse selection. Confirm VoiceOver
      announces exactly the selected visible text and selection changes do not
      move the terminal cursor or send input.
- [ ] Move the shell cursor and emit new output. Confirm cursor/selection/value
      announcements update without duplicate focus transitions or a stalled UI.
- [ ] Scroll into history and return to the bottom. Confirm the exposed visible
      range follows the viewport and the current prompt/cursor recovers.
- [ ] Split right and down, add a tab and a standard window, and focus each
      terminal. Confirm every pane has independent text, selection, cursor, and
      focus state; background panes are not reported as the focused element.
- [ ] Open and close Command Palette and Settings, then show/hide Quick Terminal.
      Confirm focus returns to the intended terminal and no disposed pane remains
      reachable through VoiceOver.

## Accessibility Inspector geometry and padding

- [ ] Inspect the focused terminal with zero padding. Confirm role, label,
      visible character range, selected text/range, insertion-point line, and
      focused state agree with the visible terminal.
- [ ] Set nonzero horizontal and vertical padding, create a fresh pane, and
      confirm the first character/cursor/selection frame begins at the rendered
      content origin rather than at the outer view origin.
- [ ] Hit-test points inside the left and top padding. Confirm they do not map to
      the first terminal character. Confirm points beyond the right/bottom grid
      also do not map to a character.
- [ ] Inspect a one-line selection, a multi-line selection, a collapsed cursor
      range, a wide CJK cell, and an emoji grapheme. Confirm every returned frame
      is finite, positive, on the intended rendered cells, and neither offset a
      second time nor clipped into padding.
- [ ] Drag a split divider until effective padding contracts, then enlarge the
      pane. Confirm text is not scaled, cell/font metrics remain fixed, range and
      cursor frames track the contracted/restored rendered origin, and Inspector
      does not retain stale geometry.
- [ ] Repeat the geometry observations on a Retina display at 2x and, when
      available, a 1x or differently scaled display. Confirm logical-point
      geometry and visible glyph placement agree without double scaling.

## Full Keyboard Access

- [ ] Enable Full Keyboard Access and use only the keyboard to move between the
      terminal, tabs/windows, Settings, Command Palette, and Quick Terminal.
      Confirm focus is visible and returns to the previously focused terminal.
- [ ] Use the native menu shortcuts to create right/down splits, select tabs,
      focus next/previous panes, equalize panes, and move the nearest divider.
      Confirm each action runs once and command keys are not inserted into the
      PTY.
- [ ] In Settings, navigate options, search, enter/leave edit mode, save, cancel,
      and close using only the keyboard. Confirm current-line focus, status, and
      terminal responder restoration remain usable with VoiceOver enabled.
- [ ] Confirm standard terminal input, shell line editing, selection Copy, and
      Paste still work after traversing native controls and no keyboard trap
      requires pointer input to escape.

## Cleanup and runtime parity

- [ ] Restore accessibility settings and terminal padding to their recorded
      values, close disposable panes/tabs/windows, and quit normally. Confirm no
      orphaned shell, invisible Quick Terminal, or stale Inspector element
      remains.
- [ ] Repeat every applicable section with the other packaged runtime.
- [ ] Confirm Developer JIT and Release AOT expose the same role, label, visible
      text/ranges, padding-aligned geometry, notifications, focus traversal, and
      cleanup behavior.

## Evidence record

Record one row per case with only: date, macOS/Xcode version, architecture,
runtime mode, display scale, padding pair, case name, `pass`/`fail`/`not
available`, and content-free geometry/focus/cleanup booleans. A sanitized
screenshot or defect link is optional. Do not record terminal text, selection
contents, shell history, paths, process IDs, or stable hierarchy identifiers.

## Automated companion evidence

`make runtime-configuration-integration` launches both packaged runtimes with
nonzero configured padding. It validates copied accessibility origins for all
four live terminal surfaces, focuses one reloaded native pane, and runs the
content-free native selector verifier at configured, contracted, and restored
origins. The renderer dependency separately covers zero/nonzero point lookup,
padding/grid misses, one- and multi-line range/cursor frames, wide cells,
notifications, malformed packets, and atomic rejection. These tests neither
enable assistive technologies nor inspect or log terminal content; the checklist
above is the authority for external spoken, Inspector, and system-focus
observations.
