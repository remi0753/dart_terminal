import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

var _failures = 0;

Future<void> main() => runTerminalIncidentServiceTests();

Future<void> runTerminalIncidentServiceTests() async {
  await _testLatestReportDiscoveryAndExport();
  await _testHostileReportEntriesAndBounds();
  await _testReportSelectionAuthority();
  await _testReportMutationCancellationAndAtomicity();
  await _testHangSampleContractAndPrivacy();
  await _testHangSampleFailuresAndCleanup();
  await _testServiceDisposalCancelsSample();
  await _testSystemProcessRunnerBounds();
  if (_failures != 0) {
    throw StateError('$_failures terminal incident service test(s) failed');
  }
}

Future<void> _testLatestReportDiscoveryAndExport() async {
  await _testAsync(
    'latest exact Apple report exports only after explicit destination',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        final File older = await fixture.writeReport(
          'older-private-name.ips',
          'OLDER-SENSITIVE-STACK',
          modified: DateTime.utc(2026, 9, 10),
        );
        final File newest = await fixture.writeReport(
          'newest-private-name.ips',
          'NEWEST-SENSITIVE-STACK',
          modified: DateTime.utc(2026, 9, 11),
        );
        await fixture.writeReport(
          'wrong-product.ips',
          'WRONG-SENSITIVE-STACK',
          bundleIdentifier: 'dev.example.other',
          modified: DateTime.utc(2026, 9, 12),
        );
        await fixture.writeReport(
          'wrong-process.ips',
          'WRONG-PROCESS-STACK',
          applicationName: 'other_process',
          modified: DateTime.utc(2026, 9, 13),
        );
        await File('${fixture.reports.path}/ignored-private.txt')
            .writeAsString('NEWEST-SENSITIVE-STACK');
        final TerminalAppleCrashReportStore store =
            TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
            );
        final TerminalIncidentReportSelection selection = await store.discover(
          cancellation: TerminalIncidentCancellation(),
        );
        final String publicSelection = selection.toString();
        _expect(
          selection.availability == TerminalIncidentReportAvailability.ready &&
              selection.matchingReportCount == 2 &&
              selection.canExport &&
              !publicSelection.contains(older.path) &&
              !publicSelection.contains(newest.path) &&
              !publicSelection.contains('SENSITIVE'),
          'selection exposed identity or did not select exact matches',
        );
        final File destination = File(
          '${fixture.exports.path}/explicit-latest.ips',
        );
        await destination.writeAsString('EXISTING-DESTINATION');
        await store.export(
          selection,
          destination,
          cancellation: TerminalIncidentCancellation(),
        );
        _expect(
          await destination.readAsString() == await newest.readAsString(),
          'latest report bytes were not atomically exported',
        );
        await _expectIncidentError(
          () => store.export(
            selection,
            File('${fixture.exports.path}/implicit-retry.ips'),
            cancellation: TerminalIncidentCancellation(),
          ),
          'report-selection-invalid',
        );
        _expect(!selection.canExport, 'consumed selection remained exportable');
        _expect(
          await _incidentTemporaryEntries(fixture.exports)
              .then((List<String> value) => value.isEmpty),
          'report export retained a sibling temporary',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testHostileReportEntriesAndBounds() async {
  await _testAsync(
    'malformed oversized linked and wrong-type reports are rejected',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        await File('${fixture.reports.path}/malformed.ips')
            .writeAsString('{not-json}\nSECRET');
        await File('${fixture.reports.path}/unterminated.ips')
            .writeAsString('{"bundleID":"$terminalUpdateProduct"}');
        await Directory('${fixture.reports.path}/directory.ips').create();
        final File outside = File('${fixture.root.path}/outside-private');
        await outside.writeAsString(_reportText('LINK-SECRET'));
        await Link('${fixture.reports.path}/linked.ips').create(outside.path);
        final File oversized = File('${fixture.reports.path}/oversized.ips');
        final RandomAccessFile sparse = await oversized.open(
          mode: FileMode.write,
        );
        await sparse.setPosition(257);
        await sparse.writeByte(0);
        await sparse.close();
        final TerminalAppleCrashReportStore store =
            TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              limits: const TerminalIncidentLimits(
                maximumHeaderBytes: 128,
                maximumAggregateHeaderBytes: 256,
                maximumRawBytes: 256,
              ),
            );
        final TerminalIncidentReportSelection selection = await store.discover(
          cancellation: TerminalIncidentCancellation(),
        );
        _expect(
          selection.availability ==
                  TerminalIncidentReportAvailability.notFound &&
              selection.matchingReportCount == 0,
          'hostile entries were treated as product reports',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _testAsync(
    'directory and aggregate scan bounds fail unavailable',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        for (var index = 0; index < 3; index++) {
          await File('${fixture.reports.path}/entry-$index.txt')
              .writeAsString('x');
        }
        final TerminalIncidentReportSelection entryLimited =
            await TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              limits: const TerminalIncidentLimits(maximumDirectoryEntries: 2),
            ).discover(cancellation: TerminalIncidentCancellation());
        _expect(
          entryLimited.availability ==
              TerminalIncidentReportAvailability.unavailable,
          'directory entry limit did not fail closed',
        );
        for (final FileSystemEntity entity
            in await fixture.reports.list().toList()) {
          await entity.delete();
        }
        for (var index = 0; index < 2; index++) {
          await File('${fixture.reports.path}/header-$index.ips')
              .writeAsString('${'x' * 80}\n');
        }
        final TerminalIncidentReportSelection headerLimited =
            await TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              limits: const TerminalIncidentLimits(
                maximumHeaderBytes: 96,
                maximumAggregateHeaderBytes: 128,
              ),
            ).discover(cancellation: TerminalIncidentCancellation());
        _expect(
          headerLimited.availability ==
              TerminalIncidentReportAvailability.unavailable,
          'aggregate header limit did not fail closed',
        );
        for (final FileSystemEntity entity
            in await fixture.reports.list().toList()) {
          await entity.delete();
        }
        await fixture.writeReport(
          'match-a.ips',
          'MATCH-A',
          modified: DateTime.utc(2026, 9, 10),
        );
        await fixture.writeReport(
          'match-b.ips',
          'MATCH-B',
          modified: DateTime.utc(2026, 9, 11),
        );
        final TerminalIncidentReportSelection matchLimited =
            await TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              limits: const TerminalIncidentLimits(maximumMatchingReports: 1),
            ).discover(cancellation: TerminalIncidentCancellation());
        _expect(
          matchLimited.availability ==
              TerminalIncidentReportAvailability.unavailable,
          'matching report limit did not fail closed',
        );
        final TerminalIncidentReportSelection missing =
            await TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: Directory(
                '${fixture.root.path}/missing-reports',
              ),
            ).discover(cancellation: TerminalIncidentCancellation());
        _expect(
          missing.availability ==
              TerminalIncidentReportAvailability.unavailable,
          'missing report directory was not unavailable',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _testAsync('cancelled discovery exposes only a fixed error', () async {
    final _IncidentFixture fixture = await _IncidentFixture.create();
    try {
      final TerminalIncidentCancellation cancellation =
          TerminalIncidentCancellation()..cancel();
      await _expectIncidentError(
        () => TerminalAppleCrashReportStore(
          diagnosticReportsDirectory: fixture.reports,
        ).discover(cancellation: cancellation),
        'operation-cancelled',
      );
    } finally {
      await fixture.dispose();
    }
  });
}

Future<void> _testReportSelectionAuthority() async {
  await _testAsync(
    'report selections are bound to one store and revision',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        final File report = await fixture.writeReport(
          'owned.ips',
          'AUTHORITY-SECRET',
          modified: DateTime.utc(2026, 9, 11),
        );
        final TerminalAppleCrashReportStore owner =
            TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
            );
        final TerminalIncidentReportSelection selection = await owner.discover(
          cancellation: TerminalIncidentCancellation(),
        );
        await _expectIncidentError(
          () =>
              TerminalAppleCrashReportStore(
                diagnosticReportsDirectory: fixture.reports,
              ).export(
                selection,
                File('${fixture.exports.path}/foreign.ips'),
                cancellation: TerminalIncidentCancellation(),
              ),
          'report-selection-invalid',
        );
        await report.writeAsString(_reportText('CHANGED-SECRET'));
        final File destination = File('${fixture.exports.path}/stale.ips');
        await destination.writeAsString('PRESERVE');
        await _expectIncidentError(
          () => owner.export(
            selection,
            destination,
            cancellation: TerminalIncidentCancellation(),
          ),
          'report-source-changed',
        );
        _expect(
          await destination.readAsString() == 'PRESERVE',
          'stale report selection replaced its destination',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testReportMutationCancellationAndAtomicity() async {
  await _testAsync(
    'mutation during report copy preserves destination',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        final File report = await fixture.writeReport(
          'mutable.ips',
          'MUTATION-SECRET-${'x' * 128000}',
          modified: DateTime.utc(2026, 9, 11),
        );
        var changed = false;
        final TerminalAppleCrashReportStore store =
            TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              copyBoundaryObserver:
                  (String boundary, File source, File temporary) async {
                    if (boundary == 'after-copy-chunk' && !changed) {
                      changed = true;
                      await source.setLastModified(DateTime.utc(2026, 9, 12));
                    }
                  },
            );
        final TerminalIncidentReportSelection selection = await store.discover(
          cancellation: TerminalIncidentCancellation(),
        );
        final File destination = File('${fixture.exports.path}/mutable.ips');
        await destination.writeAsString('PRESERVE');
        await _expectIncidentError(
          () => store.export(
            selection,
            destination,
            cancellation: TerminalIncidentCancellation(),
          ),
          'report-source-changed',
        );
        _expect(changed, 'copy mutation hook did not execute');
        _expect(
          await destination.readAsString() == 'PRESERVE' &&
              await report.exists() &&
              await _incidentTemporaryEntries(fixture.exports)
                  .then((List<String> value) => value.isEmpty),
          'mutation damaged source/destination or retained temporary data',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _testAsync(
    'copy cancellation and unsafe destinations fail closed',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        await fixture.writeReport(
          'cancel.ips',
          'CANCEL-SECRET-${'x' * 128000}',
          modified: DateTime.utc(2026, 9, 11),
        );
        final TerminalIncidentCancellation cancellation =
            TerminalIncidentCancellation();
        final TerminalAppleCrashReportStore store =
            TerminalAppleCrashReportStore(
              diagnosticReportsDirectory: fixture.reports,
              copyBoundaryObserver:
                  (String boundary, File source, File temporary) {
                    if (boundary == 'after-copy-chunk') cancellation.cancel();
                  },
            );
        final TerminalIncidentReportSelection selection = await store.discover(
          cancellation: TerminalIncidentCancellation(),
        );
        final File destination = File('${fixture.exports.path}/cancel.ips');
        await destination.writeAsString('PRESERVE');
        await _expectIncidentError(
          () =>
              store.export(selection, destination, cancellation: cancellation),
          'operation-cancelled',
        );
        final TerminalIncidentReportSelection linkSelection = await store
            .discover(cancellation: TerminalIncidentCancellation());
        final File linkTarget = File('${fixture.root.path}/link-target');
        await linkTarget.writeAsString('DO-NOT-TOUCH');
        final Link destinationLink = Link('${fixture.exports.path}/linked.ips');
        await destinationLink.create(linkTarget.path);
        await _expectIncidentError(
          () => store.export(
            linkSelection,
            File(destinationLink.path),
            cancellation: TerminalIncidentCancellation(),
          ),
          'destination-invalid',
        );
        final TerminalIncidentReportSelection extensionSelection = await store
            .discover(cancellation: TerminalIncidentCancellation());
        await _expectIncidentError(
          () => store.export(
            extensionSelection,
            File('${fixture.exports.path}/wrong-extension.txt'),
            cancellation: TerminalIncidentCancellation(),
          ),
          'destination-invalid',
        );
        _expect(
          await destination.readAsString() == 'PRESERVE' &&
              await linkTarget.readAsString() == 'DO-NOT-TOUCH' &&
              await _incidentTemporaryEntries(fixture.exports)
                  .then((List<String> value) => value.isEmpty),
          'cancelled or unsafe export changed authority boundaries',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testHangSampleContractAndPrivacy() async {
  await _testAsync(
    'hang sample uses exact current-PID argv and cleans raw temp',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        const String sensitive = 'PRIVATE-THREAD-STACK /Users/private/secret';
        final _FakeIncidentProcessRunner runner = _FakeIncidentProcessRunner(
          outputBytes: utf8.encode(sensitive),
        );
        final TerminalLocalIncidentService service =
            TerminalLocalIncidentService(
              reportStore: _UnavailableReportStore(),
              temporaryParent: fixture.temporary,
              processRunner: runner,
              currentProcessId: 4242,
            );
        final File destination = File(
          '${fixture.exports.path}/explicit.sample.txt',
        );
        await service.captureHangSample(destination);
        _expect(
          runner.executable == '/usr/bin/sample' &&
              runner.arguments.length == 5 &&
              runner.arguments[0] == '4242' &&
              runner.arguments[1] == '1' &&
              runner.arguments[2] == '1' &&
              runner.arguments[3] == '-file' &&
              runner.arguments[4] != destination.path &&
              runner.timeout == const Duration(seconds: 5) &&
              runner.maximumOutputBytes == 64 * 1024 &&
              runner.workspaceWasPrivate &&
              await destination.readAsString() == sensitive &&
              !await File(runner.arguments[4]).exists() &&
              await fixture.temporary.list().isEmpty,
          'sample argv, raw publication, or temporary cleanup differs',
        );
        service.dispose();
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testHangSampleFailuresAndCleanup() async {
  await _testAsync(
    'sample process outcomes preserve existing destination',
    () async {
      for (final MapEntry<TerminalIncidentProcessDisposition, String> scenario
          in const <TerminalIncidentProcessDisposition, String>{
            TerminalIncidentProcessDisposition.cancelled: 'operation-cancelled',
            TerminalIncidentProcessDisposition.timedOut: 'sample-timeout',
            TerminalIncidentProcessDisposition.unavailable:
                'sample-unavailable',
            TerminalIncidentProcessDisposition.failed: 'sample-failed',
            TerminalIncidentProcessDisposition.outputOverflow:
                'sample-output-overflow',
          }.entries) {
        final _IncidentFixture fixture = await _IncidentFixture.create();
        try {
          final TerminalLocalIncidentService service =
              TerminalLocalIncidentService(
                reportStore: _UnavailableReportStore(),
                temporaryParent: fixture.temporary,
                processRunner: _FakeIncidentProcessRunner(
                  disposition: scenario.key,
                ),
                currentProcessId: 4242,
              );
          final File destination = File(
            '${fixture.exports.path}/failure.sample.txt',
          );
          await destination.writeAsString('PRESERVE');
          await _expectIncidentError(
            () => service.captureHangSample(destination),
            scenario.value,
          );
          _expect(
            await destination.readAsString() == 'PRESERVE' &&
                await fixture.temporary.list().isEmpty,
            '${scenario.key.name} retained raw data or replaced destination',
          );
          service.dispose();
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  await _testAsync(
    'invalid linked and oversized sample outputs are removed',
    () async {
      for (final _FakeIncidentProcessRunner runner
          in <_FakeIncidentProcessRunner>[
            _FakeIncidentProcessRunner(createNoOutput: true),
            _FakeIncidentProcessRunner(outputBytes: List<int>.filled(65, 0x41)),
            _FakeIncidentProcessRunner(createLinkedOutput: true),
          ]) {
        final _IncidentFixture fixture = await _IncidentFixture.create();
        try {
          final TerminalIncidentLimits limits = const TerminalIncidentLimits(
            maximumRawBytes: 64,
          );
          final TerminalLocalIncidentService service =
              TerminalLocalIncidentService(
                reportStore: _UnavailableReportStore(),
                temporaryParent: fixture.temporary,
                processRunner: runner,
                currentProcessId: 4242,
                limits: limits,
              );
          final File destination = File(
            '${fixture.exports.path}/invalid.sample.txt',
          );
          await destination.writeAsString('PRESERVE');
          await _expectIncidentError(
            () => service.captureHangSample(destination),
            'sample-output-invalid',
          );
          final bool outputLinkRemoved =
              runner.arguments.isEmpty ||
              !await File(runner.arguments.last).exists();
          final bool temporaryStateIsSafe = runner.linkTarget == null
              ? await fixture.temporary.list().isEmpty
              : await runner.linkTarget!.exists();
          _expect(
            await destination.readAsString() == 'PRESERVE' &&
                outputLinkRemoved &&
                temporaryStateIsSafe,
            'invalid sample output was published or not safely cleaned',
          );
          service.dispose();
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  await _testAsync(
    'process exceptions and pre-cancellation stay content-free',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        const String sensitive = 'SECRET-PROCESS-ERROR';
        final TerminalLocalIncidentService failing =
            TerminalLocalIncidentService(
              reportStore: _UnavailableReportStore(),
              temporaryParent: fixture.temporary,
              processRunner: _FakeIncidentProcessRunner(
                thrownError: StateError(sensitive),
              ),
              currentProcessId: 4242,
            );
        final TerminalIncidentException error = await _captureIncidentError(
          () => failing.captureHangSample(
            File('${fixture.exports.path}/throw.sample.txt'),
          ),
        );
        _expect(
          error.code == 'sample-failed' &&
              !error.toString().contains(sensitive),
          'underlying sample error leaked',
        );
        failing.dispose();
        final _FakeIncidentProcessRunner runner = _FakeIncidentProcessRunner();
        final TerminalLocalIncidentService cancelled =
            TerminalLocalIncidentService(
              reportStore: _UnavailableReportStore(),
              temporaryParent: fixture.temporary,
              processRunner: runner,
              currentProcessId: 4242,
            );
        await _expectIncidentError(
          () => cancelled.captureHangSample(
            File('${fixture.exports.path}/wrong-extension.txt'),
          ),
          'destination-invalid',
        );
        final TerminalIncidentCancellation token =
            TerminalIncidentCancellation()..cancel();
        await _expectIncidentError(
          () => cancelled.captureHangSample(
            File('${fixture.exports.path}/cancelled.sample.txt'),
            cancellation: token,
          ),
          'operation-cancelled',
        );
        _expect(
          runner.callCount == 0 && await fixture.temporary.list().isEmpty,
          'pre-cancelled sample acquired process or storage authority',
        );
        cancelled.dispose();
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testServiceDisposalCancelsSample() async {
  await _testAsync(
    'service disposal cancels in-flight sampling and rejects reuse',
    () async {
      final _IncidentFixture fixture = await _IncidentFixture.create();
      try {
        final _FakeIncidentProcessRunner runner = _FakeIncidentProcessRunner(
          waitForCancellation: true,
        );
        final TerminalLocalIncidentService service =
            TerminalLocalIncidentService(
              reportStore: _UnavailableReportStore(),
              temporaryParent: fixture.temporary,
              processRunner: runner,
              currentProcessId: 4242,
            );
        final Future<void> capture = service.captureHangSample(
          File('${fixture.exports.path}/dispose.sample.txt'),
        );
        await runner.started.future;
        service.dispose();
        await _expectIncidentError(() => capture, 'operation-cancelled');
        await _expectIncidentError(
          () => service.captureHangSample(
            File('${fixture.exports.path}/reuse.sample.txt'),
          ),
          'service-disposed',
        );
        _expect(
          runner.observedCancellation && await fixture.temporary.list().isEmpty,
          'dispose did not cancel runner or clean private storage',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
}

Future<void> _testSystemProcessRunnerBounds() async {
  await _testAsync(
    'system process adapter reduces output failure and timeout',
    () async {
      const TerminalIncidentSystemProcessRunner runner =
          TerminalIncidentSystemProcessRunner();
      final TerminalIncidentProcessResult overflow = await runner.run(
        '/usr/bin/printf',
        <String>['sensitive-output'],
        timeout: const Duration(seconds: 1),
        maximumOutputBytes: 1,
        cancellation: TerminalIncidentCancellation(),
      );
      final TerminalIncidentProcessResult failed = await runner.run(
        '/usr/bin/false',
        const <String>[],
        timeout: const Duration(seconds: 1),
        maximumOutputBytes: 1,
        cancellation: TerminalIncidentCancellation(),
      );
      final TerminalIncidentProcessResult timedOut = await runner.run(
        '/bin/sleep',
        const <String>['2'],
        timeout: const Duration(milliseconds: 10),
        maximumOutputBytes: 1,
        cancellation: TerminalIncidentCancellation(),
      );
      final TerminalIncidentCancellation cancelledToken =
          TerminalIncidentCancellation()..cancel();
      final TerminalIncidentProcessResult cancelled = await runner.run(
        '/usr/bin/true',
        const <String>[],
        timeout: const Duration(seconds: 1),
        maximumOutputBytes: 1,
        cancellation: cancelledToken,
      );
      _expect(
        overflow.disposition ==
                TerminalIncidentProcessDisposition.outputOverflow &&
            failed.disposition == TerminalIncidentProcessDisposition.failed &&
            timedOut.disposition ==
                TerminalIncidentProcessDisposition.timedOut &&
            cancelled.disposition ==
                TerminalIncidentProcessDisposition.cancelled &&
            !overflow.toString().contains('sensitive-output'),
        'system runner did not reduce raw process output to fixed outcomes',
      );
    },
  );
}

final class _IncidentFixture {
  _IncidentFixture({
    required this.root,
    required this.reports,
    required this.exports,
    required this.temporary,
  });

  final Directory root;
  final Directory reports;
  final Directory exports;
  final Directory temporary;

  static Future<_IncidentFixture> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'dart-terminal-incidents-',
    );
    final Directory reports = Directory('${root.path}/DiagnosticReports');
    final Directory exports = Directory('${root.path}/Exports');
    final Directory temporary = Directory('${root.path}/Temporary');
    await reports.create();
    await exports.create();
    await temporary.create();
    return _IncidentFixture(
      root: root,
      reports: reports,
      exports: exports,
      temporary: temporary,
    );
  }

  Future<File> writeReport(
    String name,
    String sensitive, {
    String bundleIdentifier = terminalUpdateProduct,
    String applicationName = terminalIncidentApplicationName,
    required DateTime modified,
  }) async {
    final File file = File('${reports.path}/$name');
    await file.writeAsString(
      _reportText(
        sensitive,
        bundleIdentifier: bundleIdentifier,
        applicationName: applicationName,
      ),
    );
    await file.setLastModified(modified);
    return file;
  }

  Future<void> dispose() => root.delete(recursive: true);
}

final class _UnavailableReportStore
    implements TerminalIncidentCrashReportStore {
  @override
  Future<TerminalIncidentReportSelection> discover({
    required TerminalIncidentCancellation cancellation,
  }) async => TerminalAppleCrashReportStore(
    diagnosticReportsDirectory: Directory('/path/that/is/not/used'),
  ).discover(cancellation: cancellation);

  @override
  Future<void> export(
    TerminalIncidentReportSelection selection,
    File destination, {
    required TerminalIncidentCancellation cancellation,
  }) async {
    throw StateError('unavailable store cannot export');
  }
}

final class _FakeIncidentProcessRunner
    implements TerminalIncidentProcessRunner {
  _FakeIncidentProcessRunner({
    this.disposition = TerminalIncidentProcessDisposition.completed,
    List<int>? outputBytes,
    this.createNoOutput = false,
    this.createLinkedOutput = false,
    this.thrownError,
    this.waitForCancellation = false,
  }) : outputBytes = outputBytes ?? utf8.encode('fixture sample');

  final TerminalIncidentProcessDisposition disposition;
  final List<int> outputBytes;
  final bool createNoOutput;
  final bool createLinkedOutput;
  final Object? thrownError;
  final bool waitForCancellation;
  final Completer<void> started = Completer<void>();

  String executable = '';
  List<String> arguments = const <String>[];
  Duration timeout = Duration.zero;
  int maximumOutputBytes = 0;
  int callCount = 0;
  bool workspaceWasPrivate = false;
  bool observedCancellation = false;
  File? linkTarget;

  @override
  Future<TerminalIncidentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required int maximumOutputBytes,
    required TerminalIncidentCancellation cancellation,
  }) async {
    callCount++;
    this.executable = executable;
    this.arguments = List<String>.unmodifiable(arguments);
    this.timeout = timeout;
    this.maximumOutputBytes = maximumOutputBytes;
    if (!started.isCompleted) started.complete();
    final File output = File(arguments.last);
    final FileStat workspace = await output.parent.stat();
    workspaceWasPrivate = workspace.mode & 0x3f == 0;
    final Object? error = thrownError;
    if (error != null) throw error;
    if (waitForCancellation) {
      final Completer<void> cancelled = Completer<void>();
      cancellation.addListener(() {
        observedCancellation = true;
        if (!cancelled.isCompleted) cancelled.complete();
      });
      await cancelled.future;
      return const TerminalIncidentProcessResult(
        TerminalIncidentProcessDisposition.cancelled,
      );
    }
    if (disposition == TerminalIncidentProcessDisposition.completed &&
        !createNoOutput) {
      if (createLinkedOutput) {
        linkTarget = File('${output.parent.parent.path}/sample-link-target');
        await linkTarget!.writeAsBytes(outputBytes);
        await Link(output.path).create(linkTarget!.path);
      } else {
        await output.writeAsBytes(outputBytes);
      }
    }
    return TerminalIncidentProcessResult(disposition);
  }
}

String _reportText(
  String sensitive, {
  String bundleIdentifier = terminalUpdateProduct,
  String applicationName = terminalIncidentApplicationName,
}) =>
    '${jsonEncode(<String, Object?>{'app_name': applicationName, 'bundleID': bundleIdentifier, 'timestamp': 'private-and-not-retained'})}\n'
    '$sensitive\n';

Future<List<String>> _incidentTemporaryEntries(Directory directory) async =>
    <String>[
      await for (final FileSystemEntity entity in directory.list())
        if (entity.path.contains('.dart-terminal-incident-')) entity.path,
    ];

Future<TerminalIncidentException> _captureIncidentError(
  Future<void> Function() body,
) async {
  try {
    await body();
  } on TerminalIncidentException catch (error) {
    return error;
  }
  throw StateError('expected TerminalIncidentException');
}

Future<void> _expectIncidentError(
  Future<void> Function() body,
  String code,
) async {
  final TerminalIncidentException error = await _captureIncidentError(body);
  _expect(error.code == code, 'expected $code, got ${error.code}');
}

Future<void> _testAsync(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    _failures++;
    stderr.writeln('FAIL $name: $error\n$stackTrace');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
