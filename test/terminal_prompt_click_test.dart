import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalPromptClickTests();

void runTerminalPromptClickTests() {
  _testNormalAndApplicationCursorBytes();
  _testNoMovementRejectionAndInputBound();
  _testDragStaleAndChangedReleaseCancellation();
  _testLocalArbiterClearsSelectionAndPreservesOtherGestures();
  _testMouseReportingExcludesPromptClick();
}

void _testNormalAndApplicationCursorBytes() {
  final _Harness normal = _inputHarness('abcdef');
  final List<List<int>> normalWrites = <List<int>>[];
  final TerminalPromptClickController normalClick =
      TerminalPromptClickController(
        screens: normal.screens,
        onTerminalInput: (Uint8List bytes) => normalWrites.add(bytes.toList()),
      );
  final TerminalPromptClickUpdate began = normalClick.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4),
  );
  final TerminalPromptClickUpdate moved = normalClick.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 4),
  );
  _expect(
    began.consumed &&
        began.outcome == TerminalPromptClickOutcome.began &&
        moved.outcome == TerminalPromptClickOutcome.moved &&
        moved.resolution?.plan?.direction ==
            TerminalPromptCursorMoveDirection.left &&
        moved.resolution?.plan?.count == 4 &&
        normalWrites.length == 1 &&
        ascii.decode(normalWrites.single) == '\x1b[D\x1b[D\x1b[D\x1b[D' &&
        ascii.decode(moved.terminalBytes) == '\x1b[D\x1b[D\x1b[D\x1b[D',
    'one normal-cursor Option click emits one exact bounded CSI movement',
  );
  _expectThrows<UnsupportedError>(
    () => moved.terminalBytes.add(0),
    'published prompt-click bytes are immutable',
  );

  final _Harness right = _inputHarness('abcdef');
  right.screens.primary.setCursorPosition(0, 3);
  final List<List<int>> rightWrites = <List<int>>[];
  final TerminalPromptClickController rightClick =
      TerminalPromptClickController(
        screens: right.screens,
        onTerminalInput: (Uint8List bytes) => rightWrites.add(bytes.toList()),
      );
  rightClick.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 6),
  );
  final TerminalPromptClickUpdate rightMoved = rightClick.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 6),
  );
  _expect(
    rightMoved.resolution?.plan?.direction ==
            TerminalPromptCursorMoveDirection.right &&
        rightMoved.resolution?.plan?.count == 3 &&
        ascii.decode(rightWrites.single) == '\x1b[C\x1b[C\x1b[C',
    'a target after the live cursor emits exact normal-cursor right bytes',
  );

  final _Harness application = _inputHarness('abcdef');
  application.screens.setApplicationCursorKeys(true);
  final List<List<int>> applicationWrites = <List<int>>[];
  final TerminalPromptClickController applicationClick =
      TerminalPromptClickController(
        screens: application.screens,
        onTerminalInput: (Uint8List bytes) =>
            applicationWrites.add(bytes.toList()),
      );
  applicationClick.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 6),
  );
  final TerminalPromptClickUpdate applicationMoved = applicationClick.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 6),
  );
  _expect(
    applicationMoved.outcome == TerminalPromptClickOutcome.moved &&
        applicationWrites.length == 1 &&
        ascii.decode(applicationWrites.single) == '\x1bOD\x1bOD',
    'application-cursor mode emits SS3 left exactly once',
  );
}

void _testNoMovementRejectionAndInputBound() {
  final _Harness noMovement = _inputHarness('abcdef');
  var writes = 0;
  final TerminalPromptClickController click = TerminalPromptClickController(
    screens: noMovement.screens,
    onTerminalInput: (Uint8List bytes) => writes++,
  );
  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 8));
  final TerminalPromptClickUpdate stationary = click.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 8),
  );
  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 0));
  final TerminalPromptClickUpdate prompt = click.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 0),
  );
  _expect(
    stationary.outcome == TerminalPromptClickOutcome.noMovement &&
        stationary.terminalBytes.isEmpty &&
        prompt.outcome == TerminalPromptClickOutcome.rejected &&
        prompt.resolution?.rejectionReason ==
            TerminalPromptCursorMoveRejectionReason.outsideInput &&
        writes == 0,
    'same-position and prompt targets are consumed without PTY input',
  );

  final _Harness bounded = _inputHarness(
    List<String>.filled(
      TerminalPromptClickController.maximumArrowCount,
      'x',
    ).join(),
    columns: 100,
    prompt: '>',
  );
  final List<List<int>> boundedWrites = <List<int>>[];
  final TerminalPromptClickController boundedClick =
      TerminalPromptClickController(
        screens: bounded.screens,
        onTerminalInput: (Uint8List bytes) => boundedWrites.add(bytes.toList()),
      );
  boundedClick.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 1),
  );
  final TerminalPromptClickUpdate maximum = boundedClick.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 1),
  );
  _expect(
    maximum.outcome == TerminalPromptClickOutcome.moved &&
        maximum.terminalBytes.length == 255 &&
        boundedWrites.single.length == 255 &&
        maximum.terminalBytes.length <=
            TerminalInputLimits.maximumEncodedBytesPerKeyEvent,
    'the maximum accepted movement remains inside the 256-byte event cap',
  );

  final _Harness over = _inputHarness(
    List<String>.filled(
      TerminalPromptClickController.maximumArrowCount + 1,
      'x',
    ).join(),
    columns: 100,
    prompt: '>',
  );
  var overWrites = 0;
  final TerminalPromptClickController overClick = TerminalPromptClickController(
    screens: over.screens,
    onTerminalInput: (Uint8List bytes) => overWrites++,
  );
  overClick.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 1),
  );
  final TerminalPromptClickUpdate rejected = overClick.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 1),
  );
  _expect(
    rejected.outcome == TerminalPromptClickOutcome.rejected &&
        rejected.resolution?.rejectionReason ==
            TerminalPromptCursorMoveRejectionReason.movementLimit &&
        overWrites == 0,
    'movement requiring 258 bytes fails closed before callback',
  );
}

void _testDragStaleAndChangedReleaseCancellation() {
  final _Harness harness = _inputHarness('abcdef');
  var writes = 0;
  final TerminalPromptClickController click = TerminalPromptClickController(
    screens: harness.screens,
    onTerminalInput: (Uint8List bytes) => writes++,
  );
  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4));
  final TerminalPromptClickUpdate dragged = click.handle(
    _intent(TerminalLocalSelectionPhase.update, row: 0, column: 4),
  );
  _expect(
    dragged.outcome == TerminalPromptClickOutcome.cancelled &&
        dragged.consumed &&
        !click.isActive &&
        writes == 0,
    'any drag cancels the prompt click even inside its starting cell',
  );

  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4));
  final TerminalPromptClickUpdate changedCell = click.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 5),
  );
  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4));
  harness.screens.setApplicationCursorKeys(true);
  final TerminalPromptClickUpdate stale = click.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 4),
  );
  _expect(
    changedCell.outcome == TerminalPromptClickOutcome.cancelled &&
        stale.outcome == TerminalPromptClickOutcome.cancelled &&
        writes == 0,
    'changed release coordinates and mode-generation changes cancel stale plans',
  );

  click.handle(_intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4));
  _expect(
    click.cancelInteraction().outcome == TerminalPromptClickOutcome.cancelled &&
        click.cancelInteraction().outcome == TerminalPromptClickOutcome.ignored,
    'transient cancellation consumes an active sequence only once',
  );
  click.dispose();
  _expect(
    click
            .handle(
              _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4),
            )
            .outcome ==
        TerminalPromptClickOutcome.ignored,
    'disposed prompt-click ownership is inert',
  );
}

void _testLocalArbiterClearsSelectionAndPreservesOtherGestures() {
  final _Harness harness = _inputHarness('abcdef');
  final List<List<int>> writes = <List<int>>[];
  final TerminalLocalGestureController local = TerminalLocalGestureController(
    screens: harness.screens,
    onTerminalInput: (Uint8List bytes) => writes.add(bytes.toList()),
  );
  local.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 3,
      modifiers: const ModifierKeys(0),
    ),
  );
  local.handle(
    _intent(
      TerminalLocalSelectionPhase.end,
      row: 0,
      column: 3,
      modifiers: const ModifierKeys(0),
    ),
  );
  _expect(local.selection.snapshot.hasSelection, 'ordinary click selects');

  final TerminalLocalGestureUpdate began = local.handle(
    _intent(TerminalLocalSelectionPhase.begin, row: 0, column: 4),
  );
  final TerminalLocalGestureUpdate moved = local.handle(
    _intent(TerminalLocalSelectionPhase.end, row: 0, column: 4),
  );
  _expect(
    began.consumedByPromptClick &&
        began.selectionChanged &&
        !local.selection.snapshot.hasSelection &&
        moved.promptClick.outcome == TerminalPromptClickOutcome.moved &&
        writes.length == 1,
    'Option ownership clears the rendered selection before one PTY movement',
  );

  final TerminalLocalGestureUpdate modifiedDouble = local.handle(
    _intent(
      TerminalLocalSelectionPhase.begin,
      row: 0,
      column: 3,
      clickCount: 2,
    ),
  );
  _expect(
    !modifiedDouble.consumedByPromptClick &&
        modifiedDouble.selection?.snapshot.unit == TerminalSelectionUnit.word &&
        writes.length == 1,
    'Option double-click remains an ordinary word gesture',
  );
  local.dispose();
}

void _testMouseReportingExcludesPromptClick() {
  final _Harness harness = _inputHarness('abcdef');
  var localIntents = 0;
  var promptWrites = 0;
  final TerminalLocalGestureController local = TerminalLocalGestureController(
    screens: harness.screens,
    onTerminalInput: (Uint8List bytes) => promptWrites++,
  );
  final List<List<int>> reports = <List<int>>[];
  final TerminalMouseRouter router = TerminalMouseRouter(
    onTerminalReport: (Uint8List bytes) => reports.add(bytes.toList()),
    onLocalSelection: (TerminalLocalSelectionIntent intent) {
      localIntents++;
      local.handle(intent);
    },
  );
  const TerminalMouseModes reporting = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.sgr,
  );
  for (final AppKitMouseEventKind kind in <AppKitMouseEventKind>[
    AppKitMouseEventKind.down,
    AppKitMouseEventKind.up,
  ]) {
    router.route(
      _event(kind, x: 4),
      modes: reporting,
      rows: 2,
      columns: 12,
      cellWidth: 1,
      cellHeight: 1,
    );
  }
  _expect(
    reports.length == 2 &&
        localIntents == 0 &&
        promptWrites == 0 &&
        !local.promptClick.isActive,
    'active mouse reporting owns exact Option press/release without local duplication',
  );

  router.route(
    _event(
      AppKitMouseEventKind.down,
      x: 4,
      modifiers: const ModifierKeys(
        ModifierKeys.shiftBit | ModifierKeys.optionBit,
      ),
    ),
    modes: reporting,
    rows: 2,
    columns: 12,
    cellWidth: 1,
    cellHeight: 1,
  );
  _expect(
    localIntents == 1 &&
        promptWrites == 0 &&
        local.selection.snapshot.unit == TerminalSelectionUnit.cell,
    'Shift override remains local selection and is not exact Option ownership',
  );
}

_Harness _inputHarness(
  String input, {
  int columns = 12,
  String prompt = r'$ ',
}) {
  final _Harness harness = _Harness(rows: 2, columns: columns);
  harness
    ..parse(_osc('A'))
    ..parse(prompt)
    ..parse(_osc('B'))
    ..parse(input);
  return harness;
}

TerminalLocalSelectionIntent _intent(
  TerminalLocalSelectionPhase phase, {
  required int row,
  required int column,
  int clickCount = 1,
  ModifierKeys modifiers = const ModifierKeys(ModifierKeys.optionBit),
}) => TerminalLocalSelectionIntent(
  phase: phase,
  cell: TerminalPointerCell(row: row, column: column),
  button: TerminalMouseButton.left,
  clickCount: clickCount,
  modifiers: modifiers,
);

AppKitMouseEvent _event(
  AppKitMouseEventKind kind, {
  required double x,
  ModifierKeys modifiers = const ModifierKeys(ModifierKeys.optionBit),
}) => AppKitMouseEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  x: x,
  y: 0,
  button: 0,
  modifiers: modifiers,
  clickCount: 1,
);

String _osc(String action) => '\x1b]133;$action\x07';

final class _Harness {
  _Harness({required int rows, required int columns})
    : screens = TerminalScreenSet(rows: rows, columns: columns) {
    parser = VtParser(sink: TerminalScreenParserSink.forScreenSet(screens));
  }

  final TerminalScreenSet screens;
  late final VtParser parser;

  void parse(String value) =>
      parser.parse(Uint8List.fromList(utf8.encode(value)));
}

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
