import 'native_backend.dart';

abstract final class TerminalAppIntentsMacosLimits {
  static const int maximumPendingCommands = 16;
  static const Duration maximumCommandTimeout = Duration(minutes: 5);
}

enum TerminalAppIntentAction {
  newWindow(1),
  newTab(2),
  toggleQuickTerminal(3);

  const TerminalAppIntentAction(this.nativeValue);

  final int nativeValue;

  static TerminalAppIntentAction? fromNative(int value) {
    for (final TerminalAppIntentAction action in values) {
      if (action.nativeValue == value) return action;
    }
    return null;
  }
}

enum TerminalAppIntentsMacosCommandDisposition {
  completed(0),
  rejected(1),
  failed(2);

  const TerminalAppIntentsMacosCommandDisposition(this.nativeValue);

  final int nativeValue;
}

final class TerminalAppIntentsMacosCommand {
  const TerminalAppIntentsMacosCommand._({
    required this.operationId,
    required this.generation,
    required this.action,
  });

  final int operationId;
  final int generation;
  final TerminalAppIntentAction action;
}

final class TerminalAppIntentsMacosSummary {
  const TerminalAppIntentsMacosSummary({
    required this.generation,
    required this.queuedCommandCount,
    required this.pendingCommandCount,
    required this.acceptedCommandCount,
    required this.resolvedCommandCount,
    required this.rejectedCommandCount,
    required this.timedOutCommandCount,
    required this.started,
    required this.enabled,
  });

  final int generation;
  final int queuedCommandCount;
  final int pendingCommandCount;
  final int acceptedCommandCount;
  final int resolvedCommandCount;
  final int rejectedCommandCount;
  final int timedOutCommandCount;
  final bool started;
  final bool enabled;
}

final class TerminalAppIntentsMacosException implements Exception {
  const TerminalAppIntentsMacosException({
    required this.operation,
    required this.status,
  });

  final String operation;
  final int status;

  @override
  String toString() =>
      'TerminalAppIntentsMacosException($operation, status=$status)';
}

final class TerminalAppIntentsMacosSession {
  factory TerminalAppIntentsMacosSession.withBindings(
    TerminalAppIntentsMacosBindings bindings, {
    int maximumPendingCommands =
        TerminalAppIntentsMacosLimits.maximumPendingCommands,
    Duration commandTimeout = const Duration(seconds: 30),
  }) {
    RangeError.checkValueInInterval(
      maximumPendingCommands,
      1,
      TerminalAppIntentsMacosLimits.maximumPendingCommands,
      'maximumPendingCommands',
    );
    if (commandTimeout <= Duration.zero ||
        commandTimeout > TerminalAppIntentsMacosLimits.maximumCommandTimeout) {
      throw ArgumentError.value(commandTimeout, 'commandTimeout');
    }
    _requireOk(
      'sessionStart',
      bindings.sessionStart(
        maximumPendingCommands,
        commandTimeout.inMicroseconds,
      ),
    );
    return TerminalAppIntentsMacosSession._(bindings);
  }

  TerminalAppIntentsMacosSession._(this._bindings);

  final TerminalAppIntentsMacosBindings _bindings;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void setEnabled(bool enabled) {
    _requireLive();
    _requireOk('setEnabled', _bindings.setEnabled(enabled));
  }

  TerminalAppIntentsMacosCommand? takeCommand() {
    _requireLive();
    final TerminalAppIntentsMacosTakeResult result = _bindings.takeCommand();
    if (result.status == nativeStatusNotFound) return null;
    _requireOk('takeCommand', result.status);
    final int? operationId = result.operationId;
    final int? generation = result.generation;
    final TerminalAppIntentAction? action = TerminalAppIntentAction.fromNative(
      result.action ?? -1,
    );
    if (operationId == null ||
        operationId <= 0 ||
        generation == null ||
        generation <= 0 ||
        action == null) {
      throw const TerminalAppIntentsMacosException(
        operation: 'takeCommand.result',
        status: nativeStatusInternal,
      );
    }
    return TerminalAppIntentsMacosCommand._(
      operationId: operationId,
      generation: generation,
      action: action,
    );
  }

  void completeCommand(
    TerminalAppIntentsMacosCommand command,
    TerminalAppIntentsMacosCommandDisposition disposition,
  ) {
    _requireLive();
    _requireOk(
      'completeCommand',
      _bindings.completeCommand(
        command.operationId,
        command.generation,
        disposition.nativeValue,
      ),
    );
  }

  TerminalAppIntentsMacosSummary get summary {
    _requireLive();
    return _bindings.summary();
  }

  void dispose() {
    if (_disposed) return;
    _requireOk('sessionShutdown', _bindings.sessionShutdown());
    _disposed = true;
  }

  void _requireLive() {
    if (_disposed) {
      throw StateError('terminal App Intents native session is disposed');
    }
  }

  static void _requireOk(String operation, int status) {
    if (status != nativeStatusOk) {
      throw TerminalAppIntentsMacosException(
        operation: operation,
        status: status,
      );
    }
  }
}
