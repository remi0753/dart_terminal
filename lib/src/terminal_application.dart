import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/testing.dart' as appkit_testing;
import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'runtime_lifecycle.dart';
import 'terminal_action_menu.dart';
import 'terminal_action_registry.dart';
import 'terminal_application_state.dart';
import 'terminal_command_palette.dart';
import 'terminal_core/terminal_hyperlink.dart';
import 'terminal_core/terminal_mouse_modes.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_core/terminal_screen.dart';
import 'terminal_core/terminal_screen_parser_sink.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_core/terminal_style.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_focus_reporter.dart';
import 'terminal_input/terminal_hyperlink_interaction.dart';
import 'terminal_input/terminal_input_matrix.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_input/terminal_key_encoder.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_input/terminal_mouse_event.dart';
import 'terminal_input/terminal_mouse_router.dart';
import 'terminal_input/terminal_paste.dart';
import 'terminal_input/terminal_scroll_router.dart';
import 'terminal_input/terminal_selection_autoscroll.dart';
import 'terminal_input/terminal_selection_gesture.dart';
import 'terminal_input/terminal_text_input_event_router.dart';
import 'terminal_native_hierarchy.dart';
import 'terminal_pane.dart';
import 'terminal_renderer/terminal_live_metal_surface.dart';
import 'terminal_session.dart';
import 'terminal_terminfo_environment.dart';

const String terminalUsage = '''
Usage: Dart Terminal [application-options]

Application options:
  --working-directory=PATH   Initial command working directory.
  --auto-close-after=SECONDS Close automatically (for smoke testing).
''';

const String _runtimeWorkerName = 'dart_terminal_runtime_worker';
const int _runtimeSoftwareFailureExitCode = 70;
const int _runtimeTemporaryFailureExitCode = 75;
const int _appKitLimitExceededStatus = 10;
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
    this.runtimeClipboardTest = false,
    this.runtimeNativeHierarchyTest = false,
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
    var runtimeClipboardTest = false;
    var runtimeNativeHierarchyTest = false;
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
      if (argument == '--runtime-clipboard-test') {
        if (runtimeClipboardTest) {
          throw const FormatException(
            '--runtime-clipboard-test may only be supplied once',
          );
        }
        runtimeClipboardTest = true;
        continue;
      }
      if (argument == '--runtime-native-hierarchy-test') {
        if (runtimeNativeHierarchyTest) {
          throw const FormatException(
            '--runtime-native-hierarchy-test may only be supplied once',
          );
        }
        runtimeNativeHierarchyTest = true;
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
    if (runtimeClipboardTest &&
        (environment ?? Platform.environment)['DT_RUNTIME_CLIPBOARD_TEST'] !=
            '1') {
      throw const FormatException(
        'clipboard test requires the integration-test gate',
      );
    }
    if (runtimeClipboardTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'clipboard test cannot be combined with another runtime test',
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
    if (runtimeNativeHierarchyTest &&
        (environment ??
                Platform.environment)['DT_RUNTIME_NATIVE_HIERARCHY_TEST'] !=
            '1') {
      throw const FormatException(
        'native hierarchy test requires the integration-test gate',
      );
    }
    if (runtimeNativeHierarchyTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'native hierarchy test cannot be combined with another runtime test',
      );
    }
    return TerminalOptions(
      initialWorkingDirectory: initialWorkingDirectory,
      autoCloseAfter: autoCloseAfter,
      runtimeResourceStress: runtimeResourceStress,
      runtimeShutdownFaultInjection: runtimeShutdownFaultInjection,
      runtimePtyExitFaultInjection: runtimePtyExitFaultInjection,
      runtimeTerminalDisplayTest: runtimeTerminalDisplayTest,
      runtimeClipboardTest: runtimeClipboardTest,
      runtimeNativeHierarchyTest: runtimeNativeHierarchyTest,
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
  final bool runtimeClipboardTest;
  final bool runtimeNativeHierarchyTest;
  final RuntimeShellExitTestScenario runtimeShellExitTestScenario;
  final RuntimeLifecycleScenario runtimeLifecycleScenario;
  final RuntimeLifecycleWorkerCommand runtimeWorkerCommand;
}

final class TerminalApplication {
  const TerminalApplication({this.options = const TerminalOptions()});

  static const String _productWindowTitle = 'Dart Terminal';

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
    String? bundledTerminfoEntry;
    try {
      bundledTerminfoEntry = MacosRuntime.bundleResourcePath(
        TerminalTerminfoEnvironment.compiledEntryRelativePath,
      );
    } on MacosRuntimeException {
      bundledTerminfoEntry = null;
    }
    final TerminalTerminfoEnvironment terminfoEnvironment =
        TerminalTerminfoEnvironment.resolve(
          parentEnvironment: Platform.environment,
          bundledEntryPath: bundledTerminfoEntry,
        );
    stdout.writeln(terminfoEnvironment.machineLine());
    if (options.runtimeNativeHierarchyTest) {
      await _runNativeHierarchyProductAcceptance(
        application,
        ptyBackend,
        terminfoEnvironment,
        options.runtimeWorkerCommand,
        options.initialWorkingDirectory,
      );
      return;
    }
    final _TerminalClipboardProductObservation? clipboardObservation =
        options.runtimeClipboardTest
        ? _TerminalClipboardProductObservation()
        : null;
    final _MemoryTerminalClipboard? runtimeClipboard =
        options.runtimeClipboardTest ? _MemoryTerminalClipboard() : null;
    final _TerminalClipboard clipboard = runtimeClipboard != null
        ? runtimeClipboard
        : _AppKitTerminalClipboard(application.generalPasteboard);
    final _TerminalHyperlinkProductObservation hyperlinkObservation =
        _TerminalHyperlinkProductObservation();
    final TerminalPasteConfirmationGate pasteConfirmationGate =
        TerminalPasteConfirmationGate();
    final Stopwatch pasteConfirmationClock = Stopwatch()..start();
    View? contentView;
    TerminalLiveMetalSurface? metalSurface;
    TerminalTextInputClient? textInputClient;
    Window? window;
    TerminalApplicationState? applicationState;
    StreamSubscription<WindowEvent>? eventSubscription;
    StreamSubscription<AppKitEvent>? applicationEventSubscription;
    StreamSubscription<TerminalTextInputEvent>? textInputSubscription;
    _TerminalSelectionProductOwner? selectionOwner;
    TerminalAppKitMenuProjection? actionMenuProjection;
    TerminalCommandPalettePresenter? commandPalettePresenter;
    Timer? autoCloseTimer;
    Timer? autoCloseConfirmationTimer;
    RuntimeLifecycleCoordinator? lifecycle;
    TerminalSession? terminalSession;
    var lifecycleWasShutDown = false;
    var forcePaneClose = false;
    var shutdownWasClean = true;
    var requestedExitCode = 0;
    var terminalInputWriteEnqueuedCount = 0;
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
              title: _productWindowTitle,
            )
            ..contentView = createdContentView
            ..keyEventRouting = KeyEventRouting.appKitOnly
            ..defersCloseRequests = true;
      window = createdWindow;
      stdout.writeln('NATIVE_KEY_EVENT_ROUTING mode=appkit-only');
      final TerminalTextInputClient createdTextInputClient =
          TerminalTextInputClient.attach(createdContentView);
      textInputClient = createdTextInputClient;
      application.defersTerminationRequests = true;

      final TerminalApplicationState createdApplicationState =
          TerminalApplicationState();
      applicationState = createdApplicationState;
      final TerminalPaneConfiguration
      paneConfiguration = TerminalPaneConfiguration(
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
              final bool isClipboardTest = options.runtimeClipboardTest;
              final bool usesDeterministicShell =
                  isShellExitTest || isTerminalDisplayTest || isClipboardTest;
              final TerminalSession createdSession = TerminalSession(
                id: id,
                ptyBackend: ptyBackend,
                initialWorkingDirectory: options.initialWorkingDirectory,
                environment: usesDeterministicShell
                    ? <String, String>{
                        ...terminfoEnvironment.environment,
                        'TERM': isTerminalDisplayTest || isClipboardTest
                            ? 'xterm-256color'
                            : 'dumb',
                        'LC_ALL': 'C',
                        'PS1': isTerminalDisplayTest
                            ? '__DT_DISPLAY_PROMPT__ '
                            : isClipboardTest
                            ? '__DT_DISPLAY_PROMPT__ '
                            : '__RUNTIME_SHELL_EXIT_READY__ ',
                        'RPS1': '',
                      }
                    : terminfoEnvironment.environment,
                shellArguments: usesDeterministicShell
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
                  if (observation.event.stage ==
                      PtyDiagnosticStage.writeEnqueued) {
                    terminalInputWriteEnqueuedCount++;
                  }
                  clipboardObservation?.recordNative(observation.event);
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
          if (!createdWindow.isClosed && !createdWindow.isDisposed) {
            final String desiredTitle =
                terminalSession?.terminalScreenSet.metadata.windowTitle ??
                _productWindowTitle;
            if (createdWindow.title != desiredTitle) {
              createdWindow.title = desiredTitle;
            }
          }
          selectionOwner?.synchronize();
          actionMenuProjection?.refresh();
        },
        onExitRequested: createdWindow.requestClose,
        lifecycleObserver: (TerminalPaneLifecycleObservation observation) {
          stdout.writeln(observation.machineLine());
        },
        exitObserver: (TerminalPaneExitObservation observation) {
          stdout.writeln(observation.machineLine());
        },
      );
      final TerminalWindowState logicalWindow = await createdApplicationState
          .createWindow(paneConfiguration);
      final TerminalPane createdPane = createdApplicationState.paneForId(
        logicalWindow.selectedTab.focusedPaneId,
      )!;
      stdout.writeln(
        createdApplicationState.machineLineForPane(createdPane.id),
      );
      final TerminalKeyEventRouter keyEventRouter = TerminalKeyEventRouter();
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
            onCaretGeometryChanged: (TerminalCaretRect rectangle) {
              createdTextInputClient.publishCaretRect(
                x: rectangle.x,
                y: rectangle.y,
                width: rectangle.width,
                height: rectangle.height,
              );
            },
            onFatalError: (Object error, StackTrace stackTrace) {
              if (!closed.isCompleted) {
                closed.completeError(error, stackTrace);
              }
            },
          );
      metalSurface = createdMetalSurface;
      final TerminalTextInputEventRouter textInputEventRouter =
          TerminalTextInputEventRouter(
            clientId: createdTextInputClient.clientId,
            onRawKeyDown: (TerminalKeyEvent event) {
              keyEventRouter.handleTerminalKeyDown(event, createdPane);
            },
            onPreedit:
                ({
                  required int generation,
                  required String text,
                  required int selectionLocation,
                  required int selectionLength,
                }) {
                  createdMetalSurface.updatePreedit(
                    generation: generation,
                    text: text,
                    selectionLocation: selectionLocation,
                    selectionLength: selectionLength,
                  );
                },
            onClearPreedit: (int generation) {
              createdMetalSurface.clearPreedit(generation: generation);
            },
            onCommit: createdPane.insertText,
            onOverflow: (int clientId, int generation) {
              stdout.writeln(
                'TERMINAL_TEXT_INPUT_OVERFLOW client_id=$clientId '
                'generation=$generation reset=true',
              );
            },
          );
      final _TerminalMouseProductObservation mouseObservation =
          _TerminalMouseProductObservation();
      final _TerminalFocusProductObservation focusObservation =
          _TerminalFocusProductObservation();
      final _TerminalScrollProductObservation scrollObservation =
          _TerminalScrollProductObservation();
      final _TerminalSelectionProductOwner createdSelectionOwner =
          _TerminalSelectionProductOwner(
            gesture: TerminalSelectionGestureController(
              viewport: terminalSession!.terminalScreenSet.viewport,
            ),
            surface: createdMetalSurface,
          );
      selectionOwner = createdSelectionOwner;
      final TerminalMouseRouter mouseRouter = TerminalMouseRouter(
        onTerminalReport: (Uint8List bytes) {
          mouseObservation.recordTerminalReport(bytes);
          createdPane.sendInput(bytes);
        },
        onLocalSelection: (TerminalLocalSelectionIntent intent) {
          mouseObservation.recordLocalSelection(intent);
          createdSelectionOwner.handle(intent);
        },
      );
      final TerminalFocusReporter focusReporter = TerminalFocusReporter(
        onTerminalReport: (Uint8List bytes) {
          focusObservation.recordTerminalReport(bytes);
          createdPane.sendInput(bytes);
        },
      );
      final TerminalHyperlinkInteractionController hyperlinkController =
          TerminalHyperlinkInteractionController(
            viewport: terminalSession!.terminalScreenSet.viewport,
            onHoverCell: (int row, int column) {
              createdMetalSurface.updateHyperlinkHover(
                row: row,
                column: column,
              );
            },
            onClearHover: createdMetalSurface.clearHyperlinkHover,
            onOpen: (AllowedExternalUrl target) {
              if (options.runtimeTerminalDisplayTest) {
                return hyperlinkObservation.recordAcceptanceOpen(target);
              }
              try {
                return application.openExternalUrl(target);
              } on Object catch (error, stackTrace) {
                hyperlinkObservation.recordFailure(error, stackTrace);
                return false;
              }
            },
            onNotice: (TerminalHyperlinkNoticeKind kind) {
              hyperlinkObservation.recordNotice(kind);
              createdPane.showHyperlinkNotice(kind);
            },
          );
      final TerminalScrollRouter scrollRouter = TerminalScrollRouter(
        onTerminalReport: (Uint8List bytes) {
          scrollObservation.recordTerminalReport(bytes);
          createdPane.sendInput(bytes);
        },
        onLocalScroll: (int rows) {
          final TerminalViewport viewport =
              terminalSession!.terminalScreenSet.viewport;
          final int before = viewport.offset;
          viewport.scrollByRows(rows);
          scrollObservation.recordLocalScroll(
            requestedRows: rows,
            before: before,
            after: viewport.offset,
          );
          createdSelectionOwner.synchronize();
          createdMetalSurface.notifyViewportChanged();
        },
        onAlternateScreenInput: (Uint8List bytes) {
          scrollObservation.recordAlternateInput(bytes);
          createdPane.sendInput(bytes);
        },
      );
      textInputSubscription = createdTextInputClient.events.listen(
        textInputEventRouter.route,
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) {
            closed.completeError(error, stackTrace);
          }
        },
      );
      stdout.writeln(
        'NATIVE_CUSTOM_VIEW '
        'provider=$terminalMetalViewProviderIdentifier attached=true '
        'renderer_bound=true',
      );
      stdout.writeln(
        'NATIVE_TEXT_INPUT_CLIENT attached=true routing=appkit-only '
        'client_id=${createdTextInputClient.clientId}',
      );
      if (options.runtimePtyExitFaultInjection) {
        stdout.writeln(
          'TERMINAL_PTY_FAULT exit_notification=suppressed gate=true',
        );
      }

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

      void handleClipboardFailure(
        Object error,
        StackTrace stackTrace,
        TerminalClipboardNoticeKind kind,
      ) {
        createdPane.showClipboardNotice(TerminalClipboardNotice(kind));
        clipboardObservation?.recordFailure(error, stackTrace);
      }

      var pasteActionInProgress = false;
      Future<void> pasteClipboardOnce() async {
        final int invocationMicros = pasteConfirmationClock.elapsedMicroseconds;
        late final PasteboardTextSnapshot snapshot;
        try {
          snapshot = clipboard.readText();
        } on AppKitNativeException catch (error, stackTrace) {
          handleClipboardFailure(
            error,
            stackTrace,
            error.status == _appKitLimitExceededStatus
                ? TerminalClipboardNoticeKind.pasteTooLarge
                : TerminalClipboardNoticeKind.pasteUnavailable,
          );
          return;
        } on Object catch (error, stackTrace) {
          handleClipboardFailure(
            error,
            stackTrace,
            TerminalClipboardNoticeKind.pasteUnavailable,
          );
          return;
        }
        if (emitNativeEventWireObservation) {
          stdout.writeln(
            'NATIVE_PASTEBOARD_SNAPSHOT '
            'change_count=${snapshot.changeCount} '
            'has_text=${snapshot.text != null}',
          );
        }
        final String? text = snapshot.text;
        if (text == null) {
          createdPane.showClipboardNotice(
            const TerminalClipboardNotice(
              TerminalClipboardNoticeKind.pasteUnavailable,
            ),
          );
          return;
        }
        late final TerminalPastePlan plan;
        try {
          final bool bracketed = createdPane.bracketedPasteMode;
          if (clipboardObservation != null) {
            Timer.run(clipboardObservation.recordPlanningYield);
          }
          plan = await TerminalPasteCodec.planAsync(text, bracketed: bracketed);
        } on TerminalPasteLimitException {
          createdPane.showClipboardNotice(
            const TerminalClipboardNotice(
              TerminalClipboardNoticeKind.pasteTooLarge,
            ),
          );
          clipboardObservation?.recordTooLarge();
          return;
        }
        final int confirmationIssuedMicros =
            pasteConfirmationClock.elapsedMicroseconds;
        clipboardObservation?.recordGateAttempt(
          hadPending: pasteConfirmationGate.hasPendingConfirmation,
          analysis: plan.analysis,
        );
        final TerminalPasteApprovalResult approval = pasteConfirmationGate
            .evaluate(
              pasteboardChangeCount: snapshot.changeCount,
              plan: plan,
              invocationMicros: invocationMicros,
              confirmationIssuedMicros: confirmationIssuedMicros,
            );
        if (!approval.isApproved) {
          createdPane.showClipboardNotice(
            TerminalClipboardNotice(
              TerminalClipboardNoticeKind.pasteConfirmationRequired,
              analysis: approval.analysis,
            ),
          );
          clipboardObservation?.recordConfirmation(
            approval.analysis,
            changeCount: snapshot.changeCount,
            invocationMicros: invocationMicros,
            issuedMicros: confirmationIssuedMicros,
          );
          return;
        }
        clipboardObservation?.recordApproval(approval.analysis);
        final TerminalPasteTransferResult result = await createdPane.paste(
          plan,
        );
        clipboardObservation?.recordTransfer(result);
        switch (result.disposition) {
          case TerminalPasteTransferDisposition.completed:
            return;
          case TerminalPasteTransferDisposition.busy:
            createdPane.showClipboardNotice(
              const TerminalClipboardNotice(
                TerminalClipboardNoticeKind.pasteBusy,
              ),
            );
          case TerminalPasteTransferDisposition.unavailable:
            createdPane.showClipboardNotice(
              const TerminalClipboardNotice(
                TerminalClipboardNoticeKind.pasteUnavailable,
              ),
            );
          case TerminalPasteTransferDisposition.cancelled:
            createdPane.showClipboardNotice(
              const TerminalClipboardNotice(
                TerminalClipboardNoticeKind.pasteCancelled,
              ),
            );
          case TerminalPasteTransferDisposition.writeFailed:
            createdPane.showClipboardNotice(
              const TerminalClipboardNotice(
                TerminalClipboardNoticeKind.pasteFailed,
              ),
            );
        }
      }

      Future<void> pasteClipboard() async {
        if (pasteActionInProgress || createdPane.pasteInProgress) {
          createdPane.showClipboardNotice(
            const TerminalClipboardNotice(
              TerminalClipboardNoticeKind.pasteBusy,
            ),
          );
          clipboardObservation?.recordBusy();
          return;
        }
        pasteActionInProgress = true;
        try {
          await pasteClipboardOnce();
        } finally {
          pasteActionInProgress = false;
        }
      }

      void copySelection() {
        final TerminalSelectionText? selected = createdSelectionOwner
            .selectedText();
        if (selected == null || selected.text.isEmpty) {
          createdPane.showClipboardNotice(
            const TerminalClipboardNotice(
              TerminalClipboardNoticeKind.copyUnavailable,
            ),
          );
          return;
        }
        if (selected.isTruncated) {
          createdPane.showClipboardNotice(
            const TerminalClipboardNotice(
              TerminalClipboardNoticeKind.copyTooLarge,
            ),
          );
          return;
        }
        try {
          final int changeCount = clipboard.writeText(selected.text);
          pasteConfirmationGate.clear();
          clipboardObservation?.recordCopy(selected, changeCount: changeCount);
        } on Object catch (error, stackTrace) {
          handleClipboardFailure(
            error,
            stackTrace,
            TerminalClipboardNoticeKind.copyFailed,
          );
        }
      }

      final TerminalActionCatalog actionCatalog =
          TerminalActionCatalog.standard();
      late final TerminalCommandPalettePresenter installedCommandPalette;
      final TerminalActionDispatcher actionDispatcher =
          TerminalActionDispatcher(
            catalog: actionCatalog,
            registrations: <TerminalActionRegistration>[
              TerminalActionRegistration(
                id: TerminalActionId.openCommandPalette,
                handler: () => installedCommandPalette.open(),
              ),
              TerminalActionRegistration(
                id: TerminalActionId.quitApplication,
                isAvailable: () =>
                    !createdWindow.isClosed && !createdWindow.isDisposed,
                handler: createdWindow.requestClose,
              ),
              TerminalActionRegistration(
                id: TerminalActionId.closeWindow,
                isAvailable: () =>
                    !createdWindow.isClosed && !createdWindow.isDisposed,
                handler: createdWindow.requestClose,
              ),
              TerminalActionRegistration(
                id: TerminalActionId.copy,
                isAvailable: () {
                  final TerminalSelectionText? selected = createdSelectionOwner
                      .selectedText();
                  return selected != null &&
                      selected.text.isNotEmpty &&
                      !selected.isTruncated;
                },
                handler: copySelection,
              ),
              TerminalActionRegistration(
                id: TerminalActionId.paste,
                isAvailable: () =>
                    !pasteActionInProgress && !createdPane.pasteInProgress,
                handler: () {
                  unawaited(
                    pasteClipboard().onError((
                      Object error,
                      StackTrace stackTrace,
                    ) {
                      handleClipboardFailure(
                        error,
                        stackTrace,
                        TerminalClipboardNoticeKind.pasteFailed,
                      );
                    }),
                  );
                },
              ),
              TerminalActionRegistration(
                id: TerminalActionId.focusPreviousPane,
                isAvailable: () =>
                    createdApplicationState.activeWindow != null &&
                    !createdWindow.isClosed &&
                    !createdWindow.isDisposed,
                handler: () {
                  final TerminalTabState tab =
                      createdApplicationState.activeWindow!.selectedTab;
                  createdApplicationState.traversePaneFocus(
                    tab.id,
                    direction: TerminalPaneFocusTraversal.previous,
                  );
                  createdWindow.makeFirstResponder(createdContentView);
                },
              ),
              TerminalActionRegistration(
                id: TerminalActionId.focusNextPane,
                isAvailable: () =>
                    createdApplicationState.activeWindow != null &&
                    !createdWindow.isClosed &&
                    !createdWindow.isDisposed,
                handler: () {
                  final TerminalTabState tab =
                      createdApplicationState.activeWindow!.selectedTab;
                  createdApplicationState.traversePaneFocus(
                    tab.id,
                    direction: TerminalPaneFocusTraversal.next,
                  );
                  createdWindow.makeFirstResponder(createdContentView);
                },
              ),
            ],
          );
      installedCommandPalette = TerminalCommandPalettePresenter(
        dispatcher: actionDispatcher,
        terminalWindow: createdWindow,
        terminalView: createdContentView,
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) {
            closed.completeError(error, stackTrace);
          }
        },
      );
      commandPalettePresenter = installedCommandPalette;
      final TerminalAppKitMenuProjection
      installedActionMenu = TerminalAppKitMenuProjection.install(
        application: application,
        dispatcher: actionDispatcher,
        onNativeInvocation: (TerminalActionId id, MenuItemInvokedEvent event) {
          observeMenuAction(switch (id) {
            TerminalActionId.copy => 'copy',
            TerminalActionId.paste => 'paste',
            TerminalActionId.closeWindow => 'close',
            TerminalActionId.quitApplication => 'quit',
            _ => id.stableName,
          }, event);
        },
        onDispatched: (TerminalActionDispatchResult result) {
          if (result.disposition == TerminalActionDispatchDisposition.failed &&
              !closed.isCompleted) {
            closed.completeError(result.error!, result.stackTrace!);
          }
        },
      );
      actionMenuProjection = installedActionMenu;
      if (emitNativeEventWireObservation) {
        stdout.writeln(
          'NATIVE_ACTION_MENU installed=true '
          'sections=${TerminalActionMenu.values.length} '
          'actions=${actionCatalog.actions.length}',
        );
      }
      final MenuItem copyItem = installedActionMenu.itemForAction(
        TerminalActionId.copy,
      );
      final MenuItem pasteItem = installedActionMenu.itemForAction(
        TerminalActionId.paste,
      );
      final MenuItem closeItem = installedActionMenu.itemForAction(
        TerminalActionId.closeWindow,
      );
      final MenuItem quitItem = installedActionMenu.itemForAction(
        TerminalActionId.quitApplication,
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
              hyperlinkController.cancelPress();
              createdMetalSurface.clearHyperlinkHover();
              currentWindowWidth = width;
              currentWindowHeight = height;
              final TerminalGridSize grid = createdMetalSurface.resizeViewport(
                logicalWidth: width,
                logicalHeight: height,
              );
              createdPane.resize(rows: grid.rows, columns: grid.columns);
            case WindowFocusChangedEvent(:final isFocused):
              if (!isFocused) {
                hyperlinkController.cancelPress();
                createdMetalSurface.clearHyperlinkHover();
              }
              final TerminalScreenSet screens =
                  terminalSession!.terminalScreenSet;
              focusObservation.recordRoute(
                focusReporter.route(
                  isFocused: isFocused,
                  modeEnabled: screens.focusReportingMode,
                  modeGeneration: screens.focusReportingGeneration,
                ),
              );
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'focus',
                  'value=$isFocused',
                );
              }
            case WindowVisibilityChangedEvent(:final isVisible):
              if (!isVisible) {
                hyperlinkController.cancelPress();
                createdMetalSurface.clearHyperlinkHover();
              }
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
              hyperlinkController.cancelPress();
              createdMetalSurface.clearHyperlinkHover();
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
              hyperlinkController.cancelPress();
              createdMetalSurface.clearHyperlinkHover();
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
            case AppKitKeyEvent():
              break;
            case AppKitScrollEvent():
              hyperlinkController.cancelPress();
              createdMetalSurface.clearHyperlinkHover();
              final TerminalScreenSet screens =
                  terminalSession!.terminalScreenSet;
              final TerminalScreen scrollScreen = screens.activeScreen;
              final TerminalFontCatalogMetrics metrics =
                  createdMetalSurface.fontMetrics;
              final TerminalScrollRouteResult result = scrollRouter.route(
                event,
                mouseModes: screens.mouseModes,
                keyboardModes: screens.keyboardModes,
                usingAlternateScreen: screens.usingAlternate,
                rows: scrollScreen.rows,
                columns: scrollScreen.columns,
                cellWidth: metrics.cellWidth,
                cellHeight: metrics.cellHeight,
                backingScaleFactor: createdWindow.backingScaleFactor ?? 1,
              );
              if (result.disposition == TerminalScrollDisposition.ignored) {
                scrollObservation.recordIgnored(result.ignoreReason!);
              }
            case AppKitMouseEvent():
              final TerminalScreen mouseScreen =
                  terminalSession!.terminalScreenSet.activeScreen;
              final TerminalFontCatalogMetrics metrics =
                  createdMetalSurface.fontMetrics;
              final TerminalHyperlinkRouteResult hyperlinkResult =
                  hyperlinkController.route(
                    event,
                    rows: mouseScreen.rows,
                    columns: mouseScreen.columns,
                    cellWidth: metrics.cellWidth,
                    cellHeight: metrics.cellHeight,
                  );
              hyperlinkObservation.recordRoute(hyperlinkResult);
              if (hyperlinkResult.isConsumed) {
                break;
              }
              final TerminalMouseRouteResult result = mouseRouter.route(
                event,
                modes: terminalSession!.terminalScreenSet.mouseModes,
                rows: mouseScreen.rows,
                columns: mouseScreen.columns,
                cellWidth: metrics.cellWidth,
                cellHeight: metrics.cellHeight,
                backingScaleFactor: createdWindow.backingScaleFactor ?? 1,
              );
              if (result.disposition == TerminalMouseRouteDisposition.ignored) {
                mouseObservation.recordIgnored(result.ignoreReason!);
              }
              installedActionMenu.refresh();
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
          if (emitNativeEventWireObservation &&
              options.autoCloseAfter != null) {
            await _exerciseCommandPaletteProduct(
              application,
              createdWindow,
              installedActionMenu,
              installedCommandPalette,
              () => terminalInputWriteEnqueuedCount,
            );
          }
          if (options.runtimeResourceStress) {
            _exerciseResourceStress(application);
          }
          final RuntimeShellExitTestScenario shellExitTest =
              options.runtimeShellExitTestScenario;
          if (options.runtimeTerminalDisplayTest) {
            await _exerciseTerminalDisplay(
              application,
              createdLifecycle,
              terminalSession!,
              createdPane,
              createdMetalSurface,
              createdWindow,
              keyEventRouter,
              createdTextInputClient,
              textInputEventRouter,
              focusObservation,
              mouseObservation,
              createdSelectionOwner,
              scrollObservation,
              hyperlinkObservation,
            );
          } else if (options.runtimeClipboardTest) {
            await _exerciseClipboardProduct(
              application,
              createdLifecycle,
              terminalSession!,
              createdPane,
              createdMetalSurface,
              createdWindow,
              mouseObservation,
              createdSelectionOwner,
              copyItem,
              pasteItem,
              runtimeClipboard!,
              clipboardObservation!,
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
        selectionOwner?.dispose();
        if (!lifecycleWasShutDown) {
          await lifecycle?.shutdown();
        }
        await eventSubscription?.cancel();
        await applicationEventSubscription?.cancel();
        await textInputSubscription?.cancel();
        final TerminalCommandPalettePresenter? palettePresenter =
            commandPalettePresenter;
        commandPalettePresenter = null;
        await palettePresenter?.dispose();
        final TerminalAppKitMenuProjection? menuProjection =
            actionMenuProjection;
        actionMenuProjection = null;
        await menuProjection?.dispose();
        if (textInputClient != null && !textInputClient.isDisposed) {
          textInputClient.dispose();
        }
        if (metalSurface != null && !metalSurface.isDisposed) {
          metalSurface.dispose();
        }
        final TerminalApplicationState? state = applicationState;
        if (state != null) {
          final TerminalPaneOwnerShutdownResult result = await state.shutdown();
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

  static Future<void> _runNativeHierarchyProductAcceptance(
    AppKitApplication application,
    PtyBackend ptyBackend,
    TerminalTerminfoEnvironment terminfoEnvironment,
    RuntimeLifecycleWorkerCommand workerCommand,
    String? initialWorkingDirectory,
  ) async {
    const String prompt = '__DT_HIERARCHY_PROMPT__ ';
    const String expectedInputHex = '1b5b41e697a5e69cace8aa9e';
    const Rect windowFrame = Rect.fromLTWH(100, 90, 920, 580);
    final TerminalApplicationState state = TerminalApplicationState();
    final Map<PaneId, TerminalSession> sessions = <PaneId, TerminalSession>{};
    final Map<PaneId, _TerminalHierarchyProductPane> owners =
        <PaneId, _TerminalHierarchyProductPane>{};
    final List<TerminalPaneSessionShutdownResult> shutdowns =
        <TerminalPaneSessionShutdownResult>[];
    TerminalNativeHierarchyAdapter? hierarchy;
    RuntimeLifecycleCoordinator? lifecycle;
    var lifecycleWasShutDown = false;
    Object? asynchronousError;
    StackTrace? asynchronousStackTrace;

    void recordAsynchronousError(Object error, StackTrace stackTrace) {
      asynchronousError ??= error;
      asynchronousStackTrace ??= stackTrace;
    }

    TerminalPaneConfiguration configuration() {
      PaneId? paneId;
      return TerminalPaneConfiguration(
        sessionFactory:
            (
              TerminalSessionId id, {
              required void Function() onChanged,
              required void Function() onTerminated,
            }) {
              paneId = id.paneId;
              final TerminalSession session = TerminalSession(
                id: id,
                ptyBackend: ptyBackend,
                initialWorkingDirectory: initialWorkingDirectory,
                environment: <String, String>{
                  ...terminfoEnvironment.environment,
                  'TERM': 'xterm-256color',
                  'LC_ALL': 'C',
                  'PS1': prompt,
                  'RPS1': '',
                },
                shellArguments: const <String>['-f'],
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
              sessions[id.paneId] = session;
              return session;
            },
        onChanged: () {
          final PaneId? id = paneId;
          if (id != null) owners[id]?.notifyScreenChanged();
        },
        onExitRequested: () {
          recordAsynchronousError(
            StateError('hierarchy acceptance shell exited unexpectedly'),
            StackTrace.current,
          );
        },
        lifecycleObserver: (TerminalPaneLifecycleObservation observation) {
          stdout.writeln(observation.machineLine());
        },
        exitObserver: (TerminalPaneExitObservation observation) {
          stdout.writeln(observation.machineLine());
        },
      );
    }

    void checkAsynchronousError() {
      final Object? error = asynchronousError;
      if (error != null) {
        Error.throwWithStackTrace(error, asynchronousStackTrace!);
      }
    }

    try {
      application.defersTerminationRequests = true;
      final int initialNativeHandles = application.debugLiveObjectCount;
      final int initialTextInputClients =
          debugLiveTerminalTextInputClientCount();
      _expectLifecycle(
        initialNativeHandles == 0 && initialTextInputClients == 0,
        'hierarchy acceptance requires clean native baselines',
      );

      final TerminalWindowState logicalWindow = await state.createWindow(
        configuration(),
      );
      final TerminalTabState firstTab = logicalWindow.selectedTab;
      final PaneId firstPaneId = firstTab.focusedPaneId;
      final TerminalPane secondPane = await state.splitPane(
        firstPaneId,
        configuration(),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.3,
      );
      final TerminalSplitNodeId firstRootId = firstTab.splitTree.root.id;
      final TerminalTabState secondTab = await state.createTab(
        logicalWindow.id,
        configuration(),
      );
      final PaneId thirdPaneId = secondTab.focusedPaneId;
      final TerminalPane fourthPane = await state.splitPane(
        thirdPaneId,
        configuration(),
        axis: TerminalSplitAxis.vertical,
        fraction: 0.7,
      );
      final TerminalSplitNodeId secondRootId = secondTab.splitTree.root.id;
      final List<PaneId> paneIds = <PaneId>[
        firstPaneId,
        secondPane.id,
        thirdPaneId,
        fourthPane.id,
      ];

      final TerminalNativeHierarchyAdapter createdHierarchy =
          TerminalNativeHierarchyAdapter(
            state: state,
            paneResourcesFactory: (TerminalPane pane) {
              final TerminalSession session = sessions[pane.id]!;
              final View view = TerminalRendererMacos.createView();
              final TerminalTextInputClient client =
                  TerminalTextInputClient.attach(view);
              late final _TerminalHierarchyProductPane owner;
              final TerminalLiveMetalSurface surface =
                  TerminalLiveMetalSurface.attach(
                    sessionId: pane.sessionId,
                    screenSet: session.terminalScreenSet,
                    view: view,
                    logicalWidth: windowFrame.width,
                    logicalHeight: windowFrame.height,
                    isVisible: false,
                    isOccluded: true,
                    onCaretGeometryChanged: (TerminalCaretRect rectangle) {
                      client.publishCaretRect(
                        x: rectangle.x,
                        y: rectangle.y,
                        width: rectangle.width,
                        height: rectangle.height,
                      );
                    },
                    onFatalError: recordAsynchronousError,
                  );
              final TerminalKeyEventRouter keyRouter = TerminalKeyEventRouter();
              final TerminalTextInputEventRouter textRouter =
                  TerminalTextInputEventRouter(
                    clientId: client.clientId,
                    onRawKeyDown: (TerminalKeyEvent event) {
                      keyRouter.handleTerminalKeyDown(event, pane);
                    },
                    onPreedit:
                        ({
                          required int generation,
                          required String text,
                          required int selectionLocation,
                          required int selectionLength,
                        }) {
                          surface.updatePreedit(
                            generation: generation,
                            text: text,
                            selectionLocation: selectionLocation,
                            selectionLength: selectionLength,
                          );
                        },
                    onClearPreedit: (int generation) {
                      surface.clearPreedit(generation: generation);
                    },
                    onCommit: pane.insertText,
                    onOverflow: (int clientId, int generation) {
                      recordAsynchronousError(
                        StateError(
                          'hierarchy text input overflow for client $clientId '
                          'at generation $generation',
                        ),
                        StackTrace.current,
                      );
                    },
                  );
              owner = _TerminalHierarchyProductPane(
                pane: pane,
                session: session,
                view: view,
                client: client,
                surface: surface,
                textRouter: textRouter,
                onTextInputError: recordAsynchronousError,
              );
              owners[pane.id] = owner;
              return TerminalNativePaneResources(
                paneId: pane.id,
                view: view,
                onLayout: owner.applyLayout,
                onDisposeAdapters: owner.disposeAdapters,
              );
            },
            windowFrame: windowFrame,
            cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
            dividerThickness: 1,
            titleBuilder: (TerminalWindowState window, TerminalTabState tab) =>
                'Dart Terminal — ${window.id}:${tab.id}',
          );
      hierarchy = createdHierarchy;
      createdHierarchy.reconcile(
        tabSizes: <TerminalTabId, TerminalSplitLayoutSize>{
          firstTab.id: TerminalSplitLayoutSize(
            width: windowFrame.width,
            height: windowFrame.height,
          ),
          secondTab.id: TerminalSplitLayoutSize(
            width: windowFrame.width,
            height: windowFrame.height,
          ),
        },
      );
      final Map<PaneId, TerminalNativePaneResources> initialResources =
          <PaneId, TerminalNativePaneResources>{
            for (final PaneId paneId in paneIds)
              paneId: createdHierarchy.resourcesForPane(paneId)!,
          };
      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 4 &&
            createdHierarchy.nativeWindowCount == 2 &&
            createdHierarchy.splitViewCount == 2 &&
            createdHierarchy.paneResourceCount == 4 &&
            application.debugLiveObjectCount == 8 &&
            debugLiveTerminalTextInputClientCount() == 4,
        'hierarchy acceptance did not create the exact native inventory',
      );
      _expectLifecycle(
        createdHierarchy.splitViewForNode(firstRootId)!.fraction == 0.3 &&
            createdHierarchy.splitViewForNode(secondRootId)!.fraction == 0.7,
        'hierarchy acceptance did not preserve initial split ratios',
      );

      for (final PaneId paneId in paneIds) {
        final TerminalPane pane = state.paneForId(paneId)!;
        await pane.start();
        stdout.writeln(
          'TERMINAL_PANE event=started pane=${pane.id} '
          'session=${pane.sessionId}',
        );
      }

      final RuntimeLifecycleCoordinator createdLifecycle =
          RuntimeLifecycleCoordinator(
            scenario: RuntimeLifecycleScenario.normal,
            workerCommand: workerCommand,
            observer: (RuntimeLifecycleObservation observation) {
              stdout.writeln(
                observation.machineLine(RuntimeLifecycleScenario.normal),
              );
            },
            processObserver: (RuntimeLifecycleProcessObservation observation) {
              stdout.writeln(
                observation.machineLine(
                  RuntimeLifecycleScenario.normal,
                  parentProcessId: pid,
                ),
              );
            },
          );
      lifecycle = createdLifecycle;
      _expectLifecycle(
        await createdLifecycle.start() == RuntimeLifecycleStartStatus.ready,
        'hierarchy acceptance runtime worker did not become ready',
      );
      _writeLifecycleEvent(
        RuntimeLifecycleScenario.normal,
        'root-ready',
        createdLifecycle.generation,
      );
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);
      await _expectResponse(createdLifecycle);

      for (final PaneId paneId in paneIds) {
        await _waitForAsciiMarker(sessions[paneId]!, prompt.trimRight());
        final TerminalPane pane = state.paneForId(paneId)!;
        pane.insertText(
          "stty raw -echo; printf '\\r\\n__DT_HIERARCHY_%s_%s__\\r\\n' "
          "'READY' '${paneId.value}'; "
          "bytes=\$(dd bs=1 count=12 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
          "stty sane; if [ \"\$bytes\" = '$expectedInputHex' ]; then "
          "printf '\\r\\n__DT_HIERARCHY_%s_%s__\\r\\n' 'EXACT' "
          "'${paneId.value}'; else "
          "printf '\\r\\n__DT_HIERARCHY_%s_%s__\\r\\n' 'MISMATCH' "
          "'${paneId.value}'; fi",
        );
        await pane.submit();
      }
      for (final PaneId paneId in paneIds) {
        await _waitForAsciiMarker(
          sessions[paneId]!,
          '__DT_HIERARCHY_READY_${paneId.value}__',
        );
      }

      state
        ..selectTab(logicalWindow.id, firstTab.id)
        ..focusPane(firstTab.id, firstPaneId)
        ..resizeSplit(firstTab.id, firstRootId, 0.65)
        ..setPaneZoom(firstTab.id, firstPaneId);
      createdHierarchy.reconcile();
      final SplitView firstRoot = createdHierarchy.splitViewForNode(
        firstRootId,
      )!;
      _expectLifecycle(
        firstRoot.fraction == 0.65 &&
            firstRoot.zoomedChild == SplitViewChild.first &&
            owners[firstPaneId]!.isVisible &&
            !owners[secondPane.id]!.isVisible,
        'hierarchy resize/zoom did not reach the retained native split',
      );
      state
        ..setPaneZoom(firstTab.id, null)
        ..equalizeSplits(firstTab.id);
      createdHierarchy.resizeTab(
        firstTab.id,
        TerminalSplitLayoutSize(width: 700.5, height: 420.25),
      );
      _expectLifecycle(
        firstRoot.fraction == 0.5 &&
            firstRoot.zoomedChild == null &&
            owners[firstPaneId]!.isVisible &&
            owners[secondPane.id]!.isVisible,
        'hierarchy equalize/unzoom did not restore both native children',
      );

      for (var index = 0; index < paneIds.length; index++) {
        final PaneId paneId = paneIds[index];
        final TerminalPaneLocation location = state.locationForPane(paneId)!;
        state
          ..selectTab(location.windowId, location.tabId)
          ..focusPane(location.tabId, paneId);
        createdHierarchy.reconcile();
        final _TerminalHierarchyProductPane owner = owners[paneId]!;
        final Stopwatch geometryDeadline = Stopwatch()..start();
        while (owner.client.geometryGeneration == 0 &&
            geometryDeadline.elapsed < const Duration(seconds: 5)) {
          checkAsynchronousError();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        _expectLifecycle(
          owner.client.geometryGeneration > 0,
          'hierarchy pane $paneId did not publish candidate geometry',
        );
        owner.client.debugRunAcceptanceStage(1);
        await owner.waitForTextInputGeneration(3, compositionActive: true);
        owner.client.debugRunAcceptanceStage(2);
        await owner.waitForTextInputGeneration(5, compositionActive: true);
        owner.client.debugRunAcceptanceStage(3);
        await owner.waitForTextInputGeneration(6, compositionActive: false);
        await _waitForAsciiMarker(
          owner.session,
          '__DT_HIERARCHY_EXACT_${paneId.value}__',
        );
        checkAsynchronousError();
        final int exactSessions = paneIds
            .where(
              (PaneId candidate) =>
                  _findAscii(
                    sessions[candidate]!.terminalScreenSet.activeScreen,
                    '__DT_HIERARCHY_EXACT_${candidate.value}__',
                  ) !=
                  null,
            )
            .length;
        _expectLifecycle(
          exactSessions == index + 1,
          'hierarchy input leaked into an unfocused pane',
        );
      }
      _expectLifecycle(
        paneIds.every(
          (PaneId paneId) =>
              _findAscii(
                sessions[paneId]!.terminalScreenSet.activeScreen,
                '__DT_HIERARCHY_MISMATCH_${paneId.value}__',
              ) ==
              null,
        ),
        'hierarchy input reached a PTY with non-exact bytes',
      );

      for (final PaneId paneId in <PaneId>[
        secondPane.id,
        fourthPane.id,
        thirdPaneId,
      ]) {
        await owners[paneId]!.cancelTextInput();
        final TerminalPane pane = state.paneForId(paneId)!;
        _expectLifecycle(
          pane.requestClose(force: true) == TerminalPaneCloseDecision.allow,
          'hierarchy pane $paneId refused deterministic close',
        );
        final TerminalPaneRemovalResult result = await state.removePane(paneId);
        shutdowns.add(result.shutdown);
        stdout.writeln(result.shutdown.machineLine());
        createdHierarchy.reconcile();
        _expectLifecycle(
          owners[paneId]!.adaptersDisposed &&
              initialResources[paneId]!.isDisposed,
          'hierarchy pane $paneId retained native adapters after close',
        );
      }
      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 1 &&
            state.paneCount == 1 &&
            createdHierarchy.nativeWindowCount == 1 &&
            createdHierarchy.splitViewCount == 0 &&
            createdHierarchy.paneResourceCount == 1,
        'hierarchy close did not collapse split and tab ownership',
      );

      await owners[firstPaneId]!.cancelTextInput();
      createdHierarchy.dispose();
      final TerminalPaneOwnerShutdownResult finalShutdown = await state
          .shutdown();
      shutdowns.addAll(finalShutdown.sessions);
      for (final TerminalPaneSessionShutdownResult result
          in finalShutdown.sessions) {
        stdout.writeln(result.machineLine());
      }
      stdout.writeln(TerminalPaneOwnerShutdownResult(shutdowns).machineLine());
      _expectLifecycle(
        shutdowns.length == 4 &&
            shutdowns.every(
              (TerminalPaneSessionShutdownResult result) => result.isClean,
            ) &&
            owners.values.every(
              (_TerminalHierarchyProductPane owner) =>
                  owner.adaptersDisposed &&
                  owner.surface.snapshot().isDisposed &&
                  owner.surface.snapshot().liveAtlasPinCount == 0,
            ) &&
            debugLiveTerminalTextInputClientCount() == 0 &&
            application.debugLiveObjectCount == 0,
        'hierarchy acceptance cleanup retained product resources',
      );
      checkAsynchronousError();
      stdout.writeln(
        'TERMINAL_NATIVE_HIERARCHY_TEST windows=1 tabs=2 panes=4 splits=2 '
        'resize=true equalize=true zoom=true focus=true key=true ime=true '
        'isolated=true close=true sessions_clean=4 metal_clean=4 '
        'text_clients=0 native_handles=0',
      );

      final RuntimeLifecycleShutdownResult lifecycleShutdown =
          await createdLifecycle.shutdown();
      lifecycleWasShutDown = true;
      _expectLifecycle(
        !lifecycleShutdown.forced &&
            lifecycleShutdown.termination ==
                RuntimeLifecycleWorkerTermination.graceful,
        'hierarchy acceptance runtime worker did not stop cleanly',
      );
    } finally {
      for (final _TerminalHierarchyProductPane owner
          in owners.values.toList(growable: false).reversed) {
        await owner.cancelTextInput();
      }
      if (hierarchy != null && !hierarchy.isDisposed) hierarchy.dispose();
      for (final _TerminalHierarchyProductPane owner
          in owners.values.toList(growable: false).reversed) {
        if (!owner.adaptersDisposed) owner.disposeAdapters();
        if (!owner.view.isDisposed) owner.view.dispose();
      }
      if (!state.isDisposed) {
        final TerminalPaneOwnerShutdownResult result = await state.shutdown();
        for (final TerminalPaneSessionShutdownResult session
            in result.sessions) {
          stdout.writeln(session.machineLine());
        }
      }
      if (!lifecycleWasShutDown) await lifecycle?.shutdown();
      _writeLifecycleEvent(
        RuntimeLifecycleScenario.normal,
        'root-exit',
        lifecycle?.generation ?? 0,
      );
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStopped);
      await application.terminate().timeout(_hostTerminationTimeout);
    }
    stdout.writeln('Dart Terminal shut down cleanly.');
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
    AppKitApplication application,
    RuntimeLifecycleCoordinator lifecycle,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    TerminalKeyEventRouter keyEventRouter,
    TerminalTextInputClient textInputClient,
    TerminalTextInputEventRouter textInputEventRouter,
    _TerminalFocusProductObservation focusObservation,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner selectionOwner,
    _TerminalScrollProductObservation scrollObservation,
    _TerminalHyperlinkProductObservation hyperlinkObservation,
  ) async {
    const String prompt = '__DT_DISPLAY_PROMPT__ ';
    const String colorMarker = '__DT_COLOR__';
    const String wrapStart = '__DT_WRAP_START__';
    const String wrapEnd = '__DT_WRAP_END__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final bool terminfo = await _exerciseTerminfoInstall(session, pane);
    final bool modeKey = await _exerciseModeAwareKeyInput(
      session,
      pane,
      keyEventRouter,
    );
    final bool textInput = await _exerciseTextInput(
      session,
      pane,
      surface,
      textInputClient,
      textInputEventRouter,
    );
    final bool inputMatrix = await _exerciseInputMatrix(
      session,
      pane,
      textInputClient,
      textInputEventRouter,
    );
    final bool decrqss = await _exerciseDecrqssSgr(session, pane);
    final bool queryReports = await _exerciseQueryReports(session, pane);
    final bool focus = await _exerciseFocusReporting(
      application,
      session,
      pane,
      window,
      focusObservation,
    );
    final bool mouse = await _exerciseMouseInput(
      application,
      session,
      pane,
      surface,
      window,
      mouseObservation,
    );
    final bool selection = await _exerciseSelectionInput(
      application,
      session,
      pane,
      surface,
      window,
      mouseObservation,
      selectionOwner,
    );
    final bool closeScroll = await _exerciseWindowCloseScrollPosition(
      application,
      session,
      pane,
      surface,
      window,
      mouseObservation,
      selectionOwner,
    );
    final bool scroll = await _exerciseScrollInput(
      application,
      session,
      pane,
      surface,
      window,
      scrollObservation,
    );
    final bool hyperlink = await _exerciseHyperlinkInput(
      application,
      session,
      pane,
      surface,
      window,
      mouseObservation,
      hyperlinkObservation,
    );
    final bool windowTitle = await _exerciseWindowTitleMetadata(
      session,
      pane,
      window,
    );
    final bool cursorColor = await _exerciseCursorColorPresentation(
      session,
      pane,
      surface,
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
    final bool accessibility = await _exerciseAccessibilityInput(
      application,
      session,
      surface,
      window,
      mouseObservation,
      selectionOwner,
      selectionMarker: colorMarker,
      promptMarker: prompt.trimRight(),
    );

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
          terminfo &&
          modeKey &&
          textInput &&
          inputMatrix &&
          decrqss &&
          queryReports &&
          focus &&
          mouse &&
          selection &&
          closeScroll &&
          scroll &&
          hyperlink &&
          windowTitle &&
          cursorColor &&
          accessibility) {
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
          'mode_key=$modeKey text_input=$textInput '
          'input_matrix=$inputMatrix decrqss=$decrqss '
          'query_reports=$queryReports '
          'focus=$focus mouse=$mouse '
          'selection=$selection '
          'close_scroll=$closeScroll '
          'scroll=$scroll hyperlink=$hyperlink window_title=$windowTitle '
          'cursor_color=$cursorColor '
          'accessibility=$accessibility '
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
      'mode_key=$modeKey text_input=$textInput '
      'input_matrix=$inputMatrix decrqss=$decrqss '
      'query_reports=$queryReports '
      'focus=$focus mouse=$mouse '
      'selection=$selection '
      'close_scroll=$closeScroll '
      'scroll=$scroll hyperlink=$hyperlink window_title=$windowTitle '
      'cursor_color=$cursorColor '
      'accessibility=$accessibility '
      'font_size=${baseline.fontPointSize}',
    );
  }

  static Future<bool> _exerciseDecrqssSgr(
    TerminalSession session,
    TerminalPane pane,
  ) async {
    const String receivedMarker = '__DT_DECRQSS_1b50312472306d1b5c__';
    pane.insertText(
      "stty raw -echo; printf '\\033[0m\\033P\$qm\\033\\\\'; "
      "bytes=\$(dd bs=1 count=9 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "stty sane; printf '\\r\\n__DT_DECRQSS_%s__\\r\\n' \"\$bytes\"",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, receivedMarker);
    stdout.writeln(
      'TERMINAL_DECRQSS_TEST selector=sgr default=true xterm=true '
      'exact=true bytes=9',
    );
    return true;
  }

  static Future<bool> _exerciseQueryReports(
    TerminalSession session,
    TerminalPane pane,
  ) async {
    final ({int width, int height})? viewport =
        session.terminalScreenSet.logicalViewportSize;
    _expectLifecycle(
      viewport != null,
      'query report fixture requires published logical viewport geometry',
    );
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final Uint8List version = TerminalReplyEncoder.xtermVersion();
    final Uint8List pixels = TerminalReplyEncoder.textAreaSizePixels(
      height: viewport!.height,
      width: viewport.width,
    );
    final Uint8List characters = TerminalReplyEncoder.textAreaSizeCharacters(
      rows: screen.rows,
      columns: screen.columns,
    );
    String hex(Uint8List bytes) =>
        bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final String versionHex = hex(version);
    final String pixelsHex = hex(pixels);
    final String charactersHex = hex(characters);
    const String exactMarker = '__DT_QUERY_REPORT_EXACT__';
    pane.insertText(
      "stty raw -echo; printf '\\033[>q'; "
      "v1=\$(dd bs=1 count=${version.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[>0q'; "
      "v2=\$(dd bs=1 count=${version.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[14t'; "
      "px=\$(dd bs=1 count=${pixels.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[18t'; "
      "ch=\$(dd bs=1 count=${characters.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "stty sane; if [ \"\$v1\" = '$versionHex' ] && "
      "[ \"\$v2\" = '$versionHex' ] && "
      "[ \"\$px\" = '$pixelsHex' ] && "
      "[ \"\$ch\" = '$charactersHex' ]; then "
      "printf '\\r\\n__DT_QUERY_REPORT_%s__\\r\\n' 'EXACT'; else "
      "printf '\\r\\n__DT_QUERY_REPORT_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, exactMarker);
    stdout.writeln(
      'TERMINAL_QUERY_REPORT_TEST xtversion=true pixels=true '
      'characters=true exact=true identity=${TerminalReplyEncoder.xtermVersionIdentity} '
      'width=${viewport.width} height=${viewport.height} '
      'rows=${screen.rows} columns=${screen.columns}',
    );
    return true;
  }

  static Future<bool> _exerciseWindowTitleMetadata(
    TerminalSession session,
    TerminalPane pane,
    Window window,
  ) async {
    const String nativeTitle = '__DT_NATIVE_TITLE__';
    const String temporaryTitle = '__DT_TEMP_TITLE__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    pane.insertText(r"printf '\033]2;__DT_NATIVE_TITLE__\007'");
    await pane.submit();
    await _waitForWindowTitle(
      session,
      window,
      expectedMetadata: nativeTitle,
      expectedNative: nativeTitle,
    );

    pane.insertText(r"printf '\033[22;2t\033]2;__DT_TEMP_TITLE__\007'");
    await pane.submit();
    await _waitForWindowTitle(
      session,
      window,
      expectedMetadata: temporaryTitle,
      expectedNative: temporaryTitle,
    );

    pane.insertText(r"printf '\033[23;2t'");
    await pane.submit();
    await _waitForWindowTitle(
      session,
      window,
      expectedMetadata: nativeTitle,
      expectedNative: nativeTitle,
    );

    pane.insertText(r"printf '\033c'");
    await pane.submit();
    await _waitForWindowTitle(
      session,
      window,
      expectedMetadata: null,
      expectedNative: _productWindowTitle,
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    stdout.writeln(
      'TERMINAL_WINDOW_TITLE_TEST metadata=true native=true stack=true '
      'reset=true fallback=true',
    );
    return true;
  }

  static Future<void> _waitForWindowTitle(
    TerminalSession session,
    Window window, {
    required String? expectedMetadata,
    required String expectedNative,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (session.terminalScreenSet.metadata.windowTitle == expectedMetadata &&
          window.title == expectedNative) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before synchronizing the window title',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'display-test did not synchronize metadata title '
      '$expectedMetadata to native title $expectedNative',
    );
  }

  static Future<bool> _exerciseCursorColorPresentation(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
  ) async {
    const int expectedColor = 0x80123456;
    final TerminalPalette palette = session.terminalScreenSet.palette;
    final int initialCursorColor = palette.cursorColor;
    final int initialForeground = palette.defaultForeground;
    final TerminalLiveMetalSurfaceSnapshot before = surface.snapshot();

    pane.insertText(r"printf '\033]12;#123456\007'");
    await pane.submit();
    await _waitForCursorColorFrame(
      session,
      surface,
      expectedColor: expectedColor,
      minimumAcceptedFrameCount: before.acceptedFrameCount + 1,
    );
    _expectLifecycle(
      palette.defaultForeground == initialForeground,
      'OSC 12 changed the default text foreground',
    );

    final TerminalLiveMetalSurfaceSnapshot mutated = surface.snapshot();
    pane.insertText(r"printf '\033]112\007'");
    await pane.submit();
    await _waitForCursorColorFrame(
      session,
      surface,
      expectedColor: initialCursorColor,
      minimumAcceptedFrameCount: mutated.acceptedFrameCount + 1,
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    stdout.writeln(
      'TERMINAL_CURSOR_COLOR_TEST mutation=true text_independent=true '
      'presentation=true metal=true reset=true',
    );
    return true;
  }

  static Future<void> _waitForCursorColorFrame(
    TerminalSession session,
    TerminalLiveMetalSurface surface, {
    required int expectedColor,
    required int minimumAcceptedFrameCount,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (session.terminalScreenSet.palette.cursorColor == expectedColor &&
          snapshot.acceptedFrameCount >= minimumAcceptedFrameCount) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before presenting the cursor color',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'display-test did not present cursor color '
      '0x${expectedColor.toRadixString(16)}',
    );
  }

  static Future<bool> _exerciseTerminfoInstall(
    TerminalSession session,
    TerminalPane pane,
  ) async {
    pane.insertText(
      r'''if [ "${TERM-}" = xterm-256color ] && [ -n "${TERMINFO-}" ] && /usr/bin/infocmp -A "$TERMINFO" xterm-256color >/dev/null 2>&1; then printf '\r\n__DT_TERMINFO_%s__\r\n' OK; else printf '\r\n__DT_TERMINFO_%s__\r\n' MISMATCH; fi''',
    );
    await pane.submit();
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 2);
    final bool exact =
        _findAscii(
          session.terminalScreenSet.activeScreen,
          '__DT_TERMINFO_OK__',
        ) !=
        null;
    _expectLifecycle(exact, 'real PTY did not resolve bundled terminfo');
    stdout.writeln(
      'TERMINAL_TERMINFO_TEST local=true standard_name=true '
      'compiled_lookup=true ssh_standard_name=true ssh_private_path=false',
    );
    return true;
  }

  static Future<void> _exerciseClipboardProduct(
    AppKitApplication application,
    RuntimeLifecycleCoordinator lifecycle,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner selectionOwner,
    MenuItem copyItem,
    MenuItem pasteItem,
    _MemoryTerminalClipboard clipboard,
    _TerminalClipboardProductObservation observation,
  ) async {
    const int payloadBytes = 10 * 1024 * 1024;
    const int encodedBytes =
        payloadBytes + TerminalPasteCodec.bracketFrameBytes;
    const int newlineOffset = payloadBytes ~/ 2;
    const String readyMarker = '__DT_CLIPBOARD_READY__';
    const String exactMarker = '__DT_CLIPBOARD_EXACT__';
    const String mismatchMarker = '__DT_CLIPBOARD_MISMATCH__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    await _exerciseOsc52DefaultDeny(session, pane, clipboard);
    await _exerciseClipboardCopySelection(
      application,
      session,
      pane,
      surface,
      window,
      mouseObservation,
      selectionOwner,
      copyItem,
      clipboard,
      observation,
    );

    pane.insertText(
      "stty -echo -icanon min 1 time 0; "
      "printf '\\033[?2004h\\r\\n__DT_CLIPBOARD_%s__\\r\\n' 'READY'; "
      "/bin/sleep 1; "
      "/usr/bin/perl -e 'binmode STDIN; my \$n=$encodedBytes; my \$d=\"\"; "
      "while (length(\$d) < \$n) { my \$r=sysread(STDIN, my \$b, "
      "\$n-length(\$d)); exit 24 unless defined(\$r) && \$r > 0; "
      "\$d .= \$b; } my \$body=substr(\$d, 6, -6); "
      "my \$ok=substr(\$d, 0, 6) eq \"\\e[200~\" && "
      "substr(\$d, -6) eq \"\\e[201~\" && "
      "length(\$body) == $payloadBytes && "
      "substr(\$body, $newlineOffset, 1) eq \"\\n\"; "
      "substr(\$body, $newlineOffset, 1, \"a\"); "
      "exit(\$ok && \$body !~ /[^a]/ ? 0 : 23);'; result=\$?; "
      "printf '\\033[?2004l'; stty echo icanon; "
      "if [ \$result -eq 0 ]; then "
      "printf '\\r\\n__DT_CLIPBOARD_%s__\\r\\n' 'EXACT'; "
      "else printf '\\r\\n__DT_CLIPBOARD_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, readyMarker);
    _expectLifecycle(
      session.bracketedPasteMode,
      'clipboard fixture did not enable bracketed paste mode',
    );

    final Uint8List source = Uint8List(payloadBytes)
      ..fillRange(0, payloadBytes, 0x61);
    source[newlineOffset] = 0x0a;
    clipboard.seed(String.fromCharCodes(source));
    final int writeBaseline = observation.nativeWriteEnqueuedCount;
    pasteItem.performAction();
    final Stopwatch confirmationDeadline = Stopwatch()..start();
    while (confirmationDeadline.elapsed < const Duration(seconds: 15) &&
        observation.confirmationCount == 0 &&
        observation.failure == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final bool confirmationVisible =
        _findAscii(
          session.terminalScreenSet.activeScreen,
          'paste requires confirmation',
        ) !=
        null;
    final bool zeroWrite =
        observation.confirmationCount == 1 &&
        observation.writesAtFirstConfirmation == writeBaseline &&
        observation.nativeWriteEnqueuedCount == writeBaseline &&
        confirmationVisible &&
        !pane.pasteInProgress;
    _expectLifecycle(
      observation.failure == null && zeroWrite,
      'first unsafe Paste invocation wrote PTY bytes before confirmation: '
      'confirmations=${observation.confirmationCount} '
      'writes_at_confirmation=${observation.writesAtFirstConfirmation} '
      'baseline=$writeBaseline '
      'writes_now=${observation.nativeWriteEnqueuedCount} '
      'visible=$confirmationVisible paste_active=${pane.pasteInProgress} '
      'planning_yields=${observation.planningYieldCount}',
    );

    var timerTicks = 0;
    final Timer responsiveTimer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => timerTicks++,
    );
    try {
      pasteItem.performAction();
      final Stopwatch transferDeadline = Stopwatch()..start();
      while (transferDeadline.elapsed < const Duration(seconds: 30) &&
          observation.transfer == null &&
          observation.failure == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      responsiveTimer.cancel();
    }
    final TerminalPasteTransferResult? transfer = observation.transfer;
    if (observation.failure != null) {
      Error.throwWithStackTrace(
        observation.failure!,
        observation.failureStackTrace ?? StackTrace.current,
      );
    }
    _expectLifecycle(
      transfer != null && transfer.isCompleted,
      'confirmed 10 MiB paste did not complete: '
      'confirmations=${observation.confirmationCount} '
      'approvals=${observation.approvalCount} '
      'writes=${observation.nativeWriteEnqueuedCount - writeBaseline} '
      'busy=${observation.busyCount} mode=${session.bracketedPasteMode} '
      'paste_active=${pane.pasteInProgress} '
      'pending_before=${observation.pendingBeforeAttempts} '
      'source_lengths=${observation.attemptSourceLengths} '
      'body_bytes=${observation.attemptBodyBytes} '
      'newlines=${observation.attemptNewlineCounts} '
      'controls=${observation.attemptControlCounts} '
      'replaced=${observation.attemptReplacedCounts} '
      'terminators=${observation.attemptTerminators} '
      'large=${observation.attemptLarge} '
      'bracketed=${observation.attemptBracketed} '
      'encoded=${observation.attemptEncodedBytes} '
      'change_counts=${observation.confirmationChangeCounts} '
      'fingerprints=${observation.confirmationFingerprints} '
      'invocations=${observation.confirmationInvocationMicros} '
      'issued=${observation.confirmationIssuedMicros}',
    );
    final TerminalPasteTransferResult completedTransfer = transfer!;
    await _waitForAsciiMarker(session, exactMarker);
    _expectLifecycle(
      _findAscii(session.terminalScreenSet.activeScreen, mismatchMarker) ==
          null,
      'real PTY did not validate the exact bracketed payload',
    );

    final int expectedChunks =
        (encodedBytes + TerminalPasteCodec.defaultChunkBytes - 1) ~/
        TerminalPasteCodec.defaultChunkBytes;
    final TerminalPasteAnalysis? confirmed = observation.confirmedAnalysis;
    final TerminalPasteAnalysis? approved = observation.approvedAnalysis;
    final bool exact =
        confirmed != null &&
        approved != null &&
        confirmed.fingerprint == approved.fingerprint &&
        confirmed.encodedBytes == encodedBytes &&
        confirmed.logicalNewlineCount == 1 &&
        confirmed.bracketed &&
        confirmed.isLarge &&
        completedTransfer.encodedBytes == encodedBytes &&
        completedTransfer.completedChunks == expectedChunks &&
        completedTransfer.maximumQueuedBytes > 0 &&
        completedTransfer.maximumQueuedBytes <=
            TerminalPasteCodec.defaultChunkBytes &&
        observation.approvalCount == 1 &&
        observation.nativeWriteEnqueuedCount - writeBaseline == expectedChunks;
    _expectLifecycle(
      observation.copyCount == 5 &&
          observation.confirmationCount == 1 &&
          observation.busyCount == 0 &&
          observation.tooLargeCount == 0 &&
          observation.planningYieldCount == 2 &&
          timerTicks > 0 &&
          exact &&
          lifecycle.workerPid != null,
      'clipboard product acceptance invariants did not settle',
    );
    stdout.writeln(
      'TERMINAL_CLIPBOARD_TEST copy=true paste_menu=true '
      'osc52_denied=true '
      'confirmation=true confirmation_visible=$confirmationVisible '
      'zero_write=$zeroWrite bracketed=true exact=$exact '
      'bytes=${completedTransfer.encodedBytes} '
      'chunks=${completedTransfer.completedChunks} '
      'max_queue=${completedTransfer.maximumQueuedBytes} '
      'planning_yields=${observation.planningYieldCount} '
      'timer_ticks=$timerTicks',
    );
    _expectLifecycle(
      pane.requestClose(force: true) == TerminalPaneCloseDecision.allow,
      'clipboard test could not begin deterministic pane close',
    );
    window.close();
  }

  static Future<void> _exerciseOsc52DefaultDeny(
    TerminalSession session,
    TerminalPane pane,
    _MemoryTerminalClipboard clipboard,
  ) async {
    const String sentinel = '__DT_OSC52_SENTINEL__';
    const String exactMarker = '__DT_OSC52_DENY_EXACT__';
    const String mismatchMarker = '__DT_OSC52_DENY_MISMATCH__';
    clipboard.seed(sentinel);
    final int changeCount = clipboard.changeCount;
    final int reads = clipboard.readCount;
    final int writes = clipboard.writeCount;
    final TerminalScreenParserSink sink = session.terminalParserSink;
    final int deniedReads = sink.deniedClipboardReadCount;
    final int deniedWrites = sink.deniedClipboardWriteCount;
    final int deniedClears = sink.deniedClipboardClearCount;
    final int rejected = sink.rejectedClipboardRequestCount;
    final int acceptedReplies = sink.acceptedReplyCount;

    pane.insertText(
      r'''stty -echo -icanon min 1 time 0; printf '\033]52;c;c2VjcmV0\007\033]52;p;clear\033\\\033]52;c;?\007'; /usr/bin/perl -e 'binmode STDIN; my $want="\e]52;c;\a"; my $got=""; while (length($got) < length($want)) { my $n=sysread(STDIN, my $b, length($want)-length($got)); exit 42 unless defined($n) && $n > 0; $got .= $b; } exit($got eq $want ? 0 : 43);'; result=$?; stty echo icanon; if [ $result -eq 0 ]; then printf '\r\n__DT_OSC52_DENY_%s__\r\n' EXACT; else printf '\r\n__DT_OSC52_DENY_%s__\r\n' MISMATCH; fi''',
    );
    await pane.submit();
    await _waitForAsciiMarker(session, exactMarker);
    _expectLifecycle(
      _findAscii(session.terminalScreenSet.activeScreen, mismatchMarker) ==
          null,
      'real PTY did not receive the exact empty OSC 52 query reply',
    );
    final bool noClipboardAuthority =
        clipboard.text == sentinel &&
        clipboard.changeCount == changeCount &&
        clipboard.readCount == reads &&
        clipboard.writeCount == writes;
    final bool exactCounters =
        sink.deniedClipboardReadCount == deniedReads + 1 &&
        sink.deniedClipboardWriteCount == deniedWrites + 1 &&
        sink.deniedClipboardClearCount == deniedClears + 1 &&
        sink.rejectedClipboardRequestCount == rejected &&
        sink.acceptedReplyCount == acceptedReplies + 1;
    _expectLifecycle(
      noClipboardAuthority && exactCounters,
      'OSC 52 crossed the default-deny clipboard boundary: '
      'text_unchanged=${clipboard.text == sentinel} '
      'change_count=${clipboard.changeCount - changeCount} '
      'reads=${clipboard.readCount - reads} writes=${clipboard.writeCount - writes} '
      'denied_reads=${sink.deniedClipboardReadCount - deniedReads} '
      'denied_writes=${sink.deniedClipboardWriteCount - deniedWrites} '
      'denied_clears=${sink.deniedClipboardClearCount - deniedClears} '
      'rejected=${sink.rejectedClipboardRequestCount - rejected} '
      'replies=${sink.acceptedReplyCount - acceptedReplies}',
    );
    stdout.writeln(
      'TERMINAL_OSC52_POLICY_TEST query_empty=true write_denied=true '
      'clear_denied=true clipboard_callbacks=0 counters=true',
    );
  }

  static Future<void> _exerciseClipboardCopySelection(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner selectionOwner,
    MenuItem copyItem,
    _MemoryTerminalClipboard clipboard,
    _TerminalClipboardProductObservation observation,
  ) async {
    const String marker = 'COPYCLIPBOARD';
    const String cjkMarker = 'COPYCJK';
    const String cjkText = '日本語';
    pane.insertText(
      "printf '\\r\\nCOPY%s\\r\\nCOPY%s%sEND\\r\\n' "
      "'CLIPBOARD' 'CJK' '日本語'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, marker);
    await _waitForAsciiMarker(session, cjkMarker);
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final _TerminalAsciiPosition position = _findAscii(
      session.terminalScreenSet.activeScreen,
      marker,
    )!;
    final _TerminalAsciiPosition cjkPosition = _findAscii(
      session.terminalScreenSet.activeScreen,
      cjkMarker,
    )!;
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    final int initialReports = mouseObservation.terminalReportCount;

    Future<void> inject(
      AppKitMouseEventKind kind,
      _TerminalAsciiPosition target,
      int column,
    ) async {
      final int generation = selectionOwner.gesture.snapshot.generation;
      _injectMouseEventForTesting(
        application,
        window,
        kind: kind,
        x: (column + 0.5) * metrics.cellWidth,
        y: (target.row + 0.5) * metrics.cellHeight,
        button: 0,
        modifiers: 0,
        clickCount: 1,
        monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
      );
      await _waitForSelectionGeneration(selectionOwner, generation + 1);
    }

    Future<void> selectAndCopy({
      required _TerminalAsciiPosition target,
      required int startColumn,
      required int endColumn,
      required String expected,
    }) async {
      await inject(AppKitMouseEventKind.down, target, startColumn);
      await inject(AppKitMouseEventKind.dragged, target, endColumn);
      await inject(AppKitMouseEventKind.up, target, endColumn);
      _expectSelectionText(
        selectionOwner,
        expected,
        TerminalSelectionUnit.cell,
      );
      final int copyBaseline = observation.copyCount;
      copyItem.performAction();
      final Stopwatch deadline = Stopwatch()..start();
      while (deadline.elapsed < const Duration(seconds: 3) &&
          observation.copyCount == copyBaseline &&
          observation.failure == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _expectLifecycle(
        observation.failure == null &&
            observation.copyCount == copyBaseline + 1 &&
            clipboard.text == expected &&
            clipboard.changeCount == observation.copyChangeCount &&
            observation.copiedUtf8Bytes == utf8.encode(expected).length &&
            mouseObservation.terminalReportCount == initialReports,
        'native Copy menu did not publish the exact stable selection: '
        'expected=$expected actual=${clipboard.text}',
      );
    }

    await selectAndCopy(
      target: position,
      startColumn: position.column,
      endColumn: position.column + marker.length - 1,
      expected: marker,
    );
    final int cjkStart = cjkPosition.column + cjkMarker.length;
    await selectAndCopy(
      target: cjkPosition,
      startColumn: cjkStart + 1,
      endColumn: cjkStart + 1,
      expected: cjkText[0],
    );
    await selectAndCopy(
      target: cjkPosition,
      startColumn: cjkStart + 2,
      endColumn: cjkStart + 2,
      expected: cjkText[1],
    );
    await selectAndCopy(
      target: cjkPosition,
      startColumn: cjkStart + 5,
      endColumn: cjkStart + 5,
      expected: cjkText[2],
    );
    await selectAndCopy(
      target: cjkPosition,
      startColumn: cjkStart + 1,
      endColumn: cjkStart + 4,
      expected: cjkText,
    );
    stdout.writeln(
      'TERMINAL_CLIPBOARD_COPY_TEST selection=true menu=true exact=true '
      'cjk_individual=true cjk_wide=true local_only=true '
      'bytes=${observation.copiedUtf8Bytes}',
    );
  }

  static Future<bool> _exerciseTextInput(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    TerminalTextInputClient client,
    TerminalTextInputEventRouter eventRouter,
  ) async {
    const String readyMarker = '__DT_IME_READY__';
    const String receivedMarker = '__DT_IME_1b5b41e697a5e69cace8aa9e__';
    surface.updateWindowState(isVisible: true, isOccluded: false);
    surface.processPending();
    pane.insertText(
      "stty raw -echo; printf '\\r\\n__DT_%s_READY__\\r\\n' IME; "
      "bytes=\$(dd bs=1 count=12 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "stty sane; printf '\\r\\n__DT_IME_%s__\\r\\n' \"\$bytes\"",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, readyMarker);

    final TerminalLiveMetalSurfaceSnapshot baseline = surface.snapshot();
    client.debugRunAcceptanceStage(1);
    final Stopwatch preeditDeadline = Stopwatch()..start();
    var preeditFrameDelta = 0;
    while (preeditDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      preeditFrameDelta = snapshot.frameBuildCount - baseline.frameBuildCount;
      if (eventRouter.lastGeneration >= 3 &&
          eventRouter.isCompositionActive &&
          surface.preeditState.isActive &&
          snapshot.acceptedFrameCount > baseline.acceptedFrameCount &&
          preeditFrameDelta > 0) {
        break;
      }
      if (eventRouter.lastGeneration >= 3) {
        surface.processPending();
      }
      _expectLifecycle(
        session.isLive,
        'text-input test shell exited before rendering preedit',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      eventRouter.lastGeneration >= 3 &&
          eventRouter.isCompositionActive &&
          surface.preeditState.isActive &&
          preeditFrameDelta > 0,
      'text-input test did not render staged preedit '
      'generation=${eventRouter.lastGeneration} '
      'router_active=${eventRouter.isCompositionActive} '
      'surface_active=${surface.preeditState.isActive} '
      'frame_delta=$preeditFrameDelta '
      'accepted_delta='
      '${surface.snapshot().acceptedFrameCount - baseline.acceptedFrameCount}',
    );

    client.debugRunAcceptanceStage(2);
    final Stopwatch commitDeadline = Stopwatch()..start();
    while (commitDeadline.elapsed < const Duration(seconds: 5) &&
        (eventRouter.lastGeneration < 5 ||
            !eventRouter.isCompositionActive ||
            !surface.preeditState.isActive)) {
      _expectLifecycle(
        session.isLive,
        'text-input test shell exited before commit delivery',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      eventRouter.lastGeneration >= 5 &&
          eventRouter.isCompositionActive &&
          surface.preeditState.isActive,
      'text-input test did not commit once and begin cancellable preedit',
    );

    client.debugRunAcceptanceStage(3);
    final Stopwatch cancelDeadline = Stopwatch()..start();
    while (cancelDeadline.elapsed < const Duration(seconds: 5) &&
        (eventRouter.lastGeneration < 6 ||
            eventRouter.isCompositionActive ||
            surface.preeditState.isActive)) {
      _expectLifecycle(
        session.isLive,
        'text-input test shell exited before cancellation',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      eventRouter.lastGeneration >= 6 &&
          !eventRouter.isCompositionActive &&
          !surface.preeditState.isActive,
      'text-input test did not cancel without commit',
    );
    await _waitForAsciiMarker(session, receivedMarker);
    _expectLifecycle(
      client.geometryGeneration > 0,
      'text-input test did not publish candidate geometry',
    );
    stdout.writeln(
      'TERMINAL_TEXT_INPUT_TEST raw=true preedit=true commit_once=true '
      'cancel=true candidate=true geometry_generation='
      '${client.geometryGeneration} frame_build_delta=$preeditFrameDelta',
    );
    return true;
  }

  static Future<bool> _exerciseInputMatrix(
    TerminalSession session,
    TerminalPane pane,
    TerminalTextInputClient client,
    TerminalTextInputEventRouter eventRouter,
  ) async {
    final TerminalInputAcceptanceMatrix matrix =
        TerminalInputAcceptanceMatrix.standard;
    const String readyMarker = '__DT_MATRIX_READY__';
    const String receivedMarker = '__DT_MATRIX_EXACT__';
    pane.insertText(
      "stty raw -echo; printf '\\r\\n__DT_%s_READY__\\r\\n' MATRIX; "
      "bytes=\$(dd bs=1 count=${matrix.expectedBytes.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "stty sane; if [ \"\$bytes\" = '${matrix.expectedHex}' ]; then "
      "printf '\\r\\n__DT_MATRIX_EXACT__\\r\\n'; else "
      "printf '\\r\\n__DT_MATRIX_MISMATCH__\\r\\n'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, readyMarker);

    final int firstGeneration = eventRouter.lastGeneration + 1;
    client.debugRunAcceptanceMatrix();
    final Stopwatch deliveryDeadline = Stopwatch()..start();
    final int finalGeneration = firstGeneration + matrix.eventCount - 1;
    while (deliveryDeadline.elapsed < const Duration(seconds: 5) &&
        eventRouter.lastGeneration < finalGeneration) {
      _expectLifecycle(
        session.isLive,
        'input matrix shell exited before native event delivery',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      eventRouter.lastGeneration >= finalGeneration &&
          !eventRouter.isCompositionActive,
      'input matrix event generation/order is incomplete: '
      'first=$firstGeneration expected_minimum_final=$finalGeneration '
      'actual=${eventRouter.lastGeneration}',
    );
    await _waitForAsciiMarker(session, receivedMarker);
    stdout.writeln(
      'TERMINAL_INPUT_MATRIX_TEST version='
      '${TerminalInputAcceptanceMatrix.version} rows=${matrix.rows.length} '
      'events=${matrix.eventCount} bytes=${matrix.expectedBytes.length} '
      'categories=${TerminalInputMatrixCategory.values.length} '
      'us=true jis=true dead_key=true cjk=true emoji=true '
      'unicode_hex=true repeat=true exact=true',
    );
    return true;
  }

  static Future<bool> _exerciseFocusReporting(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    Window window,
    _TerminalFocusProductObservation observation,
  ) async {
    const String receivedMarker = '__DT_FOCUS_1b5b4f1b5b49__';
    final int initialReports = observation.terminalReportCount;
    final int initialBytes = observation.terminalReportBytes;
    final int initialDuplicates = observation.duplicateTransitionCount;
    final int initialDisabled = observation.modeDisabledCount;
    pane.insertText(
      "printf '\\033[?1004h'; stty raw -echo; "
      "bytes=\$(dd bs=1 count=6 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "stty sane; printf '\\033[?1004l\\r\\n__DT_FOCUS_%s__\\r\\n' "
      '"\$bytes"',
    );
    await pane.submit();

    final Stopwatch modeDeadline = Stopwatch()..start();
    while (!session.terminalScreenSet.focusReportingMode &&
        modeDeadline.elapsed < const Duration(seconds: 3)) {
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before enabling focus reporting',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      session.terminalScreenSet.focusReportingMode,
      'display-test did not observe DEC focus reporting mode',
    );

    _injectFocusEventForTesting(
      application,
      window,
      isFocused: false,
      monotonicNanoseconds: observation.nextInjectedTimestamp(),
    );
    _injectFocusEventForTesting(
      application,
      window,
      isFocused: false,
      monotonicNanoseconds: observation.nextInjectedTimestamp(),
    );
    _injectFocusEventForTesting(
      application,
      window,
      isFocused: true,
      monotonicNanoseconds: observation.nextInjectedTimestamp(),
    );
    await _waitForAsciiMarker(session, receivedMarker);

    final Stopwatch resetDeadline = Stopwatch()..start();
    while (session.terminalScreenSet.focusReportingMode &&
        resetDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      !session.terminalScreenSet.focusReportingMode,
      'display-test zsh did not reset DEC focus reporting mode',
    );
    _injectFocusEventForTesting(
      application,
      window,
      isFocused: false,
      monotonicNanoseconds: observation.nextInjectedTimestamp(),
    );
    await Future<void>.delayed(Duration.zero);

    final int reportDelta = observation.terminalReportCount - initialReports;
    final int byteDelta = observation.terminalReportBytes - initialBytes;
    final int duplicateDelta =
        observation.duplicateTransitionCount - initialDuplicates;
    final int disabledDelta = observation.modeDisabledCount - initialDisabled;
    _expectLifecycle(
      reportDelta == 2 &&
          byteDelta == 6 &&
          duplicateDelta == 1 &&
          disabledDelta == 1,
      'focus product routing counts changed unexpectedly: '
      'reports=$reportDelta bytes=$byteDelta duplicates=$duplicateDelta '
      'disabled=$disabledDelta',
    );
    stdout.writeln(
      'TERMINAL_FOCUS_TEST mode=true blur=true duplicate=true focus=true '
      'reset=true exact=true reports=$reportDelta bytes=$byteDelta',
    );
    return true;
  }

  static Future<bool> _exerciseMouseInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation observation,
  ) async {
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    _expectLifecycle(
      screen.columns >= 96,
      'mouse UTF-8 acceptance requires at least 96 columns',
    );

    void inject(
      AppKitMouseEventKind kind, {
      required int column,
      required int row,
      int button = 0,
      int modifiers = 0,
    }) {
      _injectMouseEventForTesting(
        application,
        window,
        kind: kind,
        x: (column - 0.5) * metrics.cellWidth,
        y: (row - 0.5) * metrics.cellHeight,
        button: button,
        modifiers: modifiers,
        clickCount: kind == AppKitMouseEventKind.moved ? 0 : 1,
        monotonicNanoseconds: observation.nextInjectedTimestamp(),
      );
    }

    final int initialLocal = observation.localSelectionCount;
    final int initialReports = observation.terminalReportCount;
    final int initialReportBytes = observation.terminalReportBytes;
    inject(AppKitMouseEventKind.down, column: 1, row: 1);
    inject(AppKitMouseEventKind.up, column: 1, row: 1);
    await _waitForMouseObservation(
      observation,
      terminalReports: initialReports,
      localSelections: initialLocal + 2,
    );

    await _exerciseMouseProtocolStage(
      session: session,
      pane: pane,
      observation: observation,
      id: 'X10',
      enableSequence: '\\033[?9h',
      disableSequence: '\\033[?9l',
      expectedModes: const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.x10,
      ),
      expectedBytes: const <int>[0x1b, 0x5b, 0x4d, 0x20, 0x22, 0x22],
      expectedReportDelta: 1,
      expectedLocalDelta: 2,
      inject: () {
        inject(
          AppKitMouseEventKind.down,
          column: 2,
          row: 2,
          modifiers: ModifierKeys.shiftBit,
        );
        inject(
          AppKitMouseEventKind.up,
          column: 2,
          row: 2,
          modifiers: ModifierKeys.shiftBit,
        );
        inject(AppKitMouseEventKind.down, column: 2, row: 2);
      },
    );
    await _exerciseMouseProtocolStage(
      session: session,
      pane: pane,
      observation: observation,
      id: 'UTF8',
      enableSequence: '\\033[?1000h\\033[?1005h',
      disableSequence: '\\033[?1000l\\033[?1005l',
      expectedModes: const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.normal,
        encoding: TerminalMouseCoordinateEncoding.utf8,
      ),
      expectedBytes: const <int>[0x1b, 0x5b, 0x4d, 0x20, 0xc2, 0x80, 0x22],
      expectedReportDelta: 1,
      expectedLocalDelta: 0,
      inject: () => inject(AppKitMouseEventKind.down, column: 96, row: 2),
    );
    await _exerciseMouseProtocolStage(
      session: session,
      pane: pane,
      observation: observation,
      id: 'URXVT',
      enableSequence: '\\033[?1002h\\033[?1015h',
      disableSequence: '\\033[?1002l\\033[?1015l',
      expectedModes: const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.buttonEvent,
        encoding: TerminalMouseCoordinateEncoding.urxvt,
      ),
      expectedBytes: ascii.encode('\x1b[73;3;4M'),
      expectedReportDelta: 1,
      expectedLocalDelta: 0,
      inject: () => inject(
        AppKitMouseEventKind.dragged,
        column: 3,
        row: 4,
        button: 2,
        modifiers: ModifierKeys.optionBit,
      ),
    );
    await _exerciseMouseProtocolStage(
      session: session,
      pane: pane,
      observation: observation,
      id: 'SGR',
      enableSequence: '\\033[?1003h\\033[?1006h',
      disableSequence: '\\033[?1003l\\033[?1006l',
      expectedModes: const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.anyEvent,
        encoding: TerminalMouseCoordinateEncoding.sgr,
      ),
      expectedBytes: ascii.encode('\x1b[<35;5;6M\x1b[<2;5;6m'),
      expectedReportDelta: 2,
      expectedLocalDelta: 0,
      inject: () {
        inject(AppKitMouseEventKind.moved, column: 5, row: 6, button: -1);
        inject(AppKitMouseEventKind.up, column: 5, row: 6, button: 1);
      },
    );
    const int pixelColumn = 7;
    const int pixelRow = 3;
    final double backingScaleFactor = window.backingScaleFactor ?? 1;
    final int physicalPixelColumn = TerminalMouseEvent.physicalPixelCoordinate(
      point: (pixelColumn - 0.5) * metrics.cellWidth,
      logicalExtent: screen.columns * metrics.cellWidth,
      backingScaleFactor: backingScaleFactor,
    )!;
    final int physicalPixelRow = TerminalMouseEvent.physicalPixelCoordinate(
      point: (pixelRow - 0.5) * metrics.cellHeight,
      logicalExtent: screen.rows * metrics.cellHeight,
      backingScaleFactor: backingScaleFactor,
    )!;
    final List<int> expectedPixel = ascii.encode(
      '\x1b[<0;$physicalPixelColumn;$physicalPixelRow'
      'M',
    );
    await _exerciseMouseProtocolStage(
      session: session,
      pane: pane,
      observation: observation,
      id: 'PIXEL',
      enableSequence: '\\033[?1000h\\033[?1016h',
      disableSequence: '\\033[?1000l\\033[?1016l',
      expectedModes: const TerminalMouseModes(
        tracking: TerminalMouseTrackingMode.normal,
        encoding: TerminalMouseCoordinateEncoding.sgrPixels,
      ),
      expectedBytes: expectedPixel,
      expectedReportDelta: 1,
      expectedLocalDelta: 2,
      inject: () {
        inject(
          AppKitMouseEventKind.down,
          column: pixelColumn,
          row: pixelRow,
          modifiers: ModifierKeys.shiftBit,
        );
        inject(
          AppKitMouseEventKind.up,
          column: pixelColumn,
          row: pixelRow,
          modifiers: ModifierKeys.shiftBit,
        );
        inject(AppKitMouseEventKind.down, column: pixelColumn, row: pixelRow);
      },
    );

    final int reportDelta = observation.terminalReportCount - initialReports;
    final int localDelta = observation.localSelectionCount - initialLocal;
    final int byteDelta = observation.terminalReportBytes - initialReportBytes;
    _expectLifecycle(
      reportDelta == 6 &&
          localDelta == 6 &&
          byteDelta == 41 + expectedPixel.length &&
          observation.lastLocalSelection?.phase ==
              TerminalLocalSelectionPhase.end &&
          session.terminalScreenSet.mouseModes == const TerminalMouseModes(),
      'mouse product acceptance did not preserve exclusive ownership',
    );
    stdout.writeln(
      'TERMINAL_MOUSE_TEST protocols=5 x10=true utf8=true urxvt=true '
      'sgr=true pixel=true local=true shift_override=true exact=true '
      'reports=$reportDelta local_intents=$localDelta bytes=$byteDelta '
      'pixel_bytes=${expectedPixel.length} '
      'scale_16_16=${(backingScaleFactor * 65536).round()}',
    );
    return true;
  }

  static Future<bool> _exerciseHyperlinkInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalHyperlinkProductObservation observation,
  ) async {
    const String allowedMarker = '__DT_LINK_ALLOWED__';
    const String blockedMarker = '__DT_LINK_BLOCKED__';
    const String allowedUri = 'https://example.test/product-path';
    pane.insertText(
      "printf '\\r\\n\\033]8;id=allowed;$allowedUri\\a"
      "__DT_LINK_%s__\\033]8;;\\a\\r\\n' ALLOWED; "
      "printf '\\033]8;id=blocked;file:///tmp/dart-terminal-blocked\\a"
      "__DT_LINK_%s__\\033]8;;\\a\\r\\n' BLOCKED",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, allowedMarker);
    await _waitForAsciiMarker(session, blockedMarker);

    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final _TerminalAsciiPosition allowed = _findAscii(screen, allowedMarker)!;
    final _TerminalAsciiPosition blocked = _findAscii(screen, blockedMarker)!;
    final TerminalHyperlinkHit? allowedHit = surface.hyperlinkAtCell(
      row: allowed.row,
      column: allowed.column,
    );
    final TerminalHyperlinkHit? blockedHit = surface.hyperlinkAtCell(
      row: blocked.row,
      column: blocked.column,
    );
    _expectLifecycle(
      allowedHit != null &&
          allowedHit.uri == allowedUri &&
          blockedHit != null &&
          blockedHit.uri == 'file:///tmp/dart-terminal-blocked',
      'real PTY OSC 8 targets did not resolve at their visible cells',
    );

    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    void inject(
      AppKitMouseEventKind kind,
      _TerminalAsciiPosition position, {
      int button = 0,
      int modifiers = 0,
      int? clickCount,
    }) {
      _injectMouseEventForTesting(
        application,
        window,
        kind: kind,
        x: (position.column + 0.5) * metrics.cellWidth,
        y: (position.row + 0.5) * metrics.cellHeight,
        button: button,
        modifiers: modifiers,
        clickCount: clickCount ?? (kind == AppKitMouseEventKind.moved ? 0 : 1),
        monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
      );
    }

    final int initialReports = mouseObservation.terminalReportCount;
    final int initialLocal = mouseObservation.localSelectionCount;
    final int initialConsumed = observation.consumedEventCount;
    final TerminalLiveMetalSurfaceSnapshot hoverBaseline = surface.snapshot();
    inject(AppKitMouseEventKind.moved, allowed, button: -1);
    final Stopwatch hoverDeadline = Stopwatch()..start();
    var hoverMetal = false;
    while (hoverDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      hoverMetal =
          snapshot.hyperlinkHoverId == allowedHit!.hyperlinkId &&
          snapshot.hyperlinkHoverRow == allowed.row &&
          snapshot.hyperlinkHoverColumn == allowed.column &&
          snapshot.acceptedFrameCount > hoverBaseline.acceptedFrameCount;
      if (hoverMetal) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    inject(AppKitMouseEventKind.down, allowed);
    inject(AppKitMouseEventKind.up, allowed);
    await _waitForMouseObservation(
      mouseObservation,
      terminalReports: initialReports,
      localSelections: initialLocal + 2,
    );

    inject(
      AppKitMouseEventKind.down,
      allowed,
      modifiers: ModifierKeys.commandBit,
    );
    inject(
      AppKitMouseEventKind.up,
      allowed,
      modifiers: ModifierKeys.commandBit,
    );
    inject(
      AppKitMouseEventKind.down,
      blocked,
      modifiers: ModifierKeys.commandBit,
    );
    inject(
      AppKitMouseEventKind.up,
      blocked,
      modifiers: ModifierKeys.commandBit,
    );

    final bool exact =
        observation.openedTargets.length == 1 &&
        observation.openedTargets.single.value == allowedUri;
    final bool exclusive =
        observation.consumedEventCount - initialConsumed == 4 &&
        mouseObservation.terminalReportCount == initialReports &&
        mouseObservation.localSelectionCount == initialLocal + 2;
    final bool blockedNotice =
        observation.blockedNoticeCount == 1 &&
        pane.render().contains('[link target is not allowed]');
    _expectLifecycle(
      hoverMetal &&
          observation.openedActionCount == 1 &&
          observation.blockedActionCount == 1 &&
          observation.openUnavailableCount == 0 &&
          observation.failure == null &&
          exact &&
          exclusive &&
          blockedNotice,
      'hyperlink product hover/open ownership did not settle',
    );
    stdout.writeln(
      'TERMINAL_HYPERLINK_TEST osc8=true hover=true metal=true '
      'allowed=true blocked=true exact=$exact command_exclusive=$exclusive '
      'opens=${observation.openedTargets.length} '
      'blocked_notices=${observation.blockedNoticeCount} '
      'local_passthrough=${mouseObservation.localSelectionCount - initialLocal}',
    );
    return true;
  }

  static Future<bool> _exerciseSelectionInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner owner,
  ) async {
    const String characterMarker = '__DT_SELECT_CHAR__';
    const String wordMarker = '__DT_SELECT_WORD__';
    const String lineMarker = '__DT_SELECT_LINE__';
    pane.insertText(
      "printf '\\r\\n__DT_SELECT_%s__ABCDE\\r\\n"
      "__DT_SELECT_%s__ alpha_beta omega\\r\\n"
      "__DT_SELECT_%s__\\r\\n' 'CHAR' 'WORD' 'LINE'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, lineMarker);
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    final _TerminalAsciiPosition character = _findAscii(
      screen,
      characterMarker,
    )!;
    final _TerminalAsciiPosition word = _findAscii(screen, wordMarker)!;
    final _TerminalAsciiPosition line = _findAscii(screen, lineMarker)!;
    final int initialReports = mouseObservation.terminalReportCount;

    Future<void> injectCell(
      AppKitMouseEventKind kind, {
      required int row,
      required int column,
      int clickCount = 1,
      int modifiers = 0,
    }) async {
      final int generation = owner.gesture.snapshot.generation;
      _injectMouseEventForTesting(
        application,
        window,
        kind: kind,
        x: (column + 0.5) * metrics.cellWidth,
        y: (row + 0.5) * metrics.cellHeight,
        button: 0,
        modifiers: modifiers,
        clickCount: clickCount,
        monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
      );
      await _waitForSelectionGeneration(owner, generation + 1);
    }

    final int characterStart = character.column + characterMarker.length;
    await injectCell(
      AppKitMouseEventKind.down,
      row: character.row,
      column: characterStart,
    );
    await injectCell(
      AppKitMouseEventKind.dragged,
      row: character.row,
      column: characterStart + 4,
    );
    await injectCell(
      AppKitMouseEventKind.up,
      row: character.row,
      column: characterStart + 4,
    );
    _expectSelectionText(owner, 'ABCDE', TerminalSelectionUnit.cell);

    await injectCell(
      AppKitMouseEventKind.down,
      row: character.row,
      column: characterStart + 4,
    );
    await injectCell(
      AppKitMouseEventKind.dragged,
      row: character.row,
      column: characterStart,
    );
    await injectCell(
      AppKitMouseEventKind.up,
      row: character.row,
      column: characterStart,
    );
    _expectSelectionText(
      owner,
      'ABCDE',
      TerminalSelectionUnit.cell,
      reversed: true,
    );

    final int wordColumn = word.column + wordMarker.length + 3;
    await injectCell(
      AppKitMouseEventKind.down,
      row: word.row,
      column: wordColumn,
      clickCount: 2,
    );
    await injectCell(
      AppKitMouseEventKind.up,
      row: word.row,
      column: wordColumn,
      clickCount: 2,
    );
    _expectSelectionText(owner, 'alpha_beta', TerminalSelectionUnit.word);

    await injectCell(
      AppKitMouseEventKind.down,
      row: line.row,
      column: line.column + 2,
      clickCount: 3,
    );
    await injectCell(
      AppKitMouseEventKind.up,
      row: line.row,
      column: line.column + 2,
      clickCount: 3,
    );
    _expectSelectionText(owner, lineMarker, TerminalSelectionUnit.logicalLine);

    final int fillerLines = screen.rows + 8;
    pane.insertText(
      "i=0; while [ \$i -lt $fillerLines ]; do "
      "printf '__DT_SCROLL_%03d__\\n' \$i; i=\$((i+1)); done; "
      "printf '__DT_SCROLL_%s__\\n' 'BOTTOM'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, '__DT_SCROLL_BOTTOM__');
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalViewport viewport = session.terminalScreenSet.viewport;
    viewport.scrollToBottom();
    surface.notifyViewportChanged();
    _expectLifecycle(
      viewport.maximumOffset >= 3,
      'selection acceptance did not create enough retained history',
    );

    await injectCell(AppKitMouseEventKind.down, row: 0, column: 1);
    int generation = owner.gesture.snapshot.generation;
    _injectMouseEventForTesting(
      application,
      window,
      kind: AppKitMouseEventKind.dragged,
      x: metrics.cellWidth * 1.5,
      y: -1,
      button: 0,
      modifiers: 0,
      clickCount: 1,
      monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
    );
    await _waitForSelectionGeneration(owner, generation + 1);
    await _waitForViewportOffset(viewport, minimum: 3);
    generation = owner.gesture.snapshot.generation;
    _injectMouseEventForTesting(
      application,
      window,
      kind: AppKitMouseEventKind.up,
      x: metrics.cellWidth * 1.5,
      y: -1,
      button: 0,
      modifiers: 0,
      clickCount: 1,
      monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
    );
    await _waitForSelectionGeneration(owner, generation + 1);
    final bool scrolledUp = viewport.offset >= 3 && owner.scrolledUp;

    await injectCell(
      AppKitMouseEventKind.down,
      row: screen.rows - 1,
      column: 1,
    );
    generation = owner.gesture.snapshot.generation;
    _injectMouseEventForTesting(
      application,
      window,
      kind: AppKitMouseEventKind.dragged,
      x: metrics.cellWidth * 1.5,
      y: screen.rows * metrics.cellHeight + 1,
      button: 0,
      modifiers: 0,
      clickCount: 1,
      monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
    );
    await _waitForSelectionGeneration(owner, generation + 1);
    await _waitForViewportOffset(viewport, maximum: 0);
    generation = owner.gesture.snapshot.generation;
    _injectMouseEventForTesting(
      application,
      window,
      kind: AppKitMouseEventKind.up,
      x: metrics.cellWidth * 1.5,
      y: screen.rows * metrics.cellHeight + 1,
      button: 0,
      modifiers: 0,
      clickCount: 1,
      monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
    );
    await _waitForSelectionGeneration(owner, generation + 1);
    final bool scrolledDown = viewport.atBottom && owner.scrolledDown;

    final int acceptedFrames = surface.snapshot().acceptedFrameCount;
    final Stopwatch metalDeadline = Stopwatch()..start();
    TerminalLiveMetalSurfaceSnapshot metal = surface.snapshot();
    while (metalDeadline.elapsed < const Duration(seconds: 3) &&
        (metal.acceptedFrameCount <= acceptedFrames ||
            metal.selectionSpanCount == 0 ||
            metal.selectionCellCount == 0 ||
            metal.viewportOffset != 0)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      metal = surface.snapshot();
    }
    final bool metalSelection =
        metal.acceptedFrameCount > acceptedFrames &&
        metal.selectionSpanCount > 0 &&
        metal.selectionCellCount > 0 &&
        metal.viewportOffset == 0;
    final bool localOnly =
        mouseObservation.terminalReportCount == initialReports;
    _expectLifecycle(
      owner.characterObserved &&
          owner.wordObserved &&
          owner.logicalLineObserved &&
          owner.reverseObserved &&
          owner.shiftOverrideObserved &&
          scrolledUp &&
          scrolledDown &&
          metalSelection &&
          localOnly,
      'selection product acceptance did not settle',
    );
    stdout.writeln(
      'TERMINAL_SELECTION_TEST character=true word=true line=true '
      'reverse=true shift_override=true autoscroll_up=true '
      'autoscroll_down=true metal=true local_only=true',
    );
    return true;
  }

  static Future<bool> _exerciseWindowCloseScrollPosition(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner selectionOwner,
  ) async {
    final TerminalViewport viewport = session.terminalScreenSet.viewport;
    final int maximumOffset = viewport.maximumOffset;
    _expectLifecycle(
      maximumOffset >= 3 && pane.state == TerminalPaneState.running,
      'close-scroll acceptance requires live scrollable primary history',
    );
    final List<int> targetOffsets = <int>[0, maximumOffset ~/ 2, maximumOffset];
    var preservedCount = 0;
    for (final int targetOffset in targetOffsets) {
      viewport.scrollToBottom();
      viewport.scrollByRows(targetOffset);
      surface.notifyViewportChanged();
      final Stopwatch frameDeadline = Stopwatch()..start();
      while (frameDeadline.elapsed < const Duration(seconds: 3) &&
          surface.snapshot().viewportOffset != targetOffset) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _expectLifecycle(
        surface.snapshot().viewportOffset == targetOffset,
        'close-scroll fixture did not publish its initial viewport',
      );

      final int viewportGeneration = viewport.generation;
      final List<TerminalLogicalAnchor> visibleRows = <TerminalLogicalAnchor>[
        for (int row = 0; row < viewport.rows; row++) viewport.anchorAt(row, 0),
      ];
      final TerminalSelectionGestureSnapshot selection =
          selectionOwner.gesture.snapshot;
      final int ignoredBaseline = mouseObservation.ignoredCount;
      final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
      _injectMouseEventForTesting(
        application,
        window,
        kind: AppKitMouseEventKind.down,
        x: metrics.cellWidth * 0.5,
        y: -1,
        button: 0,
        modifiers: 0,
        clickCount: 1,
        monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
      );
      window.requestClose();

      final Stopwatch closeDeadline = Stopwatch()..start();
      while (closeDeadline.elapsed < const Duration(seconds: 3) &&
          (mouseObservation.ignoredCount != ignoredBaseline + 1 ||
              pane.state != TerminalPaneState.confirmationPending)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final TerminalSelectionGestureSnapshot afterSelection =
          selectionOwner.gesture.snapshot;
      final bool rowsPreserved = <int>[
        for (int row = 0; row < viewport.rows; row++)
          if (viewport.anchorAt(row, 0) != visibleRows[row]) row,
      ].isEmpty;
      final bool selectionPreserved =
          afterSelection.generation == selection.generation &&
          afterSelection.isActive == selection.isActive &&
          afterSelection.unit == selection.unit &&
          identical(afterSelection.range, selection.range) &&
          afterSelection.verticalEdge == selection.verticalEdge;
      final bool preserved =
          mouseObservation.ignoredCount == ignoredBaseline + 1 &&
          mouseObservation.lastIgnoreReason ==
              TerminalMouseIgnoreReason.outsideViewportPress &&
          pane.state == TerminalPaneState.confirmationPending &&
          pane.render().contains('[shell is still running') &&
          viewport.maximumOffset == maximumOffset &&
          viewport.offset == targetOffset &&
          viewport.generation == viewportGeneration &&
          surface.snapshot().viewportOffset == targetOffset &&
          rowsPreserved &&
          selectionPreserved;
      _expectLifecycle(
        preserved,
        'refused close changed terminal viewport/selection state at '
        'offset $targetOffset',
      );
      preservedCount++;
      pane.cancelCloseConfirmation();
      _expectLifecycle(
        pane.state == TerminalPaneState.running,
        'close-scroll fixture could not restore the live pane',
      );
    }
    stdout.writeln(
      'TERMINAL_CLOSE_SCROLL_TEST requests=$preservedCount refused=true '
      'chrome_press_ignored=true offset_preserved=true rows_preserved=true '
      'selection_preserved=true',
    );
    return preservedCount == targetOffsets.length;
  }

  static Future<bool> _exerciseAccessibilityInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner selectionOwner, {
    required String selectionMarker,
    required String promptMarker,
  }) async {
    await _waitForAsciiMarker(session, selectionMarker);
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final _TerminalAsciiPosition position = _findAscii(
      screen,
      selectionMarker,
    )!;
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;

    Future<void> inject(AppKitMouseEventKind kind, int column) async {
      final int generation = selectionOwner.gesture.snapshot.generation;
      _injectMouseEventForTesting(
        application,
        window,
        kind: kind,
        x: (column + 0.5) * metrics.cellWidth,
        y: (position.row + 0.5) * metrics.cellHeight,
        button: 0,
        modifiers: 0,
        clickCount: 1,
        monotonicNanoseconds: mouseObservation.nextInjectedTimestamp(),
      );
      await _waitForSelectionGeneration(selectionOwner, generation + 1);
    }

    await inject(AppKitMouseEventKind.down, position.column);
    await inject(
      AppKitMouseEventKind.dragged,
      position.column + selectionMarker.length - 1,
    );
    await inject(
      AppKitMouseEventKind.up,
      position.column + selectionMarker.length - 1,
    );
    _expectSelectionText(
      selectionOwner,
      selectionMarker,
      TerminalSelectionUnit.cell,
    );

    final TerminalSelectionRange? selection =
        selectionOwner.gesture.snapshot.range;
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 3)) {
      final TerminalAccessibilitySnapshot projected =
          TerminalAccessibilitySnapshot.capture(
            session.terminalScreenSet.viewport,
            selection: selection,
            maxUtf8Bytes: TerminalAccessibilityViewSnapshot.maximumUtf8Bytes,
            maxUtf16CodeUnits:
                TerminalAccessibilityViewSnapshot.maximumUtf16CodeUnits,
            maxColumnBoundaries:
                TerminalAccessibilityViewSnapshot.maximumColumnBoundaries,
          );
      final TerminalLiveMetalSurfaceSnapshot published = surface.snapshot();
      final bool visible =
          projected.text.contains(selectionMarker) &&
          projected.text.contains(promptMarker);
      final bool selected =
          projected.hasVisibleSelection &&
          projected.selectedText == selectionMarker &&
          published.accessibilityHasVisibleSelection &&
          published.accessibilitySelectionLength == selectionMarker.length;
      final bool cursor =
          projected.cursorRange != null &&
          projected.cursorRow == projected.rows - 1 &&
          projected.cursorColumn != null &&
          projected.cursorColumn! >= promptMarker.length &&
          published.accessibilityHasCursor &&
          published.accessibilityCursorRow == projected.cursorRow &&
          published.accessibilityCursorColumn == projected.cursorColumn;
      final bool synchronized =
          published.accessibilityGeneration > 0 &&
          published.accessibilityUtf16Length == projected.utf16Length;
      if (visible && selected && cursor && synchronized) {
        surface.debugVerifyAccessibility();
        stdout.writeln(
          'TERMINAL_ACCESSIBILITY_TEST visible=true selection=true '
          'cursor=true native=true focus=true notifications=true',
        );
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'terminal accessibility acceptance did not settle without '
      'publishing content',
    );
  }

  static Future<bool> _exerciseScrollInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalScrollProductObservation observation,
  ) async {
    final TerminalScreenSet screens = session.terminalScreenSet;
    final TerminalViewport viewport = screens.viewport;
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    _expectLifecycle(
      application.eventProtocolVersion >= 5,
      'scroll acceptance requires AppKit event protocol 5',
    );
    _expectLifecycle(
      viewport.maximumOffset >= 3,
      'scroll acceptance requires retained primary history',
    );
    viewport.scrollToBottom();
    surface.notifyViewportChanged();

    void inject({
      required double deltaY,
      double deltaX = 0,
      bool precise = false,
      AppKitScrollPhase phase = AppKitScrollPhase.none,
      AppKitScrollPhase momentumPhase = AppKitScrollPhase.none,
      bool directionInverted = false,
      int modifiers = 0,
      int column = 2,
      int row = 2,
    }) {
      _injectScrollEventForTesting(
        application,
        window,
        x: (column - 0.5) * metrics.cellWidth,
        y: (row - 0.5) * metrics.cellHeight,
        deltaX: deltaX,
        deltaY: deltaY,
        precise: precise,
        phase: phase,
        momentumPhase: momentumPhase,
        directionInverted: directionInverted,
        modifiers: modifiers,
        monotonicNanoseconds: observation.nextInjectedTimestamp(),
      );
    }

    final int acceptedFrames = surface.snapshot().acceptedFrameCount;
    inject(
      deltaY: metrics.cellHeight * 0.6,
      precise: true,
      phase: AppKitScrollPhase.began,
      directionInverted: true,
    );
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 0,
      alternateInputs: 0,
      ignored: 1,
    );
    inject(
      deltaY: metrics.cellHeight * 0.6,
      precise: true,
      phase: AppKitScrollPhase.changed,
      directionInverted: true,
    );
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 1,
      alternateInputs: 0,
      ignored: 1,
    );
    await _waitForViewportOffset(viewport, minimum: 1, maximum: 1);
    inject(
      deltaY: 0,
      precise: true,
      phase: AppKitScrollPhase.ended,
      directionInverted: true,
    );
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 1,
      alternateInputs: 0,
      ignored: 2,
    );
    inject(
      deltaY: metrics.cellHeight * 0.8,
      precise: true,
      momentumPhase: AppKitScrollPhase.began,
      directionInverted: true,
    );
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 2,
      alternateInputs: 0,
      ignored: 2,
    );
    await _waitForViewportOffset(viewport, minimum: 2, maximum: 2);
    inject(
      deltaY: 0,
      precise: true,
      momentumPhase: AppKitScrollPhase.ended,
      directionInverted: true,
    );
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 2,
      alternateInputs: 0,
      ignored: 3,
    );

    final Stopwatch frameDeadline = Stopwatch()..start();
    var metalViewport = false;
    while (frameDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      metalViewport =
          snapshot.acceptedFrameCount > acceptedFrames &&
          snapshot.viewportOffset == 2;
      if (metalViewport) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    inject(deltaY: -2, phase: AppKitScrollPhase.began, directionInverted: true);
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 3,
      alternateInputs: 0,
      ignored: 3,
    );
    await _waitForViewportOffset(viewport, minimum: 0, maximum: 0);

    final List<int> expectedWheel = ascii.encode('\x1b[<64;2;2M\x1b[<64;2;2M');
    final String expectedWheelHex = expectedWheel
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    pane.insertText(
      "stty raw -echo; printf '\\033[?1000h\\033[?1006h\\r\\n"
      "__DT_SCROLL_%s_READY__\\r\\n' 'MOUSE'; "
      "bytes=\$(dd bs=1 count=${expectedWheel.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?1000l\\033[?1006l'; stty sane; "
      "if [ \"\$bytes\" = '$expectedWheelHex' ]; then "
      "printf '\\r\\n__DT_SCROLL_%s_EXACT__\\r\\n' 'MOUSE'; else "
      "printf '\\r\\n__DT_SCROLL_%s_MISMATCH__\\r\\n' 'MOUSE'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, '__DT_SCROLL_MOUSE_READY__');
    _expectLifecycle(
      screens.mouseModes ==
          const TerminalMouseModes(
            tracking: TerminalMouseTrackingMode.normal,
            encoding: TerminalMouseCoordinateEncoding.sgr,
          ),
      'scroll mouse reporting mode was not active at the ready boundary',
    );
    inject(deltaY: 1, modifiers: ModifierKeys.shiftBit);
    await _waitForScrollObservation(
      observation,
      terminalReports: 0,
      localScrolls: 4,
      alternateInputs: 0,
      ignored: 3,
    );
    await _waitForViewportOffset(viewport, minimum: 1, maximum: 1);
    inject(deltaY: 2);
    await _waitForScrollObservation(
      observation,
      terminalReports: 1,
      localScrolls: 4,
      alternateInputs: 0,
      ignored: 3,
    );
    await _waitForAsciiMarker(session, '__DT_SCROLL_MOUSE_EXACT__');
    _expectLifecycle(
      screens.mouseModes == const TerminalMouseModes(),
      'scroll mouse reporting modes did not reset after exact capture',
    );
    viewport.scrollToBottom();
    surface.notifyViewportChanged();
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    const List<int> expectedAlternate = <int>[
      0x1b,
      0x4f,
      0x42,
      0x1b,
      0x4f,
      0x42,
    ];
    final String expectedAlternateHex = expectedAlternate
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    pane.insertText(
      "stty raw -echo; printf '\\033[?1049h\\033[?1h\\r\\n"
      "__DT_SCROLL_%s_READY__\\r\\n' 'ALT'; "
      "bytes=\$(dd bs=1 count=${expectedAlternate.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?1l\\033[?1049l'; stty sane; "
      "if [ \"\$bytes\" = '$expectedAlternateHex' ]; then "
      "printf '\\r\\n__DT_SCROLL_%s_EXACT__\\r\\n' 'ALT'; else "
      "printf '\\r\\n__DT_SCROLL_%s_MISMATCH__\\r\\n' 'ALT'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, '__DT_SCROLL_ALT_READY__');
    _expectLifecycle(
      screens.usingAlternate && screens.keyboardModes.applicationCursorKeys,
      'alternate screen/application cursor modes were not active',
    );
    inject(deltaY: -2);
    await _waitForScrollObservation(
      observation,
      terminalReports: 1,
      localScrolls: 4,
      alternateInputs: 1,
      ignored: 3,
    );
    await _waitForAsciiMarker(session, '__DT_SCROLL_ALT_EXACT__');
    _expectLifecycle(
      !screens.usingAlternate && !screens.keyboardModes.applicationCursorKeys,
      'alternate scroll fixture did not restore primary keyboard modes',
    );
    viewport.scrollToBottom();
    surface.notifyViewportChanged();

    final bool exclusive =
        observation.terminalReportCount == 1 &&
        observation.terminalReportBytes == expectedWheel.length &&
        observation.localScrollCount == 4 &&
        observation.localRequestedRows == 1 &&
        observation.localMovedRows == 1 &&
        observation.alternateInputCount == 1 &&
        observation.alternateInputBytes == expectedAlternate.length &&
        observation.ignoredCount == 3;
    _expectLifecycle(
      metalViewport && exclusive,
      'scroll product acceptance did not preserve bounded exclusive ownership',
    );
    stdout.writeln(
      'TERMINAL_SCROLL_TEST protocol=5 precise=true momentum=true '
      'wheel=true mouse_report=true shift_override=true alternate=true '
      'app_cursor=true local=true metal=true exclusive=true '
      'reports=${observation.terminalReportCount} '
      'local=${observation.localScrollCount} '
      'alternate_inputs=${observation.alternateInputCount} '
      'ignored=${observation.ignoredCount} '
      'bytes=${observation.terminalReportBytes} '
      'alternate_bytes=${observation.alternateInputBytes}',
    );
    return true;
  }

  static Future<void> _waitForSelectionGeneration(
    _TerminalSelectionProductOwner owner,
    int minimum,
  ) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 3) &&
        owner.gesture.snapshot.generation < minimum) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      owner.gesture.snapshot.generation >= minimum,
      'selection gesture event was not delivered',
    );
  }

  static Future<void> _waitForViewportOffset(
    TerminalViewport viewport, {
    int? minimum,
    int? maximum,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 3) &&
        ((minimum != null && viewport.offset < minimum) ||
            (maximum != null && viewport.offset > maximum))) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      (minimum == null || viewport.offset >= minimum) &&
          (maximum == null || viewport.offset <= maximum),
      'selection autoscroll viewport offset did not settle',
    );
  }

  static void _expectSelectionText(
    _TerminalSelectionProductOwner owner,
    String expected,
    TerminalSelectionUnit unit, {
    bool reversed = false,
  }) {
    final TerminalSelectionGestureSnapshot snapshot = owner.gesture.snapshot;
    final TerminalSelectionRange? range = snapshot.range;
    final TerminalSelectionText? text = range == null
        ? null
        : owner.gesture.viewport.extractSelection(range, maxScalars: 1024);
    _expectLifecycle(
      !snapshot.isActive &&
          snapshot.unit == unit &&
          range != null &&
          range.isReversed == reversed &&
          text?.text == expected &&
          text?.isTruncated == false,
      'selection text/unit/direction differed from the product fixture',
    );
  }

  static Future<void> _exerciseMouseProtocolStage({
    required TerminalSession session,
    required TerminalPane pane,
    required _TerminalMouseProductObservation observation,
    required String id,
    required String enableSequence,
    required String disableSequence,
    required TerminalMouseModes expectedModes,
    required List<int> expectedBytes,
    required int expectedReportDelta,
    required int expectedLocalDelta,
    required void Function() inject,
  }) async {
    final String expectedHex = expectedBytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final String readyMarker = '__DT_MOUSE_${id}_READY__';
    final String exactMarker = '__DT_MOUSE_${id}_EXACT__';
    pane.insertText(
      "stty raw -echo; printf '$enableSequence\\r\\n__DT_MOUSE_%s_READY__\\r\\n' '$id'; "
      "bytes=\$(dd bs=1 count=${expectedBytes.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); printf '$disableSequence'; stty sane; "
      "if [ \"\$bytes\" = '$expectedHex' ]; then "
      "printf '\\r\\n__DT_MOUSE_%s_EXACT__\\r\\n' '$id'; else "
      "printf '\\r\\n__DT_MOUSE_%s_MISMATCH__\\r\\n' '$id'; fi",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, readyMarker);
    _expectLifecycle(
      session.terminalScreenSet.mouseModes == expectedModes,
      '$id mouse modes were not active at the ready boundary',
    );
    final int reports = observation.terminalReportCount;
    final int locals = observation.localSelectionCount;
    inject();
    await _waitForMouseObservation(
      observation,
      terminalReports: reports + expectedReportDelta,
      localSelections: locals + expectedLocalDelta,
    );
    await _waitForAsciiMarker(session, exactMarker);
    _expectLifecycle(
      session.terminalScreenSet.mouseModes == const TerminalMouseModes(),
      '$id mouse modes did not reset after capture: '
      '${session.terminalScreenSet.mouseModes.tracking.name}/'
      '${session.terminalScreenSet.mouseModes.encoding.name}',
    );
  }

  static Future<void> _waitForMouseObservation(
    _TerminalMouseProductObservation observation, {
    required int terminalReports,
    required int localSelections,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 3) &&
        (observation.terminalReportCount < terminalReports ||
            observation.localSelectionCount < localSelections)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      observation.terminalReportCount == terminalReports &&
          observation.localSelectionCount == localSelections,
      'mouse event ownership counts changed unexpectedly: '
      'reports=${observation.terminalReportCount}/$terminalReports '
      'local=${observation.localSelectionCount}/$localSelections',
    );
  }

  static Future<void> _waitForScrollObservation(
    _TerminalScrollProductObservation observation, {
    required int terminalReports,
    required int localScrolls,
    required int alternateInputs,
    required int ignored,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 3) &&
        (observation.terminalReportCount < terminalReports ||
            observation.localScrollCount < localScrolls ||
            observation.alternateInputCount < alternateInputs ||
            observation.ignoredCount < ignored)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      observation.terminalReportCount == terminalReports &&
          observation.localScrollCount == localScrolls &&
          observation.alternateInputCount == alternateInputs &&
          observation.ignoredCount == ignored,
      'scroll ownership counts changed unexpectedly: '
      'reports=${observation.terminalReportCount}/$terminalReports '
      'local=${observation.localScrollCount}/$localScrolls '
      'alternate=${observation.alternateInputCount}/$alternateInputs '
      'ignored=${observation.ignoredCount}/$ignored',
    );
  }

  static void _injectMouseEventForTesting(
    AppKitApplication application,
    Window window, {
    required AppKitMouseEventKind kind,
    required double x,
    required double y,
    required int button,
    required int modifiers,
    required int clickCount,
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      switch (kind) {
        AppKitMouseEventKind.down => 10,
        AppKitMouseEventKind.up => 11,
        AppKitMouseEventKind.moved => 12,
        AppKitMouseEventKind.dragged => 13,
      },
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      x,
      y,
      button,
      modifiers,
      clickCount,
    ]);
  }

  static void _injectKeyEventForTesting(
    AppKitApplication application,
    Window window, {
    required int keyCode,
    required int modifiers,
    required String characters,
    required String charactersIgnoringModifiers,
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      20,
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      keyCode,
      modifiers,
      false,
      characters,
      charactersIgnoringModifiers,
    ]);
  }

  static Future<void> _exerciseCommandPaletteProduct(
    AppKitApplication application,
    Window terminalWindow,
    TerminalAppKitMenuProjection menuProjection,
    TerminalCommandPalettePresenter presenter,
    int Function() inputWriteCount,
  ) async {
    final MenuItem paletteItem = menuProjection.itemForAction(
      TerminalActionId.openCommandPalette,
    );
    final int expectedModifiers =
        ModifierKeys.shiftBit | ModifierKeys.commandBit;
    _expectLifecycle(
      paletteItem.isEnabled &&
          paletteItem.keyEquivalent == 'p' &&
          paletteItem.modifiers.bits == expectedModifiers,
      'command palette menu shortcut metadata is not Shift-Command-P',
    );
    final int baselineHandles = application.debugLiveObjectCount;
    final int baselineWrites = inputWriteCount();
    final int baselineResponderRestores =
        presenter.terminalResponderRestoreCount;
    paletteItem.performAction();
    final Stopwatch openDeadline = Stopwatch()..start();
    while (!presenter.isOpen &&
        openDeadline.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final Window? paletteWindow = presenter.activeWindow;
    _expectLifecycle(
      presenter.isOpen &&
          paletteWindow != null &&
          application.debugLiveObjectCount == baselineHandles + 2 &&
          (presenter.renderedText ?? '').contains('Command Palette'),
      'command palette did not own exactly one native window and text view',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow!,
      keyCode: 3,
      modifiers: 0,
      characters: 'focus next',
      charactersIgnoringModifiers: 'focus next',
      monotonicNanoseconds: 7100000,
    );
    final Stopwatch queryDeadline = Stopwatch()..start();
    while ((presenter.state.query != 'focus next' ||
            presenter.state.selectedAction?.definition.id !=
                TerminalActionId.focusNextPane ||
            !(presenter.renderedText ?? '').contains('› Focus Next Pane')) &&
        queryDeadline.elapsed < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      presenter.state.query == 'focus next' &&
          presenter.state.selectedAction?.definition.id ==
              TerminalActionId.focusNextPane &&
          (presenter.renderedText ?? '').contains('› Focus Next Pane'),
      'palette query did not select and render Focus Next Pane',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: 7200000,
    );
    final Stopwatch closeDeadline = Stopwatch()..start();
    while ((presenter.isOpen ||
            application.debugLiveObjectCount != baselineHandles ||
            presenter.terminalResponderRestoreCount !=
                baselineResponderRestores + 1) &&
        closeDeadline.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final TerminalActionDispatchResult? dispatch = presenter.lastDispatchResult;
    final int writeDelta = inputWriteCount() - baselineWrites;
    final bool handlesRestored =
        application.debugLiveObjectCount == baselineHandles;
    final bool responderRestored =
        presenter.terminalResponderRestoreCount ==
        baselineResponderRestores + 1;
    _expectLifecycle(
      !presenter.isOpen &&
          presenter.dispatchCount == 1 &&
          dispatch?.id == TerminalActionId.focusNextPane &&
          dispatch?.disposition == TerminalActionDispatchDisposition.executed &&
          writeDelta == 0 &&
          handlesRestored &&
          responderRestored,
      'command palette acceptance failed: '
      'open=${presenter.isOpen} dispatches=${presenter.dispatchCount} '
      'action=${dispatch?.id?.stableName} '
      'disposition=${dispatch?.disposition.name} writes=$writeDelta '
      'handles_restored=$handlesRestored '
      'responder_restored=$responderRestored',
    );
    stdout.writeln(
      'COMMAND_PALETTE_ACCEPTANCE shortcut=true opened=true query=true '
      'selected=${TerminalActionId.focusNextPane.stableName} '
      'dispatch=${dispatch!.disposition.name} '
      'invocations=${presenter.dispatchCount} terminal_write_delta=$writeDelta '
      'first_responder_restored=$responderRestored '
      'handles_restored=$handlesRestored',
    );
  }

  static void _injectFocusEventForTesting(
    AppKitApplication application,
    Window window, {
    required bool isFocused,
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      3,
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      isFocused,
    ]);
  }

  static void _injectScrollEventForTesting(
    AppKitApplication application,
    Window window, {
    required double x,
    required double y,
    required double deltaX,
    required double deltaY,
    required bool precise,
    required AppKitScrollPhase phase,
    required AppKitScrollPhase momentumPhase,
    required bool directionInverted,
    required int modifiers,
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      14,
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      x,
      y,
      deltaX,
      deltaY,
      precise,
      switch (phase) {
        AppKitScrollPhase.none => 0,
        AppKitScrollPhase.began => 1,
        AppKitScrollPhase.stationary => 2,
        AppKitScrollPhase.changed => 4,
        AppKitScrollPhase.ended => 8,
        AppKitScrollPhase.cancelled => 16,
        AppKitScrollPhase.mayBegin => 32,
      },
      switch (momentumPhase) {
        AppKitScrollPhase.none => 0,
        AppKitScrollPhase.began => 1,
        AppKitScrollPhase.stationary => 2,
        AppKitScrollPhase.changed => 4,
        AppKitScrollPhase.ended => 8,
        AppKitScrollPhase.cancelled => 16,
        AppKitScrollPhase.mayBegin => 32,
      },
      directionInverted,
      modifiers,
    ]);
  }

  static Future<void> _waitForAsciiMarker(
    TerminalSession session,
    String marker,
  ) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (_findAscii(session.terminalScreenSet.activeScreen, marker) != null) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'terminal session exited before marker $marker',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('terminal did not display marker $marker');
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

final class _TerminalHierarchyProductPane {
  _TerminalHierarchyProductPane({
    required this.pane,
    required this.session,
    required this.view,
    required TerminalTextInputClient client,
    required this.surface,
    required TerminalTextInputEventRouter textRouter,
    required void Function(Object, StackTrace) onTextInputError,
  }) : client = client,
       textRouter = textRouter,
       _textInputSubscription = client.events.listen(
         textRouter.route,
         onError: onTextInputError,
       );

  final TerminalPane pane;
  final TerminalSession session;
  final View view;
  final TerminalTextInputClient client;
  final TerminalLiveMetalSurface surface;
  final TerminalTextInputEventRouter textRouter;
  final StreamSubscription<TerminalTextInputEvent> _textInputSubscription;

  Future<void>? _cancelFuture;
  bool _textInputCancelled = false;
  bool adaptersDisposed = false;
  bool isVisible = false;

  void notifyScreenChanged() {
    if (!surface.isDisposed) surface.notifyScreenChanged();
  }

  void applyLayout(TerminalPaneLayoutRect? rectangle, {required bool visible}) {
    if (adaptersDisposed) {
      throw StateError('hierarchy pane ${pane.id} adapters are disposed');
    }
    isVisible = visible;
    surface.updateWindowState(isVisible: visible, isOccluded: !visible);
    if (!visible) return;
    final TerminalPaneLayoutRect layout = rectangle!;
    final TerminalGridSize grid = surface.resizeViewport(
      logicalWidth: layout.width,
      logicalHeight: layout.height,
    );
    pane.resize(rows: grid.rows, columns: grid.columns);
  }

  Future<void> cancelTextInput() => _cancelFuture ??= _cancelTextInput();

  Future<void> _cancelTextInput() async {
    await _textInputSubscription.cancel();
    _textInputCancelled = true;
  }

  void disposeAdapters() {
    if (adaptersDisposed) return;
    if (!_textInputCancelled) {
      throw StateError(
        'hierarchy pane ${pane.id} text input must be cancelled first',
      );
    }
    if (!client.isDisposed) client.dispose();
    if (!surface.isDisposed) surface.dispose();
    adaptersDisposed = true;
    isVisible = false;
  }

  Future<void> waitForTextInputGeneration(
    int generation, {
    required bool compositionActive,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5) &&
        (textRouter.lastGeneration < generation ||
            textRouter.isCompositionActive != compositionActive ||
            surface.preeditState.isActive != compositionActive)) {
      TerminalApplication._expectLifecycle(
        session.isLive,
        'hierarchy pane ${pane.id} exited during text-input delivery',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    TerminalApplication._expectLifecycle(
      textRouter.lastGeneration >= generation &&
          textRouter.isCompositionActive == compositionActive &&
          surface.preeditState.isActive == compositionActive,
      'hierarchy pane ${pane.id} text input did not reach generation '
      '$generation with composition_active=$compositionActive',
    );
  }
}

final class _TerminalAsciiPosition {
  const _TerminalAsciiPosition({required this.row, required this.column});

  final int row;
  final int column;
}

abstract interface class _TerminalClipboard {
  PasteboardTextSnapshot readText();
  int writeText(String text);
}

final class _AppKitTerminalClipboard implements _TerminalClipboard {
  const _AppKitTerminalClipboard(this.pasteboard);

  final Pasteboard pasteboard;

  @override
  PasteboardTextSnapshot readText() => pasteboard.readText();

  @override
  int writeText(String text) => pasteboard.writeText(text);
}

final class _MemoryTerminalClipboard implements _TerminalClipboard {
  String? _text;
  var _changeCount = 0;
  var _readCount = 0;
  var _writeCount = 0;

  String? get text => _text;
  int get changeCount => _changeCount;
  int get readCount => _readCount;
  int get writeCount => _writeCount;

  void seed(String text) {
    _text = text;
    _changeCount++;
  }

  @override
  PasteboardTextSnapshot readText() {
    _readCount++;
    return PasteboardTextSnapshot(text: _text, changeCount: _changeCount);
  }

  @override
  int writeText(String text) {
    _writeCount++;
    seed(text);
    return _changeCount;
  }
}

final class _TerminalClipboardProductObservation {
  var nativeWriteEnqueuedCount = 0;
  var copyCount = 0;
  var copiedUtf8Bytes = 0;
  var copyChangeCount = 0;
  var confirmationCount = 0;
  var approvalCount = 0;
  var busyCount = 0;
  var tooLargeCount = 0;
  var planningYieldCount = 0;
  int? writesAtFirstConfirmation;
  TerminalPasteAnalysis? confirmedAnalysis;
  TerminalPasteAnalysis? approvedAnalysis;
  TerminalPasteTransferResult? transfer;
  Object? failure;
  StackTrace? failureStackTrace;
  final List<int> confirmationChangeCounts = <int>[];
  final List<int> confirmationFingerprints = <int>[];
  final List<int> confirmationInvocationMicros = <int>[];
  final List<int> confirmationIssuedMicros = <int>[];
  final List<bool> pendingBeforeAttempts = <bool>[];
  final List<int> attemptSourceLengths = <int>[];
  final List<int> attemptBodyBytes = <int>[];
  final List<int> attemptNewlineCounts = <int>[];
  final List<int> attemptControlCounts = <int>[];
  final List<int> attemptReplacedCounts = <int>[];
  final List<bool> attemptTerminators = <bool>[];
  final List<bool> attemptLarge = <bool>[];
  final List<bool> attemptBracketed = <bool>[];
  final List<int> attemptEncodedBytes = <int>[];

  void recordGateAttempt({
    required bool hadPending,
    required TerminalPasteAnalysis analysis,
  }) {
    pendingBeforeAttempts.add(hadPending);
    attemptSourceLengths.add(analysis.sourceUtf16Length);
    attemptBodyBytes.add(analysis.encodedBodyBytes);
    attemptNewlineCounts.add(analysis.logicalNewlineCount);
    attemptControlCounts.add(analysis.controlCharacterCount);
    attemptReplacedCounts.add(analysis.replacedControlCount);
    attemptTerminators.add(analysis.hasBracketTerminator);
    attemptLarge.add(analysis.isLarge);
    attemptBracketed.add(analysis.bracketed);
    attemptEncodedBytes.add(analysis.encodedBytes);
  }

  void recordNative(PtyDiagnosticEvent event) {
    if (event.stage == PtyDiagnosticStage.writeEnqueued) {
      nativeWriteEnqueuedCount++;
    }
  }

  void recordCopy(TerminalSelectionText text, {required int changeCount}) {
    copyCount++;
    copiedUtf8Bytes = utf8.encode(text.text).length;
    copyChangeCount = changeCount;
  }

  void recordConfirmation(
    TerminalPasteAnalysis analysis, {
    required int changeCount,
    required int invocationMicros,
    required int issuedMicros,
  }) {
    confirmationCount++;
    writesAtFirstConfirmation ??= nativeWriteEnqueuedCount;
    confirmedAnalysis = analysis;
    confirmationChangeCounts.add(changeCount);
    confirmationFingerprints.add(analysis.fingerprint);
    confirmationInvocationMicros.add(invocationMicros);
    confirmationIssuedMicros.add(issuedMicros);
  }

  void recordApproval(TerminalPasteAnalysis analysis) {
    approvalCount++;
    approvedAnalysis = analysis;
  }

  void recordTransfer(TerminalPasteTransferResult result) {
    transfer = result;
  }

  void recordBusy() {
    busyCount++;
  }

  void recordTooLarge() {
    tooLargeCount++;
  }

  void recordPlanningYield() {
    planningYieldCount++;
  }

  void recordFailure(Object error, StackTrace stackTrace) {
    failure ??= error;
    failureStackTrace ??= stackTrace;
  }
}

final class _TerminalSelectionProductOwner {
  _TerminalSelectionProductOwner({required this.gesture, required this.surface})
    : autoscroller = TerminalSelectionAutoscroller(gesture: gesture);

  final TerminalSelectionGestureController gesture;
  final TerminalLiveMetalSurface surface;
  final TerminalSelectionAutoscroller autoscroller;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  bool _disposed = false;
  bool characterObserved = false;
  bool wordObserved = false;
  bool logicalLineObserved = false;
  bool reverseObserved = false;
  bool shiftOverrideObserved = false;
  bool scrolledUp = false;
  bool scrolledDown = false;

  TerminalSelectionText? selectedText({
    int maxScalars = TerminalSelectionText.maximumScalars,
  }) {
    final TerminalSelectionRange? range = gesture.snapshot.range;
    return range == null
        ? null
        : gesture.viewport.extractSelection(range, maxScalars: maxScalars);
  }

  void handle(TerminalLocalSelectionIntent intent) {
    if (_disposed) return;
    final TerminalSelectionGestureUpdate update = gesture.handle(intent);
    if (update.changed) {
      _recordGesture(update.snapshot, intent);
      surface.updateSelection(update.snapshot);
    }
    autoscroller.observeGesture(monotonicMicros: _clock.elapsedMicroseconds);
    _schedule();
  }

  void synchronize() {
    if (_disposed) return;
    final TerminalSelectionGestureUpdate update = gesture.synchronize();
    if (update.changed) surface.updateSelection(update.snapshot);
    autoscroller.observeGesture(monotonicMicros: _clock.elapsedMicroseconds);
    _schedule();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _recordGesture(
    TerminalSelectionGestureSnapshot snapshot,
    TerminalLocalSelectionIntent intent,
  ) {
    switch (snapshot.unit) {
      case TerminalSelectionUnit.cell:
        characterObserved = true;
      case TerminalSelectionUnit.word:
        wordObserved = true;
      case TerminalSelectionUnit.logicalLine:
        logicalLineObserved = true;
      case null:
        break;
    }
    reverseObserved |= snapshot.range?.isReversed ?? false;
    shiftOverrideObserved |= intent.modifiers.shift;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    final int? deadline = autoscroller.nextDeadlineMicros;
    if (deadline == null) return;
    final int now = _clock.elapsedMicroseconds;
    _timer = Timer(
      Duration(microseconds: deadline > now ? deadline - now : 0),
      _tick,
    );
  }

  void _tick() {
    _timer = null;
    if (_disposed) return;
    final int before = gesture.viewport.offset;
    final TerminalSelectionAutoscrollUpdate update = autoscroller.advance(
      monotonicMicros: _clock.elapsedMicroseconds,
    );
    if (update.didScroll) {
      final int after = gesture.viewport.offset;
      scrolledUp |= after > before;
      scrolledDown |= after < before;
      surface.updateSelection(gesture.snapshot);
      surface.notifyViewportChanged();
    } else if (update.outcome == TerminalSelectionAutoscrollOutcome.cancelled) {
      surface.updateSelection(gesture.snapshot);
    }
    _schedule();
  }
}

final class _TerminalMouseProductObservation {
  int terminalReportCount = 0;
  int terminalReportBytes = 0;
  int localSelectionCount = 0;
  int ignoredCount = 0;
  int _nextTimestamp = 1000000;
  TerminalLocalSelectionIntent? lastLocalSelection;
  TerminalMouseIgnoreReason? lastIgnoreReason;

  int nextInjectedTimestamp() => _nextTimestamp++;

  void recordTerminalReport(Uint8List bytes) {
    terminalReportCount++;
    terminalReportBytes += bytes.length;
  }

  void recordLocalSelection(TerminalLocalSelectionIntent intent) {
    localSelectionCount++;
    lastLocalSelection = intent;
  }

  void recordIgnored(TerminalMouseIgnoreReason reason) {
    ignoredCount++;
    lastIgnoreReason = reason;
  }
}

final class _TerminalFocusProductObservation {
  int terminalReportCount = 0;
  int terminalReportBytes = 0;
  int modeDisabledCount = 0;
  int duplicateTransitionCount = 0;
  int _nextTimestamp = 2000000;

  int nextInjectedTimestamp() => _nextTimestamp++;

  void recordTerminalReport(Uint8List bytes) {
    terminalReportCount++;
    terminalReportBytes += bytes.length;
  }

  void recordRoute(TerminalFocusReportResult result) {
    switch (result.disposition) {
      case TerminalFocusReportDisposition.terminalReport:
        break;
      case TerminalFocusReportDisposition.modeDisabled:
        modeDisabledCount++;
      case TerminalFocusReportDisposition.duplicateTransition:
        duplicateTransitionCount++;
    }
  }
}

final class _TerminalHyperlinkProductObservation {
  int consumedEventCount = 0;
  int openedActionCount = 0;
  int blockedActionCount = 0;
  int openUnavailableCount = 0;
  int blockedNoticeCount = 0;
  int unavailableNoticeCount = 0;
  final List<AllowedExternalUrl> openedTargets = <AllowedExternalUrl>[];
  Object? failure;
  StackTrace? failureStackTrace;

  bool recordAcceptanceOpen(AllowedExternalUrl target) {
    openedTargets.add(target);
    return true;
  }

  void recordRoute(TerminalHyperlinkRouteResult result) {
    if (result.isConsumed) consumedEventCount++;
    switch (result.action) {
      case TerminalHyperlinkAction.opened:
        openedActionCount++;
      case TerminalHyperlinkAction.blocked:
        blockedActionCount++;
      case TerminalHyperlinkAction.unavailable:
        openUnavailableCount++;
      case TerminalHyperlinkAction.none ||
          TerminalHyperlinkAction.armed ||
          TerminalHyperlinkAction.cancelled:
        break;
    }
  }

  void recordNotice(TerminalHyperlinkNoticeKind kind) {
    switch (kind) {
      case TerminalHyperlinkNoticeKind.blocked:
        blockedNoticeCount++;
      case TerminalHyperlinkNoticeKind.unavailable:
        unavailableNoticeCount++;
    }
  }

  void recordFailure(Object error, StackTrace stackTrace) {
    failure ??= error;
    failureStackTrace ??= stackTrace;
  }
}

final class _TerminalScrollProductObservation {
  int terminalReportCount = 0;
  int terminalReportBytes = 0;
  int localScrollCount = 0;
  int localRequestedRows = 0;
  int localMovedRows = 0;
  int alternateInputCount = 0;
  int alternateInputBytes = 0;
  int ignoredCount = 0;
  int _nextTimestamp = 2000000;
  TerminalScrollIgnoreReason? lastIgnoreReason;

  int nextInjectedTimestamp() => _nextTimestamp++;

  void recordTerminalReport(Uint8List bytes) {
    terminalReportCount++;
    terminalReportBytes += bytes.length;
  }

  void recordLocalScroll({
    required int requestedRows,
    required int before,
    required int after,
  }) {
    localScrollCount++;
    localRequestedRows += requestedRows;
    localMovedRows += after - before;
  }

  void recordAlternateInput(Uint8List bytes) {
    alternateInputCount++;
    alternateInputBytes += bytes.length;
  }

  void recordIgnored(TerminalScrollIgnoreReason reason) {
    ignoredCount++;
    lastIgnoreReason = reason;
  }
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
    return handleTerminalKeyDown(
      TerminalAppKitKeyAdapter.adapt(appKitEvent),
      pane,
    );
  }

  TerminalKeyRouteResult handleTerminalKeyDown(
    TerminalKeyEvent event,
    TerminalPane pane,
  ) {
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
