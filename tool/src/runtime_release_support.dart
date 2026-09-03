import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

const String runtimeBundleAuditFormat = 'dart-terminal-runtime-bundle-audit';
const int runtimeBundleAuditVersion = 5;
const String runtimeBuildFingerprintFormat =
    'dart-terminal-runtime-build-fingerprint';
const int runtimeBuildFingerprintVersion = 7;
const String runtimeBuildManifestFormat =
    'dart-terminal-runtime-build-manifest';
const int runtimeBuildManifestVersion = 9;
const String runtimeBuildManifestRelativePath =
    'Resources/runtime-build-manifest.json';
const String runtimeMachOPolicy = 'dart-terminal-macos-runtime-v2';
const String runtimeDeveloperWorkerPayloadName = 'runtime_worker.dill';
const String runtimeReleaseWorkerExecutableName =
    'dart_terminal_runtime_worker';

const List<String> runtimeProjectProvenanceFiles = <String>[
  'Makefile',
  'pubspec.yaml',
  'pubspec.lock',
  'tool/runtime_build_fingerprint.dart',
  'tool/runtime_build_freshness_test.dart',
  'tool/runtime_engine_attestation.dart',
  'tool/runtime_build_manifest.dart',
  'tool/runtime_bundle_audit.dart',
  'tool/runtime_native_handoff.dart',
  'tool/runtime_universal_assembler.dart',
  'tool/runtime_release_negative_tests.dart',
  'tool/runtime_integration_smoke.dart',
  'tool/src/runtime_release_support.dart',
];

const List<String> runtimeProjectProvenanceDirectories = <String>[
  'bin',
  'lib',
  'native/macos/renderer',
  'native/macos/runtime',
];

const List<String> runtimeAppKitProvenanceFiles = <String>[
  '.clang-format',
  'Makefile',
  'packages/dart_appkit/pubspec.yaml',
];

const List<String> runtimeAppKitProvenanceDirectories = <String>[
  'native/bridge/include',
  'native/bridge/src',
  'native/runner',
  'packages/dart_appkit/lib',
];

bool runtimeSourceInventoryKeyIsAllowed(String key) {
  if (key == 'effective_override:extra_build_input') {
    return true;
  }
  for (final (String, List<String>, List<String>) repository
      in <(String, List<String>, List<String>)>[
        (
          'dart_terminal',
          runtimeProjectProvenanceFiles,
          runtimeProjectProvenanceDirectories,
        ),
        (
          'dart_appkit',
          runtimeAppKitProvenanceFiles,
          runtimeAppKitProvenanceDirectories,
        ),
      ]) {
    final String prefix = '${repository.$1}:';
    if (!key.startsWith(prefix)) {
      continue;
    }
    final String relative = key.substring(prefix.length);
    final List<String> segments = relative.split('/');
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.contains('\\') ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '.' || segment == '..',
        )) {
      return false;
    }
    return repository.$2.contains(relative) ||
        repository.$3.any(
          (String directory) => relative.startsWith('$directory/'),
        );
  }
  return false;
}

final class RuntimeAuditException implements Exception {
  const RuntimeAuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum RuntimeMode {
  developerJit(
    name: 'developer-jit',
    bundleIdentifier: 'dev.dart-terminal.developer-jit',
    payloadName: 'application.dill',
    engineName: 'libdart_engine_jit_shared.dylib',
    incompatiblePayloadName: 'application.aot',
    incompatibleEngineName: 'libdart_engine_aot_shared.dylib',
    engineConfiguration: 'release',
  ),
  releaseAot(
    name: 'release-aot',
    bundleIdentifier: 'dev.dart-terminal.release-aot',
    payloadName: 'application.aot',
    engineName: 'libdart_engine_aot_shared.dylib',
    incompatiblePayloadName: 'application.dill',
    incompatibleEngineName: 'libdart_engine_jit_shared.dylib',
    engineConfiguration: 'product',
  );

  const RuntimeMode({
    required this.name,
    required this.bundleIdentifier,
    required this.payloadName,
    required this.engineName,
    required this.incompatiblePayloadName,
    required this.incompatibleEngineName,
    required this.engineConfiguration,
  });

  final String name;
  final String bundleIdentifier;
  final String payloadName;
  final String engineName;
  final String incompatiblePayloadName;
  final String incompatibleEngineName;
  final String engineConfiguration;
}

RuntimeMode? runtimeModeByName(String name) => RuntimeMode.values
    .where((RuntimeMode candidate) => candidate.name == name)
    .firstOrNull;

const Set<String> supportedRuntimeArchitectures = <String>{'arm64', 'x86_64'};

final class RuntimeBundleAuditOptions {
  const RuntimeBundleAuditOptions({
    required this.mode,
    required this.expectedArchitectures,
    required this.deploymentTarget,
    required this.bundlePath,
  });

  final RuntimeMode mode;
  final Set<String> expectedArchitectures;
  final String deploymentTarget;
  final String bundlePath;
}

Future<ProcessResult> runRuntimeCommand(
  String executable,
  List<String> arguments,
) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    final String output = '${result.stdout}${result.stderr}'.trim();
    throw RuntimeAuditException(
      '${executable.split('/').last} failed (${result.exitCode})'
      '${output.isEmpty ? '' : ': $output'}',
    );
  }
  return result;
}

Future<String> runtimeCommandStdout(
  String executable,
  List<String> arguments,
) async {
  final ProcessResult result = await runRuntimeCommand(executable, arguments);
  return (result.stdout as String).trim();
}

Future<String> runtimePlistValue(String plistPath, String key) =>
    runtimeCommandStdout('/usr/bin/plutil', <String>[
      '-extract',
      key,
      'raw',
      '-o',
      '-',
      plistPath,
    ]);

Future<List<String>> runtimeArchitectures(String path) async {
  final String output = await runtimeCommandStdout('/usr/bin/lipo', <String>[
    '-archs',
    path,
  ]);
  return output
      .split(RegExp(r'\s+'))
      .where((String value) => value.isNotEmpty)
      .toList()
    ..sort();
}

bool sameStringSet(Iterable<String> left, Iterable<String> right) {
  final List<String> leftValues = left.toList();
  final List<String> rightValues = right.toList();
  final Set<String> leftSet = leftValues.toSet();
  final Set<String> rightSet = rightValues.toSet();
  return leftValues.length == leftSet.length &&
      rightValues.length == rightSet.length &&
      leftSet.length == rightSet.length &&
      leftSet.containsAll(rightSet);
}

Object? runtimeCanonicalJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List<Object?>) {
    return value.map<Object?>(runtimeCanonicalJsonValue).toList();
  }
  if (value is Map<String, Object?>) {
    final SplayTreeMap<String, Object?> result =
        SplayTreeMap<String, Object?>();
    for (final MapEntry<String, Object?> entry in value.entries) {
      result[entry.key] = runtimeCanonicalJsonValue(entry.value);
    }
    return result;
  }
  throw RuntimeAuditException(
    'unsupported canonical JSON value: ${value.runtimeType}',
  );
}

String runtimeCanonicalJsonEncode(Object? value) =>
    jsonEncode(runtimeCanonicalJsonValue(value));

void runtimeExpect(bool condition, String message) {
  if (!condition) {
    throw RuntimeAuditException(message);
  }
}

final class RuntimePathSnapshot {
  const RuntimePathSnapshot({
    required this.requestedPath,
    required this.canonicalPath,
    required this.leafType,
    required this.targetType,
    required this.targetIdentity,
    required this.existingAncestorIdentity,
    required this.ancestorIdentities,
  });

  final String requestedPath;
  final String canonicalPath;
  final FileSystemEntityType leafType;
  final FileSystemEntityType targetType;
  final String? targetIdentity;
  final String existingAncestorIdentity;
  final Set<String> ancestorIdentities;

  bool get exists => targetIdentity != null;
}

final class RuntimeWriteDestinationGuard {
  const RuntimeWriteDestinationGuard({
    required this.description,
    required this.destination,
    required this.protectedPaths,
    required this.allowedExistingTypes,
    required this.requireMissing,
  });

  final String description;
  final RuntimePathSnapshot destination;
  final Map<String, RuntimePathSnapshot> protectedPaths;
  final Set<FileSystemEntityType> allowedExistingTypes;
  final bool requireMissing;
}

String runtimeNormalizedAbsolutePath(String path) {
  runtimeExpect(File(path).isAbsolute, 'path must be absolute: $path');
  return File.fromUri(File(path).absolute.uri.normalizePath()).path;
}

Future<String> _runtimeFilesystemIdentity(String canonicalPath) async {
  final String value = await runtimeCommandStdout('/usr/bin/stat', <String>[
    '-f',
    '%d:%i',
    canonicalPath,
  ]);
  runtimeExpect(
    RegExp(r'^\d+:\d+$').hasMatch(value),
    'unexpected filesystem identity for $canonicalPath: $value',
  );
  return value;
}

String _runtimeJoinCanonical(String ancestor, List<String> suffix) {
  if (suffix.isEmpty) {
    return ancestor;
  }
  return ancestor == '/'
      ? '/${suffix.join('/')}'
      : '$ancestor/${suffix.join('/')}';
}

Future<RuntimePathSnapshot> runtimePathSnapshot(String path) async {
  final String requested = runtimeNormalizedAbsolutePath(path);
  final FileSystemEntityType leafType = await FileSystemEntity.type(
    requested,
    followLinks: false,
  );
  var candidate = requested;
  final List<String> missingSuffix = <String>[];
  FileSystemEntityType candidateType = leafType;
  while (candidateType == FileSystemEntityType.notFound) {
    final String parent = File(candidate).parent.path;
    runtimeExpect(parent != candidate, 'no existing ancestor for $requested');
    final String name = File(candidate).uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    runtimeExpect(
      name != '.' && name != '..' && !name.contains('/'),
      'unsafe path component in $requested',
    );
    missingSuffix.insert(0, name);
    candidate = parent;
    candidateType = await FileSystemEntity.type(candidate, followLinks: false);
  }
  runtimeExpect(
    candidateType == FileSystemEntityType.file ||
        candidateType == FileSystemEntityType.directory ||
        candidateType == FileSystemEntityType.link,
    'unsupported existing path ancestor: $candidate',
  );
  final String canonicalAncestor = await File(candidate).resolveSymbolicLinks();
  final String canonicalPath = _runtimeJoinCanonical(
    canonicalAncestor,
    missingSuffix,
  );
  final String existingAncestorIdentity = await _runtimeFilesystemIdentity(
    canonicalAncestor,
  );
  final Set<String> ancestorIdentities = <String>{};
  var ancestor = canonicalAncestor;
  while (true) {
    ancestorIdentities.add(await _runtimeFilesystemIdentity(ancestor));
    final String parent = File(ancestor).parent.path;
    if (parent == ancestor) {
      break;
    }
    ancestor = parent;
  }
  final bool exists = missingSuffix.isEmpty;
  final FileSystemEntityType targetType = exists
      ? await FileSystemEntity.type(canonicalPath, followLinks: true)
      : FileSystemEntityType.notFound;
  return RuntimePathSnapshot(
    requestedPath: requested,
    canonicalPath: canonicalPath,
    leafType: leafType,
    targetType: targetType,
    targetIdentity: exists ? existingAncestorIdentity : null,
    existingAncestorIdentity: existingAncestorIdentity,
    ancestorIdentities: ancestorIdentities,
  );
}

bool runtimePathSnapshotsOverlap(
  RuntimePathSnapshot left,
  RuntimePathSnapshot right,
) {
  if (left.targetIdentity != null &&
      left.targetIdentity == right.targetIdentity) {
    return true;
  }
  if (left.targetIdentity != null &&
      right.ancestorIdentities.contains(left.targetIdentity)) {
    return true;
  }
  if (right.targetIdentity != null &&
      left.ancestorIdentities.contains(right.targetIdentity)) {
    return true;
  }
  bool within(String child, String parent) =>
      child == parent || child.startsWith(parent == '/' ? '/' : '$parent/');
  return within(left.canonicalPath, right.canonicalPath) ||
      within(right.canonicalPath, left.canonicalPath);
}

Future<Map<String, RuntimePathSnapshot>> runtimeValidateDisjointExistingPaths(
  Map<String, String> paths,
) async {
  final Map<String, RuntimePathSnapshot> snapshots =
      <String, RuntimePathSnapshot>{};
  for (final MapEntry<String, String> entry in paths.entries) {
    final RuntimePathSnapshot snapshot = await runtimePathSnapshot(entry.value);
    runtimeExpect(
      snapshot.exists,
      '${entry.key} does not exist: ${entry.value}',
    );
    runtimeExpect(
      snapshot.leafType != FileSystemEntityType.link,
      '${entry.key} must not be a symbolic link: ${entry.value}',
    );
    for (final MapEntry<String, RuntimePathSnapshot> previous
        in snapshots.entries) {
      runtimeExpect(
        !runtimePathSnapshotsOverlap(snapshot, previous.value),
        '${entry.key} aliases or contains ${previous.key}',
      );
    }
    snapshots[entry.key] = snapshot;
  }
  return snapshots;
}

Future<RuntimeWriteDestinationGuard> runtimeValidateWriteDestination({
  required String description,
  required String destination,
  required Map<String, String> protectedPaths,
  required Set<FileSystemEntityType> allowedExistingTypes,
  bool requireMissing = false,
}) async {
  final RuntimePathSnapshot output = await runtimePathSnapshot(destination);
  runtimeExpect(
    output.leafType != FileSystemEntityType.link,
    '$description must not be a symbolic link',
  );
  runtimeExpect(
    !requireMissing || !output.exists,
    '$description already exists and is immutable: ${output.canonicalPath}',
  );
  runtimeExpect(
    !output.exists || allowedExistingTypes.contains(output.targetType),
    '$description has unsafe type ${output.targetType}',
  );
  final Map<String, RuntimePathSnapshot> protected =
      await runtimeValidateDisjointExistingPaths(protectedPaths);
  for (final MapEntry<String, RuntimePathSnapshot> entry in protected.entries) {
    runtimeExpect(
      !runtimePathSnapshotsOverlap(output, entry.value),
      '$description aliases, contains, or is inside ${entry.key}',
    );
  }
  return RuntimeWriteDestinationGuard(
    description: description,
    destination: output,
    protectedPaths: protected,
    allowedExistingTypes: allowedExistingTypes,
    requireMissing: requireMissing,
  );
}

Future<void> runtimeRevalidateWriteDestination(
  RuntimeWriteDestinationGuard guard,
) async {
  final RuntimeWriteDestinationGuard current =
      await runtimeValidateWriteDestination(
        description: guard.description,
        destination: guard.destination.requestedPath,
        protectedPaths: <String, String>{
          for (final MapEntry<String, RuntimePathSnapshot> entry
              in guard.protectedPaths.entries)
            entry.key: entry.value.requestedPath,
        },
        allowedExistingTypes: guard.allowedExistingTypes,
        requireMissing: guard.requireMissing,
      );
  runtimeExpect(
    current.destination.canonicalPath == guard.destination.canonicalPath &&
        current.destination.targetIdentity ==
            guard.destination.targetIdentity &&
        current.destination.leafType == guard.destination.leafType,
    '${guard.description} changed after validation',
  );
  for (final MapEntry<String, RuntimePathSnapshot> entry
      in guard.protectedPaths.entries) {
    final RuntimePathSnapshot actual = current.protectedPaths[entry.key]!;
    runtimeExpect(
      actual.targetIdentity == entry.value.targetIdentity &&
          actual.canonicalPath == entry.value.canonicalPath,
      '${entry.key} changed after validation',
    );
  }
}

Map<String, Object?> runtimeStringMap(Object? value, String description) {
  runtimeExpect(
    value is Map<String, Object?>,
    '$description must be an object',
  );
  return value! as Map<String, Object?>;
}

String runtimeRequiredString(
  Map<String, Object?> object,
  String key,
  String description,
) {
  final Object? value = object[key];
  runtimeExpect(
    value is String && value.isNotEmpty,
    '$description.$key must be a non-empty string',
  );
  return value! as String;
}

Future<String> runtimeSha256File(String path) async {
  final String output = await runtimeCommandStdout('/usr/bin/shasum', <String>[
    '-a',
    '256',
    path,
  ]);
  return output.split(RegExp(r'\s+')).first;
}

Future<String> runtimeMachOContentSha256(String path) async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-macho-content-',
  );
  try {
    final File normalized = File('${temporary.path}/unsigned-macho');
    await File(path).copy(normalized.path);
    await runRuntimeCommand('/usr/bin/codesign', <String>[
      '--remove-signature',
      normalized.path,
    ]);
    return await runtimeSha256File(normalized.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<String> runtimeSha256Text(String value) async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-sha256-',
  );
  try {
    final File input = File('${temporary.path}/input');
    await input.writeAsString(value, flush: true);
    return await runtimeSha256File(input.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> runtimeWriteTextIfChanged(String path, String contents) async {
  final File output = File(path).absolute;
  final FileSystemEntityType type = await FileSystemEntity.type(
    output.path,
    followLinks: false,
  );
  runtimeExpect(
    type == FileSystemEntityType.notFound || type == FileSystemEntityType.file,
    'output is not a regular file: ${output.path}',
  );
  if (type == FileSystemEntityType.file &&
      await output.readAsString() == contents) {
    return;
  }
  await output.parent.create(recursive: true);
  final File temporary = File('${output.path}.tmp.$pid');
  try {
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(output.path);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

Future<void> runtimeWriteJsonIfChanged(
  String path,
  Map<String, Object?> value,
) => runtimeWriteTextIfChanged(
  path,
  '${const JsonEncoder.withIndent('  ').convert(value)}\n',
);

Future<void> runtimeWriteJsonExclusive(
  String path,
  Map<String, Object?> value,
) async {
  final File output = File(runtimeNormalizedAbsolutePath(path));
  await output.parent.create(recursive: true);
  final File temporary = File(
    '${output.parent.path}/.${output.uri.pathSegments.last}.tmp.$pid',
  );
  try {
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      flush: true,
    );
    await runRuntimeCommand('/bin/ln', <String>[temporary.path, output.path]);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

Future<List<String>> runtimeRelativeFiles(Directory contents) async {
  final List<String> paths = <String>[];
  await for (final FileSystemEntity entity in contents.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Link) {
      throw RuntimeAuditException(
        'bundle contains unsupported symbolic link: ${entity.path}',
      );
    }
    if (entity is File) {
      paths.add(entity.path.substring(contents.path.length + 1));
    }
  }
  paths.sort();
  return paths;
}

Future<bool> runtimeIsMachO(String path) async {
  final ProcessResult result = await Process.run('/usr/bin/lipo', <String>[
    '-archs',
    path,
  ]);
  return result.exitCode == 0;
}

Future<SplayTreeMap<String, Object?>> runtimeBundleSeal(
  String bundlePath,
) async {
  final Directory root = Directory(bundlePath).absolute;
  runtimeExpect(await root.exists(), 'bundle does not exist: ${root.path}');
  final List<FileSystemEntity> entities = await root
      .list(recursive: true, followLinks: false)
      .toList();
  entities.sort(
    (FileSystemEntity left, FileSystemEntity right) =>
        left.path.compareTo(right.path),
  );
  final SplayTreeMap<String, Object?> seal = SplayTreeMap<String, Object?>();
  for (final FileSystemEntity entity in entities) {
    final String relative = entity.path.substring(root.path.length + 1);
    final FileStat stat = await entity.stat();
    if (entity is Link) {
      seal[relative] = <String, Object?>{
        'type': 'link',
        'mode': stat.mode,
        'target': await entity.target(),
      };
    } else if (entity is Directory) {
      seal[relative] = <String, Object?>{
        'type': 'directory',
        'mode': stat.mode,
      };
    } else if (entity is File) {
      seal[relative] = <String, Object?>{
        'type': 'file',
        'mode': stat.mode,
        'size': stat.size,
        'sha256': await runtimeSha256File(entity.path),
      };
    } else {
      throw RuntimeAuditException('unsupported bundle entity: ${entity.path}');
    }
  }
  return seal;
}

Future<Map<String, Object?>> _readJsonObject(
  String path,
  String description,
) async {
  final File file = File(path);
  runtimeExpect(await file.exists(), 'missing $description: $path');
  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException catch (error) {
    throw RuntimeAuditException('invalid $description: $error');
  }
  return runtimeStringMap(decoded, description);
}

void _validateHashMap(Object? value, String description) {
  final Map<String, Object?> hashes = runtimeStringMap(value, description);
  runtimeExpect(hashes.isNotEmpty, '$description is empty');
  for (final MapEntry<String, Object?> entry in hashes.entries) {
    runtimeExpect(entry.key.isNotEmpty, '$description contains an empty key');
    _validateSha256(entry.value, '$description.${entry.key}');
  }
}

void _validateSha256(Object? value, String description) {
  runtimeExpect(
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
    'invalid SHA-256 for $description',
  );
}

Map<String, Object?> _validateExactHashMap(
  Object? value,
  Set<String> expectedKeys,
  String description,
) {
  final Map<String, Object?> hashes = runtimeStringMap(value, description);
  runtimeExpect(
    sameStringSet(hashes.keys, expectedKeys),
    '$description roles ${hashes.keys.toList()..sort()} != '
    '${expectedKeys.toList()..sort()}',
  );
  _validateHashMap(hashes, description);
  return hashes;
}

void _validateRepositoryIdentity(Object? value, String description) {
  final Map<String, Object?> identity = runtimeStringMap(value, description);
  runtimeExpect(
    sameStringSet(identity.keys, const <String>{
      'revision',
      'dirty',
      'status_sha256',
      'diff_sha256',
    }),
    '$description schema mismatch',
  );
  runtimeRequiredString(identity, 'revision', description);
  runtimeExpect(identity['dirty'] is bool, '$description.dirty must be a bool');
  _validateSha256(identity['status_sha256'], '$description.status_sha256');
  _validateSha256(identity['diff_sha256'], '$description.diff_sha256');
}

Set<String> _laneInputRoles(RuntimeMode mode) => <String>{
  'dart_engine',
  'kernel_compiler',
  'platform_dill',
  if (mode == RuntimeMode.developerJit) 'runtime_worker_dart',
  if (mode == RuntimeMode.releaseAot) 'runtime_worker_compiler',
  if (mode == RuntimeMode.releaseAot) 'snapshotter',
};

Set<String> _laneProducedRoles(RuntimeMode mode) => <String>{
  if (mode == RuntimeMode.developerJit) 'launcher',
  if (mode == RuntimeMode.releaseAot) 'launcher_content',
  'dart_engine',
  if (mode == RuntimeMode.developerJit) 'kernel_payload',
  if (mode == RuntimeMode.developerJit) 'worker_kernel_payload',
  if (mode == RuntimeMode.releaseAot) 'aot_snapshot',
  if (mode == RuntimeMode.releaseAot) 'worker_executable',
};

List<String> _requiredStringList(Object? value, String description) {
  if (value is! List<Object?> ||
      value.isEmpty ||
      !value.every((Object? entry) => entry is String && entry.isNotEmpty)) {
    throw RuntimeAuditException('$description must be non-empty strings');
  }
  return value.whereType<String>().toList();
}

const Set<String> _recordableMachOArchitectures = <String>{
  'arm64',
  'arm64e',
  'x86_64',
};

List<String> _requiredCanonicalMachOArchitectures(
  Object? value,
  String description,
) {
  if (value is! List<Object?> ||
      value.isEmpty ||
      !value.every(
        (Object? entry) =>
            entry is String && _recordableMachOArchitectures.contains(entry),
      )) {
    throw RuntimeAuditException(
      '$description must be a canonical unique Mach-O architecture list',
    );
  }
  final List<String> architectures = value.whereType<String>().toList();
  final List<String> canonical = architectures.toSet().toList()..sort();
  if (architectures.length != canonical.length) {
    throw RuntimeAuditException(
      '$description must be a canonical unique Mach-O architecture list',
    );
  }
  for (var index = 0; index < canonical.length; ++index) {
    if (architectures[index] != canonical[index]) {
      throw RuntimeAuditException(
        '$description must be a canonical unique Mach-O architecture list',
      );
    }
  }
  return architectures;
}

Map<String, Object?> _buildToolRecord(
  Object? value,
  String description,
  Set<String> expectedKeys,
) {
  final Map<String, Object?> record = runtimeStringMap(value, description);
  runtimeExpect(
    sameStringSet(record.keys, expectedKeys),
    '$description schema mismatch',
  );
  final String path = runtimeRequiredString(record, 'path', description);
  runtimeExpect(File(path).isAbsolute, '$description path is not absolute');
  _validateSha256(record['sha256'], '$description.sha256');
  _requiredStringList(record['arguments'], '$description.arguments');
  if (expectedKeys.contains('version')) {
    runtimeRequiredString(record, 'version', description);
  }
  if (expectedKeys.contains('revision')) {
    runtimeRequiredString(record, 'revision', description);
  }
  if (expectedKeys.contains('architectures')) {
    _requiredCanonicalMachOArchitectures(
      record['architectures'],
      '$description.architectures',
    );
  }
  return record;
}

void _validateBuildTools(
  Object? value,
  String architecture,
  RuntimeMode mode,
  String expectedSdkVersion,
  String expectedSdkRevision,
  Map<String, Object?> resolvedPaths,
  String description,
) {
  final String projectRoot = runtimeRequiredString(
    resolvedPaths,
    'project_root',
    '$description resolved paths',
  );
  final String engineRoot = runtimeRequiredString(
    resolvedPaths,
    'dart_engine_root',
    '$description resolved paths',
  );
  final String sdkRoot = runtimeRequiredString(
    resolvedPaths,
    'dart_sdk_root',
    '$description resolved paths',
  );
  final Map<String, Object?> tools = runtimeStringMap(value, description);
  final Set<String> expectedRoles = <String>{
    'dart',
    'engine_gn',
    'engine_ninja',
    'engine_python',
    'make',
    if (mode == RuntimeMode.releaseAot) 'snapshotter_runner',
  };
  runtimeExpect(
    sameStringSet(tools.keys, expectedRoles),
    '$description roles mismatch',
  );
  final Map<String, Object?> dart = _buildToolRecord(
    tools['dart'],
    '$description.dart',
    const <String>{
      'path',
      'sha256',
      'version',
      'revision',
      'architectures',
      'arguments',
    },
  );
  runtimeExpect(
    dart['path'] == runtimeNormalizedAbsolutePath('$sdkRoot/bin/dart') &&
        dart['version'] == expectedSdkVersion &&
        dart['revision'] == expectedSdkRevision,
    '$description Dart executable path/SDK identity mismatch',
  );
  final List<String> dartArguments = _requiredStringList(
    dart['arguments'],
    '$description.dart.arguments',
  );
  runtimeExpect(
    dartArguments.length == 2 &&
        dartArguments.first == 'run' &&
        dartArguments.last ==
            runtimeNormalizedAbsolutePath(
              '$projectRoot/tool/runtime_build_fingerprint.dart',
            ),
    '$description Dart executable arguments mismatch',
  );
  final Map<String, Object?> gn = _buildToolRecord(
    tools['engine_gn'],
    '$description.engine_gn',
    const <String>{'path', 'sha256', 'arguments'},
  );
  final String engineArchitecture = architecture == 'arm64' ? 'arm64' : 'x64';
  runtimeExpect(
    gn['path'] == runtimeNormalizedAbsolutePath('$engineRoot/tools/gn.py') &&
        sameStringSet(
          _requiredStringList(
            gn['arguments'],
            '$description.engine_gn.arguments',
          ),
          <String>[
            '--mode=${mode == RuntimeMode.releaseAot ? 'product' : 'release'}',
            '--arch=$engineArchitecture',
          ],
        ),
    '$description Engine GN invocation mismatch',
  );
  final Map<String, Object?> ninja = _buildToolRecord(
    tools['engine_ninja'],
    '$description.engine_ninja',
    const <String>{'path', 'sha256', 'version', 'architectures', 'arguments'},
  );
  final List<String> ninjaArguments = _requiredStringList(
    ninja['arguments'],
    '$description.engine_ninja.arguments',
  );
  final String outputName =
      '${mode == RuntimeMode.releaseAot ? 'Product' : 'Release'}'
      '${architecture == 'arm64' ? 'ARM64' : 'X64'}';
  final String expectedOutputDirectory = runtimeNormalizedAbsolutePath(
    '$engineRoot/xcodebuild/$outputName',
  );
  final List<String> expectedNinjaTargets = <String>[
    mode == RuntimeMode.developerJit
        ? 'dart_engine_jit_shared'
        : 'dart_engine_aot_shared',
    if (mode == RuntimeMode.releaseAot) 'gen_snapshot',
    'bootstrap_gen_kernel.exe',
    '${architecture == 'arm64' ? 'clang_arm64_shared' : 'clang_x64_shared'}/vm_platform.dill',
  ];
  runtimeExpect(
    ninja['path'] ==
            runtimeNormalizedAbsolutePath(
              '$engineRoot/buildtools/ninja/ninja',
            ) &&
        ninjaArguments.length == expectedNinjaTargets.length + 2 &&
        ninjaArguments[0] == '-C' &&
        runtimeNormalizedAbsolutePath(ninjaArguments[1]) ==
            expectedOutputDirectory &&
        sameStringSet(ninjaArguments.skip(2), expectedNinjaTargets),
    '$description Engine Ninja invocation mismatch',
  );
  final Map<String, Object?> python = _buildToolRecord(
    tools['engine_python'],
    '$description.engine_python',
    const <String>{'path', 'sha256', 'version', 'architectures', 'arguments'},
  );
  final List<String> pythonArguments = _requiredStringList(
    python['arguments'],
    '$description.engine_python.arguments',
  );
  runtimeExpect(
    python['path'] == '/usr/bin/python3' &&
        pythonArguments.length == 3 &&
        pythonArguments.first == gn['path'] &&
        sameStringSet(
          pythonArguments.skip(1),
          _requiredStringList(
            gn['arguments'],
            '$description.engine_gn.arguments',
          ),
        ),
    '$description Engine Python identity/invocation mismatch',
  );
  final Map<String, Object?> make = _buildToolRecord(
    tools['make'],
    '$description.make',
    const <String>{'path', 'sha256', 'version', 'architectures', 'arguments'},
  );
  runtimeExpect(
    make['path'] == '/usr/bin/make' &&
        sameStringSet(
          _requiredStringList(make['arguments'], '$description.make.arguments'),
          <String>[
            'RUNTIME_ARCH=$architecture',
            mode == RuntimeMode.developerJit
                ? 'developer-jit-build'
                : 'release-aot-build',
          ],
        ),
    '$description recursive Make identity/invocation mismatch',
  );
  if (mode == RuntimeMode.releaseAot) {
    final Map<String, Object?> runner = _buildToolRecord(
      tools['snapshotter_runner'],
      '$description.snapshotter_runner',
      const <String>{'path', 'sha256', 'architectures', 'arguments'},
    );
    runtimeExpect(
      runner['path'] == '/usr/bin/arch' &&
          sameStringSet(
            _requiredStringList(
              runner['arguments'],
              '$description.snapshotter_runner.arguments',
            ),
            <String>['-$architecture'],
          ),
      '$description snapshotter runner identity/invocation mismatch',
    );
  }
}

void _validateArchitectureLane(
  Map<String, Object?> lane,
  String architecture,
  RuntimeMode mode,
  String description,
  String expectedPlatformDillHash,
  String expectedSdkVersion,
  String expectedSdkRevision,
  bool hasExtraBuildInput,
) {
  final Set<String> expectedLaneKeys = <String>{
    'architecture',
    'engine_gn_arguments',
    'input_binary_sha256',
    'input_binary_architectures',
    'resolved_input_paths',
    'build_tools',
    'package_config',
    'build_environment',
    'fingerprint_sha256',
    'produced_sha256',
    if (mode == RuntimeMode.releaseAot) 'intermediate_kernel_sha256',
  };
  runtimeExpect(
    sameStringSet(lane.keys, expectedLaneKeys),
    '$description schema mismatch',
  );
  runtimeExpect(
    lane['architecture'] == architecture,
    '$description architecture ${lane['architecture']} != $architecture',
  );
  final String engineArchitecture = architecture == 'arm64' ? 'arm64' : 'x64';
  final Map<String, Object?> gn = runtimeStringMap(
    lane['engine_gn_arguments'],
    '$description.engine_gn_arguments',
  );
  final Map<String, String> expectedGn = <String, String>{
    'dart_target_arch': '"$engineArchitecture"',
    'host_cpu': '"$engineArchitecture"',
    'target_cpu': '"$engineArchitecture"',
  };
  runtimeExpect(
    sameStringSet(gn.keys, expectedGn.keys) &&
        expectedGn.entries.every(
          (MapEntry<String, String> entry) => gn[entry.key] == entry.value,
        ),
    '$description Engine GN architecture does not match $architecture',
  );
  final Set<String> inputRoles = _laneInputRoles(mode);
  final Map<String, Object?> inputs = _validateExactHashMap(
    lane['input_binary_sha256'],
    inputRoles,
    '$description.input_binary_sha256',
  );
  runtimeExpect(
    inputs['platform_dill'] == expectedPlatformDillHash,
    '$description platform dill differs from semantic provenance',
  );
  final Map<String, Object?> inputArchitectures = runtimeStringMap(
    lane['input_binary_architectures'],
    '$description.input_binary_architectures',
  );
  final Set<String> expectedArchitectureRoles = <String>{
    'dart_engine',
    'kernel_compiler',
    if (mode == RuntimeMode.developerJit) 'runtime_worker_dart',
    if (mode == RuntimeMode.releaseAot) 'runtime_worker_compiler',
    if (mode == RuntimeMode.releaseAot) 'snapshotter',
  };
  runtimeExpect(
    sameStringSet(inputArchitectures.keys, expectedArchitectureRoles),
    '$description input binary architecture roles differ',
  );
  for (final MapEntry<String, Object?> entry in inputArchitectures.entries) {
    final List<String> slices = _requiredCanonicalMachOArchitectures(
      entry.value,
      '$description ${entry.key} architectures',
    );
    if (entry.key == 'dart_engine' ||
        entry.key == 'runtime_worker_dart' ||
        entry.key == 'snapshotter') {
      runtimeExpect(
        sameStringSet(slices, <String>[architecture]),
        '$description ${entry.key} does not target $architecture',
      );
    }
  }
  final Map<String, Object?> paths = runtimeStringMap(
    lane['resolved_input_paths'],
    '$description.resolved_input_paths',
  );
  runtimeExpect(
    sameStringSet(paths.keys, inputRoles) &&
        paths.values.every(
          (Object? path) =>
              path is String && path.isNotEmpty && File(path).isAbsolute,
        ),
    '$description resolved input paths do not match required roles',
  );
  final Map<String, Object?> environment = runtimeStringMap(
    lane['build_environment'],
    '$description.build_environment',
  );
  runtimeExpect(
    sameStringSet(environment.keys, const <String>{
      'resolved_paths',
      'host_tool_sha256',
      'host_tool_architectures',
    }),
    '$description build environment schema mismatch',
  );
  final Map<String, Object?> environmentPaths = runtimeStringMap(
    environment['resolved_paths'],
    '$description.build_environment.resolved_paths',
  );
  final Set<String> expectedEnvironmentPathRoles = <String>{
    'project_root',
    'dart_appkit_root',
    'dart_engine_root',
    'dart_sdk_root',
    'runtime_build_root',
    'clang',
    'sdk_root',
    if (hasExtraBuildInput) 'extra_build_input',
  };
  runtimeExpect(
    sameStringSet(environmentPaths.keys, expectedEnvironmentPathRoles) &&
        environmentPaths.values.every(
          (Object? value) => value is String && File(value).isAbsolute,
        ),
    '$description build environment resolved-path schema mismatch',
  );
  final String projectRoot = runtimeRequiredString(
    environmentPaths,
    'project_root',
    '$description.build_environment.resolved_paths',
  );
  final String appKitRoot = runtimeRequiredString(
    environmentPaths,
    'dart_appkit_root',
    '$description.build_environment.resolved_paths',
  );
  final String engineRoot = runtimeRequiredString(
    environmentPaths,
    'dart_engine_root',
    '$description.build_environment.resolved_paths',
  );
  final String sdkRoot = runtimeRequiredString(
    environmentPaths,
    'dart_sdk_root',
    '$description.build_environment.resolved_paths',
  );
  final String outputName =
      '${mode == RuntimeMode.releaseAot ? 'Product' : 'Release'}'
      '${architecture == 'arm64' ? 'ARM64' : 'X64'}';
  final String engineOutput = runtimeNormalizedAbsolutePath(
    '$engineRoot/xcodebuild/$outputName',
  );
  final String engineToolchain = architecture == 'arm64'
      ? 'clang_arm64_shared'
      : 'clang_x64_shared';
  final Map<String, String> expectedInputPaths = <String, String>{
    'dart_engine': runtimeNormalizedAbsolutePath(
      '$engineOutput/${mode.engineName}',
    ),
    'kernel_compiler': runtimeNormalizedAbsolutePath(
      '$engineOutput/bootstrap_gen_kernel.exe',
    ),
    'platform_dill': runtimeNormalizedAbsolutePath(
      '$engineOutput/$engineToolchain/vm_platform.dill',
    ),
    if (mode == RuntimeMode.developerJit)
      'runtime_worker_dart': runtimeNormalizedAbsolutePath('$sdkRoot/bin/dart'),
    if (mode == RuntimeMode.releaseAot)
      'runtime_worker_compiler': runtimeNormalizedAbsolutePath(
        '$sdkRoot/bin/dart',
      ),
    if (mode == RuntimeMode.releaseAot)
      'snapshotter': runtimeNormalizedAbsolutePath(
        '$engineOutput/gen_snapshot',
      ),
  };
  runtimeExpect(
    expectedInputPaths.entries.every(
      (MapEntry<String, String> entry) => paths[entry.key] == entry.value,
    ),
    '$description resolved Engine input paths are incoherent',
  );
  _validateBuildTools(
    lane['build_tools'],
    architecture,
    mode,
    expectedSdkVersion,
    expectedSdkRevision,
    environmentPaths,
    '$description.build_tools',
  );
  final Map<String, Object?> packageConfig = runtimeStringMap(
    lane['package_config'],
    '$description.package_config',
  );
  runtimeExpect(
    sameStringSet(packageConfig.keys, const <String>{
      'path',
      'raw_sha256',
      'resolved_package_roots',
      'pub_cache',
    }),
    '$description package config diagnostic schema mismatch',
  );
  final String packageConfigPath = runtimeRequiredString(
    packageConfig,
    'path',
    '$description.package_config',
  );
  runtimeExpect(
    File(packageConfigPath).isAbsolute,
    '$description package config path is not absolute',
  );
  _validateSha256(
    packageConfig['raw_sha256'],
    '$description.package_config.raw_sha256',
  );
  final Map<String, Object?> resolvedPackageRoots = runtimeStringMap(
    packageConfig['resolved_package_roots'],
    '$description.package_config.resolved_package_roots',
  );
  runtimeExpect(
    sameStringSet(resolvedPackageRoots.keys, const <String>{
          'dart_terminal',
          'dart_appkit',
        }) &&
        resolvedPackageRoots['dart_terminal'] == projectRoot &&
        resolvedPackageRoots['dart_appkit'] ==
            runtimeNormalizedAbsolutePath('$appKitRoot/packages/dart_appkit'),
    '$description package roots are invalid',
  );
  runtimeRequiredString(
    packageConfig,
    'pub_cache',
    '$description.package_config',
  );
  _validateExactHashMap(environment['host_tool_sha256'], const <String>{
    'clang',
  }, '$description.build_environment.host_tool_sha256');
  final Map<String, Object?> hostArchitectures = runtimeStringMap(
    environment['host_tool_architectures'],
    '$description.build_environment.host_tool_architectures',
  );
  runtimeExpect(
    sameStringSet(hostArchitectures.keys, const <String>{'clang'}),
    '$description host tool architecture roles are invalid',
  );
  _requiredCanonicalMachOArchitectures(
    hostArchitectures['clang'],
    '$description.build_environment.host_tool_architectures.clang',
  );
  _validateSha256(
    lane['fingerprint_sha256'],
    '$description.fingerprint_sha256',
  );
  final Map<String, Object?> produced = _validateExactHashMap(
    lane['produced_sha256'],
    _laneProducedRoles(mode),
    '$description.produced_sha256',
  );
  if (mode == RuntimeMode.developerJit) {
    runtimeExpect(
      produced['dart_engine'] == inputs['dart_engine'],
      '$description produced Engine does not match its fingerprinted input',
    );
  }
  if (mode == RuntimeMode.releaseAot) {
    _validateSha256(
      lane['intermediate_kernel_sha256'],
      '$description.intermediate_kernel_sha256',
    );
  } else {
    runtimeExpect(
      !lane.containsKey('intermediate_kernel_sha256'),
      '$description developer JIT lane has an AOT intermediate',
    );
  }
}

Future<Map<String, Object?>> readRuntimeBuildManifest(
  String manifestPath, {
  required RuntimeMode expectedMode,
  required Set<String> expectedArchitectures,
  required String expectedDeploymentTarget,
  required String expectedBundleVersion,
  required String expectedExecutable,
  required Map<String, String> actualProducedHashes,
}) async {
  final Map<String, Object?> manifest = await _readJsonObject(
    manifestPath,
    'runtime build manifest',
  );
  runtimeExpect(
    manifest['format'] == runtimeBuildManifestFormat,
    'unsupported runtime build manifest format',
  );
  runtimeExpect(
    manifest['version'] == runtimeBuildManifestVersion,
    'unsupported runtime build manifest version',
  );
  final bool isUniversal = expectedArchitectures.length == 2;
  final Set<String> expectedManifestKeys = <String>{
    'format',
    'version',
    'architecture',
    'runtime_mode',
    'engine_configuration',
    'deployment_target',
    'bundle',
    'dart_sdk',
    'dart_engine',
    'dart_appkit',
    'toolchain',
    'package_config',
    'architecture_neutral_inputs',
    'source',
    'effective_configuration',
    'architecture_inputs',
    if (isUniversal) 'publication_generation_sha256',
  };
  runtimeExpect(
    sameStringSet(manifest.keys, expectedManifestKeys),
    'runtime build manifest top-level schema mismatch',
  );
  final String expectedManifestArchitecture = isUniversal
      ? 'universal'
      : expectedArchitectures.single;
  runtimeExpect(
    manifest['architecture'] == expectedManifestArchitecture,
    'runtime build manifest architecture ${manifest['architecture']} != '
    '$expectedManifestArchitecture',
  );
  runtimeExpect(
    manifest['runtime_mode'] == expectedMode.name,
    'runtime build manifest mode ${manifest['runtime_mode']} != '
    '${expectedMode.name}',
  );
  runtimeExpect(
    manifest['engine_configuration'] == expectedMode.engineConfiguration,
    'runtime build manifest Engine configuration '
    '${manifest['engine_configuration']} != '
    '${expectedMode.engineConfiguration}',
  );
  runtimeExpect(
    manifest['deployment_target'] == expectedDeploymentTarget,
    'runtime build manifest deployment target '
    '${manifest['deployment_target']} != $expectedDeploymentTarget',
  );

  final Map<String, Object?> bundle = runtimeStringMap(
    manifest['bundle'],
    'runtime build manifest bundle',
  );
  runtimeExpect(
    sameStringSet(bundle.keys, const <String>{
          'identifier',
          'version',
          'executable',
        }) &&
        bundle['identifier'] == expectedMode.bundleIdentifier,
    'runtime build manifest bundle identifier mismatch',
  );
  runtimeExpect(
    bundle['version'] == expectedBundleVersion,
    'runtime build manifest bundle version mismatch',
  );
  runtimeExpect(
    bundle['executable'] == expectedExecutable,
    'runtime build manifest executable mismatch',
  );

  final Map<String, Object?> dartSdk = runtimeStringMap(
    manifest['dart_sdk'],
    'runtime build manifest dart_sdk',
  );
  runtimeExpect(
    sameStringSet(dartSdk.keys, const <String>{'version', 'revision'}),
    'runtime build manifest Dart SDK schema mismatch',
  );
  runtimeRequiredString(dartSdk, 'version', 'runtime build manifest dart_sdk');
  runtimeRequiredString(dartSdk, 'revision', 'runtime build manifest dart_sdk');
  final Map<String, Object?> engine = runtimeStringMap(
    manifest['dart_engine'],
    'runtime build manifest dart_engine',
  );
  runtimeExpect(
    sameStringSet(engine.keys, const <String>{
      'revision',
      'source_policy',
      'gn_arguments',
      'repository',
    }),
    'runtime build manifest Dart Engine schema mismatch',
  );
  final String engineRevision = runtimeRequiredString(
    engine,
    'revision',
    'runtime build manifest dart_engine',
  );
  runtimeExpect(
    engineRevision == dartSdk['revision'],
    'runtime build manifest Dart SDK/Engine revisions differ',
  );
  runtimeExpect(
    engine['source_policy'] == 'official-clean',
    'runtime build manifest Dart Engine source policy mismatch',
  );
  final Map<String, Object?> engineGnArguments = runtimeStringMap(
    engine['gn_arguments'],
    'runtime build manifest dart_engine.gn_arguments',
  );
  runtimeExpect(
    engineGnArguments['target_os'] == '"mac"',
    'runtime build manifest Engine target_os is not mac',
  );
  runtimeExpect(
    engineGnArguments['is_debug'] == 'false' &&
        engineGnArguments['is_product'] ==
            (expectedMode == RuntimeMode.releaseAot ? 'true' : 'false') &&
        engineGnArguments['is_release'] ==
            (expectedMode == RuntimeMode.developerJit ? 'true' : 'false'),
    'runtime build manifest Engine mode arguments are inconsistent',
  );
  _validateRepositoryIdentity(engine['repository'], 'dart_engine.repository');
  final Map<String, Object?> engineRepository = runtimeStringMap(
    engine['repository'],
    'dart_engine.repository',
  );
  runtimeExpect(
    engineRepository['dirty'] == false,
    'runtime build manifest Dart Engine cleanliness differs from policy',
  );

  final Map<String, Object?> appkit = runtimeStringMap(
    manifest['dart_appkit'],
    'runtime build manifest dart_appkit',
  );
  runtimeExpect(
    sameStringSet(appkit.keys, const <String>{'repository'}),
    'runtime build manifest AppKit schema mismatch',
  );
  _validateRepositoryIdentity(appkit['repository'], 'dart_appkit.repository');
  final Map<String, Object?> toolchain = runtimeStringMap(
    manifest['toolchain'],
    'runtime build manifest toolchain',
  );
  runtimeExpect(
    sameStringSet(toolchain.keys, const <String>{
      'xcode_version',
      'xcode_build_version',
      'macos_sdk_version',
      'macos_sdk_build_version',
      'macos_sdk_settings_sha256',
      'clang_version',
      'compiler_driver',
    }),
    'runtime build manifest toolchain schema mismatch',
  );
  for (final String key in <String>[
    'xcode_version',
    'xcode_build_version',
    'macos_sdk_version',
    'macos_sdk_build_version',
    'macos_sdk_settings_sha256',
    'clang_version',
    'compiler_driver',
  ]) {
    runtimeRequiredString(toolchain, key, 'runtime build manifest toolchain');
  }
  runtimeExpect(
    toolchain['compiler_driver'] == 'clang++',
    'runtime build manifest compiler driver is not clang++',
  );
  _validateSha256(
    toolchain['macos_sdk_settings_sha256'],
    'runtime build manifest toolchain.macos_sdk_settings_sha256',
  );
  final Map<String, Object?> packageConfig = runtimeStringMap(
    manifest['package_config'],
    'runtime build manifest package_config',
  );
  runtimeExpect(
    sameStringSet(packageConfig.keys, const <String>{
          'config_version',
          'generator',
          'generator_version',
          'packages',
          'semantic_sha256',
        }) &&
        packageConfig['config_version'] == 2 &&
        packageConfig['generator'] == 'pub' &&
        packageConfig['generator_version'] == dartSdk['version'],
    'runtime build manifest package config generator/version mismatch',
  );
  final Map<String, Object?> semanticPackages = runtimeStringMap(
    packageConfig['packages'],
    'runtime build manifest package_config.packages',
  );
  runtimeExpect(
    sameStringSet(semanticPackages.keys, const <String>{
      'dart_terminal',
      'dart_appkit',
    }),
    'runtime build manifest package set mismatch',
  );
  for (final MapEntry<String, Object?> entry in semanticPackages.entries) {
    final Map<String, Object?> package = runtimeStringMap(
      entry.value,
      'runtime build manifest package ${entry.key}',
    );
    runtimeExpect(
      sameStringSet(package.keys, const <String>{
            'root_role',
            'package_uri',
            'language_version',
          }) &&
          package['root_role'] ==
              (entry.key == 'dart_terminal'
                  ? 'project:.'
                  : 'dart_appkit:packages/dart_appkit') &&
          package['package_uri'] == 'lib/' &&
          package['language_version'] is String,
      'runtime build manifest package ${entry.key} policy mismatch',
    );
  }
  final Map<String, Object?> packageSemanticCopy = runtimeStringMap(
    jsonDecode(jsonEncode(packageConfig)),
    'runtime build manifest package config copy',
  );
  final Object? packageSemanticHash = packageSemanticCopy.remove(
    'semantic_sha256',
  );
  _validateSha256(
    packageSemanticHash,
    'runtime build manifest package_config.semantic_sha256',
  );
  runtimeExpect(
    packageSemanticHash ==
        await runtimeSha256Text(
          runtimeCanonicalJsonEncode(packageSemanticCopy),
        ),
    'runtime build manifest package semantic digest mismatch',
  );
  final Map<String, Object?> architectureNeutralInputs = runtimeStringMap(
    manifest['architecture_neutral_inputs'],
    'runtime build manifest architecture_neutral_inputs',
  );
  runtimeExpect(
    sameStringSet(architectureNeutralInputs.keys, const <String>{
      'platform_dill_sha256',
    }),
    'runtime build manifest architecture-neutral input roles mismatch',
  );
  _validateSha256(
    architectureNeutralInputs['platform_dill_sha256'],
    'runtime build manifest platform dill hash',
  );
  final Map<String, Object?> source = runtimeStringMap(
    manifest['source'],
    'runtime build manifest source',
  );
  runtimeExpect(
    sameStringSet(source.keys, const <String>{
      'repository',
      'input_sha256',
      'inventory_sha256',
    }),
    'runtime build manifest source schema mismatch',
  );
  _validateRepositoryIdentity(source['repository'], 'source.repository');
  final Map<String, Object?> sourceHashes = runtimeStringMap(
    source['input_sha256'],
    'runtime build manifest source.input_sha256',
  );
  _validateHashMap(sourceHashes, 'runtime build manifest source.input_sha256');
  for (final String requiredInput in <String>[
    for (final String relative in runtimeProjectProvenanceFiles)
      'dart_terminal:$relative',
    for (final String relative in runtimeAppKitProvenanceFiles)
      'dart_appkit:$relative',
  ]) {
    runtimeExpect(
      sourceHashes.containsKey(requiredInput),
      'runtime build manifest source inventory misses $requiredInput',
    );
  }
  runtimeExpect(
    sourceHashes.keys.every(runtimeSourceInventoryKeyIsAllowed),
    'runtime build manifest contains an unsupported source inventory key',
  );
  _validateSha256(
    source['inventory_sha256'],
    'runtime build manifest source.inventory_sha256',
  );
  runtimeExpect(
    source['inventory_sha256'] ==
        await runtimeSha256Text(runtimeCanonicalJsonEncode(sourceHashes)),
    'runtime build manifest source inventory digest mismatch',
  );
  final Map<String, Object?> effective = runtimeStringMap(
    manifest['effective_configuration'],
    'runtime build manifest effective_configuration',
  );
  runtimeExpect(
    sameStringSet(effective.keys, <String>{
      'runtime_mode',
      'engine_configuration',
      'deployment_target',
      'bundle_version',
      'native_flags',
      'kernel_flags',
      'worker_topology',
      'worker_protocol_version',
      'native_event_protocol_version',
      if (expectedMode == RuntimeMode.developerJit) 'worker_payload_name',
      if (expectedMode == RuntimeMode.developerJit) 'worker_kernel_flags',
      if (expectedMode == RuntimeMode.releaseAot) 'worker_executable_name',
      if (expectedMode == RuntimeMode.releaseAot) 'worker_executable_flags',
      'snapshot_flags',
      'extra_build_input_sha256',
    }),
    'runtime build manifest effective configuration schema mismatch',
  );
  runtimeExpect(
    effective['runtime_mode'] == expectedMode.name &&
        effective['engine_configuration'] == expectedMode.engineConfiguration &&
        effective['deployment_target'] == expectedDeploymentTarget &&
        effective['bundle_version'] == expectedBundleVersion,
    'runtime build manifest effective configuration mismatch',
  );
  for (final String key in <String>[
    'native_flags',
    'kernel_flags',
    'worker_topology',
    'snapshot_flags',
    'extra_build_input_sha256',
  ]) {
    runtimeRequiredString(
      effective,
      key,
      'runtime build manifest effective_configuration',
    );
  }
  runtimeExpect(
    effective['native_event_protocol_version'] ==
        dartAppKitCurrentEventProtocolVersion,
    'runtime build manifest native event protocol version mismatch',
  );
  if (expectedMode == RuntimeMode.developerJit) {
    runtimeExpect(
      effective['worker_topology'] == 'official-dart-child-process' &&
          effective['worker_protocol_version'] == 1 &&
          effective['worker_payload_name'] ==
              runtimeDeveloperWorkerPayloadName &&
          effective['worker_kernel_flags'] ==
              '--link-platform --no-embed-sources --verbosity=warning',
      'runtime build manifest Developer worker configuration mismatch',
    );
  } else {
    final String? expectedWorkerFlags = isUniversal
        ? null
        : '--target-os=macos '
              '--target-arch=${expectedArchitectures.single == 'arm64' ? 'arm64' : 'x64'} '
              '--verbosity=warning';
    runtimeExpect(
      effective['worker_topology'] == 'official-dart-child-process' &&
          effective['worker_protocol_version'] == 1 &&
          effective['worker_executable_name'] ==
              runtimeReleaseWorkerExecutableName &&
          effective['worker_executable_flags'] is String &&
          (expectedWorkerFlags == null ||
              effective['worker_executable_flags'] == expectedWorkerFlags),
      'runtime build manifest Release worker configuration mismatch',
    );
  }
  final Object? extraBuildInput = effective['extra_build_input_sha256'];
  runtimeExpect(
    extraBuildInput == 'none' ||
        (extraBuildInput is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(extraBuildInput)),
    'runtime build manifest effective extra input hash is invalid',
  );

  final Map<String, Object?> lane = runtimeStringMap(
    manifest['architecture_inputs'],
    'runtime build manifest architecture_inputs',
  );
  final Map<String, Object?> produced = _validateExactHashMap(
    lane['produced_sha256'],
    _laneProducedRoles(expectedMode),
    'runtime build manifest architecture_inputs.produced_sha256',
  );
  final bool producedRolesMatch =
      produced.length == actualProducedHashes.length &&
      actualProducedHashes.entries.every(
        (MapEntry<String, String> entry) => produced.containsKey(entry.key),
      );
  runtimeExpect(
    producedRolesMatch,
    'runtime build manifest produced artifact roles do not match bundle',
  );
  if (expectedMode == RuntimeMode.releaseAot && !isUniversal) {
    runtimeExpect(
      actualProducedHashes.entries.every(
        (MapEntry<String, String> entry) => produced[entry.key] == entry.value,
      ),
      'runtime build manifest produced artifact hashes do not match bundle',
    );
  }
  if (isUniversal) {
    runtimeExpect(
      sameStringSet(lane.keys, const <String>{
        'architectures',
        'thin_lanes',
        'produced_sha256',
      }),
      'Universal manifest architecture input schema mismatch',
    );
    final List<String> architectures = _requiredCanonicalMachOArchitectures(
      lane['architectures'],
      'Universal manifest architecture list',
    );
    runtimeExpect(
      sameStringSet(architectures, supportedRuntimeArchitectures),
      'Universal manifest architecture list must be arm64,x86_64',
    );
    final Map<String, Object?> thinLanes = runtimeStringMap(
      lane['thin_lanes'],
      'runtime build manifest architecture_inputs.thin_lanes',
    );
    runtimeExpect(
      sameStringSet(thinLanes.keys, supportedRuntimeArchitectures),
      'Universal manifest thin lane set must be arm64,x86_64',
    );
    for (final String architecture in supportedRuntimeArchitectures) {
      final Map<String, Object?> thinLane = runtimeStringMap(
        thinLanes[architecture],
        'Universal manifest $architecture lane',
      );
      _validateArchitectureLane(
        thinLane,
        architecture,
        RuntimeMode.releaseAot,
        'Universal manifest $architecture lane',
        architectureNeutralInputs['platform_dill_sha256']! as String,
        dartSdk['version']! as String,
        dartSdk['revision']! as String,
        extraBuildInput != 'none',
      );
    }
  } else {
    _validateArchitectureLane(
      lane,
      expectedManifestArchitecture,
      expectedMode,
      'runtime build manifest architecture_inputs',
      architectureNeutralInputs['platform_dill_sha256']! as String,
      dartSdk['version']! as String,
      dartSdk['revision']! as String,
      extraBuildInput != 'none',
    );
  }
  return manifest;
}

Map<String, Object?> runtimeCommonManifestProvenance(
  Map<String, Object?> manifest,
) => <String, Object?>{
  'runtime_mode': manifest['runtime_mode'],
  'engine_configuration': manifest['engine_configuration'],
  'deployment_target': manifest['deployment_target'],
  'bundle': manifest['bundle'],
  'dart_sdk': manifest['dart_sdk'],
  'dart_engine': manifest['dart_engine'],
  'dart_appkit': manifest['dart_appkit'],
  'toolchain': manifest['toolchain'],
  'package_config': manifest['package_config'],
  'architecture_neutral_inputs': manifest['architecture_neutral_inputs'],
  'source': manifest['source'],
  'effective_configuration': manifest['effective_configuration'],
};

Map<String, String> runtimeExpectedMachORoles(
  RuntimeMode mode,
  String executableName,
) => <String, String>{
  'launcher': 'MacOS/$executableName',
  'dart_engine': 'Frameworks/${mode.engineName}',
  if (mode == RuntimeMode.releaseAot)
    'aot_snapshot': 'Resources/${mode.payloadName}',
  if (mode == RuntimeMode.releaseAot)
    'worker_executable': 'Helpers/$runtimeReleaseWorkerExecutableName',
};

Set<String> runtimeExpectedMachOPaths(
  RuntimeMode mode,
  String executableName,
) => runtimeExpectedMachORoles(mode, executableName).values.toSet();

final class _MachOPolicy {
  const _MachOPolicy({
    required this.installNames,
    required this.dependencies,
    required this.rpaths,
  });

  final Set<String> installNames;
  final Set<String> dependencies;
  final Set<String> rpaths;
}

const Set<String> _launcherSystemDependencies = <String>{
  '/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit',
  '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation',
  '/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation',
  '/System/Library/Frameworks/Metal.framework/Versions/A/Metal',
  '/System/Library/Frameworks/MetalKit.framework/Versions/A/MetalKit',
  '/usr/lib/libobjc.A.dylib',
  '/usr/lib/libc++.1.dylib',
  '/usr/lib/libSystem.B.dylib',
};

const Set<String> _engineSystemDependencies = <String>{
  '/usr/lib/libSystem.B.dylib',
  '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation',
  '/usr/lib/libobjc.A.dylib',
  '/System/Library/Frameworks/Security.framework/Versions/A/Security',
  '/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation',
  '/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices',
};

_MachOPolicy _machOPolicy(RuntimeMode mode, String role) {
  switch (role) {
    case 'launcher':
      return _MachOPolicy(
        installNames: const <String>{},
        dependencies: <String>{
          '@rpath/${mode.engineName}',
          ..._launcherSystemDependencies,
        },
        rpaths: const <String>{'@executable_path/../Frameworks'},
      );
    case 'dart_engine':
      return _MachOPolicy(
        installNames: <String>{'@rpath/${mode.engineName}'},
        dependencies: _engineSystemDependencies,
        rpaths: const <String>{'@loader_path/.', '@loader_path/../../..'},
      );
    case 'aot_snapshot':
      return const _MachOPolicy(
        installNames: <String>{'application.aot'},
        dependencies: <String>{'/usr/lib/libSystem.B.dylib'},
        rpaths: <String>{},
      );
    case 'worker_executable':
      return const _MachOPolicy(
        installNames: <String>{},
        dependencies: _engineSystemDependencies,
        rpaths: <String>{
          '@loader_path/.',
          '@loader_path/../../..',
          '@executable_path/Frameworks',
        },
      );
  }
  throw RuntimeAuditException('unknown Mach-O role: $role');
}

Map<String, Object?> _parseMachOLoadCommands(String output) {
  final List<Map<String, String>> dylibCommands = <Map<String, String>>[];
  final List<String> rpaths = <String>[];
  String? pendingCommand;
  for (final String line in output.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('cmd ')) {
      runtimeExpect(
        pendingCommand == null,
        'Mach-O load command $pendingCommand has no value',
      );
      final String command = trimmed.substring('cmd '.length);
      if (command == 'LC_RPATH' ||
          (command.startsWith('LC_') && command.endsWith('DYLIB'))) {
        pendingCommand = command;
      }
      continue;
    }
    if (pendingCommand == 'LC_RPATH' && trimmed.startsWith('path ')) {
      final int offset = trimmed.lastIndexOf(' (offset ');
      runtimeExpect(offset > 'path '.length, 'invalid LC_RPATH output');
      rpaths.add(trimmed.substring('path '.length, offset));
      pendingCommand = null;
      continue;
    }
    if (pendingCommand != null && trimmed.startsWith('name ')) {
      final int offset = trimmed.lastIndexOf(' (offset ');
      runtimeExpect(offset > 'name '.length, 'invalid dylib command output');
      dylibCommands.add(<String, String>{
        'command': pendingCommand,
        'name': trimmed.substring('name '.length, offset),
      });
      pendingCommand = null;
    }
  }
  runtimeExpect(
    pendingCommand == null,
    'Mach-O load command $pendingCommand has no value',
  );
  rpaths.sort();
  dylibCommands.sort((Map<String, String> left, Map<String, String> right) {
    final int commandComparison = left['command']!.compareTo(right['command']!);
    return commandComparison != 0
        ? commandComparison
        : left['name']!.compareTo(right['name']!);
  });
  return <String, Object?>{'dylib_commands': dylibCommands, 'rpaths': rpaths};
}

void _expectExactList(
  Iterable<String> actual,
  Set<String> expected,
  String description,
) {
  runtimeExpect(
    sameStringSet(actual, expected),
    '$description ${actual.toList()} != ${expected.toList()..sort()}',
  );
}

Future<Map<String, Object?>> _auditMachOSlice(
  String path,
  String architecture,
  RuntimeMode mode,
  String role,
) async {
  final String output = await runtimeCommandStdout('/usr/bin/otool', <String>[
    '-arch',
    architecture,
    '-l',
    path,
  ]);
  final Map<String, Object?> metadata = _parseMachOLoadCommands(output);
  final List<Map<String, Object?>> commands =
      (metadata['dylib_commands']! as List<Object?>)
          .map(
            (Object? value) => runtimeStringMap(value, '$role dylib command'),
          )
          .toList();
  final List<String> installNames = commands
      .where(
        (Map<String, Object?> command) => command['command'] == 'LC_ID_DYLIB',
      )
      .map((Map<String, Object?> command) => command['name']! as String)
      .toList();
  final List<Map<String, Object?>> dependencies = commands
      .where(
        (Map<String, Object?> command) => command['command'] != 'LC_ID_DYLIB',
      )
      .toList();
  runtimeExpect(
    dependencies.every(
      (Map<String, Object?> dependency) =>
          dependency['command'] == 'LC_LOAD_DYLIB',
    ),
    '$role $architecture has an unsupported dylib load command',
  );
  final _MachOPolicy policy = _machOPolicy(mode, role);
  _expectExactList(
    installNames,
    policy.installNames,
    '$role $architecture install names',
  );
  _expectExactList(
    dependencies.map((Map<String, Object?> value) => value['name']! as String),
    policy.dependencies,
    '$role $architecture dependencies',
  );
  _expectExactList(
    (metadata['rpaths']! as List<Object?>).cast<String>(),
    policy.rpaths,
    '$role $architecture LC_RPATH values',
  );
  return metadata;
}

Future<String> _extractEntitlements(String path, String architecture) async {
  final ProcessResult result = await runRuntimeCommand(
    '/usr/bin/codesign',
    <String>[
      '--display',
      '--architecture',
      architecture,
      '--entitlements',
      '-',
      '--xml',
      path,
    ],
  );
  return (result.stdout as String).trim();
}

Future<void> _verifyAdHocSignature(
  String path,
  String description,
  Iterable<String> architectures, {
  bool ignoreResources = false,
  bool deep = false,
}) async {
  await runRuntimeCommand('/usr/bin/codesign', <String>[
    '--verify',
    if (deep) '--deep',
    '--strict',
    if (ignoreResources) '--ignore-resources',
    '--all-architectures',
    path,
  ]);
  for (final String architecture in architectures) {
    final ProcessResult details = await runRuntimeCommand(
      '/usr/bin/codesign',
      <String>[
        '--display',
        '--architecture',
        architecture,
        '--verbose=4',
        path,
      ],
    );
    final Set<String> lines = '${details.stdout}${details.stderr}'
        .split('\n')
        .map((String line) => line.trim())
        .toSet();
    runtimeExpect(
      lines.contains('Signature=adhoc') &&
          lines.contains('TeamIdentifier=not set'),
      '$description $architecture is not strictly ad-hoc signed',
    );
  }
}

Future<Map<String, Object?>> auditRuntimeBundle(
  RuntimeBundleAuditOptions options,
) async {
  runtimeExpect(
    options.expectedArchitectures.isNotEmpty &&
        supportedRuntimeArchitectures.containsAll(
          options.expectedArchitectures,
        ),
    'unsupported architecture set: ${options.expectedArchitectures.join(',')}',
  );
  final Directory bundle = Directory(options.bundlePath).absolute;
  runtimeExpect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
  runtimeExpect(bundle.path.endsWith('.app'), 'bundle must end in .app');
  final Directory contents = Directory('${bundle.path}/Contents');
  final String plistPath = '${contents.path}/Info.plist';
  runtimeExpect(
    await File(plistPath).exists(),
    'missing Info.plist: $plistPath',
  );
  await runRuntimeCommand('/usr/bin/plutil', <String>['-lint', plistPath]);

  final String packageType = await runtimePlistValue(
    plistPath,
    'CFBundlePackageType',
  );
  final String executableName = await runtimePlistValue(
    plistPath,
    'CFBundleExecutable',
  );
  final String bundleIdentifier = await runtimePlistValue(
    plistPath,
    'CFBundleIdentifier',
  );
  final String bundleVersion = await runtimePlistValue(
    plistPath,
    'CFBundleShortVersionString',
  );
  final String deploymentTarget = await runtimePlistValue(
    plistPath,
    'LSMinimumSystemVersion',
  );
  final String declaredMode = await runtimePlistValue(
    plistPath,
    'DTRuntimeMode',
  );
  final String declaredSdkVersion = await runtimePlistValue(
    plistPath,
    'DTDartSDKVersion',
  );
  final String declaredSdkRevision = await runtimePlistValue(
    plistPath,
    'DTDartSDKRevision',
  );
  runtimeExpect(packageType == 'APPL', 'CFBundlePackageType must be APPL');
  runtimeExpect(
    executableName.isNotEmpty && !executableName.contains('/'),
    'invalid CFBundleExecutable: $executableName',
  );
  runtimeExpect(
    bundleIdentifier == options.mode.bundleIdentifier,
    'bundle identifier $bundleIdentifier != ${options.mode.bundleIdentifier}',
  );
  runtimeExpect(
    deploymentTarget == options.deploymentTarget,
    'deployment target $deploymentTarget != ${options.deploymentTarget}',
  );
  runtimeExpect(
    declaredMode == options.mode.name,
    'declared runtime mode $declaredMode != ${options.mode.name}',
  );

  final String executablePath = '${contents.path}/MacOS/$executableName';
  final String enginePath =
      '${contents.path}/Frameworks/${options.mode.engineName}';
  final String payloadPath =
      '${contents.path}/Resources/${options.mode.payloadName}';
  final String? workerPayloadPath = options.mode == RuntimeMode.developerJit
      ? '${contents.path}/Resources/$runtimeDeveloperWorkerPayloadName'
      : null;
  final String? workerExecutablePath = options.mode == RuntimeMode.releaseAot
      ? '${contents.path}/Helpers/$runtimeReleaseWorkerExecutableName'
      : null;
  final List<String> files = await runtimeRelativeFiles(contents);
  for (final String requiredPath in <String>[
    'MacOS/$executableName',
    'Frameworks/${options.mode.engineName}',
    'Resources/${options.mode.payloadName}',
    if (options.mode == RuntimeMode.developerJit)
      'Resources/$runtimeDeveloperWorkerPayloadName',
    if (options.mode == RuntimeMode.releaseAot)
      'Helpers/$runtimeReleaseWorkerExecutableName',
    runtimeBuildManifestRelativePath,
  ]) {
    runtimeExpect(
      files.contains(requiredPath),
      'missing runtime file: $requiredPath',
    );
  }
  runtimeExpect(
    !files.contains('Frameworks/${options.mode.incompatibleEngineName}'),
    'bundle contains incompatible Engine: ${options.mode.incompatibleEngineName}',
  );
  runtimeExpect(
    !files.contains('Resources/${options.mode.incompatiblePayloadName}'),
    'bundle contains incompatible payload: ${options.mode.incompatiblePayloadName}',
  );
  final List<String> engineFiles = files
      .where(
        (String path) =>
            path.startsWith('Frameworks/libdart_engine_') &&
            path.endsWith('.dylib'),
      )
      .toList();
  runtimeExpect(
    engineFiles.length == 1 &&
        engineFiles.single == 'Frameworks/${options.mode.engineName}',
    'bundle must contain exactly one mode-matching Dart Engine: '
    '${engineFiles.join(',')}',
  );
  if (options.mode == RuntimeMode.developerJit) {
    final List<String> aotPayloads = files
        .where((String path) => path.toLowerCase().endsWith('.aot'))
        .toList();
    runtimeExpect(
      aotPayloads.isEmpty,
      'developer JIT bundle contains AOT payloads: ${aotPayloads.join(',')}',
    );
    final Set<String> developerKernels = files
        .where((String path) => path.toLowerCase().endsWith('.dill'))
        .toSet();
    runtimeExpect(
      sameStringSet(developerKernels, <String>{
        'Resources/${options.mode.payloadName}',
        'Resources/$runtimeDeveloperWorkerPayloadName',
      }),
      'developer JIT bundle Kernel roles differ: '
      '${developerKernels.toList()..sort()}',
    );
  } else {
    final List<String> forbiddenReleaseFiles = files.where((String path) {
      final String lower = path.toLowerCase();
      return lower.endsWith('.dill') ||
          lower.contains('vmservice') ||
          lower.contains('vm_service') ||
          lower.contains('vm-service') ||
          lower.contains('/dds');
    }).toList();
    runtimeExpect(
      forbiddenReleaseFiles.isEmpty,
      'release AOT bundle contains JIT/VM-service assets: '
      '${forbiddenReleaseFiles.join(',')}',
    );
  }

  final FileStat executableStat = await File(executablePath).stat();
  runtimeExpect(
    executableStat.mode & 0x49 != 0,
    'CFBundleExecutable is not executable: $executablePath',
  );
  runtimeExpect(
    (await File(payloadPath).stat()).size > 0,
    'runtime payload is empty: $payloadPath',
  );
  if (workerPayloadPath != null) {
    runtimeExpect(
      (await File(workerPayloadPath).stat()).size > 0,
      'runtime worker payload is empty: $workerPayloadPath',
    );
  }
  if (workerExecutablePath != null) {
    final FileStat workerExecutableStat = await File(workerExecutablePath)
        .stat();
    runtimeExpect(
      workerExecutableStat.size > 0 && workerExecutableStat.mode & 0x49 != 0,
      'runtime worker executable is empty or not executable: '
      '$workerExecutablePath',
    );
  }
  final Map<String, String> rolePaths = <String, String>{
    'launcher': executablePath,
    'dart_engine': enginePath,
    if (options.mode == RuntimeMode.releaseAot) 'aot_snapshot': payloadPath,
    if (workerExecutablePath != null) 'worker_executable': workerExecutablePath,
  };
  final Set<String> actualMachOPaths = <String>{};
  for (final String path in files) {
    if (!path.startsWith('_CodeSignature/') &&
        await runtimeIsMachO('${contents.path}/$path')) {
      actualMachOPaths.add(path);
    }
  }
  final Set<String> expectedMachOPaths = runtimeExpectedMachOPaths(
    options.mode,
    executableName,
  );
  runtimeExpect(
    sameStringSet(actualMachOPaths, expectedMachOPaths),
    'Mach-O layout ${actualMachOPaths.toList()..sort()} != '
    '${expectedMachOPaths.toList()..sort()}',
  );

  final SplayTreeMap<String, String> producedHashes =
      SplayTreeMap<String, String>();
  final List<Map<String, Object?>> machOFiles = <Map<String, Object?>>[];
  final SplayTreeMap<String, Object?> entitlements =
      SplayTreeMap<String, Object?>();
  for (final MapEntry<String, String> artifact in rolePaths.entries) {
    final List<String> architectures = await runtimeArchitectures(
      artifact.value,
    );
    runtimeExpect(
      sameStringSet(architectures, options.expectedArchitectures),
      '${artifact.key} architectures ${architectures.join(',')} != '
      '${options.expectedArchitectures.join(',')}',
    );
    final SplayTreeMap<String, Object?> slices =
        SplayTreeMap<String, Object?>();
    final SplayTreeMap<String, Object?> roleEntitlements =
        SplayTreeMap<String, Object?>();
    for (final String architecture in architectures) {
      slices[architecture] = await _auditMachOSlice(
        artifact.value,
        architecture,
        options.mode,
        artifact.key,
      );
      final String extracted = await _extractEntitlements(
        artifact.value,
        architecture,
      );
      runtimeExpect(
        extracted.isEmpty,
        '${artifact.key} $architecture entitlements are not allowed',
      );
      roleEntitlements[architecture] = 'none';
    }
    await _verifyAdHocSignature(
      artifact.value,
      artifact.key,
      architectures,
      ignoreResources: artifact.key == 'launcher',
    );
    entitlements[artifact.key] = roleEntitlements;
    final String fileHash = await runtimeSha256File(artifact.value);
    producedHashes[options.mode == RuntimeMode.releaseAot &&
                artifact.key == 'launcher'
            ? 'launcher_content'
            : artifact.key] =
        options.mode == RuntimeMode.releaseAot && artifact.key == 'launcher'
        ? await runtimeMachOContentSha256(artifact.value)
        : fileHash;
    machOFiles.add(<String, Object?>{
      'role': artifact.key,
      'path': artifact.value.substring(contents.path.length + 1),
      'architectures': architectures,
      'sha256': fileHash,
      'load_commands': slices,
      'entitlements': roleEntitlements,
      'signature': 'adhoc-strict-individual',
    });
  }
  if (options.mode == RuntimeMode.developerJit) {
    producedHashes['kernel_payload'] = await runtimeSha256File(payloadPath);
    producedHashes['worker_kernel_payload'] = await runtimeSha256File(
      workerPayloadPath!,
    );
  }

  final Map<String, Object?> manifest = await readRuntimeBuildManifest(
    '${contents.path}/$runtimeBuildManifestRelativePath',
    expectedMode: options.mode,
    expectedArchitectures: options.expectedArchitectures,
    expectedDeploymentTarget: options.deploymentTarget,
    expectedBundleVersion: bundleVersion,
    expectedExecutable: executableName,
    actualProducedHashes: producedHashes,
  );
  final Map<String, Object?> manifestSdk = runtimeStringMap(
    manifest['dart_sdk'],
    'runtime build manifest dart_sdk',
  );
  runtimeExpect(
    manifestSdk['version'] == declaredSdkVersion,
    'Info.plist Dart SDK version differs from build manifest',
  );
  runtimeExpect(
    manifestSdk['revision'] == declaredSdkRevision,
    'Info.plist Dart SDK revision differs from build manifest',
  );

  final SplayTreeMap<String, Object?> outerEntitlements =
      SplayTreeMap<String, Object?>();
  for (final String architecture in options.expectedArchitectures) {
    final String extracted = await _extractEntitlements(
      bundle.path,
      architecture,
    );
    runtimeExpect(
      extracted.isEmpty,
      'outer app $architecture entitlements are not allowed',
    );
    outerEntitlements[architecture] = 'none';
  }
  entitlements['outer_app'] = outerEntitlements;
  await _verifyAdHocSignature(
    bundle.path,
    'outer app',
    options.expectedArchitectures,
    deep: true,
  );

  final SplayTreeMap<String, Object?> seal = await runtimeBundleSeal(
    bundle.path,
  );
  final String artifactDigest = await runtimeSha256Text(
    runtimeCanonicalJsonEncode(seal),
  );
  return <String, Object?>{
    'path': bundle.path,
    'runtime_mode': options.mode.name,
    'bundle_identifier': bundleIdentifier,
    'bundle_version': bundleVersion,
    'executable': executableName,
    'engine': 'Frameworks/${options.mode.engineName}',
    'payload': 'Resources/${options.mode.payloadName}',
    if (options.mode == RuntimeMode.developerJit)
      'worker_payload': 'Resources/$runtimeDeveloperWorkerPayloadName',
    if (options.mode == RuntimeMode.releaseAot)
      'worker_executable': 'Helpers/$runtimeReleaseWorkerExecutableName',
    'deployment_target': deploymentTarget,
    'architectures': options.expectedArchitectures.toList()..sort(),
    'mach_o_policy': runtimeMachOPolicy,
    'mach_o_files': machOFiles,
    'entitlements': entitlements,
    'build_manifest': manifest,
    'manifest_sha256': await runtimeSha256File(
      '${contents.path}/$runtimeBuildManifestRelativePath',
    ),
    'artifact_digest': artifactDigest,
    'artifact_seal': seal,
    'signing': <String, Object?>{
      'nested_mach_o': 'adhoc-strict-individual',
      'outer_app': 'adhoc-deep-strict',
    },
    'passed': true,
  };
}

Map<String, Object?> runtimeAuditReport(Map<String, Object?> result) =>
    <String, Object?>{
      'format': runtimeBundleAuditFormat,
      'version': runtimeBundleAuditVersion,
      'status': 'pass',
      'result': result,
    };

Map<String, Object?> _comparableAuditResult(Map<String, Object?> result) {
  final Object? decoded = jsonDecode(jsonEncode(result));
  final Map<String, Object?> comparable = runtimeStringMap(
    decoded,
    'audit result copy',
  );
  comparable.remove('path');
  return comparable;
}

Future<Map<String, Object?>> validateRuntimeAuditReceipt(
  String reportPath,
  RuntimeBundleAuditOptions options,
) async {
  final Map<String, Object?> report = await _readJsonObject(
    reportPath,
    'runtime audit receipt',
  );
  runtimeExpect(
    report['format'] == runtimeBundleAuditFormat &&
        report['version'] == runtimeBundleAuditVersion &&
        report['status'] == 'pass',
    'runtime audit receipt format/version/status mismatch',
  );
  final Map<String, Object?> recorded = runtimeStringMap(
    report['result'],
    'runtime audit receipt result',
  );
  runtimeExpect(
    recorded['passed'] == true,
    'runtime audit receipt is not pass',
  );
  final Map<String, Object?> recordedManifest = runtimeStringMap(
    recorded['build_manifest'],
    'runtime audit receipt build manifest',
  );
  final Object? generation = recordedManifest['publication_generation_sha256'];
  if (generation != null) {
    _validateSha256(generation, 'publication generation');
    runtimeExpect(
      report['publication_generation_sha256'] == generation,
      'runtime audit receipt publication generation mismatch',
    );
  }
  final Map<String, Object?> actual = await auditRuntimeBundle(options);
  runtimeExpect(
    runtimeCanonicalJsonEncode(_comparableAuditResult(recorded)) ==
        runtimeCanonicalJsonEncode(_comparableAuditResult(actual)),
    'runtime audit receipt does not match the immutable bundle',
  );
  return actual;
}

Future<Map<String, String>> validateRuntimeToolSourceIdentity({
  required Map<String, String> receiptPaths,
  required Map<String, String> toolPaths,
}) async {
  runtimeExpect(
    receiptPaths.isNotEmpty,
    'no receipts supplied for tool identity',
  );
  runtimeExpect(toolPaths.isNotEmpty, 'no tools supplied for source identity');
  Map<String, String>? expectedHashes;
  for (final MapEntry<String, String> receipt in receiptPaths.entries) {
    final Map<String, Object?> report = await _readJsonObject(
      receipt.value,
      '${receipt.key} runtime audit receipt',
    );
    runtimeExpect(
      report['format'] == runtimeBundleAuditFormat &&
          report['version'] == runtimeBundleAuditVersion &&
          report['status'] == 'pass',
      '${receipt.key} runtime audit receipt is not a supported pass receipt',
    );
    final Map<String, Object?> result = runtimeStringMap(
      report['result'],
      '${receipt.key} audit result',
    );
    final Map<String, Object?> manifest = runtimeStringMap(
      result['build_manifest'],
      '${receipt.key} build manifest',
    );
    final Map<String, Object?> source = runtimeStringMap(
      manifest['source'],
      '${receipt.key} source provenance',
    );
    final Map<String, Object?> inventory = runtimeStringMap(
      source['input_sha256'],
      '${receipt.key} source inventory',
    );
    final Map<String, String> receiptHashes = <String, String>{};
    for (final String label in toolPaths.keys) {
      final Object? value = inventory[label];
      _validateSha256(value, '${receipt.key} source inventory $label');
      receiptHashes[label] = value! as String;
    }
    if (expectedHashes == null) {
      expectedHashes = receiptHashes;
    } else {
      runtimeExpect(
        runtimeCanonicalJsonEncode(expectedHashes) ==
            runtimeCanonicalJsonEncode(receiptHashes),
        '${receipt.key} tool source identities differ from other receipts',
      );
    }
  }
  final Map<String, String> actualHashes = <String, String>{};
  for (final MapEntry<String, String> tool in toolPaths.entries) {
    final RuntimePathSnapshot snapshot = await runtimePathSnapshot(tool.value);
    runtimeExpect(
      snapshot.exists && snapshot.targetType == FileSystemEntityType.file,
      'missing regular runtime tool: ${tool.value}',
    );
    final String actual = await runtimeSha256File(snapshot.canonicalPath);
    runtimeExpect(
      actual == expectedHashes![tool.key],
      'runtime tool source identity mismatch: ${tool.key}',
    );
    actualHashes[tool.key] = actual;
  }
  return actualHashes;
}
