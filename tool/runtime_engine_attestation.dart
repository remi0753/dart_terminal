import 'dart:convert';
import 'dart:io';

import 'src/runtime_release_support.dart';

const String _format = 'dart-terminal-official-engine-attestation';
const int _version = 1;
const int _cacheMissExitCode = 3;

final class _AttestationException implements Exception {
  const _AttestationException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _Mode { validate, record }

final class _Options {
  const _Options({
    required this.mode,
    required this.engineRoot,
    required this.expectedRevision,
    required this.engineLibrary,
    required this.kernelCompiler,
    required this.platformDill,
    required this.snapshotter,
    required this.output,
  });

  final _Mode mode;
  final String engineRoot;
  final String expectedRevision;
  final String engineLibrary;
  final String kernelCompiler;
  final String platformDill;
  final String? snapshotter;
  final String output;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw _AttestationException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw _AttestationException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> required = <String>{
    'mode',
    'engine-root',
    'expected-revision',
    'engine-library',
    'kernel-compiler',
    'platform-dill',
    'output',
  };
  const Set<String> optional = <String>{'snapshotter'};
  final Set<String> unknown = values.keys.toSet().difference(<String>{
    ...required,
    ...optional,
  });
  final Set<String> missing = required.difference(values.keys.toSet());
  if (unknown.isNotEmpty || missing.isNotEmpty) {
    throw _AttestationException(
      'unknown=${unknown.toList()..sort()} missing=${missing.toList()..sort()}',
    );
  }
  final _Mode? mode = _Mode.values
      .where((_Mode candidate) => candidate.name == values['mode'])
      .firstOrNull;
  if (mode == null) {
    throw const _AttestationException('--mode must be validate or record');
  }
  for (final String path in <String>[
    values['engine-root']!,
    values['engine-library']!,
    values['kernel-compiler']!,
    values['platform-dill']!,
    if (values['snapshotter'] != null) values['snapshotter']!,
    values['output']!,
  ]) {
    if (!File(path).isAbsolute) {
      throw _AttestationException('path must be absolute: $path');
    }
  }
  return _Options(
    mode: mode,
    engineRoot: values['engine-root']!,
    expectedRevision: values['expected-revision']!,
    engineLibrary: values['engine-library']!,
    kernelCompiler: values['kernel-compiler']!,
    platformDill: values['platform-dill']!,
    snapshotter: values['snapshotter'],
    output: values['output']!,
  );
}

Future<String> _git(_Options options, List<String> arguments) async {
  final ProcessResult result = await Process.run('/usr/bin/git', <String>[
    '-C',
    options.engineRoot,
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw _AttestationException(
      'git ${arguments.join(' ')} failed: ${result.stdout}${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<void> _validateSource(_Options options) async {
  final String revision = await _git(options, const <String>[
    'rev-parse',
    'HEAD',
  ]);
  if (revision != options.expectedRevision) {
    throw _AttestationException(
      'Engine revision $revision != ${options.expectedRevision}',
    );
  }
  final String status = await _git(options, const <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (status.isNotEmpty) {
    throw _AttestationException(
      'official Engine checkout is not clean: $status',
    );
  }
}

Future<Map<String, Object?>> _currentRecord(_Options options) async {
  final String outputDirectory = File(options.engineLibrary).parent.path;
  if (File(options.kernelCompiler).parent.path != outputDirectory ||
      !runtimeNormalizedAbsolutePath(options.platformDill)
          .startsWith('${runtimeNormalizedAbsolutePath(outputDirectory)}/') ||
      (options.snapshotter != null &&
          File(options.snapshotter!).parent.path != outputDirectory) ||
      File(options.output).parent.path != outputDirectory ||
      File(options.output).uri.pathSegments.last !=
          '.dart-terminal-official-engine.json') {
    throw const _AttestationException(
      'Engine attestation paths do not share the selected output directory',
    );
  }
  final Map<String, String> paths = <String, String>{
    'dart_engine': options.engineLibrary,
    'kernel_compiler': options.kernelCompiler,
    'platform_dill': options.platformDill,
    if (options.snapshotter != null) 'snapshotter': options.snapshotter!,
  };
  for (final String path in paths.values) {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw _AttestationException('missing regular Engine output: $path');
    }
  }
  return <String, Object?>{
    'format': _format,
    'version': _version,
    'source_policy': 'official-clean',
    'revision': options.expectedRevision,
    'artifacts': <String, Object?>{
      for (final MapEntry<String, String> entry in paths.entries)
        entry.key: <String, Object?>{
          'path': runtimeNormalizedAbsolutePath(entry.value),
          'sha256': await runtimeSha256File(entry.value),
        },
    },
  };
}

Future<bool> _validateRecord(_Options options) async {
  final File file = File(options.output);
  if (!await file.exists()) {
    return false;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException {
    return false;
  }
  if (decoded is! Map<String, Object?>) {
    return false;
  }
  final Map<String, Object?> current;
  try {
    current = await _currentRecord(options);
  } on _AttestationException {
    return false;
  }
  return runtimeCanonicalJsonEncode(decoded) ==
      runtimeCanonicalJsonEncode(current);
}

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _parseOptions(arguments);
    await _validateSource(options);
    if (options.mode == _Mode.validate) {
      if (!await _validateRecord(options)) {
        stderr.writeln('RUNTIME_ENGINE_ATTESTATION_MISS');
        exitCode = _cacheMissExitCode;
        return;
      }
      stderr.writeln('RUNTIME_ENGINE_ATTESTATION_PASS');
      return;
    }
    await runtimeWriteJsonIfChanged(
      options.output,
      await _currentRecord(options),
    );
    stderr.writeln('RUNTIME_ENGINE_ATTESTATION_RECORDED');
  } on Object catch (error) {
    stderr.writeln('RUNTIME_ENGINE_ATTESTATION_FAIL $error');
    exitCode = 1;
  }
}
