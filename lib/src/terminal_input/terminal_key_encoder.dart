import 'dart:convert';
import 'dart:typed_data';

import '../terminal_core/terminal_keyboard_modes.dart';
import 'terminal_key_event.dart';

final class TerminalKeyEncodingLimitException implements Exception {
  const TerminalKeyEncodingLimitException({
    required this.actualBytes,
    required this.maximumBytes,
  });

  final int actualBytes;
  final int maximumBytes;

  @override
  String toString() =>
      'TerminalKeyEncodingLimitException: encoded input has $actualBytes bytes; '
      'maximum is $maximumBytes';
}

/// Bounded encoder for the Phase 5 legacy xterm keyboard contract.
///
/// Kitty keyboard and modifyOtherKeys are intentionally separate later
/// protocols. An empty result means that this event has no terminal bytes.
final class TerminalKeyEncoder {
  TerminalKeyEncoder({this.maximumEncodedBytes = 256}) {
    if (maximumEncodedBytes <= 0) {
      throw RangeError.value(
        maximumEncodedBytes,
        'maximumEncodedBytes',
        'must be positive',
      );
    }
  }

  final int maximumEncodedBytes;

  Uint8List encode(
    TerminalKeyEvent event, {
    TerminalKeyboardModes modes = const TerminalKeyboardModes(),
  }) {
    if (event.modifiers.command) {
      return Uint8List(0);
    }

    final List<int>? special = _encodeSpecial(event, modes);
    if (special != null) {
      return _bounded(special);
    }

    if (event.modifiers.control) {
      final int? control = _controlByte(event.unmodifiedText);
      if (control != null) {
        return _bounded(<int>[if (event.modifiers.option) 0x1b, control]);
      }
    }

    final String printable = String.fromCharCodes(
      event.text.runes.where(
        (int scalar) =>
            scalar >= 0x20 &&
            scalar != 0x7f &&
            (scalar < 0xf700 || scalar > 0xf8ff),
      ),
    );
    if (printable.isEmpty) {
      return Uint8List(0);
    }
    return _bounded(<int>[
      if (event.modifiers.option) 0x1b,
      ...utf8.encode(printable),
    ]);
  }

  List<int>? _encodeSpecial(
    TerminalKeyEvent event,
    TerminalKeyboardModes modes,
  ) {
    final TerminalKeyModifiers modifiers = event.modifiers;
    switch (event.physicalKey) {
      case TerminalPhysicalKey.enter:
      case TerminalPhysicalKey.keypadEnter when !modes.applicationKeypad:
        return <int>[if (modifiers.option) 0x1b, 0x0d];
      case TerminalPhysicalKey.tab:
        if (!modifiers.hasXtermModifier) {
          return const <int>[0x09];
        }
        if (modifiers.shift && !modifiers.control && !modifiers.option) {
          return const <int>[0x1b, 0x5b, 0x5a];
        }
        return _csi('1;${modifiers.xtermParameter}Z');
      case TerminalPhysicalKey.backspace:
        return <int>[
          if (modifiers.option) 0x1b,
          modifiers.control ? 0x08 : 0x7f,
        ];
      case TerminalPhysicalKey.escape:
        return const <int>[0x1b];
      case TerminalPhysicalKey.arrowUp:
        return _cursor('A', modifiers, modes);
      case TerminalPhysicalKey.arrowDown:
        return _cursor('B', modifiers, modes);
      case TerminalPhysicalKey.arrowRight:
        return _cursor('C', modifiers, modes);
      case TerminalPhysicalKey.arrowLeft:
        return _cursor('D', modifiers, modes);
      case TerminalPhysicalKey.home:
        return _cursor('H', modifiers, modes);
      case TerminalPhysicalKey.end:
        return _cursor('F', modifiers, modes);
      case TerminalPhysicalKey.insert:
        return _tilde(2, modifiers);
      case TerminalPhysicalKey.deleteForward:
        return _tilde(3, modifiers);
      case TerminalPhysicalKey.pageUp:
        return _tilde(5, modifiers);
      case TerminalPhysicalKey.pageDown:
        return _tilde(6, modifiers);
      case TerminalPhysicalKey.f1:
        return _functionSs3('P', modifiers);
      case TerminalPhysicalKey.f2:
        return _functionSs3('Q', modifiers);
      case TerminalPhysicalKey.f3:
        return _functionSs3('R', modifiers);
      case TerminalPhysicalKey.f4:
        return _functionSs3('S', modifiers);
      case TerminalPhysicalKey.f5:
        return _tilde(15, modifiers);
      case TerminalPhysicalKey.f6:
        return _tilde(17, modifiers);
      case TerminalPhysicalKey.f7:
        return _tilde(18, modifiers);
      case TerminalPhysicalKey.f8:
        return _tilde(19, modifiers);
      case TerminalPhysicalKey.f9:
        return _tilde(20, modifiers);
      case TerminalPhysicalKey.f10:
        return _tilde(21, modifiers);
      case TerminalPhysicalKey.f11:
        return _tilde(23, modifiers);
      case TerminalPhysicalKey.f12:
        return _tilde(24, modifiers);
      case TerminalPhysicalKey.f13:
        return _tilde(25, modifiers);
      case TerminalPhysicalKey.f14:
        return _tilde(26, modifiers);
      case TerminalPhysicalKey.f15:
        return _tilde(28, modifiers);
      case TerminalPhysicalKey.f16:
        return _tilde(29, modifiers);
      case TerminalPhysicalKey.f17:
        return _tilde(31, modifiers);
      case TerminalPhysicalKey.f18:
        return _tilde(32, modifiers);
      case TerminalPhysicalKey.f19:
        return _tilde(33, modifiers);
      case TerminalPhysicalKey.f20:
        return _tilde(34, modifiers);
      case TerminalPhysicalKey.keypad0:
      case TerminalPhysicalKey.keypad1:
      case TerminalPhysicalKey.keypad2:
      case TerminalPhysicalKey.keypad3:
      case TerminalPhysicalKey.keypad4:
      case TerminalPhysicalKey.keypad5:
      case TerminalPhysicalKey.keypad6:
      case TerminalPhysicalKey.keypad7:
      case TerminalPhysicalKey.keypad8:
      case TerminalPhysicalKey.keypad9:
      case TerminalPhysicalKey.keypadDecimal:
      case TerminalPhysicalKey.keypadEnter:
      case TerminalPhysicalKey.keypadAdd:
      case TerminalPhysicalKey.keypadSubtract:
      case TerminalPhysicalKey.keypadMultiply:
      case TerminalPhysicalKey.keypadDivide:
      case TerminalPhysicalKey.keypadEquals:
      case TerminalPhysicalKey.jisKeypadComma:
        return _keypad(event.physicalKey, modes);
      case TerminalPhysicalKey.unknown:
      case TerminalPhysicalKey.keyA:
      case TerminalPhysicalKey.keyB:
      case TerminalPhysicalKey.keyC:
      case TerminalPhysicalKey.keyD:
      case TerminalPhysicalKey.keyE:
      case TerminalPhysicalKey.keyF:
      case TerminalPhysicalKey.keyG:
      case TerminalPhysicalKey.keyH:
      case TerminalPhysicalKey.keyI:
      case TerminalPhysicalKey.keyJ:
      case TerminalPhysicalKey.keyK:
      case TerminalPhysicalKey.keyL:
      case TerminalPhysicalKey.keyM:
      case TerminalPhysicalKey.keyN:
      case TerminalPhysicalKey.keyO:
      case TerminalPhysicalKey.keyP:
      case TerminalPhysicalKey.keyQ:
      case TerminalPhysicalKey.keyR:
      case TerminalPhysicalKey.keyS:
      case TerminalPhysicalKey.keyT:
      case TerminalPhysicalKey.keyU:
      case TerminalPhysicalKey.keyV:
      case TerminalPhysicalKey.keyW:
      case TerminalPhysicalKey.keyX:
      case TerminalPhysicalKey.keyY:
      case TerminalPhysicalKey.keyZ:
      case TerminalPhysicalKey.digit0:
      case TerminalPhysicalKey.digit1:
      case TerminalPhysicalKey.digit2:
      case TerminalPhysicalKey.digit3:
      case TerminalPhysicalKey.digit4:
      case TerminalPhysicalKey.digit5:
      case TerminalPhysicalKey.digit6:
      case TerminalPhysicalKey.digit7:
      case TerminalPhysicalKey.digit8:
      case TerminalPhysicalKey.digit9:
      case TerminalPhysicalKey.grave:
      case TerminalPhysicalKey.minus:
      case TerminalPhysicalKey.equal:
      case TerminalPhysicalKey.leftBracket:
      case TerminalPhysicalKey.rightBracket:
      case TerminalPhysicalKey.backslash:
      case TerminalPhysicalKey.semicolon:
      case TerminalPhysicalKey.quote:
      case TerminalPhysicalKey.comma:
      case TerminalPhysicalKey.period:
      case TerminalPhysicalKey.slash:
      case TerminalPhysicalKey.section:
      case TerminalPhysicalKey.space:
      case TerminalPhysicalKey.jisYen:
      case TerminalPhysicalKey.jisUnderscore:
      case TerminalPhysicalKey.jisEisu:
      case TerminalPhysicalKey.jisKana:
        return null;
    }
  }

  List<int> _cursor(
    String finalByte,
    TerminalKeyModifiers modifiers,
    TerminalKeyboardModes modes,
  ) {
    if (modifiers.hasXtermModifier) {
      return _csi('1;${modifiers.xtermParameter}$finalByte');
    }
    return modes.applicationCursorKeys ? _ss3(finalByte) : _csi(finalByte);
  }

  List<int> _functionSs3(String finalByte, TerminalKeyModifiers modifiers) =>
      modifiers.hasXtermModifier
      ? _csi('1;${modifiers.xtermParameter}$finalByte')
      : _ss3(finalByte);

  List<int> _tilde(int code, TerminalKeyModifiers modifiers) => _csi(
    modifiers.hasXtermModifier
        ? '$code;${modifiers.xtermParameter}~'
        : '$code~',
  );

  List<int> _keypad(TerminalPhysicalKey key, TerminalKeyboardModes modes) {
    final String normal = switch (key) {
      TerminalPhysicalKey.keypad0 => '0',
      TerminalPhysicalKey.keypad1 => '1',
      TerminalPhysicalKey.keypad2 => '2',
      TerminalPhysicalKey.keypad3 => '3',
      TerminalPhysicalKey.keypad4 => '4',
      TerminalPhysicalKey.keypad5 => '5',
      TerminalPhysicalKey.keypad6 => '6',
      TerminalPhysicalKey.keypad7 => '7',
      TerminalPhysicalKey.keypad8 => '8',
      TerminalPhysicalKey.keypad9 => '9',
      TerminalPhysicalKey.keypadDecimal => '.',
      TerminalPhysicalKey.keypadEnter => '\r',
      TerminalPhysicalKey.keypadAdd => '+',
      TerminalPhysicalKey.keypadSubtract => '-',
      TerminalPhysicalKey.keypadMultiply => '*',
      TerminalPhysicalKey.keypadDivide => '/',
      TerminalPhysicalKey.keypadEquals => '=',
      TerminalPhysicalKey.jisKeypadComma => ',',
      _ => throw StateError('not a keypad key: $key'),
    };
    if (!modes.applicationKeypad) {
      return ascii.encode(normal);
    }
    final String application = switch (key) {
      TerminalPhysicalKey.keypad0 => 'p',
      TerminalPhysicalKey.keypad1 => 'q',
      TerminalPhysicalKey.keypad2 => 'r',
      TerminalPhysicalKey.keypad3 => 's',
      TerminalPhysicalKey.keypad4 => 't',
      TerminalPhysicalKey.keypad5 => 'u',
      TerminalPhysicalKey.keypad6 => 'v',
      TerminalPhysicalKey.keypad7 => 'w',
      TerminalPhysicalKey.keypad8 => 'x',
      TerminalPhysicalKey.keypad9 => 'y',
      TerminalPhysicalKey.keypadDecimal => 'n',
      TerminalPhysicalKey.keypadEnter => 'M',
      TerminalPhysicalKey.keypadAdd => 'k',
      TerminalPhysicalKey.keypadSubtract => 'm',
      TerminalPhysicalKey.keypadMultiply => 'j',
      TerminalPhysicalKey.keypadDivide => 'o',
      TerminalPhysicalKey.keypadEquals => 'X',
      TerminalPhysicalKey.jisKeypadComma => 'l',
      _ => throw StateError('not a keypad key: $key'),
    };
    return _ss3(application);
  }

  static int? _controlByte(String text) {
    if (text.isEmpty) {
      return null;
    }
    final int scalar = text.runes.first;
    if (scalar == 0x20 || scalar == 0x40) {
      return 0;
    }
    if (scalar >= 0x41 && scalar <= 0x5a) {
      return scalar - 0x40;
    }
    if (scalar >= 0x61 && scalar <= 0x7a) {
      return scalar - 0x60;
    }
    return switch (scalar) {
      0x5b => 0x1b,
      0x5c => 0x1c,
      0x5d => 0x1d,
      0x5e => 0x1e,
      0x5f => 0x1f,
      0x3f => 0x7f,
      _ => null,
    };
  }

  static List<int> _csi(String body) => <int>[
    0x1b,
    0x5b,
    ...ascii.encode(body),
  ];

  static List<int> _ss3(String finalByte) => <int>[
    0x1b,
    0x4f,
    ...ascii.encode(finalByte),
  ];

  Uint8List _bounded(List<int> bytes) {
    if (bytes.length > maximumEncodedBytes) {
      throw TerminalKeyEncodingLimitException(
        actualBytes: bytes.length,
        maximumBytes: maximumEncodedBytes,
      );
    }
    return Uint8List.fromList(bytes);
  }
}
