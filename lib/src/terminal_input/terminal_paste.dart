import 'dart:typed_data';

/// Why a paste requires explicit confirmation before any PTY write.
enum TerminalPasteRisk { multiline, controlCharacter, bracketTerminator, large }

final class TerminalPasteLimitException implements Exception {
  const TerminalPasteLimitException({
    required this.limit,
    required this.actual,
  });

  final int limit;
  final int actual;

  @override
  String toString() =>
      'TerminalPasteLimitException: encoded paste exceeds $limit bytes '
      '(at least $actual)';
}

/// Content-free metadata frozen before a paste is confirmed or transported.
final class TerminalPasteAnalysis {
  const TerminalPasteAnalysis._({
    required this.sourceUtf16Length,
    required this.encodedBodyBytes,
    required this.encodedBytes,
    required this.logicalNewlineCount,
    required this.controlCharacterCount,
    required this.replacedControlCount,
    required this.hasBracketTerminator,
    required this.isLarge,
    required this.bracketed,
    required this.fingerprint,
  });

  final int sourceUtf16Length;
  final int encodedBodyBytes;
  final int encodedBytes;
  final int logicalNewlineCount;
  final int controlCharacterCount;
  final int replacedControlCount;
  final bool hasBracketTerminator;
  final bool isLarge;
  final bool bracketed;
  final int fingerprint;

  bool get isEmpty => sourceUtf16Length == 0;
  bool get requiresConfirmation =>
      logicalNewlineCount > 0 ||
      controlCharacterCount > 0 ||
      hasBracketTerminator ||
      isLarge;

  Set<TerminalPasteRisk> get risks =>
      Set<TerminalPasteRisk>.unmodifiable(<TerminalPasteRisk>{
        if (logicalNewlineCount > 0) TerminalPasteRisk.multiline,
        if (controlCharacterCount > 0) TerminalPasteRisk.controlCharacter,
        if (hasBracketTerminator) TerminalPasteRisk.bracketTerminator,
        if (isLarge) TerminalPasteRisk.large,
      });
}

/// One immutable source plus the exact mode-aware metadata used to encode it.
final class TerminalPastePlan {
  const TerminalPastePlan._(this._text, this.analysis);

  final String _text;
  final TerminalPasteAnalysis analysis;

  TerminalPasteChunkEncoder encoder({
    int maximumChunkBytes = TerminalPasteCodec.defaultChunkBytes,
  }) => TerminalPasteChunkEncoder._(
    _text,
    bracketed: analysis.bracketed,
    maximumChunkBytes: maximumChunkBytes,
  );
}

/// Scans and transforms clipboard text without allocating a whole encoded copy.
final class TerminalPasteCodec {
  const TerminalPasteCodec._();

  static const int maximumEncodedBodyBytes = 64 * 1024 * 1024;
  static const int largePasteThresholdBytes = 1024 * 1024;
  static const int defaultChunkBytes = 16 * 1024;
  static const int maximumChunkBytes = 64 * 1024;
  static const int bracketFrameBytes = 12;

  static TerminalPastePlan plan(
    String text, {
    required bool bracketed,
    int maximumBodyBytes = maximumEncodedBodyBytes,
    int largeThresholdBytes = largePasteThresholdBytes,
  }) {
    RangeError.checkValueInInterval(
      maximumBodyBytes,
      1,
      maximumEncodedBodyBytes,
      'maximumBodyBytes',
    );
    RangeError.checkValueInInterval(
      largeThresholdBytes,
      1,
      maximumBodyBytes,
      'largeThresholdBytes',
    );
    var offset = 0;
    var encodedBodyBytes = 0;
    var logicalNewlineCount = 0;
    var controlCharacterCount = 0;
    var replacedControlCount = 0;
    var hasBracketTerminator = false;
    var fingerprint = _fnvOffsetBasis;

    while (offset < text.length) {
      final int first = text.codeUnitAt(offset);
      fingerprint = _fingerprintCodeUnit(fingerprint, first);
      if (first == 0x0d) {
        offset++;
        if (offset < text.length && text.codeUnitAt(offset) == 0x0a) {
          fingerprint = _fingerprintCodeUnit(fingerprint, 0x0a);
          offset++;
        }
        logicalNewlineCount++;
        encodedBodyBytes++;
      } else if (first == 0x0a) {
        offset++;
        logicalNewlineCount++;
        encodedBodyBytes++;
      } else {
        if (first < 0x20 || first == 0x7f) {
          controlCharacterCount++;
        }
        if (_isReplacedControl(first)) {
          replacedControlCount++;
          encodedBodyBytes++;
          offset++;
        } else {
          final _Scalar scalar = _decodeScalar(text, offset);
          if (scalar.nextOffset == offset + 2) {
            fingerprint = _fingerprintCodeUnit(
              fingerprint,
              text.codeUnitAt(offset + 1),
            );
          }
          encodedBodyBytes += _utf8Length(scalar.value);
          offset = scalar.nextOffset;
        }
      }
      if (!hasBracketTerminator &&
          first == 0x1b &&
          text.startsWith(_bracketSuffixText, offset - 1)) {
        hasBracketTerminator = true;
      }
      if (encodedBodyBytes > maximumBodyBytes) {
        throw TerminalPasteLimitException(
          limit: maximumBodyBytes,
          actual: encodedBodyBytes,
        );
      }
    }

    final int encodedBytes = text.isEmpty
        ? 0
        : encodedBodyBytes + (bracketed ? bracketFrameBytes : 0);
    return TerminalPastePlan._(
      text,
      TerminalPasteAnalysis._(
        sourceUtf16Length: text.length,
        encodedBodyBytes: encodedBodyBytes,
        encodedBytes: encodedBytes,
        logicalNewlineCount: logicalNewlineCount,
        controlCharacterCount: controlCharacterCount,
        replacedControlCount: replacedControlCount,
        hasBracketTerminator: hasBracketTerminator,
        isLarge: encodedBodyBytes >= largeThresholdBytes,
        bracketed: bracketed,
        fingerprint: fingerprint,
      ),
    );
  }
}

/// Stateful single-pass encoder with one frame across every returned chunk.
final class TerminalPasteChunkEncoder {
  TerminalPasteChunkEncoder._(
    this._text, {
    required this.bracketed,
    required this.maximumChunkBytes,
  }) {
    RangeError.checkValueInInterval(
      maximumChunkBytes,
      1,
      TerminalPasteCodec.maximumChunkBytes,
      'maximumChunkBytes',
    );
    if (_text.isEmpty) _phase = _PasteEncodingPhase.done;
  }

  final String _text;
  final bool bracketed;
  final int maximumChunkBytes;
  final Uint8List _scalarBytes = Uint8List(4);
  _PasteEncodingPhase _phase = _PasteEncodingPhase.prefix;
  int _sourceOffset = 0;
  int _frameOffset = 0;
  int _scalarLength = 0;
  int _scalarOffset = 0;
  int _emittedBytes = 0;

  bool get isDone => _phase == _PasteEncodingPhase.done;
  int get emittedBytes => _emittedBytes;

  Uint8List? nextChunk() {
    if (isDone) return null;
    final Uint8List chunk = Uint8List(maximumChunkBytes);
    var length = 0;
    while (length < chunk.length) {
      final int? byte = _nextByte();
      if (byte == null) break;
      chunk[length++] = byte;
    }
    if (length == 0) return null;
    _emittedBytes += length;
    return length == chunk.length
        ? chunk
        : Uint8List.sublistView(chunk, 0, length);
  }

  int? _nextByte() {
    while (true) {
      switch (_phase) {
        case _PasteEncodingPhase.prefix:
          if (!bracketed) {
            _phase = _PasteEncodingPhase.body;
            continue;
          }
          if (_frameOffset < _bracketPrefix.length) {
            return _bracketPrefix[_frameOffset++];
          }
          _frameOffset = 0;
          _phase = _PasteEncodingPhase.body;
        case _PasteEncodingPhase.body:
          if (_scalarOffset < _scalarLength) {
            return _scalarBytes[_scalarOffset++];
          }
          if (_sourceOffset >= _text.length) {
            _frameOffset = 0;
            _phase = _PasteEncodingPhase.suffix;
            continue;
          }
          _stageNextScalar();
        case _PasteEncodingPhase.suffix:
          if (!bracketed) {
            _phase = _PasteEncodingPhase.done;
            continue;
          }
          if (_frameOffset < _bracketSuffix.length) {
            return _bracketSuffix[_frameOffset++];
          }
          _phase = _PasteEncodingPhase.done;
        case _PasteEncodingPhase.done:
          return null;
      }
    }
  }

  void _stageNextScalar() {
    final int first = _text.codeUnitAt(_sourceOffset);
    late final int scalar;
    if (first == 0x0d) {
      _sourceOffset++;
      if (_sourceOffset < _text.length &&
          _text.codeUnitAt(_sourceOffset) == 0x0a) {
        _sourceOffset++;
      }
      scalar = bracketed ? 0x0a : 0x0d;
    } else if (first == 0x0a) {
      _sourceOffset++;
      scalar = bracketed ? 0x0a : 0x0d;
    } else if (_isReplacedControl(first)) {
      _sourceOffset++;
      scalar = 0x20;
    } else {
      final _Scalar decoded = _decodeScalar(_text, _sourceOffset);
      _sourceOffset = decoded.nextOffset;
      scalar = decoded.value;
    }
    _scalarLength = _encodeScalar(scalar, _scalarBytes);
    _scalarOffset = 0;
  }
}

enum _PasteEncodingPhase { prefix, body, suffix, done }

final class _Scalar {
  const _Scalar(this.value, this.nextOffset);

  final int value;
  final int nextOffset;
}

const int _fnvOffsetBasis = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;
const int _uint64Mask = 0xffffffffffffffff;
const String _bracketSuffixText = '\x1b[201~';
final Uint8List _bracketPrefix = Uint8List.fromList(const <int>[
  0x1b,
  0x5b,
  0x32,
  0x30,
  0x30,
  0x7e,
]);
final Uint8List _bracketSuffix = Uint8List.fromList(const <int>[
  0x1b,
  0x5b,
  0x32,
  0x30,
  0x31,
  0x7e,
]);

int _fingerprintCodeUnit(int hash, int codeUnit) {
  var next = ((hash ^ (codeUnit & 0xff)) * _fnvPrime) & _uint64Mask;
  next = ((next ^ (codeUnit >> 8)) * _fnvPrime) & _uint64Mask;
  return next;
}

bool _isReplacedControl(int value) => switch (value) {
  0x00 ||
  0x03 ||
  0x04 ||
  0x05 ||
  0x08 ||
  0x0f ||
  0x11 ||
  0x12 ||
  0x13 ||
  0x15 ||
  0x16 ||
  0x17 ||
  0x1a ||
  0x1b ||
  0x1c ||
  0x7f => true,
  _ => false,
};

_Scalar _decodeScalar(String text, int offset) {
  final int first = text.codeUnitAt(offset);
  if (first >= 0xd800 && first <= 0xdbff) {
    final int next = offset + 1;
    if (next < text.length) {
      final int second = text.codeUnitAt(next);
      if (second >= 0xdc00 && second <= 0xdfff) {
        return _Scalar(
          0x10000 + ((first - 0xd800) << 10) + second - 0xdc00,
          next + 1,
        );
      }
    }
    return _Scalar(0xfffd, offset + 1);
  }
  if (first >= 0xdc00 && first <= 0xdfff) {
    return _Scalar(0xfffd, offset + 1);
  }
  return _Scalar(first, offset + 1);
}

int _utf8Length(int scalar) => switch (scalar) {
  <= 0x7f => 1,
  <= 0x7ff => 2,
  <= 0xffff => 3,
  _ => 4,
};

int _encodeScalar(int scalar, Uint8List output) {
  if (scalar <= 0x7f) {
    output[0] = scalar;
    return 1;
  }
  if (scalar <= 0x7ff) {
    output[0] = 0xc0 | (scalar >> 6);
    output[1] = 0x80 | (scalar & 0x3f);
    return 2;
  }
  if (scalar <= 0xffff) {
    output[0] = 0xe0 | (scalar >> 12);
    output[1] = 0x80 | ((scalar >> 6) & 0x3f);
    output[2] = 0x80 | (scalar & 0x3f);
    return 3;
  }
  output[0] = 0xf0 | (scalar >> 18);
  output[1] = 0x80 | ((scalar >> 12) & 0x3f);
  output[2] = 0x80 | ((scalar >> 6) & 0x3f);
  output[3] = 0x80 | (scalar & 0x3f);
  return 4;
}
