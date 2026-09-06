/// Terminal-owned legacy keyboard modes that affect host input encoding.
final class TerminalKeyboardModes {
  const TerminalKeyboardModes({
    this.applicationCursorKeys = false,
    this.applicationKeypad = false,
  });

  final bool applicationCursorKeys;
  final bool applicationKeypad;

  @override
  bool operator ==(Object other) =>
      other is TerminalKeyboardModes &&
      other.applicationCursorKeys == applicationCursorKeys &&
      other.applicationKeypad == applicationKeypad;

  @override
  int get hashCode => Object.hash(applicationCursorKeys, applicationKeypad);
}
