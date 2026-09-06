import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalReplyTests();

void runTerminalReplyTests() {
  _testBoundedSemanticEncoder();
  _testDeviceStatusAndModeQueries();
  _testOriginRelativeCursorReports();
  _testOscColorQueriesAndTerminators();
  _testXtgettcapExplicitNegativePolicy();
  _testReplyRejectionAndMalformedRecovery();
  _testQueryChunkIndependence();
}

void _testBoundedSemanticEncoder() {
  _expectBytes(
    TerminalReplyEncoder.primaryDeviceAttributes(),
    '\x1b[?62;22c',
    'primary DA advertises only VT220 ANSI color',
  );
  _expectBytes(
    TerminalReplyEncoder.secondaryDeviceAttributes(),
    '\x1b[>1;0;0c',
    'secondary DA has a fixed VT220 product tuple',
  );
  _expectBytes(
    TerminalReplyEncoder.terminalStatusOk(),
    '\x1b[0n',
    'terminal status report',
  );
  _expectBytes(
    TerminalReplyEncoder.xtgettcapNotFound(),
    '\x1bP0+r\x1b\\',
    'XTGETTCAP absent-capability report',
  );
  final Uint8List maximumCursor = TerminalReplyEncoder.cursorPosition(
    row: TerminalReplyEncoder.maximumCoordinate,
    column: TerminalReplyEncoder.maximumCoordinate,
    decPrivate: true,
  );
  _expectBytes(maximumCursor, '\x1b[?65535;65535R', 'maximum DEC cursor reply');
  _expectBytes(
    TerminalReplyEncoder.modeReport(
      mode: TerminalReplyEncoder.maximumMode,
      status: TerminalModeReportStatus.permanentlyReset,
      decPrivate: true,
    ),
    '\x1b[?2147483647;4\x24y',
    'maximum DEC mode reply',
  );
  _expectBytes(
    TerminalReplyEncoder.paletteColor(
      index: 255,
      color: 0x80abcdef,
      terminator: VtStringTerminator.stringTerminator,
    ),
    '\x1b]4;255;rgb:abab/cdcd/efef\x1b\\',
    'palette color reply expands eight-bit components to sixteen bits',
  );
  _expectBytes(
    TerminalReplyEncoder.defaultColor(
      command: 10,
      color: 0x80010203,
      terminator: VtStringTerminator.bell,
    ),
    '\x1b]10;rgb:0101/0202/0303\x07',
    'default color reply preserves BEL',
  );
  _expect(
    maximumCursor.length <= TerminalReplyEncoder.maximumReplyBytes,
    'every semantic reply remains under the fixed byte limit',
  );

  final Uint8List first = TerminalReplyEncoder.terminalStatusOk();
  final Uint8List second = TerminalReplyEncoder.terminalStatusOk();
  first[0] = 0;
  _expect(
    second[0] == 0x1b,
    'each encoded reply owns an independently retainable buffer',
  );
  _expectThrows(
    () => TerminalReplyEncoder.cursorPosition(row: 0, column: 1),
    RangeError,
    'zero cursor row',
  );
  _expectThrows(
    () => TerminalReplyEncoder.modeReport(
      mode: TerminalReplyEncoder.maximumMode + 1,
      status: TerminalModeReportStatus.set,
    ),
    RangeError,
    'oversized mode',
  );
  _expectThrows(
    () => TerminalReplyEncoder.paletteColor(
      index: 256,
      color: 0x80000000,
      terminator: VtStringTerminator.bell,
    ),
    RangeError,
    'oversized palette index',
  );
  _expectThrows(
    () => TerminalReplyEncoder.paletteColor(
      index: 0,
      color: 0x00ffffff,
      terminator: VtStringTerminator.bell,
    ),
    ArgumentError,
    'untagged palette color',
  );
  _expectThrows(
    () => TerminalReplyEncoder.defaultColor(
      command: 12,
      color: 0x80000000,
      terminator: VtStringTerminator.bell,
    ),
    ArgumentError,
    'unsupported default color command',
  );
}

void _testXtgettcapExplicitNegativePolicy() {
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(_bytes('\x1bP+q4D73\x1b\\X'));
  parser.finish();
  _expectStrings(replies, const <String>[
    '\x1bP0+r\x1b\\',
  ], 'the OSC 52 Ms query is explicitly unavailable');
  _expect(
    sink.acceptedReplyCount == 1 &&
        sink.unsupportedSequenceCount == 0 &&
        screen.contentAt(0, 0) == 0x58,
    'recognized XTGETTCAP recovers to printable input',
  );

  final TerminalScreenParserSink parameterized = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (_) => true,
  );
  final VtParser parameterizedParser = VtParser(sink: parameterized);
  parameterizedParser.parse(_bytes('\x1bP1+q4D73\x1b\\'));
  parameterizedParser.finish();
  _expect(
    parameterized.unsupportedSequenceCount == 1 &&
        parameterized.acceptedReplyCount == 0,
    'parameterized DCS remains outside the reviewed XTGETTCAP selector',
  );

  final List<Uint8List> boundedReplies = <Uint8List>[];
  final TerminalScreenParserSink bounded = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (Uint8List reply) {
      boundedReplies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser boundedParser = VtParser(sink: bounded);
  boundedParser.parse(
    _bytes(
      '\x1bP+q\x1b\\'
      '\x1bP+q4\x1b\\'
      '\x1bP+q4G\x1b\\'
      '\x1bP+q4D73;544E\x1b\\',
    ),
  );
  boundedParser.finish();
  _expect(
    bounded.unsupportedSequenceCount == 3 &&
        bounded.acceptedReplyCount == 1 &&
        boundedReplies.length == 1,
    'empty, odd, and non-hex payloads reject while a bounded list replies',
  );
}

void _testDeviceStatusAndModeQueries() {
  final TerminalScreen screen = TerminalScreen(rows: 5, columns: 8);
  screen.setCursorPosition(2, 3);
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    _bytes(
      '\x1b[c\x1b[0c\x1b[>c\x1b[>0c\x1b[5n\x1b[6n\x1b[?6n'
      '\x1b[4\x24p\x1b[4h\x1b[4\x24p'
      '\x1b[?7\x24p\x1b[?999\x24p',
    ),
  );
  _expectStrings(replies, const <String>[
    '\x1b[?62;22c',
    '\x1b[?62;22c',
    '\x1b[>1;0;0c',
    '\x1b[>1;0;0c',
    '\x1b[0n',
    '\x1b[3;4R',
    '\x1b[?3;4R',
    '\x1b[4;2\x24y',
    '\x1b[4;1\x24y',
    '\x1b[?7;1\x24y',
    '\x1b[?999;0\x24y',
  ], 'DA, DSR, CPR, and mode replies');
  _expect(
    sink.acceptedReplyCount == replies.length &&
        sink.rejectedReplyCount == 0 &&
        sink.unsupportedSequenceCount == 0,
    'recognized queries account every accepted reply',
  );

  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final List<Uint8List> screenSetReplies = <Uint8List>[];
  final TerminalScreenParserSink screenSetSink =
      TerminalScreenParserSink.forScreenSet(
        screens,
        onReply: (Uint8List reply) {
          screenSetReplies.add(Uint8List.fromList(reply));
          return true;
        },
      );
  final VtParser screenSetParser = VtParser(sink: screenSetSink);
  screenSetParser.parse(
    _bytes(
      '\x1b[?5h\x1b[?12l\x1b[?25l'
      '\x1b[?5\x24p\x1b[?12\x24p\x1b[?25\x24p\x1b[?47h'
      '\x1b[?5\x24p\x1b[?12\x24p\x1b[?25\x24p'
      '\x1b[?47\x24p\x1b[?1047\x24p\x1b[?1048\x24p\x1b[?1049\x24p'
      '\x1b[?1049h\x1b[?1049\x24p'
      '\x1b[?2004\x24p\x1b[?2004h\x1b[?2004\x24p',
    ),
  );
  _expectStrings(screenSetReplies, const <String>[
    '\x1b[?5;1\x24y',
    '\x1b[?12;2\x24y',
    '\x1b[?25;2\x24y',
    '\x1b[?5;2\x24y',
    '\x1b[?12;1\x24y',
    '\x1b[?25;1\x24y',
    '\x1b[?47;1\x24y',
    '\x1b[?1047;1\x24y',
    '\x1b[?1048;0\x24y',
    '\x1b[?1049;2\x24y',
    '\x1b[?1049;1\x24y',
    '\x1b[?2004;2\x24y',
    '\x1b[?2004;1\x24y',
  ], 'active-screen modes are reported without inventing 1048 state');
}

void _testOriginRelativeCursorReports() {
  final TerminalScreen screen = TerminalScreen(rows: 6, columns: 10);
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    _bytes(
      '\x1b[2;5r\x1b[?69h\x1b[3;8s\x1b[?6h\x1b[2;3H'
      '\x1b[6n\x1b[?6n\x1b[?6\x24p\x1b[?69\x24p',
    ),
  );
  _expect(
    screen.cursorRow == 2 && screen.cursorColumn == 4,
    'origin-addressed cursor reaches the expected physical coordinate',
  );
  _expectStrings(replies, const <String>[
    '\x1b[2;3R',
    '\x1b[?2;3R',
    '\x1b[?6;1\x24y',
    '\x1b[?69;1\x24y',
  ], 'ANSI and DEC cursor reports are origin-relative');
}

void _testOscColorQueriesAndTerminators() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 2);
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('4;1;#123;2;#abcdef'),
      ..._osc('4;1;?;2;?'),
      ..._osc('4;3;#010203;3;?', bell: false),
      ..._osc('10;#123456', bell: false),
      ..._osc('10;?', bell: false),
      ..._osc('11;rgb:f/0/8'),
      ..._osc('11;?'),
    ]),
  );
  _expectStrings(replies, const <String>[
    '\x1b]4;1;rgb:1111/2222/3333\x07',
    '\x1b]4;2;rgb:abab/cdcd/efef\x07',
    '\x1b]4;3;rgb:0101/0202/0303\x1b\\',
    '\x1b]10;rgb:1212/3434/5656\x1b\\',
    '\x1b]11;rgb:ffff/0000/8888\x07',
  ], 'OSC color replies preserve order, final state, and query terminator');
  _expect(
    sink.acceptedReplyCount == 5 &&
        sink.rejectedReplyCount == 0 &&
        sink.unsupportedSequenceCount == 0,
    'valid OSC mutations and queries are fully supported',
  );
}

void _testReplyRejectionAndMalformedRecovery() {
  final TerminalScreen missingScreen = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink missing = TerminalScreenParserSink(
    missingScreen,
  );
  final VtParser missingParser = VtParser(sink: missing);
  missingParser.parse(_bytes('\x1b[5nX'));
  _expect(
    missing.rejectedReplyCount == 1 &&
        missing.acceptedReplyCount == 0 &&
        missing.unsupportedSequenceCount == 0 &&
        missingScreen.contentAt(0, 0) == 0x58,
    'a missing transport rejects a known query and parsing continues',
  );

  final TerminalScreen rejectedScreen = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink rejected = TerminalScreenParserSink(
    rejectedScreen,
    onReply: (_) => false,
  );
  final VtParser rejectedParser = VtParser(sink: rejected);
  rejectedParser.parse(_bytes('\x1b[5nY'));
  _expect(
    rejected.rejectedReplyCount == 1 && rejectedScreen.contentAt(0, 0) == 0x59,
    'an explicit transport rejection is contained',
  );

  final TerminalScreen throwingScreen = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink throwing = TerminalScreenParserSink(
    throwingScreen,
    onReply: (_) => throw StateError('injected transport failure'),
  );
  final VtParser throwingParser = VtParser(sink: throwing);
  throwingParser.parse(_bytes('\x1b[5nZ'));
  _expect(
    throwing.rejectedReplyCount == 1 && throwingScreen.contentAt(0, 0) == 0x5a,
    'a throwing transport cannot escape the parser callback',
  );

  final List<Uint8List> malformedReplies = <Uint8List>[];
  final TerminalScreen malformedScreen = TerminalScreen(rows: 1, columns: 8);
  final TerminalScreenParserSink malformed = TerminalScreenParserSink(
    malformedScreen,
    onReply: (Uint8List reply) {
      malformedReplies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser malformedParser = VtParser(sink: malformed);
  malformedParser.parse(
    Uint8List.fromList(<int>[
      ..._bytes('\x1b[1;2c\x1b[?5n\x1b[5;6n\x1b[\x24p'),
      ..._osc('4;999;?'),
      ..._osc('4;1;#010203;2;bad'),
      ..._bytes('Q\x1b[?999\x24p'),
    ]),
  );
  _expectStrings(malformedReplies, const <String>[
    '\x1b[?999;0\x24y',
  ], 'unknown well-formed modes report status zero');
  _expect(
    malformed.unsupportedSequenceCount == 6 &&
        malformedScreen.contentAt(0, 0) == 0x51,
    'malformed query forms remain bounded and recover to printable input',
  );
}

void _testQueryChunkIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    ..._bytes('\x1b[?5h\x1b[3;4H\x1b[c\x1b[6n\x1b[?5\x24p'),
    ..._osc('10;#123456'),
    ..._osc('10;?'),
    ..._bytes('\x1bP+q4D73\x1b\\'),
  ]);
  final List<String> expected = _parseReplyStream(input);
  for (int split = 0; split <= input.length; split++) {
    _expect(
      _listsEqual(
        _parseReplyStream(input, <int>[split, input.length - split]),
        expected,
      ),
      'query stream is stable at split $split',
    );
  }
  _expect(
    _listsEqual(
      _parseReplyStream(input, List<int>.filled(input.length, 1)),
      expected,
    ),
    'query stream is stable under bytewise delivery',
  );
}

List<String> _parseReplyStream(Uint8List input, [List<int>? chunks]) {
  final TerminalScreen screen = TerminalScreen(rows: 5, columns: 8);
  final List<String> replies = <String>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (Uint8List reply) {
      replies.add(ascii.decode(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  var offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  _expect(offset == input.length, 'chunk plan consumes every query byte');
  parser.finish();
  _expect(
    sink.acceptedReplyCount == replies.length &&
        sink.rejectedReplyCount == 0 &&
        sink.unsupportedSequenceCount == 0,
    'chunked query stream has exact reply accounting',
  );
  return replies;
}

Uint8List _bytes(String value) => Uint8List.fromList(ascii.encode(value));

List<int> _osc(String payload, {bool bell = true}) => <int>[
  0x1b,
  0x5d,
  ...ascii.encode(payload),
  if (bell) 0x07 else ...const <int>[0x1b, 0x5c],
];

void _expectBytes(Uint8List actual, String expected, String description) {
  _expect(ascii.decode(actual) == expected, description);
  _expect(
    actual.length <= TerminalReplyEncoder.maximumReplyBytes,
    '$description stays bounded',
  );
}

void _expectStrings(
  List<Uint8List> actual,
  List<String> expected,
  String description,
) {
  final List<String> decoded = <String>[
    for (final Uint8List bytes in actual) ascii.decode(bytes),
  ];
  if (!_listsEqual(decoded, expected)) {
    throw StateError('$description: expected $expected, actual $decoded');
  }
  for (final Uint8List reply in actual) {
    _expect(
      reply.length <= TerminalReplyEncoder.maximumReplyBytes,
      '$description keeps every reply bounded',
    );
  }
}

bool _listsEqual(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

void _expectThrows(
  void Function() operation,
  Type expectedType,
  String description,
) {
  try {
    operation();
  } on Object catch (error) {
    if (error.runtimeType == expectedType) {
      return;
    }
    throw StateError('$description threw ${error.runtimeType}');
  }
  throw StateError('$description did not throw');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(description);
  }
}
