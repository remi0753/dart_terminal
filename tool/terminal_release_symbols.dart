import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main(List<String> arguments) async {
  try {
    String? applicationPath;
    String? outputPath;
    for (final String argument in arguments) {
      if (argument.startsWith('--application=')) {
        if (applicationPath != null) {
          throw const TerminalReleaseSymbolsException(
            'duplicate-application-option',
          );
        }
        applicationPath = argument.substring('--application='.length);
      } else if (argument.startsWith('--output=')) {
        if (outputPath != null) {
          throw const TerminalReleaseSymbolsException(
            'duplicate-output-option',
          );
        }
        outputPath = argument.substring('--output='.length);
      } else {
        throw const TerminalReleaseSymbolsException('unknown-option');
      }
    }
    if (applicationPath == null || outputPath == null) {
      throw const TerminalReleaseSymbolsException('required-option-missing');
    }
    if (!applicationPath.startsWith('/') || !outputPath.startsWith('/')) {
      throw const TerminalReleaseSymbolsException('path-not-absolute');
    }
    final TerminalReleaseSymbolPackageResult result =
        await const TerminalReleaseSymbolPackageBuilder().build(
          application: Directory(applicationPath),
          output: Directory(outputPath),
        );
    stdout.writeln(result.machineLine());
  } on Object catch (error) {
    final String code = error is TerminalReleaseSymbolsException
        ? error.code
        : 'unexpected-failure';
    stderr.writeln('TERMINAL_RELEASE_SYMBOLS_FAIL code=$code');
    exitCode = 1;
  }
}
