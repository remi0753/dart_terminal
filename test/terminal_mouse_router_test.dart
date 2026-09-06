import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalMouseRouterTests();

void runTerminalMouseRouterTests() {
  _testPointNormalizationAndLocalPhases();
  _testTerminalReportingAndShiftOverride();
  _testTrackingEligibilityAndIgnoredReasons();
  _testProtocolBoundsAndInputValidation();
}

void _testPointNormalizationAndLocalPhases() {
  final List<Uint8List> reports = <Uint8List>[];
  final List<TerminalLocalSelectionIntent> intents =
      <TerminalLocalSelectionIntent>[];
  final TerminalMouseRouter router = TerminalMouseRouter(
    onTerminalReport: reports.add,
    onLocalSelection: intents.add,
  );
  final TerminalMouseRouteResult begin = router.route(
    _event(
      AppKitMouseEventKind.down,
      x: -20,
      y: -1,
      clickCount: 2,
      modifiers: const ModifierKeys(ModifierKeys.optionBit),
    ),
    modes: const TerminalMouseModes(),
    rows: 4,
    columns: 10,
    cellWidth: 8,
    cellHeight: 16,
  );
  final TerminalMouseRouteResult update = router.route(
    _event(AppKitMouseEventKind.dragged, x: 15.9, y: 31.9),
    modes: const TerminalMouseModes(),
    rows: 4,
    columns: 10,
    cellWidth: 8,
    cellHeight: 16,
  );
  final TerminalMouseRouteResult end = router.route(
    _event(AppKitMouseEventKind.up, x: 999, y: 999),
    modes: const TerminalMouseModes(),
    rows: 4,
    columns: 10,
    cellWidth: 8,
    cellHeight: 16,
  );
  _expect(
    reports.isEmpty &&
        intents.length == 3 &&
        begin.disposition == TerminalMouseRouteDisposition.localSelection &&
        begin.localSelection!.phase == TerminalLocalSelectionPhase.begin &&
        begin.localSelection!.cell == TerminalPointerCell(row: 0, column: 0) &&
        begin.localSelection!.clickCount == 2 &&
        begin.localSelection!.modifiers.option &&
        update.localSelection!.phase == TerminalLocalSelectionPhase.update &&
        update.localSelection!.cell == TerminalPointerCell(row: 1, column: 1) &&
        end.localSelection!.phase == TerminalLocalSelectionPhase.end &&
        end.localSelection!.cell == TerminalPointerCell(row: 3, column: 9),
    'normal-shell gestures map, clamp, and emit only local intents',
  );
  _expectThrows<UnsupportedError>(
    () => begin.terminalBytes.add(1),
    'route byte results are immutable',
  );
}

void _testTerminalReportingAndShiftOverride() {
  final List<List<int>> reports = <List<int>>[];
  final List<TerminalLocalSelectionIntent> intents =
      <TerminalLocalSelectionIntent>[];
  final TerminalMouseRouter router = TerminalMouseRouter(
    onTerminalReport: (Uint8List bytes) => reports.add(bytes.toList()),
    onLocalSelection: intents.add,
  );
  const TerminalMouseModes sgr = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.sgr,
  );
  final TerminalMouseRouteResult remote = router.route(
    _event(
      AppKitMouseEventKind.down,
      x: 8,
      y: 16,
      button: 1,
      modifiers: const ModifierKeys(
        ModifierKeys.optionBit | ModifierKeys.controlBit,
      ),
    ),
    modes: sgr,
    rows: 4,
    columns: 10,
    cellWidth: 8,
    cellHeight: 16,
  );
  final TerminalMouseRouteResult local = router.route(
    _event(
      AppKitMouseEventKind.down,
      x: 8,
      y: 16,
      modifiers: const ModifierKeys(
        ModifierKeys.shiftBit | ModifierKeys.controlBit,
      ),
    ),
    modes: sgr,
    rows: 4,
    columns: 10,
    cellWidth: 8,
    cellHeight: 16,
  );
  _expect(
    remote.disposition == TerminalMouseRouteDisposition.terminalReport &&
        String.fromCharCodes(remote.terminalBytes) == '\x1b[<26;2;2M' &&
        reports.length == 1 &&
        intents.length == 1 &&
        local.disposition == TerminalMouseRouteDisposition.localSelection &&
        local.terminalBytes.isEmpty &&
        local.localSelection!.modifiers.shift &&
        local.localSelection!.modifiers.control,
    'active tracking reports remotely unless Shift chooses local selection',
  );
}

void _testTrackingEligibilityAndIgnoredReasons() {
  var reportCount = 0;
  var localCount = 0;
  final TerminalMouseRouter router = TerminalMouseRouter(
    onTerminalReport: (Uint8List bytes) => reportCount++,
    onLocalSelection: (TerminalLocalSelectionIntent intent) => localCount++,
  );
  TerminalMouseRouteResult result = _route(
    router,
    _event(AppKitMouseEventKind.moved, button: -1),
    const TerminalMouseModes(),
  );
  _expect(
    result.disposition == TerminalMouseRouteDisposition.ignored &&
        result.ignoreReason == TerminalMouseIgnoreReason.noTrackingMotion,
    'untracked plain motion is ignored',
  );
  result = _route(
    router,
    _event(AppKitMouseEventKind.up),
    const TerminalMouseModes(tracking: TerminalMouseTrackingMode.x10),
  );
  _expect(
    result.ignoreReason == TerminalMouseIgnoreReason.trackingFiltered,
    'X10 release is ignored rather than opening a local gesture',
  );
  result = _route(
    router,
    _event(AppKitMouseEventKind.dragged),
    const TerminalMouseModes(tracking: TerminalMouseTrackingMode.buttonEvent),
  );
  _expect(
    result.disposition == TerminalMouseRouteDisposition.terminalReport,
    'button-event tracking reports drag motion',
  );
  result = _route(
    router,
    _event(AppKitMouseEventKind.moved, button: -1),
    const TerminalMouseModes(tracking: TerminalMouseTrackingMode.buttonEvent),
  );
  _expect(
    result.ignoreReason == TerminalMouseIgnoreReason.trackingFiltered,
    'button-event tracking filters no-button motion',
  );
  result = _route(
    router,
    _event(AppKitMouseEventKind.moved, button: -1),
    const TerminalMouseModes(tracking: TerminalMouseTrackingMode.anyEvent),
  );
  _expect(
    result.disposition == TerminalMouseRouteDisposition.terminalReport &&
        reportCount == 2 &&
        localCount == 0,
    'any-event tracking reports movement with exclusive callbacks',
  );
  result = _route(
    router,
    _event(AppKitMouseEventKind.down, button: 4),
    const TerminalMouseModes(),
  );
  _expect(
    result.ignoreReason == TerminalMouseIgnoreReason.unsupportedButton &&
        reportCount == 2 &&
        localCount == 0,
    'unsupported auxiliary button is ignored without side effects',
  );
}

void _testProtocolBoundsAndInputValidation() {
  var callbacks = 0;
  final TerminalMouseRouter router = TerminalMouseRouter(
    onTerminalReport: (Uint8List bytes) => callbacks++,
    onLocalSelection: (TerminalLocalSelectionIntent intent) => callbacks++,
  );
  final TerminalMouseRouteResult limited = router.route(
    _event(AppKitMouseEventKind.down, x: 223.1 * 8),
    modes: const TerminalMouseModes(tracking: TerminalMouseTrackingMode.normal),
    rows: 4,
    columns: 300,
    cellWidth: 8,
    cellHeight: 16,
  );
  _expect(
    limited.disposition == TerminalMouseRouteDisposition.ignored &&
        limited.ignoreReason ==
            TerminalMouseIgnoreReason.protocolCoordinateLimit &&
        callbacks == 0,
    'unrepresentable protocol coordinates fail closed without callbacks',
  );
  _expectThrows<ArgumentError>(
    () => _route(
      router,
      _event(AppKitMouseEventKind.down, x: double.nan),
      const TerminalMouseModes(),
    ),
    'non-finite points are rejected',
  );
  _expectThrows<ArgumentError>(
    () => router.route(
      _event(AppKitMouseEventKind.down),
      modes: const TerminalMouseModes(),
      rows: 4,
      columns: 10,
      cellWidth: 0,
      cellHeight: 16,
    ),
    'non-positive metrics are rejected',
  );
  _expectThrows<RangeError>(
    () => router.route(
      _event(AppKitMouseEventKind.down, clickCount: 256),
      modes: const TerminalMouseModes(),
      rows: 4,
      columns: 10,
      cellWidth: 8,
      cellHeight: 16,
    ),
    'click count is bounded',
  );
  _expectThrows<ArgumentError>(
    () => _route(
      router,
      _event(AppKitMouseEventKind.down, modifiers: const ModifierKeys(1 << 20)),
      const TerminalMouseModes(),
    ),
    'unknown modifier bits are rejected',
  );
  _expectThrows<RangeError>(
    () => TerminalPointerCell(row: -1, column: 0),
    'public pointer cells remain bounded',
  );
  _expectThrows<ArgumentError>(
    () => TerminalLocalSelectionIntent(
      phase: TerminalLocalSelectionPhase.begin,
      cell: TerminalPointerCell(row: 0, column: 0),
      button: TerminalMouseButton.none,
      clickCount: 1,
      modifiers: const ModifierKeys(0),
    ),
    'public local intents require a physical button',
  );
  _expectThrows<ArgumentError>(
    () => TerminalMouseRouteResult.terminal(const <int>[]),
    'public terminal results require a bounded packet',
  );
}

TerminalMouseRouteResult _route(
  TerminalMouseRouter router,
  AppKitMouseEvent event,
  TerminalMouseModes modes,
) => router.route(
  event,
  modes: modes,
  rows: 4,
  columns: 10,
  cellWidth: 8,
  cellHeight: 16,
);

AppKitMouseEvent _event(
  AppKitMouseEventKind kind, {
  double x = 0,
  double y = 0,
  int button = 0,
  int clickCount = 1,
  ModifierKeys modifiers = const ModifierKeys(0),
}) => AppKitMouseEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  x: x,
  y: y,
  button: button,
  modifiers: modifiers,
  clickCount: clickCount,
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
