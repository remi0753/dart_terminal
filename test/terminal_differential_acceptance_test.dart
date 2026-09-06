import 'dart:convert';
import 'dart:io';

import '../tool/terminal_differential_acceptance.dart';

void main() => runTerminalDifferentialAcceptanceTests();

void runTerminalDifferentialAcceptanceTests() {
  final TerminalDifferentialAcceptanceResult result =
      runTerminalDifferentialAcceptanceChecks();
  _expect(
    result.accepted == 12 &&
        result.agreements == 6 &&
        result.documentedGaps == 2 &&
        result.unavailable == 4 &&
        result.minimalGapBytes == 7 &&
        result.machineLine() ==
            'TERMINAL_DIFFERENTIAL_ACCEPTANCE_PASS accepted=12 '
                'agreements=6 documented_gaps=2 unavailable=4 '
                'minimal_gap_bytes=7',
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
        summary['agreements'] == 6 &&
        summary['documented_gaps'] == 2 &&
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
            6,
    'captured comparisons accept reply evidence only',
  );
  final List<Map<String, Object?>> gaps = captured
      .where(
        (Map<String, Object?> record) =>
            record['classification'] == 'documented-gap',
      )
      .toList();
  _expect(
    gaps.length == 2 &&
        gaps.every(
          (Map<String, Object?> record) =>
              record['case_id'] == 'rendition-attributes-colors' &&
              (record['difference_fields']! as List<Object?>).join(',') ==
                  'replies' &&
              record['gap_owner'] == 'docs/phase6/decrqss-sgr-gap.md',
        ),
    'each accepted mismatch is assigned to the DECRQSS gap owner',
  );

  final Map<String, Object?> minimal = _object(report['minimal_gap']);
  final List<Map<String, Object?>> minimalCaptures = <Map<String, Object?>>[
    for (final Object? value in minimal['captures']! as List<Object?>)
      _object(value),
  ];
  _expect(
    minimal['id'] == 'decrqss-sgr-query-gap' &&
        minimal['source_case_id'] == 'rendition-attributes-colors' &&
        minimal['input_hex'] == '1b5024716d1b5c' &&
        minimal['input_bytes'] == 7 &&
        minimal['dart_reply_bytes'] == 0 &&
        minimal['gap_owner'] == 'docs/phase6/decrqss-sgr-gap.md' &&
        minimalCaptures.length == 3 &&
        minimalCaptures.first['classification'] == 'unavailable' &&
        minimalCaptures[1]['classification'] == 'documented-gap' &&
        minimalCaptures[1]['reply_bytes'] == 8 &&
        minimalCaptures[2]['classification'] == 'documented-gap' &&
        minimalCaptures[2]['reply_bytes'] == 9,
    'minimal gap preserves Dart silence and both product-specific SGR replies',
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
