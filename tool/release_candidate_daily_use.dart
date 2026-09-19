import 'dart:convert';
import 'dart:io';

import 'ghostty_p0_p1_gap_inventory.dart';
import 'terminal_application_acceptance.dart';
import 'terminal_application_matrix.dart';
import 'terminal_differential_sha256.dart';

const String releaseCandidateDailyUseMatrixPath =
    'compatibility/release_candidate_daily_use_matrix.json';

const List<String> _programIds = <String>[
  'emacs',
  'fzf',
  'lazygit',
  'mosh',
  'ncurses',
  'neovim',
  'ssh',
  'tmux',
];

const List<Map<String, Object>> _gateCatalog = <Map<String, Object>>[
  <String, Object>{
    'id': 'test',
    'expected_marker': 'dart_terminal tests passed',
    'evidence_kind': 'ordinary',
  },
  <String, Object>{
    'id': 'terminal-application-acceptance-check',
    'expected_marker': 'TERMINAL_APPLICATION_ACCEPTANCE_PASS',
    'evidence_kind': 'checked-in-replay',
  },
  <String, Object>{
    'id': 'terminal-localization-check',
    'expected_marker': 'TERMINAL_LOCALIZATION_AUDIT_PASS',
    'evidence_kind': 'ordinary',
  },
  <String, Object>{
    'id': 'runtime-integration',
    'expected_marker': 'RUNTIME_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-terminal-display-integration',
    'expected_marker': 'RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-native-hierarchy-integration',
    'expected_marker': 'RUNTIME_NATIVE_HIERARCHY_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-bounded-reliability-integration',
    'expected_marker': 'RUNTIME_BOUNDED_RELIABILITY_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-user-actions-integration',
    'expected_marker': 'RUNTIME_USER_ACTIONS_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-applescript-integration',
    'expected_marker': 'RUNTIME_APPLESCRIPT_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-system-automation-integration',
    'expected_marker': 'RUNTIME_SYSTEM_AUTOMATION_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-native-content-integration',
    'expected_marker': 'RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-quick-terminal-integration',
    'expected_marker': 'RUNTIME_QUICK_TERMINAL_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-secure-keyboard-entry-integration',
    'expected_marker': 'RUNTIME_SECURE_KEYBOARD_ENTRY_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-diagnostics-integration',
    'expected_marker': 'RUNTIME_DIAGNOSTICS_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-configuration-integration',
    'expected_marker': 'RUNTIME_CONFIGURATION_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-theme-integration',
    'expected_marker': 'RUNTIME_THEME_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-shell-integration',
    'expected_marker': 'RUNTIME_SHELL_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-desktop-signals-integration',
    'expected_marker': 'RUNTIME_DESKTOP_SIGNALS_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-osc52-integration',
    'expected_marker': 'RUNTIME_OSC52_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-restoration-integration',
    'expected_marker': 'RUNTIME_RESTORATION_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-clipboard-integration',
    'expected_marker': 'RUNTIME_CLIPBOARD_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-lifecycle-integration',
    'expected_marker': 'RUNTIME_LIFECYCLE_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-traffic-integration',
    'expected_marker': 'RUNTIME_TRAFFIC_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-resource-integration',
    'expected_marker': 'RUNTIME_RESOURCE_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'runtime-shutdown-fault-integration',
    'expected_marker': 'RUNTIME_SHUTDOWN_FAULT_INTEGRATION_PASS',
    'evidence_kind': 'two-mode-product',
  },
  <String, Object>{
    'id': 'release-aot-distribution-verify',
    'expected_marker': 'DART_ONLY_BUNDLE_AUDIT_PASS',
    'evidence_kind': 'three-architecture-release',
  },
  <String, Object>{
    'id': 'product-performance-regression-gate',
    'expected_marker': 'PRODUCT_PERFORMANCE_REGRESSION_PASS',
    'evidence_kind': 'release-aot-measured',
  },
  <String, Object>{
    'id': 'product-parser-properties',
    'expected_marker': 'TERMINAL_PROPERTY_FUZZ_PASS',
    'evidence_kind': 'bounded-deterministic',
  },
  <String, Object>{
    'id': 'product-native-sanitizer',
    'expected_marker': 'PRODUCT_NATIVE_SANITIZER_PASS',
    'evidence_kind': 'native-host-sanitized',
  },
  <String, Object>{
    'id': 'product-fault-injection',
    'expected_marker': 'PRODUCT_FAULT_INJECTION_PASS',
    'evidence_kind': 'bounded-deterministic',
  },
  <String, Object>{
    'id': 'ghostty-p0-p1-gap-closure',
    'expected_marker': 'GHOSTTY_P0_P1_GAP_CLOSURE_PASS',
    'evidence_kind': 'ordinary-and-two-mode-product',
  },
];

const List<Map<String, Object>> _workflows = <Map<String, Object>>[
  <String, Object>{
    'id': 'startup-shell',
    'gate_ids': <String>[
      'test',
      'runtime-integration',
      'runtime-terminal-display-integration',
      'runtime-shell-integration',
    ],
  },
  <String, Object>{
    'id': 'input-editor',
    'gate_ids': <String>[
      'terminal-application-acceptance-check',
      'runtime-terminal-display-integration',
      'runtime-clipboard-integration',
    ],
  },
  <String, Object>{
    'id': 'multiplexer-remote',
    'gate_ids': <String>[
      'terminal-application-acceptance-check',
      'runtime-native-hierarchy-integration',
    ],
  },
  <String, Object>{
    'id': 'hierarchy-content',
    'gate_ids': <String>[
      'runtime-native-hierarchy-integration',
      'runtime-native-content-integration',
      'runtime-quick-terminal-integration',
      'runtime-secure-keyboard-entry-integration',
      'runtime-diagnostics-integration',
    ],
  },
  <String, Object>{
    'id': 'configuration-appearance',
    'gate_ids': <String>[
      'terminal-localization-check',
      'runtime-configuration-integration',
      'runtime-theme-integration',
    ],
  },
  <String, Object>{
    'id': 'automation-integration',
    'gate_ids': <String>[
      'runtime-user-actions-integration',
      'runtime-applescript-integration',
      'runtime-system-automation-integration',
      'runtime-desktop-signals-integration',
      'runtime-osc52-integration',
    ],
  },
  <String, Object>{
    'id': 'lifecycle-recovery-resource',
    'gate_ids': <String>[
      'runtime-bounded-reliability-integration',
      'runtime-restoration-integration',
      'runtime-lifecycle-integration',
      'runtime-traffic-integration',
      'runtime-resource-integration',
      'runtime-shutdown-fault-integration',
    ],
  },
  <String, Object>{
    'id': 'distribution-performance-security-parity',
    'gate_ids': <String>[
      'release-aot-distribution-verify',
      'product-performance-regression-gate',
      'product-parser-properties',
      'product-native-sanitizer',
      'product-fault-injection',
      'ghostty-p0-p1-gap-closure',
    ],
  },
];

const List<String> _evidencePaths = <String>[
  'Makefile',
  'test/corpus/applications/matrix_v1.json',
  'compatibility/application_matrix_acceptance.json',
  'compatibility/ghostty_p0_p1_gap_inventory.json',
  'benchmark/evidence/product-performance-regression-macos-arm64-m1.json',
  'benchmark/evidence/product-relative-performance-macos-arm64-m1.json',
  'test/corpus/appkit/phase7_acceptance_v1.json',
  'test/corpus/fuzz/phase11_v1.json',
  'resources/DartTerminal.entitlements',
  'tool/dart_only_bundle_audit.dart',
  'tool/terminal_distribution_policy.dart',
  'tool/product_performance_regression_gate.dart',
  'tool/terminal_application_acceptance.dart',
  'tool/terminal_localization_audit.dart',
  'tool/native_sanitizer_gate.dart',
  'tool/runtime_integration_smoke.dart',
  'test/terminal_property_fuzz_test.dart',
  'test/run_tests.dart',
  'tool/release_candidate_daily_use.dart',
  'test/release_candidate_daily_use_test.dart',
];

final class ReleaseCandidateDailyUseException implements Exception {
  const ReleaseCandidateDailyUseException(this.message);

  final String message;

  @override
  String toString() => 'ReleaseCandidateDailyUseException: $message';
}

final class ReleaseCandidateDailyUseResult {
  const ReleaseCandidateDailyUseResult();

  int get programs => _programIds.length;
  int get cleanPrograms => 7;
  int get documentedProgramGaps => 1;
  int get workflows => _workflows.length;
  int get gates => _gateCatalog.length;
  int get knownLimitations => 5;

  String machineLine() =>
      'RELEASE_CANDIDATE_DAILY_USE_MATRIX_PASS programs=$programs '
      'clean=$cleanPrograms documented_program_gaps=$documentedProgramGaps '
      'workflows=$workflows gates=$gates known_limitations=$knownLimitations '
      'release_blockers=0 duration_claim=false notarization_claim=false '
      'intel_native_claim=false';
}

String generateReleaseCandidateDailyUseMatrix({Directory? repositoryRoot}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final TerminalApplicationAcceptanceResult applicationResult =
      runTerminalApplicationAcceptanceChecks(repositoryRoot: root);
  _expect(
    applicationResult.acceptedCells == 8 &&
        applicationResult.cleanAgreements == 7 &&
        applicationResult.documentedGapCells == 1 &&
        applicationResult.gaps == 1,
    'reviewed application result differs',
  );
  final TerminalApplicationMatrixManifest applicationMatrix =
      TerminalApplicationMatrixManifest.load(
        _regularFile(root, 'test/corpus/applications/matrix_v1.json'),
      );
  final Map<String, TerminalApplicationScenario> scenarioById =
      <String, TerminalApplicationScenario>{
        for (final TerminalApplicationScenario scenario
            in applicationMatrix.scenarios)
          scenario.id: scenario,
      };
  _expect(
    applicationMatrix.applications
            .map((TerminalApplicationDefinition value) => value.id)
            .join(',') ==
        _programIds.join(','),
    'reviewed program identity differs',
  );

  final String ghosttySource = _regularFile(
    root,
    ghosttyP0P1GapInventoryPath,
  ).readAsStringSync();
  final GhosttyP0P1GapInventoryResult ghosttyResult =
      validateGhosttyP0P1GapInventorySource(
        ghosttySource,
        expectedSource: generateGhosttyP0P1GapInventory(repositoryRoot: root),
      );
  _expect(
    ghosttyResult.rows == 102 &&
        ghosttyResult.accepted == 97 &&
        ghosttyResult.actionableP0 == 0 &&
        ghosttyResult.actionableP1 == 0,
    'pinned P0/P1 closure differs',
  );
  final Map<String, Object?> ghostty = _json(ghosttySource, 'ghostty');
  final Map<String, Object?> ghosttyTotals = _object(
    ghostty['totals'],
    'ghostty.totals',
  );
  _expect(
    ghosttyTotals['silent_misbehavior'] == 0,
    'pinned closure retains silent misbehavior',
  );

  final Map<String, Object?> performance = _json(
    _regularFile(
      root,
      'benchmark/evidence/product-performance-regression-macos-arm64-m1.json',
    ).readAsStringSync(),
    'performance',
  );
  _validatePerformance(performance);
  final Map<String, Object?> phase7 = _json(
    _regularFile(
      root,
      'test/corpus/appkit/phase7_acceptance_v1.json',
    ).readAsStringSync(),
    'phase7',
  );
  _expect(
    phase7['format'] == 'dart-terminal-phase7-appkit-acceptance' &&
        phase7['version'] == 1 &&
        phase7['status'] == 'covered' &&
        _array(phase7['criteria'], 'phase7.criteria').length == 5,
    'AppKit acceptance evidence differs',
  );
  final Map<String, Object?> fuzz = _json(
    _regularFile(root, 'test/corpus/fuzz/phase11_v1.json').readAsStringSync(),
    'fuzz',
  );
  _expect(
    fuzz['format'] == 'dart-terminal-product-fuzz-seeds' &&
        fuzz['version'] == 1 &&
        _array(fuzz['seeds'], 'fuzz.seeds').length == 5,
    'Phase 11 fuzz evidence differs',
  );
  final String entitlements = _regularFile(
    root,
    'resources/DartTerminal.entitlements',
  ).readAsStringSync();
  _expect(
    entitlements ==
        '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n'
            '<dict/>\n'
            '</plist>\n',
    'release entitlements are not the exact empty plist',
  );

  final String makefile = _regularFile(root, 'Makefile').readAsStringSync();
  final String markerSources = <String>[
    makefile,
    for (final String path in _evidencePaths.where(
      (String path) =>
          path.endsWith('.dart') &&
          path != 'tool/release_candidate_daily_use.dart' &&
          path != 'test/release_candidate_daily_use_test.dart',
    ))
      _regularFile(root, path).readAsStringSync(),
  ].join('\n');
  for (final Map<String, Object> gate in _gateCatalog) {
    final String id = gate['id']! as String;
    final String marker = gate['expected_marker']! as String;
    _expect(
      RegExp('^${RegExp.escape(id)}:', multiLine: true).hasMatch(makefile),
      'Make target $id is absent',
    );
    final String markerStem = marker.endsWith('_PASS')
        ? marker.substring(0, marker.length - 4)
        : marker;
    _expect(
      markerSources.contains(marker) || markerSources.contains(markerStem),
      'gate marker $marker is absent',
    );
  }

  final Map<String, Object?> applicationAcceptance = _json(
    _regularFile(
      root,
      'compatibility/application_matrix_acceptance.json',
    ).readAsStringSync(),
    'application acceptance',
  );
  final List<Map<String, Object?>> programs = <Map<String, Object?>>[];
  for (final Object? value in _array(
    applicationAcceptance['cells'],
    'application acceptance.cells',
  )) {
    final Map<String, Object?> cell = _object(value, 'application cell');
    final String scenarioId = cell['scenario_id']! as String;
    final TerminalApplicationScenario? scenario = scenarioById[scenarioId];
    _expect(scenario != null, 'application scenario $scenarioId is absent');
    programs.add(<String, Object?>{
      'id': cell['application_id'],
      'scenario_id': scenarioId,
      'capture_kind': 'checked-in-replay',
      'classification': cell['classification'],
      'accepted': cell['accepted'],
      'gap_ids': cell['gap_ids'],
      'deadline_ms': scenario!.deadlineMs,
      'maximum_output_bytes': scenario.maximumOutputBytes,
    });
  }

  final List<Map<String, Object?>> limitations = <Map<String, Object?>>[];
  for (final Object? value in _array(ghostty['gaps'], 'ghostty.gaps')) {
    final Map<String, Object?> gap = _object(value, 'ghostty gap');
    _expect(
      gap['product_actionable'] == false && gap['silent_misbehavior'] == false,
      'a known limitation is actionable or silent',
    );
    limitations.add(<String, Object?>{
      'id': gap['id'],
      'kind': gap['kind'],
      'owner': gap['owner'],
      'release_blocker': false,
      'claimed_as_pass': false,
    });
  }

  final Map<String, Object?> report = <String, Object?>{
    'format': 'dart-terminal-release-candidate-daily-use-matrix',
    'version': 1,
    'status': 'bounded-release-candidate-ready',
    'baseline': <String, Object?>{
      'os': 'macos',
      'architecture': 'arm64',
      'hardware_class': 'apple-m1',
      'runtime_modes': <String>['developer-jit', 'release-aot'],
    },
    'claims': <String, Object?>{
      'bounded_automation': true,
      'human_daily_use_days': 0,
      'physical_sleep': false,
      'physical_display_change': false,
      'os_memory_pressure': false,
      'developer_id_signing': false,
      'apple_notarization': false,
      'intel_native_execution': false,
      'fresh_external_program_launch': false,
    },
    'release_blockers': <String, Object?>{
      'blocker_bugs': 0,
      'crashes': 0,
      'data_loss_bugs': 0,
      'security_bugs': 0,
      'silent_misbehavior': 0,
      'actionable_p0': 0,
      'actionable_p1': 0,
    },
    'totals': <String, Object?>{
      'programs': programs.length,
      'clean_programs': applicationResult.cleanAgreements,
      'documented_program_gaps': applicationResult.documentedGapCells,
      'workflows': _workflows.length,
      'gates': _gateCatalog.length,
      'known_limitations': limitations.length,
      'evidence_sources': _evidencePaths.length,
    },
    'evidence_sources': <Map<String, Object?>>[
      for (final String path in _evidencePaths)
        <String, Object?>{
          'path': path,
          'sha256': _sha256(_regularFile(root, path)),
        },
    ],
    'programs': programs,
    'workflows': _workflows,
    'gate_catalog': _gateCatalog,
    'known_limitations': limitations,
  };
  return '${const JsonEncoder.withIndent('  ').convert(report)}\n';
}

ReleaseCandidateDailyUseResult validateReleaseCandidateDailyUseMatrixSource(
  String source, {
  required String expectedSource,
}) {
  _expect(utf8.encode(source).length <= 1024 * 1024, 'matrix exceeds 1 MiB');
  _expect(source == expectedSource, 'daily-use matrix is stale');
  final Map<String, Object?> report = _json(source, 'matrix');
  _keys(report, const <String>{
    'format',
    'version',
    'status',
    'baseline',
    'claims',
    'release_blockers',
    'totals',
    'evidence_sources',
    'programs',
    'workflows',
    'gate_catalog',
    'known_limitations',
  }, 'matrix');
  _expect(
    report['format'] == 'dart-terminal-release-candidate-daily-use-matrix' &&
        report['version'] == 1 &&
        report['status'] == 'bounded-release-candidate-ready',
    'matrix identity or status differs',
  );
  final Map<String, Object?> baseline = _object(report['baseline'], 'baseline');
  _keys(baseline, const <String>{
    'os',
    'architecture',
    'hardware_class',
    'runtime_modes',
  }, 'baseline');
  _expect(
    baseline['os'] == 'macos' &&
        baseline['architecture'] == 'arm64' &&
        baseline['hardware_class'] == 'apple-m1' &&
        _strings(baseline['runtime_modes'], 'runtime_modes').join(',') ==
            'developer-jit,release-aot',
    'baseline differs',
  );
  final Map<String, Object?> claims = _object(report['claims'], 'claims');
  _keys(claims, const <String>{
    'bounded_automation',
    'human_daily_use_days',
    'physical_sleep',
    'physical_display_change',
    'os_memory_pressure',
    'developer_id_signing',
    'apple_notarization',
    'intel_native_execution',
    'fresh_external_program_launch',
  }, 'claims');
  _expect(
    claims['bounded_automation'] == true &&
        claims['human_daily_use_days'] == 0 &&
        claims.entries
            .where(
              (MapEntry<String, Object?> entry) =>
                  entry.key != 'bounded_automation' &&
                  entry.key != 'human_daily_use_days',
            )
            .every((MapEntry<String, Object?> entry) => entry.value == false),
    'unsupported release claim is present',
  );
  final Map<String, Object?> blockers = _object(
    report['release_blockers'],
    'release_blockers',
  );
  _keys(blockers, const <String>{
    'blocker_bugs',
    'crashes',
    'data_loss_bugs',
    'security_bugs',
    'silent_misbehavior',
    'actionable_p0',
    'actionable_p1',
  }, 'release_blockers');
  _expect(
    blockers.values.every((Object? value) => value == 0),
    'release blocker is nonzero',
  );

  final List<Object?> programValues = _array(report['programs'], 'programs');
  _expect(programValues.length == _programIds.length, 'program count differs');
  final List<String> observedProgramIds = <String>[];
  var cleanPrograms = 0;
  var documentedProgramGaps = 0;
  for (final Object? value in programValues) {
    final Map<String, Object?> program = _object(value, 'program');
    _keys(program, const <String>{
      'id',
      'scenario_id',
      'capture_kind',
      'classification',
      'accepted',
      'gap_ids',
      'deadline_ms',
      'maximum_output_bytes',
    }, 'program');
    final String id = _text(program['id'], 'program.id');
    observedProgramIds.add(id);
    final List<String> gaps = _strings(program['gap_ids'], 'program.gap_ids');
    _expect(
      program['capture_kind'] == 'checked-in-replay' &&
          program['accepted'] == true &&
          program['deadline_ms'] is int &&
          (program['deadline_ms']! as int) > 0 &&
          (program['deadline_ms']! as int) <= 30000 &&
          program['maximum_output_bytes'] is int &&
          (program['maximum_output_bytes']! as int) > 0 &&
          (program['maximum_output_bytes']! as int) <= 1024 * 1024,
      'program evidence or bound differs',
    );
    if (id == 'mosh') {
      _expect(
        program['classification'] == 'documented-gap' &&
            gaps.join(',') == 'hilite-mouse',
        'mosh limitation differs',
      );
      documentedProgramGaps++;
    } else {
      _expect(
        program['classification'] == 'clean-agreement' && gaps.isEmpty,
        '$id is not a clean program agreement',
      );
      cleanPrograms++;
    }
  }
  _expect(
    observedProgramIds.join(',') == _programIds.join(','),
    'program identity or order differs',
  );
  _expect(
    _canonical(report['workflows']) == _canonical(_workflows),
    'workflow coverage differs',
  );
  _expect(
    _canonical(report['gate_catalog']) == _canonical(_gateCatalog),
    'gate catalog differs',
  );

  final List<Object?> limitations = _array(
    report['known_limitations'],
    'known_limitations',
  );
  const List<String> limitationIds = <String>[
    'hilite-mouse',
    'ghostty-differential-activation',
    'physical-duration-reliability',
    'intel-native-handoff',
    'clean-machine-distribution-acceptance',
  ];
  _expect(
    limitations.length == limitationIds.length,
    'limitation count differs',
  );
  for (var index = 0; index < limitations.length; index++) {
    final Map<String, Object?> limitation = _object(
      limitations[index],
      'known limitation',
    );
    _keys(limitation, const <String>{
      'id',
      'kind',
      'owner',
      'release_blocker',
      'claimed_as_pass',
    }, 'known limitation');
    _expect(
      limitation['id'] == limitationIds[index] &&
          limitation['kind'] is String &&
          limitation['owner'] is String &&
          limitation['release_blocker'] == false &&
          limitation['claimed_as_pass'] == false,
      'known limitation differs',
    );
  }

  final List<Object?> evidence = _array(
    report['evidence_sources'],
    'evidence_sources',
  );
  _expect(evidence.length == _evidencePaths.length, 'evidence count differs');
  for (var index = 0; index < evidence.length; index++) {
    final Map<String, Object?> entry = _object(evidence[index], 'evidence');
    _keys(entry, const <String>{'path', 'sha256'}, 'evidence');
    _expect(
      entry['path'] == _evidencePaths[index] && _isSha256(entry['sha256']),
      'evidence identity differs',
    );
  }
  final Map<String, Object?> totals = _object(report['totals'], 'totals');
  _keys(totals, const <String>{
    'programs',
    'clean_programs',
    'documented_program_gaps',
    'workflows',
    'gates',
    'known_limitations',
    'evidence_sources',
  }, 'totals');
  _expect(
    totals['programs'] == _programIds.length &&
        totals['clean_programs'] == cleanPrograms &&
        cleanPrograms == 7 &&
        totals['documented_program_gaps'] == documentedProgramGaps &&
        documentedProgramGaps == 1 &&
        totals['workflows'] == _workflows.length &&
        totals['gates'] == _gateCatalog.length &&
        totals['known_limitations'] == limitations.length &&
        totals['evidence_sources'] == _evidencePaths.length,
    'reviewed totals differ',
  );
  return const ReleaseCandidateDailyUseResult();
}

void _validatePerformance(Map<String, Object?> performance) {
  _expect(
    performance['format'] ==
            'dart-terminal-product-performance-regression-result' &&
        performance['version'] == 1 &&
        performance['status'] == 'pass',
    'performance report identity differs',
  );
  final Map<String, Object?> environment = _object(
    performance['environment'],
    'performance.environment',
  );
  final Map<String, Object?> product = _object(
    performance['product'],
    'performance.product',
  );
  final Map<String, Object?> gates = _object(
    performance['gates'],
    'performance.gates',
  );
  _expect(
    environment['os'] == 'macos' &&
        environment['abi'] == 'macos_arm64' &&
        environment['build_mode'] == 'release-aot' &&
        product['fairness'] == true &&
        gates['product_micro'] == true &&
        gates['ordinary_product'] == true &&
        gates['cross_pane_fairness'] == true &&
        gates['passed'] == true &&
        _array(gates['relative'], 'performance.gates.relative').every(
          (Object? value) =>
              _object(value, 'relative performance gate')['passed'] == true,
        ),
    'performance acceptance differs',
  );
}

Map<String, Object?> _json(String source, String context) {
  final Object? value;
  try {
    value = jsonDecode(source);
  } on FormatException catch (error) {
    throw ReleaseCandidateDailyUseException('$context is invalid JSON: $error');
  }
  return _object(value, context);
}

Map<String, Object?> _object(Object? value, String context) {
  _expect(value is Map<String, Object?>, '$context is not an object');
  return value! as Map<String, Object?>;
}

List<Object?> _array(Object? value, String context) {
  _expect(value is List<Object?>, '$context is not an array');
  return value! as List<Object?>;
}

List<String> _strings(Object? value, String context) {
  final List<Object?> values = _array(value, context);
  _expect(
    values.every((Object? item) => item is String),
    '$context is not text',
  );
  return values.cast<String>();
}

String _text(Object? value, String context) {
  _expect(value is String && value.isNotEmpty, '$context is not text');
  return value! as String;
}

void _keys(Map<String, Object?> value, Set<String> expected, String context) {
  _expect(
    value.keys.toSet().difference(expected).isEmpty &&
        expected.difference(value.keys.toSet()).isEmpty,
    '$context keys differ',
  );
}

File _regularFile(Directory root, String path) {
  final File file = File.fromUri(root.uri.resolve(path));
  final FileStat stat = file.statSync();
  _expect(
    stat.type == FileSystemEntityType.file &&
        stat.size > 0 &&
        stat.size <= 4 * 1024 * 1024,
    '$path is absent, non-regular, empty, or over 4 MiB',
  );
  return file;
}

String _sha256(File file) => terminalDifferentialSha256(file.readAsBytesSync());

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _canonical(Object? value) => jsonEncode(value);

void _expect(bool condition, String message) {
  if (!condition) throw ReleaseCandidateDailyUseException(message);
}

void main(List<String> arguments) {
  try {
    _expect(arguments.length == 1, 'expected --generate or --check');
    final String generated = generateReleaseCandidateDailyUseMatrix();
    if (arguments.single == '--generate') {
      File(releaseCandidateDailyUseMatrixPath).writeAsStringSync(generated);
      stdout.writeln(
        'RELEASE_CANDIDATE_DAILY_USE_MATRIX_GENERATED '
        'path=$releaseCandidateDailyUseMatrixPath',
      );
      return;
    }
    _expect(arguments.single == '--check', 'expected --generate or --check');
    final File report = File(releaseCandidateDailyUseMatrixPath);
    _expect(report.existsSync(), 'daily-use matrix is absent');
    final ReleaseCandidateDailyUseResult result =
        validateReleaseCandidateDailyUseMatrixSource(
          report.readAsStringSync(),
          expectedSource: generated,
        );
    stdout.writeln(result.machineLine());
  } on ReleaseCandidateDailyUseException catch (error) {
    stderr.writeln('RELEASE_CANDIDATE_DAILY_USE_MATRIX_FAIL $error');
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln(
      'RELEASE_CANDIDATE_DAILY_USE_MATRIX_FAIL filesystem operation failed',
    );
    exitCode = 1;
  } on FormatException {
    stderr.writeln('RELEASE_CANDIDATE_DAILY_USE_MATRIX_FAIL invalid input');
    exitCode = 1;
  }
}
