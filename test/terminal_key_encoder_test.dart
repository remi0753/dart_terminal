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
  _testApplicationEscapeAndModifyOtherKeys();
  _testKittyDisambiguationAndAlternates();
  _testKittyFunctionalAndKeypadMap();
  _testKittyEventTypes();
  _testKittyAllKeysAssociatedTextAndBounds();
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
        modifiers: const TerminalKeyModifiers(option: true, function: true),
      ),
    ),
    '\x1b[D',
    'Option text mode preserves plain Left Arrow navigation',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowRight,
        modifiers: const TerminalKeyModifiers(option: true, function: true),
      ),
    ),
    '\x1b[C',
    'Option text mode preserves plain Right Arrow navigation',
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
        modifiers: const TerminalKeyModifiers(option: true, function: true),
      ),
      modes: const TerminalKeyboardModes(applicationCursorKeys: true),
    ),
    '\x1bb',
    'Option-Left emits Meta-B independent of application cursor mode',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowRight,
        modifiers: const TerminalKeyModifiers(option: true, function: true),
      ),
    ),
    '\x1bf',
    'Option-Right emits Meta-F for shell word navigation',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowLeft,
        modifiers: const TerminalKeyModifiers(
          shift: true,
          option: true,
          function: true,
        ),
      ),
    ),
    '\x1b[1;4D',
    'Option-Shift-Left retains the xterm modifier sequence',
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

void _testApplicationEscapeAndModifyOtherKeys() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.escape),
      modes: const TerminalKeyboardModes(applicationEscape: true),
    ),
    '\x1bO[',
    'application Escape mode emits the unambiguous mintty keycode',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.tab,
        unmodifiedText: '\t',
        modifiers: const TerminalKeyModifiers(option: true),
      ),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 1),
    ),
    '\x1b[27;3;9~',
    'modifyOtherKeys level 1 encodes Alt-Tab',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.period,
        text: '.',
        unmodifiedText: '.',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 1),
    ),
    '\x1b[27;5;46~',
    'modifyOtherKeys level 1 encodes Control keys without a legacy mapping',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: '\x01',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 1),
    ),
    '\x01',
    'modifyOtherKeys level 1 retains well-known Control mappings',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.tab,
        unmodifiedText: '\t',
        modifiers: const TerminalKeyModifiers(shift: true),
      ),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 2),
    ),
    '\x1b[27;2;9~',
    'modifyOtherKeys level 2 includes Shift-Tab',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'A',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(shift: true),
      ),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 2),
    ),
    '\x1b[27;2;65~',
    'modifyOtherKeys carries the shifted keysym codepoint',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.keyA, text: 'a', unmodifiedText: 'a'),
      modes: const TerminalKeyboardModes(modifyOtherKeys: 3),
    ),
    '\x1b[27;1;97~',
    'modifyOtherKeys level 3 includes unmodified ordinary keys',
  );
}

void _testKittyDisambiguationAndAlternates() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  const TerminalKeyboardModes disambiguate = TerminalKeyboardModes(
    kittyKeyboardFlags: TerminalKeyboardModes.kittyDisambiguateEscapeCodes,
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowLeft,
        modifiers: const TerminalKeyModifiers(option: true, function: true),
      ),
      modes: disambiguate,
    ),
    '\x1b[1;3D',
    'Kitty protocol takes precedence over legacy Option word navigation',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.escape), modes: disambiguate),
    '\x1b[27u',
    'Kitty disambiguates Escape',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyI,
        text: '\t',
        unmodifiedText: 'i',
        modifiers: const TerminalKeyModifiers(shift: true, control: true),
      ),
      modes: const TerminalKeyboardModes(
        kittyKeyboardFlags:
            TerminalKeyboardModes.kittyDisambiguateEscapeCodes |
            TerminalKeyboardModes.kittyReportAlternateKeys,
      ),
    ),
    '\x1b[105:73;6u',
    'Kitty uses the unshifted key and reports a distinct shifted alternate',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyC,
        text: 'с',
        unmodifiedText: 'с',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
      modes: const TerminalKeyboardModes(
        kittyKeyboardFlags:
            TerminalKeyboardModes.kittyDisambiguateEscapeCodes |
            TerminalKeyboardModes.kittyReportAlternateKeys,
      ),
    ),
    '\x1b[1089::99;5u',
    'Kitty reports a distinct PC-101 base-layout key',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'a',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(command: true),
      ),
      modes: disambiguate,
    ),
    '\x1b[97;9u',
    'Kitty maps an unconsumed macOS Command event to Super',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: '\x01',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(capsLock: true, control: true),
      ),
      modes: disambiguate,
    ),
    '\x1b[97;5u',
    'Kitty omits lock modifiers from disambiguated text keys',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: '\x01',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(control: true),
      ),
      modes: const TerminalKeyboardModes(
        modifyOtherKeys: 2,
        kittyKeyboardFlags: TerminalKeyboardModes.kittyDisambiguateEscapeCodes,
      ),
    ),
    '\x1b[97;5u',
    'Kitty progressive mode takes precedence over modifyOtherKeys',
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.enter), modes: disambiguate),
    '\r',
    'Enter retains its recovery-safe legacy press encoding',
  );
}

void _testKittyFunctionalAndKeypadMap() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  const TerminalKeyboardModes modes = TerminalKeyboardModes(
    applicationCursorKeys: true,
    applicationKeypad: true,
    kittyKeyboardFlags: TerminalKeyboardModes.kittyDisambiguateEscapeCodes,
  );
  final Map<TerminalPhysicalKey, String> expected =
      <TerminalPhysicalKey, String>{
        TerminalPhysicalKey.insert: '\x1b[2~',
        TerminalPhysicalKey.deleteForward: '\x1b[3~',
        TerminalPhysicalKey.pageUp: '\x1b[5~',
        TerminalPhysicalKey.pageDown: '\x1b[6~',
        TerminalPhysicalKey.arrowUp: '\x1b[A',
        TerminalPhysicalKey.arrowDown: '\x1b[B',
        TerminalPhysicalKey.arrowRight: '\x1b[C',
        TerminalPhysicalKey.arrowLeft: '\x1b[D',
        TerminalPhysicalKey.home: '\x1b[H',
        TerminalPhysicalKey.end: '\x1b[F',
        TerminalPhysicalKey.f1: '\x1b[P',
        TerminalPhysicalKey.f2: '\x1b[Q',
        TerminalPhysicalKey.f3: '\x1b[13~',
        TerminalPhysicalKey.f4: '\x1b[S',
        TerminalPhysicalKey.f5: '\x1b[15~',
        TerminalPhysicalKey.f6: '\x1b[17~',
        TerminalPhysicalKey.f7: '\x1b[18~',
        TerminalPhysicalKey.f8: '\x1b[19~',
        TerminalPhysicalKey.f9: '\x1b[20~',
        TerminalPhysicalKey.f10: '\x1b[21~',
        TerminalPhysicalKey.f11: '\x1b[23~',
        TerminalPhysicalKey.f12: '\x1b[24~',
        for (var index = 0; index < 8; index++)
          TerminalPhysicalKey.values[TerminalPhysicalKey.f13.index + index]:
              '\x1b[${57376 + index}u',
        for (var index = 0; index < 10; index++)
          TerminalPhysicalKey.values[TerminalPhysicalKey.keypad0.index + index]:
              '\x1b[${57399 + index}u',
        TerminalPhysicalKey.keypadDecimal: '\x1b[57409u',
        TerminalPhysicalKey.keypadDivide: '\x1b[57410u',
        TerminalPhysicalKey.keypadMultiply: '\x1b[57411u',
        TerminalPhysicalKey.keypadSubtract: '\x1b[57412u',
        TerminalPhysicalKey.keypadAdd: '\x1b[57413u',
        TerminalPhysicalKey.keypadEnter: '\x1b[57414u',
        TerminalPhysicalKey.keypadEquals: '\x1b[57415u',
        TerminalPhysicalKey.jisKeypadComma: '\x1b[57416u',
      };
  for (final MapEntry<TerminalPhysicalKey, String> entry in expected.entries) {
    _expectBytes(
      encoder.encode(_event(entry.key), modes: modes),
      entry.value,
      'Kitty functional map encodes ${entry.key.name}',
    );
  }
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.f5,
        modifiers: const TerminalKeyModifiers(capsLock: true),
      ),
      modes: modes,
    ),
    '\x1b[15;65~',
    'Kitty reports Caps Lock for non-text functional keys',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keypad1,
        modifiers: const TerminalKeyModifiers(numericPad: true),
      ),
      modes: modes,
    ),
    '\x1b[57400u',
    'numeric-pad event origin is not misreported as active Num Lock',
  );
}

void _testKittyEventTypes() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  const TerminalKeyboardModes eventModes = TerminalKeyboardModes(
    kittyKeyboardFlags: TerminalKeyboardModes.kittyReportEventTypes,
  );
  _expectBytes(
    encoder.encode(_event(TerminalPhysicalKey.arrowUp), modes: eventModes),
    '\x1b[A',
    'Kitty omits the default press event type',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowUp,
        eventType: TerminalKeyEventType.repeat,
      ),
      modes: eventModes,
    ),
    '\x1b[1;1:2A',
    'Kitty reports functional-key repeat',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.arrowUp,
        eventType: TerminalKeyEventType.release,
      ),
      modes: eventModes,
    ),
    '\x1b[1;1:3A',
    'Kitty reports functional-key release',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'a',
        eventType: TerminalKeyEventType.repeat,
      ),
      modes: eventModes,
    ),
    'a',
    'text repeat stays legacy without all-keys reporting',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.keyA,
            text: 'a',
            eventType: TerminalKeyEventType.release,
          ),
          modes: eventModes,
        )
        .isEmpty,
    'text release is suppressed without all-keys reporting',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.enter,
            eventType: TerminalKeyEventType.release,
          ),
          modes: eventModes,
        )
        .isEmpty,
    'Enter release is suppressed without all-keys reporting',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.arrowUp,
            eventType: TerminalKeyEventType.release,
          ),
        )
        .isEmpty,
    'legacy mode suppresses release events',
  );
}

void _testKittyAllKeysAssociatedTextAndBounds() {
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  const int allFlags =
      TerminalKeyboardModes.kittyReportEventTypes |
      TerminalKeyboardModes.kittyReportAlternateKeys |
      TerminalKeyboardModes.kittyReportAllKeys |
      TerminalKeyboardModes.kittyReportAssociatedText;
  const TerminalKeyboardModes modes = TerminalKeyboardModes(
    kittyKeyboardFlags: allFlags,
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'A',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(shift: true),
      ),
      modes: modes,
    ),
    '\x1b[97:65;2;65u',
    'all-keys mode carries shifted alternate and associated text',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.unknown, text: '日本', unmodifiedText: ''),
      modes: modes,
    ),
    '\x1b[0;1;26085:26412u',
    'pure multi-codepoint text uses key zero and associated codepoints',
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalPhysicalKey.keyA, text: 'a\n', unmodifiedText: 'a'),
      modes: modes,
    ),
    '\x1b[97u',
    'associated text containing a control code is omitted atomically',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'a',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(capsLock: true),
        eventType: TerminalKeyEventType.repeat,
      ),
      modes: modes,
    ),
    '\x1b[97;65:2;97u',
    'all-keys repeat includes lock state, event type, and text',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'a',
        unmodifiedText: 'a',
        eventType: TerminalKeyEventType.release,
      ),
      modes: modes,
    ),
    '\x1b[97;1:3u',
    'all-keys release excludes associated text',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.keyA,
        text: 'a',
        unmodifiedText: 'a',
        modifiers: const TerminalKeyModifiers(command: true),
      ),
      modes: modes,
    ),
    '\x1b[97;9u',
    'Super prevents non-produced text from becoming associated text',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalPhysicalKey.enter,
        eventType: TerminalKeyEventType.release,
      ),
      modes: modes,
    ),
    '\x1b[13;1:3u',
    'all-keys mode enables Enter release',
  );
  _expect(
    encoder
        .encode(
          _event(
            TerminalPhysicalKey.jisEisu,
            eventType: TerminalKeyEventType.release,
          ),
          modes: modes,
        )
        .isEmpty,
    'a physical key without a protocol key code fails closed',
  );
  _expectThrowsLimit(
    () => TerminalKeyEncoder(maximumEncodedBytes: 32).encode(
      _event(
        TerminalPhysicalKey.unknown,
        text: List<String>.filled(20, '界').join(),
      ),
      modes: modes,
    ),
    'oversized associated text remains bounded',
  );
}

TerminalKeyEvent _event(
  TerminalPhysicalKey physicalKey, {
  String text = '',
  String? unmodifiedText,
  TerminalKeyModifiers modifiers = const TerminalKeyModifiers(),
  bool isRepeat = false,
  TerminalKeyEventType eventType = TerminalKeyEventType.press,
}) => TerminalKeyEvent(
  physicalKey: physicalKey,
  text: text,
  unmodifiedText: unmodifiedText ?? text,
  modifiers: modifiers,
  isRepeat: isRepeat,
  eventType: eventType,
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
