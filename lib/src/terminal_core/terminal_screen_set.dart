import 'dart:typed_data';

import 'terminal_hyperlink.dart';
import 'terminal_keyboard_modes.dart';
import 'terminal_mouse_modes.dart';
import 'terminal_screen.dart';
import 'terminal_semantic_prompt.dart';
import 'terminal_session_metadata.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

part 'terminal_selection.dart';
part 'terminal_accessibility.dart';
part 'terminal_viewport.dart';

enum TerminalScreenKind { primary, alternate }

/// Owns fixed-size primary and alternate grids with shared resources.
final class TerminalScreenSet {
  static const int maximumLogicalViewportExtent = 65535;

  factory TerminalScreenSet({
    required int rows,
    required int columns,
    TerminalStyleTable? styleTable,
    TerminalPalette? palette,
    TerminalGraphemeTable? graphemeTable,
    TerminalHyperlinkTable? hyperlinkTable,
    TerminalScrollback? scrollback,
    TerminalSessionMetadata? metadata,
    TerminalCursorShape initialCursorShape = TerminalCursorShape.block,
    bool initialCursorBlinking = true,
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
        initialCursorShape: initialCursorShape,
        initialCursorBlinking: initialCursorBlinking,
      ),
      alternate: TerminalScreen(
        rows: rows,
        columns: columns,
        styleTable: sharedStyles,
        palette: sharedPalette,
        graphemeTable: sharedGraphemes,
        hyperlinkTable: sharedHyperlinks,
        initialCursorShape: initialCursorShape,
        initialCursorBlinking: initialCursorBlinking,
      ),
      styleTable: sharedStyles,
      palette: sharedPalette,
      graphemeTable: sharedGraphemes,
      hyperlinkTable: sharedHyperlinks,
      scrollback: sharedScrollback,
      scrollbackAttachment: scrollbackAttachment,
      metadata: metadata ?? TerminalSessionMetadata(),
      semanticPrompt: TerminalSemanticPromptModel(),
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
    required this.metadata,
    required this.semanticPrompt,
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
  final TerminalSessionMetadata metadata;
  final TerminalSemanticPromptModel semanticPrompt;
  final TerminalScrollbackAttachment _scrollbackAttachment;
  late final TerminalViewport _viewport;

  TerminalScreenKind _activeKind = TerminalScreenKind.primary;
  bool _mode1049Active = false;
  bool _applicationCursorKeys = false;
  bool _applicationKeypad = false;
  bool _applicationEscape = false;
  int _modifyOtherKeys = 0;
  final _KittyKeyboardState _primaryKittyKeyboard = _KittyKeyboardState();
  final _KittyKeyboardState _alternateKittyKeyboard = _KittyKeyboardState();
  bool _bracketedPaste = false;
  bool _focusReporting = false;
  int _focusReportingGeneration = 1;
  bool _synchronizedOutput = false;
  int _synchronizedOutputGeneration = 1;
  int? _logicalViewportWidth;
  int? _logicalViewportHeight;
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
  bool get focusReportingMode => _focusReporting;
  int get focusReportingGeneration => _focusReportingGeneration;
  bool get synchronizedOutputMode => _synchronizedOutput;
  int get synchronizedOutputGeneration => _synchronizedOutputGeneration;
  TerminalKeyboardModes get keyboardModes => TerminalKeyboardModes(
    applicationCursorKeys: _applicationCursorKeys,
    applicationKeypad: _applicationKeypad,
    applicationEscape: _applicationEscape,
    modifyOtherKeys: _modifyOtherKeys,
    kittyKeyboardFlags: _activeKittyKeyboard.flags,
  );
  TerminalMouseModes get mouseModes =>
      TerminalMouseModes(tracking: _mouseTracking, encoding: _mouseEncoding);
  int get transitionGeneration => _transitionGeneration;
  int get kittyKeyboardStackDepth => _activeKittyKeyboard.depth;
  TerminalViewport get viewport => _viewport;
  ({int width, int height})? get logicalViewportSize {
    final int? width = _logicalViewportWidth;
    final int? height = _logicalViewportHeight;
    return width == null || height == null
        ? null
        : (width: width, height: height);
  }

  /// Publishes AppKit content-view dimensions for bounded XTWINOPS replies.
  ///
  /// Invalid or unrepresentable geometry clears the report rather than
  /// retaining stale native state. Terminal grid dimensions remain separate.
  bool updateLogicalViewportSize({
    required double width,
    required double height,
  }) {
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > maximumLogicalViewportExtent ||
        height > maximumLogicalViewportExtent) {
      _logicalViewportWidth = null;
      _logicalViewportHeight = null;
      return false;
    }
    _logicalViewportWidth = width.ceil();
    _logicalViewportHeight = height.ceil();
    return true;
  }

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

  void setApplicationEscape(bool enabled) {
    if (_applicationEscape == enabled) {
      return;
    }
    _applicationEscape = enabled;
    _transitionGeneration++;
  }

  void setModifyOtherKeys(int value) {
    RangeError.checkValueInInterval(value, 0, 3, 'value');
    if (_modifyOtherKeys == value) {
      return;
    }
    _modifyOtherKeys = value;
    _transitionGeneration++;
  }

  void setKittyKeyboardFlags(int flags, int mode) {
    if (_activeKittyKeyboard.setFlags(flags, mode)) {
      _transitionGeneration++;
    }
  }

  void pushKittyKeyboardFlags(int flags) {
    _activeKittyKeyboard.push(flags);
    _transitionGeneration++;
  }

  void popKittyKeyboardFlags(int count) {
    if (_activeKittyKeyboard.pop(count)) {
      _transitionGeneration++;
    }
  }

  void setBracketedPasteMode(bool enabled) {
    if (_bracketedPaste == enabled) {
      return;
    }
    _bracketedPaste = enabled;
    _transitionGeneration++;
  }

  void setFocusReportingMode(bool enabled) {
    if (_focusReporting == enabled) {
      return;
    }
    _focusReporting = enabled;
    _focusReportingGeneration++;
    _transitionGeneration++;
  }

  /// Sets DEC private mode 2026.
  ///
  /// Repeated enable controls advance the generation so the presentation owner
  /// can restart its bounded safety deadline without introducing nesting.
  void setSynchronizedOutputMode(bool enabled) {
    if (_synchronizedOutput == enabled) {
      if (enabled) {
        _synchronizedOutputGeneration++;
        _transitionGeneration++;
      }
      return;
    }
    _synchronizedOutput = enabled;
    _synchronizedOutputGeneration++;
    _transitionGeneration++;
  }

  /// Releases mode 2026 only if [expectedGeneration] still owns its deadline.
  bool expireSynchronizedOutputMode(int expectedGeneration) {
    if (!_synchronizedOutput ||
        expectedGeneration != _synchronizedOutputGeneration) {
      return false;
    }
    _synchronizedOutput = false;
    _synchronizedOutputGeneration++;
    _transitionGeneration++;
    return true;
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
    _applicationEscape = false;
    _modifyOtherKeys = 0;
    _primaryKittyKeyboard.reset();
    _alternateKittyKeyboard.reset();
    _bracketedPaste = false;
    if (_synchronizedOutput) {
      _synchronizedOutput = false;
      _synchronizedOutputGeneration++;
    }
    if (_focusReporting) {
      _focusReporting = false;
      _focusReportingGeneration++;
    }
    _mouseTracking = TerminalMouseTrackingMode.none;
    _mouseEncoding = TerminalMouseCoordinateEncoding.legacy;
    metadata.reset();
    semanticPrompt.reset();
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

  _KittyKeyboardState get _activeKittyKeyboard => switch (_activeKind) {
    TerminalScreenKind.primary => _primaryKittyKeyboard,
    TerminalScreenKind.alternate => _alternateKittyKeyboard,
  };
}

final class _KittyKeyboardState {
  static const int maximumStackDepth = 16;

  final Uint8List _stack = Uint8List(maximumStackDepth);
  int flags = 0;
  int depth = 0;

  bool setFlags(int requestedFlags, int mode) {
    final int known = requestedFlags & TerminalKeyboardModes.kittyKnownFlags;
    final int next = switch (mode) {
      1 => known,
      2 => flags | known,
      3 => flags & ~known,
      _ => throw ArgumentError.value(mode, 'mode', 'must be 1, 2, or 3'),
    };
    if (next == flags) return false;
    flags = next;
    return true;
  }

  void push(int requestedFlags) {
    if (depth == maximumStackDepth) {
      for (int index = 1; index < maximumStackDepth; index++) {
        _stack[index - 1] = _stack[index];
      }
      depth--;
    }
    _stack[depth++] = flags;
    flags = requestedFlags & TerminalKeyboardModes.kittyKnownFlags;
  }

  bool pop(int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be positive');
    }
    if (depth == 0) {
      if (flags == 0) return false;
      flags = 0;
      return true;
    }
    if (count >= depth) {
      final int next = count == depth ? _stack[0] : 0;
      final bool changed = flags != next || depth != 0;
      flags = next;
      depth = 0;
      return changed;
    }
    depth -= count;
    flags = _stack[depth];
    return true;
  }

  void reset() {
    flags = 0;
    depth = 0;
  }
}
