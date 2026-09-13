import 'dart:convert';
import 'dart:io';

import '../tool/terminal_application_evidence.dart';
import '../tool/terminal_application_matrix.dart';
import '../tool/terminal_differential_sha256.dart';

void main() => runTerminalApplicationEvidenceTests();

void runTerminalApplicationEvidenceTests() {
  _testReviewedEvidence();
  _testRawEvidenceValidation();
  _testIndexFreshnessValidation();
}

void _testReviewedEvidence() {
  final TerminalApplicationEvidenceResult result =
      runTerminalApplicationEvidenceChecks();
  _expect(
    result.cells == 8 &&
        result.outputBytes == 57737 &&
        result.samples == 32 &&
        result.passedChecks == 41 &&
        result.failedChecks == 7 &&
        result.machineLine() ==
            'TERMINAL_APPLICATION_EVIDENCE_PASS cells=8 '
                'output_bytes=57737 samples=32 passed_checks=41 '
                'failed_checks=7',
    'reviewed matrix evidence has exact bounded totals',
  );
}

void _testRawEvidenceValidation() {
  final TerminalApplicationScenario scenario =
      TerminalApplicationMatrixManifest.load(
        File(defaultTerminalApplicationMatrixPath),
      ).scenarios.first;
  final File source = File(
    'test/corpus/applications/external/emacs-terminal-ui.capture.json',
  );
  final String fixture = source.readAsStringSync();
  final TerminalApplicationRawEvidence parsed =
      TerminalApplicationRawEvidence.parse(fixture, scenario: scenario);
  _expect(
    parsed.applicationId == 'emacs' &&
        parsed.samples.length == 4 &&
        parsed.resizes.length == 2 &&
        parsed.output.isNotEmpty,
    'reviewed raw evidence round trips',
  );

  Map<String, Object?> root() =>
      Map<String, Object?>.from(jsonDecode(fixture) as Map<Object?, Object?>);
  final Map<String, Object?> currentVersion = root();
  final List<Object?> currentVersionSamples =
      currentVersion['samples']! as List<Object?>;
  final Map<String, Object?> currentVersionSample =
      currentVersionSamples.first! as Map<String, Object?>;
  currentVersionSample['snapshot'] =
      (currentVersionSample['snapshot']! as String).replaceFirst(
        'version=1 ',
        'version=4 ',
      );
  currentVersionSample['snapshot_sha256'] = terminalDifferentialSha256(
    utf8.encode(currentVersionSample['snapshot']! as String),
  );
  _expect(
    TerminalApplicationRawEvidence.parse(
      jsonEncode(currentVersion),
      scenario: scenario,
    ).samples.first.snapshot.startsWith(
      'dart-terminal-state-snapshot version=4 ',
    ),
    'current snapshot version coexists with immutable version-one evidence',
  );

  Map<String, Object?> invalid = root()..['extra'] = true;
  _expectRawFailure(invalid, scenario, 'raw evidence keys differ');

  invalid = root()..['output_bytes'] = 0;
  _expectRawFailure(invalid, scenario, 'raw output count differs');

  invalid = root();
  final List<Object?> invalidStages = invalid['samples']! as List<Object?>;
  (invalidStages.first! as Map<String, Object?>)['stage'] = 'wrong';
  _expectRawFailure(invalid, scenario, 'sample stages differ');

  invalid = root();
  final List<Object?> invalidSamples = invalid['samples']! as List<Object?>;
  final Map<String, Object?> sample =
      invalidSamples.first! as Map<String, Object?>;
  sample['snapshot'] = (sample['snapshot']! as String).replaceFirst(
    'end\n',
    '/Users/private\nend\n',
  );
  sample['snapshot_sha256'] = terminalDifferentialSha256(
    utf8.encode(sample['snapshot']! as String),
  );
  _expectRawFailure(invalid, scenario, 'snapshot contains private data');

  invalid = root();
  final List<Object?> unsupportedVersionSamples =
      invalid['samples']! as List<Object?>;
  final Map<String, Object?> unsupportedVersionSample =
      unsupportedVersionSamples.first! as Map<String, Object?>;
  unsupportedVersionSample['snapshot'] =
      (unsupportedVersionSample['snapshot']! as String).replaceFirst(
        'version=1 ',
        'version=5 ',
      );
  unsupportedVersionSample['snapshot_sha256'] = terminalDifferentialSha256(
    utf8.encode(unsupportedVersionSample['snapshot']! as String),
  );
  _expectRawFailure(invalid, scenario, 'sample snapshot envelope is invalid');

  invalid = root();
  final List<Object?> invalidResizes = invalid['resizes']! as List<Object?>;
  (invalidResizes.first! as Map<String, Object?>)['rows'] = 1;
  _expectRawFailure(
    invalid,
    scenario,
    'resize dimensions differ from scenario recipe',
  );
}

void _testIndexFreshnessValidation() {
  final Map<String, Object?> fixture = Map<String, Object?>.from(
    jsonDecode(File(defaultTerminalApplicationEvidencePath).readAsStringSync())
        as Map<Object?, Object?>,
  );
  _withIndex(<String, Object?>{
    ...fixture,
    'matrix_sha256': List<String>.filled(64, '0').join(),
  }, 'matrix hash differs');
  final List<Object?> cells = <Object?>[
    for (final Object? value in fixture['cells']! as List<Object?>)
      Map<String, Object?>.from(value! as Map<Object?, Object?>),
  ];
  (cells.first! as Map<String, Object?>)['raw_evidence_sha256'] =
      List<String>.filled(64, '0').join();
  _withIndex(<String, Object?>{
    ...fixture,
    'cells': cells,
  }, 'raw evidence hash differs');
}

void _expectRawFailure(
  Map<String, Object?> value,
  TerminalApplicationScenario scenario,
  String message,
) {
  try {
    TerminalApplicationRawEvidence.parse(jsonEncode(value), scenario: scenario);
  } on TerminalApplicationEvidenceException catch (error) {
    _expect(
      error.message.contains(message),
      'raw evidence failed for expected reason $message: $error',
    );
    return;
  }
  throw StateError('test failed: raw evidence accepted invalid $message');
}

void _withIndex(Map<String, Object?> value, String message) {
  final Directory directory = Directory.systemTemp.createTempSync(
    'dart-terminal-application-evidence-',
  );
  try {
    final File file = File('${directory.path}/index.json')
      ..writeAsStringSync('${jsonEncode(value)}\n');
    try {
      runTerminalApplicationEvidenceChecks(indexFile: file);
    } on TerminalApplicationEvidenceException catch (error) {
      _expect(
        error.message.contains(message),
        'index failed for expected reason $message: $error',
      );
      return;
    }
    throw StateError('test failed: index accepted invalid $message');
  } finally {
    directory.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
