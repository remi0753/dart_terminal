import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/testing.dart' as appkit_testing;
import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_terminal_app_intents_macos/dart_terminal_app_intents_macos.dart';
import 'package:dart_terminal_app_intents_macos/testing.dart'
    as app_intents_testing;
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'runtime_lifecycle.dart';
import 'terminal_accessibility_presentation.dart';
import 'terminal_action_menu.dart';
import 'terminal_action_registry.dart';
import 'terminal_app_intents_product.dart';
import 'terminal_appkit_policy.dart';
import 'terminal_applescript_product.dart';
import 'terminal_application_quit_coordinator.dart';
import 'terminal_application_state.dart';
import 'terminal_application_theme.dart';
import 'terminal_command_palette.dart';
import 'terminal_config.dart';
import 'terminal_config_reload.dart';
import 'terminal_configuration_reference.dart';
import 'terminal_context_dock.dart';
import 'terminal_context_dock_directory.dart';
import 'terminal_context_dock_path_handoff.dart';
import 'terminal_context_dock_process.dart';
import 'terminal_core/terminal_desktop_signals.dart';
import 'terminal_core/terminal_hyperlink.dart';
import 'terminal_core/terminal_mouse_modes.dart';
import 'terminal_core/terminal_osc52.dart';
import 'terminal_core/terminal_reply.dart';
import 'terminal_core/terminal_screen.dart';
import 'terminal_core/terminal_screen_parser_sink.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_core/terminal_semantic_prompt.dart';
import 'terminal_core/terminal_style.dart';
import 'terminal_core/vt_parser_inspector.dart';
import 'terminal_desktop_signal_projection.dart';
import 'terminal_diagnostics.dart';
import 'terminal_diagnostics_presenter.dart';
import 'terminal_directory_snapshot.dart';
import 'terminal_incident_controller.dart';
import 'terminal_incident_service.dart';
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
import 'terminal_input/terminal_prompt_click.dart';
import 'terminal_input/terminal_scroll_router.dart';
import 'terminal_input/terminal_selection_autoscroll.dart';
import 'terminal_input/terminal_selection_gesture.dart';
import 'terminal_input/terminal_text_input_event_router.dart';
import 'terminal_localization.dart';
import 'terminal_memory_pressure.dart';
import 'terminal_native_content.dart';
import 'terminal_native_hierarchy.dart';
import 'terminal_notification_product.dart';
import 'terminal_osc52_confirmation.dart';
import 'terminal_osc52_projection.dart';
import 'terminal_pane.dart';
import 'terminal_pane_close_coordinator.dart';
import 'terminal_process_resource_sampler.dart';
import 'terminal_product_configuration.dart';
import 'terminal_product_hierarchy_actions.dart';
import 'terminal_prompt_navigation.dart';
import 'terminal_quick_terminal.dart';
import 'terminal_renderer/glyph_atlas.dart';
import 'terminal_renderer/metal_atlas_bridge.dart';
import 'terminal_renderer/pane_work_scheduler.dart';
import 'terminal_renderer/terminal_cell_glyph.dart';
import 'terminal_renderer/terminal_live_metal_surface.dart';
import 'terminal_renderer/terminal_overlay.dart';
import 'terminal_restoration.dart';
import 'terminal_restoration_lifecycle.dart';
import 'terminal_secure_keyboard_entry.dart';
import 'terminal_session.dart';
import 'terminal_settings_document.dart';
import 'terminal_settings_editor.dart';
import 'terminal_settings_inspector.dart';
import 'terminal_shell_integration.dart';
import 'terminal_system_recovery.dart';
import 'terminal_tab_metadata.dart';
import 'terminal_tab_presentation.dart';
import 'terminal_terminfo_environment.dart';
import 'terminal_update_controller.dart';
import 'terminal_update_feed.dart';

final String terminalUsage = TerminalConfigurationReference().generateUsage();

const String _runtimeWorkerName = 'dart_terminal_runtime_worker';
const int _runtimeSoftwareFailureExitCode = 70;
const int _runtimeTemporaryFailureExitCode = 75;
const int _appKitLimitExceededStatus = 10;
const int _appIntentsDisabledStatus = 8;
const Duration _runtimePtyFaultGracefulTimeout = Duration(milliseconds: 200);
const Duration _runtimePtyFaultFinalTimeout = Duration(milliseconds: 200);
const Duration _runtimePtyFaultCleanupTimeout = Duration(milliseconds: 200);
const Duration _hostTerminationTimeout = Duration(seconds: 1);

RuntimeLifecycleWorkerCommand _bundledRuntimeWorkerCommand() {
  final MacosRuntimeHelperCommand command = MacosRuntime.bundleHelperCommand(
    _runtimeWorkerName,
  );
  return RuntimeLifecycleWorkerCommand(
    executable: command.executable,
    arguments: command.arguments,
  );
}

TerminalDiagnosticsPaneLifecycle _terminalDiagnosticsLifecycle(
  TerminalPaneState state,
) => switch (state) {
  TerminalPaneState.created => TerminalDiagnosticsPaneLifecycle.created,
  TerminalPaneState.starting => TerminalDiagnosticsPaneLifecycle.starting,
  TerminalPaneState.running => TerminalDiagnosticsPaneLifecycle.running,
  TerminalPaneState.confirmationPending =>
    TerminalDiagnosticsPaneLifecycle.confirmationPending,
  TerminalPaneState.exited => TerminalDiagnosticsPaneLifecycle.exited,
  TerminalPaneState.failed => TerminalDiagnosticsPaneLifecycle.failed,
  TerminalPaneState.closing => TerminalDiagnosticsPaneLifecycle.closing,
  TerminalPaneState.closed => TerminalDiagnosticsPaneLifecycle.closed,
};

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
    this.runtimeUserActionsTest = false,
    this.runtimeConfigurationTest = false,
    this.runtimeThemeTest = false,
    this.runtimeShellIntegrationTest = false,
    this.runtimeDesktopSignalsTest = false,
    this.runtimeOsc52Test = false,
    this.runtimeNativeContentTest = false,
    this.runtimeQuickTerminalTest = false,
    this.runtimeSecureKeyboardEntryTest = false,
    this.runtimeAppleScriptTest = false,
    this.runtimeSystemAutomationTest = false,
    this.runtimeDiagnosticsTest = false,
    this.runtimeDiagnosticsDirectory,
    this.runtimePerformanceTest = false,
    this.runtimeRestorationTest = false,
    this.runtimeRestorationPath,
    this.runtimeShellExitTestScenario = RuntimeShellExitTestScenario.none,
    this.runtimeLifecycleScenario = RuntimeLifecycleScenario.normal,
    this.runtimeWorkerCommand =
        const RuntimeLifecycleWorkerCommand.unconfigured(),
    this.effectiveConfiguration,
    this.configurationDiagnostics = const <TerminalConfigDiagnostic>[],
    this.configurationReloadController,
    this.settingsDocumentSession,
    this.localization,
    this.updateService,
    this.incidentService,
  });

  factory TerminalOptions.parse(
    List<String> arguments, {
    Map<String, String>? environment,
    RuntimeLifecycleWorkerCommand? runtimeWorkerCommand,
    TerminalConfigFileSystem? configFileSystem,
    TerminalConfigValueAvailabilityValidator? configValueAvailabilityValidator,
    String? currentDirectory,
  }) {
    final TerminalConfigLoader configLoader = TerminalConfigLoader(
      fileSystem: configFileSystem,
      valueAvailabilityValidator: configValueAvailabilityValidator,
    );
    final Map<String, String> selectedEnvironment =
        Map<String, String>.unmodifiable(environment ?? Platform.environment);
    final String selectedCurrentDirectory =
        currentDirectory ?? Directory.current.path;
    final TerminalConfigResolution configuration = configLoader.resolve(
      arguments,
      environment: selectedEnvironment,
      currentDirectory: selectedCurrentDirectory,
    );
    final String? initialWorkingDirectory = configuration.snapshot.value(
      TerminalProductConfigSchema.workingDirectory,
    );
    Duration? autoCloseAfter;
    var runtimeResourceStress = false;
    var runtimeShutdownFaultInjection = false;
    var runtimePtyExitFaultInjection = false;
    var runtimeTerminalDisplayTest = false;
    var runtimeClipboardTest = false;
    var runtimeNativeHierarchyTest = false;
    var runtimeUserActionsTest = false;
    var runtimeConfigurationTest = false;
    var runtimeThemeTest = false;
    var runtimeShellIntegrationTest = false;
    var runtimeDesktopSignalsTest = false;
    var runtimeOsc52Test = false;
    var runtimeNativeContentTest = false;
    var runtimeQuickTerminalTest = false;
    var runtimeSecureKeyboardEntryTest = false;
    var runtimeAppleScriptTest = false;
    var runtimeSystemAutomationTest = false;
    var runtimeDiagnosticsTest = false;
    var runtimePerformanceTest = false;
    var runtimeRestorationTest = false;
    RuntimeShellExitTestScenario? runtimeShellExitTestScenario;
    RuntimeLifecycleScenario? runtimeLifecycleScenario;
    for (final String argument in configuration.remainingArguments) {
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
      if (argument == '--runtime-user-actions-test') {
        if (runtimeUserActionsTest) {
          throw const FormatException(
            '--runtime-user-actions-test may only be supplied once',
          );
        }
        runtimeUserActionsTest = true;
        continue;
      }
      if (argument == '--runtime-configuration-test') {
        if (runtimeConfigurationTest) {
          throw const FormatException(
            '--runtime-configuration-test may only be supplied once',
          );
        }
        runtimeConfigurationTest = true;
        continue;
      }
      if (argument == '--runtime-theme-test') {
        if (runtimeThemeTest) {
          throw const FormatException(
            '--runtime-theme-test may only be supplied once',
          );
        }
        runtimeThemeTest = true;
        continue;
      }
      if (argument == '--runtime-shell-integration-test') {
        if (runtimeShellIntegrationTest) {
          throw const FormatException(
            '--runtime-shell-integration-test may only be supplied once',
          );
        }
        runtimeShellIntegrationTest = true;
        continue;
      }
      if (argument == '--runtime-desktop-signals-test') {
        if (runtimeDesktopSignalsTest) {
          throw const FormatException(
            '--runtime-desktop-signals-test may only be supplied once',
          );
        }
        runtimeDesktopSignalsTest = true;
        continue;
      }
      if (argument == '--runtime-osc52-test') {
        if (runtimeOsc52Test) {
          throw const FormatException(
            '--runtime-osc52-test may only be supplied once',
          );
        }
        runtimeOsc52Test = true;
        continue;
      }
      if (argument == '--runtime-native-content-test') {
        if (runtimeNativeContentTest) {
          throw const FormatException(
            '--runtime-native-content-test may only be supplied once',
          );
        }
        runtimeNativeContentTest = true;
        continue;
      }
      if (argument == '--runtime-quick-terminal-test') {
        if (runtimeQuickTerminalTest) {
          throw const FormatException(
            '--runtime-quick-terminal-test may only be supplied once',
          );
        }
        runtimeQuickTerminalTest = true;
        continue;
      }
      if (argument == '--runtime-secure-keyboard-entry-test') {
        if (runtimeSecureKeyboardEntryTest) {
          throw const FormatException(
            '--runtime-secure-keyboard-entry-test may only be supplied once',
          );
        }
        runtimeSecureKeyboardEntryTest = true;
        continue;
      }
      if (argument == '--runtime-applescript-test') {
        if (runtimeAppleScriptTest) {
          throw const FormatException(
            '--runtime-applescript-test may only be supplied once',
          );
        }
        runtimeAppleScriptTest = true;
        continue;
      }
      if (argument == '--runtime-system-automation-test') {
        if (runtimeSystemAutomationTest) {
          throw const FormatException(
            '--runtime-system-automation-test may only be supplied once',
          );
        }
        runtimeSystemAutomationTest = true;
        continue;
      }
      if (argument == '--runtime-diagnostics-test') {
        if (runtimeDiagnosticsTest) {
          throw const FormatException(
            '--runtime-diagnostics-test may only be supplied once',
          );
        }
        runtimeDiagnosticsTest = true;
        continue;
      }
      if (argument == '--runtime-performance-test') {
        if (runtimePerformanceTest) {
          throw const FormatException(
            '--runtime-performance-test may only be supplied once',
          );
        }
        runtimePerformanceTest = true;
        continue;
      }
      if (argument == '--runtime-restoration-test') {
        if (runtimeRestorationTest) {
          throw const FormatException(
            '--runtime-restoration-test may only be supplied once',
          );
        }
        runtimeRestorationTest = true;
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
    if (runtimeNativeContentTest &&
        selectedEnvironment['DT_RUNTIME_NATIVE_CONTENT_TEST'] != '1') {
      throw const FormatException(
        'native content test requires the integration-test gate',
      );
    }
    if (runtimeNativeContentTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeQuickTerminalTest ||
            runtimeSecureKeyboardEntryTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'native content test cannot be combined with another runtime test',
      );
    }
    if (runtimeQuickTerminalTest &&
        selectedEnvironment['DT_RUNTIME_QUICK_TERMINAL_TEST'] != '1') {
      throw const FormatException(
        'Quick Terminal test requires the integration-test gate',
      );
    }
    if (runtimeSecureKeyboardEntryTest &&
        selectedEnvironment['DT_RUNTIME_SECURE_KEYBOARD_ENTRY_TEST'] != '1') {
      throw const FormatException(
        'Secure Keyboard Entry test requires the integration-test gate',
      );
    }
    if (runtimeAppleScriptTest &&
        selectedEnvironment['DT_RUNTIME_APPLESCRIPT_TEST'] != '1') {
      throw const FormatException(
        'AppleScript test requires the integration-test gate',
      );
    }
    if (runtimeAppleScriptTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeNativeContentTest ||
            runtimeQuickTerminalTest ||
            runtimeSecureKeyboardEntryTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'AppleScript test cannot be combined with another runtime test',
      );
    }
    if (runtimeSystemAutomationTest &&
        selectedEnvironment['DT_RUNTIME_SYSTEM_AUTOMATION_TEST'] != '1') {
      throw const FormatException(
        'system automation test requires the integration-test gate',
      );
    }
    if (runtimeSystemAutomationTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeNativeContentTest ||
            runtimeQuickTerminalTest ||
            runtimeSecureKeyboardEntryTest ||
            runtimeAppleScriptTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'system automation test cannot be combined with another runtime test',
      );
    }
    final String? runtimeDiagnosticsDirectory = runtimeDiagnosticsTest
        ? selectedEnvironment['DT_RUNTIME_DIAGNOSTICS_DIRECTORY']
        : null;
    if (runtimeDiagnosticsTest &&
        selectedEnvironment['DT_RUNTIME_DIAGNOSTICS_TEST'] != '1') {
      throw const FormatException(
        'diagnostics test requires the integration-test gate',
      );
    }
    if (runtimeDiagnosticsTest &&
        (runtimeDiagnosticsDirectory == null ||
            runtimeDiagnosticsDirectory.isEmpty ||
            utf8.encode(runtimeDiagnosticsDirectory).length > 4096 ||
            !File(runtimeDiagnosticsDirectory).isAbsolute)) {
      throw const FormatException(
        'diagnostics test requires a bounded absolute export directory',
      );
    }
    if (runtimeDiagnosticsTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeNativeContentTest ||
            runtimeQuickTerminalTest ||
            runtimeSecureKeyboardEntryTest ||
            runtimeAppleScriptTest ||
            runtimeSystemAutomationTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'diagnostics test cannot be combined with another runtime test',
      );
    }
    if (runtimePerformanceTest &&
        selectedEnvironment['DT_RUNTIME_PERFORMANCE_TEST'] != '1') {
      throw const FormatException(
        'performance test requires the integration-test gate',
      );
    }
    if (runtimePerformanceTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeNativeContentTest ||
            runtimeQuickTerminalTest ||
            runtimeSecureKeyboardEntryTest ||
            runtimeAppleScriptTest ||
            runtimeSystemAutomationTest ||
            runtimeDiagnosticsTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'performance test cannot be combined with another runtime test',
      );
    }
    if (runtimeSecureKeyboardEntryTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeQuickTerminalTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'Secure Keyboard Entry test cannot be combined with another runtime '
        'test',
      );
    }
    if (runtimeQuickTerminalTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeOsc52Test ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'Quick Terminal test cannot be combined with another runtime test',
      );
    }
    if (runtimeUserActionsTest &&
        (environment ?? Platform.environment)['DT_RUNTIME_USER_ACTIONS_TEST'] !=
            '1') {
      throw const FormatException(
        'user actions test requires the integration-test gate',
      );
    }
    if (runtimeUserActionsTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'user actions test cannot be combined with another runtime test',
      );
    }
    if (runtimeConfigurationTest &&
        (environment ??
                Platform.environment)['DT_RUNTIME_CONFIGURATION_TEST'] !=
            '1') {
      throw const FormatException(
        'configuration test requires the integration-test gate',
      );
    }
    if (runtimeConfigurationTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'configuration test cannot be combined with another runtime test',
      );
    }
    if (runtimeThemeTest &&
        selectedEnvironment['DT_RUNTIME_THEME_TEST'] != '1') {
      throw const FormatException(
        'theme test requires the integration-test gate',
      );
    }
    if (runtimeThemeTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'theme test cannot be combined with another runtime test',
      );
    }
    if (runtimeShellIntegrationTest &&
        selectedEnvironment['DT_RUNTIME_SHELL_INTEGRATION_TEST'] != '1') {
      throw const FormatException(
        'shell integration test requires the integration-test gate',
      );
    }
    if (runtimeShellIntegrationTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'shell integration test cannot be combined with another runtime test',
      );
    }
    if (runtimeDesktopSignalsTest &&
        selectedEnvironment['DT_RUNTIME_DESKTOP_SIGNALS_TEST'] != '1') {
      throw const FormatException(
        'desktop signals test requires the integration-test gate',
      );
    }
    if (runtimeDesktopSignalsTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'desktop signals test cannot be combined with another runtime test',
      );
    }
    if (runtimeOsc52Test &&
        selectedEnvironment['DT_RUNTIME_OSC52_TEST'] != '1') {
      throw const FormatException(
        'OSC 52 test requires the integration-test gate',
      );
    }
    if (runtimeOsc52Test &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            runtimeConfigurationTest ||
            runtimeThemeTest ||
            runtimeShellIntegrationTest ||
            runtimeDesktopSignalsTest ||
            runtimeRestorationTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'OSC 52 test cannot be combined with another runtime test',
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
    final String? runtimeRestorationPath = runtimeRestorationTest
        ? selectedEnvironment['DT_RUNTIME_RESTORATION_PATH']
        : null;
    if (runtimeRestorationTest &&
        selectedEnvironment['DT_RUNTIME_RESTORATION_TEST'] != '1') {
      throw const FormatException(
        'restoration test requires the integration-test gate',
      );
    }
    if (runtimeRestorationTest &&
        (runtimeRestorationPath == null || runtimeRestorationPath.isEmpty)) {
      throw const FormatException(
        'restoration test requires an isolated persistence path',
      );
    }
    if (runtimeRestorationTest &&
        (selectedScenario != RuntimeLifecycleScenario.normal ||
            autoCloseAfter != null ||
            runtimeResourceStress ||
            runtimeShutdownFaultInjection ||
            runtimePtyExitFaultInjection ||
            runtimeTerminalDisplayTest ||
            runtimeClipboardTest ||
            runtimeNativeHierarchyTest ||
            runtimeUserActionsTest ||
            selectedShellExitTest != RuntimeShellExitTestScenario.none)) {
      throw const FormatException(
        'restoration test cannot be combined with another runtime test',
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
      runtimeUserActionsTest: runtimeUserActionsTest,
      runtimeConfigurationTest: runtimeConfigurationTest,
      runtimeThemeTest: runtimeThemeTest,
      runtimeShellIntegrationTest: runtimeShellIntegrationTest,
      runtimeDesktopSignalsTest: runtimeDesktopSignalsTest,
      runtimeOsc52Test: runtimeOsc52Test,
      runtimeNativeContentTest: runtimeNativeContentTest,
      runtimeQuickTerminalTest: runtimeQuickTerminalTest,
      runtimeSecureKeyboardEntryTest: runtimeSecureKeyboardEntryTest,
      runtimeAppleScriptTest: runtimeAppleScriptTest,
      runtimeSystemAutomationTest: runtimeSystemAutomationTest,
      runtimeDiagnosticsTest: runtimeDiagnosticsTest,
      runtimeDiagnosticsDirectory: runtimeDiagnosticsDirectory,
      runtimePerformanceTest: runtimePerformanceTest,
      runtimeRestorationTest: runtimeRestorationTest,
      runtimeRestorationPath: runtimeRestorationPath,
      runtimeShellExitTestScenario: selectedShellExitTest,
      runtimeLifecycleScenario: selectedScenario,
      runtimeWorkerCommand:
          runtimeWorkerCommand ?? _bundledRuntimeWorkerCommand(),
      effectiveConfiguration: configuration.snapshot,
      configurationDiagnostics: configuration.snapshot.diagnostics,
      configurationReloadController: TerminalConfigReloadController.fromStartup(
        arguments: arguments,
        initialSnapshot: configuration.snapshot,
        loader: configLoader,
        environment: selectedEnvironment,
        currentDirectory: selectedCurrentDirectory,
      ),
      settingsDocumentSession: TerminalSettingsDocumentSession(
        loader: configLoader,
        arguments: arguments,
        environment: selectedEnvironment,
        currentDirectory: selectedCurrentDirectory,
      ),
      localization: TerminalLocalization.fromEnvironment(selectedEnvironment),
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
  final bool runtimeUserActionsTest;
  final bool runtimeConfigurationTest;
  final bool runtimeThemeTest;
  final bool runtimeShellIntegrationTest;
  final bool runtimeDesktopSignalsTest;
  final bool runtimeOsc52Test;
  final bool runtimeNativeContentTest;
  final bool runtimeQuickTerminalTest;
  final bool runtimeSecureKeyboardEntryTest;
  final bool runtimeAppleScriptTest;
  final bool runtimeSystemAutomationTest;
  final bool runtimeDiagnosticsTest;
  final String? runtimeDiagnosticsDirectory;
  final bool runtimePerformanceTest;
  final bool runtimeRestorationTest;
  final String? runtimeRestorationPath;
  final RuntimeShellExitTestScenario runtimeShellExitTestScenario;
  final RuntimeLifecycleScenario runtimeLifecycleScenario;
  final RuntimeLifecycleWorkerCommand runtimeWorkerCommand;
  final TerminalConfigSnapshot? effectiveConfiguration;
  final List<TerminalConfigDiagnostic> configurationDiagnostics;
  final TerminalConfigReloadController? configurationReloadController;
  final TerminalSettingsDocumentSession? settingsDocumentSession;
  final TerminalLocalization? localization;
  final TerminalUpdateProductService? updateService;
  final TerminalIncidentService? incidentService;
}

final class TerminalApplication {
  const TerminalApplication({this.options = const TerminalOptions()});

  final TerminalOptions options;

  Future<void> run() async {
    final TerminalLocalization localization =
        options.localization ??
        TerminalLocalization.fromEnvironment(Platform.environment);
    final String productWindowTitle = localization.applicationName;
    final RuntimeLifecycleScenario scenario = options.runtimeLifecycleScenario;
    _writeLifecycleEvent(scenario, 'root-start', 0);
    TerminalRendererMacos.initialize();
    TerminalAppleScriptMacosNativePort.initialize();
    final MacosPtyBackend nativePtyBackend = MacosPtyBackend.open(
      MacosRuntime.bundleFrameworkPath(dartPtyMacosLibraryName),
    );
    final PtyBackend ptyBackend = options.runtimePtyExitFaultInjection
        ? _ExitNotificationSuppressingPtyBackend(nativePtyBackend)
        : nativePtyBackend;
    final AppKitApplication application = await AppKitApplication.attach(
      externalUrlPolicy: terminalExternalUrlPolicy,
    );
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
    String? bundledShellIntegrationContract;
    try {
      bundledShellIntegrationContract = MacosRuntime.bundleResourcePath(
        TerminalShellIntegrationContract.relativePath,
      );
    } on MacosRuntimeException {
      bundledShellIntegrationContract = null;
    }
    final TerminalShellIntegrationBundle shellIntegrationBundle =
        TerminalShellIntegrationBundle.resolve(
          bundledContractPath: bundledShellIntegrationContract,
        );
    stdout.writeln(shellIntegrationBundle.machineLine());
    if (options.runtimeRestorationTest) {
      await _runRestorationProductAcceptance(
        application,
        ptyBackend,
        terminfoEnvironment,
        options.runtimeWorkerCommand,
        options.initialWorkingDirectory,
        options.runtimeRestorationPath!,
      );
      return;
    }
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
    if (options.runtimeUserActionsTest ||
        options.runtimeConfigurationTest ||
        options.runtimeThemeTest ||
        options.runtimeShellIntegrationTest ||
        options.runtimeDesktopSignalsTest ||
        options.runtimeOsc52Test ||
        options.runtimeNativeContentTest ||
        options.runtimeQuickTerminalTest ||
        options.runtimeSecureKeyboardEntryTest ||
        options.runtimeAppleScriptTest ||
        options.runtimeSystemAutomationTest ||
        options.runtimeDiagnosticsTest ||
        options.runtimePerformanceTest ||
        _usesInteractiveProductHierarchy(options)) {
      final TerminalProductConfiguration productConfiguration =
          options.effectiveConfiguration == null
          ? TerminalProductConfiguration.defaults
          : TerminalProductConfiguration.fromSnapshot(
              options.effectiveConfiguration!,
            );
      await _runInteractiveHierarchyProduct(
        application,
        ptyBackend,
        terminfoEnvironment,
        shellIntegrationBundle,
        options.runtimeWorkerCommand,
        options.initialWorkingDirectory,
        productConfiguration,
        localization: localization,
        configurationReloadController: options.configurationReloadController,
        settingsDocumentSession: options.settingsDocumentSession,
        updateService: options.updateService,
        incidentService: options.incidentService,
        runUserActionAcceptance: options.runtimeUserActionsTest,
        runConfigurationAcceptance: options.runtimeConfigurationTest,
        runThemeAcceptance: options.runtimeThemeTest,
        runShellIntegrationAcceptance: options.runtimeShellIntegrationTest,
        runDesktopSignalAcceptance: options.runtimeDesktopSignalsTest,
        runOsc52Acceptance: options.runtimeOsc52Test,
        runNativeContentAcceptance: options.runtimeNativeContentTest,
        runQuickTerminalAcceptance: options.runtimeQuickTerminalTest,
        runSecureKeyboardEntryAcceptance:
            options.runtimeSecureKeyboardEntryTest,
        runAppleScriptAcceptance: options.runtimeAppleScriptTest,
        runSystemAutomationAcceptance: options.runtimeSystemAutomationTest,
        runDiagnosticsAcceptance: options.runtimeDiagnosticsTest,
        diagnosticsExportDirectory: options.runtimeDiagnosticsDirectory,
        runPerformanceAcceptance: options.runtimePerformanceTest,
        osc52Clipboard: options.runtimeOsc52Test
            ? _MemoryTerminalOsc52Clipboard()
            : null,
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
    TerminalTabPresentationResolver? windowPresentationResolver;
    TerminalTabState? windowPresentationTab;
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
    var currentWindowPlacement = TerminalWindowPlacement(
      windowedFrame: TerminalWindowFrame(
        left: 100,
        top: 90,
        width: currentWindowWidth,
        height: currentWindowHeight,
      ),
      screen: null,
      fullscreen: false,
    );

    try {
      final View createdContentView = TerminalRendererMacos.createView();
      contentView = createdContentView;
      final Window createdWindow =
          Window(
              frame: const Rect.fromLTWH(100, 90, 920, 580),
              title: productWindowTitle,
              configuration: terminalWindowConfiguration,
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
                graphicsWorker: lifecycle,
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
            final TerminalTabPresentationResolver? resolver =
                windowPresentationResolver;
            final TerminalTabState? tab = windowPresentationTab;
            final TerminalTabPresentation presentation =
                resolver != null && tab != null
                ? resolver.resolve(tab, fallbackTitle: productWindowTitle)
                : TerminalTabPresentation(
                    title:
                        terminalSession
                            ?.terminalScreenSet
                            .metadata
                            .windowTitle ??
                        productWindowTitle,
                    color: null,
                    representedFilePath: null,
                  );
            if (createdWindow.title != presentation.title) {
              createdWindow.title = presentation.title;
            }
            if (createdWindow.representedFilePath !=
                presentation.representedFilePath) {
              createdWindow.representedFilePath =
                  presentation.representedFilePath;
            }
            final WindowTabAccessory? tabAccessory = terminalTabAccessory(
              presentation.color,
            );
            if (createdWindow.tabAccessory != tabAccessory) {
              createdWindow.tabAccessory = tabAccessory;
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
      windowPresentationTab = logicalWindow.selectedTab;
      windowPresentationResolver = TerminalTabPresentationResolver(
        metadataForPane: (PaneId paneId) => paneId == createdPane.id
            ? terminalSession?.terminalScreenSet.metadata
            : null,
      );
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
              keyEventRouter.handleTerminalKeyEvent(event, createdPane);
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
            screens: terminalSession!.terminalScreenSet,
            surface: createdMetalSurface,
            onPromptCursorInput: createdPane.sendInput,
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
          actionMenuProjection?.refresh();
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
          installedCommandPalette.refresh();
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
            case ApplicationAppearanceChangedEvent():
              // Isolated legacy runtime fixtures retain their fixed palette;
              // the ordinary hierarchy owns live theme projection.
              break;
            case ApplicationAccessibilityDisplayPreferencesChangedEvent():
              // Product projection is installed only by the ordinary
              // hierarchy; isolated legacy fixtures safely ignore the value.
              break;
            case ApplicationPowerStateChangedEvent() ||
                ApplicationScreenSetChangedEvent() ||
                ApplicationMemoryPressureChangedEvent():
              // The isolated legacy fixture does not install product recovery
              // policy and safely ignores generic system-state observations.
              break;
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
            case WindowEvent() ||
                MenuItemInvokedEvent() ||
                GlobalHotKeyPressedEvent() ||
                ApplicationFolderServiceRequestedEvent() ||
                ApplicationUserNotificationChangedEvent() ||
                ViewQuickLookRequestedEvent() ||
                ViewServicesTextReceivedEvent() ||
                ViewDropPerformedEvent():
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
              if (options.runtimeResourceStress) {
                stdout.writeln(
                  'TERMINAL_RESOURCE_CLOSE stage=request-observed '
                  'pane_state=${createdPane.state.name}',
                );
              }
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
              if (options.runtimeResourceStress) {
                stdout.writeln(
                  'TERMINAL_RESOURCE_CLOSE stage=decision-published '
                  'allow=$allow pane_state=${createdPane.state.name}',
                );
              }
              createdWindow.replyToCloseRequest(event, allow: allow);
              if (options.runtimeResourceStress) {
                stdout.writeln(
                  'TERMINAL_RESOURCE_CLOSE stage=request-replied '
                  'allow=$allow pane_state=${createdPane.state.name}',
                );
              }
              if (!allow &&
                  options.autoCloseAfter != null &&
                  autoCloseConfirmationTimer == null) {
                autoCloseConfirmationTimer = Timer(
                  const Duration(milliseconds: 100),
                  () {
                    if (options.runtimeResourceStress) {
                      stdout.writeln(
                        'TERMINAL_RESOURCE_CLOSE '
                        'stage=confirmation-timer-fired '
                        'pane_state=${createdPane.state.name}',
                      );
                    }
                    if (!createdWindow.isClosed && !createdWindow.isDisposed) {
                      quitItem.performAction();
                      if (options.runtimeResourceStress) {
                        stdout.writeln(
                          'TERMINAL_RESOURCE_CLOSE '
                          'stage=quit-action-posted',
                        );
                      }
                    }
                  },
                );
                if (options.runtimeResourceStress) {
                  stdout.writeln(
                    'TERMINAL_RESOURCE_CLOSE '
                    'stage=confirmation-timer-scheduled',
                  );
                }
              }
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
            case WindowFrameChangedEvent(:final frame):
              if (!currentWindowPlacement.fullscreen) {
                currentWindowPlacement = currentWindowPlacement.copyWith(
                  windowedFrame: _terminalWindowFrame(frame),
                );
              }
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'frame',
                  'left=${frame.left} top=${frame.top} '
                      'width=${frame.width} height=${frame.height}',
                );
              }
            case WindowFullscreenChangedEvent(:final isFullscreen):
              currentWindowPlacement = currentWindowPlacement.copyWith(
                fullscreen: isFullscreen,
              );
              if (!isFullscreen) {
                final Rect restoredFrame = _appKitWindowFrame(
                  currentWindowPlacement.windowedFrame,
                );
                if (createdWindow.frame != restoredFrame) {
                  createdWindow.frame = restoredFrame;
                }
              }
              if (emitNativeEventWireObservation) {
                _writeWindowStateEvent(
                  application,
                  event,
                  'fullscreen',
                  'value=$isFullscreen',
                );
              }
            case WindowScreenChangedEvent(:final screen):
              hyperlinkController.cancelPress();
              createdMetalSurface.clearHyperlinkHover();
              if (screen == null) {
                currentWindowPlacement = currentWindowPlacement.copyWith(
                  clearScreen: true,
                );
              } else {
                final TerminalScreenPlacement observed =
                    _terminalScreenPlacement(screen);
                currentWindowPlacement =
                    TerminalWindowPlacementPolicy.resolveForAvailableScreens(
                      currentWindowPlacement,
                      <TerminalScreenPlacement>[observed],
                      fallbackDisplayId: observed.displayId,
                    );
                if (!currentWindowPlacement.fullscreen) {
                  final Rect migratedFrame = _appKitWindowFrame(
                    currentWindowPlacement.windowedFrame,
                  );
                  if (createdWindow.frame != migratedFrame) {
                    createdWindow.frame = migratedFrame;
                  }
                }
              }
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
      if (startStatus == RuntimeLifecycleStartStatus.ready) {
        terminalSession?.attachGraphicsWorker(createdLifecycle);
      }
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
              productWindowTitle,
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
          terminalSession?.attachGraphicsWorker(replacement);
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
        if (options.runtimeResourceStress) {
          stdout.writeln(
            'TERMINAL_RESOURCE_CLOSE stage=initial-timer-scheduled',
          );
        }
        autoCloseTimer = Timer(autoCloseAfter, () {
          if (options.runtimeResourceStress) {
            stdout.writeln(
              'TERMINAL_RESOURCE_CLOSE stage=initial-timer-fired '
              'pane_state=${createdPane.state.name}',
            );
          }
          if (!createdWindow.isClosed && !createdWindow.isDisposed) {
            pasteItem.performAction();
            if (options.runtimeResourceStress) {
              stdout.writeln(
                'TERMINAL_RESOURCE_CLOSE stage=paste-action-posted',
              );
            }
            closeItem.performAction();
            if (options.runtimeResourceStress) {
              stdout.writeln(
                'TERMINAL_RESOURCE_CLOSE stage=close-action-posted',
              );
            }
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

  static bool _usesInteractiveProductHierarchy(TerminalOptions options) =>
      options.runtimeLifecycleScenario == RuntimeLifecycleScenario.normal &&
      options.autoCloseAfter == null &&
      !options.runtimeResourceStress &&
      !options.runtimeShutdownFaultInjection &&
      !options.runtimePtyExitFaultInjection &&
      !options.runtimeTerminalDisplayTest &&
      !options.runtimeClipboardTest &&
      !options.runtimeNativeHierarchyTest &&
      !options.runtimeConfigurationTest &&
      !options.runtimeThemeTest &&
      !options.runtimeShellIntegrationTest &&
      !options.runtimeDesktopSignalsTest &&
      !options.runtimeOsc52Test &&
      !options.runtimeNativeContentTest &&
      !options.runtimeQuickTerminalTest &&
      !options.runtimeSecureKeyboardEntryTest &&
      !options.runtimeAppleScriptTest &&
      !options.runtimeSystemAutomationTest &&
      !options.runtimeDiagnosticsTest &&
      !options.runtimePerformanceTest &&
      !options.runtimeRestorationTest &&
      options.runtimeShellExitTestScenario == RuntimeShellExitTestScenario.none;

  static Future<void> _runInteractiveHierarchyProduct(
    AppKitApplication application,
    PtyBackend ptyBackend,
    TerminalTerminfoEnvironment terminfoEnvironment,
    TerminalShellIntegrationBundle shellIntegrationBundle,
    RuntimeLifecycleWorkerCommand workerCommand,
    String? initialWorkingDirectory,
    TerminalProductConfiguration productConfiguration, {
    required TerminalLocalization localization,
    TerminalConfigReloadController? configurationReloadController,
    TerminalSettingsDocumentSession? settingsDocumentSession,
    TerminalUpdateProductService? updateService,
    TerminalIncidentService? incidentService,
    bool runUserActionAcceptance = false,
    bool runConfigurationAcceptance = false,
    bool runThemeAcceptance = false,
    bool runShellIntegrationAcceptance = false,
    bool runDesktopSignalAcceptance = false,
    bool runOsc52Acceptance = false,
    bool runNativeContentAcceptance = false,
    bool runQuickTerminalAcceptance = false,
    bool runSecureKeyboardEntryAcceptance = false,
    bool runAppleScriptAcceptance = false,
    bool runSystemAutomationAcceptance = false,
    bool runDiagnosticsAcceptance = false,
    String? diagnosticsExportDirectory,
    bool runPerformanceAcceptance = false,
    TerminalOsc52ClipboardPort? osc52Clipboard,
  }) async {
    const String acceptancePrompt = '__DT_USER_ACTIONS_PROMPT__ ';
    final Rect initialWindowFrame = Rect.fromLTWH(
      100,
      90,
      productConfiguration.windowWidth,
      productConfiguration.windowHeight,
    );
    final TerminalApplicationState state = TerminalApplicationState();
    final Map<PaneId, TerminalSession> sessions = <PaneId, TerminalSession>{};
    final List<TerminalSession> allSessions = <TerminalSession>[];
    final Map<PaneId, String?> launchWorkingDirectories = <PaneId, String?>{};
    final Map<PaneId, TerminalProductConfiguration> paneConfigurations =
        <PaneId, TerminalProductConfiguration>{};
    final Map<PaneId, _TerminalHierarchyProductPane> owners =
        <PaneId, _TerminalHierarchyProductPane>{};
    final Map<PaneId, _TerminalSelectionProductOwner> selections =
        <PaneId, _TerminalSelectionProductOwner>{};
    final Map<PaneId, TerminalMouseRouter> mouseRouters =
        <PaneId, TerminalMouseRouter>{};
    final Map<PaneId, TerminalScrollRouter> scrollRouters =
        <PaneId, TerminalScrollRouter>{};
    final Map<PaneId, TerminalFocusReporter> focusReporters =
        <PaneId, TerminalFocusReporter>{};
    final Map<PaneId, TerminalHyperlinkInteractionController>
    hyperlinkControllers = <PaneId, TerminalHyperlinkInteractionController>{};
    final Map<PaneId, TerminalNativeContentCell> quickLookCells =
        <PaneId, TerminalNativeContentCell>{};
    final TerminalNativeContextGestureGate<TerminalTabId>
    nativeContextGestures = TerminalNativeContextGestureGate<TerminalTabId>();
    final Map<TerminalTabId, StreamSubscription<WindowEvent>>
    windowSubscriptions = <TerminalTabId, StreamSubscription<WindowEvent>>{};
    final TerminalPaneWorkScheduler paneWorkScheduler =
        TerminalPaneWorkScheduler();
    final TerminalProductConfigurationAuthority configurationAuthority =
        TerminalProductConfigurationAuthority(productConfiguration);
    final TerminalTabPresentationResolver presentationResolver =
        TerminalTabPresentationResolver(
          metadataForPane: (PaneId paneId) =>
              sessions[paneId]?.terminalScreenSet.metadata,
        );
    final _TerminalClipboard clipboard = runNativeContentAcceptance
        ? _MemoryTerminalClipboard()
        : _AppKitTerminalClipboard(application.generalPasteboard);
    final TerminalPasteConfirmationGate pasteConfirmationGate =
        TerminalPasteConfirmationGate();
    final Stopwatch pasteClock = Stopwatch()..start();
    final Completer<void> closed = Completer<void>();
    final _TerminalProductPerformanceObservation? performanceObservation =
        runPerformanceAcceptance
        ? _TerminalProductPerformanceObservation()
        : null;
    var diagnosticsExportSelectionIndex = 0;
    var diagnosticsOverlayGeneration = 0;
    if (runDiagnosticsAcceptance && diagnosticsExportDirectory == null) {
      throw StateError(
        'diagnostics acceptance requires an isolated export directory',
      );
    }
    TerminalNativeHierarchyAdapter? hierarchy;
    TerminalContextDockState? contextDockState;
    TerminalContextDockProcessController? contextDockProcessController;
    TerminalContextDockDirectoryController? contextDockDirectoryController;
    TerminalContextDockDirectoryPresenter? contextDockPresenter;
    TerminalContextDockActionCoordinator? contextDockActionCoordinator;
    TerminalContextDockKeyController? contextDockKeyController;
    TerminalContextDockPathHandoffController? contextDockPathHandoffController;
    TerminalNativeSplitDividerGestureController? dividerGestureController;
    TerminalSystemRecoveryController? systemRecoveryController;
    TerminalMemoryPressureController? memoryPressureController;
    TerminalQuickTerminalController? quickTerminalController;
    TerminalSecureKeyboardEntryController? secureKeyboardEntryController;
    TerminalProductHierarchyActionCoordinator? actionCoordinator;
    TerminalAppKitMenuProjection? menuProjection;
    TerminalCommandPalettePresenter? palettePresenter;
    TerminalSettingsInspectorPresenter? settingsPresenter;
    TerminalDiagnosticsPresenter? diagnosticsPresenter;
    TerminalIncidentPresenter? incidentPresenter;
    TerminalUpdatePresenter? updatePresenter;
    TerminalOsc52ConfirmationPresenter? osc52Presenter;
    TerminalActionDispatchScheduler? keyBindingActionScheduler;
    TerminalActionDispatcher? actionDispatcher;
    TerminalExternalPasteController<PaneId>? externalPasteController;
    TerminalAppleScriptMacosNativePort? appleScriptNativePort;
    TerminalAppleScriptProductSession? appleScriptSession;
    TerminalAppIntentsProductController? appIntentsController;
    Timer? appIntentsPollTimer;
    Future<void> Function(PaneId? paneId)? closePaneRequest;
    Future<void> Function(PaneId paneId, TerminalExternalContent content)?
    externalContentRequest;
    void Function(PaneId paneId, TerminalNativeContentCell cell)?
    quickLookRequest;
    void Function(PaneId paneId)? nativeContentReconcileRequest;
    void Function()? reconcileRequest;
    void Function()? secureReconcileRequest;
    RuntimeLifecycleCoordinator? lifecycle;
    StreamSubscription<AppKitEvent>? applicationSubscription;
    TerminalApplicationThemeProjection<PaneId>? applicationThemeProjection;
    TerminalApplicationAccessibilityProjection?
    applicationAccessibilityProjection;
    final Set<PaneId> deferredExitPaneIds = <PaneId>{};
    final List<TerminalActionId> nativeActionInvocations = <TerminalActionId>[];
    final List<TerminalActionDispatchResult> actionDispatches =
        <TerminalActionDispatchResult>[];
    final List<TerminalConfigReloadResult> configurationReloads =
        <TerminalConfigReloadResult>[];
    final _TerminalUpdateAcceptanceService? updateAcceptanceService =
        runUserActionAcceptance ? _TerminalUpdateAcceptanceService() : null;
    final TerminalUpdateController updateController = TerminalUpdateController(
      service: updateAcceptanceService ?? updateService,
    );
    final _TerminalIncidentAcceptanceContext? incidentAcceptance =
        runDiagnosticsAcceptance
        ? _TerminalIncidentAcceptanceContext.create(
            Directory(diagnosticsExportDirectory!),
          )
        : null;
    final TerminalIncidentController incidentController =
        TerminalIncidentController(
          service: incidentAcceptance?.service ?? incidentService,
        );
    final Map<PaneId, TerminalKeyRouteResult> lastKeyRoutes =
        <PaneId, TerminalKeyRouteResult>{};
    final Map<PaneId, int> keyRouteCounts = <PaneId, int>{};
    final Map<PaneId, int> nativeContentWriteEnqueuedCounts = <PaneId, int>{};
    final List<TerminalExternalPasteResult> nativeContentPasteResults =
        <TerminalExternalPasteResult>[];
    final List<TerminalContextDockPathHandoffResult>
    contextDockPathHandoffResults = <TerminalContextDockPathHandoffResult>[];
    final List<String> nativeContentQuickLookTexts = <String>[];
    var terminalInputDeliveryCount = 0;
    var configurationEndOfFileActionCount = 0;
    var lifecycleWasShutDown = false;
    var hierarchyReconciliationInProgress = false;
    Future<void> folderServiceQueue = Future<void>.value();
    Future<void>? productResourceDisposalFuture;
    Object? asynchronousError;
    StackTrace? asynchronousStackTrace;

    void recordAsynchronousError(Object error, StackTrace stackTrace) {
      asynchronousError ??= error;
      asynchronousStackTrace ??= stackTrace;
      if (!closed.isCompleted) closed.completeError(error, stackTrace);
    }

    final TerminalOsc52Coordinator osc52Coordinator = TerminalOsc52Coordinator(
      clipboard:
          osc52Clipboard ??
          _AppKitTerminalOsc52Clipboard(application.generalPasteboard),
      applicationActive: application.isActive,
      onPendingChanged: (TerminalOsc52PendingRequest? pending) {
        final TerminalOsc52ConfirmationPresenter? presenter = osc52Presenter;
        if (presenter != null && !presenter.isDisposed) {
          final Future<void> operation = pending == null
              ? presenter.dismiss()
              : presenter.show(pending);
          unawaited(
            operation.then<void>((_) {}, onError: recordAsynchronousError),
          );
        }
        final TerminalAppKitMenuProjection? menu = menuProjection;
        if (menu != null && !menu.isDisposed) menu.refresh();
        final TerminalCommandPalettePresenter? palette = palettePresenter;
        if (palette != null && !palette.isDisposed) palette.refresh();
        diagnosticsPresenter?.refresh();
      },
    );

    late final TerminalDesktopSignalCoordinator desktopSignalCoordinator;
    late final Future<bool> Function(TerminalSessionId sessionId)
    focusNotificationSession;
    final _TerminalNotificationAcceptancePlatformPort?
    notificationAcceptancePlatform = runSystemAutomationAcceptance
        ? _TerminalNotificationAcceptancePlatformPort()
        : null;
    final TerminalNotificationProductController notificationController =
        TerminalNotificationProductController(
          platform:
              notificationAcceptancePlatform ??
              TerminalAppKitUserNotificationPlatformPort(application),
          focusSession: (TerminalSessionId sessionId) =>
              focusNotificationSession(sessionId),
          onStatusChanged: () {
            final TerminalSettingsInspectorPresenter? settings =
                settingsPresenter;
            if (settings != null && !settings.isDisposed) settings.refresh();
            diagnosticsPresenter?.refresh();
          },
          onError: (Object error, StackTrace _) {
            stderr.writeln(
              'TERMINAL_NOTIFICATION_PRODUCT_ERROR type=${error.runtimeType}',
            );
          },
          onDeliveryFailure: (String identifier) => desktopSignalCoordinator
              .reportNotificationDeliveryFailure(identifier),
        );

    final _TerminalDesktopSignalAcceptanceNativePort?
    desktopSignalAcceptancePort = runDesktopSignalAcceptance
        ? _TerminalDesktopSignalAcceptanceNativePort(application)
        : null;
    final _TerminalDesktopSignalAcceptanceClock? desktopSignalAcceptanceClock =
        runDesktopSignalAcceptance
        ? _TerminalDesktopSignalAcceptanceClock()
        : null;
    desktopSignalCoordinator = TerminalDesktopSignalCoordinator(
      nativePort: desktopSignalAcceptancePort ?? notificationController,
      monotonicMicros: desktopSignalAcceptanceClock?.call,
      applicationActive: application.isActive,
      notificationsEnabled: false,
    );

    void applyNotificationConfiguration(bool enabled) {
      if (enabled) {
        notificationController.applyEnabled(true);
        desktopSignalCoordinator.setNotificationsEnabled(true);
      } else {
        desktopSignalCoordinator.setNotificationsEnabled(false);
        notificationController.applyEnabled(false);
      }
    }

    String? inheritedWorkingDirectory(
      PaneId? sourcePaneId,
      TerminalProductConfiguration configuration,
    ) {
      final String? configured = configuration.workingDirectory;
      if (configured != null) return configured;
      if (sourcePaneId == null) return initialWorkingDirectory;
      return presentationResolver.inheritedWorkingDirectoryForPane(
            sourcePaneId,
          ) ??
          launchWorkingDirectories[sourcePaneId] ??
          initialWorkingDirectory;
    }

    TerminalPaneConfiguration configuration(
      PaneId? sourcePaneId, {
      String? workingDirectoryOverride,
    }) {
      final TerminalProductConfiguration capturedConfiguration =
          configurationAuthority.newSessionConfiguration;
      final String? workingDirectory =
          workingDirectoryOverride ??
          inheritedWorkingDirectory(sourcePaneId, capturedConfiguration);
      PaneId? paneId;
      return TerminalPaneConfiguration(
        sessionFactory:
            (
              TerminalSessionId id, {
              required void Function() onChanged,
              required void Function() onTerminated,
            }) {
              paneId = id.paneId;
              paneConfigurations[id.paneId] = capturedConfiguration;
              final bool usesDeterministicShell =
                  runUserActionAcceptance ||
                  runConfigurationAcceptance ||
                  runThemeAcceptance ||
                  runDesktopSignalAcceptance ||
                  runOsc52Acceptance ||
                  runNativeContentAcceptance ||
                  runQuickTerminalAcceptance ||
                  runSecureKeyboardEntryAcceptance ||
                  runAppleScriptAcceptance ||
                  runSystemAutomationAcceptance ||
                  runDiagnosticsAcceptance ||
                  runPerformanceAcceptance;
              final Map<String, String> shellEnvironment =
                  usesDeterministicShell
                  ? <String, String>{
                      ...terminfoEnvironment.environment,
                      'TERM': 'xterm-256color',
                      'LC_ALL': 'C',
                      'PS1': acceptancePrompt,
                      'RPS1': '',
                    }
                  : terminfoEnvironment.environment;
              final TerminalShellLaunchPlan shellLaunchPlan =
                  shellIntegrationBundle.createLaunchPlan(
                    executable: capturedConfiguration.shellExecutable,
                    arguments: usesDeterministicShell
                        ? const <String>['-f']
                        : const <String>[],
                    environment: shellEnvironment,
                    policy: capturedConfiguration.shellIntegration,
                  );
              stdout.writeln(shellLaunchPlan.machineLine());
              final TerminalApplicationThemeProjection<PaneId> themeProjection =
                  applicationThemeProjection!;
              final TerminalThemeBrightness renderedBrightness =
                  capturedConfiguration.resolveThemeBrightness(
                    themeProjection.systemAppearance,
                  );
              final TerminalPalette palette = themeProjection
                  .createPaletteForPane(
                    key: id.paneId,
                    configuration: capturedConfiguration,
                    onChanged: () => owners[id.paneId]?.notifyScreenChanged(),
                    onAppearanceChanged: (TerminalThemeBrightness brightness) {
                      sessions[id.paneId]?.projectColorScheme(
                        _terminalColorScheme(brightness),
                      );
                    },
                  );
              final TerminalSession session = TerminalSession(
                id: id,
                ptyBackend: ptyBackend,
                initialWorkingDirectory: workingDirectory,
                shellLaunchPlan: shellLaunchPlan,
                onChanged: onChanged,
                onTerminated: onTerminated,
                lifecycleObserver:
                    (TerminalSessionLifecycleObservation observation) {
                      if (runConfigurationAcceptance &&
                          observation.stage ==
                              TerminalSessionLifecycleStage.eofRequested) {
                        configurationEndOfFileActionCount++;
                      }
                      stdout.writeln(observation.machineLine());
                    },
                nativeObserver: (TerminalSessionNativeObservation observation) {
                  if ((runNativeContentAcceptance ||
                          runUserActionAcceptance ||
                          runConfigurationAcceptance) &&
                      observation.event.stage ==
                          PtyDiagnosticStage.writeEnqueued) {
                    nativeContentWriteEnqueuedCounts.update(
                      id.paneId,
                      (int count) => count + 1,
                      ifAbsent: () => 1,
                    );
                  }
                  stdout.writeln(observation.machineLine());
                },
                palette: palette,
                scrollback: capturedConfiguration.createScrollback(),
                initialCursorShape: capturedConfiguration.terminalCursorShape,
                initialCursorBlinking: capturedConfiguration.cursorBlink,
                initialColorScheme: _terminalColorScheme(renderedBrightness),
                graphicsWorker: lifecycle,
                desktopSignalCoordinator: desktopSignalCoordinator,
                osc52Coordinator: osc52Coordinator,
                clipboardReadPolicy: capturedConfiguration.clipboardRead,
                clipboardWritePolicy: capturedConfiguration.clipboardWrite,
              );
              sessions[id.paneId] = session;
              allSessions.add(session);
              launchWorkingDirectories[id.paneId] = workingDirectory;
              return session;
            },
        onChanged: () {
          final PaneId? id = paneId;
          if (id == null) return;
          quickLookCells.remove(id);
          secureReconcileRequest?.call();
          owners[id]?.notifyScreenChanged();
          selections[id]?.synchronize();
          nativeContentReconcileRequest?.call(id);
          final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
          if (nativeHierarchy != null &&
              !nativeHierarchy.isDisposed &&
              !hierarchyReconciliationInProgress) {
            nativeHierarchy.refreshPresentation();
          }
          contextDockProcessController?.scheduleSynchronize();
          contextDockDirectoryController?.scheduleSynchronize();
          appleScriptSession?.scheduleReconcile();
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
          final TerminalCommandPalettePresenter? palette = palettePresenter;
          if (palette != null && !palette.isDisposed) palette.refresh();
          diagnosticsPresenter?.refresh();
        },
        onExitRequested: () {
          final PaneId? id = paneId;
          if (id == null || state.paneForId(id) == null) return;
          final Future<void> Function(PaneId? paneId)? request =
              closePaneRequest;
          if (request == null) {
            deferredExitPaneIds.add(id);
          } else {
            unawaited(
              request(id).then<void>((_) {}, onError: recordAsynchronousError),
            );
          }
        },
        lifecycleObserver: (TerminalPaneLifecycleObservation observation) {
          stdout.writeln(observation.machineLine());
        },
        exitObserver: (TerminalPaneExitObservation observation) {
          stdout.writeln(observation.machineLine());
        },
      );
    }

    TerminalNativePaneResources createResources(TerminalPane pane) {
      if (runUserActionAcceptance) {
        stdout.writeln(
          'TERMINAL_USER_ACTIONS_STAGE stage=pane-resource-start '
          'pane=${pane.id.value}',
        );
      }
      final TerminalSession session = sessions[pane.id]!;
      final TerminalProductConfiguration paneConfiguration =
          paneConfigurations[pane.id]!;
      final View view = TerminalRendererMacos.createView();
      if (runUserActionAcceptance) {
        stdout.writeln(
          'TERMINAL_USER_ACTIONS_STAGE stage=pane-view-created '
          'pane=${pane.id.value}',
        );
      }
      final TerminalTextInputClient client = TerminalTextInputClient.attach(
        view,
      );
      if (runUserActionAcceptance) {
        stdout.writeln(
          'TERMINAL_USER_ACTIONS_STAGE stage=pane-text-input-attached '
          'pane=${pane.id.value}',
        );
      }
      late final _TerminalHierarchyProductPane owner;
      final TerminalLiveMetalSurface surface = TerminalLiveMetalSurface.attach(
        sessionId: pane.sessionId,
        screenSet: session.terminalScreenSet,
        view: view,
        logicalWidth: paneConfiguration.windowWidth,
        logicalHeight: paneConfiguration.windowHeight,
        isVisible: false,
        isOccluded: true,
        paneWorkScheduler: paneWorkScheduler,
        fontFamily: paneConfiguration.fontFamily,
        fontPointSize: paneConfiguration.fontSize,
        syntheticStylePolicy: paneConfiguration.terminalSyntheticStylePolicy,
        fontCatalogConfiguration: paneConfiguration.fontCatalogConfiguration,
        horizontalPadding: paneConfiguration.windowPaddingHorizontal,
        verticalPadding: paneConfiguration.windowPaddingVertical,
        backgroundOpacity:
            configurationAuthority.newSessionConfiguration.backgroundOpacity,
        isPaneActive: false,
        accessibilityPresentation:
            applicationAccessibilityProjection!.presentation,
        onCaretGeometryChanged: (TerminalCaretRect rectangle) {
          client.publishCaretRect(
            x: rectangle.x,
            y: rectangle.y,
            width: rectangle.width,
            height: rectangle.height,
          );
        },
        onFatalError: recordAsynchronousError,
        onFrameAttempt: performanceObservation?.recordFrameAttempt,
      );
      if (runUserActionAcceptance) {
        stdout.writeln(
          'TERMINAL_USER_ACTIONS_STAGE stage=pane-metal-attached '
          'pane=${pane.id.value}',
        );
      }
      final TerminalKeyEventRouter keyRouter = TerminalKeyEventRouter(
        configurationAuthority: configurationAuthority,
        onApplicationAction: (TerminalActionId action) {
          keyBindingActionScheduler?.schedule(action);
        },
      );
      final TerminalTextInputEventRouter textRouter =
          TerminalTextInputEventRouter(
            clientId: client.clientId,
            onRawKeyDown: (TerminalKeyEvent event) {
              if (runUserActionAcceptance ||
                  runConfigurationAcceptance ||
                  runOsc52Acceptance ||
                  runDiagnosticsAcceptance) {
                terminalInputDeliveryCount++;
              }
              state.focusPane(state.locationForPane(pane.id)!.tabId, pane.id);
              reconcileRequest?.call();
              final TerminalKeyRouteResult route = keyRouter
                  .handleTerminalKeyEvent(event, pane);
              lastKeyRoutes[pane.id] = route;
              performanceObservation?.recordInputAdmission(route);
              keyRouteCounts.update(
                pane.id,
                (int count) => count + 1,
                ifAbsent: () => 1,
              );
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
            onCommit: (String text) {
              if (runUserActionAcceptance ||
                  runConfigurationAcceptance ||
                  runOsc52Acceptance ||
                  runDiagnosticsAcceptance) {
                terminalInputDeliveryCount++;
              }
              state.focusPane(state.locationForPane(pane.id)!.tabId, pane.id);
              reconcileRequest?.call();
              pane.insertText(text);
            },
            onOverflow: (int clientId, int generation) {
              stdout.writeln(
                'TERMINAL_TEXT_INPUT_OVERFLOW client_id=$clientId '
                'generation=$generation reset=true',
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
        horizontalPadding: paneConfiguration.windowPaddingHorizontal,
        verticalPadding: paneConfiguration.windowPaddingVertical,
        onTextInputError: recordAsynchronousError,
      );
      owners[pane.id] = owner;
      if (runUserActionAcceptance) {
        stdout.writeln(
          'TERMINAL_USER_ACTIONS_STAGE stage=pane-resource-ready '
          'pane=${pane.id.value}',
        );
      }
      selections[pane.id] = _TerminalSelectionProductOwner(
        gesture: TerminalSelectionGestureController(
          viewport: session.terminalScreenSet.viewport,
        ),
        screens: session.terminalScreenSet,
        surface: surface,
        onPromptCursorInput: pane.sendInput,
      );
      owner
        ..addNativeContentSubscription(
          view.onQuickLookRequested.listen((ViewQuickLookRequestedEvent event) {
            if (!identical(owners[pane.id], owner)) return;
            final TerminalPaneLayoutRect? layout = owner.layout;
            final TerminalPaneLayoutRect? content = owner.contentLayout;
            if (layout == null || content == null) return;
            final TerminalScreen screen =
                session.terminalScreenSet.activeScreen;
            final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
            final TerminalNativeContentCell? cell =
                TerminalNativeContentPolicy.cellAtPoint(
                  x: event.x,
                  y: event.y,
                  contentOriginX: content.left - layout.left,
                  contentOriginY: content.top - layout.top,
                  cellWidth: metrics.cellWidth,
                  cellHeight: metrics.cellHeight,
                  rows: screen.rows,
                  columns: screen.columns,
                );
            if (cell != null) quickLookRequest?.call(pane.id, cell);
          }, onError: recordAsynchronousError),
        )
        ..addNativeContentSubscription(
          view.onServicesTextReceived.listen((
            ViewServicesTextReceivedEvent event,
          ) {
            if (!identical(owners[pane.id], owner)) return;
            final TerminalExternalContentResult result =
                TerminalExternalContentAdmission.text(
                  event.text,
                  source: TerminalExternalTextSource.service,
                );
            final TerminalExternalContent? content = result.content;
            final Future<void> Function(
              PaneId paneId,
              TerminalExternalContent content,
            )?
            request = externalContentRequest;
            if (content != null && request != null) {
              unawaited(
                request(
                  pane.id,
                  content,
                ).then<void>((_) {}, onError: recordAsynchronousError),
              );
            }
          }, onError: recordAsynchronousError),
        )
        ..addNativeContentSubscription(
          view.onDropPerformed.listen((ViewDropPerformedEvent event) {
            if (!identical(owners[pane.id], owner)) return;
            final TerminalExternalContentResult result =
                switch (event.content) {
                  DroppedPlainText(:final text) =>
                    TerminalExternalContentAdmission.text(
                      text,
                      source: TerminalExternalTextSource.drop,
                    ),
                  DroppedFileUrls(:final fileUrls) => () {
                    final List<String> paths = <String>[];
                    for (final Uri fileUrl in fileUrls) {
                      final String? path =
                          TerminalNativeContentPolicy.localFilePath(fileUrl);
                      if (path == null) {
                        return const TerminalExternalContentResult.rejected(
                          TerminalExternalContentDisposition.invalidPath,
                        );
                      }
                      paths.add(path);
                    }
                    return TerminalExternalContentAdmission.filePaths(paths);
                  }(),
                };
            final TerminalExternalContent? content = result.content;
            final Future<void> Function(
              PaneId paneId,
              TerminalExternalContent content,
            )?
            request = externalContentRequest;
            if (content != null && request != null) {
              unawaited(
                request(
                  pane.id,
                  content,
                ).then<void>((_) {}, onError: recordAsynchronousError),
              );
            }
          }, onError: recordAsynchronousError),
        );
      nativeContentReconcileRequest?.call(pane.id);
      mouseRouters[pane.id] = TerminalMouseRouter(
        onTerminalReport: pane.sendInput,
        onLocalSelection: (TerminalLocalSelectionIntent intent) {
          selections[pane.id]?.handle(intent);
        },
      );
      scrollRouters[pane.id] = TerminalScrollRouter(
        onTerminalReport: pane.sendInput,
        onLocalScroll: (int rows) {
          final TerminalViewport viewport = session.terminalScreenSet.viewport;
          viewport.scrollByRows(rows);
          selections[pane.id]?.synchronize();
          surface.notifyViewportChanged();
        },
        onAlternateScreenInput: pane.sendInput,
      );
      focusReporters[pane.id] = TerminalFocusReporter(
        onTerminalReport: pane.sendInput,
      );
      hyperlinkControllers[pane.id] = TerminalHyperlinkInteractionController(
        viewport: session.terminalScreenSet.viewport,
        onHoverCell: (int row, int column) {
          surface.updateHyperlinkHover(row: row, column: column);
        },
        onClearHover: surface.clearHyperlinkHover,
        onOpen: (AllowedExternalUrl target) {
          try {
            return application.openExternalUrl(target);
          } on Object {
            return false;
          }
        },
        onNotice: pane.showHyperlinkNotice,
      );
      return TerminalNativePaneResources(
        paneId: pane.id,
        view: view,
        onLayout: owner.applyLayout,
        onBackingScale: owner.updateBackingScale,
        onDisposeAdapters: () {
          secureReconcileRequest?.call();
          applicationThemeProjection?.removePane(pane.id);
          selections.remove(pane.id)?.dispose();
          mouseRouters.remove(pane.id);
          scrollRouters.remove(pane.id);
          focusReporters.remove(pane.id);
          hyperlinkControllers.remove(pane.id)?.cancelPress();
          quickLookCells.remove(pane.id);
          nativeContextGestures.clear();
          owner.disposeAdapters();
          owners.remove(pane.id);
          final TerminalSession? removedSession = sessions.remove(pane.id);
          if (removedSession != null) {
            desktopSignalCoordinator.removeSession(removedSession.id);
          }
          launchWorkingDirectories.remove(pane.id);
          paneConfigurations.remove(pane.id);
        },
      );
    }

    TerminalPane? activePane() {
      final PaneId? paneId = state.activeWindow?.selectedTab.focusedPaneId;
      return paneId == null ? null : state.paneForId(paneId);
    }

    bool contextDockCanObservePane(PaneId paneId) {
      final TerminalPane? pane = state.paneForId(paneId);
      if (pane == null || !pane.isLive) return false;
      return TerminalContextDockPrivacyPolicy.canObserve(
        paneId: paneId,
        process: pane.processSnapshot(),
        secureInput: secureKeyboardEntryController?.status,
      );
    }

    bool contextDockCanObserveProcess(
      PaneId paneId,
      TerminalPaneProcessSnapshot process,
    ) => TerminalContextDockPrivacyPolicy.canObserveProcess(process);

    bool contextDockCanObserveDirectoryPane(PaneId paneId) =>
        contextDockCanObservePane(paneId) &&
        (contextDockProcessController?.canObserveDirectoryPane(paneId) ?? true);

    TerminalContextDockPathTarget? contextDockPathTarget(
      TerminalWindowId windowId,
      PaneId paneId,
    ) {
      final TerminalWindowState? window = state.activeWindow;
      final TerminalPane? pane = state.paneForId(paneId);
      final TerminalSession? session = sessions[paneId];
      final TerminalContextDockDirectorySnapshot? directory =
          contextDockDirectoryController?.snapshotForWindow(windowId);
      if (window == null ||
          window.id != windowId ||
          window.role != TerminalWindowRole.standard ||
          window.selectedTab.focusedPaneId != paneId ||
          pane == null ||
          !pane.isLive ||
          session == null ||
          !owners.containsKey(paneId)) {
        return null;
      }
      final TerminalPaneProcessSnapshot process = pane.processSnapshot();
      return TerminalContextDockPathTarget(
        paneId: paneId,
        identity: pane,
        isLocal:
            directory?.workingDirectory != null &&
            directory?.status !=
                TerminalContextDockDirectoryStatus.remoteUnavailable,
        secureInputActive: !contextDockCanObservePane(paneId),
        usingAlternateScreen: session.terminalScreenSet.usingAlternate,
        processDisposition: process.disposition,
      );
    }

    TerminalSecureKeyboardEntryTarget? activeSecureKeyboardEntryTarget() {
      final TerminalWindowState? logicalWindow = state.activeWindow;
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      if (logicalWindow == null ||
          nativeHierarchy == null ||
          nativeHierarchy.isDisposed) {
        return null;
      }
      final TerminalTabState tab = logicalWindow.selectedTab;
      final PaneId paneId = tab.focusedPaneId;
      final Window? window = nativeHierarchy.windowForTab(tab.id);
      final TerminalPane? pane = state.paneForId(paneId);
      final _TerminalHierarchyProductPane? owner = owners[paneId];
      if (window == null || pane == null || owner == null) return null;
      final TerminalPaneProcessSnapshot process = pane.processSnapshot();
      return TerminalSecureKeyboardEntryTarget(
        identity: paneId,
        isFocused: window.isFocused && window.isVisible,
        isLive: pane.isLive,
        terminalEchoEnabled: process.terminalEchoEnabled,
        setIndicator: (TerminalSecureKeyboardEntryIndicator indicator) {
          owner.view.badge = appKitSecureInputBadge(
            indicator,
            localization: localization,
          );
        },
      );
    }

    void reconcileSecureKeyboardEntry() {
      final TerminalSecureKeyboardEntryController? controller =
          secureKeyboardEntryController;
      if (controller == null || controller.isDisposed) return;
      controller.reconcile(activeSecureKeyboardEntryTarget());
    }

    secureReconcileRequest = reconcileSecureKeyboardEntry;

    void enforceContextDockPrivacy() {
      final TerminalWindowState? window = state.activeWindow;
      final TerminalContextDockState? dock = contextDockState;
      final TerminalContextDockDirectoryPresenter? presenter =
          contextDockPresenter;
      if (window == null || dock == null || presenter == null) return;
      final TerminalContextDockWindowSnapshot? snapshot = dock
          .snapshotForWindow(window.id);
      if (snapshot == null ||
          !snapshot.navigatorOwnsInput ||
          contextDockCanObservePane(snapshot.targetPaneId)) {
        return;
      }
      final TerminalContextDockFocusRequest request =
          TerminalContextDockFocusRequest(
            windowId: snapshot.windowId,
            paneId: snapshot.targetPaneId,
            stateGeneration: snapshot.generation,
            querySelectionGeneration: snapshot.pane.querySelectionGeneration,
          );
      presenter.focusTerminal(request);
      dock.focusTerminal(snapshot.windowId, snapshot.targetPaneId);
    }

    _TerminalSelectionProductOwner? activeSelection() {
      final PaneId? paneId = state.activeWindow?.selectedTab.focusedPaneId;
      return paneId == null ? null : selections[paneId];
    }

    TerminalViewport? activeViewport() {
      final PaneId? paneId = state.activeWindow?.selectedTab.focusedPaneId;
      return paneId == null
          ? null
          : sessions[paneId]?.terminalScreenSet.viewport;
    }

    bool focusNativeContentPane(PaneId paneId) {
      final TerminalPaneLocation? location = state.locationForPane(paneId);
      final TerminalPane? pane = state.paneForId(paneId);
      if (location == null ||
          pane == null ||
          !pane.isLive ||
          !owners.containsKey(paneId)) {
        return false;
      }
      state
        ..activateWindow(location.windowId)
        ..selectTab(location.windowId, location.tabId)
        ..focusPane(location.tabId, paneId);
      reconcileRequest?.call();
      return identical(activePane(), pane);
    }

    bool presentQuickLook(PaneId paneId, TerminalNativeContentCell cell) {
      if (!focusNativeContentPane(paneId)) return false;
      final _TerminalHierarchyProductPane? owner = owners[paneId];
      final TerminalPaneLayoutRect? layout = owner?.layout;
      final TerminalPaneLayoutRect? content = owner?.contentLayout;
      final TerminalSession? session = sessions[paneId];
      if (owner == null ||
          layout == null ||
          content == null ||
          session == null ||
          owner.view.isDisposed) {
        return false;
      }
      final TerminalViewport viewport = session.terminalScreenSet.viewport;
      final TerminalWordLookupResult lookup = TerminalWordLookup.atCell(
        viewport,
        cell.row,
        cell.column,
      );
      final TerminalWordCandidate? candidate = lookup.candidate;
      if (candidate == null ||
          !TerminalWordLookup.revalidate(viewport, candidate).isAvailable) {
        return false;
      }
      final TerminalFontCatalogMetrics metrics = owner.surface.fontMetrics;
      final TerminalDefinitionPlacement? placement =
          TerminalNativeContentPolicy.definitionPlacement(
            candidate: candidate,
            contentOriginX: content.left - layout.left,
            contentOriginY: content.top - layout.top,
            cellWidth: metrics.cellWidth,
            cellHeight: metrics.cellHeight,
            fontBaseline: metrics.baseline,
          );
      if (placement == null) return false;
      final String fontFamily = owner.surface.fontFamily;
      final TextViewFont font = fontFamily.isEmpty
          ? TextViewFont.monospacedSystem(size: metrics.pointSize)
          : TextViewFont.named(fontFamily, size: metrics.pointSize);
      owner.view.showDefinition(
        DefinitionPresentation(
          text: candidate.text,
          baselineX: placement.baselineX,
          baselineY: placement.baselineY,
          font: font,
        ),
      );
      if (runNativeContentAcceptance) {
        nativeContentQuickLookTexts.add(candidate.text);
      }
      return true;
    }

    TerminalNativeContentCell? quickLookCellForPane(PaneId paneId) {
      final TerminalSession? session = sessions[paneId];
      if (session == null || !session.isLive) return null;
      final TerminalViewport viewport = session.terminalScreenSet.viewport;
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      final TerminalNativeContentCell? cell =
          quickLookCells[paneId] ??
          TerminalNativeContentPolicy.cursorCell(
            viewport: viewport,
            cursorRow: screen.cursorRow,
            cursorColumn: screen.cursorColumn,
          );
      if (cell == null) return null;
      return TerminalWordLookup.atCell(
            viewport,
            cell.row,
            cell.column,
          ).isAvailable
          ? cell
          : null;
    }

    void synchronizeNativeContentPane(PaneId paneId) {
      final _TerminalHierarchyProductPane? owner = owners[paneId];
      final TerminalSession? session = sessions[paneId];
      final TerminalPane? pane = state.paneForId(paneId);
      if (owner == null ||
          session == null ||
          pane == null ||
          owner.view.isDisposed) {
        return;
      }
      final bool live = pane.isLive;
      final _TerminalSelectionProductOwner? selection = selections[paneId];
      final int selectionGeneration =
          selection?.gesture.snapshot.generation ?? 0;
      owner.view
        ..quickLookRequestsEnabled = live
        ..dropDestination = live ? const DropDestinationConfiguration() : null;
      owner.synchronizeServicesRequestor(
        live: live,
        selectionGeneration: selectionGeneration,
        viewportGeneration: session.terminalScreenSet.viewport.generation,
        selectionText: () => TerminalNativeContentPolicy.servicesSelection(
          selection?.selectedText(),
        ),
      );
      final TerminalActionDispatcher? dispatcher = actionDispatcher;
      if (dispatcher != null && owner.contextMenu == null) {
        owner.contextMenu = TerminalAppKitContextMenuProjection.install(
          view: owner.view,
          dispatcher: dispatcher,
          localization: localization,
          onWillRoute: (TerminalActionId id) {
            final TerminalNativeContentCell? contextCell =
                id == TerminalActionId.quickLook
                ? quickLookCells[paneId]
                : null;
            focusNativeContentPane(paneId);
            if (contextCell != null && owners.containsKey(paneId)) {
              quickLookCells[paneId] = contextCell;
            }
          },
          onNativeInvocation: (TerminalActionId id, _) {
            if (runNativeContentAcceptance) nativeActionInvocations.add(id);
          },
          onDispatched: (TerminalActionDispatchResult result) {
            if (runNativeContentAcceptance) actionDispatches.add(result);
            final TerminalAppKitMenuProjection? menu = menuProjection;
            if (menu != null && !menu.isDisposed) menu.refresh();
            final TerminalCommandPalettePresenter? palette = palettePresenter;
            if (palette != null && !palette.isDisposed) palette.refresh();
            if (result.disposition ==
                TerminalActionDispatchDisposition.failed) {
              recordAsynchronousError(result.error!, result.stackTrace!);
            }
          },
        );
      }
      owner.contextMenu?.setAvailable(
        TerminalNativeContentPolicy.contextMenuAvailable(
          isLive: live,
          mouseModes: session.terminalScreenSet.mouseModes,
        ),
      );
    }

    nativeContentReconcileRequest = synchronizeNativeContentPane;
    quickLookRequest = (PaneId paneId, TerminalNativeContentCell cell) {
      try {
        presentQuickLook(paneId, cell);
      } on Object catch (error, stackTrace) {
        recordAsynchronousError(error, stackTrace);
      }
    };

    void synchronizePromptNavigation(TerminalViewport viewport) {
      final PaneId? paneId = state.activeWindow?.selectedTab.focusedPaneId;
      if (paneId == null ||
          !identical(sessions[paneId]?.terminalScreenSet.viewport, viewport)) {
        return;
      }
      hyperlinkControllers[paneId]?.cancelPress();
      owners[paneId]?.surface.clearHyperlinkHover();
      selections[paneId]?.synchronize();
      owners[paneId]?.surface.notifyViewportChanged();
    }

    TerminalWindowState? windowForTab(TerminalTabId tabId) {
      for (final TerminalWindowState window in state.windows) {
        if (window.tabForId(tabId) != null) return window;
      }
      return null;
    }

    PaneId? paneAt(TerminalTabState tab, double x, double y) {
      for (final PaneId paneId in tab.paneIds) {
        final TerminalPaneLayoutRect? rectangle = owners[paneId]?.layout;
        if (rectangle != null &&
            x >= rectangle.left &&
            x < rectangle.left + rectangle.width &&
            y >= rectangle.top &&
            y < rectangle.top + rectangle.height) {
          return paneId;
        }
      }
      return null;
    }

    AppKitMouseEvent localMouseEvent(
      AppKitMouseEvent event,
      TerminalPaneLayoutRect rectangle,
    ) => AppKitMouseEvent(
      windowHandle: event.windowHandle,
      monotonicMicros: event.monotonicMicros,
      protocolVersion: event.protocolVersion,
      sourceGeneration: event.sourceGeneration,
      monotonicNanoseconds: event.monotonicNanoseconds,
      operationId: event.operationId,
      kind: event.kind,
      x: event.x - rectangle.left,
      y: event.y - rectangle.top,
      button: event.button,
      modifiers: event.modifiers,
      clickCount: event.clickCount,
    );

    AppKitScrollEvent localScrollEvent(
      AppKitScrollEvent event,
      TerminalPaneLayoutRect rectangle,
    ) => AppKitScrollEvent(
      windowHandle: event.windowHandle,
      monotonicMicros: event.monotonicMicros,
      protocolVersion: event.protocolVersion,
      sourceGeneration: event.sourceGeneration,
      monotonicNanoseconds: event.monotonicNanoseconds,
      operationId: event.operationId,
      x: event.x - rectangle.left,
      y: event.y - rectangle.top,
      scrollingDeltaX: event.scrollingDeltaX,
      scrollingDeltaY: event.scrollingDeltaY,
      hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
      phase: event.phase,
      momentumPhase: event.momentumPhase,
      directionInvertedFromDevice: event.directionInvertedFromDevice,
      modifiers: event.modifiers,
    );

    void cancelHyperlinkInteraction(TerminalTabState tab) {
      for (final PaneId paneId in tab.paneIds) {
        nativeContextGestures.cancel(tab.id);
        hyperlinkControllers[paneId]?.cancelPress();
        owners[paneId]?.surface.clearHyperlinkHover();
      }
    }

    late final void Function() synchronizeWindowSubscriptions;

    void synchronizePaneFocusPresentation() {
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      PaneId? activePaneId;
      final TerminalWindowState? logicalWindow = state.activeWindow;
      if (application.isActive &&
          nativeHierarchy != null &&
          !nativeHierarchy.isDisposed &&
          logicalWindow != null) {
        final TerminalTabState tab = logicalWindow.selectedTab;
        final Window? window = nativeHierarchy.windowForTab(tab.id);
        if (window != null &&
            !window.isDisposed &&
            !window.isClosed &&
            window.isVisible &&
            window.isFocused) {
          activePaneId = tab.focusedPaneId;
        }
      }
      for (final MapEntry<PaneId, _TerminalHierarchyProductPane> entry
          in owners.entries) {
        final TerminalLiveMetalSurface surface = entry.value.surface;
        if (!surface.isDisposed) {
          surface.updatePaneActive(entry.key == activePaneId);
        }
      }
    }

    void reconcileInteractiveHierarchy() {
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      if (nativeHierarchy == null || nativeHierarchy.isDisposed) return;
      if (hierarchyReconciliationInProgress) return;
      reconcileSecureKeyboardEntry();
      hierarchyReconciliationInProgress = true;
      try {
        contextDockState?.synchronize(state);
        contextDockProcessController?.synchronize();
        enforceContextDockPrivacy();
        contextDockDirectoryController?.synchronize();
        nativeHierarchy.reconcile();
      } finally {
        hierarchyReconciliationInProgress = false;
      }
      contextDockPresenter?.afterHierarchyReconcile();
      synchronizeWindowSubscriptions();
      synchronizePaneFocusPresentation();
      systemRecoveryController?.retryPendingDisplayRecovery();
      final PaneId? focusedPaneId =
          state.activeWindow?.selectedTab.focusedPaneId;
      desktopSignalCoordinator.focusSession(sessions[focusedPaneId]?.id);
      osc52Coordinator.focusSession(sessions[focusedPaneId]?.id);
      diagnosticsPresenter?.synchronizeFocus();
      reconcileSecureKeyboardEntry();
      appleScriptSession?.reconcile();
    }

    reconcileRequest = reconcileInteractiveHierarchy;

    void routeWindowEvent(TerminalTabId tabId, WindowEvent event) {
      final TerminalTabState? tab = state.tabForId(tabId);
      final TerminalWindowState? logicalWindow = windowForTab(tabId);
      if (tab == null || logicalWindow == null) return;
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      if (nativeHierarchy == null || nativeHierarchy.isDisposed) return;
      switch (event) {
        case WindowClosedEvent():
          dividerGestureController?.cancel(tabId);
          synchronizePaneFocusPresentation();
          final Future<void> Function(PaneId? paneId)? request =
              closePaneRequest;
          if (request != null) {
            unawaited(
              request(tab.focusedPaneId)
                  .then<void>((_) {}, onError: recordAsynchronousError),
            );
          }
        case WindowCloseRequestedEvent():
          final Window? window = nativeHierarchy.windowForTab(tabId);
          if (window != null && !window.isClosed && !window.isDisposed) {
            window.replyToCloseRequest(event, allow: false);
          }
          state
            ..activateWindow(logicalWindow.id)
            ..selectTab(logicalWindow.id, tabId);
          final Future<void> Function(PaneId? paneId)? request =
              closePaneRequest;
          if (request != null) {
            unawaited(
              request(tab.focusedPaneId)
                  .then<void>((_) {}, onError: recordAsynchronousError),
            );
          }
        case WindowResizedEvent(:final width, :final height):
          dividerGestureController?.cancel(tabId);
          cancelHyperlinkInteraction(tab);
          if (hierarchyReconciliationInProgress) return;
          hierarchyReconciliationInProgress = true;
          try {
            nativeHierarchy.resizeTab(
              tabId,
              TerminalSplitLayoutSize(width: width, height: height),
            );
          } finally {
            hierarchyReconciliationInProgress = false;
          }
        case WindowFocusChangedEvent(:final isFocused):
          if (isFocused) {
            state
              ..activateWindow(logicalWindow.id)
              ..selectTab(logicalWindow.id, tabId);
            reconcileInteractiveHierarchy();
          } else {
            dividerGestureController?.cancel(tabId);
            cancelHyperlinkInteraction(tab);
            synchronizePaneFocusPresentation();
          }
          if (logicalWindow.role == TerminalWindowRole.quickTerminal) {
            final TerminalQuickTerminalController? quick =
                quickTerminalController;
            if (quick != null && !quick.isDisposed) {
              unawaited(
                quick
                    .handleFocusChanged(isFocused: isFocused)
                    .then<void>((_) {}, onError: recordAsynchronousError),
              );
            }
          }
          final PaneId focusedPaneId = tab.focusedPaneId;
          final TerminalScreenSet screens =
              sessions[focusedPaneId]!.terminalScreenSet;
          focusReporters[focusedPaneId]?.route(
            isFocused: isFocused,
            modeEnabled: screens.focusReportingMode,
            modeGeneration: screens.focusReportingGeneration,
          );
          reconcileSecureKeyboardEntry();
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
          final TerminalCommandPalettePresenter? palette = palettePresenter;
          if (palette != null && !palette.isDisposed) palette.refresh();
        case WindowVisibilityChangedEvent(:final isVisible):
          if (!isVisible) {
            dividerGestureController?.cancel(tabId);
            cancelHyperlinkInteraction(tab);
          }
          for (final PaneId paneId in tab.paneIds) {
            final _TerminalHierarchyProductPane? owner = owners[paneId];
            owner?.surface.updateWindowState(
              isVisible: isVisible && owner.isVisible,
            );
          }
          synchronizePaneFocusPresentation();
          reconcileSecureKeyboardEntry();
        case WindowOcclusionChangedEvent(:final isOccluded):
          for (final PaneId paneId in tab.paneIds) {
            owners[paneId]?.surface.updateWindowState(isOccluded: isOccluded);
          }
        case WindowBackingScaleChangedEvent(:final backingScaleFactor):
          cancelHyperlinkInteraction(tab);
          for (final PaneId paneId in tab.paneIds) {
            final _TerminalHierarchyProductPane? owner = owners[paneId];
            final TerminalPaneLayoutRect? rectangle = owner?.layout;
            if (owner == null || rectangle == null) continue;
            owner.updateBackingScale(backingScaleFactor);
            owner.applyLayout(rectangle, visible: owner.isVisible);
          }
        case WindowScreenChangedEvent() ||
            WindowFrameChangedEvent() ||
            WindowFullscreenChangedEvent():
          cancelHyperlinkInteraction(tab);
          nativeHierarchy.handleWindowEvent(tabId, event);
        case AppKitMouseEvent():
          final TerminalNativeSplitDividerGestureController? gestures =
              dividerGestureController;
          if (gestures != null && gestures.route(tabId, event)) {
            cancelHyperlinkInteraction(tab);
            return;
          }
          PaneId paneId = paneAt(tab, event.x, event.y) ?? tab.focusedPaneId;
          final _TerminalHierarchyProductPane? owner = owners[paneId];
          final TerminalPaneLayoutRect? rectangle = owner?.layout;
          if (owner == null || rectangle == null) return;
          if (event.kind == AppKitMouseEventKind.down &&
              paneId != tab.focusedPaneId) {
            state
              ..activateWindow(logicalWindow.id)
              ..selectTab(logicalWindow.id, tabId)
              ..focusPane(tabId, paneId);
            reconcileInteractiveHierarchy();
          }
          final TerminalScreenSet contextScreens =
              sessions[paneId]!.terminalScreenSet;
          final bool startsNativeContextGesture =
              TerminalNativeContentPolicy.isContextGesture(
                isButtonDown: event.kind == AppKitMouseEventKind.down,
                button: event.button,
                control: event.modifiers.control,
              ) &&
              !contextScreens.mouseModes.reportingEnabled;
          if (nativeContextGestures.suppress(
            target: tabId,
            isButtonDown: event.kind == AppKitMouseEventKind.down,
            isButtonUp: event.kind == AppKitMouseEventKind.up,
            startsNativeContextGesture: startsNativeContextGesture,
          )) {
            if (!startsNativeContextGesture) return;
            final TerminalPaneLayoutRect? content = owner.contentLayout;
            final TerminalScreen screen = contextScreens.activeScreen;
            final TerminalFontCatalogMetrics metrics =
                owner.surface.fontMetrics;
            final TerminalNativeContentCell? cell = content == null
                ? null
                : TerminalNativeContentPolicy.cellAtPoint(
                    x: event.x,
                    y: event.y,
                    contentOriginX: content.left,
                    contentOriginY: content.top,
                    cellWidth: metrics.cellWidth,
                    cellHeight: metrics.cellHeight,
                    rows: screen.rows,
                    columns: screen.columns,
                  );
            if (cell == null) {
              quickLookCells.remove(paneId);
            } else {
              quickLookCells[paneId] = cell;
            }
            synchronizeNativeContentPane(paneId);
            return;
          }
          for (final PaneId otherPaneId in tab.paneIds) {
            if (otherPaneId != paneId) {
              owners[otherPaneId]?.surface.clearHyperlinkHover();
            }
          }
          final TerminalScreenSet screens = sessions[paneId]!.terminalScreenSet;
          final TerminalScreen screen = screens.activeScreen;
          final TerminalFontCatalogMetrics metrics = owner.surface.fontMetrics;
          final TerminalPaneLayoutRect contentRectangle = owner.contentLayout!;
          if (!_containsPoint(contentRectangle, event.x, event.y)) {
            owner.surface.clearHyperlinkHover();
            return;
          }
          final AppKitMouseEvent localized = localMouseEvent(
            event,
            contentRectangle,
          );
          final TerminalHyperlinkRouteResult hyperlinkResult =
              hyperlinkControllers[paneId]!.route(
                localized,
                rows: screen.rows,
                columns: screen.columns,
                cellWidth: metrics.cellWidth,
                cellHeight: metrics.cellHeight,
              );
          if (!hyperlinkResult.isConsumed) {
            mouseRouters[paneId]!.route(
              localized,
              modes: screens.mouseModes,
              rows: screen.rows,
              columns: screen.columns,
              cellWidth: metrics.cellWidth,
              cellHeight: metrics.cellHeight,
              backingScaleFactor:
                  nativeHierarchy.windowForTab(tabId)?.backingScaleFactor ?? 1,
            );
          }
          synchronizeNativeContentPane(paneId);
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
        case AppKitScrollEvent():
          final PaneId paneId =
              paneAt(tab, event.x, event.y) ?? tab.focusedPaneId;
          final _TerminalHierarchyProductPane? owner = owners[paneId];
          final TerminalPaneLayoutRect? rectangle = owner?.layout;
          if (owner == null || rectangle == null) return;
          cancelHyperlinkInteraction(tab);
          final TerminalScreenSet screens = sessions[paneId]!.terminalScreenSet;
          final TerminalScreen screen = screens.activeScreen;
          final TerminalFontCatalogMetrics metrics = owner.surface.fontMetrics;
          final TerminalPaneLayoutRect contentRectangle = owner.contentLayout!;
          if (!_containsPoint(contentRectangle, event.x, event.y)) return;
          scrollRouters[paneId]!.route(
            localScrollEvent(event, contentRectangle),
            mouseModes: screens.mouseModes,
            keyboardModes: screens.keyboardModes,
            usingAlternateScreen: screens.usingAlternate,
            rows: screen.rows,
            columns: screen.columns,
            cellWidth: metrics.cellWidth,
            cellHeight: metrics.cellHeight,
            backingScaleFactor:
                nativeHierarchy.windowForTab(tabId)?.backingScaleFactor ?? 1,
          );
        case AppKitKeyEvent():
          final TerminalContextDockKeyController? keys =
              contextDockKeyController;
          if (keys == null) break;
          unawaited(
            keys.handle(logicalWindow.id, event).then<void>((
              TerminalContextDockKeyResult result,
            ) {
              final TerminalContextDockTreeIntent? intent = result.treeIntent;
              if (intent != null) {
                contextDockDirectoryController?.handleTreeIntent(
                  logicalWindow.id,
                  intent,
                );
              }
              if (result.disposition ==
                  TerminalContextDockKeyDisposition.pathInsertionRequested) {
                final TerminalContextDockPathHandoffController? handoff =
                    contextDockPathHandoffController;
                if (handoff != null) {
                  unawaited(
                    handoff.insertPath(logicalWindow.id).then<void>((
                      TerminalContextDockPathHandoffResult handoffResult,
                    ) {
                      if (runNativeContentAcceptance) {
                        contextDockPathHandoffResults.add(handoffResult);
                      }
                      reconcileRequest?.call();
                    }, onError: recordAsynchronousError),
                  );
                }
              }
            }, onError: recordAsynchronousError),
          );
      }
    }

    synchronizeWindowSubscriptions = () {
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      if (nativeHierarchy == null || nativeHierarchy.isDisposed) return;
      final Set<TerminalTabId> liveTabIds = nativeHierarchy.windows.keys
          .toSet();
      for (final TerminalTabId tabId
          in windowSubscriptions.keys
              .where((TerminalTabId tabId) => !liveTabIds.contains(tabId))
              .toList(growable: false)) {
        dividerGestureController?.cancel(tabId);
        unawaited(windowSubscriptions.remove(tabId)!.cancel());
      }
      for (final MapEntry<TerminalTabId, Window> entry
          in nativeHierarchy.windows.entries) {
        windowSubscriptions.putIfAbsent(
          entry.key,
          () => entry.value.events.listen(
            (WindowEvent event) => routeWindowEvent(entry.key, event),
            onError: recordAsynchronousError,
          ),
        );
      }
    };

    Future<void> disposeProductResourcesOnce() async {
      Object? disposalError;
      StackTrace? disposalStackTrace;
      appIntentsPollTimer?.cancel();
      appIntentsPollTimer = null;
      try {
        await appIntentsController?.dispose();
      } on Object catch (error, stackTrace) {
        disposalError = error;
        disposalStackTrace = stackTrace;
      }
      if (!notificationController.isDisposed &&
          notificationController.status.enabled) {
        applyNotificationConfiguration(false);
      }
      appIntentsController = null;
      externalContentRequest = null;
      quickLookRequest = null;
      nativeContentReconcileRequest = null;
      appleScriptSession?.dispose();
      appleScriptSession = null;
      appleScriptNativePort = null;
      pasteConfirmationGate.clear();
      externalPasteController?.dispose();
      externalPasteController = null;
      if (!application.isTerminated) {
        application.folderServicesProvider = null;
      }
      await folderServiceQueue;
      final TerminalSecureKeyboardEntryController? secure =
          secureKeyboardEntryController;
      secureKeyboardEntryController = null;
      if (secure != null) {
        try {
          secure.dispose();
        } on Object catch (error, stackTrace) {
          disposalError ??= error;
          disposalStackTrace ??= stackTrace;
        }
      }
      await quickTerminalController?.dispose();
      quickTerminalController = null;
      await osc52Presenter?.dispose();
      osc52Presenter = null;
      osc52Coordinator.dispose();
      await diagnosticsPresenter?.dispose();
      diagnosticsPresenter = null;
      await incidentPresenter?.dispose();
      incidentPresenter = null;
      if (!incidentController.isDisposed) incidentController.dispose();
      incidentAcceptance?.removeFixtures();
      await updatePresenter?.dispose();
      updatePresenter = null;
      if (!updateController.isDisposed) await updateController.dispose();
      await settingsPresenter?.dispose();
      settingsPresenter = null;
      configurationReloadController?.dispose();
      await applicationAccessibilityProjection?.dispose();
      applicationAccessibilityProjection = null;
      await applicationThemeProjection?.dispose();
      for (final StreamSubscription<WindowEvent> subscription
          in windowSubscriptions.values.toList(growable: false)) {
        await subscription.cancel();
      }
      windowSubscriptions.clear();
      await palettePresenter?.dispose();
      await menuProjection?.dispose();
      actionDispatcher = null;
      contextDockKeyController = null;
      contextDockPathHandoffController?.dispose();
      contextDockPathHandoffController = null;
      contextDockActionCoordinator?.dispose();
      contextDockActionCoordinator = null;
      contextDockProcessController?.dispose();
      contextDockProcessController = null;
      contextDockDirectoryController?.dispose();
      contextDockDirectoryController = null;
      actionCoordinator?.dispose();
      memoryPressureController?.dispose();
      memoryPressureController = null;
      systemRecoveryController?.dispose();
      systemRecoveryController = null;
      dividerGestureController?.dispose();
      dividerGestureController = null;
      for (final _TerminalHierarchyProductPane owner in owners.values.toList(
        growable: false,
      )) {
        await owner.cancelTextInput();
      }
      final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
      if (nativeHierarchy != null && !nativeHierarchy.isDisposed) {
        nativeHierarchy.dispose();
      }
      contextDockPresenter?.dispose();
      contextDockPresenter = null;
      contextDockState?.dispose();
      contextDockState = null;
      for (final _TerminalHierarchyProductPane owner in owners.values) {
        if (!owner.adaptersDisposed) owner.disposeAdapters();
      }
      paneWorkScheduler.dispose();
      if (!lifecycleWasShutDown) {
        await lifecycle?.shutdown();
        lifecycleWasShutDown = true;
      }
      if (disposalError != null) {
        Error.throwWithStackTrace(disposalError, disposalStackTrace!);
      }
    }

    Future<void> disposeProductResources() =>
        productResourceDisposalFuture ??= disposeProductResourcesOnce();

    Future<void> pasteText(
      TerminalPane pane,
      String text, {
      required TerminalPasteConfirmationGate confirmationGate,
      required int sourceIdentity,
    }) async {
      final int invocationMicros = pasteClock.elapsedMicroseconds;
      TerminalPastePlan plan;
      try {
        plan = await TerminalPasteCodec.planAsync(
          text,
          bracketed: pane.bracketedPasteMode,
        );
      } on TerminalPasteLimitException {
        pane.showClipboardNotice(
          const TerminalClipboardNotice(
            TerminalClipboardNoticeKind.pasteTooLarge,
          ),
        );
        return;
      }
      if (!pane.isLive ||
          !identical(state.paneForId(pane.id), pane) ||
          !identical(activePane(), pane)) {
        return;
      }
      final TerminalPasteApprovalResult approval = confirmationGate.evaluate(
        pasteboardChangeCount: sourceIdentity,
        plan: plan,
        invocationMicros: invocationMicros,
        confirmationIssuedMicros: pasteClock.elapsedMicroseconds,
      );
      if (!approval.isApproved) {
        pane.showClipboardNotice(
          TerminalClipboardNotice(
            TerminalClipboardNoticeKind.pasteConfirmationRequired,
            analysis: approval.analysis,
          ),
        );
        return;
      }
      await pane.paste(plan);
    }

    Future<void> paste() async {
      final TerminalPane? pane = activePane();
      if (pane == null) return;
      PasteboardTextSnapshot snapshot;
      try {
        snapshot = clipboard.readText();
      } on Object {
        pane.showClipboardNotice(
          const TerminalClipboardNotice(
            TerminalClipboardNoticeKind.pasteUnavailable,
          ),
        );
        return;
      }
      final String? text = snapshot.text;
      if (text == null) {
        pane.showClipboardNotice(
          const TerminalClipboardNotice(
            TerminalClipboardNoticeKind.pasteUnavailable,
          ),
        );
        return;
      }
      await pasteText(
        pane,
        text,
        confirmationGate: pasteConfirmationGate,
        sourceIdentity: snapshot.changeCount,
      );
    }

    externalPasteController = TerminalExternalPasteController<PaneId>(
      resolveTarget: (PaneId paneId) {
        final TerminalPane? pane = state.paneForId(paneId);
        if (pane == null ||
            !pane.isLive ||
            !identical(activePane(), pane) ||
            !owners.containsKey(paneId)) {
          return null;
        }
        return TerminalExternalPasteTarget(
          identity: pane,
          bracketedPasteMode: pane.bracketedPasteMode,
          pasteInProgress: pane.pasteInProgress,
          showNotice: pane.showClipboardNotice,
          paste: pane.paste,
        );
      },
      monotonicMicros: () => pasteClock.elapsedMicroseconds,
    );
    externalContentRequest =
        (PaneId paneId, TerminalExternalContent content) async {
          if (!focusNativeContentPane(paneId)) return;
          final TerminalExternalPasteResult? result =
              await externalPasteController?.submit(paneId, content);
          if (runNativeContentAcceptance && result != null) {
            nativeContentPasteResults.add(result);
          }
        };

    Future<void> reloadConfiguration() async {
      final TerminalConfigReloadController? controller =
          configurationReloadController;
      if (controller == null) return;
      final TerminalConfigReloadResult result = await controller.reload();
      if (runConfigurationAcceptance) configurationReloads.add(result);
      for (final TerminalConfigDiagnostic diagnostic in result.diagnostics) {
        stderr.writeln(diagnostic.format());
      }
      stdout.writeln(
        result.machineLine(acceptedGeneration: controller.acceptedGeneration),
      );
      if (result.isAccepted) {
        configurationAuthority.applyReload(result);
        final TerminalProductConfiguration configuration =
            configurationAuthority.newSessionConfiguration;
        contextDockState?.configureDefaults(
          initiallyVisible: configuration.contextDockVisible,
          width: configuration.contextDockWidth,
        );
        for (final _TerminalHierarchyProductPane owner in owners.values.toList(
          growable: false,
        )) {
          if (!owner.surface.isDisposed) {
            owner.surface.updateBackgroundOpacity(
              configuration.backgroundOpacity,
            );
          }
        }
        final TerminalSecureKeyboardEntryController? secure =
            secureKeyboardEntryController;
        if (secure != null && !secure.isDisposed) {
          secure.applyConfiguration(
            automaticEnabled: configuration.macosSecureInputAuto,
            indicationEnabled: configuration.macosSecureInputIndication,
            target: activeSecureKeyboardEntryTarget(),
          );
          stdout.writeln(secure.status.machineLine());
        }
        final TerminalQuickTerminalController? quick = quickTerminalController;
        if (quick != null && !quick.isDisposed) {
          await quick.replaceShortcut(
            configurationAuthority
                .newSessionConfiguration
                .quickTerminalShortcut,
          );
          stdout.writeln(quick.shortcutStatus.machineLine());
        }
        final TerminalAppIntentsProductController? appIntents =
            appIntentsController;
        if (appIntents != null && !appIntents.isDisposed) {
          appIntents.applyEnabled(configuration.macosAppIntents);
        }
        if (!notificationController.isDisposed) {
          applyNotificationConfiguration(configuration.macosNotifications);
        }
        appleScriptSession?.applyEnabled(configuration.macosAppleScript);
      }
      settingsPresenter?.refresh();
      diagnosticsPresenter?.refresh();
      if (result.disposition == TerminalConfigReloadDisposition.failed) {
        Error.throwWithStackTrace(result.error!, result.stackTrace!);
      }
    }

    try {
      applicationThemeProjection = TerminalApplicationThemeProjection<PaneId>(
        application: application,
        onError: recordAsynchronousError,
      );
      applicationAccessibilityProjection =
          TerminalApplicationAccessibilityProjection(
            initialPreferences: application.accessibilityDisplayPreferences,
            events: application.onAccessibilityDisplayPreferencesChanged,
            onChanged: (TerminalAccessibilityPresentation presentation) {
              final TerminalQuickTerminalController? quick =
                  quickTerminalController;
              if (quick != null && !quick.isDisposed) {
                quick.updateAccessibilityPresentation(presentation);
              }
              final TerminalSettingsInspectorPresenter? settings =
                  settingsPresenter;
              if (settings != null && !settings.isDisposed) {
                settings.updateAccessibilityPresentation(presentation);
              }
              diagnosticsPresenter?.refresh();
              for (final _TerminalHierarchyProductPane owner
                  in owners.values.toList(growable: false)) {
                if (!owner.surface.isDisposed) {
                  owner.surface.updateAccessibilityPresentation(presentation);
                }
              }
            },
            onError: recordAsynchronousError,
          );
      if (runThemeAcceptance) {
        _expectLifecycle(
          application.eventProtocolVersion >= 7,
          'theme acceptance requires AppKit event protocol v7 or later',
        );
        _injectApplicationAppearanceEventForTesting(
          application,
          isDark: false,
          monotonicNanoseconds: 11900000,
        );
        _expectLifecycle(
          application.effectiveAppearance == AppKitAppearance.light &&
              applicationThemeProjection.systemAppearance ==
                  TerminalThemeBrightness.light,
          'theme acceptance could not seed initial light appearance',
        );
      }
      application.defersTerminationRequests = true;
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
        'interactive product worker did not become ready',
      );
      _writeLifecycleEvent(
        RuntimeLifecycleScenario.normal,
        'root-ready',
        createdLifecycle.generation,
      );
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);
      await _expectResponse(createdLifecycle);
      if (runUserActionAcceptance) {
        stdout.writeln('TERMINAL_USER_ACTIONS_STAGE stage=worker-ready');
      }

      final TerminalWindowState initialWindow = await state.createWindow(
        configuration(null),
      );
      final TerminalPane initialPane = state.paneForId(
        initialWindow.selectedTab.focusedPaneId,
      )!;

      final TerminalContextDockState createdContextDockState =
          TerminalContextDockState(
            initiallyVisible: configurationAuthority
                .newSessionConfiguration
                .contextDockVisible,
            initialWidth:
                configurationAuthority.newSessionConfiguration.contextDockWidth,
          )..synchronize(state);
      contextDockState = createdContextDockState;
      final TerminalContextDockProcessController createdDockProcess =
          TerminalContextDockProcessController(
            applicationState: state,
            dockState: createdContextDockState,
            resolveProcessSnapshot: (PaneId paneId) =>
                state.paneForId(paneId)?.processSnapshot() ??
                TerminalPaneProcessSnapshot.unavailable(
                  sessionId: TerminalSessionId(paneId: paneId, generation: 1),
                ),
            resolveForegroundJob: (PaneId paneId, TerminalSessionId sessionId) {
              final TerminalSession? session = sessions[paneId];
              if (session == null || session.id != sessionId) return null;
              return session.foregroundJobSnapshot();
            },
            canPresentWindow: (TerminalWindowId windowId) {
              final TerminalWindowState? logicalWindow = state.windowForId(
                windowId,
              );
              final TerminalNativeHierarchyAdapter? nativeHierarchy = hierarchy;
              if (logicalWindow == null) return false;
              if (nativeHierarchy == null || nativeHierarchy.isDisposed) {
                return true;
              }
              final Window? nativeWindow = nativeHierarchy.windowForTab(
                logicalWindow.selectedTabId,
              );
              return application.isActive &&
                  nativeWindow != null &&
                  !nativeWindow.isDisposed &&
                  !nativeWindow.isClosed &&
                  nativeWindow.isVisible &&
                  nativeWindow.isFocused;
            },
            canObserveProcess: contextDockCanObserveProcess,
            focusTerminal: (TerminalContextDockFocusRequest request) {
              final TerminalContextDockDirectoryPresenter? presenter =
                  contextDockPresenter;
              if (presenter == null || presenter.isDisposed) return false;
              try {
                presenter.focusTerminal(request);
                return true;
              } on Object {
                return false;
              }
            },
            onChanged: () {
              reconcileRequest?.call();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
            },
          );
      contextDockProcessController = createdDockProcess;
      createdDockProcess.synchronize();
      const TerminalWorkingDirectoryResolver workingDirectoryResolver =
          TerminalWorkingDirectoryResolver();
      final TerminalContextDockDirectoryController createdDockDirectory =
          TerminalContextDockDirectoryController(
            applicationState: state,
            dockState: createdContextDockState,
            resolveWorkingDirectory: (PaneId paneId, int generation) {
              final TerminalSession session =
                  sessions[paneId] ??
                  (throw StateError('Context Dock session is unavailable'));
              return workingDirectoryResolver.resolve(
                sessionId: session.id,
                generation: generation,
                processSnapshot: session.processSnapshot(),
                reportedWorkingDirectory:
                    session.terminalScreenSet.metadata.workingDirectory,
                processWorkingDirectory: session.workingDirectorySnapshot(),
                launchWorkingDirectory: session.initialWorkingDirectory,
              );
            },
            canObservePane: contextDockCanObserveDirectoryPane,
            onChanged: () {
              reconcileRequest?.call();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
            },
          );
      contextDockDirectoryController = createdDockDirectory;
      final TerminalContextDockDirectoryPresenter createdDockPresenter =
          TerminalContextDockDirectoryPresenter(
            applicationState: state,
            dockState: createdContextDockState,
            directoryController: createdDockDirectory,
            localization: localization,
            windowForTab: (TerminalTabId tabId) =>
                hierarchy?.windowForTab(tabId),
            terminalViewForPane: (PaneId paneId) =>
                hierarchy?.resourcesForPane(paneId)?.view,
            contentSnapshot: createdDockProcess.snapshotForWindow,
            pathHandoffSnapshot: (TerminalWindowId windowId) =>
                contextDockPathHandoffController?.snapshotForWindow(windowId),
          );
      contextDockPresenter = createdDockPresenter;

      final TerminalNativeHierarchyAdapter createdHierarchy =
          TerminalNativeHierarchyAdapter(
            state: state,
            paneResourcesFactory: createResources,
            windowFrame: initialWindowFrame,
            windowFrameBuilder: (TerminalWindowState window) {
              final PaneId paneId = window.selectedTab.focusedPaneId;
              final TerminalProductConfiguration configuration =
                  paneConfigurations[paneId] ??
                  configurationAuthority.newSessionConfiguration;
              return Rect.fromLTWH(
                initialWindowFrame.left,
                initialWindowFrame.top,
                configuration.windowWidth,
                configuration.windowHeight,
              );
            },
            windowConfigurationBuilder: (TerminalWindowState window) =>
                window.role == TerminalWindowRole.quickTerminal
                ? terminalQuickTerminalWindowConfiguration
                : terminalWindowConfiguration,
            automaticPresentationPolicy: (TerminalWindowState window) =>
                window.role == TerminalWindowRole.standard,
            cellSize: TerminalSplitLayoutSize(
              width: 8 + productConfiguration.windowPaddingHorizontal * 2,
              height: 16 + productConfiguration.windowPaddingVertical * 2,
            ),
            dividerThickness: 1,
            defersCloseRequests: true,
            tabLayoutSizeResolver:
                createdDockPresenter.resolveTerminalLayoutSize,
            tabRootDecorator: createdDockPresenter.decorateRoot,
            presentationBuilder:
                (TerminalWindowState window, TerminalTabState tab) =>
                    presentationResolver.resolve(
                      tab,
                      fallbackTitle: localization.applicationName,
                    ),
          );
      hierarchy = createdHierarchy;
      dividerGestureController = TerminalNativeSplitDividerGestureController(
        hierarchy: createdHierarchy,
        reconcile: reconcileInteractiveHierarchy,
      );
      systemRecoveryController = TerminalSystemRecoveryController(
        suspendPresentation: () {
          dividerGestureController?.cancelAll();
          nativeContextGestures.clear();
          for (final TerminalTabState tab in state.windows.expand(
            (TerminalWindowState window) => window.tabs,
          )) {
            cancelHyperlinkInteraction(tab);
          }
          for (final _TerminalSelectionProductOwner selection
              in selections.values) {
            selection.suspendTransientInteraction();
          }
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            if (!owner.surface.isDisposed) {
              owner.surface.updateSystemSuspended(true);
            }
          }
        },
        recoverDisplays: () {
          if (createdHierarchy.isDisposed || state.isDisposed) return true;
          if (hierarchyReconciliationInProgress ||
              createdHierarchy.nativeWindowCount != state.tabCount ||
              createdHierarchy.paneResourceCount != state.paneCount) {
            return false;
          }
          final AppKitResolvedScreen fallback = application.resolveScreen(
            AppKitScreenSelection.main,
          );
          hierarchyReconciliationInProgress = true;
          try {
            createdHierarchy.recoverDisplaySet(fallbackScreen: fallback);
          } finally {
            hierarchyReconciliationInProgress = false;
          }
          createdHierarchy.refreshPresentation();
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            owner.notifyScreenChanged();
          }
          return true;
        },
        resumePresentation: () {
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            if (!owner.surface.isDisposed) {
              owner.surface.updateSystemSuspended(false);
            }
          }
        },
        onError: recordAsynchronousError,
      );
      memoryPressureController = TerminalMemoryPressureController(
        apply: (AppKitMemoryPressureLevel level) {
          for (final _TerminalHierarchyProductPane owner
              in owners.values.toList(growable: false)) {
            if (!owner.surface.isDisposed) {
              owner.surface.shedMemoryPressure(level);
            }
          }
        },
        onError: recordAsynchronousError,
      );
      reconcileInteractiveHierarchy();
      if (runUserActionAcceptance) {
        stdout.writeln('TERMINAL_USER_ACTIONS_STAGE stage=hierarchy-projected');
      }
      await initialPane.start();
      if (runUserActionAcceptance) {
        stdout.writeln('TERMINAL_USER_ACTIONS_STAGE stage=pane-started');
      }
      late final TerminalSecureKeyboardEntryLease secureLease;
      try {
        secureLease = TerminalAppKitSecureKeyboardEntryLease();
      } on Object catch (error, stackTrace) {
        secureLease = TerminalUnavailableSecureKeyboardEntryLease(
          error,
          stackTrace,
        );
      }
      final TerminalProductConfiguration secureConfiguration =
          configurationAuthority.newSessionConfiguration;
      final TerminalSecureKeyboardEntryController createdSecureKeyboardEntry =
          TerminalSecureKeyboardEntryController(
            lease: secureLease,
            automaticEnabled: secureConfiguration.macosSecureInputAuto,
            indicationEnabled: secureConfiguration.macosSecureInputIndication,
            applicationActive: application.isActive,
            onStatusChanged: (TerminalSecureKeyboardEntryStatus status) {
              contextDockProcessController?.scheduleSynchronize();
              final TerminalSettingsInspectorPresenter? settings =
                  settingsPresenter;
              if (settings != null && !settings.isDisposed) settings.refresh();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
              diagnosticsPresenter?.refresh();
            },
            onFailure: (Object error, StackTrace stackTrace) {
              stderr.writeln(
                'TERMINAL_SECURE_KEYBOARD_ENTRY_ERROR '
                'type=${error.runtimeType}',
              );
            },
          );
      secureKeyboardEntryController = createdSecureKeyboardEntry;
      reconcileSecureKeyboardEntry();
      stdout.writeln(createdSecureKeyboardEntry.status.machineLine());
      final TerminalExternalPasteController<PaneId> contextDockPasteController =
          TerminalExternalPasteController<PaneId>(
            resolveTarget: (PaneId paneId) {
              final TerminalWindowState? window = state.activeWindow;
              if (window == null) return null;
              final TerminalContextDockPathTarget? target =
                  contextDockPathTarget(window.id, paneId);
              final TerminalPane? pane = state.paneForId(paneId);
              if (target == null ||
                  target.insertionBlock !=
                      TerminalContextDockPathInsertionBlock.none ||
                  pane == null ||
                  !identical(target.identity, pane)) {
                return null;
              }
              return TerminalExternalPasteTarget(
                identity: pane,
                bracketedPasteMode: pane.bracketedPasteMode,
                pasteInProgress: pane.pasteInProgress,
                showNotice: pane.showClipboardNotice,
                paste: pane.paste,
              );
            },
            monotonicMicros: () => pasteClock.elapsedMicroseconds,
          );
      final TerminalContextDockPathHandoffController createdPathHandoff =
          TerminalContextDockPathHandoffController(
            dockState: createdContextDockState,
            resolveSelection: createdDockDirectory.selectedPathForWindow,
            resolveTarget: contextDockPathTarget,
            writeClipboard: clipboard.writeText,
            pasteController: contextDockPasteController,
            focusTerminal: (TerminalWindowId windowId, PaneId paneId) async {
              final TerminalContextDockWindowSnapshot? dock =
                  createdContextDockState.snapshotForWindow(windowId);
              if (dock == null ||
                  dock.targetPaneId != paneId ||
                  !dock.navigatorOwnsInput) {
                return false;
              }
              final TerminalActionDispatcher? dispatcher = actionDispatcher;
              if (dispatcher == null) return false;
              final TerminalActionDispatchResult result = await dispatcher
                  .dispatch(TerminalActionId.focusTerminal);
              return result.disposition ==
                  TerminalActionDispatchDisposition.executed;
            },
            onClipboardWritten: pasteConfirmationGate.clear,
          );
      contextDockPathHandoffController = createdPathHandoff;
      osc52Presenter = TerminalOsc52ConfirmationPresenter(
        focusTarget: () {
          final TerminalWindowState? activeWindow = state.activeWindow;
          if (activeWindow == null) return null;
          final TerminalTabState tab = activeWindow.selectedTab;
          final Window? window = createdHierarchy.windowForTab(tab.id);
          final TerminalNativePaneResources? resources = createdHierarchy
              .resourcesForPane(tab.focusedPaneId);
          if (window == null || resources == null) return null;
          return TerminalOsc52ConfirmationFocusTarget(
            window: window,
            view: resources.view,
          );
        },
        approve: osc52Coordinator.approve,
        deny: osc52Coordinator.deny,
        onError: recordAsynchronousError,
        localization: localization,
      );
      final TerminalOsc52PendingRequest? startupPending =
          osc52Coordinator.pendingRequest;
      if (startupPending != null) {
        await osc52Presenter!.show(startupPending);
      }

      final TerminalPaneCloseCoordinator createdPaneCloseCoordinator =
          TerminalPaneCloseCoordinator(
            state: state,
            onBeforePaneRemoved: (PaneId paneId) async {
              await owners[paneId]?.cancelTextInput();
            },
            onHierarchyChanged: () {
              reconcileInteractiveHierarchy();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
              diagnosticsPresenter?.refresh();
            },
          );
      final TerminalProductHierarchyActionCoordinator createdActions =
          TerminalProductHierarchyActionCoordinator(
            state: state,
            configurationFactory: configuration,
            reconcile: reconcileInteractiveHierarchy,
            canMoveDivider: createdHierarchy.canMoveFocusedDivider,
            moveDivider: createdHierarchy.moveFocusedDivider,
            canFocusPane: createdHierarchy.canFocusPane,
            focusPane: createdHierarchy.focusPane,
            canMutate: () =>
                productResourceDisposalFuture == null &&
                !createdPaneCloseCoordinator.removalInProgress &&
                !createdPaneCloseCoordinator.applicationQuitInProgress,
            onChanged: () {
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
            },
          );
      actionCoordinator = createdActions;
      final TerminalContextDockActionCoordinator createdDockActions =
          TerminalContextDockActionCoordinator(
            applicationState: state,
            dockState: createdContextDockState,
            focusNavigator: createdDockPresenter.focusNavigator,
            focusTerminal: createdDockPresenter.focusTerminal,
            shouldConsumeNavigatorRequest: () =>
                createdDockPresenter.shouldConsumeNavigatorRequest,
            canFocusNavigator: () {
              final TerminalWindowState? activeWindow = state.activeWindow;
              return productResourceDisposalFuture == null &&
                  activeWindow != null &&
                  contextDockCanObservePane(
                    activeWindow.selectedTab.focusedPaneId,
                  ) &&
                  createdDockPresenter.canFocusNavigator;
            },
            onChanged: () {
              reconcileInteractiveHierarchy();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
            },
          );
      contextDockActionCoordinator = createdDockActions;
      final TerminalAppleScriptProductCommandExecutor appleScriptExecutor =
          TerminalAppleScriptProductCommandExecutor(
            state: state,
            configurationFactory: configuration,
            startPane: (PaneId paneId) async {
              final TerminalPane? pane = state.paneForId(paneId);
              if (pane == null) {
                throw StateError('AppleScript-created pane is stale');
              }
              await pane.start();
            },
            reconcile: reconcileInteractiveHierarchy,
            pasteController: externalPasteController!,
            paneCloseCoordinator: createdPaneCloseCoordinator,
            canMutate: () =>
                productResourceDisposalFuture == null &&
                !createdPaneCloseCoordinator.removalInProgress &&
                !createdPaneCloseCoordinator.applicationQuitInProgress,
          );
      final TerminalAppleScriptMacosNativePort createdAppleScriptNativePort =
          TerminalAppleScriptMacosNativePort.open();
      appleScriptNativePort = createdAppleScriptNativePort;
      appleScriptSession = TerminalAppleScriptProductSession(
        state: state,
        enabled:
            configurationAuthority.newSessionConfiguration.macosAppleScript,
        nativePort: createdAppleScriptNativePort,
        executor: appleScriptExecutor,
        titleForTab: (TerminalTabState tab) => presentationResolver
            .resolve(tab, fallbackTitle: localization.applicationName)
            .title,
        titleForTerminal: (PaneId paneId) {
          final TerminalPaneLocation? location = state.locationForPane(paneId);
          final TerminalTabState? tab = location == null
              ? null
              : state.tabForId(location.tabId);
          if (tab == null) return localization.applicationName;
          return sessions[paneId]?.terminalScreenSet.metadata.windowTitle ??
              presentationResolver
                  .resolve(tab, fallbackTitle: localization.applicationName)
                  .title;
        },
        workingDirectoryFor: (PaneId paneId) =>
            TerminalTabPresentationResolver.localFilePath(
              sessions[paneId]?.terminalScreenSet.metadata.workingDirectory,
            ),
        onError: recordAsynchronousError,
      );
      final TerminalPromptNavigationActionCoordinator promptNavigationActions =
          TerminalPromptNavigationActionCoordinator(
            activeViewport: activeViewport,
            onMoved: synchronizePromptNavigation,
          );
      closePaneRequest = (PaneId? paneId) async {
        final TerminalPaneCloseResult result = await createdPaneCloseCoordinator
            .requestClose(paneId: paneId);
        stdout.writeln(result.machineLine());
        final TerminalPaneRemovalResult? removal = result.removal;
        if (removal != null) {
          stdout.writeln(removal.shutdown.machineLine());
        }
        final TerminalAppKitMenuProjection? menu = menuProjection;
        if (menu != null && !menu.isDisposed) menu.refresh();
        final TerminalCommandPalettePresenter? palette = palettePresenter;
        if (palette != null && !palette.isDisposed) palette.refresh();
      };
      final TerminalApplicationQuitCoordinator createdQuitCoordinator =
          TerminalApplicationQuitCoordinator(
            state: state,
            paneCloseCoordinator: createdPaneCloseCoordinator,
            replyToTerminationRequest:
                (
                  ApplicationTerminateRequestedEvent request, {
                  required bool allow,
                }) {
                  application.replyToTerminationRequest(request, allow: allow);
                },
            onPreShutdown: disposeProductResources,
            terminateProgrammatically: () async {
              if (!closed.isCompleted) closed.complete();
            },
          );
      for (final PaneId paneId in deferredExitPaneIds.toList(growable: false)) {
        deferredExitPaneIds.remove(paneId);
        if (state.paneForId(paneId) != null) {
          unawaited(
            closePaneRequest(paneId)
                .then<void>((_) {}, onError: recordAsynchronousError),
          );
        }
      }
      final TerminalActionCatalog catalog = TerminalActionCatalog.standard(
        localization: localization,
      );
      late final TerminalCommandPalettePresenter installedPalette;
      late final TerminalActionDispatcher dispatcher;
      final TerminalQuickTerminalController createdQuickTerminal =
          TerminalQuickTerminalController(
            application: application,
            state: state,
            hierarchy: createdHierarchy,
            paneConfigurationFactory: () => configuration(null),
            configuration: () => configurationAuthority.newSessionConfiguration,
            reconcile: reconcileInteractiveHierarchy,
            onGlobalInvocation: () async {
              final TerminalActionDispatchResult result = await dispatcher
                  .dispatch(TerminalActionId.toggleQuickTerminal);
              if (runQuickTerminalAcceptance) actionDispatches.add(result);
              if (runQuickTerminalAcceptance) {
                stdout.writeln(
                  'TERMINAL_QUICK_TERMINAL_GLOBAL_DISPATCH '
                  'disposition=${result.disposition.name}',
                );
              }
              if (result.disposition ==
                  TerminalActionDispatchDisposition.failed) {
                Error.throwWithStackTrace(result.error!, result.stackTrace!);
              }
            },
            onStatusChanged: () {
              final TerminalSettingsInspectorPresenter? settings =
                  settingsPresenter;
              if (settings != null && !settings.isDisposed) settings.refresh();
              final TerminalAppKitMenuProjection? menu = menuProjection;
              if (menu != null && !menu.isDisposed) menu.refresh();
              final TerminalCommandPalettePresenter? palette = palettePresenter;
              if (palette != null && !palette.isDisposed) palette.refresh();
              diagnosticsPresenter?.refresh();
            },
            onError: recordAsynchronousError,
            accessibilityPresentation:
                applicationAccessibilityProjection!.presentation,
          );
      quickTerminalController = createdQuickTerminal;
      focusNotificationSession = (TerminalSessionId sessionId) async {
        final TerminalSession? session = sessions[sessionId.paneId];
        if (session == null || session.id != sessionId || !session.isLive) {
          return false;
        }
        final TerminalPaneLocation? location = state.locationForPane(
          sessionId.paneId,
        );
        final TerminalWindowState? logicalWindow = location == null
            ? null
            : state.windowForId(location.windowId);
        final TerminalTabState? tab = location == null
            ? null
            : state.tabForId(location.tabId);
        if (logicalWindow == null || tab == null) return false;
        state
          ..activateWindow(logicalWindow.id)
          ..selectTab(logicalWindow.id, tab.id)
          ..focusPane(tab.id, sessionId.paneId);
        if (logicalWindow.role == TerminalWindowRole.quickTerminal &&
            !createdQuickTerminal.lifecycle.isVisibleOrShowing) {
          await createdQuickTerminal.toggle();
          return sessions[sessionId.paneId]?.id == sessionId &&
              sessions[sessionId.paneId]?.isLive == true;
        }
        reconcileInteractiveHierarchy();
        final Window? nativeWindow = createdHierarchy.windowForTab(tab.id);
        final TerminalNativePaneResources? resources = createdHierarchy
            .resourcesForPane(sessionId.paneId);
        if (nativeWindow == null || resources == null) return false;
        nativeWindow
          ..show()
          ..selectTab()
          ..makeFirstResponder(resources.view);
        return true;
      };

      TerminalDiagnosticsFeatureState secureDiagnosticsState() {
        final TerminalSecureKeyboardEntryStatus status =
            createdSecureKeyboardEntry.status;
        return switch (status.mode) {
          TerminalSecureKeyboardEntryMode.failed =>
            TerminalDiagnosticsFeatureState.failed,
          TerminalSecureKeyboardEntryMode.disabled =>
            TerminalDiagnosticsFeatureState.disabled,
          TerminalSecureKeyboardEntryMode.automatic ||
          TerminalSecureKeyboardEntryMode.manual =>
            status.desired
                ? TerminalDiagnosticsFeatureState.active
                : TerminalDiagnosticsFeatureState.enabled,
        };
      }

      TerminalDiagnosticsFeatureState quickDiagnosticsState() {
        return switch (createdQuickTerminal.shortcutStatus.disposition) {
          TerminalQuickTerminalShortcutDisposition.disabled =>
            TerminalDiagnosticsFeatureState.disabled,
          TerminalQuickTerminalShortcutDisposition.failed =>
            TerminalDiagnosticsFeatureState.failed,
          TerminalQuickTerminalShortcutDisposition.registered =>
            createdQuickTerminal.lifecycle.isVisibleOrShowing
                ? TerminalDiagnosticsFeatureState.active
                : TerminalDiagnosticsFeatureState.enabled,
        };
      }

      TerminalDiagnosticsFeatureState notificationDiagnosticsState() {
        final TerminalNotificationProductStatus status =
            notificationController.status;
        if (!status.enabled) return TerminalDiagnosticsFeatureState.disabled;
        if (status.authorizationStatus ==
                AppKitUserNotificationAuthorizationStatus.denied ||
            status.lastFailure == TerminalNotificationProductFailure.denied) {
          return TerminalDiagnosticsFeatureState.denied;
        }
        if (status.lastFailure ==
                TerminalNotificationProductFailure.nativeFailure ||
            status.lastFailure == TerminalNotificationProductFailure.system) {
          return TerminalDiagnosticsFeatureState.failed;
        }
        return status.pendingRequestCount > 0
            ? TerminalDiagnosticsFeatureState.active
            : TerminalDiagnosticsFeatureState.enabled;
      }

      TerminalDiagnosticsFeatureState appIntentsDiagnosticsState() {
        final TerminalAppIntentsProductStatus? status =
            appIntentsController?.status;
        if (status == null || status.disposed) {
          return TerminalDiagnosticsFeatureState.unavailable;
        }
        if (!status.enabled) return TerminalDiagnosticsFeatureState.disabled;
        if (status.lastFailure ==
                TerminalAppIntentsProductFailure.nativeFailure ||
            status.lastFailure ==
                TerminalAppIntentsProductFailure.actionFailed) {
          return TerminalDiagnosticsFeatureState.failed;
        }
        return status.polling || status.pendingCommandCount > 0
            ? TerminalDiagnosticsFeatureState.active
            : TerminalDiagnosticsFeatureState.enabled;
      }

      TerminalDiagnosticsSnapshot captureDiagnosticsSnapshot(PaneId paneId) {
        final TerminalPane pane =
            state.paneForId(paneId) ??
            (throw StateError('focused diagnostics pane is unavailable'));
        final TerminalSession session =
            sessions[paneId] ??
            (throw StateError('focused diagnostics session is unavailable'));
        final _TerminalHierarchyProductPane owner =
            owners[paneId] ??
            (throw StateError('focused diagnostics renderer is unavailable'));
        final TerminalAccessibilityPresentation presentation =
            applicationAccessibilityProjection!.presentation;
        final TerminalConfigReloadController? reload =
            configurationReloadController;
        final TerminalConfigSnapshot? effective = reload?.effectiveSnapshot;
        final TerminalConfigSchema schema =
            effective?.schema ?? TerminalProductConfigSchema.instance;
        final List<TerminalConfigDiagnostic> diagnostics =
            reload?.lastAttemptedSnapshot == null
            ? effective?.diagnostics ?? const <TerminalConfigDiagnostic>[]
            : reload!.lastAttemptDiagnostics;
        final int warningCount = diagnostics
            .where(
              (TerminalConfigDiagnostic diagnostic) =>
                  diagnostic.severity ==
                  TerminalConfigDiagnosticSeverity.warning,
            )
            .length;
        final int errorCount = diagnostics.length - warningCount;
        final TerminalNotificationProductStatus notificationStatus =
            notificationController.status;
        final TerminalProductConfiguration currentConfiguration =
            configurationAuthority.newSessionConfiguration;
        final bool osc52Enabled =
            currentConfiguration.clipboardRead !=
                TerminalConfiguredClipboardAccess.deny ||
            currentConfiguration.clipboardWrite !=
                TerminalConfiguredClipboardAccess.deny;
        return TerminalDiagnosticsSnapshot(
          application: TerminalDiagnosticsApplicationSnapshot(
            runtimeKind: const bool.fromEnvironment('dart.vm.product')
                ? TerminalDiagnosticsRuntimeKind.releaseAot
                : TerminalDiagnosticsRuntimeKind.developerJit,
            appKitEventProtocol: application.eventProtocolVersion,
            language: localization.language == TerminalLanguage.japanese
                ? TerminalDiagnosticsLanguage.japanese
                : TerminalDiagnosticsLanguage.english,
            direction:
                localization.textDirection == TerminalTextDirection.rightToLeft
                ? TerminalDiagnosticsDirection.rightToLeft
                : TerminalDiagnosticsDirection.leftToRight,
            reduceMotion: presentation.reduceMotion,
            increaseContrast: presentation.increaseContrast,
            differentiateWithoutColor: presentation.differentiateWithoutColor,
          ),
          hierarchy: TerminalDiagnosticsHierarchySnapshot(
            windowCount: state.windowCount,
            tabCount: state.tabCount,
            paneCount: state.paneCount,
            livePaneCount: state.paneIds
                .where((PaneId id) => state.paneForId(id)?.isLive == true)
                .length,
            activeWindowRole:
                state.activeWindow?.role == TerminalWindowRole.quickTerminal
                ? TerminalDiagnosticsWindowRole.quick
                : TerminalDiagnosticsWindowRole.standard,
          ),
          focusedPane: session.captureFocusedPaneDiagnostics(
            lifecycle: _terminalDiagnosticsLifecycle(pane.state),
          ),
          parser: session.captureParserDiagnostics(),
          renderer: owner.surface.isDisposed
              ? TerminalDiagnosticsRendererSnapshot.unavailable()
              : TerminalDiagnosticsRendererSnapshot.fromLiveSurface(
                  owner.surface.snapshot(),
                  fontDiagnostics: owner.surface.fontDiagnostics(),
                ),
          configuration: TerminalDiagnosticsConfigurationSnapshot(
            schemaOptionCount: schema.options.length,
            effectiveGeneration:
                reload?.acceptedGeneration ??
                configurationAuthority.acceptedGeneration,
            attemptGeneration:
                (reload?.acceptedGeneration ??
                    configurationAuthority.acceptedGeneration) +
                (reload?.lastAttemptedSnapshot == null ? 0 : 1),
            warningCount: warningCount,
            errorCount: errorCount,
            liveOptionCount: schema.options
                .where(
                  (TerminalConfigOptionBase option) =>
                      option.applicationPolicy ==
                      TerminalConfigApplicationPolicy.live,
                )
                .length,
            newSessionOptionCount: schema.options
                .where(
                  (TerminalConfigOptionBase option) =>
                      option.applicationPolicy ==
                      TerminalConfigApplicationPolicy.newSession,
                )
                .length,
          ),
          features: TerminalDiagnosticsFeaturesSnapshot(
            secureInput: secureDiagnosticsState(),
            quickWindowShortcut: quickDiagnosticsState(),
            notifications: notificationDiagnosticsState(),
            appIntents: appIntentsDiagnosticsState(),
            appleScript: appleScriptSession == null
                ? TerminalDiagnosticsFeatureState.unavailable
                : appleScriptSession!.isEnabled
                ? TerminalDiagnosticsFeatureState.enabled
                : TerminalDiagnosticsFeatureState.disabled,
            osc52: !osc52Enabled
                ? TerminalDiagnosticsFeatureState.disabled
                : osc52Coordinator.pendingRequest != null
                ? TerminalDiagnosticsFeatureState.active
                : TerminalDiagnosticsFeatureState.enabled,
            pendingOsc52Requests: osc52Coordinator.pendingRequest == null
                ? 0
                : 1,
            pendingNotificationRequests: notificationStatus.pendingRequestCount,
            localIncidentState: TerminalDiagnosticsIncidentState.values.byName(
              incidentController.status.name,
            ),
            localIncidentMatchingReports:
                incidentController.snapshot.matchingReportCount,
            localIncidentCompletedOperations:
                incidentController.snapshot.completedOperationCount,
            localIncidentFailures:
                incidentController.snapshot.unsuccessfulOperationCount,
          ),
        );
      }

      TerminalDiagnosticsFocusTarget? activeDiagnosticsTarget() {
        final TerminalWindowState? activeWindow = state.activeWindow;
        if (activeWindow == null) return null;
        final TerminalTabState tab = activeWindow.selectedTab;
        final PaneId paneId = tab.focusedPaneId;
        final TerminalPane? pane = state.paneForId(paneId);
        final TerminalSession? session = sessions[paneId];
        final Window? window = createdHierarchy.windowForTab(tab.id);
        final TerminalNativePaneResources? resources = createdHierarchy
            .resourcesForPane(paneId);
        final _TerminalHierarchyProductPane? owner = owners[paneId];
        if (pane == null ||
            session == null ||
            !pane.isLive ||
            !session.isLive ||
            window == null ||
            resources == null ||
            owner == null ||
            owner.surface.isDisposed) {
          return null;
        }
        return TerminalDiagnosticsFocusTarget(
          identity: session.id,
          window: window,
          view: resources.view,
          isLive: () =>
              identical(sessions[paneId], session) &&
              state.paneForId(paneId)?.isLive == true &&
              session.isLive,
          beginCapture: (VtParserInspectionObserver observer) {
            session.beginDiagnosticsCapture(onEvent: observer);
          },
          endCapture: session.endDiagnosticsCapture,
          beginOverlay: () {
            owner.surface.updateInspectorOverlay(
              generation: ++diagnosticsOverlayGeneration,
              isActive: true,
            );
          },
          endOverlay: () {
            if (owner.surface.isDisposed) return;
            owner.surface.updateInspectorOverlay(
              generation: ++diagnosticsOverlayGeneration,
              isActive: false,
            );
          },
          snapshot: () => captureDiagnosticsSnapshot(paneId),
        );
      }

      String activeFontSettingsStatus() {
        final PaneId? paneId = state.activeWindow?.selectedTab.focusedPaneId;
        final _TerminalHierarchyProductPane? owner = paneId == null
            ? null
            : owners[paneId];
        if (owner == null || owner.surface.isDisposed) {
          return localization.settingsFontResolutionUnavailable;
        }
        final TerminalFontCatalogDiagnostics diagnostics = owner.surface
            .fontDiagnostics();
        final List<String> faceNames = diagnostics.resolutions
            .map(
              (TerminalFontResolutionDiagnostic resolution) =>
                  String.fromCharCodes(
                    resolution.postscriptName.runes.take(32),
                  ),
            )
            .toSet()
            .take(4)
            .toList(growable: false);
        final int remainingFaces =
            diagnostics.resolutions.length - faceNames.length;
        return localization.settingsFontResolutionStatus(
          appliedVariations: diagnostics.appliedVariationCount,
          configuredVariations: diagnostics.configuredVariationCount,
          unavailableVariations: diagnostics.unavailableVariationCount,
          availableOverrides: diagnostics.availableOverrideCount,
          configuredOverrides: diagnostics.configuredOverrideCount,
          unavailableOverrides: diagnostics.unavailableOverrideCount,
          overrideMatches: diagnostics.overrideMatchCount,
          overrideFallbacks: diagnostics.overrideFallbackCount,
          coreTextFallbacks: diagnostics.coreTextFallbackCount,
          missingGlyphs: diagnostics.missingGlyphCount,
          faceSummary: faceNames.isEmpty
              ? '-'
              : '${faceNames.join(',')}'
                    '${remainingFaces == 0 ? '' : '+$remainingFaces'}',
        );
      }

      diagnosticsPresenter = TerminalDiagnosticsPresenter(
        application: application,
        focusTarget: activeDiagnosticsTarget,
        localization: localization,
        chooseSaveDestination: runDiagnosticsAcceptance
            ? (SavePanelConfiguration _) => SavePanelResult.selected(
                '$diagnosticsExportDirectory/export-'
                '${diagnosticsExportSelectionIndex++}.json',
              )
            : null,
        onError: recordAsynchronousError,
      );
      TerminalIncidentFocusTarget? activeIncidentTarget() {
        final TerminalWindowState? activeWindow = state.activeWindow;
        if (activeWindow == null) return null;
        final TerminalTabState tab = activeWindow.selectedTab;
        final Window? window = createdHierarchy.windowForTab(tab.id);
        final TerminalNativePaneResources? resources = createdHierarchy
            .resourcesForPane(tab.focusedPaneId);
        if (window == null || resources == null) return null;
        return TerminalIncidentFocusTarget(
          window: window,
          view: resources.view,
        );
      }

      incidentPresenter = TerminalIncidentPresenter(
        application: application,
        controller: incidentController,
        focusTarget: activeIncidentTarget,
        localization: localization,
        chooseSaveDestination: runDiagnosticsAcceptance
            ? (SavePanelConfiguration configuration) {
                if (configuration.allowedFileExtension == 'ips') {
                  incidentAcceptance!.consentCount++;
                  return SavePanelResult.selected(
                    '${diagnosticsExportDirectory!}/incident-crash.ips',
                  );
                }
                incidentAcceptance!.consentCount++;
                return SavePanelResult.selected(
                  '${diagnosticsExportDirectory!}/incident-hang.sample.txt',
                );
              }
            : null,
        onError: recordAsynchronousError,
      );
      TerminalUpdateFocusTarget? activeUpdateTarget() {
        final TerminalWindowState? activeWindow = state.activeWindow;
        if (activeWindow == null) return null;
        final TerminalTabState tab = activeWindow.selectedTab;
        final Window? window = createdHierarchy.windowForTab(tab.id);
        final TerminalNativePaneResources? resources = createdHierarchy
            .resourcesForPane(tab.focusedPaneId);
        if (window == null || resources == null) return null;
        return TerminalUpdateFocusTarget(window: window, view: resources.view);
      }

      updatePresenter = TerminalUpdatePresenter(
        controller: updateController,
        focusTarget: activeUpdateTarget,
        localization: localization,
        onError: recordAsynchronousError,
      );
      dispatcher = TerminalActionDispatcher(
        catalog: catalog,
        registrations: <TerminalActionRegistration>[
          TerminalActionRegistration(
            id: TerminalActionId.openCommandPalette,
            handler: () => installedPalette.open(),
          ),
          TerminalActionRegistration(
            id: TerminalActionId.openTerminalInspector,
            isAvailable: () =>
                productResourceDisposalFuture == null &&
                diagnosticsPresenter?.hasAvailableTarget == true,
            handler: () => diagnosticsPresenter!.open(),
          ),
          TerminalActionRegistration(
            id: TerminalActionId.exportDiagnostics,
            isAvailable: () =>
                productResourceDisposalFuture == null &&
                diagnosticsPresenter?.hasAvailableTarget == true,
            handler: () async {
              await diagnosticsPresenter!.export();
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.exportLatestCrashReport,
            isAvailable: () =>
                productResourceDisposalFuture == null &&
                incidentPresenter?.canStart == true,
            handler: () async {
              await incidentPresenter!.exportLatestCrashReport();
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.captureHangSample,
            isAvailable: () =>
                productResourceDisposalFuture == null &&
                incidentPresenter?.canStart == true,
            handler: () async {
              await incidentPresenter!.captureHangSample();
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.checkForUpdates,
            isAvailable: () =>
                productResourceDisposalFuture == null &&
                !state.isDisposed &&
                updatePresenter?.isDisposed == false,
            handler: () async {
              await updatePresenter!.openAndCheck();
            },
          ),
          if (configurationReloadController != null)
            TerminalActionRegistration(
              id: TerminalActionId.openSettings,
              isAvailable: () =>
                  !configurationReloadController.isDisposed &&
                  productResourceDisposalFuture == null &&
                  !state.isDisposed,
              handler: () => settingsPresenter!.open(),
            ),
          if (configurationReloadController != null)
            TerminalActionRegistration(
              id: TerminalActionId.reloadConfiguration,
              isAvailable: () =>
                  !configurationReloadController.isDisposed &&
                  !configurationReloadController.inProgress &&
                  productResourceDisposalFuture == null &&
                  !state.isDisposed,
              handler: reloadConfiguration,
            ),
          TerminalActionRegistration(
            id: TerminalActionId.quitApplication,
            isAvailable: () =>
                !state.isDisposed &&
                !createdPaneCloseCoordinator.removalInProgress,
            handler: () async {
              final TerminalApplicationQuitResult result =
                  await createdQuitCoordinator.requestQuit();
              stdout.writeln(result.machineLine());
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.toggleQuickTerminal,
            isAvailable: () =>
                !state.isDisposed &&
                !createdQuickTerminal.isDisposed &&
                !createdPaneCloseCoordinator.removalInProgress &&
                !createdPaneCloseCoordinator.applicationQuitInProgress,
            handler: createdQuickTerminal.toggle,
          ),
          TerminalActionRegistration(
            id: TerminalActionId.toggleSecureKeyboardEntry,
            isAvailable: () =>
                !state.isDisposed &&
                !createdSecureKeyboardEntry.isDisposed &&
                !createdPaneCloseCoordinator.removalInProgress &&
                !createdPaneCloseCoordinator.applicationQuitInProgress,
            handler: () {
              createdSecureKeyboardEntry.toggleManual(
                target: activeSecureKeyboardEntryTarget(),
              );
              stdout.writeln(createdSecureKeyboardEntry.status.machineLine());
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.closeWindow,
            isAvailable: () =>
                state.activeWindow != null &&
                !createdPaneCloseCoordinator.removalInProgress &&
                !createdPaneCloseCoordinator.applicationQuitInProgress,
            handler: () async {
              if (state.activeWindow?.role ==
                  TerminalWindowRole.quickTerminal) {
                await createdQuickTerminal.hide();
              } else {
                await closePaneRequest!(null);
              }
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.quickLook,
            isAvailable: () {
              final PaneId? paneId =
                  state.activeWindow?.selectedTab.focusedPaneId;
              return paneId != null && quickLookCellForPane(paneId) != null;
            },
            handler: () {
              final PaneId? paneId =
                  state.activeWindow?.selectedTab.focusedPaneId;
              if (paneId == null) return;
              final TerminalNativeContentCell? cell = quickLookCellForPane(
                paneId,
              );
              quickLookCells.remove(paneId);
              if (cell != null) presentQuickLook(paneId, cell);
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.copy,
            isAvailable: () {
              final TerminalWindowState? window = state.activeWindow;
              final TerminalContextDockWindowSnapshot? dock = window == null
                  ? null
                  : createdContextDockState.snapshotForWindow(window.id);
              if (dock?.navigatorOwnsInput == true) {
                return createdPathHandoff.snapshotForWindow(window!.id).canCopy;
              }
              final TerminalSelectionText? selected = activeSelection()
                  ?.selectedText();
              return selected != null &&
                  selected.text.isNotEmpty &&
                  !selected.isTruncated;
            },
            handler: () {
              final TerminalWindowState? window = state.activeWindow;
              final TerminalContextDockWindowSnapshot? dock = window == null
                  ? null
                  : createdContextDockState.snapshotForWindow(window.id);
              if (dock?.navigatorOwnsInput == true) {
                final TerminalContextDockPathHandoffResult result =
                    createdPathHandoff.copyPath(window!.id);
                if (runNativeContentAcceptance) {
                  contextDockPathHandoffResults.add(result);
                }
                return;
              }
              final TerminalSelectionText? selected = activeSelection()
                  ?.selectedText();
              if (selected != null && selected.text.isNotEmpty) {
                clipboard.writeText(selected.text);
                pasteConfirmationGate.clear();
              }
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.paste,
            isAvailable: () {
              final TerminalPane? pane = activePane();
              return pane != null && !pane.pasteInProgress;
            },
            handler: paste,
          ),
          TerminalActionRegistration(
            id: TerminalActionId.allowOsc52Clipboard,
            isAvailable: () => osc52Coordinator.pendingRequest != null,
            handler: () {
              final TerminalOsc52PendingRequest? pending =
                  osc52Coordinator.pendingRequest;
              if (pending != null) osc52Coordinator.approve(pending.id);
            },
          ),
          TerminalActionRegistration(
            id: TerminalActionId.denyOsc52Clipboard,
            isAvailable: () => osc52Coordinator.pendingRequest != null,
            handler: () {
              final TerminalOsc52PendingRequest? pending =
                  osc52Coordinator.pendingRequest;
              if (pending != null) osc52Coordinator.deny(pending.id);
            },
          ),
          ...promptNavigationActions.registrations(),
          ...createdActions.registrations(),
          ...createdDockActions.registrations(),
          ...createdDockProcess.registrations(),
        ],
      );
      actionDispatcher = dispatcher;
      contextDockKeyController = TerminalContextDockKeyController(
        state: createdContextDockState,
        dispatcher: dispatcher,
        onChanged: () {
          createdDockDirectory.synchronize();
          reconcileInteractiveHierarchy();
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
          final TerminalCommandPalettePresenter? palette = palettePresenter;
          if (palette != null && !palette.isDisposed) palette.refresh();
        },
      );
      appIntentsController = TerminalAppIntentsProductController(
        session: TerminalAppIntentsMacos.open(),
        dispatch: dispatcher.dispatch,
        onStatusChanged: () {
          final TerminalSettingsInspectorPresenter? settings =
              settingsPresenter;
          if (settings != null && !settings.isDisposed) settings.refresh();
          diagnosticsPresenter?.refresh();
        },
        onError: (Object error, StackTrace _) {
          stderr.writeln(
            'TERMINAL_APP_INTENTS_PRODUCT_ERROR type=${error.runtimeType}',
          );
        },
      );
      for (final PaneId paneId in owners.keys.toList(growable: false)) {
        synchronizeNativeContentPane(paneId);
      }
      keyBindingActionScheduler = TerminalActionDispatchScheduler(
        dispatcher: dispatcher,
        onDispatched: (TerminalActionDispatchResult result) {
          if (runUserActionAcceptance ||
              runConfigurationAcceptance ||
              runOsc52Acceptance ||
              runQuickTerminalAcceptance ||
              runSecureKeyboardEntryAcceptance ||
              runDiagnosticsAcceptance) {
            actionDispatches.add(result);
          }
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
          final TerminalCommandPalettePresenter? palette = palettePresenter;
          if (palette != null && !palette.isDisposed) palette.refresh();
          if (result.disposition == TerminalActionDispatchDisposition.failed) {
            recordAsynchronousError(result.error!, result.stackTrace!);
          }
        },
        onError: recordAsynchronousError,
      );
      if (configurationReloadController != null) {
        final TerminalSettingsDocumentSession documentSession =
            settingsDocumentSession ??
            (throw StateError(
              'configuration reload requires a matching Settings document '
              'session',
            ));
        settingsPresenter = TerminalSettingsInspectorPresenter(
          controller: configurationReloadController,
          documentSession: documentSession,
          focusTarget: () {
            final TerminalWindowState? activeWindow = state.activeWindow;
            if (activeWindow == null) return null;
            final TerminalTabState tab = activeWindow.selectedTab;
            final Window? window = createdHierarchy.windowForTab(tab.id);
            final TerminalNativePaneResources? resources = createdHierarchy
                .resourcesForPane(tab.focusedPaneId);
            if (window == null || resources == null) return null;
            return TerminalSettingsInspectorFocusTarget(
              window: window,
              view: resources.view,
            );
          },
          reload: () =>
              dispatcher.dispatch(TerminalActionId.reloadConfiguration),
          onReloaded: (TerminalActionDispatchResult result) {
            if (runConfigurationAcceptance) actionDispatches.add(result);
          },
          onError: recordAsynchronousError,
          accessibilityPresentation:
              applicationAccessibilityProjection!.presentation,
          localization: localization,
          runtimeStatus: () =>
              '${createdQuickTerminal.shortcutStatus.settingsLineFor(localization)}    '
              '${createdSecureKeyboardEntry.status.settingsLineFor(localization)}    '
              '${appIntentsController!.status.settingsLineFor(localization)}    '
              '${notificationController.status.settingsLineFor(localization)}    '
              '${activeFontSettingsStatus()}',
        );
      }
      final TerminalProductConfiguration automationConfiguration =
          configurationAuthority.newSessionConfiguration;
      appIntentsController!.applyEnabled(
        automationConfiguration.macosAppIntents,
      );
      applyNotificationConfiguration(
        automationConfiguration.macosNotifications,
      );
      appIntentsPollTimer = Timer.periodic(
        TerminalAppIntentsProductController.productPollInterval,
        (_) {
          final TerminalAppIntentsProductController? controller =
              appIntentsController;
          if (controller != null) unawaited(controller.poll());
        },
      );
      installedPalette = TerminalCommandPalettePresenter.withFocusTarget(
        dispatcher: dispatcher,
        focusTarget: () {
          final TerminalWindowState? activeWindow = state.activeWindow;
          if (activeWindow == null) return null;
          final TerminalTabState tab = activeWindow.selectedTab;
          final Window? window = createdHierarchy.windowForTab(tab.id);
          final TerminalNativePaneResources? resources = createdHierarchy
              .resourcesForPane(tab.focusedPaneId);
          if (window == null || resources == null) return null;
          return TerminalCommandPaletteFocusTarget(
            window: window,
            view: resources.view,
          );
        },
        onDispatched: (TerminalActionDispatchResult result) {
          if (runUserActionAcceptance ||
              runConfigurationAcceptance ||
              runOsc52Acceptance ||
              runQuickTerminalAcceptance ||
              runSecureKeyboardEntryAcceptance ||
              runDiagnosticsAcceptance) {
            actionDispatches.add(result);
          }
          final TerminalAppKitMenuProjection? menu = menuProjection;
          if (menu != null && !menu.isDisposed) menu.refresh();
          if (result.disposition == TerminalActionDispatchDisposition.failed) {
            recordAsynchronousError(result.error!, result.stackTrace!);
          }
        },
        onError: recordAsynchronousError,
        localization: localization,
      );
      palettePresenter = installedPalette;
      menuProjection = TerminalAppKitMenuProjection.install(
        application: application,
        dispatcher: dispatcher,
        localization: localization,
        checkedReaders: <TerminalActionId, TerminalMenuCheckedReader>{
          TerminalActionId.toggleSecureKeyboardEntry: () =>
              createdSecureKeyboardEntry.manualRequested,
          TerminalActionId.toggleProcessArguments: () =>
              createdDockProcess.argumentsVisible,
        },
        onNativeInvocation: (TerminalActionId id, MenuItemInvokedEvent event) {
          if (runUserActionAcceptance ||
              runConfigurationAcceptance ||
              runOsc52Acceptance ||
              runQuickTerminalAcceptance ||
              runSecureKeyboardEntryAcceptance ||
              runDiagnosticsAcceptance) {
            nativeActionInvocations.add(id);
          }
        },
        onDispatched: (TerminalActionDispatchResult result) {
          if (runUserActionAcceptance ||
              runConfigurationAcceptance ||
              runOsc52Acceptance ||
              runQuickTerminalAcceptance ||
              runSecureKeyboardEntryAcceptance ||
              runDiagnosticsAcceptance) {
            actionDispatches.add(result);
          }
          installedPalette.refresh();
          if (result.disposition == TerminalActionDispatchDisposition.failed) {
            recordAsynchronousError(result.error!, result.stackTrace!);
          }
        },
      );
      if (runUserActionAcceptance) {
        stdout.writeln('TERMINAL_USER_ACTIONS_STAGE stage=menu-installed');
      }
      await createdQuickTerminal.replaceShortcut(
        configurationAuthority.newSessionConfiguration.quickTerminalShortcut,
      );
      stdout.writeln(createdQuickTerminal.shortcutStatus.machineLine());
      Future<void> handleFolderService(
        ApplicationFolderServiceRequestedEvent event,
      ) async {
        final List<String> workingDirectories = <String>[];
        for (final Uri directoryUrl in event.directoryUrls) {
          final String? workingDirectory =
              TerminalNativeContentPolicy.folderWorkingDirectory(directoryUrl);
          if (workingDirectory == null ||
              !Directory(workingDirectory).existsSync()) {
            return;
          }
          workingDirectories.add(workingDirectory);
        }
        if (workingDirectories.isEmpty) return;
        switch (event.action) {
          case FolderServiceAction.primary:
            TerminalWindowState? targetWindow = state.activeWindow;
            if (targetWindow?.role != TerminalWindowRole.standard) {
              targetWindow = null;
              for (final TerminalWindowState window in state.windows) {
                if (window.role == TerminalWindowRole.standard) {
                  targetWindow = window;
                }
              }
            }
            if (targetWindow == null) {
              final int created = await createdActions
                  .createWindowsAtWorkingDirectories(<String>[
                    workingDirectories.removeAt(0),
                  ]);
              if (created == 0 || workingDirectories.isEmpty) return;
            } else {
              state.activateWindow(targetWindow.id);
            }
            await createdActions.createTabsAtWorkingDirectories(
              workingDirectories,
            );
          case FolderServiceAction.secondary:
            await createdActions.createWindowsAtWorkingDirectories(
              workingDirectories,
            );
        }
      }

      application.folderServicesProvider =
          const FolderServicesProviderConfiguration();
      applicationSubscription = application.events.listen((AppKitEvent event) {
        switch (event) {
          case ApplicationActiveChangedEvent(:final isActive):
            desktopSignalCoordinator.setApplicationActive(isActive);
            osc52Coordinator.setApplicationActive(isActive);
            createdSecureKeyboardEntry.setApplicationActive(
              isActive,
              target: activeSecureKeyboardEntryTarget(),
            );
            unawaited(
              createdQuickTerminal
                  .handleApplicationActiveChanged(isActive: isActive)
                  .then<void>((_) {}, onError: recordAsynchronousError),
            );
            synchronizePaneFocusPresentation();
          case ApplicationAppearanceChangedEvent():
            // The dedicated theme projection owns palette application.
            break;
          case ApplicationAccessibilityDisplayPreferencesChangedEvent():
            // The dedicated accessibility projection owns application policy.
            break;
          case ApplicationPowerStateChangedEvent() ||
              ApplicationScreenSetChangedEvent():
            systemRecoveryController?.handle(event);
          case ApplicationMemoryPressureChangedEvent():
            memoryPressureController?.handle(event);
          case ApplicationReopenRequestedEvent(:final hasVisibleWindows):
            if (hasVisibleWindows || state.isDisposed) break;
            if (state.windows.any(
              (TerminalWindowState window) =>
                  window.role == TerminalWindowRole.standard,
            )) {
              createdHierarchy.present();
              break;
            }
            unawaited(
              dispatcher.dispatch(TerminalActionId.newWindow).then<void>((
                TerminalActionDispatchResult result,
              ) {
                if (result.disposition ==
                    TerminalActionDispatchDisposition.failed) {
                  recordAsynchronousError(result.error!, result.stackTrace!);
                }
              }, onError: recordAsynchronousError),
            );
          case ApplicationTerminateRequestedEvent():
            unawaited(
              createdQuitCoordinator.handleTerminationRequest(event).then<void>(
                (TerminalApplicationQuitResult result) {
                  stdout.writeln(result.machineLine());
                  if ((result.disposition ==
                              TerminalApplicationQuitDisposition.terminated ||
                          result.disposition ==
                              TerminalApplicationQuitDisposition
                                  .terminatedWithCleanupFailure) &&
                      !closed.isCompleted) {
                    closed.complete();
                  }
                },
                onError: recordAsynchronousError,
              ),
            );
          case ApplicationFolderServiceRequestedEvent():
            folderServiceQueue = folderServiceQueue
                .then<void>((_) => handleFolderService(event))
                .then<void>((_) {}, onError: recordAsynchronousError);
          case ApplicationUserNotificationChangedEvent():
            unawaited(
              notificationController
                  .handleEvent(event)
                  .then<void>((_) {}, onError: recordAsynchronousError),
            );
          case WindowEvent() ||
              MenuItemInvokedEvent() ||
              GlobalHotKeyPressedEvent() ||
              ViewQuickLookRequestedEvent() ||
              ViewServicesTextReceivedEvent() ||
              ViewDropPerformedEvent():
            break;
        }
      }, onError: recordAsynchronousError);

      stdout.writeln('Dart Terminal is attached to the AppKit main thread.');
      if (runPerformanceAcceptance) {
        await _exerciseProductPerformance(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          lifecycle: createdLifecycle,
          sessions: sessions,
          owners: owners,
          systemRecovery: systemRecoveryController!,
          memoryPressure: memoryPressureController!,
          observation: performanceObservation!,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runDiagnosticsAcceptance) {
        await _exerciseDiagnosticsProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          palette: installedPalette,
          presenter: diagnosticsPresenter!,
          incidentPresenter: incidentPresenter!,
          incidentController: incidentController,
          incidentAcceptance: incidentAcceptance!,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          terminalInputDeliveryCount: () => terminalInputDeliveryCount,
          reconcile: reconcileInteractiveHierarchy,
          exportDirectory: diagnosticsExportDirectory!,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runNativeContentAcceptance) {
        await _exerciseNativeContentProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          selections: selections,
          launchWorkingDirectories: launchWorkingDirectories,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          pasteResults: nativeContentPasteResults,
          writeEnqueuedCounts: nativeContentWriteEnqueuedCounts,
          quickLookTexts: nativeContentQuickLookTexts,
          contextDockState: createdContextDockState,
          contextDockProcess: createdDockProcess,
          secureKeyboardEntry: createdSecureKeyboardEntry,
          menu: menuProjection,
          palette: installedPalette,
          contextDockDirectory: createdDockDirectory,
          contextDockPresenter: createdDockPresenter,
          contextDockPathHandoff: createdPathHandoff,
          contextDockPathHandoffResults: contextDockPathHandoffResults,
          clipboard: clipboard,
          reconcile: reconcileInteractiveHierarchy,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runSystemAutomationAcceptance) {
        await _exerciseSystemAutomationProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          appIntents: appIntentsController!,
          notifications: notificationController,
          notificationPlatform: notificationAcceptancePlatform!,
          applyNotificationConfiguration: applyNotificationConfiguration,
          desktopSignalCoordinator: desktopSignalCoordinator,
          quickTerminal: createdQuickTerminal,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runAppleScriptAcceptance) {
        await _exerciseAppleScriptProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          session: appleScriptSession!,
          nativePort: appleScriptNativePort!,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runSecureKeyboardEntryAcceptance) {
        await _exerciseSecureKeyboardEntryProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          palette: installedPalette,
          settings: settingsPresenter!,
          quickTerminal: createdQuickTerminal,
          secureKeyboardEntry: createdSecureKeyboardEntry,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          lastKeyRoutes: lastKeyRoutes,
          keyRouteCounts: keyRouteCounts,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runQuickTerminalAcceptance) {
        await _exerciseQuickTerminalProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          settings: settingsPresenter!,
          controller: createdQuickTerminal,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runOsc52Acceptance) {
        await _exerciseOsc52Product(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          palette: installedPalette,
          confirmation: osc52Presenter!,
          coordinator: osc52Coordinator,
          clipboard: osc52Clipboard! as _MemoryTerminalOsc52Clipboard,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runDesktopSignalAcceptance) {
        await _exerciseDesktopSignalsProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          paneCloseCoordinator: createdPaneCloseCoordinator,
          desktopSignalCoordinator: desktopSignalCoordinator,
          nativePort: desktopSignalAcceptancePort!,
          clock: desktopSignalAcceptanceClock!,
          reconcile: reconcileInteractiveHierarchy,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runShellIntegrationAcceptance) {
        await _exerciseShellIntegrationProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          shellIntegrationBundle: shellIntegrationBundle,
          paneConfigurations: paneConfigurations,
          paneCloseCoordinator: createdPaneCloseCoordinator,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runThemeAcceptance) {
        await _exerciseThemeProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          palette: installedPalette,
          settings: settingsPresenter!,
          quickTerminal: createdQuickTerminal,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          themeProjection: applicationThemeProjection,
          accessibilityProjection: applicationAccessibilityProjection!,
          configurationReloadController: configurationReloadController,
          configurationAuthority: configurationAuthority,
          paneConfigurations: paneConfigurations,
          localization: localization,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runConfigurationAcceptance) {
        await _exerciseConfigurationProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          dispatcher: dispatcher,
          menu: menuProjection,
          palette: installedPalette,
          settings: settingsPresenter!,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          configurationReloads: configurationReloads,
          configurationReloadController: configurationReloadController,
          configurationAuthority: configurationAuthority,
          contextDockState: createdContextDockState,
          paneConfigurations: paneConfigurations,
          launchWorkingDirectories: launchWorkingDirectories,
          terminalInputDeliveryCount: () => terminalInputDeliveryCount,
          lastKeyRoutes: lastKeyRoutes,
          keyRouteCounts: keyRouteCounts,
          writeEnqueuedCounts: nativeContentWriteEnqueuedCounts,
          endOfFileActionCount: () => configurationEndOfFileActionCount,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      } else if (runUserActionAcceptance) {
        await _exerciseUserActionProduct(
          application: application,
          state: state,
          hierarchy: createdHierarchy,
          menu: menuProjection,
          palette: installedPalette,
          updatePresenter: updatePresenter!,
          updateController: updateController,
          updateService: updateAcceptanceService!,
          sessions: sessions,
          allSessions: allSessions,
          owners: owners,
          nativeActionInvocations: nativeActionInvocations,
          actionDispatches: actionDispatches,
          terminalInputDeliveryCount: () => terminalInputDeliveryCount,
          lastKeyRoutes: lastKeyRoutes,
          keyRouteCounts: keyRouteCounts,
          writeEnqueuedCounts: nativeContentWriteEnqueuedCounts,
          reconcile: reconcileInteractiveHierarchy,
          closed: closed,
          prompt: acceptancePrompt.trimRight(),
        );
      }
      await closed.future;
    } finally {
      MacosRuntime.recordDiagnosticPhase(
        RuntimeDiagnosticPhase.shutdownStarted,
      );
      await applicationSubscription?.cancel();
      applicationSubscription = null;
      await disposeProductResources();
      final TerminalPaneOwnerShutdownResult shutdown = await state.shutdown();
      for (final TerminalPaneSessionShutdownResult session
          in shutdown.sessions) {
        stdout.writeln(session.machineLine());
      }
      stdout.writeln(shutdown.machineLine());
      if (runPerformanceAcceptance) {
        _expectLifecycle(
          shutdown.sessions.length == 1 &&
              shutdown.isClean &&
              owners.values.every(
                (_TerminalHierarchyProductPane owner) =>
                    owner.adaptersDisposed && owner.surface.isDisposed,
              ) &&
              debugLiveTerminalTextInputClientCount() == 0 &&
              application.debugLiveObjectCount == 0,
          'performance acceptance did not release ordinary product owners',
        );
        stdout.writeln(
          'TERMINAL_PRODUCT_PERFORMANCE_CLEANUP sessions=1 metal=1 '
          'text_clients=0 native_handles=0',
        );
      }
      desktopSignalCoordinator.dispose();
      notificationController.dispose();
      final Object? error = asynchronousError;
      if (error != null && !closed.isCompleted) {
        Error.throwWithStackTrace(error, asynchronousStackTrace!);
      }
      if (!application.isTerminated) {
        await application.terminate().timeout(_hostTerminationTimeout);
      }
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootStopped);
    }
    stdout.writeln('Dart Terminal shut down cleanly.');
  }

  static Future<void> _exerciseProductPerformance({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required RuntimeLifecycleCoordinator lifecycle,
    required Map<PaneId, TerminalSession> sessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required TerminalSystemRecoveryController systemRecovery,
    required TerminalMemoryPressureController memoryPressure,
    required _TerminalProductPerformanceObservation observation,
    required Completer<void> closed,
    required String prompt,
  }) async {
    const int refreshSampleCount = 8;
    const int inputSampleCount = 7;
    const int visibleEchoSlackMicroseconds = 4000;
    const Duration resourceWindow = Duration(seconds: 2);
    const int resourceWindowMinimumMicroseconds = 2000000;
    const int resourceWorkloadLines = 11024;
    const int resourceWorkloadBytes = resourceWorkloadLines * 2;
    const int residentMemoryBudgetBytes = 512 * 1024 * 1024;
    const bool releasePerformanceAuthority = bool.fromEnvironment(
      'dart.vm.product',
    );
    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'performance acceptance requires one ordinary product pane',
    );
    final TerminalTabState tab = state.activeWindow!.selectedTab;
    final PaneId paneId = tab.focusedPaneId;
    final TerminalPane pane = state.paneForId(paneId)!;
    final TerminalSession session = sessions[paneId]!;
    final _TerminalHierarchyProductPane owner = owners[paneId]!;
    final Window window = hierarchy.windowForTab(tab.id)!;
    final TerminalCurrentProcessResourceSampler resourceSampler =
        TerminalCurrentProcessResourceSampler();

    await _waitForAsciiMarker(session, prompt);
    final Stopwatch initialFrameDeadline = Stopwatch()..start();
    while (initialFrameDeadline.elapsed < const Duration(seconds: 5) &&
        (!observation.startupFramePublished ||
            owner.surface.rendererState().lastPresentedFrameGeneration == 0 ||
            owner.client.geometryGeneration == 0)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    _expectLifecycle(
      observation.startupFramePublished &&
          owner.surface.snapshot().acceptedFrameCount > 0 &&
          owner.surface.rendererState().lastPresentedFrameGeneration > 0 &&
          owner.client.geometryGeneration > 0 &&
          owner.isVisible,
      'performance acceptance did not reach its first visible frame',
    );

    Future<int> measurePresentationRoundTrip() async {
      final int presentedBefore = owner.surface
          .rendererState()
          .lastPresentedFrameGeneration;
      final Stopwatch elapsed = Stopwatch()..start();
      session.terminalScreenSet.activeScreen.requestFullSnapshot();
      owner.notifyScreenChanged();
      while (elapsed.elapsed < const Duration(seconds: 2) &&
          owner.surface.rendererState().lastPresentedFrameGeneration <=
              presentedBefore) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      elapsed.stop();
      _expectLifecycle(
        owner.surface.rendererState().lastPresentedFrameGeneration >
            presentedBefore,
        'performance refresh probe was not presented',
      );
      return math.max(1, elapsed.elapsedMicroseconds);
    }

    for (var warmup = 0; warmup < 3; warmup++) {
      await measurePresentationRoundTrip();
    }
    observation.startFrameMeasurements();
    final List<int> refreshMicroseconds = <int>[];
    for (var sample = 0; sample < refreshSampleCount; sample++) {
      refreshMicroseconds.add(await measurePresentationRoundTrip());
    }
    final List<int> frameWorkMicroseconds = observation
        .finishFrameMeasurements();
    final int refreshIntervalMicroseconds = _performancePercentile(
      refreshMicroseconds,
      50,
    );
    final int frameWorkP95Microseconds = _performancePercentile(
      frameWorkMicroseconds,
      95,
    );
    final int frameBudgetMicroseconds = refreshIntervalMicroseconds * 7 ~/ 10;

    final List<int> inputAdmissionMicroseconds = <int>[];
    final List<int> visibleEchoMicroseconds = <int>[];
    for (var sample = 1; sample <= inputSampleCount; sample++) {
      final String readyMarker = '__DT_PERFORMANCE_READY_${sample}__';
      final String visibleMarker = '__DT_PERFORMANCE_VISIBLE_${sample}__';
      pane.insertText(
        "printf '\\r\\n__DT_PERFORMANCE_%s_${sample}__\\r\\n' READY; "
        "IFS= read -rsk 3 bytes; "
        "if [ \"\$bytes\" = \$'\\e[A' ] || "
        "[ \"\$bytes\" = \$'\\eOA' ]; then "
        "printf '\\r\\n__DT_PERFORMANCE_%s_${sample}__\\r\\n' VISIBLE; else "
        "printf '\\r\\n__DT_PERFORMANCE_%s_${sample}__\\r\\n' MISMATCH; fi",
      );
      await pane.submit();
      await _waitForAsciiMarkerPresented(
        owner,
        readyMarker,
        timeout: const Duration(seconds: 5),
      );
      final int acceptedBeforeInput = owner.surface
          .snapshot()
          .acceptedFrameCount;
      final Stopwatch visible = Stopwatch()..start();
      inputAdmissionMicroseconds.add(
        await observation.measureInputAdmission(
          owner.client.debugRunPerformanceKey,
        ),
      );
      final Stopwatch presentationDeadline = Stopwatch()..start();
      var visiblePresented = false;
      while (presentationDeadline.elapsed < const Duration(seconds: 5)) {
        final TerminalLiveMetalSurfaceSnapshot snapshot = owner.surface
            .snapshot();
        visiblePresented =
            _findAscii(session.terminalScreenSet.activeScreen, visibleMarker) !=
                null &&
            snapshot.acceptedFrameCount > acceptedBeforeInput;
        if (visiblePresented) break;
        _expectLifecycle(
          session.isLive,
          'performance session exited before presenting input response',
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      _expectLifecycle(
        visiblePresented,
        'performance input response was not accepted by a visible frame',
      );
      visible.stop();
      visibleEchoMicroseconds.add(math.max(1, visible.elapsedMicroseconds));
      _expectLifecycle(
        _findAscii(
              session.terminalScreenSet.activeScreen,
              '__DT_PERFORMANCE_MISMATCH_${sample}__',
            ) ==
            null,
        'performance input fixture received non-exact key bytes',
      );
    }
    final int inputAdmissionP95Microseconds = _performancePercentile(
      inputAdmissionMicroseconds,
      95,
    );
    final int visibleEchoP95Microseconds = _performancePercentile(
      visibleEchoMicroseconds,
      95,
    );
    final int visibleEchoBudgetMicroseconds =
        refreshIntervalMicroseconds + visibleEchoSlackMicroseconds;

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final TerminalLiveMetalSurfaceSnapshot idleBefore = owner.surface
        .snapshot();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final TerminalLiveMetalSurfaceSnapshot idleAfter = owner.surface.snapshot();
    final int idleBuildDelta =
        idleAfter.frameBuildCount - idleBefore.frameBuildCount;
    final int idleFrameDelta =
        idleAfter.acceptedFrameCount - idleBefore.acceptedFrameCount;

    final int windowHandle = appkit_testing.nativeWindowHandleForTesting(
      window,
    );
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      5,
      windowHandle,
      windowHandle >> 32,
      31000000,
      0,
      true,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final TerminalLiveMetalSurfaceSnapshot occludedBefore = owner.surface
        .snapshot();
    const String occludedMarker = '__DT_PERFORMANCE_OCCLUDED__';
    pane.insertText("printf '\\r\\n$occludedMarker\\r\\n'");
    await pane.submit();
    await _waitForAsciiMarker(session, occludedMarker);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final TerminalLiveMetalSurfaceSnapshot occludedAfter = owner.surface
        .snapshot();
    final int occludedBuildDelta =
        occludedAfter.frameBuildCount - occludedBefore.frameBuildCount;
    final int occludedFrameDelta =
        occludedAfter.acceptedFrameCount - occludedBefore.acceptedFrameCount;
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      5,
      windowHandle,
      windowHandle >> 32,
      31000001,
      0,
      false,
    ]);
    await _waitForAsciiMarkerPresented(
      owner,
      occludedMarker,
      timeout: const Duration(seconds: 5),
    );
    final bool resumeFrame =
        owner.surface.snapshot().acceptedFrameCount >
        occludedAfter.acceptedFrameCount;

    const String resourceReadyMarker = '__DT_RESOURCE_IDLE_READY__';
    pane.insertText(
      "printf '\\e[2 q\\r\\n__DT_RESOURCE_%s_READY__\\r\\n' IDLE",
    );
    await pane.submit();
    await _waitForAsciiMarkerPresented(
      owner,
      resourceReadyMarker,
      timeout: const Duration(seconds: 5),
    );
    _expectLifecycle(
      !session.terminalScreenSet.activeScreen.cursorBlinking,
      'performance resource window requires a non-animated cursor',
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final TerminalLiveMetalSurfaceSnapshot resourceIdleFrameBefore = owner
        .surface
        .snapshot();
    final TerminalProcessResourceSnapshot resourceIdleBefore = resourceSampler
        .snapshot();
    final Stopwatch resourceIdleClock = Stopwatch()..start();
    await Future<void>.delayed(resourceWindow);
    resourceIdleClock.stop();
    final TerminalProcessResourceSnapshot resourceIdleAfter = resourceSampler
        .snapshot();
    final TerminalLiveMetalSurfaceSnapshot resourceIdleFrameAfter = owner
        .surface
        .snapshot();
    final TerminalProcessResourceWindow idleResources =
        TerminalProcessResourceWindow(
          before: resourceIdleBefore,
          after: resourceIdleAfter,
          elapsedMicroseconds: resourceIdleClock.elapsedMicroseconds,
        );
    final int resourceIdleFrameDelta =
        resourceIdleFrameAfter.acceptedFrameCount -
        resourceIdleFrameBefore.acceptedFrameCount;

    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      5,
      windowHandle,
      windowHandle >> 32,
      32000000,
      0,
      true,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final TerminalLiveMetalSurfaceSnapshot resourceOccludedFrameBefore = owner
        .surface
        .snapshot();
    final TerminalProcessResourceSnapshot resourceOccludedBefore =
        resourceSampler.snapshot();
    final Stopwatch resourceOccludedClock = Stopwatch()..start();
    await Future<void>.delayed(resourceWindow);
    resourceOccludedClock.stop();
    final TerminalProcessResourceSnapshot resourceOccludedAfter =
        resourceSampler.snapshot();
    final TerminalLiveMetalSurfaceSnapshot resourceOccludedFrameAfter = owner
        .surface
        .snapshot();
    final TerminalProcessResourceWindow occludedResources =
        TerminalProcessResourceWindow(
          before: resourceOccludedBefore,
          after: resourceOccludedAfter,
          elapsedMicroseconds: resourceOccludedClock.elapsedMicroseconds,
        );
    final int resourceOccludedFrameDelta =
        resourceOccludedFrameAfter.acceptedFrameCount -
        resourceOccludedFrameBefore.acceptedFrameCount;
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      5,
      windowHandle,
      windowHandle >> 32,
      32000001,
      0,
      false,
    ]);
    final Stopwatch resourceResumeDeadline = Stopwatch()..start();
    while (resourceResumeDeadline.elapsed < const Duration(seconds: 5) &&
        owner.surface.snapshot().acceptedFrameCount <=
            resourceOccludedFrameAfter.acceptedFrameCount) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final bool resourceResumeFrame =
        owner.surface.snapshot().acceptedFrameCount >
        resourceOccludedFrameAfter.acceptedFrameCount;

    const String workloadMarker = '__DT_RESOURCE_WORKLOAD_READY__';
    pane.insertText(
      "yes P | head -n $resourceWorkloadLines; "
      "printf '\\r\\n__DT_RESOURCE_%s_READY__\\r\\n' WORKLOAD",
    );
    await pane.submit();
    await _waitForAsciiMarkerPresented(
      owner,
      workloadMarker,
      timeout: const Duration(seconds: 30),
    );
    final TerminalProcessResourceSnapshot workloadResources = resourceSampler
        .snapshot();
    final TerminalScrollback scrollback = session.terminalScreenSet.scrollback;
    final int minimumRetainedScrollbackLines =
        scrollback.maxLines - scrollback.pageRows + 1;
    final int expectedScrollbackPages =
        (scrollback.length + scrollback.pageRows - 1) ~/ scrollback.pageRows;
    final bool resourceCountsBound =
        state.windowCount == 1 &&
        state.tabCount == 1 &&
        state.paneCount == 1 &&
        sessions.length == 1 &&
        owners.length == 1 &&
        scrollback.length >= minimumRetainedScrollbackLines &&
        scrollback.length <= scrollback.maxLines &&
        scrollback.pageCount == expectedScrollbackPages &&
        scrollback.allocatedBytes > 0 &&
        scrollback.allocatedBytes <= scrollback.maxBytes;

    final int aggregateCpuMicroseconds =
        idleResources.cpuMicroseconds + occludedResources.cpuMicroseconds;
    final int aggregateWindowMicroseconds =
        idleResources.elapsedMicroseconds +
        occludedResources.elapsedMicroseconds;
    final int aggregateCpuBasisPoints =
        aggregateCpuMicroseconds * 10000 ~/ aggregateWindowMicroseconds;
    final int peakResidentBytes = <int>[
      resourceIdleBefore.peakResidentBytes,
      resourceIdleAfter.peakResidentBytes,
      workloadResources.peakResidentBytes,
      resourceOccludedBefore.peakResidentBytes,
      resourceOccludedAfter.peakResidentBytes,
    ].reduce(math.max);
    final bool residentMemoryBound =
        idleResources.maximumResidentBytes <= residentMemoryBudgetBytes &&
        workloadResources.currentResidentBytes <= residentMemoryBudgetBytes &&
        occludedResources.maximumResidentBytes <= residentMemoryBudgetBytes &&
        peakResidentBytes <= residentMemoryBudgetBytes;
    final bool idleCpuBound =
        aggregateCpuMicroseconds * 200 < aggregateWindowMicroseconds;

    final bool pendingBound = occludedAfter.pendingFrameCount <= 1;
    stdout.writeln(
      'TERMINAL_PRODUCT_PERFORMANCE_TEST refresh_samples=$refreshSampleCount '
      'refresh_interval_us=$refreshIntervalMicroseconds '
      'input_samples=$inputSampleCount '
      'input_p95_us=$inputAdmissionP95Microseconds '
      'visible_p95_us=$visibleEchoP95Microseconds '
      'visible_budget_us=$visibleEchoBudgetMicroseconds '
      'frame_samples=${frameWorkMicroseconds.length} '
      'frame_p95_us=$frameWorkP95Microseconds '
      'frame_budget_us=$frameBudgetMicroseconds '
      'idle_build_delta=$idleBuildDelta idle_frame_delta=$idleFrameDelta '
      'occluded_build_delta=$occludedBuildDelta '
      'occluded_frame_delta=$occludedFrameDelta resume_frame=$resumeFrame '
      'pending_bound=$pendingBound content_free=true',
    );
    stdout.writeln(
      'TERMINAL_PRODUCT_RESOURCE_TEST idle_window_us='
      '${idleResources.elapsedMicroseconds} idle_cpu_us='
      '${idleResources.cpuMicroseconds} idle_cpu_basis_points='
      '${idleResources.cpuBasisPoints} idle_rss_bytes='
      '${idleResources.maximumResidentBytes} workload_bytes='
      '$resourceWorkloadBytes workload_rss_bytes='
      '${workloadResources.currentResidentBytes} peak_rss_bytes='
      '$peakResidentBytes rss_budget_bytes=$residentMemoryBudgetBytes '
      'scrollback_lines=${scrollback.length} scrollback_pages='
      '${scrollback.pageCount} scrollback_allocated_bytes='
      '${scrollback.allocatedBytes} scrollback_max_bytes='
      '${scrollback.maxBytes} occluded_window_us='
      '${occludedResources.elapsedMicroseconds} occluded_cpu_us='
      '${occludedResources.cpuMicroseconds} occluded_cpu_basis_points='
      '${occludedResources.cpuBasisPoints} occluded_rss_bytes='
      '${occludedResources.maximumResidentBytes} aggregate_cpu_basis_points='
      '$aggregateCpuBasisPoints idle_frame_delta=$resourceIdleFrameDelta '
      'occluded_frame_delta=$resourceOccludedFrameDelta resume_frame='
      '$resourceResumeFrame rss_bound=$residentMemoryBound cpu_bound='
      '$idleCpuBound resource_counts_bound=$resourceCountsBound '
      'panes=1 sessions=1 metal=1 content_free=true',
    );
    _expectLifecycle(
      refreshMicroseconds.length == refreshSampleCount &&
          frameWorkMicroseconds.length >= refreshSampleCount &&
          frameWorkMicroseconds.length <= refreshSampleCount + 2 &&
          refreshIntervalMicroseconds > 0 &&
          refreshIntervalMicroseconds <= 50000 &&
          idleBuildDelta == 0 &&
          idleFrameDelta == 0 &&
          occludedBuildDelta == 0 &&
          occludedFrameDelta == 0 &&
          pendingBound &&
          resumeFrame,
      'ordinary product latency, frame, or suppression budget failed',
    );
    _expectLifecycle(
      idleResources.elapsedMicroseconds >= resourceWindowMinimumMicroseconds &&
          occludedResources.elapsedMicroseconds >=
              resourceWindowMinimumMicroseconds &&
          idleResources.cpuMicroseconds <= idleResources.elapsedMicroseconds &&
          occludedResources.cpuMicroseconds <=
              occludedResources.elapsedMicroseconds &&
          resourceIdleFrameDelta == 0 &&
          resourceOccludedFrameDelta == 0 &&
          resourceResumeFrame &&
          resourceCountsBound &&
          (!releasePerformanceAuthority ||
              (residentMemoryBound && idleCpuBound)),
      'ordinary product resource or idle-power proxy budget failed',
    );
    await _exerciseMemoryPressureProduct(
      application: application,
      controller: memoryPressure,
      pane: pane,
      session: session,
      owner: owner,
    );
    await _exerciseBoundedSystemReliabilityProduct(
      application: application,
      state: state,
      hierarchy: hierarchy,
      lifecycle: lifecycle,
      systemRecovery: systemRecovery,
      memoryPressure: memoryPressure,
      pane: pane,
      session: session,
      owner: owner,
      window: window,
      resourceSampler: resourceSampler,
    );
    if (!closed.isCompleted) closed.complete();
  }

  static Future<void> _exerciseMemoryPressureProduct({
    required AppKitApplication application,
    required TerminalMemoryPressureController controller,
    required TerminalPane pane,
    required TerminalSession session,
    required _TerminalHierarchyProductPane owner,
  }) async {
    final TerminalLiveMetalSurface surface = owner.surface;
    final TerminalLiveMetalSurfaceSnapshot before = surface.snapshot();
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final TerminalScrollback scrollback = session.terminalScreenSet.scrollback;
    final int screenDigest = _screenCanonicalDigest(screen);
    final int scrollbackLength = scrollback.length;
    final int scrollbackPageCount = scrollback.pageCount;
    final int scrollbackAllocatedBytes = scrollback.allocatedBytes;
    final int rendererGeneration = before.rendererGeneration;
    final int preeditGeneration = surface.preeditState.generation + 1;
    surface.updatePreedit(
      generation: preeditGeneration,
      text: 'memory-pressure-preedit',
      selectionLocation: 6,
      selectionLength: 8,
    );
    final Stopwatch preeditDeadline = Stopwatch()..start();
    while (surface.snapshot().acceptedFrameCount <= before.acceptedFrameCount &&
        preeditDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final TerminalLiveMetalSurfaceSnapshot warmed = surface.snapshot();
    _expectLifecycle(
      warmed.acceptedFrameCount > before.acceptedFrameCount &&
          warmed.shapingCacheEntryCount > 0 &&
          warmed.atlasEntryCount > 0 &&
          warmed.atlasEntryCount <= surface.atlas.limits.maximumEntries &&
          warmed.atlasRetainedBytes <=
              surface.atlas.limits.maximumRetainedBytes,
      'memory-pressure acceptance did not warm bounded reproducible caches',
    );

    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.normal,
      monotonicNanoseconds: 8200000000000000000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final TerminalMemoryPressureSnapshot controllerBaseline = controller
        .snapshot();
    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.warning,
      monotonicNanoseconds: 8200000000000100000,
    );
    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.warning,
      monotonicNanoseconds: 8200000000000200000,
    );
    final Stopwatch warningDeadline = Stopwatch()..start();
    while ((surface.snapshot().memoryPressureWarningCount <=
                warmed.memoryPressureWarningCount ||
            surface.snapshot().pendingMemoryPressureLevel != null ||
            surface.snapshot().acceptedFrameCount <=
                warmed.acceptedFrameCount ||
            controller.snapshot().applicationCount <=
                controllerBaseline.applicationCount) &&
        warningDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final TerminalLiveMetalSurfaceSnapshot afterWarning = surface.snapshot();
    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.critical,
      monotonicNanoseconds: 8200000000000300000,
    );
    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.critical,
      monotonicNanoseconds: 8200000000000400000,
    );
    final Stopwatch criticalDeadline = Stopwatch()..start();
    while ((surface.snapshot().memoryPressureCriticalCount <=
                warmed.memoryPressureCriticalCount ||
            surface.snapshot().pendingMemoryPressureLevel != null ||
            surface.snapshot().acceptedFrameCount <=
                afterWarning.acceptedFrameCount ||
            controller.snapshot().applicationCount <
                controllerBaseline.applicationCount + 2) &&
        criticalDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    _injectApplicationMemoryPressureEventForTesting(
      application,
      level: AppKitMemoryPressureLevel.normal,
      monotonicNanoseconds: 8200000000000500000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final TerminalMemoryPressureSnapshot controllerAfter = controller
        .snapshot();
    final TerminalLiveMetalSurfaceSnapshot after = surface.snapshot();
    final int acceptedEventDelta =
        controllerAfter.acceptedEventCount -
        controllerBaseline.acceptedEventCount;
    final int coalescedEventDelta =
        controllerAfter.coalescedEventCount -
        controllerBaseline.coalescedEventCount;
    final bool preeditRetained =
        surface.preeditState.generation == preeditGeneration &&
        surface.preeditState.text == 'memory-pressure-preedit' &&
        surface.preeditState.selectionLocation == 6 &&
        surface.preeditState.selectionLength == 8;
    stdout.writeln(
      'TERMINAL_MEMORY_PRESSURE_OBSERVED '
      'accepted_events=$acceptedEventDelta '
      'coalesced_events=$coalescedEventDelta '
      'applications=${controllerAfter.applicationCount - controllerBaseline.applicationCount} '
      'recoveries=${controllerAfter.recoveryCount - controllerBaseline.recoveryCount} '
      'warnings=${after.memoryPressureWarningCount - warmed.memoryPressureWarningCount} '
      'criticals=${after.memoryPressureCriticalCount - warmed.memoryPressureCriticalCount} '
      'deferrals=${after.memoryPressureDeferredCount - warmed.memoryPressureDeferredCount} '
      'shaping_entries=${after.memoryPressureShapingEntryCount - warmed.memoryPressureShapingEntryCount} '
      'atlas_entries=${after.memoryPressureAtlasEntryCount - warmed.memoryPressureAtlasEntryCount} '
      'atlas_bytes=${after.memoryPressureAtlasReleasedBytes - warmed.memoryPressureAtlasReleasedBytes} '
      'screen_retained=${_screenCanonicalDigest(screen) == screenDigest} '
      'scrollback_retained=${scrollback.length == scrollbackLength && scrollback.pageCount == scrollbackPageCount && scrollback.allocatedBytes == scrollbackAllocatedBytes} '
      'preedit_retained=$preeditRetained '
      'newest=${after.lastAcceptedModelRevision == after.lastAppliedDamageGeneration}',
    );
    _expectLifecycle(
      acceptedEventDelta == 3 &&
          coalescedEventDelta >= 2 &&
          controllerAfter.applicationCount ==
              controllerBaseline.applicationCount + 2 &&
          controllerAfter.recoveryCount ==
              controllerBaseline.recoveryCount + 1 &&
          controllerAfter.pendingLevel == null &&
          controllerAfter.observedLevel == AppKitMemoryPressureLevel.normal &&
          after.pendingMemoryPressureLevel == null &&
          after.memoryPressureWarningCount ==
              warmed.memoryPressureWarningCount + 1 &&
          after.memoryPressureCriticalCount ==
              warmed.memoryPressureCriticalCount + 1 &&
          after.memoryPressureShapingEntryCount >
              warmed.memoryPressureShapingEntryCount &&
          after.memoryPressureAtlasEntryCount >
              warmed.memoryPressureAtlasEntryCount &&
          after.memoryPressureAtlasReleasedBytes >
              warmed.memoryPressureAtlasReleasedBytes &&
          after.atlasResourceGeneration > warmed.atlasResourceGeneration &&
          after.rendererGeneration == rendererGeneration &&
          after.atlasEntryCount <= surface.atlas.limits.maximumEntries &&
          after.atlasRetainedBytes <=
              surface.atlas.limits.maximumRetainedBytes &&
          after.lastAcceptedModelRevision ==
              after.lastAppliedDamageGeneration &&
          _screenCanonicalDigest(screen) == screenDigest &&
          scrollback.length == scrollbackLength &&
          scrollback.pageCount == scrollbackPageCount &&
          scrollback.allocatedBytes == scrollbackAllocatedBytes &&
          preeditRetained &&
          identical(owner.surface, surface) &&
          identical(owner.pane, pane) &&
          identical(owner.session, session),
      'memory pressure changed canonical state or failed lazy cache recovery',
    );
    stdout.writeln(
      'TERMINAL_MEMORY_PRESSURE_TEST later_turn=true warning=true '
      'critical=true storm_coalesced=true pinned_safe=true '
      'canonical_retained=true lazy_rebuild=true capped=true '
      'accepted_events=$acceptedEventDelta '
      'coalesced_events=$coalescedEventDelta '
      'deferrals=${after.memoryPressureDeferredCount - warmed.memoryPressureDeferredCount} '
      'shaping_entries=${after.memoryPressureShapingEntryCount - warmed.memoryPressureShapingEntryCount} '
      'atlas_entries=${after.memoryPressureAtlasEntryCount - warmed.memoryPressureAtlasEntryCount} '
      'atlas_bytes=${after.memoryPressureAtlasReleasedBytes - warmed.memoryPressureAtlasReleasedBytes}',
    );
    surface.clearPreedit(generation: preeditGeneration + 1);
  }

  static Future<void> _exerciseBoundedSystemReliabilityProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required RuntimeLifecycleCoordinator lifecycle,
    required TerminalSystemRecoveryController systemRecovery,
    required TerminalMemoryPressureController memoryPressure,
    required TerminalPane pane,
    required TerminalSession session,
    required _TerminalHierarchyProductPane owner,
    required Window window,
    required TerminalCurrentProcessResourceSampler resourceSampler,
  }) async {
    const int iterationCount = 8;
    const int eventTimestampBase = 8300000000000000000;
    const int eventTimestampStride = 1000000;
    final TerminalLiveMetalSurface surface = owner.surface;
    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final TerminalScrollback scrollback = session.terminalScreenSet.scrollback;
    final int preeditGeneration = surface.preeditState.generation + 1;
    surface.updatePreedit(
      generation: preeditGeneration,
      text: 'bounded-reliability-preedit',
      selectionLocation: 8,
      selectionLength: 11,
    );
    final Stopwatch warmDeadline = Stopwatch()..start();
    while ((surface.snapshot().pendingFrameCount != 0 ||
            surface.snapshot().liveAtlasPinCount != 0) &&
        warmDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    final TerminalLiveMetalSurfaceSnapshot baseline = surface.snapshot();
    final TerminalSystemRecoverySnapshot systemBaseline = systemRecovery
        .snapshot();
    final TerminalMemoryPressureSnapshot pressureBaseline = memoryPressure
        .snapshot();
    final int descriptorBaseline = resourceSampler.openFileDescriptorCount();
    final int nativeHandleBaseline = application.debugLiveObjectCount;
    final int textClientBaseline = debugLiveTerminalTextInputClientCount();
    final int screenDigest = _screenCanonicalDigest(screen);
    final int scrollbackLength = scrollback.length;
    final int scrollbackPageCount = scrollback.pageCount;
    final int scrollbackAllocatedBytes = scrollback.allocatedBytes;
    final int rendererGeneration = baseline.rendererGeneration;
    final int workerGeneration = lifecycle.generation;
    final int? workerProcessId = lifecycle.workerPid;
    final Rect windowFrame = window.frame;
    final TerminalWindowState logicalWindow = state.activeWindow!;
    final TerminalTabState logicalTab = logicalWindow.selectedTab;
    final int initialAcceptedFrameCount = baseline.acceptedFrameCount;
    var sleepingFrameChecks = 0;
    var recoveredFrameChecks = 0;
    var descriptorBaselineChecks = 0;

    _expectLifecycle(
      baseline.pendingFrameCount == 0 &&
          baseline.liveAtlasPinCount == 0 &&
          !baseline.hasScheduledWork &&
          descriptorBaseline > 0 &&
          nativeHandleBaseline > 0 &&
          textClientBaseline == 1 &&
          workerProcessId != null &&
          RuntimeLifecycleCoordinator.outstandingProcessCount == 1,
      'bounded reliability did not begin at stable resource baselines',
    );

    for (var iteration = 0; iteration < iterationCount; iteration++) {
      final int timestamp =
          eventTimestampBase + iteration * eventTimestampStride;
      final TerminalSystemRecoverySnapshot systemBefore = systemRecovery
          .snapshot();
      final TerminalMemoryPressureSnapshot pressureBefore = memoryPressure
          .snapshot();
      final TerminalLiveMetalSurfaceSnapshot surfaceBefore = surface.snapshot();
      final AppKitMemoryPressureLevel level = iteration.isEven
          ? AppKitMemoryPressureLevel.warning
          : AppKitMemoryPressureLevel.critical;

      _injectApplicationPowerStateEventForTesting(
        application,
        state: AppKitApplicationPowerState.willSleep,
        monotonicNanoseconds: timestamp + 100000,
      );
      _injectApplicationScreenSetEventForTesting(
        application,
        monotonicNanoseconds: timestamp + 200000,
      );
      _injectApplicationScreenSetEventForTesting(
        application,
        monotonicNanoseconds: timestamp + 300000,
      );
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: level,
        monotonicNanoseconds: timestamp + 400000,
      );
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: level,
        monotonicNanoseconds: timestamp + 500000,
      );

      final Stopwatch suspendDeadline = Stopwatch()..start();
      while ((!systemRecovery.snapshot().isPresentationSuspended ||
              !surface.snapshot().isSystemSuspended ||
              memoryPressure.snapshot().applicationCount <=
                  pressureBefore.applicationCount) &&
          suspendDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final TerminalLiveMetalSurfaceSnapshot sleeping = surface.snapshot();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final TerminalLiveMetalSurfaceSnapshot sleepingStable = surface
          .snapshot();
      _expectLifecycle(
        systemRecovery.snapshot().isPresentationSuspended &&
            sleeping.isSystemSuspended &&
            sleeping.pendingMemoryPressureLevel == level &&
            sleeping.memoryPressureDeferredCount >
                surfaceBefore.memoryPressureDeferredCount &&
            sleepingStable.acceptedFrameCount == sleeping.acceptedFrameCount &&
            sleepingStable.frameBuildCount == sleeping.frameBuildCount &&
            !sleepingStable.hasScheduledWork,
        'bounded reliability admitted presentation work while sleeping',
      );
      sleepingFrameChecks++;

      _injectApplicationPowerStateEventForTesting(
        application,
        state: AppKitApplicationPowerState.didWake,
        monotonicNanoseconds: timestamp + 600000,
      );
      final Stopwatch recoveryDeadline = Stopwatch()..start();
      while ((systemRecovery.snapshot().isPresentationSuspended ||
              surface.snapshot().isSystemSuspended ||
              systemRecovery.snapshot().displayRecoveryCount <=
                  systemBefore.displayRecoveryCount ||
              surface.snapshot().pendingMemoryPressureLevel != null ||
              surface.snapshot().acceptedFrameCount <=
                  sleeping.acceptedFrameCount ||
              surface.snapshot().pendingFrameCount != 0 ||
              surface.snapshot().liveAtlasPinCount != 0 ||
              surface.snapshot().hasScheduledWork) &&
          recoveryDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.normal,
        monotonicNanoseconds: timestamp + 700000,
      );
      final Stopwatch normalDeadline = Stopwatch()..start();
      while ((memoryPressure.snapshot().observedLevel !=
                  AppKitMemoryPressureLevel.normal ||
              memoryPressure.snapshot().recoveryCount <=
                  pressureBefore.recoveryCount) &&
          normalDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final TerminalLiveMetalSurfaceSnapshot recovered = surface.snapshot();
      final TerminalSystemRecoverySnapshot systemAfter = systemRecovery
          .snapshot();
      final TerminalMemoryPressureSnapshot pressureAfter = memoryPressure
          .snapshot();
      final bool stageApplied = level == AppKitMemoryPressureLevel.warning
          ? recovered.memoryPressureWarningCount >
                surfaceBefore.memoryPressureWarningCount
          : recovered.memoryPressureCriticalCount >
                surfaceBefore.memoryPressureCriticalCount;
      final bool preeditRetained =
          surface.preeditState.generation == preeditGeneration &&
          surface.preeditState.text == 'bounded-reliability-preedit' &&
          surface.preeditState.selectionLocation == 8 &&
          surface.preeditState.selectionLength == 11;
      final int descriptorCount = resourceSampler.openFileDescriptorCount();
      _expectLifecycle(
        systemAfter.suspendCount == systemBefore.suspendCount + 1 &&
            systemAfter.displayRecoveryCount >=
                systemBefore.displayRecoveryCount + 1 &&
            systemAfter.resumeCount == systemBefore.resumeCount + 1 &&
            pressureAfter.applicationCount ==
                pressureBefore.applicationCount + 1 &&
            pressureAfter.recoveryCount == pressureBefore.recoveryCount + 1 &&
            pressureAfter.pendingLevel == null &&
            pressureAfter.observedLevel == AppKitMemoryPressureLevel.normal &&
            stageApplied &&
            recovered.pendingMemoryPressureLevel == null &&
            recovered.lastAcceptedModelRevision ==
                recovered.lastAppliedDamageGeneration &&
            recovered.pendingFrameCount == 0 &&
            recovered.liveAtlasPinCount == 0 &&
            !recovered.hasScheduledWork &&
            recovered.atlasEntryCount <= surface.atlas.limits.maximumEntries &&
            recovered.atlasRetainedBytes <=
                surface.atlas.limits.maximumRetainedBytes &&
            recovered.rendererGeneration == rendererGeneration &&
            _screenCanonicalDigest(screen) == screenDigest &&
            scrollback.length == scrollbackLength &&
            scrollback.pageCount == scrollbackPageCount &&
            scrollback.allocatedBytes == scrollbackAllocatedBytes &&
            preeditRetained &&
            state.windowCount == 1 &&
            state.tabCount == 1 &&
            state.paneCount == 1 &&
            identical(state.activeWindow, logicalWindow) &&
            identical(state.activeWindow!.selectedTab, logicalTab) &&
            identical(state.paneForId(pane.id), pane) &&
            identical(hierarchy.windowForTab(logicalTab.id), window) &&
            window.frame == windowFrame &&
            identical(owner.surface, surface) &&
            identical(owner.session, session) &&
            identical(owner.pane, pane) &&
            session.isLive &&
            lifecycle.generation == workerGeneration &&
            lifecycle.workerPid == workerProcessId &&
            RuntimeLifecycleCoordinator.outstandingProcessCount == 1 &&
            application.debugLiveObjectCount == nativeHandleBaseline &&
            debugLiveTerminalTextInputClientCount() == textClientBaseline &&
            descriptorCount == descriptorBaseline,
        'bounded reliability changed canonical state, owners, or resources',
      );
      recoveredFrameChecks++;
      descriptorBaselineChecks++;
    }

    final TerminalSystemRecoverySnapshot systemAfter = systemRecovery
        .snapshot();
    final TerminalMemoryPressureSnapshot pressureAfter = memoryPressure
        .snapshot();
    final TerminalLiveMetalSurfaceSnapshot surfaceAfter = surface.snapshot();
    final int systemAcceptedDelta =
        systemAfter.acceptedEventCount - systemBaseline.acceptedEventCount;
    final int systemCoalescedDelta =
        systemAfter.coalescedEventCount - systemBaseline.coalescedEventCount;
    final int pressureAcceptedDelta =
        pressureAfter.acceptedEventCount - pressureBaseline.acceptedEventCount;
    final int pressureCoalescedDelta =
        pressureAfter.coalescedEventCount -
        pressureBaseline.coalescedEventCount;
    _expectLifecycle(
      systemAcceptedDelta >= iterationCount * 3 &&
          systemCoalescedDelta >= iterationCount &&
          systemAfter.suspendCount ==
              systemBaseline.suspendCount + iterationCount &&
          systemAfter.displayRecoveryCount >=
              systemBaseline.displayRecoveryCount + iterationCount &&
          systemAfter.resumeCount ==
              systemBaseline.resumeCount + iterationCount &&
          pressureAcceptedDelta == iterationCount * 2 &&
          pressureCoalescedDelta >= iterationCount &&
          pressureAfter.applicationCount ==
              pressureBaseline.applicationCount + iterationCount &&
          pressureAfter.recoveryCount ==
              pressureBaseline.recoveryCount + iterationCount &&
          surfaceAfter.memoryPressureWarningCount ==
              baseline.memoryPressureWarningCount + iterationCount ~/ 2 &&
          surfaceAfter.memoryPressureCriticalCount ==
              baseline.memoryPressureCriticalCount + iterationCount ~/ 2 &&
          surfaceAfter.acceptedFrameCount >=
              initialAcceptedFrameCount + iterationCount &&
          sleepingFrameChecks == iterationCount &&
          recoveredFrameChecks == iterationCount &&
          descriptorBaselineChecks == iterationCount,
      'bounded reliability aggregate counters did not match fixed repetitions',
    );
    stdout.writeln(
      'TERMINAL_BOUNDED_RELIABILITY_TEST iterations=$iterationCount '
      'sleep=$sleepingFrameChecks wake=$recoveredFrameChecks '
      'display_recovery=${systemAfter.displayRecoveryCount - systemBaseline.displayRecoveryCount} '
      'pressure=${pressureAfter.applicationCount - pressureBaseline.applicationCount} '
      'warning=${surfaceAfter.memoryPressureWarningCount - baseline.memoryPressureWarningCount} '
      'critical=${surfaceAfter.memoryPressureCriticalCount - baseline.memoryPressureCriticalCount} '
      'pty=1 descriptors=$descriptorBaselineChecks root_isolate=1 '
      'worker_process=1 metal=1 gpu_pins=0 native_handles=$nativeHandleBaseline '
      'canonical_retained=true newest_redrawn=true baselines=true '
      'content_free=true',
    );
    surface.clearPreedit(generation: preeditGeneration + 1);
  }

  static int _performancePercentile(List<int> samples, int percentile) {
    _expectLifecycle(
      samples.isNotEmpty && percentile > 0 && percentile <= 100,
      'performance percentile input is invalid',
    );
    final List<int> sorted = List<int>.of(samples)..sort();
    final int index = ((sorted.length * percentile + 99) ~/ 100) - 1;
    return sorted[index];
  }

  static Future<void> _exerciseDiagnosticsProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalDiagnosticsPresenter presenter,
    required TerminalIncidentPresenter incidentPresenter,
    required TerminalIncidentController incidentController,
    required _TerminalIncidentAcceptanceContext incidentAcceptance,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required int Function() terminalInputDeliveryCount,
    required void Function() reconcile,
    required String exportDirectory,
    required Completer<void> closed,
    required String prompt,
  }) async {
    var eventTimestamp = 18000000;

    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    bool sameBytes(List<int> left, List<int> right) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (left[index] != right[index]) return false;
      }
      return true;
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'diagnostics product did not start from a 1/1/1 hierarchy',
    );
    final PaneId initialPaneId = state.activeWindow!.selectedTab.focusedPaneId;
    final TerminalSession initialSession = sessions[initialPaneId]!;
    final _TerminalHierarchyProductPane initialOwner = owners[initialPaneId]!;
    await _waitForAsciiMarker(initialSession, prompt);

    final int handleBaseline = application.debugLiveObjectCount;
    final int openInvocationBaseline = nativeActionInvocations.length;
    final int openDispatchBaseline = actionDispatches.length;
    final MenuItem openItem = menu.itemForAction(
      TerminalActionId.openTerminalInspector,
    );
    _expectLifecycle(
      openItem.isEnabled &&
          openItem.keyEquivalent == 'i' &&
          openItem.modifiers.bits ==
              ModifierKeys.optionBit | ModifierKeys.commandBit,
      'diagnostics inspector menu action has wrong availability or shortcut',
    );
    openItem.performAction();
    await waitFor(
      () =>
          presenter.isOpen &&
          initialSession.diagnosticsCaptureEnabled &&
          initialOwner.surface.snapshot().inspectorOverlayActive &&
          nativeActionInvocations.length == openInvocationBaseline + 1 &&
          actionDispatches.length == openDispatchBaseline + 1,
      'diagnostics inspector did not open and capture exactly once',
    );
    final Window inspectorWindow = presenter.activeWindow!;
    final int inspectorHandleCount = application.debugLiveObjectCount;
    final TerminalActionDispatchResult reopened = await dispatcher.dispatch(
      TerminalActionId.openTerminalInspector,
    );
    _expectLifecycle(
      reopened.disposition == TerminalActionDispatchDisposition.executed &&
          identical(presenter.activeWindow, inspectorWindow) &&
          inspectorHandleCount == handleBaseline + 2 &&
          application.debugLiveObjectCount == inspectorHandleCount,
      'diagnostics inspector did not preserve its single native owner pair',
    );

    const String firstPrivateMarker = '__DT_DIAGNOSTICS_PRIVATE_ALPHA__';
    initialOwner.pane.insertText(
      "printf '\\033]8;id=diagnostics;https://private.test\\a"
      "\\033[31m$firstPrivateMarker\\033[0m\\033]8;;\\a\\n'",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, firstPrivateMarker);
    await waitFor(
      () =>
          initialSession.captureParserDiagnostics().inspection.totalEventCount >
              0 &&
          initialOwner.surface.snapshot().inspectorHyperlinkSpanCount > 0 &&
          (presenter.renderedText ?? '').contains('events_total'),
      'diagnostics inspector did not refresh from live parser events',
    );
    _expectLifecycle(
      !(presenter.renderedText ?? '').contains(firstPrivateMarker),
      'diagnostics inspector retained printable terminal content',
    );

    final TerminalActionDispatchResult split = await dispatcher.dispatch(
      TerminalActionId.splitPaneRight,
    );
    await waitFor(
      () =>
          split.disposition == TerminalActionDispatchDisposition.executed &&
          state.paneCount == 2 &&
          sessions.length == 2 &&
          owners.length == 2,
      'diagnostics acceptance could not create a second focused pane',
    );
    reconcile();
    final PaneId focusedPaneId = state.activeWindow!.selectedTab.focusedPaneId;
    _expectLifecycle(
      focusedPaneId != initialPaneId,
      'diagnostics split did not focus the new pane',
    );
    final TerminalSession focusedSession = sessions[focusedPaneId]!;
    final _TerminalHierarchyProductPane focusedOwner = owners[focusedPaneId]!;
    await _waitForAsciiMarker(focusedSession, prompt);
    await waitFor(
      () =>
          !initialSession.diagnosticsCaptureEnabled &&
          initialSession.captureParserDiagnostics().inspection.events.isEmpty &&
          !initialOwner.surface.snapshot().inspectorOverlayActive &&
          initialOwner.surface.snapshot().inspectorSpanCount == 0 &&
          focusedSession.diagnosticsCaptureEnabled &&
          focusedOwner.surface.snapshot().inspectorOverlayActive &&
          presenter.capturedTargetIdentity == focusedSession.id &&
          presenter.captureHandoffCount >= 2,
      'diagnostics focus handoff did not clear old capture before new capture',
    );

    const String secondPrivateMarker = '__DT_DIAGNOSTICS_PRIVATE_BETA__';
    focusedOwner.pane.insertText(
      "printf '\\033[32m$secondPrivateMarker\\033[0m\\n'",
    );
    await focusedOwner.pane.submit();
    await _waitForAsciiMarker(focusedSession, secondPrivateMarker);
    await waitFor(
      () =>
          focusedSession.captureParserDiagnostics().inspection.totalEventCount >
              0 &&
          !(presenter.renderedText ?? '').contains(secondPrivateMarker),
      'diagnostics new-pane capture did not stay live and redacted',
    );

    final int incidentInputBaseline = terminalInputDeliveryCount();
    _expectLifecycle(
      incidentAcceptance.consentCount == 0 &&
          incidentAcceptance.store.accessCount == 0 &&
          incidentAcceptance.processRunner.runCount == 0,
      'incident fixture was accessed before explicit product consent',
    );
    final MenuItem crashItem = menu.itemForAction(
      TerminalActionId.exportLatestCrashReport,
    );
    _expectLifecycle(
      crashItem.isEnabled &&
          crashItem.keyEquivalent.isEmpty &&
          crashItem.modifiers.bits == 0,
      'crash report action is unavailable or has an unexpected shortcut',
    );
    final int crashInvocationBaseline = nativeActionInvocations.length;
    final int crashDispatchBaseline = actionDispatches.length;
    crashItem.performAction();
    final File crashExport = File('$exportDirectory/incident-crash.ips');
    await waitFor(
      () =>
          nativeActionInvocations.length == crashInvocationBaseline + 1 &&
          actionDispatches.length == crashDispatchBaseline + 1,
      'consented crash report menu action was not dispatched exactly once',
    );
    _expectLifecycle(
      incidentPresenter.lastOperationResult?.disposition ==
          TerminalIncidentOperationDisposition.exported,
      'consented crash report operation did not reach exported status; '
      'status=${incidentController.status.name} '
      'result=${incidentPresenter.lastOperationResult?.disposition.name} '
      'discoveries=${incidentAcceptance.store.discoverCount} '
      'exports=${incidentAcceptance.store.exportCount}',
    );
    _expectLifecycle(
      crashExport.existsSync(),
      'consented crash report was not atomically published',
    );
    final Window incidentWindow = incidentPresenter.activeWindow!;
    final int incidentHandleCount = application.debugLiveObjectCount;
    _expectLifecycle(
      incidentAcceptance.consentCount == 1 &&
          incidentAcceptance.store.discoverCount == 1 &&
          incidentAcceptance.store.exportCount == 1 &&
          incidentController.status == TerminalIncidentStatus.exported &&
          incidentController.snapshot.matchingReportCount == 1 &&
          incidentController.snapshot.completedOperationCount == 1 &&
          incidentPresenter.renderedText?.contains(exportDirectory) == false &&
          incidentPresenter.renderedText?.contains(
                '__DT_INCIDENT_PRIVATE_CRASH__',
              ) ==
              false,
      'crash report consent/status retained content or wrong fixed counts',
    );

    final MenuItem paletteItem = menu.itemForAction(
      TerminalActionId.openCommandPalette,
    );
    paletteItem.performAction();
    await waitFor(
      () => palette.isOpen,
      'incident acceptance could not open the command palette',
    );
    final Window incidentPaletteWindow = palette.activeWindow!;
    _injectKeyEventForTesting(
      application,
      incidentPaletteWindow,
      keyCode: 1,
      modifiers: 0,
      characters: 'capture hang sample',
      charactersIgnoringModifiers: 'capture hang sample',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          palette.state.query == 'capture hang sample' &&
          palette.state.selectedAction?.definition.id ==
              TerminalActionId.captureHangSample &&
          palette.state.selectedAction!.isEnabled,
      'command palette did not discover the hang sample action',
    );
    _injectKeyEventForTesting(
      application,
      incidentPaletteWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    final File sampleExport = File('$exportDirectory/incident-hang.sample.txt');
    await waitFor(
      () =>
          !palette.isOpen &&
          sampleExport.existsSync() &&
          incidentPresenter.lastOperationResult?.disposition ==
              TerminalIncidentOperationDisposition.sampled,
      'consented hang sample palette action did not complete',
    );
    _expectLifecycle(
      identical(incidentPresenter.activeWindow, incidentWindow) &&
          application.debugLiveObjectCount == incidentHandleCount &&
          incidentAcceptance.consentCount == 2 &&
          incidentAcceptance.processRunner.runCount == 1 &&
          incidentAcceptance.processRunner.lastArguments?.take(4).join(',') ==
              '4242,1,1,-file' &&
          incidentController.status == TerminalIncidentStatus.sampled &&
          incidentController.snapshot.completedOperationCount == 2 &&
          incidentPresenter.renderedText?.contains(exportDirectory) == false &&
          incidentPresenter.renderedText?.contains(
                '__DT_INCIDENT_PRIVATE_SAMPLE__',
              ) ==
              false &&
          terminalInputDeliveryCount() == incidentInputBaseline,
      'incident status was not singleton/content-free or leaked PTY input',
    );

    final int terminalInputBaseline = terminalInputDeliveryCount();
    final MenuItem exportItem = menu.itemForAction(
      TerminalActionId.exportDiagnostics,
    );
    _expectLifecycle(
      exportItem.isEnabled &&
          exportItem.keyEquivalent == 'e' &&
          exportItem.modifiers.bits ==
              ModifierKeys.optionBit | ModifierKeys.commandBit,
      'diagnostics export menu action has wrong availability or shortcut',
    );
    final int exportInvocationBaseline = nativeActionInvocations.length;
    final int exportDispatchBaseline = actionDispatches.length;
    exportItem.performAction();
    final File menuExport = File('$exportDirectory/export-0.json');
    await waitFor(
      () =>
          menuExport.existsSync() &&
          presenter.lastExportResult?.disposition ==
              TerminalDiagnosticsPresentationExportDisposition.written &&
          nativeActionInvocations.length == exportInvocationBaseline + 1 &&
          actionDispatches.length == exportDispatchBaseline + 1,
      'diagnostics menu export did not atomically complete exactly once',
    );

    final MenuItem diagnosticsPaletteItem = menu.itemForAction(
      TerminalActionId.openCommandPalette,
    );
    diagnosticsPaletteItem.performAction();
    await waitFor(
      () => palette.isOpen,
      'diagnostics acceptance could not open the command palette',
    );
    final Window paletteWindow = palette.activeWindow!;
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 14,
      modifiers: 0,
      characters: 'export diagnostics',
      charactersIgnoringModifiers: 'export diagnostics',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          palette.state.query == 'export diagnostics' &&
          palette.state.selectedAction?.definition.id ==
              TerminalActionId.exportDiagnostics &&
          palette.state.selectedAction!.isEnabled,
      'command palette did not discover the diagnostics export action',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    final File paletteExport = File('$exportDirectory/export-1.json');
    await waitFor(
      () => !palette.isOpen && paletteExport.existsSync(),
      'command-palette diagnostics export did not complete',
    );
    _expectLifecycle(
      palette.lastDispatchResult?.id == TerminalActionId.exportDiagnostics &&
          palette.lastDispatchResult?.disposition ==
              TerminalActionDispatchDisposition.executed &&
          terminalInputDeliveryCount() == terminalInputBaseline,
      'diagnostics UI actions leaked input or bypassed the shared dispatcher',
    );

    for (final File export in <File>[menuExport, paletteExport]) {
      final List<int> bytes = export.readAsBytesSync();
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      _expectLifecycle(
        decoded is Map<String, Object?> &&
            decoded['format'] == TerminalDiagnosticsFormatter.formatName &&
            decoded['version'] == TerminalDiagnosticsFormatter.formatVersion &&
            decoded['privacy'] is Map<String, Object?> &&
            (decoded['privacy']! as Map<String, Object?>)['paths'] ==
                'omitted' &&
            (((decoded['renderer']!
                        as Map<String, Object?>)['font_diagnostics']!
                    as Map<String, Object?>)['available'] ==
                true) &&
            (((decoded['renderer']!
                        as Map<String, Object?>)['font_diagnostics']!
                    as Map<String, Object?>)['configured_variations'] ==
                0) &&
            (((decoded['renderer']!
                        as Map<String, Object?>)['font_diagnostics']!
                    as Map<String, Object?>)['configured_overrides'] ==
                0) &&
            (((decoded['renderer']!
                            as Map<String, Object?>)['font_diagnostics']!
                        as Map<String, Object?>)['resolution_records']
                    as List<Object?>)
                .every(
                  (Object? record) =>
                      record is Map<String, Object?> &&
                      record['postscript_name'] is String &&
                      !(record['postscript_name']! as String).contains(
                        firstPrivateMarker,
                      ),
                ) &&
            bytes.length <=
                TerminalDiagnosticsFormatter.maximumOutputUtf8Bytes &&
            bytes.isNotEmpty &&
            bytes.last == 0x0a &&
            !utf8.decode(bytes).contains(firstPrivateMarker) &&
            !utf8.decode(bytes).contains(secondPrivateMarker) &&
            (decoded['features']!
                    as Map<String, Object?>)['local_incident_state'] ==
                'sampled' &&
            (decoded['features']!
                    as Map<
                      String,
                      Object?
                    >)['local_incident_matching_reports'] ==
                1 &&
            (decoded['features']!
                    as Map<
                      String,
                      Object?
                    >)['local_incident_completed_operations'] ==
                2 &&
            (decoded['features']!
                    as Map<String, Object?>)['local_incident_failures'] ==
                0 &&
            utf8
                    .encode(
                      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
                    )
                    .length ==
                bytes.length &&
            sameBytes(
              bytes,
              utf8.encode(
                '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
              ),
            ),
        'diagnostics export was noncanonical, oversized, or content-bearing',
      );
    }

    final int handlesBeforeIncidentDismiss = application.debugLiveObjectCount;
    await incidentPresenter.dismiss();
    _expectLifecycle(
      !incidentPresenter.isOpen &&
          incidentPresenter.terminalResponderRestoreCount == 1 &&
          application.debugLiveObjectCount ==
              handlesBeforeIncidentDismiss - 2 &&
          terminalInputDeliveryCount() == incidentInputBaseline,
      'incident close did not restore focus and release native owners',
    );

    final int handlesBeforeDismiss = application.debugLiveObjectCount;
    _injectKeyEventForTesting(
      application,
      inspectorWindow,
      keyCode: 53,
      modifiers: 0,
      characters: '\u001b',
      charactersIgnoringModifiers: '\u001b',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          !presenter.isOpen &&
          !focusedSession.diagnosticsCaptureEnabled &&
          focusedSession.captureParserDiagnostics().inspection.events.isEmpty &&
          !focusedOwner.surface.snapshot().inspectorOverlayActive &&
          focusedOwner.surface.snapshot().inspectorSpanCount == 0 &&
          application.debugLiveObjectCount == handlesBeforeDismiss - 2 &&
          presenter.terminalResponderRestoreCount >= 1,
      'diagnostics close did not clear capture and restore native ownership',
    );

    await dispatcher.dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatcher.dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          presenter.isDisposed &&
          incidentPresenter.isDisposed &&
          allSessions.length == 2 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true &&
                !session.diagnosticsCaptureEnabled &&
                session.captureParserDiagnostics().inspection.events.isEmpty,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'diagnostics product did not release all parser, PTY, or native owners',
    );
    stdout.writeln(
      'TERMINAL_DIAGNOSTICS_TEST inspector=true overlay=true singleton=true '
      'capture=true focus_handoff=true parser_events=true redacted=true '
      'menu=true palette=true canonical=true atomic=true exports=2 '
      'incident_consent=true incident_singleton=true incident_exports=2 '
      'incident_diagnostics=true '
      'terminal_write_delta=0 sessions_clean=2 text_clients=0 '
      'native_handles=0',
    );
  }

  static Future<void> _exerciseSystemAutomationProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppIntentsProductController appIntents,
    required TerminalNotificationProductController notifications,
    required _TerminalNotificationAcceptancePlatformPort notificationPlatform,
    required void Function(bool enabled) applyNotificationConfiguration,
    required TerminalDesktopSignalCoordinator desktopSignalCoordinator,
    required TerminalQuickTerminalController quickTerminal,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'system automation product did not start from a 1/1/1 hierarchy',
    );
    final TerminalWindowState initialWindow = state.windows.single;
    final TerminalTabState initialTab = initialWindow.selectedTab;
    final PaneId initialPaneId = initialTab.focusedPaneId;
    final TerminalSession initialSession = sessions[initialPaneId]!;
    final _TerminalHierarchyProductPane initialOwner = owners[initialPaneId]!;
    await _waitForAsciiMarker(initialSession, prompt);

    final app_intents_testing.TerminalAppIntentsMacosSelfAutomation automation =
        app_intents_testing.openTerminalAppIntentsMacosSelfAutomation();

    Future<void> invokeIntent(
      TerminalAppIntentAction action,
      bool Function() completed,
      String message,
    ) async {
      final int completedBefore = appIntents.status.completedCommandCount;
      automation.enqueue(action);
      await appIntents.poll();
      await waitFor(completed, message);
      _expectLifecycle(
        appIntents.status.completedCommandCount == completedBefore + 1,
        'App Intent ${action.name} did not complete exactly once',
      );
    }

    await invokeIntent(
      TerminalAppIntentAction.newWindow,
      () =>
          state.windowCount == 2 &&
          state.tabCount == 2 &&
          state.paneCount == 2 &&
          sessions.length == 2,
      'new-window App Intent did not use the shared hierarchy action',
    );
    await invokeIntent(
      TerminalAppIntentAction.newTab,
      () =>
          state.windowCount == 2 &&
          state.tabCount == 3 &&
          state.paneCount == 3 &&
          sessions.length == 3,
      'new-tab App Intent did not use the shared hierarchy action',
    );
    await invokeIntent(
      TerminalAppIntentAction.toggleQuickTerminal,
      () =>
          quickTerminal.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.visible &&
          state.windowCount == 3 &&
          state.tabCount == 4 &&
          state.paneCount == 4 &&
          sessions.length == 4,
      'Quick Terminal App Intent did not use the shared toggle action',
    );
    _expectLifecycle(
      appIntents.status.pendingCommandCount == 0 &&
          appIntents.status.completedCommandCount == 3 &&
          appIntents.status.rejectedCommandCount == 0 &&
          appIntents.status.failedCommandCount == 0,
      'App Intent native/product counters differ after three shared actions',
    );
    appIntents.applyEnabled(false);
    final int rejectedBefore = appIntents.status.rejectedCommandCount;
    var disabledStatus = -1;
    try {
      automation.enqueue(TerminalAppIntentAction.newWindow);
    } on TerminalAppIntentsMacosException catch (error) {
      disabledStatus = error.status;
    }
    appIntents.applyEnabled(true);
    _expectLifecycle(
      disabledStatus == _appIntentsDisabledStatus &&
          appIntents.status.rejectedCommandCount == rejectedBefore + 1 &&
          appIntents.status.lastFailure ==
              TerminalAppIntentsProductFailure.nativeRejected,
      'disabled App Intent admission did not fail closed exactly once',
    );

    _expectLifecycle(
      notificationPlatform.settingsTokens.length == 1 &&
          notifications.status.enabled &&
          desktopSignalCoordinator.notificationsEnabled,
      'notification product did not begin with one asynchronous settings query',
    );
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 1,
        kind: AppKitUserNotificationEventKind.settings,
        token: notificationPlatform.settingsTokens.single,
        authorizationStatus:
            AppKitUserNotificationAuthorizationStatus.notDetermined,
        failure: AppKitUserNotificationFailure.none,
      ),
    );
    notifications.requestAuthorization();
    _expectLifecycle(
      notificationPlatform.authorizationTokens.length == 1,
      'notification authorization did not remain an asynchronous request',
    );
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 2,
        kind: AppKitUserNotificationEventKind.authorization,
        token: notificationPlatform.authorizationTokens.single,
        authorizationStatus: AppKitUserNotificationAuthorizationStatus.denied,
        failure: AppKitUserNotificationFailure.denied,
      ),
    );

    desktopSignalCoordinator.setApplicationActive(true);
    initialOwner.pane.insertText(
      "printf '\\033]9;automation-denied\\007__DT_AUTOMATION_DENIED__\\n'",
    );
    await initialOwner.pane.submit();
    await waitFor(
      () => notificationPlatform.posts.length == 1,
      'background terminal notification did not reach the product port',
    );
    final _TerminalNotificationAcceptancePost deniedPost =
        notificationPlatform.posts.single;
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 3,
        kind: AppKitUserNotificationEventKind.delivery,
        token: deniedPost.deliveryToken,
        authorizationStatus: AppKitUserNotificationAuthorizationStatus.denied,
        failure: AppKitUserNotificationFailure.denied,
      ),
    );
    _expectLifecycle(
      notifications.status.lastFailure ==
              TerminalNotificationProductFailure.denied &&
          notifications.status.liveResponseCount == 0 &&
          desktopSignalCoordinator.metrics.projectionFailureCount == 1,
      'denied notification did not release native and logical ownership',
    );

    initialOwner.pane.insertText(
      "printf '\\033]9;automation-focus\\007__DT_AUTOMATION_FOCUS__\\n'",
    );
    await initialOwner.pane.submit();
    await waitFor(
      () => notificationPlatform.posts.length == 2,
      'notification retry did not recover after asynchronous delivery failure',
    );
    final _TerminalNotificationAcceptancePost responsePost =
        notificationPlatform.posts.last;
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 4,
        kind: AppKitUserNotificationEventKind.delivery,
        token: responsePost.deliveryToken,
        authorizationStatus:
            AppKitUserNotificationAuthorizationStatus.authorized,
        failure: AppKitUserNotificationFailure.none,
      ),
    );
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 5,
        kind: AppKitUserNotificationEventKind.defaultResponse,
        token: responsePost.responseToken,
        authorizationStatus: AppKitUserNotificationAuthorizationStatus.unknown,
        failure: AppKitUserNotificationFailure.none,
      ),
    );
    _expectLifecycle(
      state.activeWindowId == initialWindow.id &&
          initialWindow.selectedTabId == initialTab.id &&
          initialTab.focusedPaneId == initialPaneId &&
          notifications.status.liveResponseCount == 0,
      'default notification response did not focus the exact live session',
    );
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 6,
        kind: AppKitUserNotificationEventKind.defaultResponse,
        token: responsePost.responseToken,
        authorizationStatus: AppKitUserNotificationAuthorizationStatus.unknown,
        failure: AppKitUserNotificationFailure.none,
      ),
    );
    _expectLifecycle(
      notifications.status.liveResponseCount == 0,
      'duplicate notification response reacquired consumed ownership',
    );

    final TerminalSession backgroundSession = sessions.values.firstWhere(
      (TerminalSession session) =>
          session.id != initialSession.id &&
          state.locationForPane(session.id.paneId)?.windowId !=
              state.quickTerminalWindow?.id,
    );
    final _TerminalHierarchyProductPane backgroundOwner =
        owners[backgroundSession.id.paneId]!;
    backgroundOwner.pane.insertText(
      "printf '\\033]9;automation-disable\\007__DT_AUTOMATION_DISABLE__\\n'",
    );
    await backgroundOwner.pane.submit();
    await waitFor(
      () => notificationPlatform.posts.length == 3,
      'notification disable fixture did not create a live tracked record',
    );
    applyNotificationConfiguration(false);
    _expectLifecycle(
      !notifications.status.enabled &&
          !desktopSignalCoordinator.notificationsEnabled &&
          notifications.status.liveResponseCount == 0 &&
          notificationPlatform.removedIdentifiers.length == 2,
      'notification live disable did not cancel all remaining native owners',
    );
    final int postsWhileDisabled = notificationPlatform.posts.length;
    backgroundOwner.pane.insertText(
      "printf '\\033]9;automation-blocked\\007__DT_AUTOMATION_BLOCKED__\\n'",
    );
    await backgroundOwner.pane.submit();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _expectLifecycle(
      notificationPlatform.posts.length == postsWhileDisabled,
      'disabled notification projection reached the native port',
    );
    applyNotificationConfiguration(true);
    final int recoverySettingsToken = notificationPlatform.settingsTokens.last;
    await notifications.handleEvent(
      ApplicationUserNotificationChangedEvent(
        monotonicMicros: 7,
        kind: AppKitUserNotificationEventKind.settings,
        token: recoverySettingsToken,
        authorizationStatus:
            AppKitUserNotificationAuthorizationStatus.authorized,
        failure: AppKitUserNotificationFailure.none,
      ),
    );
    _expectLifecycle(
      notifications.status.authorizationStatus ==
              AppKitUserNotificationAuthorizationStatus.authorized &&
          appIntents.status.settingsLine.contains('availability=ready') &&
          notifications.status.settingsLine.contains(
            'authorization=authorized',
          ) &&
          !notifications.status.settingsLine.contains('automation-focus'),
      'Settings status did not recover with content-free automation state',
    );

    await dispatcher.dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatcher.dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          appIntents.isDisposed &&
          !notifications.status.enabled &&
          notifications.status.liveResponseCount == 0 &&
          notificationPlatform.visiblePostCount == 0 &&
          allSessions.length == 4 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'system automation product did not release every session/native owner',
    );
    stdout.writeln(
      'TERMINAL_SYSTEM_AUTOMATION_TEST app_intents=3 shared_actions=true '
      'native_queue=true disabled_rejected=1 metadata_external=true '
      'notification_settings=true authorization=true denied=true retry=true '
      'response_focus=true duplicate_inert=true disable=true reenable=true '
      'permission_untouched=true visible_notifications=0 sessions_clean=4 '
      'text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseAppleScriptProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppleScriptProductSession session,
    required TerminalAppleScriptMacosNativePort nativePort,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    var operationId = 0;
    Future<void> enqueue(
      String kind, {
      String? target,
      String? direction,
      String? text,
      required bool Function() completed,
    }) async {
      final int resumed = nativePort.summary.resumedCommandCount;
      final int enqueueStatus = nativePort.enqueueSelfAutomationCommand(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'version': 1,
              'operationId': ++operationId,
              'kind': kind,
              'target': target,
              'direction': direction,
              'text': text,
            }),
          ),
        ),
      );
      _expectLifecycle(
        enqueueStatus == 0,
        'self-automation command was rejected with status $enqueueStatus',
      );
      final TerminalAppleScriptNativeSummary queued = nativePort.summary;
      _expectLifecycle(
        queued.pendingCommandCount == 1 && queued.queuedCommandCount == 1,
        'self-automation command did not enter the native pending queue',
      );
      await waitFor(() {
        final TerminalAppleScriptNativeSummary current = nativePort.summary;
        return current.resumedCommandCount == resumed + 1 &&
            current.pendingCommandCount == 0 &&
            current.queuedCommandCount == 0 &&
            completed();
      }, 'self-automation command $kind did not complete exactly once');
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1 &&
          session.isEnabled,
      'AppleScript product did not start from a live 1/1/1 hierarchy',
    );
    final TerminalWindowState firstWindow = state.windows.single;
    final TerminalTabState firstTab = firstWindow.selectedTab;
    final PaneId firstPaneId = firstTab.focusedPaneId;
    await _waitForAsciiMarker(sessions[firstPaneId]!, prompt);
    final TerminalAppleScriptNativeSummary initial = nativePort.summary;
    _expectLifecycle(
      initial.started &&
          initial.enabled &&
          initial.windowCount == 1 &&
          initial.tabCount == 1 &&
          initial.terminalCount == 1 &&
          initial.pendingCommandCount == 0,
      'initial native AppleScript cache does not match product state',
    );

    await enqueue(
      'newWindow',
      completed: () =>
          state.windowCount == 2 &&
          state.tabCount == 2 &&
          state.paneCount == 2 &&
          nativePort.summary.windowCount == 2,
    );
    final TerminalWindowState secondWindow = state.windowForId(
      const TerminalWindowId(2),
    )!;
    await _waitForAsciiMarker(
      sessions[secondWindow.selectedTab.focusedPaneId]!,
      prompt,
    );
    await enqueue(
      'newTab',
      target: 'window:${firstWindow.id.value}',
      completed: () =>
          state.windowForId(firstWindow.id)!.tabs.length == 2 &&
          state.tabCount == 3 &&
          state.paneCount == 3 &&
          nativePort.summary.tabCount == 3,
    );
    final TerminalTabState thirdTab = state.tabForId(const TerminalTabId(3))!;
    await _waitForAsciiMarker(sessions[thirdTab.focusedPaneId]!, prompt);
    await enqueue(
      'split',
      target: 'terminal:${firstPaneId.value}',
      direction: 'right',
      completed: () =>
          firstTab.paneIds.length == 2 &&
          state.paneCount == 4 &&
          nativePort.summary.terminalCount == 4,
    );
    final PaneId splitPaneId = firstTab.focusedPaneId;
    _expectLifecycle(
      splitPaneId == const PaneId(4) &&
          firstTab.paneIds.join(',') == '${firstPaneId.value},4',
      'scripted split did not preserve stable IDs and right placement',
    );
    final TerminalSession splitSession = sessions[splitPaneId]!;
    await _waitForAsciiMarker(splitSession, prompt);
    final _TerminalHierarchyProductPane splitOwner = owners[splitPaneId]!;
    const String inputBody = 'AS9exact';
    const String inputReady = '__DT_AS_INPUT_READY__';
    const String inputExact = '__DT_AS_INPUT_EXACT__';
    const String inputMismatch = '__DT_AS_INPUT_MISMATCH__';
    const int inputEncodedBytes =
        inputBody.length + TerminalPasteCodec.bracketFrameBytes;
    splitOwner.pane.insertText(
      "stty -echo -icanon min 1 time 0; "
      "printf '\\033[?2004h\\r\\n__DT_AS_INPUT_%s__\\r\\n' 'READY'; "
      "/usr/bin/perl -e 'binmode STDIN; my \$n=$inputEncodedBytes; "
      "my \$d=\"\"; while (length(\$d) < \$n) { "
      "my \$r=sysread(STDIN, my \$b, \$n-length(\$d)); "
      "exit 24 unless defined(\$r) && \$r > 0; \$d .= \$b; } "
      "exit(\$d eq \"\\e[200~$inputBody\\e[201~\" ? 0 : 23);'; "
      "result=\$?; printf '\\033[?2004l'; stty echo icanon; "
      "if [ \$result -eq 0 ]; then "
      "printf '\\r\\n__DT_AS_INPUT_%s__\\r\\n' 'EXACT'; else "
      "printf '\\r\\n__DT_AS_INPUT_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await splitOwner.pane.submit();
    await _waitForAsciiMarker(splitSession, inputReady);
    _expectLifecycle(
      splitSession.bracketedPasteMode,
      'AppleScript input fixture did not retain bracketed paste mode',
    );
    await enqueue(
      'inputText',
      target: 'terminal:${splitPaneId.value}',
      text: inputBody,
      completed: () =>
          _findAscii(splitSession.terminalScreenSet.activeScreen, inputExact) !=
          null,
    );
    _expectLifecycle(
      _findAscii(splitSession.terminalScreenSet.activeScreen, inputMismatch) ==
          null,
      'real PTY rejected the exact AppleScript input payload',
    );
    await enqueue(
      'focus',
      target: 'terminal:${firstPaneId.value}',
      completed: () =>
          state.activeWindowId == firstWindow.id &&
          firstWindow.selectedTabId == firstTab.id &&
          firstTab.focusedPaneId == firstPaneId,
    );
    await enqueue(
      'closeTerminal',
      target: 'terminal:${splitPaneId.value}',
      completed: () =>
          state.paneForId(splitPaneId) == null &&
          nativePort.summary.terminalCount == 3,
    );
    await enqueue(
      'closeTab',
      target: 'tab:${thirdTab.id.value}',
      completed: () =>
          state.tabForId(thirdTab.id) == null &&
          nativePort.summary.tabCount == 2,
    );
    await enqueue(
      'closeWindow',
      target: 'window:${secondWindow.id.value}',
      completed: () =>
          state.windowForId(secondWindow.id) == null &&
          nativePort.summary.windowCount == 1,
    );
    final int stableGeneration = nativePort.summary.generation;
    await enqueue(
      'focus',
      target: 'terminal:${splitPaneId.value}',
      completed: () =>
          state.windowCount == 1 && state.tabCount == 1 && state.paneCount == 1,
    );
    _expectLifecycle(
      nativePort.summary.generation > stableGeneration,
      'stale target completion did not republish the stable cache',
    );

    session.applyEnabled(false);
    final TerminalAppleScriptNativeSummary disabled = nativePort.summary;
    _expectLifecycle(
      !disabled.enabled &&
          disabled.windowCount == 0 &&
          disabled.tabCount == 0 &&
          disabled.terminalCount == 0,
      'disabled scripting retained a visible native hierarchy',
    );
    final int rejectedBefore = disabled.rejectedCommandCount;
    final int disabledStatus = nativePort.enqueueSelfAutomationCommand(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'operationId': ++operationId,
            'kind': 'focus',
            'target': 'terminal:${firstPaneId.value}',
            'direction': null,
            'text': null,
          }),
        ),
      ),
    );
    _expectLifecycle(
      disabledStatus == 9,
      'disabled self-automation did not return the native disabled status',
    );
    _expectLifecycle(
      nativePort.summary.rejectedCommandCount == rejectedBefore + 1,
      'disabled command was not rejected exactly once',
    );
    session.applyEnabled(true);
    _expectLifecycle(
      nativePort.summary.enabled &&
          nativePort.summary.windowCount == 1 &&
          nativePort.summary.tabCount == 1 &&
          nativePort.summary.terminalCount == 1,
      're-enabled scripting did not restore the live standard hierarchy',
    );
    await enqueue(
      'focus',
      target: 'terminal:${firstPaneId.value}',
      completed: () => firstTab.focusedPaneId == firstPaneId,
    );

    final TerminalAppleScriptNativeSummary beforeQuit = nativePort.summary;
    _expectLifecycle(
      beforeQuit.resumedCommandCount == 10 &&
          beforeQuit.rejectedCommandCount == 1 &&
          allSessions.length == 4,
      'AppleScript native lifecycle counters differ before teardown',
    );
    await dispatcher.dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatcher.dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          session.isDisposed &&
          allSessions.every(
            (TerminalSession terminalSession) =>
                terminalSession.shutdownResult?.isClean == true,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'AppleScript product did not release all Dart and native owners',
    );
    stdout.writeln(
      'TERMINAL_APPLESCRIPT_TEST dictionary=true self_automation=true '
      'tcc_untouched=true stable_ids=true input_exact=true focus=true '
      'close_terminal=true close_tab=true close_window=true stale=true '
      'disable=true reenable=true resumed=10 rejected=1 sessions_clean=4 '
      'text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseNativeContentProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required Map<PaneId, _TerminalSelectionProductOwner> selections,
    required Map<PaneId, String?> launchWorkingDirectories,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required List<TerminalExternalPasteResult> pasteResults,
    required Map<PaneId, int> writeEnqueuedCounts,
    required List<String> quickLookTexts,
    required TerminalContextDockState contextDockState,
    required TerminalContextDockProcessController contextDockProcess,
    required TerminalSecureKeyboardEntryController secureKeyboardEntry,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalContextDockDirectoryController contextDockDirectory,
    required TerminalContextDockDirectoryPresenter contextDockPresenter,
    required TerminalContextDockPathHandoffController contextDockPathHandoff,
    required List<TerminalContextDockPathHandoffResult>
    contextDockPathHandoffResults,
    required _TerminalClipboard clipboard,
    required void Function() reconcile,
    required Completer<void> closed,
    required String prompt,
  }) async {
    const String lookupWord = 'NATIVECONTENTLOOKUP';
    const String serviceText = 'service-first\nservice-second';
    const String droppedText = 'DROPPED_TEXT_EXACT';
    var eventTimestamp = 91000000000;

    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    void injectViewEvent(
      _TerminalHierarchyProductPane owner,
      int version,
      int type,
      List<Object?> payload,
    ) {
      final int handle = appkit_testing.nativeViewHandleForTesting(owner.view);
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        version,
        type,
        handle,
        handle >> 32,
        eventTimestamp++,
        0,
        ...payload,
      ]);
    }

    Uint8List fileUrlPacket(Iterable<Uri> urls) {
      final BytesBuilder builder = BytesBuilder(copy: false);
      void addUint32(int value) {
        final ByteData data = ByteData(4)..setUint32(0, value, Endian.little);
        builder.add(data.buffer.asUint8List());
      }

      final List<Uint8List> encoded = urls
          .map((Uri url) => Uint8List.fromList(utf8.encode(url.toString())))
          .toList(growable: false);
      addUint32(encoded.length);
      for (final Uint8List value in encoded) {
        addUint32(value.length);
        builder.add(value);
      }
      return builder.takeBytes();
    }

    Future<void> prepareExactPasteReader(
      TerminalPane pane,
      TerminalSession session, {
      required String id,
      required String payload,
    }) async {
      final String expected = '\x1b[200~$payload\x1b[201~';
      final String encoded = base64Encode(utf8.encode(expected));
      pane.insertText(
        "stty -echo -icanon min 1 time 0; "
        "printf '\\033[?2004h\\r\\n__DT_NATIVE_%s__\\r\\n' "
        "'${id}_READY'; "
        "/usr/bin/perl -MMIME::Base64 -e 'binmode STDIN; "
        "my \$want=decode_base64(\$ARGV[0]); my \$got=\"\"; "
        "while (length(\$got) < length(\$want)) { "
        "my \$n=sysread(STDIN, my \$b, "
        "length(\$want)-length(\$got)); "
        "exit 42 unless defined(\$n) && \$n > 0; \$got .= \$b; } "
        "exit(\$got eq \$want ? 0 : 43);' '$encoded'; result=\$?; "
        "printf '\\033[?2004l'; stty echo icanon; "
        "if [ \$result -eq 0 ]; then "
        "printf '\\r\\n__DT_NATIVE_%s__\\r\\n' '${id}_EXACT'; "
        "else printf '\\r\\n__DT_NATIVE_%s__\\r\\n' "
        "'${id}_MISMATCH'; fi",
      );
      await pane.submit();
      await _waitForAsciiMarker(session, '__DT_NATIVE_${id}_READY__');
      _expectLifecycle(
        session.bracketedPasteMode,
        '$id fixture did not enable bracketed paste mode',
      );
    }

    Future<void> expectExactPaste(TerminalSession session, String id) async {
      await _waitForAsciiMarker(session, '__DT_NATIVE_${id}_EXACT__');
      _expectLifecycle(
        _findAscii(
              session.terminalScreenSet.activeScreen,
              '__DT_NATIVE_${id}_MISMATCH__',
            ) ==
            null,
        '$id did not preserve exact PTY paste bytes',
      );
    }

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'native content action ${id.stableName} did not execute: '
        '${result.disposition.name} ${result.error ?? ''}',
      );
    }

    final Directory fixtureRoot = await Directory.systemTemp.createTemp(
      'dart-terminal-native-content-',
    );
    try {
      final String fixtureRootPath = fixtureRoot.resolveSymbolicLinksSync();
      final Directory tabDirectory = Directory('$fixtureRootPath/service-tab')
        ..createSync();
      final Directory goToDirectory = Directory(
        '${tabDirectory.path}/go-to-folder',
      )..createSync();
      final File goToChild = File('${goToDirectory.path}/child.txt')
        ..writeAsStringSync('child');
      final Directory windowDirectory = Directory(
        '$fixtureRootPath/service-window',
      )..createSync();
      final File firstDroppedFile = File('$fixtureRootPath/drop one.txt')
        ..writeAsStringSync('one');
      final File secondDroppedFile = File("$fixtureRootPath/drop'2.txt")
        ..writeAsStringSync('two');
      final File hiddenFixtureFile = File(
        '$fixtureRootPath/.context-hidden.txt',
      )..writeAsStringSync('hidden');
      final Directory hiddenFixtureDirectory = Directory(
        '$fixtureRootPath/.context-hidden-directory',
      )..createSync();
      File('${hiddenFixtureDirectory.path}/inside.txt')
          .writeAsStringSync('inside');

      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 1 &&
            state.paneCount == 1 &&
            hierarchy.nativeWindowCount == 1 &&
            hierarchy.paneResourceCount == 1 &&
            sessions.length == 1 &&
            owners.length == 1,
        'native content product did not start from a 1/1/1 hierarchy',
      );
      final TerminalWindowState initialWindow = state.windows.single;
      final TerminalTabState initialTab = initialWindow.selectedTab;
      final PaneId initialPaneId = initialTab.focusedPaneId;
      final TerminalPane initialPane = state.paneForId(initialPaneId)!;
      final TerminalSession initialSession = sessions[initialPaneId]!;
      final _TerminalHierarchyProductPane initialOwner = owners[initialPaneId]!;
      final _TerminalSelectionProductOwner selection =
          selections[initialPaneId]!;
      await _waitForAsciiMarker(initialSession, prompt);

      final _MemoryTerminalClipboard contextDockClipboard =
          clipboard as _MemoryTerminalClipboard;
      final Window contextDockWindow = hierarchy.windowForTab(initialTab.id)!;
      if (!application.isActive) {
        appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
          application.eventProtocolVersion,
          30,
          0,
          0,
          eventTimestamp++,
          0,
          true,
        ]);
      }
      if (!contextDockWindow.isFocused) {
        _injectFocusEventForTesting(
          application,
          contextDockWindow,
          isFocused: true,
          monotonicNanoseconds: eventTimestamp++,
        );
      }
      await waitFor(
        () =>
            application.isActive &&
            contextDockWindow.isVisible &&
            contextDockWindow.isFocused,
        'native content window did not become the focused process-inspection '
        'target',
      );
      final String quotedFixtureRoot =
          TerminalExternalContentAdmission.filePaths(
            <String>[fixtureRootPath],
            maxFilePaths: 1,
            appendTrailingSeparator: false,
          ).content!.text;
      initialPane.insertText(
        "printf '\\033[?2004l\\r\\n__DT_NAV_%s__\\r\\n' SH_READY; "
        'stty echo icanon; exec /bin/sh -i',
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_NAV_SH_READY__');
      await waitFor(
        () => !initialSession.bracketedPasteMode,
        'plain local sh fixture retained zsh bracketed-paste mode',
      );
      await waitFor(() {
        final TerminalPaneProcessSnapshot process = initialPane
            .processSnapshot();
        return process.disposition == TerminalPaneProcessDisposition.idleShell;
      }, 'plain local sh did not expose an idle-shell boundary');
      initialPane.insertText(
        "cd $quotedFixtureRoot && "
        "printf '\\r\\n__DT_NAV_CWD_READY__\\r\\n'",
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_NAV_CWD_READY__');
      await waitFor(
        () =>
            initialSession.workingDirectorySnapshot()?.path == fixtureRootPath,
        'plain local sh cwd was not observable through the PTY capability',
      );
      reconcile();

      final int dockToggleWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      _expectLifecycle(
        dispatcher.catalog
                    .actionForId(TerminalActionId.toggleContextDock)!
                    .shortcut!
                    .identity ==
                'shift+option+c' &&
            dispatcher.catalog
                    .actionForId(TerminalActionId.toggleHiddenFiles)!
                    .shortcut!
                    .identity ==
                'shift+command+h',
        'Context Dock actions did not expose their default native shortcuts',
      );
      final TerminalPaneProcessSnapshot navigatorProcess = initialPane
          .processSnapshot();
      _expectLifecycle(
        dispatcher.snapshot(TerminalActionId.searchFilesAndFolders).isEnabled,
        'Context Dock search was unavailable after plain-sh reconcile: '
        'presenter=${contextDockPresenter.canFocusNavigator} '
        'process=${navigatorProcess.disposition.name} '
        'echo=${navigatorProcess.terminalEchoEnabled}',
      );
      _expectLifecycle(
        contextDockState.snapshotForWindow(initialWindow.id)?.isVisible ==
                true &&
            contextDockState.snapshotForWindow(initialWindow.id)?.width ==
                TerminalProductConfiguration.defaults.contextDockWidth &&
            !contextDockState
                .snapshotForWindow(initialWindow.id)!
                .navigatorOwnsInput,
        'default Context Dock visibility or width did not reach the native window',
      );
      await dispatch(TerminalActionId.toggleContextDock);
      _expectLifecycle(
        contextDockState.snapshotForWindow(initialWindow.id)?.isVisible ==
                false &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                dockToggleWriteBaseline,
        'default-visible Context Dock did not hide without writing to the PTY',
      );
      await dispatch(TerminalActionId.toggleContextDock);
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return dock?.isVisible == true &&
            dock!.inputOwner == TerminalContextDockInputOwner.terminal &&
            directory?.workingDirectory == fixtureRootPath &&
            directory!.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == secondDroppedFile.path,
            ) &&
            directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureFile.path,
            ) &&
            directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureDirectory.path,
            );
      }, 'Context Dock toggle did not project the real plain-sh cwd tree');
      _expectLifecycle(
        contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains('Mode: Terminal') &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains('Hidden entries: Shown') &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                dockToggleWriteBaseline,
        'Context Dock toggle did not preserve or identify terminal input '
        'ownership',
      );
      await dispatch(TerminalActionId.toggleHiddenFiles);
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return dock?.pane.showHiddenEntries == false &&
            dock!.inputOwner == TerminalContextDockInputOwner.terminal &&
            directory != null &&
            !directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureFile.path ||
                  row.entry.path == hiddenFixtureDirectory.path,
            );
      }, 'hidden-entry toggle did not filter the real plain-sh cwd tree');
      _expectLifecycle(
        contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains('Hidden entries: Hidden') &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                dockToggleWriteBaseline,
        'terminal-owned hidden-entry toggle changed focus or wrote to the PTY',
      );
      final int navigatorZeroWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      await dispatch(TerminalActionId.searchFilesAndFolders);
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return dock?.navigatorOwnsInput == true &&
            directory?.workingDirectory == fixtureRootPath &&
            directory!.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == secondDroppedFile.path,
            ) &&
            !directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureFile.path ||
                  row.entry.path == hiddenFixtureDirectory.path,
            );
      }, 'Context Dock did not project the real plain-sh cwd tree');
      await dispatch(TerminalActionId.toggleHiddenFiles);
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return dock?.pane.showHiddenEntries == true &&
            dock!.navigatorOwnsInput &&
            directory != null &&
            directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureFile.path,
            ) &&
            directory.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == hiddenFixtureDirectory.path,
            );
      }, 'Navigator-owned hidden-entry toggle did not restore dot entries');
      _expectLifecycle(
        contextDockWindow.keyEventRouting == KeyEventRouting.dartOnly &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)!
                    .isEditable ==
                true &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains('Hidden entries: Shown') &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                navigatorZeroWriteBaseline,
        'Navigator-owned hidden-entry toggle changed focus or wrote to the PTY',
      );
      final TerminalContextDockDirectorySnapshot treeBeforeToggle =
          contextDockDirectory.snapshotForWindow(initialWindow.id)!;
      final int treeRowCountBeforeToggle = treeBeforeToggle.rows.length;
      final String toggledFolderPath = treeBeforeToggle.rows.first.entry.path;
      _expectLifecycle(
        treeBeforeToggle.rows.first.isDirectory,
        'Context Dock product fixture did not select a folder for Return toggle',
      );
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: 0,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return directory?.rows.first.entry.path == toggledFolderPath &&
            directory!.rows.first.isExpanded;
      }, 'Return did not expand the selected Context Dock folder');
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: 0,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        return directory?.rows.length == treeRowCountBeforeToggle &&
            directory!.rows.first.entry.path == toggledFolderPath &&
            !directory.rows.first.isExpanded &&
            dock?.pane.selectedResultIndex == 0;
      }, 'second Return did not collapse and retain the selected folder');
      _expectLifecycle(
        (writeEnqueuedCounts[initialPaneId] ?? 0) == navigatorZeroWriteBaseline,
        'Return folder toggle wrote bytes to the terminal',
      );
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 2,
        modifiers: 0,
        characters: "drop'2",
        charactersIgnoringModifiers: "drop'2",
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return directory?.isSearch == true &&
            directory!.rows.length == 1 &&
            directory.rows.single.entry.path == secondDroppedFile.path;
      }, 'Context Dock query did not replace the tree with its local result');
      final TextEditorSnapshot navigatorEditor = contextDockPresenter
          .nativeEditorSnapshotForWindow(initialWindow.id)!;
      final String navigatorDetails = contextDockPresenter
          .nativeDetailsTextForWindow(initialWindow.id)!;
      _expectLifecycle(
        navigatorEditor.isEditable &&
            !navigatorEditor.hasMarkedText &&
            navigatorEditor.text.contains('Directory Navigator') &&
            navigatorEditor.text.contains('Mode: Search') &&
            navigatorEditor.text.contains("drop'2.txt") &&
            !navigatorEditor.text.contains(secondDroppedFile.path) &&
            navigatorDetails.contains(secondDroppedFile.path) &&
            navigatorDetails.contains("drop'2.txt") &&
            navigatorEditor.selection.start == navigatorEditor.selection.end &&
            contextDockWindow.keyEventRouting == KeyEventRouting.dartOnly &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                navigatorZeroWriteBaseline,
        'native Search did not expose its insertion caret, separate its '
        'scrollable results from pinned details, or preserve zero PTY writes',
      );
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: 0,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        final int selected = dock?.pane.selectedResultIndex ?? -1;
        return dock?.pane.navigatorMode ==
                TerminalContextDockNavigatorMode.move &&
            directory?.isSearch == false &&
            selected >= 0 &&
            directory!.rows[selected].entry.path == secondDroppedFile.path;
      }, 'Search Return did not reveal its current-root file in Move');
      _expectLifecycle(
        contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)!
                    .isEditable ==
                false &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                navigatorZeroWriteBaseline,
        'Search activation retained a caret in Move or wrote PTY bytes',
      );

      final int copyResultBaseline = contextDockPathHandoffResults.length;
      final int copyClipboardBaseline = contextDockClipboard.writeCount;
      await dispatch(TerminalActionId.copy);
      _expectLifecycle(
        contextDockPathHandoffResults.length == copyResultBaseline + 1 &&
            contextDockPathHandoffResults.last.disposition ==
                TerminalContextDockPathHandoffDisposition.copied &&
            contextDockClipboard.writeCount == copyClipboardBaseline + 1 &&
            contextDockClipboard.text == secondDroppedFile.path &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                navigatorZeroWriteBaseline &&
            contextDockState
                .snapshotForWindow(initialWindow.id)!
                .navigatorOwnsInput,
        'Copy Path did not preserve the exact raw path and zero-write focus',
      );

      initialPane.insertText('if [ -f ');
      final int insertionWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      final int insertionResultBaseline = contextDockPathHandoffResults.length;
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: ModifierKeys.optionBit,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(
        () =>
            contextDockPathHandoffResults.length == insertionResultBaseline + 1,
        'Option-Return path insertion did not settle',
      );
      _expectLifecycle(
        contextDockPathHandoffResults.last.disposition ==
                TerminalContextDockPathHandoffDisposition.inserted &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                insertionWriteBaseline + 1 &&
            contextDockState.snapshotForWindow(initialWindow.id)!.inputOwner ==
                TerminalContextDockInputOwner.terminal &&
            contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly,
        'Option-Return did not write exactly once and restore terminal focus',
      );
      initialPane.insertText(
        " ]; then printf '\\r\\n__DT_NAV_PATH_%s__\\r\\n' EXACT; "
        "else printf '\\r\\n__DT_NAV_PATH_%s__\\r\\n' MISMATCH; fi",
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_NAV_PATH_EXACT__');
      _expectLifecycle(
        _findAscii(
              initialSession.terminalScreenSet.activeScreen,
              '__DT_NAV_PATH_MISMATCH__',
            ) ==
            null,
        'inserted Navigator path did not survive shell-literal evaluation',
      );

      final int goToWriteBaseline = writeEnqueuedCounts[initialPaneId] ?? 0;
      await dispatch(TerminalActionId.goToFileOrFolder);
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 5,
        modifiers: 0,
        characters: 'go-to-folder',
        charactersIgnoringModifiers: 'go-to-folder',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        final int selected = dock?.pane.selectedResultIndex ?? -1;
        return dock?.pane.navigatorMode ==
                TerminalContextDockNavigatorMode.goTo &&
            directory?.isSearch == false &&
            selected >= 0 &&
            directory!.rows[selected].entry.path == goToDirectory.path &&
            !directory.rows[selected].isExpanded;
      }, 'Go To did not reveal its deep current-subtree directory');
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: 0,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(() {
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        return directory?.rows.any(
                  (TerminalContextDockDirectoryRow row) =>
                      row.entry.path == goToDirectory.path && row.isExpanded,
                ) ==
                true &&
            directory!.rows.any(
              (TerminalContextDockDirectoryRow row) =>
                  row.entry.path == goToChild.path,
            );
      }, 'Return did not expand the Go To directory and expose its child');
      _expectLifecycle(
        (writeEnqueuedCounts[initialPaneId] ?? 0) == goToWriteBaseline,
        'Go To reveal and folder expansion wrote bytes to the terminal',
      );

      await dispatch(TerminalActionId.searchFilesAndFolders);
      await waitFor(() {
        final TerminalContextDockWindowSnapshot? dock = contextDockState
            .snapshotForWindow(initialWindow.id);
        final TerminalContextDockDirectorySnapshot? directory =
            contextDockDirectory.snapshotForWindow(initialWindow.id);
        final int selected = dock?.pane.selectedResultIndex ?? -1;
        return directory?.isSearch == true &&
            selected >= 0 &&
            directory!.rows[selected].entry.path == secondDroppedFile.path;
      }, 'retained Search did not restore its selected path');
      initialSession.terminalScreenSet.setAlternateMode1049(true);
      reconcile();
      final int alternateResultBaseline = contextDockPathHandoffResults.length;
      final int alternateWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 36,
        modifiers: ModifierKeys.optionBit,
        characters: '\r',
        charactersIgnoringModifiers: '\r',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(
        () =>
            contextDockPathHandoffResults.length == alternateResultBaseline + 1,
        'alternate-screen insertion rejection did not settle',
      );
      _expectLifecycle(
        contextDockPathHandoffResults.last.disposition ==
                TerminalContextDockPathHandoffDisposition.unavailable &&
            contextDockPathHandoffResults.last.block ==
                TerminalContextDockPathInsertionBlock.alternateScreen &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == alternateWriteBaseline,
        'alternate-screen Navigator insertion was not a zero-write rejection',
      );
      initialSession.terminalScreenSet.setAlternateMode1049(false);
      await dispatch(TerminalActionId.focusTerminal);

      String? processDocumentText() => contextDockPresenter
          .nativeEditorSnapshotForWindow(initialWindow.id)
          ?.text;

      initialPane.insertText(
        "/bin/sh -c 'printf \"%s%s\\n\" __DT_PROCESS_ PIPE_READY__; "
        "sleep 4; printf \"%s%s\\n\" __DT_PROCESS_ PIPE_DONE__' | "
        '/bin/cat',
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_PROCESS_PIPE_READY__');
      await waitFor(() {
        final TerminalContextDockContentSnapshot? content = contextDockProcess
            .snapshotForWindow(initialWindow.id);
        final String? list = contextDockPresenter
            .nativeEditorSnapshotForWindow(initialWindow.id)
            ?.text;
        return content?.mode == TerminalContextDockContentMode.foregroundJob &&
            content?.process?.status ==
                TerminalContextDockProcessStatus.ready &&
            (content?.process?.totalMemberCount ?? 0) >= 2 &&
            content?.process?.executablePath?.startsWith('/') == true &&
            content!.process!.arguments.any(
              (String argument) =>
                  argument.contains('__DT_PROCESS_') &&
                  argument.contains('PIPE_READY__'),
            ) &&
            list?.contains('Process Inspector') == true &&
            list?.contains('Foreground job') == true &&
            !list!.contains('Working directory:') &&
            !list.contains('Directory Navigator is available') &&
            !list.contains('Each quoted token is') &&
            !list.contains('Process details') &&
            contextDockPresenter.nativeDetailsTextForWindow(initialWindow.id) ==
                '' &&
            contextDockPresenter.nativeProcessUsesFullHeightForWindow(
              initialWindow.id,
            ) &&
            list.contains('Command (process argv)') &&
            list.contains('Executable') &&
            list.contains('PGID') &&
            list.contains('__DT_PROCESS_') &&
            list.contains('PIPE_READY__');
      }, 'real pipeline did not reach the Process Inspector document');
      final TerminalContextDockContentSnapshot pipelineBefore =
          contextDockProcess.snapshotForWindow(initialWindow.id)!;
      final int pipelineElapsedBefore =
          pipelineBefore.process!.elapsedMicroseconds;
      final int processSelectionBefore = contextDockPresenter
          .nativeEditorSnapshotForWindow(initialWindow.id)!
          .selection
          .start;
      final int argumentsWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      final MenuItem argumentsItem = menu.itemForAction(
        TerminalActionId.toggleProcessArguments,
      );
      menu.refresh();
      _expectLifecycle(
        argumentsItem.isChecked,
        'process argv was not shown by default',
      );
      argumentsItem.performAction();
      await waitFor(
        () => !contextDockProcess.argumentsVisible && !argumentsItem.isChecked,
        'native menu did not hide process arguments',
      );
      _expectLifecycle(
        contextDockProcess
                    .snapshotForWindow(initialWindow.id)
                    ?.process
                    ?.arguments
                    .isEmpty ==
                true &&
            processDocumentText()?.contains('Arguments are hidden') == true &&
            !processDocumentText()!.contains('PIPE_READY__') &&
            processDocumentText()!.contains('Executable') &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == argumentsWriteBaseline,
        'hiding process argv retained argument text or wrote to the PTY',
      );
      await palette.open();
      palette
        ..refresh()
        ..state.setQuery('process arguments')
        ..refresh();
      _expectLifecycle(
        palette.state.selectedAction?.definition.id ==
                TerminalActionId.toggleProcessArguments &&
            palette.state.selectedAction!.isEnabled,
        'command palette did not expose the shared process argv display action',
      );
      final TerminalActionDispatchResult argumentsResult = await palette.state
          .invokeSelected();
      await palette.dismiss();
      menu.refresh();
      _expectLifecycle(
        argumentsResult.disposition ==
                TerminalActionDispatchDisposition.executed &&
            argumentsItem.isChecked,
        'command palette did not restore process argument visibility',
      );
      await waitFor(
        () => processDocumentText()?.contains('PIPE_READY__') == true,
        'revealing process argv did not obtain a fresh native document',
      );
      _expectLifecycle(
        !contextDockState
                .snapshotForWindow(initialWindow.id)!
                .navigatorOwnsInput &&
            contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == argumentsWriteBaseline,
        'process argument visibility changed terminal input ownership or wrote to the PTY',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      reconcile();
      final TerminalContextDockContentSnapshot pipelineAfter =
          contextDockProcess.snapshotForWindow(initialWindow.id)!;
      _expectLifecycle(
        pipelineAfter.process!.elapsedMicroseconds > pipelineElapsedBefore &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)!
                    .selection
                    .start ==
                processSelectionBefore &&
            contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly,
        'Process Inspector elapsed did not advance without disturbing terminal input',
      );
      final int processShortcutWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      await dispatch(TerminalActionId.searchFilesAndFolders);
      _expectLifecycle(
        contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.foregroundJob &&
            !contextDockState
                .snapshotForWindow(initialWindow.id)!
                .navigatorOwnsInput &&
            contextDockWindow.keyEventRouting == KeyEventRouting.appKitOnly &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                processShortcutWriteBaseline,
        'Process Inspector Navigator shortcut changed focus or wrote to the PTY',
      );
      await _waitForAsciiMarker(initialSession, '__DT_PROCESS_PIPE_DONE__');
      await waitFor(() {
        contextDockProcess.synchronize();
        reconcile();
        return contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.directoryNavigator &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)
                    ?.text
                    .contains('Directory Navigator') ==
                true &&
            !contextDockPresenter.nativeProcessUsesFullHeightForWindow(
              initialWindow.id,
            ) &&
            contextDockPresenter
                    .nativeDetailsTextForWindow(initialWindow.id)
                    ?.contains('Path actions') ==
                true;
      }, 'finished pipeline did not restore a fresh Directory Navigator');

      initialPane.insertText('/bin/cat');
      await initialPane.submit();
      await waitFor(() {
        final TerminalContextDockContentSnapshot? content = contextDockProcess
            .snapshotForWindow(initialWindow.id);
        return content?.mode == TerminalContextDockContentMode.foregroundJob &&
            content?.process?.executablePath?.endsWith('/cat') == true;
      }, 'interactive foreground process was not inspected');
      initialPane.sendInput(utf8.encode('__DT_PROCESS_INPUT_EXACT__\n'));
      await _waitForAsciiMarker(initialSession, '__DT_PROCESS_INPUT_EXACT__');
      initialPane.sendEndOfFile();
      await waitFor(() {
        contextDockProcess.synchronize();
        return initialPane.processSnapshot().disposition ==
                TerminalPaneProcessDisposition.idleShell &&
            contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.directoryNavigator;
      }, 'interactive process input did not return to the shell');

      initialPane.insertText(
        "printf '\\033]133;C\\007'; read dt_process_value; "
        "printf '\\033]133;D;0\\007\\r\\n__DT_SHELL_OWNED_DONE__\\r\\n'",
      );
      await initialPane.submit();
      await waitFor(() {
        final TerminalContextDockContentSnapshot? content = contextDockProcess
            .snapshotForWindow(initialWindow.id);
        final String? list = contextDockPresenter
            .nativeEditorSnapshotForWindow(initialWindow.id)
            ?.text;
        return content?.mode ==
                TerminalContextDockContentMode.shellOwnedCommand &&
            content?.process?.executablePath == null &&
            content?.process?.arguments.isEmpty == true &&
            list?.contains('Shell command running') == true;
      }, 'OSC 133 shell-owned command did not use the content-free status');
      initialPane.sendInput(utf8.encode('done\n'));
      await _waitForAsciiMarker(initialSession, '__DT_SHELL_OWNED_DONE__');
      await waitFor(() {
        contextDockProcess.synchronize();
        reconcile();
        return initialPane.processSnapshot().disposition ==
                TerminalPaneProcessDisposition.idleShell &&
            contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.directoryNavigator &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)
                    ?.text
                    .contains('Directory Navigator') ==
                true;
      }, 'shell-owned command did not restore Directory Navigator');

      initialPane.insertText(
        "/usr/bin/true; printf '\\r\\n__DT_PROCESS_%s__\\r\\n' SHORT_DONE",
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_PROCESS_SHORT_DONE__');
      await waitFor(() {
        contextDockProcess.synchronize();
        reconcile();
        return initialPane.processSnapshot().disposition ==
                TerminalPaneProcessDisposition.idleShell &&
            contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.directoryNavigator &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)
                    ?.text
                    .contains('Process Inspector') ==
                false;
      }, 'rapid command flickered into a retained Process Inspector document');

      initialPane.insertText(
        "stty -echo; printf '\\r\\n__DT_NAV_ECHO_OFF__\\r\\n'; "
        "sleep 4; stty echo; printf '\\r\\n__DT_NAV_ECHO_ON__\\r\\n'",
      );
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, '__DT_NAV_ECHO_OFF__');
      await waitFor(() {
        final TerminalPaneProcessSnapshot process = initialPane
            .processSnapshot();
        return process.terminalEchoEnabled == false &&
            process.disposition ==
                TerminalPaneProcessDisposition.foregroundProcess;
      }, 'foreground command did not expose the ECHO-off input boundary');
      reconcile();
      contextDockProcess.synchronize();
      contextDockDirectory.synchronize();
      await waitFor(() {
        final TerminalContextDockContentSnapshot? content = contextDockProcess
            .snapshotForWindow(initialWindow.id);
        return content?.mode == TerminalContextDockContentMode.foregroundJob &&
            content?.process?.executablePath?.endsWith('/sleep') == true &&
            processDocumentText()?.contains('Command (process argv)') == true;
      }, 'ECHO-off command did not retain the read-only Process Inspector');
      await dispatch(TerminalActionId.toggleSecureKeyboardEntry);
      reconcile();
      contextDockProcess.synchronize();
      await waitFor(() {
        reconcile();
        return secureKeyboardEntry.manualRequested &&
            secureKeyboardEntry.status.ownedEnabled;
      }, 'Process Inspector disabled manual Secure Keyboard Entry protection');
      final int secureProcessWriteBaseline =
          writeEnqueuedCounts[initialPaneId] ?? 0;
      await dispatch(TerminalActionId.searchFilesAndFolders);
      final TerminalContextDockDirectorySnapshot protectedDirectory =
          contextDockDirectory.snapshotForWindow(initialWindow.id)!;
      _expectLifecycle(
        contextDockProcess.snapshotForWindow(initialWindow.id)?.mode ==
                TerminalContextDockContentMode.foregroundJob &&
            contextDockPresenter
                    .nativeEditorSnapshotForWindow(initialWindow.id)
                    ?.text
                    .contains('Protected input') ==
                false &&
            processDocumentText()!.contains('/sleep') &&
            !contextDockState
                .snapshotForWindow(initialWindow.id)!
                .navigatorOwnsInput &&
            protectedDirectory.status ==
                TerminalContextDockDirectoryStatus.privacyUnavailable &&
            protectedDirectory.workingDirectory == null &&
            protectedDirectory.rows.isEmpty &&
            contextDockDirectory.activeOperationCount == 0 &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) ==
                secureProcessWriteBaseline,
        'manual secure input hid process metadata or enabled Navigator input',
      );
      await dispatch(TerminalActionId.toggleSecureKeyboardEntry);

      await _waitForAsciiMarker(initialSession, '__DT_NAV_ECHO_ON__');
      await waitFor(
        () =>
            initialPane.processSnapshot().disposition ==
            TerminalPaneProcessDisposition.idleShell,
        'plain sh did not restore the idle-shell Navigator boundary',
      );
      contextDockProcess.synchronize();
      reconcile();
      await dispatch(TerminalActionId.searchFilesAndFolders);
      await waitFor(
        () => contextDockState
            .snapshotForWindow(initialWindow.id)!
            .navigatorOwnsInput,
        'Navigator focus did not recover after ECHO-off process exit',
      );
      final int focusWriteBaseline = writeEnqueuedCounts[initialPaneId] ?? 0;
      _injectKeyEventForTesting(
        application,
        contextDockWindow,
        keyCode: 53,
        modifiers: 0,
        characters: '\u001b',
        charactersIgnoringModifiers: '\u001b',
        monotonicNanoseconds: eventTimestamp++,
      );
      await waitFor(
        () =>
            contextDockState.snapshotForWindow(initialWindow.id)!.inputOwner ==
            TerminalContextDockInputOwner.terminal,
        'Navigator Escape did not restore terminal input ownership',
      );
      _expectLifecycle(
        contextDockState.snapshotForWindow(initialWindow.id)!.pane.query ==
                "drop'2" &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains('Mode: Terminal') &&
            contextDockPresenter
                .nativeEditorSnapshotForWindow(initialWindow.id)!
                .text
                .contains("Search: drop'2") &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == focusWriteBaseline,
        'Navigator focus round-trip did not identify terminal mode, lost the '
        'query, or wrote PTY bytes',
      );

      initialPane.insertText("printf '\\r\\nNATIVE%s\\r\\n' 'CONTENTLOOKUP'");
      await initialPane.submit();
      await _waitForAsciiMarker(initialSession, lookupWord);

      final TerminalAppKitContextMenuProjection contextMenu =
          initialOwner.contextMenu!;
      _expectLifecycle(
        initialOwner.view.quickLookRequestsEnabled &&
            initialOwner.view.dropDestination != null &&
            initialOwner.view.servicesTextRequestor != null &&
            contextMenu.isAttached &&
            identical(initialOwner.view.contextMenu, contextMenu.menu),
        'live pane omitted a native content adapter',
      );
      final _TerminalAsciiPosition lookupPosition = _findAscii(
        initialSession.terminalScreenSet.activeScreen,
        lookupWord,
      )!;
      final TerminalPaneLayoutRect content = initialOwner.contentLayout!;
      final TerminalFontCatalogMetrics metrics =
          initialOwner.surface.fontMetrics;
      final Window nativeWindow = hierarchy.windowForTab(initialTab.id)!;
      double xForColumn(int column) =>
          content.left + (column + 0.5) * metrics.cellWidth;
      final double lookupY =
          content.top + (lookupPosition.row + 0.5) * metrics.cellHeight;
      final int selectionGeneration = selection.gesture.snapshot.generation;
      for (final (AppKitMouseEventKind kind, int column)
          in <(AppKitMouseEventKind, int)>[
            (AppKitMouseEventKind.down, lookupPosition.column),
            (
              AppKitMouseEventKind.dragged,
              lookupPosition.column + lookupWord.length - 1,
            ),
            (
              AppKitMouseEventKind.up,
              lookupPosition.column + lookupWord.length - 1,
            ),
          ]) {
        _injectMouseEventForTesting(
          application,
          nativeWindow,
          kind: kind,
          x: xForColumn(column),
          y: lookupY,
          button: 0,
          modifiers: 0,
          clickCount: 1,
          monotonicNanoseconds: eventTimestamp++,
        );
      }
      await _waitForSelectionGeneration(selection, selectionGeneration + 3);
      _expectLifecycle(
        selection.selectedText()?.text == lookupWord &&
            initialOwner.view.servicesTextRequestor?.selectionText ==
                lookupWord,
        'Services did not receive the exact bounded native selection snapshot',
      );

      final int contextSelectionGeneration =
          selection.gesture.snapshot.generation;
      final int contextWriteBaseline = writeEnqueuedCounts[initialPaneId] ?? 0;
      for (final AppKitMouseEventKind kind in <AppKitMouseEventKind>[
        AppKitMouseEventKind.down,
        AppKitMouseEventKind.dragged,
        AppKitMouseEventKind.up,
      ]) {
        _injectMouseEventForTesting(
          application,
          nativeWindow,
          kind: kind,
          x: xForColumn(lookupPosition.column),
          y: lookupY,
          button: 1,
          modifiers: 0,
          clickCount: 1,
          monotonicNanoseconds: eventTimestamp++,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _expectLifecycle(
        selection.gesture.snapshot.generation == contextSelectionGeneration &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == contextWriteBaseline &&
            selection.selectedText()?.text == lookupWord,
        'native context gesture reached selection or PTY input routing',
      );

      injectViewEvent(initialOwner, 9, 42, <Object?>[
        xForColumn(lookupPosition.column) - initialOwner.layout!.left,
        lookupY - initialOwner.layout!.top,
      ]);
      await waitFor(
        () => quickLookTexts.length == 1,
        'pressure Quick Look did not reach native definition presentation',
      );
      _expectLifecycle(
        quickLookTexts.single == lookupWord,
        'pressure Quick Look resolved the wrong terminal word',
      );

      for (final AppKitMouseEventKind kind in <AppKitMouseEventKind>[
        AppKitMouseEventKind.down,
        AppKitMouseEventKind.up,
      ]) {
        _injectMouseEventForTesting(
          application,
          nativeWindow,
          kind: kind,
          x: xForColumn(lookupPosition.column),
          y: lookupY,
          button: 1,
          modifiers: 0,
          clickCount: 1,
          monotonicNanoseconds: eventTimestamp++,
        );
      }
      contextMenu.refresh();
      _expectLifecycle(
        contextMenu.itemForAction(TerminalActionId.quickLook).isEnabled,
        'context Quick Look was not enabled at menu-open time',
      );
      final int contextInvocationBaseline = nativeActionInvocations.length;
      final int contextDispatchBaseline = actionDispatches.length;
      contextMenu.itemForAction(TerminalActionId.quickLook).performAction();
      await waitFor(
        () =>
            nativeActionInvocations.length == contextInvocationBaseline + 1 &&
            actionDispatches.length == contextDispatchBaseline + 1,
        'context Quick Look did not reach the shared action dispatcher',
      );
      _expectLifecycle(
        nativeActionInvocations.last == TerminalActionId.quickLook &&
            actionDispatches.last.id == TerminalActionId.quickLook &&
            actionDispatches.last.disposition ==
                TerminalActionDispatchDisposition.executed,
        'context Quick Look recorded a divergent action result: '
        '${actionDispatches.last.disposition.name}',
      );
      await waitFor(
        () => quickLookTexts.length == 2,
        'context Quick Look action did not present its definition',
      );

      contextMenu
          .itemForAction(TerminalActionId.splitPaneRight)
          .performAction();
      await waitFor(
        () =>
            state.paneCount == 2 &&
            sessions.length == 2 &&
            hierarchy.paneResourceCount == 2 &&
            actionDispatches.last.id == TerminalActionId.splitPaneRight,
        'context Split Right did not create one shared-action pane',
      );
      final PaneId splitPaneId = initialTab.focusedPaneId;
      _expectLifecycle(
        splitPaneId != initialPaneId &&
            nativeActionInvocations.last == TerminalActionId.splitPaneRight &&
            actionDispatches.last.disposition ==
                TerminalActionDispatchDisposition.executed,
        'context Split Right did not retain native invocation ownership',
      );
      await dispatch(TerminalActionId.closeWindow);
      await waitFor(
        () =>
            state.paneCount == 1 &&
            sessions.length == 1 &&
            owners.length == 1 &&
            hierarchy.paneResourceCount == 1 &&
            allSessions.length == 2 &&
            sessions.containsKey(initialPaneId),
        'Close did not remove only the focused split pane',
      );
      _expectLifecycle(
        allSessions
                .singleWhere(
                  (TerminalSession session) => session.id.paneId == splitPaneId,
                )
                .shutdownResult
                ?.isClean ==
            true,
        'Close did not cleanly release the split session',
      );

      await prepareExactPasteReader(
        initialPane,
        initialSession,
        id: 'SERVICE',
        payload: serviceText,
      );
      final int serviceResultBaseline = pasteResults.length;
      final int serviceWriteBaseline = writeEnqueuedCounts[initialPaneId] ?? 0;
      final Uint8List serviceBytes = Uint8List.fromList(
        utf8.encode(serviceText),
      );
      injectViewEvent(initialOwner, 10, 43, <Object?>[serviceBytes]);
      await waitFor(
        () => pasteResults.length == serviceResultBaseline + 1,
        'Services text did not settle its confirmation result',
      );
      _expectLifecycle(
        pasteResults.last.disposition ==
                TerminalExternalPasteDisposition.confirmationRequired &&
            (writeEnqueuedCounts[initialPaneId] ?? 0) == serviceWriteBaseline &&
            initialTab.focusedPaneId == initialPaneId,
        'first risky Services delivery wrote bytes or failed to focus target',
      );
      injectViewEvent(initialOwner, 10, 43, <Object?>[serviceBytes]);
      await waitFor(
        () => pasteResults.length == serviceResultBaseline + 2,
        'repeated Services approval did not settle',
      );
      _expectLifecycle(
        pasteResults.last.disposition ==
            TerminalExternalPasteDisposition.completed,
        'repeated risky Services delivery did not approve',
      );
      await expectExactPaste(initialSession, 'SERVICE');

      await prepareExactPasteReader(
        initialPane,
        initialSession,
        id: 'DROP_TEXT',
        payload: droppedText,
      );
      final int dropTextBaseline = pasteResults.length;
      injectViewEvent(initialOwner, 11, 44, <Object?>[
        0,
        20.0,
        20.0,
        Uint8List.fromList(utf8.encode(droppedText)),
      ]);
      await waitFor(
        () => pasteResults.length == dropTextBaseline + 1,
        'plain-text drop did not settle',
      );
      _expectLifecycle(
        pasteResults.last.disposition ==
            TerminalExternalPasteDisposition.completed,
        'plain-text drop did not use ordinary paste transport',
      );
      await expectExactPaste(initialSession, 'DROP_TEXT');

      final List<String> droppedPaths = <String>[
        firstDroppedFile.path,
        secondDroppedFile.path,
      ];
      final String serializedPaths = TerminalExternalContentAdmission.filePaths(
        droppedPaths,
      ).content!.text;
      await prepareExactPasteReader(
        initialPane,
        initialSession,
        id: 'DROP_FILES',
        payload: serializedPaths,
      );
      final int dropFilesBaseline = pasteResults.length;
      injectViewEvent(initialOwner, 11, 44, <Object?>[
        1,
        25.0,
        25.0,
        fileUrlPacket(droppedPaths.map(Uri.file)),
      ]);
      await waitFor(
        () => pasteResults.length == dropFilesBaseline + 1,
        'file-URL drop did not settle',
      );
      _expectLifecycle(
        pasteResults.last.disposition ==
            TerminalExternalPasteDisposition.completed,
        'file-URL drop did not use shell-quoted paste transport',
      );
      await expectExactPaste(initialSession, 'DROP_FILES');

      final int folderSessionBaseline = allSessions.length;
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        12,
        45,
        0,
        0,
        eventTimestamp++,
        0,
        0,
        fileUrlPacket(<Uri>[Uri.file('${tabDirectory.path}/')]),
      ]);
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        12,
        45,
        0,
        0,
        eventTimestamp++,
        0,
        1,
        fileUrlPacket(<Uri>[Uri.file('${windowDirectory.path}/')]),
      ]);
      await waitFor(
        () =>
            state.windowCount == 2 &&
            state.tabCount == 3 &&
            state.paneCount == 3 &&
            allSessions.length == folderSessionBaseline + 2 &&
            hierarchy.nativeWindowCount == 3 &&
            hierarchy.paneResourceCount == 3,
        'folder Services did not serialize one tab and one window creation',
      );
      _expectLifecycle(
        launchWorkingDirectories.values.contains('${tabDirectory.path}/') &&
            launchWorkingDirectories.values.contains(
              '${windowDirectory.path}/',
            ),
        'folder Services did not preserve exact trusted working directories',
      );

      await dispatch(TerminalActionId.quitApplication);
      await closed.future;
      _expectLifecycle(
        state.isDisposed &&
            hierarchy.isDisposed &&
            contextDockProcess.isDisposed &&
            contextDockProcess.activeOperationCount == 0 &&
            contextDockProcess.activeTimerCount == 0 &&
            allSessions.length == 4 &&
            allSessions.every(
              (TerminalSession session) =>
                  session.shutdownResult?.isClean == true,
            ) &&
            debugLiveTerminalTextInputClientCount() == 0 &&
            application.debugLiveObjectCount == 0,
        'native content Quit did not release all sessions and native owners',
      );
      stdout.writeln(
        'TERMINAL_NATIVE_CONTENT_TEST context=true mouse_zero_write=true '
        'navigator_tree=true navigator_search=true navigator_copy=true '
        'navigator_insert=true navigator_zero_write=true '
        'navigator_privacy=true navigator_accessibility=true '
        'process_inspector=true process_pipeline=true process_input=true '
        'process_shell_owned=true process_short=true process_elapsed=true '
        'quick_look=true services_selection=true service_confirmation=true '
        'service_exact=true drop_text_exact=true drop_files_exact=true '
        'folder_tabs=true folder_windows=true cwd_exact=true focus=true '
        'close=true sessions_clean=4 text_clients=0 native_handles=0',
      );
    } finally {
      if (fixtureRoot.existsSync()) {
        fixtureRoot.deleteSync(recursive: true);
      }
    }
  }

  static Future<void> _exerciseOsc52Product({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalOsc52ConfirmationPresenter confirmation,
    required TerminalOsc52Coordinator coordinator,
    required _MemoryTerminalOsc52Clipboard clipboard,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'OSC 52 product did not start from a 1/1/1 hierarchy',
    );
    final PaneId paneId = state.windows.single.selectedTab.focusedPaneId;
    final TerminalSession session = sessions[paneId]!;
    final _TerminalHierarchyProductPane owner = owners[paneId]!;
    await _waitForAsciiMarker(session, prompt);
    coordinator.setApplicationActive(true);
    final int nativeBaseline = application.debugLiveObjectCount;
    final TerminalScreenParserSink sink = session.terminalParserSink;
    final int acceptedReads = sink.acceptedClipboardReadCount;
    final int acceptedWrites = sink.acceptedClipboardWriteCount;
    final int acceptedClears = sink.acceptedClipboardClearCount;
    const String writeText = 'runtime-write';
    clipboard.seed('runtime-sentinel');
    final int preWriteChangeCount = clipboard.changeCount;
    final String writeEncoded = base64Encode(ascii.encode(writeText));

    owner.pane.insertText("printf '\\033]52;c;$writeEncoded\\007'");
    await owner.pane.submit();
    await waitFor(
      () =>
          coordinator.pendingRequest?.request.operation ==
              TerminalOsc52Operation.write &&
          confirmation.isOpen &&
          application.debugLiveObjectCount == nativeBaseline + 2,
      'real PTY write did not open one bounded native confirmation',
    );
    final TerminalOsc52PendingRequest writePending =
        coordinator.pendingRequest!;
    final MenuItem allowItem = menu.itemForAction(
      TerminalActionId.allowOsc52Clipboard,
    );
    _expectLifecycle(
      writePending.writeText == writeText &&
          writePending.pasteboardChangeCount == preWriteChangeCount &&
          confirmation.renderedText!.contains('"runtime-write"') &&
          allowItem.isEnabled &&
          dispatcher.snapshot(TerminalActionId.allowOsc52Clipboard).isEnabled &&
          clipboard.text == 'runtime-sentinel' &&
          clipboard.writeCount == 0,
      'write confirmation did not retain exact text and zero pre-approval authority',
    );
    allowItem.performAction();
    await waitFor(
      () =>
          coordinator.pendingRequest == null &&
          !confirmation.isOpen &&
          clipboard.text == writeText &&
          clipboard.writeCount == 1 &&
          application.debugLiveObjectCount == nativeBaseline,
      'native Edit action did not approve and release the exact write request',
    );

    const String readText = 'runtime-read';
    clipboard.seed(readText);
    final String readEncoded = base64Encode(ascii.encode(readText));
    const String readExact = '__DT_OSC52_READ_EXACT__';
    const String readMismatch = '__DT_OSC52_READ_MISMATCH__';
    owner.pane.insertText(
      "stty -echo -icanon min 1 time 0; "
      "printf '\\033]52;c;?\\007'; "
      "/usr/bin/perl -e 'binmode STDIN; my \$want=\"\\e]52;c;$readEncoded\\a\"; "
      "my \$got=\"\"; while (length(\$got) < length(\$want)) { "
      "my \$n=sysread(STDIN, my \$b, length(\$want)-length(\$got)); "
      "exit 42 unless defined(\$n) && \$n > 0; \$got .= \$b; } "
      "exit(\$got eq \$want ? 0 : 43);'; result=\$?; "
      "stty echo icanon; if [ \$result -eq 0 ]; then "
      "printf '\\r\\n%s%s\\r\\n' '__DT_OSC52_READ_' 'EXACT__'; else "
      "printf '\\r\\n%s%s\\r\\n' '__DT_OSC52_READ_' 'MISMATCH__'; fi",
    );
    await owner.pane.submit();
    await waitFor(
      () =>
          coordinator.pendingRequest?.request.operation ==
              TerminalOsc52Operation.read &&
          confirmation.isOpen &&
          clipboard.readCount == 0,
      'real PTY read did not stop before pasteboard access',
    );
    await palette.open();
    palette
      ..refresh()
      ..state.setQuery('allow osc 52 clipboard')
      ..refresh();
    _expectLifecycle(
      palette.state.selectedAction?.definition.id ==
              TerminalActionId.allowOsc52Clipboard &&
          palette.state.selectedAction!.isEnabled &&
          application.debugLiveObjectCount == nativeBaseline + 4,
      'command palette did not expose the exact pending OSC 52 approval',
    );
    final TerminalActionDispatchResult readApproval = await palette.state
        .invokeSelected();
    await palette.dismiss();
    await waitFor(
      () =>
          readApproval.disposition ==
              TerminalActionDispatchDisposition.executed &&
          coordinator.pendingRequest == null &&
          !confirmation.isOpen &&
          !palette.isOpen &&
          clipboard.readCount == 1 &&
          application.debugLiveObjectCount == nativeBaseline,
      'command palette did not approve one read and release transient owners',
    );
    await _waitForAsciiMarker(session, readExact);
    _expectLifecycle(
      _findAscii(session.terminalScreenSet.activeScreen, readMismatch) == null,
      'real PTY did not receive the exact approved OSC 52 read reply',
    );

    owner.pane.insertText("printf '\\033]52;c;!\\007'");
    await owner.pane.submit();
    await waitFor(
      () =>
          coordinator.pendingRequest?.request.operation ==
              TerminalOsc52Operation.clear &&
          confirmation.isOpen,
      'real PTY clear did not open an exact confirmation',
    );
    final MenuItem denyItem = menu.itemForAction(
      TerminalActionId.denyOsc52Clipboard,
    );
    _expectLifecycle(
      denyItem.isEnabled && clipboard.clearCount == 0,
      'clear denial action was unavailable or mutated before invocation',
    );
    denyItem.performAction();
    await waitFor(
      () =>
          coordinator.pendingRequest == null &&
          !confirmation.isOpen &&
          clipboard.clearCount == 0 &&
          clipboard.text == readText &&
          application.debugLiveObjectCount == nativeBaseline,
      'native Edit action did not deny clear without pasteboard mutation',
    );

    final TerminalOsc52ProjectionMetrics beforeShutdown = coordinator.metrics;
    final List<TerminalActionDispatchResult> osc52ActionDispatches =
        actionDispatches
            .where((TerminalActionDispatchResult result) {
              return result.id == TerminalActionId.allowOsc52Clipboard ||
                  result.id == TerminalActionId.denyOsc52Clipboard;
            })
            .toList(growable: false);
    _expectLifecycle(
      sink.acceptedClipboardReadCount == acceptedReads + 1 &&
          sink.acceptedClipboardWriteCount == acceptedWrites + 1 &&
          sink.acceptedClipboardClearCount == acceptedClears + 1 &&
          beforeShutdown.pendingRequestCount == 3 &&
          beforeShutdown.approvedRequestCount == 2 &&
          beforeShutdown.deniedRequestCount == 1 &&
          beforeShutdown.busyRequestCount == 0 &&
          beforeShutdown.staleRequestCount == 0 &&
          beforeShutdown.invalidTextRequestCount == 0 &&
          beforeShutdown.clipboardFailureCount == 0 &&
          beforeShutdown.replyFailureCount == 0 &&
          beforeShutdown.trackedSessionCount == 1 &&
          nativeActionInvocations
                  .where((TerminalActionId id) {
                    return id == TerminalActionId.allowOsc52Clipboard ||
                        id == TerminalActionId.denyOsc52Clipboard;
                  })
                  .join(',') ==
              <TerminalActionId>[
                TerminalActionId.allowOsc52Clipboard,
                TerminalActionId.denyOsc52Clipboard,
              ].join(',') &&
          osc52ActionDispatches.length == 2 &&
          osc52ActionDispatches.every(
            (TerminalActionDispatchResult result) =>
                result.disposition ==
                TerminalActionDispatchDisposition.executed,
          ) &&
          confirmation.terminalResponderRestoreCount == 3,
      'OSC 52 runtime policy, action, or ownership counters differ',
    );

    await dispatcher.dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatcher.dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    final TerminalOsc52ProjectionMetrics afterShutdown = coordinator.metrics;
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          coordinator.isDisposed &&
          confirmation.isDisposed &&
          afterShutdown.trackedSessionCount == 0 &&
          allSessions.length == 1 &&
          allSessions.single.shutdownResult?.isClean == true &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'OSC 52 product did not release PTY, coordinator, or native owners',
    );
    stdout.writeln(
      'TERMINAL_OSC52_TEST real_pty=true safe_memory_adapter=true '
      'ask_write_menu_allow=true ask_read_palette_allow=true '
      'ask_clear_menu_deny=true exact_reply=true preapproval_zero=true '
      'pending=3 approved=2 denied=1 clipboard_reads=1 '
      'clipboard_writes=1 clipboard_clears=0 responder_restores=3 '
      'sessions_clean=1 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseDesktopSignalsProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required TerminalPaneCloseCoordinator paneCloseCoordinator,
    required TerminalDesktopSignalCoordinator desktopSignalCoordinator,
    required _TerminalDesktopSignalAcceptanceNativePort nativePort,
    required _TerminalDesktopSignalAcceptanceClock clock,
    required void Function() reconcile,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'desktop signals product did not start from a 1/1/1 hierarchy',
    );
    final TerminalWindowState window = state.windows.single;
    final TerminalTabState tab = window.selectedTab;
    final PaneId firstPaneId = tab.focusedPaneId;
    final TerminalSession firstSession = sessions[firstPaneId]!;
    final _TerminalHierarchyProductPane firstOwner = owners[firstPaneId]!;
    await _waitForAsciiMarker(firstSession, prompt);

    desktopSignalCoordinator.setApplicationActive(true);
    firstOwner.pane.insertText(
      "printf '\\033]9;focused-suppressed\\007"
      "\\033]9;4;1;42\\007"
      "\\033]133;B\\007"
      "__DT_DESKTOP_FIRST__\\n'",
    );
    await firstOwner.pane.submit();
    await waitFor(() {
      final TerminalDesktopSignalSessionSnapshot? snapshot =
          desktopSignalCoordinator.snapshotFor(firstSession.id);
      return snapshot?.progress.state == TerminalProgressState.set &&
          snapshot?.progress.percent == 42 &&
          snapshot?.semanticShellState == TerminalSemanticShellState.input &&
          desktopSignalCoordinator.metrics.focusSuppressedNotificationCount ==
              1 &&
          desktopSignalCoordinator.projectedDockBadgeLabel == '42%' &&
          application.dockBadgeLabel == '42%';
    }, 'focused notification suppression or initial progress did not project');

    final TerminalActionDispatchResult split = await dispatcher.dispatch(
      TerminalActionId.splitPaneRight,
    );
    await waitFor(
      () =>
          split.disposition == TerminalActionDispatchDisposition.executed &&
          state.paneCount == 2 &&
          hierarchy.paneResourceCount == 2 &&
          sessions.length == 2 &&
          owners.length == 2,
      'desktop signals product did not create the second real PTY pane',
    );
    final PaneId secondPaneId = sessions.keys.singleWhere(
      (PaneId paneId) => paneId != firstPaneId,
    );
    final TerminalSession secondSession = sessions[secondPaneId]!;
    final _TerminalHierarchyProductPane secondOwner = owners[secondPaneId]!;
    await _waitForAsciiMarker(secondSession, prompt);
    state
      ..activateWindow(window.id)
      ..selectTab(window.id, tab.id)
      ..focusPane(tab.id, firstPaneId);
    reconcile();

    secondOwner.pane.insertText(
      "printf '\\033]99;i=job;ready\\007"
      "\\033]99;i=job;ready\\007"
      "\\033]9;legacy-1\\007"
      "\\033]9;legacy-2\\007"
      "\\033]9;legacy-3\\007"
      "\\033]9;legacy-4\\007"
      "\\033]9;4;2;55\\007"
      "\\033]133;N\\007"
      "__DT_DESKTOP_BURST__\\n'",
    );
    await secondOwner.pane.submit();
    await waitFor(() {
      final TerminalDesktopSignalSessionSnapshot? snapshot =
          desktopSignalCoordinator.snapshotFor(secondSession.id);
      final TerminalDesktopSignalMetrics metrics =
          desktopSignalCoordinator.metrics;
      return snapshot?.progress.state == TerminalProgressState.error &&
          snapshot?.progress.percent == 55 &&
          snapshot?.semanticShellState == TerminalSemanticShellState.prompt &&
          snapshot?.liveNotificationCount == 3 &&
          nativePort.posts.length == 3 &&
          metrics.admittedNotificationCount == 3 &&
          metrics.projectedNotificationCount == 3 &&
          metrics.coalescedNotificationCount == 1 &&
          metrics.rateLimitedNotificationCount == 2;
    }, 'background notification burst did not obey the exact global budget');
    _expectLifecycle(
      nativePort.posts.every(
        (AppKitUserNotification notification) =>
            notification.identifier.startsWith('dt.p') &&
            !notification.identifier.contains('job'),
      ),
      'terminal notification identity escaped into the native namespace',
    );

    state.focusPane(tab.id, secondPaneId);
    reconcile();
    _expectLifecycle(
      desktopSignalCoordinator.projectedDockBadgeLabel == '55%!' &&
          application.dockBadgeLabel == '55%!',
      'focused error progress did not replace the native Dock badge',
    );

    final int secondResetGeneration =
        secondSession.terminalScreenSet.resetGeneration;
    secondOwner.pane.insertText("printf '\\033c__DT_DESKTOP_RESET__\\n'");
    await secondOwner.pane.submit();
    await waitFor(() {
      final TerminalDesktopSignalSessionSnapshot? snapshot =
          desktopSignalCoordinator.snapshotFor(secondSession.id);
      return snapshot?.resetGeneration == secondResetGeneration + 1 &&
          snapshot?.progress.state == TerminalProgressState.removed &&
          snapshot?.semanticShellState == TerminalSemanticShellState.unknown &&
          snapshot?.liveNotificationCount == 0 &&
          nativePort.removedIdentifiers.length == 3 &&
          desktopSignalCoordinator.projectedDockBadgeLabel == null &&
          application.dockBadgeLabel == null;
    }, 'RIS did not reset semantic/progress state and cancel notifications');

    clock.advance(TerminalDesktopSignalCoordinator.defaultNotificationWindow);
    state.focusPane(tab.id, firstPaneId);
    reconcile();
    secondOwner.pane.insertText(
      "printf '\\033]9;after-window\\007"
      "__DT_DESKTOP_RECOVERY__\\n'",
    );
    await secondOwner.pane.submit();
    await waitFor(() {
      final TerminalDesktopSignalSessionSnapshot? snapshot =
          desktopSignalCoordinator.snapshotFor(secondSession.id);
      return snapshot?.liveNotificationCount == 1 &&
          nativePort.posts.length == 4 &&
          desktopSignalCoordinator.metrics.admittedNotificationCount == 4 &&
          desktopSignalCoordinator.metrics.projectedNotificationCount == 4;
    }, 'sliding notification budget did not recover at its exact boundary');

    final TerminalPaneCloseResult close = await paneCloseCoordinator
        .requestClose(paneId: secondPaneId);
    stdout.writeln(close.machineLine());
    if (close.removal != null) {
      stdout.writeln(close.removal!.shutdown.machineLine());
    }
    _expectLifecycle(
      close.disposition == TerminalPaneCloseDisposition.removed &&
          close.removal?.shutdown.isClean == true &&
          state.paneForId(secondPaneId) == null &&
          desktopSignalCoordinator.snapshotFor(secondSession.id) == null &&
          nativePort.removedIdentifiers.length == 4 &&
          desktopSignalCoordinator.metrics.cancelledNotificationCount == 4,
      'pane close did not revoke and clean the exact desktop-signal session',
    );

    await dispatcher.dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatcher.dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    final TerminalDesktopSignalMetrics metrics =
        desktopSignalCoordinator.metrics;
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          allSessions.length == 2 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          metrics.admittedNotificationCount == 4 &&
          metrics.projectedNotificationCount == 4 &&
          metrics.coalescedNotificationCount == 1 &&
          metrics.rateLimitedNotificationCount == 2 &&
          metrics.focusSuppressedNotificationCount == 1 &&
          metrics.cancelledNotificationCount == 4 &&
          metrics.projectionFailureCount == 0 &&
          metrics.trackedSessionCount == 0 &&
          nativePort.nativeErrors.isEmpty &&
          nativePort.badgeLabels.contains('42%') &&
          nativePort.badgeLabels.contains('55%!') &&
          nativePort.badgeLabels.last == null &&
          application.dockBadgeLabel == null &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'desktop signals product did not cleanly release all native resources',
    );
    stdout.writeln(
      'TERMINAL_DESKTOP_SIGNALS_TEST real_pty=true '
      'safe_post_recorder=true focused_suppressed=1 admitted=4 projected=4 '
      'coalesced=1 rate_limited=2 reset_cancelled=3 close_cancelled=1 '
      'native_removals=4 progress=true semantic=true reset=true '
      'recovery=true sessions_clean=2 text_clients=0 native_handles=0 '
      'badge_cleared=true',
    );
  }

  static Future<void> _exerciseShellIntegrationProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required TerminalShellIntegrationBundle shellIntegrationBundle,
    required Map<PaneId, TerminalProductConfiguration> paneConfigurations,
    required TerminalPaneCloseCoordinator paneCloseCoordinator,
    required Completer<void> closed,
    required String prompt,
  }) async {
    _expectLifecycle(
      shellIntegrationBundle.usesBundledResources &&
          shellIntegrationBundle.fileCount == 5,
      'shell integration acceptance requires the validated bundle contract',
    );
    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1,
      'shell integration product did not start from a 1/1/1 hierarchy',
    );
    final PaneId paneId = state.windows.single.selectedTab.focusedPaneId;
    final TerminalSession session = sessions[paneId]!;
    final _TerminalHierarchyProductPane owner = owners[paneId]!;
    final TerminalConfiguredShellIntegration policy =
        paneConfigurations[paneId]!.shellIntegration;
    _expectLifecycle(
      policy == TerminalConfiguredShellIntegration.detect ||
          policy == TerminalConfiguredShellIntegration.none,
      'shell integration acceptance requires detect or none policy',
    );
    final bool expectsIntegration =
        policy == TerminalConfiguredShellIntegration.detect;
    await _waitForAsciiMarker(
      session,
      prompt,
      timeout: const Duration(seconds: 10),
    );
    if (expectsIntegration) {
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.input,
      );
      _expectLifecycle(
        session.terminalScreenSet.metadata.workingDirectory != null,
        'integrated shell omitted initial cwd metadata',
      );
    } else {
      _expectLifecycle(
        session.terminalScreenSet.semanticPrompt.shellState ==
                TerminalSemanticShellState.unknown &&
            session.terminalScreenSet.metadata.windowTitle == null &&
            session.terminalScreenSet.metadata.iconTitle == null &&
            session.terminalScreenSet.metadata.workingDirectory == null &&
            !dispatcher
                .snapshot(TerminalActionId.jumpToPreviousPrompt)
                .isEnabled &&
            !dispatcher.snapshot(TerminalActionId.jumpToNextPrompt).isEnabled,
        'disabled shell projected semantic state, metadata, or navigation',
      );
    }
    final String integrationCondition = expectsIntegration
        ? r'[[ ${DART_TERMINAL_SHELL_INTEGRATION-} == 1 && ${DART_TERMINAL_SHELL_INTEGRATION_VERSION-} == 2 && ${DART_TERMINAL_SHELL_INTEGRATION_SHELL-} == zsh ]]'
        : r'[[ -z ${DART_TERMINAL_SHELL_INTEGRATION-} && -z ${DART_TERMINAL_SHELL_INTEGRATION_VERSION-} && -z ${DART_TERMINAL_SHELL_INTEGRATION_SHELL-} ]]';
    const String startupCondition =
        r'[[ ${DT_RUNTIME_ZSHENV_COUNT:-0} == 1 && ${DT_RUNTIME_ZSHRC_COUNT:-0} == 1 ]]';
    const String cleanupCondition =
        r'[[ -z ${DART_TERMINAL_ZDOTDIR_SET-} && -z ${DART_TERMINAL_ZDOTDIR-} ]]';
    owner.pane.insertText(
      '$integrationCondition && $startupCondition && $cleanupCondition && '
      r"printf '%s%s\n' '__DT_SHELL_' 'ACCEPTED__' || "
      r"printf '%s%s\n' '__DT_SHELL_' 'REJECTED__'",
    );
    await owner.pane.submit();
    final Stopwatch resultDeadline = Stopwatch()..start();
    var accepted = false;
    var rejected = false;
    while (!accepted &&
        !rejected &&
        resultDeadline.elapsed < const Duration(seconds: 10)) {
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      accepted = _findAscii(screen, '__DT_SHELL_ACCEPTED__') != null;
      rejected = _findAscii(screen, '__DT_SHELL_REJECTED__') != null;
      if (!accepted && !rejected) {
        _expectLifecycle(
          session.isLive,
          'shell exited before integration acceptance completed',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    _expectLifecycle(
      accepted && !rejected,
      'shell integration environment or user startup contract was rejected',
    );

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'shell integration product action ${id.stableName} did not execute',
      );
    }

    var semanticAccepted = false;
    var metadataAccepted = false;
    var promptNavigationAccepted = false;
    var closeHintAccepted = false;
    if (expectsIntegration) {
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.input,
      );
      final String semanticCwdPath =
          Platform.environment['DT_RUNTIME_SEMANTIC_CWD'] ?? '';
      _expectLifecycle(
        semanticCwdPath.isNotEmpty &&
            Directory(semanticCwdPath).isAbsolute &&
            Directory(semanticCwdPath).existsSync(),
        'integrated shell acceptance requires an existing absolute cwd fixture',
      );
      final Uri semanticCwd = Uri(
        scheme: 'file',
        host: 'localhost',
        path: semanticCwdPath,
      );
      final String semanticTitle = semanticCwdPath
          .split(Platform.pathSeparator)
          .last;
      owner.pane.insertText(
        r'builtin cd -- "$DT_RUNTIME_SEMANTIC_CWD"; '
        r"printf '%s%s\n' '__DT_SEMANTIC_' 'CWD_DONE__'",
      );
      await owner.pane.submit();
      await _waitForAsciiMarker(session, '__DT_SEMANTIC_CWD_DONE__');
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.input,
      );
      await _waitForSessionMetadata(
        session,
        expectedTitle: semanticTitle,
        expectedWorkingDirectory: semanticCwd,
      );
      metadataAccepted = true;

      owner.pane.insertText(
        r'i=0; while [[ $i -lt 96 ]]; do '
        r"printf '__DT_SEMANTIC_ROW_%03d__\n' $i; (( i += 1 )); done; "
        r"printf '%s%s\n' '__DT_SEMANTIC_' 'SCROLL_DONE__'",
      );
      await owner.pane.submit();
      await _waitForAsciiMarker(session, '__DT_SEMANTIC_SCROLL_DONE__');
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.input,
      );
      final int semanticFlags = _retainedSemanticRowFlags(
        session.terminalScreenSet,
      );
      _expectLifecycle(
        semanticFlags & TerminalRowFlags.prompt != 0 &&
            semanticFlags & TerminalRowFlags.command != 0 &&
            semanticFlags & TerminalRowFlags.output != 0 &&
            session.terminalScreenSet.scrollback.length > 0,
        'integrated shell did not retain prompt, command, and output rows',
      );
      semanticAccepted = true;

      final TerminalViewport viewport = session.terminalScreenSet.viewport;
      _expectLifecycle(
        viewport.atBottom &&
            dispatcher
                .snapshot(TerminalActionId.jumpToPreviousPrompt)
                .isEnabled &&
            !dispatcher.snapshot(TerminalActionId.jumpToNextPrompt).isEnabled,
        'integrated shell did not expose previous-prompt navigation',
      );
      await dispatch(TerminalActionId.jumpToPreviousPrompt);
      _expectLifecycle(
        viewport.offset > 0 &&
            dispatcher.snapshot(TerminalActionId.jumpToNextPrompt).isEnabled,
        'previous-prompt action did not move the focused viewport',
      );
      await dispatch(TerminalActionId.jumpToNextPrompt);
      _expectLifecycle(
        viewport.atBottom,
        'next-prompt action did not return to the live grid',
      );
      promptNavigationAccepted = true;

      owner.pane.insertText(r'read -r DT_RUNTIME_SEMANTIC_READ');
      await owner.pane.submit();
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.commandOutput,
      );
      final TerminalPaneProcessSnapshot blocking =
          await _waitForPaneProcessDisposition(
            owner.pane,
            TerminalPaneProcessDisposition.owningShellCommand,
          );
      _expectLifecycle(
        blocking.childProcessId != null &&
            blocking.owningProcessGroup == blocking.foregroundProcessGroup,
        'blocking shell builtin did not retain the owning process group',
      );
      await dispatch(TerminalActionId.closeWindow);
      final TerminalPaneCloseConfirmation? confirmation =
          paneCloseCoordinator.pendingConfirmation;
      _expectLifecycle(
        confirmation != null &&
            confirmation.paneId == paneId &&
            confirmation.processDisposition ==
                TerminalPaneProcessDisposition.owningShellCommand &&
            state.paneCount == 1 &&
            owner.pane.state == TerminalPaneState.confirmationPending &&
            paneCloseCoordinator.cancelClose(confirmation),
        'owning-shell builtin did not produce a cancellable close warning',
      );
      _expectLifecycle(
        paneCloseCoordinator.pendingConfirmation == null &&
            owner.pane.state == TerminalPaneState.running,
        'cancelled semantic close warning did not restore the live pane',
      );
      owner.pane.insertText('accepted');
      await owner.pane.submit();
      await _waitForSemanticShellState(
        session,
        TerminalSemanticShellState.input,
      );
      await _waitForPaneProcessDisposition(
        owner.pane,
        TerminalPaneProcessDisposition.idleShell,
      );
      closeHintAccepted = true;
    } else {
      await _waitForPaneProcessDisposition(
        owner.pane,
        TerminalPaneProcessDisposition.idleShell,
      );
    }

    await dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          allSessions.length == 1 &&
          allSessions.single.shutdownResult?.isClean == true &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'shell integration product did not cleanly release all resources',
    );
    stdout.writeln(
      'TERMINAL_SHELL_INTEGRATION_TEST policy=${policy.name} bundle=true '
      'shell=zsh integrated=$expectsIntegration marker_contract=true '
      'semantic=$semanticAccepted metadata=$metadataAccepted '
      'prompt_navigation=$promptNavigationAccepted '
      'close_hint=$closeHintAccepted '
      'user_startup_once=true injection_cleanup=true hierarchy=true '
      'sessions_clean=1 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseThemeProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalSettingsInspectorPresenter settings,
    required TerminalQuickTerminalController quickTerminal,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required TerminalApplicationThemeProjection<PaneId> themeProjection,
    required TerminalApplicationAccessibilityProjection accessibilityProjection,
    required TerminalConfigReloadController? configurationReloadController,
    required TerminalProductConfigurationAuthority configurationAuthority,
    required Map<PaneId, TerminalProductConfiguration> paneConfigurations,
    required TerminalLocalization localization,
    required Completer<void> closed,
    required String prompt,
  }) async {
    const int customAnsiGreen = 0x8012ab34;
    var eventTimestamp = 12000000;

    String hex(Uint8List bytes) =>
        bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      _expectLifecycle(predicate(), message);
    }

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'theme product action ${id.stableName} did not execute',
      );
    }

    bool matchesTheme(TerminalScreenSet screens, TerminalBuiltInTheme theme) {
      final TerminalPalette palette = screens.palette;
      if (palette.defaultForeground != theme.foreground ||
          palette.defaultBackground != theme.background ||
          palette.cursorColor != theme.cursor ||
          palette.colorAt(2) != customAnsiGreen) {
        return false;
      }
      for (var index = 0; index < theme.ansiColors.length; index++) {
        if (index != 2 && palette.colorAt(index) != theme.ansiColors[index]) {
          return false;
        }
      }
      return true;
    }

    Future<void> presentGreenMarker(
      _TerminalHierarchyProductPane owner,
      String suffix,
    ) async {
      final String marker = '__DT_THEME_${suffix}__';
      owner.pane.insertText(
        "printf '\\033[32m__DT_THEME_%s__\\033[0m\\n' $suffix",
      );
      await owner.pane.submit();
      await _waitForAsciiMarkerPresented(
        owner,
        marker,
        timeout: const Duration(seconds: 10),
      );
      final TerminalScreen screen =
          owner.session.terminalScreenSet.activeScreen;
      final _TerminalAsciiPosition position = _findAscii(screen, marker)!;
      _expectLifecycle(
        screen.palette.resolveToken(
              screen.foregroundAt(position.row, position.column),
              foreground: true,
            ) ==
            customAnsiGreen,
        'theme custom ANSI color did not reach a presented Metal frame',
      );
    }

    Future<TerminalLiveMetalSurfaceSnapshot> waitForStableSurface(
      _TerminalHierarchyProductPane owner,
    ) async {
      final Stopwatch deadline = Stopwatch()..start();
      TerminalLiveMetalSurfaceSnapshot previous = owner.surface.snapshot();
      var stableObservations = 0;
      while (deadline.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final TerminalLiveMetalSurfaceSnapshot current = owner.surface
            .snapshot();
        if (!current.hasScheduledWork &&
            current.pendingFrameCount == 0 &&
            current.rendererGeneration == previous.rendererGeneration &&
            current.atlasResourceGeneration ==
                previous.atlasResourceGeneration &&
            current.acceptedFrameCount == previous.acceptedFrameCount) {
          stableObservations++;
          if (stableObservations == 3) return current;
        } else {
          stableObservations = 0;
        }
        previous = current;
      }
      throw TimeoutException('theme Metal surface did not become idle');
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          themeProjection.systemAppearance == TerminalThemeBrightness.light &&
          themeProjection.registeredPaneCount == 1,
      'theme product did not start from a light ordinary 1/1/1 hierarchy',
    );
    final TerminalWindowState initialWindow = state.windows.single;
    final TerminalTabState initialTab = initialWindow.selectedTab;
    final PaneId initialPaneId = initialTab.focusedPaneId;
    final TerminalSession initialSession = sessions[initialPaneId]!;
    final _TerminalHierarchyProductPane initialOwner = owners[initialPaneId]!;
    final TerminalScreenSet initialScreens = initialSession.terminalScreenSet;
    final TerminalConfigReloadController reloadController =
        configurationReloadController!;
    final String configurationPath =
        reloadController.effectiveSnapshot.rootPath!;
    _expectLifecycle(
      paneConfigurations[initialPaneId]!.theme ==
              TerminalConfiguredTheme.system &&
          matchesTheme(initialScreens, TerminalBuiltInTheme.dartLight) &&
          !initialScreens.activeScreen.cursorBlinking,
      'initial system pane did not capture light theme and custom overlay',
    );
    await _waitForAsciiMarker(initialSession, prompt);
    await presentGreenMarker(initialOwner, 'INITIAL');

    const String darkReportReady = '__DT_THEME_DARK_REPORT_READY__';
    const String darkReportExact = '__DT_THEME_DARK_REPORT_EXACT__';
    final ({int width, int height})? initialCellSize =
        initialScreens.logicalCellSize;
    _expectLifecycle(
      initialCellSize != null,
      'initial theme pane omitted logical cell geometry',
    );
    final Uint8List initialCellReply =
        TerminalReplyEncoder.textAreaCellSizePixels(
          height: initialCellSize!.height,
          width: initialCellSize.width,
        );
    final Uint8List lightSchemeReply = TerminalReplyEncoder.colorScheme(
      TerminalColorScheme.light,
    );
    final Uint8List darkSchemeReply = TerminalReplyEncoder.colorScheme(
      TerminalColorScheme.dark,
    );
    final String initialCellHex = hex(initialCellReply);
    final String lightSchemeHex = hex(lightSchemeReply);
    final String darkSchemeHex = hex(darkSchemeReply);
    initialOwner.pane.insertText(
      "stty raw -echo; printf "
      "'\\033[16t\\033[?996n\\033[?2031h"
      "\\r\\n__DT_THEME_DARK_REPORT_%s__\\r\\n' 'READY'; "
      "cell=\$(dd bs=1 count=${initialCellReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "initial=\$(dd bs=1 count=${lightSchemeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "changed=\$(dd bs=1 count=${darkSchemeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); stty sane; "
      "if [ \"\$cell\" = '$initialCellHex' ] && "
      "[ \"\$initial\" = '$lightSchemeHex' ] && "
      "[ \"\$changed\" = '$darkSchemeHex' ]; then "
      "printf '\\r\\n__DT_THEME_DARK_REPORT_%s__\\r\\n' 'EXACT'; else "
      "printf '\\r\\n__DT_THEME_DARK_REPORT_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, darkReportReady);
    _expectLifecycle(
      initialScreens.colorScheme == TerminalColorScheme.light &&
          initialScreens.colorSchemeReportingMode,
      'initial light query did not establish opted-in appearance reporting',
    );

    final TerminalSession initialSessionIdentity = initialSession;
    final TerminalPane initialPaneIdentity = initialOwner.pane;
    final _TerminalHierarchyProductPane initialOwnerIdentity = initialOwner;

    File(configurationPath).writeAsStringSync(
      'theme = light\npalette-2 = #12ab34\ncursor-blink = false\n',
      flush: true,
    );
    await dispatch(TerminalActionId.reloadConfiguration);
    _expectLifecycle(
      reloadController.acceptedGeneration == 1 &&
          configurationAuthority.acceptedGeneration == 1 &&
          configurationAuthority.newSessionConfiguration.theme ==
              TerminalConfiguredTheme.light &&
          paneConfigurations[initialPaneId]!.theme ==
              TerminalConfiguredTheme.system &&
          identical(sessions[initialPaneId], initialSessionIdentity) &&
          identical(owners[initialPaneId], initialOwnerIdentity),
      'light reload changed an existing system pane or missed new-session policy',
    );
    await dispatch(TerminalActionId.splitPaneRight);
    await waitFor(
      () =>
          state.paneCount == 2 &&
          hierarchy.paneResourceCount == 2 &&
          sessions.length == 2 &&
          owners.length == 2,
      'theme product did not create the fixed-light split pane',
    );
    final PaneId fixedPaneId = sessions.keys.singleWhere(
      (PaneId paneId) => paneId != initialPaneId,
    );
    final TerminalSession fixedSession = sessions[fixedPaneId]!;
    final _TerminalHierarchyProductPane fixedOwner = owners[fixedPaneId]!;
    final TerminalScreenSet fixedScreens = fixedSession.terminalScreenSet;
    await _waitForAsciiMarker(fixedSession, prompt);
    await presentGreenMarker(fixedOwner, 'FIXED');
    _expectLifecycle(
      paneConfigurations[fixedPaneId]!.theme == TerminalConfiguredTheme.light &&
          matchesTheme(fixedScreens, TerminalBuiltInTheme.dartLight) &&
          themeProjection.registeredPaneCount == 2,
      'new split pane did not capture fixed light theme and custom overlay',
    );

    final TerminalScreen primaryIdentity = initialScreens.primary;
    final TerminalScreen alternateIdentity = initialScreens.alternate;
    final TerminalPalette paletteIdentity = initialScreens.palette;
    final TerminalStyleTable styleIdentity = initialScreens.styleTable;
    final TerminalScrollback scrollbackIdentity = initialScreens.scrollback;
    final TerminalLiveMetalSurface surfaceIdentity = initialOwner.surface;
    final View viewIdentity = initialOwner.view;
    await waitForStableSurface(fixedOwner);
    final int fixedPaletteGeneration = fixedScreens.palette.generation;
    final TerminalLiveMetalSurfaceSnapshot beforeDark =
        await waitForStableSurface(initialOwner);
    final int initialPaletteGeneration = initialScreens.palette.generation;
    _injectApplicationAppearanceEventForTesting(
      application,
      isDark: true,
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = initialOwner.surface
          .snapshot();
      return themeProjection.systemAppearance == TerminalThemeBrightness.dark &&
          initialScreens.palette.generation == initialPaletteGeneration + 1 &&
          matchesTheme(initialScreens, TerminalBuiltInTheme.dartDark) &&
          snapshot.lastAppliedDamageGeneration >
              beforeDark.lastAppliedDamageGeneration &&
          snapshot.acceptedFrameCount > beforeDark.acceptedFrameCount;
    }, 'live dark appearance did not reach an accepted Metal frame');
    final TerminalLiveMetalSurfaceSnapshot afterDark =
        await waitForStableSurface(initialOwner);
    _expectLifecycle(
      matchesTheme(fixedScreens, TerminalBuiltInTheme.dartLight) &&
          fixedScreens.palette.generation == fixedPaletteGeneration &&
          identical(sessions[initialPaneId], initialSessionIdentity) &&
          identical(initialOwner.pane, initialPaneIdentity) &&
          identical(owners[initialPaneId], initialOwnerIdentity) &&
          identical(initialScreens.primary, primaryIdentity) &&
          identical(initialScreens.alternate, alternateIdentity) &&
          identical(initialScreens.palette, paletteIdentity) &&
          identical(initialScreens.styleTable, styleIdentity) &&
          identical(initialScreens.scrollback, scrollbackIdentity) &&
          identical(initialOwner.surface, surfaceIdentity) &&
          identical(initialOwner.view, viewIdentity) &&
          afterDark.rendererGeneration == beforeDark.rendererGeneration &&
          afterDark.atlasResourceGeneration ==
              beforeDark.atlasResourceGeneration,
      'live dark appearance replaced resources or changed the fixed pane: '
      'renderer=${beforeDark.rendererGeneration}/'
      '${afterDark.rendererGeneration} atlas='
      '${beforeDark.atlasResourceGeneration}/'
      '${afterDark.atlasResourceGeneration} fixed_palette='
      '$fixedPaletteGeneration/${fixedScreens.palette.generation}',
    );
    await _waitForAsciiMarker(initialSession, darkReportExact);
    _expectLifecycle(
      initialScreens.colorScheme == TerminalColorScheme.dark &&
          initialScreens.colorSchemeReportingMode,
      'native dark appearance did not preserve the opted-in typed state',
    );

    const String appearanceDisableExact = '__DT_THEME_DISABLE_EXACT__';
    const String appearanceResetExact = '__DT_THEME_RESET_EXACT__';
    initialOwner.pane.insertText(
      "printf '\\033[?2031l\\r\\n__DT_THEME_DISABLE_%s__\\r\\n' 'EXACT'",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, appearanceDisableExact);
    _expectLifecycle(
      !initialScreens.colorSchemeReportingMode &&
          initialScreens.colorScheme == TerminalColorScheme.dark,
      'real PTY disable did not reset mode 2031 or retain appearance',
    );
    initialOwner.pane.insertText(
      "printf '\\033[?2031h\\033c\\r\\n__DT_THEME_RESET_%s__\\r\\n' 'EXACT'",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, appearanceResetExact);
    _expectLifecycle(
      !initialScreens.colorSchemeReportingMode &&
          initialScreens.colorScheme == TerminalColorScheme.dark,
      'real PTY RIS did not reset mode 2031 and retain appearance',
    );

    final Window themeWindow = hierarchy.windowForTab(initialTab.id)!;
    final Rect originalFrame = themeWindow.frame;
    final TerminalPaneLayoutRect initialLayout = initialOwner.layout!;
    final TerminalPaneLayoutRect fixedLayout = fixedOwner.layout!;
    final double originalContentWidth = math.max(
      initialLayout.left + initialLayout.width,
      fixedLayout.left + fixedLayout.width,
    );
    final double originalContentHeight = math.max(
      initialLayout.top + initialLayout.height,
      fixedLayout.top + fixedLayout.height,
    );
    final ({int width, int height})? originalViewport =
        fixedScreens.logicalViewportSize;
    final ({int width, int height})? fixedCellSize =
        fixedScreens.logicalCellSize;
    _expectLifecycle(
      originalViewport != null && fixedCellSize != null,
      'fixed theme pane omitted logical viewport or cell geometry',
    );
    final int originalRows = fixedScreens.activeScreen.rows;
    final int originalColumns = fixedScreens.activeScreen.columns;
    final Uint8List originalSizeReply = TerminalReplyEncoder.inBandSizeReport(
      rows: originalRows,
      columns: originalColumns,
      heightPixels: originalViewport!.height,
      widthPixels: originalViewport.width,
    );
    final TerminalLiveMetalSurfaceSnapshot beforeForwardResize =
        await waitForStableSurface(fixedOwner);
    final double widthDelta = fixedCellSize!.width * 4;
    final double heightDelta = fixedCellSize.height * 2;
    _injectWindowGeometryEventsForTesting(
      application,
      themeWindow,
      frame: Rect.fromLTWH(
        originalFrame.left,
        originalFrame.top,
        originalFrame.width - widthDelta,
        originalFrame.height - heightDelta,
      ),
      contentWidth: originalContentWidth - widthDelta,
      contentHeight: originalContentHeight - heightDelta,
      monotonicNanoseconds: eventTimestamp,
    );
    eventTimestamp += 2;
    await waitFor(() {
      final ({int width, int height})? viewport =
          fixedScreens.logicalViewportSize;
      return viewport != null && viewport != originalViewport;
    }, 'native theme-window resize did not reach screen geometry');
    final TerminalLiveMetalSurfaceSnapshot forwardResizeSurface =
        await waitForStableSurface(fixedOwner);
    _expectLifecycle(
      forwardResizeSurface.acceptedFrameCount >
          beforeForwardResize.acceptedFrameCount,
      'native theme-window resize did not reach an accepted Metal frame: '
      'frames=${beforeForwardResize.acceptedFrameCount}/'
      '${forwardResizeSurface.acceptedFrameCount}',
    );
    final ({int width, int height}) forwardViewport =
        fixedScreens.logicalViewportSize!;
    final Uint8List forwardSizeReply = TerminalReplyEncoder.inBandSizeReport(
      rows: fixedScreens.activeScreen.rows,
      columns: fixedScreens.activeScreen.columns,
      heightPixels: forwardViewport.height,
      widthPixels: forwardViewport.width,
    );
    final Uint8List fixedCellReply =
        TerminalReplyEncoder.textAreaCellSizePixels(
          height: fixedCellSize.height,
          width: fixedCellSize.width,
        );
    final String fixedCellHex = hex(fixedCellReply);
    final String forwardSizeHex = hex(forwardSizeReply);
    final String originalSizeHex = hex(originalSizeReply);
    const String resizeReportReady = '__DT_THEME_RESIZE_REPORT_READY__';
    const String resizeReportExact = '__DT_THEME_RESIZE_REPORT_EXACT__';
    fixedOwner.pane.insertText(
      "stty raw -echo; printf "
      "'\\033[?996n\\033[16t\\033[?2048h"
      "\\r\\n__DT_THEME_RESIZE_REPORT_%s__\\r\\n' 'READY'; "
      "scheme=\$(dd bs=1 count=${lightSchemeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "cell=\$(dd bs=1 count=${fixedCellReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "immediate=\$(dd bs=1 count=${forwardSizeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "resized=\$(dd bs=1 count=${originalSizeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?2048l'; stty sane; "
      "if [ \"\$scheme\" = '$lightSchemeHex' ] && "
      "[ \"\$cell\" = '$fixedCellHex' ] && "
      "[ \"\$immediate\" = '$forwardSizeHex' ] && "
      "[ \"\$resized\" = '$originalSizeHex' ]; then "
      "printf '\\r\\n__DT_THEME_RESIZE_REPORT_%s__\\r\\n' 'EXACT'; else "
      "printf '\\r\\n__DT_THEME_RESIZE_REPORT_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await fixedOwner.pane.submit();
    await _waitForAsciiMarker(fixedSession, resizeReportReady);
    _expectLifecycle(
      fixedScreens.inBandSizeReportingMode,
      'real PTY did not enable in-band resize reporting',
    );
    _injectWindowGeometryEventsForTesting(
      application,
      themeWindow,
      frame: originalFrame,
      contentWidth: originalContentWidth,
      contentHeight: originalContentHeight,
      monotonicNanoseconds: eventTimestamp,
    );
    eventTimestamp += 2;
    await waitFor(() {
      final ({int width, int height})? viewport =
          fixedScreens.logicalViewportSize;
      final TerminalLiveMetalSurfaceSnapshot snapshot = fixedOwner.surface
          .snapshot();
      return viewport == originalViewport &&
          fixedScreens.activeScreen.rows == originalRows &&
          fixedScreens.activeScreen.columns == originalColumns &&
          snapshot.acceptedFrameCount > forwardResizeSurface.acceptedFrameCount;
    }, 'native window restore did not complete reported PTY/Metal resize');
    await _waitForAsciiMarker(fixedSession, resizeReportExact);
    _expectLifecycle(
      !fixedScreens.inBandSizeReportingMode,
      'real PTY disable did not reset mode 2048 after exact resize capture',
    );

    File(configurationPath).writeAsStringSync(
      'theme = system\npalette-2 = #12ab34\ncursor-blink = false\n',
      flush: true,
    );
    await dispatch(TerminalActionId.reloadConfiguration);
    _expectLifecycle(
      reloadController.acceptedGeneration == 2 &&
          configurationAuthority.acceptedGeneration == 2 &&
          configurationAuthority.newSessionConfiguration.theme ==
              TerminalConfiguredTheme.system &&
          paneConfigurations[fixedPaneId]!.theme ==
              TerminalConfiguredTheme.light,
      'system reload did not preserve the existing fixed-light pane boundary',
    );
    final Set<PaneId> existingPaneIds = sessions.keys.toSet();
    await dispatch(TerminalActionId.newTab);
    await waitFor(
      () =>
          state.tabCount == 2 &&
          state.paneCount == 3 &&
          hierarchy.paneResourceCount == 3 &&
          sessions.length == 3 &&
          owners.length == 3,
      'theme product did not create the later system tab',
    );
    final PaneId laterSystemPaneId = sessions.keys.singleWhere(
      (PaneId paneId) => !existingPaneIds.contains(paneId),
    );
    final TerminalSession laterSystemSession = sessions[laterSystemPaneId]!;
    final _TerminalHierarchyProductPane laterSystemOwner =
        owners[laterSystemPaneId]!;
    final TerminalScreenSet laterSystemScreens =
        laterSystemSession.terminalScreenSet;
    await _waitForAsciiMarker(laterSystemSession, prompt);
    await presentGreenMarker(laterSystemOwner, 'LATER');
    _expectLifecycle(
      paneConfigurations[laterSystemPaneId]!.theme ==
              TerminalConfiguredTheme.system &&
          matchesTheme(laterSystemScreens, TerminalBuiltInTheme.dartDark) &&
          themeProjection.registeredPaneCount == 3,
      'later system pane did not capture the current dark appearance',
    );

    const String lightReportReady = '__DT_THEME_LIGHT_REPORT_READY__';
    const String lightReportExact = '__DT_THEME_LIGHT_REPORT_EXACT__';
    laterSystemOwner.pane.insertText(
      "stty raw -echo; printf "
      "'\\033[?996n\\033[?2031h"
      "\\r\\n__DT_THEME_LIGHT_REPORT_%s__\\r\\n' 'READY'; "
      "initial=\$(dd bs=1 count=${darkSchemeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "changed=\$(dd bs=1 count=${lightSchemeReply.length} 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?2031l\\033[?2031h\\033c'; stty sane; "
      "if [ \"\$initial\" = '$darkSchemeHex' ] && "
      "[ \"\$changed\" = '$lightSchemeHex' ]; then "
      "printf '\\r\\n__DT_THEME_LIGHT_REPORT_%s__\\r\\n' 'EXACT'; else "
      "printf '\\r\\n__DT_THEME_LIGHT_REPORT_%s__\\r\\n' 'MISMATCH'; fi",
    );
    await laterSystemOwner.pane.submit();
    await _waitForAsciiMarker(laterSystemSession, lightReportReady);
    _expectLifecycle(
      laterSystemScreens.colorScheme == TerminalColorScheme.dark &&
          laterSystemScreens.colorSchemeReportingMode,
      'later dark pane did not establish opted-in appearance reporting',
    );

    final TerminalSession laterSessionIdentity = laterSystemSession;
    final _TerminalHierarchyProductPane laterOwnerIdentity = laterSystemOwner;
    final TerminalScreen laterPrimaryIdentity = laterSystemScreens.primary;
    final TerminalScreen laterAlternateIdentity = laterSystemScreens.alternate;
    final TerminalPalette laterPaletteIdentity = laterSystemScreens.palette;
    final TerminalStyleTable laterStyleIdentity = laterSystemScreens.styleTable;
    final TerminalScrollback laterScrollbackIdentity =
        laterSystemScreens.scrollback;
    final TerminalLiveMetalSurface laterSurfaceIdentity =
        laterSystemOwner.surface;
    final TerminalLiveMetalSurfaceSnapshot beforeLight =
        await waitForStableSurface(laterSystemOwner);
    final int laterPaletteGeneration = laterSystemScreens.palette.generation;
    final int initialGenerationBeforeLight = initialScreens.palette.generation;
    _injectApplicationAppearanceEventForTesting(
      application,
      isDark: false,
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = laterSystemOwner.surface
          .snapshot();
      return themeProjection.systemAppearance ==
              TerminalThemeBrightness.light &&
          laterSystemScreens.palette.generation == laterPaletteGeneration + 1 &&
          matchesTheme(laterSystemScreens, TerminalBuiltInTheme.dartLight) &&
          snapshot.lastAppliedDamageGeneration >
              beforeLight.lastAppliedDamageGeneration &&
          snapshot.acceptedFrameCount > beforeLight.acceptedFrameCount;
    }, 'live light appearance did not reach the later accepted Metal frame');
    await _waitForAsciiMarker(laterSystemSession, lightReportExact);
    _expectLifecycle(
      laterSystemScreens.colorScheme == TerminalColorScheme.light &&
          !laterSystemScreens.colorSchemeReportingMode,
      'real PTY light notification did not complete disable/RIS cleanup',
    );
    final TerminalLiveMetalSurfaceSnapshot afterLight =
        await waitForStableSurface(laterSystemOwner);
    _expectLifecycle(
      matchesTheme(initialScreens, TerminalBuiltInTheme.dartLight) &&
          initialScreens.palette.generation ==
              initialGenerationBeforeLight + 1 &&
          matchesTheme(fixedScreens, TerminalBuiltInTheme.dartLight) &&
          fixedScreens.palette.generation == fixedPaletteGeneration &&
          identical(sessions[laterSystemPaneId], laterSessionIdentity) &&
          identical(owners[laterSystemPaneId], laterOwnerIdentity) &&
          identical(laterSystemScreens.primary, laterPrimaryIdentity) &&
          identical(laterSystemScreens.alternate, laterAlternateIdentity) &&
          identical(laterSystemScreens.palette, laterPaletteIdentity) &&
          identical(laterSystemScreens.styleTable, laterStyleIdentity) &&
          identical(laterSystemScreens.scrollback, laterScrollbackIdentity) &&
          identical(laterSystemOwner.surface, laterSurfaceIdentity) &&
          afterLight.rendererGeneration == beforeLight.rendererGeneration &&
          afterLight.atlasResourceGeneration ==
              beforeLight.atlasResourceGeneration,
      'live light appearance replaced resources or changed fixed policy: '
      'renderer=${beforeLight.rendererGeneration}/'
      '${afterLight.rendererGeneration} atlas='
      '${beforeLight.atlasResourceGeneration}/'
      '${afterLight.atlasResourceGeneration} fixed_palette='
      '$fixedPaletteGeneration/${fixedScreens.palette.generation}',
    );

    _expectLifecycle(
      localization.language == TerminalLanguage.japanese &&
          !localization.usesFallbackCatalog &&
          localization.textDirection == TerminalTextDirection.leftToRight,
      'theme runtime did not select the injected Japanese catalog',
    );
    final TerminalActionMessages copyMessages = localization.action(
      TerminalActionMessageId.copy,
    );
    _expectLifecycle(
      dispatcher.catalog.actionForId(TerminalActionId.copy)?.title ==
              copyMessages.title &&
          menu.itemForAction(TerminalActionId.copy).title == copyMessages.title,
      'Japanese action copy did not reach the dispatcher and native menu',
    );
    await dispatch(TerminalActionId.openCommandPalette);
    await waitFor(
      () =>
          palette.isOpen &&
          (palette.renderedText ?? '').contains(
            localization.commandPaletteTitle,
          ) &&
          (palette.renderedText ?? '').contains(copyMessages.title),
      'Japanese catalog did not reach the native Command Palette',
    );
    await palette.dismiss();
    await dispatch(TerminalActionId.openSettings);
    await waitFor(
      () => settings.isOpen && settings.renderedText != null,
      'Japanese Settings presenter did not open',
    );
    final TerminalSettingsOptionOccurrence selectedSetting =
        settings.state.selectedOccurrence!;
    final String settingsStatus = settings.activeStatusView!.text;
    final String settingsDetail = settings.activeDetailView!.text;
    _expectLifecycle(
      settingsStatus.contains(
            localization.settingsSaveState(settings.state.saveState.name),
          ) &&
          settingsStatus.contains('フォント: 軸 ') &&
          settingsStatus.contains('クイックターミナルのショートカット:') &&
          settingsStatus.contains('セキュアキーボード入力:') &&
          settingsStatus.contains('通知:') &&
          settingsDetail.contains(
            localization.settingsOptionDescription(
              selectedSetting.option.name,
              selectedSetting.option.description,
            ),
          ),
      'Japanese Settings shell, status, or option detail was incomplete',
    );

    _injectApplicationAccessibilityDisplayPreferencesEventForTesting(
      application,
      reduceMotion: false,
      increaseContrast: false,
      differentiateWithoutColor: false,
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          accessibilityProjection.presentation ==
              const TerminalAccessibilityPresentation.standard() &&
          quickTerminal.accessibilityPresentation ==
              const TerminalAccessibilityPresentation.standard() &&
          settings.accessibilityPresentation ==
              const TerminalAccessibilityPresentation.standard() &&
          owners.values.every((_TerminalHierarchyProductPane owner) {
            final TerminalLiveMetalSurfaceSnapshot snapshot = owner.surface
                .snapshot();
            return !snapshot.reduceMotion &&
                !snapshot.increaseContrast &&
                !snapshot.differentiateWithoutColor;
          }),
      'standard accessibility preferences did not reach every product owner',
    );
    final Window settingsWindowIdentity = settings.activeWindow!;
    final TextEditor settingsEditorBeforeContrast = settings.activeView!;
    final String settingsTextIdentity = settings.state.text;
    final TerminalSettingsTextSelection settingsSelectionIdentity =
        settings.state.selection;
    final TerminalSettingsEditorMode settingsModeIdentity = settings.state.mode;
    final TerminalLiveMetalSurface laterSurfaceIdentityBeforePreferences =
        laterSystemOwner.surface;
    final TerminalLiveMetalSurfaceSnapshot beforePreferences =
        await waitForStableSurface(laterSystemOwner);
    const AppKitAccessibilityDisplayPreferences enabledPreferences =
        AppKitAccessibilityDisplayPreferences(
          reduceMotion: true,
          increaseContrast: true,
          differentiateWithoutColor: true,
        );
    _injectApplicationAccessibilityDisplayPreferencesEventForTesting(
      application,
      reduceMotion: true,
      increaseContrast: true,
      differentiateWithoutColor: true,
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = laterSystemOwner.surface
          .snapshot();
      return application.accessibilityDisplayPreferences ==
              enabledPreferences &&
          accessibilityProjection.presentation.reduceMotion &&
          accessibilityProjection.presentation.increaseContrast &&
          accessibilityProjection.presentation.differentiateWithoutColor &&
          quickTerminal.accessibilityPresentation.reduceMotion &&
          settings.accessibilityPresentation.increaseContrast &&
          snapshot.reduceMotion &&
          snapshot.increaseContrast &&
          snapshot.differentiateWithoutColor &&
          snapshot.acceptedFrameCount > beforePreferences.acceptedFrameCount;
    }, 'live accessibility preferences did not reach accepted presentation');
    await waitForStableSurface(laterSystemOwner);
    final TextEditor settingsEditorAfterContrast = settings.activeView!;
    _expectLifecycle(
      terminalQuickTerminalEffectiveAnimationDuration(
                configurationAuthority
                    .newSessionConfiguration
                    .quickTerminalAnimationDuration,
                quickTerminal.accessibilityPresentation,
              ) ==
              Duration.zero &&
          identical(settings.activeWindow, settingsWindowIdentity) &&
          !identical(
            settingsEditorAfterContrast,
            settingsEditorBeforeContrast,
          ) &&
          settings.state.text == settingsTextIdentity &&
          settings.state.selection == settingsSelectionIdentity &&
          settings.state.mode == settingsModeIdentity &&
          identical(
            laterSystemOwner.surface,
            laterSurfaceIdentityBeforePreferences,
          ),
      'live preference projection changed stable product state or identity',
    );
    _injectApplicationAccessibilityDisplayPreferencesEventForTesting(
      application,
      reduceMotion: true,
      increaseContrast: true,
      differentiateWithoutColor: true,
      monotonicNanoseconds: eventTimestamp++,
    );
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      identical(settings.activeView, settingsEditorAfterContrast) &&
          identical(
            laterSystemOwner.surface,
            laterSurfaceIdentityBeforePreferences,
          ),
      'duplicate accessibility preferences replaced product owners',
    );
    stdout.writeln(
      'TERMINAL_ACCESSIBILITY_LOCALIZATION_TEST protocol='
      '${application.eventProtocolVersion} language=ja fallback=false '
      'rtl=false menu=true palette=true settings=true statuses=true '
      'preferences=true motion=true contrast=true noncolor=true '
      'deduplicated=true identities=true',
    );

    await dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          themeProjection.isDisposed &&
          accessibilityProjection.isDisposed &&
          themeProjection.registeredPaneCount == 0 &&
          allSessions.length == 3 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true &&
                !session.terminalScreenSet.colorSchemeReportingMode &&
                !session.terminalScreenSet.inBandSizeReportingMode,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'theme product did not cleanly release all resources',
    );
    stdout.writeln(
      'TERMINAL_THEME_TEST protocol=${application.eventProtocolVersion} '
      'initial_light=true live_dark=true '
      'live_light=true appearance_query=true appearance_notifications=2 '
      'appearance_disable=true appearance_reset=true cell_report=true '
      'in_band_size=true native_resize=true exact=true '
      'system_panes=2 fixed_panes=1 custom_override=true '
      'metal=true resource_identity=true reload_boundary=true '
      'event_cleanup=true sessions_clean=3 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseConfigurationProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalSettingsInspectorPresenter settings,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required List<TerminalConfigReloadResult> configurationReloads,
    required TerminalConfigReloadController? configurationReloadController,
    required TerminalProductConfigurationAuthority configurationAuthority,
    required TerminalContextDockState contextDockState,
    required Map<PaneId, TerminalProductConfiguration> paneConfigurations,
    required Map<PaneId, String?> launchWorkingDirectories,
    required int Function() terminalInputDeliveryCount,
    required Map<PaneId, TerminalKeyRouteResult> lastKeyRoutes,
    required Map<PaneId, int> keyRouteCounts,
    required Map<PaneId, int> writeEnqueuedCounts,
    required int Function() endOfFileActionCount,
    required Completer<void> closed,
    required String prompt,
  }) async {
    const int configuredForeground = 0x80d0d1d2;
    const int configuredBackground = 0x80111213;
    const int configuredCursor = 0x80f0e0d0;
    const int configuredAnsiGreen = 0x8012ab34;
    const double configuredWindowWidth = 1110;
    const double configuredWindowHeight = 710;
    const double configuredHorizontalPadding = 18;
    const double configuredVerticalPadding = 11;
    const double configuredBackgroundOpacity = 0.8;
    const int configuredScrollbackLines = 8;
    const int configuredScrollbackBytes = 1024 * 1024;
    const int reloadedForeground = 0x80a0b0c0;
    const int reloadedBackground = 0x80202122;
    const int reloadedCursor = 0x80c0b0a0;
    const int reloadedAnsiGreen = 0x8043ba21;
    const double reloadedWindowWidth = 980;
    const double reloadedWindowHeight = 640;
    const double reloadedHorizontalPadding = 9;
    const double reloadedVerticalPadding = 7;
    const double reloadedBackgroundOpacity = 0.45;
    const double finalBackgroundOpacity = 0.6;
    const int reloadedScrollbackLines = 12;
    const int reloadedScrollbackBytes = 2 * 1024 * 1024;
    const String reloadedWorkingDirectory = '/tmp';
    var eventTimestamp = 13000000;

    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _expectLifecycle(predicate(), message);
    }

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'configured product action ${id.stableName} did not execute',
      );
    }

    TerminalKeyRouteResult routeConfiguredKey(
      _TerminalHierarchyProductPane owner, {
      required int keyCode,
      required int modifiers,
      required String characters,
      required String charactersIgnoringModifiers,
    }) {
      final PaneId paneId = owner.pane.id;
      final int routeBaseline = keyRouteCounts[paneId] ?? 0;
      final TerminalTextInputRouteResult textResult = owner.textRouter.route(
        TerminalTextInputKeyEvent(
          clientId: owner.client.clientId,
          generation: owner.textRouter.lastGeneration + 1,
          monotonicNanoseconds: eventTimestamp++,
          kind: TerminalTextInputKeyKind.down,
          keyCode: keyCode,
          modifiers: ModifierKeys(modifiers),
          isRepeat: false,
          characters: characters,
          charactersIgnoringModifiers: charactersIgnoringModifiers,
        ),
      );
      _expectLifecycle(
        textResult.disposition == TerminalTextInputRouteDisposition.rawKey &&
            keyRouteCounts[paneId] == routeBaseline + 1 &&
            lastKeyRoutes[paneId] != null,
        'configured key did not cross the raw text-input/key router once',
      );
      return lastKeyRoutes[paneId]!;
    }

    int writeEnqueuedCount() => writeEnqueuedCounts.values.fold(
      0,
      (int total, int count) => total + count,
    );

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1,
      'configured product did not start from the ordinary 1/1/1 hierarchy',
    );
    final TerminalWindowState initialWindow = state.windows.single;
    final TerminalTabState initialTab = initialWindow.selectedTab;
    final PaneId initialPaneId = initialTab.focusedPaneId;
    final TerminalSession initialSession = sessions[initialPaneId]!;
    final _TerminalHierarchyProductPane initialOwner = owners[initialPaneId]!;
    final Window nativeWindow = hierarchy.windowForTab(initialTab.id)!;
    final TerminalScreenSet initialScreens = initialSession.terminalScreenSet;
    final TerminalConfigReloadController reloadController =
        configurationReloadController!;
    final String configurationPath =
        reloadController.effectiveSnapshot.rootPath!;
    final int configurationPermissionBits =
        FileStat.statSync(configurationPath).mode & 0xFFF;
    final TerminalSession stableSession = initialSession;
    final _TerminalHierarchyProductPane stableOwner = initialOwner;
    final Window stableWindow = nativeWindow;
    final int nativeHandleBaseline = application.debugLiveObjectCount;
    _expectLifecycle(
      !contextDockState.snapshotForWindow(initialWindow.id)!.isVisible &&
          contextDockState.snapshotForWindow(initialWindow.id)!.width == 380,
      'configuration fixture did not preserve its explicit Dock opt-out',
    );
    contextDockState.setWidth(initialWindow.id, 500);
    final int settingsResponderBaseline =
        settings.terminalResponderRestoreCount;
    final TerminalConfigSnapshot recoveredStartupSnapshot =
        reloadController.effectiveSnapshot;
    final TerminalConfigReloadResult unavailableReload = await reloadController
        .reload();
    _expectLifecycle(
      unavailableReload.disposition ==
              TerminalConfigReloadDisposition.rejected &&
          identical(
            unavailableReload.effectiveSnapshot,
            recoveredStartupSnapshot,
          ) &&
          reloadController.acceptedGeneration == 0 &&
          unavailableReload.candidateSnapshot!
              .value(TerminalProductConfigSchema.fontFamily)
              .isEmpty &&
          unavailableReload.diagnostics.any(
            (TerminalConfigDiagnostic diagnostic) =>
                diagnostic.code == 'CFG_UNAVAILABLE_VALUE',
          ) &&
          identical(sessions[initialPaneId], stableSession) &&
          identical(owners[initialPaneId], stableOwner) &&
          identical(hierarchy.windowForTab(initialTab.id), stableWindow),
      'unavailable-font reload did not retain the recovered startup state',
    );
    _expectLifecycle(
      nativeWindow.frame.width == configuredWindowWidth &&
          nativeWindow.frame.height == configuredWindowHeight &&
          initialScreens.palette.defaultForeground == configuredForeground &&
          initialScreens.palette.defaultBackground == configuredBackground &&
          initialScreens.palette.cursorColor == configuredCursor &&
          initialScreens.palette.colorAt(2) == configuredAnsiGreen &&
          initialScreens.scrollback.maxLines == configuredScrollbackLines &&
          initialScreens.scrollback.maxBytes == configuredScrollbackBytes &&
          initialScreens.activeScreen.cursorShape == TerminalCursorShape.bar &&
          !initialScreens.activeScreen.cursorBlinking &&
          initialOwner.surface.fontFamily.isEmpty &&
          initialOwner.surface.fontMetrics.pointSize == 18 &&
          initialOwner.surface.syntheticStylePolicy ==
              TerminalSyntheticStylePolicy.reject &&
          initialOwner.surface.horizontalPadding ==
              configuredHorizontalPadding &&
          initialOwner.surface.verticalPadding == configuredVerticalPadding &&
          initialOwner.surface.backgroundOpacity == configuredBackgroundOpacity,
      'configured product did not project the resolved initial profile',
    );
    var invalidBackgroundOpacityRejected = false;
    try {
      initialOwner.surface.updateBackgroundOpacity(double.nan);
    } on RangeError {
      invalidBackgroundOpacityRejected = true;
    }
    _expectLifecycle(
      invalidBackgroundOpacityRejected &&
          !initialOwner.surface.updateBackgroundOpacity(
            configuredBackgroundOpacity,
          ) &&
          initialOwner.surface.backgroundOpacity == configuredBackgroundOpacity,
      'terminal surface did not reject invalid opacity or deduplicate the '
      'current application-wide value',
    );
    await _waitForAsciiMarker(initialSession, prompt);
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = initialOwner.surface
          .snapshot();
      return snapshot.accessibilityGeneration > 0 &&
          snapshot.accessibilityContentOriginX == configuredHorizontalPadding &&
          snapshot.accessibilityContentOriginY == configuredVerticalPadding;
    }, 'configured accessibility origin did not reach the initial surface');
    initialOwner.surface.debugVerifyAccessibility();

    final MenuItem settingsItem = menu.itemForAction(
      TerminalActionId.openSettings,
    );
    _expectLifecycle(
      settingsItem.isEnabled &&
          settingsItem.keyEquivalent == ',' &&
          settingsItem.modifiers.bits == ModifierKeys.commandBit,
      'Settings action was unavailable or did not own Command-comma',
    );
    final int settingsMenuInvocationBaseline = nativeActionInvocations.length;
    final int settingsMenuDispatchBaseline = actionDispatches.length;
    settingsItem.performAction();
    await waitFor(
      () =>
          settings.isOpen &&
          nativeActionInvocations.length ==
              settingsMenuInvocationBaseline + 1 &&
          actionDispatches.length == settingsMenuDispatchBaseline + 1,
      'native Settings menu action did not open exactly once',
    );
    final Window initialSettingsWindow = settings.activeWindow!;
    final TerminalSettingsOptionOccurrence disabledWorkingDirectory = settings
        .state
        .occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option.name == 'working-directory',
        );
    final List<TerminalSettingsSyntaxSpan> disabledWorkingDirectorySpans =
        settings.state.syntaxSpans
            .where(
              (TerminalSettingsSyntaxSpan span) =>
                  span.start < disabledWorkingDirectory.lineEnd &&
                  span.end > disabledWorkingDirectory.lineStart,
            )
            .toList(growable: false);
    final TextEditorSnapshot initialSettingsSnapshot =
        settings.activeView!.snapshot;
    _expectLifecycle(
      initialSettingsSnapshot.text == settings.state.text &&
          initialSettingsSnapshot.selection.start ==
              settings.state.selection.start &&
          !initialSettingsSnapshot.isEditable &&
          disabledWorkingDirectory.isCommented &&
          disabledWorkingDirectorySpans.length == 1 &&
          disabledWorkingDirectorySpans.single.kind ==
              TerminalSettingsSyntaxKind.comment &&
          disabledWorkingDirectorySpans.single.start ==
              disabledWorkingDirectory.lineStart &&
          disabledWorkingDirectorySpans.single.end ==
              disabledWorkingDirectory.lineEnd &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start &&
          settings.activeView!.lineHighlight?.color ==
              terminalSettingsCurrentLineColor &&
          !identical(initialSettingsWindow, nativeWindow) &&
          initialOwner.surface.backgroundOpacity ==
              configuredBackgroundOpacity &&
          hierarchy.paneResourceCount == 1 &&
          owners.length == 1,
      'Settings did not publish its initial document and visual state',
    );
    final int lastSettingsLocation = settings.state.occurrences.last.nameStart;
    for (var step = 0; step < 64; step++) {
      _injectKeyEventForTesting(
        application,
        initialSettingsWindow,
        keyCode: 125,
        modifiers: 0,
        characters: '',
        charactersIgnoringModifiers: '',
        monotonicNanoseconds: eventTimestamp++,
      );
    }
    await waitFor(
      () =>
          settings.state.selection.start >= lastSettingsLocation &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start,
      'native Settings NORMAL navigation did not reveal the final option',
    );
    _injectKeyEventForTesting(
      application,
      initialSettingsWindow,
      keyCode: 44,
      modifiers: 0,
      characters: '/',
      charactersIgnoringModifiers: '/',
      monotonicNanoseconds: eventTimestamp++,
    );
    _injectKeyEventForTesting(
      application,
      initialSettingsWindow,
      keyCode: 17,
      modifiers: 0,
      characters: 'font-family',
      charactersIgnoringModifiers: 'font-family',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.state.query == 'font-family' &&
          settings.state.selectedOccurrence?.option.name == 'font-family' &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start,
      'native Settings search did not select the unavailable font option',
    );
    _injectKeyEventForTesting(
      application,
      initialSettingsWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () => settings.state.mode == TerminalSettingsEditorMode.normal,
      'native Settings search did not return to NORMAL mode',
    );
    final TerminalSettingsOptionOccurrence initialFont =
        settings.state.selectedOccurrence!;
    final String initialFontDetail = settings.state.renderDetail();
    _expectLifecycle(
      nativeActionInvocations.last == TerminalActionId.openSettings &&
          actionDispatches.last.id == TerminalActionId.openSettings &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          application.debugLiveObjectCount == nativeHandleBaseline + 6 &&
          reloadController.effectiveSnapshot.schema.options.length == 55 &&
          settings.state.occurrences
                  .map(
                    (TerminalSettingsOptionOccurrence occurrence) =>
                        occurrence.option.name,
                  )
                  .toSet()
                  .length ==
              55 &&
          initialFont.draftValue(settings.state.text) == 'SF Mono Terminal' &&
          reloadController.effectiveSnapshot.value(
                TerminalProductConfigSchema.theme,
              ) ==
              TerminalConfiguredTheme.system &&
          reloadController.effectiveSnapshot
              .value(TerminalProductConfigSchema.fontFamily)
              .isEmpty &&
          initialFont.lineIndex == 5 &&
          initialFont.option.applicationPolicy ==
              TerminalConfigApplicationPolicy.newSession &&
          settings.state.diagnostics.length == 3 &&
          initialFontDetail.contains('Current value\n  system\n') &&
          initialFontDetail.contains('Draft\n  SF Mono Terminal\n') &&
          initialFontDetail.contains('ERROR CFG_UNAVAILABLE_VALUE') &&
          initialFontDetail.contains('font-family = system') &&
          (settings.renderedText ?? '').contains('CFG_UNAVAILABLE_VALUE') &&
          !(settings.renderedText ?? '').contains('CFG_INVALID_VALUE') &&
          !(settings.renderedText ?? '').contains('Config Lens') &&
          !(settings.renderedText ?? '').contains('SOURCE') &&
          !(settings.renderedText ?? '').contains('APPLIES') &&
          identical(sessions[initialPaneId], stableSession) &&
          identical(owners[initialPaneId], stableOwner) &&
          identical(hierarchy.windowForTab(initialTab.id), stableWindow),
      'Settings did not expose canonical startup state and diagnostics '
      'without replacing terminal owners',
    );
    final int unavailableSaveDispatchBaseline = actionDispatches.length;
    _injectKeyEventForTesting(
      application,
      initialSettingsWindow,
      keyCode: 1,
      modifiers: ModifierKeys.commandBit,
      characters: 's',
      charactersIgnoringModifiers: 's',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.saveRequestCount == 1 &&
          settings.state.saveState == TerminalSettingsSaveState.invalid,
      'unavailable font draft was not rejected before persistence',
    );
    _expectLifecycle(
      settings.lastSaveResult?.disposition ==
              TerminalSettingsDocumentSaveDisposition.rejected &&
          settings.lastSaveResult!.diagnostics.any(
            (TerminalConfigDiagnostic diagnostic) =>
                diagnostic.code == 'CFG_UNAVAILABLE_VALUE',
          ) &&
          File(configurationPath)
              .readAsStringSync()
              .contains('font-family = SF Mono Terminal') &&
          reloadController.acceptedGeneration == 0 &&
          configurationAuthority.acceptedGeneration == 0 &&
          settings.reloadRequestCount == 0 &&
          actionDispatches.length == unavailableSaveDispatchBaseline &&
          identical(sessions[initialPaneId], stableSession) &&
          identical(owners[initialPaneId], stableOwner),
      'unavailable Settings save changed the file, config, or terminal owners',
    );
    final TerminalActionDispatchResult singletonDispatch = await dispatcher
        .dispatch(TerminalActionId.openSettings);
    _expectLifecycle(
      singletonDispatch.disposition ==
              TerminalActionDispatchDisposition.executed &&
          identical(settings.activeWindow, initialSettingsWindow) &&
          application.debugLiveObjectCount == nativeHandleBaseline + 6,
      'shared Settings redispatch created duplicate native owners',
    );
    _injectKeyEventForTesting(
      application,
      initialSettingsWindow,
      keyCode: 53,
      modifiers: 0,
      characters: '\u001b',
      charactersIgnoringModifiers: '\u001b',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          !settings.isOpen &&
          application.debugLiveObjectCount == nativeHandleBaseline &&
          settings.terminalResponderRestoreCount ==
              settingsResponderBaseline + 1,
      'native Settings close did not restore focus and release its owners',
    );

    const String paletteMarker = '__DT_CONFIG_PALETTE__';
    initialOwner.pane.insertText(
      "printf '\\033[32m__DT_CONFIG_%s__\\033[0m\\n' PALETTE",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarkerPresented(
      initialOwner,
      paletteMarker,
      timeout: const Duration(seconds: 8),
    );
    final TerminalScreen paletteScreen = initialScreens.activeScreen;
    final _TerminalAsciiPosition palettePosition = _findAscii(
      paletteScreen,
      paletteMarker,
    )!;
    _expectLifecycle(
      paletteScreen.palette.resolveToken(
            paletteScreen.foregroundAt(
              palettePosition.row,
              palettePosition.column,
            ),
            foreground: true,
          ) ==
          configuredAnsiGreen,
      'configured ANSI palette color did not reach a presented Metal frame',
    );

    const String optionMarker = 'c3a5__END__';
    initialOwner.pane.insertText(
      "printf '__DT_OPTION_HEX__'; "
      "dd bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \\n'; "
      "printf '__END__\\n'",
    );
    await initialOwner.pane.submit();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final TerminalTextInputRouteResult optionResult = initialOwner.textRouter
        .route(
          TerminalTextInputKeyEvent(
            clientId: initialOwner.client.clientId,
            generation: initialOwner.textRouter.lastGeneration + 1,
            monotonicNanoseconds: eventTimestamp++,
            kind: TerminalTextInputKeyKind.down,
            keyCode: 0,
            modifiers: const ModifierKeys(ModifierKeys.optionBit),
            isRepeat: false,
            characters: 'å',
            charactersIgnoringModifiers: 'a',
          ),
        );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(
      initialSession,
      optionMarker,
      timeout: const Duration(seconds: 8),
    );
    _expectLifecycle(
      optionResult.disposition == TerminalTextInputRouteDisposition.rawKey,
      'configured Option key did not use the raw terminal key route',
    );

    const String paneActionReady = '__DT_KEY_PANE__';
    const String paneActionMarker = '${paneActionReady}__END__';
    initialOwner.pane.insertText(
      "printf '__DT_KEY_%s__' PANE; "
      "dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \\n'; "
      "printf '__END__\\n'",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, paneActionReady);
    final int endOfFileBaseline = endOfFileActionCount();
    final TerminalKeyRouteResult paneActionResult = routeConfiguredKey(
      initialOwner,
      keyCode: 14,
      modifiers: ModifierKeys.controlBit,
      characters: '\x05',
      charactersIgnoringModifiers: 'e',
    );
    await _waitForAsciiMarker(
      initialSession,
      paneActionMarker,
      timeout: const Duration(seconds: 8),
    );
    _expectLifecycle(
      paneActionResult.disposition == TerminalKeyRouteDisposition.action &&
          paneActionResult.action == TerminalKeyBindingAction.sendEndOfFile &&
          paneActionResult.applicationAction == null &&
          endOfFileActionCount() == endOfFileBaseline + 1,
      'configured pane action did not execute exactly once',
    );

    const String unbindReady = '__DT_KEY_UNBIND__';
    const String unbindMarker = '${unbindReady}__END__';
    initialOwner.pane.insertText(
      "printf '__DT_KEY_%s__' UNBIND; "
      "dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \\n'; "
      "printf '__END__\\n'",
    );
    await initialOwner.pane.submit();
    await _waitForAsciiMarker(initialSession, unbindReady);
    final TerminalKeyRouteResult unbindResult = routeConfiguredKey(
      initialOwner,
      keyCode: 2,
      modifiers: ModifierKeys.controlBit,
      characters: '\x04',
      charactersIgnoringModifiers: 'd',
    );
    await _waitForAsciiMarker(
      initialSession,
      unbindMarker,
      timeout: const Duration(seconds: 8),
    );
    _expectLifecycle(
      unbindResult.disposition == TerminalKeyRouteDisposition.encoded &&
          unbindResult.encodedByteCount == 1 &&
          unbindResult.action == null &&
          unbindResult.applicationAction == null &&
          endOfFileActionCount() == endOfFileBaseline + 1,
      'configured unbind did not restore ordinary encoded Control-D',
    );

    final TerminalKeyRouteResult passthroughResult = routeConfiguredKey(
      initialOwner,
      keyCode: 40,
      modifiers: ModifierKeys.commandBit,
      characters: 'k',
      charactersIgnoringModifiers: 'k',
    );
    initialOwner.pane.deleteBackward();
    _expectLifecycle(
      passthroughResult.disposition == TerminalKeyRouteDisposition.encoded &&
          passthroughResult.encodedByteCount == 1 &&
          passthroughResult.action == null &&
          passthroughResult.applicationAction == null,
      'configured Command passthrough did not encode one terminal byte',
    );

    final int initialRows = initialScreens.activeScreen.rows;
    initialOwner.pane.insertText(
      "i=0; while (( i < ${initialRows + 32} )); do "
      "printf '__DT_CONFIG_HISTORY_%03d__\\n' \$i; ((i++)); done",
    );
    await initialOwner.pane.submit();
    await waitFor(
      () =>
          initialScreens.scrollback.totalRowsAppended >
              configuredScrollbackLines &&
          _findAscii(initialScreens.activeScreen, prompt) != null,
      'configured output did not fill and cap primary-screen history',
    );
    _expectLifecycle(
      initialScreens.scrollback.length <= configuredScrollbackLines &&
          initialScreens.scrollback.allocatedBytes <= configuredScrollbackBytes,
      'configured scrollback exceeded its line or byte cap',
    );

    final MenuItem reloadItem = menu.itemForAction(
      TerminalActionId.reloadConfiguration,
    );
    _expectLifecycle(
      reloadItem.isEnabled &&
          reloadItem.keyEquivalent.isEmpty &&
          reloadController.acceptedGeneration == 0 &&
          configurationAuthority.acceptedGeneration == 0,
      'reload action was unavailable or incorrectly reserved a native shortcut',
    );
    final MenuItem paletteItem = menu.itemForAction(
      TerminalActionId.openCommandPalette,
    );
    final int paletteInvocationBaseline = nativeActionInvocations.length;
    final int paletteDispatchBaseline = actionDispatches.length;
    final int paletteResponderBaseline = palette.terminalResponderRestoreCount;
    paletteItem.performAction();
    await waitFor(
      () =>
          palette.isOpen &&
          nativeActionInvocations.length == paletteInvocationBaseline + 1 &&
          actionDispatches.length == paletteDispatchBaseline + 1,
      'configuration acceptance could not open the shared command palette',
    );
    final Window paletteWindow = palette.activeWindow!;
    _expectLifecycle(
      !identical(paletteWindow, nativeWindow) &&
          initialOwner.surface.backgroundOpacity ==
              configuredBackgroundOpacity &&
          hierarchy.paneResourceCount == 1 &&
          owners.length == 1,
      'Command Palette entered the terminal surface opacity boundary',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 1,
      modifiers: 0,
      characters: 'settings',
      charactersIgnoringModifiers: 'settings',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          palette.state.query == 'settings' &&
          palette.state.selectedAction?.definition.id ==
              TerminalActionId.openSettings,
      'command palette did not discover the shared Settings action',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          !palette.isOpen &&
          settings.isOpen &&
          actionDispatches.length == paletteDispatchBaseline + 2 &&
          application.debugLiveObjectCount == nativeHandleBaseline + 6,
      'command palette did not transfer native ownership to Settings',
    );
    _expectLifecycle(
      palette.lastDispatchResult?.id == TerminalActionId.openSettings &&
          palette.lastDispatchResult?.disposition ==
              TerminalActionDispatchDisposition.executed &&
          palette.terminalResponderRestoreCount == paletteResponderBaseline &&
          actionDispatches.last.id == TerminalActionId.openSettings,
      'command-palette Settings dispatch stole focus or lost shared identity',
    );
    final Window reloadSettingsWindow = settings.activeWindow!;
    _expectLifecycle(
      !identical(reloadSettingsWindow, nativeWindow) &&
          initialOwner.surface.backgroundOpacity ==
              configuredBackgroundOpacity &&
          hierarchy.paneResourceCount == 1 &&
          owners.length == 1,
      'Settings entered the terminal surface opacity boundary',
    );
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 44,
      modifiers: 0,
      characters: '/',
      charactersIgnoringModifiers: '/',
      monotonicNanoseconds: eventTimestamp++,
    );
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 3,
      modifiers: 0,
      characters: 'font-size',
      charactersIgnoringModifiers: 'font-size',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.state.query == 'font-size' &&
          settings.state.selectedOccurrence?.option.name == 'font-size' &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start,
      'Settings did not search the accepted font-size entry',
    );
    _expectLifecycle(
      reloadController.effectiveSnapshot.value(
                TerminalProductConfigSchema.fontSize,
              ) ==
              18 &&
          settings.state.selectedOccurrence?.option.applicationPolicy ==
              TerminalConfigApplicationPolicy.newSession &&
          (settings.renderedText ?? '').contains('After save') &&
          (settings.renderedText ?? '').contains('New terminals') &&
          !(settings.renderedText ?? '').contains('SOURCE'),
      'Settings lost accepted font-size value or contextual save behavior',
    );
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () => settings.state.mode == TerminalSettingsEditorMode.normal,
      'Settings search did not return to NORMAL before editing',
    );
    final List<TerminalSettingsSyntaxSpan> normalSyntax =
        settings.state.syntaxSpans;
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 34,
      modifiers: 0,
      characters: 'i',
      charactersIgnoringModifiers: 'i',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.state.mode == TerminalSettingsEditorMode.insert &&
          settings.activeView!.snapshot.isEditable &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start,
      'Settings did not enter INSERT on the same native editor',
    );
    _expectLifecycle(
      identical(normalSyntax, settings.state.syntaxSpans),
      'entering INSERT recomputed the syntax projection',
    );

    final String originalConfiguration = File(configurationPath)
        .readAsStringSync();
    final String invalidDraft = settings.state.text.replaceFirst(
      'font-size = 18',
      'font-size = enormous',
    );
    _expectLifecycle(
      invalidDraft != settings.state.text,
      'configuration acceptance could not locate the font-size draft',
    );
    final int invalidCaret = invalidDraft.indexOf('enormous');
    settings.activeView!.setDocument(
      TextEditorDocument(
        text: invalidDraft,
        selection: TextEditorSelection(start: invalidCaret),
      ),
    );
    settings.synchronizeNativeEditor();
    _expectLifecycle(
      settings.activeView!.lineHighlight?.location == invalidCaret,
      'native INSERT caret did not update the current-line highlight',
    );
    final int rejectedDispatchBaseline = actionDispatches.length;
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 1,
      modifiers: ModifierKeys.commandBit,
      characters: 's',
      charactersIgnoringModifiers: 's',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.saveRequestCount == 2 &&
          settings.state.saveState == TerminalSettingsSaveState.invalid,
      'invalid native Settings save did not complete exactly once',
    );
    _expectLifecycle(
      settings.lastSaveResult?.disposition ==
              TerminalSettingsDocumentSaveDisposition.rejected &&
          settings.state.diagnostics.any(
            (TerminalConfigDiagnostic diagnostic) =>
                diagnostic.code == 'CFG_INVALID_VALUE',
          ) &&
          settings.state.diagnosticSpans.isNotEmpty &&
          reloadController.acceptedGeneration == 0 &&
          configurationAuthority.acceptedGeneration == 0 &&
          configurationReloads.isEmpty &&
          actionDispatches.length == rejectedDispatchBaseline &&
          settings.reloadRequestCount == 0 &&
          settings.lastReloadResult == null &&
          File(configurationPath).readAsStringSync() == originalConfiguration &&
          (settings.renderedText ?? '').contains('Fix:') &&
          identical(sessions[initialPaneId], stableSession) &&
          identical(owners[initialPaneId], stableOwner) &&
          identical(hierarchy.windowForTab(initialTab.id), stableWindow) &&
          initialScreens.palette.defaultForeground == configuredForeground &&
          initialOwner.surface.fontMetrics.pointSize == 18 &&
          initialScreens.scrollback.maxLines == configuredScrollbackLines,
      'invalid save did not retain the file and last-known-good resources',
    );

    final String correctedDraft =
        '''working-directory = $reloadedWorkingDirectory
theme = system
palette-foreground = #a0b0c0
palette-background = #202122
palette-cursor = #c0b0a0
palette-2 = #43ba21
font-family = Menlo
font-size = 20
font-synthetic-style = deny
font-variation-regular = wght=800
font-codepoint-override = U+2500..U+257F=Menlo
window-width = 980
window-height = 640
window-padding-horizontal = 9
window-padding-vertical = 7
background-opacity = 0.45
context-dock-width = 460
macos-option-key = escape
scrollback-lines = 12
scrollback-bytes = 2MiB
cursor-shape = underline
cursor-blink = true
keybind = control+e=unbind
keybind = control+d=terminal.send-end-of-file
keybind = command+k=passthrough
keybind = control+k=pane.focus-next
keybind = command+right=pane.focus-left
''';
    final int correctedCaret = correctedDraft.indexOf('font-size = 20');
    settings.activeView!.setDocument(
      TextEditorDocument(
        text: correctedDraft,
        selection: TextEditorSelection(start: correctedCaret),
      ),
    );
    settings.synchronizeNativeEditor();
    _expectLifecycle(
      settings.activeView!.lineHighlight?.location == correctedCaret,
      'corrected INSERT caret did not update the current-line highlight',
    );
    final int opacityFrameBaseline = initialOwner.surface
        .snapshot()
        .acceptedFrameCount;
    final int appliedDispatchBaseline = actionDispatches.length;
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 1,
      modifiers: ModifierKeys.commandBit,
      characters: 's',
      charactersIgnoringModifiers: 's',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          configurationReloads.length == 1 &&
          settings.saveRequestCount == 3 &&
          actionDispatches.length == appliedDispatchBaseline + 1,
      'corrected native Settings save/reload did not complete exactly once',
    );
    final TerminalConfigReloadResult appliedReload = configurationReloads.last;
    await waitFor(
      () =>
          initialOwner.surface.backgroundOpacity == reloadedBackgroundOpacity &&
          initialOwner.surface.snapshot().acceptedFrameCount >
              opacityFrameBaseline,
      'accepted live opacity did not reach the existing terminal frame',
    );
    _expectLifecycle(
      appliedReload.disposition == TerminalConfigReloadDisposition.applied &&
          appliedReload.diagnostics.isEmpty &&
          appliedReload.changePlan!.liveChanges.length == 4 &&
          appliedReload.changePlan!.newSessionChanges.length == 16 &&
          reloadController.acceptedGeneration == 1 &&
          configurationAuthority.acceptedGeneration == 1 &&
          configurationAuthority.liveGeneration == 1 &&
          !contextDockState.snapshotForWindow(initialWindow.id)!.isVisible &&
          contextDockState.snapshotForWindow(initialWindow.id)!.width == 460 &&
          actionDispatches.last.id == TerminalActionId.reloadConfiguration &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          settings.saveRequestCount == 3 &&
          settings.reloadRequestCount == 1 &&
          settings.lastSaveResult?.isSaved == true &&
          reloadController.effectiveSnapshot.value(
                TerminalProductConfigSchema.fontSize,
              ) ==
              20 &&
          File(configurationPath).readAsStringSync() == correctedDraft &&
          (FileStat.statSync(configurationPath).mode & 0xFFF) ==
              configurationPermissionBits &&
          settings.state.diagnostics.isEmpty &&
          identical(sessions[initialPaneId], stableSession) &&
          identical(owners[initialPaneId], stableOwner) &&
          identical(hierarchy.windowForTab(initialTab.id), stableWindow) &&
          initialScreens.palette.defaultForeground == configuredForeground &&
          initialOwner.surface.fontMetrics.pointSize == 18 &&
          initialOwner.surface.horizontalPadding ==
              configuredHorizontalPadding &&
          initialOwner.surface.backgroundOpacity == reloadedBackgroundOpacity &&
          initialScreens.scrollback.maxLines == configuredScrollbackLines &&
          initialScreens.activeScreen.cursorShape == TerminalCursorShape.bar,
      'accepted reload did not preserve existing new-session resources',
    );
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 53,
      modifiers: 0,
      characters: '\u001b',
      charactersIgnoringModifiers: '\u001b',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          settings.state.mode == TerminalSettingsEditorMode.normal &&
          !settings.activeView!.snapshot.isEditable &&
          settings.activeView!.lineHighlight?.location ==
              settings.state.selection.start,
      'Settings Escape did not leave INSERT without changing surfaces',
    );
    _injectKeyEventForTesting(
      application,
      reloadSettingsWindow,
      keyCode: 53,
      modifiers: 0,
      characters: '\u001b',
      charactersIgnoringModifiers: '\u001b',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          !settings.isOpen &&
          application.debugLiveObjectCount == nativeHandleBaseline &&
          settings.terminalResponderRestoreCount ==
              settingsResponderBaseline + 2,
      'Settings reload workflow did not release owners and restore focus',
    );
    final int liveEofBaseline = endOfFileActionCount();
    final TerminalKeyRouteResult liveUnbindResult = routeConfiguredKey(
      initialOwner,
      keyCode: 14,
      modifiers: ModifierKeys.controlBit,
      characters: '\x05',
      charactersIgnoringModifiers: 'e',
    );
    final TerminalKeyRouteResult liveOptionResult = routeConfiguredKey(
      initialOwner,
      keyCode: 0,
      modifiers: ModifierKeys.optionBit,
      characters: 'å',
      charactersIgnoringModifiers: 'a',
    );
    _expectLifecycle(
      liveUnbindResult.disposition == TerminalKeyRouteDisposition.encoded &&
          liveUnbindResult.encodedByteCount == 1 &&
          liveUnbindResult.action == null &&
          endOfFileActionCount() == liveEofBaseline &&
          liveOptionResult.disposition == TerminalKeyRouteDisposition.encoded &&
          liveOptionResult.encodedByteCount == 3,
      'existing pane did not observe accepted live input policy',
    );

    final MenuItem splitRightItem = menu.itemForAction(
      TerminalActionId.splitPaneRight,
    );
    _expectLifecycle(
      splitRightItem.isEnabled &&
          splitRightItem.keyEquivalent == 'd' &&
          splitRightItem.modifiers.bits == ModifierKeys.commandBit,
      'reserved Command-D native menu shortcut was not retained',
    );
    final int nativeSplitBaseline = nativeActionInvocations.length;
    final int splitDispatchBaseline = actionDispatches.length;
    final int splitInputBaseline = terminalInputDeliveryCount();
    splitRightItem.performAction();
    await waitFor(
      () =>
          state.paneCount == 2 &&
          hierarchy.paneResourceCount == 2 &&
          nativeActionInvocations.length == nativeSplitBaseline + 1 &&
          actionDispatches.length == splitDispatchBaseline + 1,
      'reserved native Command-D did not split exactly once',
    );
    _expectLifecycle(
      nativeActionInvocations.last == TerminalActionId.splitPaneRight &&
          actionDispatches.last.id == TerminalActionId.splitPaneRight &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          terminalInputDeliveryCount() == splitInputBaseline,
      'native menu priority leaked Command-D into terminal input',
    );

    final PaneId nextPaneId = initialTab.paneIds.singleWhere(
      (PaneId paneId) => paneId != initialPaneId,
    );
    final int applicationDispatchBaseline = actionDispatches.length;
    final int applicationNativeBaseline = nativeActionInvocations.length;
    final int applicationInputBaseline = terminalInputDeliveryCount();
    final TerminalKeyRouteResult applicationActionResult = routeConfiguredKey(
      initialOwner,
      keyCode: 40,
      modifiers: ModifierKeys.controlBit,
      characters: '\x0b',
      charactersIgnoringModifiers: 'k',
    );
    await waitFor(
      () =>
          initialTab.focusedPaneId == nextPaneId &&
          actionDispatches.length == applicationDispatchBaseline + 1,
      'configured application action did not focus the next pane once',
    );
    _expectLifecycle(
      applicationActionResult.disposition ==
              TerminalKeyRouteDisposition.action &&
          applicationActionResult.action == null &&
          applicationActionResult.applicationAction ==
              TerminalActionId.focusNextPane &&
          actionDispatches.last.id == TerminalActionId.focusNextPane &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          nativeActionInvocations.length == applicationNativeBaseline &&
          terminalInputDeliveryCount() == applicationInputBaseline + 1,
      'configured application action did not use one non-native dispatch',
    );
    final _TerminalHierarchyProductPane nextOwner = owners[nextPaneId]!;
    final int directionalDispatchBaseline = actionDispatches.length;
    final int directionalNativeBaseline = nativeActionInvocations.length;
    final int directionalInputBaseline = terminalInputDeliveryCount();
    final int directionalWriteBaseline = writeEnqueuedCount();
    final TerminalKeyRouteResult directionalOverrideResult = routeConfiguredKey(
      nextOwner,
      keyCode: 124,
      modifiers: ModifierKeys.commandBit,
      characters: '\uF703',
      charactersIgnoringModifiers: '\uF703',
    );
    await waitFor(
      () =>
          initialTab.focusedPaneId == initialPaneId &&
          owners[initialPaneId]!.surface.snapshot().isPaneActive &&
          !nextOwner.surface.snapshot().isPaneActive &&
          actionDispatches.length == directionalDispatchBaseline + 1,
      'live Command+Right override did not focus the left pane exactly once',
    );
    _expectLifecycle(
      directionalOverrideResult.disposition ==
              TerminalKeyRouteDisposition.action &&
          directionalOverrideResult.applicationAction ==
              TerminalActionId.focusPaneLeft &&
          actionDispatches.last.id == TerminalActionId.focusPaneLeft &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          nativeActionInvocations.length == directionalNativeBaseline &&
          terminalInputDeliveryCount() == directionalInputBaseline + 1 &&
          writeEnqueuedCount() == directionalWriteBaseline,
      'live directional override used native dispatch or wrote to the PTY',
    );

    await dispatch(TerminalActionId.newTab);
    await dispatch(TerminalActionId.newWindow);
    _expectLifecycle(
      state.windowCount == 2 &&
          state.tabCount == 3 &&
          state.paneCount == 4 &&
          hierarchy.nativeWindowCount == 3 &&
          hierarchy.paneResourceCount == 4,
      'configured profile could not create the ordinary split/tab/window set',
    );
    for (final TerminalSession session in sessions.values) {
      await _waitForAsciiMarker(session, prompt);
    }

    final List<TerminalScreenSet> screenSets = sessions.values
        .map((TerminalSession session) => session.terminalScreenSet)
        .toList(growable: false);
    final List<_TerminalHierarchyProductPane> paneOwners = owners.values.toList(
      growable: false,
    );
    final List<PaneId> reloadedPaneIds = sessions.keys
        .where((PaneId paneId) => paneId != initialPaneId)
        .toList(growable: false);
    await waitFor(
      () => reloadedPaneIds.every((PaneId paneId) {
        final TerminalLiveMetalSurfaceSnapshot snapshot = owners[paneId]!
            .surface
            .snapshot();
        return snapshot.accessibilityGeneration > 0 &&
            snapshot.accessibilityContentOriginX == reloadedHorizontalPadding &&
            snapshot.accessibilityContentOriginY == reloadedVerticalPadding;
      }),
      'configured accessibility origin did not reach reloaded surfaces',
    );
    final bool initialResourcesRetained =
        initialScreens.palette.defaultForeground == configuredForeground &&
        initialScreens.palette.defaultBackground == configuredBackground &&
        initialScreens.palette.cursorColor == configuredCursor &&
        initialScreens.palette.colorAt(2) == configuredAnsiGreen &&
        initialScreens.scrollback.maxLines == configuredScrollbackLines &&
        initialScreens.scrollback.maxBytes == configuredScrollbackBytes &&
        initialScreens.activeScreen.cursorShape == TerminalCursorShape.bar &&
        !initialScreens.activeScreen.cursorBlinking &&
        initialOwner.surface.fontFamily.isEmpty &&
        initialOwner.surface.fontMetrics.pointSize == 18 &&
        initialOwner.surface.fontCatalogConfiguration.variationCount == 1 &&
        initialOwner
                .surface
                .fontCatalogConfiguration
                .codepointOverrides
                .length ==
            1 &&
        initialOwner.surface.horizontalPadding == configuredHorizontalPadding &&
        initialOwner.surface.verticalPadding == configuredVerticalPadding &&
        initialOwner.surface.backgroundOpacity == reloadedBackgroundOpacity;
    final bool reloadedResourcesProjected = reloadedPaneIds.every((
      PaneId paneId,
    ) {
      final TerminalScreenSet screens = sessions[paneId]!.terminalScreenSet;
      final _TerminalHierarchyProductPane owner = owners[paneId]!;
      final TerminalProductConfiguration configuration =
          paneConfigurations[paneId]!;
      final TerminalLiveMetalSurfaceSnapshot snapshot = owner.surface
          .snapshot();
      final TerminalFontCatalogDiagnostics fontDiagnostics = owner.surface
          .fontDiagnostics();
      return launchWorkingDirectories[paneId] == reloadedWorkingDirectory &&
          configuration.workingDirectory == reloadedWorkingDirectory &&
          screens.palette.defaultForeground == reloadedForeground &&
          screens.palette.defaultBackground == reloadedBackground &&
          screens.palette.cursorColor == reloadedCursor &&
          screens.palette.colorAt(2) == reloadedAnsiGreen &&
          screens.scrollback.maxLines == reloadedScrollbackLines &&
          screens.scrollback.maxBytes == reloadedScrollbackBytes &&
          screens.activeScreen.cursorShape == TerminalCursorShape.underline &&
          screens.activeScreen.cursorBlinking &&
          owner.surface.fontFamily == 'Menlo' &&
          owner.surface.fontMetrics.pointSize == 20 &&
          owner.surface.syntheticStylePolicy ==
              TerminalSyntheticStylePolicy.reject &&
          owner.surface.fontCatalogConfiguration.variationCount == 1 &&
          owner.surface.fontCatalogConfiguration.codepointOverrides.length ==
              1 &&
          fontDiagnostics.configuredVariationCount == 1 &&
          fontDiagnostics.unavailableVariationCount == 1 &&
          fontDiagnostics.configuredOverrideCount == 1 &&
          fontDiagnostics.availableOverrideCount == 1 &&
          owner.surface.horizontalPadding == reloadedHorizontalPadding &&
          owner.surface.verticalPadding == reloadedVerticalPadding &&
          owner.surface.backgroundOpacity == reloadedBackgroundOpacity &&
          snapshot.contentOffsetX > 0 &&
          snapshot.contentOffsetY > 0 &&
          snapshot.accessibilityGeneration > 0 &&
          snapshot.accessibilityContentOriginX == reloadedHorizontalPadding &&
          snapshot.accessibilityContentOriginY == reloadedVerticalPadding &&
          snapshot.contentViewportWidth ==
              snapshot.viewportWidth - snapshot.contentOffsetX * 2 &&
          snapshot.contentViewportHeight ==
              snapshot.viewportHeight - snapshot.contentOffsetY * 2;
    });
    final TerminalWindowState reloadedWindow = state.windows.singleWhere(
      (TerminalWindowState window) => window.id != initialWindow.id,
    );
    final bool windowPolicyProjected =
        initialWindow.tabIds.every((TerminalTabId tabId) {
          final Window window = hierarchy.windowForTab(tabId)!;
          return window.frame.width == configuredWindowWidth &&
              window.frame.height == configuredWindowHeight;
        }) &&
        hierarchy.windowForTab(reloadedWindow.selectedTabId)!.frame.width ==
            reloadedWindowWidth &&
        hierarchy.windowForTab(reloadedWindow.selectedTabId)!.frame.height ==
            reloadedWindowHeight;
    final bool independent =
        screenSets
                .map((TerminalScreenSet screens) => screens.palette)
                .toSet()
                .length ==
            screenSets.length &&
        screenSets
                .map((TerminalScreenSet screens) => screens.scrollback)
                .toSet()
                .length ==
            screenSets.length &&
        paneOwners
                .map((_TerminalHierarchyProductPane owner) => owner.surface)
                .toSet()
                .length ==
            paneOwners.length;
    _expectLifecycle(
      reloadedPaneIds.length == 3 &&
          initialResourcesRetained &&
          reloadedResourcesProjected &&
          windowPolicyProjected &&
          independent &&
          paneOwners.every(
            (_TerminalHierarchyProductPane owner) =>
                owner.surface.backgroundOpacity == reloadedBackgroundOpacity,
          ),
      'reload did not retain existing resources or project independent '
      'new-session resources',
    );
    _expectLifecycle(
      paneOwners.every((_TerminalHierarchyProductPane owner) {
        final TerminalLiveMetalSurfaceSnapshot snapshot = owner.surface
            .snapshot();
        return !snapshot.isDisposed;
      }),
      'reload unexpectedly disposed a live Metal surface',
    );
    final PaneId activeOpacityPaneId =
        state.activeWindow!.selectedTab.focusedPaneId;
    final int finalOpacityFrameBaseline = owners[activeOpacityPaneId]!.surface
        .snapshot()
        .acceptedFrameCount;
    final String finalOpacityConfiguration = correctedDraft.replaceFirst(
      'background-opacity = 0.45',
      'background-opacity = 0.6',
    );
    _expectLifecycle(
      finalOpacityConfiguration != correctedDraft,
      'configuration acceptance could not locate background opacity',
    );
    File(configurationPath)
        .writeAsStringSync(finalOpacityConfiguration, flush: true);
    await dispatch(TerminalActionId.reloadConfiguration);
    await waitFor(
      () =>
          owners.values.every(
            (_TerminalHierarchyProductPane owner) =>
                owner.surface.backgroundOpacity == finalBackgroundOpacity,
          ) &&
          owners[activeOpacityPaneId]!.surface.snapshot().acceptedFrameCount >
              finalOpacityFrameBaseline,
      'live opacity reload did not reach every existing window, tab, and pane',
    );
    _expectLifecycle(
      configurationReloads.length == 2 &&
          configurationReloads.last.disposition ==
              TerminalConfigReloadDisposition.applied &&
          configurationReloads.last.changePlan!.liveChanges.length == 1 &&
          configurationReloads.last.changePlan!.newSessionChanges.isEmpty &&
          reloadController.acceptedGeneration == 2 &&
          configurationAuthority.acceptedGeneration == 2 &&
          configurationAuthority.liveGeneration == 2 &&
          !owners[activeOpacityPaneId]!.surface.updateBackgroundOpacity(
            finalBackgroundOpacity,
          ),
      'application-wide opacity reload was not one deduplicated live change',
    );
    _expectLifecycle(
      state.windows.every(
        (TerminalWindowState window) =>
            !contextDockState.snapshotForWindow(window.id)!.isVisible &&
            contextDockState.snapshotForWindow(window.id)!.width == 460,
      ),
      'Dock width did not reach existing and later windows without changing visibility',
    );
    final PaneId contractedPaneId = reloadedPaneIds.first;
    final TerminalPaneLocation contractedLocation = state.locationForPane(
      contractedPaneId,
    )!;
    state
      ..activateWindow(contractedLocation.windowId)
      ..selectTab(contractedLocation.windowId, contractedLocation.tabId)
      ..focusPane(contractedLocation.tabId, contractedPaneId);
    final Window contractedWindow = hierarchy.windowForTab(
      contractedLocation.tabId,
    )!;
    final TerminalNativePaneResources contractedResources = hierarchy
        .resourcesForPane(contractedPaneId)!;
    contractedWindow
      ..show()
      ..selectTab()
      ..makeFirstResponder(contractedResources.view);
    final TerminalLiveMetalSurface contractedSurface =
        owners[contractedPaneId]!.surface;
    contractedSurface.debugVerifyAccessibility();
    final int originGeneration = contractedSurface
        .snapshot()
        .accessibilityGeneration;
    contractedSurface.resizeViewport(logicalWidth: 15, logicalHeight: 9);
    contractedSurface.processPending();
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = contractedSurface
          .snapshot();
      return snapshot.accessibilityGeneration > originGeneration &&
          snapshot.accessibilityContentOriginX == 7 &&
          snapshot.accessibilityContentOriginY == 4;
    }, 'accessibility origin did not contract with an undersized viewport');
    contractedSurface.debugVerifyAccessibility();
    final int contractedGeneration = contractedSurface
        .snapshot()
        .accessibilityGeneration;
    contractedSurface.resizeViewport(logicalWidth: 100, logicalHeight: 100);
    contractedSurface.processPending();
    await waitFor(() {
      final TerminalLiveMetalSurfaceSnapshot snapshot = contractedSurface
          .snapshot();
      return snapshot.accessibilityGeneration > contractedGeneration &&
          snapshot.accessibilityContentOriginX == reloadedHorizontalPadding &&
          snapshot.accessibilityContentOriginY == reloadedVerticalPadding;
    }, 'accessibility origin did not restore its configured padding');
    contractedSurface.debugVerifyAccessibility();

    await dispatch(TerminalActionId.toggleQuickTerminal);
    await waitFor(
      () =>
          state.quickTerminalWindow != null &&
          state.windowCount == 3 &&
          state.tabCount == 4 &&
          state.paneCount == 5 &&
          hierarchy.nativeWindowCount == 4 &&
          hierarchy.paneResourceCount == 5 &&
          sessions.length == 5 &&
          owners.length == 5,
      'configuration acceptance could not create the later Quick Terminal',
    );
    final TerminalWindowState quickWindow = state.quickTerminalWindow!;
    final PaneId quickPaneId = quickWindow.selectedTab.focusedPaneId;
    await _waitForAsciiMarker(sessions[quickPaneId]!, prompt);
    _expectLifecycle(
      quickWindow.role == TerminalWindowRole.quickTerminal &&
          owners[quickPaneId]!.surface.backgroundOpacity ==
              finalBackgroundOpacity &&
          owners.values.every(
            (_TerminalHierarchyProductPane owner) =>
                owner.surface.backgroundOpacity == finalBackgroundOpacity,
          ) &&
          !settings.isOpen &&
          !palette.isOpen,
      'later Quick Terminal or an existing terminal surface diverged from the '
      'shared opacity value',
    );

    await dispatch(TerminalActionId.quitApplication);
    if (!closed.isCompleted) {
      await dispatch(TerminalActionId.quitApplication);
    }
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          allSessions.length == 5 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'configured product did not cleanly release all resources',
    );
    stdout.writeln(
      'TERMINAL_CONFIGURATION_TEST config_file=true palette=true font=true '
      'font_configuration=true font_diagnostics=true '
      'window=true padding=true accessibility_padding=true option_text=true '
      'scrollback=true cursor=true '
      'keybind_pane=true keybind_application=true unbind=true '
      'passthrough=true invalid_recovery=true native_menu_priority=true '
      'unavailable_fallback=true reload_rejected=true '
      'save_unavailable_rejected=true save_rejected=true save_applied=true '
      'permissions=true reload_applied=true '
      'live_existing=true background_opacity=true terminal_only=true '
      'new_session=true settings_menu=true settings_palette=true '
      'settings_singleton=true settings_search=true settings_edit=true '
      'settings_style_stable=true settings_disabled_lines=true '
      'settings_cursor_line=true settings_initial_document=true '
      'settings_viewport_follow=true '
      'settings_diagnostics=true '
      'settings_reload=true settings_focus=true panes=5 independent=true '
      'quick_terminal=true sessions_clean=5 text_clients=0 native_handles=0',
    );
    stdout.writeln(
      'TERMINAL_DIRECTIONAL_PANE_KEYBIND_CONFIGURATION_TEST '
      'live_override=true action=pane.focus-left pty_writes=0',
    );
  }

  static Future<void> _exerciseUserActionProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalUpdatePresenter updatePresenter,
    required TerminalUpdateController updateController,
    required _TerminalUpdateAcceptanceService updateService,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required int Function() terminalInputDeliveryCount,
    required Map<PaneId, TerminalKeyRouteResult> lastKeyRoutes,
    required Map<PaneId, int> keyRouteCounts,
    required Map<PaneId, int> writeEnqueuedCounts,
    required void Function() reconcile,
    required Completer<void> closed,
    required String prompt,
  }) async {
    var eventTimestamp = 12000000;

    Set<PaneId> activePaneIds() => owners.entries
        .where(
          (MapEntry<PaneId, _TerminalHierarchyProductPane> entry) =>
              !entry.value.surface.isDisposed &&
              entry.value.surface.snapshot().isPaneActive,
        )
        .map(
          (MapEntry<PaneId, _TerminalHierarchyProductPane> entry) => entry.key,
        )
        .toSet();

    bool hasOnlyActivePane(PaneId paneId) {
      final Set<PaneId> active = activePaneIds();
      return active.length == 1 && active.single == paneId;
    }

    int writeEnqueuedCount() => writeEnqueuedCounts.values.fold(
      0,
      (int total, int count) => total + count,
    );

    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    Future<void> performMenuAction(
      TerminalActionId id, {
      required String keyEquivalent,
      required int modifiers,
      required bool Function() completed,
    }) async {
      final MenuItem item = menu.itemForAction(id);
      _expectLifecycle(
        item.isEnabled &&
            item.keyEquivalent == keyEquivalent &&
            item.modifiers.bits == modifiers,
        'user action ${id.stableName} is unavailable or has wrong shortcut',
      );
      final int invocationBaseline = nativeActionInvocations.length;
      final int dispatchBaseline = actionDispatches.length;
      item.performAction();
      await waitFor(
        () =>
            completed() &&
            nativeActionInvocations.length == invocationBaseline + 1 &&
            actionDispatches.length == dispatchBaseline + 1,
        'user action ${id.stableName} did not complete exactly once',
      );
      _expectLifecycle(
        nativeActionInvocations.last == id &&
            actionDispatches.last.id == id &&
            actionDispatches.last.disposition ==
                TerminalActionDispatchDisposition.executed,
        'user action ${id.stableName} did not use the shared dispatcher',
      );
    }

    TerminalKeyRouteResult routePaneKey(
      _TerminalHierarchyProductPane owner, {
      required int keyCode,
      required int modifiers,
      required String characters,
    }) {
      final PaneId paneId = owner.pane.id;
      final int routeBaseline = keyRouteCounts[paneId] ?? 0;
      final TerminalTextInputRouteResult textResult = owner.textRouter.route(
        TerminalTextInputKeyEvent(
          clientId: owner.client.clientId,
          generation: owner.textRouter.lastGeneration + 1,
          monotonicNanoseconds: eventTimestamp++,
          kind: TerminalTextInputKeyKind.down,
          keyCode: keyCode,
          modifiers: ModifierKeys(modifiers),
          isRepeat: false,
          characters: characters,
          charactersIgnoringModifiers: characters,
        ),
      );
      _expectLifecycle(
        textResult.disposition == TerminalTextInputRouteDisposition.rawKey &&
            keyRouteCounts[paneId] == routeBaseline + 1 &&
            lastKeyRoutes[paneId] != null,
        'directional pane key did not cross the raw text-input/key router once',
      );
      return lastKeyRoutes[paneId]!;
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1,
      'user action product did not start from the ordinary 1/1/1 hierarchy',
    );
    await _waitForAsciiMarker(sessions.values.single, prompt);
    await waitFor(
      () => hasOnlyActivePane(state.activeWindow!.selectedTab.focusedPaneId),
      'initial terminal pane did not become the sole active surface',
    );
    final int actionInputBaseline = terminalInputDeliveryCount();

    await performMenuAction(
      TerminalActionId.checkForUpdates,
      keyEquivalent: '',
      modifiers: 0,
      completed: () =>
          updatePresenter.isOpen &&
          updateController.status == TerminalUpdateStatus.available,
    );
    await waitFor(
      () => activePaneIds().isEmpty,
      'update window left a terminal cursor visually active',
    );
    _expectLifecycle(
      updateService.checkCount == 1 &&
          updatePresenter.renderedText?.contains(
                '<b>Authenticated plain release note.</b>',
              ) ==
              true &&
          updatePresenter.renderedText?.contains('https://') == false &&
          terminalInputDeliveryCount() == actionInputBaseline,
      'update action did not render authenticated release notes as plain text',
    );
    final TerminalUpdateOperationResult installResult = await updateController
        .install();
    _expectLifecycle(
      installResult.disposition ==
              TerminalUpdateOperationDisposition.completed &&
          updateController.status == TerminalUpdateStatus.restartRequired &&
          updateService.installCount == 1,
      'update action did not prepare the authenticated candidate once',
    );
    await updatePresenter.dismiss();
    await waitFor(
      () => hasOnlyActivePane(state.activeWindow!.selectedTab.focusedPaneId),
      'terminal focus restoration did not reactivate exactly one pane',
    );
    _expectLifecycle(
      !updatePresenter.isOpen &&
          updatePresenter.terminalResponderRestoreCount == 1 &&
          terminalInputDeliveryCount() == actionInputBaseline,
      'update window did not restore terminal focus without PTY input',
    );

    await performMenuAction(
      TerminalActionId.splitPaneRight,
      keyEquivalent: 'd',
      modifiers: ModifierKeys.commandBit,
      completed: () =>
          state.paneCount == 2 &&
          hierarchy.paneResourceCount == 2 &&
          hierarchy.splitViewCount == 1,
    );
    final TerminalTabState resizedTab = state.activeWindow!.selectedTab;
    await waitFor(
      () => hasOnlyActivePane(resizedTab.focusedPaneId),
      'split creation did not activate only the focused pane',
    );
    final TerminalSplitBranch resizedRoot =
        resizedTab.splitTree.root as TerminalSplitBranch;
    final PaneId leftPaneId = resizedTab.paneIds.first;
    final PaneId rightPaneId = resizedTab.paneIds.last;
    final _TerminalHierarchyProductPane leftOwner = owners[leftPaneId]!;
    final _TerminalHierarchyProductPane rightOwner = owners[rightPaneId]!;
    await waitFor(
      () =>
          leftOwner.surface.snapshot().scale16_16 == 2 * 65536 &&
          rightOwner.surface.snapshot().scale16_16 == 2 * 65536,
      'new split did not publish the original pane Retina raster scale',
    );
    final TerminalLiveMetalSurfaceSnapshot leftBefore = leftOwner.surface
        .snapshot();
    final TerminalLiveMetalSurfaceSnapshot rightBefore = rightOwner.surface
        .snapshot();
    final TerminalFontCatalogMetrics leftMetricsBefore =
        leftOwner.surface.fontMetrics;
    final TerminalFontCatalogMetrics rightMetricsBefore =
        rightOwner.surface.fontMetrics;
    _expectLifecycle(
      rightBefore.scale16_16 == leftBefore.scale16_16,
      'new split did not inherit the original pane Retina raster scale',
    );
    _expectLifecycle(
      <TerminalActionId>[
        TerminalActionId.focusPaneLeft,
        TerminalActionId.focusPaneRight,
        TerminalActionId.focusPaneUp,
        TerminalActionId.focusPaneDown,
        TerminalActionId.moveDividerLeft,
        TerminalActionId.moveDividerRight,
        TerminalActionId.moveDividerUp,
        TerminalActionId.moveDividerDown,
      ].every((TerminalActionId id) {
        final MenuItem item = menu.itemForAction(id);
        return item.keyEquivalent.isEmpty && item.modifiers.bits == 0;
      }),
      'directional pane actions retained a native menu shortcut',
    );
    final int directionalNativeBaseline = nativeActionInvocations.length;
    final int directionalDispatchBaseline = actionDispatches.length;
    final int directionalInputBaseline = terminalInputDeliveryCount();
    final int directionalWriteBaseline = writeEnqueuedCount();
    final TerminalKeyRouteResult focusLeftResult = routePaneKey(
      rightOwner,
      keyCode: 123,
      modifiers: ModifierKeys.commandBit,
      characters: '\uF702',
    );
    await waitFor(
      () =>
          resizedTab.focusedPaneId == leftPaneId &&
          hasOnlyActivePane(leftPaneId) &&
          actionDispatches.length == directionalDispatchBaseline + 1,
      'Command+Left did not move active focus to the left pane exactly once',
    );
    final TerminalKeyRouteResult focusRightResult = routePaneKey(
      leftOwner,
      keyCode: 124,
      modifiers: ModifierKeys.commandBit,
      characters: '\uF703',
    );
    await waitFor(
      () =>
          resizedTab.focusedPaneId == rightPaneId &&
          hasOnlyActivePane(rightPaneId) &&
          actionDispatches.length == directionalDispatchBaseline + 2,
      'Command+Right did not move active focus to the right pane exactly once',
    );
    _expectLifecycle(
      focusLeftResult.applicationAction == TerminalActionId.focusPaneLeft &&
          focusRightResult.applicationAction ==
              TerminalActionId.focusPaneRight &&
          actionDispatches[directionalDispatchBaseline].id ==
              TerminalActionId.focusPaneLeft &&
          actionDispatches[directionalDispatchBaseline + 1].id ==
              TerminalActionId.focusPaneRight &&
          nativeActionInvocations.length == directionalNativeBaseline &&
          terminalInputDeliveryCount() == directionalInputBaseline + 2 &&
          writeEnqueuedCount() == directionalWriteBaseline,
      'Command+arrow focus did not remain non-native and PTY-write-free',
    );
    final TerminalKeyRouteResult dividerRightResult = routePaneKey(
      rightOwner,
      keyCode: 124,
      modifiers: ModifierKeys.shiftBit | ModifierKeys.commandBit,
      characters: '\uF703',
    );
    await waitFor(
      () =>
          (resizedTab.splitTree.root as TerminalSplitBranch).fraction >
              resizedRoot.fraction &&
          actionDispatches.length == directionalDispatchBaseline + 3,
      'Shift+Command+Right did not move the divider exactly once',
    );
    _expectLifecycle(
      dividerRightResult.applicationAction ==
              TerminalActionId.moveDividerRight &&
          actionDispatches.last.id == TerminalActionId.moveDividerRight &&
          actionDispatches.last.disposition ==
              TerminalActionDispatchDisposition.executed &&
          nativeActionInvocations.length == directionalNativeBaseline &&
          terminalInputDeliveryCount() == directionalInputBaseline + 3 &&
          writeEnqueuedCount() == directionalWriteBaseline,
      'Shift+Command+arrow divider movement leaked to native menu or PTY',
    );
    final int hierarchyActionInputBaseline = terminalInputDeliveryCount();
    await waitFor(
      () {
        final TerminalLiveMetalSurfaceSnapshot left = leftOwner.surface
            .snapshot();
        final TerminalLiveMetalSurfaceSnapshot right = rightOwner.surface
            .snapshot();
        return left.columns >= leftBefore.columns &&
            right.columns <= rightBefore.columns &&
            (left.columns > leftBefore.columns ||
                right.columns < rightBefore.columns);
      },
      'Shift+Command+Right terminal grids did not settle after viewport resize',
    );
    final TerminalLiveMetalSurfaceSnapshot leftAfter = leftOwner.surface
        .snapshot();
    final TerminalLiveMetalSurfaceSnapshot rightAfter = rightOwner.surface
        .snapshot();
    _expectLifecycle(
      leftOwner.surface.fontMetrics.cellWidth == leftMetricsBefore.cellWidth &&
          leftOwner.surface.fontMetrics.cellHeight ==
              leftMetricsBefore.cellHeight &&
          leftOwner.surface.fontMetrics.pointSize ==
              leftMetricsBefore.pointSize &&
          rightOwner.surface.fontMetrics.cellWidth ==
              rightMetricsBefore.cellWidth &&
          rightOwner.surface.fontMetrics.cellHeight ==
              rightMetricsBefore.cellHeight &&
          rightOwner.surface.fontMetrics.pointSize ==
              rightMetricsBefore.pointSize &&
          leftAfter.viewportWidth > leftBefore.viewportWidth &&
          rightAfter.viewportWidth < rightBefore.viewportWidth &&
          leftAfter.rows == leftBefore.rows &&
          rightAfter.rows == rightBefore.rows &&
          leftAfter.columns >= leftBefore.columns &&
          rightAfter.columns <= rightBefore.columns &&
          (leftAfter.columns > leftBefore.columns ||
              rightAfter.columns < rightBefore.columns) &&
          leftAfter.scale16_16 == leftBefore.scale16_16 &&
          rightAfter.scale16_16 == rightBefore.scale16_16,
      'Shift+Command+Right did not resize terminal grids with bounded cell '
      'quantization at fixed font and Retina scale: '
      'left=${leftBefore.viewportWidth}/${leftBefore.rows}x'
      '${leftBefore.columns}->${leftAfter.viewportWidth}/'
      '${leftAfter.rows}x${leftAfter.columns} '
      'right=${rightBefore.viewportWidth}/${rightBefore.rows}x'
      '${rightBefore.columns}->${rightAfter.viewportWidth}/'
      '${rightAfter.rows}x${rightAfter.columns} '
      'scales=${leftBefore.scale16_16},${rightBefore.scale16_16}->'
      '${leftAfter.scale16_16},${rightAfter.scale16_16}',
    );

    final MenuItem paletteItem = menu.itemForAction(
      TerminalActionId.openCommandPalette,
    );
    _expectLifecycle(
      paletteItem.isEnabled &&
          paletteItem.keyEquivalent == 'p' &&
          paletteItem.modifiers.bits ==
              ModifierKeys.shiftBit | ModifierKeys.commandBit,
      'user action command palette shortcut is unavailable',
    );
    final int paletteInvocationBaseline = nativeActionInvocations.length;
    final int paletteDispatchBaseline = actionDispatches.length;
    paletteItem.performAction();
    await waitFor(
      () =>
          palette.isOpen &&
          activePaneIds().isEmpty &&
          !(palette.renderedText ?? '').contains(
            'Split Pane Down  — Unavailable',
          ) &&
          nativeActionInvocations.length == paletteInvocationBaseline + 1 &&
          actionDispatches.length == paletteDispatchBaseline + 1,
      'implemented split action remained unavailable in command palette',
    );
    final Window paletteWindow = palette.activeWindow!;
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 1,
      modifiers: 0,
      characters: 'split pane down',
      charactersIgnoringModifiers: 'split pane down',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          palette.state.query == 'split pane down' &&
          palette.state.selectedAction?.definition.id ==
              TerminalActionId.splitPaneDown,
      'command palette did not select Split Pane Down',
    );
    _injectKeyEventForTesting(
      application,
      paletteWindow,
      keyCode: 36,
      modifiers: 0,
      characters: '\r',
      charactersIgnoringModifiers: '\r',
      monotonicNanoseconds: eventTimestamp++,
    );
    await waitFor(
      () =>
          !palette.isOpen &&
          state.paneCount == 3 &&
          hierarchy.paneResourceCount == 3 &&
          hierarchy.splitViewCount == 2 &&
          hasOnlyActivePane(state.activeWindow!.selectedTab.focusedPaneId),
      'command palette Split Pane Down did not project a third pane',
    );
    _expectLifecycle(
      palette.lastDispatchResult?.id == TerminalActionId.splitPaneDown &&
          palette.lastDispatchResult?.disposition ==
              TerminalActionDispatchDisposition.executed &&
          palette.terminalResponderRestoreCount == 1,
      'command palette creation did not execute once and restore focus',
    );

    await performMenuAction(
      TerminalActionId.newTab,
      keyEquivalent: 't',
      modifiers: ModifierKeys.commandBit,
      completed: () =>
          state.tabCount == 2 &&
          state.paneCount == 4 &&
          hierarchy.nativeWindowCount == 2,
    );
    await performMenuAction(
      TerminalActionId.newWindow,
      keyEquivalent: 'n',
      modifiers: ModifierKeys.commandBit,
      completed: () =>
          state.windowCount == 2 &&
          state.tabCount == 3 &&
          state.paneCount == 5 &&
          hierarchy.nativeWindowCount == 3 &&
          hierarchy.paneResourceCount == 5,
    );
    await waitFor(
      () => hasOnlyActivePane(state.activeWindow!.selectedTab.focusedPaneId),
      'new window did not leave exactly one active terminal pane',
    );
    _expectLifecycle(
      terminalInputDeliveryCount() == hierarchyActionInputBaseline,
      'menu or command-palette hierarchy action leaked into terminal input',
    );

    final List<PaneId> createdPaneIds = state.paneIds;
    for (final PaneId paneId in createdPaneIds) {
      await _waitForAsciiMarker(sessions[paneId]!, prompt);
      final TerminalPaneLocation location = state.locationForPane(paneId)!;
      state
        ..activateWindow(location.windowId)
        ..selectTab(location.windowId, location.tabId)
        ..focusPane(location.tabId, paneId);
      reconcile();
      final _TerminalHierarchyProductPane owner = owners[paneId]!;
      hierarchy.windowForTab(location.tabId)!
        ..show()
        ..selectTab()
        ..makeFirstResponder(owner.view);
      await waitFor(
        () => hasOnlyActivePane(paneId),
        'focus projection did not isolate active pane $paneId',
      );
      final TerminalTextInputRouteResult keyResult = owner.textRouter.route(
        TerminalTextInputKeyEvent(
          clientId: owner.client.clientId,
          generation: owner.textRouter.lastGeneration + 1,
          monotonicNanoseconds: eventTimestamp++,
          kind: TerminalTextInputKeyKind.down,
          keyCode: 123,
          modifiers: const ModifierKeys(0),
          isRepeat: false,
          characters: '',
          charactersIgnoringModifiers: '',
        ),
      );
      final String marker = '__DT_USER_ACTION_PANE_${paneId.value}__';
      final TerminalTextInputRouteResult commitResult = owner.textRouter.route(
        TerminalTextInputCommitEvent(
          clientId: owner.client.clientId,
          generation: owner.textRouter.lastGeneration + 1,
          monotonicNanoseconds: eventTimestamp++,
          text: "printf '$marker'",
          replacement: TerminalTextInputRange.notFound,
        ),
      );
      await owner.pane.submit();
      await _waitForAsciiMarker(owner.session, marker);
      await _waitForAsciiMarker(owner.session, prompt);
      _expectLifecycle(
        keyResult.disposition == TerminalTextInputRouteDisposition.rawKey &&
            commitResult.disposition ==
                TerminalTextInputRouteDisposition.committed &&
            createdPaneIds
                    .where(
                      (PaneId candidate) =>
                          _findAscii(
                            sessions[candidate]!.terminalScreenSet.activeScreen,
                            marker,
                          ) !=
                          null,
                    )
                    .length ==
                1,
        'created pane $paneId did not isolate physical-key and IME input',
      );
    }
    _expectLifecycle(
      terminalInputDeliveryCount() - hierarchyActionInputBaseline ==
          createdPaneIds.length * 2,
      'created panes did not each receive one physical key and one IME commit',
    );

    final TerminalWindowState firstWindow = state.windows.first;
    final TerminalTabState firstTab = firstWindow.tabs.first;
    final PaneId closedPaneId = firstTab.paneIds.first;
    state
      ..activateWindow(firstWindow.id)
      ..selectTab(firstWindow.id, firstTab.id)
      ..focusPane(firstTab.id, closedPaneId);
    reconcile();
    await performMenuAction(
      TerminalActionId.closeWindow,
      keyEquivalent: 'w',
      modifiers: ModifierKeys.commandBit,
      completed: () =>
          state.paneForId(closedPaneId) == null &&
          state.windowCount == 2 &&
          state.tabCount == 3 &&
          state.paneCount == 4 &&
          hierarchy.paneResourceCount == 4,
    );
    await waitFor(
      () => hasOnlyActivePane(state.activeWindow!.selectedTab.focusedPaneId),
      'pane close did not reactivate exactly one surviving pane',
    );
    _expectLifecycle(
      allSessions
              .singleWhere(
                (TerminalSession session) => session.id.paneId == closedPaneId,
              )
              .shutdownResult
              ?.isClean ==
          true,
      'menu Close did not cleanly release its exact pane session',
    );

    final MenuItem quitItem = menu.itemForAction(
      TerminalActionId.quitApplication,
    );
    _expectLifecycle(
      quitItem.isEnabled &&
          quitItem.keyEquivalent == 'q' &&
          quitItem.modifiers.bits == ModifierKeys.commandBit,
      'user action Quit is unavailable or has wrong shortcut',
    );
    final int quitInvocationBaseline = nativeActionInvocations.length;
    quitItem.performAction();
    try {
      await closed.future.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      if (!quitItem.isDisposed) quitItem.performAction();
      await closed.future.timeout(const Duration(seconds: 15));
    }
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      nativeActionInvocations.length >= quitInvocationBaseline + 1 &&
          nativeActionInvocations[quitInvocationBaseline] ==
              TerminalActionId.quitApplication &&
          state.isDisposed &&
          hierarchy.isDisposed &&
          allSessions.length == 5 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          updateService.disposeCount == 1 &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'user action Quit did not release all product owners exactly once',
    );
    stdout.writeln(
      'TERMINAL_ACTIVE_PANE_FOCUS_TEST active_count=1 '
      'inactive_cursor=true inactive_background=true '
      'application_focus=true window_focus=true tab_focus=true '
      'split_focus=true overlay_zero_active=true',
    );
    stdout.writeln(
      'TERMINAL_DIRECTIONAL_PANE_KEYBIND_TEST default_focus=true '
      'default_divider=true menu_unreserved=true active_projection=true '
      'pty_writes=0',
    );
    stdout.writeln(
      'TERMINAL_USER_ACTIONS_TEST windows=2 tabs=3 panes=4 '
      'created_panes=5 split_right=true split_down=true new_tab=true '
      'new_window=true palette=true command_availability=true '
      'update=true update_plain_text=true update_zero_write=true '
      'retina_scale=true divider_command=true fixed_cell_metrics=true '
      'grid_resize=true '
      'menu_zero_write=true input_isolated=true close=true quit=true '
      'sessions_clean=5 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseSecureKeyboardEntryProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalCommandPalettePresenter palette,
    required TerminalSettingsInspectorPresenter settings,
    required TerminalQuickTerminalController quickTerminal,
    required TerminalSecureKeyboardEntryController secureKeyboardEntry,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required Map<PaneId, TerminalKeyRouteResult> lastKeyRoutes,
    required Map<PaneId, int> keyRouteCounts,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'Secure Keyboard Entry action ${id.stableName} did not execute',
      );
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          hierarchy.paneResourceCount == 1 &&
          sessions.length == 1 &&
          owners.length == 1 &&
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.disabled &&
          !secureKeyboardEntry.status.desired &&
          !secureKeyboardEntry.status.ownedEnabled,
      'Secure Keyboard Entry product did not start released in a 1/1/1 '
      'hierarchy',
    );
    final TerminalWindowState ordinaryWindow = state.windows.single;
    final TerminalTabState ordinaryTab = ordinaryWindow.selectedTab;
    final PaneId ordinaryPaneId = ordinaryTab.focusedPaneId;
    final TerminalSession ordinarySession = sessions[ordinaryPaneId]!;
    final _TerminalHierarchyProductPane ordinaryOwner = owners[ordinaryPaneId]!;
    final Window ordinaryNative = hierarchy.windowForTab(ordinaryTab.id)!;
    await _waitForAsciiMarker(ordinarySession, prompt);
    if (!application.isActive) {
      appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
        application.eventProtocolVersion,
        30,
        0,
        0,
        19999000,
        0,
        true,
      ]);
    }
    await waitFor(
      () =>
          application.isActive &&
          ordinaryNative.isVisible &&
          ordinaryNative.isFocused,
      'ordinary terminal did not become the focused secure-input target',
    );

    const String initialEchoOnMarker = '__DT_SECURE_INITIAL_ECHO_ON__';
    const String echoOffMarker = '__DT_SECURE_ECHO_OFF__';
    ordinaryOwner.pane.insertText(
      "stty echo; printf '\\n$initialEchoOnMarker\\n'; "
      "IFS= read -r _; stty -echo; printf '\\n$echoOffMarker\\n'",
    );
    await ordinaryOwner.pane.submit();
    await _waitForAsciiMarker(ordinarySession, initialEchoOnMarker);
    await waitFor(
      () =>
          ordinaryOwner.pane.processSnapshot().terminalEchoEnabled == true &&
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.disabled &&
          !secureKeyboardEntry.status.ownedEnabled,
      'acceptance setup could not establish released echo-on state',
    );

    final MenuItem secureItem = menu.itemForAction(
      TerminalActionId.toggleSecureKeyboardEntry,
    );
    menu.refresh();
    await waitFor(
      () =>
          secureItem.isEnabled &&
          !secureItem.isChecked &&
          ordinaryOwner.view.badge == null,
      'released Secure Keyboard Entry did not project an unchecked menu and '
      'hidden indicator',
    );

    ordinaryOwner.pane.insertText('continue');
    await ordinaryOwner.pane.submit();
    await _waitForAsciiMarker(ordinarySession, echoOffMarker);
    await waitFor(() {
      final TerminalSecureKeyboardEntryStatus status =
          secureKeyboardEntry.status;
      return status.mode == TerminalSecureKeyboardEntryMode.automatic &&
          status.desired &&
          status.ownedEnabled &&
          status.terminalEchoEnabled == false &&
          ordinaryOwner.pane.processSnapshot().terminalEchoEnabled == false &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryAutomaticBadge;
    }, 'real PTY echo-off did not acquire and indicate automatic secure input');

    final int preeditGeneration = ordinaryOwner.textRouter.lastGeneration + 1;
    final TerminalTextInputRouteResult preeditResult = ordinaryOwner.textRouter
        .route(
          TerminalTextInputPreeditEvent(
            clientId: ordinaryOwner.client.clientId,
            generation: preeditGeneration,
            monotonicNanoseconds: 20000000,
            text: '安全',
            selection: const TerminalTextInputRange(2, 0),
            replacement: TerminalTextInputRange.notFound,
          ),
        );
    await ordinaryOwner.waitForTextInputGeneration(
      preeditGeneration,
      compositionActive: true,
    );
    final TerminalTextInputRouteResult suppressedResult = ordinaryOwner
        .textRouter
        .route(
          TerminalTextInputKeyEvent(
            clientId: ordinaryOwner.client.clientId,
            generation: ordinaryOwner.textRouter.lastGeneration + 1,
            monotonicNanoseconds: 20001000,
            kind: TerminalTextInputKeyKind.down,
            keyCode: 0,
            modifiers: const ModifierKeys(0),
            isRepeat: false,
            characters: 'a',
            charactersIgnoringModifiers: 'a',
          ),
        );
    const String imeMarker = '__DT_SECURE_IME_COMMIT__';
    const String echoOnMarker = '__DT_SECURE_ECHO_ON__';
    final TerminalTextInputRouteResult commitResult = ordinaryOwner.textRouter
        .route(
          TerminalTextInputCommitEvent(
            clientId: ordinaryOwner.client.clientId,
            generation: ordinaryOwner.textRouter.lastGeneration + 1,
            monotonicNanoseconds: 20002000,
            text:
                "printf '$imeMarker\\n'; stty echo; "
                "printf '$echoOnMarker\\n'; /bin/sleep 1",
            replacement: TerminalTextInputRange.notFound,
          ),
        );
    await ordinaryOwner.pane.submit();
    await _waitForAsciiMarker(ordinarySession, imeMarker);
    await _waitForAsciiMarker(ordinarySession, echoOnMarker);
    await waitFor(() {
      final TerminalSecureKeyboardEntryStatus status =
          secureKeyboardEntry.status;
      return status.mode == TerminalSecureKeyboardEntryMode.disabled &&
          !status.desired &&
          !status.ownedEnabled &&
          status.terminalEchoEnabled == true &&
          ordinaryOwner.pane.processSnapshot().terminalEchoEnabled == true &&
          ordinaryOwner.view.badge == null;
    }, 'real PTY echo-on did not release automatic secure input');
    await _waitForAsciiMarker(ordinarySession, prompt);
    await waitFor(
      () =>
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.automatic &&
          secureKeyboardEntry.status.ownedEnabled,
      'zsh line editing did not restore automatic echo-off ownership',
    );
    _expectLifecycle(
      preeditResult.disposition == TerminalTextInputRouteDisposition.preedit &&
          suppressedResult.disposition ==
              TerminalTextInputRouteDisposition.rawSuppressed &&
          commitResult.disposition ==
              TerminalTextInputRouteDisposition.committed &&
          !ordinaryOwner.textRouter.isCompositionActive &&
          !ordinaryOwner.surface.preeditState.isActive,
      'IME preedit/commit was not isolated from secure-input policy',
    );

    final int menuInvocationBaseline = nativeActionInvocations.length;
    final int menuDispatchBaseline = actionDispatches.length;
    secureItem.performAction();
    await waitFor(
      () =>
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.manual &&
          secureKeyboardEntry.status.ownedEnabled &&
          secureItem.isChecked &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryManualBadge &&
          nativeActionInvocations.length == menuInvocationBaseline + 1 &&
          actionDispatches.length == menuDispatchBaseline + 1,
      'native menu did not acquire manual secure input and project its check',
    );

    await settings.open();
    _expectLifecycle(
      (settings.renderedText ?? '').contains(
            'Secure Keyboard Entry: manual (owned',
          ) &&
          secureKeyboardEntry.manualRequested &&
          secureKeyboardEntry.status.ownedEnabled &&
          secureItem.isChecked,
      'Settings did not expose retained manual secure-input ownership',
    );
    await settings.dismiss();
    await waitFor(
      () =>
          ordinaryNative.isFocused &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryManualBadge,
      'dismissing Settings did not restore the focused manual indication',
    );

    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      30,
      0,
      0,
      21000000,
      0,
      false,
    ]);
    await waitFor(
      () =>
          !application.isActive &&
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.manual &&
          secureKeyboardEntry.status.desired &&
          ordinaryOwner.view.badge == null,
      'application inactivity did not retain manual intent while hiding its '
      'product indication',
    );
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      30,
      0,
      0,
      21001000,
      0,
      true,
    ]);
    await waitFor(
      () =>
          application.isActive &&
          secureKeyboardEntry.status.ownedEnabled &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryManualBadge,
      'application reactivation did not reacquire retained manual intent',
    );

    await palette.open();
    palette
      ..refresh()
      ..state.setQuery('secure keyboard')
      ..refresh();
    _expectLifecycle(
      palette.isOpen &&
          palette.state.selectedAction?.definition.id ==
              TerminalActionId.toggleSecureKeyboardEntry &&
          palette.state.selectedAction!.isEnabled,
      'command palette did not expose the shared secure-input action',
    );
    final TerminalActionDispatchResult paletteResult = await palette.state
        .invokeSelected();
    await palette.dismiss();
    menu.refresh();
    await waitFor(
      () =>
          paletteResult.disposition ==
              TerminalActionDispatchDisposition.executed &&
          !secureKeyboardEntry.manualRequested &&
          secureKeyboardEntry.status.mode ==
              TerminalSecureKeyboardEntryMode.automatic &&
          secureKeyboardEntry.status.ownedEnabled &&
          !secureItem.isChecked &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryAutomaticBadge,
      'command palette did not clear manual intent and restore automatic '
      'secure-input policy',
    );

    final int keyRouteBaseline = keyRouteCounts[ordinaryPaneId] ?? 0;
    final TerminalTextInputRouteResult keyResult = ordinaryOwner.textRouter
        .route(
          TerminalTextInputKeyEvent(
            clientId: ordinaryOwner.client.clientId,
            generation: ordinaryOwner.textRouter.lastGeneration + 1,
            monotonicNanoseconds: 22000000,
            kind: TerminalTextInputKeyKind.down,
            keyCode: 1,
            modifiers: const ModifierKeys(
              ModifierKeys.controlBit | ModifierKeys.shiftBit,
            ),
            isRepeat: false,
            characters: '\u0013',
            charactersIgnoringModifiers: 's',
          ),
        );
    await waitFor(
      () =>
          keyRouteCounts[ordinaryPaneId] == keyRouteBaseline + 1 &&
          lastKeyRoutes[ordinaryPaneId]?.applicationAction ==
              TerminalActionId.toggleSecureKeyboardEntry &&
          secureKeyboardEntry.manualRequested &&
          secureKeyboardEntry.status.ownedEnabled &&
          secureItem.isChecked,
      'configured local keybinding did not use the shared secure-input action',
    );
    _expectLifecycle(
      keyResult.disposition == TerminalTextInputRouteDisposition.rawKey &&
          lastKeyRoutes[ordinaryPaneId]?.disposition ==
              TerminalKeyRouteDisposition.action,
      'configured secure-input keybinding was not consumed as an application '
      'action',
    );

    await dispatch(TerminalActionId.toggleQuickTerminal);
    await waitFor(
      () =>
          quickTerminal.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.visible &&
          state.quickTerminalWindow != null &&
          state.activeWindowId == state.quickTerminalWindow!.id &&
          state.windowCount == 2 &&
          state.paneCount == 2,
      'manual secure input did not coexist with Quick Terminal presentation',
    );
    final TerminalWindowState quickWindow = state.quickTerminalWindow!;
    final PaneId quickPaneId = quickWindow.selectedTab.focusedPaneId;
    final TerminalSession quickSession = sessions[quickPaneId]!;
    final _TerminalHierarchyProductPane quickOwner = owners[quickPaneId]!;
    await _waitForAsciiMarker(quickSession, prompt);
    await waitFor(
      () =>
          secureKeyboardEntry.status.targetIdentity == quickPaneId &&
          secureKeyboardEntry.status.ownedEnabled &&
          quickOwner.view.badge == terminalSecureKeyboardEntryManualBadge &&
          ordinaryOwner.view.badge == null,
      'manual secure-input ownership did not hand its indication to Quick '
      'Terminal',
    );
    await dispatch(TerminalActionId.toggleQuickTerminal);
    await waitFor(
      () =>
          quickTerminal.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.hidden &&
          state.activeWindowId == ordinaryWindow.id &&
          secureKeyboardEntry.status.targetIdentity == ordinaryPaneId &&
          ordinaryOwner.view.badge == terminalSecureKeyboardEntryManualBadge &&
          quickOwner.view.badge == null,
      'hiding Quick Terminal did not restore the manual indication to the '
      'ordinary terminal',
    );

    await dispatch(TerminalActionId.quitApplication);
    await closed.future;
    _expectLifecycle(
      secureKeyboardEntry.isDisposed &&
          quickTerminal.isDisposed &&
          state.isDisposed &&
          hierarchy.isDisposed &&
          allSessions.length == 2 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'Quit did not release owned secure input, native UI, and both sessions',
    );
    stdout.writeln(
      'TERMINAL_SECURE_KEYBOARD_ENTRY_TEST automatic=true echo=true '
      'ime=true menu=true palette=true keybind=true settings=true '
      'app_lifecycle=true quick_terminal=true checked=true indication=true '
      'cleanup=true sessions_clean=2 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _exerciseQuickTerminalProduct({
    required AppKitApplication application,
    required TerminalApplicationState state,
    required TerminalNativeHierarchyAdapter hierarchy,
    required TerminalActionDispatcher dispatcher,
    required TerminalAppKitMenuProjection menu,
    required TerminalSettingsInspectorPresenter settings,
    required TerminalQuickTerminalController controller,
    required Map<PaneId, TerminalSession> sessions,
    required List<TerminalSession> allSessions,
    required Map<PaneId, _TerminalHierarchyProductPane> owners,
    required List<TerminalActionId> nativeActionInvocations,
    required List<TerminalActionDispatchResult> actionDispatches,
    required Completer<void> closed,
    required String prompt,
  }) async {
    Future<void> waitFor(
      bool Function() predicate,
      String message, {
      Duration timeout = const Duration(seconds: 10),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (!predicate() && deadline.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _expectLifecycle(predicate(), message);
    }

    Future<void> dispatch(TerminalActionId id) async {
      final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
      _expectLifecycle(
        result.disposition == TerminalActionDispatchDisposition.executed,
        'Quick Terminal action ${id.stableName} did not execute',
      );
    }

    _expectLifecycle(
      state.windowCount == 1 &&
          state.tabCount == 1 &&
          state.paneCount == 1 &&
          hierarchy.nativeWindowCount == 1 &&
          controller.activeShortcut != null &&
          controller.registeredHotKey != null &&
          controller.shortcutStatus.disposition ==
              TerminalQuickTerminalShortcutDisposition.registered,
      'Quick Terminal product did not start disabled-in-window and '
      'configured-in-shortcut',
    );
    final TerminalWindowState ordinaryWindow = state.windows.single;
    final TerminalSession ordinarySession = sessions.values.single;
    await _waitForAsciiMarker(ordinarySession, prompt);

    final MenuItem toggleItem = menu.itemForAction(
      TerminalActionId.toggleQuickTerminal,
    );
    _expectLifecycle(
      toggleItem.isEnabled &&
          toggleItem.keyEquivalent.isEmpty &&
          toggleItem.modifiers.bits == 0,
      'Quick Terminal menu action was unavailable or duplicated a local key',
    );
    final int menuInvocationBaseline = nativeActionInvocations.length;
    final int menuDispatchBaseline = actionDispatches.length;
    toggleItem.performAction();
    await waitFor(
      () =>
          controller.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.visible &&
          state.quickTerminalWindow != null &&
          state.windowCount == 2 &&
          state.paneCount == 2 &&
          hierarchy.nativeWindowCount == 2 &&
          hierarchy.paneResourceCount == 2 &&
          nativeActionInvocations.length == menuInvocationBaseline + 1 &&
          actionDispatches.length == menuDispatchBaseline + 1,
      'menu toggle did not lazily present one Quick Terminal',
    );

    final TerminalWindowState quickWindow = state.quickTerminalWindow!;
    final TerminalTabState quickTab = quickWindow.selectedTab;
    final PaneId quickPaneId = quickTab.focusedPaneId;
    final TerminalSession quickSession = sessions[quickPaneId]!;
    final _TerminalHierarchyProductPane quickOwner = owners[quickPaneId]!;
    final Window quickNative = hierarchy.windowForTab(quickTab.id)!;
    final TerminalQuickTerminalFrames frames = controller.lastFrames!;
    await _waitForAsciiMarker(quickSession, prompt);
    final int expectedScale = (controller.lastBackingScaleFactor! * 65536)
        .round();
    _expectLifecycle(
      quickWindow.role == TerminalWindowRole.quickTerminal &&
          quickWindow.tabIds.length == 1 &&
          quickNative.configuration ==
              terminalQuickTerminalWindowConfiguration &&
          quickNative.presentationConfiguration ==
              TerminalQuickTerminalController.windowPresentation &&
          quickNative.frame == frames.target &&
          frames.hidden.width == frames.target.width &&
          frames.hidden.height == frames.target.height &&
          quickOwner.surface.snapshot().scale16_16 == expectedScale,
      'Quick Terminal style, fixed-size geometry, or first-frame scale '
      'projection diverged',
    );

    final TerminalPane retainedPane = state.paneForId(quickPaneId)!;
    await dispatch(TerminalActionId.toggleQuickTerminal);
    _expectLifecycle(
      controller.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.hidden &&
          identical(state.paneForId(quickPaneId), retainedPane) &&
          identical(sessions[quickPaneId], quickSession) &&
          state.activeWindowId == ordinaryWindow.id &&
          state.windowCount == 2 &&
          hierarchy.nativeWindowCount == 2,
      'hide did not retain the singleton session or restore normal ownership',
    );

    final GlobalHotKey hotKey = controller.registeredHotKey!;
    final int hotKeyHandle = appkit_testing.nativeGlobalHotKeyHandleForTesting(
      hotKey,
    );
    final int globalDispatchBaseline = actionDispatches.length;
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      41,
      hotKeyHandle,
      hotKeyHandle >> 32,
      18000000,
      0,
    ]);
    await waitFor(
      () =>
          controller.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.visible &&
          actionDispatches.length == globalDispatchBaseline + 1,
      'exclusive global hot key did not use the shared toggle action',
    );
    _expectLifecycle(
      identical(state.quickTerminalWindow, quickWindow) &&
          identical(state.paneForId(quickPaneId), retainedPane) &&
          identical(sessions[quickPaneId], quickSession),
      'global toggle replaced the retained Quick Terminal generation',
    );

    _injectFocusEventForTesting(
      application,
      quickNative,
      isFocused: true,
      monotonicNanoseconds: 18000500,
    );
    _injectFocusEventForTesting(
      application,
      quickNative,
      isFocused: false,
      monotonicNanoseconds: 18001000,
    );
    await waitFor(
      () =>
          controller.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.hidden &&
          state.activeWindowId == ordinaryWindow.id,
      'configured focus-loss autohide did not hide Quick Terminal',
    );

    const TerminalKeyBindingChord conflictingChord = TerminalKeyBindingChord(
      physicalKey: TerminalPhysicalKey.f17,
      control: true,
      option: true,
      command: true,
    );
    final TerminalQuickTerminalHotKeyBinding conflictingBinding =
        TerminalQuickTerminalHotKeyBinding.fromChord(conflictingChord);
    final GlobalHotKey blocker = GlobalHotKey(
      keyCode: conflictingBinding.keyCode,
      modifiers: conflictingBinding.modifiers,
    );
    try {
      await controller.replaceShortcut(conflictingChord);
      _expectLifecycle(
        controller.shortcutStatus.disposition ==
                TerminalQuickTerminalShortcutDisposition.failed &&
            controller.shortcutStatus.failure ==
                TerminalQuickTerminalShortcutFailure.conflict &&
            identical(controller.registeredHotKey, hotKey) &&
            !hotKey.isDisposed,
        'failed live replacement did not retain the active registration',
      );
      await settings.open();
      _expectLifecycle(
        (settings.renderedText ?? '').contains(
          'Quick Terminal shortcut: conflict',
        ),
        'Settings did not surface shortcut replacement failure',
      );
      await settings.dismiss();
    } finally {
      blocker.dispose();
    }
    await controller.replaceShortcut(controller.activeShortcut);

    await dispatch(TerminalActionId.toggleQuickTerminal);
    await dispatch(TerminalActionId.closeWindow);
    _expectLifecycle(
      controller.lifecycle.visibility ==
              TerminalQuickTerminalVisibility.hidden &&
          state.windowCount == 2 &&
          state.paneCount == 2,
      'Close on Quick Terminal did not hide and retain its pane',
    );

    await dispatch(TerminalActionId.quitApplication);
    await closed.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    _expectLifecycle(
      state.isDisposed &&
          hierarchy.isDisposed &&
          controller.isDisposed &&
          allSessions.length == 2 &&
          allSessions.every(
            (TerminalSession session) =>
                session.shutdownResult?.isClean == true,
          ) &&
          debugLiveTerminalTextInputClientCount() == 0 &&
          application.debugLiveObjectCount == 0,
      'Quick Terminal quit did not release global/native/session owners',
    );
    stdout.writeln(
      'TERMINAL_QUICK_TERMINAL_TEST singleton=true shortcut=true '
      'menu=true global_action=true screen=true fixed_geometry=true '
      'retina_scale=true retained_session=true autohide=true '
      'conflict_visible=true close_hides=true normal_independent=true '
      'sessions_clean=2 text_clients=0 native_handles=0',
    );
  }

  static Future<void> _runRestorationProductAcceptance(
    AppKitApplication application,
    PtyBackend ptyBackend,
    TerminalTerminfoEnvironment terminfoEnvironment,
    RuntimeLifecycleWorkerCommand workerCommand,
    String? initialWorkingDirectory,
    String persistencePath,
  ) async {
    const String prompt = '__DT_RESTORATION_PROMPT__ ';
    const Rect windowFrame = Rect.fromLTWH(100, 90, 920, 580);
    final Map<PaneId, TerminalSession> sessions = <PaneId, TerminalSession>{};
    final Map<PaneId, _TerminalHierarchyProductPane> owners =
        <PaneId, _TerminalHierarchyProductPane>{};
    final Map<PaneId, String?> launchWorkingDirectories = <PaneId, String?>{};
    final List<TerminalPaneSessionShutdownResult> shutdowns =
        <TerminalPaneSessionShutdownResult>[];
    final List<TerminalRestorationDiagnostic> restorationDiagnostics =
        <TerminalRestorationDiagnostic>[];
    final TerminalTabPresentationResolver presentationResolver =
        TerminalTabPresentationResolver(
          metadataForPane: (PaneId paneId) =>
              sessions[paneId]?.terminalScreenSet.metadata,
        );
    TerminalRestorationLifecycle? restoration;
    RuntimeLifecycleCoordinator? lifecycle;
    StreamSubscription<ApplicationReopenRequestedEvent>? reopenSubscription;
    TerminalSystemRecoveryController? systemRecoveryController;
    TerminalMemoryPressureController? memoryPressureController;
    StreamSubscription<AppKitEvent>? systemRecoverySubscription;
    var lifecycleWasShutDown = false;
    Object? asynchronousError;
    StackTrace? asynchronousStackTrace;
    Completer<TerminalRestorationReopenDisposition>? reopenCompletion;
    var reopenEventCount = 0;

    void recordAsynchronousError(Object error, StackTrace stackTrace) {
      asynchronousError ??= error;
      asynchronousStackTrace ??= stackTrace;
      final Completer<TerminalRestorationReopenDisposition>? completion =
          reopenCompletion;
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
    }

    void checkAsynchronousError() {
      final Object? error = asynchronousError;
      if (error != null) {
        Error.throwWithStackTrace(error, asynchronousStackTrace!);
      }
    }

    TerminalPaneConfiguration configurationForPane(
      TerminalRestorablePane saved,
    ) {
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
                initialWorkingDirectory: saved.workingDirectory,
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
                graphicsWorker: lifecycle,
              );
              sessions[id.paneId] = session;
              launchWorkingDirectories[id.paneId] = saved.workingDirectory;
              return session;
            },
        onChanged: () {
          final PaneId? id = paneId;
          if (id != null) owners[id]?.notifyScreenChanged();
        },
        onExitRequested: () {
          recordAsynchronousError(
            StateError('restoration acceptance shell exited unexpectedly'),
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

    TerminalNativePaneResources createResources(TerminalPane pane) {
      final TerminalSession session = sessions[pane.id]!;
      final View view = TerminalRendererMacos.createView();
      final TerminalTextInputClient client = TerminalTextInputClient.attach(
        view,
      );
      late final _TerminalHierarchyProductPane owner;
      final TerminalLiveMetalSurface surface = TerminalLiveMetalSurface.attach(
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
              keyRouter.handleTerminalKeyEvent(event, pane);
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
                  'restoration text input overflow for client $clientId '
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
        onBackingScale: owner.updateBackingScale,
        onDisposeAdapters: owner.disposeAdapters,
      );
    }

    try {
      application.defersTerminationRequests = true;
      _expectLifecycle(
        application.debugLiveObjectCount == 0 &&
            debugLiveTerminalTextInputClientCount() == 0,
        'restoration acceptance requires clean native baselines',
      );

      final TerminalRestorationLifecycle createdRestoration =
          TerminalRestorationLifecycle(
            persistence: TerminalRestorationPersistence(
              FileTerminalRestorationStore(persistencePath),
            ),
            configurationForPane: configurationForPane,
            hierarchyFactory:
                ({
                  required TerminalApplicationState state,
                  required Map<TerminalWindowId, TerminalWindowPlacement>
                  placements,
                }) => TerminalNativeHierarchyAdapter(
                  state: state,
                  paneResourcesFactory: createResources,
                  windowFrame: windowFrame,
                  cellSize: TerminalSplitLayoutSize(width: 8, height: 16),
                  windowPlacements: placements,
                  dividerThickness: 1,
                  presentWindows: false,
                  presentationBuilder:
                      (TerminalWindowState window, TerminalTabState tab) =>
                          presentationResolver.resolve(
                            tab,
                            fallbackTitle:
                                'Dart Terminal — ${window.id}:${tab.id}',
                          ),
                ),
            defaultPlacement: TerminalWindowPlacement(
              windowedFrame: TerminalWindowFrame(
                left: windowFrame.left,
                top: windowFrame.top,
                width: windowFrame.width,
                height: windowFrame.height,
              ),
              screen: null,
              fullscreen: false,
            ),
            defaultWorkingDirectory: initialWorkingDirectory,
            workingDirectoryForPane: (PaneId paneId) =>
                presentationResolver.inheritedWorkingDirectoryForPane(paneId) ??
                launchWorkingDirectories[paneId],
            onDiagnostic: (TerminalRestorationDiagnostic diagnostic) {
              restorationDiagnostics.add(diagnostic);
              stdout.writeln(diagnostic.machineLine());
            },
            onEventError: recordAsynchronousError,
          );
      restoration = createdRestoration;
      _expectLifecycle(
        await createdRestoration.start() ==
            TerminalRestorationStartDisposition.defaultCreated,
        'missing isolated persistence did not create a default generation',
      );

      systemRecoveryController = TerminalSystemRecoveryController(
        suspendPresentation: () {
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            if (!owner.surface.isDisposed) {
              owner.surface.updateSystemSuspended(true);
            }
          }
        },
        recoverDisplays: () {
          final TerminalRestorationGeneration? current =
              createdRestoration.current;
          if (current == null || current.hierarchy.isDisposed) return true;
          current.hierarchy.recoverDisplaySet(
            fallbackScreen: application.resolveScreen(
              AppKitScreenSelection.main,
            ),
          );
          for (final PaneId paneId in current.state.paneIds) {
            owners[paneId]?.notifyScreenChanged();
          }
          return true;
        },
        resumePresentation: () {
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            if (!owner.surface.isDisposed) {
              owner.surface.updateSystemSuspended(false);
            }
          }
        },
        onError: recordAsynchronousError,
      );
      memoryPressureController = TerminalMemoryPressureController(
        apply: (AppKitMemoryPressureLevel level) {
          for (final _TerminalHierarchyProductPane owner
              in owners.values.toList(growable: false)) {
            if (!owner.surface.isDisposed) {
              owner.surface.shedMemoryPressure(level);
            }
          }
        },
        onError: recordAsynchronousError,
      );
      systemRecoverySubscription = application.events.listen((
        AppKitEvent event,
      ) {
        if (event is ApplicationPowerStateChangedEvent ||
            event is ApplicationScreenSetChangedEvent) {
          systemRecoveryController?.handle(event);
        } else if (event is ApplicationMemoryPressureChangedEvent) {
          memoryPressureController?.handle(event);
        }
      }, onError: recordAsynchronousError);

      reopenSubscription = application.onReopenRequested.listen((
        ApplicationReopenRequestedEvent event,
      ) {
        reopenEventCount++;
        unawaited(
          createdRestoration.handleReopenRequest(event).then((
            TerminalRestorationReopenDisposition disposition,
          ) {
            final Completer<TerminalRestorationReopenDisposition>? completion =
                reopenCompletion;
            if (completion != null && !completion.isCompleted) {
              completion.complete(disposition);
            }
          }, onError: recordAsynchronousError),
        );
      }, onError: recordAsynchronousError);

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
        'restoration acceptance runtime worker did not become ready',
      );
      for (final TerminalSession session in sessions.values) {
        session.attachGraphicsWorker(createdLifecycle);
      }
      _writeLifecycleEvent(
        RuntimeLifecycleScenario.normal,
        'root-ready',
        createdLifecycle.generation,
      );
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);
      await _expectResponse(createdLifecycle);

      final TerminalRestorationGeneration initial = createdRestoration.current!;
      final TerminalApplicationState initialState = initial.state;
      final TerminalWindowState initialWindow = initialState.windows.single;
      final TerminalTabState firstTab = initialWindow.selectedTab;
      final PaneId firstPaneId = firstTab.focusedPaneId;
      await _waitForAsciiMarker(sessions[firstPaneId]!, prompt.trimRight());
      initialState
          .paneForId(firstPaneId)!
          .insertText(
            "cd /private/tmp; printf "
            "'\\033]2;__DT_RESTORATION_TITLE__\\007"
            "\\033]7;file://localhost/private/tmp\\007'",
          );
      await initialState.paneForId(firstPaneId)!.submit();
      await _waitForSessionMetadata(
        sessions[firstPaneId]!,
        expectedTitle: '__DT_RESTORATION_TITLE__',
        expectedWorkingDirectory: Uri.parse('file://localhost/private/tmp'),
      );
      final String? inheritedWorkingDirectory = presentationResolver
          .inheritedWorkingDirectoryForPane(firstPaneId);
      _expectLifecycle(
        inheritedWorkingDirectory == '/private/tmp',
        'restoration acceptance did not resolve its inherited cwd',
      );

      final Window selectedWindow = initial.hierarchy.windowForTab(
        firstTab.id,
      )!;
      final Stopwatch presentationDeadline = Stopwatch()..start();
      while ((!selectedWindow.isVisible || selectedWindow.screen == null) &&
          presentationDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _expectLifecycle(
        selectedWindow.isVisible && selectedWindow.screen != null,
        'native tab group did not become visible on a concrete screen',
      );
      final Stopwatch activationDeadline = Stopwatch()..start();
      while (!application.isActive &&
          activationDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final Rect safeWindowedFrame = selectedWindow.frame;
      final Future<WindowFullscreenChangedEvent> entered = selectedWindow
          .onFullscreenChanged
          .firstWhere(
            (WindowFullscreenChangedEvent event) => event.isFullscreen,
          )
          .timeout(const Duration(seconds: 8));
      stdout.writeln(
        'TERMINAL_RESTORATION_FULLSCREEN stage=enter-requested '
        'active=${application.isActive} visible=${selectedWindow.isVisible}',
      );
      initial.hierarchy.requestFullscreen(initialWindow.id, true);
      await entered;
      stdout.writeln('TERMINAL_RESTORATION_FULLSCREEN stage=enter-observed');
      _expectLifecycle(
        selectedWindow.isFullscreen &&
            initial.hierarchy.placementForWindow(initialWindow.id).fullscreen &&
            initial.hierarchy
                    .placementForWindow(initialWindow.id)
                    .windowedFrame ==
                TerminalWindowFrame(
                  left: safeWindowedFrame.left,
                  top: safeWindowedFrame.top,
                  width: safeWindowedFrame.width,
                  height: safeWindowedFrame.height,
                ),
        'native fullscreen entry did not preserve the safe windowed frame',
      );
      final Future<WindowFullscreenChangedEvent> exited = selectedWindow
          .onFullscreenChanged
          .firstWhere(
            (WindowFullscreenChangedEvent event) => !event.isFullscreen,
          )
          .timeout(const Duration(seconds: 8));
      stdout.writeln('TERMINAL_RESTORATION_FULLSCREEN stage=exit-requested');
      initial.hierarchy.requestFullscreen(initialWindow.id, false);
      await exited;
      stdout.writeln('TERMINAL_RESTORATION_FULLSCREEN stage=exit-observed');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final TerminalWindowPlacement exitedPlacement = initial.hierarchy
          .placementForWindow(initialWindow.id);
      final Rect exitedFrame = _appKitWindowFrame(
        exitedPlacement.windowedFrame,
      );
      final bool exitedSizePreserved =
          exitedPlacement.windowedFrame.width == safeWindowedFrame.width &&
          exitedPlacement.windowedFrame.height == safeWindowedFrame.height;
      final bool exitedTabsConverged = initialWindow.tabIds.every(
        (TerminalTabId tabId) =>
            initial.hierarchy.windowForTab(tabId)!.frame == exitedFrame,
      );
      stdout.writeln(
        'TERMINAL_RESTORATION_FULLSCREEN_EXIT observed=true '
        'fullscreen=${selectedWindow.isFullscreen} '
        'placement_fullscreen=${exitedPlacement.fullscreen} '
        'size_preserved=$exitedSizePreserved '
        'tabs_converged=$exitedTabsConverged '
        'selected_matches=${selectedWindow.frame == exitedFrame} '
        'safe_width=${safeWindowedFrame.width} '
        'safe_height=${safeWindowedFrame.height} '
        'exited_width=${exitedPlacement.windowedFrame.width} '
        'exited_height=${exitedPlacement.windowedFrame.height}',
      );
      _expectLifecycle(
        !selectedWindow.isFullscreen &&
            !exitedPlacement.fullscreen &&
            exitedSizePreserved &&
            exitedTabsConverged,
        'native fullscreen exit did not restore the safe frame',
      );

      final Stopwatch screenDeadline = Stopwatch()..start();
      while ((selectedWindow.screen == null ||
              selectedWindow.backingScaleFactor == null) &&
          screenDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final AppKitScreen sourceScreen = selectedWindow.screen!;
      final double destinationWidth = sourceScreen.visibleFrame.width > 700
          ? 700
          : sourceScreen.visibleFrame.width;
      final double destinationHeight = sourceScreen.visibleFrame.height > 500
          ? 500
          : sourceScreen.visibleFrame.height;
      final AppKitScreen destinationScreen = AppKitScreen(
        displayId: sourceScreen.displayId + 1000000,
        frame: sourceScreen.frame,
        visibleFrame: Rect.fromLTWH(
          sourceScreen.visibleFrame.left,
          sourceScreen.visibleFrame.top,
          destinationWidth,
          destinationHeight,
        ),
      );
      final TerminalWindowPlacement expectedMigration =
          TerminalWindowPlacementPolicy.resolveForAvailableScreens(
            initial.hierarchy.placementForWindow(initialWindow.id),
            <TerminalScreenPlacement>[
              _terminalScreenPlacement(destinationScreen),
            ],
            fallbackDisplayId: destinationScreen.displayId,
          );
      final Future<WindowScreenChangedEvent> migrationObserved = selectedWindow
          .onScreenChanged
          .firstWhere(
            (WindowScreenChangedEvent event) =>
                event.screen?.displayId == destinationScreen.displayId,
          )
          .timeout(const Duration(seconds: 3));
      _injectScreenEventForTesting(
        application,
        selectedWindow,
        destinationScreen,
        monotonicNanoseconds: 900000000,
      );
      await migrationObserved;
      final Rect expectedFrame = _appKitWindowFrame(
        expectedMigration.windowedFrame,
      );
      final bool migrationPlacementMatched =
          initial.hierarchy.placementForWindow(initialWindow.id) ==
          expectedMigration;
      final bool migrationTabsConverged = initialWindow.tabIds.every(
        (TerminalTabId tabId) =>
            initial.hierarchy.windowForTab(tabId)!.frame == expectedFrame,
      );
      final bool scaleObserved =
          selectedWindow.backingScaleFactor != null &&
          selectedWindow.backingScaleFactor! > 0;
      stdout.writeln(
        'TERMINAL_RESTORATION_SCREEN_MIGRATION observed=true '
        'placement=$migrationPlacementMatched '
        'tabs_converged=$migrationTabsConverged scale=$scaleObserved',
      );
      _expectLifecycle(
        migrationPlacementMatched && migrationTabsConverged && scaleObserved,
        'screen migration did not clamp the tab group with live scale state',
      );

      final PaneId recoveryPaneId = initialWindow.selectedTab.focusedPaneId;
      final TerminalPane recoveryPane = initialState.paneForId(recoveryPaneId)!;
      final TerminalSession recoverySession = sessions[recoveryPaneId]!;
      final _TerminalHierarchyProductPane recoveryOwner =
          owners[recoveryPaneId]!;
      final TerminalLiveMetalSurface recoverySurface = recoveryOwner.surface;
      final int recoveryAcceptedBaseline = recoverySurface
          .snapshot()
          .acceptedFrameCount;
      final TerminalSystemRecoverySnapshot recoveryControllerBaseline =
          systemRecoveryController.snapshot();
      _injectApplicationPowerStateEventForTesting(
        application,
        state: AppKitApplicationPowerState.willSleep,
        monotonicNanoseconds: 8000000000000100000,
      );
      _injectApplicationPowerStateEventForTesting(
        application,
        state: AppKitApplicationPowerState.willSleep,
        monotonicNanoseconds: 8000000000000200000,
      );
      final Stopwatch suspendDeadline = Stopwatch()..start();
      while ((!systemRecoveryController.snapshot().isPresentationSuspended ||
              !recoverySurface.snapshot().isSystemSuspended) &&
          suspendDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final int acceptedAtSuspend = recoverySurface
          .snapshot()
          .acceptedFrameCount;
      recoveryPane.insertText("printf '\r\n__DT_SYSTEM_RECOVERY_NEWEST__\r\n'");
      await recoveryPane.submit();
      await _waitForAsciiMarker(
        recoverySession,
        '__DT_SYSTEM_RECOVERY_NEWEST__',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _expectLifecycle(
        systemRecoveryController.snapshot().isPresentationSuspended &&
            recoverySurface.snapshot().isSystemSuspended &&
            !recoverySurface.snapshot().hasScheduledWork &&
            recoverySurface.snapshot().acceptedFrameCount == acceptedAtSuspend,
        'sleep accepted a frame or retained presentation work',
      );

      _injectApplicationScreenSetEventForTesting(
        application,
        monotonicNanoseconds: 8000000000000300000,
      );
      _injectApplicationScreenSetEventForTesting(
        application,
        monotonicNanoseconds: 8000000000000400000,
      );
      _injectApplicationPowerStateEventForTesting(
        application,
        state: AppKitApplicationPowerState.didWake,
        monotonicNanoseconds: 8000000000000500000,
      );
      final Stopwatch recoveryDeadline = Stopwatch()..start();
      while ((systemRecoveryController.snapshot().isPresentationSuspended ||
              recoverySurface.snapshot().isSystemSuspended ||
              recoverySurface.snapshot().acceptedFrameCount <=
                  acceptedAtSuspend) &&
          recoveryDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      checkAsynchronousError();
      final TerminalSystemRecoverySnapshot recoverySnapshot =
          systemRecoveryController.snapshot();
      final TerminalLiveMetalSurfaceSnapshot recoveredSurface = recoverySurface
          .snapshot();
      final int acceptedEventDelta =
          recoverySnapshot.acceptedEventCount -
          recoveryControllerBaseline.acceptedEventCount;
      final int coalescedEventDelta =
          recoverySnapshot.coalescedEventCount -
          recoveryControllerBaseline.coalescedEventCount;
      final int suspendDelta =
          recoverySnapshot.suspendCount -
          recoveryControllerBaseline.suspendCount;
      final int displayRecoveryDelta =
          recoverySnapshot.displayRecoveryCount -
          recoveryControllerBaseline.displayRecoveryCount;
      final int resumeDelta =
          recoverySnapshot.resumeCount - recoveryControllerBaseline.resumeCount;
      final bool recoveryTabsConverged = initialWindow.tabIds.every(
        (TerminalTabId tabId) =>
            initial.hierarchy.windowForTab(tabId)!.frame ==
            _appKitWindowFrame(
              initial.hierarchy
                  .placementForWindow(initialWindow.id)
                  .windowedFrame,
            ),
      );
      stdout.writeln(
        'TERMINAL_SYSTEM_RECOVERY_OBSERVED '
        'accepted_events=$acceptedEventDelta '
        'coalesced_events=$coalescedEventDelta '
        'suspends=$suspendDelta '
        'display_recoveries=$displayRecoveryDelta '
        'resumes=$resumeDelta '
        'baseline_frames=$recoveryAcceptedBaseline '
        'suspend_frames=$acceptedAtSuspend '
        'recovered_frames=${recoveredSurface.acceptedFrameCount} '
        'applied_revision=${recoveredSurface.lastAppliedDamageGeneration} '
        'accepted_revision=${recoveredSurface.lastAcceptedModelRevision} '
        'tabs_converged=$recoveryTabsConverged',
      );
      _expectLifecycle(
        recoveryAcceptedBaseline > 0 &&
            !recoverySnapshot.isSleeping &&
            !recoverySnapshot.isPresentationSuspended &&
            acceptedEventDelta == 3 &&
            coalescedEventDelta >= 1 &&
            suspendDelta == 1 &&
            displayRecoveryDelta == 1 &&
            resumeDelta == 1 &&
            !recoveredSurface.isSystemSuspended &&
            recoveredSurface.acceptedFrameCount > acceptedAtSuspend &&
            recoveredSurface.lastAcceptedModelRevision ==
                recoveredSurface.lastAppliedDamageGeneration &&
            identical(initialState.paneForId(recoveryPaneId), recoveryPane) &&
            identical(sessions[recoveryPaneId], recoverySession) &&
            identical(owners[recoveryPaneId]!.surface, recoverySurface) &&
            recoveryTabsConverged,
        'wake did not redraw newest state with retained owner/tab placement',
      );
      stdout.writeln(
        'TERMINAL_SYSTEM_RECOVERY_TEST later_turn=true sleep=true wake=true '
        'screen_set=true coalesced=true stale_frames=0 owner_retained=true '
        'newest_redrawn=true scheduled_while_sleeping=false',
      );

      final int pressureImageId = 0x7fff0001;
      final TerminalLogicalAnchor pressureImageAnchor = recoverySession
          .terminalScreenSet
          .viewport
          .anchorAtScreenCell(TerminalScreenKind.primary, 0, 0);
      final pressureImage = recoverySession.terminalScreenSet.primaryKittyImages
          .store(
            imageId: pressureImageId,
            imageNumber: 0,
            width: 2,
            height: 2,
            transient: false,
            rgba: Uint8List.fromList(const <int>[
              255,
              0,
              0,
              255,
              0,
              255,
              0,
              255,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              255,
            ]),
          );
      final pressurePlacement = recoverySession
          .terminalScreenSet
          .primaryKittyImages
          .place(
            imageId: pressureImageId,
            imageNumber: 0,
            placementId: pressureImageId,
            logicalLineId: pressureImageAnchor.logicalLineId,
            logicalLineEpoch: pressureImageAnchor.logicalLineEpoch,
            logicalCellOffset: pressureImageAnchor.cellOffset,
            sourceX: 0,
            sourceY: 0,
            sourceWidth: 0,
            sourceHeight: 0,
            cellOffsetX: 0,
            cellOffsetY: 0,
            columns: 1,
            rows: 1,
            z: 1,
          );
      _expectLifecycle(
        pressureImage.image != null && pressurePlacement.placement != null,
        'memory-pressure fixture did not create canonical Kitty semantics',
      );
      final int pressureImageResourceGeneration =
          pressureImage.image!.resourceGeneration;
      final int pressureStoreBytes =
          recoverySession.terminalScreenSet.primaryKittyImages.retainedBytes;
      final int pressureScreenDigest = _screenCanonicalDigest(
        recoverySession.terminalScreenSet.primary,
      );
      final int pressurePreeditGeneration =
          recoverySurface.preeditState.generation + 1;
      recoverySurface.updatePreedit(
        generation: pressurePreeditGeneration,
        text: 'memory-pressure-preedit',
        selectionLocation: 6,
        selectionLength: 8,
      );
      recoveryOwner.notifyScreenChanged();
      final int pressureWarmFrameBaseline = recoverySurface
          .snapshot()
          .acceptedFrameCount;
      final Stopwatch pressureWarmDeadline = Stopwatch()..start();
      while ((recoverySurface.snapshot().acceptedFrameCount <=
                  pressureWarmFrameBaseline ||
              recoverySurface.snapshot().kittyAtlasEntryCount == 0 ||
              recoverySurface.snapshot().shapingCacheEntryCount == 0) &&
          pressureWarmDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      checkAsynchronousError();
      final TerminalLiveMetalSurfaceSnapshot pressureWarm = recoverySurface
          .snapshot();
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.normal,
        monotonicNanoseconds: 8100000000000000000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final TerminalMemoryPressureSnapshot pressureControllerBaseline =
          memoryPressureController.snapshot();
      _expectLifecycle(
        pressureWarm.kittyAtlasEntryCount > 0 &&
            pressureWarm.shapingCacheEntryCount > 0 &&
            pressureWarm.atlasEntryCount <=
                recoverySurface.atlas.limits.maximumEntries &&
            pressureWarm.atlasRetainedBytes <=
                recoverySurface.atlas.limits.maximumRetainedBytes,
        'memory-pressure fixture did not warm bounded reproducible caches',
      );

      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.warning,
        monotonicNanoseconds: 8100000000000100000,
      );
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.warning,
        monotonicNanoseconds: 8100000000000200000,
      );
      final Stopwatch warningDeadline = Stopwatch()..start();
      while ((recoverySurface.snapshot().memoryPressureWarningCount <=
                  pressureWarm.memoryPressureWarningCount ||
              recoverySurface.snapshot().pendingMemoryPressureLevel != null ||
              recoverySurface.snapshot().acceptedFrameCount <=
                  pressureWarm.acceptedFrameCount ||
              recoverySurface.snapshot().atlasEntryCount == 0 ||
              memoryPressureController.snapshot().applicationCount ==
                  pressureControllerBaseline.applicationCount) &&
          warningDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      checkAsynchronousError();
      final TerminalLiveMetalSurfaceSnapshot afterWarning = recoverySurface
          .snapshot();

      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.critical,
        monotonicNanoseconds: 8100000000000300000,
      );
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.critical,
        monotonicNanoseconds: 8100000000000400000,
      );
      final Stopwatch criticalDeadline = Stopwatch()..start();
      while ((recoverySurface.snapshot().memoryPressureCriticalCount <=
                  pressureWarm.memoryPressureCriticalCount ||
              recoverySurface.snapshot().pendingMemoryPressureLevel != null ||
              recoverySurface.snapshot().acceptedFrameCount <=
                  afterWarning.acceptedFrameCount ||
              recoverySurface.snapshot().atlasEntryCount == 0 ||
              memoryPressureController.snapshot().applicationCount <
                  pressureControllerBaseline.applicationCount + 2) &&
          criticalDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      _injectApplicationMemoryPressureEventForTesting(
        application,
        level: AppKitMemoryPressureLevel.normal,
        monotonicNanoseconds: 8100000000000500000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      checkAsynchronousError();
      final TerminalMemoryPressureSnapshot pressureControllerSnapshot =
          memoryPressureController.snapshot();
      final TerminalLiveMetalSurfaceSnapshot afterCritical = recoverySurface
          .snapshot();
      final int pressureAcceptedDelta =
          pressureControllerSnapshot.acceptedEventCount -
          pressureControllerBaseline.acceptedEventCount;
      final int pressureCoalescedDelta =
          pressureControllerSnapshot.coalescedEventCount -
          pressureControllerBaseline.coalescedEventCount;
      final bool pressureKittyRetained =
          recoverySession.terminalScreenSet.primaryKittyImages
                  .imageById(pressureImageId)
                  ?.resourceGeneration ==
              pressureImageResourceGeneration &&
          recoverySession.terminalScreenSet.primaryKittyImages.retainedBytes ==
              pressureStoreBytes &&
          recoverySession.terminalScreenSet.primaryKittyImages.placementCount ==
              1;
      final bool pressurePreeditRetained =
          recoverySurface.preeditState.generation ==
              pressurePreeditGeneration &&
          recoverySurface.preeditState.text == 'memory-pressure-preedit' &&
          recoverySurface.preeditState.selectionLocation == 6 &&
          recoverySurface.preeditState.selectionLength == 8;
      stdout.writeln(
        'TERMINAL_MEMORY_PRESSURE_OBSERVED '
        'accepted_events=$pressureAcceptedDelta '
        'coalesced_events=$pressureCoalescedDelta '
        'applications=${pressureControllerSnapshot.applicationCount - pressureControllerBaseline.applicationCount} '
        'recoveries=${pressureControllerSnapshot.recoveryCount - pressureControllerBaseline.recoveryCount} '
        'warnings=${afterCritical.memoryPressureWarningCount - pressureWarm.memoryPressureWarningCount} '
        'criticals=${afterCritical.memoryPressureCriticalCount - pressureWarm.memoryPressureCriticalCount} '
        'deferrals=${afterCritical.memoryPressureDeferredCount - pressureWarm.memoryPressureDeferredCount} '
        'shaping_entries=${afterCritical.memoryPressureShapingEntryCount - pressureWarm.memoryPressureShapingEntryCount} '
        'atlas_entries=${afterCritical.memoryPressureAtlasEntryCount - pressureWarm.memoryPressureAtlasEntryCount} '
        'atlas_bytes=${afterCritical.memoryPressureAtlasReleasedBytes - pressureWarm.memoryPressureAtlasReleasedBytes} '
        'kitty_retained=$pressureKittyRetained '
        'preedit_retained=$pressurePreeditRetained',
      );
      _expectLifecycle(
        pressureAcceptedDelta == 3 &&
            pressureCoalescedDelta >= 2 &&
            pressureControllerSnapshot.applicationCount ==
                pressureControllerBaseline.applicationCount + 2 &&
            pressureControllerSnapshot.recoveryCount ==
                pressureControllerBaseline.recoveryCount + 1 &&
            pressureControllerSnapshot.observedLevel ==
                AppKitMemoryPressureLevel.normal &&
            pressureControllerSnapshot.pendingLevel == null &&
            afterCritical.pendingMemoryPressureLevel == null &&
            afterCritical.memoryPressureWarningCount ==
                pressureWarm.memoryPressureWarningCount + 1 &&
            afterCritical.memoryPressureCriticalCount ==
                pressureWarm.memoryPressureCriticalCount + 1 &&
            afterCritical.memoryPressureShapingEntryCount >
                pressureWarm.memoryPressureShapingEntryCount &&
            afterCritical.memoryPressureAtlasEntryCount >
                pressureWarm.memoryPressureAtlasEntryCount &&
            afterCritical.memoryPressureAtlasReleasedBytes >
                pressureWarm.memoryPressureAtlasReleasedBytes &&
            afterCritical.atlasEntryCount <=
                recoverySurface.atlas.limits.maximumEntries &&
            afterCritical.atlasRetainedBytes <=
                recoverySurface.atlas.limits.maximumRetainedBytes &&
            pressureKittyRetained &&
            pressurePreeditRetained &&
            _screenCanonicalDigest(recoverySession.terminalScreenSet.primary) ==
                pressureScreenDigest &&
            identical(initialState.paneForId(recoveryPaneId), recoveryPane) &&
            identical(sessions[recoveryPaneId], recoverySession) &&
            identical(owners[recoveryPaneId]!.surface, recoverySurface),
        'memory pressure changed canonical data or failed lazy cache recovery',
      );
      stdout.writeln(
        'TERMINAL_MEMORY_PRESSURE_TEST later_turn=true warning=true '
        'critical=true storm_coalesced=true pinned_safe=true '
        'canonical_retained=true lazy_rebuild=true capped=true',
      );
      recoverySurface.clearPreedit(generation: pressurePreeditGeneration + 1);

      final TerminalPane secondPane = await initialState.splitPane(
        firstPaneId,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.35,
      );
      final TerminalTabState secondTab = await initialState.createTab(
        initialWindow.id,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
      );
      final PaneId thirdPaneId = secondTab.focusedPaneId;
      final TerminalPane fourthPane = await initialState.splitPane(
        thirdPaneId,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
        axis: TerminalSplitAxis.vertical,
        fraction: 0.65,
      );
      final TerminalWindowState auxiliaryWindow = await initialState
          .createWindow(
            configurationForPane(
              TerminalRestorablePane(
                workingDirectory: inheritedWorkingDirectory,
              ),
            ),
          );
      final TerminalTabState auxiliaryFirstTab = auxiliaryWindow.selectedTab;
      final PaneId fifthPaneId = auxiliaryFirstTab.focusedPaneId;
      final TerminalPane sixthPane = await initialState.splitPane(
        fifthPaneId,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.45,
      );
      final TerminalTabState auxiliarySecondTab = await initialState.createTab(
        auxiliaryWindow.id,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
      );
      final PaneId seventhPaneId = auxiliarySecondTab.focusedPaneId;
      final TerminalPane eighthPane = await initialState.splitPane(
        seventhPaneId,
        configurationForPane(
          TerminalRestorablePane(workingDirectory: inheritedWorkingDirectory),
        ),
        axis: TerminalSplitAxis.vertical,
        fraction: 0.55,
      );
      initialState
        ..focusPane(firstTab.id, secondPane.id)
        ..renameTab(secondTab.id, 'Restored product tab')
        ..setTabColor(secondTab.id, TerminalTabColor.greenMarker)
        ..focusPane(secondTab.id, fourthPane.id)
        ..setPaneZoom(secondTab.id, fourthPane.id)
        ..selectTab(initialWindow.id, secondTab.id)
        ..focusPane(auxiliaryFirstTab.id, sixthPane.id)
        ..focusPane(auxiliarySecondTab.id, eighthPane.id)
        ..renameTab(auxiliarySecondTab.id, 'Restored auxiliary tab')
        ..setTabColor(auxiliarySecondTab.id, TerminalTabColor.purpleMarker)
        ..selectTab(auxiliaryWindow.id, auxiliarySecondTab.id)
        ..activateWindow(initialWindow.id);
      createdRestoration.reconcile();
      initial.hierarchy.present(restoreSelectionAndFocus: false);
      final List<PaneId> initialPaneIds = initialState.paneIds;
      for (final PaneId paneId in initialPaneIds) {
        final TerminalPane pane = initialState.paneForId(paneId)!;
        if (pane.state == TerminalPaneState.created) await pane.start();
        await _waitForAsciiMarker(sessions[paneId]!, prompt.trimRight());
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _expectLifecycle(
        initialState.windowCount == 2 &&
            initialState.tabCount == 4 &&
            initialState.paneCount == 8 &&
            initialState.windows.every(
              (TerminalWindowState window) =>
                  window.tabs.length == 2 &&
                  window.tabs.fold<int>(
                        0,
                        (int total, TerminalTabState tab) =>
                            total + tab.paneIds.length,
                      ) ==
                      4,
            ) &&
            initial.hierarchy.nativeWindowCount == 4 &&
            initial.hierarchy.splitViewCount == 4 &&
            initial.hierarchy.paneResourceCount == 8 &&
            application.debugLiveObjectCount == 16 &&
            debugLiveTerminalTextInputClientCount() == 8,
        'first restoration generation did not create its exact resources',
      );

      final Set<int> oldPaneIds = initialPaneIds
          .map((PaneId paneId) => paneId.value)
          .toSet();
      final Set<int> oldWindowIds = initialState.windowIds
          .map((TerminalWindowId windowId) => windowId.value)
          .toSet();
      final TerminalRestorationSaveResult saved = await createdRestoration
          .persistCurrent();
      _expectLifecycle(
        saved.disposition == TerminalRestorationSaveDisposition.saved &&
            await File(persistencePath).exists(),
        'first generation was not durably persisted',
      );
      for (final PaneId paneId in initialPaneIds) {
        await owners[paneId]!.cancelTextInput();
      }
      final TerminalPaneOwnerShutdownResult suspended =
          (await createdRestoration.suspendForReopen())!;
      shutdowns.addAll(suspended.sessions);
      for (final TerminalPaneSessionShutdownResult result
          in suspended.sessions) {
        stdout.writeln(result.machineLine());
      }
      _expectLifecycle(
        suspended.sessions.length == 8 &&
            suspended.isClean &&
            application.debugLiveObjectCount == 0 &&
            debugLiveTerminalTextInputClientCount() == 0 &&
            initialPaneIds.every(
              (PaneId paneId) =>
                  owners[paneId]!.adaptersDisposed &&
                  owners[paneId]!.surface.snapshot().isDisposed &&
                  owners[paneId]!.surface.snapshot().liveAtlasPinCount == 0,
            ),
        'suspension retained first-generation product resources',
      );

      reopenCompletion = Completer<TerminalRestorationReopenDisposition>();
      _injectApplicationReopenEventForTesting(
        application,
        monotonicNanoseconds: 901000000,
      );
      _injectApplicationReopenEventForTesting(
        application,
        monotonicNanoseconds: 902000000,
      );
      _expectLifecycle(
        await reopenCompletion.future.timeout(const Duration(seconds: 10)) ==
            TerminalRestorationReopenDisposition.restored,
        'typed Dock reopen did not restore a generation',
      );
      await Future<void>.delayed(Duration.zero);
      checkAsynchronousError();
      final TerminalRestorationGeneration restored =
          createdRestoration.current!;
      final TerminalApplicationState restoredState = restored.state;
      final List<PaneId> restoredPaneIds = restoredState.paneIds;
      _expectLifecycle(
        reopenEventCount == 2 &&
            restoredState.windowCount == 2 &&
            restoredState.tabCount == 4 &&
            restoredState.paneCount == 8 &&
            restoredPaneIds.every(
              (PaneId paneId) => !oldPaneIds.contains(paneId.value),
            ) &&
            restoredState.windowIds.every(
              (TerminalWindowId windowId) =>
                  !oldWindowIds.contains(windowId.value),
            ) &&
            restoredState.windows.first.tabs.last.customTitle ==
                'Restored product tab' &&
            restoredState.windows.first.tabs.last.color ==
                TerminalTabColor.greenMarker &&
            restoredState.windows.first.tabs.last.isZoomed &&
            restoredState.windows.last.tabs.last.customTitle ==
                'Restored auxiliary tab' &&
            restoredState.windows.last.tabs.last.color ==
                TerminalTabColor.purpleMarker &&
            restoredState.windows.every(
              (TerminalWindowState window) =>
                  window.tabs.length == 2 &&
                  window.tabs.fold<int>(
                        0,
                        (int total, TerminalTabState tab) =>
                            total + tab.paneIds.length,
                      ) ==
                      4,
            ) &&
            restored.launchWorkingDirectories.values.every(
              (String? value) => value == '/private/tmp',
            ) &&
            restored.hierarchy.nativeWindowCount == 4 &&
            restored.hierarchy.splitViewCount == 4 &&
            restored.hierarchy.paneResourceCount == 8 &&
            application.debugLiveObjectCount == 16 &&
            debugLiveTerminalTextInputClientCount() == 8 &&
            sessions.length == 16,
        'Dock reopen duplicated or incompletely restored product owners',
      );

      for (final PaneId paneId in restoredPaneIds) {
        await _waitForAsciiMarker(sessions[paneId]!, prompt.trimRight());
        final TerminalPane pane = restoredState.paneForId(paneId)!;
        pane.insertText(
          "if [ \"\$PWD\" = '/private/tmp' ]; then "
          "printf '\\r\\n__DT_RESTORED_CWD_%s__\\r\\n' "
          "'${paneId.value}'; fi",
        );
        await pane.submit();
        await _waitForAsciiMarker(
          sessions[paneId]!,
          '__DT_RESTORED_CWD_${paneId.value}__',
        );
      }
      for (final PaneId paneId in restoredPaneIds) {
        await owners[paneId]!.cancelTextInput();
      }
      final TerminalPaneOwnerShutdownResult finalShutdown =
          (await createdRestoration.shutdown(persist: false))!;
      shutdowns.addAll(finalShutdown.sessions);
      for (final TerminalPaneSessionShutdownResult result
          in finalShutdown.sessions) {
        stdout.writeln(result.machineLine());
      }
      _expectLifecycle(
        shutdowns.length == 16 &&
            shutdowns.every(
              (TerminalPaneSessionShutdownResult result) => result.isClean,
            ) &&
            owners.values.every(
              (_TerminalHierarchyProductPane owner) =>
                  owner.adaptersDisposed &&
                  owner.surface.snapshot().isDisposed &&
                  owner.surface.snapshot().liveAtlasPinCount == 0,
            ) &&
            application.debugLiveObjectCount == 0 &&
            debugLiveTerminalTextInputClientCount() == 0,
        'final restoration teardown retained product resources',
      );
      stdout.writeln(TerminalPaneOwnerShutdownResult(shutdowns).machineLine());

      final RuntimeLifecycleShutdownResult lifecycleShutdown =
          await createdLifecycle.shutdown();
      lifecycleWasShutDown = true;
      _expectLifecycle(
        !lifecycleShutdown.forced &&
            lifecycleShutdown.termination ==
                RuntimeLifecycleWorkerTermination.graceful,
        'restoration acceptance runtime worker did not stop cleanly',
      );
      checkAsynchronousError();
      _expectLifecycle(
        restorationDiagnostics.any(
              (TerminalRestorationDiagnostic diagnostic) =>
                  diagnostic.kind ==
                  TerminalRestorationDiagnosticKind.defaultCreated,
            ) &&
            restorationDiagnostics.any(
              (TerminalRestorationDiagnostic diagnostic) =>
                  diagnostic.kind == TerminalRestorationDiagnosticKind.saved,
            ) &&
            restorationDiagnostics.any(
              (TerminalRestorationDiagnostic diagnostic) =>
                  diagnostic.kind == TerminalRestorationDiagnosticKind.reopened,
            ),
        'restoration diagnostics omitted required content-free transitions',
      );
      stdout.writeln(
        'TERMINAL_RESTORATION_TEST windows=2 tabs=4 panes=8 '
        'panes_per_window=4 generations=2 sessions_clean=16 '
        'fullscreen_enter=true fullscreen_exit=true '
        'screen_migration=true frame_clamped=true scale=true persisted=true '
        'reopen_events=2 coalesced=true fresh_ids=true cwd=true metal_clean=16 '
        'text_clients=0 native_handles=0',
      );
    } finally {
      memoryPressureController?.dispose();
      systemRecoveryController?.dispose();
      await systemRecoverySubscription?.cancel();
      await reopenSubscription?.cancel();
      for (final _TerminalHierarchyProductPane owner
          in owners.values.toList(growable: false).reversed) {
        await owner.cancelTextInput();
      }
      final TerminalRestorationLifecycle? retainedRestoration = restoration;
      if (retainedRestoration != null && !retainedRestoration.isDisposed) {
        final TerminalPaneOwnerShutdownResult? result =
            await retainedRestoration.shutdown(persist: false);
        if (result != null) {
          for (final TerminalPaneSessionShutdownResult session
              in result.sessions) {
            stdout.writeln(session.machineLine());
          }
        }
      }
      for (final _TerminalHierarchyProductPane owner
          in owners.values.toList(growable: false).reversed) {
        if (!owner.adaptersDisposed) owner.disposeAdapters();
        if (!owner.view.isDisposed) owner.view.dispose();
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

  static Future<void> _runNativeHierarchyProductAcceptance(
    AppKitApplication application,
    PtyBackend ptyBackend,
    TerminalTerminfoEnvironment terminfoEnvironment,
    RuntimeLifecycleWorkerCommand workerCommand,
    String? initialWorkingDirectory,
  ) async {
    const String prompt = '__DT_HIERARCHY_PROMPT__ ';
    const String expectedInputHex = '1b5b41e697a5e69cace8aa9e';
    const int fairnessFloodByteCount = 100 * 1024 * 1024;
    const Duration fairnessProbeDelay = Duration(milliseconds: 20);
    const Rect windowFrame = Rect.fromLTWH(100, 90, 920, 580);
    final TerminalApplicationState state = TerminalApplicationState();
    final Map<PaneId, TerminalSession> sessions = <PaneId, TerminalSession>{};
    final Map<PaneId, _TerminalHierarchyProductPane> owners =
        <PaneId, _TerminalHierarchyProductPane>{};
    final Map<PaneId, String?> launchWorkingDirectories = <PaneId, String?>{};
    final List<TerminalPaneSessionShutdownResult> shutdowns =
        <TerminalPaneSessionShutdownResult>[];
    TerminalNativeHierarchyAdapter? hierarchy;
    TerminalPaneWorkScheduler? paneWorkScheduler;
    TerminalAppKitMenuProjection? closeQuitMenu;
    final List<StreamSubscription<WindowCloseRequestedEvent>>
    closeRequestSubscriptions =
        <StreamSubscription<WindowCloseRequestedEvent>>[];
    final List<StreamSubscription<ApplicationTerminateRequestedEvent>>
    terminationRequestSubscriptions =
        <StreamSubscription<ApplicationTerminateRequestedEvent>>[];
    RuntimeLifecycleCoordinator? lifecycle;
    var lifecycleWasShutDown = false;
    var programmaticTerminationCount = 0;
    var nativeCloseRequestCount = 0;
    var nativeTerminationRequestCount = 0;
    var closeMenuInvocationCount = 0;
    var quitMenuInvocationCount = 0;
    var terminalInputDeliveryCount = 0;
    var finalNativeHandleCount = -1;
    var finalTextInputClientCount = -1;
    Object? asynchronousError;
    StackTrace? asynchronousStackTrace;
    final TerminalTabPresentationResolver presentationResolver =
        TerminalTabPresentationResolver(
          metadataForPane: (PaneId paneId) =>
              sessions[paneId]?.terminalScreenSet.metadata,
        );

    void recordAsynchronousError(Object error, StackTrace stackTrace) {
      asynchronousError ??= error;
      asynchronousStackTrace ??= stackTrace;
    }

    TerminalPaneConfiguration configuration({String? workingDirectory}) {
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
                initialWorkingDirectory: workingDirectory,
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
                graphicsWorker: lifecycle,
              );
              sessions[id.paneId] = session;
              launchWorkingDirectories[id.paneId] = workingDirectory;
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

    void routeCommittedText(
      _TerminalHierarchyProductPane owner,
      String text,
      int monotonicNanoseconds,
    ) {
      final TerminalTextInputRouteResult result = owner.textRouter.route(
        TerminalTextInputCommitEvent(
          clientId: owner.client.clientId,
          generation: owner.textRouter.lastGeneration + 1,
          monotonicNanoseconds: monotonicNanoseconds,
          text: text,
          replacement: TerminalTextInputRange.notFound,
        ),
      );
      _expectLifecycle(
        result.disposition == TerminalTextInputRouteDisposition.committed,
        'fairness probe did not traverse the committed-text input route',
      );
    }

    Future<int> measureVisibleResponse(
      _TerminalHierarchyProductPane owner, {
      required String command,
      required String marker,
    }) async {
      final Stopwatch stopwatch = Stopwatch()..start();
      final Completer<void> dispatched = Completer<void>();
      Timer(fairnessProbeDelay, () async {
        try {
          routeCommittedText(
            owner,
            command,
            stopwatch.elapsedMicroseconds * 1000,
          );
          await owner.pane.submit();
          dispatched.complete();
        } on Object catch (error, stackTrace) {
          dispatched.completeError(error, stackTrace);
        }
      });
      await dispatched.future.timeout(const Duration(seconds: 5));
      await _waitForAsciiMarkerPresented(
        owner,
        marker,
        timeout: const Duration(seconds: 10),
      );
      checkAsynchronousError();
      final int latencyMicros =
          stopwatch.elapsedMicroseconds - fairnessProbeDelay.inMicroseconds;
      return latencyMicros <= 0 ? 1 : latencyMicros;
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
        configuration(workingDirectory: initialWorkingDirectory),
      );
      final TerminalTabState firstTab = logicalWindow.selectedTab;
      final PaneId firstPaneId = firstTab.focusedPaneId;
      final TerminalPane firstPane = state.paneForId(firstPaneId)!;
      await firstPane.start();
      await _waitForAsciiMarker(sessions[firstPaneId]!, prompt.trimRight());
      firstPane.insertText(
        "cd /private/tmp; printf "
        "'\\033]2;__DT_HIERARCHY_LIVE_TITLE__\\007"
        "\\033]7;file://localhost/private/tmp\\007'",
      );
      await firstPane.submit();
      await _waitForSessionMetadata(
        sessions[firstPaneId]!,
        expectedTitle: '__DT_HIERARCHY_LIVE_TITLE__',
        expectedWorkingDirectory: Uri.parse('file://localhost/private/tmp'),
      );
      final String? inheritedWorkingDirectory = presentationResolver
          .inheritedWorkingDirectoryForPane(firstPaneId);
      _expectLifecycle(
        inheritedWorkingDirectory == '/private/tmp',
        'hierarchy acceptance did not resolve the local OSC 7 cwd',
      );
      final TerminalPane secondPane = await state.splitPane(
        firstPaneId,
        configuration(workingDirectory: inheritedWorkingDirectory),
        axis: TerminalSplitAxis.horizontal,
        fraction: 0.3,
      );
      final TerminalSplitNodeId firstRootId = firstTab.splitTree.root.id;
      final TerminalTabState secondTab = await state.createTab(
        logicalWindow.id,
        configuration(workingDirectory: inheritedWorkingDirectory),
      );
      final PaneId thirdPaneId = secondTab.focusedPaneId;
      final TerminalPane fourthPane = await state.splitPane(
        thirdPaneId,
        configuration(workingDirectory: inheritedWorkingDirectory),
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
      state
        ..focusPane(firstTab.id, firstPaneId)
        ..selectTab(logicalWindow.id, secondTab.id)
        ..renameTab(secondTab.id, 'Pinned hierarchy tab')
        ..setTabColor(secondTab.id, TerminalTabColor.purpleMarker);

      final TerminalPaneWorkScheduler createdPaneWorkScheduler =
          TerminalPaneWorkScheduler(
            onError: (_, Object error, StackTrace trace) {
              recordAsynchronousError(error, trace);
            },
          );
      paneWorkScheduler = createdPaneWorkScheduler;
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
                    paneWorkScheduler: createdPaneWorkScheduler,
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
                      terminalInputDeliveryCount++;
                      keyRouter.handleTerminalKeyEvent(event, pane);
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
                    onCommit: (String text) {
                      terminalInputDeliveryCount++;
                      pane.insertText(text);
                    },
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
            presentationBuilder:
                (TerminalWindowState window, TerminalTabState tab) =>
                    presentationResolver.resolve(
                      tab,
                      fallbackTitle: 'Dart Terminal — ${window.id}:${tab.id}',
                    ),
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
      final Window firstNativeTab = createdHierarchy.windowForTab(firstTab.id)!;
      final Window secondNativeTab = createdHierarchy.windowForTab(
        secondTab.id,
      )!;
      _expectLifecycle(
        firstNativeTab.title == '__DT_HIERARCHY_LIVE_TITLE__' &&
            firstNativeTab.representedFilePath == '/private/tmp' &&
            secondNativeTab.title == 'Pinned hierarchy tab' &&
            secondNativeTab.tabAccessory ==
                terminalTabAccessory(TerminalTabColor.purpleMarker),
        'hierarchy presentation did not reach both retained native tabs',
      );
      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 4 &&
            createdHierarchy.nativeWindowCount == 2 &&
            createdHierarchy.splitViewCount == 2 &&
            createdHierarchy.paneResourceCount == 4 &&
            createdPaneWorkScheduler.registeredPaneCount == 4 &&
            createdPaneWorkScheduler.pendingPaneCount <= 4 &&
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
        if (pane.state == TerminalPaneState.created) {
          await pane.start();
        }
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
      for (final TerminalSession session in sessions.values) {
        session.attachGraphicsWorker(createdLifecycle);
      }
      _writeLifecycleEvent(
        RuntimeLifecycleScenario.normal,
        'root-ready',
        createdLifecycle.generation,
      );
      MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);
      await _expectResponse(createdLifecycle);

      for (final PaneId paneId in paneIds) {
        await _waitForAsciiMarker(sessions[paneId]!, prompt.trimRight());
      }
      _expectLifecycle(
        paneIds
            .skip(1)
            .every(
              (PaneId paneId) =>
                  launchWorkingDirectories[paneId] == '/private/tmp',
            ),
        'descendant sessions did not receive the inherited launch cwd',
      );
      for (final PaneId paneId in paneIds.skip(1)) {
        final TerminalPane pane = state.paneForId(paneId)!;
        pane.insertText(
          "if [ \"\$PWD\" = '/private/tmp' ]; then "
          "printf '\\r\\n__DT_INHERITED_CWD_%s__\\r\\n' "
          "'${paneId.value}'; fi",
        );
        await pane.submit();
        await _waitForAsciiMarker(
          sessions[paneId]!,
          '__DT_INHERITED_CWD_${paneId.value}__',
        );
      }
      final TerminalPane fourthLogicalPane = state.paneForId(fourthPane.id)!;
      fourthLogicalPane.insertText(
        "printf "
        "'\\033]2;__DT_HIERARCHY_DESCENDANT_TITLE__\\007"
        "\\033]7;file://localhost/private/tmp\\007'",
      );
      await fourthLogicalPane.submit();
      await _waitForSessionMetadata(
        sessions[fourthPane.id]!,
        expectedTitle: '__DT_HIERARCHY_DESCENDANT_TITLE__',
        expectedWorkingDirectory: Uri.parse('file://localhost/private/tmp'),
      );
      state
        ..renameTab(secondTab.id, null)
        ..setTabColor(secondTab.id, null);
      createdHierarchy.reconcile();
      _expectLifecycle(
        secondNativeTab.title == '__DT_HIERARCHY_DESCENDANT_TITLE__' &&
            secondNativeTab.representedFilePath == '/private/tmp' &&
            secondNativeTab.tabAccessory == null,
        'hierarchy rename/color reset did not resume live session metadata',
      );
      stdout.writeln(
        'TERMINAL_TAB_METADATA_TEST title=true rename=true color=true '
        'cwd_inheritance=true proxy=true reset=true',
      );

      for (final PaneId paneId in paneIds) {
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
      final TwoPaneSplitView firstRoot = createdHierarchy.splitViewForNode(
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

      final int menuShortcutInputBaseline = terminalInputDeliveryCount;
      final TerminalActionCatalog hierarchyActionCatalog =
          TerminalActionCatalog.standard();
      late final TerminalCommandPalettePresenter hierarchyPalette;
      final TerminalActionDispatcher hierarchyActionDispatcher =
          TerminalActionDispatcher(
            catalog: hierarchyActionCatalog,
            registrations: <TerminalActionRegistration>[
              TerminalActionRegistration(
                id: TerminalActionId.openCommandPalette,
                handler: () => hierarchyPalette.open(),
              ),
              TerminalActionRegistration(
                id: TerminalActionId.focusNextPane,
                handler: () {
                  final TerminalTabState tab = state.activeWindow!.selectedTab;
                  state.traversePaneFocus(
                    tab.id,
                    direction: TerminalPaneFocusTraversal.next,
                  );
                  createdHierarchy.reconcile();
                },
              ),
            ],
          );
      final Window hierarchyPaletteTerminalWindow = createdHierarchy
          .windowForTab(secondTab.id)!;
      hierarchyPalette = TerminalCommandPalettePresenter(
        dispatcher: hierarchyActionDispatcher,
        terminalWindow: hierarchyPaletteTerminalWindow,
        terminalView: owners[thirdPaneId]!.view,
        onError: recordAsynchronousError,
      );
      final TerminalAppKitMenuProjection hierarchyActionMenu =
          TerminalAppKitMenuProjection.install(
            application: application,
            dispatcher: hierarchyActionDispatcher,
            onDispatched: (TerminalActionDispatchResult result) {
              hierarchyPalette.refresh();
              if (result.disposition ==
                  TerminalActionDispatchDisposition.failed) {
                recordAsynchronousError(result.error!, result.stackTrace!);
              }
            },
          );
      try {
        await _exerciseCommandPaletteProduct(
          application,
          hierarchyPaletteTerminalWindow,
          hierarchyActionMenu,
          hierarchyPalette,
          () => terminalInputDeliveryCount,
        );
        checkAsynchronousError();
        _expectLifecycle(
          secondTab.focusedPaneId == thirdPaneId &&
              hierarchyPalette.dispatchCount == 1 &&
              terminalInputDeliveryCount == menuShortcutInputBaseline,
          'hierarchy menu shortcut changed terminal input or the wrong pane',
        );
      } finally {
        await hierarchyPalette.dispose();
        await hierarchyActionMenu.dispose();
      }
      createdHierarchy.reconcile();
      _expectLifecycle(
        application.debugLiveObjectCount == 8 &&
            debugLiveTerminalTextInputClientCount() == 4,
        'hierarchy menu shortcut retained native palette resources',
      );
      stdout.writeln(
        'TERMINAL_HIERARCHY_MENU_SHORTCUT_TEST panes=4 shortcut=true '
        'action=pane.focus-next invocations=1 terminal_write_delta=0 '
        'focused_only=true first_responder=true handles_restored=true',
      );

      state
        ..selectTab(logicalWindow.id, firstTab.id)
        ..focusPane(firstTab.id, secondPane.id);
      createdHierarchy.reconcile();
      final _TerminalHierarchyProductPane floodOwner = owners[firstPaneId]!;
      final _TerminalHierarchyProductPane probeOwner = owners[secondPane.id]!;
      _expectLifecycle(
        floodOwner.isVisible && probeOwner.isVisible,
        'fairness acceptance requires two visible sibling panes',
      );
      await _waitForPaneProcessDisposition(
        floodOwner.pane,
        TerminalPaneProcessDisposition.idleShell,
      );
      await _waitForPaneProcessDisposition(
        probeOwner.pane,
        TerminalPaneProcessDisposition.idleShell,
      );

      final List<int> baselineLatencyMicros = <int>[];
      for (var sample = 1; sample <= 3; sample++) {
        final String marker = '__DT_FAIRNESS_INPUT_BASELINE_${sample}__';
        baselineLatencyMicros.add(
          await measureVisibleResponse(
            probeOwner,
            command:
                "printf '\\r\\n__DT_FAIRNESS_%s_%s_%s__\\r\\n' "
                "'INPUT' 'BASELINE' '$sample'",
            marker: marker,
          ),
        );
      }
      final int idleBaselineMicros = baselineLatencyMicros.reduce(
        (int current, int candidate) =>
            candidate > current ? candidate : current,
      );
      final TerminalPaneWorkSchedulerSnapshot schedulerBeforeFlood =
          createdPaneWorkScheduler.snapshot();
      final int floodAcceptedFramesBefore = floodOwner.surface
          .snapshot()
          .acceptedFrameCount;
      const String floodCompleteMarker = '__DT_FAIRNESS_FLOOD_COMPLETE__';
      final Future<int> floodLatencyFuture = measureVisibleResponse(
        probeOwner,
        command:
            "printf '\\r\\n__DT_FAIRNESS_%s_%s__\\r\\n' "
            "'INPUT' 'FLOOD'",
        marker: '__DT_FAIRNESS_INPUT_FLOOD__',
      );
      routeCommittedText(
        floodOwner,
        "/usr/bin/yes X | /usr/bin/tr '\\n' '\\r' | "
        '/usr/bin/head -c $fairnessFloodByteCount; '
        "printf '\\r\\n__DT_FAIRNESS_%s_%s__\\r\\n' "
        "'FLOOD' 'COMPLETE'",
        1,
      );
      await floodOwner.pane.submit();
      final int floodLatencyMicros = await floodLatencyFuture;
      final bool inputCompletedDuringFlood =
          _findAscii(
            floodOwner.session.terminalScreenSet.activeScreen,
            floodCompleteMarker,
          ) ==
          null;
      await _waitForAsciiMarkerPresented(
        floodOwner,
        floodCompleteMarker,
        timeout: const Duration(seconds: 180),
      );
      final TerminalPaneWorkSchedulerSnapshot schedulerAfterFlood =
          createdPaneWorkScheduler.snapshot();
      final List<TerminalLiveMetalSurfaceSnapshot> surfaceSnapshots = owners
          .values
          .map(
            (_TerminalHierarchyProductPane owner) => owner.surface.snapshot(),
          )
          .toList(growable: false);
      final int ratioMilli =
          (floodLatencyMicros * 1000 + idleBaselineMicros - 1) ~/
          idleBaselineMicros;
      final bool framesBounded = surfaceSnapshots.every(
        (TerminalLiveMetalSurfaceSnapshot snapshot) =>
            snapshot.pendingFrameCount <= 1,
      );
      stdout.writeln(
        'TERMINAL_MULTI_PANE_FAIRNESS_MEASUREMENT '
        'baseline_us=$idleBaselineMicros flood_us=$floodLatencyMicros '
        'ratio_milli=$ratioMilli input_during_flood='
        '$inputCompletedDuringFlood scheduler_registered='
        '${schedulerAfterFlood.registeredPaneCount} scheduler_pending='
        '${schedulerAfterFlood.pendingPaneCount} scheduler_yields='
        '${schedulerAfterFlood.yieldCount} scheduler_yields_before='
        '${schedulerBeforeFlood.yieldCount} scheduler_peak_pending='
        '${schedulerAfterFlood.peakPendingPaneCount} '
        'scheduler_max_work_observed='
        '${schedulerAfterFlood.maximumWorkPerTurnObserved} '
        'flood_frame_advanced='
        '${floodOwner.surface.snapshot().acceptedFrameCount > floodAcceptedFramesBefore} '
        'frames_bounded=$framesBounded',
      );
      _expectLifecycle(
        inputCompletedDuringFlood &&
            floodLatencyMicros <= idleBaselineMicros * 2 &&
            schedulerAfterFlood.registeredPaneCount == 4 &&
            schedulerAfterFlood.pendingPaneCount <= 4 &&
            schedulerAfterFlood.peakPendingPaneCount <= 4 &&
            schedulerAfterFlood.maximumWorkPerTurnObserved <= 4 &&
            schedulerAfterFlood.yieldCount > 0 &&
            schedulerAfterFlood.yieldCount > schedulerBeforeFlood.yieldCount &&
            floodOwner.surface.snapshot().acceptedFrameCount >
                floodAcceptedFramesBefore &&
            framesBounded,
        '100 MiB pane flood violated cross-pane fairness or bounded state',
      );
      stdout.writeln(
        'TERMINAL_MULTI_PANE_FAIRNESS_TEST bytes=$fairnessFloodByteCount '
        'panes=4 baseline_samples=3 input_visible=true '
        'input_completed_during_flood=true flood_complete=true '
        'scheduler_registered=4 scheduler_pending_bound=4 '
        'scheduler_work_bound=4 scheduler_yielded=true frames_bounded=true',
      );

      final TerminalPaneCloseCoordinator paneCloseCoordinator =
          TerminalPaneCloseCoordinator(
            state: state,
            onHierarchyChanged: createdHierarchy.reconcile,
          );
      Completer<TerminalPaneCloseResult>? pendingCloseResult;
      Completer<TerminalApplicationQuitResult>? pendingNativeQuitResult;
      Completer<TerminalApplicationQuitResult>? pendingMenuQuitResult;
      late final TerminalApplicationQuitCoordinator quitCoordinator;

      Future<void> disposeNativeRoutes() async {
        for (final StreamSubscription<ApplicationTerminateRequestedEvent>
            subscription
            in terminationRequestSubscriptions.toList(growable: false)) {
          await subscription.cancel();
        }
        terminationRequestSubscriptions.clear();
        for (final StreamSubscription<WindowCloseRequestedEvent> subscription
            in closeRequestSubscriptions.toList(growable: false)) {
          await subscription.cancel();
        }
        closeRequestSubscriptions.clear();
        final TerminalAppKitMenuProjection? menu = closeQuitMenu;
        closeQuitMenu = null;
        await menu?.dispose();
      }

      quitCoordinator = TerminalApplicationQuitCoordinator(
        state: state,
        paneCloseCoordinator: paneCloseCoordinator,
        replyToTerminationRequest:
            (
              ApplicationTerminateRequestedEvent request, {
              required bool allow,
            }) {
              application.replyToTerminationRequest(request, allow: allow);
            },
        onPreShutdown: () async {
          for (final _TerminalHierarchyProductPane owner in owners.values) {
            await owner.cancelTextInput();
          }
          await disposeNativeRoutes();
          final RuntimeLifecycleShutdownResult lifecycleShutdown =
              await createdLifecycle.shutdown();
          lifecycleWasShutDown = true;
          _expectLifecycle(
            !lifecycleShutdown.forced &&
                lifecycleShutdown.termination ==
                    RuntimeLifecycleWorkerTermination.graceful,
            'hierarchy acceptance runtime worker did not stop cleanly',
          );
          createdHierarchy.dispose();
          final TerminalPaneWorkSchedulerSnapshot schedulerAfterHierarchy =
              createdPaneWorkScheduler.snapshot();
          _expectLifecycle(
            schedulerAfterHierarchy.registeredPaneCount == 0 &&
                schedulerAfterHierarchy.pendingPaneCount == 0,
            'hierarchy disposal retained shared pane scheduling work',
          );
          createdPaneWorkScheduler.dispose();
        },
        terminateProgrammatically: () async {
          programmaticTerminationCount++;
          finalTextInputClientCount = debugLiveTerminalTextInputClientCount();
          finalNativeHandleCount = application.debugLiveObjectCount;
          await application.terminate().timeout(_hostTerminationTimeout);
        },
      );

      void listenForCloseRequest(Window window) {
        closeRequestSubscriptions.add(
          window.onCloseRequested.listen((WindowCloseRequestedEvent event) {
            nativeCloseRequestCount++;
            window.replyToCloseRequest(event, allow: false);
            unawaited(
              paneCloseCoordinator.requestClose().then(
                (TerminalPaneCloseResult result) {
                  final Completer<TerminalPaneCloseResult>? waiter =
                      pendingCloseResult;
                  if (waiter != null && !waiter.isCompleted) {
                    waiter.complete(result);
                  }
                },
                onError: (Object error, StackTrace stackTrace) {
                  final Completer<TerminalPaneCloseResult>? waiter =
                      pendingCloseResult;
                  if (waiter != null && !waiter.isCompleted) {
                    waiter.completeError(error, stackTrace);
                  } else {
                    recordAsynchronousError(error, stackTrace);
                  }
                },
              ),
            );
          }, onError: recordAsynchronousError),
        );
      }

      listenForCloseRequest(firstNativeTab);
      listenForCloseRequest(secondNativeTab);
      terminationRequestSubscriptions.add(
        application.onTerminateRequested.listen((
          ApplicationTerminateRequestedEvent event,
        ) {
          nativeTerminationRequestCount++;
          unawaited(
            quitCoordinator
                .handleTerminationRequest(event)
                .then(
                  (TerminalApplicationQuitResult result) {
                    final Completer<TerminalApplicationQuitResult>? waiter =
                        pendingNativeQuitResult;
                    if (waiter != null && !waiter.isCompleted) {
                      waiter.complete(result);
                    }
                  },
                  onError: (Object error, StackTrace stackTrace) {
                    final Completer<TerminalApplicationQuitResult>? waiter =
                        pendingNativeQuitResult;
                    if (waiter != null && !waiter.isCompleted) {
                      waiter.completeError(error, stackTrace);
                    } else {
                      recordAsynchronousError(error, stackTrace);
                    }
                  },
                ),
          );
        }, onError: recordAsynchronousError),
      );

      final TerminalActionDispatcher closeQuitDispatcher =
          TerminalActionDispatcher(
            catalog: TerminalActionCatalog.standard(),
            registrations: <TerminalActionRegistration>[
              TerminalActionRegistration(
                id: TerminalActionId.closeWindow,
                isAvailable: () =>
                    !state.isDisposed && state.activeWindow != null,
                handler: () {
                  final TerminalTabId activeTabId =
                      state.activeWindow!.selectedTab.id;
                  final Window? activeNativeWindow = createdHierarchy
                      .windowForTab(activeTabId);
                  if (activeNativeWindow == null) {
                    throw StateError(
                      'active hierarchy tab has no native window',
                    );
                  }
                  activeNativeWindow.requestClose();
                },
              ),
              TerminalActionRegistration(
                id: TerminalActionId.quitApplication,
                isAvailable: () => !state.isDisposed,
                handler: () async {
                  final TerminalApplicationQuitResult result =
                      await quitCoordinator.requestQuit();
                  final Completer<TerminalApplicationQuitResult>? waiter =
                      pendingMenuQuitResult;
                  if (waiter != null && !waiter.isCompleted) {
                    waiter.complete(result);
                  }
                },
              ),
            ],
          );
      final TerminalAppKitMenuProjection
      installedCloseQuitMenu = TerminalAppKitMenuProjection.install(
        application: application,
        dispatcher: closeQuitDispatcher,
        onNativeInvocation: (TerminalActionId id, MenuItemInvokedEvent event) {
          switch (id) {
            case TerminalActionId.closeWindow:
              closeMenuInvocationCount++;
            case TerminalActionId.quitApplication:
              quitMenuInvocationCount++;
            default:
              break;
          }
        },
        onDispatched: (TerminalActionDispatchResult result) {
          if (result.disposition == TerminalActionDispatchDisposition.failed) {
            recordAsynchronousError(result.error!, result.stackTrace!);
          }
        },
      );
      closeQuitMenu = installedCloseQuitMenu;
      final MenuItem closeMenuItem = installedCloseQuitMenu.itemForAction(
        TerminalActionId.closeWindow,
      );
      final MenuItem quitMenuItem = installedCloseQuitMenu.itemForAction(
        TerminalActionId.quitApplication,
      );

      Future<TerminalPaneCloseResult> invokeCloseMenu() async {
        final Completer<TerminalPaneCloseResult> waiter =
            Completer<TerminalPaneCloseResult>();
        _expectLifecycle(
          pendingCloseResult == null,
          'hierarchy Close invocation overlapped another request',
        );
        pendingCloseResult = waiter;
        try {
          closeMenuItem.performAction();
          return await waiter.future.timeout(const Duration(seconds: 5));
        } finally {
          pendingCloseResult = null;
        }
      }

      Future<TerminalApplicationQuitResult> invokeNativeQuit() async {
        final Completer<TerminalApplicationQuitResult> waiter =
            Completer<TerminalApplicationQuitResult>();
        _expectLifecycle(
          pendingNativeQuitResult == null,
          'hierarchy native Quit invocation overlapped another request',
        );
        pendingNativeQuitResult = waiter;
        try {
          appkit_testing.requestApplicationTerminationForTesting(application);
          return await waiter.future.timeout(const Duration(seconds: 5));
        } finally {
          pendingNativeQuitResult = null;
        }
      }

      Future<TerminalApplicationQuitResult> invokeQuitMenu() async {
        final Completer<TerminalApplicationQuitResult> waiter =
            Completer<TerminalApplicationQuitResult>();
        _expectLifecycle(
          pendingMenuQuitResult == null,
          'hierarchy menu Quit invocation overlapped another request',
        );
        pendingMenuQuitResult = waiter;
        try {
          quitMenuItem.performAction();
          return await waiter.future.timeout(const Duration(seconds: 10));
        } finally {
          pendingMenuQuitResult = null;
        }
      }

      state
        ..selectTab(logicalWindow.id, firstTab.id)
        ..focusPane(firstTab.id, secondPane.id);
      createdHierarchy.reconcile();
      secondPane.insertText('sleep 30');
      await secondPane.submit();
      final TerminalPaneProcessSnapshot closeForeground =
          await _waitForPaneProcessDisposition(
            secondPane,
            TerminalPaneProcessDisposition.foregroundProcess,
          );
      _expectLifecycle(
        closeForeground.foregroundProcessGroup !=
            closeForeground.owningProcessGroup,
        'hierarchy Close fixture did not start a distinct process group',
      );
      final TerminalPaneCloseResult firstClose = await invokeCloseMenu();
      stdout.writeln(firstClose.machineLine());
      _expectLifecycle(
        firstClose.disposition ==
                TerminalPaneCloseDisposition.confirmationRequired &&
            firstClose.confirmation?.paneId == secondPane.id &&
            state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 4 &&
            createdHierarchy.paneResourceCount == 4 &&
            !initialResources[secondPane.id]!.isDisposed &&
            !owners[secondPane.id]!.adaptersDisposed,
        'foreground Close mutated hierarchy before confirmation',
      );
      await owners[secondPane.id]!.cancelTextInput();
      final TerminalPaneCloseResult confirmedClose = await invokeCloseMenu();
      stdout.writeln(confirmedClose.machineLine());
      _expectLifecycle(
        confirmedClose.disposition == TerminalPaneCloseDisposition.removed &&
            confirmedClose.removal?.paneId == secondPane.id,
        'repeated foreground Close did not remove the confirmed pane',
      );
      shutdowns.add(confirmedClose.removal!.shutdown);
      stdout.writeln(confirmedClose.removal!.shutdown.machineLine());
      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 3 &&
            createdHierarchy.nativeWindowCount == 2 &&
            createdHierarchy.splitViewCount == 1 &&
            createdHierarchy.paneResourceCount == 3 &&
            owners[secondPane.id]!.adaptersDisposed &&
            initialResources[secondPane.id]!.isDisposed &&
            !initialResources[firstPaneId]!.isDisposed,
        'confirmed foreground Close did not collapse exactly one split',
      );

      state
        ..selectTab(logicalWindow.id, secondTab.id)
        ..focusPane(secondTab.id, fourthPane.id);
      createdHierarchy.reconcile();
      fourthPane.insertText('exit 23');
      await fourthPane.submit();
      await sessions[fourthPane.id]!.waitForTermination().timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(Duration.zero);
      final TerminalPaneProcessSnapshot nonLive =
          await _waitForPaneProcessDisposition(
            fourthPane,
            TerminalPaneProcessDisposition.nonLive,
          );
      _expectLifecycle(
        nonLive.childProcessId == null &&
            fourthPane.state == TerminalPaneState.exited &&
            sessions[fourthPane.id]!.exit?.exitCode == 23,
        'abnormal hierarchy pane did not retain a typed non-live status',
      );
      await owners[fourthPane.id]!.cancelTextInput();
      final TerminalPaneCloseResult nonLiveClose = await invokeCloseMenu();
      stdout.writeln(nonLiveClose.machineLine());
      _expectLifecycle(
        nonLiveClose.disposition == TerminalPaneCloseDisposition.removed &&
            nonLiveClose.removal?.paneId == fourthPane.id &&
            nonLiveClose.confirmation == null,
        'non-live hierarchy pane did not close in one menu action',
      );
      shutdowns.add(nonLiveClose.removal!.shutdown);
      stdout.writeln(nonLiveClose.removal!.shutdown.machineLine());
      _expectLifecycle(
        state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 2 &&
            createdHierarchy.nativeWindowCount == 2 &&
            createdHierarchy.splitViewCount == 0 &&
            createdHierarchy.paneResourceCount == 2 &&
            owners[fourthPane.id]!.adaptersDisposed &&
            initialResources[fourthPane.id]!.isDisposed &&
            !initialResources[thirdPaneId]!.isDisposed,
        'non-live Close did not collapse exactly its retained split',
      );

      state.focusPane(secondTab.id, thirdPaneId);
      createdHierarchy.reconcile();
      final TerminalPane thirdPane = state.paneForId(thirdPaneId)!;
      thirdPane.insertText('sleep 30');
      await thirdPane.submit();
      await _waitForPaneProcessDisposition(
        state.paneForId(firstPaneId)!,
        TerminalPaneProcessDisposition.idleShell,
      );
      await _waitForPaneProcessDisposition(
        thirdPane,
        TerminalPaneProcessDisposition.foregroundProcess,
      );

      final TerminalApplicationQuitResult firstNativeQuit =
          await invokeNativeQuit();
      stdout.writeln(firstNativeQuit.machineLine());
      stdout.writeln(firstNativeQuit.snapshot!.machineLine());
      final List<PaneId> nativeSnapshotPanes = firstNativeQuit.snapshot!.panes
          .map((TerminalApplicationQuitPaneSnapshot pane) => pane.paneId)
          .toList(growable: false);
      _expectLifecycle(
        firstNativeQuit.disposition ==
                TerminalApplicationQuitDisposition.confirmationRequired &&
            firstNativeQuit.nativeOperationId != null &&
            nativeSnapshotPanes.length == 2 &&
            nativeSnapshotPanes[0] == firstPaneId &&
            nativeSnapshotPanes[1] == thirdPaneId &&
            firstNativeQuit.snapshot!.count(
                  TerminalPaneProcessDisposition.foregroundProcess,
                ) ==
                1 &&
            state.paneCount == 2 &&
            createdHierarchy.paneResourceCount == 2,
        'native Quit did not defer one atomic visual-order snapshot',
      );
      _expectLifecycle(
        quitCoordinator.cancelQuit(firstNativeQuit.confirmation!),
        'first native Quit confirmation could not be refused',
      );
      final TerminalApplicationQuitResult secondNativeQuit =
          await invokeNativeQuit();
      stdout.writeln(secondNativeQuit.machineLine());
      _expectLifecycle(
        secondNativeQuit.disposition ==
                TerminalApplicationQuitDisposition.confirmationRequired &&
            secondNativeQuit.nativeOperationId != null &&
            secondNativeQuit.nativeOperationId !=
                firstNativeQuit.nativeOperationId &&
            state.paneCount == 2 &&
            createdHierarchy.paneResourceCount == 2,
        'refused native Quit did not clear pending native state for retry',
      );
      _expectLifecycle(
        quitCoordinator.cancelQuit(secondNativeQuit.confirmation!),
        'second native Quit confirmation could not be refused',
      );

      final TerminalApplicationQuitResult firstMenuQuit =
          await invokeQuitMenu();
      stdout.writeln(firstMenuQuit.machineLine());
      _expectLifecycle(
        firstMenuQuit.disposition ==
                TerminalApplicationQuitDisposition.confirmationRequired &&
            firstMenuQuit.nativeOperationId == null &&
            firstMenuQuit.snapshot == firstNativeQuit.snapshot &&
            state.windowCount == 1 &&
            state.tabCount == 2 &&
            state.paneCount == 2 &&
            createdHierarchy.nativeWindowCount == 2 &&
            createdHierarchy.paneResourceCount == 2 &&
            !initialResources[firstPaneId]!.isDisposed &&
            !initialResources[thirdPaneId]!.isDisposed,
        'first menu Quit mutated the aggregate before confirmation',
      );
      final TerminalApplicationQuitResult acceptedMenuQuit =
          await invokeQuitMenu();
      stdout.writeln(acceptedMenuQuit.machineLine());
      _expectLifecycle(
        acceptedMenuQuit.disposition ==
                TerminalApplicationQuitDisposition.terminated &&
            acceptedMenuQuit.shutdown?.sessions.length == 2 &&
            acceptedMenuQuit.shutdown!.isClean &&
            programmaticTerminationCount == 1 &&
            lifecycleWasShutDown,
        'repeated menu Quit did not complete one clean aggregate teardown',
      );
      shutdowns.addAll(acceptedMenuQuit.shutdown!.sessions);
      for (final TerminalPaneSessionShutdownResult result
          in acceptedMenuQuit.shutdown!.sessions) {
        stdout.writeln(result.machineLine());
      }
      stdout.writeln(TerminalPaneOwnerShutdownResult(shutdowns).machineLine());

      _expectLifecycle(
        state.isDisposed &&
            state.windowCount == 0 &&
            state.tabCount == 0 &&
            state.paneCount == 0 &&
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
            finalTextInputClientCount == 0 &&
            finalNativeHandleCount == 0 &&
            nativeCloseRequestCount == 3 &&
            nativeTerminationRequestCount == 2 &&
            closeMenuInvocationCount == 3 &&
            quitMenuInvocationCount == 2 &&
            createdPaneWorkScheduler.snapshot().isDisposed &&
            createdPaneWorkScheduler.snapshot().registeredPaneCount == 0 &&
            createdPaneWorkScheduler.snapshot().pendingPaneCount == 0,
        'Close/Quit acceptance retained product resources or lost a route',
      );
      checkAsynchronousError();
      stdout.writeln(
        'TERMINAL_CLOSE_QUIT_TEST panes=4 close_requests=3 close_menu=3 '
        'quit_menu=2 native_quit_requests=2 foreground_confirmation=true '
        'non_live_immediate=true quit_atomic=true native_refused=true '
        'programmatic_termination=1 sessions_clean=4 metal_clean=4 '
        'text_clients=0 native_handles=0',
      );
      stdout.writeln(
        'TERMINAL_NATIVE_HIERARCHY_TEST windows=1 tabs=2 panes=4 splits=2 '
        'resize=true equalize=true zoom=true focus=true key=true ime=true '
        'menu_shortcut=true isolated=true close=true sessions_clean=4 metal_clean=4 '
        'text_clients=0 native_handles=0',
      );
    } finally {
      for (final StreamSubscription<ApplicationTerminateRequestedEvent>
          subscription
          in terminationRequestSubscriptions.toList(growable: false)) {
        await subscription.cancel();
      }
      terminationRequestSubscriptions.clear();
      for (final StreamSubscription<WindowCloseRequestedEvent> subscription
          in closeRequestSubscriptions.toList(growable: false)) {
        await subscription.cancel();
      }
      closeRequestSubscriptions.clear();
      final TerminalAppKitMenuProjection? menu = closeQuitMenu;
      closeQuitMenu = null;
      await menu?.dispose();
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
      paneWorkScheduler?.dispose();
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
    String fallbackWindowTitle,
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
    final bool synchronizedOutput = await _exerciseSynchronizedOutput(
      session,
      pane,
      surface,
    );
    final bool kittyGraphics = await _exerciseKittyGraphics(
      session,
      pane,
      surface,
    );
    final bool searchOverlay = await _exerciseSearchOverlay(
      session,
      pane,
      surface,
    );
    final bool p3Color = _exerciseP3ColorRendering();
    final bool cellGlyphs = await _exerciseSyntheticCellGlyphs(
      session,
      pane,
      surface,
    );
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
    final bool semanticPointer = await _exerciseSemanticPointerInput(
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
      fallbackWindowTitle,
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
    var scaleSynchronized = false;
    var nativeWindowScale16_16 = 0;
    var surfaceScale16_16 = baseline.scale16_16;
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
      final double? nativeWindowScale = window.backingScaleFactor;
      nativeWindowScale16_16 = nativeWindowScale == null
          ? 0
          : TerminalRasterBufferV1.scaleToFixed(nativeWindowScale);
      surfaceScale16_16 = snapshot.scale16_16;
      scaleSynchronized =
          nativeWindowScale16_16 > 0 &&
          surfaceScale16_16 == nativeWindowScale16_16;
      if (sgrStripped &&
          styled &&
          wrappedRows >= 2 &&
          promptBottom &&
          newestFrame &&
          frameBounded &&
          scaleSynchronized &&
          systemFont &&
          terminfo &&
          modeKey &&
          textInput &&
          inputMatrix &&
          decrqss &&
          queryReports &&
          synchronizedOutput &&
          kittyGraphics &&
          searchOverlay &&
          p3Color &&
          cellGlyphs &&
          focus &&
          mouse &&
          selection &&
          semanticPointer &&
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
          'TERMINAL_DISPLAY_SCALE_TEST '
          'window_scale_16_16=$nativeWindowScale16_16 '
          'surface_scale_16_16=$surfaceScale16_16 '
          'synchronized=$scaleSynchronized',
        );
        stdout.writeln(
          'TERMINAL_DISPLAY_TEST sgr_stripped=$sgrStripped styled=$styled '
          'wrapped_rows=$wrappedRows prompt_bottom=$promptBottom '
          'metal_default=true newest_frame=$newestFrame '
          'frame_bounded=$frameBounded system_font=$systemFont '
          'mode_key=$modeKey text_input=$textInput '
          'input_matrix=$inputMatrix decrqss=$decrqss '
          'query_reports=$queryReports synchronized_output=$synchronizedOutput '
          'kitty_graphics=$kittyGraphics '
          'search_overlay=$searchOverlay p3_color=$p3Color '
          'cell_glyphs=$cellGlyphs '
          'focus=$focus mouse=$mouse '
          'selection=$selection '
          'semantic_pointer=$semanticPointer '
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
      'frame_bounded=$frameBounded scale_synchronized=$scaleSynchronized '
      'window_scale_16_16=$nativeWindowScale16_16 '
      'surface_scale_16_16=$surfaceScale16_16 system_font=$systemFont '
      'mode_key=$modeKey text_input=$textInput '
      'input_matrix=$inputMatrix decrqss=$decrqss '
      'query_reports=$queryReports synchronized_output=$synchronizedOutput '
      'kitty_graphics=$kittyGraphics '
      'search_overlay=$searchOverlay p3_color=$p3Color '
      'cell_glyphs=$cellGlyphs '
      'focus=$focus mouse=$mouse '
      'selection=$selection '
      'semantic_pointer=$semanticPointer '
      'close_scroll=$closeScroll '
      'scroll=$scroll hyperlink=$hyperlink window_title=$windowTitle '
      'cursor_color=$cursorColor '
      'accessibility=$accessibility '
      'font_size=${baseline.fontPointSize}',
    );
  }

  static Future<bool> _exerciseSyntheticCellGlyphs(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
  ) async {
    const List<int> acceptedScalars = <int>[0x2500, 0x2588, 0x28ff, 0xe0b0];
    const int adjacentUnsupported = 0xe0c0;
    final TerminalLiveMetalSurfaceSnapshot before = surface.snapshot();
    pane.insertText(
      r"printf '\r\n__DT_CELL_GLYPH_START__A\342\224\200\342\226\210\342\243\277\356\202\260\356\203\200Z__DT_CELL_GLYPH_END__\r\n'",
    );
    await pane.submit();

    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      final Map<int, _TerminalAsciiPosition> positions =
          <int, _TerminalAsciiPosition>{};
      for (final int scalar in <int>[...acceptedScalars, adjacentUnsupported]) {
        final _TerminalAsciiPosition? position = _findScalar(screen, scalar);
        if (position != null) positions[scalar] = position;
      }
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (positions.length == acceptedScalars.length + 1 &&
          snapshot.acceptedFrameCount > before.acceptedFrameCount &&
          snapshot.lastAcceptedModelRevision ==
              snapshot.lastAppliedDamageGeneration) {
        final double scale = surface.atlas.scale;
        final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
        final int thickness = math.max(
          1,
          (metrics.underlineThickness * scale).round(),
        );
        var exactEntries = true;
        final Set<TerminalCellGlyphFamily> families =
            <TerminalCellGlyphFamily>{};
        for (final int scalar in acceptedScalars) {
          final _TerminalAsciiPosition position = positions[scalar]!;
          final int flags = screen.widthFlagsAt(position.row, position.column);
          final int left = (position.column * metrics.cellWidth * scale)
              .round();
          final int right = ((position.column + 1) * metrics.cellWidth * scale)
              .round();
          final int top = (position.row * metrics.cellHeight * scale).round();
          final int bottom = ((position.row + 1) * metrics.cellHeight * scale)
              .round();
          final int lineThickness = thickness.clamp(
            1,
            math.min(right - left, bottom - top),
          );
          final TerminalCellGlyphRasterRequest request =
              TerminalCellGlyphRasterRequest(
                scalar: scalar,
                cellWidth: right - left,
                cellHeight: bottom - top,
                lineThickness: lineThickness,
              );
          final TerminalGlyphAtlasEntry? entry = surface.atlas.lookupCellGlyph(
            TerminalCellGlyphAtlasKey.fromRequest(
              catalogGeneration: surface.atlas.catalogGeneration,
              scale16_16: surface.atlas.scale16_16,
              request: request,
            ),
          );
          exactEntries =
              exactEntries &&
              flags & TerminalCellFlags.widthMask == TerminalCellFlags.narrow &&
              flags & TerminalCellFlags.grapheme == 0 &&
              entry != null &&
              entry.isCellGlyph &&
              entry.width == right - left &&
              entry.height == bottom - top;
          families.add(TerminalCellGlyphClassifier.classify(scalar)!.family);
        }
        final _TerminalAsciiPosition fallback = positions[adjacentUnsupported]!;
        final int fallbackFlags = screen.widthFlagsAt(
          fallback.row,
          fallback.column,
        );
        final bool fontFallback =
            !TerminalCellGlyphClassifier.supports(adjacentUnsupported) &&
            fallbackFlags & TerminalCellFlags.widthMask ==
                TerminalCellFlags.narrow &&
            fallbackFlags & TerminalCellFlags.grapheme == 0;
        if (exactEntries &&
            families.length == TerminalCellGlyphFamily.values.length &&
            fontFallback &&
            surface.atlas.cellGlyphEntryCount >= acceptedScalars.length) {
          stdout.writeln(
            'TERMINAL_CELL_GLYPH_TEST box=true block=true braille=true '
            'powerline=true accepted=4 exact_cells=true '
            'font_fallback=true metal=true bounded=true',
          );
          return true;
        }
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before presenting synthetic cell glyphs',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'display-test did not publish accepted synthetic cells and adjacent '
      'font fallback through a current Metal frame',
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
    String fallbackWindowTitle,
  ) async {
    const String nativeTitle = '__DT_NATIVE_TITLE__';
    const String temporaryTitle = '__DT_TEMP_TITLE__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    pane.insertText(
      r"printf '\033]2;__DT_NATIVE_TITLE__\007\033]7;file://localhost/private/tmp\007'",
    );
    await pane.submit();
    await _waitForWindowPresentation(
      session,
      window,
      expectedMetadata: nativeTitle,
      expectedNative: nativeTitle,
      expectedRepresentedFilePath: '/private/tmp',
    );

    pane.insertText(r"printf '\033[22;2t\033]2;__DT_TEMP_TITLE__\007'");
    await pane.submit();
    await _waitForWindowPresentation(
      session,
      window,
      expectedMetadata: temporaryTitle,
      expectedNative: temporaryTitle,
      expectedRepresentedFilePath: '/private/tmp',
    );

    pane.insertText(r"printf '\033[23;2t'");
    await pane.submit();
    await _waitForWindowPresentation(
      session,
      window,
      expectedMetadata: nativeTitle,
      expectedNative: nativeTitle,
      expectedRepresentedFilePath: '/private/tmp',
    );

    pane.insertText(r"printf '\033c'");
    await pane.submit();
    await _waitForWindowPresentation(
      session,
      window,
      expectedMetadata: null,
      expectedNative: fallbackWindowTitle,
      expectedRepresentedFilePath: null,
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    stdout.writeln(
      'TERMINAL_WINDOW_TITLE_TEST metadata=true native=true stack=true '
      'reset=true fallback=true proxy=true',
    );
    return true;
  }

  static Future<void> _waitForWindowPresentation(
    TerminalSession session,
    Window window, {
    required String? expectedMetadata,
    required String expectedNative,
    required String? expectedRepresentedFilePath,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (session.terminalScreenSet.metadata.windowTitle == expectedMetadata &&
          window.title == expectedNative &&
          window.representedFilePath == expectedRepresentedFilePath) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before synchronizing the window title',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'display-test did not synchronize metadata title $expectedMetadata to '
      'native title $expectedNative and represented path '
      '$expectedRepresentedFilePath',
    );
  }

  static Rect _appKitWindowFrame(TerminalWindowFrame frame) =>
      Rect.fromLTWH(frame.left, frame.top, frame.width, frame.height);

  static TerminalWindowFrame _terminalWindowFrame(Rect frame) =>
      TerminalWindowFrame(
        left: frame.left,
        top: frame.top,
        width: frame.width,
        height: frame.height,
      );

  static TerminalScreenPlacement _terminalScreenPlacement(
    AppKitScreen screen,
  ) => TerminalScreenPlacement(
    displayId: screen.displayId,
    frame: _terminalWindowFrame(screen.frame),
    visibleFrame: _terminalWindowFrame(screen.visibleFrame),
  );

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
      'unicode_hex=true repeat=true option_word_navigation=true exact=true',
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

  static Future<bool> _exerciseSemanticPointerInput(
    AppKitApplication application,
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
    Window window,
    _TerminalMouseProductObservation mouseObservation,
    _TerminalSelectionProductOwner owner,
  ) async {
    final TerminalFontCatalogMetrics metrics = surface.fontMetrics;
    final int initialBeginCount = owner.promptClickBeginCount;
    final int initialMoveCount = owner.promptClickMoveCount;
    final int initialPromptBytes = owner.promptClickInputBytes;

    void inject(
      AppKitMouseEventKind kind, {
      required int row,
      required int column,
      int clickCount = 1,
      int modifiers = 0,
    }) {
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
    }

    Future<void> waitFor(
      bool Function() predicate,
      String failure, {
      Duration timeout = const Duration(seconds: 3),
    }) async {
      final Stopwatch deadline = Stopwatch()..start();
      while (deadline.elapsed < timeout && !predicate()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _expectLifecycle(predicate(), failure);
    }

    Future<void> injectSelection(
      AppKitMouseEventKind kind, {
      required int row,
      required int column,
      int clickCount = 1,
      int modifiers = 0,
    }) async {
      final int generation = owner.gesture.snapshot.generation;
      inject(
        kind,
        row: row,
        column: column,
        clickCount: clickCount,
        modifiers: modifiers,
      );
      await _waitForSelectionGeneration(owner, generation + 1);
    }

    Future<bool> exerciseOptionStage({
      required bool applicationCursor,
      required int expectedMovements,
      required String expectedHex,
      required String resultMarker,
    }) async {
      final String inputKind = applicationCursor ? 'APP' : 'CSI';
      final String input = '__DT_OPT_${inputKind}_INPUT__';
      const String prompt = 'P>';
      final String modeSequence = applicationCursor ? '\\033[?1h' : '\\033[?1l';
      final int expectedBytes = expectedMovements * 3;
      pane.insertText(
        "stty raw -echo; printf '\\033[2J\\033[H$modeSequence"
        "\\033]133;A\\a$prompt\\033]133;B\\a'; "
        "printf '__DT_OPT_%s_INPUT__' '$inputKind'; "
        "bytes=\$(/bin/dd bs=1 count=$expectedBytes 2>/dev/null | "
        "/usr/bin/od -An -tx1 | /usr/bin/tr -d ' \\n'); "
        "printf '\\033[?1l\\033]133;D\\a'; stty sane; "
        "printf '\\r\\n${resultMarker}_%s__\\r\\n' \"\$bytes\"",
      );
      await pane.submit();
      await _waitForAsciiMarker(session, input);
      final TerminalScreen screen = session.terminalScreenSet.activeScreen;
      final _TerminalAsciiPosition inputPosition = _findAscii(screen, input)!;
      _expectLifecycle(
        session.terminalScreenSet.semanticPrompt.shellState ==
                TerminalSemanticShellState.input &&
            session.keyboardModes.applicationCursorKeys == applicationCursor,
        'Option-click fixture did not publish its OSC 133/mode state',
      );

      await injectSelection(
        AppKitMouseEventKind.down,
        row: inputPosition.row,
        column: inputPosition.column,
      );
      await injectSelection(
        AppKitMouseEventKind.up,
        row: inputPosition.row,
        column: inputPosition.column,
      );
      await waitFor(
        () => surface.snapshot().selectionCellCount == 1,
        'Option-click fixture did not publish its pre-existing Metal selection',
      );
      final int selectionGeneration = owner.gesture.snapshot.generation;
      final int beginCount = owner.promptClickBeginCount;
      final int acceptedFrames = surface.snapshot().acceptedFrameCount;
      final int targetInputOffset = input.length - expectedMovements;
      inject(
        AppKitMouseEventKind.down,
        row: inputPosition.row,
        column: inputPosition.column + targetInputOffset,
        modifiers: ModifierKeys.optionBit,
      );
      await waitFor(
        () =>
            owner.promptClickBeginCount == beginCount + 1 &&
            owner.gesture.snapshot.generation == selectionGeneration + 1,
        'native Option down did not exclusively clear local selection',
      );
      await waitFor(() {
        final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
        return snapshot.acceptedFrameCount > acceptedFrames &&
            snapshot.selectionCellCount == 0 &&
            snapshot.selectionSpanCount == 0;
      }, 'native Option down did not clear the Metal selection projection');
      final int moveCount = owner.promptClickMoveCount;
      inject(
        AppKitMouseEventKind.up,
        row: inputPosition.row,
        column: inputPosition.column + targetInputOffset,
        modifiers: ModifierKeys.optionBit,
      );
      await waitFor(
        () => owner.promptClickMoveCount == moveCount + 1,
        'native Option up did not emit one accepted prompt movement',
      );
      await _waitForAsciiMarker(session, '${resultMarker}_${expectedHex}__');
      await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
      return !owner.localGestures.promptClick.isActive &&
          !session.keyboardModes.applicationCursorKeys;
    }

    final bool normalCursor = await exerciseOptionStage(
      applicationCursor: false,
      expectedMovements: 4,
      expectedHex: '1b5b441b5b441b5b441b5b44',
      resultMarker: '__DT_OPTION_NORMAL',
    );
    final bool applicationCursor = await exerciseOptionStage(
      applicationCursor: true,
      expectedMovements: 2,
      expectedHex: '1b4f441b4f44',
      resultMarker: '__DT_OPTION_APPLICATION',
    );

    const String promptOne = '__DT_SEM_PROMPT_ONE__';
    const String inputOne = '__DT_SEM_INPUT_ONE__';
    const String outputOne = '__DT_SEM_OUTPUT_ONE__';
    const String promptTwo = '__DT_SEM_PROMPT_TWO__';
    const String inputTwo = '__DT_SEM_INPUT_TWO__';
    const String outputTwo = '__DT_SEM_OUTPUT_TWO__';
    pane.insertText(
      "printf '\\033[2J\\033[H\\033]133;A\\a'; "
      "printf '__DT_SEM_%s_ONE__' 'PROMPT'; printf '\\033]133;B\\a'; "
      "printf '__DT_SEM_%s_ONE__' 'INPUT'; printf '\\033]133;C\\a'; "
      "printf '__DT_SEM_%s_ONE__' 'OUTPUT'; "
      "printf '\\033]133;D\\a\\r\\n\\033]133;A\\a'; "
      "printf '__DT_SEM_%s_TWO__' 'PROMPT'; printf '\\033]133;B\\a'; "
      "printf '__DT_SEM_%s_TWO__' 'INPUT'; printf '\\033]133;C\\a'; "
      "printf '__DT_SEM_%s_TWO__' 'OUTPUT'; "
      "printf '\\033]133;D\\a\\r\\n'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, outputTwo);
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalScreen semanticScreen =
        session.terminalScreenSet.activeScreen;
    final _TerminalAsciiPosition promptPosition = _findAscii(
      semanticScreen,
      promptOne,
    )!;
    final _TerminalAsciiPosition inputPosition = _findAscii(
      semanticScreen,
      inputOne,
    )!;
    final _TerminalAsciiPosition outputPosition = _findAscii(
      semanticScreen,
      outputOne,
    )!;
    final _TerminalAsciiPosition outputTwoPosition = _findAscii(
      semanticScreen,
      outputTwo,
    )!;

    Future<bool> exactTriple(
      _TerminalAsciiPosition position,
      String expected, {
      int modifiers = 0,
      TerminalSelectionUnit unit = TerminalSelectionUnit.logicalLine,
    }) async {
      await injectSelection(
        AppKitMouseEventKind.down,
        row: position.row,
        column: position.column,
        clickCount: 3,
        modifiers: modifiers,
      );
      await injectSelection(
        AppKitMouseEventKind.up,
        row: position.row,
        column: position.column,
        clickCount: 3,
        modifiers: modifiers,
      );
      final TerminalSelectionGestureSnapshot snapshot = owner.gesture.snapshot;
      return snapshot.unit == unit && owner.selectedText()?.text == expected;
    }

    final bool semanticPrompt = await exactTriple(promptPosition, promptOne);
    final bool semanticInput = await exactTriple(inputPosition, inputOne);
    final bool semanticOutput = await exactTriple(outputPosition, outputOne);
    final bool controlOutput = await exactTriple(
      outputPosition,
      outputOne,
      modifiers: ModifierKeys.controlBit,
      unit: TerminalSelectionUnit.semanticOutput,
    );
    final bool commandOutput = await exactTriple(
      outputTwoPosition,
      outputTwo,
      modifiers: ModifierKeys.commandBit,
      unit: TerminalSelectionUnit.semanticOutput,
    );

    final int semanticReports = mouseObservation.terminalReportCount;
    final int metalFrames = surface.snapshot().acceptedFrameCount;
    await injectSelection(
      AppKitMouseEventKind.down,
      row: outputPosition.row,
      column: outputPosition.column,
      clickCount: 3,
      modifiers: ModifierKeys.controlBit,
    );
    await injectSelection(
      AppKitMouseEventKind.dragged,
      row: outputTwoPosition.row,
      column: outputTwoPosition.column,
      clickCount: 3,
      modifiers: ModifierKeys.controlBit,
    );
    await injectSelection(
      AppKitMouseEventKind.up,
      row: outputTwoPosition.row,
      column: outputTwoPosition.column,
      clickCount: 3,
      modifiers: ModifierKeys.controlBit,
    );
    final TerminalSelectionText? combined = owner.selectedText();
    final bool outputDrag =
        owner.gesture.snapshot.unit == TerminalSelectionUnit.semanticOutput &&
        combined != null &&
        combined.text.startsWith(outputOne) &&
        combined.text.endsWith(outputTwo) &&
        combined.text.contains(promptTwo) &&
        combined.text.contains(inputTwo);
    await waitFor(
      () {
        final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
        return snapshot.acceptedFrameCount > metalFrames &&
            snapshot.selectionSpanCount > 0 &&
            snapshot.selectionCellCount >= outputOne.length + outputTwo.length;
      },
      'semantic output drag did not reach the live Metal selection projection',
    );
    final bool metal = surface.snapshot().selectionCellCount > 0;

    const String reportPrompt = 'P>';
    const String reportInput = '__DT_OPT_REPORT_INPUT__';
    pane.insertText(
      "stty raw -echo; printf '\\033[2J\\033[H\\033[?9h"
      "\\033]133;A\\a$reportPrompt\\033]133;B\\a'; "
      "printf '__DT_OPT_%s_INPUT__' 'REPORT'; "
      "bytes=\$(/bin/dd bs=1 count=6 2>/dev/null | /usr/bin/od -An -tx1 | "
      "/usr/bin/tr -d ' \\n'); printf '\\033[?9l\\033]133;D\\a'; "
      "stty sane; printf '\\r\\n__DT_OPTION_REPORT_%s__\\r\\n' \"\$bytes\"",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, reportInput);
    final _TerminalAsciiPosition reportPosition = _findAscii(
      session.terminalScreenSet.activeScreen,
      reportInput,
    )!;
    await waitFor(
      () =>
          session.terminalScreenSet.mouseModes.tracking ==
          TerminalMouseTrackingMode.x10,
      'mouse-report exclusion fixture did not enable X10 tracking',
    );
    final int initialReports = mouseObservation.terminalReportCount;
    final int initialLocals = mouseObservation.localSelectionCount;
    final int reportBeginCount = owner.promptClickBeginCount;
    final int reportMoveCount = owner.promptClickMoveCount;
    final int targetColumn = reportPosition.column + 2;
    final List<int> expectedReport = <int>[
      0x1b,
      0x5b,
      0x4d,
      0x20 + 8,
      0x20 + targetColumn + 1,
      0x20 + reportPosition.row + 1,
    ];
    final String expectedReportHex = expectedReport
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    inject(
      AppKitMouseEventKind.down,
      row: reportPosition.row,
      column: targetColumn,
      modifiers: ModifierKeys.optionBit,
    );
    await waitFor(
      () => mouseObservation.terminalReportCount == initialReports + 1,
      'active mouse reporting did not own the Option press',
    );
    await _waitForAsciiMarker(
      session,
      '__DT_OPTION_REPORT_${expectedReportHex}__',
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final bool mouseExclusive =
        mouseObservation.localSelectionCount == initialLocals &&
        owner.promptClickBeginCount == reportBeginCount &&
        owner.promptClickMoveCount == reportMoveCount &&
        !owner.localGestures.promptClick.isActive &&
        session.terminalScreenSet.mouseModes == const TerminalMouseModes();

    final int moveDelta = owner.promptClickMoveCount - initialMoveCount;
    final int inputByteDelta = owner.promptClickInputBytes - initialPromptBytes;
    final bool exactBytes =
        owner.promptClickBeginCount - initialBeginCount == 2 &&
        moveDelta == 2 &&
        inputByteDelta == 18;
    final bool copyText =
        semanticPrompt &&
        semanticInput &&
        semanticOutput &&
        controlOutput &&
        commandOutput &&
        outputDrag;
    final bool cleanup =
        !owner.localGestures.promptClick.isActive &&
        !owner.gesture.snapshot.isActive;
    _expectLifecycle(
      normalCursor &&
          applicationCursor &&
          exactBytes &&
          copyText &&
          owner.logicalLineObserved &&
          owner.semanticOutputObserved &&
          metal &&
          mouseObservation.terminalReportCount == semanticReports + 1 &&
          mouseExclusive &&
          cleanup,
      'semantic pointer product acceptance did not settle',
    );
    stdout.writeln(
      'TERMINAL_SEMANTIC_POINTER_TEST option=true csi=true ss3=true '
      'exact_bytes=true prompt=true input=true output=true '
      'output_drag=true copy=true metal=true mouse_exclusive=true '
      'cleanup=true writes=$moveDelta bytes=$inputByteDelta',
    );
    return true;
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

    // Selection publication is normally coalesced through the shared pane
    // scheduler. Earlier acceptance stages can leave a later frame retry at
    // the head of that queue, so advance this surface once before inspecting
    // its native accessibility snapshot. This keeps the product scheduling
    // path intact while making the acceptance barrier depend on completed
    // publication instead of timer ordering.
    surface.processPending();

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
      'TERMINAL_SCROLL_TEST protocol=${application.eventProtocolVersion} '
      'precise=true momentum=true '
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

  static void _injectScreenEventForTesting(
    AppKitApplication application,
    Window window,
    AppKitScreen screen, {
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      7,
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      true,
      screen.displayId,
      screen.frame.left,
      screen.frame.top,
      screen.frame.width,
      screen.frame.height,
      screen.visibleFrame.left,
      screen.visibleFrame.top,
      screen.visibleFrame.width,
      screen.visibleFrame.height,
    ]);
  }

  static void _injectApplicationReopenEventForTesting(
    AppKitApplication application, {
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      31,
      0,
      0,
      monotonicNanoseconds,
      0,
      false,
    ]);
  }

  static void _injectApplicationPowerStateEventForTesting(
    AppKitApplication application, {
    required AppKitApplicationPowerState state,
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      35,
      0,
      0,
      monotonicNanoseconds,
      0,
      switch (state) {
        AppKitApplicationPowerState.willSleep => 0,
        AppKitApplicationPowerState.didWake => 1,
      },
    ]);
  }

  static void _injectApplicationScreenSetEventForTesting(
    AppKitApplication application, {
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      36,
      0,
      0,
      monotonicNanoseconds,
      0,
    ]);
  }

  static void _injectApplicationMemoryPressureEventForTesting(
    AppKitApplication application, {
    required AppKitMemoryPressureLevel level,
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      37,
      0,
      0,
      monotonicNanoseconds,
      0,
      switch (level) {
        AppKitMemoryPressureLevel.normal => 0,
        AppKitMemoryPressureLevel.warning => 1,
        AppKitMemoryPressureLevel.critical => 2,
      },
    ]);
  }

  static void _injectApplicationAppearanceEventForTesting(
    AppKitApplication application, {
    required bool isDark,
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      33,
      0,
      0,
      monotonicNanoseconds,
      0,
      isDark,
    ]);
  }

  static void _injectApplicationAccessibilityDisplayPreferencesEventForTesting(
    AppKitApplication application, {
    required bool reduceMotion,
    required bool increaseContrast,
    required bool differentiateWithoutColor,
    required int monotonicNanoseconds,
  }) {
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      34,
      0,
      0,
      monotonicNanoseconds,
      0,
      reduceMotion,
      increaseContrast,
      differentiateWithoutColor,
    ]);
  }

  static void _injectWindowGeometryEventsForTesting(
    AppKitApplication application,
    Window window, {
    required Rect frame,
    required double contentWidth,
    required double contentHeight,
    required int monotonicNanoseconds,
  }) {
    final int handle = appkit_testing.nativeWindowHandleForTesting(window);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      9,
      handle,
      handle >> 32,
      monotonicNanoseconds,
      0,
      frame.left,
      frame.top,
      frame.width,
      frame.height,
    ]);
    appkit_testing.injectRawAppKitEventForTesting(application, <Object?>[
      application.eventProtocolVersion,
      2,
      handle,
      handle >> 32,
      monotonicNanoseconds + 1,
      0,
      contentWidth,
      contentHeight,
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
    while ((presenter.renderedText ?? '').contains(
          'Focus Next Pane  — Unavailable',
        ) &&
        openDeadline.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final Window? paletteWindow = presenter.activeWindow;
    _expectLifecycle(
      presenter.isOpen &&
          paletteWindow != null &&
          application.debugLiveObjectCount == baselineHandles + 2 &&
          (presenter.renderedText ?? '').contains('Command Palette') &&
          (presenter.renderedText ?? '').contains('Focus Next Pane') &&
          !(presenter.renderedText ?? '').contains(
            'Focus Next Pane  — Unavailable',
          ),
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
    String marker, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < timeout) {
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

  static Future<void> _waitForAsciiMarkerPresented(
    _TerminalHierarchyProductPane owner,
    String marker, {
    required Duration timeout,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    int? markerDamageGeneration;
    int? markerAcceptedFrameCount;
    while (deadline.elapsed < timeout) {
      final TerminalScreen screen =
          owner.session.terminalScreenSet.activeScreen;
      final TerminalLiveMetalSurfaceSnapshot snapshot = owner.surface
          .snapshot();
      if (markerDamageGeneration == null &&
          _findAscii(screen, marker) != null) {
        markerDamageGeneration = snapshot.lastAppliedDamageGeneration;
        markerAcceptedFrameCount = snapshot.acceptedFrameCount;
        screen.requestFullSnapshot();
        owner.notifyScreenChanged();
      }
      if (markerDamageGeneration != null &&
          snapshot.lastAppliedDamageGeneration > markerDamageGeneration &&
          snapshot.acceptedFrameCount > markerAcceptedFrameCount!) {
        return;
      }
      _expectLifecycle(
        owner.session.isLive,
        'terminal session exited before presenting marker $marker',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw TimeoutException('terminal did not present marker $marker');
  }

  static Future<TerminalPaneProcessSnapshot> _waitForPaneProcessDisposition(
    TerminalPane pane,
    TerminalPaneProcessDisposition expected,
  ) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final TerminalPaneProcessSnapshot snapshot = pane.processSnapshot();
      if (snapshot.disposition == expected) return snapshot;
      if (expected != TerminalPaneProcessDisposition.nonLive) {
        _expectLifecycle(
          pane.isLive,
          'pane ${pane.id} exited before process disposition ${expected.name}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'pane ${pane.id} did not reach process disposition ${expected.name}',
    );
  }

  static Future<void> _waitForSemanticShellState(
    TerminalSession session,
    TerminalSemanticShellState expected,
  ) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (session.terminalScreenSet.semanticPrompt.shellState == expected) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'terminal session exited before semantic state ${expected.name}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'terminal session did not reach semantic state ${expected.name}',
    );
  }

  static int _retainedSemanticRowFlags(TerminalScreenSet screens) {
    var flags = 0;
    for (var row = 0; row < screens.scrollback.length; row++) {
      flags |= screens.scrollback.rowFlagsAt(row);
    }
    for (var row = 0; row < screens.primary.rows; row++) {
      flags |= screens.primary.rowFlagsAt(row);
    }
    return flags &
        (TerminalRowFlags.prompt |
            TerminalRowFlags.command |
            TerminalRowFlags.output);
  }

  static Future<void> _waitForSessionMetadata(
    TerminalSession session, {
    required String expectedTitle,
    required Uri expectedWorkingDirectory,
  }) async {
    final Stopwatch deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final metadata = session.terminalScreenSet.metadata;
      if (metadata.windowTitle == expectedTitle &&
          metadata.workingDirectory == expectedWorkingDirectory) {
        return;
      }
      _expectLifecycle(
        session.isLive,
        'terminal session exited before publishing title/cwd metadata',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'terminal session did not publish title $expectedTitle and cwd '
      '$expectedWorkingDirectory',
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
    await _waitForAsciiMarker(session, expectedMarker);
    return _exerciseKittyKeyboardInput(session, pane, keyEventRouter);
  }

  static Future<bool> _exerciseKittyKeyboardInput(
    TerminalSession session,
    TerminalPane pane,
    TerminalKeyEventRouter keyEventRouter,
  ) async {
    const String alternateReady = '__DT_KITTY_ALT_READY__';
    const String primaryReady = '__DT_KITTY_PRIMARY_READY__';
    const String expectedMarker =
        '__DT_KITTY_1b5b3f3175_1b5b3f313075_1b5b3130303b353a3375__';
    pane.insertText(
      "stty raw -echo; printf '\\033[=1u\\033[?u'; "
      "primary=\$(dd bs=1 count=5 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?1049h\\033[=10u\\033[?u'; "
      "alternate=\$(dd bs=1 count=6 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "printf '$alternateReady'; "
      "key=\$(dd bs=1 count=10 2>/dev/null | od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[?1049l$primaryReady'; "
      "dd bs=1 count=1 >/dev/null 2>&1; printf '\\033[=0u'; stty sane; "
      "printf '\\r\\n__DT_KITTY_%s_%s_%s__\\r\\n' "
      '"\$primary" "\$alternate" "\$key"',
    );
    await pane.submit();

    final Stopwatch alternateDeadline = Stopwatch()..start();
    var alternateIsolated = false;
    while (alternateDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalScreenSet screens = session.terminalScreenSet;
      alternateIsolated =
          screens.usingAlternate &&
          screens.keyboardModes.kittyKeyboardFlags == 10 &&
          _findAscii(screens.activeScreen, alternateReady) != null;
      if (alternateIsolated) {
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before alternate Kitty mode was ready',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      alternateIsolated,
      'display-test did not isolate alternate Kitty keyboard flags',
    );

    final TerminalKeyRouteResult release = keyEventRouter.handleKeyEvent(
      const AppKitKeyEvent(
        windowHandle: 1,
        monotonicMicros: 2,
        kind: AppKitKeyEventKind.up,
        keyCode: 2,
        modifiers: ModifierKeys(ModifierKeys.controlBit),
        isRepeat: false,
        characters: '\u0004',
        charactersIgnoringModifiers: 'd',
      ),
      pane,
    );
    _expectLifecycle(
      release.disposition == TerminalKeyRouteDisposition.encoded &&
          release.encodedByteCount == 10,
      'display-test Kitty release was not encoded exactly once',
    );

    final Stopwatch primaryDeadline = Stopwatch()..start();
    var primaryRestored = false;
    while (primaryDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalScreenSet screens = session.terminalScreenSet;
      primaryRestored =
          !screens.usingAlternate &&
          screens.keyboardModes.kittyKeyboardFlags == 1 &&
          _findAscii(screens.activeScreen, primaryReady) != null;
      if (primaryRestored) {
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before primary Kitty mode was restored',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      primaryRestored,
      'display-test did not restore independent primary Kitty flags',
    );

    pane.insertText('x');
    await _waitForAsciiMarker(session, expectedMarker);
    final TerminalScreenSet screens = session.terminalScreenSet;
    _expectLifecycle(
      !screens.usingAlternate && screens.keyboardModes.kittyKeyboardFlags == 0,
      'display-test Kitty keyboard state did not reset after exact capture',
    );
    stdout.writeln(
      'TERMINAL_KITTY_KEYBOARD_TEST primary_query=true '
      'alternate_query=true screens=true release=true legacy=true '
      'exact=true bytes=21',
    );
    return true;
  }

  static Future<bool> _exerciseSynchronizedOutput(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
  ) async {
    const String partialMarker = '__DT_SYNC_PARTIAL__';
    const String finalMarker = '__DT_SYNC_FINAL_1b5b3f323032363b312479__';
    const String timeoutPartialMarker = '__DT_SYNC_TIMEOUT_PARTIAL__';
    const String timeoutLegacyMarker =
        '__DT_SYNC_TIMEOUT_LEGACY_1b5b3f323032363b312479_'
        '1b5b3f323032363b322479__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    final TerminalLiveMetalSurfaceSnapshot beforeRelease = surface.snapshot();
    pane.insertText(
      "stty raw -echo; printf "
      "'\\033[?2026h\\033[?2026\$p\\033[2J\\033[H$partialMarker'; "
      "set_reply=\$(dd bs=1 count=11 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); sleep 0.60; "
      "printf '\\033[H__DT_SYNC_FINAL_%s__\\033[K\\033[?2026l' "
      '"\$set_reply"; stty sane; sleep 0.80',
    );
    await pane.submit();

    TerminalLiveMetalSurfaceSnapshot? held;
    final Stopwatch holdDeadline = Stopwatch()..start();
    while (holdDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (screens.synchronizedOutputMode &&
          snapshot.synchronizedOutputHeld &&
          _findAscii(screens.activeScreen, partialMarker) != null) {
        held = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before synchronized output was held',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      held != null &&
          held.synchronizedOutputReleaseCount ==
              beforeRelease.synchronizedOutputReleaseCount &&
          held.synchronizedOutputTimeoutCount ==
              beforeRelease.synchronizedOutputTimeoutCount,
      'display-test did not enter synchronized output exactly once',
    );
    final TerminalLiveMetalSurfaceSnapshot heldSnapshot = held!;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final TerminalLiveMetalSurfaceSnapshot frozen = surface.snapshot();
    _expectLifecycle(
      session.terminalScreenSet.synchronizedOutputMode &&
          frozen.synchronizedOutputHeld &&
          frozen.acceptedFrameCount == heldSnapshot.acceptedFrameCount &&
          frozen.frameBuildCount == heldSnapshot.frameBuildCount &&
          frozen.pendingFrameCount <= 1,
      'synchronized output built or accepted an intermediate frame',
    );

    TerminalLiveMetalSurfaceSnapshot? released;
    final Stopwatch releaseDeadline = Stopwatch()..start();
    while (releaseDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (!screens.synchronizedOutputMode &&
          !snapshot.synchronizedOutputHeld &&
          snapshot.synchronizedOutputReleaseCount ==
              beforeRelease.synchronizedOutputReleaseCount + 1 &&
          snapshot.synchronizedOutputTimeoutCount ==
              beforeRelease.synchronizedOutputTimeoutCount &&
          snapshot.acceptedFrameCount == heldSnapshot.acceptedFrameCount + 1 &&
          _findAscii(screens.activeScreen, finalMarker) != null) {
        released = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before synchronized output released',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      released != null &&
          released.pendingFrameCount <= 1 &&
          released.liveAtlasPinCount <= 3,
      'synchronized output did not publish one bounded newest frame',
    );

    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalLiveMetalSurfaceSnapshot beforeTimeout = surface.snapshot();
    pane.insertText(
      "stty raw -echo; printf "
      "'\\033[?2026h\\033[?2026\$p\\033[2J\\033[H$timeoutPartialMarker'; "
      "set_reply=\$(dd bs=1 count=11 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); sleep 1.35; "
      "printf '\\033[?2026\$p'; "
      "reset_reply=\$(dd bs=1 count=11 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033[H__DT_SYNC_TIMEOUT_LEGACY_%s_%s__\\033[K' "
      '"\$set_reply" "\$reset_reply"; stty sane; sleep 0.80',
    );
    await pane.submit();

    TerminalLiveMetalSurfaceSnapshot? timeoutHeld;
    final Stopwatch timeoutHoldDeadline = Stopwatch()..start();
    while (timeoutHoldDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (screens.synchronizedOutputMode &&
          snapshot.synchronizedOutputHeld &&
          _findAscii(screens.activeScreen, timeoutPartialMarker) != null) {
        timeoutHeld = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before timeout hold was observed',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      timeoutHeld != null,
      'display-test did not enter the abandoned synchronized-output hold',
    );
    final TerminalLiveMetalSurfaceSnapshot timeoutHeldSnapshot = timeoutHeld!;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final TerminalLiveMetalSurfaceSnapshot timeoutFrozen = surface.snapshot();
    _expectLifecycle(
      session.terminalScreenSet.synchronizedOutputMode &&
          timeoutFrozen.synchronizedOutputHeld &&
          timeoutFrozen.acceptedFrameCount ==
              timeoutHeldSnapshot.acceptedFrameCount &&
          timeoutFrozen.frameBuildCount ==
              timeoutHeldSnapshot.frameBuildCount &&
          timeoutFrozen.pendingFrameCount <= 1,
      'abandoned synchronized output presented before its deadline',
    );

    TerminalLiveMetalSurfaceSnapshot? timedOut;
    final Stopwatch timeoutDeadline = Stopwatch()..start();
    while (timeoutDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (!screens.synchronizedOutputMode &&
          !snapshot.synchronizedOutputHeld &&
          snapshot.synchronizedOutputReleaseCount ==
              beforeTimeout.synchronizedOutputReleaseCount + 1 &&
          snapshot.synchronizedOutputTimeoutCount ==
              beforeTimeout.synchronizedOutputTimeoutCount + 1 &&
          snapshot.acceptedFrameCount ==
              timeoutHeldSnapshot.acceptedFrameCount + 1 &&
          _findAscii(screens.activeScreen, timeoutPartialMarker) != null &&
          _findAscii(screens.activeScreen, timeoutLegacyMarker) == null) {
        timedOut = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before synchronized-output timeout recovery',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      timedOut != null &&
          timedOut.pendingFrameCount <= 1 &&
          timedOut.liveAtlasPinCount <= 3,
      'synchronized-output timeout did not release one bounded newest frame',
    );
    final TerminalLiveMetalSurfaceSnapshot timedOutSnapshot = timedOut!;

    TerminalLiveMetalSurfaceSnapshot? legacy;
    final Stopwatch legacyDeadline = Stopwatch()..start();
    while (legacyDeadline.elapsed < const Duration(seconds: 3)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (!screens.synchronizedOutputMode &&
          !snapshot.synchronizedOutputHeld &&
          snapshot.synchronizedOutputReleaseCount ==
              timedOutSnapshot.synchronizedOutputReleaseCount &&
          snapshot.synchronizedOutputTimeoutCount ==
              timedOutSnapshot.synchronizedOutputTimeoutCount &&
          snapshot.acceptedFrameCount > timedOutSnapshot.acceptedFrameCount &&
          snapshot.pendingFrameCount <= 1 &&
          snapshot.liveAtlasPinCount <= 3 &&
          _findAscii(screens.activeScreen, timeoutLegacyMarker) != null) {
        legacy = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before legacy presentation resumed',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      legacy != null,
      'display-test did not resume immediate legacy presentation after timeout',
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    stdout.writeln(
      'TERMINAL_SYNCHRONIZED_OUTPUT_TEST query_set=true query_reset=true '
      'hold=true intermediate_frames=0 release_frames=1 timeout=true '
      'timeout_frames=1 legacy=true bounded=true',
    );
    return true;
  }

  static Future<bool> _exerciseKittyGraphics(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
  ) async {
    const String queryMarker =
        '__DT_KITTY_GRAPHICS_QUERY_1b5f47693d39303b4f4b1b5c__';
    const String scrollMarker = '__DT_KITTY_GRAPHICS_SCROLL__';
    const String erasedMarker = '__DT_KITTY_GRAPHICS_ERASED__';
    const String deletedMarker = '__DT_KITTY_GRAPHICS_DELETED__';
    const String animationMarker = '__DT_KITTY_GRAPHICS_ANIMATION__';
    const String evictionMarker = '__DT_KITTY_GRAPHICS_EVICTION__';
    const String evictionDeletedMarker =
        '__DT_KITTY_GRAPHICS_EVICTION_DELETED__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    final TerminalLiveMetalSurfaceSnapshot baseline = surface.snapshot();
    pane.insertText(
      "stty raw -echo; printf '\\033[H'; "
      "printf '\\033_Ga=q,i=90,f=32,s=1,v=1;AQIDBA==\\033\\\\'; "
      "query=\$(dd bs=1 count=12 2>/dev/null | "
      "od -An -tx1 | tr -d ' \\n'); "
      "printf '\\033_Gi=91,q=2,f=32,s=1,v=1,m=1;AQID\\033\\\\'; "
      "printf '\\033_Gm=0,q=2;BA==\\033\\\\'; "
      "printf '\\033_Ga=p,i=91,p=1,c=1,r=1,C=1,z=-1,q=2\\033\\\\'; "
      "printf '\\033_Gi=92,q=2,f=100,m=1;"
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA\\033\\\\'; "
      "printf '\\033_Gm=0,q=2;"
      "DUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==\\033\\\\'; "
      "printf '\\033_Ga=p,i=92,p=2,c=1,r=1,C=1,z=1,q=2\\033\\\\'; "
      "printf '\\033_Gi=94,q=2,f=32,s=1,v=1;CQoL/w==\\033\\\\'; "
      "printf '\\033_Ga=p,i=94,p=3,c=1,r=1,C=1,"
      "z=-1073741825,q=2\\033\\\\'; "
      "stty sane; printf '\\r\\n__DT_KITTY_GRAPHICS_QUERY_%s__\\r\\n' "
      '"\$query"',
    );
    await pane.submit();
    await _waitForAsciiMarker(session, queryMarker);
    await session.kittyGraphicsController.waitForIdle();

    TerminalLiveMetalSurfaceSnapshot? rendered;
    final Stopwatch renderDeadline = Stopwatch()..start();
    while (renderDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      final TerminalScreenSet screens = session.terminalScreenSet;
      if (screens.primaryKittyImages.imageById(91) != null &&
          screens.primaryKittyImages.imageById(92) != null &&
          screens.primaryKittyImages.imageById(94) != null &&
          screens.primaryKittyImages.placementCount == 3 &&
          snapshot.kittyImageCount == 3 &&
          snapshot.kittyPlacementCount == 3 &&
          snapshot.kittyTileCount == 3 &&
          snapshot.kittyAtlasEntryCount >= 3 &&
          snapshot.acceptedFrameCount > baseline.acceptedFrameCount) {
        rendered = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited before Kitty graphics reached Metal',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      rendered != null &&
          rendered.pendingFrameCount <= 1 &&
          rendered.liveAtlasPinCount <= 3,
      'Kitty query/multipart placements did not reach one bounded Metal frame '
      '(images=${session.terminalScreenSet.primaryKittyImages.length}, '
      'placements='
      '${session.terminalScreenSet.primaryKittyImages.placementCount}, '
      'surface_images=${surface.snapshot().kittyImageCount}, '
      'surface_placements=${surface.snapshot().kittyPlacementCount}, '
      'surface_tiles=${surface.snapshot().kittyTileCount}, '
      'atlas_tiles=${surface.snapshot().kittyAtlasEntryCount}, '
      'accepted=${surface.snapshot().acceptedFrameCount}, '
      'baseline=${baseline.acceptedFrameCount})',
    );
    final int renderedFrameCount = rendered!.acceptedFrameCount;

    pane.insertText(
      "printf '\\033[999;1H\\033D'; "
      "printf '__DT_KITTY_GRAPHICS_%s__\\r\\n' 'SCROLL'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, scrollMarker);
    TerminalLiveMetalSurfaceSnapshot? scrolled;
    final Stopwatch scrollDeadline = Stopwatch()..start();
    while (scrollDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (session.terminalScreenSet.primaryKittyImages.placementCount == 3 &&
          session.terminalScreenSet
              .captureKittyImageViewport()
              .placements
              .isEmpty &&
          snapshot.kittyPlacementCount == 0 &&
          snapshot.acceptedFrameCount > renderedFrameCount) {
        scrolled = snapshot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      scrolled != null,
      'Kitty placements did not follow full-screen scroll into history',
    );
    final TerminalScreenSet screens = session.terminalScreenSet;
    var historyPlacementCount = 0;
    for (
      var offset = 1;
      offset <= 8 && offset <= screens.viewport.maximumOffset;
      offset++
    ) {
      screens.viewport.scrollByRows(1);
      historyPlacementCount = screens
          .captureKittyImageViewport()
          .placements
          .length;
      if (historyPlacementCount == 3) break;
    }
    surface.notifyViewportChanged();
    final Stopwatch historyDeadline = Stopwatch()..start();
    var historyVisible = false;
    while (historyDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (screens.captureKittyImageViewport().placements.length == 3 &&
          snapshot.kittyPlacementCount == 3 &&
          snapshot.acceptedFrameCount > scrolled!.acceptedFrameCount) {
        historyVisible = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      historyVisible,
      'Kitty history placements were not reprojected through Metal '
      '(offset=${screens.viewport.offset}, '
      'maximum=${screens.viewport.maximumOffset}, '
      'placements=$historyPlacementCount, '
      'surface=${surface.snapshot().kittyPlacementCount})',
    );
    screens.viewport.scrollToBottom();
    surface.notifyViewportChanged();

    final int acceptedBeforeErasePlacement =
        session.kittyGraphicsController.acceptedCommandCount;
    pane.insertText(
      "stty raw -echo; "
      "printf '\\033[10;1H\\033_Ga=T,i=93,f=32,s=1,v=1,c=1,r=1,"
      "C=1;BQYHCA==\\033\\\\'; "
      "dd bs=1 count=12 >/dev/null 2>&1; stty sane",
    );
    await pane.submit();
    final Stopwatch eraseReadyDeadline = Stopwatch()..start();
    var eraseReady = false;
    while (eraseReadyDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (session.kittyGraphicsController.acceptedCommandCount ==
              acceptedBeforeErasePlacement + 1 &&
          session.kittyGraphicsController.pendingJobCount == 0 &&
          screens.primaryKittyImages.imageById(93) != null &&
          screens.primaryKittyImages.placementCount == 4 &&
          snapshot.kittyPlacementCount == 1 &&
          snapshot.kittyTileCount == 1) {
        eraseReady = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final String placementPositions = screens.primaryKittyImages
        .placementSnapshot()
        .map((placement) {
          final TerminalViewportPosition? position = screens.viewport
              .screenCellPositionOf(
                TerminalScreenKind.primary,
                TerminalLogicalAnchor(
                  screenKind: TerminalScreenKind.primary,
                  logicalLineId: placement.logicalLineId,
                  logicalLineEpoch: placement.logicalLineEpoch,
                  cellOffset: placement.logicalCellOffset,
                ),
              );
          return '${placement.imageId}:${position?.row}:${position?.column}';
        })
        .join(',');
    _expectLifecycle(
      eraseReady,
      'Kitty transmit-and-place did not become visible before erase '
      '(images=${screens.primaryKittyImages.length}, '
      'placements=${screens.primaryKittyImages.placementCount}, '
      'viewport=${screens.captureKittyImageViewport().placements.length}, '
      'surface=${surface.snapshot().kittyPlacementCount}, '
      'tiles=${surface.snapshot().kittyTileCount}, '
      'offset=${screens.viewport.offset}, positions=$placementPositions)',
    );

    final TerminalLiveMetalSurfaceSnapshot animationBaseline = surface
        .snapshot();
    final int acceptedBeforeAnimation =
        session.kittyGraphicsController.acceptedCommandCount;
    pane.insertText(
      "stty raw -echo; "
      "printf '\\033_Ga=f,i=93,f=32,s=1,v=1;AP8A/w==\\033\\\\'; "
      "dd bs=1 count=16 >/dev/null 2>&1; "
      "printf '\\033_Ga=a,i=93,r=1,z=40,c=1,s=3,v=1\\033\\\\'; "
      "sleep 1; stty sane; "
      "printf '\\r\\n__DT_KITTY_GRAPHICS_%s__\\r\\n' 'ANIMATION'",
    );
    await pane.submit();
    final Set<int> observedAnimationFrames = <int>{};
    TerminalLiveMetalSurfaceSnapshot? animated;
    final Stopwatch animationDeadline = Stopwatch()..start();
    while (animationDeadline.elapsed < const Duration(seconds: 5)) {
      final image = screens.primaryKittyImages.imageById(93);
      if (image != null) observedAnimationFrames.add(image.currentFrameNumber);
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (image?.frameCount == 2 &&
          session.kittyGraphicsController.acceptedCommandCount ==
              acceptedBeforeAnimation + 2 &&
          session.kittyGraphicsController.pendingJobCount == 0 &&
          screens.primaryKittyImages.placementCount == 4 &&
          observedAnimationFrames.length == 2 &&
          snapshot.kittyImageCount == 1 &&
          snapshot.kittyPlacementCount == 1 &&
          snapshot.kittyTileCount == 1 &&
          snapshot.kittyAtlasEntryCount >=
              animationBaseline.kittyAtlasEntryCount &&
          snapshot.kittyAtlasEntryCount <=
              animationBaseline.kittyAtlasEntryCount + 1 &&
          snapshot.acceptedFrameCount >=
              animationBaseline.acceptedFrameCount + 2 &&
          snapshot.pendingFrameCount <= 1 &&
          snapshot.liveAtlasPinCount <= 3) {
        animated = snapshot;
        break;
      }
      _expectLifecycle(
        session.isLive,
        'display-test zsh exited during Kitty animation acceptance',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _expectLifecycle(
      animated != null,
      'Kitty animation did not advance through bounded Metal frames '
      '(protocol_frames=${screens.primaryKittyImages.imageById(93)?.frameCount}, '
      'observed=$observedAnimationFrames, '
      'placements=${screens.primaryKittyImages.placementCount}, '
      'surface_images=${surface.snapshot().kittyImageCount}, '
      'surface_placements=${surface.snapshot().kittyPlacementCount}, '
      'surface_tiles=${surface.snapshot().kittyTileCount}, '
      'atlas_tiles=${surface.snapshot().kittyAtlasEntryCount}, '
      'accepted=${surface.snapshot().acceptedFrameCount}, '
      'baseline=${animationBaseline.acceptedFrameCount})',
    );
    await _waitForAsciiMarker(session, animationMarker);

    pane.insertText(
      "printf '\\033_Ga=a,i=93,s=1\\033\\\\'; "
      "printf '\\033[2J\\033[H'; "
      "printf '__DT_KITTY_GRAPHICS_%s__\\r\\n' 'ERASED'; sleep 1; "
      "printf '\\033_Ga=d,d=R,x=91,y=94,q=2\\033\\\\'; "
      "printf '__DT_KITTY_GRAPHICS_%s__\\r\\n' 'DELETED'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, erasedMarker);
    final Stopwatch erasedDeadline = Stopwatch()..start();
    var erased = false;
    while (erasedDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (screens.primaryKittyImages.imageById(93) == null &&
          screens.primaryKittyImages.length == 3 &&
          screens.primaryKittyImages.placementCount == 3 &&
          snapshot.kittyPlacementCount == 0) {
        erased = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(erased, 'ED 2 did not clear only the visible Kitty image');

    await _waitForAsciiMarker(session, deletedMarker);
    await session.kittyGraphicsController.waitForIdle();
    final Stopwatch deleteDeadline = Stopwatch()..start();
    var deleted = false;
    while (deleteDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (screens.primaryKittyImages.isEmpty &&
          snapshot.kittyImageCount == 0 &&
          snapshot.kittyPlacementCount == 0 &&
          snapshot.kittyTileCount == 0 &&
          snapshot.kittyAtlasEntryCount == 0 &&
          snapshot.pendingFrameCount <= 1 &&
          snapshot.liveAtlasPinCount <= 3) {
        deleted = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      deleted,
      'Kitty uppercase delete did not reclaim product image state '
      '(images=${screens.primaryKittyImages.length}, '
      'placements=${screens.primaryKittyImages.placementCount}, '
      'surface_images=${surface.snapshot().kittyImageCount}, '
      'surface_placements=${surface.snapshot().kittyPlacementCount}, '
      'surface_tiles=${surface.snapshot().kittyTileCount}, '
      'pending=${session.kittyGraphicsController.pendingJobCount}, '
      'accepted=${session.kittyGraphicsController.acceptedCommandCount})',
    );

    final int acceptedBeforeEviction =
        session.kittyGraphicsController.acceptedCommandCount;
    final int resourceEvictionsBefore =
        screens.primaryKittyImages.evictionCount;
    final int evictedBytesBefore = screens.primaryKittyImages.evictedBytes;
    pane.insertText(
      "stty raw -echo; i=100; while [ \$i -le 164 ]; do "
      "printf '\\033_Gi=%d,q=2,f=32,s=1,v=1;AQIDBA==\\033\\\\' \"\$i\"; "
      "sleep 0.02; i=\$((i+1)); done; stty sane; "
      "printf '\\r\\n__DT_KITTY_GRAPHICS_%s__\\r\\n' 'EVICTION'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, evictionMarker);
    await session.kittyGraphicsController.waitForIdle();
    TerminalLiveMetalSurfaceSnapshot? evicted;
    final Stopwatch evictionDeadline = Stopwatch()..start();
    while (evictionDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (session.kittyGraphicsController.acceptedCommandCount ==
              acceptedBeforeEviction + 65 &&
          screens.primaryKittyImages.length ==
              screens.primaryKittyImages.maximumImages &&
          screens.primaryKittyImages.imageById(100) == null &&
          screens.primaryKittyImages.imageById(101) != null &&
          screens.primaryKittyImages.imageById(164) != null &&
          screens.primaryKittyImages.retainedBytes == 64 * 4 &&
          screens.primaryKittyImages.evictionCount ==
              resourceEvictionsBefore + 1 &&
          screens.primaryKittyImages.evictedBytes == evictedBytesBefore + 4 &&
          screens.primaryKittyImages.placementCount == 0 &&
          screens.primaryKittyImages.animationFrameCount == 0 &&
          snapshot.kittyAtlasEntryCount == 0 &&
          snapshot.kittyResourceEvictionCount ==
              screens.primaryKittyImages.evictionCount +
                  screens.alternateKittyImages.evictionCount &&
          snapshot.kittyEvictedBytes ==
              screens.primaryKittyImages.evictedBytes +
                  screens.alternateKittyImages.evictedBytes) {
        evicted = snapshot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      evicted != null,
      'real PTY image pressure did not retain the deterministic bounded set '
      '(accepted=${session.kittyGraphicsController.acceptedCommandCount - acceptedBeforeEviction}, '
      'images=${screens.primaryKittyImages.length}, '
      'bytes=${screens.primaryKittyImages.retainedBytes}, '
      'evictions=${screens.primaryKittyImages.evictionCount - resourceEvictionsBefore}, '
      'evicted_bytes=${screens.primaryKittyImages.evictedBytes - evictedBytesBefore}, '
      'oldest=${screens.primaryKittyImages.imageById(100) != null}, '
      'newest=${screens.primaryKittyImages.imageById(164) != null})',
    );

    pane.insertText(
      "printf '\\033_Ga=d,d=R,x=101,y=164,q=2\\033\\\\'; "
      "printf '__DT_KITTY_GRAPHICS_%s__\\r\\n' 'EVICTION_DELETED'",
    );
    await pane.submit();
    await _waitForAsciiMarker(session, evictionDeletedMarker);
    await session.kittyGraphicsController.waitForIdle();
    _expectLifecycle(
      screens.primaryKittyImages.isEmpty &&
          screens.primaryKittyImages.evictionCount ==
              resourceEvictionsBefore + 1 &&
          screens.primaryKittyImages.evictedBytes == evictedBytesBefore + 4,
      'pressure cleanup did not preserve lifetime eviction diagnostics',
    );
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    stdout.writeln(
      'TERMINAL_KITTY_GRAPHICS_TEST query=true multipart_rgba=true '
      'multipart_png=true placement=true z_order=true three_bands=true '
      'scroll=true '
      'history=true erase=true delete=true animation=true eviction=true '
      'atlas_cleanup=true metal=true bounded=true',
    );
    return true;
  }

  static Future<bool> _exerciseSearchOverlay(
    TerminalSession session,
    TerminalPane pane,
    TerminalLiveMetalSurface surface,
  ) async {
    const String marker = '__DT_SEARCH_OVERLAY_MATCH__';
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);
    pane.insertText("printf '\\r\\n$marker $marker\\r\\n'");
    await pane.submit();
    await _waitForAsciiMarker(session, marker);
    await _waitForTerminalDisplayPrompt(session, minimumOccurrences: 1);

    final TerminalScreen screen = session.terminalScreenSet.activeScreen;
    final int canonicalDigest = _screenCanonicalDigest(screen);
    final searchResult = session.terminalScreenSet.viewport.search(marker);
    _expectLifecycle(
      searchResult != null &&
          searchResult.matches.length >= 2 &&
          !searchResult.isTruncated,
      'search overlay fixture did not retain two bounded matches',
    );
    final TerminalLiveMetalSurfaceSnapshot baseline = surface.snapshot();
    final int generation = baseline.searchGeneration + 1;
    _expectLifecycle(
      surface.updateSearchResults(
        generation: generation,
        result: searchResult,
        selectedMatchIndex: 0,
      ),
      'search overlay publication did not advance its generation',
    );

    TerminalLiveMetalSurfaceSnapshot? rendered;
    final Stopwatch renderDeadline = Stopwatch()..start();
    while (renderDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (snapshot.searchGeneration == generation &&
          snapshot.searchProjectionGeneration ==
              session.terminalScreenSet.viewport.generation &&
          snapshot.searchSpanCount >= 2 &&
          snapshot.searchCellCount >= marker.length * 2 &&
          snapshot.selectedSearchSpanCount == 1 &&
          !snapshot.searchProjectionTruncated &&
          snapshot.acceptedFrameCount > baseline.acceptedFrameCount &&
          snapshot.pendingFrameCount <= 1 &&
          snapshot.liveAtlasPinCount <= 3) {
        rendered = snapshot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      rendered != null && _screenCanonicalDigest(screen) == canonicalDigest,
      'normal and selected search overlays did not reach bounded Metal '
      'without mutating canonical cells',
    );

    final int clearGeneration = generation + 1;
    _expectLifecycle(
      surface.updateSearchResults(generation: clearGeneration, result: null),
      'search overlay clear did not advance its generation',
    );
    TerminalLiveMetalSurfaceSnapshot? cleared;
    final Stopwatch clearDeadline = Stopwatch()..start();
    while (clearDeadline.elapsed < const Duration(seconds: 5)) {
      final TerminalLiveMetalSurfaceSnapshot snapshot = surface.snapshot();
      if (snapshot.searchGeneration == clearGeneration &&
          snapshot.searchProjectionGeneration == 0 &&
          snapshot.searchSpanCount == 0 &&
          snapshot.searchCellCount == 0 &&
          snapshot.selectedSearchSpanCount == 0 &&
          snapshot.acceptedFrameCount > rendered!.acceptedFrameCount &&
          snapshot.pendingFrameCount <= 1 &&
          snapshot.liveAtlasPinCount <= 3) {
        cleared = snapshot;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _expectLifecycle(
      cleared != null && _screenCanonicalDigest(screen) == canonicalDigest,
      'search overlay clear did not reach bounded Metal without cell mutation',
    );
    stdout.writeln(
      'TERMINAL_SEARCH_OVERLAY_TEST matches=true normal=true selected=true '
      'metal=true clear=true canonical=true bounded=true',
    );
    return true;
  }

  static bool _exerciseP3ColorRendering() {
    for (final int scale in <int>[1, 2]) {
      final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
        catalogGeneration: 1,
        scale: scale.toDouble(),
        limits: const TerminalGlyphAtlasLimits(
          pageWidth: 8,
          pageHeight: 8,
          maximumAlphaPages: 1,
          maximumColorPages: 1,
          maximumEntries: 1,
          maximumRetainedBytes: 8 * 8 * 4,
          gutter: 0,
        ),
      );
      final TerminalGlyphAtlasEntry entry = atlas.ingestKittyImageTile(
        key: TerminalKittyImageAtlasKey(
          screenKindIndex: 0,
          imageId: scale,
          imageResourceGeneration: 1,
          imageContentGeneration: 1,
          placementGeneration: 1,
          sourceX: 0,
          sourceY: 0,
          sourceWidth: 1,
          sourceHeight: 1,
          destinationX: 0,
          destinationY: 0,
          destinationWidth: 1,
          destinationHeight: 1,
          tileX: 0,
          tileY: 0,
          tileWidth: scale,
          tileHeight: scale,
          scale16_16: scale << 16,
        ),
        rgba: Uint8List.fromList(<int>[
          for (var pixel = 0; pixel < scale * scale; pixel++) ...const <int>[
            0xff,
            0x80,
            0x00,
            0xff,
          ],
        ]),
        inputColorSpace: TerminalRenderColorSpace.displayP3,
      );
      final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
        config: TerminalMetalRendererConfig(
          maximumViewportWidth: scale,
          maximumViewportHeight: scale,
          maximumInstances: 1,
          atlasWidth: 8,
          atlasHeight: 8,
          maximumAlphaPages: 1,
          maximumColorPages: 1,
        ),
      );
      final TerminalGlyphAtlasMetalBridge bridge =
          TerminalGlyphAtlasMetalBridge(atlas: atlas, renderer: renderer);
      try {
        _expectLifecycle(
          bridge.synchronize() ==
              TerminalGlyphAtlasSyncDisposition.synchronized,
          'tagged Display P3 tile did not synchronize at ${scale}x',
        );
        final TerminalMetalInstance? instance = bridge.imageInstance(
          entry,
          x: 0,
          y: 0,
          layer: TerminalMetalImageLayer.aboveText,
        );
        _expectLifecycle(
          instance != null,
          'tagged Display P3 tile did not produce a Metal instance',
        );
        final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
          renderer: renderer,
          frameGeneration: 1,
          atlasGeneration: bridge.nativeAtlasGeneration,
          viewportWidth: scale,
          viewportHeight: scale,
          scale16_16: scale << 16,
          backgroundRgba: 0x000000ff,
          instances: <TerminalMetalInstance>[instance!],
        );
        final Uint8List pixels = renderer.renderRgba(frame);
        var exact = pixels.length == scale * scale * 4;
        for (var offset = 0; exact && offset < pixels.length; offset += 4) {
          exact =
              pixels[offset] == 0xff &&
              pixels[offset + 1] == 0x77 &&
              pixels[offset + 2] == 0x00 &&
              pixels[offset + 3] == 0xff;
        }
        _expectLifecycle(
          exact &&
              bridge.pendingUploadCount == 0 &&
              atlas.pendingUploadPageCount == 0 &&
              atlas.livePinCount == 0,
          'tagged Display P3 tile did not render as exact canonical sRGB at '
          '${scale}x',
        );
      } finally {
        bridge.abandonRenderer();
        renderer.dispose();
      }
    }
    stdout.writeln(
      'TERMINAL_P3_COLOR_TEST conversion=true alpha=true scales=2 '
      'metal=true exact=true bounded=true',
    );
    return true;
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

  static _TerminalAsciiPosition? _findScalar(
    TerminalScreen screen,
    int scalar,
  ) {
    for (int row = 0; row < screen.rows; row++) {
      for (int column = 0; column < screen.columns; column++) {
        final int flags = screen.widthFlagsAt(row, column);
        if (flags & TerminalCellFlags.grapheme == 0 &&
            flags & TerminalCellFlags.widthMask !=
                TerminalCellFlags.continuation &&
            screen.contentAt(row, column) == scalar) {
          return _TerminalAsciiPosition(row: row, column: column);
        }
      }
    }
    return null;
  }

  static int _screenCanonicalDigest(TerminalScreen screen) {
    var digest = 0x4d595df4d0f33173;
    void mix(int value) {
      digest = ((digest ^ value) * 0x100000001b3) & 0x7fffffffffffffff;
    }

    mix(screen.rows);
    mix(screen.columns);
    mix(screen.cursorRow);
    mix(screen.cursorColumn);
    for (var row = 0; row < screen.rows; row++) {
      for (var column = 0; column < screen.columns; column++) {
        mix(screen.contentAt(row, column));
        mix(screen.foregroundAt(row, column));
        mix(screen.backgroundAt(row, column));
        mix(screen.styleAt(row, column));
        mix(screen.hyperlinkAt(row, column));
        mix(screen.widthFlagsAt(row, column));
      }
    }
    return digest;
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
        temporaryView = View(configuration: terminalBaseViewConfiguration);
        temporaryWindow = Window(
          frame: const Rect.fromLTWH(0, 0, 64, 32),
          title: 'Dart Terminal resource probe',
          configuration: terminalWindowConfiguration,
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
    final View view = View(configuration: terminalBaseViewConfiguration);
    final Window window = Window(
      frame: const Rect.fromLTWH(0, 0, 64, 32),
      title: 'Dart Terminal shutdown fault probe',
      configuration: terminalWindowConfiguration,
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

bool _containsPoint(TerminalPaneLayoutRect rectangle, double x, double y) =>
    x >= rectangle.left &&
    x < rectangle.left + rectangle.width &&
    y >= rectangle.top &&
    y < rectangle.top + rectangle.height;

TerminalColorScheme _terminalColorScheme(TerminalThemeBrightness brightness) =>
    switch (brightness) {
      TerminalThemeBrightness.light => TerminalColorScheme.light,
      TerminalThemeBrightness.dark => TerminalColorScheme.dark,
    };

final class _TerminalIncidentAcceptanceContext {
  _TerminalIncidentAcceptanceContext._({
    required this.service,
    required this.store,
    required this.processRunner,
    required this.fixtureDirectories,
  });

  factory _TerminalIncidentAcceptanceContext.create(Directory root) {
    final Directory reports = Directory('${root.path}/.incident-reports')
      ..createSync();
    final Directory temporary = Directory('${root.path}/.incident-temporary')
      ..createSync();
    File('${reports.path}/dart_terminal-fixture.ips').writeAsStringSync(
      '${jsonEncode(<String, Object?>{'bundleID': terminalUpdateProduct, 'app_name': terminalIncidentApplicationName})}\n__DT_INCIDENT_PRIVATE_CRASH__\n',
      flush: true,
    );
    final _TerminalIncidentAcceptanceStore store =
        _TerminalIncidentAcceptanceStore();
    store.delegate = TerminalAppleCrashReportStore(
      diagnosticReportsDirectory: reports,
    );
    final _TerminalIncidentAcceptanceProcessRunner processRunner =
        _TerminalIncidentAcceptanceProcessRunner();
    return _TerminalIncidentAcceptanceContext._(
      service: TerminalLocalIncidentService(
        reportStore: store,
        temporaryParent: temporary,
        processRunner: processRunner,
        currentProcessId: 4242,
      ),
      store: store,
      processRunner: processRunner,
      fixtureDirectories: <Directory>[reports, temporary],
    );
  }

  final TerminalIncidentService service;
  final _TerminalIncidentAcceptanceStore store;
  final _TerminalIncidentAcceptanceProcessRunner processRunner;
  final List<Directory> fixtureDirectories;
  int consentCount = 0;

  void removeFixtures() {
    for (final Directory directory in fixtureDirectories) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }
}

final class _TerminalIncidentAcceptanceStore
    implements TerminalIncidentCrashReportStore {
  _TerminalIncidentAcceptanceStore();

  late final TerminalIncidentCrashReportStore delegate;
  int get accessCount => discoverCount + exportCount;
  int discoverCount = 0;
  int exportCount = 0;

  @override
  Future<TerminalIncidentReportSelection> discover({
    required TerminalIncidentCancellation cancellation,
  }) async {
    discoverCount++;
    return delegate.discover(cancellation: cancellation);
  }

  @override
  Future<void> export(
    TerminalIncidentReportSelection selection,
    File destination, {
    required TerminalIncidentCancellation cancellation,
  }) async {
    exportCount++;
    await delegate.export(selection, destination, cancellation: cancellation);
  }
}

final class _TerminalIncidentAcceptanceProcessRunner
    implements TerminalIncidentProcessRunner {
  var runCount = 0;
  List<String>? lastArguments;

  @override
  Future<TerminalIncidentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required int maximumOutputBytes,
    required TerminalIncidentCancellation cancellation,
  }) async {
    runCount++;
    lastArguments = List<String>.unmodifiable(arguments);
    if (cancellation.isCancelled ||
        executable != '/usr/bin/sample' ||
        arguments.length != 5 ||
        arguments[0] != '4242' ||
        arguments[1] != '1' ||
        arguments[2] != '1' ||
        arguments[3] != '-file') {
      return const TerminalIncidentProcessResult(
        TerminalIncidentProcessDisposition.failed,
      );
    }
    File(arguments[4])
        .writeAsStringSync('__DT_INCIDENT_PRIVATE_SAMPLE__\n', flush: true);
    return const TerminalIncidentProcessResult(
      TerminalIncidentProcessDisposition.completed,
    );
  }
}

final class _TerminalUpdateAcceptanceService
    implements TerminalUpdateProductService {
  static final TerminalUpdateRelease _availableRelease = TerminalUpdateRelease(
    version: TerminalSemanticVersion.parse('0.2.0'),
    build: 2,
    minimumMacos: const TerminalMacosVersion(14, 0),
    archiveUrl: Uri.parse(
      'https://updates.example.invalid/DartTerminal-0.2.0.zip',
    ),
    archiveSize: 4096,
    archiveSha256: List<String>.filled(64, 'd').join(),
    releaseNotes: const <String>['<b>Authenticated plain release note.</b>'],
  );

  var checkCount = 0;
  var installCount = 0;
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  Future<TerminalUpdateRelease?> check() async {
    checkCount++;
    return _availableRelease;
  }

  @override
  Future<void> prepareInstall(TerminalUpdateRelease release) async {
    if (!identical(release, _availableRelease)) {
      throw StateError('update acceptance received an unauthenticated release');
    }
    installCount++;
  }

  @override
  void cancel() {
    cancelCount++;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}

final class _TerminalNotificationAcceptancePost {
  const _TerminalNotificationAcceptancePost({
    required this.notification,
    required this.deliveryToken,
    required this.responseToken,
  });

  final AppKitUserNotification notification;
  final int deliveryToken;
  final int responseToken;
}

/// Content-owning recorder used only by the gated shipped-runtime acceptance.
final class _TerminalNotificationAcceptancePlatformPort
    implements TerminalUserNotificationPlatformPort {
  final List<int> settingsTokens = <int>[];
  final List<int> authorizationTokens = <int>[];
  final List<_TerminalNotificationAcceptancePost> posts =
      <_TerminalNotificationAcceptancePost>[];
  final List<String> removedIdentifiers = <String>[];
  final List<String?> badgeLabels = <String?>[];
  var _nextToken = 1;

  @override
  AppKitUserNotificationAuthorizationStatus? get cachedAuthorizationStatus =>
      AppKitUserNotificationAuthorizationStatus.unknown;

  /// This recorder never calls UserNotifications or creates a visible post.
  int get visiblePostCount => 0;

  @override
  int refreshSettings() {
    final int token = _nextToken++;
    settingsTokens.add(token);
    return token;
  }

  @override
  int requestAuthorization() {
    final int token = _nextToken++;
    authorizationTokens.add(token);
    return token;
  }

  @override
  int postTrackedNotification(
    AppKitUserNotification notification, {
    required int responseToken,
  }) {
    final int deliveryToken = _nextToken++;
    posts.add(
      _TerminalNotificationAcceptancePost(
        notification: notification,
        deliveryToken: deliveryToken,
        responseToken: responseToken,
      ),
    );
    return deliveryToken;
  }

  @override
  void removeNotification(String identifier) {
    removedIdentifiers.add(identifier);
  }

  @override
  void setDockBadgeLabel(String? label) {
    badgeLabels.add(label);
  }
}

final class _TerminalDesktopSignalAcceptanceClock {
  int _micros = 0;

  int call() => _micros;

  void advance(Duration duration) {
    _micros += duration.inMicroseconds;
  }
}

/// Acceptance-only boundary that validates native values while suppressing the
/// user-visible notification post. Removal and Dock projection still cross the
/// real AppKit symbols, which do not request notification authorization.
final class _TerminalDesktopSignalAcceptanceNativePort
    implements TerminalDesktopSignalNativePort {
  _TerminalDesktopSignalAcceptanceNativePort(AppKitApplication application)
    : _application = application {
    _nativePort = TerminalAppKitDesktopSignalPort(
      application: application,
      onError: (Object error, StackTrace _) => nativeErrors.add(error),
    );
  }

  final AppKitApplication _application;
  late final TerminalAppKitDesktopSignalPort _nativePort;
  final List<AppKitUserNotification> posts = <AppKitUserNotification>[];
  final List<String> removedIdentifiers = <String>[];
  final List<String?> badgeLabels = <String?>[];
  final List<Object> nativeErrors = <Object>[];

  @override
  bool postNotification({
    required TerminalSessionId sessionId,
    required String identifier,
    required String title,
    required String body,
  }) {
    posts.add(
      AppKitUserNotification(identifier: identifier, title: title, body: body),
    );
    return true;
  }

  @override
  bool removeNotification(String identifier) {
    final bool removed = _nativePort.removeNotification(identifier);
    if (removed) removedIdentifiers.add(identifier);
    return removed;
  }

  @override
  bool setDockBadgeLabel(String? label) {
    final bool projected = _nativePort.setDockBadgeLabel(label);
    if (projected) {
      badgeLabels.add(label);
      if (_application.dockBadgeLabel != label) return false;
    }
    return projected;
  }
}

final class _TerminalProductPerformanceObservation {
  final Stopwatch _clock = Stopwatch()..start();
  final List<int> _frameWorkMicroseconds = <int>[];
  Completer<int>? _pendingInputAdmission;
  int _inputStartedMicroseconds = 0;
  bool _collectFrameMeasurements = false;
  bool startupFramePublished = false;

  void recordFrameAttempt(TerminalLiveMetalFrameObservation observation) {
    if (!observation.isAccepted) return;
    if (!startupFramePublished) {
      startupFramePublished = true;
      stdout.writeln('TERMINAL_PRODUCT_PERFORMANCE_STARTUP first_frame=true');
    }
    if (!_collectFrameMeasurements) return;
    if (_frameWorkMicroseconds.length >= 32) {
      throw StateError('performance frame observation exceeded its bound');
    }
    _frameWorkMicroseconds.add(math.max(1, observation.totalWorkMicroseconds));
  }

  void recordInputAdmission(TerminalKeyRouteResult route) {
    final Completer<int>? pending = _pendingInputAdmission;
    if (pending == null || pending.isCompleted) return;
    if (route.disposition != TerminalKeyRouteDisposition.encoded ||
        route.encodedByteCount != 3) {
      pending.completeError(
        StateError('performance input was not admitted as one exact key'),
      );
      return;
    }
    pending.complete(
      math.max(1, _clock.elapsedMicroseconds - _inputStartedMicroseconds),
    );
  }

  void startFrameMeasurements() {
    if (_collectFrameMeasurements) {
      throw StateError('performance frame observation is already active');
    }
    _frameWorkMicroseconds.clear();
    _collectFrameMeasurements = true;
  }

  List<int> finishFrameMeasurements() {
    if (!_collectFrameMeasurements) {
      throw StateError('performance frame observation is not active');
    }
    _collectFrameMeasurements = false;
    if (_frameWorkMicroseconds.isEmpty) {
      throw StateError('performance frame observation is empty');
    }
    return List<int>.unmodifiable(_frameWorkMicroseconds);
  }

  Future<int> measureInputAdmission(void Function() operation) async {
    if (_pendingInputAdmission != null) {
      throw StateError('performance input observation is already active');
    }
    final Completer<int> pending = Completer<int>();
    _pendingInputAdmission = pending;
    _inputStartedMicroseconds = _clock.elapsedMicroseconds;
    try {
      operation();
      return await pending.future.timeout(const Duration(seconds: 2));
    } finally {
      if (identical(_pendingInputAdmission, pending)) {
        _pendingInputAdmission = null;
      }
    }
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
    this.horizontalPadding = 0,
    this.verticalPadding = 0,
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
  final double horizontalPadding;
  final double verticalPadding;
  final StreamSubscription<TerminalTextInputEvent> _textInputSubscription;
  final List<StreamSubscription<AppKitEvent>> _nativeContentSubscriptions =
      <StreamSubscription<AppKitEvent>>[];

  Future<void>? _cancelFuture;
  bool _textInputCancelled = false;
  bool adaptersDisposed = false;
  bool isVisible = false;
  TerminalPaneLayoutRect? layout;
  TerminalAppKitContextMenuProjection? contextMenu;
  int _servicesSelectionGeneration = -1;
  int _servicesViewportGeneration = -1;
  bool _servicesRequestorLive = false;

  TerminalPaneLayoutRect? get contentLayout {
    final TerminalPaneLayoutRect? rectangle = layout;
    if (rectangle == null) return null;
    final double horizontal = math.min(
      horizontalPadding,
      math.max(0, (rectangle.width - 1) / 2),
    );
    final double vertical = math.min(
      verticalPadding,
      math.max(0, (rectangle.height - 1) / 2),
    );
    return TerminalPaneLayoutRect(
      left: rectangle.left + horizontal,
      top: rectangle.top + vertical,
      width: rectangle.width - horizontal * 2,
      height: rectangle.height - vertical * 2,
    );
  }

  void notifyScreenChanged() {
    if (!surface.isDisposed) surface.notifyScreenChanged();
  }

  void updateBackingScale(double backingScaleFactor) {
    if (!surface.isDisposed) surface.updateBackingScale(backingScaleFactor);
  }

  void addNativeContentSubscription(
    StreamSubscription<AppKitEvent> subscription,
  ) {
    if (_textInputCancelled || adaptersDisposed) {
      unawaited(subscription.cancel());
      throw StateError('hierarchy pane ${pane.id} adapters are closing');
    }
    _nativeContentSubscriptions.add(subscription);
  }

  void synchronizeServicesRequestor({
    required bool live,
    required int selectionGeneration,
    required int viewportGeneration,
    required String? Function() selectionText,
  }) {
    if (_servicesRequestorLive == live &&
        _servicesSelectionGeneration == selectionGeneration &&
        _servicesViewportGeneration == viewportGeneration) {
      return;
    }
    view.servicesTextRequestor = live
        ? ServicesTextRequestorConfiguration(selectionText: selectionText())
        : null;
    _servicesRequestorLive = live;
    _servicesSelectionGeneration = selectionGeneration;
    _servicesViewportGeneration = viewportGeneration;
  }

  void applyLayout(TerminalPaneLayoutRect? rectangle, {required bool visible}) {
    if (adaptersDisposed) {
      throw StateError('hierarchy pane ${pane.id} adapters are disposed');
    }
    isVisible = visible;
    this.layout = rectangle;
    surface.updateWindowState(isVisible: visible, isOccluded: !visible);
    if (!visible) return;
    final TerminalPaneLayoutRect resolvedLayout = rectangle!;
    final TerminalGridSize grid = surface.resizeViewport(
      logicalWidth: resolvedLayout.width,
      logicalHeight: resolvedLayout.height,
    );
    pane.resize(rows: grid.rows, columns: grid.columns);
  }

  Future<void> cancelTextInput() => _cancelFuture ??= _cancelTextInput();

  Future<void> _cancelTextInput() async {
    await _textInputSubscription.cancel();
    for (final StreamSubscription<AppKitEvent> subscription
        in _nativeContentSubscriptions) {
      await subscription.cancel();
    }
    _nativeContentSubscriptions.clear();
    _textInputCancelled = true;
  }

  void disposeAdapters() {
    if (adaptersDisposed) return;
    if (!_textInputCancelled) {
      throw StateError(
        'hierarchy pane ${pane.id} text input must be cancelled first',
      );
    }
    contextMenu?.dispose();
    contextMenu = null;
    if (!view.isDisposed) {
      view
        ..quickLookRequestsEnabled = false
        ..servicesTextRequestor = null
        ..dropDestination = null;
    }
    _servicesRequestorLive = false;
    _servicesSelectionGeneration = -1;
    _servicesViewportGeneration = -1;
    if (!client.isDisposed) client.dispose();
    if (!surface.isDisposed) surface.dispose();
    adaptersDisposed = true;
    isVisible = false;
    layout = null;
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

final class _AppKitTerminalOsc52Clipboard
    implements TerminalOsc52ClipboardPort {
  const _AppKitTerminalOsc52Clipboard(this.pasteboard);

  final Pasteboard pasteboard;

  @override
  int get changeCount => pasteboard.changeCount;

  @override
  TerminalOsc52ClipboardText readText() {
    final PasteboardTextSnapshot snapshot = pasteboard.readText();
    return TerminalOsc52ClipboardText(
      text: snapshot.text,
      changeCount: snapshot.changeCount,
    );
  }

  @override
  int writeText(String text) => pasteboard.writeText(text);

  @override
  int clear() => pasteboard.clear();
}

final class _MemoryTerminalOsc52Clipboard
    implements TerminalOsc52ClipboardPort {
  String? _text;
  var _changeCount = 0;
  var _readCount = 0;
  var _writeCount = 0;
  var _clearCount = 0;

  String? get text => _text;
  int get readCount => _readCount;
  int get writeCount => _writeCount;
  int get clearCount => _clearCount;

  void seed(String text) {
    _text = text;
    _changeCount++;
  }

  @override
  int get changeCount => _changeCount;

  @override
  TerminalOsc52ClipboardText readText() {
    _readCount++;
    return TerminalOsc52ClipboardText(text: _text, changeCount: _changeCount);
  }

  @override
  int writeText(String text) {
    _writeCount++;
    seed(text);
    return _changeCount;
  }

  @override
  int clear() {
    _clearCount++;
    _text = null;
    return ++_changeCount;
  }
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
  _TerminalSelectionProductOwner({
    required this.gesture,
    required TerminalScreenSet screens,
    required this.surface,
    required TerminalPromptClickInputCallback onPromptCursorInput,
  }) : localGestures = TerminalLocalGestureController(
         screens: screens,
         onTerminalInput: onPromptCursorInput,
         selection: gesture,
       ),
       autoscroller = TerminalSelectionAutoscroller(gesture: gesture);

  final TerminalSelectionGestureController gesture;
  final TerminalLocalGestureController localGestures;
  final TerminalLiveMetalSurface surface;
  final TerminalSelectionAutoscroller autoscroller;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  bool _disposed = false;
  bool characterObserved = false;
  bool wordObserved = false;
  bool logicalLineObserved = false;
  bool semanticOutputObserved = false;
  bool reverseObserved = false;
  bool shiftOverrideObserved = false;
  bool scrolledUp = false;
  bool scrolledDown = false;
  int promptClickBeginCount = 0;
  int promptClickMoveCount = 0;
  int promptClickCancelledCount = 0;
  int promptClickRejectedCount = 0;
  int promptClickNoMovementCount = 0;
  int promptClickInputBytes = 0;

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
    final TerminalLocalGestureUpdate localUpdate = localGestures.handle(intent);
    if (localUpdate.consumedByPromptClick) {
      _recordPromptClick(localUpdate.promptClick);
      _timer?.cancel();
      _timer = null;
      autoscroller.cancel();
      final TerminalSelectionGestureUpdate? selection = localUpdate.selection;
      if (selection != null && selection.changed) {
        surface.updateSelection(selection.snapshot);
      }
      return;
    }
    final TerminalSelectionGestureUpdate update = localUpdate.selection!;
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

  void suspendTransientInteraction() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    autoscroller.cancel();
    final TerminalLocalGestureUpdate localUpdate = localGestures
        .cancelInteraction();
    final TerminalSelectionGestureUpdate update = localUpdate.selection!;
    if (update.changed) surface.updateSelection(update.snapshot);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    autoscroller.cancel();
    localGestures.dispose();
  }

  void _recordPromptClick(TerminalPromptClickUpdate update) {
    switch (update.outcome) {
      case TerminalPromptClickOutcome.ignored:
        break;
      case TerminalPromptClickOutcome.began:
        promptClickBeginCount++;
      case TerminalPromptClickOutcome.moved:
        promptClickMoveCount++;
        promptClickInputBytes += update.terminalBytes.length;
      case TerminalPromptClickOutcome.noMovement:
        promptClickNoMovementCount++;
      case TerminalPromptClickOutcome.rejected:
        promptClickRejectedCount++;
      case TerminalPromptClickOutcome.cancelled:
        promptClickCancelledCount++;
    }
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
      case TerminalSelectionUnit.semanticOutput:
        semanticOutputObserved = true;
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
    this.applicationAction,
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

  factory TerminalKeyRouteResult.applicationAction(TerminalActionId action) =>
      TerminalKeyRouteResult._(
        TerminalKeyRouteDisposition.action,
        applicationAction: action,
      );

  final TerminalKeyRouteDisposition disposition;
  final int encodedByteCount;
  final TerminalKeyBindingAction? action;
  final TerminalActionId? applicationAction;
}

/// Resolves and encodes one AppKit key event for the active terminal pane.
///
/// Each handled event invokes one pane action, schedules one application
/// action, or performs one bounded pane write. An application binding without
/// a scheduler is consumed fail-closed and never falls through to PTY bytes.
/// Native AppKit menu key equivalents are consumed before this router receives
/// events, so it never redispatches menu commands.
final class TerminalKeyEventRouter {
  TerminalKeyEventRouter({
    TerminalKeyBindingEngine? bindingEngine,
    TerminalKeyEncoder? encoder,
    TerminalProductConfigurationAuthority? configurationAuthority,
    void Function(TerminalActionId action)? onApplicationAction,
  }) : _bindingEngine = bindingEngine ?? TerminalKeyBindingEngine.standard(),
       _encoder = encoder ?? TerminalKeyEncoder(),
       _configurationAuthority = configurationAuthority,
       _onApplicationAction = onApplicationAction {
    if (configurationAuthority != null &&
        (bindingEngine != null || encoder != null)) {
      throw ArgumentError(
        'configurationAuthority cannot be combined with a fixed binding '
        'engine or encoder',
      );
    }
  }

  final TerminalKeyBindingEngine _bindingEngine;
  final TerminalKeyEncoder _encoder;
  final TerminalProductConfigurationAuthority? _configurationAuthority;
  final void Function(TerminalActionId action)? _onApplicationAction;

  TerminalKeyRouteResult handleKeyDown(
    AppKitKeyEvent appKitEvent,
    TerminalPane pane,
  ) => handleKeyEvent(appKitEvent, pane);

  TerminalKeyRouteResult handleKeyEvent(
    AppKitKeyEvent appKitEvent,
    TerminalPane pane,
  ) =>
      handleTerminalKeyEvent(TerminalAppKitKeyAdapter.adapt(appKitEvent), pane);

  TerminalKeyRouteResult handleTerminalKeyDown(
    TerminalKeyEvent event,
    TerminalPane pane,
  ) => handleTerminalKeyEvent(event, pane);

  TerminalKeyRouteResult handleTerminalKeyEvent(
    TerminalKeyEvent event,
    TerminalPane pane,
  ) {
    if (event.eventType == TerminalKeyEventType.release) {
      return _encode(event, pane);
    }
    final TerminalKeyBindingResolution resolution =
        (_configurationAuthority?.keyBindingEngine ?? _bindingEngine).resolve(
          event,
        );
    switch (resolution.kind) {
      case TerminalKeyBindingResolutionKind.action:
        final TerminalActionId? applicationAction =
            resolution.applicationAction;
        if (applicationAction != null) {
          _onApplicationAction?.call(applicationAction);
          return TerminalKeyRouteResult.applicationAction(applicationAction);
        }
        final TerminalKeyBindingAction paneAction = resolution.action!;
        _performAction(paneAction, pane);
        return TerminalKeyRouteResult.action(paneAction);
      case TerminalKeyBindingResolutionKind.passthrough:
        return _encode(_withoutCommand(event), pane);
      case TerminalKeyBindingResolutionKind.noMatch:
        return _encode(event, pane);
    }
  }

  TerminalKeyRouteResult _encode(TerminalKeyEvent event, TerminalPane pane) {
    final Uint8List bytes = (_configurationAuthority?.keyEncoder ?? _encoder)
        .encode(event, modes: pane.keyboardModes);
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
        eventType: event.eventType,
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
  PtyProcessSnapshot processSnapshot() => _delegate.processSnapshot();

  @override
  PtyWorkingDirectorySnapshot workingDirectorySnapshot() =>
      _delegate.workingDirectorySnapshot();

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
