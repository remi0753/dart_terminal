import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _timeout = Duration(seconds: 12);

Never _usage(String message) {
  stderr.writeln('UNMODIFIED_ENGINE_PROBE_RUNNER_FAIL $message');
  stderr.writeln(
    'usage: dart run tool/unmodified_engine_probe_runner.dart '
    '--engine-root=PATH --host=PATH --snapshot=PATH --mode=aot|jit',
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
  final String? mode = options['mode'];
  if (engineRootValue == null ||
      hostValue == null ||
      snapshotValue == null ||
      (mode != 'aot' && mode != 'jit')) {
    _usage('all paths and a valid mode are required');
  }

  final Directory engineRoot = Directory(engineRootValue);
  final File host = File(hostValue);
  final File snapshot = File(snapshotValue);
  if (!engineRoot.existsSync()) {
    _usage('Engine root does not exist: ${engineRoot.path}');
  }
  if (!host.existsSync()) {
    _usage('probe host does not exist: ${host.path}');
  }
  if (!snapshot.existsSync()) {
    _usage('probe snapshot does not exist: ${snapshot.path}');
  }

  await _requireCleanEngine(engineRoot);

  final File engineHeader = File(
    '${engineRoot.path}/runtime/engine/include/dart_engine.h',
  );
  final File dartApiHeader = File(
    '${engineRoot.path}/runtime/include/dart_api.h',
  );
  final File engineSource = File('${engineRoot.path}/runtime/engine/engine.cc');
  final String engineHeaderText = engineHeader.readAsStringSync();
  final String dartApiHeaderText = dartApiHeader.readAsStringSync();
  final String engineSourceText = engineSource.readAsStringSync();

  _require(
    engineHeaderText.contains('DartEngine_CreateIsolate'),
    'public Engine header does not declare isolate creation',
  );
  _require(
    engineHeaderText.contains('DartEngine_Shutdown'),
    'public Engine header does not declare global shutdown',
  );
  final bool hasIndividualEngineShutdown = RegExp(
    r'DartEngine_(?:Destroy|Remove|Shutdown)Isolate',
  ).hasMatch(engineHeaderText);
  _require(
    dartApiHeaderText.contains('Dart_ShutdownIsolate'),
    'public low-level API no longer exposes Dart_ShutdownIsolate',
  );
  _require(
    engineSourceText.contains('isolates_.emplace_back(isolate)'),
    'Engine source no longer records every created root as expected',
  );
  _require(
    engineSourceText.contains('for (auto isolate : isolates_)'),
    'Engine source no longer performs list-wide global shutdown as expected',
  );
  final bool unregistersIndividualRoot =
      engineSourceText.contains('isolates_.erase') ||
      engineSourceText.contains('isolates_.remove');

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
  _require(status == 0, 'native probe exited $status: $diagnostics');
  _require(diagnostics.isEmpty, 'native probe wrote stderr: $diagnostics');

  const List<String> requiredMarkers = <String>[
    'probe.created_roots=3',
    'probe.cross_group_reply=true',
    'probe.worker_error_callbacks=1',
    'probe.worker_survived_error=true',
    'probe.retired_root_has_live_ports=false',
    'probe.replacement_reply=true',
    'probe.scheduler_off_main_thread=true',
    'probe.intentional_error_observed=true',
    'probe.bulk_bytes=134217728',
  ];
  for (final String marker in requiredMarkers) {
    _require(output.split('\n').contains(marker), 'missing marker: $marker');
  }
  _require(
    RegExp(
      r'^probe\.global_shutdown_micros=\d+$',
      multiLine: true,
    ).hasMatch(output),
    'global shutdown timing was not reported',
  );
  final Match? throughputMatch = RegExp(
    r'^probe\.bulk_mib_per_second=([0-9]+(?:\.[0-9]+)?)$',
    multiLine: true,
  ).firstMatch(output);
  _require(throughputMatch != null, 'bulk throughput was not reported');
  final double throughput = double.parse(throughputMatch!.group(1)!);
  _require(
    throughput >= 100,
    'bulk throughput $throughput MiB/s is below the 100 MiB/s gate',
  );

  await _requireCleanEngine(engineRoot);

  stdout.write(output);
  stdout.writeln(
    'probe.public_individual_engine_shutdown=$hasIndividualEngineShutdown',
  );
  stdout.writeln('probe.engine_unregisters_root=$unregistersIndividualRoot');
  stdout.writeln('UNMODIFIED_ENGINE_MULTIPLE_ROOT_PROBE_OK mode=$mode');
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
