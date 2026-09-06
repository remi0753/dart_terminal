import 'dart:convert';
import 'dart:io';

import 'terminal_application_matrix.dart';
import 'terminal_differential_sha256.dart';

const String _matrixPath = 'test/corpus/applications/matrix_v1.json';
const String _captureDriverPath =
    'tool/terminal_application_capture_driver.dart';
const String _evidenceRoot = 'test/corpus/applications/external';
const String _indexPath = 'compatibility/application_matrix_evidence.json';

Future<void> main(List<String> arguments) async {
  try {
    final String artifactRoot = _artifactRoot(arguments);
    final TerminalApplicationMatrixManifest manifest =
        TerminalApplicationMatrixManifest.load(File(_matrixPath));
    final Directory evidenceRoot = Directory(_evidenceRoot).absolute;
    final List<Object?> cells = <Object?>[];
    for (final TerminalApplicationScenario scenario in manifest.scenarios) {
      final TerminalApplicationDriverResult result =
          await TerminalApplicationSubprocessDriver(
            timeout: Duration(milliseconds: scenario.deadlineMs + 5000),
          ).run(
            executable: Platform.resolvedExecutable,
            arguments: <String>[
              File(_captureDriverPath).absolute.path,
              '--artifact-root=$artifactRoot',
              '--evidence-root=${evidenceRoot.path}',
            ],
            scenario: scenario,
          );
      stdout.writeln(result.machineLine(scenario));
      if (result.status != TerminalApplicationDriverStatus.ok ||
          result.observation == null) {
        throw StateError(
          '${scenario.id} capture failed with ${result.status.name}',
        );
      }
      final TerminalApplicationObservation observation = result.observation!;
      final String observationPath =
          '$_evidenceRoot/${scenario.id}.observation.json';
      final File observationFile = File(observationPath);
      observationFile.parent.createSync(recursive: true);
      observationFile.writeAsStringSync(observation.encode(), flush: true);
      final String rawPath = '$_evidenceRoot/${scenario.id}.capture.json';
      final File rawFile = File(rawPath);
      if (!rawFile.existsSync()) {
        throw StateError('${scenario.id} raw capture is missing');
      }
      cells.add(<String, Object?>{
        'application_id': scenario.applicationId,
        'scenario_id': scenario.id,
        'status': 'captured',
        'observation_path': observationPath,
        'observation_sha256': terminalDifferentialSha256(
          observationFile.readAsBytesSync(),
        ),
        'raw_evidence_path': rawPath,
        'raw_evidence_sha256': terminalDifferentialSha256(
          rawFile.readAsBytesSync(),
        ),
      });
    }
    final Map<String, String> executableHashes = <String, String>{};
    for (final Object? value in cells) {
      final Map<String, Object?> cell = value! as Map<String, Object?>;
      executableHashes[cell['application_id']!
          as String] = TerminalApplicationObservation.parse(
        File(cell['observation_path']! as String).readAsStringSync(),
        scenario: manifest.scenarios.singleWhere(
          (TerminalApplicationScenario scenario) =>
              scenario.id == cell['scenario_id'],
        ),
      ).provenance.executableSha256;
    }
    final File ncursesLibrary = File(
      '/opt/homebrew/opt/ncurses/lib/libncursesw.6.dylib',
    );
    final Map<String, Object?> index = <String, Object?>{
      'format': 'dart-terminal-application-evidence-index',
      'version': 1,
      'matrix_path': _matrixPath,
      'matrix_sha256': terminalDifferentialSha256(
        File(_matrixPath).readAsBytesSync(),
      ),
      'capture_driver_path': _captureDriverPath,
      'capture_driver_sha256': terminalDifferentialSha256(
        File(_captureDriverPath).readAsBytesSync(),
      ),
      'environment': <String, Object?>{
        'os': 'macos-26-6-2',
        'architecture': 'arm64',
        'dart': Platform.version.split(' ').first,
        'capture_method': 'developer-jit-product-pty-v1',
      },
      'sources': _sources(executableHashes, ncursesLibrary),
      'cells': cells,
    };
    final File indexFile = File(_indexPath);
    indexFile.parent.createSync(recursive: true);
    indexFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(index)}\n',
      flush: true,
    );
    stdout.writeln(
      'TERMINAL_APPLICATION_EVIDENCE_GENERATED cells=${cells.length}',
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_APPLICATION_EVIDENCE_GENERATION_FAIL $error');
    exitCode = 1;
  }
}

String _artifactRoot(List<String> arguments) {
  if (arguments.length != 1 ||
      !arguments.single.startsWith('--artifact-root=')) {
    throw ArgumentError('usage: --artifact-root=/absolute/path');
  }
  final String result = arguments.single.substring('--artifact-root='.length);
  if (!result.startsWith('/') || !Directory(result).existsSync()) {
    throw ArgumentError.value(result, 'artifact-root', 'must exist');
  }
  return result;
}

List<Object?> _sources(
  Map<String, String> executableHashes,
  File ncursesLibrary,
) => <Object?>[
  _source(
    'emacs',
    '31.1',
    'source-build-minimal-terminal',
    'https://ftp.gnu.org/gnu/emacs/emacs-31.1.tar.xz',
    '1da5790d9580c81932b5bf700633114468da7b3412d69faa767daebf974f4586',
    executableHashes['emacs']!,
  ),
  _source(
    'fzf',
    '0.74.3',
    'upstream-arm64-archive',
    'https://github.com/junegunn/fzf/releases/download/v0.74.3/'
        'fzf-0.74.3-darwin_arm64.tar.gz',
    '1f8501cea4f9c0c2d6110d0ff75d0ec9451cd9d7524d9a26244a154ea89f3bd5',
    executableHashes['fzf']!,
  ),
  _source(
    'lazygit',
    '0.65.0',
    'upstream-arm64-archive',
    'https://github.com/jesseduffield/lazygit/releases/download/v0.65.0/'
        'lazygit_0.65.0_darwin_arm64.tar.gz',
    'd8ea1cade9e4279e45cbb58652e84edb07e98a9f8ec0604099c8b0a8f709e63a',
    executableHashes['lazygit']!,
  ),
  _source(
    'mosh',
    '1.4.0',
    'upstream-universal-package',
    'https://github.com/mobile-shell/mosh/releases/download/mosh-1.4.0/'
        'mosh-1.4.0.pkg',
    '14d3ef7e0a0dfff7b284102d44da91f88a24921bbb07ff2ac6875e7075a4b207',
    executableHashes['mosh']!,
  ),
  <String, Object?>{
    ..._source(
      'ncurses',
      '6.6.20251230',
      'homebrew-library-plus-reviewed-fixture',
      'https://formulae.brew.sh/formula/ncurses',
      terminalDifferentialSha256(ncursesLibrary.readAsBytesSync()),
      executableHashes['ncurses']!,
    ),
    'fixture_path': 'test/corpus/applications/support/ncurses_resize_fixture.c',
    'fixture_sha256': terminalDifferentialSha256(
      File('test/corpus/applications/support/ncurses_resize_fixture.c')
          .readAsBytesSync(),
    ),
  },
  _source(
    'neovim',
    '0.12.2',
    'upstream-arm64-archive',
    'https://github.com/neovim/neovim/releases/download/v0.12.2/'
        'nvim-macos-arm64.tar.gz',
    'eeddee1009734f9071266e6b1b8a70308cb60cbcc45f5e1c1023adc471450fee',
    executableHashes['neovim']!,
  ),
  _source(
    'ssh',
    '10.3p1-libressl-3.3.6',
    'macos-system-binary',
    'macos-system:/usr/bin/ssh',
    executableHashes['ssh']!,
    executableHashes['ssh']!,
  ),
  <String, Object?>{
    ..._source(
      'tmux',
      '3.6b',
      'source-build-libevent-static',
      'https://github.com/tmux/tmux/releases/download/3.6b/'
          'tmux-3.6b.tar.gz',
      '390759d25fdba016887ec982b808927e637070fd7d03a8021f8ef3102b9ae3c7',
      executableHashes['tmux']!,
    ),
    'build_input': <String, Object?>{
      'product': 'libevent',
      'version': '2.1.13-stable',
      'sha256':
          'f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c',
    },
  },
];

Map<String, Object?> _source(
  String applicationId,
  String version,
  String acquisition,
  String distribution,
  String distributionSha256,
  String executableSha256,
) => <String, Object?>{
  'application_id': applicationId,
  'version': version,
  'acquisition': acquisition,
  'distribution': distribution,
  'distribution_sha256': distributionSha256,
  'executable_sha256': executableSha256,
};
