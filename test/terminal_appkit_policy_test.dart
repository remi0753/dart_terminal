import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_terminal/src/terminal_appkit_policy.dart';
import 'package:dart_terminal/src/terminal_tab_metadata.dart';

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

  _expect(
    terminalWindowConfiguration == const WindowConfiguration() &&
        terminalBaseViewConfiguration == const ViewConfiguration() &&
        terminalCommandPaletteTextViewConfiguration ==
            const TextViewConfiguration() &&
        terminalSettingsInspectorTextViewConfiguration.view ==
            terminalBaseViewConfiguration &&
        terminalSettingsInspectorTextViewConfiguration.font.size == 14 &&
        terminalSettingsInspectorTextViewConfiguration.padding.top == 18 &&
        !terminalMenuConfiguration.autoEnablesItems,
    'application-owned native presentation policies preserve product behavior',
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

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
