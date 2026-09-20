import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_durable_file_macos/dart_durable_file_macos.dart';

import 'terminal_note_model.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_sha256.dart';

abstract final class TerminalNoteStoreWorkerLimits {
  static const int protocolVersion = 1;
  static const int maximumPendingIntents = 32;
  static const int maximumPendingBodyBytes = 128 * 1024;
  static const Duration loadTimeout = Duration(seconds: 3);
  static const Duration stopTimeout = Duration(seconds: 1);
}

enum TerminalNoteStoreFailure {
  invalidLocation,
  lockBusy,
  permissionDenied,
  unsafeFile,
  resourceLimit,
  readFailed,
  writeFailed,
  fileSyncFailed,
  renameFailed,
  unlinkFailed,
  directorySyncFailed,
  codecRejected,
  upgradeRequired,
  recoveryRequired,
  revisionConflict,
  invariantViolation,
  exportCancelled,
  invalidState,
  protocolViolation,
  timeout,
  workerCrashed,
  busy,
  unknown,
}

/// Fixed, content-, identity-, time-, and path-free store failure.
final class TerminalNoteStoreException implements Exception {
  const TerminalNoteStoreException(this.failure);

  final TerminalNoteStoreFailure failure;

  @override
  String toString() => 'Terminal note store failed: ${failure.name}';
}

enum TerminalNoteStoreDisposition {
  loaded,
  empty,
  recoveryPreview,
  recoveryRequired,
  committed,
  exported,
  cancelled,
  stopped,
  unavailable,
  upgradeRequired,
  rejected,
}

final class TerminalNoteStoreMetrics {
  const TerminalNoteStoreMetrics({
    required this.noteCount,
    required this.activeCount,
    required this.dueCount,
    required this.detachedCount,
    required this.canonicalBytes,
  });

  static const TerminalNoteStoreMetrics zero = TerminalNoteStoreMetrics(
    noteCount: 0,
    activeCount: 0,
    dueCount: 0,
    detachedCount: 0,
    canonicalBytes: 0,
  );

  final int noteCount;
  final int activeCount;
  final int dueCount;
  final int detachedCount;
  final int canonicalBytes;
}

/// One content-free operation result. Only load/recovery may carry a document.
final class TerminalNoteStoreResult {
  const TerminalNoteStoreResult({
    required this.disposition,
    required this.failure,
    required this.storeRevision,
    required this.metrics,
    this.document,
  });

  final TerminalNoteStoreDisposition disposition;
  final TerminalNoteStoreFailure? failure;
  final BigInt storeRevision;
  final TerminalNoteStoreMetrics metrics;
  final TerminalNoteStoreDocument? document;

  bool get isSuccess => switch (disposition) {
    TerminalNoteStoreDisposition.loaded ||
    TerminalNoteStoreDisposition.empty ||
    TerminalNoteStoreDisposition.committed ||
    TerminalNoteStoreDisposition.exported ||
    TerminalNoteStoreDisposition.stopped => true,
    _ => false,
  };

  @override
  String toString() => failure == null
      ? 'TerminalNoteStoreResult(${disposition.name})'
      : 'TerminalNoteStoreResult(${disposition.name}, ${failure!.name})';
}

/// Validated product store location. String formatting is always redacted.
final class TerminalNoteStoreLocation {
  factory TerminalNoteStoreLocation.fromAbsolutePath(String path) {
    final String normalized = _normalizeAbsolutePath(path);
    return TerminalNoteStoreLocation._(normalized);
  }

  const TerminalNoteStoreLocation._(this._canonicalPath);

  final String _canonicalPath;

  /// Explicit filesystem adapter boundary. Do not use for diagnostics.
  String get canonicalPath => _canonicalPath;

  static TerminalNoteStoreLocation fromEnvironment(
    Map<String, String> environment,
  ) {
    final String? xdg = environment['XDG_STATE_HOME'];
    if (xdg != null && _isSafeAbsolutePath(xdg)) {
      return TerminalNoteStoreLocation.fromAbsolutePath(
        '$xdg/dart-terminal/notes',
      );
    }
    final String? home = environment['HOME'];
    if (home == null || !_isSafeAbsolutePath(home)) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.invalidLocation,
      );
    }
    return TerminalNoteStoreLocation.fromAbsolutePath(
      '$home/Library/Application Support/Dart Terminal/Notes',
    );
  }

  @override
  String toString() => 'TerminalNoteStoreLocation(<redacted>)';
}

/// Save-panel approved absolute destination, redacted outside the I/O adapter.
final class TerminalNoteApprovedExportPath {
  factory TerminalNoteApprovedExportPath.fromAbsolutePath(String path) {
    final String normalized = _normalizeAbsolutePath(path);
    final int separator = normalized.lastIndexOf('/');
    if (separator <= 0 || separator == normalized.length - 1) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.invalidLocation,
      );
    }
    final String leaf = normalized.substring(separator + 1);
    if (!_isSafeLeaf(leaf)) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.invalidLocation,
      );
    }
    return TerminalNoteApprovedExportPath._(
      normalized,
      normalized.substring(0, separator),
      leaf,
    );
  }

  const TerminalNoteApprovedExportPath._(
    this._canonicalPath,
    this._parentDirectory,
    this._leafName,
  );

  final String _canonicalPath;
  final String _parentDirectory;
  final String _leafName;

  /// Explicit filesystem adapter boundaries. Do not use for diagnostics.
  String get canonicalPath => _canonicalPath;
  String get parentDirectory => _parentDirectory;
  String get leafName => _leafName;

  @override
  String toString() => 'TerminalNoteApprovedExportPath(<redacted>)';
}

final class TerminalNoteStoreFileInfo {
  const TerminalNoteStoreFileInfo({required this.exists, required this.length});

  final bool exists;
  final int length;
}

abstract interface class TerminalNoteStoreFileSession {
  void acquireExclusiveLock(String leafName);
  TerminalNoteStoreFileInfo inspect(String leafName);
  Uint8List read(String leafName, {required int maximumBytes});
  void writeExclusive(String leafName, List<int> bytes);
  void rename(String sourceLeaf, String destinationLeaf);
  void unlink(String leafName, {bool missingOkay = false});
  void flushDirectory();
  void close();
}

abstract interface class TerminalNoteStoreFileSystem {
  TerminalNoteStoreFileSession openDirectory(
    String absolutePath, {
    required bool create,
    required int directoryPermissionBits,
    required bool narrowDirectoryPermissions,
  });
}

final class LocalTerminalNoteStoreFileSystem
    implements TerminalNoteStoreFileSystem {
  const LocalTerminalNoteStoreFileSystem();

  @override
  TerminalNoteStoreFileSession openDirectory(
    String absolutePath, {
    required bool create,
    required int directoryPermissionBits,
    required bool narrowDirectoryPermissions,
  }) {
    try {
      return _LocalTerminalNoteStoreFileSession(
        MacosDurableDirectorySession.open(
          absolutePath,
          create: create,
          directoryPermissionBits: directoryPermissionBits,
          narrowDirectoryPermissions: narrowDirectoryPermissions,
        ),
      );
    } on MacosDurableFileException catch (error) {
      throw TerminalNoteStoreException(_mapNativeFailure(error.failure));
    }
  }
}

final class _LocalTerminalNoteStoreFileSession
    implements TerminalNoteStoreFileSession {
  const _LocalTerminalNoteStoreFileSession(this._session);

  final MacosDurableDirectorySession _session;

  @override
  void acquireExclusiveLock(String leafName) =>
      _call(() => _session.acquireExclusiveLock(leafName));

  @override
  TerminalNoteStoreFileInfo inspect(String leafName) => _call(() {
    final MacosDurableFileInfo result = _session.inspect(leafName);
    return TerminalNoteStoreFileInfo(
      exists: result.exists,
      length: result.length,
    );
  });

  @override
  Uint8List read(String leafName, {required int maximumBytes}) =>
      _call(() => _session.read(leafName, maximumBytes: maximumBytes));

  @override
  void writeExclusive(String leafName, List<int> bytes) =>
      _call(() => _session.writeExclusive(leafName, bytes));

  @override
  void rename(String sourceLeaf, String destinationLeaf) =>
      _call(() => _session.rename(sourceLeaf, destinationLeaf));

  @override
  void unlink(String leafName, {bool missingOkay = false}) =>
      _call(() => _session.unlink(leafName, missingOkay: missingOkay));

  @override
  void flushDirectory() => _call(_session.flushDirectory);

  @override
  void close() => _call(_session.close);

  static T _call<T>(T Function() callback) {
    try {
      return callback();
    } on MacosDurableFileException catch (error) {
      throw TerminalNoteStoreException(_mapNativeFailure(error.failure));
    }
  }
}

TerminalNoteStoreFailure _mapNativeFailure(
  MacosDurableFileFailure failure,
) => switch (failure) {
  MacosDurableFileFailure.invalidArgument =>
    TerminalNoteStoreFailure.invalidLocation,
  MacosDurableFileFailure.busy => TerminalNoteStoreFailure.lockBusy,
  MacosDurableFileFailure.permissionDenied ||
  MacosDurableFileFailure.wrongOwner =>
    TerminalNoteStoreFailure.permissionDenied,
  MacosDurableFileFailure.unsafeType ||
  MacosDurableFileFailure.hardLink => TerminalNoteStoreFailure.unsafeFile,
  MacosDurableFileFailure.tooLarge || MacosDurableFileFailure.resourceLimit =>
    TerminalNoteStoreFailure.resourceLimit,
  MacosDurableFileFailure.notFound ||
  MacosDurableFileFailure.readFailed => TerminalNoteStoreFailure.readFailed,
  MacosDurableFileFailure.alreadyExists ||
  MacosDurableFileFailure.writeFailed => TerminalNoteStoreFailure.writeFailed,
  MacosDurableFileFailure.fileSyncFailed =>
    TerminalNoteStoreFailure.fileSyncFailed,
  MacosDurableFileFailure.renameFailed => TerminalNoteStoreFailure.renameFailed,
  MacosDurableFileFailure.unlinkFailed => TerminalNoteStoreFailure.unlinkFailed,
  MacosDurableFileFailure.directorySyncFailed =>
    TerminalNoteStoreFailure.directorySyncFailed,
  MacosDurableFileFailure.invalidState => TerminalNoteStoreFailure.invalidState,
  MacosDurableFileFailure.unsupported ||
  MacosDurableFileFailure.unknown => TerminalNoteStoreFailure.unknown,
};

/// Canonical, portable, write-only export. Import is intentionally absent.
final class TerminalNotePortableExportCodec {
  const TerminalNotePortableExportCodec();

  static const String format = 'dart-terminal-notes-export';
  static const int version = 1;

  Uint8List encode(TerminalNoteStoreDocument document) {
    final List<NoteRecord> notes = document.snapshot.notes.values.toList()
      ..sort((NoteRecord left, NoteRecord right) {
        var order = left.order.compareTo(right.order);
        if (order != 0) return order;
        order = left.body.value.compareTo(right.body.value);
        if (order != 0) return order;
        order = left.color.index.compareTo(right.color.index);
        if (order != 0) return order;
        order = left.status.index.compareTo(right.status.index);
        if (order != 0) return order;
        return _portableTrigger(
          document,
          left.id,
        ).compareTo(_portableTrigger(document, right.id));
      });
    final String source = jsonEncode(<String, Object?>{
      'format': format,
      'version': version,
      'notes': <Object?>[
        for (final NoteRecord note in notes)
          <String, Object?>{
            'body': note.body.value,
            'color': _portableColor(note.color),
            'status': note.status == NoteStatus.active ? 'active' : 'resolved',
            'order': note.order,
            'trigger': _portableTrigger(document, note.id),
          },
      ],
    });
    final Uint8List result = Uint8List.fromList(utf8.encode('$source\n'));
    if (result.length > TerminalNoteStoreCodecLimits.maximumFileBytes) {
      throw const TerminalNoteStoreException(
        TerminalNoteStoreFailure.resourceLimit,
      );
    }
    return result;
  }

  static String _portableTrigger(
    TerminalNoteStoreDocument document,
    NoteId noteId,
  ) => switch (document.snapshot.triggerFor(noteId)?.kind) {
    NoteTriggerKind.onReturn => 'onReturn',
    NoteTriggerKind.atNextPrompt => 'atNextPrompt',
    null => 'passive',
  };

  static String _portableColor(NoteColorKey color) => switch (color) {
    NoteColorKey.neutral => 'neutral',
    NoteColorKey.yellow => 'yellow',
    NoteColorKey.blue => 'blue',
    NoteColorKey.green => 'green',
    NoteColorKey.pink => 'pink',
    NoteColorKey.purple => 'purple',
  };
}

enum _TerminalNoteEngineState {
  uninitialized,
  ready,
  recoveryPreview,
  recoveryRequired,
  closed,
}

/// Synchronous worker-side transaction engine. A later client owns its isolate.
final class TerminalNoteStoreTransactionEngine {
  factory TerminalNoteStoreTransactionEngine.open({
    required TerminalNoteStoreLocation location,
    TerminalNoteStoreFileSystem fileSystem =
        const LocalTerminalNoteStoreFileSystem(),
    TerminalNoteStoreCodec codec = const TerminalNoteStoreCodec(),
    TerminalNotePortableExportCodec exportCodec =
        const TerminalNotePortableExportCodec(),
  }) {
    TerminalNoteStoreFileSession? session;
    try {
      session = fileSystem.openDirectory(
        location.canonicalPath,
        create: true,
        directoryPermissionBits: 0x1c0,
        narrowDirectoryPermissions: true,
      );
      session.acquireExclusiveLock(lockLeaf);
    } on TerminalNoteStoreException {
      try {
        session?.close();
      } on Object {
        // Preserve the fixed primary failure.
      }
      rethrow;
    } on Object {
      try {
        session?.close();
      } on Object {
        // Preserve the fixed primary failure.
      }
      throw const TerminalNoteStoreException(TerminalNoteStoreFailure.unknown);
    }
    return TerminalNoteStoreTransactionEngine._(
      location: location,
      fileSystem: fileSystem,
      session: session,
      codec: codec,
      exportCodec: exportCodec,
    );
  }

  TerminalNoteStoreTransactionEngine._({
    required this.location,
    required TerminalNoteStoreFileSystem fileSystem,
    required TerminalNoteStoreFileSession session,
    required TerminalNoteStoreCodec codec,
    required TerminalNotePortableExportCodec exportCodec,
  }) : _fileSystem = fileSystem,
       _session = session,
       _codec = codec,
       _exportCodec = exportCodec;

  static const String currentLeaf = 'store.json';
  static const String backupLeaf = 'store.backup.json';
  static const String deletionJournalLeaf = 'deletions.json';
  static const String lockLeaf = 'store.lock';
  static const String _storePendingLeaf = 'store.pending';
  static const String _backupPendingLeaf = 'backup.pending';
  static const String _deletionsPendingLeaf = 'deletions.pending';
  static const String _recoveryPendingLeaf = 'recovery.pending';

  final TerminalNoteStoreLocation location;
  final TerminalNoteStoreFileSystem _fileSystem;
  final TerminalNoteStoreFileSession _session;
  final TerminalNoteStoreCodec _codec;
  final TerminalNotePortableExportCodec _exportCodec;
  _TerminalNoteEngineState _state = _TerminalNoteEngineState.uninitialized;
  TerminalNoteStoreDocument? _loaded;
  TerminalNoteDeletionJournal _journal = TerminalNoteDeletionJournal(
    entries: const <TerminalNoteDeletionTombstone>[],
  );

  TerminalNoteStoreResult load() {
    if (_state == _TerminalNoteEngineState.closed) {
      return _failureResult(TerminalNoteStoreFailure.invalidState);
    }
    return _loadFromDisk();
  }

  TerminalNoteStoreResult commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) {
    if (_state != _TerminalNoteEngineState.ready || _loaded == null) {
      return _failureResult(TerminalNoteStoreFailure.invalidState);
    }
    final TerminalNoteStoreDocument previous = _loaded!;
    final List<TerminalNoteDeletionTombstone> requested = deletions.toList();
    try {
      final Uint8List candidateBytes = _codec.encode(candidate);
      if (candidate.snapshot.storeRevision <= previous.snapshot.storeRevision) {
        return _failureResult(TerminalNoteStoreFailure.revisionConflict);
      }
      final Map<NoteId, TerminalNoteDeletionTombstone> merged =
          <NoteId, TerminalNoteDeletionTombstone>{
            for (final TerminalNoteDeletionTombstone entry in _journal.entries)
              entry.noteId: entry,
          };
      final Set<NoteId> removed = previous.snapshot.notes.keys
          .where((NoteId id) => candidate.snapshot.noteFor(id) == null)
          .toSet();
      final Set<NoteId> requestedIds = requested
          .map((TerminalNoteDeletionTombstone entry) => entry.noteId)
          .toSet();
      if (requestedIds.length != requested.length ||
          requestedIds.length != removed.length ||
          !requestedIds.containsAll(removed)) {
        return _failureResult(TerminalNoteStoreFailure.invariantViolation);
      }
      for (final TerminalNoteDeletionTombstone deletion in requested) {
        if (previous.snapshot.noteFor(deletion.noteId) == null ||
            candidate.snapshot.noteFor(deletion.noteId) != null ||
            deletion.deletionRevision <= previous.snapshot.storeRevision ||
            deletion.deletionRevision > candidate.snapshot.storeRevision) {
          return _failureResult(TerminalNoteStoreFailure.invariantViolation);
        }
        merged[deletion.noteId] = deletion;
      }
      for (final NoteId id in merged.keys) {
        if (candidate.snapshot.noteFor(id) != null) {
          return _failureResult(TerminalNoteStoreFailure.invariantViolation);
        }
      }
      final TerminalNoteDeletionJournal nextJournal =
          TerminalNoteDeletionJournal(entries: merged.values);
      if (nextJournal.entries.isNotEmpty) {
        _replaceLeaf(
          bytes: _codec.encodeDeletionJournal(nextJournal),
          pendingLeaf: _deletionsPendingLeaf,
          targetLeaf: deletionJournalLeaf,
        );
      }
      _commitCurrent(candidateBytes);
      if (nextJournal.entries.isNotEmpty) {
        _replaceLeaf(
          bytes: candidateBytes,
          pendingLeaf: _backupPendingLeaf,
          targetLeaf: backupLeaf,
        );
        if (!_bothCopiesCover(nextJournal)) {
          throw const TerminalNoteStoreException(
            TerminalNoteStoreFailure.recoveryRequired,
          );
        }
        _session.unlink(deletionJournalLeaf, missingOkay: true);
        _session.flushDirectory();
      }
      final TerminalNoteStoreDocument committed = _codec.decode(candidateBytes);
      _loaded = committed;
      _journal = TerminalNoteDeletionJournal(
        entries: const <TerminalNoteDeletionTombstone>[],
      );
      _state = _TerminalNoteEngineState.ready;
      return _result(
        TerminalNoteStoreDisposition.committed,
        document: committed,
        exposeDocument: false,
      );
    } on TerminalNoteStoreException catch (error) {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(error.failure);
    } on TerminalNoteCodecException catch (error) {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(_codecFailure(error));
    } on TerminalNoteValidationException {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(TerminalNoteStoreFailure.invariantViolation);
    } on Object {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(TerminalNoteStoreFailure.unknown);
    }
  }

  TerminalNoteStoreResult retryRecovery() {
    if (_state == _TerminalNoteEngineState.closed) {
      return _failureResult(TerminalNoteStoreFailure.invalidState);
    }
    if (_state == _TerminalNoteEngineState.uninitialized) {
      final TerminalNoteStoreResult loaded = _loadFromDisk();
      if (loaded.disposition != TerminalNoteStoreDisposition.recoveryPreview) {
        return loaded;
      }
    }
    if (_state != _TerminalNoteEngineState.recoveryPreview || _loaded == null) {
      return _failureResult(TerminalNoteStoreFailure.recoveryRequired);
    }
    final TerminalNoteStoreDocument preview = _loaded!;
    try {
      final Uint8List bytes = _codec.encode(preview);
      _replaceLeaf(
        bytes: bytes,
        pendingLeaf: _recoveryPendingLeaf,
        targetLeaf: currentLeaf,
      );
      _replaceLeaf(
        bytes: bytes,
        pendingLeaf: _backupPendingLeaf,
        targetLeaf: backupLeaf,
      );
      if (_journal.entries.isNotEmpty) {
        if (!_bothCopiesCover(_journal)) {
          throw const TerminalNoteStoreException(
            TerminalNoteStoreFailure.recoveryRequired,
          );
        }
        _session.unlink(deletionJournalLeaf, missingOkay: true);
        _session.flushDirectory();
      }
      _journal = TerminalNoteDeletionJournal(
        entries: const <TerminalNoteDeletionTombstone>[],
      );
      _state = _TerminalNoteEngineState.ready;
      return _result(
        TerminalNoteStoreDisposition.committed,
        document: preview,
        exposeDocument: false,
      );
    } on TerminalNoteStoreException catch (error) {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(error.failure);
    } on Object {
      _state = _TerminalNoteEngineState.uninitialized;
      return _failureResult(TerminalNoteStoreFailure.unknown);
    }
  }

  TerminalNoteStoreResult exportToApprovedPath(
    TerminalNoteApprovedExportPath? destination,
  ) {
    if (destination == null) {
      return TerminalNoteStoreResult(
        disposition: TerminalNoteStoreDisposition.cancelled,
        failure: TerminalNoteStoreFailure.exportCancelled,
        storeRevision: BigInt.zero,
        metrics: TerminalNoteStoreMetrics.zero,
      );
    }
    if ((_state != _TerminalNoteEngineState.ready &&
            _state != _TerminalNoteEngineState.recoveryPreview) ||
        _loaded == null) {
      return _failureResult(TerminalNoteStoreFailure.invalidState);
    }
    TerminalNoteStoreFileSession? exportSession;
    String? pendingLeaf;
    try {
      final Uint8List bytes = _exportCodec.encode(_loaded!);
      exportSession = _fileSystem.openDirectory(
        destination.parentDirectory,
        create: false,
        directoryPermissionBits: 0x1c0,
        narrowDirectoryPermissions: false,
      );
      pendingLeaf =
          'export-${terminalSha256(utf8.encode(destination.canonicalPath)).substring(0, 32)}.pending';
      _cleanupLeaf(exportSession, pendingLeaf);
      exportSession.writeExclusive(pendingLeaf, bytes);
      exportSession.rename(pendingLeaf, destination.leafName);
      exportSession.flushDirectory();
      return _result(
        TerminalNoteStoreDisposition.exported,
        document: _loaded!,
        exposeDocument: false,
      );
    } on TerminalNoteStoreException catch (error) {
      return _failureResult(error.failure);
    } on Object {
      return _failureResult(TerminalNoteStoreFailure.unknown);
    } finally {
      if (exportSession != null && pendingLeaf != null) {
        _bestEffortCleanup(exportSession, pendingLeaf);
      }
      try {
        exportSession?.close();
      } on Object {
        // The result is already fixed; close errors never expose a path.
      }
    }
  }

  TerminalNoteStoreResult stop() {
    if (_state == _TerminalNoteEngineState.closed) {
      return TerminalNoteStoreResult(
        disposition: TerminalNoteStoreDisposition.stopped,
        failure: null,
        storeRevision: BigInt.zero,
        metrics: TerminalNoteStoreMetrics.zero,
      );
    }
    try {
      _session.close();
    } on TerminalNoteStoreException catch (error) {
      _state = _TerminalNoteEngineState.closed;
      _loaded = null;
      return _failureResult(error.failure);
    }
    _state = _TerminalNoteEngineState.closed;
    _loaded = null;
    return TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.stopped,
      failure: null,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );
  }

  TerminalNoteStoreResult _loadFromDisk() {
    try {
      _cleanupOwnedPendingFiles();
      final _ReadJournal journal = _readJournal();
      if (journal.upgradeRequired) {
        _state = _TerminalNoteEngineState.recoveryRequired;
        return _failureResult(TerminalNoteStoreFailure.upgradeRequired);
      }
      if (journal.invalid) {
        _state = _TerminalNoteEngineState.recoveryRequired;
        return _failureResult(TerminalNoteStoreFailure.recoveryRequired);
      }
      _journal =
          journal.journal ??
          TerminalNoteDeletionJournal(
            entries: const <TerminalNoteDeletionTombstone>[],
          );
      final _ReadStore current = _readStore(currentLeaf);
      final _ReadStore backup = _readStore(backupLeaf);
      if (current.upgradeRequired || backup.upgradeRequired) {
        _state = _TerminalNoteEngineState.recoveryRequired;
        return _failureResult(TerminalNoteStoreFailure.upgradeRequired);
      }
      if (current.document != null) {
        final TerminalNoteStoreDocument loaded = _applyJournal(
          current.document!,
          _journal,
        );
        _loaded = loaded;
        _state = _TerminalNoteEngineState.ready;
        return _result(
          TerminalNoteStoreDisposition.loaded,
          document: loaded,
          exposeDocument: true,
        );
      }
      if (backup.document != null) {
        final TerminalNoteStoreDocument preview = _applyJournal(
          backup.document!,
          _journal,
        );
        _loaded = preview;
        _state = _TerminalNoteEngineState.recoveryPreview;
        return _result(
          TerminalNoteStoreDisposition.recoveryPreview,
          document: preview,
          exposeDocument: true,
          failure: TerminalNoteStoreFailure.recoveryRequired,
        );
      }
      if (current.missing && backup.missing && !journal.existed) {
        final TerminalNoteStoreDocument empty = TerminalNoteStoreDocument(
          snapshot: TerminalNoteSnapshot.empty(),
        );
        _loaded = empty;
        _state = _TerminalNoteEngineState.ready;
        return _result(
          TerminalNoteStoreDisposition.empty,
          document: empty,
          exposeDocument: true,
        );
      }
      _loaded = null;
      _state = _TerminalNoteEngineState.recoveryRequired;
      return _failureResult(TerminalNoteStoreFailure.recoveryRequired);
    } on TerminalNoteStoreException catch (error) {
      _loaded = null;
      _state = _TerminalNoteEngineState.recoveryRequired;
      return _failureResult(error.failure);
    } on Object {
      _loaded = null;
      _state = _TerminalNoteEngineState.recoveryRequired;
      return _failureResult(TerminalNoteStoreFailure.unknown);
    }
  }

  _ReadStore _readStore(String leaf) {
    final TerminalNoteStoreFileInfo info = _session.inspect(leaf);
    if (!info.exists) return const _ReadStore.missing();
    final Uint8List bytes = _session.read(
      leaf,
      maximumBytes: TerminalNoteStoreCodecLimits.maximumFileBytes,
    );
    try {
      return _ReadStore.valid(_codec.decode(bytes));
    } on TerminalNoteCodecException catch (error) {
      return error.requiresUpgrade
          ? const _ReadStore.upgradeRequired()
          : const _ReadStore.invalid();
    }
  }

  _ReadJournal _readJournal() {
    final TerminalNoteStoreFileInfo info = _session.inspect(
      deletionJournalLeaf,
    );
    if (!info.exists) return const _ReadJournal.missing();
    final Uint8List bytes = _session.read(
      deletionJournalLeaf,
      maximumBytes: TerminalNoteStoreCodecLimits.maximumFileBytes,
    );
    try {
      return _ReadJournal.valid(_codec.decodeDeletionJournal(bytes));
    } on TerminalNoteCodecException catch (error) {
      return error.requiresUpgrade
          ? const _ReadJournal.upgradeRequired()
          : const _ReadJournal.invalid();
    }
  }

  void _commitCurrent(Uint8List bytes) {
    _cleanupLeaf(_session, _storePendingLeaf);
    _session.writeExclusive(_storePendingLeaf, bytes);
    try {
      if (_session.inspect(currentLeaf).exists) {
        _session.rename(currentLeaf, backupLeaf);
        _session.flushDirectory();
      }
      _session.rename(_storePendingLeaf, currentLeaf);
      _session.flushDirectory();
    } on Object {
      _bestEffortCleanup(_session, _storePendingLeaf);
      rethrow;
    }
  }

  void _replaceLeaf({
    required List<int> bytes,
    required String pendingLeaf,
    required String targetLeaf,
  }) {
    _cleanupLeaf(_session, pendingLeaf);
    _session.writeExclusive(pendingLeaf, bytes);
    try {
      _session.rename(pendingLeaf, targetLeaf);
      _session.flushDirectory();
    } on Object {
      _bestEffortCleanup(_session, pendingLeaf);
      rethrow;
    }
  }

  bool _bothCopiesCover(TerminalNoteDeletionJournal journal) {
    final _ReadStore current = _readStore(currentLeaf);
    final _ReadStore backup = _readStore(backupLeaf);
    if (current.document == null || backup.document == null) return false;
    for (final TerminalNoteDeletionTombstone entry in journal.entries) {
      if (current.document!.snapshot.storeRevision < entry.deletionRevision ||
          backup.document!.snapshot.storeRevision < entry.deletionRevision ||
          current.document!.snapshot.noteFor(entry.noteId) != null ||
          backup.document!.snapshot.noteFor(entry.noteId) != null) {
        return false;
      }
    }
    return true;
  }

  void _cleanupOwnedPendingFiles() {
    var removed = false;
    for (final String leaf in const <String>[
      _storePendingLeaf,
      _backupPendingLeaf,
      _deletionsPendingLeaf,
      _recoveryPendingLeaf,
    ]) {
      try {
        if (_session.inspect(leaf).exists) {
          _session.unlink(leaf);
          removed = true;
        }
      } on TerminalNoteStoreException {
        // Best effort never authorizes following or replacing an unsafe entry.
      }
    }
    if (removed) _session.flushDirectory();
  }

  static void _cleanupLeaf(TerminalNoteStoreFileSession session, String leaf) {
    if (session.inspect(leaf).exists) {
      session.unlink(leaf);
      session.flushDirectory();
    }
  }

  static void _bestEffortCleanup(
    TerminalNoteStoreFileSession session,
    String leaf,
  ) {
    try {
      _cleanupLeaf(session, leaf);
    } on Object {
      // Preserve the primary fixed failure.
    }
  }

  TerminalNoteStoreResult _result(
    TerminalNoteStoreDisposition disposition, {
    required TerminalNoteStoreDocument document,
    required bool exposeDocument,
    TerminalNoteStoreFailure? failure,
  }) => TerminalNoteStoreResult(
    disposition: disposition,
    failure: failure,
    storeRevision: document.snapshot.storeRevision,
    metrics: _metrics(document),
    document: exposeDocument ? document : null,
  );

  TerminalNoteStoreResult _failureResult(TerminalNoteStoreFailure failure) {
    final TerminalNoteStoreDocument? loaded = _loaded;
    return TerminalNoteStoreResult(
      disposition: failure == TerminalNoteStoreFailure.upgradeRequired
          ? TerminalNoteStoreDisposition.upgradeRequired
          : failure == TerminalNoteStoreFailure.recoveryRequired
          ? TerminalNoteStoreDisposition.recoveryRequired
          : failure == TerminalNoteStoreFailure.revisionConflict ||
                failure == TerminalNoteStoreFailure.invariantViolation ||
                failure == TerminalNoteStoreFailure.invalidState ||
                failure == TerminalNoteStoreFailure.busy
          ? TerminalNoteStoreDisposition.rejected
          : TerminalNoteStoreDisposition.unavailable,
      failure: failure,
      storeRevision: loaded?.snapshot.storeRevision ?? BigInt.zero,
      metrics: loaded == null
          ? TerminalNoteStoreMetrics.zero
          : _metrics(loaded),
    );
  }

  TerminalNoteStoreMetrics _metrics(TerminalNoteStoreDocument document) {
    final Iterable<NoteRecord> notes = document.snapshot.notes.values;
    return TerminalNoteStoreMetrics(
      noteCount: notes.length,
      activeCount: notes
          .where((NoteRecord note) => note.status == NoteStatus.active)
          .length,
      dueCount: document.snapshot.deliveries.length,
      detachedCount: notes
          .where((NoteRecord note) => note.attachment.isDetached)
          .length,
      canonicalBytes: _codec.encode(document).length,
    );
  }
}

final class _ReadStore {
  const _ReadStore._({
    required this.document,
    required this.missing,
    required this.invalid,
    required this.upgradeRequired,
  });

  const _ReadStore.valid(TerminalNoteStoreDocument document)
    : this._(
        document: document,
        missing: false,
        invalid: false,
        upgradeRequired: false,
      );

  const _ReadStore.missing()
    : this._(
        document: null,
        missing: true,
        invalid: false,
        upgradeRequired: false,
      );

  const _ReadStore.invalid()
    : this._(
        document: null,
        missing: false,
        invalid: true,
        upgradeRequired: false,
      );

  const _ReadStore.upgradeRequired()
    : this._(
        document: null,
        missing: false,
        invalid: false,
        upgradeRequired: true,
      );

  final TerminalNoteStoreDocument? document;
  final bool missing;
  final bool invalid;
  final bool upgradeRequired;
}

final class _ReadJournal {
  const _ReadJournal._({
    required this.journal,
    required this.existed,
    required this.invalid,
    required this.upgradeRequired,
  });

  _ReadJournal.valid(TerminalNoteDeletionJournal journal)
    : this._(
        journal: journal,
        existed: true,
        invalid: false,
        upgradeRequired: false,
      );

  const _ReadJournal.missing()
    : this._(
        journal: null,
        existed: false,
        invalid: false,
        upgradeRequired: false,
      );

  const _ReadJournal.invalid()
    : this._(
        journal: null,
        existed: true,
        invalid: true,
        upgradeRequired: false,
      );

  const _ReadJournal.upgradeRequired()
    : this._(
        journal: null,
        existed: true,
        invalid: false,
        upgradeRequired: true,
      );

  final TerminalNoteDeletionJournal? journal;
  final bool existed;
  final bool invalid;
  final bool upgradeRequired;
}

TerminalNoteStoreDocument _applyJournal(
  TerminalNoteStoreDocument document,
  TerminalNoteDeletionJournal journal,
) {
  if (journal.entries.isEmpty) return document;
  final Set<NoteId> deleted = journal.entries
      .map((TerminalNoteDeletionTombstone entry) => entry.noteId)
      .toSet();
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{
    for (final MapEntry<NoteId, NoteRecord> entry
        in document.snapshot.notes.entries)
      if (!deleted.contains(entry.key)) entry.key: entry.value,
  };
  final Map<Object, List<NoteRecord>> collections =
      <Object, List<NoteRecord>>{};
  for (final NoteRecord note in notes.values) {
    final Object key = note.attachment.isAttached
        ? note.attachment.contextId!
        : _detachedCollection;
    (collections[key] ??= <NoteRecord>[]).add(note);
  }
  for (final List<NoteRecord> collection in collections.values) {
    collection.sort((NoteRecord left, NoteRecord right) {
      final int order = left.order.compareTo(right.order);
      return order == 0 ? left.id.compareTo(right.id) : order;
    });
    for (var index = 0; index < collection.length; index++) {
      final NoteRecord note = collection[index];
      if (note.order == index) continue;
      notes[note.id] = NoteRecord(
        id: note.id,
        attachment: note.attachment,
        body: note.body,
        color: note.color,
        status: note.status,
        order: index,
        createdAtUtcMicros: note.createdAtUtcMicros,
        updatedAtUtcMicros: note.updatedAtUtcMicros,
        revision: note.revision,
      );
    }
  }
  BigInt revision = document.snapshot.storeRevision;
  for (final TerminalNoteDeletionTombstone entry in journal.entries) {
    if (entry.deletionRevision > revision) revision = entry.deletionRevision;
  }
  return TerminalNoteStoreDocument(
    snapshot: TerminalNoteSnapshot.fromRecords(
      storeRevision: revision,
      nextDeliverySequence: document.snapshot.nextDeliverySequence,
      contexts: document.snapshot.contexts,
      notes: notes,
      triggers: <NoteId, NoteTriggerRecord>{
        for (final MapEntry<NoteId, NoteTriggerRecord> entry
            in document.snapshot.triggers.entries)
          if (!deleted.contains(entry.key)) entry.key: entry.value,
      },
      deliveries: <NoteId, NoteDeliveryRecord>{
        for (final MapEntry<NoteId, NoteDeliveryRecord> entry
            in document.snapshot.deliveries.entries)
          if (!deleted.contains(entry.key)) entry.key: entry.value,
      },
    ),
    restorationBinding: document.restorationBinding,
  );
}

final Object _detachedCollection = Object();

TerminalNoteStoreFailure _codecFailure(TerminalNoteCodecException error) =>
    error.requiresUpgrade
    ? TerminalNoteStoreFailure.upgradeRequired
    : switch (error.failure) {
        TerminalNoteCodecFailure.fileTooLarge ||
        TerminalNoteCodecFailure.limitExceeded =>
          TerminalNoteStoreFailure.resourceLimit,
        TerminalNoteCodecFailure.invariantViolation =>
          TerminalNoteStoreFailure.invariantViolation,
        _ => TerminalNoteStoreFailure.codecRejected,
      };

String _normalizeAbsolutePath(String path) {
  if (!_isSafeAbsolutePath(path)) {
    throw const TerminalNoteStoreException(
      TerminalNoteStoreFailure.invalidLocation,
    );
  }
  var result = path;
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  if (result == '/' ||
      utf8.encode(result).length >
          MacosDurableFileLimits.maximumPathUtf8Bytes) {
    throw const TerminalNoteStoreException(
      TerminalNoteStoreFailure.invalidLocation,
    );
  }
  return result;
}

bool _isSafeAbsolutePath(String value) {
  if (!value.startsWith('/') || value.contains('\u0000')) return false;
  for (final String part in value.split('/')) {
    if (part == '.' || part == '..') return false;
  }
  for (final int rune in value.runes) {
    if (rune < 0x20 || rune == 0x7f) return false;
  }
  return true;
}

bool _isSafeLeaf(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.runes.any((int rune) => rune < 0x20 || rune == 0x7f) &&
    utf8.encode(value).length <= MacosDurableFileLimits.maximumLeafUtf8Bytes;
