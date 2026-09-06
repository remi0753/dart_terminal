import 'dart:typed_data';

import 'terminal_keyboard_modes.dart';
import 'terminal_screen.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

part 'terminal_selection.dart';
part 'terminal_viewport.dart';

enum TerminalScreenKind { primary, alternate }

/// Owns fixed-size primary and alternate grids with shared resources.
final class TerminalScreenSet {
  factory TerminalScreenSet({
    required int rows,
    required int columns,
    TerminalStyleTable? styleTable,
    TerminalPalette? palette,
    TerminalGraphemeTable? graphemeTable,
    TerminalScrollback? scrollback,
  }) {
    final TerminalStyleTable sharedStyles = styleTable ?? TerminalStyleTable();
    final TerminalPalette sharedPalette = palette ?? TerminalPalette();
    final TerminalGraphemeTable sharedGraphemes =
        graphemeTable ?? TerminalGraphemeTable();
    final TerminalScrollback sharedScrollback =
        scrollback ?? TerminalScrollback();
    final TerminalScrollbackAttachment scrollbackAttachment =
        TerminalScrollbackAttachment(sharedScrollback);
    final TerminalScreenSet result = TerminalScreenSet._(
      primary: createTerminalScreenWithScrollback(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
        graphemeTable: sharedGraphemes,
        scrollbackAttachment: scrollbackAttachment,
      ),
      alternate: TerminalScreen(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
        graphemeTable: sharedGraphemes,
      ),
      styleTable: sharedStyles,
      palette: sharedPalette,
      graphemeTable: sharedGraphemes,
      scrollback: sharedScrollback,
      scrollbackAttachment: scrollbackAttachment,
    );
    result._viewport = TerminalViewport._(result);
    return result;
  }

  TerminalScreenSet._({
    required TerminalScreen primary,
    required TerminalScreen alternate,
    required this.styleTable,
    required this.palette,
    required this.graphemeTable,
    required this.scrollback,
    required TerminalScrollbackAttachment scrollbackAttachment,
  }) : _primary = primary,
       _alternate = alternate,
       _scrollbackAttachment = scrollbackAttachment;

  TerminalScreen _primary;
  TerminalScreen _alternate;
  final TerminalStyleTable styleTable;
  final TerminalPalette palette;
  final TerminalGraphemeTable graphemeTable;
  final TerminalScrollback scrollback;
  final TerminalScrollbackAttachment _scrollbackAttachment;
  late final TerminalViewport _viewport;

  TerminalScreenKind _activeKind = TerminalScreenKind.primary;
  bool _mode1049Active = false;
  bool _applicationCursorKeys = false;
  bool _applicationKeypad = false;
  int _transitionGeneration = 1;

  TerminalScreen get primary => _primary;
  TerminalScreen get alternate => _alternate;
  TerminalScreenKind get activeKind => _activeKind;
  TerminalScreen get activeScreen => switch (_activeKind) {
    TerminalScreenKind.primary => primary,
    TerminalScreenKind.alternate => alternate,
  };
  bool get usingAlternate => _activeKind == TerminalScreenKind.alternate;
  bool get mode1049Active => _mode1049Active;
  TerminalKeyboardModes get keyboardModes => TerminalKeyboardModes(
    applicationCursorKeys: _applicationCursorKeys,
    applicationKeypad: _applicationKeypad,
  );
  int get transitionGeneration => _transitionGeneration;
  TerminalViewport get viewport => _viewport;

  /// Atomically replaces both fixed-size grids after visible-line reflow.
  void resize({required int rows, required int columns}) {
    if (rows == primary.rows &&
        columns == primary.columns &&
        rows == alternate.rows &&
        columns == alternate.columns) {
      return;
    }
    validateTerminalScreenDimensions(rows, columns);
    final ({TerminalLogicalAnchor? anchor, bool atBottom}) viewportPosition =
        viewport.capturePrimaryReflowPosition();
    final TerminalScreenHistoryResizeResult primaryResize =
        resizeTerminalScreenWithHistory(
          primary,
          scrollback,
          rows: rows,
          columns: columns,
        );
    final TerminalScreen nextPrimary = primaryResize.screen;
    final TerminalScreen nextAlternate = alternate.resized(
      rows: rows,
      columns: columns,
    );
    primaryResize.commitHistory();
    _scrollbackAttachment.activate(nextPrimary);
    _primary = nextPrimary;
    _alternate = nextAlternate;
    _transitionGeneration++;
    viewport.restorePrimaryReflowPosition(
      viewportPosition.anchor,
      wasAtBottom: viewportPosition.atBottom,
    );
  }

  /// DEC private mode 47: switch buffers without clearing either buffer.
  void setAlternateMode47(bool enabled) {
    if (_activate(
      enabled ? TerminalScreenKind.alternate : TerminalScreenKind.primary,
    )) {
      _transitionGeneration++;
    }
  }

  /// DEC private mode 1047: use alternate, clearing it before returning.
  void setAlternateMode1047(bool enabled) {
    if (enabled) {
      if (_activate(TerminalScreenKind.alternate)) {
        _transitionGeneration++;
      }
      return;
    }
    if (!usingAlternate) {
      return;
    }
    alternate.resetScreen();
    _activate(TerminalScreenKind.primary);
    _transitionGeneration++;
  }

  /// DEC private mode 1048: save or restore the active cursor and rendition.
  void setCursorSaveMode1048(bool enabled) {
    final TerminalScreen screen = activeScreen;
    final int before = screen.generation;
    if (enabled) {
      screen.saveCursor();
    } else {
      screen.restoreCursor();
    }
    if (screen.generation != before) {
      _transitionGeneration++;
    }
  }

  void setApplicationCursorKeys(bool enabled) {
    if (_applicationCursorKeys == enabled) {
      return;
    }
    _applicationCursorKeys = enabled;
    _transitionGeneration++;
  }

  void setApplicationKeypad(bool enabled) {
    if (_applicationKeypad == enabled) {
      return;
    }
    _applicationKeypad = enabled;
    _transitionGeneration++;
  }

  /// DEC private mode 1049: save primary, clear/use alternate, then restore.
  void setAlternateMode1049(bool enabled) {
    if (enabled) {
      if (_mode1049Active) {
        if (_activate(TerminalScreenKind.alternate)) {
          _transitionGeneration++;
        }
        return;
      }
      primary.saveCursor();
      alternate.resetScreen();
      _mode1049Active = true;
      _activate(TerminalScreenKind.alternate);
      _transitionGeneration++;
      return;
    }
    if (!_mode1049Active) {
      return;
    }
    _mode1049Active = false;
    _activate(TerminalScreenKind.primary);
    primary.restoreCursor();
    _transitionGeneration++;
  }

  /// Resets both grids and returns presentation ownership to primary.
  void reset() {
    final int visualBellGeneration =
        primary.visualBellGeneration >= alternate.visualBellGeneration
        ? primary.visualBellGeneration
        : alternate.visualBellGeneration;
    primary.resetScreen();
    alternate.resetScreen();
    _activeKind = TerminalScreenKind.primary;
    _mode1049Active = false;
    _applicationCursorKeys = false;
    _applicationKeypad = false;
    primary.synchronizeVisualBellGeneration(visualBellGeneration);
    primary.requestFullSnapshot();
    _transitionGeneration++;
  }

  bool _activate(TerminalScreenKind kind) {
    primary.breakGraphemeSequence();
    alternate.breakGraphemeSequence();
    if (_activeKind == kind) {
      return false;
    }
    final int visualBellGeneration = activeScreen.visualBellGeneration;
    _activeKind = kind;
    activeScreen.synchronizeVisualBellGeneration(visualBellGeneration);
    activeScreen.requestFullSnapshot();
    return true;
  }
}
