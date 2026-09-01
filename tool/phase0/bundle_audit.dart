import 'dart:convert';
import 'dart:io';

const String _format = 'dart-terminal-bundle-audit';
const int _version = 1;

final class _AuditException implements Exception {
  const _AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.expectedArchitectures,
    required this.deploymentTarget,
    required this.signing,
    required this.bundlePaths,
  });

  final Set<String> expectedArchitectures;
  final String deploymentTarget;
  final String signing;
  final List<String> bundlePaths;
}

_Options _parseOptions(List<String> arguments) {
  Set<String>? expectedArchitectures;
  var deploymentTarget = '14.0';
  var signing = 'adhoc';
  final List<String> bundlePaths = <String>[];
  for (final String argument in arguments) {
    if (argument.startsWith('--expected-architectures=')) {
      final String value = argument.substring(
        '--expected-architectures='.length,
      );
      expectedArchitectures = value
          .split(',')
          .where((String architecture) => architecture.isNotEmpty)
          .toSet();
    } else if (argument.startsWith('--deployment-target=')) {
      deploymentTarget = argument.substring('--deployment-target='.length);
    } else if (argument.startsWith('--signing=')) {
      signing = argument.substring('--signing='.length);
    } else if (argument.startsWith('-')) {
      throw _AuditException('unknown argument: $argument');
    } else {
      bundlePaths.add(argument);
    }
  }
  if (expectedArchitectures == null || expectedArchitectures.isEmpty) {
    throw const _AuditException(
      '--expected-architectures must name at least one architecture',
    );
  }
  const Set<String> supportedArchitectures = <String>{'arm64', 'x86_64'};
  if (!supportedArchitectures.containsAll(expectedArchitectures)) {
    throw _AuditException(
      'unsupported architecture set: ${expectedArchitectures.join(',')}',
    );
  }
  if (!<String>{'adhoc', 'developer-id', 'any'}.contains(signing)) {
    throw _AuditException('unsupported signing policy: $signing');
  }
  if (bundlePaths.isEmpty) {
    throw const _AuditException('at least one .app bundle is required');
  }
  return _Options(
    expectedArchitectures: expectedArchitectures,
    deploymentTarget: deploymentTarget,
    signing: signing,
    bundlePaths: bundlePaths,
  );
}

Future<ProcessResult> _run(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    final String output = '${result.stdout}${result.stderr}'.trim();
    throw _AuditException(
      '${executable.split('/').last} failed (${result.exitCode})'
      '${output.isEmpty ? '' : ': $output'}',
    );
  }
  return result;
}

Future<String> _stdout(String executable, List<String> arguments) async {
  final ProcessResult result = await _run(executable, arguments);
  return (result.stdout as String).trim();
}

Future<String> _plistValue(String plistPath, String key) => _stdout(
  '/usr/bin/plutil',
  <String>['-extract', key, 'raw', '-o', '-', plistPath],
);

Future<List<String>> _architectures(String path) async {
  final String output = await _stdout('/usr/bin/lipo', <String>[
    '-archs',
    path,
  ]);
  final List<String> architectures =
      output
          .split(RegExp(r'\s+'))
          .where((String value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return architectures;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw _AuditException(message);
  }
}

bool _sameSet(Iterable<String> left, Iterable<String> right) {
  final Set<String> leftSet = left.toSet();
  final Set<String> rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

Future<Map<String, Object>> _auditBundle(
  String rawPath,
  _Options options,
) async {
  final Directory bundle = Directory(rawPath).absolute;
  _expect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
  _expect(
    bundle.path.endsWith('.app'),
    'bundle must end in .app: ${bundle.path}',
  );

  final String contentsPath = '${bundle.path}/Contents';
  final String plistPath = '$contentsPath/Info.plist';
  final File plist = File(plistPath);
  _expect(await plist.exists(), 'missing Info.plist: $plistPath');
  await _run('/usr/bin/plutil', <String>['-lint', plistPath]);

  final String packageType = await _plistValue(
    plistPath,
    'CFBundlePackageType',
  );
  final String executableName = await _plistValue(
    plistPath,
    'CFBundleExecutable',
  );
  final String bundleIdentifier = await _plistValue(
    plistPath,
    'CFBundleIdentifier',
  );
  final String deploymentTarget = await _plistValue(
    plistPath,
    'LSMinimumSystemVersion',
  );
  _expect(packageType == 'APPL', 'CFBundlePackageType must be APPL');
  _expect(
    executableName.isNotEmpty && !executableName.contains('/'),
    'invalid CFBundleExecutable: $executableName',
  );
  _expect(
    bundleIdentifier.startsWith('dev.dart-terminal.'),
    'unexpected CFBundleIdentifier: $bundleIdentifier',
  );
  _expect(
    deploymentTarget == options.deploymentTarget,
    'deployment target $deploymentTarget != ${options.deploymentTarget}',
  );

  final String executablePath = '$contentsPath/MacOS/$executableName';
  final String enginePath =
      '$contentsPath/Frameworks/libdart_engine_aot_shared.dylib';
  final String snapshotPath = '$contentsPath/Resources/phase0_app.aot';
  final List<Map<String, Object>> machOFiles = <Map<String, Object>>[];
  for (final MapEntry<String, String> artifact in <String, String>{
    'executable': executablePath,
    'dart_engine': enginePath,
    'aot_snapshot': snapshotPath,
  }.entries) {
    final File file = File(artifact.value);
    _expect(await file.exists(), 'missing ${artifact.key}: ${artifact.value}');
    final List<String> architectures = await _architectures(artifact.value);
    _expect(
      _sameSet(architectures, options.expectedArchitectures),
      '${artifact.key} architectures ${architectures.join(',')} != '
      '${options.expectedArchitectures.join(',')}',
    );
    machOFiles.add(<String, Object>{
      'role': artifact.key,
      'path': artifact.value.substring(contentsPath.length + 1),
      'architectures': architectures,
    });
  }
  final FileStat executableStat = await File(executablePath).stat();
  _expect(
    executableStat.mode & 0x49 != 0,
    'CFBundleExecutable is not executable: $executablePath',
  );

  final String dependencies = await _stdout('/usr/bin/otool', <String>[
    '-L',
    executablePath,
  ]);
  _expect(
    dependencies.contains('@rpath/libdart_engine_aot_shared.dylib'),
    'host does not use the bundle-relative Dart Engine rpath',
  );
  for (final String line in dependencies.split('\n').skip(1)) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final String dependency = trimmed.split(RegExp(r'\s+')).first;
    final bool allowed =
        dependency.startsWith('@') ||
        dependency.startsWith('/System/Library/') ||
        dependency.startsWith('/usr/lib/');
    _expect(allowed, 'non-system absolute dependency: $dependency');
  }

  await _run('/usr/bin/codesign', <String>[
    '--verify',
    '--deep',
    '--strict',
    bundle.path,
  ]);
  final ProcessResult signatureResult = await _run(
    '/usr/bin/codesign',
    <String>['-dv', '--verbose=4', bundle.path],
  );
  final String signature = '${signatureResult.stdout}${signatureResult.stderr}';
  if (options.signing == 'adhoc') {
    _expect(
      signature.contains('Signature=adhoc'),
      'bundle is not ad-hoc signed',
    );
  } else if (options.signing == 'developer-id') {
    _expect(
      !signature.contains('Signature=adhoc') &&
          !signature.contains('TeamIdentifier=not set'),
      'bundle is not signed with a Developer ID identity',
    );
  }

  return <String, Object>{
    'path': bundle.path,
    'bundle_identifier': bundleIdentifier,
    'executable': executableName,
    'deployment_target': deploymentTarget,
    'signing': options.signing,
    'mach_o_files': machOFiles,
    'passed': true,
  };
}

Future<void> main(List<String> arguments) async {
  late final _Options options;
  try {
    options = _parseOptions(arguments);
  } on _AuditException catch (error) {
    stderr.writeln('PHASE0_BUNDLE_AUDIT_USAGE_ERROR ${error.message}');
    exitCode = 64;
    return;
  }

  final List<Map<String, Object?>> bundles = <Map<String, Object?>>[];
  final Set<String> identifiers = <String>{};
  var passed = true;
  for (final String bundlePath in options.bundlePaths) {
    try {
      final Map<String, Object> result = await _auditBundle(
        bundlePath,
        options,
      );
      final String identifier = result['bundle_identifier']! as String;
      if (!identifiers.add(identifier)) {
        throw _AuditException('duplicate bundle identifier: $identifier');
      }
      bundles.add(result);
    } on Object catch (error) {
      passed = false;
      bundles.add(<String, Object?>{
        'path': Directory(bundlePath).absolute.path,
        'passed': false,
        'error': error.toString(),
      });
    }
  }

  final List<String> expectedArchitectures =
      options.expectedArchitectures.toList()..sort();
  final Map<String, Object?> report = <String, Object?>{
    'format': _format,
    'version': _version,
    'status': passed ? 'pass' : 'fail',
    'expected_architectures': expectedArchitectures,
    'deployment_target': options.deploymentTarget,
    'signing_policy': options.signing,
    'bundles': bundles,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  stderr.writeln(
    'PHASE0_BUNDLE_AUDIT_${passed ? 'PASS' : 'FAIL'} '
    'bundles=${bundles.length} architectures=${expectedArchitectures.join(',')}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
