/// Stable physical positions used by terminal encoding and keybindings.
///
/// Produced text remains separate so keyboard layout and dead-key processing do
/// not have to pretend that a physical key has one fixed character.
enum TerminalPhysicalKey {
  unknown,
  keyA,
  keyB,
  keyC,
  keyD,
  keyE,
  keyF,
  keyG,
  keyH,
  keyI,
  keyJ,
  keyK,
  keyL,
  keyM,
  keyN,
  keyO,
  keyP,
  keyQ,
  keyR,
  keyS,
  keyT,
  keyU,
  keyV,
  keyW,
  keyX,
  keyY,
  keyZ,
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
  grave,
  minus,
  equal,
  leftBracket,
  rightBracket,
  backslash,
  semicolon,
  quote,
  comma,
  period,
  slash,
  section,
  space,
  enter,
  tab,
  backspace,
  escape,
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  home,
  end,
  insert,
  deleteForward,
  pageUp,
  pageDown,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
  f13,
  f14,
  f15,
  f16,
  f17,
  f18,
  f19,
  f20,
  keypad0,
  keypad1,
  keypad2,
  keypad3,
  keypad4,
  keypad5,
  keypad6,
  keypad7,
  keypad8,
  keypad9,
  keypadDecimal,
  keypadEnter,
  keypadAdd,
  keypadSubtract,
  keypadMultiply,
  keypadDivide,
  keypadEquals,
  jisYen,
  jisUnderscore,
  jisKeypadComma,
  jisEisu,
  jisKana,
}

abstract final class TerminalInputLimits {
  static const int maximumEncodedBytesPerKeyEvent = 256;
}

/// Native key-event identity retained through routing and terminal encoding.
enum TerminalKeyEventType { press, repeat, release }

/// Independent modifier fields retained from the platform event.
final class TerminalKeyModifiers {
  const TerminalKeyModifiers({
    this.capsLock = false,
    this.shift = false,
    this.control = false,
    this.option = false,
    this.command = false,
    this.numericPad = false,
    this.function = false,
  });

  final bool capsLock;
  final bool shift;
  final bool control;
  final bool option;
  final bool command;
  final bool numericPad;
  final bool function;

  /// Xterm's legacy modifier parameter: 1 + Shift + 2*Alt + 4*Control.
  int get xtermParameter =>
      1 + (shift ? 1 : 0) + (option ? 2 : 0) + (control ? 4 : 0);

  bool get hasXtermModifier => shift || control || option;

  @override
  bool operator ==(Object other) =>
      other is TerminalKeyModifiers &&
      other.capsLock == capsLock &&
      other.shift == shift &&
      other.control == control &&
      other.option == option &&
      other.command == command &&
      other.numericPad == numericPad &&
      other.function == function;

  @override
  int get hashCode => Object.hash(
    capsLock,
    shift,
    control,
    option,
    command,
    numericPad,
    function,
  );
}

/// Platform-independent key event consumed by the encoder and binding engine.
final class TerminalKeyEvent {
  const TerminalKeyEvent({
    required this.physicalKey,
    this.text = '',
    this.unmodifiedText = '',
    this.modifiers = const TerminalKeyModifiers(),
    TerminalKeyEventType eventType = TerminalKeyEventType.press,
    bool isRepeat = false,
  }) : eventType = isRepeat ? TerminalKeyEventType.repeat : eventType;

  final TerminalPhysicalKey physicalKey;
  final String text;
  final String unmodifiedText;
  final TerminalKeyModifiers modifiers;
  final TerminalKeyEventType eventType;

  /// Compatibility view retained for the original press/repeat-only API.
  bool get isRepeat => eventType == TerminalKeyEventType.repeat;
}
