import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import '../tool/terminal_update_feed.dart';

var _failures = 0;

Future<void> main() => runTerminalUpdateFeedTests();

Future<void> runTerminalUpdateFeedTests() async {
  _testCanonicalFeedAndSelection();
  _testStrictFeedFailures();
  _testSelectionFailures();
  await _testRealEd25519SignatureBoundary();
  await _testAtomicGeneratorAndSecretBoundary();
  if (_failures != 0) {
    throw StateError('$_failures terminal update feed test(s) failed');
  }
}

void _testCanonicalFeedAndSelection() {
  _test('canonical feed round-trips and selects newest compatible release', () {
    final TerminalUpdateFeed feed = _feed();
    final TerminalUpdateFeedCodec codec = const TerminalUpdateFeedCodec();
    final List<int> encoded = codec.encode(feed);
    final TerminalUpdateFeed decoded = codec.parse(
      encoded,
      nowUnixSeconds: 2000000000,
    );
    final TerminalUpdateRelease? selected =
        const TerminalUpdateSelectionPolicy().select(
          feed: decoded,
          highestAcceptedSequence: 40,
          installedBuild: 7,
          installedVersion: '0.1.0',
          installedArchiveSha256: null,
          currentMacos: const TerminalMacosVersion(14, 0),
        );
    _expect(
      utf8
              .decode(encoded)
              .startsWith(
                '{"format":"dart-terminal-update-feed","version":1,'
                '"product":"dev.dart-terminal","channel":"stable",',
              ) &&
          utf8.decode(encoded).endsWith('\n') &&
          selected?.build == 9 &&
          selected?.version.toString() == '0.2.0' &&
          selected?.releaseNotes.single == 'Security and rendering fixes.',
      'canonical feed and selection differ',
    );
  });

  _test('older build is up to date and incompatible latest is skipped', () {
    final TerminalUpdateFeed feed = TerminalUpdateFeed(
      sequence: 41,
      keyId: 'stable-2026',
      expiresUnixSeconds: 2000000100,
      releases: <TerminalUpdateRelease>[
        _release(
          version: '0.3.0',
          build: 10,
          minimumMacos: '15.0',
          hashCharacter: 'c',
        ),
        _release(
          version: '0.2.0',
          build: 9,
          minimumMacos: '14.0',
          hashCharacter: 'b',
        ),
      ],
    );
    final TerminalUpdateSelectionPolicy policy =
        const TerminalUpdateSelectionPolicy();
    _expect(
      policy
              .select(
                feed: feed,
                highestAcceptedSequence: 41,
                installedBuild: 8,
                installedVersion: '0.1.1',
                installedArchiveSha256: null,
                currentMacos: const TerminalMacosVersion(14, 6),
              )
              ?.build ==
          9,
      'compatible fallback release was not selected',
    );
    _expect(
      policy.select(
            feed: feed,
            highestAcceptedSequence: 41,
            installedBuild: 10,
            installedVersion: '0.3.0',
            installedArchiveSha256: _hex('c'),
            currentMacos: const TerminalMacosVersion(15, 0),
          ) ==
          null,
      'current build should be up to date',
    );
  });
}

void _testStrictFeedFailures() {
  final TerminalUpdateFeedCodec codec = const TerminalUpdateFeedCodec();
  final String valid = utf8.decode(codec.encode(_feed()));
  final List<List<int>> invalid = <List<int>>[
    utf8.encode(valid.substring(0, valid.length - 1)),
    utf8.encode('$valid\n'),
    utf8.encode(
      valid.replaceFirst(
        '{"format":"dart-terminal-update-feed","version":1',
        '{"version":1,"format":"dart-terminal-update-feed"',
      ),
    ),
    utf8.encode(
      valid.replaceFirst(
        '"product":"dev.dart-terminal"',
        '"unknown":true,"product":"dev.dart-terminal"',
      ),
    ),
    utf8.encode(valid.replaceFirst('https://', 'http://')),
    utf8.encode(
      valid.replaceFirst(_hex('b'), List<String>.filled(64, 'B').join()),
    ),
    utf8.encode(
      valid.replaceFirst(
        '"expires_unix_seconds":2000000100',
        '"expires_unix_seconds":2000000000',
      ),
    ),
    utf8.encode(
      valid.replaceFirst(
        '"expires_unix_seconds":2000000100',
        '"expires_unix_seconds":2999999999',
      ),
    ),
    <int>[0xff, ...utf8.encode(valid)],
  ];
  _test('noncanonical, unsafe, expired, and malformed feeds fail closed', () {
    for (final List<int> source in invalid) {
      _expectThrows(() => codec.parse(source, nowUnixSeconds: 2000000000));
    }
  });

  _test('release and aggregate bounds fail before encoding', () {
    for (final String version in <String>['1.0', '01.0.0', '1.0.0-beta']) {
      _expectThrows(() => TerminalSemanticVersion.parse(version));
    }
    for (final String note in <String>['unsafe\nline', 'bidi\u202evalue']) {
      _expectThrows(
        () => _release(
          version: '0.2.0',
          build: 9,
          minimumMacos: '14.0',
          hashCharacter: 'b',
          notes: <String>[note],
        ),
      );
    }
    _expectThrows(
      () => TerminalUpdateFeed(
        sequence: 41,
        keyId: 'stable-2026',
        expiresUnixSeconds: 2000000100,
        releases: List<TerminalUpdateRelease>.generate(
          33,
          (int index) => _release(
            version: '1.${32 - index}.0',
            build: 100 - index,
            minimumMacos: '14.0',
            hashCharacter: (index % 10).toString(),
          ),
        ),
      ),
    );
    _expectThrows(
      () => TerminalUpdateFeed(
        sequence: 41,
        keyId: 'stable-2026',
        expiresUnixSeconds: 2000000100,
        releases: <TerminalUpdateRelease>[
          _release(
            version: '0.2.0',
            build: 9,
            minimumMacos: '14.0',
            hashCharacter: 'b',
          ),
          _release(
            version: '0.1.0',
            build: 9,
            minimumMacos: '14.0',
            hashCharacter: 'a',
          ),
        ],
      ),
    );
  });
}

void _testSelectionFailures() {
  _test('replay, downgrade contradiction, and version contradiction fail', () {
    final TerminalUpdateSelectionPolicy policy =
        const TerminalUpdateSelectionPolicy();
    _expectThrows(
      () => policy.select(
        feed: _feed(),
        highestAcceptedSequence: 42,
        installedBuild: 7,
        installedVersion: '0.1.0',
        installedArchiveSha256: null,
        currentMacos: const TerminalMacosVersion(14, 0),
      ),
    );
    final TerminalUpdateFeed versionDowngrade = TerminalUpdateFeed(
      sequence: 42,
      keyId: 'stable-2026',
      expiresUnixSeconds: 2000000100,
      releases: <TerminalUpdateRelease>[
        _release(
          version: '0.0.9',
          build: 10,
          minimumMacos: '14.0',
          hashCharacter: 'd',
        ),
      ],
    );
    _expectThrows(
      () => policy.select(
        feed: versionDowngrade,
        highestAcceptedSequence: 41,
        installedBuild: 8,
        installedVersion: '0.1.1',
        installedArchiveSha256: null,
        currentMacos: const TerminalMacosVersion(14, 0),
      ),
    );
    _expectThrows(
      () => policy.select(
        feed: _feed(),
        highestAcceptedSequence: 41,
        installedBuild: 8,
        installedVersion: '9.9.9',
        installedArchiveSha256: null,
        currentMacos: const TerminalMacosVersion(14, 0),
      ),
    );
    final TerminalUpdateFeed contradiction = TerminalUpdateFeed(
      sequence: 41,
      keyId: 'stable-2026',
      expiresUnixSeconds: 2000000100,
      releases: <TerminalUpdateRelease>[
        _release(
          version: '0.2.0',
          build: 9,
          minimumMacos: '14.0',
          hashCharacter: 'b',
        ),
      ],
    );
    _expectThrows(
      () => policy.select(
        feed: contradiction,
        highestAcceptedSequence: 41,
        installedBuild: 9,
        installedVersion: '0.1.9',
        installedArchiveSha256: _hex('b'),
        currentMacos: const TerminalMacosVersion(14, 0),
      ),
    );
  });
}

Future<void> _testRealEd25519SignatureBoundary() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-update-signature-test-',
  );
  try {
    final File key = File('${temporary.path}/fixture_key');
    await _generateKey(key);
    final TerminalUpdatePinnedKey pinned = TerminalUpdatePinnedKey(
      keyId: 'stable-2026',
      publicKey: _publicKey(File('${key.path}.pub')),
    );
    final List<int> feedBytes = const TerminalUpdateFeedCodec().encode(_feed());
    final List<int> signature = await const TerminalOpenSshUpdateSigner().sign(
      feedBytes: feedBytes,
      signingKeyPath: key.path,
    );
    await _testAsync(
      'real ephemeral Ed25519 signature verifies exact bytes',
      () async {
        final TerminalUpdateFeed verified =
            await const TerminalSignedUpdateFeedVerifier().verify(
              feedBytes: feedBytes,
              signatureBytes: signature,
              pinnedKey: pinned,
              nowUnixSeconds: 2000000000,
            );
        _expect(
          verified.sequence == 41 &&
              ascii.decode(signature).contains('BEGIN SSH SIGNATURE'),
          'verified feed differs',
        );
      },
    );
    await _testAsync(
      'signature, key, namespace, and key-id drift fail closed',
      () async {
        final List<int> changed = List<int>.from(feedBytes);
        final int markerOffset = _indexOf(changed, ascii.encode('Security'));
        _expect(markerOffset >= 0, 'signed marker is absent');
        changed[markerOffset] = ascii.encode('s').single;
        await _expectThrowsAsync(
          () => const TerminalSignedUpdateFeedVerifier().verify(
            feedBytes: changed,
            signatureBytes: signature,
            pinnedKey: pinned,
            nowUnixSeconds: 2000000000,
          ),
        );
        final File other = File('${temporary.path}/other_key');
        await _generateKey(other);
        await _expectThrowsAsync(
          () => const TerminalSignedUpdateFeedVerifier().verify(
            feedBytes: feedBytes,
            signatureBytes: signature,
            pinnedKey: TerminalUpdatePinnedKey(
              keyId: 'stable-2026',
              publicKey: _publicKey(File('${other.path}.pub')),
            ),
            nowUnixSeconds: 2000000000,
          ),
        );
        await _expectThrowsAsync(
          () => const TerminalSignedUpdateFeedVerifier().verify(
            feedBytes: feedBytes,
            signatureBytes: signature,
            pinnedKey: TerminalUpdatePinnedKey(
              keyId: 'other-key',
              publicKey: pinned.publicKey,
            ),
            nowUnixSeconds: 2000000000,
          ),
        );
      },
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> _testAtomicGeneratorAndSecretBoundary() async {
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-update-generator-test-',
  );
  try {
    final File archive = File('${temporary.path}/DartTerminal.zip');
    await archive.writeAsBytes(utf8.encode('immutable archive fixture'));
    final File key = File('${temporary.path}/fixture_key');
    await _generateKey(key);
    final Directory output = Directory('${temporary.path}/published');
    await output.create();
    await File('${output.path}/last-good')
        .writeAsString('preserve until publish');
    final TerminalUpdateFeedGeneratorOptions options =
        TerminalUpdateFeedGeneratorOptions.parse(<String>[
          '--archive=${archive.path}',
          '--archive-url=https://updates.example.invalid/DartTerminal.zip',
          '--version=0.2.0',
          '--build=9',
          '--minimum-macos=14.0',
          '--sequence=41',
          '--expires-unix-seconds=2000000100',
          '--key-id=stable-2026',
          '--public-key=${key.path}.pub',
          '--signing-key=${key.path}',
          '--output-directory=${output.path}',
          '--release-note=Security and rendering fixes.',
        ]);
    await _testAsync(
      'generator signs, self-verifies, and atomically publishes',
      () async {
        await generateTerminalUpdateFeedArtifact(
          options,
          nowUnixSeconds: 2000000000,
        );
        final File feed = File('${output.path}/$terminalUpdateFeedFileName');
        final File signature = File(
          '${output.path}/$terminalUpdateSignatureFileName',
        );
        final TerminalUpdateFeed verified =
            await const TerminalSignedUpdateFeedVerifier().verify(
              feedBytes: await feed.readAsBytes(),
              signatureBytes: await signature.readAsBytes(),
              pinnedKey: TerminalUpdatePinnedKey(
                keyId: 'stable-2026',
                publicKey: _publicKey(File('${key.path}.pub')),
              ),
              nowUnixSeconds: 2000000000,
            );
        final String evidence = await File(
          '${output.path}/$terminalUpdateEvidenceFileName',
        ).readAsString();
        _expect(
          verified.releases.single.archiveSize == await archive.length() &&
              !evidence.contains(key.path) &&
              !evidence.contains('OPENSSH PRIVATE KEY') &&
              !await File('${output.path}/last-good').exists(),
          'generated artifact or secret boundary differs',
        );
      },
    );

    await _testAsync(
      'wrong public key preserves last-good publication',
      () async {
        final File other = File('${temporary.path}/other_key');
        await _generateKey(other);
        await File('${output.path}/marker').writeAsString('last-good');
        final TerminalUpdateFeedGeneratorOptions invalid =
            TerminalUpdateFeedGeneratorOptions.parse(<String>[
              '--archive=${archive.path}',
              '--archive-url=https://updates.example.invalid/DartTerminal.zip',
              '--version=0.2.1',
              '--build=10',
              '--minimum-macos=14.0',
              '--sequence=42',
              '--expires-unix-seconds=2000000100',
              '--key-id=stable-2026',
              '--public-key=${other.path}.pub',
              '--signing-key=${key.path}',
              '--output-directory=${output.path}',
            ]);
        await _expectThrowsAsync(
          () => generateTerminalUpdateFeedArtifact(
            invalid,
            nowUnixSeconds: 2000000000,
          ),
        );
        _expect(
          await File('${output.path}/marker').readAsString() == 'last-good',
          'last-good publication was not preserved',
        );
      },
    );

    _test(
      'generator options reject missing, duplicate, and relative paths',
      () {
        _expectThrows(
          () => TerminalUpdateFeedGeneratorOptions.parse(const <String>[]),
        );
        _expectThrows(
          () => TerminalUpdateFeedGeneratorOptions.parse(<String>[
            '--archive=${archive.path}',
            '--archive=${archive.path}',
          ]),
        );
        _expectThrows(
          () => TerminalUpdateFeedGeneratorOptions.parse(<String>[
            '--archive=relative.zip',
            '--archive-url=https://updates.example.invalid/DartTerminal.zip',
            '--version=0.2.0',
            '--build=9',
            '--minimum-macos=14.0',
            '--sequence=41',
            '--expires-unix-seconds=2000000100',
            '--key-id=stable-2026',
            '--public-key=${key.path}.pub',
            '--signing-key=${key.path}',
            '--output-directory=${output.path}',
          ]),
        );
      },
    );
  } finally {
    await temporary.delete(recursive: true);
  }
}

TerminalUpdateFeed _feed() => TerminalUpdateFeed(
  sequence: 41,
  keyId: 'stable-2026',
  expiresUnixSeconds: 2000000100,
  releases: <TerminalUpdateRelease>[
    _release(
      version: '0.2.0',
      build: 9,
      minimumMacos: '14.0',
      hashCharacter: 'b',
    ),
    _release(
      version: '0.1.1',
      build: 8,
      minimumMacos: '14.0',
      hashCharacter: 'a',
    ),
  ],
);

TerminalUpdateRelease _release({
  required String version,
  required int build,
  required String minimumMacos,
  required String hashCharacter,
  List<String> notes = const <String>['Security and rendering fixes.'],
}) => TerminalUpdateRelease(
  version: TerminalSemanticVersion.parse(version),
  build: build,
  minimumMacos: TerminalMacosVersion.parse(minimumMacos),
  archiveUrl: Uri.parse(
    'https://updates.example.invalid/DartTerminal-$build.zip',
  ),
  archiveSize: 1024 + build,
  archiveSha256: _hex(hashCharacter),
  releaseNotes: notes,
);

String _hex(String value) =>
    List<String>.filled(64, value.toLowerCase()).join();

int _indexOf(List<int> source, List<int> pattern) {
  for (var start = 0; start + pattern.length <= source.length; start++) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset++) {
      if (source[start + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}

Future<void> _generateKey(File key) async {
  final ProcessResult result = await Process.run(
    '/usr/bin/ssh-keygen',
    <String>[
      '-q',
      '-t',
      'ed25519',
      '-N',
      '',
      '-C',
      'fixture-only',
      '-f',
      key.path,
    ],
  );
  if (result.exitCode != 0) {
    throw StateError('ephemeral Ed25519 key generation failed');
  }
}

String _publicKey(File file) {
  final List<String> fields = file.readAsStringSync().trim().split(
    RegExp(r'[ \t]+'),
  );
  return '${fields[0]} ${fields[1]}';
}

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
  } on TerminalUpdateException {
    return;
  }
  throw StateError('expected TerminalUpdateException');
}

Future<void> _expectThrowsAsync(Future<void> Function() body) async {
  try {
    await body();
  } on TerminalUpdateException {
    return;
  }
  throw StateError('expected TerminalUpdateException');
}
