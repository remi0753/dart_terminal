# dart_terminal_app_intents_macos

`dart_terminal_app_intents_macos` owns the closed macOS App Intents surface for
Dart Terminal: New Terminal Window, New Terminal Tab, and Toggle Quick
Terminal. All three intents are parameterless, open the app in the foreground,
and enter one fixed-capacity in-process queue. No shell command, terminal text,
working directory, environment, object identifier, or arbitrary action crosses
the Swift boundary.

The application manifest compiles `native/TerminalAppIntents.swift` as module
`DartTerminalAppIntents` and library
`libdart_terminal_app_intents_macos.dylib`. The generic runtime links that image
into the host and stages compiler-extracted `Metadata.appintents` resources.

Dart opens one `TerminalAppIntentsMacosSession` on its root UI isolate. A
session starts disabled, then the owner projects live configuration through
`setEnabled`. `takeCommand` returns an opaque positive operation ID, its current
generation, and one of the three typed actions. The owner completes that exact
command once. Disable, capacity exhaustion, timeout, generation change, and
shutdown resolve or reject commands without retaining callers. Native
callbacks never synchronously re-enter Dart.

The exported `dtai_debug_enqueue_action` symbol is an in-process deterministic
acceptance seam. It admits only the same three action codes through the same
queue and is available to tests via `package:dart_terminal_app_intents_macos/testing.dart`;
it does not invoke or modify Siri, Shortcuts, or user-owned automation.

Packaged acceptance can open that already-staged image through
`openTerminalAppIntentsMacosSelfAutomation()` without moving an FFI boundary
into the consuming application source.
