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
    _expect(
      (assets.single! as Map<String, Object?>)['package'] == 'dart_pty_macos',
      'PTY package is not declared as a native asset',
    );
    _expect(
      (capabilities.single! as Map<String, Object?>)['package'] ==
          'dart_terminal_renderer_macos',
      'renderer package is not declared as a native capability',
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

void _expect(bool condition, String message) {
  if (!condition) {
    throw _AuditException(message);
  }
}
