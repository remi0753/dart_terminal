import 'dart:typed_data';

import 'package:dart_terminal_applescript_macos/dart_terminal_applescript_macos.dart';
import 'package:dart_terminal_applescript_macos/testing.dart';

void main() {
  _testFacadeInitializationBoundary();
  _testSelfAutomationAdmissionBoundary();
  _testSessionValidationAndLifecycle();
  _testTypedNativeFailures();
}

void _testSelfAutomationAdmissionBoundary() {
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptMacosSelfAutomation.enqueueCommand(Uint8List(0)),
    'empty self-automation packet',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptMacosSelfAutomation.enqueueCommand(
      Uint8List(TerminalAppleScriptMacosLimits.maximumCommandBytes + 1),
    ),
    'oversized self-automation packet',
  );
  final TerminalAppleScriptMacosException wrongThread =
      _expectThrows<TerminalAppleScriptMacosException>(
        () => TerminalAppleScriptMacosSelfAutomation.enqueueCommand(
          Uint8List.fromList(<int>[1]),
        ),
        'standalone self-automation thread boundary',
      );
  _expect(
    wrongThread.operation == 'enqueueSelfAutomationCommand' &&
        wrongThread.status == 8,
    'self-automation did not retain the native main-thread rejection',
  );
}

void _testFacadeInitializationBoundary() {
  _expect(
    !TerminalAppleScriptMacos.isInitialized,
    'facade starts without loading a bundle capability',
  );
  _expectThrows<StateError>(
    TerminalAppleScriptMacos.open,
    'session opened before declared capability initialization',
  );
}

void _testSessionValidationAndLifecycle() {
  final _FakeBindings bindings = _FakeBindings();
  final TerminalAppleScriptMacosSession session =
      TerminalAppleScriptMacosSession.withBindings(
        bindings,
        maximumPendingCommands: 4,
        commandTimeout: const Duration(seconds: 7),
      );
  _expect(
    bindings.startedMaximum == 4 &&
        bindings.startedTimeoutMicros == 7000000 &&
        !session.isDisposed,
    'typed session bounds were not projected to native start',
  );

  final Uint8List snapshot = Uint8List.fromList(<int>[1, 2, 3]);
  session.publishSnapshot(snapshot);
  snapshot[0] = 9;
  _expect(
    bindings.snapshot!.first == 1,
    'native binding did not synchronously own published bytes',
  );

  final Uint8List nativeCommand = Uint8List.fromList(<int>[4, 5, 6]);
  bindings
    ..takeStatus = 0
    ..nextCommand = nativeCommand;
  final Uint8List command = session.takeCommand()!;
  command[0] = 9;
  _expect(
    nativeCommand.first == 4 && session.takeCommand() == null,
    'command bytes were not copied or empty queue was not typed',
  );
  session.completeCommand(
    41,
    TerminalAppleScriptMacosCommandDisposition.completed,
    objectId: 'terminal:9',
  );
  _expect(
    bindings.completedOperation == 41 &&
        bindings.completedDisposition == 0 &&
        bindings.completedObjectId == 'terminal:9',
    'typed completion was not projected to native bindings',
  );
  final TerminalAppleScriptMacosSummary summary = session.summary;
  _expect(
    summary.generation == 7 &&
        summary.windowCount == 1 &&
        summary.started &&
        summary.enabled,
    'native lifecycle summary was not retained',
  );

  _expectThrows<ArgumentError>(
    () => session.publishSnapshot(Uint8List(0)),
    'empty snapshot',
  );
  _expectThrows<RangeError>(
    () => session.completeCommand(
      0,
      TerminalAppleScriptMacosCommandDisposition.failed,
    ),
    'zero operation ID',
  );
  _expectThrows<ArgumentError>(
    () => session.completeCommand(
      1,
      TerminalAppleScriptMacosCommandDisposition.completed,
      objectId: 'terminal:é',
    ),
    'non-ASCII object ID',
  );
  session.dispose();
  session.dispose();
  _expect(
    session.isDisposed && bindings.shutdownCount == 1,
    'session disposal was not idempotent',
  );
  _expectThrows<StateError>(session.takeCommand, 'take after dispose');

  for (final ({int maximum, Duration timeout}) invalid
      in <({int maximum, Duration timeout})>[
        (maximum: 0, timeout: const Duration(seconds: 1)),
        (maximum: 17, timeout: const Duration(seconds: 1)),
        (maximum: 1, timeout: Duration.zero),
        (maximum: 1, timeout: const Duration(minutes: 6)),
      ]) {
    _expectThrows<ArgumentError>(
      () => TerminalAppleScriptMacosSession.withBindings(
        _FakeBindings(),
        maximumPendingCommands: invalid.maximum,
        commandTimeout: invalid.timeout,
      ),
      'invalid session bounds',
    );
  }
}

void _testTypedNativeFailures() {
  final _FakeBindings startFailure = _FakeBindings()..startStatus = 8;
  final TerminalAppleScriptMacosException start =
      _expectThrows<TerminalAppleScriptMacosException>(
        () => TerminalAppleScriptMacosSession.withBindings(startFailure),
        'native start failure',
      );
  _expect(
    start.operation == 'sessionStart' && start.status == 8,
    'native start failure lost operation or status',
  );

  final _FakeBindings bindings = _FakeBindings();
  final TerminalAppleScriptMacosSession session =
      TerminalAppleScriptMacosSession.withBindings(bindings);
  bindings.publishStatus = 1;
  final TerminalAppleScriptMacosException publish =
      _expectThrows<TerminalAppleScriptMacosException>(
        () => session.publishSnapshot(Uint8List.fromList(<int>[1])),
        'native publish failure',
      );
  _expect(
    publish.operation == 'publishSnapshot' && publish.status == 1,
    'native publish failure lost operation or status',
  );
  bindings
    ..publishStatus = 0
    ..takeStatus = 10;
  _expectThrows<TerminalAppleScriptMacosException>(
    session.takeCommand,
    'native command poll failure',
  );
  bindings.takeStatus = 0;
  bindings.returnEmptySuccess = true;
  _expectThrows<TerminalAppleScriptMacosException>(
    session.takeCommand,
    'successful poll without bytes',
  );
  bindings
    ..returnEmptySuccess = false
    ..takeStatus = 5
    ..completeStatus = 5;
  _expectThrows<TerminalAppleScriptMacosException>(
    () => session.completeCommand(
      1,
      TerminalAppleScriptMacosCommandDisposition.notFound,
    ),
    'native completion failure',
  );
  bindings.completeStatus = 0;
  session.dispose();
}

final class _FakeBindings implements TerminalAppleScriptMacosBindings {
  int startStatus = 0;
  int publishStatus = 0;
  int takeStatus = 5;
  int completeStatus = 0;
  int shutdownStatus = 0;
  int? startedMaximum;
  int? startedTimeoutMicros;
  Uint8List? snapshot;
  Uint8List? nextCommand;
  bool returnEmptySuccess = false;
  int? completedOperation;
  int? completedDisposition;
  String? completedObjectId;
  int shutdownCount = 0;

  @override
  int sessionStart(int maximumPendingCommands, int timeoutMicros) {
    startedMaximum = maximumPendingCommands;
    startedTimeoutMicros = timeoutMicros;
    return startStatus;
  }

  @override
  int publishSnapshot(Uint8List bytes) {
    snapshot = Uint8List.fromList(bytes);
    return publishStatus;
  }

  @override
  TerminalAppleScriptMacosTakeResult takeCommand() {
    if (takeStatus != 0) return TerminalAppleScriptMacosTakeResult(takeStatus);
    final Uint8List? bytes = nextCommand;
    nextCommand = null;
    if (bytes == null && !returnEmptySuccess) {
      return const TerminalAppleScriptMacosTakeResult(5);
    }
    return TerminalAppleScriptMacosTakeResult(takeStatus, bytes);
  }

  @override
  int completeCommand(int operationId, int disposition, String? objectId) {
    completedOperation = operationId;
    completedDisposition = disposition;
    completedObjectId = objectId;
    return completeStatus;
  }

  @override
  int sessionShutdown() {
    shutdownCount++;
    return shutdownStatus;
  }

  @override
  TerminalAppleScriptMacosSummary summary() =>
      const TerminalAppleScriptMacosSummary(
        generation: 7,
        windowCount: 1,
        tabCount: 2,
        terminalCount: 3,
        queuedCommandCount: 0,
        pendingCommandCount: 0,
        resumedCommandCount: 4,
        rejectedCommandCount: 5,
        started: true,
        enabled: true,
      );
}

T _expectThrows<T extends Object>(void Function() action, String description) {
  try {
    action();
  } on T catch (error) {
    return error;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('AppleScript package test: $description');
}
