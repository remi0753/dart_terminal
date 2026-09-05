import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runVtParserTests();

void runVtParserTests() {
  _testTypedSequenceFamiliesAcrossChunks();
  _testUncapturedSequenceMetadataPath();
  _testUncapturedSequenceLimitBoundary();
  _testUtf8RecoveryAndC1PrecedenceAcrossChunks();
  _testCancellationMalformedAndGroundControls();
  _testParserLimitsAndRecovery();
  _testParserLimitBoundaries();
  _testFinishResetAndSlices();
  _testRetainedSequenceCopies();
  _testLimitValidation();
}

void _testUncapturedSequenceLimitBoundary() {
  final _UncapturedRecorder recorder = _UncapturedRecorder();
  final VtParser parser = VtParser(
    sink: recorder,
    limits: const VtParserLimits(maxSequenceBytes: 8, maxStringBytes: 2),
  );
  parser.parse(
    Uint8List.fromList(<int>[0x1b, 0x5d, ...ascii.encode('abc'), 0x07, 0x5a]),
  );
  parser.finish();
  _expect(
    parser.isGround &&
        recorder.limits == 1 &&
        recorder.sequences.isEmpty &&
        recorder.textScalars == 1,
    'uncaptured string limit rejects the sequence and recovers to printable',
  );
}

void _testUncapturedSequenceMetadataPath() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x41,
    0x1b,
    0x37,
    0x1b,
    0x5b,
    ...ascii.encode('?1;2h'),
    0x1b,
    0x5d,
    ...ascii.encode('abc'),
    0x07,
    0x1b,
    0x50,
    ...ascii.encode('1;2\u0024qxy'),
    0x1b,
    0x5c,
    0x1b,
    0x5f,
    0x7a,
    0x1b,
    0x5c,
  ]);
  final _UncapturedRecorder recorder = _UncapturedRecorder();
  final VtParser parser = VtParser(sink: recorder);
  parser.parse(input);
  parser.finish();
  _expect(parser.isGround && recorder.textScalars == 1, 'uncaptured ground');
  _expectList(recorder.sequences, const <String>[
    'escape/0/0/0/55/0/0',
    'controlSequence/63/2/0/104/0/0',
    'operatingSystemCommand/0/0/0/0/3/0',
    'deviceControlString/0/2/1/113/2/1',
    'controlString/0/0/0/0/1/1',
  ], 'uncaptured primitive sequence metadata');
}

void _testParserLimitBoundaries() {
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, ...ascii.encode('1;2;3m')]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 16,
        maxStringBytes: 8,
        maxParameters: 3,
      ),
    ).snapshot,
    const <String>['CSI private=- params=1;2;3 intermediates=- final=m'],
    'parameter count accepts its exact limit',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, 0x20, 0x6d]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 8,
        maxStringBytes: 4,
        maxIntermediates: 1,
      ),
    ).snapshot,
    const <String>['CSI private=- params=- intermediates=  final=m'],
    'intermediate count accepts its exact limit',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, 0x39, 0x6d]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 8,
        maxStringBytes: 4,
        maxNumericValue: 9,
      ),
    ).snapshot,
    const <String>['CSI private=- params=9 intermediates=- final=m'],
    'numeric value accepts its exact limit',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5d, ...ascii.encode('abcd'), 0x07]),
      null,
      const VtParserLimits(maxSequenceBytes: 8, maxStringBytes: 4),
    ).snapshot,
    const <String>['OSC terminator=bell payload="abcd"'],
    'string payload accepts its exact limit',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, 0x31, 0x6d]),
      null,
      const VtParserLimits(maxSequenceBytes: 4, maxStringBytes: 3),
    ).snapshot,
    const <String>['CSI private=- params=1 intermediates=- final=m'],
    'total sequence bytes accept their exact limit',
  );
}

void _testUtf8RecoveryAndC1PrecedenceAcrossChunks() {
  final Uint8List input = Uint8List.fromList(<int>[
    0xc2,
    0x9b,
    0x84,
    0xe2,
    0x28,
    0xa1,
    0xe2,
    0x1b,
    0x5b,
    0x30,
    0x6d,
    0x58,
  ]);
  final List<String> expected = <String>[
    'TEXT ${jsonEncode(String.fromCharCode(0x9b))}',
    'EXEC 0x84',
    'TEXT "�(��"',
    'CSI private=- params=0 intermediates=- final=m',
    'TEXT "X"',
  ];

  for (int split = 0; split <= input.length; split++) {
    _expectList(
      _parse(input, <int>[split, input.length - split]).snapshot,
      expected,
      'UTF-8 recovery and C1 precedence split $split',
    );
  }
  _expectList(
    _parse(input, List<int>.filled(input.length, 1)).snapshot,
    expected,
    'UTF-8 recovery and C1 precedence bytewise chunks',
  );
}

void _testTypedSequenceFamiliesAcrossChunks() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x41,
    0xe6,
    0x97,
    0xa5,
    0xf0,
    0x9f,
    0x98,
    0x80,
    0x0d,
    0x0a,
    0x1b,
    0x37,
    0x1b,
    0x5b,
    ...ascii.encode('31;1m'),
    0x1b,
    0x5b,
    ...ascii.encode('38:2::1:2:3m'),
    0x1b,
    0x5d,
    ...ascii.encode('0;title'),
    0x07,
    0x1b,
    0x5d,
    ...ascii.encode('8;;https://example'),
    0x1b,
    0x5c,
    0x1b,
    0x50,
    ...ascii.encode(r'$qm'),
    0x1b,
    0x5c,
    0x1b,
    0x5f,
    ...ascii.encode('payload'),
    0x1b,
    0x5c,
    0x1b,
    0x58,
    ...ascii.encode('sos'),
    0x1b,
    0x5c,
    0x9e,
    ...ascii.encode('pm'),
    0x9c,
    0x9b,
    0x30,
    0x6d,
    0x84,
    0x5a,
  ]);
  const List<String> expected = <String>[
    'TEXT "A日😀"',
    'EXEC 0x0d',
    'EXEC 0x0a',
    'ESC intermediates=- final=7',
    'CSI private=- params=31;1 intermediates=- final=m',
    'CSI private=- params=38:2::1:2:3 intermediates=- final=m',
    'OSC terminator=bell payload="0;title"',
    'OSC terminator=stringTerminator payload="8;;https://example"',
    r'DCS private=- params=- intermediates=$ final=q '
        'terminator=stringTerminator payload="m"',
    'STRING kind=applicationProgramCommand terminator=stringTerminator '
        'payload="payload"',
    'STRING kind=startOfString terminator=stringTerminator payload="sos"',
    'STRING kind=privacyMessage terminator=stringTerminator payload="pm"',
    'CSI private=- params=0 intermediates=- final=m',
    'EXEC 0x84',
    'TEXT "Z"',
  ];

  final _ParseResult whole = _parse(input);
  _expectList(whole.snapshot, expected, 'whole typed VT parser snapshot');
  for (int split = 0; split <= input.length; split++) {
    final _ParseResult divided = _parse(input, <int>[
      split,
      input.length - split,
    ]);
    _expectList(divided.snapshot, expected, 'typed VT parser split $split');
  }
  _expectList(
    _parse(input, List<int>.filled(input.length, 1)).snapshot,
    expected,
    'typed VT parser bytewise chunks',
  );
}

void _testCancellationMalformedAndGroundControls() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x18,
    0x1a,
    0x1b,
    0x5b,
    ...ascii.encode('31'),
    0x1b,
    0x5b,
    ...ascii.encode('0mX'),
    0x1b,
    0x5d,
    ...ascii.encode('bad'),
    0x1a,
    0x59,
    0x1b,
    0x5d,
    ...ascii.encode('drop'),
    0x1b,
    0x37,
    0x1b,
    0x5b,
    ...ascii.encode('1?2mOK'),
  ]);
  _expectList(_parse(input).snapshot, const <String>[
    'EXEC 0x18',
    'EXEC 0x1a',
    'CANCEL state=csiParameter byte=0x1b',
    'CSI private=- params=0 intermediates=- final=m',
    'TEXT "X"',
    'CANCEL state=oscString byte=0x1a',
    'TEXT "Y"',
    'CANCEL state=oscString byte=0x1b',
    'ESC intermediates=- final=7',
    'MALFORMED state=csiParameter byte=0x3f',
    'TEXT "OK"',
  ], 'cancel, ground control, malformed ignore, and printable recovery');
}

void _testParserLimitsAndRecovery() {
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, ...ascii.encode('1;2;3;4mX')]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 32,
        maxStringBytes: 8,
        maxParameters: 3,
      ),
    ).snapshot,
    const <String>['LIMIT state=csiParameter kind=parameters', 'TEXT "X"'],
    'parameter count limit recovers',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, ...ascii.encode('10mX')]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 16,
        maxStringBytes: 4,
        maxNumericValue: 9,
      ),
    ).snapshot,
    const <String>['LIMIT state=csiParameter kind=numericValue', 'TEXT "X"'],
    'numeric limit recovers',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, 0x20, 0x21, 0x6d, 0x58]),
      null,
      const VtParserLimits(
        maxSequenceBytes: 16,
        maxStringBytes: 4,
        maxIntermediates: 1,
      ),
    ).snapshot,
    const <String>[
      'LIMIT state=csiIntermediate kind=intermediates',
      'TEXT "X"',
    ],
    'intermediate limit recovers',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[
        0x1b,
        0x5d,
        ...ascii.encode('abcde'),
        0x07,
        0x58,
      ]),
      null,
      const VtParserLimits(maxSequenceBytes: 16, maxStringBytes: 4),
    ).snapshot,
    const <String>['LIMIT state=oscString kind=stringBytes', 'TEXT "X"'],
    'string payload limit recovers',
  );
  _expectList(
    _parse(
      Uint8List.fromList(<int>[0x1b, 0x5b, ...ascii.encode('123mX')]),
      null,
      const VtParserLimits(maxSequenceBytes: 4, maxStringBytes: 3),
    ).snapshot,
    const <String>['LIMIT state=csiParameter kind=sequenceBytes', 'TEXT "X"'],
    'total sequence byte limit recovers',
  );
}

void _testFinishResetAndSlices() {
  final _Recorder recorder = _Recorder();
  final VtParser parser = VtParser(sink: recorder);
  parser.parse(Uint8List.fromList(<int>[0xe2, 0x82]));
  parser.finish();
  parser.finish();
  parser.parse(Uint8List.fromList(<int>[0x1b, 0x5b, 0x31]));
  parser.finish();
  parser.parse(Uint8List.fromList(<int>[0x1b, 0x5d, 0x78, 0x1b]));
  parser.finish();
  parser.parse(Uint8List.fromList(<int>[0x41, 0x1b, 0x5b, 0x31]));
  parser.reset();
  parser.parse(Uint8List.fromList(<int>[0x42]));
  parser.finish();
  _expectList(recorder.snapshot, const <String>[
    'TEXT "�"',
    'INCOMPLETE state=csiParameter',
    'INCOMPLETE state=oscString',
    'TEXT "AB"',
  ], 'finish/reset are idempotent and parser remains reusable');
  _expect(parser.isGround, 'parser finishes in ground state');

  final Uint8List guarded = Uint8List.fromList(<int>[
    0xff,
    0x1b,
    0x5b,
    0x30,
    0x6d,
    0xff,
  ]);
  final _Recorder sliceRecorder = _Recorder();
  final VtParser sliceParser = VtParser(sink: sliceRecorder);
  sliceParser.parse(guarded, 1, guarded.length - 1);
  sliceParser.finish();
  _expectList(sliceRecorder.snapshot, const <String>[
    'CSI private=- params=0 intermediates=- final=m',
  ], 'parser slice excludes guard bytes');
  _expectThrowsRangeError(
    () => sliceParser.parse(Uint8List(1), -1),
    'negative parser slice start',
  );
  _expectThrowsRangeError(
    () => sliceParser.parse(Uint8List(1), 1, 0),
    'reversed parser slice',
  );
  _expectThrowsRangeError(
    () => sliceParser.parse(Uint8List(1), 0, 2),
    'parser slice beyond input',
  );
}

void _testRetainedSequenceCopies() {
  final _Recorder recorder = _Recorder();
  final VtParser parser = VtParser(sink: recorder);
  parser.parse(
    Uint8List.fromList(<int>[
      0x1b,
      0x5b,
      ...ascii.encode('?38:2::1m'),
      0x1b,
      0x5b,
      ...ascii.encode('0m'),
      0x1b,
      0x5d,
      ...ascii.encode('first'),
      0x07,
      0x1b,
      0x5d,
      ...ascii.encode('second'),
      0x07,
    ]),
  );
  parser.finish();
  final VtSequenceHeader firstCsi = recorder.csiSequences.first;
  _expect(
    firstCsi.privateMarker == 0x3f &&
        _sameNullableInts(firstCsi.parameters.toValueList(), const <int?>[
          38,
          2,
          null,
          1,
        ]) &&
        !firstCsi.parameters.isSubparameter(0) &&
        firstCsi.parameters.isSubparameter(1) &&
        firstCsi.parameters.isSubparameter(2) &&
        firstCsi.parameters.isSubparameter(3),
    'CSI retains private marker and colon subparameter structure',
  );
  _expect(
    utf8.decode(recorder.oscSequences.first.copyPayload()) == 'first',
    'dispatched string payload remains stable after parser reuse',
  );
}

void _testLimitValidation() {
  for (final VtParserLimits limits in <VtParserLimits>[
    const VtParserLimits(maxSequenceBytes: 3, maxStringBytes: 1),
    const VtParserLimits(maxSequenceBytes: 4, maxStringBytes: 4),
    const VtParserLimits(maxParameters: 0),
    const VtParserLimits(maxIntermediates: 0),
    const VtParserLimits(maxNumericValue: 0),
  ]) {
    try {
      VtParser(sink: _Recorder(), limits: limits);
    } on ArgumentError {
      continue;
    }
    throw StateError('test failed: invalid parser limits were accepted');
  }
}

final class _ParseResult {
  const _ParseResult(this.snapshot);

  final List<String> snapshot;
}

_ParseResult _parse(
  Uint8List input, [
  List<int>? chunks,
  VtParserLimits limits = const VtParserLimits(),
]) {
  final _Recorder recorder = _Recorder();
  final VtParser parser = VtParser(sink: recorder, limits: limits);
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    parser.parse(input, offset, offset + length);
    offset += length;
  }
  _expect(offset == input.length, 'VT chunk plan consumes all input');
  parser.finish();
  _expect(parser.isGround, 'VT parser finishes in ground state');
  return _ParseResult(recorder.snapshot);
}

final class _Recorder implements VtParserSink {
  final List<String> _actions = <String>[];
  final StringBuffer _text = StringBuffer();
  final List<VtSequenceHeader> csiSequences = <VtSequenceHeader>[];
  final List<VtStringSequence> oscSequences = <VtStringSequence>[];

  List<String> get snapshot {
    _flushText();
    return List<String>.unmodifiable(_actions);
  }

  @override
  void print(int scalar) => _text.writeCharCode(scalar);

  @override
  void execute(int controlByte) {
    _flushText();
    _actions.add('EXEC 0x${_hexByte(controlByte)}');
  }

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    _flushText();
    _actions.add(
      'ESC intermediates=${_asciiOrDash(sequence.copyIntermediates())} '
      'final=${String.fromCharCode(sequence.finalByte)}',
    );
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    _flushText();
    csiSequences.add(sequence);
    _actions.add('CSI ${_formatHeader(sequence)}');
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    _flushText();
    oscSequences.add(sequence);
    _actions.add(
      'OSC terminator=${sequence.terminator.name} '
      'payload=${jsonEncode(utf8.decode(sequence.copyPayload()))}',
    );
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    _flushText();
    _actions.add(
      'DCS ${_formatHeader(sequence.header)} '
      'terminator=${sequence.terminator.name} '
      'payload=${jsonEncode(utf8.decode(sequence.copyPayload()))}',
    );
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    _flushText();
    _actions.add(
      'STRING kind=${sequence.kind.name} '
      'terminator=${sequence.terminator.name} '
      'payload=${jsonEncode(utf8.decode(sequence.copyPayload()))}',
    );
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    _flushText();
    _actions.add('CANCEL state=${state.name} byte=0x${_hexByte(controlByte)}');
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    _flushText();
    _actions.add('LIMIT state=${state.name} kind=${kind.name}');
  }

  @override
  void malformed(VtParserState state, int byte) {
    _flushText();
    _actions.add('MALFORMED state=${state.name} byte=0x${_hexByte(byte)}');
  }

  @override
  void incomplete(VtParserState state) {
    _flushText();
    _actions.add('INCOMPLETE state=${state.name}');
  }

  void _flushText() {
    if (_text.isEmpty) {
      return;
    }
    _actions.add('TEXT ${jsonEncode(_text.toString())}');
    _text.clear();
  }
}

final class _UncapturedRecorder
    implements VtParserSink, VtParserAsciiSink, VtParserUncapturedSequenceSink {
  final List<String> sequences = <String>[];
  int textScalars = 0;
  int limits = 0;

  @override
  void print(int scalar) => textScalars++;

  @override
  void printAscii(Uint8List bytes, int start, int end) {
    textScalars += end - start;
  }

  @override
  void execute(int controlByte) {}

  @override
  void dispatchEscape(VtEscapeSequence sequence) =>
      throw StateError('retained ESC must be skipped');

  @override
  void dispatchCsi(VtSequenceHeader sequence) =>
      throw StateError('retained CSI must be skipped');

  @override
  void dispatchOsc(VtStringSequence sequence) =>
      throw StateError('retained OSC must be skipped');

  @override
  void dispatchDcs(VtDcsSequence sequence) =>
      throw StateError('retained DCS must be skipped');

  @override
  void dispatchString(VtStringSequence sequence) =>
      throw StateError('retained string must be skipped');

  @override
  void dispatchUncapturedSequence(
    VtUncapturedSequenceKind kind,
    int privateMarker,
    int parameterCount,
    int intermediateCount,
    int finalByte,
    int payloadLength,
    int terminator,
  ) {
    sequences.add(
      '${kind.name}/$privateMarker/$parameterCount/$intermediateCount/'
      '$finalByte/$payloadLength/$terminator',
    );
  }

  @override
  void cancel(VtParserState state, int controlByte) {}

  @override
  void limit(VtParserState state, VtParserLimitKind kind) => limits++;

  @override
  void malformed(VtParserState state, int byte) {}

  @override
  void incomplete(VtParserState state) {}
}

String _formatHeader(VtSequenceHeader header) =>
    'private=${header.privateMarker == null ? '-' : String.fromCharCode(header.privateMarker!)} '
    'params=${_formatParameters(header.parameters)} '
    'intermediates=${_asciiOrDash(header.copyIntermediates())} '
    'final=${String.fromCharCode(header.finalByte)}';

String _formatParameters(VtParameters parameters) {
  if (parameters.length == 0) {
    return '-';
  }
  final StringBuffer result = StringBuffer();
  for (int index = 0; index < parameters.length; index++) {
    if (index != 0) {
      result.write(parameters.isSubparameter(index) ? ':' : ';');
    }
    final int? value = parameters.valueAt(index);
    if (value != null) {
      result.write(value);
    }
  }
  return result.toString();
}

String _asciiOrDash(Uint8List bytes) =>
    bytes.isEmpty ? '-' : String.fromCharCodes(bytes);

String _hexByte(int byte) => byte.toRadixString(16).padLeft(2, '0');

bool _sameNullableInts(List<int?> first, List<int?> second) {
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

void _expectThrowsRangeError(void Function() action, String message) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectList(List<String> actual, List<String> expected, String message) {
  if (actual.length != expected.length) {
    throw StateError(
      'test failed: $message; length ${actual.length} != ${expected.length}; '
      'actual=$actual expected=$expected',
    );
  }
  for (int index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      throw StateError(
        'test failed: $message; index $index; '
        'actual=$actual expected=$expected',
      );
    }
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError('test failed: $message');
  }
}
