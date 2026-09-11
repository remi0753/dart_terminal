import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runVtParserTraceTests();

void runVtParserTraceTests() {
  _testVersionedRedactedTraceAndChunkIndependence();
  _testDroppedRecordDisclosure();
  _testInputAndOutputBounds();
  _testExportLimitValidation();
}

void _testVersionedRedactedTraceAndChunkIndependence() {
  final Map<String, Object?> fixture = _fixture();
  final Uint8List input = _decodeHex(fixture['input_hex']! as String);
  final String whole = _trace(input);
  for (var split = 0; split <= input.length; split++) {
    _expect(
      _trace(input, <int>[split, input.length - split]) == whole,
      'trace is independent of split $split',
    );
  }
  _expect(
    _trace(input, List<int>.filled(input.length, 1)) == whole,
    'trace is independent of bytewise input',
  );
  final String expected = File('test/corpus/parser/sequence_trace_v1.json')
      .readAsStringSync();
  _expect(whole == expected, 'committed trace matches the reviewed fixture');
  _expect(
    !whole.contains('secret') &&
        !whole.contains('private title') &&
        !whole.contains('private payload') &&
        !whole.contains('736563726574') &&
        !whole.contains('70726976617465'),
    'printable and string payload content is absent in text and hex form',
  );

  final Map<String, Object?> report = jsonDecode(whole) as Map<String, Object?>;
  _expect(
    report['format'] == VtParserTraceExporter.formatName &&
        report['version'] == VtParserTraceExporter.formatVersion &&
        report['input_bytes'] == input.length &&
        report['printable_scalars'] == 7 &&
        report['events_total'] == 11 &&
        report['events_retained'] == 11,
    'trace identity and aggregate counts are exact',
  );
  final Map<String, Object?> privacy =
      report['privacy']! as Map<String, Object?>;
  _expect(
    privacy.values.every((Object? value) => value != null) &&
        privacy['string_payloads'] == 'length_only' &&
        privacy['input_hash'] == 'omitted' &&
        privacy['wall_clock'] == 'omitted',
    'privacy policy is explicit and deterministic',
  );
  final Map<String, Object?> limits = report['limits']! as Map<String, Object?>;
  _expect(
    (limits['parser']! as Map<String, Object?>)['string_bytes'] == 16 &&
        (limits['parser']!
                as Map<String, Object?>)['application_program_command_bytes'] ==
            4610 &&
        (limits['inspector']! as Map<String, Object?>)['records'] == 64 &&
        (limits['export']! as Map<String, Object?>)['output_bytes'] == 1048576,
    'all reproduction and serialization bounds are exported',
  );
  final Map<String, Object?> counts =
      report['event_counts']! as Map<String, Object?>;
  _expect(
    counts.length == VtParserInspectionKind.values.length &&
        counts['escape'] == 2 &&
        counts.values.fold<int>(
              0,
              (int sum, Object? value) => sum + (value! as int),
            ) ==
            11,
    'all event families have exact aggregate counts',
  );
  final List<Object?> events = report['events']! as List<Object?>;
  final Map<String, Object?> csi = events[2]! as Map<String, Object?>;
  final Map<String, Object?> osc = events[3]! as Map<String, Object?>;
  _expect(
    csi['canonical_bytes_hex'] == '1b5b3f323568' &&
        csi['parameters'].toString() == '[25]' &&
        osc['canonical_prefix_hex'] == '1b5d' &&
        osc['payload_redacted_bytes'] == 15 &&
        osc['canonical_terminator_hex'] == '07',
    'canonical syntax evidence and redacted string envelope are exact',
  );
}

void _testDroppedRecordDisclosure() {
  final VtParserInspector inspector = VtParserInspector(
    downstream: const _Sink(),
    limits: const VtParserInspectorLimits(maxRecords: 1, maxMetadataBytes: 96),
  );
  final VtParser parser = VtParser(sink: inspector);
  parser.parse(Uint8List.fromList(const <int>[0x07, 0x08]));
  parser.finish();
  final Map<String, Object?> report = jsonDecode(
    VtParserTraceExporter().format(inspector, inputBytes: 2),
  ) as Map<String, Object?>;
  final List<Object?> events = report['events']! as List<Object?>;
  _expect(
    report['events_total'] == 2 &&
        report['events_retained'] == 1 &&
        report['events_evicted'] == 1 &&
        (events.single! as Map<String, Object?>)['ordinal'] == 2,
    'trace discloses deterministic FIFO truncation without renumbering',
  );
}

void _testInputAndOutputBounds() {
  final VtParserTraceExporter inputBounded = VtParserTraceExporter(
    limits: const VtParserTraceExportLimits(
      maxInputBytes: 1,
      maxOutputBytes: 1024,
    ),
  );
  _expectLimit(
    () => inputBounded.capture(Uint8List.fromList(const <int>[0x41, 0x42])),
    VtParserTraceLimitKind.inputBytes,
    'input byte bound',
  );

  final VtParserTraceExporter outputBounded = VtParserTraceExporter(
    limits: const VtParserTraceExportLimits(
      maxInputBytes: 1024,
      maxOutputBytes: 128,
    ),
  );
  _expectLimit(
    () => outputBounded.capture(Uint8List.fromList(const <int>[0x07])),
    VtParserTraceLimitKind.outputBytes,
    'streaming output byte bound',
  );
}

void _testExportLimitValidation() {
  _expectArgument(
    () => VtParserTraceExporter(
      limits: const VtParserTraceExportLimits(maxInputBytes: 0),
    ),
    'zero input bound',
  );
  _expectArgument(
    () => VtParserTraceExporter(
      limits: const VtParserTraceExportLimits(maxOutputBytes: 0),
    ),
    'zero output bound',
  );
}

String _trace(Uint8List input, [List<int>? chunks]) {
  final VtParserInspector inspector = VtParserInspector(
    downstream: const _Sink(),
    limits: const VtParserInspectorLimits(
      maxRecords: 64,
      maxMetadataBytes: 16384,
    ),
  );
  final VtParser parser = VtParser(
    sink: inspector,
    limits: const VtParserLimits(
      maxSequenceBytes: 64,
      maxStringBytes: 16,
      maxParameters: 32,
      maxIntermediates: 8,
      maxNumericValue: 1000000,
    ),
  );
  if (chunks == null) {
    parser.parse(input);
  } else {
    var offset = 0;
    for (final int length in chunks) {
      parser.parse(input, offset, offset + length);
      offset += length;
    }
    _expect(offset == input.length, 'chunk plan consumes all input');
  }
  parser.finish();
  return VtParserTraceExporter().format(
    inspector,
    inputBytes: input.length,
    parserLimits: const VtParserLimits(
      maxSequenceBytes: 64,
      maxStringBytes: 16,
      maxParameters: 32,
      maxIntermediates: 8,
      maxNumericValue: 1000000,
    ),
  );
}

Map<String, Object?> _fixture() => jsonDecode(
  File('test/corpus/parser/sequence_trace_case_v1.json').readAsStringSync(),
) as Map<String, Object?>;

Uint8List _decodeHex(String value) {
  final Uint8List bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return bytes;
}

final class _Sink implements VtParserSink, VtParserAsciiSink {
  const _Sink();

  @override
  void print(int scalar) {}
  @override
  void printAscii(Uint8List bytes, int start, int end) {}
  @override
  void execute(int controlByte) {}
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

void _expectLimit(
  void Function() action,
  VtParserTraceLimitKind kind,
  String message,
) {
  try {
    action();
  } on VtParserTraceLimitException catch (error) {
    _expect(error.kind == kind, message);
    return;
  }
  throw StateError('test failed: $message');
}

void _expectArgument(void Function() action, String message) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
