import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalFocusReporterTests();

void runTerminalFocusReporterTests() {
  _testModeParsingQueryAndReset();
  _testRoutingAndDuplicateSuppression();
}

void _testModeParsingQueryAndReset() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final List<String> replies = <String>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List bytes) {
      replies.add(ascii.decode(bytes));
      return true;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  final int initialGeneration = screens.focusReportingGeneration;

  parser.parse(ascii.encode('\x1b[?1004h\x1b[?1004\$p'));
  _expect(
    screens.focusReportingMode &&
        screens.focusReportingGeneration == initialGeneration + 1 &&
        replies.single == '\x1b[?1004;1\$y',
    'DECSET 1004 is terminal-owned and visible through DECRQM',
  );
  screens.setAlternateMode47(true);
  screens.resize(rows: 3, columns: 5);
  _expect(
    screens.focusReportingMode &&
        screens.focusReportingGeneration == initialGeneration + 1,
    'focus mode survives screen activation and resize',
  );
  parser.parse(ascii.encode('\x1b[?1004l\x1b[?1004\$p'));
  _expect(
    !screens.focusReportingMode &&
        screens.focusReportingGeneration == initialGeneration + 2 &&
        replies.last == '\x1b[?1004;2\$y',
    'DECRST 1004 disables reporting and advances its mode generation',
  );
  parser.parse(ascii.encode('\x1b[?1004h\x1bc'));
  _expect(
    !screens.focusReportingMode &&
        screens.focusReportingGeneration == initialGeneration + 4 &&
        sink.unsupportedSequenceCount == 0,
    'RIS resets enabled focus reporting without unsupported input',
  );
}

void _testRoutingAndDuplicateSuppression() {
  final List<Uint8List> reports = <Uint8List>[];
  final TerminalFocusReporter reporter = TerminalFocusReporter(
    onTerminalReport: reports.add,
  );

  final TerminalFocusReportResult disabled = reporter.route(
    isFocused: true,
    modeEnabled: false,
    modeGeneration: 1,
  );
  final TerminalFocusReportResult blurred = reporter.route(
    isFocused: false,
    modeEnabled: true,
    modeGeneration: 2,
  );
  final TerminalFocusReportResult duplicate = reporter.route(
    isFocused: false,
    modeEnabled: true,
    modeGeneration: 2,
  );
  final TerminalFocusReportResult focused = reporter.route(
    isFocused: true,
    modeEnabled: true,
    modeGeneration: 2,
  );
  reporter.route(isFocused: true, modeEnabled: false, modeGeneration: 3);
  final TerminalFocusReportResult reenabled = reporter.route(
    isFocused: true,
    modeEnabled: true,
    modeGeneration: 4,
  );

  _expect(
    disabled.disposition == TerminalFocusReportDisposition.modeDisabled &&
        blurred.disposition == TerminalFocusReportDisposition.terminalReport &&
        duplicate.disposition ==
            TerminalFocusReportDisposition.duplicateTransition &&
        focused.disposition == TerminalFocusReportDisposition.terminalReport &&
        reenabled.disposition ==
            TerminalFocusReportDisposition.terminalReport &&
        reports.length == 3 &&
        ascii.decode(reports[0]) == '\x1b[O' &&
        ascii.decode(reports[1]) == '\x1b[I' &&
        ascii.decode(reports[2]) == '\x1b[I' &&
        reports.every(
          (Uint8List bytes) =>
              bytes.length <= TerminalFocusReporter.maximumReportBytes,
        ),
    'enabled transitions emit exact bounded reports and suppress duplicates',
  );
  _expectThrows<UnsupportedError>(
    () => focused.terminalBytes.add(0),
    'focus route result bytes are immutable',
  );
  _expectThrows<RangeError>(
    () =>
        reporter.route(isFocused: false, modeEnabled: true, modeGeneration: 0),
    'focus mode generation must be positive',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}
