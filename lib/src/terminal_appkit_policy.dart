import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_tab_metadata.dart';

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
