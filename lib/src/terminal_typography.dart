/// Shared zero-configuration typography for terminal content and Settings.
abstract final class TerminalDefaultTypography {
  /// Empty family delegates selection to the macOS system monospace font.
  static const String fontFamily = '';

  /// Product-owned readable point size for primary editable content.
  static const double fontSize = 14;
}
