import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/testing.dart' as appkit_testing;
import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'runtime_lifecycle.dart';
import 'terminal_core/terminal_screen.dart';
import 'terminal_core/terminal_style.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_encoder.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_pane.dart';
import 'terminal_renderer/terminal_live_metal_surface.dart';
import 'terminal_session.dart';

const String terminalUsage = '''
Usage: Dart Terminal [application-options]

Application options:
  --working-directory=PATH   Initial command working directory.
  --auto-close-after=SECONDS Close automatically (for smoke testing).
''';

const String _runtimeWorkerName = 'dart_terminal_runtime_worker';
const int _runtimeSoftwareFailureExitCode = 70;
const int _runtimeTemporaryFailureExitCode = 75;
const Duration _runtimePtyFaultGracefulTimeout = Duration(milliseconds: 200);
const Duration _runtimePtyFaultFinalTimeout = Duration(milliseconds: 200);
const Duration _runtimePtyFaultCleanupTimeout = Duration(milliseconds: 200);
const Duration _hostTerminationTimeout = Duration(seconds: 1);

enum RuntimeShellExitTestScenario {
  none,
  cleanControlD,
  nonZero;

  static RuntimeShellExitTestScenario? byOptionName(String name) =>
      switch (name) {
        'clean-control-d' => RuntimeShellExitTestScenario.cleanControlD,
        'nonzero' => RuntimeShellExitTestScenario.nonZero,
        _ => null,
      };

  String get optionName => switch (this) {
    RuntimeShellExitTestScenario.none => 'none',
    RuntimeShellExitTestScenario.cleanControlD => 'clean-control-d',
    RuntimeShellExitTestScenario.nonZero => 'nonzero',
  };
}

final class TerminalOptions {
  const TerminalOptions({
    this.initialWorkingDirectory,
    this.autoCloseAfter,
    this.runtimeResourceStress = false,
    this.runtimeShutdownFaultInjection = false,
    this.runtimePtyExitFaultInjection = false,
    this.runtimeTerminalDisplayTest = false,
    this.runtimeShellExitTestScenario = RuntimeShellExitTestScenario.none,
    this.runtimeLifecycleScenario = RuntimeLifecycleScenario.normal,
    this.runtimeWorkerCommand =
        const RuntimeLifecycleWorkerCommand.unconfigured(),
  });

  factory TerminalOptions.parse(
    List<String> arguments, {
    Map<String, String>? environment,
    RuntimeLifecycleWorkerCommand? runtimeWorkerCommand,
  }) {
    String? initialWorkingDirectory;
    Duration? autoCloseAfter;
    var runtimeResourceStress = false;
    var runtimeShutdownFaultInjection = false;
    var runtimePtyExitFaultInjection = false;
    var runtimeTerminalDisplayTest = false;
    RuntimeShellExitTestScenario? runtimeShellExitTestScenario;
    RuntimeLifecycleScenario? runtimeLifecycleScenario;
    for (final String argument in arguments) {
      const String workingDirectoryPrefix = '--working-directory=';
      const String autoClosePrefix = '--auto-close-after=';
      const String lifecyclePrefix = '--runtime-lifecycle-scenario=';
      const String shellExitTestPrefix = '--runtime-shell-exit-test=';
      if (argument == '--runtime-resource-stress') {
        if (runtimeResourceStress) {
          throw const FormatException(
            '--runtime-resource-stress may only be supplied once',
          );
        }
        runtimeResourceStress = true;
        continue;
      }
      if (argument == '--runtime-shutdown-faults') {
        if (runtimeShutdownFaultInjection) {
          throw const FormatException(
            '--runtime-shutdown-faults may only be supplied once',
          );
        }
        runtimeShutdownFaultInjection = true;
        continue;
      }
      if (argument == '--runtime-pty-exit-fault') {
        if (runtimePtyExitFaultInjection) {
          throw const FormatException(
            '--runtime-pty-exit-fault may only be supplied once',
          );
        }
        runtimePtyExitFaultInjection = true;
        continue;
      }
      if (argument == '--runtime-terminal-display-test') {
        if (runtimeTerminalDisplayTest) {
          throw const FormatException(
            '--runtime-terminal-display-test may only be supplied once',
          );
        }
        runtimeTerminalDisplayTest = true;
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
      if (argument.startsWith(shellExitTestPrefix)) {
        if (runtimeShellExitTestScenario != null) {
          throw const FormatException(
            '--runtime-shell-exit-test may only be supplied once',
          );
        }
        final String value = argument.substring(shellExitTestPrefix.length);
        runtimeShellExitTestScenario =
            RuntimeShellExitTestScenario.byOptionName(value);
        if (runtimeShellExitTestScenario == null) {
          throw FormatException('unknown shell exit test scenario: $value');
        }
        continue;
      }
      throw FormatException('unknown application option: $argument');
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
    if (runtimeResourceStress &&
        (environment ?? Platform.environment)['DT_RUNTIME_RESOURCE_TEST'] !=
            '1') {
      throw const FormatException(
        'runtime resource stress requires the integration-test gate',
      );
    }
    if (runtimeResourceStress &&
        selectedScenario != RuntimeLifecycleScenario.normal) {
      throw const FormatException(
        'runtime resource stress cannot be combined with a lifecycle fault',
      );
    }
    if (runtimeShutdownFaultInjection &&
        (environment ??
                Platform.environment)['DT_RUNTIME_SHUTDOWN_FAULT_TEST'] !=
            '1') {
      throw const FormatException(
        'runtime shutdown faults require the integration-test gate',
      );
    }
    if (runtimeShutdownFaultInjection &&
        selectedScenario != RuntimeLifecycleScenario.workerUnexpectedExit) {
      throw const FormatException(
        'runtime shutdown faults require the worker-unexpected-exit scenario',
      );
    }
    if (runtimePtyExitFaultInjection &&
        (environment ??
                Platform.environment)['DT_RUNTIME_PTY_SHUTDOWN_FAULT_TEST'] !=
            '1') {
      throw const FormatException(
        'PTY exit fault requires the integration-test gate',
      );
    }
    if (runtimePtyExitFaultInjection &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection)) {
      throw const FormatException(
        'PTY exit fault cannot be combined with another runtime fault',
      );
    }
    final RuntimeShellExitTestScenario selectedShellExitTest =
        runtimeShellExitTestScenario ?? RuntimeShellExitTestScenario.none;
    if (selectedShellExitTest != RuntimeShellExitTestScenario.none &&
        (environment ?? Platform.environment)['DT_RUNTIME_SHELL_EXIT_TEST'] !=
            '1') {
      throw const FormatException(
        'shell exit test requires the integration-test gate',
      );
    }
    if (selectedShellExitTest != RuntimeShellExitTestScenario.none &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection)) {
      throw const FormatException(
        'shell exit test cannot be combined with automatic close or a '
        'runtime fault',
      );
    }
    if (runtimeTerminalDisplayTest &&
        (environment ??
                Platform.environment)['DT_RUNTIME_TERMINAL_DISPLAY_TEST'] !=
            '1') {
      throw const FormatException(
        'terminal display test requires the integration-test gate',
      );
    }
    if (runtimeTerminalDisplayTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'terminal display test cannot be combined with another runtime test',
      );
    }
    return TerminalOptions(
      initialWorkingDirectory: initialWorkingDirectory,
      autoCloseAfter: autoCloseAfter,
      runtimeResourceStress: runtimeResourceStress,
      runtimeShutdownFaultInjection: runtimeShutdownFaultInjection,
      runtimePtyExitFaultInjection: runtimePtyExitFaultInjection,
      runtimeTerminalDisplayTest: runtimeTerminalDisplayTest,
      runtimeShellExitTestScenario: selectedShellExitTest,
      runtimeLifecycleScenario: selectedScenario,
      runtimeWorkerCommand:
          runtimeWorkerCommand ??
          RuntimeLifecycleWorkerCommand(
            executable: MacosRuntime.bundleHelperPath(_runtimeWorkerName),
          ),
    );
  }

  final String? initialWorkingDirectory;
  final Duration? autoCloseAfter;
  final bool runtimeResourceStress;
  final bool runtimeShutdownFaultInjection;
  final bool runtimePtyExitFaultInjection;
  final bool runtimeTerminalDisplayTest;
  final RuntimeShellExitTestScenario runtimeShellExitTestScenario;
  final RuntimeLifecycleScenario runtimeLifecycleScenario;
  final RuntimeLifecycleWorkerCommand runtimeWorkerCommand;
}

final class TerminalApplication {
  const TerminalApplication({this.options = const TerminalOptions()});

  final TerminalOptions options;

  Future<void> run() async {
    final RuntimeLifecycleScenario scenario = options.runtimeLifecycleScenario;
    _writeLifecycleEvent(scenario, 'root-start', 0);
    TerminalRendererMacos.initialize();
    final MacosPtyBackend nativePtyBackend = MacosPtyBackend.open(
      MacosRuntime.bundleFrameworkPath(dartPtyMacosLibraryName),
    );
    final PtyBackend ptyBackend = options.runtimePtyExitFaultInjection
        ? _ExitNotificationSuppressingPtyBackend(nativePtyBackend)
        : nativePtyBackend;
    final AppKitApplication application = await AppKitApplication.attach();
    View? contentView;
    TerminalLiveMetalSurface? metalSurface;
    Window? window;
    TerminalPaneOwner? paneOwner;
    StreamSubscription<WindowEvent>? eventSubscription;
    StreamSubscription<AppKitEvent>? applicationEventSubscription;
    final List<StreamSubscription<MenuItemInvokedEvent>> menuSubscriptions =
        <StreamSubscription<MenuItemInvokedEvent>>[];
    final List<MenuItem> menuItems = <MenuItem>[];
    final List<Menu> menus = <Menu>[];
    Timer? autoCloseTimer;
    Timer? autoCloseConfirmationTimer;
    RuntimeLifecycleCoordinator? lifecycle;
    TerminalSession? terminalSession;
    var lifecycleWasShutDown = false;
    var forcePaneClose = false;
    var shutdownWasClean = true;
    var requestedExitCode = 0;
    void recordExitCode(int value) {
      MacosRuntime.setExitCode(value);
      requestedExitCode = value;
    }

    final Completer<void> closed = Completer<void>();
    final bool emitNativeEventWireObservation =
        Platform.environment['DT_RUNTIME_EVENT_WIRE_TEST'] == '1';
    var currentWindowWidth = 920.0;
    var currentWindowHeight = 580.0;

    try {
      final View createdContentView = TerminalRendererMacos.createView();
      contentView = createdContentView;
      final Window createdWindow =
          Window(
              frame: const Rect.fromLTWH(100, 90, 920, 580),
              title: 'Dart Terminal',
            )
            ..contentView = createdContentView
            ..keyEventRouting = KeyEventRouting.dartOnly
            ..defersCloseRequests = true;
      window = createdWindow;
      stdout.writeln('NATIVE_KEY_EVENT_ROUTING mode=dart-only');
      application.defersTerminationRequests = true;

      final TerminalPaneOwner createdPaneOwner = TerminalPaneOwner();
      paneOwner = createdPaneOwner;
      late final TerminalPane createdPane;
      createdPane = createdPaneOwner.createPane(
        sessionFactory:
            (
              TerminalSessionId id, {
              required void Function() onChanged,
              required void Function() onTerminated,
            }) {
              final bool isShellExitTest =
                  options.runtimeShellExitTestScenario !=
                  RuntimeShellExitTestScenario.none;
              final bool isTerminalDisplayTest =
                  options.runtimeTerminalDisplayTest;
              final TerminalSession createdSession = TerminalSession(
                id: id,
                ptyBackend: ptyBackend,
                initialWorkingDirectory: options.initialWorkingDirectory,
                environment: isShellExitTest || isTerminalDisplayTest
                    ? <String, String>{
                        ...Platform.environment,
                        'TERM': isTerminalDisplayTest
                            ? 'xterm-256color'
                            : 'dumb',
                        'LC_ALL': 'C',
                        'PS1': isTerminalDisplayTest
                            ? '__DT_DISPLAY_PROMPT__ '
                            : '__RUNTIME_SHELL_EXIT_READY__ ',
                        'RPS1': '',
                      }
                    : null,
                shellArguments: isShellExitTest || isTerminalDisplayTest
                    ? const <String>['-f']
                    : const <String>[],
                gracefulShutdownTimeout: options.runtimePtyExitFaultInjection
                    ? _runtimePtyFaultGracefulTimeout
                    : const Duration(seconds: 3),
                finalShutdownTimeout: options.runtimePtyExitFaultInjection
                    ? _runtimePtyFaultFinalTimeout
                    : const Duration(seconds: 1),
                cleanupStepTimeout: options.runtimePtyExitFaultInjection
                    ? _runtimePtyFaultCleanupTimeout
                    : const Duration(seconds: 1),
                onChanged: onChanged,
                onTerminated: onTerminated,
                lifecycleObserver:
                    (TerminalSessionLifecycleObservation observation) {
                      stdout.writeln(observation.machineLine());
                    },
                nativeObserver: (TerminalSessionNativeObservation observation) {
                  stdout.writeln(observation.machineLine());
                },
              );
              terminalSession = createdSession;
              return createdSession;
            },
        onChanged: () {
          final TerminalLiveMetalSurface? surface = metalSurface;
          if (surface != null && !surface.isDisposed) {
            surface.notifyScreenChanged();
          }
        },
        onExitRequested: createdWindow.requestClose,
        lifecycleObserver: (TerminalPaneLifecycleObservation observation) {
          stdout.writeln(observation.machineLine());
        },
        exitObserver: (TerminalPaneExitObservation observation) {
          stdout.writeln(observation.machineLine());
        },
      );
      final TerminalLiveMetalSurface createdMetalSurface =
          TerminalLiveMetalSurface.attach(
            sessionId: createdPane.sessionId,
            screenSet: terminalSession!.terminalScreenSet,
            view: createdContentView,
            logicalWidth: currentWindowWidth,
            logicalHeight: currentWindowHeight,
            backingScaleFactor: createdWindow.backingScaleFactor ?? 1,
            isVisible: createdWindow.isVisible,
            isOccluded: createdWindow.isOccluded,
            onFatalError: (Object error, StackTrace stackTrace) {
              if (!closed.isCompleted) {
                closed.completeError(error, stackTrace);
              }
            },
          );
      metalSurface = createdMetalSurface;
      stdout.writeln(
        'NATIVE_CUSTOM_VIEW '
        'provider=$terminalMetalViewProviderIdentifier attached=true '
        'renderer_bound=true',
      );
      if (options.runtimePtyExitFaultInjection) {
        stdout.writeln(
          'TERMINAL_PTY_FAULT exit_notification=suppressed gate=true',
        );
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
              createdPane.insertText(text);
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

      final TerminalKeyEventRouter keyEventRouter = TerminalKeyEventRouter();
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
          if (options.runtimeShutdownFaultInjection &&
              error is FormatException) {
            return;
          }
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
              final TerminalPaneCloseDecision decision = createdPane
                  .requestClose(force: forcePaneClose);
              final bool allow = decision == TerminalPaneCloseDecision.allow;
              stdout.writeln(
                'TERMINAL_PANE_CLOSE pane=${createdPane.id} '
                'session=${createdPane.sessionId} '
                'decision=${allow ? 'allow' : 'confirmation-required'} '
                'state=${createdPane.state.name}',
              );
              createdWindow.replyToCloseRequest(event, allow: allow);
            case WindowResizedEvent(:final width, :final height):
              currentWindowWidth = width;
              currentWindowHeight = height;
              final TerminalGridSize grid = createdMetalSurface.resizeViewport(
                logicalWidth: width,
                logicalHeight: height,
              );
              createdPane.resize(rows: grid.rows, columns: grid.columns);
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
              createdMetalSurface.updateWindowState(isVisible: isVisible);
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'visibility',
                  'value=$isVisible',
                );
              }
            case WindowOcclusionChangedEvent(:final isOccluded):
              createdMetalSurface.updateWindowState(isOccluded: isOccluded);
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'occlusion',
                  'value=$isOccluded',
                );
              }
            case WindowBackingScaleChangedEvent(:final backingScaleFactor):
              createdMetalSurface.updateBackingScale(backingScaleFactor);
              final TerminalGridSize grid = createdMetalSurface.gridSizeFor(
                logicalWidth: currentWindowWidth,
                logicalHeight: currentWindowHeight,
              );
              createdPane.resize(rows: grid.rows, columns: grid.columns);
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
              keyEventRouter.handleKeyDown(event, createdPane);
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

      final TerminalGridSize initialGrid = createdMetalSurface.resizeViewport(
        logicalWidth: currentWindowWidth,
        logicalHeight: currentWindowHeight,
      );
      createdPane.resize(rows: initialGrid.rows, columns: initialGrid.columns);
      await createdPane.start();
      stdout.writeln(
        'TERMINAL_PANE event=started pane=${createdPane.id} '
        'session=${createdPane.sessionId}',
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
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);

      if (options.runtimeShutdownFaultInjection) {
        await _exerciseShutdownFaultInjection(application);
      }

      switch (scenario) {
        case RuntimeLifecycleScenario.normal:
          await _expectResponse(createdLifecycle);
          if (options.runtimeResourceStress) {
            _exerciseResourceStress(application);
          }
          final RuntimeShellExitTestScenario shellExitTest =
              options.runtimeShellExitTestScenario;
          if (options.runtimeTerminalDisplayTest) {
            await _exerciseTerminalDisplay(
              createdLifecycle,
              terminalSession!,
              createdPane,
              createdMetalSurface,
              createdWindow,
              keyEventRouter,
            );
          } else if (shellExitTest != RuntimeShellExitTestScenario.none) {
            await _exerciseShellExitPolicy(
              shellExitTest,
              createdLifecycle,
              terminalSession!,
              createdPane,
              createdWindow,
            );
          }
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
          recordExitCode(_runtimeTemporaryFailureExitCode);
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
            forcePaneClose = true;
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
            autoCloseConfirmationTimer = Timer(
              const Duration(milliseconds: 100),
              () {
                if (!createdWindow.isClosed && !createdWindow.isDisposed) {
                  quitItem.performAction();
                }
              },
            );
          }
        });
      }
      await closed.future;
    } finally {
      try {
        MacosRuntime.recordDiagnosticPhase(
          RuntimeDiagnosticPhase.shutdownStarted,
        );
        autoCloseTimer?.cancel();
        autoCloseConfirmationTimer?.cancel();
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
        if (metalSurface != null && !metalSurface.isDisposed) {
          metalSurface.dispose();
        }
        final TerminalPaneOwner? owner = paneOwner;
        if (owner != null) {
          final TerminalPaneOwnerShutdownResult result = await owner.shutdown();
          for (final TerminalPaneSessionShutdownResult session
              in result.sessions) {
            stdout.writeln(session.machineLine());
          }
          stdout.writeln(result.machineLine());
          if (!result.isClean) {
            shutdownWasClean = false;
            recordExitCode(_runtimeTemporaryFailureExitCode);
          }
        }
        if (window != null && !window.isDisposed) {
          window.dispose();
        }
        if (contentView != null && !contentView.isDisposed) {
          contentView.dispose();
        }
        _writeLifecycleEvent(scenario, 'root-exit', lifecycle?.generation ?? 0);
        MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStopped);
        final bool auditFinalNativeHandles =
            options.runtimeResourceStress ||
            options.runtimeShutdownFaultInjection;
        final int? finalLiveHandleCount = auditFinalNativeHandles
            ? application.debugLiveObjectCount
            : null;
        if (finalLiveHandleCount != null) {
          stdout.writeln(
            options.runtimeShutdownFaultInjection
                ? 'NATIVE_SHUTDOWN_FAULT_FINAL handles=$finalLiveHandleCount'
                : 'NATIVE_RESOURCE_FINAL handles=$finalLiveHandleCount',
          );
        }
        if (finalLiveHandleCount != null) {
          _expectLifecycle(
            finalLiveHandleCount == 0,
            'product cleanup left $finalLiveHandleCount native handles',
          );
        }
      } on Object {
        shutdownWasClean = false;
        if (requestedExitCode == 0) {
          recordExitCode(_runtimeSoftwareFailureExitCode);
        }
        rethrow;
      } finally {
        try {
          await application.terminate().timeout(_hostTerminationTimeout);
        } on Object {
          shutdownWasClean = false;
          if (requestedExitCode == 0) {
            recordExitCode(_runtimeSoftwareFailureExitCode);
          }
          stdout.writeln(
            'TERMINAL_HOST_TERMINATION fallback=true '
            'exit_code=$requestedExitCode',
          );
          MacosRuntime.requestTermination(exitCode: requestedExitCode);
        }
      }
    }
    stdout.writeln(
      shutdownWasClean && requestedExitCode == 0
          ? 'Dart Terminal shut down cleanly.'
          : 'Dart Terminal shut down with classified recovery.',
    );
  }

  static Future<void> _exerciseShellExitPolicy(
    RuntimeShellExitTestScenario scenario,
    RuntimeLifecycleCoordinator lifecycle,
    TerminalSession session,
    TerminalPane pane,
    Window window,
  ) async {
    final int? workerProcessId = lifecycle.workerPid;
    _expectLifecycle(
      workerProcessId != null,
      'shell exit policy test requires a live runtime worker',
    );
    await _waitForShellExitTestPrompt(session);
    switch (scenario) {
      case RuntimeShellExitTestScenario.none:
        throw StateError('shell exit policy test requires a scenario');
      case RuntimeShellExitTestScenario.cleanControlD:
        pane.sendEndOfFile();
      case RuntimeShellExitTestScenario.nonZero:
        pane.insertText('exit 23');
        await pane.submit();
    }
    await session.waitForTermination().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    final TerminalPaneSessionExitDisposition expectedDisposition =
        scenario == RuntimeShellExitTestScenario.cleanControlD
        ? TerminalPaneSessionExitDisposition.clean
        : TerminalPaneSessionExitDisposition.nonZero;
    final bool expectedPaneState =
        scenario == RuntimeShellExitTestScenario.cleanControlD
        ? pane.state == TerminalPaneState.exited ||
              pane.state == TerminalPaneState.closing
        : pane.state == TerminalPaneState.exited;
    _expectLifecycle(
      session.exitDisposition == expectedDisposition && expectedPaneState,
      '${scenario.optionName} did not publish its expected pane exit',
    );
    if (scenario == RuntimeShellExitTestScenario.cleanControlD) {
      _expectLifecycle(
        session.exit?.exitCode == 0 && session.exit?.signal == null,
        'Control-D did not preserve the clean zsh exit status',
      );
    } else {
      _expectLifecycle(
        session.exit?.exitCode == 23 &&
            session.exit?.signal == null &&
            pane.render().contains('[shell exited with status 23]') &&
            !window.isClosed &&
            !window.isDisposed,
        'nonzero zsh exit was not retained with a visible status',
      );
    }
    stdout.writeln(
      'TERMINAL_SHELL_EXIT_TEST scenario=${scenario.optionName} '
      'shell_exit=${session.exit?.exitCode ?? -1} '
      'action=${scenario == RuntimeShellExitTestScenario.cleanControlD ? 'close' : 'retain'} '
      'worker_pid=$workerProcessId',
    );
    if (scenario == RuntimeShellExitTestScenario.nonZero) {
      window.requestClose();
    }
  }

  static Future<void> _exerciseTerminalDisplay(
    RuntimeLifecycleCoordinator lifecycle,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    TerminalKeyEventRouter keyEventRouter,
  ) async {
    const String prompt = '__DT_DISPLAY_PROMPT__ ';
    const String colorMarker = '__DT_COLOR__';
    const String wrapStart = '__DT_WRAP_START__';
    const String wrapEnd = '__DT_WRAP_END__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final bool modeKey = await _exerciseModeAwareKeyInput(
      session,
      pane,
      keyEventRouter,
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalLiveMetalSurfaceSnapshot baseline = surface.snapshot();
    final bool systemFont =
        baseline.usesMacosSystemMonospaceFont &&
        baseline.fontPointSize == TerminalLiveMetalSurface.defaultFontPointSize;
    final TerminalScreen initialScreen = session.terminalScreenSet.activeScreen;
    final int fillerLines = initialScreen.rows + 12;
    final String wrappedPayload =
        wrapStart +
        List<String>.filled(initialScreen.columns * 2, 'W').join() +
        wrapEnd;
    pane.insertText(
      "for i in {1..$fillerLines}; do printf 'FILL%03d\\n' \$i; done; "
      "printf '\\033[1;31m$colorMarker\\033[0m\\n'; "
      "printf '$wrappedPayload\\n'",
    );
    await pane.submit();

    final Stopwatch deadline = Stopwatch()..start();
    var sgrStripped = false;
    var styled = false;
    var promptBottom = false;
    var newestFrame = false;
    var frameBounded = false;
    var wrappedRows = 0;
    while (deadline.elapsed < const Duration(seconds: 8)) {
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      final _TerminalAsciiPosition? color = _findAscii(screen, colorMarker);
      final String bottom = _asciiRow(screen, screen.rows - 1);
      wrappedRows = <int>[
        for (int row = 0; row < screen.rows; row++)
          if (screen.rowFlagsAt(row) & TerminalRowFlags.softWrapped != 0) row,
      ].length;
      sgrStripped = _screenHasNoRawSgr(screen);
      styled =
          color != null &&
          TerminalStyleAttributes.has(
            screen.styleTable.attributesAt(
              screen.styleAt(color.row, color.column),
            ),
            TerminalStyleAttributes.bold,
          ) &&
          screen.foregroundAt(color.row, color.column) != 0;
      promptBottom =
          bottom.contains(prompt) &&
          screen.cursorRow == screen.rows - 1 &&
          screen.cursorColumn >= prompt.length;
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      newestFrame =
          snapshot.acceptedFrameCount > baseline.acceptedFrameCount &&
          snapshot.lastAcceptedModelRevision ==
              snapshot.lastAppliedDamageGeneration &&
          snapshot.lastAcceptedModelRevision > 0;
      frameBounded =
          snapshot.pendingFrameCount <= 1 && snapshot.liveAtlasPinCount <= 3;
      if (sgrStripped &&
          styled &&
          wrappedRows >= 2 &&
          promptBottom &&
          newestFrame &&
          frameBounded &&
          systemFont &&
          modeKey) {
        final int? workerProcessId = lifecycle.workerPid;
        _expectLifecycle(
          workerProcessId != null,
          'terminal display test lost its runtime worker',
        );
        stdout.writeln(
          'TERMINAL_DISPLAY_TEST sgr_stripped=$sgrStripped styled=$styled '
          'wrapped_rows=$wrappedRows prompt_bottom=$promptBottom '
          'metal_default=true newest_frame=$newestFrame '
          'frame_bounded=$frameBounded system_font=$systemFont '
          'mode_key=$modeKey '
          'font_size=${baseline.fontPointSize.toStringAsFixed(1)} '
          'rows=${screen.rows} '
          'columns=${screen.columns} '
          'frame_build_delta='
          '${snapshot.frameBuildCount - baseline.frameBuildCount}',
        );
        _expectLifecycle(
          pane.requestClose(force: true) == TerminalPaneCloseDecision.allow,
          'terminal display test could not begin deterministic pane close',
        );
        window.close();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'terminal display acceptance did not settle: '
      'sgr_stripped=$sgrStripped styled=$styled wrapped_rows=$wrappedRows '
      'prompt_bottom=$promptBottom newest_frame=$newestFrame '
      'frame_bounded=$frameBounded system_font=$systemFont '
      'mode_key=$modeKey '
      'font_size=${baseline.fontPointSize}',
    );
  }

  static Future<bool> _exerciseModeAwareKeyInput(
    TerminalSession session,
    TerminalPane pane,
    TerminalKeyEventRouter keyEventRouter,
  ) async {
    const String expectedMarker = '__DT_KEY_1b4f41__';
    pane.insertText(
      "printf '\\033[?1h'; stty raw -echo; "
      "key=\$(dd bs=1 count=3 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "stty sane; printf '\\033[?1l\\r\\n__DT_KEY_%s__\\r\\n' \"\$key\"",
    );
    await pane.submit();

    final Stopwatch modeDeadline = Stopwatch()..start();
    while (!session.keyboardModes.applicationCursorKeys &&
        modeDeadline.elapsed < const Duration(seconds: 3)) {
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before enabling application cursor mode',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      session.keyboardModes.applicationCursorKeys,
      'display-test did not observe DEC application cursor mode',
    );

    final TerminalKeyRouteResult route = keyEventRouter.handleKeyDown(
      const AppKitKeyEvent(
        windowHandle: 1,
        monotonicMicros: 1,
        kind: AppKitKeyEventKind.down,
        keyCode: 126,
        modifiers: ModifierKeys(ModifierKeys.functionBit),
        isRepeat: false,
        characters: '\uf700',
        charactersIgnoringModifiers: '\uf700',
      ),
      pane,
    );
    _expectLifecycle(
      route.disposition == TerminalKeyRouteDisposition.encoded &&
          route.encodedByteCount == 3,
      'display-test application cursor event was not encoded once',
    );

    final Stopwatch markerDeadline = Stopwatch()..start();
    while (markerDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      if (_findAscii(screen, expectedMarker) != null) {
        return true;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before reporting encoded key bytes',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'display-test did not receive application cursor bytes $expectedMarker',
    );
  }

  static Future<void> _waitForTerminalDisplayPrompt(
    TerminalSession session, {
    required int minimumOccurrences,
  }) async {
    const String prompt = '__DT_DISPLAY_PROMPT__ ';
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      final int occurrences = <int>[
        for (int row = 0; row < screen.rows; row++)
          if (_asciiRow(screen, row).contains(prompt)) row,
      ].length;
      if (occurrences >= minimumOccurrences) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before publishing its prompt',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('display-test zsh did not publish its prompt');
  }

  static _TerminalAsciiPosition? _findAscii(
    TerminalScreen screen,
    String pattern,
  ) {
    for (int row = 0; row < screen.rows; row++) {
      final int column = _asciiRow(screen, row).indexOf(pattern);
      if (column >= 0) {
        return _TerminalAsciiPosition(row: row, column: column);
      }
    }
    return null;
  }

  static String _asciiRow(TerminalScreen screen, int row) =>
      String.fromCharCodes(<int>[
        for (int column = 0; column < screen.columns; column++)
          screen.widthFlagsAt(row, column) & TerminalCellFlags.grapheme != 0 ||
                  screen.widthFlagsAt(row, column) &
                          TerminalCellFlags.widthMask ==
                      TerminalCellFlags.continuation ||
                  screen.contentAt(row, column) == 0
              ? 0x20
              : screen.contentAt(row, column),
      ]);

  static bool _screenHasNoRawSgr(TerminalScreen screen) {
    for (int row = 0; row < screen.rows; row++) {
      final String text = _asciiRow(screen, row);
      if (text.contains('[0m') || text.contains('[1;31m')) return false;
      for (int column = 0; column < screen.columns; column++) {
        if (screen.contentAt(row, column) == 0x1b) return false;
      }
    }
    return true;
  }

  static Future<void> _waitForShellExitTestPrompt(
    TerminalSession session,
  ) async {
    const String marker = '__RUNTIME_SHELL_EXIT_READY__';
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (session.buffer.outputText.contains(marker)) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'test zsh exited before its first prompt',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('test zsh did not publish its prompt');
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

  static void _exerciseResourceStress(AppKitApplication application) {
    const int iterationCount = 1000;
    final int baseline = application.debugLiveObjectCount;
    final Stopwatch stopwatch = Stopwatch()..start();
    var peak = baseline;
    for (var iteration = 0; iteration < iterationCount; ++iteration) {
      View? temporaryView;
      Window? temporaryWindow;
      try {
        temporaryView = View();
        temporaryWindow = Window(
          frame: const Rect.fromLTWH(0, 0, 64, 32),
          title: 'Dart Terminal resource probe',
        )..contentView = temporaryView;
        final int activeCount = application.debugLiveObjectCount;
        peak = activeCount > peak ? activeCount : peak;
        _expectLifecycle(
          activeCount == baseline + 2,
          'resource iteration $iteration registered '
          '${activeCount - baseline} handles instead of 2',
        );
      } finally {
        if (temporaryWindow != null && !temporaryWindow.isDisposed) {
          temporaryWindow.dispose();
        }
        if (temporaryView != null && !temporaryView.isDisposed) {
          temporaryView.dispose();
        }
      }
      final int currentCount = application.debugLiveObjectCount;
      _expectLifecycle(
        currentCount == baseline,
        'resource iteration $iteration changed native baseline '
        '$baseline to $currentCount',
      );
    }
    stopwatch.stop();
    final int finalCount = application.debugLiveObjectCount;
    stdout.writeln(
      'NATIVE_RESOURCE_STRESS iterations=$iterationCount baseline=$baseline '
      'peak=$peak final=$finalCount elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
  }

  static Future<void> _exerciseShutdownFaultInjection(
    AppKitApplication application,
  ) async {
    final int baseline = application.debugLiveObjectCount;
    var malformedErrors = 0;
    var lateOwnerEvents = 0;
    var continuedEvents = 0;
    final StreamSubscription<AppKitEvent> applicationEvents = application.events
        .listen(
          (AppKitEvent event) {
            if (event case ApplicationActiveChangedEvent(
              monotonicNanoseconds: 2000,
            )) {
              ++continuedEvents;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (error is FormatException) {
              ++malformedErrors;
              return;
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    final View view = View();
    final Window window = Window(
      frame: const Rect.fromLTWH(0, 0, 64, 32),
      title: 'Dart Terminal shutdown fault probe',
    )..contentView = view;
    final StreamSubscription<WindowEvent> windowEvents = window.events.listen((
      _,
    ) {
      ++lateOwnerEvents;
    });
    final int windowHandle = appkit_testing.nativeWindowHandleForTesting(
      window,
    );
    try {
      window.dispose();
      window.dispose();
      view.dispose();
      view.dispose();
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        4,
        1,
        windowHandle,
        windowHandle >> 32,
        1000,
        0,
      ]);
      appkit_testing.injectRawAppKitEventForTesting(application, 'malformed');
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        4,
        30,
        0,
        0,
        2000,
        0,
        application.isActive,
      ]);
      final int finalCount = application.debugLiveObjectCount;
      _expectLifecycle(
        malformedErrors == 1 &&
            lateOwnerEvents == 0 &&
            continuedEvents == 1 &&
            finalCount == baseline,
        'shutdown fault observations were malformed: '
        'errors=$malformedErrors late=$lateOwnerEvents '
        'continued=$continuedEvents baseline=$baseline final=$finalCount',
      );
      stdout.writeln(
        'NATIVE_SHUTDOWN_FAULT malformed_errors=$malformedErrors '
        'late_owner_events=$lateOwnerEvents double_dispose=true '
        'continued_events=$continuedEvents baseline=$baseline '
        'final=$finalCount',
      );
    } finally {
      if (!window.isDisposed) {
        window.dispose();
      }
      if (!view.isDisposed) {
        view.dispose();
      }
      await windowEvents.cancel();
      await applicationEvents.cancel();
    }
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
}

final class _TerminalAsciiPosition {
  const _TerminalAsciiPosition({required this.row, required this.column});

  final int row;
  final int column;
}

enum TerminalKeyRouteDisposition { ignored, encoded, action }

/// Observable single-outcome result of routing one AppKit key event.
final class TerminalKeyRouteResult {
  const TerminalKeyRouteResult._(
    this.disposition, {
    this.encodedByteCount = 0,
    this.action,
  });

  static const TerminalKeyRouteResult ignored = TerminalKeyRouteResult._(
    TerminalKeyRouteDisposition.ignored,
  );

  factory TerminalKeyRouteResult.encoded(int byteCount) =>
      TerminalKeyRouteResult._(
        TerminalKeyRouteDisposition.encoded,
        encodedByteCount: byteCount,
      );

  factory TerminalKeyRouteResult.action(TerminalKeyBindingAction action) =>
      TerminalKeyRouteResult._(
        TerminalKeyRouteDisposition.action,
        action: action,
      );

  final TerminalKeyRouteDisposition disposition;
  final int encodedByteCount;
  final TerminalKeyBindingAction? action;
}

/// Resolves and encodes one AppKit key-down event for the active terminal pane.
///
/// Each handled event invokes exactly one action or one bounded pane write.
/// Native AppKit menu key equivalents are consumed before this router receives
/// events, so it never redispatches menu commands.
final class TerminalKeyEventRouter {
  TerminalKeyEventRouter({
    TerminalKeyBindingEngine? bindingEngine,
    TerminalKeyEncoder? encoder,
  }) : _bindingEngine = bindingEngine ?? TerminalKeyBindingEngine.standard(),
       _encoder = encoder ?? TerminalKeyEncoder();

  final TerminalKeyBindingEngine _bindingEngine;
  final TerminalKeyEncoder _encoder;

  TerminalKeyRouteResult handleKeyDown(
    AppKitKeyEvent appKitEvent,
    TerminalPane pane,
  ) {
    if (appKitEvent.kind != AppKitKeyEventKind.down) {
      return TerminalKeyRouteResult.ignored;
    }
    final TerminalKeyEvent event = TerminalAppKitKeyAdapter.adapt(appKitEvent);
    final TerminalKeyBindingResolution resolution = _bindingEngine.resolve(
      event,
    );
    switch (resolution.kind) {
      case TerminalKeyBindingResolutionKind.action:
        final TerminalKeyBindingAction action = resolution.action!;
        _performAction(action, pane);
        return TerminalKeyRouteResult.action(action);
      case TerminalKeyBindingResolutionKind.passthrough:
        return _encode(_withoutCommand(event), pane);
      case TerminalKeyBindingResolutionKind.noMatch:
        return _encode(event, pane);
    }
  }

  TerminalKeyRouteResult _encode(TerminalKeyEvent event, TerminalPane pane) {
    final Uint8List bytes = _encoder.encode(event, modes: pane.keyboardModes);
    if (bytes.isEmpty) {
      return TerminalKeyRouteResult.ignored;
    }
    pane.sendInput(bytes);
    return TerminalKeyRouteResult.encoded(bytes.length);
  }

  static TerminalKeyEvent _withoutCommand(TerminalKeyEvent event) =>
      TerminalKeyEvent(
        physicalKey: event.physicalKey,
        text: event.text,
        unmodifiedText: event.unmodifiedText,
        modifiers: TerminalKeyModifiers(
          capsLock: event.modifiers.capsLock,
          shift: event.modifiers.shift,
          control: event.modifiers.control,
          option: event.modifiers.option,
          numericPad: event.modifiers.numericPad,
          function: event.modifiers.function,
        ),
        isRepeat: event.isRepeat,
      );

  static void _performAction(
    TerminalKeyBindingAction action,
    TerminalPane pane,
  ) {
    switch (action) {
      case TerminalKeyBindingAction.sendEndOfFile:
        pane.sendEndOfFile();
      case TerminalKeyBindingAction.sendInterruptSignal:
        pane.interrupt();
      case TerminalKeyBindingAction.sendSuspendSignal:
        pane.suspend();
      case TerminalKeyBindingAction.sendQuitSignal:
        pane.quitForegroundProcess();
    }
  }
}

final class _ExitNotificationSuppressingPtyBackend implements PtyBackend {
  const _ExitNotificationSuppressingPtyBackend(this._delegate);

  final PtyBackend _delegate;

  @override
  Future<PtyProcess> start(
    PtyCommand command, {
    PtySize initialSize = const PtySize(rows: 24, columns: 80),
    int readHighWaterBytes = 1024 * 1024,
    int readLowWaterBytes = 512 * 1024,
    int writeCapacityBytes = 1024 * 1024,
    bool enableDiagnostics = false,
  }) async => _ExitNotificationSuppressingPtyProcess(
    await _delegate.start(
      command,
      initialSize: initialSize,
      readHighWaterBytes: readHighWaterBytes,
      readLowWaterBytes: readLowWaterBytes,
      writeCapacityBytes: writeCapacityBytes,
      enableDiagnostics: enableDiagnostics,
    ),
  );
}

final class _ExitNotificationSuppressingPtyProcess implements PtyProcess {
  _ExitNotificationSuppressingPtyProcess(this._delegate) {
    _delegate.exit.ignore();
  }

  final PtyProcess _delegate;
  final Completer<PtyExit> _suppressedExit = Completer<PtyExit>();

  @override
  int get pid => _delegate.pid;

  @override
  Stream<Uint8List> get output => _delegate.output;

  @override
  Stream<PtyDiagnosticEvent> get diagnostics => _delegate.diagnostics;

  @override
  Future<PtyExit> get exit => _suppressedExit.future;

  @override
  PtyStats? get finalStats => _delegate.finalStats;

  @override
  PtyWriteResult write(Uint8List bytes) => _delegate.write(bytes);

  @override
  PtyWriteReceipt writeTracked(Uint8List bytes) =>
      _delegate.writeTracked(bytes);

  @override
  void resize(PtySize size) => _delegate.resize(size);

  @override
  void sendSignal(PtySignal signal) => _delegate.sendSignal(signal);

  @override
  void close({Duration gracePeriod = const Duration(seconds: 2)}) =>
      _delegate.close(gracePeriod: gracePeriod);

  @override
  void forceClose() => _delegate.forceClose();

  @override
  Future<void> dispose() => _delegate.dispose();
}
