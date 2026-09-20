import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

var _failures = 0;

Future<void> main() => runTerminalReleaseSymbolsTests();

Future<void> runTerminalReleaseSymbolsTests() async {
  await _testSuccessfulThinPackage();
  await _testUniversalManifest();
  await _testInventoryAndFilesystemFailures();
  await _testUuidMismatchPreservesExistingOutput();
  await _testAtomicPublicationFaults();
  await _testInterruptedPublicationRecovery();
  if (_failures != 0) {
    throw StateError('$_failures terminal release symbol test(s) failed');
  }
}

Future<void> _testSuccessfulThinPackage() async {
  await _testAsync('thin symbol package is complete and content-free', () async {
    final _SymbolFixture fixture = await _SymbolFixture.create();
    try {
      final _FakeSymbolExecutor executor = _FakeSymbolExecutor();
      final TerminalReleaseSymbolPackageResult result =
          await TerminalReleaseSymbolPackageBuilder(commandExecutor: executor)
              .build(application: fixture.application, output: fixture.output);
      final File manifestFile = File(
        '${fixture.output.path}/$terminalReleaseSymbolsManifestName',
      );
      final String manifestText = await manifestFile.readAsString();
      final Map<String, Object?> manifest =
          jsonDecode(manifestText) as Map<String, Object?>;
      final List<Object?> code = manifest['code']! as List<Object?>;
      _expect(
        result.architectures.join(',') == 'arm64' &&
            result.codeImageCount == terminalUpdateCodePaths.length &&
            result.symbolCount == terminalUpdateCodePaths.length &&
            result.machineLine() ==
                'TERMINAL_RELEASE_SYMBOLS code=10 architectures=1 symbols=10',
        'thin package result differs',
      );
      _expect(
        manifest['format'] == terminalReleaseSymbolsFormat &&
            manifest['version'] == terminalReleaseSymbolsVersion &&
            manifest['bundle_id'] == terminalUpdateProduct &&
            manifest['application_version'] == '0.1.0' &&
            manifest['runtime_mode'] == 'release-aot' &&
            manifest['coverage'] == 'function-symbols' &&
            (manifest['architectures']! as List<Object?>).single == 'arm64' &&
            code.length == terminalUpdateCodePaths.length &&
            _sameSet(manifest.keys, const <String>{
              'format',
              'version',
              'bundle_id',
              'application_version',
              'runtime_mode',
              'coverage',
              'architectures',
              'code',
            }),
        'thin manifest header differs',
      );
      for (var index = 0; index < code.length; index++) {
        final Map<String, Object?> record =
            code[index]! as Map<String, Object?>;
        final List<Object?> uuids = record['uuids']! as List<Object?>;
        _expect(
          record['path'] == terminalUpdateCodePaths[index] &&
              record['source_sha256'] == _hash('a') &&
              record['dwarf_sha256'] == _hash('a') &&
              record['dsym'] ==
                  'dSYMs/${index.toString().padLeft(2, '0')}-'
                      '${terminalUpdateCodePaths[index].split('/').last}.dSYM' &&
              record['symbols'] == 1 &&
              uuids.length == 1 &&
              _sameSet(record.keys, const <String>{
                'path',
                'source_sha256',
                'dsym',
                'dwarf_sha256',
                'uuids',
                'symbols',
              }) &&
              _sameSet(
                (uuids.single! as Map<String, Object?>).keys,
                const <String>{'architecture', 'uuid'},
              ),
          'code record $index differs',
        );
      }
      _expect(
        !manifestText.contains(fixture.root.path) &&
            executor.dsymutilCalls == terminalUpdateCodePaths.length,
        'manifest leaked local identity or code was not packaged exactly once',
      );
      final Directory secondOutput = Directory(
        '${fixture.root.path}/symbols-2',
      );
      await TerminalReleaseSymbolPackageBuilder(
        commandExecutor: _FakeSymbolExecutor(),
      ).build(application: fixture.application, output: secondOutput);
      _expect(
        await File('${secondOutput.path}/$terminalReleaseSymbolsManifestName')
                .readAsString() ==
            manifestText,
        'identical inputs produced a different canonical manifest',
      );
      final List<String> outputEntries = <String>[
        await for (final FileSystemEntity entity in fixture.output.list())
          entity.path.split('/').last,
      ]..sort();
      _expect(
        outputEntries.join(',') == 'dSYMs,$terminalReleaseSymbolsManifestName',
        'published output inventory differs',
      );
    } finally {
      await fixture.dispose();
    }
  });
}

Future<void> _testUniversalManifest() async {
  await _testAsync(
    'universal UUID sets preserve audited architecture order',
    () async {
      final _SymbolFixture fixture = await _SymbolFixture.create(
        universal: true,
      );
      try {
        final TerminalReleaseSymbolPackageResult result =
            await TerminalReleaseSymbolPackageBuilder(
              commandExecutor: _FakeSymbolExecutor(universal: true),
            ).build(application: fixture.application, output: fixture.output);
        final Map<String, Object?> manifest = jsonDecode(
          await File(
            '${fixture.output.path}/$terminalReleaseSymbolsManifestName',
          ).readAsString(),
        ) as Map<String, Object?>;
        final List<Object?> firstUuids =
            ((manifest['code']! as List<Object?>).first!
                    as Map<String, Object?>)['uuids']!
                as List<Object?>;
        _expect(
          result.architectures.join(',') == 'arm64,x86_64' &&
              (firstUuids.first! as Map<String, Object?>)['architecture'] ==
                  'arm64' &&
              (firstUuids.last! as Map<String, Object?>)['architecture'] ==
                  'x86_64',
          'universal architecture order differs',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testInventoryAndFilesystemFailures() async {
  await _testAsync('missing and extra code images fail closed', () async {
    for (final bool extra in <bool>[false, true]) {
      final _SymbolFixture fixture = await _SymbolFixture.create();
      try {
        if (extra) {
          await File(
            '${fixture.application.path}/Contents/Frameworks/unknown.dylib',
          ).writeAsBytes(_machOBytes);
        } else {
          await File(
            '${fixture.application.path}/${terminalUpdateCodePaths.last}',
          ).delete();
        }
        await _expectSymbolsError(
          () => TerminalReleaseSymbolPackageBuilder(
            commandExecutor: _FakeSymbolExecutor(),
          ).build(application: fixture.application, output: fixture.output),
          'application-code-inventory-differs',
        );
        _expect(
          !await fixture.output.exists(),
          'invalid inventory was published',
        );
      } finally {
        await fixture.dispose();
      }
    }
  });

  await _testAsync(
    'links and overlapping output fail before commands',
    () async {
      final _SymbolFixture fixture = await _SymbolFixture.create();
      try {
        final File target = File('${fixture.root.path}/outside.txt');
        await target.writeAsString('outside');
        await Link('${fixture.application.path}/Contents/Resources/linked')
            .create(target.path);
        final _FakeSymbolExecutor executor = _FakeSymbolExecutor();
        await _expectSymbolsError(
          () => TerminalReleaseSymbolPackageBuilder(commandExecutor: executor)
              .build(application: fixture.application, output: fixture.output),
          'application-unsupported-entry',
        );
        _expect(executor.dsymutilCalls == 0, 'link reached symbol generation');
        await _expectSymbolsError(
          () =>
              TerminalReleaseSymbolPackageBuilder(commandExecutor: executor)
                  .build(
                    application: fixture.application,
                    output: Directory('${fixture.application.path}/symbols'),
                  ),
          'input-output-overlap',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _testAsync('unknown executable placement fails closed', () async {
    final _SymbolFixture fixture = await _SymbolFixture.create();
    try {
      final File executable = File(
        '${fixture.application.path}/Contents/Resources/unreviewed-tool',
      );
      await executable.writeAsString('#!/bin/sh\n');
      final ProcessResult chmod = await Process.run('/bin/chmod', <String>[
        '755',
        executable.path,
      ]);
      _expect(chmod.exitCode == 0, 'fixture chmod failed');
      await _expectSymbolsError(
        () => TerminalReleaseSymbolPackageBuilder(
          commandExecutor: _FakeSymbolExecutor(),
        ).build(application: fixture.application, output: fixture.output),
        'application-code-inventory-differs',
      );
    } finally {
      await fixture.dispose();
    }
  });
}

Future<void> _testUuidMismatchPreservesExistingOutput() async {
  await _testAsync('dSYM UUID mismatch preserves last good output', () async {
    final _SymbolFixture fixture = await _SymbolFixture.create();
    try {
      await fixture.output.create();
      final File sentinel = File('${fixture.output.path}/last-good');
      await sentinel.writeAsString('preserve');
      await _expectSymbolsError(
        () => TerminalReleaseSymbolPackageBuilder(
          commandExecutor: _FakeSymbolExecutor(mismatchDsym: true),
        ).build(application: fixture.application, output: fixture.output),
        'dsym-uuid-differs',
      );
      _expect(
        await sentinel.readAsString() == 'preserve' &&
            !await Directory('${fixture.output.path}.last-good').exists() &&
            await _stagingNames(fixture)
                .then((List<String> value) => value.isEmpty),
        'pre-publication mismatch damaged output or retained staging',
      );
    } finally {
      await fixture.dispose();
    }
  });
}

Future<void> _testAtomicPublicationFaults() async {
  await _testAsync(
    'publication faults retain or restore last good output',
    () async {
      for (final String boundary in <String>[
        'before-publish',
        'after-old-move',
      ]) {
        final _SymbolFixture fixture = await _SymbolFixture.create();
        try {
          await fixture.output.create();
          final File sentinel = File('${fixture.output.path}/last-good');
          await sentinel.writeAsString(boundary);
          Object? observed;
          try {
            await TerminalReleaseSymbolPackageBuilder(
              commandExecutor: _FakeSymbolExecutor(),
              faultInjector: (String value) {
                if (value == boundary) throw StateError('injected-$boundary');
              },
            ).build(application: fixture.application, output: fixture.output);
          } on Object catch (error) {
            observed = error;
          }
          _expect(
            observed is StateError &&
                await sentinel.readAsString() == boundary &&
                !await Directory('${fixture.output.path}.last-good').exists() &&
                await _stagingNames(fixture)
                    .then((List<String> value) => value.isEmpty),
            '$boundary did not restore the last good output',
          );
        } finally {
          await fixture.dispose();
        }
      }
    },
  );
}

Future<void> _testInterruptedPublicationRecovery() async {
  await _testAsync(
    'a previous interrupted move is recovered before new symbol work',
    () async {
      final _SymbolFixture fixture = await _SymbolFixture.create();
      try {
        final Directory backup = Directory('${fixture.output.path}.last-good');
        await backup.create();
        final File sentinel = File('${backup.path}/interrupted-last-good');
        await sentinel.writeAsString('recover');
        Object? observed;
        try {
          await TerminalReleaseSymbolPackageBuilder(
            commandExecutor: _FakeSymbolExecutor(),
            faultInjector: (String boundary) {
              if (boundary == 'after-code-0') {
                throw StateError('stop-new-attempt');
              }
            },
          ).build(application: fixture.application, output: fixture.output);
        } on Object catch (error) {
          observed = error;
        }
        _expect(
          observed is StateError &&
              await File('${fixture.output.path}/interrupted-last-good')
                      .readAsString() ==
                  'recover' &&
              !await backup.exists() &&
              await _stagingNames(fixture)
                  .then((List<String> value) => value.isEmpty),
          'interrupted last-good state was not restored before new work',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<List<String>> _stagingNames(_SymbolFixture fixture) async => <String>[
  await for (final FileSystemEntity entity in fixture.root.list())
    if (entity.path.split('/').last.startsWith('symbols.staging-')) entity.path,
];

final class _SymbolFixture {
  _SymbolFixture({
    required this.root,
    required this.application,
    required this.output,
  });

  final Directory root;
  final Directory application;
  final Directory output;

  static Future<_SymbolFixture> create({bool universal = false}) async {
    final Directory root = await Directory.systemTemp.createTemp(
      'dart-terminal-release-symbols-',
    );
    final Directory application = Directory('${root.path}/DartTerminal.app');
    final Directory resources = Directory(
      '${application.path}/Contents/Resources',
    );
    await resources.create(recursive: true);
    await File('${application.path}/Contents/Info.plist').writeAsString(
      '<plist><dict><key>fixture</key><string>fixture</string></dict></plist>\n',
    );
    final Map<String, Object?> manifest = universal
        ? <String, Object?>{
            'schemaVersion': 2,
            'runtimeMode': 'release-aot',
            'bundleIdentifier': terminalUpdateProduct,
            'architectures': <String>['arm64', 'x86_64'],
            'codePaths': terminalUpdateCodePaths,
          }
        : <String, Object?>{
            'schemaVersion': 1,
            'runtimeMode': 'release-aot',
            'bundleIdentifier': terminalUpdateProduct,
            'architecture': 'arm64',
          };
    await File('${resources.path}/runtime-build-manifest.json')
        .writeAsString('${jsonEncode(manifest)}\n');
    for (final String relative in terminalUpdateCodePaths) {
      final File code = File('${application.path}/$relative');
      await code.create(recursive: true);
      await code.writeAsBytes(_machOBytes);
    }
    return _SymbolFixture(
      root: root,
      application: application,
      output: Directory('${root.path}/symbols'),
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

final class _FakeSymbolExecutor
    implements TerminalReleaseSymbolsCommandExecutor {
  _FakeSymbolExecutor({this.universal = false, this.mismatchDsym = false});

  static const String _armUuid = '11111111-1111-1111-1111-111111111111';
  static const String _x86Uuid = '22222222-2222-2222-2222-222222222222';
  static const String _badUuid = '33333333-3333-3333-3333-333333333333';

  final bool universal;
  final bool mismatchDsym;
  int dsymutilCalls = 0;

  @override
  Future<TerminalReleaseSymbolsCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    _expect(workingDirectory.startsWith('/'), 'working directory was relative');
    if (executable == '/usr/bin/plutil') {
      return TerminalReleaseSymbolsCommandResult(
        exitCode: 0,
        stdoutText: arguments[1] == 'CFBundleIdentifier'
            ? '$terminalUpdateProduct\n'
            : '0.1.0\n',
      );
    }
    if (executable == '/usr/bin/xcrun' && arguments.first == 'dsymutil') {
      dsymutilCalls++;
      final String source = arguments[1];
      final String output = arguments[3];
      final File dwarf = File(
        '$output/Contents/Resources/DWARF/${source.split('/').last}',
      );
      await dwarf.create(recursive: true);
      await dwarf.writeAsBytes(_machOBytes);
      return const TerminalReleaseSymbolsCommandResult(exitCode: 0);
    }
    if (executable == '/usr/bin/xcrun' && arguments.first == 'dwarfdump') {
      final String path = arguments.last;
      final bool dsym = path.endsWith('.dSYM');
      final String armUuid = dsym && mismatchDsym ? _badUuid : _armUuid;
      return TerminalReleaseSymbolsCommandResult(
        exitCode: 0,
        stdoutText:
            'UUID: $armUuid (arm64) $path\n'
            '${universal ? 'UUID: $_x86Uuid (x86_64) $path\n' : ''}',
      );
    }
    if (executable == '/usr/bin/shasum') {
      return TerminalReleaseSymbolsCommandResult(
        exitCode: 0,
        stdoutText: '${_hash('a')}  ${arguments.last}\n',
      );
    }
    if (executable == '/usr/bin/nm') {
      return const TerminalReleaseSymbolsCommandResult(
        exitCode: 0,
        stdoutText:
            '0000000100000000 (__TEXT,__text) external _fixture_symbol\n',
      );
    }
    throw StateError('unexpected command: $executable $arguments');
  }
}

const List<int> _machOBytes = <int>[0xcf, 0xfa, 0xed, 0xfe, 0, 0, 0, 0];

String _hash(String character) => List<String>.filled(64, character).join();

bool _sameSet(Iterable<String> values, Set<String> expected) =>
    values.toSet().length == expected.length && values.every(expected.contains);

Future<void> _expectSymbolsError(
  Future<void> Function() body,
  String code,
) async {
  try {
    await body();
  } on TerminalReleaseSymbolsException catch (error) {
    _expect(error.code == code, 'expected $code, got ${error.code}');
    return;
  }
  throw StateError('expected TerminalReleaseSymbolsException($code)');
}

Future<void> _testAsync(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    _failures++;
    stderr.writeln('FAIL $name: $error\n$stackTrace');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
