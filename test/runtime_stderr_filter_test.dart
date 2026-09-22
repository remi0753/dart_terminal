import '../tool/runtime_stderr_filter.dart';

void main() => runRuntimeStderrFilterTests();

void runRuntimeStderrFilterTests() {
  const String imk =
      '2026-09-22 14:01:22.828 dart_terminal[68267:16304334] '
      'error messaging the mach port for IMKCFRunLoopWakeUpReliable';
  _expect(unexpectedRuntimeStderrText('') == '', 'empty stderr stays empty');
  _expect(
    unexpectedRuntimeStderrText('$imk\n') == '',
    'one exact macOS IMK diagnostic does not fail acceptance',
  );
  _expect(
    unexpectedRuntimeStderrText('application failure\n$imk\n') ==
        'application failure\n',
    'application stderr remains visible beside system noise',
  );
  _expect(
    unexpectedRuntimeStderrText('$imk\n$imk\n') == '$imk\n',
    'repeated system diagnostics are not silently allowed',
  );
  _expect(
    unexpectedRuntimeStderrText('$imk additional detail\n') ==
            '$imk additional detail\n' &&
        unexpectedRuntimeStderrText(
              imk.replaceFirst('dart_terminal[', 'another_app['),
            ) !=
            '',
    'a different process or diagnostic suffix remains unexpected',
  );
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
