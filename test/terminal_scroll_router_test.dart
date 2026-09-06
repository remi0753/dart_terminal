import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalScrollRouterTests();

void runTerminalScrollRouterTests() {
  _testPreciseAccumulatorAndMomentum();
  _testDirectionClassificationPhaseAndBounds();
  _testLocalAndTerminalOwnership();
  _testAlternateScreenAndShiftOverride();
  _testCoordinateAndInputValidation();
}

void _testPreciseAccumulatorAndMomentum() {
  final TerminalScrollAccumulator accumulator = TerminalScrollAccumulator();
  _expect(
    accumulator.consume(
          _event(deltaY: 5, precise: true, phase: AppKitScrollPhase.began),
          cellHeight: 10,
        ) ==
        0,
    'a half-row physical begin is retained',
  );
  _expect(accumulator.residualRows == 0.5, 'half-row residual is exact');
  _expect(
    accumulator.consume(
          _event(deltaY: 6, precise: true, phase: AppKitScrollPhase.changed),
          cellHeight: 10,
        ) ==
        1,
    'compatible precise events accumulate into one row',
  );
  _expect(
    (accumulator.residualRows - 0.1).abs() < 0.000001,
    'fraction remains after one emitted row',
  );
  _expect(
    accumulator.consume(
          _event(
            deltaY: 9,
            precise: true,
            momentumPhase: AppKitScrollPhase.began,
          ),
          cellHeight: 10,
        ) ==
        1,
    'momentum continuation consumes the physical gesture residual once',
  );
  _expect(
    accumulator.consume(
              _event(
                deltaY: 5,
                precise: true,
                momentumPhase: AppKitScrollPhase.ended,
              ),
              cellHeight: 10,
            ) ==
            0 &&
        accumulator.residualRows == 0.0,
    'momentum end drops only a final sub-row remainder',
  );
}

void _testDirectionClassificationPhaseAndBounds() {
  final TerminalScrollAccumulator accumulator = TerminalScrollAccumulator();
  accumulator.consume(
    _event(deltaY: 9, precise: true, phase: AppKitScrollPhase.began),
    cellHeight: 10,
  );
  _expect(
    accumulator.consume(
              _event(
                deltaY: -5,
                precise: true,
                phase: AppKitScrollPhase.changed,
              ),
              cellHeight: 10,
            ) ==
            0 &&
        accumulator.residualRows == -0.5,
    'direction reversal discards the previous-direction residual',
  );
  _expect(
    accumulator.consume(_event(deltaY: -0.75), cellHeight: 10) == 0 &&
        accumulator.residualRows == -0.75,
    'precision classification change starts a new accumulator stream',
  );
  _expect(
    accumulator.consume(_event(deltaY: -0.25), cellHeight: 10) == -1,
    'non-precise fractional deltas still accumulate as row units',
  );
  _expect(
    accumulator.consume(_event(deltaY: 1000000), cellHeight: 10) ==
        TerminalScrollAccumulator.maximumRowsPerEvent,
    'one native event cannot emit beyond the row bound',
  );
  _expect(
    accumulator.consume(
              _event(deltaY: 2, phase: AppKitScrollPhase.cancelled),
              cellHeight: 10,
            ) ==
            0 &&
        accumulator.residualRows == 0.0,
    'cancelled streams emit nothing and clear residual state',
  );
}

void _testLocalAndTerminalOwnership() {
  final List<int> local = <int>[];
  final List<List<int>> terminal = <List<int>>[];
  final List<List<int>> alternate = <List<int>>[];
  final TerminalScrollRouter router = TerminalScrollRouter(
    onTerminalReport: (Uint8List bytes) => terminal.add(bytes),
    onLocalScroll: local.add,
    onAlternateScreenInput: (Uint8List bytes) => alternate.add(bytes),
  );

  final TerminalScrollRouteResult localResult = _route(
    router,
    _event(deltaY: 2),
  );
  _expect(
    localResult.disposition == TerminalScrollDisposition.localScroll &&
        localResult.localRows == 2 &&
        local.join() == '2' &&
        terminal.isEmpty &&
        alternate.isEmpty,
    'normal primary scroll has one local owner',
  );

  const TerminalMouseModes sgr = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.sgr,
  );
  final TerminalScrollRouteResult terminalResult = _route(
    router,
    _event(deltaY: 2, x: 15, y: 25),
    mouseModes: sgr,
  );
  _expect(
    terminalResult.disposition == TerminalScrollDisposition.terminalReport &&
        ascii.decode(terminalResult.terminalBytes) ==
            '\x1b[<64;2;3M\x1b[<64;2;3M' &&
        terminal.length == 1 &&
        local.length == 1,
    'active tracking receives repeated wheel presses at the pointer cell only',
  );

  final TerminalScrollRouteResult override = _route(
    router,
    _event(deltaY: -1, modifiers: const ModifierKeys(ModifierKeys.shiftBit)),
    mouseModes: sgr,
  );
  _expect(
    override.disposition == TerminalScrollDisposition.localScroll &&
        override.localRows == -1 &&
        local.length == 2 &&
        terminal.length == 1,
    'Shift changes the owner from terminal reporting to local history',
  );

  final TerminalScrollRouteResult horizontal = _route(
    router,
    _event(deltaX: 5, deltaY: 0),
  );
  _expect(
    horizontal.disposition == TerminalScrollDisposition.ignored &&
        horizontal.ignoreReason == TerminalScrollIgnoreReason.noVerticalDelta,
    'horizontal-only motion is retained by AppKit but has no vertical action',
  );
}

void _testAlternateScreenAndShiftOverride() {
  final List<List<int>> terminal = <List<int>>[];
  final List<int> local = <int>[];
  final List<List<int>> alternate = <List<int>>[];
  final TerminalScrollRouter router = TerminalScrollRouter(
    onTerminalReport: (Uint8List bytes) => terminal.add(bytes),
    onLocalScroll: local.add,
    onAlternateScreenInput: (Uint8List bytes) => alternate.add(bytes),
  );
  final TerminalScrollRouteResult arrows = _route(
    router,
    _event(deltaY: -2),
    usingAlternate: true,
    keyboardModes: const TerminalKeyboardModes(applicationCursorKeys: true),
  );
  _expect(
    arrows.disposition == TerminalScrollDisposition.alternateScreenInput &&
        ascii.decode(arrows.terminalBytes) == '\x1bOB\x1bOB' &&
        alternate.length == 1 &&
        local.isEmpty &&
        terminal.isEmpty,
    'alternate screen emulates application-cursor down keys',
  );

  const TerminalMouseModes tracking = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.sgr,
  );
  final TerminalScrollRouteResult report = _route(
    router,
    _event(deltaY: 1),
    usingAlternate: true,
    mouseModes: tracking,
  );
  _expect(
    report.disposition == TerminalScrollDisposition.terminalReport &&
        terminal.length == 1 &&
        alternate.length == 1,
    'terminal mouse tracking takes ownership on the alternate screen',
  );
  final TerminalScrollRouteResult shifted = _route(
    router,
    _event(deltaY: 1, modifiers: const ModifierKeys(ModifierKeys.shiftBit)),
    usingAlternate: true,
    mouseModes: tracking,
  );
  _expect(
    shifted.disposition == TerminalScrollDisposition.alternateScreenInput &&
        ascii.decode(shifted.terminalBytes) == '\x1b[A' &&
        alternate.length == 2 &&
        terminal.length == 1,
    'Shift bypasses alternate-screen terminal reporting without duplication',
  );
}

void _testCoordinateAndInputValidation() {
  final List<List<int>> terminal = <List<int>>[];
  final TerminalScrollRouter router = TerminalScrollRouter(
    onTerminalReport: (Uint8List bytes) => terminal.add(bytes),
    onLocalScroll: (_) {},
    onAlternateScreenInput: (_) {},
  );
  final TerminalScrollRouteResult limited = _route(
    router,
    _event(deltaY: 1, x: 2990),
    columns: 300,
    mouseModes: const TerminalMouseModes(
      tracking: TerminalMouseTrackingMode.normal,
    ),
  );
  _expect(
    limited.disposition == TerminalScrollDisposition.ignored &&
        limited.ignoreReason ==
            TerminalScrollIgnoreReason.protocolCoordinateLimit &&
        terminal.isEmpty,
    'legacy coordinate overflow fails closed without a callback',
  );

  _expectThrows<ArgumentError>(
    () => _route(router, _event(deltaY: double.nan)),
    'non-finite delta is rejected',
  );
  _expectThrows<ArgumentError>(
    () => _route(router, _event(deltaY: 1), cellHeight: 0),
    'invalid cell metrics are rejected',
  );
  _expectThrows<ArgumentError>(
    () => _route(router, _event(deltaY: 1, protocolVersion: 4)),
    'pre-v5 scroll event cannot cross the terminal boundary',
  );
  _expectThrows<ArgumentError>(
    () => _route(
      router,
      _event(deltaY: 1, modifiers: const ModifierKeys(1 << 20)),
    ),
    'unknown modifiers are rejected',
  );
}

TerminalScrollRouteResult _route(
  TerminalScrollRouter router,
  AppKitScrollEvent event, {
  TerminalMouseModes mouseModes = const TerminalMouseModes(),
  TerminalKeyboardModes keyboardModes = const TerminalKeyboardModes(),
  bool usingAlternate = false,
  int rows = 24,
  int columns = 80,
  double cellWidth = 10,
  double cellHeight = 10,
}) => router.route(
  event,
  mouseModes: mouseModes,
  keyboardModes: keyboardModes,
  usingAlternateScreen: usingAlternate,
  rows: rows,
  columns: columns,
  cellWidth: cellWidth,
  cellHeight: cellHeight,
);

AppKitScrollEvent _event({
  required double deltaY,
  double deltaX = 0,
  double x = 5,
  double y = 5,
  bool precise = false,
  int protocolVersion = 5,
  AppKitScrollPhase phase = AppKitScrollPhase.none,
  AppKitScrollPhase momentumPhase = AppKitScrollPhase.none,
  ModifierKeys modifiers = const ModifierKeys(0),
}) => AppKitScrollEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  protocolVersion: protocolVersion,
  x: x,
  y: y,
  scrollingDeltaX: deltaX,
  scrollingDeltaY: deltaY,
  hasPreciseScrollingDeltas: precise,
  phase: phase,
  momentumPhase: momentumPhase,
  directionInvertedFromDevice: false,
  modifiers: modifiers,
);

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
