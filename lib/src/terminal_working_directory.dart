import 'dart:io';

/// Resolves the working directory for a fresh terminal with no explicit cwd.
///
/// LaunchServices may start a bundled macOS application with `/` as the
/// process working directory. That process detail must not leak into the
/// user's first shell. A valid launch-environment HOME is the stable product
/// default; the process cwd remains a fail-safe for malformed environments.
String resolveTerminalDefaultWorkingDirectory({
  required Map<String, String> environment,
  required String processWorkingDirectory,
}) {
  final String? homePath = environment['HOME'];
  if (homePath != null && homePath.isNotEmpty) {
    final Directory home = Directory(homePath);
    if (home.isAbsolute && home.existsSync()) {
      return home.absolute.path;
    }
  }
  return Directory(processWorkingDirectory).absolute.path;
}
