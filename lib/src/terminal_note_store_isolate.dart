import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'terminal_note_model.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_note_store_worker.dart';

typedef TerminalNoteStoreWorkerEntrypoint = void Function(Object? message);

enum TerminalNoteStoreWorkerRequestKind {
  load,
  commitCandidate,
  exportToApprovedPath,
  retryRecovery,
  stop,
}

/// Fixed, content-free protocol rejection.
final class TerminalNoteStoreProtocolException implements Exception {
  const TerminalNoteStoreProtocolException();

  @override
  String toString() => 'Terminal note store protocol rejected';
}

abstract final class TerminalNoteStoreWorkerProtocolV1 {
  static const int magic = 0x44544e57;
  static const int version = 1;
  static const int maximumSequence = 0x7fffffffffffffff;

  static const int _bootstrapType = 1;
  static const int _requestType = 2;
  static const int _readyType = 3;
  static const int _responseType = 4;
}

/// Strict startup message. Formatting never exposes its location.
final class TerminalNoteStoreWorkerBootstrapV1 {
  TerminalNoteStoreWorkerBootstrapV1({
    required this.authorityGeneration,
    required this.location,
    required this.parentPort,
  }) {
    _requirePositiveProtocolInt(authorityGeneration);
  }

  final int authorityGeneration;
  final TerminalNoteStoreLocation location;
  final SendPort parentPort;

  Object toMessage() => <Object?>[
    TerminalNoteStoreWorkerProtocolV1.magic,
    TerminalNoteStoreWorkerProtocolV1.version,
    TerminalNoteStoreWorkerProtocolV1._bootstrapType,
    authorityGeneration,
    location.canonicalPath,
    parentPort,
  ];

  static TerminalNoteStoreWorkerBootstrapV1 decodeMessage(Object? message) {
    final List<Object?> fields = _messageFields(message, 6);
    _requireHeader(fields, TerminalNoteStoreWorkerProtocolV1._bootstrapType);
    final int generation = _protocolInt(fields[3]);
    final Object? path = fields[4];
    final Object? port = fields[5];
    if (path is! String || port is! SendPort) _protocolReject();
    try {
      return TerminalNoteStoreWorkerBootstrapV1(
        authorityGeneration: generation,
        location: TerminalNoteStoreLocation.fromAbsolutePath(path),
        parentPort: port,
      );
    } on Object {
      _protocolReject();
    }
  }

  @override
  String toString() => 'TerminalNoteStoreWorkerBootstrapV1(<redacted>)';
}

final class TerminalNoteStoreWorkerRequestV1 {
  TerminalNoteStoreWorkerRequestV1._({
    required this.authorityGeneration,
    required this.requestSequence,
    required this.kind,
    this.document,
    this.deletions = const <TerminalNoteDeletionTombstone>[],
    this.exportPath,
  });

  factory TerminalNoteStoreWorkerRequestV1.load({
    required int authorityGeneration,
    required int requestSequence,
  }) => TerminalNoteStoreWorkerRequestV1._validated(
    authorityGeneration: authorityGeneration,
    requestSequence: requestSequence,
    kind: TerminalNoteStoreWorkerRequestKind.load,
  );

  factory TerminalNoteStoreWorkerRequestV1.commitCandidate({
    required int authorityGeneration,
    required int requestSequence,
    required TerminalNoteStoreDocument document,
    required Iterable<TerminalNoteDeletionTombstone> deletions,
  }) => TerminalNoteStoreWorkerRequestV1._validated(
    authorityGeneration: authorityGeneration,
    requestSequence: requestSequence,
    kind: TerminalNoteStoreWorkerRequestKind.commitCandidate,
    document: document,
    deletions: List<TerminalNoteDeletionTombstone>.unmodifiable(deletions),
  );

  factory TerminalNoteStoreWorkerRequestV1.exportToApprovedPath({
    required int authorityGeneration,
    required int requestSequence,
    required TerminalNoteApprovedExportPath exportPath,
  }) => TerminalNoteStoreWorkerRequestV1._validated(
    authorityGeneration: authorityGeneration,
    requestSequence: requestSequence,
    kind: TerminalNoteStoreWorkerRequestKind.exportToApprovedPath,
    exportPath: exportPath,
  );

  factory TerminalNoteStoreWorkerRequestV1.retryRecovery({
    required int authorityGeneration,
    required int requestSequence,
  }) => TerminalNoteStoreWorkerRequestV1._validated(
    authorityGeneration: authorityGeneration,
    requestSequence: requestSequence,
    kind: TerminalNoteStoreWorkerRequestKind.retryRecovery,
  );

  factory TerminalNoteStoreWorkerRequestV1.stop({
    required int authorityGeneration,
    required int requestSequence,
  }) => TerminalNoteStoreWorkerRequestV1._validated(
    authorityGeneration: authorityGeneration,
    requestSequence: requestSequence,
    kind: TerminalNoteStoreWorkerRequestKind.stop,
  );

  factory TerminalNoteStoreWorkerRequestV1._validated({
    required int authorityGeneration,
    required int requestSequence,
    required TerminalNoteStoreWorkerRequestKind kind,
    TerminalNoteStoreDocument? document,
    List<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
    TerminalNoteApprovedExportPath? exportPath,
  }) {
    _requirePositiveProtocolInt(authorityGeneration);
    _requirePositiveProtocolInt(requestSequence);
    if (deletions.length >
        TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries) {
      _protocolReject();
    }
    final bool valid = switch (kind) {
      TerminalNoteStoreWorkerRequestKind.commitCandidate =>
        document != null && exportPath == null,
      TerminalNoteStoreWorkerRequestKind.exportToApprovedPath =>
        document == null && deletions.isEmpty && exportPath != null,
      TerminalNoteStoreWorkerRequestKind.load ||
      TerminalNoteStoreWorkerRequestKind.retryRecovery ||
      TerminalNoteStoreWorkerRequestKind.stop =>
        document == null && deletions.isEmpty && exportPath == null,
    };
    if (!valid) _protocolReject();
    return TerminalNoteStoreWorkerRequestV1._(
      authorityGeneration: authorityGeneration,
      requestSequence: requestSequence,
      kind: kind,
      document: document,
      deletions: deletions,
      exportPath: exportPath,
    );
  }

  final int authorityGeneration;
  final int requestSequence;
  final TerminalNoteStoreWorkerRequestKind kind;
  final TerminalNoteStoreDocument? document;
  final List<TerminalNoteDeletionTombstone> deletions;
  final TerminalNoteApprovedExportPath? exportPath;

  Object toMessage() => <Object?>[
    TerminalNoteStoreWorkerProtocolV1.magic,
    TerminalNoteStoreWorkerProtocolV1.version,
    TerminalNoteStoreWorkerProtocolV1._requestType,
    authorityGeneration,
    requestSequence,
    kind.index,
    document,
    <TerminalNoteDeletionTombstone>[...deletions],
    exportPath?.canonicalPath,
  ];

  static TerminalNoteStoreWorkerRequestV1 decodeMessage(
    Object? message, {
    required int expectedAuthorityGeneration,
  }) {
    final List<Object?> fields = _messageFields(message, 9);
    _requireHeader(fields, TerminalNoteStoreWorkerProtocolV1._requestType);
    final int generation = _protocolInt(fields[3]);
    final int sequence = _protocolInt(fields[4]);
    if (generation != expectedAuthorityGeneration) _protocolReject();
    final TerminalNoteStoreWorkerRequestKind kind = _requestKind(fields[5]);
    final Object? document = fields[6];
    final Object? deletionValues = fields[7];
    final Object? exportPath = fields[8];
    if (deletionValues is! List<Object?> ||
        deletionValues.length >
            TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries) {
      _protocolReject();
    }
    final List<TerminalNoteDeletionTombstone> deletions =
        <TerminalNoteDeletionTombstone>[];
    for (final Object? value in deletionValues) {
      if (value is! TerminalNoteDeletionTombstone) _protocolReject();
      deletions.add(value);
    }
    try {
      return TerminalNoteStoreWorkerRequestV1._validated(
        authorityGeneration: generation,
        requestSequence: sequence,
        kind: kind,
        document: document is TerminalNoteStoreDocument ? document : null,
        deletions: deletions,
        exportPath: exportPath is String
            ? TerminalNoteApprovedExportPath.fromAbsolutePath(exportPath)
            : null,
      );
    } on TerminalNoteStoreProtocolException {
      rethrow;
    } on Object {
      _protocolReject();
    }
  }

  @override
  String toString() =>
      'TerminalNoteStoreWorkerRequestV1(${kind.name}, <redacted>)';
}

final class TerminalNoteStoreWorkerReadyV1 {
  TerminalNoteStoreWorkerReadyV1._({
    required this.authorityGeneration,
    required this.requestPort,
    required this.failure,
  });

  factory TerminalNoteStoreWorkerReadyV1.ready({
    required int authorityGeneration,
    required SendPort requestPort,
  }) {
    _requirePositiveProtocolInt(authorityGeneration);
    return TerminalNoteStoreWorkerReadyV1._(
      authorityGeneration: authorityGeneration,
      requestPort: requestPort,
      failure: null,
    );
  }

  factory TerminalNoteStoreWorkerReadyV1.failed({
    required int authorityGeneration,
    required TerminalNoteStoreFailure failure,
  }) {
    _requirePositiveProtocolInt(authorityGeneration);
    return TerminalNoteStoreWorkerReadyV1._(
      authorityGeneration: authorityGeneration,
      requestPort: null,
      failure: failure,
    );
  }

  final int authorityGeneration;
  final SendPort? requestPort;
  final TerminalNoteStoreFailure? failure;

  Object toMessage() => <Object?>[
    TerminalNoteStoreWorkerProtocolV1.magic,
    TerminalNoteStoreWorkerProtocolV1.version,
    TerminalNoteStoreWorkerProtocolV1._readyType,
    authorityGeneration,
    failure == null ? -1 : failure!.index,
    requestPort,
  ];

  static TerminalNoteStoreWorkerReadyV1 decodeMessage(Object? message) {
    final List<Object?> fields = _messageFields(message, 6);
    _requireHeader(fields, TerminalNoteStoreWorkerProtocolV1._readyType);
    final int generation = _protocolInt(fields[3]);
    final TerminalNoteStoreFailure? failure = _optionalFailure(fields[4]);
    final Object? port = fields[5];
    if ((failure == null && port is! SendPort) ||
        (failure != null && port != null)) {
      _protocolReject();
    }
    return TerminalNoteStoreWorkerReadyV1._(
      authorityGeneration: generation,
      requestPort: port as SendPort?,
      failure: failure,
    );
  }

  @override
  String toString() => failure == null
      ? 'TerminalNoteStoreWorkerReadyV1(ready)'
      : 'TerminalNoteStoreWorkerReadyV1(${failure!.name})';
}

final class TerminalNoteStoreWorkerResponseV1 {
  TerminalNoteStoreWorkerResponseV1({
    required this.authorityGeneration,
    required this.requestSequence,
    required this.requestKind,
    required this.result,
  }) {
    _requirePositiveProtocolInt(authorityGeneration);
    _requirePositiveProtocolInt(requestSequence);
    _validateResponseResult(requestKind, result);
  }

  final int authorityGeneration;
  final int requestSequence;
  final TerminalNoteStoreWorkerRequestKind requestKind;
  final TerminalNoteStoreResult result;

  Object toMessage() => <Object?>[
    TerminalNoteStoreWorkerProtocolV1.magic,
    TerminalNoteStoreWorkerProtocolV1.version,
    TerminalNoteStoreWorkerProtocolV1._responseType,
    authorityGeneration,
    requestSequence,
    requestKind.index,
    result.disposition.index,
    result.failure == null ? -1 : result.failure!.index,
    result.storeRevision.toString(),
    result.metrics.noteCount,
    result.metrics.activeCount,
    result.metrics.dueCount,
    result.metrics.detachedCount,
    result.metrics.canonicalBytes,
    result.document,
  ];

  static TerminalNoteStoreWorkerResponseV1 decodeMessage(Object? message) {
    final List<Object?> fields = _messageFields(message, 15);
    _requireHeader(fields, TerminalNoteStoreWorkerProtocolV1._responseType);
    final int generation = _protocolInt(fields[3]);
    final int sequence = _protocolInt(fields[4]);
    final TerminalNoteStoreWorkerRequestKind kind = _requestKind(fields[5]);
    final TerminalNoteStoreDisposition disposition = _disposition(fields[6]);
    final TerminalNoteStoreFailure? failure = _optionalFailure(fields[7]);
    final BigInt revision = _revision(fields[8]);
    final int noteCount = _boundedMetric(
      fields[9],
      TerminalNoteLimits.maximumNotes,
    );
    final int activeCount = _boundedMetric(
      fields[10],
      TerminalNoteLimits.maximumNotes,
    );
    final int dueCount = _boundedMetric(
      fields[11],
      TerminalNoteLimits.maximumDeliveries,
    );
    final int detachedCount = _boundedMetric(
      fields[12],
      TerminalNoteLimits.maximumNotes,
    );
    final int canonicalBytes = _boundedMetric(
      fields[13],
      TerminalNoteStoreCodecLimits.maximumFileBytes,
    );
    final Object? documentValue = fields[14];
    if (activeCount > noteCount || detachedCount > noteCount) {
      _protocolReject();
    }
    final TerminalNoteStoreDocument? document =
        documentValue is TerminalNoteStoreDocument ? documentValue : null;
    if (documentValue != null && document == null) _protocolReject();
    final TerminalNoteStoreResult result = TerminalNoteStoreResult(
      disposition: disposition,
      failure: failure,
      storeRevision: revision,
      metrics: TerminalNoteStoreMetrics(
        noteCount: noteCount,
        activeCount: activeCount,
        dueCount: dueCount,
        detachedCount: detachedCount,
        canonicalBytes: canonicalBytes,
      ),
      document: document,
    );
    _validateResponseResult(kind, result);
    return TerminalNoteStoreWorkerResponseV1(
      authorityGeneration: generation,
      requestSequence: sequence,
      requestKind: kind,
      result: result,
    );
  }

  @override
  String toString() =>
      'TerminalNoteStoreWorkerResponseV1(${requestKind.name}, ${result.disposition.name})';
}

/// Production isolate entrypoint. It never emits uncaught content or paths.
@pragma('vm:entry-point')
void terminalNoteStoreWorkerEntrypoint(Object? bootstrapMessage) {
  TerminalNoteStoreWorkerBootstrapV1 bootstrap;
  try {
    bootstrap = TerminalNoteStoreWorkerBootstrapV1.decodeMessage(
      bootstrapMessage,
    );
  } on Object {
    return;
  }

  TerminalNoteStoreTransactionEngine engine;
  try {
    engine = TerminalNoteStoreTransactionEngine.open(
      location: bootstrap.location,
    );
  } on TerminalNoteStoreException catch (error) {
    bootstrap.parentPort.send(
      TerminalNoteStoreWorkerReadyV1.failed(
        authorityGeneration: bootstrap.authorityGeneration,
        failure: error.failure,
      ).toMessage(),
    );
    return;
  } on Object {
    bootstrap.parentPort.send(
      TerminalNoteStoreWorkerReadyV1.failed(
        authorityGeneration: bootstrap.authorityGeneration,
        failure: TerminalNoteStoreFailure.unknown,
      ).toMessage(),
    );
    return;
  }

  final ReceivePort requests = ReceivePort();
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerReadyV1.ready(
      authorityGeneration: bootstrap.authorityGeneration,
      requestPort: requests.sendPort,
    ).toMessage(),
  );
  requests.listen((Object? message) {
    TerminalNoteStoreWorkerRequestV1 request;
    try {
      request = TerminalNoteStoreWorkerRequestV1.decodeMessage(
        message,
        expectedAuthorityGeneration: bootstrap.authorityGeneration,
      );
    } on Object {
      requests.close();
      engine.stop();
      return;
    }
    final TerminalNoteStoreResult result = switch (request.kind) {
      TerminalNoteStoreWorkerRequestKind.load => engine.load(),
      TerminalNoteStoreWorkerRequestKind.commitCandidate =>
        engine.commitCandidate(request.document!, deletions: request.deletions),
      TerminalNoteStoreWorkerRequestKind.exportToApprovedPath =>
        engine.exportToApprovedPath(request.exportPath!),
      TerminalNoteStoreWorkerRequestKind.retryRecovery =>
        engine.retryRecovery(),
      TerminalNoteStoreWorkerRequestKind.stop => engine.stop(),
    };
    bootstrap.parentPort.send(
      TerminalNoteStoreWorkerResponseV1(
        authorityGeneration: bootstrap.authorityGeneration,
        requestSequence: request.requestSequence,
        requestKind: request.kind,
        result: result,
      ).toMessage(),
    );
    if (request.kind == TerminalNoteStoreWorkerRequestKind.stop) {
      requests.close();
    }
  });
}

enum TerminalNoteIntentAdmissionDisposition { accepted, busy, invalid, closed }

final class TerminalNoteIntentAdmissionResult {
  const TerminalNoteIntentAdmissionResult(this.disposition);

  final TerminalNoteIntentAdmissionDisposition disposition;

  bool get isAccepted =>
      disposition == TerminalNoteIntentAdmissionDisposition.accepted;

  @override
  String toString() => 'TerminalNoteIntentAdmissionResult(${disposition.name})';
}

final class TerminalNoteAdmittedIntent<T> {
  const TerminalNoteAdmittedIntent._({
    required this.intent,
    required this.bodyBytes,
  });

  final T intent;
  final int bodyBytes;

  @override
  String toString() => 'TerminalNoteAdmittedIntent(<redacted>)';
}

/// FIFO admission for authority-owned lightweight user intents.
final class TerminalNoteIntentAdmissionQueue<T> {
  TerminalNoteIntentAdmissionResult admit(T intent, {required int bodyBytes}) {
    if (_closed) {
      return const TerminalNoteIntentAdmissionResult(
        TerminalNoteIntentAdmissionDisposition.closed,
      );
    }
    if (bodyBytes < 0 ||
        bodyBytes > TerminalNoteStoreWorkerLimits.maximumPendingBodyBytes) {
      return const TerminalNoteIntentAdmissionResult(
        TerminalNoteIntentAdmissionDisposition.invalid,
      );
    }
    if (_entries.length >=
            TerminalNoteStoreWorkerLimits.maximumPendingIntents ||
        _pendingBodyBytes + bodyBytes >
            TerminalNoteStoreWorkerLimits.maximumPendingBodyBytes) {
      return const TerminalNoteIntentAdmissionResult(
        TerminalNoteIntentAdmissionDisposition.busy,
      );
    }
    _entries.addLast(
      TerminalNoteAdmittedIntent<T>._(intent: intent, bodyBytes: bodyBytes),
    );
    _pendingBodyBytes += bodyBytes;
    return const TerminalNoteIntentAdmissionResult(
      TerminalNoteIntentAdmissionDisposition.accepted,
    );
  }

  final Queue<TerminalNoteAdmittedIntent<T>> _entries =
      Queue<TerminalNoteAdmittedIntent<T>>();
  var _pendingBodyBytes = 0;
  var _closed = false;

  int get pendingCount => _entries.length;
  int get pendingBodyBytes => _pendingBodyBytes;
  bool get isClosed => _closed;

  TerminalNoteAdmittedIntent<T>? takeFirst() {
    if (_entries.isEmpty) return null;
    final TerminalNoteAdmittedIntent<T> entry = _entries.removeFirst();
    _pendingBodyBytes -= entry.bodyBytes;
    return entry;
  }

  void clear() {
    _entries.clear();
    _pendingBodyBytes = 0;
  }

  void close() {
    _closed = true;
    clear();
  }
}

final class TerminalNoteStoreWorkerStartup {
  const TerminalNoteStoreWorkerStartup({
    required this.client,
    required this.loadResult,
  });

  final TerminalNoteStoreWorkerClient? client;
  final TerminalNoteStoreResult loadResult;

  bool get hasLiveClient => client != null;
}

enum _TerminalNoteStoreClientState {
  starting,
  ready,
  stopping,
  stopped,
  failed,
}

final class _PendingStoreRequest {
  _PendingStoreRequest({required this.request, required this.completer});

  final TerminalNoteStoreWorkerRequestV1 request;
  final Completer<TerminalNoteStoreResult> completer;
  Timer? timer;
}

/// Application-side handle for one dedicated, single-flight store isolate.
final class TerminalNoteStoreWorkerClient {
  TerminalNoteStoreWorkerClient._({
    required this.authorityGeneration,
    required this.loadTimeout,
    required this.stopTimeout,
    required ReceivePort messagePort,
    required ReceivePort errorPort,
    required ReceivePort exitPort,
  }) : _messagePort = messagePort,
       _errorPort = errorPort,
       _exitPort = exitPort {
    _debugLiveClients++;
  }

  static var _debugLiveClients = 0;

  static int get debugLiveClientCount => _debugLiveClients;

  static Future<TerminalNoteStoreWorkerStartup> start({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
    Duration loadTimeout = TerminalNoteStoreWorkerLimits.loadTimeout,
    Duration stopTimeout = TerminalNoteStoreWorkerLimits.stopTimeout,
    TerminalNoteStoreWorkerEntrypoint entrypoint =
        terminalNoteStoreWorkerEntrypoint,
  }) async {
    if (!_isPositiveProtocolInt(authorityGeneration) ||
        loadTimeout <= Duration.zero ||
        stopTimeout <= Duration.zero) {
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: _clientFailure(TerminalNoteStoreFailure.invalidState),
      );
    }
    final Stopwatch deadline = Stopwatch()..start();
    final ReceivePort messages = ReceivePort();
    final ReceivePort errors = ReceivePort();
    final ReceivePort exits = ReceivePort();
    final TerminalNoteStoreWorkerClient client =
        TerminalNoteStoreWorkerClient._(
          authorityGeneration: authorityGeneration,
          loadTimeout: loadTimeout,
          stopTimeout: stopTimeout,
          messagePort: messages,
          errorPort: errors,
          exitPort: exits,
        );
    client._listen();
    try {
      client._isolate = await Isolate.spawn<Object?>(
        entrypoint,
        TerminalNoteStoreWorkerBootstrapV1(
          authorityGeneration: authorityGeneration,
          location: location,
          parentPort: messages.sendPort,
        ).toMessage(),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'terminal-note-store-worker',
      );
    } on Object {
      await client._terminate(TerminalNoteStoreFailure.workerCrashed);
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: _clientFailure(TerminalNoteStoreFailure.workerCrashed),
      );
    }
    try {
      await client._ready.future.timeout(
        _remaining(loadTimeout, deadline.elapsed),
      );
    } on TimeoutException {
      await client._terminate(TerminalNoteStoreFailure.timeout);
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: _clientFailure(TerminalNoteStoreFailure.timeout),
      );
    }
    final TerminalNoteStoreFailure? startupFailure = client._startupFailure;
    if (startupFailure != null || client._requestPort == null) {
      final TerminalNoteStoreFailure failure =
          startupFailure ?? TerminalNoteStoreFailure.workerCrashed;
      await client._terminate(failure);
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: _clientFailure(failure),
      );
    }
    client._state = _TerminalNoteStoreClientState.ready;
    final Duration remaining = _remaining(loadTimeout, deadline.elapsed);
    if (remaining <= Duration.zero) {
      await client._terminate(TerminalNoteStoreFailure.timeout);
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: _clientFailure(TerminalNoteStoreFailure.timeout),
      );
    }
    final TerminalNoteStoreResult loadResult = await client._submit(
      kind: TerminalNoteStoreWorkerRequestKind.load,
      timeout: remaining,
    );
    if (loadResult.failure == TerminalNoteStoreFailure.timeout ||
        loadResult.failure == TerminalNoteStoreFailure.workerCrashed ||
        loadResult.failure == TerminalNoteStoreFailure.protocolViolation) {
      await client._disposePorts();
      return TerminalNoteStoreWorkerStartup(
        client: null,
        loadResult: loadResult,
      );
    }
    return TerminalNoteStoreWorkerStartup(
      client: client,
      loadResult: loadResult,
    );
  }

  final int authorityGeneration;
  final Duration loadTimeout;
  final Duration stopTimeout;
  final ReceivePort _messagePort;
  final ReceivePort _errorPort;
  final ReceivePort _exitPort;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _exited = Completer<void>();
  StreamSubscription<Object?>? _messageSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Isolate? _isolate;
  SendPort? _requestPort;
  TerminalNoteStoreFailure? _startupFailure;
  _PendingStoreRequest? _inFlight;
  _TerminalNoteStoreClientState _state = _TerminalNoteStoreClientState.starting;
  Future<TerminalNoteStoreResult>? _stopFuture;
  TerminalNoteStoreResult? _stopResult;
  Future<void>? _terminationFuture;
  var _lastCompletedSequence = 0;
  var _nextSequence = 1;
  var _stopRequestSent = false;
  var _disposed = false;

  int get pendingRequestCount => _inFlight == null ? 0 : 1;
  bool get hasLiveIsolate => _isolate != null && !_disposed;
  bool get isStopped =>
      _state == _TerminalNoteStoreClientState.stopped ||
      _state == _TerminalNoteStoreClientState.failed;

  Future<TerminalNoteStoreResult> load() => _submit(
    kind: TerminalNoteStoreWorkerRequestKind.load,
    timeout: loadTimeout,
  );

  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) => _submit(
    kind: TerminalNoteStoreWorkerRequestKind.commitCandidate,
    document: candidate,
    deletions: deletions,
  );

  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath? destination,
  ) {
    if (destination == null) {
      return Future<TerminalNoteStoreResult>.value(
        TerminalNoteStoreResult(
          disposition: TerminalNoteStoreDisposition.cancelled,
          failure: TerminalNoteStoreFailure.exportCancelled,
          storeRevision: BigInt.zero,
          metrics: TerminalNoteStoreMetrics.zero,
        ),
      );
    }
    return _submit(
      kind: TerminalNoteStoreWorkerRequestKind.exportToApprovedPath,
      exportPath: destination,
    );
  }

  Future<TerminalNoteStoreResult> retryRecovery() =>
      _submit(kind: TerminalNoteStoreWorkerRequestKind.retryRecovery);

  Future<TerminalNoteStoreResult> stop() {
    final TerminalNoteStoreResult? cached = _stopResult;
    if (cached != null) return Future<TerminalNoteStoreResult>.value(cached);
    return _stopFuture ??= _runStop();
  }

  void _listen() {
    _messageSubscription = _messagePort.cast<Object?>().listen(_handleMessage);
    _errorSubscription = _errorPort.cast<Object?>().listen((Object? _) {
      unawaited(_terminate(TerminalNoteStoreFailure.workerCrashed));
    });
    _exitSubscription = _exitPort.cast<Object?>().listen((Object? _) {
      if (!_exited.isCompleted) _exited.complete();
      final _PendingStoreRequest? pending = _inFlight;
      if (_state == _TerminalNoteStoreClientState.stopping &&
          (_stopRequestSent ||
              pending?.request.kind ==
                  TerminalNoteStoreWorkerRequestKind.stop)) {
        return;
      }
      if (_state != _TerminalNoteStoreClientState.stopped && !_disposed) {
        unawaited(_terminate(TerminalNoteStoreFailure.workerCrashed));
      }
    });
  }

  void _handleMessage(Object? message) {
    if (_disposed) return;
    if (_requestPort == null) {
      try {
        final TerminalNoteStoreWorkerReadyV1 ready =
            TerminalNoteStoreWorkerReadyV1.decodeMessage(message);
        if (ready.authorityGeneration != authorityGeneration) return;
        _requestPort = ready.requestPort;
        _startupFailure = ready.failure;
      } on Object {
        _startupFailure = TerminalNoteStoreFailure.protocolViolation;
      }
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    TerminalNoteStoreWorkerResponseV1 response;
    try {
      response = TerminalNoteStoreWorkerResponseV1.decodeMessage(message);
    } on Object {
      unawaited(_terminate(TerminalNoteStoreFailure.protocolViolation));
      return;
    }
    if (response.authorityGeneration != authorityGeneration ||
        response.requestSequence <= _lastCompletedSequence) {
      return;
    }
    final _PendingStoreRequest? pending = _inFlight;
    if (pending == null) {
      unawaited(_terminate(TerminalNoteStoreFailure.protocolViolation));
      return;
    }
    if (response.requestSequence < pending.request.requestSequence) return;
    if (response.requestSequence > pending.request.requestSequence ||
        response.requestKind != pending.request.kind) {
      unawaited(_terminate(TerminalNoteStoreFailure.protocolViolation));
      return;
    }
    pending.timer?.cancel();
    _inFlight = null;
    _lastCompletedSequence = response.requestSequence;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(response.result);
    }
  }

  Future<TerminalNoteStoreResult> _submit({
    required TerminalNoteStoreWorkerRequestKind kind,
    TerminalNoteStoreDocument? document,
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
    TerminalNoteApprovedExportPath? exportPath,
    Duration? timeout,
    bool allowStopping = false,
  }) {
    if ((_state != _TerminalNoteStoreClientState.ready &&
            !(allowStopping &&
                _state == _TerminalNoteStoreClientState.stopping)) ||
        _requestPort == null ||
        _disposed) {
      return Future<TerminalNoteStoreResult>.value(
        _clientFailure(TerminalNoteStoreFailure.invalidState),
      );
    }
    if (_inFlight != null) {
      return Future<TerminalNoteStoreResult>.value(
        _clientFailure(TerminalNoteStoreFailure.busy),
      );
    }
    if (_nextSequence > TerminalNoteStoreWorkerProtocolV1.maximumSequence) {
      unawaited(_terminate(TerminalNoteStoreFailure.protocolViolation));
      return Future<TerminalNoteStoreResult>.value(
        _clientFailure(TerminalNoteStoreFailure.protocolViolation),
      );
    }
    final int sequence = _nextSequence++;
    final TerminalNoteStoreWorkerRequestV1 request = switch (kind) {
      TerminalNoteStoreWorkerRequestKind.load =>
        TerminalNoteStoreWorkerRequestV1.load(
          authorityGeneration: authorityGeneration,
          requestSequence: sequence,
        ),
      TerminalNoteStoreWorkerRequestKind.commitCandidate =>
        TerminalNoteStoreWorkerRequestV1.commitCandidate(
          authorityGeneration: authorityGeneration,
          requestSequence: sequence,
          document: document!,
          deletions: deletions,
        ),
      TerminalNoteStoreWorkerRequestKind.exportToApprovedPath =>
        TerminalNoteStoreWorkerRequestV1.exportToApprovedPath(
          authorityGeneration: authorityGeneration,
          requestSequence: sequence,
          exportPath: exportPath!,
        ),
      TerminalNoteStoreWorkerRequestKind.retryRecovery =>
        TerminalNoteStoreWorkerRequestV1.retryRecovery(
          authorityGeneration: authorityGeneration,
          requestSequence: sequence,
        ),
      TerminalNoteStoreWorkerRequestKind.stop =>
        TerminalNoteStoreWorkerRequestV1.stop(
          authorityGeneration: authorityGeneration,
          requestSequence: sequence,
        ),
    };
    final Completer<TerminalNoteStoreResult> completer =
        Completer<TerminalNoteStoreResult>();
    final _PendingStoreRequest pending = _PendingStoreRequest(
      request: request,
      completer: completer,
    );
    if (timeout != null) {
      pending.timer = Timer(timeout, () {
        if (!identical(_inFlight, pending)) return;
        unawaited(_terminate(TerminalNoteStoreFailure.timeout));
      });
    }
    _inFlight = pending;
    try {
      _requestPort!.send(request.toMessage());
    } on Object {
      pending.timer?.cancel();
      unawaited(_terminate(TerminalNoteStoreFailure.workerCrashed));
    }
    return completer.future;
  }

  Future<TerminalNoteStoreResult> _runStop() async {
    if (_disposed ||
        _state == _TerminalNoteStoreClientState.stopped ||
        _state == _TerminalNoteStoreClientState.failed) {
      return _stopResult ??= _stoppedResult();
    }
    _state = _TerminalNoteStoreClientState.stopping;
    final Stopwatch deadline = Stopwatch()..start();
    final _PendingStoreRequest? existing = _inFlight;
    if (existing != null) {
      try {
        await existing.completer.future.timeout(
          _remaining(stopTimeout, deadline.elapsed),
        );
      } on TimeoutException {
        final TerminalNoteStoreResult result = _clientFailure(
          TerminalNoteStoreFailure.timeout,
        );
        _stopResult = result;
        await _terminate(TerminalNoteStoreFailure.timeout);
        return result;
      }
    }
    if (_disposed || _state == _TerminalNoteStoreClientState.failed) {
      return _stopResult ??= _stoppedResult();
    }
    final Duration remaining = _remaining(stopTimeout, deadline.elapsed);
    if (remaining <= Duration.zero) {
      final TerminalNoteStoreResult result = _clientFailure(
        TerminalNoteStoreFailure.timeout,
      );
      _stopResult = result;
      await _terminate(TerminalNoteStoreFailure.timeout);
      return result;
    }
    _stopRequestSent = true;
    final TerminalNoteStoreResult result = await _submit(
      kind: TerminalNoteStoreWorkerRequestKind.stop,
      timeout: remaining,
      allowStopping: true,
    );
    _stopResult = result;
    _state = _TerminalNoteStoreClientState.stopped;
    if (!_exited.isCompleted) {
      try {
        await _exited.future.timeout(_remaining(stopTimeout, deadline.elapsed));
      } on TimeoutException {
        _isolate?.kill(priority: Isolate.immediate);
      }
    }
    await _disposePorts();
    return result;
  }

  Future<void> _terminate(TerminalNoteStoreFailure failure) =>
      _terminationFuture ??= _runTerminate(failure);

  Future<void> _runTerminate(TerminalNoteStoreFailure failure) async {
    if (_disposed) return;
    _startupFailure ??= failure;
    if (!_ready.isCompleted) _ready.complete();
    final _PendingStoreRequest? pending = _inFlight;
    _inFlight = null;
    pending?.timer?.cancel();
    _state = _TerminalNoteStoreClientState.failed;
    _isolate?.kill(priority: Isolate.immediate);
    await _disposePorts();
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(_clientFailure(failure));
    }
  }

  Future<void> _disposePorts() async {
    if (_disposed) return;
    _disposed = true;
    _isolate = null;
    _requestPort = null;
    _messagePort.close();
    _errorPort.close();
    _exitPort.close();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _debugLiveClients--;
  }
}

TerminalNoteStoreResult _clientFailure(TerminalNoteStoreFailure failure) =>
    TerminalNoteStoreResult(
      disposition: failure == TerminalNoteStoreFailure.busy
          ? TerminalNoteStoreDisposition.rejected
          : TerminalNoteStoreDisposition.unavailable,
      failure: failure,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );

TerminalNoteStoreResult _stoppedResult() => TerminalNoteStoreResult(
  disposition: TerminalNoteStoreDisposition.stopped,
  failure: null,
  storeRevision: BigInt.zero,
  metrics: TerminalNoteStoreMetrics.zero,
);

void _validateResponseResult(
  TerminalNoteStoreWorkerRequestKind kind,
  TerminalNoteStoreResult result,
) {
  final TerminalNoteStoreDocument? document = result.document;
  final bool documentAllowed =
      kind == TerminalNoteStoreWorkerRequestKind.load &&
      (result.disposition == TerminalNoteStoreDisposition.loaded ||
          result.disposition == TerminalNoteStoreDisposition.empty ||
          result.disposition == TerminalNoteStoreDisposition.recoveryPreview);
  if ((document != null && !documentAllowed) ||
      (documentAllowed && document == null) ||
      result.storeRevision < BigInt.zero ||
      result.storeRevision > TerminalNoteLimits.maximumUnsigned64) {
    _protocolReject();
  }
  if (document != null) {
    document.snapshot.validate();
    final Iterable<NoteRecord> notes = document.snapshot.notes.values;
    if (result.storeRevision != document.snapshot.storeRevision ||
        result.metrics.noteCount != notes.length ||
        result.metrics.activeCount !=
            notes
                .where((NoteRecord note) => note.status == NoteStatus.active)
                .length ||
        result.metrics.dueCount != document.snapshot.deliveries.length ||
        result.metrics.detachedCount !=
            notes
                .where((NoteRecord note) => note.attachment.isDetached)
                .length) {
      _protocolReject();
    }
  }
  if (kind == TerminalNoteStoreWorkerRequestKind.stop &&
      result.disposition != TerminalNoteStoreDisposition.stopped) {
    _protocolReject();
  }
}

List<Object?> _messageFields(Object? message, int length) {
  if (message is! List<Object?> || message.length != length) {
    _protocolReject();
  }
  return message;
}

void _requireHeader(List<Object?> fields, int type) {
  if (fields[0] != TerminalNoteStoreWorkerProtocolV1.magic ||
      fields[1] != TerminalNoteStoreWorkerProtocolV1.version ||
      fields[2] != type) {
    _protocolReject();
  }
}

int _protocolInt(Object? value) {
  if (value is! int || !_isPositiveProtocolInt(value)) _protocolReject();
  return value;
}

bool _isPositiveProtocolInt(int value) =>
    value > 0 && value <= TerminalNoteStoreWorkerProtocolV1.maximumSequence;

void _requirePositiveProtocolInt(int value) {
  if (!_isPositiveProtocolInt(value)) _protocolReject();
}

TerminalNoteStoreWorkerRequestKind _requestKind(Object? value) {
  if (value is! int ||
      value < 0 ||
      value >= TerminalNoteStoreWorkerRequestKind.values.length) {
    _protocolReject();
  }
  return TerminalNoteStoreWorkerRequestKind.values[value];
}

TerminalNoteStoreDisposition _disposition(Object? value) {
  if (value is! int ||
      value < 0 ||
      value >= TerminalNoteStoreDisposition.values.length) {
    _protocolReject();
  }
  return TerminalNoteStoreDisposition.values[value];
}

TerminalNoteStoreFailure? _optionalFailure(Object? value) {
  if (value == -1) return null;
  if (value is! int ||
      value < 0 ||
      value >= TerminalNoteStoreFailure.values.length) {
    _protocolReject();
  }
  return TerminalNoteStoreFailure.values[value];
}

BigInt _revision(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      (value.length > 1 && value.startsWith('0'))) {
    _protocolReject();
  }
  final BigInt? result = BigInt.tryParse(value);
  if (result == null ||
      result < BigInt.zero ||
      result > TerminalNoteLimits.maximumUnsigned64) {
    _protocolReject();
  }
  return result;
}

int _boundedMetric(Object? value, int maximum) {
  if (value is! int || value < 0 || value > maximum) _protocolReject();
  return value;
}

Duration _remaining(Duration budget, Duration elapsed) {
  final Duration result = budget - elapsed;
  return result > Duration.zero ? result : Duration.zero;
}

Never _protocolReject() => throw const TerminalNoteStoreProtocolException();
