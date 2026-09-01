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

final class _Options {
  const _Options({
    required this.mode,
    required this.bundlePath,
    required this.launchArchitecture,
  });

  final _RuntimeMode mode;
  final String bundlePath;
  final String? launchArchitecture;
}

_Options _parseOptions(List<String> arguments) {
  _RuntimeMode? mode;
  String? bundlePath;
  String? launchArchitecture;
  for (final String argument in arguments) {
    if (argument.startsWith('--mode=')) {
      final String value = argument.substring('--mode='.length);
      mode = _RuntimeMode.values
          .where((_RuntimeMode candidate) => candidate.name == value)
          .firstOrNull;
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

Future<void> _runSmoke(_Options options) async {
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

  final List<String> launchArguments;
  if (options.mode == _RuntimeMode.developerJit) {
    final String sdkVersion = await _plistValue(plistPath, 'DTDartSDKVersion');
    final String sdkRevision = await _plistValue(
      plistPath,
      'DTDartSDKRevision',
    );
    launchArguments = <String>[
      '--kernel',
      payloadPath,
      '--sdk-version',
      sdkVersion,
      '--sdk-revision',
      sdkRevision,
      '--',
      '--auto-close-after=1',
    ];
  } else {
    launchArguments = <String>['--auto-close-after=1'];
  }

  final Stopwatch stopwatch = Stopwatch()..start();
  final String processExecutable = options.launchArchitecture == null
      ? executablePath
      : '/usr/bin/arch';
  final List<String> processArguments = options.launchArchitecture == null
      ? launchArguments
      : <String>[
          '-${options.launchArchitecture}',
          executablePath,
          ...launchArguments,
        ];
  final Process process = await Process.start(
    processExecutable,
    processArguments,
    workingDirectory: Directory.current.path,
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
    }
    throw _SmokeException(
      '${options.mode.name} application did not exit within 12 seconds',
    );
  } finally {
    stopwatch.stop();
  }

  final String output = await stdoutText;
  final String errors = await stderrText;
  _expect(status == 0, 'application exited with status $status');
  _expect(
    errors.trim().isEmpty,
    'application wrote unexpected stderr: ${errors.trim()}',
  );
  for (final String expected in <String>[
    'Dart Terminal is attached to the AppKit main thread.',
    'Automated close scheduled after 1 seconds.',
    'Dart Terminal shut down cleanly.',
  ]) {
    _expect(output.contains(expected), 'missing smoke observation: $expected');
  }

  stdout.writeln(
    'RUNTIME_INTEGRATION_PASS mode=${options.mode.name} '
    'launch_architecture=${options.launchArchitecture ?? 'native'} '
    'elapsed_ms=${stopwatch.elapsedMilliseconds}',
  );
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
    await _runSmoke(options);
  } on Object catch (error) {
    stderr.writeln('RUNTIME_INTEGRATION_FAIL mode=${options.mode.name} $error');
    exitCode = 1;
  }
}
