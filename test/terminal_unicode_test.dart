import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalUnicodeTests();

void runTerminalUnicodeTests() {
  _testWidthPolicyAndPropertyBoundaries();
  _testOfficialGraphemeConformance();
  _testBreakerResetAndInvalidInput();
  _testBoundedGraphemeTable();
}

void _testWidthPolicyAndPropertyBoundaries() {
  _expect(TerminalUnicode.version == '17.0.0', 'Unicode version is pinned');
  _expect(TerminalUnicode.scalarWidth(0x41) == 1, 'ASCII is narrow');
  _expect(TerminalUnicode.scalarWidth(0x10ff) == 1, 'before wide boundary');
  _expect(TerminalUnicode.scalarWidth(0x1100) == 2, 'wide boundary start');
  _expect(TerminalUnicode.scalarWidth(0x115f) == 2, 'wide boundary end');
  _expect(TerminalUnicode.scalarWidth(0x1160) == 1, 'after wide boundary');
  _expect(TerminalUnicode.scalarWidth(0x00b7) == 1, 'ambiguous is narrow');
  _expect(TerminalUnicode.scalarWidth(0x0301) == 0, 'extend is zero width');
  _expect(TerminalUnicode.scalarWidth(0x200d) == 0, 'ZWJ is zero width');
  _expect(TerminalUnicode.scalarWidth(0x0000) == 0, 'control is zero width');
  _expect(TerminalUnicode.scalarWidth(0x1f600) == 2, 'emoji is wide');
  _expect(
    TerminalUnicode.isExtendedPictographic(0x00a9) &&
        !TerminalUnicode.isEmojiPresentation(0x00a9),
    'text-default pictograph properties remain distinct',
  );
  _expect(
    TerminalUnicode.clusterWidth(const <int>[0x00a9]) == 1 &&
        TerminalUnicode.clusterWidth(const <int>[0x00a9, 0xfe0f]) == 2,
    'variation selector chooses emoji cluster width',
  );
  _expect(
    TerminalUnicode.clusterWidth(const <int>[0x1f1ef, 0x1f1f5]) == 2,
    'regional-indicator pair is one wide cluster',
  );
  _expect(
    TerminalUnicode.clusterWidth(const <int>[0x31, 0xfe0f, 0x20e3]) == 2,
    'keycap sequence is wide',
  );
  _expect(
    TerminalUnicode.clusterWidth(const <int>[0x0301]) == 0,
    'standalone extending cluster consumes no column',
  );
  _expectThrowsArgumentError(
    () => TerminalUnicode.clusterWidth(const <int>[]),
    'empty cluster rejected',
  );
  for (final int invalid in <int>[-1, 0xd800, 0xdfff, 0x110000]) {
    _expectThrowsArgumentError(
      () => TerminalUnicode.scalarWidth(invalid),
      'invalid scalar $invalid rejected',
    );
  }
}

void _testOfficialGraphemeConformance() {
  final File data = File('test/data/unicode/17.0.0/GraphemeBreakTest.txt');
  final TerminalGraphemeBreaker breaker = TerminalGraphemeBreaker();
  var cases = 0;
  var lineNumber = 0;
  for (final String originalLine in data.readAsLinesSync()) {
    lineNumber++;
    final String line = originalLine.split('#').first.trim();
    if (line.isEmpty) {
      continue;
    }
    final List<String> tokens = line.split(RegExp(r'\s+'));
    breaker.reset();
    for (var index = 1; index < tokens.length; index += 2) {
      final int scalar = int.parse(tokens[index], radix: 16);
      final bool expectedBoundary = tokens[index - 1] == '÷';
      final bool actualBoundary = breaker.addScalar(scalar);
      if (actualBoundary != expectedBoundary) {
        throw StateError(
          'GraphemeBreakTest line $lineNumber scalar '
          'U+${scalar.toRadixString(16).toUpperCase()} expected '
          '$expectedBoundary, got $actualBoundary',
        );
      }
    }
    cases++;
  }
  _expect(cases == 766, 'all 766 Unicode 17 grapheme cases pass');
}

void _testBreakerResetAndInvalidInput() {
  final TerminalGraphemeBreaker breaker = TerminalGraphemeBreaker();
  _expect(breaker.addScalar(0x61), 'first scalar starts a cluster');
  _expect(!breaker.addScalar(0x0301), 'combining mark extends cluster');
  _expectThrowsArgumentError(
    () => breaker.addScalar(0xd800),
    'breaker rejects surrogate',
  );
  _expect(
    breaker.addScalar(0x62),
    'invalid scalar leaves existing breaker state unchanged',
  );
  breaker.reset();
  _expect(breaker.addScalar(0x0301), 'reset restores first-scalar boundary');
}

void _testBoundedGraphemeTable() {
  final TerminalGraphemeTable table = TerminalGraphemeTable(
    capacity: 3,
    maximumScalarCount: 4,
    maximumClusterLength: 2,
  );
  _expect(
    table.definitionCount == 0 &&
        table.scalarCount == 0 &&
        table.generation == 1,
    'grapheme table starts empty with nonzero generation',
  );
  final List<int> source = <int>[0x61, 0x0301];
  final int first = table.intern(source);
  final int generation = table.generation;
  source[0] = 0x62;
  _expect(first == 1, 'first grapheme receives stable nonzero ID');
  _expect(
    _equals(table.scalarsAt(first), const <int>[0x61, 0x0301]),
    'interned sequence is isolated from caller mutation',
  );
  final Uint32List returned = table.scalarsAt(first);
  returned[0] = 0x63;
  _expect(
    table.scalarsAt(first).first == 0x61,
    'returned sequence cannot mutate stored definition',
  );
  _expect(
    table.intern(const <int>[0x61, 0x0301]) == first &&
        table.generation == generation,
    'equal sequence reuses ID without changing generation',
  );
  final int emoji = table.intern(const <int>[0x00a9, 0xfe0f]);
  _expect(emoji == 2 && table.widthAt(emoji) == 2, 'cluster width is stored');
  _expect(
    table.tryIntern(const <int>[0x64]) == null,
    'scalar storage limit is hard bounded',
  );
  _expect(
    table.definitionCount == 2 && table.scalarCount == 4,
    'resource exhaustion is atomic',
  );
  _expect(
    table.tryIntern(const <int>[0x00a9, 0xfe0f]) == emoji,
    'existing value remains available after exhaustion',
  );
  _expectThrowsStateError(
    () => table.intern(const <int>[0x64]),
    'throwing intern reports resource exhaustion',
  );
  _expectThrowsArgumentError(
    () => table.tryIntern(const <int>[0xd800]),
    'table rejects surrogate',
  );
  _expectThrowsArgumentError(
    () => table.tryIntern(const <int>[]),
    'table rejects empty sequence',
  );
  _expectThrowsArgumentError(
    () => table.tryIntern(const <int>[0x61, 0x62, 0x63]),
    'table rejects overlong cluster',
  );
  for (final void Function() construct in <void Function()>[
    () => TerminalGraphemeTable(capacity: 0),
    () => TerminalGraphemeTable(maximumScalarCount: 0),
    () => TerminalGraphemeTable(maximumScalarCount: 1, maximumClusterLength: 2),
  ]) {
    _expectThrowsArgumentError(construct, 'invalid table limit rejected');
  }
}

bool _equals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(description);
  }
}

void _expectThrowsArgumentError(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError(description);
}

void _expectThrowsStateError(void Function() operation, String description) {
  try {
    operation();
  } on StateError {
    return;
  }
  throw StateError(description);
}
