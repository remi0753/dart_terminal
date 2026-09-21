import 'dart:convert';
import 'dart:typed_data';

import 'runtime_lifecycle.dart';
import 'terminal_note_authority.dart';
import 'terminal_note_model.dart';
import 'terminal_note_store_codec.dart';
import 'terminal_note_store_isolate.dart';
import 'terminal_note_store_worker.dart';

const String _processMagic = 'dart-terminal-note-process-v1';
const int _processVersion = 1;

enum _ProcessRequestKind { open, commit, export, stop }

final class _ProcessRequest {
  const _ProcessRequest({
    required this.kind,
    required this.session,
    required this.authorityGeneration,
    this.path,
    this.document,
    this.deletions = const <TerminalNoteDeletionTombstone>[],
  });

  final _ProcessRequestKind kind;
  final int session;
  final int authorityGeneration;
  final String? path;
  final TerminalNoteStoreDocument? document;
  final List<TerminalNoteDeletionTombstone> deletions;
}

final class _ProcessResponse {
  const _ProcessResponse({
    required this.kind,
    required this.session,
    required this.authorityGeneration,
    required this.sessionOpen,
    required this.result,
  });

  final TerminalNoteStoreWorkerRequestKind kind;
  final int session;
  final int authorityGeneration;
  final bool sessionOpen;
  final TerminalNoteStoreResult result;
}

/// Strict bounded codec shared by the UI-side adapter and bundled helper.
abstract final class TerminalNoteStoreProcessProtocol {
  static const TerminalNoteStoreCodec _codec = TerminalNoteStoreCodec();

  static bool hasMagic(Uint8List payload) {
    if (payload.length < 2 || payload[0] != 0x7b) return false;
    try {
      final Object? decoded = jsonDecode(utf8.decode(payload));
      return decoded is Map<String, Object?> &&
          decoded['magic'] == _processMagic;
    } on Object {
      return false;
    }
  }

  static Uint8List openRequest({
    required int session,
    required int authorityGeneration,
    required TerminalNoteStoreLocation location,
  }) => _encode(<String, Object?>{
    'magic': _processMagic,
    'version': _processVersion,
    'kind': _ProcessRequestKind.open.index,
    'session': session,
    'authorityGeneration': authorityGeneration,
    'path': location.canonicalPath,
    'document': null,
    'deletions': null,
  });

  static Uint8List commitRequest({
    required int session,
    required int authorityGeneration,
    required TerminalNoteStoreDocument document,
    required Iterable<TerminalNoteDeletionTombstone> deletions,
  }) => _encode(<String, Object?>{
    'magic': _processMagic,
    'version': _processVersion,
    'kind': _ProcessRequestKind.commit.index,
    'session': session,
    'authorityGeneration': authorityGeneration,
    'path': null,
    'document': base64Encode(_codec.encode(document)),
    'deletions': base64Encode(
      _codec.encodeDeletionJournal(
        TerminalNoteDeletionJournal(entries: deletions),
      ),
    ),
  });

  static Uint8List exportRequest({
    required int session,
    required int authorityGeneration,
    required TerminalNoteApprovedExportPath destination,
  }) => _encode(<String, Object?>{
    'magic': _processMagic,
    'version': _processVersion,
    'kind': _ProcessRequestKind.export.index,
    'session': session,
    'authorityGeneration': authorityGeneration,
    'path': destination.canonicalPath,
    'document': null,
    'deletions': null,
  });

  static Uint8List stopRequest({
    required int session,
    required int authorityGeneration,
  }) => _encode(<String, Object?>{
    'magic': _processMagic,
    'version': _processVersion,
    'kind': _ProcessRequestKind.stop.index,
    'session': session,
    'authorityGeneration': authorityGeneration,
    'path': null,
    'document': null,
    'deletions': null,
  });

  static _ProcessRequest decodeRequest(Uint8List payload) {
    final Map<String, Object?> value = _decodeMap(payload);
    _requireExactKeys(value, const <String>{
      'magic',
      'version',
      'kind',
      'session',
      'authorityGeneration',
      'path',
      'document',
      'deletions',
    });
    final _ProcessRequestKind kind = _enumValue(
      _ProcessRequestKind.values,
      value['kind'],
    );
    final int session = _positiveInt(value['session']);
    final int generation = _positiveInt(value['authorityGeneration']);
    final Object? pathValue = value['path'];
    final Object? documentValue = value['document'];
    final Object? deletionValue = value['deletions'];
    TerminalNoteStoreDocument? document;
    List<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[];
    if (documentValue != null) {
      document = _codec.decode(_base64Bytes(documentValue));
    }
    if (deletionValue != null) {
      deletions = _codec
          .decodeDeletionJournal(_base64Bytes(deletionValue))
          .entries;
    }
    final String? path = pathValue is String ? pathValue : null;
    final bool valid = switch (kind) {
      _ProcessRequestKind.open =>
        path != null && document == null && deletionValue == null,
      _ProcessRequestKind.commit =>
        path == null && document != null && deletionValue != null,
      _ProcessRequestKind.export =>
        path != null && document == null && deletionValue == null,
      _ProcessRequestKind.stop =>
        path == null && document == null && deletionValue == null,
    };
    if (!valid) throw const FormatException('invalid Note process request');
    return _ProcessRequest(
      kind: kind,
      session: session,
      authorityGeneration: generation,
      path: path,
      document: document,
      deletions: deletions,
    );
  }

  static Uint8List encodeResponse(_ProcessResponse response) {
    final TerminalNoteStoreResult result = response.result;
    return _encode(<String, Object?>{
      'magic': _processMagic,
      'version': _processVersion,
      'kind': response.kind.index,
      'session': response.session,
      'authorityGeneration': response.authorityGeneration,
      'sessionOpen': response.sessionOpen,
      'disposition': result.disposition.index,
      'failure': result.failure?.index,
      'storeRevision': result.storeRevision.toString(),
      'noteCount': result.metrics.noteCount,
      'activeCount': result.metrics.activeCount,
      'dueCount': result.metrics.dueCount,
      'detachedCount': result.metrics.detachedCount,
      'canonicalBytes': result.metrics.canonicalBytes,
      'document': result.document == null
          ? null
          : base64Encode(_codec.encode(result.document!)),
    });
  }

  static _ProcessResponse decodeResponse(Uint8List payload) {
    final Map<String, Object?> value = _decodeMap(payload);
    _requireExactKeys(value, const <String>{
      'magic',
      'version',
      'kind',
      'session',
      'authorityGeneration',
      'sessionOpen',
      'disposition',
      'failure',
      'storeRevision',
      'noteCount',
      'activeCount',
      'dueCount',
      'detachedCount',
      'canonicalBytes',
      'document',
    });
    final TerminalNoteStoreWorkerRequestKind kind = _enumValue(
      TerminalNoteStoreWorkerRequestKind.values,
      value['kind'],
    );
    final int generation = _positiveInt(value['authorityGeneration']);
    final int session = _positiveInt(value['session']);
    final Object? openValue = value['sessionOpen'];
    if (openValue is! bool) {
      throw const FormatException('invalid Note process session state');
    }
    final TerminalNoteStoreDisposition disposition = _enumValue(
      TerminalNoteStoreDisposition.values,
      value['disposition'],
    );
    final TerminalNoteStoreFailure? failure = value['failure'] == null
        ? null
        : _enumValue(TerminalNoteStoreFailure.values, value['failure']);
    final Object? revisionValue = value['storeRevision'];
    final BigInt? revision = revisionValue is String
        ? BigInt.tryParse(revisionValue)
        : null;
    if (revision == null ||
        revision < BigInt.zero ||
        revision > TerminalNoteLimits.maximumUnsigned64) {
      throw const FormatException('invalid Note process revision');
    }
    final TerminalNoteStoreResult result = TerminalNoteStoreResult(
      disposition: disposition,
      failure: failure,
      storeRevision: revision,
      metrics: TerminalNoteStoreMetrics(
        noteCount: _nonNegativeInt(value['noteCount']),
        activeCount: _nonNegativeInt(value['activeCount']),
        dueCount: _nonNegativeInt(value['dueCount']),
        detachedCount: _nonNegativeInt(value['detachedCount']),
        canonicalBytes: _nonNegativeInt(value['canonicalBytes']),
      ),
      document: value['document'] == null
          ? null
          : _codec.decode(_base64Bytes(value['document'])),
    );
    TerminalNoteStoreWorkerResponseV1(
      authorityGeneration: generation,
      requestSequence: 1,
      requestKind: kind,
      result: result,
    );
    return _ProcessResponse(
      kind: kind,
      session: session,
      authorityGeneration: generation,
      sessionOpen: openValue,
      result: result,
    );
  }

  static Uint8List _encode(Map<String, Object?> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  static Map<String, Object?> _decodeMap(Uint8List payload) {
    if (payload.isEmpty || payload.length > 32 * 1024 * 1024) {
      throw const FormatException('invalid Note process payload size');
    }
    final Object? decoded = jsonDecode(
      utf8.decode(payload, allowMalformed: false),
    );
    if (decoded is! Map<String, Object?> ||
        decoded['magic'] != _processMagic ||
        decoded['version'] != _processVersion) {
      throw const FormatException('invalid Note process protocol');
    }
    return decoded;
  }

  static void _requireExactKeys(
    Map<String, Object?> value,
    Set<String> expected,
  ) {
    if (value.keys.toSet().length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw const FormatException('invalid Note process fields');
    }
  }

  static T _enumValue<T>(List<T> values, Object? value) {
    if (value is! int || value < 0 || value >= values.length) {
      throw const FormatException('invalid Note process enum');
    }
    return values[value];
  }

  static int _positiveInt(Object? value) {
    final int result = _nonNegativeInt(value);
    if (result == 0 || result > 0xffffffff) {
      throw const FormatException('invalid Note process identity');
    }
    return result;
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0 || value > 0x7fffffffffffffff) {
      throw const FormatException('invalid Note process integer');
    }
    return value;
  }

  static Uint8List _base64Bytes(Object? value) {
    if (value is! String) {
      throw const FormatException('invalid Note process bytes');
    }
    return base64Decode(value);
  }
}

final class _ProcessSession {
  const _ProcessSession({
    required this.authorityGeneration,
    required this.engine,
  });

  final int authorityGeneration;
  final TerminalNoteStoreTransactionEngine engine;
}

/// Store service hosted by the existing dart_terminal lifecycle helper.
final class TerminalNoteStoreProcessWorkerService {
  final Map<int, _ProcessSession> _sessions = <int, _ProcessSession>{};
  var _disposed = false;

  Uint8List handle(Uint8List payload) {
    if (_disposed) throw StateError('Note process worker is disposed');
    final _ProcessRequest request =
        TerminalNoteStoreProcessProtocol.decodeRequest(payload);
    return switch (request.kind) {
      _ProcessRequestKind.open => _open(request),
      _ProcessRequestKind.commit => _apply(request),
      _ProcessRequestKind.export => _apply(request),
      _ProcessRequestKind.stop => _apply(request),
    };
  }

  Uint8List _open(_ProcessRequest request) {
    if (_sessions.containsKey(request.session)) {
      throw const FormatException('duplicate Note process session');
    }
    TerminalNoteStoreTransactionEngine engine;
    try {
      engine = TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(request.path!),
      );
    } on TerminalNoteStoreException catch (error) {
      return TerminalNoteStoreProcessProtocol.encodeResponse(
        _ProcessResponse(
          kind: TerminalNoteStoreWorkerRequestKind.load,
          session: request.session,
          authorityGeneration: request.authorityGeneration,
          sessionOpen: false,
          result: _failure(error.failure),
        ),
      );
    }
    _sessions[request.session] = _ProcessSession(
      authorityGeneration: request.authorityGeneration,
      engine: engine,
    );
    return TerminalNoteStoreProcessProtocol.encodeResponse(
      _ProcessResponse(
        kind: TerminalNoteStoreWorkerRequestKind.load,
        session: request.session,
        authorityGeneration: request.authorityGeneration,
        sessionOpen: true,
        result: engine.load(),
      ),
    );
  }

  Uint8List _apply(_ProcessRequest request) {
    final _ProcessSession? session = _sessions[request.session];
    if (session == null ||
        session.authorityGeneration != request.authorityGeneration) {
      throw const FormatException('unknown Note process session');
    }
    final TerminalNoteStoreWorkerRequestKind kind;
    final TerminalNoteStoreResult result;
    switch (request.kind) {
      case _ProcessRequestKind.open:
        throw const FormatException('duplicate Note process open');
      case _ProcessRequestKind.commit:
        kind = TerminalNoteStoreWorkerRequestKind.commitCandidate;
        result = session.engine.commitCandidate(
          request.document!,
          deletions: request.deletions,
        );
      case _ProcessRequestKind.export:
        kind = TerminalNoteStoreWorkerRequestKind.exportToApprovedPath;
        result = session.engine.exportToApprovedPath(
          TerminalNoteApprovedExportPath.fromAbsolutePath(request.path!),
        );
      case _ProcessRequestKind.stop:
        kind = TerminalNoteStoreWorkerRequestKind.stop;
        result = session.engine.stop();
        _sessions.remove(request.session);
    }
    return TerminalNoteStoreProcessProtocol.encodeResponse(
      _ProcessResponse(
        kind: kind,
        session: request.session,
        authorityGeneration: request.authorityGeneration,
        sessionOpen: request.kind != _ProcessRequestKind.stop,
        result: result,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final _ProcessSession session in _sessions.values) {
      session.engine.stop();
    }
    _sessions.clear();
  }
}

/// Creates product store ports backed by the bundled helper process.
final class TerminalNoteProcessStoreFactory
    implements TerminalNoteAuthorityStoreFactory {
  TerminalNoteProcessStoreFactory(this._client);

  static var _debugLivePortCount = 0;

  static int get debugLivePortCount => _debugLivePortCount;

  final RuntimeWorkerPayloadClient _client;
  var _nextSession = 1;
  TerminalNoteStoreFailure? _lastStartupFailure;

  TerminalNoteStoreFailure? get debugLastStartupFailure => _lastStartupFailure;

  @override
  Future<TerminalNoteAuthorityStoreStartup> start({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
  }) async {
    if (_nextSession > 0xffffffff) {
      _lastStartupFailure = TerminalNoteStoreFailure.resourceLimit;
      return TerminalNoteAuthorityStoreStartup(
        store: null,
        loadResult: _failure(TerminalNoteStoreFailure.resourceLimit),
      );
    }
    final int session = _nextSession++;
    final _ProcessResponse? response = await _request(
      TerminalNoteStoreProcessProtocol.openRequest(
        session: session,
        authorityGeneration: authorityGeneration,
        location: location,
      ),
    );
    if (response == null ||
        response.kind != TerminalNoteStoreWorkerRequestKind.load ||
        response.session != session ||
        response.authorityGeneration != authorityGeneration) {
      _lastStartupFailure = TerminalNoteStoreFailure.workerCrashed;
      return TerminalNoteAuthorityStoreStartup(
        store: null,
        loadResult: _failure(TerminalNoteStoreFailure.workerCrashed),
      );
    }
    if (!response.sessionOpen) {
      _lastStartupFailure = response.result.failure;
      return TerminalNoteAuthorityStoreStartup(
        store: null,
        loadResult: response.result,
      );
    }
    _lastStartupFailure = response.result.failure;
    return TerminalNoteAuthorityStoreStartup(
      store: _TerminalNoteProcessStorePort(
        client: _client,
        session: session,
        authorityGeneration: authorityGeneration,
      ),
      loadResult: response.result,
    );
  }

  Future<_ProcessResponse?> _request(Uint8List payload) async {
    try {
      final RuntimeLifecyclePayloadRequestResult result = await _client
          .requestPayload(payload);
      final Uint8List? response = result.copyPayload();
      if (result.status != RuntimeLifecycleRequestStatus.response ||
          response == null) {
        return null;
      }
      return TerminalNoteStoreProcessProtocol.decodeResponse(response);
    } on Object {
      return null;
    }
  }
}

final class _TerminalNoteProcessStorePort
    implements TerminalNoteAuthorityStorePort {
  _TerminalNoteProcessStorePort({
    required this.client,
    required this.session,
    required this.authorityGeneration,
  }) {
    TerminalNoteProcessStoreFactory._debugLivePortCount++;
  }

  final RuntimeWorkerPayloadClient client;
  final int session;
  final int authorityGeneration;
  var _stopped = false;

  @override
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) => _request(
    TerminalNoteStoreProcessProtocol.commitRequest(
      session: session,
      authorityGeneration: authorityGeneration,
      document: candidate,
      deletions: deletions,
    ),
    TerminalNoteStoreWorkerRequestKind.commitCandidate,
  );

  @override
  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath destination,
  ) => _request(
    TerminalNoteStoreProcessProtocol.exportRequest(
      session: session,
      authorityGeneration: authorityGeneration,
      destination: destination,
    ),
    TerminalNoteStoreWorkerRequestKind.exportToApprovedPath,
  );

  @override
  Future<TerminalNoteStoreResult> stop() async {
    if (_stopped) return _stoppedResult();
    _stopped = true;
    try {
      return await _request(
        TerminalNoteStoreProcessProtocol.stopRequest(
          session: session,
          authorityGeneration: authorityGeneration,
        ),
        TerminalNoteStoreWorkerRequestKind.stop,
        allowStopped: true,
      );
    } finally {
      TerminalNoteProcessStoreFactory._debugLivePortCount--;
    }
  }

  Future<TerminalNoteStoreResult> _request(
    Uint8List payload,
    TerminalNoteStoreWorkerRequestKind expectedKind, {
    bool allowStopped = false,
  }) async {
    if (_stopped && !allowStopped) {
      return _failure(TerminalNoteStoreFailure.invalidState);
    }
    try {
      final RuntimeLifecyclePayloadRequestResult result = await client
          .requestPayload(payload);
      final Uint8List? responseBytes = result.copyPayload();
      if (result.status != RuntimeLifecycleRequestStatus.response ||
          responseBytes == null) {
        return _failure(
          result.status == RuntimeLifecycleRequestStatus.backpressured
              ? TerminalNoteStoreFailure.busy
              : TerminalNoteStoreFailure.workerCrashed,
        );
      }
      final _ProcessResponse response =
          TerminalNoteStoreProcessProtocol.decodeResponse(responseBytes);
      if (response.kind != expectedKind ||
          response.session != session ||
          response.authorityGeneration != authorityGeneration) {
        return _failure(TerminalNoteStoreFailure.protocolViolation);
      }
      return response.result;
    } on Object {
      return _failure(TerminalNoteStoreFailure.protocolViolation);
    }
  }
}

TerminalNoteStoreResult _failure(TerminalNoteStoreFailure failure) =>
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
