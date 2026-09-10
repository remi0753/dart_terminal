import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'terminal_config.dart';
import 'terminal_core/terminal_screen.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_encoder.dart';

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
    required Iterable<TerminalKeyBindingDefinition> keybindings,
  }) : keybindings = List<TerminalKeyBindingDefinition>.unmodifiable(
         keybindings,
       );

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
    keybindings: snapshot
        .occurrences(TerminalProductConfigSchema.keybind)
        .map(
          (TerminalResolvedConfigValue<TerminalKeyBindingDefinition> value) =>
              value.value,
        ),
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
  final List<TerminalKeyBindingDefinition> keybindings;

  double get terminalContentWidth => windowWidth - windowPaddingHorizontal * 2;

  double get terminalContentHeight => windowHeight - windowPaddingVertical * 2;

  TerminalPalette createPalette() {
    final TerminalPalette xterm = TerminalPalette();
    final List<int> colors = List<int>.generate(
      TerminalPalette.colorCount,
      xterm.colorAt,
      growable: false,
    );
    colors.setRange(0, palette.ansiColors.length, palette.ansiColors);
    return TerminalPalette(
      colors: colors,
      defaultForeground: palette.foreground,
      defaultBackground: palette.background,
      cursorColor: palette.cursor,
    );
  }

  TerminalScrollback createScrollback() =>
      TerminalScrollback(maxLines: scrollbackLines, maxBytes: scrollbackBytes);

  TerminalKeyBindingEngine createKeyBindingEngine() =>
      TerminalKeyBindingEngine.standardWithOrderedOverrides(keybindings);

  TerminalCursorShape get terminalCursorShape => switch (cursorShape) {
    TerminalConfiguredCursorShape.block => TerminalCursorShape.block,
    TerminalConfiguredCursorShape.underline => TerminalCursorShape.underline,
    TerminalConfiguredCursorShape.bar => TerminalCursorShape.bar,
  };

  TerminalSyntheticStylePolicy get terminalSyntheticStylePolicy =>
      switch (fontSyntheticStyle) {
        TerminalConfiguredSyntheticStyle.allow =>
          TerminalSyntheticStylePolicy.allow,
        TerminalConfiguredSyntheticStyle.deny =>
          TerminalSyntheticStylePolicy.reject,
      };

  TerminalOptionKeyBehavior get terminalOptionKeyBehavior =>
      switch (macosOptionKey) {
        TerminalConfiguredOptionKey.escape => TerminalOptionKeyBehavior.escape,
        TerminalConfiguredOptionKey.text => TerminalOptionKeyBehavior.text,
      };
}
