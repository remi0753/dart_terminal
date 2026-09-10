import 'dart:convert';
import 'dart:io';

import 'terminal_differential_sha256.dart';

const String defaultTerminalTerminfoContractPath =
    'compatibility/terminfo_contract.json';

final class TerminalTerminfoException implements FormatException {
  const TerminalTerminfoException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalTerminfoException: $message';
}

final class TerminalTerminfoCompilerContract {
  const TerminalTerminfoCompilerContract({
    required this.path,
    required this.version,
    required this.infocmpPath,
    required this.baseDatabasePath,
    required this.arguments,
  });

  final String path;
  final String version;
  final String infocmpPath;
  final String baseDatabasePath;
  final List<String> arguments;
}

final class TerminalTerminfoContract {
  const TerminalTerminfoContract({
    required this.terminalName,
    required this.sourcePath,
    required this.compiledPath,
    required this.compiler,
    required this.sourceSha256,
    required this.baseInfocmpSha256,
    required this.compiledSha256,
    required this.compiledInfocmpSha256,
    required this.requiredCapabilities,
    required this.forbiddenCapabilities,
  });

  static const int maximumContractBytes = 64 * 1024;
  static const String format = 'dart-terminal-terminfo-contract';
  static const int version = 1;
  static const String pinnedTerminalName = 'xterm-256color';
  static const String privateBaseName = 'dart-terminal-pinned-xterm-base';
  static const List<String> pinnedArguments = <String>[
    '-x',
    '-e',
    pinnedTerminalName,
    '-o',
  ];

  final String terminalName;
  final String sourcePath;
  final String compiledPath;
  final TerminalTerminfoCompilerContract compiler;
  final String sourceSha256;
  final String baseInfocmpSha256;
  final String compiledSha256;
  final String compiledInfocmpSha256;
  final List<String> requiredCapabilities;
  final List<String> forbiddenCapabilities;

  static TerminalTerminfoContract load(File source) {
    _expect(source.existsSync(), 'contract does not exist: ${source.path}');
    _expect(
      FileSystemEntity.typeSync(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'contract must be a regular file',
    );
    final int length = source.lengthSync();
    _expect(
      length > 0 && length <= maximumContractBytes,
      'contract size $length is outside 1..$maximumContractBytes',
    );
    return parse(source.readAsStringSync());
  }

  static TerminalTerminfoContract parse(String source) {
    _expect(
      utf8.encode(source).length <= maximumContractBytes,
      'contract exceeds $maximumContractBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalTerminfoException('invalid JSON: $error');
    }
    final Map<String, Object?> root = _object(decoded, 'root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'terminal_name',
      'source_path',
      'compiled_path',
      'compiler',
      'source_sha256',
      'base_infocmp_sha256',
      'compiled_sha256',
      'compiled_infocmp_sha256',
      'required_capabilities',
      'forbidden_capabilities',
    }, 'root');
    _expect(root['format'] == format, 'unsupported contract format');
    _expect(root['version'] == version, 'unsupported contract version');
    final String terminalName = _text(root['terminal_name'], 'terminal_name');
    _expect(
      terminalName == pinnedTerminalName,
      'terminal_name must remain $pinnedTerminalName for SSH fallback',
    );
    final String sourcePath = _relativePath(root['source_path'], 'source_path');
    final String compiledPath = _relativePath(
      root['compiled_path'],
      'compiled_path',
    );
    _expect(
      sourcePath == 'resources/terminfo/dart-terminal.terminfo',
      'source_path differs from the versioned resource contract',
    );
    _expect(
      compiledPath == 'resources/terminfo/78/$pinnedTerminalName',
      'compiled_path differs from the hexadecimal ncurses layout',
    );

    final Map<String, Object?> compilerMap = _object(
      root['compiler'],
      'compiler',
    );
    _expectKeys(compilerMap, const <String>{
      'path',
      'version',
      'infocmp_path',
      'base_database_path',
      'arguments',
    }, 'compiler');
    final List<String> arguments = _stringList(
      compilerMap['arguments'],
      'compiler.arguments',
    );
    _expect(
      _listEquals(arguments, pinnedArguments),
      'compiler.arguments differ from the deterministic contract',
    );
    final TerminalTerminfoCompilerContract compiler =
        TerminalTerminfoCompilerContract(
          path: _absolutePath(compilerMap['path'], 'compiler.path'),
          version: _text(compilerMap['version'], 'compiler.version'),
          infocmpPath: _absolutePath(
            compilerMap['infocmp_path'],
            'compiler.infocmp_path',
          ),
          baseDatabasePath: _absolutePath(
            compilerMap['base_database_path'],
            'compiler.base_database_path',
          ),
          arguments: List<String>.unmodifiable(arguments),
        );
    final List<String> required = _capabilityList(
      root['required_capabilities'],
      'required_capabilities',
    );
    final List<String> forbidden = _capabilityList(
      root['forbidden_capabilities'],
      'forbidden_capabilities',
    );
    _expect(
      required.toSet().intersection(forbidden.toSet()).isEmpty,
      'required and forbidden capabilities overlap',
    );
    return TerminalTerminfoContract(
      terminalName: terminalName,
      sourcePath: sourcePath,
      compiledPath: compiledPath,
      compiler: compiler,
      sourceSha256: _sha256(root['source_sha256'], 'source_sha256'),
      baseInfocmpSha256: _sha256(
        root['base_infocmp_sha256'],
        'base_infocmp_sha256',
      ),
      compiledSha256: _sha256(root['compiled_sha256'], 'compiled_sha256'),
      compiledInfocmpSha256: _sha256(
        root['compiled_infocmp_sha256'],
        'compiled_infocmp_sha256',
      ),
      requiredCapabilities: List<String>.unmodifiable(required),
      forbiddenCapabilities: List<String>.unmodifiable(forbidden),
    );
  }
}

final class TerminalTerminfoCheckResult {
  const TerminalTerminfoCheckResult({
    required this.capabilityCount,
    required this.compiledBytes,
    required this.generated,
  });

  final int capabilityCount;
  final int compiledBytes;
  final bool generated;

  String machineLine() =>
      'TERMINAL_TERMINFO_${generated ? 'GENERATE' : 'CHECK'}_PASS '
      'terminal=xterm-256color capabilities=$capabilityCount '
      'compiled_bytes=$compiledBytes';
}

Future<TerminalTerminfoCheckResult> runTerminalTerminfoCheck({
  Directory? projectRoot,
  bool generate = false,
}) async {
  final Directory root = projectRoot ?? Directory.current;
  final File contractFile = File(
    _join(root.path, defaultTerminalTerminfoContractPath),
  );
  final Map<String, Object?> editableContract = _readContractMap(contractFile);
  final TerminalTerminfoContract contract = generate
      ? _parseGenerateTemplate(editableContract)
      : TerminalTerminfoContract.load(contractFile);
  final File source = File(_join(root.path, contract.sourcePath));
  _expect(
    source.existsSync(),
    'terminfo source does not exist: ${source.path}',
  );
  _expect(
    FileSystemEntity.typeSync(source.path, followLinks: false) ==
        FileSystemEntityType.file,
    'terminfo source must be a regular file',
  );
  final List<int> sourceBytes = source.readAsBytesSync();
  _expect(
    sourceBytes.isNotEmpty && sourceBytes.length <= 64 * 1024,
    'terminfo source size is outside 1..65536',
  );
  final String sourceText = utf8.decode(sourceBytes);
  _validateSource(sourceText);

  await _requireExecutable(contract.compiler.path, 'tic');
  await _requireExecutable(contract.compiler.infocmpPath, 'infocmp');
  _expect(
    Directory(contract.compiler.baseDatabasePath).existsSync(),
    'base terminfo database is unavailable: '
    '${contract.compiler.baseDatabasePath}',
  );
  final ProcessResult compilerVersion = await Process.run(
    contract.compiler.path,
    const <String>['-V'],
  );
  _expect(
    compilerVersion.exitCode == 0 &&
        (compilerVersion.stdout as String).trim() == contract.compiler.version,
    'tic version differs from ${contract.compiler.version}',
  );

  final String baseInfocmp = await _runInfocmp(
    contract,
    databasePath: contract.compiler.baseDatabasePath,
  );
  final String normalizedBase = normalizeTerminalInfocmp(baseInfocmp);
  final String baseHash = terminalDifferentialSha256(
    utf8.encode(normalizedBase),
  );
  final String sourceHash = terminalDifferentialSha256(sourceBytes);
  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-terminfo-',
  );
  try {
    final File privateBaseSource = File(
      _join(temporary.path, 'pinned-base.terminfo'),
    );
    privateBaseSource.writeAsStringSync(
      _renameInfocmpEntry(
        baseInfocmp,
        TerminalTerminfoContract.privateBaseName,
      ),
    );
    await _runTic(contract, <String>[
      '-x',
      '-o',
      temporary.path,
      privateBaseSource.path,
    ]);
    await _runTic(
      contract,
      <String>[...contract.compiler.arguments, temporary.path, source.path],
      environment: <String, String>{'TERMINFO': temporary.path},
    );
    final File generatedEntry = File(
      _join(temporary.path, '78/${contract.terminalName}'),
    );
    _expect(
      generatedEntry.existsSync(),
      'tic did not create the expected hexadecimal-path entry',
    );
    final List<int> generatedBytes = generatedEntry.readAsBytesSync();
    _expect(
      generatedBytes.isNotEmpty && generatedBytes.length <= 32 * 1024,
      'compiled entry size is outside 1..32768',
    );
    final String generatedInfocmp = await _runInfocmp(
      contract,
      databasePath: temporary.path,
    );
    final String normalizedCompiled = normalizeTerminalInfocmp(
      generatedInfocmp,
    );
    final Set<String> capabilities = terminalInfocmpCapabilityNames(
      normalizedCompiled,
    );
    _validateCapabilities(contract, capabilities);
    final String compiledHash = terminalDifferentialSha256(generatedBytes);
    final String compiledInfocmpHash = terminalDifferentialSha256(
      utf8.encode(normalizedCompiled),
    );

    if (generate) {
      final File destination = File(_join(root.path, contract.compiledPath));
      destination.parent.createSync(recursive: true);
      generatedEntry.copySync(destination.path);
      editableContract['source_sha256'] = sourceHash;
      editableContract['base_infocmp_sha256'] = baseHash;
      editableContract['compiled_sha256'] = compiledHash;
      editableContract['compiled_infocmp_sha256'] = compiledInfocmpHash;
      contractFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(editableContract) + '\n',
      );
    } else {
      _expect(sourceHash == contract.sourceSha256, 'terminfo source is stale');
      _expect(
        baseHash == contract.baseInfocmpSha256,
        'pinned base infocmp projection is stale',
      );
      final File committed = File(_join(root.path, contract.compiledPath));
      _expect(
        committed.existsSync(),
        'compiled terminfo entry does not exist: ${committed.path}',
      );
      final List<int> committedBytes = committed.readAsBytesSync();
      _expect(
        terminalDifferentialSha256(committedBytes) == contract.compiledSha256,
        'compiled terminfo hash is stale',
      );
      _expect(
        compiledHash == contract.compiledSha256 &&
            _listEquals(generatedBytes, committedBytes),
        'pinned tic regeneration differs from the committed entry',
      );
      _expect(
        compiledInfocmpHash == contract.compiledInfocmpSha256,
        'compiled infocmp semantic projection is stale',
      );
      _validateManifest(root, contract.compiledPath);
    }
    return TerminalTerminfoCheckResult(
      capabilityCount: capabilities.length,
      compiledBytes: generatedBytes.length,
      generated: generate,
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

String normalizeTerminalInfocmp(String source) => source
    .split('\n')
    .where((String line) => line.trim().isNotEmpty && !line.startsWith('#'))
    .map((String line) => line.trimRight())
    .join('\n');

Set<String> terminalInfocmpCapabilityNames(String normalized) {
  final Set<String> result = <String>{};
  final List<String> lines = normalized.split('\n');
  for (int index = 1; index < lines.length; index++) {
    final String value = lines[index].trim();
    if (!value.endsWith(',')) continue;
    final int equals = value.indexOf('=');
    final int number = value.indexOf('#');
    final int end = equals < 0
        ? (number < 0 ? value.length - 1 : number)
        : (number < 0 || equals < number ? equals : number);
    if (end > 0) result.add(value.substring(0, end));
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  final bool generate =
      arguments.length == 1 && arguments.single == '--generate';
  if (arguments.isNotEmpty &&
      !generate &&
      !(arguments.length == 1 && arguments.single == '--check')) {
    stderr.writeln(
      'usage: dart run tool/terminal_terminfo.dart [--check|--generate]',
    );
    exitCode = 64;
    return;
  }
  try {
    final TerminalTerminfoCheckResult result = await runTerminalTerminfoCheck(
      generate: generate,
    );
    stdout.writeln(result.machineLine());
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

TerminalTerminfoContract _parseGenerateTemplate(Map<String, Object?> source) {
  final Map<String, Object?> editable = Map<String, Object?>.from(source);
  for (final String key in const <String>[
    'source_sha256',
    'base_infocmp_sha256',
    'compiled_sha256',
    'compiled_infocmp_sha256',
  ]) {
    if (editable[key] == 'GENERATE') {
      editable[key] = List<String>.filled(64, '0').join();
    }
  }
  return TerminalTerminfoContract.parse(jsonEncode(editable));
}

Map<String, Object?> _readContractMap(File source) {
  _expect(source.existsSync(), 'contract does not exist: ${source.path}');
  final Object? decoded = jsonDecode(source.readAsStringSync());
  return _object(decoded, 'root');
}

Future<String> _runInfocmp(
  TerminalTerminfoContract contract, {
  required String databasePath,
}) async {
  final ProcessResult result = await Process.run(
    contract.compiler.infocmpPath,
    <String>['-A', databasePath, '-1', '-x', contract.terminalName],
  );
  _expect(
    result.exitCode == 0,
    'infocmp failed for $databasePath: ${(result.stderr as String).trim()}',
  );
  return result.stdout as String;
}

Future<void> _runTic(
  TerminalTerminfoContract contract,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final ProcessResult result = await Process.run(
    contract.compiler.path,
    arguments,
    environment: environment,
    includeParentEnvironment: true,
  );
  _expect(
    result.exitCode == 0,
    'tic failed: ${(result.stderr as String).trim()}',
  );
  _expect(
    (result.stderr as String).trim().isEmpty,
    'tic emitted a warning: ${(result.stderr as String).trim()}',
  );
}

Future<void> _requireExecutable(String path, String label) async {
  _expect(File(path).existsSync(), '$label does not exist: $path');
  _expect(
    FileSystemEntity.typeSync(path, followLinks: true) ==
        FileSystemEntityType.file,
    '$label is not a regular file: $path',
  );
  final ProcessResult result = await Process.run('/bin/test', <String>[
    '-x',
    path,
  ]);
  _expect(result.exitCode == 0, '$label is not executable: $path');
}

String _renameInfocmpEntry(String source, String name) {
  final List<String> lines = source.split('\n');
  final int index = lines.indexWhere(
    (String line) => line.isNotEmpty && !line.startsWith('#'),
  );
  _expect(index >= 0, 'base infocmp output has no terminal entry');
  final int separator = lines[index].indexOf('|');
  _expect(separator > 0, 'base infocmp entry has no long-name separator');
  lines[index] = '$name${lines[index].substring(separator)}';
  return lines.join('\n');
}

void _validateSource(String source) {
  _expect(
    source.startsWith('# Dart Terminal terminfo source contract version 1.'),
    'terminfo source version header is missing',
  );
  _expect(
    source.contains('\nxterm-256color|Dart Terminal audited '),
    'terminfo source public entry is missing',
  );
  _expect(
    source.contains('\tuse=${TerminalTerminfoContract.privateBaseName},'),
    'terminfo source does not inherit the pinned private base',
  );
  _expect(
    !source.contains('\tuse=xterm-256color,'),
    'terminfo source must not create a self-referential use loop',
  );
}

void _validateCapabilities(
  TerminalTerminfoContract contract,
  Set<String> capabilities,
) {
  for (final String capability in contract.requiredCapabilities) {
    _expect(
      capabilities.contains(capability),
      'compiled terminfo is missing required capability $capability',
    );
  }
  for (final String capability in contract.forbiddenCapabilities) {
    _expect(
      !capabilities.contains(capability),
      'compiled terminfo advertises forbidden capability $capability',
    );
  }
}

void _validateManifest(Directory root, String compiledPath) {
  final File manifest = File(_join(root.path, 'macos_application.json'));
  final Map<String, Object?> decoded = _object(
    jsonDecode(manifest.readAsStringSync()),
    'application manifest',
  );
  final List<Object?> resources = _array(
    decoded['resources'],
    'application manifest resources',
  );
  _expect(
    resources.contains(compiledPath) &&
        resources
                .where((Object? resource) => resource == compiledPath)
                .length ==
            1,
    'application manifest must contain the compiled terminfo resource once',
  );
}

Map<String, Object?> _object(Object? value, String name) {
  _expect(value is Map<String, Object?>, '$name must be an object');
  return value! as Map<String, Object?>;
}

List<Object?> _array(Object? value, String name) {
  _expect(value is List<Object?>, '$name must be an array');
  return value! as List<Object?>;
}

String _text(Object? value, String name) {
  _expect(value is String && value.isNotEmpty, '$name must be non-empty text');
  final String text = value! as String;
  _expect(utf8.encode(text).length <= 512, '$name is too long');
  return text;
}

String _relativePath(Object? value, String name) {
  final String path = _text(value, name);
  _expect(!path.startsWith('/'), '$name must be relative');
  final List<String> segments = path.split('/');
  _expect(
    segments.every(
      (String segment) =>
          segment.isNotEmpty && segment != '.' && segment != '..',
    ),
    '$name is not a normalized relative path',
  );
  return path;
}

String _absolutePath(Object? value, String name) {
  final String path = _text(value, name);
  _expect(path.startsWith('/'), '$name must be absolute');
  _expect(!path.split('/').contains('..'), '$name must be normalized');
  return path;
}

String _sha256(Object? value, String name) {
  final String hash = _text(value, name);
  _expect(
    RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),
    '$name must be lowercase SHA-256',
  );
  return hash;
}

List<String> _stringList(Object? value, String name) {
  final List<Object?> values = _array(value, name);
  _expect(values.isNotEmpty && values.length <= 128, '$name count is invalid');
  return <String>[
    for (int index = 0; index < values.length; index++)
      _text(values[index], '$name[$index]'),
  ];
}

List<String> _capabilityList(Object? value, String name) {
  final List<String> result = _stringList(value, name);
  String previous = '';
  for (final String capability in result) {
    _expect(
      RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(capability),
      '$name contains invalid capability $capability',
    );
    _expect(
      previous.isEmpty || previous.compareTo(capability) < 0,
      '$name must be sorted and unique',
    );
    previous = capability;
  }
  return result;
}

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String name,
) {
  _expect(
    value.keys.toSet().length == expected.length &&
        value.keys.toSet().containsAll(expected),
    '$name keys differ from the versioned schema',
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _join(String left, String right) =>
    left.endsWith('/') ? '$left$right' : '$left/$right';

Never _fail(String message) => throw TerminalTerminfoException(message);

void _expect(bool condition, String message) {
  if (!condition) _fail(message);
}
