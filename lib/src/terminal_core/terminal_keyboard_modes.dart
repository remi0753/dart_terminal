/// Terminal-owned keyboard modes that affect host input encoding.
final class TerminalKeyboardModes {
  const TerminalKeyboardModes({
    this.applicationCursorKeys = false,
    this.applicationKeypad = false,
    this.applicationEscape = false,
    this.modifyOtherKeys = 0,
    this.kittyKeyboardFlags = 0,
  });

  static const int kittyDisambiguateEscapeCodes = 1;
  static const int kittyReportEventTypes = 2;
  static const int kittyReportAlternateKeys = 4;
  static const int kittyReportAllKeys = 8;
  static const int kittyReportAssociatedText = 16;
  static const int kittyKnownFlags = 31;

  final bool applicationCursorKeys;
  final bool applicationKeypad;
  final bool applicationEscape;
  final int modifyOtherKeys;
  final int kittyKeyboardFlags;

  @override
  bool operator ==(Object other) =>
      other is TerminalKeyboardModes &&
      other.applicationCursorKeys == applicationCursorKeys &&
      other.applicationKeypad == applicationKeypad &&
      other.applicationEscape == applicationEscape &&
      other.modifyOtherKeys == modifyOtherKeys &&
      other.kittyKeyboardFlags == kittyKeyboardFlags;

  @override
  int get hashCode => Object.hash(
    applicationCursorKeys,
    applicationKeypad,
    applicationEscape,
    modifyOtherKeys,
    kittyKeyboardFlags,
  );
}
