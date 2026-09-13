import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_sha256.dart';

const String terminalUpdateFeedFileName = 'update-feed.json';
const String terminalUpdateSignatureFileName = 'update-feed.json.sig';
const String terminalUpdateEvidenceFileName = 'update-feed-evidence.json';

final class TerminalUpdateFeedGeneratorOptions {
  const TerminalUpdateFeedGeneratorOptions({
    required this.archivePath,
    required this.archiveUrl,
    required this.version,
    required this.build,
    required this.minimumMacos,
    required this.sequence,
    required this.expiresUnixSeconds,
    required this.keyId,
    required this.publicKeyPath,
    required this.signingKeyPath,
    required this.outputDirectory,
    required this.releaseNotes,
  });

  factory TerminalUpdateFeedGeneratorOptions.parse(List<String> arguments) {
    final Map<String, String> values = <String, String>{};
    final List<String> notes = <String>[];
    const Set<String> names = <String>{
      'archive',
      'archive-url',
      'version',
      'build',
      'minimum-macos',
      'sequence',
      'expires-unix-seconds',
      'key-id',
      'public-key',
      'signing-key',
      'output-directory',
      'release-note',
    };
    for (final String argument in arguments) {
      if (!argument.startsWith('--') || !argument.contains('=')) {
        throw const TerminalUpdateException('invalid-generator-option');
      }
      final int separator = argument.indexOf('=');
      final String name = argument.substring(2, separator);
      final String value = argument.substring(separator + 1);
      if (!names.contains(name) || value.isEmpty) {
        throw const TerminalUpdateException('invalid-generator-option');
      }
      if (name == 'release-note') {
        notes.add(value);
      } else if (values.containsKey(name)) {
        throw const TerminalUpdateException('duplicate-generator-option');
      } else {
        values[name] = value;
      }
    }
    final Set<String> required = names.difference(const <String>{
      'release-note',
    });
    if (values.keys.toSet().length != required.length ||
        !values.keys.toSet().containsAll(required)) {
      throw const TerminalUpdateException('missing-generator-option');
    }
    return TerminalUpdateFeedGeneratorOptions(
      archivePath: _absolutePath(values['archive']!),
      archiveUrl: Uri.parse(values['archive-url']!),
      version: TerminalSemanticVersion.parse(values['version']!),
      build: _positiveInteger(values['build']!, 'invalid-build'),
      minimumMacos: TerminalMacosVersion.parse(values['minimum-macos']!),
      sequence: _positiveInteger(values['sequence']!, 'invalid-sequence'),
      expiresUnixSeconds: _positiveInteger(
        values['expires-unix-seconds']!,
        'invalid-expiry',
      ),
      keyId: values['key-id']!,
      publicKeyPath: _absolutePath(values['public-key']!),
      signingKeyPath: _absolutePath(values['signing-key']!),
      outputDirectory: _absolutePath(values['output-directory']!),
      releaseNotes: List<String>.unmodifiable(notes),
    );
  }

  final String archivePath;
  final Uri archiveUrl;
  final TerminalSemanticVersion version;
  final int build;
  final TerminalMacosVersion minimumMacos;
  final int sequence;
  final int expiresUnixSeconds;
  final String keyId;
  final String publicKeyPath;
  final String signingKeyPath;
  final String outputDirectory;
  final List<String> releaseNotes;
}

Future<void> generateTerminalUpdateFeedArtifact(
  TerminalUpdateFeedGeneratorOptions options, {
  TerminalOpenSshUpdateSigner signer = const TerminalOpenSshUpdateSigner(),
  TerminalUpdateSignatureVerifier verifier =
      const TerminalOpenSshUpdateSignatureVerifier(),
  int? nowUnixSeconds,
}) async {
  final File archive = File(options.archivePath);
  final File publicKeyFile = File(options.publicKeyPath);
  if (!await archive.exists() || !await publicKeyFile.exists()) {
    throw const TerminalUpdateException('generator-input-missing');
  }
  final int archiveSize = await archive.length();
  if (archiveSize < 1 || archiveSize > 1024 * 1024 * 1024) {
    throw const TerminalUpdateException('archive-size-out-of-range');
  }
  final String publicKeySource = await _readBoundedText(publicKeyFile, 4096);
  if (publicKeySource.contains('\r') || publicKeySource.trim().contains('\n')) {
    throw const TerminalUpdateException('invalid-public-key');
  }
  final List<String> publicFields = publicKeySource.trim().split(
    RegExp(r'[ \t]+'),
  );
  if (publicFields.length < 2) {
    throw const TerminalUpdateException('invalid-public-key');
  }
  final TerminalUpdatePinnedKey pinnedKey = TerminalUpdatePinnedKey(
    keyId: options.keyId,
    publicKey: '${publicFields[0]} ${publicFields[1]}',
  );
  final String archiveSha256 = await _fileSha256(archive);
  final TerminalUpdateFeed feed = TerminalUpdateFeed(
    sequence: options.sequence,
    keyId: options.keyId,
    expiresUnixSeconds: options.expiresUnixSeconds,
    releases: <TerminalUpdateRelease>[
      TerminalUpdateRelease(
        version: options.version,
        build: options.build,
        minimumMacos: options.minimumMacos,
        archiveUrl: options.archiveUrl,
        archiveSize: archiveSize,
        archiveSha256: archiveSha256,
        releaseNotes: options.releaseNotes,
      ),
    ],
  );
  final TerminalUpdateFeedCodec codec = const TerminalUpdateFeedCodec();
  final List<int> feedBytes = codec.encode(feed);
  codec.parse(
    feedBytes,
    nowUnixSeconds:
        nowUnixSeconds ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
  );
  final List<int> signatureBytes = await signer.sign(
    feedBytes: feedBytes,
    signingKeyPath: options.signingKeyPath,
  );
  if (!await verifier.verify(
    feedBytes: feedBytes,
    signatureBytes: signatureBytes,
    pinnedKey: pinnedKey,
  )) {
    throw const TerminalUpdateException(
      'generated-signature-verification-failed',
    );
  }

  final Directory output = Directory(options.outputDirectory);
  final List<String> outputParts = output.uri.pathSegments
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  if (outputParts.isEmpty ||
      outputParts.last == '.' ||
      outputParts.last == '..') {
    throw const TerminalUpdateException('invalid-output-directory');
  }
  final Directory parent = output.parent;
  await parent.create(recursive: true);
  final String outputName = outputParts.last;
  final Directory staging = await parent.createTemp('.$outputName.staging-');
  Directory? previous;
  try {
    await File('${staging.path}/$terminalUpdateFeedFileName')
        .writeAsBytes(feedBytes, flush: true);
    await File('${staging.path}/$terminalUpdateSignatureFileName')
        .writeAsBytes(signatureBytes, flush: true);
    final Map<String, Object?> evidence = <String, Object?>{
      'schema_version': 1,
      'product': terminalUpdateProduct,
      'channel': terminalUpdateChannel,
      'key_id': options.keyId,
      'feed': terminalUpdateFeedFileName,
      'feed_sha256': terminalSha256(feedBytes),
      'signature': terminalUpdateSignatureFileName,
      'signature_sha256': terminalSha256(signatureBytes),
      'archive_name': archive.uri.pathSegments.last,
      'archive_size': archiveSize,
      'archive_sha256': archiveSha256,
      'sequence': options.sequence,
      'build': options.build,
    };
    await File('${staging.path}/$terminalUpdateEvidenceFileName')
        .writeAsString('${jsonEncode(evidence)}\n', flush: true);
    if (await output.exists()) {
      previous = Directory(
        '${parent.path}/.$outputName.previous-${pid.toRadixString(16)}',
      );
      if (await previous.exists()) {
        throw const TerminalUpdateException('previous-output-conflict');
      }
      await output.rename(previous.path);
    }
    try {
      await staging.rename(output.path);
    } catch (_) {
      if (previous != null && !await output.exists()) {
        await previous.rename(output.path);
        previous = null;
      }
      rethrow;
    }
    if (previous != null) {
      await previous.delete(recursive: true);
      previous = null;
    }
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
    if (previous != null && await previous.exists() && !await output.exists()) {
      await previous.rename(output.path);
    }
  }
}

Future<String> _fileSha256(File file) async {
  final ProcessResult result = await Process.run('/usr/bin/shasum', <String>[
    '-a',
    '256',
    file.path,
  ]);
  if (result.exitCode != 0 ||
      result.stdout is! String ||
      (result.stdout! as String).length > 4096) {
    throw const TerminalUpdateException('archive-hash-failed');
  }
  final RegExpMatch? match = RegExp(r'^([0-9a-f]{64})[ \t]')
      .firstMatch(result.stdout! as String);
  if (match == null) {
    throw const TerminalUpdateException('archive-hash-output-invalid');
  }
  return match.group(1)!;
}

Future<String> _readBoundedText(File file, int maximumBytes) async {
  if (await file.length() > maximumBytes) {
    throw const TerminalUpdateException('input-file-too-large');
  }
  try {
    return utf8.decode(await file.readAsBytes(), allowMalformed: false);
  } on FormatException {
    throw const TerminalUpdateException('input-file-not-utf8');
  }
}

String _absolutePath(String value) {
  if (!value.startsWith('/') || value.contains('\u0000')) {
    throw const TerminalUpdateException('path-must-be-absolute');
  }
  return value;
}

int _positiveInteger(String source, String code) {
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(source)) {
    throw TerminalUpdateException(code);
  }
  final int? value = int.tryParse(source);
  if (value == null || value > 0x1fffffffffffff) {
    throw TerminalUpdateException(code);
  }
  return value;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(
      'Usage: dart run tool/terminal_update_feed.dart '
      '--archive=/absolute/DartTerminal.zip '
      '--archive-url=https://example.invalid/DartTerminal.zip '
      '--version=MAJOR.MINOR.PATCH --build=INTEGER '
      '--minimum-macos=MAJOR.MINOR --sequence=INTEGER '
      '--expires-unix-seconds=INTEGER --key-id=ID '
      '--public-key=/absolute/release-key.pub '
      '--signing-key=/absolute/release-key-or-public-key '
      '--output-directory=/absolute/output '
      '[--release-note=PLAIN_TEXT ...]',
    );
    return;
  }
  try {
    final TerminalUpdateFeedGeneratorOptions options =
        TerminalUpdateFeedGeneratorOptions.parse(arguments);
    await generateTerminalUpdateFeedArtifact(options);
    stdout.writeln(
      'TERMINAL_UPDATE_FEED_GENERATED '
      'sequence=${options.sequence} build=${options.build} '
      'notes=${options.releaseNotes.length}',
    );
  } on TerminalUpdateException catch (error) {
    stderr.writeln('TERMINAL_UPDATE_FEED_FAIL code=${error.code}');
    exitCode = 65;
  } on FileSystemException {
    stderr.writeln('TERMINAL_UPDATE_FEED_FAIL code=filesystem-failure');
    exitCode = 74;
  } on ProcessException {
    stderr.writeln('TERMINAL_UPDATE_FEED_FAIL code=process-failure');
    exitCode = 74;
  }
}
