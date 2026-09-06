import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalHyperlinkTests();

void runTerminalHyperlinkTests() {
  _testBoundedImmutableTable();
  _testOscOpenCloseAndIdentity();
  _testMalformedAndLimitedSequencesCloseCurrentLink();
  _testHyperlinksSurviveWideGraphemeHistoryAndReflow();
  _testViewportHitTestingAndStaleRefresh();
  _testScreenSwitchAndResetState();
  _testSnapshotDefinitionsAndLimits();
}

void _testViewportHitTestingAndStaleRefresh() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 4, maxBytes: 4096, pageRows: 1),
  );
  final int first = screens.hyperlinkTable.tryIntern(
    uri: 'https://first.test',
    explicitId: 'first',
  )!;
  final int second = screens.hyperlinkTable.tryIntern(
    uri: 'https://second.test',
    explicitId: 'second',
  )!;
  screens.primary.setWideCell(0, 1, 0x754c, hyperlink: first);
  final TerminalHyperlinkHit lead = screens.viewport.hitTestHyperlink(0, 1)!;
  final TerminalHyperlinkHit continuation = screens.viewport.hitTestHyperlink(
    0,
    2,
  )!;
  _expect(
    lead.hyperlinkId == continuation.hyperlinkId &&
        lead.column == 1 &&
        continuation.column == 1 &&
        lead.pointerColumn == 1 &&
        continuation.pointerColumn == 2 &&
        lead.cellWidth == 2 &&
        lead.uri == 'https://first.test',
    'wide continuation hit normalizes to one immutable lead definition',
  );
  _expect(
    screens.viewport.hitTestHyperlink(-1, 0) == null &&
        screens.viewport.hitTestHyperlink(0, -1) == null &&
        screens.viewport.hitTestHyperlink(2, 0) == null &&
        screens.viewport.hitTestHyperlink(0, 4) == null &&
        screens.viewport.hitTestHyperlink(1, 0) == null,
    'pointer-style blank and out-of-grid hits return null',
  );

  screens.primary.setWideCell(0, 1, 0x754c, hyperlink: second);
  _expect(
    screens.viewport.refreshHyperlinkHit(lead) == null,
    'a changed cell invalidates a stale hover instead of retargeting it',
  );
  final TerminalHyperlinkHit replacement = screens.viewport.hitTestHyperlink(
    0,
    2,
  )!;
  _expect(
    replacement.hyperlinkId == second &&
        replacement.viewportGeneration > lead.viewportGeneration,
    'a fresh hit observes the replacement generation and URI identity',
  );

  screens.primary.scrollUp(1);
  screens.primary.setNarrowCell(1, 0, 0x58, hyperlink: first);
  screens.viewport.scrollByRows(1);
  final TerminalHyperlinkHit history = screens.viewport.hitTestHyperlink(0, 2)!;
  _expect(
    history.hyperlinkId == second && screens.viewport.isHistoryRow(0),
    'hit testing resolves retained history through the visible projection',
  );
  screens.viewport.scrollToBottom();
  _expect(
    screens.viewport.refreshHyperlinkHit(history) == null,
    'viewport navigation invalidates a hit whose physical row now differs',
  );
}

void _testBoundedImmutableTable() {
  final TerminalHyperlinkTable table = TerminalHyperlinkTable(
    capacity: 3,
    maximumUtf8Bytes: 48,
    maximumDefinitionUtf8Bytes: 24,
  );
  final int first = table.tryIntern(uri: 'https://a.test')!;
  final int second = table.tryIntern(uri: 'https://a.test')!;
  final int grouped = table.tryIntern(
    uri: 'https://b.test',
    explicitId: 'same',
  )!;
  _expect(first != second, 'implicit OSC 8 openings have distinct identity');
  _expect(
    table.tryIntern(uri: 'https://b.test', explicitId: 'same') == grouped &&
        table.definitionCount == 3,
    'equal explicit ID and URI reuse one immutable identity',
  );
  _expect(
    table.tryIntern(uri: 'https://c.test') == null &&
        table.definitionCount == 3 &&
        table.refusalCount == 1,
    'entry exhaustion refuses without changing retained definitions',
  );
  _expect(
    table.uriAt(first) == 'https://a.test' &&
        table.definitionAt(grouped).explicitId == 'same' &&
        table.generation == 4,
    'definition lookup and generation remain stable',
  );

  final TerminalHyperlinkTable bytes = TerminalHyperlinkTable(
    capacity: 4,
    maximumUtf8Bytes: 12,
    maximumDefinitionUtf8Bytes: 8,
  );
  _expect(
    bytes.tryIntern(uri: '12345678') == 1 &&
        bytes.tryIntern(uri: '12345') == null &&
        bytes.utf8Bytes == 8,
    'per-definition and aggregate UTF-8 limits are atomic',
  );
  for (final String unsafe in <String>[
    'has space',
    'line\nfeed',
    'bidi\u202ereverse',
    'isolate\u2066text',
  ]) {
    _expect(
      bytes.tryIntern(uri: unsafe) == null,
      'unsafe URI scalar is refused: ${jsonEncode(unsafe)}',
    );
  }
  _expect(
    bytes.tryIntern(uri: 'ok', explicitId: 'bad:id') == null,
    'parameter delimiter cannot be embedded in explicit ID',
  );
}

void _testOscOpenCloseAndIdentity() {
  final Uint8List input = _bytes(
    '${_osc('8;id=shared:future=value;https://example.test/a')}A'
    '${_osc('8;;')}B'
    '${_osc('8;id=shared;https://example.test/a')}C'
    '${_osc('8;;https://example.test/a')}D'
    '${_osc('8;;')}E',
  );
  for (int split = 0; split <= input.length; split++) {
    final TerminalScreen screen = TerminalScreen(rows: 1, columns: 8);
    final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
    final VtParser parser = VtParser(sink: sink);
    parser.parse(input, 0, split);
    parser.parse(input, split, input.length);
    parser.finish();
    final int first = screen.hyperlinkAt(0, 0);
    _expect(
      first != 0 &&
          screen.hyperlinkAt(0, 1) == 0 &&
          screen.hyperlinkAt(0, 2) == first &&
          screen.hyperlinkAt(0, 3) != 0 &&
          screen.hyperlinkAt(0, 3) != first &&
          screen.hyperlinkAt(0, 4) == 0,
      'OSC 8 identity/open/close is chunk independent at split $split',
    );
    _expect(
      screen.hyperlinkTable.definitionCount == 2 &&
          sink.acceptedHyperlinkCount == 5 &&
          sink.rejectedHyperlinkCount == 0 &&
          sink.currentHyperlinkId == 0 &&
          sink.unsupportedSequenceCount == 0,
      'OSC 8 accounting is exact at split $split',
    );
  }
}

void _testMalformedAndLimitedSequencesCloseCurrentLink() {
  final TerminalHyperlinkTable table = TerminalHyperlinkTable(capacity: 1);
  final TerminalScreen screen = TerminalScreen(
    rows: 1,
    columns: 8,
    hyperlinkTable: table,
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    Uint8List.fromList(<int>[
      ..._bytes(_osc('8;;https://safe.test')),
      0x41,
      ..._bytes(_osc('8;id=;https://bad.test')),
      0x42,
      0x1b,
      0x5d,
      0x38,
      0x3b,
      0x3b,
      0xc3,
      0x28,
      0x07,
      0x43,
      ..._bytes(_osc('8;;https://full.test')),
      0x44,
    ]),
  );
  _expect(
    screen.hyperlinkAt(0, 0) == 1 &&
        screen.hyperlinkAt(0, 1) == 0 &&
        screen.hyperlinkAt(0, 2) == 0 &&
        screen.hyperlinkAt(0, 3) == 0,
    'invalid parameters, UTF-8, and table exhaustion close prior state',
  );
  _expect(
    sink.acceptedHyperlinkCount == 1 &&
        sink.rejectedHyperlinkCount == 3 &&
        table.definitionCount == 1,
    'refused OSC 8 definitions do not mutate the bounded table',
  );

  final TerminalScreen limitedScreen = TerminalScreen(rows: 1, columns: 4);
  final TerminalScreenParserSink limitedSink = TerminalScreenParserSink(
    limitedScreen,
  );
  final VtParser limitedParser = VtParser(
    sink: limitedSink,
    limits: const VtParserLimits(maxSequenceBytes: 16, maxStringBytes: 8),
  );
  limitedParser.parse(
    _bytes('${_osc('8;;x')}A\x1b]8;;12345678901234567890\x07B'),
  );
  _expect(
    limitedScreen.hyperlinkAt(0, 0) != 0 &&
        limitedScreen.hyperlinkAt(0, 1) == 0 &&
        limitedSink.limitCount == 1 &&
        limitedSink.rejectedHyperlinkCount == 1 &&
        limitedSink.currentHyperlinkId == 0,
    'OSC string limit clears current link before printable recovery',
  );
}

void _testHyperlinksSurviveWideGraphemeHistoryAndReflow() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 8, maxBytes: 8192, pageRows: 2),
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    _bytes('${_osc('8;id=shape;https://example.test')}日e\u0301abcdef'),
  );
  final int hyperlink = screens.hyperlinkTable.definitionAt(1).id;
  _expect(
    screens.scrollback.length > 0,
    'linked wrapped output reaches retained history',
  );
  _expectAllContentUsesHyperlink(screens, hyperlink, 'before reflow');
  screens.resize(rows: 3, columns: 3);
  screens.primary.validateCellTopology();
  screens.scrollback.validateCellTopology();
  _expectAllContentUsesHyperlink(screens, hyperlink, 'after reflow');
}

void _testScreenSwitchAndResetState() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(
    _bytes(
      '${_osc('8;id=switch;https://example.test')}P'
      '\x1b[?1049hA\x1b[?1049lB',
    ),
  );
  _expect(
    identical(
          screens.primary.hyperlinkTable,
          screens.alternate.hyperlinkTable,
        ) &&
        identical(screens.hyperlinkTable, screens.primary.hyperlinkTable),
    'primary and alternate grids share one session table',
  );
  _expect(
    screens.primary.hyperlinkAt(0, 0) != 0 &&
        screens.primary.hyperlinkAt(0, 1) != 0 &&
        screens.alternate.hyperlinkAt(0, 0) != 0 &&
        sink.currentHyperlinkId != 0,
    'current link state spans primary and alternate screen switches',
  );
  parser.parse(_bytes('\x1bcC'));
  _expect(
    screens.primary.contentAt(0, 0) == 0x43 &&
        screens.primary.hyperlinkAt(0, 0) == 0 &&
        screens.alternate.hyperlinkAt(0, 0) == 0 &&
        sink.currentHyperlinkId == 0,
    'RIS clears both grids and current hyperlink state',
  );
}

void _testSnapshotDefinitionsAndLimits() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 2);
  final int hyperlink = screen.hyperlinkTable.tryIntern(
    uri: 'https://example.test/日本',
    explicitId: 'snapshot',
  )!;
  screen.setNarrowCell(0, 0, 0x58, hyperlink: hyperlink);
  final String snapshot = const TerminalSnapshotFormatter().formatScreen(
    screen,
  );
  _expect(
    snapshot.contains('hyperlinks count=1 utf8_bytes=') &&
        snapshot.contains(
          'hyperlink id=1 explicit_id="snapshot" '
          'uri="https://example.test/日本"',
        ) &&
        snapshot.contains('style=0 hyperlink=1'),
    'snapshot binds cell identity to an exact URI definition',
  );
  _expectSnapshotLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxHyperlinkDefinitions: 0),
    ).formatScreen(screen),
    'hyperlink definitions',
  );
  _expectSnapshotLimit(
    () => const TerminalSnapshotFormatter(
      limits: TerminalSnapshotFormatLimits(maxHyperlinkUtf8Bytes: 0),
    ).formatScreen(screen),
    'hyperlink UTF-8 bytes',
  );
}

void _expectAllContentUsesHyperlink(
  TerminalScreenSet screens,
  int hyperlink,
  String stage,
) {
  for (int row = 0; row < screens.scrollback.length; row++) {
    for (int column = 0; column < screens.scrollback.columnsAt(row); column++) {
      if (screens.scrollback.contentAt(row, column) != 0) {
        _expect(
          screens.scrollback.hyperlinkAt(row, column) == hyperlink,
          '$stage history cell retains hyperlink',
        );
      }
    }
  }
  for (int row = 0; row < screens.primary.rows; row++) {
    for (int column = 0; column < screens.primary.columns; column++) {
      final int flags = screens.primary.widthFlagsAt(row, column);
      final bool occupied =
          screens.primary.contentAt(row, column) != 0 ||
          (flags & TerminalCellFlags.widthMask) ==
              TerminalCellFlags.continuation;
      if (occupied) {
        _expect(
          screens.primary.hyperlinkAt(row, column) == hyperlink,
          '$stage screen cell retains hyperlink',
        );
      }
    }
  }
}

void _expectSnapshotLimit(void Function() callback, String resource) {
  try {
    callback();
  } on TerminalSnapshotLimitException catch (error) {
    _expect(error.resource == resource, '$resource limit is classified');
    return;
  }
  throw StateError('Expected TerminalSnapshotLimitException for $resource');
}

String _osc(String payload) => '\x1b]$payload\x07';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
