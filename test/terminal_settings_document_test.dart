import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSettingsDocumentTests();

void runTerminalSettingsDocumentTests() {
  _testCompleteMissingAndSparseDocuments();
  _testValidationPersistenceAndConflict();
  _testUnavailableAndInvalidUtf8();
  _testLocalAtomicWriter();
}

void _testCompleteMissingAndSparseDocuments() {
  final _MemoryDocumentFileSystem missing = _MemoryDocumentFileSystem(
    const <String, List<int>>{},
  );
  final TerminalConfigLoader missingLoader = TerminalConfigLoader(
    fileSystem: missing,
  );
  final TerminalConfigSnapshot missingSnapshot = missingLoader
      .resolve(
        const <String>[],
        environment: const <String, String>{'HOME': '/users/test'},
      )
      .snapshot;
  final TerminalSettingsDocumentSession missingSession =
      TerminalSettingsDocumentSession(
        loader: missingLoader,
        arguments: const <String>[],
        environment: const <String, String>{'HOME': '/users/test'},
        writer: missing,
      );
  final TerminalSettingsDocument missingDocument = missingSession.open(
    missingSnapshot,
  );
  _expect(
    !missingDocument.rootExisted &&
        missingDocument.canPersist &&
        missingDocument.hasGeneratedCatalog &&
        missingDocument.text.startsWith(
          '${TerminalSettingsDocumentComposer.generatedHeader}\n',
        ) &&
        _representedSchemaNames(missingDocument.text).length == 42 &&
        missingDocument.text.contains('shell = /bin/zsh\n') &&
        missingDocument.text.contains('# working-directory = <path>\n') &&
        missingDocument.text.contains('# keybind = <modifier+key=target>\n') &&
        !missing.files.containsKey(missingDocument.rootPath),
    'missing root is not a complete non-persisted canonical scaffold',
  );

  final _MemoryDocumentFileSystem sparse = _MemoryDocumentFileSystem.fromText(
    const <String, String>{
      '/config': '# keep this comment\r\ninclude = child\r\nfont-size = 17',
      '/child': 'theme = dark\n',
    },
  );
  final TerminalConfigLoader sparseLoader = TerminalConfigLoader(
    fileSystem: sparse,
  );
  final TerminalConfigSnapshot sparseSnapshot = sparseLoader.resolve(
    const <String>['--config=/config'],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalSettingsDocument sparseDocument =
      TerminalSettingsDocumentSession(
        loader: sparseLoader,
        arguments: const <String>['--config=/config'],
        environment: const <String, String>{},
        writer: sparse,
      ).open(sparseSnapshot);
  _expect(
    sparseDocument.text.startsWith(
          '# keep this comment\r\ninclude = child\r\nfont-size = 17\r\n',
        ) &&
        sparseDocument.text.contains(
          '\r\n${TerminalSettingsDocumentComposer.catalogHeader}\r\n',
        ) &&
        _occurrences(sparseDocument.text, 'font-size =') == 1 &&
        sparseDocument.text.contains('# theme = dark\r\n') &&
        sparse.readText('/config') ==
            '# keep this comment\r\ninclude = child\r\nfont-size = 17',
    'sparse document loses root text, line endings, or include-safe catalog',
  );
}

void _testValidationPersistenceAndConflict() {
  final _MemoryDocumentFileSystem files = _MemoryDocumentFileSystem.fromText(
    const <String, String>{
      '/config': 'font-size = 17\ninclude = child\n',
      '/child': 'theme = dark\n',
    },
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  final List<String> arguments = const <String>['--config=/config'];
  final TerminalConfigSnapshot snapshot = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalSettingsDocumentSession session =
      TerminalSettingsDocumentSession(
        loader: loader,
        arguments: arguments,
        environment: const <String, String>{},
        writer: files,
      );
  final TerminalSettingsDocument opened = session.open(snapshot);
  final String invalidDraft = opened.text.replaceFirst(
    'font-size = 17',
    'font-size = enormous',
  );
  final TerminalSettingsDocumentSaveResult rejected = session.save(
    invalidDraft,
  );
  _expect(
    rejected.disposition == TerminalSettingsDocumentSaveDisposition.rejected &&
        rejected.diagnostics.any(
          (TerminalConfigDiagnostic diagnostic) =>
              diagnostic.code == 'CFG_INVALID_VALUE',
        ) &&
        files.atomicWriteCount == 0 &&
        files.readText('/config') == 'font-size = 17\ninclude = child\n' &&
        identical(session.currentDocument, opened),
    'invalid draft wrote bytes or replaced the opened document revision',
  );

  final String validDraft = opened.text.replaceFirst(
    'font-size = 17',
    'font-size = 19',
  );
  final TerminalSettingsDocumentSaveResult saved = session.save(validDraft);
  _expect(
    saved.isSaved &&
        saved.candidateSnapshot?.value(TerminalProductConfigSchema.fontSize) ==
            19 &&
        saved.candidateSnapshot?.value(TerminalProductConfigSchema.theme) ==
            TerminalConfiguredTheme.dark &&
        files.atomicWriteCount == 1 &&
        files.readText('/config') == validDraft &&
        session.currentDocument?.text == validDraft,
    'valid draft did not atomically persist or validate includes',
  );

  files.setText('/config', '$validDraft# external change\n');
  final TerminalSettingsDocumentSaveResult conflict = session.save(
    '$validDraft# local change\n',
  );
  _expect(
    conflict.disposition == TerminalSettingsDocumentSaveDisposition.conflict &&
        files.atomicWriteCount == 1 &&
        files.readText('/config').endsWith('# external change\n'),
    'external root change was overwritten instead of reported as a conflict',
  );
}

void _testUnavailableAndInvalidUtf8() {
  final _MemoryDocumentFileSystem files = _MemoryDocumentFileSystem(
    const <String, List<int>>{},
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  final List<String> arguments = const <String>['--no-config'];
  final TerminalConfigSnapshot snapshot = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalSettingsDocumentSession session =
      TerminalSettingsDocumentSession(
        loader: loader,
        arguments: arguments,
        environment: const <String, String>{},
        writer: files,
      );
  final TerminalSettingsDocument document = session.open(snapshot);
  _expect(
    !document.canPersist &&
        _representedSchemaNames(document.text).length == 42 &&
        session.save(document.text).disposition ==
            TerminalSettingsDocumentSaveDisposition.unavailable &&
        files.atomicWriteCount == 0,
    'no-config document invented a persistence target or lost schema entries',
  );

  final _MemoryDocumentFileSystem malformed = _MemoryDocumentFileSystem(
    const <String, List<int>>{
      '/invalid-utf8': <int>[0xc3, 0x28],
    },
  );
  final TerminalConfigLoader malformedLoader = TerminalConfigLoader(
    fileSystem: malformed,
  );
  final TerminalConfigSnapshot malformedSnapshot = malformedLoader.resolve(
    const <String>['--config=/invalid-utf8'],
    environment: const <String, String>{},
  ).snapshot;
  _expectThrows<TerminalSettingsDocumentOpenException>(
    () => TerminalSettingsDocumentSession(
      loader: malformedLoader,
      arguments: const <String>['--config=/invalid-utf8'],
      environment: const <String, String>{},
      writer: malformed,
    ).open(malformedSnapshot),
    'malformed root bytes were replaced with a generated document',
  );
}

void _testLocalAtomicWriter() {
  final Directory root = Directory.systemTemp.createTempSync(
    'dart-terminal-settings-document-',
  );
  try {
    final String path = '${root.path}/nested/config';
    const LocalTerminalSettingsDocumentWriter().writeAtomically(
      path,
      utf8.encode('font-size = 21\n'),
    );
    final List<FileSystemEntity> siblings = Directory('${root.path}/nested')
        .listSync();
    _expect(
      File(path).readAsStringSync() == 'font-size = 21\n' &&
          siblings.length == 1 &&
          siblings.single.path == path,
      'local atomic writer left a sibling temporary artifact',
    );

    final ProcessResult chmod = Process.runSync('/bin/chmod', <String>[
      '0600',
      path,
    ]);
    _expect(chmod.exitCode == 0, 'test could not set a distinctive file mode');
    const LocalTerminalSettingsDocumentWriter().writeAtomically(
      path,
      utf8.encode('font-size = 22\n'),
    );
    final int permissionBits = FileStat.statSync(path).mode & 0xFFF;
    final List<FileSystemEntity> replacedSiblings = Directory(
      '${root.path}/nested',
    ).listSync();
    _expect(
      File(path).readAsStringSync() == 'font-size = 22\n' &&
          permissionBits == 0x180 &&
          replacedSiblings.length == 1 &&
          replacedSiblings.single.path == path,
      'atomic replacement changed existing 0600 permission bits or leaked temp',
    );

    _expectThrows<StateError>(
      () => LocalTerminalSettingsDocumentWriter(
        permissionBitsApplier:
            (String temporaryPath, String targetPath, int permissionBits) {
              throw StateError('injected permission failure');
            },
      ).writeAtomically(path, utf8.encode('font-size = 23\n')),
      'permission failure did not abort atomic replacement',
    );
    final List<FileSystemEntity> failedSiblings = Directory(
      '${root.path}/nested',
    ).listSync();
    _expect(
      File(path).readAsStringSync() == 'font-size = 22\n' &&
          (FileStat.statSync(path).mode & 0xFFF) == 0x180 &&
          failedSiblings.length == 1 &&
          failedSiblings.single.path == path,
      'permission failure replaced the target or left a temporary sibling',
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

Set<String> _representedSchemaNames(String text) {
  final RegExp assignment = RegExp(
    r'^\s*(?:#\s*)?([a-z][a-z0-9-]*)\s*=',
    multiLine: true,
  );
  return <String>{
    for (final RegExpMatch match in assignment.allMatches(text))
      if (TerminalProductConfigSchema.instance.optionNamed(match.group(1)!) !=
          null)
        match.group(1)!,
  };
}

int _occurrences(String text, String pattern) {
  var count = 0;
  var offset = 0;
  while (true) {
    final int next = text.indexOf(pattern, offset);
    if (next < 0) return count;
    count++;
    offset = next + pattern.length;
  }
}

final class _MemoryDocumentFileSystem
    implements TerminalConfigFileSystem, TerminalSettingsDocumentWriter {
  _MemoryDocumentFileSystem(Map<String, List<int>> files)
    : files = <String, List<int>>{
        for (final MapEntry<String, List<int>> entry in files.entries)
          entry.key: List<int>.from(entry.value),
      };

  factory _MemoryDocumentFileSystem.fromText(Map<String, String> files) =>
      _MemoryDocumentFileSystem(<String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      });

  final Map<String, List<int>> files;
  var atomicWriteCount = 0;

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => files.containsKey(absolutePath(path));

  @override
  List<int> readBytes(String path) =>
      List<int>.from(files[absolutePath(path)]!);

  @override
  String resolvePath(String containingFile, String includedPath) {
    if (includedPath.startsWith('/')) return absolutePath(includedPath);
    final int separator = containingFile.lastIndexOf('/');
    final String directory = separator <= 0
        ? ''
        : containingFile.substring(0, separator);
    return absolutePath('$directory/$includedPath');
  }

  @override
  void writeAtomically(String path, List<int> bytes) {
    atomicWriteCount++;
    files[absolutePath(path)] = List<int>.from(bytes);
  }

  String readText(String path) => utf8.decode(files[absolutePath(path)]!);

  void setText(String path, String text) {
    files[absolutePath(path)] = utf8.encode(text);
  }
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal settings document expectation failed: $description',
    );
  }
}
