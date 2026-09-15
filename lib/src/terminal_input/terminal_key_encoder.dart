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

enum TerminalOptionKeyBehavior { escape, text }

/// Bounded encoder for legacy xterm and progressive Kitty keyboard input.
///
/// An empty result means that this event has no terminal bytes. Progressive
/// modes are opt-in, and zero Kitty flags preserve the original legacy path.
final class TerminalKeyEncoder {
  TerminalKeyEncoder({
    this.maximumEncodedBytes =
        TerminalInputLimits.maximumEncodedBytesPerKeyEvent,
    this.optionKeyBehavior = TerminalOptionKeyBehavior.escape,
  }) {
    if (maximumEncodedBytes <= 0 ||
        maximumEncodedBytes >
            TerminalInputLimits.maximumEncodedBytesPerKeyEvent) {
      throw RangeError.range(
        maximumEncodedBytes,
        1,
        TerminalInputLimits.maximumEncodedBytesPerKeyEvent,
        'maximumEncodedBytes',
      );
    }
  }

  final int maximumEncodedBytes;
  final TerminalOptionKeyBehavior optionKeyBehavior;

  Uint8List encode(
    TerminalKeyEvent event, {
    TerminalKeyboardModes modes = const TerminalKeyboardModes(),
  }) {
    final TerminalKeyEvent effectiveEvent =
        optionKeyBehavior == TerminalOptionKeyBehavior.text &&
            event.modifiers.option
        ? TerminalKeyEvent(
            physicalKey: event.physicalKey,
            text: event.text,
            unmodifiedText: event.unmodifiedText,
            modifiers: TerminalKeyModifiers(
              capsLock: event.modifiers.capsLock,
              shift: event.modifiers.shift,
              control: event.modifiers.control,
              command: event.modifiers.command,
              numericPad: event.modifiers.numericPad,
              function: event.modifiers.function,
            ),
            eventType: event.eventType,
          )
        : event;

    final List<int>? kitty = _encodeKitty(effectiveEvent, modes);
    if (kitty != null) {
      return _bounded(kitty);
    }
    if (effectiveEvent.eventType == TerminalKeyEventType.release ||
        effectiveEvent.modifiers.command) {
      return Uint8List(0);
    }

    final List<int>? modifiedOther = _encodeModifyOtherKeys(
      effectiveEvent,
      modes.modifyOtherKeys,
    );
    if (modifiedOther != null) {
      return _bounded(modifiedOther);
    }

    final List<int>? special = _encodeSpecial(effectiveEvent, modes);
    if (special != null) {
      return _bounded(special);
    }

    if (effectiveEvent.modifiers.control) {
      final int? control = _controlByte(effectiveEvent.unmodifiedText);
      if (control != null) {
        return _bounded(<int>[
          if (effectiveEvent.modifiers.option) 0x1b,
          control,
        ]);
      }
    }

    final String printable = String.fromCharCodes(
      effectiveEvent.text.runes.where(
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
      if (effectiveEvent.modifiers.option) 0x1b,
      ...utf8.encode(printable),
    ]);
  }

  /// Returns null to continue through the byte-identical legacy path.
  /// An empty list suppresses an event which the active protocol cannot send.
  List<int>? _encodeKitty(TerminalKeyEvent event, TerminalKeyboardModes modes) {
    final int flags =
        modes.kittyKeyboardFlags & TerminalKeyboardModes.kittyKnownFlags;
    if (flags == 0) {
      return null;
    }

    final bool disambiguate =
        flags & TerminalKeyboardModes.kittyDisambiguateEscapeCodes != 0;
    final bool reportEvents =
        flags & TerminalKeyboardModes.kittyReportEventTypes != 0;
    final bool reportAlternates =
        flags & TerminalKeyboardModes.kittyReportAlternateKeys != 0;
    final bool reportAll =
        flags & TerminalKeyboardModes.kittyReportAllKeys != 0;
    final bool reportAssociated =
        reportAll &&
        flags & TerminalKeyboardModes.kittyReportAssociatedText != 0;
    final List<int>? associated =
        reportAssociated &&
            event.eventType != TerminalKeyEventType.release &&
            !event.modifiers.control &&
            !event.modifiers.option &&
            !event.modifiers.command
        ? _associatedTextCodePoints(event.text)
        : null;

    if (event.eventType == TerminalKeyEventType.release && !reportEvents) {
      return const <int>[];
    }

    final bool legacyResetKey =
        event.physicalKey == TerminalPhysicalKey.enter ||
        event.physicalKey == TerminalPhysicalKey.tab ||
        event.physicalKey == TerminalPhysicalKey.backspace;
    if (legacyResetKey && !reportAll) {
      return event.eventType == TerminalKeyEventType.release
          ? const <int>[]
          : null;
    }

    final bool protocolEncoding = disambiguate || reportEvents || reportAll;
    final _KittyKeyEncoding? functional = protocolEncoding
        ? _kittyFunctionalKey(event.physicalKey)
        : null;
    final int? textKey = _kittyTextKeyCode(event);
    final bool textNeedsEscape =
        reportAll ||
        (disambiguate &&
            _isLegacyAsciiTextKey(event.physicalKey) &&
            (event.modifiers.control ||
                event.modifiers.option ||
                event.modifiers.command));

    _KittyKeyEncoding? encoding = functional;
    var textEncoding = false;
    if (encoding == null && textNeedsEscape) {
      final int? keyCode =
          textKey ?? (associated != null && associated.isNotEmpty ? 0 : null);
      if (keyCode != null) {
        encoding = _KittyKeyEncoding.kitty(keyCode);
        textEncoding = true;
      }
    }

    if (encoding == null) {
      return event.eventType == TerminalKeyEventType.release
          ? const <int>[]
          : null;
    }

    String keyField = encoding.key.toString();
    if (textEncoding && reportAlternates && encoding.finalByte == 'u') {
      final int? shifted = event.modifiers.shift
          ? _kittyShiftedKeyCode(event)
          : null;
      final int? base = _baseLayoutKeyCode(event.physicalKey);
      final int? distinctShifted = shifted != null && shifted != encoding.key
          ? shifted
          : null;
      final int? distinctBase =
          base != null && base != encoding.key && base != distinctShifted
          ? base
          : null;
      if (distinctBase != null) {
        keyField = '$keyField:${distinctShifted ?? ''}:$distinctBase';
      } else if (distinctShifted != null) {
        keyField = '$keyField:$distinctShifted';
      }
    }

    final bool reportsEventType =
        reportEvents && event.eventType != TerminalKeyEventType.press;
    final int modifier = _kittyModifierParameter(
      event.modifiers,
      includeLocks: reportAll || !textEncoding,
    );
    final bool needsParameters =
        modifier != 1 || reportsEventType || associated != null;
    if (encoding.omitDefaultOne && !needsParameters) {
      keyField = '';
    }
    final StringBuffer body = StringBuffer(keyField);
    if (needsParameters) {
      body.write(';$modifier');
    }
    if (reportsEventType) {
      body
        ..write(':')
        ..write(switch (event.eventType) {
          TerminalKeyEventType.press => 1,
          TerminalKeyEventType.repeat => 2,
          TerminalKeyEventType.release => 3,
        });
    }
    if (associated != null) {
      body
        ..write(';')
        ..write(associated.join(':'));
    }
    body.write(encoding.finalByte);
    return _csi(body.toString());
  }

  List<int>? _encodeModifyOtherKeys(TerminalKeyEvent event, int state) {
    if (state <= 0 || state > 3) {
      return null;
    }
    final int? codePoint = _xtermOtherKeyCode(event);
    if (codePoint == null) {
      return null;
    }
    final TerminalKeyModifiers modifiers = event.modifiers;
    final bool applies = switch (state) {
      1 =>
        modifiers.option ||
            (modifiers.control && _controlByte(event.unmodifiedText) == null),
      2 => modifiers.hasXtermModifier,
      3 => true,
      _ => false,
    };
    if (!applies) {
      return null;
    }
    return _csi('27;${modifiers.xtermParameter};$codePoint~');
  }

  static _KittyKeyEncoding? _kittyFunctionalKey(TerminalPhysicalKey key) =>
      switch (key) {
        TerminalPhysicalKey.escape => _KittyKeyEncoding.kitty(27),
        TerminalPhysicalKey.enter => _KittyKeyEncoding.kitty(13),
        TerminalPhysicalKey.tab => _KittyKeyEncoding.kitty(9),
        TerminalPhysicalKey.backspace => _KittyKeyEncoding.kitty(127),
        TerminalPhysicalKey.insert => _KittyKeyEncoding.normal(2, '~'),
        TerminalPhysicalKey.deleteForward => _KittyKeyEncoding.normal(3, '~'),
        TerminalPhysicalKey.pageUp => _KittyKeyEncoding.normal(5, '~'),
        TerminalPhysicalKey.pageDown => _KittyKeyEncoding.normal(6, '~'),
        TerminalPhysicalKey.arrowUp => _KittyKeyEncoding.normal(
          1,
          'A',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.arrowDown => _KittyKeyEncoding.normal(
          1,
          'B',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.arrowRight => _KittyKeyEncoding.normal(
          1,
          'C',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.arrowLeft => _KittyKeyEncoding.normal(
          1,
          'D',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.home => _KittyKeyEncoding.normal(
          1,
          'H',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.end => _KittyKeyEncoding.normal(
          1,
          'F',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.f1 => _KittyKeyEncoding.normal(
          1,
          'P',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.f2 => _KittyKeyEncoding.normal(
          1,
          'Q',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.f3 => _KittyKeyEncoding.normal(13, '~'),
        TerminalPhysicalKey.f4 => _KittyKeyEncoding.normal(
          1,
          'S',
          omitDefaultOne: true,
        ),
        TerminalPhysicalKey.f5 => _KittyKeyEncoding.normal(15, '~'),
        TerminalPhysicalKey.f6 => _KittyKeyEncoding.normal(17, '~'),
        TerminalPhysicalKey.f7 => _KittyKeyEncoding.normal(18, '~'),
        TerminalPhysicalKey.f8 => _KittyKeyEncoding.normal(19, '~'),
        TerminalPhysicalKey.f9 => _KittyKeyEncoding.normal(20, '~'),
        TerminalPhysicalKey.f10 => _KittyKeyEncoding.normal(21, '~'),
        TerminalPhysicalKey.f11 => _KittyKeyEncoding.normal(23, '~'),
        TerminalPhysicalKey.f12 => _KittyKeyEncoding.normal(24, '~'),
        TerminalPhysicalKey.f13 => _KittyKeyEncoding.kitty(57376),
        TerminalPhysicalKey.f14 => _KittyKeyEncoding.kitty(57377),
        TerminalPhysicalKey.f15 => _KittyKeyEncoding.kitty(57378),
        TerminalPhysicalKey.f16 => _KittyKeyEncoding.kitty(57379),
        TerminalPhysicalKey.f17 => _KittyKeyEncoding.kitty(57380),
        TerminalPhysicalKey.f18 => _KittyKeyEncoding.kitty(57381),
        TerminalPhysicalKey.f19 => _KittyKeyEncoding.kitty(57382),
        TerminalPhysicalKey.f20 => _KittyKeyEncoding.kitty(57383),
        TerminalPhysicalKey.keypad0 => _KittyKeyEncoding.kitty(57399),
        TerminalPhysicalKey.keypad1 => _KittyKeyEncoding.kitty(57400),
        TerminalPhysicalKey.keypad2 => _KittyKeyEncoding.kitty(57401),
        TerminalPhysicalKey.keypad3 => _KittyKeyEncoding.kitty(57402),
        TerminalPhysicalKey.keypad4 => _KittyKeyEncoding.kitty(57403),
        TerminalPhysicalKey.keypad5 => _KittyKeyEncoding.kitty(57404),
        TerminalPhysicalKey.keypad6 => _KittyKeyEncoding.kitty(57405),
        TerminalPhysicalKey.keypad7 => _KittyKeyEncoding.kitty(57406),
        TerminalPhysicalKey.keypad8 => _KittyKeyEncoding.kitty(57407),
        TerminalPhysicalKey.keypad9 => _KittyKeyEncoding.kitty(57408),
        TerminalPhysicalKey.keypadDecimal => _KittyKeyEncoding.kitty(57409),
        TerminalPhysicalKey.keypadDivide => _KittyKeyEncoding.kitty(57410),
        TerminalPhysicalKey.keypadMultiply => _KittyKeyEncoding.kitty(57411),
        TerminalPhysicalKey.keypadSubtract => _KittyKeyEncoding.kitty(57412),
        TerminalPhysicalKey.keypadAdd => _KittyKeyEncoding.kitty(57413),
        TerminalPhysicalKey.keypadEnter => _KittyKeyEncoding.kitty(57414),
        TerminalPhysicalKey.keypadEquals => _KittyKeyEncoding.kitty(57415),
        TerminalPhysicalKey.jisKeypadComma => _KittyKeyEncoding.kitty(57416),
        _ => null,
      };

  static bool _isLegacyAsciiTextKey(TerminalPhysicalKey key) =>
      _baseLayoutKeyCode(key) != null;

  static int? _kittyTextKeyCode(TerminalKeyEvent event) {
    final int? candidate = _singlePrintableScalar(event.unmodifiedText);
    final int? base = _baseLayoutKeyCode(event.physicalKey);
    if (candidate == null) {
      return base;
    }
    if (!event.modifiers.shift) {
      return candidate;
    }

    final int? shiftedBase = _shiftedBaseLayoutKeyCode(event.physicalKey);
    if (base != null && (candidate == base || candidate == shiftedBase)) {
      return base;
    }
    final String lower = String.fromCharCode(candidate).toLowerCase();
    return _singlePrintableScalar(lower) ?? candidate;
  }

  static int? _kittyShiftedKeyCode(TerminalKeyEvent event) =>
      _singlePrintableScalar(event.text) ??
      _shiftedBaseLayoutKeyCode(event.physicalKey);

  static int? _xtermOtherKeyCode(TerminalKeyEvent event) {
    if (event.physicalKey == TerminalPhysicalKey.tab) {
      return 9;
    }
    if (!_isLegacyAsciiTextKey(event.physicalKey) &&
        event.physicalKey != TerminalPhysicalKey.section &&
        event.physicalKey != TerminalPhysicalKey.jisYen &&
        event.physicalKey != TerminalPhysicalKey.jisUnderscore &&
        event.physicalKey != TerminalPhysicalKey.unknown) {
      return null;
    }
    if (event.modifiers.shift) {
      return _singlePrintableScalar(event.text) ??
          _shiftedBaseLayoutKeyCode(event.physicalKey) ??
          _kittyTextKeyCode(event);
    }
    return _singlePrintableScalar(event.unmodifiedText) ??
        _baseLayoutKeyCode(event.physicalKey);
  }

  static int _kittyModifierParameter(
    TerminalKeyModifiers modifiers, {
    required bool includeLocks,
  }) =>
      1 +
      (modifiers.shift ? 1 : 0) +
      (modifiers.option ? 2 : 0) +
      (modifiers.control ? 4 : 0) +
      (modifiers.command ? 8 : 0) +
      (includeLocks && modifiers.capsLock ? 64 : 0);

  static List<int>? _associatedTextCodePoints(String text) {
    if (text.isEmpty) {
      return null;
    }
    final List<int> codePoints = text.runes.toList(growable: false);
    if (codePoints.any(
      (int scalar) =>
          scalar < 0x20 ||
          (scalar >= 0x7f && scalar <= 0x9f) ||
          (scalar >= 0xf700 && scalar <= 0xf8ff),
    )) {
      return null;
    }
    return codePoints;
  }

  static int? _singlePrintableScalar(String text) {
    final Iterator<int> iterator = text.runes.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    final int scalar = iterator.current;
    if (iterator.moveNext() ||
        scalar < 0x20 ||
        (scalar >= 0x7f && scalar <= 0x9f) ||
        (scalar >= 0xf700 && scalar <= 0xf8ff)) {
      return null;
    }
    return scalar;
  }

  static int? _baseLayoutKeyCode(TerminalPhysicalKey key) => switch (key) {
    TerminalPhysicalKey.keyA => 0x61,
    TerminalPhysicalKey.keyB => 0x62,
    TerminalPhysicalKey.keyC => 0x63,
    TerminalPhysicalKey.keyD => 0x64,
    TerminalPhysicalKey.keyE => 0x65,
    TerminalPhysicalKey.keyF => 0x66,
    TerminalPhysicalKey.keyG => 0x67,
    TerminalPhysicalKey.keyH => 0x68,
    TerminalPhysicalKey.keyI => 0x69,
    TerminalPhysicalKey.keyJ => 0x6a,
    TerminalPhysicalKey.keyK => 0x6b,
    TerminalPhysicalKey.keyL => 0x6c,
    TerminalPhysicalKey.keyM => 0x6d,
    TerminalPhysicalKey.keyN => 0x6e,
    TerminalPhysicalKey.keyO => 0x6f,
    TerminalPhysicalKey.keyP => 0x70,
    TerminalPhysicalKey.keyQ => 0x71,
    TerminalPhysicalKey.keyR => 0x72,
    TerminalPhysicalKey.keyS => 0x73,
    TerminalPhysicalKey.keyT => 0x74,
    TerminalPhysicalKey.keyU => 0x75,
    TerminalPhysicalKey.keyV => 0x76,
    TerminalPhysicalKey.keyW => 0x77,
    TerminalPhysicalKey.keyX => 0x78,
    TerminalPhysicalKey.keyY => 0x79,
    TerminalPhysicalKey.keyZ => 0x7a,
    TerminalPhysicalKey.digit0 => 0x30,
    TerminalPhysicalKey.digit1 => 0x31,
    TerminalPhysicalKey.digit2 => 0x32,
    TerminalPhysicalKey.digit3 => 0x33,
    TerminalPhysicalKey.digit4 => 0x34,
    TerminalPhysicalKey.digit5 => 0x35,
    TerminalPhysicalKey.digit6 => 0x36,
    TerminalPhysicalKey.digit7 => 0x37,
    TerminalPhysicalKey.digit8 => 0x38,
    TerminalPhysicalKey.digit9 => 0x39,
    TerminalPhysicalKey.grave => 0x60,
    TerminalPhysicalKey.minus => 0x2d,
    TerminalPhysicalKey.equal => 0x3d,
    TerminalPhysicalKey.leftBracket => 0x5b,
    TerminalPhysicalKey.rightBracket => 0x5d,
    TerminalPhysicalKey.backslash => 0x5c,
    TerminalPhysicalKey.semicolon => 0x3b,
    TerminalPhysicalKey.quote => 0x27,
    TerminalPhysicalKey.comma => 0x2c,
    TerminalPhysicalKey.period => 0x2e,
    TerminalPhysicalKey.slash => 0x2f,
    TerminalPhysicalKey.space => 0x20,
    _ => null,
  };

  static int? _shiftedBaseLayoutKeyCode(TerminalPhysicalKey key) =>
      switch (key) {
        TerminalPhysicalKey.keyA => 0x41,
        TerminalPhysicalKey.keyB => 0x42,
        TerminalPhysicalKey.keyC => 0x43,
        TerminalPhysicalKey.keyD => 0x44,
        TerminalPhysicalKey.keyE => 0x45,
        TerminalPhysicalKey.keyF => 0x46,
        TerminalPhysicalKey.keyG => 0x47,
        TerminalPhysicalKey.keyH => 0x48,
        TerminalPhysicalKey.keyI => 0x49,
        TerminalPhysicalKey.keyJ => 0x4a,
        TerminalPhysicalKey.keyK => 0x4b,
        TerminalPhysicalKey.keyL => 0x4c,
        TerminalPhysicalKey.keyM => 0x4d,
        TerminalPhysicalKey.keyN => 0x4e,
        TerminalPhysicalKey.keyO => 0x4f,
        TerminalPhysicalKey.keyP => 0x50,
        TerminalPhysicalKey.keyQ => 0x51,
        TerminalPhysicalKey.keyR => 0x52,
        TerminalPhysicalKey.keyS => 0x53,
        TerminalPhysicalKey.keyT => 0x54,
        TerminalPhysicalKey.keyU => 0x55,
        TerminalPhysicalKey.keyV => 0x56,
        TerminalPhysicalKey.keyW => 0x57,
        TerminalPhysicalKey.keyX => 0x58,
        TerminalPhysicalKey.keyY => 0x59,
        TerminalPhysicalKey.keyZ => 0x5a,
        TerminalPhysicalKey.digit0 => 0x29,
        TerminalPhysicalKey.digit1 => 0x21,
        TerminalPhysicalKey.digit2 => 0x40,
        TerminalPhysicalKey.digit3 => 0x23,
        TerminalPhysicalKey.digit4 => 0x24,
        TerminalPhysicalKey.digit5 => 0x25,
        TerminalPhysicalKey.digit6 => 0x5e,
        TerminalPhysicalKey.digit7 => 0x26,
        TerminalPhysicalKey.digit8 => 0x2a,
        TerminalPhysicalKey.digit9 => 0x28,
        TerminalPhysicalKey.grave => 0x7e,
        TerminalPhysicalKey.minus => 0x5f,
        TerminalPhysicalKey.equal => 0x2b,
        TerminalPhysicalKey.leftBracket => 0x7b,
        TerminalPhysicalKey.rightBracket => 0x7d,
        TerminalPhysicalKey.backslash => 0x7c,
        TerminalPhysicalKey.semicolon => 0x3a,
        TerminalPhysicalKey.quote => 0x22,
        TerminalPhysicalKey.comma => 0x3c,
        TerminalPhysicalKey.period => 0x3e,
        TerminalPhysicalKey.slash => 0x3f,
        TerminalPhysicalKey.space => 0x20,
        _ => null,
      };

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
        return modes.applicationEscape
            ? const <int>[0x1b, 0x4f, 0x5b]
            : const <int>[0x1b];
      case TerminalPhysicalKey.arrowUp:
        return _cursor('A', modifiers, modes);
      case TerminalPhysicalKey.arrowDown:
        return _cursor('B', modifiers, modes);
      case TerminalPhysicalKey.arrowRight:
        if (_isOptionWordNavigation(modifiers)) {
          return const <int>[0x1b, 0x66];
        }
        return _cursor('C', modifiers, modes);
      case TerminalPhysicalKey.arrowLeft:
        if (_isOptionWordNavigation(modifiers)) {
          return const <int>[0x1b, 0x62];
        }
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

  static bool _isOptionWordNavigation(TerminalKeyModifiers modifiers) =>
      modifiers.option &&
      !modifiers.shift &&
      !modifiers.control &&
      !modifiers.command;

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

final class _KittyKeyEncoding {
  const _KittyKeyEncoding._(
    this.key,
    this.finalByte, {
    this.omitDefaultOne = false,
  });

  const _KittyKeyEncoding.kitty(int key) : this._(key, 'u');

  const _KittyKeyEncoding.normal(
    int key,
    String finalByte, {
    bool omitDefaultOne = false,
  }) : this._(key, finalByte, omitDefaultOne: omitDefaultOne);

  final int key;
  final String finalByte;
  final bool omitDefaultOne;
}
