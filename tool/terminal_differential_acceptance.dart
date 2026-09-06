import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_compatibility_inventory.dart';
import 'terminal_differential_adapters.dart';
import 'terminal_differential_corpus.dart';
import 'terminal_differential_evidence.dart';
import 'terminal_differential_harness.dart';
import 'terminal_differential_sha256.dart';

const String defaultTerminalDifferentialAcceptancePath =
    'compatibility/differential_acceptance_report.json';
const String defaultTerminalDifferentialMinimalGapManifestPath =
    'test/corpus/differential/mismatches/decrqss_sgr_v1.json';

final class TerminalDifferentialAcceptanceException implements Exception {
  const TerminalDifferentialAcceptanceException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDifferentialAcceptanceException: $message';
}

final class TerminalDifferentialAcceptanceResult {
  const TerminalDifferentialAcceptanceResult({
    required this.accepted,
    required this.agreements,
    required this.documentedGaps,
    required this.unavailable,
    required this.minimalGapBytes,
  });

  final int accepted;
  final int agreements;
  final int documentedGaps;
  final int unavailable;
  final int minimalGapBytes;

  String machineLine() =>
      'TERMINAL_DIFFERENTIAL_ACCEPTANCE_PASS accepted=$accepted '
      'agreements=$agreements documented_gaps=$documentedGaps '
      'unavailable=$unavailable minimal_gap_bytes=$minimalGapBytes';
}

TerminalDifferentialAcceptanceResult runTerminalDifferentialAcceptanceChecks({
  bool check = true,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  runReviewedDifferentialCorpusChecks(repositoryRoot: root);
  runTerminalDifferentialEvidenceChecks(repositoryRoot: root);
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File.fromUri(
          root.uri.resolve(defaultTerminalCompatibilityInventoryPath),
        ),
        repositoryRoot: root,
      );
  final Set<String> inventoryIds = <String>{
    for (final TerminalCompatibilityRecord record in inventory.records)
      record.id,
  };
  final File manifestFile = File.fromUri(
    root.uri.resolve(defaultReviewedDifferentialManifestPath),
  );
  final TerminalDifferentialManifest manifest =
      TerminalDifferentialManifest.load(
        manifestFile,
        inventoryIds: inventoryIds,
      );
  final File backendsFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialBackendsPath),
  );
  final TerminalDifferentialBackendCatalog catalog =
      TerminalDifferentialBackendCatalog.load(
        backendsFile,
        repositoryRoot: root,
      );
  final TerminalDifferentialSelfTestLedger selfTests =
      TerminalDifferentialSelfTestLedger.load(
        File.fromUri(
          root.uri.resolve(defaultTerminalDifferentialSelfTestsPath),
        ),
        repositoryRoot: root,
        catalog: catalog,
      );
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  int accepted = 0;
  int agreements = 0;
  int documentedGaps = 0;
  int unavailable = 0;
  int capturedUnobservedFields = 0;
  for (final TerminalDifferentialBackendProfile profile in catalog.profiles) {
    final TerminalDifferentialSelfTestCapture selfTest = selfTests.capture(
      profile.id,
    );
    for (final TerminalDifferentialCase testCase in manifest.cases) {
      final List<String> unobservedFields = <String>[
        for (final TerminalDifferentialField field in testCase.fields)
          if (field != TerminalDifferentialField.replies) field.name,
      ];
      if (selfTest.automationStatus == 'activation-unavailable') {
        unavailable++;
        accepted++;
        results.add(<String, Object?>{
          'profile_id': profile.id,
          'case_id': testCase.id,
          'classification': 'unavailable',
          'accepted': true,
          'reason': 'macos-activation-unavailable',
          'expectation': testCase.expectation.name,
          'observed_fields': <String>[],
          'unobserved_fields': <String>[
            for (final TerminalDifferentialField field in testCase.fields)
              field.name,
          ],
          'difference_fields': <String>[],
          'gap_owner': testCase.gapOwner,
        });
        continue;
      }
      final File baselineFile = File.fromUri(
        root.uri.resolve(
          '$defaultReviewedDifferentialBaselineDirectory/${testCase.id}.json',
        ),
      );
      final TerminalDifferentialObservation baseline =
          TerminalDifferentialObservation.parse(
            baselineFile.readAsStringSync(),
            testCase: testCase,
          );
      final String probePath =
          'test/corpus/differential/external/${profile.id}/'
          '${testCase.id}.probe.json';
      final TerminalDifferentialProbeResult probe =
          TerminalDifferentialProbeResult.load(
            File.fromUri(root.uri.resolve(probePath)),
          );
      final bool matches = _bytesEqual(baseline.replies, probe.replies);
      final String classification;
      if (matches &&
          testCase.expectation == TerminalDifferentialExpectation.agree) {
        classification = 'agreement';
        agreements++;
      } else if (!matches &&
          testCase.expectation ==
              TerminalDifferentialExpectation.documentedGap) {
        classification = 'documented-gap';
        documentedGaps++;
      } else if (matches) {
        classification = 'stale-gap';
      } else {
        classification = 'unexpected-mismatch';
      }
      _expect(
        classification == 'agreement' || classification == 'documented-gap',
        '${profile.id}/${testCase.id} is $classification',
      );
      capturedUnobservedFields += unobservedFields.length;
      accepted++;
      results.add(<String, Object?>{
        'profile_id': profile.id,
        'case_id': testCase.id,
        'classification': classification,
        'accepted': true,
        'reason': null,
        'expectation': testCase.expectation.name,
        'observed_fields': <String>['replies'],
        'unobserved_fields': unobservedFields,
        'difference_fields': <String>[if (!matches) 'replies'],
        'gap_owner': testCase.gapOwner,
        'baseline_sha256': terminalDifferentialSha256(
          baselineFile.readAsBytesSync(),
        ),
        'probe_path': probePath,
        'probe_sha256': terminalDifferentialSha256(
          File.fromUri(root.uri.resolve(probePath)).readAsBytesSync(),
        ),
      });
    }
  }
  _expect(
    accepted == 12 &&
        agreements == 6 &&
        documentedGaps == 2 &&
        unavailable == 4 &&
        capturedUnobservedFields == 16,
    'reviewed acceptance totals differ',
  );

  final File minimalManifestFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialMinimalGapManifestPath),
  );
  final TerminalDifferentialManifest minimalManifest =
      TerminalDifferentialManifest.load(
        minimalManifestFile,
        inventoryIds: inventoryIds,
      );
  _expect(
    minimalManifest.scope == 'reviewed-corpus' &&
        minimalManifest.cases.length == 1,
    'minimal gap manifest identity differs',
  );
  final TerminalDifferentialCase minimalCase = minimalManifest.cases.single;
  _expect(
    _encodeHex(minimalCase.input) == '1b5024716d1b5c' &&
        minimalCase.input.length == 7 &&
        minimalCase.expectation ==
            TerminalDifferentialExpectation.documentedGap &&
        minimalCase.gapOwner == 'docs/phase6/decrqss-sgr-gap.md',
    'minimal DECRQSS gap contract differs',
  );
  final TerminalDifferentialCase sourceCase = manifest.cases.singleWhere(
    (TerminalDifferentialCase testCase) =>
        testCase.id == 'rendition-attributes-colors',
  );
  _expect(
    sourceCase.input.length > minimalCase.input.length &&
        _contains(sourceCase.input, minimalCase.input),
    'minimal gap is not a strict source-case reduction',
  );
  final TerminalDifferentialObservation dartMinimal =
      const DartTerminalDifferentialBackend().capture(minimalCase);
  _expect(dartMinimal.replies.isEmpty, 'Dart minimal gap unexpectedly replied');
  final List<Map<String, Object?>> minimalResults = <Map<String, Object?>>[];
  for (final TerminalDifferentialBackendProfile profile in catalog.profiles) {
    final TerminalDifferentialSelfTestCapture selfTest = selfTests.capture(
      profile.id,
    );
    if (selfTest.automationStatus == 'activation-unavailable') {
      minimalResults.add(<String, Object?>{
        'profile_id': profile.id,
        'classification': 'unavailable',
        'accepted': true,
        'reason': 'macos-activation-unavailable',
        'probe_path': null,
        'probe_sha256': null,
        'reply_bytes': 0,
        'replies_sha256': null,
      });
      continue;
    }
    final String probePath =
        'test/corpus/differential/mismatches/external/${profile.id}/'
        '${minimalCase.id}.probe.json';
    final File probeFile = File.fromUri(root.uri.resolve(probePath));
    _expect(probeFile.existsSync(), '$probePath is missing');
    final TerminalDifferentialProbeResult probe =
        TerminalDifferentialProbeResult.load(probeFile);
    _expect(
      probe.status == 'ok' && _isSuccessfulSgrReport(probe.replies),
      '${profile.id} minimal DECRQSS reply is invalid',
    );
    minimalResults.add(<String, Object?>{
      'profile_id': profile.id,
      'classification': 'documented-gap',
      'accepted': true,
      'reason': null,
      'probe_path': probePath,
      'probe_sha256': terminalDifferentialSha256(probeFile.readAsBytesSync()),
      'reply_bytes': probe.replies.length,
      'replies_sha256': terminalDifferentialSha256(probe.replies),
    });
  }
  final File evidenceFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialEvidencePath),
  );
  final String report =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': 'dart-terminal-differential-acceptance',
        'version': 1,
        'manifest_path': defaultReviewedDifferentialManifestPath,
        'manifest_sha256': terminalDifferentialSha256(manifestFile.readAsBytesSync()),
        'evidence_path': defaultTerminalDifferentialEvidencePath,
        'evidence_sha256': terminalDifferentialSha256(evidenceFile.readAsBytesSync()),
        'results': results,
        'minimal_gap': <String, Object?>{'id': minimalCase.id, 'source_case_id': sourceCase.id, 'manifest_path': defaultTerminalDifferentialMinimalGapManifestPath, 'manifest_sha256': terminalDifferentialSha256(minimalManifestFile.readAsBytesSync()), 'input_hex': _encodeHex(minimalCase.input), 'input_bytes': minimalCase.input.length, 'inventory_ids': minimalCase.inventoryIds, 'gap_owner': minimalCase.gapOwner, 'dart_reply_bytes': dartMinimal.replies.length, 'captures': minimalResults},
        'summary': <String, Object?>{'attempts': results.length, 'accepted': accepted, 'agreements': agreements, 'documented_gaps': documentedGaps, 'unavailable': unavailable, 'unexpected_mismatches': 0, 'stale_gaps': 0, 'captured_unobserved_fields': capturedUnobservedFields, 'silent_results': 0},
      })}\n';
  final File reportFile = File.fromUri(
    root.uri.resolve(defaultTerminalDifferentialAcceptancePath),
  );
  if (check) {
    _expect(reportFile.existsSync(), 'acceptance report is missing');
    _expect(
      reportFile.readAsStringSync() == report,
      'acceptance report is stale',
    );
  } else {
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(report, flush: true);
  }
  return TerminalDifferentialAcceptanceResult(
    accepted: accepted,
    agreements: agreements,
    documentedGaps: documentedGaps,
    unavailable: unavailable,
    minimalGapBytes: minimalCase.input.length,
  );
}

bool _isSuccessfulSgrReport(Uint8List replies) {
  const List<int> prefix = <int>[0x1b, 0x50, 0x31, 0x24, 0x72];
  const List<int> suffix = <int>[0x6d, 0x1b, 0x5c];
  if (replies.length < prefix.length + suffix.length) return false;
  for (int index = 0; index < prefix.length; index++) {
    if (replies[index] != prefix[index]) return false;
  }
  final int suffixOffset = replies.length - suffix.length;
  for (int index = 0; index < suffix.length; index++) {
    if (replies[suffixOffset + index] != suffix[index]) return false;
  }
  for (int index = prefix.length; index < suffixOffset; index++) {
    final int byte = replies[index];
    if (!((byte >= 0x30 && byte <= 0x39) || byte == 0x3b || byte == 0x3a)) {
      return false;
    }
  }
  return true;
}

bool _contains(Uint8List source, Uint8List candidate) {
  for (int offset = 0; offset <= source.length - candidate.length; offset++) {
    bool match = true;
    for (int index = 0; index < candidate.length; index++) {
      if (source[offset + index] != candidate[index]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _encodeHex(List<int> bytes) => <String>[
  for (final int byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join();

void main(List<String> arguments) {
  try {
    final bool check = switch (arguments) {
      <String>[] => false,
      <String>['--check'] => true,
      _ => throw const TerminalDifferentialAcceptanceException(
        'usage: terminal_differential_acceptance.dart [--check]',
      ),
    };
    stdout.writeln(
      runTerminalDifferentialAcceptanceChecks(check: check).machineLine(),
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_ACCEPTANCE_FAIL $error');
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDifferentialAcceptanceException(message);
}
