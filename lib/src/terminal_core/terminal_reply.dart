import 'dart:typed_data';

import 'vt_parser.dart';

typedef TerminalReplyHandler = bool Function(Uint8List reply);

enum TerminalModeReportStatus {
  notRecognized(0),
  set(1),
  reset(2),
  permanentlySet(3),
  permanentlyReset(4);

  const TerminalModeReportStatus(this.protocolValue);

  final int protocolValue;
}

/// Encodes the bounded terminal replies supported by the Dart terminal core.
abstract final class TerminalReplyEncoder {
  static const int maximumReplyBytes = 64;
  static const int maximumCoordinate = 65535;
  static const int maximumMode = 0x7fffffff;

  static Uint8List primaryDeviceAttributes() => Uint8List.fromList(const <int>[
    0x1b,
    0x5b,
    0x3f,
    0x36,
    0x32,
    0x3b,
    0x32,
    0x32,
    0x63,
  ]);

  static Uint8List secondaryDeviceAttributes() => Uint8List.fromList(
    const <int>[0x1b, 0x5b, 0x3e, 0x31, 0x3b, 0x30, 0x3b, 0x30, 0x63],
  );

  static Uint8List terminalStatusOk() =>
      Uint8List.fromList(const <int>[0x1b, 0x5b, 0x30, 0x6e]);

  static Uint8List xtgettcapNotFound() =>
      Uint8List.fromList(const <int>[0x1b, 0x50, 0x30, 0x2b, 0x72, 0x1b, 0x5c]);

  static Uint8List cursorPosition({
    required int row,
    required int column,
    bool decPrivate = false,
  }) {
    RangeError.checkValueInInterval(row, 1, maximumCoordinate, 'row');
    RangeError.checkValueInInterval(column, 1, maximumCoordinate, 'column');
    final _TerminalReplyBuilder builder = _TerminalReplyBuilder()
      ..csi(decPrivate ? 0x3f : null)
      ..decimal(row)
      ..byte(0x3b)
      ..decimal(column)
      ..byte(0x52);
    return builder.finish();
  }

  static Uint8List modeReport({
    required int mode,
    required TerminalModeReportStatus status,
    bool decPrivate = false,
  }) {
    RangeError.checkValueInInterval(mode, 0, maximumMode, 'mode');
    final _TerminalReplyBuilder builder = _TerminalReplyBuilder()
      ..csi(decPrivate ? 0x3f : null)
      ..decimal(mode)
      ..byte(0x3b)
      ..decimal(status.protocolValue)
      ..byte(0x24)
      ..byte(0x79);
    return builder.finish();
  }

  static Uint8List paletteColor({
    required int index,
    required int color,
    required VtStringTerminator terminator,
  }) {
    RangeError.checkValueInInterval(index, 0, 255, 'index');
    final _TerminalReplyBuilder builder = _TerminalReplyBuilder()
      ..osc()
      ..decimal(4)
      ..byte(0x3b)
      ..decimal(index)
      ..byte(0x3b);
    _writeRgb(builder, color);
    builder.terminator(terminator);
    return builder.finish();
  }

  static Uint8List defaultColor({
    required int command,
    required int color,
    required VtStringTerminator terminator,
  }) {
    if (command != 10 && command != 11 && command != 12) {
      throw ArgumentError.value(
        command,
        'command',
        'must be OSC 10, OSC 11, or OSC 12',
      );
    }
    final _TerminalReplyBuilder builder = _TerminalReplyBuilder()
      ..osc()
      ..decimal(command)
      ..byte(0x3b);
    _writeRgb(builder, color);
    builder.terminator(terminator);
    return builder.finish();
  }

  static void _writeRgb(_TerminalReplyBuilder builder, int color) {
    if (color < 0x80000000 || color > 0x80ffffff) {
      throw ArgumentError.value(color, 'color', 'must be tagged direct sRGB');
    }
    builder
      ..bytes(const <int>[0x72, 0x67, 0x62, 0x3a])
      ..hex16(((color >> 16) & 0xff) * 0x101)
      ..byte(0x2f)
      ..hex16(((color >> 8) & 0xff) * 0x101)
      ..byte(0x2f)
      ..hex16((color & 0xff) * 0x101);
  }
}

final class _TerminalReplyBuilder {
  final Uint8List _bytes = Uint8List(TerminalReplyEncoder.maximumReplyBytes);
  int _length = 0;

  void csi(int? privateMarker) {
    bytes(const <int>[0x1b, 0x5b]);
    if (privateMarker != null) {
      byte(privateMarker);
    }
  }

  void osc() => bytes(const <int>[0x1b, 0x5d]);

  void terminator(VtStringTerminator value) {
    switch (value) {
      case VtStringTerminator.bell:
        byte(0x07);
      case VtStringTerminator.stringTerminator:
        bytes(const <int>[0x1b, 0x5c]);
    }
  }

  void decimal(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must not be negative');
    }
    var divisor = 1;
    while (divisor <= value ~/ 10) {
      divisor *= 10;
    }
    do {
      byte(0x30 + value ~/ divisor % 10);
      divisor ~/= 10;
    } while (divisor != 0);
  }

  void hex16(int value) {
    RangeError.checkValueInInterval(value, 0, 0xffff, 'value');
    for (int shift = 12; shift >= 0; shift -= 4) {
      final int digit = value >> shift & 0x0f;
      byte(digit < 10 ? 0x30 + digit : 0x61 + digit - 10);
    }
  }

  void bytes(List<int> values) {
    for (final int value in values) {
      byte(value);
    }
  }

  void byte(int value) {
    if (value < 0 || value > 0x7f) {
      throw ArgumentError.value(value, 'value', 'must be a 7-bit byte');
    }
    if (_length == _bytes.length) {
      throw StateError('terminal reply exceeds the fixed byte limit');
    }
    _bytes[_length++] = value;
  }

  Uint8List finish() => Uint8List.sublistView(_bytes, 0, _length);
}
