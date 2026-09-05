import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import '../tool/product_parser_corpus.dart';

void main() => runProductParserCorpusTests();

void runProductParserCorpusTests() {
  _testReviewedProductCorpus();
  _testPrintModeDoesNotRewriteSnapshots();
  _testManifestEnvelopeValidation();
  _testCaseHexPathDimensionAndLimitValidation();
  _testSnapshotValidationAndBounds();
}

void _testReviewedProductCorpus() {
  final ProductParserCorpusResult result = runProductParserCorpus();
  _expect(result.caseCount == 4, 'reviewed corpus case count');
  _expect(result.inputBytes == 156, 'reviewed corpus input byte count');
  _expect(result.splitRuns == 164, 'reviewed corpus exhaustive split count');
  _expect(
    result.snapshotHash == 1242323160,
    'reviewed corpus aggregate snapshot hash',
  );
  _expect(
    result.machineLine() ==
        'PRODUCT_PARSER_CORPUS_PASS cases=4 input_bytes=156 '
            'split_runs=164 snapshot_hash=1242323160',
    'corpus result has stable machine-readable output',
  );
}

void _testPrintModeDoesNotRewriteSnapshots() {
  final File snapshot = File(
    'test/corpus/parser/snapshots/screen-semantics.snapshot',
  );
  final Uint8List before = snapshot.readAsBytesSync();
  final StringBuffer output = StringBuffer();
  final ProductParserCorpusResult result = runProductParserCorpus(
    printSnapshots: true,
    output: output,
  );
  _expect(
    result.caseCount == 4 && result.splitRuns == 0,
    'print mode performs one review run per case',
  );
  _expect(
    output.toString().contains('SNAPSHOT screen-semantics ') &&
        output.toString().contains('END_SNAPSHOT bounded-recovery'),
    'print mode exposes bounded reviewed sections',
  );
  _expect(
    _sameBytes(before, snapshot.readAsBytesSync()),
    'print mode never rewrites an expected snapshot',
  );
}

void _testManifestEnvelopeValidation() {
  _withFixture((Directory root, Map<String, Object?> manifest) {
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'format': 'unknown',
    }, 'unsupported corpus format');
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'version': 2,
    }, 'unsupported corpus version');
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'extra': true,
    }, 'root keys differ');
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'cases': <Object?>[],
    }, 'corpus cases must not be empty');
    final Map<String, Object?> duplicate = _case(manifest);
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'cases': <Object?>[duplicate, Map<String, Object?>.from(duplicate)],
    }, 'duplicate corpus id fixture');
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'cases': List<Object?>.generate(
        129,
        (int index) => <String, Object?>{
          ...duplicate,
          'id': 'case-$index',
          'snapshot': 'snapshots/case-$index.snapshot',
        },
      ),
    }, 'corpus cases 129 exceed 128');
  });
}

void _testCaseHexPathDimensionAndLimitValidation() {
  _withFixture((Directory root, Map<String, Object?> manifest) {
    final Map<String, Object?> valid = _case(manifest);
    _expectCaseFailure(root, manifest, valid, 'input_hex', '4g', 'invalid hex');
    _expectCaseFailure(root, manifest, valid, 'input_hex', '4', 'odd digit');
    _expectCaseFailure(
      root,
      manifest,
      valid,
      'input_hex',
      '',
      'must not be empty',
    );
    _expectCaseFailure(
      root,
      manifest,
      valid,
      'input_hex',
      List<String>.filled(16 * 1024 + 1, '41').join(' '),
      'input exceeds 16384 bytes',
    );
    _expectCaseFailure(
      root,
      manifest,
      valid,
      'snapshot',
      '../fixture.snapshot',
      'snapshot path must be',
    );
    _expectCaseFailure(root, manifest, valid, 'rows', 0, 'invalid rows');
    _expectCaseFailure(
      root,
      manifest,
      valid,
      'columns',
      513,
      'invalid columns',
    );
    final Map<String, Object?> invalidLimits = Map<String, Object?>.from(valid);
    invalidLimits['parser_limits'] = <String, Object?>{
      ...(valid['parser_limits']! as Map<String, Object?>),
      'max_string_bytes': 8192,
    };
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'cases': <Object?>[invalidLimits],
    }, 'invalid parser limits');
    final Map<String, Object?> unknownCase = Map<String, Object?>.from(valid)
      ..['unknown'] = 1;
    _expectFailure(root, <String, Object?>{
      ...manifest,
      'cases': <Object?>[unknownCase],
    }, 'corpus case keys differ');
  });
}

void _testSnapshotValidationAndBounds() {
  _withFixture((Directory root, Map<String, Object?> manifest) {
    final File snapshot = File('${root.path}/snapshots/fixture.snapshot');
    final String valid = snapshot.readAsStringSync();
    snapshot.writeAsStringSync(valid.trimRight());
    _expectFailure(root, manifest, 'snapshot must end with one newline');

    snapshot.writeAsStringSync('$valid\n');
    _expectFailure(root, manifest, 'snapshot must end with one newline');

    snapshot.writeAsStringSync('wrong-header\n');
    _expectFailure(root, manifest, 'unsupported terminal-state header');

    snapshot.deleteSync();
    _expectFailure(root, manifest, 'snapshot does not exist');

    snapshot.createSync(recursive: true);
    snapshot.openSync(mode: FileMode.write)
      ..truncateSync(16 * 1024 * 1024 + 1)
      ..closeSync();
    _expectFailure(root, manifest, 'snapshot size 16777217 is outside');

    snapshot.deleteSync();
    final File linkTarget = File('${root.path}/link-target.snapshot')
      ..writeAsStringSync(valid);
    Link(snapshot.path).createSync(linkTarget.path);
    _expectFailure(root, manifest, 'snapshot must be a regular file');
  });
}

void _withFixture(
  void Function(Directory root, Map<String, Object?> manifest) body,
) {
  final Directory root = Directory.systemTemp.createTempSync(
    'dart-terminal-product-corpus-',
  );
  try {
    final Directory snapshots = Directory('${root.path}/snapshots')
      ..createSync();
    final String snapshot = _expectedSingleA();
    File('${snapshots.path}/fixture.snapshot').writeAsStringSync(snapshot);
    final Map<String, Object?> manifest = <String, Object?>{
      'format': 'dart-terminal-product-parser-corpus',
      'version': 1,
      'cases': <Object?>[
        <String, Object?>{
          'id': 'fixture',
          'description': 'temporary loader fixture',
          'input_hex': '41',
          'snapshot': 'snapshots/fixture.snapshot',
          'rows': 2,
          'columns': 4,
          'parser_limits': <String, Object?>{
            'max_sequence_bytes': 32,
            'max_string_bytes': 16,
            'max_parameters': 8,
            'max_intermediates': 4,
            'max_numeric_value': 1000,
          },
          'scrollback': <String, Object?>{
            'max_lines': 4,
            'max_bytes': 4096,
            'page_rows': 2,
          },
        },
      ],
    };
    body(root, manifest);
  } finally {
    root.deleteSync(recursive: true);
  }
}

Map<String, Object?> _case(Map<String, Object?> manifest) =>
    Map<String, Object?>.from(
      (manifest['cases']! as List<Object?>).single! as Map<String, Object?>,
    );

void _expectCaseFailure(
  Directory root,
  Map<String, Object?> manifest,
  Map<String, Object?> valid,
  String key,
  Object? value,
  String message,
) {
  final Map<String, Object?> changed = Map<String, Object?>.from(valid)
    ..[key] = value;
  _expectFailure(root, <String, Object?>{
    ...manifest,
    'cases': <Object?>[changed],
  }, message);
}

void _expectFailure(
  Directory root,
  Map<String, Object?> manifest,
  String expectedMessage,
) {
  final File file = File('${root.path}/manifest.json');
  file.writeAsStringSync(jsonEncode(manifest));
  try {
    runProductParserCorpus(corpusPath: file.path);
  } on ProductParserCorpusException catch (error) {
    _expect(
      error.message.contains(expectedMessage),
      'failure contains "$expectedMessage": ${error.message}',
    );
    return;
  }
  throw StateError('Expected corpus failure containing $expectedMessage');
}

String _expectedSingleA() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 2,
    columns: 4,
    scrollback: TerminalScrollback(maxLines: 4, maxBytes: 4096, pageRows: 2),
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (_) => true,
  );
  final VtParser parser = VtParser(
    sink: sink,
    limits: const VtParserLimits(
      maxSequenceBytes: 32,
      maxStringBytes: 16,
      maxParameters: 8,
      maxIntermediates: 4,
      maxNumericValue: 1000,
    ),
  );
  parser.parse(Uint8List.fromList(const <int>[0x41]));
  parser.finish();
  return const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
}

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}
