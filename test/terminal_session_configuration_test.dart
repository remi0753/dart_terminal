import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalSessionConfigurationTests();

Future<void> runTerminalSessionConfigurationTests() async {
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(
        TerminalConfigLoader().resolve(const <String>[
          '--no-config',
          '--palette-foreground=#112233',
          '--palette-background=#223344',
          '--palette-cursor=#334455',
          '--palette-4=#445566',
          '--scrollback-lines=456',
          '--scrollback-bytes=3MiB',
          '--cursor-shape=bar',
          '--cursor-blink=false',
        ], environment: const <String, String>{}).snapshot,
      );
  final TerminalSession first = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(1), generation: 1),
    ptyBackend: FakePtyBackend(),
    palette: profile.createPalette(),
    scrollback: profile.createScrollback(),
    initialCursorShape: profile.terminalCursorShape,
    initialCursorBlinking: profile.cursorBlink,
    onChanged: () {},
    onTerminated: () {},
  );
  final TerminalSession second = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(2), generation: 1),
    ptyBackend: FakePtyBackend(),
    palette: profile.createPalette(),
    scrollback: profile.createScrollback(),
    initialCursorShape: profile.terminalCursorShape,
    initialCursorBlinking: profile.cursorBlink,
    onChanged: () {},
    onTerminated: () {},
  );
  try {
    final TerminalScreenSet screens = first.terminalScreenSet;
    _expect(
      !identical(screens.palette, second.terminalScreenSet.palette) &&
          !identical(screens.scrollback, second.terminalScreenSet.scrollback) &&
          screens.palette.defaultForeground == 0x80112233 &&
          screens.palette.defaultBackground == 0x80223344 &&
          screens.palette.cursorColor == 0x80334455 &&
          screens.palette.colorAt(4) == 0x80445566 &&
          screens.scrollback.maxLines == 456 &&
          screens.scrollback.maxBytes == 3 * 1024 * 1024 &&
          screens.primary.cursorShape == TerminalCursorShape.bar &&
          !screens.primary.cursorBlinking &&
          screens.alternate.cursorShape == TerminalCursorShape.bar &&
          !screens.alternate.cursorBlinking,
      'session owns configured palette, scrollback, and both cursor defaults',
    );
    screens.primary.setCursorPresentation(
      shape: TerminalCursorShape.block,
      blinking: true,
    );
    screens.primary.resetTerminalState();
    screens.resize(rows: 31, columns: 101);
    screens.primary.setCursorPresentation(
      shape: TerminalCursorShape.underline,
      blinking: true,
    );
    screens.primary.resetTerminalState();
    _expect(
      screens.primary.rows == 31 &&
          screens.primary.columns == 101 &&
          screens.primary.cursorShape == TerminalCursorShape.bar &&
          !screens.primary.cursorBlinking &&
          screens.primary.initialCursorShape == TerminalCursorShape.bar &&
          !screens.primary.initialCursorBlinking,
      'RIS and reflow retain configured cursor reset semantics',
    );
  } finally {
    await first.dispose();
    await second.dispose();
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('session configuration expectation failed: $description');
  }
}
