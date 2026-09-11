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
        inventory.inventoryRevision == 5 &&
        inventory.scope == 'complete-baseline' &&
        inventory.sourcePins.length == 12 &&
        inventory.records.length == 270 &&
        kinds[TerminalCompatibilitySelectorKind.c0] == 10 &&
        kinds[TerminalCompatibilitySelectorKind.c1] == 9 &&
        kinds[TerminalCompatibilitySelectorKind.esc] == 35 &&
        kinds[TerminalCompatibilitySelectorKind.csi] == 105 &&
        kinds[TerminalCompatibilitySelectorKind.osc] == 15 &&
        kinds[TerminalCompatibilitySelectorKind.dcs] == 8 &&
        kinds[TerminalCompatibilitySelectorKind.sos] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.pm] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.apc] == 1 &&
        kinds[TerminalCompatibilitySelectorKind.mode] == 85 &&
        support[TerminalCompatibilitySupport.implemented] == 96 &&
        support[TerminalCompatibilitySupport.partial] == 20 &&
        support[TerminalCompatibilitySupport.safeIgnore] == 9 &&
        support[TerminalCompatibilitySupport.unsupported] == 145,
    'complete baseline covers every selector kind with exact totals',
  );
  final TerminalCompatibilitySourcePin ecma = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) => pin.id == 'ecma-48-5e',
  );
  final TerminalCompatibilitySourcePin contour = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'contour-vt-extensions-05050a1-synchronized-output',
      );
  final TerminalCompatibilitySourcePin contourColor = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'contour-0ad6bdb-color-palette-notifications',
      );
  final TerminalCompatibilitySourcePin contourUnicode = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'contour-terminal-unicode-core-64f5385',
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
  final TerminalCompatibilitySourcePin ghostty = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'ghostty-d4d8f62-semantic-prompt',
      );
  final TerminalCompatibilitySourcePin ghosttyDevice = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'ghostty-d4d8f62-device-status',
      );
  final TerminalCompatibilitySourcePin ghosttySize = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'ghostty-d4d8f62-size-report',
      );
  final TerminalCompatibilitySourcePin kitty = inventory.sourcePins.singleWhere(
    (TerminalCompatibilitySourcePin pin) =>
        pin.id == 'kitty-0-48-2-keyboard-protocol',
  );
  final TerminalCompatibilitySourcePin mintty = inventory.sourcePins
      .singleWhere(
        (TerminalCompatibilitySourcePin pin) =>
            pin.id == 'mintty-ctrlseqs-25c73c7',
      );
  _expect(
    contourColor.artifactBytes == 4845 &&
        contourColor.artifactSha256 ==
            '6ba512529226511adcfee5a4d0f99a9689293e73b3e2d4d5c21afb67f45ba832' &&
        contourUnicode.artifactBytes == 7232 &&
        contourUnicode.artifactSha256 ==
            'f23237de5dd88ec8fee0c8059a6c979ca2eecc3e4c8fdf8ce4c4d86b7a2e47af' &&
        contour.artifactBytes == 5967 &&
        contour.artifactSha256 ==
            '7cb1e9bc9fad9b56d81ebd7d0e8dad423c1b865ce1089d99f2f175239b9dde89' &&
        ecma.artifactBytes == 1607865 &&
        ecma.artifactSha256 ==
            '9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450' &&
        dec.artifactBytes == 3378497 &&
        dec.artifactSha256 ==
            '440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514' &&
        ghostty.artifactBytes == 42962 &&
        ghostty.artifactSha256 ==
            '04935466b4fd8b9e0e41e7d69bb72fc6ff6141111d9274d8bda927dcb41488ff' &&
        ghosttyDevice.artifactBytes == 4808 &&
        ghosttyDevice.artifactSha256 ==
            '244a5aa349845a7780dfff4cd2cda2efa574153774d0655727bf4d22d12f579f' &&
        ghosttySize.artifactBytes == 4250 &&
        ghosttySize.artifactSha256 ==
            '806a5932dd0f6c877902e884b72cc171e27d6d3d1991e97d3dd28217ad61f3ae' &&
        iterm.artifactBytes == 31258 &&
        iterm.artifactSha256 ==
            'b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98' &&
        kitty.artifactBytes == 36641 &&
        kitty.artifactSha256 ==
            'cd452d4f1b5070752499233f8d76455c854d0ec5f2318e38309f835baf2410ce' &&
        mintty.artifactBytes == 264856 &&
        mintty.artifactSha256 ==
            '4144a9212fdc412088d5a094a09d827d729082239c8fbb7ef7b163d13d5d9d0e' &&
        xterm.artifactBytes == 1633400 &&
        xterm.documentPath == 'xterm-411/ctlseqs.ms' &&
        xterm.documentSha256 ==
            '69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349' &&
        inventory.machineLine() ==
            'TERMINAL_COMPATIBILITY_INVENTORY_CHECK version=1 revision=5 '
                'sources=12 records=270 implemented=96 partial=20 '
                'safe_ignore=9 unsupported=145',
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
        'TERMINAL_COMPATIBILITY_RECONCILIATION_PASS implementation=116 '
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
