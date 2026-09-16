import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';

/// Orders native window notifications after asynchronous hierarchy mutations.
///
/// Retains only the latest notification of each kind for each live tab. Input
/// is never replayed into a different pane, and repeated Close during a mutation
/// is refused immediately rather than becoming a Close of its future neighbor.
final class TerminalWindowEventCoordinator {
  TerminalWindowEventCoordinator({
    required this.state,
    required void Function(TerminalTabId, WindowEvent) route,
    required void Function(TerminalTabId, WindowCloseRequestedEvent)
    refuseClose,
    required void Function(Object, StackTrace) onError,
  }) : _route = route,
       _refuseClose = refuseClose,
       _onError = onError;

  final TerminalApplicationState state;
  final void Function(TerminalTabId, WindowEvent) _route;
  final void Function(TerminalTabId, WindowCloseRequestedEvent) _refuseClose;
  final void Function(Object, StackTrace) _onError;
  final Map<(TerminalTabId, Type), WindowEvent> _pending =
      <(TerminalTabId, Type), WindowEvent>{};
  bool _draining = false;
  bool _disposed = false;

  int get pendingNotificationCount => _pending.length;

  void handle(TerminalTabId tabId, WindowEvent event) {
    if (_disposed || state.isDisposed || state.tabForId(tabId) == null) return;
    if (!state.mutationInProgress && !_draining) {
      _deliver(tabId, event);
      return;
    }
    if (event is WindowCloseRequestedEvent) {
      try {
        _refuseClose(tabId, event);
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
      return;
    }
    if (event is AppKitKeyEvent ||
        event is AppKitMouseEvent ||
        event is AppKitScrollEvent) {
      return;
    }
    final (TerminalTabId, Type) key = (tabId, event.runtimeType);
    // Updating insertion order preserves ordering between notification kinds.
    _pending.remove(key);
    _pending[key] = event;
    if (!_draining) unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (!_disposed && !state.isDisposed && _pending.isNotEmpty) {
        await state.mutationSettled;
        if (_disposed || state.isDisposed) break;
        if (state.mutationInProgress) continue;
        final MapEntry<(TerminalTabId, Type), WindowEvent> entry =
            _pending.entries.first;
        _pending.remove(entry.key);
        _deliver(entry.key.$1, entry.value);
      }
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    } finally {
      _draining = false;
      if (_disposed || state.isDisposed) _pending.clear();
    }
  }

  void _deliver(TerminalTabId tabId, WindowEvent event) {
    if (_disposed || state.isDisposed || state.tabForId(tabId) == null) return;
    try {
      _route(tabId, event);
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
