import 'package:dart_terminal/dart_terminal.dart';

const TerminalSessionId _sessionId = TerminalSessionId(
  paneId: PaneId(41),
  generation: 3,
);

void main() => runRenderRebuildCoordinatorTests();

void runRenderRebuildCoordinatorTests() {
  _testFullSnapshotEpochProtectsNewerRequest();
  _testResizeRebindRetainsCapturedScreenOwnership();
  _testNewestRequestCoalescingAndSupersededCompletion();
  _testFailureRetryAndResourceTransitionRules();
  _testRequestGenerationExhaustionDoesNotWrap();
  _testTargetValidation();
}

void _testFullSnapshotEpochProtectsNewerRequest() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 3);
  final TerminalDamageOutbox outbox = _outbox(screen);
  final int capturedEpoch = screen.fullSnapshotRequestEpoch;
  final TerminalDamageTransferEnvelope first = _transfer(outbox, 1);

  screen.requestFullSnapshot();
  final int newerEpoch = screen.fullSnapshotRequestEpoch;
  _expect(
    newerEpoch == capturedEpoch + 1 &&
        !screen.acknowledgeFullSnapshot(requestEpoch: capturedEpoch) &&
        screen.fullSnapshotRequired,
    'older direct acknowledgement cannot clear a newer request epoch',
  );
  _ack(outbox, first);
  _expect(
    screen.fullSnapshotRequired &&
        screen.fullSnapshotRequestEpoch == newerEpoch &&
        outbox.inFlightCount == 0,
    'older packet ACK releases ownership without clearing newer full state',
  );

  final TerminalDamageTransferEnvelope second = _transfer(outbox, 1);
  _expect(second.isFullSnapshot, 'newer epoch publishes another full packet');
  _ack(outbox, second);
  _expect(
    !screen.fullSnapshotRequired && !outbox.hasPendingDamage,
    'exact current epoch acknowledgement clears full state',
  );
}

void _testResizeRebindRetainsCapturedScreenOwnership() {
  final TerminalScreen original = TerminalScreen(rows: 2, columns: 3)
    ..setNarrowCell(0, 0, 0x41);
  final TerminalDamageOutbox outbox = _outbox(original);
  final TerminalDamageTransferEnvelope oldFull = _transfer(outbox, 1);
  final TerminalScreen replacement = original.resized(rows: 3, columns: 4);

  outbox.rebindScreenForFullRebuild(replacement);
  _expect(
    outbox.isBoundToScreen(replacement) &&
        replacement.fullSnapshotRequired &&
        outbox.inFlightCount == 1,
    'resize publishes the replacement owner without dropping old in-flight',
  );
  _ack(outbox, oldFull);
  _expect(
    !original.fullSnapshotRequired && replacement.fullSnapshotRequired,
    'old ACK applies only to its captured screen identity',
  );

  final TerminalDamageTransferEnvelope resized = _transfer(outbox, 2);
  final TerminalDecodedDamage decoded = resized.materializeDamage(
    expectedSessionId: _sessionId,
  );
  _expect(
    decoded.isFullSnapshot &&
        decoded.rows == 3 &&
        decoded.columns == 4 &&
        decoded.requiredResourceGeneration == 2 &&
        decoded.contentAt(0) == 0x41,
    'next packet is a full snapshot of the replacement grid and resources',
  );
  _ack(outbox, resized);
  _expect(
    !replacement.fullSnapshotRequired && outbox.inFlightCount == 0,
    'replacement full snapshot completes normally',
  );
}

void _testNewestRequestCoalescingAndSupersededCompletion() {
  final TerminalScreen original = TerminalScreen(rows: 2, columns: 2);
  final TerminalDamageOutbox outbox = _initializedOutbox(original);
  final TerminalRenderRebuildCoordinator coordinator =
      TerminalRenderRebuildCoordinator(
        damageOutbox: outbox,
        initialTarget: _target(original),
        initialResources: TerminalRenderResourceGenerations(
          catalogGeneration: 10,
          atlasGeneration: 20,
        ),
      );
  final TerminalScreen resized = original.resized(rows: 3, columns: 4);

  for (int index = 0; index < 1000; index++) {
    final bool changed = coordinator.request(
      _target(
        resized,
        viewportWidth: index.isEven ? 300 : 301,
        viewportHeight: 180 + index,
      ),
    );
    _expect(
      changed && coordinator.pendingPlanCount == 1,
      'request burst retains one newest target at index $index',
    );
  }
  final TerminalRenderRebuildPlan oldPlan = coordinator.beginNewest()!;
  _expect(
    oldPlan.requestGeneration == 1000 &&
        oldPlan.reasons.hasResize &&
        !oldPlan.reasons.hasScale &&
        !oldPlan.reasons.hasFont &&
        !coordinator.hasPendingRebuild &&
        coordinator.isRebuilding,
    'burst begins only its newest resize plan',
  );

  coordinator.request(
    _target(
      resized,
      viewportWidth: 360,
      viewportHeight: 240,
      scale16_16: 2 << 16,
      fontConfigurationGeneration: 2,
    ),
  );
  final TerminalRenderRebuildCompletion superseded = coordinator.complete(
    oldPlan,
    resources: TerminalRenderResourceGenerations(
      catalogGeneration: 10,
      atlasGeneration: 20,
    ),
  );
  _expect(
    superseded.disposition ==
            TerminalRenderRebuildCompletionDisposition.superseded &&
        !outbox.isBoundToScreen(resized) &&
        coordinator.pendingPlanCount == 1 &&
        coordinator.supersededCount == 1,
    'older resource completion cannot publish after a newer request',
  );

  final TerminalRenderRebuildPlan current = coordinator.beginNewest()!;
  _expect(
    current.reasons.hasResize &&
        current.reasons.hasScale &&
        current.reasons.hasFont,
    'newest plan retains all unpublished rebuild categories',
  );
  _expectState(
    () => coordinator.complete(
      current,
      resources: TerminalRenderResourceGenerations(
        catalogGeneration: 10,
        atlasGeneration: 21,
      ),
    ),
    'font rebuild must advance its catalog generation',
  );
  _expect(
    coordinator.isRebuilding && !outbox.isBoundToScreen(resized),
    'invalid resource completion is atomic and retryable',
  );
  final TerminalRenderRebuildCompletion published = coordinator.complete(
    current,
    resources: TerminalRenderResourceGenerations(
      catalogGeneration: 11,
      atlasGeneration: 21,
    ),
  );
  _expect(
    published.isPublished &&
        outbox.isBoundToScreen(resized) &&
        coordinator.publishedTarget.viewportWidth == 360 &&
        coordinator.publishedTarget.scale16_16 == 2 << 16 &&
        coordinator.publishedResources.catalogGeneration == 11 &&
        coordinator.publishedResources.atlasGeneration == 21 &&
        coordinator.pendingReasons.isEmpty &&
        coordinator.requestCount == 1001 &&
        coordinator.publishedCount == 1,
    'only the complete newest target and resource pair is published',
  );
  final TerminalDamageTransferEnvelope rebuilt = _transfer(outbox, 21);
  final TerminalDecodedDamage damage = rebuilt.materializeDamage(
    expectedSessionId: _sessionId,
  );
  _expect(
    damage.isFullSnapshot &&
        damage.rows == 3 &&
        damage.columns == 4 &&
        damage.requiredResourceGeneration == 21,
    'published target releases one matching full damage snapshot',
  );
}

void _testFailureRetryAndResourceTransitionRules() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  final TerminalDamageOutbox outbox = _initializedOutbox(screen);
  final TerminalRenderRebuildCoordinator coordinator =
      TerminalRenderRebuildCoordinator(
        damageOutbox: outbox,
        initialTarget: _target(screen),
        initialResources: TerminalRenderResourceGenerations(
          catalogGeneration: 5,
          atlasGeneration: 8,
        ),
      );

  coordinator.request(_target(screen, scale16_16: 2 << 16));
  final TerminalRenderRebuildPlan failed = coordinator.beginNewest()!;
  coordinator.fail(failed);
  _expect(
    coordinator.failureCount == 1 &&
        coordinator.hasPendingRebuild &&
        !coordinator.isRebuilding,
    'failed work retains the newest target for bounded retry',
  );
  final TerminalRenderRebuildPlan scaleRetry = coordinator.beginNewest()!;
  _expectState(
    () => coordinator.complete(
      scaleRetry,
      resources: TerminalRenderResourceGenerations(
        catalogGeneration: 5,
        atlasGeneration: 8,
      ),
    ),
    'scale rebuild must advance atlas generation',
  );
  coordinator.complete(
    scaleRetry,
    resources: TerminalRenderResourceGenerations(
      catalogGeneration: 5,
      atlasGeneration: 9,
    ),
  );

  final TerminalScreen resized = screen.resized(rows: 2, columns: 2);
  coordinator.request(
    _target(
      resized,
      viewportWidth: 40,
      viewportHeight: 40,
      scale16_16: 2 << 16,
    ),
  );
  final TerminalRenderRebuildPlan resize = coordinator.beginNewest()!;
  coordinator.complete(
    resize,
    resources: TerminalRenderResourceGenerations(
      catalogGeneration: 5,
      atlasGeneration: 9,
    ),
  );
  _expect(
    outbox.isBoundToScreen(resized) && coordinator.publishedCount == 2,
    'resize-only publication preserves valid font and atlas generations',
  );

  coordinator.request(
    _target(
      resized,
      viewportWidth: 40,
      viewportHeight: 40,
      scale16_16: 2 << 16,
      fontConfigurationGeneration: 2,
    ),
  );
  final TerminalRenderRebuildPlan font = coordinator.beginNewest()!;
  _expectState(
    () => coordinator.complete(
      font,
      resources: TerminalRenderResourceGenerations(
        catalogGeneration: 6,
        atlasGeneration: 8,
      ),
    ),
    'resource generations cannot regress',
  );
  coordinator.complete(
    font,
    resources: TerminalRenderResourceGenerations(
      catalogGeneration: 6,
      atlasGeneration: 10,
    ),
  );
  _expect(
    coordinator.publishedCount == 3 &&
        !coordinator.hasPendingRebuild &&
        !coordinator.isRebuilding,
    'font retry publishes after both resource generations are valid',
  );
}

void _testRequestGenerationExhaustionDoesNotWrap() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  final TerminalDamageOutbox outbox = _initializedOutbox(screen);
  final TerminalRenderRebuildCoordinator coordinator =
      TerminalRenderRebuildCoordinator(
        damageOutbox: outbox,
        initialTarget: _target(screen),
        initialResources: TerminalRenderResourceGenerations(
          catalogGeneration: 1,
          atlasGeneration: 1,
        ),
        initialRequestGeneration: 0x7ffffffffffffffe,
      );
  coordinator.request(_target(screen, viewportWidth: 21));
  _expect(
    coordinator.requestGeneration == 0x7fffffffffffffff &&
        coordinator.pendingPlanCount == 1,
    'last signed rebuild generation is retained',
  );
  _expectState(
    () => coordinator.request(_target(screen, viewportWidth: 22)),
    'rebuild generation exhaustion fails before wrap or target mutation',
  );
  _expect(
    coordinator.requestedTarget.viewportWidth == 21 &&
        coordinator.pendingPlanCount == 1,
    'exhaustion preserves the last valid newest target',
  );
}

void _testTargetValidation() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  _expectRange(
    () => _target(screen, viewportWidth: 0),
    'zero viewport rejected',
  );
  _expectRange(
    () => _target(screen, scale16_16: (1 << 15) - 1),
    'sub-minimum backing scale rejected',
  );
  _expectRange(
    () => _target(screen, fontConfigurationGeneration: 0),
    'zero font configuration generation rejected',
  );
  final TerminalDamageOutbox other = _initializedOutbox(
    TerminalScreen(rows: 1, columns: 1),
  );
  _expectArgument(
    () => TerminalRenderRebuildCoordinator(
      damageOutbox: other,
      initialTarget: _target(screen),
      initialResources: TerminalRenderResourceGenerations(
        catalogGeneration: 1,
        atlasGeneration: 1,
      ),
    ),
    'initial target must match the outbox owner',
  );
}

TerminalRenderRebuildTarget _target(
  TerminalScreen screen, {
  int viewportWidth = 20,
  int viewportHeight = 20,
  int scale16_16 = 1 << 16,
  int fontConfigurationGeneration = 1,
}) => TerminalRenderRebuildTarget(
  screen: screen,
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
  scale16_16: scale16_16,
  fontConfigurationGeneration: fontConfigurationGeneration,
);

TerminalDamageOutbox _outbox(TerminalScreen screen) =>
    TerminalDamageOutbox(sessionId: _sessionId, screen: screen);

TerminalDamageOutbox _initializedOutbox(TerminalScreen screen) {
  final TerminalDamageOutbox outbox = _outbox(screen);
  _ack(outbox, _transfer(outbox, 1));
  return outbox;
}

TerminalDamageTransferEnvelope _transfer(
  TerminalDamageOutbox outbox,
  int resourceGeneration,
) {
  final TerminalDamageTransferEnvelope? transfer = outbox.tryCreateTransfer(
    requiredResourceGeneration: resourceGeneration,
  );
  if (transfer == null) throw StateError('test expected damage transfer');
  return transfer;
}

void _ack(
  TerminalDamageOutbox outbox,
  TerminalDamageTransferEnvelope envelope,
) {
  final TerminalDamageAckHandlingResult result = outbox.acknowledge(
    TerminalDamageAcknowledgement.applied(
      sessionId: envelope.sessionId,
      damageGeneration: envelope.damageGeneration,
      acceptedBytes: envelope.byteLength,
    ),
  );
  if (!result.isAccepted) throw StateError('test expected accepted ACK');
}

void _expectRange(void Function() action, String description) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('render rebuild test failed: $description');
}

void _expectArgument(void Function() action, String description) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('render rebuild test failed: $description');
}

void _expectState(void Function() action, String description) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('render rebuild test failed: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('render rebuild test failed: $description');
  }
}
