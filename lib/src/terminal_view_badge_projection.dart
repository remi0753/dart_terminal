import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_session.dart';

/// Combines independent pane-level status without writing either status into
/// the child process' terminal grid.
ViewBadge? terminalViewBadge({
  required ViewBadge? secureInputBadge,
  required TerminalSessionPresentationNotice? notice,
}) {
  if (notice == null) return secureInputBadge;
  if (secureInputBadge == null) {
    return _checkedBadge(
      text: notice.text,
      accessibilityLabel: notice.accessibilityLabel,
      accessibilityHelp: notice.accessibilityHelp,
    );
  }
  return _checkedBadge(
    text: '${secureInputBadge.text} · ${notice.text}',
    accessibilityLabel:
        '${secureInputBadge.accessibilityLabel}. '
        '${notice.accessibilityLabel}',
    accessibilityHelp:
        '${secureInputBadge.accessibilityHelp} ${notice.accessibilityHelp}',
  );
}

ViewBadge _checkedBadge({
  required String text,
  required String accessibilityLabel,
  required String accessibilityHelp,
}) {
  for (final MapEntry<String, String> value in <String, String>{
    'text': text,
    'accessibilityLabel': accessibilityLabel,
    'accessibilityHelp': accessibilityHelp,
  }.entries) {
    final int length = utf8.encode(value.value).length;
    if (length > ViewBadge.maximumTextUtf8Bytes) {
      throw StateError(
        'terminal ${value.key} exceeds the native view badge bound: $length',
      );
    }
  }
  return ViewBadge(
    text: text,
    accessibilityLabel: accessibilityLabel,
    accessibilityHelp: accessibilityHelp,
  );
}
