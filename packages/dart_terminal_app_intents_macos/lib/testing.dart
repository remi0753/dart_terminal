import 'dart:ffi';

import 'package:dart_macos_runtime/dart_macos_runtime.dart';

import 'dart_terminal_app_intents_macos.dart'
    show terminalAppIntentsMacosLibraryName;
import 'src/native_backend.dart';

export 'src/native_backend.dart'
    show
        FfiTerminalAppIntentsMacosBindings,
        TerminalAppIntentsMacosBindings,
        TerminalAppIntentsMacosSelfAutomation,
        TerminalAppIntentsMacosTakeResult,
        nativeStatusInternal,
        nativeStatusNotFound,
        nativeStatusOk;

/// Opens the already-staged App Intents image for packaged self-acceptance.
TerminalAppIntentsMacosSelfAutomation
openTerminalAppIntentsMacosSelfAutomation() =>
    TerminalAppIntentsMacosSelfAutomation.fromLibrary(
      DynamicLibrary.open(
        MacosRuntime.bundleFrameworkPath(terminalAppIntentsMacosLibraryName),
      ),
    );
