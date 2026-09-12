import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalDiagnosticsTests();

Future<void> runTerminalDiagnosticsTests() async {
  _testDeterministicPrivacySafeModel();
  _testInspectorTextBound();
  await _testSessionCaptureLifecycle();
  await _testAtomicWriter();
}

void _testDeterministicPrivacySafeModel() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 4, columns: 20);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParserInspector inspector = VtParserInspector(downstream: sink);
  final VtParser parser = VtParser(sink: inspector);
  parser.parse(
    Uint8List.fromList(<int>[
      ...utf8.encode('secret printable text'),
      0x07,
      0x1b,
      0x5d,
      ...utf8.encode('0;private title'),
      0x07,
    ]),
  );
  final TerminalDiagnosticsSnapshot snapshot = _snapshot(
    parser: TerminalDiagnosticsParserSnapshot.capture(
      inspector: inspector,
      sink: sink,
    ),
  );
  const TerminalDiagnosticsFormatter formatter = TerminalDiagnosticsFormatter();
  final Uint8List first = formatter.encode(snapshot);
  parser.parse(Uint8List.fromList(const <int>[0x08]));
  final Uint8List second = formatter.encode(snapshot);
  _expect(
    _bytesEqual(first, second),
    'immutable snapshot produces deterministic bytes after later parsing',
  );
  final String text = utf8.decode(first);
  _expect(
    !text.contains('secret printable text') &&
        !text.contains('private title') &&
        !text.contains('/Users/') &&
        !text.contains('HOME='),
    'export omits printable text, string payloads, paths, and environment',
  );
  final Map<String, Object?> report = jsonDecode(text) as Map<String, Object?>;
  _expect(
    report.keys.join(',') ==
        'format,version,privacy,limits,application,hierarchy,focused_pane,'
            'parser,renderer,configuration,features',
    'schema exposes only the ordered top-level allowlist',
  );
  final Map<String, Object?> parserReport =
      report['parser']! as Map<String, Object?>;
  final Map<String, Object?> inspection =
      parserReport['inspection']! as Map<String, Object?>;
  _expect(
    report['format'] == TerminalDiagnosticsFormatter.formatName &&
        report['version'] == TerminalDiagnosticsFormatter.formatVersion &&
        inspection['printable_scalars'] == 21 &&
        inspection['events_total'] == 2,
    'versioned report retains only bounded parser metadata',
  );
}

void _testInspectorTextBound() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 2);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParserInspector inspector = VtParserInspector(
    downstream: sink,
    limits: const VtParserInspectorLimits(
      maxRecords: 8192,
      maxMetadataBytes: 1024 * 1024,
    ),
  );
  for (var index = 0; index < 8192; index++) {
    inspector.execute(0x07);
  }
  final TerminalDiagnosticsSnapshot snapshot = _snapshot(
    parser: TerminalDiagnosticsParserSnapshot.capture(
      inspector: inspector,
      sink: sink,
    ),
  );
  _expectThrows<TerminalDiagnosticsLimitException>(
    () => const TerminalDiagnosticsFormatter().encode(snapshot),
    'bundle output cap',
  );
  final String rendered = const TerminalDiagnosticsFormatter().formatInspector(
    snapshot,
  );
  _expect(
    utf8.encode(rendered).length <=
            TerminalDiagnosticsFormatter.maximumInspectorTextUtf8Bytes &&
        rendered.contains('"truncated": true') &&
        rendered.contains('"events_total": 8192'),
    'oversized inspector rendering becomes a bounded content-free summary',
  );
}

Future<void> _testSessionCaptureLifecycle() async {
  var observed = 0;
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(1), generation: 1),
    onChanged: () {},
    onTerminated: () {},
  );
  _expect(
    !session.diagnosticsCaptureEnabled &&
        session.captureParserDiagnostics().inspection.events.isEmpty,
    'product session constructs its parser decorator with capture disabled',
  );
  session.parserInspector.execute(0x07);
  _expect(
    session.captureParserDiagnostics().inspection.totalEventCount == 0,
    'closed session capture retains no parser metadata',
  );
  session.beginDiagnosticsCapture(onEvent: (_) => observed++);
  session.parserInspector
    ..print(0x73)
    ..execute(0x08);
  final TerminalDiagnosticsFocusedPaneSnapshot focused = session
      .captureFocusedPaneDiagnostics(
        lifecycle: TerminalDiagnosticsPaneLifecycle.running,
      );
  _expect(
    session.diagnosticsCaptureEnabled &&
        observed == 1 &&
        session.captureParserDiagnostics().inspection.printableScalarCount ==
            1 &&
        focused.present &&
        focused.rows == 23 &&
        focused.columns == 100 &&
        focused.lifecycle == TerminalDiagnosticsPaneLifecycle.running,
    'session publishes a content-free focused-pane/parser snapshot',
  );
  await session.shutdown();
  _expect(
    !session.diagnosticsCaptureEnabled &&
        session.captureParserDiagnostics().inspection.events.isEmpty,
    'session shutdown disables and clears parser capture',
  );
}

Future<void> _testAtomicWriter() async {
  final _FakeDiagnosticsFiles files = _FakeDiagnosticsFiles()
    ..destinations['/tmp/report.json'] = Uint8List.fromList(<int>[9]);
  final TerminalDiagnosticsAtomicWriter writer =
      TerminalDiagnosticsAtomicWriter(files: files);
  final Uint8List bytes = Uint8List.fromList(utf8.encode('{"ok":true}\n'));
  files.collisionCount = 1;
  final TerminalDiagnosticsExportResult success = await writer.write(
    destinationPath: '/tmp/report.json',
    bytes: bytes,
  );
  _expect(
    success.disposition == TerminalDiagnosticsExportDisposition.written &&
        success.byteCount == bytes.length &&
        _bytesEqual(files.destinations['/tmp/report.json']!, bytes) &&
        files.temporaryFiles.isEmpty &&
        files.flushEquivalentWriteCount == 1,
    'exclusive sibling temporary write replaces destination only when complete',
  );

  files
    ..destinations['/tmp/report.json'] = Uint8List.fromList(<int>[7, 7])
    ..failReplace = true;
  final TerminalDiagnosticsExportResult failure = await writer.write(
    destinationPath: '/tmp/report.json',
    bytes: bytes,
  );
  _expect(
    failure.disposition == TerminalDiagnosticsExportDisposition.failed &&
        failure.byteCount == 0 &&
        _bytesEqual(
          files.destinations['/tmp/report.json']!,
          Uint8List.fromList(<int>[7, 7]),
        ) &&
        files.temporaryFiles.isEmpty,
    'failed rename preserves old destination and cleans the temporary file',
  );
  _expect(
    (await writer.write(
          destinationPath: 'relative.json',
          bytes: bytes,
        )).disposition ==
        TerminalDiagnosticsExportDisposition.failed,
    'writer rejects non-absolute destinations without file activity',
  );

  final Directory directory = await Directory.systemTemp.createTemp(
    'dart-terminal-diagnostics-test-',
  );
  try {
    final File destination = File('${directory.path}/report.json');
    await destination.writeAsBytes(const <int>[1, 2, 3], flush: true);
    final TerminalDiagnosticsExportResult local =
        await TerminalDiagnosticsAtomicWriter().write(
          destinationPath: destination.path,
          bytes: bytes,
        );
    final List<FileSystemEntity> siblings = await directory.list().toList();
    _expect(
      local.disposition == TerminalDiagnosticsExportDisposition.written &&
          _bytesEqual(await destination.readAsBytes(), bytes) &&
          siblings.length == 1 &&
          siblings.single.path == destination.path,
      'local exclusive write flushes, atomically replaces, and leaves no temp',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

TerminalDiagnosticsSnapshot _snapshot({
  required TerminalDiagnosticsParserSnapshot parser,
}) => TerminalDiagnosticsSnapshot(
  application: TerminalDiagnosticsApplicationSnapshot(
    runtimeKind: TerminalDiagnosticsRuntimeKind.developerJit,
    appKitEventProtocol: 14,
    language: TerminalDiagnosticsLanguage.english,
    direction: TerminalDiagnosticsDirection.leftToRight,
    reduceMotion: false,
    increaseContrast: false,
    differentiateWithoutColor: false,
  ),
  hierarchy: TerminalDiagnosticsHierarchySnapshot(
    windowCount: 1,
    tabCount: 1,
    paneCount: 1,
    livePaneCount: 1,
    activeWindowRole: TerminalDiagnosticsWindowRole.standard,
  ),
  focusedPane: TerminalDiagnosticsFocusedPaneSnapshot.unavailable(),
  parser: parser,
  renderer: TerminalDiagnosticsRendererSnapshot.unavailable(),
  configuration: TerminalDiagnosticsConfigurationSnapshot(
    schemaOptionCount: 32,
    effectiveGeneration: 1,
    attemptGeneration: 1,
    warningCount: 0,
    errorCount: 0,
    liveOptionCount: 10,
    newSessionOptionCount: 22,
  ),
  features: TerminalDiagnosticsFeaturesSnapshot(
    secureInput: TerminalDiagnosticsFeatureState.disabled,
    quickWindowShortcut: TerminalDiagnosticsFeatureState.enabled,
    notifications: TerminalDiagnosticsFeatureState.denied,
    appIntents: TerminalDiagnosticsFeatureState.enabled,
    appleScript: TerminalDiagnosticsFeatureState.enabled,
    osc52: TerminalDiagnosticsFeatureState.disabled,
    pendingOsc52Requests: 0,
    pendingNotificationRequests: 0,
  ),
);

final class _FakeDiagnosticsFiles implements TerminalDiagnosticsFileOperations {
  final Map<String, Uint8List> destinations = <String, Uint8List>{};
  final Map<String, Uint8List> temporaryFiles = <String, Uint8List>{};
  int collisionCount = 0;
  int flushEquivalentWriteCount = 0;
  bool failReplace = false;

  @override
  Future<void> writeExclusive(String path, Uint8List bytes) async {
    if (collisionCount > 0) {
      collisionCount--;
      throw FileSystemException(
        'already exists',
        path,
        const OSError('exists', 17),
      );
    }
    if (temporaryFiles.containsKey(path)) {
      throw FileSystemException(
        'already exists',
        path,
        const OSError('exists', 17),
      );
    }
    temporaryFiles[path] = Uint8List.fromList(bytes);
    flushEquivalentWriteCount++;
  }

  @override
  Future<void> replace(String sourcePath, String destinationPath) async {
    if (failReplace) throw FileSystemException('replace failed', sourcePath);
    destinations[destinationPath] = temporaryFiles.remove(sourcePath)!;
  }

  @override
  Future<void> remove(String path) async {
    temporaryFiles.remove(path);
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}

T _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on Object catch (error) {
    if (error is T) return error;
    throw StateError('test failed: $message threw ${error.runtimeType}');
  }
  throw StateError('test failed: $message did not throw $T');
}
