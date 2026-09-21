import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-s2-product-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  try {
    var probes = 0;
    TerminalNoteS2SentinelSnapshot probe() {
      probes++;
      return TerminalNoteS2SentinelSnapshot(
        terminalOutputBytes: 41,
        terminalRows: 24,
        terminalColumns: 80,
        shellIntegrationEvents: 3,
        restorationPayloadEntries: 0,
        diagnosticContentFields: 0,
        terminalInputDeliveries: 7,
        ptyWriteEnqueuedCount: 5,
        focusReportCount: 2,
        usingAlternateScreen: true,
        applicationCursorKeys: true,
        bracketedPasteMode: true,
        focusReportingMode: true,
        mouseTrackingEnabled: true,
        mouseSgrEncoding: true,
      );
    }

    final TerminalNoteS2ProductAcceptanceResult result =
        await TerminalNoteS2ProductAcceptance.run(
          rootDirectory: root,
          sentinelProbe: probe,
        );
    _expect(result.isSuccess, 'S2 product vector did not pass');
    _expect(probes == 2, 'protected TUI state was not sampled twice');
    final String machineLine = result.machineLine();
    _expect(
      machineLine ==
              'TERMINAL_NOTE_S2_PRODUCT_PASS vectors=4 windows=2 tabs=3 '
                  'panes=5 quick=1 focus_edges=64 fifo_acks=2 '
                  'false_consumes=0 restart=1 detached=1 disabled=1 '
                  'tui_modes=1 protected_state=1 owners=0' &&
          !machineLine.contains(root.path) &&
          !machineLine.contains('s2-'),
      'S2 evidence is not fixed and content-free',
    );
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
