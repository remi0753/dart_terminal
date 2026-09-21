import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-s1-product-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  try {
    var probes = 0;
    TerminalNoteS1SentinelSnapshot probe() {
      probes++;
      return TerminalNoteS1SentinelSnapshot(
        terminalOutputBytes: 37,
        terminalRows: 24,
        terminalColumns: 80,
        shellIntegrationEvents: 3,
        restorationPayloadEntries: 0,
        diagnosticContentFields: 0,
      );
    }

    final TerminalNoteS1ProductAcceptanceResult result =
        await TerminalNoteS1ProductAcceptance.run(
          rootDirectory: root,
          sentinelProbe: probe,
        );
    _expect(result.isSuccess, 'S1 product vector did not pass');
    _expect(probes == 2, 'protected product state was not sampled twice');
    final String machineLine = result.machineLine();
    _expect(
      machineLine.startsWith('TERMINAL_NOTE_S1_PRODUCT_PASS ') &&
          machineLine.contains('windows=2 tabs=3 panes=5 quick=1') &&
          machineLine.contains('native_faults=2') &&
          machineLine.contains('owners=0') &&
          !machineLine.contains(root.path) &&
          !machineLine.contains('s1-vector'),
      'S1 evidence is not fixed and content-free',
    );
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
