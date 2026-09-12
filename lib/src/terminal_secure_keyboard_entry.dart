import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_localization.dart';

typedef TerminalSecureKeyboardEntryStatusObserver = void Function(
  TerminalSecureKeyboardEntryStatus status,
);
typedef TerminalSecureKeyboardEntryFailureObserver = void Function(
  Object error,
  StackTrace stackTrace,
);
typedef TerminalSecureKeyboardEntryIndicatorWriter = void Function(
  TerminalSecureKeyboardEntryIndicator indicator,
);

enum TerminalSecureKeyboardEntryMode { disabled, automatic, manual, failed }

enum TerminalSecureKeyboardEntryIndicator { hidden, automatic, manual }

final class TerminalSecureKeyboardEntryLeaseSnapshot {
  const TerminalSecureKeyboardEntryLeaseSnapshot({
    required this.desired,
    required this.ownedEnabled,
    required this.systemEnabled,
    required this.lastOsStatus,
  });

  final bool desired;
  final bool ownedEnabled;
  final bool systemEnabled;
  final int lastOsStatus;
}

abstract interface class TerminalSecureKeyboardEntryLease {
  void setDesired(bool desired);

  TerminalSecureKeyboardEntryLeaseSnapshot snapshot();

  void dispose();
}

/// AppKit adapter kept separate from the product policy for deterministic
/// tests and so the balanced native owner has exactly one product owner.
final class TerminalAppKitSecureKeyboardEntryLease
    implements TerminalSecureKeyboardEntryLease {
  TerminalAppKitSecureKeyboardEntryLease() : _owner = SecureEventInput();

  final SecureEventInput _owner;

  @override
  void setDesired(bool desired) => _owner.setDesired(desired);

  @override
  TerminalSecureKeyboardEntryLeaseSnapshot snapshot() {
    final SecureEventInputSnapshot snapshot = _owner.snapshot();
    return TerminalSecureKeyboardEntryLeaseSnapshot(
      desired: snapshot.desired,
      ownedEnabled: snapshot.ownedEnabled,
      systemEnabled: snapshot.systemEnabled,
      lastOsStatus: snapshot.lastOsStatus,
    );
  }

  @override
  void dispose() => _owner.dispose();
}

/// A stable failing port used when the optional native resource cannot be
/// created. It keeps Settings and the shared action available for diagnosis.
final class TerminalUnavailableSecureKeyboardEntryLease
    implements TerminalSecureKeyboardEntryLease {
  const TerminalUnavailableSecureKeyboardEntryLease(
    this.error,
    this.stackTrace,
  );

  final Object error;
  final StackTrace stackTrace;

  Never _throw() => Error.throwWithStackTrace(error, stackTrace);

  @override
  void setDesired(bool desired) {
    if (!desired) return;
    _throw();
  }

  @override
  TerminalSecureKeyboardEntryLeaseSnapshot snapshot() => _throw();

  @override
  void dispose() {}
}

/// Content-free state for the one pane that can receive terminal input.
final class TerminalSecureKeyboardEntryTarget {
  const TerminalSecureKeyboardEntryTarget({
    required this.identity,
    required this.isFocused,
    required this.isLive,
    required this.terminalEchoEnabled,
    required this.setIndicator,
  });

  final Object identity;
  final bool isFocused;
  final bool isLive;
  final bool? terminalEchoEnabled;
  final TerminalSecureKeyboardEntryIndicatorWriter setIndicator;
}

final class TerminalSecureKeyboardEntryStatus {
  const TerminalSecureKeyboardEntryStatus({
    required this.mode,
    required this.manualRequested,
    required this.automaticEnabled,
    required this.indicationEnabled,
    required this.applicationActive,
    required this.desired,
    required this.ownedEnabled,
    required this.systemEnabled,
    required this.lastOsStatus,
    required this.targetIdentity,
    required this.terminalEchoEnabled,
    required this.failure,
  });

  final TerminalSecureKeyboardEntryMode mode;
  final bool manualRequested;
  final bool automaticEnabled;
  final bool indicationEnabled;
  final bool applicationActive;
  final bool desired;
  final bool ownedEnabled;
  final bool systemEnabled;
  final int lastOsStatus;
  final Object? targetIdentity;
  final bool? terminalEchoEnabled;
  final Object? failure;

  String get settingsLine => settingsLineFor(TerminalLocalization.english);

  String settingsLineFor(TerminalLocalization localization) {
    final String ownership = ownedEnabled
        ? 'owned'
        : desired
        ? 'yielded'
        : 'released';
    return localization.secureKeyboardStatus(
      mode: mode.name,
      ownership: ownership,
      automatic: automaticEnabled,
      indicator: indicationEnabled,
    );
  }

  String machineLine() =>
      'TERMINAL_SECURE_KEYBOARD_ENTRY mode=${mode.name} '
      'manual_requested=$manualRequested automatic_enabled=$automaticEnabled '
      'indication_enabled=$indicationEnabled application_active=$applicationActive '
      'desired=$desired owned=$ownedEnabled system_enabled=$systemEnabled '
      'os_status=$lastOsStatus target=${targetIdentity == null ? 0 : 1} '
      'terminal_echo=${terminalEchoEnabled == null
          ? 'unavailable'
          : terminalEchoEnabled!
          ? 'on'
          : 'off'} '
      'failed=${failure != null}';

  bool hasSameProjection(TerminalSecureKeyboardEntryStatus other) =>
      mode == other.mode &&
      manualRequested == other.manualRequested &&
      automaticEnabled == other.automaticEnabled &&
      indicationEnabled == other.indicationEnabled &&
      applicationActive == other.applicationActive &&
      desired == other.desired &&
      ownedEnabled == other.ownedEnabled &&
      systemEnabled == other.systemEnabled &&
      lastOsStatus == other.lastOsStatus &&
      targetIdentity == other.targetIdentity &&
      terminalEchoEnabled == other.terminalEchoEnabled &&
      failure.runtimeType == other.failure.runtimeType &&
      failure?.toString() == other.failure?.toString();
}

/// Aggregates manual intent and the focused pane's content-free ECHO state.
///
/// Manual intent remains retained while AppKit is inactive so the balanced
/// native owner can yield and reacquire. Automatic intent is scoped to one
/// active, focused, live target and is released for unknown or enabled ECHO.
final class TerminalSecureKeyboardEntryController {
  TerminalSecureKeyboardEntryController({
    required TerminalSecureKeyboardEntryLease lease,
    bool automaticEnabled = true,
    bool indicationEnabled = true,
    bool applicationActive = true,
    this.onStatusChanged,
    this.onFailure,
  }) : _lease = lease,
       _automaticEnabled = automaticEnabled,
       _indicationEnabled = indicationEnabled,
       _applicationActive = applicationActive,
       _status = TerminalSecureKeyboardEntryStatus(
         mode: TerminalSecureKeyboardEntryMode.disabled,
         manualRequested: false,
         automaticEnabled: automaticEnabled,
         indicationEnabled: indicationEnabled,
         applicationActive: applicationActive,
         desired: false,
         ownedEnabled: false,
         systemEnabled: false,
         lastOsStatus: 0,
         targetIdentity: null,
         terminalEchoEnabled: null,
         failure: null,
       );

  final TerminalSecureKeyboardEntryLease _lease;
  final TerminalSecureKeyboardEntryStatusObserver? onStatusChanged;
  final TerminalSecureKeyboardEntryFailureObserver? onFailure;

  bool _automaticEnabled;
  bool _indicationEnabled;
  bool _applicationActive;
  bool _manualRequested = false;
  bool _isDisposed = false;
  TerminalSecureKeyboardEntryTarget? _indicatorTarget;
  TerminalSecureKeyboardEntryIndicator _indicator =
      TerminalSecureKeyboardEntryIndicator.hidden;
  TerminalSecureKeyboardEntryStatus _status;

  bool get isDisposed => _isDisposed;
  bool get manualRequested => _manualRequested;
  TerminalSecureKeyboardEntryStatus get status => _status;

  void applyConfiguration({
    required bool automaticEnabled,
    required bool indicationEnabled,
    TerminalSecureKeyboardEntryTarget? target,
  }) {
    _ensureAlive();
    _automaticEnabled = automaticEnabled;
    _indicationEnabled = indicationEnabled;
    reconcile(target);
  }

  void setApplicationActive(
    bool isActive, {
    TerminalSecureKeyboardEntryTarget? target,
  }) {
    _ensureAlive();
    _applicationActive = isActive;
    reconcile(target);
  }

  void toggleManual({TerminalSecureKeyboardEntryTarget? target}) {
    _ensureAlive();
    _manualRequested = !_manualRequested;
    reconcile(target);
  }

  void reconcile([TerminalSecureKeyboardEntryTarget? target]) {
    _ensureAlive();
    Object? failure;
    StackTrace? failureStackTrace;

    void capture(Object error, StackTrace stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }

    final bool automaticDesired =
        _automaticEnabled &&
        _applicationActive &&
        target != null &&
        target.isFocused &&
        target.isLive &&
        target.terminalEchoEnabled == false;
    final bool desired = _manualRequested || automaticDesired;
    TerminalSecureKeyboardEntryLeaseSnapshot snapshot =
        const TerminalSecureKeyboardEntryLeaseSnapshot(
          desired: false,
          ownedEnabled: false,
          systemEnabled: false,
          lastOsStatus: 0,
        );
    var snapshotAvailable = false;
    try {
      snapshot = _lease.snapshot();
      snapshotAvailable = true;
      final bool retryFailedAcquire =
          desired &&
          _applicationActive &&
          !snapshot.ownedEnabled &&
          snapshot.lastOsStatus != 0;
      final bool retryFailedRelease = !desired && snapshot.ownedEnabled;
      if (snapshot.desired != desired ||
          retryFailedAcquire ||
          retryFailedRelease) {
        _lease.setDesired(desired);
        snapshot = _lease.snapshot();
      }
    } on Object catch (error, stackTrace) {
      capture(error, stackTrace);
      try {
        snapshot = _lease.snapshot();
        snapshotAvailable = true;
      } on Object catch (snapshotError, snapshotStackTrace) {
        capture(snapshotError, snapshotStackTrace);
      }
    }

    final TerminalSecureKeyboardEntryIndicator nextIndicator =
        failure == null &&
            _indicationEnabled &&
            _applicationActive &&
            target != null &&
            target.isFocused &&
            target.isLive &&
            snapshot.ownedEnabled
        ? _manualRequested
              ? TerminalSecureKeyboardEntryIndicator.manual
              : automaticDesired
              ? TerminalSecureKeyboardEntryIndicator.automatic
              : TerminalSecureKeyboardEntryIndicator.hidden
        : TerminalSecureKeyboardEntryIndicator.hidden;
    _projectIndicator(target, nextIndicator, capture);

    final TerminalSecureKeyboardEntryMode mode = failure != null
        ? TerminalSecureKeyboardEntryMode.failed
        : _manualRequested
        ? TerminalSecureKeyboardEntryMode.manual
        : automaticDesired
        ? TerminalSecureKeyboardEntryMode.automatic
        : TerminalSecureKeyboardEntryMode.disabled;
    final bool statusChanged = _publish(
      TerminalSecureKeyboardEntryStatus(
        mode: mode,
        manualRequested: _manualRequested,
        automaticEnabled: _automaticEnabled,
        indicationEnabled: _indicationEnabled,
        applicationActive: _applicationActive,
        desired: snapshotAvailable ? snapshot.desired : desired,
        ownedEnabled: snapshot.ownedEnabled,
        systemEnabled: snapshot.systemEnabled,
        lastOsStatus: snapshot.lastOsStatus,
        targetIdentity: target?.identity,
        terminalEchoEnabled: target?.terminalEchoEnabled,
        failure: failure,
      ),
    );
    if (failure != null && statusChanged) {
      onFailure?.call(failure!, failureStackTrace!);
    }
  }

  void _projectIndicator(
    TerminalSecureKeyboardEntryTarget? target,
    TerminalSecureKeyboardEntryIndicator next,
    void Function(Object error, StackTrace stackTrace) capture,
  ) {
    final TerminalSecureKeyboardEntryTarget? previous = _indicatorTarget;
    if (previous != null &&
        (previous.identity != target?.identity ||
            next == TerminalSecureKeyboardEntryIndicator.hidden)) {
      try {
        previous.setIndicator(TerminalSecureKeyboardEntryIndicator.hidden);
        _indicatorTarget = null;
        _indicator = TerminalSecureKeyboardEntryIndicator.hidden;
      } on Object catch (error, stackTrace) {
        capture(error, stackTrace);
        return;
      }
    }
    if (next == TerminalSecureKeyboardEntryIndicator.hidden || target == null) {
      return;
    }
    if (_indicatorTarget != null &&
        _indicatorTarget!.identity == target.identity &&
        _indicator == next) {
      _indicatorTarget = target;
      return;
    }
    try {
      target.setIndicator(next);
      _indicatorTarget = target;
      _indicator = next;
    } on Object catch (error, stackTrace) {
      capture(error, stackTrace);
    }
  }

  bool _publish(TerminalSecureKeyboardEntryStatus next) {
    if (_status.hasSameProjection(next)) return false;
    _status = next;
    onStatusChanged?.call(next);
    return true;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    Object? failure;
    StackTrace? failureStackTrace;

    void capture(Object error, StackTrace stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }

    final TerminalSecureKeyboardEntryTarget? target = _indicatorTarget;
    _indicatorTarget = null;
    _indicator = TerminalSecureKeyboardEntryIndicator.hidden;
    if (target != null) {
      try {
        target.setIndicator(TerminalSecureKeyboardEntryIndicator.hidden);
      } on Object catch (error, stackTrace) {
        capture(error, stackTrace);
      }
    }
    try {
      _lease.setDesired(false);
    } on Object catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    try {
      _lease.dispose();
    } on Object catch (error, stackTrace) {
      capture(error, stackTrace);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStackTrace!);
    }
  }

  void _ensureAlive() {
    if (_isDisposed) {
      throw StateError('Secure Keyboard Entry controller is disposed');
    }
  }
}

const ViewBadge terminalSecureKeyboardEntryAutomaticBadge = ViewBadge(
  text: 'SECURE AUTO',
  accessibilityLabel: 'Secure Keyboard Entry — Automatic',
  accessibilityHelp: 'Keyboard input is protected from other applications.',
);

const ViewBadge terminalSecureKeyboardEntryManualBadge = ViewBadge(
  text: 'SECURE MANUAL',
  accessibilityLabel: 'Secure Keyboard Entry — Manual',
  accessibilityHelp: 'Keyboard input is protected from other applications.',
);

ViewBadge? appKitSecureInputBadge(
  TerminalSecureKeyboardEntryIndicator indicator, {
  TerminalLocalization? localization,
}) => switch (indicator) {
  TerminalSecureKeyboardEntryIndicator.hidden => null,
  TerminalSecureKeyboardEntryIndicator.automatic => _secureInputBadge(
    automatic: true,
    localization: localization,
  ),
  TerminalSecureKeyboardEntryIndicator.manual => _secureInputBadge(
    automatic: false,
    localization: localization,
  ),
};

ViewBadge _secureInputBadge({
  required bool automatic,
  required TerminalLocalization? localization,
}) {
  final TerminalLocalization messages =
      localization ?? TerminalLocalization.english;
  if (messages.language == TerminalLanguage.english) {
    return automatic
        ? terminalSecureKeyboardEntryAutomaticBadge
        : terminalSecureKeyboardEntryManualBadge;
  }
  return ViewBadge(
    text: messages.secureBadgeText(automatic: automatic),
    accessibilityLabel: messages.secureBadgeLabel(automatic: automatic),
    accessibilityHelp: messages.secureBadgeHelp,
  );
}
