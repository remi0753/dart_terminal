import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalFileSearchTests();

Future<void> runTerminalFileSearchTests() async {
  _testQueryAndMetadataExpression();
  await _testProgressiveScopeRankingAndDedupe();
  await _testCurrentResultsPublishBeforeSystemIndex();
  await _testUnavailableIndexAndResultCap();
  await _testCancellationRejectsLateDirectoryWork();
}

Future<void> _testCurrentResultsPublishBeforeSystemIndex() async {
  final _BlockingSystemIndex index = _BlockingSystemIndex();
  final List<TerminalFileSearchSnapshot> progress =
      <TerminalFileSearchSnapshot>[];
  final TerminalFileSearchOperation operation =
      TerminalFileSearchService(
        directorySnapshots: TerminalDirectorySnapshotService(
          fileSystem: _SearchDirectoryFileSystem(
            const <String, List<TerminalDirectoryFileSystemEntry>>{
              '/cwd': <TerminalDirectoryFileSystemEntry>[
                TerminalDirectoryFileSystemEntry(
                  name: 'alpha-local',
                  path: '/cwd/alpha-local',
                  kind: TerminalDirectoryEntryKind.file,
                ),
              ],
            },
          ),
        ),
        systemIndex: index,
        pathSnapshot: _pathSnapshot,
      ).start(
        TerminalFileSearchRequest(
          query: TerminalFileSearchQuery.parse('alpha'),
          currentRoot: '/cwd',
          generation: 6,
        ),
        onProgress: progress.add,
      );
  await index.started.future;
  _expect(
    progress.any(
      (TerminalFileSearchSnapshot value) =>
          value.results.length == 1 &&
          value.results.single.entry.path == '/cwd/alpha-local' &&
          value.coverage
                  .singleWhere(
                    (TerminalFileSearchCoverage coverage) =>
                        coverage.source == TerminalFileSearchSource.systemIndex,
                  )
                  .disposition ==
              TerminalFileSearchCoverageDisposition.searching,
    ),
    'current-subtree matches publish while the wider index is still running',
  );
  index.result.complete(
    TerminalSystemFileIndexSnapshot(
      disposition: TerminalSystemFileIndexDisposition.complete,
      paths: const <String>['/system/alpha-global'],
    ),
  );
  final TerminalFileSearchSnapshot finalResult = await operation.result;
  _expect(
    finalResult.results.length == 2 && finalResult.isComplete,
    'system-index results extend rather than replace current results',
  );
}

void _testQueryAndMetadataExpression() {
  final TerminalFileSearchQuery query = TerminalFileSearchQuery.parse(
    '  Alpha  "beta gamma" delta  ',
  );
  _expect(
    query.terms.join('|') == 'alpha|beta gamma|delta' &&
        query.matches('alpha-notes', '/tmp/beta gamma/delta') &&
        !query.matches('alpha-notes', '/tmp/beta gamma'),
    'whitespace terms are ANDed and a quoted phrase remains one term',
  );
  final TerminalFileSearchQuery bounded = TerminalFileSearchQuery.parse(
    List<String>.generate(20, (int index) => 'term$index').join(' '),
  );
  _expect(
    bounded.terms.length == TerminalFileSearchLimits.maximumTerms,
    'query token count is bounded before provider execution',
  );
  final String expression = TerminalMacosMetadataFileIndex.metadataExpression(
    TerminalFileSearchQuery.parse(r'alpha* beta? gamma\delta'),
  );
  _expect(
    expression.contains(r'alpha\*') &&
        expression.contains(r'beta\?') &&
        expression.contains(r'gamma\\delta') &&
        expression.contains('kMDItemFSName') &&
        expression.contains(' && '),
    'system search owns a fixed basename predicate and escapes wildcards',
  );
}

Future<void> _testProgressiveScopeRankingAndDedupe() async {
  final _SearchDirectoryFileSystem files = _SearchDirectoryFileSystem(
    <String, List<TerminalDirectoryFileSystemEntry>>{
      '/cwd': const <TerminalDirectoryFileSystemEntry>[
        TerminalDirectoryFileSystemEntry(
          name: 'src',
          path: '/cwd/src',
          kind: TerminalDirectoryEntryKind.directory,
        ),
        TerminalDirectoryFileSystemEntry(
          name: 'alpha',
          path: '/cwd/alpha',
          kind: TerminalDirectoryEntryKind.file,
        ),
      ],
      '/cwd/src': const <TerminalDirectoryFileSystemEntry>[
        TerminalDirectoryFileSystemEntry(
          name: 'alpha-deep.md',
          path: '/cwd/src/alpha-deep.md',
          kind: TerminalDirectoryEntryKind.file,
        ),
      ],
      '/recent': const <TerminalDirectoryFileSystemEntry>[
        TerminalDirectoryFileSystemEntry(
          name: 'alpha-recent.md',
          path: '/recent/alpha-recent.md',
          kind: TerminalDirectoryEntryKind.file,
        ),
      ],
      '/chosen': const <TerminalDirectoryFileSystemEntry>[
        TerminalDirectoryFileSystemEntry(
          name: 'alpha-chosen.md',
          path: '/chosen/alpha-chosen.md',
          kind: TerminalDirectoryEntryKind.file,
        ),
      ],
    },
  );
  final _ImmediateSystemIndex index = _ImmediateSystemIndex(
    TerminalSystemFileIndexSnapshot(
      disposition: TerminalSystemFileIndexDisposition.complete,
      paths: const <String>['/cwd/alpha', '/system/alpha-tool'],
    ),
  );
  final List<TerminalFileSearchSnapshot> progress =
      <TerminalFileSearchSnapshot>[];
  final TerminalFileSearchService service = TerminalFileSearchService(
    directorySnapshots: TerminalDirectorySnapshotService(fileSystem: files),
    systemIndex: index,
    pathSnapshot: _pathSnapshot,
  );
  final TerminalFileSearchSnapshot result = await service
      .start(
        TerminalFileSearchRequest(
          query: TerminalFileSearchQuery.parse('alpha'),
          currentRoot: '/cwd',
          recentRoots: const <String>['/cwd', '/recent'],
          explicitRoots: const <String>['relative', '/chosen'],
          generation: 7,
        ),
        onProgress: progress.add,
      )
      .result;
  _expect(
    result.isComplete &&
        result.results.length == 5 &&
        result.results.first.entry.path == '/cwd/alpha' &&
        result.results
                .where((value) => value.entry.path == '/cwd/alpha')
                .length ==
            1 &&
        result.results
            .map((value) => value.source)
            .toSet()
            .containsAll(TerminalFileSearchSource.values),
    'cwd, recent, explicit, and index results merge with deterministic dedupe',
  );
  _expect(
    progress.length >= 4 &&
        result.coverage.every(
          (TerminalFileSearchCoverage value) =>
              value.disposition ==
              TerminalFileSearchCoverageDisposition.complete,
        ),
    'provider completion is progressively visible with exact coverage',
  );
}

Future<void> _testUnavailableIndexAndResultCap() async {
  final TerminalFileSearchService unavailable = TerminalFileSearchService(
    directorySnapshots: TerminalDirectorySnapshotService(
      fileSystem: _SearchDirectoryFileSystem(
        const <String, List<TerminalDirectoryFileSystemEntry>>{
          '/cwd': <TerminalDirectoryFileSystemEntry>[],
        },
      ),
    ),
    systemIndex: _ImmediateSystemIndex(
      TerminalSystemFileIndexSnapshot(
        disposition: TerminalSystemFileIndexDisposition.unavailable,
        paths: const <String>[],
      ),
    ),
  );
  final TerminalFileSearchSnapshot unavailableResult = await unavailable
      .start(
        TerminalFileSearchRequest(
          query: TerminalFileSearchQuery.parse('missing'),
          currentRoot: '/cwd',
          generation: 8,
        ),
      )
      .result;
  _expect(
    unavailableResult.results.isEmpty &&
        unavailableResult.coverage
                .singleWhere(
                  (TerminalFileSearchCoverage value) =>
                      value.source == TerminalFileSearchSource.systemIndex,
                )
                .disposition ==
            TerminalFileSearchCoverageDisposition.unavailable,
    'zero results remain distinct from unavailable system-index coverage',
  );

  final List<String> manyPaths = <String>[
    for (
      var index = 0;
      index < TerminalFileSearchLimits.maximumResults + 20;
      index++
    )
      '/system/match-$index',
  ];
  final TerminalFileSearchService bounded = TerminalFileSearchService(
    directorySnapshots: TerminalDirectorySnapshotService(
      fileSystem: _SearchDirectoryFileSystem(
        const <String, List<TerminalDirectoryFileSystemEntry>>{
          '/cwd': <TerminalDirectoryFileSystemEntry>[],
        },
      ),
    ),
    systemIndex: _ImmediateSystemIndex(
      TerminalSystemFileIndexSnapshot(
        disposition: TerminalSystemFileIndexDisposition.complete,
        paths: manyPaths,
      ),
    ),
    pathSnapshot: _pathSnapshot,
  );
  final TerminalFileSearchSnapshot boundedResult = await bounded
      .start(
        TerminalFileSearchRequest(
          query: TerminalFileSearchQuery.parse('match'),
          currentRoot: '/cwd',
          generation: 9,
        ),
      )
      .result;
  _expect(
    boundedResult.results.length == TerminalFileSearchLimits.maximumResults,
    'even a misbehaving index adapter cannot exceed the aggregate result cap',
  );
}

Future<void> _testCancellationRejectsLateDirectoryWork() async {
  final _BlockingSearchDirectoryFileSystem files =
      _BlockingSearchDirectoryFileSystem();
  final List<TerminalFileSearchSnapshot> progress =
      <TerminalFileSearchSnapshot>[];
  final TerminalFileSearchOperation operation =
      TerminalFileSearchService(
        directorySnapshots: TerminalDirectorySnapshotService(fileSystem: files),
        systemIndex: _ImmediateSystemIndex(
          TerminalSystemFileIndexSnapshot(
            disposition: TerminalSystemFileIndexDisposition.complete,
            paths: const <String>[],
          ),
        ),
      ).start(
        TerminalFileSearchRequest(
          query: TerminalFileSearchQuery.parse('late'),
          currentRoot: '/cwd',
          generation: 10,
        ),
        onProgress: progress.add,
      );
  await files.started.future;
  operation.cancel();
  final TerminalFileSearchSnapshot cancelled = await operation.result;
  files.release.complete();
  await Future<void>.delayed(Duration.zero);
  _expect(
    cancelled.wasCancelled &&
        !cancelled.isComplete &&
        cancelled.results.isEmpty &&
        cancelled.coverage.every(
          (TerminalFileSearchCoverage value) =>
              value.disposition ==
              TerminalFileSearchCoverageDisposition.partial,
        ) &&
        progress.isEmpty,
    'cancelled work cannot publish late results or leave searching coverage',
  );
}

Future<TerminalDirectoryEntrySnapshot?> _pathSnapshot(String path) async {
  final String name = path.substring(path.lastIndexOf('/') + 1);
  return TerminalDirectoryEntrySnapshot(
    name: name,
    path: path,
    kind: TerminalDirectoryEntryKind.file,
    isHidden: false,
    metadata: const TerminalDirectoryEntryMetadataSnapshot.unavailable(),
  );
}

final class _SearchDirectoryFileSystem implements TerminalDirectoryFileSystem {
  const _SearchDirectoryFileSystem(this.entries);

  final Map<String, List<TerminalDirectoryFileSystemEntry>> entries;

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) =>
      Stream<TerminalDirectoryFileSystemEntry>.fromIterable(
        entries[rootPath] ?? const <TerminalDirectoryFileSystemEntry>[],
      );

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1, mode: 0x1a4);
}

final class _BlockingSearchDirectoryFileSystem
    implements TerminalDirectoryFileSystem {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    started.complete();
    await release.future;
    yield const TerminalDirectoryFileSystemEntry(
      name: 'late',
      path: '/cwd/late',
      kind: TerminalDirectoryEntryKind.file,
    );
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async => const TerminalDirectoryFileSystemMetadata(size: 1);
}

final class _ImmediateSystemIndex implements TerminalSystemFileIndex {
  const _ImmediateSystemIndex(this.snapshot);

  final TerminalSystemFileIndexSnapshot snapshot;

  @override
  TerminalSystemFileIndexOperation start(TerminalFileSearchQuery query) =>
      _ImmediateSystemIndexOperation(snapshot);
}

final class _ImmediateSystemIndexOperation
    implements TerminalSystemFileIndexOperation {
  const _ImmediateSystemIndexOperation(this.snapshot);

  final TerminalSystemFileIndexSnapshot snapshot;

  @override
  Future<TerminalSystemFileIndexSnapshot> get result async => snapshot;

  @override
  void cancel() {}
}

final class _BlockingSystemIndex implements TerminalSystemFileIndex {
  final Completer<void> started = Completer<void>();
  final Completer<TerminalSystemFileIndexSnapshot> result =
      Completer<TerminalSystemFileIndexSnapshot>();

  @override
  TerminalSystemFileIndexOperation start(TerminalFileSearchQuery query) {
    started.complete();
    return _BlockingSystemIndexOperation(result);
  }
}

final class _BlockingSystemIndexOperation
    implements TerminalSystemFileIndexOperation {
  const _BlockingSystemIndexOperation(this.completer);

  final Completer<TerminalSystemFileIndexSnapshot> completer;

  @override
  Future<TerminalSystemFileIndexSnapshot> get result => completer.future;

  @override
  void cancel() {
    if (!completer.isCompleted) {
      completer.complete(
        TerminalSystemFileIndexSnapshot(
          disposition: TerminalSystemFileIndexDisposition.cancelled,
          paths: const <String>[],
        ),
      );
    }
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal file search expectation failed: $description');
  }
}
