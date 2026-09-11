import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'terminal_config.dart';
import 'terminal_config_reload.dart';
import 'terminal_core/terminal_screen.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_encoder.dart';

enum TerminalThemeBrightness { light, dark }

/// Product-side availability checks for values whose validity depends on
/// process-visible macOS resources.
final class TerminalMacosConfigValueAvailabilityValidator
    implements TerminalConfigValueAvailabilityValidator {
  const TerminalMacosConfigValueAvailabilityValidator({
    this.fontCatalogInitializer,
  });

  static const int _fontCatalogNotFoundStatus = 3;
  final void Function()? fontCatalogInitializer;

  @override
  TerminalConfigValueAvailabilityIssue? validate(
    TerminalConfigOptionBase option,
    Object? value,
  ) {
    if (!identical(option, TerminalProductConfigSchema.fontFamily)) return null;
    final String family = value as String;
    if (family.isEmpty) return null;
    fontCatalogInitializer?.call();
    TerminalFontCatalog? catalog;
    try {
      catalog = TerminalFontCatalog.open(family: family);
      return null;
    } on TerminalFontCatalogException catch (error) {
      if (error.status != _fontCatalogNotFoundStatus) rethrow;
      return const TerminalConfigValueAvailabilityIssue(
        message: 'font family is not available to this application',
        hint: 'use `font-family = system` or choose an installed font family',
      );
    } finally {
      catalog?.dispose();
    }
  }
}

/// Stable built-in terminal theme catalog.
final class TerminalBuiltInTheme {
  const TerminalBuiltInTheme._({
    required this.name,
    required this.brightness,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.ansiColors,
  });

  static const TerminalBuiltInTheme dartDark = TerminalBuiltInTheme._(
    name: 'Dart Dark',
    brightness: TerminalThemeBrightness.dark,
    foreground: 0x80e5e5e5,
    background: 0x80000000,
    cursor: 0x80e5e5e5,
    ansiColors: TerminalProductConfigSchema.defaultAnsiColors,
  );

  static const TerminalBuiltInTheme dartLight = TerminalBuiltInTheme._(
    name: 'Dart Light',
    brightness: TerminalThemeBrightness.light,
    foreground: 0x8024292f,
    background: 0x80f6f8fa,
    cursor: 0x800969da,
    ansiColors: <int>[
      0x801f2328,
      0x80b42318,
      0x801a7f37,
      0x807d4e00,
      0x800969da,
      0x808250df,
      0x800a7f83,
      0x806e7781,
      0x8057606a,
      0x80cf222e,
      0x80116329,
      0x809a6700,
      0x80218bff,
      0x80a475f9,
      0x800e7490,
      0x8024292f,
    ],
  );

  static const List<TerminalBuiltInTheme> catalog = <TerminalBuiltInTheme>[
    dartLight,
    dartDark,
  ];

  static TerminalBuiltInTheme forBrightness(
    TerminalThemeBrightness brightness,
  ) => switch (brightness) {
    TerminalThemeBrightness.light => dartLight,
    TerminalThemeBrightness.dark => dartDark,
  };

  final String name;
  final TerminalThemeBrightness brightness;
  final int foreground;
  final int background;
  final int cursor;
  final List<int> ansiColors;
}

final class TerminalProductPaletteConfiguration {
  TerminalProductPaletteConfiguration({
    required this.foreground,
    required this.background,
    required this.cursor,
    required Iterable<int> ansiColors,
    this.foregroundIsExplicit = true,
    this.backgroundIsExplicit = true,
    this.cursorIsExplicit = true,
    Iterable<bool>? ansiColorsExplicit,
  }) : ansiColors = List<int>.unmodifiable(ansiColors),
       ansiColorsExplicit = List<bool>.unmodifiable(
         ansiColorsExplicit ?? List<bool>.filled(16, true, growable: false),
       ) {
    if (this.ansiColors.length != 16) {
      throw ArgumentError.value(
        this.ansiColors.length,
        'ansiColors.length',
        'must contain exactly 16 colors',
      );
    }
    if (this.ansiColorsExplicit.length != 16) {
      throw ArgumentError.value(
        this.ansiColorsExplicit.length,
        'ansiColorsExplicit.length',
        'must contain exactly 16 values',
      );
    }
  }

  final int foreground;
  final int background;
  final int cursor;
  final List<int> ansiColors;
  final bool foregroundIsExplicit;
  final bool backgroundIsExplicit;
  final bool cursorIsExplicit;
  final List<bool> ansiColorsExplicit;
}

/// Immutable new-session settings resolved from one typed config snapshot.
final class TerminalProductConfiguration {
  TerminalProductConfiguration._({
    required this.workingDirectory,
    required this.shellExecutable,
    required this.shellIntegration,
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
    required this.clipboardRead,
    required this.clipboardWrite,
    required Iterable<TerminalKeyBindingDefinition> keybindings,
  }) : keybindings = List<TerminalKeyBindingDefinition>.unmodifiable(
         keybindings,
       );

  factory TerminalProductConfiguration.fromSnapshot(
    TerminalConfigSnapshot snapshot,
  ) => TerminalProductConfiguration._(
    workingDirectory: snapshot.value(
      TerminalProductConfigSchema.workingDirectory,
    ),
    shellExecutable: snapshot.value(TerminalProductConfigSchema.shell),
    shellIntegration: snapshot.value(
      TerminalProductConfigSchema.shellIntegration,
    ),
    theme: snapshot.value(TerminalProductConfigSchema.theme),
    palette: _paletteConfigurationFromSnapshot(snapshot),
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
    clipboardRead: snapshot.value(TerminalProductConfigSchema.clipboardRead),
    clipboardWrite: snapshot.value(TerminalProductConfigSchema.clipboardWrite),
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

  final String? workingDirectory;
  final String shellExecutable;
  final TerminalConfiguredShellIntegration shellIntegration;
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
  final TerminalConfiguredClipboardAccess clipboardRead;
  final TerminalConfiguredClipboardAccess clipboardWrite;
  final List<TerminalKeyBindingDefinition> keybindings;

  double get terminalContentWidth => windowWidth - windowPaddingHorizontal * 2;

  double get terminalContentHeight => windowHeight - windowPaddingVertical * 2;

  bool get followsSystemAppearance =>
      theme == TerminalConfiguredTheme.system ||
      theme == TerminalConfiguredTheme.defaultTheme;

  TerminalThemeBrightness resolveThemeBrightness(
    TerminalThemeBrightness systemAppearance,
  ) => switch (theme) {
    TerminalConfiguredTheme.system ||
    TerminalConfiguredTheme.defaultTheme => systemAppearance,
    TerminalConfiguredTheme.light => TerminalThemeBrightness.light,
    TerminalConfiguredTheme.dark => TerminalThemeBrightness.dark,
  };

  TerminalPalette createPalette({
    TerminalThemeBrightness systemAppearance = TerminalThemeBrightness.dark,
  }) {
    final ({List<int> colors, int foreground, int background, int cursor})
    resolved = _resolvedPalette(systemAppearance);
    return TerminalPalette(
      colors: resolved.colors,
      defaultForeground: resolved.foreground,
      defaultBackground: resolved.background,
      cursorColor: resolved.cursor,
    );
  }

  /// Applies a new OS appearance only when this profile follows the system.
  bool applySystemAppearanceToPalette(
    TerminalPalette target,
    TerminalThemeBrightness systemAppearance,
  ) {
    if (!followsSystemAppearance) {
      return false;
    }
    final ({List<int> colors, int foreground, int background, int cursor})
    resolved = _resolvedPalette(systemAppearance);
    return target.applyResetDefaults(
      colors: resolved.colors,
      defaultForeground: resolved.foreground,
      defaultBackground: resolved.background,
      cursorColor: resolved.cursor,
    );
  }

  ({List<int> colors, int foreground, int background, int cursor})
  _resolvedPalette(TerminalThemeBrightness systemAppearance) {
    final TerminalBuiltInTheme selected = TerminalBuiltInTheme.forBrightness(
      resolveThemeBrightness(systemAppearance),
    );
    final TerminalPalette xterm = TerminalPalette();
    final List<int> colors = List<int>.generate(
      TerminalPalette.colorCount,
      xterm.colorAt,
      growable: false,
    );
    colors.setRange(0, selected.ansiColors.length, selected.ansiColors);
    for (int index = 0; index < palette.ansiColors.length; index++) {
      if (palette.ansiColorsExplicit[index]) {
        colors[index] = palette.ansiColors[index];
      }
    }
    return (
      colors: colors,
      foreground: palette.foregroundIsExplicit
          ? palette.foreground
          : selected.foreground,
      background: palette.backgroundIsExplicit
          ? palette.background
          : selected.background,
      cursor: palette.cursorIsExplicit ? palette.cursor : selected.cursor,
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

TerminalProductPaletteConfiguration _paletteConfigurationFromSnapshot(
  TerminalConfigSnapshot snapshot,
) {
  final TerminalResolvedConfigValue<int> foreground = snapshot.resolved(
    TerminalProductConfigSchema.paletteForeground,
  );
  final TerminalResolvedConfigValue<int> background = snapshot.resolved(
    TerminalProductConfigSchema.paletteBackground,
  );
  final TerminalResolvedConfigValue<int> cursor = snapshot.resolved(
    TerminalProductConfigSchema.paletteCursor,
  );
  final List<TerminalResolvedConfigValue<int>> ansi =
      TerminalProductConfigSchema.ansiPalette
          .map(snapshot.resolved<int>)
          .toList(growable: false);
  return TerminalProductPaletteConfiguration(
    foreground: foreground.value,
    background: background.value,
    cursor: cursor.value,
    ansiColors: ansi.map(
      (TerminalResolvedConfigValue<int> value) => value.value,
    ),
    foregroundIsExplicit:
        foreground.source.kind != TerminalConfigSourceKind.schemaDefault,
    backgroundIsExplicit:
        background.source.kind != TerminalConfigSourceKind.schemaDefault,
    cursorIsExplicit:
        cursor.source.kind != TerminalConfigSourceKind.schemaDefault,
    ansiColorsExplicit: ansi.map(
      (TerminalResolvedConfigValue<int> value) =>
          value.source.kind != TerminalConfigSourceKind.schemaDefault,
    ),
  );
}

final class _TerminalLiveInputConfiguration {
  const _TerminalLiveInputConfiguration({
    required this.keyBindingEngine,
    required this.keyEncoder,
  });

  final TerminalKeyBindingEngine keyBindingEngine;
  final TerminalKeyEncoder keyEncoder;
}

/// Application-owned accepted profile and atomically replaceable live input.
final class TerminalProductConfigurationAuthority {
  TerminalProductConfigurationAuthority(
    TerminalProductConfiguration initialConfiguration,
  ) : _newSessionConfiguration = initialConfiguration,
      _liveInput = _createLiveInput(initialConfiguration);

  TerminalProductConfiguration _newSessionConfiguration;
  _TerminalLiveInputConfiguration _liveInput;
  var _acceptedGeneration = 0;
  var _liveGeneration = 0;

  TerminalProductConfiguration get newSessionConfiguration =>
      _newSessionConfiguration;
  TerminalKeyBindingEngine get keyBindingEngine => _liveInput.keyBindingEngine;
  TerminalKeyEncoder get keyEncoder => _liveInput.keyEncoder;
  int get acceptedGeneration => _acceptedGeneration;
  int get liveGeneration => _liveGeneration;

  void applyReload(TerminalConfigReloadResult result) {
    final TerminalConfigChangePlan? plan = result.changePlan;
    if (!result.isAccepted || plan == null) {
      throw ArgumentError.value(
        result.disposition,
        'result',
        'must be an accepted reload result with a change plan',
      );
    }
    final TerminalProductConfiguration next =
        TerminalProductConfiguration.fromSnapshot(result.effectiveSnapshot);
    final _TerminalLiveInputConfiguration? nextLive = plan.liveChanges.isEmpty
        ? null
        : _createLiveInput(next);
    _newSessionConfiguration = next;
    if (nextLive != null) {
      _liveInput = nextLive;
      _liveGeneration++;
    }
    _acceptedGeneration++;
  }

  static _TerminalLiveInputConfiguration _createLiveInput(
    TerminalProductConfiguration configuration,
  ) => _TerminalLiveInputConfiguration(
    keyBindingEngine: configuration.createKeyBindingEngine(),
    keyEncoder: TerminalKeyEncoder(
      optionKeyBehavior: configuration.terminalOptionKeyBehavior,
    ),
  );
}
