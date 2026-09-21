import 'dart:io';

import '../tool/terminal_note_r0_qualification.dart';

void main() => runTerminalNoteR0QualificationTests();

void runTerminalNoteR0QualificationTests() {
  final String source = File('Makefile').readAsStringSync();
  final List<String> inventory = parseTerminalNoteR0QualificationGateInventory(
    source,
  );
  _expect(
    _sameStrings(inventory, terminalNoteR0QualificationGates) &&
        inventory.toSet().length == inventory.length,
    'current aggregate has the exact ordered gate inventory',
  );
  validateTerminalNoteR0QualificationMakefile(source);

  final TerminalNoteR0QualificationResult result =
      validateTerminalNoteR0Qualification(Directory.current.absolute);
  final String machineLine = result.machineLine();
  _expect(
    machineLine ==
            'TERMINAL_NOTE_R0_QUALIFICATION_PASS version=1 gates=8 '
                'runtime_modes=2 release_architectures=3 '
                'budget_evidence=checked architecture_evidence=checked '
                'manual_claim=false promotion_claim=false content_free=true' &&
        !machineLine.contains('/') &&
        !machineLine.contains('PRIVATE'),
    'qualification result is exact and content-free',
  );

  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst('\tterminal-notes-acceptance \\\n', ''),
    ),
    'missing gate',
  );
  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst(
        '\tterminal-notes-acceptance \\\n',
        '\tterminal-notes-acceptance \\\n'
            '\tterminal-notes-acceptance \\\n',
      ),
    ),
    'duplicate gate',
  );
  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst(
        '\tterminal-note-r0-evidence \\\n'
            '\tterminal-note-r0-architecture-audit \\\n',
        '\tterminal-note-r0-architecture-audit \\\n'
            '\tterminal-note-r0-evidence \\\n',
      ),
    ),
    'reordered gates',
  );
  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst(
        '\tterminal-note-r0-architecture-audit \\\n',
        '\tterminal-note-r0-architecture-audit \\\n'
            '\tunexpected-r0-gate \\\n',
      ),
    ),
    'extra gate',
  );
  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst(
        'contextual-memory-r0-qualification:\n'
            '\t@\$(MAKE) -j1 RUNTIME_ARCH=\$(RUNTIME_ARCH)',
        'contextual-memory-r0-qualification:\n'
            '\t@\$(MAKE) -j4 RUNTIME_ARCH=\$(RUNTIME_ARCH)',
      ),
    ),
    'parallel aggregate',
  );
  _expectThrows(
    () => validateTerminalNoteR0QualificationMakefile(
      source.replaceFirst(
        'tool/terminal_note_r0_qualification.dart',
        'tool/missing_r0_qualification.dart',
      ),
    ),
    'missing final checker',
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
  throw StateError('Expected qualification failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('R0 qualification test failed: $message');
}
