import 'package:dart_terminal/src/terminal_system_entropy.dart';

void main() => runTerminalSystemEntropyTests();

void runTerminalSystemEntropyTests() {
  final List<int> first = TerminalSystemEntropy.bytes(16);
  final List<int> second = TerminalSystemEntropy.bytes(16);
  _expect(
    first.length == 16 &&
        second.length == 16 &&
        first.every((int byte) => byte >= 0 && byte <= 0xff) &&
        second.every((int byte) => byte >= 0 && byte <= 0xff) &&
        !_sameBytes(first, second),
    'system entropy did not produce two distinct bounded identifiers',
  );
  for (final int invalid in <int>[0, -1, 4097]) {
    try {
      TerminalSystemEntropy.bytes(invalid);
      throw StateError('invalid entropy request was accepted: $invalid');
    } on RangeError {
      // Expected.
    }
  }
}

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
