import 'dart:convert';
import 'dart:io';

import 'src/runtime_release_support.dart';

final class _Options {
  const _Options({
    required this.mode,
    required this.expectedArchitectures,
    required this.deploymentTarget,
    required this.bundlePath,
    required this.outputReport,
    required this.validateReport,
  });

  final RuntimeMode mode;
  final Set<String> expectedArchitectures;
  final String deploymentTarget;
  final String bundlePath;
  final String? outputReport;
  final String? validateReport;
}

_Options _parseOptions(List<String> arguments) {
  RuntimeMode? mode;
  Set<String>? expectedArchitectures;
  var deploymentTarget = '14.0';
  String? bundlePath;
  String? outputReport;
  String? validateReport;

  for (final String argument in arguments) {
    if (argument.startsWith('--mode=')) {
      final String value = argument.substring('--mode='.length);
      mode = runtimeModeByName(value);
    } else if (argument.startsWith('--expected-architectures=')) {
      final List<String> architectureValues = argument
          .substring('--expected-architectures='.length)
          .split(',')
          .where((String architecture) => architecture.isNotEmpty)
          .toList();
      expectedArchitectures = architectureValues.toSet();
      if (expectedArchitectures.length != architectureValues.length) {
        throw const RuntimeAuditException(
          '--expected-architectures contains a duplicate architecture',
        );
      }
    } else if (argument.startsWith('--deployment-target=')) {
      deploymentTarget = argument.substring('--deployment-target='.length);
    } else if (argument.startsWith('--output-report=')) {
      if (outputReport != null) {
        throw const RuntimeAuditException(
          '--output-report may be specified only once',
        );
      }
      outputReport = argument.substring('--output-report='.length);
      if (outputReport.isEmpty || !File(outputReport).isAbsolute) {
        throw const RuntimeAuditException(
          '--output-report must be an absolute path',
        );
      }
    } else if (argument.startsWith('--validate-report=')) {
      if (validateReport != null) {
        throw const RuntimeAuditException(
          '--validate-report may be specified only once',
        );
      }
      validateReport = argument.substring('--validate-report='.length);
      if (validateReport.isEmpty || !File(validateReport).isAbsolute) {
        throw const RuntimeAuditException(
          '--validate-report must be an absolute path',
        );
      }
    } else if (argument.startsWith('-')) {
      throw RuntimeAuditException('unknown argument: $argument');
    } else if (bundlePath != null) {
      throw const RuntimeAuditException('exactly one app bundle is required');
    } else {
      bundlePath = argument;
    }
  }

  if (mode == null) {
    throw const RuntimeAuditException(
      '--mode must be developer-jit or release-aot',
    );
  }
  if (expectedArchitectures == null || expectedArchitectures.isEmpty) {
    throw const RuntimeAuditException(
      '--expected-architectures must name at least one architecture',
    );
  }
  if (!supportedRuntimeArchitectures.containsAll(expectedArchitectures)) {
    throw RuntimeAuditException(
      'unsupported architecture set: ${expectedArchitectures.join(',')}',
    );
  }
  if (bundlePath == null) {
    throw const RuntimeAuditException('one app bundle is required');
  }
  if (outputReport != null && validateReport != null) {
    throw const RuntimeAuditException(
      '--output-report and --validate-report are mutually exclusive',
    );
  }
  return _Options(
    mode: mode,
    expectedArchitectures: expectedArchitectures,
    deploymentTarget: deploymentTarget,
    bundlePath: bundlePath,
    outputReport: outputReport,
    validateReport: validateReport,
  );
}

Future<void> main(List<String> arguments) async {
  late final _Options options;
  try {
    options = _parseOptions(arguments);
  } on RuntimeAuditException catch (error) {
    stderr.writeln('RUNTIME_BUNDLE_AUDIT_USAGE_ERROR ${error.message}');
    exitCode = 64;
    return;
  }

  Map<String, Object?> result;
  var passed = true;
  RuntimeWriteDestinationGuard? reportGuard;
  if (options.outputReport != null) {
    try {
      reportGuard = await runtimeValidateWriteDestination(
        description: 'runtime audit report',
        destination: options.outputReport!,
        protectedPaths: <String, String>{'audited bundle': options.bundlePath},
        allowedExistingTypes: const <FileSystemEntityType>{},
        requireMissing: true,
      );
    } on Object catch (error) {
      stderr.writeln('RUNTIME_BUNDLE_AUDIT_REPORT_FAIL $error');
      exitCode = 1;
      return;
    }
  }
  if (options.validateReport != null) {
    try {
      await runtimeValidateDisjointExistingPaths(<String, String>{
        'audited bundle': options.bundlePath,
        'runtime audit receipt': options.validateReport!,
      });
    } on Object catch (error) {
      stderr.writeln('RUNTIME_BUNDLE_AUDIT_REPORT_FAIL $error');
      exitCode = 1;
      return;
    }
  }
  try {
    final RuntimeBundleAuditOptions auditOptions = RuntimeBundleAuditOptions(
      mode: options.mode,
      expectedArchitectures: options.expectedArchitectures,
      deploymentTarget: options.deploymentTarget,
      bundlePath: options.bundlePath,
    );
    result = options.validateReport == null
        ? await auditRuntimeBundle(auditOptions)
        : await validateRuntimeAuditReceipt(
            options.validateReport!,
            auditOptions,
          );
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
    'format': runtimeBundleAuditFormat,
    'version': runtimeBundleAuditVersion,
    'status': passed ? 'pass' : 'fail',
    'result': result,
  };
  if (options.outputReport != null) {
    try {
      await runtimeRevalidateWriteDestination(reportGuard!);
      await runtimeWriteJsonExclusive(options.outputReport!, report);
    } on Object catch (error) {
      stderr.writeln('RUNTIME_BUNDLE_AUDIT_REPORT_FAIL $error');
      exitCode = 1;
      return;
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  stderr.writeln(
    'RUNTIME_BUNDLE_AUDIT_${passed ? 'PASS' : 'FAIL'} '
    'mode=${options.mode.name}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
