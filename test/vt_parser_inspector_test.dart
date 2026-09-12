import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runVtParserInspectorTests();

void runVtParserInspectorTests() {
  _testTypedContentConsciousObservations();
  _testParserSemanticsAndChunkIndependence();
  _testBoundsEvictionAndObserverIsolation();
  _testLimitsAndConfigurationValidation();
  _testDynamicCaptureLifecycle();
}

void _testTypedContentConsciousObservations() {
  final _CountingSink downstream = _CountingSink();
  final VtParserInspector inspector = VtParserInspector(downstream: downstream);
  final VtParser parser = VtParser(sink: inspector);
  parser.parse(
    Uint8List.fromList(<int>[
      ...utf8.encode('secret日'),
      0x07,
      0x1b,
      0x37,
      0x1b,
      0x5b,
      ...ascii.encode('?25h'),
      0x1b,
      0x5d,
      ...utf8.encode('0;private title'),
      0x07,
      0x1b,
      0x50,
      ...ascii.encode(r'$qm'),
      0x1b,
      0x5c,
      0x1b,
      0x5f,
      ...ascii.encode('private payload'),
      0x1b,
      0x5c,
    ]),
  );
  parser.finish();

  final List<VtParserInspectionEvent> events = inspector.events;
  _expect(inspector.printableScalarCount == 7, 'text is aggregate-only');
  _expect(downstream.printableScalars == 7, 'printable text is forwarded');
  _expect(downstream.asciiRuns == 1, 'downstream ASCII batching is preserved');
  _expect(events.length == 6, 'six non-print parser actions are retained');
  _expect(
    _kinds(events) ==
        'execute,escape,controlSequence,operatingSystemCommand,'
            'deviceControlString,controlString',
    'typed action families retain source order',
  );
  _expect(
    events[2].privateMarker == 0x3f &&
        events[2].parameters.length == 1 &&
        events[2].parameters.single == 25 &&
        events[2].finalByte == 0x68,
    'CSI syntax metadata is copied exactly',
  );
  _expect(
    events[3].payloadLength == utf8.encode('0;private title').length &&
        events[3].terminator == VtStringTerminator.bell &&
        events[4].payloadLength == 1 &&
        events[5].payloadLength == ascii.encode('private payload').length,
    'string events disclose length and terminator without payload bytes',
  );
  _expect(
    events[4].intermediateAt(0) == 0x24 &&
        events[4].finalByte == 0x71 &&
        events[5].stringKind == VtStringKind.applicationProgramCommand,
    'DCS header and generic string kind remain distinguishable',
  );
  _expect(
    inspector.totalEventCount == 6 &&
        inspector.droppedEventCount == 0 &&
        inspector.retainedMetadataBytes <= inspector.limits.maxMetadataBytes,
    'normal capture stays within both hard bounds',
  );
}

void _testParserSemanticsAndChunkIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    ...utf8.encode('A日'),
    0x0d,
    0x1b,
    0x37,
    0x1b,
    0x5b,
    ...ascii.encode('38:2::1:2:3m'),
    0x1b,
    0x5d,
    ...ascii.encode('0;redacted'),
    0x07,
    0x1b,
    0x50,
    ...ascii.encode(r'$qm'),
    0x1b,
    0x5c,
  ]);
  final String whole = _inspect(input);
  for (var split = 0; split <= input.length; split++) {
    _expect(
      _inspect(input, <int>[split, input.length - split]) == whole,
      'inspection is independent of split $split',
    );
  }
  _expect(
    _inspect(input, List<int>.filled(input.length, 1)) == whole,
    'inspection is independent of bytewise delivery',
  );

  final TerminalScreenSet directScreens = TerminalScreenSet(
    rows: 3,
    columns: 12,
  );
  final TerminalScreenSet inspectedScreens = TerminalScreenSet(
    rows: 3,
    columns: 12,
  );
  final VtParser direct = VtParser(
    sink: TerminalScreenParserSink.forScreenSet(directScreens),
  );
  final VtParser inspected = VtParser(
    sink: VtParserInspector(
      downstream: TerminalScreenParserSink.forScreenSet(inspectedScreens),
    ),
  );
  direct.parse(input);
  inspected.parse(input);
  direct.finish();
  inspected.finish();
  const TerminalSnapshotFormatter formatter = TerminalSnapshotFormatter();
  _expect(
    formatter.formatScreenSet(directScreens) ==
        formatter.formatScreenSet(inspectedScreens),
    'opt-in inspection does not change terminal semantics',
  );
}

void _testBoundsEvictionAndObserverIsolation() {
  final VtParserInspector inspector = VtParserInspector(
    downstream: _CountingSink(),
    limits: const VtParserInspectorLimits(maxRecords: 2, maxMetadataBytes: 96),
    onEvent: (_) => throw StateError('observer failure'),
  );
  final VtParser parser = VtParser(sink: inspector);
  parser.parse(Uint8List.fromList(const <int>[0x07, 0x08, 0x09]));
  parser.finish();
  _expect(
    inspector.totalEventCount == 3 &&
        inspector.events.length == 2 &&
        inspector.events.first.ordinal == 2 &&
        inspector.events.last.ordinal == 3 &&
        inspector.evictedEventCount == 1,
    'record and byte bounds evict the oldest event deterministically',
  );
  _expect(
    inspector.observerFailureCount == 3,
    'observer failures are counted without escaping into parsing',
  );
  _expect(
    inspector.eventCount(VtParserInspectionKind.execute) == 3,
    'aggregate kind counts include evicted events',
  );

  final VtParserInspector oversized = VtParserInspector(
    downstream: _CountingSink(),
    limits: const VtParserInspectorLimits(maxRecords: 4, maxMetadataBytes: 48),
  );
  final VtParser oversizedParser = VtParser(sink: oversized);
  oversizedParser.parse(
    Uint8List.fromList(<int>[0x1b, 0x5b, ...ascii.encode('1;2m'), 0x07]),
  );
  oversizedParser.finish();
  _expect(
    oversized.totalEventCount == 2 &&
        oversized.oversizedEventCount == 1 &&
        oversized.events.length == 1 &&
        oversized.events.single.kind == VtParserInspectionKind.execute,
    'an individually oversized metadata event is disclosed and dropped',
  );
}

void _testLimitsAndConfigurationValidation() {
  final VtParserInspector inspector = VtParserInspector(
    downstream: _CountingSink(),
  );
  final VtParser parser = VtParser(
    sink: inspector,
    limits: const VtParserLimits(maxSequenceBytes: 16, maxStringBytes: 4),
  );
  parser.parse(
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      0x33,
      0x31,
      0x1b,
      0x37,
      0x1b,
      0x5b,
      ...ascii.encode('1?2m'),
      0x1b,
      0x5d,
      ...ascii.encode('abcde'),
      0x07,
      0x1b,
      0x5b,
      0x31,
    ]),
  );
  parser.finish();
  _expect(
    _kinds(inspector.events) == 'cancel,escape,malformed,limit,incomplete',
    'cancel, malformed, limit, and incomplete recovery are typed and ordered',
  );
  _expect(
    inspector.events[0].state == VtParserState.csiParameter &&
        inspector.events[0].controlByte == 0x1b &&
        inspector.events[2].state == VtParserState.csiParameter &&
        inspector.events[2].controlByte == 0x3f &&
        inspector.events[3].limitKind == VtParserLimitKind.stringBytes &&
        inspector.events[4].state == VtParserState.csiParameter,
    'recovery events retain only bounded classification metadata',
  );

  _expectThrows(
    () => VtParserInspector(
      downstream: _CountingSink(),
      limits: const VtParserInspectorLimits(maxRecords: 0),
    ),
    'zero record limit',
  );
  _expectThrows(
    () => VtParserInspector(
      downstream: _CountingSink(),
      limits: const VtParserInspectorLimits(maxMetadataBytes: 47),
    ),
    'undersized metadata limit',
  );
}

void _testDynamicCaptureLifecycle() {
  final _CountingSink downstream = _CountingSink();
  var observed = 0;
  final VtParserInspector inspector = VtParserInspector(
    downstream: downstream,
    captureEnabled: false,
    onEvent: (_) => observed++,
  );
  final VtParser parser = VtParser(sink: inspector);
  parser.parse(Uint8List.fromList(<int>[...ascii.encode('private'), 0x07]));
  _expect(
    downstream.printableScalars == 7 &&
        downstream.executeCount == 1 &&
        !inspector.captureEnabled &&
        inspector.printableScalarCount == 0 &&
        inspector.totalEventCount == 0 &&
        inspector.events.isEmpty &&
        observed == 0,
    'disabled capture forwards without retaining or observing metadata',
  );

  inspector.beginCapture(onEvent: (_) => observed++);
  parser.parse(Uint8List.fromList(<int>[...ascii.encode('secret'), 0x08]));
  final VtParserInspectionSnapshot frozen = inspector.snapshot();
  _expect(
    frozen.captureEnabled &&
        frozen.printableScalarCount == 6 &&
        frozen.totalEventCount == 1 &&
        frozen.events.single.kind == VtParserInspectionKind.execute &&
        observed == 1,
    'beginCapture starts one fresh bounded generation',
  );

  parser.parse(Uint8List.fromList(const <int>[0x09]));
  _expect(
    frozen.totalEventCount == 1 && frozen.events.length == 1,
    'snapshot does not observe later parser actions',
  );
  inspector.endCapture();
  _expect(
    !inspector.captureEnabled &&
        inspector.totalEventCount == 0 &&
        inspector.events.isEmpty,
    'endCapture disables observers and clears retained aggregates',
  );
  parser.parse(Uint8List.fromList(const <int>[0x0d]));
  _expect(
    inspector.totalEventCount == 0 && observed == 2,
    'closed capture retains no subsequent events',
  );
}

String _inspect(Uint8List input, [List<int>? chunks]) {
  final VtParserInspector inspector = VtParserInspector(
    downstream: _CountingSink(),
  );
  final VtParser parser = VtParser(sink: inspector);
  if (chunks == null) {
    parser.parse(input);
  } else {
    var offset = 0;
    for (final int length in chunks) {
      parser.parse(input, offset, offset + length);
      offset += length;
    }
    _expect(offset == input.length, 'chunk plan consumes the input');
  }
  parser.finish();
  final StringBuffer result = StringBuffer()
    ..write('print=${inspector.printableScalarCount}');
  for (final VtParserInspectionEvent event in inspector.events) {
    result
      ..write('|${event.ordinal}:${event.kind.name}')
      ..write('/${event.state?.name ?? '-'}')
      ..write('/${event.controlByte ?? -1}')
      ..write('/${event.privateMarker ?? -1}')
      ..write('/${event.parameters}')
      ..write('/${event.subparameters}')
      ..write('/${event.copyIntermediates()}')
      ..write('/${event.finalByte ?? -1}')
      ..write('/${event.stringKind?.name ?? '-'}')
      ..write('/${event.payloadLength}')
      ..write('/${event.terminator?.name ?? '-'}')
      ..write('/${event.limitKind?.name ?? '-'}');
  }
  return result.toString();
}

String _kinds(List<VtParserInspectionEvent> events) =>
    events.map((VtParserInspectionEvent event) => event.kind.name).join(',');

final class _CountingSink implements VtParserSink, VtParserAsciiSink {
  int printableScalars = 0;
  int asciiRuns = 0;
  int executeCount = 0;

  @override
  void print(int scalar) => printableScalars++;

  @override
  void printAscii(Uint8List bytes, int start, int end) {
    asciiRuns++;
    printableScalars += end - start;
  }

  @override
  void execute(int controlByte) => executeCount++;

  @override
  void dispatchEscape(VtEscapeSequence sequence) {}

  @override
  void dispatchCsi(VtSequenceHeader sequence) {}

  @override
  void dispatchOsc(VtStringSequence sequence) {}

  @override
  void dispatchDcs(VtDcsSequence sequence) {}

  @override
  void dispatchString(VtStringSequence sequence) {}

  @override
  void cancel(VtParserState state, int controlByte) {}

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {}

  @override
  void malformed(VtParserState state, int byte) {}

  @override
  void incomplete(VtParserState state) {}
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('test failed: $message');
}
