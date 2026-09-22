import 'dart:convert';
import 'dart:io';

import 'terminal_note_r0_evidence.dart' as r0_evidence;
import 'terminal_note_r0_qualification.dart' as r0_qualification;
import 'terminal_note_r1_internal_profile.dart' as r1_profile;

const String terminalNoteR1QualificationTarget =
    'contextual-memory-r1-automated-qualification';

const List<String> terminalNoteR1QualificationGates = <String>[
  r1_profile.terminalNoteR1InternalProfileTarget,
  'contextual-memory-r1-rehearsal',
  r0_qualification.terminalNoteR0QualificationTarget,
  'runtime-note-r1-integration',
];

const String _gateVariable = 'TERMINAL_NOTE_R1_AUTOMATED_GATES';
const int _maximumMakefileBytes = 1024 * 1024;
const int _maximumEvidenceBytes = 1024 * 1024;

final class TerminalNoteR1QualificationResult {
  const TerminalNoteR1QualificationResult();

  String machineLine() =>
      'TERMINAL_NOTE_R1_AUTOMATED_QUALIFICATION_PASS version=1 gates=4 '
      'base_gates=8 runtime_modes=2 slices=2 panes=64 surfaces=64 worker=1 '
      'idle_changes=0 owners=0 profile=checked recovery=checked '
      'manual_claim=false stage_claim=false content_free=true';
}

List<String> parseTerminalNoteR1QualificationGateInventory(String source) {
  if (source.isEmpty ||
      utf8.encode(source).length > _maximumMakefileBytes ||
      source.contains('\r')) {
    throw const FormatException('R1 qualification Makefile framing is invalid');
  }
  final List<String> lines = const LineSplitter().convert(source);
  final String header = 'override $_gateVariable :=';
  final List<int> declarations = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index].startsWith(header)) index,
  ];
  if (declarations.length != 1 || lines[declarations.single] != '$header \\') {
    throw const FormatException('R1 qualification inventory differs');
  }

  final List<String> result = <String>[];
  var index = declarations.single + 1;
  while (index < lines.length) {
    final String line = lines[index];
    if (!line.startsWith('\t')) {
      throw const FormatException('R1 qualification inventory is truncated');
    }
    final String trimmed = line.trim();
    final bool continues = trimmed.endsWith('\\');
    final String target = continues
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : trimmed;
    if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(target)) {
      throw const FormatException('R1 qualification target is invalid');
    }
    result.add(target);
    index++;
    if (!continues) break;
  }
  if (result.isEmpty) {
    throw const FormatException('R1 qualification inventory is empty');
  }
  return List<String>.unmodifiable(result);
}

void validateTerminalNoteR1QualificationMakefile(String source) {
  final List<String> inventory = parseTerminalNoteR1QualificationGateInventory(
    source,
  );
  if (!_sameOrderedStrings(inventory, terminalNoteR1QualificationGates) ||
      inventory.toSet().length != inventory.length) {
    throw const FormatException('R1 qualification gate inventory differs');
  }

  final List<String> lines = const LineSplitter().convert(source);
  const String slash = '\\';
  final List<String> expectedAggregate = <String>[
    '$terminalNoteR1QualificationTarget:',
    '\t@\$(MAKE) -j1 RUNTIME_ARCH=\$(RUNTIME_ARCH) $slash',
    '\t\t\$($_gateVariable)',
    '\t@cd \$(PROJECT_ROOT) && \$(DART) run $slash',
    '\t\ttool/terminal_note_r1_qualification.dart $slash',
    '\t\t--source-root=\$(PROJECT_ROOT)',
  ];
  final List<String> expectedRehearsal = <String>[
    'contextual-memory-r1-rehearsal: '
        '${r1_profile.terminalNoteR1InternalProfileTarget}',
    '\t@cd \$(PROJECT_ROOT) && \$(DART) run $slash',
    '\t\ttool/terminal_note_r1_rehearsal.dart',
  ];
  final List<String> expectedDeveloperRuntime = <String>[
    'developer-jit-note-r1: developer-jit-build',
    '\t@cd \$(PROJECT_ROOT) && \$(INTEGRATION_TOOL) --mode=developer-jit '
        '$slash',
    '\t\t--suite=note-r1 \$(DEVELOPER_JIT_BUNDLE)',
  ];
  final List<String> expectedReleaseRuntime = <String>[
    'release-aot-note-r1: release-aot-build',
    '\t@cd \$(PROJECT_ROOT) && \$(INTEGRATION_TOOL) --mode=release-aot '
        '$slash',
    '\t\t--suite=note-r1 \$(RELEASE_AOT_BUNDLE)',
  ];
  final List<String> expectedRuntimeAggregate = <String>[
    'runtime-note-r1-integration: developer-jit-note-r1 release-aot-note-r1',
  ];
  if (!_sameOrderedStrings(
        _targetRecipe(lines, terminalNoteR1QualificationTarget),
        expectedAggregate,
      ) ||
      !_sameOrderedStrings(
        _targetRecipe(lines, 'contextual-memory-r1-rehearsal'),
        expectedRehearsal,
      ) ||
      !_sameOrderedStrings(
        _targetRecipe(lines, 'developer-jit-note-r1'),
        expectedDeveloperRuntime,
      ) ||
      !_sameOrderedStrings(
        _targetRecipe(lines, 'release-aot-note-r1'),
        expectedReleaseRuntime,
      ) ||
      !_sameOrderedStrings(
        _targetRecipe(lines, 'runtime-note-r1-integration'),
        expectedRuntimeAggregate,
      )) {
    throw const FormatException('R1 qualification target recipe differs');
  }
}

TerminalNoteR1QualificationResult validateTerminalNoteR1Qualification(
  Directory sourceRoot,
) {
  if (!sourceRoot.isAbsolute ||
      FileSystemEntity.typeSync(sourceRoot.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const FormatException('R1 qualification source root is invalid');
  }
  final String makefileSource = _readBoundedText(
    File.fromUri(sourceRoot.uri.resolve('Makefile')),
    _maximumMakefileBytes,
    'R1 qualification Makefile',
  );
  validateTerminalNoteR1QualificationMakefile(makefileSource);
  r1_profile.validateTerminalNoteR1InternalProfile(sourceRoot);
  r0_qualification.validateTerminalNoteR0Qualification(sourceRoot);

  final r0_evidence.TerminalNoteR0EvidenceSources sources = r0_evidence
      .loadTerminalNoteR0EvidenceSources(sourceRoot);
  final r0_evidence.TerminalNoteR0EvidenceResult evidence = r0_evidence
      .validateTerminalNoteR0EvidenceSource(
        _readBoundedText(
          File.fromUri(
            sourceRoot.uri.resolve(r0_evidence.terminalNoteR0EvidencePath),
          ),
          _maximumEvidenceBytes,
          'R1 base budget evidence',
        ),
        sources: sources,
      );
  final Object? metricsValue = evidence.document['metrics'];
  if (metricsValue is! Map<String, Object?>) {
    throw const FormatException('R1 base metrics differ');
  }
  final Object? idleValue = metricsValue['idle'];
  if (idleValue is! Map<String, Object?> ||
      idleValue['panes'] != 64 ||
      idleValue['surfaces'] != 64 ||
      idleValue['worker'] != 1 ||
      <String>[
        'projection_delta',
        'notification_delta',
        'layout_delta',
        'frame_delta',
        'store_changes',
        'owners',
      ].any((String key) => idleValue[key] != 0)) {
    throw const FormatException('R1 64-pane base invariant differs');
  }
  return const TerminalNoteR1QualificationResult();
}

List<String> _targetRecipe(List<String> lines, String target) {
  final String header = '$target:';
  final List<int> matches = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index] == header || lines[index].startsWith('$header ')) index,
  ];
  if (matches.length != 1) {
    throw FormatException('$target declaration differs');
  }
  final List<String> result = <String>[lines[matches.single]];
  for (var index = matches.single + 1; index < lines.length; index++) {
    final String line = lines[index];
    if (!line.startsWith('\t')) break;
    result.add(line);
  }
  return result;
}

String _readBoundedText(File file, int maximumBytes, String context) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FormatException('$context is not a regular file');
  }
  final int length = file.lengthSync();
  if (length <= 0 || length > maximumBytes) {
    throw FormatException('$context size is invalid');
  }
  return utf8.decode(file.readAsBytesSync(), allowMalformed: false);
}

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Directory _parseArguments(List<String> arguments) {
  const String prefix = '--source-root=';
  if (arguments.length != 1 ||
      !arguments.single.startsWith(prefix) ||
      arguments.single.length == prefix.length) {
    throw const FormatException('R1 qualification arguments differ');
  }
  return Directory(arguments.single.substring(prefix.length));
}

void main(List<String> arguments) {
  try {
    final TerminalNoteR1QualificationResult result =
        validateTerminalNoteR1Qualification(_parseArguments(arguments));
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R1_AUTOMATED_QUALIFICATION_FAIL '
      'reason=invalid_gate content_free=true',
    );
    exitCode = 1;
  }
}
