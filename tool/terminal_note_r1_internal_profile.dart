import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

const String terminalNoteR1InternalProfileTarget =
    'contextual-memory-r1-internal-profile-check';
const String terminalNoteR1InternalCandidateTarget =
    'contextual-memory-r1-internal-candidate-build';

const List<String> terminalNoteR1InternalArguments = <String>[
  '--notes=true',
  '--notes-on-return=true',
  '--notes-next-prompt=false',
];

const String _profileVariable = 'TERMINAL_NOTE_R1_INTERNAL_ARGUMENTS';
const int _maximumMakefileBytes = 1024 * 1024;

final class TerminalNoteR1InternalProfileResult {
  const TerminalNoteR1InternalProfileResult();

  String machineLine() =>
      'TERMINAL_NOTE_R1_INTERNAL_PROFILE_PASS version=1 '
      'notes=true on_return=true next_prompt=false '
      'policy=next-launch exposure=internal-preview '
      'store=environment-resolved default_off=true public_entries=0 '
      'content_free=true';
}

List<String> parseTerminalNoteR1InternalArguments(String source) {
  if (source.isEmpty ||
      utf8.encode(source).length > _maximumMakefileBytes ||
      source.contains('\r')) {
    throw const FormatException('internal profile Makefile framing is invalid');
  }
  final List<String> lines = const LineSplitter().convert(source);
  final String header = 'override $_profileVariable :=';
  final List<int> declarations = <int>[
    for (var index = 0; index < lines.length; index++)
      if (lines[index].startsWith(header)) index,
  ];
  if (declarations.length != 1 || lines[declarations.single] != '$header \\') {
    throw const FormatException('internal profile declaration differs');
  }

  final List<String> result = <String>[];
  var index = declarations.single + 1;
  while (index < lines.length) {
    final String line = lines[index];
    if (!line.startsWith('\t')) {
      throw const FormatException('internal profile is truncated');
    }
    final String trimmed = line.trim();
    final bool continues = trimmed.endsWith('\\');
    final String argument = continues
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : trimmed;
    if (!RegExp(r'^--[a-z][a-z0-9-]*=(?:true|false)$').hasMatch(argument)) {
      throw const FormatException('internal profile argument is invalid');
    }
    result.add(argument);
    index++;
    if (!continues) break;
  }
  if (result.isEmpty) {
    throw const FormatException('internal profile is empty');
  }
  return List<String>.unmodifiable(result);
}

void validateTerminalNoteR1InternalProfileMakefile(String source) {
  final List<String> arguments = parseTerminalNoteR1InternalArguments(source);
  if (!_sameOrderedStrings(arguments, terminalNoteR1InternalArguments) ||
      arguments.toSet().length != arguments.length) {
    throw const FormatException('internal profile arguments differ');
  }

  final List<String> lines = const LineSplitter().convert(source);
  final List<String> profileRecipe = _targetRecipe(
    lines,
    terminalNoteR1InternalProfileTarget,
  );
  const String slash = '\\';
  final List<String> expectedProfileRecipe = <String>[
    '$terminalNoteR1InternalProfileTarget: dependencies',
    '\t@cd \$(PROJECT_ROOT) && \$(DART) run $slash',
    '\t\ttool/terminal_note_r1_internal_profile.dart $slash',
    '\t\t--source-root=\$(PROJECT_ROOT)',
  ];
  if (!_sameOrderedStrings(profileRecipe, expectedProfileRecipe)) {
    throw const FormatException('internal profile target recipe differs');
  }

  final List<String> candidateRecipe = _targetRecipe(
    lines,
    terminalNoteR1InternalCandidateTarget,
  );
  final List<String> expectedCandidateRecipe = <String>[
    '$terminalNoteR1InternalCandidateTarget:',
    '\t@\$(MAKE) -j1 RUNTIME_ARCH=\$(RUNTIME_ARCH) $slash',
    '\t\t$terminalNoteR1InternalProfileTarget $slash',
    '\t\tdeveloper-jit-audit release-aot-audit',
    '\t@echo "CONTEXTUAL_MEMORY_R1_INTERNAL_CANDIDATE_PASS runtime_modes=2 typed_profile=checked public_exposure=false s3=false content_free=true"',
  ];
  if (!_sameOrderedStrings(candidateRecipe, expectedCandidateRecipe)) {
    throw const FormatException('internal candidate target recipe differs');
  }
}

TerminalNoteR1InternalProfileResult validateTerminalNoteR1InternalProfile(
  Directory sourceRoot,
) {
  if (!sourceRoot.isAbsolute ||
      FileSystemEntity.typeSync(sourceRoot.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const FormatException('internal profile source root is invalid');
  }
  final File makefile = File.fromUri(sourceRoot.uri.resolve('Makefile'));
  if (FileSystemEntity.typeSync(makefile.path, followLinks: false) !=
          FileSystemEntityType.file ||
      makefile.lengthSync() <= 0 ||
      makefile.lengthSync() > _maximumMakefileBytes) {
    throw const FormatException('internal profile Makefile is invalid');
  }
  final String makefileSource = utf8.decode(
    makefile.readAsBytesSync(),
    allowMalformed: false,
  );
  validateTerminalNoteR1InternalProfileMakefile(makefileSource);

  final _MemoryConfigFileSystem fileSystem = _MemoryConfigFileSystem(
    const <String, String>{
      '/internal/base.conf':
          'notes = false\n'
          'notes-on-return = false\n'
          'notes-next-prompt = true\n',
    },
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(
    fileSystem: fileSystem,
  );
  final TerminalConfigResolution resolution = loader.resolve(
    <String>[
      '--config=/internal/base.conf',
      ...terminalNoteR1InternalArguments,
    ],
    environment: const <String, String>{'HOME': '/Users/internal'},
    currentDirectory: '/internal',
  );
  if (resolution.remainingArguments.isNotEmpty ||
      resolution.snapshot.diagnostics.isNotEmpty) {
    throw const FormatException('internal profile did not resolve cleanly');
  }
  final TerminalProductConfiguration candidate =
      TerminalProductConfiguration.fromSnapshot(resolution.snapshot);
  final TerminalNoteFeatureConfiguration notes =
      TerminalNoteFeatureConfiguration.fromProduct(candidate);
  if (!notes.surfaceEnabled ||
      !notes.onReturnEnabled ||
      notes.nextPromptEnabled ||
      notes.fontSize != 15) {
    throw const FormatException('internal profile feature state differs');
  }
  for (final TerminalConfigOption<bool> option in <TerminalConfigOption<bool>>[
    TerminalProductConfigSchema.notes,
    TerminalProductConfigSchema.notesOnReturn,
    TerminalProductConfigSchema.notesNextPrompt,
  ]) {
    if (option.applicationPolicy !=
            TerminalConfigApplicationPolicy.nextLaunch ||
        option.exposure != TerminalConfigExposure.internalPreview ||
        resolution.snapshot.resolved(option).source.kind !=
            TerminalConfigSourceKind.commandLine) {
      throw const FormatException('internal profile option boundary differs');
    }
  }
  if (TerminalProductConfigSchema.notesFontSize.applicationPolicy !=
          TerminalConfigApplicationPolicy.live ||
      TerminalProductConfigSchema.notesFontSize.exposure !=
          TerminalConfigExposure.internalPreview) {
    throw const FormatException('internal Note font boundary differs');
  }

  final TerminalProductConfiguration defaults =
      TerminalProductConfiguration.fromSnapshot(
        loader
            .resolve(
              const <String>['--no-config'],
              environment: const <String, String>{},
              currentDirectory: '/internal',
            )
            .snapshot,
      );
  final Set<String> publicNames = TerminalProductConfigSchema
      .instance
      .publicOptions
      .map((TerminalConfigOptionBase option) => option.name)
      .toSet();
  const Set<String> internalNames = <String>{
    'notes',
    'notes-on-return',
    'notes-next-prompt',
    'notes-font-size',
  };
  final TerminalActionCatalog defaultCatalog = TerminalActionCatalog.standard();
  final TerminalActionCatalog internalCatalog = TerminalActionCatalog.standard(
    includeNotes: true,
  );
  const Set<TerminalActionId> noteActions = <TerminalActionId>{
    TerminalActionId.newNote,
    TerminalActionId.toggleNotes,
    TerminalActionId.focusTerminalFromNotes,
  };
  final String publicReference = <String>[
    TerminalConfigurationReference().generateUsage(),
    TerminalConfigurationReference().generateMarkdown(),
  ].join('\n');
  if (defaults.notes ||
      !defaults.notesOnReturn ||
      defaults.notesNextPrompt ||
      defaults.notesFontSize != 15 ||
      publicNames.any(internalNames.contains) ||
      publicReference.contains('--notes') ||
      noteActions.any(
        (TerminalActionId id) => defaultCatalog.actionForId(id) != null,
      ) ||
      noteActions.any(
        (TerminalActionId id) => internalCatalog.actionForId(id) == null,
      )) {
    throw const FormatException('internal profile changed public defaults');
  }

  final TerminalNoteStoreLocation xdg =
      TerminalNoteStoreLocation.fromEnvironment(const <String, String>{
        'XDG_STATE_HOME': '/private/var/internal-state',
        'HOME': '/Users/internal',
      });
  final TerminalNoteStoreLocation home =
      TerminalNoteStoreLocation.fromEnvironment(const <String, String>{
        'HOME': '/Users/internal',
      });
  if (xdg.canonicalPath != '/private/var/internal-state/dart-terminal/notes' ||
      home.canonicalPath !=
          '/Users/internal/Library/Application Support/Dart Terminal/Notes') {
    throw const FormatException('internal profile store resolution differs');
  }
  return const TerminalNoteR1InternalProfileResult();
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

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _MemoryConfigFileSystem implements TerminalConfigFileSystem {
  _MemoryConfigFileSystem(Map<String, String> files)
    : _files = Map<String, List<int>>.unmodifiable(
        files.map(
          (String path, String value) =>
              MapEntry<String, List<int>>(_normalize(path), utf8.encode(value)),
        ),
      );

  final Map<String, List<int>> _files;

  @override
  String absolutePath(String path) =>
      _normalize(path.startsWith('/') ? path : '/internal/$path');

  @override
  bool exists(String path) => _files.containsKey(_normalize(path));

  @override
  List<int> readBytes(String path) => List<int>.from(_files[_normalize(path)]!);

  @override
  String resolvePath(String containingFile, String includedPath) {
    if (includedPath.startsWith('/')) return _normalize(includedPath);
    final String normalized = _normalize(containingFile);
    final int slash = normalized.lastIndexOf('/');
    return _normalize('${normalized.substring(0, slash)}/$includedPath');
  }
}

String _normalize(String path) => Uri.file(path).normalizePath().toFilePath();

Map<String, String> _parseArguments(List<String> arguments) {
  const String prefix = '--source-root=';
  if (arguments.length != 1 ||
      !arguments.single.startsWith(prefix) ||
      arguments.single.length == prefix.length) {
    throw const FormatException('internal profile arguments differ');
  }
  return <String, String>{
    'source-root': arguments.single.substring(prefix.length),
  };
}

void main(List<String> arguments) {
  try {
    final Map<String, String> options = _parseArguments(arguments);
    final TerminalNoteR1InternalProfileResult result =
        validateTerminalNoteR1InternalProfile(
          Directory(options['source-root']!),
        );
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R1_INTERNAL_PROFILE_FAIL reason=invalid_profile '
      'content_free=true',
    );
    exitCode = 1;
  }
}
