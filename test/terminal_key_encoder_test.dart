import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalKeyEncoderTests();

void runTerminalKeyEncoderTests() {
  _testKeyboardModeParsingAndReset();
  _testTextControlAndBounds();
  _testCursorNavigationAndModifiers();
  _testFunctionAndKeypadFamilies();
  _testBasicKeysAndRepeat();
  _testOptionTextBehavior();
}

void _testKeyboardModeParsingAndReset() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final List<List<int>> replies = <List<int>>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List bytes) {
      replies.add(bytes);
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);

  parser.parse(ascii.encode('\x1b[?1h\x1b=\x1b[?1\$p'));
  _expect(
    screens.keyboardModes ==
            const TerminalKeyboardModes(
              applicationCursorKeys: true,
              applicationKeypad: true,
            ) &&
        sink.unsupportedSequenceCount == 0,
    'DECCKM and DECPAM update keyboard modes without unsupported input',
  );
  _expectBytes(
    Uint8List.fromList(replies.single),
    '\x1b[?1;1\$y',
    'DECRQM reports application cursor mode as set',
  );
  screens.setAlternateMode47(true);
  screens.resize(rows: 3, columns: 5);
  _expect(
    screens.keyboardModes ==
        const TerminalKeyboardModes(
          applicationCursorKeys: true,
          applicationKeypad: true,
        ),
    'keyboard modes survive alternate-screen activation and resize',
  );

  parser.parse(ascii.encode('\x1b[?1l\x1b>'));
  _expect(
    screens.keyboardModes == const TerminalKeyboardModes(),
    'DECCKM reset and DECPNM restore normal keyboard modes',
  );

  parser.parse(ascii.encode('\x1b[?1h\x1b=\x1bc'));
  _expect(
    screens.keyboardModes == const TerminalKeyboardModes(),
    'RIS resets both keyboard modes',
  );
}

void _testTextControlAndBounds() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.keyA, text: 'a')),
    'a',
    'produced layout text is encoded',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.unknown, text: '日本語')),
    '日本語',
    'Unicode produced text is UTF-8 encoded',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: '\x01',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
    ),
    '\x01',
    'Control-A maps from unmodified layout text',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.space,
        unmodifiedText: ' ',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
    ),
    '\x00',
    'Control-Space maps to NUL',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyX,
        text: 'x',
        unmodifiedText: 'x',
        modifiers: const TerminalKeyModifiers(option: true),
      ),
    ),
    '\x1bx',
    'Option prefixes produced text with Escape',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.keyX,
            text: 'x',
            modifiers: const TerminalKeyModifiers(command: true),
          ),
        )
        .isEmpty,
    'Command input has no default terminal bytes',
  );
  _expect(
    encoder
        .encode(_event(TerminalPhysicalKey.unknown, text: '\uf700\x07'))
        .isEmpty,
    'AppKit function placeholders and control text are filtered',
  );
  _expectThrowsLimit(
    () =>
        TerminalKeyEncoder(maximumEncodedBytes: 4)
            .encode(_event(TerminalPhysicalKey.unknown, text: '12345')),
    'oversized produced text is rejected before PTY ownership',
  );
  _expectThrowsRange(
    () => TerminalKeyEncoder(maximumEncodedBytes: 0),
    'nonpositive encoder bounds are rejected',
  );
  _expectThrowsRange(
    () => TerminalKeyEncoder(
      maximumEncodedBytes:
          TerminalInputLimits.maximumEncodedBytesPerKeyEvent + 1,
    ),
    'encoder bounds cannot exceed the product pane input limit',
  );
}

void _testOptionTextBehavior() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder(
    optionKeyBehavior: TerminalOptionKeyBehavior.text,
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'å',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(option: true),
      ),
    ),
    'å',
    'Option text mode preserves composed layout text without Escape',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowLeft,
        modifiers: const TerminalKeyModifiers(option: true, shift: true),
      ),
    ),
    '\x1b[1;2D',
    'Option text mode removes Alt from xterm special-key modifiers',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.keyA,
            text: 'å',
            modifiers: const TerminalKeyModifiers(option: true, command: true),
          ),
        )
        .isEmpty,
    'Option text mode does not weaken Command arbitration',
  );
}

void _testCursorNavigationAndModifiers() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.arrowUp)),
    '\x1b[A',
    'normal cursor key uses CSI',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.arrowUp),
      modes: const TerminalKeyboardModes(applicationCursorKeys: true),
    ),
    '\x1bOA',
    'application cursor key uses SS3',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowLeft,
        modifiers: const TerminalKeyModifiers(shift: true),
      ),
      modes: const TerminalKeyboardModes(applicationCursorKeys: true),
    ),
    '\x1b[1;2D',
    'modified cursor key uses xterm CSI independent of application mode',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.end,
        modifiers: const TerminalKeyModifiers(control: true, option: true),
      ),
    ),
    '\x1b[1;7F',
    'combined modifier parameter is deterministic',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.deleteForward)),
    '\x1b[3~',
    'Delete uses the edit-key family',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.pageDown,
        modifiers: const TerminalKeyModifiers(shift: true, control: true),
      ),
    ),
    '\x1b[6;6~',
    'modified Page Down carries the xterm modifier parameter',
  );
}

void _testFunctionAndKeypadFamilies() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.f1)),
    '\x1bOP',
    'F1 uses SS3',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.f4,
        modifiers: const TerminalKeyModifiers(option: true),
      ),
    ),
    '\x1b[1;3S',
    'modified F4 uses CSI modifier form',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.f12)),
    '\x1b[24~',
    'F12 uses the tilde family',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.keypad1)),
    '1',
    'normal keypad emits its character',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.keypad1),
      modes: const TerminalKeyboardModes(applicationKeypad: true),
    ),
    '\x1bOq',
    'application keypad digit uses SS3',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.keypadEnter),
      modes: const TerminalKeyboardModes(applicationKeypad: true),
    ),
    '\x1bOM',
    'application keypad Enter uses SS3 M',
  );
}

void _testBasicKeysAndRepeat() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.enter)),
    '\r',
    'Return emits carriage return',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.tab)),
    '\t',
    'Tab emits horizontal tab',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.tab,
        modifiers: const TerminalKeyModifiers(shift: true),
      ),
    ),
    '\x1b[Z',
    'Shift-Tab emits backtab',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.backspace,
        modifiers: const TerminalKeyModifiers(control: true),
      ),
    ),
    '\x08',
    'Control-Backspace emits BS',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.escape)),
    '\x1b',
    'Escape emits ESC',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.keyA, text: 'a', isRepeat: true)),
    'a',
    'repeat remains event data and encodes one repeat event once',
  );
}

TerminalKeyEvent _event(
  TerminalPhysicalKey physicalKey, {
  String text = '',
  String? unmodifiedText,
  TerminalKeyModifiers modifiers = const TerminalKeyModifiers(),
  bool isRepeat = false,
}) => TerminalKeyEvent(
  physicalKey: physicalKey,
  text: text,
  unmodifiedText: unmodifiedText ?? text,
  modifiers: modifiers,
  isRepeat: isRepeat,
);

void _expectBytes(Uint8List actual, String expected, String description) {
  final List<int> expectedBytes = utf8.encode(expected);
  _expect(
    actual.length == expectedBytes.length &&
        List<int>.generate(
          actual.length,
          (int index) => index,
        ).every((int index) => actual[index] == expectedBytes[index]),
    '$description: expected=$expectedBytes actual=${actual.toList()}',
  );
}

void _expectThrowsLimit(void Function() body, String description) {
  try {
    body();
  } on TerminalKeyEncodingLimitException {
    return;
  }
  throw StateError('expected TerminalKeyEncodingLimitException: $description');
}

void _expectThrowsRange(void Function() body, String description) {
  try {
    body();
  } on RangeError {
    return;
  }
  throw StateError('expected RangeError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('terminal key encoder expectation failed: $description');
  }
}
