import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalActionRegistryTests();

Future<void> runTerminalActionRegistryTests() async {
  _testStableStandardCatalog();
  _testCatalogValidationAndImmutability();
  await _testAvailabilityDispatchAndFailure();
  await _testNonBlockingDispatchScheduler();
  _testSearchOrderingAndBounds();
  await _testPaletteState();
}

Future<void> _testNonBlockingDispatchScheduler() async {
  final Completer<void> copyBarrier = Completer<void>();
  var copyCount = 0;
  var pasteCount = 0;
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: TerminalActionCatalog.standard(),
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        handler: () async {
          copyCount++;
          await copyBarrier.future;
        },
      ),
      TerminalActionRegistration(
        id: TerminalActionId.paste,
        handler: () {
          pasteCount++;
          throw StateError('injected scheduled action failure');
        },
      ),
    ],
  );
  final List<TerminalActionDispatchResult> results =
      <TerminalActionDispatchResult>[];
  final List<Object> asynchronousErrors = <Object>[];
  final TerminalActionDispatchScheduler scheduler =
      TerminalActionDispatchScheduler(
        dispatcher: dispatcher,
        onDispatched: results.add,
        onError: (Object error, StackTrace stackTrace) {
          asynchronousErrors.add(error);
        },
      );

  scheduler
    ..schedule(TerminalActionId.copy)
    ..schedule(TerminalActionId.paste);
  await _waitFor(
    () => results.length == 1,
    'busy scheduled result was not published',
  );
  _expect(
    results.single.id == TerminalActionId.paste &&
        results.single.disposition == TerminalActionDispatchDisposition.busy &&
        copyCount == 1 &&
        pasteCount == 0,
    'scheduler starts once and reports a concurrent key action as busy',
  );
  copyBarrier.complete();
  await _waitFor(
    () => results.length == 2,
    'executed scheduled result was not published',
  );
  _expect(
    results.last.id == TerminalActionId.copy &&
        results.last.disposition == TerminalActionDispatchDisposition.executed,
    'the in-flight scheduled action completes without an intermediate queue',
  );

  scheduler.schedule(TerminalActionId.focusNextPane);
  await _waitFor(
    () => results.length == 3,
    'unavailable scheduled result was not published',
  );
  scheduler.schedule(TerminalActionId.paste);
  await _waitFor(
    () => results.length == 4,
    'failed scheduled result was not published',
  );
  _expect(
    results[2].disposition == TerminalActionDispatchDisposition.unavailable &&
        results[3].disposition == TerminalActionDispatchDisposition.failed &&
        pasteCount == 1 &&
        asynchronousErrors.isEmpty,
    'unavailable and failed dispatch outcomes remain observable results',
  );
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
  _expect(
    catalog
            .actionsForMenu(TerminalActionMenu.edit)
            .map((TerminalActionDefinition action) => action.id)
            .join(',') ==
        <TerminalActionId>[
          TerminalActionId.copy,
          TerminalActionId.paste,
          TerminalActionId.allowOsc52Clipboard,
          TerminalActionId.denyOsc52Clipboard,
        ].join(','),
    'edit menu contains bounded OSC 52 decisions after copy and paste',
  );
  _expect(
    catalog
            .actionsForMenu(TerminalActionMenu.view)
            .map((TerminalActionDefinition action) => action.id)
            .join(',') ==
        <TerminalActionId>[
          TerminalActionId.togglePaneZoom,
          TerminalActionId.equalizeSplits,
          TerminalActionId.jumpToPreviousPrompt,
          TerminalActionId.jumpToNextPrompt,
        ].join(','),
    'view menu contains stable prompt navigation actions in catalog order',
  );
  _expect(
    catalog
                .actionsForMenu(TerminalActionMenu.application)
                .map((TerminalActionDefinition action) => action.id)
                .join(',') ==
            <TerminalActionId>[
              TerminalActionId.openCommandPalette,
              TerminalActionId.openSettings,
              TerminalActionId.reloadConfiguration,
              TerminalActionId.quitApplication,
            ].join(',') &&
        catalog
                .actionForId(TerminalActionId.openSettings)!
                .shortcut
                ?.identity ==
            'command+,' &&
        !catalog
            .actionForId(TerminalActionId.openSettings)!
            .restoresTerminalFocusAfterInvocation &&
        catalog.actionForId(TerminalActionId.reloadConfiguration)!.shortcut ==
            null,
    'Settings and reload have the expected shared application metadata',
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
    dispatcher.search('split down').first.definition.id ==
        TerminalActionId.splitPaneDown,
    'multi-token exact search finds the intended action',
  );
  _expect(
    dispatcher.search('SPLTRGHT').single.definition.id ==
        TerminalActionId.splitPaneRight,
    'case-insensitive subsequence search is deterministic',
  );
  _expect(
    dispatcher.search('clipboard').length == 4 &&
        dispatcher.search('clipboard')[0].definition.id ==
            TerminalActionId.copy &&
        dispatcher.search('clipboard')[1].definition.id ==
            TerminalActionId.paste &&
        dispatcher.search('clipboard')[2].definition.id ==
            TerminalActionId.allowOsc52Clipboard &&
        dispatcher.search('clipboard')[3].definition.id ==
            TerminalActionId.denyOsc52Clipboard,
    'equal keyword matches retain catalog order',
  );
  _expect(
    dispatcher
            .search('prompt')
            .map((snapshot) => snapshot.definition.id)
            .join(',') ==
        <TerminalActionId>[
          TerminalActionId.jumpToPreviousPrompt,
          TerminalActionId.jumpToNextPrompt,
        ].join(','),
    'prompt actions are searchable in stable command-palette order',
  );
  _expect(
    dispatcher.search('effective settings').single.definition.id ==
        TerminalActionId.openSettings,
    'Settings is discoverable through its shared palette metadata',
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

Future<void> _waitFor(bool Function() predicate, String description) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (!predicate() && timeout.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(Duration.zero);
  }
  _expect(predicate(), description);
}

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
