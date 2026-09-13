import 'dart:convert';
import 'dart:io';

import 'terminal_differential_sha256.dart';

const String ghosttyP0P1GapInventoryPath =
    'compatibility/ghostty_p0_p1_gap_inventory.json';
const String _matrixPath = 'FEATURE_MATRIX.md';
const String _matrixRevision = 'd4d8f62262cb1a974a7d2470d5f79f811fab15e4';
const String _differentialRevision = '492300cad104195411d12217dd22f1cd05f31376';

const List<String> _expectedRowIds = <String>[
  'RT-01',
  'RT-02',
  'RT-03',
  'PTY-01',
  'PTY-02',
  'PTY-03',
  'PTY-04',
  'PTY-05',
  'PTY-06',
  'PTY-07',
  'PTY-08',
  'PAR-01',
  'PAR-02',
  'PAR-03',
  'PAR-04',
  'PAR-05',
  'SCR-01',
  'SCR-02',
  'SCR-03',
  'SCR-04',
  'SCR-05',
  'SCR-06',
  'SCR-07',
  'SCR-08',
  'SCR-09',
  'SCR-10',
  'SCR-11',
  'SCR-12',
  'CAP-01',
  'CAP-02',
  'CAP-03',
  'CAP-04',
  'CAP-05',
  'CAP-06',
  'CAP-07',
  'CAP-08',
  'CAP-09',
  'CAP-10',
  'CAP-11',
  'CAP-12',
  'TXT-01',
  'TXT-02',
  'TXT-03',
  'TXT-04',
  'TXT-05',
  'TXT-06',
  'TXT-07',
  'TXT-08',
  'TXT-09',
  'TXT-10',
  'REN-01',
  'REN-02',
  'REN-03',
  'REN-04',
  'REN-05',
  'REN-06',
  'REN-07',
  'REN-08',
  'REN-09',
  'IN-01',
  'IN-02',
  'IN-03',
  'IN-04',
  'IN-05',
  'IN-06',
  'IN-07',
  'IN-08',
  'IN-09',
  'IN-10',
  'UI-01',
  'UI-02',
  'UI-03',
  'UI-04',
  'UI-05',
  'UI-06',
  'UI-07',
  'UI-08',
  'UI-09',
  'CFG-01',
  'CFG-02',
  'CFG-03',
  'CFG-04',
  'CFG-05',
  'CFG-06',
  'CFG-07',
  'AX-01',
  'AX-02',
  'AX-03',
  'AX-04',
  'SEC-01',
  'SEC-02',
  'SEC-03',
  'SEC-04',
  'SEC-05',
  'QA-01',
  'QA-02',
  'PERF-01',
  'PERF-02',
  'REL-01',
  'DIST-01',
  'DIST-02',
  'DIST-04',
];

const Map<String, String> _classifications = <String, String>{
  'CAP-03': 'accepted-documented-difference',
  'QA-02': 'accepted-documented-difference',
  'REL-01': 'accepted-external-follow-up',
  'DIST-01': 'accepted-external-follow-up',
  'DIST-02': 'accepted-external-follow-up',
  'TXT-07': 'actionable-p1',
  'TXT-08': 'actionable-p1',
  'TXT-10': 'actionable-p1',
  'REN-08': 'actionable-p1',
  'IN-10': 'actionable-p1',
};

const Map<String, List<String>> _rowGapIds = <String, List<String>>{
  'CAP-03': <String>['hilite-mouse'],
  'QA-02': <String>['ghostty-differential-activation', 'hilite-mouse'],
  'REL-01': <String>['physical-duration-reliability'],
  'DIST-01': <String>['intel-native-handoff'],
  'DIST-02': <String>['apple-service-acceptance'],
  'TXT-07': <String>['cursor-ligature-break'],
  'TXT-08': <String>['font-axes-overrides-diagnostics'],
  'TXT-10': <String>['synthetic-cell-glyphs'],
  'REN-08': <String>['remaining-overlays-and-color-conversion'],
  'IN-10': <String>['option-click-and-semantic-selection'],
};

const List<_Gap> _gaps = <_Gap>[
  _Gap(
    id: 'hilite-mouse',
    kind: 'documented-product-difference',
    priority: 'P0',
    rowIds: <String>['CAP-03', 'QA-02'],
    owner: 'compatibility/application_matrix_acceptance.json',
    productActionable: false,
    reason: 'Only reset was observed; mode 1001 is explicitly unsupported and does not mutate the screen.',
  ),
  _Gap(
    id: 'ghostty-differential-activation',
    kind: 'supplemental-comparator-unavailable',
    priority: 'P1',
    rowIds: <String>['QA-02'],
    owner: 'compatibility/differential_acceptance_report.json',
    productActionable: false,
    reason: 'Four query cases have no observation because the separately pinned macOS app could not be activated.',
  ),
  _Gap(
    id: 'physical-duration-reliability',
    kind: 'approved-external-follow-up',
    priority: 'P1',
    rowIds: <String>['REL-01'],
    owner: 'docs/phase11/bounded-system-reliability.md',
    productActionable: false,
    reason: 'Physical events and real-time soak are separate from the passing bounded product gate.',
  ),
  _Gap(
    id: 'intel-native-handoff',
    kind: 'approved-external-follow-up',
    priority: 'P0',
    rowIds: <String>['DIST-01'],
    owner: 'docs/phase1/universal-runtime-matrix.md',
    productActionable: false,
    reason: 'Exact x86_64 and Universal build, audit, and Rosetta evidence passes; only an Intel-host run is deferred.',
  ),
  _Gap(
    id: 'apple-service-acceptance',
    kind: 'approved-external-follow-up',
    priority: 'P1',
    rowIds: <String>['DIST-02'],
    owner: 'docs/phase11/developer-id-notarization.md',
    productActionable: false,
    reason: 'Credential-independent distribution gates pass; positive signing and notarization needs external authority.',
  ),
  _Gap(
    id: 'cursor-ligature-break',
    kind: 'actionable-product-gap',
    priority: 'P1',
    rowIds: <String>['TXT-07'],
    owner: 'ROADMAP.md#phase-11-pinned-ghostty-gap-burn-down',
    productActionable: true,
    reason: 'Ligature toggling passes, but shaping is not split at the cursor cell.',
  ),
  _Gap(
    id: 'font-axes-overrides-diagnostics',
    kind: 'actionable-product-gap',
    priority: 'P1',
    rowIds: <String>['TXT-08'],
    owner: 'ROADMAP.md#phase-11-pinned-ghostty-gap-burn-down',
    productActionable: true,
    reason: 'Variable axes, codepoint override policy, and fallback diagnostics are absent.',
  ),
  _Gap(
    id: 'synthetic-cell-glyphs',
    kind: 'actionable-product-gap',
    priority: 'P1',
    rowIds: <String>['TXT-10'],
    owner: 'ROADMAP.md#phase-11-pinned-ghostty-gap-burn-down',
    productActionable: true,
    reason: 'Box, block, braille, and Powerline cell-filling synthetic glyphs are absent.',
  ),
  _Gap(
    id: 'remaining-overlays-and-color-conversion',
    kind: 'actionable-product-gap',
    priority: 'P1',
    rowIds: <String>['REN-08'],
    owner: 'ROADMAP.md#phase-11-pinned-ghostty-gap-burn-down',
    productActionable: true,
    reason: 'Hyperlink overlay passes; image, search, inspector, and P3 conversion remain incomplete.',
  ),
  _Gap(
    id: 'option-click-and-semantic-selection',
    kind: 'actionable-product-gap',
    priority: 'P1',
    rowIds: <String>['IN-10'],
    owner: 'ROADMAP.md#phase-11-pinned-ghostty-gap-burn-down',
    productActionable: true,
    reason: 'Drag and Services pass; Option-click cursor positioning and semantic selection remain.',
  ),
];

const List<String> _evidencePaths = <String>[
  'docs/phase6/specification-source-pins.md',
  'compatibility/sequence_mode_inventory.json',
  'compatibility/implemented_sequence_manifest.json',
  'compatibility/differential_backends.json',
  'compatibility/differential_capture_evidence.json',
  'compatibility/differential_acceptance_report.json',
  'compatibility/application_matrix_acceptance.json',
  'compatibility/regression_coverage_report.json',
  'benchmark/evidence/ghostty-performance-comparator-macos-arm64-m1.json',
  'benchmark/evidence/product-relative-performance-macos-arm64-m1.json',
  'lib/src/terminal_core/terminal_semantic_prompt.dart',
  'lib/src/terminal_core/terminal_semantic_ranges.dart',
  'test/terminal_semantic_prompt_test.dart',
  'lib/src/terminal_core/terminal_snapshot.dart',
  'lib/src/terminal_core/terminal_snapshot_restore.dart',
  'lib/src/terminal_core/terminal_snapshot_restore_state.dart',
  'lib/src/terminal_core/terminal_snapshot_restore_set_state.dart',
  'lib/src/terminal_core/terminal_session_metadata.dart',
  'test/terminal_snapshot_test.dart',
];

final class GhosttyP0P1GapInventoryException implements Exception {
  const GhosttyP0P1GapInventoryException(this.message);

  final String message;

  @override
  String toString() => 'GhosttyP0P1GapInventoryException: $message';
}

final class GhosttyP0P1GapInventoryResult {
  const GhosttyP0P1GapInventoryResult();

  int get rows => 102;
  int get accepted => 92;
  int get actionableP0 => 0;
  int get actionableP1 => 5;
  int get documentedDifferences => 2;
  int get externalFollowUps => 3;

  String machineLine() =>
      'GHOSTTY_P0_P1_GAP_INVENTORY_PASS rows=$rows accepted=$accepted '
      'actionable_p0=$actionableP0 actionable_p1=$actionableP1 '
      'documented_differences=$documentedDifferences '
      'external_follow_ups=$externalFollowUps pinned_revision=d4d8f62';
}

String generateGhosttyP0P1GapInventory({Directory? repositoryRoot}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final File matrixFile = _regularFile(root, _matrixPath, 1024 * 1024);
  final String matrixSource = matrixFile.readAsStringSync();
  final List<GhosttyP0P1MatrixRow> rows = parseGhosttyP0P1MatrixSource(
    matrixSource,
  );
  _validatePinnedEvidence(root, matrixSource);
  validateGhosttyP0ClosureSources(
    sequenceInventorySource: _regularFile(
      root,
      'compatibility/sequence_mode_inventory.json',
      4 * 1024 * 1024,
    ).readAsStringSync(),
    applicationAcceptanceSource: _regularFile(
      root,
      'compatibility/application_matrix_acceptance.json',
      1024 * 1024,
    ).readAsStringSync(),
    regressionCoverageSource: _regularFile(
      root,
      'compatibility/regression_coverage_report.json',
      1024 * 1024,
    ).readAsStringSync(),
  );
  validateGhosttyP1ExtendedRenditionClosureSources(
    sequenceInventorySource: _regularFile(
      root,
      'compatibility/sequence_mode_inventory.json',
      4 * 1024 * 1024,
    ).readAsStringSync(),
    implementationManifestSource: _regularFile(
      root,
      'compatibility/implemented_sequence_manifest.json',
      1024 * 1024,
    ).readAsStringSync(),
  );
  validateGhosttyP1SemanticRangeClosureSources(
    sequenceInventorySource: _regularFile(
      root,
      'compatibility/sequence_mode_inventory.json',
      4 * 1024 * 1024,
    ).readAsStringSync(),
    semanticRangeSource: _regularFile(
      root,
      'lib/src/terminal_core/terminal_semantic_ranges.dart',
      1024 * 1024,
    ).readAsStringSync(),
    semanticRangeTestSource: _regularFile(
      root,
      'test/terminal_semantic_prompt_test.dart',
      1024 * 1024,
    ).readAsStringSync(),
  );
  validateGhosttyP1SnapshotRestoreClosureSources(
    snapshotFormatterSource: _regularFile(
      root,
      'lib/src/terminal_core/terminal_snapshot.dart',
      1024 * 1024,
    ).readAsStringSync(),
    snapshotRestoreSource: _regularFile(
      root,
      'lib/src/terminal_core/terminal_snapshot_restore.dart',
      2 * 1024 * 1024,
    ).readAsStringSync(),
    snapshotRestoreTestSource: _regularFile(
      root,
      'test/terminal_snapshot_test.dart',
      1024 * 1024,
    ).readAsStringSync(),
  );
  final Map<String, int> priorities = <String, int>{};
  final Map<String, int> classifications = <String, int>{};
  final List<Map<String, Object?>> encodedRows = <Map<String, Object?>>[];
  for (final GhosttyP0P1MatrixRow row in rows) {
    final String classification = _classifications[row.id] ?? 'accepted';
    priorities.update(
      row.priority,
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
    classifications.update(
      classification,
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
    encodedRows.add(<String, Object?>{
      'id': row.id,
      'priority': row.priority,
      'phase': row.phase,
      'acceptance_sha256': _sha256Bytes(utf8.encode(row.acceptance)),
      'pinned_evidence_sha256': _sha256Bytes(utf8.encode(row.pinnedEvidence)),
      'current_sha256': _sha256Bytes(utf8.encode(row.current)),
      'classification': classification,
      'gap_ids': _rowGapIds[row.id] ?? const <String>[],
    });
  }
  final Map<String, Object?> report = <String, Object?>{
    'format': 'dart-terminal-ghostty-p0-p1-gap-inventory',
    'version': 1,
    'status': 'open-actionable-p1',
    'matrix': <String, Object?>{
      'path': _matrixPath,
      'sha256': _sha256Bytes(utf8.encode(matrixSource)),
      'pinned_ghostty_revision': _matrixRevision,
      'pinned_archive_sha256':
          '3111538f70b1a7fed43646395906724db9ef92eb85d66410c5bce2067ad2b7d2',
    },
    'comparison_scopes': <Map<String, Object?>>[
      <String, Object?>{
        'kind': 'matrix-and-performance',
        'ghostty_revision': _matrixRevision,
        'substitution_allowed': false,
      },
      <String, Object?>{
        'kind': 'supplemental-query-capture',
        'ghostty_revision': _differentialRevision,
        'substitution_allowed': false,
        'status': 'four-cases-unavailable',
      },
    ],
    'evidence_sources': <Map<String, Object?>>[
      for (final String path in _evidencePaths)
        <String, Object?>{
          'path': path,
          'sha256': _sha256(_regularFile(root, path, 4 * 1024 * 1024)),
        },
    ],
    'totals': <String, Object?>{
      'rows': rows.length,
      'priorities': <String, Object?>{
        for (final String priority in <String>['P0', 'P0/P1', 'P1', 'P1/P2'])
          priority: priorities[priority] ?? 0,
      },
      'classifications': <String, Object?>{
        for (final String classification in <String>[
          'accepted',
          'accepted-documented-difference',
          'accepted-external-follow-up',
          'actionable-p1',
        ])
          classification: classifications[classification] ?? 0,
      },
      'actionable_p0': 0,
      'actionable_p1': 5,
      'silent_misbehavior': 0,
    },
    'p0_closure': <String, Object?>{
      'actionable_product_gaps': 0,
      'known_silent_misbehavior': 0,
      'documented_non_mutating_differences': 1,
      'matrix_blockers': 0,
      'external_follow_ups': <String>['intel-native-handoff'],
    },
    'p1_closure': <String, Object?>{
      'completed': <String>[
        'extended-rendition-and-selective-erase',
        'bounded-semantic-ranges',
        'versioned-snapshot-restore-oracle',
      ],
      'remaining_actionable': 5,
    },
    'rows': encodedRows,
    'gaps': <Map<String, Object?>>[for (final _Gap gap in _gaps) gap.toJson()],
  };
  return '${const JsonEncoder.withIndent('  ').convert(report)}\n';
}

List<GhosttyP0P1MatrixRow> parseGhosttyP0P1MatrixSource(String source) {
  _expect(utf8.encode(source).length <= 1024 * 1024, 'matrix exceeds 1 MiB');
  final RegExp revision = RegExp(r'ghostty-org/ghostty@([0-9a-f]{40})');
  final RegExpMatch? firstRevision = revision.firstMatch(source);
  _expect(
    firstRevision?.group(1) == _matrixRevision,
    'matrix Ghostty revision differs',
  );
  final RegExp rowPattern = RegExp(
    r'^\| ([A-Z]+-[0-9]+) \| (.+?) \| (P0|P0/P1|P1|P1/P2) \| ([^|]+?) \| (.+?) \| (.+) \|$',
  );
  final List<GhosttyP0P1MatrixRow> rows = <GhosttyP0P1MatrixRow>[];
  final Set<String> seen = <String>{};
  for (final String line in const LineSplitter().convert(source)) {
    final RegExpMatch? match = rowPattern.firstMatch(line);
    if (match == null) continue;
    final String id = match.group(1)!;
    _expect(seen.add(id), 'duplicate matrix row $id');
    rows.add(
      GhosttyP0P1MatrixRow(
        id: id,
        acceptance: match.group(2)!.trim(),
        priority: match.group(3)!,
        phase: match.group(4)!.trim(),
        pinnedEvidence: match.group(5)!.trim(),
        current: match.group(6)!.trim(),
      ),
    );
  }
  _expect(
    rows.map((row) => row.id).join(',') == _expectedRowIds.join(','),
    'P0/P1 row identity or order differs',
  );
  _expect(
    _classifications.keys.every(seen.contains) &&
        _rowGapIds.keys.every(seen.contains),
    'classification references an absent row',
  );
  return rows;
}

GhosttyP0P1GapInventoryResult validateGhosttyP0P1GapInventorySource(
  String source, {
  required String expectedSource,
}) {
  _expect(utf8.encode(source).length <= 1024 * 1024, 'report exceeds 1 MiB');
  _expect(source == expectedSource, 'gap inventory is stale');
  final Map<String, Object?> report = _jsonSource(source, 'report');
  _expect(
    report['format'] == 'dart-terminal-ghostty-p0-p1-gap-inventory' &&
        report['version'] == 1 &&
        report['status'] == 'open-actionable-p1',
    'report identity or status differs',
  );
  final Map<String, Object?> totals = report['totals']! as Map<String, Object?>;
  final Map<String, Object?> priorities =
      totals['priorities']! as Map<String, Object?>;
  final Map<String, Object?> classifications =
      totals['classifications']! as Map<String, Object?>;
  final Map<String, Object?> p0Closure =
      report['p0_closure']! as Map<String, Object?>;
  final Map<String, Object?> p1Closure =
      report['p1_closure']! as Map<String, Object?>;
  _expect(
    totals['rows'] == 102 &&
        priorities['P0'] == 69 &&
        priorities['P0/P1'] == 6 &&
        priorities['P1'] == 26 &&
        priorities['P1/P2'] == 1 &&
        totals['actionable_p0'] == 0 &&
        totals['actionable_p1'] == 5 &&
        totals['silent_misbehavior'] == 0 &&
        classifications['accepted'] == 92 &&
        classifications['accepted-documented-difference'] == 2 &&
        classifications['accepted-external-follow-up'] == 3 &&
        classifications['actionable-p1'] == 5 &&
        p0Closure['actionable_product_gaps'] == 0 &&
        p0Closure['known_silent_misbehavior'] == 0 &&
        p0Closure['documented_non_mutating_differences'] == 1 &&
        p0Closure['matrix_blockers'] == 0 &&
        (p0Closure['external_follow_ups']! as List<Object?>).single ==
            'intel-native-handoff' &&
        (p1Closure['completed']! as List<Object?>).join(',') ==
            'extended-rendition-and-selective-erase,bounded-semantic-ranges,'
                'versioned-snapshot-restore-oracle' &&
        p1Closure['remaining_actionable'] == 5,
    'reviewed totals differ',
  );
  return const GhosttyP0P1GapInventoryResult();
}

void validateGhosttyP1SemanticRangeClosureSources({
  required String sequenceInventorySource,
  required String semanticRangeSource,
  required String semanticRangeTestSource,
}) {
  final Map<String, Object?> inventory = _jsonSource(
    sequenceInventorySource,
    'sequence inventory',
  );
  final Map<String, Object?> record = (inventory['records']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((row) => row['id'] == 'ghostty:osc:osc-133');
  final String notes = record['notes']! as String;
  _expect(
    record['support'] == 'partial' &&
        record['disposition'] == 'execute' &&
        (record['implementationEvidence']! as List<Object?>).contains(
          'lib/src/terminal_core/terminal_semantic_ranges.dart#bounded-stable-anchor-ranges',
        ) &&
        (record['testEvidence']! as List<Object?>).contains(
          'test/terminal_semantic_prompt_test.dart#bounded-semantic-ranges',
        ) &&
        notes.contains('A/B/C/D/I/L/N/P') &&
        notes.contains('stable logical anchors') &&
        notes.contains('command text are never decoded or retained'),
    'OSC 133 semantic range inventory evidence differs',
  );
  _expect(
    semanticRangeSource.contains('enum TerminalSemanticRangeKind') &&
        semanticRangeSource.contains('class TerminalSemanticRangeSnapshot') &&
        semanticRangeSource.contains('maximumStorageCapacity = 65536') &&
        semanticRangeSource.contains('_resolveDocumentBoundary') &&
        semanticRangeSource.contains('didResetSemanticPrompt'),
    'bounded semantic range implementation contract differs',
  );
  _expect(
    semanticRangeTestSource.contains('_testExactPromptCommandOutputRanges') &&
        semanticRangeTestSource.contains(
          '_testRangesSurviveHistoryAndReflowThenRejectEviction',
        ) &&
        semanticRangeTestSource.contains('_testRangeStorageAndQueryBounds'),
    'semantic range regression evidence differs',
  );
}

void validateGhosttyP1SnapshotRestoreClosureSources({
  required String snapshotFormatterSource,
  required String snapshotRestoreSource,
  required String snapshotRestoreTestSource,
}) {
  _expect(
    snapshotFormatterSource.contains('static const int formatVersion = 4') &&
        snapshotFormatterSource.contains(
          'TerminalSnapshotParserCounters? parserCounters',
        ) &&
        snapshotFormatterSource.contains(
          'parserSink and parserCounters are mutually exclusive',
        ),
    'versioned snapshot formatter restore contract differs',
  );
  _expect(
    snapshotRestoreSource.contains('class TerminalSnapshotRestorer') &&
        snapshotRestoreSource.contains('class TerminalSnapshotRestoreResult') &&
        snapshotRestoreSource.contains(
          'TerminalSnapshotRestoreErrorKind.nonCanonical',
        ) &&
        snapshotRestoreSource.contains('if (canonical != source)') &&
        snapshotRestoreSource.contains('TerminalScreenSet(') &&
        snapshotRestoreSource.contains('TerminalScreen(') &&
        !snapshotRestoreSource.contains("import 'dart:io'"),
    'strict fresh-owner snapshot restore implementation differs',
  );
  _expect(
    snapshotRestoreTestSource.contains(
          '_testStandaloneSnapshotRestoreRoundTrip',
        ) &&
        snapshotRestoreTestSource.contains(
          '_testScreenSetSnapshotRestoreRoundTrip',
        ) &&
        snapshotRestoreTestSource.contains(
          '_testCheckedInSnapshotsRestoreExactly',
        ) &&
        snapshotRestoreTestSource.contains('restored == 8') &&
        snapshotRestoreTestSource.contains(
          '_testSnapshotRestoreRejectsMalformedOrNonCanonicalInput',
        ),
    'snapshot restore regression evidence differs',
  );
}

void validateGhosttyP1ExtendedRenditionClosureSources({
  required String sequenceInventorySource,
  required String implementationManifestSource,
}) {
  final Map<String, Object?> inventory = _jsonSource(
    sequenceInventorySource,
    'sequence inventory',
  );
  final List<Map<String, Object?>> records =
      (inventory['records']! as List<Object?>).cast<Map<String, Object?>>();
  final Map<String, Map<String, Object?>> byId = <String, Map<String, Object?>>{
    for (final Map<String, Object?> record in records)
      record['id']! as String: record,
  };
  for (final MapEntry<String, String> expected in const <String, String>{
    'dec:csi:decsca': 'implemented',
    'dec:csi:decsed': 'partial',
    'dec:csi:decsel': 'implemented',
  }.entries) {
    final Map<String, Object?>? record = byId[expected.key];
    _expect(
      record != null &&
          record['support'] == expected.value &&
          record['disposition'] == 'execute' &&
          (record['implementationEvidence']! as List<Object?>).isNotEmpty &&
          (record['testEvidence']! as List<Object?>).isNotEmpty,
      '${expected.key} closure evidence differs',
    );
  }
  final Map<String, Object?>? sgr = byId['ecma48:csi:sgr'];
  final String sgrNotes = sgr?['notes'] as String? ?? '';
  _expect(
    sgr?['support'] == 'partial' &&
        sgr?['disposition'] == 'execute' &&
        sgrNotes.contains('overline') &&
        sgrNotes.contains('underline colors'),
    'extended SGR closure evidence differs',
  );

  final Map<String, Object?> manifest = _jsonSource(
    implementationManifestSource,
    'implementation manifest',
  );
  final Set<String> selectorKeys = (manifest['selectors']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((Map<String, Object?> selector) => selector['key']! as String)
      .toSet();
  _expect(
    selectorKeys.containsAll(const <String>{
      'csi:-1:1:34:113',
      'csi:63:0:0:74',
      'csi:63:0:0:75',
    }),
    'extended rendition implementation selectors differ',
  );
}

void validateGhosttyP0ClosureSources({
  required String sequenceInventorySource,
  required String applicationAcceptanceSource,
  required String regressionCoverageSource,
}) {
  final Map<String, Object?> inventory = _jsonSource(
    sequenceInventorySource,
    'sequence inventory',
  );
  final List<Map<String, Object?>> hiliteRecords =
      (inventory['records']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .where((row) => row['id'] == 'xterm:mode:xterm-hilite-mouse-tracking')
          .toList(growable: false);
  _expect(hiliteRecords.length == 1, 'mode 1001 inventory owner differs');
  final Map<String, Object?> hiliteRecord = hiliteRecords.single;
  final Map<String, Object?> selector =
      hiliteRecord['selector']! as Map<String, Object?>;
  _expect(
    hiliteRecord['support'] == 'unsupported' &&
        hiliteRecord['disposition'] == 'reject' &&
        selector['kind'] == 'mode' &&
        selector['private'] == true &&
        selector['number'] == 1001 &&
        (hiliteRecord['implementationEvidence']! as List<Object?>).isEmpty &&
        (hiliteRecord['testEvidence']! as List<Object?>).isEmpty,
    'mode 1001 inventory contract differs',
  );

  final Map<String, Object?> application = _jsonSource(
    applicationAcceptanceSource,
    'application acceptance',
  );
  final List<Object?> applicationGaps = application['gaps']! as List<Object?>;
  _expect(applicationGaps.length == 1, 'P0 application gap total differs');
  final Map<String, Object?> gap =
      applicationGaps.single! as Map<String, Object?>;
  _expect(
    gap['id'] == 'hilite-mouse' &&
        gap['disposition'] == 'explicit-unsupported' &&
        gap['impact'] == 'input-events' &&
        (gap['inventory_ids']! as List<Object?>).single ==
            'xterm:mode:xterm-hilite-mouse-tracking' &&
        gap['minimal_hex'] == '1b5b3f313030316c' &&
        (gap['variants']! as List<Object?>).length == 1 &&
        gap['screen_mutation'] == false &&
        gap['matrix_blocker'] == false,
    'mode 1001 application classification differs',
  );

  final Map<String, Object?> regression = _jsonSource(
    regressionCoverageSource,
    'regression coverage',
  );
  final Map<String, Object?> phaseExit =
      regression['phase_exit']! as Map<String, Object?>;
  final List<Object?> ownedGaps =
      regression['owned_application_gaps']! as List<Object?>;
  _expect(
    phaseExit['known_p0_silent_corruption'] == 0 &&
        phaseExit['blocking_failures'] == 0 &&
        phaseExit['unsupported_sequences_classified'] == true &&
        ownedGaps.length == 1 &&
        (ownedGaps.single! as Map<String, Object?>)['id'] == 'hilite-mouse' &&
        (ownedGaps.single! as Map<String, Object?>)['screen_mutation'] ==
            false &&
        (ownedGaps.single! as Map<String, Object?>)['matrix_blocker'] == false,
    'P0 regression closure differs',
  );
}

void _validatePinnedEvidence(Directory root, String matrixSource) {
  _expect(
    matrixSource.contains(
      '3111538f70b1a7fed43646395906724db9ef92eb85d66410c5bce2067ad2b7d2',
    ),
    'matrix pinned archive identity differs',
  );
  final String pins = _regularFile(
    root,
    'docs/phase6/specification-source-pins.md',
    1024 * 1024,
  ).readAsStringSync();
  _expect(
    RegExp('^\\| `ghostty-d4d8f62-', multiLine: true).allMatches(pins).length ==
            9 &&
        pins.contains(_matrixRevision),
    'primary Ghostty source pins differ',
  );
  final Map<String, Object?> performance = _jsonFile(
    _regularFile(
      root,
      'benchmark/evidence/ghostty-performance-comparator-macos-arm64-m1.json',
      1024 * 1024,
    ),
  );
  final Map<String, Object?> provenance =
      performance['provenance']! as Map<String, Object?>;
  _expect(
    provenance['product'] == 'ghostty' &&
        provenance['revision'] == _matrixRevision &&
        provenance['project_local_patches'] == false,
    'performance comparator does not use the matrix pin',
  );
  final Map<String, Object?> backends = _jsonFile(
    _regularFile(root, 'compatibility/differential_backends.json', 1024 * 1024),
  );
  final Map<String, Object?> ghosttyBackend =
      (backends['backends']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((row) => row['product'] == 'ghostty');
  _expect(
    ghosttyBackend['implementation_revision'] == _differentialRevision,
    'supplemental Ghostty differential pin differs',
  );
  final Map<String, Object?> differential = _jsonFile(
    _regularFile(
      root,
      'compatibility/differential_acceptance_report.json',
      1024 * 1024,
    ),
  );
  final int unavailable = (differential['results']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .where(
        (row) =>
            row['profile_id'] == 'ghostty-tip-492300c-macos-arm64' &&
            row['classification'] == 'unavailable' &&
            row['reason'] == 'macos-activation-unavailable',
      )
      .length;
  _expect(unavailable == 4, 'supplemental Ghostty unavailability differs');
}

Map<String, Object?> _jsonFile(File file) =>
    _jsonSource(file.readAsStringSync(), file.path);

Map<String, Object?> _jsonSource(String source, String context) {
  final Object? decoded = jsonDecode(source);
  _expect(decoded is Map<String, Object?>, '$context is not an object');
  return decoded! as Map<String, Object?>;
}

File _regularFile(Directory root, String path, int maximumBytes) {
  final File file = File.fromUri(root.uri.resolve(path));
  final FileStat stat = file.statSync();
  _expect(
    stat.type == FileSystemEntityType.file && stat.size <= maximumBytes,
    '$path is absent, non-regular, or too large',
  );
  return file;
}

String _sha256(File file) => _sha256Bytes(file.readAsBytesSync());

String _sha256Bytes(List<int> bytes) => terminalDifferentialSha256(bytes);

void _expect(bool condition, String message) {
  if (!condition) throw GhosttyP0P1GapInventoryException(message);
}

final class GhosttyP0P1MatrixRow {
  const GhosttyP0P1MatrixRow({
    required this.id,
    required this.acceptance,
    required this.priority,
    required this.phase,
    required this.pinnedEvidence,
    required this.current,
  });

  final String id;
  final String acceptance;
  final String priority;
  final String phase;
  final String pinnedEvidence;
  final String current;
}

final class _Gap {
  const _Gap({
    required this.id,
    required this.kind,
    required this.priority,
    required this.rowIds,
    required this.owner,
    required this.productActionable,
    required this.reason,
  });

  final String id;
  final String kind;
  final String priority;
  final List<String> rowIds;
  final String owner;
  final bool productActionable;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'priority': priority,
    'row_ids': rowIds,
    'owner': owner,
    'product_actionable': productActionable,
    'silent_misbehavior': false,
    'reason': reason,
  };
}

void main(List<String> arguments) {
  try {
    _expect(arguments.length == 1, 'expected --generate or --check');
    final String generated = generateGhosttyP0P1GapInventory();
    if (arguments.single == '--generate') {
      File(ghosttyP0P1GapInventoryPath).writeAsStringSync(generated);
      stdout.writeln(
        'GHOSTTY_P0_P1_GAP_INVENTORY_GENERATED '
        'path=$ghosttyP0P1GapInventoryPath',
      );
      return;
    }
    _expect(arguments.single == '--check', 'expected --generate or --check');
    final File report = File(ghosttyP0P1GapInventoryPath);
    _expect(report.existsSync(), 'gap inventory is absent');
    final GhosttyP0P1GapInventoryResult result =
        validateGhosttyP0P1GapInventorySource(
          report.readAsStringSync(),
          expectedSource: generated,
        );
    stdout.writeln(result.machineLine());
  } on GhosttyP0P1GapInventoryException catch (error) {
    stderr.writeln('GHOSTTY_P0_P1_GAP_INVENTORY_FAIL $error');
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln(
      'GHOSTTY_P0_P1_GAP_INVENTORY_FAIL filesystem operation failed',
    );
    exitCode = 1;
  } on FormatException {
    stderr.writeln('GHOSTTY_P0_P1_GAP_INVENTORY_FAIL invalid JSON');
    exitCode = 1;
  }
}
