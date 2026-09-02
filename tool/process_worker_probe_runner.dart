import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _timeout = Duration(seconds: 45);

Never _usage(String message) {
  stderr.writeln('PROCESS_WORKER_RUNNER_FAIL $message');
  stderr.writeln(
    'usage: dart run tool/process_worker_probe_runner.dart '
    '--engine-root=PATH --command=PATH --source=PATH '
    '--expected-arch=arm64|x86_64 --mode=aot|jit',
  );
  exit(64);
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = <String, String>{};
  for (final String argument in arguments) {
    final int separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator <= 2) {
      _usage('invalid argument: $argument');
    }
    final String name = argument.substring(2, separator);
    if (!<String>{
      'engine-root',
      'command',
      'source',
      'expected-arch',
      'mode',
    }.contains(name)) {
      _usage('unknown option: $name');
    }
    if (options.containsKey(name)) {
      _usage('duplicate option: $name');
    }
    options[name] = argument.substring(separator + 1);
  }

  final String? engineRootValue = options['engine-root'];
  final String? commandValue = options['command'];
  final String? sourceValue = options['source'];
  final String? expectedArchitecture = options['expected-arch'];
  final String? mode = options['mode'];
  if (engineRootValue == null ||
      commandValue == null ||
      sourceValue == null ||
      (expectedArchitecture != 'arm64' && expectedArchitecture != 'x86_64') ||
      (mode != 'aot' && mode != 'jit')) {
    _usage('all paths, a valid architecture, and a valid mode are required');
  }

  final String selectedArchitecture = expectedArchitecture!;
  final String selectedMode = mode!;

  final Directory engineRoot = Directory(engineRootValue);
  final File command = File(commandValue);
  final File source = File(sourceValue);
  for (final FileSystemEntity entity in <FileSystemEntity>[
    engineRoot,
    command,
    source,
  ]) {
    if (!entity.existsSync()) {
      _usage('required path does not exist: ${entity.path}');
    }
  }

  await _requireCleanEngine(engineRoot);
  _auditSourceBoundary(source);
  await _requireArchitecture(command, selectedArchitecture);
  if (selectedMode == 'aot') {
    await _requireSelfContainedAot(command);
  }

  final List<String> commandArguments = selectedMode == 'jit'
      ? <String>['run', source.path]
      : <String>[];
  final Process process = await Process.start(command.path, commandArguments);
  await process.stdin.close();
  final Future<String> stdoutText = process.stdout
      .transform(utf8.decoder)
      .join();
  final Future<String> stderrText = process.stderr
      .transform(utf8.decoder)
      .join();

  int status;
  try {
    status = await process.exitCode.timeout(_timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    throw StateError(
      'process worker probe exceeded ${_timeout.inSeconds} seconds',
    );
  }

  final String output = await stdoutText;
  final String diagnostics = await stderrText;
  _require(
    status == 0,
    'process worker probe exited $status:\nstdout:\n$output\nstderr:\n$diagnostics',
  );
  _require(
    diagnostics.isEmpty,
    'process worker supervisor wrote stderr: $diagnostics',
  );

  final Map<String, String> markers = _parseMarkers(output);
  final Map<String, String> requiredValues = <String, String>{
    'probe.mode': selectedMode,
    'probe.ready': 'true',
    'probe.distinct_processes': 'true',
    'probe.bulk_bytes': '134217728',
    'probe.graceful_exit': '0',
    'probe.crash_stderr': 'true',
    'probe.replacements': '2',
    'probe.final_outstanding': '0',
    'probe.passed': 'true',
  };
  for (final MapEntry<String, String> required in requiredValues.entries) {
    _require(
      markers[required.key] == required.value,
      '${required.key} was ${markers[required.key]}, expected ${required.value}',
    );
  }

  final int startupMicros = _positiveInteger(markers, 'probe.startup_micros');
  final int bulkMicros = _positiveInteger(markers, 'probe.bulk_micros');
  final double throughput = _positiveDouble(
    markers,
    'probe.bulk_mib_per_second',
  );
  final int crashExit = _integer(markers, 'probe.crash_exit');
  final int forcedExit = _integer(markers, 'probe.forced_exit');
  _require(crashExit != 0, 'crash exit status must be nonzero');
  _require(forcedExit != 0, 'forced exit status must be nonzero');
  _require(startupMicros > 0, 'startup duration must be positive');
  _require(bulkMicros > 0, 'bulk duration must be positive');
  _require(
    throughput.isFinite && throughput > 0,
    'bulk throughput must be finite and positive',
  );

  await _requireCleanEngine(engineRoot);
  stdout.write(output);
  stdout.writeln(
    'PROCESS_WORKER_PROBE_ACCEPTED '
    'mode=$selectedMode runtime=official_dart_executable',
  );
}

Map<String, String> _parseMarkers(String output) {
  final Map<String, String> markers = <String, String>{};
  for (final String line in const LineSplitter().convert(output)) {
    if (line.isEmpty) {
      continue;
    }
    final int separator = line.indexOf('=');
    _require(
      line.startsWith('probe.') && separator > 'probe.'.length,
      'unexpected supervisor output: $line',
    );
    final String key = line.substring(0, separator);
    final String value = line.substring(separator + 1);
    _require(!markers.containsKey(key), 'duplicate supervisor marker: $key');
    markers[key] = value;
  }
  return markers;
}

int _positiveInteger(Map<String, String> markers, String key) {
  final int value = _integer(markers, key);
  _require(value > 0, '$key must be positive');
  return value;
}

int _integer(Map<String, String> markers, String key) {
  final String? text = markers[key];
  final int? value = text == null ? null : int.tryParse(text);
  _require(value != null, '$key is not an integer: $text');
  return value!;
}

double _positiveDouble(Map<String, String> markers, String key) {
  final String? text = markers[key];
  final double? value = text == null ? null : double.tryParse(text);
  _require(value != null, '$key is not a number: $text');
  return value!;
}

void _auditSourceBoundary(File source) {
  final String text = source.readAsStringSync();
  for (final String required in <String>[
    "import 'dart:io';",
    'Process.start(',
    'Platform.resolvedExecutable',
    'bool.fromEnvironment(',
    "'PROCESS_PROBE_SELF_EXEC'",
  ]) {
    _require(
      text.contains(required),
      'process probe does not contain $required',
    );
  }
  for (final String forbidden in <String>[
    "import 'dart:ffi';",
    "import 'package:",
    'dart_engine',
    'Dart_CreateIsolate',
    'DartEngine_',
  ]) {
    _require(
      !text.contains(forbidden),
      'process probe crosses the official executable boundary: $forbidden',
    );
  }
}

Future<void> _requireArchitecture(File executable, String expected) async {
  final ProcessResult result = await Process.run('/usr/bin/lipo', <String>[
    '-archs',
    executable.path,
  ]);
  _require(
    result.exitCode == 0,
    'could not inspect ${executable.path} architecture: ${result.stderr}',
  );
  final Set<String> architectures = (result.stdout as String)
      .trim()
      .split(RegExp(r'\s+'))
      .toSet();
  _require(
    architectures.contains(expected),
    '${executable.path} does not contain $expected: ${result.stdout}',
  );
}

Future<void> _requireSelfContainedAot(File executable) async {
  final ProcessResult result = await Process.run('/usr/bin/otool', <String>[
    '-L',
    executable.path,
  ]);
  _require(
    result.exitCode == 0,
    'could not inspect AOT dependencies: ${result.stderr}',
  );
  final String dependencies = (result.stdout as String).toLowerCase();
  for (final String forbidden in <String>[
    'libdart_engine',
    'libdart_jit',
    'libdart_aotruntime',
    'libdart.',
  ]) {
    _require(
      !dependencies.contains(forbidden),
      'AOT executable depends on a separate Dart runtime: $forbidden',
    );
  }
}

Future<void> _requireCleanEngine(Directory root) async {
  final ProcessResult result = await Process.run('/usr/bin/git', <String>[
    '-C',
    root.path,
    'status',
    '--porcelain',
  ]);
  _require(result.exitCode == 0, 'could not inspect Engine git status');
  final String output = (result.stdout as String).trim();
  _require(output.isEmpty, 'Engine checkout is not clean: $output');
}

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
