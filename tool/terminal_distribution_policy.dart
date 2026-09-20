import 'dart:convert';
import 'dart:io';

import 'terminal_differential_sha256.dart';

const String terminalDistributionBundleIdentifier = 'dev.dart-terminal';
const String terminalDistributionApplicationName = 'DartTerminal.app';
const String terminalDistributionArchiveName = 'DartTerminal.zip';
const String terminalDistributionManifestName = 'distribution-manifest.json';
const String terminalDistributionIconPath =
    'Contents/Resources/DartTerminal.icns';
const List<String> terminalDistributionCodePaths = <String>[
  'Contents/Frameworks/libdart_engine_aot_shared.dylib',
  'Contents/Frameworks/libdart_pty_macos.dylib',
  'Contents/Frameworks/libdart_terminal_app_intents_macos.dylib',
  'Contents/Frameworks/libdart_terminal_applescript_macos.dylib',
  'Contents/Frameworks/libdart_terminal_notes_macos.dylib',
  'Contents/Frameworks/libdart_terminal_renderer_macos.dylib',
  'Contents/Helpers/dart_terminal_runtime_worker',
  'Contents/MacOS/dart_terminal',
  'Contents/Resources/DartHelpers/dart_terminal_runtime_worker.aot',
  'Contents/Resources/application.aot',
];

List<String> terminalDistributionEntitlementsDisplayArguments(
  String applicationPath,
) => List<String>.unmodifiable(<String>[
  '--display',
  '--entitlements',
  '-',
  '--xml',
  applicationPath,
]);

final class TerminalDistributionPolicyException implements Exception {
  const TerminalDistributionPolicyException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class TerminalDistributionPolicy {
  const TerminalDistributionPolicy._();

  static void validatePreflight({
    required Map<String, Object?> sourceManifest,
    required Map<String, Object?> entitlements,
  }) {
    _expect(entitlements.isEmpty, 'distribution entitlements must be empty');
    _expect(
      sourceManifest['schemaVersion'] == 2 &&
          sourceManifest['runtimeMode'] == 'release-aot' &&
          sourceManifest['bundleIdentifier'] ==
              terminalDistributionBundleIdentifier &&
          _sameStrings(
            _strings(sourceManifest['architectures']),
            const <String>['arm64', 'x86_64'],
          ) &&
          _sameStrings(
            _strings(sourceManifest['codePaths']),
            terminalDistributionCodePaths,
          ),
      'source is not the exact Universal Release AOT product contract',
    );
    final Object? applicationContract = sourceManifest['applicationContract'];
    _expect(
      applicationContract is Map<String, Object?> &&
          applicationContract['bundleIdentifier'] ==
              terminalDistributionBundleIdentifier &&
          applicationContract['runtimeMode'] == 'release-aot' &&
          applicationContract['executable'] == 'dart_terminal',
      'source application contract is invalid',
    );
    final Map<String, Object?> contract =
        applicationContract! as Map<String, Object?>;
    final List<Map<String, Object?>> helpers = _maps(contract['dartHelpers']);
    _expect(
      helpers.length == 1 &&
          _exactEntries(helpers.single, const <String, Object>{
            'name': 'dart_terminal_runtime_worker',
            'entrypoint': 'bin/runtime_worker.dart',
            'payload': 'DartHelpers/dart_terminal_runtime_worker.aot',
          }),
      'source helper contract is invalid',
    );
    final List<Map<String, Object?>> assets = _maps(contract['nativeAssets']);
    _expect(
      assets.length == 1 &&
          assets.single['id'] == 'dart_pty_macos' &&
          assets.single['library'] == 'libdart_pty_macos.dylib',
      'source native asset contract is invalid',
    );
    final List<Map<String, Object?>> capabilities = _maps(
      contract['nativeCapabilities'],
    );
    _expect(
      capabilities.length == 3 &&
          _sameStrings(
            capabilities.map(
              (Map<String, Object?> value) => value['id'] as String,
            ),
            const <String>[
              'dart_terminal_applescript_macos',
              'dart_terminal_notes_macos',
              'dart_terminal_renderer_macos',
            ],
          ),
      'source native capability contract is invalid',
    );
    final Object? appIntents = contract['appIntents'];
    _expect(
      appIntents is Map<String, Object?> &&
          appIntents['library'] == 'libdart_terminal_app_intents_macos.dylib' &&
          appIntents['targetTriple'] == r'$ARCH-apple-macos14.0',
      'source App Intents contract is invalid',
    );
    final Object? icon = contract['icon'];
    _expect(
      icon is Map<String, Object?> &&
          icon.length == 3 &&
          icon['source'] == 'resources/DartTerminal.icns' &&
          icon['bundleName'] == 'DartTerminal.icns' &&
          icon['bytes'] is int &&
          (icon['bytes']! as int) > 0,
      'source application icon contract is invalid',
    );
    final Map<String, Object?> iconContract = icon! as Map<String, Object?>;
    final List<Map<String, Object?>> iconResources =
        _maps(sourceManifest['resourceFiles'])
            .where(
              (Map<String, Object?> value) =>
                  value['path'] == terminalDistributionIconPath,
            )
            .toList();
    _expect(
      iconResources.length == 1 &&
          iconResources.single.length == 3 &&
          iconResources.single['bytes'] == iconContract['bytes'] &&
          _sha256(iconResources.single['sha256']),
      'source application icon resource evidence is invalid',
    );
  }

  static void validateDistributionEvidence({
    required Map<String, Object?> evidence,
    required String sourceManifestSha256,
    required String entitlementsSha256,
    required String signingIdentity,
    required String teamIdentifier,
  }) {
    _expect(
      RegExp(r'^[A-Z0-9]{10}$').hasMatch(teamIdentifier),
      'expected Team ID is invalid',
    );
    _expect(
      evidence.length == 13 &&
          evidence['schemaVersion'] == 1 &&
          evidence['bundleIdentifier'] ==
              terminalDistributionBundleIdentifier &&
          _sameStrings(_strings(evidence['architectures']), const <String>[
            'arm64',
            'x86_64',
          ]) &&
          evidence['sourceManifestSha256'] == sourceManifestSha256 &&
          evidence['entitlementsSha256'] == entitlementsSha256 &&
          evidence['signingIdentity'] == signingIdentity &&
          evidence['teamIdentifier'] == teamIdentifier &&
          evidence['hardenedRuntime'] == true &&
          evidence['secureTimestamp'] == true &&
          evidence['application'] == terminalDistributionApplicationName,
      'distribution evidence header differs from product policy',
    );
    final Object? notarization = evidence['notarization'];
    _expect(
      notarization is Map<String, Object?> &&
          notarization.length == 6 &&
          notarization['id'] is String &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(notarization['id']! as String) &&
          notarization['status'] == 'Accepted' &&
          notarization['logFormatVersion'] is int &&
          (notarization['logFormatVersion']! as int) > 0 &&
          notarization['issues'] == 0 &&
          notarization['stapled'] == true &&
          notarization['gatekeeperAccepted'] == true,
      'distribution notarization evidence is invalid',
    );
    final Object? archive = evidence['archive'];
    _expect(
      archive is Map<String, Object?> &&
          archive.length == 2 &&
          archive['name'] == terminalDistributionArchiveName &&
          _sha256(archive['sha256']),
      'distribution archive evidence is invalid',
    );
    final List<Map<String, Object?>> code = _maps(evidence['code']);
    _expect(
      code.length == terminalDistributionCodePaths.length &&
          _sameStrings(
            code.map((Map<String, Object?> value) => value['path'] as String),
            terminalDistributionCodePaths,
          ) &&
          code.every(
            (Map<String, Object?> value) =>
                value.length == 2 && _sha256(value['sha256']),
          ),
      'distribution code evidence is invalid',
    );
  }

  static bool _exactEntries(
    Map<String, Object?> source,
    Map<String, Object> expected,
  ) =>
      source.length == expected.length &&
      expected.entries.every(
        (MapEntry<String, Object> entry) => source[entry.key] == entry.value,
      );

  static List<String> _strings(Object? value) {
    _expect(value is List<Object?>, 'expected a string list');
    final List<Object?> values = value! as List<Object?>;
    _expect(
      values.every((Object? item) => item is String),
      'expected a string list',
    );
    return values.cast<String>();
  }

  static List<Map<String, Object?>> _maps(Object? value) {
    _expect(value is List<Object?>, 'expected an object list');
    final List<Object?> values = value! as List<Object?>;
    _expect(
      values.every((Object? item) => item is Map<String, Object?>),
      'expected an object list',
    );
    return values.cast<Map<String, Object?>>();
  }

  static bool _sha256(Object? value) =>
      value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static void _expect(bool condition, String message) {
    if (!condition) throw TerminalDistributionPolicyException(message);
  }
}

Future<void> main(List<String> arguments) async {
  try {
    String? sourcePath;
    String? entitlementsPath;
    String? distributionPath;
    String? signingIdentity;
    String? teamIdentifier;
    for (final String argument in arguments) {
      if (argument.startsWith('--source-app=')) {
        sourcePath = argument.substring('--source-app='.length);
      } else if (argument.startsWith('--entitlements=')) {
        entitlementsPath = argument.substring('--entitlements='.length);
      } else if (argument.startsWith('--distribution-directory=')) {
        distributionPath = argument.substring(
          '--distribution-directory='.length,
        );
      } else if (argument.startsWith('--signing-identity=')) {
        signingIdentity = argument.substring('--signing-identity='.length);
      } else if (argument.startsWith('--team-id=')) {
        teamIdentifier = argument.substring('--team-id='.length);
      } else {
        throw TerminalDistributionPolicyException(
          'unknown or malformed argument: $argument',
        );
      }
    }
    if (sourcePath == null || entitlementsPath == null) {
      throw const TerminalDistributionPolicyException(
        '--source-app and --entitlements are required',
      );
    }
    final Directory source = Directory(sourcePath).absolute;
    final File entitlements = File(entitlementsPath).absolute;
    final Map<String, Object?> sourceManifest = await _jsonFile(
      File('${source.path}/Contents/Resources/runtime-build-manifest.json'),
    );
    final Map<String, Object?> entitlementMap = await _plistJson(entitlements);
    TerminalDistributionPolicy.validatePreflight(
      sourceManifest: sourceManifest,
      entitlements: entitlementMap,
    );
    if (distributionPath == null &&
        signingIdentity == null &&
        teamIdentifier == null) {
      stdout.writeln(
        'TERMINAL_DISTRIBUTION_POLICY_PASS code=${terminalDistributionCodePaths.length} entitlements=0',
      );
      return;
    }
    if (distributionPath == null ||
        signingIdentity == null ||
        signingIdentity.isEmpty ||
        teamIdentifier == null) {
      throw const TerminalDistributionPolicyException(
        'full audit requires distribution directory, identity, and Team ID',
      );
    }
    await _auditDistribution(
      source: source,
      entitlements: entitlements,
      distribution: Directory(distributionPath).absolute,
      signingIdentity: signingIdentity,
      teamIdentifier: teamIdentifier,
    );
    stdout.writeln(
      'TERMINAL_DISTRIBUTION_AUDIT_PASS code=${terminalDistributionCodePaths.length} notarization=Accepted issues=0',
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DISTRIBUTION_AUDIT_FAIL $error');
    exitCode = 1;
  }
}

Future<void> _auditDistribution({
  required Directory source,
  required File entitlements,
  required Directory distribution,
  required String signingIdentity,
  required String teamIdentifier,
}) async {
  _expect(await distribution.exists(), 'distribution directory is missing');
  final Set<String> entries = <String>{};
  await for (final FileSystemEntity entity in distribution.list()) {
    _expect(
      await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.link,
      'distribution contains a symbolic link',
    );
    entries.add(
      entity.uri.pathSegments.lastWhere((String value) => value.isNotEmpty),
    );
  }
  _expect(
    _sameStrings(entries, const <String>[
      terminalDistributionApplicationName,
      terminalDistributionArchiveName,
      terminalDistributionManifestName,
    ]),
    'distribution root inventory is not exact',
  );
  final Directory application = Directory(
    '${distribution.path}/$terminalDistributionApplicationName',
  );
  final File archive = File(
    '${distribution.path}/$terminalDistributionArchiveName',
  );
  final Map<String, Object?> evidence = await _jsonFile(
    File('${distribution.path}/$terminalDistributionManifestName'),
  );
  TerminalDistributionPolicy.validateDistributionEvidence(
    evidence: evidence,
    sourceManifestSha256: await _fileSha256(
      File('${source.path}/Contents/Resources/runtime-build-manifest.json'),
    ),
    entitlementsSha256: await _fileSha256(entitlements),
    signingIdentity: signingIdentity,
    teamIdentifier: teamIdentifier,
  );
  final Map<String, Object?> archiveEvidence =
      evidence['archive']! as Map<String, Object?>;
  _expect(
    await _fileSha256(archive) == archiveEvidence['sha256'],
    'distribution archive bytes differ from evidence',
  );
  final Map<String, String> codeHashes = <String, String>{
    for (final Map<String, Object?> value
        in (evidence['code']! as List<Object?>).cast<Map<String, Object?>>())
      value['path']! as String: value['sha256']! as String,
  };
  for (final String path in terminalDistributionCodePaths) {
    _expect(
      await _fileSha256(File('${application.path}/$path')) == codeHashes[path],
      'signed code differs from evidence: $path',
    );
  }
  final File sourceIcon = File('${source.path}/$terminalDistributionIconPath');
  final File distributedIcon = File(
    '${application.path}/$terminalDistributionIconPath',
  );
  _expect(
    await sourceIcon.exists() &&
        await distributedIcon.exists() &&
        await _fileSha256(sourceIcon) == await _fileSha256(distributedIcon),
    'distributed application icon differs from the reviewed source',
  );
  final String requirement =
      'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
      'and certificate leaf[subject.OU] = "$teamIdentifier"';
  await _run('/usr/bin/codesign', <String>[
    '--verify',
    '--deep',
    '--strict',
    '-R=$requirement',
    application.path,
  ]);
  for (final String path in <String>[
    for (final String codePath in terminalDistributionCodePaths)
      '${application.path}/$codePath',
    application.path,
  ]) {
    final ProcessResult result = await _run('/usr/bin/codesign', <String>[
      '--display',
      '--verbose=4',
      path,
    ]);
    final String details = '${result.stdout}\n${result.stderr}';
    _expect(
      details.contains('Authority=Developer ID Application:') &&
          details.contains('TeamIdentifier=$teamIdentifier') &&
          RegExp(r'flags=.*\bruntime\b').hasMatch(details) &&
          RegExp(r'^Timestamp=.+$', multiLine: true).hasMatch(details) &&
          !details.contains('Signature=adhoc'),
      'signed code metadata differs from distribution policy: $path',
    );
  }
  final ProcessResult signedEntitlements = await _run(
    '/usr/bin/codesign',
    terminalDistributionEntitlementsDisplayArguments(application.path),
  );
  _expect(
    (signedEntitlements.stdout as String).trim().isNotEmpty,
    'signed application has no extractable entitlements',
  );
  final Directory entitlementExtraction = await Directory.systemTemp.createTemp(
    'dart-terminal-entitlements-audit-',
  );
  try {
    final File extractedEntitlements = File(
      '${entitlementExtraction.path}/signed.entitlements',
    );
    await extractedEntitlements.writeAsString(
      signedEntitlements.stdout as String,
      flush: true,
    );
    _expect(
      (await _plistJson(extractedEntitlements)).isEmpty,
      'signed application entitlements are not empty',
    );
  } finally {
    await entitlementExtraction.delete(recursive: true);
  }
  await _run('/usr/bin/xcrun', <String>[
    'stapler',
    'validate',
    '-v',
    application.path,
  ]);
  await _run('/usr/sbin/spctl', <String>[
    '--assess',
    '--type',
    'execute',
    '--verbose=4',
    application.path,
  ]);
  final Directory extraction = await Directory.systemTemp.createTemp(
    'dart-terminal-distribution-audit-',
  );
  try {
    await _run('/usr/bin/ditto', <String>[
      '-x',
      '-k',
      archive.path,
      extraction.path,
    ]);
    final Directory extracted = Directory(
      '${extraction.path}/$terminalDistributionApplicationName',
    );
    _expect(await extracted.exists(), 'archive omitted the application');
    _expect(
      _sameStringMap(
        await _bundleHashes(application),
        await _bundleHashes(extracted),
      ),
      'archive application differs from the stapled application',
    );
  } finally {
    await extraction.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _plistJson(File file) async {
  _expect(
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file,
    'entitlements must be a regular file',
  );
  final ProcessResult result = await _run('/usr/bin/plutil', <String>[
    '-convert',
    'json',
    '-o',
    '-',
    file.path,
  ]);
  final Object? value = jsonDecode(result.stdout as String);
  _expect(value is Map<String, Object?>, 'entitlements must be a dictionary');
  return value! as Map<String, Object?>;
}

Future<Map<String, Object?>> _jsonFile(File file) async {
  _expect(
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file,
    'required JSON file is missing or not regular: ${file.path}',
  );
  final Object? value = jsonDecode(await file.readAsString());
  _expect(value is Map<String, Object?>, 'required JSON root is not an object');
  return value! as Map<String, Object?>;
}

Future<Map<String, String>> _bundleHashes(Directory root) async {
  final Map<String, String> result = <String, String>{};
  final Set<String> folded = <String>{};
  await for (final FileSystemEntity entity in root.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = entity.path.substring(root.path.length + 1);
    final FileSystemEntityType type = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    _expect(type != FileSystemEntityType.link, 'bundle contains a symlink');
    _expect(
      type == FileSystemEntityType.file ||
          type == FileSystemEntityType.directory,
      'bundle contains an unsupported entry',
    );
    _expect(
      folded.add(relative.toLowerCase()),
      'bundle contains case-folded aliases',
    );
    if (type == FileSystemEntityType.file) {
      result[relative] = await _fileSha256(File(entity.path));
    }
  }
  return result;
}

Future<String> _fileSha256(File file) async =>
    terminalDifferentialSha256(await file.readAsBytes());

Future<ProcessResult> _run(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  _expect(
    result.exitCode == 0,
    '$executable failed (${result.exitCode}): ${result.stderr}',
  );
  return result;
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> a = left.toList()..sort();
  final List<String> b = right.toList()..sort();
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; ++index) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) =>
    _sameStrings(left.keys, right.keys) &&
    left.entries.every(
      (MapEntry<String, String> entry) => right[entry.key] == entry.value,
    );

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDistributionPolicyException(message);
}
