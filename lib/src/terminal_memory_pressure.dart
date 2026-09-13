import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

typedef TerminalMemoryPressureSchedule = void Function(void Function() work);
typedef TerminalMemoryPressureApply = void Function(
  AppKitMemoryPressureLevel level,
);
typedef TerminalMemoryPressureError = void Function(
  Object error,
  StackTrace stackTrace,
);

enum TerminalMemoryPressureEventDisposition {
  accepted,
  coalesced,
  stale,
  unhandled,
  disposed,
}

/// Content-free, constant-space diagnostic state for product pressure policy.
final class TerminalMemoryPressureSnapshot {
  const TerminalMemoryPressureSnapshot({
    required this.isDisposed,
    required this.observedLevel,
    required this.pendingLevel,
    required this.hasScheduledDrain,
    required this.acceptedEventCount,
    required this.coalescedEventCount,
    required this.staleEventCount,
    required this.drainCount,
    required this.applicationCount,
    required this.recoveryCount,
    required this.failureCount,
    required this.exhaustedCount,
  });

  final bool isDisposed;
  final AppKitMemoryPressureLevel observedLevel;
  final AppKitMemoryPressureLevel? pendingLevel;
  final bool hasScheduledDrain;
  final int acceptedEventCount;
  final int coalescedEventCount;
  final int staleEventCount;
  final int drainCount;
  final int applicationCount;
  final int recoveryCount;
  final int failureCount;
  final int exhaustedCount;
}

/// Coalesces generic memory-pressure signals into product-owned cache work.
///
/// Event delivery only updates bounded scalar state and schedules one later
/// Dart turn. A same-turn storm retains its highest severity. Callback failure
/// has a fixed retry budget and never grows an error or event queue.
final class TerminalMemoryPressureController {
  TerminalMemoryPressureController({
    required TerminalMemoryPressureApply apply,
    TerminalMemoryPressureSchedule schedule = scheduleMicrotask,
    TerminalMemoryPressureError? onError,
    this.maximumAttempts = 3,
  }) : _apply = apply,
       _schedule = schedule,
       _onError = onError {
    RangeError.checkValueInInterval(maximumAttempts, 1, 16, 'maximumAttempts');
  }

  static const int maximumCounterValue = 0x7fffffffffffffff;

  final TerminalMemoryPressureApply _apply;
  final TerminalMemoryPressureSchedule _schedule;
  final TerminalMemoryPressureError? _onError;
  final int maximumAttempts;

  AppKitMemoryPressureLevel _observedLevel = AppKitMemoryPressureLevel.normal;
  AppKitMemoryPressureLevel? _pendingLevel;
  int _episodeSeverity = 0;
  int _pendingAttemptCount = 0;
  bool _scheduled = false;
  bool _disposed = false;
  int _lastMonotonicMicros = -1;
  int _acceptedEventCount = 0;
  int _coalescedEventCount = 0;
  int _staleEventCount = 0;
  int _drainCount = 0;
  int _applicationCount = 0;
  int _recoveryCount = 0;
  int _failureCount = 0;
  int _exhaustedCount = 0;

  bool get isDisposed => _disposed;

  TerminalMemoryPressureEventDisposition handle(AppKitEvent event) {
    if (_disposed) return TerminalMemoryPressureEventDisposition.disposed;
    if (event case ApplicationMemoryPressureChangedEvent(
      :final level,
      :final monotonicMicros,
    )) {
      if (monotonicMicros <= _lastMonotonicMicros) {
        _staleEventCount = _increment(_staleEventCount);
        return TerminalMemoryPressureEventDisposition.stale;
      }
      _lastMonotonicMicros = monotonicMicros;
      _observedLevel = level;
      final int severity = _severity(level);
      if (severity == 0) {
        if (_episodeSeverity == 0) return _coalesced();
        _episodeSeverity = 0;
        _acceptedEventCount = _increment(_acceptedEventCount);
        _recoveryCount = _increment(_recoveryCount);
        return TerminalMemoryPressureEventDisposition.accepted;
      }
      if (severity <= _episodeSeverity) return _coalesced();
      _episodeSeverity = severity;
      final AppKitMemoryPressureLevel? pending = _pendingLevel;
      if (pending == null || severity > _severity(pending)) {
        _pendingLevel = level;
        _pendingAttemptCount = 0;
      }
      _acceptedEventCount = _increment(_acceptedEventCount);
      _scheduleDrain();
      return TerminalMemoryPressureEventDisposition.accepted;
    }
    return TerminalMemoryPressureEventDisposition.unhandled;
  }

  TerminalMemoryPressureSnapshot snapshot() => TerminalMemoryPressureSnapshot(
    isDisposed: _disposed,
    observedLevel: _observedLevel,
    pendingLevel: _pendingLevel,
    hasScheduledDrain: _scheduled,
    acceptedEventCount: _acceptedEventCount,
    coalescedEventCount: _coalescedEventCount,
    staleEventCount: _staleEventCount,
    drainCount: _drainCount,
    applicationCount: _applicationCount,
    recoveryCount: _recoveryCount,
    failureCount: _failureCount,
    exhaustedCount: _exhaustedCount,
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduled = false;
    _pendingLevel = null;
    _pendingAttemptCount = 0;
  }

  TerminalMemoryPressureEventDisposition _coalesced() {
    _coalescedEventCount = _increment(_coalescedEventCount);
    return TerminalMemoryPressureEventDisposition.coalesced;
  }

  void _scheduleDrain() {
    if (_scheduled || _disposed || _pendingLevel == null) return;
    _scheduled = true;
    _schedule(_runScheduled);
  }

  void _runScheduled() {
    if (_disposed) return;
    _scheduled = false;
    final AppKitMemoryPressureLevel? pending = _pendingLevel;
    if (pending == null) return;
    _drainCount = _increment(_drainCount);
    _pendingAttemptCount++;
    try {
      _apply(pending);
      _pendingLevel = null;
      _pendingAttemptCount = 0;
      _applicationCount = _increment(_applicationCount);
    } on Object catch (error, stackTrace) {
      _failureCount = _increment(_failureCount);
      if (_pendingAttemptCount < maximumAttempts) {
        _scheduleDrain();
        return;
      }
      _pendingLevel = null;
      _pendingAttemptCount = 0;
      _exhaustedCount = _increment(_exhaustedCount);
      final TerminalMemoryPressureError? handler = _onError;
      if (handler == null) Error.throwWithStackTrace(error, stackTrace);
      handler(error, stackTrace);
    }
  }

  static int _severity(AppKitMemoryPressureLevel level) => switch (level) {
    AppKitMemoryPressureLevel.normal => 0,
    AppKitMemoryPressureLevel.warning => 1,
    AppKitMemoryPressureLevel.critical => 2,
  };

  static int _increment(int value) =>
      value == maximumCounterValue ? maximumCounterValue : value + 1;
}
