import 'dart:io';

import 'package:dart_terminal/src/terminal_terminfo_environment.dart';

void main() => runTerminalTerminfoEnvironmentTests();

void runTerminalTerminfoEnvironmentTests() {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-terminfo-environment-',
  );
  try {
    final File bundled = File(
      '${temporary.path}/${TerminalTerminfoEnvironment.compiledEntryRelativePath}',
    );
    bundled.parent.createSync(recursive: true);
    File('resources/terminfo/78/xterm-256color').copySync(bundled.path);
    final TerminalTerminfoEnvironment resolved =
        TerminalTerminfoEnvironment.resolve(
          parentEnvironment: const <String, String>{
            'TERM': 'dumb',
            'COLORTERM': 'legacy',
            'TERMINFO': '/untrusted/parent/database',
            'DT_RETAIN': 'yes',
          },
          bundledEntryPath: bundled.absolute.path,
        );
    _expect(
      resolved.disposition == TerminalTerminfoDisposition.bundled &&
          resolved.usesBundledDatabase &&
          resolved.compiledEntryBytes == bundled.lengthSync() &&
          resolved.environment['TERM'] == 'xterm-256color' &&
          resolved.environment['COLORTERM'] == 'truecolor' &&
          resolved.environment['TERMINFO'] == bundled.parent.parent.path &&
          resolved.environment['DT_RETAIN'] == 'yes' &&
          resolved.sshPtyEnvironment.length == 1 &&
          resolved.sshPtyEnvironment['TERM'] == 'xterm-256color' &&
          !resolved.sshPtyEnvironment.containsKey('TERMINFO'),
      'valid bundle overrides terminal capability environment exactly',
    );

    final TerminalTerminfoEnvironment missing =
        TerminalTerminfoEnvironment.resolve(
          parentEnvironment: const <String, String>{
            'TERM': 'unknown',
            'TERMINFO': '/stale/private/database',
          },
        );
    _expect(
      missing.disposition == TerminalTerminfoDisposition.fallbackMissing &&
          missing.environment['TERM'] == 'xterm-256color' &&
          missing.environment['COLORTERM'] == 'truecolor' &&
          !missing.environment.containsKey('TERMINFO') &&
          missing.compiledEntryBytes == 0,
      'missing bundle clears private lookup and keeps standard TERM fallback',
    );

    final File malformed = File(
      '${temporary.path}/malformed/${TerminalTerminfoEnvironment.compiledEntryRelativePath}',
    );
    malformed.parent.createSync(recursive: true);
    malformed.writeAsBytesSync(const <int>[0x1a, 0x01, 0x00, 0x00]);
    final TerminalTerminfoEnvironment invalid =
        TerminalTerminfoEnvironment.resolve(
          parentEnvironment: const <String, String>{
            'TERMINFO': '/stale/private/database',
          },
          bundledEntryPath: malformed.absolute.path,
        );
    _expect(
      invalid.disposition == TerminalTerminfoDisposition.fallbackInvalid &&
          invalid.environment['TERM'] == 'xterm-256color' &&
          !invalid.environment.containsKey('TERMINFO'),
      'malformed bundle fails closed to the standard TERM name',
    );

    final File wrongLayout = File('${temporary.path}/wrong-name');
    bundled.copySync(wrongLayout.path);
    _expect(
      TerminalTerminfoEnvironment.resolve(
            parentEnvironment: const <String, String>{},
            bundledEntryPath: wrongLayout.absolute.path,
          ).disposition ==
          TerminalTerminfoDisposition.fallbackInvalid,
      'valid bytes outside the declared bundle layout are rejected',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
