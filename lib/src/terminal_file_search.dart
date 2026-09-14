import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_directory_snapshot.dart';

abstract final class TerminalFileSearchLimits {
  static const int maximumTerms = 16;
  static const int maximumTermUnits = 64;
  static const int maximumResults = 512;
  static const int maximumDirectories = 512;
  static const int maximumScannedEntries = 4096;
  static const int maximumDepth = 12;
  static const int maximumAdditionalRoots = 8;
  static const int maximumRetainedPathUtf8Bytes = 1024 * 1024;
  static const int maximumSystemIndexOutputBytes = 1024 * 1024;
  static const int maximumSystemIndexResults = 256;
  static const Duration deadline = Duration(seconds: 3);
  static const Duration systemIndexDeadline = Duration(milliseconds: 1200);
}

final class TerminalFileSearchQuery {
  TerminalFileSearchQuery._(this.raw, Iterable<String> terms)
    : terms = List<String>.unmodifiable(terms);

  factory TerminalFileSearchQuery.parse(String raw) {
    final List<String> terms = <String>[];
    final StringBuffer current = StringBuffer();
    var quoted = false;
    void commit() {
      final String value = current.toString().trim().toLowerCase();
      current.clear();
      if (value.isEmpty ||
          terms.length >= TerminalFileSearchLimits.maximumTerms) {
        return;
      }
      terms.add(
        value.length > TerminalFileSearchLimits.maximumTermUnits
            ? value.substring(0, TerminalFileSearchLimits.maximumTermUnits)
            : value,
      );
    }

    for (final int scalar in raw.runes) {
      if (scalar == 0x22) {
        if (quoted) commit();
        quoted = !quoted;
      } else if (!quoted && _isWhitespace(scalar)) {
        commit();
      } else if (current.length < TerminalFileSearchLimits.maximumTermUnits) {
        current.writeCharCode(scalar);
      }
    }
    commit();
    return TerminalFileSearchQuery._(raw, terms);
  }

  final String raw;
  final List<String> terms;

  bool get isEmpty => terms.isEmpty;

  bool matches(String name, String path) {
    final String foldedName = name.toLowerCase();
    final String foldedPath = path.toLowerCase();
    return terms.every(
      (String term) => foldedName.contains(term) || foldedPath.contains(term),
    );
  }

  static bool _isWhitespace(int scalar) =>
      scalar == 0x20 || scalar == 0x09 || scalar == 0x0a || scalar == 0x0d;
}

enum TerminalFileSearchSource { currentSubtree, recent, explicit, systemIndex }

enum TerminalFileSearchCoverageDisposition {
  searching,
  complete,
  partial,
  unavailable,
}

final class TerminalFileSearchCoverage {
  const TerminalFileSearchCoverage({
    required this.source,
    required this.disposition,
    required this.rootCount,
  });

  final TerminalFileSearchSource source;
  final TerminalFileSearchCoverageDisposition disposition;
  final int rootCount;
}

final class TerminalFileSearchResult {
  const TerminalFileSearchResult({
    required this.entry,
    required this.source,
    required this.depth,
  });

  final TerminalDirectoryEntrySnapshot entry;
  final TerminalFileSearchSource source;
  final int depth;
}

final class TerminalFileSearchSnapshot {
  TerminalFileSearchSnapshot({
    required this.generation,
    required this.query,
    required Iterable<TerminalFileSearchResult> results,
    required Iterable<TerminalFileSearchCoverage> coverage,
    required this.isComplete,
    required this.wasCancelled,
    required this.scannedEntryCount,
    required this.omittedResultCount,
  }) : results = List<TerminalFileSearchResult>.unmodifiable(results),
       coverage = List<TerminalFileSearchCoverage>.unmodifiable(coverage);

  final int generation;
  final TerminalFileSearchQuery query;
  final List<TerminalFileSearchResult> results;
  final List<TerminalFileSearchCoverage> coverage;
  final bool isComplete;
  final bool wasCancelled;
  final int scannedEntryCount;
  final int omittedResultCount;
}

final class TerminalFileSearchRequest {
  TerminalFileSearchRequest({
    required this.query,
    required this.currentRoot,
    required this.generation,
    Iterable<String> recentRoots = const <String>[],
    Iterable<String> explicitRoots = const <String>[],
  }) : recentRoots = _safeRoots(recentRoots, excluding: currentRoot),
       explicitRoots = _safeRoots(explicitRoots, excluding: currentRoot) {
    if (generation <= 0) {
      throw ArgumentError.value(generation, 'generation', 'must be positive');
    }
    if (query.isEmpty) {
      throw ArgumentError.value(query.raw, 'query', 'must not be empty');
    }
    if (TerminalLocalPathPolicy.normalizeAbsolute(currentRoot) != currentRoot) {
      throw ArgumentError.value(currentRoot, 'currentRoot', 'must be safe');
    }
  }

  final TerminalFileSearchQuery query;
  final String currentRoot;
  final int generation;
  final List<String> recentRoots;
  final List<String> explicitRoots;

  static List<String> _safeRoots(
    Iterable<String> roots, {
    required String excluding,
  }) {
    final List<String> safe = <String>[];
    final Set<String> seen = <String>{excluding};
    for (final String root in roots) {
      final String? normalized = TerminalLocalPathPolicy.normalizeAbsolute(
        root,
      );
      if (normalized == null || !seen.add(normalized)) continue;
      safe.add(normalized);
      if (safe.length >= TerminalFileSearchLimits.maximumAdditionalRoots) break;
    }
    return List<String>.unmodifiable(safe);
  }
}

enum TerminalSystemFileIndexDisposition {
  complete,
  partial,
  unavailable,
  cancelled,
}

final class TerminalSystemFileIndexSnapshot {
  TerminalSystemFileIndexSnapshot({
    required this.disposition,
    required Iterable<String> paths,
  }) : paths = List<String>.unmodifiable(paths);

  final TerminalSystemFileIndexDisposition disposition;
  final List<String> paths;
}

abstract interface class TerminalSystemFileIndexOperation {
  Future<TerminalSystemFileIndexSnapshot> get result;
  void cancel();
}

abstract interface class TerminalSystemFileIndex {
  TerminalSystemFileIndexOperation start(TerminalFileSearchQuery query);
}

/// Shell-free macOS metadata index adapter with a fixed basename predicate.
final class TerminalMacosMetadataFileIndex implements TerminalSystemFileIndex {
  const TerminalMacosMetadataFileIndex();

  @override
  TerminalSystemFileIndexOperation start(TerminalFileSearchQuery query) =>
      _TerminalMacosMetadataFileIndexOperation(query);

  static String metadataExpression(TerminalFileSearchQuery query) => query.terms
      .map((String term) => 'kMDItemFSName == "*${_escapeTerm(term)}*"cd')
      .map((String predicate) => '($predicate)')
      .join(' && ');

  static String _escapeTerm(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('*', r'\*')
      .replaceAll('?', r'\?');
}

final class _TerminalMacosMetadataFileIndexOperation
    implements TerminalSystemFileIndexOperation {
  _TerminalMacosMetadataFileIndexOperation(TerminalFileSearchQuery query) {
    _result = _run(query);
  }

  Process? _process;
  bool _cancelled = false;
  late final Future<TerminalSystemFileIndexSnapshot> _result;

  @override
  Future<TerminalSystemFileIndexSnapshot> get result => _result;

  @override
  void cancel() {
    _cancelled = true;
    _process?.kill(ProcessSignal.sigkill);
  }

  Future<TerminalSystemFileIndexSnapshot> _run(
    TerminalFileSearchQuery query,
  ) async {
    Timer? deadline;
    try {
      final Process process = await Process.start('/usr/bin/mdfind', <String>[
        '-0',
        TerminalMacosMetadataFileIndex.metadataExpression(query),
      ]);
      _process = process;
      if (_cancelled) process.kill(ProcessSignal.sigkill);
      deadline = Timer(TerminalFileSearchLimits.systemIndexDeadline, () {
        process.kill(ProcessSignal.sigkill);
      });
      unawaited(process.stderr.drain<void>());
      final BytesBuilder bytes = BytesBuilder(copy: false);
      var overflow = false;
      await for (final List<int> chunk in process.stdout) {
        if (_cancelled) break;
        final int remaining =
            TerminalFileSearchLimits.maximumSystemIndexOutputBytes -
            bytes.length;
        if (remaining <= 0) {
          overflow = true;
          process.kill(ProcessSignal.sigkill);
          break;
        }
        if (chunk.length > remaining) {
          bytes.add(chunk.take(remaining).toList(growable: false));
          overflow = true;
          process.kill(ProcessSignal.sigkill);
          break;
        }
        bytes.add(chunk);
      }
      final int exitCode = await process.exitCode;
      if (_cancelled) {
        return TerminalSystemFileIndexSnapshot(
          disposition: TerminalSystemFileIndexDisposition.cancelled,
          paths: const <String>[],
        );
      }
      final List<String> paths = _decodePaths(bytes.takeBytes());
      return TerminalSystemFileIndexSnapshot(
        disposition: overflow
            ? TerminalSystemFileIndexDisposition.partial
            : exitCode == 0
            ? TerminalSystemFileIndexDisposition.complete
            : paths.isEmpty
            ? TerminalSystemFileIndexDisposition.unavailable
            : TerminalSystemFileIndexDisposition.partial,
        paths: paths,
      );
    } on Object {
      return TerminalSystemFileIndexSnapshot(
        disposition: _cancelled
            ? TerminalSystemFileIndexDisposition.cancelled
            : TerminalSystemFileIndexDisposition.unavailable,
        paths: const <String>[],
      );
    } finally {
      deadline?.cancel();
      _process = null;
    }
  }

  static List<String> _decodePaths(Uint8List bytes) {
    final List<String> paths = <String>[];
    var start = 0;
    for (var index = 0; index <= bytes.length; index++) {
      if (index != bytes.length && bytes[index] != 0) continue;
      if (index > start) {
        try {
          final String value = utf8.decode(bytes.sublist(start, index));
          final String? normalized = TerminalLocalPathPolicy.normalizeAbsolute(
            value,
          );
          if (normalized != null) paths.add(normalized);
        } on FormatException {
          // Invalid native filename bytes are not safe display/search results.
        }
      }
      start = index + 1;
      if (paths.length >= TerminalFileSearchLimits.maximumSystemIndexResults) {
        break;
      }
    }
    return paths;
  }
}

final class TerminalFileSearchOperation {
  TerminalFileSearchOperation._(this.result, this._owner);

  final Future<TerminalFileSearchSnapshot> result;
  final _TerminalFileSearchOwner _owner;

  void cancel() => _owner.cancel();
}

typedef TerminalFileSearchProgress = void Function(
  TerminalFileSearchSnapshot snapshot,
);
typedef TerminalFileSearchPathSnapshot =
    Future<TerminalDirectoryEntrySnapshot?> Function(String path);

/// Progressive bounded search: cwd, recent roots, explicit roots, then index.
final class TerminalFileSearchService {
  const TerminalFileSearchService({
    TerminalDirectorySnapshotService directorySnapshots =
        const TerminalDirectorySnapshotService(),
    TerminalSystemFileIndex systemIndex =
        const TerminalMacosMetadataFileIndex(),
    TerminalFileSearchPathSnapshot pathSnapshot = _localPathSnapshot,
  }) : _directorySnapshots = directorySnapshots,
       _systemIndex = systemIndex,
       _pathSnapshot = pathSnapshot;

  final TerminalDirectorySnapshotService _directorySnapshots;
  final TerminalSystemFileIndex _systemIndex;
  final TerminalFileSearchPathSnapshot _pathSnapshot;

  TerminalFileSearchOperation start(
    TerminalFileSearchRequest request, {
    TerminalFileSearchProgress? onProgress,
  }) {
    final _TerminalFileSearchOwner owner = _TerminalFileSearchOwner(
      request: request,
      directorySnapshots: _directorySnapshots,
      systemIndex: _systemIndex,
      pathSnapshot: _pathSnapshot,
      onProgress: onProgress,
    );
    return TerminalFileSearchOperation._(owner.run(), owner);
  }

  static Future<TerminalDirectoryEntrySnapshot?> _localPathSnapshot(
    String path,
  ) async {
    try {
      final FileSystemEntityType type = await FileSystemEntity.type(
        path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) return null;
      final String name = path == '/'
          ? '/'
          : path.substring(path.lastIndexOf('/') + 1);
      if (!TerminalLocalPathPolicy.isSafeName(name)) return null;
      return TerminalDirectoryEntrySnapshot(
        name: name,
        path: path,
        kind: switch (type) {
          FileSystemEntityType.directory =>
            TerminalDirectoryEntryKind.directory,
          FileSystemEntityType.file => TerminalDirectoryEntryKind.file,
          FileSystemEntityType.link => TerminalDirectoryEntryKind.symbolicLink,
          _ => TerminalDirectoryEntryKind.other,
        },
        isHidden: name.startsWith('.'),
        metadata: const TerminalDirectoryEntryMetadataSnapshot.unavailable(),
      );
    } on FileSystemException {
      return null;
    }
  }
}

final class _TerminalFileSearchOwner {
  _TerminalFileSearchOwner({
    required this.request,
    required this.directorySnapshots,
    required this.systemIndex,
    required this.pathSnapshot,
    required this.onProgress,
  }) {
    _deadline = Timer(TerminalFileSearchLimits.deadline, cancel);
  }

  final TerminalFileSearchRequest request;
  final TerminalDirectorySnapshotService directorySnapshots;
  final TerminalSystemFileIndex systemIndex;
  final TerminalFileSearchPathSnapshot pathSnapshot;
  final TerminalFileSearchProgress? onProgress;
  final List<TerminalFileSearchResult> _results = <TerminalFileSearchResult>[];
  final Map<TerminalFileSearchSource, TerminalFileSearchCoverageDisposition>
  _coverage = <TerminalFileSearchSource, TerminalFileSearchCoverageDisposition>{
    for (final TerminalFileSearchSource source
        in TerminalFileSearchSource.values)
      source: TerminalFileSearchCoverageDisposition.searching,
  };
  final Map<TerminalFileSearchSource, int> _rootCounts =
      <TerminalFileSearchSource, int>{};
  final Set<String> _paths = <String>{};
  late final Timer _deadline;
  TerminalDirectorySnapshotOperation? _directoryOperation;
  TerminalSystemFileIndexOperation? _indexOperation;
  bool _cancelled = false;
  var _scanned = 0;
  var _directoryCount = 0;
  var _omitted = 0;
  var _pathBytes = 0;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _directoryOperation?.cancel();
    _indexOperation?.cancel();
  }

  Future<TerminalFileSearchSnapshot> run() async {
    try {
      await _searchRoots(<String>[
        request.currentRoot,
      ], TerminalFileSearchSource.currentSubtree);
      if (!_cancelled) {
        await _searchRoots(
          request.recentRoots,
          TerminalFileSearchSource.recent,
        );
      }
      if (!_cancelled) {
        await _searchRoots(
          request.explicitRoots,
          TerminalFileSearchSource.explicit,
        );
      }
      if (!_cancelled) await _searchSystemIndex();
      if (_cancelled) {
        for (final TerminalFileSearchSource source
            in TerminalFileSearchSource.values) {
          if (_coverage[source] ==
              TerminalFileSearchCoverageDisposition.searching) {
            _coverage[source] = TerminalFileSearchCoverageDisposition.partial;
          }
        }
      }
      final TerminalFileSearchSnapshot result = _snapshot(
        isComplete: !_cancelled,
      );
      if (!_cancelled) onProgress?.call(result);
      return result;
    } finally {
      _deadline.cancel();
      _directoryOperation = null;
      _indexOperation = null;
    }
  }

  Future<void> _searchRoots(
    List<String> roots,
    TerminalFileSearchSource source,
  ) async {
    _rootCounts[source] = roots.length;
    if (roots.isEmpty) {
      _coverage[source] = TerminalFileSearchCoverageDisposition.complete;
      _publish();
      return;
    }
    final List<_TerminalSearchDirectory> queue = <_TerminalSearchDirectory>[
      for (final String root in roots)
        _TerminalSearchDirectory(path: root, depth: 0),
    ];
    var sourceDirectoryCount = 0;
    var partial = false;
    while (queue.isNotEmpty && !_cancelled) {
      if (_results.length >= TerminalFileSearchLimits.maximumResults ||
          _directoryCount >= TerminalFileSearchLimits.maximumDirectories ||
          _scanned >= TerminalFileSearchLimits.maximumScannedEntries) {
        partial = true;
        break;
      }
      final _TerminalSearchDirectory directory = queue.removeAt(0);
      _directoryCount++;
      sourceDirectoryCount++;
      final int remainingScans =
          TerminalFileSearchLimits.maximumScannedEntries - _scanned;
      if (remainingScans <= 1) {
        partial = true;
        break;
      }
      final int entryBudget = remainingScans - 1 < 128
          ? remainingScans - 1
          : 128;
      final TerminalDirectorySnapshotOperation operation = directorySnapshots
          .start(
            TerminalDirectorySnapshotRequest(
              rootPath: directory.path,
              generation: request.generation,
              maximumEntries: entryBudget,
              maximumTotalPathUtf8Bytes: 128 * 1024,
              deadline: const Duration(milliseconds: 500),
            ),
          );
      _directoryOperation = operation;
      final TerminalDirectorySnapshot snapshot = await operation.result;
      if (_cancelled ||
          snapshot.disposition ==
              TerminalDirectorySnapshotDisposition.cancelled) {
        break;
      }
      _scanned += snapshot.scannedEntryCount;
      if (snapshot.disposition !=
          TerminalDirectorySnapshotDisposition.complete) {
        partial = true;
      }
      for (final TerminalDirectoryEntrySnapshot entry in snapshot.entries) {
        if (_cancelled) break;
        if (request.query.matches(entry.name, entry.path)) {
          _add(entry, source, directory.depth + 1);
        }
        if (entry.kind == TerminalDirectoryEntryKind.directory &&
            directory.depth < TerminalFileSearchLimits.maximumDepth &&
            queue.length < TerminalFileSearchLimits.maximumDirectories) {
          queue.add(
            _TerminalSearchDirectory(
              path: entry.path,
              depth: directory.depth + 1,
            ),
          );
        }
      }
      if (sourceDirectoryCount % 16 == 0) _publish();
    }
    _coverage[source] = _cancelled
        ? TerminalFileSearchCoverageDisposition.partial
        : partial
        ? TerminalFileSearchCoverageDisposition.partial
        : TerminalFileSearchCoverageDisposition.complete;
    _publish();
  }

  Future<void> _searchSystemIndex() async {
    _rootCounts[TerminalFileSearchSource.systemIndex] = 1;
    if (_results.length >= TerminalFileSearchLimits.maximumResults) {
      _coverage[TerminalFileSearchSource.systemIndex] =
          TerminalFileSearchCoverageDisposition.partial;
      _publish();
      return;
    }
    late final TerminalSystemFileIndexSnapshot snapshot;
    try {
      final TerminalSystemFileIndexOperation operation = systemIndex.start(
        request.query,
      );
      _indexOperation = operation;
      snapshot = await operation.result;
    } on Object {
      if (_cancelled) return;
      _coverage[TerminalFileSearchSource.systemIndex] =
          TerminalFileSearchCoverageDisposition.unavailable;
      _publish();
      return;
    }
    if (_cancelled ||
        snapshot.disposition == TerminalSystemFileIndexDisposition.cancelled) {
      return;
    }
    var pathFailure = false;
    for (final String path in snapshot.paths) {
      if (_cancelled ||
          _results.length >= TerminalFileSearchLimits.maximumResults) {
        break;
      }
      if (TerminalLocalPathPolicy.normalizeAbsolute(path) != path) continue;
      final String name = path == '/'
          ? '/'
          : path.substring(path.lastIndexOf('/') + 1);
      if (!TerminalLocalPathPolicy.isSafeName(name) ||
          !request.query.matches(name, path)) {
        continue;
      }
      TerminalDirectoryEntrySnapshot? entry;
      try {
        entry = await pathSnapshot(path);
      } on Object {
        pathFailure = true;
        continue;
      }
      if (_cancelled ||
          entry == null ||
          entry.path != path ||
          entry.name != name ||
          !TerminalLocalPathPolicy.isSafeName(entry.name)) {
        continue;
      }
      _add(entry, TerminalFileSearchSource.systemIndex, _pathDepth(path));
    }
    _coverage[TerminalFileSearchSource.systemIndex] =
        switch (snapshot.disposition) {
          TerminalSystemFileIndexDisposition.complete =>
            pathFailure
                ? TerminalFileSearchCoverageDisposition.partial
                : TerminalFileSearchCoverageDisposition.complete,
          TerminalSystemFileIndexDisposition.partial =>
            TerminalFileSearchCoverageDisposition.partial,
          TerminalSystemFileIndexDisposition.unavailable =>
            TerminalFileSearchCoverageDisposition.unavailable,
          TerminalSystemFileIndexDisposition.cancelled =>
            TerminalFileSearchCoverageDisposition.partial,
        };
    _publish();
  }

  void _add(
    TerminalDirectoryEntrySnapshot entry,
    TerminalFileSearchSource source,
    int depth,
  ) {
    if (!_paths.add(entry.path)) return;
    final int bytes = utf8.encode(entry.path).length;
    if (_results.length >= TerminalFileSearchLimits.maximumResults ||
        _pathBytes >
            TerminalFileSearchLimits.maximumRetainedPathUtf8Bytes - bytes) {
      _omitted++;
      return;
    }
    _pathBytes += bytes;
    _results.add(
      TerminalFileSearchResult(entry: entry, source: source, depth: depth),
    );
    _results.sort(_compareResults);
  }

  int _compareResults(
    TerminalFileSearchResult left,
    TerminalFileSearchResult right,
  ) {
    int compare(bool leftValue, bool rightValue) => leftValue == rightValue
        ? 0
        : leftValue
        ? -1
        : 1;
    final String query = request.query.terms.join(' ');
    final String leftName = left.entry.name.toLowerCase();
    final String rightName = right.entry.name.toLowerCase();
    var order = compare(leftName == query, rightName == query);
    if (order != 0) return order;
    order = compare(leftName.startsWith(query), rightName.startsWith(query));
    if (order != 0) return order;
    order = compare(leftName.contains(query), rightName.contains(query));
    if (order != 0) return order;
    order = left.source.index.compareTo(right.source.index);
    if (order != 0) return order;
    order = left.depth.compareTo(right.depth);
    if (order != 0) return order;
    return left.entry.path.compareTo(right.entry.path);
  }

  void _publish() {
    if (!_cancelled) onProgress?.call(_snapshot(isComplete: false));
  }

  TerminalFileSearchSnapshot _snapshot({required bool isComplete}) =>
      TerminalFileSearchSnapshot(
        generation: request.generation,
        query: request.query,
        results: _results,
        coverage: <TerminalFileSearchCoverage>[
          for (final TerminalFileSearchSource source
              in TerminalFileSearchSource.values)
            TerminalFileSearchCoverage(
              source: source,
              disposition: _coverage[source]!,
              rootCount: _rootCounts[source] ?? 0,
            ),
        ],
        isComplete: isComplete,
        wasCancelled: _cancelled,
        scannedEntryCount: _scanned,
        omittedResultCount: _omitted,
      );

  static int _pathDepth(String path) =>
      path.split('/').where((String component) => component.isNotEmpty).length;
}

final class _TerminalSearchDirectory {
  const _TerminalSearchDirectory({required this.path, required this.depth});

  final String path;
  final int depth;
}
