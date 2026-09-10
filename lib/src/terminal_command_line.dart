import 'terminal_config.dart';
import 'terminal_configuration_reference.dart';
import 'terminal_effective_config.dart';

enum TerminalEarlyExitMode { help, showConfig }

final class TerminalEarlyExitResult {
  const TerminalEarlyExitResult({
    required this.mode,
    required this.standardOutput,
  });

  final TerminalEarlyExitMode mode;
  final String standardOutput;
}

/// Resolves process modes that must complete before application ownership.
final class TerminalEarlyExitResolver {
  TerminalEarlyExitResolver({
    TerminalConfigSchema? schema,
    TerminalConfigFileSystem? fileSystem,
    TerminalConfigurationReference? reference,
    TerminalEffectiveConfigFormatter? effectiveFormatter,
  }) : schema = schema ?? TerminalProductConfigSchema.instance,
       fileSystem = fileSystem,
       _reference = reference,
       _effectiveFormatter = effectiveFormatter;

  final TerminalConfigSchema schema;
  final TerminalConfigFileSystem? fileSystem;
  final TerminalConfigurationReference? _reference;
  final TerminalEffectiveConfigFormatter? _effectiveFormatter;

  TerminalEarlyExitResult? resolve(
    List<String> arguments, {
    Map<String, String>? environment,
    String? currentDirectory,
  }) {
    final int helpCount = _count(arguments, '--help');
    final int showConfigCount = _count(arguments, '--show-config');
    if (helpCount == 0 && showConfigCount == 0) return null;
    if (helpCount > 1) {
      throw const FormatException('--help may only be supplied once');
    }
    if (showConfigCount > 1) {
      throw const FormatException('--show-config may only be supplied once');
    }
    if (helpCount == 1 && showConfigCount == 1) {
      throw const FormatException(
        '--help cannot be combined with --show-config',
      );
    }
    if (helpCount == 1) {
      if (arguments.length != 1) {
        throw const FormatException(
          '--help cannot be combined with other arguments',
        );
      }
      return TerminalEarlyExitResult(
        mode: TerminalEarlyExitMode.help,
        standardOutput:
            (_reference ?? TerminalConfigurationReference(schema: schema))
                .generateUsage(),
      );
    }

    final TerminalConfigResolution resolution =
        TerminalConfigLoader(schema: schema, fileSystem: fileSystem).resolve(
          arguments,
          environment: environment,
          currentDirectory: currentDirectory,
        );
    if (resolution.remainingArguments.length != 1 ||
        resolution.remainingArguments.single != '--show-config') {
      final String unsupported = resolution.remainingArguments.firstWhere(
        (String argument) => argument != '--show-config',
        orElse: () => '--show-config',
      );
      throw FormatException(
        '--show-config cannot be combined with application option: '
        '$unsupported',
      );
    }
    return TerminalEarlyExitResult(
      mode: TerminalEarlyExitMode.showConfig,
      standardOutput:
          (_effectiveFormatter ?? TerminalEffectiveConfigFormatter()).format(
            resolution.snapshot,
          ),
    );
  }

  static int _count(List<String> arguments, String expected) =>
      arguments.where((String argument) => argument == expected).length;
}
