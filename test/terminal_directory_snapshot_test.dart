import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalDirectorySnapshotTests();

Future<void> runTerminalDirectorySnapshotTests() async {
  _testWorkingDirectoryAuthorityPriority();
  await _testDeterministicFakeSnapshot();
  await _testFailureAndCancellation();
  await _testHardEntryAndPathByteBounds();
  await _testRealTemporaryDirectorySnapshot();
}

void _testWorkingDirectoryAuthorityPriority() {
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: PaneId(1),
    generation: 2,
  );
  const TerminalSessionId staleSessionId = TerminalSessionId(
    paneId: PaneId(1),
    generation: 1,
  );
  final TerminalPaneProcessSnapshot process =
      TerminalPaneProcessSnapshot.available(
        sessionId: sessionId,
        childProcessId: 42,
        owningProcessGroup: 42,
        foregroundProcessGroup: 42,
      );
  const TerminalWorkingDirectoryResolver resolver =
      TerminalWorkingDirectoryResolver();

  TerminalWorkingDirectoryResolution resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 7,
    processSnapshot: process,
    reportedWorkingDirectory: Uri.parse('file:///tmp/osc%20cwd'),
    processWorkingDirectory: PtyWorkingDirectorySnapshot.available(
      processId: 42,
      path: '/tmp/process',
    ),
    launchWorkingDirectory: '/tmp/launch',
  );
  _expect(
    resolved.isAvailable &&
        resolved.generation == 7 &&
        resolved.path == '/tmp/osc cwd' &&
        resolved.source == TerminalWorkingDirectorySource.osc7 &&
        resolved.issues.isEmpty,
    'accepted local OSC 7 has deterministic first authority',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 8,
    processSnapshot: process,
    reportedWorkingDirectory: Uri.parse('file://remote.example/tmp/remote'),
    processWorkingDirectory: PtyWorkingDirectorySnapshot.available(
      processId: 42,
      path: '/tmp/local-process',
    ),
    launchWorkingDirectory: '/tmp/local-launch',
  );
  _expect(
    resolved.disposition ==
            TerminalWorkingDirectoryDisposition.remoteUnavailable &&
        resolved.path == null &&
        resolved.source == null,
    'remote OSC 7 blocks every local cwd fallback',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 9,
    processSnapshot: process,
    reportedWorkingDirectory: null,
    processWorkingDirectory: PtyWorkingDirectorySnapshot.available(
      processId: 42,
      path: '/tmp/process/../shell',
    ),
    launchWorkingDirectory: '/tmp/launch',
  );
  _expect(
    resolved.path == '/tmp/shell' &&
        resolved.source == TerminalWorkingDirectorySource.owningShell,
    'matching owning-shell observation is normalized without symlink probing',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 10,
    processSnapshot: process,
    reportedWorkingDirectory: null,
    processWorkingDirectory: PtyWorkingDirectorySnapshot.available(
      processId: 99,
      path: '/tmp/wrong-process',
    ),
    launchWorkingDirectory: '/tmp/launch/./fallback',
  );
  _expect(
    resolved.path == '/tmp/launch/fallback' &&
        resolved.source == TerminalWorkingDirectorySource.launch &&
        resolved.issues.contains(
          TerminalWorkingDirectoryIssueKind.processIdentityMismatch,
        ),
    'PID mismatch is rejected before trusted launch cwd fallback',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 11,
    processSnapshot: process,
    reportedWorkingDirectory: null,
    processWorkingDirectory: PtyWorkingDirectorySnapshot.available(
      processId: 42,
      path: '/tmp/unsafe\u202eprocess',
    ),
    launchWorkingDirectory: '/tmp/launch',
  );
  _expect(
    resolved.source == TerminalWorkingDirectorySource.launch &&
        resolved.issues.contains(
          TerminalWorkingDirectoryIssueKind.unsafeProcessDirectory,
        ),
    'bidi-bearing process cwd never becomes filesystem authority',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 12,
    processSnapshot: TerminalPaneProcessSnapshot.nonLive(staleSessionId),
    reportedWorkingDirectory: null,
    processWorkingDirectory: null,
    launchWorkingDirectory: '/tmp/launch',
  );
  _expect(
    resolved.disposition == TerminalWorkingDirectoryDisposition.unavailable &&
        resolved.issues.single ==
            TerminalWorkingDirectoryIssueKind.sessionMismatch,
    'session generation mismatch cannot borrow launch or process authority',
  );

  resolved = resolver.resolve(
    sessionId: sessionId,
    generation: 13,
    processSnapshot: process,
    reportedWorkingDirectory: null,
    processWorkingDirectory: null,
    launchWorkingDirectory: 'relative',
  );
  _expect(
    resolved.disposition == TerminalWorkingDirectoryDisposition.unavailable &&
        resolved.issues.contains(
          TerminalWorkingDirectoryIssueKind.processUnavailable,
        ) &&
        resolved.issues.contains(
          TerminalWorkingDirectoryIssueKind.unsafeLaunchDirectory,
        ),
    'no unsafe fallback is synthesized when every authority is unavailable',
  );
}

Future<void> _testDeterministicFakeSnapshot() async {
  final _FakeDirectoryFileSystem files = _FakeDirectoryFileSystem(
    entries: const <TerminalDirectoryFileSystemEntry>[
      TerminalDirectoryFileSystemEntry(
        name: 'z.txt',
        path: '/root/z.txt',
        kind: TerminalDirectoryEntryKind.file,
      ),
      TerminalDirectoryFileSystemEntry(
        name: '.hidden',
        path: '/root/.hidden',
        kind: TerminalDirectoryEntryKind.file,
      ),
      TerminalDirectoryFileSystemEntry(
        name: 'Folder',
        path: '/root/Folder',
        kind: TerminalDirectoryEntryKind.directory,
      ),
      TerminalDirectoryFileSystemEntry(
        name: 'shortcut',
        path: '/root/shortcut',
        kind: TerminalDirectoryEntryKind.symbolicLink,
      ),
    ],
    metadataFor: (TerminalDirectoryFileSystemEntry entry) async {
      await Future<void>.delayed(Duration.zero);
      return entry.kind == TerminalDirectoryEntryKind.symbolicLink
          ? const TerminalDirectoryFileSystemMetadata(
              symlinkTarget: '../target',
            )
          : TerminalDirectoryFileSystemMetadata(
              mode: entry.kind == TerminalDirectoryEntryKind.directory
                  ? 0x41ed
                  : 0x81a4,
              size: entry.name.length,
              modifiedMicrosecondsSinceEpoch: 1234,
              ownerUserId: 501,
              ownerGroupId: 20,
            );
    },
  );
  final TerminalDirectorySnapshotOperation operation =
      TerminalDirectorySnapshotService(fileSystem: files).start(
        TerminalDirectorySnapshotRequest(
          rootPath: '/root/./nested/..',
          generation: 21,
          metadataConcurrency: 2,
        ),
      );
  final TerminalDirectorySnapshot snapshot = await operation.result;
  operation.cancel();

  _expect(
    snapshot.disposition == TerminalDirectorySnapshotDisposition.complete &&
        snapshot.generation == 21 &&
        snapshot.rootPath == '/root' &&
        snapshot.entries.map((value) => value.name).join(',') ==
            'Folder,.hidden,z.txt,shortcut' &&
        snapshot.entries[1].isHidden &&
        snapshot.entries[1].metadata.ownerUserId == 501 &&
        snapshot.entries.last.metadata.symlinkTarget == '../target' &&
        files.maximumActiveMetadata == 2 &&
        !operation.isCancelled &&
        snapshot.metadataFailureCount == 0 &&
        snapshot.omittedEntryCount == 0,
    'one-level snapshot retains dotfiles, metadata, links, and stable order',
  );
  _expectThrows<UnsupportedError>(
    () => snapshot.entries.add(snapshot.entries.first),
    'entry snapshot is immutable',
  );
  _expectThrows<UnsupportedError>(
    () => snapshot.issues.add(
      const TerminalDirectoryIssue(kind: TerminalDirectoryIssueKind.ioFailure),
    ),
    'issue snapshot is immutable',
  );
}

Future<void> _testFailureAndCancellation() async {
  final TerminalDirectorySnapshot invalid =
      await const TerminalDirectorySnapshotService(
            fileSystem: _EmptyDirectoryFileSystem(),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/../escape',
              generation: 30,
            ),
          )
          .result;
  _expect(
    invalid.disposition == TerminalDirectorySnapshotDisposition.unavailable &&
        invalid.rootPath == null &&
        invalid.issues.single.kind == TerminalDirectoryIssueKind.invalidRoot,
    'root traversal above slash is rejected before filesystem access',
  );

  final TerminalDirectorySnapshot denied =
      await const TerminalDirectorySnapshotService(
            fileSystem: _DeniedDirectoryFileSystem(),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/denied',
              generation: 31,
            ),
          )
          .result;
  _expect(
    denied.disposition == TerminalDirectorySnapshotDisposition.unavailable &&
        denied.entries.isEmpty &&
        denied.issues.single.kind ==
            TerminalDirectoryIssueKind.permissionDenied &&
        denied.issues.single.systemError == 13,
    'directory permission failure is typed without retaining an error path',
  );

  final _FakeDirectoryFileSystem hostile = _FakeDirectoryFileSystem(
    entries: const <TerminalDirectoryFileSystemEntry>[
      TerminalDirectoryFileSystemEntry(
        name: 'safe',
        path: '/root/safe',
        kind: TerminalDirectoryEntryKind.file,
      ),
      TerminalDirectoryFileSystemEntry(
        name: 'safe',
        path: '/root/safe',
        kind: TerminalDirectoryEntryKind.file,
      ),
      TerminalDirectoryFileSystemEntry(
        name: 'outside',
        path: '/outside',
        kind: TerminalDirectoryEntryKind.file,
      ),
      TerminalDirectoryFileSystemEntry(
        name: 'bad\nname',
        path: '/root/bad\nname',
        kind: TerminalDirectoryEntryKind.file,
      ),
    ],
    metadataFor: (_) async =>
        const TerminalDirectoryFileSystemMetadata(size: 1),
  );
  final TerminalDirectorySnapshot filtered =
      await TerminalDirectorySnapshotService(fileSystem: hostile)
          .start(
            TerminalDirectorySnapshotRequest(rootPath: '/root', generation: 32),
          )
          .result;
  _expect(
    filtered.disposition == TerminalDirectorySnapshotDisposition.partial &&
        filtered.entries.single.name == 'safe' &&
        filtered.scannedEntryCount == 4 &&
        filtered.omittedEntryCount == 3 &&
        filtered.issues.map((value) => value.kind).toSet().containsAll(
          const <TerminalDirectoryIssueKind>{
            TerminalDirectoryIssueKind.duplicateEntry,
            TerminalDirectoryIssueKind.invalidEntry,
          },
        ),
    'duplicate, escaping, and unsafe-name rows are omitted deterministically',
  );

  final _FakeDirectoryFileSystem changing = _FakeDirectoryFileSystem(
    entries: const <TerminalDirectoryFileSystemEntry>[
      TerminalDirectoryFileSystemEntry(
        name: 'vanished',
        path: '/root/vanished',
        kind: TerminalDirectoryEntryKind.file,
      ),
    ],
    metadataFor: (_) => Future<TerminalDirectoryFileSystemMetadata>.error(
      const FileSystemException(
        'gone',
        '/must-not-be-retained-in-result',
        OSError('gone', 2),
      ),
    ),
  );
  final TerminalDirectorySnapshot partial =
      await TerminalDirectorySnapshotService(fileSystem: changing)
          .start(
            TerminalDirectorySnapshotRequest(rootPath: '/root', generation: 32),
          )
          .result;
  _expect(
    partial.disposition == TerminalDirectorySnapshotDisposition.partial &&
        partial.entries.single.metadata.disposition ==
            TerminalDirectoryMetadataDisposition.unavailable &&
        partial.entries.single.metadata.systemError == 2 &&
        partial.metadataFailureCount == 1 &&
        partial.issues.single.kind ==
            TerminalDirectoryIssueKind.metadataUnavailable,
    'vanished metadata keeps the row and exposes only typed failure state',
  );

  final TerminalDirectorySnapshot detached =
      await const TerminalDirectorySnapshotService(
            fileSystem: _DetachedDirectoryFileSystem(),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/volume',
              generation: 33,
            ),
          )
          .result;
  _expect(
    detached.disposition == TerminalDirectorySnapshotDisposition.partial &&
        detached.entries.single.name == 'observed-before-detach' &&
        detached.issues.single.kind == TerminalDirectoryIssueKind.ioFailure &&
        detached.issues.single.systemError == 6,
    'mount detach preserves observed rows and reports a typed partial result',
  );

  final _BlockingMetadataFileSystem blocking = _BlockingMetadataFileSystem();
  final TerminalDirectorySnapshotOperation operation =
      TerminalDirectorySnapshotService(fileSystem: blocking).start(
        TerminalDirectorySnapshotRequest(rootPath: '/root', generation: 33),
      );
  await blocking.metadataStarted.future;
  operation.cancel();
  final TerminalDirectorySnapshot cancelled = await operation.result;
  _expect(
    operation.isCancelled &&
        cancelled.disposition ==
            TerminalDirectorySnapshotDisposition.cancelled &&
        cancelled.entries.isEmpty &&
        cancelled.issues.single.kind == TerminalDirectoryIssueKind.cancelled,
    'explicit cancellation publishes no partial or late entry state',
  );
  blocking.metadataResult.complete(
    const TerminalDirectoryFileSystemMetadata(size: 99),
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    cancelled.entries.isEmpty,
    'late metadata completion cannot mutate a cancelled immutable snapshot',
  );

  final _BlockingListFileSystem slow = _BlockingListFileSystem();
  final TerminalDirectorySnapshot deadline =
      await TerminalDirectorySnapshotService(fileSystem: slow)
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/root',
              generation: 34,
              deadline: const Duration(milliseconds: 20),
            ),
          )
          .result;
  _expect(
    deadline.disposition == TerminalDirectorySnapshotDisposition.partial &&
        deadline.entries.single.name == 'seen' &&
        deadline.entries.single.metadata.disposition ==
            TerminalDirectoryMetadataDisposition.unavailable &&
        deadline.issues.single.kind ==
            TerminalDirectoryIssueKind.deadlineExceeded,
    'deadline returns only already-observed bounded rows with no late metadata',
  );
  slow.release.complete();
}

Future<void> _testHardEntryAndPathByteBounds() async {
  _expect(
    TerminalDirectorySnapshotLimits.retainedSnapshotCapacity == 0 &&
        TerminalDirectorySnapshotLimits.fileSystemWatcherCapacity == 0,
    'one-shot snapshot layer retains no cache or filesystem watcher owner',
  );
  final TerminalDirectorySnapshot requestBounded =
      await TerminalDirectorySnapshotService(
            fileSystem: _GeneratedDirectoryFileSystem(
              count: 3,
              nameForIndex: (int index) => 'bounded-$index',
            ),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/root',
              generation: 39,
              maximumEntries: 2,
              maximumTotalPathUtf8Bytes: 1024,
            ),
          )
          .result;
  _expect(
    requestBounded.entries.length == 2 &&
        requestBounded.disposition ==
            TerminalDirectorySnapshotDisposition.partial &&
        requestBounded.issues.single.kind ==
            TerminalDirectoryIssueKind.entryLimitReached,
    'a caller may select a smaller budget without weakening hard limits',
  );
  _expectThrows<ArgumentError>(
    () => TerminalDirectorySnapshotRequest(
      rootPath: '/root',
      generation: 39,
      maximumEntries: TerminalDirectorySnapshotLimits.maximumEntries + 1,
    ),
    'request entry budgets cannot exceed the hard maximum',
  );
  final TerminalDirectorySnapshot entries =
      await TerminalDirectorySnapshotService(
            fileSystem: _GeneratedDirectoryFileSystem(
              count: TerminalDirectorySnapshotLimits.maximumEntries + 1,
              nameForIndex: (int index) => 'entry-$index',
            ),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/root',
              generation: 40,
              deadline: TerminalDirectorySnapshotLimits.maximumDeadline,
            ),
          )
          .result;
  _expect(
    entries.disposition == TerminalDirectorySnapshotDisposition.partial &&
        entries.entries.length ==
            TerminalDirectorySnapshotLimits.maximumEntries &&
        entries.scannedEntryCount ==
            TerminalDirectorySnapshotLimits.maximumEntries + 1 &&
        entries.omittedEntryCount == 1 &&
        entries.issues.single.kind ==
            TerminalDirectoryIssueKind.entryLimitReached,
    'entry cap accepts the exact boundary and observes only one overflow row',
  );

  final TerminalDirectorySnapshot bytes =
      await TerminalDirectorySnapshotService(
            fileSystem: _GeneratedDirectoryFileSystem(
              count: TerminalDirectorySnapshotLimits.maximumEntries,
              nameForIndex: (int index) => '${'n' * 600}-$index',
            ),
          )
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: '/root',
              generation: 41,
              deadline: TerminalDirectorySnapshotLimits.maximumDeadline,
            ),
          )
          .result;
  _expect(
    bytes.disposition == TerminalDirectorySnapshotDisposition.partial &&
        bytes.entries.length < TerminalDirectorySnapshotLimits.maximumEntries &&
        bytes.totalPathUtf8Bytes <=
            TerminalDirectorySnapshotLimits.maximumTotalPathUtf8Bytes &&
        bytes.issues.single.kind ==
            TerminalDirectoryIssueKind.pathByteLimitReached,
    'aggregate retained path bytes cannot cross the one MiB hard cap',
  );
}

Future<void> _testRealTemporaryDirectorySnapshot() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dart-terminal-directory-snapshot-',
  );
  try {
    await Directory('${root.path}/folder').create();
    await File('${root.path}/folder/nested.txt').writeAsString('nested');
    await File('${root.path}/visible.txt').writeAsString('visible');
    await File('${root.path}/.hidden').writeAsString('hidden');
    await Link('${root.path}/shortcut').create('visible.txt');
    await Link('${root.path}/loop').create('.');

    final TerminalDirectorySnapshot snapshot =
        await const TerminalDirectorySnapshotService()
            .start(
              TerminalDirectorySnapshotRequest(
                rootPath: root.path,
                generation: 50,
                deadline: TerminalDirectorySnapshotLimits.maximumDeadline,
              ),
            )
            .result;
    final Map<String, TerminalDirectoryEntrySnapshot> byName =
        <String, TerminalDirectoryEntrySnapshot>{
          for (final TerminalDirectoryEntrySnapshot entry in snapshot.entries)
            entry.name: entry,
        };
    _expect(
      snapshot.disposition == TerminalDirectorySnapshotDisposition.complete &&
          byName.length == 5 &&
          byName['folder']?.kind == TerminalDirectoryEntryKind.directory &&
          byName['visible.txt']?.kind == TerminalDirectoryEntryKind.file &&
          byName['.hidden']?.isHidden == true &&
          byName['shortcut']?.kind == TerminalDirectoryEntryKind.symbolicLink &&
          byName['shortcut']?.metadata.symlinkTarget == 'visible.txt' &&
          byName['loop']?.kind == TerminalDirectoryEntryKind.symbolicLink &&
          byName['loop']?.metadata.symlinkTarget == '.' &&
          byName['visible.txt']?.metadata.size ==
              utf8.encode('visible').length &&
          byName['visible.txt']?.metadata.mode != null &&
          byName['visible.txt']?.metadata.modifiedMicrosecondsSinceEpoch !=
              null &&
          !byName.containsKey('nested.txt'),
      'real adapter observes one level, dotfiles, stat metadata, and unfollowed links',
    );
    final TerminalDirectorySnapshot child =
        await const TerminalDirectorySnapshotService()
            .start(
              TerminalDirectorySnapshotRequest(
                rootPath: '${root.path}/folder',
                generation: 51,
                deadline: TerminalDirectorySnapshotLimits.maximumDeadline,
              ),
            )
            .result;
    _expect(
      child.disposition == TerminalDirectorySnapshotDisposition.complete &&
          child.entries.single.name == 'nested.txt',
      'a subtree is enumerated only when its directory is requested lazily',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

final class _FakeDirectoryFileSystem implements TerminalDirectoryFileSystem {
  _FakeDirectoryFileSystem({required this.entries, required this.metadataFor});

  final List<TerminalDirectoryFileSystemEntry> entries;
  final Future<TerminalDirectoryFileSystemMetadata> Function(
    TerminalDirectoryFileSystemEntry entry,
  )
  metadataFor;
  int activeMetadata = 0;
  int maximumActiveMetadata = 0;

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    for (final TerminalDirectoryFileSystemEntry entry in entries) {
      yield entry;
    }
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async {
    activeMetadata++;
    if (activeMetadata > maximumActiveMetadata) {
      maximumActiveMetadata = activeMetadata;
    }
    try {
      return await metadataFor(entry);
    } finally {
      activeMetadata--;
    }
  }
}

final class _EmptyDirectoryFileSystem implements TerminalDirectoryFileSystem {
  const _EmptyDirectoryFileSystem();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) =>
      const Stream<TerminalDirectoryFileSystemEntry>.empty();

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata();
}

final class _DeniedDirectoryFileSystem implements TerminalDirectoryFileSystem {
  const _DeniedDirectoryFileSystem();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    throw const FileSystemException(
      'denied',
      '/must-not-be-retained-in-result',
      OSError('denied', 13),
    );
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata();
}

final class _DetachedDirectoryFileSystem
    implements TerminalDirectoryFileSystem {
  const _DetachedDirectoryFileSystem();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    yield const TerminalDirectoryFileSystemEntry(
      name: 'observed-before-detach',
      path: '/volume/observed-before-detach',
      kind: TerminalDirectoryEntryKind.file,
    );
    throw const FileSystemException(
      'detached',
      '/must-not-be-retained-in-result',
      OSError('device unavailable', 6),
    );
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1);
}

final class _BlockingMetadataFileSystem implements TerminalDirectoryFileSystem {
  final Completer<void> metadataStarted = Completer<void>();
  final Completer<TerminalDirectoryFileSystemMetadata> metadataResult =
      Completer<TerminalDirectoryFileSystemMetadata>();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    yield const TerminalDirectoryFileSystemEntry(
      name: 'pending',
      path: '/root/pending',
      kind: TerminalDirectoryEntryKind.file,
    );
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) {
    if (!metadataStarted.isCompleted) metadataStarted.complete();
    return metadataResult.future;
  }
}

final class _BlockingListFileSystem implements TerminalDirectoryFileSystem {
  final Completer<void> release = Completer<void>();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    yield const TerminalDirectoryFileSystemEntry(
      name: 'seen',
      path: '/root/seen',
      kind: TerminalDirectoryEntryKind.file,
    );
    await release.future;
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1);
}

final class _GeneratedDirectoryFileSystem
    implements TerminalDirectoryFileSystem {
  const _GeneratedDirectoryFileSystem({
    required this.count,
    required this.nameForIndex,
  });

  final int count;
  final String Function(int index) nameForIndex;

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    for (var index = 0; index < count; index++) {
      final String name = nameForIndex(index);
      yield TerminalDirectoryFileSystemEntry(
        name: name,
        path: '$rootPath/$name',
        kind: TerminalDirectoryEntryKind.file,
      );
    }
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1);
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
      'terminal directory snapshot expectation failed: $description',
    );
  }
}
