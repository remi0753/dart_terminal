import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_desktop_signal_projection.dart';
import 'terminal_localization.dart';
import 'terminal_pane.dart';

typedef TerminalNotificationFocusSession = FutureOr<bool> Function(
  TerminalSessionId sessionId,
);
typedef TerminalNotificationProductStatusObserver = void Function();
typedef TerminalNotificationProductErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);
typedef TerminalNotificationDeliveryFailureObserver = void Function(
  String identifier,
);

abstract interface class TerminalUserNotificationPlatformPort {
  AppKitUserNotificationAuthorizationStatus? get cachedAuthorizationStatus;

  int refreshSettings();

  int requestAuthorization();

  int postTrackedNotification(
    AppKitUserNotification notification, {
    required int responseToken,
  });

  void removeNotification(String identifier);

  void setDockBadgeLabel(String? label);
}

final class TerminalAppKitUserNotificationPlatformPort
    implements TerminalUserNotificationPlatformPort {
  const TerminalAppKitUserNotificationPlatformPort(this.application);

  final AppKitApplication application;

  @override
  AppKitUserNotificationAuthorizationStatus? get cachedAuthorizationStatus =>
      application.userNotificationAuthorizationStatus;

  @override
  int refreshSettings() => application.refreshUserNotificationSettings();

  @override
  int requestAuthorization() =>
      application.requestUserNotificationAuthorization();

  @override
  int postTrackedNotification(
    AppKitUserNotification notification, {
    required int responseToken,
  }) => application.postTrackedUserNotification(
    notification,
    responseToken: responseToken,
  );

  @override
  void removeNotification(String identifier) =>
      application.removeUserNotification(identifier);

  @override
  void setDockBadgeLabel(String? label) => application.dockBadgeLabel = label;
}

enum TerminalNotificationProductFailure {
  none,
  denied,
  system,
  cancelled,
  staleResponse,
  capacity,
  nativeFailure,
}

final class TerminalNotificationProductStatus {
  const TerminalNotificationProductStatus({
    required this.enabled,
    required this.authorizationStatus,
    required this.pendingRequestCount,
    required this.liveResponseCount,
    required this.lastFailure,
    required this.disposed,
  });

  final bool enabled;
  final AppKitUserNotificationAuthorizationStatus authorizationStatus;
  final int pendingRequestCount;
  final int liveResponseCount;
  final TerminalNotificationProductFailure lastFailure;
  final bool disposed;

  String get settingsLine => settingsLineFor(TerminalLocalization.english);

  String settingsLineFor(TerminalLocalization localization) =>
      localization.notificationStatus(
        enabled: enabled,
        authorization: authorizationStatus.name,
        pending: pendingRequestCount,
        responses: liveResponseCount,
        last: lastFailure.name,
        stopped: disposed,
      );
}

/// Owns content-free notification request/response correlation for the product.
final class TerminalNotificationProductController
    implements TerminalDesktopSignalNativePort {
  TerminalNotificationProductController({
    required TerminalUserNotificationPlatformPort platform,
    required TerminalNotificationFocusSession focusSession,
    this.onStatusChanged,
    this.onError,
    this.onDeliveryFailure,
  }) : _platform = platform,
       _focusSession = focusSession,
       _authorizationStatus =
           platform.cachedAuthorizationStatus ??
           AppKitUserNotificationAuthorizationStatus.unknown;

  static const int _maximumToken = 0x7fffffffffffffff;
  static const int maximumTrackedNotifications = 256;

  final TerminalUserNotificationPlatformPort _platform;
  final TerminalNotificationFocusSession _focusSession;
  final TerminalNotificationProductStatusObserver? onStatusChanged;
  final TerminalNotificationProductErrorObserver? onError;
  final TerminalNotificationDeliveryFailureObserver? onDeliveryFailure;
  final Map<String, _TerminalNotificationRecord> _recordsByIdentifier =
      <String, _TerminalNotificationRecord>{};
  final Map<int, _TerminalNotificationRecord> _recordsByDeliveryToken =
      <int, _TerminalNotificationRecord>{};
  final Map<int, _TerminalNotificationRecord> _recordsByResponseToken =
      <int, _TerminalNotificationRecord>{};
  final Set<int> _settingsTokens = <int>{};
  final Set<int> _authorizationTokens = <int>{};

  AppKitUserNotificationAuthorizationStatus _authorizationStatus;
  TerminalNotificationProductFailure _lastFailure =
      TerminalNotificationProductFailure.none;
  int _nextResponseToken = 1;
  bool _enabled = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  TerminalNotificationProductStatus get status =>
      TerminalNotificationProductStatus(
        enabled: _enabled,
        authorizationStatus: _authorizationStatus,
        pendingRequestCount:
            _settingsTokens.length +
            _authorizationTokens.length +
            _recordsByDeliveryToken.length,
        liveResponseCount: _recordsByResponseToken.length,
        lastFailure: _lastFailure,
        disposed: _disposed,
      );

  void applyEnabled(bool enabled) {
    _ensureLive();
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      refreshSettings();
    } else {
      _clearTrackedNotifications();
      _settingsTokens.clear();
      _authorizationTokens.clear();
    }
    onStatusChanged?.call();
  }

  void refreshSettings() {
    _ensureLive();
    if (!_enabled || _settingsTokens.isNotEmpty) return;
    try {
      _settingsTokens.add(_platform.refreshSettings());
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalNotificationProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
    }
    onStatusChanged?.call();
  }

  void requestAuthorization() {
    _ensureLive();
    if (!_enabled || _authorizationTokens.isNotEmpty) return;
    try {
      _authorizationTokens.add(_platform.requestAuthorization());
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalNotificationProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
    }
    onStatusChanged?.call();
  }

  @override
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  }) {
    if (_disposed || !_enabled) return false;
    if (!_recordsByIdentifier.containsKey(identifier) &&
        _recordsByIdentifier.length >= maximumTrackedNotifications) {
      _recordFailure(TerminalNotificationProductFailure.capacity);
      onStatusChanged?.call();
      return false;
    }
    final int responseToken = _newResponseToken();
    try {
      final int deliveryToken = _platform.postTrackedNotification(
        AppKitUserNotification(
          identifier: identifier,
          title: title,
          body: body,
        ),
        responseToken: responseToken,
      );
      if (deliveryToken <= 0 ||
          _recordsByDeliveryToken.containsKey(deliveryToken)) {
        throw StateError('notification delivery token is invalid or reused');
      }
      final _TerminalNotificationRecord? previous =
          _recordsByIdentifier[identifier];
      if (previous != null) _forget(previous);
      final _TerminalNotificationRecord record = _TerminalNotificationRecord(
        identifier: identifier,
        sessionId: sessionId,
        deliveryToken: deliveryToken,
        responseToken: responseToken,
      );
      _recordsByIdentifier[identifier] = record;
      _recordsByDeliveryToken[deliveryToken] = record;
      _recordsByResponseToken[responseToken] = record;
      onStatusChanged?.call();
      return true;
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalNotificationProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
      return false;
    }
  }

  @override
  bool removeNotification(String identifier) {
    if (_disposed) return false;
    var removed = true;
    try {
      _platform.removeNotification(identifier);
    } on Object catch (error, stackTrace) {
      removed = false;
      _recordFailure(TerminalNotificationProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
    } finally {
      final _TerminalNotificationRecord? record =
          _recordsByIdentifier[identifier];
      if (record != null) _forget(record);
    }
    onStatusChanged?.call();
    return removed;
  }

  @override
  bool setDockBadgeLabel(String? label) {
    if (_disposed) return false;
    try {
      _platform.setDockBadgeLabel(label);
      return true;
    } on Object catch (error, stackTrace) {
      _recordFailure(TerminalNotificationProductFailure.nativeFailure);
      onError?.call(error, stackTrace);
      return false;
    }
  }

  Future<void> handleEvent(
    ApplicationUserNotificationChangedEvent event,
  ) async {
    if (_disposed) return;
    switch (event.kind) {
      case AppKitUserNotificationEventKind.settings:
        if (!_settingsTokens.remove(event.token)) return;
        _updateAuthorization(event.authorizationStatus);
        _recordNativeFailure(event.failure);
      case AppKitUserNotificationEventKind.authorization:
        if (!_authorizationTokens.remove(event.token)) return;
        _updateAuthorization(event.authorizationStatus);
        _recordNativeFailure(event.failure);
      case AppKitUserNotificationEventKind.delivery:
        final _TerminalNotificationRecord? record = _recordsByDeliveryToken
            .remove(event.token);
        if (record == null) return;
        _updateAuthorization(event.authorizationStatus);
        if (event.failure != AppKitUserNotificationFailure.none) {
          _recordNativeFailure(event.failure);
          _forget(record);
          onDeliveryFailure?.call(record.identifier);
        }
      case AppKitUserNotificationEventKind.defaultResponse:
        final _TerminalNotificationRecord? record =
            _recordsByResponseToken[event.token];
        if (record == null) return;
        _forget(record);
        final bool focused;
        try {
          focused = await _focusSession(record.sessionId);
        } on Object catch (error, stackTrace) {
          _recordFailure(TerminalNotificationProductFailure.nativeFailure);
          onError?.call(error, stackTrace);
          onStatusChanged?.call();
          return;
        }
        if (!focused) {
          _recordFailure(TerminalNotificationProductFailure.staleResponse);
        }
    }
    onStatusChanged?.call();
  }

  void dispose() {
    if (_disposed) return;
    if (_enabled) {
      _enabled = false;
      _clearTrackedNotifications();
    }
    _settingsTokens.clear();
    _authorizationTokens.clear();
    _disposed = true;
    onStatusChanged?.call();
  }

  int _newResponseToken() {
    for (
      var attempt = 0;
      attempt <= _recordsByResponseToken.length;
      attempt++
    ) {
      final int candidate = _nextResponseToken;
      _nextResponseToken = candidate >= _maximumToken ? 1 : candidate + 1;
      if (!_recordsByResponseToken.containsKey(candidate)) return candidate;
    }
    throw StateError('notification response token space is exhausted');
  }

  void _clearTrackedNotifications() {
    for (final String identifier in _recordsByIdentifier.keys.toList(
      growable: false,
    )) {
      removeNotification(identifier);
    }
  }

  void _forget(_TerminalNotificationRecord record) {
    if (identical(_recordsByIdentifier[record.identifier], record)) {
      _recordsByIdentifier.remove(record.identifier);
    }
    if (identical(_recordsByDeliveryToken[record.deliveryToken], record)) {
      _recordsByDeliveryToken.remove(record.deliveryToken);
    }
    if (identical(_recordsByResponseToken[record.responseToken], record)) {
      _recordsByResponseToken.remove(record.responseToken);
    }
  }

  void _recordNativeFailure(AppKitUserNotificationFailure failure) {
    switch (failure) {
      case AppKitUserNotificationFailure.none:
        return;
      case AppKitUserNotificationFailure.denied:
        _recordFailure(TerminalNotificationProductFailure.denied);
      case AppKitUserNotificationFailure.system:
        _recordFailure(TerminalNotificationProductFailure.system);
      case AppKitUserNotificationFailure.cancelled:
        _recordFailure(TerminalNotificationProductFailure.cancelled);
    }
  }

  void _recordFailure(TerminalNotificationProductFailure failure) {
    _lastFailure = failure;
  }

  void _updateAuthorization(AppKitUserNotificationAuthorizationStatus status) {
    if (status != AppKitUserNotificationAuthorizationStatus.unknown) {
      _authorizationStatus = status;
    }
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('terminal notification product controller is disposed');
    }
  }
}

final class _TerminalNotificationRecord {
  _TerminalNotificationRecord({
    required this.identifier,
    required this.sessionId,
    required this.deliveryToken,
    required this.responseToken,
  });

  final String identifier;
  final TerminalSessionId sessionId;
  final int deliveryToken;
  final int responseToken;
}
