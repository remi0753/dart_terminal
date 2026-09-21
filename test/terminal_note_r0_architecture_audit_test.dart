import 'dart:convert';
import 'dart:io';

import '../tool/terminal_differential_sha256.dart';
import '../tool/terminal_note_r0_architecture_audit.dart';

void main() => runTerminalNoteR0ArchitectureAuditTests();

void runTerminalNoteR0ArchitectureAuditTests() {
  final List<int> auditorSource = File(
    'tool/terminal_note_r0_architecture_audit.dart',
  ).readAsBytesSync();
  _testPassingArchitectureEvidence(auditorSource);
  _testManifestAndCapabilityFailures(auditorSource);
  _testResourceAndArchitectureFailures(auditorSource);
  _testPrivacyAndCheckedSchemaFailures(auditorSource);
  _testCheckedArchitectureEvidence(auditorSource);
}

void _testPassingArchitectureEvidence(List<int> auditorSource) {
  final _Fixture fixture = _fixture();
  final TerminalNoteR0ArchitectureResult first = fixture.build(auditorSource);
  final TerminalNoteR0ArchitectureResult second = fixture.build(auditorSource);
  final String encoded = first.encode();
  final Map<String, Object?> document =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> resources =
      document['resources']! as Map<String, Object?>;
  final Map<String, Object?> architecture =
      document['architecture']! as Map<String, Object?>;
  final Map<String, Object?> privacy =
      document['privacy']! as Map<String, Object?>;
  _expect(
    encoded == second.encode() &&
        first.machineLine() == second.machineLine() &&
        document['format'] == terminalNoteR0ArchitectureEvidenceFormat &&
        document['version'] == 1 &&
        document['status'] == 'pass' &&
        resources['files'] == 2 &&
        resources['bytes'] == 13 &&
        resources['inventories_equal'] == true &&
        resources['paths_retained'] == false &&
        architecture['note_images'] == 8 &&
        architecture['universal_code_images'] == 15 &&
        privacy['content_sentinel_matches'] == 0 &&
        privacy['absolute_path_matches'] == 0 &&
        encoded.endsWith('\n') &&
        !encoded.contains('/Users/') &&
        !encoded.contains('Contents/Resources/en.lproj') &&
        !encoded.contains('PRIVATE-WORKER-LOG-BODY-SENTINEL') &&
        !encoded.contains('"raw_content":'),
    'passing architecture evidence is deterministic and content-free',
  );
}

void _testManifestAndCapabilityFailures(List<int> auditorSource) {
  final _Fixture extraKey = _fixture();
  extraKey.releaseArm64Manifest['unexpected'] = true;
  _expectThrows(
    () => extraKey.build(auditorSource),
    'unknown thin manifest key',
  );

  final _Fixture missingCapability = _fixture();
  (missingCapability.releaseX86Manifest['nativeCapabilities']! as List<Object?>)
      .removeLast();
  _expectThrows(
    () => missingCapability.build(auditorSource),
    'missing x86 Notes capability',
  );

  final _Fixture changedAbi = _fixture();
  final List<Object?> developerCapabilities =
      changedAbi.developerManifest['nativeCapabilities']! as List<Object?>;
  (developerCapabilities.last! as Map<String, Object?>)['abiVersion'] = 2;
  _expectThrows(
    () => changedAbi.build(auditorSource),
    'Developer JIT Notes ABI mismatch',
  );

  final _Fixture releaseContract = _fixture();
  releaseContract.releaseX86Manifest['dartSdkRevision'] = 'different';
  _expectThrows(
    () => releaseContract.build(auditorSource),
    'thin Release application contract mismatch',
  );

  final _Fixture thinOwnership = _fixture();
  (thinOwnership.universalManifest['thinManifests']!
          as Map<String, Object?>)['arm64'] =
      _zeroHash;
  _expectThrows(
    () => thinOwnership.build(auditorSource),
    'Universal thin manifest ownership mismatch',
  );
}

void _testResourceAndArchitectureFailures(List<int> auditorSource) {
  final _Fixture changedResource = _fixture();
  changedResource.x86Resources[_localizedPath] = utf8.encode('changed');
  _expectThrows(
    () => changedResource.build(auditorSource),
    'x86 neutral resource byte mismatch',
  );

  final _Fixture extraResource = _fixture();
  extraResource.universalResources['Contents/Resources/extra.txt'] = utf8
      .encode('extra');
  _expectThrows(
    () => extraResource.build(auditorSource),
    'Universal extra neutral resource',
  );

  final _Fixture resourceEvidence = _fixture();
  final List<Object?> entries =
      resourceEvidence.universalManifest['resourceFiles']! as List<Object?>;
  (entries.first! as Map<String, Object?>)['sha256'] = _zeroHash;
  _expectThrows(
    () => resourceEvidence.build(auditorSource),
    'Universal resource evidence hash mismatch',
  );

  final _Fixture wrongThinImage = _fixture();
  wrongThinImage.x86FrameworkArchitectures
    ..clear()
    ..add('arm64');
  _expectThrows(
    () => wrongThinImage.build(auditorSource),
    'x86 Notes framework architecture mismatch',
  );

  final _Fixture incompleteUniversal = _fixture();
  incompleteUniversal.universalHelperArchitectures.remove('x86_64');
  _expectThrows(
    () => incompleteUniversal.build(auditorSource),
    'Universal Notes helper is not universal',
  );

  final _Fixture reversedArchitectures = _fixture();
  reversedArchitectures.universalManifest['architectures'] = <String>[
    'x86_64',
    'arm64',
  ];
  _expectThrows(
    () => reversedArchitectures.build(auditorSource),
    'Universal architecture order mismatch',
  );
}

void _testPrivacyAndCheckedSchemaFailures(List<int> auditorSource) {
  final _Fixture contentLeak = _fixture();
  for (final Map<String, List<int>> resources in contentLeak.allResources) {
    resources[_localizedPath] = utf8.encode('PRIVATE-WORKER-LOG-BODY-SENTINEL');
  }
  _refreshUniversalResourceEvidence(contentLeak);
  _expectThrows(
    () => contentLeak.build(auditorSource),
    'Note body sentinel in equal resources',
  );

  final _Fixture absolutePathLeak = _fixture();
  for (final Map<String, Object?> manifest in absolutePathLeak.allManifests) {
    manifest['dartSdkRevision'] = '/Users/private/build';
  }
  _refreshUniversalContract(absolutePathLeak);
  _expectThrows(
    () => absolutePathLeak.build(auditorSource),
    'absolute path in matching manifests',
  );

  final _Fixture fixture = _fixture();
  Map<String, Object?> fresh() =>
      jsonDecode(fixture.build(auditorSource).encode()) as Map<String, Object?>;
  String encode(Map<String, Object?> value) =>
      '${const JsonEncoder.withIndent('  ').convert(value)}\n';

  final Map<String, Object?> rawPath = fresh();
  rawPath['resource_paths'] = <String>['/Users/private/resource'];
  _expectThrows(
    () => validateTerminalNoteR0ArchitectureEvidence(
      encode(rawPath),
      auditorSource: auditorSource,
    ),
    'unknown raw path evidence',
  );

  final Map<String, Object?> forgedSource = fresh();
  (forgedSource['source_integrity']!
          as Map<String, Object?>)['architecture_auditor_sha256'] =
      _zeroHash;
  _expectThrows(
    () => validateTerminalNoteR0ArchitectureEvidence(
      encode(forgedSource),
      auditorSource: auditorSource,
    ),
    'forged auditor source hash',
  );

  final Map<String, Object?> forgedGate = fresh();
  (forgedGate['gates']! as Map<String, Object?>)['privacy'] = false;
  _expectThrows(
    () => validateTerminalNoteR0ArchitectureEvidence(
      encode(forgedGate),
      auditorSource: auditorSource,
    ),
    'false checked privacy gate',
  );

  _expectThrows(
    () => validateTerminalNoteR0ArchitectureEvidence(
      '${jsonEncode(fresh())}\n',
      auditorSource: auditorSource,
    ),
    'noncanonical checked architecture JSON',
  );
}

void _testCheckedArchitectureEvidence(List<int> auditorSource) {
  final File evidence = File(terminalNoteR0ArchitectureEvidencePath);
  _expect(evidence.existsSync(), 'checked architecture evidence exists');
  final String source = evidence.readAsStringSync();
  final TerminalNoteR0ArchitectureResult result =
      validateTerminalNoteR0ArchitectureEvidence(
        source,
        auditorSource: auditorSource,
      );
  final Map<String, Object?> gates =
      result.document['gates']! as Map<String, Object?>;
  _expect(
    utf8.encode(source).length <= 64 * 1024 &&
        gates.values.every((Object? value) => value == true) &&
        result.machineLine().startsWith(
          'TERMINAL_NOTE_R0_ARCHITECTURE_PASS ',
        ) &&
        !source.contains('/Users/') &&
        !source.contains('Contents/Resources/en.lproj') &&
        !source.contains('PRIVATE-WORKER-LOG-BODY-SENTINEL'),
    'checked architecture evidence is current and content-free',
  );
}

final class _Fixture {
  _Fixture({
    required this.developerManifest,
    required this.releaseArm64Manifest,
    required this.releaseX86Manifest,
    required this.universalManifest,
    required this.developerResources,
    required this.arm64Resources,
    required this.x86Resources,
    required this.universalResources,
    required this.developerFrameworkArchitectures,
    required this.developerHelperArchitectures,
    required this.arm64FrameworkArchitectures,
    required this.arm64HelperArchitectures,
    required this.x86FrameworkArchitectures,
    required this.x86HelperArchitectures,
    required this.universalFrameworkArchitectures,
    required this.universalHelperArchitectures,
  });

  final Map<String, Object?> developerManifest;
  final Map<String, Object?> releaseArm64Manifest;
  final Map<String, Object?> releaseX86Manifest;
  final Map<String, Object?> universalManifest;
  final Map<String, List<int>> developerResources;
  final Map<String, List<int>> arm64Resources;
  final Map<String, List<int>> x86Resources;
  final Map<String, List<int>> universalResources;
  final Set<String> developerFrameworkArchitectures;
  final Set<String> developerHelperArchitectures;
  final Set<String> arm64FrameworkArchitectures;
  final Set<String> arm64HelperArchitectures;
  final Set<String> x86FrameworkArchitectures;
  final Set<String> x86HelperArchitectures;
  final Set<String> universalFrameworkArchitectures;
  final Set<String> universalHelperArchitectures;

  List<Map<String, Object?>> get allManifests => <Map<String, Object?>>[
    developerManifest,
    releaseArm64Manifest,
    releaseX86Manifest,
    universalManifest,
  ];

  List<Map<String, List<int>>> get allResources => <Map<String, List<int>>>[
    developerResources,
    arm64Resources,
    x86Resources,
    universalResources,
  ];

  TerminalNoteR0ArchitectureResult build(List<int> auditorSource) =>
      buildTerminalNoteR0ArchitectureEvidence(
        developerJitArm64: _observation(
          developerManifest,
          developerResources,
          developerFrameworkArchitectures,
          developerHelperArchitectures,
        ),
        releaseArm64: _observation(
          releaseArm64Manifest,
          arm64Resources,
          arm64FrameworkArchitectures,
          arm64HelperArchitectures,
        ),
        releaseX86_64: _observation(
          releaseX86Manifest,
          x86Resources,
          x86FrameworkArchitectures,
          x86HelperArchitectures,
        ),
        releaseUniversal: _observation(
          universalManifest,
          universalResources,
          universalFrameworkArchitectures,
          universalHelperArchitectures,
        ),
        auditorSource: auditorSource,
      );
}

_Fixture _fixture() {
  final Map<String, Object?> developer = _thinManifest(
    mode: 'developer-jit',
    architecture: 'arm64',
  );
  final Map<String, Object?> arm64 = _thinManifest(
    mode: 'release-aot',
    architecture: 'arm64',
  );
  final Map<String, Object?> x86 = _thinManifest(
    mode: 'release-aot',
    architecture: 'x86_64',
  );
  final Map<String, List<int>> resources = <String, List<int>>{
    'Contents/Info.plist': utf8.encode('<plist/>'),
    _localizedPath: utf8.encode('hello'),
  };
  final Map<String, Object?> contract = _normalizedContract(arm64);
  final List<String> codePaths = _fixtureCodePaths()..sort();
  final Map<String, Object?> universal = <String, Object?>{
    'schemaVersion': 2,
    ..._deepCopy(contract),
    'runtimeMode': 'release-aot',
    'architectures': <String>['arm64', 'x86_64'],
    'bundleIdentifier': 'dev.dart-terminal',
    'executable': 'dart_terminal',
    'payload': 'application.aot',
    'engine': 'libdart_engine_aot_shared.dylib',
    'dartSdkVersion': '3.13.2',
    'dartSdkRevision': 'revision',
    'codePaths': codePaths,
    'resourceFiles': _resourceEvidence(resources),
    'thinManifests': <String, Object?>{
      'arm64': _shaManifest(arm64),
      'x86_64': _shaManifest(x86),
    },
    'applicationContract': _deepCopy(contract),
  };
  return _Fixture(
    developerManifest: developer,
    releaseArm64Manifest: arm64,
    releaseX86Manifest: x86,
    universalManifest: universal,
    developerResources: _copyResources(resources),
    arm64Resources: _copyResources(resources),
    x86Resources: _copyResources(resources),
    universalResources: _copyResources(resources),
    developerFrameworkArchitectures: <String>{'arm64'},
    developerHelperArchitectures: <String>{'arm64'},
    arm64FrameworkArchitectures: <String>{'arm64'},
    arm64HelperArchitectures: <String>{'arm64'},
    x86FrameworkArchitectures: <String>{'x86_64'},
    x86HelperArchitectures: <String>{'x86_64'},
    universalFrameworkArchitectures: <String>{'arm64', 'x86_64'},
    universalHelperArchitectures: <String>{'arm64', 'x86_64'},
  );
}

Map<String, Object?> _thinManifest({
  required String mode,
  required String architecture,
}) {
  final bool release = mode == 'release-aot';
  return <String, Object?>{
    'schemaVersion': 1,
    'runtimeMode': mode,
    'architecture': architecture,
    'bundleIdentifier': 'dev.dart-terminal',
    'executable': 'dart_terminal',
    'payload': release ? 'application.aot' : 'application.dill',
    'engine': release
        ? 'libdart_engine_aot_shared.dylib'
        : 'libdart_engine_jit_shared.dylib',
    'dartSdkVersion': '3.13.2',
    'dartSdkRevision': 'revision',
    'runner': <String, Object?>{'activationPolicy': 'regular'},
    'services': <Object?>[],
    'icon': <String, Object?>{'bundleName': 'DartTerminal.icns'},
    'scriptingDefinition': <String, Object?>{'bundleName': 'DartTerminal.sdef'},
    'appIntents': <String, Object?>{
      'library': 'libdart_terminal_app_intents_macos.dylib',
      'targetTriple': '$architecture-apple-macos14.0',
      'libraryBytes': 100,
    },
    'dartHelpers': <Object?>[
      <String, Object?>{
        'name': 'dart_terminal_runtime_worker',
        'entrypoint': 'bin/runtime_worker.dart',
        if (release) 'payload': 'DartHelpers/dart_terminal_runtime_worker.aot',
        'nativeAssets': const <String>[
          'libdart_durable_file_macos.dylib',
          'libdart_pty_macos.dylib',
          'libdart_terminal_applescript_macos.dylib',
          'libdart_terminal_notes_macos.dylib',
          'libdart_terminal_renderer_macos.dylib',
        ],
      },
    ],
    'resources': const <String>[
      'en.lproj/Localizable.strings',
      'resources/terminfo/78/xterm-256color',
    ],
    'nativeAssets': <Object?>[
      <String, Object?>{
        'id': 'dart_pty_macos',
        'library': 'libdart_pty_macos.dylib',
      },
    ],
    'nativeCapabilities': <Object?>[
      <String, Object?>{
        'id': 'dart_terminal_applescript_macos',
        'package': 'dart_terminal_applescript_macos',
        'library': 'libdart_terminal_applescript_macos.dylib',
        'abiVersion': 1,
        'abiVersionSymbol': 'dtas_abi_version',
        'initializerSymbol': 'dtas_initialize',
      },
      <String, Object?>{
        'id': 'dart_terminal_renderer_macos',
        'package': 'dart_terminal_renderer_macos',
        'library': 'libdart_terminal_renderer_macos.dylib',
        'abiVersion': 12,
        'abiVersionSymbol': 'dtr_abi_version',
        'initializerSymbol': 'dtr_initialize',
      },
      <String, Object?>{
        'id': 'dart_terminal_notes_macos',
        'package': 'dart_terminal_notes_macos',
        'library': 'libdart_terminal_notes_macos.dylib',
        'abiVersion': 1,
        'abiVersionSymbol': 'dtn_abi_version',
        'initializerSymbol': 'dtn_initialize',
      },
    ],
  };
}

Map<String, Object?> _normalizedContract(Map<String, Object?> thin) {
  final Map<String, Object?> result = _deepCopy(thin)
    ..remove('schemaVersion')
    ..remove('architecture');
  final Map<String, Object?> appIntents =
      result['appIntents']! as Map<String, Object?>;
  appIntents['targetTriple'] = r'$ARCH-apple-macos14.0';
  appIntents.remove('libraryBytes');
  return _canonicalize(result) as Map<String, Object?>;
}

List<String> _fixtureCodePaths() => <String>[
  'Contents/MacOS/dart_terminal',
  'Contents/Resources/application.aot',
  'Contents/Frameworks/libdart_engine_aot_shared.dylib',
  'Contents/Helpers/dart_terminal_runtime_worker',
  'Contents/Resources/DartHelpers/dart_terminal_runtime_worker.aot',
  'Contents/lib/libdart_durable_file_macos.dylib',
  'Contents/lib/libdart_pty_macos.dylib',
  'Contents/lib/libdart_terminal_applescript_macos.dylib',
  'Contents/lib/libdart_terminal_notes_macos.dylib',
  'Contents/lib/libdart_terminal_renderer_macos.dylib',
  'Contents/Frameworks/libdart_pty_macos.dylib',
  'Contents/Frameworks/libdart_terminal_applescript_macos.dylib',
  'Contents/Frameworks/libdart_terminal_renderer_macos.dylib',
  'Contents/Frameworks/libdart_terminal_notes_macos.dylib',
  'Contents/Frameworks/libdart_terminal_app_intents_macos.dylib',
];

TerminalNoteR0BundleObservation _observation(
  Map<String, Object?> manifest,
  Map<String, List<int>> resources,
  Set<String> frameworkArchitectures,
  Set<String> helperArchitectures,
) => TerminalNoteR0BundleObservation(
  manifestSource: _encodeManifest(manifest),
  neutralResources: resources,
  frameworkArchitectures: frameworkArchitectures,
  helperArchitectures: helperArchitectures,
);

void _refreshUniversalResourceEvidence(_Fixture fixture) {
  fixture.universalManifest['resourceFiles'] = _resourceEvidence(
    fixture.universalResources,
  );
}

void _refreshUniversalContract(_Fixture fixture) {
  final Map<String, Object?> contract = _normalizedContract(
    fixture.releaseArm64Manifest,
  );
  fixture.universalManifest['applicationContract'] = _deepCopy(contract);
  for (final String key in contract.keys) {
    fixture.universalManifest[key] = _deepCopyValue(contract[key]);
  }
  (fixture.universalManifest['thinManifests']! as Map<String, Object?>)
    ..['arm64'] = _shaManifest(fixture.releaseArm64Manifest)
    ..['x86_64'] = _shaManifest(fixture.releaseX86Manifest);
}

List<Map<String, Object?>> _resourceEvidence(Map<String, List<int>> resources) {
  final List<String> paths = resources.keys.toList()..sort();
  return <Map<String, Object?>>[
    for (final String path in paths)
      <String, Object?>{
        'path': path,
        'bytes': resources[path]!.length,
        'sha256': terminalDifferentialSha256(resources[path]!),
      },
  ];
}

Map<String, List<int>> _copyResources(Map<String, List<int>> value) =>
    <String, List<int>>{
      for (final MapEntry<String, List<int>> entry in value.entries)
        entry.key: List<int>.of(entry.value),
    };

String _shaManifest(Map<String, Object?> value) =>
    terminalDifferentialSha256(utf8.encode(_encodeManifest(value)));

String _encodeManifest(Map<String, Object?> value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Object? _deepCopyValue(Object? value) => jsonDecode(jsonEncode(value));

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

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected architecture audit failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('Architecture audit test failed: $message');
}

const String _localizedPath = 'Contents/Resources/en.lproj/Localizable.strings';
const String _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';
