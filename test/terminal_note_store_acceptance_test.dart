import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_durable_file_macos/dart_durable_file_macos.dart';
import 'package:dart_terminal/dart_terminal.dart';

const String _lockReadyLine = 'NOTE_STORE_LOCK_HELPER_READY';
const String _lockStoppedLine = 'NOTE_STORE_LOCK_HELPER_STOPPED';
const String _workerLogPassLine = 'NOTE_STORE_WORKER_LOG_PASS';
const String _bodySentinel = 'PRIVATE-WORKER-LOG-BODY-SENTINEL';
const String _idSentinel = 'deadbeefdeadbeefdeadbeefdeadbeef';
const String _timeSentinel = '777777777777';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 2 && arguments[0] == '--lock-helper') {
    await _runLockHelper(arguments[1]);
    return;
  }
  if (arguments.length == 2 && arguments[0] == '--worker-log-helper') {
    await _runWorkerLogHelper(arguments[1]);
    return;
  }
  await runTerminalNoteStoreAcceptanceTests();
}

Future<void> runTerminalNoteStoreAcceptanceTests() async {
  if (!Platform.isMacOS) {
    throw StateError('terminal Note store acceptance requires macOS');
  }
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-acceptance-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  try {
    await _testRealPermissionsLinksAndOrphans(root);
    await _testRealRecoveryDeletionAndExport(root);
    await _testTwoProcessContention(root);
    await _testWorkerLogPrivacy(root);
    final int commitP95Micros = await _measureOneMibWorkerCommit(root);
    final int primitiveP95Micros = _measureSixteenMibPrimitive(root);
    _expect(
      commitP95Micros <= 250000,
      '1 MiB durable worker commit p95 exceeds 250 ms',
    );
    _expect(
      primitiveP95Micros <= 1500000,
      '16 MiB durable primitive p95 exceeds 1.5 s',
    );
    stdout.writeln(
      'TERMINAL_NOTE_STORE_ACCEPTANCE_PASS '
      'runs=20 commit_p95_us=$commitP95Micros '
      'primitive_p95_us=$primitiveP95Micros '
      'contention=true recovery=true privacy=true',
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> _testRealPermissionsLinksAndOrphans(Directory root) async {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteStoreDocument document = _twoNoteDocument();
  final String permissionPath = '${root.path}/permissions';
  Directory(permissionPath).createSync();
  await _chmod('0755', permissionPath);
  final File current = File(
    '$permissionPath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
  )..writeAsBytesSync(codec.encode(document), flush: true);
  await _chmod('0644', current.path);
  final TerminalNoteStoreTransactionEngine permissionEngine =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(permissionPath),
      );
  final TerminalNoteStoreResult loaded = permissionEngine.load();
  _expect(
    loaded.disposition == TerminalNoteStoreDisposition.loaded &&
        _permissionBits(permissionPath) == 0x1c0 &&
        _permissionBits(current.path) == 0x180,
    'real store narrows directory to 0700 and current file to 0600',
  );
  permissionEngine.stop();

  final String orphanPath = '${root.path}/orphan';
  Directory(orphanPath).createSync();
  final File orphan = File('$orphanPath/store.pending')
    ..writeAsBytesSync(<int>[1, 2, 3], flush: true);
  final TerminalNoteStoreTransactionEngine orphanEngine =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(orphanPath),
      );
  _expect(
    orphanEngine.load().disposition == TerminalNoteStoreDisposition.empty &&
        !orphan.existsSync(),
    'owned safe orphan pending is removed before an empty load',
  );
  orphanEngine.stop();

  final Directory linkTarget = Directory('${root.path}/link-target')
    ..createSync();
  final Link directoryLink = Link('${root.path}/directory-link');
  await directoryLink.create(linkTarget.path);
  _expectThrowsStore(
    () => TerminalNoteStoreTransactionEngine.open(
      location: TerminalNoteStoreLocation.fromAbsolutePath(directoryLink.path),
    ),
    TerminalNoteStoreFailure.unsafeFile,
    'directory symlink is rejected without traversal',
  );

  final String symlinkLeafPath = '${root.path}/symlink-leaf';
  Directory(symlinkLeafPath).createSync();
  final File outside = File('${root.path}/outside-store')
    ..writeAsBytesSync(codec.encode(document), flush: true);
  await Link(
    '$symlinkLeafPath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
  ).create(outside.path);
  final TerminalNoteStoreTransactionEngine symlinkEngine =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(symlinkLeafPath),
      );
  _expect(
    symlinkEngine.load().failure == TerminalNoteStoreFailure.unsafeFile,
    'current symlink is rejected without reading its target',
  );
  symlinkEngine.stop();

  final String hardLinkPath = '${root.path}/hard-link';
  Directory(hardLinkPath).createSync();
  final File hardSource = File('${root.path}/hard-source')
    ..writeAsBytesSync(codec.encode(document), flush: true);
  final ProcessResult linkResult = await Process.run('/bin/ln', <String>[
    hardSource.path,
    '$hardLinkPath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
  ]);
  _expect(linkResult.exitCode == 0, 'hard-link fixture is created');
  final TerminalNoteStoreTransactionEngine hardLinkEngine =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(hardLinkPath),
      );
  _expect(
    hardLinkEngine.load().failure == TerminalNoteStoreFailure.unsafeFile,
    'multi-link current file is rejected',
  );
  hardLinkEngine.stop();
}

Future<void> _testRealRecoveryDeletionAndExport(Directory root) async {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final TerminalNoteStoreDocument base = _twoNoteDocument();
  final TerminalNoteStoreDocument edited = _editSecond(base);
  final String recoveryPath = '${root.path}/recovery';
  final TerminalNoteStoreTransactionEngine writer =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(recoveryPath),
      );
  _expect(writer.load().isSuccess, 'recovery writer starts empty');
  _expect(writer.commitCandidate(base).isSuccess, 'base current commits');
  _expect(writer.commitCandidate(edited).isSuccess, 'edited current commits');
  writer.stop();

  final File current = File(
    '$recoveryPath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
  )..writeAsBytesSync(<int>[1, 2, 3], flush: true);
  final Uint8List corruptBytes = current.readAsBytesSync();
  final TerminalNoteStoreTransactionEngine recovery =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(recoveryPath),
      );
  final TerminalNoteStoreResult preview = recovery.load();
  _expect(
    preview.disposition == TerminalNoteStoreDisposition.recoveryPreview &&
        _sameDocument(preview.document!, base) &&
        _bytesEqual(current.readAsBytesSync(), corruptBytes),
    'invalid current returns backup preview without automatic overwrite',
  );
  _expect(
    recovery.retryRecovery().disposition ==
        TerminalNoteStoreDisposition.committed,
    'explicit recovery restores real current and backup',
  );
  recovery.stop();
  for (final String leaf in <String>[
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
  ]) {
    _expect(
      _sameDocument(
        codec.decode(File('$recoveryPath/$leaf').readAsBytesSync()),
        base,
      ),
      'explicit recovery publishes the preview to both copies',
    );
  }

  final String deletionPath = '${root.path}/deletion';
  final TerminalNoteDeletionTombstone tombstone = TerminalNoteDeletionTombstone(
    noteId: _noteId(1),
    deletionRevision: base.snapshot.storeRevision + BigInt.one,
  );
  final MacosDurableDirectorySession setup = MacosDurableDirectorySession.open(
    deletionPath,
    create: true,
  );
  try {
    _replaceLeaf(
      setup,
      TerminalNoteStoreTransactionEngine.currentLeaf,
      codec.encode(base),
      'setup-current.pending',
    );
    _replaceLeaf(
      setup,
      TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
      codec.encodeDeletionJournal(
        TerminalNoteDeletionJournal(
          entries: <TerminalNoteDeletionTombstone>[tombstone],
        ),
      ),
      'setup-deletion.pending',
    );
  } finally {
    setup.close();
  }
  final TerminalNoteStoreTransactionEngine deletion =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(deletionPath),
      );
  final TerminalNoteStoreResult filtered = deletion.load();
  _expect(
    filtered.disposition == TerminalNoteStoreDisposition.loaded &&
        filtered.document!.snapshot.noteFor(_noteId(1)) == null &&
        filtered.document!.snapshot.noteFor(_noteId(2)) != null,
    'real durable journal filters deleted Note from current load',
  );

  final String exportPath = '${root.path}/exports';
  Directory(exportPath).createSync();
  await _chmod('0755', exportPath);
  final File exported = File('$exportPath/共有メモ.json');
  _expect(
    deletion.exportToApprovedPath(null).disposition ==
            TerminalNoteStoreDisposition.cancelled &&
        !exported.existsSync(),
    'real export cancellation performs no destination write',
  );
  final TerminalNoteStoreResult exportResult = deletion.exportToApprovedPath(
    TerminalNoteApprovedExportPath.fromAbsolutePath(exported.path),
  );
  final String exportSource = exported.readAsStringSync();
  _expect(
    exportResult.isSuccess &&
        _permissionBits(exportPath) == 0x1ed &&
        _permissionBits(exported.path) == 0x180 &&
        !exportSource.contains('deleted private body') &&
        !exportSource.contains(_noteId(1).canonicalValue) &&
        exportSource.contains('remaining private body'),
    'real portable export preserves parent mode and never resurrects deletion',
  );

  final TerminalNoteStoreDocument next = _withRevision(
    filtered.document!,
    filtered.document!.snapshot.storeRevision + BigInt.one,
  );
  _expect(
    deletion.commitCandidate(next).isSuccess,
    'next real commit makes both copies deletion-safe',
  );
  deletion.stop();
  _expect(
    !File(
      '$deletionPath/${TerminalNoteStoreTransactionEngine.deletionJournalLeaf}',
    ).existsSync(),
    'verified real copies compact the deletion journal',
  );
  for (final String leaf in <String>[
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
  ]) {
    final TerminalNoteStoreDocument stored = codec.decode(
      File('$deletionPath/$leaf').readAsBytesSync(),
    );
    _expect(
      stored.snapshot.noteFor(_noteId(1)) == null,
      'deleted Note is absent from each real durable copy',
    );
  }

  final String journalOnlyPath = '${root.path}/journal-only';
  final MacosDurableDirectorySession journalOnlySetup =
      MacosDurableDirectorySession.open(journalOnlyPath, create: true);
  try {
    _replaceLeaf(
      journalOnlySetup,
      TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
      codec.encodeDeletionJournal(
        TerminalNoteDeletionJournal(
          entries: <TerminalNoteDeletionTombstone>[tombstone],
        ),
      ),
      'setup-journal.pending',
    );
  } finally {
    journalOnlySetup.close();
  }
  final TerminalNoteStoreTransactionEngine journalOnly =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(journalOnlyPath),
      );
  _expect(
    journalOnly.load().disposition ==
            TerminalNoteStoreDisposition.recoveryRequired &&
        !File(
          '$journalOnlyPath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
        ).existsSync(),
    'journal-only real store is not reset to empty',
  );
  journalOnly.stop();
}

Future<void> _testTwoProcessContention(Directory root) async {
  final String path = '${root.path}/two-process';
  final Process helper = await Process.start(
    Platform.resolvedExecutable,
    _helperArguments('--lock-helper', path),
    workingDirectory: Directory.current.path,
  );
  final List<String> stderrLines = <String>[];
  final Future<void> stderrDone = helper.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(stderrLines.add);
  final StreamIterator<String> output = StreamIterator<String>(
    helper.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    var ready = false;
    while (await output.moveNext().timeout(const Duration(seconds: 15))) {
      if (output.current == _lockReadyLine) {
        ready = true;
        break;
      }
    }
    _expect(ready, 'lock helper reaches ready');
    _expectThrowsStore(
      () => TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(path),
      ),
      TerminalNoteStoreFailure.lockBusy,
      'second process receives kernel lock contention',
    );
    helper.stdin.writeln('stop');
    await helper.stdin.flush();
    await helper.stdin.close();
    final int exitCode = await helper.exitCode.timeout(
      const Duration(seconds: 15),
    );
    _expect(exitCode == 0, 'lock helper exits cleanly');
    var stopped = false;
    while (await output.moveNext()) {
      if (output.current == _lockStoppedLine) stopped = true;
    }
    _expect(stopped, 'lock helper confirms stop');
    await stderrDone;
    _expect(stderrLines.isEmpty, 'lock helper emits no stderr');

    final TerminalNoteStoreTransactionEngine afterExit =
        TerminalNoteStoreTransactionEngine.open(
          location: TerminalNoteStoreLocation.fromAbsolutePath(path),
        );
    _expect(
      afterExit.load().disposition == TerminalNoteStoreDisposition.empty,
      'stale lock pathname does not block a later process',
    );
    afterExit.stop();
  } finally {
    await output.cancel();
    if (await _isProcessRunning(helper)) helper.kill(ProcessSignal.sigkill);
  }
}

Future<void> _testWorkerLogPrivacy(Directory root) async {
  final String path = '${root.path}/worker-log';
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    _helperArguments('--worker-log-helper', path),
    workingDirectory: Directory.current.path,
  ).timeout(const Duration(seconds: 20));
  final String output = '${result.stdout}\n${result.stderr}';
  _expect(
    result.exitCode == 0 && output.contains(_workerLogPassLine),
    'production worker log helper succeeds',
  );
  for (final String sentinel in <String>[
    _bodySentinel,
    _idSentinel,
    _timeSentinel,
    'purple',
    'onReturn',
    path,
  ]) {
    _expect(
      !output.contains(sentinel),
      'worker stdout/stderr contains no private sentinel',
    );
  }
}

Future<int> _measureOneMibWorkerCommit(Directory root) async {
  const TerminalNoteStoreCodec codec = TerminalNoteStoreCodec();
  final String path = '${root.path}/one-mib-performance';
  final TerminalNoteStoreWorkerStartup startup =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(path),
        authorityGeneration: 9001,
      );
  _expect(startup.hasLiveClient, 'performance worker starts');
  final TerminalNoteStoreWorkerClient client = startup.client!;
  final TerminalNoteContextId firstContext = _contextId(99);
  final TerminalNoteContextId secondContext = _contextId(100);
  final Map<TerminalNoteContextId, NoteContextRecord> contexts =
      <TerminalNoteContextId, NoteContextRecord>{
        firstContext: NoteContextRecord(
          id: firstContext,
          kind: TerminalNoteContextKind.standard,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        ),
        secondContext: NoteContextRecord(
          id: secondContext,
          kind: TerminalNoteContextKind.standard,
          state: TerminalNoteContextState.active,
          revision: BigInt.one,
        ),
      };
  final String body = List<String>.filled(4096, 'x', growable: false).join();
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{};
  for (var index = 0; index < 256; index++) {
    final NoteId id = _noteId(1000 + index);
    notes[id] = NoteRecord(
      id: id,
      attachment: TerminalNoteAttachment.attached(
        index < 128 ? firstContext : secondContext,
      ),
      body: NoteBody.fromText(body),
      color: NoteColorKey.yellow,
      status: NoteStatus.active,
      order: index % 128,
      createdAtUtcMicros: index,
      updatedAtUtcMicros: index,
      revision: BigInt.one,
    );
  }
  TerminalNoteStoreDocument candidate(int revision) =>
      TerminalNoteStoreDocument(
        snapshot: TerminalNoteSnapshot.fromRecords(
          storeRevision: BigInt.from(revision),
          nextDeliverySequence: BigInt.one,
          contexts: contexts,
          notes: notes,
          triggers: const <NoteId, NoteTriggerRecord>{},
          deliveries: const <NoteId, NoteDeliveryRecord>{},
        ),
      );
  final TerminalNoteStoreDocument warmup = candidate(1);
  final int encodedBytes = codec.encode(warmup).length;
  _expect(
    encodedBytes >= 1024 * 1024 &&
        encodedBytes < TerminalNoteStoreCodecLimits.maximumFileBytes,
    'performance store is at least 1 MiB and below the hard cap',
  );
  _expect(
    (await client.commitCandidate(warmup)).isSuccess,
    'performance warm-up commits',
  );
  final List<int> samples = <int>[];
  for (var run = 0; run < 20; run++) {
    final TerminalNoteStoreDocument document = candidate(run + 2);
    final Stopwatch stopwatch = Stopwatch()..start();
    final TerminalNoteStoreResult result = await client.commitCandidate(
      document,
    );
    stopwatch.stop();
    _expect(result.isSuccess, 'measured 1 MiB commit succeeds');
    samples.add(stopwatch.elapsedMicroseconds);
  }
  await client.stop();
  return _p95(samples);
}

int _measureSixteenMibPrimitive(Directory root) {
  final String path = '${root.path}/sixteen-mib-performance';
  final MacosDurableDirectorySession session =
      MacosDurableDirectorySession.open(path, create: true);
  final Uint8List payload = Uint8List(
    MacosDurableFileLimits.maximumPayloadBytes,
  );
  try {
    _publishPrimitive(session, payload);
    final List<int> samples = <int>[];
    for (var run = 0; run < 20; run++) {
      final Stopwatch stopwatch = Stopwatch()..start();
      _publishPrimitive(session, payload);
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    _expect(
      session.inspect('primitive.current').length == payload.length,
      '16 MiB primitive publishes exact bytes',
    );
    return _p95(samples);
  } finally {
    session.close();
  }
}

void _publishPrimitive(
  MacosDurableDirectorySession session,
  Uint8List payload,
) {
  session.writeExclusive('primitive.pending', payload);
  session.rename('primitive.pending', 'primitive.current');
  session.flushDirectory();
}

Future<void> _runLockHelper(String path) async {
  final TerminalNoteStoreTransactionEngine engine =
      TerminalNoteStoreTransactionEngine.open(
        location: TerminalNoteStoreLocation.fromAbsolutePath(path),
      );
  final TerminalNoteStoreResult loaded = engine.load();
  if (loaded.disposition != TerminalNoteStoreDisposition.empty) {
    exitCode = 2;
    engine.stop();
    return;
  }
  stdout.writeln(_lockReadyLine);
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  engine.stop();
  stdout.writeln(_lockStoppedLine);
}

Future<void> _runWorkerLogHelper(String path) async {
  final TerminalNoteStoreWorkerStartup startup =
      await TerminalNoteStoreWorkerClient.start(
        location: TerminalNoteStoreLocation.fromAbsolutePath(path),
        authorityGeneration: 1,
      );
  if (!startup.hasLiveClient || !startup.loadResult.isSuccess) {
    exitCode = 3;
    return;
  }
  final TerminalNoteStoreResult committed = await startup.client!
      .commitCandidate(_privacyDocument());
  if (!committed.isSuccess) {
    exitCode = 4;
    await startup.client!.stop();
    return;
  }
  await startup.client!.stop();
  stdout.writeln(_workerLogPassLine);
}

TerminalNoteStoreDocument _privacyDocument() {
  final TerminalNoteContextId contextId = TerminalNoteContextId.fromHex(
    'feedfacefeedfacefeedfacefeedface',
  );
  final NoteId noteId = NoteId.fromHex(_idSentinel);
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: contextId,
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.createNote(
      id: noteId,
      contextId: contextId,
      body: _bodySentinel,
      color: NoteColorKey.purple,
      utcMicros: 777777777777,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.armOnReturn(
      noteId: noteId,
      isEligible: false,
      expectedStoreRevision: snapshot.storeRevision,
      expectedNoteRevision: snapshot.noteFor(noteId)!.revision,
    ),
  );
  return TerminalNoteStoreDocument(snapshot: snapshot);
}

TerminalNoteStoreDocument _twoNoteDocument() {
  final TerminalNoteContextId contextId = _contextId(1);
  TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.empty();
  snapshot = _accept(
    snapshot.createContext(
      id: contextId,
      kind: TerminalNoteContextKind.standard,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.createNote(
      id: _noteId(1),
      contextId: contextId,
      body: 'deleted private body',
      color: NoteColorKey.yellow,
      utcMicros: 10,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  snapshot = _accept(
    snapshot.createNote(
      id: _noteId(2),
      contextId: contextId,
      body: 'remaining private body',
      color: NoteColorKey.blue,
      utcMicros: 20,
      expectedStoreRevision: snapshot.storeRevision,
    ),
  );
  return TerminalNoteStoreDocument(snapshot: snapshot);
}

TerminalNoteStoreDocument _editSecond(TerminalNoteStoreDocument source) {
  final NoteRecord note = source.snapshot.noteFor(_noteId(2))!;
  return TerminalNoteStoreDocument(
    snapshot: _accept(
      source.snapshot.editNote(
        noteId: note.id,
        body: 'edited private body',
        color: NoteColorKey.green,
        updatedAtUtcMicros: 30,
        expectedStoreRevision: source.snapshot.storeRevision,
        expectedNoteRevision: note.revision,
      ),
    ),
  );
}

TerminalNoteStoreDocument _withRevision(
  TerminalNoteStoreDocument source,
  BigInt revision,
) => TerminalNoteStoreDocument(
  snapshot: TerminalNoteSnapshot.fromRecords(
    storeRevision: revision,
    nextDeliverySequence: source.snapshot.nextDeliverySequence,
    contexts: source.snapshot.contexts,
    notes: source.snapshot.notes,
    triggers: source.snapshot.triggers,
    deliveries: source.snapshot.deliveries,
  ),
  restorationBinding: source.restorationBinding,
);

TerminalNoteSnapshot _accept(TerminalNoteMutationResult result) {
  _expect(
    result.disposition == TerminalNoteMutationDisposition.accepted,
    'fixture mutation is accepted',
  );
  return result.snapshot;
}

NoteId _noteId(int value) =>
    NoteId.fromHex(value.toRadixString(16).padLeft(32, '0'));

TerminalNoteContextId _contextId(int value) => TerminalNoteContextId.fromHex(
  (0x100000 + value).toRadixString(16).padLeft(32, '0'),
);

void _replaceLeaf(
  MacosDurableDirectorySession session,
  String target,
  List<int> bytes,
  String pending,
) {
  session.writeExclusive(pending, bytes);
  session.rename(pending, target);
  session.flushDirectory();
}

Future<void> _chmod(String mode, String path) async {
  final ProcessResult result = await Process.run('/bin/chmod', <String>[
    mode,
    path,
  ]);
  _expect(result.exitCode == 0, 'fixture permission change succeeds');
}

int _permissionBits(String path) => FileStat.statSync(path).mode & 0x1ff;

int _p95(List<int> samples) {
  _expect(samples.length >= 20, 'p95 has at least 20 samples');
  final List<int> sorted = List<int>.of(samples)..sort();
  final int index = ((sorted.length * 95 + 99) ~/ 100) - 1;
  return sorted[index];
}

bool _sameDocument(
  TerminalNoteStoreDocument left,
  TerminalNoteStoreDocument right,
) => _bytesEqual(
  const TerminalNoteStoreCodec().encode(left),
  const TerminalNoteStoreCodec().encode(right),
);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<bool> _isProcessRunning(Process process) async {
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 1));
    return false;
  } on TimeoutException {
    return true;
  }
}

List<String> _helperArguments(String mode, String path) {
  final String executable = File(Platform.resolvedExecutable).absolute.path;
  final String script = File.fromUri(Platform.script).absolute.path;
  return executable == script
      ? <String>[mode, path]
      : <String>[
          '${Directory.current.path}/test/terminal_note_store_acceptance_test.dart',
          mode,
          path,
        ];
}

void _expectThrowsStore(
  void Function() callback,
  TerminalNoteStoreFailure failure,
  String description,
) {
  try {
    callback();
  } on TerminalNoteStoreException catch (error) {
    _expect(error.failure == failure, description);
    return;
  }
  throw StateError('expected TerminalNoteStoreException: $description');
}

void _expect(bool value, String description) {
  if (!value) throw StateError(description);
}
