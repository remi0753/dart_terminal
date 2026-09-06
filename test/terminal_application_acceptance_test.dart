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
        result.cleanAgreements == 2 &&
        result.documentedGapCells == 6 &&
        result.gaps == 12 &&
        result.uniqueSequences == 18 &&
        result.unsupportedIncrements == 82 &&
        result.machineLine() ==
            'TERMINAL_APPLICATION_ACCEPTANCE_PASS accepted=8 clean=2 '
                'documented_gap_cells=6 gaps=12 unique_sequences=18 '
                'unsupported_increments=82',
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
  final Map<String, Object?> gap = _gap(report, 'application-escape-mode');
  gap['variants'] = <String>['1b5b3f3737323768'];
  _expectFailure(report, 'tmux-session-resize has unowned sequence');
}

void _testScreenMutationFailure() {
  final Map<String, Object?> report = _report();
  _gap(report, 'decrqss')['screen_mutation'] = true;
  _expectFailure(report, 'decrqss screen-mutation classification differs');
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
