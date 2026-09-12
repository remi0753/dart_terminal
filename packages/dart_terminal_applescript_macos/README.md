# dart_terminal_applescript_macos

`dart_terminal_applescript_macos` is an optional terminal-specific Cocoa
Scripting capability for `dart_macos_runtime`. It owns native scripting object
wrappers and suspended Apple Events; the application remains authoritative for
all hierarchy mutation, input safety, and close policy.

Declare both the validated dictionary and capability:

```json
{
  "scriptingDefinition": {
    "path": "resources/DartTerminal.sdef"
  },
  "nativeCapabilities": [
    {
      "id": "dart_terminal_applescript_macos",
      "package": "dart_terminal_applescript_macos",
      "library": "libdart_terminal_applescript_macos.dylib",
      "abiVersion": 1,
      "abiVersionSymbol": "dtas_abi_version",
      "initializerSymbol": "dtas_initialize"
    }
  ]
}
```

Call `TerminalAppleScriptMacos.initialize()` on the root UI isolate after
startup, then open one `TerminalAppleScriptMacosSession`. Publish version-one
snapshot JSON atomically, poll version-one command JSON from the AppKit turn,
execute it through Dart-owned product state, publish any resulting snapshot,
and complete the operation. Object-producing commands require the matching
window, tab, or terminal ID from that published snapshot; other commands
complete with a boolean result. No native callback synchronously enters Dart.

The bundled `native/DartTerminal.sdef` exposes only:

- application -> standard windows -> tabs -> terminals;
- stable text IDs, bounded titles/local working directories, and selected,
  focused, and frontmost relations;
- new window, new tab, right/left/down/up split, input text, focus, and close.

Terminal contents/history, arbitrary actions, synthetic input, launch records,
mutable titles, and Quick Terminal are intentionally absent. Scripted input is
only a request: the application must route it through its ordinary paste
confirmation and transport path.

The native side accepts at most 32 windows, 64 tabs per window, 64 terminals,
a 4 MiB snapshot, 16 pending commands, and a five-minute timeout. Queries use
the last accepted immutable cache. Invalid replacement is atomic. Disabling
the snapshot or shutting down empties visible collections and resumes every
pending command exactly once with an error. Cocoa Scripting/TCC decides whether
an external sender has Automation authority; this package never requests,
grants, or resets that permission.

The `testing.dart` library exposes an in-process self-automation enqueue seam
for shipped-bundle acceptance. It accepts only the same bounded, versioned JSON
packet as Cocoa commands and enters the same native pending queue, but retains
no `NSScriptCommand`, sends no Apple Event, and does not read or modify TCC.
Products must keep this seam behind an explicit test-only CLI and environment
gate; external Script Editor and `osascript` permission behavior remains a
manual acceptance responsibility.
