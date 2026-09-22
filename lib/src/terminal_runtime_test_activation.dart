import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Activates only the already-running GUI candidate under native-content test.
///
/// This uses a process ID and exact executable path, never a bundle ID or app
/// name that Launch Services could resolve to an installed copy.
List<String> runtimeTestActivationArguments({
  required int processId,
  required String executablePath,
}) {
  if (processId <= 0) {
    throw ArgumentError.value(processId, 'processId', 'a live process ID');
  }
  if (!executablePath.startsWith('/')) {
    throw ArgumentError.value(
      executablePath,
      'executablePath',
      'an absolute executable path',
    );
  }
  return <String>[
    '-l',
    'JavaScript',
    '-e',
    r'''
function run(argv) {
  ObjC.import('AppKit');
  const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(
      Number(argv[0]));
  if (app.isNil() || app.executableURL.isNil() ||
      ObjC.unwrap(app.executableURL.path) !== argv[1]) {
    throw new Error('candidate process mismatch');
  }
  if (!app.isActive) {
    app.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
  }
  for (let attempt = 0; attempt < 100; attempt++) {
    if (app.isActive) return 'active';
    delay(0.05);
  }
  throw new Error('candidate did not become active');
}
''',
    '--',
    '$processId',
    executablePath,
  ];
}

Future<bool> activateCurrentRuntimeCandidateForTesting() async {
  final Process process = await Process.start(
    '/usr/bin/osascript',
    runtimeTestActivationArguments(
      processId: pid,
      executablePath: Platform.resolvedExecutable,
    ),
  );
  final Future<String> output = process.stdout.transform(utf8.decoder).join();
  final Future<void> errorDrain = process.stderr.drain<void>();
  int status;
  try {
    status = await process.exitCode.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await output;
    await errorDrain;
    return false;
  }
  final String result = await output;
  await errorDrain;
  return status == 0 && result.trim() == 'active';
}
