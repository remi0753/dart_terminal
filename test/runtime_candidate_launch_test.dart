import '../tool/runtime_candidate_launch.dart';

void main() => runRuntimeCandidateLaunchTests();

void runRuntimeCandidateLaunchTests() {
  const String bundle = '/tmp/build/DartTerminal.app';
  const String buildCandidate =
      '/repo/build/runtime/arm64/developer-jit/DartTerminal.app';
  _expect(
    requireRuntimeBuildCandidatePath(
          canonicalBundlePath: buildCandidate,
          canonicalBuildRoot: '/repo/build/runtime',
        ) ==
        buildCandidate,
    'a canonical build candidate is accepted',
  );
  _expectThrows(
    () => requireRuntimeBuildCandidatePath(
      canonicalBundlePath: '/Users/remi/Applications/DartTerminal.app',
      canonicalBuildRoot: '/repo/build/runtime',
    ),
    'an installed app is rejected before launch',
  );
  _expectThrows(
    () => requireRuntimeBuildCandidatePath(
      canonicalBundlePath: '/repo/build/runtime-other/DartTerminal.app',
      canonicalBuildRoot: '/repo/build/runtime',
    ),
    'a sibling path cannot bypass the build root boundary',
  );
  final List<String> arguments = runtimeCandidateOpenArguments(
    bundlePath: bundle,
    stdoutPath: '/tmp/stdout',
    stderrPath: '/tmp/stderr',
    environment: const <String, String>{'TEST_MODE': '1'},
    applicationArguments: const <String>['--runtime-native-content-test'],
    architecture: 'arm64',
  );
  _expect(
    arguments.contains(bundle) &&
        arguments.indexOf(bundle) == arguments.indexOf('--args') - 1 &&
        arguments.contains('-n') &&
        arguments.contains('-F') &&
        !arguments.contains('-a') &&
        !arguments.contains('-b'),
    'Launch Services receives only the exact build candidate path',
  );
  _expect(
    arguments.contains('TEST_MODE=1') &&
        arguments.contains('arm64') &&
        arguments.last == '--runtime-native-content-test',
    'candidate launch retains environment, architecture, and test arguments',
  );
  _expectThrows(
    () => runtimeCandidateOpenArguments(
      bundlePath: 'DartTerminal.app',
      stdoutPath: '/tmp/stdout',
      stderrPath: '/tmp/stderr',
      environment: const <String, String>{},
      applicationArguments: const <String>[],
    ),
    'relative app names cannot resolve to an installed copy',
  );
  _expectThrows(
    () => runtimeCandidateOpenArguments(
      bundlePath: 'dev.dart-terminal',
      stdoutPath: '/tmp/stdout',
      stderrPath: '/tmp/stderr',
      environment: const <String, String>{},
      applicationArguments: const <String>[],
    ),
    'bundle identifiers cannot replace a candidate path',
  );
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError(description);
}
