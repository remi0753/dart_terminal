import 'dart:convert';
import 'dart:io';

import 'terminal_compatibility_inventory.dart';
import 'terminal_differential_harness.dart';
import 'terminal_differential_sha256.dart';

const String defaultReviewedDifferentialManifestPath =
    'test/corpus/differential/reviewed_v1.json';
const String defaultReviewedDifferentialBaselineDirectory =
    'test/corpus/differential/baseline';
const String defaultReviewedDifferentialBaselineReportPath =
    'compatibility/differential_baseline_report.json';
const String _implementationManifestPath =
    'compatibility/implemented_sequence_manifest.json';

final class ReviewedDifferentialCorpusException implements Exception {
  const ReviewedDifferentialCorpusException(this.message);

  final String message;

  @override
  String toString() => 'ReviewedDifferentialCorpusException: $message';
}

final class ReviewedDifferentialCorpusResult {
  const ReviewedDifferentialCorpusResult({
    required this.caseCount,
    required this.inputBytes,
    required this.splitRuns,
  });

  final int caseCount;
  final int inputBytes;
  final int splitRuns;

  String machineLine() =>
      'TERMINAL_DIFFERENTIAL_CORPUS_BASELINE_PASS cases=$caseCount '
      'input_bytes=$inputBytes split_runs=$splitRuns external_captures=0';
}

ReviewedDifferentialCorpusResult runReviewedDifferentialCorpusChecks({
  bool check = true,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final File inventoryFile = File.fromUri(
    root.uri.resolve(defaultTerminalCompatibilityInventoryPath),
  );
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(inventoryFile, repositoryRoot: root);
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
  _expect(
    manifest.scope == 'reviewed-corpus',
    'manifest is not reviewed corpus',
  );
  final File implementationFile = File.fromUri(
    root.uri.resolve(_implementationManifestPath),
  );
  _expect(
    implementationFile.existsSync() &&
        FileSystemEntity.typeSync(
              implementationFile.path,
              followLinks: false,
            ) ==
            FileSystemEntityType.file,
    'implementation manifest is unavailable',
  );
  final String implementationSha256 = terminalDifferentialSha256(
    implementationFile.readAsBytesSync(),
  );
  final TerminalDifferentialProvenance provenance =
      TerminalDifferentialProvenance(
        product: 'dart-terminal',
        productVersion: 'workspace',
        implementationRevision: 'surface-sha256-$implementationSha256',
        executableSha256: null,
        configId: 'defaults-v1',
        configSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        captureMethod: 'in-process-screen-v1',
        operatingSystem: 'portable-model',
        architecture: 'model-v1',
      );
  const DartTerminalDifferentialBackend backend =
      DartTerminalDifferentialBackend();
  const TerminalDifferentialComparator comparator =
      TerminalDifferentialComparator();
  final Map<String, String> observationFiles = <String, String>{};
  final List<Map<String, Object?>> caseReports = <Map<String, Object?>>[];
  final Set<String> families = <String>{};
  int inputBytes = 0;
  int splitRuns = 0;
  for (final TerminalDifferentialCase testCase in manifest.cases) {
    final String family = testCase.id.split('-').first;
    _expect(
      const <String>{'editing', 'mode', 'query', 'rendition'}.contains(family),
      '${testCase.id} has an unknown review family',
    );
    _expect(families.add(family), 'review family $family is duplicated');
    inputBytes += testCase.input.length;
    final TerminalDifferentialObservation whole = backend.capture(
      testCase,
      provenance: provenance,
    );
    final String encoded = whole.encode();
    final TerminalDifferentialObservation decoded =
        TerminalDifferentialObservation.parse(encoded, testCase: testCase);
    _expect(
      comparator.compare(testCase, whole, decoded).matches,
      '${testCase.id} baseline round trip differs',
    );
    int caseSplitRuns = 0;
    for (int split = 0; split <= testCase.input.length; split++) {
      final TerminalDifferentialObservation splitObservation = backend.capture(
        testCase,
        provenance: provenance,
        chunkLengths: <int>[split, testCase.input.length - split],
      );
      _expect(
        comparator.compare(testCase, whole, splitObservation).matches,
        '${testCase.id} differs at split $split',
      );
      caseSplitRuns++;
    }
    final TerminalDifferentialObservation bytewise = backend.capture(
      testCase,
      provenance: provenance,
      chunkLengths: List<int>.filled(testCase.input.length, 1),
    );
    _expect(
      comparator.compare(testCase, whole, bytewise).matches,
      '${testCase.id} differs under bytewise input',
    );
    caseSplitRuns++;
    splitRuns += caseSplitRuns;
    final String observationPath =
        '$defaultReviewedDifferentialBaselineDirectory/${testCase.id}.json';
    observationFiles[observationPath] = encoded;
    caseReports.add(<String, Object?>{
      'id': testCase.id,
      'family': family,
      'inventory_ids': testCase.inventoryIds,
      'input_sha256': terminalDifferentialSha256(testCase.input),
      'fields': <String>[
        for (final TerminalDifferentialField field in testCase.fields)
          field.name,
      ],
      'expectation': testCase.expectation.name,
      'observation_path': observationPath,
      'observation_sha256': terminalDifferentialSha256(utf8.encode(encoded)),
      'split_runs': caseSplitRuns,
      'external_evidence': 'separate-acceptance-report',
    });
  }
  _expect(
    families.length == 4 &&
        families.containsAll(const <String>{
          'editing',
          'mode',
          'query',
          'rendition',
        }),
    'reviewed corpus must cover four required families',
  );
  final String report =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': 'dart-terminal-differential-baseline-report',
        'version': 1,
        'manifest_path': defaultReviewedDifferentialManifestPath,
        'manifest_sha256': terminalDifferentialSha256(manifestFile.readAsBytesSync()),
        'inventory_path': defaultTerminalCompatibilityInventoryPath,
        'inventory_sha256': terminalDifferentialSha256(inventoryFile.readAsBytesSync()),
        'implementation_manifest_path': _implementationManifestPath,
        'implementation_manifest_sha256': implementationSha256,
        'observation_version': manifest.observationVersion,
        'cases': caseReports,
        'summary': <String, Object?>{'case_count': manifest.cases.length, 'input_bytes': inputBytes, 'split_runs': splitRuns, 'families': families.toList()..sort(), 'external_captures': 0},
      })}\n';
  final File reportFile = File.fromUri(
    root.uri.resolve(defaultReviewedDifferentialBaselineReportPath),
  );
  if (check) {
    _expect(reportFile.existsSync(), 'baseline report is missing');
    _expect(
      reportFile.readAsStringSync() == report,
      'baseline report is stale',
    );
    final Directory baselineDirectory = Directory.fromUri(
      root.uri.resolve('$defaultReviewedDifferentialBaselineDirectory/'),
    );
    _expect(baselineDirectory.existsSync(), 'baseline directory is missing');
    final Set<String> expectedNames = <String>{
      for (final String path in observationFiles.keys) path.split('/').last,
    };
    final Set<String> actualNames = <String>{
      for (final FileSystemEntity entity in baselineDirectory.listSync())
        if (entity is File && entity.path.endsWith('.json'))
          entity.uri.pathSegments.last,
    };
    _expect(
      expectedNames.length == actualNames.length &&
          expectedNames.containsAll(actualNames),
      'baseline observation file set differs',
    );
    for (final MapEntry<String, String> entry in observationFiles.entries) {
      final File file = File.fromUri(root.uri.resolve(entry.key));
      _expect(file.existsSync(), '${entry.key} is missing');
      _expect(file.readAsStringSync() == entry.value, '${entry.key} is stale');
    }
  } else {
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(report, flush: true);
    for (final MapEntry<String, String> entry in observationFiles.entries) {
      final File file = File.fromUri(root.uri.resolve(entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value, flush: true);
    }
  }
  return ReviewedDifferentialCorpusResult(
    caseCount: manifest.cases.length,
    inputBytes: inputBytes,
    splitRuns: splitRuns,
  );
}

void main(List<String> arguments) {
  try {
    final bool check = switch (arguments) {
      <String>[] => false,
      <String>['--check'] => true,
      _ => throw const ReviewedDifferentialCorpusException(
        'usage: terminal_differential_corpus.dart [--check]',
      ),
    };
    stdout.writeln(
      runReviewedDifferentialCorpusChecks(check: check).machineLine(),
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_CORPUS_BASELINE_FAIL $error');
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw ReviewedDifferentialCorpusException(message);
}
