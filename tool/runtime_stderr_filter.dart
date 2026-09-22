/// Returns stderr that the runtime acceptance harness must still reject.
///
/// macOS occasionally emits this one Input Method Kit diagnostic from its
/// process-global machinery while the application otherwise exits cleanly.
/// It has no application stack, and it is not a terminal input observation.
/// Only one exact, timestamped system line is ignored per launch; every other
/// stderr byte remains subject to the existing acceptance checks.
String unexpectedRuntimeStderrText(String raw) {
  var ignoredImkDiagnostic = false;
  final List<String> retained = <String>[];
  for (final String line in raw.split('\n')) {
    final String candidate = line.endsWith('\r')
        ? line.substring(0, line.length - 1)
        : line;
    if (!ignoredImkDiagnostic && _imkDiagnostic.hasMatch(candidate)) {
      ignoredImkDiagnostic = true;
      continue;
    }
    retained.add(line);
  }
  return retained.join('\n');
}

final RegExp _imkDiagnostic = RegExp(
  r'^[0-9]{4}-[0-9]{2}-[0-9]{2} '
  r'[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} '
  r'dart_terminal\[[0-9]+:[0-9]+\] '
  r'error messaging the mach port for IMKCFRunLoopWakeUpReliable$',
);
