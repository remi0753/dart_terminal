import 'package:dart_terminal/dart_terminal.dart';

void main() => runFrameSchedulerTests();

void runFrameSchedulerTests() {
  _testExactFrameTimingMetrics();
  _testAppliedDamageCoalescesToNewestModel();
  _testBackpressureRetainsOneMarkerAndRebuilds();
  _testPreparedWorkSupersededDuringBuild();
  _testAppliedRevisionStressHasNoFrameQueue();
  _testSynchronizedPresentationGate();
  _testSynchronizedOutputBlocksBuildAndRetainsNewest();
  _testBoundedCursorAndBellClock();
  _testKittyAnimationUsesNewestOnlySchedulerClock();
  _testVisibilityOcclusionPauseAndResume();
  _testOcclusionDuringBuildSupersedesBeforeSubmit();
  _testPresentationRevisionExhaustionDoesNotWrap();
  _testFrameGenerationExhaustionDoesNotWrap();
}

void _testKittyAnimationUsesNewestOnlySchedulerClock() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final _FakeAnimationDriver animation = _FakeAnimationDriver();
  var submissionCount = 0;
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        animationDriver: animation,
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0, presentation),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) {
              submissionCount++;
              if (submissionCount == 2) {
                return TerminalFrameSubmissionOutcome.backpressured;
              }
              return TerminalFrameSubmissionOutcome.accepted(
                frameGeneration: frameGeneration,
                submissionToken: frameGeneration,
              );
            },
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().isAccepted &&
        !scheduler.advancePresentation(monotonicMicros: 0) &&
        animation.advanceTimes.length == 1 &&
        scheduler.nextPresentationDeadlineMicros == 10,
    'the auxiliary animation anchors one deadline in the ordinary scheduler',
  );
  _expect(
    !scheduler.advancePresentation(monotonicMicros: 9) &&
        scheduler.advancePresentation(monotonicMicros: 10) &&
        scheduler.pendingFrameCount == 1 &&
        scheduler.nextPresentationDeadlineMicros == 20 &&
        scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.backpressured,
    'an exact animation tick retains one newest marker through backpressure',
  );
  _expect(
    scheduler.advancePresentation(monotonicMicros: 100) &&
        scheduler.pendingFrameCount == 1 &&
        animation.changeCount == 2 &&
        scheduler.nextPresentationDeadlineMicros == 110 &&
        scheduler.submitNewest().isAccepted &&
        scheduler.pendingFrameCount == 0,
    'a late tick advances once and replaces rather than queues missed frames',
  );

  final int beforePauseAdvances = animation.advanceTimes.length;
  _expect(
    scheduler.updateWindowState(isOccluded: true, monotonicMicros: 101) &&
        animation.pauseCount == 1 &&
        scheduler.nextPresentationDeadlineMicros == null &&
        !scheduler.advancePresentation(monotonicMicros: 500) &&
        animation.advanceTimes.length == beforePauseAdvances,
    'occlusion clears the animation deadline and performs no hidden tick',
  );
  _expect(
    scheduler.updateWindowState(isOccluded: false, monotonicMicros: 501) &&
        !scheduler.advancePresentation(monotonicMicros: 501) &&
        animation.nextDeadlineMicros == 511 &&
        scheduler.updateSynchronizedOutput(isHeld: true) &&
        animation.pauseCount == 2 &&
        scheduler.nextPresentationDeadlineMicros == null &&
        scheduler.updateSynchronizedOutput(isHeld: false) &&
        !scheduler.advancePresentation(monotonicMicros: 900) &&
        animation.nextDeadlineMicros == 910,
    'resume and synchronized release reanchor from now without replaying time',
  );
  scheduler.pauseAnimation();
  _expect(
    animation.pauseCount == 3 && animation.nextDeadlineMicros == null,
    'explicit recovery or disposal cleanup leaves no animation deadline',
  );
}

void _testSynchronizedOutputBlocksBuildAndRetainsNewest() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final List<int> builtRevisions = <int>[];
  var backpressureNext = false;
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        buildFrame:
            (
              TerminalDamageRenderModel model, {
              required int modelRevision,
              required int frameGeneration,
              required TerminalFramePresentation presentation,
            }) {
              builtRevisions.add(modelRevision);
              return _FakeFrame(
                modelRevision,
                frameGeneration,
                model.contentAt(0, 0),
                presentation,
              );
            },
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) {
              if (backpressureNext) {
                backpressureNext = false;
                return TerminalFrameSubmissionOutcome.backpressured;
              }
              return TerminalFrameSubmissionOutcome.accepted(
                frameGeneration: frameGeneration,
                submissionToken: frameGeneration,
              );
            },
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().isAccepted &&
        scheduler.updateSynchronizedOutput(isHeld: true) &&
        scheduler.isSynchronizedOutputHeld,
    'an accepted baseline is frozen by the synchronized-output guard',
  );
  for (int revision = 2; revision <= 1025; revision++) {
    scheduler.applyDamage(
      sequence.mutateAndCapture(0, 0, revision.isEven ? 0x41 : 0x42),
      availableResourceGeneration: 1,
      monotonicMicros: revision,
    );
    _expect(
      scheduler.submitNewest().disposition ==
              TerminalFrameAttemptDisposition.synchronized &&
          scheduler.pendingFrameCount == 1 &&
          builtRevisions.length == 1,
      'held revision $revision never builds or queues an intermediate frame',
    );
  }
  backpressureNext = true;
  _expect(
    scheduler.updateWindowState(isOccluded: true, monotonicMicros: 1026) &&
        scheduler.updateSynchronizedOutput(isHeld: false) &&
        !scheduler.isSynchronizedOutputHeld &&
        scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.paused &&
        scheduler.pendingFrameCount == 1 &&
        scheduler.updateWindowState(isOccluded: false, monotonicMicros: 1027) &&
        scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.backpressured &&
        scheduler.pendingFrameCount == 1 &&
        scheduler.submitNewest().isAccepted &&
        scheduler.pendingFrameCount == 0 &&
        builtRevisions.length == 3 &&
        builtRevisions.last == 1025,
    'occluded release remains pending, survives one native backpressure '
    'result, and accepts only newest',
  );
}

void _testSynchronizedPresentationGate() {
  _expectArgument(
    () => TerminalSynchronizedPresentationGate(holdDuration: Duration.zero),
    'zero synchronized-output duration is rejected',
  );
  final TerminalSynchronizedPresentationGate gate =
      TerminalSynchronizedPresentationGate(
        holdDuration: const Duration(microseconds: 1000),
      );
  _expect(
    gate.synchronize(enabled: false, modeGeneration: 1, monotonicMicros: 10) ==
        TerminalSynchronizedPresentationDisposition.unchanged,
    'initial reset mode leaves presentation open',
  );
  _expect(
    gate.synchronize(enabled: true, modeGeneration: 2, monotonicMicros: 20) ==
            TerminalSynchronizedPresentationDisposition.started &&
        gate.isHolding &&
        gate.nextDeadlineMicros == 1020 &&
        !gate.deadlineReached(monotonicMicros: 500),
    'begin owns one exact monotonic deadline',
  );
  _expect(
    gate.synchronize(enabled: true, modeGeneration: 3, monotonicMicros: 900) ==
            TerminalSynchronizedPresentationDisposition.restarted &&
        gate.nextDeadlineMicros == 1900 &&
        !gate.deadlineReached(monotonicMicros: 1020) &&
        gate.deadlineReached(monotonicMicros: 1900),
    'repeated begin replaces rather than stacks its deadline',
  );
  _expect(
    gate.synchronize(
              enabled: false,
              modeGeneration: 4,
              monotonicMicros: 1900,
            ) ==
            TerminalSynchronizedPresentationDisposition.released &&
        !gate.isHolding &&
        gate.nextDeadlineMicros == null,
    'reset releases the hold and clears its deadline',
  );
  _expectState(
    () => gate.synchronize(
      enabled: true,
      modeGeneration: 3,
      monotonicMicros: 1901,
    ),
    'mode generation regression is rejected',
  );
  _expectState(
    () => gate.deadlineReached(monotonicMicros: 1899),
    'monotonic time regression is rejected',
  );
}

void _testExactFrameTimingMetrics() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final _FakeTimingClock timingClock = _FakeTimingClock(<int>[
    10,
    13,
    20,
    25,
    30,
    37,
    40,
    51,
    60,
    62,
    70,
    83,
  ]);
  var submissions = 0;
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        timingClock: timingClock.read,
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0, presentation),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) {
              submissions++;
              return switch (submissions) {
                1 => TerminalFrameSubmissionOutcome.backpressured,
                2 => TerminalFrameSubmissionOutcome.stale(
                  nativeLastAcceptedFrameGeneration: 5,
                ),
                _ => TerminalFrameSubmissionOutcome.accepted(
                  frameGeneration: frameGeneration,
                  submissionToken: 9,
                ),
              };
            },
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.backpressured &&
        scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.stale &&
        scheduler.submitNewest().isAccepted,
    'timing fixture exercises all synchronous native outcomes',
  );
  final TerminalFrameSchedulerMetrics metrics = scheduler.metrics;
  _expect(
    metrics.buildCount == 3 &&
        metrics.buildTotalMicroseconds == 12 &&
        metrics.buildMaximumMicroseconds == 7 &&
        metrics.averageBuildMicroseconds == 4.0 &&
        metrics.submissionCount == 3 &&
        metrics.submissionTotalMicroseconds == 29 &&
        metrics.submissionMaximumMicroseconds == 13 &&
        metrics.acceptedCount == 1 &&
        metrics.staleCount == 1 &&
        metrics.backpressureCount == 1 &&
        metrics.supersededCount == 0 &&
        timingClock.readCount == 12,
    'fake monotonic time yields exact bounded count/total/maximum metrics',
  );
  _expect(
    scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.idle &&
        timingClock.readCount == 12,
    'idle scheduler polling creates no timing sample',
  );

  final _DamageSequence buildFailureSequence = _DamageSequence(
    rows: 1,
    columns: 1,
  );
  final TerminalNewestFrameScheduler<_FakeFrame> buildFailure =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        timingClock: _FakeTimingClock(<int>[100, 104]).read,
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => throw StateError('injected build failure'),
        submitFrame: (
          _FakeFrame frame, {
          required int modelRevision,
          required int frameGeneration,
        }) => throw StateError('unexpected submit'),
      );
  buildFailure.applyDamage(
    buildFailureSequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expectState(buildFailure.submitNewest, 'injected build failure is surfaced');
  _expect(
    buildFailure.metrics.buildCount == 1 &&
        buildFailure.metrics.buildTotalMicroseconds == 4 &&
        buildFailure.metrics.submissionCount == 0 &&
        buildFailure.pendingFrameCount == 1,
    'failed build time is counted while newest work remains pending',
  );

  final _DamageSequence submitFailureSequence = _DamageSequence(
    rows: 1,
    columns: 1,
  );
  final TerminalNewestFrameScheduler<_FakeFrame> submitFailure =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        timingClock: _FakeTimingClock(<int>[200, 202, 210, 216]).read,
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0),
        submitFrame: (
          _FakeFrame frame, {
          required int modelRevision,
          required int frameGeneration,
        }) => throw StateError('injected submit failure'),
      );
  submitFailure.applyDamage(
    submitFailureSequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expectState(
    submitFailure.submitNewest,
    'injected submission failure is surfaced',
  );
  _expect(
    submitFailure.metrics.buildCount == 1 &&
        submitFailure.metrics.buildTotalMicroseconds == 2 &&
        submitFailure.metrics.submissionCount == 1 &&
        submitFailure.metrics.submissionTotalMicroseconds == 6 &&
        submitFailure.pendingFrameCount == 1,
    'failed submit time is counted while newest work remains pending',
  );
}

void _testBoundedCursorAndBellClock() {
  _expectArgument(
    () => TerminalPresentationClock(cursorOnDuration: Duration.zero),
    'zero cursor duration is rejected',
  );
  _expectArgument(
    () => TerminalPresentationClock(
      visualBellDuration: const Duration(minutes: 2),
    ),
    'animation durations remain bounded',
  );
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 2);
  final List<_FakeFrame> built = <_FakeFrame>[];
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        presentationClock: TerminalPresentationClock(
          cursorOnDuration: const Duration(microseconds: 10),
          cursorOffDuration: const Duration(microseconds: 20),
          visualBellDuration: const Duration(microseconds: 5),
        ),
        buildFrame:
            (
              TerminalDamageRenderModel model, {
              required int modelRevision,
              required int frameGeneration,
              required TerminalFramePresentation presentation,
            }) {
              final _FakeFrame frame = _FakeFrame(
                modelRevision,
                frameGeneration,
                0,
                presentation,
              );
              built.add(frame);
              return frame;
            },
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: frameGeneration,
            ),
      );

  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  final TerminalFrameAttemptResult initial = scheduler.submitNewest();
  _expect(
    initial.isAccepted &&
        initial.requiresFullRedraw &&
        built.single.presentation!.cursorDrawn &&
        !built.single.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == 10,
    'initial full model starts one visible cursor phase and deadline',
  );
  _expect(
    !scheduler.advancePresentation(monotonicMicros: 9) &&
        scheduler.pendingFrameCount == 0,
    'early animation polling creates no frame',
  );
  _expect(
    scheduler.advancePresentation(monotonicMicros: 10) &&
        scheduler.pendingFrameCount == 1,
    'cursor deadline retains one presentation marker',
  );
  final TerminalFrameAttemptResult cursorOff = scheduler.submitNewest();
  _expect(
    cursorOff.isAccepted &&
        !cursorOff.requiresFullRedraw &&
        !built.last.presentation!.cursorDrawn &&
        scheduler.nextPresentationDeadlineMicros == 30,
    'cursor toggles once and schedules from a late-safe current epoch',
  );
  _expect(
    scheduler.advancePresentation(monotonicMicros: 100) &&
        scheduler.pendingFrameCount == 1,
    'many missed cursor intervals coalesce to one phase change',
  );
  scheduler.submitNewest();
  _expect(
    built.last.presentation!.cursorDrawn &&
        scheduler.nextPresentationDeadlineMicros == 110,
    'late cursor advance never replays missed ticks',
  );

  final TerminalDecodedDamage firstBell = sequence.mutatePresentation((
    TerminalScreen screen,
  ) {
    screen.setCursorPresentation(blinking: false);
    TerminalScreenParserSink(screen).execute(0x07);
  });
  scheduler.applyDamage(
    firstBell,
    availableResourceGeneration: 1,
    monotonicMicros: 101,
  );
  scheduler.submitNewest();
  _expect(
    built.last.presentation!.cursorDrawn &&
        built.last.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == 106,
    'parser BEL starts one bounded pulse and nonblinking cursor stays visible',
  );
  scheduler.applyDamage(
    sequence.mutatePresentation(
      (TerminalScreen screen) => TerminalScreenParserSink(screen).execute(0x07),
    ),
    availableResourceGeneration: 1,
    monotonicMicros: 104,
  );
  scheduler.submitNewest();
  _expect(
    built.last.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == 109,
    'repeated BEL restarts one pulse without adding a deadline queue',
  );
  _expect(
    !scheduler.advancePresentation(monotonicMicros: 108) &&
        scheduler.advancePresentation(monotonicMicros: 109) &&
        scheduler.pendingFrameCount == 1,
    'only the restarted bell expiry invalidates presentation',
  );
  scheduler.submitNewest();
  _expect(
    !built.last.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == null,
    'bell expiry produces one replacement frame and leaves no timer',
  );

  _expect(
    scheduler.updateReduceMotion(reduceMotion: true, monotonicMicros: 110),
    'enabling Reduce Motion changes presentation policy once',
  );
  scheduler.applyDamage(
    sequence.mutatePresentation(
      (TerminalScreen screen) => TerminalScreenParserSink(screen).execute(0x07),
    ),
    availableResourceGeneration: 1,
    monotonicMicros: 111,
  );
  scheduler.submitNewest();
  _expect(
    scheduler.presentationClock.reduceMotion &&
        scheduler.presentationClock.lastVisualBellGeneration == 3 &&
        !built.last.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == null,
    'Reduce Motion acknowledges BEL without a timed frame or deadline',
  );
  _expect(
    !scheduler.updateReduceMotion(reduceMotion: true, monotonicMicros: 112) &&
        scheduler.updateReduceMotion(reduceMotion: false, monotonicMicros: 113),
    'motion preference updates are deduplicated and re-enable future bells',
  );
  scheduler.submitNewest();
  scheduler.applyDamage(
    sequence.mutatePresentation(
      (TerminalScreen screen) => TerminalScreenParserSink(screen).execute(0x07),
    ),
    availableResourceGeneration: 1,
    monotonicMicros: 114,
  );
  scheduler.submitNewest();
  _expect(
    built.last.presentation!.visualBellActive &&
        scheduler.nextPresentationDeadlineMicros == 119,
    'disabling Reduce Motion affects only later BEL generations',
  );

  final _DamageSequence boundedSequence = _DamageSequence(rows: 1, columns: 1);
  final TerminalNewestFrameScheduler<_FakeFrame> boundedScheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        presentationClock: TerminalPresentationClock(
          cursorOnDuration: const Duration(microseconds: 10),
        ),
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0, presentation),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: frameGeneration,
            ),
      );
  boundedScheduler.applyDamage(
    boundedSequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0x7ffffffffffffffa,
  );
  _expect(
    boundedScheduler.nextPresentationDeadlineMicros == 0x7fffffffffffffff &&
        boundedScheduler.advancePresentation(
          monotonicMicros: 0x7fffffffffffffff,
        ) &&
        boundedScheduler.nextPresentationDeadlineMicros == null,
    'deadline saturation reaches the signed maximum without wrapping',
  );
}

void _testVisibilityOcclusionPauseAndResume() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 2);
  final List<_FakeFrame> built = <_FakeFrame>[];
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        presentationClock: TerminalPresentationClock(
          cursorOnDuration: const Duration(microseconds: 10),
          cursorOffDuration: const Duration(microseconds: 10),
        ),
        buildFrame:
            (
              TerminalDamageRenderModel model, {
              required int modelRevision,
              required int frameGeneration,
              required TerminalFramePresentation presentation,
            }) {
              final _FakeFrame frame = _FakeFrame(
                modelRevision,
                frameGeneration,
                0,
                presentation,
              );
              built.add(frame);
              return frame;
            },
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: frameGeneration,
            ),
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  scheduler.submitNewest();
  final int visibleBuilds = scheduler.buildCount;

  _expect(
    scheduler.updateWindowState(isOccluded: true, monotonicMicros: 1) &&
        !scheduler.isPresentationActive &&
        scheduler.nextPresentationDeadlineMicros == null,
    'occlusion pauses cursor and bell deadlines immediately',
  );
  scheduler.applyDamage(
    sequence.mutatePresentation(
      (TerminalScreen screen) => TerminalScreenParserSink(screen).execute(0x07),
    ),
    availableResourceGeneration: 1,
    monotonicMicros: 2,
  );
  _expect(
    !scheduler.advancePresentation(monotonicMicros: 100) &&
        scheduler.pendingFrameCount == 1,
    'hidden damage and animation retain only one newest marker',
  );
  final TerminalFrameAttemptResult paused = scheduler.submitNewest();
  _expect(
    paused.disposition == TerminalFrameAttemptDisposition.paused &&
        paused.frameGeneration == 0 &&
        scheduler.buildCount == visibleBuilds,
    'occluded submission builds nothing and consumes no frame generation',
  );

  _expect(
    scheduler.updateWindowState(isVisible: false, monotonicMicros: 101) &&
        scheduler.updateWindowState(isOccluded: false, monotonicMicros: 102) &&
        !scheduler.isPresentationActive,
    'visibility and occlusion must both permit presentation',
  );
  _expect(
    scheduler.updateWindowState(isVisible: true, monotonicMicros: 103) &&
        scheduler.isPresentationActive &&
        scheduler.pendingFrameCount == 1 &&
        scheduler.nextPresentationDeadlineMicros == 113,
    'resume starts a deterministic visible cursor epoch and one marker',
  );
  final TerminalFrameAttemptResult resumed = scheduler.submitNewest();
  _expect(
    resumed.isAccepted &&
        resumed.frameGeneration == 2 &&
        resumed.requiresFullRedraw &&
        built.last.presentation!.requiresFullRedraw &&
        built.last.presentation!.cursorDrawn &&
        !built.last.presentation!.visualBellActive,
    'resume submits current state as one full redraw without replaying bell',
  );
  _expect(
    !scheduler.updateWindowState(isVisible: true, monotonicMicros: 104) &&
        scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.idle &&
        scheduler.pendingFrameCount == 0,
    'duplicate visible state does not schedule another resume frame',
  );
}

void _testPresentationRevisionExhaustionDoesNotWrap() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        presentationClock: TerminalPresentationClock(
          initialRevision: 0x7ffffffffffffffe,
        ),
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0, presentation),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: 1,
            ),
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  scheduler.submitNewest();
  scheduler.updateWindowState(isOccluded: true, monotonicMicros: 1);
  _expect(
    scheduler.presentationClock.revision == 0x7fffffffffffffff &&
        !scheduler.isPresentationActive,
    'last signed presentation revision pauses without wrap',
  );
  _expectState(
    () => scheduler.updateWindowState(isOccluded: false, monotonicMicros: 2),
    'presentation revision exhaustion rejects resume before reuse',
  );
  _expect(
    scheduler.isWindowOccluded && !scheduler.isPresentationActive,
    'failed exhausted resume does not publish a partially visible state',
  );
}

void _testOcclusionDuringBuildSupersedesBeforeSubmit() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  late final TerminalNewestFrameScheduler<_FakeFrame> scheduler;
  var buildCount = 0;
  var submitCount = 0;
  scheduler = TerminalNewestFrameScheduler<_FakeFrame>(
    model: TerminalDamageRenderModel(),
    buildFrame:
        (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) {
          buildCount++;
          if (buildCount == 1) {
            scheduler.updateWindowState(isOccluded: true, monotonicMicros: 1);
          }
          return _FakeFrame(modelRevision, frameGeneration, 0, presentation);
        },
    submitFrame:
        (
          _FakeFrame frame, {
          required int modelRevision,
          required int frameGeneration,
        }) {
          submitCount++;
          return TerminalFrameSubmissionOutcome.accepted(
            frameGeneration: frameGeneration,
            submissionToken: frameGeneration,
          );
        },
  );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  final TerminalFrameAttemptResult superseded = scheduler.submitNewest();
  _expect(
    superseded.disposition == TerminalFrameAttemptDisposition.superseded &&
        submitCount == 0 &&
        scheduler.pendingFrameCount == 1 &&
        !scheduler.isPresentationActive,
    'occlusion observed during build discards work before native submission',
  );
  scheduler.updateWindowState(isOccluded: false, monotonicMicros: 2);
  final TerminalFrameAttemptResult resumed = scheduler.submitNewest();
  _expect(
    resumed.isAccepted &&
        resumed.frameGeneration == 2 &&
        resumed.requiresFullRedraw &&
        submitCount == 1,
    'post-supersession resume rebuilds one current full frame',
  );
}

void _testAppliedDamageCoalescesToNewestModel() {
  final _DamageSequence sequence = _DamageSequence(rows: 2, columns: 3);
  final TerminalDecodedDamage full = sequence.captureFull();
  final TerminalDecodedDamage second = sequence.mutateAndCapture(0, 0, 0x41);
  final TerminalDecodedDamage third = sequence.mutateAndCapture(1, 2, 0x42);
  final TerminalDecodedDamage fourth = sequence.mutateAndCapture(0, 1, 0x43);
  final TerminalDecodedDamage fifth = sequence.mutateAndCapture(1, 1, 0x44);
  final List<_FakeFrame> submitted = <_FakeFrame>[];
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, model.contentAt(1, 2)),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) {
              submitted.add(frame);
              return TerminalFrameSubmissionOutcome.accepted(
                frameGeneration: frameGeneration,
                submissionToken: 90 + frameGeneration,
              );
            },
      );

  for (final TerminalDecodedDamage damage in <TerminalDecodedDamage>[
    full,
    second,
    third,
  ]) {
    _expect(
      scheduler
          .applyDamage(
            damage,
            availableResourceGeneration: 1,
            monotonicMicros: 0,
          )
          .isApplied,
      'ordered damage ${damage.damageGeneration} applies',
    );
    _expect(
      scheduler.pendingFrameCount == 1 && scheduler.buildCount == 0,
      'applied revisions coalesce before frame construction',
    );
  }
  _expect(
    scheduler
            .applyDamage(
              fifth,
              availableResourceGeneration: 1,
              monotonicMicros: 0,
            )
            .disposition ==
        TerminalDamageApplyDisposition.needsFullSnapshot,
    'future unapplied delta is not promoted to a frame revision',
  );
  _expect(
    scheduler.newestModelRevision == 3 && scheduler.pendingFrameCount == 1,
    'failed future delta leaves the previous newest marker intact',
  );
  _expect(
    scheduler
            .applyDamage(
              fourth,
              availableResourceGeneration: 1,
              monotonicMicros: 0,
            )
            .isApplied &&
        scheduler
            .applyDamage(
              fifth,
              availableResourceGeneration: 1,
              monotonicMicros: 0,
            )
            .isApplied,
    'missing delta and retried future delta both apply in order',
  );

  final TerminalFrameAttemptResult result = scheduler.submitNewest();
  _expect(
    result.isAccepted &&
        result.modelRevision == 5 &&
        result.frameGeneration == 1 &&
        result.submissionToken == 91,
    'one accepted frame targets only the newest applied model',
  );
  _expect(
    submitted.length == 1 &&
        submitted.single.modelRevision == 5 &&
        submitted.single.sample == 0x42 &&
        scheduler.lastAcceptedModelRevision == 5 &&
        scheduler.lastAcceptedFrameGeneration == 1 &&
        scheduler.pendingFrameCount == 0,
    'coalesced submission advances model and frame watermarks once',
  );
  _expect(
    scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.idle &&
        scheduler.buildCount == 1 &&
        scheduler.acceptedCount == 1,
    'idle polling does not manufacture another frame',
  );
}

void _testBackpressureRetainsOneMarkerAndRebuilds() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 2);
  final TerminalDecodedDamage full = sequence.captureFull();
  final TerminalDecodedDamage delta = sequence.mutateAndCapture(0, 1, 0x58);
  final List<_FakeFrame> built = <_FakeFrame>[];
  var submissions = 0;
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        buildFrame:
            (
              TerminalDamageRenderModel model, {
              required int modelRevision,
              required int frameGeneration,
              required TerminalFramePresentation presentation,
            }) {
              final _FakeFrame frame = _FakeFrame(
                modelRevision,
                frameGeneration,
                model.contentAt(0, 1),
              );
              built.add(frame);
              return frame;
            },
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) {
              submissions++;
              if (submissions < 3) {
                return TerminalFrameSubmissionOutcome.backpressured;
              }
              return TerminalFrameSubmissionOutcome.accepted(
                frameGeneration: frameGeneration,
                submissionToken: 300,
              );
            },
      );
  scheduler.applyDamage(
    full,
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.backpressured &&
        scheduler.pendingFrameCount == 1,
    'first backpressure retains one model marker',
  );
  scheduler.applyDamage(
    delta,
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().disposition ==
            TerminalFrameAttemptDisposition.backpressured &&
        scheduler.pendingFrameCount == 1,
    'newer model replaces the marker while native remains full',
  );
  final TerminalFrameAttemptResult accepted = scheduler.submitNewest();
  _expect(
    accepted.isAccepted && accepted.modelRevision == 2,
    'later slot signal submits the newest model',
  );
  _expect(
    built.length == 3 &&
        built[0].frameGeneration == 1 &&
        built[0].modelRevision == 1 &&
        built[1].frameGeneration == 2 &&
        built[1].modelRevision == 2 &&
        built[2].frameGeneration == 3 &&
        built[2].modelRevision == 2 &&
        !identical(built[0], built[1]) &&
        !identical(built[1], built[2]) &&
        scheduler.backpressureCount == 2 &&
        scheduler.acceptedCount == 1,
    'every retry rebuilds with a fresh generation and retains no packed queue',
  );
}

void _testPreparedWorkSupersededDuringBuild() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 2);
  final TerminalDecodedDamage full = sequence.captureFull();
  final TerminalDecodedDamage delta = sequence.mutateAndCapture(0, 0, 0x51);
  late final TerminalNewestFrameScheduler<_FakeFrame> scheduler;
  var buildCalls = 0;
  var submitCalls = 0;
  scheduler = TerminalNewestFrameScheduler<_FakeFrame>(
    model: TerminalDamageRenderModel(),
    buildFrame:
        (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) {
          buildCalls++;
          if (buildCalls == 1) {
            _expect(
              scheduler
                  .applyDamage(
                    delta,
                    availableResourceGeneration: 1,
                    monotonicMicros: 0,
                  )
                  .isApplied,
              'new damage can apply while older frame work is prepared',
            );
          }
          return _FakeFrame(
            modelRevision,
            frameGeneration,
            model.contentAt(0, 0),
          );
        },
    submitFrame:
        (
          _FakeFrame frame, {
          required int modelRevision,
          required int frameGeneration,
        }) {
          submitCalls++;
          return TerminalFrameSubmissionOutcome.accepted(
            frameGeneration: frameGeneration,
            submissionToken: frameGeneration,
          );
        },
  );
  scheduler.applyDamage(
    full,
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  final TerminalFrameAttemptResult superseded = scheduler.submitNewest();
  _expect(
    superseded.disposition == TerminalFrameAttemptDisposition.superseded &&
        superseded.modelRevision == 1 &&
        submitCalls == 0 &&
        scheduler.pendingFrameCount == 1,
    'prepared stale work is discarded before native submission',
  );
  final TerminalFrameAttemptResult accepted = scheduler.submitNewest();
  _expect(
    accepted.isAccepted &&
        accepted.modelRevision == 2 &&
        accepted.frameGeneration == 2 &&
        submitCalls == 1 &&
        scheduler.supersededCount == 1,
    'replacement build submits the newer applied model exactly once',
  );
}

void _testAppliedRevisionStressHasNoFrameQueue() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final List<int> builtRevisions = <int>[];
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        buildFrame:
            (
              TerminalDamageRenderModel model, {
              required int modelRevision,
              required int frameGeneration,
              required TerminalFramePresentation presentation,
            }) {
              builtRevisions.add(modelRevision);
              return _FakeFrame(
                modelRevision,
                frameGeneration,
                model.contentAt(0, 0),
              );
            },
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: 1,
            ),
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  for (int revision = 2; revision <= 1025; revision++) {
    final TerminalDecodedDamage damage = sequence.mutateAndCapture(
      0,
      0,
      revision.isEven ? 0x41 : 0x42,
    );
    _expect(
      scheduler
              .applyDamage(
                damage,
                availableResourceGeneration: 1,
                monotonicMicros: 0,
              )
              .isApplied &&
          scheduler.pendingFrameCount == 1 &&
          scheduler.buildCount == 0,
      'applied stress revision $revision retains one marker',
    );
  }
  _expect(
    scheduler.submitNewest().isAccepted &&
        builtRevisions.length == 1 &&
        builtRevisions.single == 1025,
    '1,025 applied revisions generate only the newest frame',
  );
}

void _testFrameGenerationExhaustionDoesNotWrap() {
  final _DamageSequence sequence = _DamageSequence(rows: 1, columns: 1);
  final TerminalNewestFrameScheduler<_FakeFrame> scheduler =
      TerminalNewestFrameScheduler<_FakeFrame>(
        model: TerminalDamageRenderModel(),
        initialFrameGeneration: 0x7ffffffffffffffe,
        buildFrame: (
          TerminalDamageRenderModel model, {
          required int modelRevision,
          required int frameGeneration,
          required TerminalFramePresentation presentation,
        }) => _FakeFrame(modelRevision, frameGeneration, 0),
        submitFrame:
            (
              _FakeFrame frame, {
              required int modelRevision,
              required int frameGeneration,
            }) => TerminalFrameSubmissionOutcome.accepted(
              frameGeneration: frameGeneration,
              submissionToken: 1,
            ),
      );
  scheduler.applyDamage(
    sequence.captureFull(),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expect(
    scheduler.submitNewest().frameGeneration == 0x7fffffffffffffff,
    'last signed frame generation is accepted without wrap',
  );
  scheduler.applyDamage(
    sequence.mutateAndCapture(0, 0, 0x41),
    availableResourceGeneration: 1,
    monotonicMicros: 0,
  );
  _expectState(
    scheduler.submitNewest,
    'frame generation exhaustion fails before reuse',
  );
  _expect(
    scheduler.pendingFrameCount == 1,
    'generation exhaustion preserves the newest model marker for recovery',
  );
}

final class _DamageSequence {
  _DamageSequence({required int rows, required int columns})
    : screen = TerminalScreen(rows: rows, columns: columns);

  final TerminalScreen screen;
  int _generation = 0;

  TerminalDecodedDamage captureFull() {
    final TerminalDecodedDamage damage = _capture();
    if (!damage.isFullSnapshot) throw StateError('test expected full damage');
    screen.acknowledgeFullSnapshot();
    return damage;
  }

  TerminalDecodedDamage mutateAndCapture(int row, int column, int scalar) {
    screen.setNarrowCell(row, column, scalar);
    final TerminalDecodedDamage damage = _capture();
    if (damage.isFullSnapshot) {
      throw StateError('test expected incremental damage');
    }
    return damage;
  }

  TerminalDecodedDamage mutatePresentation(
    void Function(TerminalScreen screen) mutation,
  ) {
    mutation(screen);
    final TerminalDecodedDamage damage = _capture();
    if (damage.isFullSnapshot || damage.damagedCellCount != 0) {
      throw StateError('test expected metadata-only damage');
    }
    return damage;
  }

  TerminalDecodedDamage _capture() {
    _generation++;
    final TerminalDamagePacket? packet = TerminalDamageCodec.capture(
      screen,
      damageGeneration: _generation,
      requiredResourceGeneration: 1,
    );
    if (packet == null) throw StateError('test expected damage');
    return TerminalDamageCodec.decode(packet.copyBytes());
  }
}

final class _FakeFrame {
  const _FakeFrame(
    this.modelRevision,
    this.frameGeneration,
    this.sample, [
    this.presentation,
  ]);

  final int modelRevision;
  final int frameGeneration;
  final int sample;
  final TerminalFramePresentation? presentation;
}

final class _FakeTimingClock {
  _FakeTimingClock(this._values);

  final List<int> _values;
  int readCount = 0;

  int read() {
    if (readCount >= _values.length) {
      throw StateError('frame timing clock was read too often');
    }
    return _values[readCount++];
  }
}

final class _FakeAnimationDriver implements TerminalFrameAnimationDriver {
  int? _nextDeadlineMicros;
  int pauseCount = 0;
  int changeCount = 0;
  final List<int> advanceTimes = <int>[];

  @override
  int? get nextDeadlineMicros => _nextDeadlineMicros;

  @override
  TerminalFrameAnimationTick advance({required int monotonicMicros}) {
    advanceTimes.add(monotonicMicros);
    final int? deadline = _nextDeadlineMicros;
    final bool changed = deadline != null && monotonicMicros >= deadline;
    if (changed) changeCount++;
    if (deadline == null || changed) {
      _nextDeadlineMicros = monotonicMicros + 10;
    }
    return TerminalFrameAnimationTick(
      changed: changed,
      nextDeadlineMicros: _nextDeadlineMicros,
    );
  }

  @override
  void pause() {
    pauseCount++;
    _nextDeadlineMicros = null;
  }
}

void _expectArgument(void Function() action, String description) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('frame scheduler test failed: $description');
}

void _expectState(void Function() action, String description) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('frame scheduler test failed: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('frame scheduler test failed: $description');
  }
}
