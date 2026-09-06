import 'dart:convert';
import 'dart:typed_data';

import '../terminal_core/terminal_mouse_modes.dart';
import 'terminal_mouse_event.dart';

final class TerminalMouseEncodingLimitException implements Exception {
  const TerminalMouseEncodingLimitException({
    required this.encoding,
    required this.column,
    required this.row,
    required this.maximumCoordinate,
  });

  final TerminalMouseCoordinateEncoding encoding;
  final int column;
  final int row;
  final int maximumCoordinate;

  @override
  String toString() =>
      'TerminalMouseEncodingLimitException: $encoding coordinate '
      '($column,$row) exceeds $maximumCoordinate';
}

/// Bounded xterm-compatible encoder for terminal-cell mouse events.
final class TerminalMouseEncoder {
  const TerminalMouseEncoder();

  static const int maximumPacketBytes = 64;
  static const int legacyMaximumCoordinate = 223;
  static const int utf8MaximumCoordinate = 2015;

  bool shouldReport(TerminalMouseEvent event, TerminalMouseModes modes) {
    switch (modes.tracking) {
      case TerminalMouseTrackingMode.none:
        return false;
      case TerminalMouseTrackingMode.x10:
        return event.kind == TerminalMouseEventKind.press;
      case TerminalMouseTrackingMode.normal:
        return event.kind != TerminalMouseEventKind.motion;
      case TerminalMouseTrackingMode.buttonEvent:
        return event.kind != TerminalMouseEventKind.motion ||
            event.button != TerminalMouseButton.none;
      case TerminalMouseTrackingMode.anyEvent:
        return true;
    }
  }

  Uint8List encode(TerminalMouseEvent event, TerminalMouseModes modes) {
    if (!shouldReport(event, modes)) return Uint8List(0);
    final int maximumCoordinate = switch (modes.encoding) {
      TerminalMouseCoordinateEncoding.legacy => legacyMaximumCoordinate,
      TerminalMouseCoordinateEncoding.utf8 => utf8MaximumCoordinate,
      TerminalMouseCoordinateEncoding.sgr ||
      TerminalMouseCoordinateEncoding.sgrPixels ||
      TerminalMouseCoordinateEncoding.urxvt =>
        TerminalMouseEvent.maximumCoordinate,
    };
    if (event.column > maximumCoordinate || event.row > maximumCoordinate) {
      throw TerminalMouseEncodingLimitException(
        encoding: modes.encoding,
        column: event.column,
        row: event.row,
        maximumCoordinate: maximumCoordinate,
      );
    }

    final int button = _buttonCode(event, modes.encoding);
    final Uint8List result = switch (modes.encoding) {
      TerminalMouseCoordinateEncoding.legacy => Uint8List.fromList(<int>[
        0x1b,
        0x5b,
        0x4d,
        button + 32,
        event.column + 32,
        event.row + 32,
      ]),
      TerminalMouseCoordinateEncoding.utf8 => Uint8List.fromList(<int>[
        0x1b,
        0x5b,
        0x4d,
        ...utf8.encode(String.fromCharCode(button + 32)),
        ...utf8.encode(String.fromCharCode(event.column + 32)),
        ...utf8.encode(String.fromCharCode(event.row + 32)),
      ]),
      TerminalMouseCoordinateEncoding.sgr ||
      TerminalMouseCoordinateEncoding.sgrPixels => _ascii(
        '\x1b[<$button;${event.column};${event.row}'
        '${event.kind == TerminalMouseEventKind.release ? 'm' : 'M'}',
      ),
      TerminalMouseCoordinateEncoding.urxvt => _ascii(
        '\x1b[${button + 32};${event.column};${event.row}M',
      ),
    };
    if (result.isEmpty || result.length > maximumPacketBytes) {
      throw StateError('mouse encoder violated its packet bound');
    }
    return result;
  }

  static int _buttonCode(
    TerminalMouseEvent event,
    TerminalMouseCoordinateEncoding encoding,
  ) {
    final int modifiers = event.modifiers.xtermCode;
    return switch (event.kind) {
      TerminalMouseEventKind.press => event.button.xtermCode + modifiers,
      TerminalMouseEventKind.release =>
        (encoding == TerminalMouseCoordinateEncoding.sgr ||
                    encoding == TerminalMouseCoordinateEncoding.sgrPixels
                ? event.button.xtermCode
                : TerminalMouseButton.none.xtermCode) +
            modifiers,
      TerminalMouseEventKind.motion => event.button.xtermCode + modifiers + 32,
    };
  }

  static Uint8List _ascii(String value) =>
      Uint8List.fromList(ascii.encode(value));
}
