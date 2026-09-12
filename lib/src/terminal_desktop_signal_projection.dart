import 'dart:collection';
import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_core/terminal_desktop_signals.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_core/terminal_semantic_prompt.dart';
import 'terminal_pane.dart';

typedef TerminalDesktopSignalProjectionErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Product-owned native boundary for bounded desktop terminal signals.
abstract interface class TerminalDesktopSignalNativePort {
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  });

  bool removeNotification(String identifier);

  bool setDockBadgeLabel(String? label);
}

/// AppKit projection that contains no terminal admission or lifecycle policy.
final class TerminalAppKitDesktopSignalPort
    implements TerminalDesktopSignalNativePort {
  TerminalAppKitDesktopSignalPort({
    required AppKitApplication application,
    TerminalDesktopSignalProjectionErrorHandler? onError,
  }) : _application = application,
       _onError = onError;

  final AppKitApplication _application;
  final TerminalDesktopSignalProjectionErrorHandler? _onError;

  @override
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  }) => _guard(() {
    _application.postUserNotification(
      AppKitUserNotification(identifier: identifier, title: title, body: body),
    );
  });

  @override
  bool removeNotification(String identifier) =>
      _guard(() => _application.removeUserNotification(identifier));

  @override
  bool setDockBadgeLabel(String? label) =>
      _guard(() => _application.dockBadgeLabel = label);

  bool _guard(void Function() operation) {
    try {
      operation();
      return true;
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      return false;
    }
  }
}

/// Immutable diagnostics for application-global desktop-signal admission.
final class TerminalDesktopSignalMetrics {
  const TerminalDesktopSignalMetrics({
    required this.admittedNotificationCount,
    required this.projectedNotificationCount,
    required this.coalescedNotificationCount,
    required this.rateLimitedNotificationCount,
    required this.focusSuppressedNotificationCount,
    required this.revokedSessionDroppedNotificationCount,
    required this.cancelledNotificationCount,
    required this.projectionFailureCount,
    required this.trackedSessionCount,
  });

  final int admittedNotificationCount;
  final int projectedNotificationCount;
  final int coalescedNotificationCount;
  final int rateLimitedNotificationCount;
  final int focusSuppressedNotificationCount;
  final int revokedSessionDroppedNotificationCount;
  final int cancelledNotificationCount;
  final int projectionFailureCount;
  final int trackedSessionCount;
}

/// Content-free projection state for one live terminal session.
final class TerminalDesktopSignalSessionSnapshot {
  const TerminalDesktopSignalSessionSnapshot({
    required this.sessionId,
    required this.resetGeneration,
    required this.progress,
    required this.semanticShellState,
    required this.liveNotificationCount,
  });

  final TerminalSessionId sessionId;
  final int resetGeneration;
  final TerminalProgressUpdate progress;
  final TerminalSemanticShellState semanticShellState;
  final int liveNotificationCount;
}

/// Single-session authority issued and revoked by the application coordinator.
final class TerminalDesktopSignalSessionProjection {
  TerminalDesktopSignalSessionProjection._(this._owner, this.sessionId);

  final TerminalDesktopSignalCoordinator _owner;
  final TerminalSessionId sessionId;
  _SessionProjectionState? _state;
  bool _closed = false;

  bool get isClosed => _closed;

  void synchronize(TerminalScreenSet screens) =>
      _owner._synchronizeSession(this, screens);

  void close() => _owner._closeSession(this);
}

/// Deterministic admission and lifecycle owner for terminal desktop signals.
final class TerminalDesktopSignalCoordinator {
  factory TerminalDesktopSignalCoordinator({
    required TerminalDesktopSignalNativePort nativePort,
    int Function()? monotonicMicros,
    int notificationBudget = defaultNotificationBudget,
    Duration notificationWindow = defaultNotificationWindow,
    int maximumLiveNotificationsPerSession =
        defaultMaximumLiveNotificationsPerSession,
    String fallbackTitle = 'Dart Terminal',
    bool applicationActive = false,
    bool notificationsEnabled = true,
  }) {
    final Stopwatch clock = Stopwatch()..start();
    return TerminalDesktopSignalCoordinator._(
      nativePort: nativePort,
      monotonicMicros: monotonicMicros ?? () => clock.elapsedMicroseconds,
      notificationBudget: notificationBudget,
      notificationWindow: notificationWindow,
      maximumLiveNotificationsPerSession: maximumLiveNotificationsPerSession,
      fallbackTitle: fallbackTitle,
      applicationActive: applicationActive,
      notificationsEnabled: notificationsEnabled,
    );
  }

  TerminalDesktopSignalCoordinator._({
    required TerminalDesktopSignalNativePort nativePort,
    required int Function() monotonicMicros,
    required this.notificationBudget,
    required this.notificationWindow,
    required this.maximumLiveNotificationsPerSession,
    required this.fallbackTitle,
    required bool applicationActive,
    required bool notificationsEnabled,
  }) : _nativePort = nativePort,
       _monotonicMicros = monotonicMicros,
       _applicationActive = applicationActive,
       _notificationsEnabled = notificationsEnabled {
    RangeError.checkValueInInterval(
      notificationBudget,
      1,
      maximumNotificationBudget,
      'notificationBudget',
    );
    final int windowMicros = notificationWindow.inMicroseconds;
    RangeError.checkValueInInterval(
      windowMicros,
      minimumNotificationWindow.inMicroseconds,
      maximumNotificationWindow.inMicroseconds,
      'notificationWindow',
    );
    RangeError.checkValueInInterval(
      maximumLiveNotificationsPerSession,
      1,
      maximumSupportedLiveNotificationsPerSession,
      'maximumLiveNotificationsPerSession',
    );
    if (utf8.encode(fallbackTitle).length >
        AppKitUserNotification.maximumTextUtf8Bytes) {
      throw ArgumentError.value(fallbackTitle, 'fallbackTitle', 'is too long');
    }
  }

  static const int defaultNotificationBudget = 3;
  static const int maximumNotificationBudget = 8;
  static const Duration defaultNotificationWindow = Duration(seconds: 10);
  static const Duration minimumNotificationWindow = Duration(seconds: 1);
  static const Duration maximumNotificationWindow = Duration(hours: 1);
  static const int defaultMaximumLiveNotificationsPerSession = 8;
  static const int maximumSupportedLiveNotificationsPerSession = 8;
  static const int maximumTrackedSessions = 64;
  static const int _maximumMetric = 0x7fffffff;
  static const int _maximumNativeSerial = 0x7fffffff;

  final TerminalDesktopSignalNativePort _nativePort;
  final int Function() _monotonicMicros;
  final int notificationBudget;
  final Duration notificationWindow;
  final int maximumLiveNotificationsPerSession;
  final String fallbackTitle;
  final LinkedHashMap<TerminalSessionId, TerminalDesktopSignalSessionProjection>
  _sessions =
      LinkedHashMap<
        TerminalSessionId,
        TerminalDesktopSignalSessionProjection
      >();
  final ListQueue<int> _admittedNotificationMicros = ListQueue<int>();

  TerminalSessionId? _focusedSessionId;
  String? _projectedDockBadgeLabel;
  bool _applicationActive;
  bool _notificationsEnabled;
  bool _disposed = false;
  int _lastMonotonicMicros = 0;
  int _nextNativeSerial = 1;
  int _admittedNotificationCount = 0;
  int _projectedNotificationCount = 0;
  int _coalescedNotificationCount = 0;
  int _rateLimitedNotificationCount = 0;
  int _focusSuppressedNotificationCount = 0;
  int _revokedSessionDroppedNotificationCount = 0;
  int _cancelledNotificationCount = 0;
  int _projectionFailureCount = 0;

  bool get isDisposed => _disposed;
  TerminalSessionId? get focusedSessionId => _focusedSessionId;
  String? get projectedDockBadgeLabel => _projectedDockBadgeLabel;
  bool get notificationsEnabled => _notificationsEnabled;

  TerminalDesktopSignalMetrics get metrics => TerminalDesktopSignalMetrics(
    admittedNotificationCount: _admittedNotificationCount,
    projectedNotificationCount: _projectedNotificationCount,
    coalescedNotificationCount: _coalescedNotificationCount,
    rateLimitedNotificationCount: _rateLimitedNotificationCount,
    focusSuppressedNotificationCount: _focusSuppressedNotificationCount,
    revokedSessionDroppedNotificationCount:
        _revokedSessionDroppedNotificationCount,
    cancelledNotificationCount: _cancelledNotificationCount,
    projectionFailureCount: _projectionFailureCount,
    trackedSessionCount: _sessions.length,
  );

  TerminalDesktopSignalSessionSnapshot? snapshotFor(
    TerminalSessionId sessionId,
  ) {
    final _SessionProjectionState? state = _sessions[sessionId]?._state;
    if (state == null) return null;
    return TerminalDesktopSignalSessionSnapshot(
      sessionId: sessionId,
      resetGeneration: state.resetGeneration,
      progress: state.progress,
      semanticShellState: state.semanticShellState,
      liveNotificationCount: state.liveNotifications.length,
    );
  }

  /// Registers one live session and returns its revocable projection authority.
  TerminalDesktopSignalSessionProjection registerSession(
    TerminalSessionId sessionId,
  ) {
    if (_disposed) {
      throw StateError('desktop signal coordinator is disposed');
    }
    if (_sessions.containsKey(sessionId)) {
      throw StateError('desktop signal session $sessionId is already live');
    }
    if (_sessions.length >= maximumTrackedSessions) {
      throw StateError('desktop signal live session limit is exhausted');
    }
    final TerminalDesktopSignalSessionProjection result =
        TerminalDesktopSignalSessionProjection._(this, sessionId);
    _sessions[sessionId] = result;
    return result;
  }

  /// Drains and projects the bounded state produced by one parser turn.
  void _synchronizeSession(
    TerminalDesktopSignalSessionProjection projection,
    TerminalScreenSet screens,
  ) {
    if (_disposed || projection._closed) {
      final int dropped = _dropQueuedRequests(screens.desktopNotifications);
      _revokedSessionDroppedNotificationCount = _saturatingAdd(
        _revokedSessionDroppedNotificationCount,
        dropped,
      );
      return;
    }
    if (!identical(_sessions[projection.sessionId], projection)) {
      projection._closed = true;
      final int dropped = _dropQueuedRequests(screens.desktopNotifications);
      _revokedSessionDroppedNotificationCount = _saturatingAdd(
        _revokedSessionDroppedNotificationCount,
        dropped,
      );
      return;
    }
    _SessionProjectionState? state = projection._state;
    if (state != null && !identical(state.screens, screens)) {
      _cancelAll(state);
      projection._state = null;
      state = null;
    }
    if (state == null) {
      state = _SessionProjectionState(screens);
      projection._state = state;
    }

    if (state.resetGeneration != screens.resetGeneration) {
      _cancelAll(state);
      state.resetGeneration = screens.resetGeneration;
    }
    state
      ..progress = screens.progress.value
      ..semanticShellState = screens.semanticPrompt.shellState;

    final LinkedHashMap<
      ({
        TerminalDesktopNotificationProtocol protocol,
        String? identifier,
        String title,
        String body,
      }),
      TerminalDesktopNotificationRequest
    >
    coalesced = LinkedHashMap();
    TerminalDesktopNotificationRequest? request;
    while ((request = screens.desktopNotifications.takeNextRequest()) != null) {
      final TerminalDesktopNotificationRequest current = request!;
      final key = (
        protocol: current.protocol,
        identifier: current.identifier,
        title: current.identifier == null ? current.title : '',
        body: current.identifier == null ? current.body : '',
      );
      if (coalesced.containsKey(key)) {
        _coalescedNotificationCount = _saturatingIncrement(
          _coalescedNotificationCount,
        );
      }
      coalesced[key] = current;
    }
    for (final TerminalDesktopNotificationRequest pending in coalesced.values) {
      _projectNotification(projection.sessionId, state, pending);
    }
    if (_focusedSessionId == projection.sessionId) _refreshDockBadge();
  }

  void focusSession(TerminalSessionId? sessionId) {
    if (_disposed || _focusedSessionId == sessionId) return;
    _focusedSessionId = sessionId;
    _refreshDockBadge();
  }

  void setApplicationActive(bool active) {
    if (_disposed) return;
    _applicationActive = active;
  }

  void setNotificationsEnabled(bool enabled) {
    if (_disposed || _notificationsEnabled == enabled) return;
    _notificationsEnabled = enabled;
    if (!enabled) {
      for (final TerminalDesktopSignalSessionProjection projection
          in _sessions.values) {
        final _SessionProjectionState? state = projection._state;
        if (state != null) _cancelAll(state);
      }
      _admittedNotificationMicros.clear();
    }
  }

  /// Forgets an asynchronously rejected native delivery without another remove.
  void reportNotificationDeliveryFailure(String nativeIdentifier) {
    if (_disposed) return;
    for (final TerminalDesktopSignalSessionProjection projection
        in _sessions.values) {
      final _SessionProjectionState? state = projection._state;
      final _LiveNotification? notification =
          state?.liveNotifications[nativeIdentifier];
      if (state == null || notification == null) continue;
      state.liveNotifications.remove(nativeIdentifier);
      final String? logicalIdentifier = notification.logicalIdentifier;
      if (logicalIdentifier != null &&
          state.nativeIdentifierByLogicalIdentifier[logicalIdentifier] ==
              nativeIdentifier) {
        state.nativeIdentifierByLogicalIdentifier.remove(logicalIdentifier);
      }
      _projectionFailureCount = _saturatingIncrement(_projectionFailureCount);
      return;
    }
  }

  void removeSession(TerminalSessionId sessionId) {
    if (_disposed) return;
    _sessions[sessionId]?.close();
  }

  void _closeSession(TerminalDesktopSignalSessionProjection projection) {
    if (projection._closed) return;
    projection._closed = true;
    if (identical(_sessions[projection.sessionId], projection)) {
      _sessions.remove(projection.sessionId);
    }
    final _SessionProjectionState? state = projection._state;
    projection._state = null;
    if (state != null) _cancelAll(state);
    if (_focusedSessionId == projection.sessionId) {
      _focusedSessionId = null;
      _refreshDockBadge();
    }
  }

  void dispose() {
    if (_disposed) return;
    for (final TerminalDesktopSignalSessionProjection projection
        in _sessions.values.toList(growable: false)) {
      _closeSession(projection);
    }
    _focusedSessionId = null;
    _setDockBadgeLabel(null);
    _admittedNotificationMicros.clear();
    _disposed = true;
  }

  void _projectNotification(
    TerminalSessionId sessionId,
    _SessionProjectionState state,
    TerminalDesktopNotificationRequest request,
  ) {
    if (!_notificationsEnabled) return;
    if (_applicationActive && _focusedSessionId == sessionId) {
      _focusSuppressedNotificationCount = _saturatingIncrement(
        _focusSuppressedNotificationCount,
      );
      return;
    }
    final String? logicalIdentifier = request.identifier == null
        ? null
        : '${request.protocol.index}:${request.identifier}';
    final _NotificationFingerprint fingerprint =
        _NotificationFingerprint.fromRequest(request);
    final String? existingNativeIdentifier = logicalIdentifier == null
        ? null
        : state.nativeIdentifierByLogicalIdentifier[logicalIdentifier];
    if (existingNativeIdentifier != null &&
        state.liveNotifications[existingNativeIdentifier]?.fingerprint ==
            fingerprint) {
      _coalescedNotificationCount = _saturatingIncrement(
        _coalescedNotificationCount,
      );
      return;
    }
    if (!_admitNotification()) {
      _rateLimitedNotificationCount = _saturatingIncrement(
        _rateLimitedNotificationCount,
      );
      return;
    }
    _admittedNotificationCount = _saturatingIncrement(
      _admittedNotificationCount,
    );

    String nativeIdentifier =
        existingNativeIdentifier ?? _newNativeIdentifier(sessionId, state);
    if (existingNativeIdentifier == null &&
        state.liveNotifications.length >= maximumLiveNotificationsPerSession) {
      final MapEntry<String, _LiveNotification> evicted =
          state.liveNotifications.entries.first;
      _cancelNotification(state, evicted.key, evicted.value);
      nativeIdentifier = _newNativeIdentifier(sessionId, state);
    }
    final String title = request.title.isEmpty ? fallbackTitle : request.title;
    final bool projected = _nativePort.postNotification(
      sessionId: sessionId,
      identifier: nativeIdentifier,
      title: title,
      body: request.body,
    );
    if (!projected) {
      _projectionFailureCount = _saturatingIncrement(_projectionFailureCount);
      return;
    }
    _projectedNotificationCount = _saturatingIncrement(
      _projectedNotificationCount,
    );
    state.liveNotifications[nativeIdentifier] = _LiveNotification(
      logicalIdentifier: logicalIdentifier,
      fingerprint: fingerprint,
    );
    if (logicalIdentifier != null) {
      state.nativeIdentifierByLogicalIdentifier[logicalIdentifier] =
          nativeIdentifier;
    }
  }

  bool _admitNotification() {
    int now = _monotonicMicros();
    if (now < _lastMonotonicMicros) now = _lastMonotonicMicros;
    _lastMonotonicMicros = now;
    final int windowMicros = notificationWindow.inMicroseconds;
    while (_admittedNotificationMicros.isNotEmpty &&
        now - _admittedNotificationMicros.first >= windowMicros) {
      _admittedNotificationMicros.removeFirst();
    }
    if (_admittedNotificationMicros.length >= notificationBudget) return false;
    _admittedNotificationMicros.addLast(now);
    return true;
  }

  String _newNativeIdentifier(
    TerminalSessionId sessionId,
    _SessionProjectionState state,
  ) {
    for (
      int attempt = 0;
      attempt <= maximumSupportedLiveNotificationsPerSession;
      attempt++
    ) {
      final int serial = _nextNativeSerial;
      _nextNativeSerial = serial >= _maximumNativeSerial ? 1 : serial + 1;
      final String candidate =
          'dt.p${sessionId.paneId.value.toRadixString(16)}'
          '.s${sessionId.generation.toRadixString(16)}'
          '.n${serial.toRadixString(16)}';
      if (!state.liveNotifications.containsKey(candidate)) return candidate;
    }
    throw StateError('bounded desktop notification identity space exhausted');
  }

  void _cancelAll(_SessionProjectionState state) {
    for (final MapEntry<String, _LiveNotification> entry
        in state.liveNotifications.entries.toList(growable: false)) {
      _cancelNotification(state, entry.key, entry.value);
    }
    state.nativeIdentifierByLogicalIdentifier.clear();
  }

  void _cancelNotification(
    _SessionProjectionState state,
    String nativeIdentifier,
    _LiveNotification notification,
  ) {
    state.liveNotifications.remove(nativeIdentifier);
    final String? logicalIdentifier = notification.logicalIdentifier;
    if (logicalIdentifier != null &&
        state.nativeIdentifierByLogicalIdentifier[logicalIdentifier] ==
            nativeIdentifier) {
      state.nativeIdentifierByLogicalIdentifier.remove(logicalIdentifier);
    }
    if (_nativePort.removeNotification(nativeIdentifier)) {
      _cancelledNotificationCount = _saturatingIncrement(
        _cancelledNotificationCount,
      );
    } else {
      _projectionFailureCount = _saturatingIncrement(_projectionFailureCount);
    }
  }

  void _refreshDockBadge() {
    final _SessionProjectionState? state = _sessions[_focusedSessionId]?._state;
    _setDockBadgeLabel(
      state == null ? null : _progressBadgeLabel(state.progress),
    );
  }

  void _setDockBadgeLabel(String? label) {
    if (_projectedDockBadgeLabel == label) return;
    if (_nativePort.setDockBadgeLabel(label)) {
      _projectedDockBadgeLabel = label;
    } else {
      _projectionFailureCount = _saturatingIncrement(_projectionFailureCount);
    }
  }

  static String? _progressBadgeLabel(TerminalProgressUpdate progress) =>
      switch (progress.state) {
        TerminalProgressState.removed => null,
        TerminalProgressState.set => '${progress.percent ?? 0}%',
        TerminalProgressState.error =>
          progress.percent == null ? '!' : '${progress.percent}%!',
        TerminalProgressState.indeterminate => '…',
        TerminalProgressState.paused =>
          progress.percent == null ? 'paused' : '${progress.percent}% paused',
      };

  static int _dropQueuedRequests(TerminalDesktopNotificationModel model) {
    var result = 0;
    while (model.takeNextRequest() != null) {
      result++;
    }
    return result;
  }

  static int _saturatingIncrement(int value) =>
      value >= _maximumMetric ? _maximumMetric : value + 1;

  static int _saturatingAdd(int value, int delta) =>
      value >= _maximumMetric - delta ? _maximumMetric : value + delta;
}

final class _SessionProjectionState {
  _SessionProjectionState(this.screens)
    : resetGeneration = screens.resetGeneration,
      progress = screens.progress.value,
      semanticShellState = screens.semanticPrompt.shellState;

  final TerminalScreenSet screens;
  int resetGeneration;
  TerminalProgressUpdate progress;
  TerminalSemanticShellState semanticShellState;
  final LinkedHashMap<String, _LiveNotification> liveNotifications =
      LinkedHashMap<String, _LiveNotification>();
  final Map<String, String> nativeIdentifierByLogicalIdentifier =
      <String, String>{};
}

final class _LiveNotification {
  const _LiveNotification({
    required this.logicalIdentifier,
    required this.fingerprint,
  });

  final String? logicalIdentifier;
  final _NotificationFingerprint fingerprint;
}

final class _NotificationFingerprint {
  const _NotificationFingerprint({
    required this.titleLength,
    required this.bodyLength,
    required this.titleHash,
    required this.bodyHash,
  });

  factory _NotificationFingerprint.fromRequest(
    TerminalDesktopNotificationRequest request,
  ) => _NotificationFingerprint(
    titleLength: request.title.length,
    bodyLength: request.body.length,
    titleHash: request.title.hashCode,
    bodyHash: request.body.hashCode,
  );

  final int titleLength;
  final int bodyLength;
  final int titleHash;
  final int bodyHash;

  @override
  bool operator ==(Object other) =>
      other is _NotificationFingerprint &&
      other.titleLength == titleLength &&
      other.bodyLength == bodyLength &&
      other.titleHash == titleHash &&
      other.bodyHash == bodyHash;

  @override
  int get hashCode => Object.hash(titleLength, bodyLength, titleHash, bodyHash);
}
