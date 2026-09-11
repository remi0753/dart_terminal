import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';

void main() => runTerminalConfigTests();

void runTerminalConfigTests() {
  _testSchemaAndZeroConfig();
  _testDefaultLocationAndPrecedence();
  _testRepeatableKeybindOccurrences();
  _testDiagnosticsAndRecovery();
  _testResolvedFileValueAvailabilityFallback();
  _testIncludeCycleAndBounds();
  _testTerminalOptionsIntegration();
}

void _testRepeatableKeybindOccurrences() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{
      '/root': '''
include = child
keybind = shift+control+k=pane.focus-next
''',
      '/child': '''
keybind = control+d=unbind
''',
      '/invalid': '''
keybind = command+d=pane.focus-next
keybind = control+not-a-key=passthrough
keybind = control+x=application.not-real
keybind = control+y=terminal.send-suspend-signal
''',
      '/bounded': '''
item = one
item = two
item = three
''',
    },
  );
  final TerminalConfigSnapshot ordered = TerminalConfigLoader(fileSystem: files)
      .resolve(const <String>[
        '--config=/root',
        '--keybind=option+j=terminal.send-quit-signal',
        '--keybind=command+k=passthrough',
      ], environment: const <String, String>{})
      .snapshot;
  final List<TerminalResolvedConfigValue<TerminalKeyBindingDefinition>>
  occurrences = ordered.occurrences(TerminalProductConfigSchema.keybind);
  _expect(
    ordered.diagnostics.isEmpty &&
        occurrences.length == 4 &&
        occurrences[0].value.chord.configName == 'control+d' &&
        occurrences[0].value.directive == TerminalKeyBindingDirective.unbind &&
        occurrences[0].source.path == '/child' &&
        occurrences[1].value.chord.configName == 'shift+control+k' &&
        occurrences[1].value.applicationAction ==
            TerminalActionId.focusNextPane &&
        occurrences[1].source.path == '/root' &&
        occurrences[2].value.action ==
            TerminalKeyBindingAction.sendQuitSignal &&
        occurrences[2].source.kind == TerminalConfigSourceKind.commandLine &&
        occurrences[2].source.line == 2 &&
        occurrences[3].value.directive ==
            TerminalKeyBindingDirective.passthrough &&
        occurrences[3].source.line == 3,
    'repeatable keybinds retain include/root/CLI order and per-item provenance',
  );
  _expectThrows(
    () => occurrences.add(occurrences.first),
    'repeatable snapshot occurrences are immutable',
  );

  final List<String> targetNames = <String>[
    ...TerminalKeyBindingAction.values.map(
      (TerminalKeyBindingAction action) => action.configName,
    ),
    ...TerminalActionId.values.map(
      (TerminalActionId action) => action.stableName,
    ),
  ];
  final _MemoryConfigFileSystem actionFiles = _MemoryConfigFileSystem(
    <String, String>{
      '/actions': targetNames
          .map((String target) => 'keybind = control+k=$target')
          .join('\n'),
    },
  );
  final List<TerminalResolvedConfigValue<TerminalKeyBindingDefinition>>
  actionOccurrences = TerminalConfigLoader(fileSystem: actionFiles)
      .resolve(const <String>[
        '--config=/actions',
      ], environment: const <String, String>{})
      .snapshot
      .occurrences(TerminalProductConfigSchema.keybind);
  _expect(
    actionOccurrences
            .map(
              (
                TerminalResolvedConfigValue<TerminalKeyBindingDefinition> value,
              ) => value.value.targetConfigName,
            )
            .join(',') ==
        targetNames.join(','),
    'every pane and application action ID is a typed keybind target',
  );

  final TerminalConfigSnapshot invalid = TerminalConfigLoader(fileSystem: files)
      .resolve(const <String>[
        '--config=/invalid',
      ], environment: const <String, String>{})
      .snapshot;
  _expect(
    invalid.diagnostics.length == 3 &&
        invalid.diagnostics.every(
          (TerminalConfigDiagnostic diagnostic) =>
              diagnostic.code == 'CFG_INVALID_VALUE' && diagnostic.hint != null,
        ) &&
        invalid
                .occurrences(TerminalProductConfigSchema.keybind)
                .single
                .value
                .action ==
            TerminalKeyBindingAction.sendSuspendSignal,
    'invalid, reserved, and unknown keybinds recover independently',
  );

  final TerminalConfigRepeatedOption<String> item =
      TerminalConfigRepeatedOption<String>(
        name: 'item',
        description: 'bounded repeated test value',
        valueSyntax: '<text>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        maximumOccurrences: 2,
        parser: TerminalConfigDecodeResult<String>.success,
        formatter: (String value) => value,
      );
  final TerminalConfigSnapshot bounded =
      TerminalConfigLoader(
        schema: TerminalConfigSchema(<TerminalConfigOptionBase>[item]),
        fileSystem: files,
      ).resolve(const <String>[
        '--config=/bounded',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    bounded.occurrences(item).map((value) => value.value).join(',') ==
            'two,three' &&
        bounded.diagnostics.single.code == 'CFG_REPEAT_LIMIT' &&
        bounded.diagnostics.single.severity ==
            TerminalConfigDiagnosticSeverity.warning,
    'repeatable options retain the newest bounded occurrences with one warning',
  );
}

void _testSchemaAndZeroConfig() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{},
  );
  final TerminalConfigResolution result =
      TerminalConfigLoader(fileSystem: files).resolve(
        const <String>[],
        environment: const <String, String>{},
        currentDirectory: '/workspace',
      );
  _expect(
    result.snapshot.value(TerminalProductConfigSchema.workingDirectory) ==
            null &&
        result.snapshot.value(TerminalProductConfigSchema.theme) ==
            TerminalConfiguredTheme.system &&
        result.snapshot.rootPath == null &&
        result.snapshot.diagnostics.isEmpty &&
        result.remainingArguments.isEmpty,
    'zero-config resolution preserves schema defaults without diagnostics',
  );
  for (final MapEntry<String, TerminalConfiguredTheme> entry
      in const <String, TerminalConfiguredTheme>{
        'system': TerminalConfiguredTheme.system,
        'default': TerminalConfiguredTheme.system,
        'light': TerminalConfiguredTheme.light,
        'dark': TerminalConfiguredTheme.dark,
      }.entries) {
    final TerminalResolvedConfigValue<TerminalConfiguredTheme> theme =
        TerminalConfigLoader(fileSystem: files)
            .resolve(<String>[
              '--no-config',
              '--theme=${entry.key}',
            ], environment: const <String, String>{})
            .snapshot
            .resolved(TerminalProductConfigSchema.theme);
    _expect(
      theme.value == entry.value &&
          theme.source.kind == TerminalConfigSourceKind.commandLine,
      'theme selector ${entry.key} resolves to ${entry.value.name}',
    );
  }
  _expectThrows(
    () => TerminalConfigLoader(fileSystem: files).resolve(const <String>[
      '--no-config',
      '--theme=unknown',
    ], environment: const <String, String>{}),
    'unknown CLI theme is a usage failure',
  );
  _expect(
    TerminalConfigLoader.defaultConfigPath(const <String, String>{
          'XDG_CONFIG_HOME': '/xdg',
          'HOME': '/home/me',
        }) ==
        '/xdg/dart-terminal/config',
    'XDG configuration location takes precedence when explicitly configured',
  );
  _expect(
    TerminalConfigLoader.defaultConfigPath(const <String, String>{
          'HOME': '/home/me',
        }) ==
        '/home/me/Library/Application Support/Dart Terminal/config',
    'macOS application-support location is the HOME fallback',
  );
  _expectThrows(
    () => TerminalConfigSchema(<TerminalConfigOptionBase>[
      TerminalProductConfigSchema.workingDirectory,
      TerminalProductConfigSchema.workingDirectory,
    ]),
    'schema rejects duplicate names',
  );
  _expectThrows(
    () => TerminalConfigSchema(<TerminalConfigOptionBase>[
      TerminalConfigOption<String?>(
        name: 'include',
        description: 'reserved',
        valueSyntax: '<path>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: null,
        parser: (String value) =>
            TerminalConfigDecodeResult<String?>.success(value),
        formatter: (String? value) => value,
      ),
    ]),
    'schema reserves the include directive name',
  );
}

void _testDefaultLocationAndPrecedence() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{
      '/home/me/Library/Application Support/Dart Terminal/config': '''
working-directory = "/from root # retained"
include = child.conf
''',
      '/home/me/Library/Application Support/Dart Terminal/child.conf': '''
working-directory = /from-child
''',
    },
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  final TerminalConfigResolution file = loader.resolve(
    const <String>['--auto-close-after=2'],
    environment: const <String, String>{'HOME': '/home/me'},
    currentDirectory: '/workspace',
  );
  final TerminalResolvedConfigValue<String?> fileValue = file.snapshot.resolved(
    TerminalProductConfigSchema.workingDirectory,
  );
  _expect(
    fileValue.value == '/from root # retained',
    'including-file assignments override included files independent of order: '
    '${fileValue.value}',
  );
  _expect(
    fileValue.source.kind == TerminalConfigSourceKind.file &&
        fileValue.source.path.endsWith('/Dart Terminal/config') &&
        fileValue.source.line == 1,
    'winning file value retains source provenance: '
    '${fileValue.source.kind.name} ${fileValue.source.path} '
    '${fileValue.source.line}:${fileValue.source.column}',
  );
  _expect(
    file.remainingArguments.single == '--auto-close-after=2' &&
        file.snapshot.diagnostics.isEmpty,
    'non-schema CLI arguments remain available without file diagnostics',
  );

  final TerminalConfigResolution commandLine = loader.resolve(
    const <String>[
      '--config=config/main.conf',
      '--working-directory=/from-cli',
      '--auto-close-after=2',
    ],
    environment: const <String, String>{},
    currentDirectory: '/workspace',
  );
  _expect(
    commandLine.snapshot.rootPath == '/workspace/config/main.conf' &&
        commandLine.snapshot.diagnostics.single.code == 'CFG_FILE_MISSING' &&
        commandLine.snapshot
                .resolved(TerminalProductConfigSchema.workingDirectory)
                .value ==
            '/from-cli' &&
        commandLine.snapshot
                .resolved(TerminalProductConfigSchema.workingDirectory)
                .source
                .kind ==
            TerminalConfigSourceKind.commandLine &&
        commandLine.remainingArguments.single == '--auto-close-after=2',
    'CLI wins over a nonfatal explicit-file error and preserves other args',
  );

  final TerminalConfigResolution disabled = loader.resolve(
    const <String>['--no-config'],
    environment: const <String, String>{'HOME': '/home/me'},
    currentDirectory: '/workspace',
  );
  _expect(
    disabled.snapshot.rootPath == null &&
        disabled.snapshot.diagnostics.isEmpty &&
        disabled.snapshot.value(TerminalProductConfigSchema.workingDirectory) ==
            null,
    '--no-config skips an existing default file',
  );
  _expectThrows(
    () => loader.resolve(const <String>[
      '--no-config',
      '--config=/tmp/config',
    ], environment: const <String, String>{}),
    'explicit and disabled config modes are mutually exclusive',
  );
  _expectThrows(
    () => loader.resolve(const <String>[
      '--config=bad\npath',
    ], environment: const <String, String>{}),
    'explicit config paths reject control characters',
  );
}

void _testDiagnosticsAndRecovery() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{
      '/config': '''
working-diretory = /typo
working-directory /missing-equals
working-directory =
working-directory = /valid
working-directory = /last
quoted = "unterminated
''',
    },
  );
  final TerminalConfigSnapshot snapshot =
      TerminalConfigLoader(fileSystem: files).resolve(const <String>[
        '--config=/config',
      ], environment: const <String, String>{}).snapshot;
  final Set<String> codes = snapshot.diagnostics
      .map((TerminalConfigDiagnostic diagnostic) => diagnostic.code)
      .toSet();
  _expect(
    codes.length == 5 &&
        codes.containsAll(const <String>{
          'CFG_UNKNOWN_OPTION',
          'CFG_SYNTAX',
          'CFG_INVALID_VALUE',
          'CFG_VALUE_SYNTAX',
          'CFG_DUPLICATE_OPTION',
        }) &&
        snapshot.value(TerminalProductConfigSchema.workingDirectory) == '/last',
    'invalid entries diagnose and recover while the last valid value wins',
  );
  final TerminalConfigDiagnostic typo = snapshot.diagnostics.singleWhere(
    (TerminalConfigDiagnostic diagnostic) =>
        diagnostic.code == 'CFG_UNKNOWN_OPTION',
  );
  _expect(
    typo.source.path == '/config' &&
        typo.source.line == 1 &&
        typo.source.column == 1 &&
        typo.hint == 'did you mean `working-directory`?' &&
        typo.format().startsWith('/config:1:1: error[CFG_UNKNOWN_OPTION]:'),
    'diagnostics retain precise source, stable code, and correction hint',
  );
}

void _testResolvedFileValueAvailabilityFallback() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{
      '/config': '''font-family = Unavailable Family
font-size = 18
''',
      '/repeatable': 'item = one\n',
    },
  );
  final _RecordingAvailabilityValidator validator =
      _RecordingAvailabilityValidator();
  final TerminalConfigSnapshot recovered =
      TerminalConfigLoader(
        fileSystem: files,
        valueAvailabilityValidator: validator,
      ).resolve(const <String>[
        '--config=/config',
      ], environment: const <String, String>{}).snapshot;
  final TerminalConfigDiagnostic diagnostic = recovered.diagnostics.single;
  _expect(
    recovered.value(TerminalProductConfigSchema.fontFamily).isEmpty &&
        recovered
                .resolved(TerminalProductConfigSchema.fontFamily)
                .source
                .kind ==
            TerminalConfigSourceKind.schemaDefault &&
        recovered.value(TerminalProductConfigSchema.fontSize) == 18 &&
        recovered.resolved(TerminalProductConfigSchema.fontSize).source.path ==
            '/config' &&
        diagnostic.code == 'CFG_UNAVAILABLE_VALUE' &&
        diagnostic.source.path == '/config' &&
        diagnostic.source.line == 1 &&
        diagnostic.source.column == 1 &&
        diagnostic.message ==
            '`font-family`: configured value is unavailable' &&
        diagnostic.hint == 'use the schema default' &&
        validator.optionNames.join(',') == 'font-family,font-size',
    'unavailable file winner did not recover exactly one item to its default',
  );

  final _RecordingAvailabilityValidator commandLineValidator =
      _RecordingAvailabilityValidator();
  final TerminalConfigSnapshot commandLine =
      TerminalConfigLoader(
        fileSystem: files,
        valueAvailabilityValidator: commandLineValidator,
      ).resolve(const <String>[
        '--config=/config',
        '--font-family=Unavailable Family',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    commandLine.value(TerminalProductConfigSchema.fontFamily) ==
            'Unavailable Family' &&
        commandLine
                .resolved(TerminalProductConfigSchema.fontFamily)
                .source
                .kind ==
            TerminalConfigSourceKind.commandLine &&
        commandLine.diagnostics.isEmpty &&
        commandLineValidator.optionNames.join(',') == 'font-size',
    'availability fallback incorrectly intercepted an explicit CLI winner',
  );

  final TerminalConfigRepeatedOption<String> item =
      TerminalConfigRepeatedOption<String>(
        name: 'item',
        description: 'availability test repeated value',
        valueSyntax: '<text>',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        maximumOccurrences: 2,
        parser: TerminalConfigDecodeResult<String>.success,
        formatter: (String value) => value,
      );
  final _RecordingAvailabilityValidator repeatedValidator =
      _RecordingAvailabilityValidator();
  final TerminalConfigSnapshot repeated =
      TerminalConfigLoader(
        schema: TerminalConfigSchema(<TerminalConfigOptionBase>[item]),
        fileSystem: files,
        valueAvailabilityValidator: repeatedValidator,
      ).resolve(const <String>[
        '--config=/repeatable',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    repeated.occurrences(item).single.value == 'one' &&
        repeatedValidator.optionNames.isEmpty,
    'availability validation probed a repeated value',
  );
}

void _testIncludeCycleAndBounds() {
  final _MemoryConfigFileSystem cycleFiles = _MemoryConfigFileSystem(
    const <String, String>{
      '/a': 'include = b\nworking-directory = /a\n',
      '/b': 'include = a\n',
    },
  );
  final TerminalConfigSnapshot cycle =
      TerminalConfigLoader(fileSystem: cycleFiles).resolve(const <String>[
        '--config=/a',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    cycle.diagnostics.single.code == 'CFG_INCLUDE_CYCLE' &&
        cycle.value(TerminalProductConfigSchema.workingDirectory) == '/a',
    'include cycles are bounded without discarding valid root assignments',
  );

  final _MemoryConfigFileSystem boundedFiles = _MemoryConfigFileSystem(
    const <String, String>{
      '/large': 'working-directory = /value',
      '/lines': 'bad\nbad\nbad\n',
    },
  );
  final TerminalConfigSnapshot size =
      TerminalConfigLoader(
        fileSystem: boundedFiles,
        limits: const TerminalConfigLimits(maxFileBytes: 8),
      ).resolve(const <String>[
        '--config=/large',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    size.diagnostics.single.code == 'CFG_FILE_SIZE',
    'file byte limit fails closed to defaults',
  );
  final TerminalConfigSnapshot diagnostics =
      TerminalConfigLoader(
        fileSystem: boundedFiles,
        limits: const TerminalConfigLimits(maxDiagnostics: 2),
      ).resolve(const <String>[
        '--config=/lines',
      ], environment: const <String, String>{}).snapshot;
  _expect(
    diagnostics.diagnostics.length == 2 &&
        diagnostics.diagnostics.last.code == 'CFG_DIAGNOSTIC_LIMIT',
    'diagnostic collection reports its own deterministic bound',
  );
}

void _testTerminalOptionsIntegration() {
  final _MemoryConfigFileSystem files = _MemoryConfigFileSystem(
    const <String, String>{
      '/config': '''
working-diretory = /typo
working-directory = /from-file
''',
      '/font': 'font-family = Unavailable Family\nfont-size = 18\n',
    },
  );
  final TerminalOptions file = TerminalOptions.parse(
    const <String>['--config=/config', '--auto-close-after=3'],
    environment: const <String, String>{},
    currentDirectory: '/workspace',
    configFileSystem: files,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  _expect(
    file.initialWorkingDirectory == '/from-file' &&
        file.autoCloseAfter == const Duration(seconds: 3) &&
        file.configurationDiagnostics.single.code == 'CFG_UNKNOWN_OPTION' &&
        identical(
          file.configurationDiagnostics,
          file.effectiveConfiguration!.diagnostics,
        ) &&
        file.configurationReloadController != null &&
        identical(
          file.configurationReloadController!.effectiveSnapshot,
          file.effectiveConfiguration,
        ),
    'TerminalOptions starts with recovered typed file configuration',
  );
  final TerminalOptions overridden = TerminalOptions.parse(
    const <String>['--config=/config', '--working-directory=/from-cli'],
    environment: const <String, String>{},
    configFileSystem: files,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  _expect(
    overridden.initialWorkingDirectory == '/from-cli',
    'TerminalOptions applies the schema CLI winner',
  );
  final _RecordingAvailabilityValidator availabilityValidator =
      _RecordingAvailabilityValidator();
  final TerminalOptions recoveredFont = TerminalOptions.parse(
    const <String>['--config=/font'],
    environment: const <String, String>{},
    configFileSystem: files,
    configValueAvailabilityValidator: availabilityValidator,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  final TerminalSettingsDocument recoveredDocument = recoveredFont
      .settingsDocumentSession!
      .open(recoveredFont.effectiveConfiguration!);
  final TerminalSettingsDocumentSaveResult unavailableSave = recoveredFont
      .settingsDocumentSession!
      .save(recoveredDocument.text);
  _expect(
    recoveredFont.effectiveConfiguration!
            .value(TerminalProductConfigSchema.fontFamily)
            .isEmpty &&
        recoveredFont.configurationDiagnostics.single.code ==
            'CFG_UNAVAILABLE_VALUE' &&
        identical(
          recoveredFont.configurationReloadController!.effectiveSnapshot,
          recoveredFont.effectiveConfiguration,
        ) &&
        recoveredDocument.text.startsWith(
          'font-family = Unavailable Family\nfont-size = 18\n',
        ) &&
        unavailableSave.disposition ==
            TerminalSettingsDocumentSaveDisposition.rejected &&
        unavailableSave.diagnostics.single.code == 'CFG_UNAVAILABLE_VALUE',
    'TerminalOptions did not share availability recovery with Settings',
  );
  final TerminalOptions runtimeConfiguration = TerminalOptions.parse(
    const <String>['--no-config', '--runtime-configuration-test'],
    environment: const <String, String>{'DT_RUNTIME_CONFIGURATION_TEST': '1'},
    configFileSystem: files,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  _expect(
    runtimeConfiguration.runtimeConfigurationTest,
    'TerminalOptions admits the isolated configuration acceptance gate',
  );
  final TerminalOptions runtimeTheme = TerminalOptions.parse(
    const <String>['--no-config', '--runtime-theme-test'],
    environment: const <String, String>{'DT_RUNTIME_THEME_TEST': '1'},
    configFileSystem: files,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  _expect(
    runtimeTheme.runtimeThemeTest,
    'TerminalOptions admits the isolated theme acceptance gate',
  );
  final TerminalOptions runtimeShellIntegration = TerminalOptions.parse(
    const <String>['--no-config', '--runtime-shell-integration-test'],
    environment: const <String, String>{
      'DT_RUNTIME_SHELL_INTEGRATION_TEST': '1',
    },
    configFileSystem: files,
    runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
      executable: '/usr/bin/true',
    ),
  );
  _expect(
    runtimeShellIntegration.runtimeShellIntegrationTest,
    'TerminalOptions admits the isolated shell integration acceptance gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>['--no-config', '--runtime-configuration-test'],
      environment: const <String, String>{},
      configFileSystem: files,
    ),
    'configuration acceptance is unavailable without its environment gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>['--no-config', '--runtime-theme-test'],
      environment: const <String, String>{},
      configFileSystem: files,
    ),
    'theme acceptance is unavailable without its environment gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>['--no-config', '--runtime-shell-integration-test'],
      environment: const <String, String>{},
      configFileSystem: files,
    ),
    'shell integration acceptance is unavailable without its environment gate',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>[
        '--no-config',
        '--runtime-configuration-test',
        '--runtime-user-actions-test',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_CONFIGURATION_TEST': '1',
        'DT_RUNTIME_USER_ACTIONS_TEST': '1',
      },
      configFileSystem: files,
    ),
    'configuration acceptance cannot be combined with another runtime test',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>[
        '--no-config',
        '--runtime-theme-test',
        '--runtime-configuration-test',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_THEME_TEST': '1',
        'DT_RUNTIME_CONFIGURATION_TEST': '1',
      },
      configFileSystem: files,
    ),
    'theme acceptance cannot be combined with another runtime test',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>[
        '--no-config',
        '--runtime-shell-integration-test',
        '--runtime-configuration-test',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_SHELL_INTEGRATION_TEST': '1',
        'DT_RUNTIME_CONFIGURATION_TEST': '1',
      },
      configFileSystem: files,
    ),
    'shell integration acceptance cannot be combined with another runtime test',
  );
  _expectThrows(
    () => TerminalOptions.parse(
      const <String>['--working-directory=/one', '--working-directory=/two'],
      environment: const <String, String>{},
      configFileSystem: files,
    ),
    'TerminalOptions preserves duplicate CLI rejection',
  );
}

final class _MemoryConfigFileSystem implements TerminalConfigFileSystem {
  _MemoryConfigFileSystem(Map<String, String> files)
    : _files = Map<String, List<int>>.unmodifiable(
        files.map(
          (String path, String value) =>
              MapEntry<String, List<int>>(_normalize(path), utf8.encode(value)),
        ),
      );

  final Map<String, List<int>> _files;

  @override
  String absolutePath(String path) =>
      _normalize(path.startsWith('/') ? path : '/workspace/$path');

  @override
  bool exists(String path) => _files.containsKey(_normalize(path));

  @override
  List<int> readBytes(String path) => List<int>.from(_files[_normalize(path)]!);

  @override
  String resolvePath(String containingFile, String includedPath) {
    if (includedPath.startsWith('/')) {
      return _normalize(includedPath);
    }
    final String normalized = _normalize(containingFile);
    final int slash = normalized.lastIndexOf('/');
    return _normalize('${normalized.substring(0, slash)}/$includedPath');
  }
}

final class _RecordingAvailabilityValidator
    implements TerminalConfigValueAvailabilityValidator {
  final List<String> optionNames = <String>[];

  @override
  TerminalConfigValueAvailabilityIssue? validate(
    TerminalConfigOptionBase option,
    Object? value,
  ) {
    optionNames.add(option.name);
    if (identical(option, TerminalProductConfigSchema.fontFamily) &&
        value == 'Unavailable Family') {
      return const TerminalConfigValueAvailabilityIssue(
        message: 'configured value is unavailable',
        hint: 'use the schema default',
      );
    }
    return null;
  }
}

String _normalize(String path) {
  final List<String> segments = <String>[];
  for (final String segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return '/${segments.join('/')}';
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal config expectation failed: $description');
  }
}

void _expectThrows(void Function() callback, String description) {
  try {
    callback();
  } on Object {
    return;
  }
  throw StateError('terminal config expectation failed: $description');
}
