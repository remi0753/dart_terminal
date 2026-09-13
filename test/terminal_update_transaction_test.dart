import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_terminal/dart_terminal.dart';

var _failures = 0;

Future<void> main() => runTerminalUpdateTransactionTests();

Future<void> runTerminalUpdateTransactionTests() async {
  _testCandidatePolicy();
  _testCandidatePolicyFailures();
  _testArchivePolicy();
  _testZipInventoryPolicy();
  _testJournalCodec();
  await _testOfflineArchiveDownloader();
  await _testSuccessfulInstallAndAcknowledgement();
  await _testExplicitRollback();
  await _testInstallFaultRecovery();
  await _testRecoveryFaultIdempotence();
  await _testLocalStorageBoundary();
  if (_failures != 0) {
    throw StateError('$_failures terminal update transaction test(s) failed');
  }
}

void _testCandidatePolicy() {
  _test(
    'candidate policy accepts the exact signed Universal bundle contract',
    () {
      final TerminalUpdateVerifiedCandidate candidate =
          const TerminalUpdateCandidatePolicy().validate(
            inspection: _inspection(),
            release: _release(),
            expectedTeamIdentifier: 'ABCDEF1234',
          );
      _expect(
        candidate.identity.version == '0.2.0' &&
            candidate.identity.build == 2 &&
            candidate.identity.archiveSha256 == _hash('b'),
        'verified candidate identity differs',
      );
    },
  );
}

void _testCandidatePolicyFailures() {
  final TerminalUpdateCandidateInspection baseline = _inspection();
  final List<TerminalUpdateCandidateInspection> invalid =
      <TerminalUpdateCandidateInspection>[
        _inspection(rootEntries: const <String>['DartTerminal.app', 'extra']),
        _inspection(entryCount: 0),
        _inspection(hasUnsupportedEntry: true),
        _inspection(hasSymbolicLink: true),
        _inspection(hasHardLink: true),
        _inspection(hasCaseFoldedAlias: true),
        _inspection(
          infoPlist: <String, Object?>{
            ...baseline.infoPlist,
            'CFBundleIdentifier': 'dev.example',
          },
        ),
        _inspection(
          infoPlist: <String, Object?>{
            ...baseline.infoPlist,
            'CFBundleShortVersionString': '0.2.1',
          },
        ),
        _inspection(
          runtimeManifest: <String, Object?>{
            ...baseline.runtimeManifest,
            'runtimeMode': 'developer-jit',
          },
        ),
        _inspection(
          runtimeManifest: <String, Object?>{
            ...baseline.runtimeManifest,
            'architectures': <String>['arm64'],
          },
        ),
        _inspection(
          signature: TerminalUpdateCodeSignatureEvidence(
            teamIdentifier: 'ABCDEF1234',
            developerId: false,
            hardenedRuntime: true,
            secureTimestamp: true,
            stapled: true,
            gatekeeperAccepted: true,
          ),
        ),
      ];
  for (final TerminalUpdateCandidateInspection inspection in invalid) {
    _expectThrows(
      () => const TerminalUpdateCandidatePolicy().validate(
        inspection: inspection,
        release: _release(),
        expectedTeamIdentifier: 'ABCDEF1234',
      ),
    );
  }
  _test('candidate policy rejects structural and code identity drift', () {});
}

void _testArchivePolicy() {
  _test(
    'archive policy binds response, size, and digest to signed metadata',
    () {
      const TerminalUpdateArchivePolicy().validate(
        release: _release(),
        statusCode: 200,
        redirected: false,
        declaredLength: 4,
        actualLength: 4,
        actualSha256: _hash('b'),
      );
      for (final ({
            int status,
            bool redirect,
            int? declared,
            int actual,
            String hash,
          })
          value
          in <
            ({
              int status,
              bool redirect,
              int? declared,
              int actual,
              String hash,
            })
          >[
            (
              status: 302,
              redirect: true,
              declared: 4,
              actual: 4,
              hash: _hash('b'),
            ),
            (
              status: 500,
              redirect: false,
              declared: 4,
              actual: 4,
              hash: _hash('b'),
            ),
            (
              status: 200,
              redirect: false,
              declared: 5,
              actual: 4,
              hash: _hash('b'),
            ),
            (
              status: 200,
              redirect: false,
              declared: 4,
              actual: 3,
              hash: _hash('b'),
            ),
            (
              status: 200,
              redirect: false,
              declared: 4,
              actual: 4,
              hash: _hash('c'),
            ),
          ]) {
        _expectThrows(
          () => const TerminalUpdateArchivePolicy().validate(
            release: _release(),
            statusCode: value.status,
            redirected: value.redirect,
            declaredLength: value.declared,
            actualLength: value.actual,
            actualSha256: value.hash,
          ),
        );
      }
      _expectThrows(
        () => const TerminalUpdateArchivePolicy().validate(
          release: _release(),
          timedOut: true,
          statusCode: 200,
          redirected: false,
          declaredLength: 4,
          actualLength: 4,
          actualSha256: _hash('b'),
        ),
      );
      _expectThrows(
        () => const TerminalUpdateArchivePolicy().validate(
          release: _release(),
          networkFailed: true,
          statusCode: 200,
          redirected: false,
          declaredLength: 4,
          actualLength: 4,
          actualSha256: _hash('b'),
        ),
      );
    },
  );
}

void _testZipInventoryPolicy() {
  _test('ZIP inventory rejects traversal, aliases, and extra roots', () {
    const TerminalUpdateZipInventoryPolicy policy =
        TerminalUpdateZipInventoryPolicy();
    policy.validate(const <String>[
      'DartTerminal.app/',
      'DartTerminal.app/Contents/',
      'DartTerminal.app/Contents/Info.plist',
    ]);
    for (final List<String> entries in <List<String>>[
      <String>['../DartTerminal.app/Contents/Info.plist'],
      <String>['/DartTerminal.app/Contents/Info.plist'],
      <String>['DartTerminal.app\\Contents\\Info.plist'],
      <String>['DartTerminal.app/../escape'],
      <String>['DartTerminal.app/Contents', 'dartterminal.app/contents'],
      <String>['DartTerminal.app/Contents', 'extra/file'],
      <String>[],
    ]) {
      _expectThrows(() => policy.validate(entries));
    }
  });
}

void _testJournalCodec() {
  _test('journal codec round-trips exact content-free state', () {
    const TerminalUpdateTransactionJournalCodec codec =
        TerminalUpdateTransactionJournalCodec();
    final TerminalUpdateTransactionJournal journal = _journal(
      TerminalUpdateTransactionPhase.awaitingHealth,
    );
    final List<int> bytes = codec.encode(journal);
    final TerminalUpdateTransactionJournal parsed = codec.parse(bytes);
    final String source = utf8.decode(bytes);
    _expect(
      parsed.transactionId == journal.transactionId &&
          parsed.phase == TerminalUpdateTransactionPhase.awaitingHealth &&
          parsed.candidate.build == 2 &&
          source.endsWith('\n') &&
          !source.contains('/Users/') &&
          !source.contains('archive_url') &&
          !source.contains('command'),
      'journal round-trip or privacy boundary differs',
    );
    final Map<String, Object?> decoded =
        jsonDecode(source) as Map<String, Object?>;
    decoded['unknown'] = true;
    _expectThrows(() => codec.parse(utf8.encode('${jsonEncode(decoded)}\n')));
    _expectThrows(() => codec.parse(<int>[...bytes, 0x0a]));
    decoded.remove('unknown');
    decoded['current_name'] = '/Applications/DartTerminal.app';
    _expectThrows(() => codec.parse(utf8.encode('${jsonEncode(decoded)}\n')));
  });
}

Future<void> _testOfflineArchiveDownloader() async {
  await _testAsync(
    'offline archive adapter streams exact bytes and cleans failure',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dart-terminal-offline-archive-test-',
      );
      try {
        final File source = File('${root.path}/source.zip');
        await source.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
        const String digest =
            '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';
        final TerminalFileUpdateArchiveDownloader downloader =
            TerminalFileUpdateArchiveDownloader(source: source);
        final File accepted = File('${root.path}/accepted.zip');
        await downloader.download(
          release: _release(archiveSha256: digest),
          destination: accepted,
        );
        _expect(
          accepted.readAsBytesSync().join(',') == '1,2,3,4',
          'offline archive bytes differ',
        );
        final File rejected = File('${root.path}/rejected.zip');
        await _expectThrowsAsync(
          () => downloader.download(
            release: _release(archiveSha256: _hash('c')),
            destination: rejected,
          ),
        );
        _expect(!rejected.existsSync(), 'failed offline archive was retained');
        final File timedOut = File('${root.path}/timed-out.zip');
        await _expectThrowsAsync(
          () =>
              TerminalFileUpdateArchiveDownloader(
                source: source,
                timeout: Duration.zero,
              ).download(
                release: _release(archiveSha256: digest),
                destination: timedOut,
              ),
        );
        _expect(!timedOut.existsSync(), 'timed-out archive was retained');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> _testSuccessfulInstallAndAcknowledgement() async {
  await _testAsync(
    'install waits for one exact health token and commits',
    () async {
      final _MemoryStorage storage = _MemoryStorage.seeded();
      final TerminalUpdateTransactionCoordinator coordinator =
          TerminalUpdateTransactionCoordinator(
            storage: storage,
            random: Random(1),
          );
      final String token = await coordinator.install(
        candidate: _candidate(),
        previous: _previous,
        feedSequence: 7,
      );
      _expect(
        storage.apps[terminalUpdateApplicationName] == _next &&
            storage.apps[terminalUpdateBackupName] == _previous &&
            !storage.apps.containsKey(terminalUpdateCandidateName) &&
            storage.phase == TerminalUpdateTransactionPhase.awaitingHealth,
        'install topology before health differs',
      );
      await _expectThrowsAsync(
        () =>
            coordinator.acknowledgeHealth(List<String>.filled(32, '0').join()),
      );
      await coordinator.acknowledgeHealth(token);
      _expect(
        storage.phase == TerminalUpdateTransactionPhase.committed &&
            storage.apps.length == 2,
        'health acknowledgement did not retain one bounded backup',
      );
      await _expectThrowsAsync(() => coordinator.acknowledgeHealth(token));
    },
  );
}

Future<void> _testExplicitRollback() async {
  await _testAsync(
    'explicit rollback restores the verified last-good app',
    () async {
      final _MemoryStorage storage = _MemoryStorage.seeded();
      final TerminalUpdateTransactionCoordinator coordinator =
          TerminalUpdateTransactionCoordinator(
            storage: storage,
            random: Random(2),
          );
      final String token = await coordinator.install(
        candidate: _candidate(),
        previous: _previous,
        feedSequence: 8,
      );
      await coordinator.acknowledgeHealth(token);
      await coordinator.rollback(token);
      await coordinator.recover();
      _expect(
        storage.apps.length == 1 &&
            storage.apps[terminalUpdateApplicationName] == _previous &&
            storage.phase == TerminalUpdateTransactionPhase.rolledBack,
        'explicit rollback did not converge idempotently',
      );
    },
  );
}

Future<void> _testInstallFaultRecovery() async {
  await _testAsync(
    'every install storage fault recovers verified last-good',
    () async {
      for (var failAt = 1; failAt <= 14; failAt++) {
        final _MemoryStorage storage = _MemoryStorage.seeded()..failAt = failAt;
        final TerminalUpdateTransactionCoordinator coordinator =
            TerminalUpdateTransactionCoordinator(
              storage: storage,
              random: Random(3),
            );
        try {
          await coordinator.install(
            candidate: _candidate(),
            previous: _previous,
            feedSequence: 9,
          );
        } on _InjectedFailure {
          // Recovery may itself be interrupted by the same injected boundary.
        }
        storage.failAt = null;
        await coordinator.recover();
        if (storage.phase == TerminalUpdateTransactionPhase.awaitingHealth) {
          await coordinator.recover();
        }
        final bool preJournalFailure = storage.journal == null;
        _expect(
          storage.apps[terminalUpdateApplicationName] == _previous &&
              !storage.apps.containsKey(terminalUpdateBackupName) &&
              (preJournalFailure
                  ? storage.apps[terminalUpdateCandidateName] == _next
                  : !storage.apps.containsKey(terminalUpdateCandidateName)),
          'fault $failAt did not converge to one last-good current app',
        );
      }
    },
  );
}

Future<void> _testRecoveryFaultIdempotence() async {
  await _testAsync('repeated interrupted recovery is idempotent', () async {
    for (var failAt = 1; failAt <= 10; failAt++) {
      final _MemoryStorage storage = _MemoryStorage.awaitingHealth()
        ..failAt = failAt;
      final TerminalUpdateTransactionCoordinator coordinator =
          TerminalUpdateTransactionCoordinator(storage: storage);
      try {
        await coordinator.recover();
      } on _InjectedFailure {
        // The next launch retries from the durable journal and observed paths.
      }
      storage.failAt = null;
      await coordinator.recover();
      await coordinator.recover();
      _expect(
        storage.apps.length == 1 &&
            storage.apps[terminalUpdateApplicationName] == _previous &&
            storage.phase == TerminalUpdateTransactionPhase.rolledBack,
        'recovery fault $failAt left an ambiguous topology',
      );
    }
  });
}

Future<void> _testLocalStorageBoundary() async {
  await _testAsync(
    'local storage uses fixed sibling names and atomic journal',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'dart-terminal-update-storage-test-',
      );
      try {
        await Directory('${root.path}/$terminalUpdateApplicationName').create();
        await Directory('${root.path}/$terminalUpdateCandidateName').create();
        final TerminalLocalUpdateTransactionStorage storage =
            TerminalLocalUpdateTransactionStorage(
              installDirectory: root,
              verifyBundle: (
                Directory application,
                TerminalUpdateInstalledIdentity identity,
              ) async => application.existsSync(),
            );
        final List<int> journal = const TerminalUpdateTransactionJournalCodec()
            .encode(_journal(TerminalUpdateTransactionPhase.prepared));
        await storage.writeJournal(journal);
        await storage.writeJournal(
          const TerminalUpdateTransactionJournalCodec().encode(
            _journal(TerminalUpdateTransactionPhase.backupMoved),
          ),
        );
        _expect(
          const TerminalUpdateTransactionJournalCodec()
                      .parse((await storage.readJournal())!)
                      .phase ==
                  TerminalUpdateTransactionPhase.backupMoved &&
              !File('${root.path}/$terminalUpdateJournalName.new').existsSync(),
          'local atomic journal differs or leaked a temporary file',
        );
        await storage.move(
          terminalUpdateApplicationName,
          terminalUpdateBackupName,
        );
        await storage.remove(terminalUpdateBackupName);
        _expect(
          !Directory('${root.path}/$terminalUpdateBackupName').existsSync(),
          'local fixed-name move/remove failed',
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

final TerminalUpdateInstalledIdentity _previous =
    TerminalUpdateInstalledIdentity(
      version: '0.1.0',
      build: 1,
      archiveSha256: _hash('a'),
    );

final TerminalUpdateInstalledIdentity _next = TerminalUpdateInstalledIdentity(
  version: '0.2.0',
  build: 2,
  archiveSha256: _hash('b'),
);

TerminalUpdateVerifiedCandidate _candidate() =>
    const TerminalUpdateCandidatePolicy().validate(
      inspection: _inspection(),
      release: _release(),
      expectedTeamIdentifier: 'ABCDEF1234',
    );

TerminalUpdateRelease _release({String? archiveSha256}) =>
    TerminalUpdateRelease(
      version: TerminalSemanticVersion.parse('0.2.0'),
      build: 2,
      minimumMacos: const TerminalMacosVersion(14, 0),
      archiveUrl: Uri.parse('https://updates.example.test/DartTerminal.zip'),
      archiveSize: 4,
      archiveSha256: archiveSha256 ?? _hash('b'),
      releaseNotes: const <String>['Verified update.'],
    );

TerminalUpdateCandidateInspection _inspection({
  List<String> rootEntries = const <String>[terminalUpdateApplicationName],
  int entryCount = 12,
  bool hasUnsupportedEntry = false,
  bool hasSymbolicLink = false,
  bool hasHardLink = false,
  bool hasCaseFoldedAlias = false,
  Map<String, Object?>? infoPlist,
  Map<String, Object?>? runtimeManifest,
  TerminalUpdateCodeSignatureEvidence? signature,
}) => TerminalUpdateCandidateInspection(
  rootEntries: rootEntries,
  entryCount: entryCount,
  hasUnsupportedEntry: hasUnsupportedEntry,
  hasSymbolicLink: hasSymbolicLink,
  hasHardLink: hasHardLink,
  hasCaseFoldedAlias: hasCaseFoldedAlias,
  infoPlist:
      infoPlist ??
      <String, Object?>{
        'CFBundleIdentifier': terminalUpdateProduct,
        'CFBundleShortVersionString': '0.2.0',
        'CFBundlePackageType': 'APPL',
        'CFBundleExecutable': 'dart_terminal',
      },
  runtimeManifest:
      runtimeManifest ??
      <String, Object?>{
        'schemaVersion': 2,
        'runtimeMode': 'release-aot',
        'bundleIdentifier': terminalUpdateProduct,
        'architectures': <String>['arm64', 'x86_64'],
        'codePaths': terminalUpdateCodePaths,
        'applicationContract': <String, Object?>{
          'bundleIdentifier': terminalUpdateProduct,
          'runtimeMode': 'release-aot',
          'executable': 'dart_terminal',
        },
      },
  signature:
      signature ??
      TerminalUpdateCodeSignatureEvidence(
        teamIdentifier: 'ABCDEF1234',
        developerId: true,
        hardenedRuntime: true,
        secureTimestamp: true,
        stapled: true,
        gatekeeperAccepted: true,
      ),
);

TerminalUpdateTransactionJournal _journal(
  TerminalUpdateTransactionPhase phase,
) => TerminalUpdateTransactionJournal(
  transactionId: '0123456789abcdef0123456789abcdef',
  phase: phase,
  feedSequence: 7,
  previous: _previous,
  candidate: _next,
);

final class _MemoryStorage implements TerminalUpdateTransactionStorage {
  _MemoryStorage.seeded()
    : apps = <String, TerminalUpdateInstalledIdentity>{
        terminalUpdateApplicationName: _previous,
        terminalUpdateCandidateName: _next,
      };

  _MemoryStorage.awaitingHealth()
    : apps = <String, TerminalUpdateInstalledIdentity>{
        terminalUpdateApplicationName: _next,
        terminalUpdateBackupName: _previous,
      },
      journal = const TerminalUpdateTransactionJournalCodec().encode(
        _journal(TerminalUpdateTransactionPhase.awaitingHealth),
      );

  final Map<String, TerminalUpdateInstalledIdentity> apps;
  List<int>? journal;
  int calls = 0;
  int? failAt;

  TerminalUpdateTransactionPhase? get phase => journal == null
      ? null
      : const TerminalUpdateTransactionJournalCodec().parse(journal!).phase;

  void _boundary() {
    calls++;
    if (calls == failAt) throw const _InjectedFailure();
  }

  @override
  Future<bool> exists(String name) async {
    _boundary();
    return apps.containsKey(name);
  }

  @override
  Future<bool> isVerifiedApplication(
    String name,
    TerminalUpdateInstalledIdentity identity,
  ) async {
    _boundary();
    final TerminalUpdateInstalledIdentity? value = apps[name];
    return value?.version == identity.version &&
        value?.build == identity.build &&
        value?.archiveSha256 == identity.archiveSha256;
  }

  @override
  Future<void> move(String sourceName, String destinationName) async {
    _boundary();
    if (!apps.containsKey(sourceName) || apps.containsKey(destinationName)) {
      throw StateError('invalid fake move');
    }
    apps[destinationName] = apps.remove(sourceName)!;
  }

  @override
  Future<void> remove(String name) async {
    _boundary();
    apps.remove(name);
  }

  @override
  Future<List<int>?> readJournal() async {
    _boundary();
    return journal == null ? null : List<int>.of(journal!);
  }

  @override
  Future<void> writeJournal(List<int> bytes) async {
    _boundary();
    journal = List<int>.of(bytes);
  }
}

final class _InjectedFailure implements Exception {
  const _InjectedFailure();
}

String _hash(String character) => List<String>.filled(64, character).join();

void _test(String name, void Function() body) {
  try {
    body();
    stdout.writeln('PASS $name');
  } catch (error) {
    _failures++;
    stderr.writeln('FAIL $name: $error');
  }
}

Future<void> _testAsync(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } catch (error) {
    _failures++;
    stderr.writeln('FAIL $name: $error');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows(void Function() body) {
  try {
    body();
  } on TerminalUpdateTransactionException {
    return;
  }
  throw StateError('expected TerminalUpdateTransactionException');
}

Future<void> _expectThrowsAsync(Future<void> Function() body) async {
  try {
    await body();
  } on TerminalUpdateTransactionException {
    return;
  }
  throw StateError('expected TerminalUpdateTransactionException');
}
