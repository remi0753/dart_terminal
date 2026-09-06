import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../tool/terminal_application_matrix.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single.startsWith('--fake-driver=')) {
    await _runFakeDriver(arguments.single.substring('--fake-driver='.length));
    return;
  }
  await runTerminalApplicationMatrixTests();
}

Future<void> runTerminalApplicationMatrixTests() async {
  _testReviewedManifest();
  _testManifestValidation();
  _testObservationValidation();
  await _testSubprocessDriverClassifications();
}

TerminalApplicationMatrixManifest _manifest() =>
    TerminalApplicationMatrixManifest.load(
      File(defaultTerminalApplicationMatrixPath),
    );

void _testReviewedManifest() {
  final TerminalApplicationMatrixManifest manifest = _manifest();
  final List<TerminalApplicationScenario> scenarios = manifest.scenarios
      .toList();
  _expect(
    manifest.version == 1 &&
        manifest.scope == 'phase6-reviewed' &&
        manifest.observationVersion == 1 &&
        manifest.applications.length == 8 &&
        manifest.applications.map((value) => value.id).join(',') ==
            'emacs,fzf,lazygit,mosh,ncurses,neovim,ssh,tmux' &&
        scenarios.length == 8 &&
        scenarios.every(
          (TerminalApplicationScenario scenario) =>
              scenario.requiredFields.length == 6 &&
              scenario.checks.length == 6,
        ),
    'reviewed manifest has eight exact bounded application scenarios',
  );
  final TerminalApplicationMatrixContractResult result =
      runTerminalApplicationMatrixContractChecks();
  _expect(
    result.applications == 8 &&
        result.scenarios == 8 &&
        result.requiredFields == 48 &&
        result.checks == 48 &&
        result.machineLine() ==
            'TERMINAL_APPLICATION_MATRIX_CONTRACT_PASS applications=8 '
                'scenarios=8 required_fields=48 checks=48',
    'normal-gate contract result has exact content-free totals',
  );
  final Map<String, Object?> request = Map<String, Object?>.from(
    scenarios.first.toDriverRequest(),
  );
  _expect(
    request.keys.join(',') == 'format,version,application_id,scenario' &&
        !jsonEncode(request).contains(scenarios.first.description),
    'driver request exposes bounded execution contract without prose content',
  );
}

void _testManifestValidation() {
  final String fixture = File(defaultTerminalApplicationMatrixPath)
      .readAsStringSync();
  _expectManifestFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    'unsupported manifest version',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '"applications": [',
      '"unknown": true, "applications": [',
    ),
    'root keys differ',
  );
  _expectManifestFailure(
    fixture
        .replaceFirst('"id": "tmux"', '"id": "zzapp"')
        .replaceFirst(
          '"id": "tmux-session-resize"',
          '"id": "zzapp-session-resize"',
        ),
    'exactly the eight required applications',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"rows": 24', '"rows": 0'),
    'rows are outside bounds',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"deadline_ms": 20000', '"deadline_ms": 30001'),
    'deadline_ms is outside',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '"maximum_output_bytes": 262144',
      '"maximum_output_bytes": 1048577',
    ),
    'maximum_output_bytes is outside bounds',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '["stream", "screen", "cursor", "modes", "resize", "exit"]',
      '["screen", "stream", "cursor", "modes", "resize", "exit"]',
    ),
    'canonical order',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '["clean-exit", "cursor-bounded", "marker-visible", "parser-clean", "primary-restored", "resize-observed"]',
      '["cursor-bounded", "clean-exit", "marker-visible", "parser-clean", "primary-restored", "resize-observed"]',
    ),
    'checks must be sorted',
  );
}

void _testObservationValidation() {
  final TerminalApplicationScenario scenario = _manifest().scenarios.first;
  final TerminalApplicationObservation observation = _observation(
    scenario,
    passed: true,
  );
  final TerminalApplicationObservation decoded =
      TerminalApplicationObservation.parse(
        observation.encode(),
        scenario: scenario,
      );
  _expect(
    decoded.passed &&
        decoded.applicationId == 'emacs' &&
        decoded.scenarioId == 'emacs-terminal-ui' &&
        decoded.capturedFields.length == 6 &&
        decoded.checks.length == 6,
    'content-free application observation round trips exactly',
  );
  final TerminalApplicationObservation semanticFailure = _observation(
    scenario,
    passed: false,
  );
  _expect(
    !TerminalApplicationObservation.parse(
      semanticFailure.encode(),
      scenario: scenario,
    ).passed,
    'semantic check failure remains a valid non-passing observation',
  );
  final String encoded = observation.encode();
  _expectObservationFailure(
    encoded.replaceFirst('"version":1', '"version":2'),
    scenario,
    'unsupported observation version',
  );
  _expectObservationFailure(
    encoded.replaceFirst('"application_id":"emacs"', '"application_id":"fzf"'),
    scenario,
    'application_id differs',
  );
  _expectObservationFailure(
    encoded.replaceFirst('"stream","screen"', '"screen","stream"'),
    scenario,
    'captured_fields differ',
  );
  _expectObservationFailure(
    encoded.replaceFirst('"id":"clean-exit"', '"id":"wrong-check"'),
    scenario,
    'check id/order differs',
  );
  _expectObservationFailure(
    encoded.replaceFirst(List<String>.filled(64, '0').join(), 'not-a-hash'),
    scenario,
    'not SHA-256',
  );
}

Future<void> _testSubprocessDriverClassifications() async {
  final TerminalApplicationScenario scenario = _manifest().scenarios.first;
  final String helper = File('test/terminal_application_matrix_test.dart')
      .absolute
      .path;
  Future<TerminalApplicationDriverResult> invoke(
    String mode, {
    TerminalApplicationSubprocessDriver driver =
        const TerminalApplicationSubprocessDriver(),
  }) => driver.run(
    executable: Platform.resolvedExecutable,
    arguments: <String>[helper, '--fake-driver=$mode'],
    scenario: scenario,
  );

  final TerminalApplicationDriverResult ok = await invoke('ok');
  _expect(
    ok.status == TerminalApplicationDriverStatus.ok &&
        ok.exitCode == 0 &&
        ok.observation?.passed == true &&
        ok.stdoutBytes > 0,
    'partial-write valid driver response is accepted exactly once',
  );
  final TerminalApplicationDriverResult semanticFailure = await invoke(
    'semantic-failure',
  );
  _expect(
    semanticFailure.status == TerminalApplicationDriverStatus.ok &&
        semanticFailure.observation?.passed == false,
    'semantic failure cannot be confused with harness failure or pass',
  );
  final TerminalApplicationDriverResult malformed = await invoke('malformed');
  _expect(
    malformed.status == TerminalApplicationDriverStatus.protocolError,
    'malformed output is a protocol error',
  );
  final TerminalApplicationDriverResult duplicate = await invoke('duplicate');
  _expect(
    duplicate.status == TerminalApplicationDriverStatus.protocolError,
    'duplicate observations cannot be accepted as one result',
  );
  final TerminalApplicationDriverResult crashed = await invoke('crash');
  _expect(
    crashed.status == TerminalApplicationDriverStatus.crashed &&
        crashed.exitCode == 7 &&
        crashed.stderrBytes > 0,
    'nonzero driver exit is a content-free crash classification',
  );
  final TerminalApplicationDriverResult signaled = await invoke('signal');
  _expect(
    signaled.status == TerminalApplicationDriverStatus.crashed &&
        signaled.exitCode != 0,
    'signal termination is classified as a crash',
  );
  final TerminalApplicationDriverResult timeout = await invoke(
    'timeout',
    driver: const TerminalApplicationSubprocessDriver(
      timeout: Duration(milliseconds: 50),
    ),
  );
  _expect(
    timeout.status == TerminalApplicationDriverStatus.timedOut,
    'driver deadline is bounded and classified',
  );
  final TerminalApplicationDriverResult overflow = await invoke(
    'overflow',
    driver: const TerminalApplicationSubprocessDriver(maximumOutputBytes: 128),
  );
  _expect(
    overflow.status == TerminalApplicationDriverStatus.outputLimit &&
        overflow.stdoutBytes == 128,
    'oversized stdout is killed and capped',
  );
  final TerminalApplicationDriverResult stderrOverflow = await invoke(
    'stderr-overflow',
    driver: const TerminalApplicationSubprocessDriver(maximumStderrBytes: 64),
  );
  _expect(
    stderrOverflow.status == TerminalApplicationDriverStatus.outputLimit &&
        stderrOverflow.stderrBytes == 64,
    'oversized stderr is killed and capped',
  );
  final TerminalApplicationDriverResult unavailable =
      await const TerminalApplicationSubprocessDriver().run(
        executable: '/private/tmp/dart-terminal-no-such-application-driver',
        arguments: const <String>[],
        scenario: scenario,
      );
  _expect(
    unavailable.status == TerminalApplicationDriverStatus.unavailable &&
        unavailable.exitCode == null,
    'missing driver is unavailable and cannot become a pass',
  );
  final Directory directory = Directory.systemTemp.createTempSync(
    'dart-terminal-non-executable-application-driver-',
  );
  try {
    final File nonExecutable = File.fromUri(directory.uri.resolve('driver'))
      ..writeAsStringSync('not executable\n');
    final TerminalApplicationDriverResult startFailure =
        await const TerminalApplicationSubprocessDriver().run(
          executable: nonExecutable.path,
          arguments: const <String>[],
          scenario: scenario,
        );
    _expect(
      startFailure.status == TerminalApplicationDriverStatus.startFailure,
      'existing non-executable path is distinct from unavailable',
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
  _expect(
    !ok.machineLine(scenario).contains('marker-visible') &&
        !crashed.machineLine(scenario).contains('fake crash') &&
        crashed.machineLine(scenario).contains('stderr_bytes='),
    'machine diagnostics expose scalar metadata but no check or stderr content',
  );
}

TerminalApplicationObservation _observation(
  TerminalApplicationScenario scenario, {
  required bool passed,
}) => TerminalApplicationObservation(
  applicationId: scenario.applicationId,
  scenarioId: scenario.id,
  driverId: 'fixture-driver',
  provenance: TerminalApplicationProvenance(
    product: 'fixture-application',
    productVersion: '1.0',
    executableSha256: List<String>.filled(64, '0').join(),
    configId: 'fixture-config',
    configSha256: List<String>.filled(64, '1').join(),
    captureMethod: 'fixture-pty-v1',
    operatingSystem: 'macos',
    architecture: 'arm64',
  ),
  capturedFields: scenario.requiredFields,
  outputBytes: 128,
  outputSha256: List<String>.filled(64, '2').join(),
  rawEvidenceSha256: List<String>.filled(64, '3').join(),
  checks: <TerminalApplicationCheckResult>[
    for (int index = 0; index < scenario.checks.length; index++)
      TerminalApplicationCheckResult(
        id: scenario.checks[index],
        passed: passed || index != 0,
      ),
  ],
);

Future<void> _runFakeDriver(String mode) async {
  switch (mode) {
    case 'malformed':
      stdout.write('{not-json}\n');
      return;
    case 'duplicate':
      final String response = await _fakeObservationFromRequest(passed: true);
      stdout.write(response);
      stdout.write(response);
      return;
    case 'crash':
      stderr.write('fake crash content must stay private');
      exitCode = 7;
      return;
    case 'signal':
      Process.killPid(pid, ProcessSignal.sigkill);
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    case 'timeout':
      await Future<void>.delayed(const Duration(seconds: 2));
      return;
    case 'overflow':
      stdout.write(List<String>.filled(4096, 'x').join());
      return;
    case 'stderr-overflow':
      stderr.write(List<String>.filled(4096, 'x').join());
      return;
    case 'semantic-failure':
      stdout.write(await _fakeObservationFromRequest(passed: false));
      return;
    case 'ok':
      final String response = await _fakeObservationFromRequest(passed: true);
      final int split = response.length ~/ 2;
      stdout.write(response.substring(0, split));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      stdout.write(response.substring(split));
      return;
    default:
      exitCode = 64;
  }
}

Future<String> _fakeObservationFromRequest({required bool passed}) async {
  final Map<String, Object?> request = Map<String, Object?>.from(
    jsonDecode(await utf8.decoder.bind(stdin).join()) as Map<Object?, Object?>,
  );
  final Map<String, Object?> scenario = Map<String, Object?>.from(
    request['scenario']! as Map<Object?, Object?>,
  );
  final List<Object?> fields = scenario['required_fields']! as List<Object?>;
  final List<Object?> checks = scenario['checks']! as List<Object?>;
  return '${jsonEncode(<String, Object?>{
    'format': TerminalApplicationObservation.formatName,
    'version': TerminalApplicationObservation.formatVersion,
    'application_id': request['application_id'],
    'scenario_id': scenario['id'],
    'driver_id': 'fixture-driver',
    'provenance': <String, Object?>{'product': 'fixture-application', 'product_version': '1.0', 'executable_sha256': List<String>.filled(64, '0').join(), 'config_id': 'fixture-config', 'config_sha256': List<String>.filled(64, '1').join(), 'capture_method': 'fixture-pty-v1', 'os': 'macos', 'architecture': 'arm64'},
    'captured_fields': fields,
    'output_bytes': 128,
    'output_sha256': List<String>.filled(64, '2').join(),
    'raw_evidence_sha256': List<String>.filled(64, '3').join(),
    'checks': <Object?>[
      for (int index = 0; index < checks.length; index++) <String, Object?>{'id': checks[index], 'passed': passed || index != 0},
    ],
  })}\n';
}

void _expectManifestFailure(String source, String messagePart) {
  try {
    TerminalApplicationMatrixManifest.parse(source);
  } on TerminalApplicationMatrixException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'manifest failed for expected reason $messagePart: $error',
    );
    return;
  }
  throw StateError('test failed: manifest accepted invalid $messagePart');
}

void _expectObservationFailure(
  String source,
  TerminalApplicationScenario scenario,
  String messagePart,
) {
  try {
    TerminalApplicationObservation.parse(source, scenario: scenario);
  } on TerminalApplicationMatrixException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'observation failed for expected reason $messagePart: $error',
    );
    return;
  }
  throw StateError('test failed: observation accepted invalid $messagePart');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
