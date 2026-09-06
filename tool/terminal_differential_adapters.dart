import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'terminal_differential_harness.dart';
import 'terminal_differential_sha256.dart';

const String defaultTerminalDifferentialBackendsPath =
    'compatibility/differential_backends.json';
const String defaultTerminalDifferentialSelfTestsPath =
    'compatibility/differential_self_tests.json';
const int _maximumCatalogBytes = 256 * 1024;
const int _maximumDriverRequestBytes = 128 * 1024;
const int _maximumExecutableBytes = 512 * 1024 * 1024;
const int _maximumProcessDiagnosticBytes = 64 * 1024;

final class TerminalDifferentialAdapterException implements Exception {
  const TerminalDifferentialAdapterException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDifferentialAdapterException: $message';
}

enum TerminalDifferentialLauncher { direct, directX11, macosOpenApp }

final class TerminalDifferentialSupportFile {
  const TerminalDifferentialSupportFile({
    required this.path,
    required this.sha256,
  });

  final String path;
  final String sha256;
}

final class TerminalDifferentialBackendProfile {
  const TerminalDifferentialBackendProfile({
    required this.id,
    required this.product,
    required this.productVersion,
    required this.implementationRevision,
    required this.artifactUrl,
    required this.artifactBytes,
    required this.artifactSha256,
    required this.expectedExecutableSha256,
    required this.versionArguments,
    required this.versionContains,
    required this.configId,
    required this.configPath,
    required this.configSha256,
    required this.supportFiles,
    required this.captureMethod,
    required this.operatingSystem,
    required this.architecture,
    required this.launcher,
  });

  final String id;
  final String product;
  final String productVersion;
  final String implementationRevision;
  final String artifactUrl;
  final int artifactBytes;
  final String artifactSha256;
  final String? expectedExecutableSha256;
  final List<String> versionArguments;
  final String versionContains;
  final String configId;
  final String configPath;
  final String configSha256;
  final List<TerminalDifferentialSupportFile> supportFiles;
  final String captureMethod;
  final String operatingSystem;
  final String architecture;
  final TerminalDifferentialLauncher launcher;
}

final class TerminalDifferentialBackendCatalog {
  const TerminalDifferentialBackendCatalog({
    required this.version,
    required this.profiles,
  });

  final int version;
  final List<TerminalDifferentialBackendProfile> profiles;

  TerminalDifferentialBackendProfile profile(String id) {
    for (final TerminalDifferentialBackendProfile profile in profiles) {
      if (profile.id == id) return profile;
    }
    throw TerminalDifferentialAdapterException('unknown backend profile $id');
  }

  static TerminalDifferentialBackendCatalog load(
    File source, {
    required Directory repositoryRoot,
  }) {
    _expect(source.existsSync(), 'backend catalog does not exist');
    _expect(
      FileSystemEntity.typeSync(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'backend catalog must be a regular file',
    );
    final int length = source.lengthSync();
    _expect(
      length > 0 && length <= _maximumCatalogBytes,
      'backend catalog size is outside the limit',
    );
    return parse(source.readAsStringSync(), repositoryRoot: repositoryRoot);
  }

  static TerminalDifferentialBackendCatalog parse(
    String source, {
    required Directory repositoryRoot,
  }) {
    _expect(
      utf8.encode(source).length <= _maximumCatalogBytes,
      'backend catalog exceeds the encoded limit',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalDifferentialAdapterException(
        'invalid backend catalog JSON: $error',
      );
    }
    final Map<String, Object?> root = _object(decoded, 'catalog');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'backends',
    }, 'catalog');
    _expect(
      root['format'] == 'dart-terminal-differential-backends',
      'unsupported backend catalog format',
    );
    final int version = _integer(root['version'], 'catalog.version');
    _expect(version == 1, 'unsupported backend catalog version $version');
    final List<Object?> values = _array(root['backends'], 'catalog.backends');
    _expect(values.length == 3, 'backend catalog must contain three profiles');
    final List<TerminalDifferentialBackendProfile> profiles =
        <TerminalDifferentialBackendProfile>[];
    final Set<String> products = <String>{};
    String previousId = '';
    for (int index = 0; index < values.length; index++) {
      final String context = 'catalog.backends[$index]';
      final TerminalDifferentialBackendProfile profile = _parseProfile(
        _object(values[index], context),
        context,
        repositoryRoot,
      );
      _expect(
        previousId.isEmpty || previousId.compareTo(profile.id) < 0,
        'backend profiles must be sorted and unique',
      );
      previousId = profile.id;
      _expect(products.add(profile.product), 'backend products must be unique');
      profiles.add(profile);
    }
    _expect(
      products.containsAll(const <String>{'ghostty', 'kitty', 'xterm'}),
      'backend catalog must pin ghostty, kitty, and xterm',
    );
    return TerminalDifferentialBackendCatalog(
      version: version,
      profiles: List<TerminalDifferentialBackendProfile>.unmodifiable(profiles),
    );
  }

  static TerminalDifferentialBackendProfile _parseProfile(
    Map<String, Object?> map,
    String context,
    Directory repositoryRoot,
  ) {
    _expectKeys(map, const <String>{
      'id',
      'product',
      'product_version',
      'implementation_revision',
      'artifact_url',
      'artifact_bytes',
      'artifact_sha256',
      'expected_executable_sha256',
      'version_arguments',
      'version_contains',
      'config_id',
      'config_path',
      'config_sha256',
      'support_files',
      'capture_method',
      'operating_system',
      'architecture',
      'launcher',
    }, context);
    final String id = _id(map['id'], '$context.id');
    final String product = _id(map['product'], '$context.product');
    final String productVersion = _text(
      map['product_version'],
      '$context.product_version',
      96,
    );
    final String implementationRevision = _text(
      map['implementation_revision'],
      '$context.implementation_revision',
      128,
    );
    final String artifactUrl = _text(
      map['artifact_url'],
      '$context.artifact_url',
      512,
    );
    final Uri? artifactUri = Uri.tryParse(artifactUrl);
    _expect(
      artifactUri != null &&
          artifactUri.scheme == 'https' &&
          artifactUri.host.isNotEmpty,
      '$context.artifact_url must be an HTTPS URL',
    );
    final int artifactBytes = _integer(
      map['artifact_bytes'],
      '$context.artifact_bytes',
    );
    _expect(
      artifactBytes > 0 && artifactBytes <= _maximumExecutableBytes,
      '$context.artifact_bytes is outside the limit',
    );
    final String artifactSha256 = _sha256(
      map['artifact_sha256'],
      '$context.artifact_sha256',
    );
    final String? expectedExecutableSha256 =
        map['expected_executable_sha256'] == null
        ? null
        : _sha256(
            map['expected_executable_sha256'],
            '$context.expected_executable_sha256',
          );
    final List<Object?> versionValues = _array(
      map['version_arguments'],
      '$context.version_arguments',
    );
    _expect(
      versionValues.isNotEmpty && versionValues.length <= 8,
      '$context.version_arguments count is outside 1..8',
    );
    final List<String> versionArguments = <String>[];
    for (int index = 0; index < versionValues.length; index++) {
      versionArguments.add(
        _argument(versionValues[index], '$context.version_arguments[$index]'),
      );
    }
    final String configPath = _relativePath(
      map['config_path'],
      '$context.config_path',
    );
    final String configSha256 = _sha256(
      map['config_sha256'],
      '$context.config_sha256',
    );
    final File config = File.fromUri(repositoryRoot.uri.resolve(configPath));
    _expect(config.existsSync(), '$context config does not exist');
    _expect(
      FileSystemEntity.typeSync(config.path, followLinks: false) ==
          FileSystemEntityType.file,
      '$context config must be a regular file',
    );
    _expect(config.lengthSync() <= 1024 * 1024, '$context config is too large');
    _expect(
      terminalDifferentialSha256(config.readAsBytesSync()) == configSha256,
      '$context config SHA-256 differs',
    );
    final List<Object?> supportFileValues = _array(
      map['support_files'],
      '$context.support_files',
    );
    _expect(
      supportFileValues.isNotEmpty && supportFileValues.length <= 8,
      '$context.support_files count is outside 1..8',
    );
    final List<TerminalDifferentialSupportFile> supportFiles =
        <TerminalDifferentialSupportFile>[];
    String previousSupportPath = '';
    for (int index = 0; index < supportFileValues.length; index++) {
      final String supportContext = '$context.support_files[$index]';
      final Map<String, Object?> supportMap = _object(
        supportFileValues[index],
        supportContext,
      );
      _expectKeys(supportMap, const <String>{'path', 'sha256'}, supportContext);
      final String path = _relativePath(
        supportMap['path'],
        '$supportContext.path',
      );
      _expect(
        previousSupportPath.isEmpty || previousSupportPath.compareTo(path) < 0,
        '$context support files must be sorted and unique',
      );
      previousSupportPath = path;
      final String sha256 = _sha256(
        supportMap['sha256'],
        '$supportContext.sha256',
      );
      final File supportFile = File.fromUri(repositoryRoot.uri.resolve(path));
      _expect(supportFile.existsSync(), '$supportContext file does not exist');
      _expect(
        FileSystemEntity.typeSync(supportFile.path, followLinks: false) ==
            FileSystemEntityType.file,
        '$supportContext must be a regular file',
      );
      _expect(
        supportFile.lengthSync() <= 1024 * 1024,
        '$supportContext file is too large',
      );
      _expect(
        terminalDifferentialSha256(supportFile.readAsBytesSync()) == sha256,
        '$supportContext SHA-256 differs',
      );
      supportFiles.add(
        TerminalDifferentialSupportFile(path: path, sha256: sha256),
      );
    }
    final TerminalDifferentialLauncher launcher = switch (_id(
      map['launcher'],
      '$context.launcher',
    )) {
      'direct' => TerminalDifferentialLauncher.direct,
      'direct-x11' => TerminalDifferentialLauncher.directX11,
      'macos-open-app' => TerminalDifferentialLauncher.macosOpenApp,
      final String value => throw TerminalDifferentialAdapterException(
        '$context has unknown launcher $value',
      ),
    };
    _expect(
      product != 'xterm' || expectedExecutableSha256 == null,
      '$context source-built xterm must record its runtime executable hash',
    );
    _expect(
      product == 'xterm' || expectedExecutableSha256 != null,
      '$context official app must pin its executable SHA-256',
    );
    return TerminalDifferentialBackendProfile(
      id: id,
      product: product,
      productVersion: productVersion,
      implementationRevision: implementationRevision,
      artifactUrl: artifactUrl,
      artifactBytes: artifactBytes,
      artifactSha256: artifactSha256,
      expectedExecutableSha256: expectedExecutableSha256,
      versionArguments: List<String>.unmodifiable(versionArguments),
      versionContains: _text(
        map['version_contains'],
        '$context.version_contains',
        256,
      ),
      configId: _id(map['config_id'], '$context.config_id'),
      configPath: configPath,
      configSha256: configSha256,
      supportFiles: List<TerminalDifferentialSupportFile>.unmodifiable(
        supportFiles,
      ),
      captureMethod: _id(map['capture_method'], '$context.capture_method'),
      operatingSystem: _id(
        map['operating_system'],
        '$context.operating_system',
      ),
      architecture: _token(map['architecture'], '$context.architecture'),
      launcher: launcher,
    );
  }
}

final class TerminalDifferentialSelfTestCapture {
  const TerminalDifferentialSelfTestCapture({
    required this.profileId,
    required this.status,
    required this.automationStatus,
    required this.capturedOn,
    required this.hostOs,
    required this.hostVersion,
    required this.architecture,
    required this.executableSha256,
    required this.configSha256,
    required this.probePath,
    required this.probeSha256,
    required this.runner,
    required this.notes,
  });

  final String profileId;
  final String status;
  final String automationStatus;
  final String capturedOn;
  final String hostOs;
  final String hostVersion;
  final String architecture;
  final String executableSha256;
  final String configSha256;
  final String probePath;
  final String probeSha256;
  final String runner;
  final String notes;
}

final class TerminalDifferentialSelfTestLedger {
  const TerminalDifferentialSelfTestLedger({
    required this.version,
    required this.input,
    required this.expectedReplies,
    required this.captures,
  });

  final int version;
  final Uint8List input;
  final Uint8List expectedReplies;
  final List<TerminalDifferentialSelfTestCapture> captures;

  TerminalDifferentialSelfTestCapture capture(String profileId) {
    for (final TerminalDifferentialSelfTestCapture capture in captures) {
      if (capture.profileId == profileId) return capture;
    }
    throw TerminalDifferentialAdapterException(
      'unknown self-test capture $profileId',
    );
  }

  static TerminalDifferentialSelfTestLedger load(
    File source, {
    required Directory repositoryRoot,
    required TerminalDifferentialBackendCatalog catalog,
  }) {
    _expect(source.existsSync(), 'self-test ledger does not exist');
    _expect(
      FileSystemEntity.typeSync(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'self-test ledger must be a regular file',
    );
    _expect(
      source.lengthSync() > 0 && source.lengthSync() <= _maximumCatalogBytes,
      'self-test ledger size is outside the limit',
    );
    return parse(
      source.readAsStringSync(),
      repositoryRoot: repositoryRoot,
      catalog: catalog,
    );
  }

  static TerminalDifferentialSelfTestLedger parse(
    String source, {
    required Directory repositoryRoot,
    required TerminalDifferentialBackendCatalog catalog,
  }) {
    _expect(
      utf8.encode(source).length <= _maximumCatalogBytes,
      'self-test ledger exceeds the encoded limit',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalDifferentialAdapterException(
        'invalid self-test ledger JSON: $error',
      );
    }
    final Map<String, Object?> root = _object(decoded, 'self-test ledger');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'input_hex',
      'expected_replies_hex',
      'captures',
    }, 'self-test ledger');
    _expect(
      root['format'] == 'dart-terminal-differential-self-tests',
      'unsupported self-test ledger format',
    );
    final int version = _integer(root['version'], 'self-test ledger.version');
    _expect(version == 1, 'unsupported self-test ledger version $version');
    final Uint8List input = _decodeHex(
      _text(root['input_hex'], 'self-test ledger.input_hex', 512),
      allowEmpty: false,
      maximumBytes: 256,
    );
    final Uint8List expectedReplies = _decodeHex(
      _text(
        root['expected_replies_hex'],
        'self-test ledger.expected_replies_hex',
        512,
      ),
      allowEmpty: false,
      maximumBytes: 256,
    );
    _expect(
      _encodeHex(input) == '1b5b3f31681b5b3f312470',
      'self-test input differs from the version 1 query',
    );
    _expect(
      _encodeHex(expectedReplies) == '1b5b3f313b312479',
      'self-test replies differ from the version 1 expectation',
    );
    final List<Object?> values = _array(
      root['captures'],
      'self-test ledger.captures',
    );
    _expect(
      values.length == catalog.profiles.length,
      'self-test ledger must cover every backend profile',
    );
    final List<TerminalDifferentialSelfTestCapture> captures =
        <TerminalDifferentialSelfTestCapture>[];
    String previousProfileId = '';
    for (int index = 0; index < values.length; index++) {
      final String context = 'self-test ledger.captures[$index]';
      final Map<String, Object?> map = _object(values[index], context);
      _expectKeys(map, const <String>{
        'profile_id',
        'status',
        'automation_status',
        'captured_on',
        'host_os',
        'host_version',
        'architecture',
        'executable_sha256',
        'config_sha256',
        'probe_path',
        'probe_sha256',
        'runner',
        'notes',
      }, context);
      final String profileId = _id(map['profile_id'], '$context.profile_id');
      _expect(
        previousProfileId.isEmpty || previousProfileId.compareTo(profileId) < 0,
        'self-test captures must be sorted and unique',
      );
      previousProfileId = profileId;
      final TerminalDifferentialBackendProfile profile = catalog.profile(
        profileId,
      );
      final String status = _id(map['status'], '$context.status');
      _expect(status == 'passed', '$context capture has not passed');
      final String automationStatus = _id(
        map['automation_status'],
        '$context.automation_status',
      );
      _expect(
        automationStatus == 'passed' ||
            automationStatus == 'activation-unavailable',
        '$context automation status is unknown',
      );
      _expect(
        automationStatus != 'activation-unavailable' ||
            profile.product == 'ghostty',
        '$context activation exception is only valid for Ghostty',
      );
      final String capturedOn = _text(
        map['captured_on'],
        '$context.captured_on',
        10,
      );
      _expect(
        RegExp(r'^20[0-9]{2}-[01][0-9]-[0-3][0-9]$').hasMatch(capturedOn) &&
            DateTime.tryParse(capturedOn) != null,
        '$context captured_on is not a date',
      );
      final String hostOs = _id(map['host_os'], '$context.host_os');
      final String architecture = _token(
        map['architecture'],
        '$context.architecture',
      );
      _expect(hostOs == profile.operatingSystem, '$context host OS differs');
      _expect(
        architecture == profile.architecture,
        '$context architecture differs',
      );
      final String executableSha256 = _sha256(
        map['executable_sha256'],
        '$context.executable_sha256',
      );
      _expect(
        profile.expectedExecutableSha256 == null ||
            executableSha256 == profile.expectedExecutableSha256,
        '$context executable SHA-256 differs from profile',
      );
      final String configSha256 = _sha256(
        map['config_sha256'],
        '$context.config_sha256',
      );
      _expect(
        configSha256 == profile.configSha256,
        '$context config SHA-256 differs from profile',
      );
      final String probePath = _relativePath(
        map['probe_path'],
        '$context.probe_path',
      );
      final String probeSha256 = _sha256(
        map['probe_sha256'],
        '$context.probe_sha256',
      );
      final File probe = File.fromUri(repositoryRoot.uri.resolve(probePath));
      _expect(probe.existsSync(), '$context probe does not exist');
      _expect(
        FileSystemEntity.typeSync(probe.path, followLinks: false) ==
            FileSystemEntityType.file,
        '$context probe must be a regular file',
      );
      _expect(probe.lengthSync() <= 32 * 1024, '$context probe is too large');
      _expect(
        terminalDifferentialSha256(probe.readAsBytesSync()) == probeSha256,
        '$context probe SHA-256 differs',
      );
      final TerminalDifferentialProbeResult probeResult =
          TerminalDifferentialProbeResult.load(probe);
      _expect(probeResult.status == 'ok', '$context probe did not pass');
      _expect(
        probeResult.terminalRows >= 4 && probeResult.terminalColumns >= 10,
        '$context probe dimensions differ',
      );
      _expect(
        _encodeHex(probeResult.replies) == _encodeHex(expectedReplies),
        '$context probe replies differ',
      );
      final String notes = _relativePath(map['notes'], '$context.notes');
      _expect(notes.startsWith('docs/'), '$context notes must be in docs');
      _expect(
        File.fromUri(repositoryRoot.uri.resolve(notes)).existsSync(),
        '$context notes do not exist',
      );
      captures.add(
        TerminalDifferentialSelfTestCapture(
          profileId: profileId,
          status: status,
          automationStatus: automationStatus,
          capturedOn: capturedOn,
          hostOs: hostOs,
          hostVersion: _token(map['host_version'], '$context.host_version'),
          architecture: architecture,
          executableSha256: executableSha256,
          configSha256: configSha256,
          probePath: probePath,
          probeSha256: probeSha256,
          runner: _id(map['runner'], '$context.runner'),
          notes: notes,
        ),
      );
    }
    return TerminalDifferentialSelfTestLedger(
      version: version,
      input: input,
      expectedReplies: expectedReplies,
      captures: List<TerminalDifferentialSelfTestCapture>.unmodifiable(
        captures,
      ),
    );
  }
}

final class TerminalDifferentialAdapterOptions {
  const TerminalDifferentialAdapterOptions({
    this.executable,
    this.appBundle,
    this.display,
  });

  final String? executable;
  final String? appBundle;
  final String? display;
}

final class TerminalDifferentialExternalAdapter {
  const TerminalDifferentialExternalAdapter({
    required this.repositoryRoot,
    this.launchTimeout = const Duration(seconds: 15),
  });

  final Directory repositoryRoot;
  final Duration launchTimeout;

  Future<TerminalDifferentialObservation> capture({
    required TerminalDifferentialBackendProfile profile,
    required TerminalDifferentialCase testCase,
    required TerminalDifferentialAdapterOptions options,
    File? rawProbeDestination,
  }) async {
    final String executable = options.executable ?? _defaultExecutable(profile);
    if (!executable.startsWith('/') || !File(executable).existsSync()) {
      throw const TerminalDifferentialAdapterException(
        'comparator executable is unavailable',
      );
    }
    final String executableSha256 = await _verifyExecutable(
      profile,
      executable,
    );
    final String architecture = await _hostArchitecture();
    _expect(
      Platform.operatingSystem == profile.operatingSystem,
      'comparator operating system differs from profile',
    );
    _expect(
      architecture == profile.architecture,
      'comparator architecture differs from profile',
    );
    final File config = File.fromUri(
      repositoryRoot.uri.resolve(profile.configPath),
    );
    final Directory temporary = Directory.systemTemp.createTempSync(
      'dart-terminal-differential-${profile.product}-',
    );
    int? launchedApplicationPid;
    try {
      final File result = File.fromUri(temporary.uri.resolve('probe.json'));
      final String probe = File.fromUri(
        repositoryRoot.uri.resolve('tool/terminal_differential_probe.dart'),
      ).absolute.path;
      final List<String> probeArguments = <String>[
        probe,
        '--result=${result.path}',
        '--input-hex=${_encodeHex(testCase.input)}',
        '--deadline-ms=1600',
        '--quiet-ms=100',
      ];
      final _Launch launch = _launch(
        profile: profile,
        executable: executable,
        config: config.absolute.path,
        testCase: testCase,
        probeArguments: probeArguments,
        options: options,
      );
      final Process process;
      try {
        process = await Process.start(
          launch.executable,
          launch.arguments,
          workingDirectory: repositoryRoot.absolute.path,
          environment: launch.environment,
          includeParentEnvironment: true,
        );
      } on ProcessException catch (error) {
        throw TerminalDifferentialAdapterException(
          'comparator launch failed with ${error.errorCode}',
        );
      }
      final _ProcessDrain stdoutDrain = _ProcessDrain(process.stdout);
      final _ProcessDrain stderrDrain = _ProcessDrain(process.stderr);
      bool exited = false;
      int? processExitCode;
      final Future<int> exitFuture = process.exitCode.then((int value) {
        exited = true;
        processExitCode = value;
        return value;
      });
      if (profile.launcher == TerminalDifferentialLauncher.macosOpenApp) {
        launchedApplicationPid = await _findApplicationProcess(
          executable: executable,
          resultPath: result.path,
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _activateMacApplication(
          processIdentifier: launchedApplicationPid,
          cacheDirectory: Directory.fromUri(
            temporary.uri.resolve('swift-module-cache/'),
          ),
        );
      }
      final DateTime deadline = DateTime.now().add(launchTimeout);
      while (!result.existsSync() && DateTime.now().isBefore(deadline)) {
        if (stdoutDrain.overflowed || stderrDrain.overflowed) {
          process.kill(ProcessSignal.sigkill);
          throw const TerminalDifferentialAdapterException(
            'comparator diagnostics exceeded the limit',
          );
        }
        if (exited) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (!result.existsSync()) {
        process.kill(ProcessSignal.sigkill);
        await _boundedExit(exitFuture);
        throw TerminalDifferentialAdapterException(
          exited
              ? 'comparator exited before probe capture ($processExitCode)'
              : 'comparator probe capture timed out',
        );
      }
      final TerminalDifferentialProbeResult probeResult =
          TerminalDifferentialProbeResult.load(result);
      if (!exited) {
        try {
          processExitCode = await exitFuture.timeout(
            const Duration(seconds: 3),
          );
          exited = true;
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await _boundedExit(exitFuture);
        }
      }
      await stdoutDrain.done;
      await stderrDrain.done;
      _expect(
        processExitCode == null || processExitCode == 0,
        'comparator exited unsuccessfully after probe capture',
      );
      _expect(
        probeResult.status == 'ok',
        'probe did not run on a terminal: ${probeResult.status}',
      );
      _expect(
        probeResult.terminalRows >= testCase.rows &&
            probeResult.terminalColumns >= testCase.columns,
        'comparator terminal dimensions are invalid',
      );
      if (rawProbeDestination != null) {
        rawProbeDestination.parent.createSync(recursive: true);
        rawProbeDestination.writeAsBytesSync(
          result.readAsBytesSync(),
          flush: true,
        );
      }
      return _observation(
        profile: profile,
        testCase: testCase,
        executableSha256: executableSha256,
        architecture: architecture,
        replies: probeResult.replies,
      );
    } finally {
      if (launchedApplicationPid != null) {
        Process.killPid(launchedApplicationPid, ProcessSignal.sigterm);
      }
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    }
  }

  _Launch _launch({
    required TerminalDifferentialBackendProfile profile,
    required String executable,
    required String config,
    required TerminalDifferentialCase testCase,
    required List<String> probeArguments,
    required TerminalDifferentialAdapterOptions options,
  }) {
    final int rows = math.max(testCase.rows, 4);
    final int columns = math.max(testCase.columns, 10);
    final Map<String, String> environment = <String, String>{
      'LANG': 'en_US.UTF-8',
      'LC_ALL': 'en_US.UTF-8',
    };
    switch (profile.launcher) {
      case TerminalDifferentialLauncher.direct:
        return _Launch(
          executable: executable,
          arguments: <String>[
            '--config=$config',
            '--start-as=hidden',
            '--override=initial_window_width=${columns}c',
            '--override=initial_window_height=${rows}c',
            Platform.resolvedExecutable,
            ...probeArguments,
          ],
          environment: environment,
        );
      case TerminalDifferentialLauncher.directX11:
        final String? display =
            options.display ?? Platform.environment['DISPLAY'];
        _expect(
          display != null && display.isNotEmpty && !_hasControl(display),
          'X11 display is unavailable',
        );
        environment['DISPLAY'] = display!;
        environment['XENVIRONMENT'] = config;
        return _Launch(
          executable: executable,
          arguments: <String>[
            '-geometry',
            '${columns}x$rows',
            '-u8',
            '-e',
            Platform.resolvedExecutable,
            ...probeArguments,
          ],
          environment: environment,
        );
      case TerminalDifferentialLauncher.macosOpenApp:
        final String appBundle =
            options.appBundle ?? _defaultAppBundle(profile);
        _expect(
          appBundle.startsWith('/') && Directory(appBundle).existsSync(),
          'comparator app bundle is unavailable',
        );
        return _Launch(
          executable: '/usr/bin/open',
          arguments: <String>[
            '-F',
            '-g',
            '-n',
            '-W',
            '-a',
            appBundle,
            '--args',
            '--config-default-files=false',
            '--config-file=$config',
            '--window-width=$columns',
            '--window-height=$rows',
            '-e',
            Platform.resolvedExecutable,
            ...probeArguments,
          ],
          environment: environment,
        );
    }
  }

  Future<String> _verifyExecutable(
    TerminalDifferentialBackendProfile profile,
    String executable,
  ) async {
    _expect(
      FileSystemEntity.typeSync(executable, followLinks: true) ==
          FileSystemEntityType.file,
      'comparator executable is not a regular file',
    );
    final File file = File(executable);
    final int length = file.lengthSync();
    _expect(
      length > 0 && length <= _maximumExecutableBytes,
      'comparator executable size is outside the limit',
    );
    final String hash = terminalDifferentialSha256(file.readAsBytesSync());
    _expect(
      profile.expectedExecutableSha256 == null ||
          profile.expectedExecutableSha256 == hash,
      'comparator executable SHA-256 differs from profile',
    );
    final _CommandResult version = await _runBoundedCommand(
      executable,
      profile.versionArguments,
    );
    _expect(version.exitCode == 0, 'comparator version command failed');
    _expect(
      version.output.contains(profile.versionContains),
      'comparator version differs from profile',
    );
    return hash;
  }

  Future<int> _findApplicationProcess({
    required String executable,
    required String resultPath,
  }) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final _CommandResult matches = await _runBoundedCommand(
        '/usr/bin/pgrep',
        <String>['-f', resultPath],
      );
      if (matches.exitCode == 0) {
        for (final String line in const LineSplitter().convert(
          matches.output,
        )) {
          final int? pid = int.tryParse(line.trim());
          if (pid == null || pid <= 0) continue;
          final _CommandResult command = await _runBoundedCommand(
            '/bin/ps',
            <String>['-p', '$pid', '-o', 'command='],
          );
          if (command.exitCode == 0 &&
              (command.output.trim() == executable ||
                  command.output.startsWith('$executable '))) {
            return pid;
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw const TerminalDifferentialAdapterException(
      'comparator application process was not found',
    );
  }

  Future<void> _activateMacApplication({
    required int processIdentifier,
    required Directory cacheDirectory,
  }) async {
    cacheDirectory.createSync(recursive: true);
    final String helper = File.fromUri(
      repositoryRoot.uri.resolve(
        'tool/terminal_differential_macos_activation.swift',
      ),
    ).absolute.path;
    final _CommandResult result = await _runBoundedCommand(
      '/usr/bin/xcrun',
      <String>['swift', helper, '$processIdentifier'],
      environment: <String, String>{
        'CLANG_MODULE_CACHE_PATH': cacheDirectory.path,
        'SWIFT_MODULECACHE_PATH': cacheDirectory.path,
      },
      timeout: const Duration(seconds: 10),
    );
    _expect(result.exitCode == 0, 'comparator application activation failed');
  }

  static Future<void> _boundedExit(Future<int> exitFuture) async {
    try {
      await exitFuture.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // The child was already killed. A leaked inherited descriptor must not
      // make the adapter wait without a bound.
    }
  }
}

final class _Launch {
  const _Launch({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

final class _ProcessDrain {
  _ProcessDrain(Stream<List<int>> source) {
    final Completer<void> completer = Completer<void>();
    _done = completer.future;
    source.listen(
      (List<int> chunk) {
        length += chunk.length;
        if (length > _maximumProcessDiagnosticBytes) overflowed = true;
      },
      onError: (Object _, StackTrace __) {
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
  }

  late final Future<void> _done;
  int length = 0;
  bool overflowed = false;

  Future<void> get done => _done.timeout(const Duration(seconds: 2));
}

final class TerminalDifferentialProbeResult {
  const TerminalDifferentialProbeResult({
    required this.status,
    required this.terminalRows,
    required this.terminalColumns,
    required this.replies,
  });

  final String status;
  final int terminalRows;
  final int terminalColumns;
  final Uint8List replies;

  static TerminalDifferentialProbeResult load(File source) {
    _expect(source.lengthSync() <= 32 * 1024, 'probe result is too large');
    final Map<String, Object?> root = _object(
      jsonDecode(source.readAsStringSync()),
      'probe result',
    );
    _expectKeys(root, const <String>{
      'format',
      'version',
      'status',
      'terminal_rows',
      'terminal_columns',
      'replies_hex',
    }, 'probe result');
    _expect(
      root['format'] == 'dart-terminal-differential-probe' &&
          root['version'] == 1,
      'unsupported probe result format',
    );
    final String status = _id(root['status'], 'probe result.status');
    _expect(
      status == 'ok' || status == 'not-a-terminal' || status == 'overflow',
      'unknown probe status',
    );
    return TerminalDifferentialProbeResult(
      status: status,
      terminalRows: _integer(
        root['terminal_rows'],
        'probe result.terminal_rows',
      ),
      terminalColumns: _integer(
        root['terminal_columns'],
        'probe result.terminal_columns',
      ),
      replies: _decodeHex(
        _text(
          root['replies_hex'],
          'probe result.replies_hex',
          8192,
          allowEmpty: true,
        ),
        allowEmpty: true,
        maximumBytes: TerminalDifferentialObservation.maximumRepliesBytes,
      ),
    );
  }
}

final class _CommandResult {
  const _CommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

Future<_CommandResult> _runBoundedCommand(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: true,
  );
  final BytesBuilder output = BytesBuilder(copy: false);
  bool overflowed = false;
  void collect(List<int> chunk) {
    if (overflowed) return;
    if (output.length + chunk.length > _maximumProcessDiagnosticBytes) {
      overflowed = true;
      process.kill(ProcessSignal.sigkill);
      return;
    }
    output.add(chunk);
  }

  final Future<void> stdoutDone = process.stdout
      .listen(collect)
      .asFuture<void>();
  final Future<void> stderrDone = process.stderr
      .listen(collect)
      .asFuture<void>();
  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    throw const TerminalDifferentialAdapterException(
      'comparator version command timed out',
    );
  }
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone])
      .timeout(const Duration(seconds: 2));
  _expect(!overflowed, 'comparator version output exceeded the limit');
  return _CommandResult(
    exitCode: exitCode,
    output: utf8.decode(output.takeBytes(), allowMalformed: true),
  );
}

TerminalDifferentialObservation _observation({
  required TerminalDifferentialBackendProfile profile,
  required TerminalDifferentialCase testCase,
  required String executableSha256,
  required String architecture,
  required Uint8List replies,
}) {
  final TerminalDifferentialCell blank = const TerminalDifferentialCell(
    text: '',
    width: 1,
    style: 0,
    foreground: 0,
    background: 0,
  );
  return TerminalDifferentialObservation(
    caseId: testCase.id,
    backendId: profile.id,
    provenance: TerminalDifferentialProvenance(
      product: profile.product,
      productVersion: profile.productVersion,
      implementationRevision: profile.implementationRevision,
      executableSha256: executableSha256,
      configId: profile.configId,
      configSha256: profile.configSha256,
      captureMethod: profile.captureMethod,
      operatingSystem: profile.operatingSystem,
      architecture: architecture,
    ),
    activeScreen: 'primary',
    rows: <TerminalDifferentialRow>[
      for (int row = 0; row < testCase.rows; row++)
        TerminalDifferentialRow(
          wrapped: false,
          cells: <TerminalDifferentialCell>[
            for (int column = 0; column < testCase.columns; column++) blank,
          ],
        ),
    ],
    cursor: const TerminalDifferentialCursor(
      row: 0,
      column: 0,
      visible: true,
      blinking: true,
      shape: 'block',
    ),
    modes: const <String, Object?>{
      'application_cursor': false,
      'application_keypad': false,
      'autowrap': true,
      'bracketed_paste': false,
      'horizontal_margins': false,
      'insert': false,
      'mouse_encoding': 'defaultEncoding',
      'mouse_tracking': 'disabled',
      'origin': false,
      'reverse_video': false,
    },
    replies: replies,
  );
}

Future<TerminalDifferentialCase> _readDriverRequest() async {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  await for (final List<int> chunk in stdin) {
    _expect(
      bytes.length + chunk.length <= _maximumDriverRequestBytes,
      'driver request exceeds the limit',
    );
    bytes.add(chunk);
  }
  final Map<String, Object?> root = _object(
    jsonDecode(utf8.decode(bytes.takeBytes(), allowMalformed: false)),
    'driver request',
  );
  _expectKeys(root, const <String>{
    'format',
    'version',
    'case',
  }, 'driver request');
  _expect(
    root['format'] == 'dart-terminal-differential-driver-request' &&
        root['version'] == 1,
    'unsupported driver request format',
  );
  final Map<String, Object?> value = _object(
    root['case'],
    'driver request.case',
  );
  _expectKeys(value, const <String>{
    'id',
    'input_hex',
    'rows',
    'columns',
    'initial_state',
    'fields',
  }, 'driver request.case');
  _expect(
    value['initial_state'] == 'power-on',
    'driver request initial state is unsupported',
  );
  final int rows = _integer(value['rows'], 'driver request.case.rows');
  final int columns = _integer(value['columns'], 'driver request.case.columns');
  _expect(
    rows > 0 && rows <= TerminalDifferentialManifest.maximumRows,
    'driver request rows are outside the limit',
  );
  _expect(
    columns > 0 && columns <= TerminalDifferentialManifest.maximumColumns,
    'driver request columns are outside the limit',
  );
  _expect(
    rows * columns <= TerminalDifferentialManifest.maximumCells,
    'driver request cells exceed the limit',
  );
  final List<Object?> fieldValues = _array(
    value['fields'],
    'driver request.case.fields',
  );
  _expect(fieldValues.isNotEmpty, 'driver request fields are empty');
  final List<TerminalDifferentialField> fields = <TerminalDifferentialField>[];
  int previous = -1;
  for (int index = 0; index < fieldValues.length; index++) {
    final TerminalDifferentialField field = _parseField(
      fieldValues[index],
      'driver request.case.fields[$index]',
    );
    _expect(field.index > previous, 'driver request fields are not canonical');
    previous = field.index;
    fields.add(field);
  }
  return TerminalDifferentialCase(
    id: _id(value['id'], 'driver request.case.id'),
    description: 'External comparator driver request.',
    inventoryIds: const <String>[],
    input: _decodeHex(
      _text(
        value['input_hex'],
        'driver request.case.input_hex',
        TerminalDifferentialManifest.maximumInputBytesPerCase * 2,
      ),
      allowEmpty: false,
      maximumBytes: TerminalDifferentialManifest.maximumInputBytesPerCase,
    ),
    rows: rows,
    columns: columns,
    fields: List<TerminalDifferentialField>.unmodifiable(fields),
    expectation: TerminalDifferentialExpectation.agree,
    gapOwner: null,
  );
}

TerminalDifferentialField _parseField(Object? value, String context) {
  final String field = _id(value, context);
  return switch (field) {
    'screen' => TerminalDifferentialField.screen,
    'text' => TerminalDifferentialField.text,
    'style' => TerminalDifferentialField.style,
    'color' => TerminalDifferentialField.color,
    'wrap' => TerminalDifferentialField.wrap,
    'cursor' => TerminalDifferentialField.cursor,
    'modes' => TerminalDifferentialField.modes,
    'replies' => TerminalDifferentialField.replies,
    _ => throw TerminalDifferentialAdapterException(
      '$context has unknown field $field',
    ),
  };
}

Future<String> _hostArchitecture() async {
  final _CommandResult result = await _runBoundedCommand(
    '/usr/bin/uname',
    const <String>['-m'],
  );
  _expect(result.exitCode == 0, 'could not determine host architecture');
  final String value = result.output.trim();
  _expect(
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value),
    'host architecture is not a safe token',
  );
  return value;
}

String _defaultExecutable(TerminalDifferentialBackendProfile profile) {
  return switch (profile.product) {
    'ghostty' => '/Applications/Ghostty.app/Contents/MacOS/ghostty',
    'kitty' => '/Applications/kitty.app/Contents/MacOS/kitty',
    'xterm' => _pathExecutable('xterm') ?? '',
    _ => '',
  };
}

String _defaultAppBundle(TerminalDifferentialBackendProfile profile) =>
    switch (profile.product) {
      'ghostty' => '/Applications/Ghostty.app',
      _ => '',
    };

String? _pathExecutable(String name) {
  final String? path = Platform.environment['PATH'];
  if (path == null) return null;
  for (final String directory in path.split(':')) {
    if (directory.isEmpty) continue;
    final String candidate = '$directory/$name';
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

Future<void> _runLiveSelfTest({
  required TerminalDifferentialBackendProfile profile,
  required TerminalDifferentialSelfTestCapture recordedCapture,
  required TerminalDifferentialAdapterOptions options,
}) async {
  final String executable = options.executable ?? _defaultExecutable(profile);
  _expect(executable.isNotEmpty, 'comparator executable is unavailable');
  final TerminalDifferentialCase testCase = TerminalDifferentialCase(
    id: 'adapter-query',
    description: 'DECCKM set and DECRQM reply adapter self-test.',
    inventoryIds: const <String>[],
    input: Uint8List.fromList(const <int>[
      0x1b,
      0x5b,
      0x3f,
      0x31,
      0x68,
      0x1b,
      0x5b,
      0x3f,
      0x31,
      0x24,
      0x70,
    ]),
    rows: 4,
    columns: 10,
    fields: const <TerminalDifferentialField>[
      TerminalDifferentialField.replies,
    ],
    expectation: TerminalDifferentialExpectation.agree,
    gapOwner: null,
  );
  final List<String> driverArguments = <String>[
    File.fromUri(
      Directory.current.uri.resolve('tool/terminal_differential_adapters.dart'),
    ).absolute.path,
    '--driver=${profile.id}',
    '--executable=$executable',
    if (options.appBundle != null) '--app-bundle=${options.appBundle}',
    if (options.display != null) '--display=${options.display}',
  ];
  final TerminalDifferentialDriverResult result =
      await const TerminalDifferentialSubprocessDriver(
        timeout: Duration(seconds: 25),
      ).run(
        executable: Platform.resolvedExecutable,
        arguments: driverArguments,
        testCase: testCase,
        workingDirectory: Directory.current.absolute.path,
      );
  if (result.status != TerminalDifferentialDriverStatus.ok) {
    if (recordedCapture.automationStatus == 'activation-unavailable' &&
        result.status == TerminalDifferentialDriverStatus.crashed) {
      throw const TerminalDifferentialAdapterException(
        'live self-test is unavailable because the macOS application '
        'could not become active in this automation session',
      );
    }
    throw TerminalDifferentialAdapterException(
      'live self-test driver status is ${result.status.name}',
    );
  }
  final TerminalDifferentialObservation expected =
      const DartTerminalDifferentialBackend().capture(testCase);
  final TerminalDifferentialComparison comparison =
      const TerminalDifferentialComparator().compare(
        testCase,
        expected,
        result.observation!,
      );
  _expect(comparison.accepted, 'live self-test reply differs');
  stdout.writeln(
    'TERMINAL_DIFFERENTIAL_ADAPTER_SELF_TEST_PASS '
    'backend=${profile.id} product=${profile.product} '
    'replies=${result.observation!.replies.length}',
  );
}

Future<void> _printAvailability(
  TerminalDifferentialBackendCatalog catalog,
) async {
  for (final TerminalDifferentialBackendProfile profile in catalog.profiles) {
    final String executable = _defaultExecutable(profile);
    final bool executableAvailable =
        executable.isNotEmpty && File(executable).existsSync();
    final bool appAvailable =
        profile.launcher != TerminalDifferentialLauncher.macosOpenApp ||
        Directory(_defaultAppBundle(profile)).existsSync();
    final bool displayAvailable =
        profile.launcher != TerminalDifferentialLauncher.directX11 ||
        (Platform.environment['DISPLAY']?.isNotEmpty ?? false);
    final bool available =
        executableAvailable && appAvailable && displayAvailable;
    stdout.writeln(
      'TERMINAL_DIFFERENTIAL_ADAPTER_AVAILABILITY '
      'backend=${profile.id} status=${available ? 'available' : 'unavailable'}',
    );
  }
}

final class _Cli {
  const _Cli({
    required this.mode,
    required this.profileId,
    required this.options,
  });

  final String mode;
  final String? profileId;
  final TerminalDifferentialAdapterOptions options;

  static _Cli parse(List<String> arguments) {
    String? mode;
    String? profileId;
    String? executable;
    String? appBundle;
    String? display;
    for (final String argument in arguments) {
      if (argument == '--check' || argument == '--availability') {
        _expect(mode == null, 'adapter mode is duplicated');
        mode = argument.substring(2);
      } else if (argument.startsWith('--driver=')) {
        _expect(mode == null, 'adapter mode is duplicated');
        mode = 'driver';
        profileId = argument.substring('--driver='.length);
      } else if (argument.startsWith('--live-self-test=')) {
        _expect(mode == null, 'adapter mode is duplicated');
        mode = 'live-self-test';
        profileId = argument.substring('--live-self-test='.length);
      } else if (argument.startsWith('--executable=')) {
        _expect(executable == null, 'executable option is duplicated');
        executable = argument.substring('--executable='.length);
      } else if (argument.startsWith('--app-bundle=')) {
        _expect(appBundle == null, 'app bundle option is duplicated');
        appBundle = argument.substring('--app-bundle='.length);
      } else if (argument.startsWith('--display=')) {
        _expect(display == null, 'display option is duplicated');
        display = argument.substring('--display='.length);
      } else {
        throw TerminalDifferentialAdapterException(
          'unknown adapter option $argument',
        );
      }
    }
    _expect(mode != null, 'adapter mode is required');
    _expect(
      (mode == 'driver' || mode == 'live-self-test') == (profileId != null),
      'adapter profile is inconsistent with mode',
    );
    for (final String? path in <String?>[executable, appBundle]) {
      _expect(
        path == null || (path.startsWith('/') && !_hasControl(path)),
        'adapter path must be absolute and control-free',
      );
    }
    _expect(display == null || !_hasControl(display), 'display is invalid');
    return _Cli(
      mode: mode!,
      profileId: profileId,
      options: TerminalDifferentialAdapterOptions(
        executable: executable,
        appBundle: appBundle,
        display: display,
      ),
    );
  }
}

Future<void> main(List<String> arguments) async {
  try {
    final _Cli cli = _Cli.parse(arguments);
    final Directory repositoryRoot = Directory.current.absolute;
    final TerminalDifferentialBackendCatalog catalog =
        TerminalDifferentialBackendCatalog.load(
          File.fromUri(
            repositoryRoot.uri.resolve(defaultTerminalDifferentialBackendsPath),
          ),
          repositoryRoot: repositoryRoot,
        );
    final TerminalDifferentialSelfTestLedger selfTests =
        TerminalDifferentialSelfTestLedger.load(
          File.fromUri(
            repositoryRoot.uri.resolve(
              defaultTerminalDifferentialSelfTestsPath,
            ),
          ),
          repositoryRoot: repositoryRoot,
          catalog: catalog,
        );
    switch (cli.mode) {
      case 'check':
        stdout.writeln(
          'TERMINAL_DIFFERENTIAL_ADAPTERS_PASS '
          'profiles=${catalog.profiles.length} '
          'captures=${selfTests.captures.length}',
        );
      case 'availability':
        await _printAvailability(catalog);
      case 'driver':
        final TerminalDifferentialCase testCase = await _readDriverRequest();
        final TerminalDifferentialObservation observation =
            await TerminalDifferentialExternalAdapter(
              repositoryRoot: repositoryRoot,
            ).capture(
              profile: catalog.profile(cli.profileId!),
              testCase: testCase,
              options: cli.options,
            );
        stdout.write(observation.encode());
      case 'live-self-test':
        await _runLiveSelfTest(
          profile: catalog.profile(cli.profileId!),
          recordedCapture: selfTests.capture(cli.profileId!),
          options: cli.options,
        );
      default:
        throw const TerminalDifferentialAdapterException(
          'unsupported adapter mode',
        );
    }
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_ADAPTER_FAIL $error');
    exitCode = 1;
  }
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw TerminalDifferentialAdapterException('$context must be an object');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    _expect(entry.key is String, '$context has a non-string key');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  if (value is! List<Object?>) {
    throw TerminalDifferentialAdapterException('$context must be an array');
  }
  return value;
}

String _text(
  Object? value,
  String context,
  int maximumCharacters, {
  bool allowEmpty = false,
}) {
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      value.length > maximumCharacters ||
      _hasControl(value)) {
    throw TerminalDifferentialAdapterException('$context is invalid text');
  }
  return value;
}

String _id(Object? value, String context) {
  final String result = _text(value, context, 128);
  _expect(
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(result),
    '$context is not a canonical id',
  );
  return result;
}

String _token(Object? value, String context) {
  final String result = _text(value, context, 128);
  _expect(
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(result),
    '$context is not a safe token',
  );
  return result;
}

String _argument(Object? value, String context) {
  final String result = _text(value, context, 256);
  _expect(!result.contains('\u0000'), '$context contains NUL');
  return result;
}

String _sha256(Object? value, String context) {
  final String result = _text(value, context, 64);
  _expect(
    RegExp(r'^[0-9a-f]{64}$').hasMatch(result),
    '$context is not SHA-256',
  );
  return result;
}

String _relativePath(Object? value, String context) {
  final String result = _text(value, context, 512);
  _expect(
    !result.startsWith('/') &&
        !result.contains('\\') &&
        result
            .split('/')
            .every(
              (String segment) =>
                  segment.isNotEmpty && segment != '.' && segment != '..',
            ),
    '$context is not a safe relative path',
  );
  return result;
}

int _integer(Object? value, String context) {
  if (value is! int) {
    throw TerminalDifferentialAdapterException('$context must be an integer');
  }
  return value;
}

void _expectKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = map.keys.toSet();
  if (actual.length == expected.length && actual.containsAll(expected)) return;
  throw TerminalDifferentialAdapterException('$context keys differ');
}

bool _hasControl(String value) {
  for (final int unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return true;
  }
  return false;
}

Uint8List _decodeHex(
  String source, {
  required bool allowEmpty,
  required int maximumBytes,
}) {
  _expect(source.length.isEven, 'hex input has an odd length');
  _expect(source.length ~/ 2 <= maximumBytes, 'hex input exceeds the limit');
  _expect(allowEmpty || source.isNotEmpty, 'hex input is empty');
  final Uint8List result = Uint8List(source.length ~/ 2);
  for (int index = 0; index < result.length; index++) {
    final int high = _hexNibble(source.codeUnitAt(index * 2));
    final int low = _hexNibble(source.codeUnitAt(index * 2 + 1));
    _expect(high >= 0 && low >= 0, 'hex input is invalid');
    result[index] = high << 4 | low;
  }
  return result;
}

int _hexNibble(int value) {
  if (value >= 0x30 && value <= 0x39) return value - 0x30;
  if (value >= 0x61 && value <= 0x66) return value - 0x61 + 10;
  return -1;
}

String _encodeHex(List<int> bytes) => <String>[
  for (final int byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join();

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDifferentialAdapterException(message);
}
