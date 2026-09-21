import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_note_authority.dart';
import 'package:dart_terminal/src/terminal_note_store_process.dart';
import 'package:dart_terminal/src/terminal_note_store_worker.dart';
import 'package:dart_terminal/src/terminal_pane.dart';

Future<void> main() => runTerminalNoteStoreProcessTests();

Future<void> runTerminalNoteStoreProcessTests() async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dart-terminal-note-process-test-',
  );
  final TerminalNoteStoreProcessWorkerService service =
      TerminalNoteStoreProcessWorkerService();
  final _ServicePayloadClient payloadClient = _ServicePayloadClient(service);
  final TerminalNoteProcessStoreFactory factory =
      TerminalNoteProcessStoreFactory(payloadClient);
  final int ownerBaseline = TerminalNoteProcessStoreFactory.debugLivePortCount;
  try {
    final String resolvedRoot = await root.resolveSymbolicLinks();
    final TerminalNoteStoreLocation location =
        TerminalNoteStoreLocation.fromAbsolutePath('$resolvedRoot/store');
    final TerminalNoteAuthorityStoreStartup first = await factory.start(
      location: location,
      authorityGeneration: 11,
    );
    _expect(
      first.store != null &&
          first.loadResult.disposition == TerminalNoteStoreDisposition.empty &&
          first.loadResult.document != null &&
          TerminalNoteProcessStoreFactory.debugLivePortCount ==
              ownerBaseline + 1,
      'process store open mismatch: '
      'store=${first.store != null} '
      'disposition=${first.loadResult.disposition.name} '
      'failure=${first.loadResult.failure?.name ?? 'none'} '
      'document=${first.loadResult.document != null} '
      'owners=${TerminalNoteProcessStoreFactory.debugLivePortCount - ownerBaseline}',
    );

    final TerminalNoteAuthority authority = await TerminalNoteAuthority.start(
      authorityGeneration: 11,
      store: first.store,
      loadResult: first.loadResult,
      restoration: null,
      paneIdsInTraversalOrder: const <PaneId>[
        PaneId(1),
        PaneId(2),
        PaneId(3),
        PaneId(4),
        PaneId(5),
      ],
      ensureQuickTerminalContext: true,
      updatedAtUtcMicros: 10000,
    );
    _expect(
      authority.capability == TerminalNoteAuthorityCapability.ready &&
          authority.livePaneCount == 5 &&
          authority.bindings.quickTerminalContextId != null,
      'process store accepts startup reconciliation: '
      'capability=${authority.capability.name} '
      'failure=${authority.failure?.name ?? 'none'} '
      'storeFailure=${authority.storeFailure?.name ?? 'none'}',
    );

    final TerminalNoteAuthorityStoreStartup competing = await factory.start(
      location: location,
      authorityGeneration: 12,
    );
    _expect(
      competing.store == null &&
          competing.loadResult.failure == TerminalNoteStoreFailure.lockBusy &&
          TerminalNoteProcessStoreFactory.debugLivePortCount ==
              ownerBaseline + 1,
      'process store preserves exclusive lock classification',
    );

    final TerminalNoteStoreResult stopped = await authority.stop();
    _expect(
      stopped.disposition == TerminalNoteStoreDisposition.stopped &&
          TerminalNoteProcessStoreFactory.debugLivePortCount == ownerBaseline,
      'process store stops and releases its owner',
    );
  } finally {
    service.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
  final String? bundledHelper = Platform.environment['DT_TEST_NOTE_HELPER'];
  if (bundledHelper != null) {
    await _testBundledHelper(File(bundledHelper));
  }
}

Future<void> _testBundledHelper(File helper) async {
  final Directory root = await Directory.systemTemp.createTemp(
    'dart-terminal-note-bundled-helper-test-',
  );
  final RuntimeLifecycleCoordinator lifecycle = RuntimeLifecycleCoordinator(
    scenario: RuntimeLifecycleScenario.normal,
    workerCommand: RuntimeLifecycleWorkerCommand(
      executable: helper.path,
      arguments: <String>[
        if (Platform.environment['DT_TEST_NOTE_HELPER_PAYLOAD']
            case final String payload)
          payload,
      ],
      workingDirectory: helper.parent.parent.path,
    ),
    observer: (_) {},
    requestTimeout: const Duration(seconds: 3),
  );
  TerminalNoteAuthority? authority;
  try {
    _expect(
      await lifecycle.start() == RuntimeLifecycleStartStatus.ready,
      'bundled helper did not become ready',
    );
    final TerminalNoteProcessStoreFactory factory =
        TerminalNoteProcessStoreFactory(lifecycle);
    final TerminalNoteAuthorityStoreStartup startup = await factory.start(
      location: TerminalNoteStoreLocation.fromAbsolutePath(
        '${await root.resolveSymbolicLinks()}/store',
      ),
      authorityGeneration: 101,
    );
    authority = await TerminalNoteAuthority.start(
      authorityGeneration: 101,
      store: startup.store,
      loadResult: startup.loadResult,
      restoration: null,
      paneIdsInTraversalOrder: const <PaneId>[
        PaneId(1),
        PaneId(2),
        PaneId(3),
        PaneId(4),
        PaneId(5),
      ],
      ensureQuickTerminalContext: true,
      updatedAtUtcMicros: 10000,
    );
    _expect(
      authority.capability == TerminalNoteAuthorityCapability.ready,
      'bundled helper startup reconciliation mismatch: '
      'capability=${authority.capability.name} '
      'failure=${authority.failure?.name ?? 'none'} '
      'storeFailure=${authority.storeFailure?.name ?? 'none'} '
      'load=${startup.loadResult.disposition.name} '
      'loadDocument=${startup.loadResult.document != null}',
    );
  } finally {
    await authority?.stop();
    await lifecycle.shutdown();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _ServicePayloadClient implements RuntimeWorkerPayloadClient {
  const _ServicePayloadClient(this.service);

  final TerminalNoteStoreProcessWorkerService service;

  @override
  Future<RuntimeLifecyclePayloadRequestResult> requestPayload(
    Uint8List payload, {
    bool expectsInt64Response = false,
  }) async => RuntimeLifecyclePayloadRequestResult(
    RuntimeLifecycleRequestStatus.response,
    payload: service.handle(payload),
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
