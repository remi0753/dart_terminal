import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_application_evidence.dart';
import 'terminal_application_matrix.dart';
import 'terminal_application_unsupported_trace.dart';
import 'terminal_compatibility_inventory.dart';
import 'terminal_differential_sha256.dart';

const String defaultTerminalApplicationAcceptancePath =
    'compatibility/application_matrix_acceptance.json';

final class TerminalApplicationAcceptanceException implements Exception {
  const TerminalApplicationAcceptanceException(this.message);

  final String message;

  @override
  String toString() => 'TerminalApplicationAcceptanceException: $message';
}

final class TerminalApplicationAcceptanceResult {
  const TerminalApplicationAcceptanceResult({
    required this.acceptedCells,
    required this.cleanAgreements,
    required this.documentedGapCells,
    required this.gaps,
    required this.uniqueSequences,
    required this.unsupportedIncrements,
  });

  final int acceptedCells;
  final int cleanAgreements;
  final int documentedGapCells;
  final int gaps;
  final int uniqueSequences;
  final int unsupportedIncrements;

  String machineLine() =>
      'TERMINAL_APPLICATION_ACCEPTANCE_PASS accepted=$acceptedCells '
      'clean=$cleanAgreements documented_gap_cells=$documentedGapCells '
      'gaps=$gaps unique_sequences=$uniqueSequences '
      'unsupported_increments=$unsupportedIncrements';
}

TerminalApplicationAcceptanceResult runTerminalApplicationAcceptanceChecks({
  File? reportFile,
  Directory? repositoryRoot,
}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  runTerminalApplicationEvidenceChecks(
    indexFile: File.fromUri(
      root.uri.resolve(defaultTerminalApplicationEvidencePath),
    ),
  );
  final File source =
      reportFile ??
      File.fromUri(root.uri.resolve(defaultTerminalApplicationAcceptancePath));
  _regularFile(source, maximumBytes: 1024 * 1024, context: 'acceptance');
  final Map<String, Object?> report = _object(
    jsonDecode(source.readAsStringSync()),
    'acceptance',
  );
  _keys(report, const <String>{
    'format',
    'version',
    'evidence_index_path',
    'evidence_index_sha256',
    'implementation_manifest_path',
    'implementation_manifest_sha256',
    'trace_tool_path',
    'trace_tool_sha256',
    'status',
    'totals',
    'cells',
    'gaps',
  }, 'acceptance');
  _expect(
    report['format'] == 'dart-terminal-application-acceptance' &&
        report['version'] == 2,
    'unsupported acceptance report',
  );
  _expect(
    report['status'] == 'accepted-with-owned-gaps',
    'acceptance status differs',
  );
  _pinnedFile(
    root,
    report['evidence_index_path'],
    report['evidence_index_sha256'],
    defaultTerminalApplicationEvidencePath,
    'evidence index',
  );
  _pinnedFile(
    root,
    report['implementation_manifest_path'],
    report['implementation_manifest_sha256'],
    'compatibility/implemented_sequence_manifest.json',
    'implementation manifest',
  );
  _pinnedFile(
    root,
    report['trace_tool_path'],
    report['trace_tool_sha256'],
    'tool/terminal_application_unsupported_trace.dart',
    'trace tool',
  );

  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File.fromUri(
          root.uri.resolve(defaultTerminalCompatibilityInventoryPath),
        ),
        repositoryRoot: root,
      );
  final Map<String, TerminalCompatibilityRecord> inventoryById =
      <String, TerminalCompatibilityRecord>{
        for (final TerminalCompatibilityRecord record in inventory.records)
          record.id: record,
      };
  final List<_AcceptanceGap> gaps = _parseGaps(
    report['gaps'],
    inventoryById,
    File.fromUri(root.uri.resolve('ROADMAP.md')).readAsStringSync(),
  );
  final Map<String, _AcceptanceGap> gapByVariant = <String, _AcceptanceGap>{};
  for (final _AcceptanceGap gap in gaps) {
    for (final String variant in gap.variants) {
      _expect(
        gapByVariant.putIfAbsent(variant, () => gap) == gap,
        'sequence variant belongs to multiple gaps',
      );
    }
  }

  final TerminalApplicationMatrixManifest manifest =
      TerminalApplicationMatrixManifest.load(
        File.fromUri(root.uri.resolve(defaultTerminalApplicationMatrixPath)),
      );
  final List<_DerivedCell> derivedCells = <_DerivedCell>[];
  final Set<String> uniqueSequences = <String>{};
  var unsupportedIncrements = 0;
  for (final TerminalApplicationScenario scenario in manifest.scenarios) {
    final File rawFile = File.fromUri(
      root.uri.resolve(
        'test/corpus/applications/external/${scenario.id}.capture.json',
      ),
    );
    final TerminalApplicationRawEvidence raw =
        TerminalApplicationRawEvidence.parse(
          rawFile.readAsStringSync(),
          scenario: scenario,
        );
    final TerminalApplicationUnsupportedTrace trace =
        traceTerminalApplicationUnsupported(
          raw.output,
          rows: scenario.rows,
          columns: scenario.columns,
          resizes: raw.resizes,
        );
    _expect(
      trace.unsupportedControls == raw.parser['unsupported_controls'] &&
          trace.cancel == raw.parser['cancel'] &&
          trace.limit == raw.parser['limit'] &&
          trace.malformed == raw.parser['malformed'] &&
          trace.incomplete == raw.parser['incomplete'],
      '${scenario.id} replay counters differ from evidence',
    );
    final Set<String> cellGaps = <String>{};
    var tracedIncrements = 0;
    for (final TerminalApplicationUnsupportedEntry entry in trace.entries) {
      final _AcceptanceGap? gap = gapByVariant[entry.hex];
      _expect(gap != null, '${scenario.id} has unowned sequence ${entry.hex}');
      cellGaps.add(gap!.id);
      uniqueSequences.add(entry.hex);
      tracedIncrements += entry.unsupportedIncrements;
    }
    _expect(
      tracedIncrements == trace.unsupportedSequences,
      '${scenario.id} trace increments differ',
    );
    unsupportedIncrements += tracedIncrements;
    final List<String> gapIds = cellGaps.toList()..sort();
    derivedCells.add(
      _DerivedCell(
        applicationId: scenario.applicationId,
        scenarioId: scenario.id,
        classification: gapIds.isEmpty ? 'clean-agreement' : 'documented-gap',
        gapIds: gapIds,
        capturedUnsupportedSequences: raw.parser['unsupported_sequences']!,
        replayedUnsupportedSequences: trace.unsupportedSequences,
      ),
    );
  }
  _expect(
    uniqueSequences.length == gapByVariant.length &&
        uniqueSequences.containsAll(gapByVariant.keys),
    'acceptance variants differ from observed sequences',
  );

  final List<Object?> cells = _array(report['cells'], 'cells');
  _expect(cells.length == derivedCells.length, 'acceptance cell count differs');
  var cleanAgreements = 0;
  var documentedGapCells = 0;
  for (var index = 0; index < cells.length; index++) {
    final Map<String, Object?> cell = _object(cells[index], 'cells[$index]');
    _keys(cell, const <String>{
      'application_id',
      'scenario_id',
      'classification',
      'accepted',
      'gap_ids',
      'captured_unsupported_sequences',
      'replayed_unsupported_sequences',
    }, 'cell');
    final _DerivedCell expected = derivedCells[index];
    final List<String> gapIds = _strings(cell['gap_ids'], 'cell.gap_ids');
    _expect(_sortedUnique(gapIds), 'cell gap IDs must be sorted and unique');
    _expect(
      cell['application_id'] == expected.applicationId &&
          cell['scenario_id'] == expected.scenarioId &&
          cell['classification'] == expected.classification &&
          cell['accepted'] == true &&
          cell['captured_unsupported_sequences'] ==
              expected.capturedUnsupportedSequences &&
          cell['replayed_unsupported_sequences'] ==
              expected.replayedUnsupportedSequences &&
          _same(gapIds, expected.gapIds),
      '${expected.scenarioId} acceptance differs from replay',
    );
    if (expected.classification == 'clean-agreement') {
      cleanAgreements++;
    } else {
      documentedGapCells++;
    }
  }

  final int safeIgnoreGaps = gaps
      .where((_AcceptanceGap gap) => gap.disposition == 'safe-ignore')
      .length;
  final Map<String, Object?> totals = _object(report['totals'], 'totals');
  _keys(totals, const <String>{
    'cells',
    'clean_agreements',
    'documented_gap_cells',
    'unique_sequences',
    'unsupported_increments',
    'gaps',
    'safe_ignore_gaps',
    'explicit_unsupported_gaps',
  }, 'totals');
  _expect(
    totals['cells'] == cells.length &&
        totals['clean_agreements'] == cleanAgreements &&
        totals['documented_gap_cells'] == documentedGapCells &&
        totals['unique_sequences'] == uniqueSequences.length &&
        totals['unsupported_increments'] == unsupportedIncrements &&
        totals['gaps'] == gaps.length &&
        totals['safe_ignore_gaps'] == safeIgnoreGaps &&
        totals['explicit_unsupported_gaps'] == gaps.length - safeIgnoreGaps,
    'acceptance totals differ from replay',
  );
  _expect(
    cells.length == 8 &&
        cleanAgreements == 7 &&
        documentedGapCells == 1 &&
        gaps.length == 1 &&
        uniqueSequences.length == 1 &&
        unsupportedIncrements == 4 &&
        safeIgnoreGaps == 0,
    'reviewed acceptance baseline differs',
  );
  return TerminalApplicationAcceptanceResult(
    acceptedCells: cells.length,
    cleanAgreements: cleanAgreements,
    documentedGapCells: documentedGapCells,
    gaps: gaps.length,
    uniqueSequences: uniqueSequences.length,
    unsupportedIncrements: unsupportedIncrements,
  );
}

List<_AcceptanceGap> _parseGaps(
  Object? value,
  Map<String, TerminalCompatibilityRecord> inventoryById,
  String roadmap,
) {
  const Map<String, String> owners = <String, String>{
    'ROADMAP.md#phase-6-terminfo': 'terminfo source、compile/install/fallback',
    'ROADMAP.md#phase-6-osc-title-cwd-policy':
        'OSC title/cwd/hyperlink/palette/clipboard policy',
    'ROADMAP.md#phase-6-focus-mouse-query':
        'focus/mouse/bracketed paste/query reports',
    'ROADMAP.md#phase-9-kitty-keyboard-protocol': 'Kitty keyboard protocol',
    'ROADMAP.md#phase-9-light-dark-notification-reports':
        'light/dark notification と extended reports',
  };
  final List<Object?> values = _array(value, 'gaps');
  final List<_AcceptanceGap> result = <_AcceptanceGap>[];
  var previous = '';
  for (var index = 0; index < values.length; index++) {
    final Map<String, Object?> gap = _object(values[index], 'gaps[$index]');
    _keys(gap, const <String>{
      'id',
      'disposition',
      'impact',
      'inventory_ids',
      'owner',
      'minimal_hex',
      'variants',
      'screen_mutation',
      'matrix_blocker',
    }, 'gap');
    final String id = _id(gap['id'], 'gap.id');
    _expect(previous.isEmpty || previous.compareTo(id) < 0, 'gaps not sorted');
    previous = id;
    final String disposition = _text(gap['disposition'], 'gap.disposition');
    _expect(
      disposition == 'safe-ignore' || disposition == 'explicit-unsupported',
      '$id disposition is invalid',
    );
    final String impact = _id(gap['impact'], 'gap.impact');
    final String owner = _text(gap['owner'], 'gap.owner');
    _expect(
      owners.containsKey(owner) && roadmap.contains(owners[owner]!),
      '$id owner is not a reviewed ROADMAP owner',
    );
    final List<String> inventoryIds = _strings(
      gap['inventory_ids'],
      'gap.inventory_ids',
    );
    _expect(_sortedUnique(inventoryIds), '$id inventory IDs are not sorted');
    for (final String inventoryId in inventoryIds) {
      final TerminalCompatibilityRecord? record = inventoryById[inventoryId];
      _expect(record != null, '$id inventory record $inventoryId is missing');
      _expect(
        disposition == 'safe-ignore'
            ? record!.support == TerminalCompatibilitySupport.safeIgnore
            : record!.support == TerminalCompatibilitySupport.unsupported ||
                  record.support == TerminalCompatibilitySupport.partial,
        '$id disposition differs from inventory $inventoryId',
      );
    }
    _expect(
      inventoryIds.isNotEmpty || owner.startsWith('ROADMAP.md#phase-9-'),
      '$id unlisted extension lacks a future protocol owner',
    );
    final String minimalHex = _hex(gap['minimal_hex'], 'gap.minimal_hex');
    final List<String> variants = _strings(gap['variants'], 'gap.variants');
    _expect(_sortedUnique(variants), '$id variants are not sorted and unique');
    for (final String variant in variants) {
      _hex(variant, '$id variant');
    }
    _expect(
      variants.contains(minimalHex),
      '$id minimal sequence is unobserved',
    );
    final int shortest = variants
        .map((String variant) => variant.length)
        .reduce((int left, int right) => left < right ? left : right);
    _expect(
      minimalHex.length == shortest,
      '$id minimal sequence is not shortest',
    );
    final Uint8List minimal = _decodeHex(minimalHex);
    final TerminalApplicationUnsupportedTrace minimalTrace =
        traceTerminalApplicationUnsupported(minimal);
    _expect(
      minimalTrace.unsupportedControls == 0 &&
          minimalTrace.unsupportedSequences == 1 &&
          minimalTrace.cancel == 0 &&
          minimalTrace.limit == 0 &&
          minimalTrace.malformed == 0 &&
          minimalTrace.incomplete == 0,
      '$id minimal sequence does not isolate one bounded reject',
    );
    final bool screenMutation = gap['screen_mutation'] == true;
    _expect(
      gap['screen_mutation'] is bool &&
          terminalApplicationUnsupportedMutatesScreen(minimal) ==
              screenMutation,
      '$id screen-mutation classification differs',
    );
    _expect(!screenMutation, '$id silently mutates screen state');
    _expect(
      gap['matrix_blocker'] == false,
      '$id remains an unaccepted matrix blocker',
    );
    result.add(
      _AcceptanceGap(
        id: id,
        disposition: disposition,
        impact: impact,
        owner: owner,
        variants: variants,
      ),
    );
  }
  return result;
}

final class _AcceptanceGap {
  const _AcceptanceGap({
    required this.id,
    required this.disposition,
    required this.impact,
    required this.owner,
    required this.variants,
  });

  final String id;
  final String disposition;
  final String impact;
  final String owner;
  final List<String> variants;
}

final class _DerivedCell {
  const _DerivedCell({
    required this.applicationId,
    required this.scenarioId,
    required this.classification,
    required this.gapIds,
    required this.capturedUnsupportedSequences,
    required this.replayedUnsupportedSequences,
  });

  final String applicationId;
  final String scenarioId;
  final String classification;
  final List<String> gapIds;
  final int capturedUnsupportedSequences;
  final int replayedUnsupportedSequences;
}

void _pinnedFile(
  Directory root,
  Object? pathValue,
  Object? hashValue,
  String expectedPath,
  String context,
) {
  _expect(pathValue == expectedPath, '$context path differs');
  final File file = File.fromUri(root.uri.resolve(expectedPath));
  _regularFile(file, maximumBytes: 4 * 1024 * 1024, context: context);
  _expect(
    hashValue == terminalDifferentialSha256(file.readAsBytesSync()),
    '$context hash differs',
  );
}

void _regularFile(
  File file, {
  required int maximumBytes,
  required String context,
}) {
  _expect(file.existsSync(), '$context is missing');
  final FileStat stat = file.statSync();
  _expect(stat.type == FileSystemEntityType.file, '$context is not a file');
  _expect(stat.size <= maximumBytes, '$context exceeds size limit');
}

Map<String, Object?> _object(Object? value, String context) {
  _expect(value is Map<Object?, Object?>, '$context must be an object');
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry
      in (value! as Map<Object?, Object?>).entries) {
    _expect(entry.key is String, '$context has a non-string key');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  _expect(value is List<Object?>, '$context must be an array');
  return value! as List<Object?>;
}

List<String> _strings(Object? value, String context) {
  final List<Object?> values = _array(value, context);
  return <String>[
    for (var index = 0; index < values.length; index++)
      _text(values[index], '$context[$index]'),
  ];
}

String _text(Object? value, String context) {
  _expect(value is String && value.isNotEmpty, '$context must be text');
  return value! as String;
}

String _id(Object? value, String context) {
  final String result = _text(value, context);
  _expect(
    RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(result),
    '$context is not an identifier',
  );
  return result;
}

String _hex(Object? value, String context) {
  final String result = _text(value, context);
  _expect(
    result.length.isEven &&
        result.length >= 2 &&
        result.length <= 8192 * 2 &&
        RegExp(r'^[0-9a-f]+$').hasMatch(result),
    '$context is not bounded lowercase hex',
  );
  return result;
}

Uint8List _decodeHex(String value) {
  final Uint8List result = Uint8List(value.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

bool _sortedUnique(List<String> values) {
  for (var index = 1; index < values.length; index++) {
    if (values[index - 1].compareTo(values[index]) >= 0) return false;
  }
  return true;
}

bool _same(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _keys(Map<String, Object?> value, Set<String> expected, String context) {
  _expect(
    value.keys.toSet().length == expected.length &&
        value.keys.toSet().containsAll(expected),
    '$context keys differ',
  );
}

Never _fail(String message) {
  throw TerminalApplicationAcceptanceException(message);
}

void _expect(bool condition, String message) {
  if (!condition) _fail(message);
}

void main(List<String> arguments) {
  try {
    if (arguments.length != 1 || arguments.single != '--check') {
      _fail(
        'usage: dart run tool/terminal_application_acceptance.dart --check',
      );
    }
    stdout.writeln(runTerminalApplicationAcceptanceChecks().machineLine());
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
