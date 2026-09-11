import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'terminal_config.dart';
import 'terminal_core/terminal_osc52.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_pane.dart';

final class TerminalOsc52ClipboardText {
  const TerminalOsc52ClipboardText({
    required this.text,
    required this.changeCount,
  });

  final String? text;
  final int changeCount;
}

/// Application-owned plain-text clipboard capability used by OSC 52 policy.
abstract interface class TerminalOsc52ClipboardPort {
  TerminalOsc52ClipboardText readText();
  int get changeCount;
  int writeText(String text);
  int clear();
}

enum TerminalOsc52ConfirmationDisposition {
  approved,
  denied,
  stale,
  failed,
  missing,
}

final class TerminalOsc52PendingRequest {
  const TerminalOsc52PendingRequest._({
    required this.id,
    required this.sessionId,
    required this.resetGeneration,
    required this.request,
    required this.writeText,
    required this.writeUtf8Bytes,
    required this.pasteboardChangeCount,
    required this.issuedMicros,
    required this.expiresMicros,
  });

  final int id;
  final TerminalSessionId sessionId;
  final int resetGeneration;
  final TerminalOsc52Request request;
  final String? writeText;
  final int writeUtf8Bytes;
  final int? pasteboardChangeCount;
  final int issuedMicros;
  final int expiresMicros;
}

final class TerminalOsc52ProjectionMetrics {
  const TerminalOsc52ProjectionMetrics({
    required this.pendingRequestCount,
    required this.approvedRequestCount,
    required this.deniedRequestCount,
    required this.busyRequestCount,
    required this.staleRequestCount,
    required this.invalidTextRequestCount,
    required this.clipboardFailureCount,
    required this.replyFailureCount,
    required this.trackedSessionCount,
  });

  final int pendingRequestCount;
  final int approvedRequestCount;
  final int deniedRequestCount;
  final int busyRequestCount;
  final int staleRequestCount;
  final int invalidTextRequestCount;
  final int clipboardFailureCount;
  final int replyFailureCount;
  final int trackedSessionCount;
}

typedef TerminalOsc52PendingObserver = void Function(
  TerminalOsc52PendingRequest? pending,
);

final class TerminalOsc52SessionProjection {
  TerminalOsc52SessionProjection._({
    required TerminalOsc52Coordinator owner,
    required this.sessionId,
    required this.readPolicy,
    required this.writePolicy,
    required TerminalReplyHandler onReply,
    required int resetGeneration,
  }) : _owner = owner,
       _onReply = onReply,
       _resetGeneration = resetGeneration;

  final TerminalOsc52Coordinator _owner;
  final TerminalSessionId sessionId;
  final TerminalConfiguredClipboardAccess readPolicy;
  final TerminalConfiguredClipboardAccess writePolicy;
  final TerminalReplyHandler _onReply;
  int _resetGeneration;
  bool _closed = false;

  bool get isClosed => _closed;
  int get resetGeneration => _resetGeneration;

  bool handle(TerminalOsc52Request request) => _owner._handle(this, request);

  void synchronize(int resetGeneration) =>
      _owner._synchronize(this, resetGeneration);

  void close() => _owner._closeSession(this);
}

/// Global, bounded owner for OSC 52 clipboard authority and confirmation.
final class TerminalOsc52Coordinator {
  factory TerminalOsc52Coordinator({
    required TerminalOsc52ClipboardPort clipboard,
    TerminalOsc52PendingObserver? onPendingChanged,
    int Function()? monotonicMicros,
    Duration confirmationTimeout = defaultConfirmationTimeout,
    bool applicationActive = false,
  }) {
    final Stopwatch clock = Stopwatch()..start();
    return TerminalOsc52Coordinator._(
      clipboard: clipboard,
      onPendingChanged: onPendingChanged,
      monotonicMicros: monotonicMicros ?? () => clock.elapsedMicroseconds,
      confirmationTimeout: confirmationTimeout,
      applicationActive: applicationActive,
    );
  }

  TerminalOsc52Coordinator._({
    required TerminalOsc52ClipboardPort clipboard,
    required TerminalOsc52PendingObserver? onPendingChanged,
    required int Function() monotonicMicros,
    required this.confirmationTimeout,
    required bool applicationActive,
  }) : _clipboard = clipboard,
       _onPendingChanged = onPendingChanged,
       _monotonicMicros = monotonicMicros,
       _applicationActive = applicationActive {
    if (confirmationTimeout < minimumConfirmationTimeout ||
        confirmationTimeout > maximumConfirmationTimeout) {
      throw RangeError.range(
        confirmationTimeout.inMicroseconds,
        minimumConfirmationTimeout.inMicroseconds,
        maximumConfirmationTimeout.inMicroseconds,
        'confirmationTimeout.inMicroseconds',
      );
    }
  }

  static const Duration defaultConfirmationTimeout = Duration(seconds: 30);
  static const Duration minimumConfirmationTimeout = Duration(seconds: 1);
  static const Duration maximumConfirmationTimeout = Duration(minutes: 5);
  static const int maximumTrackedSessions = 64;
  static const int _maximumMetric = 0x7fffffff;
  static const int _maximumIdentity = 0x7fffffff;

  final TerminalOsc52ClipboardPort _clipboard;
  final TerminalOsc52PendingObserver? _onPendingChanged;
  final int Function() _monotonicMicros;
  final Duration confirmationTimeout;
  final LinkedHashMap<TerminalSessionId, TerminalOsc52SessionProjection>
  _sessions =
      LinkedHashMap<TerminalSessionId, TerminalOsc52SessionProjection>();

  TerminalSessionId? _focusedSessionId;
  TerminalOsc52PendingRequest? _pending;
  Timer? _pendingTimer;
  bool _applicationActive;
  bool _disposed = false;
  int _nextRequestId = 1;
  int _lastMicros = 0;
  int _pendingRequestCount = 0;
  int _approvedRequestCount = 0;
  int _deniedRequestCount = 0;
  int _busyRequestCount = 0;
  int _staleRequestCount = 0;
  int _invalidTextRequestCount = 0;
  int _clipboardFailureCount = 0;
  int _replyFailureCount = 0;

  bool get isDisposed => _disposed;
  TerminalSessionId? get focusedSessionId => _focusedSessionId;
  TerminalOsc52PendingRequest? get pendingRequest => _pending;

  TerminalOsc52ProjectionMetrics get metrics => TerminalOsc52ProjectionMetrics(
    pendingRequestCount: _pendingRequestCount,
    approvedRequestCount: _approvedRequestCount,
    deniedRequestCount: _deniedRequestCount,
    busyRequestCount: _busyRequestCount,
    staleRequestCount: _staleRequestCount,
    invalidTextRequestCount: _invalidTextRequestCount,
    clipboardFailureCount: _clipboardFailureCount,
    replyFailureCount: _replyFailureCount,
    trackedSessionCount: _sessions.length,
  );

  TerminalOsc52SessionProjection registerSession({
    required TerminalSessionId sessionId,
    required TerminalConfiguredClipboardAccess readPolicy,
    required TerminalConfiguredClipboardAccess writePolicy,
    required TerminalReplyHandler onReply,
    int resetGeneration = 1,
  }) {
    if (_disposed) throw StateError('OSC 52 coordinator is disposed');
    if (resetGeneration <= 0) {
      throw ArgumentError.value(resetGeneration, 'resetGeneration');
    }
    if (_sessions.containsKey(sessionId)) {
      throw StateError('OSC 52 session $sessionId is already registered');
    }
    if (_sessions.length >= maximumTrackedSessions) {
      throw StateError('OSC 52 tracked-session limit is exhausted');
    }
    final TerminalOsc52SessionProjection projection =
        TerminalOsc52SessionProjection._(
          owner: this,
          sessionId: sessionId,
          readPolicy: readPolicy,
          writePolicy: writePolicy,
          onReply: onReply,
          resetGeneration: resetGeneration,
        );
    _sessions[sessionId] = projection;
    return projection;
  }

  void focusSession(TerminalSessionId? sessionId) {
    if (_disposed || _focusedSessionId == sessionId) return;
    _focusedSessionId = sessionId;
    final TerminalOsc52PendingRequest? pending = _pending;
    if (pending != null && pending.sessionId != sessionId) {
      _cancelPending(pending);
    }
  }

  void setApplicationActive(bool active) {
    if (_disposed || _applicationActive == active) return;
    _applicationActive = active;
    final TerminalOsc52PendingRequest? pending = _pending;
    if (!active && pending != null) _cancelPending(pending);
  }

  TerminalOsc52ConfirmationDisposition approve(int requestId) {
    final TerminalOsc52PendingRequest? pending = _matchingPending(requestId);
    if (pending == null) return TerminalOsc52ConfirmationDisposition.missing;
    final TerminalOsc52SessionProjection? projection =
        _sessions[pending.sessionId];
    if (projection == null ||
        projection._closed ||
        projection._resetGeneration != pending.resetGeneration ||
        _focusedSessionId != pending.sessionId ||
        !_applicationActive) {
      _staleRequestCount = _increment(_staleRequestCount);
      _cancelPending(pending);
      return TerminalOsc52ConfirmationDisposition.stale;
    }
    if (pending.pasteboardChangeCount != null) {
      try {
        if (_clipboard.changeCount != pending.pasteboardChangeCount) {
          _staleRequestCount = _increment(_staleRequestCount);
          _cancelPending(pending);
          return TerminalOsc52ConfirmationDisposition.stale;
        }
      } on Object {
        _clipboardFailureCount = _increment(_clipboardFailureCount);
        _cancelPending(pending);
        return TerminalOsc52ConfirmationDisposition.failed;
      }
    }
    _clearPending(pending);
    final bool completed = _execute(
      projection,
      pending.request,
      decodedWriteText: pending.writeText,
    );
    if (completed) {
      _approvedRequestCount = _increment(_approvedRequestCount);
      return TerminalOsc52ConfirmationDisposition.approved;
    }
    if (pending.request.operation == TerminalOsc52Operation.read) {
      _replyUnavailable(projection, pending.request);
    }
    return TerminalOsc52ConfirmationDisposition.failed;
  }

  TerminalOsc52ConfirmationDisposition deny(int requestId) {
    final TerminalOsc52PendingRequest? pending = _matchingPending(requestId);
    if (pending == null) return TerminalOsc52ConfirmationDisposition.missing;
    _cancelPending(pending);
    return TerminalOsc52ConfirmationDisposition.denied;
  }

  /// Deterministic test/diagnostic path shared by the one-shot timer.
  bool expirePending({int? nowMicros}) {
    final TerminalOsc52PendingRequest? pending = _pending;
    if (pending == null) return false;
    if ((nowMicros ?? _nowMicros()) < pending.expiresMicros) return false;
    _cancelPending(pending);
    return true;
  }

  void dispose() {
    if (_disposed) return;
    final TerminalOsc52PendingRequest? pending = _pending;
    if (pending != null) _cancelPending(pending);
    for (final TerminalOsc52SessionProjection projection
        in _sessions.values.toList(growable: false)) {
      projection._closed = true;
    }
    _sessions.clear();
    _focusedSessionId = null;
    _disposed = true;
  }

  bool _handle(
    TerminalOsc52SessionProjection projection,
    TerminalOsc52Request request,
  ) {
    if (_disposed ||
        projection._closed ||
        !identical(_sessions[projection.sessionId], projection) ||
        !_applicationActive ||
        _focusedSessionId != projection.sessionId ||
        !request.targetsClipboard) {
      return false;
    }
    final TerminalConfiguredClipboardAccess policy =
        request.operation == TerminalOsc52Operation.read
        ? projection.readPolicy
        : projection.writePolicy;
    switch (policy) {
      case TerminalConfiguredClipboardAccess.deny:
        return false;
      case TerminalConfiguredClipboardAccess.allow:
        return _execute(projection, request);
      case TerminalConfiguredClipboardAccess.ask:
        return _ask(projection, request);
    }
  }

  bool _ask(
    TerminalOsc52SessionProjection projection,
    TerminalOsc52Request request,
  ) {
    if (_pending != null) {
      _busyRequestCount = _increment(_busyRequestCount);
      return false;
    }
    String? decodedWriteText;
    var writeUtf8Bytes = 0;
    int? pasteboardChangeCount;
    if (request.operation == TerminalOsc52Operation.write) {
      decodedWriteText = _decodeWrite(request);
      if (decodedWriteText == null) return false;
      writeUtf8Bytes = utf8.encode(decodedWriteText).length;
    }
    if (request.operation != TerminalOsc52Operation.read) {
      try {
        pasteboardChangeCount = _clipboard.changeCount;
      } on Object {
        _clipboardFailureCount = _increment(_clipboardFailureCount);
        return false;
      }
    }
    final int issuedMicros = _nowMicros();
    final int id = _takeRequestId();
    final TerminalOsc52PendingRequest pending = TerminalOsc52PendingRequest._(
      id: id,
      sessionId: projection.sessionId,
      resetGeneration: projection._resetGeneration,
      request: request,
      writeText: decodedWriteText,
      writeUtf8Bytes: writeUtf8Bytes,
      pasteboardChangeCount: pasteboardChangeCount,
      issuedMicros: issuedMicros,
      expiresMicros: issuedMicros + confirmationTimeout.inMicroseconds,
    );
    _pending = pending;
    _pendingRequestCount = _increment(_pendingRequestCount);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(confirmationTimeout, () {
      final TerminalOsc52PendingRequest? current = _pending;
      if (current != null && current.id == id) {
        expirePending(nowMicros: current.expiresMicros);
      }
    });
    _notifyPendingChanged(pending);
    return true;
  }

  bool _execute(
    TerminalOsc52SessionProjection projection,
    TerminalOsc52Request request, {
    String? decodedWriteText,
  }) {
    try {
      switch (request.operation) {
        case TerminalOsc52Operation.read:
          final TerminalOsc52ClipboardText snapshot = _clipboard.readText();
          final String? text = snapshot.text;
          if (text == null ||
              utf8.encode(text).length >
                  TerminalOsc52Protocol.maximumClipboardTextUtf8Bytes) {
            return false;
          }
          return _reply(
            projection,
            TerminalOsc52Protocol.encodeReadReply(request, text),
          );
        case TerminalOsc52Operation.write:
          final String? text = decodedWriteText ?? _decodeWrite(request);
          if (text == null) return false;
          _clipboard.writeText(text);
          return true;
        case TerminalOsc52Operation.clear:
          _clipboard.clear();
          return true;
      }
    } on Object {
      _clipboardFailureCount = _increment(_clipboardFailureCount);
      return false;
    }
  }

  String? _decodeWrite(TerminalOsc52Request request) {
    final String? encoded = request.encodedData;
    if (encoded == null) return null;
    try {
      final Uint8List bytes = base64Decode(encoded);
      if (bytes.length > TerminalOsc52Protocol.maximumClipboardTextUtf8Bytes) {
        _invalidTextRequestCount = _increment(_invalidTextRequestCount);
        return null;
      }
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      _invalidTextRequestCount = _increment(_invalidTextRequestCount);
      return null;
    }
  }

  void _synchronize(
    TerminalOsc52SessionProjection projection,
    int resetGeneration,
  ) {
    if (_disposed || projection._closed) return;
    if (resetGeneration < projection._resetGeneration || resetGeneration <= 0) {
      throw ArgumentError.value(resetGeneration, 'resetGeneration');
    }
    if (resetGeneration == projection._resetGeneration) return;
    projection._resetGeneration = resetGeneration;
    final TerminalOsc52PendingRequest? pending = _pending;
    if (pending?.sessionId == projection.sessionId) _cancelPending(pending!);
  }

  void _closeSession(TerminalOsc52SessionProjection projection) {
    if (projection._closed) return;
    projection._closed = true;
    if (identical(_sessions[projection.sessionId], projection)) {
      _sessions.remove(projection.sessionId);
    }
    final TerminalOsc52PendingRequest? pending = _pending;
    if (pending?.sessionId == projection.sessionId) _cancelPending(pending!);
    if (_focusedSessionId == projection.sessionId) _focusedSessionId = null;
  }

  void _cancelPending(TerminalOsc52PendingRequest pending) {
    if (!identical(_pending, pending)) return;
    final TerminalOsc52SessionProjection? projection =
        _sessions[pending.sessionId];
    _clearPending(pending);
    _deniedRequestCount = _increment(_deniedRequestCount);
    if (projection != null &&
        !projection._closed &&
        pending.request.operation == TerminalOsc52Operation.read) {
      _replyUnavailable(projection, pending.request);
    }
  }

  void _clearPending(TerminalOsc52PendingRequest pending) {
    if (!identical(_pending, pending)) return;
    _pending = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _notifyPendingChanged(null);
  }

  void _replyUnavailable(
    TerminalOsc52SessionProjection projection,
    TerminalOsc52Request request,
  ) {
    _reply(
      projection,
      TerminalReplyEncoder.clipboardUnavailable(
        selection: request.selection.codeUnits,
        terminator: request.terminator,
      ),
    );
  }

  bool _reply(TerminalOsc52SessionProjection projection, Uint8List reply) {
    try {
      if (projection._onReply(reply)) return true;
    } on Object {
      // Reply delivery is fail-closed and cannot restore clipboard authority.
    }
    _replyFailureCount = _increment(_replyFailureCount);
    return false;
  }

  TerminalOsc52PendingRequest? _matchingPending(int requestId) {
    if (_disposed || requestId <= 0) return null;
    final TerminalOsc52PendingRequest? pending = _pending;
    return pending?.id == requestId ? pending : null;
  }

  int _nowMicros() {
    final int observed = _monotonicMicros();
    if (observed < _lastMicros) return _lastMicros;
    _lastMicros = observed;
    return observed;
  }

  int _takeRequestId() {
    final int result = _nextRequestId;
    _nextRequestId = result == _maximumIdentity ? 1 : result + 1;
    return result;
  }

  void _notifyPendingChanged(TerminalOsc52PendingRequest? pending) {
    try {
      _onPendingChanged?.call(pending);
    } on Object {
      // UI observation cannot change policy state.
    }
  }

  static int _increment(int value) =>
      value == _maximumMetric ? value : value + 1;
}
