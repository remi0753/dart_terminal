enum TerminalMouseTrackingMode { none, x10, normal, buttonEvent, anyEvent }

enum TerminalMouseCoordinateEncoding { legacy, utf8, sgr, sgrPixels, urxvt }

/// Terminal-owned DEC mouse tracking and coordinate-encoding state.
final class TerminalMouseModes {
  const TerminalMouseModes({
    this.tracking = TerminalMouseTrackingMode.none,
    this.encoding = TerminalMouseCoordinateEncoding.legacy,
  });

  final TerminalMouseTrackingMode tracking;
  final TerminalMouseCoordinateEncoding encoding;

  bool get reportingEnabled => tracking != TerminalMouseTrackingMode.none;

  /// Returns the DECRQM state for recognized mouse modes, or null otherwise.
  bool? decPrivateModeState(int mode) => switch (mode) {
    9 => tracking == TerminalMouseTrackingMode.x10,
    1000 => tracking == TerminalMouseTrackingMode.normal,
    1002 => tracking == TerminalMouseTrackingMode.buttonEvent,
    1003 => tracking == TerminalMouseTrackingMode.anyEvent,
    1005 => encoding == TerminalMouseCoordinateEncoding.utf8,
    1006 => encoding == TerminalMouseCoordinateEncoding.sgr,
    1015 => encoding == TerminalMouseCoordinateEncoding.urxvt,
    1016 => encoding == TerminalMouseCoordinateEncoding.sgrPixels,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is TerminalMouseModes &&
      other.tracking == tracking &&
      other.encoding == encoding;

  @override
  int get hashCode => Object.hash(tracking, encoding);
}
