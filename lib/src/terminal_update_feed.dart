import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String terminalUpdateFeedFormat = 'dart-terminal-update-feed';
const int terminalUpdateFeedVersion = 1;
const String terminalUpdateProduct = 'dev.dart-terminal';
const String terminalUpdateChannel = 'stable';
const String terminalUpdateSignatureNamespace = 'dart-terminal-update-v1';

final class TerminalUpdateException implements Exception {
  const TerminalUpdateException(this.code);

  final String code;

  @override
  String toString() => 'TerminalUpdateException: $code';
}

final class TerminalSemanticVersion
    implements Comparable<TerminalSemanticVersion> {
  const TerminalSemanticVersion(this.major, this.minor, this.patch);

  factory TerminalSemanticVersion.parse(String source) {
    final RegExpMatch? match = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
    ).firstMatch(source);
    if (match == null) {
      throw const TerminalUpdateException('invalid-version');
    }
    final List<int> values = <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
    if (values.any((int value) => value > 0x7fffffff)) {
      throw const TerminalUpdateException('version-component-out-of-range');
    }
    return TerminalSemanticVersion(values[0], values[1], values[2]);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(TerminalSemanticVersion other) {
    final int majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final int minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

final class TerminalMacosVersion implements Comparable<TerminalMacosVersion> {
  const TerminalMacosVersion(this.major, this.minor);

  factory TerminalMacosVersion.parse(String source) {
    final RegExpMatch? match = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
        .firstMatch(source);
    if (match == null) {
      throw const TerminalUpdateException('invalid-minimum-macos');
    }
    final int major = int.parse(match.group(1)!);
    final int minor = int.parse(match.group(2)!);
    if (major > 999 || minor > 999) {
      throw const TerminalUpdateException('minimum-macos-out-of-range');
    }
    return TerminalMacosVersion(major, minor);
  }

  final int major;
  final int minor;

  @override
  int compareTo(TerminalMacosVersion other) {
    final int majorOrder = major.compareTo(other.major);
    return majorOrder != 0 ? majorOrder : minor.compareTo(other.minor);
  }

  @override
  String toString() => '$major.$minor';
}

final class TerminalUpdateRelease {
  TerminalUpdateRelease({
    required this.version,
    required this.build,
    required this.minimumMacos,
    required this.archiveUrl,
    required this.archiveSize,
    required this.archiveSha256,
    required List<String> releaseNotes,
  }) : releaseNotes = List<String>.unmodifiable(releaseNotes) {
    _validate();
  }

  final TerminalSemanticVersion version;
  final int build;
  final TerminalMacosVersion minimumMacos;
  final Uri archiveUrl;
  final int archiveSize;
  final String archiveSha256;
  final List<String> releaseNotes;

  void _validate() {
    _expect(build >= 1 && build <= 0x7fffffff, 'build-out-of-range');
    _expect(
      minimumMacos.compareTo(const TerminalMacosVersion(14, 0)) >= 0,
      'minimum-macos-below-deployment-target',
    );
    _validateArchiveUrl(archiveUrl);
    _expect(
      archiveSize >= 1 && archiveSize <= 1024 * 1024 * 1024,
      'archive-size-out-of-range',
    );
    _expect(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(archiveSha256),
      'invalid-archive-sha256',
    );
    _expect(releaseNotes.length <= 64, 'too-many-release-notes');
    var aggregateBytes = 0;
    for (final String line in releaseNotes) {
      final int length = utf8.encode(line).length;
      aggregateBytes += length;
      _expect(length <= 512, 'release-note-line-too-large');
      _expect(!_hasForbiddenText(line), 'unsafe-release-note');
    }
    _expect(aggregateBytes <= 16 * 1024, 'release-notes-too-large');
  }

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'version': version.toString(),
    'build': build,
    'minimum_macos': minimumMacos.toString(),
    'architecture': 'universal-arm64-x86_64',
    'archive_url': archiveUrl.toString(),
    'archive_size': archiveSize,
    'archive_sha256': archiveSha256,
    'bundle_id': terminalUpdateProduct,
    'release_notes': releaseNotes,
  };
}

final class TerminalUpdateFeed {
  TerminalUpdateFeed({
    required this.sequence,
    required this.keyId,
    required this.expiresUnixSeconds,
    required List<TerminalUpdateRelease> releases,
  }) : releases = List<TerminalUpdateRelease>.unmodifiable(releases) {
    _validate();
  }

  final int sequence;
  final String keyId;
  final int expiresUnixSeconds;
  final List<TerminalUpdateRelease> releases;

  void _validate() {
    _expect(
      sequence >= 1 && sequence <= 0x1fffffffffffff,
      'sequence-out-of-range',
    );
    _expect(_validKeyId(keyId), 'invalid-key-id');
    _expect(
      expiresUnixSeconds >= 1 && expiresUnixSeconds <= 0x1fffffffffffff,
      'expiry-out-of-range',
    );
    _expect(
      releases.isNotEmpty && releases.length <= 32,
      'release-count-out-of-range',
    );
    final Set<int> builds = <int>{};
    final Set<String> versions = <String>{};
    final Set<String> urls = <String>{};
    final Set<String> hashes = <String>{};
    for (var index = 0; index < releases.length; index++) {
      final TerminalUpdateRelease release = releases[index];
      _expect(builds.add(release.build), 'duplicate-build');
      _expect(versions.add(release.version.toString()), 'duplicate-version');
      _expect(urls.add(release.archiveUrl.toString()), 'duplicate-archive-url');
      _expect(hashes.add(release.archiveSha256), 'duplicate-archive-sha256');
      if (index > 0) {
        final TerminalUpdateRelease previous = releases[index - 1];
        _expect(
          previous.build > release.build,
          'releases-not-build-descending',
        );
        _expect(
          previous.version.compareTo(release.version) > 0,
          'releases-not-version-descending',
        );
      }
    }
  }

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'format': terminalUpdateFeedFormat,
    'version': terminalUpdateFeedVersion,
    'product': terminalUpdateProduct,
    'channel': terminalUpdateChannel,
    'sequence': sequence,
    'key_id': keyId,
    'expires_unix_seconds': expiresUnixSeconds,
    'releases': releases
        .map((TerminalUpdateRelease release) => release.toCanonicalJson())
        .toList(growable: false),
  };
}

final class TerminalUpdateFeedCodec {
  const TerminalUpdateFeedCodec();

  static const int maximumFeedBytes = 256 * 1024;
  static const int maximumFutureSeconds = 90 * 24 * 60 * 60;

  Uint8List encode(TerminalUpdateFeed feed) => Uint8List.fromList(
    utf8.encode('${jsonEncode(feed.toCanonicalJson())}\n'),
  );

  TerminalUpdateFeed parse(List<int> bytes, {required int nowUnixSeconds}) {
    _expect(
      bytes.isNotEmpty && bytes.length <= maximumFeedBytes,
      'feed-size-out-of-range',
    );
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const TerminalUpdateException('feed-is-not-utf8');
    }
    _expect(
      source.endsWith('\n') && !source.endsWith('\n\n'),
      'non-canonical-feed-newline',
    );
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const TerminalUpdateException('invalid-feed-json');
    }
    final Map<String, Object?> root = _object(decoded, 'feed-not-object');
    _expectExactKeys(root, const <String>{
      'format',
      'version',
      'product',
      'channel',
      'sequence',
      'key_id',
      'expires_unix_seconds',
      'releases',
    }, 'feed-fields-differ');
    _expect(root['format'] == terminalUpdateFeedFormat, 'feed-format-differs');
    _expect(
      root['version'] == terminalUpdateFeedVersion,
      'feed-version-differs',
    );
    _expect(root['product'] == terminalUpdateProduct, 'feed-product-differs');
    _expect(root['channel'] == terminalUpdateChannel, 'feed-channel-differs');
    final int sequence = _integer(root['sequence'], 'invalid-sequence');
    final String keyId = _string(root['key_id'], 'invalid-key-id');
    final int expires = _integer(
      root['expires_unix_seconds'],
      'invalid-expiry',
    );
    _expect(expires > nowUnixSeconds, 'feed-expired');
    _expect(
      expires - nowUnixSeconds <= maximumFutureSeconds,
      'feed-expiry-too-distant',
    );
    final List<Object?> values = _array(root['releases'], 'releases-not-array');
    final List<TerminalUpdateRelease> releases = <TerminalUpdateRelease>[];
    for (final Object? value in values) {
      final Map<String, Object?> item = _object(value, 'release-not-object');
      _expectExactKeys(item, const <String>{
        'version',
        'build',
        'minimum_macos',
        'architecture',
        'archive_url',
        'archive_size',
        'archive_sha256',
        'bundle_id',
        'release_notes',
      }, 'release-fields-differ');
      _expect(
        item['architecture'] == 'universal-arm64-x86_64',
        'architecture-differs',
      );
      _expect(item['bundle_id'] == terminalUpdateProduct, 'bundle-id-differs');
      final List<Object?> noteValues = _array(
        item['release_notes'],
        'release-notes-not-array',
      );
      releases.add(
        TerminalUpdateRelease(
          version: TerminalSemanticVersion.parse(
            _string(item['version'], 'invalid-version'),
          ),
          build: _integer(item['build'], 'invalid-build'),
          minimumMacos: TerminalMacosVersion.parse(
            _string(item['minimum_macos'], 'invalid-minimum-macos'),
          ),
          archiveUrl: _uri(_string(item['archive_url'], 'invalid-archive-url')),
          archiveSize: _integer(item['archive_size'], 'invalid-archive-size'),
          archiveSha256: _string(
            item['archive_sha256'],
            'invalid-archive-sha256',
          ),
          releaseNotes: noteValues
              .map((Object? note) => _string(note, 'invalid-release-note'))
              .toList(growable: false),
        ),
      );
    }
    final TerminalUpdateFeed feed = TerminalUpdateFeed(
      sequence: sequence,
      keyId: keyId,
      expiresUnixSeconds: expires,
      releases: releases,
    );
    _expect(_bytesEqual(encode(feed), bytes), 'feed-is-not-canonical');
    return feed;
  }
}

final class TerminalUpdatePinnedKey {
  TerminalUpdatePinnedKey({required this.keyId, required String publicKey})
    : publicKey = _canonicalPublicKey(publicKey) {
    _expect(_validKeyId(keyId), 'invalid-key-id');
  }

  final String keyId;
  final String publicKey;
}

abstract interface class TerminalUpdateSignatureVerifier {
  Future<bool> verify({
    required List<int> feedBytes,
    required List<int> signatureBytes,
    required TerminalUpdatePinnedKey pinnedKey,
  });
}

final class TerminalSignedUpdateFeedVerifier {
  const TerminalSignedUpdateFeedVerifier({
    this.codec = const TerminalUpdateFeedCodec(),
    this.signatureVerifier = const TerminalOpenSshUpdateSignatureVerifier(),
  });

  final TerminalUpdateFeedCodec codec;
  final TerminalUpdateSignatureVerifier signatureVerifier;

  Future<TerminalUpdateFeed> verify({
    required List<int> feedBytes,
    required List<int> signatureBytes,
    required TerminalUpdatePinnedKey pinnedKey,
    required int nowUnixSeconds,
  }) async {
    final TerminalUpdateFeed feed = codec.parse(
      feedBytes,
      nowUnixSeconds: nowUnixSeconds,
    );
    _expect(feed.keyId == pinnedKey.keyId, 'feed-key-id-differs');
    _expect(
      await signatureVerifier.verify(
        feedBytes: feedBytes,
        signatureBytes: signatureBytes,
        pinnedKey: pinnedKey,
      ),
      'signature-verification-failed',
    );
    return feed;
  }
}

final class TerminalOpenSshUpdateSignatureVerifier
    implements TerminalUpdateSignatureVerifier {
  const TerminalOpenSshUpdateSignatureVerifier({
    this.executable = '/usr/bin/ssh-keygen',
    this.timeout = const Duration(seconds: 5),
  });

  final String executable;
  final Duration timeout;

  @override
  Future<bool> verify({
    required List<int> feedBytes,
    required List<int> signatureBytes,
    required TerminalUpdatePinnedKey pinnedKey,
  }) async {
    _expect(
      feedBytes.isNotEmpty &&
          feedBytes.length <= TerminalUpdateFeedCodec.maximumFeedBytes,
      'feed-size-out-of-range',
    );
    _validateSshSignature(signatureBytes, pinnedKey);
    final Directory temporary = await Directory.systemTemp.createTemp(
      'dart-terminal-update-verify-',
    );
    try {
      final File allowedSigners = File('${temporary.path}/allowed_signers');
      final File signature = File('${temporary.path}/feed.sig');
      await allowedSigners.writeAsString(
        '${pinnedKey.keyId} ${pinnedKey.publicKey}\n',
        flush: true,
      );
      await signature.writeAsBytes(signatureBytes, flush: true);
      final _CommandOutcome result = await _runBoundedCommand(
        executable,
        <String>[
          '-Y',
          'verify',
          '-f',
          allowedSigners.path,
          '-I',
          pinnedKey.keyId,
          '-n',
          terminalUpdateSignatureNamespace,
          '-s',
          signature.path,
        ],
        input: feedBytes,
        timeout: timeout,
      );
      return result.exitCode == 0 && !result.timedOut && !result.outputOverflow;
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}

final class TerminalOpenSshUpdateSigner {
  const TerminalOpenSshUpdateSigner({
    this.executable = '/usr/bin/ssh-keygen',
    this.timeout = const Duration(seconds: 10),
  });

  final String executable;
  final Duration timeout;

  Future<Uint8List> sign({
    required List<int> feedBytes,
    required String signingKeyPath,
  }) async {
    _expect(
      feedBytes.isNotEmpty &&
          feedBytes.length <= TerminalUpdateFeedCodec.maximumFeedBytes,
      'feed-size-out-of-range',
    );
    _expect(
      signingKeyPath.startsWith('/') && !signingKeyPath.contains('\u0000'),
      'invalid-signing-key-path',
    );
    final Directory temporary = await Directory.systemTemp.createTemp(
      'dart-terminal-update-sign-',
    );
    try {
      final File feed = File('${temporary.path}/feed.json');
      await feed.writeAsBytes(feedBytes, flush: true);
      final _CommandOutcome result = await _runBoundedCommand(
        executable,
        <String>[
          '-Y',
          'sign',
          '-f',
          signingKeyPath,
          '-n',
          terminalUpdateSignatureNamespace,
          feed.path,
        ],
        timeout: timeout,
      );
      _expect(
        result.exitCode == 0 && !result.timedOut && !result.outputOverflow,
        'signing-failed',
      );
      final File signature = File('${feed.path}.sig');
      _expect(await signature.exists(), 'signature-not-created');
      final int length = await signature.length();
      _expect(
        length >= 1 && length <= 16 * 1024,
        'signature-size-out-of-range',
      );
      return Uint8List.fromList(await signature.readAsBytes());
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}

final class TerminalUpdateSelectionPolicy {
  const TerminalUpdateSelectionPolicy();

  TerminalUpdateRelease? select({
    required TerminalUpdateFeed feed,
    required int highestAcceptedSequence,
    required int installedBuild,
    required String installedVersion,
    required String? installedArchiveSha256,
    required TerminalMacosVersion currentMacos,
  }) {
    _expect(highestAcceptedSequence >= 0, 'invalid-accepted-sequence');
    _expect(installedBuild >= 1, 'invalid-installed-build');
    final TerminalSemanticVersion current = TerminalSemanticVersion.parse(
      installedVersion,
    );
    _expect(feed.sequence >= highestAcceptedSequence, 'feed-sequence-replay');
    for (final TerminalUpdateRelease release in feed.releases) {
      if (release.build == installedBuild) {
        _expect(
          release.version.compareTo(current) == 0 &&
              (installedArchiveSha256 == null ||
                  release.archiveSha256 == installedArchiveSha256),
          'installed-build-contradiction',
        );
      }
      if (release.build > installedBuild) {
        _expect(
          release.version.compareTo(current) > 0,
          'update-version-downgrade',
        );
        if (release.minimumMacos.compareTo(currentMacos) <= 0) return release;
      }
    }
    return null;
  }
}

void _validateArchiveUrl(Uri uri) {
  _expect(
    uri.isAbsolute &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        !uri.hasQuery &&
        (!uri.hasPort || uri.port == 443) &&
        uri.path.endsWith('.zip') &&
        !uri.pathSegments.any(
          (String segment) =>
              segment == '.' || segment == '..' || segment.contains('\\'),
        ) &&
        !_hasForbiddenText(uri.toString()),
    'invalid-archive-url',
  );
}

bool _hasForbiddenText(String value) {
  for (final int rune in value.runes) {
    if (rune < 0x20 ||
        (rune >= 0x7f && rune <= 0x9f) ||
        rune == 0x202a ||
        rune == 0x202b ||
        rune == 0x202c ||
        rune == 0x202d ||
        rune == 0x202e ||
        (rune >= 0x2066 && rune <= 0x2069)) {
      return true;
    }
  }
  return false;
}

String _canonicalPublicKey(String source) {
  _expect(
    !source.contains('\r') && !source.contains('\n'),
    'invalid-public-key',
  );
  final List<String> fields = source.trim().split(RegExp(r'[ \t]+'));
  _expect(
    fields.length == 2 && fields[0] == 'ssh-ed25519',
    'invalid-public-key',
  );
  late final Uint8List blob;
  try {
    blob = base64.decode(fields[1]);
  } on FormatException {
    throw const TerminalUpdateException('invalid-public-key');
  }
  try {
    final _SshReader reader = _SshReader(blob);
    _expect(
      utf8.decode(reader.string(), allowMalformed: false) == 'ssh-ed25519',
      'invalid-public-key',
    );
    _expect(reader.string().length == 32 && reader.atEnd, 'invalid-public-key');
  } on FormatException {
    throw const TerminalUpdateException('invalid-public-key');
  }
  return '${fields[0]} ${fields[1]}';
}

void _validateSshSignature(List<int> bytes, TerminalUpdatePinnedKey pinnedKey) {
  _expect(
    bytes.isNotEmpty && bytes.length <= 16 * 1024,
    'signature-size-out-of-range',
  );
  late final String armor;
  try {
    armor = ascii.decode(bytes, allowInvalid: false);
  } on FormatException {
    throw const TerminalUpdateException('invalid-signature-armor');
  }
  _expect(
    !armor.contains('\r') && armor.endsWith('\n'),
    'invalid-signature-armor',
  );
  final List<String> lines = armor.trim().split('\n');
  _expect(
    lines.length >= 3 &&
        lines.first == '-----BEGIN SSH SIGNATURE-----' &&
        lines.last == '-----END SSH SIGNATURE-----',
    'invalid-signature-armor',
  );
  final String encoded = lines.sublist(1, lines.length - 1).join();
  _expect(
    RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(encoded),
    'invalid-signature-armor',
  );
  late final Uint8List payload;
  try {
    payload = base64.decode(encoded);
  } on FormatException {
    throw const TerminalUpdateException('invalid-signature-armor');
  }
  try {
    final _SshReader reader = _SshReader(payload);
    _expect(
      ascii.decode(reader.raw(6), allowInvalid: false) == 'SSHSIG',
      'invalid-signature-format',
    );
    _expect(reader.uint32() == 1, 'invalid-signature-version');
    final Uint8List embeddedKey = reader.string();
    final Uint8List expectedKey = base64.decode(
      pinnedKey.publicKey.split(' ')[1],
    );
    _expect(_bytesEqual(embeddedKey, expectedKey), 'signature-key-differs');
    _expect(
      utf8.decode(reader.string(), allowMalformed: false) ==
          terminalUpdateSignatureNamespace,
      'signature-namespace-differs',
    );
    _expect(reader.string().isEmpty, 'signature-reserved-data');
    _expect(
      utf8.decode(reader.string(), allowMalformed: false) == 'sha512',
      'signature-hash-differs',
    );
    final _SshReader signature = _SshReader(reader.string());
    _expect(
      utf8.decode(signature.string(), allowMalformed: false) == 'ssh-ed25519',
      'signature-algorithm-differs',
    );
    _expect(
      signature.string().length == 64 && signature.atEnd && reader.atEnd,
      'invalid-signature-data',
    );
  } on FormatException {
    throw const TerminalUpdateException('invalid-signature-data');
  }
}

Uri _uri(String source) {
  try {
    return Uri.parse(source);
  } on FormatException {
    throw const TerminalUpdateException('invalid-archive-url');
  }
}

final class _SshReader {
  _SshReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  bool get atEnd => offset == bytes.length;

  int uint32() {
    _expect(offset + 4 <= bytes.length, 'truncated-ssh-data');
    final int value =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value;
  }

  Uint8List raw(int length) {
    _expect(
      length >= 0 && offset + length <= bytes.length,
      'truncated-ssh-data',
    );
    final Uint8List value = Uint8List.sublistView(
      bytes,
      offset,
      offset + length,
    );
    offset += length;
    return value;
  }

  Uint8List string() => raw(uint32());
}

final class _CommandOutcome {
  const _CommandOutcome({
    required this.exitCode,
    required this.timedOut,
    required this.outputOverflow,
  });

  final int exitCode;
  final bool timedOut;
  final bool outputOverflow;
}

Future<_CommandOutcome> _runBoundedCommand(
  String executable,
  List<String> arguments, {
  List<int>? input,
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    return const _CommandOutcome(
      exitCode: -1,
      timedOut: false,
      outputOverflow: false,
    );
  }
  final Future<bool> stdoutOverflow = _drainBounded(process.stdout);
  final Future<bool> stderrOverflow = _drainBounded(process.stderr);
  if (input != null) process.stdin.add(input);
  await process.stdin.close();
  var timedOut = false;
  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
    exitCode = await process.exitCode;
  }
  return _CommandOutcome(
    exitCode: exitCode,
    timedOut: timedOut,
    outputOverflow: await stdoutOverflow || await stderrOverflow,
  );
}

Future<bool> _drainBounded(Stream<List<int>> stream) async {
  var bytes = 0;
  await for (final List<int> chunk in stream) {
    bytes += chunk.length;
  }
  return bytes > 4096;
}

Map<String, Object?> _object(Object? value, String code) {
  if (value is! Map<String, Object?>) throw TerminalUpdateException(code);
  return value;
}

List<Object?> _array(Object? value, String code) {
  if (value is! List<Object?>) throw TerminalUpdateException(code);
  return value;
}

String _string(Object? value, String code) {
  if (value is! String) throw TerminalUpdateException(code);
  return value;
}

int _integer(Object? value, String code) {
  if (value is! int) throw TerminalUpdateException(code);
  return value;
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String code,
) {
  _expect(
    value.length == expected.length && value.keys.toSet().containsAll(expected),
    code,
  );
}

bool _validKeyId(String value) =>
    RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(value);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

void _expect(bool condition, String code) {
  if (!condition) throw TerminalUpdateException(code);
}
