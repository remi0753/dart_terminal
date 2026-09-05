import 'terminal_screen.dart';
import 'vt_parser.dart';
import 'vt_parser_table.dart';

/// Applies the currently supported VT screen actions to a [TerminalScreen].
///
/// SGR, palette, alternate-screen, protocol strings, and query replies belong
/// to later roadmap tasks. They are counted as unsupported without throwing or
/// corrupting the visible screen.
final class TerminalScreenParserSink implements VtParserSink {
  TerminalScreenParserSink(this.screen);

  final TerminalScreen screen;

  int _unsupportedControlCount = 0;
  int _unsupportedSequenceCount = 0;
  int _cancelCount = 0;
  int _limitCount = 0;
  int _malformedCount = 0;
  int _incompleteCount = 0;

  int get unsupportedControlCount => _unsupportedControlCount;
  int get unsupportedSequenceCount => _unsupportedSequenceCount;
  int get cancelCount => _cancelCount;
  int get limitCount => _limitCount;
  int get malformedCount => _malformedCount;
  int get incompleteCount => _incompleteCount;

  @override
  void print(int scalar) {
    screen.printNarrowScalar(scalar);
  }

  @override
  void execute(int controlByte) {
    switch (controlByte) {
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
    if (sequence.intermediateCount != 0) {
      _unsupportedSequenceCount++;
      return;
    }
    switch (sequence.finalByte) {
      case 0x37:
        screen.saveCursor();
      case 0x38:
        screen.restoreCursor();
      case 0x44:
        screen.index();
      case 0x45:
        screen.nextLine();
      case 0x48:
        screen.setTabStop(screen.cursorColumn);
      case 0x4d:
        screen.reverseIndex();
      case 0x63:
        screen.resetScreen();
      default:
        _unsupportedSequenceCount++;
    }
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    if (_hasSubparameters(sequence)) {
      _unsupportedSequenceCount++;
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
    _unsupportedSequenceCount++;
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    _unsupportedSequenceCount++;
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    _unsupportedSequenceCount++;
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    _cancelCount++;
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    _limitCount++;
  }

  @override
  void malformed(VtParserState state, int byte) {
    _malformedCount++;
  }

  @override
  void incomplete(VtParserState state) {
    _incompleteCount++;
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

  void _setPrivateModes(VtSequenceHeader sequence, bool enabled) {
    if (sequence.parameters.length == 0) {
      _unsupportedSequenceCount++;
      return;
    }
    for (int index = 0; index < sequence.parameters.length; index++) {
      switch (sequence.parameters.valueAt(index)) {
        case 5:
          screen.setMode(TerminalScreenMode.reverseVideo, enabled);
        case 6:
          screen.setMode(TerminalScreenMode.origin, enabled);
        case 7:
          screen.setMode(TerminalScreenMode.autoWrap, enabled);
        case 12:
          screen.setCursorPresentation(blinking: enabled);
        case 25:
          screen.setCursorPresentation(visible: enabled);
        case 69:
          screen.setMode(TerminalScreenMode.horizontalMargins, enabled);
        default:
          _unsupportedSequenceCount++;
      }
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
