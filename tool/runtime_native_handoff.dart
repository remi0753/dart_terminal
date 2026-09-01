import 'dart:convert';
import 'dart:io';

import 'src/runtime_release_support.dart';

final class _HandoffException implements Exception {
  const _HandoffException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.developerBundle,
    required this.developerReport,
    required this.releaseBundle,
    required this.releaseReport,
    required this.universalBundle,
    required this.universalReport,
    required this.deploymentTarget,
    required this.smoke,
    required this.hardwareLabel,
    required this.outputEvidence,
  });

  final String developerBundle;
  final String developerReport;
  final String releaseBundle;
  final String releaseReport;
  final String universalBundle;
  final String universalReport;
  final String deploymentTarget;
  final String smoke;
  final String hardwareLabel;
  final String outputEvidence;
}

final class _ValidatedInputs {
  const _ValidatedInputs({
    required this.evidenceGuard,
    required this.toolHashes,
  });

  final RuntimeWriteDestinationGuard evidenceGuard;
  final Map<String, String> toolHashes;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _HandoffException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw _HandoffException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> expected = <String>{
    'developer-jit-bundle',
    'developer-jit-report',
    'release-aot-bundle',
    'release-aot-report',
    'universal-bundle',
    'universal-report',
    'deployment-target',
    'smoke',
    'hardware-label',
    'output-evidence',
  };
  final Set<String> unknown = values.keys.toSet().difference(expected);
  final Set<String> missing = expected.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _HandoffException(
      'unknown=${unknown.join(',')} missing=${missing.join(',')}',
    );
  }
  for (final String name in <String>[
    'developer-jit-bundle',
    'developer-jit-report',
    'release-aot-bundle',
    'release-aot-report',
    'universal-bundle',
    'universal-report',
    'smoke',
    'output-evidence',
  ]) {
    if (!File(values[name]!).isAbsolute) {
      throw _HandoffException('--$name must be an absolute path');
    }
  }
  return _Options(
    developerBundle: values['developer-jit-bundle']!,
    developerReport: values['developer-jit-report']!,
    releaseBundle: values['release-aot-bundle']!,
    releaseReport: values['release-aot-report']!,
    universalBundle: values['universal-bundle']!,
    universalReport: values['universal-report']!,
    deploymentTarget: values['deployment-target']!,
    smoke: values['smoke']!,
    hardwareLabel: values['hardware-label']!,
    outputEvidence: values['output-evidence']!,
  );
}

Future<String> _stdout(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw _HandoffException(
      '${executable.split('/').last} failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<String> _sysctl(String name, {bool allowMissing = false}) async {
  final ProcessResult result = await Process.run('/usr/sbin/sysctl', <String>[
    '-n',
    name,
  ]);
  if (result.exitCode != 0) {
    if (allowMissing) {
      return 'unavailable';
    }
    throw _HandoffException(
      'sysctl $name failed: ${result.stdout}${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<Map<String, Object?>> _runSmoke(
  String script,
  RuntimeMode mode,
  String bundle,
) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>[script, '--mode=${mode.name}', bundle],
    environment: const <String, String>{'DART_SUPPRESS_ANALYTICS': 'true'},
    includeParentEnvironment: true,
  );
  stopwatch.stop();
  if (result.exitCode != 0) {
    throw _HandoffException(
      '${mode.name} native smoke failed (${result.exitCode}): '
      '${result.stdout}${result.stderr}',
    );
  }
  final String output = (result.stdout as String).trim();
  if (!output.contains('launch_architecture=native')) {
    throw _HandoffException(
      '${mode.name} smoke was not reported as native: $output',
    );
  }
  return <String, Object?>{
    'mode': mode.name,
    'bundle': Directory(bundle).absolute.path,
    'elapsed_ms': stopwatch.elapsedMilliseconds,
    'observation': output,
  };
}

Future<_ValidatedInputs> _validateStaticInputs(_Options options) async {
  final RuntimeWriteDestinationGuard evidenceGuard =
      await runtimeValidateWriteDestination(
        description: 'Intel-native evidence output',
        destination: options.outputEvidence,
        protectedPaths: <String, String>{
          'developer-JIT bundle': options.developerBundle,
          'developer-JIT receipt': options.developerReport,
          'release-AOT bundle': options.releaseBundle,
          'release-AOT receipt': options.releaseReport,
          'Universal bundle': options.universalBundle,
          'Universal receipt': options.universalReport,
        },
        allowedExistingTypes: const <FileSystemEntityType>{},
        requireMissing: true,
      );
  final String handoff = File(Platform.script.toFilePath()).absolute.path;
  final String toolDirectory = File(handoff).parent.path;
  final Map<String, String> toolHashes =
      await validateRuntimeToolSourceIdentity(
        receiptPaths: <String, String>{
          'developer-JIT': options.developerReport,
          'release-AOT': options.releaseReport,
          'Universal': options.universalReport,
        },
        toolPaths: <String, String>{
          'dart_terminal:tool/runtime_integration_smoke.dart': options.smoke,
          'dart_terminal:tool/runtime_native_handoff.dart': handoff,
          'dart_terminal:tool/runtime_bundle_audit.dart':
              '$toolDirectory/runtime_bundle_audit.dart',
          'dart_terminal:tool/src/runtime_release_support.dart':
              '$toolDirectory/src/runtime_release_support.dart',
        },
      );
  return _ValidatedInputs(evidenceGuard: evidenceGuard, toolHashes: toolHashes);
}

Future<Map<String, Object?>> _verify(_Options options) async {
  final _ValidatedInputs validated = await _validateStaticInputs(options);
  final String machine = await _stdout('/usr/bin/uname', <String>['-m']);
  final String translated = await _sysctl(
    'sysctl.proc_translated',
    allowMissing: true,
  );
  final String armCapability = await _sysctl(
    'hw.optional.arm64',
    allowMissing: true,
  );
  if (machine != 'x86_64' || translated == '1' || armCapability == '1') {
    throw _HandoffException(
      'Intel-native hardware is required; '
      'uname=$machine translated=$translated hw.optional.arm64=$armCapability',
    );
  }
  final Map<String, Object?> developerAudit = await validateRuntimeAuditReceipt(
    options.developerReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.developerJit,
      expectedArchitectures: const <String>{'x86_64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.developerBundle,
    ),
  );
  final Map<String, Object?> releaseAudit = await validateRuntimeAuditReceipt(
    options.releaseReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: const <String>{'x86_64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.releaseBundle,
    ),
  );
  final Map<String, Object?> universalAudit = await validateRuntimeAuditReceipt(
    options.universalReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: supportedRuntimeArchitectures,
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.universalBundle,
    ),
  );
  final List<Map<String, Object?>> smokes = <Map<String, Object?>>[
    await _runSmoke(
      options.smoke,
      RuntimeMode.developerJit,
      options.developerBundle,
    ),
    await _runSmoke(
      options.smoke,
      RuntimeMode.releaseAot,
      options.releaseBundle,
    ),
    await _runSmoke(
      options.smoke,
      RuntimeMode.releaseAot,
      options.universalBundle,
    ),
  ];
  await validateRuntimeAuditReceipt(
    options.developerReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.developerJit,
      expectedArchitectures: const <String>{'x86_64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.developerBundle,
    ),
  );
  await validateRuntimeAuditReceipt(
    options.releaseReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: const <String>{'x86_64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.releaseBundle,
    ),
  );
  await validateRuntimeAuditReceipt(
    options.universalReport,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: supportedRuntimeArchitectures,
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.universalBundle,
    ),
  );
  await runtimeRevalidateWriteDestination(validated.evidenceGuard);
  final Map<String, Object?> evidence = <String, Object?>{
    'format': 'dart-terminal-intel-native-runtime-evidence',
    'version': 2,
    'status': 'pass',
    'hardware': <String, Object?>{
      'label': options.hardwareLabel,
      'uname_machine': machine,
      'sysctl_proc_translated': translated,
      'hw_optional_arm64': armCapability,
      'model': await _sysctl('hw.model'),
      'cpu': await _sysctl('machdep.cpu.brand_string'),
      'os_version': await _stdout('/usr/bin/sw_vers', <String>[
        '-productVersion',
      ]),
      'os_build': await _stdout('/usr/bin/sw_vers', <String>['-buildVersion']),
    },
    'receipts': <String, Object?>{
      'developer_jit_sha256': await runtimeSha256File(options.developerReport),
      'release_aot_sha256': await runtimeSha256File(options.releaseReport),
      'universal_sha256': await runtimeSha256File(options.universalReport),
    },
    'verified_tool_sha256': validated.toolHashes,
    'dart_runtime': <String, Object?>{
      'version': Platform.version,
      'executable': Platform.resolvedExecutable,
      'executable_sha256': await runtimeSha256File(Platform.resolvedExecutable),
    },
    'audits': <String, Object?>{
      'developer_jit': developerAudit,
      'release_aot': releaseAudit,
      'universal_release_aot': universalAudit,
    },
    'smokes': smokes,
  };
  await runtimeWriteJsonExclusive(options.outputEvidence, evidence);
  return evidence;
}

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseOptions(arguments);
    final Map<String, Object?> evidence = await _verify(options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(evidence));
    stderr.writeln('RUNTIME_INTEL_NATIVE_HANDOFF_PASS');
  } on Object catch (error) {
    stderr.writeln('RUNTIME_INTEL_NATIVE_HANDOFF_FAIL $error');
    exitCode = 1;
  }
}
