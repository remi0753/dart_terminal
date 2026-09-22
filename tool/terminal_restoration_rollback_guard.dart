import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

const String _action = '--prepare-pre-notes-rollback';
const String _acknowledgement = '--acknowledge-app-closed-and-store-backed-up';

void parseTerminalRestorationRollbackGuardArguments(List<String> arguments) {
  if (arguments.length != 2 ||
      !arguments.contains(_action) ||
      !arguments.contains(_acknowledgement)) {
    throw const FormatException(
      'rollback guard requires exact acknowledgement',
    );
  }
}

Future<bool> prepareTerminalRestorationPreNotesRollback(
  Map<String, String> environment,
) async {
  try {
    final String path = TerminalInteractiveRestorationLocation.fromEnvironment(
      environment,
    ).path;
    return await TerminalInteractiveRestorationPersistence(path)
        .invalidateTrust();
  } on Object {
    return false;
  }
}

Future<void> main(List<String> arguments) async {
  try {
    parseTerminalRestorationRollbackGuardArguments(arguments);
  } on FormatException {
    stderr.writeln(
      'TERMINAL_RESTORATION_ROLLBACK_GUARD_FAIL reason=arguments '
      'content_free=true',
    );
    exitCode = 64;
    return;
  }
  final bool prepared = await prepareTerminalRestorationPreNotesRollback(
    Platform.environment,
  );
  stdout.writeln(
    'TERMINAL_RESTORATION_ROLLBACK_GUARD_${prepared ? 'PASS' : 'FAIL'} '
    'trust_invalidated=$prepared note_payload_mutation=false '
    'content_free=true',
  );
  if (!prepared) exitCode = 1;
}
