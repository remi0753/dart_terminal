import 'dart:io';

import 'terminal_compatibility_inventory.dart';
import 'terminal_differential_adapters.dart';
import 'terminal_differential_corpus.dart';
import 'terminal_differential_harness.dart';

const String defaultExternalDifferentialCaptureDirectory =
    'test/corpus/differential/external';

final class TerminalDifferentialCaptureException implements Exception {
  const TerminalDifferentialCaptureException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDifferentialCaptureException: $message';
}

Future<void> main(List<String> arguments) async {
  try {
    final Map<String, String> values = _parse(arguments);
    final Directory repositoryRoot = Directory.current.absolute;
    final TerminalDifferentialBackendCatalog catalog =
        TerminalDifferentialBackendCatalog.load(
          File(defaultTerminalDifferentialBackendsPath),
          repositoryRoot: repositoryRoot,
        );
    final TerminalCompatibilityInventory inventory =
        TerminalCompatibilityInventory.load(
          File(defaultTerminalCompatibilityInventoryPath),
          repositoryRoot: repositoryRoot,
        );
    final String manifestPath =
        values['manifest'] ?? defaultReviewedDifferentialManifestPath;
    final TerminalDifferentialManifest manifest =
        TerminalDifferentialManifest.load(
          File.fromUri(repositoryRoot.uri.resolve(manifestPath)),
          inventoryIds: <String>{
            for (final TerminalCompatibilityRecord record in inventory.records)
              record.id,
          },
        );
    _expect(manifest.scope == 'reviewed-corpus', 'manifest scope differs');
    final String profileId = values['profile']!;
    final TerminalDifferentialBackendProfile profile = catalog.profile(
      profileId,
    );
    final TerminalDifferentialAdapterOptions options =
        TerminalDifferentialAdapterOptions(
          executable: values['executable'],
          appBundle: values['app-bundle'],
          display: values['display'],
        );
    final Directory temporary = Directory.systemTemp.createTempSync(
      'dart-terminal-differential-corpus-$profileId-',
    );
    try {
      final TerminalDifferentialExternalAdapter adapter =
          TerminalDifferentialExternalAdapter(repositoryRoot: repositoryRoot);
      for (final TerminalDifferentialCase testCase in manifest.cases) {
        await adapter.capture(
          profile: profile,
          testCase: testCase,
          options: options,
          rawProbeDestination: File.fromUri(
            temporary.uri.resolve('${testCase.id}.probe.json'),
          ),
        );
      }
      final Directory destination = Directory.fromUri(
        repositoryRoot.uri.resolve(
          '${values['destination'] ?? '$defaultExternalDifferentialCaptureDirectory/$profileId'}/',
        ),
      );
      destination.createSync(recursive: true);
      final Set<String> expectedNames = <String>{
        for (final TerminalDifferentialCase testCase in manifest.cases)
          '${testCase.id}.probe.json',
      };
      final Set<String> actualNames = <String>{
        for (final FileSystemEntity entity in destination.listSync())
          if (entity is File && entity.path.endsWith('.probe.json'))
            entity.uri.pathSegments.last,
      };
      _expect(
        actualNames.difference(expectedNames).isEmpty,
        'destination contains an unexpected probe',
      );
      for (final String name in expectedNames) {
        final File source = File.fromUri(temporary.uri.resolve(name));
        final File output = File.fromUri(destination.uri.resolve(name));
        output.writeAsBytesSync(source.readAsBytesSync(), flush: true);
      }
    } finally {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    }
    stdout.writeln(
      'TERMINAL_DIFFERENTIAL_CAPTURE_PASS backend=$profileId '
      'cases=${manifest.cases.length}',
    );
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_CAPTURE_FAIL $error');
    exitCode = 1;
  }
}

Map<String, String> _parse(List<String> arguments) {
  final Map<String, String> result = <String, String>{};
  for (final String argument in arguments) {
    _expect(
      argument.startsWith('--') && argument.contains('='),
      'invalid option',
    );
    final int separator = argument.indexOf('=');
    final String name = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    _expect(
      const <String>{
            'profile',
            'executable',
            'app-bundle',
            'display',
            'manifest',
            'destination',
          }.contains(name) &&
          value.isNotEmpty &&
          !result.containsKey(name) &&
          !_hasControl(value),
      'invalid option',
    );
    result[name] = value;
  }
  _expect(result.containsKey('profile'), 'profile is required');
  for (final String name in const <String>['executable', 'app-bundle']) {
    _expect(
      !result.containsKey(name) || result[name]!.startsWith('/'),
      '$name must be absolute',
    );
  }
  for (final String name in const <String>['manifest', 'destination']) {
    if (!result.containsKey(name)) continue;
    final String path = result[name]!;
    _expect(
      !path.startsWith('/') &&
          !path.contains('\\') &&
          path
              .split('/')
              .every(
                (String segment) =>
                    segment.isNotEmpty && segment != '.' && segment != '..',
              ),
      '$name must be a safe relative path',
    );
  }
  return result;
}

bool _hasControl(String value) =>
    value.codeUnits.any((int unit) => unit < 0x20 || unit == 0x7f);

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDifferentialCaptureException(message);
}
