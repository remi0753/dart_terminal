import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalOsc52ProjectionTests();

void runTerminalOsc52ProjectionTests() {
  _testAllowProjectsReadWriteAndClearExactly();
  _testAskIsExactBusyAndPasteboardStaleSafe();
  _testPendingLifecycleIsFocusResetCloseAndTimeoutSafe();
  _testInvalidTextAndReplyPressureFailClosed();
  _testReadReplyRetainsTheWireBound();
}

void _testAllowProjectsReadWriteAndClearExactly() {
  final _MemoryClipboard clipboard = _MemoryClipboard()..seed('read ✓');
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
  );
  final TerminalSessionId id = _id(301);
  final TerminalOsc52SessionProjection projection = coordinator.registerSession(
    sessionId: id,
    readPolicy: TerminalConfiguredClipboardAccess.allow,
    writePolicy: TerminalConfiguredClipboardAccess.allow,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  coordinator.focusSession(id);
  final TerminalScreenParserSink sink = _sink(
    projection,
    fallbackReplies: replies,
  );
  final VtParser parser = VtParser(sink: sink);
  parser
    ..parse(_osc('52;c;?'))
    ..parse(_osc('52;c;${base64Encode(utf8.encode('write 文'))}'))
    ..parse(_osc('52;c;!', bell: false));
  _expect(
    ascii.decode(replies.single) ==
            '\x1b]52;c;${base64Encode(utf8.encode('read ✓'))}\x07' &&
        clipboard.readCount == 1 &&
        clipboard.writeCount == 1 &&
        clipboard.clearCount == 1 &&
        clipboard.text == null &&
        sink.acceptedClipboardReadCount == 1 &&
        sink.acceptedClipboardWriteCount == 1 &&
        sink.acceptedClipboardClearCount == 1,
    'allow policy did not project exact bounded plain text operations',
  );

  parser.parse(_osc('52;p;?'));
  _expect(
    ascii.decode(replies.last) == '\x1b]52;p;\x07' &&
        sink.deniedClipboardReadCount == 1 &&
        clipboard.readCount == 1,
    'a non-clipboard xterm selection gained native authority',
  );
  coordinator.dispose();
}

void _testAskIsExactBusyAndPasteboardStaleSafe() {
  final _MemoryClipboard clipboard = _MemoryClipboard()..seed('original');
  final List<Uint8List> replies = <Uint8List>[];
  final List<TerminalOsc52PendingRequest?> changes =
      <TerminalOsc52PendingRequest?>[];
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
    onPendingChanged: changes.add,
  );
  final TerminalSessionId id = _id(302);
  final TerminalOsc52SessionProjection projection = coordinator.registerSession(
    sessionId: id,
    readPolicy: TerminalConfiguredClipboardAccess.ask,
    writePolicy: TerminalConfiguredClipboardAccess.ask,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  coordinator.focusSession(id);
  final TerminalScreenParserSink sink = _sink(
    projection,
    fallbackReplies: replies,
  );
  final VtParser parser = VtParser(sink: sink);
  const String firstText = 'first\n\u202e';
  parser.parse(_osc('52;c;${base64Encode(utf8.encode(firstText))}'));
  final TerminalOsc52PendingRequest first = coordinator.pendingRequest!;
  _expect(
    first.request.operation == TerminalOsc52Operation.write &&
        first.writeText == firstText &&
        first.writeUtf8Bytes == utf8.encode(firstText).length &&
        first.pasteboardChangeCount == clipboard.changeCount &&
        clipboard.writeCount == 0 &&
        changes.single == first,
    'ask did not retain the exact decoded request without writing',
  );
  parser.parse(_osc('52;c;?'));
  _expect(
    sink.deniedClipboardReadCount == 1 &&
        ascii.decode(replies.single) == '\x1b]52;c;\x07' &&
        coordinator.metrics.busyRequestCount == 1 &&
        coordinator.approve(first.id + 1) ==
            TerminalOsc52ConfirmationDisposition.missing,
    'busy or wrong-identity confirmation did not fail closed',
  );
  clipboard.seed('changed by user');
  _expect(
    coordinator.approve(first.id) ==
            TerminalOsc52ConfirmationDisposition.stale &&
        clipboard.text == 'changed by user' &&
        clipboard.writeCount == 0 &&
        coordinator.pendingRequest == null,
    'a pending write overwrote a newer pasteboard generation',
  );

  const String secondText = 'approved ✓';
  parser.parse(_osc('52;c;${base64Encode(utf8.encode(secondText))}'));
  final int secondId = coordinator.pendingRequest!.id;
  _expect(
    coordinator.approve(secondId) ==
            TerminalOsc52ConfirmationDisposition.approved &&
        clipboard.text == secondText &&
        clipboard.writeCount == 1,
    'exact current write approval did not execute once',
  );

  parser.parse(_osc('52;c;?', bell: false));
  final int readId = coordinator.pendingRequest!.id;
  clipboard.seed('approval-time value');
  _expect(
    coordinator.approve(readId) ==
            TerminalOsc52ConfirmationDisposition.approved &&
        ascii.decode(replies.last) ==
            '\x1b]52;c;${base64Encode(utf8.encode('approval-time value'))}'
                '\x1b\\' &&
        clipboard.readCount == 1,
    'read approval reread or disclosed a value outside its exact gesture',
  );

  parser.parse(_osc('52;c;?'));
  final int deniedId = coordinator.pendingRequest!.id;
  _expect(
    coordinator.deny(deniedId) == TerminalOsc52ConfirmationDisposition.denied &&
        ascii.decode(replies.last) == '\x1b]52;c;\x07' &&
        changes.last == null,
    'explicit read denial did not complete with the unavailable reply',
  );
  coordinator.dispose();
}

void _testPendingLifecycleIsFocusResetCloseAndTimeoutSafe() {
  var now = 1000000;
  final _MemoryClipboard clipboard = _MemoryClipboard()..seed('private');
  final List<Uint8List> replies = <Uint8List>[];
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
    monotonicMicros: () => now,
    confirmationTimeout: const Duration(seconds: 1),
  );
  final TerminalSessionId firstId = _id(303);
  final TerminalSessionId secondId = _id(304);
  final TerminalOsc52SessionProjection first = coordinator.registerSession(
    sessionId: firstId,
    readPolicy: TerminalConfiguredClipboardAccess.ask,
    writePolicy: TerminalConfiguredClipboardAccess.ask,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final TerminalOsc52SessionProjection second = coordinator.registerSession(
    sessionId: secondId,
    readPolicy: TerminalConfiguredClipboardAccess.ask,
    writePolicy: TerminalConfiguredClipboardAccess.ask,
    onReply: (Uint8List reply) {
      replies.add(Uint8List.fromList(reply));
      return true;
    },
  );
  final TerminalScreenParserSink firstSink = _sink(
    first,
    fallbackReplies: replies,
  );
  final TerminalScreenParserSink secondSink = _sink(
    second,
    fallbackReplies: replies,
  );
  coordinator.focusSession(firstId);
  VtParser(sink: firstSink).parse(_osc('52;c;?'));
  coordinator.focusSession(secondId);
  _expect(
    coordinator.pendingRequest == null &&
        ascii.decode(replies.last) == '\x1b]52;c;\x07',
    'focus change retained a pending disclosure',
  );

  VtParser(sink: secondSink).parse(_osc('52;c;?'));
  second.synchronize(2);
  _expect(
    coordinator.pendingRequest == null && second.resetGeneration == 2,
    'terminal reset retained its prior confirmation identity',
  );
  VtParser(sink: secondSink).parse(_osc('52;c;?'));
  coordinator.setApplicationActive(false);
  _expect(
    coordinator.pendingRequest == null,
    'application deactivation retained a pending clipboard request',
  );
  coordinator.setApplicationActive(true);
  VtParser(sink: secondSink).parse(_osc('52;c;?'));
  now += const Duration(seconds: 1).inMicroseconds;
  _expect(
    coordinator.expirePending(nowMicros: now) &&
        coordinator.pendingRequest == null,
    'deadline did not expire the exact pending request',
  );
  VtParser(sink: secondSink).parse(_osc('52;c;?'));
  second.close();
  _expect(
    coordinator.pendingRequest == null &&
        second.isClosed &&
        coordinator.metrics.trackedSessionCount == 1,
    'session close retained request or registration state',
  );
  first.close();
  coordinator.dispose();
}

void _testInvalidTextAndReplyPressureFailClosed() {
  final _MemoryClipboard clipboard = _MemoryClipboard()..seed('secret');
  final TerminalOsc52Coordinator coordinator = TerminalOsc52Coordinator(
    clipboard: clipboard,
    applicationActive: true,
  );
  final TerminalSessionId id = _id(305);
  var replyAttempts = 0;
  final TerminalOsc52SessionProjection projection = coordinator.registerSession(
    sessionId: id,
    readPolicy: TerminalConfiguredClipboardAccess.allow,
    writePolicy: TerminalConfiguredClipboardAccess.allow,
    onReply: (Uint8List reply) {
      replyAttempts++;
      return false;
    },
  );
  coordinator.focusSession(id);
  bool rejectReply(Uint8List reply) {
    replyAttempts++;
    return false;
  }

  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onReply: rejectReply,
    onOsc52Request: projection.handle,
  );
  final VtParser parser = VtParser(sink: sink);
  parser
    ..parse(_osc('52;c;/w=='))
    ..parse(_osc('52;c;${base64Encode(Uint8List(3061))}'))
    ..parse(_osc('52;c;?'));
  _expect(
    clipboard.writeCount == 0 &&
        sink.deniedClipboardWriteCount == 2 &&
        sink.deniedClipboardReadCount == 1 &&
        replyAttempts == 2 &&
        coordinator.metrics.invalidTextRequestCount == 2 &&
        coordinator.metrics.replyFailureCount == 1,
    'invalid UTF-8, oversize text, or reply pressure gained authority',
  );
  coordinator.dispose();
}

void _testReadReplyRetainsTheWireBound() {
  TerminalOsc52Request? request;
  final TerminalScreenParserSink sink = TerminalScreenParserSink(
    TerminalScreen(rows: 1, columns: 1),
    onOsc52Request: (TerminalOsc52Request value) {
      request = value;
      return true;
    },
  );
  VtParser(sink: sink).parse(_osc('52;cpqs01234567;?', bell: false));
  final Uint8List maximum = TerminalOsc52Protocol.encodeReadReply(
    request!,
    'a' * TerminalOsc52Protocol.maximumClipboardTextUtf8Bytes,
  );
  _expect(
    maximum.length == TerminalOsc52Protocol.maximumReplyBytes,
    'maximum admitted text did not exactly fit the documented wire bound',
  );
  _expectThrows<RangeError>(
    () => TerminalOsc52Protocol.encodeReadReply(
      request!,
      'a' * (TerminalOsc52Protocol.maximumClipboardTextUtf8Bytes + 1),
    ),
    'oversize successful reply was encoded',
  );
}

TerminalScreenParserSink _sink(
  TerminalOsc52SessionProjection projection, {
  required List<Uint8List> fallbackReplies,
}) => TerminalScreenParserSink(
  TerminalScreen(rows: 1, columns: 1),
  onReply: (Uint8List reply) {
    fallbackReplies.add(Uint8List.fromList(reply));
    return true;
  },
  onOsc52Request: projection.handle,
);

TerminalSessionId _id(int pane) =>
    TerminalSessionId(paneId: PaneId(pane), generation: 1);

Uint8List _osc(String payload, {bool bell = true}) => Uint8List.fromList(<int>[
  0x1b,
  0x5d,
  ...ascii.encode(payload),
  if (bell) 0x07 else ...const <int>[0x1b, 0x5c],
]);

final class _MemoryClipboard implements TerminalOsc52ClipboardPort {
  String? text;
  int _changeCount = 0;
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  void seed(String value) {
    text = value;
    _changeCount++;
  }

  @override
  int get changeCount => _changeCount;

  @override
  TerminalOsc52ClipboardText readText() {
    readCount++;
    return TerminalOsc52ClipboardText(text: text, changeCount: _changeCount);
  }

  @override
  int writeText(String value) {
    writeCount++;
    seed(value);
    return _changeCount;
  }

  @override
  int clear() {
    clearCount++;
    text = null;
    return ++_changeCount;
  }
}

void _expectThrows<T extends Object>(void Function() callback, String message) {
  try {
    callback();
  } on T {
    return;
  }
  throw StateError(message);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
