import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

import 'runtime_diagnostics_host.dart';
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
const String _runtimeWorkerModePrefix = '--runtime-worker-mode=';
const String _terminalMetalViewProviderIdentifier =
    'dart_terminal.TerminalMetalView';

enum _RuntimeWorkerMode { kernel, selfContained }

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
    _RuntimeWorkerMode? runtimeWorkerMode;
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
      if (argument.startsWith(_runtimeWorkerModePrefix)) {
        if (runtimeWorkerMode != null) {
          throw const FormatException(
            'internal runtime worker mode may only be supplied once',
          );
        }
        runtimeWorkerMode = switch (argument.substring(
          _runtimeWorkerModePrefix.length,
        )) {
          'kernel' => _RuntimeWorkerMode.kernel,
          'self-contained' => _RuntimeWorkerMode.selfContained,
          _ => throw const FormatException(
            'internal runtime worker mode must be kernel or self-contained',
          ),
        };
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
    if (runtimeWorkerExecutable == null ||
        runtimeWorkerMode == null ||
        (runtimeWorkerMode == _RuntimeWorkerMode.kernel &&
            runtimeWorkerKernel == null) ||
        (runtimeWorkerMode == _RuntimeWorkerMode.selfContained &&
            runtimeWorkerKernel != null)) {
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
        arguments: runtimeWorkerMode == _RuntimeWorkerMode.kernel
            ? <String>[runtimeWorkerKernel!]
            : const <String>[],
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
    View? contentView;
    Window? window;
    TerminalSession? session;
    StreamSubscription<WindowEvent>? eventSubscription;
    StreamSubscription<AppKitEvent>? applicationEventSubscription;
    final List<StreamSubscription<MenuItemInvokedEvent>> menuSubscriptions =
        <StreamSubscription<MenuItemInvokedEvent>>[];
    final List<MenuItem> menuItems = <MenuItem>[];
    final List<Menu> menus = <Menu>[];
    Timer? autoCloseTimer;
    RuntimeLifecycleCoordinator? lifecycle;
    var lifecycleWasShutDown = false;
    final Completer<void> closed = Completer<void>();
    final bool emitNativeEventWireObservation =
        Platform.environment['DT_RUNTIME_EVENT_WIRE_TEST'] == '1';
    final bool useTerminalMetalView =
        Platform.environment['DT_RUNTIME_CUSTOM_VIEW_TEST'] == '1';

    try {
      final TextView? createdTextView = useTerminalMetalView
          ? null
          : TextView();
      final View createdContentView =
          createdTextView ?? View.custom(_terminalMetalViewProviderIdentifier);
      contentView = createdContentView;
      final Window createdWindow =
          Window(
              frame: const Rect.fromLTWH(100, 90, 920, 580),
              title: 'Dart Terminal',
            )
            ..contentView = createdContentView
            ..defersCloseRequests = true;
      window = createdWindow;
      application.defersTerminationRequests = true;
      if (useTerminalMetalView) {
        stdout.writeln(
          'NATIVE_CUSTOM_VIEW '
          'provider=$_terminalMetalViewProviderIdentifier attached=true',
        );
      }

      late final TerminalSession createdSession;
      createdSession = TerminalSession(
        initialWorkingDirectory: options.initialWorkingDirectory,
        onChanged: () {
          if (createdTextView != null && !createdTextView.isDisposed) {
            createdTextView.text = createdSession.render();
          }
        },
        onExitRequested: createdWindow.requestClose,
      );
      session = createdSession;
      if (createdTextView != null) {
        createdTextView.text = createdSession.render();
      }

      Menu ownMenu(Menu menu) {
        menus.add(menu);
        return menu;
      }

      MenuItem ownMenuItem(MenuItem item) {
        menuItems.add(item);
        return item;
      }

      final Menu mainMenu = ownMenu(Menu());
      final Menu applicationMenu = ownMenu(Menu(title: 'Dart Terminal'));
      final Menu fileMenu = ownMenu(Menu(title: 'File'));
      final Menu editMenu = ownMenu(Menu(title: 'Edit'));
      final MenuItem applicationMenuItem = ownMenuItem(
        MenuItem(title: 'Dart Terminal')..submenu = applicationMenu,
      );
      final MenuItem fileMenuItem = ownMenuItem(
        MenuItem(title: 'File')..submenu = fileMenu,
      );
      final MenuItem editMenuItem = ownMenuItem(
        MenuItem(title: 'Edit')..submenu = editMenu,
      );
      final MenuItem quitItem = ownMenuItem(
        MenuItem(
          title: 'Quit Dart Terminal',
          keyEquivalent: 'q',
          modifiers: const ModifierKeys(ModifierKeys.commandBit),
        ),
      );
      final MenuItem closeItem = ownMenuItem(
        MenuItem(
          title: 'Close',
          keyEquivalent: 'w',
          modifiers: const ModifierKeys(ModifierKeys.commandBit),
        ),
      );
      final MenuItem pasteItem = ownMenuItem(
        MenuItem(
          title: 'Paste',
          keyEquivalent: 'v',
          modifiers: const ModifierKeys(ModifierKeys.commandBit),
        ),
      );
      mainMenu
        ..addItem(applicationMenuItem)
        ..addItem(fileMenuItem)
        ..addItem(editMenuItem);
      applicationMenu.addItem(quitItem);
      fileMenu.addItem(closeItem);
      editMenu.addItem(pasteItem);
      application.mainMenu = mainMenu;

      void observeMenuAction(String action, MenuItemInvokedEvent event) {
        if (!emitNativeEventWireObservation) {
          return;
        }
        stdout.writeln(
          'NATIVE_MENU_ACTION negotiated=${application.eventProtocolVersion} '
          'action=$action protocol=${event.protocolVersion} '
          'source_generation=${event.sourceGeneration} '
          'operation_id=${event.operationId} '
          'timestamp_ns=${event.monotonicNanoseconds}',
        );
      }

      menuSubscriptions
        ..add(
          pasteItem.onInvoked.listen((MenuItemInvokedEvent event) {
            observeMenuAction('paste', event);
            final PasteboardTextSnapshot snapshot = application
                .generalPasteboard
                .readText();
            if (emitNativeEventWireObservation) {
              stdout.writeln(
                'NATIVE_PASTEBOARD_SNAPSHOT '
                'change_count=${snapshot.changeCount} '
                'has_text=${snapshot.text != null}',
              );
            }
            final String? text = snapshot.text;
            if (text != null) {
              createdSession.insertText(text);
            }
          }),
        )
        ..add(
          closeItem.onInvoked.listen((MenuItemInvokedEvent event) {
            observeMenuAction('close', event);
            if (!createdWindow.isClosed && !createdWindow.isDisposed) {
              createdWindow.requestClose();
            }
          }),
        )
        ..add(
          quitItem.onInvoked.listen((MenuItemInvokedEvent event) {
            observeMenuAction('quit', event);
            if (!createdWindow.isClosed && !createdWindow.isDisposed) {
              createdWindow.requestClose();
            }
          }),
        );

      applicationEventSubscription = application.events.listen(
        (AppKitEvent event) {
          switch (event) {
            case ApplicationActiveChangedEvent(:final isActive):
              if (emitNativeEventWireObservation) {
                stdout.writeln(
                  'NATIVE_APPLICATION_ACTIVE '
                  'negotiated=${application.eventProtocolVersion} '
                  'protocol=${event.protocolVersion} '
                  'source_generation=${event.sourceGeneration} '
                  'operation_id=${event.operationId} '
                  'timestamp_ns=${event.monotonicNanoseconds} '
                  'value=$isActive',
                );
              }
            case ApplicationReopenRequestedEvent(:final hasVisibleWindows):
              if (!hasVisibleWindows &&
                  !createdWindow.isClosed &&
                  !createdWindow.isDisposed) {
                createdWindow.show();
              }
            case ApplicationTerminateRequestedEvent():
              if (emitNativeEventWireObservation) {
                stdout.writeln(
                  'NATIVE_APPLICATION_TERMINATE_REQUEST '
                  'negotiated=${application.eventProtocolVersion} '
                  'protocol=${event.protocolVersion} '
                  'source_generation=${event.sourceGeneration} '
                  'operation_id=${event.operationId} '
                  'timestamp_ns=${event.monotonicNanoseconds}',
                );
              }
              application.replyToTerminationRequest(event, allow: false);
              if (!createdWindow.isClosed && !createdWindow.isDisposed) {
                createdWindow.requestClose();
              }
            case WindowEvent() || MenuItemInvokedEvent():
              break;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) {
            closed.completeError(error, stackTrace);
          }
        },
      );

      eventSubscription = createdWindow.events.listen(
        (WindowEvent event) {
          switch (event) {
            case WindowClosedEvent(
              :final protocolVersion,
              :final sourceGeneration,
              :final monotonicNanoseconds,
              :final operationId,
            ):
              if (emitNativeEventWireObservation) {
                stdout.writeln(
                  'NATIVE_EVENT_WIRE negotiated='
                  '${application.eventProtocolVersion} event=window-closed '
                  'protocol=$protocolVersion '
                  'source_generation=$sourceGeneration '
                  'operation_id=$operationId '
                  'timestamp_ns=$monotonicNanoseconds',
                );
              }
              if (!closed.isCompleted) {
                closed.complete();
              }
            case WindowCloseRequestedEvent():
              if (emitNativeEventWireObservation) {
                stdout.writeln(
                  'NATIVE_WINDOW_CLOSE_REQUEST '
                  'negotiated=${application.eventProtocolVersion} '
                  'protocol=${event.protocolVersion} '
                  'source_generation=${event.sourceGeneration} '
                  'operation_id=${event.operationId} '
                  'timestamp_ns=${event.monotonicNanoseconds}',
                );
              }
              createdWindow.replyToCloseRequest(event, allow: true);
            case WindowResizedEvent(:final height):
              createdSession.viewportRows = _rowsForHeight(height);
              createdSession.refresh();
            case WindowFocusChangedEvent(:final isFocused):
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'focus',
                  'value=$isFocused',
                );
              }
            case WindowVisibilityChangedEvent(:final isVisible):
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'visibility',
                  'value=$isVisible',
                );
              }
            case WindowOcclusionChangedEvent(:final isOccluded):
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'occlusion',
                  'value=$isOccluded',
                );
              }
            case WindowBackingScaleChangedEvent(:final backingScaleFactor):
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'backing-scale',
                  'value=$backingScaleFactor',
                );
              }
            case WindowScreenChangedEvent(:final screen):
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'screen',
                  switch (screen) {
                    null => 'present=false display_id=0',
                    AppKitScreen(
                      :final displayId,
                      :final frame,
                      :final visibleFrame,
                    ) =>
                      'present=true display_id=$displayId '
                          'frame_width=${frame.width} '
                          'frame_height=${frame.height} '
                          'visible_width=${visibleFrame.width} '
                          'visible_height=${visibleFrame.height}',
                  },
                );
              }
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
      if (emitNativeEventWireObservation) {
        stdout.writeln(
          'NATIVE_APPLICATION_STATE '
          'negotiated=${application.eventProtocolVersion} '
          'active=${application.isActive}',
        );
      }
      RuntimeLifecycleCoordinator createLifecycle({
        RuntimeLifecycleScenario? workerScenario,
        int initialGeneration = 0,
      }) => RuntimeLifecycleCoordinator(
        scenario: scenario,
        workerScenario: workerScenario,
        initialGeneration: initialGeneration,
        workerCommand: options.runtimeWorkerCommand,
        observer: (RuntimeLifecycleObservation observation) {
          stdout.writeln(observation.machineLine(scenario));
        },
        processObserver: (RuntimeLifecycleProcessObservation observation) {
          stdout.writeln(
            observation.machineLine(scenario, parentProcessId: pid),
          );
        },
      );
      final RuntimeLifecycleCoordinator createdLifecycle = createLifecycle(
        workerScenario: scenario == RuntimeLifecycleScenario.workerReplacement
            ? RuntimeLifecycleScenario.workerUnexpectedExit
            : null,
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
      RuntimeDiagnosticsHost.recordPhase(RuntimeDiagnosticPhase.rootReady);

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
        case RuntimeLifecycleScenario.workerReplacement:
          final int failedProcessId = createdLifecycle.workerPid!;
          final RuntimeLifecycleRequestResult failed = await createdLifecycle
              .request(41);
          _expectLifecycle(
            failed.status == RuntimeLifecycleRequestStatus.unexpectedExit,
            'replacement source did not exit unexpectedly',
          );
          lifecycleWasShutDown = true;
          final RuntimeLifecycleCoordinator replacement = createLifecycle(
            workerScenario: RuntimeLifecycleScenario.normal,
            initialGeneration: createdLifecycle.generation,
          );
          lifecycle = replacement;
          lifecycleWasShutDown = false;
          _expectLifecycle(
            await replacement.start() == RuntimeLifecycleStartStatus.ready,
            'replacement worker did not become ready',
          );
          _expectLifecycle(
            replacement.workerPid != failedProcessId,
            'replacement worker reused the failed process',
          );
          await _expectResponse(replacement);
          final RuntimeLifecycleShutdownResult replacementShutdown =
              await replacement.shutdown();
          _expectLifecycle(
            replacementShutdown.termination ==
                RuntimeLifecycleWorkerTermination.graceful,
            'replacement worker did not stop gracefully',
          );
          lifecycleWasShutDown = true;
        case RuntimeLifecycleScenario.workerTraffic:
          await _exerciseWorkerTraffic(createdLifecycle, createdWindow);
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
            pasteItem.performAction();
            closeItem.performAction();
            quitItem.performAction();
          }
        });
      }
      await closed.future;
    } finally {
      RuntimeDiagnosticsHost.recordPhase(
        RuntimeDiagnosticPhase.shutdownStarted,
      );
      autoCloseTimer?.cancel();
      if (!lifecycleWasShutDown) {
        await lifecycle?.shutdown();
      }
      await eventSubscription?.cancel();
      await applicationEventSubscription?.cancel();
      for (final StreamSubscription<MenuItemInvokedEvent> subscription
          in menuSubscriptions) {
        await subscription.cancel();
      }
      application.mainMenu = null;
      for (final MenuItem item in menuItems.reversed) {
        if (!item.isDisposed) {
          item.dispose();
        }
      }
      for (final Menu menu in menus.reversed) {
        if (!menu.isDisposed) {
          menu.dispose();
        }
      }
      await session?.dispose();
      if (window != null && !window.isDisposed) {
        window.dispose();
      }
      if (contentView != null && !contentView.isDisposed) {
        contentView.dispose();
      }
      _writeLifecycleEvent(scenario, 'root-exit', lifecycle?.generation ?? 0);
      RuntimeDiagnosticsHost.recordPhase(RuntimeDiagnosticPhase.rootStopped);
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

  static Future<void> _exerciseWorkerTraffic(
    RuntimeLifecycleCoordinator lifecycle,
    Window window,
  ) async {
    const int requestCount = 256;
    final Completer<void> closeTimerFired = Completer<void>();
    final Timer closeTimer = Timer(const Duration(milliseconds: 25), () {
      if (!window.isClosed && !window.isDisposed) {
        window.close();
      }
      closeTimerFired.complete();
    });
    final Stopwatch stopwatch = Stopwatch()..start();
    var responses = 0;
    List<int> pending = List<int>.generate(requestCount, (int index) => index);
    try {
      while (pending.isNotEmpty) {
        final List<({int input, RuntimeLifecycleRequestResult result})>
        results = await Future.wait(
          pending.map((int input) async {
            final RuntimeLifecycleRequestResult result = await lifecycle
                .request(input);
            return (input: input, result: result);
          }),
        );
        final List<int> retry = <int>[];
        for (final ({int input, RuntimeLifecycleRequestResult result}) item
            in results) {
          switch (item.result.status) {
            case RuntimeLifecycleRequestStatus.response:
              _expectLifecycle(
                item.result.value == item.input + 1,
                'traffic response did not match its request',
              );
              ++responses;
            case RuntimeLifecycleRequestStatus.backpressured:
              retry.add(item.input);
            case RuntimeLifecycleRequestStatus.uncaughtError:
            case RuntimeLifecycleRequestStatus.unexpectedExit:
            case RuntimeLifecycleRequestStatus.cancelled:
              throw StateError(
                'runtime lifecycle traffic failed: ${item.result.status.name}',
              );
          }
        }
        _expectLifecycle(
          retry.length < pending.length,
          'traffic backpressure made no forward progress',
        );
        pending = retry;
      }
      await closeTimerFired.future.timeout(const Duration(seconds: 1));
    } finally {
      closeTimer.cancel();
      stopwatch.stop();
    }
    _expectLifecycle(
      responses == requestCount &&
          lifecycle.maximumInFlightObserved ==
              lifecycle.maximumInFlightRequests &&
          lifecycle.backpressureRejectionCount > 0 &&
          window.isClosed,
      'bounded traffic did not exercise backpressure and scheduled close',
    );
    stdout.writeln(
      'RUNTIME_WORKER_TRAFFIC requests=$requestCount responses=$responses '
      'backpressured=${lifecycle.backpressureRejectionCount} '
      'max_in_flight=${lifecycle.maximumInFlightObserved} '
      'close_timer_fired=1 elapsed_ms=${stopwatch.elapsedMilliseconds}',
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

  static void _writeWindowStateEvent(
    AppKitApplication application,
    WindowEvent event,
    String eventName,
    String value,
  ) {
    stdout.writeln(
      'NATIVE_WINDOW_STATE negotiated=${application.eventProtocolVersion} '
      'event=$eventName protocol=${event.protocolVersion} '
      'source_generation=${event.sourceGeneration} '
      'operation_id=${event.operationId} '
      'timestamp_ns=${event.monotonicNanoseconds} $value',
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
