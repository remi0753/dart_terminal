import 'dart:ffi';

import 'package:dart_terminal_app_intents_macos/dart_terminal_app_intents_macos.dart';
import 'package:dart_terminal_app_intents_macos/testing.dart';

import 'metadata_test.dart';

Future<void> main(List<String> arguments) async {
  _testConstantsAndValidation();
  _testTypedSessionLifecycle();
  _testNativeFailureProjection();
  _testSelfAutomationBoundary();
  if (arguments.isNotEmpty) {
    _testFfiSymbolAndThreadBoundary(arguments.single);
  }
  await runMetadataTest();
}

void _testFfiSymbolAndThreadBoundary(String libraryPath) {
  final FfiTerminalAppIntentsMacosBindings bindings =
      FfiTerminalAppIntentsMacosBindings(DynamicLibrary.open(libraryPath));
  _expect(
    bindings.sessionStart(1, 1000000) == 7 &&
        bindings.setEnabled(true) == 7 &&
        bindings.takeCommand().status == 7 &&
        bindings.completeCommand(1, 1, 0) == 7 &&
        bindings.sessionShutdown() == 7 &&
        bindings.debugEnqueueAction(1) == 3,
    'standalone Dart FFI did not preserve native thread/session statuses',
  );
  final TerminalAppIntentsMacosException summary =
      _expectThrows<TerminalAppIntentsMacosException>(
        bindings.summary,
        'standalone summary thread boundary',
      );
  _expect(
    summary.operation == 'summary' && summary.status == 7,
    'FFI summary lost native wrong-thread status',
  );
}

void _testConstantsAndValidation() {
  _expect(
    terminalAppIntentsMacosLibraryName ==
            'libdart_terminal_app_intents_macos.dylib' &&
        terminalAppIntentsMacosModuleName == 'DartTerminalAppIntents' &&
        terminalAppIntentsMacosSource == 'native/TerminalAppIntents.swift' &&
        TerminalAppIntentAction.values
                .map((value) => value.nativeValue)
                .join(',') ==
            '1,2,3',
    'public packaging and action constants are not exact',
  );
  for (final ({int maximum, Duration timeout}) invalid
      in <({int maximum, Duration timeout})>[
        (maximum: 0, timeout: const Duration(seconds: 1)),
        (maximum: 17, timeout: const Duration(seconds: 1)),
        (maximum: 1, timeout: Duration.zero),
        (maximum: 1, timeout: const Duration(minutes: 6)),
      ]) {
    _expectThrows<ArgumentError>(
      () => TerminalAppIntentsMacosSession.withBindings(
        _FakeBindings(),
        maximumPendingCommands: invalid.maximum,
        commandTimeout: invalid.timeout,
      ),
      'invalid session bounds',
    );
  }
}

void _testTypedSessionLifecycle() {
  final _FakeBindings bindings = _FakeBindings();
  final TerminalAppIntentsMacosSession session =
      TerminalAppIntentsMacosSession.withBindings(
        bindings,
        maximumPendingCommands: 4,
        commandTimeout: const Duration(seconds: 7),
      );
  _expect(
    bindings.startedMaximum == 4 &&
        bindings.startedTimeoutMicros == 7000000 &&
        !session.isDisposed,
    'typed start bounds were not projected to native',
  );
  session.setEnabled(true);
  _expect(bindings.enabled == true, 'enabled state was not projected');

  bindings.nextCommand = const TerminalAppIntentsMacosTakeResult(
    0,
    operationId: 41,
    generation: 7,
    action: 2,
  );
  final TerminalAppIntentsMacosCommand command = session.takeCommand()!;
  _expect(
    command.operationId == 41 &&
        command.generation == 7 &&
        command.action == TerminalAppIntentAction.newTab &&
        session.takeCommand() == null,
    'typed command or empty queue result was not retained',
  );
  session.completeCommand(
    command,
    TerminalAppIntentsMacosCommandDisposition.completed,
  );
  _expect(
    bindings.completedOperation == 41 &&
        bindings.completedGeneration == 7 &&
        bindings.completedDisposition == 0,
    'opaque command completion was not projected exactly',
  );
  final TerminalAppIntentsMacosSummary summary = session.summary;
  _expect(
    summary.generation == 7 &&
        summary.acceptedCommandCount == 4 &&
        summary.resolvedCommandCount == 3 &&
        summary.started &&
        summary.enabled,
    'bounded summary was not retained',
  );

  session.dispose();
  session.dispose();
  _expect(
    session.isDisposed && bindings.shutdownCount == 1,
    'session shutdown was not idempotent',
  );
  _expectThrows<StateError>(session.takeCommand, 'take after disposal');
  _expectThrows<StateError>(
    () => session.setEnabled(false),
    'configuration after disposal',
  );
}

void _testNativeFailureProjection() {
  final _FakeBindings startFailure = _FakeBindings()..startStatus = 7;
  final TerminalAppIntentsMacosException start =
      _expectThrows<TerminalAppIntentsMacosException>(
        () => TerminalAppIntentsMacosSession.withBindings(startFailure),
        'native start failure',
      );
  _expect(
    start.operation == 'sessionStart' && start.status == 7,
    'start failure lost native status',
  );

  final _FakeBindings bindings = _FakeBindings();
  final TerminalAppIntentsMacosSession session =
      TerminalAppIntentsMacosSession.withBindings(bindings);
  bindings.setEnabledStatus = 8;
  _expectThrows<TerminalAppIntentsMacosException>(
    () => session.setEnabled(true),
    'native enable failure',
  );
  bindings
    ..setEnabledStatus = 0
    ..nextCommand = const TerminalAppIntentsMacosTakeResult(
      0,
      operationId: 1,
      generation: 2,
      action: 99,
    );
  final TerminalAppIntentsMacosException malformed =
      _expectThrows<TerminalAppIntentsMacosException>(
        session.takeCommand,
        'unknown native action',
      );
  _expect(
    malformed.operation == 'takeCommand.result' &&
        malformed.status == nativeStatusInternal,
    'malformed native output did not fail closed',
  );
  bindings.nextCommand = const TerminalAppIntentsMacosTakeResult(10);
  _expectThrows<TerminalAppIntentsMacosException>(
    session.takeCommand,
    'native poll failure',
  );
  bindings
    ..nextCommand = const TerminalAppIntentsMacosTakeResult(
      0,
      operationId: 9,
      generation: 2,
      action: 1,
    )
    ..completeStatus = 9;
  final TerminalAppIntentsMacosCommand stale = session.takeCommand()!;
  _expectThrows<TerminalAppIntentsMacosException>(
    () => session.completeCommand(
      stale,
      TerminalAppIntentsMacosCommandDisposition.failed,
    ),
    'stale completion failure',
  );
  bindings
    ..completeStatus = 0
    ..shutdownStatus = 7;
  _expectThrows<TerminalAppIntentsMacosException>(
    session.dispose,
    'native shutdown failure',
  );
  _expect(!session.isDisposed, 'failed shutdown must remain retryable');
  bindings.shutdownStatus = 0;
  session.dispose();
}

void _testSelfAutomationBoundary() {
  final _FakeBindings bindings = _FakeBindings();
  final TerminalAppIntentsMacosSelfAutomation automation =
      TerminalAppIntentsMacosSelfAutomation.withBindings(bindings);
  automation.enqueue(TerminalAppIntentAction.toggleQuickTerminal);
  _expect(bindings.debugAction == 3, 'typed self-automation action');
  bindings.debugStatus = 6;
  final TerminalAppIntentsMacosException failure =
      _expectThrows<TerminalAppIntentsMacosException>(
        () => automation.enqueue(TerminalAppIntentAction.newWindow),
        'self-automation capacity failure',
      );
  _expect(
    failure.operation == 'debugEnqueueAction' && failure.status == 6,
    'self-automation failure lost status',
  );
}

final class _FakeBindings implements TerminalAppIntentsMacosBindings {
  int startStatus = 0;
  int setEnabledStatus = 0;
  int completeStatus = 0;
  int shutdownStatus = 0;
  int debugStatus = 0;
  int? startedMaximum;
  int? startedTimeoutMicros;
  bool? enabled;
  TerminalAppIntentsMacosTakeResult? nextCommand;
  int? completedOperation;
  int? completedGeneration;
  int? completedDisposition;
  int? debugAction;
  int shutdownCount = 0;

  @override
  int sessionStart(int maximumPendingCommands, int timeoutMicros) {
    startedMaximum = maximumPendingCommands;
    startedTimeoutMicros = timeoutMicros;
    return startStatus;
  }

  @override
  int setEnabled(bool enabled) {
    this.enabled = enabled;
    return setEnabledStatus;
  }

  @override
  TerminalAppIntentsMacosTakeResult takeCommand() {
    final TerminalAppIntentsMacosTakeResult result =
        nextCommand ??
        const TerminalAppIntentsMacosTakeResult(nativeStatusNotFound);
    nextCommand = null;
    return result;
  }

  @override
  int completeCommand(int operationId, int generation, int disposition) {
    completedOperation = operationId;
    completedGeneration = generation;
    completedDisposition = disposition;
    return completeStatus;
  }

  @override
  int sessionShutdown() {
    shutdownCount += 1;
    return shutdownStatus;
  }

  @override
  TerminalAppIntentsMacosSummary summary() =>
      const TerminalAppIntentsMacosSummary(
        generation: 7,
        queuedCommandCount: 1,
        pendingCommandCount: 1,
        acceptedCommandCount: 4,
        resolvedCommandCount: 3,
        rejectedCommandCount: 2,
        timedOutCommandCount: 1,
        started: true,
        enabled: true,
      );

  @override
  int debugEnqueueAction(int action) {
    debugAction = action;
    return debugStatus;
  }
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
  if (!condition) throw StateError('App Intents package test: $description');
}
