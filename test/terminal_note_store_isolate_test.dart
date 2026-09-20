import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNoteStoreIsolateTests();

Future<void> runTerminalNoteStoreIsolateTests() async {
  _testProtocolRoundTripAndRejection();
  _testBoundedIntentAdmission();
  await _testRealIsolateStoreRoundTrip();
  await _testSingleFlightAndLateResponseHandling();
  await _testTimeoutCrashProtocolFailureAndRestart();
  await _testStopTimeoutAndIdempotence();
  _expect(
    TerminalNoteStoreWorkerClient.debugLiveClientCount == 0,
    'all isolate client handles are released',
  );
}

void _testProtocolRoundTripAndRejection() {
  final ReceivePort parent = ReceivePort();
  final TerminalNoteStoreWorkerBootstrapV1 bootstrap =
      TerminalNoteStoreWorkerBootstrapV1(
        authorityGeneration: 7,
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/protocol-store',
        ),
        parentPort: parent.sendPort,
      );
  final TerminalNoteStoreWorkerBootstrapV1 decodedBootstrap =
      TerminalNoteStoreWorkerBootstrapV1.decodeMessage(bootstrap.toMessage());
  _expect(
    decodedBootstrap.authorityGeneration == 7 &&
        decodedBootstrap.location.canonicalPath ==
            '/private/tmp/protocol-store' &&
        !decodedBootstrap.toString().contains('protocol-store'),
    'bootstrap v1 round-trips and redacts its path',
  );

  final TerminalNoteStoreDocument document = _document();
  final TerminalNoteStoreWorkerRequestV1 request =
      TerminalNoteStoreWorkerRequestV1.commitCandidate(
        authorityGeneration: 7,
        requestSequence: 9,
        document: document,
        deletions: const <TerminalNoteDeletionTombstone>[],
      );
  final TerminalNoteStoreWorkerRequestV1 decodedRequest =
      TerminalNoteStoreWorkerRequestV1.decodeMessage(
        request.toMessage(),
        expectedAuthorityGeneration: 7,
      );
  _expect(
    decodedRequest.kind == TerminalNoteStoreWorkerRequestKind.commitCandidate &&
        decodedRequest.requestSequence == 9 &&
        decodedRequest.document!.snapshot.storeRevision ==
            document.snapshot.storeRevision &&
        !decodedRequest.toString().contains('private body'),
    'commit request has exact generation/sequence and redacted formatting',
  );

  final TerminalNoteStoreResult loadResult = _loadResult(document);
  final TerminalNoteStoreWorkerResponseV1 response =
      TerminalNoteStoreWorkerResponseV1(
        authorityGeneration: 7,
        requestSequence: 10,
        requestKind: TerminalNoteStoreWorkerRequestKind.load,
        result: loadResult,
      );
  final TerminalNoteStoreWorkerResponseV1 decodedResponse =
      TerminalNoteStoreWorkerResponseV1.decodeMessage(response.toMessage());
  _expect(
    decodedResponse.authorityGeneration == 7 &&
        decodedResponse.requestSequence == 10 &&
        decodedResponse.result.metrics.noteCount == 1 &&
        decodedResponse.result.document!.snapshot.noteFor(_noteId(1)) != null,
    'load response v1 round-trips its validated document and bounded metrics',
  );

  final List<Object?> wrongVersion = List<Object?>.of(
    request.toMessage() as List<Object?>,
  )..[1] = 2;
  _expectProtocolReject(
    () => TerminalNoteStoreWorkerRequestV1.decodeMessage(
      wrongVersion,
      expectedAuthorityGeneration: 7,
    ),
    'unknown request protocol version is rejected',
  );
  _expectProtocolReject(
    () => TerminalNoteStoreWorkerRequestV1.decodeMessage(
      request.toMessage(),
      expectedAuthorityGeneration: 8,
    ),
    'stale authority generation is rejected by the worker decoder',
  );
  final List<Object?> malformedResponse = List<Object?>.of(
    response.toMessage() as List<Object?>,
  )..[9] = TerminalNoteLimits.maximumNotes + 1;
  _expectProtocolReject(
    () => TerminalNoteStoreWorkerResponseV1.decodeMessage(malformedResponse),
    'unbounded response metrics are rejected',
  );
  _expectProtocolReject(
    () => TerminalNoteStoreWorkerBootstrapV1.decodeMessage(<Object?>[]),
    'wrong field count is rejected',
  );
  parent.close();
}

void _testBoundedIntentAdmission() {
  final TerminalNoteIntentAdmissionQueue<String> queue =
      TerminalNoteIntentAdmissionQueue<String>();
  for (
    var index = 0;
    index < TerminalNoteStoreWorkerLimits.maximumPendingIntents;
    index++
  ) {
    _expect(
      queue.admit('private-$index', bodyBytes: 4 * 1024).isAccepted,
      'intent within count/body cap is admitted',
    );
  }
  _expect(
    queue.pendingCount == 32 &&
        queue.pendingBodyBytes ==
            TerminalNoteStoreWorkerLimits.maximumPendingBodyBytes,
    'queue reaches the exact 32 intent and 128 KiB bounds',
  );
  _expect(
    queue.admit('overflow', bodyBytes: 0).disposition ==
        TerminalNoteIntentAdmissionDisposition.busy,
    '33rd intent is rejected without changing the queue',
  );
  final TerminalNoteAdmittedIntent<String> first = queue.takeFirst()!;
  _expect(
    first.intent == 'private-0' &&
        first.bodyBytes == 4 * 1024 &&
        !first.toString().contains('private-0'),
    'admission is FIFO and entry formatting redacts intent content',
  );
  _expect(
    queue.admit('replacement', bodyBytes: 4 * 1024).isAccepted,
    'released count/body capacity can be reused',
  );
  _expect(
    queue
            .admit(
              'too-large',
              bodyBytes:
                  TerminalNoteStoreWorkerLimits.maximumPendingBodyBytes + 1,
            )
            .disposition ==
        TerminalNoteIntentAdmissionDisposition.invalid,
    'one malformed body cost is rejected',
  );
  queue.close();
  _expect(
    queue.isClosed &&
        queue.pendingCount == 0 &&
        queue.pendingBodyBytes == 0 &&
        queue.admit('late', bodyBytes: 0).disposition ==
            TerminalNoteIntentAdmissionDisposition.closed,
    'close rejects late intents and releases all pending ownership',
  );
}

Future<void> _testRealIsolateStoreRoundTrip() async {
  final int baseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory parent = await Directory.systemTemp.createTemp(
    'dart-terminal-note-isolate-',
  );
  final String resolved = await parent.resolveSymbolicLinks();
  final TerminalNoteStoreLocation location =
      TerminalNoteStoreLocation.fromAbsolutePath('$resolved/store');
  try {
    final TerminalNoteStoreWorkerStartup first =
        await TerminalNoteStoreWorkerClient.start(
          location: location,
          authorityGeneration: 101,
        );
    _expect(
      first.hasLiveClient &&
          first.loadResult.disposition == TerminalNoteStoreDisposition.empty &&
          first.loadResult.document!.snapshot.notes.isEmpty,
      'production isolate opens the lock and returns a validated empty load',
    );
    final TerminalNoteStoreWorkerClient firstClient = first.client!;
    final TerminalNoteStoreDocument document = _document();
    final TerminalNoteStoreResult committed = await firstClient.commitCandidate(
      document,
    );
    _expect(
      committed.disposition == TerminalNoteStoreDisposition.committed &&
          committed.document == null &&
          committed.storeRevision == document.snapshot.storeRevision,
      'one immutable candidate commits across a real isolate',
    );
    final TerminalNoteStoreResult stopped = await firstClient.stop();
    final TerminalNoteStoreResult stoppedAgain = await firstClient.stop();
    _expect(
      stopped.disposition == TerminalNoteStoreDisposition.stopped &&
          stoppedAgain.disposition == TerminalNoteStoreDisposition.stopped &&
          firstClient.pendingRequestCount == 0 &&
          !firstClient.hasLiveIsolate,
      'real worker stop is idempotent and releases its handle',
    );

    final TerminalNoteStoreWorkerStartup restarted =
        await TerminalNoteStoreWorkerClient.start(
          location: location,
          authorityGeneration: 102,
        );
    _expect(
      restarted.hasLiveClient &&
          restarted.loadResult.disposition ==
              TerminalNoteStoreDisposition.loaded &&
          restarted.loadResult.document!.snapshot.noteFor(_noteId(1)) != null,
      'new authority generation restarts and loads the durable candidate',
    );
    await restarted.client!.stop();
  } finally {
    await parent.delete(recursive: true);
  }
  _expect(
    TerminalNoteStoreWorkerClient.debugLiveClientCount == baseline,
    'real isolate/restart leaves no live client handle',
  );
}

Future<void> _testSingleFlightAndLateResponseHandling() async {
  final TerminalNoteStoreWorkerStartup startup =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-busy',
        ),
        authorityGeneration: 201,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(seconds: 1),
        entrypoint: _scriptedWorker,
      );
  _expect(startup.hasLiveClient, 'scripted worker starts');
  final TerminalNoteStoreWorkerClient client = startup.client!;
  final Future<TerminalNoteStoreResult> delayed = client.load();
  final TerminalNoteStoreResult concurrent = await client.retryRecovery();
  _expect(
    concurrent.failure == TerminalNoteStoreFailure.busy &&
        concurrent.disposition == TerminalNoteStoreDisposition.rejected &&
        client.pendingRequestCount == 1,
    'second request is rejected while exactly one request is in flight',
  );
  final Future<TerminalNoteStoreResult> stopping = client.stop();
  final TerminalNoteStoreResult afterFreeze = await client.retryRecovery();
  _expect(
    afterFreeze.failure == TerminalNoteStoreFailure.invalidState,
    'stop freezes new admission while the existing request drains',
  );
  _expect((await delayed).isSuccess, 'the original request still completes');
  _expect(
    (await stopping).disposition == TerminalNoteStoreDisposition.stopped,
    'stop sends one final request after draining the in-flight operation',
  );

  final TerminalNoteStoreWorkerStartup stale =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-stale',
        ),
        authorityGeneration: 205,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(seconds: 1),
        entrypoint: _scriptedWorker,
      );
  final TerminalNoteStoreResult accepted = await stale.client!.load();
  _expect(
    accepted.isSuccess && stale.client!.pendingRequestCount == 0,
    'stale generation and completed-sequence responses are dropped before the exact response',
  );
  await stale.client!.stop();
}

Future<void> _testTimeoutCrashProtocolFailureAndRestart() async {
  final int baseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final TerminalNoteStoreWorkerStartup startupFailure =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-startup-failure',
        ),
        authorityGeneration: 300,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(milliseconds: 100),
        entrypoint: _startupFailureWorker,
      );
  _expect(
    !startupFailure.hasLiveClient &&
        startupFailure.loadResult.failure == TerminalNoteStoreFailure.lockBusy,
    'fixed worker startup failure crosses the ready protocol',
  );

  final TerminalNoteStoreWorkerStartup noReady =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-no-ready',
        ),
        authorityGeneration: 301,
        loadTimeout: const Duration(milliseconds: 40),
        stopTimeout: const Duration(milliseconds: 40),
        entrypoint: _silentBootstrapWorker,
      );
  _expect(
    !noReady.hasLiveClient &&
        noReady.loadResult.failure == TerminalNoteStoreFailure.timeout,
    'worker bootstrap shares the bounded load deadline',
  );

  final TerminalNoteStoreWorkerStartup noLoad =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-no-load',
        ),
        authorityGeneration: 302,
        loadTimeout: const Duration(milliseconds: 40),
        stopTimeout: const Duration(milliseconds: 40),
        entrypoint: _readyButSilentWorker,
      );
  _expect(
    !noLoad.hasLiveClient &&
        noLoad.loadResult.failure == TerminalNoteStoreFailure.timeout,
    'initial load timeout kills the generation without implicit retry',
  );

  final TerminalNoteStoreWorkerStartup crash =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-crash',
        ),
        authorityGeneration: 303,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(milliseconds: 100),
        entrypoint: _crashOnLoadWorker,
      );
  _expect(
    !crash.hasLiveClient &&
        crash.loadResult.failure == TerminalNoteStoreFailure.workerCrashed &&
        !crash.loadResult.toString().contains('PRIVATE-CRASH-SENTINEL'),
    'uncaught worker error is collapsed without exposing its message',
  );

  final TerminalNoteStoreWorkerStartup futureSequence =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-future',
        ),
        authorityGeneration: 304,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(milliseconds: 100),
        entrypoint: _scriptedWorker,
      );
  final TerminalNoteStoreResult protocolFailure = await futureSequence.client!
      .load();
  _expect(
    protocolFailure.failure == TerminalNoteStoreFailure.protocolViolation &&
        futureSequence.client!.pendingRequestCount == 0 &&
        !futureSequence.client!.hasLiveIsolate,
    'future request sequence fails closed and releases the worker',
  );

  final TerminalNoteStoreWorkerStartup restarted =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-normal',
        ),
        authorityGeneration: 305,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(seconds: 1),
        entrypoint: _scriptedWorker,
      );
  _expect(
    restarted.hasLiveClient && restarted.loadResult.isSuccess,
    'explicit new generation restarts after prior crash/protocol failure',
  );
  await restarted.client!.stop();
  _expect(
    TerminalNoteStoreWorkerClient.debugLiveClientCount == baseline,
    'timeout/crash/restart paths release all client handles',
  );
}

Future<void> _testStopTimeoutAndIdempotence() async {
  final int baseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final TerminalNoteStoreWorkerStartup startup =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(
          '/private/tmp/script-stop-silent',
        ),
        authorityGeneration: 401,
        loadTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(milliseconds: 40),
        entrypoint: _scriptedWorker,
      );
  final TerminalNoteStoreWorkerClient client = startup.client!;
  final TerminalNoteStoreResult first = await client.stop();
  final TerminalNoteStoreResult second = await client.stop();
  _expect(
    first.failure == TerminalNoteStoreFailure.timeout &&
        second.failure == TerminalNoteStoreFailure.timeout &&
        client.pendingRequestCount == 0 &&
        !client.hasLiveIsolate &&
        TerminalNoteStoreWorkerClient.debugLiveClientCount == baseline,
    'stop timeout kills once, caches its result, and leaves no pending handle',
  );
}

@pragma('vm:entry-point')
void _silentBootstrapWorker(Object? message) {
  TerminalNoteStoreWorkerBootstrapV1.decodeMessage(message);
  final ReceivePort keepAlive = ReceivePort();
  keepAlive.listen((Object? _) {});
}

@pragma('vm:entry-point')
void _startupFailureWorker(Object? message) {
  final TerminalNoteStoreWorkerBootstrapV1 bootstrap =
      TerminalNoteStoreWorkerBootstrapV1.decodeMessage(message);
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerReadyV1.failed(
      authorityGeneration: bootstrap.authorityGeneration,
      failure: TerminalNoteStoreFailure.lockBusy,
    ).toMessage(),
  );
}

@pragma('vm:entry-point')
void _readyButSilentWorker(Object? message) {
  final TerminalNoteStoreWorkerBootstrapV1 bootstrap =
      TerminalNoteStoreWorkerBootstrapV1.decodeMessage(message);
  final ReceivePort requests = ReceivePort();
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerReadyV1.ready(
      authorityGeneration: bootstrap.authorityGeneration,
      requestPort: requests.sendPort,
    ).toMessage(),
  );
  requests.listen((Object? _) {});
}

@pragma('vm:entry-point')
void _crashOnLoadWorker(Object? message) {
  final TerminalNoteStoreWorkerBootstrapV1 bootstrap =
      TerminalNoteStoreWorkerBootstrapV1.decodeMessage(message);
  final ReceivePort requests = ReceivePort();
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerReadyV1.ready(
      authorityGeneration: bootstrap.authorityGeneration,
      requestPort: requests.sendPort,
    ).toMessage(),
  );
  requests.listen((Object? _) {
    throw StateError('PRIVATE-CRASH-SENTINEL');
  });
}

@pragma('vm:entry-point')
void _scriptedWorker(Object? message) {
  final TerminalNoteStoreWorkerBootstrapV1 bootstrap =
      TerminalNoteStoreWorkerBootstrapV1.decodeMessage(message);
  final String scenario = bootstrap.location.canonicalPath;
  final ReceivePort requests = ReceivePort();
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerReadyV1.ready(
      authorityGeneration: bootstrap.authorityGeneration,
      requestPort: requests.sendPort,
    ).toMessage(),
  );
  var requestCount = 0;
  requests.listen((Object? value) {
    final TerminalNoteStoreWorkerRequestV1 request =
        TerminalNoteStoreWorkerRequestV1.decodeMessage(
          value,
          expectedAuthorityGeneration: bootstrap.authorityGeneration,
        );
    requestCount++;
    if (scenario.endsWith('stop-silent') &&
        request.kind == TerminalNoteStoreWorkerRequestKind.stop) {
      return;
    }
    if (scenario.endsWith('busy') && requestCount == 2) {
      Timer(
        const Duration(milliseconds: 30),
        () => _sendScriptedResult(bootstrap, request),
      );
      return;
    }
    if (scenario.endsWith('stale') && requestCount == 2) {
      bootstrap.parentPort.send(
        TerminalNoteStoreWorkerResponseV1(
          authorityGeneration: bootstrap.authorityGeneration - 1,
          requestSequence: request.requestSequence,
          requestKind: request.kind,
          result: _emptyLoadResult(),
        ).toMessage(),
      );
      bootstrap.parentPort.send(
        TerminalNoteStoreWorkerResponseV1(
          authorityGeneration: bootstrap.authorityGeneration,
          requestSequence: request.requestSequence - 1,
          requestKind: request.kind,
          result: _emptyLoadResult(),
        ).toMessage(),
      );
      Timer(
        const Duration(milliseconds: 10),
        () => _sendScriptedResult(bootstrap, request),
      );
      return;
    }
    if (scenario.endsWith('future') && requestCount == 2) {
      bootstrap.parentPort.send(
        TerminalNoteStoreWorkerResponseV1(
          authorityGeneration: bootstrap.authorityGeneration,
          requestSequence: request.requestSequence + 1,
          requestKind: request.kind,
          result: _emptyLoadResult(),
        ).toMessage(),
      );
      return;
    }
    _sendScriptedResult(bootstrap, request);
    if (request.kind == TerminalNoteStoreWorkerRequestKind.stop) {
      requests.close();
    }
  });
}

void _sendScriptedResult(
  TerminalNoteStoreWorkerBootstrapV1 bootstrap,
  TerminalNoteStoreWorkerRequestV1 request,
) {
  bootstrap.parentPort.send(
    TerminalNoteStoreWorkerResponseV1(
      authorityGeneration: bootstrap.authorityGeneration,
      requestSequence: request.requestSequence,
      requestKind: request.kind,
      result: request.kind == TerminalNoteStoreWorkerRequestKind.stop
          ? TerminalNoteStoreResult(
              disposition: TerminalNoteStoreDisposition.stopped,
              failure: null,
              storeRevision: BigInt.zero,
              metrics: TerminalNoteStoreMetrics.zero,
            )
          : _emptyLoadResult(),
    ).toMessage(),
  );
}

TerminalNoteStoreResult _emptyLoadResult() {
  final TerminalNoteStoreDocument document = TerminalNoteStoreDocument(
    snapshot: TerminalNoteSnapshot.empty(),
  );
  return _loadResult(document, disposition: TerminalNoteStoreDisposition.empty);
}

TerminalNoteStoreResult _loadResult(
  TerminalNoteStoreDocument document, {
  TerminalNoteStoreDisposition disposition =
      TerminalNoteStoreDisposition.loaded,
}) => TerminalNoteStoreResult(
  disposition: disposition,
  failure: null,
  storeRevision: document.snapshot.storeRevision,
  metrics: TerminalNoteStoreMetrics(
    noteCount: document.snapshot.notes.length,
    activeCount: document.snapshot.notes.values
        .where((NoteRecord note) => note.status == NoteStatus.active)
        .length,
    dueCount: document.snapshot.deliveries.length,
    detachedCount: document.snapshot.notes.values
        .where((NoteRecord note) => note.attachment.isDetached)
        .length,
    canonicalBytes: const TerminalNoteStoreCodec().encode(document).length,
  ),
  document: document,
);

TerminalNoteStoreDocument _document() {
  final TerminalNoteContextId contextId = _contextId(1);
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
      id: _noteId(1),
      contextId: contextId,
      body: 'private body',
      color: NoteColorKey.yellow,
      utcMicros: 10,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  return TerminalNoteStoreDocument(snapshot: snapshot);
}

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

void _expectProtocolReject(void Function() callback, String description) {
  try {
    callback();
  } on TerminalNoteStoreProtocolException {
    return;
  }
  throw StateError('expected protocol rejection: $description');
}

void _expect(bool value, String description) {
  if (!value) throw StateError(description);
}
