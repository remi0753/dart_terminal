import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

const String _privateBody = 'R0-PRIVATE-BODY-MUST-NOT-LEAK';
const String _privateNoteId = 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0';

Future<void> main() => runTerminalNoteR0HiddenQualificationTests();

Future<void> runTerminalNoteR0HiddenQualificationTests() async {
  final int compositionBaseline =
      TerminalNoteCompositionRoot.debugLiveSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int workerBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r0-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  try {
    final TerminalProductConfiguration defaults =
        TerminalProductConfiguration.fromSnapshot(
          TerminalConfigLoader().resolve(const <String>[
            '--no-config',
          ], environment: const <String, String>{}).snapshot,
        );
    final TerminalActionCatalog normalCatalog =
        TerminalActionCatalog.standard();
    final Set<TerminalActionId> noteActions = <TerminalActionId>{
      TerminalActionId.newNote,
      TerminalActionId.toggleNotes,
      TerminalActionId.focusTerminalFromNotes,
    };
    final String publicReference = <String>[
      TerminalConfigurationReference().generateUsage(),
      TerminalConfigurationReference().generateMarkdown(),
    ].join('\n');
    final Set<String> publicOptionNames = TerminalProductConfigSchema
        .instance
        .publicOptions
        .map((TerminalConfigOptionBase option) => option.name)
        .toSet();
    final bool hiddenDefault =
        !defaults.notes &&
        defaults.notesOnReturn &&
        !defaults.notesNextPrompt &&
        defaults.notesFontSize == 15 &&
        noteActions.every(
          (TerminalActionId id) => normalCatalog.actionForId(id) == null,
        ) &&
        !publicOptionNames.contains('notes') &&
        !publicOptionNames.contains('notes-on-return') &&
        !publicOptionNames.contains('notes-next-prompt') &&
        !publicOptionNames.contains('notes-font-size') &&
        !publicReference.contains('--notes');
    _expect(hiddenDefault, 'normal release exposes an R0 Note entry');

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
    final TerminalNoteMutationResult created = initial.document.snapshot
        .createNote(
          id: NoteId.fromHex(_privateNoteId),
          contextId: originalContext,
          body: _privateBody,
          color: NoteColorKey.purple,
          utcMicros: 2,
          expectedStoreRevision: initial.document.snapshot.storeRevision,
        );
    _expect(
      created.disposition == TerminalNoteMutationDisposition.accepted,
      'R0 temporary fixture Note was rejected',
    );
    final TerminalNoteStoreDocument stored = TerminalNoteStoreDocument(
      snapshot: created.snapshot,
      restorationBinding: initial.document.restorationBinding,
    );

    final String storePath = '${root.path}/temporary-store';
    final TerminalNoteStoreWorkerStartup startup =
        await TerminalNoteStoreWorkerClient.start(
          location: TerminalNoteStoreLocation.fromAbsolutePath(storePath),
          authorityGeneration: 1,
        );
    _expect(
      startup.hasLiveClient && startup.loadResult.isSuccess,
      'R0 temporary Note worker did not start',
    );
    final TerminalNoteStoreResult committed = await startup.client!
        .commitCandidate(stored);
    _expect(committed.isSuccess, 'R0 temporary Note store did not commit');
    await startup.client!.stop();
    final Map<String, List<int>> storeBefore = _captureFiles(
      Directory(storePath),
    );
    _expect(storeBefore.isNotEmpty, 'R0 temporary store has no durable files');

    final String corruptStorePath = '${root.path}/corrupt-store';
    Directory(corruptStorePath).createSync(recursive: true);
    File('$corruptStorePath/${TerminalNoteStoreTransactionEngine.currentLeaf}')
        .writeAsBytesSync(<int>[1], flush: true);
    File('$corruptStorePath/${TerminalNoteStoreTransactionEngine.backupLeaf}')
        .writeAsBytesSync(<int>[2], flush: true);
    final Map<String, List<int>> corruptBefore = _captureStorePayloads(
      Directory(corruptStorePath),
    );
    final TerminalNoteStoreWorkerStartup corruptStartup =
        await TerminalNoteStoreWorkerClient.start(
          location: TerminalNoteStoreLocation.fromAbsolutePath(
            corruptStorePath,
          ),
          authorityGeneration: 2,
        );
    _expect(
      corruptStartup.hasLiveClient &&
          corruptStartup.loadResult.disposition ==
              TerminalNoteStoreDisposition.recoveryRequired &&
          corruptStartup.loadResult.failure ==
              TerminalNoteStoreFailure.recoveryRequired &&
          corruptStartup.loadResult.document == null,
      'R0 corrupt store was reset or admitted',
    );
    await corruptStartup.client!.stop();
    _expect(
      _sameFiles(
        corruptBefore,
        _captureStorePayloads(Directory(corruptStorePath)),
      ),
      'R0 corrupt store changed without explicit recovery',
    );

    final String incompatibleStorePath = '${root.path}/incompatible-store';
    Directory(incompatibleStorePath).createSync(recursive: true);
    final List<int> currentBytes =
        storeBefore[TerminalNoteStoreTransactionEngine.currentLeaf]!;
    final String currentText = utf8.decode(currentBytes);
    final String newerText = currentText.replaceFirst(
      '"version":1',
      '"version":2',
    );
    _expect(newerText != currentText, 'R0 newer-version fixture was not made');
    File(
      '$incompatibleStorePath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
    ).writeAsBytesSync(utf8.encode(newerText), flush: true);
    File(
      '$incompatibleStorePath/${TerminalNoteStoreTransactionEngine.backupLeaf}',
    ).writeAsBytesSync(currentBytes, flush: true);
    final Map<String, List<int>> incompatibleBefore = _captureStorePayloads(
      Directory(incompatibleStorePath),
    );
    final TerminalNoteStoreWorkerStartup incompatibleStartup =
        await TerminalNoteStoreWorkerClient.start(
          location: TerminalNoteStoreLocation.fromAbsolutePath(
            incompatibleStorePath,
          ),
          authorityGeneration: 3,
        );
    _expect(
      incompatibleStartup.hasLiveClient &&
          incompatibleStartup.loadResult.disposition ==
              TerminalNoteStoreDisposition.upgradeRequired &&
          incompatibleStartup.loadResult.failure ==
              TerminalNoteStoreFailure.upgradeRequired &&
          incompatibleStartup.loadResult.document == null,
      'R0 newer store fell back to an older copy',
    );
    await incompatibleStartup.client!.stop();
    _expect(
      _sameFiles(
        incompatibleBefore,
        _captureStorePayloads(Directory(incompatibleStorePath)),
      ),
      'R0 newer store changed without a compatible upgrade',
    );

    var disabledFactoryCalls = 0;
    final String untouchedProbePath = '${root.path}/disabled-must-not-exist';
    final TerminalNoteCompositionRoot disabled =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: TerminalNoteFeatureConfiguration.fromProduct(
            defaults,
          ),
          factory: (_) {
            disabledFactoryCalls++;
            Directory(untouchedProbePath).createSync(recursive: true);
            throw StateError('disabled R0 composition evaluated its factory');
          },
        );
    _expect(
      disabled.capability == TerminalNoteApplicationCapability.disabled &&
          !disabled.ownsRuntime &&
          disabledFactoryCalls == 0 &&
          !Directory(untouchedProbePath).existsSync(),
      'R0 disabled path admitted a Note resource',
    );
    await disabled.shutdown();

    var unavailableFactoryCalls = 0;
    final TerminalNoteCompositionRoot nativeUnavailable =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: const TerminalNoteFeatureConfiguration(
            notes: true,
            notesOnReturn: true,
            notesNextPrompt: false,
            fontSize: 15,
          ),
          factory: (_) async {
            unavailableFactoryCalls++;
            return TerminalNoteSubsystemStartResult.failure(
              TerminalNoteApplicationCapability.unavailable,
            );
          },
        );
    _expect(
      nativeUnavailable.capability ==
              TerminalNoteApplicationCapability.unavailable &&
          !nativeUnavailable.ownsRuntime &&
          unavailableFactoryCalls == 1,
      'R0 native-missing path did not fail closed',
    );
    await nativeUnavailable.shutdown();

    final Map<String, List<int>> storeAfterSoftRollback = _captureFiles(
      Directory(storePath),
    );
    _expect(
      _sameFiles(storeBefore, storeAfterSoftRollback),
      'soft rollback or native failure changed the Note store',
    );

    // A pre-Notes binary reads and republishes only restoration v1. It has no
    // Note store authority, so this exact-byte round-trip deliberately does
    // not open [storePath].
    final TerminalNoteRestorationArtifact preNotesRoundTrip =
        TerminalNoteRestorationArtifact.fromExactEncoded(
          exactRestoration.exactEncoded,
        );
    final TerminalNoteContextReconciliationResult exactReupgrade = reconciler
        .reconcile(
          stored: stored,
          restoration: preNotesRoundTrip,
          paneIdsInTraversalOrder: const <PaneId>[PaneId(101)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 3,
        );
    final NoteRecord exactNote = exactReupgrade.document.snapshot.noteFor(
      NoteId.fromHex(_privateNoteId),
    )!;
    final bool exactReattached =
        exactReupgrade.disposition ==
            TerminalNoteContextReconciliationDisposition.matched &&
        exactReupgrade.bindings.contextForPane(const PaneId(101)) ==
            originalContext &&
        exactNote.attachment.contextId == originalContext &&
        !exactReupgrade.requiresCommit;
    _expect(exactReattached, 'exact pre-Notes rollback did not reattach');

    final TerminalNoteContextReconciliationResult mismatchReupgrade = reconciler
        .reconcile(
          stored: stored,
          restoration: _restoration(left: 140),
          paneIdsInTraversalOrder: const <PaneId>[PaneId(201)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 4,
        );
    final TerminalNoteContextId mismatchContext = mismatchReupgrade.bindings
        .contextForPane(const PaneId(201))!;
    final NoteRecord mismatchNote = mismatchReupgrade.document.snapshot.noteFor(
      NoteId.fromHex(_privateNoteId),
    )!;
    final bool mismatchDetached =
        mismatchReupgrade.disposition ==
            TerminalNoteContextReconciliationDisposition.fresh &&
        mismatchReupgrade.freshReason ==
            TerminalNoteContextFreshReason.hashMismatch &&
        mismatchContext != originalContext &&
        mismatchNote.attachment.isDetached &&
        mismatchReupgrade.document.snapshot
            .projectionFor(mismatchContext)
            .orderedNotes
            .isEmpty;
    _expect(
      mismatchDetached,
      'layout-changing rollback attached a Note to the wrong pane',
    );
    _expect(
      _sameFiles(storeBefore, _captureFiles(Directory(storePath))),
      'pure re-upgrade rehearsal changed durable store bytes',
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
    final String machineLine =
        'TERMINAL_NOTE_R0_HARNESS_PASS temporary_store=1 default_off=1 '
        'user_entries=0 disabled_resources=0 soft_rollback=1 '
        'corrupt=1 incompatible=1 native_missing=1 exact_reattach=1 '
        'mismatch_detached=1 '
        'wrong_attach=0 store_changes=0 privacy=1 owners=$ownerLeakCount';
    _expect(
      ownerLeakCount == 0 &&
          !machineLine.contains(root.path) &&
          !machineLine.contains(_privateBody) &&
          !machineLine.contains(_privateNoteId),
      'R0 harness leaked an owner or private evidence',
    );
    stdout.writeln(machineLine);
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
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

Map<String, List<int>> _captureFiles(Directory directory) {
  final Map<String, List<int>> result = <String, List<int>>{};
  final List<FileSystemEntity> entities =
      directory.listSync(recursive: true, followLinks: false)
        ..sort((FileSystemEntity left, FileSystemEntity right) {
          return left.path.compareTo(right.path);
        });
  for (final FileSystemEntity entity in entities) {
    if (entity is! File) continue;
    final String relative = entity.path.substring(directory.path.length + 1);
    result[relative] = entity.readAsBytesSync();
  }
  return result;
}

Map<String, List<int>> _captureStorePayloads(Directory directory) {
  const Set<String> payloadLeaves = <String>{
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
    TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
  };
  final Map<String, List<int>> files = _captureFiles(directory);
  files.removeWhere(
    (String name, List<int> _) => !payloadLeaves.contains(name),
  );
  return files;
}

bool _sameFiles(Map<String, List<int>> left, Map<String, List<int>> right) {
  if (left.length != right.length ||
      !left.keys.toSet().containsAll(right.keys)) {
    return false;
  }
  for (final String name in left.keys) {
    final List<int> leftBytes = left[name]!;
    final List<int> rightBytes = right[name]!;
    if (leftBytes.length != rightBytes.length) return false;
    for (var index = 0; index < leftBytes.length; index++) {
      if (leftBytes[index] != rightBytes[index]) return false;
    }
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
