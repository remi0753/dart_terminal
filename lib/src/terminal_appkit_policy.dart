import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_tab_metadata.dart';
import 'terminal_typography.dart';

/// Native window styles intentionally selected by Dart Terminal.
const WindowConfiguration terminalWindowConfiguration = WindowConfiguration(
  titled: true,
  closable: true,
  miniaturizable: true,
  resizable: true,
);

/// Behavior used by package-created diagnostic views.
const ViewConfiguration terminalBaseViewConfiguration = ViewConfiguration(
  acceptsFirstResponder: true,
  autoresizesWidth: true,
  autoresizesHeight: true,
);

/// Presentation used by the built-in command-palette text surface.
const TextViewConfiguration terminalCommandPaletteTextViewConfiguration =
    TextViewConfiguration(
      view: terminalBaseViewConfiguration,
      font: TextViewFont.monospacedSystem(
        size: 18,
        weight: TextViewFontWeight.regular,
      ),
      padding: TextViewPadding.all(20),
      foregroundColor: TextViewColor.label(),
      backgroundColor: TextViewColor.windowBackground(),
    );

/// Presentation used by the searchable effective-configuration inspector.
const TextViewConfiguration terminalSettingsInspectorTextViewConfiguration =
    TextViewConfiguration(
      view: terminalBaseViewConfiguration,
      font: TextViewFont.monospacedSystem(
        size: TerminalDefaultTypography.fontSize,
        weight: TextViewFontWeight.regular,
      ),
      padding: TextViewPadding.all(18),
      foregroundColor: TextViewColor.label(),
      backgroundColor: TextViewColor.windowBackground(),
    );

/// Quiet, editor-first presentation shared by every Settings mode.
final TextViewColor terminalSettingsSurfaceColor = TextViewColor.sRgb(
  red: 0.055,
  green: 0.063,
  blue: 0.078,
);
final TextViewColor terminalSettingsPrimaryTextColor = TextViewColor.sRgb(
  red: 0.82,
  green: 0.85,
  blue: 0.9,
);
final TextViewColor terminalSettingsSecondaryTextColor = TextViewColor.sRgb(
  red: 0.57,
  green: 0.62,
  blue: 0.7,
);
const ViewConfiguration _terminalSettingsPassiveViewConfiguration =
    ViewConfiguration(
      acceptsFirstResponder: false,
      autoresizesWidth: true,
      autoresizesHeight: true,
    );

final TextEditorConfiguration terminalSettingsEditorConfiguration =
    TextEditorConfiguration(
      view: terminalBaseViewConfiguration,
      font: const TextViewFont.monospacedSystem(
        size: TerminalDefaultTypography.fontSize,
        weight: TextViewFontWeight.regular,
      ),
      padding: const TextViewPadding(top: 22, right: 20, bottom: 18, left: 24),
      foregroundColor: terminalSettingsPrimaryTextColor,
      backgroundColor: terminalSettingsSurfaceColor,
    );

final TextViewConfiguration terminalSettingsStatusConfiguration =
    TextViewConfiguration(
      view: _terminalSettingsPassiveViewConfiguration,
      font: const TextViewFont.monospacedSystem(
        size: 12,
        weight: TextViewFontWeight.medium,
      ),
      padding: const TextViewPadding(top: 10, right: 18, bottom: 10, left: 24),
      foregroundColor: terminalSettingsSecondaryTextColor,
      backgroundColor: terminalSettingsSurfaceColor,
    );

final TextViewConfiguration terminalSettingsDetailConfiguration =
    TextViewConfiguration(
      view: _terminalSettingsPassiveViewConfiguration,
      font: const TextViewFont.monospacedSystem(
        size: 13,
        weight: TextViewFontWeight.regular,
      ),
      padding: const TextViewPadding(top: 24, right: 18, bottom: 18, left: 18),
      foregroundColor: terminalSettingsPrimaryTextColor,
      backgroundColor: terminalSettingsSurfaceColor,
    );

/// Terminal commands own enabled state; AppKit must not infer it.
const MenuConfiguration terminalMenuConfiguration = MenuConfiguration(
  autoEnablesItems: false,
);

/// Product-owned URL rules shared by parsing and native opening.
final ExternalUrlPolicy terminalExternalUrlPolicy = ExternalUrlPolicy(
  <ExternalUrlSchemePolicy>[
    ExternalUrlSchemePolicy(
      scheme: 'http',
      requiresAuthority: true,
      requiresHost: true,
    ),
    ExternalUrlSchemePolicy(
      scheme: 'https',
      requiresAuthority: true,
      requiresHost: true,
    ),
    ExternalUrlSchemePolicy(
      scheme: 'mailto',
      allowsAuthority: false,
      requiresPath: true,
    ),
  ],
);

/// Product presentation for the compact native tab marker.
WindowTabAccessory? terminalTabAccessory(TerminalTabColor? color) =>
    color == null
    ? null
    : WindowTabAccessory(
        color: WindowTabColor(
          red: color.red / 255,
          green: color.green / 255,
          blue: color.blue / 255,
          alpha: color.alpha / 255,
        ),
        width: 8,
        height: 8,
        shape: WindowTabAccessoryShape.ellipse,
      );
