import 'dart:convert';
import 'dart:io';

import 'terminal_config.dart';

enum TerminalSettingsDocumentLimitKind { sourceBytes, draftBytes }

final class TerminalSettingsDocumentLimitException implements Exception {
  const TerminalSettingsDocumentLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final TerminalSettingsDocumentLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalSettingsDocumentLimitException(${kind.name}: '
      '$actual > $maximum)';
}

enum TerminalSettingsDocumentOpenFailureKind { inspect, read, utf8 }

final class TerminalSettingsDocumentOpenException implements Exception {
  const TerminalSettingsDocumentOpenException({
    required this.kind,
    required this.path,
    required this.cause,
  });

  final TerminalSettingsDocumentOpenFailureKind kind;
  final String path;
  final Object cause;

  @override
  String toString() =>
      'TerminalSettingsDocumentOpenException(${kind.name}, $path): $cause';
}

/// Immutable editable projection of one root configuration file.
final class TerminalSettingsDocument {
  const TerminalSettingsDocument({
    required this.rootPath,
    required this.text,
    required this.rootExisted,
    required this.hasGeneratedCatalog,
  });

  final String? rootPath;
  final String text;
  final bool rootExisted;
  final bool hasGeneratedCatalog;

  bool get canPersist => rootPath != null;
}

/// Builds a complete editor buffer without changing configuration semantics.
final class TerminalSettingsDocumentComposer {
  const TerminalSettingsDocumentComposer();

  static const String generatedHeader = '# Dart Terminal settings';
  static const String catalogHeader =
      '# Settings catalog - uncomment a line to override its current source.';

  static final RegExp _representedAssignment = RegExp(
    r'^\s*(?:#\s*)?([a-z][a-z0-9-]*)\s*=',
  );

  TerminalSettingsDocument compose({
    required TerminalConfigSnapshot snapshot,
    required String? rootText,
    required bool rootExisted,
    required int maximumBytes,
  }) {
    if (maximumBytes < 1) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes', 'must be > 0');
    }
    final bool emptyRoot = rootText == null || rootText.trim().isEmpty;
    final String text;
    final bool hasGeneratedCatalog;
    if (emptyRoot) {
      text = _newDocument(snapshot);
      hasGeneratedCatalog = true;
    } else {
      final Set<String> represented = _representedOptions(
        rootText,
        snapshot.schema,
      );
      final List<TerminalConfigOptionBase> missing = snapshot.schema.options
          .where(
            (TerminalConfigOptionBase option) =>
                !represented.contains(option.name),
          )
          .toList(growable: false);
      if (missing.isEmpty) {
        text = rootText;
        hasGeneratedCatalog = false;
      } else {
        final String newline = rootText.contains('\r\n') ? '\r\n' : '\n';
        final StringBuffer buffer = StringBuffer(rootText);
        if (!rootText.endsWith('\n') && !rootText.endsWith('\r')) {
          buffer.write(newline);
        }
        buffer
          ..write(newline)
          ..write(catalogHeader)
          ..write(newline);
        for (final TerminalConfigOptionBase option in missing) {
          buffer
            ..write('# ')
            ..write(option.name)
            ..write(' = ')
            ..write(_suggestedValue(snapshot, option))
            ..write(newline);
        }
        text = buffer.toString();
        hasGeneratedCatalog = true;
      }
    }
    final int bytes = utf8.encode(text).length;
    if (bytes > maximumBytes) {
      throw TerminalSettingsDocumentLimitException(
        kind: TerminalSettingsDocumentLimitKind.draftBytes,
        actual: bytes,
        maximum: maximumBytes,
      );
    }
    return TerminalSettingsDocument(
      rootPath: snapshot.rootPath,
      text: text,
      rootExisted: rootExisted,
      hasGeneratedCatalog: hasGeneratedCatalog,
    );
  }

  static String _newDocument(TerminalConfigSnapshot snapshot) {
    final StringBuffer buffer = StringBuffer()
      ..writeln(generatedHeader)
      ..writeln(
        '# Nullable and repeatable examples stay disabled until uncommented.',
      )
      ..writeln();
    for (final TerminalConfigOptionBase option in snapshot.schema.options) {
      final String value = _suggestedValue(snapshot, option);
      final bool active = !option.isRepeatable && value != option.valueSyntax;
      if (!active) buffer.write('# ');
      buffer
        ..write(option.name)
        ..write(' = ')
        ..writeln(value);
    }
    return buffer.toString();
  }

  static Set<String> _representedOptions(
    String text,
    TerminalConfigSchema schema,
  ) {
    final Set<String> represented = <String>{};
    for (final String line in const LineSplitter().convert(text)) {
      final RegExpMatch? match = _representedAssignment.firstMatch(line);
      if (match == null) continue;
      final String name = match.group(1)!;
      if (schema.optionNamed(name) != null) represented.add(name);
    }
    return represented;
  }

  static String _suggestedValue(
    TerminalConfigSnapshot snapshot,
    TerminalConfigOptionBase option,
  ) {
    if (option.isRepeatable) return option.valueSyntax;
    final TerminalResolvedConfigValue<Object?> resolved = snapshot
        .resolvedOption(option);
    return option.formatObject(resolved.value) ?? option.valueSyntax;
  }
}

/// Filesystem mutation boundary used after a draft has passed validation.
abstract interface class TerminalSettingsDocumentWriter {
  void writeAtomically(String path, List<int> bytes);
}

typedef TerminalSettingsPermissionBitsApplier = void Function(
  String temporaryPath,
  String targetPath,
  int permissionBits,
);

/// Same-directory temporary-file replacement for the local macOS product.
final class LocalTerminalSettingsDocumentWriter
    implements TerminalSettingsDocumentWriter {
  const LocalTerminalSettingsDocumentWriter({
    TerminalSettingsPermissionBitsApplier permissionBitsApplier =
        _applyLocalPermissionBits,
  }) : _permissionBitsApplier = permissionBitsApplier;

  static int _nextTemporaryId = 0;
  final TerminalSettingsPermissionBitsApplier _permissionBitsApplier;

  @override
  void writeAtomically(String path, List<int> bytes) {
    final File target = File(path);
    if (!target.isAbsolute) {
      throw ArgumentError.value(path, 'path', 'must be absolute');
    }
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('refusing to replace a non-regular file', path);
    }
    final int? permissionBits = type == FileSystemEntityType.file
        ? FileStat.statSync(path).mode & 0xFFF
        : null;
    target.parent.createSync(recursive: true);

    File? temporary;
    try {
      for (var attempt = 0; attempt < 64; attempt++) {
        final int id = _nextTemporaryId++;
        final File candidate = File(
          '$path.dart-terminal-${pid.toRadixString(16)}-$id.tmp',
        );
        try {
          candidate.createSync(exclusive: true);
          temporary = candidate;
          break;
        } on FileSystemException {
          // A stale/colliding sibling never authorizes overwriting it.
        }
      }
      final File selected =
          temporary ??
          (throw FileSystemException(
            'could not reserve an atomic-save temporary file',
            path,
          ));
      final RandomAccessFile output = selected.openSync(mode: FileMode.write);
      try {
        output
          ..writeFromSync(bytes)
          ..flushSync();
      } finally {
        output.closeSync();
      }
      if (permissionBits != null) {
        _permissionBitsApplier(selected.path, path, permissionBits);
      }
      selected.renameSync(path);
      temporary = null;
    } finally {
      final File? leftover = temporary;
      if (leftover != null && leftover.existsSync()) {
        leftover.deleteSync();
      }
    }
  }
}

void _applyLocalPermissionBits(
  String temporaryPath,
  String targetPath,
  int permissionBits,
) {
  final String mode = permissionBits.toRadixString(8).padLeft(4, '0');
  final ProcessResult result = Process.runSync('/bin/chmod', <String>[
    mode,
    temporaryPath,
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'could not preserve existing configuration permissions',
      targetPath,
    );
  }
}

enum TerminalSettingsDocumentSaveDisposition {
  saved,
  rejected,
  conflict,
  unavailable,
  failed,
}

final class TerminalSettingsDocumentSaveResult {
  const TerminalSettingsDocumentSaveResult({
    required this.disposition,
    required this.document,
    this.candidateSnapshot,
    this.diagnostics = const <TerminalConfigDiagnostic>[],
    this.error,
    this.stackTrace,
  });

  final TerminalSettingsDocumentSaveDisposition disposition;
  final TerminalSettingsDocument document;
  final TerminalConfigSnapshot? candidateSnapshot;
  final List<TerminalConfigDiagnostic> diagnostics;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSaved =>
      disposition == TerminalSettingsDocumentSaveDisposition.saved;
}

/// Owns one opened root revision and validates before atomic replacement.
final class TerminalSettingsDocumentSession {
  TerminalSettingsDocumentSession({
    required TerminalConfigLoader loader,
    required List<String> arguments,
    Map<String, String>? environment,
    String? currentDirectory,
    TerminalSettingsDocumentWriter writer =
        const LocalTerminalSettingsDocumentWriter(),
    TerminalSettingsDocumentComposer composer =
        const TerminalSettingsDocumentComposer(),
  }) : _loader = loader,
       _arguments = List<String>.unmodifiable(arguments),
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _currentDirectory = currentDirectory ?? Directory.current.path,
       _writer = writer,
       _composer = composer;

  final TerminalConfigLoader _loader;
  final List<String> _arguments;
  final Map<String, String> _environment;
  final String _currentDirectory;
  final TerminalSettingsDocumentWriter _writer;
  final TerminalSettingsDocumentComposer _composer;

  TerminalSettingsDocument? _document;
  List<int>? _baselineBytes;
  var _baselineExisted = false;

  TerminalSettingsDocument? get currentDocument => _document;

  TerminalSettingsDocument open(TerminalConfigSnapshot snapshot) {
    if (!identical(snapshot.schema, _loader.schema)) {
      throw ArgumentError(
        'snapshot and document loader must use the same schema instance',
      );
    }
    final String? path = snapshot.rootPath;
    List<int>? sourceBytes;
    var existed = false;
    if (path != null) {
      try {
        existed = _loader.fileSystem.exists(path);
      } on Object catch (error) {
        throw TerminalSettingsDocumentOpenException(
          kind: TerminalSettingsDocumentOpenFailureKind.inspect,
          path: path,
          cause: error,
        );
      }
      if (existed) {
        try {
          sourceBytes = _loader.fileSystem.readBytes(path);
        } on Object catch (error) {
          throw TerminalSettingsDocumentOpenException(
            kind: TerminalSettingsDocumentOpenFailureKind.read,
            path: path,
            cause: error,
          );
        }
        if (sourceBytes.length > _loader.limits.maxFileBytes) {
          throw TerminalSettingsDocumentLimitException(
            kind: TerminalSettingsDocumentLimitKind.sourceBytes,
            actual: sourceBytes.length,
            maximum: _loader.limits.maxFileBytes,
          );
        }
      }
    }

    String? rootText;
    if (sourceBytes != null) {
      try {
        rootText = utf8.decode(sourceBytes);
      } on FormatException catch (error) {
        throw TerminalSettingsDocumentOpenException(
          kind: TerminalSettingsDocumentOpenFailureKind.utf8,
          path: path!,
          cause: error,
        );
      }
    }
    final TerminalSettingsDocument opened = _composer.compose(
      snapshot: snapshot,
      rootText: rootText,
      rootExisted: existed,
      maximumBytes: _loader.limits.maxFileBytes,
    );
    _baselineBytes = sourceBytes == null
        ? null
        : List<int>.unmodifiable(sourceBytes);
    _baselineExisted = existed;
    _document = opened;
    return opened;
  }

  TerminalSettingsDocumentSaveResult save(String draft) {
    final TerminalSettingsDocument opened =
        _document ?? (throw StateError('settings document is not open'));
    final String? path = opened.rootPath;
    if (path == null) {
      return TerminalSettingsDocumentSaveResult(
        disposition: TerminalSettingsDocumentSaveDisposition.unavailable,
        document: opened,
      );
    }
    final List<int> bytes = utf8.encode(draft);
    if (bytes.length > _loader.limits.maxFileBytes) {
      throw TerminalSettingsDocumentLimitException(
        kind: TerminalSettingsDocumentLimitKind.draftBytes,
        actual: bytes.length,
        maximum: _loader.limits.maxFileBytes,
      );
    }

    try {
      if (!_matchesBaseline(path)) {
        return TerminalSettingsDocumentSaveResult(
          disposition: TerminalSettingsDocumentSaveDisposition.conflict,
          document: opened,
        );
      }
      final TerminalConfigFileSystem overlay =
          _TerminalSettingsRootOverlayFileSystem(
            base: _loader.fileSystem,
            rootPath: path,
            bytes: bytes,
          );
      final TerminalConfigSnapshot candidate =
          TerminalConfigLoader(
                schema: _loader.schema,
                fileSystem: overlay,
                limits: _loader.limits,
              )
              .resolve(
                _arguments,
                environment: _environment,
                currentDirectory: _currentDirectory,
              )
              .snapshot;
      if (candidate.rootPath != path) {
        throw StateError('draft validation resolved a different root path');
      }
      final bool hasError = candidate.diagnostics.any(
        (TerminalConfigDiagnostic diagnostic) =>
            diagnostic.severity == TerminalConfigDiagnosticSeverity.error,
      );
      if (hasError) {
        return TerminalSettingsDocumentSaveResult(
          disposition: TerminalSettingsDocumentSaveDisposition.rejected,
          document: opened,
          candidateSnapshot: candidate,
          diagnostics: candidate.diagnostics,
        );
      }

      _writer.writeAtomically(path, bytes);
      final TerminalSettingsDocument saved = TerminalSettingsDocument(
        rootPath: path,
        text: draft,
        rootExisted: true,
        hasGeneratedCatalog: opened.hasGeneratedCatalog,
      );
      _baselineBytes = List<int>.unmodifiable(bytes);
      _baselineExisted = true;
      _document = saved;
      return TerminalSettingsDocumentSaveResult(
        disposition: TerminalSettingsDocumentSaveDisposition.saved,
        document: saved,
        candidateSnapshot: candidate,
        diagnostics: candidate.diagnostics,
      );
    } on Object catch (error, stackTrace) {
      return TerminalSettingsDocumentSaveResult(
        disposition: TerminalSettingsDocumentSaveDisposition.failed,
        document: opened,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _matchesBaseline(String path) {
    final bool exists = _loader.fileSystem.exists(path);
    if (exists != _baselineExisted) return false;
    if (!exists) return true;
    final List<int> current = _loader.fileSystem.readBytes(path);
    final List<int>? baseline = _baselineBytes;
    if (baseline == null || current.length != baseline.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index] != baseline[index]) return false;
    }
    return true;
  }
}

final class _TerminalSettingsRootOverlayFileSystem
    implements TerminalConfigFileSystem {
  const _TerminalSettingsRootOverlayFileSystem({
    required this.base,
    required this.rootPath,
    required this.bytes,
  });

  final TerminalConfigFileSystem base;
  final String rootPath;
  final List<int> bytes;

  @override
  String absolutePath(String path) => base.absolutePath(path);

  @override
  bool exists(String path) => _isRoot(path) || base.exists(path);

  @override
  List<int> readBytes(String path) =>
      _isRoot(path) ? List<int>.from(bytes) : base.readBytes(path);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      base.resolvePath(containingFile, includedPath);

  bool _isRoot(String path) => base.absolutePath(path) == rootPath;
}
