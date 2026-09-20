import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalKeyBindingTests();

void runTerminalKeyBindingTests() {
  _testStableActionRegistry();
  _testStablePhysicalKeyVocabulary();
  _testStandardAndExactResolution();
  _testOverrideUnbindAndPassthrough();
  _testOrderedConfigurationOverrides();
  _testConflictValidation();
  _testBoundAndImmutableConstruction();
}

void _testOrderedConfigurationOverrides() {
  const TerminalKeyBindingChord controlD = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.keyD,
    control: true,
  );
  const TerminalKeyBindingChord controlK = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.keyK,
    control: true,
  );
  final TerminalKeyBindingEngine engine =
      TerminalKeyBindingEngine.standardWithOrderedOverrides(
        const <TerminalKeyBindingDefinition>[
          TerminalKeyBindingDefinition.action(
            chord: controlD,
            action: TerminalKeyBindingAction.sendInterruptSignal,
          ),
          TerminalKeyBindingDefinition.unbind(chord: controlD),
          TerminalKeyBindingDefinition.applicationAction(
            chord: controlK,
            applicationAction: TerminalActionId.focusPreviousPane,
          ),
          TerminalKeyBindingDefinition.action(
            chord: controlK,
            action: TerminalKeyBindingAction.sendSuspendSignal,
          ),
        ],
      );
  _expect(
    engine.definitionCount == 15 &&
        engine.resolve(_event(TerminalPhysicalKey.keyD, control: true)).kind ==
            TerminalKeyBindingResolutionKind.noMatch &&
        engine
                .resolve(_event(TerminalPhysicalKey.keyK, control: true))
                .action ==
            TerminalKeyBindingAction.sendSuspendSignal &&
        engine
                .resolve(_event(TerminalPhysicalKey.keyK, control: true))
                .origin ==
            TerminalKeyBindingResolutionOrigin.overrides &&
        engine
                .resolve(_event(TerminalPhysicalKey.arrowLeft, command: true))
                .origin ==
            TerminalKeyBindingResolutionOrigin.defaults,
    'ordered config declarations replace earlier chords over the default',
  );
}

void _testStablePhysicalKeyVocabulary() {
  final List<TerminalPhysicalKey> keys = TerminalPhysicalKey.values
      .where((TerminalPhysicalKey key) => key != TerminalPhysicalKey.unknown)
      .toList(growable: false);
  final Set<String> names = keys
      .map(TerminalKeyBindingVocabulary.configNameForKey)
      .toSet();
  _expect(
    names.length == keys.length &&
        keys.every(
          (TerminalPhysicalKey key) =>
              TerminalKeyBindingVocabulary.keyFromConfigName(
                TerminalKeyBindingVocabulary.configNameForKey(key),
              ) ==
              key,
        ),
    'every non-unknown physical key has one stable round-trip config name',
  );
  _expect(
    TerminalKeyBindingVocabulary.configNameForKey(
              TerminalPhysicalKey.leftBracket,
            ) ==
            'left-bracket' &&
        TerminalKeyBindingVocabulary.configNameForKey(
              TerminalPhysicalKey.keypadEnter,
            ) ==
            'keypad-enter' &&
        TerminalKeyBindingVocabulary.configNameForKey(
              TerminalPhysicalKey.jisUnderscore,
            ) ==
            'jis-underscore' &&
        TerminalKeyBindingVocabulary.chordForNativeShortcut(
              const TerminalActionShortcut(
                keyEquivalent: '\uF703',
                command: true,
              ),
            ) ==
            const TerminalKeyBindingChord(
              physicalKey: TerminalPhysicalKey.arrowRight,
              command: true,
            ) &&
        TerminalKeyBindingVocabulary.keyFromConfigName('unknown') == null,
    'representative key families and native arrows use stable names',
  );
  final List<TerminalActionShortcut> nativeShortcuts =
      TerminalActionCatalog.standard().actions
          .map((TerminalActionDefinition action) => action.shortcut)
          .whereType<TerminalActionShortcut>()
          .toList(growable: false);
  _expect(
    nativeShortcuts
            .map(TerminalKeyBindingVocabulary.chordForNativeShortcut)
            .whereType<TerminalKeyBindingChord>()
            .toSet()
            .length ==
        nativeShortcuts.length,
    'every native menu shortcut has one unique physical collision identity',
  );
  _expectThrowsArgument(
    () => TerminalKeyBindingVocabulary.configNameForKey(
      TerminalPhysicalKey.unknown,
    ),
    'unknown key has no configurable identity',
  );
}

void _testStableActionRegistry() {
  final Set<String> names = TerminalKeyBindingAction.values
      .map((TerminalKeyBindingAction action) => action.configName)
      .toSet();
  _expect(
    names.length == TerminalKeyBindingAction.values.length,
    'action config names are unique',
  );
  for (final TerminalKeyBindingAction action
      in TerminalKeyBindingAction.values) {
    _expect(
      TerminalKeyBindingAction.fromConfigName(action.configName) == action,
      'action ${action.configName} round-trips through the registry',
    );
  }
  _expect(
    TerminalKeyBindingAction.fromConfigName('terminal.unknown') == null,
    'unknown action names are rejected without a fallback',
  );
}

void _testStandardAndExactResolution() {
  final TerminalKeyBindingEngine engine = TerminalKeyBindingEngine.standard();
  final TerminalKeyBindingResolution controlD = engine.resolve(
    _event(TerminalPhysicalKey.keyD, control: true),
  );
  _expect(
    controlD.kind == TerminalKeyBindingResolutionKind.action &&
        controlD.action == TerminalKeyBindingAction.sendEndOfFile,
    'standard Control-D resolves to the tracked EOF action',
  );
  const List<(TerminalPhysicalKey, bool, TerminalActionId)>
  directionalBindings = <(TerminalPhysicalKey, bool, TerminalActionId)>[
    (TerminalPhysicalKey.arrowLeft, false, TerminalActionId.focusPaneLeft),
    (TerminalPhysicalKey.arrowRight, false, TerminalActionId.focusPaneRight),
    (TerminalPhysicalKey.arrowUp, false, TerminalActionId.focusPaneUp),
    (TerminalPhysicalKey.arrowDown, false, TerminalActionId.focusPaneDown),
    (TerminalPhysicalKey.arrowLeft, true, TerminalActionId.moveDividerLeft),
    (TerminalPhysicalKey.arrowRight, true, TerminalActionId.moveDividerRight),
    (TerminalPhysicalKey.arrowUp, true, TerminalActionId.moveDividerUp),
    (TerminalPhysicalKey.arrowDown, true, TerminalActionId.moveDividerDown),
  ];
  _expect(
    directionalBindings.every(
      ((TerminalPhysicalKey, bool, TerminalActionId) binding) =>
          engine
              .resolve(_event(binding.$1, command: true, shift: binding.$2))
              .applicationAction ==
          binding.$3,
    ),
    'Command+arrow focuses panes and Shift+Command+arrow moves dividers',
  );
  const List<(TerminalPhysicalKey, TerminalActionId)> dockBindings =
      <(TerminalPhysicalKey, TerminalActionId)>[
        (
          TerminalPhysicalKey.arrowLeft,
          TerminalActionId.moveContextDockBoundaryLeft,
        ),
        (
          TerminalPhysicalKey.arrowRight,
          TerminalActionId.moveContextDockBoundaryRight,
        ),
      ];
  _expect(
    dockBindings.every(
      ((TerminalPhysicalKey, TerminalActionId) binding) =>
          engine
                  .resolve(_event(binding.$1, control: true, shift: true))
                  .applicationAction ==
              binding.$2 &&
          engine.resolve(_event(binding.$1, control: true)).kind ==
              TerminalKeyBindingResolutionKind.noMatch &&
          engine
                  .resolve(
                    _event(
                      binding.$1,
                      control: true,
                      shift: true,
                      option: true,
                    ),
                  )
                  .kind ==
              TerminalKeyBindingResolutionKind.noMatch,
    ),
    'Dock boundary defaults require exact Control+Shift arrows, not plain Control arrows',
  );
  _expect(
    engine
            .resolve(
              _event(TerminalPhysicalKey.keyD, control: true, shift: true),
            )
            .kind ==
        TerminalKeyBindingResolutionKind.noMatch,
    'binding modifiers match exactly',
  );
  _expect(
    engine
            .resolve(
              _event(
                TerminalPhysicalKey.keyD,
                control: true,
                capsLock: true,
                numericPad: true,
                function: true,
                isRepeat: true,
              ),
            )
            .action ==
        TerminalKeyBindingAction.sendEndOfFile,
    'Caps Lock, keypad/function provenance, and repeat remain non-binding data',
  );
  _expect(
    engine.resolve(_event(TerminalPhysicalKey.unknown)).kind ==
        TerminalKeyBindingResolutionKind.noMatch,
    'unknown physical keys cannot accidentally match',
  );
}

void _testOverrideUnbindAndPassthrough() {
  const TerminalKeyBindingChord controlD = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.keyD,
    control: true,
  );
  final TerminalKeyBindingEngine overridden = TerminalKeyBindingEngine.standard(
    overrides: const <TerminalKeyBindingDefinition>[
      TerminalKeyBindingDefinition.action(
        chord: controlD,
        action: TerminalKeyBindingAction.sendInterruptSignal,
      ),
    ],
  );
  _expect(
    overridden
            .resolve(_event(TerminalPhysicalKey.keyD, control: true))
            .action ==
        TerminalKeyBindingAction.sendInterruptSignal,
    'override action replaces the default deterministically',
  );

  final TerminalKeyBindingEngine unbound = TerminalKeyBindingEngine.standard(
    overrides: const <TerminalKeyBindingDefinition>[
      TerminalKeyBindingDefinition.unbind(chord: controlD),
    ],
  );
  _expect(
    unbound.activeBindingCount == 10 &&
        unbound.resolve(_event(TerminalPhysicalKey.keyD, control: true)).kind ==
            TerminalKeyBindingResolutionKind.noMatch,
    'unbind removes the inherited binding and leaves no match',
  );

  const TerminalKeyBindingChord commandRight = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.arrowRight,
    command: true,
  );
  const TerminalKeyBindingChord shiftCommandRight = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.arrowRight,
    shift: true,
    command: true,
  );
  final TerminalKeyBindingEngine directionalOverrides =
      TerminalKeyBindingEngine.standardWithOrderedOverrides(
        const <TerminalKeyBindingDefinition>[
          TerminalKeyBindingDefinition.applicationAction(
            chord: commandRight,
            applicationAction: TerminalActionId.focusPaneDown,
          ),
          TerminalKeyBindingDefinition.passthrough(chord: shiftCommandRight),
        ],
      );
  _expect(
    directionalOverrides
                .resolve(_event(TerminalPhysicalKey.arrowRight, command: true))
                .applicationAction ==
            TerminalActionId.focusPaneDown &&
        directionalOverrides
                .resolve(
                  _event(
                    TerminalPhysicalKey.arrowRight,
                    shift: true,
                    command: true,
                  ),
                )
                .kind ==
            TerminalKeyBindingResolutionKind.passthrough,
    'directional pane defaults are replaceable and can pass through',
  );

  final TerminalKeyBindingEngine passthrough =
      TerminalKeyBindingEngine.standard(
        overrides: const <TerminalKeyBindingDefinition>[
          TerminalKeyBindingDefinition.passthrough(chord: controlD),
        ],
      );
  _expect(
    passthrough.resolve(_event(TerminalPhysicalKey.keyD, control: true)).kind ==
        TerminalKeyBindingResolutionKind.passthrough,
    'passthrough remains an explicit matched resolution',
  );

  final TerminalKeyBindingEngine applicationAction =
      TerminalKeyBindingEngine.standard(
        overrides: const <TerminalKeyBindingDefinition>[
          TerminalKeyBindingDefinition.applicationAction(
            chord: TerminalKeyBindingChord(
              physicalKey: TerminalPhysicalKey.keyK,
              control: true,
              shift: true,
            ),
            applicationAction: TerminalActionId.focusNextPane,
          ),
        ],
      );
  final TerminalKeyBindingResolution applicationResolution = applicationAction
      .resolve(_event(TerminalPhysicalKey.keyK, control: true, shift: true));
  _expect(
    applicationResolution.kind == TerminalKeyBindingResolutionKind.action &&
        applicationResolution.action == null &&
        applicationResolution.applicationAction ==
            TerminalActionId.focusNextPane &&
        applicationResolution.origin ==
            TerminalKeyBindingResolutionOrigin.overrides,
    'application action targets retain the shared catalog identity',
  );
}

void _testConflictValidation() {
  const TerminalKeyBindingChord chord = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.keyK,
    command: true,
  );
  _expectThrowsConflict(
    () => TerminalKeyBindingEngine(
      defaults: const <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.action(
          chord: chord,
          action: TerminalKeyBindingAction.sendInterruptSignal,
        ),
        TerminalKeyBindingDefinition.passthrough(chord: chord),
      ],
    ),
    TerminalKeyBindingLayer.defaults,
    'duplicate defaults conflict',
  );
  _expectThrowsConflict(
    () => TerminalKeyBindingEngine(
      overrides: const <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.unbind(chord: chord),
        TerminalKeyBindingDefinition.passthrough(chord: chord),
      ],
    ),
    TerminalKeyBindingLayer.overrides,
    'duplicate overrides conflict',
  );
  _expectThrowsArgument(
    () => TerminalKeyBindingEngine(
      defaults: const <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.passthrough(
          chord: TerminalKeyBindingChord(
            physicalKey: TerminalPhysicalKey.unknown,
          ),
        ),
      ],
    ),
    'unknown physical key definition',
  );
}

void _testBoundAndImmutableConstruction() {
  final List<TerminalKeyBindingDefinition> definitions =
      <TerminalKeyBindingDefinition>[
        const TerminalKeyBindingDefinition.action(
          chord: TerminalKeyBindingChord(physicalKey: TerminalPhysicalKey.keyA),
          action: TerminalKeyBindingAction.sendInterruptSignal,
        ),
      ];
  final TerminalKeyBindingEngine engine = TerminalKeyBindingEngine(
    defaults: definitions,
  );
  definitions.clear();
  _expect(
    engine.definitionCount == 1 &&
        engine.activeBindingCount == 1 &&
        engine.resolve(_event(TerminalPhysicalKey.keyA)).kind ==
            TerminalKeyBindingResolutionKind.action,
    'construction copies iterable definitions into immutable state',
  );

  final int keyCount = TerminalPhysicalKey.values.length - 1;
  _expectThrowsLimit(
    () => TerminalKeyBindingEngine(
      defaults: Iterable<TerminalKeyBindingDefinition>.generate(
        TerminalKeyBindingEngine.maximumDefinitionCount + 1,
        (int index) {
          final int modifierBits = index ~/ keyCount;
          return TerminalKeyBindingDefinition.passthrough(
            chord: TerminalKeyBindingChord(
              physicalKey: TerminalPhysicalKey.values[index % keyCount + 1],
              shift: modifierBits & 1 != 0,
              control: modifierBits & 2 != 0,
              option: modifierBits & 4 != 0,
              command: modifierBits & 8 != 0,
            ),
          );
        },
      ),
    ),
    'definition iteration stops at the hard bound',
  );
}

TerminalKeyEvent _event(
  TerminalPhysicalKey key, {
  bool capsLock = false,
  bool shift = false,
  bool control = false,
  bool option = false,
  bool command = false,
  bool numericPad = false,
  bool function = false,
  bool isRepeat = false,
}) => TerminalKeyEvent(
  physicalKey: key,
  modifiers: TerminalKeyModifiers(
    capsLock: capsLock,
    shift: shift,
    control: control,
    option: option,
    command: command,
    numericPad: numericPad,
    function: function,
  ),
  isRepeat: isRepeat,
);

void _expectThrowsConflict(
  void Function() body,
  TerminalKeyBindingLayer layer,
  String description,
) {
  try {
    body();
  } on TerminalKeyBindingConflictException catch (error) {
    _expect(
      error.layer == layer && error.firstIndex == 0 && error.secondIndex == 1,
      '$description reports exact layer and indices',
    );
    return;
  }
  throw StateError('expected binding conflict: $description');
}

void _expectThrowsLimit(void Function() body, String description) {
  try {
    body();
  } on TerminalKeyBindingLimitException catch (error) {
    _expect(
      error.actualDefinitions ==
              TerminalKeyBindingEngine.maximumDefinitionCount + 1 &&
          error.maximumDefinitions ==
              TerminalKeyBindingEngine.maximumDefinitionCount,
      '$description reports exact bounds',
    );
    return;
  }
  throw StateError('expected binding limit: $description');
}

void _expectThrowsArgument(void Function() body, String description) {
  try {
    body();
  } on ArgumentError {
    return;
  }
  throw StateError('expected ArgumentError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal key binding expectation failed: $description');
  }
}
