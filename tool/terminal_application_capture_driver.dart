import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_application_matrix.dart';
import 'terminal_differential_sha256.dart';

const String _driverId = 'developer-jit-product-pty';
const Duration _quietPeriod = Duration(milliseconds: 150);
const Duration _stepTimeout = Duration(seconds: 8);

Future<void> main(List<String> arguments) async {
  try {
    final _DriverOptions options = _DriverOptions.parse(arguments);
    final Map<String, Object?> request = _request(
      await utf8.decoder.bind(stdin).join(),
    );
    final String applicationId = request['application_id']! as String;
    final Map<String, Object?> scenario = Map<String, Object?>.from(
      request['scenario']! as Map<Object?, Object?>,
    );
    final _ApplicationFixture fixture = await _fixture(
      applicationId,
      options.artifactRoot,
    );
    final _CaptureResult capture = await _capture(fixture, scenario);
    final File rawEvidence = File(
      '${options.evidenceRoot.path}/${scenario['id']}.capture.json',
    );
    rawEvidence.parent.createSync(recursive: true);
    final String rawSource = capture.rawEvidence(
      applicationId: applicationId,
      scenarioId: scenario['id']! as String,
      fixture: fixture,
    );
    rawEvidence.writeAsStringSync(rawSource, flush: true);
    final TerminalApplicationObservation observation =
        TerminalApplicationObservation(
          applicationId: applicationId,
          scenarioId: scenario['id']! as String,
          driverId: _driverId,
          provenance: TerminalApplicationProvenance(
            product: fixture.product,
            productVersion: fixture.version,
            executableSha256: terminalDifferentialSha256(
              File(fixture.command.executable).readAsBytesSync(),
            ),
            configId: fixture.configId,
            configSha256: terminalDifferentialSha256(
              utf8.encode(fixture.canonicalConfig),
            ),
            captureMethod: 'developer-jit-product-pty-v1',
            operatingSystem: 'macos-26-6-2',
            architecture: 'arm64',
          ),
          capturedFields: _fields(scenario['required_fields']),
          outputBytes: capture.output.length,
          outputSha256: terminalDifferentialSha256(capture.output),
          rawEvidenceSha256: terminalDifferentialSha256(utf8.encode(rawSource)),
          checks: <TerminalApplicationCheckResult>[
            for (final String check in _strings(scenario['checks']))
              TerminalApplicationCheckResult(
                id: check,
                passed: capture.check(check, fixture.marker),
              ),
          ],
        );
    stdout.write(observation.encode());
  } on Object catch (error, stackTrace) {
    stderr.writeln('application capture failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

final class _DriverOptions {
  const _DriverOptions({
    required this.artifactRoot,
    required this.evidenceRoot,
  });

  final Directory artifactRoot;
  final Directory evidenceRoot;

  static _DriverOptions parse(List<String> arguments) {
    String? artifactRoot;
    String? evidenceRoot;
    for (final String argument in arguments) {
      if (argument.startsWith('--artifact-root=')) {
        artifactRoot = argument.substring('--artifact-root='.length);
      } else if (argument.startsWith('--evidence-root=')) {
        evidenceRoot = argument.substring('--evidence-root='.length);
      } else {
        throw ArgumentError.value(argument, 'argument', 'unknown option');
      }
    }
    if (artifactRoot == null ||
        evidenceRoot == null ||
        !artifactRoot.startsWith('/') ||
        !evidenceRoot.startsWith('/')) {
      throw ArgumentError(
        'usage: --artifact-root=/absolute/path --evidence-root=/absolute/path',
      );
    }
    return _DriverOptions(
      artifactRoot: Directory(artifactRoot),
      evidenceRoot: Directory(evidenceRoot),
    );
  }
}

Map<String, Object?> _request(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('request must be an object');
  }
  final Map<String, Object?> result = Map<String, Object?>.from(decoded);
  if (result['format'] != 'dart-terminal-application-driver-request' ||
      result['version'] != 1 ||
      result['application_id'] is! String ||
      result['scenario'] is! Map<Object?, Object?>) {
    throw const FormatException('unsupported request');
  }
  return result;
}

List<TerminalApplicationObservationField> _fields(Object? value) =>
    <TerminalApplicationObservationField>[
      for (final String name in _strings(value))
        TerminalApplicationObservationField.values.singleWhere(
          (TerminalApplicationObservationField field) => field.name == name,
        ),
    ];

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((Object? item) => item is! String)) {
    throw const FormatException('expected a string list');
  }
  return value.cast<String>();
}

final class _ApplicationFixture {
  const _ApplicationFixture({
    required this.product,
    required this.version,
    required this.configId,
    required this.canonicalConfig,
    required this.command,
    required this.marker,
    required this.activate,
    required this.exitInput,
    required this.cleanup,
  });

  final String product;
  final String version;
  final String configId;
  final String canonicalConfig;
  final PtyCommand command;
  final String marker;
  final Uint8List activate;
  final Uint8List exitInput;
  final Future<void> Function() cleanup;
}

Future<_ApplicationFixture> _fixture(
  String application,
  Directory artifacts,
) async {
  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-$application-',
  );
  try {
    switch (application) {
      case 'emacs':
        return _simpleFixture(
          product: 'emacs',
          version: '31.1',
          configId: 'emacs-terminal-ui-v1',
          executable: '${artifacts.path}/emacs/bin/emacs',
          arguments: const <String>[
            '-Q',
            '-nw',
            '--eval',
            '(progn (switch-to-buffer "*matrix*") '
                '(insert "DART_MATRIX_EMACS") '
                '(set-buffer-modified-p nil))',
          ],
          marker: 'DART_MATRIX_EMACS',
          exitInput: const <int>[0x18, 0x03],
          temporary: temporary,
        );
      case 'fzf':
        return _simpleFixture(
          product: 'fzf',
          version: '0.74.3',
          configId: 'fzf-filter-selection-v1',
          executable: '${artifacts.path}/fzf/fzf',
          arguments: const <String>[
            '--no-mouse',
            '--no-history',
            '--no-sort',
            '--prompt=matrix> ',
          ],
          marker: 'DART_MATRIX_FZF',
          activate: utf8.encode('DART_MATRIX_FZF'),
          exitInput: const <int>[0x0d],
          environment: const <String, String>{
            'FZF_DEFAULT_COMMAND':
                "/usr/bin/printf 'alpha\\nDART_MATRIX_FZF\\nomega\\n'",
          },
          temporary: temporary,
        );
      case 'lazygit':
        final Directory repository = Directory(
          '${temporary.path}/matrix-repository',
        )..createSync();
        await _runChecked('/usr/bin/git', const <String>[
          'init',
          '-q',
        ], repository);
        File('${repository.path}/DART_MATRIX_LAZYGIT.txt')
            .writeAsStringSync('controlled fixture\n');
        return _simpleFixture(
          product: 'lazygit',
          version: '0.65.0',
          configId: 'lazygit-repository-ui-v1',
          executable: '${artifacts.path}/lazygit/lazygit',
          arguments: const <String>['--use-config-file=/dev/null'],
          marker: 'DART_MATRIX_LAZYGIT',
          exitInput: const <int>[0x71],
          temporary: temporary,
          workingDirectory: repository.path,
        );
      case 'mosh':
        return await _moshFixture(artifacts, temporary);
      case 'ncurses':
        return _simpleFixture(
          product: 'ncurses',
          version: '6.6.20251230',
          configId: 'ncurses-resize-ui-v1',
          executable: '${artifacts.path}/ncurses-resize-fixture',
          marker: 'DART_MATRIX_NCURSES',
          exitInput: const <int>[0x71],
          temporary: temporary,
        );
      case 'neovim':
        return _simpleFixture(
          product: 'neovim',
          version: '0.12.2',
          configId: 'neovim-editing-ui-v1',
          executable: '${artifacts.path}/nvim/nvim-macos-arm64/bin/nvim',
          arguments: const <String>[
            '--clean',
            '-n',
            '-i',
            'NONE',
            '--cmd',
            'set noswapfile noshowmode noruler laststatus=0',
          ],
          marker: 'DART_MATRIX_NEOVIM',
          activate: Uint8List.fromList(<int>[
            0x69,
            ...utf8.encode('DART_MATRIX_NEOVIM'),
            0x1b,
          ]),
          exitInput: Uint8List.fromList(utf8.encode(':qa!\r')),
          temporary: temporary,
        );
      case 'ssh':
        return await _sshFixture(temporary);
      case 'tmux':
        return await _tmuxFixture(artifacts, temporary);
      default:
        throw ArgumentError.value(application, 'application', 'unsupported');
    }
  } on Object {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    rethrow;
  }
}

_ApplicationFixture _simpleFixture({
  required String product,
  required String version,
  required String configId,
  required String executable,
  required String marker,
  required List<int> exitInput,
  required Directory temporary,
  List<String> arguments = const <String>[],
  List<int> activate = const <int>[],
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) {
  final Map<String, String> fullEnvironment = <String, String>{
    ..._baseEnvironment,
    ...environment,
  };
  final PtyCommand command = PtyCommand(
    executable: executable,
    arguments: arguments,
    environment: fullEnvironment,
    includeParentEnvironment: false,
    workingDirectory: workingDirectory ?? temporary.path,
  );
  return _ApplicationFixture(
    product: product,
    version: version,
    configId: configId,
    canonicalConfig: _canonicalConfig(command, configId),
    command: command,
    marker: marker,
    activate: Uint8List.fromList(activate),
    exitInput: Uint8List.fromList(exitInput),
    cleanup: () async {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    },
  );
}

Future<_ApplicationFixture> _tmuxFixture(
  Directory artifacts,
  Directory temporary,
) async {
  final String executable = '${artifacts.path}/tmux/bin/tmux';
  final String socket = 'dart-terminal-matrix-${pid.toRadixString(16)}';
  final PtyCommand command = PtyCommand(
    executable: executable,
    arguments: <String>[
      '-L',
      socket,
      '-f',
      '/dev/null',
      'new-session',
      '/bin/zsh',
      '-f',
    ],
    environment: _baseEnvironment,
    includeParentEnvironment: false,
    workingDirectory: temporary.path,
  );
  return _ApplicationFixture(
    product: 'tmux',
    version: '3.6b',
    configId: 'tmux-session-resize-v1',
    canonicalConfig: _canonicalConfig(command, 'tmux-session-resize-v1'),
    command: command,
    marker: 'DART_MATRIX_TMUX',
    activate: Uint8List.fromList(utf8.encode("printf 'DART_MATRIX_TMUX\\n'\r")),
    exitInput: Uint8List.fromList(const <int>[0x02, 0x64]),
    cleanup: () async {
      await Process.run(
        executable,
        <String>['-L', socket, 'kill-server'],
        environment: _baseEnvironment,
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 3));
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    },
  );
}

Future<_ApplicationFixture> _moshFixture(
  Directory artifacts,
  Directory temporary,
) async {
  final String directory =
      '${artifacts.path}/mosh-expanded/package/edu.mit.mosh.mosh.pkg/'
      'Payload/local/bin';
  final String serverPath = '$directory/mosh-server';
  final String clientPath = '$directory/mosh-client';
  final Process server = await Process.start(
    serverPath,
    const <String>[
      'new',
      '-s',
      '-c',
      '256',
      '-p',
      '61000:61099',
      '-l',
      'LANG=en_US.UTF-8',
      '--',
      '/usr/bin/env',
      'PS1=matrix% ',
      '/bin/zsh',
      '-f',
    ],
    workingDirectory: temporary.path,
    environment: _baseEnvironment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  final Completer<String> connect = Completer<String>();
  final StringBuffer diagnostics = StringBuffer();
  final StreamSubscription<String> outputSubscription = server.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((String line) {
        if (line.startsWith('MOSH CONNECT ') && !connect.isCompleted) {
          connect.complete(line);
        }
      });
  final StreamSubscription<String> diagnosticSubscription = server.stderr
      .transform(utf8.decoder)
      .listen(diagnostics.write);
  final String line;
  try {
    line = await connect.future.timeout(_stepTimeout);
  } on Object {
    server.kill(ProcessSignal.sigkill);
    throw StateError('mosh-server did not publish a connection: $diagnostics');
  }
  final List<String> parts = line.split(' ');
  if (parts.length != 4 || int.tryParse(parts[2]) == null) {
    server.kill(ProcessSignal.sigkill);
    throw StateError('mosh-server returned malformed connection metadata');
  }
  final Map<String, String> environment = <String, String>{
    ..._baseEnvironment,
    'MOSH_KEY': parts[3],
  };
  final PtyCommand command = PtyCommand(
    executable: clientPath,
    arguments: <String>['127.0.0.1', parts[2]],
    environment: environment,
    includeParentEnvironment: false,
    workingDirectory: temporary.path,
  );
  return _ApplicationFixture(
    product: 'mosh',
    version: '1.4.0',
    configId: 'mosh-local-session-v1',
    canonicalConfig: _canonicalConfig(
      PtyCommand(
        executable: clientPath,
        arguments: const <String>['127.0.0.1', '<SERVER_PORT>'],
        environment: <String, String>{..._baseEnvironment, 'MOSH_KEY': '<KEY>'},
        includeParentEnvironment: false,
        workingDirectory: '/private/tmp',
      ),
      'mosh-local-session-v1',
    ),
    command: command,
    marker: 'DART_MATRIX_MOSH',
    activate: Uint8List.fromList(utf8.encode("printf 'DART_MATRIX_MOSH\\n'\r")),
    exitInput: Uint8List.fromList(utf8.encode('exit\r')),
    cleanup: () async {
      server.kill(ProcessSignal.sigkill);
      await server.exitCode.timeout(const Duration(seconds: 3));
      await outputSubscription.cancel();
      await diagnosticSubscription.cancel();
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    },
  );
}

Future<_ApplicationFixture> _sshFixture(Directory temporary) async {
  final String hostKey = '${temporary.path}/host_ed25519';
  final String clientKey = '${temporary.path}/client_ed25519';
  await _runChecked('/usr/bin/ssh-keygen', <String>[
    '-q',
    '-t',
    'ed25519',
    '-N',
    '',
    '-f',
    hostKey,
  ], temporary);
  await _runChecked('/usr/bin/ssh-keygen', <String>[
    '-q',
    '-t',
    'ed25519',
    '-N',
    '',
    '-f',
    clientKey,
  ], temporary);
  final File authorizedKeys = File('${temporary.path}/authorized_keys')
    ..writeAsStringSync(File('$clientKey.pub').readAsStringSync());
  await _runChecked('/bin/chmod', <String>[
    '600',
    authorizedKeys.path,
  ], temporary);
  final int port = await _unusedLoopbackPort();
  final String user = Platform.environment['USER'] ?? '';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(user)) {
    throw StateError('current account name is unsafe for ssh fixture');
  }
  final File configuration = File('${temporary.path}/sshd_config')
    ..writeAsStringSync(
      'Port $port\n'
      'ListenAddress 127.0.0.1\n'
      'HostKey $hostKey\n'
      'AuthorizedKeysFile ${authorizedKeys.path}\n'
      'PidFile ${temporary.path}/sshd.pid\n'
      'StrictModes no\n'
      'PasswordAuthentication no\n'
      'KbdInteractiveAuthentication no\n'
      'PubkeyAuthentication yes\n'
      'UsePAM no\n'
      'PermitRootLogin no\n'
      'AllowUsers $user\n'
      'LogLevel ERROR\n',
    );
  final Process server = await Process.start(
    '/usr/sbin/sshd',
    <String>['-D', '-e', '-f', configuration.path],
    workingDirectory: temporary.path,
    runInShell: false,
  );
  final StringBuffer diagnostics = StringBuffer();
  final StreamSubscription<String> stdoutSubscription = server.stdout
      .transform(utf8.decoder)
      .listen((String _) {});
  final StreamSubscription<String> stderrSubscription = server.stderr
      .transform(utf8.decoder)
      .listen(diagnostics.write);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final int? earlyExit = await _completedExitCode(server);
  if (earlyExit != null) {
    throw StateError('sshd exited $earlyExit before capture: $diagnostics');
  }
  final Map<String, String> environment = <String, String>{
    ..._baseEnvironment,
    'PS1': 'matrix% ',
  };
  final PtyCommand command = PtyCommand(
    executable: '/usr/bin/ssh',
    arguments: <String>[
      '-tt',
      '-F',
      '/dev/null',
      '-o',
      'BatchMode=yes',
      '-o',
      'IdentitiesOnly=yes',
      '-o',
      'LogLevel=ERROR',
      '-o',
      'StrictHostKeyChecking=no',
      '-o',
      'UserKnownHostsFile=/dev/null',
      '-i',
      clientKey,
      '-p',
      '$port',
      '-l',
      user,
      '127.0.0.1',
      '/usr/bin/env',
      'PS1=matrix% ',
      '/bin/zsh',
      '-f',
    ],
    environment: environment,
    includeParentEnvironment: false,
    workingDirectory: temporary.path,
  );
  return _ApplicationFixture(
    product: 'openssh',
    version: '10.3p1-libressl-3.3.6',
    configId: 'ssh-local-pty-v1',
    canonicalConfig: _canonicalConfig(
      PtyCommand(
        executable: '/usr/bin/ssh',
        arguments: const <String>[
          '-tt',
          '-F',
          '/dev/null',
          '-o',
          'BatchMode=yes',
          '-o',
          'IdentitiesOnly=yes',
          '-o',
          'LogLevel=ERROR',
          '-o',
          'StrictHostKeyChecking=no',
          '-o',
          'UserKnownHostsFile=/dev/null',
          '-i',
          '<CLIENT_KEY>',
          '-p',
          '<SERVER_PORT>',
          '-l',
          '<USER>',
          '127.0.0.1',
          '/usr/bin/env',
          'PS1=matrix% ',
          '/bin/zsh',
          '-f',
        ],
        environment: _baseEnvironment,
        includeParentEnvironment: false,
        workingDirectory: '/private/tmp',
      ),
      'ssh-local-pty-v1',
    ),
    command: command,
    marker: 'DART_MATRIX_SSH',
    activate: Uint8List.fromList(utf8.encode("printf 'DART_MATRIX_SSH\\n'\r")),
    exitInput: Uint8List.fromList(utf8.encode('exit\r')),
    cleanup: () async {
      server.kill(ProcessSignal.sigterm);
      try {
        await server.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        server.kill(ProcessSignal.sigkill);
        await server.exitCode.timeout(const Duration(seconds: 3));
      }
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    },
  );
}

Future<_CaptureResult> _capture(
  _ApplicationFixture fixture,
  Map<String, Object?> scenario,
) async {
  final int rows = scenario['rows']! as int;
  final int columns = scenario['columns']! as int;
  final int maximumOutputBytes = scenario['maximum_output_bytes']! as int;
  final List<int> output = <int>[];
  final List<_CaptureSample> samples = <_CaptureSample>[];
  final List<_ResizeEvidence> resizes = <_ResizeEvidence>[];
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: rows,
    columns: columns,
  );
  PtyProcess? process;
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List reply) {
      final PtyProcess? target = process;
      return target != null && target.write(reply) == PtyWriteResult.accepted;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  final Completer<void> outputDone = Completer<void>();
  Object? outputFailure;
  var exited = false;
  StreamSubscription<Uint8List>? subscription;
  PtyExit? exit;
  try {
    process = await startPty(
      fixture.command,
      initialSize: PtySize(rows: rows, columns: columns),
      readHighWaterBytes: maximumOutputBytes,
      readLowWaterBytes: maximumOutputBytes ~/ 2,
      writeCapacityBytes: 64 * 1024,
    ).timeout(_stepTimeout);
    subscription = process.output.listen(
      (Uint8List chunk) {
        if (output.length + chunk.length > maximumOutputBytes) {
          outputFailure = StateError('PTY output exceeded scenario bound');
          process!.forceClose();
          return;
        }
        output.addAll(chunk);
        parser.parse(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        outputFailure = error;
        if (!outputDone.isCompleted) {
          outputDone.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!outputDone.isCompleted) outputDone.complete();
      },
    );
    await _waitForQuiet(output, minimumBytes: 1);
    samples.add(_sample('initial', output.length, screens, sink));
    if (fixture.activate.isNotEmpty) {
      _write(process, fixture.activate);
      await _waitForQuiet(output, minimumBytes: output.length + 1);
    }
    samples.add(_sample('activated', output.length, screens, sink));
    await _resize(
      process,
      screens,
      output,
      rows: rows + 3,
      columns: columns + 7,
      resizes: resizes,
    );
    samples.add(_sample('resized', output.length, screens, sink));
    await _resize(
      process,
      screens,
      output,
      rows: rows,
      columns: columns,
      resizes: resizes,
    );
    if (fixture.exitInput.isNotEmpty) _write(process, fixture.exitInput);
    exit = await process.exit.timeout(_stepTimeout);
    exited = true;
    await outputDone.future.timeout(_stepTimeout);
    if (outputFailure case final Object error) throw error;
    parser.finish();
    samples.add(_sample('exited', output.length, screens, sink));
  } finally {
    if (!exited) {
      try {
        process?.forceClose();
      } on Object {
        // A start failure owns no live PTY.
      }
    }
    await subscription?.cancel();
    if (process case final PtyProcess target) {
      try {
        await target.dispose().timeout(_stepTimeout);
      } on Object {
        // The original capture failure is more actionable.
      }
    }
    await fixture.cleanup();
  }
  if (output.isEmpty) {
    throw StateError('application capture is incomplete');
  }
  return _CaptureResult(
    output: Uint8List.fromList(output),
    samples: samples,
    resizes: resizes,
    exit: exit,
    sink: sink,
    screens: screens,
  );
}

Future<void> _resize(
  PtyProcess process,
  TerminalScreenSet screens,
  List<int> output, {
  required int rows,
  required int columns,
  required List<_ResizeEvidence> resizes,
}) async {
  final int before = output.length;
  screens.resize(rows: rows, columns: columns);
  try {
    process.resize(PtySize(rows: rows, columns: columns));
  } on StateError catch (error) {
    throw StateError('PTY resize failed after $before bytes ($error)');
  }
  await _waitForQuiet(output, minimumBytes: before);
  resizes.add(
    _ResizeEvidence(
      rows: rows,
      columns: columns,
      outputBytesBefore: before,
      outputBytesAfter: output.length,
      screenRows: screens.activeScreen.rows,
      screenColumns: screens.activeScreen.columns,
    ),
  );
}

_CaptureSample _sample(
  String stage,
  int outputBytes,
  TerminalScreenSet screens,
  TerminalScreenParserSink sink,
) => _CaptureSample(
  stage: stage,
  outputBytes: outputBytes,
  snapshot: const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  ),
  cursorBounded:
      screens.activeScreen.cursorRow >= 0 &&
      screens.activeScreen.cursorRow < screens.activeScreen.rows &&
      screens.activeScreen.cursorColumn >= 0 &&
      screens.activeScreen.cursorColumn < screens.activeScreen.columns,
);

final class _CaptureSample {
  const _CaptureSample({
    required this.stage,
    required this.outputBytes,
    required this.snapshot,
    required this.cursorBounded,
  });

  final String stage;
  final int outputBytes;
  final String snapshot;
  final bool cursorBounded;

  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage,
    'output_bytes': outputBytes,
    'snapshot_sha256': terminalDifferentialSha256(utf8.encode(snapshot)),
    'cursor_bounded': cursorBounded,
    'snapshot': snapshot,
  };
}

final class _ResizeEvidence {
  const _ResizeEvidence({
    required this.rows,
    required this.columns,
    required this.outputBytesBefore,
    required this.outputBytesAfter,
    required this.screenRows,
    required this.screenColumns,
  });

  final int rows;
  final int columns;
  final int outputBytesBefore;
  final int outputBytesAfter;
  final int screenRows;
  final int screenColumns;

  bool get observed => screenRows == rows && screenColumns == columns;

  Map<String, Object?> toJson() => <String, Object?>{
    'rows': rows,
    'columns': columns,
    'output_bytes_before': outputBytesBefore,
    'output_bytes_after': outputBytesAfter,
    'screen_rows': screenRows,
    'screen_columns': screenColumns,
  };
}

final class _CaptureResult {
  const _CaptureResult({
    required this.output,
    required this.samples,
    required this.resizes,
    required this.exit,
    required this.sink,
    required this.screens,
  });

  final Uint8List output;
  final List<_CaptureSample> samples;
  final List<_ResizeEvidence> resizes;
  final PtyExit exit;
  final TerminalScreenParserSink sink;
  final TerminalScreenSet screens;

  bool check(String id, String marker) => switch (id) {
    'clean-exit' => exit.exitCode == 0 && exit.signal == null,
    'cursor-bounded' => samples.every(
      (_CaptureSample sample) => sample.cursorBounded,
    ),
    'marker-visible' => samples.any(
      (_CaptureSample sample) => sample.snapshot.contains(marker),
    ),
    'parser-clean' =>
      sink.unsupportedControlCount == 0 &&
          sink.unsupportedSequenceCount == 0 &&
          sink.cancelCount == 0 &&
          sink.limitCount == 0 &&
          sink.malformedCount == 0 &&
          sink.incompleteCount == 0,
    'primary-restored' =>
      screens.activeKind == TerminalScreenKind.primary &&
          !screens.mode1049Active,
    'resize-observed' =>
      resizes.length == 2 &&
          resizes.every((_ResizeEvidence resize) => resize.observed),
    _ => throw StateError('unsupported semantic check $id'),
  };

  String rawEvidence({
    required String applicationId,
    required String scenarioId,
    required _ApplicationFixture fixture,
  }) =>
      '${jsonEncode(<String, Object?>{
        'format': 'dart-terminal-application-raw-evidence',
        'version': 1,
        'application_id': applicationId,
        'scenario_id': scenarioId,
        'capture_method': 'developer-jit-product-pty-v1',
        'product': fixture.product,
        'product_version': fixture.version,
        'output_bytes': output.length,
        'output_sha256': terminalDifferentialSha256(output),
        'output_base64': base64Encode(output),
        'samples': <Object?>[for (final _CaptureSample sample in samples) sample.toJson()],
        'resizes': <Object?>[for (final _ResizeEvidence resize in resizes) resize.toJson()],
        'exit': <String, Object?>{'exit_code': exit.exitCode, 'signal': exit.signal},
        'parser': <String, Object?>{'unsupported_controls': sink.unsupportedControlCount, 'unsupported_sequences': sink.unsupportedSequenceCount, 'cancel': sink.cancelCount, 'limit': sink.limitCount, 'malformed': sink.malformedCount, 'incomplete': sink.incompleteCount, 'replies_accepted': sink.acceptedReplyCount, 'replies_rejected': sink.rejectedReplyCount},
      })}\n';
}

const Map<String, String> _baseEnvironment = <String, String>{
  'COLORTERM': 'truecolor',
  'HOME': '/private/tmp',
  'LANG': 'en_US.UTF-8',
  'LC_ALL': 'en_US.UTF-8',
  'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  'TERM': 'xterm-256color',
};

String _canonicalConfig(PtyCommand command, String configId) {
  final Map<String, String> environment = Map<String, String>.from(
    command.environment,
  );
  environment.remove('MOSH_KEY');
  return '${jsonEncode(<String, Object?>{'config_id': configId, 'executable_basename': command.executable.split('/').last, 'arguments': command.arguments, 'environment': environment, 'working_directory': command.workingDirectory == null ? null : '<FIXTURE>'})}\n';
}

Future<void> _waitForQuiet(List<int> bytes, {required int minimumBytes}) async {
  final Stopwatch timeout = Stopwatch()..start();
  var previousLength = -1;
  while (timeout.elapsed < _stepTimeout) {
    await Future<void>.delayed(_quietPeriod);
    if (bytes.length >= minimumBytes && bytes.length == previousLength) return;
    previousLength = bytes.length;
  }
  throw TimeoutException('PTY output did not become quiet');
}

void _write(PtyProcess process, Uint8List bytes) {
  if (process.write(bytes) != PtyWriteResult.accepted) {
    throw StateError('application input was backpressured');
  }
}

Future<void> _runChecked(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    runInShell: false,
  ).timeout(_stepTimeout);
  if (result.exitCode != 0) {
    throw StateError('$executable fixture setup exited ${result.exitCode}');
  }
}

Future<int> _unusedLoopbackPort() async {
  final ServerSocket socket = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = socket.port;
  await socket.close();
  return port;
}

Future<int?> _completedExitCode(Process process) async {
  try {
    return await process.exitCode.timeout(const Duration(milliseconds: 1));
  } on TimeoutException {
    return null;
  }
}
