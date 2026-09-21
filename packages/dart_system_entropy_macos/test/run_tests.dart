import 'dart:io';

import 'package:dart_system_entropy_macos/dart_system_entropy_macos.dart';

void main() {
  final List<int> first = MacosSystemEntropy.bytes(16);
  final List<int> second = MacosSystemEntropy.bytes(16);
  final List<int> maximum = MacosSystemEntropy.bytes(
    MacosSystemEntropy.maximumRequestBytes,
  );
  _expect(
    first.length == 16 &&
        second.length == 16 &&
        maximum.length == MacosSystemEntropy.maximumRequestBytes &&
        first.every(_isByte) &&
        second.every(_isByte) &&
        maximum.every(_isByte) &&
        !_sameBytes(first, second),
    'system entropy bytes are bounded and distinct',
  );

  try {
    first[0] = first[0];
    throw StateError('system entropy result is mutable');
  } on UnsupportedError {
    // Expected.
  }

  for (final int invalid in <int>[
    -1,
    0,
    MacosSystemEntropy.maximumRequestBytes + 1,
  ]) {
    try {
      MacosSystemEntropy.bytes(invalid);
      throw StateError('invalid entropy request was accepted: $invalid');
    } on RangeError {
      // Expected.
    }
  }

  stdout.writeln(
    'DART_SYSTEM_ENTROPY_MACOS_PASS bounded=true immutable=true '
    'content_free=true',
  );
}

bool _isByte(int value) => value >= 0 && value <= 0xff;

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
