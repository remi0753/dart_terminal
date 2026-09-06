import 'dart:typed_data';

import 'terminal_hyperlink.dart';
import 'terminal_keyboard_modes.dart';
import 'terminal_mouse_modes.dart';
import 'terminal_screen.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

part 'terminal_selection.dart';
part 'terminal_accessibility.dart';
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
    TerminalHyperlinkTable? hyperlinkTable,
    TerminalScrollback? scrollback,
  }) {
    final TerminalStyleTable sharedStyles = styleTable ?? TerminalStyleTable();
    final TerminalPalette sharedPalette = palette ?? TerminalPalette();
    final TerminalGraphemeTable sharedGraphemes =
        graphemeTable ?? TerminalGraphemeTable();
    final TerminalHyperlinkTable sharedHyperlinks =
        hyperlinkTable ?? TerminalHyperlinkTable();
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
        hyperlinkTable: sharedHyperlinks,
        scrollbackAttachment: scrollbackAttachment,
      ),
      alternate: TerminalScreen(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
        graphemeTable: sharedGraphemes,
        hyperlinkTable: sharedHyperlinks,
      ),
      styleTable: sharedStyles,
      palette: sharedPalette,
      graphemeTable: sharedGraphemes,
      hyperlinkTable: sharedHyperlinks,
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
    required this.hyperlinkTable,
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
  final TerminalHyperlinkTable hyperlinkTable;
  final TerminalScrollback scrollback;
  final TerminalScrollbackAttachment _scrollbackAttachment;
  late final TerminalViewport _viewport;

  TerminalScreenKind _activeKind = TerminalScreenKind.primary;
  bool _mode1049Active = false;
  bool _applicationCursorKeys = false;
  bool _applicationKeypad = false;
  bool _bracketedPaste = false;
  TerminalMouseTrackingMode _mouseTracking = TerminalMouseTrackingMode.none;
  TerminalMouseCoordinateEncoding _mouseEncoding =
      TerminalMouseCoordinateEncoding.legacy;
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
  bool get bracketedPasteMode => _bracketedPaste;
  TerminalKeyboardModes get keyboardModes => TerminalKeyboardModes(
    applicationCursorKeys: _applicationCursorKeys,
    applicationKeypad: _applicationKeypad,
  );
  TerminalMouseModes get mouseModes =>
      TerminalMouseModes(tracking: _mouseTracking, encoding: _mouseEncoding);
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

  void setBracketedPasteMode(bool enabled) {
    if (_bracketedPaste == enabled) {
      return;
    }
    _bracketedPaste = enabled;
    _transitionGeneration++;
  }

  void setMouseTrackingMode(TerminalMouseTrackingMode mode, bool enabled) {
    if (mode == TerminalMouseTrackingMode.none) {
      throw ArgumentError.value(mode, 'mode', 'must be a DEC tracking mode');
    }
    final TerminalMouseTrackingMode next = enabled
        ? mode
        : (_mouseTracking == mode
              ? TerminalMouseTrackingMode.none
              : _mouseTracking);
    if (_mouseTracking == next) return;
    _mouseTracking = next;
    _transitionGeneration++;
  }

  void setMouseCoordinateEncoding(
    TerminalMouseCoordinateEncoding encoding,
    bool enabled,
  ) {
    if (encoding == TerminalMouseCoordinateEncoding.legacy) {
      throw ArgumentError.value(
        encoding,
        'encoding',
        'must be an extended DEC coordinate encoding',
      );
    }
    final TerminalMouseCoordinateEncoding next = enabled
        ? encoding
        : (_mouseEncoding == encoding
              ? TerminalMouseCoordinateEncoding.legacy
              : _mouseEncoding);
    if (_mouseEncoding == next) return;
    _mouseEncoding = next;
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
    _bracketedPaste = false;
    _mouseTracking = TerminalMouseTrackingMode.none;
    _mouseEncoding = TerminalMouseCoordinateEncoding.legacy;
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
