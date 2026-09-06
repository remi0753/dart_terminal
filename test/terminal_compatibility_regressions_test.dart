import 'dart:io';

import '../tool/terminal_compatibility_regressions.dart';

void main() => runTerminalCompatibilityRegressionTests();

void runTerminalCompatibilityRegressionTests() {
  final String source = File(terminalCompatibilityRegressionCorpusPath)
      .readAsStringSync();
  final TerminalCompatibilityRegressionCorpus corpus =
      parseTerminalCompatibilityRegressionCorpus(source);
  final TerminalCompatibilityRegressionRun result =
      runTerminalCompatibilityRegressionCorpus(corpus);
  _expect(
    result.cases == 9 &&
        result.fixFamilies.length == 9 &&
        result.machineLine().startsWith(
          'TERMINAL_COMPATIBILITY_REGRESSIONS_PASS cases=9 ',
        ),
    'reviewed corpus totals are exact',
  );
  _expectFailure(
    source.replaceFirst('1b28306c', 'zz28306c'),
    'invalid lowercase hex',
  );
  _expectFailure(
    source.replaceFirst('"max_cases": 32', '"max_cases": 1'),
    'case count bound',
  );
  _expectFailure(
    source.replaceFirst(
      'docs/phase6/terminfo-source-compile-install-fallback.md',
      '../unsafe.md',
    ),
    'unsafe owner path',
  );
  _expectFailure(
    source.replaceFirst(
      '"id": "xtgettcap-explicit-negative"',
      '"id": "dec-special-graphics"',
    ),
    'duplicate case id',
  );
  _expectFailure(
    source.replaceFirst(
      RegExp(r'[0-9a-f]{64}'),
      List<String>.filled(64, '0').join(),
    ),
    'reviewed observation mismatch',
    parseOnly: false,
  );
}

void _expectFailure(String source, String message, {bool parseOnly = true}) {
  try {
    final TerminalCompatibilityRegressionCorpus corpus =
        parseTerminalCompatibilityRegressionCorpus(source);
    if (!parseOnly) runTerminalCompatibilityRegressionCorpus(corpus);
  } on TerminalCompatibilityRegressionException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
