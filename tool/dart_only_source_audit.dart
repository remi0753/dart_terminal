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
      '--cached',
      '--others',
      '--exclude-standard',
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
      '.swift',
    };
    const Set<String> reviewedTestNativeSources = <String>{
      'test/corpus/applications/support/ncurses_resize_fixture.c',
    };
    const Set<String> reviewedToolNativeSources = <String>{
      'tool/macos_ghostty_performance_capture.swift',
      'tool/terminal_differential_macos_activation.swift',
    };
    const Set<String> productPackageNativeRoots = <String>{
      'packages/dart_durable_file_macos/native/',
      'packages/dart_pty_macos/native/',
      'packages/dart_terminal_renderer_macos/native/',
      'packages/dart_terminal_applescript_macos/native/',
      'packages/dart_terminal_app_intents_macos/native/',
      'packages/dart_terminal_notes_macos/native/',
    };
    final List<String> nativeSources = tracked
        .where(
          (String path) =>
              File(path).existsSync() &&
              nativeExtensions.any(path.toLowerCase().endsWith),
        )
        .toList();
    final List<String> productPackageNativeSources = nativeSources
        .where((String path) => productPackageNativeRoots.any(path.startsWith))
        .toList();
    final List<String> applicationNativeSources = nativeSources
        .where(
          (String path) =>
              !reviewedTestNativeSources.contains(path) &&
              !reviewedToolNativeSources.contains(path) &&
              !productPackageNativeRoots.any(path.startsWith),
        )
        .toList();
    _expect(
      applicationNativeSources.isEmpty,
      'application layer contains native source outside an owned package: '
      '${applicationNativeSources.join(', ')}',
    );
    for (final String root in productPackageNativeRoots) {
      _expect(
        productPackageNativeSources.any((String path) => path.startsWith(root)),
        'owned native package is missing its source boundary: $root',
      );
    }
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
    for (final String path in reviewedToolNativeSources) {
      _expect(
        nativeSources.contains(path) && File(path).existsSync(),
        'reviewed tool native source is missing: $path',
      );
      _expect(
        path.startsWith('tool/'),
        'reviewed native tool escaped the tool boundary: $path',
      );
    }

    final String makefile = await File('Makefile').readAsString();
    for (final String forbidden in <String>[
      '/native/runner',
      '/native/macos',
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

    const String processResourcePackagePath =
        'packages/dart_process_resource_macos/lib/src/'
        'current_process_resources.dart';
    final String processResourcePackage = await File(processResourcePackagePath)
        .readAsString();
    final String processResourceFacade = await File(
      'lib/src/terminal_process_resource_sampler.dart',
    ).readAsString();
    _expect(
      tracked.contains(processResourcePackagePath) &&
          processResourcePackage.contains("import 'dart:ffi';") &&
          processResourcePackage.contains('DynamicLibrary.process()') &&
          processResourcePackage.contains('maximumDescriptorScanCount = 65536'),
      'current-process FFI package boundary differs',
    );
    _expect(
      processResourceFacade.contains(
            "import 'package:dart_process_resource_macos/"
            "dart_process_resource_macos.dart';",
          ) &&
          !processResourceFacade.contains("import 'dart:ffi';") &&
          !processResourceFacade.contains('DynamicLibrary.'),
      'application process-resource facade owns a native boundary',
    );

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
    final Map<String, Object?> applicationIcon =
        manifest['icon']! as Map<String, Object?>;
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
      capabilitiesById.length == 3 &&
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
          ) &&
          _exactEntries(
            capabilitiesById['dart_terminal_notes_macos']!,
            const <String, Object>{
              'id': 'dart_terminal_notes_macos',
              'package': 'dart_terminal_notes_macos',
              'library': 'libdart_terminal_notes_macos.dylib',
              'abiVersion': 1,
              'abiVersionSymbol': 'dtn_abi_version',
              'initializerSymbol': 'dtn_initialize',
            },
          ),
      'terminal native capability declarations do not match',
    );
    _expect(
      applicationIcon.length == 1 &&
          applicationIcon['path'] == 'resources/DartTerminal.icns',
      'terminal application icon declaration does not match',
    );
    final List<int> iconMaster = await File('resources/DartTerminalIcon.png')
        .readAsBytes();
    final List<int> applicationIconBytes = await File(
      'resources/DartTerminal.icns',
    ).readAsBytes();
    _expect(
      iconMaster.length > 24 &&
          _sameBytes(iconMaster.sublist(0, 8), const <int>[
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]) &&
          _uint32BigEndian(iconMaster, 16) == 1024 &&
          _uint32BigEndian(iconMaster, 20) == 1024 &&
          applicationIconBytes.length <= 16 * 1024 * 1024 &&
          _sameBytes(applicationIconBytes.sublist(0, 4), const <int>[
            0x69,
            0x63,
            0x6e,
            0x73,
          ]),
      'terminal icon master or ICNS asset is invalid',
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
    final Set<Object?> rootDependencies =
        (rootPackage['dependencies']! as List<Object?>).toSet();
    _expect(
      rootDependencies.contains('dart_terminal_app_intents_macos') &&
          rootDependencies.contains('dart_terminal_notes_macos'),
      'terminal native product packages are not direct dependencies',
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
      'application_native_sources=0 '
      'product_package_native_sources=${productPackageNativeSources.length} '
      'process_resource_ffi_packages=1 '
      'reviewed_test_native_sources=${reviewedTestNativeSources.length} '
      'reviewed_tool_native_sources=${reviewedToolNativeSources.length}',
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

int _uint32BigEndian(List<int> bytes, int offset) =>
    bytes[offset] << 24 |
    bytes[offset + 1] << 16 |
    bytes[offset + 2] << 8 |
    bytes[offset + 3];

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
