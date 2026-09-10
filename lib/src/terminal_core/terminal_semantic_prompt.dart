import 'terminal_screen.dart';
import 'vt_parser.dart';

/// Privacy-safe subset of OSC 133 semantic prompt actions.
enum TerminalSemanticPromptAction {
  promptStart,
  inputStart,
  outputStart,
  commandEnd,
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
      0x50 => TerminalSemanticPromptAction.secondaryPrompt,
      _ => null,
    };
    if (action == null) return null;
    if (length == 1) return action;
    if (sequence.payloadByteAt(start + 1) != 0x3b) return null;
    for (int index = start + 2; index < sequence.payloadLength; index++) {
      final int byte = sequence.payloadByteAt(index);
      if (byte < 0x20 || byte > 0x7e) return null;
    }
    return action;
  }

  void apply(TerminalSemanticPromptAction action, TerminalScreen screen) {
    final TerminalSemanticShellState next = switch (action) {
      TerminalSemanticPromptAction.promptStart ||
      TerminalSemanticPromptAction.secondaryPrompt =>
        TerminalSemanticShellState.prompt,
      TerminalSemanticPromptAction.inputStart =>
        TerminalSemanticShellState.input,
      TerminalSemanticPromptAction.outputStart =>
        TerminalSemanticShellState.commandOutput,
      TerminalSemanticPromptAction.commandEnd =>
        TerminalSemanticShellState.unknown,
    };
    if (_shellState != next) {
      _shellState = next;
      _generation++;
    }
    if (action != TerminalSemanticPromptAction.outputStart &&
        action != TerminalSemanticPromptAction.commandEnd) {
      markCurrentRow(screen);
    }
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
    if (_shellState == TerminalSemanticShellState.unknown) return;
    _shellState = TerminalSemanticShellState.unknown;
    _generation++;
  }
}
