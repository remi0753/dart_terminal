import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/src/runtime_lifecycle.dart';

import 'src/runtime_release_support.dart';

final class _FreshnessException implements Exception {
  const _FreshnessException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.projectRoot,
    required this.make,
    required this.focus,
  });

  final String projectRoot;
  final String make;
  final String? focus;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _FreshnessException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw _FreshnessException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> allowed = <String>{'project-root', 'make', 'focus'};
  const Set<String> required = <String>{'project-root', 'make'};
  final Set<String> unknown = values.keys.toSet().difference(allowed);
  final Set<String> missing = required.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _FreshnessException(
      'unknown=${unknown.join(',')} missing=${missing.join(',')}',
    );
  }
  if (!Directory(values['project-root']!).isAbsolute ||
      !File(values['make']!).isAbsolute) {
    throw const _FreshnessException('paths must be absolute');
  }
  final String? focus = values['focus'];
  if (focus != null &&
      focus != 'engine-patch-composition' &&
      focus != 'developer-clean-sdk') {
    throw _FreshnessException('unknown focus: $focus');
  }
  return _Options(
    projectRoot: values['project-root']!,
    make: values['make']!,
    focus: focus,
  );
}

Future<void> _runBuild(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig, {
  List<String> protectedPathOverrides = const <String>[],
  String? sdkRoot,
  String? clang,
  String? dartSdkRoot,
  bool forceRebuild = false,
}) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      if (forceRebuild) '-B',
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      'RUNTIME_PACKAGE_CONFIG=$packageConfig',
      if (sdkRoot != null) 'SDKROOT=$sdkRoot',
      if (clang != null) 'CLANGXX=$clang',
      if (dartSdkRoot != null) 'DART_SDK_ROOT=$dartSdkRoot',
      ...protectedPathOverrides,
      'developer-jit-build',
      'release-aot-build',
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  if (result.exitCode != 0) {
    throw _FreshnessException(
      'isolated runtime build failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
}

Future<void> _runBuildExpectingFlagFailure(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig,
  String nativeFlags,
) async {
  for (final String target in <String>[
    'developer-jit-build',
    'release-aot-build',
  ]) {
    final ProcessResult result = await Process.run(
      options.make,
      <String>[
        '-C',
        options.projectRoot,
        'RUNTIME_BUILD_DIR=$buildRoot',
        'RUNTIME_ARCH=arm64',
        'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
        'RUNTIME_PACKAGE_CONFIG=$packageConfig',
        'NATIVE_FLAGS=$nativeFlags',
        target,
      ],
      environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
      includeParentEnvironment: true,
    );
    final String output = '${result.stdout}${result.stderr}';
    if (result.exitCode == 0 ||
        !output.contains(
          'effective flags contain unsupported path-bearing token',
        )) {
      throw _FreshnessException(
        'path-bearing flags did not fail closed for $target: '
        'status=${result.exitCode} $output',
      );
    }
  }
}

Future<void> _runBuildExpectingPackageFailure(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig,
) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      'RUNTIME_PACKAGE_CONFIG=$packageConfig',
      'developer-jit-build',
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 || !output.contains('package dart_appkit root')) {
    throw _FreshnessException(
      'forged package root did not fail closed: status=${result.exitCode} '
      '$output',
    );
  }
}

Future<void> _runBuildExpectingMissingOverrideFailure(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig,
) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      'RUNTIME_PACKAGE_CONFIG=$packageConfig',
      'developer-jit-build',
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 ||
      !output.contains('No rule to make target') ||
      await File(packageConfig).exists()) {
    throw _FreshnessException(
      'missing package-config override did not fail as an input: '
      'status=${result.exitCode} $output',
    );
  }
}

Future<void> _verifyInternalOverrideDatabase(
  _Options options,
  String isolatedBuildRoot,
  Map<String, String> overrides,
) async {
  final ProcessResult result = await Process.run(options.make, <String>[
    '-C',
    options.projectRoot,
    '-pn',
    'RUNTIME_ARCH=arm64',
    'RUNTIME_BUILD_DIR=$isolatedBuildRoot',
    for (final MapEntry<String, String> entry in overrides.entries)
      '${entry.key}=${entry.value}',
    'help',
  ]);
  if (result.exitCode != 0) {
    throw _FreshnessException(
      'Make variable database failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
  final List<String> lines = (result.stdout as String).split('\n');
  for (final MapEntry<String, String> entry in overrides.entries) {
    final RegExp definition = RegExp(
      '^${RegExp.escape(entry.key)}\\s*[:+?]?=\\s*(.*)\$',
    );
    final List<RegExpMatch> matches = <RegExpMatch>[
      for (final String line in lines)
        if (definition.firstMatch(line) case final RegExpMatch match) match,
    ];
    if (matches.length != 1 || matches.single.group(1) == entry.value) {
      throw _FreshnessException(
        'internal Make variable accepted hostile override: ${entry.key}',
      );
    }
  }
}

Future<void> _verifyProtectedDryRun(
  _Options options,
  String isolatedBuildRoot,
  String extraInput,
  String packageConfig,
  String dartSdkRoot,
  Map<String, String> overrides,
  List<String> hostileNeedles,
) async {
  final ProcessResult result = await Process.run(options.make, <String>[
    '-C',
    options.projectRoot,
    '-n',
    'RUNTIME_BUILD_DIR=$isolatedBuildRoot',
    'RUNTIME_ARCH=arm64',
    'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
    'RUNTIME_PACKAGE_CONFIG=$packageConfig',
    'DART_SDK_ROOT=$dartSdkRoot',
    for (final MapEntry<String, String> entry in overrides.entries)
      '${entry.key}=${entry.value}',
    'DART_EXECUTABLE=/usr/bin/true',
    'developer-jit-build',
    'release-aot-build',
    'universal-release-aot-assemble',
    'intel-native-runtime-verify',
  ]);
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode != 0) {
    throw _FreshnessException(
      'protected runtime dry-run failed (${result.exitCode}): $output',
    );
  }
  for (final String needle in hostileNeedles) {
    if (output.contains(needle)) {
      throw _FreshnessException(
        'protected runtime dry-run consumed hostile input: $needle',
      );
    }
  }
  for (final String required in <String>[
    '/native/macos/runtime/ReleaseAotRunner.mm',
    '/tool/runtime_build_fingerprint.dart',
    '/tool/runtime_universal_assembler.dart',
    '/tool/runtime_native_handoff.dart',
    '/usr/bin/arch',
  ]) {
    if (!output.contains(required)) {
      throw _FreshnessException(
        'protected runtime dry-run missed canonical input: $required',
      );
    }
  }
}

Future<void> _runBuildExpectingRunnerFailure(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig,
  String runner,
) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      'RUNTIME_PACKAGE_CONFIG=$packageConfig',
      'RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE=$runner',
      'release-aot-build',
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 ||
      !output.contains(
        'snapshotter runner executable does not identify /usr/bin/arch',
      )) {
    throw _FreshnessException(
      'unapproved snapshotter runner did not fail closed: '
      'status=${result.exitCode} $output',
    );
  }
}

Future<void> _runBuildExpectingSdkFailure(
  _Options options,
  String buildRoot,
  String extraInput,
  String packageConfig,
  String fakeSdkRoot,
) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      'RUNTIME_PACKAGE_CONFIG=$packageConfig',
      'DART_EXECUTABLE=$fakeSdkRoot/bin/dart',
      'DART_SDK_ROOT=$fakeSdkRoot',
      'developer-jit-build',
      'release-aot-build',
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 ||
      !output.contains(
        'selected Dart SDK does not identify the trusted bootstrap',
      )) {
    throw _FreshnessException(
      'self-authenticating Dart SDK root did not fail closed: '
      'status=${result.exitCode} $output',
    );
  }
}

Future<void> _verifyBuildToolEvidence(
  String developerFingerprint,
  String releaseFingerprint,
  String dartExecutable,
  String engineGn,
  String engineNinja,
) async {
  final Map<String, String> expectedHashes = <String, String>{
    'dart': await runtimeSha256File(dartExecutable),
    'engine_gn': await runtimeSha256File(engineGn),
    'engine_ninja': await runtimeSha256File(engineNinja),
    'engine_python': await runtimeSha256File('/usr/bin/python3'),
    'make': await runtimeSha256File('/usr/bin/make'),
    'snapshotter_runner': await runtimeSha256File('/usr/bin/arch'),
  };
  for (final MapEntry<String, String> fingerprint in <String, String>{
    'developer': developerFingerprint,
    'release': releaseFingerprint,
  }.entries) {
    final Object? decoded = jsonDecode(
      await File(fingerprint.value).readAsString(),
    );
    if (decoded is! Map<String, Object?> ||
        decoded['lane'] is! Map<String, Object?>) {
      throw _FreshnessException(
        '${fingerprint.key} fingerprint lane is invalid',
      );
    }
    final Map<String, Object?> lane = decoded['lane']! as Map<String, Object?>;
    final Object? toolsValue = lane['build_tools'];
    if (toolsValue is! Map<String, Object?>) {
      throw _FreshnessException(
        '${fingerprint.key} fingerprint lacks build-tool evidence',
      );
    }
    final Set<String> expectedRoles = <String>{
      'dart',
      'engine_gn',
      'engine_ninja',
      'engine_python',
      'make',
      if (fingerprint.key == 'release') 'snapshotter_runner',
    };
    if (!sameStringSet(toolsValue.keys, expectedRoles)) {
      throw _FreshnessException(
        '${fingerprint.key} fingerprint build-tool roles differ',
      );
    }
    for (final String role in expectedRoles) {
      final Object? record = toolsValue[role];
      if (record is! Map<String, Object?> ||
          record['sha256'] != expectedHashes[role] ||
          record['arguments'] is! List<Object?> ||
          (record['arguments']! as List<Object?>).isEmpty) {
        throw _FreshnessException(
          '${fingerprint.key} fingerprint $role evidence differs',
        );
      }
    }
  }
}

Future<Map<String, DateTime>> _modificationTimes(List<String> paths) async {
  final Map<String, DateTime> result = <String, DateTime>{};
  for (final String path in paths) {
    final File file = File(path);
    if (!await file.exists()) {
      throw _FreshnessException('missing derived artifact: $path');
    }
    result[path] = (await file.stat()).modified;
  }
  return result;
}

Future<void> _expectGitSuccess(
  List<String> arguments, {
  required String description,
}) async {
  final ProcessResult result = await Process.run('/usr/bin/git', arguments);
  if (result.exitCode != 0) {
    throw _FreshnessException(
      '$description failed: ${result.stdout}${result.stderr}',
    );
  }
}

Future<void> _verifyEnginePatchCompositionNegative(Directory temporary) async {
  final Directory fixture = Directory('${temporary.path}/engine-fixture');
  final File engine = File('${fixture.path}/runtime/engine/engine.cc');
  await engine.parent.create(recursive: true);
  await engine.writeAsString(
    'void WorkerSupport() {\n'
    '  root();\n'
    '}\n'
    '\n'
    'void Shutdown() {\n'
    '  root();\n'
    '}\n',
    flush: true,
  );
  await _expectGitSuccess(<String>[
    'init',
    '--quiet',
    fixture.path,
  ], description: 'Engine fixture initialization');
  await _expectGitSuccess(<String>[
    '-C',
    fixture.path,
    'add',
    'runtime/engine/engine.cc',
  ], description: 'Engine fixture staging');
  await _expectGitSuccess(<String>[
    '-C',
    fixture.path,
    '-c',
    'user.name=Dart Terminal Test',
    '-c',
    'user.email=dart-terminal-test.invalid',
    'commit',
    '--quiet',
    '-m',
    'base',
  ], description: 'Engine fixture commit');

  final File workerPatch = File('${temporary.path}/worker.patch');
  await workerPatch.writeAsString(
    'diff --git a/runtime/engine/engine.cc b/runtime/engine/engine.cc\n'
    '--- a/runtime/engine/engine.cc\n'
    '+++ b/runtime/engine/engine.cc\n'
    '@@ -1,3 +1,4 @@\n'
    ' void WorkerSupport() {\n'
    '   root();\n'
    '+  workers();\n'
    ' }\n',
    flush: true,
  );
  final File lifecyclePatch = File('${temporary.path}/lifecycle.patch');
  await lifecyclePatch.writeAsString(
    'diff --git a/runtime/engine/engine.cc b/runtime/engine/engine.cc\n'
    '--- a/runtime/engine/engine.cc\n'
    '+++ b/runtime/engine/engine.cc\n'
    '@@ -6,3 +6,4 @@\n'
    ' void Shutdown() {\n'
    '   root();\n'
    '+  cleanup();\n'
    ' }\n',
    flush: true,
  );
  for (final File patch in <File>[workerPatch, lifecyclePatch]) {
    await _expectGitSuccess(<String>[
      '-C',
      fixture.path,
      'apply',
      patch.path,
    ], description: 'Engine fixture patch application');
  }
  await verifyRuntimeEnginePatchComposition(
    engineRoot: fixture.path,
    engineFile: 'runtime/engine/engine.cc',
    patches: <String>[workerPatch.path, lifecyclePatch.path],
  );
  final String exactPatchedContents = await engine.readAsString();
  final String exactPatchedHash = await runtimeSha256File(engine.path);

  await engine.writeAsString(
    '$exactPatchedContents\nvoid UnrelatedHandEdit() {}\n',
    flush: true,
  );
  for (final File patch in <File>[workerPatch, lifecyclePatch]) {
    await _expectGitSuccess(<String>[
      '-C',
      fixture.path,
      'apply',
      '--reverse',
      '--check',
      patch.path,
    ], description: 'Engine fixture reverse check with extra edit');
  }
  var rejected = false;
  try {
    await verifyRuntimeEnginePatchComposition(
      engineRoot: fixture.path,
      engineFile: 'runtime/engine/engine.cc',
      patches: <String>[workerPatch.path, lifecyclePatch.path],
    );
  } on RuntimeAuditException catch (error) {
    rejected = error.message.contains('does not exactly match');
  }
  if (!rejected) {
    throw const _FreshnessException(
      'non-overlapping Engine hand edit was not rejected',
    );
  }
  stdout.writeln('RUNTIME_BUILD_FRESHNESS_PASS extra_engine_edit_rejected=1');

  await engine.writeAsString(exactPatchedContents, flush: true);
  final ProcessResult chmod = await Process.run('/bin/chmod', <String>[
    '755',
    engine.path,
  ]);
  if (chmod.exitCode != 0) {
    throw _FreshnessException(
      'could not create Engine mode-only edit: ${chmod.stderr}',
    );
  }
  if (await runtimeSha256File(engine.path) != exactPatchedHash) {
    throw const _FreshnessException(
      'Engine mode-only fixture unexpectedly changed file contents',
    );
  }
  for (final File patch in <File>[workerPatch, lifecyclePatch]) {
    await _expectGitSuccess(<String>[
      '-C',
      fixture.path,
      'apply',
      '--reverse',
      '--check',
      patch.path,
    ], description: 'Engine fixture reverse check with mode-only edit');
  }
  rejected = false;
  try {
    await verifyRuntimeEnginePatchComposition(
      engineRoot: fixture.path,
      engineFile: 'runtime/engine/engine.cc',
      patches: <String>[workerPatch.path, lifecyclePatch.path],
    );
  } on RuntimeAuditException catch (error) {
    rejected = error.message.contains('does not exactly match');
  }
  if (!rejected) {
    throw const _FreshnessException(
      'mode-only Engine hand edit was not rejected',
    );
  }
  stdout.writeln('RUNTIME_BUILD_FRESHNESS_PASS engine_mode_edit_rejected=1');
}

Future<String> _runDeveloperTarget(
  _Options options,
  String buildRoot,
  String target, {
  String? extraInput,
}) async {
  final ProcessResult result = await Process.run(
    options.make,
    <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_BUILD_DIR=$buildRoot',
      'RUNTIME_ARCH=arm64',
      if (extraInput != null) 'RUNTIME_EXTRA_BUILD_INPUT=$extraInput',
      target,
    ],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode != 0) {
    throw _FreshnessException(
      'Developer target $target failed (${result.exitCode}): $output',
    );
  }
  for (final String forbidden in <String>[
    'dart-engine-worker-isolates.patch',
    'dart-engine-lifecycle-shutdown.patch',
    'dart-engine-worker-support',
    'dart-engine-lifecycle-support',
  ]) {
    if (output.contains(forbidden)) {
      throw _FreshnessException(
        'Developer target $target reached legacy patch activity: $forbidden',
      );
    }
  }
  return output;
}

Future<String> _gitOutput(String root, List<String> arguments) async {
  final ProcessResult result = await Process.run('/usr/bin/git', <String>[
    '-C',
    root,
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw _FreshnessException(
      'git ${arguments.join(' ')} failed in $root: '
      '${result.stdout}${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<void> _verifyCleanRepository(
  String root,
  String expectedRevision,
) async {
  final String revision = await _gitOutput(root, const <String>[
    'rev-parse',
    'HEAD',
  ]);
  final String status = await _gitOutput(root, const <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (revision != expectedRevision || status.isNotEmpty) {
    throw _FreshnessException(
      'repository is not the expected clean revision: root=$root '
      'revision=$revision expected=$expectedRevision status=$status',
    );
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> parent, String key) =>
    runtimeStringMap(parent[key], 'Developer manifest $key');

Future<Map<String, Object?>> _readDeveloperManifest(String manifestPath) async {
  final Object? decoded = jsonDecode(await File(manifestPath).readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const _FreshnessException('Developer manifest is not an object');
  }
  if (decoded['format'] != runtimeBuildManifestFormat ||
      decoded['version'] != runtimeBuildManifestVersion ||
      decoded['runtime_mode'] != RuntimeMode.developerJit.name ||
      decoded['architecture'] != 'arm64') {
    throw const _FreshnessException(
      'Developer manifest identity does not match the focused gate',
    );
  }
  return decoded;
}

Future<String> _verifyDeveloperManifest(
  String manifestPath,
  String workerKernelPath,
) async {
  final Map<String, Object?> manifest = await _readDeveloperManifest(
    manifestPath,
  );
  final Map<String, Object?> engine = _requiredMap(manifest, 'dart_engine');
  final Map<String, Object?> engineRepository = runtimeStringMap(
    engine['repository'],
    'Developer manifest dart_engine.repository',
  );
  if (engine['source_policy'] != 'official-clean' ||
      engine.containsKey('worker_patch_sha256') ||
      engine.containsKey('lifecycle_patch_sha256') ||
      engineRepository['dirty'] != false) {
    throw const _FreshnessException(
      'Developer manifest does not enforce a clean official Engine',
    );
  }

  final Map<String, Object?> source = _requiredMap(manifest, 'source');
  final Map<String, Object?> sourceHashes = runtimeStringMap(
    source['input_sha256'],
    'Developer manifest source.input_sha256',
  );
  if (sourceHashes.keys.any(
    (String input) => input.startsWith('dart_terminal:patches/'),
  )) {
    throw const _FreshnessException(
      'Developer manifest retains a patch provenance input',
    );
  }

  final Map<String, Object?> effective = _requiredMap(
    manifest,
    'effective_configuration',
  );
  if (effective['worker_topology'] != 'official-dart-child-process' ||
      effective['worker_protocol_version'] != 1 ||
      effective['worker_payload_name'] != runtimeDeveloperWorkerPayloadName ||
      effective['worker_kernel_flags'] !=
          '--link-platform --no-embed-sources --verbosity=warning') {
    throw const _FreshnessException(
      'Developer worker configuration differs from the selected contract',
    );
  }

  final Map<String, Object?> lane = _requiredMap(
    manifest,
    'architecture_inputs',
  );
  final Map<String, Object?> inputPaths = runtimeStringMap(
    lane['resolved_input_paths'],
    'Developer manifest architecture_inputs.resolved_input_paths',
  );
  final Map<String, Object?> inputHashes = runtimeStringMap(
    lane['input_binary_sha256'],
    'Developer manifest architecture_inputs.input_binary_sha256',
  );
  final Map<String, Object?> produced = runtimeStringMap(
    lane['produced_sha256'],
    'Developer manifest architecture_inputs.produced_sha256',
  );
  final Object? workerDartValue = inputPaths['runtime_worker_dart'];
  if (workerDartValue is! String || !File(workerDartValue).isAbsolute) {
    throw const _FreshnessException(
      'Developer manifest lacks an absolute runtime worker executable',
    );
  }
  final String workerDart = await File(workerDartValue).resolveSymbolicLinks();
  if (inputHashes['runtime_worker_dart'] !=
          await runtimeSha256File(workerDart) ||
      produced['worker_kernel_payload'] !=
          await runtimeSha256File(workerKernelPath)) {
    throw const _FreshnessException(
      'Developer worker executable or Kernel hash evidence differs',
    );
  }
  return workerDart;
}

Future<void> _verifyEngineAttestation(Map<String, Object?> manifest) async {
  final Map<String, Object?> lane = _requiredMap(
    manifest,
    'architecture_inputs',
  );
  final Map<String, Object?> environment = runtimeStringMap(
    lane['build_environment'],
    'Developer manifest architecture_inputs.build_environment',
  );
  final Map<String, Object?> environmentPaths = runtimeStringMap(
    environment['resolved_paths'],
    'Developer manifest build_environment.resolved_paths',
  );
  final String engineRoot = runtimeRequiredString(
    environmentPaths,
    'dart_engine_root',
    'Developer manifest build_environment.resolved_paths',
  );
  final String revision = runtimeRequiredString(
    _requiredMap(manifest, 'dart_engine'),
    'revision',
    'Developer manifest dart_engine',
  );
  await _verifyCleanRepository(engineRoot, revision);

  final Map<String, Object?> inputPaths = runtimeStringMap(
    lane['resolved_input_paths'],
    'Developer manifest architecture_inputs.resolved_input_paths',
  );
  final Map<String, Object?> inputHashes = runtimeStringMap(
    lane['input_binary_sha256'],
    'Developer manifest architecture_inputs.input_binary_sha256',
  );
  final File attestation = File(
    '${File(runtimeRequiredString(inputPaths, 'dart_engine', 'Developer lane')).parent.path}'
    '/.dart-terminal-official-engine.json',
  );
  final Object? decoded = jsonDecode(await attestation.readAsString());
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != 'dart-terminal-official-engine-attestation' ||
      decoded['version'] != 1 ||
      decoded['source_policy'] != 'official-clean' ||
      decoded['revision'] != revision) {
    throw const _FreshnessException('official Engine attestation is invalid');
  }
  final Map<String, Object?> artifacts = runtimeStringMap(
    decoded['artifacts'],
    'official Engine attestation artifacts',
  );
  for (final String role in <String>[
    'dart_engine',
    'kernel_compiler',
    'platform_dill',
  ]) {
    final Map<String, Object?> artifact = runtimeStringMap(
      artifacts[role],
      'official Engine attestation $role',
    );
    if (artifact['path'] != inputPaths[role] ||
        artifact['sha256'] != inputHashes[role] ||
        artifact['sha256'] !=
            await runtimeSha256File(inputPaths[role]! as String)) {
      throw _FreshnessException(
        'official Engine attestation differs for $role',
      );
    }
  }
}

Future<void> _verifyBundledWorker(
  String workerDart,
  String workerKernel,
) async {
  final List<RuntimeLifecycleObservation> observations =
      <RuntimeLifecycleObservation>[];
  final RuntimeLifecycleCoordinator coordinator = RuntimeLifecycleCoordinator(
    scenario: RuntimeLifecycleScenario.normal,
    observer: observations.add,
    workerCommand: RuntimeLifecycleWorkerCommand(
      executable: workerDart,
      arguments: <String>[workerKernel],
    ),
  );
  final RuntimeLifecycleStartStatus start = await coordinator.start();
  if (start != RuntimeLifecycleStartStatus.ready ||
      coordinator.workerPid == null ||
      coordinator.workerPid == pid) {
    throw const _FreshnessException(
      'bundled Developer worker did not become ready in a child process',
    );
  }
  final RuntimeLifecycleRequestResult reply = await coordinator.request(41);
  final RuntimeLifecycleShutdownResult shutdown = await coordinator.shutdown();
  if (reply.status != RuntimeLifecycleRequestStatus.response ||
      reply.value != 42 ||
      shutdown.termination != RuntimeLifecycleWorkerTermination.graceful ||
      RuntimeLifecycleCoordinator.outstandingProcessCount != 0 ||
      !observations.any(
        (RuntimeLifecycleObservation value) => value.event == 'worker-exit',
      )) {
    throw const _FreshnessException(
      'bundled Developer worker lifecycle contract failed',
    );
  }
}

Future<void> _verifyHostOwnedWorkerArguments(
  Map<String, Object?> manifest,
  String bundlePath,
) async {
  final Map<String, Object?> bundle = _requiredMap(manifest, 'bundle');
  final Map<String, Object?> sdk = _requiredMap(manifest, 'dart_sdk');
  final String executable =
      '$bundlePath/Contents/MacOS/${bundle['executable']}';
  final ProcessResult result = await Process.run(executable, <String>[
    '--kernel',
    '$bundlePath/Contents/Resources/application.dill',
    '--sdk-version',
    sdk['version']! as String,
    '--sdk-revision',
    sdk['revision']! as String,
    '--',
    '--runtime-worker-executable=/usr/bin/false',
  ]);
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode != 66 ||
      !output.contains('runtime worker configuration is host-owned')) {
    throw _FreshnessException(
      'Developer launcher accepted a user worker override: '
      'status=${result.exitCode} $output',
    );
  }
}

Future<void> _verifyMissingWorkerRejected(
  Directory temporary,
  String bundlePath,
) async {
  final String copiedBundle = '${temporary.path}/missing-worker.app';
  final ProcessResult copy = await Process.run('/usr/bin/ditto', <String>[
    '--noqtn',
    bundlePath,
    copiedBundle,
  ]);
  if (copy.exitCode != 0) {
    throw _FreshnessException(
      'could not copy Developer negative fixture: '
      '${copy.stdout}${copy.stderr}',
    );
  }
  await File(
    '$copiedBundle/Contents/Resources/$runtimeDeveloperWorkerPayloadName',
  ).delete();
  var rejected = false;
  try {
    await auditRuntimeBundle(
      RuntimeBundleAuditOptions(
        mode: RuntimeMode.developerJit,
        expectedArchitectures: const <String>{'arm64'},
        deploymentTarget: '14.0',
        bundlePath: copiedBundle,
      ),
    );
  } on RuntimeAuditException catch (error) {
    rejected = error.message.contains(
      'missing runtime file: Resources/$runtimeDeveloperWorkerPayloadName',
    );
  }
  if (!rejected) {
    throw const _FreshnessException(
      'Developer audit accepted a missing worker Kernel',
    );
  }
}

Future<void> _verifyDeveloperDependencyBoundary(
  _Options options,
  String buildRoot,
) async {
  final ProcessResult database = await Process.run(options.make, <String>[
    '-C',
    options.projectRoot,
    '-pn',
    'RUNTIME_ARCH=arm64',
    'RUNTIME_BUILD_DIR=$buildRoot',
    'help',
  ]);
  if (database.exitCode != 0) {
    throw _FreshnessException(
      'could not inspect Developer dependency graph: '
      '${database.stdout}${database.stderr}',
    );
  }
  final List<String> lines = (database.stdout as String).split('\n');
  final List<String> jitRules = lines
      .where((String line) => line.startsWith('runtime-jit-engine:'))
      .toList();
  final List<String> fingerprintRules = lines
      .where(
        (String line) =>
            line.contains('/developer-jit/.effective-build-inputs.json:'),
      )
      .toList();
  if (jitRules.length != 1 ||
      !jitRules.single.contains('unmodified-engine-sdk-clean') ||
      jitRules.single.contains('dart-engine-lifecycle-support') ||
      jitRules.single.contains('dart-engine-worker-support') ||
      fingerprintRules.length != 1 ||
      !fingerprintRules.single.contains('| runtime-jit-engine ')) {
    throw _FreshnessException(
      'Developer dependency graph does not terminate at the clean SDK gate: '
      'jit=$jitRules fingerprint=$fingerprintRules',
    );
  }
}

Future<void> _verifyDeveloperCleanSdk(
  _Options options,
  Directory temporary,
) async {
  final String buildRoot = '${temporary.path}/developer-runtime';
  final File extraInput = File('${temporary.path}/developer-input.txt');
  await extraInput.writeAsString('developer-input-a\n', flush: true);
  await _verifyDeveloperDependencyBoundary(options, buildRoot);

  await _runDeveloperTarget(
    options,
    buildRoot,
    'developer-jit-build',
    extraInput: extraInput.path,
  );
  final String buildDirectory = '$buildRoot/arm64/developer-jit';
  final String manifestPath = '$buildDirectory/runtime-build-manifest.json';
  final String workerKernelPath = '$buildDirectory/runtime_worker.dill';
  final String bundlePath = '$buildDirectory/DartTerminalDeveloper.app';
  final String bundledWorker =
      '$bundlePath/Contents/Resources/$runtimeDeveloperWorkerPayloadName';
  Map<String, Object?> manifest = await _readDeveloperManifest(manifestPath);
  final String workerDart = await _verifyDeveloperManifest(
    manifestPath,
    workerKernelPath,
  );
  await _verifyEngineAttestation(manifest);
  await _runDeveloperTarget(
    options,
    buildRoot,
    'developer-jit-audit',
    extraInput: extraInput.path,
  );
  await _verifyBundledWorker(workerDart, bundledWorker);
  await _verifyHostOwnedWorkerArguments(manifest, bundlePath);
  await _verifyMissingWorkerRejected(temporary, bundlePath);

  final List<String> derived = <String>[
    '$buildDirectory/.effective-build-inputs.json',
    '$buildDirectory/dart_terminal_developer_jit',
    '$buildDirectory/application.dill',
    workerKernelPath,
    manifestPath,
    '$bundlePath/Contents/MacOS/dart_terminal_developer_jit',
    '$bundlePath/Contents/Resources/application.dill',
    bundledWorker,
    '$bundlePath/Contents/Resources/runtime-build-manifest.json',
  ];
  final Map<String, DateTime> first = await _modificationTimes(derived);
  await _runDeveloperTarget(
    options,
    buildRoot,
    'developer-jit-build',
    extraInput: extraInput.path,
  );
  final Map<String, DateTime> second = await _modificationTimes(derived);
  for (final String path in derived) {
    if (second[path] != first[path]) {
      throw _FreshnessException(
        'unchanged Developer input rewrote derived artifact: $path',
      );
    }
  }

  await extraInput.writeAsString('developer-input-b\n', flush: true);
  await _runDeveloperTarget(
    options,
    buildRoot,
    'developer-jit-build',
    extraInput: extraInput.path,
  );
  final Map<String, DateTime> third = await _modificationTimes(derived);
  for (final String path in derived) {
    if (!third[path]!.isAfter(second[path]!)) {
      throw _FreshnessException(
        'changed Developer input did not regenerate artifact: $path',
      );
    }
  }
  manifest = await _readDeveloperManifest(manifestPath);
  await _verifyDeveloperManifest(manifestPath, workerKernelPath);
  await _verifyEngineAttestation(manifest);
  await _runDeveloperTarget(
    options,
    buildRoot,
    'developer-jit-audit',
    extraInput: extraInput.path,
  );

  final Map<String, Object?> environment = runtimeStringMap(
    _requiredMap(manifest, 'architecture_inputs')['build_environment'],
    'Developer manifest architecture_inputs.build_environment',
  );
  final Map<String, Object?> environmentPaths = runtimeStringMap(
    environment['resolved_paths'],
    'Developer manifest build_environment.resolved_paths',
  );
  final String appKitRoot = runtimeRequiredString(
    environmentPaths,
    'dart_appkit_root',
    'Developer manifest build_environment.resolved_paths',
  );
  final String engineRoot = runtimeRequiredString(
    environmentPaths,
    'dart_engine_root',
    'Developer manifest build_environment.resolved_paths',
  );
  final String appKitRevision = runtimeRequiredString(
    runtimeStringMap(
      _requiredMap(manifest, 'dart_appkit')['repository'],
      'Developer manifest dart_appkit.repository',
    ),
    'revision',
    'Developer manifest dart_appkit.repository',
  );
  final String engineRevision = runtimeRequiredString(
    _requiredMap(manifest, 'dart_engine'),
    'revision',
    'Developer manifest dart_engine',
  );
  await _verifyCleanRepository(appKitRoot, appKitRevision);
  await _verifyCleanRepository(engineRoot, engineRevision);
  if (RuntimeLifecycleCoordinator.outstandingProcessCount != 0) {
    throw const _FreshnessException(
      'focused Developer gate leaked a worker process',
    );
  }
  stdout.writeln(
    'RUNTIME_BUILD_FRESHNESS_PASS '
    'developer_clean_sdk=1 patch_activity=0 worker_kernel=1 '
    'worker_smoke=1 missing_worker_rejected=1 host_override_rejected=1 '
    'stable_noop=${derived.length} regenerated=${derived.length}',
  );
}

Future<void> _runTest(_Options options) async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-runtime-freshness-',
  );
  try {
    if (options.focus == 'engine-patch-composition') {
      await _verifyEnginePatchCompositionNegative(temporary);
      return;
    }
    if (options.focus == 'developer-clean-sdk') {
      await _verifyDeveloperCleanSdk(options, temporary);
      return;
    }
    final String buildRoot = '${temporary.path}/runtime';
    final String selectedSdkRoot = await runtimeCommandStdout(
      '/usr/bin/xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
    );
    final Directory spacedSdkParent = Directory(
      '${temporary.path}/Xcode Beta.app/Contents/Developer/SDKs',
    );
    await spacedSdkParent.create(recursive: true);
    final Link spacedSdkRoot = Link('${spacedSdkParent.path}/MacOSX SDK.sdk');
    await spacedSdkRoot.create(selectedSdkRoot);
    final String selectedClang = await runtimeCommandStdout(
      '/usr/bin/xcrun',
      const <String>['--find', 'clang++'],
    );
    final Directory spacedClangParent = Directory(
      '${temporary.path}/Xcode Beta.app/Contents/Developer/Toolchains/'
      'XcodeDefault.xctoolchain/usr/bin',
    );
    await spacedClangParent.create(recursive: true);
    final Link spacedClang = Link('${spacedClangParent.path}/clang++');
    await spacedClang.create(selectedClang);
    final File seed = File('${temporary.path}/effective-input.txt');
    await seed.writeAsString('seed-a\n', flush: true);
    final File sourcePackageConfig = File(
      '${options.projectRoot}/.dart_tool/package_config.json',
    );
    final Object? decoded = jsonDecode(
      await sourcePackageConfig.readAsString(),
    );
    if (decoded is! Map<String, Object?> ||
        decoded['packages'] is! List<Object?>) {
      throw const _FreshnessException('source package config is invalid');
    }
    final List<Object?> packages = decoded['packages']! as List<Object?>;
    for (final Object? value in packages) {
      if (value is! Map<String, Object?> || value['rootUri'] is! String) {
        throw const _FreshnessException('source package entry is invalid');
      }
      final Uri resolved = sourcePackageConfig.absolute.uri.resolve(
        value['rootUri']! as String,
      );
      value['rootUri'] = resolved.toString();
    }
    decoded['pubCache'] = Directory('${temporary.path}/pub-cache-a').uri
        .toString();
    final File packageConfig = File('${temporary.path}/package_config.json');
    await packageConfig.writeAsString(jsonEncode(decoded), flush: true);
    final Directory protectedBundle = Directory(
      '${temporary.path}/sentinel-bundle.app',
    );
    await protectedBundle.create();
    await File('${protectedBundle.path}/sentinel.txt')
        .writeAsString('bundle-sentinel\n', flush: true);
    final File protectedReceipt = File(
      '${temporary.path}/other-lane-thin-audit.json',
    );
    await protectedReceipt.writeAsString('other-lane-receipt\n', flush: true);
    final File protectedSentinel = File('${temporary.path}/sentinel.txt');
    await protectedSentinel.writeAsString('sentinel\n', flush: true);
    final String protectedBundleBefore = await runtimeSha256Text(
      runtimeCanonicalJsonEncode(await runtimeBundleSeal(protectedBundle.path)),
    );
    final String protectedReceiptBefore = await runtimeSha256File(
      protectedReceipt.path,
    );
    final String protectedSentinelBefore = await runtimeSha256File(
      protectedSentinel.path,
    );
    final String runtimeDart = await File(Platform.resolvedExecutable)
        .resolveSymbolicLinks();
    final String dartSdkRoot = File(runtimeDart).parent.parent.path;
    final String engineRoot = await Directory(
      '${options.projectRoot}/../dart_appkit/.dart_tool/dart-engine/sdk',
    ).resolveSymbolicLinks();
    await _verifyEnginePatchCompositionNegative(temporary);
    final Directory hostileRoot = Directory('${temporary.path}/hostile-inputs');
    await hostileRoot.create();
    final File hostileMarker = File('${hostileRoot.path}/executed.txt');
    final File hostileExecutable = File('${hostileRoot.path}/hostile-tool');
    await hostileExecutable.writeAsString(
      '#!/bin/zsh\nprint hostile >> ${hostileMarker.path}\nexit 97\n',
      flush: true,
    );
    final ProcessResult chmodResult = await Process.run('/bin/chmod', <String>[
      '755',
      hostileExecutable.path,
    ]);
    if (chmodResult.exitCode != 0) {
      throw _FreshnessException(
        'failed to make hostile tool executable: ${chmodResult.stderr}',
      );
    }
    final File hostileDart = File('${hostileRoot.path}/hostile.dart');
    await hostileDart.writeAsString(
      "import 'dart:io';\nvoid main() {\n"
      "  File(${jsonEncode(hostileMarker.path)}).writeAsStringSync('dart');\n"
      '}\n',
      flush: true,
    );
    final File hostileSource = File('${hostileRoot.path}/hostile.mm');
    await hostileSource.writeAsString('#error hostile source consumed\n');
    final File hostileHeader = File('${hostileRoot.path}/hostile.h');
    await hostileHeader.writeAsString('#error hostile header consumed\n');
    final File hostileFile = File('${hostileRoot.path}/hostile.input');
    await hostileFile.writeAsString('hostile input\n', flush: true);
    final File hostilePlist = File('${hostileRoot.path}/hostile.plist');
    await hostilePlist.writeAsString('not a plist\n', flush: true);
    final Map<String, String> internalOverrides = <String, String>{
      'SHELL': '/usr/bin/false',
      'MAKE': '/usr/bin/true',
      'PROJECT_ROOT': hostileRoot.path,
      'HOST_ARCH': 'hostile-host',
      'DART_SDK_VERSION': '0.0.0-hostile',
      'DART_SDK_REVISION': 'hostile-revision',
      'DART_SDK_HASH': 'hostilehash',
      'DART_EXECUTABLE': hostileExecutable.path,
      'DART_ENGINE_RELEASE_ARCH': 'HOSTILE',
      'DART_ENGINE_SHARED_TOOLCHAIN': 'hostile-toolchain',
      'DART_ENGINE_OUT': hostileRoot.path,
      'DART_ENGINE_JIT_OUT': hostileRoot.path,
      'DART_ENGINE_GN': hostileExecutable.path,
      'DART_ENGINE_NINJA': hostileExecutable.path,
      'RUNTIME_ENGINE_PYTHON': hostileExecutable.path,
      'DART_ENGINE_AOT_LIBRARY': hostileExecutable.path,
      'DART_ENGINE_JIT_LIBRARY': hostileExecutable.path,
      'DART_ENGINE_KERNEL_COMPILER': hostileExecutable.path,
      'DART_ENGINE_PLATFORM_KERNEL': hostileFile.path,
      'DART_ENGINE_WORKER_PATCH': hostileFile.path,
      'DART_ENGINE_LIFECYCLE_PATCH': hostileFile.path,
      'RUNTIME_DEFAULT_PACKAGE_CONFIG': hostileFile.path,
      'RUNTIME_DART_EXECUTABLE': hostileExecutable.path,
      'RUNTIME_DART_SOURCES': hostileDart.path,
      'RUNTIME_BRIDGE_HEADERS': hostileHeader.path,
      'RUNTIME_BRIDGE_SOURCES': hostileSource.path,
      'RUNTIME_LIFECYCLE_HEADER': hostileHeader.path,
      'RUNTIME_LIFECYCLE_SOURCE': hostileSource.path,
      'RUNTIME_JIT_MAIN_SOURCE': hostileSource.path,
      'RUNTIME_JIT_RUNNER_HEADERS': hostileHeader.path,
      'RUNTIME_JIT_RUNNER_SOURCES': hostileSource.path,
      'RUNTIME_MESSAGE_PUMP_HEADERS': hostileHeader.path,
      'RUNTIME_MESSAGE_PUMP_SOURCE': hostileSource.path,
      'RUNTIME_AUDIT_SOURCE': hostileDart.path,
      'RUNTIME_FINGERPRINT_SOURCE': hostileDart.path,
      'RUNTIME_ENGINE_ATTESTATION_SOURCE': hostileDart.path,
      'RUNTIME_FRESHNESS_TEST_SOURCE': hostileDart.path,
      'RUNTIME_MANIFEST_SOURCE': hostileDart.path,
      'RUNTIME_RELEASE_SUPPORT_SOURCE': hostileDart.path,
      'RUNTIME_UNIVERSAL_ASSEMBLER_SOURCE': hostileDart.path,
      'RUNTIME_RELEASE_NEGATIVE_SOURCE': hostileDart.path,
      'RUNTIME_NATIVE_HANDOFF_SOURCE': hostileDart.path,
      'RUNTIME_INTEGRATION_SOURCE': hostileDart.path,
      'RUNTIME_EXTRA_BUILD_INPUT_ARGUMENT':
          '--extra-build-input=${hostileFile.path}',
      'RUNTIME_WORKER_KERNEL_FLAGS': '--hostile-worker-kernel-flag',
      'RUNTIME_BUNDLE_VERSION': '9.9.9-hostile',
      'RUNTIME_NATIVE_FLAG_PREFIX': '-DHOSTILE_PREFIX=1',
      'RUNTIME_NATIVE_FLAG_SUFFIX': '-DHOSTILE_SUFFIX=1',
      'RUNTIME_DART_TARGET_ARCH': 'hostile-arch',
      'RUNTIME_ENGINE_ARCH': 'HOSTILE',
      'RUNTIME_ENGINE_TOOLCHAIN': 'hostile-toolchain',
      'RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS': '--hostile',
      'RUNTIME_ENGINE_PRODUCT_OUT': hostileRoot.path,
      'RUNTIME_ENGINE_RELEASE_OUT': hostileRoot.path,
      'RUNTIME_ENGINE_AOT_LIBRARY': hostileExecutable.path,
      'RUNTIME_ENGINE_JIT_LIBRARY': hostileExecutable.path,
      'RUNTIME_ENGINE_KERNEL_COMPILER': hostileExecutable.path,
      'RUNTIME_ENGINE_PLATFORM_KERNEL': hostileFile.path,
      'RUNTIME_ENGINE_JIT_ATTESTATION': hostileFile.path,
      'RUNTIME_ENGINE_AOT_KERNEL_COMPILER': hostileExecutable.path,
      'RUNTIME_ENGINE_AOT_PLATFORM_KERNEL': hostileFile.path,
      'RUNTIME_ENGINE_AOT_SNAPSHOTTER': hostileExecutable.path,
      'DEVELOPER_JIT_BUILD_DIR': protectedBundle.path,
      'DEVELOPER_JIT_RUNNER': protectedSentinel.path,
      'DEVELOPER_JIT_KERNEL': protectedSentinel.path,
      'DEVELOPER_JIT_KERNEL_DEPFILE': protectedSentinel.path,
      'DEVELOPER_JIT_WORKER_KERNEL': protectedSentinel.path,
      'DEVELOPER_JIT_WORKER_KERNEL_DEPFILE': protectedSentinel.path,
      'DEVELOPER_JIT_MANIFEST': protectedSentinel.path,
      'DEVELOPER_JIT_FINGERPRINT': protectedSentinel.path,
      'DEVELOPER_JIT_BUNDLE': protectedBundle.path,
      'DEVELOPER_JIT_EXECUTABLE': protectedSentinel.path,
      'DEVELOPER_JIT_BUNDLED_KERNEL': protectedSentinel.path,
      'DEVELOPER_JIT_BUNDLED_WORKER_KERNEL': protectedSentinel.path,
      'DEVELOPER_JIT_BUNDLE_STAMP': protectedSentinel.path,
      'DEVELOPER_JIT_INFO_PLIST': hostilePlist.path,
      'DEVELOPER_JIT_AUDIT_REPORT': protectedReceipt.path,
      'RELEASE_AOT_BUILD_DIR': protectedBundle.path,
      'RELEASE_AOT_KERNEL': protectedSentinel.path,
      'RELEASE_AOT_KERNEL_DEPFILE': protectedSentinel.path,
      'RELEASE_AOT_SNAPSHOT': protectedSentinel.path,
      'RELEASE_AOT_HOST': protectedSentinel.path,
      'RELEASE_AOT_MANIFEST': protectedSentinel.path,
      'RELEASE_AOT_FINGERPRINT': protectedSentinel.path,
      'RELEASE_AOT_BUNDLE': protectedBundle.path,
      'RELEASE_AOT_EXECUTABLE': protectedSentinel.path,
      'RELEASE_AOT_BUNDLE_STAMP': protectedSentinel.path,
      'RELEASE_AOT_HOST_SOURCE': hostileSource.path,
      'RELEASE_AOT_INFO_PLIST': hostilePlist.path,
      'RELEASE_AOT_AUDIT_REPORT': protectedReceipt.path,
      'UNIVERSAL_RELEASE_BUILD_DIR': protectedBundle.path,
      'UNIVERSAL_RELEASE_BUNDLE': protectedBundle.path,
      'UNIVERSAL_RELEASE_REPORT': protectedReceipt.path,
      'UNIVERSAL_RELEASE_AUDIT_REPORT': protectedReceipt.path,
      'ARM64_RELEASE_BUNDLE': protectedBundle.path,
      'X86_64_RELEASE_BUNDLE': protectedBundle.path,
      'ARM64_RELEASE_AUDIT_REPORT': protectedReceipt.path,
      'X86_64_RELEASE_AUDIT_REPORT': protectedReceipt.path,
    };
    await _verifyInternalOverrideDatabase(
      options,
      '${temporary.path}/database-runtime',
      internalOverrides,
    );
    await _verifyProtectedDryRun(
      options,
      '${temporary.path}/dry-run-runtime',
      seed.path,
      packageConfig.path,
      dartSdkRoot,
      internalOverrides,
      <String>[
        hostileRoot.path,
        protectedBundle.path,
        protectedReceipt.path,
        protectedSentinel.path,
        '/usr/bin/true',
        '/usr/bin/false',
      ],
    );
    await _runBuild(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      sdkRoot: spacedSdkRoot.path,
      clang: spacedClang.path,
      dartSdkRoot: dartSdkRoot,
      protectedPathOverrides: <String>[
        for (final MapEntry<String, String> entry in internalOverrides.entries)
          '${entry.key}=${entry.value}',
        'DART_EXECUTABLE=/usr/bin/true',
      ],
    );
    if (await runtimeSha256Text(
              runtimeCanonicalJsonEncode(
                await runtimeBundleSeal(protectedBundle.path),
              ),
            ) !=
            protectedBundleBefore ||
        await runtimeSha256File(protectedReceipt.path) !=
            protectedReceiptBefore ||
        await runtimeSha256File(protectedSentinel.path) !=
            protectedSentinelBefore) {
      throw const _FreshnessException(
        'Make command-line path override changed a protected sentinel',
      );
    }
    if (await hostileMarker.exists()) {
      throw const _FreshnessException(
        'hostile Make tool override was executed',
      );
    }
    final List<String> derived = <String>[
      '$buildRoot/arm64/developer-jit/.effective-build-inputs.json',
      '$buildRoot/arm64/developer-jit/dart_terminal_developer_jit',
      '$buildRoot/arm64/developer-jit/application.dill',
      '$buildRoot/arm64/developer-jit/runtime-build-manifest.json',
      '$buildRoot/arm64/release-aot/.effective-build-inputs.json',
      '$buildRoot/arm64/release-aot/dart_terminal_release_aot',
      '$buildRoot/arm64/release-aot/application.aot.dill',
      '$buildRoot/arm64/release-aot/application.aot',
      '$buildRoot/arm64/release-aot/runtime-build-manifest.json',
    ];
    final List<String> produced = <String>[
      '$buildRoot/arm64/developer-jit/dart_terminal_developer_jit',
      '$buildRoot/arm64/developer-jit/application.dill',
      '$buildRoot/arm64/release-aot/dart_terminal_release_aot',
      '$buildRoot/arm64/release-aot/application.aot.dill',
      '$buildRoot/arm64/release-aot/application.aot',
    ];
    final Map<String, String> hostileBuildHashes = <String, String>{
      for (final String path in produced) path: await runtimeSha256File(path),
    };
    await _runBuild(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      sdkRoot: spacedSdkRoot.path,
      clang: spacedClang.path,
      dartSdkRoot: dartSdkRoot,
      forceRebuild: true,
    );
    for (final MapEntry<String, String> entry in hostileBuildHashes.entries) {
      if (await runtimeSha256File(entry.key) != entry.value) {
        throw _FreshnessException(
          'hostile internal override changed product output: ${entry.key}',
        );
      }
    }
    await _verifyBuildToolEvidence(
      derived[0],
      derived[4],
      runtimeDart,
      '$engineRoot/tools/gn.py',
      '$engineRoot/buildtools/ninja/ninja',
    );
    final Map<String, String> artifactsBeforeRunnerChecks = <String, String>{
      for (final String path in derived) path: await runtimeSha256File(path),
    };
    final Link approvedSdkAlias = Link(
      '${hostileRoot.path}/approved-sdk-alias',
    );
    await approvedSdkAlias.create(dartSdkRoot);
    await _runBuild(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      dartSdkRoot: approvedSdkAlias.path,
    );
    final Directory fakeSdkRoot = Directory('${hostileRoot.path}/fake-sdk');
    await Directory('${fakeSdkRoot.path}/bin').create(recursive: true);
    final String selectedSdkVersion = (await File(
      '$dartSdkRoot/version',
    ).readAsString()).trim();
    await File('$dartSdkRoot/version').copy('${fakeSdkRoot.path}/version');
    await File('$dartSdkRoot/revision').copy('${fakeSdkRoot.path}/revision');
    final File fakeSdkMarker = File('${hostileRoot.path}/fake-sdk-executed');
    final File fakeSdkDart = File('${fakeSdkRoot.path}/bin/dart');
    await fakeSdkDart.writeAsString(
      '#!/bin/zsh\n'
      'if [[ "\$1" == "--version" ]]; then\n'
      '  print -u2 "Dart SDK version: $selectedSdkVersion forged"\n'
      '  exit 0\n'
      'fi\n'
      'print executed >> ${fakeSdkMarker.path}\n'
      'exit 0\n',
      flush: true,
    );
    await Process.run('/bin/chmod', <String>['755', fakeSdkDart.path]);
    await _runBuildExpectingSdkFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      fakeSdkRoot.path,
    );
    if (await fakeSdkMarker.exists()) {
      throw const _FreshnessException(
        'untrusted Dart SDK executable reached a runtime recipe',
      );
    }
    final Link approvedRunnerAlias = Link(
      '${hostileRoot.path}/approved-arch-alias',
    );
    await approvedRunnerAlias.create('/usr/bin/arch');
    await _runBuild(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      dartSdkRoot: dartSdkRoot,
      protectedPathOverrides: <String>[
        'RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE=${approvedRunnerAlias.path}',
      ],
    );
    final File rejectedRunner = File('${hostileRoot.path}/runner-under-test');
    await rejectedRunner.writeAsString(
      '#!/bin/zsh\nexec /usr/bin/arch "\$@"\n',
      flush: true,
    );
    await Process.run('/bin/chmod', <String>['755', rejectedRunner.path]);
    await _runBuildExpectingRunnerFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      rejectedRunner.path,
    );
    await rejectedRunner.writeAsString(
      '#!/bin/zsh\n# changed content\nexec /usr/bin/arch "\$@"\n',
      flush: true,
    );
    await _runBuildExpectingRunnerFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      rejectedRunner.path,
    );
    for (final MapEntry<String, String> entry
        in artifactsBeforeRunnerChecks.entries) {
      if (await runtimeSha256File(entry.key) != entry.value) {
        throw _FreshnessException(
          'runner identity check changed existing artifact: ${entry.key}',
        );
      }
    }
    stdout.writeln(
      'RUNTIME_BUILD_FRESHNESS_PASS '
      'make_internal_overrides_ignored=${internalOverrides.length} '
      'dry_run_consumed_hostile=0 dart_true_bypass=0 '
      'sdk_alias_accepted=1 self_authenticating_sdk_rejected=1 '
      'runner_alias_accepted=1 runner_replacements_rejected=2 '
      'tool_evidence_verified=6',
    );
    final Map<String, DateTime> first = await _modificationTimes(derived);
    stdout.writeln(
      'RUNTIME_BUILD_FRESHNESS_PASS '
      'space_containing_toolchain_paths_built=${derived.length}',
    );
    final String firstJitFingerprint = await runtimeSha256File(derived[0]);
    final String firstAotFingerprint = await runtimeSha256File(derived[4]);

    await seed.writeAsString('seed-b\n', flush: true);
    await _runBuild(options, buildRoot, seed.path, packageConfig.path);
    final Map<String, DateTime> second = await _modificationTimes(derived);
    final String secondJitFingerprint = await runtimeSha256File(derived[0]);
    final String secondAotFingerprint = await runtimeSha256File(derived[4]);
    if (firstJitFingerprint == secondJitFingerprint ||
        firstAotFingerprint == secondAotFingerprint) {
      throw const _FreshnessException(
        'changed effective input did not change both fingerprints',
      );
    }
    for (final String path in derived) {
      if (!second[path]!.isAfter(first[path]!)) {
        throw _FreshnessException(
          'changed effective input did not regenerate artifact: $path',
        );
      }
    }

    await _runBuild(options, buildRoot, seed.path, packageConfig.path);
    final Map<String, DateTime> third = await _modificationTimes(derived);
    for (final String path in derived) {
      if (third[path] != second[path]) {
        throw _FreshnessException(
          'unchanged fingerprint unexpectedly rewrote artifact: $path',
        );
      }
    }

    decoded['pubCache'] = Directory('${temporary.path}/pub-cache-b').uri
        .toString();
    await packageConfig.writeAsString(jsonEncode(decoded), flush: true);
    await _runBuild(options, buildRoot, seed.path, packageConfig.path);
    final Map<String, DateTime> fourth = await _modificationTimes(derived);
    final String fourthJitFingerprint = await runtimeSha256File(derived[0]);
    final String fourthAotFingerprint = await runtimeSha256File(derived[4]);
    if (secondJitFingerprint == fourthJitFingerprint ||
        secondAotFingerprint == fourthAotFingerprint) {
      throw const _FreshnessException(
        'changed package config did not change both fingerprints',
      );
    }
    for (final String path in derived) {
      if (!fourth[path]!.isAfter(third[path]!)) {
        throw _FreshnessException(
          'changed package config did not regenerate artifact: $path',
        );
      }
    }

    await _runBuild(options, buildRoot, seed.path, packageConfig.path);
    final Map<String, DateTime> fifth = await _modificationTimes(derived);
    for (final String path in derived) {
      if (fifth[path] != fourth[path]) {
        throw _FreshnessException(
          'unchanged package config unexpectedly rewrote artifact: $path',
        );
      }
    }
    final Map<String, String> artifactsBeforeRejectedFlags = <String, String>{
      for (final String path in derived) path: await runtimeSha256File(path),
    };
    final File forcedHeader = File('${temporary.path}/forced-header.h');
    await forcedHeader.writeAsString('#define EXTERNAL_VALUE 1\n', flush: true);
    await _runBuildExpectingFlagFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      '-include ${forcedHeader.path}',
    );
    await forcedHeader.writeAsString('#define EXTERNAL_VALUE 2\n', flush: true);
    await _runBuildExpectingFlagFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      '-include ${forcedHeader.path}',
    );
    final File responseFile = File('${temporary.path}/compiler.rsp');
    await responseFile.writeAsString('-DEXTERNAL_VALUE=1\n', flush: true);
    await _runBuildExpectingFlagFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      '@${responseFile.path}',
    );
    await responseFile.writeAsString('-DEXTERNAL_VALUE=2\n', flush: true);
    await _runBuildExpectingFlagFailure(
      options,
      buildRoot,
      seed.path,
      packageConfig.path,
      '@${responseFile.path}',
    );
    final String relativeStem =
        '.runtime-freshness-$pid-${DateTime.now().microsecondsSinceEpoch}';
    final File relativeHeader = File('${options.projectRoot}/$relativeStem.h');
    final File relativeConfig = File(
      '${options.projectRoot}/$relativeStem.cfg',
    );
    final File relativeProfile = File(
      '${options.projectRoot}/$relativeStem.prof',
    );
    final Directory relativeInclude = Directory(
      '${options.projectRoot}/$relativeStem-include',
    );
    final List<String> relativeFlags = <String>[
      '-Wp,-include,$relativeStem.h',
      '-Wa,-I,$relativeStem-include',
      '-Xassembler=-I$relativeStem-include',
      '--config=$relativeStem.cfg',
      '-fprofile-sample-use=$relativeStem.prof',
    ];
    try {
      await relativeHeader.writeAsString(
        '#define EXTERNAL_VALUE 1\n',
        flush: true,
      );
      await relativeConfig.writeAsString('-DEXTERNAL_VALUE=1\n', flush: true);
      await relativeProfile.writeAsString('profile-version-1\n', flush: true);
      await relativeInclude.create();
      await File('${relativeInclude.path}/external.inc')
          .writeAsString('include-version-1\n', flush: true);
      for (final String flags in relativeFlags) {
        await _runBuildExpectingFlagFailure(
          options,
          buildRoot,
          seed.path,
          packageConfig.path,
          flags,
        );
      }
      await relativeHeader.writeAsString(
        '#define EXTERNAL_VALUE 2\n',
        flush: true,
      );
      await relativeConfig.writeAsString('-DEXTERNAL_VALUE=2\n', flush: true);
      await relativeProfile.writeAsString('profile-version-2\n', flush: true);
      await File('${relativeInclude.path}/external.inc')
          .writeAsString('include-version-2\n', flush: true);
      for (final String flags in relativeFlags) {
        await _runBuildExpectingFlagFailure(
          options,
          buildRoot,
          seed.path,
          packageConfig.path,
          flags,
        );
      }
    } finally {
      for (final File file in <File>[
        relativeHeader,
        relativeConfig,
        relativeProfile,
      ]) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (await relativeInclude.exists()) {
        await relativeInclude.delete(recursive: true);
      }
    }
    for (final MapEntry<String, String> entry
        in artifactsBeforeRejectedFlags.entries) {
      if (await runtimeSha256File(entry.key) != entry.value) {
        throw _FreshnessException(
          'rejected path-bearing input changed existing artifact: '
          '${entry.key}',
        );
      }
    }
    stdout.writeln(
      'RUNTIME_BUILD_FRESHNESS_PASS '
      'external_header_response_and_forwarding_rejected=28 '
      'stale_artifacts_reused=0',
    );
    stdout.writeln(
      'RUNTIME_BUILD_FRESHNESS_PASS '
      'effective_input_regenerated=${derived.length} '
      'package_config_regenerated=${derived.length} '
      'stable_noop=${derived.length}',
    );
    final Object? forgedDecoded = jsonDecode(jsonEncode(decoded));
    if (forgedDecoded is! Map<String, Object?> ||
        forgedDecoded['packages'] is! List<Object?>) {
      throw const _FreshnessException('forged package fixture is invalid');
    }
    final String alternateAppKitRoot =
        '${temporary.path}/alternate-dart_appkit';
    final ProcessResult copyResult = await Process.run(
      '/usr/bin/ditto',
      <String>[
        '--noqtn',
        '${options.projectRoot}/../dart_appkit/packages/dart_appkit',
        alternateAppKitRoot,
      ],
    );
    if (copyResult.exitCode != 0) {
      throw _FreshnessException(
        'failed to create alternate package root fixture: '
        '${copyResult.stdout}${copyResult.stderr}',
      );
    }
    for (final Object? value in forgedDecoded['packages']! as List<Object?>) {
      if (value is Map<String, Object?> && value['name'] == 'dart_appkit') {
        value['rootUri'] = Directory(alternateAppKitRoot).uri.toString();
      }
    }
    final File forged = File('${temporary.path}/forged_package_config.json');
    await forged.writeAsString(jsonEncode(forgedDecoded), flush: true);
    await _runBuildExpectingPackageFailure(
      options,
      '${temporary.path}/forged-runtime',
      seed.path,
      forged.path,
    );
    stdout.writeln(
      'RUNTIME_BUILD_FRESHNESS_PASS forged_package_root_rejected=1',
    );
    await _runBuildExpectingMissingOverrideFailure(
      options,
      '${temporary.path}/missing-override-runtime',
      seed.path,
      '${temporary.path}/missing/package_config.json',
    );
    stdout.writeln('RUNTIME_BUILD_FRESHNESS_PASS missing_override_rejected=1');
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> main(List<String> arguments) async {
  try {
    await _runTest(_parseOptions(arguments));
  } on Object catch (error) {
    stderr.writeln('RUNTIME_BUILD_FRESHNESS_FAIL $error');
    exitCode = 1;
  }
}
