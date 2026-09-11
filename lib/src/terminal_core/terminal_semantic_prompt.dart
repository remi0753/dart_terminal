import 'terminal_screen.dart';
import 'vt_parser.dart';

/// Privacy-safe subset of OSC 133 semantic prompt actions.
enum TerminalSemanticPromptAction {
  freshLine,
  promptStart,
  inputStart,
  inputStartUntilLineEnd,
  outputStart,
  commandEnd,
  newCommand,
  secondaryPrompt,
}

/// Bounded shell lifecycle state derived from semantic prompt markers.
enum TerminalSemanticShellState { unknown, prompt, input, commandOutput }

/// Owns transient semantic shell state and projects it onto existing row flags.
///
/// Marker options are deliberately neither decoded nor retained. The model
/// therefore cannot become a command-line, prompt-text, or exit-status store.
final class TerminalSemanticPromptModel {
  static const int maximumPayloadBytes = 256;

  TerminalSemanticShellState _shellState = TerminalSemanticShellState.unknown;
  bool _inputEndsAtLineFeed = false;
  int _generation = 1;

  TerminalSemanticShellState get shellState => _shellState;
  int get generation => _generation;

  /// Parses the bytes following `133;` without allocating a payload copy.
  static TerminalSemanticPromptAction? parse(
    VtStringSequence sequence,
    int start,
  ) {
    final int length = sequence.payloadLength - start;
    if (length < 1 || length > maximumPayloadBytes) return null;
    final TerminalSemanticPromptAction? action = switch (sequence.payloadByteAt(
      start,
    )) {
      0x41 => TerminalSemanticPromptAction.promptStart,
      0x42 => TerminalSemanticPromptAction.inputStart,
      0x43 => TerminalSemanticPromptAction.outputStart,
      0x44 => TerminalSemanticPromptAction.commandEnd,
      0x49 => TerminalSemanticPromptAction.inputStartUntilLineEnd,
      0x4c => TerminalSemanticPromptAction.freshLine,
      0x4e => TerminalSemanticPromptAction.newCommand,
      0x50 => TerminalSemanticPromptAction.secondaryPrompt,
      _ => null,
    };
    if (action == null) return null;
    if (length == 1) return action;
    if (action == TerminalSemanticPromptAction.freshLine) return null;
    if (sequence.payloadByteAt(start + 1) != 0x3b) return null;
    for (int index = start + 2; index < sequence.payloadLength; index++) {
      final int byte = sequence.payloadByteAt(index);
      if (byte < 0x20 || byte > 0x7e) return null;
    }
    return action;
  }

  void apply(TerminalSemanticPromptAction action, TerminalScreen screen) {
    if (action == TerminalSemanticPromptAction.freshLine) {
      _moveToFreshLine(screen);
      return;
    }
    if (action == TerminalSemanticPromptAction.promptStart ||
        action == TerminalSemanticPromptAction.newCommand) {
      _moveToFreshLine(screen);
    }
    final TerminalSemanticShellState next = switch (action) {
      TerminalSemanticPromptAction.freshLine => _shellState,
      TerminalSemanticPromptAction.promptStart ||
      TerminalSemanticPromptAction.newCommand ||
      TerminalSemanticPromptAction.secondaryPrompt =>
        TerminalSemanticShellState.prompt,
      TerminalSemanticPromptAction.inputStart ||
      TerminalSemanticPromptAction.inputStartUntilLineEnd =>
        TerminalSemanticShellState.input,
      TerminalSemanticPromptAction.outputStart =>
        TerminalSemanticShellState.commandOutput,
      TerminalSemanticPromptAction.commandEnd =>
        TerminalSemanticShellState.unknown,
    };
    final bool nextInputEndsAtLineFeed =
        action == TerminalSemanticPromptAction.inputStartUntilLineEnd;
    if (_shellState != next ||
        _inputEndsAtLineFeed != nextInputEndsAtLineFeed) {
      _shellState = next;
      _inputEndsAtLineFeed = nextInputEndsAtLineFeed;
      _generation++;
    }
    if (action != TerminalSemanticPromptAction.outputStart &&
        action != TerminalSemanticPromptAction.commandEnd) {
      markCurrentRow(screen);
    }
  }

  /// Applies the `I` extension's end-of-line transition after LF/VT/FF/NEL.
  void completeLineFeed() {
    if (!_inputEndsAtLineFeed) return;
    _inputEndsAtLineFeed = false;
    _shellState = TerminalSemanticShellState.commandOutput;
    _generation++;
  }

  /// Adds the active semantic class before content or a hard break is applied.
  void markCurrentRow(TerminalScreen screen) {
    final int semanticFlag = switch (_shellState) {
      TerminalSemanticShellState.unknown => 0,
      TerminalSemanticShellState.prompt => TerminalRowFlags.prompt,
      TerminalSemanticShellState.input => TerminalRowFlags.command,
      TerminalSemanticShellState.commandOutput => TerminalRowFlags.output,
    };
    if (semanticFlag == 0) return;
    final int row = screen.cursorRow;
    screen.setRowFlags(row, screen.rowFlagsAt(row) | semanticFlag);
  }

  void reset() {
    if (_shellState == TerminalSemanticShellState.unknown &&
        !_inputEndsAtLineFeed) {
      return;
    }
    _shellState = TerminalSemanticShellState.unknown;
    _inputEndsAtLineFeed = false;
    _generation++;
  }

  static void _moveToFreshLine(TerminalScreen screen) {
    final int previousColumn = screen.cursorColumn;
    screen.carriageReturn();
    if (screen.cursorColumn != previousColumn) screen.index();
  }
}
