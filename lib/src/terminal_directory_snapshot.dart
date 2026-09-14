import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_pty_macos/dart_pty_macos.dart';

import 'terminal_core/terminal_session_metadata.dart';
import 'terminal_pane.dart';
import 'terminal_tab_presentation.dart';

abstract final class TerminalDirectorySnapshotLimits {
  static const int maximumEntries = 2048;
  static const int maximumScannedEntries = 4096;
  static const int maximumTotalPathUtf8Bytes = 1024 * 1024;
  static const int maximumNameUtf8Bytes = 1024;
  static const int maximumSymlinkTargetUtf8Bytes = 4096;
  static const int maximumIssues = 128;
  static const int maximumMetadataConcurrency = 16;
  static const Duration defaultDeadline = Duration(milliseconds: 1500);
  static const Duration maximumDeadline = Duration(seconds: 5);

  // The one-shot provider deliberately retains no cache and owns no watcher.
  // The visible tree owner may add both later behind separate bounded policy.
  static const int retainedSnapshotCapacity = 0;
  static const int fileSystemWatcherCapacity = 0;
}

enum TerminalWorkingDirectorySource { osc7, owningShell, launch }

enum TerminalWorkingDirectoryDisposition {
  available,
  remoteUnavailable,
  unavailable,
}

enum TerminalWorkingDirectoryIssueKind {
  sessionMismatch,
  unsafeReportedDirectory,
  processUnavailable,
  processIdentityMismatch,
  unsafeProcessDirectory,
  unsafeLaunchDirectory,
}

/// One generation-bound resolution of a pane's trusted local cwd.
final class TerminalWorkingDirectoryResolution {
  TerminalWorkingDirectoryResolution._({
    required this.sessionId,
    required this.generation,
    required this.disposition,
    required this.path,
    required this.source,
    required Iterable<TerminalWorkingDirectoryIssueKind> issues,
  }) : issues = List<TerminalWorkingDirectoryIssueKind>.unmodifiable(issues);

  final TerminalSessionId sessionId;
  final int generation;
  final TerminalWorkingDirectoryDisposition disposition;
  final String? path;
  final TerminalWorkingDirectorySource? source;
  final List<TerminalWorkingDirectoryIssueKind> issues;

  bool get isAvailable =>
      disposition == TerminalWorkingDirectoryDisposition.available;
}

/// Resolves local cwd authority without reading terminal text or running a
/// command in the PTY.
final class TerminalWorkingDirectoryResolver {
  const TerminalWorkingDirectoryResolver();

  TerminalWorkingDirectoryResolution resolve({
    required TerminalSessionId sessionId,
    required int generation,
    required TerminalPaneProcessSnapshot processSnapshot,
    required Uri? reportedWorkingDirectory,
    required PtyWorkingDirectorySnapshot? processWorkingDirectory,
    required String? launchWorkingDirectory,
  }) {
    if (generation <= 0) {
      throw ArgumentError.value(generation, 'generation', 'must be positive');
    }
    final List<TerminalWorkingDirectoryIssueKind> issues =
        <TerminalWorkingDirectoryIssueKind>[];
    if (processSnapshot.sessionId != sessionId) {
      issues.add(TerminalWorkingDirectoryIssueKind.sessionMismatch);
      return _unavailable(sessionId, generation, issues);
    }

    final Uri? reported = reportedWorkingDirectory;
    if (reported != null) {
      if (!TerminalSessionMetadata.isSafeWorkingDirectory(reported)) {
        issues.add(TerminalWorkingDirectoryIssueKind.unsafeReportedDirectory);
      } else if (reported.host.isNotEmpty &&
          reported.host.toLowerCase() != 'localhost') {
        return TerminalWorkingDirectoryResolution._(
          sessionId: sessionId,
          generation: generation,
          disposition: TerminalWorkingDirectoryDisposition.remoteUnavailable,
          path: null,
          source: null,
          issues: issues,
        );
      } else {
        final String? local = TerminalTabPresentationResolver.localFilePath(
          reported,
        );
        final String? normalized = TerminalLocalPathPolicy.normalizeAbsolute(
          local,
        );
        if (normalized != null) {
          return _available(
            sessionId,
            generation,
            normalized,
            TerminalWorkingDirectorySource.osc7,
            issues,
          );
        }
        issues.add(TerminalWorkingDirectoryIssueKind.unsafeReportedDirectory);
      }
    }

    final PtyWorkingDirectorySnapshot? processDirectory =
        processWorkingDirectory;
    final int? expectedProcessId = processSnapshot.childProcessId;
    if (processDirectory == null || !processDirectory.isAvailable) {
      issues.add(TerminalWorkingDirectoryIssueKind.processUnavailable);
    } else if (expectedProcessId == null ||
        processDirectory.processId != expectedProcessId) {
      issues.add(TerminalWorkingDirectoryIssueKind.processIdentityMismatch);
    } else {
      final String? normalized = TerminalLocalPathPolicy.normalizeAbsolute(
        processDirectory.path,
      );
      if (normalized != null) {
        return _available(
          sessionId,
          generation,
          normalized,
          TerminalWorkingDirectorySource.owningShell,
          issues,
        );
      }
      issues.add(TerminalWorkingDirectoryIssueKind.unsafeProcessDirectory);
    }

    final String? launch = TerminalLocalPathPolicy.normalizeAbsolute(
      launchWorkingDirectory,
    );
    if (launch != null) {
      return _available(
        sessionId,
        generation,
        launch,
        TerminalWorkingDirectorySource.launch,
        issues,
      );
    }
    if (launchWorkingDirectory != null) {
      issues.add(TerminalWorkingDirectoryIssueKind.unsafeLaunchDirectory);
    }
    return _unavailable(sessionId, generation, issues);
  }

  static TerminalWorkingDirectoryResolution _available(
    TerminalSessionId sessionId,
    int generation,
    String path,
    TerminalWorkingDirectorySource source,
    List<TerminalWorkingDirectoryIssueKind> issues,
  ) => TerminalWorkingDirectoryResolution._(
    sessionId: sessionId,
    generation: generation,
    disposition: TerminalWorkingDirectoryDisposition.available,
    path: path,
    source: source,
    issues: issues,
  );

  static TerminalWorkingDirectoryResolution _unavailable(
    TerminalSessionId sessionId,
    int generation,
    List<TerminalWorkingDirectoryIssueKind> issues,
  ) => TerminalWorkingDirectoryResolution._(
    sessionId: sessionId,
    generation: generation,
    disposition: TerminalWorkingDirectoryDisposition.unavailable,
    path: null,
    source: null,
    issues: issues,
  );
}

/// Shared lexical and display-safety policy for local filesystem authority.
abstract final class TerminalLocalPathPolicy {
  static String? normalizeAbsolute(String? value) {
    if (value == null ||
        value.length >
            TerminalSessionMetadata.maximumWorkingDirectoryUtf8Bytes ||
        !value.startsWith('/') ||
        !TerminalSessionMetadata.isSafeDisplayText(
          value,
          maximumUtf8Bytes:
              TerminalSessionMetadata.maximumWorkingDirectoryUtf8Bytes,
        )) {
      return null;
    }
    final List<String> components = <String>[];
    for (final String component in value.split('/')) {
      if (component.isEmpty || component == '.') continue;
      if (component == '..') {
        if (components.isEmpty) return null;
        components.removeLast();
        continue;
      }
      components.add(component);
    }
    return components.isEmpty ? '/' : '/${components.join('/')}';
  }

  static bool isSafeName(String value) =>
      value.isNotEmpty &&
      value.length <= TerminalDirectorySnapshotLimits.maximumNameUtf8Bytes &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      TerminalSessionMetadata.isSafeDisplayText(
        value,
        maximumUtf8Bytes: TerminalDirectorySnapshotLimits.maximumNameUtf8Bytes,
      );

  static bool isSafeSymlinkTarget(String value) =>
      value.isNotEmpty &&
      value.length <=
          TerminalDirectorySnapshotLimits.maximumSymlinkTargetUtf8Bytes &&
      TerminalSessionMetadata.isSafeDisplayText(
        value,
        maximumUtf8Bytes:
            TerminalDirectorySnapshotLimits.maximumSymlinkTargetUtf8Bytes,
      );
}

enum TerminalDirectoryEntryKind { directory, file, symbolicLink, other }

enum TerminalDirectoryMetadataDisposition { available, unavailable }

final class TerminalDirectoryFileSystemEntry {
  const TerminalDirectoryFileSystemEntry({
    required this.name,
    required this.path,
    required this.kind,
  });

  final String name;
  final String path;
  final TerminalDirectoryEntryKind kind;
}

final class TerminalDirectoryFileSystemMetadata {
  const TerminalDirectoryFileSystemMetadata({
    this.mode,
    this.size,
    this.modifiedMicrosecondsSinceEpoch,
    this.ownerUserId,
    this.ownerGroupId,
    this.symlinkTarget,
  });

  final int? mode;
  final int? size;
  final int? modifiedMicrosecondsSinceEpoch;
  final int? ownerUserId;
  final int? ownerGroupId;
  final String? symlinkTarget;
}

abstract interface class TerminalDirectoryFileSystem {
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath);

  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  );
}

/// Async dart:io adapter. Listing is one level only and never follows links.
final class TerminalIoDirectoryFileSystem
    implements TerminalDirectoryFileSystem {
  const TerminalIoDirectoryFileSystem();

  @override
  Stream<TerminalDirectoryFileSystemEntry> list(String rootPath) async* {
    await for (final FileSystemEntity entity in Directory(
      rootPath,
    ).list(recursive: false, followLinks: false)) {
      final String path = entity.path;
      final int separator = path.lastIndexOf('/');
      final String name = separator < 0 ? path : path.substring(separator + 1);
      yield TerminalDirectoryFileSystemEntry(
        name: name,
        path: path,
        kind: switch (entity) {
          Directory() => TerminalDirectoryEntryKind.directory,
          File() => TerminalDirectoryEntryKind.file,
          Link() => TerminalDirectoryEntryKind.symbolicLink,
          _ => TerminalDirectoryEntryKind.other,
        },
      );
    }
  }

  @override
  Future<TerminalDirectoryFileSystemMetadata> metadata(
    TerminalDirectoryFileSystemEntry entry,
  ) async {
    if (entry.kind == TerminalDirectoryEntryKind.symbolicLink) {
      return TerminalDirectoryFileSystemMetadata(
        symlinkTarget: await Link(entry.path).target(),
      );
    }
    final FileStat stat = await FileStat.stat(entry.path);
    if (stat.type == FileSystemEntityType.notFound ||
        !_matchesKind(entry.kind, stat.type)) {
      throw FileSystemException(
        'directory entry changed during metadata observation',
        entry.path,
      );
    }
    return TerminalDirectoryFileSystemMetadata(
      mode: stat.mode,
      size: stat.size,
      modifiedMicrosecondsSinceEpoch: stat.modified.microsecondsSinceEpoch,
    );
  }

  static bool _matchesKind(
    TerminalDirectoryEntryKind kind,
    FileSystemEntityType type,
  ) => switch (kind) {
    TerminalDirectoryEntryKind.directory =>
      type == FileSystemEntityType.directory,
    TerminalDirectoryEntryKind.file => type == FileSystemEntityType.file,
    TerminalDirectoryEntryKind.symbolicLink =>
      type == FileSystemEntityType.link,
    TerminalDirectoryEntryKind.other =>
      type == FileSystemEntityType.pipe ||
          type == FileSystemEntityType.unixDomainSock,
  };
}

enum TerminalDirectorySnapshotDisposition {
  complete,
  partial,
  unavailable,
  cancelled,
}

enum TerminalDirectoryIssueKind {
  invalidRoot,
  invalidEntry,
  duplicateEntry,
  permissionDenied,
  notFound,
  ioFailure,
  metadataUnavailable,
  entryLimitReached,
  scanLimitReached,
  pathByteLimitReached,
  deadlineExceeded,
  cancelled,
  issueLimitReached,
}

final class TerminalDirectoryIssue {
  const TerminalDirectoryIssue({required this.kind, this.systemError});

  final TerminalDirectoryIssueKind kind;
  final int? systemError;
}

final class TerminalDirectoryEntryMetadataSnapshot {
  const TerminalDirectoryEntryMetadataSnapshot._({
    required this.disposition,
    required this.mode,
    required this.size,
    required this.modifiedMicrosecondsSinceEpoch,
    required this.ownerUserId,
    required this.ownerGroupId,
    required this.symlinkTarget,
    required this.systemError,
  });

  factory TerminalDirectoryEntryMetadataSnapshot.available(
    TerminalDirectoryFileSystemMetadata metadata,
  ) => TerminalDirectoryEntryMetadataSnapshot._(
    disposition: TerminalDirectoryMetadataDisposition.available,
    mode: metadata.mode,
    size: metadata.size,
    modifiedMicrosecondsSinceEpoch: metadata.modifiedMicrosecondsSinceEpoch,
    ownerUserId: metadata.ownerUserId,
    ownerGroupId: metadata.ownerGroupId,
    symlinkTarget: metadata.symlinkTarget,
    systemError: null,
  );

  const TerminalDirectoryEntryMetadataSnapshot.unavailable({this.systemError})
    : disposition = TerminalDirectoryMetadataDisposition.unavailable,
      mode = null,
      size = null,
      modifiedMicrosecondsSinceEpoch = null,
      ownerUserId = null,
      ownerGroupId = null,
      symlinkTarget = null;

  final TerminalDirectoryMetadataDisposition disposition;
  final int? mode;
  final int? size;
  final int? modifiedMicrosecondsSinceEpoch;
  final int? ownerUserId;
  final int? ownerGroupId;
  final String? symlinkTarget;
  final int? systemError;
}

final class TerminalDirectoryEntrySnapshot {
  const TerminalDirectoryEntrySnapshot({
    required this.name,
    required this.path,
    required this.kind,
    required this.isHidden,
    required this.metadata,
  });

  final String name;
  final String path;
  final TerminalDirectoryEntryKind kind;
  final bool isHidden;
  final TerminalDirectoryEntryMetadataSnapshot metadata;
}

final class TerminalDirectorySnapshot {
  TerminalDirectorySnapshot._({
    required this.generation,
    required this.rootPath,
    required this.disposition,
    required Iterable<TerminalDirectoryEntrySnapshot> entries,
    required Iterable<TerminalDirectoryIssue> issues,
    required this.scannedEntryCount,
    required this.omittedEntryCount,
    required this.metadataFailureCount,
    required this.totalPathUtf8Bytes,
  }) : entries = List<TerminalDirectoryEntrySnapshot>.unmodifiable(entries),
       issues = List<TerminalDirectoryIssue>.unmodifiable(issues);

  final int generation;
  final String? rootPath;
  final TerminalDirectorySnapshotDisposition disposition;
  final List<TerminalDirectoryEntrySnapshot> entries;
  final List<TerminalDirectoryIssue> issues;
  final int scannedEntryCount;
  final int omittedEntryCount;
  final int metadataFailureCount;
  final int totalPathUtf8Bytes;
}

final class TerminalDirectorySnapshotRequest {
  TerminalDirectorySnapshotRequest({
    required this.rootPath,
    required this.generation,
    this.deadline = TerminalDirectorySnapshotLimits.defaultDeadline,
    this.metadataConcurrency =
        TerminalDirectorySnapshotLimits.maximumMetadataConcurrency,
  }) {
    if (generation <= 0) {
      throw ArgumentError.value(generation, 'generation', 'must be positive');
    }
    if (deadline <= Duration.zero ||
        deadline > TerminalDirectorySnapshotLimits.maximumDeadline) {
      throw ArgumentError.value(deadline, 'deadline', 'must be in bounds');
    }
    if (metadataConcurrency <= 0 ||
        metadataConcurrency >
            TerminalDirectorySnapshotLimits.maximumMetadataConcurrency) {
      throw ArgumentError.value(
        metadataConcurrency,
        'metadataConcurrency',
        'must be in bounds',
      );
    }
  }

  final String rootPath;
  final int generation;
  final Duration deadline;
  final int metadataConcurrency;
}

final class TerminalDirectorySnapshotOperation {
  TerminalDirectorySnapshotOperation._(this.result, this._token);

  final Future<TerminalDirectorySnapshot> result;
  final _TerminalDirectoryCancellationToken _token;

  bool get isCancelled => _token.reason == _TerminalDirectoryStop.cancelled;

  void cancel() => _token.cancel();
}

/// Starts bounded, one-level directory observations with explicit ownership.
final class TerminalDirectorySnapshotService {
  const TerminalDirectorySnapshotService({
    TerminalDirectoryFileSystem fileSystem =
        const TerminalIoDirectoryFileSystem(),
  }) : _fileSystem = fileSystem;

  final TerminalDirectoryFileSystem _fileSystem;

  TerminalDirectorySnapshotOperation start(
    TerminalDirectorySnapshotRequest request,
  ) {
    final _TerminalDirectoryCancellationToken token =
        _TerminalDirectoryCancellationToken(request.deadline);
    final Future<TerminalDirectorySnapshot> result = _snapshot(
      request,
      token,
    ).whenComplete(token.finish);
    return TerminalDirectorySnapshotOperation._(result, token);
  }

  Future<TerminalDirectorySnapshot> _snapshot(
    TerminalDirectorySnapshotRequest request,
    _TerminalDirectoryCancellationToken token,
  ) async {
    final String? root = TerminalLocalPathPolicy.normalizeAbsolute(
      request.rootPath,
    );
    final _TerminalDirectoryIssueCollector issues =
        _TerminalDirectoryIssueCollector();
    if (root == null) {
      issues.add(TerminalDirectoryIssueKind.invalidRoot);
      return _result(
        request: request,
        rootPath: null,
        disposition: TerminalDirectorySnapshotDisposition.unavailable,
        entries: const <TerminalDirectoryEntrySnapshot>[],
        issues: issues,
      );
    }

    final List<TerminalDirectoryFileSystemEntry> candidates =
        <TerminalDirectoryFileSystemEntry>[];
    final Set<String> paths = <String>{};
    var scanned = 0;
    var omitted = 0;
    var pathBytes = 0;
    StreamIterator<TerminalDirectoryFileSystemEntry>? iterator;
    try {
      iterator = StreamIterator<TerminalDirectoryFileSystemEntry>(
        _fileSystem.list(root),
      );
      while (true) {
        final _TerminalDirectoryWait<bool> next = await token.waitFor(
          iterator.moveNext(),
        );
        if (next.isStopped) break;
        if (!next.value!) break;
        scanned++;
        if (scanned > TerminalDirectorySnapshotLimits.maximumScannedEntries) {
          omitted++;
          issues.add(TerminalDirectoryIssueKind.scanLimitReached);
          break;
        }
        final TerminalDirectoryFileSystemEntry candidate = iterator.current;
        if (!_isDirectSafeChild(root, candidate)) {
          omitted++;
          issues.add(TerminalDirectoryIssueKind.invalidEntry);
          continue;
        }
        if (!paths.add(candidate.path)) {
          omitted++;
          issues.add(TerminalDirectoryIssueKind.duplicateEntry);
          continue;
        }
        if (candidates.length >=
            TerminalDirectorySnapshotLimits.maximumEntries) {
          omitted++;
          issues.add(TerminalDirectoryIssueKind.entryLimitReached);
          break;
        }
        final int candidateBytes = utf8.encode(candidate.path).length;
        if (pathBytes >
            TerminalDirectorySnapshotLimits.maximumTotalPathUtf8Bytes -
                candidateBytes) {
          omitted++;
          issues.add(TerminalDirectoryIssueKind.pathByteLimitReached);
          break;
        }
        candidates.add(candidate);
        pathBytes += candidateBytes;
      }
    } on FileSystemException catch (error) {
      issues.add(_issueForFileSystemError(error), _errorCode(error));
      if (candidates.isEmpty) {
        return _result(
          request: request,
          rootPath: root,
          disposition: TerminalDirectorySnapshotDisposition.unavailable,
          entries: const <TerminalDirectoryEntrySnapshot>[],
          issues: issues,
          scannedEntryCount: scanned,
          omittedEntryCount: omitted,
          totalPathUtf8Bytes: pathBytes,
        );
      }
    } on Object {
      issues.add(TerminalDirectoryIssueKind.ioFailure);
      if (candidates.isEmpty) {
        return _result(
          request: request,
          rootPath: root,
          disposition: TerminalDirectorySnapshotDisposition.unavailable,
          entries: const <TerminalDirectoryEntrySnapshot>[],
          issues: issues,
          scannedEntryCount: scanned,
          omittedEntryCount: omitted,
          totalPathUtf8Bytes: pathBytes,
        );
      }
    } finally {
      if (iterator != null) unawaited(iterator.cancel());
    }

    if (token.reason == _TerminalDirectoryStop.cancelled) {
      return _cancelled(request, root, scanned, omitted, pathBytes);
    }

    candidates.sort(_compareEntries);
    final List<TerminalDirectoryEntryMetadataSnapshot?> metadata =
        List<TerminalDirectoryEntryMetadataSnapshot?>.filled(
          candidates.length,
          null,
        );
    var nextMetadataIndex = 0;
    var metadataFailures = 0;

    Future<void> worker() async {
      while (!token.isStopped) {
        final int index = nextMetadataIndex++;
        if (index >= candidates.length) return;
        try {
          final _TerminalDirectoryWait<TerminalDirectoryFileSystemMetadata>
          observed = await token.waitFor(
            _fileSystem.metadata(candidates[index]),
          );
          if (observed.isStopped) return;
          final TerminalDirectoryFileSystemMetadata value = observed.value!;
          final String? target = value.symlinkTarget;
          if (target != null &&
              !TerminalLocalPathPolicy.isSafeSymlinkTarget(target)) {
            metadata[index] =
                const TerminalDirectoryEntryMetadataSnapshot.unavailable();
            metadataFailures++;
            issues.add(TerminalDirectoryIssueKind.metadataUnavailable);
            continue;
          }
          metadata[index] = TerminalDirectoryEntryMetadataSnapshot.available(
            value,
          );
        } on FileSystemException catch (error) {
          metadata[index] = TerminalDirectoryEntryMetadataSnapshot.unavailable(
            systemError: _errorCode(error),
          );
          metadataFailures++;
          issues.add(
            TerminalDirectoryIssueKind.metadataUnavailable,
            _errorCode(error),
          );
        } on Object {
          metadata[index] =
              const TerminalDirectoryEntryMetadataSnapshot.unavailable();
          metadataFailures++;
          issues.add(TerminalDirectoryIssueKind.metadataUnavailable);
        }
      }
    }

    final int workers = request.metadataConcurrency < candidates.length
        ? request.metadataConcurrency
        : candidates.length;
    await Future.wait<void>(<Future<void>>[
      for (var index = 0; index < workers; index++) worker(),
    ]);

    if (token.reason == _TerminalDirectoryStop.cancelled) {
      return _cancelled(request, root, scanned, omitted, pathBytes);
    }
    if (token.reason == _TerminalDirectoryStop.deadline) {
      issues.add(TerminalDirectoryIssueKind.deadlineExceeded);
    }

    final List<TerminalDirectoryEntrySnapshot> entries =
        <TerminalDirectoryEntrySnapshot>[
          for (var index = 0; index < candidates.length; index++)
            TerminalDirectoryEntrySnapshot(
              name: candidates[index].name,
              path: candidates[index].path,
              kind: candidates[index].kind,
              isHidden: candidates[index].name.startsWith('.'),
              metadata:
                  metadata[index] ??
                  const TerminalDirectoryEntryMetadataSnapshot.unavailable(),
            ),
        ];
    final bool partial =
        issues.isNotEmpty || metadataFailures != 0 || token.isStopped;
    return _result(
      request: request,
      rootPath: root,
      disposition: partial
          ? TerminalDirectorySnapshotDisposition.partial
          : TerminalDirectorySnapshotDisposition.complete,
      entries: entries,
      issues: issues,
      scannedEntryCount: scanned,
      omittedEntryCount: omitted,
      metadataFailureCount: metadataFailures,
      totalPathUtf8Bytes: pathBytes,
    );
  }

  static TerminalDirectorySnapshot _cancelled(
    TerminalDirectorySnapshotRequest request,
    String root,
    int scanned,
    int omitted,
    int pathBytes,
  ) => TerminalDirectorySnapshot._(
    generation: request.generation,
    rootPath: root,
    disposition: TerminalDirectorySnapshotDisposition.cancelled,
    entries: const <TerminalDirectoryEntrySnapshot>[],
    issues: const <TerminalDirectoryIssue>[
      TerminalDirectoryIssue(kind: TerminalDirectoryIssueKind.cancelled),
    ],
    scannedEntryCount: scanned,
    omittedEntryCount: omitted,
    metadataFailureCount: 0,
    totalPathUtf8Bytes: pathBytes,
  );

  static TerminalDirectorySnapshot _result({
    required TerminalDirectorySnapshotRequest request,
    required String? rootPath,
    required TerminalDirectorySnapshotDisposition disposition,
    required Iterable<TerminalDirectoryEntrySnapshot> entries,
    required _TerminalDirectoryIssueCollector issues,
    int scannedEntryCount = 0,
    int omittedEntryCount = 0,
    int metadataFailureCount = 0,
    int totalPathUtf8Bytes = 0,
  }) => TerminalDirectorySnapshot._(
    generation: request.generation,
    rootPath: rootPath,
    disposition: disposition,
    entries: entries,
    issues: issues.values,
    scannedEntryCount: scannedEntryCount,
    omittedEntryCount: omittedEntryCount,
    metadataFailureCount: metadataFailureCount,
    totalPathUtf8Bytes: totalPathUtf8Bytes,
  );

  static bool _isDirectSafeChild(
    String root,
    TerminalDirectoryFileSystemEntry entry,
  ) {
    if (!TerminalLocalPathPolicy.isSafeName(entry.name)) return false;
    final String expected = root == '/'
        ? '/${entry.name}'
        : '$root/${entry.name}';
    return entry.path == expected &&
        TerminalLocalPathPolicy.normalizeAbsolute(entry.path) == entry.path;
  }

  static int _compareEntries(
    TerminalDirectoryFileSystemEntry left,
    TerminalDirectoryFileSystemEntry right,
  ) {
    final int kind = _kindOrder(left.kind).compareTo(_kindOrder(right.kind));
    if (kind != 0) return kind;
    final int folded = left.name.toLowerCase().compareTo(
      right.name.toLowerCase(),
    );
    return folded != 0 ? folded : left.name.compareTo(right.name);
  }

  static int _kindOrder(TerminalDirectoryEntryKind kind) => switch (kind) {
    TerminalDirectoryEntryKind.directory => 0,
    TerminalDirectoryEntryKind.file => 1,
    TerminalDirectoryEntryKind.symbolicLink => 2,
    TerminalDirectoryEntryKind.other => 3,
  };

  static TerminalDirectoryIssueKind _issueForFileSystemError(
    FileSystemException error,
  ) => switch (_errorCode(error)) {
    1 || 13 => TerminalDirectoryIssueKind.permissionDenied,
    2 => TerminalDirectoryIssueKind.notFound,
    _ => TerminalDirectoryIssueKind.ioFailure,
  };

  static int? _errorCode(FileSystemException error) => error.osError?.errorCode;
}

final class _TerminalDirectoryIssueCollector {
  final List<TerminalDirectoryIssue> _values = <TerminalDirectoryIssue>[];
  bool _overflowRecorded = false;

  List<TerminalDirectoryIssue> get values =>
      List<TerminalDirectoryIssue>.unmodifiable(_values);
  bool get isNotEmpty => _values.isNotEmpty;

  void add(TerminalDirectoryIssueKind kind, [int? systemError]) {
    if (_values.any(
      (TerminalDirectoryIssue value) =>
          value.kind == kind && value.systemError == systemError,
    )) {
      return;
    }
    if (_values.length < TerminalDirectorySnapshotLimits.maximumIssues) {
      _values.add(TerminalDirectoryIssue(kind: kind, systemError: systemError));
      return;
    }
    if (_overflowRecorded) return;
    _overflowRecorded = true;
    _values[TerminalDirectorySnapshotLimits.maximumIssues -
        1] = const TerminalDirectoryIssue(
      kind: TerminalDirectoryIssueKind.issueLimitReached,
    );
  }
}

enum _TerminalDirectoryStop { cancelled, deadline }

final class _TerminalDirectoryCancellationToken {
  _TerminalDirectoryCancellationToken(Duration deadline) {
    _timer = Timer(deadline, () => _stop(_TerminalDirectoryStop.deadline));
  }

  final Completer<_TerminalDirectoryStop> _stopped =
      Completer<_TerminalDirectoryStop>();
  Timer? _timer;
  _TerminalDirectoryStop? reason;
  bool _isFinished = false;

  bool get isStopped => reason != null;

  Future<_TerminalDirectoryWait<T>> waitFor<T>(Future<T> future) =>
      Future.any<_TerminalDirectoryWait<T>>(<Future<_TerminalDirectoryWait<T>>>[
        future.then<_TerminalDirectoryWait<T>>(
          (T value) => _TerminalDirectoryWait<T>.value(value),
        ),
        _stopped.future.then<_TerminalDirectoryWait<T>>(
          (_) => const _TerminalDirectoryWait<Never>.stopped(),
        ),
      ]);

  void cancel() {
    if (!_isFinished) _stop(_TerminalDirectoryStop.cancelled);
  }

  void finish() {
    _isFinished = true;
    _timer?.cancel();
    _timer = null;
  }

  void _stop(_TerminalDirectoryStop value) {
    if (_stopped.isCompleted) return;
    reason = value;
    _stopped.complete(value);
  }
}

final class _TerminalDirectoryWait<T> {
  const _TerminalDirectoryWait.value(this.value) : isStopped = false;
  const _TerminalDirectoryWait.stopped() : value = null, isStopped = true;

  final T? value;
  final bool isStopped;
}
