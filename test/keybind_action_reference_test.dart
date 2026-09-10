import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import '../tool/generate_keybind_action_reference.dart';

void main() => runKeybindActionReferenceTests();

void runKeybindActionReferenceTests() {
  final String generated = generateKeybindActionReference();
  final File committed = File(keybindActionReferencePath);
  _expect(
    keybindActionReferenceIsFresh(committed) &&
        committed.readAsStringSync() == generated,
    'committed keybinding/action reference is fresh',
  );

  for (final TerminalPhysicalKey key in TerminalPhysicalKey.values) {
    if (key == TerminalPhysicalKey.unknown) continue;
    final String name = TerminalKeyBindingVocabulary.configNameForKey(key);
    _expect(
      generated.contains('`$name`'),
      'generated reference contains physical key $name',
    );
  }
  for (final TerminalKeyBindingAction action
      in TerminalKeyBindingAction.values) {
    _expect(
      generated.contains('`${action.configName}`'),
      'generated reference contains pane action ${action.configName}',
    );
  }
  for (final TerminalActionDefinition action
      in TerminalActionCatalog.standard().actions) {
    _expect(
      generated.contains('`${action.id.stableName}`') &&
          generated.contains(action.title),
      'generated reference contains application action '
      '${action.id.stableName}',
    );
  }
  for (final TerminalKeyBindingDefinition binding
      in TerminalKeyBindingEngine.standardDefinitions) {
    _expect(
      generated.contains(
        '| `${binding.chord.configName}` | `${binding.targetConfigName}` |',
      ),
      'generated reference contains standard binding '
      '${binding.chord.configName}',
    );
  }
  _expectFailure(
    generated.replaceFirst('# Keybindings and actions', '# Stale reference'),
    generated,
    'modified generated reference',
  );
}

void _expectFailure(String source, String expected, String description) {
  try {
    validateKeybindActionReferenceSource(source, expectedSource: expected);
  } on KeybindActionReferenceException {
    return;
  }
  throw StateError('expected stale reference failure: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('keybinding/action reference test failed: $description');
  }
}
