import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/src/runtime_image_worker.dart';
import 'package:dart_terminal/src/runtime_image_worker_protocol.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/runtime_worker_protocol.dart';

Future<void> main() => runRuntimeImageWorkerTests();

Future<void> runRuntimeImageWorkerTests() async {
  _testRequestAndResponseCodecs();
  _testRawRgbAndRgbaDecode();
  _testZlibDecode();
  _testPngColorTypesAndFilters();
  _testMultipartAbortReplacementAndLimits();
  _testMalformedDecodeInputs();
  _testWorkerOnlySourceBoundary();
  await _testRealWorkerPayloadRoundTrip();
  await _testRealWorkerFailureAndPendingTeardown();
}

void _testRequestAndResponseCodecs() {
  final RuntimeImageWorkerRequest request = RuntimeImageWorkerRequest.chunk(
    paneId: 7,
    sessionGeneration: 9,
    transferGeneration: 11,
    start: true,
    finalChunk: false,
    compressed: true,
    format: 32,
    width: 2,
    height: 1,
    declaredDataSize: 8,
    data: _bytes('AAAA'),
  );
  final Uint8List encoded = RuntimeImageWorkerRequestCodec.encode(request);
  final RuntimeImageWorkerRequest decoded =
      RuntimeImageWorkerRequestCodec.decode(encoded);
  encoded.last = 0x5a;
  _expect(
    decoded.kind == RuntimeImageWorkerRequestKind.chunk &&
        decoded.paneId == 7 &&
        decoded.sessionGeneration == 9 &&
        decoded.transferGeneration == 11 &&
        decoded.start &&
        !decoded.finalChunk &&
        decoded.compressed &&
        decoded.format == 32 &&
        decoded.width == 2 &&
        decoded.height == 1 &&
        decoded.declaredDataSize == 8 &&
        ascii.decode(decoded.copyData()) == 'AAAA',
    'image request codec is exact and decoded data is copied',
  );
  _expect(
    RuntimeImageWorkerRequestCodec.hasMagic(
      RuntimeImageWorkerRequestCodec.encode(request),
    ),
    'image request magic is detectable without decoding arbitrary payloads',
  );

  final RuntimeImageWorkerRequest abort = RuntimeImageWorkerRequest.abort(
    paneId: 7,
    sessionGeneration: 9,
    transferGeneration: 11,
  );
  _expect(
    RuntimeImageWorkerRequestCodec.decode(
          RuntimeImageWorkerRequestCodec.encode(abort),
        ).kind ==
        RuntimeImageWorkerRequestKind.abort,
    'abort request round trips without chunk metadata',
  );

  final RuntimeImageWorkerResponse response = RuntimeImageWorkerResponse(
    status: RuntimeImageWorkerStatus.decoded,
    paneId: 7,
    sessionGeneration: 9,
    transferGeneration: 11,
    width: 1,
    height: 1,
    rgba: Uint8List.fromList(const <int>[1, 2, 3, 4]),
  );
  final Uint8List encodedResponse = RuntimeImageWorkerResponseCodec.encode(
    response,
  );
  final RuntimeImageWorkerResponse decodedResponse =
      RuntimeImageWorkerResponseCodec.decode(encodedResponse);
  encodedResponse.last = 99;
  _expectInts(decodedResponse.copyRgba(), const <int>[
    1,
    2,
    3,
    4,
  ], 'image response codec copies canonical RGBA bytes');

  _expectThrows(
    () => RuntimeImageWorkerRequestCodec.encode(
      RuntimeImageWorkerRequest.chunk(
        paneId: 1,
        sessionGeneration: 1,
        transferGeneration: 1,
        start: false,
        finalChunk: true,
        format: 32,
        width: 1,
        data: _bytes('AAAA'),
      ),
    ),
    'continuation requests cannot repeat start metadata',
  );
  _expectThrows(
    () => RuntimeImageWorkerResponseCodec.encode(
      RuntimeImageWorkerResponse(
        status: RuntimeImageWorkerStatus.decoded,
        paneId: 1,
        sessionGeneration: 1,
        transferGeneration: 1,
        width: 1,
        height: 1,
        rgba: Uint8List(3),
      ),
    ),
    'decoded response dimensions must exactly match RGBA bytes',
  );
}

void _testRawRgbAndRgbaDecode() {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  final RuntimeImageWorkerResponse rgb = _handleChunk(
    service,
    format: 24,
    width: 2,
    height: 1,
    data: const <int>[0xff, 0, 0, 0, 0xff, 0],
  );
  _expect(
    rgb.status == RuntimeImageWorkerStatus.decoded &&
        rgb.width == 2 &&
        rgb.height == 1,
    'raw RGB decodes to a typed image',
  );
  _expectInts(rgb.copyRgba(), const <int>[
    0xff,
    0,
    0,
    0xff,
    0,
    0xff,
    0,
    0xff,
  ], 'raw RGB receives opaque alpha');

  final RuntimeImageWorkerResponse rgba = _handleChunk(
    service,
    transferGeneration: 2,
    format: 32,
    width: 1,
    height: 2,
    data: const <int>[1, 2, 3, 4, 5, 6, 7, 8],
  );
  _expectInts(rgba.copyRgba(), const <int>[
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
  ], 'raw RGBA survives canonical decode exactly');
  service.dispose();
}

void _testZlibDecode() {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  const List<int> rgba = <int>[1, 2, 3, 4, 5, 6, 7, 8];
  final Uint8List compressed = Uint8List.fromList(ZLibEncoder().convert(rgba));
  final RuntimeImageWorkerResponse response = _handleChunk(
    service,
    format: 32,
    width: 2,
    height: 1,
    data: compressed,
    compressed: true,
    declaredDataSize: rgba.length,
  );
  _expect(
    response.status == RuntimeImageWorkerStatus.decoded,
    'RFC 1950 zlib raw data decodes',
  );
  _expectInts(response.copyRgba(), rgba, 'zlib output is exact');

  final RuntimeImageWorkerResponse wrongSize = _handleChunk(
    service,
    transferGeneration: 2,
    format: 32,
    width: 2,
    height: 1,
    data: compressed,
    compressed: true,
    declaredDataSize: rgba.length + 1,
  );
  _expect(
    wrongSize.status == RuntimeImageWorkerStatus.invalidDataLength,
    'declared decompressed length mismatch fails closed',
  );
  service.dispose();
}

void _testPngColorTypesAndFilters() {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  final List<({int colorType, List<int> row, List<int> expected})> cases =
      <({int colorType, List<int> row, List<int> expected})>[
        (colorType: 0, row: <int>[42], expected: <int>[42, 42, 42, 0xff]),
        (colorType: 2, row: <int>[1, 2, 3], expected: <int>[1, 2, 3, 0xff]),
        (colorType: 4, row: <int>[42, 128], expected: <int>[42, 42, 42, 128]),
        (colorType: 6, row: <int>[1, 2, 3, 4], expected: <int>[1, 2, 3, 4]),
      ];
  var generation = 1;
  for (final ({int colorType, List<int> row, List<int> expected}) testCase
      in cases) {
    final Uint8List png = _png(
      width: 1,
      colorType: testCase.colorType,
      rows: <List<int>>[testCase.row],
    );
    final RuntimeImageWorkerResponse response = _handleChunk(
      service,
      transferGeneration: generation++,
      format: 100,
      width: 0,
      height: 0,
      data: png,
    );
    _expect(
      response.status == RuntimeImageWorkerStatus.decoded,
      'PNG color type ${testCase.colorType} decodes',
    );
    _expectInts(
      response.copyRgba(),
      testCase.expected,
      'PNG color type ${testCase.colorType} canonical RGBA',
    );
  }

  final Uint8List indexed = _png(
    width: 1,
    colorType: 3,
    rows: const <List<int>>[
      <int>[1],
    ],
    palette: const <int>[10, 20, 30, 40, 50, 60],
    transparency: const <int>[255, 128],
  );
  final RuntimeImageWorkerResponse indexedResponse = _handleChunk(
    service,
    transferGeneration: generation++,
    format: 100,
    width: 1,
    height: 1,
    data: indexed,
  );
  _expectInts(indexedResponse.copyRgba(), const <int>[
    40,
    50,
    60,
    128,
  ], 'indexed PNG palette and tRNS alpha decode');

  const List<int> filterRow = <int>[10, 20, 30, 40, 50, 60, 70, 80];
  final RuntimeImageWorkerResponse filters = _handleChunk(
    service,
    transferGeneration: generation++,
    format: 100,
    width: 2,
    height: 5,
    data: _png(
      width: 2,
      colorType: 6,
      rows: List<List<int>>.generate(5, (_) => filterRow),
      filters: const <int>[0, 1, 2, 3, 4],
    ),
  );
  _expect(
    filters.status == RuntimeImageWorkerStatus.decoded &&
        filters.copyRgba().length == filterRow.length * 5,
    'all five PNG row filters decode under exact output bounds',
  );
  for (
    var offset = 0;
    offset < filters.rgbaLength;
    offset += filterRow.length
  ) {
    _expectInts(
      filters.copyRgba().sublist(offset, offset + filterRow.length),
      filterRow,
      'PNG filtered row ${offset ~/ filterRow.length} is exact',
    );
  }

  final Uint8List compressedPng = Uint8List.fromList(
    ZLibEncoder().convert(indexed),
  );
  final RuntimeImageWorkerResponse compressedResponse = _handleChunk(
    service,
    transferGeneration: generation,
    format: 100,
    width: 1,
    height: 1,
    data: compressedPng,
    compressed: true,
    declaredDataSize: indexed.length,
  );
  _expectInts(compressedResponse.copyRgba(), const <int>[
    40,
    50,
    60,
    128,
  ], 'outer zlib-compressed PNG decodes before PNG parsing');
  service.dispose();
}

void _testMultipartAbortReplacementAndLimits() {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  final String encoded = base64.encode(const <int>[1, 2, 3, 4, 5, 6]);
  final RuntimeImageWorkerResponse pending = _send(
    service,
    RuntimeImageWorkerRequest.chunk(
      paneId: 1,
      sessionGeneration: 1,
      transferGeneration: 1,
      start: true,
      finalChunk: false,
      format: 24,
      width: 2,
      height: 1,
      data: _bytes(encoded.substring(0, 4)),
    ),
  );
  _expect(
    pending.status == RuntimeImageWorkerStatus.pending &&
        service.pendingTransferCount == 1 &&
        service.pendingEncodedBytes == 4,
    'first multipart chunk is retained only in the worker',
  );
  final RuntimeImageWorkerResponse decoded = _send(
    service,
    RuntimeImageWorkerRequest.chunk(
      paneId: 1,
      sessionGeneration: 1,
      transferGeneration: 1,
      start: false,
      finalChunk: true,
      data: _bytes(encoded.substring(4)),
    ),
  );
  _expect(
    decoded.status == RuntimeImageWorkerStatus.decoded &&
        service.pendingTransferCount == 0 &&
        service.pendingEncodedBytes == 0,
    'matching final multipart chunk decodes and releases encoded storage',
  );

  _send(
    service,
    RuntimeImageWorkerRequest.chunk(
      paneId: 1,
      sessionGeneration: 1,
      transferGeneration: 2,
      start: true,
      finalChunk: false,
      format: 32,
      width: 1,
      height: 1,
      data: _bytes('AAAA'),
    ),
  );
  final RuntimeImageWorkerResponse stale = _send(
    service,
    RuntimeImageWorkerRequest.chunk(
      paneId: 1,
      sessionGeneration: 1,
      transferGeneration: 1,
      start: false,
      finalChunk: true,
      data: _bytes('AAAA'),
    ),
  );
  _expect(
    stale.status == RuntimeImageWorkerStatus.noPendingTransfer &&
        service.pendingTransferCount == 1,
    'stale continuation cannot consume the current transfer',
  );
  final RuntimeImageWorkerResponse aborted = _send(
    service,
    RuntimeImageWorkerRequest.abort(
      paneId: 1,
      sessionGeneration: 1,
      transferGeneration: 2,
    ),
  );
  _expect(
    aborted.status == RuntimeImageWorkerStatus.aborted &&
        service.pendingTransferCount == 0,
    'abort releases the current multipart transfer',
  );
  _expect(
    _send(
          service,
          RuntimeImageWorkerRequest.abort(
            paneId: 1,
            sessionGeneration: 1,
            transferGeneration: 2,
          ),
        ).status ==
        RuntimeImageWorkerStatus.noPendingTransfer,
    'duplicate abort is typed and idempotent',
  );

  service.dispose();
  final RuntimeImageWorkerService transferLimited = RuntimeImageWorkerService(
    maximumPendingTransfers: 2,
    maximumPendingEncodedBytes: 16,
  );
  for (var pane = 1; pane <= 2; pane++) {
    final RuntimeImageWorkerResponse response = _send(
      transferLimited,
      RuntimeImageWorkerRequest.chunk(
        paneId: pane,
        sessionGeneration: 2,
        transferGeneration: 1,
        start: true,
        finalChunk: false,
        format: 32,
        width: 1,
        height: 1,
        data: _bytes('AAAA'),
      ),
    );
    _expect(
      response.status == RuntimeImageWorkerStatus.pending,
      'pending transfer $pane is admitted within the configured cap',
    );
  }
  final RuntimeImageWorkerResponse saturated = _send(
    transferLimited,
    RuntimeImageWorkerRequest.chunk(
      paneId: 3,
      sessionGeneration: 2,
      transferGeneration: 1,
      start: true,
      finalChunk: false,
      format: 32,
      width: 1,
      height: 1,
      data: _bytes('AAAA'),
    ),
  );
  _expect(
    saturated.status == RuntimeImageWorkerStatus.resourceLimit &&
        transferLimited.pendingTransferCount == 2,
    'the next concurrent transfer is rejected without evicting prior work',
  );
  transferLimited.dispose();
  _expect(
    transferLimited.pendingTransferCount == 0 &&
        transferLimited.pendingEncodedBytes == 0,
    'worker dispose clears all bounded pending ownership',
  );

  final RuntimeImageWorkerService imageLimited = RuntimeImageWorkerService(
    maximumEncodedBytes: 8,
    maximumPendingEncodedBytes: 16,
  );
  _expect(
    _beginPending(imageLimited, paneId: 1).status ==
        RuntimeImageWorkerStatus.pending,
    'per-image encoded cap admits its first chunk',
  );
  _expect(
    _send(
          imageLimited,
          RuntimeImageWorkerRequest.chunk(
            paneId: 1,
            sessionGeneration: 2,
            transferGeneration: 1,
            start: false,
            finalChunk: false,
            data: _bytes('AAAA'),
          ),
        ).status ==
        RuntimeImageWorkerStatus.pending,
    'per-image encoded cap admits its exact boundary',
  );
  _expect(
    _send(
          imageLimited,
          RuntimeImageWorkerRequest.chunk(
            paneId: 1,
            sessionGeneration: 2,
            transferGeneration: 1,
            start: false,
            finalChunk: false,
            data: _bytes('AAAA'),
          ),
        ).status ==
        RuntimeImageWorkerStatus.resourceLimit,
    'per-image encoded overflow rejects and releases the transfer',
  );
  _expect(imageLimited.pendingTransferCount == 0, 'overflow releases bytes');
  imageLimited.dispose();

  final RuntimeImageWorkerService aggregateLimited = RuntimeImageWorkerService(
    maximumEncodedBytes: 16,
    maximumPendingTransfers: 3,
    maximumPendingEncodedBytes: 8,
  );
  _beginPending(aggregateLimited, paneId: 1);
  _beginPending(aggregateLimited, paneId: 2);
  _expect(
    _beginPending(aggregateLimited, paneId: 3).status ==
            RuntimeImageWorkerStatus.resourceLimit &&
        aggregateLimited.pendingTransferCount == 2 &&
        aggregateLimited.pendingEncodedBytes == 8,
    'aggregate encoded cap rejects only the newly admitted transfer',
  );
  aggregateLimited.dispose();
}

void _testMalformedDecodeInputs() {
  RuntimeImageWorkerResponse handle({
    required int generation,
    required int format,
    required int width,
    required int height,
    required Uint8List encoded,
    bool compressed = false,
    int declaredDataSize = 0,
  }) {
    final RuntimeImageWorkerService service = RuntimeImageWorkerService();
    final RuntimeImageWorkerResponse response = _send(
      service,
      RuntimeImageWorkerRequest.chunk(
        paneId: 1,
        sessionGeneration: 1,
        transferGeneration: generation,
        start: true,
        finalChunk: true,
        compressed: compressed,
        format: format,
        width: width,
        height: height,
        declaredDataSize: declaredDataSize,
        data: encoded,
      ),
    );
    service.dispose();
    return response;
  }

  _expect(
    RuntimeImageWorkerResponseCodec.decode(
          RuntimeImageWorkerService().handle(Uint8List(3)),
        ).status ==
        RuntimeImageWorkerStatus.invalidRequest,
    'malformed image subprotocol request returns a typed error',
  );
  _expect(
    handle(
          generation: 1,
          format: 32,
          width: 1,
          height: 1,
          encoded: _bytes('%%%='),
        ).status ==
        RuntimeImageWorkerStatus.invalidBase64,
    'non-RFC4648 payload is rejected',
  );
  _expect(
    handle(
          generation: 2,
          format: 99,
          width: 1,
          height: 1,
          encoded: _bytes('AAAA'),
        ).status ==
        RuntimeImageWorkerStatus.unsupportedFormat,
    'unknown pixel format is rejected',
  );
  _expect(
    handle(
          generation: 3,
          format: 24,
          width: 0,
          height: 1,
          encoded: _bytes('AAAA'),
        ).status ==
        RuntimeImageWorkerStatus.invalidDimensions,
    'raw zero dimensions are rejected',
  );
  _expect(
    handle(
          generation: 4,
          format: 32,
          width: 1,
          height: 1,
          encoded: _bytes('AAAA'),
        ).status ==
        RuntimeImageWorkerStatus.invalidDataLength,
    'raw byte-length mismatch is rejected',
  );
  _expect(
    handle(
          generation: 5,
          format: 32,
          width: 1,
          height: 1,
          encoded: _bytes(base64.encode(const <int>[1, 2, 3, 4])),
          compressed: true,
        ).status ==
        RuntimeImageWorkerStatus.invalidCompression,
    'malformed zlib input is rejected',
  );
  final Uint8List expansion = Uint8List.fromList(
    ZLibEncoder().convert(List<int>.filled(64, 0)),
  );
  _expect(
    handle(
          generation: 51,
          format: 32,
          width: 1,
          height: 1,
          encoded: _bytes(base64.encode(expansion)),
          compressed: true,
        ).status ==
        RuntimeImageWorkerStatus.resourceLimit,
    'zlib output beyond the exact raw image size is stopped by the sink cap',
  );

  final Uint8List badCrc = _png(
    width: 1,
    colorType: 6,
    rows: const <List<int>>[
      <int>[1, 2, 3, 4],
    ],
  )..[29] ^= 1;
  _expect(
    handle(
          generation: 6,
          format: 100,
          width: 0,
          height: 0,
          encoded: _bytes(base64.encode(badCrc)),
        ).status ==
        RuntimeImageWorkerStatus.invalidPng,
    'PNG CRC mismatch is rejected',
  );
  final Uint8List interlaced = _png(
    width: 1,
    colorType: 6,
    rows: const <List<int>>[
      <int>[1, 2, 3, 4],
    ],
    interlace: 1,
  );
  _expect(
    handle(
          generation: 7,
          format: 100,
          width: 0,
          height: 0,
          encoded: _bytes(base64.encode(interlaced)),
        ).status ==
        RuntimeImageWorkerStatus.invalidPng,
    'interlaced PNG is explicitly rejected',
  );

  _expectThrows(
    () => RuntimeImageWorkerRequestCodec.encode(
      RuntimeImageWorkerRequest.chunk(
        paneId: 1,
        sessionGeneration: 1,
        transferGeneration: 1,
        start: true,
        finalChunk: true,
        format: 32,
        width: 1,
        height: 1,
        data: Uint8List(RuntimeImageWorkerLimits.maximumChunkBytes + 1),
      ),
    ),
    'IPC codec rejects data larger than one APC chunk',
  );
  _expectThrows(
    () => RuntimeImageWorkerService(maximumPendingTransfers: 0),
    'worker limit overrides cannot disable or exceed product caps',
  );
}

void _testWorkerOnlySourceBoundary() {
  final String lifecycle = File(
    '${Directory.current.path}/lib/src/runtime_lifecycle.dart',
  ).readAsStringSync();
  final String worker = File(
    '${Directory.current.path}/lib/src/runtime_worker.dart',
  ).readAsStringSync();
  final String decoder = File(
    '${Directory.current.path}/lib/src/runtime_image_worker.dart',
  ).readAsStringSync();
  final String entrypoint = File(
    '${Directory.current.path}/bin/runtime_worker.dart',
  ).readAsStringSync();
  _expect(
    !lifecycle.contains('runtime_image_worker.dart') &&
        !lifecycle.contains('runRuntimeLifecycleWorkerProcess') &&
        worker.contains("import 'runtime_image_worker.dart';") &&
        decoder.contains('base64.decode') &&
        decoder.contains('ZLibDecoder') &&
        entrypoint.contains('src/runtime_worker.dart'),
    'base64/zlib/PNG implementation is reachable only from worker source',
  );
}

Future<void> _testRealWorkerPayloadRoundTrip() async {
  final RuntimeLifecycleCoordinator coordinator = _coordinator(
    RuntimeLifecycleScenario.normal,
  );
  _expect(
    await coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'real image worker reaches ready',
  );
  final RuntimeImageWorkerRequest request = RuntimeImageWorkerRequest.chunk(
    paneId: 9,
    sessionGeneration: 3,
    transferGeneration: 7,
    start: true,
    finalChunk: true,
    format: 32,
    width: 1,
    height: 1,
    data: _bytes(base64.encode(const <int>[4, 3, 2, 1])),
  );
  final RuntimeLifecyclePayloadRequestResult result = await coordinator
      .requestPayload(RuntimeImageWorkerRequestCodec.encode(request));
  _expect(
    result.status == RuntimeLifecycleRequestStatus.response,
    'real worker returns a typed payload response',
  );
  final RuntimeImageWorkerResponse response =
      RuntimeImageWorkerResponseCodec.decode(result.copyPayload()!);
  _expect(
    response.status == RuntimeImageWorkerStatus.decoded &&
        response.paneId == 9 &&
        response.sessionGeneration == 3 &&
        response.transferGeneration == 7,
    'real worker preserves session and transfer generations',
  );
  _expectInts(response.copyRgba(), const <int>[
    4,
    3,
    2,
    1,
  ], 'real worker returns canonical RGBA bytes');
  var oversizedRejected = false;
  try {
    await coordinator.requestPayload(
      Uint8List(runtimeWorkerMaximumPayloadLength + 1),
    );
  } on RangeError {
    oversizedRejected = true;
  }
  _expect(
    oversizedRejected,
    'coordinator rejects oversized payloads before touching the worker',
  );
  _expect(
    (await coordinator.request(41)).value == 42,
    'legacy signed-int traffic remains compatible beside image payloads',
  );
  await coordinator.shutdown();
  _expect(
    RuntimeLifecycleCoordinator.outstandingProcessCount == 0,
    'real image worker is reaped after graceful shutdown',
  );
}

Future<void> _testRealWorkerFailureAndPendingTeardown() async {
  final RuntimeLifecycleCoordinator failing = _coordinator(
    RuntimeLifecycleScenario.workerUnexpectedExit,
  );
  await failing.start();
  final RuntimeLifecyclePayloadRequestResult failure = await failing
      .requestPayload(
        RuntimeImageWorkerRequestCodec.encode(
          RuntimeImageWorkerRequest.chunk(
            paneId: 1,
            sessionGeneration: 1,
            transferGeneration: 1,
            start: true,
            finalChunk: true,
            format: 32,
            width: 1,
            height: 1,
            data: _bytes('AAAAAA=='),
          ),
        ),
      );
  _expect(
    failure.status == RuntimeLifecycleRequestStatus.unexpectedExit,
    'worker exit classifies an in-flight image payload request',
  );
  await failing.shutdown();

  final RuntimeLifecycleCoordinator first = _coordinator(
    RuntimeLifecycleScenario.normal,
  );
  await first.start();
  final RuntimeLifecyclePayloadRequestResult pending = await first
      .requestPayload(
        RuntimeImageWorkerRequestCodec.encode(
          RuntimeImageWorkerRequest.chunk(
            paneId: 1,
            sessionGeneration: 1,
            transferGeneration: 2,
            start: true,
            finalChunk: false,
            format: 32,
            width: 1,
            height: 1,
            data: _bytes('AAAA'),
          ),
        ),
      );
  _expect(
    RuntimeImageWorkerResponseCodec.decode(pending.copyPayload()!).status ==
        RuntimeImageWorkerStatus.pending,
    'real worker holds one partial transfer before shutdown',
  );
  await first.shutdown();

  final RuntimeLifecycleCoordinator replacement = _coordinator(
    RuntimeLifecycleScenario.normal,
    initialGeneration: first.generation,
  );
  await replacement.start();
  final RuntimeLifecyclePayloadRequestResult continuation = await replacement
      .requestPayload(
        RuntimeImageWorkerRequestCodec.encode(
          RuntimeImageWorkerRequest.chunk(
            paneId: 1,
            sessionGeneration: 1,
            transferGeneration: 2,
            start: false,
            finalChunk: true,
            data: _bytes('AAAA'),
          ),
        ),
      );
  _expect(
    RuntimeImageWorkerResponseCodec.decode(continuation.copyPayload()!)
            .status ==
        RuntimeImageWorkerStatus.noPendingTransfer,
    'replacement worker cannot resurrect predecessor pending bytes',
  );
  await replacement.shutdown();
  _expect(
    RuntimeLifecycleCoordinator.outstandingProcessCount == 0,
    'failure and replacement workers are completely reaped',
  );
}

RuntimeLifecycleCoordinator _coordinator(
  RuntimeLifecycleScenario scenario, {
  int initialGeneration = 0,
}) => RuntimeLifecycleCoordinator(
  scenario: scenario,
  observer: (_) {},
  initialGeneration: initialGeneration,
  startupTimeout: const Duration(seconds: 15),
  workerCommand: RuntimeLifecycleWorkerCommand(
    executable: Platform.resolvedExecutable,
    arguments: <String>['${Directory.current.path}/bin/runtime_worker.dart'],
    workingDirectory: Directory.current.path,
  ),
);

RuntimeImageWorkerResponse _handleChunk(
  RuntimeImageWorkerService service, {
  int transferGeneration = 1,
  required int format,
  required int width,
  required int height,
  required List<int> data,
  bool compressed = false,
  int declaredDataSize = 0,
}) => _send(
  service,
  RuntimeImageWorkerRequest.chunk(
    paneId: 1,
    sessionGeneration: 1,
    transferGeneration: transferGeneration,
    start: true,
    finalChunk: true,
    compressed: compressed,
    format: format,
    width: width,
    height: height,
    declaredDataSize: declaredDataSize,
    data: _bytes(base64.encode(data)),
  ),
);

RuntimeImageWorkerResponse _send(
  RuntimeImageWorkerService service,
  RuntimeImageWorkerRequest request,
) => RuntimeImageWorkerResponseCodec.decode(
  service.handle(RuntimeImageWorkerRequestCodec.encode(request)),
);

RuntimeImageWorkerResponse _beginPending(
  RuntimeImageWorkerService service, {
  required int paneId,
}) => _send(
  service,
  RuntimeImageWorkerRequest.chunk(
    paneId: paneId,
    sessionGeneration: 2,
    transferGeneration: 1,
    start: true,
    finalChunk: false,
    format: 32,
    width: 1,
    height: 1,
    data: _bytes('AAAA'),
  ),
);

Uint8List _png({
  required int width,
  required int colorType,
  required List<List<int>> rows,
  List<int> filters = const <int>[0],
  List<int>? palette,
  List<int>? transparency,
  int interlace = 0,
}) {
  _expect(rows.isNotEmpty, 'PNG test rows are nonempty');
  final int bytesPerPixel = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => throw ArgumentError.value(colorType),
  };
  final ByteData header = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, rows.length, Endian.big)
    ..setUint8(8, 8)
    ..setUint8(9, colorType)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, interlace);
  final BytesBuilder scanlines = BytesBuilder(copy: false);
  List<int> previous = List<int>.filled(width * bytesPerPixel, 0);
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final List<int> row = rows[rowIndex];
    _expect(
      row.length == width * bytesPerPixel,
      'PNG test row has the expected byte width',
    );
    final int filter = filters[rowIndex % filters.length];
    scanlines.addByte(filter);
    final Uint8List filtered = Uint8List(row.length);
    for (var index = 0; index < row.length; index++) {
      final int left = index >= bytesPerPixel ? row[index - bytesPerPixel] : 0;
      final int above = previous[index];
      final int upperLeft = index >= bytesPerPixel
          ? previous[index - bytesPerPixel]
          : 0;
      final int predictor = switch (filter) {
        0 => 0,
        1 => left,
        2 => above,
        3 => (left + above) ~/ 2,
        4 => _paeth(left, above, upperLeft),
        _ => throw ArgumentError.value(filter),
      };
      filtered[index] = (row[index] - predictor) & 0xff;
    }
    scanlines.add(filtered);
    previous = row;
  }
  final BytesBuilder png = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_pngChunk('IHDR', header.buffer.asUint8List()));
  if (palette != null) png.add(_pngChunk('PLTE', Uint8List.fromList(palette)));
  if (transparency != null) {
    png.add(_pngChunk('tRNS', Uint8List.fromList(transparency)));
  }
  png
    ..add(
      _pngChunk(
        'IDAT',
        Uint8List.fromList(ZLibEncoder().convert(scanlines.toBytes())),
      ),
    )
    ..add(_pngChunk('IEND', Uint8List(0)));
  return png.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final Uint8List typeBytes = _bytes(type);
  final Uint8List crcInput = Uint8List(typeBytes.length + data.length)
    ..setRange(0, typeBytes.length, typeBytes)
    ..setRange(typeBytes.length, typeBytes.length + data.length, data);
  final Uint8List result = Uint8List(12 + data.length);
  final ByteData view = ByteData.sublistView(result);
  view.setUint32(0, data.length, Endian.big);
  result.setRange(4, 8, typeBytes);
  result.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, _crc32(crcInput), Endian.big);
  return result;
}

int _paeth(int left, int above, int upperLeft) {
  final int prediction = left + above - upperLeft;
  final int leftDistance = (prediction - left).abs();
  final int aboveDistance = (prediction - above).abs();
  final int upperLeftDistance = (prediction - upperLeft).abs();
  if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final int byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _bytes(String value) => Uint8List.fromList(ascii.encode(value));

void _expectInts(List<int> actual, List<int> expected, String message) {
  _expect(actual.length == expected.length, '$message length');
  for (var index = 0; index < actual.length; index++) {
    _expect(actual[index] == expected[index], '$message at byte $index');
  }
}

void _expectThrows(void Function() operation, String message) {
  try {
    operation();
  } on Object {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
