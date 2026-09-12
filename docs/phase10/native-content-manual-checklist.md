# Native Content Manual Acceptance Checklist

## Purpose

This checklist covers macOS behavior that cannot be made deterministic inside
the shipped-runtime harness: Services database registration, Finder selection,
third-party text Services, physical trackpad pressure, and user accessibility
settings. Run it against both the Developer JIT and Release AOT application
bundles after `make runtime-native-content-integration` passes.

## Prerequisites

- Use macOS 14 or later with a Force Touch trackpad for the pressure-click case.
- Build both bundles with `make developer-jit-build release-aot-build`.
- In System Settings > Keyboard > Keyboard Shortcuts > Services, enable
  **New Dart Terminal Tab Here**, **New Dart Terminal Window Here**, and one
  plain-text Service that returns transformed text.
- If newly built Services do not appear, launch each application bundle once,
  then log out and back in or refresh the macOS Services database. Record the
  macOS version, hardware, bundle mode, and any refresh action with the result.
- Use disposable directories and files whose names include a space and a
  single quote. Do not use production data for the drag/drop cases.

## Finder Folder Services

- [ ] In Finder, select one directory and invoke **New Dart Terminal Tab
      Here**. A new standard tab opens and `pwd` prints that exact directory.
- [ ] Select one file and invoke the same Service. A new tab opens in its
      parent directory, not at the file path.
- [ ] Select multiple files from the same parent plus one directory. Only one
      tab is created per normalized directory, in Finder selection order.
- [ ] Repeat the cases with **New Dart Terminal Window Here**. Each normalized
      directory receives a separate standard window with the exact `pwd`.
- [ ] Invoke either Service while Quick Terminal is visible. New tabs attach
      to a standard window and never become tabs of the retained Quick Terminal.

## Selection, Services, and Drag/Drop

- [ ] Select bounded terminal text, open the Services menu, and verify the text
      Service receives exactly the visible selection—no adjacent cell or
      scrollback text.
- [ ] Let the Service return a single safe line. It is inserted into the pane
      that originated the request and that pane becomes focused.
- [ ] Let a Service return multiple lines. The first delivery shows the normal
      paste confirmation without sending input; repeating the same operation
      within the confirmation interval inserts the data once.
- [ ] Drag plain text into a non-focused pane. The target pane becomes focused
      and receives the exact text through normal bracketed-paste behavior.
- [ ] Drag the disposable Finder files whose names contain a space and a single
      quote. The terminal receives one shell-quoted literal word per path; no
      filename content executes as shell syntax.
- [ ] Cancel a drag outside a pane and drop an unsupported rich/image object.
      Neither action changes focus or sends terminal input.

## Quick Look and Context Menu

- [ ] Force-click the middle of an ASCII word. The macOS definition popover
      shows exactly that word and its anchor follows the active font baseline.
- [ ] Repeat on a wide-character word, after resizing a split pane, and on a
      Retina display. The popover remains attached to the intended cell.
- [ ] Force-click whitespace, an empty row, and stale scrolled content. No
      partial or unrelated definition is presented.
- [ ] Right-click and Control-click with terminal mouse reporting disabled.
      One native menu shows Copy, Paste, Quick Look, Split Right, and Split
      Down with enablement matching the main menu.
- [ ] Invoke Quick Look and both split actions from the context menu. They have
      the same focus, result, and availability as their main-menu counterparts.
- [ ] Run `printf '\e[?1000h'`, then right-click and Control-click. Terminal
      mouse reporting owns the gesture and the terminal context menu is absent.
      Run `printf '\e[?1000l'` to restore ordinary interaction.
- [ ] A right-click sequence never changes the current selection and never
      appears as duplicated terminal mouse input when reporting is disabled.

## Accessibility and Teardown

- [ ] Repeat Control-click with macOS secondary-click and trackpad Force Click
      settings both enabled and disabled where applicable. The documented
      alternative gesture remains usable and no ordinary left click is lost.
- [ ] Close panes/tabs/windows while a definition popover is visible and while
      a drag is hovering. No stale event reaches another pane and no crash or
      orphan window remains.
- [ ] Quit after creating tabs/windows through Services. All terminal child
      processes exit, the application terminates, and relaunch starts with one
      usable standard terminal window.

## Recording Results

For each bundle mode, record pass/fail, macOS build, architecture, display scale,
trackpad availability, Services database refresh method, and any failed step.
Attach screenshots only when they clarify a failure; do not record selected
terminal text that contains secrets or personal data.
