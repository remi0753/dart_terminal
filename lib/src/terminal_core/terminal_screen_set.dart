import 'dart:typed_data';

import 'terminal_desktop_signals.dart';
import 'terminal_hyperlink.dart';
import 'terminal_keyboard_modes.dart';
import 'terminal_kitty_image_store.dart';
import 'terminal_mouse_modes.dart';
import 'terminal_reply.dart';
import 'terminal_screen.dart';
import 'terminal_semantic_prompt.dart';
import 'terminal_session_metadata.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

part 'terminal_selection.dart';
part 'terminal_semantic_ranges.dart';
part 'terminal_accessibility.dart';
part 'terminal_kitty_image_viewport.dart';
part 'terminal_viewport.dart';
part 'terminal_snapshot_restore_set_state.dart';

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
    TerminalDesktopNotificationModel? desktopNotifications,
    TerminalProgressModel? progress,
    TerminalKittyImageStore? primaryKittyImages,
    TerminalKittyImageStore? alternateKittyImages,
    TerminalCursorShape initialCursorShape = TerminalCursorShape.block,
    bool initialCursorBlinking = true,
    TerminalColorScheme initialColorScheme = TerminalColorScheme.dark,
    int semanticRangeCapacity =
        TerminalSemanticRangeSnapshot.defaultStorageCapacity,
  }) {
    RangeError.checkValueInInterval(
      semanticRangeCapacity,
      1,
      TerminalSemanticRangeSnapshot.maximumStorageCapacity,
      'semanticRangeCapacity',
    );
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
      desktopNotifications:
          desktopNotifications ?? TerminalDesktopNotificationModel(),
      progress: progress ?? TerminalProgressModel(),
      semanticPrompt: TerminalSemanticPromptModel(),
      primaryKittyImages: primaryKittyImages ?? TerminalKittyImageStore(),
      alternateKittyImages: alternateKittyImages ?? TerminalKittyImageStore(),
      initialColorScheme: initialColorScheme,
    );
    result._viewport = TerminalViewport._(result);
    result._semanticRanges = _TerminalSemanticRangeTracker(
      result,
      capacity: semanticRangeCapacity,
    );
    result.semanticPrompt.attachObserver(result._semanticRanges);
    result._attachKittyImageObservers();
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
    required this.desktopNotifications,
    required this.progress,
    required this.semanticPrompt,
    required this.primaryKittyImages,
    required this.alternateKittyImages,
    required TerminalColorScheme initialColorScheme,
  }) : _primary = primary,
       _alternate = alternate,
       _scrollbackAttachment = scrollbackAttachment,
       _colorScheme = initialColorScheme;

  TerminalScreen _primary;
  TerminalScreen _alternate;
  final TerminalStyleTable styleTable;
  final TerminalPalette palette;
  final TerminalGraphemeTable graphemeTable;
  final TerminalHyperlinkTable hyperlinkTable;
  final TerminalScrollback scrollback;
  final TerminalSessionMetadata metadata;
  final TerminalDesktopNotificationModel desktopNotifications;
  final TerminalProgressModel progress;
  final TerminalSemanticPromptModel semanticPrompt;
  final TerminalKittyImageStore primaryKittyImages;
  final TerminalKittyImageStore alternateKittyImages;
  final TerminalScrollbackAttachment _scrollbackAttachment;
  late final TerminalViewport _viewport;
  late final _TerminalSemanticRangeTracker _semanticRanges;

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
  bool _colorSchemeReporting = false;
  bool _inBandSizeReporting = false;
  TerminalColorScheme _colorScheme;
  int? _logicalViewportWidth;
  int? _logicalViewportHeight;
  int? _logicalCellWidth;
  int? _logicalCellHeight;
  TerminalMouseTrackingMode _mouseTracking = TerminalMouseTrackingMode.none;
  TerminalMouseCoordinateEncoding _mouseEncoding =
      TerminalMouseCoordinateEncoding.legacy;
  int _transitionGeneration = 1;
  int _resetGeneration = 1;

  TerminalScreen get primary => _primary;
  TerminalScreen get alternate => _alternate;
  TerminalScreenKind get activeKind => _activeKind;
  TerminalScreen get activeScreen => switch (_activeKind) {
    TerminalScreenKind.primary => primary,
    TerminalScreenKind.alternate => alternate,
  };
  TerminalScreen screenFor(TerminalScreenKind kind) => switch (kind) {
    TerminalScreenKind.primary => primary,
    TerminalScreenKind.alternate => alternate,
  };
  TerminalKittyImageStore get activeKittyImages => switch (_activeKind) {
    TerminalScreenKind.primary => primaryKittyImages,
    TerminalScreenKind.alternate => alternateKittyImages,
  };

  TerminalKittyImageStore kittyImagesFor(TerminalScreenKind kind) =>
      switch (kind) {
        TerminalScreenKind.primary => primaryKittyImages,
        TerminalScreenKind.alternate => alternateKittyImages,
      };
  bool get usingAlternate => _activeKind == TerminalScreenKind.alternate;
  bool get mode1049Active => _mode1049Active;
  bool get bracketedPasteMode => _bracketedPaste;
  bool get focusReportingMode => _focusReporting;
  int get focusReportingGeneration => _focusReportingGeneration;
  bool get synchronizedOutputMode => _synchronizedOutput;
  int get synchronizedOutputGeneration => _synchronizedOutputGeneration;
  bool get colorSchemeReportingMode => _colorSchemeReporting;
  bool get inBandSizeReportingMode => _inBandSizeReporting;
  TerminalColorScheme get colorScheme => _colorScheme;
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
  int get resetGeneration => _resetGeneration;
  int get kittyKeyboardStackDepth => _activeKittyKeyboard.depth;
  TerminalViewport get viewport => _viewport;
  TerminalSemanticRangeSnapshot semanticRangeSnapshot({
    TerminalScreenKind? screenKind,
    int maxRanges = TerminalSemanticRangeSnapshot.defaultMaximumRanges,
  }) => _semanticRanges.snapshot(
    screenKind: screenKind ?? activeKind,
    maxRanges: maxRanges,
  );

  /// Resolves an Option-click target into one bounded shell cursor movement.
  /// The caller owns gesture/modifier arbitration and byte encoding.
  TerminalPromptCursorMoveResolution resolvePromptCursorMove(
    int viewportRow,
    int column, {
    int maxMovements = TerminalPromptCursorMovePlan.maximumCount,
  }) => _resolvePromptCursorMove(
    this,
    viewportRow,
    column,
    maxMovements: maxMovements,
  );
  TerminalKittyViewportSnapshot captureKittyImageViewport() =>
      TerminalKittyViewportSnapshot.capture(this);
  Set<int> captureVisibleKittyImageIds() =>
      TerminalKittyViewportSnapshot.captureVisibleImageIds(this);
  ({int width, int height})? get logicalViewportSize {
    final int? width = _logicalViewportWidth;
    final int? height = _logicalViewportHeight;
    return width == null || height == null
        ? null
        : (width: width, height: height);
  }

  ({int width, int height})? get logicalCellSize {
    final int? width = _logicalCellWidth;
    final int? height = _logicalCellHeight;
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

  /// Publishes one terminal cell's padding-free logical pixel dimensions.
  bool updateLogicalCellSize({required double width, required double height}) {
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > maximumLogicalViewportExtent ||
        height > maximumLogicalViewportExtent) {
      _logicalCellWidth = null;
      _logicalCellHeight = null;
      return false;
    }
    _logicalCellWidth = width.ceil();
    _logicalCellHeight = height.ceil();
    return true;
  }

  bool updateColorScheme(TerminalColorScheme scheme) {
    if (_colorScheme == scheme) return false;
    _colorScheme = scheme;
    _transitionGeneration++;
    return true;
  }

  void setColorSchemeReportingMode(bool enabled) {
    if (_colorSchemeReporting == enabled) return;
    _colorSchemeReporting = enabled;
    _transitionGeneration++;
  }

  void setInBandSizeReportingMode(bool enabled) {
    if (_inBandSizeReporting == enabled) return;
    _inBandSizeReporting = enabled;
    _transitionGeneration++;
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
    _attachKittyImageObservers();
    _transitionGeneration++;
    viewport.restorePrimaryReflowPosition(
      viewportPosition.anchor,
      wasAtBottom: viewportPosition.atBottom,
    );
    _pruneKittyPlacements(TerminalScreenKind.primary);
    _pruneKittyPlacements(TerminalScreenKind.alternate);
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
    _colorSchemeReporting = false;
    _inBandSizeReporting = false;
    if (_focusReporting) {
      _focusReporting = false;
      _focusReportingGeneration++;
    }
    _mouseTracking = TerminalMouseTrackingMode.none;
    _mouseEncoding = TerminalMouseCoordinateEncoding.legacy;
    metadata.reset();
    desktopNotifications.reset();
    progress.reset();
    semanticPrompt.reset();
    _resetGeneration++;
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

  void _attachKittyImageObservers() {
    primary.attachMutationObserver(
      _TerminalKittyScreenMutationObserver(this, TerminalScreenKind.primary),
    );
    alternate.attachMutationObserver(
      _TerminalKittyScreenMutationObserver(this, TerminalScreenKind.alternate),
    );
  }

  bool _pruneKittyPlacements(TerminalScreenKind kind) {
    final TerminalKittyImageStore store = kittyImagesFor(kind);
    return store.removeUnresolvedPlacements(
          (TerminalKittyImagePlacement placement) =>
              _kittyPlacementScreenPosition(kind, placement),
        ) !=
        0;
  }

  TerminalKittyImagePlacementPosition? _kittyPlacementScreenPosition(
    TerminalScreenKind kind,
    TerminalKittyImagePlacement placement,
  ) {
    final TerminalViewportPosition? position = viewport.screenCellPositionOf(
      kind,
      TerminalLogicalAnchor(
        screenKind: kind,
        logicalLineId: placement.logicalLineId,
        logicalLineEpoch: placement.logicalLineEpoch,
        cellOffset: placement.logicalCellOffset,
      ),
    );
    return position == null
        ? null
        : TerminalKittyImagePlacementPosition(
            row: position.row,
            column: position.column,
          );
  }

  _KittyKeyboardState get _activeKittyKeyboard => switch (_activeKind) {
    TerminalScreenKind.primary => _primaryKittyKeyboard,
    TerminalScreenKind.alternate => _alternateKittyKeyboard,
  };
}

final class _TerminalKittyScreenMutationObserver
    implements TerminalScreenMutationObserver {
  _TerminalKittyScreenMutationObserver(this._screens, this._kind);

  final TerminalScreenSet _screens;
  final TerminalScreenKind _kind;
  List<_KittyPlacementBeforeScroll> _beforeScroll =
      const <_KittyPlacementBeforeScroll>[];

  @override
  void willScroll(
    TerminalScreen screen,
    TerminalScreenScrollMutation mutation,
  ) {
    final ({int width, int height})? cell = _screens.logicalCellSize;
    if (cell == null) {
      _beforeScroll = const <_KittyPlacementBeforeScroll>[];
      return;
    }
    final TerminalKittyImageStore store = _screens.kittyImagesFor(_kind);
    final List<_KittyPlacementBeforeScroll> captured =
        <_KittyPlacementBeforeScroll>[];
    for (final TerminalKittyImagePlacement placement
        in store.placementSnapshot()) {
      final TerminalKittyImage? image = store.imageById(placement.imageId);
      final TerminalKittyImagePlacementPosition? position = _screens
          ._kittyPlacementScreenPosition(_kind, placement);
      if (image == null ||
          image.resourceGeneration != placement.imageResourceGeneration ||
          position == null) {
        continue;
      }
      final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
        image: image,
        cellWidth: cell.width,
        cellHeight: cell.height,
      );
      captured.add(
        _KittyPlacementBeforeScroll(
          placement: placement,
          position: position,
          geometry: geometry,
        ),
      );
    }
    _beforeScroll = List<_KittyPlacementBeforeScroll>.unmodifiable(captured);
  }

  @override
  void didScroll(TerminalScreen screen, TerminalScreenScrollMutation mutation) {
    final TerminalKittyImageStore store = _screens.kittyImagesFor(_kind);
    final int beforeGeneration = store.stateGeneration;
    final ({int width, int height})? cell = _screens.logicalCellSize;
    final bool retainedFullScreenScroll =
        mutation.direction == TerminalScreenScrollDirection.up &&
        mutation.capturesScrollback &&
        mutation.top == 0 &&
        mutation.bottom == screen.rows - 1 &&
        mutation.left == 0 &&
        mutation.right == screen.columns - 1;
    if (cell != null && !retainedFullScreenScroll) {
      for (final _KittyPlacementBeforeScroll captured in _beforeScroll) {
        _reconcileAfterScroll(store, screen, mutation, cell, captured);
      }
    }
    _beforeScroll = const <_KittyPlacementBeforeScroll>[];
    _screens._pruneKittyPlacements(_kind);
    if (store.stateGeneration != beforeGeneration) {
      _screens._transitionGeneration++;
    }
  }

  void _reconcileAfterScroll(
    TerminalKittyImageStore store,
    TerminalScreen screen,
    TerminalScreenScrollMutation mutation,
    ({int width, int height}) cell,
    _KittyPlacementBeforeScroll captured,
  ) {
    final TerminalKittyImagePlacementPosition position = captured.position;
    final TerminalKittyImagePlacementGeometry geometry = captured.geometry;
    if (geometry.columns <= 0 || geometry.rows <= 0) return;
    final bool whollyInside =
        position.row >= mutation.top &&
        position.row + geometry.rows - 1 <= mutation.bottom &&
        position.column >= mutation.left &&
        position.column + geometry.columns - 1 <= mutation.right;
    int targetRow = position.row;
    var clipTopPixels = 0;
    var clipBottomPixels = 0;
    var targetOffsetY = geometry.cellOffsetY;
    if (whollyInside) {
      targetRow += mutation.direction == TerminalScreenScrollDirection.up
          ? -mutation.amount
          : mutation.amount;
      final int targetTopPixel = targetRow * cell.height + geometry.cellOffsetY;
      final int regionTopPixel = mutation.top * cell.height;
      final int regionBottomPixel = (mutation.bottom + 1) * cell.height;
      clipTopPixels = (regionTopPixel - targetTopPixel).clamp(
        0,
        geometry.pixelHeight,
      );
      clipBottomPixels =
          (targetTopPixel + geometry.pixelHeight - regionBottomPixel).clamp(
            0,
            geometry.pixelHeight,
          );
      if (clipTopPixels + clipBottomPixels >= geometry.pixelHeight) {
        store.removePlacement(captured.placement.placementGeneration);
        return;
      }
      final int visibleTopPixel = targetTopPixel + clipTopPixels;
      targetRow = visibleTopPixel ~/ cell.height;
      targetOffsetY = visibleTopPixel % cell.height;
    }
    if (targetRow < 0 ||
        targetRow >= screen.rows ||
        position.column < 0 ||
        position.column >= screen.columns) {
      if (whollyInside) {
        store.removePlacement(captured.placement.placementGeneration);
      }
      return;
    }
    final TerminalLogicalAnchor anchor = _screens.viewport.anchorAtScreenCell(
      _kind,
      targetRow,
      position.column,
    );
    store.reconcilePlacement(
      placementGeneration: captured.placement.placementGeneration,
      logicalLineId: anchor.logicalLineId,
      logicalLineEpoch: anchor.logicalLineEpoch,
      logicalCellOffset: anchor.cellOffset,
      cellOffsetX: geometry.cellOffsetX,
      cellOffsetY: targetOffsetY,
      cellWidth: cell.width,
      cellHeight: cell.height,
      clipTopPixels: clipTopPixels,
      clipBottomPixels: clipBottomPixels,
    );
  }

  @override
  void didEraseInDisplay(TerminalScreen screen, int mode) {
    if (mode != 2) return;
    final TerminalKittyImageStore store = _screens.kittyImagesFor(_kind);
    final int beforeGeneration = store.stateGeneration;
    final ({int width, int height})? cell = _screens.logicalCellSize;
    store.removePlacementsWhere(
      predicate: (TerminalKittyImagePlacement placement) {
        final TerminalKittyImagePlacementPosition? position = _screens
            ._kittyPlacementScreenPosition(_kind, placement);
        if (position == null) return false;
        if (cell == null) {
          return position.row >= 0 && position.row < screen.rows;
        }
        final TerminalKittyImage? image = store.imageById(placement.imageId);
        if (image == null ||
            image.resourceGeneration != placement.imageResourceGeneration) {
          return true;
        }
        final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
          image: image,
          cellWidth: cell.width,
          cellHeight: cell.height,
        );
        return position.row < screen.rows &&
            position.row + geometry.rows > 0 &&
            position.column < screen.columns &&
            position.column + geometry.columns > 0;
      },
      reclaimUnusedData: true,
    );
    if (store.stateGeneration != beforeGeneration) {
      _screens._transitionGeneration++;
    }
  }

  @override
  void didResetScreen(TerminalScreen screen) {
    final TerminalKittyImageStore store = _screens.kittyImagesFor(_kind);
    final int beforeGeneration = store.stateGeneration;
    store.clear();
    if (store.stateGeneration != beforeGeneration) {
      _screens._transitionGeneration++;
    }
  }
}

final class _KittyPlacementBeforeScroll {
  const _KittyPlacementBeforeScroll({
    required this.placement,
    required this.position,
    required this.geometry,
  });

  final TerminalKittyImagePlacement placement;
  final TerminalKittyImagePlacementPosition position;
  final TerminalKittyImagePlacementGeometry geometry;
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
