# Dart Terminal

Dart Terminal is an independent terminal emulator for macOS, written primarily
in Dart. It combines native AppKit windows with persistent PTY sessions,
CoreText text shaping, and Metal rendering. Ghostty is used as a quality and
compatibility reference only; neither Ghostty nor `libghostty` is embedded in
the application.

Dart Terminal currently targets macOS 14 or later. Apple Silicon is the primary
development and acceptance platform.

## Launch

To open an existing application bundle, double-click `DartTerminal.app` in
Finder or run:

```shell
open /path/to/DartTerminal.app
```

A new terminal starts in your home directory unless another working directory
is explicitly configured.

### Run from source on Apple Silicon

The source build expects a sibling checkout of `dart_appkit` and a Dart SDK
compatible with the version declared in `pubspec.yaml`. First prepare the
unmodified Dart engine used by the runtime:

```shell
cd ../dart_appkit
make engine
```

Then return to this repository, resolve the Dart packages, and launch the
Developer JIT application:

```shell
cd ../dart_terminal
dart pub get
make RUNTIME_ARCH=arm64 developer-jit-run
```

## Highlights

- **A native terminal core.** Persistent login shells, modern VT behavior,
  Unicode text, IME composition, keyboard and mouse input, selection, and the
  clipboard are integrated with a CoreText and Metal display pipeline.
- **Windows, tabs, and split panes.** Sessions can be organized without leaving
  the keyboard, with native menus and a searchable command palette available
  when a command is easier to discover than to remember.
- **Context Dock.** A side panel keeps useful context visible without covering
  the terminal. Directory Navigator shows and searches the current directory
  tree, while Process Inspector summarizes the foreground command. The two
  views remain available while moving between windows, tabs, and panes.
- **A macOS-first experience.** The application includes native text input,
  accessibility support, secure keyboard entry, Quick Look, configurable
  keybindings, themes, and appearance settings.

## Learn more

- [Configuration and command-line reference](docs/reference/configuration-and-command-line.md)
- [Keybindings and actions](docs/reference/keybindings-and-actions.md)
- [Terminal inspector and local diagnostics](docs/reference/terminal-diagnostics.md)
- [Feature status](FEATURE_MATRIX.md)
- [Development roadmap](ROADMAP.md)
