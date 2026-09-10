import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalProductConfigurationTests();

void runTerminalProductConfigurationTests() {
  _testDefaultsAndSchemaInventory();
  _testCompleteFileProfile();
  _testInvalidValuesRecoverIndependently();
  _testCliPrecedenceAndCapacitySyntax();
  _testConsumerResourceFactoriesAndMappings();
}

void _testDefaultsAndSchemaInventory() {
  final TerminalProductConfiguration defaults =
      TerminalProductConfiguration.defaults;
  _expect(
    TerminalProductConfigSchema.instance.options.length == 34 &&
        TerminalProductConfigSchema.instance.options
                .map((TerminalConfigOptionBase option) => option.name)
                .toSet()
                .length ==
            34 &&
        TerminalProductConfigSchema.instance.options.every(
          (TerminalConfigOptionBase option) => option.description.isNotEmpty,
        ),
    'product schema has 33 unique documented options',
  );
  _expect(
    defaults.theme == TerminalConfiguredTheme.defaultTheme &&
        defaults.palette.foreground == 0x80e5e5e5 &&
        defaults.palette.background == 0x80000000 &&
        defaults.palette.cursor == 0x80e5e5e5 &&
        _listEquals(
          defaults.palette.ansiColors,
          TerminalProductConfigSchema.defaultAnsiColors,
        ) &&
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

void _testCompleteFileProfile() {
  final StringBuffer config = StringBuffer()
    ..writeln('theme = default')
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
    profile.palette.foreground == 0x80112233 &&
        profile.palette.background == 0x80010203 &&
        profile.palette.cursor == 0x80abcdef &&
        profile.palette.ansiColors[15] == 0x8000000f &&
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
    snapshot.diagnostics.length == 15 &&
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
