import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'runtime_image_worker_protocol.dart';
import 'runtime_lifecycle.dart';
import 'terminal_core/terminal_kitty_graphics.dart';
import 'terminal_core/terminal_kitty_image_store.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_core/terminal_screen_set.dart';

abstract final class TerminalKittyGraphicsControllerLimits {
  static const int maximumQueuedJobs = 64;
  static const int maximumQueuedBytes = 256 * 1024;
}

/// Session-owned FIFO joining asynchronous Kitty decode with ordinary replies.
final class TerminalKittyGraphicsController {
  TerminalKittyGraphicsController({
    required this.screenSet,
    required this.paneId,
    required this.sessionGeneration,
    required TerminalReplyHandler onReply,
    RuntimeWorkerPayloadClient? worker,
    this.maximumQueuedJobs =
        TerminalKittyGraphicsControllerLimits.maximumQueuedJobs,
    this.maximumQueuedBytes =
        TerminalKittyGraphicsControllerLimits.maximumQueuedBytes,
  }) : _onReply = onReply,
       _worker = worker {
    if (paneId <= 0 ||
        paneId > 0xffffffff ||
        sessionGeneration <= 0 ||
        sessionGeneration > 0xffffffff) {
      throw ArgumentError('Kitty controller identity must fit unsigned 32-bit');
    }
    if (maximumQueuedJobs <= 0 ||
        maximumQueuedJobs >
            TerminalKittyGraphicsControllerLimits.maximumQueuedJobs ||
        maximumQueuedBytes <= 0 ||
        maximumQueuedBytes >
            TerminalKittyGraphicsControllerLimits.maximumQueuedBytes) {
      throw ArgumentError(
        'Kitty controller queue bounds exceed product limits',
      );
    }
  }

  final TerminalScreenSet screenSet;
  final int paneId;
  final int sessionGeneration;
  final TerminalReplyHandler _onReply;
  final int maximumQueuedJobs;
  final int maximumQueuedBytes;
  final Queue<_TerminalKittyQueueJob> _queue = Queue<_TerminalKittyQueueJob>();
  final List<Completer<void>> _idleWaiters = <Completer<void>>[];

  RuntimeWorkerPayloadClient? _worker;
  _TerminalKittyPendingTransfer? _pendingTransfer;
  var _workerEpoch = 1;
  var _nextTransferGeneration = 1;
  var _pendingJobs = 0;
  var _pendingBytes = 0;
  var _draining = false;
  var _queueDesynchronized = false;
  var _disposed = false;
  var _acceptedCommandCount = 0;
  var _rejectedCommandCount = 0;
  var _emittedGraphicsReplyCount = 0;
  var _rejectedGraphicsReplyCount = 0;
  var _deferredReplyWriteFailureCount = 0;
  var _workerFailureCount = 0;
  var _staleCompletionCount = 0;

  int get pendingJobCount => _pendingJobs;
  int get pendingByteCount => _pendingBytes;
  bool get hasPendingTransfer => _pendingTransfer != null;
  bool get isDisposed => _disposed;
  int get acceptedCommandCount => _acceptedCommandCount;
  int get rejectedCommandCount => _rejectedCommandCount;
  int get emittedGraphicsReplyCount => _emittedGraphicsReplyCount;
  int get rejectedGraphicsReplyCount => _rejectedGraphicsReplyCount;
  int get deferredReplyWriteFailureCount => _deferredReplyWriteFailureCount;
  int get workerFailureCount => _workerFailureCount;
  int get staleCompletionCount => _staleCompletionCount;

  bool attachWorker(RuntimeWorkerPayloadClient worker) {
    if (_disposed) return false;
    if (identical(_worker, worker)) return false;
    final RuntimeWorkerPayloadClient? oldWorker = _worker;
    final _TerminalKittyPendingTransfer? oldTransfer = _pendingTransfer;
    _workerEpoch++;
    _worker = worker;
    _pendingTransfer = null;
    if (oldWorker != null && oldTransfer != null) {
      unawaited(_sendAbort(oldWorker, oldTransfer));
    }
    return true;
  }

  bool enqueueCommand(TerminalKittyGraphicsCommand command) {
    if (!_admit(command.dataLength)) {
      _rejectedCommandCount++;
      _queueDesynchronized = true;
      return false;
    }
    _acceptedCommandCount++;
    _queue.addLast(_TerminalKittyQueueJob.command(command));
    _startDrain();
    return true;
  }

  /// Sends ordinary replies immediately while idle, or queues them behind an
  /// earlier graphics command so an asynchronous query cannot be overtaken.
  bool enqueueOrdinaryReply(Uint8List reply) {
    if (_disposed) return false;
    final Uint8List owned = Uint8List.fromList(reply);
    if (_pendingJobs == 0) return _callReply(owned);
    if (!_admit(owned.length)) return false;
    _queue.addLast(_TerminalKittyQueueJob.reply(owned));
    _startDrain();
    return true;
  }

  Future<void> waitForIdle() {
    if (_pendingJobs == 0) return Future<void>.value();
    final Completer<void> waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _workerEpoch++;
    final RuntimeWorkerPayloadClient? worker = _worker;
    final _TerminalKittyPendingTransfer? transfer = _pendingTransfer;
    _worker = null;
    _pendingTransfer = null;
    while (_queue.isNotEmpty) {
      final _TerminalKittyQueueJob removed = _queue.removeFirst();
      _pendingJobs--;
      _pendingBytes -= removed.byteCost;
    }
    _queueDesynchronized = false;
    screenSet.primaryKittyImages.clear();
    screenSet.alternateKittyImages.clear();
    _completeIdleWaitersIfNeeded();
    if (worker != null && transfer != null) {
      await _sendAbort(worker, transfer);
    }
  }

  bool _admit(int byteCost) {
    if (_disposed ||
        byteCost < 0 ||
        _pendingJobs >= maximumQueuedJobs ||
        _pendingBytes + byteCost > maximumQueuedBytes) {
      return false;
    }
    _pendingJobs++;
    _pendingBytes += byteCost;
    return true;
  }

  void _startDrain() {
    if (_draining) return;
    _draining = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        if (_queueDesynchronized && !_disposed) {
          _queueDesynchronized = false;
          await _abortPendingTransfer();
        }
        final _TerminalKittyQueueJob job = _queue.removeFirst();
        try {
          if (!_disposed) {
            final TerminalKittyGraphicsCommand? command = job.command;
            if (command != null) {
              await _executeCommand(command);
            } else if (!_callReply(job.copyReply()!)) {
              _deferredReplyWriteFailureCount++;
            }
          }
        } on Object {
          if (job.command != null && !_disposed) {
            _workerFailureCount++;
            _emitError(job.command!, 'EIO', 'graphics command failed');
          } else {
            _deferredReplyWriteFailureCount++;
          }
        } finally {
          _pendingJobs--;
          _pendingBytes -= job.byteCost;
          if (_pendingJobs < 0 || _pendingBytes < 0) {
            throw StateError('Kitty controller queue accounting underflow');
          }
          _completeIdleWaitersIfNeeded();
        }
        if (_queueDesynchronized && !_disposed) {
          _queueDesynchronized = false;
          await _abortPendingTransfer();
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty && !_disposed) _startDrain();
    }
  }

  Future<void> _executeCommand(TerminalKittyGraphicsCommand command) async {
    if (command.hasImageIdKey && command.hasImageNumberKey) {
      await _abortPendingTransfer();
      _emitError(
        command,
        'EINVAL',
        'image id and number are mutually exclusive',
      );
      return;
    }
    if ((command.hasImageIdKey && command.transmission.imageId == 0) ||
        (command.hasImageNumberKey && command.transmission.imageNumber == 0)) {
      await _abortPendingTransfer();
      _emitError(command, 'EINVAL', 'image identifiers must be positive');
      return;
    }
    switch (command.action) {
      case TerminalKittyGraphicsAction.controlAnimation:
      case TerminalKittyGraphicsAction.composeAnimation:
      case TerminalKittyGraphicsAction.transmitAnimationFrame:
        await _abortPendingTransfer();
        _emitError(command, 'ENOTSUP', 'image animation is not supported');
        return;
      case TerminalKittyGraphicsAction.place:
      case TerminalKittyGraphicsAction.transmitAndPlace:
        await _abortPendingTransfer();
        _emitError(command, 'ENOTSUP', 'image placement is not yet supported');
        return;
      case TerminalKittyGraphicsAction.delete:
        await _abortPendingTransfer();
        _emitError(command, 'ENOTSUP', 'image deletion is not yet supported');
        return;
      case TerminalKittyGraphicsAction.query:
      case TerminalKittyGraphicsAction.transmit:
        break;
    }
    if (command.transmission.medium != TerminalKittyGraphicsMedium.direct) {
      await _abortPendingTransfer();
      _emitError(command, 'ENOTSUP', 'local image transport is not supported');
      return;
    }
    if (command.transmission.dataOffset != 0) {
      await _abortPendingTransfer();
      _emitError(
        command,
        'EINVAL',
        'direct transport cannot use a data offset',
      );
      return;
    }
    if (command.transmission.usage & ~1 != 0) {
      await _abortPendingTransfer();
      _emitError(command, 'EINVAL', 'image usage contains unsupported bits');
      return;
    }

    final _TerminalKittyPendingTransfer? pending = _pendingTransfer;
    if (pending != null) {
      if (!command.isMultipartContinuationCompatible) {
        await _abortPendingTransfer();
        _emitError(
          command,
          'EINVAL',
          'multipart continuation contains forbidden controls',
          identitySource: pending.command,
        );
        return;
      }
      await _sendChunk(command, pending, start: false);
      return;
    }

    if (command.isMultipartContinuationCompatible && command.hasMoreChunksKey) {
      _emitError(command, 'ENOENT', 'no multipart image transfer is pending');
      return;
    }
    if (command.transmission.imageId == 0 &&
        command.transmission.imageNumber == 0) {
      _emitError(command, 'EINVAL', 'image id or number is required');
      return;
    }
    final int transferGeneration = _takeTransferGeneration();
    final _TerminalKittyPendingTransfer transfer =
        _TerminalKittyPendingTransfer(
          command: command,
          screenKind: screenSet.activeKind,
          transferGeneration: transferGeneration,
        );
    _pendingTransfer = transfer;
    await _sendChunk(command, transfer, start: true);
  }

  Future<void> _sendChunk(
    TerminalKittyGraphicsCommand command,
    _TerminalKittyPendingTransfer transfer, {
    required bool start,
  }) async {
    final RuntimeWorkerPayloadClient? worker = _worker;
    final int epoch = _workerEpoch;
    if (worker == null) {
      _pendingTransfer = null;
      _workerFailureCount++;
      _emitError(
        command,
        'EIO',
        'image worker is unavailable',
        identitySource: transfer.command,
      );
      return;
    }
    final RuntimeImageWorkerRequest request = RuntimeImageWorkerRequest.chunk(
      paneId: paneId,
      sessionGeneration: sessionGeneration,
      transferGeneration: transfer.transferGeneration,
      start: start,
      finalChunk: !command.transmission.moreChunks,
      compressed:
          start &&
          command.transmission.compression ==
              TerminalKittyGraphicsCompression.zlib,
      format: start ? command.transmission.format : 0,
      width: start ? command.transmission.width : 0,
      height: start ? command.transmission.height : 0,
      declaredDataSize: start ? command.transmission.dataSize : 0,
      data: command.copyData(),
    );
    late final RuntimeLifecyclePayloadRequestResult result;
    try {
      result = await worker.requestPayload(
        RuntimeImageWorkerRequestCodec.encode(request),
      );
    } on Object {
      if (_isStale(epoch, transfer)) return;
      _pendingTransfer = null;
      _workerFailureCount++;
      _emitError(
        command,
        'EIO',
        'image worker request failed',
        identitySource: transfer.command,
      );
      return;
    }
    if (_isStale(epoch, transfer)) return;
    if (result.status != RuntimeLifecycleRequestStatus.response) {
      _pendingTransfer = null;
      _workerFailureCount++;
      final String code =
          result.status == RuntimeLifecycleRequestStatus.backpressured
          ? 'EBUSY'
          : 'EIO';
      _emitError(
        command,
        code,
        'image worker did not accept the request',
        identitySource: transfer.command,
      );
      return;
    }
    final Uint8List? payload = result.copyPayload();
    late final RuntimeImageWorkerResponse response;
    try {
      response = RuntimeImageWorkerResponseCodec.decode(payload!);
    } on Object {
      _pendingTransfer = null;
      _workerFailureCount++;
      _emitError(
        command,
        'EIO',
        'image worker returned an invalid response',
        identitySource: transfer.command,
      );
      return;
    }
    if (response.paneId != paneId ||
        response.sessionGeneration != sessionGeneration ||
        response.transferGeneration != transfer.transferGeneration) {
      _pendingTransfer = null;
      _workerFailureCount++;
      _emitError(
        command,
        'EIO',
        'image worker response identity mismatch',
        identitySource: transfer.command,
      );
      return;
    }
    if (response.status == RuntimeImageWorkerStatus.pending) {
      if (!command.transmission.moreChunks) {
        _pendingTransfer = null;
        _workerFailureCount++;
        _emitError(
          command,
          'EIO',
          'image worker omitted the final result',
          identitySource: transfer.command,
        );
      }
      return;
    }
    _pendingTransfer = null;
    if (response.status != RuntimeImageWorkerStatus.decoded) {
      final ({String code, String description}) error = _workerError(
        response.status,
      );
      _emitError(
        command,
        error.code,
        error.description,
        identitySource: transfer.command,
      );
      return;
    }
    if (command.transmission.moreChunks) {
      _workerFailureCount++;
      _emitError(
        command,
        'EIO',
        'image worker completed before the final chunk',
        identitySource: transfer.command,
      );
      return;
    }
    _completeDecoded(command, transfer, response);
  }

  void _completeDecoded(
    TerminalKittyGraphicsCommand finalCommand,
    _TerminalKittyPendingTransfer transfer,
    RuntimeImageWorkerResponse response,
  ) {
    final TerminalKittyGraphicsCommand initial = transfer.command;
    if (initial.action == TerminalKittyGraphicsAction.query) {
      _emitSuccess(finalCommand, identitySource: initial);
      return;
    }
    final TerminalKittyImageStore store = screenSet.kittyImagesFor(
      transfer.screenKind,
    );
    final TerminalKittyImageStoreResult stored = store.store(
      imageId: initial.transmission.imageId,
      imageNumber: initial.transmission.imageNumber,
      width: response.width,
      height: response.height,
      transient: initial.transmission.usage & 1 != 0,
      rgba: response.copyRgba(),
    );
    if (stored.disposition ==
        TerminalKittyImageStoreDisposition.resourceLimit) {
      _emitError(
        finalCommand,
        'ENOSPC',
        'image storage limit reached',
        identitySource: initial,
      );
      return;
    }
    final TerminalKittyImage image = stored.image!;
    _emitSuccess(
      finalCommand,
      identitySource: initial,
      resolvedImageId: image.id,
    );
  }

  Future<void> _abortPendingTransfer() async {
    final _TerminalKittyPendingTransfer? transfer = _pendingTransfer;
    final RuntimeWorkerPayloadClient? worker = _worker;
    _pendingTransfer = null;
    if (transfer != null && worker != null) {
      await _sendAbort(worker, transfer);
    }
  }

  Future<void> _sendAbort(
    RuntimeWorkerPayloadClient worker,
    _TerminalKittyPendingTransfer transfer,
  ) async {
    try {
      await worker.requestPayload(
        RuntimeImageWorkerRequestCodec.encode(
          RuntimeImageWorkerRequest.abort(
            paneId: paneId,
            sessionGeneration: sessionGeneration,
            transferGeneration: transfer.transferGeneration,
          ),
        ),
      );
    } on Object {
      _workerFailureCount++;
    }
  }

  bool _isStale(int epoch, _TerminalKittyPendingTransfer transfer) {
    if (_disposed ||
        epoch != _workerEpoch ||
        !identical(_pendingTransfer, transfer)) {
      _staleCompletionCount++;
      return true;
    }
    return false;
  }

  int _takeTransferGeneration() {
    if (_nextTransferGeneration > 0xffffffff) {
      throw StateError('Kitty transfer generation space is exhausted');
    }
    return _nextTransferGeneration++;
  }

  void _emitSuccess(
    TerminalKittyGraphicsCommand command, {
    required TerminalKittyGraphicsCommand identitySource,
    int? resolvedImageId,
  }) {
    final Uint8List? reply = TerminalKittyGraphicsResponseEncoder.success(
      quiet: command.quiet,
      imageId: resolvedImageId ?? identitySource.transmission.imageId,
      imageNumber: identitySource.transmission.imageNumber,
      placementId: identitySource.transmission.placementId,
    );
    _emitGraphicsReply(reply);
  }

  void _emitError(
    TerminalKittyGraphicsCommand command,
    String code,
    String description, {
    TerminalKittyGraphicsCommand? identitySource,
  }) {
    final TerminalKittyGraphicsCommand identity = identitySource ?? command;
    final Uint8List? reply = TerminalKittyGraphicsResponseEncoder.error(
      quiet: command.quiet,
      code: code,
      description: description,
      imageId: identity.transmission.imageId,
      imageNumber: identity.transmission.imageNumber,
      placementId: identity.transmission.placementId,
    );
    _emitGraphicsReply(reply);
  }

  void _emitGraphicsReply(Uint8List? reply) {
    if (reply == null || _disposed) return;
    if (_callReply(reply)) {
      _emittedGraphicsReplyCount++;
    } else {
      _rejectedGraphicsReplyCount++;
    }
  }

  bool _callReply(Uint8List reply) {
    try {
      return _onReply(Uint8List.fromList(reply));
    } on Object {
      return false;
    }
  }

  void _completeIdleWaitersIfNeeded() {
    if (_pendingJobs != 0) return;
    for (final Completer<void> waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
  }

  static ({String code, String description}) _workerError(
    RuntimeImageWorkerStatus status,
  ) => switch (status) {
    RuntimeImageWorkerStatus.invalidRequest => (
      code: 'EINVAL',
      description: 'invalid image request',
    ),
    RuntimeImageWorkerStatus.invalidBase64 => (
      code: 'EINVAL',
      description: 'invalid base64 image data',
    ),
    RuntimeImageWorkerStatus.invalidCompression => (
      code: 'EINVAL',
      description: 'invalid compressed image data',
    ),
    RuntimeImageWorkerStatus.invalidDimensions => (
      code: 'EINVAL',
      description: 'invalid image dimensions',
    ),
    RuntimeImageWorkerStatus.invalidDataLength => (
      code: 'EINVAL',
      description: 'invalid image data length',
    ),
    RuntimeImageWorkerStatus.invalidPng => (
      code: 'EINVAL',
      description: 'invalid PNG image data',
    ),
    RuntimeImageWorkerStatus.unsupportedFormat => (
      code: 'ENOTSUP',
      description: 'image format is not supported',
    ),
    RuntimeImageWorkerStatus.resourceLimit => (
      code: 'ENOSPC',
      description: 'image decode limit reached',
    ),
    RuntimeImageWorkerStatus.aborted ||
    RuntimeImageWorkerStatus.noPendingTransfer ||
    RuntimeImageWorkerStatus.pending ||
    RuntimeImageWorkerStatus.decoded => (
      code: 'EIO',
      description: 'unexpected image worker response',
    ),
  };
}

final class _TerminalKittyPendingTransfer {
  const _TerminalKittyPendingTransfer({
    required this.command,
    required this.screenKind,
    required this.transferGeneration,
  });

  final TerminalKittyGraphicsCommand command;
  final TerminalScreenKind screenKind;
  final int transferGeneration;
}

final class _TerminalKittyQueueJob {
  _TerminalKittyQueueJob.command(TerminalKittyGraphicsCommand value)
    : command = value,
      _reply = null,
      byteCost = value.dataLength;

  _TerminalKittyQueueJob.reply(Uint8List reply)
    : command = null,
      _reply = Uint8List.fromList(reply),
      byteCost = reply.length;

  final TerminalKittyGraphicsCommand? command;
  final Uint8List? _reply;
  final int byteCost;

  Uint8List? copyReply() => _reply == null ? null : Uint8List.fromList(_reply);
}
