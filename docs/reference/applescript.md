# AppleScript reference

Dart Terminal exposes a native macOS scripting dictionary for standard terminal
windows. The dictionary is bundled as `DartTerminal.sdef` and can be opened from
Script Editor. It is enabled by default and follows normal macOS Automation/TCC
consent; Dart Terminal never grants or resets that permission itself.

## Object model

The read-only hierarchy is:

```text
application
└─ windows
   └─ tabs
      └─ terminals
```

Only standard windows are scriptable. Quick Terminal is intentionally absent.
IDs are stable, type-prefixed text values such as `window:1`, `tab:1`, and
`terminal:1`; an ID is never reused during the application lifetime.

| Object | Read-only properties |
| --- | --- |
| application | name, version, scripting enabled, windows |
| window | id, title, one-based index, frontmost, selected tab, tabs |
| tab | id, title, one-based index, selected, focused terminal, terminals |
| terminal | id, title, trusted local working directory |

Terminal screen contents, history, selections, environment variables, and
process command lines are not exposed.

## Commands

| Command | Target/result | Behavior |
| --- | --- | --- |
| `new window` | returns a window | Creates a standard window with a fresh terminal. |
| `new tab` | `in` a window; returns a tab | Creates a tab using normal new-session configuration. |
| `split` | terminal plus `right`, `left`, `down`, or `up`; returns a terminal | Splits through the authoritative Dart hierarchy and minimum-size policy. |
| `input text` | text `in` a terminal; returns a boolean | Uses the ordinary bounded paste analysis, confirmation, and PTY transport path. |
| `focus` | terminal; returns a boolean | Selects its window and tab and focuses the terminal. |
| `close` | terminal, tab, or window; returns a boolean | Uses the same foreground-process risk and confirmation policy as native Close actions. |

The Script Editor dictionary is authoritative for command syntax. A typical
sequence is:

```applescript
tell application "Dart Terminal"
  set createdWindow to new window
  set createdTab to new tab in createdWindow
  set firstTerminal to focused terminal of createdTab
  set createdTerminal to split firstTerminal direction right
  input text "hello from AppleScript" in createdTerminal
  focus createdTerminal
end tell
```

`input text` does not synthesize a Return key. Include the input required by the
target program, and expect the normal confirmation UI for multiline, control,
terminator-containing, or large text. Repeating a confirmed operation is bound
to that exact AppleScript source and payload; it cannot reuse authority from a
Service, drag/drop, clipboard, or a different script request.

## Configuration and permission

The generated configuration option is:

```text
macos-applescript = true
```

It is a live option. Setting it to `false` clears the native cached hierarchy,
rejects new commands, and completes pending commands once without changing the
terminal hierarchy. Setting it back to `true` republishes the surviving standard
objects with their existing IDs. The dictionary remains discoverable in the
application bundle while runtime access is disabled.

The sending application owns macOS Automation consent. On first external use,
macOS may ask whether that sender may control Dart Terminal. Denial is returned
as an Automation error and does not make Dart Terminal unresponsive. Permission
can be reviewed or changed only by the user in System Settings > Privacy &
Security > Automation.

## Limits and failures

- Snapshots are immutable, validated, and capped at 4 MiB, 32 windows, 64 tabs
  per window, and 64 total terminals.
- At most 16 commands may be pending. Command packets, IDs, titles, working
  directories, and input text all have fixed byte/count limits.
- Commands are serialized and completed exactly once. Native command timeout,
  disable, and shutdown resolve retained Apple Events rather than leaving a
  sender suspended.
- Malformed, oversized, wrong-kind, stale, hidden, busy, disabled, denied, or
  unavailable requests fail without redirecting the operation to another
  object.
- Scripted input shares the 64 MiB paste admission cap. Scripted close never
  bypasses foreground-process confirmation.

## Validation

`make RUNTIME_ARCH=arm64 runtime-applescript-integration` validates the exact
bundled dictionary and the real cached native queue/completion ABI in both
Developer JIT and Release AOT. It covers stable object IDs, creation, split,
byte-exact real-PTY input, focus, each close scope, stale references, live
disable/re-enable, exactly-once counters, and zero-owner teardown without
sending an external Apple Event or modifying TCC.

External discovery, Script Editor/`osascript`, consent denial and recovery,
System Settings visibility, and cross-runtime user-facing behavior are kept in
the [manual acceptance checklist](../phase10/applescript-manual-acceptance.md).
