import 'dart:convert';
import 'dart:io';

import '../tool/release_candidate_daily_use.dart';

void main() => runReleaseCandidateDailyUseTests();

void runReleaseCandidateDailyUseTests() {
  final String generated = generateReleaseCandidateDailyUseMatrix();
  final String committed = File(releaseCandidateDailyUseMatrixPath)
      .readAsStringSync();
  final ReleaseCandidateDailyUseResult result =
      validateReleaseCandidateDailyUseMatrixSource(
        committed,
        expectedSource: generated,
      );
  _expect(
    result.programs == 8 &&
        result.cleanPrograms == 7 &&
        result.documentedProgramGaps == 1 &&
        result.workflows == 8 &&
        result.gates == 31 &&
        result.knownLimitations == 5,
    'reviewed release-candidate totals are exact',
  );
  final Map<String, Object?> report =
      jsonDecode(committed) as Map<String, Object?>;
  final String lower = committed.toLowerCase();
  _expect(
    utf8.encode(committed).length <= 1024 * 1024 &&
        !committed.contains('/Users/') &&
        !lower.contains('terminal_text') &&
        !lower.contains('clipboard_text') &&
        !lower.contains('process_id') &&
        !lower.contains('timestamp') &&
        !lower.contains('environment_variables'),
    'checked-in matrix is bounded and content-free',
  );
  _expect(
    (report['programs']! as List<Object?>).length == 8 &&
        (report['workflows']! as List<Object?>).length == 8 &&
        (report['gate_catalog']! as List<Object?>).length == 31 &&
        (report['known_limitations']! as List<Object?>).length == 5,
    'all program, workflow, gate, and limitation cells are present',
  );

  _expectStaleFailure(
    committed.replaceFirst(RegExp(r'"sha256": "[0-9a-f]'), '"sha256": "0'),
    generated,
    'source hash drift',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"status": "bounded-release-candidate-ready"',
      '"status": "unreviewed"',
    ),
    'status drift',
  );
  _expectSemanticFailure(
    committed.replaceFirst('"blocker_bugs": 0', '"blocker_bugs": 1'),
    'nonzero blocker',
  );
  _expectSemanticFailure(
    committed.replaceFirst('"actionable_p1": 0', '"actionable_p1": 1'),
    'actionable P1 gap',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"apple_notarization": false',
      '"apple_notarization": true',
    ),
    'false notarization claim',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"fresh_external_program_launch": false',
      '"fresh_external_program_launch": true',
    ),
    'false external launch claim',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"classification": "documented-gap"',
      '"classification": "clean-agreement"',
    ),
    'unowned mosh difference',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"id": "startup-shell"',
      '"id": "startup-unreviewed"',
    ),
    'workflow identity drift',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"id": "runtime-integration"',
      '"id": "runtime-unreviewed"',
    ),
    'gate identity drift',
  );
  _expectSemanticFailure(
    committed.replaceFirst(
      '"release_blocker": false',
      '"release_blocker": true',
    ),
    'limitation promoted to blocker',
  );
}

void _expectStaleFailure(String source, String expected, String label) {
  var failed = false;
  try {
    validateReleaseCandidateDailyUseMatrixSource(
      source,
      expectedSource: expected,
    );
  } on ReleaseCandidateDailyUseException {
    failed = true;
  }
  _expect(failed, '$label did not fail closed');
}

void _expectSemanticFailure(String source, String label) {
  var failed = false;
  try {
    validateReleaseCandidateDailyUseMatrixSource(
      source,
      expectedSource: source,
    );
  } on ReleaseCandidateDailyUseException {
    failed = true;
  }
  _expect(failed, '$label did not fail closed');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
