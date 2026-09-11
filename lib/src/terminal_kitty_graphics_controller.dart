import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'runtime_image_worker_protocol.dart';
import 'runtime_lifecycle.dart';
import 'terminal_core/terminal_kitty_graphics.dart';
import 'terminal_core/terminal_kitty_image_store.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_core/terminal_screen.dart';
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
    void Function()? onChanged,
    RuntimeWorkerPayloadClient? worker,
    this.maximumQueuedJobs =
        TerminalKittyGraphicsControllerLimits.maximumQueuedJobs,
    this.maximumQueuedBytes =
        TerminalKittyGraphicsControllerLimits.maximumQueuedBytes,
  }) : _onReply = onReply,
       _onChanged = onChanged,
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
  final void Function()? _onChanged;
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
    final TerminalScreenKind screenKind = screenSet.activeKind;
    final TerminalScreen screen = screenSet.activeScreen;
    _queue.addLast(
      _TerminalKittyQueueJob.command(
        command,
        _TerminalKittyCommandContext(
          screenKind: screenKind,
          cursorAnchor: screenSet.viewport.anchorAtScreenCell(
            screenKind,
            screen.cursorRow,
            screen.cursorColumn,
          ),
          cursorRow: screen.cursorRow,
          cursorColumn: screen.cursorColumn,
        ),
      ),
    );
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
              await _executeCommand(command, job.context!);
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

  Future<void> _executeCommand(
    TerminalKittyGraphicsCommand command,
    _TerminalKittyCommandContext context,
  ) async {
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
    if ((command.action == TerminalKittyGraphicsAction.controlAnimation ||
            command.action == TerminalKittyGraphicsAction.composeAnimation) &&
        command.transmission.imageId == 0 &&
        command.transmission.imageNumber == 0) {
      await _abortPendingTransfer();
      _emitError(command, 'EINVAL', 'image id or number is required');
      return;
    }
    switch (command.action) {
      case TerminalKittyGraphicsAction.controlAnimation:
        await _abortPendingTransfer();
        _controlAnimation(command, context);
        return;
      case TerminalKittyGraphicsAction.composeAnimation:
        await _abortPendingTransfer();
        _composeAnimation(command, context);
        return;
      case TerminalKittyGraphicsAction.transmitAnimationFrame:
        break;
      case TerminalKittyGraphicsAction.place:
        await _abortPendingTransfer();
        _placeImage(command, identitySource: command, context: context);
        return;
      case TerminalKittyGraphicsAction.transmitAndPlace:
        break;
      case TerminalKittyGraphicsAction.delete:
        await _abortPendingTransfer();
        _delete(command, context);
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
      if (!command.isMultipartContinuationFor(pending.command.action)) {
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
    final TerminalKittyImageStore contextStore = screenSet.kittyImagesFor(
      context.screenKind,
    );
    final TerminalKittyImage? frameTarget =
        command.action == TerminalKittyGraphicsAction.transmitAnimationFrame
        ? command.transmission.imageId != 0
              ? contextStore.imageById(command.transmission.imageId)
              : contextStore.newestImageByNumber(
                  command.transmission.imageNumber,
                )
        : null;
    if (command.action == TerminalKittyGraphicsAction.transmitAnimationFrame &&
        frameTarget == null) {
      _emitError(command, 'ENOENT', 'image not found');
      return;
    }
    if (command.action != TerminalKittyGraphicsAction.query &&
        command.action != TerminalKittyGraphicsAction.transmitAnimationFrame &&
        command.transmission.imageId != 0 &&
        contextStore.removePlacementsForImage(command.transmission.imageId) !=
            0) {
      _notifyChanged();
    }
    final _TerminalKittyPendingTransfer transfer =
        _TerminalKittyPendingTransfer(
          command: command,
          context: context,
          transferGeneration: transferGeneration,
          targetImageResourceGeneration: frameTarget?.resourceGeneration,
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
      transfer.context.screenKind,
    );
    if (initial.action == TerminalKittyGraphicsAction.transmitAnimationFrame) {
      final TerminalKittyAnimationMutationResult result = store
          .storeAnimationFrame(
            imageId: initial.transmission.imageId,
            imageNumber: initial.transmission.imageNumber,
            expectedResourceGeneration: transfer.targetImageResourceGeneration!,
            width: response.width,
            height: response.height,
            x: initial.frameTransmission.x,
            y: initial.frameTransmission.y,
            baseFrame: initial.frameTransmission.baseFrame,
            editFrame: initial.frameTransmission.editFrame,
            gapMilliseconds: initial.frameTransmission.gapMilliseconds,
            overwrite: initial.frameTransmission.overwrite,
            backgroundRgba: initial.frameTransmission.backgroundRgba,
            transient: initial.transmission.usage & 1 != 0,
            rgba: response.copyRgba(),
          );
      switch (result.disposition) {
        case TerminalKittyAnimationMutationDisposition.stored:
          _notifyChanged();
          _emitSuccess(
            finalCommand,
            identitySource: initial,
            resolvedImageId: result.image!.id,
            resolvedFrameNumber: result.frameNumber,
          );
          return;
        case TerminalKittyAnimationMutationDisposition.imageMissing:
          _emitError(
            finalCommand,
            'ENOENT',
            'image not found',
            identitySource: initial,
            frameNumber: initial.frameTransmission.editFrame,
          );
          return;
        case TerminalKittyAnimationMutationDisposition.baseFrameMissing:
          _emitError(
            finalCommand,
            'EINVAL',
            'base frame not found',
            identitySource: initial,
            frameNumber: result.frameNumber,
          );
          return;
        case TerminalKittyAnimationMutationDisposition.sourceFrameMissing:
        case TerminalKittyAnimationMutationDisposition.destinationFrameMissing:
          throw StateError(
            'frame composition result returned for transmission',
          );
        case TerminalKittyAnimationMutationDisposition.invalidRectangle:
          _emitError(
            finalCommand,
            'EINVAL',
            'frame dimensions exceed image',
            identitySource: initial,
            frameNumber: initial.frameTransmission.editFrame,
          );
          return;
        case TerminalKittyAnimationMutationDisposition.resourceLimit:
          _emitError(
            finalCommand,
            'ENOSPC',
            'animation frame storage full',
            identitySource: initial,
            frameNumber: result.frameNumber,
          );
          return;
      }
    }
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
    if (initial.action == TerminalKittyGraphicsAction.transmitAndPlace) {
      _placeImage(
        finalCommand,
        identitySource: initial,
        context: transfer.context,
        resolvedImageId: image.id,
      );
      return;
    }
    _notifyChanged();
    _emitSuccess(
      finalCommand,
      identitySource: initial,
      resolvedImageId: image.id,
    );
  }

  void _placeImage(
    TerminalKittyGraphicsCommand replyCommand, {
    required TerminalKittyGraphicsCommand identitySource,
    required _TerminalKittyCommandContext context,
    int? resolvedImageId,
  }) {
    final TerminalKittyGraphicsPlacement request = identitySource.placement;
    if (request.cursorMovement > 1) {
      _emitError(
        replyCommand,
        'EINVAL',
        'cursor movement must be zero or one',
        identitySource: identitySource,
      );
      return;
    }
    if (request.virtual) {
      _emitError(
        replyCommand,
        'ENOTSUP',
        'virtual image placement is not supported',
        identitySource: identitySource,
      );
      return;
    }
    if (request.parentImageId != 0 ||
        request.parentPlacementId != 0 ||
        request.relativeColumnOffset != 0 ||
        request.relativeRowOffset != 0) {
      _emitError(
        replyCommand,
        'ENOTSUP',
        'relative image placement is not supported',
        identitySource: identitySource,
      );
      return;
    }
    if (request.z < -0x40000000) {
      _emitError(
        replyCommand,
        'ENOTSUP',
        'extreme negative image z-index is not supported',
        identitySource: identitySource,
      );
      return;
    }
    final ({int width, int height})? cell = screenSet.logicalCellSize;
    if (cell == null) {
      _emitError(
        replyCommand,
        'EAGAIN',
        'logical cell metrics are unavailable',
        identitySource: identitySource,
      );
      return;
    }
    final TerminalScreen screen = screenSet.screenFor(context.screenKind);
    final TerminalLogicalAnchor anchor = context.cursorAnchor;
    final TerminalKittyImageStore store = screenSet.kittyImagesFor(
      context.screenKind,
    );
    late final TerminalKittyImagePlacementResult result;
    try {
      result = store.place(
        imageId: resolvedImageId ?? request.imageId,
        imageNumber: resolvedImageId == null ? request.imageNumber : 0,
        placementId: request.placementId,
        logicalLineId: anchor.logicalLineId,
        logicalLineEpoch: anchor.logicalLineEpoch,
        logicalCellOffset: anchor.cellOffset,
        sourceX: request.sourceX,
        sourceY: request.sourceY,
        sourceWidth: request.sourceWidth,
        sourceHeight: request.sourceHeight,
        cellOffsetX: request.cellOffsetX,
        cellOffsetY: request.cellOffsetY,
        columns: request.columns,
        rows: request.rows,
        z: request.z,
      );
    } on Object {
      _emitError(
        replyCommand,
        'EINVAL',
        'invalid image placement metadata',
        identitySource: identitySource,
      );
      return;
    }
    switch (result.disposition) {
      case TerminalKittyImagePlacementDisposition.imageMissing:
        _emitError(
          replyCommand,
          'ENOENT',
          'image not found',
          identitySource: identitySource,
        );
        return;
      case TerminalKittyImagePlacementDisposition.resourceLimit:
        _emitError(
          replyCommand,
          'ENOSPC',
          'image placement limit reached',
          identitySource: identitySource,
        );
        return;
      case TerminalKittyImagePlacementDisposition.stored:
        break;
    }
    final TerminalKittyImage image = result.image!;
    final TerminalKittyImagePlacement placement = result.placement!;
    final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
      image: image,
      cellWidth: cell.width,
      cellHeight: cell.height,
    );
    if (!request.suppressCursorMovement) {
      _moveCursorAfterPlacement(screen, geometry);
    }
    _notifyChanged();
    _emitSuccess(
      replyCommand,
      identitySource: identitySource,
      resolvedImageId: image.id,
    );
  }

  void _controlAnimation(
    TerminalKittyGraphicsCommand command,
    _TerminalKittyCommandContext context,
  ) {
    final TerminalKittyImageStore store = screenSet.kittyImagesFor(
      context.screenKind,
    );
    final int before = store.stateGeneration;
    final TerminalKittyAnimationControlResult result = store.controlAnimation(
      imageId: command.transmission.imageId,
      imageNumber: command.transmission.imageNumber,
      control: command.animationControl,
    );
    if (result.disposition ==
        TerminalKittyAnimationControlDisposition.imageMissing) {
      _emitError(command, 'ENOENT', 'image not found');
      return;
    }
    if (store.stateGeneration != before) _notifyChanged();
    // Kitty animation-control success is deliberately reply-free.
  }

  void _composeAnimation(
    TerminalKittyGraphicsCommand command,
    _TerminalKittyCommandContext context,
  ) {
    final TerminalKittyImageStore store = screenSet.kittyImagesFor(
      context.screenKind,
    );
    final TerminalKittyAnimationMutationResult result = store
        .composeAnimationFrames(
          imageId: command.transmission.imageId,
          imageNumber: command.transmission.imageNumber,
          composition: command.frameComposition,
        );
    switch (result.disposition) {
      case TerminalKittyAnimationMutationDisposition.stored:
        _notifyChanged();
        _emitSuccess(
          command,
          identitySource: command,
          resolvedImageId: result.image!.id,
        );
        return;
      case TerminalKittyAnimationMutationDisposition.imageMissing:
        _emitError(command, 'ENOENT', 'image not found');
        return;
      case TerminalKittyAnimationMutationDisposition.baseFrameMissing:
        throw StateError('frame transmission result returned for composition');
      case TerminalKittyAnimationMutationDisposition.sourceFrameMissing:
        _emitError(command, 'ENOENT', 'source frame not found');
        return;
      case TerminalKittyAnimationMutationDisposition.destinationFrameMissing:
        _emitError(command, 'ENOENT', 'destination frame not found');
        return;
      case TerminalKittyAnimationMutationDisposition.invalidRectangle:
        _emitError(command, 'EINVAL', 'invalid animation rectangle');
        return;
      case TerminalKittyAnimationMutationDisposition.resourceLimit:
        _emitError(command, 'ENOSPC', 'animation frame storage full');
        return;
    }
  }

  void _moveCursorAfterPlacement(
    TerminalScreen screen,
    TerminalKittyImagePlacementGeometry geometry,
  ) {
    if (geometry.columns == 0 || geometry.rows == 0) return;
    final int targetColumn = screen.cursorColumn + geometry.columns;
    final bool wraps = targetColumn >= screen.columns;
    final int requestedRows = geometry.rows - 1 + (wraps ? 1 : 0);
    final bool cursorInRegion =
        screen.cursorRow >= screen.topMargin &&
        screen.cursorRow <= screen.bottomMargin &&
        screen.cursorColumn >= screen.activeLeftMargin &&
        screen.cursorColumn <= screen.activeRightMargin;
    final int rowsBeforeScroll = cursorInRegion
        ? screen.bottomMargin - screen.cursorRow
        : 0;
    final int rowsToMove = requestedRows.clamp(
      0,
      rowsBeforeScroll + screen.rows,
    );
    for (var row = 0; row < rowsToMove; row++) {
      screen.index();
    }
    screen.setCursorPosition(screen.cursorRow, wraps ? 0 : targetColumn);
  }

  void _delete(
    TerminalKittyGraphicsCommand command,
    _TerminalKittyCommandContext context,
  ) {
    final TerminalKittyGraphicsDeleteSelector selector =
        command.deletion.selector;
    if (selector == TerminalKittyGraphicsDeleteSelector.animationFrames ||
        selector ==
            TerminalKittyGraphicsDeleteSelector.animationFramesAndData) {
      final TerminalKittyImageStore store = screenSet.kittyImagesFor(
        context.screenKind,
      );
      final int before = store.stateGeneration;
      store.deleteAnimationFrame(command.deletion);
      if (store.stateGeneration != before) _notifyChanged();
      return;
    }
    final TerminalScreenKind kind = context.screenKind;
    final TerminalScreen screen = screenSet.screenFor(kind);
    final TerminalKittyImageStore store = screenSet.kittyImagesFor(kind);
    final ({int width, int height})? cell = screenSet.logicalCellSize;
    final TerminalKittyImageDeleteResult deleted = store.delete(
      deletion: command.deletion,
      cursorRow: context.cursorRow,
      cursorColumn: context.cursorColumn,
      screenRows: screen.rows,
      screenColumns: screen.columns,
      cellWidth: cell?.width ?? 0,
      cellHeight: cell?.height ?? 0,
      resolvePosition: (TerminalKittyImagePlacement placement) {
        final TerminalViewportPosition? position = screenSet.viewport
            .screenCellPositionOf(
              kind,
              TerminalLogicalAnchor(
                screenKind: kind,
                logicalLineId: placement.logicalLineId,
                logicalLineEpoch: placement.logicalLineEpoch,
                cellOffset: placement.logicalCellOffset,
              ),
            );
        return position == null
            ? null
            : TerminalKittyImagePlacementPosition(
                row: position.row,
                column: position.column,
              );
      },
    );
    if (deleted.mutated) _notifyChanged();
  }

  void _notifyChanged() {
    try {
      _onChanged?.call();
    } on Object {
      // Presentation notification cannot alter terminal protocol ownership.
    }
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
    int resolvedFrameNumber = 0,
  }) {
    final Uint8List? reply = TerminalKittyGraphicsResponseEncoder.success(
      quiet: command.quiet,
      imageId: resolvedImageId ?? identitySource.transmission.imageId,
      imageNumber: identitySource.transmission.imageNumber,
      placementId: identitySource.transmission.placementId,
      frameNumber: resolvedFrameNumber,
    );
    _emitGraphicsReply(reply);
  }

  void _emitError(
    TerminalKittyGraphicsCommand command,
    String code,
    String description, {
    TerminalKittyGraphicsCommand? identitySource,
    int frameNumber = 0,
  }) {
    final TerminalKittyGraphicsCommand identity = identitySource ?? command;
    final int responseFrameNumber = frameNumber != 0
        ? frameNumber
        : identity.action == TerminalKittyGraphicsAction.transmitAnimationFrame
        ? identity.frameTransmission.editFrame
        : 0;
    final Uint8List? reply = TerminalKittyGraphicsResponseEncoder.error(
      quiet: command.quiet,
      code: code,
      description: description,
      imageId: identity.transmission.imageId,
      imageNumber: identity.transmission.imageNumber,
      placementId: identity.transmission.placementId,
      frameNumber: responseFrameNumber,
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
    required this.context,
    required this.transferGeneration,
    required this.targetImageResourceGeneration,
  });

  final TerminalKittyGraphicsCommand command;
  final _TerminalKittyCommandContext context;
  final int transferGeneration;
  final int? targetImageResourceGeneration;
}

final class _TerminalKittyCommandContext {
  const _TerminalKittyCommandContext({
    required this.screenKind,
    required this.cursorAnchor,
    required this.cursorRow,
    required this.cursorColumn,
  });

  final TerminalScreenKind screenKind;
  final TerminalLogicalAnchor cursorAnchor;
  final int cursorRow;
  final int cursorColumn;
}

final class _TerminalKittyQueueJob {
  _TerminalKittyQueueJob.command(
    TerminalKittyGraphicsCommand value,
    _TerminalKittyCommandContext valueContext,
  ) : command = value,
      context = valueContext,
      _reply = null,
      byteCost = value.dataLength;

  _TerminalKittyQueueJob.reply(Uint8List reply)
    : command = null,
      context = null,
      _reply = Uint8List.fromList(reply),
      byteCost = reply.length;

  final TerminalKittyGraphicsCommand? command;
  final _TerminalKittyCommandContext? context;
  final Uint8List? _reply;
  final int byteCost;

  Uint8List? copyReply() => _reply == null ? null : Uint8List.fromList(_reply);
}
