import 'dart:convert';
import 'dart:typed_data';

const int _stateGround = 0;
const int _stateEscape = 1;
const int _stateEscapeIntermediate = 2;
const int _stateCsi = 3;
const int _stateCsiIntermediate = 4;
const int _stateOsc = 5;
const int _stateDcs = 6;
const int _stateApc = 7;
const int _stateStringEscape = 8;

const int _eventScalar = 1;
const int _eventControl = 2;
const int _eventEscape = 3;
const int _eventCsi = 4;
const int _eventOsc = 5;
const int _eventDcs = 6;
const int _eventApc = 7;
const int _eventCancel = 8;
const int _eventLimit = 9;
const int _eventIncomplete = 10;

final class ParserLimits {
  const ParserLimits({
    this.maxSequenceBytes = 8192,
    this.maxStringBytes = 4096,
    this.maxParameters = 32,
    this.maxNumericValue = 1000000,
  });

  final int maxSequenceBytes;
  final int maxStringBytes;
  final int maxParameters;
  final int maxNumericValue;

  void validate() {
    if (maxSequenceBytes < 4 ||
        maxSequenceBytes > 65536 ||
        maxStringBytes < 1 ||
        maxStringBytes >= maxSequenceBytes ||
        maxParameters < 1 ||
        maxParameters > 1024 ||
        maxNumericValue < 1 ||
        maxNumericValue > 0x7fffffff) {
      throw ArgumentError('invalid parser limits');
    }
  }
}

final class ParserActionRecorder {
  ParserActionRecorder({int maxEvents = 4096, int arenaBytes = 65536})
    : _records = Uint32List(maxEvents * 4),
      _arena = Uint8List(arenaBytes);

  final Uint32List _records;
  final Uint8List _arena;
  int _eventCount = 0;
  int _arenaLength = 0;

  int get eventCount => _eventCount;

  void reset() {
    _eventCount = 0;
    _arenaLength = 0;
  }

  void recordScalar(int scalar) => _record(_eventScalar, scalar, 0, 0);

  void recordControl(int byte) => _record(_eventControl, byte, 0, 0);

  void recordSequence(int type, Uint8List bytes, int length) {
    if (_arenaLength + length > _arena.length) {
      throw StateError('parser action byte arena exhausted');
    }
    _arena.setRange(_arenaLength, _arenaLength + length, bytes);
    _record(type, _arenaLength, length, 0);
    _arenaLength += length;
  }

  void recordStatus(int type, int state, int byte) {
    _record(type, state, byte, 0);
  }

  List<String> formatSnapshot() {
    final List<String> lines = <String>[];
    final StringBuffer text = StringBuffer();

    void flushText() {
      if (text.isEmpty) {
        return;
      }
      lines.add('TEXT ${jsonEncode(text.toString())}');
      text.clear();
    }

    for (int event = 0; event < _eventCount; event++) {
      final int base = event * 4;
      final int type = _records[base];
      final int first = _records[base + 1];
      final int second = _records[base + 2];
      if (type == _eventScalar) {
        text.writeCharCode(first);
        continue;
      }
      flushText();
      switch (type) {
        case _eventControl:
          lines.add('EXEC ${_controlName(first)} (0x${_hexByte(first)})');
        case _eventEscape:
        case _eventCsi:
        case _eventOsc:
        case _eventDcs:
        case _eventApc:
          lines.add('${_eventName(type)} "${_escapeBytes(first, second)}"');
        case _eventCancel:
        case _eventLimit:
        case _eventIncomplete:
          final String suffix = type == _eventCancel
              ? ' byte=${_controlName(second)}'
              : '';
          lines.add('${_eventName(type)} state=${_stateName(first)}$suffix');
        default:
          throw StateError('unknown recorded parser event $type');
      }
    }
    flushText();
    return lines;
  }

  void _record(int type, int first, int second, int third) {
    if ((_eventCount + 1) * 4 > _records.length) {
      throw StateError('parser action recorder exhausted');
    }
    final int base = _eventCount * 4;
    _records[base] = type;
    _records[base + 1] = first;
    _records[base + 2] = second;
    _records[base + 3] = third;
    _eventCount++;
  }

  String _escapeBytes(int offset, int length) {
    final StringBuffer result = StringBuffer();
    for (int index = offset; index < offset + length; index++) {
      final int byte = _arena[index];
      switch (byte) {
        case 0x1b:
          result.write(r'\e');
        case 0x07:
          result.write(r'\a');
        case 0x5c:
          result.write(r'\\');
        case 0x22:
          result.write(r'\"');
        default:
          if (byte >= 0x20 && byte <= 0x7e) {
            result.writeCharCode(byte);
          } else {
            result.write(r'\x');
            result.write(_hexByte(byte));
          }
      }
    }
    return result.toString();
  }
}

final class VtStreamProbe {
  VtStreamProbe({this.limits = const ParserLimits(), this.recorder})
    : _sequence = Uint8List(limits.maxSequenceBytes) {
    limits.validate();
  }

  final ParserLimits limits;
  final ParserActionRecorder? recorder;
  final Uint8List _sequence;

  int _state = _stateGround;
  int _stringState = _stateOsc;
  int _sequenceLength = 0;
  int _stringPayloadLength = 0;
  int _parameterCount = 0;
  int _numericValue = 0;
  bool _limited = false;

  int _utf8Needed = 0;
  int _utf8Scalar = 0;
  int _utf8Minimum = 0;

  int textScalars = 0;
  int controls = 0;
  int sequences = 0;
  int cancellations = 0;
  int limitsHit = 0;
  int replacements = 0;
  int actionHash = 0x13579bdf;

  bool get isGround => _state == _stateGround && _utf8Needed == 0;

  void reset() {
    _state = _stateGround;
    _stringState = _stateOsc;
    _sequenceLength = 0;
    _stringPayloadLength = 0;
    _parameterCount = 0;
    _numericValue = 0;
    _limited = false;
    _utf8Needed = 0;
    _utf8Scalar = 0;
    _utf8Minimum = 0;
    textScalars = 0;
    controls = 0;
    sequences = 0;
    cancellations = 0;
    limitsHit = 0;
    replacements = 0;
    actionHash = 0x13579bdf;
    recorder?.reset();
  }

  void parse(Uint8List bytes, [int start = 0, int? end]) {
    final int limit = end ?? bytes.length;
    if (start < 0 || limit < start || limit > bytes.length) {
      throw RangeError('invalid parser slice $start..$limit');
    }
    int index = start;
    while (index < limit) {
      if (_state == _stateGround && _utf8Needed == 0) {
        int byte = bytes[index];
        if (byte >= 0x20 && byte <= 0x7e) {
          if (recorder == null) {
            do {
              textScalars++;
              _mix(_eventScalar, byte);
              index++;
              if (index >= limit) {
                break;
              }
              byte = bytes[index];
            } while (byte >= 0x20 && byte <= 0x7e);
          } else {
            do {
              _emitScalar(byte);
              index++;
              if (index >= limit) {
                break;
              }
              byte = bytes[index];
            } while (byte >= 0x20 && byte <= 0x7e);
          }
          continue;
        }
      }
      _processByte(bytes[index]);
      index++;
    }
  }

  void finish() {
    _flushIncompleteUtf8();
    if (_state != _stateGround) {
      recorder?.recordStatus(_eventIncomplete, _state, 0);
      _mix(_eventIncomplete, _state);
      _state = _stateGround;
      _sequenceLength = 0;
      _limited = false;
    }
  }

  void _processByte(int byte) {
    switch (_state) {
      case _stateGround:
        _processGround(byte);
      case _stateEscape:
        _processEscape(byte);
      case _stateEscapeIntermediate:
        _processEscapeIntermediate(byte);
      case _stateCsi:
        _processCsi(byte, allowParameters: true);
      case _stateCsiIntermediate:
        _processCsi(byte, allowParameters: false);
      case _stateOsc:
      case _stateDcs:
      case _stateApc:
        _processString(byte);
      case _stateStringEscape:
        _processStringEscape(byte);
      default:
        throw StateError('invalid parser state $_state');
    }
  }

  void _processGround(int byte) {
    if (byte == 0x1b) {
      _flushIncompleteUtf8();
      _beginEscape();
      return;
    }
    if (byte < 0x20 || byte == 0x7f) {
      _flushIncompleteUtf8();
      _emitControl(byte);
      return;
    }
    if (_utf8Needed != 0) {
      _feedUtf8(byte);
      return;
    }
    if (byte <= 0x7e) {
      _emitScalar(byte);
      return;
    }
    _feedUtf8(byte);
  }

  void _processEscape(int byte) {
    if (_cancelOrRestart(byte)) {
      return;
    }
    if (byte < 0x20 || byte == 0x7f) {
      _emitControl(byte);
      return;
    }
    _appendSequence(byte);
    if (byte == 0x5b) {
      _state = _stateCsi;
      _parameterCount = 1;
      _numericValue = 0;
    } else if (byte == 0x5d) {
      _beginString(_stateOsc);
    } else if (byte == 0x50) {
      _beginString(_stateDcs);
    } else if (byte == 0x5f) {
      _beginString(_stateApc);
    } else if (byte >= 0x20 && byte <= 0x2f) {
      _state = _stateEscapeIntermediate;
    } else if (byte >= 0x30 && byte <= 0x7e) {
      _dispatchSequence(_eventEscape, _stateEscape);
    } else {
      _recordCancel(_stateEscape, byte);
      _resetSequence();
    }
  }

  void _processEscapeIntermediate(int byte) {
    if (_cancelOrRestart(byte)) {
      return;
    }
    if (byte < 0x20 || byte == 0x7f) {
      _emitControl(byte);
      return;
    }
    _appendSequence(byte);
    if (byte >= 0x20 && byte <= 0x2f) {
      return;
    }
    if (byte >= 0x30 && byte <= 0x7e) {
      _dispatchSequence(_eventEscape, _stateEscapeIntermediate);
      return;
    }
    _recordCancel(_stateEscapeIntermediate, byte);
    _resetSequence();
  }

  void _processCsi(int byte, {required bool allowParameters}) {
    if (_cancelOrRestart(byte)) {
      return;
    }
    if (byte < 0x20 || byte == 0x7f) {
      _emitControl(byte);
      return;
    }
    _appendSequence(byte);
    if (allowParameters && byte >= 0x30 && byte <= 0x3f) {
      _consumeParameterByte(byte);
      return;
    }
    if (byte >= 0x20 && byte <= 0x2f) {
      _state = _stateCsiIntermediate;
      return;
    }
    if (byte >= 0x40 && byte <= 0x7e) {
      _dispatchSequence(_eventCsi, _stateCsi);
      return;
    }
    _limited = true;
  }

  void _processString(int byte) {
    if (byte == 0x18 || byte == 0x1a) {
      _recordCancel(_state, byte);
      _resetSequence();
      return;
    }
    if (_state == _stateOsc && byte == 0x07) {
      _appendSequence(byte);
      _dispatchString();
      return;
    }
    if (byte == 0x1b) {
      _stringState = _state;
      _appendSequence(byte);
      _state = _stateStringEscape;
      return;
    }
    _appendSequence(byte);
    _stringPayloadLength++;
    if (_stringPayloadLength > limits.maxStringBytes) {
      _limited = true;
    }
  }

  void _processStringEscape(int byte) {
    if (byte == 0x5c) {
      _appendSequence(byte);
      _state = _stringState;
      _dispatchString();
      return;
    }
    _recordCancel(_stringState, 0x1b);
    _beginEscape();
    _processEscape(byte);
  }

  bool _cancelOrRestart(int byte) {
    if (byte == 0x18 || byte == 0x1a) {
      _recordCancel(_state, byte);
      _resetSequence();
      return true;
    }
    if (byte == 0x1b) {
      _recordCancel(_state, byte);
      _beginEscape();
      return true;
    }
    return false;
  }

  void _beginEscape() {
    _state = _stateEscape;
    _sequenceLength = 0;
    _stringPayloadLength = 0;
    _limited = false;
    _appendSequence(0x1b);
  }

  void _beginString(int state) {
    _state = state;
    _stringState = state;
    _stringPayloadLength = 0;
  }

  void _resetSequence() {
    _state = _stateGround;
    _sequenceLength = 0;
    _stringPayloadLength = 0;
    _limited = false;
  }

  void _appendSequence(int byte) {
    if (_sequenceLength < _sequence.length) {
      _sequence[_sequenceLength] = byte;
      _sequenceLength++;
    } else {
      _limited = true;
    }
  }

  void _consumeParameterByte(int byte) {
    if (byte >= 0x30 && byte <= 0x39) {
      final int digit = byte - 0x30;
      if (_numericValue > (limits.maxNumericValue - digit) ~/ 10) {
        _limited = true;
      } else {
        _numericValue = _numericValue * 10 + digit;
      }
      return;
    }
    if (byte == 0x3b || byte == 0x3a) {
      _parameterCount++;
      _numericValue = 0;
      if (_parameterCount > limits.maxParameters) {
        _limited = true;
      }
    } else {
      _numericValue = 0;
    }
  }

  void _dispatchString() {
    final int type = switch (_state) {
      _stateOsc => _eventOsc,
      _stateDcs => _eventDcs,
      _stateApc => _eventApc,
      _ => throw StateError('invalid string dispatch state $_state'),
    };
    _dispatchSequence(type, _state);
  }

  void _dispatchSequence(int eventType, int sourceState) {
    if (_limited) {
      limitsHit++;
      recorder?.recordStatus(_eventLimit, sourceState, 0);
      _mix(_eventLimit, sourceState);
    } else {
      sequences++;
      recorder?.recordSequence(eventType, _sequence, _sequenceLength);
      _mix(eventType, _sequenceLength);
      for (int index = 0; index < _sequenceLength; index++) {
        _mix(eventType, _sequence[index]);
      }
    }
    _resetSequence();
  }

  void _recordCancel(int sourceState, int byte) {
    cancellations++;
    recorder?.recordStatus(_eventCancel, sourceState, byte);
    _mix(_eventCancel, sourceState);
    _mix(_eventCancel, byte);
  }

  void _emitControl(int byte) {
    controls++;
    recorder?.recordControl(byte);
    _mix(_eventControl, byte);
  }

  void _emitScalar(int scalar) {
    textScalars++;
    recorder?.recordScalar(scalar);
    _mix(_eventScalar, scalar);
  }

  void _emitReplacement() {
    replacements++;
    _emitScalar(0xfffd);
  }

  void _feedUtf8(int byte) {
    if (_utf8Needed == 0) {
      if (byte >= 0xc2 && byte <= 0xdf) {
        _utf8Needed = 1;
        _utf8Scalar = byte & 0x1f;
        _utf8Minimum = 0x80;
      } else if (byte >= 0xe0 && byte <= 0xef) {
        _utf8Needed = 2;
        _utf8Scalar = byte & 0x0f;
        _utf8Minimum = 0x800;
      } else if (byte >= 0xf0 && byte <= 0xf4) {
        _utf8Needed = 3;
        _utf8Scalar = byte & 0x07;
        _utf8Minimum = 0x10000;
      } else {
        _emitReplacement();
      }
      return;
    }

    if (byte < 0x80 || byte > 0xbf) {
      _emitReplacement();
      _utf8Needed = 0;
      _utf8Scalar = 0;
      _utf8Minimum = 0;
      _processGround(byte);
      return;
    }
    _utf8Scalar = (_utf8Scalar << 6) | (byte & 0x3f);
    _utf8Needed--;
    if (_utf8Needed != 0) {
      return;
    }
    final int scalar = _utf8Scalar;
    final bool valid =
        scalar >= _utf8Minimum &&
        scalar <= 0x10ffff &&
        (scalar < 0xd800 || scalar > 0xdfff);
    _utf8Scalar = 0;
    _utf8Minimum = 0;
    if (valid) {
      _emitScalar(scalar);
    } else {
      _emitReplacement();
    }
  }

  void _flushIncompleteUtf8() {
    if (_utf8Needed == 0) {
      return;
    }
    _utf8Needed = 0;
    _utf8Scalar = 0;
    _utf8Minimum = 0;
    _emitReplacement();
  }

  void _mix(int kind, int value) {
    actionHash = ((actionHash ^ kind ^ value) * 0x01000193) & 0x7fffffff;
  }
}

String _hexByte(int byte) => byte.toRadixString(16).padLeft(2, '0');

String _controlName(int byte) => switch (byte) {
  0x00 => 'NUL',
  0x07 => 'BEL',
  0x08 => 'BS',
  0x09 => 'HT',
  0x0a => 'LF',
  0x0b => 'VT',
  0x0c => 'FF',
  0x0d => 'CR',
  0x18 => 'CAN',
  0x1a => 'SUB',
  0x1b => 'ESC',
  0x7f => 'DEL',
  _ => 'C0',
};

String _eventName(int event) => switch (event) {
  _eventEscape => 'ESC',
  _eventCsi => 'CSI',
  _eventOsc => 'OSC',
  _eventDcs => 'DCS',
  _eventApc => 'APC',
  _eventCancel => 'CANCEL',
  _eventLimit => 'LIMIT',
  _eventIncomplete => 'INCOMPLETE',
  _ => 'EVENT-$event',
};

String _stateName(int state) => switch (state) {
  _stateGround => 'ground',
  _stateEscape => 'escape',
  _stateEscapeIntermediate => 'escape-intermediate',
  _stateCsi => 'csi',
  _stateCsiIntermediate => 'csi-intermediate',
  _stateOsc => 'osc',
  _stateDcs => 'dcs',
  _stateApc => 'apc',
  _stateStringEscape => 'string-escape',
  _ => 'state-$state',
};
