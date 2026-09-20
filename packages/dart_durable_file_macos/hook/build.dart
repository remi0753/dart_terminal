import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (BuildInput input, BuildOutputBuilder output) async {
    if (input.config.code.targetOS.name != 'macos') {
      throw UnsupportedError('dart_durable_file_macos requires macOS');
    }
    final CLibrary library = CLibrary(
      name: 'dart_durable_file_macos',
      assetName: 'dart_durable_file_macos.dart',
      sources: const <String>['native/DurableFile.c'],
      flags: const <String>[
        '-std=c17',
        '-fvisibility=hidden',
        '-Wall',
        '-Wextra',
        '-Wpedantic',
        '-Werror',
        '-Wno-unused-command-line-argument',
        '-mmacosx-version-min=14.0',
      ],
      language: Language.c,
    );
    await library.build(
      input: input,
      output: output,
      routing: const <AssetRouting>[ToAppBundle()],
      linkModePreference: LinkModePreference.dynamic,
    );
  });
}
