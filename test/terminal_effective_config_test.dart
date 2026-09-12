import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalEffectiveConfigTests();

Future<void> runTerminalEffectiveConfigTests() async {
  _testSchemaPresentationIsCompleteAndCanonical();
  _testEffectiveSnapshotAndFormattingAreStableAndEscaped();
  _testPresentationBoundsFailClosed();
  await _testDeprecatedThemeWarningIsAcceptedByReload();
}

void _testSchemaPresentationIsCompleteAndCanonical() {
  final TerminalConfigSchema schema = TerminalProductConfigSchema.instance;
  _expect(schema.options.length == 45, 'product schema option count changed');
  for (final TerminalConfigOptionBase option in schema.options) {
    _expect(
      option.valueSyntax.isNotEmpty && option.description.isNotEmpty,
      '${option.name} is missing presentation metadata',
    );
    if (option.isRepeatable) continue;
    final String? canonical = option.formatObject(option.defaultValueObject);
    if (canonical == null) continue;
    final TerminalConfigDecodeResult<Object?> decoded = option.decodeObject(
      canonical,
    );
    _expect(
      decoded.isSuccess &&
          decoded.warning == null &&
          option.formatObject(decoded.value) == canonical,
      '${option.name} default does not round-trip canonically',
    );
  }
  _expect(
    TerminalProductConfigSchema.theme.format(
          TerminalConfiguredTheme.defaultTheme,
        ) ==
        'system',
    'programmatic theme alias does not normalize to canonical system spelling',
  );

  final TerminalKeyBindingDefinition binding = TerminalProductConfigSchema
      .keybind
      .decode('shift+control+k=pane.focus-next')
      .value!;
  _expect(
    TerminalProductConfigSchema.keybind.format(binding) ==
        'shift+control+k=pane.focus-next',
    'keybinding formatter does not preserve canonical chord and target order',
  );

  _expectThrows(
    () => TerminalConfigSchema(<TerminalConfigOptionBase>[
      TerminalConfigOption<int>(
        name: 'missing-syntax',
        description: 'invalid metadata fixture',
        valueSyntax: '',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 1,
        parser: (String value) => TerminalConfigDecodeResult<int>.success(1),
        formatter: (int value) => value.toString(),
      ),
    ]),
    (Object error) => error is ArgumentError,
    'schema accepts empty presentation syntax',
  );
}

void _testEffectiveSnapshotAndFormattingAreStableAndEscaped() {
  const String workingDirectory = '/workspace # "quoted"\\tail';
  final TerminalConfigSnapshot snapshot = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--working-directory=$workingDirectory',
      '--theme=default',
      '--font-size=17.500',
      '--scrollback-bytes=64MiB',
      '--cursor-blink=false',
      '--keybind=control+d=unbind',
      '--keybind=shift+control+k=pane.focus-next',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalEffectiveConfigSnapshot effective =
      TerminalEffectiveConfigSnapshot.fromSnapshot(snapshot);
  _expect(
    effective.entries.length == snapshot.schema.options.length + 1 &&
        effective.diagnostics.single.code == 'CFG_DEPRECATED_VALUE',
    'effective view is not complete or lost the migration diagnostic',
  );

  final TerminalEffectiveConfigEntry working = effective
      .entriesFor(TerminalProductConfigSchema.workingDirectory)
      .single;
  final TerminalEffectiveConfigEntry theme = effective
      .entriesFor(TerminalProductConfigSchema.theme)
      .single;
  final List<TerminalEffectiveConfigEntry> keybindings = effective
      .entriesFor(TerminalProductConfigSchema.keybind)
      .toList(growable: false);
  _expect(
    working.canonicalValue == workingDirectory &&
        working.source.kind == TerminalConfigSourceKind.commandLine &&
        theme.canonicalValue == 'system' &&
        keybindings.length == 2 &&
        keybindings[0].canonicalValue == 'control+d=unbind' &&
        keybindings[0].occurrenceIndex == 1 &&
        keybindings[1].canonicalValue == 'shift+control+k=pane.focus-next' &&
        keybindings[1].occurrenceIndex == 2 &&
        keybindings.every(
          (TerminalEffectiveConfigEntry entry) => entry.occurrenceCount == 2,
        ),
    'effective entries lost canonical values, source, or repeated order',
  );

  final TerminalEffectiveConfigEntry emptyKeybind =
      TerminalEffectiveConfigSnapshot.fromSnapshot(
        TerminalConfigLoader().resolve(const <String>[
          '--no-config',
        ], environment: const <String, String>{}).snapshot,
      ).entriesFor(TerminalProductConfigSchema.keybind).single;
  _expect(
    !emptyKeybind.hasOccurrence &&
        emptyKeybind.canonicalValue == null &&
        emptyKeybind.source.kind == TerminalConfigSourceKind.schemaDefault,
    'empty repeatable option lacks one explicit default placeholder',
  );

  final TerminalEffectiveConfigFormatter formatter =
      TerminalEffectiveConfigFormatter();
  final String output = formatter.format(snapshot);
  final String themeLine = const LineSplitter()
      .convert(output)
      .singleWhere((String line) => line.contains('name="theme"'));
  final String workingLine = const LineSplitter()
      .convert(output)
      .singleWhere((String line) => line.contains('name="working-directory"'));
  _expect(
    output == formatter.format(snapshot) &&
        output.startsWith(
          'dart-terminal-effective-config version=1 options=45 entries=46 '
          'diagnostics=1\n',
        ) &&
        output.endsWith('end\n') &&
        themeLine.contains('value="system"') &&
        !themeLine.contains('default') &&
        workingLine.contains('value=${jsonEncode(workingDirectory)}') &&
        !workingLine.contains('\ntail'),
    'effective output is unstable, non-canonical, or permits line injection',
  );
  final String warningLine = const LineSplitter()
      .convert(output)
      .singleWhere((String line) => line.startsWith('diagnostic '));
  _expect(
    warningLine.contains('severity=warning') &&
        warningLine.contains('code="CFG_DEPRECATED_VALUE"') &&
        warningLine.contains('hint="replace it with `theme = system`"'),
    'bounded diagnostic output lost severity, code, or migration hint',
  );
}

void _testPresentationBoundsFailClosed() {
  final TerminalConfigSnapshot snapshot = TerminalConfigLoader().resolve(
    const <String>['--no-config'],
    environment: const <String, String>{},
  ).snapshot;
  _expectThrows(
    () => TerminalEffectiveConfigSnapshot.fromSnapshot(
      snapshot,
      limits: const TerminalEffectiveConfigLimits(maxEntries: 1),
    ),
    (Object error) =>
        error is TerminalEffectiveConfigLimitException &&
        error.kind == TerminalEffectiveConfigLimitKind.entries,
    'effective snapshot silently truncates entries beyond its bound',
  );
  _expectThrows(
    () => TerminalEffectiveConfigSnapshot.fromSnapshot(
      snapshot,
      limits: const TerminalEffectiveConfigLimits(maxCanonicalCharacters: 1),
    ),
    (Object error) =>
        error is TerminalEffectiveConfigLimitException &&
        error.kind == TerminalEffectiveConfigLimitKind.canonicalCharacters,
    'effective snapshot silently truncates canonical values beyond its bound',
  );
  final _EffectiveConfigMemoryFileSystem files =
      _EffectiveConfigMemoryFileSystem(<String, String>{
        '/diagnostics': 'theme = default\ntheme = system\n',
      });
  final TerminalConfigSnapshot diagnosticSnapshot =
      TerminalConfigLoader(fileSystem: files).resolve(const <String>[
        '--config=/diagnostics',
      ], environment: const <String, String>{}).snapshot;
  _expectThrows(
    () => TerminalEffectiveConfigSnapshot.fromSnapshot(
      diagnosticSnapshot,
      limits: const TerminalEffectiveConfigLimits(maxDiagnostics: 1),
    ),
    (Object error) =>
        error is TerminalEffectiveConfigLimitException &&
        error.kind == TerminalEffectiveConfigLimitKind.diagnostics,
    'effective snapshot silently truncates diagnostics beyond its bound',
  );
  _expectThrows(
    () => TerminalEffectiveConfigFormatter(
      limits: const TerminalEffectiveConfigLimits(maxOutputCharacters: 64),
    ).format(snapshot),
    (Object error) =>
        error is TerminalEffectiveConfigLimitException &&
        error.kind == TerminalEffectiveConfigLimitKind.outputCharacters,
    'effective formatter silently truncates output beyond its bound',
  );
  _expectThrows(
    () => TerminalEffectiveConfigFormatter(
      limits: const TerminalEffectiveConfigLimits(maxEntries: 0),
    ),
    (Object error) => error is ArgumentError,
    'effective formatter accepts an invalid configured limit',
  );

  final String escapedDiagnostic = TerminalEffectiveConfigFormatter()
      .formatDiagnostic(
        const TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_FORGED',
          message: 'message\noption name="forged"',
          source: TerminalConfigSource(
            kind: TerminalConfigSourceKind.file,
            path: '/config\noption name="forged"',
            line: 2,
            column: 3,
          ),
          hint: 'hint\nend',
        ),
      );
  _expect(
    !escapedDiagnostic.contains('\n') &&
        escapedDiagnostic.contains(r'message\noption name=\"forged\"') &&
        escapedDiagnostic.contains(r'/config\noption name=\"forged\"') &&
        escapedDiagnostic.contains(r'hint\nend'),
    'diagnostic formatter permits path, message, or hint line injection',
  );
}

Future<void> _testDeprecatedThemeWarningIsAcceptedByReload() async {
  final _EffectiveConfigMemoryFileSystem files =
      _EffectiveConfigMemoryFileSystem(<String, String>{
        '/config': 'theme = system\n',
      });
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  const List<String> arguments = <String>['--config=/config'];
  final TerminalConfigSnapshot initial = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController.fromStartup(
        arguments: arguments,
        initialSnapshot: initial,
        loader: loader,
        environment: const <String, String>{},
      );
  files.write('/config', 'theme = default\n');
  final TerminalConfigReloadResult migrated = await controller.reload();
  _expect(
    migrated.disposition == TerminalConfigReloadDisposition.unchanged &&
        migrated.isAccepted &&
        migrated.changePlan!.isEmpty &&
        migrated.diagnostics.single.code == 'CFG_DEPRECATED_VALUE' &&
        migrated.diagnostics.single.severity ==
            TerminalConfigDiagnosticSeverity.warning &&
        migrated.diagnostics.single.source.path == '/config' &&
        migrated.diagnostics.single.source.line == 1 &&
        migrated.diagnostics.single.source.column == 9 &&
        migrated.diagnostics.single.hint ==
            'replace it with `theme = system`' &&
        controller.acceptedGeneration == 1 &&
        controller.effectiveSnapshot.value(TerminalProductConfigSchema.theme) ==
            TerminalConfiguredTheme.system,
    'deprecated theme reload is not one accepted semantic no-op warning',
  );

  files.write('/config', 'theme = system\n');
  final TerminalConfigReloadResult corrected = await controller.reload();
  _expect(
    corrected.disposition == TerminalConfigReloadDisposition.unchanged &&
        corrected.diagnostics.isEmpty &&
        controller.acceptedGeneration == 2,
    'canonical theme spelling does not clear the migration warning',
  );

  final TerminalConfigSnapshot commandLine = loader.resolve(const <String>[
    '--no-config',
    '--theme=default',
  ], environment: const <String, String>{}).snapshot;
  _expect(
    commandLine.diagnostics.single.code == 'CFG_DEPRECATED_VALUE' &&
        commandLine.diagnostics.single.source.kind ==
            TerminalConfigSourceKind.commandLine &&
        commandLine.diagnostics.single.source.line == 2 &&
        commandLine.diagnostics.single.source.column == 9,
    'command-line alias does not produce one precise migration warning',
  );
}

final class _EffectiveConfigMemoryFileSystem
    implements TerminalConfigFileSystem {
  _EffectiveConfigMemoryFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

  final Map<String, List<int>> _files;

  void write(String path, String value) {
    _files[path] = utf8.encode(value);
  }

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

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows(
  void Function() action,
  bool Function(Object error) matches,
  String message,
) {
  try {
    action();
  } on Object catch (error) {
    if (matches(error)) return;
    throw StateError('$message: unexpected $error');
  }
  throw StateError(message);
}
