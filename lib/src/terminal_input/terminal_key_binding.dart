import '../terminal_action_registry.dart';
import 'terminal_key_event.dart';

abstract final class TerminalKeyBindingLimits {
  static const int maximumDefinitionCount = 1024;
  static const int maximumConfigurationUnits = 512;
}

/// Stable action IDs accepted by the initial configurable binding engine.
enum TerminalKeyBindingAction {
  sendEndOfFile('terminal.send-end-of-file'),
  sendInterruptSignal('terminal.send-interrupt-signal'),
  sendSuspendSignal('terminal.send-suspend-signal'),
  sendQuitSignal('terminal.send-quit-signal');

  const TerminalKeyBindingAction(this.configName);

  final String configName;

  static TerminalKeyBindingAction? fromConfigName(String value) {
    for (final TerminalKeyBindingAction action in values) {
      if (action.configName == value) {
        return action;
      }
    }
    return null;
  }
}

/// Exact binding identity after non-binding platform provenance is removed.
final class TerminalKeyBindingChord {
  const TerminalKeyBindingChord({
    required this.physicalKey,
    this.shift = false,
    this.control = false,
    this.option = false,
    this.command = false,
  });

  factory TerminalKeyBindingChord.fromEvent(TerminalKeyEvent event) =>
      TerminalKeyBindingChord(
        physicalKey: event.physicalKey,
        shift: event.modifiers.shift,
        control: event.modifiers.control,
        option: event.modifiers.option,
        command: event.modifiers.command,
      );

  final TerminalPhysicalKey physicalKey;
  final bool shift;
  final bool control;
  final bool option;
  final bool command;

  @override
  bool operator ==(Object other) =>
      other is TerminalKeyBindingChord &&
      other.physicalKey == physicalKey &&
      other.shift == shift &&
      other.control == control &&
      other.option == option &&
      other.command == command;

  @override
  int get hashCode => Object.hash(physicalKey, shift, control, option, command);

  @override
  String toString() => <String>[
    if (shift) 'Shift',
    if (control) 'Control',
    if (option) 'Option',
    if (command) 'Command',
    physicalKey.name,
  ].join('+');

  String get configName => <String>[
    if (shift) 'shift',
    if (control) 'control',
    if (option) 'option',
    if (command) 'command',
    TerminalKeyBindingVocabulary.configNameForKey(physicalKey),
  ].join('+');
}

/// Stable configuration names for the physical-key binding surface.
abstract final class TerminalKeyBindingVocabulary {
  static const List<String> modifierConfigNames = <String>[
    'shift',
    'control',
    'option',
    'command',
  ];

  static String configNameForKey(TerminalPhysicalKey key) {
    if (key == TerminalPhysicalKey.unknown) {
      throw ArgumentError.value(key, 'key', 'unknown has no config name');
    }
    final String name = key.name;
    if (name.length == 4 && name.startsWith('key')) {
      return name.substring(3).toLowerCase();
    }
    if (name.length == 6 && name.startsWith('digit')) {
      return name.substring(5);
    }
    if (name.startsWith('arrow')) {
      return _camelToKebab(name.substring(5));
    }
    if (name.startsWith('keypad')) {
      return 'keypad-${_camelToKebab(name.substring(6))}';
    }
    if (name.startsWith('jis')) {
      return 'jis-${_camelToKebab(name.substring(3))}';
    }
    return _camelToKebab(name);
  }

  static TerminalPhysicalKey? keyFromConfigName(String value) {
    for (final TerminalPhysicalKey key in TerminalPhysicalKey.values) {
      if (key != TerminalPhysicalKey.unknown &&
          configNameForKey(key) == value) {
        return key;
      }
    }
    return null;
  }

  static TerminalKeyBindingChord? chordForNativeShortcut(
    TerminalActionShortcut shortcut,
  ) {
    final TerminalPhysicalKey? key = keyFromConfigName(
      _configNameForNativeKeyEquivalent(shortcut.keyEquivalent.toLowerCase()),
    );
    if (key == null) return null;
    return TerminalKeyBindingChord(
      physicalKey: key,
      shift: shortcut.shift,
      control: shortcut.control,
      option: shortcut.option,
      command: shortcut.command,
    );
  }

  static String _configNameForNativeKeyEquivalent(String value) =>
      switch (value) {
        '`' => 'grave',
        '-' => 'minus',
        '=' => 'equal',
        '[' => 'left-bracket',
        ']' => 'right-bracket',
        '\\' => 'backslash',
        ';' => 'semicolon',
        "'" => 'quote',
        ',' => 'comma',
        '.' => 'period',
        '/' => 'slash',
        _ => value,
      };

  static String _camelToKebab(String value) {
    final StringBuffer result = StringBuffer();
    for (var index = 0; index < value.length; index += 1) {
      final int unit = value.codeUnitAt(index);
      if (unit >= 0x41 && unit <= 0x5a) {
        if (index > 0) result.write('-');
        result.writeCharCode(unit + 0x20);
      } else {
        result.writeCharCode(unit);
      }
    }
    return result.toString();
  }
}

enum TerminalKeyBindingDirective { action, unbind, passthrough }

/// One immutable binding definition from a default or override layer.
final class TerminalKeyBindingDefinition {
  const TerminalKeyBindingDefinition.action({
    required this.chord,
    required TerminalKeyBindingAction this.action,
  }) : directive = TerminalKeyBindingDirective.action,
       applicationAction = null;

  const TerminalKeyBindingDefinition.applicationAction({
    required this.chord,
    required TerminalActionId this.applicationAction,
  }) : directive = TerminalKeyBindingDirective.action,
       action = null;

  const TerminalKeyBindingDefinition.unbind({required this.chord})
    : directive = TerminalKeyBindingDirective.unbind,
      action = null,
      applicationAction = null;

  const TerminalKeyBindingDefinition.passthrough({required this.chord})
    : directive = TerminalKeyBindingDirective.passthrough,
      action = null,
      applicationAction = null;

  final TerminalKeyBindingChord chord;
  final TerminalKeyBindingDirective directive;
  final TerminalKeyBindingAction? action;
  final TerminalActionId? applicationAction;

  static const String unbindConfigName = 'unbind';
  static const String passthroughConfigName = 'passthrough';

  String get targetConfigName => switch (directive) {
    TerminalKeyBindingDirective.unbind => unbindConfigName,
    TerminalKeyBindingDirective.passthrough => passthroughConfigName,
    TerminalKeyBindingDirective.action =>
      action?.configName ?? applicationAction!.stableName,
  };

  @override
  bool operator ==(Object other) =>
      other is TerminalKeyBindingDefinition &&
      other.chord == chord &&
      other.directive == directive &&
      other.action == action &&
      other.applicationAction == applicationAction;

  @override
  int get hashCode => Object.hash(chord, directive, action, applicationAction);
}

enum TerminalKeyBindingLayer { defaults, overrides }

final class TerminalKeyBindingConflictException implements Exception {
  const TerminalKeyBindingConflictException({
    required this.layer,
    required this.chord,
    required this.firstIndex,
    required this.secondIndex,
  });

  final TerminalKeyBindingLayer layer;
  final TerminalKeyBindingChord chord;
  final int firstIndex;
  final int secondIndex;

  @override
  String toString() =>
      'TerminalKeyBindingConflictException: duplicate $chord in '
      '${layer.name} at indices $firstIndex and $secondIndex';
}

final class TerminalKeyBindingLimitException implements Exception {
  const TerminalKeyBindingLimitException({
    required this.actualDefinitions,
    required this.maximumDefinitions,
  });

  final int actualDefinitions;
  final int maximumDefinitions;

  @override
  String toString() =>
      'TerminalKeyBindingLimitException: $actualDefinitions definitions; '
      'maximum is $maximumDefinitions';
}

enum TerminalKeyBindingResolutionKind { noMatch, action, passthrough }

final class TerminalKeyBindingResolution {
  const TerminalKeyBindingResolution._(
    this.kind,
    this.action,
    this.applicationAction,
  );

  static const TerminalKeyBindingResolution noMatch =
      TerminalKeyBindingResolution._(
        TerminalKeyBindingResolutionKind.noMatch,
        null,
        null,
      );
  static const TerminalKeyBindingResolution passthrough =
      TerminalKeyBindingResolution._(
        TerminalKeyBindingResolutionKind.passthrough,
        null,
        null,
      );

  factory TerminalKeyBindingResolution.action(
    TerminalKeyBindingAction action,
  ) => TerminalKeyBindingResolution._(
    TerminalKeyBindingResolutionKind.action,
    action,
    null,
  );

  factory TerminalKeyBindingResolution.applicationAction(
    TerminalActionId action,
  ) => TerminalKeyBindingResolution._(
    TerminalKeyBindingResolutionKind.action,
    null,
    action,
  );

  final TerminalKeyBindingResolutionKind kind;
  final TerminalKeyBindingAction? action;
  final TerminalActionId? applicationAction;
}

/// Bounded immutable two-layer keybinding resolver.
///
/// Duplicate chords in one layer are configuration errors. An override action
/// or passthrough replaces a default. An unbind removes the default and leaves
/// the event unmatched, allowing later policy to choose its ordinary behavior.
final class TerminalKeyBindingEngine {
  factory TerminalKeyBindingEngine({
    Iterable<TerminalKeyBindingDefinition> defaults =
        const <TerminalKeyBindingDefinition>[],
    Iterable<TerminalKeyBindingDefinition> overrides =
        const <TerminalKeyBindingDefinition>[],
  }) {
    final List<TerminalKeyBindingDefinition> defaultList = _collectLayer(
      defaults,
      TerminalKeyBindingLayer.defaults,
      consumedBefore: 0,
    );
    final List<TerminalKeyBindingDefinition> overrideList = _collectLayer(
      overrides,
      TerminalKeyBindingLayer.overrides,
      consumedBefore: defaultList.length,
    );
    final Map<TerminalKeyBindingChord, TerminalKeyBindingResolution> bindings =
        <TerminalKeyBindingChord, TerminalKeyBindingResolution>{};
    for (final TerminalKeyBindingDefinition definition in defaultList) {
      _apply(bindings, definition);
    }
    for (final TerminalKeyBindingDefinition definition in overrideList) {
      _apply(bindings, definition);
    }
    return TerminalKeyBindingEngine._(
      Map<TerminalKeyBindingChord, TerminalKeyBindingResolution>.unmodifiable(
        bindings,
      ),
      defaultList.length + overrideList.length,
    );
  }

  factory TerminalKeyBindingEngine.standard({
    Iterable<TerminalKeyBindingDefinition> overrides =
        const <TerminalKeyBindingDefinition>[],
  }) => TerminalKeyBindingEngine(
    defaults: standardDefinitions,
    overrides: overrides,
  );

  /// Applies ordered configuration declarations over the standard defaults.
  ///
  /// Unlike one programmatic layer, later declarations intentionally replace
  /// earlier declarations for the same chord. This mirrors include/root/CLI
  /// precedence while retaining the global definition bound.
  factory TerminalKeyBindingEngine.standardWithOrderedOverrides(
    Iterable<TerminalKeyBindingDefinition> declarations,
  ) {
    final List<TerminalKeyBindingDefinition> collected = _collectOrdered(
      declarations,
      consumedBefore: standardDefinitionCount,
    );
    final Map<TerminalKeyBindingChord, TerminalKeyBindingResolution> bindings =
        <TerminalKeyBindingChord, TerminalKeyBindingResolution>{};
    for (final TerminalKeyBindingDefinition definition in standardDefinitions) {
      _apply(bindings, definition);
    }
    for (final TerminalKeyBindingDefinition definition in collected) {
      _apply(bindings, definition);
    }
    return TerminalKeyBindingEngine._(
      Map<TerminalKeyBindingChord, TerminalKeyBindingResolution>.unmodifiable(
        bindings,
      ),
      standardDefinitionCount + collected.length,
    );
  }

  const TerminalKeyBindingEngine._(this._bindings, this.definitionCount);

  static const int maximumDefinitionCount =
      TerminalKeyBindingLimits.maximumDefinitionCount;
  static const int standardDefinitionCount = 1;
  static const List<TerminalKeyBindingDefinition> standardDefinitions =
      <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.action(
          chord: TerminalKeyBindingChord(
            physicalKey: TerminalPhysicalKey.keyD,
            control: true,
          ),
          action: TerminalKeyBindingAction.sendEndOfFile,
        ),
      ];

  final Map<TerminalKeyBindingChord, TerminalKeyBindingResolution> _bindings;
  final int definitionCount;

  int get activeBindingCount => _bindings.length;

  TerminalKeyBindingResolution resolve(TerminalKeyEvent event) {
    if (event.physicalKey == TerminalPhysicalKey.unknown) {
      return TerminalKeyBindingResolution.noMatch;
    }
    return _bindings[TerminalKeyBindingChord.fromEvent(event)] ??
        TerminalKeyBindingResolution.noMatch;
  }

  static List<TerminalKeyBindingDefinition> _collectLayer(
    Iterable<TerminalKeyBindingDefinition> definitions,
    TerminalKeyBindingLayer layer, {
    required int consumedBefore,
  }) {
    final List<TerminalKeyBindingDefinition> result =
        <TerminalKeyBindingDefinition>[];
    final Map<TerminalKeyBindingChord, int> firstIndices =
        <TerminalKeyBindingChord, int>{};
    for (final TerminalKeyBindingDefinition definition in definitions) {
      if (consumedBefore + result.length >= maximumDefinitionCount) {
        throw TerminalKeyBindingLimitException(
          actualDefinitions: consumedBefore + result.length + 1,
          maximumDefinitions: maximumDefinitionCount,
        );
      }
      if (definition.chord.physicalKey == TerminalPhysicalKey.unknown) {
        throw ArgumentError.value(
          definition.chord,
          '${layer.name}[${result.length}].chord',
          'unknown physical keys cannot be bound',
        );
      }
      final int? firstIndex = firstIndices[definition.chord];
      if (firstIndex != null) {
        throw TerminalKeyBindingConflictException(
          layer: layer,
          chord: definition.chord,
          firstIndex: firstIndex,
          secondIndex: result.length,
        );
      }
      firstIndices[definition.chord] = result.length;
      result.add(definition);
    }
    return List<TerminalKeyBindingDefinition>.unmodifiable(result);
  }

  static List<TerminalKeyBindingDefinition> _collectOrdered(
    Iterable<TerminalKeyBindingDefinition> definitions, {
    required int consumedBefore,
  }) {
    final List<TerminalKeyBindingDefinition> result =
        <TerminalKeyBindingDefinition>[];
    for (final TerminalKeyBindingDefinition definition in definitions) {
      if (consumedBefore + result.length >= maximumDefinitionCount) {
        throw TerminalKeyBindingLimitException(
          actualDefinitions: consumedBefore + result.length + 1,
          maximumDefinitions: maximumDefinitionCount,
        );
      }
      if (definition.chord.physicalKey == TerminalPhysicalKey.unknown) {
        throw ArgumentError.value(
          definition.chord,
          'declarations[${result.length}].chord',
          'unknown physical keys cannot be bound',
        );
      }
      result.add(definition);
    }
    return List<TerminalKeyBindingDefinition>.unmodifiable(result);
  }

  static void _apply(
    Map<TerminalKeyBindingChord, TerminalKeyBindingResolution> bindings,
    TerminalKeyBindingDefinition definition,
  ) {
    switch (definition.directive) {
      case TerminalKeyBindingDirective.action:
        final TerminalKeyBindingAction? paneAction = definition.action;
        bindings[definition.chord] = paneAction != null
            ? TerminalKeyBindingResolution.action(paneAction)
            : TerminalKeyBindingResolution.applicationAction(
                definition.applicationAction!,
              );
      case TerminalKeyBindingDirective.unbind:
        bindings.remove(definition.chord);
      case TerminalKeyBindingDirective.passthrough:
        bindings[definition.chord] = TerminalKeyBindingResolution.passthrough;
    }
  }
}
