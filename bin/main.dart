import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

@pragma('vm:entry-point')
Future<void> main(List<String> arguments) async {
  try {
    final TerminalOptions options = TerminalOptions.parse(arguments);
    await TerminalApplication(options: options).run();
  } on FormatException catch (error) {
    stderr.writeln('Argument error: ${error.message}');
    stderr.writeln(terminalUsage);
    exitCode = 64;
  }
}
