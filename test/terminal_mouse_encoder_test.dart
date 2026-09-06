import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalMouseEncoderTests();

void runTerminalMouseEncoderTests() {
  _testMouseModeParsingQueryResetAndExclusivity();
  _testTrackingEligibilityAndButtonMapping();
  _testLegacyAndUtf8Encoding();
  _testSgrAndUrxvtEncoding();
  _testValidationAndBounds();
}

void _testMouseModeParsingQueryResetAndExclusivity() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final List<String> replies = <String>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List bytes) {
      replies.add(ascii.decode(bytes));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);

  parser.parse(ascii.encode('\x1b[?9h\x1b[?1000h\x1b[?1005h\x1b[?1006h'));
  _expect(
    screens.mouseModes ==
        const TerminalMouseModes(
          tracking: TerminalMouseTrackingMode.normal,
          encoding: TerminalMouseCoordinateEncoding.sgr,
        ),
    'new tracking/encoding DECSET replaces its family predecessor',
  );
  parser.parse(
    ascii.encode(
      '\x1b[?9\$p\x1b[?1000\$p\x1b[?1005\$p\x1b[?1006\$p'
      '\x1b[?1015\$p',
    ),
  );
  _expect(
    replies.join() ==
        '\x1b[?9;2\$y\x1b[?1000;1\$y\x1b[?1005;2\$y'
            '\x1b[?1006;1\$y\x1b[?1015;2\$y',
    'DECRQM reports each recognized mouse mode independently',
  );

  parser.parse(ascii.encode('\x1b[?9l\x1b[?1005l'));
  _expect(
    screens.mouseModes ==
        const TerminalMouseModes(
          tracking: TerminalMouseTrackingMode.normal,
          encoding: TerminalMouseCoordinateEncoding.sgr,
        ),
    'resetting non-current family members is a no-op',
  );
  screens.setAlternateMode47(true);
  screens.resize(rows: 3, columns: 5);
  _expect(
    screens.mouseModes.tracking == TerminalMouseTrackingMode.normal &&
        screens.mouseModes.encoding == TerminalMouseCoordinateEncoding.sgr,
    'mouse modes survive alternate-screen activation and resize',
  );
  parser.parse(ascii.encode('\x1b[?1000l\x1b[?1006l'));
  _expect(
    screens.mouseModes == const TerminalMouseModes(),
    'current DEC mouse modes return to defaults',
  );
  parser.parse(ascii.encode('\x1b[?1003h\x1b[?1015h\x1bc'));
  _expect(
    screens.mouseModes == const TerminalMouseModes() &&
        sink.unsupportedSequenceCount == 0,
    'RIS resets mouse state without unsupported input',
  );
}

void _testTrackingEligibilityAndButtonMapping() {
  const TerminalMouseEncoder encoder = TerminalMouseEncoder();
  final TerminalMouseEvent press = _event(TerminalMouseEventKind.press);
  final TerminalMouseEvent release = _event(TerminalMouseEventKind.release);
  final TerminalMouseEvent drag = _event(TerminalMouseEventKind.motion);
  final TerminalMouseEvent move = _event(
    TerminalMouseEventKind.motion,
    button: TerminalMouseButton.none,
  );
  _expect(
    !encoder.shouldReport(press, const TerminalMouseModes()) &&
        encoder.shouldReport(
          press,
          const TerminalMouseModes(tracking: TerminalMouseTrackingMode.x10),
        ) &&
        !encoder.shouldReport(
          release,
          const TerminalMouseModes(tracking: TerminalMouseTrackingMode.x10),
        ) &&
        !encoder.shouldReport(
          drag,
          const TerminalMouseModes(tracking: TerminalMouseTrackingMode.normal),
        ) &&
        encoder.shouldReport(
          drag,
          const TerminalMouseModes(
            tracking: TerminalMouseTrackingMode.buttonEvent,
          ),
        ) &&
        !encoder.shouldReport(
          move,
          const TerminalMouseModes(
            tracking: TerminalMouseTrackingMode.buttonEvent,
          ),
        ) &&
        encoder.shouldReport(
          move,
          const TerminalMouseModes(
            tracking: TerminalMouseTrackingMode.anyEvent,
          ),
        ),
    'tracking modes admit only their specified event kinds',
  );
  _expect(
    TerminalMouseButton.fromAppKitButton(0) == TerminalMouseButton.left &&
        TerminalMouseButton.fromAppKitButton(1) == TerminalMouseButton.right &&
        TerminalMouseButton.fromAppKitButton(2) == TerminalMouseButton.middle &&
        TerminalMouseButton.fromAppKitButton(3) == null,
    'AppKit buttons map to xterm left/right/middle order',
  );
}

void _testLegacyAndUtf8Encoding() {
  const TerminalMouseEncoder encoder = TerminalMouseEncoder();
  const TerminalMouseModes normal = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
  );
  _expectBytes(
    encoder.encode(_event(TerminalMouseEventKind.press), normal),
    <int>[0x1b, 0x5b, 0x4d, 0x20, 0x21, 0x21],
    'legacy left press uses 1-based biased bytes',
  );
  _expectBytes(
    encoder.encode(
      _event(
        TerminalMouseEventKind.press,
        button: TerminalMouseButton.right,
        modifiers: const TerminalMouseModifiers(
          shift: true,
          option: true,
          control: true,
        ),
      ),
      normal,
    ),
    <int>[0x1b, 0x5b, 0x4d, 0x3e, 0x21, 0x21],
    'legacy press maps right and all supported modifiers',
  );
  _expectBytes(
    encoder.encode(_event(TerminalMouseEventKind.release), normal),
    <int>[0x1b, 0x5b, 0x4d, 0x23, 0x21, 0x21],
    'legacy release uses button 3',
  );
  const TerminalMouseModes utf8Mode = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.utf8,
  );
  _expectBytes(
    encoder.encode(
      _event(TerminalMouseEventKind.press, column: 96, row: 2015),
      utf8Mode,
    ),
    <int>[0x1b, 0x5b, 0x4d, 0x20, 0xc2, 0x80, 0xdf, 0xbf],
    'UTF-8 coordinates encode extended scalar boundaries',
  );
}

void _testSgrAndUrxvtEncoding() {
  const TerminalMouseEncoder encoder = TerminalMouseEncoder();
  const TerminalMouseModes sgr = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.anyEvent,
    encoding: TerminalMouseCoordinateEncoding.sgr,
  );
  _expectAscii(
    encoder.encode(
      _event(TerminalMouseEventKind.press, column: 4, row: 7),
      sgr,
    ),
    '\x1b[<0;4;7M',
    'SGR press uses unbiased decimal button and M',
  );
  _expectAscii(
    encoder.encode(
      _event(
        TerminalMouseEventKind.release,
        button: TerminalMouseButton.right,
        column: 4,
        row: 7,
      ),
      sgr,
    ),
    '\x1b[<2;4;7m',
    'SGR release retains its button and uses m',
  );
  _expectAscii(
    encoder.encode(
      _event(
        TerminalMouseEventKind.motion,
        button: TerminalMouseButton.none,
        column: 4,
        row: 7,
      ),
      sgr,
    ),
    '\x1b[<35;4;7M',
    'SGR any-motion uses no-button plus motion flag',
  );
  const TerminalMouseModes urxvt = TerminalMouseModes(
    tracking: TerminalMouseTrackingMode.normal,
    encoding: TerminalMouseCoordinateEncoding.urxvt,
  );
  _expectAscii(
    encoder.encode(
      _event(TerminalMouseEventKind.press, column: 4096, row: 4096),
      urxvt,
    ),
    '\x1b[32;4096;4096M',
    'URXVT supports the terminal screen coordinate bound',
  );
  _expectAscii(
    encoder.encode(
      _event(TerminalMouseEventKind.release, column: 4, row: 7),
      urxvt,
    ),
    '\x1b[35;4;7M',
    'URXVT release uses legacy button 3 plus bias',
  );
}

void _testValidationAndBounds() {
  const TerminalMouseEncoder encoder = TerminalMouseEncoder();
  _expectThrows<ArgumentError>(
    () => TerminalMouseEvent(
      kind: TerminalMouseEventKind.press,
      button: TerminalMouseButton.none,
      column: 1,
      row: 1,
    ),
    'press requires a physical button',
  );
  _expectThrows<RangeError>(
    () => _event(TerminalMouseEventKind.press, column: 0),
    'coordinates are 1-based',
  );
  _expectThrows<RangeError>(
    () => _event(TerminalMouseEventKind.press, row: 4097),
    'coordinates are bounded by the terminal grid contract',
  );
  _expectThrows<TerminalMouseEncodingLimitException>(
    () => encoder.encode(
      _event(TerminalMouseEventKind.press, column: 224),
      const TerminalMouseModes(tracking: TerminalMouseTrackingMode.normal),
    ),
    'legacy encoding fails closed beyond coordinate 223',
  );
  _expectThrows<TerminalMouseEncodingLimitException>(
    () => encoder.encode(
      _event(TerminalMouseEventKind.press, row: 2016),
      const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.normal,
        encoding: TerminalMouseCoordinateEncoding.utf8,
      ),
    ),
    'UTF-8 encoding fails closed beyond coordinate 2015',
  );
  _expectThrows<ArgumentError>(
    () => TerminalScreenSet(
      rows: 1,
      columns: 1,
    ).setMouseTrackingMode(TerminalMouseTrackingMode.none, true),
    'default tracking cannot masquerade as a DECSET mode',
  );
}

TerminalMouseEvent _event(
  TerminalMouseEventKind kind, {
  TerminalMouseButton button = TerminalMouseButton.left,
  int column = 1,
  int row = 1,
  TerminalMouseModifiers modifiers = const TerminalMouseModifiers(),
}) => TerminalMouseEvent(
  kind: kind,
  button: button,
  column: column,
  row: row,
  modifiers: modifiers,
);

void _expectBytes(Uint8List actual, List<int> expected, String message) {
  _expect(actual.toString() == expected.toString(), message);
}

void _expectAscii(Uint8List actual, String expected, String message) {
  _expectBytes(actual, ascii.encode(expected), message);
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
