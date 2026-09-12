import 'dart:convert';
import 'dart:io';

final class _AuditException implements Exception {
  const _AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> main() async {
  try {
    final ProcessResult trackedResult = await Process.run('git', const <String>[
      'ls-files',
    ]);
    _expect(trackedResult.exitCode == 0, 'could not enumerate tracked files');
    final List<String> tracked = const LineSplitter()
        .convert(trackedResult.stdout as String)
        .where((String path) => path.isNotEmpty)
        .toList();
    const Set<String> nativeExtensions = <String>{
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.m',
      '.mm',
      '.metal',
    };
    const Set<String> reviewedTestNativeSources = <String>{
      'test/corpus/applications/support/ncurses_resize_fixture.c',
    };
    final List<String> nativeSources = tracked
        .where(
          (String path) =>
              File(path).existsSync() &&
              nativeExtensions.any(path.toLowerCase().endsWith),
        )
        .toList();
    final List<String> productNativeSources = nativeSources
        .where((String path) => !reviewedTestNativeSources.contains(path))
        .toList();
    _expect(
      productNativeSources.isEmpty,
      'product repository contains native source: '
      '${productNativeSources.join(', ')}',
    );
    for (final String path in reviewedTestNativeSources) {
      _expect(
        nativeSources.contains(path) && File(path).existsSync(),
        'reviewed test native source is missing: $path',
      );
      _expect(
        path.startsWith('test/corpus/applications/support/'),
        'reviewed native source escaped the test corpus: $path',
      );
    }

    final String makefile = await File('Makefile').readAsString();
    for (final String forbidden in <String>[
      '/native/bridge',
      '/native/runner',
      '/native/macos',
      'clang++',
      'xcrun',
      'TerminalMetalView.mm',
      'DeveloperJitRunner.mm',
      'ReleaseAotRunner.mm',
    ]) {
      _expect(
        !makefile.contains(forbidden),
        'application build references an internal native path: $forbidden',
      );
    }

    final List<String> productSourcePaths = <String>[
      'Makefile',
      'macos_application.json',
      ...tracked.where(
        (String path) =>
            (path.startsWith('bin/') || path.startsWith('lib/')) &&
            File(path).existsSync(),
      ),
    ];
    for (final String fixturePath in reviewedTestNativeSources) {
      for (final String productPath in productSourcePaths) {
        final String source = await File(productPath).readAsString();
        _expect(
          !source.contains(fixturePath),
          'product build/source references test native source: '
          '$productPath -> $fixturePath',
        );
      }
    }

    for (final String path in tracked.where(
      (String path) =>
          (path.startsWith('bin/') || path.startsWith('lib/')) &&
          path.endsWith('.dart') &&
          File(path).existsSync(),
    )) {
      final String source = await File(path).readAsString();
      _expect(
        !source.contains("import 'dart:ffi';"),
        'application source owns a direct FFI boundary: $path',
      );
      _expect(
        !source.contains('DynamicLibrary.'),
        'application source loads a native image directly: $path',
      );
    }

    final String terminalApplication = await File(
      'lib/src/terminal_application.dart',
    ).readAsString();
    for (final String required in <String>[
      'TerminalRendererMacos.createView()',
      'TerminalLiveMetalSurface.attach(',
      'screenSet: terminalSession!.terminalScreenSet',
    ]) {
      _expect(
        terminalApplication.contains(required),
        'product terminal omits its default Metal connection: $required',
      );
    }
    for (final String forbidden in <String>[
      'TextView(',
      'createdPane.render()',
      'DT_RUNTIME_CUSTOM_VIEW_TEST',
    ]) {
      _expect(
        !terminalApplication.contains(forbidden),
        'product terminal retains a legacy display path: $forbidden',
      );
    }

    final Map<String, Object?> manifest = jsonDecode(
      await File('macos_application.json').readAsString(),
    ) as Map<String, Object?>;
    final List<Object?> assets = manifest['nativeAssets']! as List<Object?>;
    final List<Object?> capabilities =
        manifest['nativeCapabilities']! as List<Object?>;
    final List<Object?> helpers = manifest['dartHelpers']! as List<Object?>;
    final Map<String, Object?> appIntents =
        manifest['appIntents']! as Map<String, Object?>;
    _expect(
      (assets.single! as Map<String, Object?>)['package'] == 'dart_pty_macos',
      'PTY package is not declared as a native asset',
    );
    final Map<String, Map<String, Object?>> capabilitiesById =
        <String, Map<String, Object?>>{
          for (final Map<String, Object?> value
              in capabilities.cast<Map<String, Object?>>())
            value['id']! as String: value,
        };
    _expect(
      capabilitiesById.length == 2 &&
          capabilitiesById['dart_terminal_renderer_macos']?['package'] ==
              'dart_terminal_renderer_macos' &&
          capabilitiesById['dart_terminal_applescript_macos']?['package'] ==
              'dart_terminal_applescript_macos' &&
          _exactEntries(
            capabilitiesById['dart_terminal_applescript_macos']!,
            const <String, Object>{
              'id': 'dart_terminal_applescript_macos',
              'package': 'dart_terminal_applescript_macos',
              'library': 'libdart_terminal_applescript_macos.dylib',
              'abiVersion': 1,
              'abiVersionSymbol': 'dtas_abi_version',
              'initializerSymbol': 'dtas_initialize',
            },
          ),
      'terminal native capability declarations do not match',
    );
    final Map<String, Object?> scriptingDefinition =
        manifest['scriptingDefinition']! as Map<String, Object?>;
    _expect(
      scriptingDefinition.length == 1 &&
          scriptingDefinition['path'] == 'resources/DartTerminal.sdef',
      'terminal scripting definition declaration does not match',
    );
    _expect(
      _exactEntries(appIntents, const <String, Object>{
        'package': 'dart_terminal_app_intents_macos',
        'source': 'native/TerminalAppIntents.swift',
        'moduleName': 'DartTerminalAppIntents',
        'library': 'libdart_terminal_app_intents_macos.dylib',
      }),
      'terminal App Intents declaration does not match',
    );
    final File canonicalAppIntents = await _packageFile(
      'dart_terminal_app_intents_macos',
      'native/TerminalAppIntents.swift',
    );
    _expect(
      canonicalAppIntents.existsSync() &&
          canonicalAppIntents.lengthSync() > 0 &&
          canonicalAppIntents.lengthSync() <= 1024 * 1024,
      'canonical terminal App Intents source is missing or outside its bound',
    );
    final Map<String, Object?> packageGraph = jsonDecode(
      await File('.dart_tool/package_graph.json').readAsString(),
    ) as Map<String, Object?>;
    final Map<String, Object?> rootPackage =
        (packageGraph['packages']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .singleWhere(
              (Map<String, Object?> value) => value['name'] == 'dart_terminal',
            );
    _expect(
      (rootPackage['dependencies']! as List<Object?>).contains(
        'dart_terminal_app_intents_macos',
      ),
      'terminal App Intents package is not a direct product dependency',
    );
    final File consumerSdef = File('resources/DartTerminal.sdef');
    final File canonicalSdef = await _packageFile(
      'dart_terminal_applescript_macos',
      'native/DartTerminal.sdef',
    );
    _expect(
      consumerSdef.existsSync() && canonicalSdef.existsSync(),
      'consumer or canonical terminal scripting definition is missing',
    );
    _expect(
      _sameBytes(
        await consumerSdef.readAsBytes(),
        await canonicalSdef.readAsBytes(),
      ),
      'consumer terminal scripting definition differs from the capability',
    );
    _expect(
      (helpers.single! as Map<String, Object?>)['entrypoint'] ==
          'bin/runtime_worker.dart',
      'runtime worker is not a declared Dart helper',
    );
    stdout.writeln(
      'DART_ONLY_SOURCE_AUDIT_PASS tracked=${tracked.length} '
      'product_native_sources=0 '
      'reviewed_test_native_sources=${reviewedTestNativeSources.length}',
    );
  } on Object catch (error) {
    stderr.writeln('DART_ONLY_SOURCE_AUDIT_FAIL $error');
    exitCode = 1;
  }
}

Future<File> _packageFile(String packageName, String relativePath) async {
  final File configuration = File('.dart_tool/package_config.json').absolute;
  final Map<String, Object?> root =
      jsonDecode(await configuration.readAsString()) as Map<String, Object?>;
  final List<Object?> packages = root['packages']! as List<Object?>;
  final Map<String, Object?> package = packages
      .cast<Map<String, Object?>>()
      .singleWhere((Map<String, Object?> item) => item['name'] == packageName);
  final String rootUri = package['rootUri']! as String;
  final Uri resolved = configuration.uri.resolve(
    rootUri.endsWith('/') ? rootUri : '$rootUri/',
  );
  return File.fromUri(resolved.resolve(relativePath));
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _exactEntries(Map<String, Object?> actual, Map<String, Object> expected) {
  if (actual.length != expected.length) return false;
  for (final MapEntry<String, Object> entry in expected.entries) {
    if (actual[entry.key] != entry.value) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw _AuditException(message);
  }
}
