import 'dart:convert';
import 'dart:io';

const String _format = 'dart-terminal-runtime-bundle-audit';
const int _version = 1;

final class _AuditException implements Exception {
  const _AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _RuntimeMode {
  developerJit(
    name: 'developer-jit',
    bundleIdentifier: 'dev.dart-terminal.developer-jit',
    engineName: 'libdart_engine_jit_shared.dylib',
    payloadName: 'application.dill',
    incompatibleEngineName: 'libdart_engine_aot_shared.dylib',
    incompatiblePayloadName: 'application.aot',
  ),
  releaseAot(
    name: 'release-aot',
    bundleIdentifier: 'dev.dart-terminal.release-aot',
    engineName: 'libdart_engine_aot_shared.dylib',
    payloadName: 'application.aot',
    incompatibleEngineName: 'libdart_engine_jit_shared.dylib',
    incompatiblePayloadName: 'application.dill',
  );

  const _RuntimeMode({
    required this.name,
    required this.bundleIdentifier,
    required this.engineName,
    required this.payloadName,
    required this.incompatibleEngineName,
    required this.incompatiblePayloadName,
  });

  final String name;
  final String bundleIdentifier;
  final String engineName;
  final String payloadName;
  final String incompatibleEngineName;
  final String incompatiblePayloadName;
}

final class _Options {
  const _Options({
    required this.mode,
    required this.expectedArchitectures,
    required this.deploymentTarget,
    required this.bundlePath,
  });

  final _RuntimeMode mode;
  final Set<String> expectedArchitectures;
  final String deploymentTarget;
  final String bundlePath;
}

_Options _parseOptions(List<String> arguments) {
  _RuntimeMode? mode;
  Set<String>? expectedArchitectures;
  var deploymentTarget = '14.0';
  String? bundlePath;

  for (final String argument in arguments) {
    if (argument.startsWith('--mode=')) {
      final String value = argument.substring('--mode='.length);
      mode = _RuntimeMode.values
          .where((_RuntimeMode candidate) => candidate.name == value)
          .firstOrNull;
    } else if (argument.startsWith('--expected-architectures=')) {
      expectedArchitectures = argument
          .substring('--expected-architectures='.length)
          .split(',')
          .where((String architecture) => architecture.isNotEmpty)
          .toSet();
    } else if (argument.startsWith('--deployment-target=')) {
      deploymentTarget = argument.substring('--deployment-target='.length);
    } else if (argument.startsWith('-')) {
      throw _AuditException('unknown argument: $argument');
    } else if (bundlePath != null) {
      throw const _AuditException('exactly one app bundle is required');
    } else {
      bundlePath = argument;
    }
  }

  if (mode == null) {
    throw const _AuditException('--mode must be developer-jit or release-aot');
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
  if (bundlePath == null) {
    throw const _AuditException('one app bundle is required');
  }
  return _Options(
    mode: mode,
    expectedArchitectures: expectedArchitectures,
    deploymentTarget: deploymentTarget,
    bundlePath: bundlePath,
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
  return output
      .split(RegExp(r'\s+'))
      .where((String value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
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

Future<List<String>> _relativeFiles(Directory contents) async {
  final List<String> paths = <String>[];
  await for (final FileSystemEntity entity in contents.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      paths.add(entity.path.substring(contents.path.length + 1));
    }
  }
  paths.sort();
  return paths;
}

Future<Map<String, Object?>> _audit(_Options options) async {
  final Directory bundle = Directory(options.bundlePath).absolute;
  _expect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
  _expect(bundle.path.endsWith('.app'), 'bundle must end in .app');

  final Directory contents = Directory('${bundle.path}/Contents');
  final String plistPath = '${contents.path}/Info.plist';
  _expect(await File(plistPath).exists(), 'missing Info.plist: $plistPath');
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
  final String declaredMode = await _plistValue(plistPath, 'DTRuntimeMode');

  _expect(packageType == 'APPL', 'CFBundlePackageType must be APPL');
  _expect(
    executableName.isNotEmpty && !executableName.contains('/'),
    'invalid CFBundleExecutable: $executableName',
  );
  _expect(
    bundleIdentifier == options.mode.bundleIdentifier,
    'bundle identifier $bundleIdentifier != '
    '${options.mode.bundleIdentifier}',
  );
  _expect(
    deploymentTarget == options.deploymentTarget,
    'deployment target $deploymentTarget != ${options.deploymentTarget}',
  );
  _expect(
    declaredMode == options.mode.name,
    'declared runtime mode $declaredMode != ${options.mode.name}',
  );

  final String executablePath = '${contents.path}/MacOS/$executableName';
  final String enginePath =
      '${contents.path}/Frameworks/${options.mode.engineName}';
  final String payloadPath =
      '${contents.path}/Resources/${options.mode.payloadName}';
  final List<String> files = await _relativeFiles(contents);

  for (final String requiredPath in <String>[
    'MacOS/$executableName',
    'Frameworks/${options.mode.engineName}',
    'Resources/${options.mode.payloadName}',
  ]) {
    _expect(
      files.contains(requiredPath),
      'missing runtime file: $requiredPath',
    );
  }
  _expect(
    !files.contains('Frameworks/${options.mode.incompatibleEngineName}'),
    'bundle contains incompatible Engine: '
    '${options.mode.incompatibleEngineName}',
  );
  _expect(
    !files.contains('Resources/${options.mode.incompatiblePayloadName}'),
    'bundle contains incompatible payload: '
    '${options.mode.incompatiblePayloadName}',
  );

  final List<String> engineFiles = files
      .where(
        (String path) =>
            path.startsWith('Frameworks/libdart_engine_') &&
            path.endsWith('.dylib'),
      )
      .toList();
  _expect(
    engineFiles.length == 1 &&
        engineFiles.single == 'Frameworks/${options.mode.engineName}',
    'bundle must contain exactly one mode-matching Dart Engine: '
    '${engineFiles.join(',')}',
  );

  if (options.mode == _RuntimeMode.developerJit) {
    final List<String> aotPayloads = files
        .where((String path) => path.toLowerCase().endsWith('.aot'))
        .toList();
    _expect(
      aotPayloads.isEmpty,
      'developer JIT bundle contains AOT payloads: ${aotPayloads.join(',')}',
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
    _expect(
      forbiddenReleaseFiles.isEmpty,
      'release AOT bundle contains JIT/VM-service assets: '
      '${forbiddenReleaseFiles.join(',')}',
    );
  }

  final FileStat executableStat = await File(executablePath).stat();
  _expect(
    executableStat.mode & 0x49 != 0,
    'CFBundleExecutable is not executable: $executablePath',
  );
  final FileStat payloadStat = await File(payloadPath).stat();
  _expect(payloadStat.size > 0, 'runtime payload is empty: $payloadPath');

  final List<Map<String, Object>> machOFiles = <Map<String, Object>>[];
  final Map<String, String> architectureInputs = <String, String>{
    'executable': executablePath,
    'dart_engine': enginePath,
    if (options.mode == _RuntimeMode.releaseAot) 'aot_snapshot': payloadPath,
  };
  for (final MapEntry<String, String> artifact in architectureInputs.entries) {
    final List<String> architectures = await _architectures(artifact.value);
    _expect(
      _sameSet(architectures, options.expectedArchitectures),
      '${artifact.key} architectures ${architectures.join(',')} != '
      '${options.expectedArchitectures.join(',')}',
    );
    machOFiles.add(<String, Object>{
      'role': artifact.key,
      'path': artifact.value.substring(contents.path.length + 1),
      'architectures': architectures,
    });
  }

  final String dependencies = await _stdout('/usr/bin/otool', <String>[
    '-L',
    executablePath,
  ]);
  final String expectedEngineDependency = '@rpath/${options.mode.engineName}';
  _expect(
    dependencies.contains(expectedEngineDependency),
    'host does not use $expectedEngineDependency',
  );
  _expect(
    !dependencies.contains(options.mode.incompatibleEngineName),
    'host links the incompatible Engine '
    '${options.mode.incompatibleEngineName}',
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
  _expect(signature.contains('Signature=adhoc'), 'bundle is not ad-hoc signed');

  return <String, Object?>{
    'path': bundle.path,
    'runtime_mode': options.mode.name,
    'bundle_identifier': bundleIdentifier,
    'executable': executableName,
    'engine': 'Frameworks/${options.mode.engineName}',
    'payload': 'Resources/${options.mode.payloadName}',
    'deployment_target': deploymentTarget,
    'architectures': options.expectedArchitectures.toList()..sort(),
    'mach_o_files': machOFiles,
    'signing': 'adhoc',
    'passed': true,
  };
}

Future<void> main(List<String> arguments) async {
  late final _Options options;
  try {
    options = _parseOptions(arguments);
  } on _AuditException catch (error) {
    stderr.writeln('RUNTIME_BUNDLE_AUDIT_USAGE_ERROR ${error.message}');
    exitCode = 64;
    return;
  }

  Map<String, Object?> result;
  var passed = true;
  try {
    result = await _audit(options);
  } on Object catch (error) {
    passed = false;
    result = <String, Object?>{
      'path': Directory(options.bundlePath).absolute.path,
      'runtime_mode': options.mode.name,
      'passed': false,
      'error': error.toString(),
    };
  }

  final Map<String, Object?> report = <String, Object?>{
    'format': _format,
    'version': _version,
    'status': passed ? 'pass' : 'fail',
    'result': result,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  stderr.writeln(
    'RUNTIME_BUNDLE_AUDIT_${passed ? 'PASS' : 'FAIL'} '
    'mode=${options.mode.name}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
