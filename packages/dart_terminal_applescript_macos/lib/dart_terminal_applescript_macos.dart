/// Bounded native Cocoa Scripting support for terminal applications.
library;

import 'package:dart_macos_runtime/dart_macos_runtime.dart';

import 'src/api.dart';
import 'src/native_backend.dart';

export 'src/api.dart'
    show
        TerminalAppleScriptMacosCommandDisposition,
        TerminalAppleScriptMacosException,
        TerminalAppleScriptMacosLimits,
        TerminalAppleScriptMacosSession,
        TerminalAppleScriptMacosSummary;

const String terminalAppleScriptMacosCapabilityId =
    'dart_terminal_applescript_macos';

abstract final class TerminalAppleScriptMacos {
  static MacosNativeCapability? _capability;

  static bool get isInitialized => _capability != null;

  static void initialize() {
    _capability ??= MacosNativeCapability.load(
      terminalAppleScriptMacosCapabilityId,
    );
  }

  static TerminalAppleScriptMacosSession open({
    int maximumPendingCommands =
        TerminalAppleScriptMacosLimits.maximumPendingCommands,
    Duration commandTimeout = const Duration(seconds: 30),
  }) {
    if (_capability == null) {
      throw StateError('TerminalAppleScriptMacos.initialize() must be called');
    }
    return TerminalAppleScriptMacosSession.withBindings(
      FfiTerminalAppleScriptMacosBindings(),
      maximumPendingCommands: maximumPendingCommands,
      commandTimeout: commandTimeout,
    );
  }
}
