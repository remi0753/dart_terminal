import 'dart:async';
import 'dart:isolate';

import 'package:dart_terminal/dart_terminal.dart';

const TerminalSessionId _isolateSession = TerminalSessionId(
  paneId: PaneId(19),
  generation: 4,
);

Future<void> main() => runTerminalDamageTransferTests();

Future<void> runTerminalDamageTransferTests() async {
  await _testRealIsolateTransferAndPendingDamage();
  _testOneInFlightAndBoundedCoalescing();
  _testAcknowledgementValidation();
  _testPaneReplacementAndTransportTermination();
  _testDamageGenerationExhaustion();
  _testTransferEnvelopeValidation();
}

Future<void> _testRealIsolateTransferAndPendingDamage() async {
  final ReceivePort replies = ReceivePort();
  final ReceivePort exits = ReceivePort();
  final StreamIterator<Object?> replyIterator = StreamIterator<Object?>(
    replies.cast<Object?>(),
  );
  await Isolate.spawn<SendPort>(
    _damageReceiverWorker,
    replies.sendPort,
    onExit: exits.sendPort,
  );
  _expect(await replyIterator.moveNext(), 'receiver publishes its direct port');
  final SendPort receiver = replyIterator.current! as SendPort;

  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 5);
  screen.setNarrowCell(0, 0, 0x41);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: _isolateSession,
    screen: screen,
  );
  final TerminalDamageTransferEnvelope first = _transfer(
    outbox,
    resourceGeneration: 7,
  );
  final Object firstMessage = first.takeMessage();
  _expectState(
    first.takeMessage,
    'one transfer envelope cannot be sent more than once',
  );
  receiver.send(firstMessage);

  screen.setNarrowCell(1, 3, 0x42);
  _expect(
    outbox.tryCreateTransfer(requiredResourceGeneration: 7) == null &&
        outbox.inFlightCount == 1 &&
        outbox.hasPendingDamage,
    'mutation during transfer remains coalesced behind one in-flight packet',
  );
  _expect(await replyIterator.moveNext(), 'receiver returns first ACK');
  final TerminalDamageAckHandlingResult firstAck = outbox.acknowledgeMessage(
    replyIterator.current,
  );
  _expect(firstAck.isAccepted, 'real isolate full transfer is acknowledged');
  _expect(
    !screen.fullSnapshotRequired && screen.isRowDirty(1),
    'full ACK clears only resync state and preserves later dirty cells',
  );

  final TerminalDamageTransferEnvelope second = _transfer(
    outbox,
    resourceGeneration: 7,
  );
  _expect(!second.isFullSnapshot, 'post-ACK pending mutation is incremental');
  receiver.send(second.takeMessage());
  _expect(await replyIterator.moveNext(), 'receiver returns second ACK');
  _expect(
    outbox.acknowledgeMessage(replyIterator.current).isAccepted,
    'real isolate incremental transfer is acknowledged',
  );
  _expect(
    outbox.inFlightCount == 0 &&
        !outbox.hasPendingDamage &&
        outbox.publishedPacketCount == 2 &&
        outbox.acknowledgedPacketCount == 2,
    'real isolate exchange leaves constant-size empty bookkeeping',
  );

  await exits.first.timeout(const Duration(seconds: 5));
  await replyIterator.cancel();
  replies.close();
  exits.close();
}

Future<void> _damageReceiverWorker(SendPort parent) async {
  final ReceivePort incoming = ReceivePort();
  parent.send(incoming.sendPort);
  final TerminalDamageRenderModel model = TerminalDamageRenderModel();
  var received = 0;
  await for (final Object? message in incoming) {
    final TerminalDamageTransferEnvelope envelope =
        TerminalDamageTransferEnvelope.decodeMessage(message);
    final TerminalDecodedDamage damage = envelope.materializeDamage(
      expectedSessionId: _isolateSession,
    );
    final TerminalDamageApplyResult result = model.apply(
      damage,
      availableResourceGeneration: 7,
    );
    parent.send(
      result.isApplied
          ? TerminalDamageAcknowledgement.applied(
              sessionId: envelope.sessionId,
              damageGeneration: envelope.damageGeneration,
              acceptedBytes: result.acceptedBytes,
            ).toMessage()
          : TerminalDamageAcknowledgement.rejected(
              sessionId: envelope.sessionId,
              damageGeneration: envelope.damageGeneration,
            ).toMessage(),
    );
    received++;
    if (received == 2) {
      incoming.close();
    }
  }
}

void _testOneInFlightAndBoundedCoalescing() {
  const TerminalSessionId session = TerminalSessionId(
    paneId: PaneId(3),
    generation: 2,
  );
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 10);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: session,
    screen: screen,
  );
  final TerminalDamageTransferEnvelope full = _transfer(
    outbox,
    resourceGeneration: 1,
  );
  for (int mutation = 0; mutation < 1000; mutation++) {
    final int column = mutation.isEven ? 2 : 7;
    screen.setNarrowCell(1, column, 0x41 + mutation % 20);
    _expect(
      outbox.tryCreateTransfer(requiredResourceGeneration: 1) == null,
      'one-in-flight cap holds during sustained mutation $mutation',
    );
  }
  _expect(
    outbox.inFlightCount == 1 &&
        outbox.publishedPacketCount == 1 &&
        screen.rowVersionAt(1) == 1 &&
        screen.dirtyStartAt(1) == 2 &&
        screen.dirtyEndAt(1) == 8,
    'sustained changes use one transfer and one pending row union',
  );
  _expect(
    outbox
        .acknowledge(
          TerminalDamageAcknowledgement.applied(
            sessionId: session,
            damageGeneration: full.damageGeneration,
            acceptedBytes: full.byteLength,
          ),
        )
        .isAccepted,
    'exact full ACK releases sender bookkeeping',
  );
  final TerminalDamageTransferEnvelope pending = _transfer(
    outbox,
    resourceGeneration: 1,
  );
  final TerminalDamageTransferEnvelope received =
      TerminalDamageTransferEnvelope.decodeMessage(pending.takeMessage());
  final TerminalDecodedDamage decoded = received.materializeDamage(
    expectedSessionId: session,
  );
  _expect(
    !decoded.isFullSnapshot &&
        decoded.rowRecords.length == 1 &&
        decoded.rowRecords.single.firstColumn == 2 &&
        decoded.rowRecords.single.cellCount == 6,
    'next packet contains the complete pending union and no extra rows',
  );
  _expect(
    outbox
        .acknowledge(
          TerminalDamageAcknowledgement.applied(
            sessionId: session,
            damageGeneration: pending.damageGeneration,
            acceptedBytes: pending.byteLength,
          ),
        )
        .isAccepted,
    'pending union releases only after its exact ACK',
  );
  _expect(
    outbox.inFlightCount == 0 && !outbox.hasPendingDamage,
    'coalesced transfer drains without a sender queue',
  );
}

void _testAcknowledgementValidation() {
  const TerminalSessionId session = TerminalSessionId(
    paneId: PaneId(5),
    generation: 3,
  );
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 4);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: session,
    screen: screen,
  );
  final TerminalDamageTransferEnvelope transfer = _transfer(
    outbox,
    resourceGeneration: 2,
  );
  final List<Object?> valid =
      TerminalDamageAcknowledgement.applied(
            sessionId: session,
            damageGeneration: transfer.damageGeneration,
            acceptedBytes: transfer.byteLength,
          ).toMessage()
          as List<Object?>;

  final List<void Function(List<Object?>)> malformed =
      <void Function(List<Object?>)>[
        (List<Object?> values) => values[0] = 0,
        (List<Object?> values) => values[1] = 2,
        (List<Object?> values) => values[2] = 0,
        (List<Object?> values) => values[3] = 0,
        (List<Object?> values) => values[4] = 0,
        (List<Object?> values) => values[5] = -1,
        (List<Object?> values) => values[5] = 0,
        (List<Object?> values) => values[5] = 32 * 1024 * 1024 + 1,
        (List<Object?> values) => values[6] = 2,
        (List<Object?> values) => values[2] = '5',
        (List<Object?> values) {
          values[5] = 1;
          values[6] = 1;
        },
      ];
  _expect(
    outbox.acknowledgeMessage(null).disposition ==
        TerminalDamageAckDisposition.malformed,
    'non-list ACK is malformed',
  );
  _expect(
    outbox.acknowledgeMessage(<Object?>[]).disposition ==
        TerminalDamageAckDisposition.malformed,
    'wrong ACK field count is malformed',
  );
  for (int index = 0; index < malformed.length; index++) {
    final List<Object?> message = List<Object?>.from(valid);
    malformed[index](message);
    _expect(
      outbox.acknowledgeMessage(message).disposition ==
          TerminalDamageAckDisposition.malformed,
      'ACK scalar corruption $index is malformed',
    );
    _expect(outbox.inFlightCount == 1, 'malformed ACK retains in-flight state');
  }

  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: const TerminalSessionId(
                  paneId: PaneId(6),
                  generation: 3,
                ),
                damageGeneration: 1,
                acceptedBytes: transfer.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.wrongPane,
    'ACK for another logical pane is rejected',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: const TerminalSessionId(
                  paneId: PaneId(5),
                  generation: 2,
                ),
                damageGeneration: 1,
                acceptedBytes: transfer.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.stalePaneIgnored,
    'ACK from an older pane generation is ignored',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: const TerminalSessionId(
                  paneId: PaneId(5),
                  generation: 4,
                ),
                damageGeneration: 1,
                acceptedBytes: transfer.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.futurePane,
    'ACK from a future pane generation is rejected',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: session,
                damageGeneration: 2,
                acceptedBytes: transfer.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.futureDamage,
    'future damage ACK cannot release the current transfer',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: session,
                damageGeneration: 1,
                acceptedBytes: transfer.byteLength + 1,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.wrongByteCount,
    'wrong accepted byte count cannot release the current transfer',
  );
  _expect(
    outbox.acknowledgeMessage(valid).isAccepted && outbox.inFlightCount == 0,
    'only the exact valid ACK releases the transfer',
  );
  _expect(
    outbox.acknowledgeMessage(valid).disposition ==
        TerminalDamageAckDisposition.duplicate,
    'duplicate accepted ACK is classified deterministically',
  );
  final TerminalDamageOutbox advanced = TerminalDamageOutbox(
    sessionId: session,
    screen: TerminalScreen(rows: 1, columns: 1),
    initialDamageGeneration: 2,
  );
  _expect(
    advanced
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: session,
                damageGeneration: 1,
                acceptedBytes: TerminalDamageCodec.headerBytes,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.staleDamage,
    'older-than-last damage ACK is classified separately from a duplicate',
  );

  screen.setNarrowCell(0, 1, 0x41);
  final TerminalDamageTransferEnvelope rejected = _transfer(
    outbox,
    resourceGeneration: 2,
  );
  final TerminalDamageAckHandlingResult rejection = outbox.acknowledge(
    TerminalDamageAcknowledgement.rejected(
      sessionId: session,
      damageGeneration: rejected.damageGeneration,
    ),
  );
  _expect(
    rejection.disposition == TerminalDamageAckDisposition.rendererRejected &&
        rejection.relationshipClosed &&
        !outbox.isOpen &&
        outbox.inFlightCount == 0 &&
        screen.fullSnapshotRequired &&
        outbox.lastCloseReason ==
            TerminalDamageOutboxCloseReason.rendererRejected,
    'renderer rejection terminates the relationship and forces resync',
  );
}

void _testPaneReplacementAndTransportTermination() {
  const TerminalSessionId firstSession = TerminalSessionId(
    paneId: PaneId(8),
    generation: 1,
  );
  const TerminalSessionId secondSession = TerminalSessionId(
    paneId: PaneId(8),
    generation: 2,
  );
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 3);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: firstSession,
    screen: screen,
  );
  final TerminalDamageTransferEnvelope retired = _transfer(
    outbox,
    resourceGeneration: 1,
  );
  outbox.replacePaneGeneration(secondSession);
  _expect(
    outbox.isOpen &&
        outbox.inFlightCount == 0 &&
        outbox.lastAcknowledgedGeneration == 0 &&
        screen.fullSnapshotRequired,
    'pane replacement releases old bookkeeping and requests a full model',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: firstSession,
                damageGeneration: retired.damageGeneration,
                acceptedBytes: retired.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.stalePaneIgnored,
    'late ACK from replaced pane is ignored',
  );
  _expect(
    !outbox.notifyPortClosed(firstSession) &&
        !outbox.expireAcknowledgement(
          sessionId: firstSession,
          damageGeneration: retired.damageGeneration,
        ),
    'late close and deadline callbacks cannot retire the replacement',
  );
  final TerminalDamageTransferEnvelope replacement = _transfer(
    outbox,
    resourceGeneration: 2,
  );
  _expect(
    replacement.damageGeneration == 1 && replacement.isFullSnapshot,
    'replacement pane restarts damage generations with a full snapshot',
  );
  _expectArgument(
    () => outbox.replacePaneGeneration(secondSession),
    'same pane generation cannot replace itself',
  );
  _expectArgument(
    () => outbox.replacePaneGeneration(
      const TerminalSessionId(paneId: PaneId(9), generation: 3),
    ),
    'replacement cannot change logical pane identity',
  );
  _expect(
    !outbox.expireAcknowledgement(
      sessionId: secondSession,
      damageGeneration: replacement.damageGeneration + 1,
    ),
    'stale deadline token cannot close the active transfer',
  );
  _expect(
    outbox.expireAcknowledgement(
          sessionId: secondSession,
          damageGeneration: replacement.damageGeneration,
        ) &&
        !outbox.isOpen &&
        outbox.lastCloseReason ==
            TerminalDamageOutboxCloseReason.acknowledgementDeadlineExceeded &&
        screen.fullSnapshotRequired,
    'exact ACK deadline closes the relationship and forces resync',
  );
  _expectState(
    () => outbox.tryCreateTransfer(requiredResourceGeneration: 2),
    'closed relationship cannot publish',
  );
  _expect(
    outbox
            .acknowledge(
              TerminalDamageAcknowledgement.applied(
                sessionId: secondSession,
                damageGeneration: replacement.damageGeneration,
                acceptedBytes: replacement.byteLength,
              ),
            )
            .disposition ==
        TerminalDamageAckDisposition.relationshipClosed,
    'late current-generation ACK cannot reopen a closed relationship',
  );

  const TerminalSessionId thirdSession = TerminalSessionId(
    paneId: PaneId(8),
    generation: 3,
  );
  outbox.replacePaneGeneration(thirdSession);
  _transfer(outbox, resourceGeneration: 3);
  _expect(
    !outbox.notifyPortClosed(secondSession) &&
        outbox.notifyPortClosed(thirdSession) &&
        !outbox.isOpen &&
        outbox.lastCloseReason == TerminalDamageOutboxCloseReason.portClosed,
    'only the exact active port-close event terminates the relationship',
  );
}

void _testTransferEnvelopeValidation() {
  const TerminalSessionId session = TerminalSessionId(
    paneId: PaneId(12),
    generation: 6,
  );
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 3);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: session,
    screen: screen,
  );
  final TerminalDamageTransferEnvelope transfer = _transfer(
    outbox,
    resourceGeneration: 4,
  );
  final List<Object?> valid = transfer.takeMessage() as List<Object?>;
  _expectProtocol(
    () => TerminalDamageTransferEnvelope.decodeMessage(null),
    'non-list transfer',
  );
  _expectProtocol(
    () => TerminalDamageTransferEnvelope.decodeMessage(<Object?>[]),
    'wrong transfer field count',
  );
  final List<void Function(List<Object?>)> malformed =
      <void Function(List<Object?>)>[
        (List<Object?> values) => values[0] = 0,
        (List<Object?> values) => values[1] = 2,
        (List<Object?> values) => values[2] = 0,
        (List<Object?> values) => values[3] = 0,
        (List<Object?> values) => values[4] = 0,
        (List<Object?> values) => values[5] = 0,
        (List<Object?> values) => values[6] = 79,
        (List<Object?> values) => values[6] = 32 * 1024 * 1024 + 1,
        (List<Object?> values) => values[7] = 2,
        (List<Object?> values) => values[8] = 'bytes',
        (List<Object?> values) => values[4] = '1',
      ];
  for (int index = 0; index < malformed.length; index++) {
    final List<Object?> message = List<Object?>.from(valid);
    malformed[index](message);
    _expectProtocol(
      () => TerminalDamageTransferEnvelope.decodeMessage(message),
      'transfer scalar corruption $index',
    );
  }

  final TerminalScreen mismatchScreen = TerminalScreen(rows: 1, columns: 3);
  final TerminalDamageOutbox mismatchOutbox = TerminalDamageOutbox(
    sessionId: session,
    screen: mismatchScreen,
  );
  final TerminalDamageTransferEnvelope mismatch = _transfer(
    mismatchOutbox,
    resourceGeneration: 4,
  );
  final List<Object?> mismatchMessage = mismatch.takeMessage() as List<Object?>;
  mismatchMessage[4] = mismatch.damageGeneration + 1;
  final TerminalDamageTransferEnvelope receivedMismatch =
      TerminalDamageTransferEnvelope.decodeMessage(mismatchMessage);
  _expectProtocol(
    () => receivedMismatch.materializeDamage(expectedSessionId: session),
    'payload header must match transfer envelope',
  );

  final TerminalScreen materializeScreen = TerminalScreen(rows: 1, columns: 3);
  final TerminalDamageOutbox materializeOutbox = TerminalDamageOutbox(
    sessionId: session,
    screen: materializeScreen,
  );
  final TerminalDamageTransferEnvelope materialize = _transfer(
    materializeOutbox,
    resourceGeneration: 4,
  );
  final TerminalDamageTransferEnvelope received =
      TerminalDamageTransferEnvelope.decodeMessage(materialize.takeMessage());
  _expectProtocol(
    () => received.materializeDamage(
      expectedSessionId: const TerminalSessionId(
        paneId: PaneId(12),
        generation: 7,
      ),
    ),
    'receiver validates expected pane generation before materialization',
  );
  _expect(
    received.materializeDamage(expectedSessionId: session).damageGeneration ==
        materialize.damageGeneration,
    'valid receiver materializes and validates damage once',
  );
  _expectState(
    () => received.materializeDamage(expectedSessionId: session),
    'transfer payload cannot be materialized twice',
  );
}

void _testDamageGenerationExhaustion() {
  const TerminalSessionId session = TerminalSessionId(
    paneId: PaneId(11),
    generation: 1,
  );
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: session,
    screen: screen,
    initialDamageGeneration: 0x7ffffffffffffffe,
  );
  final TerminalDamageTransferEnvelope last = _transfer(
    outbox,
    resourceGeneration: 1,
  );
  _expect(
    last.damageGeneration == 0x7fffffffffffffff,
    'last positive signed damage generation remains publishable',
  );
  _expect(
    outbox
        .acknowledge(
          TerminalDamageAcknowledgement.applied(
            sessionId: session,
            damageGeneration: last.damageGeneration,
            acceptedBytes: last.byteLength,
          ),
        )
        .isAccepted,
    'last damage generation can be acknowledged exactly',
  );
  screen.setNarrowCell(0, 0, 0x41);
  _expectState(
    () => outbox.tryCreateTransfer(requiredResourceGeneration: 1),
    'damage generation does not wrap or alias',
  );
  _expect(
    !outbox.isOpen &&
        outbox.inFlightCount == 0 &&
        outbox.lastCloseReason ==
            TerminalDamageOutboxCloseReason.generationExhausted &&
        screen.fullSnapshotRequired,
    'generation exhaustion closes the relationship and forces replacement',
  );
}

TerminalDamageTransferEnvelope _transfer(
  TerminalDamageOutbox outbox, {
  required int resourceGeneration,
}) {
  final TerminalDamageTransferEnvelope? transfer = outbox.tryCreateTransfer(
    requiredResourceGeneration: resourceGeneration,
  );
  if (transfer == null) throw StateError('test expected damage transfer');
  return transfer;
}

void _expectProtocol(void Function() action, String message) {
  try {
    action();
  } on TerminalDamageProtocolException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectState(void Function() action, String message) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectArgument(void Function() action, String message) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
