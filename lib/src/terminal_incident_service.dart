import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'terminal_update_feed.dart';

const String terminalIncidentApplicationName = 'dart_terminal';

final class TerminalIncidentException implements Exception {
  const TerminalIncidentException(this.code);

  final String code;

  @override
  String toString() => 'TerminalIncidentException: $code';
}

final class TerminalIncidentLimits {
  const TerminalIncidentLimits({
    this.maximumDirectoryEntries = maximumAllowedDirectoryEntries,
    this.maximumHeaderBytes = maximumAllowedHeaderBytes,
    this.maximumAggregateHeaderBytes = maximumAllowedAggregateHeaderBytes,
    this.maximumMatchingReports = maximumAllowedMatchingReports,
    this.maximumRawBytes = maximumAllowedRawBytes,
    this.maximumCommandOutputBytes = maximumAllowedCommandOutputBytes,
    this.copyTimeout = const Duration(seconds: 30),
    this.sampleTimeout = const Duration(seconds: 5),
  }) : assert(
         maximumDirectoryEntries > 0 &&
             maximumDirectoryEntries <= maximumAllowedDirectoryEntries,
       ),
       assert(
         maximumHeaderBytes > 0 &&
             maximumHeaderBytes <= maximumAllowedHeaderBytes,
       ),
       assert(
         maximumAggregateHeaderBytes >= maximumHeaderBytes &&
             maximumAggregateHeaderBytes <= maximumAllowedAggregateHeaderBytes,
       ),
       assert(
         maximumMatchingReports > 0 &&
             maximumMatchingReports <= maximumAllowedMatchingReports,
       ),
       assert(maximumRawBytes > 0 && maximumRawBytes <= maximumAllowedRawBytes),
       assert(
         maximumCommandOutputBytes > 0 &&
             maximumCommandOutputBytes <= maximumAllowedCommandOutputBytes,
       );

  static const int maximumAllowedDirectoryEntries = 4096;
  static const int maximumAllowedHeaderBytes = 16 * 1024;
  static const int maximumAllowedAggregateHeaderBytes = 4 * 1024 * 1024;
  static const int maximumAllowedMatchingReports = 256;
  static const int maximumAllowedRawBytes = 64 * 1024 * 1024;
  static const int maximumAllowedCommandOutputBytes = 64 * 1024;

  final int maximumDirectoryEntries;
  final int maximumHeaderBytes;
  final int maximumAggregateHeaderBytes;
  final int maximumMatchingReports;
  final int maximumRawBytes;
  final int maximumCommandOutputBytes;
  final Duration copyTimeout;
  final Duration sampleTimeout;
}

final class TerminalIncidentCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final List<void Function()> listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final void Function() listener in listeners) {
      try {
        listener();
      } on Object {
        // Cancellation remains content-free and best-effort for every owner.
      }
    }
  }

  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      try {
        listener();
      } on Object {
        // The token remains cancelled even when an observer is already stale.
      }
      return _noOp;
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

enum TerminalIncidentReportAvailability { ready, notFound, unavailable }

final class TerminalIncidentReportSelection {
  TerminalIncidentReportSelection._({
    required this.availability,
    required this.matchingReportCount,
    required Object owner,
    _TerminalIncidentReportCandidate? candidate,
  }) : _owner = owner,
       _candidate = candidate;

  final TerminalIncidentReportAvailability availability;
  final int matchingReportCount;
  final Object _owner;
  final _TerminalIncidentReportCandidate? _candidate;
  bool _consumed = false;

  bool get canExport =>
      availability == TerminalIncidentReportAvailability.ready && !_consumed;

  @override
  String toString() =>
      'TerminalIncidentReportSelection('
      '${availability.name}, count=$matchingReportCount)';
}

typedef TerminalIncidentCopyBoundaryObserver = FutureOr<void> Function(
  String boundary,
  File source,
  File temporary,
);

abstract interface class TerminalIncidentCrashReportStore {
  Future<TerminalIncidentReportSelection> discover({
    required TerminalIncidentCancellation cancellation,
  });

  Future<void> export(
    TerminalIncidentReportSelection selection,
    File destination, {
    required TerminalIncidentCancellation cancellation,
  });
}

final class TerminalAppleCrashReportStore
    implements TerminalIncidentCrashReportStore {
  TerminalAppleCrashReportStore({
    required this.diagnosticReportsDirectory,
    this.limits = const TerminalIncidentLimits(),
    this.copyBoundaryObserver,
  }) {
    _validateIncidentLimits(limits);
  }

  factory TerminalAppleCrashReportStore.standard({
    TerminalIncidentLimits limits = const TerminalIncidentLimits(),
  }) {
    final String? home = Platform.environment['HOME'];
    return TerminalAppleCrashReportStore(
      diagnosticReportsDirectory: Directory(
        home == null ? '' : '$home/Library/Logs/DiagnosticReports',
      ),
      limits: limits,
    );
  }

  final Directory diagnosticReportsDirectory;
  final TerminalIncidentLimits limits;
  final TerminalIncidentCopyBoundaryObserver? copyBoundaryObserver;
  final Object _owner = Object();

  @override
  Future<TerminalIncidentReportSelection> discover({
    required TerminalIncidentCancellation cancellation,
  }) async {
    try {
      _throwIfCancelled(cancellation);
      if (!diagnosticReportsDirectory.isAbsolute ||
          await FileSystemEntity.type(
                diagnosticReportsDirectory.path,
                followLinks: false,
              ) !=
              FileSystemEntityType.directory) {
        return _selection(TerminalIncidentReportAvailability.unavailable);
      }
      final String root = await diagnosticReportsDirectory
          .resolveSymbolicLinks();
      final Directory directory = Directory(root);
      var entryCount = 0;
      var headerBytes = 0;
      final List<_TerminalIncidentReportCandidate> candidates =
          <_TerminalIncidentReportCandidate>[];
      await for (final FileSystemEntity entity in directory.list(
        followLinks: false,
      )) {
        _throwIfCancelled(cancellation);
        entryCount++;
        if (entryCount > limits.maximumDirectoryEntries) {
          throw const TerminalIncidentException('report-scan-limit');
        }
        final String? name = _directChildName(root, entity.path);
        if (name == null || !name.endsWith('.ips')) continue;
        final _TerminalIncidentHeaderInspection inspection =
            await _inspectProductReport(
              File(entity.path),
              maximumHeaderBytes: limits.maximumHeaderBytes,
              maximumRawBytes: limits.maximumRawBytes,
            );
        headerBytes += inspection.bytesRead;
        if (headerBytes > limits.maximumAggregateHeaderBytes) {
          throw const TerminalIncidentException('report-header-limit');
        }
        final _TerminalIncidentFileSnapshot? snapshot = inspection.snapshot;
        if (!inspection.matchesProduct || snapshot == null) continue;
        candidates.add(
          _TerminalIncidentReportCandidate(
            name: name,
            source: File('$root/$name'),
            snapshot: snapshot,
          ),
        );
        if (candidates.length > limits.maximumMatchingReports) {
          throw const TerminalIncidentException('report-match-limit');
        }
      }
      _throwIfCancelled(cancellation);
      if (candidates.isEmpty) {
        return _selection(TerminalIncidentReportAvailability.notFound);
      }
      candidates.sort(_compareReportCandidates);
      return _selection(
        TerminalIncidentReportAvailability.ready,
        count: candidates.length,
        candidate: candidates.last,
      );
    } on TerminalIncidentException catch (error) {
      if (error.code == 'operation-cancelled') rethrow;
      return _selection(TerminalIncidentReportAvailability.unavailable);
    } on Object {
      return _selection(TerminalIncidentReportAvailability.unavailable);
    }
  }

  @override
  Future<void> export(
    TerminalIncidentReportSelection selection,
    File destination, {
    required TerminalIncidentCancellation cancellation,
  }) async {
    _throwIfCancelled(cancellation);
    final _TerminalIncidentReportCandidate? candidate = selection._candidate;
    if (!identical(selection._owner, _owner) ||
        selection.availability != TerminalIncidentReportAvailability.ready ||
        candidate == null ||
        selection._consumed) {
      throw const TerminalIncidentException('report-selection-invalid');
    }
    selection._consumed = true;
    final _TerminalIncidentFileSnapshot? current = await _snapshotRegularFile(
      candidate.source,
      maximumBytes: limits.maximumRawBytes,
    );
    if (current == null || current != candidate.snapshot) {
      throw const TerminalIncidentException('report-source-changed');
    }
    try {
      await _copyIncidentFileAtomically(
        source: candidate.source,
        expectedSource: candidate.snapshot,
        destination: destination,
        requiredSuffix: '.ips',
        limits: limits,
        cancellation: cancellation,
        boundaryObserver: copyBoundaryObserver,
        validateTemporary: (File temporary) async {
          final _TerminalIncidentHeaderInspection inspection =
              await _inspectProductReport(
                temporary,
                maximumHeaderBytes: limits.maximumHeaderBytes,
                maximumRawBytes: limits.maximumRawBytes,
              );
          if (!inspection.matchesProduct) {
            throw const TerminalIncidentException('report-source-changed');
          }
        },
      );
    } on TerminalIncidentException {
      rethrow;
    } on Object {
      throw const TerminalIncidentException('report-copy-failed');
    }
  }

  TerminalIncidentReportSelection _selection(
    TerminalIncidentReportAvailability availability, {
    int count = 0,
    _TerminalIncidentReportCandidate? candidate,
  }) => TerminalIncidentReportSelection._(
    availability: availability,
    matchingReportCount: count,
    owner: _owner,
    candidate: candidate,
  );
}

enum TerminalIncidentProcessDisposition {
  completed,
  cancelled,
  timedOut,
  unavailable,
  failed,
  outputOverflow,
}

final class TerminalIncidentProcessResult {
  const TerminalIncidentProcessResult(this.disposition);

  final TerminalIncidentProcessDisposition disposition;
}

abstract interface class TerminalIncidentProcessRunner {
  Future<TerminalIncidentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required int maximumOutputBytes,
    required TerminalIncidentCancellation cancellation,
  });
}

final class TerminalIncidentSystemProcessRunner
    implements TerminalIncidentProcessRunner {
  const TerminalIncidentSystemProcessRunner();

  @override
  Future<TerminalIncidentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required int maximumOutputBytes,
    required TerminalIncidentCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return const TerminalIncidentProcessResult(
        TerminalIncidentProcessDisposition.cancelled,
      );
    }
    Process? process;
    void Function()? removeCancellationListener;
    try {
      process = await Process.start(
        executable,
        List<String>.unmodifiable(arguments),
        mode: ProcessStartMode.normal,
      );
      final Process running = process;
      removeCancellationListener = cancellation.addListener(
        () => running.kill(ProcessSignal.sigkill),
      );
      final Future<_TerminalIncidentOutputCount> stdout = _countBoundedOutput(
        running.stdout,
        maximumOutputBytes,
      );
      final Future<_TerminalIncidentOutputCount> stderr = _countBoundedOutput(
        running.stderr,
        maximumOutputBytes,
      );
      await running.stdin.close();
      var timedOut = false;
      late final int exitStatus;
      try {
        exitStatus = await running.exitCode.timeout(timeout);
      } on TimeoutException {
        timedOut = true;
        running.kill(ProcessSignal.sigkill);
        exitStatus = await running.exitCode;
      }
      final List<_TerminalIncidentOutputCount> output = await Future.wait(
        <Future<_TerminalIncidentOutputCount>>[stdout, stderr],
      );
      if (cancellation.isCancelled) {
        return const TerminalIncidentProcessResult(
          TerminalIncidentProcessDisposition.cancelled,
        );
      }
      if (timedOut) {
        return const TerminalIncidentProcessResult(
          TerminalIncidentProcessDisposition.timedOut,
        );
      }
      if (output.any((_TerminalIncidentOutputCount value) => value.overflow)) {
        return const TerminalIncidentProcessResult(
          TerminalIncidentProcessDisposition.outputOverflow,
        );
      }
      return TerminalIncidentProcessResult(
        exitStatus == 0
            ? TerminalIncidentProcessDisposition.completed
            : TerminalIncidentProcessDisposition.failed,
      );
    } on ProcessException {
      return const TerminalIncidentProcessResult(
        TerminalIncidentProcessDisposition.unavailable,
      );
    } on Object {
      process?.kill(ProcessSignal.sigkill);
      return TerminalIncidentProcessResult(
        cancellation.isCancelled
            ? TerminalIncidentProcessDisposition.cancelled
            : TerminalIncidentProcessDisposition.failed,
      );
    } finally {
      removeCancellationListener?.call();
    }
  }
}

abstract interface class TerminalIncidentService {
  Future<TerminalIncidentReportSelection> discoverLatestCrashReport({
    TerminalIncidentCancellation? cancellation,
  });

  Future<void> exportLatestCrashReport(
    TerminalIncidentReportSelection selection,
    File destination, {
    TerminalIncidentCancellation? cancellation,
  });

  Future<void> captureHangSample(
    File destination, {
    TerminalIncidentCancellation? cancellation,
  });

  void dispose();
}

final class TerminalLocalIncidentService implements TerminalIncidentService {
  TerminalLocalIncidentService({
    required this.reportStore,
    required this.temporaryParent,
    this.processRunner = const TerminalIncidentSystemProcessRunner(),
    int? currentProcessId,
    this.limits = const TerminalIncidentLimits(),
    this.copyBoundaryObserver,
  }) : _currentProcessId = currentProcessId ?? pid {
    _validateIncidentLimits(limits);
    if (_currentProcessId <= 0) {
      throw ArgumentError.value(_currentProcessId, 'currentProcessId');
    }
  }

  factory TerminalLocalIncidentService.standard({
    TerminalIncidentLimits limits = const TerminalIncidentLimits(),
  }) => TerminalLocalIncidentService(
    reportStore: TerminalAppleCrashReportStore.standard(limits: limits),
    temporaryParent: Directory.systemTemp,
    limits: limits,
  );

  final TerminalIncidentCrashReportStore reportStore;
  final Directory temporaryParent;
  final TerminalIncidentProcessRunner processRunner;
  final TerminalIncidentLimits limits;
  final TerminalIncidentCopyBoundaryObserver? copyBoundaryObserver;
  final int _currentProcessId;
  final Set<TerminalIncidentCancellation> _operations =
      <TerminalIncidentCancellation>{};
  bool _disposed = false;

  @override
  Future<TerminalIncidentReportSelection> discoverLatestCrashReport({
    TerminalIncidentCancellation? cancellation,
  }) => _runOperation(
    cancellation,
    (TerminalIncidentCancellation owned) =>
        reportStore.discover(cancellation: owned),
  );

  @override
  Future<void> exportLatestCrashReport(
    TerminalIncidentReportSelection selection,
    File destination, {
    TerminalIncidentCancellation? cancellation,
  }) => _runOperation(
    cancellation,
    (TerminalIncidentCancellation owned) =>
        reportStore.export(selection, destination, cancellation: owned),
  );

  @override
  Future<void> captureHangSample(
    File destination, {
    TerminalIncidentCancellation? cancellation,
  }) => _runOperation(cancellation, (TerminalIncidentCancellation owned) async {
    _throwIfCancelled(owned);
    final File safeDestination = await _safeIncidentDestination(
      destination,
      requiredSuffix: '.sample.txt',
    );
    final Directory workspace = await _createPrivateWorkspace();
    try {
      final File sample = File('${workspace.path}/sample.txt');
      final List<String> arguments = <String>[
        _currentProcessId.toString(),
        '1',
        '1',
        '-file',
        sample.path,
      ];
      final TerminalIncidentProcessResult result;
      try {
        result = await processRunner.run(
          '/usr/bin/sample',
          arguments,
          timeout: limits.sampleTimeout,
          maximumOutputBytes: limits.maximumCommandOutputBytes,
          cancellation: owned,
        );
      } on Object {
        throw const TerminalIncidentException('sample-failed');
      }
      _throwIfCancelled(owned);
      switch (result.disposition) {
        case TerminalIncidentProcessDisposition.completed:
          break;
        case TerminalIncidentProcessDisposition.cancelled:
          throw const TerminalIncidentException('operation-cancelled');
        case TerminalIncidentProcessDisposition.timedOut:
          throw const TerminalIncidentException('sample-timeout');
        case TerminalIncidentProcessDisposition.unavailable:
          throw const TerminalIncidentException('sample-unavailable');
        case TerminalIncidentProcessDisposition.outputOverflow:
          throw const TerminalIncidentException('sample-output-overflow');
        case TerminalIncidentProcessDisposition.failed:
          throw const TerminalIncidentException('sample-failed');
      }
      final _TerminalIncidentFileSnapshot? snapshot =
          await _snapshotRegularFile(
            sample,
            maximumBytes: limits.maximumRawBytes,
          );
      if (snapshot == null) {
        throw const TerminalIncidentException('sample-output-invalid');
      }
      await _copyIncidentFileAtomically(
        source: sample,
        expectedSource: snapshot,
        destination: safeDestination,
        requiredSuffix: '.sample.txt',
        limits: limits,
        cancellation: owned,
        boundaryObserver: copyBoundaryObserver,
      );
    } on TerminalIncidentException {
      rethrow;
    } on Object {
      throw const TerminalIncidentException('sample-failed');
    } finally {
      if (!await _deleteIncidentWorkspace(workspace)) {
        throw const TerminalIncidentException('temporary-cleanup-failed');
      }
    }
  });

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final TerminalIncidentCancellation operation in _operations.toList()) {
      operation.cancel();
    }
  }

  Future<T> _runOperation<T>(
    TerminalIncidentCancellation? external,
    Future<T> Function(TerminalIncidentCancellation cancellation) body,
  ) async {
    if (_disposed) {
      throw const TerminalIncidentException('service-disposed');
    }
    final TerminalIncidentCancellation owned = TerminalIncidentCancellation();
    final void Function()? removeExternal = external?.addListener(owned.cancel);
    _operations.add(owned);
    try {
      _throwIfCancelled(owned);
      return await body(owned);
    } on TerminalIncidentException {
      rethrow;
    } on Object {
      throw const TerminalIncidentException('incident-operation-failed');
    } finally {
      removeExternal?.call();
      _operations.remove(owned);
    }
  }

  Future<Directory> _createPrivateWorkspace() async {
    if (!temporaryParent.isAbsolute ||
        await FileSystemEntity.type(temporaryParent.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const TerminalIncidentException('temporary-storage-unavailable');
    }
    final String parent = await temporaryParent.resolveSymbolicLinks();
    final Directory workspace;
    try {
      workspace = await Directory(parent).createTemp('dart-terminal-incident-');
    } on Object {
      throw const TerminalIncidentException('temporary-storage-unavailable');
    }
    final FileStat stat;
    try {
      stat = await workspace.stat();
    } on Object {
      await _deleteIncidentWorkspace(workspace);
      throw const TerminalIncidentException('temporary-storage-unavailable');
    }
    final bool exactChild =
        _directChildName(
          parent,
          workspace.path,
        )?.startsWith('dart-terminal-incident-') ??
        false;
    if (!exactChild ||
        stat.type != FileSystemEntityType.directory ||
        stat.mode & 0x3f != 0) {
      try {
        await _deleteIncidentWorkspace(workspace);
      } on Object {
        // Do not disclose or reuse an invalid temporary workspace.
      }
      throw const TerminalIncidentException('temporary-storage-not-private');
    }
    return workspace;
  }
}

Future<void> _copyIncidentFileAtomically({
  required File source,
  required _TerminalIncidentFileSnapshot expectedSource,
  required File destination,
  required String requiredSuffix,
  required TerminalIncidentLimits limits,
  required TerminalIncidentCancellation cancellation,
  TerminalIncidentCopyBoundaryObserver? boundaryObserver,
  Future<void> Function(File temporary)? validateTemporary,
}) async {
  _throwIfCancelled(cancellation);
  final File target = await _safeIncidentDestination(
    destination,
    requiredSuffix: requiredSuffix,
  );
  if (source.path == target.path) {
    throw const TerminalIncidentException('destination-invalid');
  }
  File? temporary;
  IOSink? output;
  var published = false;
  try {
    for (var attempt = 0; attempt < 64; attempt++) {
      final File candidate = File(
        '${target.path}.dart-terminal-incident-${_incidentNonce()}.tmp',
      );
      try {
        await candidate.create(exclusive: true);
        temporary = candidate;
        break;
      } on FileSystemException {
        // Never overwrite a colliding sibling.
      }
    }
    final File staging =
        temporary ??
        (throw const TerminalIncidentException('temporary-create-failed'));
    await boundaryObserver?.call('before-copy', source, staging);
    _throwIfCancelled(cancellation);
    final Stopwatch elapsed = Stopwatch()..start();
    output = staging.openWrite(mode: FileMode.write);
    var copied = 0;
    await for (final List<int> chunk in source.openRead().timeout(
      limits.copyTimeout,
    )) {
      _throwIfCancelled(cancellation);
      if (elapsed.elapsed > limits.copyTimeout) {
        throw const TerminalIncidentException('copy-timeout');
      }
      copied += chunk.length;
      if (copied > limits.maximumRawBytes || copied > expectedSource.size) {
        throw const TerminalIncidentException('raw-data-too-large');
      }
      output.add(chunk);
      await boundaryObserver?.call('after-copy-chunk', source, staging);
    }
    await output.flush();
    await output.close();
    output = null;
    _throwIfCancelled(cancellation);
    if (elapsed.elapsed > limits.copyTimeout || copied != expectedSource.size) {
      throw const TerminalIncidentException('report-source-changed');
    }
    await boundaryObserver?.call('after-copy', source, staging);
    final _TerminalIncidentFileSnapshot? sourceAfter =
        await _snapshotRegularFile(
          source,
          maximumBytes: limits.maximumRawBytes,
        );
    if (sourceAfter == null || sourceAfter != expectedSource) {
      throw const TerminalIncidentException('report-source-changed');
    }
    final _TerminalIncidentFileSnapshot? stagingSnapshot =
        await _snapshotRegularFile(
          staging,
          maximumBytes: limits.maximumRawBytes,
        );
    if (stagingSnapshot == null || stagingSnapshot.size != copied) {
      throw const TerminalIncidentException('temporary-output-invalid');
    }
    if (validateTemporary != null) await validateTemporary(staging);
    _throwIfCancelled(cancellation);
    await boundaryObserver?.call('before-publish', source, staging);
    _throwIfCancelled(cancellation);
    await staging.rename(target.path);
    published = true;
  } on TimeoutException {
    throw const TerminalIncidentException('copy-timeout');
  } on TerminalIncidentException {
    rethrow;
  } on Object {
    throw const TerminalIncidentException('copy-failed');
  } finally {
    if (output != null) {
      try {
        await output.close();
      } on Object {
        // Preserve the fixed primary failure classification.
      }
    }
    final File? leftover = temporary;
    if (!published && leftover != null) {
      var cleaned = false;
      try {
        final FileSystemEntityType type = await FileSystemEntity.type(
          leftover.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          cleaned = true;
        } else if (type == FileSystemEntityType.file) {
          await leftover.delete();
          cleaned = true;
        } else if (type == FileSystemEntityType.link) {
          await Link(leftover.path).delete();
          cleaned = true;
        }
      } on Object {
        // The fixed cleanup failure below does not reveal its sensitive path.
      }
      if (!cleaned) {
        throw const TerminalIncidentException('temporary-cleanup-failed');
      }
    }
  }
}

Future<File> _safeIncidentDestination(
  File destination, {
  required String requiredSuffix,
}) async {
  if (!destination.isAbsolute) {
    throw const TerminalIncidentException('destination-invalid');
  }
  final List<String> segments = destination.uri.pathSegments
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    throw const TerminalIncidentException('destination-invalid');
  }
  final String leaf = segments.last;
  if (!leaf.endsWith(requiredSuffix) ||
      utf8.encode(leaf).length > 160 ||
      leaf.codeUnits.any((int value) => value < 0x20 || value == 0x7f)) {
    throw const TerminalIncidentException('destination-invalid');
  }
  final Directory parent = destination.parent;
  if (await FileSystemEntity.type(parent.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const TerminalIncidentException('destination-invalid');
  }
  final String resolvedParent = await parent.resolveSymbolicLinks();
  final File target = File('$resolvedParent/$leaf');
  final FileSystemEntityType targetType = await FileSystemEntity.type(
    target.path,
    followLinks: false,
  );
  if (targetType != FileSystemEntityType.notFound &&
      targetType != FileSystemEntityType.file) {
    throw const TerminalIncidentException('destination-invalid');
  }
  return target;
}

Future<_TerminalIncidentHeaderInspection> _inspectProductReport(
  File report, {
  required int maximumHeaderBytes,
  required int maximumRawBytes,
}) async {
  final _TerminalIncidentFileSnapshot? before = await _snapshotRegularFile(
    report,
    maximumBytes: maximumRawBytes,
  );
  if (before == null) {
    return const _TerminalIncidentHeaderInspection.invalid();
  }
  RandomAccessFile? input;
  List<int> bytes;
  try {
    input = await report.open();
    bytes = await input.read(maximumHeaderBytes + 1);
  } on Object {
    return const _TerminalIncidentHeaderInspection.invalid();
  } finally {
    await input?.close();
  }
  final int newline = bytes.indexOf(0x0a);
  if (newline <= 0 || newline > maximumHeaderBytes) {
    return _TerminalIncidentHeaderInspection.invalid(bytesRead: bytes.length);
  }
  final Map<String, Object?> header;
  try {
    final Object? decoded = jsonDecode(
      utf8.decode(bytes.sublist(0, newline), allowMalformed: false),
    );
    if (decoded is! Map<String, Object?>) {
      return _TerminalIncidentHeaderInspection.invalid(bytesRead: newline + 1);
    }
    header = decoded;
  } on Object {
    return _TerminalIncidentHeaderInspection.invalid(bytesRead: newline + 1);
  }
  final _TerminalIncidentFileSnapshot? after = await _snapshotRegularFile(
    report,
    maximumBytes: maximumRawBytes,
  );
  if (after == null || after != before) {
    return _TerminalIncidentHeaderInspection.invalid(bytesRead: newline + 1);
  }
  return _TerminalIncidentHeaderInspection(
    bytesRead: newline + 1,
    matchesProduct:
        header['bundleID'] == terminalUpdateProduct &&
        header['app_name'] == terminalIncidentApplicationName,
    snapshot: after,
  );
}

Future<_TerminalIncidentFileSnapshot?> _snapshotRegularFile(
  File file, {
  required int maximumBytes,
}) async {
  try {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final FileStat stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < 1 ||
        stat.size > maximumBytes) {
      return null;
    }
    return _TerminalIncidentFileSnapshot(
      size: stat.size,
      modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
      changedMicroseconds: stat.changed.microsecondsSinceEpoch,
      mode: stat.mode,
    );
  } on Object {
    return null;
  }
}

Future<_TerminalIncidentOutputCount> _countBoundedOutput(
  Stream<List<int>> source,
  int maximumBytes,
) async {
  var count = 0;
  await for (final List<int> chunk in source) {
    count += chunk.length;
  }
  return _TerminalIncidentOutputCount(overflow: count > maximumBytes);
}

Future<bool> _deleteIncidentWorkspace(Directory workspace) async {
  try {
    final FileSystemEntityType type = await FileSystemEntity.type(
      workspace.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return true;
    if (type == FileSystemEntityType.directory) {
      await workspace.delete(recursive: true);
      return true;
    }
    if (type == FileSystemEntityType.link) {
      await Link(workspace.path).delete();
      return true;
    }
    if (type == FileSystemEntityType.file) {
      await File(workspace.path).delete();
      return true;
    }
    return false;
  } on Object {
    return false;
  }
}

int _compareReportCandidates(
  _TerminalIncidentReportCandidate left,
  _TerminalIncidentReportCandidate right,
) {
  final int modified = left.snapshot.modifiedMicroseconds.compareTo(
    right.snapshot.modifiedMicroseconds,
  );
  return modified != 0 ? modified : left.name.compareTo(right.name);
}

String? _directChildName(String parent, String child) {
  if (!child.startsWith('$parent${Platform.pathSeparator}')) return null;
  final String relative = child.substring(parent.length + 1);
  if (relative.isEmpty || relative.contains(Platform.pathSeparator))
    return null;
  return relative;
}

int _nextIncidentTemporaryId = 0;

String _incidentNonce() {
  final int id = _nextIncidentTemporaryId++;
  if (_nextIncidentTemporaryId > 0x7fffffff) _nextIncidentTemporaryId = 0;
  return '${pid.toRadixString(16)}-${id.toRadixString(16)}';
}

void _throwIfCancelled(TerminalIncidentCancellation cancellation) {
  if (cancellation.isCancelled) {
    throw const TerminalIncidentException('operation-cancelled');
  }
}

void _validateIncidentLimits(TerminalIncidentLimits limits) {
  if (limits.maximumDirectoryEntries <= 0 ||
      limits.maximumDirectoryEntries >
          TerminalIncidentLimits.maximumAllowedDirectoryEntries ||
      limits.maximumHeaderBytes <= 0 ||
      limits.maximumHeaderBytes >
          TerminalIncidentLimits.maximumAllowedHeaderBytes ||
      limits.maximumAggregateHeaderBytes < limits.maximumHeaderBytes ||
      limits.maximumAggregateHeaderBytes >
          TerminalIncidentLimits.maximumAllowedAggregateHeaderBytes ||
      limits.maximumMatchingReports <= 0 ||
      limits.maximumMatchingReports >
          TerminalIncidentLimits.maximumAllowedMatchingReports ||
      limits.maximumRawBytes <= 0 ||
      limits.maximumRawBytes > TerminalIncidentLimits.maximumAllowedRawBytes ||
      limits.maximumCommandOutputBytes <= 0 ||
      limits.maximumCommandOutputBytes >
          TerminalIncidentLimits.maximumAllowedCommandOutputBytes ||
      limits.copyTimeout <= Duration.zero ||
      limits.sampleTimeout <= Duration.zero) {
    throw ArgumentError.value(limits, 'limits', 'outside safe bounds');
  }
}

void _noOp() {}

final class _TerminalIncidentReportCandidate {
  const _TerminalIncidentReportCandidate({
    required this.name,
    required this.source,
    required this.snapshot,
  });

  final String name;
  final File source;
  final _TerminalIncidentFileSnapshot snapshot;
}

final class _TerminalIncidentFileSnapshot {
  const _TerminalIncidentFileSnapshot({
    required this.size,
    required this.modifiedMicroseconds,
    required this.changedMicroseconds,
    required this.mode,
  });

  final int size;
  final int modifiedMicroseconds;
  final int changedMicroseconds;
  final int mode;

  @override
  bool operator ==(Object other) =>
      other is _TerminalIncidentFileSnapshot &&
      other.size == size &&
      other.modifiedMicroseconds == modifiedMicroseconds &&
      other.changedMicroseconds == changedMicroseconds &&
      other.mode == mode;

  @override
  int get hashCode =>
      Object.hash(size, modifiedMicroseconds, changedMicroseconds, mode);
}

final class _TerminalIncidentHeaderInspection {
  const _TerminalIncidentHeaderInspection({
    required this.bytesRead,
    required this.matchesProduct,
    required this.snapshot,
  });

  const _TerminalIncidentHeaderInspection.invalid({this.bytesRead = 0})
    : matchesProduct = false,
      snapshot = null;

  final int bytesRead;
  final bool matchesProduct;
  final _TerminalIncidentFileSnapshot? snapshot;
}

final class _TerminalIncidentOutputCount {
  const _TerminalIncidentOutputCount({required this.overflow});

  final bool overflow;
}
