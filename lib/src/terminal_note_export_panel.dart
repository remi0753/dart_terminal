import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart'
    show TerminalNotesLocale;

import 'terminal_note_store_worker.dart';

/// Dart Terminal presentation policy for one explicit portable Note export.
///
/// The generic AppKit package owns only the save-panel primitive. Product
/// wording, filename, and conversion to the Note store's approved path remain
/// in Dart Terminal.
abstract final class TerminalNoteExportPanel {
  static SavePanelConfiguration configuration(TerminalNotesLocale locale) {
    final bool japanese = locale == TerminalNotesLocale.japanese;
    return SavePanelConfiguration(
      title: japanese ? 'ノートを書き出す' : 'Export Notes',
      message: japanese
          ? '警告: 書き出すファイルにはすべてのノート本文が含まれます。保管や共有には注意してください。'
          : 'Warning: The exported file contains the full text of all notes. '
                'Store and share it carefully.',
      prompt: japanese ? '書き出す' : 'Export',
      defaultFileName: japanese
          ? 'Dart Terminal ノート.json'
          : 'Dart Terminal Notes.json',
      allowedFileExtension: 'json',
    );
  }

  static TerminalNoteApprovedExportPath? choose({
    required AppKitApplication application,
    required TerminalNotesLocale locale,
  }) {
    final SavePanelResult result = application.chooseSaveDestination(
      configuration(locale),
    );
    if (!result.isSelected) return null;
    return TerminalNoteApprovedExportPath.fromAbsolutePath(result.path!);
  }
}
