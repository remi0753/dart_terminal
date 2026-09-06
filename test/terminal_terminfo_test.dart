import 'dart:convert';
import 'dart:io';

import '../tool/terminal_terminfo.dart';

void main() => runTerminalTerminfoTests();

void runTerminalTerminfoTests() {
  _testReviewedContract();
  _testContractValidation();
  _testInfocmpProjection();
}

String _fixture() =>
    File(defaultTerminalTerminfoContractPath).readAsStringSync();

void _testReviewedContract() {
  final TerminalTerminfoContract contract = TerminalTerminfoContract.load(
    File(defaultTerminalTerminfoContractPath),
  );
  _expect(
    contract.terminalName == 'xterm-256color' &&
        contract.sourcePath == 'resources/terminfo/dart-terminal.terminfo' &&
        contract.compiledPath == 'resources/terminfo/78/xterm-256color' &&
        contract.compiler.version == 'ncurses 6.6.20251230' &&
        contract.requiredCapabilities.contains('Tc') &&
        contract.forbiddenCapabilities.contains('Ms'),
    'reviewed contract pins source, artifact, producer, and policy',
  );
}

void _testContractValidation() {
  final String fixture = _fixture();
  _expectFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    'unsupported contract version',
  );
  _expectFailure(
    fixture.replaceFirst(
      '"terminal_name": "xterm-256color"',
      '"terminal_name": "dart-terminal"',
    ),
    'must remain xterm-256color',
  );
  _expectFailure(
    fixture.replaceFirst(
      '"source_path": "resources/',
      '"source_path": "../resources/',
    ),
    'normalized relative path',
  );
  _expectFailure(
    fixture.replaceFirst(
      '"compiled_sha256": "',
      '"unknown": true,\n  "compiled_sha256": "',
    ),
    'keys differ',
  );
  _expectFailure(
    fixture.replaceFirst(
      RegExp(r'"source_sha256": "[^"]+"'),
      '"source_sha256": "not-a-hash"',
    ),
    'lowercase SHA-256',
  );
  final Map<String, Object?> overlap = Map<String, Object?>.from(
    jsonDecode(fixture) as Map<String, Object?>,
  );
  overlap['forbidden_capabilities'] = <String>[
    ...(overlap['forbidden_capabilities']! as List<Object?>).cast<String>(),
    'smcup',
  ]..sort();
  _expectFailure(
    jsonEncode(overlap),
    'required and forbidden capabilities overlap',
  );
}

void _testInfocmpProjection() {
  const String sample = '''
# reconstructed path changes between temporary roots
xterm-256color|Dart Terminal,
\tAX,
\tcolors#256,
\tcup=\\E[%i%p1%d;%p2%dH,
''';
  final String normalized = normalizeTerminalInfocmp(sample);
  final Set<String> names = terminalInfocmpCapabilityNames(normalized);
  _expect(
    normalized.startsWith('xterm-256color|') &&
        names.join(',') == 'AX,colors,cup',
    'infocmp normalization removes provenance and preserves capabilities',
  );
}

void _expectFailure(String source, String message) {
  try {
    TerminalTerminfoContract.parse(source);
  } on TerminalTerminfoException catch (error) {
    _expect(
      error.message.contains(message),
      'expected "$message", got "${error.message}"',
    );
    return;
  }
  throw StateError('expected terminfo contract failure containing "$message"');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
