import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_action_registry.dart';
import 'terminal_appkit_policy.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_event.dart';

enum TerminalCommandPaletteKeyDisposition {
  ignored,
  updated,
  dismissed,
  invoked,
  overflow,
}

final class TerminalCommandPaletteKeyResult {
  const TerminalCommandPaletteKeyResult({
    required this.disposition,
    this.dispatchResult,
  });

  final TerminalCommandPaletteKeyDisposition disposition;
  final TerminalActionDispatchResult? dispatchResult;
}

/// Owns palette key editing independently from a terminal text-input client.
final class TerminalCommandPaletteKeyController {
  const TerminalCommandPaletteKeyController(this.state);

  final TerminalCommandPaletteState state;

  Future<TerminalCommandPaletteKeyResult> handle(AppKitKeyEvent event) async {
    if (!state.isOpen || event.kind != AppKitKeyEventKind.down) {
      return const TerminalCommandPaletteKeyResult(
        disposition: TerminalCommandPaletteKeyDisposition.ignored,
      );
    }
    final TerminalKeyEvent key = TerminalAppKitKeyAdapter.adapt(event);
    switch (key.physicalKey) {
      case TerminalPhysicalKey.escape:
        state.dismiss();
        return const TerminalCommandPaletteKeyResult(
          disposition: TerminalCommandPaletteKeyDisposition.dismissed,
        );
      case TerminalPhysicalKey.backspace:
        state.deleteLastScalar();
        return const TerminalCommandPaletteKeyResult(
          disposition: TerminalCommandPaletteKeyDisposition.updated,
        );
      case TerminalPhysicalKey.arrowUp:
        state.moveSelection(-1);
        return const TerminalCommandPaletteKeyResult(
          disposition: TerminalCommandPaletteKeyDisposition.updated,
        );
      case TerminalPhysicalKey.arrowDown:
        state.moveSelection(1);
        return const TerminalCommandPaletteKeyResult(
          disposition: TerminalCommandPaletteKeyDisposition.updated,
        );
      case TerminalPhysicalKey.enter:
      case TerminalPhysicalKey.keypadEnter:
        final TerminalActionDispatchResult result = await state
            .invokeSelected();
        return TerminalCommandPaletteKeyResult(
          disposition: TerminalCommandPaletteKeyDisposition.invoked,
          dispatchResult: result,
        );
      default:
        break;
    }
    if (key.modifiers.command ||
        key.modifiers.control ||
        key.text.isEmpty ||
        key.text.runes.any((int scalar) => scalar < 0x20 || scalar == 0x7f)) {
      return const TerminalCommandPaletteKeyResult(
        disposition: TerminalCommandPaletteKeyDisposition.ignored,
      );
    }
    try {
      state.append(key.text);
    } on TerminalActionLimitException {
      return const TerminalCommandPaletteKeyResult(
        disposition: TerminalCommandPaletteKeyDisposition.overflow,
      );
    }
    return const TerminalCommandPaletteKeyResult(
      disposition: TerminalCommandPaletteKeyDisposition.updated,
    );
  }
}

typedef TerminalCommandPaletteDispatchObserver = void Function(
  TerminalActionDispatchResult result,
);
typedef TerminalCommandPaletteErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);

final class TerminalCommandPaletteFocusTarget {
  const TerminalCommandPaletteFocusTarget({
    required this.window,
    required this.view,
  });

  final Window window;
  final View view;
}

typedef TerminalCommandPaletteFocusTargetProvider =
    TerminalCommandPaletteFocusTarget? Function();

/// Product-owned transient native command-palette window.
final class TerminalCommandPalettePresenter {
  TerminalCommandPalettePresenter({
    required this.dispatcher,
    required Window terminalWindow,
    required View terminalView,
    this.onDispatched,
    this.onError,
  }) : _focusTarget = (() => TerminalCommandPaletteFocusTarget(
         window: terminalWindow,
         view: terminalView,
       )),
       state = TerminalCommandPaletteState(dispatcher) {
    _keys = TerminalCommandPaletteKeyController(state);
  }

  TerminalCommandPalettePresenter.withFocusTarget({
    required this.dispatcher,
    required TerminalCommandPaletteFocusTargetProvider focusTarget,
    this.onDispatched,
    this.onError,
  }) : _focusTarget = focusTarget,
       state = TerminalCommandPaletteState(dispatcher) {
    _keys = TerminalCommandPaletteKeyController(state);
  }

  final TerminalActionDispatcher dispatcher;
  final TerminalCommandPaletteFocusTargetProvider _focusTarget;
  final TerminalCommandPaletteDispatchObserver? onDispatched;
  final TerminalCommandPaletteErrorObserver? onError;
  final TerminalCommandPaletteState state;

  late final TerminalCommandPaletteKeyController _keys;
  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  TerminalActionDispatchResult? _lastDispatchResult;
  int _dispatchCount = 0;
  int _terminalResponderRestoreCount = 0;
  bool _isDisposed = false;

  bool get isOpen => state.isOpen && _window != null;
  bool get isDisposed => _isDisposed;
  Window? get activeWindow => _window;
  String? get renderedText => _view?.text;
  TerminalActionDispatchResult? get lastDispatchResult => _lastDispatchResult;
  int get dispatchCount => _dispatchCount;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;

  /// Current terminal window restored after dismissing the palette.
  Window get terminalWindow => _requireFocusTarget().window;

  /// Current terminal view restored after dismissing the palette.
  View get terminalView => _requireFocusTarget().view;

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) {
      await closing;
    }
    if (_isDisposed) {
      throw StateError('command palette presenter is disposed');
    }
    final Window? existing = _window;
    if (existing != null) {
      state.refresh();
      _render();
      existing.show();
      return;
    }
    final TextView view = TextView(
      configuration: terminalCommandPaletteTextViewConfiguration,
    );
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      window = Window(
        frame: const Rect.fromLTWH(220, 180, 560, 420),
        title: 'Command Palette',
        configuration: terminalWindowConfiguration,
      )..contentView = view;
      window
        ..keyEventRouting = KeyEventRouting.dartOnly
        ..defersCloseRequests = true;
      subscription = window.events.listen(
        _handleWindowEvent,
        onError: (Object error, StackTrace stackTrace) {
          onError?.call(error, stackTrace);
        },
      );
      _view = view;
      _window = window;
      _subscription = subscription;
      state.open();
      _render();
      window.show();
    } on Object {
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) {
          window.close();
        }
        window.dispose();
      }
      if (!view.isDisposed) {
        view.dispose();
      }
      _view = null;
      _window = null;
      _subscription = null;
      if (state.isOpen) {
        state.dismiss();
      }
      rethrow;
    }
  }

  Future<void> dismiss() {
    if (_isDisposed && _window == null) {
      return Future<void>.value();
    }
    if (state.isOpen) {
      state.dismiss();
    }
    return _close(restoreTerminalFocus: true, closeWindow: true);
  }

  /// Refreshes availability after an external dispatcher transition.
  ///
  /// Opening the palette can itself be an action. Its first snapshot is then
  /// captured while the dispatcher is busy, so the menu owner calls this once
  /// that dispatch has completed.
  void refresh() {
    if (_isDisposed || !state.isOpen) return;
    state.refresh();
    _render();
  }

  Future<void> dispose() {
    if (_isDisposed) {
      return _closingFuture ?? Future<void>.value();
    }
    _isDisposed = true;
    if (state.isOpen) {
      state.dismiss();
    }
    return _close(restoreTerminalFocus: false, closeWindow: true);
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case AppKitKeyEvent():
        unawaited(_handleKey(event));
      case WindowCloseRequestedEvent():
        final Window? window = _window;
        if (window != null && !window.isClosed && !window.isDisposed) {
          window.replyToCloseRequest(event, allow: false);
        }
        unawaited(dismiss());
      case WindowClosedEvent():
        if (state.isOpen) {
          state.dismiss();
        }
        unawaited(_close(restoreTerminalFocus: true, closeWindow: false));
      case WindowResizedEvent() ||
          WindowFocusChangedEvent() ||
          WindowVisibilityChangedEvent() ||
          WindowOcclusionChangedEvent() ||
          WindowBackingScaleChangedEvent() ||
          WindowScreenChangedEvent() ||
          WindowFrameChangedEvent() ||
          WindowFullscreenChangedEvent() ||
          AppKitMouseEvent() ||
          AppKitScrollEvent():
        break;
    }
  }

  Future<void> _handleKey(AppKitKeyEvent event) async {
    try {
      final TerminalCommandPaletteKeyResult result = await _keys.handle(event);
      final TerminalActionDispatchResult? dispatchResult =
          result.dispatchResult;
      if (dispatchResult != null) {
        _lastDispatchResult = dispatchResult;
        _dispatchCount++;
        onDispatched?.call(dispatchResult);
      }
      if (result.disposition ==
              TerminalCommandPaletteKeyDisposition.dismissed ||
          !state.isOpen) {
        await _close(restoreTerminalFocus: true, closeWindow: true);
      } else if (result.disposition !=
          TerminalCommandPaletteKeyDisposition.ignored) {
        _render();
      }
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  void _render() {
    final TextView? view = _view;
    if (view == null || view.isDisposed || !state.isOpen) {
      return;
    }
    final StringBuffer output = StringBuffer()
      ..writeln('Command Palette')
      ..writeln('> ${state.query}')
      ..writeln();
    if (state.results.isEmpty) {
      output.writeln('  No matching actions');
    } else {
      for (var index = 0; index < state.results.length; index++) {
        final TerminalActionSnapshot snapshot = state.results[index];
        output
          ..write(index == state.selectedIndex ? '› ' : '  ')
          ..write(snapshot.definition.title);
        if (!snapshot.isEnabled) {
          output.write('  — Unavailable');
        }
        output.writeln();
      }
    }
    output
      ..writeln()
      ..write('↑↓ Select    Return Run    Esc Close');
    view.text = output.toString();
  }

  Future<void> _close({
    required bool restoreTerminalFocus,
    required bool closeWindow,
  }) {
    final Future<void>? existing = _closingFuture;
    if (existing != null) {
      return existing;
    }
    final Completer<void> completion = Completer<void>();
    _closingFuture = completion.future;
    () async {
      try {
        final StreamSubscription<WindowEvent>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
        final Window? window = _window;
        final TextView? view = _view;
        _window = null;
        _view = null;
        if (window != null && !window.isDisposed) {
          if (closeWindow && !window.isClosed) {
            window.close();
          }
          window.dispose();
        }
        if (view != null && !view.isDisposed) {
          view.dispose();
        }
        if (restoreTerminalFocus) {
          final TerminalCommandPaletteFocusTarget? target = _focusTarget();
          if (target != null &&
              !target.window.isClosed &&
              !target.window.isDisposed &&
              !target.view.isDisposed) {
            target.window.show();
            target.window.makeFirstResponder(target.view);
            _terminalResponderRestoreCount++;
          }
        }
        completion.complete();
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
        onError?.call(error, stackTrace);
      } finally {
        _closingFuture = null;
      }
    }();
    return completion.future;
  }

  TerminalCommandPaletteFocusTarget _requireFocusTarget() =>
      _focusTarget() ??
      (throw StateError('terminal command-palette focus target is absent'));
}
