import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

import 'runtime_lifecycle.dart';
import 'runtime_lifecycle_host.dart';
import 'terminal_session.dart';

const String terminalUsage = '''
Usage: Dart Terminal [application-options]

Application options:
  --working-directory=PATH   Initial command working directory.
  --auto-close-after=SECONDS Close automatically (for smoke testing).
''';

const String _runtimeWorkerExecutablePrefix = '--runtime-worker-executable=';
const String _runtimeWorkerKernelPrefix = '--runtime-worker-kernel=';

final class TerminalOptions {
  const TerminalOptions({
    this.initialWorkingDirectory,
    this.autoCloseAfter,
    this.runtimeLifecycleScenario = RuntimeLifecycleScenario.normal,
    this.runtimeWorkerCommand =
        const RuntimeLifecycleWorkerCommand.unconfigured(),
  });

  factory TerminalOptions.parse(
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    String? initialWorkingDirectory;
    Duration? autoCloseAfter;
    RuntimeLifecycleScenario? runtimeLifecycleScenario;
    String? runtimeWorkerExecutable;
    String? runtimeWorkerKernel;
    for (final String argument in arguments) {
      const String workingDirectoryPrefix = '--working-directory=';
      const String autoClosePrefix = '--auto-close-after=';
      const String lifecyclePrefix = '--runtime-lifecycle-scenario=';
      if (argument.startsWith(_runtimeWorkerExecutablePrefix)) {
        if (runtimeWorkerExecutable != null) {
          throw const FormatException(
            'internal runtime worker executable may only be supplied once',
          );
        }
        final String value = argument.substring(
          _runtimeWorkerExecutablePrefix.length,
        );
        if (value.isEmpty || !File(value).isAbsolute) {
          throw const FormatException(
            'internal runtime worker executable must be an absolute path',
          );
        }
        runtimeWorkerExecutable = value;
        continue;
      }
      if (argument.startsWith(_runtimeWorkerKernelPrefix)) {
        if (runtimeWorkerKernel != null) {
          throw const FormatException(
            'internal runtime worker Kernel may only be supplied once',
          );
        }
        final String value = argument.substring(
          _runtimeWorkerKernelPrefix.length,
        );
        if (value.isEmpty || !File(value).isAbsolute) {
          throw const FormatException(
            'internal runtime worker Kernel must be an absolute path',
          );
        }
        runtimeWorkerKernel = value;
        continue;
      }
      if (argument.startsWith(workingDirectoryPrefix)) {
        if (initialWorkingDirectory != null) {
          throw const FormatException(
            '--working-directory may only be supplied once',
          );
        }
        final String value = argument.substring(workingDirectoryPrefix.length);
        if (value.isEmpty) {
          throw const FormatException('--working-directory requires a path');
        }
        initialWorkingDirectory = value;
        continue;
      }
      if (argument.startsWith(autoClosePrefix)) {
        if (autoCloseAfter != null) {
          throw const FormatException(
            '--auto-close-after may only be supplied once',
          );
        }
        final int? seconds = int.tryParse(
          argument.substring(autoClosePrefix.length),
        );
        if (seconds == null || seconds <= 0) {
          throw FormatException(
            '--auto-close-after must be a positive number: $argument',
          );
        }
        autoCloseAfter = Duration(seconds: seconds);
        continue;
      }
      if (argument.startsWith(lifecyclePrefix)) {
        if (runtimeLifecycleScenario != null) {
          throw const FormatException(
            '--runtime-lifecycle-scenario may only be supplied once',
          );
        }
        final String value = argument.substring(lifecyclePrefix.length);
        runtimeLifecycleScenario = RuntimeLifecycleScenario.byName(value);
        if (runtimeLifecycleScenario == null) {
          throw FormatException('unknown runtime lifecycle scenario: $value');
        }
        continue;
      }
      throw FormatException('unknown application option: $argument');
    }
    if (runtimeWorkerExecutable == null || runtimeWorkerKernel == null) {
      throw const FormatException(
        'internal runtime worker configuration is incomplete',
      );
    }
    final RuntimeLifecycleScenario selectedScenario =
        runtimeLifecycleScenario ?? RuntimeLifecycleScenario.normal;
    if (selectedScenario != RuntimeLifecycleScenario.normal &&
        (environment ?? Platform.environment)['DT_RUNTIME_LIFECYCLE_TEST'] !=
            '1') {
      throw const FormatException(
        'runtime lifecycle fault scenarios require the integration-test gate',
      );
    }
    return TerminalOptions(
      initialWorkingDirectory: initialWorkingDirectory,
      autoCloseAfter: autoCloseAfter,
      runtimeLifecycleScenario: selectedScenario,
      runtimeWorkerCommand: RuntimeLifecycleWorkerCommand(
        executable: runtimeWorkerExecutable,
        arguments: <String>[runtimeWorkerKernel],
      ),
    );
  }

  final String? initialWorkingDirectory;
  final Duration? autoCloseAfter;
  final RuntimeLifecycleScenario runtimeLifecycleScenario;
  final RuntimeLifecycleWorkerCommand runtimeWorkerCommand;
}

final class TerminalApplication {
  const TerminalApplication({this.options = const TerminalOptions()});

  final TerminalOptions options;

  Future<void> run() async {
    final RuntimeLifecycleScenario scenario = options.runtimeLifecycleScenario;
    _writeLifecycleEvent(scenario, 'root-start', 0);
    final AppKitApplication application = await AppKitApplication.attach();
    TextView? textView;
    Window? window;
    TerminalSession? session;
    StreamSubscription<WindowEvent>? eventSubscription;
    Timer? autoCloseTimer;
    RuntimeLifecycleCoordinator? lifecycle;
    var lifecycleWasShutDown = false;
    final Completer<void> closed = Completer<void>();

    try {
      final TextView createdTextView = TextView();
      textView = createdTextView;
      final Window createdWindow = Window(
        frame: const Rect.fromLTWH(100, 90, 920, 580),
        title: 'Dart Terminal',
      )..contentView = createdTextView;
      window = createdWindow;

      late final TerminalSession createdSession;
      createdSession = TerminalSession(
        initialWorkingDirectory: options.initialWorkingDirectory,
        onChanged: () {
          if (!createdTextView.isDisposed) {
            createdTextView.text = createdSession.render();
          }
        },
        onExitRequested: createdWindow.close,
      );
      session = createdSession;
      createdTextView.text = createdSession.render();

      eventSubscription = createdWindow.events.listen(
        (WindowEvent event) {
          switch (event) {
            case WindowClosedEvent():
              if (!closed.isCompleted) {
                closed.complete();
              }
            case WindowResizedEvent(:final height):
              createdSession.viewportRows = _rowsForHeight(height);
              createdSession.refresh();
            case AppKitKeyEvent() when event.kind == AppKitKeyEventKind.down:
              _handleKeyDown(event, createdSession);
            case AppKitKeyEvent():
            case AppKitMouseEvent():
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) {
            closed.completeError(error, stackTrace);
          }
        },
      );

      createdWindow.show();
      stdout.writeln('Dart Terminal is attached to the AppKit main thread.');
      final RuntimeLifecycleCoordinator createdLifecycle =
          RuntimeLifecycleCoordinator(
            scenario: scenario,
            workerCommand: options.runtimeWorkerCommand,
            observer: (RuntimeLifecycleObservation observation) {
              stdout.writeln(observation.machineLine(scenario));
            },
          );
      lifecycle = createdLifecycle;
      final RuntimeLifecycleStartStatus startStatus = await createdLifecycle
          .start();
      if (scenario == RuntimeLifecycleScenario.workerStartupFailure) {
        _expectLifecycle(
          startStatus == RuntimeLifecycleStartStatus.startupFailure,
          'worker startup failure was not observed',
        );
      } else {
        _expectLifecycle(
          startStatus == RuntimeLifecycleStartStatus.ready,
          'worker did not become ready',
        );
      }
      _writeLifecycleEvent(scenario, 'root-ready', createdLifecycle.generation);

      switch (scenario) {
        case RuntimeLifecycleScenario.normal:
          await _expectResponse(createdLifecycle);
        case RuntimeLifecycleScenario.workerSyncUncaught:
        case RuntimeLifecycleScenario.workerAsyncUncaught:
          final RuntimeLifecycleRequestResult result = await createdLifecycle
              .request(41);
          _expectLifecycle(
            result.status == RuntimeLifecycleRequestStatus.uncaughtError,
            '${scenario.name} did not produce a contained worker error',
          );
        case RuntimeLifecycleScenario.workerUnexpectedExit:
          final RuntimeLifecycleRequestResult result = await createdLifecycle
              .request(41);
          _expectLifecycle(
            result.status == RuntimeLifecycleRequestStatus.unexpectedExit,
            'worker exit was not classified as unexpected',
          );
        case RuntimeLifecycleScenario.workerStartupFailure:
          break;
        case RuntimeLifecycleScenario.workerIdleUncaught:
          final RuntimeLifecycleWorkerTermination termination =
              await createdLifecycle.waitForTermination();
          lifecycleWasShutDown = true;
          _expectLifecycle(
            termination == RuntimeLifecycleWorkerTermination.uncaughtError,
            'idle worker crash was not reconciled as an uncaught error',
          );
        case RuntimeLifecycleScenario.workerIdleExit:
          final RuntimeLifecycleWorkerTermination termination =
              await createdLifecycle.waitForTermination();
          lifecycleWasShutDown = true;
          _expectLifecycle(
            termination == RuntimeLifecycleWorkerTermination.unexpectedExit,
            'idle worker exit was not reconciled as unexpected',
          );
        case RuntimeLifecycleScenario.workerStopUncaught:
          await _expectResponse(createdLifecycle);
          final RuntimeLifecycleShutdownResult result = await createdLifecycle
              .shutdown();
          lifecycleWasShutDown = true;
          _expectLifecycle(
            !result.forced &&
                result.termination ==
                    RuntimeLifecycleWorkerTermination.uncaughtError,
            'stop-processing crash was mislabeled as a shutdown timeout',
          );
        case RuntimeLifecycleScenario.shutdownTimeout:
          await _expectResponse(createdLifecycle);
          final RuntimeLifecycleShutdownResult result = await createdLifecycle
              .shutdown();
          lifecycleWasShutDown = true;
          _expectLifecycle(result.forced, 'shutdown deadline did not force');
          RuntimeLifecycleHost.setExitCode(runtimeTemporaryFailureExitCode);
        case RuntimeLifecycleScenario.lateCompletion:
          final Future<RuntimeLifecycleRequestResult> request = createdLifecycle
              .request(41);
          final RuntimeLifecycleShutdownResult shutdown = await createdLifecycle
              .shutdown();
          lifecycleWasShutDown = true;
          final RuntimeLifecycleRequestResult requestResult = await request;
          _expectLifecycle(
            !shutdown.forced &&
                requestResult.status == RuntimeLifecycleRequestStatus.cancelled,
            'late completion changed the stopped generation',
          );
        case RuntimeLifecycleScenario.doubleShutdown:
          await _expectResponse(createdLifecycle);
          final Future<RuntimeLifecycleShutdownResult> first = createdLifecycle
              .shutdown();
          final Future<RuntimeLifecycleShutdownResult> second = createdLifecycle
              .shutdown();
          _expectLifecycle(
            identical(first, second),
            'double shutdown did not return the cached future',
          );
          _expectLifecycle(
            !(await first).forced,
            'double shutdown did not finish gracefully',
          );
          lifecycleWasShutDown = true;
        case RuntimeLifecycleScenario.rootStartupFailure:
          throw StateError('root startup failure reached application run');
        case RuntimeLifecycleScenario.rootUncaught:
          await _expectResponse(createdLifecycle);
          Timer.run(() {
            _writeLifecycleEvent(
              scenario,
              'root-uncaught',
              createdLifecycle.generation,
            );
            stderr.writeln(
              'RUNTIME_LIFECYCLE_FATAL class=root-uncaught status=70',
            );
            throw StateError('requested asynchronous root failure');
          });
      }

      if (scenario != RuntimeLifecycleScenario.normal &&
          scenario != RuntimeLifecycleScenario.rootUncaught &&
          !createdWindow.isClosed &&
          !createdWindow.isDisposed) {
        createdWindow.close();
      }

      final Duration? autoCloseAfter =
          scenario == RuntimeLifecycleScenario.normal
          ? options.autoCloseAfter
          : null;
      if (autoCloseAfter != null) {
        stdout.writeln(
          'Automated close scheduled after '
          '${autoCloseAfter.inSeconds} seconds.',
        );
        autoCloseTimer = Timer(autoCloseAfter, () {
          if (!createdWindow.isClosed && !createdWindow.isDisposed) {
            createdWindow.close();
          }
        });
      }
      await closed.future;
    } finally {
      autoCloseTimer?.cancel();
      if (!lifecycleWasShutDown) {
        await lifecycle?.shutdown();
      }
      await eventSubscription?.cancel();
      await session?.dispose();
      if (window != null && !window.isDisposed) {
        window.dispose();
      }
      if (textView != null && !textView.isDisposed) {
        textView.dispose();
      }
      _writeLifecycleEvent(scenario, 'root-exit', lifecycle?.generation ?? 0);
      await application.terminate();
    }
    stdout.writeln('Dart Terminal shut down cleanly.');
  }

  static Future<void> _expectResponse(
    RuntimeLifecycleCoordinator lifecycle,
  ) async {
    final RuntimeLifecycleRequestResult result = await lifecycle.request(41);
    _expectLifecycle(
      result.status == RuntimeLifecycleRequestStatus.response &&
          result.value == 42,
      'worker request did not return its expected response',
    );
  }

  static void _expectLifecycle(bool condition, String message) {
    if (!condition) {
      throw StateError('runtime lifecycle invariant failed: $message');
    }
  }

  static void _writeLifecycleEvent(
    RuntimeLifecycleScenario scenario,
    String event,
    int generation,
  ) {
    stdout.writeln(
      RuntimeLifecycleObservation(
        event: event,
        generation: generation,
      ).machineLine(scenario),
    );
  }

  static int _rowsForHeight(double height) {
    final int rows = ((height - 40) / 22).floor();
    if (rows < 4) {
      return 4;
    }
    if (rows > 200) {
      return 200;
    }
    return rows;
  }

  static void _handleKeyDown(AppKitKeyEvent event, TerminalSession session) {
    if (event.modifiers.control && event.keyCode == 8) {
      session.interrupt();
      return;
    }
    if (event.modifiers.control && event.keyCode == 2) {
      session.requestExitIfIdle();
      return;
    }
    if (session.isBusy || event.modifiers.command) {
      return;
    }

    switch (event.keyCode) {
      case 36:
      case 76:
        unawaited(session.submit());
        return;
      case 51:
        session.deleteBackward();
        return;
      case 117:
        session.deleteForward();
        return;
      case 123:
        session.moveLeft();
        return;
      case 124:
        session.moveRight();
        return;
      case 125:
        session.nextHistory();
        return;
      case 126:
        session.previousHistory();
        return;
      case 115:
        session.moveToStart();
        return;
      case 119:
        session.moveToEnd();
        return;
    }

    if (event.modifiers.control || event.modifiers.function) {
      return;
    }
    final Iterable<int> printableRunes = event.characters.runes.where(
      (int rune) =>
          rune >= 0x20 && rune != 0x7f && (rune < 0xf700 || rune > 0xf8ff),
    );
    session.insertText(String.fromCharCodes(printableRunes));
  }
}
