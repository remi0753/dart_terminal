import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalPreeditTests();

void runTerminalPreeditTests() {
  _testUnicodeClustersAndSanitization();
  _testRangesAndPayloadBounds();
  _testLayoutWrapSelectionAndClipping();
  _testMonotonicModelUpdates();
}

void _testUnicodeClustersAndSanitization() {
  final TerminalPreeditState state = TerminalPreeditState(
    generation: 1,
    text: 'A\u0301界👩‍💻\n\u0301',
    selectionLocation: 3,
    selectionLength: 5,
  );
  _expect(
    state.clusters.length == 5 &&
        state.clusters[0].text == 'A\u0301' &&
        state.clusters[0].width == 1 &&
        state.clusters[1].text == '界' &&
        state.clusters[1].width == 2 &&
        state.clusters[2].text == '👩‍💻' &&
        state.clusters[2].utf16Start == 3 &&
        state.clusters[2].utf16Length == 5 &&
        state.clusters[2].width == 2 &&
        state.clusters[3].text == '\ufffd' &&
        state.clusters[4].text == '\u25cc\u0301' &&
        state.clusters[4].width == 1,
    'preedit uses Unicode grapheme widths and sanitizes control/standalone marks',
  );

  final TerminalPreeditState boundedCluster = TerminalPreeditState(
    generation: 2,
    text: 'a${List<String>.filled(70, '\u0301').join()}',
    selectionLocation: 0,
    selectionLength: 0,
  );
  _expect(
    boundedCluster.clusters.length == 2 &&
        boundedCluster.clusters.first.utf16Length ==
            TerminalPreeditState.maximumScalarsPerCluster &&
        boundedCluster.clusters.last.text.startsWith('\u25cc'),
    'pathological extending sequences split at the scalar resource limit',
  );
}

void _testRangesAndPayloadBounds() {
  _expectThrows<ArgumentError>(
    () => TerminalPreeditState(
      generation: 1,
      text: '😀',
      selectionLocation: 1,
      selectionLength: 0,
    ),
    'UTF-16 ranges cannot split a surrogate pair',
  );
  _expectThrows<RangeError>(
    () => TerminalPreeditState(
      generation: 1,
      text: 'abc',
      selectionLocation: 2,
      selectionLength: 2,
    ),
    'selection range stays inside preedit text',
  );
  _expectThrows<RangeError>(
    () => TerminalPreeditState(
      generation: 1,
      text: List<String>.filled(
        TerminalPreeditState.maximumTextBytes + 1,
        'a',
      ).join(),
      selectionLocation: 0,
      selectionLength: 0,
    ),
    'preedit text enforces the native UTF-8 payload limit',
  );
}

void _testLayoutWrapSelectionAndClipping() {
  final TerminalPreeditState state = TerminalPreeditState(
    generation: 1,
    text: '界ABC',
    selectionLocation: 0,
    selectionLength: 1,
  );
  final TerminalPreeditLayout layout = TerminalPreeditLayout.compute(
    state: state,
    startRow: 0,
    startColumn: 3,
    rows: 2,
    columns: 4,
  );
  _expect(
    layout.cells.length == 3 &&
        layout.cells[0].row == 1 &&
        layout.cells[0].column == 0 &&
        layout.cells[0].width == 2 &&
        layout.cells[0].isSelected &&
        layout.cells[1].column == 2 &&
        layout.cells[2].column == 3 &&
        layout.caretRow == 1 &&
        layout.caretColumn == 2 &&
        layout.isClipped,
    'wide preedit wraps before the right edge and clips beyond the viewport',
  );

  final TerminalPreeditLayout graphemeCaret = TerminalPreeditLayout.compute(
    state: TerminalPreeditState(
      generation: 2,
      text: 'A\u0301B',
      selectionLocation: 1,
      selectionLength: 0,
    ),
    startRow: 0,
    startColumn: 0,
    rows: 1,
    columns: 4,
  );
  _expect(
    graphemeCaret.caretColumn == 1,
    'a UTF-16 caret inside a grapheme snaps after the whole terminal cluster',
  );
}

void _testMonotonicModelUpdates() {
  final TerminalPreeditModel model = TerminalPreeditModel();
  final bool first = model.update(
    generation: 2,
    text: 'かな',
    selectionLocation: 2,
    selectionLength: 0,
  );
  final bool stale = model.update(
    generation: 1,
    text: 'stale',
    selectionLocation: 0,
    selectionLength: 0,
  );
  final bool cleared = model.clear(generation: 3);
  final bool staleClear = model.clear(generation: 2);
  _expect(
    first &&
        !stale &&
        cleared &&
        !staleClear &&
        !model.state.isActive &&
        model.state.generation == 3,
    'only the newest composition generation changes preedit state',
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
