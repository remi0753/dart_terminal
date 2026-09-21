import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_differential_sha256.dart';

const String terminalNoteR0ArchitectureEvidenceFormat =
    'dart-terminal-note-r0-architecture-evidence';
const String terminalNoteR0ArchitectureEvidencePath =
    'benchmark/evidence/terminal-note-r0-architecture-macos.json';

const int _maximumManifestBytes = 64 * 1024;
const int _maximumResourceBytes = 32 * 1024 * 1024;
const int _maximumAggregateResourceBytes = 64 * 1024 * 1024;

const Map<String, Object?> _noteCapability = <String, Object?>{
  'id': 'dart_terminal_notes_macos',
  'package': 'dart_terminal_notes_macos',
  'library': 'libdart_terminal_notes_macos.dylib',
  'abiVersion': 1,
  'abiVersionSymbol': 'dtn_abi_version',
  'initializerSymbol': 'dtn_initialize',
};

const Set<String> _thinManifestKeys = <String>{
  'schemaVersion',
  'runtimeMode',
  'architecture',
  'bundleIdentifier',
  'executable',
  'payload',
  'engine',
  'dartSdkVersion',
  'dartSdkRevision',
  'runner',
  'services',
  'icon',
  'scriptingDefinition',
  'appIntents',
  'dartHelpers',
  'resources',
  'nativeAssets',
  'nativeCapabilities',
};

const Set<String> _universalManifestKeys = <String>{
  'schemaVersion',
  'runtimeMode',
  'architectures',
  'bundleIdentifier',
  'executable',
  'payload',
  'engine',
  'dartSdkVersion',
  'dartSdkRevision',
  'runner',
  'services',
  'icon',
  'scriptingDefinition',
  'appIntents',
  'dartHelpers',
  'resources',
  'nativeAssets',
  'nativeCapabilities',
  'codePaths',
  'resourceFiles',
  'thinManifests',
  'applicationContract',
};

const List<String> _applicationContractKeys = <String>[
  'runtimeMode',
  'bundleIdentifier',
  'executable',
  'payload',
  'engine',
  'dartSdkVersion',
  'dartSdkRevision',
  'runner',
  'services',
  'icon',
  'scriptingDefinition',
  'appIntents',
  'dartHelpers',
  'resources',
  'nativeAssets',
  'nativeCapabilities',
];

const List<String> _contentSentinels = <String>[
  'R0-PRIVATE-BODY-MUST-NOT-LEAK',
  'PRIVATE-CODEC-BODY-SENTINEL',
  'PRIVATE-WORKER-BODY-SENTINEL',
  'PRIVATE-WORKER-LOG-BODY-SENTINEL',
  'PRIVATE_BODY_SENTINEL_9347',
  'PRIVATE-CRASH-SENTINEL',
  'deadbeefdeadbeefdeadbeefdeadbeef',
  '777777777777',
];

const List<String> _absolutePathSentinels = <String>[
  '/Users/',
  '/private/var/',
  '/var/folders/',
  'file:///Users/',
];

final class TerminalNoteR0BundleObservation {
  TerminalNoteR0BundleObservation({
    required this.manifestSource,
    required Map<String, List<int>> neutralResources,
    required Set<String> frameworkArchitectures,
    required Set<String> helperArchitectures,
  }) : neutralResources = Map<String, List<int>>.unmodifiable(
         neutralResources.map(
           (String key, List<int> value) =>
               MapEntry<String, List<int>>(key, List<int>.unmodifiable(value)),
         ),
       ),
       frameworkArchitectures = Set<String>.unmodifiable(
         frameworkArchitectures,
       ),
       helperArchitectures = Set<String>.unmodifiable(helperArchitectures);

  final String manifestSource;
  final Map<String, List<int>> neutralResources;
  final Set<String> frameworkArchitectures;
  final Set<String> helperArchitectures;
}

final class TerminalNoteR0ArchitectureResult {
  const TerminalNoteR0ArchitectureResult(this.document);

  final Map<String, Object?> document;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';

  String machineLine() {
    final Map<String, Object?> resources =
        document['resources']! as Map<String, Object?>;
    final Map<String, Object?> architecture =
        document['architecture']! as Map<String, Object?>;
    return 'TERMINAL_NOTE_R0_ARCHITECTURE_PASS version=1 bundles=4 '
        'resources=${resources['files']} resource_bytes=${resources['bytes']} '
        'note_images=${architecture['note_images']} '
        'architectures=arm64,x86_64,universal capability_abi=1 '
        'sentinels=0 absolute_paths=0 content_free=true';
  }
}

TerminalNoteR0ArchitectureResult buildTerminalNoteR0ArchitectureEvidence({
  required TerminalNoteR0BundleObservation developerJitArm64,
  required TerminalNoteR0BundleObservation releaseArm64,
  required TerminalNoteR0BundleObservation releaseX86_64,
  required TerminalNoteR0BundleObservation releaseUniversal,
  required List<int> auditorSource,
}) {
  final Map<String, Object?> developer = _decodeThinManifest(
    developerJitArm64.manifestSource,
    mode: 'developer-jit',
    architecture: 'arm64',
  );
  final Map<String, Object?> arm64 = _decodeThinManifest(
    releaseArm64.manifestSource,
    mode: 'release-aot',
    architecture: 'arm64',
  );
  final Map<String, Object?> x86_64 = _decodeThinManifest(
    releaseX86_64.manifestSource,
    mode: 'release-aot',
    architecture: 'x86_64',
  );
  final Map<String, Object?> universal = _decodeUniversalManifest(
    releaseUniversal.manifestSource,
  );

  final Map<String, Object?> normalizedArm64 = _normalizeReleaseContract(
    arm64,
    'arm64',
  );
  final Map<String, Object?> normalizedX86_64 = _normalizeReleaseContract(
    x86_64,
    'x86_64',
  );
  final Map<String, Object?> universalContract = _object(
    universal['applicationContract'],
    'Universal application contract',
  );
  if (_canonical(normalizedArm64) != _canonical(normalizedX86_64) ||
      _canonical(normalizedArm64) != _canonical(universalContract)) {
    throw const FormatException('Release application contracts differ');
  }
  for (final String key in _applicationContractKeys) {
    if (_canonical(universal[key]) != _canonical(universalContract[key])) {
      throw const FormatException('Universal top-level contract differs');
    }
  }

  for (final Map<String, Object?> manifest in <Map<String, Object?>>[
    developer,
    arm64,
    x86_64,
    universalContract,
  ]) {
    _validateNoteCapability(manifest);
  }
  final Object? developerResources = developer['resources'];
  if (_canonical(developerResources) != _canonical(arm64['resources']) ||
      _canonical(developerResources) != _canonical(x86_64['resources']) ||
      _canonical(developerResources) !=
          _canonical(universalContract['resources'])) {
    throw const FormatException('declared resource lists differ');
  }

  final Set<String> releaseCodePaths = _codePathsFromThin(arm64);
  if (!_sameStrings(releaseCodePaths, _codePathsFromThin(x86_64))) {
    throw const FormatException('Release code inventories differ');
  }
  final List<String> universalCodePaths = _strictStringList(
    universal['codePaths'],
    'Universal code paths',
  );
  if (!_sortedUniqueSafe(universalCodePaths) ||
      !_sameStrings(universalCodePaths, releaseCodePaths)) {
    throw const FormatException('Universal code inventory differs');
  }
  const Set<String> requiredNoteCodePaths = <String>{
    'Contents/Frameworks/libdart_terminal_notes_macos.dylib',
    'Contents/lib/libdart_terminal_notes_macos.dylib',
  };
  if (!releaseCodePaths.containsAll(requiredNoteCodePaths)) {
    throw const FormatException('Notes code images are not both declared');
  }

  final String armManifestHash = _shaText(releaseArm64.manifestSource);
  final String x86ManifestHash = _shaText(releaseX86_64.manifestSource);
  final Map<String, Object?> thinManifests = _object(
    universal['thinManifests'],
    'Universal thin manifests',
  );
  _exactKeys(thinManifests, const <String>{
    'arm64',
    'x86_64',
  }, 'Universal thin manifests');
  if (thinManifests['arm64'] != armManifestHash ||
      thinManifests['x86_64'] != x86ManifestHash) {
    throw const FormatException('Universal thin manifest ownership differs');
  }

  final List<TerminalNoteR0BundleObservation> observations =
      <TerminalNoteR0BundleObservation>[
        developerJitArm64,
        releaseArm64,
        releaseX86_64,
        releaseUniversal,
      ];
  final Map<String, List<int>> canonicalResources =
      developerJitArm64.neutralResources;
  for (final TerminalNoteR0BundleObservation observation in observations) {
    _validateResourceInventory(observation.neutralResources);
    if (!_sameResourceMaps(canonicalResources, observation.neutralResources)) {
      throw const FormatException('neutral bundle resources differ');
    }
  }
  _validateUniversalResourceEvidence(
    universal['resourceFiles'],
    canonicalResources,
  );

  _expectArchitectures(developerJitArm64, const <String>{'arm64'});
  _expectArchitectures(releaseArm64, const <String>{'arm64'});
  _expectArchitectures(releaseX86_64, const <String>{'x86_64'});
  _expectArchitectures(releaseUniversal, const <String>{'arm64', 'x86_64'});

  final List<List<int>> privacyInputs = <List<int>>[
    utf8.encode(developerJitArm64.manifestSource),
    utf8.encode(releaseArm64.manifestSource),
    utf8.encode(releaseX86_64.manifestSource),
    utf8.encode(releaseUniversal.manifestSource),
    ...canonicalResources.values,
  ];
  final int contentMatches = _patternMatches(privacyInputs, _contentSentinels);
  final int absolutePathMatches = _patternMatches(
    privacyInputs,
    _absolutePathSentinels,
  );
  if (contentMatches != 0 || absolutePathMatches != 0) {
    throw const FormatException('bundle evidence privacy audit failed');
  }

  final ({int bytes, String sha256}) resourceSummary = _resourceSummary(
    canonicalResources,
  );
  final Map<String, Object?> document = <String, Object?>{
    'format': terminalNoteR0ArchitectureEvidenceFormat,
    'version': 1,
    'status': 'pass',
    'inputs': <String, Object?>{
      'developer_jit_arm64_manifest_sha256': _shaText(
        developerJitArm64.manifestSource,
      ),
      'release_arm64_manifest_sha256': armManifestHash,
      'release_x86_64_manifest_sha256': x86ManifestHash,
      'release_universal_manifest_sha256': _shaText(
        releaseUniversal.manifestSource,
      ),
    },
    'source_integrity': <String, Object?>{
      'architecture_auditor_sha256': terminalDifferentialSha256(auditorSource),
    },
    'note_capability': _noteCapability,
    'resources': <String, Object?>{
      'files': canonicalResources.length,
      'bytes': resourceSummary.bytes,
      'aggregate_sha256': resourceSummary.sha256,
      'inventories_equal': true,
      'bytes_equal': true,
      'universal_evidence_equal': true,
      'paths_retained': false,
      'raw_content_retained': false,
    },
    'architecture': <String, Object?>{
      'developer_jit_arm64': const <String>['arm64'],
      'release_arm64': const <String>['arm64'],
      'release_x86_64': const <String>['x86_64'],
      'release_universal': const <String>['arm64', 'x86_64'],
      'note_images_per_bundle': 2,
      'note_images': 8,
      'universal_code_images': universalCodePaths.length,
      'thin_manifest_ownership': true,
    },
    'privacy': <String, Object?>{
      'content_sentinel_matches': contentMatches,
      'absolute_path_matches': absolutePathMatches,
      'manifest_and_neutral_resources_only': true,
      'content_free': true,
    },
    'gates': const <String, Object?>{
      'strict_manifests': true,
      'release_contract_equality': true,
      'note_capability_equality': true,
      'note_image_architectures': true,
      'neutral_resource_equality': true,
      'universal_resource_evidence': true,
      'thin_manifest_ownership': true,
      'privacy': true,
      'passed': true,
    },
  };
  _validateEvidenceDocument(document, auditorSource: auditorSource);
  return TerminalNoteR0ArchitectureResult(document);
}

TerminalNoteR0ArchitectureResult validateTerminalNoteR0ArchitectureEvidence(
  String source, {
  required List<int> auditorSource,
}) {
  final List<int> bytes = utf8.encode(source);
  if (bytes.isEmpty ||
      bytes.length > _maximumManifestBytes ||
      source.contains('\r') ||
      !source.endsWith('\n') ||
      source.endsWith('\n\n')) {
    throw const FormatException('architecture evidence framing is invalid');
  }
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('architecture evidence is not an object');
  }
  _validateEvidenceDocument(decoded, auditorSource: auditorSource);
  final String canonical =
      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  if (canonical != source) {
    throw const FormatException('architecture evidence is not canonical');
  }
  return TerminalNoteR0ArchitectureResult(decoded);
}

Map<String, Object?> _decodeThinManifest(
  String source, {
  required String mode,
  required String architecture,
}) {
  final Map<String, Object?> manifest = _decodeManifest(source);
  _exactKeys(manifest, _thinManifestKeys, 'thin manifest');
  if (manifest['schemaVersion'] != 1 ||
      manifest['runtimeMode'] != mode ||
      manifest['architecture'] != architecture ||
      manifest['bundleIdentifier'] != 'dev.dart-terminal' ||
      manifest['executable'] != 'dart_terminal') {
    throw const FormatException('thin manifest authority differs');
  }
  _validateSafeLeaf(manifest['payload'], 'payload');
  _validateSafeLeaf(manifest['engine'], 'engine');
  _strictStringList(manifest['resources'], 'declared resources');
  _validateNoteCapability(manifest);
  _codePathsFromThin(manifest);
  return manifest;
}

Map<String, Object?> _decodeUniversalManifest(String source) {
  final Map<String, Object?> manifest = _decodeManifest(source);
  _exactKeys(manifest, _universalManifestKeys, 'Universal manifest');
  final List<String> architectures = _strictStringList(
    manifest['architectures'],
    'Universal architectures',
  );
  if (manifest['schemaVersion'] != 2 ||
      manifest['runtimeMode'] != 'release-aot' ||
      architectures.length != 2 ||
      architectures[0] != 'arm64' ||
      architectures[1] != 'x86_64' ||
      manifest['bundleIdentifier'] != 'dev.dart-terminal' ||
      manifest['executable'] != 'dart_terminal') {
    throw const FormatException('Universal manifest authority differs');
  }
  return manifest;
}

Map<String, Object?> _decodeManifest(String source) {
  final List<int> bytes = utf8.encode(source);
  if (bytes.isEmpty ||
      bytes.length > _maximumManifestBytes ||
      source.contains('\r') ||
      !source.endsWith('\n') ||
      source.endsWith('\n\n')) {
    throw const FormatException('runtime manifest framing is invalid');
  }
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('runtime manifest is not an object');
  }
  return decoded;
}

void _validateNoteCapability(Map<String, Object?> manifest) {
  final Object? capabilitiesValue = manifest['nativeCapabilities'];
  if (capabilitiesValue is! List<Object?> || capabilitiesValue.length != 3) {
    throw const FormatException('native capability inventory differs');
  }
  final List<Map<String, Object?>> capabilities = capabilitiesValue
      .map<Map<String, Object?>>(
        (Object? value) => _object(value, 'native capability'),
      )
      .toList(growable: false);
  final List<Map<String, Object?>> notes = capabilities
      .where(
        (Map<String, Object?> value) =>
            value['id'] == 'dart_terminal_notes_macos',
      )
      .toList(growable: false);
  if (notes.length != 1 ||
      _canonical(notes.single) != _canonical(_noteCapability)) {
    throw const FormatException('Notes capability declaration differs');
  }
  final Object? helpersValue = manifest['dartHelpers'];
  if (helpersValue is! List<Object?> || helpersValue.length != 1) {
    throw const FormatException('Dart helper inventory differs');
  }
  final Map<String, Object?> helper = _object(
    helpersValue.single,
    'Dart helper',
  );
  final List<String> helperAssets = _strictStringList(
    helper['nativeAssets'],
    'Dart helper native assets',
  );
  if (helperAssets
          .where(
            (String value) => value == 'libdart_terminal_notes_macos.dylib',
          )
          .length !=
      1) {
    throw const FormatException('Notes helper image declaration differs');
  }
}

Set<String> _codePathsFromThin(Map<String, Object?> manifest) {
  final Set<String> result = <String>{
    'Contents/MacOS/${_safeLeaf(manifest['executable'], 'executable')}',
    'Contents/Resources/${_safeLeaf(manifest['payload'], 'payload')}',
    'Contents/Frameworks/${_safeLeaf(manifest['engine'], 'engine')}',
  };
  final List<Object?> helpers = _list(manifest['dartHelpers'], 'Dart helpers');
  for (final Object? value in helpers) {
    final Map<String, Object?> helper = _object(value, 'Dart helper');
    result.add('Contents/Helpers/${_safeLeaf(helper['name'], 'helper name')}');
    final Object? payload = helper['payload'];
    if (payload != null) {
      final String relative = _safeRelative(payload, 'helper payload');
      result.add('Contents/Resources/$relative');
    }
    for (final String asset in _strictStringList(
      helper['nativeAssets'],
      'helper native assets',
    )) {
      result.add('Contents/lib/${_safeLeaf(asset, 'helper native asset')}');
    }
  }
  void addLibraries(String key) {
    for (final Object? value in _list(manifest[key], key)) {
      final Map<String, Object?> entry = _object(value, key);
      result.add(
        'Contents/Frameworks/${_safeLeaf(entry['library'], '$key library')}',
      );
    }
  }

  addLibraries('nativeAssets');
  addLibraries('nativeCapabilities');
  final Map<String, Object?> appIntents = _object(
    manifest['appIntents'],
    'App Intents',
  );
  result.add(
    'Contents/Frameworks/${_safeLeaf(appIntents['library'], 'App Intents library')}',
  );
  return result;
}

Map<String, Object?> _normalizeReleaseContract(
  Map<String, Object?> manifest,
  String architecture,
) {
  final Map<String, Object?> copy = _deepCopy(manifest);
  copy
    ..remove('schemaVersion')
    ..remove('architecture');
  final Map<String, Object?> appIntents = _object(
    copy['appIntents'],
    'App Intents',
  );
  final Object? targetValue = appIntents['targetTriple'];
  if (targetValue is! String) {
    throw const FormatException('App Intents target triple is invalid');
  }
  final String prefix = '$architecture-apple-macos';
  if (!targetValue.startsWith(prefix) || targetValue.length == prefix.length) {
    throw const FormatException('App Intents target architecture differs');
  }
  appIntents['targetTriple'] =
      r'$ARCH-apple-macos' + targetValue.substring(prefix.length);
  if (appIntents.remove('libraryBytes') is! int) {
    throw const FormatException('App Intents library bytes are invalid');
  }
  return _canonicalize(copy) as Map<String, Object?>;
}

void _validateUniversalResourceEvidence(
  Object? value,
  Map<String, List<int>> resources,
) {
  final List<Object?> entries = _list(value, 'Universal resource evidence');
  if (entries.length != resources.length) {
    throw const FormatException('Universal resource evidence count differs');
  }
  String previous = '';
  final Set<String> seen = <String>{};
  for (final Object? value in entries) {
    final Map<String, Object?> entry = _object(
      value,
      'Universal resource entry',
    );
    _exactKeys(entry, const <String>{
      'path',
      'bytes',
      'sha256',
    }, 'Universal resource entry');
    final Object? pathValue = entry['path'];
    final Object? bytesValue = entry['bytes'];
    final Object? shaValue = entry['sha256'];
    if (pathValue is! String ||
        !_safeRelativePath(pathValue) ||
        pathValue.compareTo(previous) <= 0 ||
        !seen.add(pathValue) ||
        bytesValue is! int ||
        bytesValue < 0 ||
        !_isSha256(shaValue)) {
      throw const FormatException('Universal resource entry is invalid');
    }
    previous = pathValue;
    final List<int>? actual = resources[pathValue];
    if (actual == null ||
        actual.length != bytesValue ||
        terminalDifferentialSha256(actual) != shaValue) {
      throw const FormatException('Universal resource evidence differs');
    }
  }
}

void _validateResourceInventory(Map<String, List<int>> resources) {
  if (resources.isEmpty) {
    throw const FormatException('neutral resource inventory is empty');
  }
  var total = 0;
  for (final MapEntry<String, List<int>> entry in resources.entries) {
    if (!_safeRelativePath(entry.key) ||
        entry.key == 'Contents/Resources/runtime-build-manifest.json' ||
        entry.value.isEmpty ||
        entry.value.length > _maximumResourceBytes) {
      throw const FormatException('neutral resource entry is invalid');
    }
    total += entry.value.length;
    if (total > _maximumAggregateResourceBytes) {
      throw const FormatException('neutral resources exceed aggregate bound');
    }
  }
}

void _expectArchitectures(
  TerminalNoteR0BundleObservation observation,
  Set<String> expected,
) {
  if (!_sameStrings(observation.frameworkArchitectures, expected) ||
      !_sameStrings(observation.helperArchitectures, expected)) {
    throw const FormatException('Notes image architecture differs');
  }
}

({int bytes, String sha256}) _resourceSummary(
  Map<String, List<int>> resources,
) {
  final BytesBuilder aggregate = BytesBuilder(copy: false);
  var bytes = 0;
  final List<String> paths = resources.keys.toList()..sort();
  for (final String path in paths) {
    final List<int> pathBytes = utf8.encode(path);
    final List<int> value = resources[path]!;
    bytes += value.length;
    aggregate
      ..add(utf8.encode('${pathBytes.length}:'))
      ..add(pathBytes)
      ..addByte(0)
      ..add(utf8.encode('${value.length}:'))
      ..add(value)
      ..addByte(0);
  }
  return (
    bytes: bytes,
    sha256: terminalDifferentialSha256(aggregate.takeBytes()),
  );
}

int _patternMatches(List<List<int>> inputs, List<String> patterns) {
  var matches = 0;
  for (final List<int> input in inputs) {
    for (final String pattern in patterns) {
      if (_containsBytes(input, utf8.encode(pattern))) matches++;
    }
  }
  return matches;
}

bool _containsBytes(List<int> input, List<int> pattern) {
  if (pattern.isEmpty || pattern.length > input.length) return false;
  for (var start = 0; start <= input.length - pattern.length; start++) {
    var equal = true;
    for (var index = 0; index < pattern.length; index++) {
      if (input[start + index] != pattern[index]) {
        equal = false;
        break;
      }
    }
    if (equal) return true;
  }
  return false;
}

void _validateEvidenceDocument(
  Map<String, Object?> document, {
  required List<int> auditorSource,
}) {
  _exactKeys(document, const <String>{
    'format',
    'version',
    'status',
    'inputs',
    'source_integrity',
    'note_capability',
    'resources',
    'architecture',
    'privacy',
    'gates',
  }, 'architecture evidence');
  if (document['format'] != terminalNoteR0ArchitectureEvidenceFormat ||
      document['version'] != 1 ||
      document['status'] != 'pass' ||
      _canonical(document['note_capability']) != _canonical(_noteCapability)) {
    throw const FormatException('architecture evidence identity differs');
  }
  final Map<String, Object?> inputs = _object(document['inputs'], 'inputs');
  _exactKeys(inputs, const <String>{
    'developer_jit_arm64_manifest_sha256',
    'release_arm64_manifest_sha256',
    'release_x86_64_manifest_sha256',
    'release_universal_manifest_sha256',
  }, 'inputs');
  if (!inputs.values.every(_isSha256)) {
    throw const FormatException('architecture input hash is invalid');
  }
  final Map<String, Object?> source = _object(
    document['source_integrity'],
    'source integrity',
  );
  _exactKeys(source, const <String>{
    'architecture_auditor_sha256',
  }, 'source integrity');
  if (source['architecture_auditor_sha256'] !=
      terminalDifferentialSha256(auditorSource)) {
    throw const FormatException('architecture auditor hash differs');
  }
  final Map<String, Object?> resources = _object(
    document['resources'],
    'resources',
  );
  _exactKeys(resources, const <String>{
    'files',
    'bytes',
    'aggregate_sha256',
    'inventories_equal',
    'bytes_equal',
    'universal_evidence_equal',
    'paths_retained',
    'raw_content_retained',
  }, 'resources');
  if (resources['files'] is! int ||
      (resources['files']! as int) <= 0 ||
      resources['bytes'] is! int ||
      (resources['bytes']! as int) <= 0 ||
      !_isSha256(resources['aggregate_sha256']) ||
      resources['inventories_equal'] != true ||
      resources['bytes_equal'] != true ||
      resources['universal_evidence_equal'] != true ||
      resources['paths_retained'] != false ||
      resources['raw_content_retained'] != false) {
    throw const FormatException('architecture resource evidence differs');
  }
  final Map<String, Object?> architecture = _object(
    document['architecture'],
    'architecture',
  );
  _exactKeys(architecture, const <String>{
    'developer_jit_arm64',
    'release_arm64',
    'release_x86_64',
    'release_universal',
    'note_images_per_bundle',
    'note_images',
    'universal_code_images',
    'thin_manifest_ownership',
  }, 'architecture');
  if (_canonical(architecture['developer_jit_arm64']) !=
          _canonical(const <String>['arm64']) ||
      _canonical(architecture['release_arm64']) !=
          _canonical(const <String>['arm64']) ||
      _canonical(architecture['release_x86_64']) !=
          _canonical(const <String>['x86_64']) ||
      _canonical(architecture['release_universal']) !=
          _canonical(const <String>['arm64', 'x86_64']) ||
      architecture['note_images_per_bundle'] != 2 ||
      architecture['note_images'] != 8 ||
      architecture['universal_code_images'] is! int ||
      (architecture['universal_code_images']! as int) < 2 ||
      architecture['thin_manifest_ownership'] != true) {
    throw const FormatException('architecture image evidence differs');
  }
  final Map<String, Object?> privacy = _object(document['privacy'], 'privacy');
  _exactKeys(privacy, const <String>{
    'content_sentinel_matches',
    'absolute_path_matches',
    'manifest_and_neutral_resources_only',
    'content_free',
  }, 'privacy');
  if (privacy['content_sentinel_matches'] != 0 ||
      privacy['absolute_path_matches'] != 0 ||
      privacy['manifest_and_neutral_resources_only'] != true ||
      privacy['content_free'] != true) {
    throw const FormatException('architecture privacy evidence differs');
  }
  const Map<String, Object?> expectedGates = <String, Object?>{
    'strict_manifests': true,
    'release_contract_equality': true,
    'note_capability_equality': true,
    'note_image_architectures': true,
    'neutral_resource_equality': true,
    'universal_resource_evidence': true,
    'thin_manifest_ownership': true,
    'privacy': true,
    'passed': true,
  };
  if (_canonical(document['gates']) != _canonical(expectedGates)) {
    throw const FormatException('architecture gates differ');
  }
}

Future<TerminalNoteR0BundleObservation> loadTerminalNoteR0BundleObservation(
  Directory application,
) async {
  if (!application.isAbsolute ||
      FileSystemEntity.typeSync(application.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const FormatException('application must be an absolute directory');
  }
  final File manifestFile = File(
    '${application.path}/Contents/Resources/runtime-build-manifest.json',
  );
  final String manifestSource = _readBoundedText(manifestFile);
  final Map<String, Object?> manifest = _decodeManifest(manifestSource);
  final Set<String> codePaths = manifest['schemaVersion'] == 1
      ? _codePathsFromThin(manifest)
      : _strictStringList(
          manifest['codePaths'],
          'Universal code paths',
        ).toSet();
  final Map<String, List<int>> resources = <String, List<int>>{};
  final Set<String> folded = <String>{};
  var totalBytes = 0;
  await for (final FileSystemEntity entity in application.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = entity.path.substring(application.path.length + 1);
    if (!_safeRelativePath(relative) || !folded.add(relative.toLowerCase())) {
      throw const FormatException('bundle path inventory is unsafe');
    }
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory)) {
      throw const FormatException('bundle entry type is unsupported');
    }
    if (relative == 'Contents/_CodeSignature' ||
        relative.startsWith('Contents/_CodeSignature/')) {
      continue;
    }
    if (type != FileSystemEntityType.file ||
        relative == 'Contents/Resources/runtime-build-manifest.json' ||
        codePaths.contains(relative)) {
      continue;
    }
    final File file = File(entity.path);
    final int length = file.lengthSync();
    if (length <= 0 || length > _maximumResourceBytes) {
      throw const FormatException('bundle neutral resource size is invalid');
    }
    totalBytes += length;
    if (totalBytes > _maximumAggregateResourceBytes) {
      throw const FormatException('bundle neutral resources are too large');
    }
    resources[relative] = file.readAsBytesSync();
  }
  for (final String codePath in codePaths) {
    if (FileSystemEntity.typeSync(
          '${application.path}/$codePath',
          followLinks: false,
        ) !=
        FileSystemEntityType.file) {
      throw const FormatException('declared bundle code image is missing');
    }
  }
  final Set<String> frameworkArchitectures = await _imageArchitectures(
    File(
      '${application.path}/Contents/Frameworks/'
      'libdart_terminal_notes_macos.dylib',
    ),
  );
  final Set<String> helperArchitectures = await _imageArchitectures(
    File('${application.path}/Contents/lib/libdart_terminal_notes_macos.dylib'),
  );
  return TerminalNoteR0BundleObservation(
    manifestSource: manifestSource,
    neutralResources: resources,
    frameworkArchitectures: frameworkArchitectures,
    helperArchitectures: helperArchitectures,
  );
}

Future<Set<String>> _imageArchitectures(File file) async {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Notes bundle image is missing');
  }
  final ProcessResult result = await Process.run('/usr/bin/lipo', <String>[
    '-archs',
    file.path,
  ]);
  if (result.exitCode != 0 || result.stderr.toString().trim().isNotEmpty) {
    throw const FormatException('Notes image architecture is unavailable');
  }
  final Set<String> architectures = result.stdout
      .toString()
      .trim()
      .split(RegExp(r'\s+'))
      .where((String value) => value.isNotEmpty)
      .toSet();
  if (architectures.isEmpty ||
      architectures.any(
        (String value) => value != 'arm64' && value != 'x86_64',
      )) {
    throw const FormatException('Notes image architecture is invalid');
  }
  return architectures;
}

String _readBoundedText(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('manifest is not a regular file');
  }
  final int length = file.lengthSync();
  if (length <= 0 || length > _maximumManifestBytes) {
    throw const FormatException('manifest size is invalid');
  }
  return utf8.decode(file.readAsBytesSync(), allowMalformed: false);
}

bool _sameResourceMaps(
  Map<String, List<int>> left,
  Map<String, List<int>> right,
) {
  if (!_sameStrings(left.keys, right.keys)) return false;
  for (final String path in left.keys) {
    final List<int> leftBytes = left[path]!;
    final List<int>? rightBytes = right[path];
    if (rightBytes == null || !_sameBytes(leftBytes, rightBytes)) return false;
  }
  return true;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> leftValues = left.toList()..sort();
  final List<String> rightValues = right.toList()..sort();
  if (leftValues.length != rightValues.length) return false;
  for (var index = 0; index < leftValues.length; index++) {
    if (leftValues[index] != rightValues[index]) return false;
  }
  return true;
}

bool _sortedUniqueSafe(List<String> values) {
  String previous = '';
  final Set<String> seen = <String>{};
  for (final String value in values) {
    if (!_safeRelativePath(value) ||
        value.compareTo(previous) <= 0 ||
        !seen.add(value)) {
      return false;
    }
    previous = value;
  }
  return true;
}

List<String> _strictStringList(Object? value, String context) {
  final List<Object?> values = _list(value, context);
  if (values.any((Object? item) => item is! String || item.isEmpty)) {
    throw FormatException('$context is not a string list');
  }
  return values.cast<String>();
}

List<Object?> _list(Object? value, String context) {
  if (value is! List<Object?>) throw FormatException('$context is not a list');
  return value;
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$context is not an object');
  }
  return value;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('$context keys differ');
  }
}

void _validateSafeLeaf(Object? value, String context) =>
    _safeLeaf(value, context);

String _safeLeaf(Object? value, String context) {
  if (value is! String ||
      value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains('\\') ||
      value.contains('\u0000')) {
    throw FormatException('$context is not a safe leaf');
  }
  return value;
}

String _safeRelative(Object? value, String context) {
  if (value is! String || !_safeRelativePath(value)) {
    throw FormatException('$context is not a safe relative path');
  }
  return value;
}

bool _safeRelativePath(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !value.contains('\\') &&
    value
        .split('/')
        .every(
          (String part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              !part.contains('\u0000'),
        );

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Object? _canonicalize(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) _canonicalize(item)];
  }
  return value;
}

String _canonical(Object? value) => jsonEncode(_canonicalize(value));

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _shaText(String source) =>
    terminalDifferentialSha256(utf8.encode(source));

Map<String, String> _parseArguments(List<String> arguments) {
  const Set<String> expected = <String>{
    'developer-jit-app',
    'release-arm64-app',
    'release-x86-64-app',
    'release-universal-app',
    'source-root',
    'output',
  };
  final Map<String, String> result = <String, String>{};
  for (final String argument in arguments) {
    final int separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator <= 2) {
      throw const FormatException('architecture argument is malformed');
    }
    final String key = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    if (!expected.contains(key) || value.isEmpty || result.containsKey(key)) {
      throw const FormatException('architecture argument differs');
    }
    result[key] = value;
  }
  if (result.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(result.keys.toSet()).isNotEmpty) {
    throw const FormatException('architecture arguments are incomplete');
  }
  return result;
}

Future<void> _writeAtomic(File output, String source) async {
  if (!output.isAbsolute) {
    throw const FormatException('architecture output must be absolute');
  }
  await output.parent.create(recursive: true);
  final File temporary = File('${output.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString(source, flush: true);
  await temporary.rename(output.path);
}

Future<void> main(List<String> arguments) async {
  try {
    final Map<String, String> options = _parseArguments(arguments);
    final Directory sourceRoot = Directory(options['source-root']!);
    if (!sourceRoot.isAbsolute || !sourceRoot.existsSync()) {
      throw const FormatException('source root must be absolute');
    }
    final List<int> auditorSource = File.fromUri(
      sourceRoot.uri.resolve('tool/terminal_note_r0_architecture_audit.dart'),
    ).readAsBytesSync();
    final TerminalNoteR0ArchitectureResult result =
        buildTerminalNoteR0ArchitectureEvidence(
          developerJitArm64: await loadTerminalNoteR0BundleObservation(
            Directory(options['developer-jit-app']!),
          ),
          releaseArm64: await loadTerminalNoteR0BundleObservation(
            Directory(options['release-arm64-app']!),
          ),
          releaseX86_64: await loadTerminalNoteR0BundleObservation(
            Directory(options['release-x86-64-app']!),
          ),
          releaseUniversal: await loadTerminalNoteR0BundleObservation(
            Directory(options['release-universal-app']!),
          ),
          auditorSource: auditorSource,
        );
    await _writeAtomic(File(options['output']!), result.encode());
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R0_ARCHITECTURE_FAIL reason=invalid_input '
      'content_free=true',
    );
    exitCode = 1;
  }
}
