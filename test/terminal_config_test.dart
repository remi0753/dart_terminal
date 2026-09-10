import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';

void main() => runTerminalConfigTests();

void runTerminalConfigTests() {
  _testSchemaAndZeroConfig();
  _testDefaultLocationAndPrecedence();
  _testDiagnosticsAndRecovery();
  _testIncludeCycleAndBounds();
  _testTerminalOptionsIntegration();
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
        result.snapshot.rootPath == null &&
        result.snapshot.diagnostics.isEmpty &&
        result.remainingArguments.isEmpty,
    'zero-config resolution preserves schema defaults without diagnostics',
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
        defaultValue: null,
        parser: (String value) =>
            TerminalConfigDecodeResult<String?>.success(value),
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
