import 'dart:convert';
import 'dart:io';

import 'terminal_differential_sha256.dart';

const String phase7AppKitAcceptancePath =
    'test/corpus/appkit/phase7_acceptance_v1.json';

final class Phase7AppKitAcceptanceException implements Exception {
  const Phase7AppKitAcceptanceException(this.message);

  final String message;

  @override
  String toString() => 'Phase7AppKitAcceptanceException: $message';
}

final class Phase7AppKitAcceptanceResult {
  const Phase7AppKitAcceptanceResult({
    required this.criteria,
    required this.sourceReferences,
    required this.unitTests,
    required this.integrationTests,
    required this.uiAssertions,
  });

  final int criteria;
  final int sourceReferences;
  final int unitTests;
  final int integrationTests;
  final int uiAssertions;

  String machineLine() =>
      'PHASE7_APPKIT_ACCEPTANCE_PASS criteria=$criteria '
      'source_refs=$sourceReferences unit_tests=$unitTests '
      'integration_tests=$integrationTests ui_assertions=$uiAssertions';
}

const List<_CriterionRequirement> _requirements = <_CriterionRequirement>[
  _CriterionRequirement(
    id: 'multi-window-tab-pane-restoration',
    summary:
        'multiple windows, tabs, and four-pane graphs repeat with fresh owners',
    sources: <_SourceRequirement>[
      _SourceRequirement('lib/src/terminal_application_state.dart', <String>[
        'final class TerminalApplicationState',
      ]),
      _SourceRequirement('lib/src/terminal_restoration.dart', <String>[
        'abstract final class TerminalApplicationRestorationCapture',
        'abstract final class TerminalApplicationRestorer',
      ]),
      _SourceRequirement('lib/src/terminal_native_hierarchy.dart', <String>[
        'final class TerminalNativeHierarchyAdapter',
      ]),
    ],
    unitTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_application_state_test.dart',
        'runTerminalApplicationStateTests',
      ),
      _TestRequirement(
        'test/terminal_restoration_test.dart',
        'runTerminalRestorationTests',
      ),
    ],
    integrationTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_native_hierarchy_test.dart',
        'runTerminalNativeHierarchyTests',
      ),
    ],
    uiAssertions: <_UiRequirement>[
      _UiRequirement(
        suite: 'restoration',
        applicationMarker: 'TERMINAL_RESTORATION_TEST',
        driverMarker: 'RUNTIME_RESTORATION_INTEGRATION_PASS',
      ),
    ],
  ),
  _CriterionRequirement(
    id: 'focused-input-and-menu-isolation',
    summary:
        'focus presentation, raw key, IME, and menu shortcuts remain isolated',
    sources: <_SourceRequirement>[
      _SourceRequirement('lib/src/terminal_application.dart', <String>[
        'TerminalTextInputEventRouter(',
        'TerminalAppKitMenuProjection.install(',
        'synchronizePaneFocusPresentation()',
      ]),
      _SourceRequirement(
        'lib/src/terminal_renderer/terminal_screen_metal_compositor.dart',
        <String>[
          'inactivePaneBackgroundBrightness',
          'inactivePaneScrimRgb',
          'inactivePaneScrimOpacity',
        ],
      ),
      _SourceRequirement(
        'lib/src/terminal_input/terminal_text_input_event_router.dart',
        <String>['final class TerminalTextInputEventRouter'],
      ),
      _SourceRequirement('lib/src/terminal_action_menu.dart', <String>[
        'final class TerminalAppKitMenuProjection',
      ]),
      _SourceRequirement(
        'lib/src/terminal_product_hierarchy_actions.dart',
        <String>['final class TerminalProductHierarchyActionCoordinator'],
      ),
    ],
    unitTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_appkit_key_adapter_test.dart',
        'runTerminalAppKitKeyAdapterTests',
      ),
      _TestRequirement(
        'test/terminal_text_input_event_router_test.dart',
        'runTerminalTextInputEventRouterTests',
      ),
      _TestRequirement(
        'test/terminal_action_menu_test.dart',
        'runTerminalActionMenuTests',
      ),
      _TestRequirement(
        'test/terminal_product_hierarchy_actions_test.dart',
        'runTerminalProductHierarchyActionTests',
      ),
      _TestRequirement(
        'test/frame_scheduler_test.dart',
        'runFrameSchedulerTests',
      ),
      _TestRequirement(
        'test/terminal_screen_metal_compositor_test.dart',
        'runTerminalScreenMetalCompositorTests',
      ),
    ],
    integrationTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_native_hierarchy_test.dart',
        'runTerminalNativeHierarchyTests',
      ),
    ],
    uiAssertions: <_UiRequirement>[
      _UiRequirement(
        suite: 'hierarchy',
        applicationMarker: 'TERMINAL_NATIVE_HIERARCHY_TEST',
        driverMarker: 'RUNTIME_NATIVE_HIERARCHY_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'display',
        applicationMarker: 'COMMAND_PALETTE_ACCEPTANCE',
        driverMarker: 'RUNTIME_TERMINAL_DISPLAY_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'actions',
        applicationMarker: 'TERMINAL_USER_ACTIONS_TEST',
        driverMarker: 'RUNTIME_USER_ACTIONS_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'actions',
        applicationMarker: 'TERMINAL_ACTIVE_PANE_FOCUS_TEST',
        driverMarker: 'RUNTIME_USER_ACTIONS_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'actions',
        applicationMarker: 'TERMINAL_DIRECTIONAL_PANE_KEYBIND_TEST',
        driverMarker: 'RUNTIME_USER_ACTIONS_INTEGRATION_PASS',
      ),
    ],
  ),
  _CriterionRequirement(
    id: 'pane-resource-cleanup',
    summary: 'pane close and restoration reclaim PTY, Metal, text, native, and worker owners',
    sources: <_SourceRequirement>[
      _SourceRequirement('lib/src/terminal_pane.dart', <String>[
        'final class TerminalPaneOwner',
      ]),
      _SourceRequirement('lib/src/terminal_native_hierarchy.dart', <String>[
        'void dispose()',
      ]),
      _SourceRequirement('lib/src/runtime_lifecycle.dart', <String>[
        'final class RuntimeLifecycleCoordinator',
      ]),
    ],
    unitTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_application_state_test.dart',
        'runTerminalApplicationStateTests',
      ),
      _TestRequirement(
        'test/runtime_lifecycle_test.dart',
        'runRuntimeLifecycleTests',
      ),
    ],
    integrationTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_native_hierarchy_test.dart',
        'runTerminalNativeHierarchyTests',
      ),
    ],
    uiAssertions: <_UiRequirement>[
      _UiRequirement(
        suite: 'hierarchy',
        applicationMarker: 'TERMINAL_CLOSE_QUIT_TEST',
        driverMarker: 'RUNTIME_NATIVE_HIERARCHY_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'restoration',
        applicationMarker: 'TERMINAL_RESTORATION_TEST',
        driverMarker: 'RUNTIME_RESTORATION_INTEGRATION_PASS',
      ),
      _UiRequirement(
        suite: 'actions',
        applicationMarker: 'TERMINAL_USER_ACTIONS_TEST',
        driverMarker: 'RUNTIME_USER_ACTIONS_INTEGRATION_PASS',
      ),
    ],
  ),
  _CriterionRequirement(
    id: 'cross-pane-flood-fairness',
    summary: 'one 100 MiB pane flood does not starve another pane input or grow queues',
    sources: <_SourceRequirement>[
      _SourceRequirement(
        'lib/src/terminal_renderer/pane_work_scheduler.dart',
        <String>['final class TerminalPaneWorkScheduler'],
      ),
      _SourceRequirement('lib/src/terminal_session.dart', <String>[
        'static const int defaultReadBatchesPerEventLoopTurn = 2',
      ]),
      _SourceRequirement('lib/src/terminal_application.dart', <String>[
        'TERMINAL_MULTI_PANE_FAIRNESS_TEST',
      ]),
    ],
    unitTests: <_TestRequirement>[
      _TestRequirement(
        'test/pane_work_scheduler_test.dart',
        'runTerminalPaneWorkSchedulerTests',
      ),
      _TestRequirement(
        'test/frame_scheduler_test.dart',
        'runFrameSchedulerTests',
      ),
    ],
    integrationTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_native_hierarchy_test.dart',
        'runTerminalNativeHierarchyTests',
      ),
    ],
    uiAssertions: <_UiRequirement>[
      _UiRequirement(
        suite: 'hierarchy',
        applicationMarker: 'TERMINAL_MULTI_PANE_FAIRNESS_TEST',
        driverMarker: 'RUNTIME_NATIVE_HIERARCHY_INTEGRATION_PASS',
      ),
    ],
  ),
  _CriterionRequirement(
    id: 'context-dock-directory-navigation',
    summary: 'a native sibling Dock provides bounded local tree, search, and explicit path handoff',
    sources: <_SourceRequirement>[
      _SourceRequirement('lib/src/terminal_context_dock.dart', <String>[
        'final class TerminalContextDockState',
        'final class TerminalContextDockKeyController',
      ]),
      _SourceRequirement(
        'lib/src/terminal_context_dock_directory.dart',
        <String>[
          'final class TerminalContextDockDirectoryController',
          'final class TerminalContextDockDirectoryPresenter',
          'TerminalContextDockDirectoryStatus.privacyUnavailable',
        ],
      ),
      _SourceRequirement('lib/src/terminal_directory_snapshot.dart', <String>[
        'final class TerminalWorkingDirectoryResolver',
        'final class TerminalDirectorySnapshotService',
      ]),
      _SourceRequirement('lib/src/terminal_file_search.dart', <String>[
        'abstract final class TerminalFileSearchLimits',
        'final class TerminalFileSearchService',
      ]),
      _SourceRequirement(
        'lib/src/terminal_context_dock_path_handoff.dart',
        <String>[
          'abstract final class TerminalContextDockPrivacyPolicy',
          'final class TerminalContextDockPathHandoffController',
          'appendTrailingSeparator: false',
        ],
      ),
    ],
    unitTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_context_dock_test.dart',
        'runTerminalContextDockTests',
      ),
      _TestRequirement(
        'test/terminal_directory_snapshot_test.dart',
        'runTerminalDirectorySnapshotTests',
      ),
      _TestRequirement(
        'test/terminal_file_search_test.dart',
        'runTerminalFileSearchTests',
      ),
      _TestRequirement(
        'test/terminal_native_content_test.dart',
        'runTerminalNativeContentTests',
      ),
    ],
    integrationTests: <_TestRequirement>[
      _TestRequirement(
        'test/terminal_native_hierarchy_test.dart',
        'runTerminalNativeHierarchyTests',
      ),
    ],
    uiAssertions: <_UiRequirement>[
      _UiRequirement(
        suite: 'nativeContent',
        applicationMarker: 'TERMINAL_NATIVE_CONTENT_TEST',
        driverMarker: 'RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS',
      ),
    ],
  ),
];

String generatePhase7AppKitAcceptance({Directory? repositoryRoot}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final String runner = _file(root, 'test/run_tests.dart').readAsStringSync();
  var sourceReferences = 0;
  var unitTests = 0;
  var integrationTests = 0;
  var uiAssertions = 0;
  final List<Map<String, Object?>> criteria = <Map<String, Object?>>[];
  final Set<String> criterionIds = <String>{};
  for (final _CriterionRequirement requirement in _requirements) {
    _expect(criterionIds.add(requirement.id), 'duplicate ${requirement.id}');
    final List<Map<String, Object?>> sources = requirement.sources
        .map((_SourceRequirement source) {
          final File file = _file(root, source.path);
          final String contents = file.readAsStringSync();
          for (final String needle in source.needles) {
            _expect(
              contents.contains(needle),
              '${source.path} is missing required implementation $needle',
            );
          }
          sourceReferences++;
          return <String, Object?>{
            'path': source.path,
            'sha256': terminalDifferentialSha256(file.readAsBytesSync()),
          };
        })
        .toList(growable: false);
    List<Map<String, Object?>> tests(
      List<_TestRequirement> requirements, {
      required bool integration,
    }) => requirements
        .map((_TestRequirement test) {
          final File file = _file(root, test.path);
          final String importName = test.path.substring('test/'.length);
          _expect(
            runner.contains("import '$importName';") &&
                runner.contains('${test.entryPoint}('),
            '${test.path} is not called by test/run_tests.dart',
          );
          if (integration) {
            integrationTests++;
          } else {
            unitTests++;
          }
          return <String, Object?>{
            'path': test.path,
            'entrypoint': test.entryPoint,
            'sha256': terminalDifferentialSha256(file.readAsBytesSync()),
          };
        })
        .toList(growable: false);
    final List<Map<String, Object?>> ui = requirement.uiAssertions
        .map((_UiRequirement assertion) {
          final File application = _file(
            root,
            'lib/src/terminal_application.dart',
          );
          final File driver = _file(
            root,
            'tool/runtime_integration_smoke.dart',
          );
          final String applicationSource = application.readAsStringSync();
          final String driverSource = driver.readAsStringSync();
          _expect(
            applicationSource.contains(assertion.applicationMarker),
            'application is missing ${assertion.applicationMarker}',
          );
          _expect(
            driverSource.contains(assertion.applicationMarker) &&
                driverSource.contains(assertion.driverMarker) &&
                driverSource.contains('_Suite.${assertion.suite}'),
            'runtime driver is missing ${assertion.suite} UI evidence',
          );
          uiAssertions++;
          return <String, Object?>{
            'suite': assertion.suite,
            'application_marker': assertion.applicationMarker,
            'driver_marker': assertion.driverMarker,
          };
        })
        .toList(growable: false);
    _expect(
      sources.isNotEmpty &&
          requirement.unitTests.isNotEmpty &&
          requirement.integrationTests.isNotEmpty &&
          ui.isNotEmpty,
      '${requirement.id} does not cover every required layer',
    );
    criteria.add(<String, Object?>{
      'id': requirement.id,
      'summary': requirement.summary,
      'status': 'covered',
      'sources': sources,
      'unit_tests': tests(requirement.unitTests, integration: false),
      'integration_tests': tests(
        requirement.integrationTests,
        integration: true,
      ),
      'ui_assertions': ui,
    });
  }
  final Map<String, Object?> report = <String, Object?>{
    'format': 'dart-terminal-phase7-appkit-acceptance',
    'version': 1,
    'status': 'covered',
    'criteria': criteria,
    'totals': <String, Object?>{
      'criteria': criteria.length,
      'source_references': sourceReferences,
      'unit_tests': unitTests,
      'integration_tests': integrationTests,
      'ui_assertions': uiAssertions,
      'blocking_failures': 0,
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(report)}\n';
}

Phase7AppKitAcceptanceResult runPhase7AppKitAcceptanceChecks({
  File? reportFile,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final String expected = generatePhase7AppKitAcceptance(repositoryRoot: root);
  final File actualFile = reportFile ?? _file(root, phase7AppKitAcceptancePath);
  final String actual = actualFile.readAsStringSync();
  validatePhase7AppKitAcceptanceSource(actual, expectedSource: expected);
  final Map<String, Object?> report = _object(jsonDecode(actual), 'report');
  final Map<String, Object?> totals = _object(report['totals'], 'totals');
  return Phase7AppKitAcceptanceResult(
    criteria: _integer(totals['criteria'], 'criteria'),
    sourceReferences: _integer(
      totals['source_references'],
      'source references',
    ),
    unitTests: _integer(totals['unit_tests'], 'unit tests'),
    integrationTests: _integer(
      totals['integration_tests'],
      'integration tests',
    ),
    uiAssertions: _integer(totals['ui_assertions'], 'UI assertions'),
  );
}

void validatePhase7AppKitAcceptanceSource(
  String source, {
  required String expectedSource,
}) {
  _expect(utf8.encode(source).length <= 1024 * 1024, 'report exceeds 1 MiB');
  final Map<String, Object?> report = _object(jsonDecode(source), 'report');
  _expect(
    report['format'] == 'dart-terminal-phase7-appkit-acceptance' &&
        report['version'] == 1 &&
        report['status'] == 'covered',
    'report identity or status differs',
  );
  _expect(source == expectedSource, 'Phase 7 AppKit acceptance is stale');
}

File _file(Directory root, String path) {
  _expect(
    path.isNotEmpty &&
        !path.startsWith('/') &&
        !path.contains('..') &&
        !path.contains('\\'),
    'unsafe repository path $path',
  );
  final File file = File.fromUri(root.uri.resolve(path));
  _expect(file.existsSync(), 'missing regular file $path');
  final FileStat stat = file.statSync();
  _expect(
    stat.type == FileSystemEntityType.file && stat.size <= 8 * 1024 * 1024,
    'invalid or oversized file $path',
  );
  return file;
}

Map<String, Object?> _object(Object? value, String context) {
  _expect(value is Map<String, Object?>, '$context must be an object');
  return value! as Map<String, Object?>;
}

int _integer(Object? value, String context) {
  _expect(value is int && value >= 0, '$context must be non-negative');
  return value! as int;
}

Never _fail(String message) => throw Phase7AppKitAcceptanceException(message);

void _expect(bool condition, String message) {
  if (!condition) _fail(message);
}

final class _CriterionRequirement {
  const _CriterionRequirement({
    required this.id,
    required this.summary,
    required this.sources,
    required this.unitTests,
    required this.integrationTests,
    required this.uiAssertions,
  });

  final String id;
  final String summary;
  final List<_SourceRequirement> sources;
  final List<_TestRequirement> unitTests;
  final List<_TestRequirement> integrationTests;
  final List<_UiRequirement> uiAssertions;
}

final class _SourceRequirement {
  const _SourceRequirement(this.path, this.needles);

  final String path;
  final List<String> needles;
}

final class _TestRequirement {
  const _TestRequirement(this.path, this.entryPoint);

  final String path;
  final String entryPoint;
}

final class _UiRequirement {
  const _UiRequirement({
    required this.suite,
    required this.applicationMarker,
    required this.driverMarker,
  });

  final String suite;
  final String applicationMarker;
  final String driverMarker;
}

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != '--generate' && arguments.single != '--check')) {
    stderr.writeln('usage: phase7_appkit_acceptance.dart --generate|--check');
    exitCode = 64;
    return;
  }
  try {
    if (arguments.single == '--generate') {
      final File output = File(phase7AppKitAcceptancePath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(generatePhase7AppKitAcceptance(), flush: true);
      stdout.writeln('generated ${output.path}');
    } else {
      stdout.writeln(runPhase7AppKitAcceptanceChecks().machineLine());
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
