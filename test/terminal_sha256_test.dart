import 'dart:collection';
import 'dart:convert';

import 'package:dart_terminal/src/terminal_sha256.dart';

void main() => runTerminalSha256Tests();

void runTerminalSha256Tests() {
  _testPublishedVectorsAndPaddingBoundaries();
  _testIndexedInputIsNotMaterialized();
}

void _testPublishedVectorsAndPaddingBoundaries() {
  const Map<int, String> repeatedA = <int, String>{
    0: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    1: 'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb',
    55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
    56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
    57: 'f13b2d724659eb3bf47f2dd6af1accc87b81f09f59f2b75e5c0bed6589dfe8c6',
    63: '7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34',
    64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
    65: '635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0',
    1000: '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3',
  };
  for (final MapEntry<int, String> vector in repeatedA.entries) {
    final List<int> source = utf8.encode('a' * vector.key);
    _expect(
      terminalSha256(source) == vector.value,
      'SHA-256 differs at the ${vector.key}-byte padding boundary',
    );
  }
  _expect(
    terminalSha256(utf8.encode('abc')) ==
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'SHA-256 differs from the published abc vector',
  );
}

void _testIndexedInputIsNotMaterialized() {
  final _IndexedZeroBytes source = _IndexedZeroBytes(1024 * 1024);
  _expect(
    terminalSha256(source) ==
        '30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58',
    'SHA-256 differs for the one-MiB indexed vector',
  );
  _expect(
    source.readCount == source.length,
    'SHA-256 must read an indexed byte source exactly once',
  );
}

final class _IndexedZeroBytes extends ListBase<int> {
  _IndexedZeroBytes(this._length);

  final int _length;
  var readCount = 0;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('fixed length');

  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);
    readCount++;
    return 0;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');

  @override
  Iterator<int> get iterator =>
      throw StateError('SHA-256 must not iterate or copy the input');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
