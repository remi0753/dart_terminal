import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../tool/terminal_compatibility_inventory.dart';
import '../tool/terminal_differential_harness.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single.startsWith('--fake-driver=')) {
    await _runFakeDriver(arguments.single.substring('--fake-driver='.length));
    return;
  }
  await runTerminalDifferentialHarnessTests();
}

Future<void> runTerminalDifferentialHarnessTests() async {
  _testContractManifestAndProductBackend();
  _testManifestValidation();
  _testObservationValidationAndComparison();
  await _testSubprocessDriverClassifications();
}

Set<String> _inventoryIds() {
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(defaultTerminalCompatibilityInventoryPath),
        repositoryRoot: Directory.current,
      );
  return <String>{
    for (final TerminalCompatibilityRecord record in inventory.records)
      record.id,
  };
}

TerminalDifferentialManifest _manifest() => TerminalDifferentialManifest.load(
  File(defaultTerminalDifferentialManifestPath),
  inventoryIds: _inventoryIds(),
);

void _testContractManifestAndProductBackend() {
  final TerminalDifferentialManifest manifest = _manifest();
  _expect(
    manifest.version == 1 &&
        manifest.scope == 'contract-smoke' &&
        manifest.observationVersion == 1 &&
        manifest.cases.length == 2,
    'contract manifest has exact version and smoke cases',
  );
  final TerminalDifferentialContractResult result =
      runTerminalDifferentialContractChecks();
  _expect(
    result.caseCount == 2 &&
        result.inputBytes == 24 &&
        result.splitRuns == 28 &&
        result.machineLine() ==
            'TERMINAL_DIFFERENTIAL_CONTRACT_PASS cases=2 input_bytes=24 '
                'split_runs=28',
    'Dart backend is exact across whole, every split, and bytewise input',
  );

  final TerminalDifferentialCase modeCase = manifest.cases.last;
  final TerminalDifferentialObservation observation =
      const DartTerminalDifferentialBackend().capture(modeCase);
  _expect(
    observation.modes['application_cursor'] == true &&
        _hex(observation.replies) == '1b5b3f313b312479',
    'product observation exposes DECCKM state and exact DECRQM reply',
  );
}

void _testManifestValidation() {
  final String fixture = File(defaultTerminalDifferentialManifestPath)
      .readAsStringSync();
  final Set<String> inventoryIds = _inventoryIds();
  _expectManifestFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    inventoryIds,
    'unsupported manifest version',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"cases": [', '"unknown": true, "cases": ['),
    inventoryIds,
    'root keys differ',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '"ecma48:csi:cub",\n        "ecma48:csi:sgr"',
      '"ecma48:csi:sgr",\n        "ecma48:csi:cub"',
    ),
    inventoryIds,
    'inventory_ids must be sorted',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"ecma48:csi:cub"', '"ecma48:csi:missing"'),
    inventoryIds,
    'unknown inventory id',
  );
  _expectManifestFailure(
    fixture.replaceFirst('41 42 43 1b 5b 32 44', '41 42 43 1b 5b 32 4g'),
    inventoryIds,
    'invalid hex',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"rows": 2', '"rows": 0'),
    inventoryIds,
    'rows are outside',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '"text",\n        "style",\n        "color"',
      '"color",\n        "style",\n        "text"',
    ),
    inventoryIds,
    'canonical order',
  );
  _expectManifestFailure(
    fixture.replaceFirst(
      '"expectation": "agree"',
      '"expectation": "documented-gap"',
    ),
    inventoryIds,
    'requires a safe docs gap_owner',
  );
  _expectManifestFailure(
    fixture.replaceFirst('"gap_owner": null', '"gap_owner": "docs/gap.md"'),
    inventoryIds,
    'agree expectation cannot have gap_owner',
  );
}

void _testObservationValidationAndComparison() {
  final TerminalDifferentialCase testCase = _manifest().cases.first;
  final TerminalDifferentialObservation product =
      const DartTerminalDifferentialBackend().capture(testCase);
  final TerminalDifferentialObservation decoded =
      TerminalDifferentialObservation.parse(
        product.encode(),
        testCase: testCase,
      );
  const TerminalDifferentialComparator comparator =
      TerminalDifferentialComparator();
  final TerminalDifferentialComparison equal = comparator.compare(
    testCase,
    product,
    decoded,
  );
  _expect(
    equal.matches && equal.accepted && equal.differences.isEmpty,
    'observation round trip compares equal',
  );

  final List<TerminalDifferentialRow> changedRows = <TerminalDifferentialRow>[
    for (int row = 0; row < product.rows.length; row++)
      TerminalDifferentialRow(
        wrapped: product.rows[row].wrapped,
        cells: <TerminalDifferentialCell>[
          for (
            int column = 0;
            column < product.rows[row].cells.length;
            column++
          )
            if (row == 0 && column == 0)
              TerminalDifferentialCell(
                text: 'X',
                width: product.rows[row].cells[column].width,
                style: product.rows[row].cells[column].style,
                foreground: product.rows[row].cells[column].foreground,
                background: product.rows[row].cells[column].background,
              )
            else
              product.rows[row].cells[column],
        ],
      ),
  ];
  final TerminalDifferentialObservation changed =
      TerminalDifferentialObservation(
        caseId: product.caseId,
        backendId: 'reference-fixture',
        provenance: product.provenance,
        activeScreen: product.activeScreen,
        rows: changedRows,
        cursor: product.cursor,
        modes: product.modes,
        replies: product.replies,
      );
  final TerminalDifferentialComparison mismatch = comparator.compare(
    testCase,
    product,
    changed,
  );
  _expect(
    !mismatch.matches &&
        !mismatch.accepted &&
        mismatch.differences.single == 'text@0,0',
    'mismatch reports a content-free field coordinate and rejects agree policy',
  );
  final TerminalDifferentialCase documentedGap = TerminalDifferentialCase(
    id: testCase.id,
    description: testCase.description,
    inventoryIds: testCase.inventoryIds,
    input: testCase.input,
    rows: testCase.rows,
    columns: testCase.columns,
    fields: testCase.fields,
    expectation: TerminalDifferentialExpectation.documentedGap,
    gapOwner: 'docs/phase6/black-box-differential-harness.md',
  );
  _expect(
    comparator.compare(documentedGap, product, changed).accepted &&
        !comparator.compare(documentedGap, product, product).accepted,
    'documented gap requires a real difference and detects a stale gap',
  );

  final String encoded = product.encode();
  _expectObservationFailure(
    encoded.replaceFirst('"version":1', '"version":2'),
    testCase,
    'unsupported observation version',
  );
  _expectObservationFailure(
    encoded.replaceFirst(
      '"case_id":"${testCase.id}"',
      '"case_id":"wrong-case"',
    ),
    testCase,
    'case_id differs',
  );
  _expectObservationFailure(
    encoded.replaceFirst('"width":1', '"width":3'),
    testCase,
    'width is outside',
  );
  _expectObservationFailure(
    encoded.replaceFirst('"shape":"block"', '"shape":"unknown"'),
    testCase,
    'cursor.shape is unknown',
  );
  final String external = changed.encode();
  _expectObservationFailure(
    external.replaceFirst(
      '"product":"dart-terminal"',
      '"product":"fake-reference"',
    ),
    testCase,
    'external product requires executable_sha256',
  );
  _expectObservationFailure(
    encoded.replaceFirst(
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      'not-a-hash',
    ),
    testCase,
    'config_sha256 is not SHA-256',
  );
}

Future<void> _testSubprocessDriverClassifications() async {
  final TerminalDifferentialCase testCase = _manifest().cases.first;
  final String helper = File('test/terminal_differential_harness_test.dart')
      .absolute
      .path;
  Future<TerminalDifferentialDriverResult> invoke(
    String mode, {
    TerminalDifferentialSubprocessDriver driver =
        const TerminalDifferentialSubprocessDriver(),
  }) => driver.run(
    executable: Platform.resolvedExecutable,
    arguments: <String>[helper, '--fake-driver=$mode'],
    testCase: testCase,
  );

  final TerminalDifferentialDriverResult ok = await invoke('ok');
  _expect(
    ok.status == TerminalDifferentialDriverStatus.ok &&
        ok.exitCode == 0 &&
        ok.observation?.caseId == testCase.id &&
        ok.stdoutBytes > 0,
    'partial-write valid driver response is accepted exactly once',
  );
  final TerminalDifferentialDriverResult malformed = await invoke('malformed');
  _expect(
    malformed.status == TerminalDifferentialDriverStatus.protocolError &&
        malformed.observation == null,
    'malformed driver output is a protocol error',
  );
  final TerminalDifferentialDriverResult duplicate = await invoke('duplicate');
  _expect(
    duplicate.status == TerminalDifferentialDriverStatus.protocolError,
    'duplicate JSON results cannot be accepted as one observation',
  );
  final TerminalDifferentialDriverResult crashed = await invoke('crash');
  _expect(
    crashed.status == TerminalDifferentialDriverStatus.crashed &&
        crashed.exitCode == 7 &&
        crashed.stderrBytes > 0,
    'nonzero driver exit is classified without exposing stderr content',
  );
  final TerminalDifferentialDriverResult signaled = await invoke('signal');
  _expect(
    signaled.status == TerminalDifferentialDriverStatus.crashed &&
        signaled.exitCode != 0,
    'signal termination is classified as a crash',
  );
  final TerminalDifferentialDriverResult timeout = await invoke(
    'timeout',
    driver: const TerminalDifferentialSubprocessDriver(
      timeout: Duration(milliseconds: 50),
    ),
  );
  _expect(
    timeout.status == TerminalDifferentialDriverStatus.timedOut,
    'driver deadline is bounded and classified',
  );
  final TerminalDifferentialDriverResult overflow = await invoke(
    'overflow',
    driver: const TerminalDifferentialSubprocessDriver(maximumOutputBytes: 128),
  );
  _expect(
    overflow.status == TerminalDifferentialDriverStatus.outputLimit &&
        overflow.stdoutBytes == 128,
    'oversized stdout is killed and capped',
  );
  final TerminalDifferentialDriverResult stderrOverflow = await invoke(
    'stderr-overflow',
    driver: const TerminalDifferentialSubprocessDriver(maximumStderrBytes: 64),
  );
  _expect(
    stderrOverflow.status == TerminalDifferentialDriverStatus.outputLimit &&
        stderrOverflow.stderrBytes == 64,
    'oversized stderr is killed and capped',
  );
  final TerminalDifferentialDriverResult unavailable =
      await const TerminalDifferentialSubprocessDriver().run(
        executable: '/private/tmp/dart-terminal-no-such-differential-driver',
        arguments: const <String>[],
        testCase: testCase,
      );
  _expect(
    unavailable.status == TerminalDifferentialDriverStatus.unavailable &&
        unavailable.exitCode == null &&
        unavailable.stdoutBytes == 0,
    'missing executable is unavailable, never agreement',
  );
  final Directory nonExecutableDirectory = Directory.systemTemp.createTempSync(
    'dart-terminal-non-executable-driver-',
  );
  try {
    final File nonExecutable = File.fromUri(
      nonExecutableDirectory.uri.resolve('driver'),
    )..writeAsStringSync('not executable\n');
    final TerminalDifferentialDriverResult startFailure =
        await const TerminalDifferentialSubprocessDriver().run(
          executable: nonExecutable.path,
          arguments: const <String>[],
          testCase: testCase,
        );
    _expect(
      startFailure.status == TerminalDifferentialDriverStatus.startFailure,
      'an existing path that cannot execute is distinct from unavailable',
    );
  } finally {
    nonExecutableDirectory.deleteSync(recursive: true);
  }
  _expect(
    !ok.machineLine(testCase.id).contains('41 42 43') &&
        crashed.machineLine(testCase.id).contains('stderr_bytes=') &&
        !crashed.machineLine(testCase.id).contains('fake crash'),
    'driver diagnostics expose only bounded scalar metadata',
  );
}

Future<void> _runFakeDriver(String mode) async {
  switch (mode) {
    case 'malformed':
      stdout.write('{not-json}\n');
      return;
    case 'duplicate':
      final String response = await _fakeObservationFromRequest();
      stdout.write(response);
      stdout.write(response);
      return;
    case 'crash':
      stderr.write('fake crash content must stay private');
      exitCode = 7;
      return;
    case 'signal':
      Process.killPid(pid, ProcessSignal.sigkill);
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    case 'timeout':
      await Future<void>.delayed(const Duration(seconds: 2));
      return;
    case 'overflow':
      stdout.write(List<String>.filled(4096, 'x').join());
      return;
    case 'stderr-overflow':
      stderr.write(List<String>.filled(4096, 'x').join());
      return;
    case 'ok':
      final String response = await _fakeObservationFromRequest();
      final int split = response.length ~/ 2;
      stdout.write(response.substring(0, split));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      stdout.write(response.substring(split));
      return;
    default:
      exitCode = 64;
  }
}

Future<String> _fakeObservationFromRequest() async {
  final String requestSource = await utf8.decoder.bind(stdin).join();
  final Map<String, Object?> request = Map<String, Object?>.from(
    jsonDecode(requestSource) as Map<Object?, Object?>,
  );
  final Map<String, Object?> testCase = Map<String, Object?>.from(
    request['case']! as Map<Object?, Object?>,
  );
  final int rows = testCase['rows']! as int;
  final int columns = testCase['columns']! as int;
  final String caseId = testCase['id']! as String;
  final Map<String, Object?> blank = <String, Object?>{
    'text': '',
    'width': 1,
    'style': 0,
    'foreground': 0,
    'background': 0,
  };
  return '${jsonEncode(<String, Object?>{
    'format': TerminalDifferentialObservation.formatName,
    'version': TerminalDifferentialObservation.formatVersion,
    'case_id': caseId,
    'backend_id': 'fake-reference',
    'provenance': <String, Object?>{'product': 'fake-reference', 'product_version': '1.0', 'implementation_revision': 'fixture-v1', 'executable_sha256': List<String>.filled(64, '0').join(), 'config_id': 'fixture-v1', 'config_sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'capture_method': 'json-fixture-v1', 'os': 'macos', 'architecture': 'arm64'},
    'observation': <String, Object?>{
      'active_screen': 'primary',
      'rows': <Object?>[
        for (int row = 0; row < rows; row++) <String, Object?>{
            'wrapped': false,
            'cells': <Object?>[for (int column = 0; column < columns; column++) blank],
          },
      ],
      'cursor': <String, Object?>{'row': 0, 'column': 0, 'visible': true, 'blinking': true, 'shape': 'block'},
      'modes': <String, Object?>{'application_cursor': false, 'application_keypad': false, 'autowrap': true, 'bracketed_paste': false, 'horizontal_margins': false, 'insert': false, 'mouse_encoding': 'legacy', 'mouse_tracking': 'none', 'origin': false, 'reverse_video': false},
      'replies_hex': '',
    },
  })}\n';
}

void _expectManifestFailure(
  String source,
  Set<String> inventoryIds,
  String messagePart,
) {
  try {
    TerminalDifferentialManifest.parse(source, inventoryIds: inventoryIds);
  } on TerminalDifferentialException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'manifest failed for expected reason $messagePart: $error',
    );
    return;
  }
  throw StateError('test failed: manifest accepted invalid $messagePart');
}

void _expectObservationFailure(
  String source,
  TerminalDifferentialCase testCase,
  String messagePart,
) {
  try {
    TerminalDifferentialObservation.parse(source, testCase: testCase);
  } on TerminalDifferentialException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'observation failed for expected reason $messagePart: $error',
    );
    return;
  }
  throw StateError('test failed: observation accepted invalid $messagePart');
}

String _hex(Uint8List bytes) => <String>[
  for (final int byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join();

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
