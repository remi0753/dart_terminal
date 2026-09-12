import 'dart:convert';
import 'dart:io';

import '../tool/terminal_distribution_policy.dart';

var _failures = 0;

void _test(String name, void Function() body) {
  try {
    body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    ++_failures;
    stderr.writeln('FAIL $name: $error\n$stackTrace');
  }
}

void _expectThrows(void Function() body) {
  try {
    body();
  } on TerminalDistributionPolicyException {
    return;
  }
  throw StateError('expected TerminalDistributionPolicyException');
}

Map<String, Object?> _source() => <String, Object?>{
  'schemaVersion': 2,
  'runtimeMode': 'release-aot',
  'bundleIdentifier': terminalDistributionBundleIdentifier,
  'architectures': const <String>['arm64', 'x86_64'],
  'codePaths': terminalDistributionCodePaths,
  'applicationContract': <String, Object?>{
    'runtimeMode': 'release-aot',
    'bundleIdentifier': terminalDistributionBundleIdentifier,
    'executable': 'dart_terminal',
    'dartHelpers': <Object?>[
      <String, Object?>{
        'name': 'dart_terminal_runtime_worker',
        'entrypoint': 'bin/runtime_worker.dart',
        'payload': 'DartHelpers/dart_terminal_runtime_worker.aot',
      },
    ],
    'nativeAssets': <Object?>[
      <String, Object?>{
        'id': 'dart_pty_macos',
        'library': 'libdart_pty_macos.dylib',
      },
    ],
    'nativeCapabilities': <Object?>[
      <String, Object?>{'id': 'dart_terminal_applescript_macos'},
      <String, Object?>{'id': 'dart_terminal_renderer_macos'},
    ],
    'appIntents': <String, Object?>{
      'library': 'libdart_terminal_app_intents_macos.dylib',
      'targetTriple': r'$ARCH-apple-macos14.0',
    },
  },
};

Map<String, Object?> _evidence() => <String, Object?>{
  'schemaVersion': 1,
  'bundleIdentifier': terminalDistributionBundleIdentifier,
  'architectures': const <String>['arm64', 'x86_64'],
  'sourceManifestSha256': _hex('a'),
  'entitlementsSha256': _hex('b'),
  'signingIdentity': 'Developer ID Application: Example (ABCDE12345)',
  'teamIdentifier': 'ABCDE12345',
  'hardenedRuntime': true,
  'secureTimestamp': true,
  'notarization': <String, Object?>{
    'id': '12345678-1234-1234-1234-123456789abc',
    'status': 'Accepted',
    'logFormatVersion': 1,
    'issues': 0,
    'stapled': true,
    'gatekeeperAccepted': true,
  },
  'application': terminalDistributionApplicationName,
  'archive': <String, Object?>{
    'name': terminalDistributionArchiveName,
    'sha256': _hex('c'),
  },
  'code': <Map<String, Object?>>[
    for (final String path in terminalDistributionCodePaths)
      <String, Object?>{'path': path, 'sha256': _hex('d')},
  ],
};

Map<String, Object?> _clone(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

String _hex(String value) => List<String>.filled(64, value).join();

void main() {
  _test('exact empty-entitlement preflight passes', () {
    TerminalDistributionPolicy.validatePreflight(
      sourceManifest: _source(),
      entitlements: const <String, Object?>{},
    );
  });

  _test('every added entitlement is rejected', () {
    for (final Map<String, Object?> entitlements in <Map<String, Object?>>[
      <String, Object?>{'com.apple.security.get-task-allow': true},
      <String, Object?>{'com.apple.security.cs.allow-jit': true},
      <String, Object?>{'com.example.unreviewed': false},
    ]) {
      _expectThrows(
        () => TerminalDistributionPolicy.validatePreflight(
          sourceManifest: _source(),
          entitlements: entitlements,
        ),
      );
    }
  });

  _test('source header and exact code inventory fail closed', () {
    final List<Map<String, Object?>> invalid = <Map<String, Object?>>[];
    for (final String key in <String>[
      'schemaVersion',
      'runtimeMode',
      'bundleIdentifier',
      'architectures',
      'codePaths',
    ]) {
      final Map<String, Object?> source = _clone(_source());
      source[key] = switch (key) {
        'schemaVersion' => 1,
        'runtimeMode' => 'developer-jit',
        'bundleIdentifier' => 'dev.example.other',
        'architectures' => <String>['arm64'],
        'codePaths' => <String>[...terminalDistributionCodePaths]..removeLast(),
        _ => throw StateError('unreachable'),
      };
      invalid.add(source);
    }
    for (final Map<String, Object?> source in invalid) {
      _expectThrows(
        () => TerminalDistributionPolicy.validatePreflight(
          sourceManifest: source,
          entitlements: const <String, Object?>{},
        ),
      );
    }
  });

  _test(
    'product helper, asset, capability, and intents drift fails closed',
    () {
      for (final String key in <String>[
        'dartHelpers',
        'nativeAssets',
        'nativeCapabilities',
        'appIntents',
      ]) {
        final Map<String, Object?> source = _clone(_source());
        final Map<String, Object?> contract =
            source['applicationContract']! as Map<String, Object?>;
        contract[key] = key == 'appIntents' ? <String, Object?>{} : <Object?>[];
        _expectThrows(
          () => TerminalDistributionPolicy.validatePreflight(
            sourceManifest: source,
            entitlements: const <String, Object?>{},
          ),
        );
      }
    },
  );

  _test('exact accepted distribution evidence passes', () {
    TerminalDistributionPolicy.validateDistributionEvidence(
      evidence: _evidence(),
      sourceManifestSha256: _hex('a'),
      entitlementsSha256: _hex('b'),
      signingIdentity: 'Developer ID Application: Example (ABCDE12345)',
      teamIdentifier: 'ABCDE12345',
    );
  });

  _test('distribution authority and notarization drift fails closed', () {
    final List<Map<String, Object?>> invalid = <Map<String, Object?>>[];
    for (final String key in <String>[
      'sourceManifestSha256',
      'entitlementsSha256',
      'signingIdentity',
      'teamIdentifier',
      'hardenedRuntime',
      'secureTimestamp',
      'application',
    ]) {
      final Map<String, Object?> evidence = _clone(_evidence());
      evidence[key] = key.endsWith('Sha256')
          ? _hex('0')
          : key == 'hardenedRuntime' || key == 'secureTimestamp'
          ? false
          : 'unexpected';
      invalid.add(evidence);
    }
    for (final String key in <String>[
      'status',
      'logFormatVersion',
      'issues',
      'stapled',
      'gatekeeperAccepted',
    ]) {
      final Map<String, Object?> evidence = _clone(_evidence());
      final Map<String, Object?> notarization =
          evidence['notarization']! as Map<String, Object?>;
      notarization[key] = switch (key) {
        'status' => 'Invalid',
        'logFormatVersion' => 0,
        'issues' => 1,
        _ => false,
      };
      invalid.add(evidence);
    }
    for (final Map<String, Object?> evidence in invalid) {
      _expectThrows(
        () => TerminalDistributionPolicy.validateDistributionEvidence(
          evidence: evidence,
          sourceManifestSha256: _hex('a'),
          entitlementsSha256: _hex('b'),
          signingIdentity: 'Developer ID Application: Example (ABCDE12345)',
          teamIdentifier: 'ABCDE12345',
        ),
      );
    }
  });

  _test('archive and code evidence drift fails closed', () {
    final Map<String, Object?> archive = _clone(_evidence());
    (archive['archive']! as Map<String, Object?>)['sha256'] = 'bad';
    final Map<String, Object?> code = _clone(_evidence());
    (code['code']! as List<Object?>).removeLast();
    final Map<String, Object?> extra = _clone(_evidence());
    extra['unexpected'] = true;
    for (final Map<String, Object?> evidence in <Map<String, Object?>>[
      archive,
      code,
      extra,
    ]) {
      _expectThrows(
        () => TerminalDistributionPolicy.validateDistributionEvidence(
          evidence: evidence,
          sourceManifestSha256: _hex('a'),
          entitlementsSha256: _hex('b'),
          signingIdentity: 'Developer ID Application: Example (ABCDE12345)',
          teamIdentifier: 'ABCDE12345',
        ),
      );
    }
  });

  if (_failures != 0) {
    stderr.writeln('$_failures terminal distribution policy test(s) failed');
    exitCode = 1;
  }
}
