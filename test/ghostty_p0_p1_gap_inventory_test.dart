import 'dart:convert';
import 'dart:io';

import '../tool/ghostty_p0_p1_gap_inventory.dart';

void main() => runGhosttyP0P1GapInventoryTests();

void runGhosttyP0P1GapInventoryTests() {
  final String generated = generateGhosttyP0P1GapInventory();
  final String committed = File(ghosttyP0P1GapInventoryPath).readAsStringSync();
  final GhosttyP0P1GapInventoryResult result =
      validateGhosttyP0P1GapInventorySource(
        committed,
        expectedSource: generated,
      );
  _expect(
    result.rows == 102 &&
        result.accepted == 90 &&
        result.actionableP0 == 0 &&
        result.actionableP1 == 7 &&
        result.documentedDifferences == 2 &&
        result.externalFollowUps == 3,
    'reviewed result totals are exact',
  );
  final Map<String, Object?> report =
      jsonDecode(committed) as Map<String, Object?>;
  final List<Object?> rows = report['rows']! as List<Object?>;
  final List<Object?> gaps = report['gaps']! as List<Object?>;
  _expect(
    rows.length == 102 &&
        gaps.length == 12 &&
        rows
                .cast<Map<String, Object?>>()
                .where((row) => row['classification'] == 'actionable-p1')
                .length ==
            7 &&
        gaps
            .cast<Map<String, Object?>>()
            .where((gap) => gap['silent_misbehavior'] == true)
            .isEmpty,
    'every row and reviewed gap is represented',
  );
  _expectFailure(
    committed.replaceFirst('"actionable_p1": 7', '"actionable_p1": 8'),
    generated,
    'stale actionable total',
  );
  _expectFailure(
    committed.replaceFirst(
      '"pinned_ghostty_revision": "d4d8f622',
      '"pinned_ghostty_revision": "00000000',
    ),
    generated,
    'pinned revision drift',
  );
  final String matrix = File('FEATURE_MATRIX.md').readAsStringSync();
  _expectMatrixFailure(
    matrix.replaceFirst('| RT-02 |', '| RT-01 |'),
    'duplicate row',
  );
  _expectMatrixFailure(
    matrix.replaceFirst(
      'ghostty-org/ghostty@d4d8f62262cb1a974a7d2470d5f79f811fab15e4',
      'ghostty-org/ghostty@0000000000000000000000000000000000000000',
    ),
    'matrix revision drift',
  );
  final String sequenceInventory = File(
    'compatibility/sequence_mode_inventory.json',
  ).readAsStringSync();
  final String applicationAcceptance = File(
    'compatibility/application_matrix_acceptance.json',
  ).readAsStringSync();
  final String regressionCoverage = File(
    'compatibility/regression_coverage_report.json',
  ).readAsStringSync();
  final String implementationManifest = File(
    'compatibility/implemented_sequence_manifest.json',
  ).readAsStringSync();
  validateGhosttyP0ClosureSources(
    sequenceInventorySource: sequenceInventory,
    applicationAcceptanceSource: applicationAcceptance,
    regressionCoverageSource: regressionCoverage,
  );
  _expectP0Failure(
    sequenceInventory,
    applicationAcceptance.replaceFirst(
      '"screen_mutation": false',
      '"screen_mutation": true',
    ),
    regressionCoverage,
    'screen-mutating documented difference',
  );
  _expectP0Failure(
    sequenceInventory.replaceFirst(
      '"id": "xterm:mode:xterm-hilite-mouse-tracking",',
      '"id": "xterm:mode:unowned-hilite-mouse-tracking",',
    ),
    applicationAcceptance,
    regressionCoverage,
    'missing exact inventory owner',
  );
  _expectP0Failure(
    sequenceInventory,
    applicationAcceptance,
    regressionCoverage.replaceFirst(
      '"known_p0_silent_corruption": 0',
      '"known_p0_silent_corruption": 1',
    ),
    'silent P0 regression',
  );
  validateGhosttyP1ExtendedRenditionClosureSources(
    sequenceInventorySource: sequenceInventory,
    implementationManifestSource: implementationManifest,
  );
  _expectP1Failure(
    sequenceInventory.replaceFirst(
      '"id": "dec:csi:decsel",',
      '"id": "dec:csi:unowned-decsel",',
    ),
    implementationManifest,
    'missing DECSEL evidence',
  );
  _expectP1Failure(
    sequenceInventory,
    implementationManifest.replaceFirst(
      '"key": "csi:-1:1:34:113",',
      '"key": "csi:-1:1:34:114",',
    ),
    'missing DECSCA selector',
  );
}

void _expectFailure(String source, String expected, String message) {
  try {
    validateGhosttyP0P1GapInventorySource(source, expectedSource: expected);
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectMatrixFailure(String source, String message) {
  try {
    parseGhosttyP0P1MatrixSource(source);
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectP0Failure(
  String inventory,
  String application,
  String regression,
  String message,
) {
  try {
    validateGhosttyP0ClosureSources(
      sequenceInventorySource: inventory,
      applicationAcceptanceSource: application,
      regressionCoverageSource: regression,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectP1Failure(
  String sequenceInventory,
  String implementationManifest,
  String message,
) {
  var threw = false;
  try {
    validateGhosttyP1ExtendedRenditionClosureSources(
      sequenceInventorySource: sequenceInventory,
      implementationManifestSource: implementationManifest,
    );
  } on GhosttyP0P1GapInventoryException {
    threw = true;
  }
  _expect(threw, message);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
