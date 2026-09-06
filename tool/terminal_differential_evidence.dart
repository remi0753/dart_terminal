import 'dart:convert';
import 'dart:io';

import 'terminal_compatibility_inventory.dart';
import 'terminal_differential_adapters.dart';
import 'terminal_differential_capture.dart';
import 'terminal_differential_corpus.dart';
import 'terminal_differential_harness.dart';
import 'terminal_differential_sha256.dart';

const String defaultTerminalDifferentialEvidencePath =
    'compatibility/differential_capture_evidence.json';

final class TerminalDifferentialEvidenceException implements Exception {
  const TerminalDifferentialEvidenceException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDifferentialEvidenceException: $message';
}

final class TerminalDifferentialEvidenceResult {
  const TerminalDifferentialEvidenceResult({
    required this.attempts,
    required this.captured,
    required this.unavailable,
  });

  final int attempts;
  final int captured;
  final int unavailable;

  String machineLine() =>
      'TERMINAL_DIFFERENTIAL_EVIDENCE_PASS attempts=$attempts '
      'captured=$captured unavailable=$unavailable observed_replies=$captured';
}

TerminalDifferentialEvidenceResult runTerminalDifferentialEvidenceChecks({
  bool check = true,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final File backendsFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialBackendsPath),
  );
  final TerminalDifferentialBackendCatalog catalog =
      TerminalDifferentialBackendCatalog.load(
        backendsFile,
        repositoryRoot: root,
      );
  final File selfTestsFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialSelfTestsPath),
  );
  final TerminalDifferentialSelfTestLedger selfTests =
      TerminalDifferentialSelfTestLedger.load(
        selfTestsFile,
        repositoryRoot: root,
        catalog: catalog,
      );
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File.fromUri(
          root.uri.resolve(defaultTerminalCompatibilityInventoryPath),
        ),
        repositoryRoot: root,
      );
  final File manifestFile = File.fromUri(
    root.uri.resolve(defaultReviewedDifferentialManifestPath),
  );
  final TerminalDifferentialManifest manifest =
      TerminalDifferentialManifest.load(
        manifestFile,
        inventoryIds: <String>{
          for (final TerminalCompatibilityRecord record in inventory.records)
            record.id,
        },
      );
  _expect(manifest.scope == 'reviewed-corpus', 'manifest scope differs');

  final List<Map<String, Object?>> records = <Map<String, Object?>>[];
  final Set<String> expectedProbePaths = <String>{};
  int captured = 0;
  int unavailable = 0;
  for (final TerminalDifferentialBackendProfile profile in catalog.profiles) {
    final TerminalDifferentialSelfTestCapture selfTest = selfTests.capture(
      profile.id,
    );
    for (final TerminalDifferentialCase testCase in manifest.cases) {
      if (selfTest.automationStatus == 'activation-unavailable') {
        unavailable++;
        records.add(<String, Object?>{
          'profile_id': profile.id,
          'case_id': testCase.id,
          'status': 'unavailable',
          'reason': 'macos-activation-unavailable',
          'captured_on': selfTest.capturedOn,
          'host_os': selfTest.hostOs,
          'host_version': selfTest.hostVersion,
          'architecture': selfTest.architecture,
          'executable_sha256': selfTest.executableSha256,
          'config_sha256': selfTest.configSha256,
          'capture_method': profile.captureMethod,
          'observed_fields': <String>[],
          'probe_path': null,
          'probe_sha256': null,
          'reply_bytes': 0,
          'replies_sha256': null,
        });
        continue;
      }
      final String probePath =
          '$defaultExternalDifferentialCaptureDirectory/${profile.id}/'
          '${testCase.id}.probe.json';
      expectedProbePaths.add(probePath);
      final File probeFile = File.fromUri(root.uri.resolve(probePath));
      _expect(probeFile.existsSync(), '$probePath is missing');
      _expect(
        FileSystemEntity.typeSync(probeFile.path, followLinks: false) ==
            FileSystemEntityType.file,
        '$probePath must be a regular file',
      );
      final TerminalDifferentialProbeResult probe =
          TerminalDifferentialProbeResult.load(probeFile);
      _expect(probe.status == 'ok', '$probePath did not capture');
      _expect(
        probe.terminalRows >= testCase.rows &&
            probe.terminalColumns >= testCase.columns,
        '$probePath dimensions differ',
      );
      _expect(
        testCase.fields.contains(TerminalDifferentialField.replies),
        '${testCase.id} does not declare the observed replies field',
      );
      captured++;
      records.add(<String, Object?>{
        'profile_id': profile.id,
        'case_id': testCase.id,
        'status': 'captured',
        'reason': null,
        'captured_on': selfTest.capturedOn,
        'host_os': selfTest.hostOs,
        'host_version': selfTest.hostVersion,
        'architecture': selfTest.architecture,
        'executable_sha256': selfTest.executableSha256,
        'config_sha256': selfTest.configSha256,
        'capture_method': profile.captureMethod,
        'observed_fields': <String>['replies'],
        'probe_path': probePath,
        'probe_sha256': terminalDifferentialSha256(probeFile.readAsBytesSync()),
        'reply_bytes': probe.replies.length,
        'replies_sha256': terminalDifferentialSha256(probe.replies),
      });
    }
  }
  _expect(
    records.length == catalog.profiles.length * manifest.cases.length,
    'evidence matrix is incomplete',
  );
  final Directory captureDirectory = Directory.fromUri(
    root.uri.resolve('$defaultExternalDifferentialCaptureDirectory/'),
  );
  _expect(captureDirectory.existsSync(), 'capture directory is missing');
  final Set<String> actualProbePaths = <String>{
    for (final FileSystemEntity entity in captureDirectory.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is File && entity.path.endsWith('.probe.json'))
        entity.absolute.path.substring(root.absolute.path.length + 1),
  };
  _expect(
    expectedProbePaths.length == actualProbePaths.length &&
        expectedProbePaths.containsAll(actualProbePaths),
    'external probe file set differs',
  );
  final String evidence =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': 'dart-terminal-differential-capture-evidence',
        'version': 1,
        'manifest_path': defaultReviewedDifferentialManifestPath,
        'manifest_sha256': terminalDifferentialSha256(manifestFile.readAsBytesSync()),
        'backends_path': defaultTerminalDifferentialBackendsPath,
        'backends_sha256': terminalDifferentialSha256(backendsFile.readAsBytesSync()),
        'self_tests_path': defaultTerminalDifferentialSelfTestsPath,
        'self_tests_sha256': terminalDifferentialSha256(selfTestsFile.readAsBytesSync()),
        'records': records,
        'summary': <String, Object?>{'products': catalog.profiles.length, 'cases': manifest.cases.length, 'attempts': records.length, 'captured': captured, 'unavailable': unavailable, 'observed_reply_captures': captured, 'screen_style_mode_captures': 0},
      })}\n';
  final File evidenceFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialEvidencePath),
  );
  if (check) {
    _expect(evidenceFile.existsSync(), 'capture evidence index is missing');
    _expect(
      evidenceFile.readAsStringSync() == evidence,
      'capture evidence index is stale',
    );
  } else {
    evidenceFile.parent.createSync(recursive: true);
    evidenceFile.writeAsStringSync(evidence, flush: true);
  }
  return TerminalDifferentialEvidenceResult(
    attempts: records.length,
    captured: captured,
    unavailable: unavailable,
  );
}

void main(List<String> arguments) {
  try {
    final bool check = switch (arguments) {
      <String>[] => false,
      <String>['--check'] => true,
      _ => throw const TerminalDifferentialEvidenceException(
        'usage: terminal_differential_evidence.dart [--check]',
      ),
    };
    stdout.writeln(
      runTerminalDifferentialEvidenceChecks(check: check).machineLine(),
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_EVIDENCE_FAIL $error');
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDifferentialEvidenceException(message);
}
