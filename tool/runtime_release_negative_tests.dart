import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'src/runtime_release_support.dart';

final class _NegativeTestException implements Exception {
  const _NegativeTestException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.arm64Bundle,
    required this.arm64Report,
    required this.x86_64Bundle,
    required this.x86_64Report,
    required this.universalArtifactDirectory,
    required this.universalBundle,
    required this.universalReport,
    required this.deploymentTarget,
    required this.assembler,
    required this.auditor,
    required this.handoff,
    required this.projectRoot,
  });

  final String arm64Bundle;
  final String arm64Report;
  final String x86_64Bundle;
  final String x86_64Report;
  final String universalArtifactDirectory;
  final String universalBundle;
  final String universalReport;
  final String deploymentTarget;
  final String assembler;
  final String auditor;
  final String handoff;
  final String projectRoot;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _NegativeTestException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw _NegativeTestException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> expected = <String>{
    'arm64-bundle',
    'arm64-report',
    'x86_64-bundle',
    'x86_64-report',
    'universal-artifact-directory',
    'universal-bundle',
    'universal-report',
    'deployment-target',
    'assembler',
    'auditor',
    'handoff',
    'project-root',
  };
  final Set<String> unknown = values.keys.toSet().difference(expected);
  final Set<String> missing = expected.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _NegativeTestException(
      'unknown=${unknown.join(',')} missing=${missing.join(',')}',
    );
  }
  return _Options(
    arm64Bundle: values['arm64-bundle']!,
    arm64Report: values['arm64-report']!,
    x86_64Bundle: values['x86_64-bundle']!,
    x86_64Report: values['x86_64-report']!,
    universalArtifactDirectory: values['universal-artifact-directory']!,
    universalBundle: values['universal-bundle']!,
    universalReport: values['universal-report']!,
    deploymentTarget: values['deployment-target']!,
    assembler: values['assembler']!,
    auditor: values['auditor']!,
    handoff: values['handoff']!,
    projectRoot: values['project-root']!,
  );
}

Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String> environment = const <String, String>{},
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: <String, String>{
    'DART_SUPPRESS_ANALYTICS': 'true',
    ...environment,
  },
  includeParentEnvironment: true,
);

Future<void> _expectPass(
  String description,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final ProcessResult result = await _run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw _NegativeTestException(
      '$description unexpectedly failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
}

Future<void> _expectFailure(
  String description,
  String executable,
  List<String> arguments,
  String expectedText, {
  String? workingDirectory,
}) async {
  final ProcessResult result = await _run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 || !output.contains(expectedText)) {
    throw _NegativeTestException(
      '$description did not fail closed with "$expectedText" '
      '(status ${result.exitCode}): $output',
    );
  }
  stdout.writeln('RUNTIME_RELEASE_NEGATIVE_PASS case=$description');
}

Future<void> _expectFaultTermination(
  String description,
  List<String> arguments,
  String faultPoint,
) async {
  final ProcessResult result = await _run(
    Platform.resolvedExecutable,
    arguments,
    environment: <String, String>{'DART_TERMINAL_UNIVERSAL_FAULT': faultPoint},
  );
  final String output = '${result.stdout}${result.stderr}';
  if (result.exitCode == 0 ||
      !output.contains('RUNTIME_UNIVERSAL_FAULT_INJECTED point=$faultPoint')) {
    throw _NegativeTestException(
      '$description did not terminate at $faultPoint '
      '(status ${result.exitCode}): $output',
    );
  }
  stdout.writeln('RUNTIME_RELEASE_NEGATIVE_PASS case=$description');
}

Future<void> _expectPublicationRaceFailure(
  String description,
  List<String> arguments,
  Directory barrier,
  Future<void> Function(String stagingPath) replaceDestination,
  String expectedText, {
  String barrierPoint = 'before-publish',
  Map<String, String> environment = const <String, String>{},
}) async {
  await barrier.create();
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    arguments,
    environment: <String, String>{
      'DART_SUPPRESS_ANALYTICS': 'true',
      'DART_TERMINAL_UNIVERSAL_TEST_BARRIER': barrier.path,
      'DART_TERMINAL_UNIVERSAL_TEST_BARRIER_POINT': barrierPoint,
      ...environment,
    },
    includeParentEnvironment: true,
  );
  final Future<String> stdoutText = process.stdout
      .transform(utf8.decoder)
      .join();
  final Future<String> stderrText = process.stderr
      .transform(utf8.decoder)
      .join();
  var released = false;
  try {
    final File ready = File('${barrier.path}/ready');
    final Object event = await Future.any<Object>(<Future<Object>>[
      (() async {
        final DateTime deadline = DateTime.now().add(
          const Duration(seconds: 30),
        );
        while (!await ready.exists()) {
          if (!DateTime.now().isBefore(deadline)) {
            throw const _NegativeTestException(
              'publication-race barrier timed out',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return 'ready';
      })(),
      process.exitCode.then<Object>((int status) => status),
    ]);
    if (event != 'ready') {
      throw _NegativeTestException(
        '$description exited before publication capture (status $event): '
        '${await stdoutText}${await stderrText}',
      );
    }
    final List<String> readyLines = await ready.readAsLines();
    if (readyLines.length != 3 || readyLines[1] != barrierPoint) {
      throw _NegativeTestException(
        '$description produced malformed barrier state: $readyLines',
      );
    }
    await replaceDestination(readyLines[2]);
    await File('${barrier.path}/continue').create(exclusive: true);
    released = true;
    final int status = await process.exitCode;
    final String output = '${await stdoutText}${await stderrText}';
    if (status == 0 || !output.contains(expectedText)) {
      throw _NegativeTestException(
        '$description did not fail closed with "$expectedText" '
        '(status $status): $output',
      );
    }
    stdout.writeln('RUNTIME_RELEASE_NEGATIVE_PASS case=$description');
  } finally {
    if (!released) {
      try {
        await File('${barrier.path}/continue').create();
      } on Object {
        // The child may already have removed its private fixture directory.
      }
      process.kill();
      await process.exitCode;
    }
  }
}

Future<void> _copyBundle(String source, String destination) async {
  await _expectPass('bundle fixture copy', '/usr/bin/ditto', <String>[
    '--noqtn',
    source,
    destination,
  ]);
}

Future<void> _sign(String path, {String? entitlements}) =>
    _expectPass('fixture sign', '/usr/bin/codesign', <String>[
      '--force',
      if (entitlements != null) '--force-library-entitlements',
      '--sign',
      '-',
      '--timestamp=none',
      if (entitlements != null) ...<String>['--entitlements', entitlements],
      path,
    ]);

Future<void> _signOuter(String bundle) => _sign(bundle);

List<String> _auditorArguments(
  _Options options,
  String bundle,
  String architectures, {
  String? outputReport,
}) => <String>[
  options.auditor,
  '--mode=release-aot',
  '--expected-architectures=$architectures',
  '--deployment-target=${options.deploymentTarget}',
  if (outputReport != null) '--output-report=$outputReport',
  bundle,
];

List<String> _assemblerArguments(
  _Options options, {
  required String arm64,
  required String arm64Report,
  required String x86_64,
  required String x86_64Report,
  required String outputDirectory,
}) => <String>[
  options.assembler,
  '--arm64-bundle=$arm64',
  '--arm64-report=$arm64Report',
  '--x86_64-bundle=$x86_64',
  '--x86_64-report=$x86_64Report',
  '--output-directory=$outputDirectory',
  '--deployment-target=${options.deploymentTarget}',
];

List<String> _handoffArguments(
  _Options options, {
  required String developerBundle,
  required String developerReport,
  required String releaseBundle,
  required String releaseReport,
  required String smoke,
  required String evidence,
}) => <String>[
  options.handoff,
  '--developer-jit-bundle=$developerBundle',
  '--developer-jit-report=$developerReport',
  '--release-aot-bundle=$releaseBundle',
  '--release-aot-report=$releaseReport',
  '--universal-bundle=${options.universalBundle}',
  '--universal-report=${options.universalReport}',
  '--deployment-target=${options.deploymentTarget}',
  '--smoke=$smoke',
  '--hardware-label=negative-test',
  '--output-evidence=$evidence',
];

Future<void> _writePassingReceipt(
  _Options options,
  String bundle,
  String architecture,
  String report,
) => _expectPass(
  'fixture audit receipt',
  Platform.resolvedExecutable,
  _auditorArguments(options, bundle, architecture, outputReport: report),
);

Future<void> _rewriteManifest(
  String bundle,
  void Function(Map<String, Object?> manifest) mutate,
) async {
  final File file = File(
    '$bundle/Contents/Resources/runtime-build-manifest.json',
  );
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const _NegativeTestException('manifest is not an object');
  }
  mutate(decoded);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
    flush: true,
  );
  await _signOuter(bundle);
}

Map<String, Object?> _manifestLane(Map<String, Object?> manifest) =>
    runtimeStringMap(
      manifest['architecture_inputs'],
      'negative-test architecture lane',
    );

Map<String, Object?> _manifestBuildTool(
  Map<String, Object?> manifest,
  String role,
) => runtimeStringMap(
  runtimeStringMap(
    _manifestLane(manifest)['build_tools'],
    'negative-test build tools',
  )[role],
  'negative-test $role tool',
);

Map<String, Object?> _manifestEnvironmentPaths(Map<String, Object?> manifest) =>
    runtimeStringMap(
      runtimeStringMap(
        _manifestLane(manifest)['build_environment'],
        'negative-test build environment',
      )['resolved_paths'],
      'negative-test resolved paths',
    );

Future<void> _expectAbsent(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw _NegativeTestException('failed command published output: $path');
  }
}

Future<String> _sealDigest(String bundle) async => runtimeSha256Text(
  runtimeCanonicalJsonEncode(await runtimeBundleSeal(bundle)),
);

Future<String> _validatePublishedPair(
  _Options options,
  String artifactDirectory,
) async {
  final String bundle = '$artifactDirectory/DartTerminal.app';
  final String assemblyReportPath = '$artifactDirectory/assembly-report.json';
  final String auditReportPath = '$artifactDirectory/universal-audit.json';
  final Map<String, Object?> audit = await validateRuntimeAuditReceipt(
    auditReportPath,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: supportedRuntimeArchitectures,
      deploymentTarget: options.deploymentTarget,
      bundlePath: bundle,
    ),
  );
  final Object? assemblyDecoded = jsonDecode(
    await File(assemblyReportPath).readAsString(),
  );
  final Object? auditDecoded = jsonDecode(
    await File(auditReportPath).readAsString(),
  );
  final Map<String, Object?> assembly = runtimeStringMap(
    assemblyDecoded,
    'published assembly report',
  );
  final Map<String, Object?> auditReceipt = runtimeStringMap(
    auditDecoded,
    'published runtime audit receipt',
  );
  final Map<String, Object?> manifest = runtimeStringMap(
    audit['build_manifest'],
    'published Universal manifest',
  );
  final Object? generation = manifest['publication_generation_sha256'];
  if (assembly['status'] != 'pass' ||
      auditReceipt['status'] != 'pass' ||
      generation is! String ||
      assembly['publication_generation_sha256'] != generation ||
      auditReceipt['publication_generation_sha256'] != generation) {
    throw const _NegativeTestException(
      'published bundle and receipts do not identify one generation',
    );
  }
  return generation;
}

Future<void> _replaceWithExtraSlice(String bundle) async {
  final String launcher = '$bundle/Contents/MacOS/dart_terminal_release_aot';
  final String arm64e = '$bundle/Contents/Resources/.arm64e-fixture';
  final String fat = '$bundle/Contents/Resources/.extra-fat-fixture';
  await _expectPass('extract arm64e fixture', '/usr/bin/lipo', <String>[
    '/bin/ls',
    '-thin',
    'arm64e',
    '-output',
    arm64e,
  ]);
  await _expectPass('create extra-slice fixture', '/usr/bin/lipo', <String>[
    '-create',
    launcher,
    arm64e,
    '-output',
    fat,
  ]);
  await File(launcher).delete();
  await File(fat).rename(launcher);
  await File(arm64e).delete();
}

Future<void> _replaceWithMalformedDuplicateHeader(String bundle) async {
  final String launcher = '$bundle/Contents/MacOS/dart_terminal_release_aot';
  final File launcherFile = File(launcher);
  final Uint8List contents = await launcherFile.readAsBytes();
  if (contents.length < 68) {
    throw const _NegativeTestException('fat header fixture is too short');
  }
  final ByteData bytes = ByteData.sublistView(contents);
  if (bytes.getUint32(0, Endian.big) != 0xcafebabe ||
      bytes.getUint32(4, Endian.big) != 2) {
    throw const _NegativeTestException(
      'accepted Universal launcher is not a two-record FAT_MAGIC file',
    );
  }
  bytes.setUint32(4, 3, Endian.big);
  contents.setRange(48, 68, contents, 8);
  await launcherFile.writeAsBytes(contents, flush: true);
}

Future<void> _runTests(_Options options) async {
  for (final String path in <String>[
    options.arm64Bundle,
    options.arm64Report,
    options.x86_64Bundle,
    options.x86_64Report,
    options.universalArtifactDirectory,
    options.universalBundle,
    options.universalReport,
    options.assembler,
    options.auditor,
    options.handoff,
    options.projectRoot,
  ]) {
    if (!File(path).isAbsolute) {
      throw _NegativeTestException('path must be absolute: $path');
    }
  }
  await validateRuntimeAuditReceipt(
    options.universalReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: supportedRuntimeArchitectures,
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.universalBundle,
    ),
  );
  final String arm64Before = await _sealDigest(options.arm64Bundle);
  final String x86_64Before = await _sealDigest(options.x86_64Bundle);
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-runtime-release-negative-',
  );
  try {
    await _expectFailure('missing-architecture', '/usr/bin/make', <String>[
      '-C',
      options.projectRoot,
      'runtime-architecture-check',
    ], 'RUNTIME_ARCH=arm64 or RUNTIME_ARCH=x86_64 is required');
    await _expectFailure('unsupported-architecture', '/usr/bin/make', <String>[
      '-C',
      options.projectRoot,
      'RUNTIME_ARCH=host',
      'runtime-architecture-check',
    ], 'RUNTIME_ARCH=arm64 or RUNTIME_ARCH=x86_64 is required');
    await _expectFailure(
      'duplicate-expected-slice-cli',
      Platform.resolvedExecutable,
      _auditorArguments(options, options.arm64Bundle, 'arm64,arm64'),
      'duplicate architecture',
    );
    if (sameStringSet(const <String>[
      'arm64',
      'arm64',
      'x86_64',
    ], supportedRuntimeArchitectures)) {
      throw const _NegativeTestException(
        'exact-slice helper normalized a duplicate architecture',
      );
    }
    stdout.writeln('RUNTIME_RELEASE_NEGATIVE_PASS case=duplicate-slice-parser');

    final String wrapperArm = '${temporary.path}/WrapperArm.app';
    final String wrapperX86 = '${temporary.path}/WrapperX86.app';
    await _copyBundle(options.arm64Bundle, wrapperArm);
    await _copyBundle(options.x86_64Bundle, wrapperX86);
    final String wrapperArmSeal = await _sealDigest(wrapperArm);
    await _expectPass(
      'make-wrapper-output-overrides',
      '/usr/bin/make',
      <String>[
        '-C',
        options.projectRoot,
        'ARM64_RELEASE_BUNDLE=$wrapperArm',
        'ARM64_RELEASE_AUDIT_REPORT=${options.arm64Report}',
        'X86_64_RELEASE_BUNDLE=$wrapperX86',
        'X86_64_RELEASE_AUDIT_REPORT=${options.x86_64Report}',
        'UNIVERSAL_RELEASE_BUILD_DIR=$wrapperArm',
        'universal-release-aot-assemble',
      ],
    );
    if (await _sealDigest(wrapperArm) != wrapperArmSeal) {
      throw const _NegativeTestException(
        'Make wrapper changed its aliased thin bundle',
      );
    }
    await _validatePublishedPair(options, options.universalArtifactDirectory);
    stdout.writeln(
      'RUNTIME_RELEASE_NEGATIVE_PASS '
      'case=make-wrapper-output-overrides-ignored',
    );

    final String insideThin =
        '$wrapperArm/Contents/Resources/prospective-universal';
    await _expectPass(
      'make-wrapper-build-dir-inside-thin',
      '/usr/bin/make',
      <String>[
        '-C',
        options.projectRoot,
        'ARM64_RELEASE_BUNDLE=$wrapperArm',
        'ARM64_RELEASE_AUDIT_REPORT=${options.arm64Report}',
        'X86_64_RELEASE_BUNDLE=$wrapperX86',
        'X86_64_RELEASE_AUDIT_REPORT=${options.x86_64Report}',
        'UNIVERSAL_RELEASE_BUILD_DIR=$insideThin',
        'universal-release-aot-assemble',
      ],
    );
    await _expectAbsent(insideThin);
    if (await _sealDigest(wrapperArm) != wrapperArmSeal) {
      throw const _NegativeTestException(
        'Make wrapper pre-wrote inside a thin input',
      );
    }
    stdout.writeln(
      'RUNTIME_RELEASE_NEGATIVE_PASS '
      'case=make-wrapper-build-dir-inside-thin-ignored',
    );

    await _expectFailure(
      'assembler-output-alias',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: options.arm64Bundle,
      ),
      'Universal artifact directory aliases, contains, or is inside',
    );
    final String directInsideThin =
        '${options.arm64Bundle}/Contents/Resources/prospective-universal';
    await _expectFailure(
      'assembler-build-dir-inside-thin',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: directInsideThin,
      ),
      'Universal artifact directory aliases, contains, or is inside',
    );
    await _expectAbsent(directInsideThin);

    final String caseVariant =
        '${File(options.arm64Bundle).parent.path}/dartterminal.app';
    final RuntimePathSnapshot caseSnapshot = await runtimePathSnapshot(
      caseVariant,
    );
    if (caseSnapshot.targetIdentity ==
        (await runtimePathSnapshot(options.arm64Bundle)).targetIdentity) {
      await _expectFailure(
        'case-variant-output-alias',
        Platform.resolvedExecutable,
        _assemblerArguments(
          options,
          arm64: options.arm64Bundle,
          arm64Report: options.arm64Report,
          x86_64: options.x86_64Bundle,
          x86_64Report: options.x86_64Report,
          outputDirectory: caseVariant,
        ),
        'Universal artifact directory aliases, contains, or is inside',
      );
    } else {
      stdout.writeln(
        'RUNTIME_RELEASE_NEGATIVE_SKIP case=case-variant-output-alias '
        'reason=case-sensitive-volume',
      );
    }

    final String unicodeBundle = '${temporary.path}/Thin-\u00e9.app';
    final String unicodeVariant = '${temporary.path}/Thin-e\u0301.app';
    final String unicodeReport = '${temporary.path}/thin-unicode.json';
    await _copyBundle(options.arm64Bundle, unicodeBundle);
    await _writePassingReceipt(options, unicodeBundle, 'arm64', unicodeReport);
    final RuntimePathSnapshot unicodeSnapshot = await runtimePathSnapshot(
      unicodeVariant,
    );
    if (unicodeSnapshot.targetIdentity ==
        (await runtimePathSnapshot(unicodeBundle)).targetIdentity) {
      await _expectFailure(
        'unicode-normalization-output-alias',
        Platform.resolvedExecutable,
        _assemblerArguments(
          options,
          arm64: unicodeBundle,
          arm64Report: unicodeReport,
          x86_64: options.x86_64Bundle,
          x86_64Report: options.x86_64Report,
          outputDirectory: unicodeVariant,
        ),
        'Universal artifact directory aliases, contains, or is inside',
      );
    } else {
      stdout.writeln(
        'RUNTIME_RELEASE_NEGATIVE_SKIP case=unicode-normalization-output-alias '
        'reason=normalization-sensitive-volume',
      );
    }

    final String hardLinkedReceipt =
        '${temporary.path}/hard-linked-receipt.json';
    await _expectPass('hard-link receipt fixture', '/bin/ln', <String>[
      options.arm64Report,
      hardLinkedReceipt,
    ]);
    await _expectFailure(
      'hard-link-thin-receipt-alias',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: hardLinkedReceipt,
        outputDirectory: '${temporary.path}/hard-link-output',
      ),
      'x86_64 thin receipt aliases or contains arm64 thin receipt',
    );

    final String reportInsideBundle =
        '${temporary.path}/ReportInsideBundle.app';
    await _copyBundle(options.x86_64Bundle, reportInsideBundle);
    final String reportInsideSeal = await _sealDigest(reportInsideBundle);
    final String forbiddenReport =
        '$reportInsideBundle/Contents/Resources/forbidden-audit.json';
    await _expectFailure(
      'bundle-audit-report-inside-bundle',
      Platform.resolvedExecutable,
      _auditorArguments(
        options,
        reportInsideBundle,
        'x86_64',
        outputReport: forbiddenReport,
      ),
      'runtime audit report aliases, contains, or is inside audited bundle',
    );
    await _expectAbsent(forbiddenReport);
    if (await _sealDigest(reportInsideBundle) != reportInsideSeal) {
      throw const _NegativeTestException(
        'rejected in-bundle audit report changed the bundle',
      );
    }

    final String immutableReceiptBefore = await runtimeSha256File(
      options.x86_64Report,
    );
    await _expectFailure(
      'existing-thin-receipt-is-immutable',
      Platform.resolvedExecutable,
      _auditorArguments(
        options,
        options.x86_64Bundle,
        'x86_64',
        outputReport: options.x86_64Report,
      ),
      'runtime audit report already exists and is immutable',
    );
    await _expectPass(
      'Make thin audit performs read-only receipt validation',
      '/usr/bin/make',
      <String>[
        '-C',
        options.projectRoot,
        'RUNTIME_ARCH=x86_64',
        'release-aot-audit',
      ],
    );
    if (await runtimeSha256File(options.x86_64Report) !=
        immutableReceiptBefore) {
      throw const _NegativeTestException(
        'fresh thin audit rewrote its immutable receipt',
      );
    }
    stdout.writeln(
      'RUNTIME_RELEASE_NEGATIVE_PASS '
      'case=make-thin-audit-read-only-validation',
    );

    final String handoffDeveloper = '${temporary.path}/HandoffDeveloper.app';
    final String handoffRelease = '${temporary.path}/HandoffRelease.app';
    final String handoffDeveloperReport =
        '${temporary.path}/handoff-developer.json';
    final String handoffReleaseReport =
        '${temporary.path}/handoff-release.json';
    await _copyBundle(options.x86_64Bundle, handoffDeveloper);
    await _copyBundle(options.x86_64Bundle, handoffRelease);
    await File(options.x86_64Report).copy(handoffDeveloperReport);
    await File(options.x86_64Report).copy(handoffReleaseReport);
    final String realSmoke =
        '${options.projectRoot}/tool/'
        'runtime_integration_smoke.dart';
    final String forbiddenEvidence =
        '${options.universalBundle}/Contents/forbidden-evidence.json';
    await _expectFailure(
      'handoff-evidence-inside-input',
      Platform.resolvedExecutable,
      _handoffArguments(
        options,
        developerBundle: handoffDeveloper,
        developerReport: handoffDeveloperReport,
        releaseBundle: handoffRelease,
        releaseReport: handoffReleaseReport,
        smoke: realSmoke,
        evidence: forbiddenEvidence,
      ),
      'Intel-native evidence output aliases, contains, or is inside '
          'Universal bundle',
    );
    await _expectAbsent(forbiddenEvidence);

    final File fakeSmoke = File('${temporary.path}/fake-smoke.dart');
    await fakeSmoke.writeAsString(
      "void main() => print('launch_architecture=native');\n",
      flush: true,
    );
    await _expectFailure(
      'fake-smoke-harness',
      Platform.resolvedExecutable,
      _handoffArguments(
        options,
        developerBundle: handoffDeveloper,
        developerReport: handoffDeveloperReport,
        releaseBundle: handoffRelease,
        releaseReport: handoffReleaseReport,
        smoke: fakeSmoke.path,
        evidence: '${temporary.path}/fake-smoke-evidence.json',
      ),
      'runtime tool source identity mismatch: '
          'dart_terminal:tool/runtime_integration_smoke.dart',
    );

    final String staleReceipt = '${temporary.path}/StaleReceipt.app';
    await _copyBundle(options.x86_64Bundle, staleReceipt);
    await File('$staleReceipt/Contents/Resources/DART_SDK_LICENSE.txt')
        .writeAsString('\nstale receipt\n', mode: FileMode.append, flush: true);
    await _signOuter(staleReceipt);
    final String staleOutput = '${temporary.path}/stale-receipt-output';
    await _expectFailure(
      'stale-audit-receipt',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: staleReceipt,
        x86_64Report: options.x86_64Report,
        outputDirectory: staleOutput,
      ),
      'runtime audit receipt does not match',
    );
    await _expectAbsent(staleOutput);

    final String provenanceMismatch =
        '${temporary.path}/ProvenanceMismatch.app';
    final String provenanceReport =
        '${temporary.path}/provenance-mismatch.json';
    await _copyBundle(options.x86_64Bundle, provenanceMismatch);
    await _rewriteManifest(provenanceMismatch, (Map<String, Object?> manifest) {
      final Map<String, Object?> source = runtimeStringMap(
        manifest['source'],
        'source provenance',
      );
      final Map<String, Object?> repository = runtimeStringMap(
        source['repository'],
        'source repository',
      );
      repository['revision'] = 'ffffffffffffffffffffffffffffffffffffffff';
    });
    await _writePassingReceipt(
      options,
      provenanceMismatch,
      'x86_64',
      provenanceReport,
    );
    final String provenanceOutput =
        '${temporary.path}/provenance-mismatch-output';
    await _expectFailure(
      'common-provenance-mismatch',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: provenanceMismatch,
        x86_64Report: provenanceReport,
        outputDirectory: provenanceOutput,
      ),
      'thin common provenance/build manifests do not match',
    );
    await _expectAbsent(provenanceOutput);

    final String relocatedLane = '${temporary.path}/RelocatedLane.app';
    final String relocatedLaneReport = '${temporary.path}/relocated-lane.json';
    await _copyBundle(options.x86_64Bundle, relocatedLane);
    await _rewriteManifest(relocatedLane, (Map<String, Object?> manifest) {
      const String projectRoot = '/relocated/project';
      const String appKitRoot = '/relocated/dart_appkit';
      const String engineRoot = '/relocated/engine';
      const String dartSdkRoot = '/relocated/dart-sdk';
      const String engineOutput = '/relocated/engine/xcodebuild/ProductX64';
      final Map<String, Object?> lane = runtimeStringMap(
        manifest['architecture_inputs'],
        'relocated architecture lane',
      );
      final Map<String, Object?> inputs = runtimeStringMap(
        lane['resolved_input_paths'],
        'relocated resolved inputs',
      );
      inputs['dart_engine'] = '$engineOutput/libdart_engine_aot_shared.dylib';
      inputs['kernel_compiler'] = '$engineOutput/bootstrap_gen_kernel.exe';
      inputs['platform_dill'] =
          '$engineOutput/clang_x64_shared/vm_platform.dill';
      inputs['snapshotter'] = '$engineOutput/gen_snapshot';
      final Map<String, Object?> packageConfig = runtimeStringMap(
        lane['package_config'],
        'relocated package config',
      );
      packageConfig['path'] = '$projectRoot/.dart_tool/package_config.json';
      packageConfig['raw_sha256'] = List<String>.filled(64, '1').join();
      packageConfig['pub_cache'] = 'file:///relocated/pub-cache';
      final Map<String, Object?> packageRoots = runtimeStringMap(
        packageConfig['resolved_package_roots'],
        'relocated package roots',
      );
      packageRoots['dart_terminal'] = projectRoot;
      packageRoots['dart_appkit'] = '$appKitRoot/packages/dart_appkit';
      final Map<String, Object?> environment = runtimeStringMap(
        lane['build_environment'],
        'relocated build environment',
      );
      final Map<String, Object?> environmentPaths = runtimeStringMap(
        environment['resolved_paths'],
        'relocated environment paths',
      );
      environmentPaths['project_root'] = projectRoot;
      environmentPaths['dart_appkit_root'] = appKitRoot;
      environmentPaths['dart_engine_root'] = engineRoot;
      environmentPaths['dart_sdk_root'] = dartSdkRoot;
      environmentPaths['runtime_build_root'] = '/relocated/runtime-build';
      environmentPaths['clang'] = '/relocated/toolchain/clang++';
      environmentPaths['sdk_root'] = '/relocated/macos-sdk';
      final Map<String, Object?> hostHashes = runtimeStringMap(
        environment['host_tool_sha256'],
        'relocated host tool hashes',
      );
      hostHashes['clang'] = List<String>.filled(64, '2').join();
      final Map<String, Object?> buildTools = runtimeStringMap(
        lane['build_tools'],
        'relocated build tools',
      );
      final Map<String, Object?> dart = runtimeStringMap(
        buildTools['dart'],
        'relocated Dart tool',
      );
      dart['path'] = '$dartSdkRoot/bin/dart';
      (dart['arguments']! as List<Object?>)[1] =
          '$projectRoot/tool/runtime_build_fingerprint.dart';
      final Map<String, Object?> gn = runtimeStringMap(
        buildTools['engine_gn'],
        'relocated GN tool',
      );
      gn['path'] = '$engineRoot/tools/gn.py';
      final Map<String, Object?> ninja = runtimeStringMap(
        buildTools['engine_ninja'],
        'relocated Ninja tool',
      );
      ninja['path'] = '$engineRoot/buildtools/ninja/ninja';
      (ninja['arguments']! as List<Object?>)[1] = engineOutput;
      final Map<String, Object?> python = runtimeStringMap(
        buildTools['engine_python'],
        'relocated Python tool',
      );
      (python['arguments']! as List<Object?>)[0] = '$engineRoot/tools/gn.py';
    });
    await _writePassingReceipt(
      options,
      relocatedLane,
      'x86_64',
      relocatedLaneReport,
    );
    final String relocatedOutput = '${temporary.path}/relocated-output';
    await _expectPass(
      'semantically equivalent relocated lane assembly',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: relocatedLane,
        x86_64Report: relocatedLaneReport,
        outputDirectory: relocatedOutput,
      ),
    );
    await _validatePublishedPair(options, relocatedOutput);
    stdout.writeln(
      'RUNTIME_RELEASE_NEGATIVE_PASS '
      'case=semantically-equivalent-relocated-roots',
    );

    final String configurationMismatch =
        '${temporary.path}/ConfigurationMismatch.app';
    await _copyBundle(options.x86_64Bundle, configurationMismatch);
    await _rewriteManifest(configurationMismatch, (
      Map<String, Object?> manifest,
    ) {
      manifest['engine_configuration'] = 'release';
    });
    await _expectFailure(
      'configuration-mismatch',
      Platform.resolvedExecutable,
      _auditorArguments(options, configurationMismatch, 'x86_64'),
      'Engine configuration release != product',
    );

    final String laneMismatch = '${temporary.path}/LaneMismatch.app';
    await _copyBundle(options.x86_64Bundle, laneMismatch);
    await _rewriteManifest(laneMismatch, (Map<String, Object?> manifest) {
      final Map<String, Object?> lane = runtimeStringMap(
        manifest['architecture_inputs'],
        'architecture lane',
      );
      final Map<String, Object?> gn = runtimeStringMap(
        lane['engine_gn_arguments'],
        'architecture GN arguments',
      );
      gn['target_cpu'] = '"arm64"';
    });
    await _expectFailure(
      'architecture-lane-gn-mismatch',
      Platform.resolvedExecutable,
      _auditorArguments(options, laneMismatch, 'x86_64'),
      'Engine GN architecture does not match x86_64',
    );

    final List<(String, void Function(Map<String, Object?>), String)>
    toolCoherenceCases =
        <(String, void Function(Map<String, Object?>), String)>[
          (
            'resolved-path-extra-role',
            (Map<String, Object?> manifest) {
              _manifestEnvironmentPaths(manifest)['forged_root'] =
                  '/forged/root';
            },
            'build environment resolved-path schema mismatch',
          ),
          (
            'dart-tool-root-mismatch',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'dart')['path'] = '/forged/bin/dart';
            },
            'Dart executable path/SDK identity mismatch',
          ),
          (
            'dart-tool-script-mismatch',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> dart = _manifestBuildTool(
                manifest,
                'dart',
              );
              (dart['arguments']! as List<Object?>)[1] =
                  '/forged/tool/runtime_build_fingerprint.dart';
            },
            'Dart executable arguments mismatch',
          ),
          (
            'gn-tool-root-mismatch',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'engine_gn')['path'] =
                  '/forged/tools/gn.py';
            },
            'Engine GN invocation mismatch',
          ),
          (
            'python-gn-script-mismatch',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> python = _manifestBuildTool(
                manifest,
                'engine_python',
              );
              (python['arguments']! as List<Object?>)[0] =
                  '/forged/tools/gn.py';
            },
            'Engine Python identity/invocation mismatch',
          ),
          (
            'ninja-tool-root-mismatch',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'engine_ninja')['path'] =
                  '/forged/buildtools/ninja/ninja';
            },
            'Engine Ninja invocation mismatch',
          ),
          (
            'ninja-output-root-mismatch',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> ninja = _manifestBuildTool(
                manifest,
                'engine_ninja',
              );
              (ninja['arguments']! as List<Object?>)[1] =
                  '/forged/xcodebuild/ProductX64';
            },
            'Engine Ninja invocation mismatch',
          ),
          (
            'engine-input-root-mismatch',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> inputs = runtimeStringMap(
                _manifestLane(manifest)['resolved_input_paths'],
                'negative-test resolved Engine inputs',
              );
              inputs['snapshotter'] =
                  '/forged/xcodebuild/ProductX64/gen_snapshot';
            },
            'resolved Engine input paths are incoherent',
          ),
          (
            'package-root-mismatch',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> packageConfig = runtimeStringMap(
                _manifestLane(manifest)['package_config'],
                'negative-test package config',
              );
              final Map<String, Object?> roots = runtimeStringMap(
                packageConfig['resolved_package_roots'],
                'negative-test package roots',
              );
              roots['dart_terminal'] = '/forged/project';
            },
            'package roots are invalid',
          ),
        ];
    for (final (
          String label,
          void Function(Map<String, Object?>) mutate,
          String expected,
        )
        in toolCoherenceCases) {
      final String bundle = '${temporary.path}/ToolCoherence-$label.app';
      await _copyBundle(options.x86_64Bundle, bundle);
      await _rewriteManifest(bundle, mutate);
      await _expectFailure(
        label,
        Platform.resolvedExecutable,
        _auditorArguments(options, bundle, 'x86_64'),
        expected,
      );
    }

    final List<(String, void Function(Map<String, Object?>))>
    thinArchitectureMetadataCases =
        <(String, void Function(Map<String, Object?>))>[
          for (final String role in <String>[
            'dart',
            'engine_ninja',
            'engine_python',
            'make',
            'snapshotter_runner',
          ])
            (
              'tool-$role-architecture-unknown',
              (Map<String, Object?> manifest) {
                _manifestBuildTool(manifest, role)['architectures'] = <Object?>[
                  'forged',
                ];
              },
            ),
          for (final String role in <String>[
            'dart_engine',
            'kernel_compiler',
            'snapshotter',
          ])
            (
              'input-$role-architecture-unknown',
              (Map<String, Object?> manifest) {
                final Map<String, Object?> architectures = runtimeStringMap(
                  _manifestLane(manifest)['input_binary_architectures'],
                  'negative-test input architectures',
                );
                architectures[role] = <Object?>['forged'];
              },
            ),
          (
            'host-clang-architecture-unknown',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> environment = runtimeStringMap(
                _manifestLane(manifest)['build_environment'],
                'negative-test build environment',
              );
              final Map<String, Object?> architectures = runtimeStringMap(
                environment['host_tool_architectures'],
                'negative-test host tool architectures',
              );
              architectures['clang'] = <Object?>['forged'];
            },
          ),
          (
            'tool-architecture-null',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'dart')['architectures'] = <Object?>[
                null,
              ];
            },
          ),
          (
            'input-architecture-null',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> architectures = runtimeStringMap(
                _manifestLane(manifest)['input_binary_architectures'],
                'negative-test input architectures',
              );
              architectures['kernel_compiler'] = <Object?>[null];
            },
          ),
          (
            'host-architecture-null',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> environment = runtimeStringMap(
                _manifestLane(manifest)['build_environment'],
                'negative-test build environment',
              );
              final Map<String, Object?> architectures = runtimeStringMap(
                environment['host_tool_architectures'],
                'negative-test host tool architectures',
              );
              architectures['clang'] = <Object?>[null];
            },
          ),
          (
            'tool-architecture-duplicate',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'engine_python')['architectures'] =
                  <Object?>['arm64e', 'arm64e'];
            },
          ),
          (
            'input-architecture-duplicate',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> architectures = runtimeStringMap(
                _manifestLane(manifest)['input_binary_architectures'],
                'negative-test input architectures',
              );
              architectures['snapshotter'] = <Object?>['x86_64', 'x86_64'];
            },
          ),
          (
            'host-architecture-duplicate',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> environment = runtimeStringMap(
                _manifestLane(manifest)['build_environment'],
                'negative-test build environment',
              );
              final Map<String, Object?> architectures = runtimeStringMap(
                environment['host_tool_architectures'],
                'negative-test host tool architectures',
              );
              architectures['clang'] = <Object?>['arm64', 'arm64'];
            },
          ),
          (
            'tool-architecture-noncanonical-order',
            (Map<String, Object?> manifest) {
              _manifestBuildTool(manifest, 'engine_python')['architectures'] =
                  <Object?>['x86_64', 'arm64e'];
            },
          ),
          (
            'input-architecture-noncanonical-order',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> architectures = runtimeStringMap(
                _manifestLane(manifest)['input_binary_architectures'],
                'negative-test input architectures',
              );
              architectures['kernel_compiler'] = <Object?>['x86_64', 'arm64'];
            },
          ),
          (
            'host-architecture-noncanonical-order',
            (Map<String, Object?> manifest) {
              final Map<String, Object?> environment = runtimeStringMap(
                _manifestLane(manifest)['build_environment'],
                'negative-test build environment',
              );
              final Map<String, Object?> architectures = runtimeStringMap(
                environment['host_tool_architectures'],
                'negative-test host tool architectures',
              );
              architectures['clang'] = <Object?>['x86_64', 'arm64e'];
            },
          ),
        ];
    for (final (String label, void Function(Map<String, Object?>) mutate)
        in thinArchitectureMetadataCases) {
      final String bundle = '${temporary.path}/Architecture-$label.app';
      await _copyBundle(options.x86_64Bundle, bundle);
      await _rewriteManifest(bundle, mutate);
      await _expectFailure(
        label,
        Platform.resolvedExecutable,
        _auditorArguments(options, bundle, 'x86_64'),
        'must be a canonical unique Mach-O architecture list',
      );
    }

    final List<(String, List<Object?>)> universalArchitectureCases =
        <(String, List<Object?>)>[
          ('universal-architecture-unknown', <Object?>['forged']),
          ('universal-architecture-null', <Object?>[null]),
          (
            'universal-architecture-duplicate',
            <Object?>['arm64', 'x86_64', 'x86_64'],
          ),
          (
            'universal-architecture-noncanonical-order',
            <Object?>['x86_64', 'arm64'],
          ),
        ];
    for (final (String label, List<Object?> architectures)
        in universalArchitectureCases) {
      final String bundle = '${temporary.path}/Architecture-$label.app';
      await _copyBundle(options.universalBundle, bundle);
      await _rewriteManifest(bundle, (Map<String, Object?> manifest) {
        _manifestLane(manifest)['architectures'] = architectures;
      });
      await _expectFailure(
        label,
        Platform.resolvedExecutable,
        _auditorArguments(options, bundle, 'arm64,x86_64'),
        'must be a canonical unique Mach-O architecture list',
      );
    }

    for (final String relative in <String>[
      for (final String source in runtimeProjectProvenanceFiles)
        if (source.startsWith('tool/')) source,
    ]) {
      final String label = relative.replaceAll('/', '-').replaceAll('.', '-');
      final String bundle = '${temporary.path}/MissingSource-$label.app';
      await _copyBundle(options.x86_64Bundle, bundle);
      await _rewriteManifest(bundle, (Map<String, Object?> manifest) {
        final Map<String, Object?> source = runtimeStringMap(
          manifest['source'],
          'negative-test source inventory',
        );
        final Map<String, Object?> hashes = runtimeStringMap(
          source['input_sha256'],
          'negative-test source hashes',
        );
        hashes.remove('dart_terminal:$relative');
      });
      await _expectFailure(
        'missing-required-source-$label',
        Platform.resolvedExecutable,
        _auditorArguments(options, bundle, 'x86_64'),
        'source inventory misses dart_terminal:$relative',
      );
    }

    final String resourceMismatch = '${temporary.path}/ResourceMismatch.app';
    final String resourceReport = '${temporary.path}/resource-mismatch.json';
    await _copyBundle(options.x86_64Bundle, resourceMismatch);
    await File(
      '$resourceMismatch/Contents/Resources/DART_SDK_LICENSE.txt',
    ).writeAsString('\nresource drift\n', mode: FileMode.append, flush: true);
    await _signOuter(resourceMismatch);
    await _writePassingReceipt(
      options,
      resourceMismatch,
      'x86_64',
      resourceReport,
    );

    final String unexpectedMach = '${temporary.path}/UnexpectedMach.app';
    await _copyBundle(options.x86_64Bundle, unexpectedMach);
    await File(
      '$unexpectedMach/Contents/Frameworks/libdart_engine_aot_shared.dylib',
    ).copy('$unexpectedMach/Contents/Resources/unexpected-mach.bin');
    await _signOuter(unexpectedMach);
    await _expectFailure(
      'unexpected-mach-o',
      Platform.resolvedExecutable,
      _auditorArguments(options, unexpectedMach, 'x86_64'),
      'Mach-O layout',
    );

    final String dependencyMismatch =
        '${temporary.path}/DependencyMismatch.app';
    await _copyBundle(options.x86_64Bundle, dependencyMismatch);
    final String dependencyLauncher =
        '$dependencyMismatch/Contents/MacOS/dart_terminal_release_aot';
    await _expectPass(
      'mutate launcher dependency',
      '/usr/bin/install_name_tool',
      <String>[
        '-change',
        '@rpath/libdart_engine_aot_shared.dylib',
        '@loader_path/evil.dylib',
        dependencyLauncher,
      ],
    );
    await _sign(dependencyLauncher);
    await _signOuter(dependencyMismatch);
    await _expectFailure(
      'strict-launcher-dependency',
      Platform.resolvedExecutable,
      _auditorArguments(options, dependencyMismatch, 'x86_64'),
      'launcher x86_64 dependencies',
    );

    final String installNameMismatch =
        '${temporary.path}/InstallNameMismatch.app';
    await _copyBundle(options.x86_64Bundle, installNameMismatch);
    final String installNameSnapshot =
        '$installNameMismatch/Contents/Resources/application.aot';
    await _expectPass(
      'mutate snapshot install name',
      '/usr/bin/install_name_tool',
      <String>['-id', '@rpath/evil.aot', installNameSnapshot],
    );
    await _sign(installNameSnapshot);
    await _signOuter(installNameMismatch);
    await _expectFailure(
      'strict-snapshot-install-name',
      Platform.resolvedExecutable,
      _auditorArguments(options, installNameMismatch, 'x86_64'),
      'aot_snapshot x86_64 install names',
    );

    final String rpathMismatch = '${temporary.path}/RpathMismatch.app';
    await _copyBundle(options.x86_64Bundle, rpathMismatch);
    final String rpathLauncher =
        '$rpathMismatch/Contents/MacOS/dart_terminal_release_aot';
    await _expectPass(
      'mutate launcher rpath',
      '/usr/bin/install_name_tool',
      <String>[
        '-rpath',
        '@executable_path/../Frameworks',
        '@executable_path/..',
        rpathLauncher,
      ],
    );
    await _sign(rpathLauncher);
    await _signOuter(rpathMismatch);
    await _expectFailure(
      'strict-launcher-rpath',
      Platform.resolvedExecutable,
      _auditorArguments(options, rpathMismatch, 'x86_64'),
      'launcher x86_64 LC_RPATH values',
    );

    final String entitlementMismatch =
        '${temporary.path}/EntitlementMismatch.app';
    await _copyBundle(options.x86_64Bundle, entitlementMismatch);
    final File entitlements = File('${temporary.path}/forbidden.plist');
    await entitlements.writeAsString(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key>'
      '<true/></dict></plist>\n',
      flush: true,
    );
    await _sign(
      '$entitlementMismatch/Contents/Resources/application.aot',
      entitlements: entitlements.path,
    );
    await _signOuter(entitlementMismatch);
    await _expectFailure(
      'entitlement-not-allowed',
      Platform.resolvedExecutable,
      _auditorArguments(options, entitlementMismatch, 'x86_64'),
      'entitlements are not allowed',
    );

    final String unsignedSnapshot = '${temporary.path}/UnsignedSnapshot.app';
    await _copyBundle(options.x86_64Bundle, unsignedSnapshot);
    await _expectPass(
      'remove nested snapshot signature',
      '/usr/bin/codesign',
      <String>[
        '--remove-signature',
        '$unsignedSnapshot/Contents/Resources/application.aot',
      ],
    );
    await _signOuter(unsignedSnapshot);
    await _expectFailure(
      'nested-snapshot-signature',
      Platform.resolvedExecutable,
      _auditorArguments(options, unsignedSnapshot, 'x86_64'),
      'codesign failed',
    );

    final String extraSlice = '${temporary.path}/ExtraSlice.app';
    await _copyBundle(options.universalBundle, extraSlice);
    await _replaceWithExtraSlice(extraSlice);
    await _expectFailure(
      'actual-extra-fat-slice',
      Platform.resolvedExecutable,
      _auditorArguments(options, extraSlice, 'arm64,x86_64'),
      'architectures arm64,arm64e,x86_64 != arm64,x86_64',
    );

    final String malformedDuplicate =
        '${temporary.path}/MalformedDuplicate.app';
    await _copyBundle(options.universalBundle, malformedDuplicate);
    await _replaceWithMalformedDuplicateHeader(malformedDuplicate);
    await _expectFailure(
      'malformed-duplicate-fat-record',
      Platform.resolvedExecutable,
      _auditorArguments(options, malformedDuplicate, 'arm64,x86_64'),
      'Mach-O layout',
    );

    await _expectFailure(
      'thin-claimed-universal',
      Platform.resolvedExecutable,
      _auditorArguments(options, options.arm64Bundle, 'arm64,x86_64'),
      'architectures arm64 != arm64,x86_64',
    );

    final String lastGoodDirectory = '${temporary.path}/last-good';
    final String lastGood = '$lastGoodDirectory/DartTerminal.app';
    final String lastGoodReport = '$lastGoodDirectory/universal-audit.json';
    await _expectPass(
      'initial atomic publication',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: lastGoodDirectory,
      ),
    );
    final String lastGoodGeneration = await _validatePublishedPair(
      options,
      lastGoodDirectory,
    );
    final String lastGoodDigest = await _sealDigest(lastGoodDirectory);
    final String lastGoodReportDigest = await runtimeSha256File(lastGoodReport);
    await _expectFailure(
      'failed-replacement-preserves-last-good',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: resourceMismatch,
        x86_64Report: resourceReport,
        outputDirectory: lastGoodDirectory,
      ),
      'non-Mach resource differs',
    );
    if (await _sealDigest(lastGoodDirectory) != lastGoodDigest ||
        await runtimeSha256File(lastGoodReport) != lastGoodReportDigest) {
      throw const _NegativeTestException(
        'failed replacement changed the last-good artifact directory',
      );
    }
    await _expectPass(
      'atomic replacement of existing output',
      Platform.resolvedExecutable,
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: lastGoodDirectory,
      ),
    );
    await _expectPass(
      'replacement exact-slice audit',
      Platform.resolvedExecutable,
      _auditorArguments(options, lastGood, 'arm64,x86_64'),
    );
    stdout.writeln(
      'RUNTIME_RELEASE_NEGATIVE_PASS case=atomic-existing-output-replacement',
    );

    final String competingDirectory = '${temporary.path}/competing-generation';
    await _expectPass(
      'competing publication fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, competingDirectory],
    );
    final File competingMarker = File(
      '$competingDirectory/competing-generation.txt',
    );
    await competingMarker.writeAsString('competing-generation\n', flush: true);
    final String competingDigest = await _sealDigest(competingDirectory);
    final String capturedOriginal = '${temporary.path}/captured-original';
    final Directory publicationBarrier = Directory(
      '${temporary.path}/publication-race-barrier',
    );
    await _expectPublicationRaceFailure(
      'concurrent-publisher-generation-preserved',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: lastGoodDirectory,
      ),
      publicationBarrier,
      (String _) async {
        await _expectFailure(
          'cooperative-publisher-lock',
          Platform.resolvedExecutable,
          _assemblerArguments(
            options,
            arm64: options.arm64Bundle,
            arm64Report: options.arm64Report,
            x86_64: options.x86_64Bundle,
            x86_64Report: options.x86_64Report,
            outputDirectory: lastGoodDirectory,
          ),
          'another Universal publisher is active',
        );
        await Directory(lastGoodDirectory).rename(capturedOriginal);
        await Directory(competingDirectory).rename(lastGoodDirectory);
      },
      'Universal destination changed during atomic publication',
    );
    if (await _sealDigest(lastGoodDirectory) != competingDigest ||
        !await File('$lastGoodDirectory/competing-generation.txt').exists() ||
        !await Directory(capturedOriginal).exists()) {
      throw const _NegativeTestException(
        'publication race deleted or replaced a competing generation',
      );
    }
    await _validatePublishedPair(options, lastGoodDirectory);

    final String stagingReplacementOutput =
        '${temporary.path}/staging-replacement-output';
    await _expectPass(
      'staging replacement output fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, stagingReplacementOutput],
    );
    final String stagingReplacementDigest = await _sealDigest(
      stagingReplacementOutput,
    );
    late String replacedStagingPath;
    late String ownedStagingPath;
    await _expectPublicationRaceFailure(
      'replaced-staging-entry-retained',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: stagingReplacementOutput,
      ),
      Directory('${temporary.path}/staging-replacement-barrier'),
      (String stagingPath) async {
        replacedStagingPath = stagingPath;
        ownedStagingPath = '$stagingPath.owned';
        await Directory(stagingPath).rename(ownedStagingPath);
        await Directory(stagingPath).create();
        await File('$stagingPath/foreign-marker.txt')
            .writeAsString('foreign-staging-entry\n', flush: true);
      },
      'Universal staging directory changed immediately before publication',
    );
    if (await _sealDigest(stagingReplacementOutput) !=
            stagingReplacementDigest ||
        !await Directory(ownedStagingPath).exists() ||
        !await File('$replacedStagingPath/foreign-marker.txt').exists()) {
      throw const _NegativeTestException(
        'staging replacement was published, deleted, or lost',
      );
    }

    final String stagingSymlinkOutput =
        '${temporary.path}/staging-symlink-output';
    await _expectPass(
      'staging symlink output fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, stagingSymlinkOutput],
    );
    final String stagingSymlinkDigest = await _sealDigest(stagingSymlinkOutput);
    late String stagingSymlinkPath;
    late String symlinkOwnedStagingPath;
    await _expectPublicationRaceFailure(
      'staging-symlink-entry-retained',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: stagingSymlinkOutput,
      ),
      Directory('${temporary.path}/staging-symlink-barrier'),
      (String stagingPath) async {
        stagingSymlinkPath = stagingPath;
        symlinkOwnedStagingPath = '$stagingPath.owned';
        await Directory(stagingPath).rename(symlinkOwnedStagingPath);
        await Link(stagingPath).create(symlinkOwnedStagingPath);
      },
      'Universal staging directory changed immediately before publication',
    );
    if (await _sealDigest(stagingSymlinkOutput) != stagingSymlinkDigest ||
        !await Directory(symlinkOwnedStagingPath).exists() ||
        await FileSystemEntity.type(stagingSymlinkPath, followLinks: false) !=
            FileSystemEntityType.link) {
      throw const _NegativeTestException(
        'staging symlink was published, followed by cleanup, or lost',
      );
    }

    final String syncCompleteOutput = '${temporary.path}/sync-complete-output';
    late String syncCompleteStagingPath;
    await _expectPublicationRaceFailure(
      'new-output-sync-failure-retains-complete-pair',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: syncCompleteOutput,
      ),
      Directory('${temporary.path}/sync-complete-barrier'),
      (String stagingPath) async {
        syncCompleteStagingPath = stagingPath;
      },
      'complete or competing public directory retained without rollback',
      barrierPoint: 'after-publish-before-sync',
      environment: const <String, String>{
        'DART_TERMINAL_UNIVERSAL_TEST_SYNC_FAILURE': 'after-publish',
      },
    );
    await _validatePublishedPair(options, syncCompleteOutput);
    if (await FileSystemEntity.type(
          syncCompleteStagingPath,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw const _NegativeTestException(
        'new-output sync failure left a mixed staging entry',
      );
    }

    final String existingSyncOutput = '${temporary.path}/existing-sync-output';
    await _expectPass(
      'existing sync output fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, existingSyncOutput],
    );
    final String existingSyncDigest = await _sealDigest(existingSyncOutput);
    await _expectPublicationRaceFailure(
      'existing-output-sync-failure-restores-last-good',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: existingSyncOutput,
      ),
      Directory('${temporary.path}/existing-sync-barrier'),
      (String _) async {},
      'injected post-publication sync failure',
      barrierPoint: 'after-publish-before-sync',
      environment: const <String, String>{
        'DART_TERMINAL_UNIVERSAL_TEST_SYNC_FAILURE': 'after-publish',
      },
    );
    if (await _sealDigest(existingSyncOutput) != existingSyncDigest) {
      throw const _NegativeTestException(
        'existing-output sync failure did not restore last-good pair',
      );
    }
    await _validatePublishedPair(options, existingSyncOutput);

    final String cleanupRaceOutput = '${temporary.path}/cleanup-race-output';
    await _expectPass(
      'cleanup race output fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, cleanupRaceOutput],
    );
    late String cleanupRaceStagingPath;
    final String capturedCleanupOld = '${temporary.path}/captured-cleanup-old';
    await _expectPublicationRaceFailure(
      'cleanup-replacement-retained',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: cleanupRaceOutput,
      ),
      Directory('${temporary.path}/cleanup-race-barrier'),
      (String stagingPath) async {
        cleanupRaceStagingPath = stagingPath;
        await Directory(stagingPath).rename(capturedCleanupOld);
        await Directory(stagingPath).create();
        await File('$stagingPath/cleanup-foreign-marker.txt')
            .writeAsString('cleanup-foreign-entry\n', flush: true);
      },
      'Universal staging changed before cleanup; replacement retained',
      barrierPoint: 'before-cleanup',
    );
    await _validatePublishedPair(options, cleanupRaceOutput);
    await _validatePublishedPair(options, capturedCleanupOld);
    if (!await File('$cleanupRaceStagingPath/cleanup-foreign-marker.txt')
        .exists()) {
      throw const _NegativeTestException(
        'cleanup race deleted the replacement staging directory',
      );
    }

    final String syncCompetingDirectory =
        '${temporary.path}/sync-competing-generation';
    await _expectPass(
      'sync competitor fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, syncCompetingDirectory],
    );
    await File('$syncCompetingDirectory/sync-competitor.txt')
        .writeAsString('sync-competitor\n', flush: true);
    final String syncCompetingDigest = await _sealDigest(
      syncCompetingDirectory,
    );
    final String syncRaceOutput = '${temporary.path}/sync-race-output';
    final String capturedSyncPublication =
        '${temporary.path}/captured-sync-publication';
    late String syncRaceStagingPath;
    await _expectPublicationRaceFailure(
      'new-output-sync-failure-retains-competing-generation',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: syncRaceOutput,
      ),
      Directory('${temporary.path}/sync-race-barrier'),
      (String stagingPath) async {
        syncRaceStagingPath = stagingPath;
        await Directory(syncRaceOutput).rename(capturedSyncPublication);
        await Directory(syncCompetingDirectory).rename(syncRaceOutput);
      },
      'complete or competing public directory retained without rollback',
      barrierPoint: 'after-publish-before-sync',
      environment: const <String, String>{
        'DART_TERMINAL_UNIVERSAL_TEST_SYNC_FAILURE': 'after-publish',
      },
    );
    if (await _sealDigest(syncRaceOutput) != syncCompetingDigest ||
        !await File('$syncRaceOutput/sync-competitor.txt').exists() ||
        !await Directory(capturedSyncPublication).exists() ||
        await FileSystemEntity.type(syncRaceStagingPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const _NegativeTestException(
        'sync failure moved, deleted, or replaced a competing generation',
      );
    }
    await _validatePublishedPair(options, capturedSyncPublication);

    final String existingSyncRaceOutput =
        '${temporary.path}/existing-sync-race-output';
    await _expectPass(
      'existing sync race output fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, existingSyncRaceOutput],
    );
    final String existingSyncCompetitor =
        '${temporary.path}/existing-sync-competitor';
    await _expectPass(
      'existing sync race competitor fixture copy',
      '/usr/bin/ditto',
      <String>['--noqtn', lastGoodDirectory, existingSyncCompetitor],
    );
    await File('$existingSyncCompetitor/existing-sync-competitor.txt')
        .writeAsString('existing-sync-competitor\n', flush: true);
    final String existingSyncCompetitorDigest = await _sealDigest(
      existingSyncCompetitor,
    );
    final String capturedExistingSyncNew =
        '${temporary.path}/captured-existing-sync-new';
    late String existingSyncRaceStaging;
    await _expectPublicationRaceFailure(
      'existing-sync-race-retains-competing-and-displaced-generations',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: existingSyncRaceOutput,
      ),
      Directory('${temporary.path}/existing-sync-race-barrier'),
      (String stagingPath) async {
        existingSyncRaceStaging = stagingPath;
        await Directory(existingSyncRaceOutput).rename(capturedExistingSyncNew);
        await Directory(existingSyncCompetitor).rename(existingSyncRaceOutput);
      },
      'Universal publication changed before sync rollback',
      barrierPoint: 'after-publish-before-sync',
      environment: const <String, String>{
        'DART_TERMINAL_UNIVERSAL_TEST_SYNC_FAILURE': 'after-publish',
      },
    );
    if (await _sealDigest(existingSyncRaceOutput) !=
            existingSyncCompetitorDigest ||
        !await File('$existingSyncRaceOutput/existing-sync-competitor.txt')
            .exists() ||
        !await Directory(existingSyncRaceStaging).exists() ||
        !await Directory(capturedExistingSyncNew).exists()) {
      throw const _NegativeTestException(
        'existing sync race lost a competing or displaced generation',
      );
    }
    await _validatePublishedPair(options, existingSyncRaceStaging);
    await _validatePublishedPair(options, capturedExistingSyncNew);

    final String beforeStageFaultDigest = await _sealDigest(lastGoodDirectory);
    await _expectFaultTermination(
      'pre-publication-crash-preserves-last-good-pair',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: lastGoodDirectory,
      ),
      'after-stage-sync',
    );
    if (await _sealDigest(lastGoodDirectory) != beforeStageFaultDigest ||
        await _validatePublishedPair(options, lastGoodDirectory) !=
            lastGoodGeneration) {
      throw const _NegativeTestException(
        'pre-publication crash changed the last-good artifact pair',
      );
    }

    await _expectFaultTermination(
      'publication-window-crash-keeps-complete-pair',
      _assemblerArguments(
        options,
        arm64: options.arm64Bundle,
        arm64Report: options.arm64Report,
        x86_64: options.x86_64Bundle,
        x86_64Report: options.x86_64Report,
        outputDirectory: lastGoodDirectory,
      ),
      'after-publish-before-sync',
    );
    final String postPublishGeneration = await _validatePublishedPair(
      options,
      lastGoodDirectory,
    );
    if (postPublishGeneration != lastGoodGeneration) {
      throw const _NegativeTestException(
        'publication-window crash exposed a mixed artifact generation',
      );
    }

    await _expectPass(
      'accepted Universal receipt revalidation',
      Platform.resolvedExecutable,
      <String>[
        options.auditor,
        '--mode=release-aot',
        '--expected-architectures=arm64,x86_64',
        '--deployment-target=${options.deploymentTarget}',
        '--validate-report=${options.universalReport}',
        options.universalBundle,
      ],
    );
  } finally {
    await temporary.delete(recursive: true);
  }
  if (await _sealDigest(options.arm64Bundle) != arm64Before ||
      await _sealDigest(options.x86_64Bundle) != x86_64Before) {
    throw const _NegativeTestException(
      'accepted signed thin input changed during negative tests',
    );
  }
  stdout.writeln('RUNTIME_RELEASE_NEGATIVE_TESTS_PASS');
}

Future<void> main(List<String> arguments) async {
  try {
    await _runTests(_parseOptions(arguments));
  } on Object catch (error) {
    stderr.writeln('RUNTIME_RELEASE_NEGATIVE_TESTS_FAIL $error');
    exitCode = 1;
  }
}
