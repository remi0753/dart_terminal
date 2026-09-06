import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../tool/terminal_compatibility_inventory.dart';
import '../tool/terminal_differential_adapters.dart';
import '../tool/terminal_differential_corpus.dart';
import '../tool/terminal_differential_evidence.dart';
import '../tool/terminal_differential_harness.dart';

void main() => runTerminalDifferentialEvidenceTests();

void runTerminalDifferentialEvidenceTests() {
  final TerminalDifferentialEvidenceResult result =
      runTerminalDifferentialEvidenceChecks();
  _expect(
    result.attempts == 12 &&
        result.captured == 8 &&
        result.unavailable == 4 &&
        result.machineLine() ==
            'TERMINAL_DIFFERENTIAL_EVIDENCE_PASS attempts=12 captured=8 '
                'unavailable=4 observed_replies=8',
    'external evidence matrix has exact captured and unavailable counts',
  );
  final Map<String, Object?> evidence = _object(
    jsonDecode(
      File(defaultTerminalDifferentialEvidencePath).readAsStringSync(),
    ),
  );
  final List<Map<String, Object?>> records = <Map<String, Object?>>[
    for (final Object? value in evidence['records']! as List<Object?>)
      _object(value),
  ];
  _expect(
    records.length == 12 &&
        records
            .take(4)
            .every(
              (Map<String, Object?> record) =>
                  record['profile_id'] == 'ghostty-tip-492300c-macos-arm64' &&
                  record['status'] == 'unavailable' &&
                  record['reason'] == 'macos-activation-unavailable' &&
                  (record['observed_fields']! as List<Object?>).isEmpty &&
                  record['probe_path'] == null,
            ) &&
        records
            .skip(4)
            .every(
              (Map<String, Object?> record) =>
                  record['status'] == 'captured' &&
                  (record['observed_fields']! as List<Object?>).single ==
                      'replies' &&
                  record['probe_path'] != null,
            ),
    'unavailable Ghostty cannot become agreement and captures claim replies only',
  );
  final Map<String, Object?> summary = _object(evidence['summary']);
  _expect(
    summary['observed_reply_captures'] == 8 &&
        summary['screen_style_mode_captures'] == 0,
    'evidence index does not claim unobserved screen, style, or mode state',
  );

  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(defaultTerminalCompatibilityInventoryPath),
        repositoryRoot: Directory.current,
      );
  final TerminalDifferentialManifest manifest =
      TerminalDifferentialManifest.load(
        File(defaultReviewedDifferentialManifestPath),
        inventoryIds: <String>{
          for (final TerminalCompatibilityRecord record in inventory.records)
            record.id,
        },
      );
  final Map<String, TerminalDifferentialCase> cases =
      <String, TerminalDifferentialCase>{
        for (final TerminalDifferentialCase testCase in manifest.cases)
          testCase.id: testCase,
      };
  for (final String caseId in cases.keys) {
    final TerminalDifferentialCase testCase = cases[caseId]!;
    final TerminalDifferentialObservation dart =
        TerminalDifferentialObservation.parse(
          File('$defaultReviewedDifferentialBaselineDirectory/$caseId.json')
              .readAsStringSync(),
          testCase: testCase,
        );
    final TerminalDifferentialProbeResult kitty =
        TerminalDifferentialProbeResult.load(
          File(
            'test/corpus/differential/external/'
            'kitty-0-48-2-macos-arm64/$caseId.probe.json',
          ),
        );
    final TerminalDifferentialProbeResult xterm =
        TerminalDifferentialProbeResult.load(
          File(
            'test/corpus/differential/external/'
            'xterm-411-linux-aarch64/$caseId.probe.json',
          ),
        );
    if (caseId == 'rendition-attributes-colors') {
      _expect(
        dart.replies.isNotEmpty &&
            kitty.replies.isNotEmpty &&
            xterm.replies.isNotEmpty &&
            _bytesEqual(dart.replies, xterm.replies) &&
            !_bytesEqual(dart.replies, kitty.replies) &&
            !_bytesEqual(kitty.replies, xterm.replies),
        'raw DECRQSS serialization differences remain visible in evidence',
      );
    } else {
      _expect(
        _bytesEqual(dart.replies, kitty.replies) &&
            _bytesEqual(dart.replies, xterm.replies),
        '$caseId reply evidence differs unexpectedly',
      );
    }
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<Object?, Object?>) throw StateError('expected object');
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key! as String: entry.value,
  };
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
