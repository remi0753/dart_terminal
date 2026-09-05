import 'dart:convert';
import 'dart:io';

const String _unicodeVersion = '17.0.0';
const String _defaultOutput =
    'lib/src/terminal_core/generated/unicode_tables.g.dart';

const Map<String, String> _inputUrls = <String, String>{
  'EastAsianWidth.txt':
      'https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt',
  'GraphemeBreakProperty.txt':
      'https://www.unicode.org/Public/17.0.0/ucd/auxiliary/'
      'GraphemeBreakProperty.txt',
  'emoji-data.txt':
      'https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt',
  'DerivedCoreProperties.txt':
      'https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt',
};

const Map<String, String> _inputHashes = <String, String>{
  'EastAsianWidth.txt':
      'ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33',
  'GraphemeBreakProperty.txt':
      'd6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89',
  'emoji-data.txt':
      '2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b',
  'DerivedCoreProperties.txt':
      '24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08',
};

const Map<String, int> _graphemeBreakCodes = <String, int>{
  'CR': 1,
  'LF': 2,
  'Control': 3,
  'Extend': 4,
  'ZWJ': 5,
  'Regional_Indicator': 6,
  'Prepend': 7,
  'SpacingMark': 8,
  'L': 9,
  'V': 10,
  'T': 11,
  'LV': 12,
  'LVT': 13,
};

const Map<String, int> _indicConjunctCodes = <String, int>{
  'Consonant': 1,
  'Extend': 2,
  'Linker': 3,
};

final class _Range {
  const _Range(this.start, this.end, [this.value = 1]);

  final int start;
  final int end;
  final int value;
}

void main(List<String> arguments) {
  var check = false;
  String? inputDirectory;
  var output = _defaultOutput;
  for (var index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '--check') {
      check = true;
    } else if (argument == '--ucd-dir' && index + 1 < arguments.length) {
      inputDirectory = arguments[++index];
    } else if (argument.startsWith('--ucd-dir=')) {
      inputDirectory = argument.substring('--ucd-dir='.length);
    } else if (argument == '--output' && index + 1 < arguments.length) {
      output = arguments[++index];
    } else if (argument.startsWith('--output=')) {
      output = argument.substring('--output='.length);
    } else {
      stderr.writeln('Unknown or incomplete argument: $argument');
      exitCode = 64;
      return;
    }
  }
  if (inputDirectory == null) {
    stderr.writeln(
      'Usage: dart run tool/generate_unicode_tables.dart '
      '--ucd-dir <Unicode 17 data directory> [--check] [--output <path>]',
    );
    exitCode = 64;
    return;
  }

  final Directory directory = Directory(inputDirectory);
  final Map<String, String> inputs = <String, String>{};
  for (final MapEntry<String, String> input in _inputHashes.entries) {
    final File file = File('${directory.path}/${input.key}');
    if (!file.existsSync()) {
      stderr.writeln('Missing Unicode input: ${file.path}');
      exitCode = 66;
      return;
    }
    final List<int> bytes = file.readAsBytesSync();
    final String actualHash = _sha256(bytes);
    if (actualHash != input.value) {
      stderr.writeln(
        'Unicode input hash mismatch for ${input.key}: '
        'expected ${input.value}, got $actualHash',
      );
      exitCode = 65;
      return;
    }
    inputs[input.key] = utf8.decode(bytes);
  }

  final List<_Range> wide = _mergeRanges(
    _parsePropertyRanges(
      inputs['EastAsianWidth.txt']!,
      propertyField: 1,
      accepted: const <String, int>{'W': 1, 'F': 1},
    ),
  );
  final List<_Range> graphemeBreak = _mergeRanges(
    _parsePropertyRanges(
      inputs['GraphemeBreakProperty.txt']!,
      propertyField: 1,
      accepted: _graphemeBreakCodes,
    ),
  );
  final List<_Range> extendedPictographic = _mergeRanges(
    _parsePropertyRanges(
      inputs['emoji-data.txt']!,
      propertyField: 1,
      accepted: const <String, int>{'Extended_Pictographic': 1},
    ),
  );
  final List<_Range> emojiPresentation = _mergeRanges(
    _parsePropertyRanges(
      inputs['emoji-data.txt']!,
      propertyField: 1,
      accepted: const <String, int>{'Emoji_Presentation': 1},
    ),
  );
  final List<_Range> indicConjunct = _mergeRanges(
    _parsePropertyRanges(
      inputs['DerivedCoreProperties.txt']!,
      propertyField: 2,
      requiredPrefix: 'InCB',
      accepted: _indicConjunctCodes,
    ),
  );

  final String generated = _render(
    wide: wide,
    graphemeBreak: graphemeBreak,
    extendedPictographic: extendedPictographic,
    emojiPresentation: emojiPresentation,
    indicConjunct: indicConjunct,
  );
  final File outputFile = File(output);
  if (check) {
    if (!outputFile.existsSync() ||
        outputFile.readAsStringSync() != generated) {
      stderr.writeln(
        '$output is stale; regenerate it with generate_unicode_tables.dart.',
      );
      exitCode = 1;
    }
    return;
  }
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(generated);
}

List<_Range> _parsePropertyRanges(
  String source, {
  required int propertyField,
  required Map<String, int> accepted,
  String? requiredPrefix,
}) {
  final List<_Range> result = <_Range>[];
  for (final String originalLine in const LineSplitter().convert(source)) {
    final String line = originalLine.split('#').first.trim();
    if (line.isEmpty) {
      continue;
    }
    final List<String> fields = line
        .split(';')
        .map((String field) => field.trim())
        .toList(growable: false);
    if (requiredPrefix != null &&
        (fields.length < 2 || fields[1] != requiredPrefix)) {
      continue;
    }
    if (propertyField >= fields.length) {
      continue;
    }
    final int? value = accepted[fields[propertyField]];
    if (value == null) {
      continue;
    }
    final List<String> bounds = fields.first.split('..');
    final int start = int.parse(bounds.first, radix: 16);
    final int end = int.parse(
      bounds.length == 1 ? bounds.first : bounds.last,
      radix: 16,
    );
    result.add(_Range(start, end, value));
  }
  result.sort((_Range left, _Range right) => left.start.compareTo(right.start));
  return result;
}

List<_Range> _mergeRanges(List<_Range> ranges) {
  if (ranges.isEmpty) {
    return ranges;
  }
  final List<_Range> merged = <_Range>[];
  var current = ranges.first;
  for (final _Range next in ranges.skip(1)) {
    if (next.start <= current.end) {
      throw StateError('overlapping Unicode property ranges');
    }
    if (next.start == current.end + 1 && next.value == current.value) {
      current = _Range(current.start, next.end, current.value);
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

String _render({
  required List<_Range> wide,
  required List<_Range> graphemeBreak,
  required List<_Range> extendedPictographic,
  required List<_Range> emojiPresentation,
  required List<_Range> indicConjunct,
}) {
  final StringBuffer output = StringBuffer()
    ..writeln('// Generated by tool/generate_unicode_tables.dart. Do not edit.')
    ..writeln(
      '// Unicode $_unicodeVersion; inputs are hash-verified by the generator.',
    )
    ..writeln()
    ..writeln("const String terminalUnicodeVersion = '$_unicodeVersion';")
    ..writeln()
    ..writeln('// dart format off')
    ..writeln('const Map<String, String> terminalUnicodeInputSha256 =')
    ..writeln('    <String, String>{');
  for (final MapEntry<String, String> input in _inputHashes.entries) {
    output.writeln("      '${input.key}': '${input.value}',");
  }
  output
    ..writeln('    };')
    ..writeln()
    ..writeln('const Map<String, String> terminalUnicodeInputUrls =')
    ..writeln('    <String, String>{');
  for (final MapEntry<String, String> input in _inputUrls.entries) {
    output.writeln("      '${input.key}': '${input.value}',");
  }
  output
    ..writeln('    };')
    ..writeln()
    ..write(_renderRanges('terminalUnicodeWideRanges', wide, valued: false))
    ..writeln()
    ..write(_renderRanges('terminalGraphemeBreakRanges', graphemeBreak))
    ..writeln()
    ..write(
      _renderRanges(
        'terminalExtendedPictographicRanges',
        extendedPictographic,
        valued: false,
      ),
    )
    ..writeln()
    ..write(
      _renderRanges(
        'terminalEmojiPresentationRanges',
        emojiPresentation,
        valued: false,
      ),
    )
    ..writeln()
    ..write(_renderRanges('terminalIndicConjunctRanges', indicConjunct))
    ..writeln('// dart format on');
  return output.toString();
}

String _renderRanges(String name, List<_Range> ranges, {bool valued = true}) {
  final List<int> values = <int>[];
  for (final _Range range in ranges) {
    values
      ..add(range.start)
      ..add(range.end + 1);
    if (valued) {
      values.add(range.value);
    }
  }
  final StringBuffer output = StringBuffer('const List<int> $name = <int>[');
  for (var offset = 0; offset < values.length; offset += 9) {
    final int end = (offset + 9).clamp(0, values.length);
    final String line = values
        .sublist(offset, end)
        .map((int value) => '0x${value.toRadixString(16)}')
        .join(', ');
    output.write('\n  $line,');
  }
  return '${output.toString()}\n];\n';
}

String _sha256(List<int> source) {
  const List<int> constants = <int>[
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
  final List<int> bytes = List<int>.of(source)..add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  final int bitLength = source.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }
  final List<int> hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final List<int> words = List<int>.filled(64, 0);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final int byteOffset = offset + index * 4;
      words[index] =
          (bytes[byteOffset] << 24) |
          (bytes[byteOffset + 1] << 16) |
          (bytes[byteOffset + 2] << 8) |
          bytes[byteOffset + 3];
    }
    for (var index = 16; index < 64; index++) {
      final int left = words[index - 15];
      final int right = words[index - 2];
      final int sigma0 =
          _rotateRight(left, 7) ^ _rotateRight(left, 18) ^ (left >> 3);
      final int sigma1 =
          _rotateRight(right, 17) ^ _rotateRight(right, 19) ^ (right >> 10);
      words[index] =
          (words[index - 16] + sigma0 + words[index - 7] + sigma1) & 0xffffffff;
    }
    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final int sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final int choice = (e & f) ^ ((~e) & g);
      final int temporary1 =
          (h + sum1 + choice + constants[index] + words[index]) & 0xffffffff;
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
    final List<int> compressed = <int>[a, b, c, d, e, f, g, h];
    for (var index = 0; index < hash.length; index++) {
      hash[index] = (hash[index] + compressed[index]) & 0xffffffff;
    }
  }
  return hash
      .map((int value) => value.toRadixString(16).padLeft(8, '0'))
      .join();
}

int _rotateRight(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xffffffff;
