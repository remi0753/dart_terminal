import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalOsc52PolicyTests();

void runTerminalOsc52PolicyTests() {
  _testDenyPolicyClassifiesWithoutClipboardAuthority();
  _testAdmissionReceivesImmutableBoundedRequests();
  _testAdmissionFailureFallsBackToDeny();
  _testMalformedRequestsRejectAtomically();
  _testChunkingAndPayloadLimitAreDeterministic();
  _testRequestModelRetainsItsOwnPayloadBound();
  _testUnavailableReplyEncoderIsBounded();
}

void _testRequestModelRetainsItsOwnPayloadBound() {
  var calls = 0;
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onOsc52Request: (TerminalOsc52Request request) {
      calls++;
      return true;
    },
  );
  final VtParser parser = VtParser(
    sink: sink,
    limits: const VtParserLimits(maxSequenceBytes: 16384, maxStringBytes: 8192),
  );
  parser.parse(_osc('52;c;${'A' * 4092}'));
  parser.finish();
  _expect(
    calls == 0 &&
        sink.rejectedClipboardRequestCount == 1 &&
        sink.unsupportedSequenceCount == 1,
    'request admission cannot retain a payload above its independent bound',
  );
}

void _testAdmissionReceivesImmutableBoundedRequests() {
  final List<TerminalOsc52Request> requests = <TerminalOsc52Request>[];
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
    onOsc52Request: (TerminalOsc52Request request) {
      requests.add(request);
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('52;c;?'),
      ..._osc('52;pc;c2FmZQ==', bell: false),
      ..._osc('52;c;!'),
    ]),
  );
  parser.finish();
  _expect(
    requests.length == 3 &&
        requests[0].operation == TerminalOsc52Operation.read &&
        requests[0].selection == 'c' &&
        requests[0].encodedData == null &&
        requests[0].targetsClipboard &&
        requests[0].terminator == VtStringTerminator.bell &&
        requests[1].operation == TerminalOsc52Operation.write &&
        requests[1].selection == 'pc' &&
        requests[1].encodedData == 'c2FmZQ==' &&
        requests[1].targetsClipboard &&
        requests[1].terminator == VtStringTerminator.stringTerminator &&
        requests[2].operation == TerminalOsc52Operation.clear &&
        sink.acceptedClipboardReadCount == 1 &&
        sink.acceptedClipboardWriteCount == 1 &&
        sink.acceptedClipboardClearCount == 1 &&
        sink.deniedClipboardReadCount == 0 &&
        sink.deniedClipboardWriteCount == 0 &&
        sink.deniedClipboardClearCount == 0 &&
        replies.isEmpty,
    'admission receives exact bounded protocol values without implicit replies',
  );
}

void _testAdmissionFailureFallsBackToDeny() {
  var calls = 0;
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
    onOsc52Request: (TerminalOsc52Request request) {
      calls++;
      if (calls == 1) throw StateError('fixture admission failure');
      return false;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('52;c;?'),
      ..._osc('52;c;YQ=='),
      ..._osc('52;c;'),
    ]),
  );
  parser.finish();
  _expect(
    calls == 3 &&
        sink.deniedClipboardReadCount == 1 &&
        sink.deniedClipboardWriteCount == 1 &&
        sink.deniedClipboardClearCount == 1 &&
        sink.acceptedClipboardReadCount == 0 &&
        sink.acceptedClipboardWriteCount == 0 &&
        sink.acceptedClipboardClearCount == 0 &&
        ascii.decode(replies.single) == '\x1b]52;c;\x07',
    'false or throwing admission remains fail-closed',
  );
}

void _testDenyPolicyClassifiesWithoutClipboardAuthority() {
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 2);
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
      ..._osc('52;c;?'),
      ..._osc('52;;?', bell: false),
      ..._osc('52;cp;c2VjcmV0'),
      ..._osc('52;0;YQ==', bell: false),
      ..._osc('52;s;'),
      ..._osc('52;7;not-base64'),
      ..._osc('52;q;===='),
      0x58,
    ]),
  );
  parser.finish();

  _expectStrings(replies, const <String>[
    '\x1b]52;c;\x07',
    '\x1b]52;;\x1b\\',
  ], 'queries return empty data with the request selection and terminator');
  _expect(
    sink.deniedClipboardReadCount == 2 &&
        sink.deniedClipboardWriteCount == 2 &&
        sink.deniedClipboardClearCount == 3 &&
        sink.rejectedClipboardRequestCount == 0 &&
        sink.acceptedReplyCount == 2 &&
        sink.unsupportedSequenceCount == 0 &&
        screen.contentAt(0, 0) == 0x58,
    'valid reads, writes, and clears are denied without becoming unsupported',
  );
}

void _testMalformedRequestsRejectAtomically() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    screen,
    onReply: (_) => true,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._osc('52'),
      ..._osc('52;c'),
      ..._osc('52;x;?'),
      ..._osc('52;ccccccccccccc;?'),
    ]),
  );
  parser.finish();
  _expect(
    sink.rejectedClipboardRequestCount == 4 &&
        sink.unsupportedSequenceCount == 4 &&
        sink.deniedClipboardReadCount == 0 &&
        sink.deniedClipboardWriteCount == 0 &&
        sink.deniedClipboardClearCount == 0 &&
        sink.acceptedReplyCount == 0,
    'missing fields, invalid selections, and oversized selections reject',
  );
}

void _testChunkingAndPayloadLimitAreDeterministic() {
  final Uint8List input = Uint8List.fromList(<int>[
    ..._osc('52;c;?'),
    ..._osc('52;p;YQ==', bell: false),
    ..._osc('52;s;!'),
  ]);
  final List<Object> expected = _parseSnapshot(input, <int>[input.length]);
  for (int split = 0; split <= input.length; split++) {
    _expect(
      _listsEqual(_parseSnapshot(input, <int>[split, input.length]), expected),
      'OSC 52 policy differs at split $split',
    );
  }
  _expect(
    _listsEqual(
      _parseSnapshot(input, List<int>.filled(input.length, 1)),
      expected,
    ),
    'OSC 52 policy differs under bytewise delivery',
  );

  final TerminalScreenParserSink limitedSink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (_) => true,
  );
  final VtParser limitedParser = VtParser(
    sink: limitedSink,
    limits: const VtParserLimits(maxSequenceBytes: 32, maxStringBytes: 16),
  );
  limitedParser.parse(_osc('52;c;AAAAAAAAAAAAAAAAAAAA'));
  limitedParser.finish();
  _expect(
    limitedSink.limitCount == 1 &&
        limitedSink.deniedClipboardReadCount == 0 &&
        limitedSink.deniedClipboardWriteCount == 0 &&
        limitedSink.deniedClipboardClearCount == 0 &&
        limitedSink.rejectedClipboardRequestCount == 0,
    'oversized OSC 52 data is discarded by the parser bound before policy',
  );
}

void _testUnavailableReplyEncoderIsBounded() {
  _expectStrings(
    <Uint8List>[
      TerminalReplyEncoder.clipboardUnavailable(
        selection: ascii.encode('cpqs01234567'),
        terminator: VtStringTerminator.stringTerminator,
      ),
    ],
    const <String>['\x1b]52;cpqs01234567;\x1b\\'],
    'maximum meaningful selection reply is byte exact',
  );
  _expectThrows(
    () => TerminalReplyEncoder.clipboardUnavailable(
      selection: List<int>.filled(13, 0x63),
      terminator: VtStringTerminator.bell,
    ),
    RangeError,
    'reply rejects oversized selections',
  );
  _expectThrows(
    () => TerminalReplyEncoder.clipboardUnavailable(
      selection: const <int>[0x78],
      terminator: VtStringTerminator.bell,
    ),
    ArgumentError,
    'reply rejects invalid selections',
  );
}

List<Object> _parseSnapshot(Uint8List input, List<int> chunks) {
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  var offset = 0;
  for (final int length in chunks) {
    final int end = offset + length > input.length
        ? input.length
        : offset + length;
    parser.parse(Uint8List.sublistView(input, offset, end));
    offset = end;
  }
  if (offset < input.length) {
    parser.parse(Uint8List.sublistView(input, offset));
  }
  parser.finish();
  return <Object>[
    sink.deniedClipboardReadCount,
    sink.deniedClipboardWriteCount,
    sink.deniedClipboardClearCount,
    sink.rejectedClipboardRequestCount,
    sink.unsupportedSequenceCount,
    sink.acceptedReplyCount,
    ...replies.map((Uint8List reply) => base64Encode(reply)),
  ];
}

Uint8List _osc(String payload, {bool bell = true}) => Uint8List.fromList(<int>[
  0x1b,
  0x5d,
  ...ascii.encode(payload),
  if (bell) 0x07 else ...const <int>[0x1b, 0x5c],
]);

void _expectStrings(
  List<Uint8List> actual,
  List<String> expected,
  String message,
) {
  _expect(
    actual.length == expected.length &&
        List<bool>.generate(
          actual.length,
          (int index) => ascii.decode(actual[index]) == expected[index],
        ).every((bool value) => value),
    '$message: actual=${actual.map(ascii.decode).toList()}',
  );
}

bool _listsEqual(List<Object> left, List<Object> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expectThrows(void Function() callback, Type type, String message) {
  try {
    callback();
  } on Object catch (error) {
    _expect(error.runtimeType == type, '$message: $error');
    return;
  }
  throw StateError('$message: expected $type');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
