import 'dart:io';

import '../tool/terminal_note_r1_qualification.dart';

void main() => runTerminalNoteR1QualificationTests();

void runTerminalNoteR1QualificationTests() {
  final String source = File('Makefile').readAsStringSync();
  final List<String> inventory = parseTerminalNoteR1QualificationGateInventory(
    source,
  );
  _expect(
    _sameStrings(inventory, terminalNoteR1QualificationGates) &&
        inventory.toSet().length == inventory.length,
    'current aggregate has the exact ordered R1 gate inventory',
  );
  validateTerminalNoteR1QualificationMakefile(source);

  final TerminalNoteR1QualificationResult result =
      validateTerminalNoteR1Qualification(Directory.current.absolute);
  final String machineLine = result.machineLine();
  _expect(
    machineLine ==
            'TERMINAL_NOTE_R1_AUTOMATED_QUALIFICATION_PASS version=1 gates=4 '
                'base_gates=8 runtime_modes=2 slices=2 panes=64 surfaces=64 '
                'worker=1 idle_changes=0 owners=0 profile=checked '
                'recovery=checked manual_claim=false stage_claim=false '
                'content_free=true' &&
        !machineLine.contains('/') &&
        !machineLine.contains('PRIVATE'),
    'R1 qualification result is exact and content-free',
  );

  _expectThrows(
    () => validateTerminalNoteR1QualificationMakefile(
      source.replaceFirst('\tcontextual-memory-r1-rehearsal \\\n', ''),
    ),
    'missing recovery gate',
  );
  _expectThrows(
    () => validateTerminalNoteR1QualificationMakefile(
      source.replaceFirst(
        '\tcontextual-memory-r0-qualification \\\n'
            '\truntime-note-r1-integration\n',
        '\truntime-note-r1-integration \\\n'
            '\tcontextual-memory-r0-qualification\n',
      ),
    ),
    'reordered base and runtime gates',
  );
  _expectThrows(
    () => validateTerminalNoteR1QualificationMakefile(
      source.replaceFirst(
        'contextual-memory-r1-automated-qualification:\n'
            '\t@\$(MAKE) -j1 RUNTIME_ARCH=\$(RUNTIME_ARCH)',
        'contextual-memory-r1-automated-qualification:\n'
            '\t@\$(MAKE) -j4 RUNTIME_ARCH=\$(RUNTIME_ARCH)',
      ),
    ),
    'parallel aggregate',
  );
  _expectThrows(
    () => validateTerminalNoteR1QualificationMakefile(
      source.replaceFirst(
        '--suite=note-r1 \$(RELEASE_AOT_BUNDLE)',
        '--suite=note-s2 \$(RELEASE_AOT_BUNDLE)',
      ),
    ),
    'release runtime suite drift',
  );
  _expectThrows(
    () => validateTerminalNoteR1QualificationMakefile(
      source.replaceFirst(
        'runtime-note-r1-integration: developer-jit-note-r1 '
            'release-aot-note-r1',
        'runtime-note-r1-integration: release-aot-note-r1 '
            'developer-jit-note-r1',
      ),
    ),
    'runtime order drift',
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
  throw StateError('Expected R1 qualification failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('R1 qualification test failed: $message');
  }
}
