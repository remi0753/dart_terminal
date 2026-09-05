part of 'terminal_screen_set.dart';

/// Navigable row projection over primary history plus the active screen.
///
/// Positive offsets and scroll deltas move toward older primary rows. An
/// alternate screen always projects its own grid at effective offset zero;
/// the primary offset remains available when primary ownership returns.
final class TerminalViewport {
  TerminalViewport._(this._screens)
    : _seenHistoryGeneration = _screens.scrollback.generation,
      _seenRowsAppended = _screens.scrollback.totalRowsAppended,
      _seenContinuityGeneration = _screens.scrollback.continuityGeneration,
      _seenPrimaryGeneration = _screens.primary.generation,
      _seenAlternateGeneration = _screens.alternate.generation,
      _seenTransitionGeneration = _screens.transitionGeneration;

  final TerminalScreenSet _screens;
  int _primaryOffset = 0;
  int _generation = 1;
  int _seenHistoryGeneration;
  int _seenRowsAppended;
  int _seenContinuityGeneration;
  int _seenPrimaryGeneration;
  int _seenAlternateGeneration;
  int _seenTransitionGeneration;

  int get rows {
    _sync();
    return _screens.activeScreen.rows;
  }

  int get columns {
    _sync();
    return _screens.activeScreen.columns;
  }

  int get offset {
    _sync();
    return _screens.usingAlternate ? 0 : _primaryOffset;
  }

  int get maximumOffset {
    _sync();
    return _screens.usingAlternate ? 0 : _screens.scrollback.length;
  }

  bool get atBottom => offset == 0;

  int get generation {
    _sync();
    return _generation;
  }

  int? get cursorRow {
    _sync();
    final TerminalScreen screen = _screens.activeScreen;
    if (_screens.usingAlternate) {
      return screen.cursorRow;
    }
    final int projected = _primaryOffset + screen.cursorRow;
    return projected < screen.rows ? projected : null;
  }

  int? get cursorColumn =>
      cursorRow == null ? null : _screens.activeScreen.cursorColumn;

  /// Moves by physical rows; positive values move toward older history.
  void scrollByRows(int rows) {
    _sync();
    if (_screens.usingAlternate || rows == 0) {
      return;
    }
    _setPrimaryOffset(_primaryOffset + rows);
  }

  /// Moves by active-grid heights; positive values move toward history.
  void scrollByPages(int pages) {
    _sync();
    if (_screens.usingAlternate || pages == 0) {
      return;
    }
    _setPrimaryOffset(_primaryOffset + pages * _screens.primary.rows);
  }

  void scrollToTop() {
    _sync();
    if (_screens.usingAlternate) {
      return;
    }
    _setPrimaryOffset(_screens.scrollback.length);
  }

  void scrollToBottom() {
    _sync();
    if (_screens.usingAlternate) {
      return;
    }
    _setPrimaryOffset(0);
  }

  bool isHistoryRow(int viewportRow) => _locate(viewportRow).history;

  /// Returns the stored source width for a projected physical row.
  int columnsAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.columnsAt(location.row)
        : _screens.activeScreen.columns;
  }

  int rowFlagsAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.rowFlagsAt(location.row)
        : _screens.activeScreen.rowFlagsAt(location.row);
  }

  int logicalLineIdAt(int viewportRow) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.logicalLineIdAt(location.row)
        : _screens.activeScreen.logicalLineIdAt(location.row);
  }

  int contentAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.contentAt(location.row, column)
        : _screens.activeScreen.contentAt(location.row, column);
  }

  int foregroundAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.foregroundAt(location.row, column)
        : _screens.activeScreen.foregroundAt(location.row, column);
  }

  int backgroundAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.backgroundAt(location.row, column)
        : _screens.activeScreen.backgroundAt(location.row, column);
  }

  int styleAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.styleAt(location.row, column)
        : _screens.activeScreen.styleAt(location.row, column);
  }

  int hyperlinkAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.hyperlinkAt(location.row, column)
        : _screens.activeScreen.hyperlinkAt(location.row, column);
  }

  int widthFlagsAt(int viewportRow, int column) {
    final _ViewportLocation location = _locate(viewportRow);
    return location.history
        ? _screens.scrollback.widthFlagsAt(location.row, column)
        : _screens.activeScreen.widthFlagsAt(location.row, column);
  }

  _ViewportLocation _locate(int viewportRow) {
    _sync();
    final TerminalScreen screen = _screens.activeScreen;
    if (viewportRow < 0 || viewportRow >= screen.rows) {
      throw RangeError.range(viewportRow, 0, screen.rows - 1, 'viewportRow');
    }
    if (_screens.usingAlternate) {
      return _ViewportLocation.screen(viewportRow);
    }
    final int historyLength = _screens.scrollback.length;
    final int combinedRow = historyLength - _primaryOffset + viewportRow;
    if (combinedRow < historyLength) {
      return _ViewportLocation.history(combinedRow);
    }
    return _ViewportLocation.screen(combinedRow - historyLength);
  }

  void _setPrimaryOffset(int value) {
    final int next = value.clamp(0, _screens.scrollback.length);
    if (_primaryOffset == next) {
      return;
    }
    _primaryOffset = next;
    _generation++;
  }

  void _sync() {
    final TerminalScrollback history = _screens.scrollback;
    final int appended = history.totalRowsAppended - _seenRowsAppended;
    bool offsetChanged = false;
    if (history.continuityGeneration != _seenContinuityGeneration) {
      offsetChanged = _primaryOffset != 0;
      _primaryOffset = 0;
    } else if (_primaryOffset > 0 && appended > 0) {
      final int next = (_primaryOffset + appended).clamp(0, history.length);
      offsetChanged = next != _primaryOffset;
      _primaryOffset = next;
    } else if (_primaryOffset > history.length) {
      _primaryOffset = history.length;
      offsetChanged = true;
    }

    final bool usingAlternate = _screens.usingAlternate;
    final bool historyChanged = history.generation != _seenHistoryGeneration;
    final bool primaryChanged =
        _screens.primary.generation != _seenPrimaryGeneration;
    final bool alternateChanged =
        _screens.alternate.generation != _seenAlternateGeneration;
    final bool transitionChanged =
        _screens.transitionGeneration != _seenTransitionGeneration;
    if (transitionChanged ||
        (usingAlternate ? alternateChanged : primaryChanged) ||
        (!usingAlternate && (historyChanged || offsetChanged))) {
      _generation++;
    }

    _seenHistoryGeneration = history.generation;
    _seenRowsAppended = history.totalRowsAppended;
    _seenContinuityGeneration = history.continuityGeneration;
    _seenPrimaryGeneration = _screens.primary.generation;
    _seenAlternateGeneration = _screens.alternate.generation;
    _seenTransitionGeneration = _screens.transitionGeneration;
  }
}

final class _ViewportLocation {
  const _ViewportLocation.history(this.row) : history = true;
  const _ViewportLocation.screen(this.row) : history = false;

  final bool history;
  final int row;
}
