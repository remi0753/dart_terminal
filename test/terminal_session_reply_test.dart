import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalSessionReplyTests();

Future<void> runTerminalSessionReplyTests() async {
  await _testRawParserFeedReplyOrderingAndCompletion();
  await _testReplyBackpressureAndUnavailableSession();
  await _testResizeValidationIsAtomic();
}

Future<void> _testRawParserFeedReplyOrderingAndCompletion() async {
  final FakePtyBackend backend = FakePtyBackend(autoExitOnClose: false);
  final TerminalSession session = _session(pane: 201, backend: backend);
  session.resize(rows: 3, columns: 6);
  await session.start();
  final FakePtyProcess process = backend.processes.single;
  _expect(
    process.sizes.single.rows == 3 &&
        process.sizes.single.columns == 6 &&
        session.terminalScreenSet.primary.rows == 3 &&
        session.terminalScreenSet.primary.columns == 6,
    'pre-start dimensions initialize both PTY and terminal core',
  );

  session.insertText('u');
  process.emitOutput(const <int>[0x41, 0xe2]);
  process.emitOutput(const <int>[
    0x82,
    0xac,
    0x1b,
    0x5b,
    0x35,
    0x6e,
    0x42,
    0x1b,
    0x5d,
    0x35,
    0x32,
    0x3b,
    0x63,
    0x3b,
    0x3f,
    0x07,
    0x1b,
    0x5b,
    0x36,
    0x6e,
  ]);
  session.insertText('v');

  final TerminalScreen screen = session.terminalScreenSet.primary;
  _expect(
    screen.contentAt(0, 0) == 0x41 &&
        screen.contentAt(0, 1) == 0x20ac &&
        screen.contentAt(0, 2) == 0x42,
    'original split PTY bytes reach the canonical terminal parser',
  );
  _expect(
    session.buffer.outputText.contains('A€') &&
        session.buffer.outputText.contains('B'),
    'the same byte stream still feeds the legacy text projection',
  );
  _expectWrites(process.writes, const <String>[
    'u',
    '\x1b[0n',
    '\x1b]52;c;\x07',
    '\x1b[1;4R',
    'v',
  ]);
  _expect(
    session.terminalParserSink.acceptedReplyCount == 3 &&
        session.terminalParserSink.rejectedReplyCount == 0 &&
        session.terminalParserSink.deniedClipboardReadCount == 1 &&
        session.terminalParserSink.deniedClipboardWriteCount == 0 &&
        session.terminalParserSink.deniedClipboardClearCount == 0,
    'accepted reply is ordered between surrounding accepted user writes',
  );

  session.resize(rows: 4, columns: 8);
  _expect(
    process.sizes.last.rows == 4 &&
        process.sizes.last.columns == 8 &&
        session.terminalScreenSet.primary.rows == 4 &&
        session.terminalScreenSet.primary.columns == 8 &&
        session.terminalScreenSet.alternate.rows == 4 &&
        session.terminalScreenSet.alternate.columns == 8,
    'live resize updates PTY and both terminal grids',
  );

  process.emitOutput(const <int>[0x1b, 0x5b]);
  process.finish(exitCode: 0);
  await session.waitForTermination();
  _expect(
    session.terminalParserSink.incompleteCount == 1,
    'PTY output close finishes an incomplete parser sequence exactly once',
  );
  await session.dispose();
}

Future<void> _testReplyBackpressureAndUnavailableSession() async {
  final FakePtyBackend backend = FakePtyBackend();
  final TerminalSession session = _session(
    pane: 202,
    backend: backend,
    writeCapacityBytes: 4,
  );
  final VtParser externalParser = VtParser(sink: session.terminalParserSink);
  externalParser.parse(_bytes('\x1b[5n'));
  _expect(
    session.terminalParserSink.rejectedReplyCount == 1 &&
        session.replyWriteBackpressureCount == 0,
    'a reply before PTY start is rejected without misclassifying pressure',
  );

  await session.start();
  final FakePtyProcess process = backend.processes.single;
  session.insertText('fill');
  process.emitOutput(_bytes('\x1b[5n'));
  _expect(
    process.writes.length == 1 &&
        session.replyWriteBackpressureCount == 1 &&
        session.replyWriteBackpressured &&
        session.terminalParserSink.rejectedReplyCount == 2,
    'a saturated native queue rejects and counts one automatic reply',
  );

  process.drainWrites();
  process.emitOutput(_bytes('\x1b[5n'));
  _expectWrites(process.writes, const <String>['fill', '\x1b[0n']);
  _expect(
    session.replyWriteBackpressureCount == 1 &&
        !session.replyWriteBackpressured &&
        session.terminalParserSink.acceptedReplyCount == 1,
    'a later query succeeds after native capacity becomes available',
  );

  process.finish(exitCode: 0);
  await session.waitForTermination();
  await session.dispose();
  externalParser.parse(_bytes('\x1b[5n'));
  _expect(
    session.terminalParserSink.rejectedReplyCount == 3 &&
        session.replyWriteBackpressureCount == 1,
    'a disposed session rejects replies without touching the native process',
  );
}

Future<void> _testResizeValidationIsAtomic() async {
  final FakePtyBackend backend = FakePtyBackend();
  final TerminalSession session = _session(pane: 203, backend: backend);
  await session.start();
  final FakePtyProcess process = backend.processes.single;
  final TerminalScreen primary = session.terminalScreenSet.primary;
  final int sizeCount = process.sizes.length;

  _expectThrows(
    () => session.resize(rows: 0, columns: 80),
    'zero session row count',
  );
  _expectThrows(
    () => session.resize(rows: TerminalScreen.maxRows + 1, columns: 1),
    'session row count beyond terminal-core storage',
  );
  _expect(
    identical(session.terminalScreenSet.primary, primary) &&
        primary.rows == 23 &&
        primary.columns == 100 &&
        process.sizes.length == sizeCount,
    'invalid resize changes neither terminal core nor PTY dimensions',
  );
  await session.dispose();
}

TerminalSession _session({
  required int pane,
  required FakePtyBackend backend,
  int writeCapacityBytes = 1024 * 1024,
}) => TerminalSession(
  id: TerminalSessionId(paneId: PaneId(pane), generation: 1),
  ptyBackend: backend,
  initialWorkingDirectory: Directory.systemTemp.path,
  writeCapacityBytes: writeCapacityBytes,
  onChanged: () {},
  onTerminated: () {},
);

Uint8List _bytes(String value) => Uint8List.fromList(ascii.encode(value));

void _expectWrites(List<Uint8List> actual, List<String> expected) {
  final List<String> decoded = <String>[
    for (final Uint8List bytes in actual) ascii.decode(bytes),
  ];
  if (decoded.length != expected.length) {
    throw StateError('write count: expected $expected, actual $decoded');
  }
  for (int index = 0; index < decoded.length; index++) {
    if (decoded[index] != expected[index]) {
      throw StateError('write order: expected $expected, actual $decoded');
    }
  }
}

void _expectThrows(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError(description);
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(description);
  }
}
