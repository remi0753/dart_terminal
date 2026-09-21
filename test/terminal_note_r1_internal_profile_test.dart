import 'dart:io';

import '../tool/terminal_note_r1_internal_profile.dart';

void main() => runTerminalNoteR1InternalProfileTests();

void runTerminalNoteR1InternalProfileTests() {
  final String source = File('Makefile').readAsStringSync();
  final List<String> arguments = parseTerminalNoteR1InternalArguments(source);
  _expect(
    _sameStrings(arguments, terminalNoteR1InternalArguments) &&
        arguments.toSet().length == arguments.length,
    'current profile has the exact ordered typed arguments',
  );
  validateTerminalNoteR1InternalProfileMakefile(source);

  final TerminalNoteR1InternalProfileResult result =
      validateTerminalNoteR1InternalProfile(Directory.current.absolute);
  final String machineLine = result.machineLine();
  _expect(
    machineLine ==
            'TERMINAL_NOTE_R1_INTERNAL_PROFILE_PASS version=1 '
                'notes=true on_return=true next_prompt=false '
                'policy=next-launch exposure=internal-preview '
                'store=environment-resolved default_off=true public_entries=0 '
                'content_free=true' &&
        !machineLine.contains('/') &&
        !machineLine.contains('PRIVATE'),
    'internal profile result is exact and content-free',
  );

  _expectThrows(
    () => validateTerminalNoteR1InternalProfileMakefile(
      source.replaceFirst('\t--notes-on-return=true \\\n', ''),
    ),
    'missing argument',
  );
  _expectThrows(
    () => validateTerminalNoteR1InternalProfileMakefile(
      source.replaceFirst(
        '\t--notes-next-prompt=false\n',
        '\t--notes-next-prompt=true\n',
      ),
    ),
    'S3 enabled',
  );
  _expectThrows(
    () => validateTerminalNoteR1InternalProfileMakefile(
      source.replaceFirst(
        '\t--notes=true \\\n\t--notes-on-return=true \\\n',
        '\t--notes-on-return=true \\\n\t--notes=true \\\n',
      ),
    ),
    'reordered arguments',
  );
  _expectThrows(
    () => validateTerminalNoteR1InternalProfileMakefile(
      source.replaceFirst(
        'developer-jit-audit release-aot-audit',
        'release-aot-audit developer-jit-audit',
      ),
    ),
    'reordered candidate builds',
  );
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected internal profile failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('R1 internal profile test failed: $message');
  }
}
