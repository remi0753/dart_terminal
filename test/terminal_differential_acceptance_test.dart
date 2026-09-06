import 'dart:convert';
import 'dart:io';

import '../tool/terminal_differential_acceptance.dart';

void main() => runTerminalDifferentialAcceptanceTests();

void runTerminalDifferentialAcceptanceTests() {
  final TerminalDifferentialAcceptanceResult result =
      runTerminalDifferentialAcceptanceChecks();
  _expect(
    result.accepted == 12 &&
        result.agreements == 8 &&
        result.documentedGaps == 0 &&
        result.unavailable == 4 &&
        result.decrqssRegressionBytes == 7 &&
        result.machineLine() ==
            'TERMINAL_DIFFERENTIAL_ACCEPTANCE_PASS accepted=12 '
                'agreements=8 documented_gaps=0 unavailable=4 '
                'decrqss_regression_bytes=7',
    'acceptance result has exact reviewed totals',
  );

  final Map<String, Object?> report = _object(
    jsonDecode(
      File(defaultTerminalDifferentialAcceptancePath).readAsStringSync(),
    ),
  );
  final Map<String, Object?> summary = _object(report['summary']);
  _expect(
    summary['attempts'] == 12 &&
        summary['accepted'] == 12 &&
        summary['agreements'] == 8 &&
        summary['semantic_agreements'] == 1 &&
        summary['documented_gaps'] == 0 &&
        summary['unavailable'] == 4 &&
        summary['unexpected_mismatches'] == 0 &&
        summary['stale_gaps'] == 0 &&
        summary['captured_unobserved_fields'] == 16 &&
        summary['silent_results'] == 0,
    'acceptance report cannot hide a result or an unobserved field',
  );

  final List<Map<String, Object?>> records = <Map<String, Object?>>[
    for (final Object? value in report['results']! as List<Object?>)
      _object(value),
  ];
  _expect(
    records.length == 12 &&
        records
            .take(4)
            .every(
              (Map<String, Object?> record) =>
                  record['profile_id'] == 'ghostty-tip-492300c-macos-arm64' &&
                  record['classification'] == 'unavailable' &&
                  record['accepted'] == true &&
                  record['reason'] == 'macos-activation-unavailable' &&
                  (record['observed_fields']! as List<Object?>).isEmpty &&
                  (record['unobserved_fields']! as List<Object?>).isNotEmpty,
            ),
    'Ghostty activation unavailability remains explicit and unobserved',
  );
  final List<Map<String, Object?>> captured = records.skip(4).toList();
  _expect(
    captured.length == 8 &&
        captured.every(
          (Map<String, Object?> record) =>
              record['accepted'] == true &&
              (record['observed_fields']! as List<Object?>).join(',') ==
                  'replies' &&
              (record['unobserved_fields']! as List<Object?>).isNotEmpty &&
              record['probe_path'] != null,
        ) &&
        captured
                .where(
                  (Map<String, Object?> record) =>
                      record['classification'] == 'agreement',
                )
                .length ==
            7 &&
        captured
                .where(
                  (Map<String, Object?> record) =>
                      record['classification'] == 'semantic-agreement',
                )
                .length ==
            1,
    'captured comparisons accept reply evidence only',
  );
  final List<Map<String, Object?>> semantic = captured
      .where(
        (Map<String, Object?> record) =>
            record['classification'] == 'semantic-agreement',
      )
      .toList();
  _expect(
    semantic.length == 1 &&
        semantic.single['case_id'] == 'rendition-attributes-colors' &&
        (semantic.single['difference_fields']! as List<Object?>).join(',') ==
            'replies' &&
        semantic.single['gap_owner'] == null &&
        semantic.single['reason'] == 'valid-product-specific-sgr-serialization',
    'valid Kitty serialization remains visible as a semantic agreement',
  );

  final Map<String, Object?> minimal = _object(report['decrqss_regression']);
  final List<Map<String, Object?>> minimalCaptures = <Map<String, Object?>>[
    for (final Object? value in minimal['captures']! as List<Object?>)
      _object(value),
  ];
  _expect(
    minimal['id'] == 'decrqss-sgr-query-gap' &&
        minimal['source_case_id'] == 'rendition-attributes-colors' &&
        minimal['input_hex'] == '1b5024716d1b5c' &&
        minimal['input_bytes'] == 7 &&
        minimal['dart_reply_bytes'] == 9 &&
        minimal['dart_replies_sha256'] != null &&
        minimal['gap_owner'] == null &&
        minimalCaptures.length == 3 &&
        minimalCaptures.first['classification'] == 'unavailable' &&
        minimalCaptures[1]['classification'] == 'semantic-agreement' &&
        minimalCaptures[1]['reply_bytes'] == 8 &&
        minimalCaptures[2]['classification'] == 'agreement' &&
        minimalCaptures[2]['reply_bytes'] == 9,
    'minimal regression accepts exact xterm and visible Kitty serialization',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<Object?, Object?>) throw StateError('expected object');
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key! as String: entry.value,
  };
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
