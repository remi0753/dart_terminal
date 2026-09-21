import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_note_internal_store_admin.dart';
import 'terminal_note_r1_internal_profile.dart';

const String _privateBody = 'R1-PRIVATE-BODY-MUST-NOT-LEAK';
const String _editedPrivateBody = 'R1-EDITED-PRIVATE-BODY-MUST-NOT-LEAK';
const String _privateNoteId = 'd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1';

final class TerminalNoteR1RehearsalResult {
  const TerminalNoteR1RehearsalResult();

  String machineLine() =>
      'TERMINAL_NOTE_R1_REHEARSAL_PASS version=1 typed_profile=1 '
      'real_store=1 worker=1 lock=1 kill_switch=1 native_missing=1 '
      'recovery_preview=1 raw_backup=1 export=1 restore=1 corrupt=1 '
      'newer=1 exact_reattach=1 mismatch_detached=1 wrong_attach=0 '
      'unintended_payload_changes=0 privacy=1 owners=0 temp_cleanup=1 '
      'content_free=true';
}

Future<TerminalNoteR1RehearsalResult> runTerminalNoteR1Rehearsal() async {
  final int compositionBaseline =
      TerminalNoteCompositionRoot.debugLiveSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int workerBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r1-rehearsal-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  TerminalNoteStoreWorkerClient? liveClient;
  TerminalNoteR1RehearsalResult? completed;
  try {
    final TerminalConfigResolution resolution = TerminalConfigLoader().resolve(
      <String>['--no-config', ...terminalNoteR1InternalArguments],
      environment: const <String, String>{},
      currentDirectory: root.path,
    );
    final TerminalProductConfiguration product =
        TerminalProductConfiguration.fromSnapshot(resolution.snapshot);
    final TerminalNoteFeatureConfiguration enabled =
        TerminalNoteFeatureConfiguration.fromProduct(product);
    _expect(
      resolution.remainingArguments.isEmpty &&
          resolution.snapshot.diagnostics.isEmpty &&
          enabled.surfaceEnabled &&
          enabled.onReturnEnabled &&
          !enabled.nextPromptEnabled,
      'typed internal profile did not admit only S1 and S2',
    );

    final TerminalNoteRestorationArtifact exactRestoration = _restoration(
      left: 100,
    );
    var nextContextIdentity = 1;
    final TerminalNoteContextReconciler reconciler =
        TerminalNoteContextReconciler(
          TerminalNoteContextIdGenerator.forTesting(() {
            final List<int> bytes = List<int>.filled(16, 0);
            bytes[14] = nextContextIdentity >> 8;
            bytes[15] = nextContextIdentity & 0xff;
            nextContextIdentity++;
            return bytes;
          }),
        );
    final TerminalNoteContextReconciliationResult initial = reconciler
        .reconcile(
          stored: TerminalNoteStoreDocument(
            snapshot: TerminalNoteSnapshot.empty(),
          ),
          restoration: exactRestoration,
          paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 1,
        );
    final TerminalNoteContextId originalContext = initial.bindings
        .contextForPane(const PaneId(1))!;
    final NoteId noteId = NoteId.fromHex(_privateNoteId);
    final TerminalNoteMutationResult created = initial.document.snapshot
        .createNote(
          id: noteId,
          contextId: originalContext,
          body: _privateBody,
          color: NoteColorKey.yellow,
          utcMicros: 2,
          expectedStoreRevision: initial.document.snapshot.storeRevision,
        );
    _expect(
      created.disposition == TerminalNoteMutationDisposition.accepted,
      'initial R1 Note mutation was rejected',
    );
    final TerminalNoteStoreDocument firstDocument = TerminalNoteStoreDocument(
      snapshot: created.snapshot,
      restorationBinding: initial.document.restorationBinding,
    );
    final NoteRecord firstNote = created.snapshot.noteFor(noteId)!;
    final TerminalNoteMutationResult edited = created.snapshot.editNote(
      noteId: noteId,
      body: _editedPrivateBody,
      color: NoteColorKey.blue,
      updatedAtUtcMicros: 3,
      expectedStoreRevision: created.snapshot.storeRevision,
      expectedNoteRevision: firstNote.revision,
    );
    _expect(
      edited.disposition == TerminalNoteMutationDisposition.accepted,
      'edited R1 Note mutation was rejected',
    );
    final TerminalNoteStoreDocument latestDocument = TerminalNoteStoreDocument(
      snapshot: edited.snapshot,
      restorationBinding: initial.document.restorationBinding,
    );

    final TerminalNoteStoreLocation location =
        TerminalNoteStoreLocation.fromEnvironment(<String, String>{
          'XDG_STATE_HOME': root.path,
          'HOME': root.path,
        });
    final Directory storeDirectory = Directory(location.canonicalPath);
    final TerminalNoteStoreWorkerStartup startup =
        await TerminalNoteStoreWorkerClient.start(
          location: location,
          authorityGeneration: 101,
        );
    liveClient = startup.client;
    _expect(
      startup.hasLiveClient &&
          startup.loadResult.disposition == TerminalNoteStoreDisposition.empty,
      'real R1 store worker did not start empty',
    );
    final TerminalNoteStoreWorkerClient primaryClient = startup.client!;
    _expect(
      (await primaryClient.commitCandidate(firstDocument)).isSuccess &&
          (await primaryClient.commitCandidate(latestDocument)).isSuccess,
      'real R1 store worker did not durably commit both revisions',
    );
    final Map<String, List<int>> beforeLock = _captureStorePayloads(
      storeDirectory,
    );
    _expect(
      beforeLock.keys.contains(
            TerminalNoteStoreTransactionEngine.currentLeaf,
          ) &&
          beforeLock.keys.contains(
            TerminalNoteStoreTransactionEngine.backupLeaf,
          ),
      'real R1 store did not retain current and backup copies',
    );
    final TerminalNoteInternalStoreAdminResult locked =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.status,
            location: location,
          ),
        );
    _expect(
      !locked.isSuccess &&
          locked.sourceState == 'locked' &&
          !locked.mutatedPayload &&
          _sameFiles(beforeLock, _captureStorePayloads(storeDirectory)),
      'live worker lock did not reject offline administration without mutation',
    );
    final TerminalNoteStoreResult primaryStopped = await primaryClient.stop();
    _expect(
      primaryStopped.disposition == TerminalNoteStoreDisposition.stopped,
      'primary R1 store worker did not stop cleanly',
    );
    liveClient = null;
    final Map<String, List<int>> stableStore = _captureStorePayloads(
      storeDirectory,
    );

    final TerminalProductConfiguration disabledProduct =
        TerminalProductConfiguration.fromSnapshot(
          TerminalConfigLoader()
              .resolve(
                const <String>[
                  '--no-config',
                  '--notes=false',
                  '--notes-on-return=true',
                  '--notes-next-prompt=false',
                ],
                environment: const <String, String>{},
                currentDirectory: root.path,
              )
              .snapshot,
        );
    var disabledFactoryCalls = 0;
    final TerminalNoteCompositionRoot disabled =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: TerminalNoteFeatureConfiguration.fromProduct(
            disabledProduct,
          ),
          factory: (_) {
            disabledFactoryCalls++;
            throw StateError('kill switch evaluated its disabled factory');
          },
        );
    _expect(
      disabled.capability == TerminalNoteApplicationCapability.disabled &&
          !disabled.ownsRuntime &&
          disabledFactoryCalls == 0 &&
          _sameFiles(stableStore, _captureStorePayloads(storeDirectory)),
      'on-to-off restart touched the R1 store or admitted a resource',
    );
    await disabled.shutdown();

    var nativeMissingLocationCalls = 0;
    final TerminalNoteSubsystemStartResult nativeMissing =
        await TerminalNoteProductSubsystem.start(
          configuration: enabled,
          environment: <String, String>{
            'XDG_STATE_HOME': root.path,
            'HOME': root.path,
          },
          authorityGeneration: 102,
          restoration: exactRestoration,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 4,
          copyEffect: (_) => false,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {
            throw StateError('simulated missing native Notes capability');
          },
          locationResolver: (_) {
            nativeMissingLocationCalls++;
            return location;
          },
        );
    _expect(
      nativeMissing.capability ==
              TerminalNoteApplicationCapability.unavailable &&
          nativeMissing.runtime == null &&
          nativeMissingLocationCalls == 0 &&
          _sameFiles(stableStore, _captureStorePayloads(storeDirectory)),
      'native-missing launch crossed the store admission boundary',
    );

    final TerminalNoteRestorationArtifact preNotesRoundTrip =
        TerminalNoteRestorationArtifact.fromExactEncoded(
          exactRestoration.exactEncoded,
        );
    final TerminalNoteContextReconciliationResult exactReupgrade = reconciler
        .reconcile(
          stored: latestDocument,
          restoration: preNotesRoundTrip,
          paneIdsInTraversalOrder: const <PaneId>[PaneId(101)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 5,
        );
    final NoteRecord exactNote = exactReupgrade.document.snapshot.noteFor(
      noteId,
    )!;
    _expect(
      exactReupgrade.disposition ==
              TerminalNoteContextReconciliationDisposition.matched &&
          exactReupgrade.bindings.contextForPane(const PaneId(101)) ==
              originalContext &&
          exactNote.attachment.contextId == originalContext &&
          !exactReupgrade.requiresCommit,
      'exact pre-Notes rollback did not reattach to its original context',
    );
    final TerminalNoteContextReconciliationResult mismatchReupgrade = reconciler
        .reconcile(
          stored: latestDocument,
          restoration: _restoration(left: 140),
          paneIdsInTraversalOrder: const <PaneId>[PaneId(201)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 6,
        );
    final TerminalNoteContextId mismatchContext = mismatchReupgrade.bindings
        .contextForPane(const PaneId(201))!;
    final NoteRecord mismatchNote = mismatchReupgrade.document.snapshot.noteFor(
      noteId,
    )!;
    _expect(
      mismatchReupgrade.disposition ==
              TerminalNoteContextReconciliationDisposition.fresh &&
          mismatchReupgrade.freshReason ==
              TerminalNoteContextFreshReason.hashMismatch &&
          mismatchContext != originalContext &&
          mismatchNote.attachment.isDetached &&
          mismatchReupgrade.document.snapshot
              .projectionFor(mismatchContext)
              .orderedNotes
              .isEmpty &&
          _sameFiles(stableStore, _captureStorePayloads(storeDirectory)),
      'layout-changing rollback attached a Note or changed the store',
    );

    final Directory recoveryDirectory = Directory('${root.path}/recovery');
    _writePayloadFixture(recoveryDirectory, stableStore);
    File(
      '${recoveryDirectory.path}/${TerminalNoteStoreTransactionEngine.currentLeaf}',
    ).writeAsBytesSync(<int>[1], flush: true);
    final TerminalNoteStoreLocation recoveryLocation =
        TerminalNoteStoreLocation.fromAbsolutePath(recoveryDirectory.path);
    final Map<String, List<int>> beforeRecovery = _captureStorePayloads(
      recoveryDirectory,
    );
    final TerminalNoteInternalStoreAdminResult recoveryStatus =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.status,
            location: recoveryLocation,
          ),
        );
    _expect(
      recoveryStatus.isSuccess &&
          recoveryStatus.sourceState == 'recovery-preview' &&
          !recoveryStatus.mutatedPayload &&
          _sameFiles(beforeRecovery, _captureStorePayloads(recoveryDirectory)),
      'current-only corruption was not a payload-preserving recovery preview',
    );

    final Directory exportDirectory = Directory('${root.path}/export')
      ..createSync();
    final File portableExport = File('${exportDirectory.path}/notes.json');
    final TerminalNoteInternalStoreAdminResult exported =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.exportPortable,
            location: recoveryLocation,
            exportDestination: TerminalNoteApprovedExportPath.fromAbsolutePath(
              portableExport.path,
            ),
            acknowledgeSensitiveExport: true,
          ),
        );
    final Map<String, dynamic> portable = jsonDecode(
      portableExport.readAsStringSync().trim(),
    ) as Map<String, dynamic>;
    final List<dynamic> portableNotes = portable['notes'] as List<dynamic>;
    final Map<String, dynamic> portableNote =
        portableNotes.single as Map<String, dynamic>;
    _expect(
      exported.isSuccess &&
          exported.sourceState == 'recovery-preview' &&
          exported.outcome == 'exported' &&
          !exported.mutatedPayload &&
          portable.keys.join(',') == 'format,version,notes' &&
          portable['format'] == TerminalNotePortableExportCodec.format &&
          portable['version'] == TerminalNotePortableExportCodec.version &&
          portableNote.keys.join(',') == 'body,color,status,order,trigger' &&
          portableNote['body'] == _privateBody &&
          !portableExport.readAsStringSync().contains(_privateNoteId) &&
          _sameFiles(beforeRecovery, _captureStorePayloads(recoveryDirectory)),
      'explicit recovery export was not portable or payload-preserving',
    );

    final Directory rawBackupDirectory = Directory('${root.path}/raw-backup');
    _writePayloadFixture(rawBackupDirectory, beforeRecovery);
    _expect(
      _sameFiles(beforeRecovery, _captureStorePayloads(rawBackupDirectory)),
      'raw recovery backup did not preserve exact bytes',
    );
    final TerminalNoteInternalStoreAdminResult restored =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.restoreBackup,
            location: recoveryLocation,
            acknowledgeDataChange: true,
          ),
        );
    _expect(
      restored.isSuccess &&
          restored.sourceState == 'recovery-preview' &&
          restored.outcome == 'restored' &&
          restored.mutatedPayload,
      'acknowledged backup restore did not complete',
    );
    final TerminalNoteStoreWorkerStartup recoveredStartup =
        await TerminalNoteStoreWorkerClient.start(
          location: recoveryLocation,
          authorityGeneration: 103,
        );
    liveClient = recoveredStartup.client;
    final TerminalNoteStoreWorkerClient recoveredClient =
        recoveredStartup.client!;
    final NoteRecord? recoveredNote = recoveredStartup
        .loadResult
        .document
        ?.snapshot
        .noteFor(noteId);
    _expect(
      recoveredStartup.hasLiveClient &&
          recoveredStartup.loadResult.disposition ==
              TerminalNoteStoreDisposition.loaded &&
          recoveredNote?.body.value == _privateBody,
      'restored backup was not readable by the real worker',
    );
    final TerminalNoteStoreResult recoveredStopped = await recoveredClient
        .stop();
    _expect(
      recoveredStopped.disposition == TerminalNoteStoreDisposition.stopped,
      'recovered R1 store worker did not stop cleanly',
    );
    liveClient = null;

    final Directory corruptDirectory = Directory('${root.path}/corrupt-both')
      ..createSync();
    File(
      '${corruptDirectory.path}/${TerminalNoteStoreTransactionEngine.currentLeaf}',
    ).writeAsBytesSync(<int>[1], flush: true);
    File(
      '${corruptDirectory.path}/${TerminalNoteStoreTransactionEngine.backupLeaf}',
    ).writeAsBytesSync(<int>[2], flush: true);
    final Map<String, List<int>> corruptBefore = _captureStorePayloads(
      corruptDirectory,
    );
    final TerminalNoteInternalStoreAdminResult corruptStatus =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.status,
            location: TerminalNoteStoreLocation.fromAbsolutePath(
              corruptDirectory.path,
            ),
          ),
        );
    _expect(
      corruptStatus.isSuccess &&
          corruptStatus.sourceState == 'recovery-required' &&
          !corruptStatus.mutatedPayload &&
          _sameFiles(corruptBefore, _captureStorePayloads(corruptDirectory)),
      'corrupt-both store was reset or changed',
    );

    final Directory newerDirectory = Directory('${root.path}/newer')
      ..createSync();
    final List<int> currentBytes =
        stableStore[TerminalNoteStoreTransactionEngine.currentLeaf]!;
    final String currentText = utf8.decode(currentBytes);
    final String newerText = currentText.replaceFirst(
      '"version":1',
      '"version":2',
    );
    _expect(newerText != currentText, 'newer-version fixture was not created');
    File(
      '${newerDirectory.path}/${TerminalNoteStoreTransactionEngine.currentLeaf}',
    ).writeAsBytesSync(utf8.encode(newerText), flush: true);
    File(
      '${newerDirectory.path}/${TerminalNoteStoreTransactionEngine.backupLeaf}',
    ).writeAsBytesSync(
      stableStore[TerminalNoteStoreTransactionEngine.backupLeaf]!,
      flush: true,
    );
    final Map<String, List<int>> newerBefore = _captureStorePayloads(
      newerDirectory,
    );
    final TerminalNoteInternalStoreAdminResult newerStatus =
        runTerminalNoteInternalStoreAdmin(
          TerminalNoteInternalStoreAdminRequest(
            action: TerminalNoteInternalStoreAdminAction.status,
            location: TerminalNoteStoreLocation.fromAbsolutePath(
              newerDirectory.path,
            ),
          ),
        );
    _expect(
      newerStatus.isSuccess &&
          newerStatus.sourceState == 'upgrade-required' &&
          !newerStatus.mutatedPayload &&
          _sameFiles(newerBefore, _captureStorePayloads(newerDirectory)),
      'newer store fell back, downgraded, or changed',
    );

    final int ownerLeakCount =
        (TerminalNoteCompositionRoot.debugLiveSubsystemCount -
                compositionBaseline)
            .abs() +
        (TerminalNoteAuthority.debugLiveAuthorityCount - authorityBaseline)
            .abs() +
        (TerminalNoteStoreWorkerClient.debugLiveClientCount - workerBaseline)
            .abs() +
        (TerminalNoteProductSubsystem.debugLiveProductSubsystemCount -
                productBaseline)
            .abs();
    _expect(ownerLeakCount == 0, 'R1 rehearsal leaked a runtime owner');
    completed = const TerminalNoteR1RehearsalResult();
    final String machineLine = completed.machineLine();
    _expect(
      !machineLine.contains(root.path) &&
          !machineLine.contains(_privateBody) &&
          !machineLine.contains(_editedPrivateBody) &&
          !machineLine.contains(_privateNoteId),
      'R1 rehearsal result contains private evidence',
    );
  } finally {
    try {
      await liveClient?.stop();
    } on Object {
      // Preserve the primary fixed rehearsal failure.
    }
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
  return completed;
}

TerminalNoteRestorationArtifact _restoration({required double left}) =>
    TerminalNoteRestorationArtifact.fromSnapshot(
      TerminalRestorationSnapshot(
        windows: <TerminalRestorableWindow>[
          TerminalRestorableWindow(
            placement: TerminalWindowPlacement(
              windowedFrame: TerminalWindowFrame(
                left: left,
                top: 100,
                width: 900,
                height: 600,
              ),
              screen: null,
              fullscreen: false,
            ),
            tabs: <TerminalRestorableTab>[
              TerminalRestorableTab(
                splitTree: TerminalRestorableSplitLeaf(
                  TerminalRestorablePane(workingDirectory: null),
                ),
                focusedPaneIndex: 0,
                zoomedPaneIndex: null,
                customTitle: null,
                color: null,
              ),
            ],
            selectedTabIndex: 0,
          ),
        ],
        activeWindowIndex: 0,
      ),
    );

Map<String, List<int>> _captureStorePayloads(Directory directory) {
  const Set<String> payloadLeaves = <String>{
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
    TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
  };
  final Map<String, List<int>> result = <String, List<int>>{};
  if (!directory.existsSync()) return result;
  for (final FileSystemEntity entity in directory.listSync(
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String leaf = entity.uri.pathSegments.last;
    if (payloadLeaves.contains(leaf)) result[leaf] = entity.readAsBytesSync();
  }
  return result;
}

void _writePayloadFixture(
  Directory directory,
  Map<String, List<int>> payloads,
) {
  directory.createSync(recursive: true);
  for (final MapEntry<String, List<int>> entry in payloads.entries) {
    File('${directory.path}/${entry.key}')
        .writeAsBytesSync(entry.value, flush: true);
  }
}

bool _sameFiles(Map<String, List<int>> left, Map<String, List<int>> right) {
  if (left.length != right.length ||
      !left.keys.toSet().containsAll(right.keys)) {
    return false;
  }
  for (final String key in left.keys) {
    final List<int> first = left[key]!;
    final List<int>? second = right[key];
    if (second == null || first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('R1 rehearsal failed: $message');
}

Future<void> main() async {
  try {
    final TerminalNoteR1RehearsalResult result =
        await runTerminalNoteR1Rehearsal();
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R1_REHEARSAL_FAIL version=1 reason=rejected '
      'content_free=true',
    );
    exitCode = 1;
  }
}
