import 'dart:convert';

import 'terminal_application_state.dart';
import 'terminal_core/terminal_session_metadata.dart';
import 'terminal_pane.dart';
import 'terminal_tab_metadata.dart';

typedef TerminalPaneSessionMetadataProvider = TerminalSessionMetadata? Function(
  PaneId paneId,
);

/// One immutable presentation resolved for a logical terminal tab.
final class TerminalTabPresentation {
  const TerminalTabPresentation({
    required this.title,
    required this.color,
    required this.representedFilePath,
  });

  final String title;
  final TerminalTabColor? color;
  final String? representedFilePath;
}

/// Resolves trusted application presentation from bounded session metadata.
final class TerminalTabPresentationResolver {
  TerminalTabPresentationResolver({
    required TerminalPaneSessionMetadataProvider metadataForPane,
  }) : _metadataForPane = metadataForPane;

  final TerminalPaneSessionMetadataProvider _metadataForPane;

  TerminalTabPresentation resolve(
    TerminalTabState tab, {
    required String fallbackTitle,
  }) {
    if (fallbackTitle.isEmpty ||
        !TerminalSessionMetadata.isSafeTitle(fallbackTitle)) {
      throw ArgumentError.value(
        fallbackTitle,
        'fallbackTitle',
        'must be non-empty safe bounded text',
      );
    }
    final TerminalSessionMetadata? metadata = _metadataForPane(
      tab.focusedPaneId,
    );
    final String? localPath = localFilePath(metadata?.workingDirectory);
    return TerminalTabPresentation(
      title:
          tab.customTitle ??
          metadata?.windowTitle ??
          _basename(localPath) ??
          fallbackTitle,
      color: tab.color,
      representedFilePath: localPath,
    );
  }

  /// Chooses the local cwd copied into a descendant session launch request.
  String? inheritedWorkingDirectoryForPane(PaneId paneId, {String? fallback}) =>
      localFilePath(_metadataForPane(paneId)?.workingDirectory) ?? fallback;

  /// Converts descriptive OSC 7 metadata into local launch authority.
  static String? localFilePath(Uri? value) {
    if (value == null ||
        !TerminalSessionMetadata.isSafeWorkingDirectory(value) ||
        value.host.isNotEmpty && value.host.toLowerCase() != 'localhost') {
      return null;
    }
    try {
      final String path = Uri(path: value.path).toFilePath(windows: false);
      if (!path.startsWith('/') ||
          utf8.encode(path).length >
              TerminalSessionMetadata.maximumWorkingDirectoryUtf8Bytes ||
          _containsUnsafePathScalar(path)) {
        return null;
      }
      return path;
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  static String? _basename(String? path) {
    if (path == null) return null;
    if (path == '/') return path;
    final List<String> components = path
        .split('/')
        .where((String component) => component.isNotEmpty)
        .toList(growable: false);
    return components.isEmpty ? '/' : components.last;
  }

  static bool _containsUnsafePathScalar(String value) {
    for (final int scalar in value.runes) {
      if (scalar <= 0x1f ||
          scalar >= 0x7f && scalar <= 0x9f ||
          scalar == 0x061c ||
          scalar == 0x200e ||
          scalar == 0x200f ||
          scalar == 0x2028 ||
          scalar == 0x2029 ||
          scalar >= 0x202a && scalar <= 0x202e ||
          scalar >= 0x2066 && scalar <= 0x2069) {
        return true;
      }
    }
    return false;
  }
}
