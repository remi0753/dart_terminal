import 'dart:async';
import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_appkit_policy.dart';
import 'terminal_core/terminal_osc52.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_osc52_projection.dart';

final class TerminalOsc52ConfirmationFocusTarget {
  const TerminalOsc52ConfirmationFocusTarget({
    required this.window,
    required this.view,
  });

  final Window window;
  final View view;
}

typedef TerminalOsc52ConfirmationFocusTargetProvider =
    TerminalOsc52ConfirmationFocusTarget? Function();
typedef TerminalOsc52ConfirmationResolver =
    TerminalOsc52ConfirmationDisposition Function(int requestId);
typedef TerminalOsc52ConfirmationErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Owns the transient native window for one exact pending OSC 52 request.
final class TerminalOsc52ConfirmationPresenter {
  TerminalOsc52ConfirmationPresenter({
    required TerminalOsc52ConfirmationFocusTargetProvider focusTarget,
    required TerminalOsc52ConfirmationResolver approve,
    required TerminalOsc52ConfirmationResolver deny,
    TerminalOsc52ConfirmationErrorHandler? onError,
  }) : _focusTarget = focusTarget,
       _approve = approve,
       _deny = deny,
       _onError = onError;

  final TerminalOsc52ConfirmationFocusTargetProvider _focusTarget;
  final TerminalOsc52ConfirmationResolver _approve;
  final TerminalOsc52ConfirmationResolver _deny;
  final TerminalOsc52ConfirmationErrorHandler? _onError;

  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  TerminalOsc52PendingRequest? _presented;
  int _presentationEpoch = 0;
  int _terminalResponderRestoreCount = 0;
  bool _disposed = false;

  bool get isOpen => _window != null && _presented != null;
  bool get isDisposed => _disposed;
  Window? get activeWindow => _window;
  String? get renderedText => _view?.text;
  TerminalOsc52PendingRequest? get presentedRequest => _presented;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;

  Future<void> show(TerminalOsc52PendingRequest pending) async {
    final int epoch = ++_presentationEpoch;
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_disposed || epoch != _presentationEpoch) return;
    final Window? existing = _window;
    if (existing != null) {
      _presented = pending;
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
        frame: const Rect.fromLTWH(240, 190, 640, 460),
        title: 'OSC 52 Clipboard Request',
        configuration: terminalWindowConfiguration,
      )..contentView = view;
      window
        ..keyEventRouting = KeyEventRouting.dartOnly
        ..defersCloseRequests = true;
      subscription = window.events.listen(
        _handleWindowEvent,
        onError: (Object error, StackTrace stackTrace) {
          _onError?.call(error, stackTrace);
        },
      );
      _view = view;
      _window = window;
      _subscription = subscription;
      _presented = pending;
      _render();
      window.show();
    } on Object {
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) window.close();
        window.dispose();
      }
      if (!view.isDisposed) view.dispose();
      _view = null;
      _window = null;
      _subscription = null;
      _presented = null;
      rethrow;
    }
  }

  Future<void> dismiss() {
    _presentationEpoch++;
    _presented = null;
    return _close(restoreTerminalFocus: true, closeWindow: true);
  }

  Future<void> dispose() {
    if (_disposed) return _closingFuture ?? Future<void>.value();
    _disposed = true;
    _presentationEpoch++;
    _presented = null;
    return _close(restoreTerminalFocus: false, closeWindow: true);
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case AppKitKeyEvent():
        _handleKey(event);
      case WindowCloseRequestedEvent():
        final Window? window = _window;
        if (window != null && !window.isClosed && !window.isDisposed) {
          window.replyToCloseRequest(event, allow: false);
        }
        _denyPresented();
      case WindowClosedEvent():
        _denyPresented();
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

  void _handleKey(AppKitKeyEvent event) {
    if (event.kind != AppKitKeyEventKind.down) return;
    final TerminalPhysicalKey key = TerminalAppKitKeyAdapter.adapt(event)
        .physicalKey;
    switch (key) {
      case TerminalPhysicalKey.enter:
      case TerminalPhysicalKey.keypadEnter:
        final TerminalOsc52PendingRequest? pending = _presented;
        if (pending != null) _approve(pending.id);
      case TerminalPhysicalKey.escape:
        _denyPresented();
      default:
        break;
    }
  }

  void _denyPresented() {
    final TerminalOsc52PendingRequest? pending = _presented;
    if (pending != null) _deny(pending.id);
  }

  void _render() {
    final TextView? view = _view;
    final TerminalOsc52PendingRequest? pending = _presented;
    if (view == null || view.isDisposed || pending == null) return;
    final TerminalOsc52Operation operation = pending.request.operation;
    final StringBuffer output = StringBuffer()
      ..writeln('OSC 52 Clipboard Request')
      ..writeln()
      ..writeln(
        'Pane ${pending.sessionId.paneId.value}  '
        'Session ${pending.sessionId.generation}  Request ${pending.id}',
      )
      ..writeln('Selection: ${jsonEncode(pending.request.selection)}')
      ..writeln(
        'Operation: ${switch (operation) {
          TerminalOsc52Operation.read => 'Read clipboard',
          TerminalOsc52Operation.write => 'Write clipboard (${pending.writeUtf8Bytes} UTF-8 bytes)',
          TerminalOsc52Operation.clear => 'Clear clipboard',
        }}',
      )
      ..writeln()
      ..writeln(switch (operation) {
        TerminalOsc52Operation.read =>
          'The focused terminal is requesting clipboard contents.',
        TerminalOsc52Operation.write =>
          'The focused terminal is requesting this exact text:',
        TerminalOsc52Operation.clear =>
          'The focused terminal is requesting destructive clipboard clear.',
      });
    if (pending.writeText != null) {
      output
        ..writeln()
        ..writeln(_safeJsonPreview(pending.writeText!));
    }
    output
      ..writeln()
      ..writeln('Return  Allow      Esc  Deny')
      ..write('You can change the matching clipboard policy in Settings.');
    view.text = output.toString();
  }

  static String _safeJsonPreview(String text) {
    final String encoded = jsonEncode(text);
    final StringBuffer escaped = StringBuffer();
    for (final int scalar in encoded.runes) {
      if ((scalar >= 0x200b && scalar <= 0x200f) ||
          (scalar >= 0x2028 && scalar <= 0x202e) ||
          (scalar >= 0x2066 && scalar <= 0x2069) ||
          scalar == 0xfeff) {
        escaped.write('\\u${scalar.toRadixString(16).padLeft(4, '0')}');
      } else {
        escaped.writeCharCode(scalar);
      }
    }
    return escaped.toString();
  }

  Future<void> _close({
    required bool restoreTerminalFocus,
    required bool closeWindow,
  }) {
    final Future<void>? existing = _closingFuture;
    if (existing != null) return existing;
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
          if (closeWindow && !window.isClosed) window.close();
          window.dispose();
        }
        if (view != null && !view.isDisposed) view.dispose();
        if (restoreTerminalFocus) {
          final TerminalOsc52ConfirmationFocusTarget? target = _focusTarget();
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
        _onError?.call(error, stackTrace);
      } finally {
        _closingFuture = null;
      }
    }();
    return completion.future;
  }
}
