import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_application_acceptance.dart';
import 'terminal_compatibility_inventory.dart';
import 'terminal_compatibility_regressions.dart';
import 'terminal_differential_acceptance.dart';
import 'terminal_differential_sha256.dart';

const String terminalCompatibilityRegressionCoveragePath =
    'compatibility/regression_coverage_report.json';

final class TerminalCompatibilityRegressionCoverageException
    implements Exception {
  const TerminalCompatibilityRegressionCoverageException(this.message);

  final String message;

  @override
  String toString() =>
      'TerminalCompatibilityRegressionCoverageException: $message';
}

final class TerminalCompatibilityRegressionCoverageResult {
  const TerminalCompatibilityRegressionCoverageResult({
    required this.fixFamilies,
    required this.cases,
    required this.splitRuns,
    required this.ownedGaps,
    required this.knownP0SilentCorruption,
  });

  final int fixFamilies;
  final int cases;
  final int splitRuns;
  final int ownedGaps;
  final int knownP0SilentCorruption;

  String machineLine() =>
      'TERMINAL_COMPATIBILITY_REGRESSION_COVERAGE_PASS '
      'fix_families=$fixFamilies cases=$cases split_runs=$splitRuns '
      'owned_gaps=$ownedGaps '
      'known_p0_silent_corruption=$knownP0SilentCorruption';
}

const List<_FixFamilyRequirement>
_requiredFixFamilies = <_FixFamilyRequirement>[
  _FixFamilyRequirement(
    id: 'dec-special-graphics',
    caseId: 'dec-special-graphics',
    owner: 'docs/phase6/terminfo-source-compile-install-fallback.md',
  ),
  _FixFamilyRequirement(
    id: 'xtgettcap-policy',
    caseId: 'xtgettcap-explicit-negative',
    owner: 'docs/phase6/terminfo-source-compile-install-fallback.md',
  ),
  _FixFamilyRequirement(
    id: 'osc-metadata',
    caseId: 'osc-metadata-title-stack-hyperlink',
    owner: 'docs/phase6/osc-title-cwd-hyperlink-palette-clipboard-policy.md',
  ),
  _FixFamilyRequirement(
    id: 'osc-color-policy',
    caseId: 'osc-palette-default-cursor-color',
    owner: 'docs/phase6/osc-title-cwd-hyperlink-palette-clipboard-policy.md',
  ),
  _FixFamilyRequirement(
    id: 'osc52-default-deny',
    caseId: 'osc52-default-deny',
    owner: 'docs/phase6/osc-title-cwd-hyperlink-palette-clipboard-policy.md',
  ),
  _FixFamilyRequirement(
    id: 'focus-reporting',
    caseId: 'focus-mode-report',
    owner: 'docs/phase6/focus-mouse-bracketed-paste-query-reports.md',
  ),
  _FixFamilyRequirement(
    id: 'sgr-pixel-mouse',
    caseId: 'sgr-pixel-mouse-mode-report',
    owner: 'docs/phase6/focus-mouse-bracketed-paste-query-reports.md',
  ),
  _FixFamilyRequirement(
    id: 'decrqss-sgr',
    caseId: 'decrqss-current-sgr',
    owner: 'docs/phase6/decrqss-sgr-gap.md',
  ),
  _FixFamilyRequirement(
    id: 'xterm-query-reports',
    caseId: 'xterm-version-window-reports',
    owner: 'docs/phase6/focus-mouse-bracketed-paste-query-reports.md',
  ),
];

String generateTerminalCompatibilityRegressionCoverage({
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final File corpusFile = _file(
    root,
    terminalCompatibilityRegressionCorpusPath,
    1024 * 1024,
  );
  final String corpusSource = corpusFile.readAsStringSync();
  final TerminalCompatibilityRegressionRun corpusRun =
      runTerminalCompatibilityRegressionCorpus(
        parseTerminalCompatibilityRegressionCorpus(corpusSource),
      );
  final Map<String, Object?> corpus = _jsonObject(corpusSource, 'corpus');
  final List<Object?> caseValues = _array(corpus['cases'], 'corpus.cases');
  final Map<String, _CorpusCase> casesByFamily = <String, _CorpusCase>{};
  final Set<String> caseIds = <String>{};
  for (var index = 0; index < caseValues.length; index++) {
    final Map<String, Object?> item = _object(
      caseValues[index],
      'corpus.cases[$index]',
    );
    final _CorpusCase testCase = _CorpusCase(
      id: _id(item['id'], 'case.id'),
      fixFamily: _id(item['fix_family'], 'case.fix_family'),
      owner: _path(item['owner'], 'case.owner'),
    );
    _expect(caseIds.add(testCase.id), 'duplicate case ${testCase.id}');
    _expect(
      casesByFamily.putIfAbsent(testCase.fixFamily, () => testCase) == testCase,
      'fix family ${testCase.fixFamily} has multiple cases',
    );
  }
  _expect(
    caseValues.length == _requiredFixFamilies.length &&
        corpusRun.cases == _requiredFixFamilies.length &&
        corpusRun.fixFamilies.length == _requiredFixFamilies.length,
    'compatibility corpus family totals differ',
  );
  final List<Map<String, Object?>> fixFamilies = <Map<String, Object?>>[];
  for (final _FixFamilyRequirement required in _requiredFixFamilies) {
    final _CorpusCase? actual = casesByFamily.remove(required.id);
    _expect(actual != null, 'missing fix family ${required.id}');
    _expect(
      actual!.id == required.caseId && actual.owner == required.owner,
      '${required.id} case or owner differs',
    );
    final File owner = _file(root, required.owner, 1024 * 1024);
    fixFamilies.add(<String, Object?>{
      'id': required.id,
      'case_ids': <String>[required.caseId],
      'owner': required.owner,
      'owner_sha256': _sha256(owner),
      'status': 'covered',
    });
  }
  _expect(casesByFamily.isEmpty, 'corpus has unknown fix families');

  final File inventoryFile = _file(
    root,
    defaultTerminalCompatibilityInventoryPath,
    4 * 1024 * 1024,
  );
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(inventoryFile, repositoryRoot: root);
  final File implementationFile = _file(
    root,
    defaultTerminalImplementationSurfacePath,
    1024 * 1024,
  );
  inventory.reconcileImplementationSurface(implementationFile);
  final Map<TerminalCompatibilitySupport, int> support =
      inventory.supportCounts;
  final int explicitUnsupported = inventory.records
      .where(
        (TerminalCompatibilityRecord record) =>
            record.support == TerminalCompatibilitySupport.unsupported &&
            record.disposition == TerminalCompatibilityDisposition.reject,
      )
      .length;
  final int safeIgnore = inventory.records
      .where(
        (TerminalCompatibilityRecord record) =>
            record.support == TerminalCompatibilitySupport.safeIgnore &&
            record.disposition == TerminalCompatibilityDisposition.ignore,
      )
      .length;
  _expect(
    inventory.records.length == 270 &&
        support[TerminalCompatibilitySupport.implemented] == 96 &&
        support[TerminalCompatibilitySupport.partial] == 20 &&
        support[TerminalCompatibilitySupport.safeIgnore] == 9 &&
        support[TerminalCompatibilitySupport.unsupported] == 145 &&
        safeIgnore == 9 &&
        explicitUnsupported == 145,
    'reviewed inventory boundary differs',
  );
  final Map<String, Object?> implementation = _jsonObject(
    implementationFile.readAsStringSync(),
    'implementation',
  );
  final int selectors = _array(
    implementation['selectors'],
    'implementation.selectors',
  ).length;
  final int modes = _array(
    implementation['modes'],
    'implementation.modes',
  ).length;
  _expect(
    selectors == 89 && modes == 27,
    'reviewed implementation declaration totals differ',
  );

  final TerminalApplicationAcceptanceResult application =
      runTerminalApplicationAcceptanceChecks(repositoryRoot: root);
  final File applicationFile = _file(
    root,
    defaultTerminalApplicationAcceptancePath,
    1024 * 1024,
  );
  final Map<String, Object?> applicationReport = _jsonObject(
    applicationFile.readAsStringSync(),
    'application acceptance',
  );
  final List<Map<String, Object?>> ownedGaps = <Map<String, Object?>>[];
  for (final Object? value in _array(
    applicationReport['gaps'],
    'application gaps',
  )) {
    final Map<String, Object?> gap = _object(value, 'application gap');
    _expect(
      gap['disposition'] == 'explicit-unsupported' &&
          gap['screen_mutation'] == false &&
          gap['matrix_blocker'] == false,
      '${gap['id']} remains an unsafe or blocking application gap',
    );
    ownedGaps.add(<String, Object?>{
      'id': _id(gap['id'], 'gap.id'),
      'disposition': gap['disposition'],
      'impact': _id(gap['impact'], 'gap.impact'),
      'owner': _text(gap['owner'], 'gap.owner'),
      'variants': _array(gap['variants'], 'gap.variants').length,
      'screen_mutation': false,
      'matrix_blocker': false,
    });
  }
  _expect(
    application.acceptedCells == 8 &&
        application.cleanAgreements == 7 &&
        application.documentedGapCells == 1 &&
        application.gaps == 1 &&
        application.uniqueSequences == 1 &&
        application.unsupportedIncrements == 4 &&
        ownedGaps.length == 1,
    'reviewed application acceptance totals differ',
  );

  final TerminalDifferentialAcceptanceResult differential =
      runTerminalDifferentialAcceptanceChecks(repositoryRoot: root);
  final File differentialFile = _file(
    root,
    defaultTerminalDifferentialAcceptancePath,
    1024 * 1024,
  );
  final Map<String, Object?> differentialReport = _jsonObject(
    differentialFile.readAsStringSync(),
    'differential acceptance',
  );
  final Map<String, Object?> differentialSummary = _object(
    differentialReport['summary'],
    'differential summary',
  );
  _expect(
    differential.accepted == 12 &&
        differential.agreements == 8 &&
        differential.documentedGaps == 0 &&
        differential.unavailable == 4 &&
        differential.decrqssRegressionBytes == 7 &&
        differentialSummary['semantic_agreements'] == 1 &&
        differentialSummary['unexpected_mismatches'] == 0 &&
        differentialSummary['silent_results'] == 0,
    'reviewed differential acceptance totals differ',
  );

  final _ParserTraceEvidence trace = _checkParserTrace(root);
  _expect(
    trace.inputBytes == 97 && trace.events == 11,
    'reviewed parser trace totals differ',
  );

  final List<String> sourcePaths = <String>[
    terminalCompatibilityRegressionCorpusPath,
    defaultTerminalCompatibilityInventoryPath,
    defaultTerminalImplementationSurfacePath,
    defaultTerminalApplicationAcceptancePath,
    defaultTerminalDifferentialAcceptancePath,
    'test/corpus/parser/sequence_trace_case_v1.json',
    'test/corpus/parser/sequence_trace_v1.json',
    'README.md',
    'FEATURE_MATRIX.md',
  ];
  final List<Map<String, Object?>> sources = <Map<String, Object?>>[
    for (final String path in sourcePaths)
      <String, Object?>{
        'path': path,
        'sha256': _sha256(_file(root, path, 4 * 1024 * 1024)),
      },
  ];

  final Map<String, Object?> report = <String, Object?>{
    'format': 'dart-terminal-compatibility-regression-coverage',
    'version': 1,
    'status': 'accepted-with-nonblocking-duration-follow-up',
    'sources': sources,
    'fix_families': fixFamilies,
    'owned_application_gaps': ownedGaps,
    'acceptance': <String, Object?>{
      'regression_corpus': <String, Object?>{
        'cases': corpusRun.cases,
        'fix_families': corpusRun.fixFamilies.length,
        'input_bytes': corpusRun.inputBytes,
        'split_runs': corpusRun.splitRuns,
      },
      'inventory': <String, Object?>{
        'records': inventory.records.length,
        'implemented': support[TerminalCompatibilitySupport.implemented],
        'partial': support[TerminalCompatibilitySupport.partial],
        'safe_ignore': safeIgnore,
        'explicit_unsupported': explicitUnsupported,
        'implementation_selectors': selectors,
        'implementation_modes': modes,
      },
      'application_matrix': <String, Object?>{
        'cells': application.acceptedCells,
        'clean_agreements': application.cleanAgreements,
        'documented_gap_cells': application.documentedGapCells,
        'gaps': application.gaps,
        'unique_sequences': application.uniqueSequences,
        'unsupported_increments': application.unsupportedIncrements,
      },
      'differential': <String, Object?>{
        'accepted': differential.accepted,
        'agreements': differential.agreements,
        'semantic_agreements': differentialSummary['semantic_agreements'],
        'documented_gaps': differential.documentedGaps,
        'unavailable': differential.unavailable,
        'unexpected_mismatches': differentialSummary['unexpected_mismatches'],
        'silent_results': differentialSummary['silent_results'],
      },
      'parser_trace': <String, Object?>{
        'input_bytes': trace.inputBytes,
        'events': trace.events,
      },
    },
    'phase_exit': <String, Object?>{
      'known_p0_silent_corruption': 0,
      'unsupported_sequences_classified': true,
      'fix_families_with_byte_regressions': _requiredFixFamilies.length,
      'duration_only_soak': 'low-priority-nonblocking-follow-up',
      'blocking_failures': 0,
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(report)}\n';
}

TerminalCompatibilityRegressionCoverageResult
runTerminalCompatibilityRegressionCoverageChecks({
  File? reportFile,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final String expected = generateTerminalCompatibilityRegressionCoverage(
    repositoryRoot: root,
  );
  final File actualFile =
      reportFile ??
      _file(root, terminalCompatibilityRegressionCoveragePath, 1024 * 1024);
  final String actual = actualFile.readAsStringSync();
  validateTerminalCompatibilityRegressionCoverageSource(
    actual,
    expectedSource: expected,
  );
  final Map<String, Object?> report = _jsonObject(actual, 'coverage report');
  final Map<String, Object?> acceptance = _object(
    report['acceptance'],
    'acceptance',
  );
  final Map<String, Object?> corpus = _object(
    acceptance['regression_corpus'],
    'regression corpus',
  );
  final Map<String, Object?> phaseExit = _object(
    report['phase_exit'],
    'phase exit',
  );
  return TerminalCompatibilityRegressionCoverageResult(
    fixFamilies: _array(report['fix_families'], 'fix families').length,
    cases: _integer(corpus['cases'], 'corpus cases'),
    splitRuns: _integer(corpus['split_runs'], 'split runs'),
    ownedGaps: _array(report['owned_application_gaps'], 'owned gaps').length,
    knownP0SilentCorruption: _integer(
      phaseExit['known_p0_silent_corruption'],
      'known P0 silent corruption',
    ),
  );
}

void validateTerminalCompatibilityRegressionCoverageSource(
  String source, {
  required String expectedSource,
}) {
  _expect(utf8.encode(source).length <= 1024 * 1024, 'report exceeds 1 MiB');
  final Map<String, Object?> report = _jsonObject(source, 'coverage report');
  _keys(report, const <String>{
    'format',
    'version',
    'status',
    'sources',
    'fix_families',
    'owned_application_gaps',
    'acceptance',
    'phase_exit',
  }, 'coverage report');
  _expect(
    report['format'] == 'dart-terminal-compatibility-regression-coverage' &&
        report['version'] == 1 &&
        report['status'] == 'accepted-with-nonblocking-duration-follow-up',
    'coverage report identity or status differs',
  );
  _expect(source == expectedSource, 'coverage report is stale');
}

_ParserTraceEvidence _checkParserTrace(Directory root) {
  final File caseFile = _file(
    root,
    'test/corpus/parser/sequence_trace_case_v1.json',
    1024 * 1024,
  );
  final Map<String, Object?> fixture = _jsonObject(
    caseFile.readAsStringSync(),
    'parser trace case',
  );
  _expect(
    fixture['format'] == 'dart-terminal-parser-trace-case' &&
        fixture['version'] == 1 &&
        fixture['case_id'] == 'all-action-families-redacted',
    'parser trace case identity differs',
  );
  final Uint8List input = _hex(
    _text(fixture['input_hex'], 'trace input'),
    'trace input',
  );
  final Map<String, Object?> parser = _object(
    fixture['parser_limits'],
    'parser limits',
  );
  final Map<String, Object?> inspector = _object(
    fixture['inspector_limits'],
    'inspector limits',
  );
  final Map<String, Object?> export = _object(
    fixture['export_limits'],
    'export limits',
  );
  final int events = _integer(
    fixture['expected_event_count'],
    'expected event count',
  );
  final String actual =
      VtParserTraceExporter(
        limits: VtParserTraceExportLimits(
          maxInputBytes: _integer(export['max_input_bytes'], 'max input bytes'),
          maxOutputBytes: _integer(
            export['max_output_bytes'],
            'max output bytes',
          ),
        ),
      ).capture(
        input,
        parserLimits: VtParserLimits(
          maxSequenceBytes: _integer(
            parser['max_sequence_bytes'],
            'max sequence bytes',
          ),
          maxStringBytes: _integer(
            parser['max_string_bytes'],
            'max string bytes',
          ),
          maxParameters: _integer(parser['max_parameters'], 'max parameters'),
          maxIntermediates: _integer(
            parser['max_intermediates'],
            'max intermediates',
          ),
          maxNumericValue: _integer(
            parser['max_numeric_value'],
            'max numeric value',
          ),
        ),
        inspectorLimits: VtParserInspectorLimits(
          maxRecords: _integer(inspector['max_records'], 'max records'),
          maxMetadataBytes: _integer(
            inspector['max_metadata_bytes'],
            'max metadata bytes',
          ),
        ),
      );
  final File expectedFile = _file(
    root,
    'test/corpus/parser/sequence_trace_v1.json',
    1024 * 1024,
  );
  _expect(
    actual == expectedFile.readAsStringSync(),
    'parser trace fixture is stale',
  );
  final Map<String, Object?> trace = _jsonObject(actual, 'parser trace');
  _expect(
    trace['input_bytes'] == input.length &&
        trace['events_total'] == events &&
        trace['events_retained'] == events,
    'parser trace metrics differ',
  );
  return _ParserTraceEvidence(inputBytes: input.length, events: events);
}

File _file(Directory root, String path, int maximumBytes) {
  _expect(
    RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path) &&
        !path.startsWith('/') &&
        !path.split('/').contains('..'),
    'unsafe repository path: $path',
  );
  final File file = File.fromUri(root.uri.resolve(path));
  _expect(file.existsSync(), 'missing file: $path');
  final FileStat stat = file.statSync();
  _expect(
    stat.type == FileSystemEntityType.file &&
        stat.size > 0 &&
        stat.size <= maximumBytes,
    'file size or type is invalid: $path',
  );
  return file;
}

String _sha256(File file) => terminalDifferentialSha256(file.readAsBytesSync());

Map<String, Object?> _jsonObject(String source, String context) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on Object catch (error) {
    throw TerminalCompatibilityRegressionCoverageException(
      '$context has invalid JSON: $error',
    );
  }
  return _object(decoded, context);
}

Map<String, Object?> _object(Object? value, String context) {
  _expect(value is Map<Object?, Object?>, '$context must be an object');
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry
      in (value! as Map<Object?, Object?>).entries) {
    _expect(entry.key is String, '$context has a non-string key');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  _expect(value is List<Object?>, '$context must be an array');
  return value! as List<Object?>;
}

String _text(Object? value, String context) {
  _expect(value is String && value.isNotEmpty, '$context must be text');
  return value! as String;
}

String _id(Object? value, String context) {
  final String valueText = _text(value, context);
  _expect(
    RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(valueText),
    '$context is not an identifier',
  );
  return valueText;
}

String _path(Object? value, String context) {
  final String valueText = _text(value, context);
  _expect(
    RegExp(r'^docs/phase6/[a-z0-9-]+\.md$').hasMatch(valueText),
    '$context is not a safe Phase 6 owner',
  );
  return valueText;
}

int _integer(Object? value, String context) {
  _expect(value is int && value >= 0, '$context must be a non-negative int');
  return value! as int;
}

Uint8List _hex(String value, String context) {
  _expect(
    value.length.isEven && RegExp(r'^[0-9a-f]*$').hasMatch(value),
    '$context is not lowercase byte-aligned hex',
  );
  final Uint8List result = Uint8List(value.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

void _keys(Map<String, Object?> value, Set<String> expected, String context) {
  _expect(
    value.keys.length == expected.length &&
        value.keys.toSet().containsAll(expected),
    '$context keys differ',
  );
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw TerminalCompatibilityRegressionCoverageException(message);
  }
}

final class _FixFamilyRequirement {
  const _FixFamilyRequirement({
    required this.id,
    required this.caseId,
    required this.owner,
  });

  final String id;
  final String caseId;
  final String owner;
}

final class _CorpusCase {
  const _CorpusCase({
    required this.id,
    required this.fixFamily,
    required this.owner,
  });

  final String id;
  final String fixFamily;
  final String owner;
}

final class _ParserTraceEvidence {
  const _ParserTraceEvidence({required this.inputBytes, required this.events});

  final int inputBytes;
  final int events;
}

void main(List<String> arguments) {
  try {
    if (arguments.length != 1 ||
        arguments.single != '--generate' && arguments.single != '--check') {
      throw const TerminalCompatibilityRegressionCoverageException(
        'usage: terminal_compatibility_regression_coverage.dart '
        '[--generate|--check]',
      );
    }
    if (arguments.single == '--generate') {
      File(terminalCompatibilityRegressionCoveragePath)
          .writeAsStringSync(generateTerminalCompatibilityRegressionCoverage());
      stdout.writeln(
        'TERMINAL_COMPATIBILITY_REGRESSION_COVERAGE_GENERATED '
        'path=$terminalCompatibilityRegressionCoveragePath',
      );
      return;
    }
    stdout.writeln(
      runTerminalCompatibilityRegressionCoverageChecks().machineLine(),
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_COMPATIBILITY_REGRESSION_COVERAGE_FAIL $error');
    exitCode = 1;
  }
}
