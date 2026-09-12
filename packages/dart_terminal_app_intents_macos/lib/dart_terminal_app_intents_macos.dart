/// Bounded App Intents support for terminal applications on macOS.
library;

import 'dart:ffi';

import 'package:dart_macos_runtime/dart_macos_runtime.dart';

import 'src/api.dart';
import 'src/native_backend.dart';

export 'src/api.dart'
    show
        TerminalAppIntentAction,
        TerminalAppIntentsMacosCommand,
        TerminalAppIntentsMacosCommandDisposition,
        TerminalAppIntentsMacosException,
        TerminalAppIntentsMacosLimits,
        TerminalAppIntentsMacosSession,
        TerminalAppIntentsMacosSummary;

const String terminalAppIntentsMacosLibraryName =
    'libdart_terminal_app_intents_macos.dylib';
const String terminalAppIntentsMacosModuleName = 'DartTerminalAppIntents';
const String terminalAppIntentsMacosSource = 'native/TerminalAppIntents.swift';

abstract final class TerminalAppIntentsMacos {
  static TerminalAppIntentsMacosSession open({
    int maximumPendingCommands =
        TerminalAppIntentsMacosLimits.maximumPendingCommands,
    Duration commandTimeout = const Duration(seconds: 30),
  }) {
    final String path = MacosRuntime.bundleFrameworkPath(
      terminalAppIntentsMacosLibraryName,
    );
    return TerminalAppIntentsMacosSession.withBindings(
      FfiTerminalAppIntentsMacosBindings(DynamicLibrary.open(path)),
      maximumPendingCommands: maximumPendingCommands,
      commandTimeout: commandTimeout,
    );
  }
}
