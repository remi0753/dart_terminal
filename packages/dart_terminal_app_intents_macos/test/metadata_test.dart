import 'dart:convert';
import 'dart:io';

Future<void> runMetadataTest() async {
  if (!Platform.isMacOS) return;
  final Directory root = await Directory.systemTemp.createTemp(
    'dart_terminal_app_intents_metadata.',
  );
  try {
    final File source = File.fromUri(
      Platform.script.resolve('../native/TerminalAppIntents.swift'),
    );
    final File protocols = File('${root.path}/protocols.json')
      ..writeAsStringSync('["AppIntent","AppShortcutsProvider"]\n');
    final File object = File('${root.path}/module.o');
    final File constValues = File('${root.path}/module.swiftconstvalues');
    final File library = File(
      '${root.path}/libdart_terminal_app_intents_macos.dylib',
    );
    final File sourceList = File('${root.path}/sources.list')
      ..writeAsStringSync('${source.path}\n');
    final File constValuesList = File('${root.path}/const-values.list')
      ..writeAsStringSync('${constValues.path}\n');
    final Directory moduleCache = Directory('${root.path}/module-cache')
      ..createSync();
    final String swiftc = await _output('/usr/bin/xcrun', const <String>[
      '--find',
      'swiftc',
    ], root.path);
    final String processor = await _output('/usr/bin/xcrun', const <String>[
      '--find',
      'appintentsmetadataprocessor',
    ], root.path);
    final String xcodebuild = await _output('/usr/bin/xcrun', const <String>[
      '--find',
      'xcodebuild',
    ], root.path);
    final String sdk = await _output('/usr/bin/xcrun', const <String>[
      '--sdk',
      'macosx',
      '--show-sdk-path',
    ], root.path);
    final String architecture = await _output('/usr/bin/uname', const <String>[
      '-m',
    ], root.path);
    final String target = '$architecture-apple-macos14.0';
    await _run(swiftc, <String>[
      '-c',
      '-parse-as-library',
      '-swift-version',
      '6',
      '-warnings-as-errors',
      '-emit-const-values',
      '-emit-const-values-path',
      constValues.path,
      '-Xfrontend',
      '-const-gather-protocols-file',
      '-Xfrontend',
      protocols.path,
      '-module-name',
      'DartTerminalAppIntents',
      '-target',
      target,
      '-sdk',
      sdk,
      '-module-cache-path',
      moduleCache.path,
      '-o',
      object.path,
      source.path,
    ], root.path);
    await _run(swiftc, <String>[
      '-emit-library',
      '-target',
      target,
      '-sdk',
      sdk,
      '-Xlinker',
      '-install_name',
      '-Xlinker',
      '@rpath/${library.uri.pathSegments.last}',
      '-o',
      library.path,
      object.path,
    ], root.path);
    final String xcodeVersion = await _output(xcodebuild, const <String>[
      '-version',
    ], root.path);
    final String buildVersion = RegExp(
      r'(?:^|\n)Build version ([A-Za-z0-9]+)(?:\n|$)',
    ).firstMatch(xcodeVersion)!.group(1)!;
    final Directory toolchain = File(swiftc).parent.parent.parent;
    final Directory output = Directory('${root.path}/metadata')..createSync();
    await _run(processor, <String>[
      '--output',
      output.path,
      '--toolchain-dir',
      toolchain.path,
      '--module-name',
      'DartTerminalAppIntents',
      '--sdk-root',
      sdk,
      '--xcode-version',
      buildVersion,
      '--platform-family',
      'macOS',
      '--deployment-target',
      '14.0',
      '--target-triple',
      target,
      '--source-file-list',
      sourceList.path,
      '--swift-const-vals-list',
      constValuesList.path,
      '--no-app-shortcuts-localization',
      '--force',
    ], root.path);

    final Directory metadata = Directory('${output.path}/Metadata.appintents');
    final List<String> entries =
        metadata
            .listSync(followLinks: false)
            .map((FileSystemEntity value) => value.uri.pathSegments.last)
            .toList()
          ..sort();
    final String actions = File('${metadata.path}/extract.actionsdata')
        .readAsStringSync();
    final Map<String, Object?> decodedActions =
        jsonDecode(actions) as Map<String, Object?>;
    final Map<String, Object?> actionDeclarations =
        decodedActions['actions']! as Map<String, Object?>;
    final List<Object?> shortcuts =
        decodedActions['autoShortcuts']! as List<Object?>;
    final Set<String> actionNames = actionDeclarations.keys.toSet();
    final bool actionsAreParameterless = actionDeclarations.values.every(
      (Object? value) =>
          value is Map<String, Object?> &&
          value['openAppWhenRun'] == true &&
          (value['parameters']! as List<Object?>).isEmpty,
    );
    final Set<Object?> shortcutActions = shortcuts
        .map(
          (Object? value) =>
              (value! as Map<String, Object?>)['actionIdentifier'],
        )
        .toSet();
    final Map<String, Object?> version = jsonDecode(
      File('${metadata.path}/version.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final String images = await _output('/usr/bin/otool', <String>[
      '-L',
      library.path,
    ], root.path);
    final String symbols = await _output('/usr/bin/nm', <String>[
      '-gU',
      library.path,
    ], root.path);
    _expect(
      entries.join(',') == 'extract.actionsdata,version.json' &&
          actionNames.length == 3 &&
          actionNames.contains('NewTerminalWindowIntent') &&
          actionNames.contains('NewTerminalTabIntent') &&
          actionNames.contains('ToggleQuickTerminalIntent') &&
          actionsAreParameterless &&
          shortcuts.length == 3 &&
          shortcutActions.length == 3 &&
          shortcutActions.containsAll(actionNames) &&
          actions.contains('DartTerminalAppIntents.NewTerminalWindowIntent') &&
          actions.contains('DartTerminalAppIntents.NewTerminalTabIntent') &&
          actions.contains(
            'DartTerminalAppIntents.ToggleQuickTerminalIntent',
          ) &&
          actions.contains('autoShortcuts') &&
          version['toolsVersion'] == buildVersion &&
          images.contains('@rpath/libdart_terminal_app_intents_macos.dylib') &&
          images.contains('/AppIntents.framework/') &&
          symbols.contains('_dtai_take_command') &&
          symbols.contains('_dtai_complete_command'),
      'Swift image, three actions, shortcuts, metadata, and queue ABI',
    );
    stdout.writeln('PASS terminal App Intents compiler metadata');
  } finally {
    await root.delete(recursive: true);
  }
}

Future<String> _output(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final ProcessResult result = await _run(
    executable,
    arguments,
    workingDirectory,
  );
  return (result.stdout as String).trim();
}

Future<ProcessResult> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('metadata test failed: $description');
  }
}
