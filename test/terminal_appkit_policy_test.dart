import 'dart:io';
import 'dart:math' as math;

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_terminal/src/terminal_accessibility_presentation.dart';
import 'package:dart_terminal/src/terminal_appkit_policy.dart';
import 'package:dart_terminal/src/terminal_config.dart';
import 'package:dart_terminal/src/terminal_renderer/terminal_live_metal_surface.dart';
import 'package:dart_terminal/src/terminal_tab_metadata.dart';
import 'package:dart_terminal/src/terminal_typography.dart';

void main() => runTerminalAppKitPolicyTests();

void runTerminalAppKitPolicyTests() {
  final MacosApplicationManifest manifest = MacosApplicationManifest.parse(
    File('macos_application.json').readAsStringSync(),
  );
  _expect(
    manifest.runner.activationPolicy == MacosRunnerActivationPolicy.regular &&
        manifest.runner.activateOnLaunch &&
        !manifest.runner.terminateAfterLastWindowClosed &&
        manifest.runner.reopenHandled &&
        manifest.runner.messagePump.maxMessagesPerTurn == 64 &&
        manifest.runner.messagePump.maxTimePerTurnMicros == 4000,
    'manifest fixes Dart Terminal Runner lifecycle and message-pump policy',
  );

  final String runtimeIntegrationSource = File(
    'tool/runtime_integration_smoke.dart',
  ).readAsStringSync();
  final int userActionsStart = runtimeIntegrationSource.indexOf(
    'Future<void> _runUserActions(',
  );
  final int userActionsEnd = runtimeIntegrationSource.indexOf(
    'Future<void> _runDiagnostics(',
    userActionsStart,
  );
  _expect(
    userActionsStart >= 0 &&
        userActionsEnd > userActionsStart &&
        runtimeIntegrationSource
            .substring(userActionsStart, userActionsEnd)
            .contains('throughLaunchServices: true,'),
    'foreground-dependent user actions require an exact-bundle Launch '
    'Services launch',
  );
  final int secureKeyboardEntryStart = runtimeIntegrationSource.indexOf(
    'Future<void> _runSecureKeyboardEntry(',
  );
  final int secureKeyboardEntryEnd = runtimeIntegrationSource.indexOf(
    'Future<void> _runDesktopSignals(',
    secureKeyboardEntryStart,
  );
  final String secureKeyboardEntrySource =
      secureKeyboardEntryStart >= 0 &&
          secureKeyboardEntryEnd > secureKeyboardEntryStart
      ? runtimeIntegrationSource.substring(
          secureKeyboardEntryStart,
          secureKeyboardEntryEnd,
        )
      : '';
  _expect(
    secureKeyboardEntrySource.contains('throughLaunchServices: true,'),
    'foreground-dependent Secure Keyboard Entry requires an exact-bundle '
    'Launch Services launch',
  );

  final String terminalApplicationSource = File(
    'lib/src/terminal_application.dart',
  ).readAsStringSync();
  final int secureKeyboardProductStart = terminalApplicationSource.indexOf(
    'static Future<void> _exerciseSecureKeyboardEntryProduct(',
  );
  final int secureKeyboardProductEnd = terminalApplicationSource.indexOf(
    'static Future<void> _exerciseQuickTerminalProduct(',
    secureKeyboardProductStart,
  );
  final String secureKeyboardProductSource =
      secureKeyboardProductStart >= 0 &&
          secureKeyboardProductEnd > secureKeyboardProductStart
      ? terminalApplicationSource.substring(
          secureKeyboardProductStart,
          secureKeyboardProductEnd,
        )
      : '';
  _expect(
    secureKeyboardProductSource.contains('if (!ordinaryNative.isFocused)') &&
        secureKeyboardProductSource.contains('_injectFocusEventForTesting('),
    'Secure Keyboard Entry readiness targets the exact native window when '
    'Launch Services does not focus it',
  );
  final int secureKeyboardPromptReady = secureKeyboardProductSource.indexOf(
    'await _waitForAsciiMarker(ordinarySession, prompt);',
  );
  final int secureKeyboardStatusRead = secureKeyboardProductSource.indexOf(
    'secureKeyboardEntry.status.mode',
  );
  _expect(
    secureKeyboardPromptReady >= 0 &&
        secureKeyboardStatusRead > secureKeyboardPromptReady,
    'Secure Keyboard Entry status is asserted only after current prompt '
    'readiness',
  );

  _expect(
    terminalWindowConfiguration == const WindowConfiguration() &&
        terminalBaseViewConfiguration == const ViewConfiguration() &&
        terminalCommandPaletteTextViewConfiguration ==
            const TextViewConfiguration() &&
        terminalCommandPaletteEditorConfiguration ==
            const TextEditorConfiguration(
              font: TextViewFont.monospacedSystem(size: 18),
              padding: TextViewPadding.all(20),
            ) &&
        terminalSettingsInspectorTextViewConfiguration.view ==
            terminalBaseViewConfiguration &&
        terminalSettingsInspectorTextViewConfiguration.font.size ==
            TerminalDefaultTypography.fontSize &&
        terminalSettingsInspectorTextViewConfiguration.padding.top == 18 &&
        !terminalMenuConfiguration.autoEnablesItems,
    'application-owned native presentation policies preserve product behavior',
  );

  _expect(
    TerminalProductConfigSchema.fontFamily.defaultValue ==
            TerminalDefaultTypography.fontFamily &&
        TerminalProductConfigSchema.fontSize.defaultValue ==
            TerminalDefaultTypography.fontSize &&
        TerminalLiveMetalSurface.defaultFontFamily ==
            TerminalDefaultTypography.fontFamily &&
        TerminalLiveMetalSurface.defaultFontPointSize ==
            TerminalDefaultTypography.fontSize,
    'zero-config schema and renderer share the product typography defaults',
  );
  _expect(
    TerminalDefaultTypography.fontFamily.isEmpty &&
        terminalSettingsEditorConfiguration.font.kind ==
            TextViewFontKind.monospacedSystem &&
        terminalSettingsEditorConfiguration.font.family == null &&
        terminalSettingsEditorConfiguration.font.weight ==
            TextViewFontWeight.regular &&
        terminalSettingsEditorConfiguration.font.size ==
            TerminalDefaultTypography.fontSize,
    'Settings editor matches the zero-config terminal font and size',
  );
  final TerminalSettingsPresentation highContrast =
      terminalSettingsHighContrastPresentation;
  final List<TextViewColor> accessibleTextColors = <TextViewColor>[
    highContrast.primaryTextColor,
    highContrast.secondaryTextColor,
    highContrast.commentColor,
    highContrast.optionColor,
    highContrast.directiveColor,
    highContrast.operatorColor,
    highContrast.valueColor,
    highContrast.unknownColor,
    highContrast.errorColor,
    highContrast.warningColor,
  ];
  _expect(
    highContrast.surfaceColor.kind == TextViewColorKind.sRgb &&
        highContrast.surfaceColor.red == 0 &&
        highContrast.surfaceColor.green == 0 &&
        highContrast.surfaceColor.blue == 0 &&
        accessibleTextColors.every(
          (TextViewColor color) =>
              _contrastRatio(color, highContrast.surfaceColor) >= 7,
        ) &&
        terminalSettingsPresentationFor(
              const TerminalAccessibilityPresentation(
                reduceMotion: false,
                increaseContrast: true,
                differentiateWithoutColor: false,
              ),
            ).editorConfiguration ==
            highContrast.editorConfiguration,
    'Increase Contrast selects deterministic Settings colors at 7:1 or more',
  );

  final WindowTabAccessory accessory = terminalTabAccessory(
    TerminalTabColor.purpleMarker,
  )!;
  _expect(
    accessory.width == 8 &&
        accessory.height == 8 &&
        accessory.shape == WindowTabAccessoryShape.ellipse &&
        accessory.color.red == TerminalTabColor.purpleMarker.red / 255 &&
        accessory.color.green == TerminalTabColor.purpleMarker.green / 255 &&
        accessory.color.blue == TerminalTabColor.purpleMarker.blue / 255 &&
        accessory.color.alpha == 1 &&
        terminalTabAccessory(null) == null,
    'tab presentation explicitly retains the 8-by-8 elliptical marker',
  );

  _expect(
    AllowedExternalUrl.tryParse(
          'https://example.com/path',
          policy: terminalExternalUrlPolicy,
        ) !=
        null,
    'terminal URL policy allows hosted HTTPS',
  );
  _expect(
    AllowedExternalUrl.tryParse(
          'mailto:user@example.com',
          policy: terminalExternalUrlPolicy,
        ) !=
        null,
    'terminal URL policy allows non-authority mailto',
  );
  for (final String rejected in <String>[
    'ftp://example.com/file',
    'https:///missing-host',
    'https://user@example.com/private',
    'mailto://example.com/user',
  ]) {
    _expect(
      AllowedExternalUrl.tryParse(
            rejected,
            policy: terminalExternalUrlPolicy,
          ) ==
          null,
      'terminal URL policy rejects $rejected',
    );
  }
}

double _contrastRatio(TextViewColor left, TextViewColor right) {
  final double leftLuminance = _relativeLuminance(left);
  final double rightLuminance = _relativeLuminance(right);
  final double lighter = math.max(leftLuminance, rightLuminance);
  final double darker = math.min(leftLuminance, rightLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(TextViewColor color) {
  double linear(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.red) +
      0.7152 * linear(color.green) +
      0.0722 * linear(color.blue);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
