import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_sha256.dart';

void main() => runTerminalShellIntegrationResourceTests();

void runTerminalShellIntegrationResourceTests() {
  _testReviewedContractAndResources();
  _testContractValidation();
  _testResourcePolicyTextAndInstalledSyntax();
  _testResourceCorruptionFailsClosed();
  _testSha256Oracle();
}

void _testResourcePolicyTextAndInstalledSyntax() {
  final Map<String, String> textByPath = <String, String>{
    for (final TerminalShellIntegrationFileRequirement required
        in TerminalShellIntegrationContract.requiredFiles)
      required.relativePath: File(
        'resources/shell-integration/${required.relativePath}',
      ).readAsStringSync(),
  };
  final String zshBootstrap =
      textByPath[TerminalShellIntegrationResources.zshBootstrapRelativePath]!;
  final String bash =
      textByPath[TerminalShellIntegrationResources
          .bashIntegrationRelativePath]!;
  final String fish =
      textByPath[TerminalShellIntegrationResources
          .fishIntegrationRelativePath]!;
  final String nushell =
      textByPath[TerminalShellIntegrationResources
          .nushellIntegrationRelativePath]!;
  for (final TerminalShellKind shell in TerminalShellKind.values) {
    final String integration = switch (shell) {
      TerminalShellKind.zsh =>
        textByPath[TerminalShellIntegrationResources
            .zshIntegrationRelativePath]!,
      TerminalShellKind.bash => bash,
      TerminalShellKind.fish => fish,
      TerminalShellKind.nushell => nushell,
    };
    _expect(
      integration.contains(
            TerminalShellIntegrationContract.markerEnvironment,
          ) &&
          integration.contains(
            TerminalShellIntegrationContract.versionEnvironment,
          ) &&
          integration.contains(shell.name),
      '${shell.name} resource publishes the versioned execution marker',
    );
  }
  _expect(
    zshBootstrap.contains('DART_TERMINAL_ZDOTDIR') &&
        zshBootstrap.contains('dart-terminal-integration.zsh') &&
        bash.contains('builtin set +o posix') &&
        bash.contains(r'$HOME/.bash_profile') &&
        fish.contains('DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR') &&
        fish.contains('string split :') &&
        nushell.contains('DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR') &&
        nushell.contains('export module dart_terminal'),
    'resources retain startup restoration and temporary XDG cleanup contracts',
  );

  for (final ({String executable, List<String> paths}) syntax
      in <({String executable, List<String> paths})>[
        (
          executable: '/bin/zsh',
          paths: <String>[
            TerminalShellIntegrationResources.zshBootstrapRelativePath,
            TerminalShellIntegrationResources.zshIntegrationRelativePath,
          ],
        ),
        (
          executable: '/bin/bash',
          paths: <String>[
            TerminalShellIntegrationResources.bashIntegrationRelativePath,
          ],
        ),
      ]) {
    for (final String path in syntax.paths) {
      final ProcessResult result = Process.runSync(syntax.executable, <String>[
        '-n',
        'resources/shell-integration/$path',
      ]);
      _expect(
        result.exitCode == 0,
        '${syntax.executable} rejects $path: ${result.stderr}',
      );
    }
  }
}

File _contractFile([Directory? root]) => File(
  '${(root ?? Directory.current).path}/${TerminalShellIntegrationContract.relativePath}',
);

void _testReviewedContractAndResources() {
  final File contractFile = _contractFile();
  final TerminalShellIntegrationContract contract =
      TerminalShellIntegrationContract.load(contractFile);
  final TerminalShellIntegrationResources resources = contract
      .validateResources(contractFile.parent);
  _expect(
    contract.files.length == 5 &&
        contract.files.fold<int>(
              0,
              (int total, TerminalShellIntegrationFileContract file) =>
                  total + file.byteLength,
            ) ==
            4545 &&
        resources.availableShells.length == 4 &&
        resources.rootPath == contractFile.parent.absolute.path &&
        contract.files.every(
          (TerminalShellIntegrationFileContract file) =>
              file.sha256.length == 64,
        ),
    'reviewed contract pins five resources covering all four shells',
  );
  _expectThrowsUnsupported(
    () => contract.files.add(contract.files.first),
    'contract resource list is immutable',
  );
}

void _testContractValidation() {
  final String fixture = _contractFile().readAsStringSync();
  _expectContractFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    'unsupported contract version',
  );
  _expectContractFailure(
    fixture.replaceFirst(
      '"marker_environment": "DART_TERMINAL_SHELL_INTEGRATION"',
      '"marker_environment": "OTHER"',
    ),
    'marker environment differs',
  );
  _expectContractFailure(
    fixture.replaceFirst('"path": "zsh/.zshenv"', '"path": "../.zshenv"'),
    'required path',
  );
  _expectContractFailure(
    fixture.replaceFirst('"shell": "zsh"', '"shell": "bash"'),
    'required order',
  );
  _expectContractFailure(
    fixture.replaceFirst(
      RegExp(r'"sha256": "[0-9a-f]{64}"'),
      '"sha256": "not-a-hash"',
    ),
    'lowercase SHA-256',
  );
  _expectContractFailure(
    fixture.replaceFirst('"files": [', '"unknown": true,\n  "files": ['),
    'keys differ',
  );
}

void _testResourceCorruptionFailsClosed() {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-shell-integration-',
  );
  try {
    final Directory resourceRoot = Directory(
      '${temporary.path}/resources/shell-integration',
    )..createSync(recursive: true);
    for (final TerminalShellIntegrationFileRequirement required
        in TerminalShellIntegrationContract.requiredFiles) {
      final File source = File(
        'resources/shell-integration/${required.relativePath}',
      );
      final File target = File('${resourceRoot.path}/${required.relativePath}');
      target.parent.createSync(recursive: true);
      source.copySync(target.path);
    }
    final File copiedContract = _contractFile(temporary);
    copiedContract.parent.createSync(recursive: true);
    _contractFile().copySync(copiedContract.path);
    final TerminalShellIntegrationContract contract =
        TerminalShellIntegrationContract.load(copiedContract);
    final File bash = File(
      '${resourceRoot.path}/${TerminalShellIntegrationResources.bashIntegrationRelativePath}',
    );
    bash.writeAsStringSync('${bash.readAsStringSync()}# changed\n');
    _expectResourceFailure(
      () => contract.validateResources(resourceRoot),
      'resource byte length differs',
    );
    bash.deleteSync();
    _expectResourceFailure(
      () => contract.validateResources(resourceRoot),
      'resource is missing',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _testSha256Oracle() {
  _expect(
    terminalSha256(utf8.encode('abc')) ==
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'runtime SHA-256 matches the published abc oracle',
  );
}

void _expectContractFailure(String source, String message) {
  _expectResourceFailure(
    () => TerminalShellIntegrationContract.parse(source),
    message,
  );
}

void _expectResourceFailure(void Function() operation, String message) {
  try {
    operation();
  } on TerminalShellIntegrationException catch (error) {
    _expect(
      error.message.contains(message),
      'expected "$message", got "${error.message}"',
    );
    return;
  }
  throw StateError(
    'shell resource expectation failed: expected failure containing "$message"',
  );
}

void _expectThrowsUnsupported(void Function() operation, String description) {
  try {
    operation();
  } on UnsupportedError {
    return;
  }
  throw StateError('shell resource expectation failed: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('shell resource expectation failed: $description');
  }
}
