import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runMetalFailureRecoveryTests();

void runMetalFailureRecoveryTests() {
  _testPreparationFailureRetriesWithoutRetiringCurrent();
  _testActivationFailureLeavesNoPartialPublishedDomain();
  _testRepeatedFailureExhaustsOneBoundedRequest();
  _testRendererGenerationMustAdvanceStrictly();
}

void _testPreparationFailureRetriesWithoutRetiringCurrent() {
  final _FakeRecoveryDomain initial = _FakeRecoveryDomain(
    generation: 1,
    failure: TerminalMetalFailureKind.commandExecution,
    pinCount: 2,
    activated: true,
  );
  final _FakeRecoveryDomain replacement = _FakeRecoveryDomain(generation: 2);
  var preparationCount = 0;
  var fullDamageCount = 0;
  var fullRedrawCount = 0;
  final TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>
  coordinator = TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>(
    initialDomain: initial,
    prepareReplacement: () {
      preparationCount++;
      if (preparationCount == 1) {
        throw const TerminalMetalRecoveryException(
          operation: 'injected create',
          failure: TerminalMetalFailureKind.deviceUnavailable,
        );
      }
      return replacement;
    },
    requestFullDamage: () => fullDamageCount++,
    requestFullRedraw: () => fullRedrawCount++,
  );
  _expect(
    coordinator.observeCurrentFailure() &&
        !coordinator.requestRecovery(
          TerminalMetalFailureKind.commandExecution,
        ) &&
        coordinator.pendingRecoveryCount == 1,
    'native observation and duplicate request retain one recovery marker',
  );

  final TerminalMetalRecoveryResult failed = coordinator.processNewest();
  _expect(
    failed.disposition == TerminalMetalRecoveryDisposition.retryableFailure &&
        failed.attempt == 1 &&
        failed.failure == TerminalMetalFailureKind.deviceUnavailable &&
        identical(coordinator.currentDomain, initial) &&
        initial.abandonCount == 0 &&
        coordinator.pendingRecoveryCount == 1 &&
        fullDamageCount == 0 &&
        fullRedrawCount == 0,
    'preparation failure preserves the old domain and emits no redraw',
  );

  final TerminalMetalRecoveryResult recovered = coordinator.processNewest();
  _expect(
    recovered.isRecovered &&
        recovered.attempt == 2 &&
        recovered.rendererGeneration == 2 &&
        recovered.abandonedPinCount == 2 &&
        initial.abandonCount == 1 &&
        initial.pinCount == 0 &&
        replacement.activateCount == 1 &&
        identical(coordinator.currentDomain, replacement) &&
        coordinator.pendingRecoveryCount == 0 &&
        coordinator.recoveryCount == 1 &&
        coordinator.totalAttemptCount == 2 &&
        fullDamageCount == 1 &&
        fullRedrawCount == 1,
    'successful retry atomically swaps ownership and requests one full frame',
  );
  _expect(
    coordinator.processNewest().disposition ==
            TerminalMetalRecoveryDisposition.idle &&
        fullDamageCount == 1 &&
        fullRedrawCount == 1,
    'idle processing cannot duplicate recovery redraw work',
  );
  coordinator.dispose();
  coordinator.dispose();
  _expect(
    replacement.abandonCount == 1 && coordinator.isDisposed,
    'coordinator shutdown abandons the replacement exactly once',
  );
}

void _testActivationFailureLeavesNoPartialPublishedDomain() {
  final _FakeRecoveryDomain initial = _FakeRecoveryDomain(
    generation: 10,
    failure: TerminalMetalFailureKind.deviceLost,
    pinCount: 3,
    activated: true,
  );
  final _FakeRecoveryDomain rejected = _FakeRecoveryDomain(
    generation: 11,
    activationFailure: const TerminalMetalRecoveryException(
      operation: 'injected bind',
      failure: TerminalMetalFailureKind.resourceAllocation,
    ),
  );
  final _FakeRecoveryDomain accepted = _FakeRecoveryDomain(generation: 12);
  var preparationCount = 0;
  var fullRequestCount = 0;
  final TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>
  coordinator = TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>(
    initialDomain: initial,
    prepareReplacement: () => preparationCount++ == 0 ? rejected : accepted,
    requestFullDamage: () => fullRequestCount++,
    requestFullRedraw: () => fullRequestCount++,
  );
  coordinator.requestRecovery(TerminalMetalFailureKind.deviceLost);
  final TerminalMetalRecoveryResult failed = coordinator.processNewest();
  _expect(
    failed.disposition == TerminalMetalRecoveryDisposition.retryableFailure &&
        failed.abandonedPinCount == 3 &&
        initial.abandonCount == 1 &&
        rejected.activateCount == 1 &&
        rejected.abandonCount == 1 &&
        !coordinator.hasCurrentDomain &&
        coordinator.rendererGenerationFloor == 11 &&
        coordinator.pendingRecoveryCount == 1 &&
        fullRequestCount == 0,
    'failed bind publishes neither old nor incomplete replacement domain',
  );
  final TerminalMetalRecoveryResult recovered = coordinator.processNewest();
  _expect(
    recovered.isRecovered &&
        recovered.rendererGeneration == 12 &&
        recovered.abandonedPinCount == 0 &&
        identical(coordinator.currentDomain, accepted) &&
        fullRequestCount == 2,
    'retry after bind failure accepts only a newer complete domain',
  );
  coordinator.dispose();
}

void _testRepeatedFailureExhaustsOneBoundedRequest() {
  final _FakeRecoveryDomain initial = _FakeRecoveryDomain(
    generation: 20,
    failure: TerminalMetalFailureKind.commandExecution,
    activated: true,
  );
  var preparationCount = 0;
  final TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>
  coordinator = TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>(
    initialDomain: initial,
    maximumAttempts: 2,
    prepareReplacement: () {
      preparationCount++;
      throw const TerminalMetalRecoveryException(
        operation: 'injected create',
        failure: TerminalMetalFailureKind.shaderLibrary,
      );
    },
    requestFullDamage: () => throw StateError('unexpected full damage'),
    requestFullRedraw: () => throw StateError('unexpected full redraw'),
  );
  coordinator.requestRecovery(TerminalMetalFailureKind.commandExecution);
  final TerminalMetalRecoveryResult first = coordinator.processNewest();
  final TerminalMetalRecoveryResult second = coordinator.processNewest();
  _expect(
    first.disposition == TerminalMetalRecoveryDisposition.retryableFailure &&
        second.disposition == TerminalMetalRecoveryDisposition.exhausted &&
        second.attempt == 2 &&
        second.failure == TerminalMetalFailureKind.shaderLibrary &&
        preparationCount == 2 &&
        coordinator.pendingRecoveryCount == 0 &&
        coordinator.isExhausted &&
        !coordinator.requestRecovery(TerminalMetalFailureKind.deviceLost) &&
        initial.abandonCount == 0,
    'repeated preparation failure stops at the fixed attempt budget',
  );
  coordinator.dispose();
}

void _testRendererGenerationMustAdvanceStrictly() {
  final _FakeRecoveryDomain initial = _FakeRecoveryDomain(
    generation: 30,
    failure: TerminalMetalFailureKind.commandExecution,
    activated: true,
  );
  final _FakeRecoveryDomain stale = _FakeRecoveryDomain(generation: 30);
  final TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>
  coordinator = TerminalMetalFailureRecoveryCoordinator<_FakeRecoveryDomain>(
    initialDomain: initial,
    prepareReplacement: () => stale,
    requestFullDamage: () {},
    requestFullRedraw: () {},
  );
  coordinator.requestRecovery(TerminalMetalFailureKind.commandExecution);
  _expectState(
    coordinator.processNewest,
    'same-generation replacement is a product invariant violation',
  );
  _expect(
    stale.abandonCount == 1 &&
        initial.abandonCount == 0 &&
        identical(coordinator.currentDomain, initial),
    'invalid candidate is discarded before current ownership changes',
  );
  coordinator.dispose();
}

final class _FakeRecoveryDomain implements TerminalMetalRecoveryDomain {
  _FakeRecoveryDomain({
    required int generation,
    this.failure = TerminalMetalFailureKind.none,
    this.pinCount = 0,
    this.activated = false,
    this.activationFailure,
  }) : rendererGeneration = generation;

  @override
  final int rendererGeneration;
  @override
  TerminalMetalFailureKind failure;
  int pinCount;
  bool activated;
  final Object? activationFailure;
  int activateCount = 0;
  int abandonCount = 0;

  @override
  bool get isFaulted => failure != TerminalMetalFailureKind.none;

  @override
  bool get isAbandoned => abandonCount != 0;

  @override
  void activate() {
    activateCount++;
    final Object? error = activationFailure;
    if (error != null) throw error;
    activated = true;
  }

  @override
  int abandon() {
    if (isAbandoned) return 0;
    abandonCount++;
    activated = false;
    final int released = pinCount;
    pinCount = 0;
    return released;
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Metal failure recovery test failed: $description');
  }
}

void _expectState(void Function() action, String description) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('Metal failure recovery test failed: $description');
}
