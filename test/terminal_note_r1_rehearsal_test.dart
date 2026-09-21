import '../tool/terminal_note_internal_store_admin.dart';
import '../tool/terminal_note_r1_rehearsal.dart';

Future<void> main() => runTerminalNoteR1RehearsalTests();

Future<void> runTerminalNoteR1RehearsalTests() async {
  final TerminalNoteR1RehearsalResult result =
      await runTerminalNoteR1Rehearsal();
  final String machineLine = result.machineLine();
  _expect(
    machineLine ==
            'TERMINAL_NOTE_R1_REHEARSAL_PASS version=1 typed_profile=1 '
                'real_store=1 worker=1 lock=1 kill_switch=1 '
                'native_missing=1 recovery_preview=1 raw_backup=1 export=1 '
                'restore=1 corrupt=1 newer=1 exact_reattach=1 '
                'mismatch_detached=1 wrong_attach=0 '
                'unintended_payload_changes=0 '
                'privacy=1 owners=0 temp_cleanup=1 content_free=true' &&
        !machineLine.contains('/') &&
        !machineLine.contains('PRIVATE'),
    'R1 result is not exact and content-free',
  );

  final TerminalNoteInternalStoreAdminRequest status =
      parseTerminalNoteInternalStoreAdminRequest(const <String>[
        '--store=/private/tmp/dart-terminal-notes',
        '--status',
      ]);
  _expect(
    status.action == TerminalNoteInternalStoreAdminAction.status &&
        status.exportDestination == null &&
        !status.acknowledgeSensitiveExport &&
        !status.acknowledgeDataChange,
    'status request did not remain payload-preserving',
  );
  final TerminalNoteInternalStoreAdminRequest export =
      parseTerminalNoteInternalStoreAdminRequest(const <String>[
        '--store=/private/tmp/dart-terminal-notes',
        '--export=/private/tmp/portable-notes.json',
        '--acknowledge-sensitive-export',
      ]);
  _expect(
    export.action == TerminalNoteInternalStoreAdminAction.exportPortable &&
        export.exportDestination != null &&
        export.acknowledgeSensitiveExport &&
        !export.acknowledgeDataChange,
    'portable export did not require its dedicated acknowledgement',
  );
  final TerminalNoteInternalStoreAdminRequest restore =
      parseTerminalNoteInternalStoreAdminRequest(const <String>[
        '--store=/private/tmp/dart-terminal-notes',
        '--restore-backup',
        '--acknowledge-data-change',
      ]);
  _expect(
    restore.action == TerminalNoteInternalStoreAdminAction.restoreBackup &&
        restore.exportDestination == null &&
        !restore.acknowledgeSensitiveExport &&
        restore.acknowledgeDataChange,
    'backup restore did not require its dedicated acknowledgement',
  );

  _expectThrows(
    () => parseTerminalNoteInternalStoreAdminRequest(const <String>[
      '--store=relative/store',
      '--status',
    ]),
    'relative store path',
  );
  _expectThrows(
    () => parseTerminalNoteInternalStoreAdminRequest(const <String>[
      '--store=/private/tmp/dart-terminal-notes',
      '--export=/private/tmp/portable-notes.json',
    ]),
    'export without acknowledgement',
  );
  _expectThrows(
    () => parseTerminalNoteInternalStoreAdminRequest(const <String>[
      '--store=/private/tmp/dart-terminal-notes',
      '--restore-backup',
    ]),
    'restore without acknowledgement',
  );
  _expectThrows(
    () => parseTerminalNoteInternalStoreAdminRequest(const <String>[
      '--store=/private/tmp/dart-terminal-notes',
      '--status',
      '--restore-backup',
      '--acknowledge-data-change',
    ]),
    'multiple actions',
  );
  _expectThrows(
    () => parseTerminalNoteInternalStoreAdminRequest(const <String>[
      '--store=/private/tmp/dart-terminal-notes',
      '--status',
      '--acknowledge-sensitive-export',
    ]),
    'irrelevant acknowledgement',
  );

  const TerminalNoteInternalStoreAdminResult contentFree =
      TerminalNoteInternalStoreAdminResult(
        action: TerminalNoteInternalStoreAdminAction.restoreBackup,
        sourceState: 'recovery-preview',
        outcome: 'restored',
        mutatedPayload: true,
        isSuccess: true,
      );
  _expect(
    contentFree.machineLine() ==
            'TERMINAL_NOTE_INTERNAL_STORE_ADMIN_PASS '
                'action=restore-backup source_state=recovery-preview '
                'outcome=restored payload_mutation=true content_free=true' &&
        !contentFree.machineLine().contains('/'),
    'internal administration result exposed variable content',
  );
}

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('Expected R1 administration failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('R1 rehearsal test failed: $message');
}
