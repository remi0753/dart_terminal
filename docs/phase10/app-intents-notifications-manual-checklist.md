# App Intents, Shortcuts, and notifications manual checklist

## Purpose

Validate the external macOS surfaces that the deterministic Developer JIT and
Release AOT acceptance must not automate: Shortcuts discovery and invocation,
the user-owned notification permission prompt and System Settings state, and a
real notification selection. Run this checklist only after
`make runtime-system-automation-integration` passes.

## Preconditions and safety

- Build the Developer JIT and Release AOT app bundles for the current
  architecture. Record the bundle path, runtime mode, macOS version, Xcode
  version, and architecture for each run.
- Use a normal interactive macOS session with Shortcuts and System Settings
  available. Use a disposable shell and harmless marker text only.
- Do not reset the notification database, edit TCC databases, script System
  Settings, or create/delete the tester's unrelated shortcuts. Permission
  changes in this checklist are explicit user actions.
- Start with one standard Dart Terminal window. Keep
  `macos-app-intents = true` and `macos-notifications = true` for the initial
  cases. A failure blocks acceptance and must be recorded in the Phase 10 task
  memo with content-free state and a sanitized screenshot path if useful.

## Shortcuts discovery and actions

- [ ] Open Shortcuts, search the application actions for Dart Terminal, and
      confirm exactly **New Terminal Window**, **New Terminal Tab**, and
      **Quick Terminal** are discoverable.
- [ ] Confirm none of the three actions asks for command text, terminal text,
      working directory, environment, object ID, or another parameter.
- [ ] Run **New Terminal Window** and confirm exactly one standard window and
      one fresh terminal session are created.
- [ ] Run **New Terminal Tab** and confirm exactly one tab is created in the
      active standard window.
- [ ] Run **Quick Terminal** twice and confirm the existing singleton is shown
      and then hidden without replacing its retained session.
- [ ] Set `macos-app-intents = false` while the app is running, save Settings,
      and invoke each shortcut. Confirm each reports that the action is
      unavailable/disabled and does not change the hierarchy.
- [ ] Restore `macos-app-intents = true` without restarting, invoke all three
      again, and confirm they recover with the same behavior.
- [ ] Confirm Settings reports only enabled/disabled, availability, pending and
      bounded result counters; it must not show terminal content or parameters.

## Notification permission and delivery

- [ ] From a terminal that is not the active focused pane, emit a harmless
      legacy notification, for example `printf '\e]9;manual sample\a'`.
      Confirm the normal macOS notification authorization prompt appears only
      when the system's current state requires it.
- [ ] Deny permission in a disposable permission state. Confirm the terminal
      remains responsive, no repeated prompt loop occurs, and Settings reports
      `denied` with a content-free failure class.
- [ ] Open System Settings > Notifications and allow notifications for Dart
      Terminal. Do this manually; do not use a database reset or command-line
      permission mutation.
- [ ] Emit another notification from a background pane. Confirm one system
      notification appears with the expected title/body and that repeated
      terminal output still obeys the documented global and per-session caps.
- [ ] Select the notification. Confirm Dart Terminal activates and focuses the
      exact still-live window, tab, and pane that emitted it.
- [ ] Emit a notification, close its pane, and then select any retained system
      entry if macOS still presents it. Confirm no stale pane is recreated and
      no other pane is focused as a fallback.
- [ ] Disable `macos-notifications` live. Confirm pending/delivered terminal
      notifications are removed, new terminal notification sequences do not
      create system posts, and Dock progress cleanup remains correct.
- [ ] Re-enable `macos-notifications` without restarting. Confirm current
      authorization is refreshed, delivery recovers under system policy, and
      Settings contains no notification title, body, identifier, or pane ID.
- [ ] Change notification permission once more in System Settings while the app
      remains open, then trigger a fresh notification. Confirm the refreshed
      authorized/denied result is honored without a crash or prompt loop.

## Cleanup and runtime parity

- [ ] Remove only disposable shortcuts created for this checklist and restore
      both configuration options to their recorded values.
- [ ] Close all disposable windows/tabs/panes and quit normally. Confirm no
      orphaned terminal process, Quick Terminal, notification response owner,
      or hung Shortcuts invocation remains.
- [ ] Repeat all applicable cases with the other packaged runtime.
- [ ] Confirm Developer JIT and Release AOT have the same three actions,
      parameterless contract, live settings behavior, permission/failure
      reporting, notification focus result, stale handling, and cleanup.

## Evidence record

Record one row per case with only: date, macOS/Xcode version, architecture,
runtime mode, case name, `pass`/`fail`/`not available`, action count, enabled and
authorization state, focus/cancel/cleanup booleans, and an optional sanitized
screenshot or defect link. Do not record terminal content, notification text,
shell history, environment values, or stable hierarchy identifiers.

## Automated companion evidence

`make runtime-system-automation-integration` inspects both signed bundles for
the exact Swift image, two-file metadata bundle, three parameterless foreground
actions, and three matching automatic shortcuts. It then launches each shipped
runtime, drives the real bounded native App Intent queue through the three
shared actions, and validates deterministic notification settings,
authorization, denied delivery, retry, default response, duplicate response,
live disable/re-enable, and teardown. Its notification recorder never calls
UserNotifications, never changes permission, and never creates a visible post;
the checklist above is the authority for those external observations.
