import 'package:dart_appkit/dart_appkit.dart';

import '../terminal_core/terminal_hyperlink.dart';
import '../terminal_core/terminal_screen_set.dart';

enum TerminalHyperlinkRouteDisposition { passThrough, consumed }

enum TerminalHyperlinkAction {
  none,
  armed,
  cancelled,
  blocked,
  opened,
  unavailable,
}

enum TerminalHyperlinkNoticeKind { blocked, unavailable }

final class TerminalHyperlinkRouteResult {
  const TerminalHyperlinkRouteResult._({
    required this.disposition,
    required this.action,
    required this.hyperlinkId,
  });

  const TerminalHyperlinkRouteResult.passThrough()
    : this._(
        disposition: TerminalHyperlinkRouteDisposition.passThrough,
        action: TerminalHyperlinkAction.none,
        hyperlinkId: 0,
      );

  const TerminalHyperlinkRouteResult.consumed(
    TerminalHyperlinkAction action,
    int hyperlinkId,
  ) : this._(
        disposition: TerminalHyperlinkRouteDisposition.consumed,
        action: action,
        hyperlinkId: hyperlinkId,
      );

  final TerminalHyperlinkRouteDisposition disposition;
  final TerminalHyperlinkAction action;
  final int hyperlinkId;

  bool get isConsumed =>
      disposition == TerminalHyperlinkRouteDisposition.consumed;
}

typedef TerminalHyperlinkHoverCellCallback = void Function(int row, int column);
typedef TerminalHyperlinkClearHoverCallback = void Function();
typedef TerminalHyperlinkOpenCallback = bool Function(AllowedExternalUrl url);
typedef TerminalHyperlinkNoticeCallback = void Function(
  TerminalHyperlinkNoticeKind kind,
);

/// Owns only deliberate Command-primary-clicks on current OSC 8 cells.
///
/// Hover remains observational and mouse-move events continue to the terminal
/// mouse router. Once a link press is armed, its drag/up sequence is consumed
/// so it cannot also become terminal input or a local selection gesture.
final class TerminalHyperlinkInteractionController {
  TerminalHyperlinkInteractionController({
    required this.viewport,
    required this.onHoverCell,
    required this.onClearHover,
    required this.onOpen,
    required this.onNotice,
  });

  final TerminalViewport viewport;
  final TerminalHyperlinkHoverCellCallback onHoverCell;
  final TerminalHyperlinkClearHoverCallback onClearHover;
  final TerminalHyperlinkOpenCallback onOpen;
  final TerminalHyperlinkNoticeCallback onNotice;

  int _pressedHyperlinkId = 0;
  TerminalLogicalAnchor? _pressedAnchor;
  bool _pressEligible = false;

  TerminalHyperlinkRouteResult route(
    AppKitMouseEvent event, {
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    final ({int row, int column})? cell = _cellAt(
      event,
      rows: rows,
      columns: columns,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
    if (cell == null) {
      onClearHover();
    } else {
      onHoverCell(cell.row, cell.column);
    }

    switch (event.kind) {
      case AppKitMouseEventKind.moved:
        return const TerminalHyperlinkRouteResult.passThrough();
      case AppKitMouseEventKind.down:
        _clearPress();
        if (!_isExactCommandPrimary(event) || cell == null) {
          return const TerminalHyperlinkRouteResult.passThrough();
        }
        final TerminalHyperlinkHit? hit = viewport.hitTestHyperlink(
          cell.row,
          cell.column,
        );
        if (hit == null) {
          return const TerminalHyperlinkRouteResult.passThrough();
        }
        _pressedHyperlinkId = hit.hyperlinkId;
        _pressedAnchor = viewport.anchorAt(hit.row, hit.column);
        _pressEligible = true;
        return TerminalHyperlinkRouteResult.consumed(
          TerminalHyperlinkAction.armed,
          hit.hyperlinkId,
        );
      case AppKitMouseEventKind.dragged:
        if (_pressedHyperlinkId == 0) {
          return const TerminalHyperlinkRouteResult.passThrough();
        }
        final int hyperlinkId = _pressedHyperlinkId;
        _pressEligible = false;
        return TerminalHyperlinkRouteResult.consumed(
          TerminalHyperlinkAction.cancelled,
          hyperlinkId,
        );
      case AppKitMouseEventKind.up:
        if (_pressedHyperlinkId == 0) {
          return const TerminalHyperlinkRouteResult.passThrough();
        }
        final int hyperlinkId = _pressedHyperlinkId;
        final TerminalLogicalAnchor? pressedAnchor = _pressedAnchor;
        final bool eligible = _pressEligible;
        _clearPress();
        if (!eligible || !_isExactCommandPrimary(event) || cell == null) {
          return TerminalHyperlinkRouteResult.consumed(
            TerminalHyperlinkAction.cancelled,
            hyperlinkId,
          );
        }
        final TerminalHyperlinkHit? hit = viewport.hitTestHyperlink(
          cell.row,
          cell.column,
        );
        if (hit == null || hit.hyperlinkId != hyperlinkId) {
          return TerminalHyperlinkRouteResult.consumed(
            TerminalHyperlinkAction.cancelled,
            hyperlinkId,
          );
        }
        final TerminalLogicalAnchor currentAnchor = viewport.anchorAt(
          hit.row,
          hit.column,
        );
        if (currentAnchor != pressedAnchor) {
          return TerminalHyperlinkRouteResult.consumed(
            TerminalHyperlinkAction.cancelled,
            hyperlinkId,
          );
        }
        final AllowedExternalUrl? target = AllowedExternalUrl.tryParse(hit.uri);
        if (target == null) {
          onNotice(TerminalHyperlinkNoticeKind.blocked);
          return TerminalHyperlinkRouteResult.consumed(
            TerminalHyperlinkAction.blocked,
            hyperlinkId,
          );
        }
        final bool opened = onOpen(target);
        if (!opened) {
          onNotice(TerminalHyperlinkNoticeKind.unavailable);
        }
        return TerminalHyperlinkRouteResult.consumed(
          opened
              ? TerminalHyperlinkAction.opened
              : TerminalHyperlinkAction.unavailable,
          hyperlinkId,
        );
    }
  }

  void cancelPress() => _clearPress();

  void _clearPress() {
    _pressedHyperlinkId = 0;
    _pressedAnchor = null;
    _pressEligible = false;
  }

  static bool _isExactCommandPrimary(AppKitMouseEvent event) =>
      event.button == 0 &&
      event.modifiers.bits == ModifierKeys.commandBit &&
      event.clickCount > 0;

  static ({int row, int column})? _cellAt(
    AppKitMouseEvent event, {
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    if (!event.x.isFinite ||
        !event.y.isFinite ||
        !cellWidth.isFinite ||
        !cellHeight.isFinite ||
        cellWidth <= 0 ||
        cellHeight <= 0 ||
        rows <= 0 ||
        columns <= 0) {
      return null;
    }
    final int row = (event.y / cellHeight).floor();
    final int column = (event.x / cellWidth).floor();
    if (row < 0 || row >= rows || column < 0 || column >= columns) {
      return null;
    }
    return (row: row, column: column);
  }
}
