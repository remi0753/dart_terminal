import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'terminal_appkit_key_adapter.dart';
import 'terminal_key_event.dart';

typedef TerminalRawKeyDownHandler = void Function(TerminalKeyEvent event);
typedef TerminalPreeditUpdateHandler = void Function({
  required int generation,
  required String text,
  required int selectionLocation,
  required int selectionLength,
});
typedef TerminalPreeditClearHandler = void Function(int generation);
typedef TerminalCommittedTextHandler = void Function(String text);
typedef TerminalTextInputOverflowHandler = void Function(
  int clientId,
  int generation,
);

enum TerminalTextInputRouteDisposition {
  stale,
  rawKey,
  rawSuppressed,
  keyUpIgnored,
  preedit,
  committed,
  cancelled,
  overflowReset,
}

final class TerminalTextInputRouteResult {
  const TerminalTextInputRouteResult(this.disposition, this.generation);

  final TerminalTextInputRouteDisposition disposition;
  final int generation;
}

/// Single-delivery policy between native NSTextInputClient events and a pane.
///
/// Native already suppresses raw keys while marked text exists. This owner
/// repeats that invariant defensively, ignores key-up for terminal encoding,
/// and makes commit the only composition event that inserts text into the PTY.
final class TerminalTextInputEventRouter {
  TerminalTextInputEventRouter({
    required this.clientId,
    required this.onRawKeyDown,
    required this.onPreedit,
    required this.onClearPreedit,
    required this.onCommit,
    required this.onOverflow,
  }) {
    RangeError.checkValueInInterval(
      clientId,
      1,
      0x7fffffffffffffff,
      'clientId',
    );
  }

  final int clientId;
  final TerminalRawKeyDownHandler onRawKeyDown;
  final TerminalPreeditUpdateHandler onPreedit;
  final TerminalPreeditClearHandler onClearPreedit;
  final TerminalCommittedTextHandler onCommit;
  final TerminalTextInputOverflowHandler onOverflow;

  int _lastGeneration = 0;
  bool _compositionActive = false;

  int get lastGeneration => _lastGeneration;
  bool get isCompositionActive => _compositionActive;

  TerminalTextInputRouteResult route(TerminalTextInputEvent event) {
    if (event.clientId != clientId) {
      throw StateError(
        'text-input client ${event.clientId} does not match $clientId',
      );
    }
    if (event.generation <= 0 || event.generation > 0x7fffffffffffffff) {
      throw RangeError.range(
        event.generation,
        1,
        0x7fffffffffffffff,
        'event.generation',
      );
    }
    if (event.generation <= _lastGeneration) {
      return TerminalTextInputRouteResult(
        TerminalTextInputRouteDisposition.stale,
        event.generation,
      );
    }
    _lastGeneration = event.generation;

    return switch (event) {
      TerminalTextInputKeyEvent() => _routeKey(event),
      TerminalTextInputPreeditEvent() => _routePreedit(event),
      TerminalTextInputCommitEvent() => _routeCommit(event),
      TerminalTextInputCancelEvent() => _routeCancel(event),
      TerminalTextInputOverflowEvent() => _routeOverflow(event),
    };
  }

  TerminalTextInputRouteResult _routeKey(TerminalTextInputKeyEvent event) {
    if (event.kind == TerminalTextInputKeyKind.up) {
      return TerminalTextInputRouteResult(
        TerminalTextInputRouteDisposition.keyUpIgnored,
        event.generation,
      );
    }
    if (_compositionActive) {
      return TerminalTextInputRouteResult(
        TerminalTextInputRouteDisposition.rawSuppressed,
        event.generation,
      );
    }
    onRawKeyDown(
      TerminalAppKitKeyAdapter.adaptFields(
        keyCode: event.keyCode,
        modifiers: event.modifiers,
        isRepeat: event.isRepeat,
        characters: event.characters,
        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
      ),
    );
    return TerminalTextInputRouteResult(
      TerminalTextInputRouteDisposition.rawKey,
      event.generation,
    );
  }

  TerminalTextInputRouteResult _routePreedit(
    TerminalTextInputPreeditEvent event,
  ) {
    onPreedit(
      generation: event.generation,
      text: event.text,
      selectionLocation: event.selection.location,
      selectionLength: event.selection.length,
    );
    _compositionActive = true;
    return TerminalTextInputRouteResult(
      TerminalTextInputRouteDisposition.preedit,
      event.generation,
    );
  }

  TerminalTextInputRouteResult _routeCommit(
    TerminalTextInputCommitEvent event,
  ) {
    onClearPreedit(event.generation);
    _compositionActive = false;
    onCommit(event.text);
    return TerminalTextInputRouteResult(
      TerminalTextInputRouteDisposition.committed,
      event.generation,
    );
  }

  TerminalTextInputRouteResult _routeCancel(
    TerminalTextInputCancelEvent event,
  ) {
    onClearPreedit(event.generation);
    _compositionActive = false;
    return TerminalTextInputRouteResult(
      TerminalTextInputRouteDisposition.cancelled,
      event.generation,
    );
  }

  TerminalTextInputRouteResult _routeOverflow(
    TerminalTextInputOverflowEvent event,
  ) {
    onClearPreedit(event.generation);
    _compositionActive = false;
    onOverflow(event.clientId, event.generation);
    return TerminalTextInputRouteResult(
      TerminalTextInputRouteDisposition.overflowReset,
      event.generation,
    );
  }
}
