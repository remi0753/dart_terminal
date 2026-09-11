import 'dart:convert';
import 'dart:io';

import '../tool/terminal_compatibility_regression_coverage.dart';

void main() => runTerminalCompatibilityRegressionCoverageTests();

void runTerminalCompatibilityRegressionCoverageTests() {
  final String generated = generateTerminalCompatibilityRegressionCoverage();
  final String committed = File(terminalCompatibilityRegressionCoveragePath)
      .readAsStringSync();
  validateTerminalCompatibilityRegressionCoverageSource(
    committed,
    expectedSource: generated,
  );
  final Map<String, Object?> report =
      jsonDecode(committed) as Map<String, Object?>;
  final Map<String, Object?> acceptance =
      report['acceptance']! as Map<String, Object?>;
  final Map<String, Object?> corpus =
      acceptance['regression_corpus']! as Map<String, Object?>;
  final Map<String, Object?> phaseExit =
      report['phase_exit']! as Map<String, Object?>;
  _expect(
    (report['fix_families']! as List<Object?>).length == 9 &&
        (report['owned_application_gaps']! as List<Object?>).length == 1 &&
        corpus['cases'] == 9 &&
        corpus['split_runs'] == 417 &&
        phaseExit['known_p0_silent_corruption'] == 0 &&
        phaseExit['duration_only_soak'] == 'low-priority-nonblocking-follow-up',
    'reviewed coverage and Phase exit totals are exact',
  );
  _expectFailure(
    committed.replaceFirst('"fix_families": 9', '"fix_families": 8'),
    generated,
    'stale total',
  );
  _expectFailure(
    committed.replaceFirst(
      '"id": "dec-special-graphics"',
      '"id": "unknown-family"',
    ),
    generated,
    'unknown family',
  );
  _expectFailure(
    committed.replaceFirst(
      RegExp(r'[0-9a-f]{64}'),
      List<String>.filled(64, '0').join(),
    ),
    generated,
    'stale source pin',
  );
  _expectFailure(
    committed.replaceFirst(
      '"known_p0_silent_corruption": 0',
      '"known_p0_silent_corruption": 1',
    ),
    generated,
    'silent corruption mutation',
  );
}

void _expectFailure(String source, String expected, String message) {
  try {
    validateTerminalCompatibilityRegressionCoverageSource(
      source,
      expectedSource: expected,
    );
  } on TerminalCompatibilityRegressionCoverageException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
