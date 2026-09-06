import 'dart:io';

import '../tool/generate_terminal_compatibility_inventory.dart'
    as inventory_generator;
import '../tool/generate_terminal_compatibility_summary.dart'
    as summary_generator;
import '../tool/terminal_compatibility_inventory.dart';

void main() => runTerminalCompatibilityInventoryTests();

void runTerminalCompatibilityInventoryTests() {
  _testCompletePinnedInventory();
  _testGeneratedArtifactsAreFresh();
  _testImplementationSurfaceReconciliation();
  _testSchemaRejectsMalformedRecords();
  _testSelectorBoundsAndTaxonomy();
}

void _testCompletePinnedInventory() {
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(defaultTerminalCompatibilityInventoryPath),
        repositoryRoot: Directory.current,
      );
  final Map<TerminalCompatibilitySelectorKind, int> kinds =
      inventory.selectorKindCounts;
  final Map<TerminalCompatibilitySupport, int> support =
      inventory.supportCounts;
  _expect(
    inventory.version == 1 &&
        inventory.inventoryRevision == 2 &&
        inventory.scope == 'complete-baseline' &&
        inventory.sourcePins.length == 4 &&
        inventory.records.length == 260 &&
        kinds[TerminalCompatibilitySelectorKind.c0] == 10 &&
        kinds[TerminalCompatibilitySelectorKind.c1] == 9 &&
        kinds[TerminalCompatibilitySelectorKind.esc] == 35 &&
        kinds[TerminalCompatibilitySelectorKind.csi] == 101 &&
        kinds[TerminalCompatibilitySelectorKind.osc] == 14 &&
        kinds[TerminalCompatibilitySelectorKind.dcs] == 8 &&
        kinds[TerminalCompatibilitySelectorKind.sos] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.pm] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.apc] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.mode] == 80 &&
        support[TerminalCompatibilitySupport.implemented] == 85 &&
        support[TerminalCompatibilitySupport.partial] == 19 &&
        support[TerminalCompatibilitySupport.safeIgnore] == 9 &&
        support[TerminalCompatibilitySupport.unsupported] == 147,
    'complete baseline covers every selector kind with exact totals',
  );
  final TerminalCompatibilitySourcePin ecma = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) => pin.id == 'ecma-48-5e',
  );
  final TerminalCompatibilitySourcePin dec = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) => pin.id == 'dec-vt510-rm-b01',
  );
  final TerminalCompatibilitySourcePin xterm = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) => pin.id == 'xterm-411',
  );
  final TerminalCompatibilitySourcePin iterm = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) =>
        pin.id == 'iterm2-escape-codes-2026-09-07',
  );
  _expect(
    ecma.artifactBytes == 1607865 &&
        ecma.artifactSha256 ==
            '9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450' &&
        dec.artifactBytes == 3378497 &&
        dec.artifactSha256 ==
            '440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514' &&
        iterm.artifactBytes == 31258 &&
        iterm.artifactSha256 ==
            'b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98' &&
        xterm.artifactBytes == 1633400 &&
        xterm.documentPath == 'xterm-411/ctlseqs.ms' &&
        xterm.documentSha256 ==
            '69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349' &&
        inventory.machineLine() ==
            'TERMINAL_COMPATIBILITY_INVENTORY_CHECK version=1 revision=2 '
                'sources=4 records=260 implemented=85 partial=19 '
                'safe_ignore=9 unsupported=147',
    'primary source pins and content-free summary remain exact',
  );
  _expectThrows<UnsupportedError>(
    () => inventory.records.add(inventory.records.first),
    'record collection is immutable',
  );
  _expectThrows<UnsupportedError>(
    () => kinds[TerminalCompatibilitySelectorKind.c0] = 9,
    'selector counts are immutable',
  );
}

void _testGeneratedArtifactsAreFresh() {
  final File inventoryFile = File(defaultTerminalCompatibilityInventoryPath);
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        inventoryFile,
        repositoryRoot: Directory.current,
      );
  _expect(
    inventory_generator.terminalCompatibilityInventoryIsFresh(inventoryFile),
    'checked-in inventory matches its product-derived generator',
  );
  _expect(
    summary_generator.terminalCompatibilitySummaryIsFresh(
      File(summary_generator.defaultTerminalCompatibilitySummaryPath),
      inventory,
    ),
    'checked-in human-readable summary matches the inventory',
  );

  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-compatibility-generation-',
  );
  try {
    final File missing = File.fromUri(temporary.uri.resolve('missing.json'));
    final File stale = File.fromUri(temporary.uri.resolve('stale.json'))
      ..writeAsStringSync('{}\n');
    final File exact = File.fromUri(temporary.uri.resolve('exact.json'))
      ..writeAsStringSync(
        inventory_generator.generateTerminalCompatibilityInventorySource(),
      );
    _expect(
      !inventory_generator.terminalCompatibilityInventoryIsFresh(missing) &&
          !inventory_generator.terminalCompatibilityInventoryIsFresh(stale) &&
          inventory_generator.terminalCompatibilityInventoryIsFresh(exact),
      'inventory freshness rejects missing/stale output and accepts exact output',
    );

    final File summaryMissing = File.fromUri(
      temporary.uri.resolve('missing.md'),
    );
    final File summaryStale = File.fromUri(temporary.uri.resolve('stale.md'))
      ..writeAsStringSync('stale\n');
    final File summaryExact = File.fromUri(temporary.uri.resolve('exact.md'))
      ..writeAsStringSync(
        summary_generator.generateTerminalCompatibilitySummary(inventory),
      );
    _expect(
      !summary_generator.terminalCompatibilitySummaryIsFresh(
            summaryMissing,
            inventory,
          ) &&
          !summary_generator.terminalCompatibilitySummaryIsFresh(
            summaryStale,
            inventory,
          ) &&
          summary_generator.terminalCompatibilitySummaryIsFresh(
            summaryExact,
            inventory,
          ),
      'summary freshness rejects missing/stale output and accepts exact output',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _testImplementationSurfaceReconciliation() {
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(defaultTerminalCompatibilityInventoryPath),
        repositoryRoot: Directory.current,
      );
  final File manifest = File(defaultTerminalImplementationSurfacePath);
  _expect(
    inventory.reconcileImplementationSurface(manifest) ==
        'TERMINAL_COMPATIBILITY_RECONCILIATION_PASS implementation=104 '
            'safe_ignore_families=4',
    'all product declarations and safe-ignore families reconcile exactly',
  );

  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-compatibility-reconciliation-',
  );
  try {
    final File drifted = File.fromUri(temporary.uri.resolve('drifted.json'))
      ..writeAsStringSync(
        manifest.readAsStringSync().replaceFirst(
          '"key": "c0:7"',
          '"key": "c0:6"',
        ),
      );
    _expectThrowsInventory(
      () => inventory.reconcileImplementationSurface(drifted),
      'implementation reconciliation differs',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _testSchemaRejectsMalformedRecords() {
  final String fixture = File(defaultTerminalCompatibilityInventoryPath)
      .readAsStringSync();
  _expectInvalid(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    'unsupported inventory version',
  );
  _expectInvalid(
    fixture.replaceFirst('"records": [', '"unexpected": true, "records": ['),
    'root keys differ',
  );
  _expectInvalid(
    fixture.replaceFirst(
      '9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450',
      'not-a-sha256',
    ),
    'artifact hash is invalid',
  );
  _expectInvalid(
    fixture.replaceFirst(
      'lib/src/terminal_core/terminal_screen_parser_sink.dart#semantic-dispatch',
      '../terminal_screen_parser_sink.dart#dispatchDcs',
    ),
    'unsafe path',
  );
  _expectInvalid(
    fixture.replaceFirst('"support": "partial"', '"support": "unknown"'),
    'unknown support',
  );
  _expectInvalid(
    fixture.replaceFirst('"source": "xterm-411"', '"source": "missing-source"'),
    'unknown source',
  );
  _expectInvalid(
    fixture.replaceFirst(
      '"support": "unsupported",\n      "disposition": "reject"',
      '"support": "unsupported",\n      "disposition": "execute"',
    ),
    'unsupported support requires reject disposition',
  );
}

void _testSelectorBoundsAndTaxonomy() {
  final String fixture = File(defaultTerminalCompatibilityInventoryPath)
      .readAsStringSync();
  _expectInvalid(
    fixture.replaceFirst(
      '"kind": "c0",\n        "code": 7',
      '"kind": "c0",\n        "code": 32',
    ),
    'outside the c0 range',
  );
  _expectInvalid(
    fixture.replaceFirst('"id": "ecma48:c1:nel"', '"id": "ecma48:c0:nel"'),
    'selector kind differs',
  );
  _expectInvalid(
    fixture.replaceFirst(
      '"private": true,\n        "number": 2004',
      '"private": true,\n        "number": 65536',
    ),
    'outside 0..65535',
  );
  _expectInvalid(
    fixture.replaceFirst(
      '"intermediates": [\n          36\n        ],\n        "finalByte": 112',
      '"intermediates": [\n          48\n        ],\n        "finalByte": 112',
    ),
    'outside 32..47',
  );
}

void _expectThrowsInventory(void Function() body, String messagePart) {
  try {
    body();
  } on TerminalCompatibilityInventoryException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'inventory operation failed for the expected reason: $messagePart; $error',
    );
    return;
  }
  throw StateError(
    'test failed: inventory operation was accepted: $messagePart',
  );
}

void _expectInvalid(String source, String messagePart) {
  try {
    TerminalCompatibilityInventory.parse(
      source,
      repositoryRoot: Directory.current,
    );
  } on TerminalCompatibilityInventoryException catch (error) {
    _expect(
      error.message.contains(messagePart),
      'invalid fixture failed for the expected reason: $messagePart; $error',
    );
    return;
  }
  throw StateError('test failed: invalid fixture was accepted: $messagePart');
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
