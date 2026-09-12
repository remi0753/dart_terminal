# Accessibility display preferences and localization checklist

## Purpose

Validate the macOS-owned display-preference and locale surfaces that automated
Developer JIT and Release AOT acceptance cannot change globally: Reduce Motion,
Increase Contrast, Differentiate Without Color, visible Japanese system UI, and
right-to-left application composition. This is a release checklist, not a
duration or soak test.

## Preconditions and safety

- Build both packaged runtimes for the current architecture. Record the bundle,
  runtime mode, macOS version, architecture, display scale, system language,
  region, layout direction, and initial values of the three display preferences.
- Use a normal interactive macOS session and change accessibility/language
  settings only through System Settings. Do not edit preference databases.
- Use disposable, non-sensitive terminal text. Evidence must not contain shell
  history, credentials, environment values, private paths, process IDs, or
  terminal contents.
- Run the automated companion commands below first. A manual failure blocks
  release acceptance but does not invalidate deterministic automated evidence.

## Reduce Motion

- [ ] With Reduce Motion off, show and hide Quick Terminal and trigger a visual
      bell. Confirm the configured top-edge transition and bounded bell pulse
      are visible.
- [ ] Enable Reduce Motion while the application is running. Show and hide the
      same Quick Terminal and trigger another visual bell. Confirm the window
      transition completes with no interpolation and the bell has no pulse or
      delayed redraw.
- [ ] Confirm the configured animation duration is unchanged in Settings and a
      fresh pane, tab, and window retain the same font and cell dimensions.
- [ ] Disable Reduce Motion and confirm the configured behavior returns without
      restarting the application or replacing the existing terminal session.

## Increase Contrast

- [ ] Enable Increase Contrast while Settings and a terminal are visible.
      Confirm Settings controls/current-line state and terminal cursor,
      selection, and overlays remain distinguishable in both light and dark
      appearances without changing text size or cell geometry.
- [ ] Move a split divider before and after the change. Confirm content is
      reflowed to the new grid width and is never bitmap-scaled or blurred.
- [ ] Disable Increase Contrast and confirm the standard palette returns while
      the Settings draft, selection, editor mode, focused pane, and PTY remain.

## Differentiate Without Color

- [ ] Enable Differentiate Without Color and create a local selection. Confirm
      its non-color edge is visible in focused and unfocused panes.
- [ ] Hover a safe OSC 8 link and confirm the underline is visibly stronger;
      trigger a visual bell and confirm its border remains identifiable even
      when Reduce Motion is also enabled.
- [ ] Exercise the Secure Keyboard Entry indicator. Confirm its state is
      understandable without color alone and terminal input remains focused.
- [ ] Disable the preference and confirm no stale edge, underline, or border is
      retained after the next accepted frame.

## Japanese and fallback localization

- [ ] Run once with Japanese as the preferred system language. Confirm the
      Application/File/Edit/Shell/View/Window menus, terminal context menu,
      Command Palette, Settings shell/options/statuses, confirmation messages,
      and OSC 52 prompt use Japanese while terminal output, paths, and config
      values remain byte-for-byte user data.
- [ ] Confirm Finder Services and App Shortcuts expose their Japanese resource
      names after normal macOS registration. Record `not available` when the OS
      has not refreshed registration; do not mutate system databases.
- [ ] Run once with English and confirm the same surfaces use the English
      catalog.
- [ ] Run with an unsupported locale and confirm the application falls back to
      English without a mixed, blank, or identifier-valued UI string.

## Right-to-left application composition

- [ ] With an unsupported right-to-left locale such as Arabic selected for a
      disposable launch, open Settings and confirm its application-level
      navigation/detail composition follows right-to-left direction while the
      English fallback catalog remains complete.
- [ ] Confirm terminal cells, prompt/output order, selection anchors, cursor
      movement, split geometry, paths, and copied text are not mirrored or
      reordered.
- [ ] Open the Command Palette and native menus, dispatch an action once, and
      confirm focus returns to the same terminal without command text entering
      the PTY.

## Runtime parity and cleanup

- [ ] Repeat all applicable cases with Developer JIT and Release AOT bundles.
- [ ] Restore the original system language, region, layout direction, and three
      accessibility preferences. Close disposable windows and quit normally.
- [ ] Confirm there is no orphaned shell, stale Quick Terminal, replaced
      Settings draft, or inaccessible terminal after cleanup.

## Evidence record

Record one row per case with only: date, macOS version, architecture, runtime
mode, display scale, locale/direction, three preference booleans, case name,
`pass`/`fail`/`not available`, and content-free identity/geometry/cleanup
booleans. A sanitized screenshot or defect link is optional.

## Automated companion evidence

`make terminal-localization-check` rejects catalog literals in the 12 bounded
production owners, verifies the nine application wiring/acceptance handoffs,
and checks the English/Japanese four-family resource layout and paired keys.
`make runtime-bundle-audit runtime-configuration-integration
runtime-theme-integration` verifies both packaged runtimes, exact localization
resource bytes, deterministic English configuration UI, Japanese
menu/palette/Settings/status UI, protocol-v14 live preference projection,
deduplication, stable owners, accepted Metal frames, and complete teardown.
These commands do not change system preferences or language and therefore do
not replace the manual observations above.
