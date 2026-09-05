import 'dart:isolate';
import 'dart:typed_data';

import '../terminal_core/terminal_screen.dart';
import '../terminal_pane.dart';
import 'terminal_damage.dart';

final class TerminalDamageProtocolException implements Exception {
  const TerminalDamageProtocolException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDamageProtocolException: $message';
}

/// One-shot isolate message containing copied ADR-003 damage bytes.
final class TerminalDamageTransferEnvelope {
  TerminalDamageTransferEnvelope._({
    required this.sessionId,
    required this.damageGeneration,
    required this.requiredResourceGeneration,
    required this.byteLength,
    required this.isFullSnapshot,
    required TransferableTypedData payload,
  }) : _payload = payload;

  static const int messageMagic = 0x44545444;
  static const int messageVersion = 1;
  static const int messageFieldCount = 9;
  static const int maximumByteLength = 32 * 1024 * 1024;

  final TerminalSessionId sessionId;
  final int damageGeneration;
  final int requiredResourceGeneration;
  final int byteLength;
  final bool isFullSnapshot;
  final TransferableTypedData _payload;
  bool _messageTaken = false;
  bool _materialized = false;

  /// Returns the primitive, sendable wire envelope exactly once.
  Object takeMessage() {
    if (_messageTaken) {
      throw StateError('damage transfer message was already taken');
    }
    if (_materialized) {
      throw StateError('materialized damage cannot be transferred');
    }
    _messageTaken = true;
    return <Object?>[
      messageMagic,
      messageVersion,
      sessionId.paneId.value,
      sessionId.generation,
      damageGeneration,
      requiredResourceGeneration,
      byteLength,
      isFullSnapshot ? 1 : 0,
      _payload,
    ];
  }

  /// Strictly validates the scalar envelope without materializing its payload.
  factory TerminalDamageTransferEnvelope.decodeMessage(Object? message) {
    final List<Object?> fields = _messageFields(
      message,
      expectedCount: messageFieldCount,
      expectedMagic: messageMagic,
      expectedVersion: messageVersion,
      kind: 'damage transfer',
    );
    final int paneId = _positiveInt64(fields[2], 'pane ID');
    final int paneGeneration = _positiveInt64(fields[3], 'pane generation');
    final int damageGeneration = _positiveInt64(fields[4], 'damage generation');
    final int resourceGeneration = _positiveInt64(
      fields[5],
      'resource generation',
    );
    final int byteLength = _boundedInt(
      fields[6],
      'damage byte length',
      TerminalDamageCodec.headerBytes,
      maximumByteLength,
    );
    final int fullFlag = _boundedInt(fields[7], 'full-snapshot flag', 0, 1);
    final Object? payload = fields[8];
    if (payload is! TransferableTypedData) {
      throw const TerminalDamageProtocolException(
        'damage payload is not TransferableTypedData',
      );
    }
    return TerminalDamageTransferEnvelope._(
      sessionId: TerminalSessionId(
        paneId: PaneId(paneId),
        generation: paneGeneration,
      ),
      damageGeneration: damageGeneration,
      requiredResourceGeneration: resourceGeneration,
      byteLength: byteLength,
      isFullSnapshot: fullFlag == 1,
      payload: payload,
    );
  }

  /// Materializes once, then cross-checks envelope scalars against ADR-003.
  TerminalDecodedDamage materializeDamage({
    required TerminalSessionId expectedSessionId,
    TerminalDamageLimits limits = const TerminalDamageLimits(),
  }) {
    _validateSessionId(expectedSessionId, 'expectedSessionId');
    if (sessionId != expectedSessionId) {
      throw const TerminalDamageProtocolException(
        'damage transfer belongs to a different pane generation',
      );
    }
    if (_materialized) {
      throw StateError('damage transfer was already materialized');
    }
    if (_messageTaken) {
      throw StateError('sender-side damage transfer cannot be materialized');
    }
    _materialized = true;
    final Uint8List bytes = _payload.materialize().asUint8List();
    if (bytes.length != byteLength) {
      throw const TerminalDamageProtocolException(
        'damage payload length does not match its envelope',
      );
    }
    final TerminalDecodedDamage damage = TerminalDamageCodec.decode(
      bytes,
      expectedResourceGeneration: requiredResourceGeneration,
      limits: limits,
    );
    if (damage.damageGeneration != damageGeneration ||
        damage.requiredResourceGeneration != requiredResourceGeneration ||
        damage.isFullSnapshot != isFullSnapshot ||
        damage.byteLength != byteLength) {
      throw const TerminalDamageProtocolException(
        'damage envelope does not match its payload header',
      );
    }
    return damage;
  }
}

enum TerminalDamageAcknowledgementStatus { applied, rejected }

/// Strict scalar-only renderer acknowledgement suitable for a SendPort.
final class TerminalDamageAcknowledgement {
  TerminalDamageAcknowledgement._({
    required this.sessionId,
    required this.damageGeneration,
    required this.acceptedBytes,
    required this.status,
  });

  factory TerminalDamageAcknowledgement.applied({
    required TerminalSessionId sessionId,
    required int damageGeneration,
    required int acceptedBytes,
  }) {
    _validateSessionId(sessionId, 'sessionId');
    _requirePositiveInt64(damageGeneration, 'damageGeneration');
    RangeError.checkValueInInterval(
      acceptedBytes,
      TerminalDamageCodec.headerBytes,
      TerminalDamageTransferEnvelope.maximumByteLength,
      'acceptedBytes',
    );
    return TerminalDamageAcknowledgement._(
      sessionId: sessionId,
      damageGeneration: damageGeneration,
      acceptedBytes: acceptedBytes,
      status: TerminalDamageAcknowledgementStatus.applied,
    );
  }

  factory TerminalDamageAcknowledgement.rejected({
    required TerminalSessionId sessionId,
    required int damageGeneration,
  }) {
    _validateSessionId(sessionId, 'sessionId');
    _requirePositiveInt64(damageGeneration, 'damageGeneration');
    return TerminalDamageAcknowledgement._(
      sessionId: sessionId,
      damageGeneration: damageGeneration,
      acceptedBytes: 0,
      status: TerminalDamageAcknowledgementStatus.rejected,
    );
  }

  static const int messageMagic = 0x4b434144;
  static const int messageVersion = 1;
  static const int messageFieldCount = 7;

  final TerminalSessionId sessionId;
  final int damageGeneration;
  final int acceptedBytes;
  final TerminalDamageAcknowledgementStatus status;

  Object toMessage() => <Object?>[
    messageMagic,
    messageVersion,
    sessionId.paneId.value,
    sessionId.generation,
    damageGeneration,
    acceptedBytes,
    switch (status) {
      TerminalDamageAcknowledgementStatus.applied => 0,
      TerminalDamageAcknowledgementStatus.rejected => 1,
    },
  ];

  factory TerminalDamageAcknowledgement.decodeMessage(Object? message) {
    final List<Object?> fields = _messageFields(
      message,
      expectedCount: messageFieldCount,
      expectedMagic: messageMagic,
      expectedVersion: messageVersion,
      kind: 'damage acknowledgement',
    );
    final int paneId = _positiveInt64(fields[2], 'pane ID');
    final int paneGeneration = _positiveInt64(fields[3], 'pane generation');
    final int damageGeneration = _positiveInt64(fields[4], 'damage generation');
    final int acceptedBytes = _boundedInt(
      fields[5],
      'accepted byte count',
      0,
      TerminalDamageTransferEnvelope.maximumByteLength,
    );
    final int statusCode = _boundedInt(fields[6], 'ACK status', 0, 1);
    if ((statusCode == 0 && acceptedBytes < TerminalDamageCodec.headerBytes) ||
        (statusCode == 1 && acceptedBytes != 0)) {
      throw const TerminalDamageProtocolException(
        'ACK status and accepted byte count disagree',
      );
    }
    return TerminalDamageAcknowledgement._(
      sessionId: TerminalSessionId(
        paneId: PaneId(paneId),
        generation: paneGeneration,
      ),
      damageGeneration: damageGeneration,
      acceptedBytes: acceptedBytes,
      status: statusCode == 0
          ? TerminalDamageAcknowledgementStatus.applied
          : TerminalDamageAcknowledgementStatus.rejected,
    );
  }
}

enum TerminalDamageAckDisposition {
  accepted,
  malformed,
  wrongPane,
  stalePaneIgnored,
  futurePane,
  relationshipClosed,
  duplicate,
  staleDamage,
  futureDamage,
  wrongByteCount,
  rendererRejected,
}

final class TerminalDamageAckHandlingResult {
  const TerminalDamageAckHandlingResult({
    required this.disposition,
    required this.relationshipClosed,
  });

  final TerminalDamageAckDisposition disposition;
  final bool relationshipClosed;

  bool get isAccepted => disposition == TerminalDamageAckDisposition.accepted;
}

enum TerminalDamageOutboxCloseReason {
  portClosed,
  acknowledgementDeadlineExceeded,
  rendererRejected,
  generationExhausted,
}

/// Terminal-engine-side, constant-size owner of one unacknowledged transfer.
final class TerminalDamageOutbox {
  TerminalDamageOutbox({
    required TerminalSessionId sessionId,
    required TerminalScreen screen,
    this.limits = const TerminalDamageLimits(),
    int initialDamageGeneration = 0,
  }) : _sessionId = sessionId,
       _screen = screen,
       _nextDamageGeneration = initialDamageGeneration + 1,
       _lastAcknowledgedGeneration = initialDamageGeneration {
    _validateSessionId(sessionId, 'sessionId');
    limits.validate();
    RangeError.checkValueInInterval(
      initialDamageGeneration,
      0,
      0x7ffffffffffffffe,
      'initialDamageGeneration',
    );
  }

  TerminalSessionId _sessionId;
  TerminalScreen _screen;
  final TerminalDamageLimits limits;
  _OutstandingDamage? _outstanding;
  int _nextDamageGeneration;
  bool _damageGenerationExhausted = false;
  int _lastAcknowledgedGeneration;
  bool _isOpen = true;
  bool _rebuildPaused = false;
  TerminalDamageOutboxCloseReason? _lastCloseReason;
  int _publishedPacketCount = 0;
  int _acknowledgedPacketCount = 0;

  TerminalSessionId get sessionId => _sessionId;
  bool get isOpen => _isOpen;
  bool get isPausedForFullRebuild => _rebuildPaused;
  int get inFlightCount => _outstanding == null ? 0 : 1;
  int? get inFlightDamageGeneration => _outstanding?.damageGeneration;
  int get lastAcknowledgedGeneration => _lastAcknowledgedGeneration;
  int get publishedPacketCount => _publishedPacketCount;
  int get acknowledgedPacketCount => _acknowledgedPacketCount;
  TerminalDamageOutboxCloseReason? get lastCloseReason => _lastCloseReason;

  bool isBoundToScreen(TerminalScreen screen) => identical(_screen, screen);

  bool get hasPendingDamage {
    if (_screen.fullSnapshotRequired) return true;
    for (int row = 0; row < _screen.rows; row++) {
      if (_screen.isRowDirty(row)) return true;
    }
    return false;
  }

  TerminalDamageTransferEnvelope? tryCreateTransfer({
    required int requiredResourceGeneration,
  }) {
    if (!_isOpen) {
      throw StateError('damage relationship is closed');
    }
    _requirePositiveInt64(
      requiredResourceGeneration,
      'requiredResourceGeneration',
    );
    if (_rebuildPaused) return null;
    if (_outstanding != null) return null;
    if (_damageGenerationExhausted) {
      _terminate(TerminalDamageOutboxCloseReason.generationExhausted);
      throw StateError('damage generation capacity exhausted');
    }
    final TerminalDamagePacket? packet = TerminalDamageCodec.capture(
      _screen,
      damageGeneration: _nextDamageGeneration,
      requiredResourceGeneration: requiredResourceGeneration,
      limits: limits,
    );
    if (packet == null) return null;
    late final TransferableTypedData payload;
    try {
      payload = TransferableTypedData.fromList(<TypedData>[packet.copyBytes()]);
    } on Object {
      _screen.requestFullSnapshot();
      rethrow;
    }
    final _OutstandingDamage outstanding = _OutstandingDamage(
      damageGeneration: packet.damageGeneration,
      byteLength: packet.byteLength,
      isFullSnapshot: packet.isFullSnapshot,
      capturedScreen: _screen,
      fullSnapshotRequestEpoch: packet.isFullSnapshot
          ? _screen.fullSnapshotRequestEpoch
          : 0,
    );
    _outstanding = outstanding;
    if (_nextDamageGeneration == 0x7fffffffffffffff) {
      _damageGenerationExhausted = true;
    } else {
      _nextDamageGeneration++;
    }
    _publishedPacketCount++;
    return TerminalDamageTransferEnvelope._(
      sessionId: _sessionId,
      damageGeneration: packet.damageGeneration,
      requiredResourceGeneration: packet.requiredResourceGeneration,
      byteLength: packet.byteLength,
      isFullSnapshot: packet.isFullSnapshot,
      payload: payload,
    );
  }

  TerminalDamageAckHandlingResult acknowledgeMessage(Object? message) {
    late final TerminalDamageAcknowledgement acknowledgement;
    try {
      acknowledgement = TerminalDamageAcknowledgement.decodeMessage(message);
    } on TerminalDamageProtocolException {
      return _ackResult(TerminalDamageAckDisposition.malformed);
    }
    return acknowledge(acknowledgement);
  }

  TerminalDamageAckHandlingResult acknowledge(
    TerminalDamageAcknowledgement acknowledgement,
  ) {
    final TerminalSessionId incoming = acknowledgement.sessionId;
    if (incoming.paneId != _sessionId.paneId) {
      return _ackResult(TerminalDamageAckDisposition.wrongPane);
    }
    if (incoming.generation < _sessionId.generation) {
      return _ackResult(TerminalDamageAckDisposition.stalePaneIgnored);
    }
    if (incoming.generation > _sessionId.generation) {
      return _ackResult(TerminalDamageAckDisposition.futurePane);
    }
    if (!_isOpen) {
      return _ackResult(TerminalDamageAckDisposition.relationshipClosed);
    }
    final _OutstandingDamage? outstanding = _outstanding;
    if (outstanding == null) {
      if (acknowledgement.damageGeneration == _lastAcknowledgedGeneration) {
        return _ackResult(TerminalDamageAckDisposition.duplicate);
      }
      return _ackResult(
        acknowledgement.damageGeneration < _lastAcknowledgedGeneration
            ? TerminalDamageAckDisposition.staleDamage
            : TerminalDamageAckDisposition.futureDamage,
      );
    }
    if (acknowledgement.damageGeneration < outstanding.damageGeneration) {
      return _ackResult(
        acknowledgement.damageGeneration == _lastAcknowledgedGeneration
            ? TerminalDamageAckDisposition.duplicate
            : TerminalDamageAckDisposition.staleDamage,
      );
    }
    if (acknowledgement.damageGeneration > outstanding.damageGeneration) {
      return _ackResult(TerminalDamageAckDisposition.futureDamage);
    }
    if (acknowledgement.status ==
        TerminalDamageAcknowledgementStatus.rejected) {
      _terminate(TerminalDamageOutboxCloseReason.rendererRejected);
      return _ackResult(TerminalDamageAckDisposition.rendererRejected);
    }
    if (acknowledgement.acceptedBytes != outstanding.byteLength) {
      return _ackResult(TerminalDamageAckDisposition.wrongByteCount);
    }
    _outstanding = null;
    _lastAcknowledgedGeneration = acknowledgement.damageGeneration;
    _acknowledgedPacketCount++;
    if (outstanding.isFullSnapshot) {
      outstanding.capturedScreen.acknowledgeFullSnapshot(
        requestEpoch: outstanding.fullSnapshotRequestEpoch,
      );
    }
    return _ackResult(TerminalDamageAckDisposition.accepted);
  }

  /// Prevents new damage publication while render resources are rebuilding.
  ///
  /// An already published packet remains owned until its exact ACK arrives.
  void pauseForFullRebuild() {
    if (!_isOpen) {
      throw StateError('damage relationship is closed');
    }
    _rebuildPaused = true;
  }

  /// Publishes a rebuilt screen only after its matching resources are ready.
  ///
  /// An older in-flight packet retains its captured screen and exact snapshot
  /// epoch until ACK; later transfers use [replacement].
  void rebindScreenForFullRebuild(TerminalScreen replacement) {
    if (!_isOpen) {
      throw StateError('damage relationship is closed');
    }
    replacement.requestFullSnapshot();
    _screen = replacement;
    _rebuildPaused = false;
  }

  /// Ignores stale timer callbacks and closes only the exact in-flight packet.
  bool expireAcknowledgement({
    required TerminalSessionId sessionId,
    required int damageGeneration,
  }) {
    _validateSessionId(sessionId, 'sessionId');
    _requirePositiveInt64(damageGeneration, 'damageGeneration');
    if (!_isOpen || sessionId != _sessionId) return false;
    if (_outstanding?.damageGeneration != damageGeneration) return false;
    _terminate(TerminalDamageOutboxCloseReason.acknowledgementDeadlineExceeded);
    return true;
  }

  /// Ignores close callbacks from a retired pane generation.
  bool notifyPortClosed(TerminalSessionId sessionId) {
    _validateSessionId(sessionId, 'sessionId');
    if (!_isOpen || sessionId != _sessionId) return false;
    _terminate(TerminalDamageOutboxCloseReason.portClosed);
    return true;
  }

  /// Releases old bookkeeping and starts a full-resync relationship.
  void replacePaneGeneration(TerminalSessionId replacement) {
    _validateSessionId(replacement, 'replacement');
    if (replacement.paneId != _sessionId.paneId) {
      throw ArgumentError.value(
        replacement,
        'replacement',
        'must retain the logical pane ID',
      );
    }
    if (replacement.generation <= _sessionId.generation) {
      throw ArgumentError.value(
        replacement,
        'replacement',
        'must have a newer pane generation',
      );
    }
    _outstanding = null;
    _screen.requestFullSnapshot();
    _sessionId = replacement;
    _nextDamageGeneration = 1;
    _damageGenerationExhausted = false;
    _lastAcknowledgedGeneration = 0;
    _isOpen = true;
    _rebuildPaused = false;
    _lastCloseReason = null;
  }

  void _terminate(TerminalDamageOutboxCloseReason reason) {
    _outstanding = null;
    _isOpen = false;
    _rebuildPaused = false;
    _lastCloseReason = reason;
    _screen.requestFullSnapshot();
  }

  TerminalDamageAckHandlingResult _ackResult(
    TerminalDamageAckDisposition disposition,
  ) => TerminalDamageAckHandlingResult(
    disposition: disposition,
    relationshipClosed: !_isOpen,
  );
}

final class _OutstandingDamage {
  const _OutstandingDamage({
    required this.damageGeneration,
    required this.byteLength,
    required this.isFullSnapshot,
    required this.capturedScreen,
    required this.fullSnapshotRequestEpoch,
  });

  final int damageGeneration;
  final int byteLength;
  final bool isFullSnapshot;
  final TerminalScreen capturedScreen;
  final int fullSnapshotRequestEpoch;
}

List<Object?> _messageFields(
  Object? message, {
  required int expectedCount,
  required int expectedMagic,
  required int expectedVersion,
  required String kind,
}) {
  if (message is! List || message.length != expectedCount) {
    throw TerminalDamageProtocolException('invalid $kind field count');
  }
  final List<Object?> fields = List<Object?>.from(message);
  if (fields[0] != expectedMagic || fields[1] != expectedVersion) {
    throw TerminalDamageProtocolException('invalid $kind magic or version');
  }
  return fields;
}

int _positiveInt64(Object? value, String name) {
  if (value is! int || value <= 0 || value > 0x7fffffffffffffff) {
    throw TerminalDamageProtocolException('invalid $name');
  }
  return value;
}

int _boundedInt(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw TerminalDamageProtocolException('invalid $name');
  }
  return value;
}

void _validateSessionId(TerminalSessionId sessionId, String name) {
  if (sessionId.paneId.value <= 0 ||
      sessionId.paneId.value > 0x7fffffffffffffff ||
      sessionId.generation <= 0 ||
      sessionId.generation > 0x7fffffffffffffff) {
    throw ArgumentError.value(sessionId, name, 'contains an invalid scalar');
  }
}

void _requirePositiveInt64(int value, String name) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    throw RangeError.range(value, 1, 0x7fffffffffffffff, name);
  }
}
