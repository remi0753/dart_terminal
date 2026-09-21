import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _Arc4RandomBufferNative = Void Function(Pointer<Void>, Size);
typedef _Arc4RandomBufferDart = void Function(Pointer<Void>, int);

/// Application-owned cryptographically secure entropy supplied by macOS.
///
/// The embedded Dart runtime intentionally does not assume that
/// `Random.secure()` is available. This adapter keeps that platform detail in
/// dart_terminal and exposes only an injectable byte source to product code.
abstract final class TerminalSystemEntropy {
  static const int maximumRequestBytes = 4096;

  static final _Arc4RandomBufferDart _fill = DynamicLibrary.process()
      .lookupFunction<_Arc4RandomBufferNative, _Arc4RandomBufferDart>(
        'arc4random_buf',
      );

  static List<int> bytes(int length) {
    if (length <= 0 || length > maximumRequestBytes) {
      throw RangeError.range(length, 1, maximumRequestBytes, 'length');
    }
    final Pointer<Uint8> buffer = calloc<Uint8>(length);
    try {
      _fill(buffer.cast<Void>(), length);
      return List<int>.unmodifiable(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }
}
