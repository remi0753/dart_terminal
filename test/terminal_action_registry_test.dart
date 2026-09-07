import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalActionRegistryTests();

Future<void> runTerminalActionRegistryTests() async {
  _testStableStandardCatalog();
  _testCatalogValidationAndImmutability();
  await _testAvailabilityDispatchAndFailure();
  _testSearchOrderingAndBounds();
  await _testPaletteState();
}

void _testStableStandardCatalog() {
  final TerminalActionCatalog catalog = TerminalActionCatalog.standard();
  _expect(
    catalog.actions.length == TerminalActionId.values.length,
    'standard catalog covers every stable application action exactly once',
  );
  final Set<String> stableNames = TerminalActionId.values
      .map((TerminalActionId id) => id.stableName)
      .toSet();
  _expect(
    stableNames.length == TerminalActionId.values.length,
    'stable action names are unique',
  );
  for (final TerminalActionId id in TerminalActionId.values) {
    _expect(
      TerminalActionId.fromStableName(id.stableName) == id &&
          catalog.actionForId(id)?.id == id,
      'action ${id.stableName} round-trips and is catalogued',
    );
  }
  _expect(
    TerminalActionId.fromStableName('application.unknown') == null,
    'unknown stable action names have no fallback',
  );
  _expect(
    catalog
            .actionsForMenu(TerminalActionMenu.shell)
            .map((TerminalActionDefinition action) => action.id)
            .join(',') ==
        <TerminalActionId>[
          TerminalActionId.newTab,
          TerminalActionId.splitPaneRight,
          TerminalActionId.splitPaneDown,
        ].join(','),
    'menu projection preserves catalog order',
  );
}

void _testCatalogValidationAndImmutability() {
  final List<TerminalActionDefinition> definitions = <TerminalActionDefinition>[
    _definition(TerminalActionId.copy),
  ];
  final TerminalActionCatalog catalog = TerminalActionCatalog(definitions);
  definitions.clear();
  _expect(
    catalog.actions.length == 1 &&
        catalog.actionForId(TerminalActionId.copy) != null,
    'catalog copies its source iterable',
  );
  _expectThrows<UnsupportedError>(
    () => catalog.actions.clear(),
    'action catalog snapshot is immutable',
  );
  _expectThrows<TerminalActionCatalogConflictException>(
    () => TerminalActionCatalog(<TerminalActionDefinition>[
      _definition(TerminalActionId.copy),
      _definition(TerminalActionId.copy),
    ]),
    'duplicate action identity is rejected',
  );
  _expectThrows<TerminalActionCatalogConflictException>(
    () => TerminalActionCatalog(<TerminalActionDefinition>[
      _definition(
        TerminalActionId.copy,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'C',
          command: true,
        ),
      ),
      _definition(
        TerminalActionId.paste,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'c',
          command: true,
        ),
      ),
    ]),
    'case-insensitive duplicate native shortcut is rejected',
  );
  _expectThrows<TerminalActionLimitException>(
    () => TerminalActionCatalog(
      Iterable<TerminalActionDefinition>.generate(
        TerminalActionLimits.maximumActions + 1,
        (int index) => _definition(TerminalActionId.copy),
      ),
    ),
    'catalog iteration stops at its hard bound',
  );
  _expectThrows<ArgumentError>(
    () => TerminalActionDefinition(
      id: TerminalActionId.copy,
      title: '',
      menu: TerminalActionMenu.edit,
    ),
    'empty titles are rejected',
  );
  _expectThrows<ArgumentError>(
    () => TerminalActionDefinition(
      id: TerminalActionId.copy,
      title: 'Copy',
      menu: TerminalActionMenu.edit,
      shortcut: const TerminalActionShortcut(keyEquivalent: '\n'),
    ),
    'control key equivalents are rejected',
  );
}

Future<void> _testAvailabilityDispatchAndFailure() async {
  final TerminalActionCatalog catalog = TerminalActionCatalog(
    <TerminalActionDefinition>[
      _definition(TerminalActionId.copy),
      _definition(TerminalActionId.paste),
      _definition(TerminalActionId.newTab),
    ],
  );
  var copyAvailable = false;
  var copyCount = 0;
  final Completer<void> pasteGate = Completer<void>();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        isAvailable: () => copyAvailable,
        handler: () => copyCount++,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.paste,
        handler: () => pasteGate.future,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.newTab,
        handler: () => throw StateError('expected failure'),
      ),
    ],
  );
  _expect(
    !dispatcher.snapshot(TerminalActionId.copy).isEnabled,
    'dynamic false availability disables an action',
  );
  _expect(
    (await dispatcher.dispatch(TerminalActionId.copy)).disposition ==
            TerminalActionDispatchDisposition.unavailable &&
        copyCount == 0,
    'unavailable action does not invoke its handler',
  );
  copyAvailable = true;
  _expect(
    (await dispatcher.dispatch(TerminalActionId.copy)).disposition ==
            TerminalActionDispatchDisposition.executed &&
        copyCount == 1,
    'available action executes exactly once',
  );
  final Future<TerminalActionDispatchResult> pending = dispatcher.dispatch(
    TerminalActionId.paste,
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    dispatcher.snapshot(TerminalActionId.paste).isRunning &&
        (await dispatcher.dispatch(TerminalActionId.copy)).disposition ==
            TerminalActionDispatchDisposition.busy &&
        copyCount == 1,
    'one in-flight handler serializes reentrant dispatch',
  );
  pasteGate.complete();
  _expect(
    (await pending).disposition == TerminalActionDispatchDisposition.executed,
    'async handler completion clears the dispatcher',
  );
  final TerminalActionDispatchResult failed = await dispatcher.dispatch(
    TerminalActionId.newTab,
  );
  _expect(
    failed.disposition == TerminalActionDispatchDisposition.failed &&
        failed.error is StateError &&
        failed.stackTrace != null,
    'handler failure is classified and retained without escaping',
  );
  final TerminalActionDispatcher throwingAvailability =
      TerminalActionDispatcher(
        catalog: catalog,
        registrations: <TerminalActionRegistration>[
          TerminalActionRegistration(
            id: TerminalActionId.copy,
            isAvailable: () => throw StateError('invalid context'),
            handler: () => copyCount++,
          ),
        ],
      );
  _expect(
    !throwingAvailability.snapshot(TerminalActionId.copy).isEnabled,
    'availability exceptions fail closed',
  );
  _expectThrows<ArgumentError>(
    () => TerminalActionDispatcher(
      catalog: catalog,
      registrations: <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.quitApplication,
          handler: () {},
        ),
      ],
    ),
    'registration outside the catalog is rejected',
  );
  _expectThrows<StateError>(
    () => TerminalActionDispatcher(
      catalog: catalog,
      registrations: <TerminalActionRegistration>[
        TerminalActionRegistration(id: TerminalActionId.copy, handler: () {}),
        TerminalActionRegistration(id: TerminalActionId.copy, handler: () {}),
      ],
    ),
    'duplicate handlers are rejected',
  );
}

void _testSearchOrderingAndBounds() {
  final TerminalActionCatalog catalog = TerminalActionCatalog.standard();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      for (final TerminalActionDefinition action in catalog.actions)
        TerminalActionRegistration(id: action.id, handler: () {}),
    ],
  );
  _expect(
    dispatcher.search('split down').single.definition.id ==
        TerminalActionId.splitPaneDown,
    'multi-token exact search finds the intended action',
  );
  _expect(
    dispatcher.search('SPLTRGHT').single.definition.id ==
        TerminalActionId.splitPaneRight,
    'case-insensitive subsequence search is deterministic',
  );
  _expect(
    dispatcher.search('clipboard').length == 2 &&
        dispatcher.search('clipboard')[0].definition.id ==
            TerminalActionId.copy &&
        dispatcher.search('clipboard')[1].definition.id ==
            TerminalActionId.paste,
    'equal keyword matches retain catalog order',
  );
  _expect(
    !dispatcher
        .search('quit')
        .any(
          (TerminalActionSnapshot snapshot) =>
              snapshot.definition.id == TerminalActionId.quitApplication,
        ),
    'palette-hidden actions remain absent from search',
  );
  _expect(
    dispatcher.search('', maximumResults: 3).length == 3,
    'empty query and explicit result count remain bounded',
  );
  _expectThrows<TerminalActionLimitException>(
    () => dispatcher.search(
      'x' * (TerminalActionLimits.maximumPaletteQueryUnits + 1),
    ),
    'oversize query is rejected',
  );
  _expectThrows<ArgumentError>(
    () => dispatcher.search(
      '',
      maximumResults: TerminalActionLimits.maximumPaletteResults + 1,
    ),
    'oversize result request is rejected',
  );
}

Future<void> _testPaletteState() async {
  final TerminalActionCatalog catalog = TerminalActionCatalog(
    <TerminalActionDefinition>[
      TerminalActionDefinition(
        id: TerminalActionId.copy,
        title: 'Copy 日本語',
        menu: TerminalActionMenu.edit,
        keywords: const <String>['複製'],
      ),
      _definition(TerminalActionId.paste),
    ],
  );
  var copyCount = 0;
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
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
  );
  final TerminalCommandPaletteState palette = TerminalCommandPaletteState(
    dispatcher,
  );
  _expectThrows<StateError>(palette.refresh, 'closed palette rejects mutation');
  palette.open();
  _expect(
    palette.isOpen &&
        palette.query.isEmpty &&
        palette.results.length == 2 &&
        palette.selectedAction?.definition.id == TerminalActionId.copy,
    'open palette initializes an immutable searchable snapshot',
  );
  _expectThrows<UnsupportedError>(
    () => palette.results.clear(),
    'palette result list is immutable',
  );
  palette
    ..setQuery('複製')
    ..append('🙂')
    ..deleteLastScalar();
  _expect(
    palette.query == '複製' &&
        palette.results.single.definition.id == TerminalActionId.copy,
    'Unicode query and last-scalar deletion are exact',
  );
  palette.setQuery('');
  palette.moveSelection(-1);
  _expect(
    palette.selectedAction?.definition.id == TerminalActionId.paste,
    'negative navigation wraps to the last result',
  );
  final TerminalActionDispatchResult unavailable = await palette
      .invokeSelected();
  _expect(
    unavailable.disposition == TerminalActionDispatchDisposition.unavailable &&
        palette.isOpen,
    'unavailable selection remains open without invocation',
  );
  palette.moveSelection(1);
  final TerminalActionDispatchResult executed = await palette.invokeSelected();
  _expect(
    executed.disposition == TerminalActionDispatchDisposition.executed &&
        copyCount == 1 &&
        !palette.isOpen &&
        palette.results.isEmpty,
    'successful invocation executes once and dismisses the palette',
  );
  palette.open();
  _expectThrows<TerminalActionLimitException>(
    () => palette.setQuery(
      'x' * (TerminalActionLimits.maximumPaletteQueryUnits + 1),
    ),
    'palette state enforces the query bound',
  );
  _expectThrows<ArgumentError>(
    () => palette.setQuery('bad\nquery'),
    'palette state rejects control characters',
  );
  palette.dismiss();
}

TerminalActionDefinition _definition(
  TerminalActionId id, {
  TerminalActionShortcut? shortcut,
}) => TerminalActionDefinition(
  id: id,
  title: id.stableName,
  menu: TerminalActionMenu.application,
  shortcut: shortcut,
);

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal action registry expectation failed: $description',
    );
  }
}
