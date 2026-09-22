import 'package:dart_terminal/src/terminal_runtime_test_activation.dart';

void main() => runTerminalRuntimeTestActivationTests();

void runTerminalRuntimeTestActivationTests() {
  final List<String> arguments = runtimeTestActivationArguments(
    processId: 1234,
    executablePath: '/repo/build/runtime/arm64/DartTerminal.app/Contents/MacOS/dart_terminal',
  );
  _expect(
    arguments.last ==
            '/repo/build/runtime/arm64/DartTerminal.app/Contents/MacOS/dart_terminal' &&
        arguments[arguments.length - 2] == '1234' &&
        arguments.contains('JavaScript') &&
        arguments.contains('--') &&
        arguments.every((String value) => value != '-a' && value != '-b'),
    'activation identifies only the running candidate PID and executable',
  );
  final String script = arguments[3];
  _expect(
    script.contains('runningApplicationWithProcessIdentifier') &&
        script.contains('executableURL.path') &&
        !script.contains('bundleIdentifier') &&
        !script.contains('launchApplication'),
    'activation never resolves an installed app by bundle ID or launches it',
  );
  _expectThrows(
    () => runtimeTestActivationArguments(
      processId: 0,
      executablePath: '/tmp/candidate',
    ),
    'invalid PID is rejected',
  );
  _expectThrows(
    () => runtimeTestActivationArguments(
      processId: 1234,
      executablePath: 'DartTerminal.app',
    ),
    'relative app names are rejected',
  );
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError(description);
}
