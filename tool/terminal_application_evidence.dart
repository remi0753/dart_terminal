import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_application_matrix.dart';
import 'terminal_differential_sha256.dart';

const String defaultTerminalApplicationEvidencePath =
    'compatibility/application_matrix_evidence.json';

final class TerminalApplicationEvidenceException implements FormatException {
  const TerminalApplicationEvidenceException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalApplicationEvidenceException: $message';
}

final class TerminalApplicationEvidenceResult {
  const TerminalApplicationEvidenceResult({
    required this.cells,
    required this.outputBytes,
    required this.samples,
    required this.passedChecks,
    required this.failedChecks,
  });

  final int cells;
  final int outputBytes;
  final int samples;
  final int passedChecks;
  final int failedChecks;

  String machineLine() =>
      'TERMINAL_APPLICATION_EVIDENCE_PASS cells=$cells '
      'output_bytes=$outputBytes samples=$samples '
      'passed_checks=$passedChecks failed_checks=$failedChecks';
}

TerminalApplicationEvidenceResult runTerminalApplicationEvidenceChecks({
  File? indexFile,
}) {
  final File source = indexFile ?? File(defaultTerminalApplicationEvidencePath);
  _regularFile(source, maximumBytes: 1024 * 1024, context: 'evidence index');
  final Map<String, Object?> root = _decodeObject(
    source.readAsStringSync(),
    'evidence index',
  );
  _keys(root, const <String>{
    'format',
    'version',
    'matrix_path',
    'matrix_sha256',
    'capture_driver_path',
    'capture_driver_sha256',
    'environment',
    'sources',
    'cells',
  }, 'evidence index');
  _expect(
    root['format'] == 'dart-terminal-application-evidence-index' &&
        root['version'] == 1,
    'unsupported evidence index',
  );
  final String matrixPath = _reviewedPath(
    root['matrix_path'],
    'matrix_path',
    exact: defaultTerminalApplicationMatrixPath,
  );
  final File matrixFile = File(matrixPath);
  _hashMatches(matrixFile, root['matrix_sha256'], 'matrix');
  final TerminalApplicationMatrixManifest manifest =
      TerminalApplicationMatrixManifest.load(matrixFile);
  final String driverPath = _reviewedPath(
    root['capture_driver_path'],
    'capture_driver_path',
    exact: 'tool/terminal_application_capture_driver.dart',
  );
  _hashMatches(File(driverPath), root['capture_driver_sha256'], 'driver');
  final Map<String, Object?> environment = _object(
    root['environment'],
    'environment',
  );
  _keys(environment, const <String>{
    'os',
    'architecture',
    'dart',
    'capture_method',
  }, 'environment');
  _expect(environment['os'] == 'macos-26-6-2', 'unexpected evidence OS');
  _expect(environment['architecture'] == 'arm64', 'unexpected architecture');
  _expect(
    environment['capture_method'] == 'developer-jit-product-pty-v1',
    'unexpected capture method',
  );
  _token(environment['dart'], 'environment.dart');
  final Map<String, _ReviewedSource> sources = _parseSources(root['sources']);
  final List<Object?> cells = _array(root['cells'], 'cells');
  _expect(cells.length == 8, 'evidence index must contain eight cells');
  final List<TerminalApplicationScenario> scenarios = manifest.scenarios
      .toList();
  var totalOutputBytes = 0;
  var totalSamples = 0;
  var passedChecks = 0;
  var failedChecks = 0;
  String previousScenario = '';
  final Set<String> observedScenarios = <String>{};
  for (int index = 0; index < cells.length; index++) {
    final Map<String, Object?> cell = _object(cells[index], 'cells[$index]');
    _keys(cell, const <String>{
      'application_id',
      'scenario_id',
      'status',
      'observation_path',
      'observation_sha256',
      'raw_evidence_path',
      'raw_evidence_sha256',
    }, 'cell');
    final String applicationId = _id(
      cell['application_id'],
      'cell.application_id',
    );
    final String scenarioId = _id(cell['scenario_id'], 'cell.scenario_id');
    _expect(cell['status'] == 'captured', '$scenarioId is not captured');
    _expect(
      previousScenario.isEmpty || previousScenario.compareTo(scenarioId) < 0,
      'cells must be sorted by scenario id',
    );
    previousScenario = scenarioId;
    _expect(observedScenarios.add(scenarioId), 'duplicate cell $scenarioId');
    final TerminalApplicationScenario scenario = scenarios.singleWhere(
      (TerminalApplicationScenario candidate) => candidate.id == scenarioId,
      orElse: () => throw TerminalApplicationEvidenceException(
        'unknown scenario $scenarioId',
      ),
    );
    _expect(
      scenario.applicationId == applicationId,
      '$scenarioId application differs from manifest',
    );
    final String observationPath = _evidencePath(
      cell['observation_path'],
      scenarioId,
      'observation.json',
    );
    final File observationFile = File(observationPath);
    _hashMatches(
      observationFile,
      cell['observation_sha256'],
      '$scenarioId observation',
    );
    final TerminalApplicationObservation observation =
        TerminalApplicationObservation.parse(
          observationFile.readAsStringSync(),
          scenario: scenario,
        );
    final String rawPath = _evidencePath(
      cell['raw_evidence_path'],
      scenarioId,
      'capture.json',
    );
    final File rawFile = File(rawPath);
    _hashMatches(
      rawFile,
      cell['raw_evidence_sha256'],
      '$scenarioId raw evidence',
      maximumBytes: 2 * 1024 * 1024,
    );
    _expect(
      observation.rawEvidenceSha256 == cell['raw_evidence_sha256'],
      '$scenarioId observation raw hash differs from index',
    );
    final TerminalApplicationRawEvidence raw =
        TerminalApplicationRawEvidence.parse(
          rawFile.readAsStringSync(),
          scenario: scenario,
        );
    _crossCheck(
      scenario: scenario,
      source: sources[applicationId]!,
      observation: observation,
      raw: raw,
      environment: environment,
    );
    totalOutputBytes += raw.output.length;
    totalSamples += raw.samples.length;
    for (final TerminalApplicationCheckResult check in observation.checks) {
      if (check.passed) {
        passedChecks++;
      } else {
        failedChecks++;
      }
    }
  }
  _expect(
    observedScenarios.length == scenarios.length &&
        observedScenarios.containsAll(scenarios.map((value) => value.id)),
    'evidence cells differ from manifest scenarios',
  );
  return TerminalApplicationEvidenceResult(
    cells: cells.length,
    outputBytes: totalOutputBytes,
    samples: totalSamples,
    passedChecks: passedChecks,
    failedChecks: failedChecks,
  );
}

final class TerminalApplicationRawEvidence {
  const TerminalApplicationRawEvidence({
    required this.applicationId,
    required this.scenarioId,
    required this.captureMethod,
    required this.product,
    required this.productVersion,
    required this.output,
    required this.samples,
    required this.resizes,
    required this.exitCode,
    required this.signal,
    required this.parser,
  });

  final String applicationId;
  final String scenarioId;
  final String captureMethod;
  final String product;
  final String productVersion;
  final Uint8List output;
  final List<TerminalApplicationRawSample> samples;
  final List<TerminalApplicationRawResize> resizes;
  final int exitCode;
  final int? signal;
  final Map<String, int> parser;

  static TerminalApplicationRawEvidence parse(
    String source, {
    required TerminalApplicationScenario scenario,
  }) {
    _expect(
      utf8.encode(source).length <= 2 * 1024 * 1024,
      '${scenario.id} raw evidence exceeds 2 MiB',
    );
    final Map<String, Object?> root = _decodeObject(source, 'raw evidence');
    _keys(root, const <String>{
      'format',
      'version',
      'application_id',
      'scenario_id',
      'capture_method',
      'product',
      'product_version',
      'output_bytes',
      'output_sha256',
      'output_base64',
      'samples',
      'resizes',
      'exit',
      'parser',
    }, 'raw evidence');
    _expect(
      root['format'] == 'dart-terminal-application-raw-evidence' &&
          root['version'] == 1,
      'unsupported raw evidence',
    );
    final String applicationId = _id(
      root['application_id'],
      'raw.application_id',
    );
    final String scenarioId = _id(root['scenario_id'], 'raw.scenario_id');
    _expect(
      applicationId == scenario.applicationId && scenarioId == scenario.id,
      'raw evidence identity differs from scenario',
    );
    final String encoded = _text(
      root['output_base64'],
      'output_base64',
      1400000,
    );
    final Uint8List output;
    try {
      output = base64Decode(encoded);
    } on FormatException {
      throw const TerminalApplicationEvidenceException(
        'output_base64 is invalid',
      );
    }
    _expect(
      output.isNotEmpty && output.length <= scenario.maximumOutputBytes,
      'raw output is outside scenario bounds',
    );
    _expect(root['output_bytes'] == output.length, 'raw output count differs');
    _expect(
      root['output_sha256'] == terminalDifferentialSha256(output),
      'raw output hash differs',
    );
    final String outputText = utf8.decode(output, allowMalformed: true);
    for (final String forbidden in _privateContentTokens) {
      _expect(
        !outputText.contains(forbidden),
        'raw output contains private data',
      );
    }
    final List<Object?> sampleValues = _array(root['samples'], 'samples');
    _expect(sampleValues.length == 4, 'raw evidence must contain four samples');
    const List<String> stages = <String>[
      'initial',
      'activated',
      'resized',
      'exited',
    ];
    final List<TerminalApplicationRawSample> samples =
        <TerminalApplicationRawSample>[];
    var previousBytes = -1;
    for (int index = 0; index < sampleValues.length; index++) {
      final TerminalApplicationRawSample sample =
          TerminalApplicationRawSample.parse(
            sampleValues[index],
            expectedStage: stages[index],
          );
      _expect(
        sample.outputBytes >= previousBytes &&
            sample.outputBytes <= output.length,
        'sample output counts are not monotonic',
      );
      previousBytes = sample.outputBytes;
      samples.add(sample);
    }
    final List<Object?> resizeValues = _array(root['resizes'], 'resizes');
    _expect(resizeValues.length == 2, 'raw evidence must contain two resizes');
    final List<TerminalApplicationRawResize> resizes =
        <TerminalApplicationRawResize>[
          for (int index = 0; index < resizeValues.length; index++)
            TerminalApplicationRawResize.parse(resizeValues[index]),
        ];
    _expect(
      resizes[0].rows == scenario.rows + 3 &&
          resizes[0].columns == scenario.columns + 7 &&
          resizes[1].rows == scenario.rows &&
          resizes[1].columns == scenario.columns,
      'resize dimensions differ from scenario recipe',
    );
    final Map<String, Object?> exit = _object(root['exit'], 'exit');
    _keys(exit, const <String>{'exit_code', 'signal'}, 'exit');
    final int exitCode = _integer(exit['exit_code'], 'exit.exit_code');
    final int? signal = switch (exit['signal']) {
      null => null,
      final Object? value => _integer(value, 'exit.signal'),
    };
    final Map<String, Object?> parserMap = _object(root['parser'], 'parser');
    const Set<String> parserKeys = <String>{
      'unsupported_controls',
      'unsupported_sequences',
      'cancel',
      'limit',
      'malformed',
      'incomplete',
      'replies_accepted',
      'replies_rejected',
    };
    _keys(parserMap, parserKeys, 'parser');
    final Map<String, int> parser = <String, int>{
      for (final String key in parserKeys)
        key: _nonNegative(parserMap[key], 'parser.$key'),
    };
    final String captureMethod = _id(root['capture_method'], 'capture_method');
    final String product = _id(root['product'], 'product');
    final String productVersion = _token(
      root['product_version'],
      'product_version',
    );
    return TerminalApplicationRawEvidence(
      applicationId: applicationId,
      scenarioId: scenarioId,
      captureMethod: captureMethod,
      product: product,
      productVersion: productVersion,
      output: output,
      samples: List<TerminalApplicationRawSample>.unmodifiable(samples),
      resizes: List<TerminalApplicationRawResize>.unmodifiable(resizes),
      exitCode: exitCode,
      signal: signal,
      parser: Map<String, int>.unmodifiable(parser),
    );
  }
}

final class TerminalApplicationRawSample {
  const TerminalApplicationRawSample({
    required this.stage,
    required this.outputBytes,
    required this.snapshot,
    required this.cursorBounded,
  });

  final String stage;
  final int outputBytes;
  final String snapshot;
  final bool cursorBounded;

  static TerminalApplicationRawSample parse(
    Object? value, {
    required String expectedStage,
  }) {
    final Map<String, Object?> map = _object(value, 'sample');
    _keys(map, const <String>{
      'stage',
      'output_bytes',
      'snapshot_sha256',
      'cursor_bounded',
      'snapshot',
    }, 'sample');
    _expect(map['stage'] == expectedStage, 'sample stages differ');
    final String snapshot = _text(
      map['snapshot'],
      'sample.snapshot',
      512 * 1024,
    );
    _expect(
      RegExp(r'^dart-terminal-state-snapshot version=(1|2|3) ')
              .hasMatch(snapshot) &&
          snapshot.endsWith('end\n'),
      'sample snapshot envelope is invalid',
    );
    _expect(
      map['snapshot_sha256'] ==
          terminalDifferentialSha256(utf8.encode(snapshot)),
      'sample snapshot hash differs',
    );
    for (final String forbidden in _privateContentTokens) {
      _expect(!snapshot.contains(forbidden), 'snapshot contains private data');
    }
    return TerminalApplicationRawSample(
      stage: expectedStage,
      outputBytes: _nonNegative(map['output_bytes'], 'sample.output_bytes'),
      snapshot: snapshot,
      cursorBounded: _boolean(map['cursor_bounded'], 'cursor_bounded'),
    );
  }
}

final class TerminalApplicationRawResize {
  const TerminalApplicationRawResize({
    required this.rows,
    required this.columns,
    required this.outputBytesBefore,
    required this.outputBytesAfter,
    required this.screenRows,
    required this.screenColumns,
  });

  final int rows;
  final int columns;
  final int outputBytesBefore;
  final int outputBytesAfter;
  final int screenRows;
  final int screenColumns;

  bool get observed => rows == screenRows && columns == screenColumns;

  static TerminalApplicationRawResize parse(Object? value) {
    final Map<String, Object?> map = _object(value, 'resize');
    _keys(map, const <String>{
      'rows',
      'columns',
      'output_bytes_before',
      'output_bytes_after',
      'screen_rows',
      'screen_columns',
    }, 'resize');
    final int before = _nonNegative(
      map['output_bytes_before'],
      'resize.output_bytes_before',
    );
    final int after = _nonNegative(
      map['output_bytes_after'],
      'resize.output_bytes_after',
    );
    _expect(after >= before, 'resize output count moved backwards');
    return TerminalApplicationRawResize(
      rows: _positive(map['rows'], 'resize.rows'),
      columns: _positive(map['columns'], 'resize.columns'),
      outputBytesBefore: before,
      outputBytesAfter: after,
      screenRows: _positive(map['screen_rows'], 'resize.screen_rows'),
      screenColumns: _positive(map['screen_columns'], 'resize.screen_columns'),
    );
  }
}

final class _ReviewedSource {
  const _ReviewedSource({
    required this.applicationId,
    required this.version,
    required this.executableSha256,
  });

  final String applicationId;
  final String version;
  final String executableSha256;
}

Map<String, _ReviewedSource> _parseSources(Object? value) {
  final List<Object?> values = _array(value, 'sources');
  _expect(values.length == 8, 'sources must contain eight applications');
  final Map<String, _ReviewedSource> result = <String, _ReviewedSource>{};
  String previous = '';
  for (int index = 0; index < values.length; index++) {
    final Map<String, Object?> source = _object(
      values[index],
      'sources[$index]',
    );
    final String application = _id(
      source['application_id'],
      'source.application_id',
    );
    final Set<String> expected = <String>{
      'application_id',
      'version',
      'acquisition',
      'distribution',
      'distribution_sha256',
      'executable_sha256',
      if (application == 'ncurses') ...<String>{
        'fixture_path',
        'fixture_sha256',
      },
      if (application == 'tmux') 'build_input',
    };
    _keys(source, expected, 'source $application');
    _expect(
      previous.isEmpty || previous.compareTo(application) < 0,
      'sources must be sorted by application id',
    );
    previous = application;
    _expect(!result.containsKey(application), 'duplicate source $application');
    final Map<String, String>? pinned = _pinnedSources[application];
    _expect(pinned != null, 'unknown source $application');
    final String version = _token(source['version'], 'source.version');
    _expect(
      version == pinned!['version'],
      '$application version is not pinned',
    );
    _expect(
      source['acquisition'] == pinned['acquisition'] &&
          source['distribution'] == pinned['distribution'] &&
          source['distribution_sha256'] == pinned['distribution_sha256'],
      '$application distribution provenance differs',
    );
    final String executableHash = _sha256(
      source['executable_sha256'],
      'source.executable_sha256',
    );
    if (application == 'ncurses') {
      final String fixturePath = _reviewedPath(
        source['fixture_path'],
        'source.fixture_path',
        exact: 'test/corpus/applications/support/ncurses_resize_fixture.c',
      );
      _hashMatches(
        File(fixturePath),
        source['fixture_sha256'],
        'ncurses fixture',
      );
    } else if (application == 'tmux') {
      final Map<String, Object?> build = _object(
        source['build_input'],
        'tmux build_input',
      );
      _keys(build, const <String>{
        'product',
        'version',
        'sha256',
      }, 'build_input');
      _expect(
        build['product'] == 'libevent' &&
            build['version'] == '2.1.13-stable' &&
            build['sha256'] == 'f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c',
        'tmux build input differs',
      );
    }
    result[application] = _ReviewedSource(
      applicationId: application,
      version: version,
      executableSha256: executableHash,
    );
  }
  _expect(
    result.keys.toSet().containsAll(
      TerminalApplicationMatrixManifest.requiredApplicationIds,
    ),
    'source set differs from required applications',
  );
  return result;
}

void _crossCheck({
  required TerminalApplicationScenario scenario,
  required _ReviewedSource source,
  required TerminalApplicationObservation observation,
  required TerminalApplicationRawEvidence raw,
  required Map<String, Object?> environment,
}) {
  _expect(source.applicationId == scenario.applicationId, 'source mismatch');
  _expect(
    observation.provenance.productVersion == source.version &&
        observation.provenance.executableSha256 == source.executableSha256,
    '${scenario.id} executable provenance differs',
  );
  _expect(
    observation.provenance.product == raw.product &&
        observation.provenance.productVersion == raw.productVersion &&
        observation.provenance.captureMethod == raw.captureMethod &&
        observation.provenance.captureMethod == environment['capture_method'] &&
        observation.provenance.operatingSystem == environment['os'] &&
        observation.provenance.architecture == environment['architecture'],
    '${scenario.id} capture provenance differs',
  );
  _expect(
    observation.outputBytes == raw.output.length &&
        observation.outputSha256 == terminalDifferentialSha256(raw.output),
    '${scenario.id} output observation differs',
  );
  final String marker = _markers[scenario.applicationId]!;
  final Map<String, bool> derived = <String, bool>{
    'clean-exit': raw.exitCode == 0 && raw.signal == null,
    'cursor-bounded': raw.samples.every((sample) => sample.cursorBounded),
    'marker-visible': raw.samples.any(
      (TerminalApplicationRawSample sample) => sample.snapshot.contains(marker),
    ),
    'parser-clean': const <String>[
      'unsupported_controls',
      'unsupported_sequences',
      'cancel',
      'limit',
      'malformed',
      'incomplete',
    ].every((String key) => raw.parser[key] == 0),
    'primary-restored': raw.samples.last.snapshot.contains(
      'set active=primary mode1049=false ',
    ),
    'resize-observed':
        raw.resizes.length == 2 &&
        raw.resizes.every((resize) => resize.observed),
  };
  for (final TerminalApplicationCheckResult check in observation.checks) {
    _expect(
      derived[check.id] == check.passed,
      '${scenario.id} check ${check.id} differs from raw evidence',
    );
  }
}

const Map<String, String> _markers = <String, String>{
  'emacs': 'DART_MATRIX_EMACS',
  'fzf': 'DART_MATRIX_FZF',
  'lazygit': 'DART_MATRIX_LAZYGIT',
  'mosh': 'DART_MATRIX_MOSH',
  'ncurses': 'DART_MATRIX_NCURSES',
  'neovim': 'DART_MATRIX_NEOVIM',
  'ssh': 'DART_MATRIX_SSH',
  'tmux': 'DART_MATRIX_TMUX',
};

const List<String> _privateContentTokens = <String>[
  '/Users/',
  'MOSH_KEY',
  'BEGIN OPENSSH',
  'authorized_keys',
  'client_ed25519',
  'host_ed25519',
];

const Map<String, Map<String, String>>
_pinnedSources = <String, Map<String, String>>{
  'emacs': <String, String>{
    'version': '31.1',
    'acquisition': 'source-build-minimal-terminal',
    'distribution': 'https://ftp.gnu.org/gnu/emacs/emacs-31.1.tar.xz',
    'distribution_sha256':
        '1da5790d9580c81932b5bf700633114468da7b3412d69faa767daebf974f4586',
  },
  'fzf': <String, String>{
    'version': '0.74.3',
    'acquisition': 'upstream-arm64-archive',
    'distribution':
        'https://github.com/junegunn/fzf/releases/download/v0.74.3/'
        'fzf-0.74.3-darwin_arm64.tar.gz',
    'distribution_sha256':
        '1f8501cea4f9c0c2d6110d0ff75d0ec9451cd9d7524d9a26244a154ea89f3bd5',
  },
  'lazygit': <String, String>{
    'version': '0.65.0',
    'acquisition': 'upstream-arm64-archive',
    'distribution':
        'https://github.com/jesseduffield/lazygit/releases/download/v0.65.0/'
        'lazygit_0.65.0_darwin_arm64.tar.gz',
    'distribution_sha256':
        'd8ea1cade9e4279e45cbb58652e84edb07e98a9f8ec0604099c8b0a8f709e63a',
  },
  'mosh': <String, String>{
    'version': '1.4.0',
    'acquisition': 'upstream-universal-package',
    'distribution':
        'https://github.com/mobile-shell/mosh/releases/download/mosh-1.4.0/'
        'mosh-1.4.0.pkg',
    'distribution_sha256':
        '14d3ef7e0a0dfff7b284102d44da91f88a24921bbb07ff2ac6875e7075a4b207',
  },
  'ncurses': <String, String>{
    'version': '6.6.20251230',
    'acquisition': 'homebrew-library-plus-reviewed-fixture',
    'distribution': 'https://formulae.brew.sh/formula/ncurses',
    'distribution_sha256':
        'c3881a5cfce214efe54744a4664f18b7cea5caa86ff87e0231244809c1386a50',
  },
  'neovim': <String, String>{
    'version': '0.12.2',
    'acquisition': 'upstream-arm64-archive',
    'distribution':
        'https://github.com/neovim/neovim/releases/download/v0.12.2/'
        'nvim-macos-arm64.tar.gz',
    'distribution_sha256':
        'eeddee1009734f9071266e6b1b8a70308cb60cbcc45f5e1c1023adc471450fee',
  },
  'ssh': <String, String>{
    'version': '10.3p1-libressl-3.3.6',
    'acquisition': 'macos-system-binary',
    'distribution': 'macos-system:/usr/bin/ssh',
    'distribution_sha256':
        '17542914a3fb55e7efeb35a90d594a21c84bf6a4cfe1fc8ddff5606dc2658fc3',
  },
  'tmux': <String, String>{
    'version': '3.6b',
    'acquisition': 'source-build-libevent-static',
    'distribution':
        'https://github.com/tmux/tmux/releases/download/3.6b/tmux-3.6b.tar.gz',
    'distribution_sha256':
        '390759d25fdba016887ec982b808927e637070fd7d03a8021f8ef3102b9ae3c7',
  },
};

String _evidencePath(Object? value, String scenarioId, String suffix) =>
    _reviewedPath(
      value,
      'evidence path',
      exact: 'test/corpus/applications/external/$scenarioId.$suffix',
    );

String _reviewedPath(Object? value, String context, {required String exact}) {
  final String path = _text(value, context, 256);
  _expect(path == exact, '$context differs from reviewed path');
  return path;
}

void _hashMatches(
  File file,
  Object? expected,
  String context, {
  int maximumBytes = 1024 * 1024,
}) {
  _regularFile(file, maximumBytes: maximumBytes, context: context);
  final String hash = _sha256(expected, '$context hash');
  _expect(
    terminalDifferentialSha256(file.readAsBytesSync()) == hash,
    '$context hash differs',
  );
}

void _regularFile(
  File file, {
  required int maximumBytes,
  required String context,
}) {
  _expect(file.existsSync(), '$context does not exist');
  _expect(
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file,
    '$context must be a regular file',
  );
  final int length = file.lengthSync();
  _expect(
    length > 0 && length <= maximumBytes,
    '$context size is outside bounds',
  );
}

Map<String, Object?> _decodeObject(String source, String context) {
  try {
    return _object(jsonDecode(source), context);
  } on TerminalApplicationEvidenceException {
    rethrow;
  } on Object catch (error) {
    throw TerminalApplicationEvidenceException(
      '$context is invalid JSON: $error',
    );
  }
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw TerminalApplicationEvidenceException('$context must be an object');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw TerminalApplicationEvidenceException('$context has non-string key');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  if (value is! List<Object?>) {
    throw TerminalApplicationEvidenceException('$context must be an array');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> expected, String context) {
  final Set<String> actual = value.keys.toSet();
  _expect(
    actual.length == expected.length && actual.containsAll(expected),
    '$context keys differ',
  );
}

String _text(Object? value, String context, int maximumLength) {
  if (value is! String || value.isEmpty || value.length > maximumLength) {
    throw TerminalApplicationEvidenceException('$context is invalid text');
  }
  return value;
}

String _id(Object? value, String context) {
  final String result = _text(value, context, 96);
  _expect(
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(result),
    '$context is not an identifier',
  );
  return result;
}

String _token(Object? value, String context) {
  final String result = _text(value, context, 96);
  _expect(
    RegExp(r'^[A-Za-z0-9._+-]+$').hasMatch(result),
    '$context is not a token',
  );
  return result;
}

String _sha256(Object? value, String context) {
  final String result = _text(value, context, 64);
  _expect(
    RegExp(r'^[0-9a-f]{64}$').hasMatch(result),
    '$context is not SHA-256',
  );
  return result;
}

int _integer(Object? value, String context) {
  if (value is! int) {
    throw TerminalApplicationEvidenceException('$context is not an integer');
  }
  return value;
}

int _nonNegative(Object? value, String context) {
  final int result = _integer(value, context);
  _expect(result >= 0, '$context must be non-negative');
  return result;
}

int _positive(Object? value, String context) {
  final int result = _integer(value, context);
  _expect(result > 0, '$context must be positive');
  return result;
}

bool _boolean(Object? value, String context) {
  if (value is! bool) {
    throw TerminalApplicationEvidenceException('$context is not a boolean');
  }
  return value;
}

void _expect(bool condition, String message) {
  if (!condition) throw TerminalApplicationEvidenceException(message);
}

void main(List<String> arguments) {
  try {
    if (arguments.isNotEmpty &&
        !(arguments.length == 1 && arguments.single == '--check')) {
      throw const TerminalApplicationEvidenceException(
        'usage: terminal_application_evidence.dart [--check]',
      );
    }
    stdout.writeln(runTerminalApplicationEvidenceChecks().machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_APPLICATION_EVIDENCE_FAIL $error');
    exitCode = 1;
  }
}
