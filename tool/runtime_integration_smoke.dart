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

enum _Suite { smoke, lifecycle, all }

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
  });

  final String executable;
  final List<String> applicationArgumentPrefix;

  List<String> arguments(List<String> applicationArguments) => <String>[
    ...applicationArgumentPrefix,
    ...applicationArguments,
  ];
}

final class _ProcessObservation {
  const _ProcessObservation({
    required this.status,
    required this.stdoutText,
    required this.stderrText,
    required this.elapsed,
  });

  final int status;
  final String stdoutText;
  final String stderrText;
  final Duration elapsed;
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
  });

  final String name;
  final String? machineScenario;
  final List<String> applicationArguments;
  final Map<String, String> environment;
  final int expectedStatus;
  final List<String> expectedObservations;
  final String? expectedStderrMarker;
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
        throw const _SmokeException('--suite must be smoke, lifecycle, or all');
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
  final String declaredMode = await _plistValue(plistPath, 'DTRuntimeMode');
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

  if (options.mode == _RuntimeMode.releaseAot) {
    return _Invocation(
      executable: executablePath,
      applicationArgumentPrefix: const <String>[],
    );
  }
  final String sdkVersion = await _plistValue(plistPath, 'DTDartSDKVersion');
  final String sdkRevision = await _plistValue(plistPath, 'DTDartSDKRevision');
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
  );
}

Future<_ProcessObservation> _launch(
  _Options options,
  _Invocation invocation,
  List<String> applicationArguments, {
  Map<String, String> environment = const <String, String>{},
}) async {
  final String processExecutable = options.launchArchitecture == null
      ? invocation.executable
      : '/usr/bin/arch';
  final List<String> invocationArguments = invocation.arguments(
    applicationArguments,
  );
  final List<String> processArguments = options.launchArchitecture == null
      ? invocationArguments
      : <String>[
          '-${options.launchArchitecture}',
          invocation.executable,
          ...invocationArguments,
        ];
  final Stopwatch stopwatch = Stopwatch()..start();
  final Process process = await Process.start(
    processExecutable,
    processArguments,
    workingDirectory: Directory.current.path,
    environment: environment.isEmpty ? null : environment,
  );
  final Future<String> stdoutText = process.stdout
      .transform(utf8.decoder)
      .join();
  final Future<String> stderrText = process.stderr
      .transform(utf8.decoder)
      .join();
  late final int status;
  try {
    status = await process.exitCode.timeout(const Duration(seconds: 12));
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    throw _SmokeException(
      '${options.mode.name} application did not exit within 12 seconds; '
      'stdout=${(await stdoutText).trim()} '
      'stderr=${(await stderrText).trim()}',
    );
  } finally {
    stopwatch.stop();
  }
  return _ProcessObservation(
    status: status,
    stdoutText: await stdoutText,
    stderrText: await stderrText,
    elapsed: stopwatch.elapsed,
  );
}

Future<void> _runSmoke(_Options options, _Invocation invocation) async {
  final _ProcessObservation observation = await _launch(
    options,
    invocation,
    const <String>['--auto-close-after=1'],
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
    'Automated close scheduled after 1 seconds.',
    'Dart Terminal shut down cleanly.',
  ]) {
    _expect(
      observation.stdoutText.contains(expected),
      'missing smoke observation: $expected',
    );
  }
  stdout.writeln(
    'RUNTIME_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'elapsed_ms=${observation.elapsed.inMilliseconds}',
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
    ]),
    expectedStderrMarker:
        'RUNTIME_LIFECYCLE_FATAL class=root-uncaught status=70',
  ),
  const _LifecycleCase(
    name: 'host-startup-failure',
    applicationArguments: <String>[],
    environment: <String, String>{'DT_RUNTIME_TEST_HOST_STARTUP_FAILURE': '1'},
    expectedStatus: 70,
    expectedObservations: <String>[],
    expectedStderrMarker:
        'RUNTIME_LIFECYCLE_FATAL class=host-startup status=70',
  ),
  const _LifecycleCase(
    name: 'usage-error',
    applicationArguments: <String>['--unsupported-lifecycle-option'],
    expectedStatus: 64,
    expectedObservations: <String>[],
    expectedStderrMarker:
        'Argument error: unknown application option: '
        '--unsupported-lifecycle-option',
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
    stdout.writeln(
      'RUNTIME_LIFECYCLE_INTEGRATION_PASS mode=${options.mode.name} '
      'scenario=${testCase.name} status=${result.status} '
      'elapsed_ms=${result.elapsed.inMilliseconds}',
    );
  }
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
    if (options.suite != _Suite.lifecycle) {
      await _runSmoke(options, invocation);
    }
    if (options.suite != _Suite.smoke) {
      await _runLifecycle(options, invocation);
    }
  } on Object catch (error) {
    stderr.writeln('RUNTIME_INTEGRATION_FAIL mode=${options.mode.name} $error');
    exitCode = 1;
  }
}
