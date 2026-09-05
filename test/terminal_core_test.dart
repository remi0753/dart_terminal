import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/src/terminal_core/streaming_utf8_decoder.dart';
import 'package:dart_terminal/src/terminal_core/vt_parser_table.dart';

import '../tool/generate_vt_parser_table.dart' as table_generator;

void main() => runTerminalCoreTests();

void runTerminalCoreTests() {
  _testValidUtf8Boundaries();
  _testMalformedUtf8Recovery();
  _testUtf8ChunkAndSliceIndependence();
  _testUtf8FinishAndReset();
  _testUtf8SliceValidation();
  _testParserTableCoverage();
  _testParserTableTransitions();
  _testParserTableGeneration();
}

void _testValidUtf8Boundaries() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x00,
    0x41,
    0x7f,
    0xc2,
    0x80,
    0xdf,
    0xbf,
    0xe0,
    0xa0,
    0x80,
    0xed,
    0x9f,
    0xbf,
    0xee,
    0x80,
    0x80,
    0xef,
    0xbf,
    0xbf,
    0xf0,
    0x90,
    0x80,
    0x80,
    0xf4,
    0x8f,
    0xbf,
    0xbf,
  ]);
  _expectList(_decode(input), const <int>[
    0x00,
    0x41,
    0x7f,
    0x80,
    0x7ff,
    0x800,
    0xd7ff,
    0xe000,
    0xffff,
    0x10000,
    0x10ffff,
  ], 'valid UTF-8 scalar boundaries');
}

void _testMalformedUtf8Recovery() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x80,
    0xbf,
    0xc0,
    0xc1,
    0xf5,
    0xff,
    0xe2,
    0x28,
    0xa1,
    0xe0,
    0x80,
    0x80,
    0xed,
    0xa0,
    0x80,
    0xf4,
    0x90,
    0x80,
    0x80,
    0xc2,
    0x41,
    0xef,
    0xbf,
    0xbd,
  ]);
  _expectList(_decode(input), <int>[
    ...List<int>.filled(6, StreamingUtf8Decoder.replacementScalar),
    StreamingUtf8Decoder.replacementScalar,
    0x28,
    StreamingUtf8Decoder.replacementScalar,
    StreamingUtf8Decoder.replacementScalar,
    StreamingUtf8Decoder.replacementScalar,
    StreamingUtf8Decoder.replacementScalar,
    StreamingUtf8Decoder.replacementScalar,
    0x41,
    StreamingUtf8Decoder.replacementScalar,
  ], 'malformed UTF-8 replacement and byte-order recovery');
}

void _testUtf8ChunkAndSliceIndependence() {
  final Uint8List input = Uint8List.fromList(<int>[
    0x41,
    0xe6,
    0x97,
    0xa5,
    0xf0,
    0x9f,
    0x98,
    0x80,
    0xe2,
    0x28,
    0xa1,
    0xc2,
  ]);
  final List<int> expected = _decode(input);
  for (int split = 0; split <= input.length; split++) {
    _expectList(
      _decode(input, <int>[split, input.length - split]),
      expected,
      'UTF-8 single split $split',
    );
  }
  _expectList(
    _decode(input, List<int>.filled(input.length, 1)),
    expected,
    'UTF-8 bytewise chunks',
  );

  final Uint8List guarded = Uint8List.fromList(<int>[0xff, ...input, 0xff]);
  final List<int> sliced = <int>[];
  final StreamingUtf8Decoder decoder = StreamingUtf8Decoder(
    onScalar: sliced.add,
  );
  decoder.decode(guarded, 1, guarded.length - 1);
  decoder.finish();
  _expectList(sliced, expected, 'UTF-8 non-zero slice excludes guard bytes');
}

void _testUtf8FinishAndReset() {
  final List<int> scalars = <int>[];
  final StreamingUtf8Decoder decoder = StreamingUtf8Decoder(
    onScalar: scalars.add,
  );
  decoder.decode(Uint8List.fromList(<int>[0xe2, 0x82]));
  _expect(
    !decoder.isAccepting && decoder.pendingContinuationCount == 1,
    'decoder retains only partial UTF-8 state',
  );
  decoder.finish();
  decoder.finish();
  decoder.decode(Uint8List.fromList(<int>[0x41]));
  decoder.decode(Uint8List.fromList(<int>[0xf0, 0x9f]));
  decoder.reset();
  decoder.decode(Uint8List.fromList(<int>[0x42]));
  decoder.finish();
  _expectList(scalars, const <int>[
    StreamingUtf8Decoder.replacementScalar,
    0x41,
    0x42,
  ], 'finish flushes once and reset silently discards pending state');
  _expect(decoder.isAccepting, 'decoder is reusable after finish and reset');
}

void _testUtf8SliceValidation() {
  final StreamingUtf8Decoder decoder = StreamingUtf8Decoder(onScalar: (_) {});
  _expectThrowsRangeError(
    () => decoder.decode(Uint8List(1), -1),
    'negative UTF-8 slice start',
  );
  _expectThrowsRangeError(
    () => decoder.decode(Uint8List(1), 1, 0),
    'reversed UTF-8 slice',
  );
  _expectThrowsRangeError(
    () => decoder.decode(Uint8List(1), 0, 2),
    'UTF-8 slice beyond input',
  );
}

void _testParserTableCoverage() {
  _expect(
    VtParserTable.stateCount == VtParserState.values.length &&
        VtParserTable.actionCount == VtParserAction.values.length,
    'generated state and action counts match enums',
  );
  int sequenceStartCount = 0;
  for (int state = 0; state < VtParserTable.stateCount; state++) {
    _expect(
      VtParserTable.entryActionIdUnchecked(state) >= 0 &&
          VtParserTable.entryActionIdUnchecked(state) <
              VtParserTable.actionCount &&
          VtParserTable.exitActionIdUnchecked(state) >= 0 &&
          VtParserTable.exitActionIdUnchecked(state) <
              VtParserTable.actionCount,
      'state $state entry/exit actions are valid',
    );
    for (int byte = 0; byte < VtParserTable.byteCount; byte++) {
      final int nextState = VtParserTable.nextStateIdUnchecked(state, byte);
      final int action = VtParserTable.transitionActionIdUnchecked(state, byte);
      final bool startsSequence =
          VtParserTable.transitionStartsSequenceUnchecked(state, byte);
      if (startsSequence) {
        sequenceStartCount++;
      }
      _expect(
        nextState >= 0 &&
            nextState < VtParserTable.stateCount &&
            action >= 0 &&
            action < VtParserTable.actionCount,
        'state $state byte $byte has valid generated IDs',
      );
    }
  }
  _expect(
    sequenceStartCount > 0 &&
        sequenceStartCount < VtParserTable.stateCount * VtParserTable.byteCount,
    'generated table identifies introducers separately from ordinary loops',
  );
  _expectThrowsRangeError(
    () => VtParserTable.nextState(VtParserState.ground, -1),
    'checked parser table rejects a negative byte',
  );
  _expectThrowsRangeError(
    () => VtParserTable.transitionAction(VtParserState.ground, 256),
    'checked parser table rejects a byte above 255',
  );
}

void _testParserTableTransitions() {
  _expectTransition(
    VtParserState.ground,
    0x41,
    VtParserState.ground,
    VtParserAction.print,
  );
  _expectTransition(
    VtParserState.ground,
    0xe2,
    VtParserState.ground,
    VtParserAction.utf8,
  );
  _expectTransition(
    VtParserState.ground,
    0x1b,
    VtParserState.escape,
    VtParserAction.none,
  );
  _expect(
    VtParserTable.entryAction(VtParserState.escape) == VtParserAction.clear,
    'escape entry clears sequence state',
  );
  _expect(
    VtParserTable.transitionStartsSequence(VtParserState.escape, 0x1b),
    'ESC explicitly re-enters escape so sequence state is cleared',
  );
  _expectTransition(
    VtParserState.escape,
    0x5b,
    VtParserState.csiEntry,
    VtParserAction.none,
  );
  _expectTransition(
    VtParserState.csiEntry,
    0x3f,
    VtParserState.csiParameter,
    VtParserAction.collect,
  );
  _expectTransition(
    VtParserState.csiParameter,
    0x3a,
    VtParserState.csiParameter,
    VtParserAction.parameter,
  );
  _expectTransition(
    VtParserState.csiParameter,
    0x6d,
    VtParserState.ground,
    VtParserAction.csiDispatch,
  );
  _expectTransition(
    VtParserState.csiParameter,
    0x18,
    VtParserState.ground,
    VtParserAction.cancel,
  );
  _expectTransition(
    VtParserState.escape,
    0x5d,
    VtParserState.oscString,
    VtParserAction.none,
  );
  _expect(
    VtParserTable.entryAction(VtParserState.oscString) ==
            VtParserAction.oscStart &&
        VtParserTable.exitAction(VtParserState.oscString) ==
            VtParserAction.oscEnd,
    'OSC state has generated start/end lifecycle actions',
  );
  _expectTransition(
    VtParserState.oscString,
    0x78,
    VtParserState.oscString,
    VtParserAction.oscPut,
  );
  _expect(
    VtParserTable.transitionStartsSequence(VtParserState.oscString, 0x9d),
    'C1 OSC explicitly ends and restarts an OSC string',
  );
  _expectTransition(
    VtParserState.oscString,
    0x07,
    VtParserState.ground,
    VtParserAction.none,
  );
  _expectTransition(
    VtParserState.dcsEntry,
    0x71,
    VtParserState.dcsPassthrough,
    VtParserAction.none,
  );
  _expect(
    VtParserTable.entryAction(VtParserState.dcsPassthrough) ==
            VtParserAction.dcsHook &&
        VtParserTable.exitAction(VtParserState.dcsPassthrough) ==
            VtParserAction.dcsUnhook,
    'DCS passthrough has generated hook/unhook lifecycle actions',
  );
  _expectTransition(
    VtParserState.dcsPassthrough,
    0x78,
    VtParserState.dcsPassthrough,
    VtParserAction.dcsPut,
  );
  _expectTransition(
    VtParserState.dcsPassthrough,
    0x9c,
    VtParserState.ground,
    VtParserAction.none,
  );
  _expectTransition(
    VtParserState.escape,
    0x5f,
    VtParserState.sosPmApcString,
    VtParserAction.none,
  );
  _expectTransition(
    VtParserState.sosPmApcString,
    0x78,
    VtParserState.sosPmApcString,
    VtParserAction.stringPut,
  );
  _expectTransition(
    VtParserState.ground,
    0x9b,
    VtParserState.csiEntry,
    VtParserAction.none,
  );
}

void _testParserTableGeneration() {
  final String first = table_generator.generateVtParserTableSource();
  final String second = table_generator.generateVtParserTableSource();
  _expect(first == second, 'VT parser table generation is deterministic');
  final String checkedIn = File(
    'lib/src/terminal_core/generated/vt_parser_table.g.dart',
  ).readAsStringSync();
  _expect(first == checkedIn, 'checked-in VT parser table is fresh');
}

List<int> _decode(Uint8List input, [List<int>? chunks]) {
  final List<int> scalars = <int>[];
  final StreamingUtf8Decoder decoder = StreamingUtf8Decoder(
    onScalar: scalars.add,
  );
  int offset = 0;
  for (final int length in chunks ?? <int>[input.length]) {
    decoder.decode(input, offset, offset + length);
    offset += length;
  }
  _expect(offset == input.length, 'UTF-8 chunk plan consumes input');
  decoder.finish();
  _expect(decoder.isAccepting, 'UTF-8 decoder finishes in accepting state');
  return scalars;
}

void _expectTransition(
  VtParserState state,
  int byte,
  VtParserState nextState,
  VtParserAction action,
) {
  _expect(
    VtParserTable.nextState(state, byte) == nextState &&
        VtParserTable.transitionAction(state, byte) == action,
    '${state.name} byte 0x${byte.toRadixString(16)} transitions to '
    '${nextState.name}/${action.name}',
  );
}

void _expectThrowsRangeError(void Function() action, String message) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectList(List<int> actual, List<int> expected, String message) {
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
