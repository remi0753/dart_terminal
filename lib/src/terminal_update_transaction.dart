import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'terminal_update_feed.dart';

const String terminalUpdateApplicationName = 'DartTerminal.app';
const String terminalUpdateBackupName = '.DartTerminal.last-good.app';
const String terminalUpdateCandidateName = '.DartTerminal.candidate.app';
const String terminalUpdateJournalName = '.dart-terminal-update-journal.json';

const List<String> terminalUpdateCodePaths = <String>[
  'Contents/Frameworks/libdart_engine_aot_shared.dylib',
  'Contents/Frameworks/libdart_pty_macos.dylib',
  'Contents/Frameworks/libdart_terminal_app_intents_macos.dylib',
  'Contents/Frameworks/libdart_terminal_applescript_macos.dylib',
  'Contents/Frameworks/libdart_terminal_notes_macos.dylib',
  'Contents/Frameworks/libdart_terminal_renderer_macos.dylib',
  'Contents/Helpers/dart_terminal_runtime_worker',
  'Contents/MacOS/dart_terminal',
  'Contents/Resources/DartHelpers/dart_terminal_runtime_worker.aot',
  'Contents/Resources/application.aot',
];

final class TerminalUpdateTransactionException implements Exception {
  const TerminalUpdateTransactionException(this.code);

  final String code;

  @override
  String toString() => 'TerminalUpdateTransactionException: $code';
}

final class TerminalUpdateInstalledIdentity {
  TerminalUpdateInstalledIdentity({
    required this.version,
    required this.build,
    required this.archiveSha256,
  }) {
    try {
      TerminalSemanticVersion.parse(version);
    } on TerminalUpdateException {
      throw const TerminalUpdateTransactionException(
        'identity-version-invalid',
      );
    }
    _expect(build >= 1 && build <= 0x7fffffff, 'identity-build-out-of-range');
    _expect(_isSha256(archiveSha256), 'identity-hash-invalid');
  }

  final String version;
  final int build;
  final String archiveSha256;
}

final class TerminalUpdateCodeSignatureEvidence {
  TerminalUpdateCodeSignatureEvidence({
    required this.teamIdentifier,
    required this.developerId,
    required this.hardenedRuntime,
    required this.secureTimestamp,
    required this.stapled,
    required this.gatekeeperAccepted,
  }) {
    _expect(
      RegExp(r'^[A-Z0-9]{10}$').hasMatch(teamIdentifier),
      'candidate-team-id-invalid',
    );
  }

  final String teamIdentifier;
  final bool developerId;
  final bool hardenedRuntime;
  final bool secureTimestamp;
  final bool stapled;
  final bool gatekeeperAccepted;
}

final class TerminalUpdateCandidateInspection {
  TerminalUpdateCandidateInspection({
    required List<String> rootEntries,
    required this.entryCount,
    required this.hasUnsupportedEntry,
    required this.hasSymbolicLink,
    required this.hasHardLink,
    required this.hasCaseFoldedAlias,
    required this.infoPlist,
    required this.runtimeManifest,
    required this.signature,
  }) : rootEntries = List<String>.unmodifiable(rootEntries);

  final List<String> rootEntries;
  final int entryCount;
  final bool hasUnsupportedEntry;
  final bool hasSymbolicLink;
  final bool hasHardLink;
  final bool hasCaseFoldedAlias;
  final Map<String, Object?> infoPlist;
  final Map<String, Object?> runtimeManifest;
  final TerminalUpdateCodeSignatureEvidence signature;
}

final class TerminalUpdateVerifiedCandidate {
  const TerminalUpdateVerifiedCandidate._({required this.identity});

  final TerminalUpdateInstalledIdentity identity;
}

final class TerminalUpdateCandidatePolicy {
  const TerminalUpdateCandidatePolicy();

  static const int maximumEntries = 50000;

  TerminalUpdateVerifiedCandidate validate({
    required TerminalUpdateCandidateInspection inspection,
    required TerminalUpdateRelease release,
    required String expectedTeamIdentifier,
  }) {
    _expect(
      RegExp(r'^[A-Z0-9]{10}$').hasMatch(expectedTeamIdentifier),
      'candidate-team-id-invalid',
    );
    _expect(
      inspection.rootEntries.length == 1 &&
          inspection.rootEntries.single == terminalUpdateApplicationName,
      'candidate-root-inventory-differs',
    );
    _expect(
      inspection.entryCount >= 1 && inspection.entryCount <= maximumEntries,
      'candidate-entry-count-out-of-range',
    );
    _expect(!inspection.hasUnsupportedEntry, 'candidate-unsupported-entry');
    _expect(!inspection.hasSymbolicLink, 'candidate-symbolic-link');
    _expect(!inspection.hasHardLink, 'candidate-hard-link');
    _expect(!inspection.hasCaseFoldedAlias, 'candidate-case-folded-alias');
    final Map<String, Object?> plist = inspection.infoPlist;
    _expect(
      plist['CFBundleIdentifier'] == terminalUpdateProduct &&
          plist['CFBundleShortVersionString'] == release.version.toString() &&
          plist['CFBundlePackageType'] == 'APPL' &&
          plist['CFBundleExecutable'] == 'dart_terminal',
      'candidate-bundle-identity-differs',
    );
    final Map<String, Object?> manifest = inspection.runtimeManifest;
    _expect(
      manifest['schemaVersion'] == 2 &&
          manifest['runtimeMode'] == 'release-aot' &&
          manifest['bundleIdentifier'] == terminalUpdateProduct &&
          _sameStrings(_strings(manifest['architectures']), const <String>[
            'arm64',
            'x86_64',
          ]) &&
          _sameStrings(
            _strings(manifest['codePaths']),
            terminalUpdateCodePaths,
          ),
      'candidate-runtime-manifest-differs',
    );
    final Object? contract = manifest['applicationContract'];
    _expect(
      contract is Map<String, Object?> &&
          contract['bundleIdentifier'] == terminalUpdateProduct &&
          contract['runtimeMode'] == 'release-aot' &&
          contract['executable'] == 'dart_terminal',
      'candidate-application-contract-differs',
    );
    final TerminalUpdateCodeSignatureEvidence signature = inspection.signature;
    _expect(
      signature.teamIdentifier == expectedTeamIdentifier &&
          signature.developerId &&
          signature.hardenedRuntime &&
          signature.secureTimestamp &&
          signature.stapled &&
          signature.gatekeeperAccepted,
      'candidate-code-signature-differs',
    );
    return TerminalUpdateVerifiedCandidate._(
      identity: TerminalUpdateInstalledIdentity(
        version: release.version.toString(),
        build: release.build,
        archiveSha256: release.archiveSha256,
      ),
    );
  }
}

final class TerminalUpdateArchivePolicy {
  const TerminalUpdateArchivePolicy();

  void validate({
    required TerminalUpdateRelease release,
    bool timedOut = false,
    bool networkFailed = false,
    required int statusCode,
    required bool redirected,
    required int? declaredLength,
    required int actualLength,
    required String actualSha256,
  }) {
    _expect(!timedOut, 'download-timeout');
    _expect(!networkFailed, 'download-network-failed');
    _expect(!redirected, 'download-redirect-rejected');
    _expect(statusCode == HttpStatus.ok, 'download-response-rejected');
    _expect(
      declaredLength == null || declaredLength == release.archiveSize,
      'download-declared-size-differs',
    );
    _expect(actualLength == release.archiveSize, 'download-size-differs');
    _expect(actualSha256 == release.archiveSha256, 'download-hash-differs');
  }
}

final class TerminalUpdateZipInventoryPolicy {
  const TerminalUpdateZipInventoryPolicy();

  void validate(List<String> entries) {
    _expect(
      entries.isNotEmpty &&
          entries.length <= TerminalUpdateCandidatePolicy.maximumEntries,
      'candidate-entry-count-out-of-range',
    );
    final Set<String> folded = <String>{};
    final Set<String> roots = <String>{};
    for (final String raw in entries) {
      final String path = raw.endsWith('/')
          ? raw.substring(0, raw.length - 1)
          : raw;
      _expect(
        path.isNotEmpty &&
            utf8.encode(path).length <= 4096 &&
            !path.startsWith('/') &&
            !path.contains('\\') &&
            !path.contains('\u0000'),
        'candidate-archive-path-invalid',
      );
      final List<String> segments = path.split('/');
      _expect(
        segments.every(
          (String segment) =>
              segment.isNotEmpty && segment != '.' && segment != '..',
        ),
        'candidate-archive-path-invalid',
      );
      _expect(folded.add(path.toLowerCase()), 'candidate-case-folded-alias');
      roots.add(segments.first);
    }
    _expect(
      roots.length == 1 && roots.single == terminalUpdateApplicationName,
      'candidate-root-inventory-differs',
    );
  }
}

abstract interface class TerminalUpdateArchiveDownloader {
  Future<void> download({
    required TerminalUpdateRelease release,
    required File destination,
  });
}

final class TerminalHttpsUpdateArchiveDownloader
    implements TerminalUpdateArchiveDownloader {
  const TerminalHttpsUpdateArchiveDownloader({
    this.timeout = const Duration(seconds: 30),
  });

  final Duration timeout;

  @override
  Future<void> download({
    required TerminalUpdateRelease release,
    required File destination,
  }) async {
    _expect(release.archiveUrl.scheme == 'https', 'download-url-not-https');
    _expect(!await destination.exists(), 'download-destination-exists');
    final Stopwatch elapsed = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    IOSink? output;
    var verified = false;
    try {
      final HttpClientRequest request = await client
          .getUrl(release.archiveUrl)
          .timeout(timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final bool redirected = response.isRedirect;
      _expect(!redirected, 'download-redirect-rejected');
      _expect(
        response.statusCode == HttpStatus.ok,
        'download-response-rejected',
      );
      _expect(
        response.contentLength < 0 ||
            response.contentLength == release.archiveSize,
        'download-declared-size-differs',
      );
      await destination.create(exclusive: true);
      output = destination.openWrite(mode: FileMode.write);
      var received = 0;
      await for (final List<int> chunk in response.timeout(timeout)) {
        _expect(elapsed.elapsed <= timeout, 'download-timeout');
        received += chunk.length;
        _expect(received <= release.archiveSize, 'download-size-differs');
        output.add(chunk);
      }
      await output.flush();
      await output.close();
      output = null;
      _expect(elapsed.elapsed <= timeout, 'download-timeout');
      _expect(received == release.archiveSize, 'download-size-differs');
      final String digest = await _fileSha256(destination, timeout: timeout);
      const TerminalUpdateArchivePolicy().validate(
        release: release,
        statusCode: response.statusCode,
        redirected: redirected,
        declaredLength: response.contentLength < 0
            ? null
            : response.contentLength,
        actualLength: received,
        actualSha256: digest,
      );
      verified = true;
    } on TerminalUpdateTransactionException {
      rethrow;
    } on TimeoutException {
      throw const TerminalUpdateTransactionException('download-timeout');
    } on SocketException {
      throw const TerminalUpdateTransactionException('download-network-failed');
    } on HttpException {
      throw const TerminalUpdateTransactionException('download-network-failed');
    } on FileSystemException {
      throw const TerminalUpdateTransactionException('download-storage-failed');
    } finally {
      if (output != null) {
        await output.close();
      }
      client.close(force: true);
      if (!verified && await destination.exists()) {
        try {
          await destination.delete();
        } on Object {
          // The fixed failure classification above is more useful than cleanup
          // details, and a staging file is never an installable candidate.
        }
      }
    }
  }
}

final class TerminalFileUpdateArchiveDownloader
    implements TerminalUpdateArchiveDownloader {
  const TerminalFileUpdateArchiveDownloader({
    required this.source,
    this.timeout = const Duration(seconds: 30),
  });

  final File source;
  final Duration timeout;

  @override
  Future<void> download({
    required TerminalUpdateRelease release,
    required File destination,
  }) async {
    _expect(
      await FileSystemEntity.type(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'offline-archive-not-regular',
    );
    _expect(!await destination.exists(), 'download-destination-exists');
    var verified = false;
    IOSink? output;
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      await destination.create(exclusive: true);
      output = destination.openWrite(mode: FileMode.write);
      var received = 0;
      await for (final List<int> chunk in source.openRead().timeout(timeout)) {
        _expect(elapsed.elapsed <= timeout, 'download-timeout');
        received += chunk.length;
        _expect(received <= release.archiveSize, 'download-size-differs');
        output.add(chunk);
      }
      await output.flush();
      await output.close();
      output = null;
      _expect(elapsed.elapsed <= timeout, 'download-timeout');
      final String digest = await _fileSha256(destination, timeout: timeout);
      const TerminalUpdateArchivePolicy().validate(
        release: release,
        statusCode: HttpStatus.ok,
        redirected: false,
        declaredLength: await source.length(),
        actualLength: received,
        actualSha256: digest,
      );
      verified = true;
    } on TerminalUpdateTransactionException {
      rethrow;
    } on TimeoutException {
      throw const TerminalUpdateTransactionException('download-timeout');
    } on FileSystemException {
      throw const TerminalUpdateTransactionException('download-storage-failed');
    } finally {
      if (output != null) await output.close();
      if (!verified && await destination.exists()) {
        try {
          await destination.delete();
        } on Object {
          // A fixed staging file never becomes an installable candidate.
        }
      }
    }
  }
}

final class TerminalMacosUpdateCandidatePreparer {
  const TerminalMacosUpdateCandidatePreparer({
    this.timeout = const Duration(seconds: 30),
  });

  static const String _extractionName = '.DartTerminal.extracting';
  static const int _maximumMetadataBytes = 1024 * 1024;

  final Duration timeout;

  Future<TerminalUpdateVerifiedCandidate> prepare({
    required File archive,
    required Directory installDirectory,
    required TerminalUpdateRelease release,
    required String expectedTeamIdentifier,
  }) async {
    final Directory root = installDirectory.absolute;
    final File source = archive.absolute;
    _expect(
      RegExp(r'^[A-Z0-9]{10}$').hasMatch(expectedTeamIdentifier),
      'candidate-team-id-invalid',
    );
    _expect(await root.exists(), 'install-directory-missing');
    _expect(
      await FileSystemEntity.type(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'candidate-archive-not-regular',
    );
    const TerminalUpdateArchivePolicy().validate(
      release: release,
      statusCode: HttpStatus.ok,
      redirected: false,
      declaredLength: await source.length(),
      actualLength: await source.length(),
      actualSha256: await _fileSha256(source, timeout: timeout),
    );
    final Directory extraction = Directory('${root.path}/$_extractionName');
    final Directory candidate = Directory(
      '${root.path}/$terminalUpdateCandidateName',
    );
    _expect(
      await FileSystemEntity.type(extraction.path, followLinks: false) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(candidate.path, followLinks: false) ==
              FileSystemEntityType.notFound,
      'candidate-staging-exists',
    );
    await _validateZipInventory(source);
    await extraction.create();
    try {
      await _requireCommand('/usr/bin/ditto', <String>[
        '-x',
        '-k',
        source.path,
        extraction.path,
      ], 'candidate-extraction-failed');
      final TerminalUpdateCandidateInspection inspection = await _inspect(
        extraction,
        expectedTeamIdentifier,
      );
      final TerminalUpdateVerifiedCandidate verified =
          const TerminalUpdateCandidatePolicy().validate(
            inspection: inspection,
            release: release,
            expectedTeamIdentifier: expectedTeamIdentifier,
          );
      await Directory('${extraction.path}/$terminalUpdateApplicationName')
          .rename(candidate.path);
      return verified;
    } on TerminalUpdateTransactionException {
      rethrow;
    } on FileSystemException {
      throw const TerminalUpdateTransactionException(
        'candidate-staging-failed',
      );
    } finally {
      if (await extraction.exists()) await extraction.delete(recursive: true);
    }
  }

  Future<bool> verifyInstalledApplication({
    required Directory application,
    required TerminalUpdateInstalledIdentity identity,
    required String expectedTeamIdentifier,
  }) async {
    try {
      _expect(
        await FileSystemEntity.type(application.path, followLinks: false) ==
            FileSystemEntityType.directory,
        'installed-application-not-directory',
      );
      final TerminalUpdateCandidateInspection inspection =
          await _inspectApplication(application, const <String>[
            terminalUpdateApplicationName,
          ], expectedTeamIdentifier);
      const TerminalUpdateCandidatePolicy().validate(
        inspection: inspection,
        release: TerminalUpdateRelease(
          version: TerminalSemanticVersion.parse(identity.version),
          build: identity.build,
          minimumMacos: const TerminalMacosVersion(14, 0),
          archiveUrl: Uri.parse('https://identity.invalid/DartTerminal.zip'),
          archiveSize: 1,
          archiveSha256: identity.archiveSha256,
          releaseNotes: const <String>[],
        ),
        expectedTeamIdentifier: expectedTeamIdentifier,
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _validateZipInventory(File archive) async {
    final _TerminalCommandResult result = await _command(
      '/usr/bin/zipinfo',
      <String>['-1', archive.path],
      maximumOutputBytes: 2 * 1024 * 1024,
    );
    _expect(
      result.exitCode == 0 && !result.timedOut && !result.outputOverflow,
      'candidate-archive-inventory-failed',
    );
    const TerminalUpdateZipInventoryPolicy().validate(
      const LineSplitter().convert(result.stdout),
    );
    final _TerminalCommandResult modes = await _command(
      '/usr/bin/zipinfo',
      <String>['-l', archive.path],
      maximumOutputBytes: 4 * 1024 * 1024,
    );
    _expect(
      modes.exitCode == 0 && !modes.timedOut && !modes.outputOverflow,
      'candidate-archive-mode-scan-failed',
    );
    _expect(
      !RegExp(
        r'^[lbcps][rwxStT-]{9}\s',
        multiLine: true,
      ).hasMatch(modes.stdout),
      'candidate-archive-unsafe-entry-mode',
    );
  }

  Future<TerminalUpdateCandidateInspection> _inspect(
    Directory extraction,
    String expectedTeamIdentifier,
  ) async {
    final List<FileSystemEntity> rootEntities = await extraction
        .list(followLinks: false)
        .toList();
    final List<String> rootEntries = rootEntities
        .map((FileSystemEntity entity) => _basename(entity.path))
        .toList(growable: false);
    final Directory application = Directory(
      '${extraction.path}/$terminalUpdateApplicationName',
    );
    return _inspectApplication(
      application,
      rootEntries,
      expectedTeamIdentifier,
    );
  }

  Future<TerminalUpdateCandidateInspection> _inspectApplication(
    Directory application,
    List<String> rootEntries,
    String expectedTeamIdentifier,
  ) async {
    var entryCount = 1;
    var hasUnsupportedEntry = false;
    var hasSymbolicLink = false;
    var hasCaseFoldedAlias = false;
    final Set<String> folded = <String>{
      terminalUpdateApplicationName.toLowerCase(),
    };
    await for (final FileSystemEntity entity in application.list(
      recursive: true,
      followLinks: false,
    )) {
      entryCount++;
      _expect(
        entryCount <= TerminalUpdateCandidatePolicy.maximumEntries,
        'candidate-entry-count-out-of-range',
      );
      final String relative =
          '$terminalUpdateApplicationName/'
          '${entity.path.substring(application.path.length + 1)}';
      _expect(utf8.encode(relative).length <= 4096, 'candidate-path-too-large');
      if (!folded.add(relative.toLowerCase())) hasCaseFoldedAlias = true;
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) hasSymbolicLink = true;
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.link) {
        hasUnsupportedEntry = true;
      }
    }
    final _TerminalCommandResult hardLinks = await _command(
      '/usr/bin/find',
      <String>[application.path, '-type', 'f', '-links', '+1', '-print'],
      maximumOutputBytes: 4096,
    );
    _expect(
      hardLinks.exitCode == 0 &&
          !hardLinks.timedOut &&
          !hardLinks.outputOverflow,
      'candidate-hard-link-scan-failed',
    );
    final Map<String, Object?> plist = await _plist(
      File('${application.path}/Contents/Info.plist'),
    );
    final Map<String, Object?> manifest = await _json(
      File(
        '${application.path}/Contents/Resources/runtime-build-manifest.json',
      ),
    );
    for (final String relative in terminalUpdateCodePaths) {
      _expect(
        await FileSystemEntity.type(
              '${application.path}/$relative',
              followLinks: false,
            ) ==
            FileSystemEntityType.file,
        'candidate-code-path-missing',
      );
    }
    final String requirement =
        'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
        'and certificate leaf[subject.OU] = "$expectedTeamIdentifier"';
    await _requireCommand('/usr/bin/codesign', <String>[
      '--verify',
      '--deep',
      '--strict',
      '-R=$requirement',
      application.path,
    ], 'candidate-code-signature-differs');
    var developerId = true;
    var hardenedRuntime = true;
    var secureTimestamp = true;
    for (final String path in <String>[
      for (final String relative in terminalUpdateCodePaths)
        '${application.path}/$relative',
      application.path,
    ]) {
      final _TerminalCommandResult display = await _command(
        '/usr/bin/codesign',
        <String>['--display', '--verbose=4', path],
        maximumOutputBytes: 64 * 1024,
      );
      final String details = '${display.stdout}\n${display.stderr}';
      developerId =
          developerId &&
          display.exitCode == 0 &&
          details.contains('Authority=Developer ID Application:') &&
          details.contains('TeamIdentifier=$expectedTeamIdentifier') &&
          !details.contains('Signature=adhoc');
      hardenedRuntime =
          hardenedRuntime && RegExp(r'flags=.*\bruntime\b').hasMatch(details);
      secureTimestamp =
          secureTimestamp &&
          RegExp(r'^Timestamp=.+$', multiLine: true).hasMatch(details);
    }
    final bool stapled = await _commandSucceeded('/usr/bin/xcrun', <String>[
      'stapler',
      'validate',
      '-v',
      application.path,
    ]);
    final bool gatekeeper = await _commandSucceeded('/usr/sbin/spctl', <String>[
      '--assess',
      '--type',
      'execute',
      '--verbose=4',
      application.path,
    ]);
    return TerminalUpdateCandidateInspection(
      rootEntries: rootEntries,
      entryCount: entryCount,
      hasUnsupportedEntry: hasUnsupportedEntry,
      hasSymbolicLink: hasSymbolicLink,
      hasHardLink: hardLinks.stdout.trim().isNotEmpty,
      hasCaseFoldedAlias: hasCaseFoldedAlias,
      infoPlist: plist,
      runtimeManifest: manifest,
      signature: TerminalUpdateCodeSignatureEvidence(
        teamIdentifier: expectedTeamIdentifier,
        developerId: developerId,
        hardenedRuntime: hardenedRuntime,
        secureTimestamp: secureTimestamp,
        stapled: stapled,
        gatekeeperAccepted: gatekeeper,
      ),
    );
  }

  Future<Map<String, Object?>> _plist(File file) async {
    _expect(
      await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file,
      'candidate-info-plist-missing',
    );
    final _TerminalCommandResult result = await _command(
      '/usr/bin/plutil',
      <String>['-convert', 'json', '-o', '-', file.path],
      maximumOutputBytes: _maximumMetadataBytes,
    );
    _expect(
      result.exitCode == 0 && !result.timedOut && !result.outputOverflow,
      'candidate-info-plist-invalid',
    );
    return _decodeObject(result.stdout, 'candidate-info-plist-invalid');
  }

  Future<Map<String, Object?>> _json(File file) async {
    _expect(
      await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          await file.length() <= _maximumMetadataBytes,
      'candidate-runtime-manifest-invalid',
    );
    return _decodeObject(
      await file.readAsString(),
      'candidate-runtime-manifest-invalid',
    );
  }

  Future<void> _requireCommand(
    String executable,
    List<String> arguments,
    String code,
  ) async {
    final _TerminalCommandResult result = await _command(
      executable,
      arguments,
      maximumOutputBytes: 64 * 1024,
    );
    _expect(
      result.exitCode == 0 && !result.timedOut && !result.outputOverflow,
      code,
    );
  }

  Future<bool> _commandSucceeded(
    String executable,
    List<String> arguments,
  ) async {
    final _TerminalCommandResult result = await _command(
      executable,
      arguments,
      maximumOutputBytes: 64 * 1024,
    );
    return result.exitCode == 0 && !result.timedOut && !result.outputOverflow;
  }

  Future<_TerminalCommandResult> _command(
    String executable,
    List<String> arguments, {
    required int maximumOutputBytes,
  }) => _runTerminalUpdateCommand(
    executable,
    arguments,
    timeout: timeout,
    maximumOutputBytes: maximumOutputBytes,
  );
}

enum TerminalUpdateTransactionPhase {
  prepared,
  backupMoved,
  candidateInstalled,
  awaitingHealth,
  committed,
  rolledBack,
}

final class TerminalUpdateTransactionJournal {
  TerminalUpdateTransactionJournal({
    required this.transactionId,
    required this.phase,
    required this.feedSequence,
    required this.previous,
    required this.candidate,
  }) {
    _expect(_isTransactionId(transactionId), 'journal-transaction-id-invalid');
    _expect(
      feedSequence >= 1 && feedSequence <= 0x1fffffffffffff,
      'journal-sequence-out-of-range',
    );
  }

  final String transactionId;
  final TerminalUpdateTransactionPhase phase;
  final int feedSequence;
  final TerminalUpdateInstalledIdentity previous;
  final TerminalUpdateInstalledIdentity candidate;

  TerminalUpdateTransactionJournal withPhase(
    TerminalUpdateTransactionPhase value,
  ) => TerminalUpdateTransactionJournal(
    transactionId: transactionId,
    phase: value,
    feedSequence: feedSequence,
    previous: previous,
    candidate: candidate,
  );

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'format': 'dart-terminal-update-transaction',
    'version': 1,
    'product': terminalUpdateProduct,
    'transaction_id': transactionId,
    'phase': phase.name,
    'feed_sequence': feedSequence,
    'current_name': terminalUpdateApplicationName,
    'backup_name': terminalUpdateBackupName,
    'candidate_name': terminalUpdateCandidateName,
    'previous_version': previous.version,
    'previous_build': previous.build,
    'previous_archive_sha256': previous.archiveSha256,
    'candidate_version': candidate.version,
    'candidate_build': candidate.build,
    'candidate_archive_sha256': candidate.archiveSha256,
  };
}

final class TerminalUpdateTransactionJournalCodec {
  const TerminalUpdateTransactionJournalCodec();

  static const int maximumBytes = 16 * 1024;

  Uint8List encode(TerminalUpdateTransactionJournal journal) =>
      Uint8List.fromList(
        utf8.encode('${jsonEncode(journal.toCanonicalJson())}\n'),
      );

  TerminalUpdateTransactionJournal parse(List<int> bytes) {
    _expect(
      bytes.isNotEmpty && bytes.length <= maximumBytes,
      'journal-size-invalid',
    );
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const TerminalUpdateTransactionException('journal-not-utf8');
    }
    _expect(
      source.endsWith('\n') && !source.endsWith('\n\n'),
      'journal-newline-invalid',
    );
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const TerminalUpdateTransactionException('journal-json-invalid');
    }
    _expect(decoded is Map<String, Object?>, 'journal-root-invalid');
    final Map<String, Object?> value = decoded! as Map<String, Object?>;
    const Set<String> fields = <String>{
      'format',
      'version',
      'product',
      'transaction_id',
      'phase',
      'feed_sequence',
      'current_name',
      'backup_name',
      'candidate_name',
      'previous_version',
      'previous_build',
      'previous_archive_sha256',
      'candidate_version',
      'candidate_build',
      'candidate_archive_sha256',
    };
    _expect(
      value.length == fields.length && value.keys.toSet().containsAll(fields),
      'journal-fields-differ',
    );
    _expect(
      value['format'] == 'dart-terminal-update-transaction' &&
          value['version'] == 1 &&
          value['product'] == terminalUpdateProduct &&
          value['current_name'] == terminalUpdateApplicationName &&
          value['backup_name'] == terminalUpdateBackupName &&
          value['candidate_name'] == terminalUpdateCandidateName,
      'journal-contract-differs',
    );
    final TerminalUpdateTransactionPhase phase;
    try {
      phase = TerminalUpdateTransactionPhase.values.byName(
        _string(value['phase'], 'journal-phase-invalid'),
      );
    } on ArgumentError {
      throw const TerminalUpdateTransactionException('journal-phase-invalid');
    }
    final TerminalUpdateTransactionJournal journal =
        TerminalUpdateTransactionJournal(
          transactionId: _string(
            value['transaction_id'],
            'journal-transaction-id-invalid',
          ),
          phase: phase,
          feedSequence: _integer(
            value['feed_sequence'],
            'journal-sequence-invalid',
          ),
          previous: TerminalUpdateInstalledIdentity(
            version: _string(
              value['previous_version'],
              'journal-previous-version-invalid',
            ),
            build: _integer(
              value['previous_build'],
              'journal-previous-build-invalid',
            ),
            archiveSha256: _string(
              value['previous_archive_sha256'],
              'journal-previous-hash-invalid',
            ),
          ),
          candidate: TerminalUpdateInstalledIdentity(
            version: _string(
              value['candidate_version'],
              'journal-candidate-version-invalid',
            ),
            build: _integer(
              value['candidate_build'],
              'journal-candidate-build-invalid',
            ),
            archiveSha256: _string(
              value['candidate_archive_sha256'],
              'journal-candidate-hash-invalid',
            ),
          ),
        );
    _expect(_bytesEqual(encode(journal), bytes), 'journal-not-canonical');
    return journal;
  }
}

abstract interface class TerminalUpdateTransactionStorage {
  Future<bool> exists(String name);

  Future<bool> isVerifiedApplication(
    String name,
    TerminalUpdateInstalledIdentity identity,
  );

  Future<void> move(String sourceName, String destinationName);

  Future<void> remove(String name);

  Future<List<int>?> readJournal();

  Future<void> writeJournal(List<int> bytes);
}

typedef TerminalUpdateLocalBundleVerifier = Future<bool> Function(
  Directory application,
  TerminalUpdateInstalledIdentity identity,
);

final class TerminalLocalUpdateTransactionStorage
    implements TerminalUpdateTransactionStorage {
  TerminalLocalUpdateTransactionStorage({
    required Directory installDirectory,
    required TerminalUpdateLocalBundleVerifier verifyBundle,
  }) : _root = installDirectory.absolute,
       _verifyBundle = verifyBundle {
    _expect(_root.path.startsWith('/'), 'install-directory-not-absolute');
  }

  final Directory _root;
  final TerminalUpdateLocalBundleVerifier _verifyBundle;

  @override
  Future<bool> exists(String name) async =>
      await FileSystemEntity.type(_path(name), followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  Future<bool> isVerifiedApplication(
    String name,
    TerminalUpdateInstalledIdentity identity,
  ) async {
    final String path = _path(name);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    return _verifyBundle(Directory(path), identity);
  }

  @override
  Future<List<int>?> readJournal() async {
    final File journal = File(_path(terminalUpdateJournalName));
    final FileSystemEntityType type = await FileSystemEntity.type(
      journal.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return null;
    _expect(type == FileSystemEntityType.file, 'journal-not-regular-file');
    _expect(
      await journal.length() <=
          TerminalUpdateTransactionJournalCodec.maximumBytes,
      'journal-size-invalid',
    );
    return journal.readAsBytes();
  }

  @override
  Future<void> writeJournal(List<int> bytes) async {
    _expect(
      bytes.isNotEmpty &&
          bytes.length <= TerminalUpdateTransactionJournalCodec.maximumBytes,
      'journal-size-invalid',
    );
    final File target = File(_path(terminalUpdateJournalName));
    final File temporary = File('${target.path}.new');
    if (await temporary.exists()) await temporary.delete();
    try {
      final RandomAccessFile handle = await temporary.open(
        mode: FileMode.write,
      );
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> move(String sourceName, String destinationName) async {
    final String source = _path(sourceName);
    final String destination = _path(destinationName);
    _expect(
      await FileSystemEntity.type(destination, followLinks: false) ==
          FileSystemEntityType.notFound,
      'transaction-destination-exists',
    );
    await Directory(source).rename(destination);
  }

  @override
  Future<void> remove(String name) async {
    final String path = _path(name);
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    _expect(
      type == FileSystemEntityType.directory,
      'transaction-entry-not-directory',
    );
    await Directory(path).delete(recursive: true);
  }

  String _path(String name) {
    _expect(_allowedTransactionName(name), 'transaction-name-invalid');
    return '${_root.path}/$name';
  }
}

final class TerminalUpdateTransactionCoordinator {
  TerminalUpdateTransactionCoordinator({
    required TerminalUpdateTransactionStorage storage,
    TerminalUpdateTransactionJournalCodec codec =
        const TerminalUpdateTransactionJournalCodec(),
    Random? random,
  }) : _storage = storage,
       _codec = codec,
       _random = random ?? Random.secure();

  final TerminalUpdateTransactionStorage _storage;
  final TerminalUpdateTransactionJournalCodec _codec;
  final Random _random;

  Future<String> install({
    required TerminalUpdateVerifiedCandidate candidate,
    required TerminalUpdateInstalledIdentity previous,
    required int feedSequence,
  }) async {
    final List<int>? existingBytes = await _storage.readJournal();
    if (existingBytes != null) {
      final TerminalUpdateTransactionJournal existing = _codec.parse(
        existingBytes,
      );
      _expect(
        existing.phase == TerminalUpdateTransactionPhase.committed ||
            existing.phase == TerminalUpdateTransactionPhase.rolledBack,
        'transaction-already-active',
      );
      _expect(
        feedSequence > existing.feedSequence,
        'transaction-sequence-replay',
      );
    }
    _expect(
      candidate.identity.build > previous.build &&
          TerminalSemanticVersion.parse(candidate.identity.version)
                  .compareTo(TerminalSemanticVersion.parse(previous.version)) >
              0,
      'candidate-not-newer',
    );
    _expect(
      await _storage.isVerifiedApplication(
        terminalUpdateApplicationName,
        previous,
      ),
      'current-application-not-verified',
    );
    _expect(
      await _storage.isVerifiedApplication(
        terminalUpdateCandidateName,
        candidate.identity,
      ),
      'candidate-application-not-verified',
    );
    TerminalUpdateTransactionJournal journal = TerminalUpdateTransactionJournal(
      transactionId: _transactionId(),
      phase: TerminalUpdateTransactionPhase.prepared,
      feedSequence: feedSequence,
      previous: previous,
      candidate: candidate.identity,
    );
    await _write(journal);
    try {
      if (await _storage.exists(terminalUpdateBackupName)) {
        await _storage.remove(terminalUpdateBackupName);
      }
      await _storage.move(
        terminalUpdateApplicationName,
        terminalUpdateBackupName,
      );
      journal = journal.withPhase(TerminalUpdateTransactionPhase.backupMoved);
      await _write(journal);
      await _storage.move(
        terminalUpdateCandidateName,
        terminalUpdateApplicationName,
      );
      journal = journal.withPhase(
        TerminalUpdateTransactionPhase.candidateInstalled,
      );
      await _write(journal);
      journal = journal.withPhase(
        TerminalUpdateTransactionPhase.awaitingHealth,
      );
      await _write(journal);
      return journal.transactionId;
    } on Object {
      try {
        await recover();
      } on Object {
        // The durable pre-mutation journal lets a later launch retry recovery.
      }
      rethrow;
    }
  }

  Future<void> acknowledgeHealth(String transactionId) async {
    final TerminalUpdateTransactionJournal journal = await _requiredJournal();
    _expect(
      journal.phase == TerminalUpdateTransactionPhase.awaitingHealth,
      'health-not-awaited',
    );
    _expect(journal.transactionId == transactionId, 'health-token-differs');
    _expect(
      await _storage.isVerifiedApplication(
        terminalUpdateApplicationName,
        journal.candidate,
      ),
      'healthy-application-not-verified',
    );
    await _write(journal.withPhase(TerminalUpdateTransactionPhase.committed));
  }

  Future<void> recover() async {
    final List<int>? bytes = await _storage.readJournal();
    if (bytes == null) return;
    final TerminalUpdateTransactionJournal journal = _codec.parse(bytes);
    if (journal.phase == TerminalUpdateTransactionPhase.committed) {
      if (await _storage.isVerifiedApplication(
        terminalUpdateApplicationName,
        journal.candidate,
      )) {
        if (await _storage.exists(terminalUpdateCandidateName)) {
          await _storage.remove(terminalUpdateCandidateName);
        }
        return;
      }
    }
    if (journal.phase == TerminalUpdateTransactionPhase.rolledBack &&
        await _storage.isVerifiedApplication(
          terminalUpdateApplicationName,
          journal.previous,
        )) {
      if (await _storage.exists(terminalUpdateCandidateName)) {
        await _storage.remove(terminalUpdateCandidateName);
      }
      return;
    }
    await _restore(journal);
  }

  Future<void> rollback(String transactionId) async {
    final TerminalUpdateTransactionJournal journal = await _requiredJournal();
    _expect(journal.transactionId == transactionId, 'rollback-token-differs');
    _expect(
      journal.phase == TerminalUpdateTransactionPhase.awaitingHealth ||
          journal.phase == TerminalUpdateTransactionPhase.committed,
      'rollback-not-available',
    );
    await _restore(journal);
  }

  Future<void> _restore(TerminalUpdateTransactionJournal journal) async {
    final bool backupVerified = await _storage.isVerifiedApplication(
      terminalUpdateBackupName,
      journal.previous,
    );
    final bool currentIsPrevious = await _storage.isVerifiedApplication(
      terminalUpdateApplicationName,
      journal.previous,
    );
    if (!currentIsPrevious) {
      _expect(backupVerified, 'last-good-application-not-verified');
      if (await _storage.exists(terminalUpdateApplicationName)) {
        await _storage.remove(terminalUpdateApplicationName);
      }
      await _storage.move(
        terminalUpdateBackupName,
        terminalUpdateApplicationName,
      );
    } else if (await _storage.exists(terminalUpdateBackupName)) {
      await _storage.remove(terminalUpdateBackupName);
    }
    if (await _storage.exists(terminalUpdateCandidateName)) {
      await _storage.remove(terminalUpdateCandidateName);
    }
    await _write(journal.withPhase(TerminalUpdateTransactionPhase.rolledBack));
  }

  Future<TerminalUpdateTransactionJournal> _requiredJournal() async {
    final List<int>? bytes = await _storage.readJournal();
    _expect(bytes != null, 'transaction-journal-missing');
    return _codec.parse(bytes!);
  }

  Future<void> _write(TerminalUpdateTransactionJournal journal) =>
      _storage.writeJournal(_codec.encode(journal));

  String _transactionId() {
    final StringBuffer value = StringBuffer();
    for (var index = 0; index < 16; index++) {
      value.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return value.toString();
  }
}

bool _allowedTransactionName(String value) =>
    value == terminalUpdateApplicationName ||
    value == terminalUpdateBackupName ||
    value == terminalUpdateCandidateName ||
    value == terminalUpdateJournalName;

bool _isTransactionId(String value) =>
    RegExp(r'^[0-9a-f]{32}$').hasMatch(value);

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

Future<String> _fileSha256(File file, {required Duration timeout}) async {
  final ProcessResult result;
  try {
    result = await Process.run('/usr/bin/shasum', <String>[
      '-a',
      '256',
      file.path,
    ]).timeout(timeout);
  } on TimeoutException {
    throw const TerminalUpdateTransactionException('download-hash-timeout');
  } on ProcessException {
    throw const TerminalUpdateTransactionException('download-hash-failed');
  }
  final String output = result.stdout as String;
  final RegExpMatch? match = RegExp(r'^([0-9a-f]{64})  ').firstMatch(output);
  _expect(
    result.exitCode == 0 && output.length <= 4096 && match != null,
    'download-hash-failed',
  );
  return match!.group(1)!;
}

final class _TerminalCommandResult {
  const _TerminalCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.outputOverflow,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool outputOverflow;
}

Future<_TerminalCommandResult> _runTerminalUpdateCommand(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  required int maximumOutputBytes,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    return const _TerminalCommandResult(
      exitCode: -1,
      stdout: '',
      stderr: '',
      timedOut: false,
      outputOverflow: false,
    );
  }
  final _BoundedText stdout = _BoundedText(maximumOutputBytes);
  final _BoundedText stderr = _BoundedText(maximumOutputBytes);
  final Future<void> stdoutDone = stdout.add(process.stdout);
  final Future<void> stderrDone = stderr.add(process.stderr);
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
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return _TerminalCommandResult(
    exitCode: exitCode,
    stdout: stdout.text,
    stderr: stderr.text,
    timedOut: timedOut,
    outputOverflow: stdout.overflow || stderr.overflow,
  );
}

final class _BoundedText {
  _BoundedText(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _seen = 0;

  bool get overflow => _seen > maximumBytes;

  String get text => utf8.decode(_bytes.takeBytes(), allowMalformed: true);

  Future<void> add(Stream<List<int>> source) async {
    await for (final List<int> chunk in source) {
      final int remaining = maximumBytes - _bytes.length;
      if (remaining > 0) {
        _bytes.add(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
      }
      _seen += chunk.length;
    }
  }
}

Map<String, Object?> _decodeObject(String source, String code) {
  try {
    final Object? value = jsonDecode(source);
    if (value is Map<String, Object?>) return value;
  } on FormatException {
    // Use the caller's fixed classification below.
  }
  throw TerminalUpdateTransactionException(code);
}

String _basename(String path) {
  final List<String> segments = path.split('/');
  return segments.lastWhere((String value) => value.isNotEmpty);
}

List<String> _strings(Object? value) {
  _expect(value is List<Object?>, 'candidate-string-list-invalid');
  final List<Object?> values = value! as List<Object?>;
  _expect(
    values.every((Object? item) => item is String),
    'candidate-string-list-invalid',
  );
  return values.cast<String>();
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> a = left.toList()..sort();
  final List<String> b = right.toList()..sort();
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

String _string(Object? value, String code) {
  if (value is! String) throw TerminalUpdateTransactionException(code);
  return value;
}

int _integer(Object? value, String code) {
  if (value is! int) throw TerminalUpdateTransactionException(code);
  return value;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

void _expect(bool condition, String code) {
  if (!condition) throw TerminalUpdateTransactionException(code);
}
