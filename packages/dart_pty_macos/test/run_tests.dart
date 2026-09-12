import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_pty_macos/testing.dart';

typedef TestBody = FutureOr<void> Function();

var _failures = 0;

@Native<Uint32 Function()>(
  symbol: 'dpty_abi_version',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _abiVersion();

@Native<Uint64 Function()>(
  symbol: 'dpty_debug_live_session_count',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _liveSessionCount();

Future<void> _test(String name, TestBody body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    ++_failures;
    stderr.writeln('FAIL $name: $error');
    stderr.writeln(stackTrace);
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('expectation failed: $description');
  }
}

T _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}');
  }
  throw StateError('expected $T but no error was thrown');
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 &&
      arguments.single == '--closed-stdin-pty-helper') {
    await stdin.drain<void>();
    final PtyProcess process = await startPty(
      PtyCommand(executable: '/usr/bin/tty', includeParentEnvironment: false),
    );
    final Future<List<int>> output = process.output
        .expand<int>((Uint8List bytes) => bytes)
        .toList();
    final PtyExit exit = await process.exit.timeout(const Duration(seconds: 3));
    final String text = utf8.decode(await output);
    await process.dispose();
    if (exit.exitCode != 0 || !text.startsWith('/dev/ttys')) {
      throw StateError('closed-stdin PTY is not a controlling terminal');
    }
    stdout.writeln('CLOSED_STDIN_PTY_PASS');
    return;
  }
  await _test('public command and queue validation', () async {
    _expectThrows<ArgumentError>(() => PtyCommand(executable: 'zsh'));
    _expectThrows<RangeError>(
      () => PtyCommand(executable: '/bin/zsh', readBatchBytes: 0),
    );
    _expectThrows<RangeError>(
      () => PtyCommand(executable: '/bin/zsh', readBatchBytes: 64 * 1024 + 1),
    );
    _expectThrows<RangeError>(
      () => PtyCommand(executable: '/bin/zsh', readBatchesPerEventLoopTurn: -1),
    );
    _expectThrows<RangeError>(
      () => PtyCommand(executable: '/bin/zsh', readBatchesPerEventLoopTurn: 9),
    );
    _expect(
      PtyCommand(executable: '/bin/zsh').readBatchBytes == 64 * 1024 &&
          PtyCommand(executable: '/bin/zsh').readBatchesPerEventLoopTurn == 0 &&
          PtyCommand(
                executable: '/bin/zsh',
                readBatchBytes: 4 * 1024,
                readBatchesPerEventLoopTurn: 4,
              ).readBatchBytes ==
              4 * 1024 &&
          PtyCommand(
                executable: '/bin/zsh',
                readBatchesPerEventLoopTurn: 4,
              ).readBatchesPerEventLoopTurn ==
              4,
      'default and consumer-specific read scheduling is retained',
    );
    _expectThrows<ArgumentError>(
      () => PtyCommand(
        executable: '/bin/zsh',
        environment: <String, String>{'BAD=KEY': 'value'},
      ),
    );
    final FakePtyBackend backend = FakePtyBackend();
    await _expectThrowsAsync<ArgumentError>(() {
      return startPty(
        PtyCommand(executable: '/bin/sh'),
        backend: backend,
        readHighWaterBytes: 10,
        readLowWaterBytes: 10,
      );
    });
  });

  await _test('deterministic fake backend lifecycle', () async {
    final FakePtyBackend backend = FakePtyBackend(autoExitOnClose: false);
    final PtyCommand command = PtyCommand(
      executable: '/bin/zsh',
      arguments: const <String>['-f', '-i'],
      environment: const <String, String>{'TERM': 'xterm-256color'},
      workingDirectory: '/private/tmp',
      loginShell: true,
    );
    final PtyProcess process = await startPty(
      command,
      backend: backend,
      initialSize: const PtySize(rows: 30, columns: 100),
      writeCapacityBytes: 4,
    );
    final FakePtyProcess fake = backend.processes.single;
    final List<int> output = <int>[];
    final StreamSubscription<Uint8List> subscription = process.output.listen(
      output.addAll,
    );
    _expect(process.pid == 4000, 'fake PID');
    _expect(identical(backend.commands.single, command), 'command recorded');
    final PtyProcessSnapshot idleSnapshot = process.processSnapshot();
    _expect(
      idleSnapshot.isAvailable &&
          idleSnapshot.childPid == process.pid &&
          idleSnapshot.childProcessGroup == process.pid &&
          idleSnapshot.foregroundProcessGroup == process.pid &&
          !idleSnapshot.hasDistinctForegroundProcess &&
          idleSnapshot.hasTerminalAttributes &&
          idleSnapshot.terminalEchoEnabled == true &&
          !idleSnapshot.hasExited,
      'fake idle process snapshot is available',
    );
    fake.terminalEchoEnabled = false;
    final PtyProcessSnapshot echoDisabledSnapshot = process.processSnapshot();
    _expect(
      echoDisabledSnapshot.hasTerminalAttributes &&
          echoDisabledSnapshot.terminalEchoEnabled == false,
      'fake terminal echo state is content-free and typed',
    );
    fake.terminalAttributesSystemError = 25;
    final PtyProcessSnapshot terminalUnavailableSnapshot = process
        .processSnapshot();
    _expect(
      !terminalUnavailableSnapshot.hasTerminalAttributes &&
          terminalUnavailableSnapshot.terminalEchoEnabled == null &&
          terminalUnavailableSnapshot.terminalAttributesSystemError == 25,
      'fake terminal attribute failure remains typed and unavailable',
    );
    fake
      ..terminalEchoEnabled = true
      ..terminalAttributesSystemError = 0;
    fake.foregroundProcessGroup = process.pid + 1;
    _expect(
      process.processSnapshot().hasDistinctForegroundProcess,
      'fake distinct foreground process is classified',
    );
    fake.foregroundProcessGroupSystemError = 6;
    final PtyProcessSnapshot unavailableSnapshot = process.processSnapshot();
    _expect(
      !unavailableSnapshot.isAvailable &&
          unavailableSnapshot.foregroundProcessGroup == null &&
          unavailableSnapshot.foregroundProcessGroupSystemError == 6 &&
          !unavailableSnapshot.hasDistinctForegroundProcess,
      'fake foreground lookup failure remains typed and unavailable',
    );
    fake
      ..foregroundProcessGroup = process.pid
      ..foregroundProcessGroupSystemError = 0;
    _expect(
      process.write(Uint8List.fromList(<int>[1, 2, 3, 4])) ==
          PtyWriteResult.accepted,
      'bounded write accepted',
    );
    _expect(
      process.write(Uint8List.fromList(<int>[5])) ==
          PtyWriteResult.backpressured,
      'bounded write rejects overflow',
    );
    fake.drainWrites();
    process.resize(const PtySize(rows: 43, columns: 132));
    process.sendSignal(PtySignal.interrupt);
    fake.emitOutput(<int>[0xe2]);
    fake.emitOutput(<int>[0x82, 0xac]);
    process.close(gracePeriod: const Duration(milliseconds: 250));
    fake.finish(exitCode: 37);
    final PtyExit exit = await process.exit;
    await subscription.cancel();
    await process.dispose();
    _expect(exit.exitCode == 37 && exit.signal == null, 'fake exit');
    _expect(output.length == 3, 'raw split bytes are preserved');
    _expect(fake.sizes.last.rows == 43, 'resize recorded');
    _expect(fake.signals.single == PtySignal.interrupt, 'signal recorded');
    _expect(
      fake.closeGracePeriods.single == const Duration(milliseconds: 250),
      'close grace recorded',
    );
    _expect(process.finalStats?.hasExited ?? false, 'fake stats finalized');
  });

  await _test('fake force close remains valid while closing', () async {
    final FakePtyBackend backend = FakePtyBackend(
      autoExitOnClose: false,
      autoExitOnForceClose: false,
    );
    final PtyProcess process = await startPty(
      PtyCommand(executable: '/bin/sh'),
      backend: backend,
    );
    final FakePtyProcess fake = backend.processes.single;
    process.close(gracePeriod: const Duration(seconds: 60));
    process.forceClose();
    process.forceClose();
    _expect(
      fake.forceCloseRequests == 2,
      'repeated force requests are accepted after graceful close',
    );
    fake.finish(exitCode: 137, signal: 9);
    final PtyExit exit = await process.exit;
    process.forceClose();
    await process.dispose();
    _expect(
      fake.forceCloseRequests == 2,
      'force close is a no-op after process completion',
    );
    _expect(
      exit.exitCode == 137 && exit.signal == 9,
      'fake forced exit is preserved',
    );
  });

  await _test('real Dart listener callback and process lifecycle', () async {
    _expect(_abiVersion() == 6, 'native asset ABI');
    final PtyProcess process = await startPty(
      PtyCommand(
        executable: '/bin/sh',
        arguments: const <String>[
          '-c',
          'printf "__DPTY_DART__%s:%s" "\$DPTY_DART_ENV" "\$PWD"; exit 9',
        ],
        environment: const <String, String>{'DPTY_DART_ENV': 'ok'},
        includeParentEnvironment: false,
        workingDirectory: '/private/tmp',
      ),
      readHighWaterBytes: 128 * 1024,
      readLowWaterBytes: 64 * 1024,
      writeCapacityBytes: 64 * 1024,
    );
    final Future<List<int>> outputFuture = process.output
        .expand<int>((Uint8List bytes) => bytes)
        .toList();
    final PtyProcessSnapshot snapshot = process.processSnapshot();
    _expect(
      snapshot.childPid == process.pid &&
          snapshot.childProcessGroup == process.pid &&
          snapshot.foregroundProcessGroup == process.pid &&
          snapshot.isAvailable &&
          !snapshot.hasDistinctForegroundProcess &&
          snapshot.hasTerminalAttributes &&
          snapshot.terminalEchoEnabled == true &&
          !snapshot.hasExited,
      'real idle shell process snapshot crosses the FFI boundary',
    );
    final PtyExit exit = await process.exit.timeout(const Duration(seconds: 4));
    final String output = utf8.decode(await outputFuture);
    _expect(exit.exitCode == 9 && exit.signal == null, 'real exit code');
    _expect(
      output.contains('__DPTY_DART__ok:/private/tmp'),
      'environment and cwd cross the native callback boundary',
    );
    _expect(process.finalStats?.hasExited ?? false, 'real stats finalized');
    await process.dispose();
    _expect(_liveSessionCount() == 0, 'real native session is released');
  });

  await _test(
    'cooperative read batches enforce a configurable Dart turn limit',
    () async {
      final PtyProcess process = await startPty(
        PtyCommand(
          executable: '/bin/sh',
          arguments: const <String>[
            '-c',
            "/bin/stty -echo; printf __DPTY_COOPERATIVE_READY__; "
                "IFS= read -r ready; "
                "/usr/bin/head -c 1048576 /dev/zero | "
                "/usr/bin/tr '\\000' x",
          ],
          includeParentEnvironment: false,
          readBatchBytes: 4 * 1024,
          readBatchesPerEventLoopTurn: 4,
        ),
        readHighWaterBytes: 4 * 1024,
        readLowWaterBytes: 0,
      );
      var callbackCount = 0;
      var outputBytes = 0;
      var eventTurnRequired = false;
      var exceededTurnLimit = false;
      var maximumBatchBytes = 0;
      var measuring = false;
      final StringBuffer startupOutput = StringBuffer();
      final Completer<void> ready = Completer<void>();
      final StreamSubscription<Uint8List> subscription = process.output.listen((
        Uint8List bytes,
      ) {
        if (eventTurnRequired) {
          exceededTurnLimit = true;
        }
        ++callbackCount;
        if (callbackCount % 4 == 0) {
          eventTurnRequired = true;
          Timer.run(() {
            eventTurnRequired = false;
          });
        }
        if (!measuring) {
          startupOutput.write(utf8.decode(bytes, allowMalformed: true));
          if (startupOutput.toString().contains('__DPTY_COOPERATIVE_READY__')) {
            measuring = true;
            ready.complete();
          }
          return;
        }
        outputBytes += bytes.length;
        if (bytes.length > maximumBatchBytes) {
          maximumBatchBytes = bytes.length;
        }
      });
      await ready.future.timeout(const Duration(seconds: 3));
      _expect(
        process.write(Uint8List.fromList(<int>[0x0a])) ==
            PtyWriteResult.accepted,
        'cooperative output starts only after its listener is installed',
      );
      final PtyExit exit = await process.exit.timeout(
        const Duration(seconds: 10),
      );
      final PtyStats? stats = process.finalStats;
      await subscription.cancel();
      await process.dispose();
      _expect(
        exit.exitCode == 0 &&
            outputBytes == 1024 * 1024 &&
            callbackCount > 1 &&
            maximumBatchBytes <= 4 * 1024 &&
            stats?.readBatches == callbackCount &&
            stats?.readPauseCount == callbackCount &&
            (stats?.maxReadInFlightBytes ?? 4 * 1024 + 1) <= 4 * 1024 &&
            !exceededTurnLimit,
        'one event-loop turn separates each bounded four-callback group: '
        'exit=${exit.exitCode} bytes=$outputBytes callbacks=$callbackCount '
        'max_batch=$maximumBatchBytes exceeded_limit=$exceededTurnLimit',
      );
      _expect(
        _liveSessionCount() == 0,
        'cooperative native session is released',
      );
    },
  );

  await _test('closed parent stdin cannot alias child PTY stdin', () async {
    final Process helper = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        File.fromUri(Platform.script).path,
        '--closed-stdin-pty-helper',
      ],
      workingDirectory: Directory.current.path,
      runInShell: false,
    );
    await helper.stdin.close();
    final Future<String> output = utf8.decoder.bind(helper.stdout).join();
    final Future<String> diagnostics = utf8.decoder.bind(helper.stderr).join();
    final int status = await helper.exitCode.timeout(
      const Duration(seconds: 20),
    );
    final String stdoutText = await output;
    final String stderrText = await diagnostics;
    _expect(
      status == 0 && stdoutText.contains('CLOSED_STDIN_PTY_PASS'),
      'closed-stdin helper preserves PTY fd 0: status=$status '
      'stderr=$stderrText',
    );
  });

  await _test(
    'real force close bypasses an active graceful deadline',
    () async {
      final PtyProcess process = await startPty(
        PtyCommand(
          executable: '/bin/sh',
          arguments: const <String>[
            '-c',
            "trap '' HUP TERM; printf __DPTY_DART_FORCE__; while :; do sleep 1; done",
          ],
          includeParentEnvironment: false,
        ),
      );
      final StringBuffer output = StringBuffer();
      final Completer<void> ready = Completer<void>();
      final StreamSubscription<Uint8List> subscription = process.output.listen((
        Uint8List bytes,
      ) {
        output.write(utf8.decode(bytes, allowMalformed: true));
        if (!ready.isCompleted &&
            output.toString().contains('__DPTY_DART_FORCE__')) {
          ready.complete();
        }
      });
      await ready.future.timeout(const Duration(seconds: 3));
      process.close(gracePeriod: const Duration(seconds: 60));
      final Stopwatch elapsed = Stopwatch()..start();
      process.forceClose();
      process.forceClose();
      final PtyExit exit = await process.exit.timeout(
        const Duration(seconds: 3),
      );
      elapsed.stop();
      process.forceClose();
      await subscription.cancel();
      await process.dispose();
      _expect(
        exit.exitCode == 137 && exit.signal == 9,
        'real explicit force close reports SIGKILL',
      );
      _expect(
        elapsed.elapsed < const Duration(seconds: 2),
        'real explicit force close bypasses the 60 second grace period',
      );
      _expect(_liveSessionCount() == 0, 'force-closed session is released');
    },
  );

  await _test('tracked write diagnostics cross the Dart boundary', () async {
    final PtyProcess process = await startPty(
      PtyCommand(executable: '/bin/cat', includeParentEnvironment: false),
      enableDiagnostics: true,
    );
    final List<PtyDiagnosticEvent> diagnostics = <PtyDiagnosticEvent>[];
    final StreamSubscription<PtyDiagnosticEvent> subscription = process
        .diagnostics
        .listen(diagnostics.add);
    final PtyWriteReceipt receipt = process.writeTracked(
      Uint8List.fromList(const <int>[0x64]),
    );
    _expect(
      receipt.result == PtyWriteResult.accepted && receipt.requestId != null,
      'tracked write returns an accepted request identity',
    );
    await _waitFor(
      () => diagnostics.any(
        (PtyDiagnosticEvent event) =>
            event.stage == PtyDiagnosticStage.writeCompleted &&
            event.requestId == receipt.requestId,
      ),
      'tracked write completion diagnostic',
    );
    process.forceClose();
    await process.exit.timeout(const Duration(seconds: 3));
    await subscription.cancel();
    await process.dispose();
    for (final PtyDiagnosticStage stage in <PtyDiagnosticStage>[
      PtyDiagnosticStage.writeEnqueued,
      PtyDiagnosticStage.writeDequeued,
      PtyDiagnosticStage.writeCompleted,
      PtyDiagnosticStage.stateSnapshot,
      PtyDiagnosticStage.termiosSnapshot,
      PtyDiagnosticStage.forceCloseDequeued,
      PtyDiagnosticStage.signalDelivery,
      PtyDiagnosticStage.waitpidResult,
      PtyDiagnosticStage.processExitReady,
      PtyDiagnosticStage.exitPublished,
    ]) {
      _expect(
        diagnostics.any((PtyDiagnosticEvent event) => event.stage == stage),
        'diagnostic stage ${stage.name}',
      );
    }
    _expect(
      diagnostics
          .where(
            (PtyDiagnosticEvent event) =>
                event.stage == PtyDiagnosticStage.termiosSnapshot,
          )
          .any(
            (PtyDiagnosticEvent event) =>
                event.terminalEofCharacter == 4 &&
                event.terminalLocalFlags != null,
          ),
      'termios metadata includes VEOF without terminal content',
    );
    _expect(_liveSessionCount() == 0, 'diagnostic session is released');
  });

  await _test('live Dart child cannot steal native PTY completion', () async {
    final Process dartOwnedChild = await Process.start('/bin/sleep', const [
      '30',
    ]);
    PtyProcess? process;
    StreamSubscription<Uint8List>? outputSubscription;
    StreamSubscription<PtyDiagnosticEvent>? diagnosticSubscription;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      process = await startPty(
        PtyCommand(
          executable: '/bin/sh',
          arguments: const <String>[
            '-c',
            'printf __DPTY_DART_REAPER_READY__; IFS= read -r value; exit 37',
          ],
          includeParentEnvironment: false,
        ),
        enableDiagnostics: true,
      );
      final StringBuffer output = StringBuffer();
      final Completer<void> ready = Completer<void>();
      final List<PtyDiagnosticEvent> diagnostics = <PtyDiagnosticEvent>[];
      outputSubscription = process.output.listen((Uint8List bytes) {
        output.write(utf8.decode(bytes, allowMalformed: true));
        if (!ready.isCompleted &&
            output.toString().contains('__DPTY_DART_REAPER_READY__')) {
          ready.complete();
        }
      });
      diagnosticSubscription = process.diagnostics.listen(diagnostics.add);
      await ready.future.timeout(const Duration(seconds: 3));
      final PtyWriteReceipt receipt = process.writeTracked(
        Uint8List.fromList(const <int>[0x04]),
      );
      _expect(
        receipt.result == PtyWriteResult.accepted,
        'competing-reaper Control-D is accepted',
      );
      final PtyExit result = await process.exit.timeout(
        const Duration(seconds: 3),
      );
      _expect(
        result.exitCode == 37 && result.signal == null,
        'competing Dart reaper preserves PTY exit status',
      );
      final PtyDiagnosticEvent external = diagnostics.firstWhere(
        (PtyDiagnosticEvent event) =>
            event.stage == PtyDiagnosticStage.externalReapObserved,
      );
      _expect(
        external.childProcessId == process.pid &&
            external.childStatus != null &&
            external.systemError == 10,
        'external Dart reap is explicitly classified with retained status',
      );
      _expect(
        diagnostics.any(
          (PtyDiagnosticEvent event) =>
              event.stage == PtyDiagnosticStage.exitPublished &&
              event.exitCode == 37,
        ),
        'external reap publishes exactly one matching PTY exit',
      );
      await outputSubscription.cancel();
      outputSubscription = null;
      await diagnosticSubscription.cancel();
      diagnosticSubscription = null;
      await process.dispose();
      process = null;
      _expect(_liveSessionCount() == 0, 'external-reap session is released');
    } finally {
      await outputSubscription?.cancel();
      await diagnosticSubscription?.cancel();
      final PtyProcess? remainingProcess = process;
      if (remainingProcess != null) {
        remainingProcess.forceClose();
        try {
          await remainingProcess.exit.timeout(const Duration(seconds: 3));
          await remainingProcess.dispose();
        } on Object {
          // Preserve the original test failure; the process is force-requested.
        }
      }
      dartOwnedChild.kill(ProcessSignal.sigkill);
      await dartOwnedChild.exitCode.timeout(const Duration(seconds: 3));
    }
  });

  await _test('explicit bundled-library loading', () async {
    final Uri packageLibrary = (await Isolate.resolvePackageUri(
      Uri.parse('package:dart_pty_macos/dart_pty_macos.dart'),
    ))!;
    final String libraryPath = File.fromUri(packageLibrary).parent.parent
        .childDirectory('.dart_tool')
        .childDirectory('lib')
        .childFile('libdart_pty_macos.dylib')
        .path;
    final MacosPtyBackend backend = MacosPtyBackend.open(libraryPath);
    final PtyProcess process = await backend.start(
      PtyCommand(
        executable: '/bin/sh',
        arguments: const <String>['-c', 'printf __DPTY_DYNAMIC__; exit 4'],
        includeParentEnvironment: false,
      ),
    );
    final Future<List<int>> outputFuture = process.output
        .expand<int>((Uint8List bytes) => bytes)
        .toList();
    final PtyExit exit = await process.exit.timeout(const Duration(seconds: 4));
    _expect(exit.exitCode == 4, 'dynamic backend exit code');
    _expect(
      utf8.decode(await outputFuture).contains('__DPTY_DYNAMIC__'),
      'dynamic backend output',
    );
    await process.dispose();
    _expect(_liveSessionCount() == 0, 'dynamic native session is released');
  });

  await _test('real asynchronous exec failure', () async {
    await _expectThrowsAsync<PtyException>(() {
      return startPty(
        PtyCommand(
          executable: '/definitely/missing/dpty',
          includeParentEnvironment: false,
        ),
      );
    });
    _expect(_liveSessionCount() == 0, 'failed native session is released');
  });

  if (_failures != 0) {
    exitCode = 1;
  }
}

extension on Directory {
  Directory childDirectory(String name) =>
      Directory(uri.resolve('$name/').toFilePath());

  File childFile(String name) => File(uri.resolve(name).toFilePath());
}

Future<T> _expectThrowsAsync<T extends Object>(
  Future<void> Function() body,
) async {
  try {
    await body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}: $error');
  }
  throw StateError('expected $T but no error was thrown');
}

Future<void> _waitFor(bool Function() predicate, String description) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 3)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('timed out waiting for $description');
}
