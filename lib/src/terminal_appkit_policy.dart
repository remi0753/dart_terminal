import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_accessibility_presentation.dart';
import 'terminal_tab_metadata.dart';
import 'terminal_typography.dart';

/// Native window styles intentionally selected by Dart Terminal.
const WindowConfiguration terminalWindowConfiguration = WindowConfiguration(
  titled: true,
  closable: true,
  miniaturizable: true,
  resizable: true,
);

/// Borderless retained surface used only by the product Quick Terminal role.
const WindowConfiguration terminalQuickTerminalWindowConfiguration =
    WindowConfiguration(
      titled: false,
      closable: false,
      miniaturizable: false,
      resizable: false,
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

/// Read-only presentation for the privacy-bounded terminal inspector.
const TextViewConfiguration terminalDiagnosticsTextViewConfiguration =
    TextViewConfiguration(
      view: terminalBaseViewConfiguration,
      font: TextViewFont.monospacedSystem(
        size: 13,
        weight: TextViewFontWeight.regular,
      ),
      padding: TextViewPadding.all(18),
      foregroundColor: TextViewColor.label(),
      backgroundColor: TextViewColor.windowBackground(),
    );

/// Read-only plain-text presentation for signed update state and release notes.
const TextViewConfiguration terminalUpdateTextViewConfiguration =
    terminalDiagnosticsTextViewConfiguration;

/// Read-only content-free local incident status presentation.
const TextViewConfiguration terminalIncidentTextViewConfiguration =
    terminalDiagnosticsTextViewConfiguration;

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

const ViewConfiguration _terminalSettingsPassiveViewConfiguration =
    ViewConfiguration(
      acceptsFirstResponder: false,
      autoresizesWidth: true,
      autoresizesHeight: true,
    );

/// Complete immutable Settings palette and native creation configuration.
final class TerminalSettingsPresentation {
  TerminalSettingsPresentation({
    required this.surfaceColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.currentLineColor,
    required this.commentColor,
    required this.optionColor,
    required this.directiveColor,
    required this.operatorColor,
    required this.valueColor,
    required this.unknownColor,
    required this.errorColor,
    required this.warningColor,
  }) : editorConfiguration = TextEditorConfiguration(
         view: terminalBaseViewConfiguration,
         font: const TextViewFont.monospacedSystem(
           size: TerminalDefaultTypography.fontSize,
           weight: TextViewFontWeight.regular,
         ),
         padding: const TextViewPadding(
           top: 22,
           right: 20,
           bottom: 18,
           left: 24,
         ),
         foregroundColor: primaryTextColor,
         backgroundColor: surfaceColor,
       ),
       statusConfiguration = TextViewConfiguration(
         view: _terminalSettingsPassiveViewConfiguration,
         font: const TextViewFont.monospacedSystem(
           size: 12,
           weight: TextViewFontWeight.medium,
         ),
         padding: const TextViewPadding(
           top: 10,
           right: 18,
           bottom: 10,
           left: 24,
         ),
         foregroundColor: secondaryTextColor,
         backgroundColor: surfaceColor,
       ),
       detailConfiguration = TextViewConfiguration(
         view: _terminalSettingsPassiveViewConfiguration,
         font: const TextViewFont.monospacedSystem(
           size: 13,
           weight: TextViewFontWeight.regular,
         ),
         padding: const TextViewPadding(
           top: 24,
           right: 18,
           bottom: 18,
           left: 18,
         ),
         foregroundColor: primaryTextColor,
         backgroundColor: surfaceColor,
       );

  final TextViewColor surfaceColor;
  final TextViewColor primaryTextColor;
  final TextViewColor secondaryTextColor;
  final TextViewColor currentLineColor;
  final TextViewColor commentColor;
  final TextViewColor optionColor;
  final TextViewColor directiveColor;
  final TextViewColor operatorColor;
  final TextViewColor valueColor;
  final TextViewColor unknownColor;
  final TextViewColor errorColor;
  final TextViewColor warningColor;
  final TextEditorConfiguration editorConfiguration;
  final TextViewConfiguration statusConfiguration;
  final TextViewConfiguration detailConfiguration;
}

TextViewColor _settingsColor(double red, double green, double blue) =>
    TextViewColor.sRgb(red: red, green: green, blue: blue);

/// Quiet, editor-first presentation shared by every Settings mode.
final TerminalSettingsPresentation terminalSettingsStandardPresentation =
    TerminalSettingsPresentation(
      surfaceColor: _settingsColor(0.055, 0.063, 0.078),
      primaryTextColor: _settingsColor(0.82, 0.85, 0.9),
      secondaryTextColor: _settingsColor(0.57, 0.62, 0.7),
      currentLineColor: _settingsColor(0.09, 0.12, 0.17),
      commentColor: _settingsColor(0.42, 0.47, 0.55),
      optionColor: _settingsColor(0.39, 0.69, 0.98),
      directiveColor: _settingsColor(0.75, 0.56, 0.96),
      operatorColor: _settingsColor(0.5, 0.55, 0.63),
      valueColor: _settingsColor(0.59, 0.83, 0.65),
      unknownColor: _settingsColor(0.98, 0.43, 0.48),
      errorColor: _settingsColor(1, 0.35, 0.4),
      warningColor: _settingsColor(0.96, 0.7, 0.3),
    );

/// Deterministic high-contrast colors; every text color is at least 7:1
/// against the black surface and diagnostics retain underline geometry.
final TerminalSettingsPresentation terminalSettingsHighContrastPresentation =
    TerminalSettingsPresentation(
      surfaceColor: _settingsColor(0, 0, 0),
      primaryTextColor: _settingsColor(1, 1, 1),
      secondaryTextColor: _settingsColor(0.85, 0.85, 0.85),
      currentLineColor: _settingsColor(0.18, 0.18, 0.18),
      commentColor: _settingsColor(0.75, 0.75, 0.75),
      optionColor: _settingsColor(0.65, 0.88, 1),
      directiveColor: _settingsColor(1, 0.72, 1),
      operatorColor: _settingsColor(0.8, 0.8, 0.8),
      valueColor: _settingsColor(0.7, 1, 0.72),
      unknownColor: _settingsColor(1, 0.62, 0.62),
      errorColor: _settingsColor(1, 0.55, 0.55),
      warningColor: _settingsColor(1, 0.82, 0.45),
    );

TerminalSettingsPresentation terminalSettingsPresentationFor(
  TerminalAccessibilityPresentation presentation,
) => presentation.increaseContrast
    ? terminalSettingsHighContrastPresentation
    : terminalSettingsStandardPresentation;

final TextViewColor terminalSettingsSurfaceColor =
    terminalSettingsStandardPresentation.surfaceColor;
final TextViewColor terminalSettingsPrimaryTextColor =
    terminalSettingsStandardPresentation.primaryTextColor;
final TextViewColor terminalSettingsSecondaryTextColor =
    terminalSettingsStandardPresentation.secondaryTextColor;
final TextViewColor terminalSettingsCurrentLineColor =
    terminalSettingsStandardPresentation.currentLineColor;
final TextEditorConfiguration terminalSettingsEditorConfiguration =
    terminalSettingsStandardPresentation.editorConfiguration;
final TextViewConfiguration terminalSettingsStatusConfiguration =
    terminalSettingsStandardPresentation.statusConfiguration;
final TextViewConfiguration terminalSettingsDetailConfiguration =
    terminalSettingsStandardPresentation.detailConfiguration;

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
