import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'support/kitty_reference_golden_fixture.dart';

void main() => runTerminalKittyReferenceCompositorTests();

void runTerminalKittyReferenceCompositorTests() {
  _testLayeringSamplingClippingAndGolden();
  _testMissingGeometryFailsClosed();
}

void _testLayeringSamplingClippingAndGolden() {
  for (final int scale in <int>[1, 2]) {
    final TerminalReferenceImage rendered = createKittyReferenceGoldenFixture(
      scale: scale,
    );
    _expect(
      rendered.pixelAt(0, 0) == 0x0000ffff &&
          rendered.pixelAt(scale, 0) == 0xffffffff,
      'negative viewport y clips the first source row at ${scale}x',
    );
    _expect(
      rendered.pixelAt(scale, scale) == 0xffffffff &&
          rendered.pixelAt(2 * scale, scale) == 0x00ff00ff,
      'below-text scaling is covered by glyphs but not blank cells at ${scale}x',
    );
    _expect(
      rendered.pixelAt(scale, 2 * scale) == 0xffff00ff &&
          rendered.pixelAt(0, 2 * scale) == 0x00ffffff,
      'nonnegative image z covers glyphs while cursor remains above at ${scale}x',
    );
    final File fixture = File(
      'test/goldens/kitty/static-placement-${scale}x.dtgi',
    );
    _expect(fixture.existsSync(), 'checked-in ${scale}x Kitty golden exists');
    final Uint8List expectedBytes = fixture.readAsBytesSync();
    final Uint8List actualBytes = TerminalGoldenImageCodec.encode(rendered);
    _expect(
      _bytesEqual(expectedBytes, actualBytes),
      'checked-in ${scale}x Kitty golden is byte exact',
    );
    TerminalGoldenImageComparator.compare(
      TerminalGoldenImageCodec.decode(expectedBytes),
      rendered,
    ).requireMatch('Kitty static placement ${scale}x golden');
  }
}

void _testMissingGeometryFailsClosed() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 1);
  _expectThrows(
    () => TerminalKittyReferenceCompositor.render(
      snapshot: screens.captureKittyImageViewport(),
    ),
    'a viewport without logical cell metrics is not guessed',
  );
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Kitty reference compositor failed: $description');
  }
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('Kitty reference compositor failed: $description');
}
