import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _timeout = Duration(seconds: 30);

Never _usage(String message) {
  stderr.writeln('PUBLIC_EMBEDDER_WORKER_RUNNER_FAIL $message');
  stderr.writeln(
    'usage: dart run tool/public_embedder_worker_probe_runner.dart '
    '--engine-root=PATH --host=PATH --snapshot=PATH --mode=aot|jit '
    '--dart-source=PATH --native-source=PATH',
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
    options[argument.substring(2, separator)] = argument.substring(
      separator + 1,
    );
  }

  final String? engineRootValue = options['engine-root'];
  final String? hostValue = options['host'];
  final String? snapshotValue = options['snapshot'];
  final String? dartSourceValue = options['dart-source'];
  final String? nativeSourceValue = options['native-source'];
  final String? mode = options['mode'];
  if (engineRootValue == null ||
      hostValue == null ||
      snapshotValue == null ||
      dartSourceValue == null ||
      nativeSourceValue == null ||
      (mode != 'aot' && mode != 'jit')) {
    _usage('all paths and a valid mode are required');
  }

  final Directory engineRoot = Directory(engineRootValue);
  final File host = File(hostValue);
  final File snapshot = File(snapshotValue);
  final File dartSource = File(dartSourceValue);
  final File nativeSource = File(nativeSourceValue);
  for (final FileSystemEntity entity in <FileSystemEntity>[
    engineRoot,
    host,
    snapshot,
    dartSource,
    nativeSource,
  ]) {
    if (!entity.existsSync()) {
      _usage('required path does not exist: ${entity.path}');
    }
  }

  await _requireCleanEngine(engineRoot);
  _auditPublicApiBoundary(engineRoot, dartSource, nativeSource);

  final Process process = await Process.start(host.path, <String>[
    snapshot.path,
  ]);
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
    }
    throw StateError('native probe exceeded ${_timeout.inSeconds} seconds');
  }

  final String output = await stdoutText;
  final String diagnostics = await stderrText;
  _require(
    status == 0,
    'native probe exited $status:\nstdout:\n$output\nstderr:\n$diagnostics',
  );
  _require(diagnostics.isEmpty, 'native probe wrote stderr: $diagnostics');

  const List<String> requiredMarkers = <String>[
    'probe.report_status=0',
    'probe.transferred_bytes=134217728',
    'probe.normal_observed=1',
    'probe.fault_observed=1',
    'probe.forced_observed=1',
    'probe.replacement_observed=1',
    'probe.microtasks_unavailable_observed=1',
    'probe.fault_diagnostic_lost_observed=1',
    'probe.native_created=4',
    'probe.native_shutdown=4',
    'probe.native_cleaned=4',
    'probe.native_released=4',
    'probe.outstanding_workers=0',
    'probe.root_message_error=false',
    'probe.native_error=',
  ];
  final Set<String> outputLines = output.split('\n').toSet();
  for (final String marker in requiredMarkers) {
    _require(outputLines.contains(marker), 'missing marker: $marker');
  }
  _require(
    RegExp(
      r'^probe\.engine_shutdown_micros=\d+$',
      multiLine: true,
    ).hasMatch(output),
    'Engine shutdown timing was not reported',
  );

  final Match? transferMatch = RegExp(
    r'^probe\.transfer_micros=(\d+)$',
    multiLine: true,
  ).firstMatch(output);
  _require(transferMatch != null, 'transfer timing was not reported');
  final int transferMicros = int.parse(transferMatch!.group(1)!);
  _require(transferMicros > 0, 'transfer timing must be positive');
  final double throughput = 128.0 * 1000000.0 / transferMicros;
  _require(
    throughput >= 100,
    'bulk throughput $throughput MiB/s is below the 100 MiB/s gate',
  );

  await _requireCleanEngine(engineRoot);

  stdout.write(output);
  stdout.writeln('probe.bulk_mib_per_second=${throughput.toStringAsFixed(2)}');
  stdout.writeln(
    'PUBLIC_EMBEDDER_WORKER_PROBE_REJECTED '
    'mode=$mode reason=child_core_libraries_uninitialized',
  );
}

void _auditPublicApiBoundary(
  Directory engineRoot,
  File dartSource,
  File nativeSource,
) {
  final File dartApiHeader = File(
    '${engineRoot.path}/runtime/include/dart_api.h',
  );
  final File engineHeader = File(
    '${engineRoot.path}/runtime/engine/include/dart_engine.h',
  );
  final String dartApi = dartApiHeader.readAsStringSync();
  final String engineApi = engineHeader.readAsStringSync();
  for (final String declaration in <String>[
    'Dart_CreateIsolateInGroup',
    'Dart_RunLoopAsync',
    'Dart_KillIsolate',
  ]) {
    _require(
      dartApi.contains(declaration),
      'public dart_api.h does not declare $declaration',
    );
  }
  for (final String declaration in <String>[
    'DartEngine_Init',
    'DartEngine_CreateIsolate',
    'DartEngine_Shutdown',
  ]) {
    _require(
      engineApi.contains(declaration),
      'public dart_engine.h does not declare $declaration',
    );
  }

  final String dartText = dartSource.readAsStringSync();
  _require(
    !dartText.contains('Isolate.spawn') && !dartText.contains('Isolate.run'),
    'probe must not fall back to Dart isolate spawn helpers',
  );

  final String nativeText = nativeSource.readAsStringSync();
  for (final String call in <String>[
    'Dart_CreateIsolateInGroup(',
    'Dart_RunLoopAsync(',
    'Dart_KillIsolate(',
  ]) {
    _require(nativeText.contains(call), 'native probe does not call $call');
  }
  for (final String privateDependency in <String>[
    'dart_embedder_api.h',
    'runtime/bin/',
    'runtime/vm/',
    '"bin/',
    '"vm/',
  ]) {
    _require(
      !nativeText.contains(privateDependency),
      'native probe depends on private SDK surface: $privateDependency',
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
