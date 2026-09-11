import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalProductConfigurationTests();

Future<void> runTerminalProductConfigurationTests() async {
  _testDefaultsAndSchemaInventory();
  _testBuiltInThemePairAndCustomOverlay();
  _testCompleteFileProfile();
  _testInvalidValuesRecoverIndependently();
  _testMacosFontAvailabilityFallback();
  _testCliPrecedenceAndCapacitySyntax();
  _testConsumerResourceFactoriesAndMappings();
  _testApplicationPoliciesAndSemanticChangePlan();
  await _testAcceptedConfigurationAuthority();
}

void _testMacosFontAvailabilityFallback() {
  const TerminalMacosConfigValueAvailabilityValidator validator =
      TerminalMacosConfigValueAvailabilityValidator();
  final _ProfileMemoryFileSystem files = _ProfileMemoryFileSystem(
    const <String, String>{
      '/system': 'font-family = system\nfont-size = 17\n',
      '/valid': 'font-family = Menlo\nfont-size = 18\n',
      '/missing':
          'font-family = Dart Terminal Definitely Missing Font 0753\n'
          'font-size = 19\n',
    },
  );
  final TerminalConfigSnapshot system =
      TerminalConfigLoader(
        fileSystem: files,
        valueAvailabilityValidator: validator,
      ).resolve(const <String>[
        '--config=/system',
      ], environment: const <String, String>{}).snapshot;
  final TerminalConfigSnapshot valid =
      TerminalConfigLoader(
        fileSystem: files,
        valueAvailabilityValidator: validator,
      ).resolve(const <String>[
        '--config=/valid',
      ], environment: const <String, String>{}).snapshot;
  final TerminalConfigSnapshot missing =
      TerminalConfigLoader(
        fileSystem: files,
        valueAvailabilityValidator: validator,
      ).resolve(const <String>[
        '--config=/missing',
      ], environment: const <String, String>{}).snapshot;
  final TerminalConfigDiagnostic diagnostic = missing.diagnostics.single;
  _expect(
    system.diagnostics.isEmpty &&
        system.value(TerminalProductConfigSchema.fontFamily).isEmpty &&
        valid.diagnostics.isEmpty &&
        valid.value(TerminalProductConfigSchema.fontFamily) == 'Menlo' &&
        missing.value(TerminalProductConfigSchema.fontFamily).isEmpty &&
        missing.value(TerminalProductConfigSchema.fontSize) == 19 &&
        diagnostic.code == 'CFG_UNAVAILABLE_VALUE' &&
        diagnostic.source.path == '/missing' &&
        diagnostic.source.line == 1 &&
        diagnostic.message ==
            '`font-family`: font family is not available to this application' &&
        diagnostic.hint ==
            'use `font-family = system` or choose an installed font family',
    'macOS font availability did not preserve system/valid or recover missing',
  );
}

Future<void> _testAcceptedConfigurationAuthority() async {
  TerminalConfigSnapshot candidate = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--font-size=18',
      '--macos-option-key=text',
      '--keybind=control+d=unbind',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigSnapshot initial = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--font-size=14',
      '--macos-option-key=escape',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => TerminalConfigResolution(
          snapshot: candidate,
          remainingArguments: const <String>[],
        ),
      );
  final TerminalProductConfigurationAuthority authority =
      TerminalProductConfigurationAuthority(
        TerminalProductConfiguration.fromSnapshot(initial),
      );
  final TerminalKeyBindingEngine initialBindings = authority.keyBindingEngine;
  final TerminalKeyEncoder initialEncoder = authority.keyEncoder;
  final TerminalConfigReloadResult mixed = await controller.reload();
  authority.applyReload(mixed);
  _expect(
    authority.acceptedGeneration == 1 &&
        authority.liveGeneration == 1 &&
        authority.newSessionConfiguration.fontSize == 18 &&
        !identical(authority.keyBindingEngine, initialBindings) &&
        !identical(authority.keyEncoder, initialEncoder) &&
        authority.keyBindingEngine
                .resolve(
                  const TerminalKeyEvent(
                    physicalKey: TerminalPhysicalKey.keyD,
                    modifiers: TerminalKeyModifiers(control: true),
                  ),
                )
                .kind ==
            TerminalKeyBindingResolutionKind.noMatch &&
        authority.keyEncoder.optionKeyBehavior ==
            TerminalOptionKeyBehavior.text,
    'accepted mixed reload atomically publishes live input and new-session profile',
  );

  candidate = TerminalConfigLoader().resolve(const <String>[
    '--no-config',
    '--font-size=20',
    '--macos-option-key=text',
    '--keybind=control+d=unbind',
  ], environment: const <String, String>{}).snapshot;
  final TerminalKeyBindingEngine mixedBindings = authority.keyBindingEngine;
  final TerminalKeyEncoder mixedEncoder = authority.keyEncoder;
  final TerminalConfigReloadResult newSessionOnly = await controller.reload();
  authority.applyReload(newSessionOnly);
  _expect(
    authority.acceptedGeneration == 2 &&
        authority.liveGeneration == 1 &&
        authority.newSessionConfiguration.fontSize == 20 &&
        identical(authority.keyBindingEngine, mixedBindings) &&
        identical(authority.keyEncoder, mixedEncoder),
    'new-session-only reload preserves existing live input objects',
  );

  candidate =
      TerminalConfigLoader(
        fileSystem: _ProfileMemoryFileSystem(const <String, String>{
          '/invalid-reload': 'font-size = huge\n',
        }),
      ).resolve(const <String>[
        '--config=/invalid-reload',
      ], environment: const <String, String>{}).snapshot;
  final TerminalConfigReloadResult rejected = await controller.reload();
  _expectThrows(
    () => authority.applyReload(rejected),
    'configuration authority rejects a non-accepted reload result',
  );
  _expect(
    authority.acceptedGeneration == 2 &&
        authority.newSessionConfiguration.fontSize == 20 &&
        identical(authority.keyBindingEngine, mixedBindings),
    'rejected reload cannot mutate the configuration authority',
  );
}

void _testApplicationPoliciesAndSemanticChangePlan() {
  final TerminalConfigSchema schema = TerminalProductConfigSchema.instance;
  final List<TerminalConfigOptionBase> live = schema.options
      .where(
        (TerminalConfigOptionBase option) =>
            option.applicationPolicy == TerminalConfigApplicationPolicy.live,
      )
      .toList(growable: false);
  _expect(
    live.map((TerminalConfigOptionBase option) => option.name).join(',') ==
            'macos-option-key,keybind' &&
        schema.options.length == 36 &&
        schema.options.every(
          (TerminalConfigOptionBase option) =>
              option.applicationPolicy ==
                  TerminalConfigApplicationPolicy.live ||
              option.applicationPolicy ==
                  TerminalConfigApplicationPolicy.newSession,
        ),
    'every product option declares its exact live or new-session policy',
  );

  final TerminalConfigSnapshot previous = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--font-size=15',
      '--macos-option-key=escape',
      '--keybind=control+d=unbind',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigSnapshot candidate = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--font-size=18',
      '--macos-option-key=text',
      '--keybind=control+d=terminal.send-quit-signal',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigChangePlan plan = TerminalConfigChangePlan.between(
    previous,
    candidate,
  );
  _expect(
    plan.changes
            .map((TerminalConfigChange change) => change.option.name)
            .join(',') ==
        'font-size,macos-option-key,keybind',
    'change plan follows deterministic schema order',
  );
  _expect(
    plan.liveChanges
                .map((TerminalConfigChange change) => change.option.name)
                .join(',') ==
            'macos-option-key,keybind' &&
        plan.newSessionChanges.single.option.name == 'font-size',
    'change plan partitions options by declared application policy',
  );

  final TerminalConfigSnapshot sameValuesDifferentSources =
      TerminalConfigLoader().resolve(const <String>[
        '--no-config',
        '--font-size=15',
        '--macos-option-key=escape',
        '--keybind=control+d=unbind',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    TerminalConfigChangePlan.between(
      previous,
      sameValuesDifferentSources,
    ).isEmpty,
    'equal scalar and semantic repeated values produce an empty plan',
  );

  final TerminalConfigSnapshot defaultPalette = TerminalConfigLoader().resolve(
    const <String>['--no-config'],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigSnapshot explicitEqualPalette = TerminalConfigLoader()
      .resolve(const <String>[
        '--no-config',
        '--palette-foreground=#e5e5e5',
      ], environment: const <String, String>{})
      .snapshot;
  final TerminalConfigChangePlan paletteOwnershipChange =
      TerminalConfigChangePlan.between(defaultPalette, explicitEqualPalette);
  _expect(
    paletteOwnershipChange.newSessionChanges.single.option ==
        TerminalProductConfigSchema.paletteForeground,
    'palette schema-default to explicit ownership is a semantic change',
  );
  final TerminalConfigSnapshot explicitEqualPaletteFromFile =
      TerminalConfigLoader(
        fileSystem: _ProfileMemoryFileSystem(const <String, String>{
          '/palette': 'palette-foreground = #e5e5e5\n',
        }),
      ).resolve(const <String>[
        '--config=/palette',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    TerminalConfigChangePlan.between(
      explicitEqualPaletteFromFile,
      explicitEqualPalette,
    ).isEmpty,
    'equal explicit file and CLI palette ownership is not a semantic change',
  );
  final TerminalConfigSnapshot explicitEqualFont = TerminalConfigLoader()
      .resolve(const <String>[
        '--no-config',
        '--font-size=14',
      ], environment: const <String, String>{})
      .snapshot;
  _expect(
    TerminalConfigChangePlan.between(defaultPalette, explicitEqualFont).isEmpty,
    'ordinary provenance-only changes remain omitted from the plan',
  );

  final TerminalConfigOption<int> foreignOption = TerminalConfigOption<int>(
    name: 'foreign',
    description: 'foreign schema option',
    valueSyntax: '<integer>',
    applicationPolicy: TerminalConfigApplicationPolicy.newSession,
    defaultValue: 0,
    parser: (String value) => TerminalConfigDecodeResult<int>.success(0),
    formatter: (int value) => value.toString(),
  );
  final TerminalConfigSnapshot foreign =
      TerminalConfigLoader(
        schema: TerminalConfigSchema(<TerminalConfigOptionBase>[foreignOption]),
      ).resolve(const <String>[
        '--no-config',
      ], environment: const <String, String>{}).snapshot;
  _expectThrows(
    () => TerminalConfigChangePlan.between(previous, foreign),
    'change planning rejects snapshots from different schema authorities',
  );
}

void _testDefaultsAndSchemaInventory() {
  final TerminalProductConfiguration defaults =
      TerminalProductConfiguration.defaults;
  _expect(
    TerminalProductConfigSchema.instance.options.length == 36 &&
        TerminalProductConfigSchema.instance.options
                .map((TerminalConfigOptionBase option) => option.name)
                .toSet()
                .length ==
            36 &&
        TerminalProductConfigSchema.instance.options.every(
          (TerminalConfigOptionBase option) => option.description.isNotEmpty,
        ),
    'product schema has 36 unique documented options',
  );
  _expect(
    defaults.workingDirectory == null &&
        defaults.shellExecutable == '/bin/zsh' &&
        defaults.shellIntegration ==
            TerminalConfiguredShellIntegration.detect &&
        defaults.theme == TerminalConfiguredTheme.system &&
        defaults.palette.foreground == 0x80e5e5e5 &&
        defaults.palette.background == 0x80000000 &&
        defaults.palette.cursor == 0x80e5e5e5 &&
        _listEquals(
          defaults.palette.ansiColors,
          TerminalProductConfigSchema.defaultAnsiColors,
        ) &&
        !defaults.palette.foregroundIsExplicit &&
        !defaults.palette.backgroundIsExplicit &&
        !defaults.palette.cursorIsExplicit &&
        defaults.palette.ansiColorsExplicit.every((bool value) => !value) &&
        defaults.fontFamily.isEmpty &&
        defaults.fontSize == 14 &&
        defaults.fontSyntheticStyle == TerminalConfiguredSyntheticStyle.allow &&
        defaults.windowWidth == 920 &&
        defaults.windowHeight == 580 &&
        defaults.windowPaddingHorizontal == 0 &&
        defaults.windowPaddingVertical == 0 &&
        defaults.terminalContentWidth == 920 &&
        defaults.terminalContentHeight == 580 &&
        defaults.macosOptionKey == TerminalConfiguredOptionKey.escape &&
        defaults.scrollbackLines == 10000 &&
        defaults.scrollbackBytes == 64 * 1024 * 1024 &&
        defaults.cursorShape == TerminalConfiguredCursorShape.block &&
        defaults.cursorBlink &&
        defaults.keybindings.isEmpty,
    'zero-config profile exactly preserves existing product defaults',
  );
  _expectThrows(
    () => defaults.palette.ansiColors.add(0x80000000),
    'palette profile is immutable',
  );
  _expectThrows(
    () => defaults.palette.ansiColorsExplicit.add(true),
    'palette provenance profile is immutable',
  );
  _expectThrows(
    () => defaults.keybindings.add(
      const TerminalKeyBindingDefinition.unbind(
        chord: TerminalKeyBindingChord(
          physicalKey: TerminalPhysicalKey.keyD,
          control: true,
        ),
      ),
    ),
    'keybinding profile is immutable',
  );
}

void _testBuiltInThemePairAndCustomOverlay() {
  _expect(
    TerminalBuiltInTheme.catalog.length == 2 &&
        TerminalBuiltInTheme.catalog[0].name == 'Dart Light' &&
        TerminalBuiltInTheme.catalog[0].brightness ==
            TerminalThemeBrightness.light &&
        TerminalBuiltInTheme.catalog[1].name == 'Dart Dark' &&
        TerminalBuiltInTheme.catalog[1].brightness ==
            TerminalThemeBrightness.dark &&
        TerminalBuiltInTheme.catalog.every(
          (TerminalBuiltInTheme theme) => theme.ansiColors.length == 16,
        ) &&
        TerminalBuiltInTheme.catalog.every(
          (TerminalBuiltInTheme theme) =>
              _contrastRatio(theme.foreground, theme.background) >= 7,
        ),
    'built-in catalog exposes one stable high-contrast light/dark pair',
  );
  _expectThrows(
    () => TerminalBuiltInTheme.catalog.add(TerminalBuiltInTheme.dartDark),
    'built-in theme catalog is immutable',
  );

  TerminalProductConfiguration profile(List<String> arguments) =>
      TerminalProductConfiguration.fromSnapshot(
        TerminalConfigLoader().resolve(<String>[
          '--no-config',
          ...arguments,
        ], environment: const <String, String>{}).snapshot,
      );

  final TerminalProductConfiguration system = profile(const <String>[]);
  final TerminalProductConfiguration alias = profile(const <String>[
    '--theme=default',
  ]);
  final TerminalProductConfiguration light = profile(const <String>[
    '--theme=light',
  ]);
  final TerminalProductConfiguration dark = profile(const <String>[
    '--theme=dark',
  ]);
  final TerminalPalette systemLight = system.createPalette(
    systemAppearance: TerminalThemeBrightness.light,
  );
  final TerminalPalette systemDark = system.createPalette(
    systemAppearance: TerminalThemeBrightness.dark,
  );
  final TerminalPalette fixedLight = light.createPalette(
    systemAppearance: TerminalThemeBrightness.dark,
  );
  final TerminalPalette fixedDark = dark.createPalette(
    systemAppearance: TerminalThemeBrightness.light,
  );
  _expect(
    alias.theme == TerminalConfiguredTheme.system &&
        system.followsSystemAppearance &&
        alias.followsSystemAppearance &&
        !light.followsSystemAppearance &&
        !dark.followsSystemAppearance &&
        light.resolveThemeBrightness(TerminalThemeBrightness.dark) ==
            TerminalThemeBrightness.light &&
        dark.resolveThemeBrightness(TerminalThemeBrightness.light) ==
            TerminalThemeBrightness.dark,
    'system/default alias and fixed selectors resolve deterministically',
  );
  _expect(
    systemLight.defaultForeground ==
            TerminalBuiltInTheme.dartLight.foreground &&
        systemLight.defaultBackground ==
            TerminalBuiltInTheme.dartLight.background &&
        systemLight.cursorColor == TerminalBuiltInTheme.dartLight.cursor &&
        systemLight.colorAt(0) ==
            TerminalBuiltInTheme.dartLight.ansiColors[0] &&
        fixedLight.defaultBackground ==
            TerminalBuiltInTheme.dartLight.background &&
        systemDark.defaultForeground ==
            TerminalPalette.xtermDefaultForeground &&
        systemDark.defaultBackground ==
            TerminalPalette.xtermDefaultBackground &&
        fixedDark.colorAt(15) ==
            TerminalProductConfigSchema.defaultAnsiColors[15] &&
        systemLight.colorAt(16) == systemDark.colorAt(16) &&
        systemLight.colorAt(255) == systemDark.colorAt(255),
    'built-in pair selects exact logical/ANSI colors and preserves xterm tail',
  );

  final TerminalProductConfiguration custom = profile(const <String>[
    '--theme=system',
    '--palette-background=#112233',
    '--palette-3=#445566',
  ]);
  final TerminalPalette customPalette = custom.createPalette(
    systemAppearance: TerminalThemeBrightness.light,
  );
  _expect(
    !custom.palette.foregroundIsExplicit &&
        custom.palette.backgroundIsExplicit &&
        !custom.palette.cursorIsExplicit &&
        custom.palette.ansiColorsExplicit[3] &&
        custom.palette.ansiColorsExplicit.where((bool value) => value).length ==
            1 &&
        customPalette.defaultForeground ==
            TerminalBuiltInTheme.dartLight.foreground &&
        customPalette.defaultBackground == 0x80112233 &&
        customPalette.colorAt(3) == 0x80445566,
    'explicit palette provenance forms a sparse custom theme overlay',
  );

  final TerminalScreen screen = TerminalScreen(
    rows: 1,
    columns: 1,
    palette: customPalette,
  );
  final int lightAnsiOne = customPalette.colorAt(1);
  screen.setPaletteColor(1, lightAnsiOne);
  screen.setDefaultForegroundColor(customPalette.defaultForeground);
  final int generation = customPalette.generation;
  _expect(
    custom.applySystemAppearanceToPalette(
          customPalette,
          TerminalThemeBrightness.dark,
        ) &&
        customPalette.generation == generation + 1 &&
        customPalette.colorAt(0) ==
            TerminalBuiltInTheme.dartDark.ansiColors[0] &&
        customPalette.colorAt(1) == lightAnsiOne &&
        customPalette.colorAt(3) == 0x80445566 &&
        customPalette.defaultForeground ==
            TerminalBuiltInTheme.dartLight.foreground &&
        customPalette.defaultBackground == 0x80112233,
    'system switch preserves config and same-value OSC override layers',
  );
  screen.resetPaletteColor(1);
  screen.resetDefaultForegroundColor();
  _expect(
    customPalette.colorAt(1) == TerminalBuiltInTheme.dartDark.ansiColors[1] &&
        customPalette.defaultForeground ==
            TerminalBuiltInTheme.dartDark.foreground &&
        customPalette.defaultBackground == 0x80112233,
    'OSC reset reveals the new dark theme beneath the custom overlay',
  );
  final int fixedGeneration = fixedLight.generation;
  _expect(
    !light.applySystemAppearanceToPalette(
          fixedLight,
          TerminalThemeBrightness.light,
        ) &&
        fixedLight.generation == fixedGeneration,
    'fixed theme rejects system appearance projection',
  );
  _expectThrows(
    () => TerminalProductPaletteConfiguration(
      foreground: 0x80111111,
      background: 0x80222222,
      cursor: 0x80333333,
      ansiColors: List<int>.filled(16, 0x80444444),
      ansiColorsExplicit: const <bool>[true],
    ),
    'custom palette rejects mismatched provenance storage',
  );
}

void _testCompleteFileProfile() {
  final StringBuffer config = StringBuffer()
    ..writeln('working-directory = /configured/work')
    ..writeln('shell = /opt/homebrew/bin/fish')
    ..writeln('shell-integration = fish')
    ..writeln('theme = system')
    ..writeln('palette-foreground = #112233 # configured foreground')
    ..writeln('palette-background = #010203')
    ..writeln('palette-cursor = #abcdef');
  for (var index = 0; index < 16; index += 1) {
    config.writeln(
      'palette-$index = #${index.toRadixString(16).padLeft(6, '0')}',
    );
  }
  config
    ..writeln('font-family = "JetBrains Mono"')
    ..writeln('font-size = 17.5')
    ..writeln('font-synthetic-style = deny')
    ..writeln('window-width = 1200')
    ..writeln('window-height = 760')
    ..writeln('window-padding-horizontal = 12')
    ..writeln('window-padding-vertical = 8')
    ..writeln('macos-option-key = text')
    ..writeln('scrollback-lines = 50000')
    ..writeln('scrollback-bytes = 128MiB')
    ..writeln('cursor-shape = bar')
    ..writeln('cursor-blink = false')
    ..writeln('keybind = control+d=unbind')
    ..writeln('keybind = shift+control+k=pane.focus-next');
  final _ProfileMemoryFileSystem files = _ProfileMemoryFileSystem(
    <String, String>{'/profile': config.toString()},
  );
  final TerminalConfigSnapshot snapshot =
      TerminalConfigLoader(fileSystem: files).resolve(const <String>[
        '--config=/profile',
      ], environment: const <String, String>{}).snapshot;
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(snapshot);
  _expect(snapshot.diagnostics.isEmpty, 'complete profile has no diagnostics');
  _expect(
    profile.workingDirectory == '/configured/work' &&
        profile.shellExecutable == '/opt/homebrew/bin/fish' &&
        profile.shellIntegration == TerminalConfiguredShellIntegration.fish &&
        profile.theme == TerminalConfiguredTheme.system &&
        profile.palette.foreground == 0x80112233 &&
        profile.palette.background == 0x80010203 &&
        profile.palette.cursor == 0x80abcdef &&
        profile.palette.ansiColors[15] == 0x8000000f &&
        profile.palette.foregroundIsExplicit &&
        profile.palette.backgroundIsExplicit &&
        profile.palette.cursorIsExplicit &&
        profile.palette.ansiColorsExplicit.every((bool value) => value) &&
        profile.fontFamily == 'JetBrains Mono' &&
        profile.fontSize == 17.5 &&
        profile.fontSyntheticStyle == TerminalConfiguredSyntheticStyle.deny &&
        profile.windowWidth == 1200 &&
        profile.windowHeight == 760 &&
        profile.windowPaddingHorizontal == 12 &&
        profile.windowPaddingVertical == 8 &&
        profile.terminalContentWidth == 1176 &&
        profile.terminalContentHeight == 744 &&
        profile.macosOptionKey == TerminalConfiguredOptionKey.text &&
        profile.scrollbackLines == 50000 &&
        profile.scrollbackBytes == 128 * 1024 * 1024 &&
        profile.cursorShape == TerminalConfiguredCursorShape.bar &&
        !profile.cursorBlink &&
        profile.keybindings.length == 2 &&
        profile.keybindings.first.directive ==
            TerminalKeyBindingDirective.unbind &&
        profile.keybindings.last.applicationAction ==
            TerminalActionId.focusNextPane,
    'all option families resolve into one immutable typed profile',
  );
}

void _testInvalidValuesRecoverIndependently() {
  final _ProfileMemoryFileSystem files = _ProfileMemoryFileSystem(
    const <String, String>{
      '/invalid': '''
theme = unknown
shell = zsh
shell-integration = automatic
palette-foreground = red
palette-0 = #ffff
font-family =
font-size = nan
font-synthetic-style = maybe
window-width = 479
window-height = 8193
window-padding-horizontal = -1
window-padding-vertical = 65
macos-option-key = meta
scrollback-lines = 0
scrollback-bytes = 2GiB
cursor-shape = beam
cursor-blink = yes
''',
    },
  );
  final TerminalConfigSnapshot snapshot =
      TerminalConfigLoader(fileSystem: files).resolve(const <String>[
        '--config=/invalid',
      ], environment: const <String, String>{}).snapshot;
  final TerminalProductConfiguration recovered =
      TerminalProductConfiguration.fromSnapshot(snapshot);
  _expect(
    snapshot.diagnostics.length == 17 &&
        snapshot.diagnostics.every(
          (TerminalConfigDiagnostic diagnostic) =>
              diagnostic.code == 'CFG_INVALID_VALUE' &&
              diagnostic.source.path == '/invalid' &&
              diagnostic.hint != null,
        ),
    'each invalid option reports one located actionable diagnostic',
  );
  _expect(
    recovered.palette.foreground ==
            TerminalProductConfiguration.defaults.palette.foreground &&
        recovered.shellExecutable == '/bin/zsh' &&
        recovered.shellIntegration ==
            TerminalConfiguredShellIntegration.detect &&
        recovered.fontSize == TerminalProductConfiguration.defaults.fontSize &&
        recovered.windowWidth ==
            TerminalProductConfiguration.defaults.windowWidth &&
        recovered.macosOptionKey ==
            TerminalProductConfiguration.defaults.macosOptionKey &&
        recovered.scrollbackBytes ==
            TerminalProductConfiguration.defaults.scrollbackBytes &&
        recovered.cursorShape ==
            TerminalProductConfiguration.defaults.cursorShape,
    'invalid values independently recover to their schema defaults',
  );
}

void _testCliPrecedenceAndCapacitySyntax() {
  final _ProfileMemoryFileSystem files = _ProfileMemoryFileSystem(
    const <String, String>{
      '/profile': '''
font-family = Menlo
font-size = 15
scrollback-bytes = 1024B
cursor-blink = false
''',
    },
  );
  final TerminalConfigSnapshot snapshot =
      TerminalConfigLoader(fileSystem: files).resolve(const <String>[
        '--config=/profile',
        '--font-family=system',
        '--font-size=18',
        '--scrollback-bytes=2MiB',
        '--cursor-blink=true',
      ], environment: const <String, String>{}).snapshot;
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(snapshot);
  _expect(
    profile.fontFamily.isEmpty &&
        profile.fontSize == 18 &&
        profile.scrollbackBytes == 2 * 1024 * 1024 &&
        profile.cursorBlink &&
        snapshot.resolved(TerminalProductConfigSchema.fontSize).source.kind ==
            TerminalConfigSourceKind.commandLine,
    'CLI values use identical codecs and win over file values',
  );
  for (final String invalid in <String>[
    '--palette-background=#12345g',
    '--font-size=Infinity',
    '--scrollback-bytes=1MB',
    '--scrollback-lines=1000001',
  ]) {
    _expectThrows(
      () => TerminalConfigLoader(fileSystem: files)
          .resolve(<String>[invalid], environment: const <String, String>{}),
      'invalid CLI config value is a usage failure: $invalid',
    );
  }
}

void _testConsumerResourceFactoriesAndMappings() {
  final TerminalConfigSnapshot snapshot = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--palette-foreground=#102030',
      '--palette-background=#405060',
      '--palette-cursor=#708090',
      '--palette-2=#a0b0c0',
      '--font-synthetic-style=deny',
      '--macos-option-key=text',
      '--scrollback-lines=321',
      '--scrollback-bytes=2MiB',
      '--cursor-shape=underline',
      '--cursor-blink=false',
      '--keybind=control+d=unbind',
      '--keybind=shift+control+k=pane.focus-next',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(snapshot);
  final TerminalPalette firstPalette = profile.createPalette();
  final TerminalPalette secondPalette = profile.createPalette();
  final TerminalScrollback firstScrollback = profile.createScrollback();
  final TerminalScrollback secondScrollback = profile.createScrollback();
  final TerminalKeyBindingEngine keyBindings = profile.createKeyBindingEngine();
  _expect(
    !identical(firstPalette, secondPalette) &&
        firstPalette.defaultForeground == 0x80102030 &&
        firstPalette.defaultBackground == 0x80405060 &&
        firstPalette.cursorColor == 0x80708090 &&
        firstPalette.colorAt(2) == 0x80a0b0c0 &&
        firstPalette.colorAt(16) == secondPalette.colorAt(16) &&
        !identical(firstScrollback, secondScrollback) &&
        firstScrollback.maxLines == 321 &&
        firstScrollback.maxBytes == 2 * 1024 * 1024 &&
        profile.terminalCursorShape == TerminalCursorShape.underline &&
        profile.terminalSyntheticStylePolicy ==
            TerminalSyntheticStylePolicy.reject &&
        profile.terminalOptionKeyBehavior == TerminalOptionKeyBehavior.text &&
        keyBindings
                .resolve(
                  const TerminalKeyEvent(
                    physicalKey: TerminalPhysicalKey.keyD,
                    modifiers: TerminalKeyModifiers(control: true),
                  ),
                )
                .kind ==
            TerminalKeyBindingResolutionKind.noMatch &&
        keyBindings
                .resolve(
                  const TerminalKeyEvent(
                    physicalKey: TerminalPhysicalKey.keyK,
                    modifiers: TerminalKeyModifiers(shift: true, control: true),
                  ),
                )
                .applicationAction ==
            TerminalActionId.focusNextPane,
    'profile creates independent bounded consumer resources and exact enums',
  );
}

final class _ProfileMemoryFileSystem implements TerminalConfigFileSystem {
  _ProfileMemoryFileSystem(Map<String, String> files)
    : _files = Map<String, List<int>>.unmodifiable(
        files.map(
          (String path, String value) =>
              MapEntry<String, List<int>>(path, utf8.encode(value)),
        ),
      );

  final Map<String, List<int>> _files;

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  List<int> readBytes(String path) => List<int>.from(_files[path]!);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      includedPath.startsWith('/') ? includedPath : '/$includedPath';
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

double _contrastRatio(int first, int second) {
  double luminance(int color) {
    double channel(int shift) {
      final double value = ((color >> shift) & 0xff) / 255;
      return value <= 0.04045
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  final double firstLuminance = luminance(first);
  final double secondLuminance = luminance(second);
  final double lighter = math.max(firstLuminance, secondLuminance);
  final double darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal product configuration expectation failed: $description',
    );
  }
}

void _expectThrows(void Function() callback, String description) {
  try {
    callback();
  } on Object {
    return;
  }
  throw StateError(
    'terminal product configuration expectation failed: $description',
  );
}
