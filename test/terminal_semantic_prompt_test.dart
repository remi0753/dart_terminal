import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSemanticPromptTests();

void runTerminalSemanticPromptTests() {
  _testLifecycleProjectsPrivacySafeRowFlags();
  _testFreshLineAndNewCommandExtensions();
  _testInputUntilLineEndExtension();
  _testMalformedAndExcludedActionsFailClosed();
  _testWrappingScrollbackAndReflowRetainMarks();
  _testAlternateScreenAndResetOwnership();
  _testChunkAndTerminatorIndependence();
}

void _testFreshLineAndNewCommandExtensions() {
  final _Harness harness = _Harness(rows: 4, columns: 8);
  harness.parse('output');
  harness.parse(_osc('L'));
  _expect(
    harness.screens.primary.cursorRow == 1 &&
        harness.screens.primary.cursorColumn == 0 &&
        harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.unknown,
    'L moves a non-left-edge cursor to a fresh line without changing state',
  );
  harness.parse(_osc('L'));
  _expect(
    harness.screens.primary.cursorRow == 1,
    'L at the left edge is a no-op',
  );
  harness.parse('old');
  harness.parse(_osc('N;aid=ignored;cmdline=not-retained'));
  harness.parse(r'$ ');
  _expect(
    harness.screens.primary.cursorRow == 2 &&
        harness.screens.primary.cursorColumn == 2 &&
        harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.prompt &&
        harness.screens.primary.rowFlagsAt(2) & TerminalRowFlags.prompt != 0,
    'N composes fresh-line and prompt start without retaining options',
  );
}

void _testInputUntilLineEndExtension() {
  final _Harness harness = _Harness(rows: 4, columns: 8);
  harness.parse(_osc('A'));
  harness.parse(r'$ ');
  harness.parse(_osc('I;unknown=value'));
  harness.parse('echo');
  harness.parse('\r\n');
  _expect(
    harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.commandOutput &&
        harness.screens.primary.rowFlagsAt(0) & TerminalRowFlags.command != 0,
    'I marks input and changes to output at the next explicit line feed',
  );
  harness.parse('result');
  _expect(
    harness.screens.primary.rowFlagsAt(1) & TerminalRowFlags.output != 0,
    'content after the I line feed is classified as output',
  );

  final _Harness nel = _Harness(rows: 3, columns: 8);
  nel.parse(_osc('I'));
  nel.parse(
    'input\x1b'
    'Eoutput',
  );
  _expect(
    nel.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.commandOutput &&
        nel.screens.primary.rowFlagsAt(0) & TerminalRowFlags.command != 0 &&
        nel.screens.primary.rowFlagsAt(1) & TerminalRowFlags.output != 0,
    'I also terminates on the supported 7-bit NEL line boundary',
  );
}

void _testLifecycleProjectsPrivacySafeRowFlags() {
  final _Harness harness = _Harness(rows: 4, columns: 8);
  harness.parse(_osc('A;aid=ignored;cmdline=not-retained'));
  harness.parse(r'$ ');
  _expect(
    harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.prompt &&
        harness.screens.primary.rowFlagsAt(0) & TerminalRowFlags.prompt != 0,
    'A enters prompt state and marks the current row',
  );

  harness.parse(_osc('B;unknown=value'));
  harness.parse('echo');
  harness.parse('\r\n');
  _expect(
    harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.input &&
        harness.screens.primary.rowFlagsAt(0) & TerminalRowFlags.command != 0,
    'B classifies input without retaining its contents',
  );

  harness.parse(_osc('C'));
  harness.parse('output');
  harness.parse('\r\n');
  _expect(
    harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.commandOutput &&
        harness.screens.primary.rowFlagsAt(1) & TerminalRowFlags.output != 0,
    'C classifies following output',
  );

  harness.parse(_osc('D;0;cmdline=still-not-retained'));
  _expect(
    harness.screens.semanticPrompt.shellState ==
        TerminalSemanticShellState.unknown,
    'D ends the active command without storing status or options',
  );
  harness.parse(_osc('P;k=s'));
  _expect(
    harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.prompt &&
        harness.screens.primary.rowFlagsAt(2) & TerminalRowFlags.prompt != 0 &&
        harness.sink.unsupportedSequenceCount == 0,
    'P marks a secondary prompt through the same bounded state',
  );
}

void _testMalformedAndExcludedActionsFailClosed() {
  final _Harness harness = _Harness(rows: 2, columns: 8);
  harness.parse(_osc('A'));
  final int generation = harness.screens.semanticPrompt.generation;
  for (final String payload in <String>['L;option=bad', 'Aextra', 'X', '']) {
    harness.parse(_osc(payload));
  }
  harness.parseBytes(<int>[0x1b, 0x5d, ...ascii.encode('133;A;'), 0x80, 0x07]);
  harness.parse(_osc('A;${List<String>.filled(255, 'x').join()}'));
  _expect(
    harness.sink.unsupportedSequenceCount == 6 &&
        harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.prompt &&
        harness.screens.semanticPrompt.generation == generation,
    'excluded, malformed, and over-limit actions leave state unchanged',
  );
}

void _testWrappingScrollbackAndReflowRetainMarks() {
  final TerminalScrollback history = TerminalScrollback(
    maxLines: 8,
    maxBytes: 16 * 1024,
    pageRows: 2,
  );
  final _Harness harness = _Harness(rows: 2, columns: 4, scrollback: history);
  harness.parse(_osc('A'));
  harness.parse('prompt');
  _expect(
    harness.screens.primary.rowFlagsAt(0) & TerminalRowFlags.prompt != 0 &&
        harness.screens.primary.rowFlagsAt(1) & TerminalRowFlags.prompt != 0,
    'semantic state follows a printable autowrap onto the destination row',
  );
  harness.parse('\r\n');
  harness.parse(_osc('C'));
  harness.parse('out\r\n');
  _expect(
    history.length >= 1 && history.rowFlagsAt(0) & TerminalRowFlags.prompt != 0,
    'prompt marks enter bounded scrollback with their row',
  );

  harness.screens.resize(rows: 3, columns: 3);
  bool retainedPrompt = false;
  for (int row = 0; row < history.length; row++) {
    retainedPrompt =
        retainedPrompt ||
        history.rowFlagsAt(row) & TerminalRowFlags.prompt != 0;
  }
  for (int row = 0; row < harness.screens.primary.rows; row++) {
    retainedPrompt =
        retainedPrompt ||
        harness.screens.primary.rowFlagsAt(row) & TerminalRowFlags.prompt != 0;
  }
  _expect(retainedPrompt, 'resize/reflow retains a parsed prompt mark');
}

void _testAlternateScreenAndResetOwnership() {
  final _Harness harness = _Harness(rows: 2, columns: 6);
  harness.parse(_osc('C'));
  harness.parse('\x1b[?47h');
  harness.parse(_osc('P'));
  harness.parse('more');
  _expect(
    harness.screens.usingAlternate &&
        harness.screens.alternate.rowFlagsAt(0) & TerminalRowFlags.prompt !=
            0 &&
        harness.screens.primary.rowFlagsAt(0) == 0,
    'markers project only onto the active alternate grid',
  );
  final int generation = harness.screens.semanticPrompt.generation;
  harness.parse('\x1bc');
  _expect(
    !harness.screens.usingAlternate &&
        harness.screens.semanticPrompt.shellState ==
            TerminalSemanticShellState.unknown &&
        harness.screens.semanticPrompt.generation > generation &&
        harness.screens.primary.rowFlagsAt(0) == 0 &&
        harness.screens.alternate.rowFlagsAt(0) == 0,
    'RIS resets both row storage and transient semantic state',
  );
}

void _testChunkAndTerminatorIndependence() {
  final String stream = '${_osc('A', bell: false)}p${_osc('B')}x';
  _Harness? baseline;
  for (int split = 0; split <= stream.length; split++) {
    final _Harness harness = _Harness(rows: 2, columns: 8);
    harness.parse(stream.substring(0, split));
    harness.parse(stream.substring(split));
    harness.finish();
    baseline ??= harness;
    _expect(
      harness.screens.semanticPrompt.shellState ==
              TerminalSemanticShellState.input &&
          harness.screens.primary.rowFlagsAt(0) ==
              TerminalRowFlags.prompt | TerminalRowFlags.command &&
          harness.sink.unsupportedSequenceCount == 0,
      'OSC 133 is chunk- and BEL/ST-terminator-independent at split $split',
    );
  }
  _expect(baseline != null, 'chunk-independence baseline was created');
}

String _osc(String payload, {bool bell = true}) =>
    '\x1b]133;$payload${bell ? '\x07' : '\x1b\\'}';

final class _Harness {
  _Harness({
    required int rows,
    required int columns,
    TerminalScrollback? scrollback,
  }) : screens = TerminalScreenSet(
         rows: rows,
         columns: columns,
         scrollback: scrollback,
       ) {
    sink = TerminalScreenParserSink.forScreenSet(screens);
    parser = VtParser(sink: sink);
  }

  final TerminalScreenSet screens;
  late final TerminalScreenParserSink sink;
  late final VtParser parser;

  void parse(String value) => parseBytes(utf8.encode(value));

  void parseBytes(List<int> bytes) => parser.parse(Uint8List.fromList(bytes));

  void finish() => parser.finish();
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
