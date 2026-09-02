import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/src/runtime_worker_protocol.dart';

import 'src/runtime_release_support.dart';

final class _FingerprintException implements Exception {
  const _FingerprintException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.mode,
    required this.architecture,
    required this.deploymentTarget,
    required this.bundleVersion,
    required this.projectRoot,
    required this.dartAppKitRoot,
    required this.dartEngineRoot,
    required this.dartSdkRoot,
    required this.dartExecutable,
    required this.engineGnScript,
    required this.engineNinja,
    required this.enginePython,
    required this.makeExecutable,
    required this.runtimeBuildRoot,
    required this.packageConfig,
    required this.engineLibrary,
    required this.kernelCompiler,
    required this.platformDill,
    required this.snapshotter,
    required this.snapshotterRunnerExecutable,
    required this.snapshotterRunnerArguments,
    required this.clang,
    required this.sdkRoot,
    required this.nativeFlags,
    required this.kernelFlags,
    required this.workerKernelFlags,
    required this.workerExecutableFlags,
    required this.snapshotFlags,
    required this.extraBuildInput,
    required this.output,
  });

  final RuntimeMode mode;
  final String architecture;
  final String deploymentTarget;
  final String bundleVersion;
  final String projectRoot;
  final String dartAppKitRoot;
  final String dartEngineRoot;
  final String dartSdkRoot;
  final String dartExecutable;
  final String engineGnScript;
  final String engineNinja;
  final String enginePython;
  final String makeExecutable;
  final String runtimeBuildRoot;
  final String packageConfig;
  final String engineLibrary;
  final String kernelCompiler;
  final String platformDill;
  final String? snapshotter;
  final String? snapshotterRunnerExecutable;
  final String? snapshotterRunnerArguments;
  final String clang;
  final String sdkRoot;
  final String nativeFlags;
  final String kernelFlags;
  final String? workerKernelFlags;
  final String? workerExecutableFlags;
  final String snapshotFlags;
  final String? extraBuildInput;
  final String output;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _FingerprintException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || values.containsKey(name)) {
      throw _FingerprintException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> expected = <String>{
    'mode',
    'architecture',
    'deployment-target',
    'bundle-version',
    'project-root',
    'dart-appkit-root',
    'dart-engine-root',
    'dart-sdk-root',
    'dart-executable',
    'engine-gn-script',
    'engine-ninja',
    'engine-python',
    'make-executable',
    'runtime-build-root',
    'package-config',
    'engine-library',
    'kernel-compiler',
    'platform-dill',
    'clang',
    'sdk-root',
    'native-flags',
    'kernel-flags',
    'snapshot-flags',
    'output',
  };
  const Set<String> optional = <String>{
    'worker-kernel-flags',
    'worker-executable-flags',
    'snapshotter',
    'snapshotter-runner-executable',
    'snapshotter-runner-arguments',
    'extra-build-input',
  };
  final Set<String> unknown = values.keys.toSet().difference(<String>{
    ...expected,
    ...optional,
  });
  final Set<String> missing = expected.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _FingerprintException(
      'unknown=${unknown.join(',')} missing=${missing.join(',')}',
    );
  }
  final RuntimeMode? mode = runtimeModeByName(values['mode']!);
  if (mode == null) {
    throw const _FingerprintException(
      '--mode must be developer-jit or release-aot',
    );
  }
  final String architecture = values['architecture']!;
  if (!supportedRuntimeArchitectures.contains(architecture)) {
    throw const _FingerprintException('--architecture must be arm64 or x86_64');
  }
  final String? snapshotter = values['snapshotter'];
  final String? snapshotterRunnerExecutable =
      values['snapshotter-runner-executable'];
  final String? snapshotterRunnerArguments =
      values['snapshotter-runner-arguments'];
  if (mode == RuntimeMode.releaseAot &&
      (snapshotter == null ||
          snapshotter.isEmpty ||
          snapshotterRunnerExecutable == null ||
          snapshotterRunnerExecutable.isEmpty ||
          snapshotterRunnerArguments == null ||
          snapshotterRunnerArguments.isEmpty)) {
    throw const _FingerprintException(
      'release-aot requires snapshotter and snapshotter runner identity',
    );
  }
  if (mode == RuntimeMode.developerJit &&
      (snapshotter != null ||
          snapshotterRunnerExecutable != null ||
          snapshotterRunnerArguments != null)) {
    throw const _FingerprintException(
      'developer-jit must not configure a snapshotter runner',
    );
  }
  final String? workerKernelFlags = values['worker-kernel-flags'];
  final String? workerExecutableFlags = values['worker-executable-flags'];
  if (mode == RuntimeMode.developerJit &&
      (workerKernelFlags == null || workerKernelFlags.isEmpty)) {
    throw const _FingerprintException(
      'developer-jit requires worker Kernel flags',
    );
  }
  if (mode == RuntimeMode.releaseAot &&
      (workerExecutableFlags == null || workerExecutableFlags.isEmpty)) {
    throw const _FingerprintException(
      'release-aot requires self-contained worker executable flags',
    );
  }
  if (mode == RuntimeMode.releaseAot && workerKernelFlags != null) {
    throw const _FingerprintException(
      'release-aot must not configure Developer worker Kernel flags',
    );
  }
  if (mode == RuntimeMode.developerJit && workerExecutableFlags != null) {
    throw const _FingerprintException(
      'developer-jit must not configure Release worker executable flags',
    );
  }
  return _Options(
    mode: mode,
    architecture: architecture,
    deploymentTarget: values['deployment-target']!,
    bundleVersion: values['bundle-version']!,
    projectRoot: values['project-root']!,
    dartAppKitRoot: values['dart-appkit-root']!,
    dartEngineRoot: values['dart-engine-root']!,
    dartSdkRoot: values['dart-sdk-root']!,
    dartExecutable: values['dart-executable']!,
    engineGnScript: values['engine-gn-script']!,
    engineNinja: values['engine-ninja']!,
    enginePython: values['engine-python']!,
    makeExecutable: values['make-executable']!,
    runtimeBuildRoot: values['runtime-build-root']!,
    packageConfig: values['package-config']!,
    engineLibrary: values['engine-library']!,
    kernelCompiler: values['kernel-compiler']!,
    platformDill: values['platform-dill']!,
    snapshotter: snapshotter,
    snapshotterRunnerExecutable: snapshotterRunnerExecutable,
    snapshotterRunnerArguments: snapshotterRunnerArguments,
    clang: values['clang']!,
    sdkRoot: values['sdk-root']!,
    nativeFlags: values['native-flags']!,
    kernelFlags: values['kernel-flags']!,
    workerKernelFlags: workerKernelFlags,
    workerExecutableFlags: workerExecutableFlags,
    snapshotFlags: values['snapshot-flags']!,
    extraBuildInput: values['extra-build-input'],
    output: values['output']!,
  );
}

Future<String> _stdout(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw _FingerprintException(
      '${executable.split('/').last} failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<String> _git(String root, List<String> arguments) =>
    _stdout('/usr/bin/git', <String>['-C', root, ...arguments]);

Future<Map<String, Object?>> _repositoryIdentity(
  String root, {
  required String policy,
}) async {
  final String status = await _git(root, <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (policy == 'clean' && status.isNotEmpty) {
    throw _FingerprintException('$root is not clean: $status');
  }
  if (policy == 'engine-lifecycle-patches' &&
      status != 'M runtime/engine/engine.cc') {
    throw _FingerprintException(
      'Dart Engine modifications are not the lifecycle patch set: '
      '${status.isEmpty ? '(none)' : status}',
    );
  }
  final String diff = await _git(root, <String>['diff', '--binary', 'HEAD']);
  return <String, Object?>{
    'revision': await _git(root, <String>['rev-parse', 'HEAD']),
    'dirty': status.isNotEmpty,
    'status_sha256': await runtimeSha256Text(status),
    'diff_sha256': await runtimeSha256Text(diff),
  };
}

Future<Map<String, Object?>> _toolchain(_Options options) async {
  final String selectedClang = await _stdout('/usr/bin/xcrun', const <String>[
    '--find',
    'clang++',
  ]);
  final String selectedSdk = await _stdout('/usr/bin/xcrun', const <String>[
    '--sdk',
    'macosx',
    '--show-sdk-path',
  ]);
  final RuntimePathSnapshot configuredClang = await runtimePathSnapshot(
    options.clang,
  );
  final RuntimePathSnapshot expectedClang = await runtimePathSnapshot(
    selectedClang,
  );
  final RuntimePathSnapshot configuredSdk = await runtimePathSnapshot(
    options.sdkRoot,
  );
  final RuntimePathSnapshot expectedSdk = await runtimePathSnapshot(
    selectedSdk,
  );
  final String configuredDriver = options.clang.split('/').last;
  final String selectedDriver = selectedClang.split('/').last;
  if (configuredDriver != 'clang++' ||
      selectedDriver != 'clang++' ||
      configuredClang.targetIdentity != expectedClang.targetIdentity ||
      configuredSdk.targetIdentity != expectedSdk.targetIdentity) {
    throw const _FingerprintException(
      'configured clang++/SDK do not match the selected Xcode toolchain',
    );
  }
  final List<String> xcode = (await _stdout('/usr/bin/xcodebuild', <String>[
    '-version',
  ])).split('\n');
  if (xcode.length != 2 ||
      !xcode[0].startsWith('Xcode ') ||
      !xcode[1].startsWith('Build version ')) {
    throw _FingerprintException(
      'unexpected xcodebuild version: ${xcode.join(' | ')}',
    );
  }
  final String sdkVersion = await _stdout('/usr/bin/xcrun', <String>[
    '--sdk',
    'macosx',
    '--show-sdk-version',
  ]);
  final String sdkBuildVersion = await _stdout('/usr/bin/xcrun', <String>[
    '--sdk',
    'macosx',
    '--show-sdk-build-version',
  ]);
  final List<String> clangVersion = (await _stdout(options.clang, <String>[
    '--version',
  ])).split('\n');
  if (clangVersion.isEmpty || clangVersion.first.isEmpty) {
    throw const _FingerprintException('clang --version returned no version');
  }
  return <String, Object?>{
    'xcode_version': xcode[0].substring('Xcode '.length),
    'xcode_build_version': xcode[1].substring('Build version '.length),
    'macos_sdk_version': sdkVersion,
    'macos_sdk_build_version': sdkBuildVersion,
    'macos_sdk_settings_sha256': await runtimeSha256File(
      '${options.sdkRoot}/SDKSettings.plist',
    ),
    'clang_version': clangVersion.first,
    'compiler_driver': configuredDriver,
  };
}

Future<RuntimePathSnapshot> _regularToolSnapshot(
  String path,
  String description,
) async {
  final RuntimePathSnapshot snapshot = await runtimePathSnapshot(path);
  if (snapshot.targetType != FileSystemEntityType.file) {
    throw _FingerprintException('$description is not a regular file: $path');
  }
  return snapshot;
}

Future<void> _requireSameToolIdentity(
  String actual,
  String expected,
  String description,
) async {
  final RuntimePathSnapshot actualSnapshot = await _regularToolSnapshot(
    actual,
    description,
  );
  final RuntimePathSnapshot expectedSnapshot = await _regularToolSnapshot(
    expected,
    'expected $description',
  );
  if (actualSnapshot.targetIdentity != expectedSnapshot.targetIdentity) {
    throw _FingerprintException(
      '$description does not identify ${expectedSnapshot.canonicalPath}',
    );
  }
}

Future<Map<String, Object?>> _buildTools(
  _Options options,
  String sdkVersion,
  String sdkRevision,
) async {
  await _requireSameToolIdentity(
    options.dartExecutable,
    '${options.dartSdkRoot}/bin/dart',
    'configured Dart executable',
  );
  await _requireSameToolIdentity(
    options.dartExecutable,
    Platform.resolvedExecutable,
    'running Dart executable',
  );
  if (Platform.version.split(RegExp(r'\s+')).first != sdkVersion) {
    throw _FingerprintException(
      'running Dart version does not match SDK version $sdkVersion',
    );
  }
  await _requireSameToolIdentity(
    options.engineGnScript,
    '${options.dartEngineRoot}/tools/gn.py',
    'Engine GN script',
  );
  await _requireSameToolIdentity(
    options.engineNinja,
    '${options.dartEngineRoot}/buildtools/ninja/ninja',
    'Engine Ninja executable',
  );
  await _requireSameToolIdentity(
    options.enginePython,
    '/usr/bin/python3',
    'Engine Python executable',
  );
  await _requireSameToolIdentity(
    options.makeExecutable,
    '/usr/bin/make',
    'recursive Make executable',
  );
  final String outputMode = options.mode == RuntimeMode.releaseAot
      ? 'Product'
      : 'Release';
  final String outputArchitecture = options.architecture == 'arm64'
      ? 'ARM64'
      : 'X64';
  final String engineArchitecture = options.architecture == 'arm64'
      ? 'arm64'
      : 'x64';
  final String outputDirectory =
      '${options.dartEngineRoot}/xcodebuild/$outputMode$outputArchitecture';
  final Map<String, Object?> tools = <String, Object?>{
    'dart': <String, Object?>{
      'path': (await runtimePathSnapshot(options.dartExecutable)).canonicalPath,
      'sha256': await runtimeSha256File(options.dartExecutable),
      'version': sdkVersion,
      'revision': sdkRevision,
      'architectures': await runtimeArchitectures(options.dartExecutable),
      'arguments': <String>[
        'run',
        '${options.projectRoot}/tool/runtime_build_fingerprint.dart',
      ],
    },
    'engine_gn': <String, Object?>{
      'path': (await runtimePathSnapshot(options.engineGnScript)).canonicalPath,
      'sha256': await runtimeSha256File(options.engineGnScript),
      'arguments': <String>[
        '--mode=${options.mode == RuntimeMode.releaseAot ? 'product' : 'release'}',
        '--arch=$engineArchitecture',
      ],
    },
    'engine_ninja': <String, Object?>{
      'path': (await runtimePathSnapshot(options.engineNinja)).canonicalPath,
      'sha256': await runtimeSha256File(options.engineNinja),
      'version': await _stdout(options.engineNinja, const <String>[
        '--version',
      ]),
      'architectures': await runtimeArchitectures(options.engineNinja),
      'arguments': <String>[
        '-C',
        outputDirectory,
        if (options.mode == RuntimeMode.developerJit)
          'dart_engine_jit_shared'
        else
          'dart_engine_aot_shared',
        if (options.mode == RuntimeMode.releaseAot) 'gen_snapshot',
        'bootstrap_gen_kernel.exe',
        '${options.architecture == 'arm64' ? 'clang_arm64_shared' : 'clang_x64_shared'}/vm_platform.dill',
      ],
    },
    'engine_python': <String, Object?>{
      'path': (await runtimePathSnapshot(options.enginePython)).canonicalPath,
      'sha256': await runtimeSha256File(options.enginePython),
      'version': await _stdout(options.enginePython, const <String>[
        '--version',
      ]),
      'architectures': await runtimeArchitectures(options.enginePython),
      'arguments': <String>[
        (await runtimePathSnapshot(options.engineGnScript)).canonicalPath,
        '--mode=${options.mode == RuntimeMode.releaseAot ? 'product' : 'release'}',
        '--arch=$engineArchitecture',
      ],
    },
    'make': <String, Object?>{
      'path': (await runtimePathSnapshot(options.makeExecutable)).canonicalPath,
      'sha256': await runtimeSha256File(options.makeExecutable),
      'version': (await _stdout(options.makeExecutable, const <String>[
        '--version',
      ])).split('\n').first,
      'architectures': await runtimeArchitectures(options.makeExecutable),
      'arguments': <String>[
        'RUNTIME_ARCH=${options.architecture}',
        options.mode == RuntimeMode.developerJit
            ? 'developer-jit-build'
            : 'release-aot-build',
      ],
    },
  };
  if (options.mode == RuntimeMode.releaseAot) {
    await _requireSameToolIdentity(
      options.snapshotterRunnerExecutable!,
      '/usr/bin/arch',
      'snapshotter runner executable',
    );
    final String expectedArgument = '-${options.architecture}';
    if (options.snapshotterRunnerArguments != expectedArgument) {
      throw _FingerprintException(
        'snapshotter runner arguments '
        '${options.snapshotterRunnerArguments} != $expectedArgument',
      );
    }
    tools['snapshotter_runner'] = <String, Object?>{
      'path': (await runtimePathSnapshot(options.snapshotterRunnerExecutable!))
          .canonicalPath,
      'sha256': await runtimeSha256File(options.snapshotterRunnerExecutable!),
      'architectures': await runtimeArchitectures(
        options.snapshotterRunnerExecutable!,
      ),
      'arguments': <String>[expectedArgument],
    };
  }
  return tools;
}

Future<Map<String, SplayTreeMap<String, String>>> _engineArguments(
  _Options options,
) async {
  final String outputMode = options.mode == RuntimeMode.releaseAot
      ? 'Product'
      : 'Release';
  final String outputArchitecture = options.architecture == 'arm64'
      ? 'ARM64'
      : 'X64';
  final String engineArchitecture = options.architecture == 'arm64'
      ? 'arm64'
      : 'x64';
  final File argsFile = File(
    '${options.dartEngineRoot}/xcodebuild/'
    '$outputMode$outputArchitecture/args.gn',
  );
  if (!await argsFile.exists()) {
    throw _FingerprintException('missing Engine args.gn: ${argsFile.path}');
  }
  final SplayTreeMap<String, String> common = SplayTreeMap<String, String>();
  for (final String line in await argsFile.readAsLines()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final Match? match = RegExp(r'^([a-zA-Z0-9_]+) = (.+)$')
        .firstMatch(trimmed);
    if (match == null || common.containsKey(match.group(1))) {
      throw _FingerprintException(
        'unsupported or duplicate Engine GN argument: $trimmed',
      );
    }
    common[match.group(1)!] = match.group(2)!;
  }
  final SplayTreeMap<String, String> lane = SplayTreeMap<String, String>();
  final Map<String, String> expectedLane = <String, String>{
    'host_cpu': '"$engineArchitecture"',
    'target_cpu': '"$engineArchitecture"',
    'dart_target_arch': '"$engineArchitecture"',
  };
  for (final MapEntry<String, String> entry in expectedLane.entries) {
    final String? value = common.remove(entry.key);
    if (value != entry.value) {
      throw _FingerprintException(
        'Engine GN ${entry.key}=$value != ${entry.value}',
      );
    }
    lane[entry.key] = value!;
  }
  final Map<String, String> expectedMode = <String, String>{
    'target_os': '"mac"',
    'is_debug': 'false',
    'is_product': options.mode == RuntimeMode.releaseAot ? 'true' : 'false',
    'is_release': options.mode == RuntimeMode.developerJit ? 'true' : 'false',
    'dart_runtime_mode': options.mode == RuntimeMode.releaseAot
        ? '"release"'
        : '"develop"',
  };
  for (final MapEntry<String, String> entry in expectedMode.entries) {
    if (common[entry.key] != entry.value) {
      throw _FingerprintException(
        'Engine GN ${entry.key}=${common[entry.key]} != ${entry.value}',
      );
    }
  }
  return <String, SplayTreeMap<String, String>>{'common': common, 'lane': lane};
}

Future<({Map<String, Object?> semantic, Map<String, Object?> local})>
_packageConfiguration(_Options options, String sdkVersion) async {
  final File configFile = File(options.packageConfig);
  final FileSystemEntityType configType = await FileSystemEntity.type(
    configFile.path,
    followLinks: false,
  );
  if (configType != FileSystemEntityType.file) {
    throw _FingerprintException(
      'missing regular package config: ${configFile.path}',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(await configFile.readAsString());
  } on FormatException catch (error) {
    throw _FingerprintException('invalid package config JSON: $error');
  }
  if (decoded is! Map<String, Object?>) {
    throw const _FingerprintException('package config must be an object');
  }
  if (!sameStringSet(decoded.keys, const <String>{
    'configVersion',
    'packages',
    'generator',
    'generatorVersion',
    'pubCache',
  })) {
    throw _FingerprintException(
      'unexpected package config keys: ${decoded.keys.toList()..sort()}',
    );
  }
  if (decoded['configVersion'] != 2 ||
      decoded['generator'] != 'pub' ||
      decoded['generatorVersion'] != sdkVersion) {
    throw _FingerprintException(
      'package config generator/version does not match Dart SDK $sdkVersion',
    );
  }
  final Object? packagesValue = decoded['packages'];
  if (packagesValue is! List<Object?>) {
    throw const _FingerprintException('package config packages must be a list');
  }
  final String languageVersion = sdkVersion.split('.').take(2).join('.');
  final Map<String, String> expectedRoots = <String, String>{
    'dart_terminal': await Directory(options.projectRoot)
        .resolveSymbolicLinks(),
    'dart_appkit': await Directory(
      '${options.dartAppKitRoot}/packages/dart_appkit',
    ).resolveSymbolicLinks(),
  };
  final SplayTreeMap<String, Object?> semanticPackages =
      SplayTreeMap<String, Object?>();
  final SplayTreeMap<String, Object?> resolvedRoots =
      SplayTreeMap<String, Object?>();
  for (final Object? packageValue in packagesValue) {
    if (packageValue is! Map<String, Object?> ||
        !sameStringSet(packageValue.keys, const <String>{
          'name',
          'rootUri',
          'packageUri',
          'languageVersion',
        })) {
      throw const _FingerprintException(
        'package config entry has an unsupported shape',
      );
    }
    final Object? nameValue = packageValue['name'];
    final Object? rootValue = packageValue['rootUri'];
    final Object? packageUriValue = packageValue['packageUri'];
    final Object? languageValue = packageValue['languageVersion'];
    if (nameValue is! String ||
        rootValue is! String ||
        packageUriValue != 'lib/' ||
        languageValue != languageVersion ||
        semanticPackages.containsKey(nameValue)) {
      throw const _FingerprintException(
        'package config entry values are invalid or duplicated',
      );
    }
    final String? expectedRoot = expectedRoots[nameValue];
    if (expectedRoot == null) {
      throw _FingerprintException('unexpected package in config: $nameValue');
    }
    final Uri resolvedUri = configFile.absolute.uri.resolve(rootValue);
    if (resolvedUri.scheme != 'file' ||
        (resolvedUri.hasAuthority && resolvedUri.authority.isNotEmpty) ||
        resolvedUri.hasQuery ||
        resolvedUri.hasFragment) {
      throw _FingerprintException(
        'package $nameValue rootUri must resolve to a local file URI',
      );
    }
    final String resolvedRoot = Directory.fromUri(resolvedUri).absolute.path;
    final RuntimePathSnapshot resolvedRootSnapshot = await runtimePathSnapshot(
      resolvedRoot,
    );
    final RuntimePathSnapshot expectedRootSnapshot = await runtimePathSnapshot(
      expectedRoot,
    );
    if (resolvedRootSnapshot.targetType != FileSystemEntityType.directory ||
        resolvedRootSnapshot.targetIdentity !=
            expectedRootSnapshot.targetIdentity) {
      throw _FingerprintException(
        'package $nameValue root does not identify $expectedRoot',
      );
    }
    final RuntimePathSnapshot libraryRootSnapshot = await runtimePathSnapshot(
      '${resolvedRootSnapshot.canonicalPath}/lib',
    );
    final RuntimePathSnapshot expectedLibraryRootSnapshot =
        await runtimePathSnapshot('${expectedRootSnapshot.canonicalPath}/lib');
    if (libraryRootSnapshot.targetType != FileSystemEntityType.directory ||
        libraryRootSnapshot.targetIdentity !=
            expectedLibraryRootSnapshot.targetIdentity) {
      throw _FingerprintException(
        'package $nameValue packageUri escapes its expected root',
      );
    }
    semanticPackages[nameValue] = <String, Object?>{
      'root_role': nameValue == 'dart_terminal'
          ? 'project:.'
          : 'dart_appkit:packages/dart_appkit',
      'package_uri': 'lib/',
      'language_version': languageVersion,
    };
    resolvedRoots[nameValue] = resolvedRootSnapshot.canonicalPath;
  }
  if (!sameStringSet(semanticPackages.keys, expectedRoots.keys)) {
    throw _FingerprintException(
      'package config set ${semanticPackages.keys.toList()} != '
      '${expectedRoots.keys.toList()}',
    );
  }
  final Object? pubCacheValue = decoded['pubCache'];
  final Uri? pubCacheUri = pubCacheValue is String
      ? Uri.tryParse(pubCacheValue)
      : null;
  if (pubCacheUri == null ||
      pubCacheUri.scheme != 'file' ||
      (pubCacheUri.hasAuthority && pubCacheUri.authority.isNotEmpty) ||
      pubCacheUri.hasQuery ||
      pubCacheUri.hasFragment) {
    throw const _FingerprintException(
      'package config pubCache must be a file URI',
    );
  }
  final Map<String, Object?> semantic = <String, Object?>{
    'config_version': 2,
    'generator': 'pub',
    'generator_version': sdkVersion,
    'packages': semanticPackages,
  };
  semantic['semantic_sha256'] = await runtimeSha256Text(
    runtimeCanonicalJsonEncode(semantic),
  );
  return (
    semantic: semantic,
    local: <String, Object?>{
      'path': await configFile.resolveSymbolicLinks(),
      'raw_sha256': await runtimeSha256File(configFile.path),
      'resolved_package_roots': resolvedRoots,
      'pub_cache': pubCacheValue,
    },
  );
}

Future<void> _addFile(
  SplayTreeMap<String, String> files,
  String label,
  String path,
) async {
  final FileSystemEntityType type = await FileSystemEntity.type(
    path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.file) {
    throw _FingerprintException('missing regular build input: $path');
  }
  files[label] = path;
}

Future<void> _addDirectory(
  SplayTreeMap<String, String> files,
  String label,
  String root,
  String relativeDirectory,
) async {
  final Directory directory = Directory('$root/$relativeDirectory');
  if (!await directory.exists()) {
    throw _FingerprintException('missing input directory: ${directory.path}');
  }
  await for (final FileSystemEntity entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Link) {
      throw _FingerprintException('build input is a symlink: ${entity.path}');
    }
    if (entity is File) {
      final String relative = entity.path.substring(root.length + 1);
      files['$label:$relative'] = entity.path;
    }
  }
}

Future<SplayTreeMap<String, Object?>> _sourceInventory(_Options options) async {
  final SplayTreeMap<String, String> files = SplayTreeMap<String, String>();
  for (final String relative in runtimeProjectProvenanceFilesForMode(
    options.mode,
  )) {
    await _addFile(
      files,
      'dart_terminal:$relative',
      '${options.projectRoot}/$relative',
    );
  }
  for (final String directory in <String>[
    'bin',
    'lib',
    'native/macos/runtime',
  ]) {
    await _addDirectory(files, 'dart_terminal', options.projectRoot, directory);
  }
  for (final String relative in runtimeAppKitProvenanceFiles) {
    await _addFile(
      files,
      'dart_appkit:$relative',
      '${options.dartAppKitRoot}/$relative',
    );
  }
  for (final String directory in <String>[
    'native/bridge/include',
    'native/bridge/src',
    'native/runner',
    'packages/dart_appkit/lib',
  ]) {
    await _addDirectory(
      files,
      'dart_appkit',
      options.dartAppKitRoot,
      directory,
    );
  }
  if (options.extraBuildInput != null) {
    await _addFile(
      files,
      'effective_override:extra_build_input',
      options.extraBuildInput!,
    );
  }
  final SplayTreeMap<String, Object?> hashes = SplayTreeMap<String, Object?>();
  for (final MapEntry<String, String> entry in files.entries) {
    hashes[entry.key] = await runtimeSha256File(entry.value);
  }
  return hashes;
}

Never _unsupportedEffectiveFlags(String actual, List<String> expected) {
  throw _FingerprintException(
    'effective flags contain unsupported path-bearing token or '
    'non-product configuration: actual="$actual" '
    'expected="${expected.join(' ')}"',
  );
}

List<String> _flagTokens(String flags) =>
    flags.trim().isEmpty ? <String>[] : flags.trim().split(RegExp(r'\s+'));

bool _sameFlagTokens(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < actual.length; ++index) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}

String _normalizedNativeFlags(_Options options) {
  final List<String> expected = <String>[
    '-Wall',
    '-Wextra',
    '-Wpedantic',
    '-Werror',
    '-Wno-gnu-anonymous-struct',
    '-Wno-nested-anon-types',
    '-std=c++20',
    '-fobjc-arc',
    '-isysroot',
    options.sdkRoot,
    '-mmacosx-version-min=${options.deploymentTarget}',
    '-fblocks',
    '-fvisibility=hidden',
  ];
  if (options.nativeFlags.trim() != expected.join(' ')) {
    _unsupportedEffectiveFlags(options.nativeFlags, expected);
  }
  expected[9] = r'${MACOS_SDK_ROOT}';
  return expected.join(' ');
}

String _normalizedKernelFlags(_Options options, String sdkRevision) {
  final List<String> expected = options.mode == RuntimeMode.developerJit
      ? <String>[
          '--no-aot',
          '--link-platform',
          '--no-embed-sources',
          '-Dsdk_hash=${sdkRevision.substring(0, 10)}',
          '-Ddart.vm.product=false',
          '-Ddart.vm.asan=false',
          '-Ddart.vm.msan=false',
          '-Ddart.vm.tsan=false',
        ]
      : <String>[
          '--aot',
          '--link-platform',
          '--no-embed-sources',
          '--target-os=macos',
          '--invocation-modes=compile',
          '--verbosity=error',
          '-Ddart.vm.product=true',
          '-Ddart.vm.asan=false',
          '-Ddart.vm.msan=false',
          '-Ddart.vm.tsan=false',
        ];
  final List<String> actual = _flagTokens(options.kernelFlags);
  if (!_sameFlagTokens(actual, expected)) {
    _unsupportedEffectiveFlags(options.kernelFlags, expected);
  }
  return actual.join(' ');
}

String _normalizedSnapshotFlags(_Options options) {
  final List<String> expected = options.mode == RuntimeMode.developerJit
      ? <String>['not-applicable']
      : <String>['--snapshot-kind=app-aot-macho-dylib', '--macho'];
  final List<String> actual = _flagTokens(options.snapshotFlags);
  if (!_sameFlagTokens(actual, expected)) {
    _unsupportedEffectiveFlags(options.snapshotFlags, expected);
  }
  return actual.join(' ');
}

String? _normalizedWorkerKernelFlags(_Options options) {
  if (options.mode == RuntimeMode.releaseAot) {
    return null;
  }
  const List<String> expected = <String>[
    '--link-platform',
    '--no-embed-sources',
    '--verbosity=warning',
  ];
  final List<String> actual = _flagTokens(options.workerKernelFlags!);
  if (!_sameFlagTokens(actual, expected)) {
    _unsupportedEffectiveFlags(options.workerKernelFlags!, expected);
  }
  return actual.join(' ');
}

String? _normalizedWorkerExecutableFlags(_Options options) {
  if (options.mode == RuntimeMode.developerJit) {
    return null;
  }
  final List<String> expected = <String>[
    '--target-os=macos',
    '--target-arch=${options.architecture == 'arm64' ? 'arm64' : 'x64'}',
    '--verbosity=warning',
  ];
  final List<String> actual = _flagTokens(options.workerExecutableFlags!);
  if (!_sameFlagTokens(actual, expected)) {
    _unsupportedEffectiveFlags(options.workerExecutableFlags!, expected);
  }
  return actual.join(' ');
}

Future<Map<String, Object?>> _createFingerprint(_Options options) async {
  for (final String root in <String>[
    options.projectRoot,
    options.dartAppKitRoot,
    options.dartEngineRoot,
    options.dartSdkRoot,
    options.runtimeBuildRoot,
    options.sdkRoot,
  ]) {
    if (!Directory(root).isAbsolute) {
      throw _FingerprintException('root must be absolute: $root');
    }
  }
  for (final String file in <String>[
    options.engineLibrary,
    options.kernelCompiler,
    options.platformDill,
    options.clang,
    options.packageConfig,
    options.dartExecutable,
    options.engineGnScript,
    options.engineNinja,
    options.enginePython,
    options.makeExecutable,
    if (options.snapshotter != null) options.snapshotter!,
    if (options.snapshotterRunnerExecutable != null)
      options.snapshotterRunnerExecutable!,
  ]) {
    if (!File(file).isAbsolute) {
      throw _FingerprintException('file path must be absolute: $file');
    }
  }
  if (!File(options.output).isAbsolute) {
    throw _FingerprintException('output must be absolute: ${options.output}');
  }

  final String sdkVersion = (await File(
    '${options.dartSdkRoot}/version',
  ).readAsString()).trim();
  final String sdkRevision = (await File(
    '${options.dartSdkRoot}/revision',
  ).readAsString()).trim();
  final Map<String, Object?> engineRepository = await _repositoryIdentity(
    options.dartEngineRoot,
    policy: 'clean',
  );
  if (sdkRevision != engineRepository['revision']) {
    throw _FingerprintException(
      'Dart SDK revision $sdkRevision does not match Engine '
      '${engineRepository['revision']}',
    );
  }
  final Map<String, SplayTreeMap<String, String>> engineArguments =
      await _engineArguments(options);
  final Map<String, Object?> buildTools = await _buildTools(
    options,
    sdkVersion,
    sdkRevision,
  );
  final packageConfiguration = await _packageConfiguration(options, sdkVersion);
  final SplayTreeMap<String, Object?> sourceInventory = await _sourceInventory(
    options,
  );
  final SplayTreeMap<String, Object?> binaryHashes =
      SplayTreeMap<String, Object?>();
  final SplayTreeMap<String, Object?> binaryPaths =
      SplayTreeMap<String, Object?>();
  final SplayTreeMap<String, Object?> binaryArchitectures =
      SplayTreeMap<String, Object?>();
  final Map<String, String> laneFiles = <String, String>{
    'dart_engine': options.engineLibrary,
    'kernel_compiler': options.kernelCompiler,
    'platform_dill': options.platformDill,
    if (options.mode == RuntimeMode.developerJit)
      'runtime_worker_dart': options.dartExecutable,
    if (options.mode == RuntimeMode.releaseAot)
      'runtime_worker_compiler': options.dartExecutable,
    if (options.snapshotter != null) 'snapshotter': options.snapshotter!,
  };
  for (final MapEntry<String, String> entry in laneFiles.entries) {
    binaryHashes[entry.key] = await runtimeSha256File(entry.value);
    binaryPaths[entry.key] = await File(entry.value).resolveSymbolicLinks();
    if (entry.key != 'platform_dill') {
      binaryArchitectures[entry.key] = await runtimeArchitectures(entry.value);
    }
  }
  final List<String> engineSlices =
      (binaryArchitectures['dart_engine']! as List<String>);
  if (!sameStringSet(engineSlices, <String>[options.architecture])) {
    throw _FingerprintException(
      'Engine slices ${engineSlices.join(',')} != ${options.architecture}',
    );
  }
  if (options.snapshotter != null) {
    final List<String> snapshotterSlices =
        (binaryArchitectures['snapshotter']! as List<String>);
    if (!sameStringSet(snapshotterSlices, <String>[options.architecture])) {
      throw _FingerprintException(
        'snapshotter slices ${snapshotterSlices.join(',')} != '
        '${options.architecture}',
      );
    }
  }
  if (options.mode == RuntimeMode.developerJit) {
    final List<String> workerDartSlices =
        (binaryArchitectures['runtime_worker_dart']! as List<String>);
    if (!sameStringSet(workerDartSlices, <String>[options.architecture])) {
      throw _FingerprintException(
        'runtime worker Dart slices ${workerDartSlices.join(',')} != '
        '${options.architecture}',
      );
    }
  }
  final String? extraInputHash = options.extraBuildInput == null
      ? null
      : sourceInventory['effective_override:extra_build_input']! as String;
  return <String, Object?>{
    'format': runtimeBuildFingerprintFormat,
    'version': runtimeBuildFingerprintVersion,
    'common': <String, Object?>{
      'runtime_mode': options.mode.name,
      'engine_configuration': options.mode.engineConfiguration,
      'deployment_target': options.deploymentTarget,
      'bundle': <String, Object?>{
        'identifier': options.mode.bundleIdentifier,
        'version': options.bundleVersion,
        'executable': options.mode == RuntimeMode.developerJit
            ? 'dart_terminal_developer_jit'
            : 'dart_terminal_release_aot',
      },
      'dart_sdk': <String, Object?>{
        'version': sdkVersion,
        'revision': sdkRevision,
      },
      'dart_engine': <String, Object?>{
        'revision': engineRepository['revision'],
        'source_policy': 'official-clean',
        'gn_arguments': engineArguments['common'],
        'repository': engineRepository,
      },
      'dart_appkit': <String, Object?>{
        'repository': await _repositoryIdentity(
          options.dartAppKitRoot,
          policy: 'clean',
        ),
      },
      'toolchain': await _toolchain(options),
      'package_config': packageConfiguration.semantic,
      'architecture_neutral_inputs': <String, Object?>{
        'platform_dill_sha256': binaryHashes['platform_dill'],
      },
      'source': <String, Object?>{
        'repository': await _repositoryIdentity(
          options.projectRoot,
          policy: 'record',
        ),
        'input_sha256': sourceInventory,
        'inventory_sha256': await runtimeSha256Text(
          runtimeCanonicalJsonEncode(sourceInventory),
        ),
      },
      'effective_configuration': <String, Object?>{
        'runtime_mode': options.mode.name,
        'engine_configuration': options.mode.engineConfiguration,
        'deployment_target': options.deploymentTarget,
        'bundle_version': options.bundleVersion,
        'native_flags': _normalizedNativeFlags(options),
        'kernel_flags': _normalizedKernelFlags(options, sdkRevision),
        'worker_topology': 'official-dart-child-process',
        'worker_protocol_version': runtimeWorkerProtocolVersion,
        if (options.mode == RuntimeMode.developerJit)
          'worker_payload_name': runtimeDeveloperWorkerPayloadName,
        if (options.mode == RuntimeMode.developerJit)
          'worker_kernel_flags': _normalizedWorkerKernelFlags(options),
        if (options.mode == RuntimeMode.releaseAot)
          'worker_executable_name': runtimeReleaseWorkerExecutableName,
        if (options.mode == RuntimeMode.releaseAot)
          'worker_executable_flags': _normalizedWorkerExecutableFlags(options),
        'snapshot_flags': _normalizedSnapshotFlags(options),
        'extra_build_input_sha256': extraInputHash ?? 'none',
      },
    },
    'lane': <String, Object?>{
      'architecture': options.architecture,
      'engine_gn_arguments': engineArguments['lane'],
      'input_binary_sha256': binaryHashes,
      'input_binary_architectures': binaryArchitectures,
      'resolved_input_paths': binaryPaths,
      'build_tools': buildTools,
      'package_config': packageConfiguration.local,
      'build_environment': <String, Object?>{
        'resolved_paths': <String, Object?>{
          'project_root': await Directory(options.projectRoot)
              .resolveSymbolicLinks(),
          'dart_appkit_root': await Directory(options.dartAppKitRoot)
              .resolveSymbolicLinks(),
          'dart_engine_root': await Directory(options.dartEngineRoot)
              .resolveSymbolicLinks(),
          'dart_sdk_root': await Directory(options.dartSdkRoot)
              .resolveSymbolicLinks(),
          'runtime_build_root': runtimeNormalizedAbsolutePath(
            options.runtimeBuildRoot,
          ),
          'clang': await File(options.clang).resolveSymbolicLinks(),
          'sdk_root': await Directory(options.sdkRoot).resolveSymbolicLinks(),
          if (options.extraBuildInput != null)
            'extra_build_input': await File(options.extraBuildInput!)
                .resolveSymbolicLinks(),
        },
        'host_tool_sha256': <String, Object?>{
          'clang': await runtimeSha256File(options.clang),
        },
        'host_tool_architectures': <String, Object?>{
          'clang': await runtimeArchitectures(options.clang),
        },
      },
    },
  };
}

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseOptions(arguments);
    final Map<String, Object?> fingerprint = await _createFingerprint(options);
    await runtimeWriteJsonIfChanged(options.output, fingerprint);
    stderr.writeln(
      'RUNTIME_BUILD_FINGERPRINT_PASS mode=${options.mode.name} '
      'architecture=${options.architecture}',
    );
  } on Object catch (error) {
    stderr.writeln('RUNTIME_BUILD_FINGERPRINT_FAIL $error');
    exitCode = 1;
  }
}
