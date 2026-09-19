import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/src/terminal_secure_keyboard_entry.dart';
import 'package:dart_terminal/src/terminal_session.dart';
import 'package:dart_terminal/src/terminal_view_badge_projection.dart';

void main() => runTerminalViewBadgeProjectionTests();

void runTerminalViewBadgeProjectionTests() {
  const TerminalSessionPresentationNotice notice =
      TerminalSessionPresentationNotice(
        text: 'paste requires confirmation — repeat Paste within 10 seconds',
        accessibilityLabel: 'Terminal notice: paste requires confirmation',
        accessibilityHelp: 'This notice is not shell output.',
      );

  final ViewBadge noticeOnly = terminalViewBadge(
    secureInputBadge: null,
    notice: notice,
  )!;
  _expect(
    noticeOnly.text == notice.text &&
        noticeOnly.accessibilityLabel == notice.accessibilityLabel,
    'terminal notice projects without mutating terminal cells',
  );

  final ViewBadge secureOnly = terminalViewBadge(
    secureInputBadge: terminalSecureKeyboardEntryAutomaticBadge,
    notice: null,
  )!;
  _expect(
    secureOnly == terminalSecureKeyboardEntryAutomaticBadge,
    'secure-input badge remains exact without a terminal notice',
  );

  final ViewBadge combined = terminalViewBadge(
    secureInputBadge: terminalSecureKeyboardEntryAutomaticBadge,
    notice: notice,
  )!;
  _expect(
    combined.text.contains('SECURE AUTO') &&
        combined.text.contains('paste requires confirmation') &&
        combined.accessibilityLabel.contains('Secure Keyboard Entry') &&
        combined.accessibilityLabel.contains('Terminal notice'),
    'simultaneous secure-input and terminal notice states remain visible',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
