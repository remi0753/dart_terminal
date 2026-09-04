import 'dart:async';
import 'dart:io';

import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';

const int _runtimeUsageExitCode = 64;

@pragma('vm:entry-point')
void main(List<String> arguments) {
  MacosRuntime.validateHost();
  MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStarting);
  try {
    final TerminalOptions options = TerminalOptions.parse(arguments);
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
