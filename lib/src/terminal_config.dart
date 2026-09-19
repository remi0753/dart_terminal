import 'dart:convert';
import 'dart:io';

import 'terminal_action_registry.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_typography.dart';

typedef TerminalConfigValueParser<T> = TerminalConfigDecodeResult<T> Function(
  String value,
);
typedef TerminalConfigValueFormatter<T> = String? Function(T value);

enum TerminalConfigDiagnosticSeverity { warning, error }

enum TerminalConfigSourceKind { schemaDefault, file, commandLine }

/// When an accepted reload may publish a changed option to product consumers.
enum TerminalConfigApplicationPolicy { live, newSession }

enum TerminalConfiguredTheme {
  system,
  light,
  dark,

  /// Source-compatibility alias for programmatic callers. Config text named
  /// `default` is normalized to [system].
  defaultTheme,
}

enum TerminalConfiguredSyntheticStyle { allow, deny }

/// One product-owned OpenType coordinate before renderer projection.
final class TerminalConfiguredFontVariation {
  factory TerminalConfiguredFontVariation(String tag, double value) {
    final List<int> units = tag.codeUnits;
    if (units.length != tagByteLength ||
        units.any((int unit) => unit < 0x20 || unit > 0x7e)) {
      throw ArgumentError.value(
        tag,
        'tag',
        'must contain exactly four printable ASCII bytes',
      );
    }
    if (!value.isFinite || value < minimumValue || value > maximumValue) {
      throw RangeError.value(
        value,
        'value',
        'must be finite and within $minimumValue...$maximumValue',
      );
    }
    return TerminalConfiguredFontVariation._(tag, value);
  }

  const TerminalConfiguredFontVariation._(this.tag, this.value);

  static const int tagByteLength = 4;
  static const double minimumValue = -65536;
  static const double maximumValue = 65536;

  final String tag;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is TerminalConfiguredFontVariation &&
      tag == other.tag &&
      value == other.value;

  @override
  int get hashCode => Object.hash(tag, value);
}

/// One product-owned inclusive Unicode scalar range and explicit font family.
final class TerminalConfiguredFontCodepointOverride {
  factory TerminalConfiguredFontCodepointOverride({
    required int firstScalar,
    required int lastScalar,
    required String family,
  }) {
    if (!_isUnicodeScalar(firstScalar) ||
        !_isUnicodeScalar(lastScalar) ||
        firstScalar > lastScalar ||
        firstScalar <= 0xdfff && lastScalar >= 0xd800) {
      throw ArgumentError.value(
        '$firstScalar..$lastScalar',
        'range',
        'must be one ordered inclusive Unicode scalar range',
      );
    }
    final List<int> familyBytes = utf8.encode(family);
    if (familyBytes.isEmpty ||
        familyBytes.length > maximumFamilyBytes ||
        familyBytes.contains(0) ||
        _containsControl(family)) {
      throw ArgumentError.value(
        family,
        'family',
        'must be control-free UTF-8 within $maximumFamilyBytes bytes',
      );
    }
    return TerminalConfiguredFontCodepointOverride._(
      firstScalar,
      lastScalar,
      family,
    );
  }

  const TerminalConfiguredFontCodepointOverride._(
    this.firstScalar,
    this.lastScalar,
    this.family,
  );

  static const int maximumScalar = 0x10ffff;
  static const int maximumFamilyBytes = 256;

  final int firstScalar;
  final int lastScalar;
  final String family;

  @override
  bool operator ==(Object other) =>
      other is TerminalConfiguredFontCodepointOverride &&
      firstScalar == other.firstScalar &&
      lastScalar == other.lastScalar &&
      family == other.family;

  @override
  int get hashCode => Object.hash(firstScalar, lastScalar, family);

  static bool _isUnicodeScalar(int value) =>
      value >= 0 &&
      value <= maximumScalar &&
      (value < 0xd800 || value > 0xdfff);
}

enum TerminalConfiguredOptionKey { escape, text }

enum TerminalConfiguredCursorShape { block, underline, bar }

enum TerminalConfiguredClipboardAccess { deny, ask, allow }

enum TerminalConfiguredQuickTerminalScreen { main, mouse, macosMenuBar }

enum TerminalConfiguredShellIntegration {
  detect,
  none,
  zsh,
  bash,
  fish,
  nushell,
}

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
  const TerminalConfigDecodeResult.success(this.value, {this.warning})
    : message = null,
      hint = null;

  const TerminalConfigDecodeResult.failure(this.message, {this.hint})
    : value = null,
      warning = null;

  final T? value;
  final String? message;
  final String? hint;
  final TerminalConfigDecodeWarning? warning;

  bool get isSuccess => message == null;
}

/// One non-fatal migration notice attached to an otherwise valid raw value.
final class TerminalConfigDecodeWarning {
  const TerminalConfigDecodeWarning({
    required this.code,
    required this.message,
    required this.hint,
  });

  final String code;
  final String message;
  final String hint;
}

/// A platform/resource reason why one otherwise valid file value cannot be
/// used by this process.
final class TerminalConfigValueAvailabilityIssue {
  const TerminalConfigValueAvailabilityIssue({
    required this.message,
    required this.hint,
  });

  final String message;
  final String hint;
}

/// Optional product boundary for availability checks that cannot belong to
/// the portable configuration grammar.
abstract interface class TerminalConfigValueAvailabilityValidator {
  TerminalConfigValueAvailabilityIssue? validate(
    TerminalConfigOptionBase option,
    Object? value,
  );
}

/// Hard schema-presentation bounds shared by CLI, reference, and Settings UI.
abstract final class TerminalConfigPresentationLimits {
  static const int maximumSyntaxCharacters = 128;
  static const int maximumDescriptionCharacters = 512;
  static const int maximumValueCharacters = 16 * 1024;
}

sealed class TerminalConfigOptionBase {
  String get name;
  String get description;
  String get valueSyntax;
  TerminalConfigApplicationPolicy get applicationPolicy;
  bool get sourceKindAffectsSemantics;
  bool get isRepeatable;
  int? get maximumOccurrences;
  Object? get defaultValueObject;
  TerminalConfigDecodeResult<Object?> decodeObject(String value);
  String? formatObject(Object? value);
}

final class TerminalConfigOption<T> extends TerminalConfigOptionBase {
  TerminalConfigOption({
    required this.name,
    required this.description,
    required this.valueSyntax,
    required this.applicationPolicy,
    required this.defaultValue,
    this.sourceKindAffectsSemantics = false,
    required TerminalConfigValueParser<T> parser,
    required TerminalConfigValueFormatter<T> formatter,
  }) : _parser = parser,
       _formatter = formatter;

  @override
  final String name;

  @override
  final String description;

  @override
  final String valueSyntax;

  @override
  final TerminalConfigApplicationPolicy applicationPolicy;

  @override
  final bool sourceKindAffectsSemantics;

  @override
  bool get isRepeatable => false;

  @override
  int? get maximumOccurrences => null;

  final T defaultValue;
  final TerminalConfigValueParser<T> _parser;
  final TerminalConfigValueFormatter<T> _formatter;

  @override
  Object? get defaultValueObject => defaultValue;

  TerminalConfigDecodeResult<T> decode(String value) => _parser(value);

  String? format(T value) => _validateFormattedValue(name, _formatter(value));

  @override
  TerminalConfigDecodeResult<Object?> decodeObject(String value) {
    final TerminalConfigDecodeResult<T> decoded = decode(value);
    if (!decoded.isSuccess) {
      return TerminalConfigDecodeResult<Object?>.failure(
        decoded.message!,
        hint: decoded.hint,
      );
    }
    return TerminalConfigDecodeResult<Object?>.success(
      decoded.value,
      warning: decoded.warning,
    );
  }

  @override
  String? formatObject(Object? value) => format(value as T);
}

/// One schema option that preserves every valid occurrence in precedence order.
final class TerminalConfigRepeatedOption<T> extends TerminalConfigOptionBase {
  TerminalConfigRepeatedOption({
    required this.name,
    required this.description,
    required this.valueSyntax,
    required this.applicationPolicy,
    required this.maximumOccurrences,
    required TerminalConfigValueParser<T> parser,
    required TerminalConfigValueFormatter<T> formatter,
  }) : _parser = parser,
       _formatter = formatter {
    if (maximumOccurrences <= 0 || maximumOccurrences > 4096) {
      throw ArgumentError.value(
        maximumOccurrences,
        'maximumOccurrences',
        'must be in 1..4096',
      );
    }
  }

  @override
  final String name;

  @override
  final String description;

  @override
  final String valueSyntax;

  @override
  final TerminalConfigApplicationPolicy applicationPolicy;

  @override
  bool get sourceKindAffectsSemantics => false;

  @override
  final int maximumOccurrences;

  final TerminalConfigValueParser<T> _parser;
  final TerminalConfigValueFormatter<T> _formatter;

  @override
  bool get isRepeatable => true;

  @override
  Object? get defaultValueObject => null;

  TerminalConfigDecodeResult<T> decode(String value) => _parser(value);

  String format(T value) {
    final String? formatted = _validateFormattedValue(name, _formatter(value));
    if (formatted == null) {
      throw StateError('repeatable option `$name` formatted a null value');
    }
    return formatted;
  }

  @override
  TerminalConfigDecodeResult<Object?> decodeObject(String value) {
    final TerminalConfigDecodeResult<T> decoded = decode(value);
    if (!decoded.isSuccess) {
      return TerminalConfigDecodeResult<Object?>.failure(
        decoded.message!,
        hint: decoded.hint,
      );
    }
    return TerminalConfigDecodeResult<Object?>.success(
      decoded.value,
      warning: decoded.warning,
    );
  }

  @override
  String formatObject(Object? value) => format(value as T);
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
      _validatePresentationText(
        option.valueSyntax,
        name: '${option.name}.valueSyntax',
        maximum: TerminalConfigPresentationLimits.maximumSyntaxCharacters,
      );
      _validatePresentationText(
        option.description,
        name: '${option.name}.description',
        maximum: TerminalConfigPresentationLimits.maximumDescriptionCharacters,
      );
      if (!option.isRepeatable) {
        option.formatObject(option.defaultValueObject);
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
    required this.schema,
    required Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
    values,
    Map<TerminalConfigOptionBase, List<TerminalResolvedConfigValue<Object?>>>
        repeatedValues =
        const <
          TerminalConfigOptionBase,
          List<TerminalResolvedConfigValue<Object?>>
        >{},
    required Iterable<TerminalConfigDiagnostic> diagnostics,
    required this.rootPath,
  }) : _values =
           Map<
             TerminalConfigOptionBase,
             TerminalResolvedConfigValue<Object?>
           >.unmodifiable(values),
       _repeatedValues =
           Map<
             TerminalConfigOptionBase,
             List<TerminalResolvedConfigValue<Object?>>
           >.unmodifiable(
             repeatedValues.map(
               (
                 TerminalConfigOptionBase option,
                 List<TerminalResolvedConfigValue<Object?>> values,
               ) =>
                   MapEntry<
                     TerminalConfigOptionBase,
                     List<TerminalResolvedConfigValue<Object?>>
                   >(
                     option,
                     List<TerminalResolvedConfigValue<Object?>>.unmodifiable(
                       values,
                     ),
                   ),
             ),
           ),
       diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(diagnostics);

  final TerminalConfigSchema schema;
  final Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
  _values;
  final Map<
    TerminalConfigOptionBase,
    List<TerminalResolvedConfigValue<Object?>>
  >
  _repeatedValues;
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

  List<TerminalResolvedConfigValue<T>> occurrences<T>(
    TerminalConfigRepeatedOption<T> option,
  ) {
    final List<TerminalResolvedConfigValue<Object?>>? values =
        _repeatedValues[option];
    if (values == null) {
      throw ArgumentError.value(option.name, 'option', 'not in schema');
    }
    return List<TerminalResolvedConfigValue<T>>.unmodifiable(
      values.map(
        (TerminalResolvedConfigValue<Object?> value) =>
            TerminalResolvedConfigValue<T>(
              value: value.value as T,
              source: value.source,
            ),
      ),
    );
  }

  /// Type-erased scalar access for schema-driven presentation consumers.
  TerminalResolvedConfigValue<Object?> resolvedOption(
    TerminalConfigOptionBase option,
  ) {
    if (option.isRepeatable) {
      throw ArgumentError.value(option.name, 'option', 'is repeatable');
    }
    final TerminalResolvedConfigValue<Object?>? value = _values[option];
    if (value == null) {
      throw ArgumentError.value(option.name, 'option', 'not in schema');
    }
    return value;
  }

  /// Type-erased repeated access for schema-driven presentation consumers.
  List<TerminalResolvedConfigValue<Object?>> occurrencesFor(
    TerminalConfigOptionBase option,
  ) {
    if (!option.isRepeatable) {
      throw ArgumentError.value(option.name, 'option', 'is not repeatable');
    }
    final List<TerminalResolvedConfigValue<Object?>>? values =
        _repeatedValues[option];
    if (values == null) {
      throw ArgumentError.value(option.name, 'option', 'not in schema');
    }
    return values;
  }
}

/// One semantically changed option in a configuration reload candidate.
final class TerminalConfigChange {
  const TerminalConfigChange(this.option);

  final TerminalConfigOptionBase option;

  TerminalConfigApplicationPolicy get applicationPolicy =>
      option.applicationPolicy;
}

/// Immutable, deterministic semantic difference between two typed snapshots.
///
/// Provenance-only changes are omitted unless an option declares that source
/// ownership changes its effective semantics (for example palette overlays).
final class TerminalConfigChangePlan {
  factory TerminalConfigChangePlan.between(
    TerminalConfigSnapshot previous,
    TerminalConfigSnapshot candidate,
  ) {
    if (!identical(previous.schema, candidate.schema)) {
      throw ArgumentError(
        'configuration snapshots must use the same schema instance',
      );
    }
    final List<TerminalConfigChange> changes = <TerminalConfigChange>[];
    for (final TerminalConfigOptionBase option in previous.schema.options) {
      final bool changed = option.isRepeatable
          ? !_resolvedOccurrenceValuesEqual(
              previous._repeatedValues[option],
              candidate._repeatedValues[option],
            )
          : previous._values[option]?.value !=
                    candidate._values[option]?.value ||
                (option.sourceKindAffectsSemantics &&
                    (previous._values[option]?.source.kind ==
                            TerminalConfigSourceKind.schemaDefault) !=
                        (candidate._values[option]?.source.kind ==
                            TerminalConfigSourceKind.schemaDefault));
      if (changed) changes.add(TerminalConfigChange(option));
    }
    return TerminalConfigChangePlan._(changes);
  }

  TerminalConfigChangePlan._(Iterable<TerminalConfigChange> changes)
    : changes = List<TerminalConfigChange>.unmodifiable(changes),
      liveChanges = List<TerminalConfigChange>.unmodifiable(
        changes.where(
          (TerminalConfigChange change) =>
              change.applicationPolicy == TerminalConfigApplicationPolicy.live,
        ),
      ),
      newSessionChanges = List<TerminalConfigChange>.unmodifiable(
        changes.where(
          (TerminalConfigChange change) =>
              change.applicationPolicy ==
              TerminalConfigApplicationPolicy.newSession,
        ),
      );

  final List<TerminalConfigChange> changes;
  final List<TerminalConfigChange> liveChanges;
  final List<TerminalConfigChange> newSessionChanges;

  bool get isEmpty => changes.isEmpty;

  static bool _resolvedOccurrenceValuesEqual(
    List<TerminalResolvedConfigValue<Object?>>? left,
    List<TerminalResolvedConfigValue<Object?>>? right,
  ) {
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].value != right[index].value) return false;
    }
    return true;
  }
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
        description:
            'Initial command working directory; unset uses the user home.',
        valueSyntax: '<path>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: null,
        parser: _parseNonEmptyPath,
        formatter: _formatNullableString,
      );

  static final TerminalConfigOption<String> shell =
      TerminalConfigOption<String>(
        name: 'shell',
        description: 'Absolute executable path for new terminal sessions.',
        valueSyntax: '<absolute-path>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: '/bin/zsh',
        parser: _parseShellExecutable,
        formatter: _formatString,
      );

  static final TerminalConfigOption<TerminalConfiguredShellIntegration>
  shellIntegration = TerminalConfigOption<TerminalConfiguredShellIntegration>(
    name: 'shell-integration',
    description:
        'Shell integration policy: detect, none, zsh, bash, fish, or nushell.',
    valueSyntax: 'detect|none|zsh|bash|fish|nushell',
    applicationPolicy: TerminalConfigApplicationPolicy.newSession,
    defaultValue: TerminalConfiguredShellIntegration.detect,
    parser: _parseShellIntegration,
    formatter: _formatShellIntegration,
  );

  static final TerminalConfigOption<TerminalConfiguredTheme> theme =
      TerminalConfigOption<TerminalConfiguredTheme>(
        name: 'theme',
        description: 'Base theme: system, light, or dark.',
        valueSyntax: 'system|light|dark',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: TerminalConfiguredTheme.system,
        parser: _parseTheme,
        formatter: _formatTheme,
      );

  static final TerminalConfigOption<int> paletteForeground =
      TerminalConfigOption<int>(
        name: 'palette-foreground',
        description: 'Default terminal foreground color.',
        valueSyntax: '#RRGGBB',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 0x80e5e5e5,
        sourceKindAffectsSemantics: true,
        parser: _parseColor,
        formatter: _formatColor,
      );

  static final TerminalConfigOption<int> paletteBackground =
      TerminalConfigOption<int>(
        name: 'palette-background',
        description: 'Default terminal background color.',
        valueSyntax: '#RRGGBB',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 0x80000000,
        sourceKindAffectsSemantics: true,
        parser: _parseColor,
        formatter: _formatColor,
      );

  static final TerminalConfigOption<double>
  backgroundOpacity = TerminalConfigOption<double>(
    name: 'background-opacity',
    description:
        'Shared terminal background opacity; 0 is transparent and 1 is opaque.',
    valueSyntax: '<0..1>',
    applicationPolicy: TerminalConfigApplicationPolicy.live,
    defaultValue: 1,
    parser: _parseBackgroundOpacity,
    formatter: _formatDouble,
  );

  static final TerminalConfigOption<int> paletteCursor =
      TerminalConfigOption<int>(
        name: 'palette-cursor',
        description: 'Terminal cursor color.',
        valueSyntax: '#RRGGBB',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 0x80e5e5e5,
        sourceKindAffectsSemantics: true,
        parser: _parseColor,
        formatter: _formatColor,
      );

  static final List<TerminalConfigOption<int>> ansiPalette =
      List<TerminalConfigOption<int>>.unmodifiable(
        List<TerminalConfigOption<int>>.generate(
          defaultAnsiColors.length,
          (int index) => TerminalConfigOption<int>(
            name: 'palette-$index',
            description: 'ANSI palette color $index.',
            valueSyntax: '#RRGGBB',
            applicationPolicy: TerminalConfigApplicationPolicy.newSession,
            defaultValue: defaultAnsiColors[index],
            sourceKindAffectsSemantics: true,
            parser: _parseColor,
            formatter: _formatColor,
          ),
          growable: false,
        ),
      );

  static final TerminalConfigOption<String> fontFamily =
      TerminalConfigOption<String>(
        name: 'font-family',
        description: 'Terminal monospace font family, or `system`.',
        valueSyntax: 'system|<family>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: TerminalDefaultTypography.fontFamily,
        parser: _parseFontFamily,
        formatter: _formatFontFamily,
      );

  static final TerminalConfigOption<double> fontSize =
      TerminalConfigOption<double>(
        name: 'font-size',
        description: 'Terminal font size in points.',
        valueSyntax: '<4..128>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: TerminalDefaultTypography.fontSize,
        parser: _parseFontSize,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<TerminalConfiguredSyntheticStyle>
  fontSyntheticStyle = TerminalConfigOption<TerminalConfiguredSyntheticStyle>(
    name: 'font-synthetic-style',
    description: 'Whether missing bold and italic faces may be synthesized.',
    valueSyntax: 'allow|deny',
    applicationPolicy: TerminalConfigApplicationPolicy.newSession,
    defaultValue: TerminalConfiguredSyntheticStyle.allow,
    parser: _parseSyntheticStyle,
    formatter: _formatSyntheticStyle,
  );

  static final TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>
  fontVariationRegular = _fontVariationOption(
    name: 'font-variation-regular',
    description: 'OpenType variation coordinate for the regular font face.',
  );

  static final TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>
  fontVariationBold = _fontVariationOption(
    name: 'font-variation-bold',
    description: 'OpenType variation coordinate for the bold font face.',
  );

  static final TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>
  fontVariationItalic = _fontVariationOption(
    name: 'font-variation-italic',
    description: 'OpenType variation coordinate for the italic font face.',
  );

  static final TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>
  fontVariationBoldItalic = _fontVariationOption(
    name: 'font-variation-bold-italic',
    description: 'OpenType variation coordinate for the bold italic font face.',
  );

  static final TerminalConfigRepeatedOption<
    TerminalConfiguredFontCodepointOverride
  >
  fontCodepointOverride =
      TerminalConfigRepeatedOption<TerminalConfiguredFontCodepointOverride>(
        name: 'font-codepoint-override',
        description:
            'Explicit font family for one inclusive Unicode scalar range.',
        valueSyntax: 'U+<hex>[..U+<hex>]=<family>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        maximumOccurrences: 256,
        parser: _parseFontCodepointOverride,
        formatter: _formatFontCodepointOverride,
      );

  static final TerminalConfigOption<double> windowWidth =
      TerminalConfigOption<double>(
        name: 'window-width',
        description: 'Initial terminal window width in logical points.',
        valueSyntax: '<480..8192>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 920,
        parser: _parseWindowWidth,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<double> windowHeight =
      TerminalConfigOption<double>(
        name: 'window-height',
        description: 'Initial terminal window height in logical points.',
        valueSyntax: '<320..8192>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 580,
        parser: _parseWindowHeight,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<double> windowPaddingHorizontal =
      TerminalConfigOption<double>(
        name: 'window-padding-horizontal',
        description: 'Horizontal terminal content padding in logical points.',
        valueSyntax: '<0..64>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 0,
        parser: _parseWindowPadding,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<double> windowPaddingVertical =
      TerminalConfigOption<double>(
        name: 'window-padding-vertical',
        description: 'Vertical terminal content padding in logical points.',
        valueSyntax: '<0..64>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 0,
        parser: _parseWindowPadding,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<TerminalKeyBindingChord?>
  quickTerminalShortcut = TerminalConfigOption<TerminalKeyBindingChord?>(
    name: 'quick-terminal-shortcut',
    description:
        'Exclusive macOS global shortcut for Toggle Quick Terminal, or `none`.',
    valueSyntax: 'none|<modifier+physical-key>',
    applicationPolicy: TerminalConfigApplicationPolicy.live,
    defaultValue: null,
    parser: _parseQuickTerminalShortcut,
    formatter: _formatQuickTerminalShortcut,
  );

  static final TerminalConfigOption<bool> contextDockVisible =
      TerminalConfigOption<bool>(
        name: 'context-dock-visible',
        description:
            'Initial Context Dock visibility for new standard windows.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<double>
  contextDockWidth = TerminalConfigOption<double>(
    name: 'context-dock-width',
    description:
        'Context Dock width in logical points; changes resize existing docks.',
    valueSyntax: '<220..640>',
    applicationPolicy: TerminalConfigApplicationPolicy.live,
    defaultValue: 380,
    parser: _parseContextDockWidth,
    formatter: _formatDouble,
  );

  static final TerminalConfigOption<TerminalConfiguredQuickTerminalScreen>
  quickTerminalScreen =
      TerminalConfigOption<TerminalConfiguredQuickTerminalScreen>(
        name: 'quick-terminal-screen',
        description: 'Quick Terminal screen: keyboard-focus, mouse, or macOS menu-bar screen.',
        valueSyntax: 'main|mouse|macos-menu-bar',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: TerminalConfiguredQuickTerminalScreen.main,
        parser: _parseQuickTerminalScreen,
        formatter: _formatQuickTerminalScreen,
      );

  static final TerminalConfigOption<double> quickTerminalAnimationDuration =
      TerminalConfigOption<double>(
        name: 'quick-terminal-animation-duration',
        description: 'Quick Terminal enter and exit animation duration in seconds; 0 disables it.',
        valueSyntax: '<0..5>',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: 0.2,
        parser: _parseQuickTerminalAnimationDuration,
        formatter: _formatDouble,
      );

  static final TerminalConfigOption<bool> quickTerminalAutohide =
      TerminalConfigOption<bool>(
        name: 'quick-terminal-autohide',
        description:
            'Hide Quick Terminal automatically when its window loses focus.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<bool> macosAppIntents =
      TerminalConfigOption<bool>(
        name: 'macos-app-intents',
        description:
            'Allow the parameterless terminal actions exposed to Shortcuts.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<bool> macosNotifications =
      TerminalConfigOption<bool>(
        name: 'macos-notifications',
        description:
            'Allow terminal desktop notifications under macOS system policy.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<bool> macosSecureInputAuto =
      TerminalConfigOption<bool>(
        name: 'macos-secure-input-auto',
        description: 'Request Secure Keyboard Entry automatically while the focused terminal has echo disabled.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<bool> macosAppleScript =
      TerminalConfigOption<bool>(
        name: 'macos-applescript',
        description:
            'Allow TCC-authorized AppleScript queries and terminal automation.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<bool> macosSecureInputIndication =
      TerminalConfigOption<bool>(
        name: 'macos-secure-input-indication',
        description: 'Show an accessible automatic or manual Secure Keyboard Entry indicator.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.live,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<TerminalConfiguredOptionKey>
  macosOptionKey = TerminalConfigOption<TerminalConfiguredOptionKey>(
    name: 'macos-option-key',
    description: 'Treat the macOS Option key as `escape` or composed `text`.',
    valueSyntax: 'escape|text',
    applicationPolicy: TerminalConfigApplicationPolicy.live,
    defaultValue: TerminalConfiguredOptionKey.escape,
    parser: _parseOptionKey,
    formatter: _formatOptionKey,
  );

  static final TerminalConfigOption<int> scrollbackLines =
      TerminalConfigOption<int>(
        name: 'scrollback-lines',
        description: 'Maximum retained primary-screen history lines.',
        valueSyntax: '<1..1000000>',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 10000,
        parser: _parseScrollbackLines,
        formatter: _formatInteger,
      );

  static final TerminalConfigOption<int> scrollbackBytes =
      TerminalConfigOption<int>(
        name: 'scrollback-bytes',
        description: 'Maximum retained primary-screen history bytes.',
        valueSyntax: '<1..1073741824>[B|KiB|MiB|GiB]',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: 64 * 1024 * 1024,
        parser: _parseScrollbackBytes,
        formatter: _formatInteger,
      );

  static final TerminalConfigOption<TerminalConfiguredCursorShape> cursorShape =
      TerminalConfigOption<TerminalConfiguredCursorShape>(
        name: 'cursor-shape',
        description: 'Initial terminal cursor shape.',
        valueSyntax: 'block|underline|bar',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: TerminalConfiguredCursorShape.block,
        parser: _parseCursorShape,
        formatter: _formatCursorShape,
      );

  static final TerminalConfigOption<bool> cursorBlink =
      TerminalConfigOption<bool>(
        name: 'cursor-blink',
        description: 'Whether the initial terminal cursor blinks.',
        valueSyntax: 'true|false',
        applicationPolicy: TerminalConfigApplicationPolicy.newSession,
        defaultValue: true,
        parser: _parseBoolean,
        formatter: _formatBoolean,
      );

  static final TerminalConfigOption<TerminalConfiguredClipboardAccess>
  clipboardRead = TerminalConfigOption<TerminalConfiguredClipboardAccess>(
    name: 'clipboard-read',
    description: 'OSC 52 clipboard read policy: deny, ask, or allow.',
    valueSyntax: 'deny|ask|allow',
    applicationPolicy: TerminalConfigApplicationPolicy.newSession,
    defaultValue: TerminalConfiguredClipboardAccess.deny,
    parser: _parseClipboardAccess,
    formatter: _formatClipboardAccess,
  );

  static final TerminalConfigOption<TerminalConfiguredClipboardAccess>
  clipboardWrite = TerminalConfigOption<TerminalConfiguredClipboardAccess>(
    name: 'clipboard-write',
    description:
        'OSC 52 clipboard write and clear policy: deny, ask, or allow.',
    valueSyntax: 'deny|ask|allow',
    applicationPolicy: TerminalConfigApplicationPolicy.newSession,
    defaultValue: TerminalConfiguredClipboardAccess.deny,
    parser: _parseClipboardAccess,
    formatter: _formatClipboardAccess,
  );

  static final TerminalConfigRepeatedOption<TerminalKeyBindingDefinition>
  keybind = TerminalConfigRepeatedOption<TerminalKeyBindingDefinition>(
    name: 'keybind',
    description: 'Exact physical-key chord and action override.',
    valueSyntax: '<modifier+key=target>',
    applicationPolicy: TerminalConfigApplicationPolicy.live,
    maximumOccurrences:
        TerminalKeyBindingEngine.maximumDefinitionCount -
        TerminalKeyBindingEngine.standardDefinitionCount,
    parser: _parseKeyBinding,
    formatter: _formatKeyBinding,
  );

  static final TerminalConfigSchema instance = TerminalConfigSchema(
    <TerminalConfigOptionBase>[
      workingDirectory,
      shell,
      shellIntegration,
      theme,
      paletteForeground,
      paletteBackground,
      backgroundOpacity,
      paletteCursor,
      ...ansiPalette,
      fontFamily,
      fontSize,
      fontSyntheticStyle,
      fontVariationRegular,
      fontVariationBold,
      fontVariationItalic,
      fontVariationBoldItalic,
      fontCodepointOverride,
      windowWidth,
      windowHeight,
      windowPaddingHorizontal,
      windowPaddingVertical,
      contextDockVisible,
      contextDockWidth,
      quickTerminalShortcut,
      quickTerminalScreen,
      quickTerminalAnimationDuration,
      quickTerminalAutohide,
      macosAppIntents,
      macosNotifications,
      macosAppleScript,
      macosSecureInputAuto,
      macosSecureInputIndication,
      macosOptionKey,
      scrollbackLines,
      scrollbackBytes,
      cursorShape,
      cursorBlink,
      clipboardRead,
      clipboardWrite,
      keybind,
    ],
  );
}

final class TerminalConfigLoader {
  TerminalConfigLoader({
    TerminalConfigSchema? schema,
    TerminalConfigFileSystem? fileSystem,
    this.limits = const TerminalConfigLimits(),
    this.valueAvailabilityValidator,
  }) : schema = schema ?? TerminalProductConfigSchema.instance,
       fileSystem = fileSystem ?? const LocalTerminalConfigFileSystem();

  final TerminalConfigSchema schema;
  final TerminalConfigFileSystem fileSystem;
  final TerminalConfigLimits limits;
  final TerminalConfigValueAvailabilityValidator? valueAvailabilityValidator;

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
      valueAvailabilityValidator: valueAvailabilityValidator,
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
    final Map<TerminalConfigOptionBase, List<_TerminalRawValue>> values =
        <TerminalConfigOptionBase, List<_TerminalRawValue>>{};
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
      if (!matched.isRepeatable && values.containsKey(matched)) {
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
      values
          .putIfAbsent(matched, () => <_TerminalRawValue>[])
          .add(
            _TerminalRawValue(
              raw: raw,
              source: TerminalConfigSource(
                kind: TerminalConfigSourceKind.commandLine,
                path: '<command-line>',
                line: index + 1,
                column: prefix.length + 1,
              ),
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
  final Map<TerminalConfigOptionBase, List<_TerminalRawValue>> values;
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
    required this.valueAvailabilityValidator,
  }) {
    for (final TerminalConfigOptionBase option in schema.options) {
      if (option.isRepeatable) {
        _repeatedValues[option] = <TerminalResolvedConfigValue<Object?>>[];
      } else {
        _values[option] = TerminalResolvedConfigValue<Object?>(
          value: option.defaultValueObject,
          source: const TerminalConfigSource.schemaDefault(),
        );
      }
    }
  }

  final TerminalConfigSchema schema;
  final TerminalConfigFileSystem fileSystem;
  final TerminalConfigLimits limits;
  final TerminalConfigValueAvailabilityValidator? valueAvailabilityValidator;
  final Map<TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>
  _values = <TerminalConfigOptionBase, TerminalResolvedConfigValue<Object?>>{};
  final Map<
    TerminalConfigOptionBase,
    List<TerminalResolvedConfigValue<Object?>>
  >
  _repeatedValues =
      <TerminalConfigOptionBase, List<TerminalResolvedConfigValue<Object?>>>{};
  final List<TerminalConfigDiagnostic> _diagnostics =
      <TerminalConfigDiagnostic>[];
  final List<String> _includeStack = <String>[];
  final Set<TerminalConfigOptionBase> _repeatLimitReported =
      <TerminalConfigOptionBase>{};
  var _fileCount = 0;
  var _assignmentCount = 0;
  var _diagnosticLimitReported = false;

  void loadRoot(String path, {required bool required}) {
    _loadFile(path, required: required, depth: 0, source: null);
  }

  void applyCommandLine(
    Map<TerminalConfigOptionBase, List<_TerminalRawValue>> values,
  ) {
    for (final MapEntry<TerminalConfigOptionBase, List<_TerminalRawValue>> entry
        in values.entries) {
      for (final _TerminalRawValue rawValue in entry.value) {
        final TerminalConfigDecodeResult<Object?> decoded = entry.key
            .decodeObject(rawValue.raw);
        if (!decoded.isSuccess) {
          throw StateError('validated command-line value changed result');
        }
        _addDecodeWarning(decoded, rawValue.source);
        final TerminalResolvedConfigValue<Object?> resolved =
            TerminalResolvedConfigValue<Object?>(
              value: decoded.value,
              source: rawValue.source,
            );
        if (entry.key.isRepeatable) {
          _appendRepeated(entry.key, resolved);
        } else {
          _values[entry.key] = resolved;
        }
      }
    }
  }

  TerminalConfigSnapshot snapshot({required String? rootPath}) {
    _applyAvailabilityFallbacks();
    return TerminalConfigSnapshot(
      schema: schema,
      values: _values,
      repeatedValues: _repeatedValues,
      diagnostics: _diagnostics,
      rootPath: rootPath,
    );
  }

  void _applyAvailabilityFallbacks() {
    final TerminalConfigValueAvailabilityValidator? validator =
        valueAvailabilityValidator;
    if (validator == null) return;
    for (final TerminalConfigOptionBase option in schema.options) {
      if (option.isRepeatable) continue;
      final TerminalResolvedConfigValue<Object?> resolved = _values[option]!;
      if (resolved.source.kind != TerminalConfigSourceKind.file) continue;
      final TerminalConfigValueAvailabilityIssue? issue = validator.validate(
        option,
        resolved.value,
      );
      if (issue == null) continue;
      _addDiagnostic(
        TerminalConfigDiagnostic(
          severity: TerminalConfigDiagnosticSeverity.error,
          code: 'CFG_UNAVAILABLE_VALUE',
          message: '`${option.name}`: ${issue.message}',
          source: resolved.source,
          hint: issue.hint,
        ),
      );
      _values[option] = TerminalResolvedConfigValue<Object?>(
        value: option.defaultValueObject,
        source: const TerminalConfigSource.schemaDefault(),
      );
    }
  }

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
        if (!option.isRepeatable && !assigned.add(option)) {
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
        _addDecodeWarning(
          decoded,
          TerminalConfigSource(
            kind: TerminalConfigSourceKind.file,
            path: path,
            line: directive.source.line,
            column: directive.valueColumn,
          ),
        );
        final TerminalResolvedConfigValue<Object?> resolved =
            TerminalResolvedConfigValue<Object?>(
              value: decoded.value,
              source: directive.source,
            );
        if (option.isRepeatable) {
          _appendRepeated(option, resolved);
        } else {
          _values[option] = resolved;
        }
      }
    } finally {
      _includeStack.removeLast();
    }
  }

  void _appendRepeated(
    TerminalConfigOptionBase option,
    TerminalResolvedConfigValue<Object?> value,
  ) {
    final List<TerminalResolvedConfigValue<Object?>> values =
        _repeatedValues[option]!;
    final int maximum = option.maximumOccurrences!;
    if (values.length >= maximum) {
      values.removeAt(0);
      if (_repeatLimitReported.add(option)) {
        _addDiagnostic(
          TerminalConfigDiagnostic(
            severity: TerminalConfigDiagnosticSeverity.warning,
            code: 'CFG_REPEAT_LIMIT',
            message:
                '`${option.name}` retains at most $maximum occurrences; '
                'the earliest lower-precedence occurrence was discarded',
            source: value.source,
            hint: 'remove overridden or unnecessary declarations',
          ),
        );
      }
    }
    values.add(value);
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

  void _addDecodeWarning(
    TerminalConfigDecodeResult<Object?> decoded,
    TerminalConfigSource source,
  ) {
    final TerminalConfigDecodeWarning? warning = decoded.warning;
    if (warning == null) return;
    _addDiagnostic(
      TerminalConfigDiagnostic(
        severity: TerminalConfigDiagnosticSeverity.warning,
        code: warning.code,
        message: warning.message,
        source: source,
        hint: warning.hint,
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

void _validatePresentationText(
  String value, {
  required String name,
  required int maximum,
}) {
  if (value.isEmpty || value.length > maximum || _containsControl(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be control-free text within $maximum UTF-16 units',
    );
  }
}

String? _validateFormattedValue(String optionName, String? value) {
  if (value == null) return null;
  if (value.length > TerminalConfigPresentationLimits.maximumValueCharacters ||
      _containsControl(value)) {
    throw StateError(
      'formatter for `$optionName` produced control characters or more than '
      '${TerminalConfigPresentationLimits.maximumValueCharacters} UTF-16 units',
    );
  }
  return value;
}

String? _formatNullableString(String? value) => value;

String _formatString(String value) => value;

String _formatShellIntegration(TerminalConfiguredShellIntegration value) =>
    switch (value) {
      TerminalConfiguredShellIntegration.detect => 'detect',
      TerminalConfiguredShellIntegration.none => 'none',
      TerminalConfiguredShellIntegration.zsh => 'zsh',
      TerminalConfiguredShellIntegration.bash => 'bash',
      TerminalConfiguredShellIntegration.fish => 'fish',
      TerminalConfiguredShellIntegration.nushell => 'nushell',
    };

String _formatTheme(TerminalConfiguredTheme value) => switch (value) {
  TerminalConfiguredTheme.system ||
  TerminalConfiguredTheme.defaultTheme => 'system',
  TerminalConfiguredTheme.light => 'light',
  TerminalConfiguredTheme.dark => 'dark',
};

String _formatColor(int value) =>
    '#${(value & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';

String _formatFontFamily(String value) => value.isEmpty ? 'system' : value;

String _formatDouble(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();

String _formatSyntheticStyle(TerminalConfiguredSyntheticStyle value) =>
    switch (value) {
      TerminalConfiguredSyntheticStyle.allow => 'allow',
      TerminalConfiguredSyntheticStyle.deny => 'deny',
    };

String _formatOptionKey(TerminalConfiguredOptionKey value) => switch (value) {
  TerminalConfiguredOptionKey.escape => 'escape',
  TerminalConfiguredOptionKey.text => 'text',
};

String _formatInteger(int value) => value.toString();

String _formatCursorShape(TerminalConfiguredCursorShape value) =>
    switch (value) {
      TerminalConfiguredCursorShape.block => 'block',
      TerminalConfiguredCursorShape.underline => 'underline',
      TerminalConfiguredCursorShape.bar => 'bar',
    };

String _formatClipboardAccess(TerminalConfiguredClipboardAccess value) =>
    switch (value) {
      TerminalConfiguredClipboardAccess.deny => 'deny',
      TerminalConfiguredClipboardAccess.ask => 'ask',
      TerminalConfiguredClipboardAccess.allow => 'allow',
    };

String _formatQuickTerminalShortcut(TerminalKeyBindingChord? value) =>
    value?.configName ?? 'none';

String _formatQuickTerminalScreen(
  TerminalConfiguredQuickTerminalScreen value,
) => switch (value) {
  TerminalConfiguredQuickTerminalScreen.main => 'main',
  TerminalConfiguredQuickTerminalScreen.mouse => 'mouse',
  TerminalConfiguredQuickTerminalScreen.macosMenuBar => 'macos-menu-bar',
};

String _formatBoolean(bool value) => value ? 'true' : 'false';

String _formatKeyBinding(TerminalKeyBindingDefinition value) =>
    '${value.chord.configName}=${value.targetConfigName}';

TerminalConfigDecodeResult<String?> _parseNonEmptyPath(String value) {
  if (value.isEmpty) {
    return const TerminalConfigDecodeResult<String?>.failure(
      'path must not be empty',
      hint: 'provide an absolute or relative filesystem path',
    );
  }
  if (_containsControl(value) || utf8.encode(value).length > 4096) {
    return const TerminalConfigDecodeResult<String?>.failure(
      'path must be control-free UTF-8 within 4096 bytes',
      hint: 'remove control characters or shorten the path',
    );
  }
  return TerminalConfigDecodeResult<String?>.success(value);
}

TerminalConfigDecodeResult<String> _parseShellExecutable(String value) {
  if (!value.startsWith('/')) {
    return const TerminalConfigDecodeResult<String>.failure(
      'shell executable must be an absolute path',
      hint: 'for example, use `shell = /bin/zsh`',
    );
  }
  final List<int> encoded = utf8.encode(value);
  if (encoded.length > 4096 || _containsControl(value)) {
    return const TerminalConfigDecodeResult<String>.failure(
      'shell executable must be control-free UTF-8 within 4096 bytes',
      hint: 'use a shorter absolute executable path',
    );
  }
  if (value.endsWith('/')) {
    return const TerminalConfigDecodeResult<String>.failure(
      'shell executable must name a file, not a directory',
      hint: 'for example, use `shell = /bin/zsh`',
    );
  }
  return TerminalConfigDecodeResult<String>.success(value);
}

TerminalConfigDecodeResult<TerminalConfiguredShellIntegration>
_parseShellIntegration(String value) => switch (value) {
  'detect' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.detect),
  'none' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.none),
  'zsh' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.zsh),
  'bash' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.bash),
  'fish' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.fish),
  'nushell' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.success(TerminalConfiguredShellIntegration.nushell),
  _ =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredShellIntegration
    >.failure(
      'shell integration must be `detect`, `none`, `zsh`, `bash`, `fish`, or `nushell`',
      hint: 'use `shell-integration = detect` for automatic selection',
    ),
};

TerminalConfigDecodeResult<TerminalConfiguredTheme> _parseTheme(
  String value,
) => switch (value) {
  'default' =>
    const TerminalConfigDecodeResult<TerminalConfiguredTheme>.success(
      TerminalConfiguredTheme.system,
      warning: TerminalConfigDecodeWarning(
        code: 'CFG_DEPRECATED_VALUE',
        message: '`theme = default` is deprecated',
        hint: 'replace it with `theme = system`',
      ),
    ),
  'system' => const TerminalConfigDecodeResult<TerminalConfiguredTheme>.success(
    TerminalConfiguredTheme.system,
  ),
  'light' => const TerminalConfigDecodeResult<TerminalConfiguredTheme>.success(
    TerminalConfiguredTheme.light,
  ),
  'dark' => const TerminalConfigDecodeResult<TerminalConfiguredTheme>.success(
    TerminalConfiguredTheme.dark,
  ),
  _ => const TerminalConfigDecodeResult<TerminalConfiguredTheme>.failure(
    'theme must be `system`, `light`, or `dark`',
    hint: 'use `theme = system`; `default` is an accepted system alias',
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

TerminalConfigDecodeResult<double> _parseBackgroundOpacity(String value) =>
    _parseFiniteDouble(
      value,
      minimum: 0,
      maximum: 1,
      description: 'background opacity',
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

TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>
_fontVariationOption({required String name, required String description}) =>
    TerminalConfigRepeatedOption<TerminalConfiguredFontVariation>(
      name: name,
      description: description,
      valueSyntax: '<four-byte-tag>=<-65536..65536>',
      applicationPolicy: TerminalConfigApplicationPolicy.newSession,
      maximumOccurrences: 16,
      parser: _parseFontVariation,
      formatter: _formatFontVariation,
    );

TerminalConfigDecodeResult<TerminalConfiguredFontVariation> _parseFontVariation(
  String value,
) {
  if (value.length < TerminalConfiguredFontVariation.tagByteLength + 2 ||
      value.substring(TerminalConfiguredFontVariation.tagByteLength, 5) !=
          '=') {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontVariation
    >.failure(
      'font variation must be a four-byte tag followed by `=` and a coordinate',
      hint: 'for example, use `wght=700`',
    );
  }
  final String tag = value.substring(
    0,
    TerminalConfiguredFontVariation.tagByteLength,
  );
  final String coordinate = value.substring(
    TerminalConfiguredFontVariation.tagByteLength + 1,
  );
  final double? parsed = double.tryParse(coordinate);
  if (tag.codeUnits.length != TerminalConfiguredFontVariation.tagByteLength ||
      tag.codeUnits.any((int unit) => unit < 0x20 || unit > 0x7e) ||
      parsed == null ||
      !parsed.isFinite ||
      parsed < TerminalConfiguredFontVariation.minimumValue ||
      parsed > TerminalConfiguredFontVariation.maximumValue) {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontVariation
    >.failure(
      'font variation requires four printable ASCII bytes and a finite '
      'coordinate in -65536..65536',
      hint: 'for example, use `wght=700`',
    );
  }
  return TerminalConfigDecodeResult<TerminalConfiguredFontVariation>.success(
    TerminalConfiguredFontVariation(tag, parsed),
  );
}

String _formatFontVariation(TerminalConfiguredFontVariation variation) =>
    '${variation.tag}=${_formatDouble(variation.value)}';

TerminalConfigDecodeResult<TerminalConfiguredFontCodepointOverride>
_parseFontCodepointOverride(String value) {
  final int separator = value.indexOf('=');
  if (separator <= 0 || separator == value.length - 1) {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontCodepointOverride
    >.failure(
      'font codepoint override requires a scalar range and font family',
      hint: 'for example, use `U+2500..U+257F=Menlo`',
    );
  }
  final RegExpMatch? range = RegExp(
    r'^U\+([0-9A-Fa-f]{1,6})(?:\.\.U\+([0-9A-Fa-f]{1,6}))?$',
  ).firstMatch(value.substring(0, separator));
  if (range == null) {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontCodepointOverride
    >.failure(
      'font codepoint override range must use `U+<hex>` or '
      '`U+<hex>..U+<hex>`',
      hint: 'for example, use `U+2500..U+257F=Menlo`',
    );
  }
  final int first = int.parse(range.group(1)!, radix: 16);
  final int last = int.parse(range.group(2) ?? range.group(1)!, radix: 16);
  final String family = value.substring(separator + 1);
  if (!TerminalConfiguredFontCodepointOverride._isUnicodeScalar(first) ||
      !TerminalConfiguredFontCodepointOverride._isUnicodeScalar(last) ||
      first > last ||
      first <= 0xdfff && last >= 0xd800) {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontCodepointOverride
    >.failure(
      'font codepoint override must be one ordered Unicode scalar range',
      hint: 'exclude surrogate values U+D800..U+DFFF',
    );
  }
  final List<int> familyBytes = utf8.encode(family);
  if (familyBytes.isEmpty ||
      familyBytes.length >
          TerminalConfiguredFontCodepointOverride.maximumFamilyBytes ||
      familyBytes.contains(0) ||
      _containsControl(family)) {
    return const TerminalConfigDecodeResult<
      TerminalConfiguredFontCodepointOverride
    >.failure(
      'font codepoint override family must be control-free UTF-8 within '
      '256 bytes',
      hint: 'choose an explicit installed font family',
    );
  }
  return TerminalConfigDecodeResult<
    TerminalConfiguredFontCodepointOverride
  >.success(
    TerminalConfiguredFontCodepointOverride(
      firstScalar: first,
      lastScalar: last,
      family: family,
    ),
  );
}

String _formatFontCodepointOverride(
  TerminalConfiguredFontCodepointOverride override,
) {
  final String first = _formatUnicodeScalar(override.firstScalar);
  final String range = override.firstScalar == override.lastScalar
      ? first
      : '$first..${_formatUnicodeScalar(override.lastScalar)}';
  return '$range=${override.family}';
}

String _formatUnicodeScalar(int scalar) =>
    'U+${scalar.toRadixString(16).toUpperCase().padLeft(4, '0')}';

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

TerminalConfigDecodeResult<double> _parseContextDockWidth(String value) {
  final double? width = double.tryParse(value);
  if (width == null || !width.isFinite || width < 220 || width > 640) {
    return const TerminalConfigDecodeResult<double>.failure(
      'Context Dock width must be finite and between 220 and 640 points',
      hint: 'for example, use `context-dock-width = 380`',
    );
  }
  return TerminalConfigDecodeResult<double>.success(width);
}

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

TerminalConfigDecodeResult<TerminalConfiguredClipboardAccess>
_parseClipboardAccess(String value) => switch (value) {
  'deny' =>
    const TerminalConfigDecodeResult<TerminalConfiguredClipboardAccess>.success(
      TerminalConfiguredClipboardAccess.deny,
    ),
  'ask' =>
    const TerminalConfigDecodeResult<TerminalConfiguredClipboardAccess>.success(
      TerminalConfiguredClipboardAccess.ask,
    ),
  'allow' =>
    const TerminalConfigDecodeResult<TerminalConfiguredClipboardAccess>.success(
      TerminalConfiguredClipboardAccess.allow,
    ),
  _ =>
    const TerminalConfigDecodeResult<TerminalConfiguredClipboardAccess>.failure(
      'clipboard access must be `deny`, `ask`, or `allow`',
      hint: 'use `deny` unless OSC 52 clipboard access is explicitly wanted',
    ),
};

TerminalConfigDecodeResult<TerminalKeyBindingChord?>
_parseQuickTerminalShortcut(String value) {
  if (value == 'none') {
    return const TerminalConfigDecodeResult<TerminalKeyBindingChord?>.success(
      null,
    );
  }
  final TerminalConfigDecodeResult<TerminalKeyBindingDefinition> parsed =
      _parseKeyBinding(
        '$value=${TerminalActionId.toggleQuickTerminal.stableName}',
      );
  if (!parsed.isSuccess) {
    return TerminalConfigDecodeResult<TerminalKeyBindingChord?>.failure(
      'quick terminal shortcut is invalid: ${parsed.message}',
      hint: 'use `none` or a non-menu chord such as `command+grave` with at least one modifier',
    );
  }
  final TerminalKeyBindingChord chord = parsed.value!.chord;
  if (!chord.shift && !chord.control && !chord.option && !chord.command) {
    return const TerminalConfigDecodeResult<TerminalKeyBindingChord?>.failure(
      'quick terminal shortcut must contain at least one modifier',
      hint: 'for example, use `quick-terminal-shortcut = command+grave`',
    );
  }
  return TerminalConfigDecodeResult<TerminalKeyBindingChord?>.success(chord);
}

TerminalConfigDecodeResult<TerminalConfiguredQuickTerminalScreen>
_parseQuickTerminalScreen(String value) => switch (value) {
  'main' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredQuickTerminalScreen
    >.success(TerminalConfiguredQuickTerminalScreen.main),
  'mouse' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredQuickTerminalScreen
    >.success(TerminalConfiguredQuickTerminalScreen.mouse),
  'macos-menu-bar' =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredQuickTerminalScreen
    >.success(TerminalConfiguredQuickTerminalScreen.macosMenuBar),
  _ =>
    const TerminalConfigDecodeResult<
      TerminalConfiguredQuickTerminalScreen
    >.failure(
      'quick terminal screen must be `main`, `mouse`, or `macos-menu-bar`',
      hint: 'use `quick-terminal-screen = main` for the default behavior',
    ),
};

TerminalConfigDecodeResult<double> _parseQuickTerminalAnimationDuration(
  String value,
) => _parseFiniteDouble(
  value,
  minimum: 0,
  maximum: 5,
  description: 'quick terminal animation duration',
);

TerminalConfigDecodeResult<TerminalKeyBindingDefinition> _parseKeyBinding(
  String value,
) {
  if (value.isEmpty ||
      value.length > TerminalKeyBindingLimits.maximumConfigurationUnits ||
      _containsControl(value)) {
    return const TerminalConfigDecodeResult<
      TerminalKeyBindingDefinition
    >.failure(
      'keybind must be control-free text within '
      '${TerminalKeyBindingLimits.maximumConfigurationUnits} UTF-16 units',
      hint: 'use `keybind = control+k=terminal.send-interrupt-signal`',
    );
  }
  final int equals = value.indexOf('=');
  if (equals <= 0 || equals != value.lastIndexOf('=')) {
    return const TerminalConfigDecodeResult<
      TerminalKeyBindingDefinition
    >.failure(
      'keybind must contain one `chord=target` separator',
      hint: 'use `keybind = control+k=terminal.send-interrupt-signal`',
    );
  }
  final String chordText = value.substring(0, equals).trim();
  final String targetText = value.substring(equals + 1).trim();
  if (chordText.isEmpty || targetText.isEmpty) {
    return const TerminalConfigDecodeResult<
      TerminalKeyBindingDefinition
    >.failure(
      'keybind chord and target must not be empty',
      hint:
          'provide one physical key and an action, `unbind`, or `passthrough`',
    );
  }
  final List<String> tokens = chordText
      .split('+')
      .map((String token) => token.trim())
      .toList(growable: false);
  if (tokens.any((String token) => token.isEmpty) || tokens.length > 5) {
    return const TerminalConfigDecodeResult<
      TerminalKeyBindingDefinition
    >.failure(
      'keybind chord must contain one key and at most four modifiers',
      hint: 'modifiers are `shift`, `control`, `option`, and `command`',
    );
  }
  var shift = false;
  var control = false;
  var option = false;
  var command = false;
  TerminalPhysicalKey? physicalKey;
  final Set<String> seenModifiers = <String>{};
  for (final String token in tokens) {
    if (_terminalKeyBindingModifiers.contains(token)) {
      if (!seenModifiers.add(token)) {
        return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.failure(
          'keybind modifier `$token` is repeated',
          hint: 'list each modifier at most once',
        );
      }
      switch (token) {
        case 'shift':
          shift = true;
        case 'control':
          control = true;
        case 'option':
          option = true;
        case 'command':
          command = true;
      }
      continue;
    }
    final TerminalPhysicalKey? key =
        TerminalKeyBindingVocabulary.keyFromConfigName(token);
    if (key == null) {
      return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.failure(
        'unknown keybind key or modifier `$token`',
        hint: 'consult the generated keybinding/action reference',
      );
    }
    if (physicalKey != null) {
      return const TerminalConfigDecodeResult<
        TerminalKeyBindingDefinition
      >.failure(
        'keybind chord must contain exactly one physical key',
        hint: 'remove the extra key name',
      );
    }
    physicalKey = key;
  }
  if (physicalKey == null) {
    return const TerminalConfigDecodeResult<
      TerminalKeyBindingDefinition
    >.failure(
      'keybind chord is missing a physical key',
      hint: 'add one key name after any modifiers',
    );
  }
  final TerminalKeyBindingChord chord = TerminalKeyBindingChord(
    physicalKey: physicalKey,
    shift: shift,
    control: control,
    option: option,
    command: command,
  );
  if (_reservedNativeMenuChords.contains(chord)) {
    return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.failure(
      'keybind chord `${chord.configName}` is reserved by a native menu item',
      hint: 'choose a chord that is not listed as a reserved native shortcut',
    );
  }
  if (targetText == TerminalKeyBindingDefinition.unbindConfigName) {
    return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.success(
      TerminalKeyBindingDefinition.unbind(chord: chord),
    );
  }
  if (targetText == TerminalKeyBindingDefinition.passthroughConfigName) {
    return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.success(
      TerminalKeyBindingDefinition.passthrough(chord: chord),
    );
  }
  final TerminalKeyBindingAction? paneAction =
      TerminalKeyBindingAction.fromConfigName(targetText);
  if (paneAction != null) {
    return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.success(
      TerminalKeyBindingDefinition.action(chord: chord, action: paneAction),
    );
  }
  final TerminalActionId? applicationAction = TerminalActionId.fromStableName(
    targetText,
  );
  if (applicationAction != null) {
    return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.success(
      TerminalKeyBindingDefinition.applicationAction(
        chord: chord,
        applicationAction: applicationAction,
      ),
    );
  }
  return TerminalConfigDecodeResult<TerminalKeyBindingDefinition>.failure(
    'unknown keybind target `$targetText`',
    hint: 'consult the generated keybinding/action reference',
  );
}

final Set<String> _terminalKeyBindingModifiers = Set<String>.unmodifiable(
  TerminalKeyBindingVocabulary.modifierConfigNames,
);

final Set<TerminalKeyBindingChord> _reservedNativeMenuChords =
    Set<TerminalKeyBindingChord>.unmodifiable(
      TerminalActionCatalog.standard().actions
          .where((TerminalActionDefinition action) => action.shortcut != null)
          .map((TerminalActionDefinition action) {
            final TerminalActionShortcut shortcut = action.shortcut!;
            final TerminalKeyBindingChord? chord =
                TerminalKeyBindingVocabulary.chordForNativeShortcut(shortcut);
            if (chord == null) {
              throw StateError(
                'native shortcut `${shortcut.identity}` has no physical key',
              );
            }
            return chord;
          }),
    );

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
