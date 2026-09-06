import 'dart:convert';
import 'dart:typed_data';

import 'terminal_mouse_modes.dart';
import 'terminal_reply.dart';
import 'terminal_screen.dart';
import 'terminal_screen_set.dart';
import 'terminal_style.dart';
import 'vt_parser.dart';
import 'vt_parser_table.dart';

/// Applies the currently supported VT screen actions to a [TerminalScreen].
///
/// Unsupported protocol strings are counted without throwing or corrupting the
/// visible screen. Supported query replies are emitted synchronously through a
/// bounded callback and never recursively enter the parser.
final class TerminalScreenParserSink
    implements VtParserSink, VtParserAsciiSink {
  TerminalScreenParserSink(
    TerminalScreen screen, {
    TerminalReplyHandler? onReply,
  }) : _screen = screen,
       screenSet = null,
       _onReply = onReply;

  TerminalScreenParserSink.forScreenSet(
    TerminalScreenSet screens, {
    TerminalReplyHandler? onReply,
  }) : _screen = null,
       screenSet = screens,
       _onReply = onReply;

  final TerminalScreen? _screen;
  final TerminalScreenSet? screenSet;
  final TerminalReplyHandler? _onReply;

  TerminalScreen get screen => screenSet?.activeScreen ?? _screen!;

  int _unsupportedControlCount = 0;
  int _unsupportedSequenceCount = 0;
  int _cancelCount = 0;
  int _limitCount = 0;
  int _malformedCount = 0;
  int _incompleteCount = 0;
  int _acceptedReplyCount = 0;
  int _rejectedReplyCount = 0;
  int _acceptedHyperlinkCount = 0;
  int _rejectedHyperlinkCount = 0;
  int _currentHyperlinkId = 0;
  final Uint16List _oscPaletteIndices = Uint16List(
    TerminalPalette.maxBatchEntries,
  );
  final Uint32List _oscPaletteColors = Uint32List(
    TerminalPalette.maxBatchEntries,
  );
  final Uint16List _oscPaletteQueryIndices = Uint16List(
    TerminalPalette.maxBatchEntries,
  );

  int get unsupportedControlCount => _unsupportedControlCount;
  int get unsupportedSequenceCount => _unsupportedSequenceCount;
  int get cancelCount => _cancelCount;
  int get limitCount => _limitCount;
  int get malformedCount => _malformedCount;
  int get incompleteCount => _incompleteCount;
  int get acceptedReplyCount => _acceptedReplyCount;
  int get rejectedReplyCount => _rejectedReplyCount;
  int get acceptedHyperlinkCount => _acceptedHyperlinkCount;
  int get rejectedHyperlinkCount => _rejectedHyperlinkCount;
  int get currentHyperlinkId => _currentHyperlinkId;

  @override
  void print(int scalar) {
    screen.printScalar(scalar, hyperlink: _currentHyperlinkId);
  }

  @override
  void printAscii(Uint8List bytes, int start, int end) {
    final TerminalScreen target = screen;
    for (var index = start; index < end; index++) {
      target.printScalar(bytes[index], hyperlink: _currentHyperlinkId);
    }
  }

  @override
  void execute(int controlByte) {
    screen.breakGraphemeSequence();
    switch (controlByte) {
      case 0x07:
        screen.ringVisualBell();
      case 0x08:
        screen.backspace();
      case 0x09:
        screen.horizontalTab();
      case 0x0a:
      case 0x0b:
      case 0x0c:
        screen.lineFeed();
      case 0x0d:
        screen.carriageReturn();
      case 0x84:
        screen.index();
      case 0x85:
        screen.nextLine();
      case 0x88:
        screen.setTabStop(screen.cursorColumn);
      case 0x8d:
        screen.reverseIndex();
      default:
        _unsupportedControlCount++;
    }
  }

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    screen.breakGraphemeSequence();
    if (sequence.intermediateCount != 0) {
      _unsupportedSequenceCount++;
      return;
    }
    switch (sequence.finalByte) {
      case 0x37:
        screen.saveCursor();
      case 0x38:
        screen.restoreCursor();
      case 0x3d:
        final TerminalScreenSet? screens = screenSet;
        if (screens == null) {
          _unsupportedSequenceCount++;
        } else {
          screens.setApplicationKeypad(true);
        }
      case 0x3e:
        final TerminalScreenSet? screens = screenSet;
        if (screens == null) {
          _unsupportedSequenceCount++;
        } else {
          screens.setApplicationKeypad(false);
        }
      case 0x44:
        screen.index();
      case 0x45:
        screen.nextLine();
      case 0x48:
        screen.setTabStop(screen.cursorColumn);
      case 0x4d:
        screen.reverseIndex();
      case 0x63:
        _currentHyperlinkId = 0;
        final TerminalScreenSet? screens = screenSet;
        if (screens == null) {
          screen.resetScreen();
        } else {
          screens.reset();
        }
      default:
        _unsupportedSequenceCount++;
    }
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    screen.breakGraphemeSequence();
    if (sequence.privateMarker == null &&
        sequence.intermediateCount == 0 &&
        sequence.finalByte == 0x6d) {
      _applySgr(sequence);
      return;
    }
    if (_hasSubparameters(sequence)) {
      _unsupportedSequenceCount++;
      return;
    }
    if (_dispatchCsiQuery(sequence)) {
      return;
    }
    if (sequence.privateMarker == 0x3f && sequence.intermediateCount == 0) {
      if (sequence.finalByte == 0x68 || sequence.finalByte == 0x6c) {
        _setPrivateModes(sequence, sequence.finalByte == 0x68);
        return;
      }
      _unsupportedSequenceCount++;
      return;
    }
    if (sequence.privateMarker != null) {
      _unsupportedSequenceCount++;
      return;
    }
    if (sequence.intermediateCount != 0) {
      if (sequence.intermediateCount == 1 &&
          sequence.intermediateAt(0) == 0x20 &&
          sequence.finalByte == 0x71) {
        _setCursorStyle(_parameter(sequence, 0, 0, zeroIsDefault: false));
        return;
      }
      _unsupportedSequenceCount++;
      return;
    }

    switch (sequence.finalByte) {
      case 0x40:
        screen.insertCharacters(_count(sequence));
      case 0x41:
        screen.moveCursorUp(_count(sequence));
      case 0x42:
        screen.moveCursorDown(_count(sequence));
      case 0x43:
        screen.moveCursorForward(_count(sequence));
      case 0x44:
        screen.moveCursorBackward(_count(sequence));
      case 0x45:
        screen.moveCursorNextLine(_count(sequence));
      case 0x46:
        screen.moveCursorPreviousLine(_count(sequence));
      case 0x47:
      case 0x60:
        screen.setCursorColumn(_oneBasedPosition(sequence, 0));
      case 0x48:
      case 0x66:
        screen.setCursorAddress(
          _oneBasedPosition(sequence, 0),
          _oneBasedPosition(sequence, 1),
        );
      case 0x49:
        screen.horizontalTab(_count(sequence));
      case 0x4a:
        _eraseDisplay(sequence);
      case 0x4b:
        _eraseLine(sequence);
      case 0x4c:
        screen.insertLines(_count(sequence));
      case 0x4d:
        screen.deleteLines(_count(sequence));
      case 0x50:
        screen.deleteCharacters(_count(sequence));
      case 0x53:
        screen.scrollUp(_count(sequence));
      case 0x54:
        screen.scrollDown(_count(sequence));
      case 0x58:
        screen.eraseCharacters(_count(sequence));
      case 0x5a:
        screen.backwardTab(_count(sequence));
      case 0x64:
        screen.setCursorRow(_oneBasedPosition(sequence, 0));
      case 0x67:
        _clearTabStops(sequence);
      case 0x68:
        _setAnsiModes(sequence, true);
      case 0x6c:
        _setAnsiModes(sequence, false);
      case 0x72:
        _setVerticalMargins(sequence);
      case 0x73:
        _setHorizontalMarginsOrSave(sequence);
      case 0x75:
        screen.restoreCursor();
      default:
        _unsupportedSequenceCount++;
    }
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    screen.breakGraphemeSequence();
    final int commandEnd = _findPayloadByte(sequence, 0, 0x3b);
    final int command = _parsePayloadDecimal(sequence, 0, commandEnd, 999);
    final bool hasPayload = commandEnd < sequence.payloadLength;
    final int payloadStart = hasPayload ? commandEnd + 1 : commandEnd;
    bool supported = false;
    switch (command) {
      case 4:
        supported = hasPayload && _applyOscPalette(sequence, payloadStart);
      case 8:
        supported = hasPayload && _applyOscHyperlink(sequence, payloadStart);
      case 10:
        supported =
            hasPayload &&
            _applyOscDefaultColor(sequence, payloadStart, foreground: true);
      case 11:
        supported =
            hasPayload &&
            _applyOscDefaultColor(sequence, payloadStart, foreground: false);
      case 104:
        supported = _applyOscPaletteReset(sequence, payloadStart, hasPayload);
      case 110:
        supported = _payloadIsEmpty(sequence, payloadStart, hasPayload);
        if (supported) {
          screen.resetDefaultForegroundColor();
        }
      case 111:
        supported = _payloadIsEmpty(sequence, payloadStart, hasPayload);
        if (supported) {
          screen.resetDefaultBackgroundColor();
        }
    }
    if (!supported) {
      _unsupportedSequenceCount++;
    }
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    screen.breakGraphemeSequence();
    _unsupportedSequenceCount++;
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    screen.breakGraphemeSequence();
    _unsupportedSequenceCount++;
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    screen.breakGraphemeSequence();
    if (state == VtParserState.oscString) {
      _currentHyperlinkId = 0;
    }
    _cancelCount++;
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    screen.breakGraphemeSequence();
    if (state == VtParserState.oscString) {
      _currentHyperlinkId = 0;
      _rejectedHyperlinkCount++;
    }
    _limitCount++;
  }

  @override
  void malformed(VtParserState state, int byte) {
    screen.breakGraphemeSequence();
    if (state == VtParserState.oscString) {
      _currentHyperlinkId = 0;
    }
    _malformedCount++;
  }

  @override
  void incomplete(VtParserState state) {
    screen.breakGraphemeSequence();
    if (state == VtParserState.oscString) {
      _currentHyperlinkId = 0;
    }
    _incompleteCount++;
  }

  bool _dispatchCsiQuery(VtSequenceHeader sequence) {
    if (sequence.intermediateCount == 0 && sequence.finalByte == 0x63) {
      if (sequence.privateMarker == null || sequence.privateMarker == 0x3e) {
        _reportDeviceAttributes(sequence);
        return true;
      }
      return false;
    }
    if (sequence.intermediateCount == 0 && sequence.finalByte == 0x6e) {
      if (sequence.privateMarker == null || sequence.privateMarker == 0x3f) {
        _reportDeviceStatus(sequence);
        return true;
      }
      return false;
    }
    if (sequence.intermediateCount == 1 &&
        sequence.intermediateAt(0) == 0x24 &&
        sequence.finalByte == 0x70 &&
        (sequence.privateMarker == null || sequence.privateMarker == 0x3f)) {
      _reportMode(sequence);
      return true;
    }
    return false;
  }

  void _reportDeviceAttributes(VtSequenceHeader sequence) {
    if (sequence.parameters.length > 1) {
      _unsupportedSequenceCount++;
      return;
    }
    final int parameter = sequence.parameters.length == 0
        ? 0
        : sequence.parameters.valueAt(0) ?? 0;
    if (parameter != 0) {
      _unsupportedSequenceCount++;
      return;
    }
    _emitReply(
      sequence.privateMarker == null
          ? TerminalReplyEncoder.primaryDeviceAttributes()
          : TerminalReplyEncoder.secondaryDeviceAttributes(),
    );
  }

  void _reportDeviceStatus(VtSequenceHeader sequence) {
    if (sequence.parameters.length != 1) {
      _unsupportedSequenceCount++;
      return;
    }
    final int? parameter = sequence.parameters.valueAt(0);
    if (sequence.privateMarker == null && parameter == 5) {
      _emitReply(TerminalReplyEncoder.terminalStatusOk());
      return;
    }
    if (parameter == 6) {
      final bool origin = screen.modeEnabled(TerminalScreenMode.origin);
      final int row = screen.cursorRow - (origin ? screen.topMargin : 0) + 1;
      final int column =
          screen.cursorColumn - (origin ? screen.activeLeftMargin : 0) + 1;
      _emitReply(
        TerminalReplyEncoder.cursorPosition(
          row: row,
          column: column,
          decPrivate: sequence.privateMarker == 0x3f,
        ),
      );
      return;
    }
    _unsupportedSequenceCount++;
  }

  void _reportMode(VtSequenceHeader sequence) {
    if (sequence.parameters.length != 1) {
      _unsupportedSequenceCount++;
      return;
    }
    final int? mode = sequence.parameters.valueAt(0);
    if (mode == null) {
      _unsupportedSequenceCount++;
      return;
    }
    final bool decPrivate = sequence.privateMarker == 0x3f;
    _emitReply(
      TerminalReplyEncoder.modeReport(
        mode: mode,
        status: _modeReportStatus(mode, decPrivate: decPrivate),
        decPrivate: decPrivate,
      ),
    );
  }

  TerminalModeReportStatus _modeReportStatus(
    int mode, {
    required bool decPrivate,
  }) {
    final bool? enabled;
    if (!decPrivate) {
      enabled = mode == 4
          ? screen.modeEnabled(TerminalScreenMode.insert)
          : null;
    } else {
      enabled = switch (mode) {
        1 => screenSet?.keyboardModes.applicationCursorKeys,
        5 => screen.modeEnabled(TerminalScreenMode.reverseVideo),
        6 => screen.modeEnabled(TerminalScreenMode.origin),
        7 => screen.modeEnabled(TerminalScreenMode.autoWrap),
        12 => screen.cursorBlinking,
        25 => screen.cursorVisible,
        47 || 1047 => screenSet?.usingAlternate,
        69 => screen.modeEnabled(TerminalScreenMode.horizontalMargins),
        1049 => screenSet?.mode1049Active,
        2004 => screenSet?.bracketedPasteMode,
        _ => screenSet?.mouseModes.decPrivateModeState(mode),
      };
    }
    if (enabled == null) {
      return TerminalModeReportStatus.notRecognized;
    }
    return enabled
        ? TerminalModeReportStatus.set
        : TerminalModeReportStatus.reset;
  }

  void _emitReply(Uint8List reply) {
    final TerminalReplyHandler? handler = _onReply;
    if (handler == null) {
      _rejectedReplyCount++;
      return;
    }
    try {
      if (handler(reply)) {
        _acceptedReplyCount++;
      } else {
        _rejectedReplyCount++;
      }
    } on Object {
      _rejectedReplyCount++;
    }
  }

  void _setAnsiModes(VtSequenceHeader sequence, bool enabled) {
    if (sequence.parameters.length == 0) {
      _unsupportedSequenceCount++;
      return;
    }
    for (int index = 0; index < sequence.parameters.length; index++) {
      final int? mode = sequence.parameters.valueAt(index);
      if (mode == 4) {
        screen.setMode(TerminalScreenMode.insert, enabled);
      } else {
        _unsupportedSequenceCount++;
      }
    }
  }

  bool _applyOscHyperlink(VtStringSequence sequence, int start) {
    final int parametersEnd = _findPayloadByte(sequence, start, 0x3b);
    if (parametersEnd >= sequence.payloadLength) {
      return _rejectHyperlink();
    }
    final int uriStart = parametersEnd + 1;
    if (uriStart == sequence.payloadLength) {
      if (parametersEnd != start) {
        return _rejectHyperlink();
      }
      _currentHyperlinkId = 0;
      _acceptedHyperlinkCount++;
      return true;
    }

    final ({bool valid, String? explicitId}) parameters =
        _parseOscHyperlinkParameters(sequence, start, parametersEnd);
    if (!parameters.valid) {
      return _rejectHyperlink();
    }
    final Uint8List uriBytes = Uint8List(sequence.payloadLength - uriStart);
    for (int index = 0; index < uriBytes.length; index++) {
      uriBytes[index] = sequence.payloadByteAt(uriStart + index);
    }
    final String uri;
    try {
      uri = utf8.decode(uriBytes, allowMalformed: false);
    } on FormatException {
      return _rejectHyperlink();
    }
    final int? hyperlink = screen.hyperlinkTable.tryIntern(
      uri: uri,
      explicitId: parameters.explicitId,
    );
    if (hyperlink == null) {
      return _rejectHyperlink();
    }
    _currentHyperlinkId = hyperlink;
    _acceptedHyperlinkCount++;
    return true;
  }

  ({bool valid, String? explicitId}) _parseOscHyperlinkParameters(
    VtStringSequence sequence,
    int start,
    int end,
  ) {
    if (start == end) {
      return (valid: true, explicitId: null);
    }
    String? explicitId;
    int offset = start;
    while (offset < end) {
      final int componentEnd = _findPayloadByte(sequence, offset, 0x3a, end);
      final int equals = _findPayloadByte(sequence, offset, 0x3d, componentEnd);
      if (equals == offset || equals >= componentEnd) {
        return (valid: false, explicitId: null);
      }
      for (int index = offset; index < equals; index++) {
        final int byte = sequence.payloadByteAt(index);
        final bool validKeyByte =
            (byte >= 0x30 && byte <= 0x39) ||
            (byte >= 0x41 && byte <= 0x5a) ||
            (byte >= 0x61 && byte <= 0x7a) ||
            byte == 0x2d ||
            byte == 0x5f;
        if (!validKeyByte) {
          return (valid: false, explicitId: null);
        }
      }
      for (int index = equals + 1; index < componentEnd; index++) {
        final int byte = sequence.payloadByteAt(index);
        if (byte < 0x21 || byte > 0x7e) {
          return (valid: false, explicitId: null);
        }
      }
      if (equals + 1 == componentEnd) {
        return (valid: false, explicitId: null);
      }
      final bool isId =
          equals - offset == 2 &&
          sequence.payloadByteAt(offset) == 0x69 &&
          sequence.payloadByteAt(offset + 1) == 0x64;
      if (isId) {
        if (explicitId != null) {
          return (valid: false, explicitId: null);
        }
        explicitId = String.fromCharCodes(
          List<int>.generate(
            componentEnd - equals - 1,
            (int index) => sequence.payloadByteAt(equals + 1 + index),
            growable: false,
          ),
        );
      }
      if (componentEnd + 1 == end) {
        return (valid: false, explicitId: null);
      }
      offset = componentEnd + 1;
    }
    return (valid: true, explicitId: explicitId);
  }

  bool _rejectHyperlink() {
    _currentHyperlinkId = 0;
    _rejectedHyperlinkCount++;
    return true;
  }

  bool _applyOscPalette(VtStringSequence sequence, int start) {
    int offset = start;
    int pairCount = 0;
    int mutationCount = 0;
    int queryCount = 0;
    while (offset < sequence.payloadLength) {
      if (pairCount >= TerminalPalette.maxBatchEntries) {
        return false;
      }
      final int indexEnd = _findPayloadByte(sequence, offset, 0x3b);
      if (indexEnd >= sequence.payloadLength) {
        return false;
      }
      final int index = _parsePayloadDecimal(
        sequence,
        offset,
        indexEnd,
        TerminalPalette.colorCount - 1,
      );
      final int colorStart = indexEnd + 1;
      final int colorEnd = _findPayloadByte(sequence, colorStart, 0x3b);
      if (index < 0 || colorStart >= colorEnd) {
        return false;
      }
      if (colorEnd - colorStart == 1 &&
          sequence.payloadByteAt(colorStart) == 0x3f) {
        _oscPaletteQueryIndices[queryCount++] = index;
      } else {
        final int color = _parseOscColor(sequence, colorStart, colorEnd);
        if (color < 0) {
          return false;
        }
        _oscPaletteIndices[mutationCount] = index;
        _oscPaletteColors[mutationCount] = color;
        mutationCount++;
      }
      pairCount++;
      offset = colorEnd < sequence.payloadLength
          ? colorEnd + 1
          : sequence.payloadLength;
    }
    if (pairCount == 0) {
      return false;
    }
    if (mutationCount != 0) {
      screen.setPaletteColors(
        _oscPaletteIndices,
        _oscPaletteColors,
        mutationCount,
      );
    }
    for (int query = 0; query < queryCount; query++) {
      final int index = _oscPaletteQueryIndices[query];
      _emitReply(
        TerminalReplyEncoder.paletteColor(
          index: index,
          color: screen.paletteColorAt(index),
          terminator: sequence.terminator,
        ),
      );
    }
    return true;
  }

  bool _applyOscPaletteReset(
    VtStringSequence sequence,
    int start,
    bool hasPayload,
  ) {
    if (!hasPayload || start == sequence.payloadLength) {
      screen.resetPalette();
      return true;
    }
    int offset = start;
    int count = 0;
    while (offset < sequence.payloadLength) {
      if (count >= TerminalPalette.maxBatchEntries) {
        return false;
      }
      final int end = _findPayloadByte(sequence, offset, 0x3b);
      final int index = _parsePayloadDecimal(
        sequence,
        offset,
        end,
        TerminalPalette.colorCount - 1,
      );
      if (index < 0) {
        return false;
      }
      _oscPaletteIndices[count++] = index;
      offset = end < sequence.payloadLength ? end + 1 : sequence.payloadLength;
    }
    screen.resetPaletteColors(_oscPaletteIndices, count);
    return true;
  }

  bool _applyOscDefaultColor(
    VtStringSequence sequence,
    int start, {
    required bool foreground,
  }) {
    if (start >= sequence.payloadLength ||
        _findPayloadByte(sequence, start, 0x3b) != sequence.payloadLength) {
      return false;
    }
    if (sequence.payloadLength - start == 1 &&
        sequence.payloadByteAt(start) == 0x3f) {
      _emitReply(
        TerminalReplyEncoder.defaultColor(
          command: foreground ? 10 : 11,
          color: foreground
              ? screen.defaultForegroundColor
              : screen.defaultBackgroundColor,
          terminator: sequence.terminator,
        ),
      );
      return true;
    }
    final int color = _parseOscColor(sequence, start, sequence.payloadLength);
    if (color < 0) {
      return false;
    }
    if (foreground) {
      screen.setDefaultForegroundColor(color);
    } else {
      screen.setDefaultBackgroundColor(color);
    }
    return true;
  }

  static bool _payloadIsEmpty(
    VtStringSequence sequence,
    int start,
    bool hasPayload,
  ) => !hasPayload || start == sequence.payloadLength;

  static int _parseOscColor(VtStringSequence sequence, int start, int end) {
    if (end <= start) {
      return -1;
    }
    if (end - start == 1 && sequence.payloadByteAt(start) == 0x3f) {
      return -1;
    }
    if (sequence.payloadByteAt(start) == 0x23) {
      final int digits = end - start - 1;
      if (digits < 3 || digits > 12 || digits % 3 != 0) {
        return -1;
      }
      final int width = digits ~/ 3;
      final int red = _parseHexComponent(sequence, start + 1, width);
      final int green = _parseHexComponent(sequence, start + 1 + width, width);
      final int blue = _parseHexComponent(
        sequence,
        start + 1 + width * 2,
        width,
      );
      if (red < 0 || green < 0 || blue < 0) {
        return -1;
      }
      return _directColor(
        _scaleHexComponent(red, width),
        _scaleHexComponent(green, width),
        _scaleHexComponent(blue, width),
      );
    }
    if (end - start < 9 ||
        sequence.payloadByteAt(start) != 0x72 ||
        sequence.payloadByteAt(start + 1) != 0x67 ||
        sequence.payloadByteAt(start + 2) != 0x62 ||
        sequence.payloadByteAt(start + 3) != 0x3a) {
      return -1;
    }
    final int firstSlash = _findPayloadByte(sequence, start + 4, 0x2f, end);
    if (firstSlash >= end) {
      return -1;
    }
    final int secondSlash = _findPayloadByte(
      sequence,
      firstSlash + 1,
      0x2f,
      end,
    );
    if (secondSlash >= end ||
        _findPayloadByte(sequence, secondSlash + 1, 0x2f, end) < end) {
      return -1;
    }
    final int redWidth = firstSlash - (start + 4);
    final int greenWidth = secondSlash - (firstSlash + 1);
    final int blueWidth = end - (secondSlash + 1);
    if (redWidth < 1 ||
        redWidth > 4 ||
        greenWidth < 1 ||
        greenWidth > 4 ||
        blueWidth < 1 ||
        blueWidth > 4) {
      return -1;
    }
    final int red = _parseHexComponent(sequence, start + 4, redWidth);
    final int green = _parseHexComponent(sequence, firstSlash + 1, greenWidth);
    final int blue = _parseHexComponent(sequence, secondSlash + 1, blueWidth);
    if (red < 0 || green < 0 || blue < 0) {
      return -1;
    }
    return _directColor(
      _scaleHexComponent(red, redWidth),
      _scaleHexComponent(green, greenWidth),
      _scaleHexComponent(blue, blueWidth),
    );
  }

  static int _parseHexComponent(
    VtStringSequence sequence,
    int start,
    int width,
  ) {
    int result = 0;
    for (int index = start; index < start + width; index++) {
      final int byte = sequence.payloadByteAt(index);
      final int digit;
      if (byte >= 0x30 && byte <= 0x39) {
        digit = byte - 0x30;
      } else if (byte >= 0x41 && byte <= 0x46) {
        digit = byte - 0x41 + 10;
      } else if (byte >= 0x61 && byte <= 0x66) {
        digit = byte - 0x61 + 10;
      } else {
        return -1;
      }
      result = (result << 4) | digit;
    }
    return result;
  }

  static int _scaleHexComponent(int value, int width) {
    final int maximum = (1 << (width * 4)) - 1;
    return (value * 255 + maximum ~/ 2) ~/ maximum;
  }

  static int _findPayloadByte(
    VtStringSequence sequence,
    int start,
    int byte, [
    int? limit,
  ]) {
    final int end = limit ?? sequence.payloadLength;
    for (int index = start; index < end; index++) {
      if (sequence.payloadByteAt(index) == byte) {
        return index;
      }
    }
    return end;
  }

  static int _parsePayloadDecimal(
    VtStringSequence sequence,
    int start,
    int end,
    int maximum,
  ) {
    if (end <= start) {
      return -1;
    }
    int value = 0;
    for (int index = start; index < end; index++) {
      final int byte = sequence.payloadByteAt(index);
      if (byte < 0x30 || byte > 0x39) {
        return -1;
      }
      value = value * 10 + byte - 0x30;
      if (value > maximum) {
        return -1;
      }
    }
    return value;
  }

  void _applySgr(VtSequenceHeader sequence) {
    int attributes = screen.currentStyleAttributes;
    int foreground = screen.currentForeground;
    int background = screen.currentBackground;
    if (sequence.parameters.length == 0) {
      screen.resetCurrentRendition();
      return;
    }

    int index = 0;
    while (index < sequence.parameters.length) {
      if (sequence.parameters.isSubparameter(index)) {
        _unsupportedSequenceCount++;
        index++;
        continue;
      }
      final int parameter = sequence.parameters.valueAt(index) ?? 0;
      switch (parameter) {
        case 0:
          attributes = 0;
          foreground = 0;
          background = 0;
        case 1:
          attributes |= TerminalStyleAttributes.bold;
        case 2:
          attributes |= TerminalStyleAttributes.faint;
        case 3:
          attributes |= TerminalStyleAttributes.italic;
        case 4:
          final _SgrUnderlineResult result = _parseSgrUnderline(
            sequence,
            index,
          );
          if (result.valid) {
            attributes = TerminalStyleAttributes.withUnderline(
              attributes,
              result.underline,
            );
          } else {
            _unsupportedSequenceCount++;
          }
          index = result.nextIndex;
          continue;
        case 5:
        case 6:
          attributes |= TerminalStyleAttributes.blink;
        case 7:
          attributes |= TerminalStyleAttributes.inverse;
        case 8:
          attributes |= TerminalStyleAttributes.conceal;
        case 9:
          attributes |= TerminalStyleAttributes.strike;
        case 21:
          attributes = TerminalStyleAttributes.withUnderline(
            attributes,
            TerminalUnderlineStyle.double,
          );
        case 22:
          attributes &=
              ~(TerminalStyleAttributes.bold | TerminalStyleAttributes.faint);
        case 23:
          attributes &= ~TerminalStyleAttributes.italic;
        case 24:
          attributes = TerminalStyleAttributes.withUnderline(
            attributes,
            TerminalUnderlineStyle.none,
          );
        case 25:
          attributes &= ~TerminalStyleAttributes.blink;
        case 27:
          attributes &= ~TerminalStyleAttributes.inverse;
        case 28:
          attributes &= ~TerminalStyleAttributes.conceal;
        case 29:
          attributes &= ~TerminalStyleAttributes.strike;
        case >= 30 && <= 37:
          foreground = parameter - 30 + 1;
        case 38:
        case 48:
          final _SgrColorResult result = _parseSgrColor(sequence, index);
          if (result.valid) {
            if (parameter == 38) {
              foreground = result.color;
            } else {
              background = result.color;
            }
          } else {
            _unsupportedSequenceCount++;
          }
          index = result.nextIndex;
          continue;
        case 39:
          foreground = 0;
        case >= 40 && <= 47:
          background = parameter - 40 + 1;
        case 49:
          background = 0;
        case >= 90 && <= 97:
          foreground = parameter - 90 + 9;
        case >= 100 && <= 107:
          background = parameter - 100 + 9;
        default:
          _unsupportedSequenceCount++;
      }
      index++;
    }
    try {
      screen.setCurrentRendition(
        foreground: foreground,
        background: background,
        styleAttributes: attributes,
      );
    } on StateError {
      _unsupportedSequenceCount++;
    }
  }

  _SgrUnderlineResult _parseSgrUnderline(
    VtSequenceHeader sequence,
    int introducer,
  ) {
    final int first = introducer + 1;
    if (first >= sequence.parameters.length ||
        !sequence.parameters.isSubparameter(first)) {
      return _SgrUnderlineResult(
        valid: true,
        underline: TerminalUnderlineStyle.single,
        nextIndex: introducer + 1,
      );
    }
    int end = first;
    while (end < sequence.parameters.length &&
        sequence.parameters.isSubparameter(end)) {
      end++;
    }
    if (end != first + 1) {
      return _SgrUnderlineResult(
        valid: false,
        underline: TerminalUnderlineStyle.none,
        nextIndex: end,
      );
    }
    final int variant = sequence.parameters.valueAt(first) ?? 1;
    if (variant < 0 || variant >= TerminalUnderlineStyle.values.length) {
      return _SgrUnderlineResult(
        valid: false,
        underline: TerminalUnderlineStyle.none,
        nextIndex: end,
      );
    }
    return _SgrUnderlineResult(
      valid: true,
      underline: TerminalUnderlineStyle.values[variant],
      nextIndex: end,
    );
  }

  _SgrColorResult _parseSgrColor(VtSequenceHeader sequence, int introducer) {
    final int modeIndex = introducer + 1;
    if (modeIndex >= sequence.parameters.length) {
      return _SgrColorResult.invalid(sequence.parameters.length);
    }
    if (sequence.parameters.isSubparameter(modeIndex)) {
      return _parseColonSgrColor(sequence, modeIndex);
    }
    final int? mode = sequence.parameters.valueAt(modeIndex);
    if (mode == 5) {
      final int valueIndex = modeIndex + 1;
      final int next = (valueIndex + 1).clamp(0, sequence.parameters.length);
      if (valueIndex < sequence.parameters.length &&
          !sequence.parameters.isSubparameter(valueIndex)) {
        final int? value = sequence.parameters.valueAt(valueIndex);
        if (_isColorComponent(value)) {
          return _SgrColorResult(
            valid: true,
            color: value! + 1,
            nextIndex: next,
          );
        }
      }
      return _SgrColorResult.invalid(next);
    }
    if (mode == 2) {
      final int next = (modeIndex + 4).clamp(0, sequence.parameters.length);
      if (modeIndex + 3 < sequence.parameters.length) {
        final int? red = sequence.parameters.valueAt(modeIndex + 1);
        final int? green = sequence.parameters.valueAt(modeIndex + 2);
        final int? blue = sequence.parameters.valueAt(modeIndex + 3);
        if (!sequence.parameters.isSubparameter(modeIndex + 1) &&
            !sequence.parameters.isSubparameter(modeIndex + 2) &&
            !sequence.parameters.isSubparameter(modeIndex + 3) &&
            _isColorComponent(red) &&
            _isColorComponent(green) &&
            _isColorComponent(blue)) {
          return _SgrColorResult(
            valid: true,
            color: _directColor(red!, green!, blue!),
            nextIndex: next,
          );
        }
      }
      return _SgrColorResult.invalid(next);
    }
    return _SgrColorResult.invalid(modeIndex + 1);
  }

  _SgrColorResult _parseColonSgrColor(
    VtSequenceHeader sequence,
    int modeIndex,
  ) {
    int end = modeIndex;
    while (end < sequence.parameters.length &&
        sequence.parameters.isSubparameter(end)) {
      end++;
    }
    final int? mode = sequence.parameters.valueAt(modeIndex);
    if (mode == 5 && end == modeIndex + 2) {
      final int? value = sequence.parameters.valueAt(modeIndex + 1);
      if (_isColorComponent(value)) {
        return _SgrColorResult(valid: true, color: value! + 1, nextIndex: end);
      }
    }
    if (mode == 2) {
      int componentStart = modeIndex + 1;
      if (end == modeIndex + 5) {
        final int? colorSpace = sequence.parameters.valueAt(componentStart);
        if (colorSpace != null && colorSpace != 0) {
          return _SgrColorResult.invalid(end);
        }
        componentStart++;
      }
      if (end == componentStart + 3) {
        final int? red = sequence.parameters.valueAt(componentStart);
        final int? green = sequence.parameters.valueAt(componentStart + 1);
        final int? blue = sequence.parameters.valueAt(componentStart + 2);
        if (_isColorComponent(red) &&
            _isColorComponent(green) &&
            _isColorComponent(blue)) {
          return _SgrColorResult(
            valid: true,
            color: _directColor(red!, green!, blue!),
            nextIndex: end,
          );
        }
      }
    }
    return _SgrColorResult.invalid(end);
  }

  static bool _isColorComponent(int? value) =>
      value != null && value >= 0 && value <= 255;

  static int _directColor(int red, int green, int blue) =>
      0x80000000 | (red << 16) | (green << 8) | blue;

  void _setPrivateModes(VtSequenceHeader sequence, bool enabled) {
    if (sequence.parameters.length == 0) {
      _unsupportedSequenceCount++;
      return;
    }
    for (int index = 0; index < sequence.parameters.length; index++) {
      switch (sequence.parameters.valueAt(index)) {
        case 1:
          final TerminalScreenSet? screens = screenSet;
          if (screens == null) {
            _unsupportedSequenceCount++;
          } else {
            screens.setApplicationCursorKeys(enabled);
          }
        case 5:
          screen.setMode(TerminalScreenMode.reverseVideo, enabled);
        case 6:
          screen.setMode(TerminalScreenMode.origin, enabled);
        case 7:
          screen.setMode(TerminalScreenMode.autoWrap, enabled);
        case 9:
          _setMouseTrackingMode(TerminalMouseTrackingMode.x10, enabled);
        case 12:
          screen.setCursorPresentation(blinking: enabled);
        case 25:
          screen.setCursorPresentation(visible: enabled);
        case 47:
          _setScreenMode(enabled, 47);
        case 69:
          screen.setMode(TerminalScreenMode.horizontalMargins, enabled);
        case 1000:
          _setMouseTrackingMode(TerminalMouseTrackingMode.normal, enabled);
        case 1002:
          _setMouseTrackingMode(TerminalMouseTrackingMode.buttonEvent, enabled);
        case 1003:
          _setMouseTrackingMode(TerminalMouseTrackingMode.anyEvent, enabled);
        case 1005:
          _setMouseCoordinateEncoding(
            TerminalMouseCoordinateEncoding.utf8,
            enabled,
          );
        case 1006:
          _setMouseCoordinateEncoding(
            TerminalMouseCoordinateEncoding.sgr,
            enabled,
          );
        case 1015:
          _setMouseCoordinateEncoding(
            TerminalMouseCoordinateEncoding.urxvt,
            enabled,
          );
        case 1047:
          _setScreenMode(enabled, 1047);
        case 1048:
          _setScreenMode(enabled, 1048);
        case 1049:
          _setScreenMode(enabled, 1049);
        case 2004:
          final TerminalScreenSet? screens = screenSet;
          if (screens == null) {
            _unsupportedSequenceCount++;
          } else {
            screens.setBracketedPasteMode(enabled);
          }
        default:
          _unsupportedSequenceCount++;
      }
    }
  }

  void _setMouseTrackingMode(TerminalMouseTrackingMode mode, bool enabled) {
    final TerminalScreenSet? screens = screenSet;
    if (screens == null) {
      _unsupportedSequenceCount++;
      return;
    }
    screens.setMouseTrackingMode(mode, enabled);
  }

  void _setMouseCoordinateEncoding(
    TerminalMouseCoordinateEncoding encoding,
    bool enabled,
  ) {
    final TerminalScreenSet? screens = screenSet;
    if (screens == null) {
      _unsupportedSequenceCount++;
      return;
    }
    screens.setMouseCoordinateEncoding(encoding, enabled);
  }

  void _setScreenMode(bool enabled, int mode) {
    final TerminalScreenSet? screens = screenSet;
    if (screens == null) {
      _unsupportedSequenceCount++;
      return;
    }
    switch (mode) {
      case 47:
        screens.setAlternateMode47(enabled);
      case 1047:
        screens.setAlternateMode1047(enabled);
      case 1048:
        screens.setCursorSaveMode1048(enabled);
      case 1049:
        screens.setAlternateMode1049(enabled);
    }
  }

  void _setCursorStyle(int value) {
    switch (value) {
      case 0:
      case 1:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.block,
          blinking: true,
        );
      case 2:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.block,
          blinking: false,
        );
      case 3:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.underline,
          blinking: true,
        );
      case 4:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.underline,
          blinking: false,
        );
      case 5:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.bar,
          blinking: true,
        );
      case 6:
        screen.setCursorPresentation(
          shape: TerminalCursorShape.bar,
          blinking: false,
        );
      default:
        _unsupportedSequenceCount++;
    }
  }

  void _eraseDisplay(VtSequenceHeader sequence) {
    final int mode = _parameter(sequence, 0, 0, zeroIsDefault: false);
    if (mode >= 0 && mode <= 2) {
      screen.eraseInDisplay(mode);
    } else {
      _unsupportedSequenceCount++;
    }
  }

  void _eraseLine(VtSequenceHeader sequence) {
    final int mode = _parameter(sequence, 0, 0, zeroIsDefault: false);
    if (mode >= 0 && mode <= 2) {
      screen.eraseInLine(mode);
    } else {
      _unsupportedSequenceCount++;
    }
  }

  void _clearTabStops(VtSequenceHeader sequence) {
    final int mode = _parameter(sequence, 0, 0, zeroIsDefault: false);
    if (mode == 0) {
      screen.setTabStop(screen.cursorColumn, enabled: false);
    } else if (mode == 3) {
      screen.clearAllTabStops();
    } else {
      _unsupportedSequenceCount++;
    }
  }

  void _setVerticalMargins(VtSequenceHeader sequence) {
    final int top = _oneBasedPosition(sequence, 0);
    final int bottom = _oneBasedPosition(
      sequence,
      1,
      defaultOneBased: screen.rows,
    );
    if (top < bottom && bottom < screen.rows) {
      screen.setVerticalMargins(top, bottom);
    } else if (top == 0 && bottom == screen.rows - 1) {
      screen.resetVerticalMargins();
    } else {
      _unsupportedSequenceCount++;
    }
  }

  void _setHorizontalMarginsOrSave(VtSequenceHeader sequence) {
    if (!screen.modeEnabled(TerminalScreenMode.horizontalMargins)) {
      screen.saveCursor();
      return;
    }
    final int left = _oneBasedPosition(sequence, 0);
    final int right = _oneBasedPosition(
      sequence,
      1,
      defaultOneBased: screen.columns,
    );
    if (left < right && right < screen.columns) {
      screen.setHorizontalMargins(left, right);
    } else if (left == 0 && right == screen.columns - 1) {
      screen.resetHorizontalMargins();
    } else {
      _unsupportedSequenceCount++;
    }
  }

  static bool _hasSubparameters(VtSequenceHeader sequence) {
    for (int index = 0; index < sequence.parameters.length; index++) {
      if (sequence.parameters.isSubparameter(index)) {
        return true;
      }
    }
    return false;
  }

  static int _count(VtSequenceHeader sequence) => _parameter(sequence, 0, 1);

  static int _oneBasedPosition(
    VtSequenceHeader sequence,
    int index, {
    int defaultOneBased = 1,
  }) => _parameter(sequence, index, defaultOneBased) - 1;

  static int _parameter(
    VtSequenceHeader sequence,
    int index,
    int defaultValue, {
    bool zeroIsDefault = true,
  }) {
    if (index >= sequence.parameters.length) {
      return defaultValue;
    }
    final int? value = sequence.parameters.valueAt(index);
    if (value == null || (zeroIsDefault && value == 0)) {
      return defaultValue;
    }
    return value;
  }
}

final class _SgrColorResult {
  const _SgrColorResult({
    required this.valid,
    required this.color,
    required this.nextIndex,
  });

  factory _SgrColorResult.invalid(int nextIndex) =>
      _SgrColorResult(valid: false, color: 0, nextIndex: nextIndex);

  final bool valid;
  final int color;
  final int nextIndex;
}

final class _SgrUnderlineResult {
  const _SgrUnderlineResult({
    required this.valid,
    required this.underline,
    required this.nextIndex,
  });

  final bool valid;
  final TerminalUnderlineStyle underline;
  final int nextIndex;
}
