import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';

import 'terminal_differential_sha256.dart';

const String terminalNoteR0EvidenceFormat =
    'dart-terminal-note-r0-budget-evidence';
const String terminalNoteR0EvidencePath =
    'benchmark/evidence/terminal-note-r0-budget-macos-arm64-m1.json';

const int _maximumLogBytes = 64 * 1024;
const int _maximumSourceBytes = 4 * 1024 * 1024;
const int _maximumAuditedSourceBytes = 16 * 1024 * 1024;

const Map<String, Object?> _authority = <String, Object?>{
  'os': 'macos',
  'abi': 'macos_arm64',
  'hardware_model': 'MacBookPro17,1',
  'memory_bytes': 16 * 1024 * 1024 * 1024,
  'dart_sdk': '3.13.2',
  'build_mode': 'release-aot',
};

const Map<String, Object?> _measurementPolicy = <String, Object?>{
  'version': 1,
  'dart_phase_processes': 4,
  'native_actual_appkit': true,
  'raw_samples_retained': false,
  'content_retained': false,
  'identities_retained': false,
  'timestamps_retained': false,
  'paths_retained': false,
};

const Map<String, Object?> _passingGates = <String, Object?>{
  'input_contracts': true,
  'authority_environment': true,
  'idle': true,
  'model_transition': true,
  'dart_projection': true,
  'native_apply': true,
  'combined_first_visible': true,
  'hard_cap': true,
  'disabled_input': true,
  'durable_store': true,
  'structural_bounds': true,
  'static_source_audit': true,
  'content_free': true,
  'passed': true,
};

const Set<String> _provenanceSourceNames = <String>{
  'dart_budget_benchmark',
  'native_budget_benchmark',
  'disabled_input_benchmark',
  'store_acceptance',
  'evidence_builder',
};

final class TerminalNoteR0EvidenceSources {
  TerminalNoteR0EvidenceSources({
    required Map<String, List<int>> provenanceSources,
    required Map<String, String> auditedNoteSources,
  }) : provenanceSources = Map<String, List<int>>.unmodifiable(
         provenanceSources.map(
           (String key, List<int> value) =>
               MapEntry<String, List<int>>(key, List<int>.unmodifiable(value)),
         ),
       ),
       auditedNoteSources = Map<String, String>.unmodifiable(
         auditedNoteSources,
       );

  final Map<String, List<int>> provenanceSources;
  final Map<String, String> auditedNoteSources;
}

final class TerminalNoteR0EvidenceResult {
  const TerminalNoteR0EvidenceResult(this.document);

  final Map<String, Object?> document;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(document)}\n';

  String machineLine() {
    final Map<String, Object?> combined =
        (document['metrics']!
                as Map<String, Object?>)['combined_first_visible']!
            as Map<String, Object?>;
    final Map<String, Object?> audit =
        document['static_audit']! as Map<String, Object?>;
    return 'TERMINAL_NOTE_R0_EVIDENCE_PASS version=1 inputs=4 sources=6 '
        'combined_first_visible_us=${combined['p95_us']} '
        'combined_budget_us=${combined['budget_us']} '
        'periodic_timers=${audit['periodic_timer_matches']} '
        'display_links=${audit['display_link_matches']} '
        'request_timeout_timers=${audit['request_timeout_timer_matches']} '
        'content_free=true';
  }
}

TerminalNoteR0EvidenceResult buildTerminalNoteR0Evidence({
  required String dartLog,
  required String nativeLog,
  required String disabledLog,
  required String storeLog,
  required TerminalNoteR0EvidenceSources sources,
}) {
  final List<String> dartLines = _strictLines(dartLog, 5, 'Dart budget');
  final Map<String, int> idle = _decodeIdle(dartLines[0]);
  final Map<String, int> model = _decodeModel(dartLines[1]);
  final Map<String, int> projection = _decodeProjection(dartLines[2]);
  final Map<String, int> hardCap = _decodeHardCap(dartLines[3]);
  _decodeDartAuthority(dartLines[4]);
  final Map<String, int> native = _decodeNative(
    _strictLines(nativeLog, 1, 'native budget').single,
  );
  final Map<String, int> disabled = _decodeDisabled(
    _strictLines(disabledLog, 1, 'disabled input').single,
  );
  final Map<String, int> store = _decodeStore(
    _strictLines(storeLog, 1, 'store acceptance').single,
  );
  final Map<String, Object?> structural = _structuralBounds();
  final Map<String, Object?> staticAudit = _staticAudit(sources);
  final Map<String, Object?> sourceIntegrity = _sourceIntegrity(sources);
  final int combinedP95 =
      projection['p95_us']! + native['first_visible_p95_us']!;
  if (combinedP95 > 100000) {
    throw const FormatException('combined first-visible budget failed');
  }

  final Map<String, Object?> document = <String, Object?>{
    'format': terminalNoteR0EvidenceFormat,
    'version': 1,
    'status': 'pass',
    'authority': _authority,
    'input_integrity': <String, Object?>{
      'dart_budget_sha256': _shaText(dartLog),
      'native_budget_sha256': _shaText(nativeLog),
      'disabled_input_sha256': _shaText(disabledLog),
      'store_acceptance_sha256': _shaText(storeLog),
    },
    'source_integrity': sourceIntegrity,
    'measurement_policy': _measurementPolicy,
    'metrics': <String, Object?>{
      'idle': idle,
      'model_transition': model,
      'dart_projection': projection,
      'native_apply': native,
      'combined_first_visible': <String, Object?>{
        'p95_us': combinedP95,
        'budget_us': 100000,
      },
      'hard_cap': hardCap,
      'disabled_input': disabled,
      'durable_store': store,
    },
    'structural_bounds': structural,
    'static_audit': staticAudit,
    'gates': _passingGates,
  };
  _validateDocument(document, sources);
  return TerminalNoteR0EvidenceResult(document);
}

TerminalNoteR0EvidenceResult validateTerminalNoteR0EvidenceSource(
  String source, {
  required TerminalNoteR0EvidenceSources sources,
}) {
  if (utf8.encode(source).length > _maximumLogBytes ||
      !source.endsWith('\n') ||
      source.endsWith('\n\n') ||
      source.contains('\r')) {
    throw const FormatException('checked evidence framing is invalid');
  }
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('checked evidence is not an object');
  }
  _validateDocument(decoded, sources);
  final String canonical =
      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  if (canonical != source) {
    throw const FormatException('checked evidence is not deterministic JSON');
  }
  return TerminalNoteR0EvidenceResult(decoded);
}

TerminalNoteR0EvidenceSources loadTerminalNoteR0EvidenceSources(
  Directory sourceRoot,
) {
  if (!sourceRoot.isAbsolute || !sourceRoot.existsSync()) {
    throw const FormatException('source root must be an absolute directory');
  }
  const Map<String, String> fixed = <String, String>{
    'dart_budget_benchmark': 'tool/terminal_note_r0_budget_benchmark.dart',
    'native_budget_benchmark':
        'packages/dart_terminal_notes_macos/native/test/'
        'TerminalNotesBudgetBenchmark.mm',
    'disabled_input_benchmark':
        'tool/terminal_note_disabled_input_benchmark.dart',
    'store_acceptance': 'test/terminal_note_store_acceptance_test.dart',
    'evidence_builder': 'tool/terminal_note_r0_evidence.dart',
  };
  final Map<String, List<int>> provenance = <String, List<int>>{
    for (final MapEntry<String, String> entry in fixed.entries)
      entry.key: _readBoundedFile(sourceRoot, entry.value),
  };
  final Map<String, String> audited = <String, String>{};
  final List<FileSystemEntity> candidates = <FileSystemEntity>[
    ...Directory.fromUri(sourceRoot.uri.resolve('lib/src/')).listSync(),
    ...Directory.fromUri(
      sourceRoot.uri.resolve('packages/dart_terminal_notes_macos/lib/src/'),
    ).listSync(recursive: true, followLinks: false),
    ...Directory.fromUri(
      sourceRoot.uri.resolve('packages/dart_terminal_notes_macos/native/'),
    ).listSync(recursive: true, followLinks: false),
  ];
  final List<File> files =
      candidates
          .whereType<File>()
          .where((File file) {
            final String relative = _relativePath(sourceRoot, file);
            if (relative.startsWith('lib/src/')) {
              final String leaf = file.uri.pathSegments.last;
              return leaf.startsWith('terminal_note_') &&
                  leaf.endsWith('.dart');
            }
            if (relative.contains('/lib/src/'))
              return relative.endsWith('.dart');
            return relative.endsWith('.h') ||
                relative.endsWith('.m') ||
                relative.endsWith('.mm');
          })
          .toList(growable: false)
        ..sort((File left, File right) {
          return _relativePath(
            sourceRoot,
            left,
          ).compareTo(_relativePath(sourceRoot, right));
        });
  var totalBytes = 0;
  for (final File file in files) {
    final String relative = _relativePath(sourceRoot, file);
    final List<int> bytes = _readBoundedFile(sourceRoot, relative);
    totalBytes += bytes.length;
    if (totalBytes > _maximumAuditedSourceBytes) {
      throw const FormatException('audited Note source inventory is too large');
    }
    audited[relative] = utf8.decode(bytes, allowMalformed: false);
  }
  if (audited.isEmpty ||
      !audited.containsKey('lib/src/terminal_note_store_isolate.dart')) {
    throw const FormatException('audited Note source inventory is incomplete');
  }
  return TerminalNoteR0EvidenceSources(
    provenanceSources: provenance,
    auditedNoteSources: audited,
  );
}

List<String> _strictLines(String source, int count, String name) {
  final int byteLength = utf8.encode(source).length;
  if (byteLength == 0 ||
      byteLength > _maximumLogBytes ||
      source.contains('\r') ||
      !source.endsWith('\n') ||
      source.endsWith('\n\n')) {
    throw FormatException('$name log framing is invalid');
  }
  final List<String> lines = source.substring(0, source.length - 1).split('\n');
  if (lines.length != count || lines.any((String line) => line.isEmpty)) {
    throw FormatException('$name log inventory is invalid');
  }
  return lines;
}

Map<String, int> _decodeIdle(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_R0_IDLE_PASS panes=([0-9]+) surfaces=([0-9]+) '
      r'worker=([0-9]+) rss_delta_bytes=([0-9]+) '
      r'rss_budget_bytes=([0-9]+) idle_window_ms=([0-9]+) '
      r'projection_delta=([0-9]+) notification_delta=([0-9]+) '
      r'layout_delta=([0-9]+) frame_delta=([0-9]+) '
      r'store_changes=([0-9]+) owners=([0-9]+)$',
    ),
    const <String>[
      'panes',
      'surfaces',
      'worker',
      'rss_delta_bytes',
      'rss_budget_bytes',
      'idle_window_ms',
      'projection_delta',
      'notification_delta',
      'layout_delta',
      'frame_delta',
      'store_changes',
      'owners',
    ],
    'idle',
  );
  if (value['panes'] != 64 ||
      value['surfaces'] != 64 ||
      value['worker'] != 1 ||
      value['rss_budget_bytes'] != 16 * 1024 * 1024 ||
      value['rss_delta_bytes']! > value['rss_budget_bytes']! ||
      value['idle_window_ms'] != 250 ||
      value['projection_delta'] != 0 ||
      value['notification_delta'] != 0 ||
      value['layout_delta'] != 0 ||
      value['frame_delta'] != 0 ||
      value['store_changes'] != 0 ||
      value['owners'] != 0) {
    throw const FormatException('idle gate failed');
  }
  return value;
}

Map<String, int> _decodeModel(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_R0_MODEL_PASS samples=([0-9]+) p95_us=([0-9]+) '
      r'max_us=([0-9]+) p95_budget_us=([0-9]+) '
      r'max_budget_us=([0-9]+) store_commit_delta=([0-9]+) '
      r'body_encode=([0-9]+) fsync=([0-9]+) owners=([0-9]+)$',
    ),
    const <String>[
      'samples',
      'p95_us',
      'max_us',
      'p95_budget_us',
      'max_budget_us',
      'store_commit_delta',
      'body_encode',
      'fsync',
      'owners',
    ],
    'model',
  );
  if (value['samples'] != 64 ||
      value['p95_budget_us'] != 1000 ||
      value['max_budget_us'] != 4000 ||
      value['p95_us']! > value['p95_budget_us']! ||
      value['max_us']! > value['max_budget_us']! ||
      value['p95_us']! > value['max_us']! ||
      value['store_commit_delta'] != 0 ||
      value['body_encode'] != 0 ||
      value['fsync'] != 0 ||
      value['owners'] != 0) {
    throw const FormatException('model transition gate failed');
  }
  return value;
}

Map<String, int> _decodeProjection(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_R0_PROJECTION_PASS samples=([0-9]+) '
      r'notes=([0-9]+) cards=([0-9]+) body_bytes=([0-9]+) '
      r'p95_us=([0-9]+) budget_us=([0-9]+) '
      r'store_commit_delta=([0-9]+) owners=([0-9]+)$',
    ),
    const <String>[
      'samples',
      'notes',
      'cards',
      'body_bytes',
      'p95_us',
      'budget_us',
      'store_commit_delta',
      'owners',
    ],
    'projection',
  );
  if (value['samples'] != 21 ||
      value['notes'] != 128 ||
      value['cards'] != 64 ||
      value['body_bytes'] != 256 * 1024 ||
      value['budget_us'] != 100000 ||
      value['p95_us']! > value['budget_us']! ||
      value['store_commit_delta'] != 0 ||
      value['owners'] != 0) {
    throw const FormatException('Dart projection gate failed');
  }
  return value;
}

Map<String, int> _decodeHardCap(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_R0_HARD_CAP_PASS notes=([0-9]+) '
      r'contexts=([0-9]+) triggers=([0-9]+) deliveries=([0-9]+) '
      r'body_bytes=([0-9]+) file_bytes=([0-9]+) '
      r'steady_delta_bytes=([0-9]+) steady_budget_bytes=([0-9]+) '
      r'peak_delta_bytes=([0-9]+) peak_budget_bytes=([0-9]+) '
      r'owners=([0-9]+)$',
    ),
    const <String>[
      'notes',
      'contexts',
      'triggers',
      'deliveries',
      'body_bytes',
      'file_bytes',
      'steady_delta_bytes',
      'steady_budget_bytes',
      'peak_delta_bytes',
      'peak_budget_bytes',
      'owners',
    ],
    'hard cap',
  );
  if (value['notes'] != 2048 ||
      value['contexts'] != 4096 ||
      value['triggers'] != 2048 ||
      value['deliveries'] != 2048 ||
      value['body_bytes'] != 8 * 1024 * 1024 ||
      value['file_bytes'] == 0 ||
      value['file_bytes']! > 16 * 1024 * 1024 ||
      value['steady_budget_bytes'] != 64 * 1024 * 1024 ||
      value['steady_delta_bytes']! > value['steady_budget_bytes']! ||
      value['peak_budget_bytes'] != 96 * 1024 * 1024 ||
      value['peak_delta_bytes']! > value['peak_budget_bytes']! ||
      value['peak_delta_bytes']! < value['steady_delta_bytes']! ||
      value['owners'] != 0) {
    throw const FormatException('hard-cap gate failed');
  }
  return value;
}

void _decodeDartAuthority(String line) {
  final RegExpMatch? match = RegExp(
    r'^TERMINAL_NOTE_R0_DART_BUDGET_PASS version=1 build=release-aot '
    r'abi=macos_arm64 hardware=MacBookPro17,1 memory_bytes=17179869184 '
    r'dart=3\.13\.2 phases=4 content_free=true$',
  ).firstMatch(line);
  if (match == null) {
    throw const FormatException('Dart authority line is invalid');
  }
}

Map<String, int> _decodeNative(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_R0_NATIVE_BUDGET_PASS version=1 abi=macos_arm64 '
      r'hardware=MacBookPro17,1 memory_bytes=17179869184 '
      r'warmups=([0-9]+) samples=([0-9]+) cards=([0-9]+) '
      r'materialized=([0-9]+) body_bytes=([0-9]+) '
      r'apply_p95_us=([0-9]+) apply_budget_us=([0-9]+) '
      r'first_visible_p95_us=([0-9]+) first_visible_budget_us=([0-9]+) '
      r'stalls=([0-9]+) stall_threshold_us=([0-9]+) '
      r'owners=([0-9]+) content_free=true$',
    ),
    const <String>[
      'warmups',
      'samples',
      'cards',
      'materialized',
      'body_bytes',
      'apply_p95_us',
      'apply_budget_us',
      'first_visible_p95_us',
      'first_visible_budget_us',
      'stalls',
      'stall_threshold_us',
      'owners',
    ],
    'native',
  );
  if (value['warmups'] != 5 ||
      value['samples'] != 21 ||
      value['cards'] != 64 ||
      value['materialized'] != 32 ||
      value['body_bytes'] != 256 * 1024 ||
      value['apply_budget_us'] != 8000 ||
      value['apply_p95_us']! > value['apply_budget_us']! ||
      value['first_visible_budget_us'] != 100000 ||
      value['first_visible_p95_us']! > value['first_visible_budget_us']! ||
      value['first_visible_p95_us']! < value['apply_p95_us']! ||
      value['stalls'] != 0 ||
      value['stall_threshold_us'] != 33340 ||
      value['owners'] != 0) {
    throw const FormatException('native apply gate failed');
  }
  return value;
}

Map<String, int> _decodeDisabled(String line) {
  final RegExpMatch? match = RegExp(
    r'^TERMINAL_NOTE_DISABLED_INPUT_PASS rounds=([0-9]+) '
    r'events_per_route=([0-9]+) factory_calls=([0-9]+) '
    r'baseline_p95_ns=([0-9]+) disabled_p95_ns=([0-9]+) '
    r'median_ratio=([0-9]+)\.([0-9]{6}) maximum_ratio=1\.05 '
    r'integrity=true$',
  ).firstMatch(line);
  if (match == null) {
    throw const FormatException('disabled input line is invalid');
  }
  final List<String> names = <String>[
    'rounds',
    'events_per_route',
    'factory_calls',
    'baseline_p95_ns',
    'disabled_p95_ns',
  ];
  final Map<String, int> value = <String, int>{
    for (var index = 0; index < names.length; index++)
      names[index]: _parseInteger(match.group(index + 1)!, 'disabled input'),
  };
  final int ratioWhole = _parseInteger(match.group(6)!, 'disabled ratio');
  final int ratioFraction = _parseInteger(match.group(7)!, 'disabled ratio');
  value['median_ratio_ppm'] = ratioWhole * 1000000 + ratioFraction;
  value['maximum_ratio_ppm'] = 1050000;
  if (value['rounds'] != 21 ||
      value['events_per_route'] != 1050000 ||
      value['factory_calls'] != 0 ||
      value['baseline_p95_ns']! >= 2000000 ||
      value['disabled_p95_ns']! >= 2000000 ||
      value['median_ratio_ppm']! <= 0 ||
      value['median_ratio_ppm']! > value['maximum_ratio_ppm']!) {
    throw const FormatException('disabled input gate failed');
  }
  return value;
}

Map<String, int> _decodeStore(String line) {
  final Map<String, int> value = _integerMatch(
    line,
    RegExp(
      r'^TERMINAL_NOTE_STORE_ACCEPTANCE_PASS runs=([0-9]+) '
      r'commit_p95_us=([0-9]+) primitive_p95_us=([0-9]+) '
      r'contention=true recovery=true privacy=true$',
    ),
    const <String>['runs', 'commit_p95_us', 'primitive_p95_us'],
    'store acceptance',
  );
  value['commit_budget_us'] = 250000;
  value['primitive_budget_us'] = 1500000;
  if (value['runs'] != 20 ||
      value['commit_p95_us']! > value['commit_budget_us']! ||
      value['primitive_p95_us']! > value['primitive_budget_us']!) {
    throw const FormatException('durable store gate failed');
  }
  return value;
}

Map<String, int> _integerMatch(
  String line,
  RegExp pattern,
  List<String> names,
  String context,
) {
  final RegExpMatch? match = pattern.firstMatch(line);
  if (match == null || match.groupCount != names.length) {
    throw FormatException('$context line is invalid');
  }
  return <String, int>{
    for (var index = 0; index < names.length; index++)
      names[index]: _parseInteger(match.group(index + 1)!, context),
  };
}

int _parseInteger(String source, String context) {
  final int? value = int.tryParse(source);
  if (value == null || value < 0) {
    throw FormatException('$context integer is invalid');
  }
  return value;
}

Map<String, Object?> _structuralBounds() {
  final Map<String, Object?> value = <String, Object?>{
    'model': <String, Object?>{
      'notes': TerminalNoteLimits.maximumNotes,
      'notes_per_attached_context':
          TerminalNoteLimits.maximumNotesPerAttachedContext,
      'contexts': TerminalNoteLimits.maximumContexts,
      'triggers': TerminalNoteLimits.maximumTriggers,
      'deliveries': TerminalNoteLimits.maximumDeliveries,
      'body_utf8_bytes': TerminalNoteLimits.maximumBodyUtf8Bytes,
      'body_lines': TerminalNoteLimits.maximumBodyLines,
      'aggregate_body_utf8_bytes':
          TerminalNoteLimits.maximumAggregateBodyUtf8Bytes,
      'prompt_events_per_batch': TerminalNoteLimits.maximumPromptEventsPerBatch,
      'coalesced_focus_edges': TerminalNoteLimits.maximumCoalescedFocusEdges,
    },
    'authority': <String, Object?>{
      'pending_intents': TerminalNoteAuthorityLimits.maximumPendingIntents,
      'pending_body_bytes': TerminalNoteAuthorityLimits.maximumPendingBodyBytes,
      'intent_sources': TerminalNoteAuthorityLimits.maximumIntentSources,
      'live_contexts': TerminalNoteAuthorityLimits.maximumLiveContexts,
      'live_sessions': TerminalNoteAuthorityLimits.maximumLiveSessions,
      'prompt_events_per_session':
          TerminalNoteAuthorityLimits.maximumPromptEventsPerSession,
    },
    'store_worker': <String, Object?>{
      'pending_intents': TerminalNoteStoreWorkerLimits.maximumPendingIntents,
      'pending_body_bytes':
          TerminalNoteStoreWorkerLimits.maximumPendingBodyBytes,
    },
    'store_codec': <String, Object?>{
      'file_bytes': TerminalNoteStoreCodecLimits.maximumFileBytes,
      'restoration_pane_contexts':
          TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts,
      'deletion_journal_entries':
          TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries,
      'json_depth': TerminalNoteStoreCodecLimits.maximumJsonDepth,
      'json_nodes': TerminalNoteStoreCodecLimits.maximumJsonNodes,
    },
    'product_projection': <String, Object?>{
      'cards': TerminalNoteProjectionLimits.maximumExpandedCards,
      'body_bytes': TerminalNoteProjectionLimits.maximumExpandedBodyUtf8Bytes,
    },
    'native_projection': <String, Object?>{
      'cards': TerminalNotesLimits.maximumCards,
      'materialized_cards': TerminalNotesLimits.maximumMaterializedCards,
      'card_body_bytes': TerminalNotesLimits.maximumCardBodyUtf8Bytes,
      'aggregate_body_bytes': TerminalNotesLimits.maximumAggregateBodyUtf8Bytes,
      'context_notes': TerminalNotesLimits.maximumContextNotes,
      'detached_notes': TerminalNotesLimits.maximumDetachedNotes,
    },
  };
  const Map<String, Object?> frozen = <String, Object?>{
    'model': <String, Object?>{
      'notes': 2048,
      'notes_per_attached_context': 128,
      'contexts': 4096,
      'triggers': 2048,
      'deliveries': 2048,
      'body_utf8_bytes': 4096,
      'body_lines': 64,
      'aggregate_body_utf8_bytes': 8388608,
      'prompt_events_per_batch': 32,
      'coalesced_focus_edges': 2,
    },
    'authority': <String, Object?>{
      'pending_intents': 32,
      'pending_body_bytes': 131072,
      'intent_sources': 64,
      'live_contexts': 64,
      'live_sessions': 64,
      'prompt_events_per_session': 32,
    },
    'store_worker': <String, Object?>{
      'pending_intents': 32,
      'pending_body_bytes': 131072,
    },
    'store_codec': <String, Object?>{
      'file_bytes': 16777216,
      'restoration_pane_contexts': 64,
      'deletion_journal_entries': 8192,
      'json_depth': 16,
      'json_nodes': 262144,
    },
    'product_projection': <String, Object?>{'cards': 64, 'body_bytes': 262144},
    'native_projection': <String, Object?>{
      'cards': 64,
      'materialized_cards': 32,
      'card_body_bytes': 4096,
      'aggregate_body_bytes': 262144,
      'context_notes': 128,
      'detached_notes': 2048,
    },
  };
  if (!_sameJson(value, frozen)) {
    throw const FormatException('structural Note bounds differ');
  }
  return value;
}

Map<String, Object?> _staticAudit(TerminalNoteR0EvidenceSources sources) {
  final Map<String, String> audited = sources.auditedNoteSources;
  if (audited.isEmpty) {
    throw const FormatException('Note source audit inventory is empty');
  }
  final int periodic = audited.values.fold<int>(
    0,
    (int count, String source) =>
        count +
        RegExp(r'\bTimer\s*\.\s*periodic\s*\(').allMatches(source).length,
  );
  final int displayLink = audited.values.fold<int>(
    0,
    (int count, String source) =>
        count +
        RegExp(
          r'(?:CVDisplayLink|CADisplayLink|displayLink)',
          caseSensitive: false,
        ).allMatches(source).length,
  );
  final int oneShot = audited.values.fold<int>(
    0,
    (int count, String source) =>
        count + RegExp(r'\bTimer\s*\(').allMatches(source).length,
  );
  final String? store = audited['lib/src/terminal_note_store_isolate.dart'];
  final int requestTimeout = store == null
      ? 0
      : RegExp(
          r'pending\.timer\s*=\s*Timer\s*\(timeout,\s*\(\)\s*\{'
          r'[\s\S]{0,256}?_terminate\(TerminalNoteStoreFailure\.timeout\)',
        ).allMatches(store).length;
  if (periodic != 0 ||
      displayLink != 0 ||
      oneShot != 1 ||
      requestTimeout != 1) {
    throw const FormatException('Note timer or display-link audit failed');
  }
  return <String, Object?>{
    'audited_source_files': audited.length,
    'periodic_timer_matches': periodic,
    'display_link_matches': displayLink,
    'one_shot_timer_matches': oneShot,
    'request_timeout_timer_matches': requestTimeout,
  };
}

Map<String, Object?> _sourceIntegrity(TerminalNoteR0EvidenceSources sources) {
  if (sources.provenanceSources.keys
          .toSet()
          .difference(_provenanceSourceNames)
          .isNotEmpty ||
      _provenanceSourceNames
          .difference(sources.provenanceSources.keys.toSet())
          .isNotEmpty) {
    throw const FormatException('provenance source inventory differs');
  }
  final BytesBuilder aggregate = BytesBuilder(copy: false);
  final List<String> paths = sources.auditedNoteSources.keys.toList()..sort();
  for (final String path in paths) {
    final List<int> pathBytes = utf8.encode(path);
    final List<int> sourceBytes = utf8.encode(
      sources.auditedNoteSources[path]!,
    );
    aggregate
      ..add(utf8.encode('${pathBytes.length}:'))
      ..add(pathBytes)
      ..addByte(0)
      ..add(utf8.encode('${sourceBytes.length}:'))
      ..add(sourceBytes)
      ..addByte(0);
  }
  return <String, Object?>{
    for (final String name in _provenanceSourceNames.toList()..sort())
      '${name}_sha256': terminalDifferentialSha256(
        sources.provenanceSources[name]!,
      ),
    'audited_note_sources_sha256': terminalDifferentialSha256(
      aggregate.takeBytes(),
    ),
  };
}

void _validateDocument(
  Map<String, Object?> document,
  TerminalNoteR0EvidenceSources sources,
) {
  _exactKeys(document, const <String>{
    'format',
    'version',
    'status',
    'authority',
    'input_integrity',
    'source_integrity',
    'measurement_policy',
    'metrics',
    'structural_bounds',
    'static_audit',
    'gates',
  }, 'evidence');
  if (document['format'] != terminalNoteR0EvidenceFormat ||
      document['version'] != 1 ||
      document['status'] != 'pass' ||
      !_sameJson(document['authority'], _authority) ||
      !_sameJson(document['measurement_policy'], _measurementPolicy) ||
      !_sameJson(document['structural_bounds'], _structuralBounds()) ||
      !_sameJson(document['static_audit'], _staticAudit(sources)) ||
      !_sameJson(document['source_integrity'], _sourceIntegrity(sources)) ||
      !_sameJson(document['gates'], _passingGates)) {
    throw const FormatException('evidence fixed contract differs');
  }
  final Map<String, Object?> inputs = _object(
    document['input_integrity'],
    'input integrity',
  );
  _exactKeys(inputs, const <String>{
    'dart_budget_sha256',
    'native_budget_sha256',
    'disabled_input_sha256',
    'store_acceptance_sha256',
  }, 'input integrity');
  if (!inputs.values.every(_isSha256)) {
    throw const FormatException('input integrity digest is invalid');
  }

  final Map<String, Object?> metrics = _object(document['metrics'], 'metrics');
  _exactKeys(metrics, const <String>{
    'idle',
    'model_transition',
    'dart_projection',
    'native_apply',
    'combined_first_visible',
    'hard_cap',
    'disabled_input',
    'durable_store',
  }, 'metrics');
  final Map<String, Object?> idle = _integerObject(
    metrics['idle'],
    const <String>{
      'panes',
      'surfaces',
      'worker',
      'rss_delta_bytes',
      'rss_budget_bytes',
      'idle_window_ms',
      'projection_delta',
      'notification_delta',
      'layout_delta',
      'frame_delta',
      'store_changes',
      'owners',
    },
    'idle',
  );
  final Map<String, Object?> model = _integerObject(
    metrics['model_transition'],
    const <String>{
      'samples',
      'p95_us',
      'max_us',
      'p95_budget_us',
      'max_budget_us',
      'store_commit_delta',
      'body_encode',
      'fsync',
      'owners',
    },
    'model transition',
  );
  final Map<String, Object?> projection = _integerObject(
    metrics['dart_projection'],
    const <String>{
      'samples',
      'notes',
      'cards',
      'body_bytes',
      'p95_us',
      'budget_us',
      'store_commit_delta',
      'owners',
    },
    'Dart projection',
  );
  final Map<String, Object?> native = _integerObject(
    metrics['native_apply'],
    const <String>{
      'warmups',
      'samples',
      'cards',
      'materialized',
      'body_bytes',
      'apply_p95_us',
      'apply_budget_us',
      'first_visible_p95_us',
      'first_visible_budget_us',
      'stalls',
      'stall_threshold_us',
      'owners',
    },
    'native apply',
  );
  final Map<String, Object?> combined = _integerObject(
    metrics['combined_first_visible'],
    const <String>{'p95_us', 'budget_us'},
    'combined first-visible',
  );
  final Map<String, Object?> hardCap = _integerObject(
    metrics['hard_cap'],
    const <String>{
      'notes',
      'contexts',
      'triggers',
      'deliveries',
      'body_bytes',
      'file_bytes',
      'steady_delta_bytes',
      'steady_budget_bytes',
      'peak_delta_bytes',
      'peak_budget_bytes',
      'owners',
    },
    'hard cap',
  );
  final Map<String, Object?> disabled = _integerObject(
    metrics['disabled_input'],
    const <String>{
      'rounds',
      'events_per_route',
      'factory_calls',
      'baseline_p95_ns',
      'disabled_p95_ns',
      'median_ratio_ppm',
      'maximum_ratio_ppm',
    },
    'disabled input',
  );
  final Map<String, Object?> store = _integerObject(
    metrics['durable_store'],
    const <String>{
      'runs',
      'commit_p95_us',
      'primitive_p95_us',
      'commit_budget_us',
      'primitive_budget_us',
    },
    'durable store',
  );
  if (idle['panes'] != 64 ||
      idle['surfaces'] != 64 ||
      idle['worker'] != 1 ||
      idle['rss_budget_bytes'] != 16777216 ||
      (idle['rss_delta_bytes']! as int) > 16777216 ||
      idle['idle_window_ms'] != 250 ||
      <String>[
        'projection_delta',
        'notification_delta',
        'layout_delta',
        'frame_delta',
        'store_changes',
        'owners',
      ].any((String key) => idle[key] != 0) ||
      model['samples'] != 64 ||
      model['p95_budget_us'] != 1000 ||
      model['max_budget_us'] != 4000 ||
      (model['p95_us']! as int) > 1000 ||
      (model['max_us']! as int) > 4000 ||
      (model['p95_us']! as int) > (model['max_us']! as int) ||
      <String>[
        'store_commit_delta',
        'body_encode',
        'fsync',
        'owners',
      ].any((String key) => model[key] != 0) ||
      projection['samples'] != 21 ||
      projection['notes'] != 128 ||
      projection['cards'] != 64 ||
      projection['body_bytes'] != 262144 ||
      projection['budget_us'] != 100000 ||
      (projection['p95_us']! as int) > 100000 ||
      projection['store_commit_delta'] != 0 ||
      projection['owners'] != 0 ||
      native['warmups'] != 5 ||
      native['samples'] != 21 ||
      native['cards'] != 64 ||
      native['materialized'] != 32 ||
      native['body_bytes'] != 262144 ||
      native['apply_budget_us'] != 8000 ||
      (native['apply_p95_us']! as int) > 8000 ||
      native['first_visible_budget_us'] != 100000 ||
      (native['first_visible_p95_us']! as int) > 100000 ||
      (native['first_visible_p95_us']! as int) <
          (native['apply_p95_us']! as int) ||
      native['stalls'] != 0 ||
      native['stall_threshold_us'] != 33340 ||
      native['owners'] != 0 ||
      combined['budget_us'] != 100000 ||
      combined['p95_us'] !=
          (projection['p95_us']! as int) +
              (native['first_visible_p95_us']! as int) ||
      (combined['p95_us']! as int) > 100000 ||
      hardCap['notes'] != 2048 ||
      hardCap['contexts'] != 4096 ||
      hardCap['triggers'] != 2048 ||
      hardCap['deliveries'] != 2048 ||
      hardCap['body_bytes'] != 8388608 ||
      hardCap['file_bytes'] == 0 ||
      (hardCap['file_bytes']! as int) > 16777216 ||
      hardCap['steady_budget_bytes'] != 67108864 ||
      (hardCap['steady_delta_bytes']! as int) > 67108864 ||
      hardCap['peak_budget_bytes'] != 100663296 ||
      (hardCap['peak_delta_bytes']! as int) > 100663296 ||
      (hardCap['peak_delta_bytes']! as int) <
          (hardCap['steady_delta_bytes']! as int) ||
      hardCap['owners'] != 0 ||
      disabled['rounds'] != 21 ||
      disabled['events_per_route'] != 1050000 ||
      disabled['factory_calls'] != 0 ||
      (disabled['baseline_p95_ns']! as int) >= 2000000 ||
      (disabled['disabled_p95_ns']! as int) >= 2000000 ||
      (disabled['median_ratio_ppm']! as int) <= 0 ||
      (disabled['median_ratio_ppm']! as int) > 1050000 ||
      disabled['maximum_ratio_ppm'] != 1050000 ||
      store['runs'] != 20 ||
      store['commit_budget_us'] != 250000 ||
      (store['commit_p95_us']! as int) > 250000 ||
      store['primitive_budget_us'] != 1500000 ||
      (store['primitive_p95_us']! as int) > 1500000) {
    throw const FormatException('evidence metric gate failed');
  }
}

Map<String, Object?> _integerObject(
  Object? value,
  Set<String> keys,
  String context,
) {
  final Map<String, Object?> result = _object(value, context);
  _exactKeys(result, keys, context);
  if (!result.values.every((Object? item) => item is int && item >= 0)) {
    throw FormatException('$context values are not non-negative integers');
  }
  return result;
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$context is not an object');
  }
  return value;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('$context keys differ');
  }
}

bool _sameJson(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _shaText(String source) =>
    terminalDifferentialSha256(utf8.encode(source));

List<int> _readBoundedFile(Directory root, String relative) {
  final File file = File.fromUri(root.uri.resolve(relative));
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('evidence source is not a regular file');
  }
  final int size = file.lengthSync();
  if (size <= 0 || size > _maximumSourceBytes) {
    throw const FormatException('evidence source size is invalid');
  }
  return file.readAsBytesSync();
}

String _relativePath(Directory root, File file) {
  final String rootPath = root.absolute.path.endsWith('/')
      ? root.absolute.path
      : '${root.absolute.path}/';
  final String path = file.absolute.path;
  if (!path.startsWith(rootPath)) {
    throw const FormatException('audited source escapes source root');
  }
  return path.substring(rootPath.length);
}

Future<String> _readLog(File file) async {
  if (!file.isAbsolute ||
      FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException('evidence log must be an absolute file');
  }
  final int size = await file.length();
  if (size <= 0 || size > _maximumLogBytes) {
    throw const FormatException('evidence log size is invalid');
  }
  return utf8.decode(await file.readAsBytes(), allowMalformed: false);
}

Map<String, String> _parseArguments(List<String> arguments) {
  const Set<String> expected = <String>{
    'dart-log',
    'native-log',
    'disabled-log',
    'store-log',
    'source-root',
    'output',
  };
  final Map<String, String> values = <String, String>{};
  for (final String argument in arguments) {
    final int separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator <= 2) {
      throw const FormatException('evidence argument is malformed');
    }
    final String key = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    if (!expected.contains(key) || value.isEmpty || values.containsKey(key)) {
      throw const FormatException('evidence argument is unknown or duplicated');
    }
    values[key] = value;
  }
  if (values.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(values.keys.toSet()).isNotEmpty) {
    throw const FormatException('evidence argument inventory is incomplete');
  }
  return values;
}

Future<void> _writeAtomic(File output, String source) async {
  if (!output.isAbsolute) {
    throw const FormatException('evidence output must be absolute');
  }
  await output.parent.create(recursive: true);
  final File temporary = File('${output.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString(source, flush: true);
  await temporary.rename(output.path);
}

Future<void> main(List<String> arguments) async {
  try {
    final Map<String, String> options = _parseArguments(arguments);
    final Directory sourceRoot = Directory(options['source-root']!);
    final TerminalNoteR0EvidenceSources sources =
        loadTerminalNoteR0EvidenceSources(sourceRoot);
    final TerminalNoteR0EvidenceResult result = buildTerminalNoteR0Evidence(
      dartLog: await _readLog(File(options['dart-log']!)),
      nativeLog: await _readLog(File(options['native-log']!)),
      disabledLog: await _readLog(File(options['disabled-log']!)),
      storeLog: await _readLog(File(options['store-log']!)),
      sources: sources,
    );
    await _writeAtomic(File(options['output']!), result.encode());
    stdout.writeln(result.machineLine());
  } on Object {
    stderr.writeln(
      'TERMINAL_NOTE_R0_EVIDENCE_FAIL reason=invalid_input '
      'content_free=true',
    );
    exitCode = 1;
  }
}
