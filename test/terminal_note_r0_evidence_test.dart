import 'dart:convert';
import 'dart:io';

import '../tool/terminal_note_r0_evidence.dart';

void main() => runTerminalNoteR0EvidenceTests();

void runTerminalNoteR0EvidenceTests() {
  final TerminalNoteR0EvidenceSources sources =
      loadTerminalNoteR0EvidenceSources(Directory.current.absolute);
  _testPassingEvidenceAndDeterminism(sources);
  _testStrictInputInventory(sources);
  _testHardGateFailures(sources);
  _testStaticSourceAudit(sources);
  _testCheckedSchemaRejections(sources);
  _testCheckedEvidence(sources);
}

void _testPassingEvidenceAndDeterminism(TerminalNoteR0EvidenceSources sources) {
  final TerminalNoteR0EvidenceResult first = _build(sources: sources);
  final TerminalNoteR0EvidenceResult second = _build(sources: sources);
  final String encoded = first.encode();
  final Map<String, Object?> document =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> integrity =
      document['input_integrity']! as Map<String, Object?>;
  final Map<String, Object?> sourceIntegrity =
      document['source_integrity']! as Map<String, Object?>;
  final Map<String, Object?> audit =
      document['static_audit']! as Map<String, Object?>;
  final Map<String, Object?> metrics =
      document['metrics']! as Map<String, Object?>;
  final Map<String, Object?> combined =
      metrics['combined_first_visible']! as Map<String, Object?>;
  _expect(
    encoded == second.encode() &&
        first.machineLine() == second.machineLine() &&
        document['format'] == terminalNoteR0EvidenceFormat &&
        document['version'] == 1 &&
        document['status'] == 'pass' &&
        integrity.length == 4 &&
        integrity.values.every(_isSha256) &&
        sourceIntegrity.length == 6 &&
        sourceIntegrity.values.every(_isSha256) &&
        audit['periodic_timer_matches'] == 0 &&
        audit['display_link_matches'] == 0 &&
        audit['one_shot_timer_matches'] == 1 &&
        audit['request_timeout_timer_matches'] == 1 &&
        combined['p95_us'] == 16200 &&
        combined['budget_us'] == 100000 &&
        encoded.endsWith('\n') &&
        !encoded.contains('/Users/') &&
        !encoded.contains('lib/src/') &&
        !encoded.contains('tool/') &&
        !encoded.contains('PRIVATE-NOTE-BODY') &&
        !encoded.contains('0123456789abcdef0123456789abcdef') &&
        !encoded.contains('"raw_samples":'),
    'passing evidence is deterministic, bounded, content-free, and complete',
  );
}

void _testStrictInputInventory(TerminalNoteR0EvidenceSources sources) {
  final List<String> dartLines = _dartLog
      .substring(0, _dartLog.length - 1)
      .split('\n');
  _expectThrows(
    () => _build(sources: sources, dartLog: '$_dartLog\n'),
    'extra blank Dart line',
  );
  _expectThrows(
    () =>
        _build(sources: sources, dartLog: '${dartLines.take(4).join('\n')}\n'),
    'missing Dart line',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      dartLog:
          '${dartLines[1]}\n${dartLines[0]}\n${dartLines.skip(2).join('\n')}\n',
    ),
    'reordered Dart lines',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      dartLog: _dartLog.replaceFirst('panes=64', 'pane_count=64'),
    ),
    'unknown Dart key',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      nativeLog: _nativeLog.replaceFirst(
        ' owners=0 content_free=true',
        ' secret=PRIVATE-NOTE-BODY owners=0 content_free=true',
      ),
    ),
    'content-bearing unknown native key',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      disabledLog: _disabledLog.substring(0, _disabledLog.length - 1),
    ),
    'missing final newline',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      storeLog: _storeLog.replaceFirst('\n', '\r\n'),
    ),
    'carriage return',
  );
}

void _testHardGateFailures(TerminalNoteR0EvidenceSources sources) {
  _expectThrows(
    () => _build(
      sources: sources,
      dartLog: _dartLog.replaceFirst(
        'rss_budget_bytes=16777216',
        'rss_budget_bytes=16777217',
      ),
    ),
    'forged idle threshold',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      nativeLog: _nativeLog.replaceFirst(
        'hardware=MacBookPro17,1',
        'hardware=MacBookPro18,1',
      ),
    ),
    'authority environment mismatch',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      dartLog: _dartLog.replaceFirst('p95_us=4200', 'p95_us=90000'),
      nativeLog: _nativeLog.replaceFirst(
        'first_visible_p95_us=12000',
        'first_visible_p95_us=11000',
      ),
    ),
    'combined first-visible over 100 ms',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      disabledLog: _disabledLog.replaceFirst(
        'median_ratio=1.010000',
        'median_ratio=1.050001',
      ),
    ),
    'disabled relative overhead over five percent',
  );
  _expectThrows(
    () => _build(
      sources: sources,
      storeLog: _storeLog.replaceFirst(
        'commit_p95_us=50000',
        'commit_p95_us=250001',
      ),
    ),
    'durable commit over 250 ms',
  );
}

void _testStaticSourceAudit(TerminalNoteR0EvidenceSources sources) {
  final Map<String, String> periodic = Map<String, String>.of(
    sources.auditedNoteSources,
  );
  periodic['lib/src/terminal_note_synthetic.dart'] =
      'void start() { Timer.periodic(Duration.zero, (_) {}); }\n';
  _expectThrows(
    () => _build(
      sources: TerminalNoteR0EvidenceSources(
        provenanceSources: sources.provenanceSources,
        auditedNoteSources: periodic,
      ),
    ),
    'periodic Note timer',
  );

  final Map<String, String> displayLink = Map<String, String>.of(
    sources.auditedNoteSources,
  );
  displayLink['packages/dart_terminal_notes_macos/native/Synthetic.m'] =
      'CVDisplayLinkRef link;\n';
  _expectThrows(
    () => _build(
      sources: TerminalNoteR0EvidenceSources(
        provenanceSources: sources.provenanceSources,
        auditedNoteSources: displayLink,
      ),
    ),
    'Note display-link owner',
  );

  final Map<String, String> missingTimeout = Map<String, String>.of(
    sources.auditedNoteSources,
  );
  missingTimeout['lib/src/terminal_note_store_isolate.dart'] =
      missingTimeout['lib/src/terminal_note_store_isolate.dart']!.replaceFirst(
        'Timer(timeout,',
        'Future<void>.delayed(timeout,',
      );
  _expectThrows(
    () => _build(
      sources: TerminalNoteR0EvidenceSources(
        provenanceSources: sources.provenanceSources,
        auditedNoteSources: missingTimeout,
      ),
    ),
    'missing allowlisted request timeout',
  );
}

void _testCheckedSchemaRejections(TerminalNoteR0EvidenceSources sources) {
  Map<String, Object?> fresh() =>
      jsonDecode(_build(sources: sources).encode()) as Map<String, Object?>;
  String encode(Map<String, Object?> value) =>
      '${const JsonEncoder.withIndent('  ').convert(value)}\n';

  final Map<String, Object?> extraKey = fresh();
  extraKey['note_body'] = 'PRIVATE-NOTE-BODY';
  _expectThrows(
    () => validateTerminalNoteR0EvidenceSource(
      encode(extraKey),
      sources: sources,
    ),
    'unknown content-bearing evidence key',
  );

  final Map<String, Object?> forgedSource = fresh();
  (forgedSource['source_integrity']!
      as Map<String, Object?>)['evidence_builder_sha256'] = List<String>.filled(
    64,
    '0',
    growable: false,
  ).join();
  _expectThrows(
    () => validateTerminalNoteR0EvidenceSource(
      encode(forgedSource),
      sources: sources,
    ),
    'forged source digest',
  );

  final Map<String, Object?> rawSamples = fresh();
  final Map<String, Object?> rawMetrics =
      rawSamples['metrics']! as Map<String, Object?>;
  (rawMetrics['native_apply']! as Map<String, Object?>)['raw_samples'] = <int>[
    1,
  ];
  _expectThrows(
    () => validateTerminalNoteR0EvidenceSource(
      encode(rawSamples),
      sources: sources,
    ),
    'raw samples in checked evidence',
  );

  final Map<String, Object?> forgedMetric = fresh();
  final Map<String, Object?> forgedMetrics =
      forgedMetric['metrics']! as Map<String, Object?>;
  (forgedMetrics['combined_first_visible']! as Map<String, Object?>)['p95_us'] =
      100001;
  _expectThrows(
    () => validateTerminalNoteR0EvidenceSource(
      encode(forgedMetric),
      sources: sources,
    ),
    'forged checked metric',
  );

  _expectThrows(
    () => validateTerminalNoteR0EvidenceSource(
      '${jsonEncode(fresh())}\n',
      sources: sources,
    ),
    'noncanonical checked JSON',
  );
}

void _testCheckedEvidence(TerminalNoteR0EvidenceSources sources) {
  final File evidence = File(terminalNoteR0EvidencePath);
  _expect(evidence.existsSync(), 'checked R0 budget evidence exists');
  final String source = evidence.readAsStringSync();
  final TerminalNoteR0EvidenceResult result =
      validateTerminalNoteR0EvidenceSource(source, sources: sources);
  final Map<String, Object?> gates =
      result.document['gates']! as Map<String, Object?>;
  _expect(
    utf8.encode(source).length <= 64 * 1024 &&
        gates.values.every((Object? value) => value == true) &&
        result.machineLine().startsWith('TERMINAL_NOTE_R0_EVIDENCE_PASS ') &&
        !source.contains('/Users/') &&
        !source.contains('PRIVATE-NOTE-BODY') &&
        !source.contains('0123456789abcdef0123456789abcdef') &&
        !source.contains('"raw_samples":'),
    'checked evidence is current, passing, bounded, and content-free',
  );
}

TerminalNoteR0EvidenceResult _build({
  required TerminalNoteR0EvidenceSources sources,
  String dartLog = _dartLog,
  String nativeLog = _nativeLog,
  String disabledLog = _disabledLog,
  String storeLog = _storeLog,
}) => buildTerminalNoteR0Evidence(
  dartLog: dartLog,
  nativeLog: nativeLog,
  disabledLog: disabledLog,
  storeLog: storeLog,
  sources: sources,
);

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected failure: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('R0 evidence test failed: $message');
}

const String _dartLog =
    'TERMINAL_NOTE_R0_IDLE_PASS panes=64 surfaces=64 worker=1 '
    'rss_delta_bytes=3000000 rss_budget_bytes=16777216 idle_window_ms=250 '
    'projection_delta=0 notification_delta=0 layout_delta=0 frame_delta=0 '
    'store_changes=0 owners=0\n'
    'TERMINAL_NOTE_R0_MODEL_PASS samples=64 p95_us=4 max_us=11 '
    'p95_budget_us=1000 max_budget_us=4000 store_commit_delta=0 '
    'body_encode=0 fsync=0 owners=0\n'
    'TERMINAL_NOTE_R0_PROJECTION_PASS samples=21 notes=128 cards=64 '
    'body_bytes=262144 p95_us=4200 budget_us=100000 '
    'store_commit_delta=0 owners=0\n'
    'TERMINAL_NOTE_R0_HARD_CAP_PASS notes=2048 contexts=4096 triggers=2048 '
    'deliveries=2048 body_bytes=8388608 file_bytes=9698603 '
    'steady_delta_bytes=44000000 steady_budget_bytes=67108864 '
    'peak_delta_bytes=90000000 peak_budget_bytes=100663296 owners=0\n'
    'TERMINAL_NOTE_R0_DART_BUDGET_PASS version=1 build=release-aot '
    'abi=macos_arm64 hardware=MacBookPro17,1 memory_bytes=17179869184 '
    'dart=3.13.2 phases=4 content_free=true\n';

const String _nativeLog =
    'TERMINAL_NOTE_R0_NATIVE_BUDGET_PASS version=1 abi=macos_arm64 '
    'hardware=MacBookPro17,1 memory_bytes=17179869184 warmups=5 samples=21 '
    'cards=64 materialized=32 body_bytes=262144 apply_p95_us=4500 '
    'apply_budget_us=8000 first_visible_p95_us=12000 '
    'first_visible_budget_us=100000 stalls=0 stall_threshold_us=33340 '
    'owners=0 content_free=true\n';

const String _disabledLog =
    'TERMINAL_NOTE_DISABLED_INPUT_PASS rounds=21 events_per_route=1050000 '
    'factory_calls=0 baseline_p95_ns=500 disabled_p95_ns=505 '
    'median_ratio=1.010000 maximum_ratio=1.05 integrity=true\n';

const String _storeLog =
    'TERMINAL_NOTE_STORE_ACCEPTANCE_PASS runs=20 commit_p95_us=50000 '
    'primitive_p95_us=20000 contention=true recovery=true privacy=true\n';
