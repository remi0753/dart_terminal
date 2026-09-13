import 'dart:async';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

var _failures = 0;

Future<void> main() => runTerminalUpdateControllerTests();

Future<void> runTerminalUpdateControllerTests() async {
  await _testNotConfiguredIsInert();
  await _testCheckInstallAndPlainNotes();
  await _testSingleFlightCancellationAndDisposal();
  await _testFailureIsContentFree();
  if (_failures != 0) {
    throw StateError('$_failures terminal update controller test(s) failed');
  }
}

Future<void> _testNotConfiguredIsInert() async {
  await _test(
    'unconfigured controller performs no remote or install work',
    () async {
      final TerminalUpdateController controller = TerminalUpdateController();
      final TerminalUpdateOperationResult check = await controller.check();
      final TerminalUpdateOperationResult install = await controller.install();
      _expect(
        check.disposition == TerminalUpdateOperationDisposition.notConfigured &&
            install.disposition ==
                TerminalUpdateOperationDisposition.unavailable &&
            controller.status == TerminalUpdateStatus.notConfigured &&
            controller.release == null &&
            controller.machineLine() == 'TERMINAL_UPDATE status=notConfigured configured=false busy=false available=false notes=0',
        'unconfigured controller was not inert and explicit',
      );
      await controller.dispose();
    },
  );
}

Future<void> _testCheckInstallAndPlainNotes() async {
  await _test(
    'authenticated result projects bounded plain notes and prepares once',
    () async {
      final _UpdateService service = _UpdateService()..next = _release();
      final TerminalUpdateController controller = TerminalUpdateController(
        service: service,
      );
      var changes = 0;
      controller.addListener(() => changes++);
      final TerminalUpdateOperationResult check = await controller.check();
      final TerminalUpdateOperationResult install = await controller.install();
      _expect(
        check.disposition == TerminalUpdateOperationDisposition.completed &&
            install.disposition ==
                TerminalUpdateOperationDisposition.completed &&
            controller.status == TerminalUpdateStatus.restartRequired &&
            controller.release?.releaseNotes.join('|') ==
                '<b>Plain, never markup.</b>|Run no scripts.' &&
            service.checkCount == 1 &&
            service.installCount == 1 &&
            service.installed?.archiveSha256 == _hash('d') &&
            changes >= 4,
        'check/install projection differs',
      );
      await controller.dispose();
    },
  );
}

Future<void> _testSingleFlightCancellationAndDisposal() async {
  await _test(
    'single-flight cancellation ignores late service completion',
    () async {
      final _UpdateService service = _UpdateService();
      final Completer<TerminalUpdateRelease?> pending =
          Completer<TerminalUpdateRelease?>();
      service.pending = pending;
      final TerminalUpdateController controller = TerminalUpdateController(
        service: service,
      );
      final Future<TerminalUpdateOperationResult> first = controller.check();
      final TerminalUpdateOperationResult busy = await controller.check();
      controller.cancel();
      pending.complete(_release());
      final TerminalUpdateOperationResult cancelled = await first;
      _expect(
        busy.disposition == TerminalUpdateOperationDisposition.busy &&
            cancelled.disposition ==
                TerminalUpdateOperationDisposition.cancelled &&
            controller.status == TerminalUpdateStatus.cancelled &&
            controller.release == null &&
            service.cancelCount == 1,
        'single-flight cancellation accepted a stale result',
      );
      await controller.dispose();
      _expect(
        controller.status == TerminalUpdateStatus.disposed &&
            service.disposeCount == 1 &&
            (await controller.check()).disposition ==
                TerminalUpdateOperationDisposition.unavailable,
        'controller disposal did not close service ownership',
      );
    },
  );
}

Future<void> _testFailureIsContentFree() async {
  await _test(
    'service failures retain only a fixed status classification',
    () async {
      final _UpdateService service = _UpdateService()
        ..failure = StateError(
          'SECRET terminal text /Users/example token=credential',
        );
      final TerminalUpdateController controller = TerminalUpdateController(
        service: service,
      );
      final TerminalUpdateOperationResult result = await controller.check();
      final String line = controller.machineLine();
      _expect(
        result.disposition == TerminalUpdateOperationDisposition.failed &&
            controller.status == TerminalUpdateStatus.failed &&
            !line.contains('SECRET') &&
            !line.contains('/Users/') &&
            !line.contains('credential'),
        'service error escaped fixed update status',
      );
      await controller.dispose();
    },
  );
}

TerminalUpdateRelease _release() => TerminalUpdateRelease(
  version: TerminalSemanticVersion.parse('0.2.0'),
  build: 2,
  minimumMacos: const TerminalMacosVersion(14, 0),
  archiveUrl: Uri.parse('https://updates.example.test/DartTerminal.zip'),
  archiveSize: 4096,
  archiveSha256: _hash('d'),
  releaseNotes: const <String>[
    '<b>Plain, never markup.</b>',
    'Run no scripts.',
  ],
);

final class _UpdateService implements TerminalUpdateProductService {
  TerminalUpdateRelease? next;
  Completer<TerminalUpdateRelease?>? pending;
  Object? failure;
  TerminalUpdateRelease? installed;
  var checkCount = 0;
  var installCount = 0;
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  Future<TerminalUpdateRelease?> check() async {
    checkCount++;
    final Object? selectedFailure = failure;
    if (selectedFailure != null) throw selectedFailure;
    final Completer<TerminalUpdateRelease?>? selectedPending = pending;
    return selectedPending == null ? next : selectedPending.future;
  }

  @override
  Future<void> prepareInstall(TerminalUpdateRelease release) async {
    installCount++;
    installed = release;
  }

  @override
  void cancel() {
    cancelCount++;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}

String _hash(String character) => List<String>.filled(64, character).join();

Future<void> _test(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } catch (error) {
    _failures++;
    stderr.writeln('FAIL $name: $error');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
