import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalNoteStoreWorkerTests();

void runTerminalNoteStoreWorkerTests() {
  _testLocationAndLockBoundary();
  _testLoadCommitAndRecovery();
  _testOrdinaryCommitFaultMatrix();
  _testDeletionCrashMatrix();
  _testPortableExport();
  _testPrivacyAndGenericPackageBoundary();
}

void _testLocationAndLockBoundary() {
  final TerminalNoteStoreLocation xdg =
      TerminalNoteStoreLocation.fromEnvironment(<String, String>{
        'XDG_STATE_HOME': '/private/tmp/state',
        'HOME': '/Users/example',
      });
  _expect(
    xdg.canonicalPath == '/private/tmp/state/dart-terminal/notes',
    'safe XDG state root wins',
  );
  final TerminalNoteStoreLocation fallback =
      TerminalNoteStoreLocation.fromEnvironment(<String, String>{
        'XDG_STATE_HOME': 'relative',
        'HOME': '/Users/example',
      });
  _expect(
    fallback.canonicalPath ==
        '/Users/example/Library/Application Support/Dart Terminal/Notes',
    'unsafe XDG state falls back to the macOS application support root',
  );
  _expectThrowsStore(
    () => TerminalNoteStoreLocation.fromEnvironment(<String, String>{
      'HOME': '/Users/../escape',
    }),
    TerminalNoteStoreFailure.invalidLocation,
    'unsafe fallback root is rejected',
  );
  _expect(
    !xdg.toString().contains(xdg.canonicalPath),
    'location formatting redacts the path',
  );

  final _FakeFileSystem fileSystem = _FakeFileSystem();
  final TerminalNoteStoreTransactionEngine first = _open(fileSystem);
  _expectThrowsStore(
    () => _open(fileSystem),
    TerminalNoteStoreFailure.lockBusy,
    'one process-wide store lock excludes a second writer',
  );
  _expect(first.stop().isSuccess, 'first lock holder stops cleanly');
  final TerminalNoteStoreTransactionEngine afterStop = _open(fileSystem);
  _expect(afterStop.stop().isSuccess, 'lock is released by stop');

  final _FakeFileSystem lockFailure = _FakeFileSystem()
    ..failNext('lock:', TerminalNoteStoreFailure.lockBusy);
  _expectThrowsStore(
    () => _open(lockFailure),
    TerminalNoteStoreFailure.lockBusy,
    'lock failure is mapped without creating an engine',
  );
  _expect(
    lockFailure.activeSessions == 0,
    'directory session is closed when lock acquisition fails',
  );
}

void _testLoadCommitAndRecovery() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteStoreDocument base = _baseDocument();
  final TerminalNoteStoreDocument edited = _editedDocument(base);

  final _FakeFileSystem emptyFileSystem = _FakeFileSystem();
  final TerminalNoteStoreTransactionEngine empty = _open(emptyFileSystem);
  final TerminalNoteStoreResult emptyLoad = empty.load();
  _expect(
    emptyLoad.disposition == TerminalNoteStoreDisposition.empty &&
        emptyLoad.document!.snapshot.notes.isEmpty &&
        emptyFileSystem.mutationOperations.isEmpty,
    'two missing copies load as empty without writing',
  );
  _expect(
    empty.commitCandidate(base).disposition ==
        TerminalNoteStoreDisposition.committed,
    'first candidate is committed',
  );
  _expect(
    empty.commitCandidate(edited).disposition ==
        TerminalNoteStoreDisposition.committed,
    'second candidate rotates the previous current into backup',
  );
  empty.stop();
  _expectDocumentBytes(
    emptyFileSystem.file(
      _storePath,
      TerminalNoteStoreTransactionEngine.currentLeaf,
    ),
    codec.encode(edited),
    'current contains the latest commit',
  );
  _expectDocumentBytes(
    emptyFileSystem.file(
      _storePath,
      TerminalNoteStoreTransactionEngine.backupLeaf,
    ),
    codec.encode(base),
    'backup contains the previous known-good commit',
  );

  final TerminalNoteStoreTransactionEngine reloaded = _open(emptyFileSystem);
  final TerminalNoteStoreResult currentLoad = reloaded.load();
  _expect(
    currentLoad.disposition == TerminalNoteStoreDisposition.loaded &&
        _sameDocument(currentLoad.document!, edited),
    'valid current is authoritative and is not merged with older backup',
  );
  reloaded.stop();

  final _FakeFileSystem backupOnly = _FakeFileSystem()
    ..put(_storePath, TerminalNoteStoreTransactionEngine.currentLeaf, <int>[
      1,
      2,
      3,
    ])
    ..put(
      _storePath,
      TerminalNoteStoreTransactionEngine.backupLeaf,
      codec.encode(base),
    );
  final TerminalNoteStoreTransactionEngine recovery = _open(backupOnly);
  backupOnly.resetTrace();
  final TerminalNoteStoreResult preview = recovery.load();
  _expect(
    preview.disposition == TerminalNoteStoreDisposition.recoveryPreview &&
        preview.failure == TerminalNoteStoreFailure.recoveryRequired &&
        _sameDocument(preview.document!, base) &&
        backupOnly.mutationOperations.isEmpty,
    'invalid current exposes a read-only backup preview without auto-write',
  );
  _expect(
    recovery.retryRecovery().disposition ==
        TerminalNoteStoreDisposition.committed,
    'explicit retry restores both durable copies',
  );
  recovery.stop();
  _expectDocumentBytes(
    backupOnly.file(_storePath, TerminalNoteStoreTransactionEngine.currentLeaf),
    codec.encode(base),
    'explicit recovery restores current',
  );
  _expectDocumentBytes(
    backupOnly.file(_storePath, TerminalNoteStoreTransactionEngine.backupLeaf),
    codec.encode(base),
    'explicit recovery restores backup',
  );

  final _FakeFileSystem corrupt = _FakeFileSystem()
    ..put(_storePath, TerminalNoteStoreTransactionEngine.currentLeaf, <int>[1])
    ..put(_storePath, TerminalNoteStoreTransactionEngine.backupLeaf, <int>[2]);
  final TerminalNoteStoreTransactionEngine corruptEngine = _open(corrupt);
  corrupt.resetTrace();
  final TerminalNoteStoreResult corruptResult = corruptEngine.load();
  _expect(
    corruptResult.disposition ==
            TerminalNoteStoreDisposition.recoveryRequired &&
        corruptResult.document == null &&
        corrupt.mutationOperations.isEmpty,
    'invalid copies are never silently reset to empty',
  );
  corruptEngine.stop();

  final Uint8List newer = Uint8List.fromList(
    utf8.encode(
      utf8
          .decode(codec.encode(base))
          .replaceFirst('"version":1', '"version":2'),
    ),
  );
  final _FakeFileSystem upgrade = _FakeFileSystem()
    ..put(_storePath, TerminalNoteStoreTransactionEngine.currentLeaf, newer)
    ..put(
      _storePath,
      TerminalNoteStoreTransactionEngine.backupLeaf,
      codec.encode(base),
    );
  final TerminalNoteStoreTransactionEngine upgradeEngine = _open(upgrade);
  final TerminalNoteStoreResult upgradeResult = upgradeEngine.load();
  _expect(
    upgradeResult.disposition == TerminalNoteStoreDisposition.upgradeRequired &&
        upgradeResult.failure == TerminalNoteStoreFailure.upgradeRequired,
    'newer current never falls back to an older readable backup',
  );
  upgradeEngine.stop();
}

void _testOrdinaryCommitFaultMatrix() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteStoreDocument base = _baseDocument();
  final TerminalNoteStoreDocument edited = _editedDocument(base);

  final _FakeFileSystem reference = _fileSystemWithCurrent(base);
  final TerminalNoteStoreTransactionEngine referenceEngine = _open(reference);
  _expect(referenceEngine.load().isSuccess, 'reference store loads');
  reference.resetTrace();
  _expect(
    referenceEngine.commitCandidate(edited).isSuccess,
    'reference ordinary commit succeeds',
  );
  final List<String> operations = List<String>.of(reference.operations);
  referenceEngine.stop();
  _expect(
    operations.any((String value) => value.startsWith('write:')) &&
        operations.any((String value) => value.startsWith('fileSync:')) &&
        operations.any((String value) => value.startsWith('rename:')) &&
        operations.any((String value) => value == 'directorySync'),
    'fault matrix covers write, file fsync, rename, and directory fsync',
  );

  for (var index = 0; index < operations.length; index++) {
    final _FakeFileSystem fileSystem = _fileSystemWithCurrent(base);
    final TerminalNoteStoreTransactionEngine engine = _open(fileSystem);
    _expect(engine.load().isSuccess, 'fault fixture loads');
    fileSystem.resetTrace(failAt: index);
    final TerminalNoteStoreResult result = engine.commitCandidate(edited);
    _expect(!result.isSuccess, 'filesystem fault rejects ordinary commit');
    engine.stop();
    fileSystem.disableFailure();

    final TerminalNoteStoreTransactionEngine verifier = _open(fileSystem);
    final TerminalNoteStoreResult loaded = verifier.load();
    _expect(
      loaded.disposition == TerminalNoteStoreDisposition.loaded ||
          loaded.disposition == TerminalNoteStoreDisposition.recoveryPreview,
      'ordinary fault leaves a readable current or backup',
    );
    final Uint8List actual = codec.encode(loaded.document!);
    _expect(
      _bytesEqual(actual, codec.encode(base)) ||
          _bytesEqual(actual, codec.encode(edited)),
      'ordinary fault exposes only the old or new complete document',
    );
    verifier.stop();
  }
}

void _testDeletionCrashMatrix() {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteStoreDocument base = _baseDocument();
  final NoteId deletedId = _noteId(1);
  final TerminalNoteStoreDocument deleted = _deletedDocument(base, deletedId);
  final TerminalNoteDeletionTombstone tombstone = TerminalNoteDeletionTombstone(
    noteId: deletedId,
    deletionRevision: deleted.snapshot.storeRevision,
  );

  final _FakeFileSystem missingIntent = _fileSystemWithCurrent(base);
  final TerminalNoteStoreTransactionEngine missingIntentEngine = _open(
    missingIntent,
  );
  _expect(missingIntentEngine.load().isSuccess, 'deletion guard store loads');
  missingIntent.resetTrace();
  final TerminalNoteStoreResult missingIntentResult = missingIntentEngine
      .commitCandidate(deleted);
  _expect(
    missingIntentResult.failure ==
            TerminalNoteStoreFailure.invariantViolation &&
        missingIntent.mutationOperations.isEmpty,
    'a removed Note cannot commit without an exact deletion tombstone',
  );
  missingIntentEngine.stop();

  final _FakeFileSystem reference = _fileSystemWithCurrent(base);
  final TerminalNoteStoreTransactionEngine referenceEngine = _open(reference);
  _expect(referenceEngine.load().isSuccess, 'deletion reference store loads');
  reference.resetTrace();
  _expect(
    referenceEngine
        .commitCandidate(
          deleted,
          deletions: <TerminalNoteDeletionTombstone>[tombstone],
        )
        .isSuccess,
    'reference deletion commits',
  );
  final List<String> operations = List<String>.of(reference.operations);
  referenceEngine.stop();
  _expect(
    reference.file(
          _storePath,
          TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
        ) ==
        null,
    'verified current and backup allow journal compaction',
  );
  for (final String leaf in <String>[
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
  ]) {
    final Uint8List? bytes = reference.file(_storePath, leaf);
    _expect(
      bytes != null && codec.decode(bytes).snapshot.noteFor(deletedId) == null,
      'successful deletion removes the Note from both durable copies',
    );
  }

  for (var index = 0; index < operations.length; index++) {
    final _FakeFileSystem fileSystem = _fileSystemWithCurrent(base);
    final TerminalNoteStoreTransactionEngine engine = _open(fileSystem);
    _expect(engine.load().isSuccess, 'deletion fault fixture loads');
    fileSystem.resetTrace(failAt: index);
    final TerminalNoteStoreResult result = engine.commitCandidate(
      deleted,
      deletions: <TerminalNoteDeletionTombstone>[tombstone],
    );
    _expect(!result.isSuccess, 'filesystem fault rejects deletion commit');
    final bool durableIntentStarted = fileSystem.directorySyncSnapshots.any(
      (Set<String> leaves) => leaves.contains(
        TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
      ),
    );
    engine.stop();
    fileSystem.disableFailure();

    final TerminalNoteStoreTransactionEngine verifier = _open(fileSystem);
    final TerminalNoteStoreResult loaded = verifier.load();
    _expect(
      loaded.disposition == TerminalNoteStoreDisposition.loaded ||
          loaded.disposition == TerminalNoteStoreDisposition.recoveryPreview,
      'deletion fault leaves a readable known-good copy',
    );
    if (durableIntentStarted) {
      _expect(
        loaded.document!.snapshot.noteFor(deletedId) == null,
        'a durable deletion journal prevents resurrection after every later fault',
      );
    }
    verifier.stop();
  }
}

void _testPortableExport() {
  final TerminalNoteStoreDocument base = _baseDocument(withTrigger: true);
  final _FakeFileSystem fileSystem = _fileSystemWithCurrent(base)
    ..ensureDirectory('/private/tmp/exports');
  final TerminalNoteStoreTransactionEngine engine = _open(fileSystem);
  _expect(engine.load().isSuccess, 'export fixture loads');

  final int beforeCancel = fileSystem.operations.length;
  final TerminalNoteStoreResult cancelled = engine.exportToApprovedPath(null);
  _expect(
    cancelled.disposition == TerminalNoteStoreDisposition.cancelled &&
        cancelled.failure == TerminalNoteStoreFailure.exportCancelled &&
        fileSystem.operations.length == beforeCancel,
    'save-panel cancellation performs no encoding or filesystem operation',
  );

  final TerminalNoteApprovedExportPath destination =
      TerminalNoteApprovedExportPath.fromAbsolutePath(
        '/private/tmp/exports/メモ共有.json',
      );
  _expect(
    !destination.toString().contains('メモ共有'),
    'approved destination formatting redacts the path',
  );
  final TerminalNoteStoreResult exported = engine.exportToApprovedPath(
    destination,
  );
  _expect(exported.isSuccess, 'safe UTF-8 export filename succeeds');
  final Uint8List exportBytes = fileSystem.file(
    '/private/tmp/exports',
    'メモ共有.json',
  )!;
  final Map<String, dynamic> root =
      jsonDecode(utf8.decode(exportBytes).trim()) as Map<String, dynamic>;
  _expect(
    root.keys.join(',') == 'format,version,notes' &&
        root['format'] == TerminalNotePortableExportCodec.format &&
        root['version'] == TerminalNotePortableExportCodec.version,
    'portable export has the fixed envelope only',
  );
  final List<dynamic> notes = root['notes'] as List<dynamic>;
  _expect(notes.length == 2, 'portable export contains both Notes');
  for (final dynamic value in notes) {
    final Map<String, dynamic> note = value as Map<String, dynamic>;
    _expect(
      note.keys.join(',') == 'body,color,status,order,trigger',
      'portable record omits identity, timestamp, revision, and context',
    );
  }
  _expect(
    notes.any(
      (dynamic value) =>
          (value as Map<String, dynamic>)['trigger'] == 'onReturn',
    ),
    'portable export preserves trigger intent',
  );
  final _OpenCall exportOpen = fileSystem.openCalls.last;
  _expect(
    !exportOpen.create && !exportOpen.narrowDirectoryPermissions,
    'export never creates or chmods the save-panel selected parent',
  );

  final Uint8List original = Uint8List.fromList(<int>[9, 8, 7]);
  fileSystem.put('/private/tmp/exports', 'existing.json', original);
  fileSystem.failNext('rename:', TerminalNoteStoreFailure.renameFailed);
  final TerminalNoteStoreResult failed = engine.exportToApprovedPath(
    TerminalNoteApprovedExportPath.fromAbsolutePath(
      '/private/tmp/exports/existing.json',
    ),
  );
  _expect(
    failed.failure == TerminalNoteStoreFailure.renameFailed &&
        _bytesEqual(
          fileSystem.file('/private/tmp/exports', 'existing.json')!,
          original,
        ) &&
        !fileSystem
            .leaves('/private/tmp/exports')
            .any((String leaf) => leaf.endsWith('.pending')),
    'failed export preserves the destination and removes its owned pending file',
  );
  engine.stop();
}

void _testPrivacyAndGenericPackageBoundary() {
  const String bodySentinel = 'PRIVATE-WORKER-BODY-SENTINEL';
  const String pathSentinel = '/private/secret/store';
  const String idSentinel = 'deadbeefdeadbeefdeadbeefdeadbeef';
  final TerminalNoteStoreException exception = TerminalNoteStoreException(
    TerminalNoteStoreFailure.writeFailed,
  );
  final String result = TerminalNoteStoreResult(
    disposition: TerminalNoteStoreDisposition.unavailable,
    failure: TerminalNoteStoreFailure.writeFailed,
    storeRevision: BigInt.zero,
    metrics: TerminalNoteStoreMetrics.zero,
  ).toString();
  for (final String sentinel in <String>[
    bodySentinel,
    pathSentinel,
    idSentinel,
    'yellow',
    'onReturn',
  ]) {
    _expect(
      !exception.toString().contains(sentinel) && !result.contains(sentinel),
      'store errors and results do not expose private payloads',
    );
  }

  final List<FileSystemEntity> genericSources = <FileSystemEntity>[
    ...Directory('packages/dart_durable_file_macos/lib')
        .listSync(recursive: true),
    ...Directory('packages/dart_durable_file_macos/native')
        .listSync(recursive: true),
  ];
  for (final FileSystemEntity entity in genericSources) {
    if (entity is! File ||
        !(entity.path.endsWith('.dart') || entity.path.endsWith('.c'))) {
      continue;
    }
    final String source = entity.readAsStringSync().toLowerCase();
    for (final String forbidden in <String>[
      'dart_terminal',
      'terminalnote',
      'dart_appkit',
      'dart_pty',
      'appkit',
    ]) {
      _expect(
        !source.contains(forbidden),
        'generic durable-file source does not contain $forbidden',
      );
    }
  }
}

const String _storePath = '/private/tmp/note-store';

TerminalNoteStoreTransactionEngine _open(_FakeFileSystem fileSystem) =>
    TerminalNoteStoreTransactionEngine.open(
      location: TerminalNoteStoreLocation.fromAbsolutePath(_storePath),
      fileSystem: fileSystem,
    );

_FakeFileSystem _fileSystemWithCurrent(TerminalNoteStoreDocument document) =>
    _FakeFileSystem()..put(
      _storePath,
      TerminalNoteStoreTransactionEngine.currentLeaf,
      const TerminalNoteStoreCodec().encode(document),
    );

TerminalNoteStoreDocument _baseDocument({bool withTrigger = false}) {
  final TerminalNoteContextId contextId = _contextId(1);
  final NoteId first = _noteId(1);
  final NoteId second = _noteId(2);
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: contextId,
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.createNote(
      id: first,
      contextId: contextId,
      body: 'private first body',
      color: NoteColorKey.yellow,
      utcMicros: 10,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.createNote(
      id: second,
      contextId: contextId,
      body: '二番目のメモ',
      color: NoteColorKey.blue,
      utcMicros: 20,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  if (withTrigger) {
    snapshot = _accept(
      snapshot.armOnReturn(
        noteId: first,
        isEligible: false,
        expectedStoreRevision: snapshot.storeRevision,
        expectedNoteRevision: snapshot.noteFor(first)!.revision,
      ),
    );
  }
  return TerminalNoteStoreDocument(snapshot: snapshot);
}

TerminalNoteStoreDocument _editedDocument(TerminalNoteStoreDocument source) {
  final NoteId id = _noteId(2);
  return TerminalNoteStoreDocument(
    snapshot: _accept(
      source.snapshot.editNote(
        noteId: id,
        body: 'edited complete body',
        color: NoteColorKey.green,
        updatedAtUtcMicros: 30,
        expectedStoreRevision: source.snapshot.storeRevision,
        expectedNoteRevision: source.snapshot.noteFor(id)!.revision,
      ),
    ),
  );
}

TerminalNoteStoreDocument _deletedDocument(
  TerminalNoteStoreDocument source,
  NoteId id,
) => TerminalNoteStoreDocument(
  snapshot: _accept(
    source.snapshot.deleteNote(
      noteId: id,
      updatedAtUtcMicros: 40,
      expectedStoreRevision: source.snapshot.storeRevision,
      expectedNoteRevision: source.snapshot.noteFor(id)!.revision,
    ),
  ),
);

TerminalNoteSnapshot _accept(TerminalNoteMutationResult result) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.accepted,
    'fixture mutation is accepted',
  );
  return result.snapshot;
}

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalNoteContextId _contextId(int value) => TerminalNoteContextId.fromHex(
  (0x100000 + value).toRadixString(16).padLeft(32, '0'),
);

bool _sameDocument(
  TerminalNoteStoreDocument left,
  TerminalNoteStoreDocument right,
) => _bytesEqual(
  const TerminalNoteStoreCodec().encode(left),
  const TerminalNoteStoreCodec().encode(right),
);

void _expectDocumentBytes(
  Uint8List? actual,
  Uint8List expected,
  String description,
) => _expect(actual != null && _bytesEqual(actual, expected), description);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expectThrowsStore(
  void Function() callback,
  TerminalNoteStoreFailure failure,
  String description,
) {
  try {
    callback();
  } on TerminalNoteStoreException catch (error) {
    _expect(error.failure == failure, description);
    return;
  }
  throw StateError('expected TerminalNoteStoreException: $description');
}

void _expect(bool value, String description) {
  if (!value) throw StateError(description);
}

final class _OpenCall {
  const _OpenCall({
    required this.path,
    required this.create,
    required this.directoryPermissionBits,
    required this.narrowDirectoryPermissions,
  });

  final String path;
  final bool create;
  final int directoryPermissionBits;
  final bool narrowDirectoryPermissions;
}

final class _FakeDirectory {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  var lockHolders = 0;
}

final class _FakeFileSystem implements TerminalNoteStoreFileSystem {
  final Map<String, _FakeDirectory> _directories = <String, _FakeDirectory>{};
  final List<String> operations = <String>[];
  final List<_OpenCall> openCalls = <_OpenCall>[];
  final List<Set<String>> directorySyncSnapshots = <Set<String>>[];
  int? _failureIndex;
  String? _failurePrefix;
  TerminalNoteStoreFailure? _failure;
  var _failureFired = false;
  var activeSessions = 0;

  Iterable<String> get mutationOperations => operations.where(
    (String value) =>
        value.startsWith('write:') ||
        value.startsWith('fileSync:') ||
        value.startsWith('rename:') ||
        value.startsWith('unlink:') ||
        value == 'directorySync',
  );

  void ensureDirectory(String path) {
    _directories.putIfAbsent(path, _FakeDirectory.new);
  }

  void put(String path, String leaf, List<int> bytes) {
    ensureDirectory(path);
    _directories[path]!.files[leaf] = Uint8List.fromList(bytes);
  }

  Uint8List? file(String path, String leaf) {
    final Uint8List? bytes = _directories[path]?.files[leaf];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  Iterable<String> leaves(String path) =>
      _directories[path]?.files.keys ?? const <String>[];

  void resetTrace({int? failAt}) {
    operations.clear();
    directorySyncSnapshots.clear();
    _failureIndex = failAt;
    _failurePrefix = null;
    _failure = null;
    _failureFired = false;
  }

  void failNext(String prefix, TerminalNoteStoreFailure failure) {
    _failureIndex = null;
    _failurePrefix = prefix;
    _failure = failure;
    _failureFired = false;
  }

  void disableFailure() {
    _failureIndex = null;
    _failurePrefix = null;
    _failure = null;
    _failureFired = false;
  }

  void step(String operation, TerminalNoteStoreFailure defaultFailure) {
    final int index = operations.length;
    operations.add(operation);
    final bool selected =
        !_failureFired &&
        ((_failureIndex != null && index == _failureIndex) ||
            (_failurePrefix != null && operation.startsWith(_failurePrefix!)));
    if (!selected) return;
    _failureFired = true;
    throw TerminalNoteStoreException(_failure ?? defaultFailure);
  }

  @override
  TerminalNoteStoreFileSession openDirectory(
    String absolutePath, {
    required bool create,
    required int directoryPermissionBits,
    required bool narrowDirectoryPermissions,
  }) {
    step('open', TerminalNoteStoreFailure.permissionDenied);
    openCalls.add(
      _OpenCall(
        path: absolutePath,
        create: create,
        directoryPermissionBits: directoryPermissionBits,
        narrowDirectoryPermissions: narrowDirectoryPermissions,
      ),
    );
    if (create) ensureDirectory(absolutePath);
    final _FakeDirectory? directory = _directories[absolutePath];
    if (directory == null) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.invalidLocation,
      );
    }
    activeSessions++;
    return _FakeSession(this, directory);
  }
}

final class _FakeSession implements TerminalNoteStoreFileSession {
  _FakeSession(this._fileSystem, this._directory);

  final _FakeFileSystem _fileSystem;
  final _FakeDirectory _directory;
  var _closed = false;
  var _ownsLock = false;

  void _ensureOpen() {
    if (_closed) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.invalidState,
      );
    }
  }

  @override
  void acquireExclusiveLock(String leafName) {
    _ensureOpen();
    _fileSystem.step('lock:$leafName', TerminalNoteStoreFailure.lockBusy);
    if (_directory.lockHolders != 0) {
      throw const TerminalNoteStoreException(TerminalNoteStoreFailure.lockBusy);
    }
    _directory.lockHolders++;
    _ownsLock = true;
    _directory.files.putIfAbsent(leafName, () => Uint8List(0));
  }

  @override
  TerminalNoteStoreFileInfo inspect(String leafName) {
    _ensureOpen();
    _fileSystem.step('inspect:$leafName', TerminalNoteStoreFailure.readFailed);
    final Uint8List? bytes = _directory.files[leafName];
    return TerminalNoteStoreFileInfo(
      exists: bytes != null,
      length: bytes?.length ?? 0,
    );
  }

  @override
  Uint8List read(String leafName, {required int maximumBytes}) {
    _ensureOpen();
    _fileSystem.step('read:$leafName', TerminalNoteStoreFailure.readFailed);
    final Uint8List? bytes = _directory.files[leafName];
    if (bytes == null) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.readFailed,
      );
    }
    if (bytes.length > maximumBytes) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.resourceLimit,
      );
    }
    return Uint8List.fromList(bytes);
  }

  @override
  void writeExclusive(String leafName, List<int> bytes) {
    _ensureOpen();
    _fileSystem.step('write:$leafName', TerminalNoteStoreFailure.writeFailed);
    if (_directory.files.containsKey(leafName)) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.writeFailed,
      );
    }
    _directory.files[leafName] = Uint8List.fromList(bytes);
    _fileSystem.step(
      'fileSync:$leafName',
      TerminalNoteStoreFailure.fileSyncFailed,
    );
  }

  @override
  void rename(String sourceLeaf, String destinationLeaf) {
    _ensureOpen();
    _fileSystem.step(
      'rename:$sourceLeaf>$destinationLeaf',
      TerminalNoteStoreFailure.renameFailed,
    );
    final Uint8List? source = _directory.files.remove(sourceLeaf);
    if (source == null) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.renameFailed,
      );
    }
    _directory.files[destinationLeaf] = source;
  }

  @override
  void unlink(String leafName, {bool missingOkay = false}) {
    _ensureOpen();
    _fileSystem.step('unlink:$leafName', TerminalNoteStoreFailure.unlinkFailed);
    if (_directory.files.remove(leafName) == null && !missingOkay) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.unlinkFailed,
      );
    }
  }

  @override
  void flushDirectory() {
    _ensureOpen();
    _fileSystem.directorySyncSnapshots.add(
      Set<String>.of(_directory.files.keys),
    );
    _fileSystem.step(
      'directorySync',
      TerminalNoteStoreFailure.directorySyncFailed,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _fileSystem.step('close', TerminalNoteStoreFailure.invalidState);
    _closed = true;
    if (_ownsLock) _directory.lockHolders--;
    _fileSystem.activeSessions--;
  }
}
