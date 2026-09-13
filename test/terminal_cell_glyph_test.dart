import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalCellGlyphTests();

void runTerminalCellGlyphTests() {
  _testExactScalarClassification();
  _testRequestBoundsAndFractionRounding();
  _testRasterOwnsExactAlphaCoverage();
}

void _testExactScalarClassification() {
  final Map<TerminalCellGlyphFamily, int> counts =
      <TerminalCellGlyphFamily, int>{
        for (final TerminalCellGlyphFamily family
            in TerminalCellGlyphFamily.values)
          family: 0,
      };
  var total = 0;
  for (int scalar = 0; scalar <= 0x10ffff; scalar++) {
    final TerminalCellGlyphSpec? spec = TerminalCellGlyphClassifier.classify(
      scalar,
    );
    if (spec == null) continue;
    _expect(spec.scalar == scalar, 'classification retains its scalar');
    counts[spec.family] = counts[spec.family]! + 1;
    total++;
  }
  _expect(
    total == TerminalCellGlyphClassifier.acceptedScalarCount &&
        counts[TerminalCellGlyphFamily.boxDrawing] == 128 &&
        counts[TerminalCellGlyphFamily.blockElement] == 32 &&
        counts[TerminalCellGlyphFamily.braille] == 256 &&
        counts[TerminalCellGlyphFamily.powerline] == 18,
    'classifier owns exactly the reviewed 434-scalar surface',
  );

  for (final int scalar in <int>[
    -1,
    0x24ff,
    0x25a0,
    0x27ff,
    0x2900,
    0xe0af,
    0xe0c0,
    0xe0d1,
    0xe0d3,
    0xe0d5,
    0x110000,
  ]) {
    _expect(
      !TerminalCellGlyphClassifier.supports(scalar),
      'adjacent unsupported scalar U+${scalar.toRadixString(16)} remains '
      'font-owned',
    );
  }
}

void _testRequestBoundsAndFractionRounding() {
  final TerminalCellGlyphRasterRequest odd = TerminalCellGlyphRasterRequest(
    scalar: 0x2588,
    cellWidth: 7,
    cellHeight: 15,
    lineThickness: 1,
  );
  _expect(
    odd.spec.family == TerminalCellGlyphFamily.blockElement &&
        odd.byteLength == 105 &&
        odd.fractionMin(1, 2, extent: 7) == 3 &&
        odd.fractionMax(1, 2, extent: 7) == 4 &&
        odd.fractionMin(1, 2, extent: 8) == 4 &&
        odd.fractionMax(1, 2, extent: 8) == 4 &&
        odd.fractionMax(1, 8, extent: 7) == 1 &&
        odd.fractionMin(7, 8, extent: 7) == 6,
    'device fractions use deterministic complementary half-up rounding',
  );

  _expectThrows(
    () => TerminalCellGlyphRasterRequest(
      scalar: 0xe0c0,
      cellWidth: 8,
      cellHeight: 16,
      lineThickness: 1,
    ),
    'unsupported Powerline scalar fails closed',
  );
  _expectThrows(
    () => TerminalCellGlyphRasterRequest(
      scalar: 0x2500,
      cellWidth: 0,
      cellHeight: 16,
      lineThickness: 1,
    ),
    'zero-width raster fails closed',
  );
  _expectThrows(
    () => TerminalCellGlyphRasterRequest(
      scalar: 0x2500,
      cellWidth: 8,
      cellHeight: 16,
      lineThickness: 9,
    ),
    'line thickness larger than the cell fails closed',
  );
  _expectThrows(
    () => odd.fractionMax(9, 8, extent: 7),
    'out-of-range fraction fails closed',
  );
}

void _testRasterOwnsExactAlphaCoverage() {
  final TerminalCellGlyphRasterRequest request = TerminalCellGlyphRasterRequest(
    scalar: 0x2801,
    cellWidth: 2,
    cellHeight: 4,
    lineThickness: 1,
  );
  final Uint8List input = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
  final TerminalCellGlyphRaster raster = TerminalCellGlyphRaster(
    request: request,
    coverage: input,
  );
  input[0] = 99;
  final Uint8List firstCopy = raster.copyCoverage();
  firstCopy[7] = 99;
  _expect(
    raster.width == 2 &&
        raster.height == 4 &&
        raster.rowStride == 2 &&
        raster.byteLength == 8 &&
        raster.coverageAt(0, 0) == 1 &&
        raster.coverageAt(1, 3) == 8,
    'raster owns exact tightly packed alpha bytes',
  );
  _expectThrows(
    () => TerminalCellGlyphRaster(request: request, coverage: Uint8List(7)),
    'incorrect alpha byte length fails closed',
  );
  _expectThrows(
    () => raster.coverageAt(2, 0),
    'out-of-range coverage lookup fails closed',
  );
}

void _expectThrows(void Function() body, String message) {
  try {
    body();
  } on Object {
    return;
  }
  throw StateError(message);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
