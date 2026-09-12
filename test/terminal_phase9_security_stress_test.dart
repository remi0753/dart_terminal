import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_image_worker.dart';
import 'package:dart_terminal/src/runtime_image_worker_protocol.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_core/terminal_kitty_image_store.dart';
import 'package:dart_terminal/src/terminal_kitty_graphics_controller.dart';

Future<void> main() => runTerminalPhase9SecurityStressTests();

Future<void> runTerminalPhase9SecurityStressTests() async {
  _testOsc52AuthorityStateMachine();
  _testDesktopSignalAuthorityStateMachine();
  _testImageWorkerStateMachine();
  await _testKittyControllerQueueStress();
  _testKittyStoreRetainedResourceStress();
  _testProductKittyStoreByteBoundary();
  stdout.writeln(
    'phase9 security stress passed: seed=0x509a1171 '
    'osc52=1024 desktop=1024 worker=1024 store=2048',
  );
}

void _testOsc52AuthorityStateMachine() {
  final _StressRandom random = _StressRandom(0x509a1171);
  final _GuardedClipboard clipboard = _GuardedClipboard()
    ..externalWrite('initial');
  var nowMicros = 1000000;
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
    monotonicMicros: () => nowMicros,
    confirmationTimeout: const Duration(seconds: 1),
  );
  const List<
    ({
      TerminalConfiguredClipboardAccess read,
      TerminalConfiguredClipboardAccess write,
    })
  >
  policies =
      <
        ({
          TerminalConfiguredClipboardAccess read,
          TerminalConfiguredClipboardAccess write,
        })
      >[
        (
          read: TerminalConfiguredClipboardAccess.ask,
          write: TerminalConfiguredClipboardAccess.ask,
        ),
        (
          read: TerminalConfiguredClipboardAccess.allow,
          write: TerminalConfiguredClipboardAccess.allow,
        ),
        (
          read: TerminalConfiguredClipboardAccess.deny,
          write: TerminalConfiguredClipboardAccess.deny,
        ),
        (
          read: TerminalConfiguredClipboardAccess.ask,
          write: TerminalConfiguredClipboardAccess.allow,
        ),
        (
          read: TerminalConfiguredClipboardAccess.allow,
          write: TerminalConfiguredClipboardAccess.ask,
        ),
        (
          read: TerminalConfiguredClipboardAccess.deny,
          write: TerminalConfiguredClipboardAccess.ask,
        ),
        (
          read: TerminalConfiguredClipboardAccess.ask,
          write: TerminalConfiguredClipboardAccess.deny,
        ),
        (
          read: TerminalConfiguredClipboardAccess.allow,
          write: TerminalConfiguredClipboardAccess.deny,
        ),
      ];
  final List<TerminalSessionId> ids = <TerminalSessionId>[];
  final List<TerminalOsc52SessionProjection> projections =
      <TerminalOsc52SessionProjection>[];
  final List<VtParser> parsers = <VtParser>[];
  final List<int> resetGenerations = List<int>.filled(policies.length, 1);
  final List<Uint8List> replies = <Uint8List>[];

  for (var index = 0; index < policies.length; index++) {
    final TerminalSessionId id = _sessionId(100 + index);
    ids.add(id);
    final TerminalOsc52SessionProjection projection = coordinator
        .registerSession(
          sessionId: id,
          readPolicy: policies[index].read,
          writePolicy: policies[index].write,
          onReply: (Uint8List bytes) {
            replies.add(Uint8List.fromList(bytes));
            return true;
          },
        );
    projections.add(projection);
    parsers.add(
      VtParser(
        sink: TerminalScreenParserSink(
          TerminalScreen(rows: 2, columns: 4),
          onReply: (Uint8List bytes) {
            replies.add(Uint8List.fromList(bytes));
            return true;
          },
          onOsc52Request: projection.handle,
        ),
      ),
    );
  }

  TerminalSessionId? focused = ids.first;
  var active = true;
  coordinator.focusSession(focused);
  for (var operationIndex = 0; operationIndex < 1024; operationIndex++) {
    final TerminalOsc52PendingRequest? pending = coordinator.pendingRequest;
    if (pending != null) {
      switch (random.nextInt(6)) {
        case 0:
          final Set<_ClipboardCapability> grants =
              pending.request.operation == TerminalOsc52Operation.read
              ? <_ClipboardCapability>{_ClipboardCapability.read}
              : <_ClipboardCapability>{
                  _ClipboardCapability.generation,
                  _capabilityFor(pending.request.operation),
                };
          clipboard.withCapabilities(
            grants,
            () => coordinator.approve(pending.id),
          );
        case 1:
          coordinator.deny(pending.id);
        case 2:
          if (pending.request.operation != TerminalOsc52Operation.read) {
            clipboard.externalWrite('external-$operationIndex');
            clipboard.withCapabilities(const <_ClipboardCapability>{
              _ClipboardCapability.generation,
            }, () => coordinator.approve(pending.id));
          } else {
            coordinator.deny(pending.id);
          }
        case 3:
          focused = ids[(ids.indexOf(pending.sessionId) + 1) % ids.length];
          coordinator.focusSession(focused);
        case 4:
          final int index = ids.indexOf(pending.sessionId);
          resetGenerations[index]++;
          projections[index].synchronize(resetGenerations[index]);
        case 5:
          nowMicros += const Duration(seconds: 1).inMicroseconds;
          coordinator.expirePending(nowMicros: nowMicros);
      }
    }

    final int sessionIndex = random.nextInt(ids.length);
    if (operationIndex % 11 == 0) {
      focused = ids[sessionIndex];
      coordinator.focusSession(focused);
    } else if (operationIndex % 29 == 0) {
      focused = null;
      coordinator.focusSession(null);
    }
    if (operationIndex % 17 == 0) {
      active = !active;
      coordinator.setApplicationActive(active);
    }

    final TerminalOsc52Operation operation = TerminalOsc52Operation
        .values[random.nextInt(TerminalOsc52Operation.values.length)];
    final bool targetsClipboard = operationIndex % 19 != 0;
    final String selection = targetsClipboard ? 'c' : 'p';
    final String payload = switch (operation) {
      TerminalOsc52Operation.read => '?',
      TerminalOsc52Operation.clear => '!',
      TerminalOsc52Operation.write =>
        operationIndex % 31 == 0
            ? '/w=='
            : base64Encode(utf8.encode('value-$operationIndex-✓')),
    };
    final TerminalConfiguredClipboardAccess policy =
        operation == TerminalOsc52Operation.read
        ? policies[sessionIndex].read
        : policies[sessionIndex].write;
    final bool eligible =
        active && focused == ids[sessionIndex] && targetsClipboard;
    final Set<_ClipboardCapability> grants = <_ClipboardCapability>{};
    if (eligible && policy == TerminalConfiguredClipboardAccess.allow) {
      grants.add(_capabilityFor(operation));
    } else if (eligible &&
        policy == TerminalConfiguredClipboardAccess.ask &&
        coordinator.pendingRequest == null &&
        operation != TerminalOsc52Operation.read &&
        (operation != TerminalOsc52Operation.write ||
            operationIndex % 31 != 0)) {
      grants.add(_ClipboardCapability.generation);
    }
    clipboard.withCapabilities(
      grants,
      () => parsers[sessionIndex].parse(_oscBytes(52, '$selection;$payload')),
    );

    _expect(
      coordinator.pendingRequest == null ||
          coordinator.pendingRequest!.sessionId == focused,
      'OSC 52 retained a request outside the focused session at operation '
      '$operationIndex',
    );
    _expect(
      coordinator.metrics.pendingRequestCount <= operationIndex + 1 &&
          coordinator.metrics.trackedSessionCount == policies.length &&
          clipboard.unauthorizedCallCount == 0 &&
          replies.every(
            (Uint8List reply) =>
                reply.length <= TerminalOsc52Protocol.maximumReplyBytes,
          ),
      'OSC 52 authority or retained state escaped its cap at operation '
      '$operationIndex: pendingTotal=${coordinator.metrics.pendingRequestCount} '
      'tracked=${coordinator.metrics.trackedSessionCount} '
      'unauthorized=${clipboard.unauthorizedCallCount} '
      'lastUnauthorized=${clipboard.lastUnauthorizedCapability} '
      'maximumReply=${replies.fold<int>(0, (int value, Uint8List reply) => reply.length > value ? reply.length : value)}',
    );
  }

  coordinator.setApplicationActive(false);
  for (final TerminalOsc52SessionProjection projection in projections) {
    projection.close();
  }
  coordinator.dispose();
  _expect(
    coordinator.pendingRequest == null &&
        coordinator.metrics.trackedSessionCount == 0 &&
        clipboard.unauthorizedCallCount == 0,
    'OSC 52 teardown retained authority or session state',
  );
  _testOsc52TrackedSessionCap();
}

void _testOsc52TrackedSessionCap() {
  final _GuardedClipboard clipboard = _GuardedClipboard();
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
  );
  final List<TerminalOsc52SessionProjection> projections =
      <TerminalOsc52SessionProjection>[];
  for (
    var index = 0;
    index < TerminalOsc52Coordinator.maximumTrackedSessions;
    index++
  ) {
    projections.add(
      coordinator.registerSession(
        sessionId: _sessionId(1000 + index),
        readPolicy: TerminalConfiguredClipboardAccess.deny,
        writePolicy: TerminalConfiguredClipboardAccess.deny,
        onReply: (_) => true,
      ),
    );
  }
  _expectThrows<StateError>(
    () => coordinator.registerSession(
      sessionId: _sessionId(2000),
      readPolicy: TerminalConfiguredClipboardAccess.deny,
      writePolicy: TerminalConfiguredClipboardAccess.deny,
      onReply: (_) => true,
    ),
    'OSC 52 sixty-fifth tracked session',
  );
  for (final TerminalOsc52SessionProjection projection in projections) {
    projection.close();
  }
  coordinator.dispose();
  _expect(
    coordinator.metrics.trackedSessionCount == 0,
    'OSC 52 cap harness did not release every session',
  );
}

void _testDesktopSignalAuthorityStateMachine() {
  final _StressRandom random = _StressRandom(0xd35c7001);
  final _GuardedDesktopPort port = _GuardedDesktopPort();
  var nowMicros = 0;
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(
        nativePort: port,
        monotonicMicros: () => nowMicros,
        notificationBudget: 8,
        notificationWindow: const Duration(seconds: 1),
        maximumLiveNotificationsPerSession: 4,
      );
  final List<TerminalSessionId> ids = <TerminalSessionId>[];
  final List<TerminalScreenSet> screens = <TerminalScreenSet>[];
  final List<VtParser> parsers = <VtParser>[];
  final List<TerminalDesktopSignalSessionProjection> projections =
      <TerminalDesktopSignalSessionProjection>[];
  for (var index = 0; index < 8; index++) {
    final TerminalSessionId id = _sessionId(300 + index);
    final TerminalScreenSet screenSet = TerminalScreenSet(rows: 3, columns: 8);
    ids.add(id);
    screens.add(screenSet);
    parsers.add(
      VtParser(sink: TerminalScreenParserSink.forScreenSet(screenSet)),
    );
    projections.add(coordinator.registerSession(id));
  }
  TerminalSessionId? focused;
  for (var operationIndex = 0; operationIndex < 1024; operationIndex++) {
    final int sessionIndex = random.nextInt(ids.length);
    if (operationIndex % 9 == 0) {
      focused = operationIndex % 27 == 0 ? null : ids[sessionIndex];
      port.withAuthority(() => coordinator.focusSession(focused));
    }
    if (operationIndex % 13 == 0) {
      coordinator.setApplicationActive(operationIndex.isEven);
    }
    if (operationIndex % 37 == 0) {
      nowMicros += const Duration(seconds: 1).inMicroseconds;
    }

    final String sequence = switch (random.nextInt(7)) {
      0 => _osc(9, 'legacy-$operationIndex'),
      1 => _osc(
        99,
        'i=evil-$sessionIndex-${operationIndex % 9};title-$operationIndex',
      ),
      2 => _osc(99, 'i=evil-pending-${operationIndex % 8}:d=0;partial'),
      3 => _osc(99, 'i=evil-pending-${operationIndex % 8}:p=body;complete'),
      4 => _osc(9, '4;${operationIndex % 5};${operationIndex % 101}'),
      5 => _osc(
        133,
        const <String>['A', 'B', 'C', 'D', 'N'][operationIndex % 5],
      ),
      6 => operationIndex % 2 == 0 ? '\x1bc' : _osc(99, 'bad metadata'),
      _ => throw StateError('unreachable desktop operation'),
    };
    final int nativeCallsBeforeParse = port.totalCallCount;
    parsers[sessionIndex].parse(Uint8List.fromList(utf8.encode(sequence)));
    if (operationIndex % 41 == 0) {
      final String flood = List<String>.generate(
        12,
        (int index) => _osc(9, 'flood-$operationIndex-$index'),
      ).join();
      parsers[sessionIndex].parse(Uint8List.fromList(utf8.encode(flood)));
    }
    _expect(
      port.totalCallCount == nativeCallsBeforeParse &&
          screens[sessionIndex].desktopNotifications.queuedRequestCount <=
              TerminalDesktopNotificationModel.maximumQueuedRequests &&
          screens[sessionIndex].desktopNotifications.pendingRequestCount <=
              TerminalDesktopNotificationModel.maximumPendingRequests,
      'terminal parsing acquired desktop authority or exceeded a parser queue '
      'at operation $operationIndex',
    );

    port.withAuthority(
      () => projections[sessionIndex].synchronize(screens[sessionIndex]),
    );
    for (var index = 0; index < ids.length; index++) {
      final TerminalDesktopSignalSessionSnapshot? snapshot = coordinator
          .snapshotFor(ids[index]);
      _expect(
        snapshot == null || snapshot.liveNotificationCount <= 4,
        'desktop live notification cap escaped for session $index at '
        'operation $operationIndex',
      );
    }
    _expect(
      coordinator.metrics.trackedSessionCount == ids.length &&
          port.liveIdentifiers.length <= ids.length * 4 &&
          port.unauthorizedCallCount == 0,
      'desktop coordinator retained unbounded or unauthorized state at '
      'operation $operationIndex',
    );
  }

  port.withAuthority(() {
    for (final TerminalDesktopSignalSessionProjection projection
        in projections) {
      projection.close();
    }
    coordinator.dispose();
  });
  _expect(
    port.liveIdentifiers.isEmpty &&
        port.badgeLabel == null &&
        coordinator.metrics.trackedSessionCount == 0 &&
        port.unauthorizedCallCount == 0,
    'desktop coordinator teardown retained native identities or authority',
  );
  _testDesktopTrackedSessionCap();
}

void _testDesktopTrackedSessionCap() {
  final _GuardedDesktopPort port = _GuardedDesktopPort();
  final TerminalDesktopSignalCoordinator coordinator =
      TerminalDesktopSignalCoordinator(nativePort: port);
  final List<TerminalDesktopSignalSessionProjection> projections =
      <TerminalDesktopSignalSessionProjection>[];
  for (
    var index = 0;
    index < TerminalDesktopSignalCoordinator.maximumTrackedSessions;
    index++
  ) {
    projections.add(coordinator.registerSession(_sessionId(3000 + index)));
  }
  _expectThrows<StateError>(
    () => coordinator.registerSession(_sessionId(4000)),
    'desktop sixty-fifth tracked session',
  );
  port.withAuthority(() {
    for (final TerminalDesktopSignalSessionProjection projection
        in projections) {
      projection.close();
    }
    coordinator.dispose();
  });
  _expect(
    coordinator.metrics.trackedSessionCount == 0 &&
        port.unauthorizedCallCount == 0,
    'desktop cap harness did not release every session',
  );
}

void _testImageWorkerStateMachine() {
  final _StressRandom random = _StressRandom(0x1a6e600d);
  final RuntimeImageWorkerService worker = RuntimeImageWorkerService(
    maximumEncodedBytes: 32,
    maximumPendingTransfers: 4,
    maximumPendingEncodedBytes: 32,
  );
  for (var operationIndex = 0; operationIndex < 1024; operationIndex++) {
    final int paneId = random.nextInt(8) + 1;
    final int transferGeneration = random.nextInt(16) + 1;
    final RuntimeImageWorkerRequest request = switch (random.nextInt(5)) {
      0 => RuntimeImageWorkerRequest.chunk(
        paneId: paneId,
        sessionGeneration: 1,
        transferGeneration: transferGeneration,
        start: true,
        finalChunk: false,
        format: 32,
        width: 1,
        height: 1,
        data: _asciiBytes('AQID'),
      ),
      1 => RuntimeImageWorkerRequest.chunk(
        paneId: paneId,
        sessionGeneration: 1,
        transferGeneration: transferGeneration,
        start: false,
        finalChunk: true,
        data: _asciiBytes('BA=='),
      ),
      2 => RuntimeImageWorkerRequest.abort(
        paneId: paneId,
        sessionGeneration: 1,
        transferGeneration: transferGeneration,
      ),
      3 => RuntimeImageWorkerRequest.chunk(
        paneId: paneId,
        sessionGeneration: 1,
        transferGeneration: transferGeneration,
        start: true,
        finalChunk: true,
        format: 32,
        width: 1,
        height: 1,
        data: _asciiBytes('AQIDBA=='),
      ),
      4 => RuntimeImageWorkerRequest.chunk(
        paneId: paneId,
        sessionGeneration: 1,
        transferGeneration: transferGeneration,
        start: true,
        finalChunk: false,
        format: 32,
        width: 1,
        height: 1,
        data: _asciiBytes('%%%='),
      ),
      _ => throw StateError('unreachable worker operation'),
    };
    final RuntimeImageWorkerResponse response =
        RuntimeImageWorkerResponseCodec.decode(
          worker.handle(RuntimeImageWorkerRequestCodec.encode(request)),
        );
    _expect(
      response.status != RuntimeImageWorkerStatus.invalidRequest &&
          worker.pendingTransferCount <= 4 &&
          worker.pendingEncodedBytes <= 32,
      'image worker accounting escaped its injected cap at operation '
      '$operationIndex',
    );
  }
  worker.dispose();
  _expect(
    worker.pendingTransferCount == 0 && worker.pendingEncodedBytes == 0,
    'image worker dispose retained multipart bytes',
  );
}

Future<void> _testKittyControllerQueueStress() async {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 2);
  final _GatedImageWorker worker = _GatedImageWorker();
  final Completer<void> gate = Completer<void>();
  worker.gate = gate;
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalKittyGraphicsController controller =
      TerminalKittyGraphicsController(
        screenSet: screens,
        paneId: 700,
        sessionGeneration: 1,
        worker: worker,
        maximumQueuedJobs: 8,
        maximumQueuedBytes: 64,
        onReply: (Uint8List bytes) {
          replies.add(Uint8List.fromList(bytes));
          return true;
        },
      );
  _expect(
    controller.enqueueCommand(_graphicsCommand('Gi=1,f=32,s=1,v=1;AQIDBA==')),
    'controller did not admit its first bounded graphics job',
  );
  await Future<void>.delayed(Duration.zero);
  var rejectedReplies = 0;
  for (var index = 0; index < 32; index++) {
    if (!controller.enqueueOrdinaryReply(_asciiBytes('r$index'))) {
      rejectedReplies++;
    }
    _expect(
      controller.pendingJobCount <= 8 && controller.pendingByteCount <= 64,
      'controller FIFO escaped its injected cap at reply $index',
    );
  }
  final bool rejectedCommand = !controller.enqueueCommand(
    _graphicsCommand('Gi=2,f=32,s=1,v=1;AQIDBA=='),
  );
  _expect(
    rejectedReplies > 0 &&
        rejectedCommand &&
        controller.rejectedCommandCount == 1,
    'controller pressure did not reject excess reply and command work',
  );
  gate.complete();
  await controller.waitForIdle().timeout(const Duration(seconds: 2));
  worker.gate = null;
  _expect(
    controller.pendingJobCount == 0 &&
        controller.pendingByteCount == 0 &&
        !controller.hasPendingTransfer &&
        worker.service.pendingTransferCount == 0 &&
        screens.primaryKittyImages.imageById(1) != null &&
        replies.isNotEmpty,
    'controller pressure did not make forward progress or release its FIFO',
  );
  await controller.dispose();
  worker.dispose();
  _expect(
    screens.primaryKittyImages.isEmpty &&
        screens.alternateKittyImages.isEmpty &&
        worker.service.pendingTransferCount == 0,
    'controller dispose retained images or worker transfers',
  );
}

void _testKittyStoreRetainedResourceStress() {
  final _StressRandom random = _StressRandom(0x5702e123);
  final TerminalKittyImageStore store = TerminalKittyImageStore(
    maximumImages: 4,
    maximumPlacements: 8,
    maximumAnimationFrames: 8,
    maximumRetainedBytes: 128,
  );
  for (var operationIndex = 0; operationIndex < 2048; operationIndex++) {
    final int imageId = random.nextInt(12) + 1;
    switch (random.nextInt(5)) {
      case 0:
      case 1:
        store.store(
          imageId: imageId,
          imageNumber: 0,
          width: 2,
          height: 2,
          transient: operationIndex.isEven,
          rgba: Uint8List.fromList(
            List<int>.generate(
              16,
              (int index) => (operationIndex + index) & 0xff,
            ),
          ),
        );
      case 2:
        final TerminalKittyImage? image = store.imageById(imageId);
        if (image != null) {
          store.storeAnimationFrame(
            imageId: imageId,
            imageNumber: 0,
            expectedResourceGeneration: image.resourceGeneration,
            width: 2,
            height: 2,
            x: 0,
            y: 0,
            baseFrame: 1,
            editFrame: 0,
            gapMilliseconds: 40,
            overwrite: true,
            backgroundRgba: 0,
            transient: operationIndex.isOdd,
            rgba: Uint8List(16),
          );
        }
      case 3:
        if (store.imageById(imageId) != null) {
          store.place(
            imageId: imageId,
            imageNumber: 0,
            placementId: random.nextInt(12) + 1,
            logicalLineId: random.nextInt(16) + 1,
            logicalLineEpoch: 1,
            logicalCellOffset: random.nextInt(4),
            sourceX: 0,
            sourceY: 0,
            sourceWidth: 2,
            sourceHeight: 2,
            cellOffsetX: 0,
            cellOffsetY: 0,
            columns: 1,
            rows: 1,
            z: random.nextInt(7) - 3,
          );
        }
      case 4:
        if (operationIndex % 127 == 0) store.clear();
    }
    final int exactBytes = store.snapshot().fold<int>(
      0,
      (int total, TerminalKittyImage image) => total + image.storageByteLength,
    );
    _expect(
      store.length <= 4 &&
          store.placementCount <= 8 &&
          store.animationFrameCount <= 8 &&
          store.retainedBytes <= 128 &&
          store.retainedBytes == exactBytes,
      'Kitty store accounting escaped its injected cap at operation '
      '$operationIndex',
    );
  }
  store.clear();
  _expect(
    store.isEmpty &&
        store.retainedBytes == 0 &&
        store.placementCount == 0 &&
        store.animationFrameCount == 0,
    'Kitty store clear retained image, placement, frame, or byte ownership',
  );
}

void _testProductKittyStoreByteBoundary() {
  final TerminalKittyImageStore store = TerminalKittyImageStore();
  final Uint8List oneMiBRgba = Uint8List(1024 * 1024);
  for (var imageId = 1; imageId <= 16; imageId++) {
    final TerminalKittyImageStoreResult result = store.store(
      imageId: imageId,
      imageNumber: 0,
      width: 512,
      height: 512,
      transient: false,
      rgba: oneMiBRgba,
    );
    _expect(
      result.disposition == TerminalKittyImageStoreDisposition.stored &&
          store.retainedBytes == imageId * 1024 * 1024,
      'product Kitty byte boundary rejected image $imageId',
    );
  }
  store.store(
    imageId: 17,
    imageNumber: 0,
    width: 512,
    height: 512,
    transient: false,
    rgba: oneMiBRgba,
  );
  _expect(
    store.length == 16 &&
        store.retainedBytes ==
            TerminalKittyImageStoreLimits.maximumRetainedBytes &&
        store.imageById(1) == null &&
        store.imageById(17) != null &&
        store.evictionCount == 1,
    'product Kitty byte boundary did not deterministically evict the oldest '
    'one-MiB image',
  );
  store.clear();
  _expect(
    store.isEmpty && store.retainedBytes == 0,
    'product Kitty byte-boundary teardown retained RGBA ownership',
  );
}

enum _ClipboardCapability { generation, read, write, clear }

_ClipboardCapability _capabilityFor(TerminalOsc52Operation operation) =>
    switch (operation) {
      TerminalOsc52Operation.read => _ClipboardCapability.read,
      TerminalOsc52Operation.write => _ClipboardCapability.write,
      TerminalOsc52Operation.clear => _ClipboardCapability.clear,
    };

final class _GuardedClipboard implements TerminalOsc52ClipboardPort {
  final Set<_ClipboardCapability> _capabilities = <_ClipboardCapability>{};
  String? _text;
  int _changeCount = 0;
  int unauthorizedCallCount = 0;
  _ClipboardCapability? lastUnauthorizedCapability;

  T withCapabilities<T>(
    Set<_ClipboardCapability> capabilities,
    T Function() body,
  ) {
    if (_capabilities.isNotEmpty) {
      throw StateError('clipboard capability scopes cannot be nested');
    }
    _capabilities.addAll(capabilities);
    try {
      return body();
    } finally {
      _capabilities.clear();
    }
  }

  void externalWrite(String text) {
    _text = text;
    _changeCount++;
  }

  void _require(_ClipboardCapability capability) {
    if (!_capabilities.remove(capability)) {
      unauthorizedCallCount++;
      lastUnauthorizedCapability = capability;
      throw StateError('unauthorized clipboard $capability');
    }
  }

  @override
  int get changeCount {
    _require(_ClipboardCapability.generation);
    return _changeCount;
  }

  @override
  TerminalOsc52ClipboardText readText() {
    _require(_ClipboardCapability.read);
    return TerminalOsc52ClipboardText(text: _text, changeCount: _changeCount);
  }

  @override
  int writeText(String text) {
    _require(_ClipboardCapability.write);
    _text = text;
    return ++_changeCount;
  }

  @override
  int clear() {
    _require(_ClipboardCapability.clear);
    _text = null;
    return ++_changeCount;
  }
}

final class _GuardedDesktopPort implements TerminalDesktopSignalNativePort {
  final Set<String> liveIdentifiers = <String>{};
  var unauthorizedCallCount = 0;
  var totalCallCount = 0;
  var _hasAuthority = false;
  String? badgeLabel;

  T withAuthority<T>(T Function() body) {
    if (_hasAuthority) throw StateError('desktop authority scopes cannot nest');
    _hasAuthority = true;
    try {
      return body();
    } finally {
      _hasAuthority = false;
    }
  }

  void _requireAuthority() {
    totalCallCount++;
    if (!_hasAuthority) {
      unauthorizedCallCount++;
      throw StateError('terminal parser acquired native desktop authority');
    }
  }

  @override
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  }) {
    _requireAuthority();
    _expect(
      RegExp(r'^dt\.p[0-9a-f]+\.s[0-9a-f]+\.n[0-9a-f]+$')
              .hasMatch(identifier) &&
          !identifier.contains('evil'),
      'terminal-controlled identifier crossed the native desktop boundary',
    );
    liveIdentifiers.add(identifier);
    return true;
  }

  @override
  bool removeNotification(String identifier) {
    _requireAuthority();
    liveIdentifiers.remove(identifier);
    return true;
  }

  @override
  bool setDockBadgeLabel(String? label) {
    _requireAuthority();
    badgeLabel = label;
    return true;
  }
}

final class _GatedImageWorker implements RuntimeWorkerPayloadClient {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  Completer<void>? gate;

  @override
  Future<RuntimeLifecyclePayloadRequestResult> requestPayload(
    Uint8List payload, {
    bool expectsInt64Response = false,
  }) async {
    await gate?.future;
    return RuntimeLifecyclePayloadRequestResult(
      RuntimeLifecycleRequestStatus.response,
      payload: service.handle(payload),
    );
  }

  void dispose() => service.dispose();
}

final class _StressRandom {
  _StressRandom(this._state);

  int _state;

  int nextInt(int maximum) {
    var value = _state & 0xffffffff;
    value ^= (value << 13) & 0xffffffff;
    value ^= value >> 17;
    value ^= (value << 5) & 0xffffffff;
    _state = value & 0xffffffff;
    return _state % maximum;
  }
}

TerminalKittyGraphicsCommand _graphicsCommand(String payload) =>
    TerminalKittyGraphicsCommandParser.parse(_asciiBytes(payload));

TerminalSessionId _sessionId(int paneId) =>
    TerminalSessionId(paneId: PaneId(paneId), generation: 1);

String _osc(int command, String payload) => '\x1b]$command;$payload\x07';

Uint8List _oscBytes(int command, String payload) =>
    Uint8List.fromList(utf8.encode(_osc(command, payload)));

Uint8List _asciiBytes(String value) => Uint8List.fromList(ascii.encode(value));

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _expectThrows<T extends Object>(
  void Function() action,
  String description,
) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}
