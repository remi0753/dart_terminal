import 'dart:convert';
import 'dart:io';

import '../tool/terminal_compatibility_inventory.dart';
import '../tool/terminal_differential_corpus.dart';
import '../tool/terminal_differential_harness.dart';
import '../tool/terminal_differential_sha256.dart';

void main() => runTerminalDifferentialCorpusTests();

void runTerminalDifferentialCorpusTests() {
  final ReviewedDifferentialCorpusResult result =
      runReviewedDifferentialCorpusChecks();
  _expect(
    result.caseCount == 4 &&
        result.inputBytes == 202 &&
        result.splitRuns == 210 &&
        result.machineLine() ==
            'TERMINAL_DIFFERENTIAL_CORPUS_BASELINE_PASS cases=4 '
                'input_bytes=202 split_runs=210 external_captures=0',
    'reviewed Dart baseline is byte and split exact',
  );

  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(defaultTerminalCompatibilityInventoryPath),
        repositoryRoot: Directory.current,
      );
  final TerminalDifferentialManifest manifest =
      TerminalDifferentialManifest.load(
        File(defaultReviewedDifferentialManifestPath),
        inventoryIds: <String>{
          for (final TerminalCompatibilityRecord record in inventory.records)
            record.id,
        },
      );
  _expect(
    manifest.scope == 'reviewed-corpus' &&
        manifest.cases
                .map((TerminalDifferentialCase testCase) => testCase.id)
                .join(',') ==
            'editing-character-operations,mode-private-transitions,'
                'query-status-and-modes,rendition-attributes-colors' &&
        manifest.cases.every(
          (TerminalDifferentialCase testCase) =>
              testCase.expectation == TerminalDifferentialExpectation.agree &&
              testCase.gapOwner == null &&
              testCase.inventoryIds.isNotEmpty,
        ),
    'reviewed manifest covers four inventory-traceable agreement candidates',
  );

  final Map<String, Object?> report = _object(
    jsonDecode(
      File(defaultReviewedDifferentialBaselineReportPath).readAsStringSync(),
    ),
  );
  _expect(
    report['format'] == 'dart-terminal-differential-baseline-report' &&
        report['version'] == 1 &&
        report['manifest_sha256'] ==
            terminalDifferentialSha256(
              File(defaultReviewedDifferentialManifestPath).readAsBytesSync(),
            ),
    'baseline report is tied to the exact reviewed manifest',
  );
  final Map<String, Object?> summary = _object(report['summary']);
  _expect(
    summary['case_count'] == 4 &&
        summary['external_captures'] == 0 &&
        (summary['families'] as List<Object?>).join(',') ==
            'editing,mode,query,rendition',
    'baseline report cannot imply external comparator evidence',
  );
  final List<Object?> cases = report['cases']! as List<Object?>;
  _expect(
    cases.length == 4 &&
        cases.every(
          (Object? value) => _object(value)['external_evidence'] == 'pending',
        ),
    'each reviewed baseline keeps external evidence pending',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<Object?, Object?>) throw StateError('expected object');
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key! as String: entry.value,
  };
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
