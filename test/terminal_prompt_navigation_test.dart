import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalPromptNavigationTests();

Future<void> runTerminalPromptNavigationTests() async {
  await _testFocusedViewportDispatchAndAvailability();
}

Future<void> _testFocusedViewportDispatchAndAvailability() async {
  final TerminalScreenSet markedScreens = TerminalScreenSet(
    columns: 4,
    rows: 2,
    scrollback: TerminalScrollback(maxLines: 8, maxBytes: 4096, pageRows: 2),
  );
  final TerminalScreen marked = markedScreens.primary;
  marked
    ..setLogicalLineId(0, 1)
    ..setRowFlags(0, TerminalRowFlags.prompt)
    ..scrollUp(1)
    ..setLogicalLineId(0, 2)
    ..setRowFlags(0, TerminalRowFlags.prompt)
    ..setCursorPosition(1, 0);
  final TerminalViewport markedViewport = markedScreens.viewport;

  final TerminalScreenSet emptyScreens = TerminalScreenSet(
    columns: 4,
    rows: 2,
    scrollback: TerminalScrollback(maxLines: 8, maxBytes: 4096, pageRows: 2),
  );
  final TerminalViewport emptyViewport = emptyScreens.viewport;
  TerminalViewport? focused = markedViewport;
  final List<TerminalViewport> moved = <TerminalViewport>[];
  final TerminalPromptNavigationActionCoordinator coordinator =
      TerminalPromptNavigationActionCoordinator(
        activeViewport: () => focused,
        onMoved: moved.add,
      );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: coordinator.registrations(),
  );

  _expectEnabled(dispatcher, TerminalActionId.jumpToPreviousPrompt, true);
  _expectEnabled(dispatcher, TerminalActionId.jumpToNextPrompt, false);
  _expect(
    (await dispatcher.dispatch(TerminalActionId.jumpToPreviousPrompt))
                .disposition ==
            TerminalActionDispatchDisposition.executed &&
        markedViewport.offset == 1 &&
        emptyViewport.offset == 0 &&
        moved.length == 1 &&
        identical(moved.single, markedViewport),
    'previous-prompt dispatch moves and publishes only the focused viewport',
  );

  _expectEnabled(dispatcher, TerminalActionId.jumpToPreviousPrompt, false);
  _expectEnabled(dispatcher, TerminalActionId.jumpToNextPrompt, true);
  focused = emptyViewport;
  _expectEnabled(dispatcher, TerminalActionId.jumpToPreviousPrompt, false);
  _expectEnabled(dispatcher, TerminalActionId.jumpToNextPrompt, false);
  _expect(
    (await dispatcher.dispatch(TerminalActionId.jumpToPreviousPrompt))
                .disposition ==
            TerminalActionDispatchDisposition.unavailable &&
        markedViewport.offset == 1 &&
        emptyViewport.offset == 0 &&
        moved.length == 1,
    'a focused viewport without marks fails closed without touching another pane',
  );

  focused = markedViewport;
  markedScreens.setAlternateMode47(true);
  _expectEnabled(dispatcher, TerminalActionId.jumpToPreviousPrompt, false);
  _expectEnabled(dispatcher, TerminalActionId.jumpToNextPrompt, false);
  markedScreens.setAlternateMode47(false);
  _expect(
    (await dispatcher.dispatch(TerminalActionId.jumpToNextPrompt))
                .disposition ==
            TerminalActionDispatchDisposition.executed &&
        markedViewport.offset == 0 &&
        moved.length == 2 &&
        identical(moved.last, markedViewport),
    'returning to primary restores next-prompt navigation to the live grid',
  );

  focused = null;
  _expectEnabled(dispatcher, TerminalActionId.jumpToPreviousPrompt, false);
  _expectEnabled(dispatcher, TerminalActionId.jumpToNextPrompt, false);
}

void _expectEnabled(
  TerminalActionDispatcher dispatcher,
  TerminalActionId id,
  bool expected,
) {
  _expect(
    dispatcher.snapshot(id).isEnabled == expected,
    '${id.stableName} availability is $expected',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
