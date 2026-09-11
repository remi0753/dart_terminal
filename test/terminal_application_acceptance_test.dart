import 'dart:convert';
import 'dart:io';

import '../tool/terminal_application_acceptance.dart';

void main() => runTerminalApplicationAcceptanceTests();

void runTerminalApplicationAcceptanceTests() {
  _testReviewedAcceptance();
  _testFreshnessFailure();
  _testImplementationFreshnessFailure();
  _testUnownedSequenceFailure();
  _testScreenMutationFailure();
  _testOwnerFailure();
}

void _testReviewedAcceptance() {
  final TerminalApplicationAcceptanceResult result =
      runTerminalApplicationAcceptanceChecks();
  _expect(
    result.acceptedCells == 8 &&
        result.cleanAgreements == 4 &&
        result.documentedGapCells == 4 &&
        result.gaps == 4 &&
        result.uniqueSequences == 6 &&
        result.unsupportedIncrements == 63 &&
        result.machineLine() ==
            'TERMINAL_APPLICATION_ACCEPTANCE_PASS accepted=8 clean=4 '
                'documented_gap_cells=4 gaps=4 unique_sequences=6 '
                'unsupported_increments=63',
    'reviewed acceptance has exact replay-derived totals',
  );
}

void _testImplementationFreshnessFailure() {
  final Map<String, Object?> report = _report();
  report['implementation_manifest_sha256'] = List<String>.filled(
    64,
    '0',
  ).join();
  _expectFailure(report, 'implementation manifest hash differs');
}

void _testFreshnessFailure() {
  final Map<String, Object?> report = _report();
  report['evidence_index_sha256'] = List<String>.filled(64, '0').join();
  _expectFailure(report, 'evidence index hash differs');
}

void _testUnownedSequenceFailure() {
  final Map<String, Object?> report = _report();
  final Map<String, Object?> gap = _gap(report, 'synchronized-output');
  gap['variants'] = <String>['1b5b3f3230323668'];
  _expectFailure(report, 'fzf-filter-selection has unowned sequence');
}

void _testScreenMutationFailure() {
  final Map<String, Object?> report = _report();
  _gap(report, 'hilite-mouse')['screen_mutation'] = true;
  _expectFailure(report, 'hilite-mouse screen-mutation classification differs');
}

void _testOwnerFailure() {
  final Map<String, Object?> report = _report();
  _gap(report, 'synchronized-output')['owner'] = 'ROADMAP.md#missing';
  _expectFailure(
    report,
    'synchronized-output owner is not a reviewed ROADMAP owner',
  );
}

Map<String, Object?> _report() => Map<String, Object?>.from(
  jsonDecode(File(defaultTerminalApplicationAcceptancePath).readAsStringSync())
      as Map<Object?, Object?>,
);

Map<String, Object?> _gap(Map<String, Object?> report, String id) {
  for (final Object? value in report['gaps']! as List<Object?>) {
    final Map<String, Object?> gap = value! as Map<String, Object?>;
    if (gap['id'] == id) return gap;
  }
  throw StateError('test fixture gap is missing: $id');
}

void _expectFailure(Map<String, Object?> report, String message) {
  final Directory directory = Directory.systemTemp.createTempSync(
    'dart-terminal-application-acceptance-',
  );
  try {
    final File file = File('${directory.path}/acceptance.json')
      ..writeAsStringSync('${jsonEncode(report)}\n');
    try {
      runTerminalApplicationAcceptanceChecks(reportFile: file);
    } on TerminalApplicationAcceptanceException catch (error) {
      _expect(
        error.message.contains(message),
        'acceptance failed for expected reason $message: $error',
      );
      return;
    }
    throw StateError('test failed: acceptance accepted invalid $message');
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
