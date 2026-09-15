import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalInputMatrixTests();

void runTerminalInputMatrixTests() {
  final TerminalInputAcceptanceMatrix matrix =
      TerminalInputAcceptanceMatrix.standard;
  final TerminalKeyEncoder encoder = TerminalKeyEncoder();
  for (final TerminalInputMatrixRow row in matrix.rows) {
    switch (row.delivery) {
      case TerminalInputMatrixDelivery.committedText:
        _expect(
          row.expectedBytesPerEvent.toString() ==
              utf8.encode(row.committedText!).toString(),
          '${row.id} uses exact committed UTF-8',
        );
      case TerminalInputMatrixDelivery.rawKey:
        _expect(
          encoder.encode(row.keyEvent!).toString() ==
              row.expectedBytesPerEvent.toString(),
          '${row.id} uses the product normal-mode key encoder',
        );
    }
  }
  _expect(
    TerminalInputAcceptanceMatrix.version == 2 &&
        matrix.rows.length == 14 &&
        matrix.eventCount == 15 &&
        matrix.expectedBytes.length == 55 &&
        matrix.expectedHex ==
            '6141c2a55fc3a9e4b8ade69687e697a5e69cace8aa9e'
                'ed959ceab880f09f91a9e2808df09f92bbe28c98'
                '1b5b431b5b431b5b431b621b66' &&
        <TerminalInputMatrixCategory>{
              for (final TerminalInputMatrixRow row in matrix.rows)
                row.category,
            }.length ==
            TerminalInputMatrixCategory.values.length,
    'standard matrix has stable row/event/byte/category identity',
  );

  _expectThrows<ArgumentError>(
    () => TerminalInputAcceptanceMatrix(<TerminalInputMatrixRow>[
      matrix.rows.first,
      matrix.rows.first,
    ], requireAllCategories: false),
    'duplicate row IDs are rejected',
  );
  _expectThrows<ArgumentError>(
    () => TerminalInputAcceptanceMatrix(<TerminalInputMatrixRow>[
      matrix.rows.first,
    ]),
    'complete matrices require every category',
  );
  _expectThrows<ArgumentError>(
    () => TerminalInputMatrixRow.committed(
      id: 'Not Stable',
      category: TerminalInputMatrixCategory.us,
      text: 'x',
    ),
    'row IDs are stable lowercase identifiers',
  );
  _expectThrows<RangeError>(
    () => TerminalInputMatrixRow.raw(
      id: 'unbounded-repeat',
      category: TerminalInputMatrixCategory.keyRepeat,
      event: const TerminalKeyEvent(
        physicalKey: TerminalPhysicalKey.arrowRight,
      ),
      repetitions: 33,
      expectedBytesPerEvent: const <int>[0x1b],
    ),
    'repeat count is bounded',
  );
  _expectThrows<UnsupportedError>(
    () => matrix.rows.add(matrix.rows.first),
    'matrix row collection is immutable',
  );
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
