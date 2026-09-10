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
      architecture == 'arm64' || architecture == 'x86_64',
      'architecture must be arm64 or x86_64',
    );
    _expect(bundlePath != null, 'application bundle path is required');

    final Directory bundle = Directory(bundlePath!).absolute;
    _expect(await bundle.exists(), 'bundle does not exist: ${bundle.path}');
    final String contents = '${bundle.path}/Contents';
    final String resources = '$contents/Resources';
    final Map<String, Object?> manifest = jsonDecode(
      await File('$resources/runtime-build-manifest.json').readAsString(),
    ) as Map<String, Object?>;
    _expect(manifest['schemaVersion'] == 1, 'manifest schema mismatch');
    _expect(manifest['runtimeMode'] == mode, 'runtime mode mismatch');
    _expect(manifest['architecture'] == architecture, 'architecture mismatch');
    _expect(
      manifest['bundleIdentifier'] == 'dev.dart-terminal',
      'bundle identifier mismatch',
    );
    _expect(manifest['executable'] == 'dart_terminal', 'executable mismatch');

    final List<Object?> helpers = manifest['dartHelpers']! as List<Object?>;
    final List<Object?> assets = manifest['nativeAssets']! as List<Object?>;
    final List<Object?> capabilities =
        manifest['nativeCapabilities']! as List<Object?>;
    _expect(
      helpers.length == 1 &&
          (helpers.single! as Map<String, Object?>)['name'] ==
              'dart_terminal_runtime_worker',
      'Dart helper manifest mismatch',
    );
    _expect(
      assets.length == 1 &&
          (assets.single! as Map<String, Object?>)['id'] == 'dart_pty_macos',
      'PTY asset manifest mismatch',
    );
    _expect(
      capabilities.length == 1 &&
          (capabilities.single! as Map<String, Object?>)['id'] ==
              'dart_terminal_renderer_macos',
      'renderer capability manifest mismatch',
    );

    final String executable = '$contents/MacOS/dart_terminal';
    final String helper = '$contents/Helpers/dart_terminal_runtime_worker';
    final String engine =
        '$contents/Frameworks/libdart_engine_${mode == 'developer-jit' ? 'jit' : 'aot'}_shared.dylib';
    final String pty = '$contents/Frameworks/libdart_pty_macos.dylib';
    final String renderer =
        '$contents/Frameworks/libdart_terminal_renderer_macos.dylib';
    final String payload =
        '$resources/${mode == 'developer-jit' ? 'application.dill' : 'application.aot'}';
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
      payload,
      '$resources/DART_SDK_LICENSE.txt',
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

    for (final String path in <String>[
      executable,
      helper,
      engine,
      pty,
      renderer,
    ]) {
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
        architectures.contains(architecture),
        '$path does not contain $architecture: $architectures',
      );
      final ProcessResult links = await Process.run('/usr/bin/otool', <String>[
        '-L',
        path,
      ]);
      _expect(links.exitCode == 0, 'otool failed for $path: ${links.stderr}');
      final String linkText = const LineSplitter()
          .convert(links.stdout as String)
          .skip(1)
          .join('\n');
      _expect(
        !linkText.contains('/Users/') && !linkText.contains('/dart_appkit/'),
        '$path retains a build-machine dependency path',
      );
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
      'capabilities=${capabilities.length}',
    );
  } on Object catch (error) {
    stderr.writeln('DART_ONLY_BUNDLE_AUDIT_FAIL $error');
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw _AuditException(message);
  }
}
