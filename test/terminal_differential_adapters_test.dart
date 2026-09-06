import 'dart:io';

import '../tool/terminal_differential_adapters.dart';
import '../tool/terminal_differential_sha256.dart';

void main() => runTerminalDifferentialAdapterTests();

void runTerminalDifferentialAdapterTests() {
  _testPinnedCatalogAndSelfTestEvidence();
  _testCatalogValidation();
  _testSelfTestLedgerValidation();
  _testSha256Implementation();
}

void _testPinnedCatalogAndSelfTestEvidence() {
  final Directory repositoryRoot = Directory.current.absolute;
  final TerminalDifferentialBackendCatalog catalog =
      TerminalDifferentialBackendCatalog.load(
        File(defaultTerminalDifferentialBackendsPath),
        repositoryRoot: repositoryRoot,
      );
  final TerminalDifferentialSelfTestLedger ledger =
      TerminalDifferentialSelfTestLedger.load(
        File(defaultTerminalDifferentialSelfTestsPath),
        repositoryRoot: repositoryRoot,
        catalog: catalog,
      );
  _expect(
    catalog.version == 1 &&
        catalog.profiles.map((profile) => profile.product).join(',') ==
            'ghostty,kitty,xterm' &&
        catalog.profiles.every((profile) => profile.supportFiles.isNotEmpty),
    'catalog pins all comparator products and support files',
  );
  _expect(
    ledger.version == 1 &&
        ledger.captures.length == 3 &&
        ledger.captures.every((capture) => capture.status == 'passed') &&
        ledger.captures
                .singleWhere(
                  (capture) => capture.profileId.startsWith('ghostty-'),
                )
                .automationStatus ==
            'activation-unavailable' &&
        ledger.captures
            .where((capture) => !capture.profileId.startsWith('ghostty-'))
            .every((capture) => capture.automationStatus == 'passed'),
    'ledger preserves three genuine captures and current automation status',
  );
}

void _testCatalogValidation() {
  final Directory repositoryRoot = Directory.current.absolute;
  final String fixture = File(defaultTerminalDifferentialBackendsPath)
      .readAsStringSync();
  _expectCatalogFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    repositoryRoot,
    'unsupported backend catalog version',
  );
  _expectCatalogFailure(
    fixture.replaceFirst('"backends": [', '"unknown": true, "backends": ['),
    repositoryRoot,
    'catalog keys differ',
  );
  _expectCatalogFailure(
    fixture.replaceFirst('https://github.com/', 'http://github.com/'),
    repositoryRoot,
    'artifact_url must be an HTTPS URL',
  );
  _expectCatalogFailure(
    fixture.replaceFirst(
      'test/corpus/differential/configs/ghostty-query.conf',
      '../ghostty-query.conf',
    ),
    repositoryRoot,
    'config_path is not a safe relative path',
  );
  _expectCatalogFailure(
    fixture.replaceFirst(
      'da0298fb5f13b6cb7b2ae2c21554292f11d802eb648e2f3f26f30a70ae758ca3',
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
    repositoryRoot,
    'config SHA-256 differs',
  );
  _expectCatalogFailure(
    fixture.replaceFirst(
      '7a95183789657f8c877332503c789ccd82df9778dc70b007b99091043a1e5ad7',
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
    repositoryRoot,
    'SHA-256 differs',
  );
}

void _testSelfTestLedgerValidation() {
  final Directory repositoryRoot = Directory.current.absolute;
  final TerminalDifferentialBackendCatalog catalog =
      TerminalDifferentialBackendCatalog.load(
        File(defaultTerminalDifferentialBackendsPath),
        repositoryRoot: repositoryRoot,
      );
  final String fixture = File(defaultTerminalDifferentialSelfTestsPath)
      .readAsStringSync();
  _expectLedgerFailure(
    fixture.replaceFirst('"version": 1', '"version": 2'),
    repositoryRoot,
    catalog,
    'unsupported self-test ledger version',
  );
  _expectLedgerFailure(
    fixture.replaceFirst('"captures": [', '"unknown": true, "captures": ['),
    repositoryRoot,
    catalog,
    'self-test ledger keys differ',
  );
  _expectLedgerFailure(
    fixture.replaceFirst('1b5b3f31681b5b3f312470', '1b5b3f31681b5b3f312471'),
    repositoryRoot,
    catalog,
    'self-test input differs',
  );
  _expectLedgerFailure(
    fixture.replaceFirst('"status": "passed"', '"status": "pending"'),
    repositoryRoot,
    catalog,
    'capture has not passed',
  );
  _expectLedgerFailure(
    fixture.replaceFirst('activation-unavailable', 'unavailable'),
    repositoryRoot,
    catalog,
    'automation status is unknown',
  );
  _expectLedgerFailure(
    fixture.replaceFirst('"captured_on": "2026-09-07"', '"captured_on": "?"'),
    repositoryRoot,
    catalog,
    'captured_on is not a date',
  );
  _expectLedgerFailure(
    fixture.replaceFirst(
      'e19afac078faf37132d59156e919faf1bad64251c12aacd6dee78af325fc28ad',
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
    repositoryRoot,
    catalog,
    'probe SHA-256 differs',
  );
}

void _testSha256Implementation() {
  _expect(
    terminalDifferentialSha256(const <int>[]) ==
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' &&
        terminalDifferentialSha256('abc'.codeUnits) ==
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'bounded in-process SHA-256 matches standard vectors',
  );
}

void _expectCatalogFailure(
  String source,
  Directory repositoryRoot,
  String expectedMessage,
) {
  _expectFailure(
    () => TerminalDifferentialBackendCatalog.parse(
      source,
      repositoryRoot: repositoryRoot,
    ),
    expectedMessage,
  );
}

void _expectLedgerFailure(
  String source,
  Directory repositoryRoot,
  TerminalDifferentialBackendCatalog catalog,
  String expectedMessage,
) {
  _expectFailure(
    () => TerminalDifferentialSelfTestLedger.parse(
      source,
      repositoryRoot: repositoryRoot,
      catalog: catalog,
    ),
    expectedMessage,
  );
}

void _expectFailure(void Function() callback, String expectedMessage) {
  try {
    callback();
  } on TerminalDifferentialAdapterException catch (error) {
    _expect(
      error.message.contains(expectedMessage),
      'validation failure must identify $expectedMessage, got ${error.message}',
    );
    return;
  }
  throw StateError('expected validation failure: $expectedMessage');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
