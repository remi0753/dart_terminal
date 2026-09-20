import 'dart:io';

import '../lib/src/terminal_config.dart';
import '../lib/src/terminal_configuration_reference.dart';

const String configurationReferencePath =
    'docs/reference/configuration-and-command-line.md';

final class ConfigurationReferenceException implements Exception {
  const ConfigurationReferenceException(this.message);

  final String message;

  @override
  String toString() => 'ConfigurationReferenceException: $message';
}

String generateConfigurationReference() =>
    TerminalConfigurationReference().generateMarkdown();

bool configurationReferenceIsFresh(File output) =>
    output.existsSync() &&
    output.readAsStringSync() == generateConfigurationReference();

void validateConfigurationReferenceSource(
  String source, {
  String? expectedSource,
}) {
  if (source != (expectedSource ?? generateConfigurationReference())) {
    throw const ConfigurationReferenceException(
      'configuration/command-line reference is stale',
    );
  }
}

String configurationReferencePassLine() {
  final List<TerminalConfigOptionBase> options = TerminalProductConfigSchema
      .instance
      .publicOptions
      .toList(growable: false);
  final int live = options
      .where(
        (TerminalConfigOptionBase option) =>
            option.applicationPolicy == TerminalConfigApplicationPolicy.live,
      )
      .length;
  final int repeatable = options
      .where((TerminalConfigOptionBase option) => option.isRepeatable)
      .length;
  final int nextLaunch = options
      .where(
        (TerminalConfigOptionBase option) =>
            option.applicationPolicy ==
            TerminalConfigApplicationPolicy.nextLaunch,
      )
      .length;
  return 'CONFIGURATION_REFERENCE_CHECK_PASS options=${options.length} '
      'live=$live new_session=${options.length - live - nextLaunch} '
      'next_launch=$nextLaunch '
      'repeatable=$repeatable';
}

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != '--generate' && arguments.single != '--check')) {
    stderr.writeln(
      'CONFIGURATION_REFERENCE_FAIL usage: '
      'dart run tool/generate_configuration_reference.dart '
      '--generate|--check',
    );
    exitCode = 64;
    return;
  }
  final Directory repositoryRoot = File.fromUri(Platform.script)
      .absolute
      .parent
      .parent;
  final File output = File.fromUri(
    repositoryRoot.uri.resolve(configurationReferencePath),
  );
  try {
    if (arguments.single == '--generate') {
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(generateConfigurationReference(), flush: true);
      stdout.writeln(
        'CONFIGURATION_REFERENCE_GENERATED path=$configurationReferencePath',
      );
      return;
    }
    if (!configurationReferenceIsFresh(output)) {
      stderr.writeln(
        'CONFIGURATION_REFERENCE_STALE path=$configurationReferencePath; '
        'regenerate with `make configuration-reference`',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(configurationReferencePassLine());
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
