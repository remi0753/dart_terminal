import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import '../tool/generate_configuration_reference.dart';

void main() => runTerminalConfigurationReferenceTests();

void runTerminalConfigurationReferenceTests() {
  _testUsageAndReferenceAreCompleteAndFresh();
  _testEarlyHelpDoesNotResolveConfiguration();
  _testEarlyShowConfigUsesTheTypedSnapshot();
  _testEarlyModeConflictsFailAsUsageErrors();
  _testEntrypointReturnsBeforeApplicationOwnership();
  _testReferenceBoundsFailClosed();
}

void _testUsageAndReferenceAreCompleteAndFresh() {
  final TerminalConfigurationReference reference =
      TerminalConfigurationReference();
  final String usage = reference.generateUsage();
  final String markdown = reference.generateMarkdown();
  _expect(
    terminalUsage == usage &&
        usage.startsWith('Usage: Dart Terminal [options]\n') &&
        usage.contains('  --help\n') &&
        usage.contains('  --show-config\n') &&
        usage.contains('  --config=<path>\n') &&
        usage.contains('  --no-config\n') &&
        !usage.contains('--auto-close-after'),
    'usage is not the ordinary schema-generated product surface',
  );
  for (final TerminalConfigOptionBase option
      in TerminalProductConfigSchema.instance.options) {
    _expect(
      _occurrences(usage, '--${option.name}=') == 1,
      'usage does not contain ${option.name} exactly once',
    );
    _expect(
      _occurrences(markdown, '| <code>${option.name}</code> |') == 1 &&
          markdown.contains('<code>--${option.name}=VALUE</code>') &&
          markdown.contains(
            '<code>${const HtmlEscape(HtmlEscapeMode.element).convert(option.valueSyntax)}</code>',
          ),
      'reference does not contain one complete ${option.name} row',
    );
  }
  final File committed = File(configurationReferencePath);
  _expect(
    configurationReferenceIsFresh(committed) &&
        committed.readAsStringSync() == markdown &&
        markdown.contains(
          '[Keybindings and actions](keybindings-and-actions.md)',
        ) &&
        markdown.contains('`CFG_DEPRECATED_VALUE`') &&
        markdown.contains('`theme = system`'),
    'committed configuration reference is stale or incomplete',
  );
  _expectThrows(
    () => validateConfigurationReferenceSource(
      markdown.replaceFirst(
        '# Configuration and command-line reference',
        '# Stale reference',
      ),
      expectedSource: markdown,
    ),
    (Object error) => error is ConfigurationReferenceException,
    'modified generated reference is not rejected',
  );
}

void _testEarlyHelpDoesNotResolveConfiguration() {
  final _CountingFailingFileSystem files = _CountingFailingFileSystem();
  final TerminalEarlyExitResolver resolver = TerminalEarlyExitResolver(
    fileSystem: files,
  );
  final TerminalEarlyExitResult result = resolver.resolve(const <String>[
    '--help',
  ])!;
  _expect(
    result.mode == TerminalEarlyExitMode.help &&
        result.standardOutput == terminalUsage &&
        files.operationCount == 0,
    'help touched configuration or did not return generated usage',
  );
  _expect(
    resolver.resolve(const <String>[]) == null && files.operationCount == 0,
    'ordinary application arguments are incorrectly consumed as early mode',
  );
}

void _testEarlyShowConfigUsesTheTypedSnapshot() {
  final _ReferenceMemoryFileSystem files = _ReferenceMemoryFileSystem(
    const <String, String>{
      '/config': 'theme = default\nfont-size = 15\n',
      '/invalid': 'font-size = enormous\n',
      '/unavailable': 'font-family = Unavailable Family\n',
    },
  );
  final TerminalEarlyExitResolver resolver = TerminalEarlyExitResolver(
    fileSystem: files,
    valueAvailabilityValidator: _ReferenceAvailabilityValidator(),
  );
  final TerminalEarlyExitResult result = resolver.resolve(
    const <String>[
      '--show-config',
      '--config=/config',
      '--font-size=17.5',
      '--keybind=control+d=unbind',
    ],
    environment: const <String, String>{},
    currentDirectory: '/workspace',
  )!;
  final List<String> lines = const LineSplitter().convert(
    result.standardOutput,
  );
  final String theme = lines.singleWhere(
    (String line) => line.contains('name="theme"'),
  );
  final String fontSize = lines.singleWhere(
    (String line) => line.contains('name="font-size"'),
  );
  final String keybind = lines.singleWhere(
    (String line) => line.contains('name="keybind"'),
  );
  _expect(
    result.mode == TerminalEarlyExitMode.showConfig &&
        result.standardOutput.startsWith(
          'dart-terminal-effective-config version=1 options=44 entries=44 '
          'diagnostics=1\nroot path="/config"\n',
        ) &&
        theme.contains('value="system"') &&
        theme.contains('source=file') &&
        fontSize.contains('value="17.5"') &&
        fontSize.contains('source=command-line') &&
        fontSize.contains('line=3 column=13') &&
        keybind.contains('value="control+d=unbind"') &&
        keybind.contains('occurrence=1/1') &&
        result.standardOutput.contains(
          'diagnostic severity=warning code="CFG_DEPRECATED_VALUE"',
        ) &&
        result.standardOutput.endsWith('end\n'),
    'show-config lost canonical value, provenance, policy, or diagnostic data',
  );

  final TerminalEarlyExitResult recovered = resolver.resolve(const <String>[
    '--config=/invalid',
    '--show-config',
  ], environment: const <String, String>{})!;
  _expect(
    recovered.standardOutput.contains('value="14"') &&
        recovered.standardOutput.contains(
          'diagnostic severity=error code="CFG_INVALID_VALUE"',
        ),
    'show-config does not expose a recovered invalid snapshot',
  );

  final TerminalEarlyExitResult unavailable = resolver.resolve(const <String>[
    '--config=/unavailable',
    '--show-config',
  ], environment: const <String, String>{})!;
  final String unavailableFont = const LineSplitter()
      .convert(unavailable.standardOutput)
      .singleWhere((String line) => line.contains('name="font-family"'));
  _expect(
    unavailableFont.contains('value="system"') &&
        unavailableFont.contains('source=default') &&
        unavailable.standardOutput.contains(
          'diagnostic severity=error code="CFG_UNAVAILABLE_VALUE"',
        ),
    'show-config did not share file-value availability recovery',
  );
}

void _testEarlyModeConflictsFailAsUsageErrors() {
  final TerminalEarlyExitResolver resolver = TerminalEarlyExitResolver();
  for (final List<String> arguments in <List<String>>[
    <String>['--help', '--help'],
    <String>['--show-config', '--show-config'],
    <String>['--help', '--show-config'],
    <String>['--help', '--no-config'],
    <String>['--show-config', '--auto-close-after=1'],
  ]) {
    _expectThrows(
      () => resolver.resolve(arguments, environment: const <String, String>{}),
      (Object error) => error is FormatException,
      'invalid early-mode combination was accepted: $arguments',
    );
  }
}

void _testEntrypointReturnsBeforeApplicationOwnership() {
  final String source = File('bin/main.dart').readAsStringSync();
  final int earlyResolver = source.indexOf('TerminalEarlyExitResolver(');
  final int earlyBranch = source.indexOf('if (earlyExit != null)');
  final int options = source.indexOf('TerminalOptions.parse(');
  final int application = source.indexOf(
    'TerminalApplication(options: options)',
  );
  final String earlySource = source.substring(earlyBranch, options);
  _expect(
    earlyResolver >= 0 &&
        earlyResolver < earlyBranch &&
        earlyBranch < options &&
        options < application &&
        earlySource.contains('RuntimeDiagnosticPhase.rootStopped') &&
        earlySource.contains('requestTermination(exitCode: 0)') &&
        earlySource.contains('return;') &&
        !earlySource.contains('TerminalOptions.parse') &&
        !earlySource.contains('TerminalApplication'),
    'entrypoint can create options or application ownership before early exit',
  );
}

void _testReferenceBoundsFailClosed() {
  _expectThrows(
    () => TerminalConfigurationReference(
      limits: const TerminalConfigurationReferenceLimits(
        maxUsageCharacters: 32,
      ),
    ).generateUsage(),
    (Object error) =>
        error is TerminalConfigurationReferenceLimitException &&
        error.kind == TerminalConfigurationReferenceLimitKind.usage,
    'usage generation silently truncates its schema output',
  );
  _expectThrows(
    () => TerminalConfigurationReference(
      limits: const TerminalConfigurationReferenceLimits(
        maxMarkdownCharacters: 64,
      ),
    ).generateMarkdown(),
    (Object error) =>
        error is TerminalConfigurationReferenceLimitException &&
        error.kind == TerminalConfigurationReferenceLimitKind.markdown,
    'Markdown generation silently truncates its schema output',
  );
}

int _occurrences(String value, String pattern) {
  var count = 0;
  var offset = 0;
  while (true) {
    final int next = value.indexOf(pattern, offset);
    if (next < 0) return count;
    count++;
    offset = next + pattern.length;
  }
}

final class _CountingFailingFileSystem implements TerminalConfigFileSystem {
  var operationCount = 0;

  Never _fail() {
    operationCount++;
    throw StateError('help must not touch configuration');
  }

  @override
  String absolutePath(String path) => _fail();

  @override
  bool exists(String path) => _fail();

  @override
  List<int> readBytes(String path) => _fail();

  @override
  String resolvePath(String containingFile, String includedPath) => _fail();
}

final class _ReferenceMemoryFileSystem implements TerminalConfigFileSystem {
  _ReferenceMemoryFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

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

final class _ReferenceAvailabilityValidator
    implements TerminalConfigValueAvailabilityValidator {
  @override
  TerminalConfigValueAvailabilityIssue? validate(
    TerminalConfigOptionBase option,
    Object? value,
  ) =>
      identical(option, TerminalProductConfigSchema.fontFamily) &&
          value == 'Unavailable Family'
      ? const TerminalConfigValueAvailabilityIssue(
          message: 'font unavailable in reference test',
          hint: 'use `font-family = system`',
        )
      : null;
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
