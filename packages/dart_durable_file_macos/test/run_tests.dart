import 'dart:io';
import 'dart:typed_data';

import 'package:dart_durable_file_macos/dart_durable_file_macos.dart';

Future<void> main() async {
  _expect(
    MacosDurableDirectorySession.abiVersion == 1,
    'native ABI version is exact',
  );
  _testSourceBoundary();
  final int baseline = MacosDurableDirectorySession.debugOpenSessionCount;
  final Directory parent = await Directory.systemTemp.createTemp(
    'dart-durable-file-',
  );
  final Directory resolvedParent = Directory(
    await parent.resolveSymbolicLinks(),
  );
  try {
    await _testLifecycleAndPermissions(resolvedParent);
    await _testUnsafeEntries(resolvedParent);
    await _testLockContention(resolvedParent);
    await _testInputAndSizeBounds(resolvedParent);
  } finally {
    await parent.delete(recursive: true);
  }
  _expect(
    MacosDurableDirectorySession.debugOpenSessionCount == baseline,
    'all native directory sessions are closed',
  );
  stdout.writeln(
    'DART_DURABLE_FILE_MACOS_PASS '
    'permissions=true links=true lock=true fsync=true',
  );
}

Future<void> _testLifecycleAndPermissions(Directory parent) async {
  final String path = '${parent.path}/nested/store';
  Directory(path).createSync(recursive: true);
  await Process.run('/bin/chmod', <String>['0755', path]);
  final MacosDurableDirectorySession session =
      MacosDurableDirectorySession.open(path, create: true);
  try {
    _expect(
      FileStat.statSync(path).mode & 0x1ff == 0x1c0,
      'created directory is mode 0700',
    );
    session.acquireExclusiveLock('owner.lock');
    _expect(
      FileStat.statSync('$path/owner.lock').mode & 0x1ff == 0x180,
      'lock file is mode 0600',
    );
    final Uint8List payload = Uint8List.fromList(<int>[1, 2, 3, 4]);
    session.writeExclusive('candidate.tmp', payload);
    final MacosDurableFileInfo temporary = session.inspect('candidate.tmp');
    _expect(
      temporary.exists &&
          temporary.length == payload.length &&
          temporary.permissionBits == 0x180 &&
          temporary.linkCount == 1,
      'exclusive temporary is bounded regular 0600 with one link',
    );
    _expectBytes(
      session.read('candidate.tmp'),
      payload,
      'descriptor-relative read is exact',
    );
    session.rename('candidate.tmp', 'current.data');
    session.flushDirectory();
    _expect(
      !session.inspect('candidate.tmp').exists &&
          session.inspect('current.data').exists,
      'rename and directory fsync publish one target',
    );

    await Process.run('/bin/chmod', <String>['0644', '$path/current.data']);
    _expectBytes(
      session.read('current.data'),
      payload,
      'broad owned permission is narrowed before read',
    );
    _expect(
      FileStat.statSync('$path/current.data').mode & 0x1ff == 0x180,
      'read normalization restores mode 0600',
    );
    _expectFailure(
      () => session.writeExclusive('current.data', payload),
      MacosDurableFileFailure.alreadyExists,
      'exclusive write never overwrites an existing leaf',
    );
    session.unlink('current.data');
    session.unlink('current.data', missingOkay: true);
    session.flushDirectory();
  } finally {
    session.close();
    session.close();
  }
  _expectFailure(
    () => session.inspect('after-close'),
    MacosDurableFileFailure.invalidState,
    'closed session cannot be reused',
  );
}

void _testSourceBoundary() {
  for (final String path in <String>[
    'lib/dart_durable_file_macos.dart',
    'lib/src/durable_file.dart',
    'native/DurableFile.c',
    'hook/build.dart',
  ]) {
    final String source = File(path).readAsStringSync();
    for (final String forbidden in <String>[
      'dart_terminal',
      'TerminalNote',
      'dart_appkit',
      'dart_pty',
      'AppKit',
    ]) {
      _expect(
        !source.contains(forbidden),
        'generic durable-file source excludes $forbidden',
      );
    }
  }
}

Future<void> _testUnsafeEntries(Directory parent) async {
  final String path = '${parent.path}/unsafe';
  final MacosDurableDirectorySession session =
      MacosDurableDirectorySession.open(path, create: true);
  try {
    final File regular = File('$path/regular')..writeAsBytesSync(<int>[1]);
    await Process.run('/bin/ln', <String>[regular.path, '$path/hard-link']);
    _expectFailure(
      () => session.inspect('regular'),
      MacosDurableFileFailure.hardLink,
      'source with a second hard link is rejected',
    );
    _expectFailure(
      () => session.read('hard-link'),
      MacosDurableFileFailure.hardLink,
      'hard-link alias is rejected',
    );
    final File outside = File('${parent.path}/outside')
      ..writeAsBytesSync(<int>[2]);
    await Link('$path/symbolic').create(outside.path);
    _expectFailure(
      () => session.inspect('symbolic'),
      MacosDurableFileFailure.unsafeType,
      'symbolic file is rejected without following it',
    );
    Directory('$path/directory').createSync();
    _expectFailure(
      () => session.read('directory'),
      MacosDurableFileFailure.unsafeType,
      'directory leaf is rejected as a file',
    );
  } finally {
    session.close();
  }

  final Directory target = Directory('${parent.path}/real-directory')
    ..createSync();
  final Link directoryLink = Link('${parent.path}/directory-link');
  await directoryLink.create(target.path);
  _expectFailure(
    () => MacosDurableDirectorySession.open(directoryLink.path),
    MacosDurableFileFailure.unsafeType,
    'directory symlink traversal is rejected',
  );
}

Future<void> _testLockContention(Directory parent) async {
  final String path = '${parent.path}/contention';
  final MacosDurableDirectorySession first = MacosDurableDirectorySession.open(
    path,
    create: true,
  );
  final MacosDurableDirectorySession second = MacosDurableDirectorySession.open(
    path,
  );
  try {
    first.acquireExclusiveLock('store.lock');
    _expectFailure(
      () => second.acquireExclusiveLock('store.lock'),
      MacosDurableFileFailure.busy,
      'second open file description cannot acquire the held lock',
    );
  } finally {
    first.close();
  }
  try {
    second.acquireExclusiveLock('store.lock');
  } finally {
    second.close();
  }
}

Future<void> _testInputAndSizeBounds(Directory parent) async {
  final MacosDurableDirectorySession session =
      MacosDurableDirectorySession.open('${parent.path}/bounds', create: true);
  try {
    for (final String invalid in <String>['', '.', '..', '../escape', 'a/b']) {
      _expectFailure(
        () => session.inspect(invalid),
        MacosDurableFileFailure.invalidArgument,
        'unsafe leaf syntax is rejected',
      );
    }
    _expectFailure(
      () => session.writeExclusive(
        'too-large',
        Uint8List(MacosDurableFileLimits.maximumPayloadBytes + 1),
      ),
      MacosDurableFileFailure.tooLarge,
      'payload cap plus one is rejected before native write',
    );
    session.writeExclusive('empty', Uint8List(0));
    _expect(session.read('empty').isEmpty, 'zero-byte generic file is exact');
    _expectFailure(
      () => session.read('missing'),
      MacosDurableFileFailure.notFound,
      'missing file remains distinct from empty',
    );
  } finally {
    session.close();
  }
  _expectFailure(
    () => MacosDurableDirectorySession.open('relative/path'),
    MacosDurableFileFailure.invalidArgument,
    'directory path must be absolute',
  );
}

void _expectFailure(
  void Function() callback,
  MacosDurableFileFailure failure,
  String description,
) {
  try {
    callback();
  } on MacosDurableFileException catch (error) {
    _expect(
      error.failure == failure &&
          error.toString() == 'Durable file operation failed: ${failure.name}',
      description,
    );
    return;
  }
  throw StateError('expected durable file failure: $description');
}

void _expectBytes(List<int> actual, List<int> expected, String description) {
  _expect(actual.length == expected.length, description);
  for (var index = 0; index < actual.length; index++) {
    _expect(actual[index] == expected[index], description);
  }
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
