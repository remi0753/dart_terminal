import 'dart:convert';
import 'dart:io';

typedef TerminalConfigValueParser<T> = TerminalConfigDecodeResult<T> Function(
  String value,
);

enum TerminalConfigDiagnosticSeverity { warning, error }

enum TerminalConfigSourceKind { schemaDefault, file, commandLine }

enum TerminalConfiguredTheme { defaultTheme }

enum TerminalConfiguredSyntheticStyle { allow, deny }

enum TerminalConfiguredOptionKey { escape, text }

enum TerminalConfiguredCursorShape { block, underline, bar }

final class TerminalConfigLimits {
  const TerminalConfigLimits({
    this.maxFiles = 32,
    this.maxIncludeDepth = 8,
    this.maxFileBytes = 1024 * 1024,
    this.maxLineCharacters = 16 * 1024,
    this.maxAssignments = 4096,
    this.maxDiagnostics = 128,
  }) : assert(maxFiles > 0),
       assert(maxIncludeDepth >= 0),
       assert(maxFileBytes > 0),
       assert(maxLineCharacters > 0),
       assert(maxAssignments > 0),
       assert(maxDiagnostics > 0);

  final int maxFiles;
  final int maxIncludeDepth;
  final int maxFileBytes;
  final int maxLineCharacters;
  final int maxAssignments;
  final int maxDiagnostics;
}

final class TerminalConfigSource {
  const TerminalConfigSource({
    required this.kind,
    required this.path,
    required this.line,
    required this.column,
  });

  const TerminalConfigSource.schemaDefault()
    : kind = TerminalConfigSourceKind.schemaDefault,
      path = '<default>',
      line = 1,
      column = 1;

  final TerminalConfigSourceKind kind;
  final String path;
  final int line;
  final int column;
}

final class TerminalConfigDiagnostic {
  const TerminalConfigDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    required this.source,
    this.hint,
  });

  final TerminalConfigDiagnosticSeverity severity;
  final String code;
  final String message;
  final TerminalConfigSource source;
  final String? hint;

  String format() {
    final String level = severity.name;
    final String correction = hint == null ? '' : '\n  hint: $hint';
    return '${source.path}:${source.line}:${source.column}: '
        '$level[$code]: $message$correction';
  }
}

final class TerminalConfigDecodeResult<T> {
  const TerminalConfigDecodeResult.success(this.value)
    : message = null,
      hint = null;

  const TerminalConfigDecodeResult.failure(this.message, {this.hint})
    : value = null;

  final T? value;
  final String? message;
  final String? hint;

  bool get isSuccess => message == null;
}

sealed class TerminalConfigOptionBase {
  String get name;
  String get description;
  Object? get defaultValueObject;
  TerminalConfigDecodeResult<Object?> decodeObject(String value);
}

final class TerminalConfigOption<T> extends TerminalConfigOptionBase {
  TerminalConfigOption({
    required this.name,
    required this.description,
    required this.defaultValue,
    required TerminalConfigValueParser<T> parser,
  }) : _parser = parser;

  @override
  final String name;

  @override
  final String description;

  final T defaultValue;
  final TerminalConfigValueParser<T> _parser;

  @override
  Object? get defaultValueObject => defaultValue;

  TerminalConfigDecodeResult<T> decode(String value) => _parser(value);

  @override
  TerminalConfigDecodeResult<Object?> decodeObject(String value) {
    final TerminalConfigDecodeResult<T> decoded = decode(value);
    if (!decoded.isSuccess) {
      return TerminalConfigDecodeResult<Object?>.failure(
        decoded.message!,
        hint: decoded.hint,
      );
    }
    return TerminalConfigDecodeResult<Object?>.success(decoded.value);
  }
}

final class TerminalConfigSchema {
  TerminalConfigSchema(Iterable<TerminalConfigOptionBase> options)
    : options = List<TerminalConfigOptionBase>.unmodifiable(options) {
    if (this.options.length > 256) {
      throw ArgumentError.value(this.options.length, 'options', 'maximum 256');
    }
    final Map<String, TerminalConfigOptionBase> byName =
        <String, TerminalConfigOptionBase>{};
    for (final TerminalConfigOptionBase option in this.options) {
      if (!_optionName.hasMatch(option.name) || option.name == 'include') {
        throw ArgumentError.value(option.name, 'option.name', 'invalid name');
      }
      if (byName.containsKey(option.name)) {
        throw ArgumentError.value(option.name, 'options', 'duplicate name');
      }
      byName[option.name] = option;
    }
    _byName = Map<String, TerminalConfigOptionBase>.unmodifiable(byName);
  }

  static final RegExp _optionName = RegExp(r'^[a-z][a-z0-9-]*$');

  final List<TerminalConfigOptionBase> options;
  late final Map<String, TerminalConfigOptionBase> _byName;

  TerminalConfigOptionBase? optionNamed(String name) => _byName[name];
}

final class TerminalResolvedConfigValue<T> {
  const TerminalResolvedConfigValue({
    required this.value,
    required this.source,
  });

  final T value;
  final TerminalConfigSource source;
}

final class TerminalConfigSnapshot {
  TerminalConfigSnapshot({
    required Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
    values,
    required Iterable<TerminalConfigDiagnostic> diagnostics,
    required this.rootPath,
  }) : _values =
           Map<
             TerminalConfigOptionBase,
             TerminalResolvedConfigValue<Object?>
           >.unmodifiable(values),
       diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(diagnostics);

  final Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
  _values;
  final List<TerminalConfigDiagnostic> diagnostics;
  final String? rootPath;

  TerminalResolvedConfigValue<T> resolved<T>(TerminalConfigOption<T> option) {
    final TerminalResolvedConfigValue<Object?>? value = _values[option];
    if (value == null) {
      throw ArgumentError.value(option.name, 'option', 'not in schema');
    }
    return TerminalResolvedConfigValue<T>(
      value: value.value as T,
      source: value.source,
    );
  }

  T value<T>(TerminalConfigOption<T> option) => resolved(option).value;
}

final class TerminalConfigResolution {
  TerminalConfigResolution({
    required this.snapshot,
    required Iterable<String> remainingArguments,
  }) : remainingArguments = List<String>.unmodifiable(remainingArguments);

  final TerminalConfigSnapshot snapshot;
  final List<String> remainingArguments;
}

abstract interface class TerminalConfigFileSystem {
  bool exists(String path);
  List<int> readBytes(String path);
  String absolutePath(String path);
  String resolvePath(String containingFile, String includedPath);
}

final class LocalTerminalConfigFileSystem implements TerminalConfigFileSystem {
  const LocalTerminalConfigFileSystem();

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  List<int> readBytes(String path) => File(path).readAsBytesSync();

  @override
  String absolutePath(String path) =>
      File(path).absolute.uri.normalizePath().toFilePath();

  @override
  String resolvePath(String containingFile, String includedPath) {
    if (includedPath.startsWith('/')) {
      return absolutePath(includedPath);
    }
    return absolutePath('${File(containingFile).parent.path}/$includedPath');
  }
}

abstract final class TerminalProductConfigSchema {
  static const List<int> defaultAnsiColors = <int>[
    0x80000000,
    0x80cd0000,
    0x8000cd00,
    0x80cdcd00,
    0x800000ee,
    0x80cd00cd,
    0x8000cdcd,
    0x80e5e5e5,
    0x807f7f7f,
    0x80ff0000,
    0x8000ff00,
    0x80ffff00,
    0x805c5cff,
    0x80ff00ff,
    0x8000ffff,
    0x80ffffff,
  ];

  static final TerminalConfigOption<String?> workingDirectory =
      TerminalConfigOption<String?>(
        name: 'working-directory',
        description: 'Initial command working directory.',
        defaultValue: null,
        parser: _parseNonEmptyPath,
      );

  static final TerminalConfigOption<TerminalConfiguredTheme> theme =
      TerminalConfigOption<TerminalConfiguredTheme>(
        name: 'theme',
        description: 'Base theme name.',
        defaultValue: TerminalConfiguredTheme.defaultTheme,
        parser: _parseTheme,
      );

  static final TerminalConfigOption<int> paletteForeground =
      TerminalConfigOption<int>(
        name: 'palette-foreground',
        description: 'Default terminal foreground color.',
        defaultValue: 0x80e5e5e5,
        parser: _parseColor,
      );

  static final TerminalConfigOption<int> paletteBackground =
      TerminalConfigOption<int>(
        name: 'palette-background',
        description: 'Default terminal background color.',
        defaultValue: 0x80000000,
        parser: _parseColor,
      );

  static final TerminalConfigOption<int> paletteCursor =
      TerminalConfigOption<int>(
        name: 'palette-cursor',
        description: 'Terminal cursor color.',
        defaultValue: 0x80e5e5e5,
        parser: _parseColor,
      );

  static final List<TerminalConfigOption<int>> ansiPalette =
      List<TerminalConfigOption<int>>.unmodifiable(
        List<TerminalConfigOption<int>>.generate(
          defaultAnsiColors.length,
          (int index) => TerminalConfigOption<int>(
            name: 'palette-$index',
            description: 'ANSI palette color $index.',
            defaultValue: defaultAnsiColors[index],
            parser: _parseColor,
          ),
          growable: false,
        ),
      );

  static final TerminalConfigOption<String> fontFamily =
      TerminalConfigOption<String>(
        name: 'font-family',
        description: 'Terminal monospace font family, or `system`.',
        defaultValue: '',
        parser: _parseFontFamily,
      );

  static final TerminalConfigOption<double> fontSize =
      TerminalConfigOption<double>(
        name: 'font-size',
        description: 'Terminal font size in points.',
        defaultValue: 14,
        parser: _parseFontSize,
      );

  static final TerminalConfigOption<TerminalConfiguredSyntheticStyle>
  fontSyntheticStyle = TerminalConfigOption<TerminalConfiguredSyntheticStyle>(
    name: 'font-synthetic-style',
    description: 'Whether missing bold and italic faces may be synthesized.',
    defaultValue: TerminalConfiguredSyntheticStyle.allow,
    parser: _parseSyntheticStyle,
  );

  static final TerminalConfigOption<double> windowWidth =
      TerminalConfigOption<double>(
        name: 'window-width',
        description: 'Initial terminal window width in logical points.',
        defaultValue: 920,
        parser: _parseWindowWidth,
      );

  static final TerminalConfigOption<double> windowHeight =
      TerminalConfigOption<double>(
        name: 'window-height',
        description: 'Initial terminal window height in logical points.',
        defaultValue: 580,
        parser: _parseWindowHeight,
      );

  static final TerminalConfigOption<double> windowPaddingHorizontal =
      TerminalConfigOption<double>(
        name: 'window-padding-horizontal',
        description: 'Horizontal terminal content padding in logical points.',
        defaultValue: 0,
        parser: _parseWindowPadding,
      );

  static final TerminalConfigOption<double> windowPaddingVertical =
      TerminalConfigOption<double>(
        name: 'window-padding-vertical',
        description: 'Vertical terminal content padding in logical points.',
        defaultValue: 0,
        parser: _parseWindowPadding,
      );

  static final TerminalConfigOption<TerminalConfiguredOptionKey>
  macosOptionKey = TerminalConfigOption<TerminalConfiguredOptionKey>(
    name: 'macos-option-key',
    description: 'Treat the macOS Option key as `escape` or composed `text`.',
    defaultValue: TerminalConfiguredOptionKey.escape,
    parser: _parseOptionKey,
  );

  static final TerminalConfigOption<int> scrollbackLines =
      TerminalConfigOption<int>(
        name: 'scrollback-lines',
        description: 'Maximum retained primary-screen history lines.',
        defaultValue: 10000,
        parser: _parseScrollbackLines,
      );

  static final TerminalConfigOption<int> scrollbackBytes =
      TerminalConfigOption<int>(
        name: 'scrollback-bytes',
        description: 'Maximum retained primary-screen history bytes.',
        defaultValue: 64 * 1024 * 1024,
        parser: _parseScrollbackBytes,
      );

  static final TerminalConfigOption<TerminalConfiguredCursorShape> cursorShape =
      TerminalConfigOption<TerminalConfiguredCursorShape>(
        name: 'cursor-shape',
        description: 'Initial terminal cursor shape.',
        defaultValue: TerminalConfiguredCursorShape.block,
        parser: _parseCursorShape,
      );

  static final TerminalConfigOption<bool> cursorBlink =
      TerminalConfigOption<bool>(
        name: 'cursor-blink',
        description: 'Whether the initial terminal cursor blinks.',
        defaultValue: true,
        parser: _parseBoolean,
      );

  static final TerminalConfigSchema instance = TerminalConfigSchema(
    <TerminalConfigOptionBase>[
      workingDirectory,
      theme,
      paletteForeground,
      paletteBackground,
      paletteCursor,
      ...ansiPalette,
      fontFamily,
      fontSize,
      fontSyntheticStyle,
      windowWidth,
      windowHeight,
      windowPaddingHorizontal,
      windowPaddingVertical,
      macosOptionKey,
      scrollbackLines,
      scrollbackBytes,
      cursorShape,
      cursorBlink,
    ],
  );
}

final class TerminalConfigLoader {
  TerminalConfigLoader({
    TerminalConfigSchema? schema,
    TerminalConfigFileSystem? fileSystem,
    this.limits = const TerminalConfigLimits(),
  }) : schema = schema ?? TerminalProductConfigSchema.instance,
       fileSystem = fileSystem ?? const LocalTerminalConfigFileSystem();

  final TerminalConfigSchema schema;
  final TerminalConfigFileSystem fileSystem;
  final TerminalConfigLimits limits;

  TerminalConfigResolution resolve(
    List<String> arguments, {
    Map<String, String>? environment,
    String? currentDirectory,
  }) {
    final Map<String, String> selectedEnvironment =
        environment ?? Platform.environment;
    final _TerminalConfigArguments parsedArguments = _parseArguments(arguments);
    final String baseDirectory = currentDirectory ?? Directory.current.path;
    String? rootPath;
    var explicitRoot = false;
    if (!parsedArguments.noConfig) {
      if (parsedArguments.configPath != null) {
        rootPath = fileSystem.absolutePath(
          _resolveCommandLinePath(baseDirectory, parsedArguments.configPath!),
        );
        explicitRoot = true;
      } else {
        final String? defaultPath = defaultConfigPath(selectedEnvironment);
        if (defaultPath != null) {
          rootPath = fileSystem.absolutePath(defaultPath);
        }
      }
    }

    final _TerminalConfigCollector collector = _TerminalConfigCollector(
      schema: schema,
      fileSystem: fileSystem,
      limits: limits,
    );
    if (rootPath != null) {
      collector.loadRoot(rootPath, required: explicitRoot);
    }
    collector.applyCommandLine(parsedArguments.values);
    return TerminalConfigResolution(
      snapshot: collector.snapshot(rootPath: rootPath),
      remainingArguments: parsedArguments.remaining,
    );
  }

  static String? defaultConfigPath(Map<String, String> environment) {
    final String? xdgConfigHome = environment['XDG_CONFIG_HOME'];
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      return '$xdgConfigHome/dart-terminal/config';
    }
    final String? home = environment['HOME'];
    if (home == null || home.isEmpty) {
      return null;
    }
    return '$home/Library/Application Support/Dart Terminal/config';
  }

  _TerminalConfigArguments _parseArguments(List<String> arguments) {
    String? configPath;
    var noConfig = false;
    final Map<TerminalConfigOptionBase, _TerminalRawValue> values =
        <TerminalConfigOptionBase, _TerminalRawValue>{};
    final List<String> remaining = <String>[];
    for (var index = 0; index < arguments.length; index += 1) {
      final String argument = arguments[index];
      if (argument == '--no-config') {
        if (noConfig) {
          throw const FormatException('--no-config may only be supplied once');
        }
        if (configPath != null) {
          throw const FormatException(
            '--no-config cannot be combined with --config',
          );
        }
        noConfig = true;
        continue;
      }
      const String configPrefix = '--config=';
      if (argument.startsWith(configPrefix)) {
        if (noConfig) {
          throw const FormatException(
            '--config cannot be combined with --no-config',
          );
        }
        if (configPath != null) {
          throw const FormatException('--config may only be supplied once');
        }
        configPath = argument.substring(configPrefix.length);
        final TerminalConfigDecodeResult<String?> decoded = _parseNonEmptyPath(
          configPath,
        );
        if (!decoded.isSuccess) {
          throw FormatException('--config: ${decoded.message}');
        }
        continue;
      }
      TerminalConfigOptionBase? matched;
      for (final TerminalConfigOptionBase option in schema.options) {
        if (argument.startsWith('--${option.name}=')) {
          matched = option;
          break;
        }
      }
      if (matched == null) {
        remaining.add(argument);
        continue;
      }
      if (values.containsKey(matched)) {
        throw FormatException('--${matched.name} may only be supplied once');
      }
      final String prefix = '--${matched.name}=';
      final String raw = argument.substring(prefix.length);
      final TerminalConfigDecodeResult<Object?> decoded = matched.decodeObject(
        raw,
      );
      if (!decoded.isSuccess) {
        throw FormatException('--${matched.name}: ${decoded.message}');
      }
      values[matched] = _TerminalRawValue(
        raw: raw,
        source: TerminalConfigSource(
          kind: TerminalConfigSourceKind.commandLine,
          path: '<command-line>',
          line: index + 1,
          column: prefix.length + 1,
        ),
      );
    }
    return _TerminalConfigArguments(
      configPath: configPath,
      noConfig: noConfig,
      values: values,
      remaining: remaining,
    );
  }

  String _resolveCommandLinePath(String currentDirectory, String path) {
    if (path.startsWith('/')) {
      return path;
    }
    return '$currentDirectory/$path';
  }
}

final class _TerminalConfigArguments {
  const _TerminalConfigArguments({
    required this.configPath,
    required this.noConfig,
    required this.values,
    required this.remaining,
  });

  final String? configPath;
  final bool noConfig;
  final Map<TerminalConfigOptionBase, _TerminalRawValue> values;
  final List<String> remaining;
}

final class _TerminalRawValue {
  const _TerminalRawValue({required this.raw, required this.source});

  final String raw;
  final TerminalConfigSource source;
}

final class _TerminalDirective {
  const _TerminalDirective({
    required this.name,
    required this.raw,
    required this.source,
    required this.valueColumn,
  });

  final String name;
  final String raw;
  final TerminalConfigSource source;
  final int valueColumn;
}

final class _TerminalConfigCollector {
  _TerminalConfigCollector({
    required this.schema,
    required this.fileSystem,
    required this.limits,
  }) {
    for (final TerminalConfigOptionBase option in schema.options) {
      _values[option] = TerminalResolvedConfigValue<Object?>(
        value: option.defaultValueObject,
        source: const TerminalConfigSource.schemaDefault(),
      );
    }
  }

  final TerminalConfigSchema schema;
  final TerminalConfigFileSystem fileSystem;
  final TerminalConfigLimits limits;
  final Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
  _values = <TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>{};
  final List<TerminalConfigDiagnostic> _diagnostics =
      <TerminalConfigDiagnostic>[];
  final List<String> _includeStack = <String>[];
  var _fileCount = 0;
  var _assignmentCount = 0;
  var _diagnosticLimitReported = false;

  void loadRoot(String path, {required bool required}) {
    _loadFile(path, required: required, depth: 0, source: null);
  }

  void applyCommandLine(
    Map<TerminalConfigOptionBase, _TerminalRawValue> values,
  ) {
    for (final MapEntry<TerminalConfigOptionBase, _TerminalRawValue> entry
        in values.entries) {
      final TerminalConfigDecodeResult<Object?> decoded = entry.key
          .decodeObject(entry.value.raw);
      if (!decoded.isSuccess) {
        throw StateError('validated command-line value changed result');
      }
      _values[entry.key] = TerminalResolvedConfigValue<Object?>(
        value: decoded.value,
        source: entry.value.source,
      );
    }
  }

  TerminalConfigSnapshot snapshot({required String? rootPath}) =>
      TerminalConfigSnapshot(
        values: _values,
        diagnostics: _diagnostics,
        rootPath: rootPath,
      );

  void _loadFile(
    String path, {
    required bool required,
    required int depth,
    required TerminalConfigSource? source,
  }) {
    final TerminalConfigSource diagnosticSource =
        source ??
        TerminalConfigSource(
          kind: TerminalConfigSourceKind.file,
          path: path,
          line: 1,
          column: 1,
        );
    if (depth > limits.maxIncludeDepth) {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_INCLUDE_DEPTH',
          message:
              'configuration include depth exceeds '
              '${limits.maxIncludeDepth}',
          source: diagnosticSource,
          hint: 'remove an include level or merge the included files',
        ),
      );
      return;
    }
    if (_includeStack.contains(path)) {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_INCLUDE_CYCLE',
          message: 'configuration include cycle detected',
          source: diagnosticSource,
          hint: 'remove the include that points to an ancestor file',
        ),
      );
      return;
    }
    if (_fileCount >= limits.maxFiles) {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_FILE_LIMIT',
          message: 'configuration file count exceeds ${limits.maxFiles}',
          source: diagnosticSource,
          hint: 'reduce the number of included files',
        ),
      );
      return;
    }
    bool exists;
    try {
      exists = fileSystem.exists(path);
    } on Exception {
      exists = false;
    }
    if (!exists) {
      if (required) {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.error,
            code: 'CFG_FILE_MISSING',
            message: 'configuration file does not exist',
            source: diagnosticSource,
            hint: 'create the file or select an existing path',
          ),
        );
      }
      return;
    }
    _fileCount += 1;
    List<int> bytes;
    try {
      bytes = fileSystem.readBytes(path);
    } on Exception {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_FILE_READ',
          message: 'configuration file could not be read',
          source: diagnosticSource,
          hint: 'check the file permissions and try again',
        ),
      );
      return;
    }
    if (bytes.length > limits.maxFileBytes) {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_FILE_SIZE',
          message: 'configuration file exceeds ${limits.maxFileBytes} bytes',
          source: diagnosticSource,
          hint: 'split or shorten the configuration file',
        ),
      );
      return;
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_UTF8',
          message: 'configuration file is not valid UTF-8',
          source: diagnosticSource,
          hint: 'save the file as UTF-8',
        ),
      );
      return;
    }

    _includeStack.add(path);
    try {
      final List<_TerminalDirective> directives = _parseFile(path, text);
      for (final _TerminalDirective directive in directives) {
        if (directive.name != 'include') {
          continue;
        }
        final TerminalConfigDecodeResult<String?> decoded = _parseNonEmptyPath(
          directive.raw,
        );
        if (!decoded.isSuccess) {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.error,
              code: 'CFG_INCLUDE_VALUE',
              message: decoded.message!,
              source: TerminalConfigSource(
                kind: TerminalConfigSourceKind.file,
                path: path,
                line: directive.source.line,
                column: directive.valueColumn,
              ),
              hint: decoded.hint,
            ),
          );
          continue;
        }
        String includedPath;
        try {
          includedPath = fileSystem.resolvePath(path, decoded.value!);
        } on Exception {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.error,
              code: 'CFG_INCLUDE_PATH',
              message: 'included configuration path could not be resolved',
              source: directive.source,
              hint: 'use a valid relative or absolute file path',
            ),
          );
          continue;
        }
        _loadFile(
          includedPath,
          required: true,
          depth: depth + 1,
          source: directive.source,
        );
      }
      final Set<TerminalConfigOptionBase> assigned =
          <TerminalConfigOptionBase>{};
      for (final _TerminalDirective directive in directives) {
        if (directive.name == 'include') {
          continue;
        }
        final TerminalConfigOptionBase? option = schema.optionNamed(
          directive.name,
        );
        if (option == null) {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.error,
              code: 'CFG_UNKNOWN_OPTION',
              message: 'unknown configuration option `${directive.name}`',
              source: directive.source,
              hint: _unknownOptionHint(directive.name),
            ),
          );
          continue;
        }
        if (_assignmentCount >= limits.maxAssignments) {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.error,
              code: 'CFG_ASSIGNMENT_LIMIT',
              message:
                  'configuration assignment count exceeds '
                  '${limits.maxAssignments}',
              source: directive.source,
              hint: 'remove duplicate or unnecessary assignments',
            ),
          );
          break;
        }
        _assignmentCount += 1;
        if (!assigned.add(option)) {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.warning,
              code: 'CFG_DUPLICATE_OPTION',
              message:
                  '`${option.name}` is assigned more than once in this '
                  'file; the last valid value wins',
              source: directive.source,
              hint: 'remove the earlier assignment',
            ),
          );
        }
        final TerminalConfigDecodeResult<Object?> decoded = option.decodeObject(
          directive.raw,
        );
        if (!decoded.isSuccess) {
          _addDiagnostic(
            TerminalConfigDiagnostic(
              severity: TerminalConfigDiagnosticSeverity.error,
              code: 'CFG_INVALID_VALUE',
              message: '`${option.name}`: ${decoded.message}',
              source: TerminalConfigSource(
                kind: TerminalConfigSourceKind.file,
                path: path,
                line: directive.source.line,
                column: directive.valueColumn,
              ),
              hint: decoded.hint,
            ),
          );
          continue;
        }
        _values[option] = TerminalResolvedConfigValue<Object?>(
          value: decoded.value,
          source: directive.source,
        );
      }
    } finally {
      _includeStack.removeLast();
    }
  }

  List<_TerminalDirective> _parseFile(String path, String text) {
    final List<_TerminalDirective> directives = <_TerminalDirective>[];
    final List<String> lines = const LineSplitter().convert(text);
    for (var index = 0; index < lines.length; index += 1) {
      final String original = lines[index];
      final TerminalConfigSource lineSource = TerminalConfigSource(
        kind: TerminalConfigSourceKind.file,
        path: path,
        line: index + 1,
        column: 1,
      );
      if (original.length > limits.maxLineCharacters) {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.error,
            code: 'CFG_LINE_SIZE',
            message:
                'configuration line exceeds '
                '${limits.maxLineCharacters} characters',
            source: lineSource,
            hint: 'split or shorten the line',
          ),
        );
        continue;
      }
      final String withoutComment = _stripComment(original);
      if (withoutComment.trim().isEmpty) {
        continue;
      }
      final int equals = withoutComment.indexOf('=');
      if (equals < 0) {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.error,
            code: 'CFG_SYNTAX',
            message: 'configuration assignment requires `key = value`',
            source: lineSource,
            hint: 'insert `=` between the option name and value',
          ),
        );
        continue;
      }
      final String name = withoutComment.substring(0, equals).trim();
      final int nameOffset = _firstNonWhitespace(withoutComment, 0, equals);
      final TerminalConfigSource nameSource = TerminalConfigSource(
        kind: TerminalConfigSourceKind.file,
        path: path,
        line: index + 1,
        column: nameOffset + 1,
      );
      if (!TerminalConfigSchema._optionName.hasMatch(name) &&
          name != 'include') {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.error,
            code: 'CFG_OPTION_NAME',
            message: 'invalid configuration option name',
            source: nameSource,
            hint: 'use lowercase letters, digits, and hyphens',
          ),
        );
        continue;
      }
      final int valueOffset = _firstNonWhitespace(
        withoutComment,
        equals + 1,
        withoutComment.length,
      );
      final String rawValue = withoutComment.substring(valueOffset).trimRight();
      final TerminalConfigDecodeResult<String> scalar = _decodeScalar(rawValue);
      if (!scalar.isSuccess) {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.error,
            code: 'CFG_VALUE_SYNTAX',
            message: scalar.message!,
            source: TerminalConfigSource(
              kind: TerminalConfigSourceKind.file,
              path: path,
              line: index + 1,
              column: valueOffset + 1,
            ),
            hint: scalar.hint,
          ),
        );
        continue;
      }
      directives.add(
        _TerminalDirective(
          name: name,
          raw: scalar.value!,
          source: nameSource,
          valueColumn: valueOffset + 1,
        ),
      );
    }
    return directives;
  }

  void _addDiagnostic(TerminalConfigDiagnostic diagnostic) {
    if (_diagnosticLimitReported) {
      return;
    }
    if (_diagnostics.length < limits.maxDiagnostics - 1) {
      _diagnostics.add(diagnostic);
      return;
    }
    _diagnosticLimitReported = true;
    _diagnostics.add(
      TerminalConfigDiagnostic(
        severity: TerminalConfigDiagnosticSeverity.error,
        code: 'CFG_DIAGNOSTIC_LIMIT',
        message: 'additional configuration diagnostics were suppressed',
        source: diagnostic.source,
        hint: 'fix the reported errors before retrying',
      ),
    );
  }

  String? _unknownOptionHint(String name) {
    TerminalConfigOptionBase? closest;
    var distance = 4;
    for (final TerminalConfigOptionBase option in schema.options) {
      final int candidate = _editDistance(name, option.name, maximum: distance);
      if (candidate < distance) {
        distance = candidate;
        closest = option;
      }
    }
    if (closest == null) {
      return 'remove the option or consult the generated configuration reference';
    }
    return 'did you mean `${closest.name}`?';
  }
}

TerminalConfigDecodeResult<String?> _parseNonEmptyPath(String value) {
  if (value.isEmpty) {
    return const TerminalConfigDecodeResult<String?>.failure(
      'path must not be empty',
      hint: 'provide an absolute or relative filesystem path',
    );
  }
  if (_containsControl(value)) {
    return const TerminalConfigDecodeResult<String?>.failure(
      'path must not contain control characters',
      hint: 'remove the control character',
    );
  }
  return TerminalConfigDecodeResult<String?>.success(value);
}

TerminalConfigDecodeResult<TerminalConfiguredTheme> _parseTheme(String value) =>
    switch (value) {
      'default' =>
        const TerminalConfigDecodeResult<TerminalConfiguredTheme>.success(
          TerminalConfiguredTheme.defaultTheme,
        ),
      _ => const TerminalConfigDecodeResult<TerminalConfiguredTheme>.failure(
        'theme must be `default`',
        hint: 'use `theme = default`; additional themes are added later',
      ),
    };

TerminalConfigDecodeResult<int> _parseColor(String value) {
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return const TerminalConfigDecodeResult<int>.failure(
      'color must use `#RRGGBB` hexadecimal notation',
      hint: 'for example, use `#e5e5e5`',
    );
  }
  return TerminalConfigDecodeResult<int>.success(
    0x80000000 | int.parse(value.substring(1), radix: 16),
  );
}

TerminalConfigDecodeResult<String> _parseFontFamily(String value) {
  if (value == 'system') {
    return const TerminalConfigDecodeResult<String>.success('');
  }
  if (value.isEmpty) {
    return const TerminalConfigDecodeResult<String>.failure(
      'font family must not be empty',
      hint: 'use `system` for the macOS system monospace font',
    );
  }
  final List<int> encoded = utf8.encode(value);
  if (encoded.length > 256 || encoded.contains(0) || _containsControl(value)) {
    return const TerminalConfigDecodeResult<String>.failure(
      'font family must be control-free UTF-8 within 256 bytes',
      hint: 'shorten the family name or use `system`',
    );
  }
  return TerminalConfigDecodeResult<String>.success(value);
}

TerminalConfigDecodeResult<double> _parseFontSize(String value) =>
    _parseFiniteDouble(
      value,
      minimum: 4,
      maximum: 128,
      description: 'font size',
    );

TerminalConfigDecodeResult<TerminalConfiguredSyntheticStyle>
_parseSyntheticStyle(String value) => switch (value) {
  'allow' =>
    const TerminalConfigDecodeResult<TerminalConfiguredSyntheticStyle>.success(
      TerminalConfiguredSyntheticStyle.allow,
    ),
  'deny' =>
    const TerminalConfigDecodeResult<TerminalConfiguredSyntheticStyle>.success(
      TerminalConfiguredSyntheticStyle.deny,
    ),
  _ =>
    const TerminalConfigDecodeResult<TerminalConfiguredSyntheticStyle>.failure(
      'font synthetic style must be `allow` or `deny`',
      hint: 'use `font-synthetic-style = allow` for the default behavior',
    ),
};

TerminalConfigDecodeResult<double> _parseWindowWidth(String value) =>
    _parseFiniteDouble(
      value,
      minimum: 480,
      maximum: 8192,
      description: 'window width',
    );

TerminalConfigDecodeResult<double> _parseWindowHeight(String value) =>
    _parseFiniteDouble(
      value,
      minimum: 320,
      maximum: 8192,
      description: 'window height',
    );

TerminalConfigDecodeResult<double> _parseWindowPadding(String value) =>
    _parseFiniteDouble(
      value,
      minimum: 0,
      maximum: 64,
      description: 'window padding',
    );

TerminalConfigDecodeResult<TerminalConfiguredOptionKey> _parseOptionKey(
  String value,
) => switch (value) {
  'escape' =>
    const TerminalConfigDecodeResult<TerminalConfiguredOptionKey>.success(
      TerminalConfiguredOptionKey.escape,
    ),
  'text' =>
    const TerminalConfigDecodeResult<TerminalConfiguredOptionKey>.success(
      TerminalConfiguredOptionKey.text,
    ),
  _ => const TerminalConfigDecodeResult<TerminalConfiguredOptionKey>.failure(
    'macOS Option key behavior must be `escape` or `text`',
    hint: 'use `macos-option-key = escape` for the default behavior',
  ),
};

TerminalConfigDecodeResult<int> _parseScrollbackLines(String value) =>
    _parseBoundedInteger(
      value,
      minimum: 1,
      maximum: 1000000,
      description: 'scrollback lines',
    );

TerminalConfigDecodeResult<int> _parseScrollbackBytes(String value) {
  final RegExpMatch? match = RegExp(r'^([0-9]+)(B|KiB|MiB|GiB)?$')
      .firstMatch(value);
  if (match == null) {
    return const TerminalConfigDecodeResult<int>.failure(
      'scrollback bytes must be an integer with optional B/KiB/MiB/GiB suffix',
      hint: 'for example, use `64MiB`',
    );
  }
  final int? magnitude = int.tryParse(match.group(1)!);
  final int multiplier = switch (match.group(2)) {
    'KiB' => 1024,
    'MiB' => 1024 * 1024,
    'GiB' => 1024 * 1024 * 1024,
    _ => 1,
  };
  if (magnitude == null ||
      magnitude <= 0 ||
      magnitude > (1024 * 1024 * 1024) ~/ multiplier) {
    return const TerminalConfigDecodeResult<int>.failure(
      'scrollback bytes must be between 1 byte and 1 GiB',
      hint: 'reduce the configured history byte cap',
    );
  }
  return TerminalConfigDecodeResult<int>.success(magnitude * multiplier);
}

TerminalConfigDecodeResult<TerminalConfiguredCursorShape> _parseCursorShape(
  String value,
) => switch (value) {
  'block' =>
    const TerminalConfigDecodeResult<TerminalConfiguredCursorShape>.success(
      TerminalConfiguredCursorShape.block,
    ),
  'underline' =>
    const TerminalConfigDecodeResult<TerminalConfiguredCursorShape>.success(
      TerminalConfiguredCursorShape.underline,
    ),
  'bar' =>
    const TerminalConfigDecodeResult<TerminalConfiguredCursorShape>.success(
      TerminalConfiguredCursorShape.bar,
    ),
  _ => const TerminalConfigDecodeResult<TerminalConfiguredCursorShape>.failure(
    'cursor shape must be `block`, `underline`, or `bar`',
    hint: 'use `cursor-shape = block` for the default behavior',
  ),
};

TerminalConfigDecodeResult<bool> _parseBoolean(String value) => switch (value) {
  'true' => const TerminalConfigDecodeResult<bool>.success(true),
  'false' => const TerminalConfigDecodeResult<bool>.success(false),
  _ => const TerminalConfigDecodeResult<bool>.failure(
    'boolean value must be `true` or `false`',
    hint: 'use a lowercase boolean literal',
  ),
};

TerminalConfigDecodeResult<double> _parseFiniteDouble(
  String value, {
  required double minimum,
  required double maximum,
  required String description,
}) {
  final double? parsed = double.tryParse(value);
  if (parsed == null ||
      !parsed.isFinite ||
      parsed < minimum ||
      parsed > maximum) {
    return TerminalConfigDecodeResult<double>.failure(
      '$description must be a finite number from $minimum to $maximum',
      hint: 'choose a value within the supported range',
    );
  }
  return TerminalConfigDecodeResult<double>.success(parsed);
}

TerminalConfigDecodeResult<int> _parseBoundedInteger(
  String value, {
  required int minimum,
  required int maximum,
  required String description,
}) {
  final int? parsed = int.tryParse(value);
  if (parsed == null || parsed < minimum || parsed > maximum) {
    return TerminalConfigDecodeResult<int>.failure(
      '$description must be an integer from $minimum to $maximum',
      hint: 'choose a value within the supported range',
    );
  }
  return TerminalConfigDecodeResult<int>.success(parsed);
}

TerminalConfigDecodeResult<String> _decodeScalar(String raw) {
  if (raw.isEmpty) {
    return const TerminalConfigDecodeResult<String>.success('');
  }
  if (!raw.startsWith('"')) {
    if (_containsControl(raw)) {
      return const TerminalConfigDecodeResult<String>.failure(
        'configuration value contains a control character',
        hint: 'remove the control character',
      );
    }
    return TerminalConfigDecodeResult<String>.success(raw);
  }
  if (raw.length < 2 || !raw.endsWith('"')) {
    return const TerminalConfigDecodeResult<String>.failure(
      'quoted configuration value is not terminated',
      hint: 'add a closing double quote',
    );
  }
  final StringBuffer decoded = StringBuffer();
  for (var index = 1; index < raw.length - 1; index += 1) {
    final String character = raw[index];
    if (character != r'\') {
      decoded.write(character);
      continue;
    }
    index += 1;
    if (index >= raw.length - 1) {
      return const TerminalConfigDecodeResult<String>.failure(
        'quoted configuration value ends with an escape',
        hint: 'escape a backslash as `\\\\`',
      );
    }
    final String escaped = raw[index];
    if (escaped != r'\' && escaped != '"') {
      return TerminalConfigDecodeResult<String>.failure(
        'unsupported escape sequence `\\$escaped`',
        hint: 'only `\\\\` and `\\"` escapes are supported',
      );
    }
    decoded.write(escaped);
  }
  final String value = decoded.toString();
  if (_containsControl(value)) {
    return const TerminalConfigDecodeResult<String>.failure(
      'configuration value contains a control character',
      hint: 'remove the control character',
    );
  }
  return TerminalConfigDecodeResult<String>.success(value);
}

String _stripComment(String line) {
  var quoted = false;
  var escaped = false;
  for (var index = 0; index < line.length; index += 1) {
    final String character = line[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character == r'\' && quoted) {
      escaped = true;
      continue;
    }
    if (character == '"') {
      quoted = !quoted;
      continue;
    }
    if (character == '#' && !quoted) {
      if (_isHexColorLiteralAt(line, index)) {
        index += 6;
        continue;
      }
      return line.substring(0, index);
    }
  }
  return line;
}

bool _isHexColorLiteralAt(String value, int offset) {
  if (offset + 7 > value.length) return false;
  for (var index = offset + 1; index < offset + 7; index += 1) {
    final int code = value.codeUnitAt(index);
    final bool digit = code >= 0x30 && code <= 0x39;
    final bool lower = code >= 0x61 && code <= 0x66;
    final bool upper = code >= 0x41 && code <= 0x46;
    if (!digit && !lower && !upper) return false;
  }
  if (offset + 7 == value.length) return true;
  final String next = value[offset + 7];
  return next == ' ' || next == '\t' || next == '#';
}

int _firstNonWhitespace(String value, int start, int end) {
  var index = start;
  while (index < end && (value[index] == ' ' || value[index] == '\t')) {
    index += 1;
  }
  return index;
}

bool _containsControl(String value) {
  for (final int scalar in value.runes) {
    if (scalar < 0x20 || scalar == 0x7f) {
      return true;
    }
  }
  return false;
}

int _editDistance(String left, String right, {required int maximum}) {
  if ((left.length - right.length).abs() >= maximum) {
    return maximum;
  }
  List<int> previous = List<int>.generate(
    right.length + 1,
    (int index) => index,
  );
  for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
    final List<int> current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    var rowMinimum = current[0];
    for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
      final int substitution =
          previous[rightIndex] +
          (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1);
      final int insertion = current[rightIndex] + 1;
      final int deletion = previous[rightIndex + 1] + 1;
      final int value = substitution < insertion
          ? (substitution < deletion ? substitution : deletion)
          : (insertion < deletion ? insertion : deletion);
      current[rightIndex + 1] = value;
      if (value < rowMinimum) {
        rowMinimum = value;
      }
    }
    if (rowMinimum >= maximum) {
      return maximum;
    }
    previous = current;
  }
  final int result = previous[right.length];
  return result < maximum ? result : maximum;
}
