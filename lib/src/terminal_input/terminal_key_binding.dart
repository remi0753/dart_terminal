import 'terminal_key_event.dart';

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
}

enum TerminalKeyBindingDirective { action, unbind, passthrough }

/// One immutable binding definition from a default or override layer.
final class TerminalKeyBindingDefinition {
  const TerminalKeyBindingDefinition.action({
    required this.chord,
    required TerminalKeyBindingAction this.action,
  }) : directive = TerminalKeyBindingDirective.action;

  const TerminalKeyBindingDefinition.unbind({required this.chord})
    : directive = TerminalKeyBindingDirective.unbind,
      action = null;

  const TerminalKeyBindingDefinition.passthrough({required this.chord})
    : directive = TerminalKeyBindingDirective.passthrough,
      action = null;

  final TerminalKeyBindingChord chord;
  final TerminalKeyBindingDirective directive;
  final TerminalKeyBindingAction? action;
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
  const TerminalKeyBindingResolution._(this.kind, this.action);

  static const TerminalKeyBindingResolution noMatch =
      TerminalKeyBindingResolution._(
        TerminalKeyBindingResolutionKind.noMatch,
        null,
      );
  static const TerminalKeyBindingResolution passthrough =
      TerminalKeyBindingResolution._(
        TerminalKeyBindingResolutionKind.passthrough,
        null,
      );

  factory TerminalKeyBindingResolution.action(
    TerminalKeyBindingAction action,
  ) => TerminalKeyBindingResolution._(
    TerminalKeyBindingResolutionKind.action,
    action,
  );

  final TerminalKeyBindingResolutionKind kind;
  final TerminalKeyBindingAction? action;
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
    defaults: const <TerminalKeyBindingDefinition>[
      TerminalKeyBindingDefinition.action(
        chord: TerminalKeyBindingChord(
          physicalKey: TerminalPhysicalKey.keyD,
          control: true,
        ),
        action: TerminalKeyBindingAction.sendEndOfFile,
      ),
    ],
    overrides: overrides,
  );

  const TerminalKeyBindingEngine._(this._bindings, this.definitionCount);

  static const int maximumDefinitionCount = 1024;

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

  static void _apply(
    Map<TerminalKeyBindingChord, TerminalKeyBindingResolution> bindings,
    TerminalKeyBindingDefinition definition,
  ) {
    switch (definition.directive) {
      case TerminalKeyBindingDirective.action:
        bindings[definition.chord] = TerminalKeyBindingResolution.action(
          definition.action!,
        );
      case TerminalKeyBindingDirective.unbind:
        bindings.remove(definition.chord);
      case TerminalKeyBindingDirective.passthrough:
        bindings[definition.chord] = TerminalKeyBindingResolution.passthrough;
    }
  }
}
