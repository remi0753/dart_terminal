import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

enum TerminalNoteInternalStoreAdminAction {
  status('status'),
  exportPortable('export-portable'),
  restoreBackup('restore-backup');

  const TerminalNoteInternalStoreAdminAction(this.machineName);

  final String machineName;
}

final class TerminalNoteInternalStoreAdminRequest {
  TerminalNoteInternalStoreAdminRequest({
    required this.action,
    required this.location,
    this.exportDestination,
    this.acknowledgeSensitiveExport = false,
    this.acknowledgeDataChange = false,
  }) {
    final bool valid = switch (action) {
      TerminalNoteInternalStoreAdminAction.status =>
        exportDestination == null &&
            !acknowledgeSensitiveExport &&
            !acknowledgeDataChange,
      TerminalNoteInternalStoreAdminAction.exportPortable =>
        exportDestination != null &&
            acknowledgeSensitiveExport &&
            !acknowledgeDataChange,
      TerminalNoteInternalStoreAdminAction.restoreBackup =>
        exportDestination == null &&
            !acknowledgeSensitiveExport &&
            acknowledgeDataChange,
    };
    if (!valid) {
      throw const FormatException('internal store acknowledgement differs');
    }
  }

  final TerminalNoteInternalStoreAdminAction action;
  final TerminalNoteStoreLocation location;
  final TerminalNoteApprovedExportPath? exportDestination;
  final bool acknowledgeSensitiveExport;
  final bool acknowledgeDataChange;
}

final class TerminalNoteInternalStoreAdminResult {
  const TerminalNoteInternalStoreAdminResult({
    required this.action,
    required this.sourceState,
    required this.outcome,
    required this.mutatedPayload,
    required this.isSuccess,
  });

  final TerminalNoteInternalStoreAdminAction action;
  final String sourceState;
  final String outcome;
  final bool mutatedPayload;
  final bool isSuccess;

  String machineLine() =>
      'TERMINAL_NOTE_INTERNAL_STORE_ADMIN_${isSuccess ? 'PASS' : 'FAIL'} '
      'action=${action.machineName} source_state=$sourceState '
      'outcome=$outcome payload_mutation=${mutatedPayload ? 'true' : 'false'} '
      'content_free=true';
}

TerminalNoteInternalStoreAdminResult runTerminalNoteInternalStoreAdmin(
  TerminalNoteInternalStoreAdminRequest request,
) {
  TerminalNoteStoreTransactionEngine? engine;
  try {
    engine = TerminalNoteStoreTransactionEngine.open(
      location: request.location,
    );
    final TerminalNoteStoreResult loaded = engine.load();
    final String sourceState = _sourceState(loaded);
    return switch (request.action) {
      TerminalNoteInternalStoreAdminAction.status =>
        TerminalNoteInternalStoreAdminResult(
          action: request.action,
          sourceState: sourceState,
          outcome: 'inspected',
          mutatedPayload: false,
          isSuccess: _isInspectable(loaded),
        ),
      TerminalNoteInternalStoreAdminAction.exportPortable => _exportPortable(
        request: request,
        engine: engine,
        loaded: loaded,
        sourceState: sourceState,
      ),
      TerminalNoteInternalStoreAdminAction.restoreBackup => _restoreBackup(
        request: request,
        engine: engine,
        loaded: loaded,
        sourceState: sourceState,
      ),
    };
  } on TerminalNoteStoreException catch (error) {
    return TerminalNoteInternalStoreAdminResult(
      action: request.action,
      sourceState: _failureState(error.failure),
      outcome: 'rejected',
      mutatedPayload: false,
      isSuccess: false,
    );
  } on Object {
    return TerminalNoteInternalStoreAdminResult(
      action: request.action,
      sourceState: 'unavailable',
      outcome: 'rejected',
      mutatedPayload: false,
      isSuccess: false,
    );
  } finally {
    try {
      engine?.stop();
    } on Object {
      // The operation result is already fixed and remains content-free.
    }
  }
}

TerminalNoteInternalStoreAdminResult _exportPortable({
  required TerminalNoteInternalStoreAdminRequest request,
  required TerminalNoteStoreTransactionEngine engine,
  required TerminalNoteStoreResult loaded,
  required String sourceState,
}) {
  if (loaded.disposition != TerminalNoteStoreDisposition.loaded &&
      loaded.disposition != TerminalNoteStoreDisposition.empty &&
      loaded.disposition != TerminalNoteStoreDisposition.recoveryPreview) {
    return TerminalNoteInternalStoreAdminResult(
      action: request.action,
      sourceState: sourceState,
      outcome: 'rejected',
      mutatedPayload: false,
      isSuccess: false,
    );
  }
  final TerminalNoteStoreResult exported = engine.exportToApprovedPath(
    request.exportDestination,
  );
  return TerminalNoteInternalStoreAdminResult(
    action: request.action,
    sourceState: sourceState,
    outcome: exported.disposition == TerminalNoteStoreDisposition.exported
        ? 'exported'
        : 'rejected',
    mutatedPayload: false,
    isSuccess:
        exported.disposition == TerminalNoteStoreDisposition.exported &&
        exported.failure == null,
  );
}

TerminalNoteInternalStoreAdminResult _restoreBackup({
  required TerminalNoteInternalStoreAdminRequest request,
  required TerminalNoteStoreTransactionEngine engine,
  required TerminalNoteStoreResult loaded,
  required String sourceState,
}) {
  if (loaded.disposition != TerminalNoteStoreDisposition.recoveryPreview) {
    return TerminalNoteInternalStoreAdminResult(
      action: request.action,
      sourceState: sourceState,
      outcome: 'rejected',
      mutatedPayload: false,
      isSuccess: false,
    );
  }
  final TerminalNoteStoreResult restored = engine.retryRecovery();
  final bool success =
      restored.disposition == TerminalNoteStoreDisposition.committed &&
      restored.failure == null;
  return TerminalNoteInternalStoreAdminResult(
    action: request.action,
    sourceState: sourceState,
    outcome: success ? 'restored' : 'rejected',
    mutatedPayload: success,
    isSuccess: success,
  );
}

bool _isInspectable(TerminalNoteStoreResult result) =>
    switch (result.disposition) {
      TerminalNoteStoreDisposition.loaded ||
      TerminalNoteStoreDisposition.empty ||
      TerminalNoteStoreDisposition.recoveryPreview ||
      TerminalNoteStoreDisposition.recoveryRequired ||
      TerminalNoteStoreDisposition.upgradeRequired => true,
      _ => false,
    };

String _sourceState(TerminalNoteStoreResult result) =>
    switch (result.disposition) {
      TerminalNoteStoreDisposition.loaded => 'loaded',
      TerminalNoteStoreDisposition.empty => 'empty',
      TerminalNoteStoreDisposition.recoveryPreview => 'recovery-preview',
      TerminalNoteStoreDisposition.recoveryRequired => 'recovery-required',
      TerminalNoteStoreDisposition.upgradeRequired => 'upgrade-required',
      _ => _failureState(result.failure),
    };

String _failureState(TerminalNoteStoreFailure? failure) => switch (failure) {
  TerminalNoteStoreFailure.lockBusy => 'locked',
  TerminalNoteStoreFailure.recoveryRequired => 'recovery-required',
  TerminalNoteStoreFailure.upgradeRequired => 'upgrade-required',
  TerminalNoteStoreFailure.permissionDenied ||
  TerminalNoteStoreFailure.unsafeFile => 'unsafe',
  _ => 'unavailable',
};

TerminalNoteInternalStoreAdminRequest
parseTerminalNoteInternalStoreAdminRequest(List<String> arguments) {
  String? storePath;
  String? exportPath;
  var status = false;
  var restoreBackup = false;
  var acknowledgeSensitiveExport = false;
  var acknowledgeDataChange = false;
  for (final String argument in arguments) {
    if (argument.startsWith('--store=')) {
      if (storePath != null) {
        throw const FormatException('duplicate internal store path');
      }
      storePath = argument.substring('--store='.length);
      continue;
    }
    if (argument.startsWith('--export=')) {
      if (exportPath != null) {
        throw const FormatException('duplicate internal export path');
      }
      exportPath = argument.substring('--export='.length);
      continue;
    }
    if (argument == '--status') {
      if (status) throw const FormatException('duplicate status action');
      status = true;
      continue;
    }
    if (argument == '--restore-backup') {
      if (restoreBackup) {
        throw const FormatException('duplicate restore action');
      }
      restoreBackup = true;
      continue;
    }
    if (argument == '--acknowledge-sensitive-export') {
      if (acknowledgeSensitiveExport) {
        throw const FormatException('duplicate export acknowledgement');
      }
      acknowledgeSensitiveExport = true;
      continue;
    }
    if (argument == '--acknowledge-data-change') {
      if (acknowledgeDataChange) {
        throw const FormatException('duplicate change acknowledgement');
      }
      acknowledgeDataChange = true;
      continue;
    }
    throw const FormatException('unknown internal store argument');
  }
  if (storePath == null ||
      storePath.isEmpty ||
      utf8.encode(storePath).length > 4096) {
    throw const FormatException('bounded absolute internal store is required');
  }
  final int actionCount =
      (status ? 1 : 0) + (restoreBackup ? 1 : 0) + (exportPath == null ? 0 : 1);
  if (actionCount != 1) {
    throw const FormatException(
      'exactly one internal store action is required',
    );
  }
  final TerminalNoteStoreLocation location =
      TerminalNoteStoreLocation.fromAbsolutePath(storePath);
  if (status) {
    return TerminalNoteInternalStoreAdminRequest(
      action: TerminalNoteInternalStoreAdminAction.status,
      location: location,
      acknowledgeSensitiveExport: acknowledgeSensitiveExport,
      acknowledgeDataChange: acknowledgeDataChange,
    );
  }
  if (restoreBackup) {
    return TerminalNoteInternalStoreAdminRequest(
      action: TerminalNoteInternalStoreAdminAction.restoreBackup,
      location: location,
      acknowledgeSensitiveExport: acknowledgeSensitiveExport,
      acknowledgeDataChange: acknowledgeDataChange,
    );
  }
  if (exportPath == null ||
      exportPath.isEmpty ||
      utf8.encode(exportPath).length > 4096) {
    throw const FormatException('bounded absolute export path is required');
  }
  return TerminalNoteInternalStoreAdminRequest(
    action: TerminalNoteInternalStoreAdminAction.exportPortable,
    location: location,
    exportDestination: TerminalNoteApprovedExportPath.fromAbsolutePath(
      exportPath,
    ),
    acknowledgeSensitiveExport: acknowledgeSensitiveExport,
    acknowledgeDataChange: acknowledgeDataChange,
  );
}

void main(List<String> arguments) {
  try {
    final TerminalNoteInternalStoreAdminRequest request =
        parseTerminalNoteInternalStoreAdminRequest(arguments);
    final TerminalNoteInternalStoreAdminResult result =
        runTerminalNoteInternalStoreAdmin(request);
    stdout.writeln(result.machineLine());
    if (!result.isSuccess) exitCode = 1;
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_INTERNAL_STORE_ADMIN_FAIL action=invalid '
      'source_state=unavailable outcome=rejected payload_mutation=false '
      'content_free=true',
    );
    exitCode = 64;
  }
}
