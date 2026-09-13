import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalCommandPaletteTests();

Future<void> runTerminalCommandPaletteTests() async {
  await _testEditingNavigationAndInvocation();
  await _testRefreshAfterOpeningDispatch();
  await _testIgnoredDismissAndOverflow();
}

Future<void> _testRefreshAfterOpeningDispatch() async {
  late final TerminalCommandPaletteState state;
  final TerminalActionCatalog catalog = TerminalActionCatalog(
    <TerminalActionDefinition>[
      _definition(TerminalActionId.openCommandPalette, 'Command Palette'),
      _definition(TerminalActionId.focusNextPane, 'Focus Next Pane'),
      _definition(TerminalActionId.newTab, 'New Tab'),
    ],
  );
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.openCommandPalette,
        handler: () => state.open(),
      ),
      TerminalActionRegistration(
        id: TerminalActionId.focusNextPane,
        handler: () {},
      ),
    ],
  );
  state = TerminalCommandPaletteState(dispatcher);

  final Future<TerminalActionDispatchResult> opening = dispatcher.dispatch(
    TerminalActionId.openCommandPalette,
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    state.isOpen && state.results.every((result) => !result.isEnabled),
    'opening action snapshots are conservatively disabled while dispatch runs',
  );
  _expect(
    (await opening).disposition == TerminalActionDispatchDisposition.executed,
    'palette opening action completes normally',
  );
  state.refresh();
  _expect(
    state.results
            .singleWhere(
              (result) =>
                  result.definition.id == TerminalActionId.focusNextPane,
            )
            .isEnabled &&
        !state.results
            .singleWhere(
              (result) => result.definition.id == TerminalActionId.newTab,
            )
            .isEnabled,
    'post-dispatch refresh enables only implemented actions',
  );
}

Future<void> _testEditingNavigationAndInvocation() async {
  final TerminalActionCatalog catalog = TerminalActionCatalog(
    <TerminalActionDefinition>[
      _definition(TerminalActionId.copy, 'Copy'),
      _definition(TerminalActionId.paste, 'Paste'),
    ],
  );
  var copyCount = 0;
  final TerminalCommandPaletteState state = TerminalCommandPaletteState(
    TerminalActionDispatcher(
      catalog: catalog,
      registrations: <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.copy,
          handler: () => copyCount++,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.paste,
          isAvailable: () => false,
          handler: () {},
        ),
      ],
    ),
  )..open();
  final TerminalCommandPaletteKeyController keys =
      TerminalCommandPaletteKeyController(state);
  _expect(
    (await keys.handle(_key(keyCode: 0, characters: 'co'))).disposition ==
            TerminalCommandPaletteKeyDisposition.updated &&
        state.query == 'co' &&
        state.results.single.definition.id == TerminalActionId.copy,
    'printable multi-scalar event updates the query and search once',
  );
  await keys.handle(_key(keyCode: 51));
  _expect(
    state.query == 'c',
    'physical Backspace removes the last query scalar',
  );
  await keys.handle(_key(keyCode: 51));
  await keys.handle(_key(keyCode: 125));
  _expect(
    state.selectedAction?.definition.id == TerminalActionId.paste,
    'physical Down Arrow moves selection independently from text',
  );
  await keys.handle(_key(keyCode: 125));
  await keys.handle(_key(keyCode: 125));
  _expect(
    state.selectedAction?.definition.id == TerminalActionId.paste,
    'physical Down Arrow stops at the final result',
  );
  final TerminalCommandPaletteKeyResult unavailable = await keys.handle(
    _key(keyCode: 36, characters: '\r'),
  );
  _expect(
    unavailable.disposition == TerminalCommandPaletteKeyDisposition.invoked &&
        unavailable.dispatchResult?.disposition ==
            TerminalActionDispatchDisposition.unavailable &&
        state.isOpen,
    'Return preserves the palette after an unavailable action',
  );
  await keys.handle(_key(keyCode: 126));
  await keys.handle(_key(keyCode: 126));
  await keys.handle(_key(keyCode: 126));
  _expect(
    state.selectedAction?.definition.id == TerminalActionId.copy,
    'physical Up Arrow stops at the first result',
  );
  final TerminalCommandPaletteKeyResult executed = await keys.handle(
    _key(keyCode: 76, characters: '\r'),
  );
  _expect(
    executed.dispatchResult?.id == TerminalActionId.copy &&
        executed.dispatchResult?.disposition ==
            TerminalActionDispatchDisposition.executed &&
        copyCount == 1 &&
        !state.isOpen,
    'keypad Return dispatches the selected action exactly once',
  );
}

Future<void> _testIgnoredDismissAndOverflow() async {
  final TerminalActionCatalog catalog = TerminalActionCatalog(
    <TerminalActionDefinition>[_definition(TerminalActionId.copy, 'Copy')],
  );
  final TerminalCommandPaletteState state = TerminalCommandPaletteState(
    TerminalActionDispatcher(catalog: catalog),
  )..open();
  final TerminalCommandPaletteKeyController keys =
      TerminalCommandPaletteKeyController(state);
  for (final AppKitKeyEvent event in <AppKitKeyEvent>[
    _key(keyCode: 0, characters: 'a', kind: AppKitKeyEventKind.up),
    _key(
      keyCode: 0,
      characters: 'a',
      modifiers: const ModifierKeys(ModifierKeys.commandBit),
    ),
    _key(
      keyCode: 0,
      characters: '\u0001',
      modifiers: const ModifierKeys(ModifierKeys.controlBit),
    ),
  ]) {
    _expect(
      (await keys.handle(event)).disposition ==
          TerminalCommandPaletteKeyDisposition.ignored,
      'non-owned key input is ignored',
    );
  }
  state.setQuery('x' * TerminalActionLimits.maximumPaletteQueryUnits);
  _expect(
    (await keys.handle(_key(keyCode: 0, characters: 'y'))).disposition ==
            TerminalCommandPaletteKeyDisposition.overflow &&
        state.query.length == TerminalActionLimits.maximumPaletteQueryUnits,
    'the key controller reports overflow without changing bounded state',
  );
  final TerminalCommandPaletteKeyResult dismissed = await keys.handle(
    _key(keyCode: 53, characters: '\u001b'),
  );
  _expect(
    dismissed.disposition == TerminalCommandPaletteKeyDisposition.dismissed &&
        !state.isOpen,
    'physical Escape dismisses and clears the palette',
  );
  _expect(
    (await keys.handle(_key(keyCode: 0, characters: 'z'))).disposition ==
        TerminalCommandPaletteKeyDisposition.ignored,
    'closed palette consumes no later key event',
  );
}

TerminalActionDefinition _definition(TerminalActionId id, String title) =>
    TerminalActionDefinition(
      id: id,
      title: title,
      menu: TerminalActionMenu.edit,
    );

AppKitKeyEvent _key({
  required int keyCode,
  String characters = '',
  ModifierKeys modifiers = const ModifierKeys(0),
  AppKitKeyEventKind kind = AppKitKeyEventKind.down,
}) => AppKitKeyEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  keyCode: keyCode,
  modifiers: modifiers,
  isRepeat: false,
  characters: characters,
  charactersIgnoringModifiers: characters,
);

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal command palette expectation failed: $description',
    );
  }
}
