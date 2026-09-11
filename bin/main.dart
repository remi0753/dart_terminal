import 'dart:async';
import 'dart:io';

import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

const int _runtimeUsageExitCode = 64;

@pragma('vm:entry-point')
void main(List<String> arguments) {
  MacosRuntime.validateHost();
  MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStarting);
  try {
    final valueAvailabilityValidator =
        TerminalMacosConfigValueAvailabilityValidator(
          fontCatalogInitializer: TerminalRendererMacos.initialize,
        );
    final TerminalEarlyExitResult? earlyExit = TerminalEarlyExitResolver(
      valueAvailabilityValidator: valueAvailabilityValidator,
    ).resolve(arguments);
    if (earlyExit != null) {
      stdout.write(earlyExit.standardOutput);
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStopped);
      MacosRuntime.requestTermination(exitCode: 0);
      return;
    }
    final TerminalOptions options = TerminalOptions.parse(
      arguments,
      configValueAvailabilityValidator: valueAvailabilityValidator,
    );
    for (final TerminalConfigDiagnostic diagnostic
        in options.configurationDiagnostics) {
      stderr.writeln(diagnostic.format());
    }
    if (options.runtimeLifecycleScenario ==
        RuntimeLifecycleScenario.rootStartupFailure) {
      stdout.writeln(
        const RuntimeLifecycleObservation(
          event: 'root-start',
          generation: 0,
        ).machineLine(RuntimeLifecycleScenario.rootStartupFailure),
      );
      stderr.writeln('RUNTIME_LIFECYCLE_FATAL class=root-startup status=70');
      throw StateError('requested synchronous root startup failure');
    }
    unawaited(TerminalApplication(options: options).run());
  } on FormatException catch (error) {
    stderr.writeln('Argument error: ${error.message}');
    stderr.writeln(terminalUsage);
    exitCode = 64;
    MacosRuntime.requestTermination(exitCode: _runtimeUsageExitCode);
  }
}
