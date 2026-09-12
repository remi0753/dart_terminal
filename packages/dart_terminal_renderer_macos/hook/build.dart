import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (BuildInput input, BuildOutputBuilder output) async {
    if (input.config.code.targetOS.name != 'macos') {
      throw UnsupportedError('dart_terminal_renderer_macos requires macOS');
    }
    if (!input.config.buildCodeAssets) {
      return;
    }
    final Uri shaderSource = input.packageRoot.resolve(
      'native/TerminalShaders.metal',
    );
    final Uri shaderLibrary = input.outputDirectory.resolve(
      'TerminalShaders.metallib',
    );
    await Directory.fromUri(input.outputDirectory).create(recursive: true);
    final ProcessResult metal = await Process.run('xcrun', <String>[
      '-sdk',
      'macosx',
      'metal',
      '-target',
      'air64-apple-macos14.0',
      shaderSource.toFilePath(),
      '-o',
      shaderLibrary.toFilePath(),
    ]);
    if (metal.exitCode != 0) {
      throw StateError(
        'Metal shader compilation failed (${metal.exitCode}): '
        '${metal.stderr}',
      );
    }
    output.dependencies.add(shaderSource);
    final CLibrary library = CLibrary(
      name: 'dart_terminal_renderer_macos',
      assetName: 'dart_terminal_renderer_macos.dart',
      sources: const <String>['native/TerminalRendererPlugin.m'],
      includes: const <String>[
        '../../../dart_appkit/native/bridge/include',
      ],
      frameworks: const <String>['AppKit', 'CoreText', 'Metal', 'MetalKit'],
      flags: <String>[
        '-fobjc-arc',
        '-fblocks',
        '-fvisibility=hidden',
        '-Wall',
        '-Wextra',
        '-Wpedantic',
        '-Werror',
        '-Wno-unused-command-line-argument',
        '-mmacosx-version-min=14.0',
        '-Wl,-sectcreate,__DATA,__dtrlib,${shaderLibrary.toFilePath()}',
      ],
      language: Language.objectiveC,
    );
    await library.build(
      input: input,
      output: output,
      routing: const <AssetRouting>[ToAppBundle()],
      linkModePreference: LinkModePreference.dynamic,
    );
  });
}
