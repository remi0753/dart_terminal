import 'terminal_action_registry.dart';
import 'terminal_core/terminal_screen_set.dart';

typedef TerminalPromptViewportReader = TerminalViewport? Function();
typedef TerminalPromptViewportMoved = void Function(TerminalViewport viewport);

/// Product actions that navigate semantic prompt marks in the active viewport.
///
/// The product owns active-pane resolution and render synchronization. This
/// coordinator deliberately contains no AppKit or PTY types, and never writes
/// terminal input.
final class TerminalPromptNavigationActionCoordinator {
  const TerminalPromptNavigationActionCoordinator({
    required TerminalPromptViewportReader activeViewport,
    required TerminalPromptViewportMoved onMoved,
  }) : _activeViewport = activeViewport,
       _onMoved = onMoved;

  final TerminalPromptViewportReader _activeViewport;
  final TerminalPromptViewportMoved _onMoved;

  List<TerminalActionRegistration> registrations() =>
      <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.jumpToPreviousPrompt,
          isAvailable: _canJumpToPreviousPrompt,
          handler: _jumpToPreviousPrompt,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.jumpToNextPrompt,
          isAvailable: _canJumpToNextPrompt,
          handler: _jumpToNextPrompt,
        ),
      ];

  bool _canJumpToPreviousPrompt() =>
      _activeViewport()?.canJumpToPreviousPrompt ?? false;

  bool _canJumpToNextPrompt() =>
      _activeViewport()?.canJumpToNextPrompt ?? false;

  void _jumpToPreviousPrompt() => _jump(previous: true);

  void _jumpToNextPrompt() => _jump(previous: false);

  void _jump({required bool previous}) {
    final TerminalViewport? viewport = _activeViewport();
    if (viewport == null) return;
    final bool moved = previous
        ? viewport.jumpToPreviousPrompt()
        : viewport.jumpToNextPrompt();
    if (moved) _onMoved(viewport);
  }
}
