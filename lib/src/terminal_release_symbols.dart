import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'terminal_update_feed.dart';
import 'terminal_update_transaction.dart';

const String terminalReleaseSymbolsFormat = 'dart-terminal-release-symbols';
const int terminalReleaseSymbolsVersion = 1;
const String terminalReleaseSymbolsManifestName = 'symbols-manifest.json';

final class TerminalReleaseSymbolsException implements Exception {
  const TerminalReleaseSymbolsException(this.code);

  final String code;

  @override
  String toString() => 'TerminalReleaseSymbolsException: $code';
}

final class TerminalReleaseSymbolsCommandResult {
  const TerminalReleaseSymbolsCommandResult({
    required this.exitCode,
    this.stdoutText = '',
    this.stderrText = '',
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

abstract interface class TerminalReleaseSymbolsCommandExecutor {
  Future<TerminalReleaseSymbolsCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });
}

final class TerminalReleaseSymbolsSystemCommandExecutor
    implements TerminalReleaseSymbolsCommandExecutor {
  const TerminalReleaseSymbolsSystemCommandExecutor();

  static const int maximumOutputBytes = 4 * 1024 * 1024;
  static const Duration timeout = Duration(minutes: 3);

  @override
  Future<TerminalReleaseSymbolsCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    Process? process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.normal,
      );
      final Future<_BoundedCommandOutput> stdout = _readBounded(process.stdout);
      final Future<_BoundedCommandOutput> stderr = _readBounded(process.stderr);
      late final int status;
      try {
        status = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        throw const TerminalReleaseSymbolsException('command-timeout');
      }
      final _BoundedCommandOutput stdoutResult = await stdout;
      final _BoundedCommandOutput stderrResult = await stderr;
      if (stdoutResult.exceeded || stderrResult.exceeded) {
        throw const TerminalReleaseSymbolsException('command-output-too-large');
      }
      return TerminalReleaseSymbolsCommandResult(
        exitCode: status,
        stdoutText: stdoutResult.text,
        stderrText: stderrResult.text,
      );
    } on TerminalReleaseSymbolsException {
      rethrow;
    } on Object {
      process?.kill(ProcessSignal.sigkill);
      throw const TerminalReleaseSymbolsException('command-start-failed');
    }
  }

  static Future<_BoundedCommandOutput> _readBounded(
    Stream<List<int>> input,
  ) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    var exceeded = false;
    await for (final List<int> chunk in input) {
      final int remaining = maximumOutputBytes - bytes.length;
      if (remaining <= 0) {
        exceeded = true;
        continue;
      }
      if (chunk.length <= remaining) {
        bytes.add(chunk);
      } else {
        bytes.add(chunk.sublist(0, remaining));
        exceeded = true;
      }
    }
    return _BoundedCommandOutput(
      text: utf8.decode(bytes.takeBytes(), allowMalformed: true),
      exceeded: exceeded,
    );
  }
}

final class TerminalReleaseSymbolPackageResult {
  TerminalReleaseSymbolPackageResult({
    required List<String> architectures,
    required this.codeImageCount,
    required this.symbolCount,
  }) : architectures = List<String>.unmodifiable(architectures);

  final List<String> architectures;
  final int codeImageCount;
  final int symbolCount;

  String machineLine() =>
      'TERMINAL_RELEASE_SYMBOLS code=$codeImageCount '
      'architectures=${architectures.length} symbols=$symbolCount';
}

typedef TerminalReleaseSymbolsFaultInjector = void Function(String boundary);

final class TerminalReleaseSymbolPackageBuilder {
  const TerminalReleaseSymbolPackageBuilder({
    this.commandExecutor = const TerminalReleaseSymbolsSystemCommandExecutor(),
    this.faultInjector,
  });

  static const int maximumManifestBytes = 1024 * 1024;
  static const int maximumCodeImageBytes = 1024 * 1024 * 1024;
  static const int maximumDsymBytes = 2 * 1024 * 1024 * 1024;
  static const int maximumTreeEntries = 50000;
  static const int maximumSymbolCount = 10000000;

  final TerminalReleaseSymbolsCommandExecutor commandExecutor;
  final TerminalReleaseSymbolsFaultInjector? faultInjector;

  Future<TerminalReleaseSymbolPackageResult> build({
    required Directory application,
    required Directory output,
  }) async {
    final _SafeSymbolPaths paths = await _safePaths(application, output);
    await _recoverInterruptedPublication(paths.output);
    final Map<String, Object?> runtimeManifest = await _readJsonObject(
      File(
        '${paths.application.path}/Contents/Resources/'
        'runtime-build-manifest.json',
      ),
      maximumBytes: maximumManifestBytes,
      failure: 'runtime-manifest-invalid',
    );
    final List<String> architectures = _validateRuntimeManifest(
      runtimeManifest,
    );
    final String applicationVersion = await _plistValue(
      paths.application,
      'CFBundleShortVersionString',
    );
    final String bundleIdentifier = await _plistValue(
      paths.application,
      'CFBundleIdentifier',
    );
    _expect(
      bundleIdentifier == terminalUpdateProduct &&
          RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(applicationVersion),
      'application-identity-invalid',
    );
    await _validateBundleTree(paths.application);

    final String nonce = _nonce();
    final Directory staging = Directory('${paths.output.path}.staging-$nonce');
    final Directory backup = Directory('${paths.output.path}.last-good');
    var published = false;
    try {
      _expect(
        await FileSystemEntity.type(staging.path, followLinks: false) ==
            FileSystemEntityType.notFound,
        'staging-path-exists',
      );
      await staging.create();
      final Directory symbolRoot = Directory('${staging.path}/dSYMs');
      await symbolRoot.create();
      final List<Map<String, Object?>> records = <Map<String, Object?>>[];
      var totalSymbols = 0;
      for (var index = 0; index < terminalUpdateCodePaths.length; index++) {
        final String codePath = terminalUpdateCodePaths[index];
        final File source = File('${paths.application.path}/$codePath');
        await _validateRegularFile(
          source,
          maximumBytes: maximumCodeImageBytes,
          failure: 'code-image-invalid',
        );
        final List<_MachOUuid> sourceUuids = await _uuids(
          source.path,
          workingDirectory: paths.application.parent.path,
        );
        _expect(
          _sameStrings(
            sourceUuids.map((_MachOUuid value) => value.architecture),
            architectures,
          ),
          'code-architecture-differs',
        );
        final String leaf = codePath.split('/').last;
        final String dsymName =
            '${index.toString().padLeft(2, '0')}-$leaf.dSYM';
        final Directory dsym = Directory('${symbolRoot.path}/$dsymName');
        await _runChecked('dsymutil-failed', '/usr/bin/xcrun', <String>[
          'dsymutil',
          source.path,
          '-o',
          dsym.path,
        ], workingDirectory: paths.application.parent.path);
        final File dwarf = await _validateDsymTree(dsym);
        final List<_MachOUuid> dsymUuids = await _uuids(
          dsym.path,
          workingDirectory: staging.path,
        );
        _expect(_sameUuids(sourceUuids, dsymUuids), 'dsym-uuid-differs');
        final int symbolCount = await _symbolCount(
          dwarf,
          workingDirectory: staging.path,
        );
        totalSymbols += symbolCount;
        _expect(
          totalSymbols <= maximumSymbolCount,
          'symbol-count-out-of-range',
        );
        records.add(<String, Object?>{
          'path': codePath,
          'source_sha256': await _sha256(
            source,
            workingDirectory: paths.application.parent.path,
          ),
          'dsym': 'dSYMs/$dsymName',
          'dwarf_sha256': await _sha256(dwarf, workingDirectory: staging.path),
          'uuids': <Map<String, Object?>>[
            for (final _MachOUuid uuid in sourceUuids)
              <String, Object?>{
                'architecture': uuid.architecture,
                'uuid': uuid.uuid,
              },
          ],
          'symbols': symbolCount,
        });
        faultInjector?.call('after-code-$index');
      }
      final Map<String, Object?> manifest = <String, Object?>{
        'format': terminalReleaseSymbolsFormat,
        'version': terminalReleaseSymbolsVersion,
        'bundle_id': bundleIdentifier,
        'application_version': applicationVersion,
        'runtime_mode': 'release-aot',
        'coverage': 'function-symbols',
        'architectures': architectures,
        'code': records,
      };
      final List<int> manifestBytes = utf8.encode('${jsonEncode(manifest)}\n');
      _expect(
        manifestBytes.length <= maximumManifestBytes,
        'symbols-manifest-too-large',
      );
      final File manifestFile = File(
        '${staging.path}/$terminalReleaseSymbolsManifestName',
      );
      await manifestFile.writeAsBytes(manifestBytes, flush: true);
      await _validateRegularFile(
        manifestFile,
        maximumBytes: maximumManifestBytes,
        failure: 'symbols-manifest-invalid',
      );
      faultInjector?.call('before-publish');
      await _publish(staging: staging, output: paths.output, backup: backup);
      published = true;
      return TerminalReleaseSymbolPackageResult(
        architectures: architectures,
        codeImageCount: records.length,
        symbolCount: totalSymbols,
      );
    } finally {
      if (!published && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<String> _plistValue(Directory application, String key) async {
    final File plist = File('${application.path}/Contents/Info.plist');
    await _validateRegularFile(
      plist,
      maximumBytes: maximumManifestBytes,
      failure: 'info-plist-invalid',
    );
    final TerminalReleaseSymbolsCommandResult result = await _runChecked(
      'plist-read-failed',
      '/usr/bin/plutil',
      <String>['-extract', key, 'raw', '-o', '-', plist.path],
      workingDirectory: application.parent.path,
    );
    final String value = result.stdoutText.trim();
    _expect(
      value.isNotEmpty && utf8.encode(value).length <= 128,
      'plist-value-invalid',
    );
    return value;
  }

  Future<List<_MachOUuid>> _uuids(
    String path, {
    required String workingDirectory,
  }) async {
    final TerminalReleaseSymbolsCommandResult result = await _runChecked(
      'uuid-read-failed',
      '/usr/bin/xcrun',
      <String>['dwarfdump', '--uuid', path],
      workingDirectory: workingDirectory,
    );
    final List<_MachOUuid> values = <_MachOUuid>[];
    final Set<String> identities = <String>{};
    for (final String line in const LineSplitter().convert(result.stdoutText)) {
      final RegExpMatch? match = RegExp(
        r'^UUID: ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}) \((arm64|x86_64)\)(?: .*)?$',
      ).firstMatch(line);
      _expect(match != null, 'uuid-output-invalid');
      final _MachOUuid value = _MachOUuid(
        architecture: match!.group(2)!,
        uuid: match.group(1)!.toUpperCase(),
      );
      _expect(
        identities.add('${value.architecture}:${value.uuid}'),
        'uuid-output-invalid',
      );
      values.add(value);
    }
    _expect(values.isNotEmpty && values.length <= 2, 'uuid-output-invalid');
    values.sort(
      (_MachOUuid left, _MachOUuid right) =>
          _architectureIndex(left.architecture)
              .compareTo(_architectureIndex(right.architecture)),
    );
    return values;
  }

  Future<String> _sha256(File file, {required String workingDirectory}) async {
    final TerminalReleaseSymbolsCommandResult result = await _runChecked(
      'hash-failed',
      '/usr/bin/shasum',
      <String>['-a', '256', file.path],
      workingDirectory: workingDirectory,
    );
    final RegExpMatch? match = RegExp(r'^([0-9a-f]{64})  .+\n?$')
        .firstMatch(result.stdoutText);
    _expect(match != null, 'hash-output-invalid');
    return match!.group(1)!;
  }

  Future<int> _symbolCount(
    File dwarf, {
    required String workingDirectory,
  }) async {
    final TerminalReleaseSymbolsCommandResult result = await _runChecked(
      'symbol-read-failed',
      '/usr/bin/nm',
      <String>['-nm', dwarf.path],
      workingDirectory: workingDirectory,
    );
    final int count = const LineSplitter()
        .convert(result.stdoutText)
        .where(
          (String line) =>
              RegExp(r'^[0-9a-fA-F]{8,16} \(__[^,]+,[^)]+\) ').hasMatch(line),
        )
        .length;
    _expect(count >= 1 && count <= maximumSymbolCount, 'symbols-unavailable');
    return count;
  }

  Future<TerminalReleaseSymbolsCommandResult> _runChecked(
    String failure,
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final TerminalReleaseSymbolsCommandResult result;
    try {
      result = await commandExecutor.run(
        executable,
        List<String>.unmodifiable(arguments),
        workingDirectory: workingDirectory,
      );
    } on TerminalReleaseSymbolsException {
      rethrow;
    } on Object {
      throw TerminalReleaseSymbolsException(failure);
    }
    _expect(result.exitCode == 0, failure);
    return result;
  }

  Future<File> _validateDsymTree(Directory dsym) async {
    _expect(
      await FileSystemEntity.type(dsym.path, followLinks: false) ==
          FileSystemEntityType.directory,
      'dsym-invalid',
    );
    final Directory dwarfDirectory = Directory(
      '${dsym.path}/Contents/Resources/DWARF',
    );
    var entries = 0;
    var bytes = 0;
    final Set<String> folded = <String>{};
    final List<File> dwarfFiles = <File>[];
    await for (final FileSystemEntity entity in dsym.list(
      recursive: true,
      followLinks: false,
    )) {
      entries++;
      _expect(entries <= maximumTreeEntries, 'dsym-tree-too-large');
      final String relative = entity.path.substring(dsym.path.length + 1);
      _expect(folded.add(relative.toLowerCase()), 'dsym-case-alias');
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      _expect(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
        'dsym-unsupported-entry',
      );
      if (type == FileSystemEntityType.file) {
        final int length = await File(entity.path).length();
        bytes += length;
        _expect(bytes <= maximumDsymBytes, 'dsym-tree-too-large');
        if (_isInside(dwarfDirectory.path, entity.path)) {
          dwarfFiles.add(File(entity.path));
        }
      }
    }
    _expect(dwarfFiles.length == 1, 'dsym-dwarf-inventory-differs');
    await _validateRegularFile(
      dwarfFiles.single,
      maximumBytes: maximumDsymBytes,
      failure: 'dsym-dwarf-invalid',
    );
    return dwarfFiles.single;
  }

  Future<void> _validateBundleTree(Directory application) async {
    var entries = 0;
    final Set<String> folded = <String>{};
    final Set<String> discoveredMachO = <String>{};
    await for (final FileSystemEntity entity in application.list(
      recursive: true,
      followLinks: false,
    )) {
      entries++;
      _expect(entries <= maximumTreeEntries, 'application-tree-too-large');
      final String relative = entity.path.substring(
        application.path.length + 1,
      );
      _expect(folded.add(relative.toLowerCase()), 'application-case-alias');
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      _expect(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
        'application-unsupported-entry',
      );
      if (type == FileSystemEntityType.file &&
          await _hasMachOMagic(File(entity.path))) {
        discoveredMachO.add(relative);
      }
      if (type == FileSystemEntityType.file) {
        final FileStat stat = await entity.stat();
        final bool executable = stat.mode & 0x49 != 0;
        _expect(
          !executable || terminalUpdateCodePaths.contains(relative),
          'application-code-inventory-differs',
        );
      }
    }
    _expect(
      _sameStrings(discoveredMachO.toList()..sort(), terminalUpdateCodePaths),
      'application-code-inventory-differs',
    );
  }

  Future<void> _publish({
    required Directory staging,
    required Directory output,
    required Directory backup,
  }) async {
    final FileSystemEntityType outputType = await FileSystemEntity.type(
      output.path,
      followLinks: false,
    );
    _expect(
      outputType == FileSystemEntityType.notFound ||
          outputType == FileSystemEntityType.directory,
      'output-path-invalid',
    );
    final FileSystemEntityType backupType = await FileSystemEntity.type(
      backup.path,
      followLinks: false,
    );
    _expect(
      backupType == FileSystemEntityType.notFound ||
          backupType == FileSystemEntityType.directory,
      'backup-path-invalid',
    );
    if (backupType == FileSystemEntityType.directory) {
      await backup.delete(recursive: true);
    }
    var movedOld = false;
    try {
      if (outputType == FileSystemEntityType.directory) {
        await output.rename(backup.path);
        movedOld = true;
      }
      faultInjector?.call('after-old-move');
      await staging.rename(output.path);
      if (movedOld && await backup.exists()) {
        try {
          await backup.delete(recursive: true);
        } on FileSystemException {
          // Publication already committed. A fixed sibling from the previous
          // successful output is safe to retain and will be cleaned first on
          // the next attempt.
        }
      }
    } on Object {
      if (movedOld &&
          await FileSystemEntity.type(output.path, followLinks: false) ==
              FileSystemEntityType.notFound &&
          await backup.exists()) {
        await backup.rename(output.path);
      }
      rethrow;
    }
  }

  Future<void> _recoverInterruptedPublication(Directory output) async {
    final Directory backup = Directory('${output.path}.last-good');
    final FileSystemEntityType outputType = await FileSystemEntity.type(
      output.path,
      followLinks: false,
    );
    final FileSystemEntityType backupType = await FileSystemEntity.type(
      backup.path,
      followLinks: false,
    );
    _expect(
      outputType == FileSystemEntityType.notFound ||
          outputType == FileSystemEntityType.directory,
      'output-path-invalid',
    );
    _expect(
      backupType == FileSystemEntityType.notFound ||
          backupType == FileSystemEntityType.directory,
      'backup-path-invalid',
    );
    if (outputType == FileSystemEntityType.notFound &&
        backupType == FileSystemEntityType.directory) {
      await backup.rename(output.path);
    }
  }
}

Future<_SafeSymbolPaths> _safePaths(
  Directory application,
  Directory output,
) async {
  _expect(
    application.path == application.absolute.path,
    'application-not-absolute',
  );
  _expect(output.path == output.absolute.path, 'output-not-absolute');
  _expect(
    await FileSystemEntity.type(application.path, followLinks: false) ==
        FileSystemEntityType.directory,
    'application-invalid',
  );
  final String resolvedApplication = await application.resolveSymbolicLinks();
  final Directory outputParent = output.parent;
  _expect(
    await FileSystemEntity.type(outputParent.path, followLinks: false) ==
        FileSystemEntityType.directory,
    'output-parent-invalid',
  );
  final String resolvedOutputParent = await outputParent.resolveSymbolicLinks();
  final List<String> outputSegments = output.uri.pathSegments
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  _expect(outputSegments.isNotEmpty, 'output-name-invalid');
  final String outputLeaf = outputSegments.last;
  _expect(
    outputLeaf.isNotEmpty &&
        outputLeaf != '.' &&
        outputLeaf != '..' &&
        utf8.encode(outputLeaf).length <= 200,
    'output-name-invalid',
  );
  final String resolvedOutput = '$resolvedOutputParent/$outputLeaf';
  _expect(
    !_pathsOverlap(resolvedApplication, resolvedOutput),
    'input-output-overlap',
  );
  return _SafeSymbolPaths(
    application: Directory(resolvedApplication),
    output: Directory(resolvedOutput),
  );
}

List<String> _validateRuntimeManifest(Map<String, Object?> manifest) {
  _expect(
    manifest['runtimeMode'] == 'release-aot' &&
        manifest['bundleIdentifier'] == terminalUpdateProduct,
    'runtime-manifest-invalid',
  );
  final List<String> architectures;
  if (manifest['schemaVersion'] == 1) {
    final Object? architecture = manifest['architecture'];
    _expect(
      architecture == 'arm64' || architecture == 'x86_64',
      'runtime-manifest-invalid',
    );
    architectures = <String>[architecture! as String];
  } else if (manifest['schemaVersion'] == 2) {
    architectures = _stringList(manifest['architectures']);
    _expect(
      _sameStrings(architectures, const <String>['arm64', 'x86_64']),
      'runtime-manifest-invalid',
    );
    _expect(
      _sameStrings(_stringList(manifest['codePaths']), terminalUpdateCodePaths),
      'runtime-manifest-invalid',
    );
  } else {
    throw const TerminalReleaseSymbolsException('runtime-manifest-invalid');
  }
  return List<String>.unmodifiable(architectures);
}

Future<Map<String, Object?>> _readJsonObject(
  File file, {
  required int maximumBytes,
  required String failure,
}) async {
  await _validateRegularFile(
    file,
    maximumBytes: maximumBytes,
    failure: failure,
  );
  try {
    final Object? decoded = jsonDecode(
      utf8.decode(await file.readAsBytes(), allowMalformed: false),
    );
    _expect(decoded is Map<String, Object?>, failure);
    return decoded! as Map<String, Object?>;
  } on TerminalReleaseSymbolsException {
    rethrow;
  } on Object {
    throw TerminalReleaseSymbolsException(failure);
  }
}

Future<void> _validateRegularFile(
  File file, {
  required int maximumBytes,
  required String failure,
}) async {
  _expect(
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file,
    failure,
  );
  final int length = await file.length();
  _expect(length >= 1 && length <= maximumBytes, failure);
}

Future<bool> _hasMachOMagic(File file) async {
  final RandomAccessFile input = await file.open();
  try {
    final List<int> bytes = await input.read(4);
    if (bytes.length != 4) return false;
    final String magic = bytes
        .map((int value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return const <String>{
      'feedface',
      'cefaedfe',
      'feedfacf',
      'cffaedfe',
      'cafebabe',
      'bebafeca',
      'cafebabf',
      'bfbafeca',
    }.contains(magic);
  } finally {
    await input.close();
  }
}

List<String> _stringList(Object? value) {
  _expect(
    value is List<Object?> && value.every((Object? item) => item is String),
    'runtime-manifest-invalid',
  );
  return (value! as List<Object?>).cast<String>();
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> a = left.toList(growable: false);
  final List<String> b = right.toList(growable: false);
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameUuids(List<_MachOUuid> left, List<_MachOUuid> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (int index) =>
          left[index].architecture == right[index].architecture &&
          left[index].uuid == right[index].uuid,
    ).every((bool value) => value);

int _architectureIndex(String architecture) => architecture == 'arm64' ? 0 : 1;

bool _pathsOverlap(String left, String right) =>
    left == right || _isInside(left, right) || _isInside(right, left);

bool _isInside(String parent, String child) =>
    child.startsWith('$parent${Platform.pathSeparator}');

String _nonce() {
  final Random random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
}

void _expect(bool condition, String code) {
  if (!condition) throw TerminalReleaseSymbolsException(code);
}

final class _SafeSymbolPaths {
  const _SafeSymbolPaths({required this.application, required this.output});

  final Directory application;
  final Directory output;
}

final class _MachOUuid {
  const _MachOUuid({required this.architecture, required this.uuid});

  final String architecture;
  final String uuid;
}

final class _BoundedCommandOutput {
  const _BoundedCommandOutput({required this.text, required this.exceeded});

  final String text;
  final bool exceeded;
}
