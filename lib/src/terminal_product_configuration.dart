import 'terminal_config.dart';

final class TerminalProductPaletteConfiguration {
  TerminalProductPaletteConfiguration({
    required this.foreground,
    required this.background,
    required this.cursor,
    required Iterable<int> ansiColors,
  }) : ansiColors = List<int>.unmodifiable(ansiColors) {
    if (this.ansiColors.length != 16) {
      throw ArgumentError.value(
        this.ansiColors.length,
        'ansiColors.length',
        'must contain exactly 16 colors',
      );
    }
  }

  final int foreground;
  final int background;
  final int cursor;
  final List<int> ansiColors;
}

/// Immutable new-session settings resolved from one typed config snapshot.
final class TerminalProductConfiguration {
  TerminalProductConfiguration._({
    required this.theme,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.fontSyntheticStyle,
    required this.windowWidth,
    required this.windowHeight,
    required this.windowPaddingHorizontal,
    required this.windowPaddingVertical,
    required this.macosOptionKey,
    required this.scrollbackLines,
    required this.scrollbackBytes,
    required this.cursorShape,
    required this.cursorBlink,
  });

  factory TerminalProductConfiguration.fromSnapshot(
    TerminalConfigSnapshot snapshot,
  ) => TerminalProductConfiguration._(
    theme: snapshot.value(TerminalProductConfigSchema.theme),
    palette: TerminalProductPaletteConfiguration(
      foreground: snapshot.value(TerminalProductConfigSchema.paletteForeground),
      background: snapshot.value(TerminalProductConfigSchema.paletteBackground),
      cursor: snapshot.value(TerminalProductConfigSchema.paletteCursor),
      ansiColors: TerminalProductConfigSchema.ansiPalette.map(
        snapshot.value<int>,
      ),
    ),
    fontFamily: snapshot.value(TerminalProductConfigSchema.fontFamily),
    fontSize: snapshot.value(TerminalProductConfigSchema.fontSize),
    fontSyntheticStyle: snapshot.value(
      TerminalProductConfigSchema.fontSyntheticStyle,
    ),
    windowWidth: snapshot.value(TerminalProductConfigSchema.windowWidth),
    windowHeight: snapshot.value(TerminalProductConfigSchema.windowHeight),
    windowPaddingHorizontal: snapshot.value(
      TerminalProductConfigSchema.windowPaddingHorizontal,
    ),
    windowPaddingVertical: snapshot.value(
      TerminalProductConfigSchema.windowPaddingVertical,
    ),
    macosOptionKey: snapshot.value(TerminalProductConfigSchema.macosOptionKey),
    scrollbackLines: snapshot.value(
      TerminalProductConfigSchema.scrollbackLines,
    ),
    scrollbackBytes: snapshot.value(
      TerminalProductConfigSchema.scrollbackBytes,
    ),
    cursorShape: snapshot.value(TerminalProductConfigSchema.cursorShape),
    cursorBlink: snapshot.value(TerminalProductConfigSchema.cursorBlink),
  );

  static final TerminalProductConfiguration defaults =
      TerminalProductConfiguration.fromSnapshot(
        TerminalConfigLoader().resolve(const <String>[
          '--no-config',
        ], environment: const <String, String>{}).snapshot,
      );

  final TerminalConfiguredTheme theme;
  final TerminalProductPaletteConfiguration palette;
  final String fontFamily;
  final double fontSize;
  final TerminalConfiguredSyntheticStyle fontSyntheticStyle;
  final double windowWidth;
  final double windowHeight;
  final double windowPaddingHorizontal;
  final double windowPaddingVertical;
  final TerminalConfiguredOptionKey macosOptionKey;
  final int scrollbackLines;
  final int scrollbackBytes;
  final TerminalConfiguredCursorShape cursorShape;
  final bool cursorBlink;

  double get terminalContentWidth => windowWidth - windowPaddingHorizontal * 2;

  double get terminalContentHeight => windowHeight - windowPaddingVertical * 2;
}
