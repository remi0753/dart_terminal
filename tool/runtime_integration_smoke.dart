import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class _SmokeException implements Exception {
  const _SmokeException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _RuntimeMode {
  developerJit('developer-jit', 'application.dill'),
  releaseAot('release-aot', 'application.aot');

  const _RuntimeMode(this.name, this.payloadName);

  final String name;
  final String payloadName;
}

enum _Suite {
  smoke,
  display,
  hierarchy,
  restoration,
  clipboard,
  lifecycle,
  traffic,
  resource,
  fault,
  all,
}

final class _Options {
  const _Options({
    required this.mode,
    required this.suite,
    required this.bundlePath,
    required this.launchArchitecture,
  });

  final _RuntimeMode mode;
  final _Suite suite;
  final String bundlePath;
  final String? launchArchitecture;
}

final class _Invocation {
  const _Invocation({
    required this.executable,
    required this.applicationArgumentPrefix,
    required this.architecture,
    required this.bundleIdentifier,
    required this.applicationVersion,
    required this.dartSdkRevision,
  });

  final String executable;
  final List<String> applicationArgumentPrefix;
  final String architecture;
  final String bundleIdentifier;
  final String applicationVersion;
  final String dartSdkRevision;

  List<String> arguments(List<String> applicationArguments) => <String>[
    ...applicationArgumentPrefix,
    ...applicationArguments,
  ];
}

final class _ProcessObservation {
  const _ProcessObservation({
    required this.processId,
    required this.status,
    required this.stdoutText,
    required this.stderrText,
    required this.elapsed,
    required this.workerProcesses,
  });

  final int processId;
  final int status;
  final String stdoutText;
  final String stderrText;
  final Duration elapsed;
  final List<_WorkerProcessObservation> workerProcesses;
}

final class _WorkerProcessObservation {
  const _WorkerProcessObservation({
    required this.event,
    required this.scenario,
    required this.generation,
    required this.parentProcessId,
    required this.workerProcessId,
  });

  final String event;
  final String scenario;
  final int generation;
  final int parentProcessId;
  final int workerProcessId;
}

final class _LifecycleCase {
  const _LifecycleCase({
    required this.name,
    required this.applicationArguments,
    required this.expectedStatus,
    required this.expectedObservations,
    this.machineScenario,
    this.environment = const <String, String>{},
    this.expectedStderrMarker,
    this.expectedWorkerProcessCount = 1,
    this.expectedDiagnosticPhase = 'root-stopped',
  });

  final String name;
  final String? machineScenario;
  final List<String> applicationArguments;
  final Map<String, String> environment;
  final int expectedStatus;
  final List<String> expectedObservations;
  final String? expectedStderrMarker;
  final int expectedWorkerProcessCount;
  final String expectedDiagnosticPhase;
}

_Options _parseOptions(List<String> arguments) {
  _RuntimeMode? mode;
  var suite = _Suite.smoke;
  String? bundlePath;
  String? launchArchitecture;
  for (final String argument in arguments) {
    if (argument.startsWith('--mode=')) {
      final String value = argument.substring('--mode='.length);
      mode = _RuntimeMode.values
          .where((_RuntimeMode candidate) => candidate.name == value)
          .firstOrNull;
    } else if (argument.startsWith('--suite=')) {
      final String value = argument.substring('--suite='.length);
      final _Suite? selected = _Suite.values
          .where((_Suite candidate) => candidate.name == value)
          .firstOrNull;
      if (selected == null) {
        throw const _SmokeException(
          '--suite must be smoke, display, hierarchy, restoration, clipboard, '
          'lifecycle, traffic, resource, fault, or all',
        );
      }
      suite = selected;
    } else if (argument.startsWith('--launch-architecture=')) {
      launchArchitecture = argument.substring('--launch-architecture='.length);
    } else if (argument.startsWith('-')) {
      throw _SmokeException('unknown argument: $argument');
    } else if (bundlePath != null) {
      throw const _SmokeException('exactly one app bundle is required');
    } else {
      bundlePath = argument;
    }
  }
  if (mode == null) {
    throw const _SmokeException('--mode must be developer-jit or release-aot');
  }
  if (bundlePath == null) {
    throw const _SmokeException('one app bundle is required');
  }
  if (launchArchitecture != null &&
      launchArchitecture != 'arm64' &&
      launchArchitecture != 'x86_64') {
    throw const _SmokeException(
      '--launch-architecture must be arm64 or x86_64',
    );
  }
  return _Options(
    mode: mode,
    suite: suite,
    bundlePath: bundlePath,
    launchArchitecture: launchArchitecture,
  );
}

Future<String> _plistValue(String plistPath, String key) async {
  final ProcessResult result = await Process.run('/usr/bin/plutil', <String>[
    '-extract',
    key,
    'raw',
    '-o',
    '-',
    plistPath,
  ]);
  if (result.exitCode != 0) {
    throw _SmokeException(
      'could not read $key from Info.plist: '
              '${result.stdout}${result.stderr}'
          .trim(),
    );
  }
  return (result.stdout as String).trim();
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw _SmokeException(message);
  }
}

Future<_Invocation> _loadInvocation(_Options options) async {
  final Directory bundle = Directory(options.bundlePath).absolute;
  _expect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
  final String contentsPath = '${bundle.path}/Contents';
  final String plistPath = '$contentsPath/Info.plist';
  _expect(await File(plistPath).exists(), 'missing Info.plist: $plistPath');
  final File buildManifestFile = File(
    '$contentsPath/Resources/runtime-build-manifest.json',
  );
  _expect(await buildManifestFile.exists(), 'missing runtime build manifest');
  final Map<String, Object?> buildManifest = jsonDecode(
    await buildManifestFile.readAsString(),
  ) as Map<String, Object?>;
  final String declaredMode = buildManifest['runtimeMode']! as String;
  _expect(
    declaredMode == options.mode.name,
    'declared runtime mode $declaredMode != ${options.mode.name}',
  );
  final String executableName = await _plistValue(
    plistPath,
    'CFBundleExecutable',
  );
  final String executablePath = '$contentsPath/MacOS/$executableName';
  final String payloadPath =
      '$contentsPath/Resources/${options.mode.payloadName}';
  _expect(await File(executablePath).exists(), 'missing executable');
  _expect(await File(payloadPath).exists(), 'missing runtime payload');
  final String bundleIdentifier = await _plistValue(
    plistPath,
    'CFBundleIdentifier',
  );
  final String applicationVersion = await _plistValue(
    plistPath,
    'CFBundleShortVersionString',
  );
  final String dartSdkRevision = buildManifest['dartSdkRevision']! as String;
  final String architecture =
      options.launchArchitecture ?? await _hostArchitecture();

  if (options.mode == _RuntimeMode.releaseAot) {
    return _Invocation(
      executable: executablePath,
      applicationArgumentPrefix: const <String>[],
      architecture: architecture,
      bundleIdentifier: bundleIdentifier,
      applicationVersion: applicationVersion,
      dartSdkRevision: dartSdkRevision,
    );
  }
  final String sdkVersion = buildManifest['dartSdkVersion']! as String;
  final String sdkRevision = buildManifest['dartSdkRevision']! as String;
  return _Invocation(
    executable: executablePath,
    applicationArgumentPrefix: <String>[
      '--kernel',
      payloadPath,
      '--sdk-version',
      sdkVersion,
      '--sdk-revision',
      sdkRevision,
      '--',
    ],
    architecture: architecture,
    bundleIdentifier: bundleIdentifier,
    applicationVersion: applicationVersion,
    dartSdkRevision: dartSdkRevision,
  );
}

Future<String> _hostArchitecture() async {
  final ProcessResult result = await Process.run('/usr/bin/uname', <String>[
    '-m',
  ]);
  final String architecture = (result.stdout as String).trim();
  _expect(
    result.exitCode == 0 &&
        (architecture == 'arm64' || architecture == 'x86_64'),
    'could not determine supported host architecture',
  );
  return architecture;
}

Future<_ProcessObservation> _launch(
  _Options options,
  _Invocation invocation,
  List<String> applicationArguments, {
  Map<String, String> environment = const <String, String>{},
  String expectedDiagnosticPhase = 'root-stopped',
  Duration timeout = const Duration(seconds: 12),
  bool throughLaunchServices = false,
}) async {
  final List<String> invocationArguments = invocation.arguments(
    applicationArguments,
  );
  final Directory diagnosticsDirectory = await Directory.systemTemp.createTemp(
    'dart-terminal-runtime-diagnostics-',
  );
  Directory? captureDirectory;
  try {
    final Map<String, String> launchEnvironment = <String, String>{
      ...environment,
      'DMR_RUNTIME_DIAGNOSTICS_TEST': '1',
      'DMR_RUNTIME_DIAGNOSTICS_DIRECTORY': diagnosticsDirectory.path,
    };
    late final String processExecutable;
    late final List<String> processArguments;
    String? capturedStdoutPath;
    String? capturedStderrPath;
    if (throughLaunchServices) {
      captureDirectory = await Directory.systemTemp.createTemp(
        'dart-terminal-runtime-output-',
      );
      capturedStdoutPath = '${captureDirectory.path}/stdout.txt';
      capturedStderrPath = '${captureDirectory.path}/stderr.txt';
      processExecutable = '/usr/bin/open';
      processArguments = <String>[
        '-W',
        '-n',
        '-F',
        if (options.launchArchitecture != null) ...<String>[
          '--arch',
          options.launchArchitecture!,
        ],
        '-o',
        capturedStdoutPath,
        '--stderr',
        capturedStderrPath,
        for (final MapEntry<String, String> value
            in launchEnvironment.entries) ...<String>[
          '--env',
          '${value.key}=${value.value}',
        ],
        options.bundlePath,
        '--args',
        ...invocationArguments,
      ];
    } else {
      processExecutable = options.launchArchitecture == null
          ? invocation.executable
          : '/usr/bin/arch';
      processArguments = options.launchArchitecture == null
          ? invocationArguments
          : <String>[
              '-${options.launchArchitecture}',
              invocation.executable,
              ...invocationArguments,
            ];
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    final Process process = await Process.start(
      processExecutable,
      processArguments,
      workingDirectory: Directory.current.path,
      environment: throughLaunchServices ? null : launchEnvironment,
    );
    final Future<String> launcherStdout = process.stdout
        .transform(utf8.decoder)
        .join();
    final Future<String> launcherStderr = process.stderr
        .transform(utf8.decoder)
        .join();
    Future<String> completedOutput(
      String launcher,
      String? capturedPath,
    ) async {
      if (capturedPath == null || !await File(capturedPath).exists()) {
        return launcher;
      }
      return '${await File(capturedPath).readAsString()}$launcher';
    }

    late final int launcherStatus;
    try {
      launcherStatus = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      if (throughLaunchServices) {
        final int? applicationProcessId = await _runtimeDiagnosticProcessId(
          diagnosticsDirectory,
        );
        if (applicationProcessId != null) {
          Process.killPid(applicationProcessId, ProcessSignal.sigterm);
        }
      }
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      final String completedStdout = await completedOutput(
        await launcherStdout,
        capturedStdoutPath,
      );
      final String completedStderr = await completedOutput(
        await launcherStderr,
        capturedStderrPath,
      );
      throw _SmokeException(
        '${options.mode.name} application did not exit within '
        '${timeout.inSeconds} seconds; '
        'stdout=${completedStdout.trim()} '
        'stderr=${completedStderr.trim()}',
      );
    } finally {
      stopwatch.stop();
    }
    final String completedStdout = await completedOutput(
      await launcherStdout,
      capturedStdoutPath,
    );
    final String completedStderr = await completedOutput(
      await launcherStderr,
      capturedStderrPath,
    );
    final int processId = throughLaunchServices
        ? await _runtimeDiagnosticProcessId(diagnosticsDirectory) ?? process.pid
        : process.pid;
    final int status = throughLaunchServices
        ? await _runtimeDiagnosticExitCode(diagnosticsDirectory) ??
              launcherStatus
        : launcherStatus;
    final List<_WorkerProcessObservation> workerProcesses =
        _parseWorkerProcesses(completedStdout);
    for (final int workerProcessId
        in workerProcesses
            .where(
              (_WorkerProcessObservation observation) =>
                  observation.event == 'spawned',
            )
            .map(
              (_WorkerProcessObservation observation) =>
                  observation.workerProcessId,
            )) {
      await _expectProcessAbsent(workerProcessId);
    }
    try {
      await _expectRuntimeDiagnostics(
        options,
        invocation,
        diagnosticsDirectory,
        processId: processId,
        status: status,
        expectedPhase: expectedDiagnosticPhase,
      );
    } on _SmokeException catch (error) {
      throw _SmokeException(
        '${error.message}; stdout=${completedStdout.trim()} '
        'stderr=${completedStderr.trim()}',
      );
    }
    return _ProcessObservation(
      processId: processId,
      status: status,
      stdoutText: completedStdout,
      stderrText: completedStderr,
      elapsed: stopwatch.elapsed,
      workerProcesses: workerProcesses,
    );
  } finally {
    if (captureDirectory != null && await captureDirectory.exists()) {
      await captureDirectory.delete(recursive: true);
    }
    if (await diagnosticsDirectory.exists()) {
      await diagnosticsDirectory.delete(recursive: true);
    }
  }
}

Future<int?> _runtimeDiagnosticProcessId(Directory directory) async {
  final File file = File('${directory.path}/current-run.json');
  if (!await file.exists()) return null;
  try {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded case <String, dynamic>{'process_id': final int processId}
        when processId > 0) {
      return processId;
    }
  } on Object {
    return null;
  }
  return null;
}

Future<int?> _runtimeDiagnosticExitCode(Directory directory) async {
  final File file = File('${directory.path}/current-run.json');
  if (!await file.exists()) return null;
  try {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded case <String, dynamic>{'exit_code': final int exitCode}) {
      return exitCode;
    }
  } on Object {
    return null;
  }
  return null;
}

Future<void> _expectRuntimeDiagnostics(
  _Options options,
  _Invocation invocation,
  Directory directory, {
  required int processId,
  required int status,
  required String expectedPhase,
}) async {
  final FileStat directoryStat = await directory.stat();
  _expect(
    directoryStat.type == FileSystemEntityType.directory &&
        directoryStat.mode & 0x1ff == 0x1c0,
    'diagnostics directory is not owner-only',
  );
  final List<String> entries =
      await directory
            .list(followLinks: false)
            .map((FileSystemEntity entry) => entry.uri.pathSegments.last)
            .toList()
        ..sort();
  _expect(
    _sameStrings(entries, const <String>['current-run.json']),
    'diagnostics retention was not isolated to current-run.json: $entries',
  );

  final File recordFile = File('${directory.path}/current-run.json');
  final FileStat recordStat = await recordFile.stat();
  _expect(
    recordStat.type == FileSystemEntityType.file &&
        recordStat.size > 0 &&
        recordStat.size <= 16 * 1024 &&
        recordStat.mode & 0x1ff == 0x180,
    'diagnostics record type, size, or owner-only mode is invalid',
  );
  final Object? decoded = jsonDecode(await recordFile.readAsString());
  _expect(decoded is Map<String, dynamic>, 'diagnostics record is not JSON');
  final Map<String, dynamic> record = decoded! as Map<String, dynamic>;
  const Set<String> expectedKeys = <String>{
    'format',
    'version',
    'launch_id',
    'bundle_identifier',
    'application_version',
    'runtime_mode',
    'architecture',
    'dart_sdk_revision',
    'process_id',
    'started_at',
    'updated_at',
    'phase',
    'outcome',
    'exit_code',
  };
  _expect(
    record.keys.toSet().length == expectedKeys.length &&
        record.keys.toSet().containsAll(expectedKeys),
    'diagnostics record does not use the exact privacy allowlist',
  );
  _expect(
    record['format'] == 'dart-macos-runtime-local-run-metadata' &&
        record['version'] == 1,
    'diagnostics format or version is invalid',
  );
  _expect(
    record['launch_id'] is String &&
        RegExp(
          r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
          r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
        ).hasMatch(record['launch_id'] as String),
    'diagnostics launch ID is invalid',
  );
  _expect(
    record['bundle_identifier'] == invocation.bundleIdentifier &&
        record['application_version'] == invocation.applicationVersion &&
        record['runtime_mode'] == options.mode.name &&
        record['architecture'] == invocation.architecture &&
        record['dart_sdk_revision'] == invocation.dartSdkRevision &&
        record['process_id'] == processId,
    'diagnostics build or process identity does not match the launch',
  );
  final DateTime startedAt = _parseUtcTimestamp(
    record['started_at'],
    'started_at',
  );
  final DateTime updatedAt = _parseUtcTimestamp(
    record['updated_at'],
    'updated_at',
  );
  _expect(
    !updatedAt.isBefore(startedAt),
    'diagnostics update precedes launch start',
  );
  _expect(
    record['phase'] == expectedPhase &&
        record['outcome'] == (status == 0 ? 'clean' : 'failure') &&
        record['exit_code'] == status,
    'diagnostics completion does not match phase/status '
    '$expectedPhase/$status: $record',
  );
}

DateTime _parseUtcTimestamp(Object? value, String field) {
  DateTime? parsed;
  if (value is String) {
    parsed = DateTime.tryParse(value);
  }
  _expect(parsed != null && parsed.isUtc, 'diagnostics $field is not UTC');
  return parsed!;
}

List<_WorkerProcessObservation> _parseWorkerProcesses(String output) {
  final RegExp pattern = RegExp(
    r'^RUNTIME_WORKER_PROCESS event=(spawned|reaped) '
    r'scenario=([a-z-]+) generation=([0-9]+) '
    r'parent_pid=([0-9]+) worker_pid=([0-9]+)$',
  );
  final List<_WorkerProcessObservation> observations =
      <_WorkerProcessObservation>[];
  for (final String line in output.split('\n')) {
    if (!line.startsWith('RUNTIME_WORKER_PROCESS ')) {
      continue;
    }
    final RegExpMatch? match = pattern.firstMatch(line);
    _expect(match != null, 'malformed worker process observation: $line');
    observations.add(
      _WorkerProcessObservation(
        event: match!.group(1)!,
        scenario: match.group(2)!,
        generation: int.parse(match.group(3)!),
        parentProcessId: int.parse(match.group(4)!),
        workerProcessId: int.parse(match.group(5)!),
      ),
    );
  }
  return observations;
}

Future<void> _expectProcessAbsent(int processId) async {
  final Stopwatch deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 2)) {
    final ProcessResult result = await Process.run('/bin/ps', <String>[
      '-p',
      '$processId',
      '-o',
      'pid=',
    ]);
    if (result.exitCode != 0 || (result.stdout as String).trim().isEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw _SmokeException('worker process remained after app exit: $processId');
}

void _expectWorkerProcessContract(
  _ProcessObservation observation, {
  required String scenario,
  required int expectedCount,
}) {
  final List<_WorkerProcessObservation> spawned = observation.workerProcesses
      .where((_WorkerProcessObservation value) => value.event == 'spawned')
      .toList();
  final List<_WorkerProcessObservation> reaped = observation.workerProcesses
      .where((_WorkerProcessObservation value) => value.event == 'reaped')
      .toList();
  _expect(
    spawned.length == expectedCount,
    '$scenario spawned ${spawned.length} workers, expected $expectedCount',
  );
  final Set<int> spawnedIds = <int>{
    for (final _WorkerProcessObservation value in spawned)
      value.workerProcessId,
  };
  final Set<int> reapedIds = <int>{
    for (final _WorkerProcessObservation value in reaped) value.workerProcessId,
  };
  _expect(
    spawnedIds.length == spawned.length &&
        spawned.every(
          (_WorkerProcessObservation value) =>
              value.scenario == scenario &&
              value.parentProcessId == observation.processId &&
              value.workerProcessId != observation.processId &&
              value.generation > 0,
        ),
    '$scenario emitted invalid or duplicate spawned-process evidence',
  );
  _expect(
    reaped.every(
      (_WorkerProcessObservation value) =>
          value.scenario == scenario &&
          value.parentProcessId == observation.processId &&
          spawnedIds.contains(value.workerProcessId),
    ),
    '$scenario emitted a reaped process without matching ownership',
  );
  _expect(
    reapedIds.length == reaped.length && _sameIntSets(spawnedIds, reapedIds),
    '$scenario did not observe every child exit in-process',
  );
}

bool _sameIntSets(Set<int> left, Set<int> right) =>
    left.length == right.length && left.containsAll(right);

bool _containsOrderedValues(List<String> actual, List<String> expected) {
  var expectedIndex = 0;
  for (final String value in actual) {
    if (expectedIndex < expected.length && value == expected[expectedIndex]) {
      ++expectedIndex;
    }
  }
  return expectedIndex == expected.length;
}

Future<void> _runSmoke(_Options options, _Invocation invocation) async {
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    const <String>['--auto-close-after=1'],
    environment: const <String, String>{'DT_RUNTIME_EVENT_WIRE_TEST': '1'},
  );
  _expect(
    observation.status == 0,
    'application exited with status ${observation.status}',
  );
  _expect(
    observation.stderrText.trim().isEmpty,
    'application wrote unexpected stderr: ${observation.stderrText.trim()}',
  );
  for (final String expected in <String>[
    'Dart Terminal is attached to the AppKit main thread.',
    'NATIVE_KEY_EVENT_ROUTING mode=appkit-only',
    'NATIVE_TEXT_INPUT_CLIENT attached=true routing=appkit-only client_id=',
    'NATIVE_CUSTOM_VIEW '
        'provider=dart_terminal.TerminalMetalView attached=true '
        'renderer_bound=true',
    'Automated close scheduled after 1 seconds.',
    'Dart Terminal shut down cleanly.',
  ]) {
    _expect(
      observation.stdoutText.contains(expected),
      'missing smoke observation: $expected',
    );
  }
  final RegExp eventWire = RegExp(
    r'^NATIVE_EVENT_WIRE negotiated=6 event=window-closed protocol=6 '
    r'source_generation=[1-9][0-9]* operation_id=0 '
    r'timestamp_ns=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    eventWire.hasMatch(observation.stdoutText),
    'missing current native event wire observation',
  );
  final String statePrefix = r'^NATIVE_WINDOW_STATE negotiated=6 event=';
  final String stateMetadata =
      r' protocol=6 source_generation=[1-9][0-9]* operation_id=0 '
      r'timestamp_ns=[1-9][0-9]* ';
  RegExp stateEvent(String name, String payload) =>
      RegExp('$statePrefix$name$stateMetadata$payload', multiLine: true);
  final Map<String, RegExp> stateEvents = <String, RegExp>{
    'focus': stateEvent('focus', r'value=(true|false)$'),
    'visibility': stateEvent('visibility', r'value=true$'),
    'occlusion': stateEvent('occlusion', r'value=(true|false)$'),
    'backing-scale': stateEvent(
      'backing-scale',
      r'value=[1-9][0-9]*(\.[0-9]+)?$',
    ),
    'screen': stateEvent(
      'screen',
      r'present=true display_id=[1-9][0-9]* '
          r'frame_width=[1-9][0-9]*(\.[0-9]+)? '
          r'frame_height=[1-9][0-9]*(\.[0-9]+)? '
          r'visible_width=[1-9][0-9]*(\.[0-9]+)? '
          r'visible_height=[1-9][0-9]*(\.[0-9]+)?$',
    ),
    'frame': stateEvent(
      'frame',
      r'left=-?[0-9]+(\.[0-9]+)? top=-?[0-9]+(\.[0-9]+)? '
          r'width=[1-9][0-9]*(\.[0-9]+)? '
          r'height=[1-9][0-9]*(\.[0-9]+)?$',
    ),
    'fullscreen': stateEvent('fullscreen', r'value=false$'),
  };
  for (final MapEntry<String, RegExp> stateEvent in stateEvents.entries) {
    _expect(
      stateEvent.value.hasMatch(observation.stdoutText),
      'missing native ${stateEvent.key} state observation',
    );
  }
  final RegExp applicationState = RegExp(
    r'^NATIVE_APPLICATION_STATE negotiated=6 active=(true|false)$',
    multiLine: true,
  );
  _expect(
    applicationState.hasMatch(observation.stdoutText),
    'missing application active-state observation',
  );
  _expect(
    RegExp(
          r'^COMMAND_PALETTE_ACCEPTANCE shortcut=true opened=true query=true '
          r'selected=pane\.focus-next dispatch=executed invocations=1 '
          r'terminal_write_delta=0 first_responder_restored=true '
          r'handles_restored=true$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'missing or duplicate isolated native command-palette acceptance',
  );
  _expect(
    RegExp(
          r'^NATIVE_ACTION_MENU installed=true sections=6 actions=15$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'missing or duplicate standard action-menu projection observation',
  );
  RegExp menuAction(String action) => RegExp(
    '^NATIVE_MENU_ACTION negotiated=6 action=$action protocol=6 '
    r'source_generation=[1-9][0-9]* operation_id=0 '
    r'timestamp_ns=[1-9][0-9]*$',
    multiLine: true,
  );
  for (final String action in <String>[
    'application.open-command-palette',
    'paste',
    'close',
    'quit',
  ]) {
    _expect(
      menuAction(action).allMatches(observation.stdoutText).length == 1,
      'missing or duplicate $action menu-action observation',
    );
  }
  final RegExp pasteboardSnapshot = RegExp(
    r'^NATIVE_PASTEBOARD_SNAPSHOT change_count=[0-9]+ '
    r'has_text=(true|false)$',
    multiLine: true,
  );
  _expect(
    pasteboardSnapshot.allMatches(observation.stdoutText).length == 1,
    'missing or duplicate pasteboard snapshot observation',
  );
  final RegExp closeRequest = RegExp(
    r'^NATIVE_WINDOW_CLOSE_REQUEST negotiated=6 protocol=6 '
    r'source_generation=[1-9][0-9]* operation_id=[1-9][0-9]* '
    r'timestamp_ns=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    closeRequest.allMatches(observation.stdoutText).length == 2,
    'close confirmation did not produce two deferred close requests',
  );
  final RegExp paneStarted = RegExp(
    r'^TERMINAL_PANE event=started pane=([1-9][0-9]*) '
    r'session=([1-9][0-9]*):([1-9][0-9]*)$',
    multiLine: true,
  );
  final RegExpMatch? paneMatch = paneStarted.firstMatch(observation.stdoutText);
  _expect(
    paneMatch != null &&
        paneMatch.group(1) == paneMatch.group(2) &&
        paneMatch.group(3) == '1',
    'application did not publish one pane-owned session identity',
  );
  final String pane = paneMatch!.group(1)!;
  final String session = '${paneMatch.group(2)}:${paneMatch.group(3)}';
  _expectSinglePaneApplicationModel(
    observation.stdoutText,
    pane: pane,
    session: session,
  );
  final List<String> closeDecisions = observation.stdoutText
      .split('\n')
      .where((String line) => line.startsWith('TERMINAL_PANE_CLOSE '))
      .toList();
  _expect(
    closeDecisions.length == 2 &&
        closeDecisions[0] ==
            'TERMINAL_PANE_CLOSE pane=$pane session=$session '
                'decision=confirmation-required state=confirmationPending' &&
        closeDecisions[1] ==
            'TERMINAL_PANE_CLOSE pane=$pane session=$session '
                'decision=allow state=closing',
    'application close decisions did not preserve pane/session ownership: '
    '$closeDecisions',
  );
  final RegExp paneLifecycle = RegExp(
    '^TERMINAL_PANE_LIFECYCLE pane=$pane session=$session '
    r'state=([A-Za-z]+)$',
  );
  final List<String> paneStates = observation.stdoutText
      .split('\n')
      .map(paneLifecycle.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
  _expect(
    _containsOrderedValues(paneStates, const <String>[
      'created',
      'starting',
      'running',
      'confirmationPending',
      'closing',
      'closed',
    ]),
    'pane lifecycle diagnostics are incomplete or out of order: $paneStates',
  );
  final RegExp ptyLifecycle = RegExp(
    '^TERMINAL_PTY_LIFECYCLE pane=$pane session=$session '
    r'process_id=[0-9]+ stage=([A-Za-z]+)$',
  );
  final List<String> ptyStages = observation.stdoutText
      .split('\n')
      .map(ptyLifecycle.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
  _expect(
    _containsOrderedValues(ptyStages, const <String>[
      'startRequested',
      'processStarted',
      'disposeStarted',
      'gracefulCloseRequested',
      'nativeExitObserved',
      'outputDrainStarted',
      'outputDrained',
      'terminationCompleted',
      'terminationWaitCompleted',
      'outputCancellationStarted',
      'outputCancellationCompleted',
      'processDisposeStarted',
      'processDisposeCompleted',
      'shutdownResultPublished',
      'disposeCompleted',
    ]),
    'PTY lifecycle diagnostics are incomplete or out of order: $ptyStages',
  );
  final List<String> nativePtyStages = _nativePtyStages(
    observation.stdoutText,
    pane: pane,
    session: session,
  );
  _expect(
    _containsOrderedValues(nativePtyStages, const <String>[
      'stateSnapshot',
      'termiosSnapshot',
      'signalDelivery',
      'processExitReady',
      'waitpidResult',
      'exitPublished',
    ]),
    'native PTY close boundaries are incomplete or out of order: '
    '$nativePtyStages',
  );
  _expect(
    RegExp(
          '^TERMINAL_SESSION_SHUTDOWN pane=$pane session=$session '
          r'process_id=[1-9][0-9]* disposition=clean '
          r'termination_observed=true cleanup_completed=true$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'normal PTY shutdown did not publish exactly one clean session result',
  );
  _expect(
    RegExp(
          r'^TERMINAL_PANE_OWNER_SHUTDOWN pane_count=1 disposition=clean$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'normal PTY shutdown did not publish one clean owner result',
  );
  _expectWorkerProcessContract(
    observation,
    scenario: 'normal',
    expectedCount: 1,
  );
  await _runShellExitPolicySmoke(options, invocation, cleanControlD: true);
  await _runShellExitPolicySmoke(options, invocation, cleanControlD: false);
  stdout.writeln(
    'RUNTIME_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'elapsed_ms=${observation.elapsed.inMilliseconds}',
  );
}

void _expectSinglePaneApplicationModel(
  String output, {
  required String pane,
  required String session,
}) {
  _expect(
    RegExp(
          '^TERMINAL_APPLICATION_MODEL windows=1 tabs=1 panes=1 '
          r'window=1 tab=1 split_leaf=1 '
          'pane=$pane session=$session '
          r'active=true selected=true focused=true$',
          multiLine: true,
        ).allMatches(output).length ==
        1,
    'application did not publish exactly one indexed single-pane hierarchy',
  );
}

Future<void> _runTerminalDisplay(
  _Options options,
  _Invocation invocation,
) async {
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    const <String>['--runtime-terminal-display-test'],
    environment: const <String, String>{
      'DT_RUNTIME_TERMINAL_DISPLAY_TEST': '1',
    },
    timeout: const Duration(seconds: 15),
  );
  _expect(
    observation.status == 0,
    'terminal display application exited with status ${observation.status}; '
    'stdout=${observation.stdoutText.trim()} '
    'stderr=${observation.stderrText.trim()}',
  );
  _expect(
    observation.stderrText.trim().isEmpty,
    'terminal display application wrote unexpected stderr: '
    '${observation.stderrText.trim()}',
  );
  _expect(
    observation.stdoutText.contains(
      'NATIVE_CUSTOM_VIEW '
      'provider=dart_terminal.TerminalMetalView attached=true '
      'renderer_bound=true',
    ),
    'terminal display launch did not use the default Metal surface',
  );
  _expect(
    RegExp(
          r'^TERMINAL_TERMINFO_ENVIRONMENT disposition=bundled '
          r'term=xterm-256color private_database=true '
          r'compiled_bytes=[1-9][0-9]* ssh_term=xterm-256color '
          r'ssh_private_database=false$',
          multiLine: true,
        ).hasMatch(observation.stdoutText) &&
        observation.stdoutText.contains(
          'TERMINAL_TERMINFO_TEST local=true standard_name=true '
          'compiled_lookup=true ssh_standard_name=true '
          'ssh_private_path=false',
        ),
    'terminal display launch did not install local terminfo with SSH fallback',
  );
  _expect(
    observation.stdoutText.contains(
      'NATIVE_TEXT_INPUT_CLIENT attached=true routing=appkit-only client_id=',
    ),
    'terminal display launch did not attach its native text-input client',
  );
  final RegExp textInputAcceptance = RegExp(
    r'^TERMINAL_TEXT_INPUT_TEST raw=true preedit=true commit_once=true '
    r'cancel=true candidate=true geometry_generation=[1-9][0-9]* '
    r'frame_build_delta=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    textInputAcceptance.hasMatch(observation.stdoutText) &&
        !observation.stdoutText.contains('TERMINAL_TEXT_INPUT_OVERFLOW'),
    'terminal display launch omitted exclusive IME/PTY acceptance',
  );
  final RegExp inputMatrixAcceptance = RegExp(
    r'^TERMINAL_INPUT_MATRIX_TEST version=1 rows=12 events=13 bytes=51 '
    r'categories=7 us=true jis=true dead_key=true cjk=true emoji=true '
    r'unicode_hex=true repeat=true exact=true$',
    multiLine: true,
  );
  _expect(
    inputMatrixAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact input-source matrix acceptance',
  );
  _expect(
    observation.stdoutText.contains(
      'TERMINAL_DECRQSS_TEST selector=sgr default=true xterm=true '
      'exact=true bytes=9',
    ),
    'terminal display launch omitted exact DECRQSS SGR PTY acceptance',
  );
  final RegExp queryReportAcceptance = RegExp(
    r'^TERMINAL_QUERY_REPORT_TEST xtversion=true pixels=true '
    r'characters=true exact=true identity=DartTerminal\(1\) '
    r'width=[1-9][0-9]* height=[1-9][0-9]* '
    r'rows=[1-9][0-9]* columns=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    queryReportAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact XTVERSION/XTWINOPS acceptance',
  );
  final RegExp mouseAcceptance = RegExp(
    r'^TERMINAL_MOUSE_TEST protocols=5 x10=true utf8=true urxvt=true '
    r'sgr=true pixel=true local=true shift_override=true exact=true reports=6 '
    r'local_intents=6 bytes=[1-9][0-9]* pixel_bytes=[1-9][0-9]* '
    r'scale_16_16=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    mouseAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact mouse/selection arbitration',
  );
  final RegExp focusAcceptance = RegExp(
    r'^TERMINAL_FOCUS_TEST mode=true blur=true duplicate=true focus=true '
    r'reset=true exact=true reports=2 bytes=6$',
    multiLine: true,
  );
  _expect(
    focusAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact native focus reporting',
  );
  final RegExp selectionAcceptance = RegExp(
    r'^TERMINAL_SELECTION_TEST character=true word=true line=true '
    r'reverse=true shift_override=true autoscroll_up=true '
    r'autoscroll_down=true metal=true local_only=true$',
    multiLine: true,
  );
  _expect(
    selectionAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact local selection acceptance',
  );
  final RegExp closeScrollAcceptance = RegExp(
    r'^TERMINAL_CLOSE_SCROLL_TEST requests=3 refused=true '
    r'chrome_press_ignored=true offset_preserved=true rows_preserved=true '
    r'selection_preserved=true$',
    multiLine: true,
  );
  _expect(
    closeScrollAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted refused-close viewport acceptance',
  );
  final RegExp scrollAcceptance = RegExp(
    r'^TERMINAL_SCROLL_TEST protocol=6 precise=true momentum=true '
    r'wheel=true mouse_report=true shift_override=true alternate=true '
    r'app_cursor=true local=true metal=true exclusive=true reports=1 '
    r'local=4 alternate_inputs=1 ignored=3 bytes=20 alternate_bytes=6$',
    multiLine: true,
  );
  _expect(
    scrollAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted exact precision-scroll acceptance',
  );
  final RegExp hyperlinkAcceptance = RegExp(
    r'^TERMINAL_HYPERLINK_TEST osc8=true hover=true metal=true '
    r'allowed=true blocked=true exact=true command_exclusive=true opens=1 '
    r'blocked_notices=1 local_passthrough=2$',
    multiLine: true,
  );
  _expect(
    hyperlinkAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted safe hyperlink hover/open acceptance',
  );
  final RegExp windowTitleAcceptance = RegExp(
    r'^TERMINAL_WINDOW_TITLE_TEST metadata=true native=true stack=true '
    r'reset=true fallback=true proxy=true$',
    multiLine: true,
  );
  _expect(
    windowTitleAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted native window-title acceptance',
  );
  final RegExp cursorColorAcceptance = RegExp(
    r'^TERMINAL_CURSOR_COLOR_TEST mutation=true text_independent=true '
    r'presentation=true metal=true reset=true$',
    multiLine: true,
  );
  _expect(
    cursorColorAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted independent cursor-color acceptance',
  );
  final RegExp accessibilityAcceptance = RegExp(
    r'^TERMINAL_ACCESSIBILITY_TEST visible=true selection=true '
    r'cursor=true native=true focus=true notifications=true$',
    multiLine: true,
  );
  _expect(
    accessibilityAcceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted native accessibility acceptance',
  );
  final RegExp acceptance = RegExp(
    r'^TERMINAL_DISPLAY_TEST sgr_stripped=true styled=true '
    r'wrapped_rows=([2-9]|[1-9][0-9]+) prompt_bottom=true '
    r'metal_default=true newest_frame=true frame_bounded=true '
    r'system_font=true mode_key=true text_input=true input_matrix=true '
    r'decrqss=true query_reports=true focus=true mouse=true selection=true '
    r'close_scroll=true scroll=true '
    r'hyperlink=true '
    r'window_title=true cursor_color=true accessibility=true font_size=14\.0 '
    r'rows=([4-9]|[1-9][0-9]+) '
    r'columns=([2-9][0-9]|[1-9][0-9]{2,}) '
    r'frame_build_delta=[1-9][0-9]*$',
    multiLine: true,
  );
  _expect(
    acceptance.hasMatch(observation.stdoutText),
    'terminal display launch omitted its content-free acceptance result',
  );
  _expect(
    observation.stdoutText.contains('Dart Terminal shut down cleanly.'),
    'terminal display launch did not complete clean ownership teardown',
  );
  stdout.writeln(
    'RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'elapsed_ms=${observation.elapsed.inMilliseconds}',
  );
}

Future<void> _runClipboardProduct(
  _Options options,
  _Invocation invocation,
) async {
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    const <String>['--runtime-clipboard-test'],
    environment: const <String, String>{'DT_RUNTIME_CLIPBOARD_TEST': '1'},
    timeout: const Duration(seconds: 60),
  );
  _expect(
    observation.status == 0,
    'clipboard application exited with status ${observation.status}; '
    'stdout=${observation.stdoutText.trim()} '
    'stderr=${observation.stderrText.trim()}',
  );
  _expect(
    observation.stderrText.trim().isEmpty,
    'clipboard application wrote unexpected stderr: '
    '${observation.stderrText.trim()}',
  );
  final RegExp acceptance = RegExp(
    r'^TERMINAL_CLIPBOARD_TEST copy=true paste_menu=true '
    r'osc52_denied=true '
    r'confirmation=true confirmation_visible=true zero_write=true '
    r'bracketed=true exact=true '
    r'bytes=10485772 chunks=641 max_queue=([1-9][0-9]*) '
    r'planning_yields=2 '
    r'timer_ticks=([1-9][0-9]*)$',
    multiLine: true,
  );
  final RegExpMatch? match = acceptance.firstMatch(observation.stdoutText);
  _expect(
    match != null && int.parse(match.group(1)!) <= 16 * 1024,
    'clipboard launch omitted bounded exact 10 MiB acceptance',
  );
  _expect(
    observation.stdoutText.contains(
          'TERMINAL_OSC52_POLICY_TEST query_empty=true write_denied=true '
          'clear_denied=true clipboard_callbacks=0 counters=true',
        ) &&
        observation.stdoutText.contains(
          'TERMINAL_CLIPBOARD_COPY_TEST selection=true menu=true exact=true '
          'cjk_individual=true cjk_wide=true local_only=true bytes=9',
        ) &&
        observation.stdoutText.contains('Dart Terminal shut down cleanly.'),
    'clipboard launch omitted selection Copy or clean ownership teardown',
  );
  stdout.writeln(
    'RUNTIME_CLIPBOARD_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'elapsed_ms=${observation.elapsed.inMilliseconds}',
  );
}

Future<void> _runNativeHierarchy(
  _Options options,
  _Invocation invocation,
) async {
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    const <String>['--runtime-native-hierarchy-test'],
    environment: const <String, String>{
      'DT_RUNTIME_NATIVE_HIERARCHY_TEST': '1',
    },
    timeout: const Duration(seconds: 120),
  );
  _expect(
    observation.status == 0,
    'native hierarchy application exited with status ${observation.status}; '
    'stdout=${observation.stdoutText.trim()} '
    'stderr=${observation.stderrText.trim()}',
  );
  _expect(
    observation.stderrText.trim().isEmpty,
    'native hierarchy application wrote unexpected stderr: '
    '${observation.stderrText.trim()}',
  );
  _expect(
    RegExp(
          r'^TERMINAL_NATIVE_HIERARCHY_TEST windows=1 tabs=2 panes=4 '
          r'splits=2 resize=true equalize=true zoom=true focus=true key=true '
          r'ime=true menu_shortcut=true isolated=true close=true '
          r'sessions_clean=4 metal_clean=4 '
          r'text_clients=0 native_handles=0$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'native hierarchy acceptance summary is missing or malformed',
  );
  _expect(
    RegExp(
          r'^TERMINAL_HIERARCHY_MENU_SHORTCUT_TEST panes=4 shortcut=true '
          r'action=pane\.focus-next invocations=1 terminal_write_delta=0 '
          r'focused_only=true first_responder=true handles_restored=true$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'native hierarchy omitted isolated command-palette shortcut routing',
  );
  _expect(
    RegExp(
          r'^TERMINAL_CLOSE_QUIT_TEST panes=4 close_requests=3 close_menu=3 '
          r'quit_menu=2 native_quit_requests=2 '
          r'foreground_confirmation=true non_live_immediate=true '
          r'quit_atomic=true native_refused=true '
          r'programmatic_termination=1 sessions_clean=4 metal_clean=4 '
          r'text_clients=0 native_handles=0$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'native hierarchy acceptance omitted the exact Close/Quit lifecycle',
  );
  _expect(
    RegExp(
          r'^TERMINAL_TAB_METADATA_TEST title=true rename=true color=true '
          r'cwd_inheritance=true proxy=true reset=true$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'native hierarchy acceptance omitted tab metadata and cwd inheritance',
  );
  _expect(
    RegExp(
          r'^TERMINAL_MULTI_PANE_FAIRNESS_TEST bytes=104857600 panes=4 '
          r'baseline_samples=3 input_visible=true '
          r'input_completed_during_flood=true flood_complete=true '
          r'scheduler_registered=4 scheduler_pending_bound=4 '
          r'scheduler_work_bound=4 scheduler_yielded=true '
          r'frames_bounded=true$',
          multiLine: true,
        ).allMatches(observation.stdoutText).length ==
        1,
    'native hierarchy acceptance omitted cross-pane flood fairness',
  );
  final RegExpMatch? fairnessMeasurement = RegExp(
    r'^TERMINAL_MULTI_PANE_FAIRNESS_MEASUREMENT '
    r'baseline_us=([1-9][0-9]*) flood_us=([1-9][0-9]*) '
    r'ratio_milli=([1-9][0-9]*) input_during_flood=true '
    r'scheduler_registered=4 scheduler_pending=([0-4]) '
    r'scheduler_yields=([1-9][0-9]*) scheduler_yields_before=([0-9]+) '
    r'scheduler_peak_pending=([1-4]) '
    r'scheduler_max_work_observed=([1-4]) '
    r'flood_frame_advanced=true frames_bounded=true$',
    multiLine: true,
  ).firstMatch(observation.stdoutText);
  _expect(
    fairnessMeasurement != null,
    'native hierarchy fairness measurement is missing or malformed',
  );
  final int idleBaselineMicros = int.parse(fairnessMeasurement!.group(1)!);
  final int floodLatencyMicros = int.parse(fairnessMeasurement.group(2)!);
  final int ratioMilli = int.parse(fairnessMeasurement.group(3)!);
  final int schedulerYields = int.parse(fairnessMeasurement.group(5)!);
  final int schedulerYieldsBefore = int.parse(fairnessMeasurement.group(6)!);
  _expect(
    floodLatencyMicros <= idleBaselineMicros * 2 &&
        schedulerYields > schedulerYieldsBefore &&
        ratioMilli ==
            (floodLatencyMicros * 1000 + idleBaselineMicros - 1) ~/
                idleBaselineMicros,
    'native hierarchy cross-pane response exceeded 2x idle baseline',
  );
  _expect(
    !observation.stdoutText.contains('TERMINAL_TEXT_INPUT_OVERFLOW') &&
        !observation.stdoutText.contains('HIERARCHY_MISMATCH'),
    'native hierarchy input was not isolated',
  );
  _expect(
    RegExp(
              r'^TERMINAL_SESSION_SHUTDOWN pane=[1-4] session=[1-4]:1 '
              r'process_id=[1-9][0-9]* disposition=clean '
              r'termination_observed=true cleanup_completed=true$',
              multiLine: true,
            ).allMatches(observation.stdoutText).length ==
            4 &&
        RegExp(
              r'^TERMINAL_PANE_OWNER_SHUTDOWN pane_count=4 disposition=clean$',
              multiLine: true,
            ).allMatches(observation.stdoutText).length ==
            1,
    'native hierarchy did not cleanly shut down four exact PTY owners',
  );
  _expect(
    observation.stdoutText.contains('Dart Terminal shut down cleanly.'),
    'native hierarchy did not finish clean application teardown',
  );
  _expectWorkerProcessContract(
    observation,
    scenario: 'normal',
    expectedCount: 1,
  );
  stdout.writeln(
    'RUNTIME_NATIVE_HIERARCHY_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'tabs=2 panes=4 baseline_us=$idleBaselineMicros '
    'flood_us=$floodLatencyMicros ratio_milli=$ratioMilli '
    'scheduler_yields=$schedulerYields '
    'elapsed_ms=${observation.elapsed.inMilliseconds}',
  );
}

Future<void> _runRestoration(_Options options, _Invocation invocation) async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'dart-terminal-restoration-',
  );
  final String persistencePath = '${directory.path}/state.json';
  try {
    final _ProcessObservation observation = await _launch(
      options,
      invocation,
      const <String>['--runtime-restoration-test'],
      environment: <String, String>{
        'DT_RUNTIME_RESTORATION_TEST': '1',
        'DT_RUNTIME_RESTORATION_PATH': persistencePath,
      },
      timeout: const Duration(seconds: 60),
      throughLaunchServices: true,
    );
    _expect(
      observation.status == 0,
      'restoration application exited with status ${observation.status}; '
      'stdout=${observation.stdoutText.trim()} '
      'stderr=${observation.stderrText.trim()}',
    );
    _expect(
      observation.stderrText.trim().isEmpty,
      'restoration application wrote unexpected stderr: '
      '${observation.stderrText.trim()}',
    );
    _expect(
      RegExp(
            r'^TERMINAL_RESTORATION_TEST windows=2 tabs=4 panes=8 '
            r'panes_per_window=4 generations=2 sessions_clean=16 '
            r'fullscreen_enter=true '
            r'fullscreen_exit=true screen_migration=true frame_clamped=true '
            r'scale=true persisted=true reopen_events=2 coalesced=true '
            r'fresh_ids=true cwd=true metal_clean=16 text_clients=0 '
            r'native_handles=0$',
            multiLine: true,
          ).allMatches(observation.stdoutText).length ==
          1,
      'restoration acceptance summary is missing or malformed',
    );
    _expect(
      RegExp(
                r'^TERMINAL_SESSION_SHUTDOWN pane=([1-9]|1[0-6]) '
                r'session=([1-9]|1[0-6]):1 '
                r'process_id=[1-9][0-9]* disposition=clean '
                r'termination_observed=true cleanup_completed=true$',
                multiLine: true,
              ).allMatches(observation.stdoutText).length ==
              16 &&
          RegExp(
                r'^TERMINAL_PANE_OWNER_SHUTDOWN pane_count=16 '
                r'disposition=clean$',
                multiLine: true,
              ).allMatches(observation.stdoutText).length ==
              1,
      'restoration did not cleanly shut down eight exact PTY owners',
    );
    _expect(
      RegExp(
                r'^TERMINAL_RESTORATION event=defaultCreated windows=1 '
                r'tabs=1 panes=1$',
                multiLine: true,
              ).allMatches(observation.stdoutText).length ==
              1 &&
          RegExp(
                r'^TERMINAL_RESTORATION event=reopened windows=2 tabs=4 '
                r'panes=8$',
                multiLine: true,
              ).allMatches(observation.stdoutText).length ==
              1,
      'restoration omitted its content-free generation diagnostics',
    );
    final File persistenceFile = File(persistencePath);
    _expect(await persistenceFile.exists(), 'restoration file is missing');
    final FileStat persistenceStat = await persistenceFile.stat();
    _expect(
      persistenceStat.type == FileSystemEntityType.file &&
          persistenceStat.size > 0 &&
          persistenceStat.size <= 512 * 1024,
      'restoration file type or serialized bound is invalid',
    );
    final String encoded = await persistenceFile.readAsString();
    final Object? decoded = jsonDecode(encoded);
    _expect(
      decoded is Map<String, dynamic> &&
          decoded['version'] == 1 &&
          decoded['windows'] is List<dynamic> &&
          (decoded['windows'] as List<dynamic>).length == 2 &&
          !encoded.contains('__DT_RESTORATION_PROMPT__') &&
          !encoded.contains('__DT_RESTORED_CWD_') &&
          !observation.stdoutText.contains(persistencePath) &&
          !observation.stdoutText.contains('TERMINAL_TEXT_INPUT_OVERFLOW') &&
          observation.stdoutText.contains('Dart Terminal shut down cleanly.'),
      'restoration persistence or ordinary output leaked terminal content/path',
    );
    _expectWorkerProcessContract(
      observation,
      scenario: 'normal',
      expectedCount: 1,
    );
    stdout.writeln(
      'RUNTIME_RESTORATION_INTEGRATION_PASS mode=${options.mode.name} '
      'launch_architecture=${options.launchArchitecture ?? 'native'} '
      'generations=2 windows=2 tabs=4 panes=8 elapsed_ms='
      '${observation.elapsed.inMilliseconds}',
    );
  } finally {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<void> _runShellExitPolicySmoke(
  _Options options,
  _Invocation invocation, {
  required bool cleanControlD,
}) async {
  final String scenario = cleanControlD ? 'clean-control-d' : 'nonzero';
  final String disposition = cleanControlD ? 'clean' : 'nonZero';
  final String action = cleanControlD ? 'close' : 'retain';
  final int expectedShellExit = cleanControlD ? 0 : 23;
  final int expectedKernelStatus = expectedShellExit << 8;
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    <String>['--runtime-shell-exit-test=$scenario'],
    environment: const <String, String>{'DT_RUNTIME_SHELL_EXIT_TEST': '1'},
    timeout: const Duration(seconds: 15),
  );
  _expect(
    observation.status == 0,
    '$scenario app exited with status ${observation.status}; '
    'stdout=${observation.stdoutText.trim()} '
    'stderr=${observation.stderrText.trim()}',
  );
  _expect(
    observation.stderrText.trim().isEmpty,
    '$scenario app wrote unexpected stderr: ${observation.stderrText.trim()}',
  );
  final RegExp paneStarted = RegExp(
    r'^TERMINAL_PANE event=started pane=([1-9][0-9]*) '
    r'session=([1-9][0-9]*):([1-9][0-9]*)$',
    multiLine: true,
  );
  final RegExpMatch? paneMatch = paneStarted.firstMatch(observation.stdoutText);
  _expect(
    paneMatch != null &&
        paneMatch.group(1) == paneMatch.group(2) &&
        paneMatch.group(3) == '1',
    '$scenario did not publish one pane-owned session identity',
  );
  final String pane = paneMatch!.group(1)!;
  final String session = '${paneMatch.group(2)}:${paneMatch.group(3)}';
  final List<String> nativeStages = _nativePtyStages(
    observation.stdoutText,
    pane: pane,
    session: session,
  );
  final bool externallyReaped = nativeStages.contains('externalReapObserved');
  final bool ptyOwnedReap = RegExp(
    '^TERMINAL_PTY_NATIVE pane=$pane session=$session '
    r'process_id=[0-9]+ stage=waitpidResult .*'
    r'waitpid_result=[1-9][0-9]* .*errno=0$',
    multiLine: true,
  ).hasMatch(observation.stdoutText);
  _expect(
    externallyReaped || ptyOwnedReap,
    '$scenario observed exit readiness without a classified reap owner',
  );
  final List<String> expectedExitBoundary = externallyReaped
      ? const <String>[
          'processExitReady',
          'externalReapObserved',
          'exitPublished',
        ]
      : const <String>['processExitReady', 'waitpidResult', 'exitPublished'];
  _expect(
    _containsOrderedValues(nativeStages, expectedExitBoundary),
    '$scenario did not publish its classified kernel-to-Dart PTY exit '
    'boundary: $nativeStages',
  );
  _expect(
    RegExp(
      '^TERMINAL_PTY_NATIVE pane=$pane session=$session '
      r'process_id=[0-9]+ stage=processExitReady .*'
      'child_status=$expectedKernelStatus child_status_valid=true .*errno=0\$',
      multiLine: true,
    ).hasMatch(observation.stdoutText),
    '$scenario did not preserve the valid kernel exit status; '
    'native=${observation.stdoutText.split('\n').where((String line) => line.contains('stage=processExitReady')).join(' | ')}',
  );
  _expect(
    RegExp(
      '^TERMINAL_PTY_NATIVE pane=$pane session=$session '
      r'process_id=[0-9]+ stage=exitPublished .*'
      'exit_code=$expectedShellExit exit_signal=0 errno=0\$',
      multiLine: true,
    ).hasMatch(observation.stdoutText),
    '$scenario did not publish the decoded shell exit status',
  );
  final String policyLine =
      'TERMINAL_PANE_EXIT pane=$pane session=$session '
      'disposition=$disposition action=$action';
  _expect(
    observation.stdoutText
            .split('\n')
            .where((String line) => line == policyLine)
            .length ==
        1,
    '$scenario did not publish exactly one $action pane policy decision',
  );
  _expect(
    RegExp(
      '^TERMINAL_SHELL_EXIT_TEST scenario=$scenario '
      'shell_exit=$expectedShellExit action=$action worker_pid=[1-9][0-9]*\$',
      multiLine: true,
    ).hasMatch(observation.stdoutText),
    '$scenario did not complete while the runtime worker was active',
  );
  final List<String> closeDecisions = observation.stdoutText
      .split('\n')
      .where((String line) => line.startsWith('TERMINAL_PANE_CLOSE '))
      .toList();
  _expect(
    closeDecisions.length == 1 &&
        closeDecisions.single ==
            'TERMINAL_PANE_CLOSE pane=$pane session=$session '
                'decision=allow state=closing',
    '$scenario shell exit did not close its non-live pane in one step: '
    '$closeDecisions',
  );
  final int workerReady = observation.stdoutText.indexOf(
    'RUNTIME_LIFECYCLE event=root-ready',
  );
  final int exitPublished = observation.stdoutText.indexOf(
    'stage=exitPublished',
  );
  final int workerStop = observation.stdoutText.indexOf(
    'RUNTIME_LIFECYCLE event=worker-stop-request',
  );
  _expect(
    workerReady >= 0 &&
        exitPublished > workerReady &&
        workerStop > exitPublished,
    '$scenario did not exit zsh while the runtime worker remained active',
  );
  _expect(
    observation.stdoutText.contains('Dart Terminal shut down cleanly.'),
    '$scenario did not complete product cleanup cleanly',
  );
  _expectWorkerProcessContract(
    observation,
    scenario: 'normal',
    expectedCount: 1,
  );
}

const Map<String, String> _lifecycleGate = <String, String>{
  'DT_RUNTIME_LIFECYCLE_TEST': '1',
};

List<String> _expected(List<String> events) => <String>[
  for (final String event in events) '$event:${event == 'root-start' ? 0 : 1}',
];

List<_LifecycleCase> _lifecycleCases() => <_LifecycleCase>[
  _LifecycleCase(
    name: 'normal',
    machineScenario: 'normal',
    applicationArguments: const <String>['--auto-close-after=1'],
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-response',
      'worker-stop-request',
      'worker-stop-ack',
      'worker-exit',
      'root-exit',
    ]),
  ),
  for (final String scenario in <String>[
    'worker-sync-uncaught',
    'worker-async-uncaught',
  ])
    _LifecycleCase(
      name: scenario,
      machineScenario: scenario,
      applicationArguments: <String>['--runtime-lifecycle-scenario=$scenario'],
      environment: _lifecycleGate,
      expectedStatus: 0,
      expectedObservations: _expected(const <String>[
        'root-start',
        'worker-start',
        'worker-ready',
        'root-ready',
        'worker-request',
        'worker-error',
        'worker-exit',
        'root-exit',
      ]),
    ),
  _LifecycleCase(
    name: 'worker-unexpected-exit',
    machineScenario: 'worker-unexpected-exit',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-unexpected-exit',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-unexpected-exit',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'worker-startup-failure',
    machineScenario: 'worker-startup-failure',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-startup-failure',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-error',
      'worker-startup-failure',
      'worker-exit',
      'root-ready',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'worker-idle-uncaught',
    machineScenario: 'worker-idle-uncaught',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-idle-uncaught',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-error',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'worker-idle-exit',
    machineScenario: 'worker-idle-exit',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-idle-exit',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-unexpected-exit',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'worker-stop-uncaught',
    machineScenario: 'worker-stop-uncaught',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-stop-uncaught',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-response',
      'worker-stop-request',
      'worker-error',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'shutdown-timeout',
    machineScenario: 'shutdown-timeout',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=shutdown-timeout',
    ],
    environment: _lifecycleGate,
    expectedStatus: 75,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-response',
      'worker-stop-request',
      'worker-stop-timeout',
      'worker-force-kill',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'late-completion',
    machineScenario: 'late-completion',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=late-completion',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-stop-request',
      'worker-stop-ack',
      'late-completion-ignored',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'double-shutdown',
    machineScenario: 'double-shutdown',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=double-shutdown',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-response',
      'worker-stop-request',
      'shutdown-idempotent',
      'worker-stop-ack',
      'worker-exit',
      'root-exit',
    ]),
  ),
  _LifecycleCase(
    name: 'worker-replacement',
    machineScenario: 'worker-replacement',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=worker-replacement',
    ],
    environment: _lifecycleGate,
    expectedStatus: 0,
    expectedWorkerProcessCount: 2,
    expectedObservations: const <String>[
      'root-start:0',
      'worker-start:1',
      'worker-ready:1',
      'root-ready:1',
      'worker-request:1',
      'worker-unexpected-exit:1',
      'worker-exit:1',
      'worker-start:2',
      'worker-ready:2',
      'worker-request:2',
      'worker-response:2',
      'worker-stop-request:2',
      'worker-stop-ack:2',
      'worker-exit:2',
      'root-exit:2',
    ],
  ),
  _LifecycleCase(
    name: 'root-startup-failure',
    machineScenario: 'root-startup-failure',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=root-startup-failure',
    ],
    environment: _lifecycleGate,
    expectedStatus: 70,
    expectedObservations: _expected(const <String>['root-start']),
    expectedStderrMarker:
        'RUNTIME_LIFECYCLE_FATAL class=root-startup status=70',
    expectedWorkerProcessCount: 0,
    expectedDiagnosticPhase: 'root-starting',
  ),
  _LifecycleCase(
    name: 'root-uncaught',
    machineScenario: 'root-uncaught',
    applicationArguments: const <String>[
      '--runtime-lifecycle-scenario=root-uncaught',
    ],
    environment: _lifecycleGate,
    expectedStatus: 70,
    expectedObservations: _expected(const <String>[
      'root-start',
      'worker-start',
      'worker-ready',
      'root-ready',
      'worker-request',
      'worker-response',
      'root-uncaught',
      'worker-stop-request',
      'worker-stop-ack',
      'worker-exit',
      'root-exit',
    ]),
    expectedStderrMarker:
        'RUNTIME_LIFECYCLE_FATAL class=root-uncaught status=70',
  ),
  const _LifecycleCase(
    name: 'host-startup-failure',
    applicationArguments: <String>[],
    environment: <String, String>{'DMR_RUNTIME_TEST_HOST_STARTUP_FAILURE': '1'},
    expectedStatus: 70,
    expectedObservations: <String>[],
    expectedStderrMarker:
        'RUNTIME_LIFECYCLE_FATAL class=host-startup status=70',
    expectedWorkerProcessCount: 0,
    expectedDiagnosticPhase: 'host-starting',
  ),
  const _LifecycleCase(
    name: 'usage-error',
    applicationArguments: <String>['--unsupported-lifecycle-option'],
    expectedStatus: 64,
    expectedObservations: <String>[],
    expectedStderrMarker:
        'Argument error: unknown application option: '
        '--unsupported-lifecycle-option',
    expectedWorkerProcessCount: 0,
    expectedDiagnosticPhase: 'root-starting',
  ),
];

Future<void> _runLifecycle(_Options options, _Invocation invocation) async {
  final RegExp lifecycleLine = RegExp(
    r'^RUNTIME_LIFECYCLE event=([a-z-]+) scenario=([a-z-]+) generation=([0-9]+)$',
  );
  for (final _LifecycleCase testCase in _lifecycleCases()) {
    final _ProcessObservation result = await _launch(
      options,
      invocation,
      testCase.applicationArguments,
      environment: testCase.environment,
      expectedDiagnosticPhase: testCase.expectedDiagnosticPhase,
    );
    _expect(
      result.status == testCase.expectedStatus,
      '${testCase.name} status ${result.status} != '
      '${testCase.expectedStatus}; stdout=${result.stdoutText.trim()} '
      'stderr=${result.stderrText.trim()}',
    );
    final List<String> observations = <String>[];
    for (final String line in result.stdoutText.split('\n')) {
      if (!line.startsWith('RUNTIME_LIFECYCLE ')) {
        continue;
      }
      final RegExpMatch? match = lifecycleLine.firstMatch(line);
      _expect(match != null, '${testCase.name} malformed observation: $line');
      _expect(
        match!.group(2) == testCase.machineScenario,
        '${testCase.name} reported scenario ${match.group(2)}',
      );
      observations.add('${match.group(1)}:${match.group(3)}');
    }
    _expect(
      _sameStrings(observations, testCase.expectedObservations),
      '${testCase.name} observations $observations != '
      '${testCase.expectedObservations}',
    );
    final String errors = result.stderrText.trim();
    if (testCase.expectedStderrMarker == null) {
      _expect(errors.isEmpty, '${testCase.name} unexpected stderr: $errors');
    } else {
      _expect(
        errors.contains(testCase.expectedStderrMarker!),
        '${testCase.name} missing stderr marker: $errors',
      );
    }
    _expectWorkerProcessContract(
      result,
      scenario: testCase.machineScenario ?? testCase.name,
      expectedCount: testCase.expectedWorkerProcessCount,
    );
    stdout.writeln(
      'RUNTIME_LIFECYCLE_INTEGRATION_PASS mode=${options.mode.name} '
      'scenario=${testCase.name} status=${result.status} '
      'elapsed_ms=${result.elapsed.inMilliseconds}',
    );
  }
}

Future<void> _runTraffic(_Options options, _Invocation invocation) async {
  final _ProcessObservation result = await _launch(
    options,
    invocation,
    const <String>['--runtime-lifecycle-scenario=worker-traffic'],
    environment: _lifecycleGate,
  );
  _expect(
    result.status == 0,
    'traffic application exited with status ${result.status}; '
    'stdout=${result.stdoutText.trim()} stderr=${result.stderrText.trim()}',
  );
  _expect(
    result.stderrText.trim().isEmpty,
    'traffic application wrote stderr: ${result.stderrText.trim()}',
  );
  final RegExp summary = RegExp(
    r'^RUNTIME_WORKER_TRAFFIC requests=256 responses=256 '
    r'backpressured=([1-9][0-9]*) max_in_flight=64 '
    r'close_timer_fired=1 elapsed_ms=([1-9][0-9]*)$',
    multiLine: true,
  );
  final RegExpMatch? summaryMatch = summary.firstMatch(result.stdoutText);
  _expect(summaryMatch != null, 'traffic summary is missing or malformed');
  final int trafficElapsed = int.parse(summaryMatch!.group(2)!);
  _expect(
    trafficElapsed < 3000 && result.elapsed < const Duration(seconds: 5),
    'traffic did not preserve bounded GUI close: '
    'traffic=${trafficElapsed}ms app=${result.elapsed.inMilliseconds}ms',
  );

  final RegExp lifecycleLine = RegExp(
    r'^RUNTIME_LIFECYCLE event=([a-z-]+) scenario=worker-traffic '
    r'generation=([0-9]+)$',
  );
  final List<String> events = <String>[];
  for (final String line in result.stdoutText.split('\n')) {
    final RegExpMatch? match = lifecycleLine.firstMatch(line);
    if (match != null) {
      events.add(match.group(1)!);
    }
  }
  int count(String event) =>
      events.where((String value) => value == event).length;
  for (final String singleton in <String>[
    'root-start',
    'worker-start',
    'worker-ready',
    'root-ready',
    'worker-stop-request',
    'worker-stop-ack',
    'worker-exit',
    'root-exit',
  ]) {
    _expect(count(singleton) == 1, 'traffic event $singleton is not singular');
  }
  _expect(
    count('worker-request') == 256 &&
        count('worker-response') == 256 &&
        count('worker-backpressure') > 0,
    'traffic lifecycle counts do not prove bounded admission: $events',
  );
  _expectWorkerProcessContract(
    result,
    scenario: 'worker-traffic',
    expectedCount: 1,
  );
  stdout.writeln(
    'RUNTIME_TRAFFIC_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'backpressured=${summaryMatch.group(1)} '
    'traffic_elapsed_ms=$trafficElapsed '
    'application_elapsed_ms=${result.elapsed.inMilliseconds}',
  );
}

Future<void> _runResource(_Options options, _Invocation invocation) async {
  final _ProcessObservation result = await _launch(
    options,
    invocation,
    const <String>['--runtime-resource-stress', '--auto-close-after=1'],
    environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
    timeout: const Duration(seconds: 60),
  );
  _expect(
    result.status == 0,
    'resource application exited with status ${result.status}; '
    'stdout=${result.stdoutText.trim()} stderr=${result.stderrText.trim()}',
  );
  _expect(
    result.stderrText.trim().isEmpty,
    'resource application wrote stderr: ${result.stderrText.trim()}',
  );
  final RegExp summary = RegExp(
    r'^NATIVE_RESOURCE_STRESS iterations=1000 baseline=([0-9]+) '
    r'peak=([0-9]+) final=([0-9]+) elapsed_ms=([1-9][0-9]*)$',
    multiLine: true,
  );
  final RegExpMatch? summaryMatch = summary.firstMatch(result.stdoutText);
  _expect(summaryMatch != null, 'resource stress summary is missing');
  final int baseline = int.parse(summaryMatch!.group(1)!);
  final int peak = int.parse(summaryMatch.group(2)!);
  final int finalCount = int.parse(summaryMatch.group(3)!);
  final int stressElapsed = int.parse(summaryMatch.group(4)!);
  _expect(
    peak == baseline + 2 && finalCount == baseline,
    'resource counts do not prove a stable two-handle pair: '
    'baseline=$baseline peak=$peak final=$finalCount',
  );
  final List<String> closeStages =
      RegExp(r'^TERMINAL_RESOURCE_CLOSE stage=([a-z-]+)', multiLine: true)
          .allMatches(result.stdoutText)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
  _expect(
    _sameStrings(closeStages, const <String>[
      'initial-timer-scheduled',
      'initial-timer-fired',
      'paste-action-posted',
      'close-action-posted',
      'request-observed',
      'decision-published',
      'request-replied',
      'confirmation-timer-scheduled',
      'confirmation-timer-fired',
      'quit-action-posted',
      'request-observed',
      'decision-published',
      'request-replied',
    ]),
    'resource close confirmation did not wait for the first native reply: '
    '$closeStages',
  );
  _expect(
    RegExp(
          r'^NATIVE_RESOURCE_FINAL handles=0$',
          multiLine: true,
        ).allMatches(result.stdoutText).length ==
        1,
    'product cleanup did not report exactly one zero-handle result',
  );
  _expectWorkerProcessContract(result, scenario: 'normal', expectedCount: 1);
  stdout.writeln(
    'RUNTIME_RESOURCE_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'iterations=1000 baseline=$baseline peak=$peak '
    'stress_elapsed_ms=$stressElapsed '
    'elapsed_ms=${result.elapsed.inMilliseconds}',
  );
}

Future<void> _runShutdownFaults(
  _Options options,
  _Invocation invocation,
) async {
  final _ProcessObservation result = await _launch(
    options,
    invocation,
    const <String>[
      '--runtime-shutdown-faults',
      '--runtime-lifecycle-scenario=worker-unexpected-exit',
    ],
    environment: const <String, String>{
      'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      'DT_RUNTIME_LIFECYCLE_TEST': '1',
    },
  );
  _expect(
    result.status == 0,
    'shutdown fault application exited with status ${result.status}; '
    'stdout=${result.stdoutText.trim()} stderr=${result.stderrText.trim()}',
  );
  _expect(
    result.stderrText.trim().isEmpty,
    'shutdown fault application wrote stderr: ${result.stderrText.trim()}',
  );
  final RegExp summary = RegExp(
    r'^NATIVE_SHUTDOWN_FAULT malformed_errors=1 late_owner_events=0 '
    r'double_dispose=true continued_events=1 baseline=([0-9]+) '
    r'final=([0-9]+)$',
    multiLine: true,
  );
  final RegExpMatch? summaryMatch = summary.firstMatch(result.stdoutText);
  _expect(summaryMatch != null, 'shutdown fault summary is missing');
  _expect(
    summaryMatch!.group(1) == summaryMatch.group(2),
    'shutdown faults changed the native handle baseline',
  );
  _expect(
    RegExp(
          r'^NATIVE_SHUTDOWN_FAULT_FINAL handles=0$',
          multiLine: true,
        ).allMatches(result.stdoutText).length ==
        1,
    'shutdown fault cleanup did not report exactly one zero-handle result',
  );
  const List<String> expectedLifecycle = <String>[
    'root-start:0',
    'worker-start:1',
    'worker-ready:1',
    'root-ready:1',
    'worker-request:1',
    'worker-unexpected-exit:1',
    'worker-exit:1',
    'root-exit:1',
  ];
  final RegExp lifecycleLine = RegExp(
    r'^RUNTIME_LIFECYCLE event=([a-z-]+) '
    r'scenario=worker-unexpected-exit generation=([0-9]+)$',
  );
  final List<String> lifecycle = <String>[];
  for (final String line in result.stdoutText.split('\n')) {
    final RegExpMatch? match = lifecycleLine.firstMatch(line);
    if (match != null) {
      lifecycle.add('${match.group(1)}:${match.group(2)}');
    }
  }
  _expect(
    _sameStrings(lifecycle, expectedLifecycle),
    'shutdown fault lifecycle $lifecycle != $expectedLifecycle',
  );
  _expectWorkerProcessContract(
    result,
    scenario: 'worker-unexpected-exit',
    expectedCount: 1,
  );
  stdout.writeln(
    'RUNTIME_SHUTDOWN_FAULT_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'baseline=${summaryMatch.group(1)} '
    'elapsed_ms=${result.elapsed.inMilliseconds}',
  );
}

Future<void> _runPtyExitDeadlineFault(
  _Options options,
  _Invocation invocation,
) async {
  final _ProcessObservation result = await _launch(
    options,
    invocation,
    const <String>['--runtime-pty-exit-fault', '--auto-close-after=1'],
    environment: const <String, String>{
      'DT_RUNTIME_PTY_SHUTDOWN_FAULT_TEST': '1',
    },
  );
  _expect(
    result.status == 75,
    'PTY exit deadline application status ${result.status} != 75; '
    'stdout=${result.stdoutText.trim()} stderr=${result.stderrText.trim()}',
  );
  _expect(
    result.stderrText.trim().isEmpty,
    'PTY exit deadline application wrote stderr: ${result.stderrText.trim()}',
  );
  _expect(
    RegExp(
          r'^TERMINAL_PTY_FAULT exit_notification=suppressed gate=true$',
          multiLine: true,
        ).allMatches(result.stdoutText).length ==
        1,
    'PTY exit notification fault was not selected exactly once',
  );
  final RegExp sessionSummary = RegExp(
    r'^TERMINAL_SESSION_SHUTDOWN pane=([0-9]+) '
    r'session=([0-9]+:[0-9]+) process_id=([1-9][0-9]*) '
    r'disposition=deadlineExceeded termination_observed=false '
    r'cleanup_completed=false$',
    multiLine: true,
  );
  final RegExpMatch? summary = sessionSummary.firstMatch(result.stdoutText);
  _expect(summary != null, 'deadline-exceeded PTY summary is missing');
  final String pane = summary!.group(1)!;
  final String session = summary.group(2)!;
  _expect(
    session.startsWith('$pane:'),
    'PTY shutdown summary mixed pane/session identity: $pane/$session',
  );
  _expect(
    RegExp(
          r'^TERMINAL_PANE_OWNER_SHUTDOWN pane_count=1 '
          r'disposition=deadlineExceeded$',
          multiLine: true,
        ).allMatches(result.stdoutText).length ==
        1,
    'pane owner did not aggregate the PTY deadline exactly once',
  );
  final RegExp lifecycleLine = RegExp(
    '^TERMINAL_PTY_LIFECYCLE pane=$pane session=$session '
    r'process_id=[0-9]+ stage=([A-Za-z]+)$',
  );
  final List<String> stages = result.stdoutText
      .split('\n')
      .map(lifecycleLine.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
  _expect(
    _containsOrderedValues(stages, const <String>[
      'disposeStarted',
      'gracefulCloseRequested',
      'terminationWaitTimedOut',
      'forceCloseRequested',
      'finalDeadlineExceeded',
      'outputCancellationStarted',
      'outputCancellationCompleted',
      'processDisposeSkipped',
      'terminationCompleted',
      'shutdownResultPublished',
      'disposeCompleted',
    ]),
    'PTY deadline lifecycle is incomplete or out of order: $stages',
  );
  final List<String> nativePtyStages = _nativePtyStages(
    result.stdoutText,
    pane: pane,
    session: session,
  );
  _expect(
    _containsOrderedValues(nativePtyStages, const <String>[
      'stateSnapshot',
      'termiosSnapshot',
      'signalDelivery',
      'processExitReady',
      'waitpidResult',
      'exitPublished',
    ]),
    'suppressed Dart exit still lacks native signal/reap/publication evidence: '
    '$nativePtyStages',
  );
  _expect(
    !stages.contains('nativeExitObserved'),
    'fault injection unexpectedly delivered the suppressed Dart exit',
  );
  _expect(
    RegExp(
          '^TERMINAL_PANE_LIFECYCLE pane=$pane session=$session state=closed\$',
          multiLine: true,
        ).allMatches(result.stdoutText).length ==
        1,
    'PTY deadline pane did not reach closed exactly once',
  );
  final RegExp rootLifecycle = RegExp(
    r'^RUNTIME_LIFECYCLE event=([a-z-]+) scenario=normal '
    r'generation=([0-9]+)$',
  );
  final List<String> lifecycle = result.stdoutText
      .split('\n')
      .map(rootLifecycle.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => '${match.group(1)}:${match.group(2)}')
      .toList();
  _expect(
    _sameStrings(
      lifecycle,
      _expected(const <String>[
        'root-start',
        'worker-start',
        'worker-ready',
        'root-ready',
        'worker-request',
        'worker-response',
        'worker-stop-request',
        'worker-stop-ack',
        'worker-exit',
        'root-exit',
      ]),
    ),
    'PTY deadline root lifecycle is incomplete: $lifecycle',
  );
  _expectWorkerProcessContract(result, scenario: 'normal', expectedCount: 1);
  _expect(
    result.elapsed < const Duration(seconds: 8),
    'PTY deadline recovery exceeded 8 seconds: ${result.elapsed}',
  );
  stdout.writeln(
    'RUNTIME_PTY_DEADLINE_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'status=${result.status} elapsed_ms=${result.elapsed.inMilliseconds}',
  );
}

List<String> _nativePtyStages(
  String output, {
  required String pane,
  required String session,
}) {
  final RegExp line = RegExp(
    '^TERMINAL_PTY_NATIVE pane=$pane session=$session '
    r'process_id=[0-9]+ stage=([A-Za-z]+) ',
  );
  return output
      .split('\n')
      .map(line.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; ++index) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

Future<void> main(List<String> arguments) async {
  late final _Options options;
  try {
    options = _parseOptions(arguments);
  } on _SmokeException catch (error) {
    stderr.writeln('RUNTIME_INTEGRATION_USAGE_ERROR ${error.message}');
    exitCode = 64;
    return;
  }

  try {
    final _Invocation invocation = await _loadInvocation(options);
    if (options.suite == _Suite.smoke || options.suite == _Suite.all) {
      await _runSmoke(options, invocation);
    }
    if (options.suite == _Suite.display || options.suite == _Suite.all) {
      await _runTerminalDisplay(options, invocation);
    }
    if (options.suite == _Suite.hierarchy || options.suite == _Suite.all) {
      await _runNativeHierarchy(options, invocation);
    }
    if (options.suite == _Suite.restoration || options.suite == _Suite.all) {
      await _runRestoration(options, invocation);
    }
    if (options.suite == _Suite.clipboard || options.suite == _Suite.all) {
      await _runClipboardProduct(options, invocation);
    }
    if (options.suite == _Suite.lifecycle || options.suite == _Suite.all) {
      await _runLifecycle(options, invocation);
    }
    if (options.suite == _Suite.traffic || options.suite == _Suite.all) {
      await _runTraffic(options, invocation);
    }
    if (options.suite == _Suite.resource || options.suite == _Suite.all) {
      await _runResource(options, invocation);
    }
    if (options.suite == _Suite.fault || options.suite == _Suite.all) {
      await _runShutdownFaults(options, invocation);
      await _runPtyExitDeadlineFault(options, invocation);
    }
  } on Object catch (error) {
    stderr.writeln('RUNTIME_INTEGRATION_FAIL mode=${options.mode.name} $error');
    exitCode = 1;
  }
}
