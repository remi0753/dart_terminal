import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const bool _releaseAot = bool.fromEnvironment('dart.vm.product');
const int _roundCount = 21;
const int _warmupIterations = 50000;
const int _iterationsPerBatch = 50000;
const double _maximumRelativeOverhead = 0.05;
const double _maximumP95Nanoseconds = 2000000;

Future<void> main() async {
  if (!_releaseAot) {
    throw StateError('disabled Note input benchmark must run as Release AOT');
  }

  final int subsystemBaseline =
      TerminalNoteCompositionRoot.debugLiveSubsystemCount;
  var factoryCalls = 0;
  final TerminalNoteCompositionRoot disabled =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: const TerminalNoteFeatureConfiguration(
          notes: false,
          notesOnReturn: true,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        factory: (_) {
          factoryCalls++;
          throw StateError('disabled composition evaluated its factory');
        },
      );
  final _InputRouteHarness baseline = await _InputRouteHarness.start();
  final _InputRouteHarness disabledRoute = await _InputRouteHarness.start();
  try {
    baseline.routeBatch(_warmupIterations);
    disabledRoute.routeBatch(_warmupIterations);
    baseline.reset();
    disabledRoute.reset();

    final List<double> ratios = <double>[];
    final List<double> baselineNanoseconds = <double>[];
    final List<double> disabledNanoseconds = <double>[];
    for (var round = 0; round < _roundCount; round++) {
      late final int baselineElapsed;
      late final int disabledElapsed;
      if (round.isEven) {
        baselineElapsed = baseline.measureBatch(_iterationsPerBatch);
        disabledElapsed = disabledRoute.measureBatch(_iterationsPerBatch);
      } else {
        disabledElapsed = disabledRoute.measureBatch(_iterationsPerBatch);
        baselineElapsed = baseline.measureBatch(_iterationsPerBatch);
      }
      final double baselinePerEvent =
          baselineElapsed *
          1000000000 /
          (Stopwatch().frequency * _iterationsPerBatch);
      final double disabledPerEvent =
          disabledElapsed *
          1000000000 /
          (Stopwatch().frequency * _iterationsPerBatch);
      baselineNanoseconds.add(baselinePerEvent);
      disabledNanoseconds.add(disabledPerEvent);
      ratios.add(disabledPerEvent / baselinePerEvent);
    }

    final double medianRatio = _median(ratios);
    final double baselineP95 = _percentile(baselineNanoseconds, 95);
    final double disabledP95 = _percentile(disabledNanoseconds, 95);
    final int expectedEvents = _roundCount * _iterationsPerBatch;
    final bool integrityPassed =
        factoryCalls == 0 &&
        disabled.capability == TerminalNoteApplicationCapability.disabled &&
        !disabled.ownsRuntime &&
        TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
            subsystemBaseline &&
        baseline.writeCount == expectedEvents &&
        disabledRoute.writeCount == expectedEvents &&
        baseline.byteCount == disabledRoute.byteCount &&
        baseline.checksum == disabledRoute.checksum &&
        baseline.queueRejections == 0 &&
        disabledRoute.queueRejections == 0;
    final bool passed =
        integrityPassed &&
        baselineP95 < _maximumP95Nanoseconds &&
        disabledP95 < _maximumP95Nanoseconds &&
        medianRatio <= 1 + _maximumRelativeOverhead;
    stdout.writeln(
      'TERMINAL_NOTE_DISABLED_INPUT_${passed ? 'PASS' : 'FAIL'} '
      'rounds=$_roundCount events_per_route=$expectedEvents '
      'factory_calls=$factoryCalls '
      'baseline_p95_ns=${baselineP95.round()} '
      'disabled_p95_ns=${disabledP95.round()} '
      'median_ratio=${medianRatio.toStringAsFixed(6)} '
      'maximum_ratio=${(1 + _maximumRelativeOverhead).toStringAsFixed(2)} '
      'integrity=$integrityPassed',
    );
    if (!passed) exitCode = 1;
  } finally {
    await baseline.shutdown();
    await disabledRoute.shutdown();
    await disabled.shutdown();
  }
  if (TerminalNoteCompositionRoot.debugLiveSubsystemCount !=
      subsystemBaseline) {
    throw StateError('disabled Note benchmark leaked a subsystem owner');
  }
}

double _median(List<double> samples) => _percentile(samples, 50);

double _percentile(List<double> samples, int percentile) {
  final List<double> sorted = List<double>.of(samples)..sort();
  final int index = ((sorted.length * percentile + 99) ~/ 100) - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

final class _InputRouteHarness {
  _InputRouteHarness._({
    required this.owner,
    required this.pane,
    required this.session,
  });

  static Future<_InputRouteHarness> start() async {
    final TerminalPaneOwner owner = TerminalPaneOwner();
    late final _BenchmarkPaneSession session;
    final TerminalPane pane = owner.createPane(
      sessionFactory:
          (
            TerminalSessionId id, {
            required void Function() onChanged,
            required void Function() onTerminated,
          }) {
            session = _BenchmarkPaneSession(id);
            return session;
          },
      onChanged: () {},
      onExitRequested: () {},
    );
    await pane.start();
    return _InputRouteHarness._(owner: owner, pane: pane, session: session);
  }

  static const List<TerminalKeyEvent> _events = <TerminalKeyEvent>[
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyA,
      text: 'a',
      unmodifiedText: 'a',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyB,
      text: 'b',
      unmodifiedText: 'b',
      modifiers: TerminalKeyModifiers(option: true),
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.arrowUp,
      modifiers: TerminalKeyModifiers(function: true),
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyJ,
      text: '日',
      unmodifiedText: 'j',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.enter,
      text: '\r',
      unmodifiedText: '\r',
    ),
    TerminalKeyEvent(
      physicalKey: TerminalPhysicalKey.keyZ,
      text: 'Z',
      unmodifiedText: 'z',
      modifiers: TerminalKeyModifiers(shift: true),
    ),
  ];

  final TerminalPaneOwner owner;
  final TerminalPane pane;
  final _BenchmarkPaneSession session;
  final TerminalKeyEventRouter router = TerminalKeyEventRouter();

  int get writeCount => session.writeCount;
  int get byteCount => session.byteCount;
  int get checksum => session.checksum;
  int get queueRejections => session.queueRejections;

  void reset() => session.resetMeasurements();

  void routeBatch(int iterations) {
    for (var iteration = 0; iteration < iterations; iteration++) {
      final TerminalKeyRouteResult result = router.handleTerminalKeyEvent(
        _events[iteration % _events.length],
        pane,
      );
      if (result.disposition != TerminalKeyRouteDisposition.encoded ||
          result.encodedByteCount <= 0) {
        throw StateError('input benchmark did not write one key event');
      }
    }
  }

  int measureBatch(int iterations) {
    final Stopwatch clock = Stopwatch()..start();
    routeBatch(iterations);
    clock.stop();
    return clock.elapsedTicks;
  }

  Future<void> shutdown() => owner.shutdown();
}

final class _BenchmarkPaneSession implements TerminalPaneSession {
  _BenchmarkPaneSession(this.id);

  static const int _queueCapacityBytes = 64 * 1024;

  @override
  final TerminalSessionId id;
  var _live = false;
  var _queuedBytes = 0;
  var writeCount = 0;
  var byteCount = 0;
  var checksum = 0;
  var queueRejections = 0;

  void resetMeasurements() {
    _queuedBytes = 0;
    writeCount = 0;
    byteCount = 0;
    checksum = 0;
    queueRejections = 0;
  }

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() => _live
      ? TerminalPaneProcessSnapshot.available(
          sessionId: id,
          childProcessId: 1,
          owningProcessGroup: 1,
          foregroundProcessGroup: 1,
        )
      : TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => _live = true;
  @override
  String render() => '';
  @override
  void insertText(String value) {}
  @override
  void deleteBackward() {}
  @override
  void deleteForward() {}
  @override
  void moveLeft() {}
  @override
  void moveRight() {}
  @override
  void moveToStart() {}
  @override
  void moveToEnd() {}
  @override
  void previousHistory() {}
  @override
  void nextHistory() {}
  @override
  Future<void> submit() async {}
  @override
  void interrupt() {}
  @override
  void suspend() {}
  @override
  void quitForegroundProcess() {}
  @override
  void sendEndOfFile() {}
  @override
  void sendInput(Uint8List bytes) {
    if (_queuedBytes + bytes.length > _queueCapacityBytes) {
      queueRejections++;
      throw StateError('bounded input benchmark queue rejected a key');
    }
    _queuedBytes += bytes.length;
    writeCount++;
    byteCount += bytes.length;
    for (final int byte in bytes) {
      checksum = ((checksum * 16777619) ^ byte) & 0x7fffffff;
    }
    if (writeCount % 64 == 0) _queuedBytes = 0;
  }

  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async =>
      const TerminalPasteTransferResult(
        disposition: TerminalPasteTransferDisposition.completed,
        encodedBytes: 0,
        completedChunks: 0,
        backpressureCount: 0,
        maximumQueuedBytes: 0,
        concurrentInputRejections: 0,
      );
  @override
  void resize({required int rows, required int columns}) {}
  @override
  void showClipboardNotice(TerminalClipboardNotice notice) {}
  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {}
  @override
  void showCloseConfirmation() {}
  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    _live = false;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}
