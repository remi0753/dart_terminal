import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'src/runtime_release_support.dart';

final class _ManifestException implements Exception {
  const _ManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _Options {
  const _Options({
    required this.mode,
    required this.architecture,
    required this.fingerprint,
    required this.launcher,
    required this.engine,
    required this.payload,
    required this.workerPayload,
    required this.intermediate,
    required this.output,
  });

  final RuntimeMode mode;
  final String architecture;
  final String fingerprint;
  final String launcher;
  final String engine;
  final String payload;
  final String? workerPayload;
  final String? intermediate;
  final String output;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _ManifestException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw _ManifestException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> required = <String>{
    'mode',
    'architecture',
    'fingerprint',
    'launcher',
    'engine',
    'payload',
    'output',
  };
  const Set<String> optional = <String>{'worker-payload', 'intermediate'};
  final Set<String> unknown = values.keys.toSet().difference(<String>{
    ...required,
    ...optional,
  });
  final Set<String> missing = required.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _ManifestException(
      'unknown=${unknown.join(',')} missing=${missing.join(',')}',
    );
  }
  final RuntimeMode? mode = runtimeModeByName(values['mode']!);
  if (mode == null) {
    throw const _ManifestException(
      '--mode must be developer-jit or release-aot',
    );
  }
  final String architecture = values['architecture']!;
  if (!supportedRuntimeArchitectures.contains(architecture)) {
    throw const _ManifestException('--architecture must be arm64 or x86_64');
  }
  if (mode == RuntimeMode.releaseAot && values['intermediate'] == null) {
    throw const _ManifestException('release-aot requires --intermediate');
  }
  if (mode == RuntimeMode.developerJit && values['worker-payload'] == null) {
    throw const _ManifestException('developer-jit requires --worker-payload');
  }
  if (mode == RuntimeMode.releaseAot && values['worker-payload'] != null) {
    throw const _ManifestException(
      'release-aot must not contain a Developer worker Kernel',
    );
  }
  return _Options(
    mode: mode,
    architecture: architecture,
    fingerprint: values['fingerprint']!,
    launcher: values['launcher']!,
    engine: values['engine']!,
    payload: values['payload']!,
    workerPayload: values['worker-payload'],
    intermediate: values['intermediate'],
    output: values['output']!,
  );
}

Future<Map<String, Object?>> _readFingerprint(String path) async {
  final File file = File(path);
  if (!await file.exists()) {
    throw _ManifestException('missing build fingerprint: $path');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException catch (error) {
    throw _ManifestException('invalid build fingerprint: $error');
  }
  if (decoded is! Map<String, Object?>) {
    throw const _ManifestException('build fingerprint must be an object');
  }
  return decoded;
}

Future<Map<String, Object?>> _createManifest(_Options options) async {
  for (final String path in <String>[
    options.fingerprint,
    options.launcher,
    options.engine,
    options.payload,
    if (options.workerPayload != null) options.workerPayload!,
    if (options.intermediate != null) options.intermediate!,
    options.output,
  ]) {
    if (!File(path).isAbsolute) {
      throw _ManifestException('path must be absolute: $path');
    }
  }
  final Map<String, Object?> fingerprint = await _readFingerprint(
    options.fingerprint,
  );
  if (fingerprint['format'] != runtimeBuildFingerprintFormat ||
      fingerprint['version'] != runtimeBuildFingerprintVersion) {
    throw const _ManifestException(
      'unsupported build fingerprint format/version',
    );
  }
  final Map<String, Object?> common = runtimeStringMap(
    fingerprint['common'],
    'build fingerprint common',
  );
  final Map<String, Object?> lane = runtimeStringMap(
    fingerprint['lane'],
    'build fingerprint lane',
  );
  if (common['runtime_mode'] != options.mode.name ||
      common['engine_configuration'] != options.mode.engineConfiguration ||
      lane['architecture'] != options.architecture) {
    throw const _ManifestException(
      'build fingerprint mode/configuration/architecture mismatch',
    );
  }
  final Object? commonCopy = jsonDecode(jsonEncode(common));
  final Object? laneCopy = jsonDecode(jsonEncode(lane));
  if (commonCopy is! Map<String, Object?> ||
      laneCopy is! Map<String, Object?>) {
    throw const _ManifestException('build fingerprint sections are invalid');
  }
  final SplayTreeMap<String, Object?> produced =
      SplayTreeMap<String, Object?>();
  produced['dart_engine'] = await runtimeSha256File(options.engine);
  produced['launcher'] = await runtimeSha256File(options.launcher);
  if (options.mode == RuntimeMode.releaseAot) {
    produced['aot_snapshot'] = await runtimeSha256File(options.payload);
    laneCopy['intermediate_kernel_sha256'] = await runtimeSha256File(
      options.intermediate!,
    );
  } else {
    produced['kernel_payload'] = await runtimeSha256File(options.payload);
    produced['worker_kernel_payload'] = await runtimeSha256File(
      options.workerPayload!,
    );
  }
  laneCopy['fingerprint_sha256'] = await runtimeSha256File(options.fingerprint);
  laneCopy['produced_sha256'] = produced;
  return <String, Object?>{
    'format': runtimeBuildManifestFormat,
    'version': runtimeBuildManifestVersion,
    'architecture': options.architecture,
    ...commonCopy,
    'architecture_inputs': laneCopy,
  };
}

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseOptions(arguments);
    final Map<String, Object?> manifest = await _createManifest(options);
    await runtimeWriteJsonIfChanged(options.output, manifest);
    stderr.writeln(
      'RUNTIME_BUILD_MANIFEST_PASS mode=${options.mode.name} '
      'architecture=${options.architecture}',
    );
  } on Object catch (error) {
    stderr.writeln('RUNTIME_BUILD_MANIFEST_FAIL $error');
    exitCode = 1;
  }
}
