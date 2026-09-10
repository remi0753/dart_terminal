import 'dart:async';
import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalConfigReloadTests();

Future<void> runTerminalConfigReloadTests() async {
  await _testAcceptedRejectedAndCorrectedTransactions();
  await _testFixedCommandLinePriorityAndWarningAcceptance();
  await _testSingleFlightFailureAndDispose();
}

Future<void> _testAcceptedRejectedAndCorrectedTransactions() async {
  final _ReloadMemoryFileSystem files = _ReloadMemoryFileSystem(
    <String, String>{
      '/config': '''
font-size = 15
macos-option-key = escape
keybind = control+d=unbind
''',
    },
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  final List<String> arguments = <String>['--config=/config'];
  final TerminalConfigSnapshot initial = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController.fromStartup(
        arguments: arguments,
        initialSnapshot: initial,
        loader: loader,
        environment: const <String, String>{},
        currentDirectory: '/workspace',
      );

  arguments.add('--font-size=99');
  files.write('/config', '''
font-size = 18
macos-option-key = text
keybind = control+d=terminal.send-quit-signal
''');
  final TerminalConfigReloadResult applied = await controller.reload();
  _expect(
    applied.disposition == TerminalConfigReloadDisposition.applied &&
        applied.isAccepted &&
        applied.changePlan!.liveChanges.length == 2 &&
        applied.changePlan!.newSessionChanges.single.option.name ==
            'font-size' &&
        controller.acceptedGeneration == 1 &&
        controller.effectiveSnapshot.value(
              TerminalProductConfigSchema.fontSize,
            ) ==
            18,
    'valid reload atomically publishes deterministic mixed-policy changes',
  );

  files.write('/config', '''
font-size = enormous
macos-option-key = escape
''');
  final TerminalConfigReloadResult rejected = await controller.reload();
  _expect(
    rejected.disposition == TerminalConfigReloadDisposition.rejected &&
        !rejected.isAccepted &&
        rejected.changePlan == null &&
        rejected.diagnostics.single.code == 'CFG_INVALID_VALUE' &&
        rejected.diagnostics.single.source.path == '/config' &&
        rejected.diagnostics.single.source.line == 1 &&
        rejected.diagnostics.single.hint != null &&
        identical(rejected.effectiveSnapshot, applied.effectiveSnapshot) &&
        controller.acceptedGeneration == 1 &&
        controller.effectiveSnapshot.value(
              TerminalProductConfigSchema.macosOptionKey,
            ) ==
            TerminalConfiguredOptionKey.text,
    'erroneous reload exposes diagnostics and retains every last-known-good value',
  );

  files.write('/config', '''
font-size = 18
macos-option-key = text
keybind = control+d=terminal.send-quit-signal
''');
  final TerminalConfigReloadResult corrected = await controller.reload();
  _expect(
    corrected.disposition == TerminalConfigReloadDisposition.unchanged &&
        corrected.isAccepted &&
        corrected.changePlan!.isEmpty &&
        controller.acceptedGeneration == 2 &&
        controller.lastAttemptDiagnostics.isEmpty &&
        identical(
          controller.lastAttemptedSnapshot,
          corrected.candidateSnapshot,
        ),
    'corrected semantic no-op advances effective provenance and clears diagnostics',
  );
}

Future<void> _testFixedCommandLinePriorityAndWarningAcceptance() async {
  final _ReloadMemoryFileSystem files = _ReloadMemoryFileSystem(
    <String, String>{'/config': 'font-size = 12\n'},
  );
  final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
  const List<String> arguments = <String>['--config=/config', '--font-size=16'];
  final TerminalConfigSnapshot initial = loader
      .resolve(arguments, environment: const <String, String>{})
      .snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController.fromStartup(
        arguments: arguments,
        initialSnapshot: initial,
        loader: loader,
        environment: const <String, String>{},
      );
  files.write('/config', '''
font-size = 20
macos-option-key = escape
macos-option-key = text
''');
  final TerminalConfigReloadResult result = await controller.reload();
  _expect(
    result.disposition == TerminalConfigReloadDisposition.applied &&
        result.diagnostics.single.code == 'CFG_DUPLICATE_OPTION' &&
        result.diagnostics.single.severity ==
            TerminalConfigDiagnosticSeverity.warning &&
        result.changePlan!.changes.single.option.name == 'macos-option-key' &&
        result.effectiveSnapshot.value(TerminalProductConfigSchema.fontSize) ==
            16 &&
        result.effectiveSnapshot
                .resolved(TerminalProductConfigSchema.fontSize)
                .source
                .kind ==
            TerminalConfigSourceKind.commandLine,
    'warnings are accepted while fixed startup CLI inputs retain precedence',
  );
}

Future<void> _testSingleFlightFailureAndDispose() async {
  final TerminalConfigSnapshot initial = TerminalConfigLoader().resolve(
    const <String>['--no-config'],
    environment: const <String, String>{},
  ).snapshot;
  final Completer<TerminalConfigResolution> pending =
      Completer<TerminalConfigResolution>();
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => pending.future,
      );
  final Future<TerminalConfigReloadResult> first = controller.reload();
  final TerminalConfigReloadResult busy = await controller.reload();
  _expect(
    controller.inProgress &&
        busy.disposition == TerminalConfigReloadDisposition.busy &&
        identical(busy.effectiveSnapshot, initial),
    'concurrent reload is consumed as busy and not queued',
  );
  pending.complete(
    TerminalConfigResolution(
      snapshot: initial,
      remainingArguments: const <String>[],
    ),
  );
  final TerminalConfigReloadResult completed = await first;
  _expect(
    completed.disposition == TerminalConfigReloadDisposition.unchanged &&
        !controller.inProgress,
    'single-flight owner clears after completion',
  );

  final Completer<TerminalConfigResolution> disposalPending =
      Completer<TerminalConfigResolution>();
  final TerminalConfigReloadController disposing =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => disposalPending.future,
      );
  final Future<TerminalConfigReloadResult> disposalAttempt = disposing.reload();
  disposing.dispose();
  disposalPending.complete(
    TerminalConfigResolution(
      snapshot: initial,
      remainingArguments: const <String>[],
    ),
  );
  final TerminalConfigReloadResult disposedInFlight = await disposalAttempt;
  _expect(
    disposedInFlight.disposition == TerminalConfigReloadDisposition.disposed &&
        disposing.acceptedGeneration == 0 &&
        identical(disposing.effectiveSnapshot, initial) &&
        !disposing.inProgress,
    'disposal during resolution prevents later candidate publication',
  );

  final TerminalConfigReloadController failing = TerminalConfigReloadController(
    initialSnapshot: initial,
    resolver: () => throw StateError('test reload failure'),
  );
  final TerminalConfigReloadResult failed = await failing.reload();
  _expect(
    failed.disposition == TerminalConfigReloadDisposition.failed &&
        failed.error is StateError &&
        failed.stackTrace != null &&
        identical(failing.lastFailure, failed.error) &&
        identical(failed.effectiveSnapshot, initial) &&
        !failing.inProgress,
    'unexpected resolver failure is retained without changing effective state',
  );
  failing.dispose();
  final TerminalConfigReloadResult disposed = await failing.reload();
  _expect(
    disposed.disposition == TerminalConfigReloadDisposition.disposed &&
        identical(disposed.effectiveSnapshot, initial),
    'disposed controller rejects later requests without invoking its resolver',
  );
}

final class _ReloadMemoryFileSystem implements TerminalConfigFileSystem {
  _ReloadMemoryFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

  final Map<String, List<int>> _files;

  void write(String path, String value) {
    _files[path] = utf8.encode(value);
  }

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  List<int> readBytes(String path) => List<int>.from(_files[path]!);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      includedPath.startsWith('/') ? includedPath : '/$includedPath';
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
