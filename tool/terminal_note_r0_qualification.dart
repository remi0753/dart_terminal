import 'dart:convert';
import 'dart:io';

import 'terminal_note_r0_architecture_audit.dart' hide main;
import 'terminal_note_r0_evidence.dart' hide main;

const String terminalNoteR0QualificationTarget =
    'contextual-memory-r0-qualification';

const List<String> terminalNoteR0QualificationGates = <String>[
  'terminal-note-r0-evidence',
  'terminal-note-r0-architecture-audit',
  'terminal-notes-acceptance',
  'contextual-memory-s1-acceptance',
  'contextual-memory-s2-acceptance',
  'product-sanitizer-fuzz-fault-gate',
  'runtime-verify',
  'release-aot-distribution-verify',
];

const String _gateVariable = 'TERMINAL_NOTE_R0_QUALIFICATION_GATES';
const int _maximumMakefileBytes = 1024 * 1024;
const int _maximumEvidenceBytes = 1024 * 1024;
const int _maximumAuditorBytes = 2 * 1024 * 1024;

final class TerminalNoteR0QualificationResult {
  const TerminalNoteR0QualificationResult();

  String machineLine() =>
      'TERMINAL_NOTE_R0_QUALIFICATION_PASS version=1 gates=8 '
      'runtime_modes=2 release_architectures=3 '
      'budget_evidence=checked architecture_evidence=checked '
      'manual_claim=false promotion_claim=false content_free=true';
}

List<String> parseTerminalNoteR0QualificationGateInventory(String source) {
  if (source.isEmpty ||
      utf8.encode(source).length > _maximumMakefileBytes ||
      source.contains('\r')) {
    throw const FormatException('qualification Makefile framing is invalid');
  }
  final List<String> lines = const LineSplitter().convert(source);
  final String header = 'override $_gateVariable :=';
  final List<int> declarations = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index].startsWith(header)) index,
  ];
  if (declarations.length != 1 || lines[declarations.single] != '$header \\') {
    throw const FormatException(
      'qualification gate inventory declaration differs',
    );
  }

  final List<String> result = <String>[];
  var index = declarations.single + 1;
  while (index < lines.length) {
    final String line = lines[index];
    if (!line.startsWith('\t')) {
      throw const FormatException('qualification gate inventory is truncated');
    }
    final String trimmed = line.trim();
    final bool continues = trimmed.endsWith('\\');
    final String target = continues
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : trimmed;
    if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(target)) {
      throw const FormatException('qualification gate target is invalid');
    }
    result.add(target);
    index++;
    if (!continues) break;
  }
  if (result.isEmpty) {
    throw const FormatException('qualification gate inventory is empty');
  }
  return List<String>.unmodifiable(result);
}

void validateTerminalNoteR0QualificationMakefile(String source) {
  final List<String> inventory = parseTerminalNoteR0QualificationGateInventory(
    source,
  );
  if (!_sameOrderedStrings(inventory, terminalNoteR0QualificationGates) ||
      inventory.toSet().length != inventory.length) {
    throw const FormatException('qualification gate inventory differs');
  }

  final List<String> lines = const LineSplitter().convert(source);
  final String header = '$terminalNoteR0QualificationTarget:';
  final List<int> declarations = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index] == header) index,
  ];
  if (declarations.length != 1) {
    throw const FormatException('qualification target declaration differs');
  }
  final List<String> stanza = <String>[header];
  for (var index = declarations.single + 1; index < lines.length; index++) {
    final String line = lines[index];
    if (!line.startsWith('\t')) break;
    stanza.add(line);
  }
  const String slash = '\\';
  final List<String> expected = <String>[
    header,
    '\t@\$(MAKE) -j1 RUNTIME_ARCH=\$(RUNTIME_ARCH) $slash',
    '\t\t\$($_gateVariable)',
    '\t@cd \$(PROJECT_ROOT) && \$(DART) run $slash',
    '\t\ttool/terminal_note_r0_qualification.dart $slash',
    '\t\t--source-root=\$(PROJECT_ROOT)',
  ];
  if (!_sameOrderedStrings(stanza, expected)) {
    throw const FormatException('qualification target recipe differs');
  }
}

TerminalNoteR0QualificationResult validateTerminalNoteR0Qualification(
  Directory sourceRoot,
) {
  if (!sourceRoot.isAbsolute ||
      FileSystemEntity.typeSync(sourceRoot.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const FormatException('qualification source root is invalid');
  }
  final String makefileSource = _readBoundedText(
    File.fromUri(sourceRoot.uri.resolve('Makefile')),
    _maximumMakefileBytes,
    'qualification Makefile',
  );
  validateTerminalNoteR0QualificationMakefile(makefileSource);

  final TerminalNoteR0EvidenceSources budgetSources =
      loadTerminalNoteR0EvidenceSources(sourceRoot);
  validateTerminalNoteR0EvidenceSource(
    _readBoundedText(
      File.fromUri(sourceRoot.uri.resolve(terminalNoteR0EvidencePath)),
      _maximumEvidenceBytes,
      'budget evidence',
    ),
    sources: budgetSources,
  );

  final File architectureAuditor = File.fromUri(
    sourceRoot.uri.resolve('tool/terminal_note_r0_architecture_audit.dart'),
  );
  final List<int> auditorSource = _readBoundedBytes(
    architectureAuditor,
    _maximumAuditorBytes,
    'architecture auditor',
  );
  validateTerminalNoteR0ArchitectureEvidence(
    _readBoundedText(
      File.fromUri(
        sourceRoot.uri.resolve(terminalNoteR0ArchitectureEvidencePath),
      ),
      _maximumEvidenceBytes,
      'architecture evidence',
    ),
    auditorSource: auditorSource,
  );
  return const TerminalNoteR0QualificationResult();
}

String _readBoundedText(File file, int maximumBytes, String context) {
  final List<int> bytes = _readBoundedBytes(file, maximumBytes, context);
  return utf8.decode(bytes, allowMalformed: false);
}

List<int> _readBoundedBytes(File file, int maximumBytes, String context) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FormatException('$context is not a regular file');
  }
  final int length = file.lengthSync();
  if (length <= 0 || length > maximumBytes) {
    throw FormatException('$context size is invalid');
  }
  return file.readAsBytesSync();
}

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, String> _parseArguments(List<String> arguments) {
  const String prefix = '--source-root=';
  if (arguments.length != 1 ||
      !arguments.single.startsWith(prefix) ||
      arguments.single.length == prefix.length) {
    throw const FormatException('qualification arguments differ');
  }
  return <String, String>{
    'source-root': arguments.single.substring(prefix.length),
  };
}

void main(List<String> arguments) {
  try {
    final Map<String, String> options = _parseArguments(arguments);
    final TerminalNoteR0QualificationResult result =
        validateTerminalNoteR0Qualification(Directory(options['source-root']!));
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R0_QUALIFICATION_FAIL reason=invalid_gate '
      'content_free=true',
    );
    exitCode = 1;
  }
}
