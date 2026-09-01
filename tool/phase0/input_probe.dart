import 'dart:typed_data';

const int inputKeyText = 0;
const int inputKeyEnter = 1;
const int inputKeyTab = 2;
const int inputKeyBackspace = 3;
const int inputKeyEscape = 4;
const int inputKeyUp = 5;
const int inputKeyDown = 6;
const int inputKeyRight = 7;
const int inputKeyLeft = 8;
const int inputKeyHome = 9;
const int inputKeyEnd = 10;
const int inputKeyDelete = 11;

const int inputModifierShift = 1 << 0;
const int inputModifierAlt = 1 << 1;
const int inputModifierControl = 1 << 2;

const int inputModeApplicationCursor = 1 << 0;

final class InputEncoderProbe {
  final Uint8List bytes = Uint8List(16);

  int encode({
    required int key,
    required int scalar,
    required int modifiers,
    required int modes,
  }) {
    int length = 0;
    if (key == inputKeyText) {
      if (scalar <= 0 || scalar > 0x10ffff) {
        return 0;
      }
      if ((modifiers & inputModifierAlt) != 0) {
        bytes[length++] = 0x1b;
      }
      if ((modifiers & inputModifierControl) != 0 &&
          scalar >= 0x40 &&
          scalar <= 0x7f) {
        bytes[length++] = scalar & 0x1f;
        return length;
      }
      return length + _writeUtf8(scalar, length);
    }

    switch (key) {
      case inputKeyEnter:
        bytes[0] = 0x0d;
        return 1;
      case inputKeyTab:
        bytes[0] = 0x09;
        return 1;
      case inputKeyBackspace:
        bytes[0] = 0x7f;
        return 1;
      case inputKeyEscape:
        bytes[0] = 0x1b;
        return 1;
      case inputKeyUp:
      case inputKeyDown:
      case inputKeyRight:
      case inputKeyLeft:
      case inputKeyHome:
      case inputKeyEnd:
        final int finalByte = switch (key) {
          inputKeyUp => 0x41,
          inputKeyDown => 0x42,
          inputKeyRight => 0x43,
          inputKeyLeft => 0x44,
          inputKeyHome => 0x48,
          inputKeyEnd => 0x46,
          _ => throw StateError('unreachable cursor key'),
        };
        final int xtermModifier =
            1 +
            ((modifiers & inputModifierShift) != 0 ? 1 : 0) +
            ((modifiers & inputModifierAlt) != 0 ? 2 : 0) +
            ((modifiers & inputModifierControl) != 0 ? 4 : 0);
        bytes[0] = 0x1b;
        if (xtermModifier != 1) {
          bytes[1] = 0x5b;
          bytes[2] = 0x31;
          bytes[3] = 0x3b;
          final int digits = _writeDecimal(xtermModifier, 4);
          bytes[4 + digits] = finalByte;
          return 5 + digits;
        }
        bytes[1] = (modes & inputModeApplicationCursor) != 0 ? 0x4f : 0x5b;
        bytes[2] = finalByte;
        return 3;
      case inputKeyDelete:
        bytes[0] = 0x1b;
        bytes[1] = 0x5b;
        bytes[2] = 0x33;
        bytes[3] = 0x7e;
        return 4;
      default:
        return 0;
    }
  }

  int _writeUtf8(int scalar, int offset) {
    if (scalar <= 0x7f) {
      bytes[offset] = scalar;
      return 1;
    }
    if (scalar <= 0x7ff) {
      bytes[offset] = 0xc0 | (scalar >> 6);
      bytes[offset + 1] = 0x80 | (scalar & 0x3f);
      return 2;
    }
    if (scalar >= 0xd800 && scalar <= 0xdfff) {
      return 0;
    }
    if (scalar <= 0xffff) {
      bytes[offset] = 0xe0 | (scalar >> 12);
      bytes[offset + 1] = 0x80 | ((scalar >> 6) & 0x3f);
      bytes[offset + 2] = 0x80 | (scalar & 0x3f);
      return 3;
    }
    bytes[offset] = 0xf0 | (scalar >> 18);
    bytes[offset + 1] = 0x80 | ((scalar >> 12) & 0x3f);
    bytes[offset + 2] = 0x80 | ((scalar >> 6) & 0x3f);
    bytes[offset + 3] = 0x80 | (scalar & 0x3f);
    return 4;
  }

  int _writeDecimal(int value, int offset) {
    if (value < 10) {
      bytes[offset] = 0x30 + value;
      return 1;
    }
    bytes[offset] = 0x30 + value ~/ 10;
    bytes[offset + 1] = 0x30 + value % 10;
    return 2;
  }
}

final class BoundedByteQueueProbe {
  BoundedByteQueueProbe(int capacity) : _storage = Uint8List(capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity');
    }
  }

  final Uint8List _storage;
  int _head = 0;
  int _tail = 0;
  int _length = 0;
  int maxLength = 0;

  int get length => _length;
  int get capacity => _storage.length;

  bool enqueue(Uint8List source, int length) {
    if (length < 0 || length > source.length) {
      throw RangeError('invalid queue source length');
    }
    if (length > capacity - _length) {
      return false;
    }
    for (int index = 0; index < length; index++) {
      _storage[_tail] = source[index];
      _tail = (_tail + 1) % capacity;
    }
    _length += length;
    if (_length > maxLength) {
      maxLength = _length;
    }
    return true;
  }

  int drain(int maximumBytes) {
    if (maximumBytes < 0) {
      throw RangeError.value(maximumBytes, 'maximumBytes');
    }
    final int drained = maximumBytes < _length ? maximumBytes : _length;
    _head = (_head + drained) % capacity;
    _length -= drained;
    return drained;
  }

  int drainInto(Uint8List destination, int maximumBytes) {
    if (maximumBytes < 0) {
      throw RangeError.value(maximumBytes, 'maximumBytes');
    }
    var drained = maximumBytes < _length ? maximumBytes : _length;
    if (drained > destination.length) {
      drained = destination.length;
    }
    for (int index = 0; index < drained; index++) {
      destination[index] = _storage[_head];
      _head = (_head + 1) % capacity;
    }
    _length -= drained;
    return drained;
  }
}
