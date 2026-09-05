import 'dart:typed_data';

import 'streaming_utf8_decoder.dart';
import 'vt_parser_table.dart';

const int _parameterPresentBit = 1 << 0;
const int _parameterSubparameterBit = 1 << 1;

enum VtParserLimitKind {
  sequenceBytes,
  stringBytes,
  parameters,
  intermediates,
  numericValue,
}

enum VtStringKind {
  operatingSystemCommand,
  deviceControlString,
  startOfString,
  privacyMessage,
  applicationProgramCommand,
}

enum VtStringTerminator { bell, stringTerminator }

enum VtUncapturedSequenceKind {
  escape,
  controlSequence,
  operatingSystemCommand,
  deviceControlString,
  controlString,
}

final class VtParserLimits {
  const VtParserLimits({
    this.maxSequenceBytes = 8192,
    this.maxStringBytes = 4096,
    this.maxParameters = 32,
    this.maxIntermediates = 8,
    this.maxNumericValue = 1000000,
  });

  final int maxSequenceBytes;
  final int maxStringBytes;
  final int maxParameters;
  final int maxIntermediates;
  final int maxNumericValue;

  void validate() {
    if (maxSequenceBytes < 4 || maxSequenceBytes > 1024 * 1024) {
      throw ArgumentError.value(
        maxSequenceBytes,
        'maxSequenceBytes',
        'must be between 4 and 1048576',
      );
    }
    if (maxStringBytes < 1 || maxStringBytes >= maxSequenceBytes) {
      throw ArgumentError.value(
        maxStringBytes,
        'maxStringBytes',
        'must be positive and smaller than maxSequenceBytes',
      );
    }
    if (maxParameters < 1 || maxParameters > 1024) {
      throw ArgumentError.value(
        maxParameters,
        'maxParameters',
        'must be between 1 and 1024',
      );
    }
    if (maxIntermediates < 1 || maxIntermediates > 64) {
      throw ArgumentError.value(
        maxIntermediates,
        'maxIntermediates',
        'must be between 1 and 64',
      );
    }
    if (maxNumericValue < 1 || maxNumericValue > 0x7fffffff) {
      throw ArgumentError.value(
        maxNumericValue,
        'maxNumericValue',
        'must be between 1 and 2147483647',
      );
    }
  }
}

/// Retainable typed parameter segments for one CSI or DCS header.
///
/// A missing parameter has a null [valueAt]. [isSubparameter] is true when the
/// segment was introduced by `:` rather than `;`.
final class VtParameters {
  VtParameters._(this._values, this._metadata);

  final Uint32List _values;
  final Uint8List _metadata;

  int get length => _values.length;

  int? valueAt(int index) {
    RangeError.checkValidIndex(index, _values);
    return (_metadata[index] & _parameterPresentBit) == 0
        ? null
        : _values[index];
  }

  bool isSubparameter(int index) {
    RangeError.checkValidIndex(index, _values);
    return (_metadata[index] & _parameterSubparameterBit) != 0;
  }

  List<int?> toValueList() => List<int?>.generate(length, valueAt);
}

/// Retainable header for a CSI dispatch or the header of a DCS sequence.
final class VtSequenceHeader {
  VtSequenceHeader._({
    required this.privateMarker,
    required this.parameters,
    required Uint8List intermediates,
    required this.finalByte,
  }) : _intermediates = intermediates;

  final int? privateMarker;
  final VtParameters parameters;
  final Uint8List _intermediates;
  final int finalByte;

  int get intermediateCount => _intermediates.length;

  int intermediateAt(int index) {
    RangeError.checkValidIndex(index, _intermediates);
    return _intermediates[index];
  }

  Uint8List copyIntermediates() => Uint8List.fromList(_intermediates);
}

final class VtEscapeSequence {
  VtEscapeSequence._({
    required Uint8List intermediates,
    required this.finalByte,
  }) : _intermediates = intermediates;

  final Uint8List _intermediates;
  final int finalByte;

  int get intermediateCount => _intermediates.length;

  int intermediateAt(int index) {
    RangeError.checkValidIndex(index, _intermediates);
    return _intermediates[index];
  }

  Uint8List copyIntermediates() => Uint8List.fromList(_intermediates);
}

final class VtStringSequence {
  VtStringSequence._({
    required this.kind,
    required Uint8List payload,
    required this.terminator,
  }) : _payload = payload;

  final VtStringKind kind;
  final Uint8List _payload;
  final VtStringTerminator terminator;

  int get payloadLength => _payload.length;

  int payloadByteAt(int index) {
    RangeError.checkValidIndex(index, _payload);
    return _payload[index];
  }

  Uint8List copyPayload() => Uint8List.fromList(_payload);
}

final class VtDcsSequence {
  VtDcsSequence._({
    required this.header,
    required Uint8List payload,
    required this.terminator,
  }) : _payload = payload;

  final VtSequenceHeader header;
  final Uint8List _payload;
  final VtStringTerminator terminator;

  int get payloadLength => _payload.length;

  int payloadByteAt(int index) {
    RangeError.checkValidIndex(index, _payload);
    return _payload[index];
  }

  Uint8List copyPayload() => Uint8List.fromList(_payload);
}

/// Synchronous byte-to-action boundary used by [VtParser].
///
/// Scalar and control callbacks avoid allocating an event object per input
/// byte. Sequence objects contain private copies and may be retained. A sink
/// must not recursively call the parser from one of these callbacks.
abstract interface class VtParserSink {
  void print(int scalar);

  void execute(int controlByte);

  void dispatchEscape(VtEscapeSequence sequence);

  void dispatchCsi(VtSequenceHeader sequence);

  void dispatchOsc(VtStringSequence sequence);

  void dispatchDcs(VtDcsSequence sequence);

  void dispatchString(VtStringSequence sequence);

  void cancel(VtParserState state, int controlByte);

  void limit(VtParserState state, VtParserLimitKind kind);

  void malformed(VtParserState state, int byte);

  void incomplete(VtParserState state);
}

/// Opt-in synchronous callback for a contiguous printable ASCII run.
///
/// [bytes] is borrowed only for the duration of the callback and must not be
/// retained. Each byte from [start] (inclusive) to [end] (exclusive) has the
/// same meaning and ordering as an individual [VtParserSink.print] callback.
abstract interface class VtParserAsciiSink {
  void printAscii(Uint8List bytes, int start, int end);
}

/// Opt-in non-retaining sequence callback for benchmark and metrics sinks.
///
/// When a [VtParserSink] also implements this interface, successful ESC, CSI,
/// OSC, DCS, and SOS/PM/APC dispatches skip retainable action objects and copied
/// typed arrays. Only primitive metadata valid for the callback is exposed.
/// Text, controls, cancellation, limit, malformed, and incomplete callbacks
/// continue through [VtParserSink]. Semantic consumers must not implement this
/// interface because parameters, intermediates, and payload bytes are omitted.
abstract interface class VtParserUncapturedSequenceSink {
  void dispatchUncapturedSequence(
    VtUncapturedSequenceKind kind,
    int privateMarker,
    int parameterCount,
    int intermediateCount,
    int finalByte,
    int payloadLength,
    int terminator,
  );
}

/// Incremental table-driven parser for UTF-8 and VT sequence families.
final class VtParser {
  factory VtParser({
    required VtParserSink sink,
    VtParserLimits limits = const VtParserLimits(),
  }) {
    limits.validate();
    return VtParser._(sink: sink, limits: limits);
  }

  VtParser._({required this.sink, required this.limits})
    : _asciiSink = sink is VtParserAsciiSink ? sink as VtParserAsciiSink : null,
      _uncapturedSequenceSink = sink is VtParserUncapturedSequenceSink
          ? sink as VtParserUncapturedSequenceSink
          : null,
      _intermediates = Uint8List(limits.maxIntermediates),
      _parameterValues = Uint32List(limits.maxParameters),
      _parameterMetadata = Uint8List(limits.maxParameters),
      _stringPayload = Uint8List(limits.maxStringBytes),
      _utf8Byte = Uint8List(1),
      _utf8Decoder = StreamingUtf8Decoder(onScalar: sink.print);

  final VtParserSink sink;
  final VtParserLimits limits;
  final VtParserAsciiSink? _asciiSink;
  final VtParserUncapturedSequenceSink? _uncapturedSequenceSink;
  final StreamingUtf8Decoder _utf8Decoder;
  final Uint8List _utf8Byte;
  final Uint8List _intermediates;
  final Uint32List _parameterValues;
  final Uint8List _parameterMetadata;
  final Uint8List _stringPayload;

  VtParserState _state = VtParserState.ground;
  int _sequenceBytes = 0;
  int _intermediateCount = 0;
  int _parameterCount = 0;
  int? _privateMarker;
  bool _headerRejected = false;
  bool _limitReported = false;
  bool _malformedReported = false;

  bool _stringActive = false;
  bool _stringRejected = false;
  bool _stringCancelled = false;
  int _stringLength = 0;
  VtStringKind _stringKind = VtStringKind.operatingSystemCommand;
  VtParserState _stringSourceState = VtParserState.oscString;
  VtSequenceHeader? _dcsHeader;
  int _dcsPrivateMarker = 0;
  int _dcsParameterCount = 0;
  int _dcsIntermediateCount = 0;
  int _dcsFinalByte = 0;
  bool _stringEscapePending = false;

  VtParserState get state => _state;

  bool get isGround =>
      _state == VtParserState.ground &&
      _utf8Decoder.isAccepting &&
      !_stringEscapePending;

  void parse(Uint8List bytes, [int start = 0, int? end]) {
    final int limit = end ?? bytes.length;
    RangeError.checkValidRange(start, limit, bytes.length);
    int index = start;
    while (index < limit) {
      if (_state == VtParserState.ground && _utf8Decoder.isAccepting) {
        int byte = bytes[index];
        if (byte >= 0x20 && byte <= 0x7e) {
          final int runStart = index;
          do {
            index++;
            if (index >= limit) {
              break;
            }
            byte = bytes[index];
          } while (byte >= 0x20 && byte <= 0x7e);
          final VtParserAsciiSink? asciiSink = _asciiSink;
          if (asciiSink != null) {
            asciiSink.printAscii(bytes, runStart, index);
          } else {
            for (var asciiIndex = runStart; asciiIndex < index; asciiIndex++) {
              sink.print(bytes[asciiIndex]);
            }
          }
          continue;
        }
      }
      if (_uncapturedSequenceSink != null &&
          _stringActive &&
          !_stringRejected &&
          (_state == VtParserState.oscString ||
              _state == VtParserState.dcsPassthrough ||
              _state == VtParserState.sosPmApcString)) {
        var stringEnd = index;
        while (stringEnd < limit) {
          final int byte = bytes[stringEnd];
          if (byte < 0x20 || byte > 0x7e) {
            break;
          }
          stringEnd++;
        }
        final int runLength = stringEnd - index;
        if (runLength != 0 &&
            _sequenceBytes + runLength <= limits.maxSequenceBytes &&
            _stringLength + runLength <= limits.maxStringBytes) {
          _sequenceBytes += runLength;
          _stringLength += runLength;
          index = stringEnd;
          continue;
        }
      }
      final int byte = bytes[index++];
      if (!_utf8Decoder.isAccepting) {
        if (byte >= 0x80 && byte <= 0xbf) {
          _feedUtf8Byte(byte);
          continue;
        }
        _utf8Decoder.finish();
      }
      _processVtByte(byte);
    }
  }

  /// Flushes partial UTF-8 or VT input exactly once and returns to ground.
  void finish() {
    _utf8Decoder.finish();
    if (_stringEscapePending) {
      sink.incomplete(_stringSourceState);
    } else if (_state != VtParserState.ground) {
      sink.incomplete(_state);
    }
    _resetState();
  }

  /// Discards all partial input without emitting an action.
  void reset() {
    _utf8Decoder.reset();
    _resetState();
  }

  void _processVtByte(int byte) {
    if (_stringEscapePending &&
        _state == VtParserState.escape &&
        byte != 0x5c) {
      _cancelPendingString();
    }

    final VtParserState previousState = _state;
    final int stateId = previousState.index;
    final VtParserState nextState =
        VtParserState.values[VtParserTable.nextStateIdUnchecked(stateId, byte)];
    final VtParserAction action = VtParserAction
        .values[VtParserTable.transitionActionIdUnchecked(stateId, byte)];
    final bool startsSequence = VtParserTable.transitionStartsSequenceUnchecked(
      stateId,
      byte,
    );

    if (previousState != VtParserState.ground) {
      _countSequenceByte(previousState);
    }
    _executeTransitionAction(action, previousState, byte);

    final bool changesState = nextState != previousState;
    final bool reentersState = startsSequence && !changesState;
    if (changesState || reentersState) {
      _executeExitAction(
        VtParserTable.exitAction(previousState),
        previousState,
        byte,
        startsSequence: startsSequence,
      );
      if (startsSequence) {
        _beginSequence();
      }
      _state = nextState;
      _executeEntryAction(
        VtParserTable.entryAction(nextState),
        nextState,
        byte,
      );
    } else {
      _state = nextState;
    }

    if (_state == VtParserState.ground &&
        previousState != VtParserState.ground &&
        !startsSequence) {
      _endSequence();
    }
  }

  void _executeTransitionAction(
    VtParserAction action,
    VtParserState sourceState,
    int byte,
  ) {
    switch (action) {
      case VtParserAction.none:
      case VtParserAction.ignore:
        return;
      case VtParserAction.print:
        sink.print(byte);
      case VtParserAction.execute:
        sink.execute(byte);
      case VtParserAction.collect:
        _collect(byte, sourceState);
      case VtParserAction.parameter:
        _consumeParameter(byte, sourceState);
      case VtParserAction.escapeDispatch:
        _dispatchEscape(byte);
      case VtParserAction.csiDispatch:
        _dispatchCsi(byte);
      case VtParserAction.dcsPut:
      case VtParserAction.oscPut:
      case VtParserAction.stringPut:
        _appendStringByte(byte, sourceState);
      case VtParserAction.cancel:
        sink.cancel(sourceState, byte);
        _headerRejected = true;
        if (_stringActive) {
          _stringCancelled = true;
        }
      case VtParserAction.utf8:
        _feedUtf8Byte(byte);
      case VtParserAction.malformed:
        _markMalformed(sourceState, byte);
      case VtParserAction.clear:
      case VtParserAction.dcsHook:
      case VtParserAction.dcsUnhook:
      case VtParserAction.oscStart:
      case VtParserAction.oscEnd:
      case VtParserAction.stringStart:
      case VtParserAction.stringEnd:
        throw StateError('invalid transition action: ${action.name}');
    }
  }

  void _executeEntryAction(
    VtParserAction action,
    VtParserState enteredState,
    int byte,
  ) {
    switch (action) {
      case VtParserAction.none:
        return;
      case VtParserAction.clear:
        _clearHeader();
      case VtParserAction.dcsHook:
        _startDcsString(enteredState, byte);
      case VtParserAction.oscStart:
        _startString(VtStringKind.operatingSystemCommand, enteredState);
      case VtParserAction.stringStart:
        _startString(_stringKindForIntroducer(byte), enteredState);
      case VtParserAction.ignore:
      case VtParserAction.print:
      case VtParserAction.execute:
      case VtParserAction.collect:
      case VtParserAction.parameter:
      case VtParserAction.escapeDispatch:
      case VtParserAction.csiDispatch:
      case VtParserAction.dcsPut:
      case VtParserAction.dcsUnhook:
      case VtParserAction.oscPut:
      case VtParserAction.oscEnd:
      case VtParserAction.stringPut:
      case VtParserAction.stringEnd:
      case VtParserAction.cancel:
      case VtParserAction.utf8:
      case VtParserAction.malformed:
        throw StateError('invalid entry action: ${action.name}');
    }
  }

  void _executeExitAction(
    VtParserAction action,
    VtParserState exitedState,
    int byte, {
    required bool startsSequence,
  }) {
    switch (action) {
      case VtParserAction.none:
        return;
      case VtParserAction.dcsUnhook:
      case VtParserAction.oscEnd:
      case VtParserAction.stringEnd:
        _leaveString(exitedState, byte, startsSequence: startsSequence);
      case VtParserAction.ignore:
      case VtParserAction.print:
      case VtParserAction.execute:
      case VtParserAction.clear:
      case VtParserAction.collect:
      case VtParserAction.parameter:
      case VtParserAction.escapeDispatch:
      case VtParserAction.csiDispatch:
      case VtParserAction.dcsHook:
      case VtParserAction.dcsPut:
      case VtParserAction.oscStart:
      case VtParserAction.oscPut:
      case VtParserAction.stringStart:
      case VtParserAction.stringPut:
      case VtParserAction.cancel:
      case VtParserAction.utf8:
      case VtParserAction.malformed:
        throw StateError('invalid exit action: ${action.name}');
    }
  }

  void _feedUtf8Byte(int byte) {
    _utf8Byte[0] = byte;
    _utf8Decoder.decode(_utf8Byte);
  }

  void _beginSequence() {
    _sequenceBytes = 1;
    _headerRejected = false;
    _limitReported = false;
    _malformedReported = false;
    _clearHeader();
  }

  void _endSequence() {
    _sequenceBytes = 0;
    _headerRejected = false;
    _limitReported = false;
    _malformedReported = false;
    _clearHeader();
  }

  void _countSequenceByte(VtParserState sourceState) {
    if (_sequenceBytes <= limits.maxSequenceBytes) {
      _sequenceBytes++;
    }
    if (_sequenceBytes > limits.maxSequenceBytes) {
      _markLimit(sourceState, VtParserLimitKind.sequenceBytes);
    }
  }

  void _clearHeader() {
    _intermediateCount = 0;
    _parameterCount = 0;
    _privateMarker = null;
  }

  void _collect(int byte, VtParserState sourceState) {
    if (_headerRejected) {
      return;
    }
    if (byte >= 0x3c && byte <= 0x3f && _privateMarker == null) {
      _privateMarker = byte;
      return;
    }
    if (_intermediateCount >= _intermediates.length) {
      _markLimit(sourceState, VtParserLimitKind.intermediates);
      return;
    }
    _intermediates[_intermediateCount++] = byte;
  }

  void _consumeParameter(int byte, VtParserState sourceState) {
    if (_headerRejected) {
      return;
    }
    if (byte >= 0x30 && byte <= 0x39) {
      if (!_ensureParameter(sourceState, isSubparameter: false)) {
        return;
      }
      final int index = _parameterCount - 1;
      final int digit = byte - 0x30;
      final int current = _parameterValues[index];
      final int maximumPrefix = limits.maxNumericValue ~/ 10;
      if (current > maximumPrefix ||
          (current == maximumPrefix && digit > limits.maxNumericValue % 10)) {
        _markLimit(sourceState, VtParserLimitKind.numericValue);
        return;
      }
      _parameterValues[index] = current * 10 + digit;
      _parameterMetadata[index] |= _parameterPresentBit;
      return;
    }

    if (!_ensureParameter(sourceState, isSubparameter: false)) {
      return;
    }
    _appendParameter(sourceState, isSubparameter: byte == 0x3a);
  }

  bool _ensureParameter(
    VtParserState sourceState, {
    required bool isSubparameter,
  }) {
    if (_parameterCount != 0) {
      return true;
    }
    return _appendParameter(sourceState, isSubparameter: isSubparameter);
  }

  bool _appendParameter(
    VtParserState sourceState, {
    required bool isSubparameter,
  }) {
    if (_parameterCount >= _parameterValues.length) {
      _markLimit(sourceState, VtParserLimitKind.parameters);
      return false;
    }
    _parameterValues[_parameterCount] = 0;
    _parameterMetadata[_parameterCount] = isSubparameter
        ? _parameterSubparameterBit
        : 0;
    _parameterCount++;
    return true;
  }

  void _dispatchEscape(int finalByte) {
    if (_stringEscapePending && finalByte == 0x5c) {
      _finalizeString(VtStringTerminator.stringTerminator);
      return;
    }
    if (_headerRejected) {
      return;
    }
    final VtParserUncapturedSequenceSink? uncaptured = _uncapturedSequenceSink;
    if (uncaptured != null) {
      uncaptured.dispatchUncapturedSequence(
        VtUncapturedSequenceKind.escape,
        0,
        0,
        _intermediateCount,
        finalByte,
        0,
        0,
      );
      return;
    }
    sink.dispatchEscape(
      VtEscapeSequence._(
        intermediates: _copyIntermediates(),
        finalByte: finalByte,
      ),
    );
  }

  void _dispatchCsi(int finalByte) {
    if (_headerRejected) {
      return;
    }
    final VtParserUncapturedSequenceSink? uncaptured = _uncapturedSequenceSink;
    if (uncaptured != null) {
      uncaptured.dispatchUncapturedSequence(
        VtUncapturedSequenceKind.controlSequence,
        _privateMarker ?? 0,
        _parameterCount,
        _intermediateCount,
        finalByte,
        0,
        0,
      );
    } else {
      sink.dispatchCsi(_snapshotHeader(finalByte));
    }
  }

  void _startDcsString(VtParserState state, int finalByte) {
    if (_headerRejected) {
      _dcsHeader = null;
    } else if (_uncapturedSequenceSink == null) {
      _dcsHeader = _snapshotHeader(finalByte);
    } else {
      _dcsPrivateMarker = _privateMarker ?? 0;
      _dcsParameterCount = _parameterCount;
      _dcsIntermediateCount = _intermediateCount;
      _dcsFinalByte = finalByte;
    }
    _startString(VtStringKind.deviceControlString, state);
  }

  void _startString(VtStringKind kind, VtParserState state) {
    _stringActive = true;
    _stringRejected = _headerRejected;
    _stringCancelled = false;
    _stringLength = 0;
    _stringKind = kind;
    _stringSourceState = state;
    _stringEscapePending = false;
  }

  void _appendStringByte(int byte, VtParserState sourceState) {
    if (!_stringActive || _stringRejected) {
      return;
    }
    if (_stringLength >= _stringPayload.length) {
      _markLimit(sourceState, VtParserLimitKind.stringBytes);
      return;
    }
    if (_uncapturedSequenceSink == null) {
      _stringPayload[_stringLength] = byte;
    }
    _stringLength++;
  }

  void _leaveString(
    VtParserState sourceState,
    int byte, {
    required bool startsSequence,
  }) {
    if (!_stringActive) {
      return;
    }
    if (_stringCancelled) {
      _discardString();
      return;
    }
    if (byte == 0x1b) {
      _stringEscapePending = true;
      _stringSourceState = sourceState;
      return;
    }
    if (byte == 0x9c) {
      _finalizeString(VtStringTerminator.stringTerminator);
      return;
    }
    if (_stringKind == VtStringKind.operatingSystemCommand && byte == 0x07) {
      _finalizeString(VtStringTerminator.bell);
      return;
    }
    if (startsSequence) {
      if (!_stringRejected) {
        sink.cancel(sourceState, byte);
      }
      _discardString();
    }
  }

  void _cancelPendingString() {
    if (!_stringRejected) {
      sink.cancel(_stringSourceState, 0x1b);
    }
    _discardString();
  }

  void _finalizeString(VtStringTerminator terminator) {
    if (!_stringRejected && !_stringCancelled) {
      final VtParserUncapturedSequenceSink? uncaptured =
          _uncapturedSequenceSink;
      if (uncaptured != null) {
        final bool dcs = _stringKind == VtStringKind.deviceControlString;
        uncaptured.dispatchUncapturedSequence(
          dcs
              ? VtUncapturedSequenceKind.deviceControlString
              : _stringKind == VtStringKind.operatingSystemCommand
              ? VtUncapturedSequenceKind.operatingSystemCommand
              : VtUncapturedSequenceKind.controlString,
          dcs ? _dcsPrivateMarker : 0,
          dcs ? _dcsParameterCount : 0,
          dcs ? _dcsIntermediateCount : 0,
          dcs ? _dcsFinalByte : 0,
          _stringLength,
          terminator.index,
        );
      } else {
        final Uint8List payload = _copyStringPayload();
        if (_stringKind == VtStringKind.deviceControlString) {
          sink.dispatchDcs(
            VtDcsSequence._(
              header: _dcsHeader!,
              payload: payload,
              terminator: terminator,
            ),
          );
        } else {
          final VtStringSequence sequence = VtStringSequence._(
            kind: _stringKind,
            payload: payload,
            terminator: terminator,
          );
          if (_stringKind == VtStringKind.operatingSystemCommand) {
            sink.dispatchOsc(sequence);
          } else {
            sink.dispatchString(sequence);
          }
        }
      }
    }
    _discardString();
  }

  void _discardString() {
    _stringActive = false;
    _stringRejected = false;
    _stringCancelled = false;
    _stringLength = 0;
    _dcsHeader = null;
    _dcsPrivateMarker = 0;
    _dcsParameterCount = 0;
    _dcsIntermediateCount = 0;
    _dcsFinalByte = 0;
    _stringEscapePending = false;
  }

  void _markLimit(VtParserState sourceState, VtParserLimitKind kind) {
    if (_limitReported) {
      return;
    }
    _limitReported = true;
    _headerRejected = true;
    if (_stringActive) {
      _stringRejected = true;
    }
    sink.limit(sourceState, kind);
  }

  void _markMalformed(VtParserState sourceState, int byte) {
    if (_malformedReported || _headerRejected) {
      return;
    }
    _malformedReported = true;
    _headerRejected = true;
    sink.malformed(sourceState, byte);
  }

  VtSequenceHeader _snapshotHeader(int finalByte) => VtSequenceHeader._(
    privateMarker: _privateMarker,
    parameters: _snapshotParameters(),
    intermediates: _copyIntermediates(),
    finalByte: finalByte,
  );

  VtParameters _snapshotParameters() {
    final Uint32List values = Uint32List(_parameterCount)
      ..setRange(0, _parameterCount, _parameterValues);
    final Uint8List metadata = Uint8List(_parameterCount)
      ..setRange(0, _parameterCount, _parameterMetadata);
    return VtParameters._(values, metadata);
  }

  Uint8List _copyIntermediates() =>
      Uint8List(_intermediateCount)
        ..setRange(0, _intermediateCount, _intermediates);

  Uint8List _copyStringPayload() =>
      Uint8List(_stringLength)..setRange(0, _stringLength, _stringPayload);

  VtStringKind _stringKindForIntroducer(int byte) => switch (byte) {
    0x58 || 0x98 => VtStringKind.startOfString,
    0x5e || 0x9e => VtStringKind.privacyMessage,
    0x5f || 0x9f => VtStringKind.applicationProgramCommand,
    _ => throw StateError('invalid string introducer: $byte'),
  };

  void _resetState() {
    _state = VtParserState.ground;
    _discardString();
    _endSequence();
  }
}
