# Terminal inspector and diagnostics manual checklist

This optional checklist supplements the automated M1/arm64 Developer JIT and
Release AOT product acceptance. It does not request terminal contents and must
not attach a generated report to an external service without the user's own
deliberate review and decision.

## Automated prerequisite

- [x] Static schema/source privacy audit covers 168 keys, 11 top-level entries,
  and six owner boundaries.
- [x] Developer JIT ordinary-product inspector/export acceptance passes.
- [x] Release AOT ordinary-product inspector/export acceptance passes.
- [x] Menu and Command Palette actions write zero bytes to the PTY and all
  parser/session/native owners return to zero at shutdown.

## Optional visual and filesystem checks

- [ ] With one live pane focused, use View > Open Terminal Inspector and confirm
  that exactly one read-only window appears.
- [ ] Produce ordinary colored output and confirm counters/events update without
  the printed words appearing in the inspector.
- [ ] Split the terminal, focus the other pane, and confirm the inspector starts
  a new empty parser capture instead of retaining the previous pane's records.
- [ ] Press Escape and confirm keyboard input returns to the currently focused
  terminal pane.
- [ ] Cancel File > Export Diagnostics… and confirm no file is created.
- [ ] Export to a chosen local file, review it before sharing, and confirm it has
  no terminal text, command, cwd/path, environment, clipboard/notification text,
  hyperlink target, image data, timestamp, stable ID, or raw error.
- [ ] Repeat using Option-Command-I, Option-Command-E, and Command Palette
  search; confirm no shortcut character reaches the shell.

Long-duration use is outside this checklist and was intentionally skipped under
the user's priority instruction. Crash/hang collection and any distribution or
support workflow are owned by Phase 11.
