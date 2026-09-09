import 'dart:convert';
import 'dart:io';

import '../tool/phase7_appkit_acceptance.dart';

void main() => runPhase7AppKitAcceptanceTests();

void runPhase7AppKitAcceptanceTests() {
  final String generated = generatePhase7AppKitAcceptance();
  final String committed = File(phase7AppKitAcceptancePath).readAsStringSync();
  validatePhase7AppKitAcceptanceSource(committed, expectedSource: generated);
  final Phase7AppKitAcceptanceResult result = runPhase7AppKitAcceptanceChecks();
  _expect(
    result.criteria == 4 &&
        result.sourceReferences == 12 &&
        result.unitTests == 9 &&
        result.integrationTests == 4 &&
        result.uiAssertions == 6 &&
        result.machineLine() ==
            'PHASE7_APPKIT_ACCEPTANCE_PASS criteria=4 source_refs=12 '
                'unit_tests=9 integration_tests=4 ui_assertions=6',
    'reviewed Phase 7 layer totals are exact',
  );
  final Map<String, Object?> report =
      jsonDecode(committed) as Map<String, Object?>;
  _expectFailure(
    _mutate(report, 'status', 'incomplete'),
    generated,
    'status mutation',
  );
  _expectFailure(
    committed.replaceFirst(
      'multi-window-tab-pane-restoration',
      'unknown-criterion',
    ),
    generated,
    'criterion mutation',
  );
  _expectFailure(
    committed.replaceFirst(
      RegExp(r'[0-9a-f]{64}'),
      List<String>.filled(64, '0').join(),
    ),
    generated,
    'source freshness mutation',
  );
}

String _mutate(Map<String, Object?> source, String key, Object? value) {
  final Map<String, Object?> copy = Map<String, Object?>.from(source);
  copy[key] = value;
  return '${const JsonEncoder.withIndent('  ').convert(copy)}\n';
}

void _expectFailure(String source, String expected, String message) {
  try {
    validatePhase7AppKitAcceptanceSource(source, expectedSource: expected);
  } on Phase7AppKitAcceptanceException {
    return;
  }
  throw StateError('test failed: accepted $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
