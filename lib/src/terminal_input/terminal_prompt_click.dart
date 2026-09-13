import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';

import '../terminal_core/terminal_screen_set.dart';
import 'terminal_key_event.dart';
import 'terminal_mouse_event.dart';
import 'terminal_mouse_router.dart';
import 'terminal_selection_gesture.dart';

enum TerminalPromptClickOutcome {
  ignored,
  began,
  moved,
  noMovement,
  rejected,
  cancelled,
}

final class TerminalPromptClickUpdate {
  TerminalPromptClickUpdate._({
    required this.outcome,
    required this.consumed,
    required this.resolution,
    required Iterable<int> terminalBytes,
  }) : terminalBytes = List<int>.unmodifiable(terminalBytes);

  factory TerminalPromptClickUpdate.ignored() => TerminalPromptClickUpdate._(
    outcome: TerminalPromptClickOutcome.ignored,
    consumed: false,
    resolution: null,
    terminalBytes: const <int>[],
  );

  factory TerminalPromptClickUpdate.consumed(
    TerminalPromptClickOutcome outcome, {
    TerminalPromptCursorMoveResolution? resolution,
    Iterable<int> terminalBytes = const <int>[],
  }) => TerminalPromptClickUpdate._(
    outcome: outcome,
    consumed: true,
    resolution: resolution,
    terminalBytes: terminalBytes,
  );

  final TerminalPromptClickOutcome outcome;
  final bool consumed;
  final TerminalPromptCursorMoveResolution? resolution;
  final List<int> terminalBytes;
}

typedef TerminalPromptClickInputCallback = void Function(Uint8List bytes);

final class TerminalLocalGestureUpdate {
  const TerminalLocalGestureUpdate({
    required this.promptClick,
    required this.selection,
  });

  final TerminalPromptClickUpdate promptClick;
  final TerminalSelectionGestureUpdate? selection;

  bool get consumedByPromptClick => promptClick.consumed;
  bool get selectionChanged => selection?.changed ?? false;
}

/// Gives an exact Option-click or ordinary selection exactly one local owner.
final class TerminalLocalGestureController {
  TerminalLocalGestureController({
    required TerminalScreenSet screens,
    required TerminalPromptClickInputCallback onTerminalInput,
    TerminalSelectionGestureController? selection,
  }) : selection =
           selection ??
           TerminalSelectionGestureController(viewport: screens.viewport),
       promptClick = TerminalPromptClickController(
         screens: screens,
         onTerminalInput: onTerminalInput,
       );

  final TerminalSelectionGestureController selection;
  final TerminalPromptClickController promptClick;

  TerminalLocalGestureUpdate handle(TerminalLocalSelectionIntent intent) {
    final TerminalPromptClickUpdate prompt = promptClick.handle(intent);
    if (prompt.consumed) {
      final TerminalSelectionGestureUpdate? cleared =
          prompt.outcome == TerminalPromptClickOutcome.began
          ? selection.clear()
          : null;
      return TerminalLocalGestureUpdate(
        promptClick: prompt,
        selection: cleared,
      );
    }
    return TerminalLocalGestureUpdate(
      promptClick: prompt,
      selection: selection.handle(intent),
    );
  }

  TerminalLocalGestureUpdate cancelInteraction() {
    final TerminalPromptClickUpdate prompt = promptClick.cancelInteraction();
    final TerminalSelectionGestureUpdate selectionUpdate = selection
        .cancelInteraction();
    return TerminalLocalGestureUpdate(
      promptClick: prompt,
      selection: selectionUpdate,
    );
  }

  void dispose() => promptClick.dispose();
}

/// Owns one exact-Option click sequence and emits at most one bounded movement.
final class TerminalPromptClickController {
  TerminalPromptClickController({
    required this.screens,
    required this.onTerminalInput,
  });

  static const int maximumArrowCount =
      TerminalInputLimits.maximumEncodedBytesPerKeyEvent ~/ 3;

  final TerminalScreenSet screens;
  final TerminalPromptClickInputCallback onTerminalInput;
  _TerminalPromptClickSequence? _sequence;
  bool _disposed = false;

  bool get isActive => _sequence != null;

  TerminalPromptClickUpdate handle(TerminalLocalSelectionIntent intent) {
    if (_disposed) return TerminalPromptClickUpdate.ignored();
    return switch (intent.phase) {
      TerminalLocalSelectionPhase.begin => _begin(intent),
      TerminalLocalSelectionPhase.update => _update(intent),
      TerminalLocalSelectionPhase.end => _end(intent),
    };
  }

  TerminalPromptClickUpdate cancelInteraction() {
    if (_sequence == null) return TerminalPromptClickUpdate.ignored();
    _sequence = null;
    return TerminalPromptClickUpdate.consumed(
      TerminalPromptClickOutcome.cancelled,
    );
  }

  void dispose() {
    _disposed = true;
    _sequence = null;
  }

  TerminalPromptClickUpdate _begin(TerminalLocalSelectionIntent intent) {
    _sequence = null;
    if (!_isExactOptionClick(intent) ||
        intent.verticalEdge != TerminalPointerVerticalEdge.inside) {
      return TerminalPromptClickUpdate.ignored();
    }
    _sequence = _TerminalPromptClickSequence(
      cell: intent.cell,
      screenKind: screens.activeKind,
      transitionGeneration: screens.transitionGeneration,
      resetGeneration: screens.resetGeneration,
      screenGeneration: screens.activeScreen.generation,
      semanticGeneration: screens.semanticRangeSnapshot().generation,
      viewportOffset: screens.viewport.offset,
    );
    return TerminalPromptClickUpdate.consumed(TerminalPromptClickOutcome.began);
  }

  TerminalPromptClickUpdate _update(TerminalLocalSelectionIntent intent) {
    if (_sequence == null) return TerminalPromptClickUpdate.ignored();
    _sequence = null;
    return TerminalPromptClickUpdate.consumed(
      TerminalPromptClickOutcome.cancelled,
    );
  }

  TerminalPromptClickUpdate _end(TerminalLocalSelectionIntent intent) {
    final _TerminalPromptClickSequence? sequence = _sequence;
    if (sequence == null) return TerminalPromptClickUpdate.ignored();
    _sequence = null;
    if (!_isExactOptionClick(intent) ||
        intent.verticalEdge != TerminalPointerVerticalEdge.inside ||
        intent.cell != sequence.cell ||
        !_isCurrent(sequence)) {
      return TerminalPromptClickUpdate.consumed(
        TerminalPromptClickOutcome.cancelled,
      );
    }

    final TerminalPromptCursorMoveResolution resolution = screens
        .resolvePromptCursorMove(
          intent.cell.row,
          intent.cell.column,
          maxMovements: maximumArrowCount,
        );
    switch (resolution.disposition) {
      case TerminalPromptCursorMoveDisposition.noMovement:
        return TerminalPromptClickUpdate.consumed(
          TerminalPromptClickOutcome.noMovement,
          resolution: resolution,
        );
      case TerminalPromptCursorMoveDisposition.rejected:
        return TerminalPromptClickUpdate.consumed(
          TerminalPromptClickOutcome.rejected,
          resolution: resolution,
        );
      case TerminalPromptCursorMoveDisposition.move:
        final Uint8List bytes = _encode(resolution.plan!);
        onTerminalInput(bytes);
        return TerminalPromptClickUpdate.consumed(
          TerminalPromptClickOutcome.moved,
          resolution: resolution,
          terminalBytes: bytes,
        );
    }
  }

  bool _isCurrent(_TerminalPromptClickSequence sequence) =>
      screens.activeKind == sequence.screenKind &&
      screens.transitionGeneration == sequence.transitionGeneration &&
      screens.resetGeneration == sequence.resetGeneration &&
      screens.activeScreen.generation == sequence.screenGeneration &&
      screens.semanticRangeSnapshot().generation ==
          sequence.semanticGeneration &&
      screens.viewport.offset == sequence.viewportOffset;

  static bool _isExactOptionClick(TerminalLocalSelectionIntent intent) =>
      intent.button == TerminalMouseButton.left &&
      intent.clickCount == 1 &&
      intent.modifiers.bits == ModifierKeys.optionBit;

  Uint8List _encode(TerminalPromptCursorMovePlan plan) {
    if (plan.count > maximumArrowCount) {
      throw StateError('prompt click movement exceeds the input byte bound');
    }
    final bool application = screens.keyboardModes.applicationCursorKeys;
    final int finalByte =
        plan.direction == TerminalPromptCursorMoveDirection.left ? 0x44 : 0x43;
    final Uint8List bytes = Uint8List(plan.encodedByteCount);
    for (var offset = 0; offset < bytes.length; offset += 3) {
      bytes[offset] = 0x1b;
      bytes[offset + 1] = application ? 0x4f : 0x5b;
      bytes[offset + 2] = finalByte;
    }
    if (bytes.length > TerminalInputLimits.maximumEncodedBytesPerKeyEvent) {
      throw StateError('prompt click encoded bytes exceed the input event cap');
    }
    return bytes;
  }
}

final class _TerminalPromptClickSequence {
  const _TerminalPromptClickSequence({
    required this.cell,
    required this.screenKind,
    required this.transitionGeneration,
    required this.resetGeneration,
    required this.screenGeneration,
    required this.semanticGeneration,
    required this.viewportOffset,
  });

  final TerminalPointerCell cell;
  final TerminalScreenKind screenKind;
  final int transitionGeneration;
  final int resetGeneration;
  final int screenGeneration;
  final int semanticGeneration;
  final int viewportOffset;
}
