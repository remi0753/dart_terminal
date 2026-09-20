import 'dart:convert';

import 'terminal_config.dart';

enum TerminalEffectiveConfigLimitKind {
  entries,
  canonicalCharacters,
  diagnostics,
  outputCharacters,
}

final class TerminalEffectiveConfigLimitException implements Exception {
  const TerminalEffectiveConfigLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final TerminalEffectiveConfigLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalEffectiveConfigLimitException(${kind.name}: '
      '$actual > $maximum)';
}

/// Hard collection and rendering bounds for local configuration inspection.
final class TerminalEffectiveConfigLimits {
  const TerminalEffectiveConfigLimits({
    this.maxEntries = 4608,
    this.maxCanonicalCharacters = 1024 * 1024,
    this.maxDiagnostics = 128,
    this.maxOutputCharacters = 2 * 1024 * 1024,
  });

  static const int maximumEntries = 8192;
  static const int maximumCanonicalCharacters = 16 * 1024 * 1024;
  static const int maximumDiagnostics = 1024;
  static const int maximumOutputCharacters = 16 * 1024 * 1024;

  final int maxEntries;
  final int maxCanonicalCharacters;
  final int maxDiagnostics;
  final int maxOutputCharacters;

  void validate() {
    _validateBound(maxEntries, maximumEntries, 'maxEntries');
    _validateBound(
      maxCanonicalCharacters,
      maximumCanonicalCharacters,
      'maxCanonicalCharacters',
    );
    _validateBound(maxDiagnostics, maximumDiagnostics, 'maxDiagnostics');
    _validateBound(
      maxOutputCharacters,
      maximumOutputCharacters,
      'maxOutputCharacters',
    );
  }

  static void _validateBound(int value, int maximum, String name) {
    if (value < 1 || value > maximum) {
      throw ArgumentError.value(value, name, 'must be in 1..$maximum');
    }
  }
}

/// One scalar value, repeated occurrence, or empty-repeatable placeholder.
final class TerminalEffectiveConfigEntry {
  const TerminalEffectiveConfigEntry({
    required this.option,
    required this.canonicalValue,
    required this.source,
    required this.occurrenceIndex,
    required this.occurrenceCount,
  });

  final TerminalConfigOptionBase option;
  final String? canonicalValue;
  final TerminalConfigSource source;

  /// One-based for effective values and zero for an empty repeatable option.
  final int occurrenceIndex;
  final int occurrenceCount;

  bool get hasOccurrence => occurrenceIndex != 0;
  bool get isRepeatable => option.isRepeatable;
}

/// Immutable, schema-ordered view of one accepted or attempted snapshot.
final class TerminalEffectiveConfigSnapshot {
  factory TerminalEffectiveConfigSnapshot.fromSnapshot(
    TerminalConfigSnapshot snapshot, {
    TerminalEffectiveConfigLimits limits =
        const TerminalEffectiveConfigLimits(),
    bool publicOnly = false,
  }) {
    limits.validate();
    final List<TerminalEffectiveConfigEntry> entries =
        <TerminalEffectiveConfigEntry>[];
    var canonicalCharacters = 0;
    final Iterable<TerminalConfigOptionBase> options = publicOnly
        ? snapshot.schema.publicOptions
        : snapshot.schema.options;
    for (final TerminalConfigOptionBase option in options) {
      if (!option.isRepeatable) {
        final TerminalResolvedConfigValue<Object?> resolved = snapshot
            .resolvedOption(option);
        final String? canonical = option.formatObject(resolved.value);
        canonicalCharacters += canonical?.length ?? 0;
        entries.add(
          TerminalEffectiveConfigEntry(
            option: option,
            canonicalValue: canonical,
            source: resolved.source,
            occurrenceIndex: 1,
            occurrenceCount: 1,
          ),
        );
        continue;
      }
      final List<TerminalResolvedConfigValue<Object?>> occurrences = snapshot
          .occurrencesFor(option);
      if (occurrences.isEmpty) {
        entries.add(
          TerminalEffectiveConfigEntry(
            option: option,
            canonicalValue: null,
            source: const TerminalConfigSource.schemaDefault(),
            occurrenceIndex: 0,
            occurrenceCount: 0,
          ),
        );
        continue;
      }
      for (var index = 0; index < occurrences.length; index += 1) {
        final TerminalResolvedConfigValue<Object?> resolved =
            occurrences[index];
        final String canonical = option.formatObject(resolved.value)!;
        canonicalCharacters += canonical.length;
        entries.add(
          TerminalEffectiveConfigEntry(
            option: option,
            canonicalValue: canonical,
            source: resolved.source,
            occurrenceIndex: index + 1,
            occurrenceCount: occurrences.length,
          ),
        );
      }
    }
    _checkLimit(
      TerminalEffectiveConfigLimitKind.entries,
      entries.length,
      limits.maxEntries,
    );
    _checkLimit(
      TerminalEffectiveConfigLimitKind.canonicalCharacters,
      canonicalCharacters,
      limits.maxCanonicalCharacters,
    );
    _checkLimit(
      TerminalEffectiveConfigLimitKind.diagnostics,
      snapshot.diagnostics.length,
      limits.maxDiagnostics,
    );
    return TerminalEffectiveConfigSnapshot._(
      schema: snapshot.schema,
      rootPath: snapshot.rootPath,
      entries: entries,
      diagnostics: snapshot.diagnostics,
      canonicalCharacters: canonicalCharacters,
    );
  }

  TerminalEffectiveConfigSnapshot._({
    required this.schema,
    required this.rootPath,
    required Iterable<TerminalEffectiveConfigEntry> entries,
    required Iterable<TerminalConfigDiagnostic> diagnostics,
    required this.canonicalCharacters,
  }) : entries = List<TerminalEffectiveConfigEntry>.unmodifiable(entries),
       diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(diagnostics);

  final TerminalConfigSchema schema;
  final String? rootPath;
  final List<TerminalEffectiveConfigEntry> entries;
  final List<TerminalConfigDiagnostic> diagnostics;
  final int canonicalCharacters;

  Iterable<TerminalEffectiveConfigEntry> entriesFor(
    TerminalConfigOptionBase option,
  ) => entries.where(
    (TerminalEffectiveConfigEntry entry) => identical(entry.option, option),
  );
}

/// Deterministic line-oriented output with JSON-escaped user-controlled text.
final class TerminalEffectiveConfigFormatter {
  factory TerminalEffectiveConfigFormatter({
    TerminalEffectiveConfigLimits limits =
        const TerminalEffectiveConfigLimits(),
  }) {
    limits.validate();
    return TerminalEffectiveConfigFormatter._(limits);
  }

  const TerminalEffectiveConfigFormatter._(this.limits);

  static const String formatName = 'dart-terminal-effective-config';
  static const int formatVersion = 1;

  final TerminalEffectiveConfigLimits limits;

  String format(TerminalConfigSnapshot snapshot) {
    final TerminalEffectiveConfigSnapshot effective =
        TerminalEffectiveConfigSnapshot.fromSnapshot(snapshot, limits: limits);
    final _EffectiveConfigWriter writer = _EffectiveConfigWriter(
      limits.maxOutputCharacters,
    );
    writer.line(
      '$formatName version=$formatVersion options=${effective.schema.options.length} '
      'entries=${effective.entries.length} '
      'diagnostics=${effective.diagnostics.length}',
    );
    writer.line('root path=${jsonEncode(effective.rootPath)}');
    for (final TerminalEffectiveConfigEntry entry in effective.entries) {
      writer.line(_formatEntry(entry));
    }
    for (final TerminalConfigDiagnostic diagnostic in effective.diagnostics) {
      writer.line(formatDiagnostic(diagnostic));
    }
    writer.line('end');
    return writer.finish();
  }

  String formatDiagnostic(TerminalConfigDiagnostic diagnostic) {
    final TerminalConfigSource source = diagnostic.source;
    final String formatted =
        'diagnostic severity=${diagnostic.severity.name} '
        'code=${jsonEncode(diagnostic.code)} '
        'message=${jsonEncode(diagnostic.message)} '
        'hint=${jsonEncode(diagnostic.hint)} '
        'source=${_sourceKind(source.kind)} '
        'path=${jsonEncode(source.path)} line=${source.line} '
        'column=${source.column}';
    _checkLimit(
      TerminalEffectiveConfigLimitKind.outputCharacters,
      formatted.length,
      limits.maxOutputCharacters,
    );
    return formatted;
  }

  String _formatEntry(TerminalEffectiveConfigEntry entry) {
    final TerminalConfigSource source = entry.source;
    return 'option name=${jsonEncode(entry.option.name)} '
        'value=${jsonEncode(entry.canonicalValue)} '
        'syntax=${jsonEncode(entry.option.valueSyntax)} '
        'repeatable=${entry.isRepeatable} '
        'occurrence=${entry.occurrenceIndex}/${entry.occurrenceCount} '
        'policy=${_policy(entry.option.applicationPolicy)} '
        'source=${_sourceKind(source.kind)} '
        'path=${jsonEncode(source.path)} line=${source.line} '
        'column=${source.column}';
  }

  static String _policy(TerminalConfigApplicationPolicy policy) =>
      switch (policy) {
        TerminalConfigApplicationPolicy.live => 'live',
        TerminalConfigApplicationPolicy.newSession => 'new-session',
        TerminalConfigApplicationPolicy.nextLaunch => 'next-launch',
      };

  static String _sourceKind(TerminalConfigSourceKind kind) => switch (kind) {
    TerminalConfigSourceKind.schemaDefault => 'default',
    TerminalConfigSourceKind.file => 'file',
    TerminalConfigSourceKind.commandLine => 'command-line',
  };
}

void _checkLimit(
  TerminalEffectiveConfigLimitKind kind,
  int actual,
  int maximum,
) {
  if (actual > maximum) {
    throw TerminalEffectiveConfigLimitException(
      kind: kind,
      actual: actual,
      maximum: maximum,
    );
  }
}

final class _EffectiveConfigWriter {
  _EffectiveConfigWriter(this.maximumCharacters);

  final int maximumCharacters;
  final StringBuffer _buffer = StringBuffer();
  var _characters = 0;

  void line(String value) {
    final int next = _characters + value.length + 1;
    _checkLimit(
      TerminalEffectiveConfigLimitKind.outputCharacters,
      next,
      maximumCharacters,
    );
    _buffer
      ..write(value)
      ..write('\n');
    _characters = next;
  }

  String finish() => _buffer.toString();
}
