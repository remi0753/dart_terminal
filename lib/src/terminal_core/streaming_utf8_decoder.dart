import 'dart:typed_data';

/// Receives one decoded Unicode scalar at a time.
///
/// Malformed input and an incomplete sequence passed to [finish] are reported
/// as U+FFFD through the same callback.
typedef Utf8ScalarSink = void Function(int scalar);

/// Incrementally decodes UTF-8 without retaining input chunks.
///
/// A malformed continuation emits one replacement for the pending sequence,
/// then reprocesses the interrupting byte as a possible ASCII byte or new UTF-8
/// lead. Overlong encodings, surrogate scalars, and values above U+10FFFF emit
/// one replacement after their complete encoded sequence. This policy matches
/// the byte-order recovery contract established by the Phase 0 parser corpus.
final class StreamingUtf8Decoder {
  StreamingUtf8Decoder({required Utf8ScalarSink onScalar})
    : _onScalar = onScalar;

  static const int replacementScalar = 0xfffd;

  final Utf8ScalarSink _onScalar;

  int _continuationsNeeded = 0;
  int _scalar = 0;
  int _minimumScalar = 0;

  /// Whether no partial UTF-8 sequence is retained between chunks.
  bool get isAccepting => _continuationsNeeded == 0;

  /// The number of continuation bytes still needed by the pending sequence.
  int get pendingContinuationCount => _continuationsNeeded;

  /// Decodes a byte slice and synchronously reports scalars to the sink.
  ///
  /// Empty slices are accepted. Invalid slice bounds are cold-path programming
  /// errors and throw [RangeError]; malformed bytes never throw here.
  void decode(Uint8List bytes, [int start = 0, int? end]) {
    final int limit = end ?? bytes.length;
    RangeError.checkValidRange(start, limit, bytes.length);

    int index = start;
    while (index < limit) {
      if (_continuationsNeeded == 0) {
        int byte = bytes[index];
        if (byte <= 0x7f) {
          do {
            _onScalar(byte);
            index++;
            if (index >= limit) {
              break;
            }
            byte = bytes[index];
          } while (byte <= 0x7f);
          continue;
        }
      }
      _decodeByte(bytes[index]);
      index++;
    }
  }

  /// Flushes an incomplete sequence as U+FFFD and leaves the decoder reusable.
  void finish() {
    if (_continuationsNeeded == 0) {
      return;
    }
    _clearPending();
    _onScalar(replacementScalar);
  }

  /// Discards any incomplete sequence without emitting a scalar.
  void reset() => _clearPending();

  void _decodeByte(int byte) {
    while (true) {
      if (_continuationsNeeded == 0) {
        if (byte <= 0x7f) {
          _onScalar(byte);
        } else if (byte >= 0xc2 && byte <= 0xdf) {
          _continuationsNeeded = 1;
          _scalar = byte & 0x1f;
          _minimumScalar = 0x80;
        } else if (byte >= 0xe0 && byte <= 0xef) {
          _continuationsNeeded = 2;
          _scalar = byte & 0x0f;
          _minimumScalar = 0x800;
        } else if (byte >= 0xf0 && byte <= 0xf4) {
          _continuationsNeeded = 3;
          _scalar = byte & 0x07;
          _minimumScalar = 0x10000;
        } else {
          _onScalar(replacementScalar);
        }
        return;
      }

      if (byte < 0x80 || byte > 0xbf) {
        _clearPending();
        _onScalar(replacementScalar);
        continue;
      }

      _scalar = (_scalar << 6) | (byte & 0x3f);
      _continuationsNeeded--;
      if (_continuationsNeeded != 0) {
        return;
      }

      final int scalar = _scalar;
      final bool isValid =
          scalar >= _minimumScalar &&
          scalar <= 0x10ffff &&
          (scalar < 0xd800 || scalar > 0xdfff);
      _scalar = 0;
      _minimumScalar = 0;
      _onScalar(isValid ? scalar : replacementScalar);
      return;
    }
  }

  void _clearPending() {
    _continuationsNeeded = 0;
    _scalar = 0;
    _minimumScalar = 0;
  }
}
