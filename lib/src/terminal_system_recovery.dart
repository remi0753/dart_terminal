import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

typedef TerminalSystemRecoverySchedule = void Function(void Function() work);
typedef TerminalSystemRecoveryError = void Function(
  Object error,
  StackTrace stackTrace,
);

enum TerminalSystemRecoveryEventDisposition {
  accepted,
  coalesced,
  stale,
  unhandled,
  disposed,
}

/// Content-free, constant-space diagnostic state for system recovery policy.
final class TerminalSystemRecoverySnapshot {
  const TerminalSystemRecoverySnapshot({
    required this.isDisposed,
    required this.isSleeping,
    required this.isPresentationSuspended,
    required this.hasScheduledDrain,
    required this.hasPendingScreenRecovery,
    required this.acceptedEventCount,
    required this.coalescedEventCount,
    required this.staleEventCount,
    required this.drainCount,
    required this.suspendCount,
    required this.displayRecoveryCount,
    required this.resumeCount,
  });

  final bool isDisposed;
  final bool isSleeping;
  final bool isPresentationSuspended;
  final bool hasScheduledDrain;
  final bool hasPendingScreenRecovery;
  final int acceptedEventCount;
  final int coalescedEventCount;
  final int staleEventCount;
  final int drainCount;
  final int suspendCount;
  final int displayRecoveryCount;
  final int resumeCount;
}

/// Coalesces generic AppKit power/screen signals into product-owned work.
///
/// Native callbacks only set bounded scalar state and schedule one later Dart
/// turn. The injected callbacks own all terminal-specific policy and resources.
final class TerminalSystemRecoveryController {
  TerminalSystemRecoveryController({
    required void Function() suspendPresentation,
    required void Function() recoverDisplays,
    required void Function() resumePresentation,
    TerminalSystemRecoverySchedule schedule = scheduleMicrotask,
    TerminalSystemRecoveryError? onError,
  }) : _suspendPresentation = suspendPresentation,
       _recoverDisplays = recoverDisplays,
       _resumePresentation = resumePresentation,
       _schedule = schedule,
       _onError = onError;

  static const int maximumCounterValue = 0x7fffffffffffffff;

  final void Function() _suspendPresentation;
  final void Function() _recoverDisplays;
  final void Function() _resumePresentation;
  final TerminalSystemRecoverySchedule _schedule;
  final TerminalSystemRecoveryError? _onError;

  bool _isSleeping = false;
  bool _isPresentationSuspended = false;
  bool _pendingSuspend = false;
  bool _pendingWake = false;
  bool _pendingScreenRecovery = false;
  bool _scheduled = false;
  bool _disposed = false;
  int _lastPowerMicros = -1;
  int _lastScreenMicros = -1;
  int _acceptedEventCount = 0;
  int _coalescedEventCount = 0;
  int _staleEventCount = 0;
  int _drainCount = 0;
  int _suspendCount = 0;
  int _displayRecoveryCount = 0;
  int _resumeCount = 0;

  bool get isDisposed => _disposed;

  TerminalSystemRecoveryEventDisposition handle(AppKitEvent event) {
    if (_disposed) return TerminalSystemRecoveryEventDisposition.disposed;
    if (event case ApplicationPowerStateChangedEvent(
      :final state,
      :final monotonicMicros,
    )) {
      if (monotonicMicros <= _lastPowerMicros) {
        _staleEventCount = _increment(_staleEventCount);
        return TerminalSystemRecoveryEventDisposition.stale;
      }
      _lastPowerMicros = monotonicMicros;
      switch (state) {
        case AppKitApplicationPowerState.willSleep:
          if (_isSleeping) return _coalesced();
          _isSleeping = true;
          _pendingSuspend = true;
          _pendingWake = false;
        case AppKitApplicationPowerState.didWake:
          if (!_isSleeping && !_pendingSuspend) return _coalesced();
          _isSleeping = false;
          _pendingWake = true;
      }
      _acceptedEventCount = _increment(_acceptedEventCount);
      _scheduleDrain();
      return TerminalSystemRecoveryEventDisposition.accepted;
    }
    if (event case ApplicationScreenSetChangedEvent(:final monotonicMicros)) {
      if (monotonicMicros <= _lastScreenMicros) {
        _staleEventCount = _increment(_staleEventCount);
        return TerminalSystemRecoveryEventDisposition.stale;
      }
      _lastScreenMicros = monotonicMicros;
      if (_pendingScreenRecovery) return _coalesced();
      _pendingScreenRecovery = true;
      _acceptedEventCount = _increment(_acceptedEventCount);
      _scheduleDrain();
      return TerminalSystemRecoveryEventDisposition.accepted;
    }
    return TerminalSystemRecoveryEventDisposition.unhandled;
  }

  TerminalSystemRecoverySnapshot snapshot() => TerminalSystemRecoverySnapshot(
    isDisposed: _disposed,
    isSleeping: _isSleeping,
    isPresentationSuspended: _isPresentationSuspended,
    hasScheduledDrain: _scheduled,
    hasPendingScreenRecovery: _pendingScreenRecovery,
    acceptedEventCount: _acceptedEventCount,
    coalescedEventCount: _coalescedEventCount,
    staleEventCount: _staleEventCount,
    drainCount: _drainCount,
    suspendCount: _suspendCount,
    displayRecoveryCount: _displayRecoveryCount,
    resumeCount: _resumeCount,
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduled = false;
    _pendingSuspend = false;
    _pendingWake = false;
    _pendingScreenRecovery = false;
  }

  TerminalSystemRecoveryEventDisposition _coalesced() {
    _coalescedEventCount = _increment(_coalescedEventCount);
    return TerminalSystemRecoveryEventDisposition.coalesced;
  }

  void _scheduleDrain() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    _schedule(_runScheduled);
  }

  void _runScheduled() {
    if (_disposed) return;
    _scheduled = false;
    try {
      _drain();
    } on Object catch (error, stackTrace) {
      final TerminalSystemRecoveryError? handler = _onError;
      if (handler == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      handler(error, stackTrace);
    }
  }

  void _drain() {
    _drainCount = _increment(_drainCount);
    if (_pendingSuspend) {
      _pendingSuspend = false;
      if (!_isPresentationSuspended) {
        _suspendPresentation();
        _isPresentationSuspended = true;
        _suspendCount = _increment(_suspendCount);
      }
    }
    if (_isSleeping) return;

    final bool recoverAfterWake = _pendingWake;
    if (recoverAfterWake || _pendingScreenRecovery) {
      _pendingWake = false;
      _pendingScreenRecovery = false;
      _recoverDisplays();
      _displayRecoveryCount = _increment(_displayRecoveryCount);
    }
    if (recoverAfterWake && _isPresentationSuspended) {
      _resumePresentation();
      _isPresentationSuspended = false;
      _resumeCount = _increment(_resumeCount);
    }
  }

  static int _increment(int value) =>
      value == maximumCounterValue ? maximumCounterValue : value + 1;
}
