import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_differential_sha256.dart';

final class TerminalShellIntegrationCheckResult {
  const TerminalShellIntegrationCheckResult({
    required this.fileCount,
    required this.totalBytes,
    required this.generated,
  });

  final int fileCount;
  final int totalBytes;
  final bool generated;

  String machineLine() =>
      'TERMINAL_SHELL_INTEGRATION_RESOURCES_'
      '${generated ? 'GENERATE' : 'CHECK'}_PASS '
      'version=${TerminalShellIntegrationContract.integrationVersion} '
      'shells=${TerminalShellKind.values.length} files=$fileCount '
      'total_bytes=$totalBytes';
}

Future<TerminalShellIntegrationCheckResult> runTerminalShellIntegrationCheck({
  Directory? projectRoot,
  bool generate = false,
}) async {
  final Directory root = (projectRoot ?? Directory.current).absolute;
  final Directory resourceRoot = Directory(
    '${root.path}/resources/shell-integration',
  );
  final List<Map<String, Object?>> fileEntries = <Map<String, Object?>>[];
  var totalBytes = 0;
  for (final TerminalShellIntegrationFileRequirement required
      in TerminalShellIntegrationContract.requiredFiles) {
    final File file = File('${resourceRoot.path}/${required.relativePath}');
    _expect(file.existsSync(), 'resource is missing: ${required.relativePath}');
    _expect(
      FileSystemEntity.typeSync(file.path, followLinks: false) ==
          FileSystemEntityType.file,
      'resource must be a regular file: ${required.relativePath}',
    );
    final List<int> bytes = file.readAsBytesSync();
    _expect(
      bytes.isNotEmpty &&
          bytes.length <= TerminalShellIntegrationContract.maximumResourceBytes,
      'resource size is invalid: ${required.relativePath}',
    );
    totalBytes += bytes.length;
    fileEntries.add(<String, Object?>{
      'shell': required.shell.name,
      'path': required.relativePath,
      'bytes': bytes.length,
      'sha256': terminalDifferentialSha256(bytes),
    });
  }
  _expect(
    totalBytes <= TerminalShellIntegrationContract.maximumTotalResourceBytes,
    'total shell integration resource bytes exceed the contract',
  );
  final File contractFile = File(
    '${root.path}/${TerminalShellIntegrationContract.relativePath}',
  );
  if (generate) {
    final String encoded = const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{
          'format': TerminalShellIntegrationContract.format,
          'version': TerminalShellIntegrationContract.version,
          'integration_version':
              TerminalShellIntegrationContract.integrationVersion,
          'marker_environment':
              TerminalShellIntegrationContract.markerEnvironment,
          'version_environment':
              TerminalShellIntegrationContract.versionEnvironment,
          'files': fileEntries,
        });
    contractFile.writeAsStringSync('$encoded\n');
  }
  final TerminalShellIntegrationContract contract =
      TerminalShellIntegrationContract.load(contractFile);
  final TerminalShellIntegrationResources resources = contract
      .validateResources(resourceRoot);
  _expect(
    resources.availableShells.length == TerminalShellKind.values.length,
    'validated resources do not cover every supported shell',
  );
  _validateManifest(root);
  return TerminalShellIntegrationCheckResult(
    fileCount: contract.files.length,
    totalBytes: totalBytes,
    generated: generate,
  );
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1 ||
        (arguments.single != '--check' && arguments.single != '--generate')) {
      throw const TerminalShellIntegrationException(
        'usage: terminal_shell_integration.dart --check|--generate',
      );
    }
    final TerminalShellIntegrationCheckResult result =
        await runTerminalShellIntegrationCheck(
          generate: arguments.single == '--generate',
        );
    stdout.writeln(result.machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_SHELL_INTEGRATION_RESOURCES_FAIL $error');
    exitCode = 1;
  }
}

void _validateManifest(Directory root) {
  final Map<String, Object?> manifest = jsonDecode(
    File('${root.path}/macos_application.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final List<String> resources = (manifest['resources']! as List<Object?>)
      .cast<String>();
  final Set<String> expected = <String>{
    'en.lproj/InfoPlist.strings',
    'en.lproj/Localizable.strings',
    'en.lproj/AppShortcuts.strings',
    'en.lproj/ServicesMenu.strings',
    'ja.lproj/InfoPlist.strings',
    'ja.lproj/Localizable.strings',
    'ja.lproj/AppShortcuts.strings',
    'ja.lproj/ServicesMenu.strings',
    'resources/terminfo/78/xterm-256color',
    TerminalShellIntegrationContract.relativePath,
    for (final TerminalShellIntegrationFileRequirement required
        in TerminalShellIntegrationContract.requiredFiles)
      'resources/shell-integration/${required.relativePath}',
  };
  _expect(
    resources.length == resources.toSet().length &&
        resources.toSet().difference(expected).isEmpty &&
        expected.difference(resources.toSet()).isEmpty,
    'application manifest resources differ from the shell/terminfo contract',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw TerminalShellIntegrationException(message);
  }
}
