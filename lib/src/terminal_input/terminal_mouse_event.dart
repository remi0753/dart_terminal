enum TerminalMouseEventKind { press, release, motion }

enum TerminalMouseButton {
  left(0),
  middle(1),
  right(2),
  none(3),
  wheelUp(64),
  wheelDown(65);

  const TerminalMouseButton(this.xtermCode);

  final int xtermCode;

  static TerminalMouseButton? fromAppKitButton(int button) => switch (button) {
    0 => TerminalMouseButton.left,
    1 => TerminalMouseButton.right,
    2 => TerminalMouseButton.middle,
    _ => null,
  };
}

final class TerminalMouseModifiers {
  const TerminalMouseModifiers({
    this.shift = false,
    this.option = false,
    this.control = false,
  });

  final bool shift;
  final bool option;
  final bool control;

  int get xtermCode => (shift ? 4 : 0) | (option ? 8 : 0) | (control ? 16 : 0);

  @override
  bool operator ==(Object other) =>
      other is TerminalMouseModifiers &&
      other.shift == shift &&
      other.option == option &&
      other.control == control;

  @override
  int get hashCode => Object.hash(shift, option, control);
}

/// One normalized, 1-based terminal cell or physical-pixel mouse event.
final class TerminalMouseEvent {
  TerminalMouseEvent({
    required this.kind,
    required this.button,
    required this.column,
    required this.row,
    this.modifiers = const TerminalMouseModifiers(),
  }) {
    RangeError.checkValueInInterval(column, 1, maximumCoordinate, 'column');
    RangeError.checkValueInInterval(row, 1, maximumCoordinate, 'row');
    if (kind != TerminalMouseEventKind.motion &&
        button == TerminalMouseButton.none) {
      throw ArgumentError('press/release events require a physical button');
    }
  }

  static const int maximumCellCoordinate = 4096;
  static const int maximumCoordinate = 65535;

  /// Converts a logical AppKit point to a 1-based physical pixel coordinate.
  ///
  /// Returns null rather than truncating if the bounded protocol coordinate
  /// cannot represent the point. Points outside the text grid are clamped to
  /// its nearest edge so drag/release behavior matches cell routing.
  static int? physicalPixelCoordinate({
    required double point,
    required double logicalExtent,
    required double backingScaleFactor,
  }) {
    if (!point.isFinite ||
        !logicalExtent.isFinite ||
        !backingScaleFactor.isFinite ||
        logicalExtent <= 0 ||
        backingScaleFactor <= 0) {
      throw ArgumentError(
        'mouse pixel geometry must be finite with positive extent and scale',
      );
    }
    final double boundedPoint = point.clamp(0, logicalExtent);
    final int coordinate = boundedPoint >= logicalExtent
        ? (logicalExtent * backingScaleFactor).ceil()
        : (boundedPoint * backingScaleFactor).floor() + 1;
    return coordinate < 1 || coordinate > maximumCoordinate ? null : coordinate;
  }

  final TerminalMouseEventKind kind;
  final TerminalMouseButton button;
  final int column;
  final int row;
  final TerminalMouseModifiers modifiers;
}
