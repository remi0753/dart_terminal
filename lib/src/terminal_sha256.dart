/// Returns the lowercase SHA-256 digest of [source].
///
/// This small Dart-only implementation keeps runtime resource validation free
/// of native/process dependencies. Inputs are already bounded by each caller,
/// and the digest keeps only one 64-byte block plus its word schedule.
String terminalSha256(List<int> source) {
  final _TerminalSha256 digest = _TerminalSha256();
  for (var index = 0; index < source.length; index++) {
    digest.addByte(source[index]);
  }
  return digest.close();
}

/// Returns the SHA-256 digest of the standard UTF-8 encoding of [source].
///
/// UTF-16 code units are converted directly into the bounded digest state so
/// callers do not need an input-sized intermediate byte list. Unpaired
/// surrogates use the same U+FFFD replacement as Dart's standard UTF-8 codec.
String terminalSha256Utf8(String source) {
  final _TerminalSha256 digest = _TerminalSha256();
  for (var index = 0; index < source.length; index++) {
    final int first = source.codeUnitAt(index);
    if (first < 0x80) {
      digest.addByte(first);
    } else if (first < 0x800) {
      digest.addCodePoint(first);
    } else if (first >= 0xd800 && first <= 0xdbff) {
      if (index + 1 < source.length) {
        final int second = source.codeUnitAt(index + 1);
        if (second >= 0xdc00 && second <= 0xdfff) {
          digest.addCodePoint(
            0x10000 + ((first - 0xd800) << 10) + second - 0xdc00,
          );
          index++;
          continue;
        }
      }
      digest.addCodePoint(0xfffd);
    } else if (first >= 0xdc00 && first <= 0xdfff) {
      digest.addCodePoint(0xfffd);
    } else {
      digest.addCodePoint(first);
    }
  }
  return digest.close();
}

final class _TerminalSha256 {
  static const List<int> _constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final List<int> _hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final List<int> _block = List<int>.filled(64, 0);
  final List<int> _words = List<int>.filled(64, 0);
  var _blockLength = 0;
  var _byteLength = 0;
  var _closed = false;

  @pragma('vm:prefer-inline')
  void addByte(int value) {
    if (_closed) throw StateError('SHA-256 digest is closed');
    _block[_blockLength++] = value;
    _byteLength++;
    if (_blockLength == 64) {
      _compress();
      _blockLength = 0;
    }
  }

  @pragma('vm:prefer-inline')
  void addCodePoint(int value) {
    if (value < 0x80) {
      addByte(value);
    } else if (value < 0x800) {
      addByte(0xc0 | (value >> 6));
      addByte(0x80 | (value & 0x3f));
    } else if (value < 0x10000) {
      addByte(0xe0 | (value >> 12));
      addByte(0x80 | ((value >> 6) & 0x3f));
      addByte(0x80 | (value & 0x3f));
    } else {
      addByte(0xf0 | (value >> 18));
      addByte(0x80 | ((value >> 12) & 0x3f));
      addByte(0x80 | ((value >> 6) & 0x3f));
      addByte(0x80 | (value & 0x3f));
    }
  }

  String close() {
    if (_closed) throw StateError('SHA-256 digest is closed');
    final int bitLength = _byteLength * 8;
    _block[_blockLength++] = 0x80;
    if (_blockLength > 56) {
      while (_blockLength < 64) {
        _block[_blockLength++] = 0;
      }
      _compress();
      _blockLength = 0;
    }
    while (_blockLength < 56) {
      _block[_blockLength++] = 0;
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      _block[_blockLength++] = (bitLength >> shift) & 0xff;
    }
    _compress();
    _blockLength = 0;
    _closed = true;
    return _hash
        .map((int value) => value.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  void _compress() {
    for (var index = 0; index < 16; index++) {
      final int offset = index * 4;
      _words[index] =
          (_block[offset] << 24) |
          (_block[offset + 1] << 16) |
          (_block[offset + 2] << 8) |
          _block[offset + 3];
    }
    for (var index = 16; index < 64; index++) {
      final int left = _words[index - 15];
      final int right = _words[index - 2];
      final int sigma0 =
          _rotateRight(left, 7) ^ _rotateRight(left, 18) ^ (left >> 3);
      final int sigma1 =
          _rotateRight(right, 17) ^ _rotateRight(right, 19) ^ (right >> 10);
      _words[index] =
          (_words[index - 16] + sigma0 + _words[index - 7] + sigma1) &
          0xffffffff;
    }
    int a = _hash[0];
    int b = _hash[1];
    int c = _hash[2];
    int d = _hash[3];
    int e = _hash[4];
    int f = _hash[5];
    int g = _hash[6];
    int h = _hash[7];
    for (var index = 0; index < 64; index++) {
      final int sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final int choice = (e & f) ^ ((~e) & g);
      final int temporary1 =
          (h + sum1 + choice + _constants[index] + _words[index]) & 0xffffffff;
      final int sum0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temporary2 = (sum0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) & 0xffffffff;
    }
    _hash[0] = (_hash[0] + a) & 0xffffffff;
    _hash[1] = (_hash[1] + b) & 0xffffffff;
    _hash[2] = (_hash[2] + c) & 0xffffffff;
    _hash[3] = (_hash[3] + d) & 0xffffffff;
    _hash[4] = (_hash[4] + e) & 0xffffffff;
    _hash[5] = (_hash[5] + f) & 0xffffffff;
    _hash[6] = (_hash[6] + g) & 0xffffffff;
    _hash[7] = (_hash[7] + h) & 0xffffffff;
  }
}

int _rotateRight(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xffffffff;
