/// Stable presentation phases for the singleton Quick Terminal.
enum TerminalQuickTerminalVisibility {
  hidden,
  showing,
  visible,
  hiding,
  disposed,
}

/// Immutable identity for one requested Quick Terminal visibility transition.
final class TerminalQuickTerminalTransition {
  const TerminalQuickTerminalTransition._({
    required this.generation,
    required this.targetVisible,
  });

  final int generation;
  final bool targetVisible;
}

/// Pure, generation-checked Quick Terminal presentation state.
///
/// Native animation and focus work may finish asynchronously. A newer request
/// supersedes the active transition, so completion from the old request cannot
/// mutate the current logical state.
final class TerminalQuickTerminalLifecycle {
  TerminalQuickTerminalVisibility _visibility =
      TerminalQuickTerminalVisibility.hidden;
  TerminalQuickTerminalTransition? _activeTransition;
  var _generation = 0;

  TerminalQuickTerminalVisibility get visibility => _visibility;
  TerminalQuickTerminalTransition? get activeTransition => _activeTransition;
  bool get isDisposed =>
      _visibility == TerminalQuickTerminalVisibility.disposed;
  bool get isTransitioning => _activeTransition != null;
  bool get isVisibleOrShowing => switch (_visibility) {
    TerminalQuickTerminalVisibility.showing ||
    TerminalQuickTerminalVisibility.visible => true,
    TerminalQuickTerminalVisibility.hidden ||
    TerminalQuickTerminalVisibility.hiding ||
    TerminalQuickTerminalVisibility.disposed => false,
  };

  TerminalQuickTerminalTransition requestToggle() {
    _requireLive();
    return requestVisibility(visible: !isVisibleOrShowing)!;
  }

  TerminalQuickTerminalTransition? requestAutohide({required bool enabled}) {
    _requireLive();
    if (!enabled || !isVisibleOrShowing) return null;
    return requestVisibility(visible: false);
  }

  TerminalQuickTerminalTransition? requestVisibility({required bool visible}) {
    _requireLive();
    if (_activeTransition == null && isVisibleOrShowing == visible) {
      return null;
    }
    final TerminalQuickTerminalTransition transition =
        TerminalQuickTerminalTransition._(
          generation: ++_generation,
          targetVisible: visible,
        );
    _activeTransition = transition;
    _visibility = visible
        ? TerminalQuickTerminalVisibility.showing
        : TerminalQuickTerminalVisibility.hiding;
    return transition;
  }

  /// Completes [transition], returning false when it has been superseded.
  bool complete(
    TerminalQuickTerminalTransition transition, {
    required bool succeeded,
  }) {
    _requireLive();
    if (!identical(_activeTransition, transition) ||
        transition.generation != _generation) {
      return false;
    }
    _activeTransition = null;
    final bool visible = succeeded
        ? transition.targetVisible
        : !transition.targetVisible;
    _visibility = visible
        ? TerminalQuickTerminalVisibility.visible
        : TerminalQuickTerminalVisibility.hidden;
    return true;
  }

  /// Invalidates in-flight native work and returns to a reusable hidden state.
  void resetHidden() {
    _requireLive();
    _generation++;
    _activeTransition = null;
    _visibility = TerminalQuickTerminalVisibility.hidden;
  }

  /// Invalidates every transition permanently. Repeated disposal is harmless.
  void dispose() {
    if (isDisposed) return;
    _generation++;
    _activeTransition = null;
    _visibility = TerminalQuickTerminalVisibility.disposed;
  }

  void _requireLive() {
    if (isDisposed) {
      throw StateError('Quick Terminal lifecycle is disposed');
    }
  }
}
