import 'dart:async';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalActionMenuTests();

Future<void> runTerminalActionMenuTests() async {
  _testProjectionValidation();
  await _testDynamicValidationAndExactlyOnceRouting();
  await _testBusyFailureAndDisposal();
}

void _testProjectionValidation() {
  final TerminalActionCatalog catalog = _catalog();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
  );
  _expectThrows<StateError>(
    () => TerminalMenuProjectionController(
      dispatcher: dispatcher,
      bindings: <TerminalMenuEnablementBinding>[
        _binding(TerminalActionId.copy, _FakeEnabledItem()),
      ],
    ),
    'projection requires every catalog action',
  );
  _expectThrows<StateError>(
    () => TerminalMenuProjectionController(
      dispatcher: dispatcher,
      bindings: <TerminalMenuEnablementBinding>[
        _binding(TerminalActionId.copy, _FakeEnabledItem()),
        _binding(TerminalActionId.copy, _FakeEnabledItem()),
        _binding(TerminalActionId.paste, _FakeEnabledItem()),
      ],
    ),
    'projection rejects duplicate item bindings',
  );
  final TerminalActionCatalog copyOnly = TerminalActionCatalog(
    <TerminalActionDefinition>[_definition(TerminalActionId.copy)],
  );
  _expectThrows<ArgumentError>(
    () => TerminalMenuProjectionController(
      dispatcher: TerminalActionDispatcher(catalog: copyOnly),
      bindings: <TerminalMenuEnablementBinding>[
        _binding(TerminalActionId.paste, _FakeEnabledItem()),
      ],
    ),
    'projection rejects an item outside the catalog',
  );
  _expectThrows<StateError>(
    () => TerminalMenuProjectionController(
      dispatcher: dispatcher,
      bindings: <TerminalMenuEnablementBinding>[
        _binding(TerminalActionId.copy, _FakeEnabledItem()),
        _binding(TerminalActionId.paste, _FakeEnabledItem()),
      ],
      checkedBindings: <TerminalMenuCheckedBinding>[
        _checkedBinding(TerminalActionId.copy, _FakeEnabledItem(), () => false),
        _checkedBinding(TerminalActionId.copy, _FakeEnabledItem(), () => true),
      ],
    ),
    'projection rejects duplicate checked bindings',
  );
}

Future<void> _testDynamicValidationAndExactlyOnceRouting() async {
  final TerminalActionCatalog catalog = _catalog();
  var canCopy = false;
  var copyCount = 0;
  var pasteCount = 0;
  var pasteChecked = false;
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        isAvailable: () => canCopy,
        handler: () => copyCount++,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.paste,
        handler: () => pasteCount++,
      ),
    ],
  );
  final _FakeEnabledItem copyItem = _FakeEnabledItem();
  final _FakeEnabledItem pasteItem = _FakeEnabledItem();
  final List<TerminalActionDispatchResult> observations =
      <TerminalActionDispatchResult>[];
  final TerminalMenuProjectionController controller =
      TerminalMenuProjectionController(
        dispatcher: dispatcher,
        bindings: <TerminalMenuEnablementBinding>[
          _binding(TerminalActionId.copy, copyItem),
          _binding(TerminalActionId.paste, pasteItem),
        ],
        checkedBindings: <TerminalMenuCheckedBinding>[
          _checkedBinding(
            TerminalActionId.paste,
            pasteItem,
            () => pasteChecked,
          ),
        ],
        onDispatched: observations.add,
      );
  controller.refresh();
  _expect(
    !copyItem.enabled && pasteItem.enabled,
    'native item enablement reflects current dispatcher availability',
  );
  _expect(
    copyItem.writeCount == 1 &&
        pasteItem.writeCount == 0 &&
        pasteItem.checkedWriteCount == 0,
    'refresh writes only changed native enabled and checked values',
  );
  pasteChecked = true;
  controller.refresh();
  controller.refresh();
  _expect(
    pasteItem.checked && pasteItem.checkedWriteCount == 1,
    'checked projection writes one changed retained mode value',
  );
  final TerminalActionDispatchResult unavailable = await controller.route(
    TerminalActionId.copy,
  );
  _expect(
    unavailable.disposition == TerminalActionDispatchDisposition.unavailable &&
        copyCount == 0 &&
        observations.length == 1,
    'disabled menu route invokes no handler and publishes one result',
  );
  canCopy = true;
  controller.refresh();
  _expect(
    copyItem.enabled && copyItem.writeCount == 2,
    'later context refresh enables the same projected item',
  );
  final TerminalActionDispatchResult executed = await controller.route(
    TerminalActionId.copy,
  );
  _expect(
    executed.disposition == TerminalActionDispatchDisposition.executed &&
        copyCount == 1 &&
        pasteCount == 0 &&
        observations.length == 2,
    'one menu route reaches exactly one selected handler and observation',
  );
}

Future<void> _testBusyFailureAndDisposal() async {
  final TerminalActionCatalog catalog = _catalog();
  final Completer<void> copyGate = Completer<void>();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      TerminalActionRegistration(
        id: TerminalActionId.copy,
        handler: () => copyGate.future,
      ),
      TerminalActionRegistration(
        id: TerminalActionId.paste,
        handler: () => throw StateError('paste failure'),
      ),
    ],
  );
  final _FakeEnabledItem copyItem = _FakeEnabledItem();
  final _FakeEnabledItem pasteItem = _FakeEnabledItem();
  final List<TerminalActionDispatchDisposition> observations =
      <TerminalActionDispatchDisposition>[];
  final TerminalMenuProjectionController controller =
      TerminalMenuProjectionController(
        dispatcher: dispatcher,
        bindings: <TerminalMenuEnablementBinding>[
          _binding(TerminalActionId.copy, copyItem),
          _binding(TerminalActionId.paste, pasteItem),
        ],
        onDispatched: (TerminalActionDispatchResult result) {
          observations.add(result.disposition);
        },
      );
  controller.refresh();
  final Future<TerminalActionDispatchResult> pending = controller.route(
    TerminalActionId.copy,
  );
  await Future<void>.delayed(Duration.zero);
  controller.refresh();
  _expect(
    !copyItem.enabled && !pasteItem.enabled,
    'in-flight action disables all projected mutations',
  );
  final TerminalActionDispatchResult busy = await controller.route(
    TerminalActionId.paste,
  );
  _expect(
    busy.disposition == TerminalActionDispatchDisposition.busy,
    'reentrant menu event is classified busy',
  );
  copyGate.complete();
  _expect(
    (await pending).disposition == TerminalActionDispatchDisposition.executed &&
        copyItem.enabled &&
        pasteItem.enabled,
    'completion refreshes all menu items',
  );
  final TerminalActionDispatchResult failed = await controller.route(
    TerminalActionId.paste,
  );
  _expect(
    failed.disposition == TerminalActionDispatchDisposition.failed &&
        failed.error is StateError &&
        observations.join(',') ==
            <TerminalActionDispatchDisposition>[
              TerminalActionDispatchDisposition.busy,
              TerminalActionDispatchDisposition.executed,
              TerminalActionDispatchDisposition.failed,
            ].join(','),
    'busy, completion, and handler failure each publish one result',
  );
  controller.dispose();
  controller.dispose();
  _expect(controller.isDisposed, 'controller disposal is idempotent');
  _expectThrows<StateError>(
    controller.refresh,
    'disposed projection rejects refresh',
  );
  await _expectFutureThrows<StateError>(
    () => controller.route(TerminalActionId.copy),
    'disposed projection rejects routing',
  );
}

TerminalActionCatalog _catalog() =>
    TerminalActionCatalog(<TerminalActionDefinition>[
      _definition(TerminalActionId.copy),
      _definition(TerminalActionId.paste),
    ]);

TerminalActionDefinition _definition(TerminalActionId id) =>
    TerminalActionDefinition(
      id: id,
      title: id.stableName,
      menu: TerminalActionMenu.edit,
    );

TerminalMenuEnablementBinding _binding(
  TerminalActionId id,
  _FakeEnabledItem item,
) => TerminalMenuEnablementBinding(
  id: id,
  read: () => item.enabled,
  write: (bool value) {
    item.enabled = value;
    item.writeCount++;
  },
);

TerminalMenuCheckedBinding _checkedBinding(
  TerminalActionId id,
  _FakeEnabledItem item,
  bool Function() desired,
) => TerminalMenuCheckedBinding(
  id: id,
  desired: desired,
  read: () => item.checked,
  write: (bool value) {
    item.checked = value;
    item.checkedWriteCount++;
  },
);

final class _FakeEnabledItem {
  bool enabled = true;
  int writeCount = 0;
  bool checked = false;
  int checkedWriteCount = 0;
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

Future<void> _expectFutureThrows<T extends Object>(
  Future<void> Function() body,
  String description,
) async {
  try {
    await body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal action menu expectation failed: $description');
  }
}
