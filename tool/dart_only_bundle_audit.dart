import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_differential_sha256.dart';
import 'terminal_terminfo.dart';

final class _AuditException implements Exception {
  const _AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> arguments) async {
  try {
    String? mode;
    String? architecture;
    String? bundlePath;
    for (final String argument in arguments) {
      if (argument.startsWith('--mode=')) {
        mode = argument.substring('--mode='.length);
      } else if (argument.startsWith('--architecture=')) {
        architecture = argument.substring('--architecture='.length);
      } else if (!argument.startsWith('-') && bundlePath == null) {
        bundlePath = argument;
      } else {
        throw _AuditException('unknown or duplicate argument: $argument');
      }
    }
    _expect(
      mode == 'developer-jit' || mode == 'release-aot',
      'mode must be developer-jit or release-aot',
    );
    _expect(
      architecture == 'arm64' ||
          architecture == 'x86_64' ||
          architecture == 'universal',
      'architecture must be arm64, x86_64, or universal',
    );
    final bool universal = architecture == 'universal';
    _expect(
      !universal || mode == 'release-aot',
      'Universal audit requires release-aot mode',
    );
    _expect(bundlePath != null, 'application bundle path is required');

    final Directory bundle = Directory(bundlePath!).absolute;
    _expect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
    final String contents = '${bundle.path}/Contents';
    final String resources = '$contents/Resources';
    final Map<String, Object?> rootManifest = jsonDecode(
      await File('$resources/runtime-build-manifest.json').readAsString(),
    ) as Map<String, Object?>;
    final Map<String, Object?> manifest;
    if (universal) {
      _expect(rootManifest['schemaVersion'] == 2, 'manifest schema mismatch');
      _expect(
        rootManifest['runtimeMode'] == 'release-aot',
        'runtime mode mismatch',
      );
      final Object? architectures = rootManifest['architectures'];
      _expect(
        architectures is List<Object?> &&
            architectures.length == 2 &&
            architectures[0] == 'arm64' &&
            architectures[1] == 'x86_64',
        'Universal architecture evidence mismatch',
      );
      final Object? applicationContract = rootManifest['applicationContract'];
      _expect(
        applicationContract is Map<String, Object?>,
        'Universal application contract is missing',
      );
      manifest = applicationContract! as Map<String, Object?>;
      for (final String key in const <String>[
        'bundleIdentifier',
        'executable',
        'payload',
        'engine',
        'dartSdkVersion',
        'dartSdkRevision',
      ]) {
        _expect(
          rootManifest[key] == manifest[key],
          'Universal top-level $key differs from its application contract',
        );
      }
      for (final String key in const <String>[
        'runner',
        'services',
        'icon',
        'scriptingDefinition',
        'appIntents',
        'dartHelpers',
        'resources',
        'nativeAssets',
        'nativeCapabilities',
      ]) {
        _expect(
          jsonEncode(rootManifest[key]) == jsonEncode(manifest[key]),
          'Universal top-level $key differs from its application contract',
        );
      }
      final Object? thinManifests = rootManifest['thinManifests'];
      _expect(
        thinManifests is Map<String, Object?> &&
            thinManifests.length == 2 &&
            thinManifests.keys.toSet().containsAll(const <String>{
              'arm64',
              'x86_64',
            }) &&
            thinManifests.values.every(
              (Object? value) =>
                  value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
            ),
        'Universal thin manifest ownership evidence mismatch',
      );
      _expect(
        !jsonEncode(rootManifest).contains('/Users/') &&
            !jsonEncode(rootManifest).contains('/dart_appkit/'),
        'Universal evidence contains a build-machine path',
      );
    } else {
      _expect(rootManifest['schemaVersion'] == 1, 'manifest schema mismatch');
      _expect(rootManifest['runtimeMode'] == mode, 'runtime mode mismatch');
      _expect(
        rootManifest['architecture'] == architecture,
        'architecture mismatch',
      );
      manifest = rootManifest;
    }
    _expect(
      manifest['bundleIdentifier'] == 'dev.dart-terminal',
      'bundle identifier mismatch',
    );
    _expect(manifest['executable'] == 'dart_terminal', 'executable mismatch');

    final List<Object?> helpers = manifest['dartHelpers']! as List<Object?>;
    final List<Object?> assets = manifest['nativeAssets']! as List<Object?>;
    final List<Object?> capabilities =
        manifest['nativeCapabilities']! as List<Object?>;
    final Set<String> declaredResources =
        (manifest['resources']! as List<Object?>).cast<String>().toSet();
    const List<String> localizedResources = <String>[
      'en.lproj/InfoPlist.strings',
      'en.lproj/Localizable.strings',
      'en.lproj/AppShortcuts.strings',
      'en.lproj/ServicesMenu.strings',
      'ja.lproj/InfoPlist.strings',
      'ja.lproj/Localizable.strings',
      'ja.lproj/AppShortcuts.strings',
      'ja.lproj/ServicesMenu.strings',
    ];
    _expect(
      declaredResources.containsAll(localizedResources),
      'runtime manifest omitted localization resources',
    );
    final Map<String, Object?> scriptingDefinition =
        manifest['scriptingDefinition']! as Map<String, Object?>;
    final Map<String, Object?> applicationIcon =
        manifest['icon']! as Map<String, Object?>;
    final Map<String, Object?> appIntents =
        manifest['appIntents']! as Map<String, Object?>;
    _expect(helpers.length == 1, 'Dart helper manifest mismatch');
    final Map<String, Object?> helperDeclaration =
        helpers.single! as Map<String, Object?>;
    final String? helperPayload = mode == 'release-aot'
        ? 'DartHelpers/dart_terminal_runtime_worker.aot'
        : null;
    _expect(
      helperDeclaration['name'] == 'dart_terminal_runtime_worker' &&
          helperDeclaration['entrypoint'] == 'bin/runtime_worker.dart' &&
          helperDeclaration['payload'] == helperPayload &&
          helperDeclaration.length == (mode == 'release-aot' ? 3 : 2),
      'Dart helper manifest mismatch',
    );
    _expect(
      assets.length == 1 &&
          (assets.single! as Map<String, Object?>)['id'] == 'dart_pty_macos',
      'PTY asset manifest mismatch',
    );
    final Map<String, Map<String, Object?>> capabilitiesById =
        <String, Map<String, Object?>>{
          for (final Map<String, Object?> value
              in capabilities.cast<Map<String, Object?>>())
            value['id']! as String: value,
        };
    _expect(
      capabilities.length == 3 &&
          capabilitiesById.length == 3 &&
          capabilitiesById.containsKey('dart_terminal_renderer_macos') &&
          capabilitiesById.containsKey('dart_terminal_applescript_macos') &&
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
      'terminal capability manifest mismatch',
    );
    _expect(
      applicationIcon.length == 3 &&
          applicationIcon['source'] == 'resources/DartTerminal.icns' &&
          applicationIcon['bundleName'] == 'DartTerminal.icns' &&
          applicationIcon['bytes'] is int &&
          (applicationIcon['bytes']! as int) > 0,
      'terminal application icon build manifest mismatch',
    );
    _expect(
      scriptingDefinition.length == 3 &&
          scriptingDefinition['source'] == 'resources/DartTerminal.sdef' &&
          scriptingDefinition['bundleName'] == 'DartTerminal.sdef' &&
          scriptingDefinition['bytes'] is int &&
          (scriptingDefinition['bytes']! as int) > 0,
      'terminal scripting definition build manifest mismatch',
    );
    final List<Object?> appIntentsMetadataFiles =
        appIntents['metadataFiles']! as List<Object?>;
    final Map<String, int> appIntentsMetadataBytes = <String, int>{
      for (final Map<String, Object?> value
          in appIntentsMetadataFiles.cast<Map<String, Object?>>())
        value['name']! as String: value['bytes']! as int,
    };
    _expect(
      appIntents.length == (universal ? 9 : 10) &&
          appIntents['package'] == 'dart_terminal_app_intents_macos' &&
          appIntents['source'] == 'native/TerminalAppIntents.swift' &&
          appIntents['moduleName'] == 'DartTerminalAppIntents' &&
          appIntents['library'] == 'libdart_terminal_app_intents_macos.dylib' &&
          appIntents['sourceBytes'] is int &&
          (appIntents['sourceBytes']! as int) > 0 &&
          (universal ||
              (appIntents['libraryBytes'] is int &&
                  (appIntents['libraryBytes']! as int) > 0)) &&
          appIntents['targetTriple'] ==
              (universal
                  ? r'$ARCH-apple-macos14.0'
                  : '$architecture-apple-macos14.0') &&
          appIntents['xcodeBuildVersion'] is String &&
          (appIntents['xcodeBuildVersion']! as String).isNotEmpty &&
          appIntents['metadataBundle'] == 'Metadata.appintents' &&
          appIntentsMetadataFiles.length == 2 &&
          appIntentsMetadataBytes.length == 2 &&
          appIntentsMetadataBytes.keys.toSet().containsAll(const <String>{
            'extract.actionsdata',
            'version.json',
          }),
      'terminal App Intents build manifest mismatch',
    );

    final String executable = '$contents/MacOS/dart_terminal';
    final String helper = '$contents/Helpers/dart_terminal_runtime_worker';
    final String engine =
        '$contents/Frameworks/libdart_engine_${mode == 'developer-jit' ? 'jit' : 'aot'}_shared.dylib';
    final String pty = '$contents/Frameworks/libdart_pty_macos.dylib';
    final String renderer =
        '$contents/Frameworks/libdart_terminal_renderer_macos.dylib';
    final String appleScript =
        '$contents/Frameworks/libdart_terminal_applescript_macos.dylib';
    final String notes =
        '$contents/Frameworks/libdart_terminal_notes_macos.dylib';
    final String appIntentsImage =
        '$contents/Frameworks/libdart_terminal_app_intents_macos.dylib';
    final String applicationIconPath = '$resources/DartTerminal.icns';
    final String scriptingDictionary = '$resources/DartTerminal.sdef';
    final String appIntentsMetadata = '$resources/Metadata.appintents';
    final String appIntentsActions = '$appIntentsMetadata/extract.actionsdata';
    final String appIntentsVersion = '$appIntentsMetadata/version.json';
    final String payload =
        '$resources/${mode == 'developer-jit' ? 'application.dill' : 'application.aot'}';
    final String? helperPayloadPath = helperPayload == null
        ? null
        : '$resources/$helperPayload';
    final List<String> codeImages = <String>[
      executable,
      helper,
      engine,
      pty,
      renderer,
      appleScript,
      notes,
      appIntentsImage,
      if (helperPayloadPath != null) helperPayloadPath,
      if (mode == 'release-aot') payload,
    ];
    if (universal) {
      final List<String> expectedCodePaths =
          codeImages
              .map((String path) => path.substring(bundle.path.length + 1))
              .toList()
            ..sort();
      final Object? declaredCodePaths = rootManifest['codePaths'];
      _expect(
        declaredCodePaths is List<Object?> &&
            _sameStrings(declaredCodePaths.cast<String>(), expectedCodePaths),
        'Universal code path evidence mismatch',
      );
      final Object? declaredResourceFiles = rootManifest['resourceFiles'];
      _expect(
        declaredResourceFiles is List<Object?>,
        'Universal resource evidence is missing',
      );
      final Set<String> evidencePaths = <String>{};
      String previousPath = '';
      for (final Object? value in declaredResourceFiles! as List<Object?>) {
        _expect(
          value is Map<String, Object?> &&
              value.length == 3 &&
              value['path'] is String &&
              value['bytes'] is int &&
              value['sha256'] is String,
          'Universal resource evidence entry is malformed',
        );
        final Map<String, Object?> entry = value! as Map<String, Object?>;
        final String path = entry['path']! as String;
        _expect(
          _safeRelativePath(path) &&
              path.compareTo(previousPath) > 0 &&
              evidencePaths.add(path),
          'Universal resource evidence paths are unsafe or unordered',
        );
        previousPath = path;
        final File file = File('${bundle.path}/$path');
        _expect(
          await file.exists(),
          'Universal evidence file is missing: $path',
        );
        final List<int> bytes = await file.readAsBytes();
        _expect(
          bytes.length == entry['bytes'] &&
              terminalDifferentialSha256(bytes) == entry['sha256'],
          'Universal resource evidence differs from bundle bytes: $path',
        );
      }
      final Set<String> actualNeutralFiles = await _regularBundleFiles(bundle)
        ..removeAll(expectedCodePaths)
        ..remove('Contents/Resources/runtime-build-manifest.json');
      _expect(
        _sameStrings(evidencePaths, actualNeutralFiles),
        'Universal resource evidence does not own the exact neutral inventory',
      );
    }
    final TerminalTerminfoContract terminfoContract =
        TerminalTerminfoContract.load(
          File(defaultTerminalTerminfoContractPath),
        );
    final String terminfo = '$resources/${terminfoContract.compiledPath}';
    final String shellContractPath =
        '$resources/${TerminalShellIntegrationContract.relativePath}';
    final TerminalShellIntegrationContract shellContract =
        TerminalShellIntegrationContract.load(File(shellContractPath));
    final TerminalShellIntegrationResources shellResources = shellContract
        .validateResources(File(shellContractPath).parent);
    for (final String path in <String>[
      '$contents/Info.plist',
      executable,
      helper,
      engine,
      pty,
      renderer,
      appleScript,
      notes,
      appIntentsImage,
      applicationIconPath,
      scriptingDictionary,
      appIntentsActions,
      appIntentsVersion,
      if (helperPayloadPath != null) helperPayloadPath,
      payload,
      '$resources/DART_SDK_LICENSE.txt',
      for (final String relativePath in localizedResources)
        '$resources/$relativePath',
      terminfo,
      shellContractPath,
      for (final TerminalShellIntegrationFileContract file
          in shellContract.files)
        '${shellResources.rootPath}/${file.relativePath}',
    ]) {
      final File file = File(path);
      _expect(await file.exists(), 'required bundle file is missing: $path');
      _expect((await file.stat()).size > 0, 'bundle file is empty: $path');
    }
    final List<int> bundledSdef = await File(scriptingDictionary).readAsBytes();
    final List<int> reviewedSdef = await File('resources/DartTerminal.sdef')
        .readAsBytes();
    _expect(
      _sameBytes(bundledSdef, reviewedSdef) &&
          bundledSdef.length == scriptingDefinition['bytes'],
      'bundled scripting definition differs from its reviewed source',
    );
    final List<int> bundledIcon = await File(applicationIconPath).readAsBytes();
    final List<int> reviewedIcon = await File('resources/DartTerminal.icns')
        .readAsBytes();
    _expect(
      _sameBytes(bundledIcon, reviewedIcon) &&
          bundledIcon.length == applicationIcon['bytes'],
      'bundled application icon differs from its reviewed source',
    );
    for (final String relativePath in localizedResources) {
      _expect(
        _sameBytes(
          await File('$resources/$relativePath').readAsBytes(),
          await File(relativePath).readAsBytes(),
        ),
        'bundled localization resource differs: $relativePath',
      );
    }
    final File canonicalAppIntents = await _packageFile(
      'dart_terminal_app_intents_macos',
      'native/TerminalAppIntents.swift',
    );
    _expect(
      canonicalAppIntents.existsSync() &&
          canonicalAppIntents.lengthSync() == appIntents['sourceBytes'] &&
          (universal ||
              File(appIntentsImage).lengthSync() ==
                  appIntents['libraryBytes']) &&
          File(appIntentsActions).lengthSync() ==
              appIntentsMetadataBytes['extract.actionsdata'] &&
          File(appIntentsVersion).lengthSync() ==
              appIntentsMetadataBytes['version.json'],
      'App Intents source, image, or metadata byte evidence differs',
    );
    final List<String> metadataEntries =
        Directory(appIntentsMetadata)
            .listSync(followLinks: false)
            .map((FileSystemEntity value) => value.uri.pathSegments.last)
            .toList()
          ..sort();
    _expect(
      metadataEntries.join(',') == 'extract.actionsdata,version.json',
      'App Intents metadata bundle contains an unexpected file',
    );
    final Map<String, Object?> actionMetadata = jsonDecode(
      await File(appIntentsActions).readAsString(),
    ) as Map<String, Object?>;
    final Map<String, Object?> actionDeclarations =
        actionMetadata['actions']! as Map<String, Object?>;
    final List<Object?> shortcuts =
        actionMetadata['autoShortcuts']! as List<Object?>;
    final Set<String> actionNames = actionDeclarations.keys.toSet();
    final Set<Object?> shortcutActions = shortcuts
        .map(
          (Object? value) =>
              (value! as Map<String, Object?>)['actionIdentifier'],
        )
        .toSet();
    _expect(
      actionNames.length == 3 &&
          actionNames.containsAll(const <String>{
            'NewTerminalWindowIntent',
            'NewTerminalTabIntent',
            'ToggleQuickTerminalIntent',
          }) &&
          actionDeclarations.values.every(
            (Object? value) =>
                value is Map<String, Object?> &&
                value['openAppWhenRun'] == true &&
                (value['parameters']! as List<Object?>).isEmpty,
          ) &&
          shortcuts.length == 3 &&
          shortcutActions.length == 3 &&
          shortcutActions.containsAll(actionNames),
      'App Intents metadata is not the exact parameterless action set',
    );
    final Map<String, Object?> metadataVersion = jsonDecode(
      await File(appIntentsVersion).readAsString(),
    ) as Map<String, Object?>;
    _expect(
      metadataVersion['toolsVersion'] == appIntents['xcodeBuildVersion'] &&
          metadataVersion['version'] is String &&
          (metadataVersion['version']! as String).isNotEmpty,
      'App Intents metadata tools version differs from build evidence',
    );
    final ProcessResult plistResult = await Process.run(
      '/usr/bin/plutil',
      <String>['-convert', 'json', '-o', '-', '$contents/Info.plist'],
    );
    _expect(
      plistResult.exitCode == 0,
      'Info.plist conversion failed: ${plistResult.stderr}',
    );
    final Map<String, Object?> infoPlist =
        jsonDecode(plistResult.stdout as String) as Map<String, Object?>;
    _expect(
      infoPlist['CFBundleDisplayName'] == 'Dart Terminal' &&
          infoPlist['CFBundleIconFile'] == 'DartTerminal.icns' &&
          infoPlist['NSAppleScriptEnabled'] == true &&
          infoPlist['OSAScriptingDefinition'] == 'DartTerminal.sdef',
      'display name, icon, or Cocoa Scripting Info.plist declaration mismatch',
    );
    _expect(
      terminalDifferentialSha256(await File(terminfo).readAsBytes()) ==
          terminfoContract.compiledSha256,
      'bundled terminfo entry differs from the reviewed contract',
    );
    final File reviewedShellContract = File(
      TerminalShellIntegrationContract.relativePath,
    );
    _expect(
      terminalDifferentialSha256(await File(shellContractPath).readAsBytes()) ==
          terminalDifferentialSha256(await reviewedShellContract.readAsBytes()),
      'bundled shell integration contract differs from the reviewed contract',
    );
    _expect(
      (await File(helper).stat()).mode & 0x49 != 0,
      'Dart helper is not executable',
    );

    final Set<String> expectedArchitectures = universal
        ? const <String>{'arm64', 'x86_64'}
        : <String>{architecture!};
    for (final String path in codeImages) {
      final ProcessResult arch = await Process.run('/usr/bin/lipo', <String>[
        '-archs',
        path,
      ]);
      _expect(arch.exitCode == 0, 'lipo failed for $path: ${arch.stderr}');
      final Set<String> architectures = (arch.stdout as String)
          .trim()
          .split(RegExp(r'\s+'))
          .where((String value) => value.isNotEmpty)
          .toSet();
      _expect(
        _sameStrings(architectures, expectedArchitectures),
        '$path does not contain the exact expected architectures: '
        '$architectures',
      );
      final ProcessResult links = await Process.run('/usr/bin/otool', <String>[
        '-L',
        path,
      ]);
      _expect(links.exitCode == 0, 'otool failed for $path: ${links.stderr}');
      final String linkText = const LineSplitter()
          .convert(links.stdout as String)
          .where((String line) => line.startsWith(' ') || line.startsWith('\t'))
          .join('\n');
      _expect(
        !linkText.contains('/Users/') && !linkText.contains('/dart_appkit/'),
        '$path retains a build-machine dependency path',
      );
      if (path == executable) {
        _expect(
          linkText.contains('@rpath/libdart_terminal_app_intents_macos.dylib'),
          'runtime host does not load the App Intents image at launch',
        );
      } else if (path == appIntentsImage) {
        _expect(
          linkText.contains(
                '@rpath/libdart_terminal_app_intents_macos.dylib',
              ) &&
              linkText.contains('/AppIntents.framework/'),
          'App Intents image identity or framework dependency mismatch',
        );
      }
    }

    final ProcessResult signature = await Process.run(
      '/usr/bin/codesign',
      <String>['--verify', '--deep', '--strict', bundle.path],
    );
    _expect(
      signature.exitCode == 0,
      'bundle signature verification failed: ${signature.stderr}',
    );
    stdout.writeln(
      'DART_ONLY_BUNDLE_AUDIT_PASS mode=$mode architecture=$architecture '
      'helpers=${helpers.length} assets=${assets.length} '
      'capabilities=${capabilities.length} scripting_definition=1 '
      'app_intents=${actionNames.length} localizations=${localizedResources.length}',
    );
  } on Object catch (error) {
    stderr.writeln('DART_ONLY_BUNDLE_AUDIT_FAIL $error');
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

Future<Set<String>> _regularBundleFiles(Directory bundle) async {
  final Set<String> files = <String>{};
  final Set<String> foldedPaths = <String>{};
  await for (final FileSystemEntity entity in bundle.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relativePath = entity.path.substring(bundle.path.length + 1);
    final FileSystemEntityType type = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    _expect(type != FileSystemEntityType.link, 'bundle contains a symlink');
    _expect(
      type == FileSystemEntityType.file ||
          type == FileSystemEntityType.directory,
      'bundle contains an unsupported filesystem entry',
    );
    _expect(
      foldedPaths.add(relativePath.toLowerCase()),
      'bundle contains case-folded path aliases',
    );
    if (relativePath == 'Contents/_CodeSignature' ||
        relativePath.startsWith('Contents/_CodeSignature/')) {
      continue;
    }
    if (type == FileSystemEntityType.file) files.add(relativePath);
  }
  return files;
}

bool _safeRelativePath(String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains('\\')) {
    return false;
  }
  return value
      .split('/')
      .every(
        (String part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !part.contains('\u0000'),
      );
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> sortedLeft = left.toList()..sort();
  final List<String> sortedRight = right.toList()..sort();
  if (sortedLeft.length != sortedRight.length) return false;
  for (var index = 0; index < sortedLeft.length; ++index) {
    if (sortedLeft[index] != sortedRight[index]) return false;
  }
  return true;
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
