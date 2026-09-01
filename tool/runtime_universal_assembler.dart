import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'src/runtime_release_support.dart';

const String _assemblyFormat = 'dart-terminal-universal-release-assembly';
const int _assemblyVersion = 3;
const int _renameSwap = 0x00000002;
const int _renameExclusive = 0x00000004;

typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _MallocDart = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> pointer);
typedef _FreeDart = void Function(Pointer<Void> pointer);
typedef _RenamexNative = Int32 Function(
  Pointer<Uint8> from,
  Pointer<Uint8> to,
  Uint32 flags,
);
typedef _RenamexDart = int Function(
  Pointer<Uint8> from,
  Pointer<Uint8> to,
  int flags,
);
typedef _ErrorNative = Pointer<Int32> Function();
typedef _ErrorDart = Pointer<Int32> Function();

final class _Options {
  const _Options({
    required this.arm64Bundle,
    required this.arm64Report,
    required this.x86_64Bundle,
    required this.x86_64Report,
    required this.outputDirectory,
    required this.deploymentTarget,
  });

  final String arm64Bundle;
  final String arm64Report;
  final String x86_64Bundle;
  final String x86_64Report;
  final String outputDirectory;
  final String deploymentTarget;
}

_Options _parseOptions(List<String> arguments) {
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw RuntimeAuditException('unknown argument: $argument');
    }
    final int equals = argument.indexOf('=');
    final String name = argument.substring(2, equals);
    final String value = argument.substring(equals + 1);
    if (name.isEmpty || value.isEmpty || values.containsKey(name)) {
      throw RuntimeAuditException('invalid or duplicate option: --$name');
    }
    values[name] = value;
  }
  const Set<String> expected = <String>{
    'arm64-bundle',
    'arm64-report',
    'x86_64-bundle',
    'x86_64-report',
    'output-directory',
    'deployment-target',
  };
  final Set<String> unknown = values.keys.toSet().difference(expected);
  final Set<String> missing = expected.difference(values.keys.toSet());
  runtimeExpect(unknown.isEmpty, 'unknown options: ${unknown.join(',')}');
  runtimeExpect(missing.isEmpty, 'missing options: ${missing.join(',')}');
  return _Options(
    arm64Bundle: values['arm64-bundle']!,
    arm64Report: values['arm64-report']!,
    x86_64Bundle: values['x86_64-bundle']!,
    x86_64Report: values['x86_64-report']!,
    outputDirectory: values['output-directory']!,
    deploymentTarget: values['deployment-target']!,
  );
}

Future<bool> _filesEqual(String leftPath, String rightPath) async {
  final File left = File(leftPath);
  final File right = File(rightPath);
  final FileStat leftStat = await left.stat();
  final FileStat rightStat = await right.stat();
  if (leftStat.size != rightStat.size) {
    return false;
  }
  final RandomAccessFile leftReader = await left.open();
  final RandomAccessFile rightReader = await right.open();
  try {
    var remaining = leftStat.size;
    while (remaining > 0) {
      final int count = remaining > 64 * 1024 ? 64 * 1024 : remaining;
      final Uint8List leftBytes = await leftReader.read(count);
      final Uint8List rightBytes = await rightReader.read(count);
      if (leftBytes.length != rightBytes.length) {
        return false;
      }
      for (var index = 0; index < leftBytes.length; ++index) {
        if (leftBytes[index] != rightBytes[index]) {
          return false;
        }
      }
      remaining -= leftBytes.length;
    }
    return true;
  } finally {
    await leftReader.close();
    await rightReader.close();
  }
}

Map<String, Object?> _laneManifest(Map<String, Object?> audit) {
  final Map<String, Object?> manifest = runtimeStringMap(
    audit['build_manifest'],
    'thin build manifest',
  );
  return runtimeStringMap(
    manifest['architecture_inputs'],
    'thin manifest architecture_inputs',
  );
}

void _compareThinEntitlements(
  Map<String, Object?> arm64Audit,
  Map<String, Object?> x86_64Audit,
) {
  final Map<String, Object?> arm64 = runtimeStringMap(
    arm64Audit['entitlements'],
    'arm64 entitlements',
  );
  final Map<String, Object?> x86_64 = runtimeStringMap(
    x86_64Audit['entitlements'],
    'x86_64 entitlements',
  );
  runtimeExpect(
    sameStringSet(arm64.keys, x86_64.keys),
    'thin entitlement role sets differ',
  );
  for (final String role in arm64.keys) {
    final Map<String, Object?> armRole = runtimeStringMap(
      arm64[role],
      'arm64 $role entitlements',
    );
    final Map<String, Object?> x86Role = runtimeStringMap(
      x86_64[role],
      'x86_64 $role entitlements',
    );
    runtimeExpect(
      armRole.length == 1 &&
          armRole['arm64'] == 'none' &&
          x86Role.length == 1 &&
          x86Role['x86_64'] == 'none',
      'thin entitlement mismatch or non-empty entitlement for $role',
    );
  }
}

Future<void> _compareThinInputs(
  Directory arm64Bundle,
  Directory x86_64Bundle,
  Map<String, Object?> arm64Audit,
  Map<String, Object?> x86_64Audit,
) async {
  final Map<String, Object?> arm64Manifest = runtimeStringMap(
    arm64Audit['build_manifest'],
    'arm64 build manifest',
  );
  final Map<String, Object?> x86Manifest = runtimeStringMap(
    x86_64Audit['build_manifest'],
    'x86_64 build manifest',
  );
  runtimeExpect(
    arm64Manifest['architecture'] == 'arm64' &&
        x86Manifest['architecture'] == 'x86_64',
    'thin manifest architectures do not match their lanes',
  );
  runtimeExpect(
    runtimeCanonicalJsonEncode(
          runtimeCommonManifestProvenance(arm64Manifest),
        ) ==
        runtimeCanonicalJsonEncode(
          runtimeCommonManifestProvenance(x86Manifest),
        ),
    'thin common provenance/build manifests do not match',
  );
  _compareThinEntitlements(arm64Audit, x86_64Audit);

  final String arm64Contents = '${arm64Bundle.path}/Contents';
  final String x86Contents = '${x86_64Bundle.path}/Contents';
  final List<String> arm64Files = (await runtimeRelativeFiles(
    Directory(arm64Contents),
  )).where((String path) => !path.startsWith('_CodeSignature/')).toList();
  final List<String> x86Files = (await runtimeRelativeFiles(
    Directory(x86Contents),
  )).where((String path) => !path.startsWith('_CodeSignature/')).toList();
  runtimeExpect(
    arm64Files.length == x86Files.length &&
        arm64Files.indexed.every(
          ((int, String) entry) => entry.$2 == x86Files[entry.$1],
        ),
    'thin bundle layouts differ outside signatures',
  );

  final String executable = arm64Audit['executable']! as String;
  final Set<String> expectedMachO = runtimeExpectedMachOPaths(
    RuntimeMode.releaseAot,
    executable,
  );
  for (final String relative in arm64Files) {
    final String arm64Path = '$arm64Contents/$relative';
    final String x86Path = '$x86Contents/$relative';
    final bool arm64MachO = await runtimeIsMachO(arm64Path);
    final bool x86MachO = await runtimeIsMachO(x86Path);
    runtimeExpect(
      arm64MachO == x86MachO,
      'thin artifact kind differs: $relative',
    );
    if (expectedMachO.contains(relative)) {
      runtimeExpect(arm64MachO, 'expected Mach-O is not Mach-O: $relative');
      continue;
    }
    runtimeExpect(!arm64MachO, 'unexpected Mach-O file: $relative');
    if (relative == runtimeBuildManifestRelativePath) {
      continue;
    }
    runtimeExpect(
      await _filesEqual(arm64Path, x86Path),
      'non-Mach resource differs: $relative',
    );
  }
}

Future<void> _mergeMachO(
  String arm64Path,
  String x86_64Path,
  String outputPath,
) async {
  final String temporaryPath = '$outputPath.lipo.$pid';
  final File temporary = File(temporaryPath);
  try {
    await runRuntimeCommand('/usr/bin/lipo', <String>[
      '-create',
      arm64Path,
      x86_64Path,
      '-output',
      temporaryPath,
    ]);
    final List<String> architectures = await runtimeArchitectures(
      temporaryPath,
    );
    runtimeExpect(
      sameStringSet(architectures, supportedRuntimeArchitectures),
      'merged Mach-O architectures ${architectures.join(',')} != '
      'arm64,x86_64',
    );
    await File(outputPath).delete();
    await temporary.rename(outputPath);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

Pointer<Uint8> _nativeString(String value, _MallocDart malloc) {
  final Uint8List bytes = utf8.encode(value);
  final Pointer<Uint8> pointer = malloc(bytes.length + 1).cast<Uint8>();
  runtimeExpect(pointer.address != 0, 'malloc failed for atomic rename path');
  final Uint8List nativeBytes = pointer.asTypedList(bytes.length + 1);
  nativeBytes.setAll(0, bytes);
  nativeBytes[bytes.length] = 0;
  return pointer;
}

void _atomicRename(String left, String right, int flags) {
  final DynamicLibrary process = DynamicLibrary.process();
  final _MallocDart malloc = process.lookupFunction<_MallocNative, _MallocDart>(
    'malloc',
  );
  final _FreeDart free = process.lookupFunction<_FreeNative, _FreeDart>('free');
  final _RenamexDart renamex = process
      .lookupFunction<_RenamexNative, _RenamexDart>('renamex_np');
  final _ErrorDart error = process.lookupFunction<_ErrorNative, _ErrorDart>(
    '__error',
  );
  final Pointer<Uint8> leftPointer = _nativeString(left, malloc);
  final Pointer<Uint8> rightPointer = _nativeString(right, malloc);
  try {
    final int result = renamex(leftPointer, rightPointer, flags);
    if (result != 0) {
      throw RuntimeAuditException(
        'atomic output rename failed with errno ${error().value}',
      );
    }
  } finally {
    free(leftPointer.cast<Void>());
    free(rightPointer.cast<Void>());
  }
}

Future<String> _currentBundleDigest(String path) async {
  final Map<String, Object?> seal = await runtimeBundleSeal(path);
  return runtimeSha256Text(runtimeCanonicalJsonEncode(seal));
}

void _killAtFaultPoint(String point) {
  if (Platform.environment['DART_TERMINAL_UNIVERSAL_FAULT'] != point) {
    return;
  }
  stderr.writeln('RUNTIME_UNIVERSAL_FAULT_INJECTED point=$point');
  Process.killPid(pid, ProcessSignal.sigkill);
  sleep(const Duration(seconds: 1));
  throw RuntimeAuditException('SIGKILL fault injection did not terminate');
}

bool _matchesDirectoryEntry(
  RuntimePathSnapshot snapshot,
  String expectedPath,
  String? expectedIdentity,
) {
  final String normalized = runtimeNormalizedAbsolutePath(expectedPath);
  return expectedIdentity != null &&
      snapshot.requestedPath == normalized &&
      snapshot.canonicalPath == normalized &&
      snapshot.leafType == FileSystemEntityType.directory &&
      snapshot.targetType == FileSystemEntityType.directory &&
      snapshot.targetIdentity == expectedIdentity;
}

bool _matchesMissingEntry(
  RuntimePathSnapshot snapshot,
  RuntimePathSnapshot expected,
) =>
    snapshot.canonicalPath == expected.canonicalPath &&
    snapshot.leafType == FileSystemEntityType.notFound &&
    snapshot.targetType == FileSystemEntityType.notFound &&
    snapshot.targetIdentity == null;

bool _sameObservedEntry(RuntimePathSnapshot left, RuntimePathSnapshot right) =>
    left.requestedPath == right.requestedPath &&
    left.canonicalPath == right.canonicalPath &&
    left.leafType == right.leafType &&
    left.targetType == right.targetType &&
    left.targetIdentity == right.targetIdentity;

Future<void> _waitAtPublicationTestBarrier(
  String point,
  String stagingPath,
) async {
  final String? barrier =
      Platform.environment['DART_TERMINAL_UNIVERSAL_TEST_BARRIER'];
  final String requestedPoint =
      Platform.environment['DART_TERMINAL_UNIVERSAL_TEST_BARRIER_POINT'] ??
      'before-publish';
  if (barrier == null || requestedPoint != point) {
    return;
  }
  runtimeExpect(
    Directory(barrier).isAbsolute && await Directory(barrier).exists(),
    'publication test barrier must be an existing absolute directory',
  );
  final File ready = File('$barrier/ready');
  final File proceed = File('$barrier/continue');
  runtimeExpect(
    !await ready.exists() && !await proceed.exists(),
    'publication test barrier is not fresh',
  );
  await ready.create(exclusive: true);
  await ready.writeAsString('$pid\n$point\n$stagingPath\n', flush: true);
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!await proceed.exists()) {
    runtimeExpect(
      DateTime.now().isBefore(deadline),
      'publication test barrier timed out',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _syncPublishedDirectory() async {
  if (Platform.environment['DART_TERMINAL_UNIVERSAL_TEST_SYNC_FAILURE'] ==
      'after-publish') {
    throw RuntimeAuditException('injected post-publication sync failure');
  }
  await runRuntimeCommand('/bin/sync', const <String>[]);
}

Future<void> _deleteOwnedStaging(
  Directory staging,
  String? safeIdentity,
  bool published,
) async {
  final RuntimePathSnapshot current = await runtimePathSnapshot(staging.path);
  if (current.targetType == FileSystemEntityType.notFound) {
    return;
  }
  if (!_matchesDirectoryEntry(current, staging.path, safeIdentity)) {
    stderr.writeln(
      'RUNTIME_UNIVERSAL_STAGING_RETAINED path=${staging.path} '
      'reason=identity-or-entry-mismatch',
    );
    if (published) {
      throw RuntimeAuditException(
        'Universal staging changed before cleanup; replacement retained',
      );
    }
    return;
  }
  try {
    await staging.delete(recursive: true);
  } on Object catch (error) {
    if (!published) {
      rethrow;
    }
    stderr.writeln(
      'RUNTIME_UNIVERSAL_OLD_OUTPUT_CLEANUP_WARNING '
      '${staging.path}: $error',
    );
  }
}

Future<RandomAccessFile> _acquirePublisherLock(
  String path,
  RuntimeWriteDestinationGuard outputGuard,
) async {
  final RuntimePathSnapshot before = await runtimePathSnapshot(path);
  runtimeExpect(
    before.leafType != FileSystemEntityType.link &&
        (before.targetType == FileSystemEntityType.notFound ||
            before.targetType == FileSystemEntityType.file) &&
        !runtimePathSnapshotsOverlap(before, outputGuard.destination),
    'Universal publisher lock path is unsafe',
  );
  for (final RuntimePathSnapshot protected
      in outputGuard.protectedPaths.values) {
    runtimeExpect(
      !runtimePathSnapshotsOverlap(before, protected),
      'Universal publisher lock aliases a protected input',
    );
  }
  final RandomAccessFile handle = await File(path).open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.exclusive);
    final RuntimePathSnapshot after = await runtimePathSnapshot(path);
    runtimeExpect(
      after.leafType != FileSystemEntityType.link &&
          after.targetType == FileSystemEntityType.file &&
          !runtimePathSnapshotsOverlap(after, outputGuard.destination),
      'Universal publisher lock changed during acquisition',
    );
    for (final RuntimePathSnapshot protected
        in outputGuard.protectedPaths.values) {
      runtimeExpect(
        !runtimePathSnapshotsOverlap(after, protected),
        'Universal publisher lock aliases a protected input',
      );
    }
    return handle;
  } on Object catch (error) {
    await handle.close();
    throw RuntimeAuditException(
      'another Universal publisher is active or its lock is unsafe: $error',
    );
  }
}

Future<Map<String, Object?>> _assemble(_Options options) async {
  for (final String path in <String>[
    options.arm64Bundle,
    options.x86_64Bundle,
  ]) {
    runtimeExpect(
      Directory(path).isAbsolute,
      'bundle path must be absolute: $path',
    );
    runtimeExpect(path.endsWith('.app'), 'bundle path must end in .app: $path');
  }
  for (final String path in <String>[
    options.arm64Report,
    options.x86_64Report,
  ]) {
    runtimeExpect(File(path).isAbsolute, 'report path must be absolute: $path');
  }
  runtimeExpect(
    Directory(options.outputDirectory).isAbsolute,
    'output directory path must be absolute',
  );

  final RuntimeWriteDestinationGuard outputGuard =
      await runtimeValidateWriteDestination(
        description: 'Universal artifact directory',
        destination: options.outputDirectory,
        protectedPaths: <String, String>{
          'arm64 thin bundle': options.arm64Bundle,
          'arm64 thin receipt': options.arm64Report,
          'x86_64 thin bundle': options.x86_64Bundle,
          'x86_64 thin receipt': options.x86_64Report,
        },
        allowedExistingTypes: const <FileSystemEntityType>{
          FileSystemEntityType.directory,
        },
      );
  final String outputDirectory = outputGuard.destination.canonicalPath;
  final String resolvedArm64 =
      outputGuard.protectedPaths['arm64 thin bundle']!.canonicalPath;
  final String resolvedArm64Report =
      outputGuard.protectedPaths['arm64 thin receipt']!.canonicalPath;
  final String resolvedX86_64 =
      outputGuard.protectedPaths['x86_64 thin bundle']!.canonicalPath;
  final String resolvedX86_64Report =
      outputGuard.protectedPaths['x86_64 thin receipt']!.canonicalPath;
  final String output = '$outputDirectory/DartTerminal.app';
  final String outputReport = '$outputDirectory/assembly-report.json';
  final String outputAuditReport = '$outputDirectory/universal-audit.json';

  final Map<String, Object?> arm64Audit = await validateRuntimeAuditReceipt(
    resolvedArm64Report,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: const <String>{'arm64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: resolvedArm64,
    ),
  );
  final Map<String, Object?> x86_64Audit = await validateRuntimeAuditReceipt(
    resolvedX86_64Report,
    RuntimeBundleAuditOptions(
      mode: RuntimeMode.releaseAot,
      expectedArchitectures: const <String>{'x86_64'},
      deploymentTarget: options.deploymentTarget,
      bundlePath: resolvedX86_64,
    ),
  );
  await _compareThinInputs(
    Directory(resolvedArm64),
    Directory(resolvedX86_64),
    arm64Audit,
    x86_64Audit,
  );

  final String arm64ReportHash = await runtimeSha256File(resolvedArm64Report);
  final String x86_64ReportHash = await runtimeSha256File(resolvedX86_64Report);
  final Map<String, Object?> arm64Manifest = runtimeStringMap(
    arm64Audit['build_manifest'],
    'arm64 build manifest',
  );
  final String generation = await runtimeSha256Text(
    runtimeCanonicalJsonEncode(<String, Object?>{
      'format': _assemblyFormat,
      'version': _assemblyVersion,
      'arm64_receipt_sha256': arm64ReportHash,
      'x86_64_receipt_sha256': x86_64ReportHash,
      'deployment_target': options.deploymentTarget,
      'common_provenance': runtimeCommonManifestProvenance(arm64Manifest),
    }),
  );
  final Directory outputDirectoryEntity = Directory(outputDirectory);
  await outputDirectoryEntity.parent.create(recursive: true);
  await runtimeRevalidateWriteDestination(outputGuard);
  final String outputName = outputDirectoryEntity.uri.pathSegments
      .where((String segment) => segment.isNotEmpty)
      .last;
  final RandomAccessFile publisherLock = await _acquirePublisherLock(
    '${outputDirectoryEntity.parent.path}/.$outputName.publish.lock',
    outputGuard,
  );
  var published = false;
  var swappedExisting = false;
  Directory? cleanupStaging;
  String? safeCleanupIdentity;
  try {
    final Directory staging = await outputDirectoryEntity.parent.createTemp(
      '.$outputName.staging.$pid.',
    );
    cleanupStaging = staging;
    final RuntimePathSnapshot ownedStaging = await runtimePathSnapshot(
      staging.path,
    );
    runtimeExpect(
      _matchesDirectoryEntry(
        ownedStaging,
        staging.path,
        ownedStaging.targetIdentity,
      ),
      'Universal staging directory was not exclusively created',
    );
    safeCleanupIdentity = ownedStaging.targetIdentity;
    final String stagingBundle = '${staging.path}/DartTerminal.app';
    final String stagingAssemblyReport = '${staging.path}/assembly-report.json';
    final String stagingAuditReport = '${staging.path}/universal-audit.json';
    await runRuntimeCommand('/usr/bin/ditto', <String>[
      '--noqtn',
      resolvedArm64,
      stagingBundle,
    ]);
    final Directory inheritedSignature = Directory(
      '$stagingBundle/Contents/_CodeSignature',
    );
    if (await inheritedSignature.exists()) {
      await inheritedSignature.delete(recursive: true);
    }

    final String executable = arm64Audit['executable']! as String;
    final Map<String, String> machORoles = runtimeExpectedMachORoles(
      RuntimeMode.releaseAot,
      executable,
    );
    for (final String relative in machORoles.values.toList()..sort()) {
      await _mergeMachO(
        '$resolvedArm64/Contents/$relative',
        '$resolvedX86_64/Contents/$relative',
        '$stagingBundle/Contents/$relative',
      );
    }

    final Map<String, Object?> universalManifest = runtimeStringMap(
      jsonDecode(jsonEncode(arm64Manifest)),
      'Universal build manifest',
    );
    final Map<String, Object?> universalHashes = <String, Object?>{};
    for (final MapEntry<String, String> role in machORoles.entries) {
      universalHashes[role.key] = await runtimeSha256File(
        '$stagingBundle/Contents/${role.value}',
      );
    }
    universalManifest['architecture'] = 'universal';
    universalManifest['publication_generation_sha256'] = generation;
    universalManifest['architecture_inputs'] = <String, Object?>{
      'architectures': <String>['arm64', 'x86_64'],
      'thin_lanes': <String, Object?>{
        'arm64': _laneManifest(arm64Audit),
        'x86_64': _laneManifest(x86_64Audit),
      },
      'produced_sha256': universalHashes,
    };
    await runtimeWriteJsonIfChanged(
      '$stagingBundle/Contents/$runtimeBuildManifestRelativePath',
      universalManifest,
    );

    for (final String relative in <String>[
      'Resources/application.aot',
      'Frameworks/libdart_engine_aot_shared.dylib',
      'MacOS/$executable',
    ]) {
      await runRuntimeCommand('/usr/bin/codesign', <String>[
        '--force',
        '--sign',
        '-',
        '--timestamp=none',
        '$stagingBundle/Contents/$relative',
      ]);
    }
    await runRuntimeCommand('/usr/bin/codesign', <String>[
      '--force',
      '--sign',
      '-',
      '--timestamp=none',
      stagingBundle,
    ]);

    final Map<String, Object?> universalAudit = await auditRuntimeBundle(
      RuntimeBundleAuditOptions(
        mode: RuntimeMode.releaseAot,
        expectedArchitectures: supportedRuntimeArchitectures,
        deploymentTarget: options.deploymentTarget,
        bundlePath: stagingBundle,
      ),
    );
    runtimeExpect(
      await _currentBundleDigest(resolvedArm64) ==
              arm64Audit['artifact_digest'] &&
          await _currentBundleDigest(resolvedX86_64) ==
              x86_64Audit['artifact_digest'] &&
          await runtimeSha256File(resolvedArm64Report) == arm64ReportHash &&
          await runtimeSha256File(resolvedX86_64Report) == x86_64ReportHash,
      'thin input changed during Universal assembly',
    );
    universalAudit['path'] = output;
    final Map<String, Object?> result = <String, Object?>{
      'arm64_input': resolvedArm64,
      'arm64_receipt_sha256': arm64ReportHash,
      'x86_64_input': resolvedX86_64,
      'x86_64_receipt_sha256': x86_64ReportHash,
      'output_directory': outputDirectory,
      'output': output,
      'assembly_report': outputReport,
      'runtime_audit_receipt': outputAuditReport,
      'publication_generation_sha256': generation,
      'architectures': <String>['arm64', 'x86_64'],
      'merged_mach_o': machORoles.values.toList()..sort(),
      'common_provenance': runtimeCommonManifestProvenance(arm64Manifest),
      'thin_lanes': <String, Object?>{
        'arm64': _laneManifest(arm64Audit),
        'x86_64': _laneManifest(x86_64Audit),
      },
      'audit': universalAudit,
      'publication': 'single-directory-same-volume-atomic-rename',
      'passed': true,
    };
    final Map<String, Object?> report = <String, Object?>{
      'format': _assemblyFormat,
      'version': _assemblyVersion,
      'status': 'pass',
      'publication_generation_sha256': generation,
      'result': result,
    };
    final Map<String, Object?> auditReceipt = <String, Object?>{
      'format': runtimeBundleAuditFormat,
      'version': runtimeBundleAuditVersion,
      'status': 'pass',
      'publication_generation_sha256': generation,
      'result': universalAudit,
    };
    await runtimeWriteJsonIfChanged(stagingAuditReport, auditReceipt);
    await runtimeWriteJsonIfChanged(stagingAssemblyReport, report);
    await runRuntimeCommand('/bin/sync', const <String>[]);
    runtimeExpect(
      await _currentBundleDigest(resolvedArm64) ==
              arm64Audit['artifact_digest'] &&
          await _currentBundleDigest(resolvedX86_64) ==
              x86_64Audit['artifact_digest'] &&
          await runtimeSha256File(resolvedArm64Report) == arm64ReportHash &&
          await runtimeSha256File(resolvedX86_64Report) == x86_64ReportHash,
      'thin input changed immediately before Universal publication',
    );
    await runtimeRevalidateWriteDestination(outputGuard);
    _killAtFaultPoint('after-stage-sync');

    final RuntimePathSnapshot capturedOutput = await runtimePathSnapshot(
      outputDirectory,
    );
    final RuntimePathSnapshot capturedStaging = await runtimePathSnapshot(
      staging.path,
    );
    runtimeExpect(
      outputGuard.destination.exists
          ? _matchesDirectoryEntry(
              capturedOutput,
              outputDirectory,
              outputGuard.destination.targetIdentity,
            )
          : _matchesMissingEntry(capturedOutput, outputGuard.destination),
      'Universal artifact directory changed before publication capture',
    );
    runtimeExpect(
      _matchesDirectoryEntry(
        capturedStaging,
        staging.path,
        ownedStaging.targetIdentity,
      ),
      'Universal staging directory changed before publication',
    );
    final String capturedStagingIdentity = capturedStaging.targetIdentity!;
    await _waitAtPublicationTestBarrier('before-publish', staging.path);
    final RuntimePathSnapshot readyStaging = await runtimePathSnapshot(
      staging.path,
    );
    runtimeExpect(
      _matchesDirectoryEntry(
        readyStaging,
        staging.path,
        capturedStagingIdentity,
      ),
      'Universal staging directory changed immediately before publication',
    );

    if (capturedOutput.targetType == FileSystemEntityType.directory) {
      _atomicRename(staging.path, outputDirectory, _renameSwap);
      swappedExisting = true;
      final RuntimePathSnapshot displaced = await runtimePathSnapshot(
        staging.path,
      );
      final RuntimePathSnapshot installed = await runtimePathSnapshot(
        outputDirectory,
      );
      if (!_matchesDirectoryEntry(
            displaced,
            staging.path,
            capturedOutput.targetIdentity,
          ) ||
          !_matchesDirectoryEntry(
            installed,
            outputDirectory,
            capturedStagingIdentity,
          )) {
        safeCleanupIdentity = null;
        try {
          final RuntimePathSnapshot beforeRollbackOutput =
              await runtimePathSnapshot(outputDirectory);
          final RuntimePathSnapshot beforeRollbackStaging =
              await runtimePathSnapshot(staging.path);
          runtimeExpect(
            _sameObservedEntry(beforeRollbackOutput, installed) &&
                _sameObservedEntry(beforeRollbackStaging, displaced),
            'Universal publication changed again before rollback; '
            'displaced directory retained',
          );
          _atomicRename(staging.path, outputDirectory, _renameSwap);
          swappedExisting = false;
          final RuntimePathSnapshot restoredOutput = await runtimePathSnapshot(
            outputDirectory,
          );
          final RuntimePathSnapshot recoveredStaging =
              await runtimePathSnapshot(staging.path);
          final bool restoredObservedEntry =
              restoredOutput.targetIdentity == displaced.targetIdentity &&
              restoredOutput.leafType == displaced.leafType &&
              recoveredStaging.targetIdentity == installed.targetIdentity &&
              recoveredStaging.leafType == installed.leafType;
          if (_matchesDirectoryEntry(
            recoveredStaging,
            staging.path,
            capturedStagingIdentity,
          )) {
            safeCleanupIdentity = capturedStagingIdentity;
          }
          await runRuntimeCommand('/bin/sync', const <String>[]);
          runtimeExpect(
            restoredObservedEntry,
            'Universal publication rollback identity mismatch; '
            'unproven directory retained',
          );
        } on Object catch (rollbackError) {
          throw RuntimeAuditException(
            'Universal destination changed during atomic publication and '
            'rollback failed; displaced directory retained: $rollbackError',
          );
        }
        throw RuntimeAuditException(
          'Universal destination changed during atomic publication',
        );
      }
      safeCleanupIdentity = capturedOutput.targetIdentity;
    } else {
      runtimeExpect(
        _matchesMissingEntry(capturedOutput, outputGuard.destination),
        'Universal artifact directory changed before publication',
      );
      _atomicRename(staging.path, outputDirectory, _renameExclusive);
      final RuntimePathSnapshot installed = await runtimePathSnapshot(
        outputDirectory,
      );
      runtimeExpect(
        _matchesDirectoryEntry(
          installed,
          outputDirectory,
          capturedStagingIdentity,
        ),
        'unexpected Universal generation installed during publication',
      );
    }
    _killAtFaultPoint('after-publish-before-sync');
    await _waitAtPublicationTestBarrier(
      'after-publish-before-sync',
      staging.path,
    );
    try {
      await _syncPublishedDirectory();
    } on Object catch (publishError) {
      safeCleanupIdentity = null;
      if (!swappedExisting) {
        final RuntimePathSnapshot retainedOutput = await runtimePathSnapshot(
          outputDirectory,
        );
        throw RuntimeAuditException(
          'post-publication sync failed; complete or competing public '
          'directory retained without rollback: '
          'identity=${retainedOutput.targetIdentity} error=$publishError',
        );
      }
      try {
        final RuntimePathSnapshot beforeRollbackOutput =
            await runtimePathSnapshot(outputDirectory);
        final RuntimePathSnapshot beforeRollbackStaging =
            await runtimePathSnapshot(staging.path);
        runtimeExpect(
          _matchesDirectoryEntry(
                beforeRollbackOutput,
                outputDirectory,
                capturedStagingIdentity,
              ) &&
              _matchesDirectoryEntry(
                beforeRollbackStaging,
                staging.path,
                capturedOutput.targetIdentity,
              ),
          'Universal publication changed before sync rollback; '
          'displaced directory retained',
        );
        _atomicRename(staging.path, outputDirectory, _renameSwap);
        swappedExisting = false;
        final RuntimePathSnapshot restoredOutput = await runtimePathSnapshot(
          outputDirectory,
        );
        final RuntimePathSnapshot recoveredStaging = await runtimePathSnapshot(
          staging.path,
        );
        runtimeExpect(
          _matchesDirectoryEntry(
                restoredOutput,
                outputDirectory,
                capturedOutput.targetIdentity,
              ) &&
              _matchesDirectoryEntry(
                recoveredStaging,
                staging.path,
                capturedStagingIdentity,
              ),
          'Universal sync rollback identity mismatch; '
          'unproven directory retained',
        );
        safeCleanupIdentity = capturedStagingIdentity;
        await runRuntimeCommand('/bin/sync', const <String>[]);
      } on Object catch (rollbackError) {
        throw RuntimeAuditException(
          'Universal publication sync failed and rollback failed; '
          'displaced directory retained: publish=$publishError '
          'rollback=$rollbackError',
        );
      }
      throw publishError;
    }
    published = true;
    await _waitAtPublicationTestBarrier('before-cleanup', staging.path);
    return report;
  } finally {
    try {
      if (cleanupStaging != null) {
        await _deleteOwnedStaging(
          cleanupStaging,
          safeCleanupIdentity,
          published,
        );
      }
    } finally {
      try {
        await publisherLock.unlock();
      } finally {
        await publisherLock.close();
      }
    }
  }
}

Future<void> main(List<String> arguments) async {
  _Options? options;
  Map<String, Object?> report;
  var passed = true;
  try {
    options = _parseOptions(arguments);
    report = await _assemble(options);
  } on Object catch (error) {
    passed = false;
    report = <String, Object?>{
      'format': _assemblyFormat,
      'version': _assemblyVersion,
      'status': 'fail',
      'result': <String, Object?>{
        if (options != null) 'output_directory': options.outputDirectory,
        'passed': false,
        'error': error.toString(),
      },
    };
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  stderr.writeln('RUNTIME_UNIVERSAL_ASSEMBLY_${passed ? 'PASS' : 'FAIL'}');
  if (!passed) {
    exitCode = options == null ? 64 : 1;
  }
}
