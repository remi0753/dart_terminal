/// Stable application identity for one logical terminal pane.
final class PaneId {
  const PaneId(this.value) : assert(value > 0);

  final int value;

  @override
  bool operator ==(Object other) => other is PaneId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// Identity for one process generation owned by a [PaneId].
final class TerminalSessionId {
  const TerminalSessionId({required this.paneId, required this.generation})
    : assert(generation > 0);

  final PaneId paneId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is TerminalSessionId &&
      other.paneId == paneId &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(paneId, generation);

  @override
  String toString() => '${paneId.value}:$generation';
}

enum TerminalPaneState {
  created,
  starting,
  running,
  confirmationPending,
  exited,
  failed,
  closing,
  closed,
}

enum TerminalPaneCloseDecision { confirmationRequired, allow }

/// The product-facing session surface owned by exactly one [TerminalPane].
abstract interface class TerminalPaneSession {
  TerminalSessionId get id;
  bool get isLive;

  Future<void> start();
  String render();
  void insertText(String value);
  void deleteBackward();
  void deleteForward();
  void moveLeft();
  void moveRight();
  void moveToStart();
  void moveToEnd();
  void previousHistory();
  void nextHistory();
  Future<void> submit();
  void interrupt();
  void suspend();
  void quitForegroundProcess();
  void sendEndOfFile();
  void resize({required int rows, required int columns});
  void showCloseConfirmation();
  Future<void> dispose();
}

typedef TerminalPaneSessionFactory = TerminalPaneSession Function(
  TerminalSessionId id, {
  required void Function() onChanged,
  required void Function() onTerminated,
});

/// Application-owned collection that is the sole creator/remover of panes.
final class TerminalPaneOwner {
  TerminalPaneOwner({int initialPaneId = 0}) : _nextPaneId = initialPaneId {
    if (initialPaneId < 0 || initialPaneId >= 0x7fffffffffffffff) {
      throw ArgumentError.value(
        initialPaneId,
        'initialPaneId',
        'must leave room for a positive pane ID',
      );
    }
  }

  int _nextPaneId;
  final Map<PaneId, TerminalPane> _panes = <PaneId, TerminalPane>{};
  bool _disposed = false;

  int get livePaneCount => _panes.length;
  Iterable<PaneId> get paneIds => List<PaneId>.unmodifiable(_panes.keys);

  TerminalPane createPane({
    required TerminalPaneSessionFactory sessionFactory,
    required void Function() onChanged,
    required void Function() onExitRequested,
  }) {
    if (_disposed) {
      throw StateError('terminal pane owner is disposed');
    }
    if (_nextPaneId >= 0x7fffffffffffffff) {
      throw StateError('terminal pane ID space is exhausted');
    }
    final PaneId paneId = PaneId(++_nextPaneId);
    final TerminalSessionId sessionId = TerminalSessionId(
      paneId: paneId,
      generation: 1,
    );
    TerminalPane? pane;
    var pendingChange = false;
    var pendingTermination = false;
    final TerminalPaneSession session = sessionFactory(
      sessionId,
      onChanged: () {
        final TerminalPane? current = pane;
        if (current == null) {
          pendingChange = true;
        } else {
          current._handleSessionChanged();
        }
      },
      onTerminated: () {
        final TerminalPane? current = pane;
        if (current == null) {
          pendingTermination = true;
        } else {
          current._handleSessionTerminated();
        }
      },
    );
    if (session.id != sessionId) {
      throw StateError(
        'session ${session.id} does not belong to allocated pane $paneId',
      );
    }
    final TerminalPane createdPane = TerminalPane._(
      id: paneId,
      sessionId: sessionId,
      session: session,
      onChanged: onChanged,
      onExitRequested: onExitRequested,
    );
    pane = createdPane;
    if (pendingChange) {
      createdPane._handleSessionChanged();
    }
    if (pendingTermination) {
      createdPane._handleSessionTerminated();
    }
    _panes[paneId] = createdPane;
    return createdPane;
  }

  Future<void> disposePane(TerminalPane pane) async {
    final TerminalPane? owned = _panes[pane.id];
    if (!identical(owned, pane)) {
      throw StateError('pane ${pane.id} is not owned by this owner');
    }
    await pane.dispose();
    _panes.remove(pane.id);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final List<TerminalPane> panes = _panes.values.toList(growable: false);
    for (final TerminalPane pane in panes.reversed) {
      await pane.dispose();
    }
    _panes.clear();
  }
}

/// Owns one session generation and the user-visible close state for one pane.
final class TerminalPane {
  TerminalPane._({
    required this.id,
    required this.sessionId,
    required TerminalPaneSession session,
    required void Function() onChanged,
    required void Function() onExitRequested,
  }) : _session = session,
       _onChanged = onChanged,
       _onExitRequested = onExitRequested;

  final PaneId id;
  final TerminalSessionId sessionId;
  final TerminalPaneSession _session;
  final void Function() _onChanged;
  final void Function() _onExitRequested;

  TerminalPaneState _state = TerminalPaneState.created;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;

  TerminalPaneState get state => _state;
  bool get isLive => _session.isLive;
  bool get closeConfirmationPending =>
      _state == TerminalPaneState.confirmationPending;

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_state != TerminalPaneState.created) {
      throw StateError('pane $id cannot start from ${_state.name}');
    }
    _setState(TerminalPaneState.starting);
    try {
      await _session.start();
      if (_state == TerminalPaneState.starting) {
        _setState(
          _session.isLive
              ? TerminalPaneState.running
              : TerminalPaneState.exited,
        );
      }
    } on Object {
      if (_state != TerminalPaneState.closing &&
          _state != TerminalPaneState.closed) {
        _setState(TerminalPaneState.failed);
      }
      rethrow;
    }
  }

  String render() => _session.render();

  void insertText(String value) {
    _recordInteraction();
    _session.insertText(value);
  }

  void deleteBackward() {
    _recordInteraction();
    _session.deleteBackward();
  }

  void deleteForward() {
    _recordInteraction();
    _session.deleteForward();
  }

  void moveLeft() {
    _recordInteraction();
    _session.moveLeft();
  }

  void moveRight() {
    _recordInteraction();
    _session.moveRight();
  }

  void moveToStart() {
    _recordInteraction();
    _session.moveToStart();
  }

  void moveToEnd() {
    _recordInteraction();
    _session.moveToEnd();
  }

  void previousHistory() {
    _recordInteraction();
    _session.previousHistory();
  }

  void nextHistory() {
    _recordInteraction();
    _session.nextHistory();
  }

  Future<void> submit() {
    _recordInteraction();
    return _session.submit();
  }

  void interrupt() {
    _recordInteraction();
    _session.interrupt();
  }

  void suspend() {
    _recordInteraction();
    _session.suspend();
  }

  void quitForegroundProcess() {
    _recordInteraction();
    _session.quitForegroundProcess();
  }

  void sendEndOfFile() {
    _recordInteraction();
    _session.sendEndOfFile();
  }

  void resize({required int rows, required int columns}) {
    _session.resize(rows: rows, columns: columns);
  }

  TerminalPaneCloseDecision requestClose({bool force = false}) {
    if (_state == TerminalPaneState.closing ||
        _state == TerminalPaneState.closed) {
      return TerminalPaneCloseDecision.allow;
    }
    if (force || !_session.isLive) {
      _setState(TerminalPaneState.closing);
      return TerminalPaneCloseDecision.allow;
    }
    if (_state == TerminalPaneState.confirmationPending) {
      _setState(TerminalPaneState.closing);
      return TerminalPaneCloseDecision.allow;
    }
    _setState(TerminalPaneState.confirmationPending);
    _session.showCloseConfirmation();
    return TerminalPaneCloseDecision.confirmationRequired;
  }

  void cancelCloseConfirmation() {
    if (_state != TerminalPaneState.confirmationPending) {
      return;
    }
    _setState(
      _session.isLive ? TerminalPaneState.running : TerminalPaneState.exited,
    );
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_state == TerminalPaneState.closed) {
      return;
    }
    if (_state != TerminalPaneState.closing) {
      _setState(TerminalPaneState.closing);
    }
    try {
      await _session.dispose();
    } finally {
      _setState(TerminalPaneState.closed);
    }
  }

  void _recordInteraction() {
    cancelCloseConfirmation();
  }

  void _handleSessionChanged() {
    if (_state != TerminalPaneState.closed) {
      _onChanged();
    }
  }

  void _handleSessionTerminated() {
    if (_state == TerminalPaneState.closed ||
        _state == TerminalPaneState.closing) {
      return;
    }
    _setState(TerminalPaneState.exited);
    _onExitRequested();
  }

  void _setState(TerminalPaneState value) {
    if (_state == value) {
      return;
    }
    _state = value;
    _onChanged();
  }
}
