import 'dart:io';

import '../tool/terminal_compatibility_inventory.dart';

void main() => runTerminalCompatibilityInventoryTests();

void runTerminalCompatibilityInventoryTests() {
  _testPinnedFoundationInventory();
  _testSchemaRejectsMalformedRecords();
  _testSelectorBoundsAndTaxonomy();
}

void _testPinnedFoundationInventory() {
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
        inventory.inventoryRevision == 1 &&
        inventory.scope == 'schema-foundation' &&
        inventory.sourcePins.length == 3 &&
        inventory.records.length == 10 &&
        TerminalCompatibilitySelectorKind.values.every(
          (TerminalCompatibilitySelectorKind kind) => kinds[kind] == 1,
        ) &&
        support[TerminalCompatibilitySupport.implemented] == 5 &&
        support[TerminalCompatibilitySupport.partial] == 1 &&
        support[TerminalCompatibilitySupport.safeIgnore] == 4 &&
        support[TerminalCompatibilitySupport.unsupported] == 0,
    'foundation inventory covers every selector kind with exact totals',
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
  _expect(
    ecma.artifactBytes == 1607865 &&
        ecma.artifactSha256 ==
            '9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450' &&
        dec.artifactBytes == 3378497 &&
        dec.artifactSha256 ==
            '440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514' &&
        xterm.artifactBytes == 1633400 &&
        xterm.documentPath == 'xterm-411/ctlseqs.ms' &&
        xterm.documentSha256 ==
            '69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349' &&
        inventory.machineLine() ==
            'TERMINAL_COMPATIBILITY_INVENTORY_CHECK version=1 revision=1 '
                'sources=3 records=10 implemented=5 partial=1 safe_ignore=4 '
                'unsupported=0',
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
      'lib/src/terminal_core/terminal_screen_parser_sink.dart#dispatchDcs',
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
    fixture.replaceFirst('"id": "ecma48:c1:ind"', '"id": "ecma48:c0:ind"'),
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
      '"intermediates": [36],\n        "finalByte": 113',
      '"intermediates": [48],\n        "finalByte": 113',
    ),
    'outside 32..47',
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
