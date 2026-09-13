import 'dart:async';

import 'package:dart_terminal_app_intents_macos/dart_terminal_app_intents_macos.dart';

import 'terminal_action_registry.dart';
import 'terminal_localization.dart';

typedef TerminalAppIntentActionDispatch =
    Future<TerminalActionDispatchResult> Function(TerminalActionId action);
typedef TerminalAppIntentsProductStatusObserver = void Function();
typedef TerminalAppIntentsProductErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);

enum TerminalAppIntentsProductFailure {
  none,
  unavailable,
  busy,
  actionFailed,
  nativeRejected,
  timedOut,
  nativeFailure,
}

/// Content-free status shown by Settings and deterministic acceptance tests.
final class TerminalAppIntentsProductStatus {
  const TerminalAppIntentsProductStatus({
    required this.enabled,
    required this.polling,
    required this.pendingCommandCount,
    required this.disposed,
    required this.completedCommandCount,
    required this.rejectedCommandCount,
    required this.failedCommandCount,
    required this.lastFailure,
  });

  final bool enabled;
  final bool polling;
  final int pendingCommandCount;
  final bool disposed;
  final int completedCommandCount;
  final int rejectedCommandCount;
  final int failedCommandCount;
  final TerminalAppIntentsProductFailure lastFailure;

  String get settingsLine => settingsLineFor(TerminalLocalization.english);

  String settingsLineFor(TerminalLocalization localization) {
    final String availability = disposed
        ? 'stopped'
        : enabled
        ? 'ready'
        : 'disabled';
    return localization.appIntentsStatus(
      enabled: enabled,
      availability: availability,
      pending: pendingCommandCount,
      completed: completedCommandCount,
      rejected: rejectedCommandCount,
      failed: failedCommandCount,
      last: lastFailure.name,
    );
  }
}

/// Drains the native bounded queue into the existing product action authority.
final class TerminalAppIntentsProductController {
  TerminalAppIntentsProductController({
    required TerminalAppIntentsMacosSession session,
    required TerminalAppIntentActionDispatch dispatch,
    this.onStatusChanged,
    this.onError,
  }) : _session = session,
       _dispatch = dispatch;

  static const int _maximumCounter = 0x7fffffff;
  static const Duration productPollInterval = Duration(milliseconds: 250);

  final TerminalAppIntentsMacosSession _session;
  final TerminalAppIntentActionDispatch _dispatch;
  final TerminalAppIntentsProductStatusObserver? onStatusChanged;
  final TerminalAppIntentsProductErrorObserver? onError;

  Future<void>? _activePoll;
  bool _enabled = false;
  bool _polling = false;
  bool _disposing = false;
  bool _disposed = false;
  int _completedCommandCount = 0;
  int _rejectedCommandCount = 0;
  int _failedCommandCount = 0;
  int _pendingCommandCount = 0;
  int _nativeRejectedCommandCount = 0;
  int _nativeTimedOutCommandCount = 0;
  TerminalAppIntentsProductFailure _lastFailure =
      TerminalAppIntentsProductFailure.none;

  bool get isDisposed => _disposed;

  TerminalAppIntentsProductStatus get status => TerminalAppIntentsProductStatus(
    enabled: _enabled,
    polling: _polling,
    pendingCommandCount: _pendingCommandCount,
    disposed: _disposed,
    completedCommandCount: _completedCommandCount,
    rejectedCommandCount: _rejectedCommandCount,
    failedCommandCount: _failedCommandCount,
    lastFailure: _lastFailure,
  );

  void applyEnabled(bool enabled) {
    _ensureMutable();
    if (_enabled == enabled) return;
    try {
      _session.setEnabled(enabled);
      _enabled = enabled;
      _refreshNativeSummary();
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalAppIntentsProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
      rethrow;
    }
    onStatusChanged?.call();
  }

  Future<void> poll() {
    if (_disposed || _disposing || !_enabled) return Future<void>.value();
    final Future<void>? active = _activePoll;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _pollOnce().whenComplete(() {
      if (identical(_activePoll, operation)) _activePoll = null;
    });
    _activePoll = operation;
    return operation;
  }

  Future<void> _pollOnce() async {
    TerminalAppIntentsMacosCommand? command;
    try {
      command = _session.takeCommand();
      if (command == null) {
        _refreshNativeSummary();
        return;
      }
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalAppIntentsProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
      return;
    }
    _polling = true;
    onStatusChanged?.call();
    try {
      for (
        var index = 0;
        index < TerminalAppIntentsMacosLimits.maximumPendingCommands;
        index++
      ) {
        if (_disposing || !_enabled) break;
        if (index > 0) command = _session.takeCommand();
        if (command == null) break;
        final TerminalActionDispatchResult result = await _dispatch(
          _actionId(command.action),
        );
        final TerminalAppIntentsMacosCommandDisposition disposition;
        switch (result.disposition) {
          case TerminalActionDispatchDisposition.executed:
            disposition = TerminalAppIntentsMacosCommandDisposition.completed;
            _completedCommandCount = _increment(_completedCommandCount);
          case TerminalActionDispatchDisposition.unavailable:
            disposition = TerminalAppIntentsMacosCommandDisposition.rejected;
            _rejectedCommandCount = _increment(_rejectedCommandCount);
            _lastFailure = TerminalAppIntentsProductFailure.unavailable;
          case TerminalActionDispatchDisposition.busy:
            disposition = TerminalAppIntentsMacosCommandDisposition.rejected;
            _rejectedCommandCount = _increment(_rejectedCommandCount);
            _lastFailure = TerminalAppIntentsProductFailure.busy;
          case TerminalActionDispatchDisposition.failed:
            disposition = TerminalAppIntentsMacosCommandDisposition.failed;
            _failedCommandCount = _increment(_failedCommandCount);
            _lastFailure = TerminalAppIntentsProductFailure.actionFailed;
            final Object? error = result.error;
            final StackTrace? stackTrace = result.stackTrace;
            if (error != null && stackTrace != null) {
              onError?.call(error, stackTrace);
            }
        }
        _session.completeCommand(command, disposition);
      }
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalAppIntentsProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
    } finally {
      try {
        _refreshNativeSummary();
      } on Object catch (error, stackTrace) {
        _recordFailure(TerminalAppIntentsProductFailure.nativeFailure);
        onError?.call(error, stackTrace);
      }
      _polling = false;
      onStatusChanged?.call();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposing = true;
    await _activePoll;
    Object? firstError;
    StackTrace? firstStackTrace;
    if (_enabled) {
      try {
        _session.setEnabled(false);
      } on Object catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    _enabled = false;
    try {
      _session.dispose();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    _disposed = true;
    _disposing = false;
    _pendingCommandCount = 0;
    onStatusChanged?.call();
    if (firstError != null) {
      final StackTrace stackTrace = firstStackTrace ?? StackTrace.current;
      _recordFailure(TerminalAppIntentsProductFailure.nativeFailure);
      onError?.call(firstError, stackTrace);
      Error.throwWithStackTrace(firstError, stackTrace);
    }
  }

  void _recordFailure(TerminalAppIntentsProductFailure failure) {
    _failedCommandCount = _increment(_failedCommandCount);
    _lastFailure = failure;
    onStatusChanged?.call();
  }

  void _refreshNativeSummary() {
    final TerminalAppIntentsMacosSummary summary = _session.summary;
    _pendingCommandCount = summary.pendingCommandCount;
    final int rejectedDelta =
        summary.rejectedCommandCount - _nativeRejectedCommandCount;
    final int timedOutDelta =
        summary.timedOutCommandCount - _nativeTimedOutCommandCount;
    if (rejectedDelta > 0) {
      _rejectedCommandCount = _add(_rejectedCommandCount, rejectedDelta);
      _lastFailure = TerminalAppIntentsProductFailure.nativeRejected;
    }
    if (timedOutDelta > 0) {
      _failedCommandCount = _add(_failedCommandCount, timedOutDelta);
      _lastFailure = TerminalAppIntentsProductFailure.timedOut;
    }
    _nativeRejectedCommandCount = summary.rejectedCommandCount;
    _nativeTimedOutCommandCount = summary.timedOutCommandCount;
  }

  void _ensureMutable() {
    if (_disposed || _disposing) {
      throw StateError('terminal App Intents product controller is disposed');
    }
  }

  static TerminalActionId _actionId(TerminalAppIntentAction action) =>
      switch (action) {
        TerminalAppIntentAction.newWindow => TerminalActionId.newWindow,
        TerminalAppIntentAction.newTab => TerminalActionId.newTab,
        TerminalAppIntentAction.toggleQuickTerminal =>
          TerminalActionId.toggleQuickTerminal,
      };

  static int _increment(int value) =>
      value >= _maximumCounter ? _maximumCounter : value + 1;

  static int _add(int value, int delta) {
    if (delta <= 0) return value;
    if (value >= _maximumCounter || delta >= _maximumCounter - value) {
      return _maximumCounter;
    }
    return value + delta;
  }
}
