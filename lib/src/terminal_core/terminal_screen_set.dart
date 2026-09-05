import 'terminal_screen.dart';
import 'terminal_style.dart';

enum TerminalScreenKind { primary, alternate }

/// Owns fixed-size primary and alternate grids with shared resources.
final class TerminalScreenSet {
  factory TerminalScreenSet({
    required int rows,
    required int columns,
    TerminalStyleTable? styleTable,
    TerminalPalette? palette,
  }) {
    final TerminalStyleTable sharedStyles = styleTable ?? TerminalStyleTable();
    final TerminalPalette sharedPalette = palette ?? TerminalPalette();
    return TerminalScreenSet._(
      primary: TerminalScreen(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
      ),
      alternate: TerminalScreen(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
      ),
      styleTable: sharedStyles,
      palette: sharedPalette,
    );
  }

  TerminalScreenSet._({
    required this.primary,
    required this.alternate,
    required this.styleTable,
    required this.palette,
  });

  final TerminalScreen primary;
  final TerminalScreen alternate;
  final TerminalStyleTable styleTable;
  final TerminalPalette palette;

  TerminalScreenKind _activeKind = TerminalScreenKind.primary;
  bool _mode1049Active = false;
  int _transitionGeneration = 1;

  TerminalScreenKind get activeKind => _activeKind;
  TerminalScreen get activeScreen => switch (_activeKind) {
    TerminalScreenKind.primary => primary,
    TerminalScreenKind.alternate => alternate,
  };
  bool get usingAlternate => _activeKind == TerminalScreenKind.alternate;
  bool get mode1049Active => _mode1049Active;
  int get transitionGeneration => _transitionGeneration;

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
    primary.resetScreen();
    alternate.resetScreen();
    _activeKind = TerminalScreenKind.primary;
    _mode1049Active = false;
    primary.requestFullSnapshot();
    _transitionGeneration++;
  }

  bool _activate(TerminalScreenKind kind) {
    if (_activeKind == kind) {
      return false;
    }
    _activeKind = kind;
    activeScreen.requestFullSnapshot();
    return true;
  }
}
