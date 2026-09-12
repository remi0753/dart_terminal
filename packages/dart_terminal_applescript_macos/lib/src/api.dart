import 'dart:typed_data';

import 'native_backend.dart';

abstract final class TerminalAppleScriptMacosLimits {
  static const int maximumWindows = 32;
  static const int maximumTabsPerWindow = 64;
  static const int maximumTerminals = 64;
  static const int maximumPendingCommands = 16;
  static const int maximumSnapshotBytes = 4 * 1024 * 1024;
  static const int maximumCommandBytes = 64 * 1024 * 1024 + 4096;
  static const int maximumObjectIdBytes = 63;
  static const Duration maximumCommandTimeout = Duration(minutes: 5);
}

enum TerminalAppleScriptMacosCommandDisposition {
  completed(0),
  confirmationRequired(1),
  disabled(2),
  notFound(3),
  busy(4),
  rejected(5),
  failed(6),
  timedOut(7),
  disposed(8);

  const TerminalAppleScriptMacosCommandDisposition(this.nativeValue);

  final int nativeValue;
}

final class TerminalAppleScriptMacosSummary {
  const TerminalAppleScriptMacosSummary({
    required this.generation,
    required this.windowCount,
    required this.tabCount,
    required this.terminalCount,
    required this.queuedCommandCount,
    required this.pendingCommandCount,
    required this.resumedCommandCount,
    required this.rejectedCommandCount,
    required this.started,
    required this.enabled,
  });

  final int generation;
  final int windowCount;
  final int tabCount;
  final int terminalCount;
  final int queuedCommandCount;
  final int pendingCommandCount;
  final int resumedCommandCount;
  final int rejectedCommandCount;
  final bool started;
  final bool enabled;
}

final class TerminalAppleScriptMacosException implements Exception {
  const TerminalAppleScriptMacosException({
    required this.operation,
    required this.status,
  });

  final String operation;
  final int status;

  @override
  String toString() =>
      'TerminalAppleScriptMacosException($operation, status=$status)';
}

final class TerminalAppleScriptMacosSession {
  factory TerminalAppleScriptMacosSession.withBindings(
    TerminalAppleScriptMacosBindings bindings, {
    int maximumPendingCommands =
        TerminalAppleScriptMacosLimits.maximumPendingCommands,
    Duration commandTimeout = const Duration(seconds: 30),
  }) {
    RangeError.checkValueInInterval(
      maximumPendingCommands,
      1,
      TerminalAppleScriptMacosLimits.maximumPendingCommands,
      'maximumPendingCommands',
    );
    if (commandTimeout <= Duration.zero ||
        commandTimeout > TerminalAppleScriptMacosLimits.maximumCommandTimeout) {
      throw ArgumentError.value(commandTimeout, 'commandTimeout');
    }
    _requireOk(
      'sessionStart',
      bindings.sessionStart(
        maximumPendingCommands,
        commandTimeout.inMicroseconds,
      ),
    );
    return TerminalAppleScriptMacosSession._(bindings);
  }

  TerminalAppleScriptMacosSession._(this._bindings);

  final TerminalAppleScriptMacosBindings _bindings;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void publishSnapshot(Uint8List bytes) {
    _requireLive();
    if (bytes.isEmpty ||
        bytes.length > TerminalAppleScriptMacosLimits.maximumSnapshotBytes) {
      throw ArgumentError.value(bytes.length, 'bytes');
    }
    _requireOk('publishSnapshot', _bindings.publishSnapshot(bytes));
  }

  Uint8List? takeCommand() {
    _requireLive();
    final TerminalAppleScriptMacosTakeResult result = _bindings.takeCommand();
    if (result.status == nativeStatusNotFound) return null;
    _requireOk('takeCommand', result.status);
    final Uint8List? bytes = result.bytes;
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > TerminalAppleScriptMacosLimits.maximumCommandBytes) {
      throw const TerminalAppleScriptMacosException(
        operation: 'takeCommand.length',
        status: nativeStatusInternal,
      );
    }
    return Uint8List.fromList(bytes);
  }

  void completeCommand(
    int operationId,
    TerminalAppleScriptMacosCommandDisposition disposition, {
    String? objectId,
  }) {
    _requireLive();
    if (operationId <= 0) {
      throw RangeError.value(operationId, 'operationId');
    }
    if (objectId != null &&
        (objectId.isEmpty ||
            objectId.codeUnits.length >
                TerminalAppleScriptMacosLimits.maximumObjectIdBytes ||
            objectId.codeUnits.any((int unit) => unit > 0x7f))) {
      throw ArgumentError.value(objectId, 'objectId');
    }
    _requireOk(
      'completeCommand',
      _bindings.completeCommand(operationId, disposition.nativeValue, objectId),
    );
  }

  TerminalAppleScriptMacosSummary get summary {
    _requireLive();
    return _bindings.summary();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requireOk('sessionShutdown', _bindings.sessionShutdown());
  }

  void _requireLive() {
    if (_disposed) {
      throw StateError('terminal AppleScript native session is disposed');
    }
  }

  static void _requireOk(String operation, int status) {
    if (status != nativeStatusOk) {
      throw TerminalAppleScriptMacosException(
        operation: operation,
        status: status,
      );
    }
  }
}
