import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalCellGlyphTests();

void runTerminalCellGlyphTests() {
  _testExactScalarClassification();
  _testRequestBoundsAndFractionRounding();
  _testRasterOwnsExactAlphaCoverage();
  _testEveryBoxDrawingScalarIsBoundedAndDeterministic();
  _testBoxDrawingEdgeOwnershipAndJoins();
  _testBoxDrawingSpecialGeometry();
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

void _testEveryBoxDrawingScalarIsBoundedAndDeterministic() {
  for (final (int, int, int) geometry in <(int, int, int)>[
    (7, 15, 1),
    (14, 30, 2),
  ]) {
    for (int scalar = 0x2500; scalar <= 0x257f; scalar++) {
      final TerminalCellGlyphRasterRequest request =
          TerminalCellGlyphRasterRequest(
            scalar: scalar,
            cellWidth: geometry.$1,
            cellHeight: geometry.$2,
            lineThickness: geometry.$3,
          );
      final TerminalCellGlyphRaster first =
          TerminalCellGlyphRasterizer.rasterizeBoxDrawing(request);
      final TerminalCellGlyphRaster second =
          TerminalCellGlyphRasterizer.rasterizeBoxDrawing(request);
      final Uint8List firstBytes = first.copyCoverage();
      final int topology = _expectedBoxTopologies[scalar - 0x2500];
      final int expectedEdgeMask =
          (((topology >> 6) & 3) == 0 ? 0 : _up) |
          (((topology >> 4) & 3) == 0 ? 0 : _right) |
          (((topology >> 2) & 3) == 0 ? 0 : _down) |
          ((topology & 3) == 0 ? 0 : _left);
      final int actualEdgeMask =
          (_edgeHasInk(first, _up) ? _up : 0) |
          (_edgeHasInk(first, _right) ? _right : 0) |
          (_edgeHasInk(first, _down) ? _down : 0) |
          (_edgeHasInk(first, _left) ? _left : 0);
      _expect(
        first.width == geometry.$1 &&
            first.height == geometry.$2 &&
            first.rowStride == geometry.$1 &&
            first.byteLength == geometry.$1 * geometry.$2 &&
            firstBytes.any((int alpha) => alpha != 0) &&
            _bytesEqual(firstBytes, second.copyCoverage()),
        'Box Drawing U+${scalar.toRadixString(16)} is bounded and '
        'deterministic at ${geometry.$1}x${geometry.$2}',
      );
      if (topology != 0) {
        _expect(
          actualEdgeMask == expectedEdgeMask,
          'Box Drawing U+${scalar.toRadixString(16)} owns exactly its pinned '
          'direction edges (actual=$actualEdgeMask expected=$expectedEdgeMask)',
        );
      }
    }
  }

  _expectThrows(
    () => TerminalCellGlyphRasterizer.rasterizeBoxDrawing(
      TerminalCellGlyphRasterRequest(
        scalar: 0x2588,
        cellWidth: 7,
        cellHeight: 15,
        lineThickness: 1,
      ),
    ),
    'Box Drawing entry point rejects another classified family',
  );
}

void _testBoxDrawingEdgeOwnershipAndJoins() {
  const Map<int, int> expectedEdges = <int, int>{
    0x2500: _left | _right,
    0x2501: _left | _right,
    0x2502: _up | _down,
    0x2503: _up | _down,
    0x250c: _right | _down,
    0x2510: _left | _down,
    0x2514: _up | _right,
    0x2518: _up | _left,
    0x251c: _up | _right | _down,
    0x2524: _up | _down | _left,
    0x252c: _right | _down | _left,
    0x2534: _up | _right | _left,
    0x253c: _up | _right | _down | _left,
    0x2550: _left | _right,
    0x2551: _up | _down,
    0x2554: _right | _down,
    0x2557: _left | _down,
    0x255a: _up | _right,
    0x255d: _up | _left,
    0x2560: _up | _right | _down,
    0x2563: _up | _down | _left,
    0x2566: _right | _down | _left,
    0x2569: _up | _right | _left,
    0x256c: _up | _right | _down | _left,
    0x256d: _right | _down,
    0x256e: _left | _down,
    0x256f: _up | _left,
    0x2570: _up | _right,
    0x2571: _up | _right | _down | _left,
    0x2572: _up | _right | _down | _left,
    0x2573: _up | _right | _down | _left,
    0x2574: _left,
    0x2575: _up,
    0x2576: _right,
    0x2577: _down,
    0x2578: _left,
    0x2579: _up,
    0x257a: _right,
    0x257b: _down,
    0x257c: _left | _right,
    0x257d: _up | _down,
    0x257e: _left | _right,
    0x257f: _up | _down,
  };
  for (final MapEntry<int, int> entry in expectedEdges.entries) {
    final TerminalCellGlyphRaster raster = _boxRaster(entry.key);
    final int actual =
        (_edgeHasInk(raster, _up) ? _up : 0) |
        (_edgeHasInk(raster, _right) ? _right : 0) |
        (_edgeHasInk(raster, _down) ? _down : 0) |
        (_edgeHasInk(raster, _left) ? _left : 0);
    _expect(
      actual & entry.value == entry.value,
      'Box Drawing U+${entry.key.toRadixString(16)} owns every declared edge '
      '(actual=$actual expected=${entry.value})',
    );
  }

  for (final int scalar in <int>[0x2500, 0x2501, 0x2550]) {
    final TerminalCellGlyphRaster raster = _boxRaster(scalar);
    _expect(
      _bytesEqual(_edge(raster, _left), _edge(raster, _right)),
      'horizontal U+${scalar.toRadixString(16)} has matching shared edges',
    );
  }
  for (final int scalar in <int>[0x2502, 0x2503, 0x2551]) {
    final TerminalCellGlyphRaster raster = _boxRaster(scalar);
    _expect(
      _bytesEqual(_edge(raster, _up), _edge(raster, _down)),
      'vertical U+${scalar.toRadixString(16)} has matching shared edges',
    );
  }
}

void _testBoxDrawingSpecialGeometry() {
  final TerminalCellGlyphRaster light = _boxRaster(0x2500);
  final TerminalCellGlyphRaster heavy = _boxRaster(0x2501);
  final TerminalCellGlyphRaster double = _boxRaster(0x2550);
  _expect(
    _inkCount(heavy) == _inkCount(light) * 2,
    'heavy horizontal line is exactly twice the light thickness',
  );
  final int centerX = double.width ~/ 2;
  _expect(
    double.coverageAt(centerX, double.height ~/ 2) == 0 &&
        _edge(double, _left).where((int alpha) => alpha != 0).length == 2,
    'double horizontal line preserves its one-line center gap',
  );

  for (final int scalar in <int>[
    0x2504,
    0x2505,
    0x2506,
    0x2507,
    0x2508,
    0x2509,
    0x250a,
    0x250b,
    0x254c,
    0x254d,
    0x254e,
    0x254f,
  ]) {
    final TerminalCellGlyphRaster raster = _boxRaster(
      scalar,
      width: 16,
      height: 32,
      thickness: 2,
    );
    _expect(
      raster.copyCoverage().contains(0) && _inkCount(raster) > 0,
      'dashed U+${scalar.toRadixString(16)} contains bounded gaps and ink',
    );
  }

  for (final int scalar in <int>[0x256d, 0x256e, 0x256f, 0x2570]) {
    final TerminalCellGlyphRaster raster = _boxRaster(scalar);
    final int cornerCount = <int>[
      raster.coverageAt(0, 0),
      raster.coverageAt(raster.width - 1, 0),
      raster.coverageAt(0, raster.height - 1),
      raster.coverageAt(raster.width - 1, raster.height - 1),
    ].where((int alpha) => alpha != 0).length;
    _expect(
      cornerCount == 0,
      'curved U+${scalar.toRadixString(16)} does not collapse into a square '
      'corner',
    );
  }
  final TerminalCellGlyphRaster horizontal = _boxRaster(0x2500);
  final TerminalCellGlyphRaster vertical = _boxRaster(0x2502);
  final Map<int, (int, int)> arcJoins = <int, (int, int)>{
    0x256d: (_down, _right),
    0x256e: (_down, _left),
    0x256f: (_up, _left),
    0x2570: (_up, _right),
  };
  for (final MapEntry<int, (int, int)> entry in arcJoins.entries) {
    final TerminalCellGlyphRaster arc = _boxRaster(entry.key);
    _expect(
      _inkMaskContains(
            _edge(arc, entry.value.$1),
            _edge(vertical, entry.value.$1),
          ) &&
          _inkMaskContains(
            _edge(arc, entry.value.$2),
            _edge(horizontal, entry.value.$2),
          ),
      'curved U+${entry.key.toRadixString(16)} joins straight light edges '
      'without a boundary mismatch '
      '(vertical=${_inkMask(_edge(arc, entry.value.$1))}/'
      '${_inkMask(_edge(vertical, entry.value.$1))} '
      'horizontal=${_inkMask(_edge(arc, entry.value.$2))}/'
      '${_inkMask(_edge(horizontal, entry.value.$2))})',
    );
  }
  for (final int scalar in <int>[0x2571, 0x2572, 0x2573]) {
    final TerminalCellGlyphRaster raster = _boxRaster(scalar);
    _expect(
      _edgeHasInk(raster, _up) &&
          _edgeHasInk(raster, _right) &&
          _edgeHasInk(raster, _down) &&
          _edgeHasInk(raster, _left),
      'diagonal U+${scalar.toRadixString(16)} reaches its cell corners',
    );
  }
}

const int _up = 1;
const int _right = 2;
const int _down = 4;
const int _left = 8;

// Independent pinned expectation, encoded as two-bit up/right/down/left
// styles. Zero entries are the separately tested dashed/arc/diagonal glyphs.
const List<int> _expectedBoxTopologies = <int>[
  0x11,
  0x22,
  0x44,
  0x88,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x14,
  0x24,
  0x18,
  0x28,
  0x05,
  0x06,
  0x09,
  0x0a,
  0x50,
  0x60,
  0x90,
  0xa0,
  0x41,
  0x42,
  0x81,
  0x82,
  0x54,
  0x64,
  0x94,
  0x58,
  0x98,
  0xa4,
  0x68,
  0xa8,
  0x45,
  0x46,
  0x85,
  0x49,
  0x89,
  0x86,
  0x4a,
  0x8a,
  0x15,
  0x16,
  0x25,
  0x26,
  0x19,
  0x1a,
  0x29,
  0x2a,
  0x51,
  0x52,
  0x61,
  0x62,
  0x91,
  0x92,
  0xa1,
  0xa2,
  0x55,
  0x56,
  0x65,
  0x66,
  0x95,
  0x59,
  0x99,
  0x96,
  0xa5,
  0x5a,
  0x69,
  0xa6,
  0x6a,
  0x9a,
  0xa9,
  0xaa,
  0x00,
  0x00,
  0x00,
  0x00,
  0x33,
  0xcc,
  0x34,
  0x1c,
  0x3c,
  0x07,
  0x0d,
  0x0f,
  0x70,
  0xd0,
  0xf0,
  0x43,
  0xc1,
  0xc3,
  0x74,
  0xdc,
  0xfc,
  0x47,
  0xcd,
  0xcf,
  0x37,
  0x1d,
  0x3f,
  0x73,
  0xd1,
  0xf3,
  0x77,
  0xdd,
  0xff,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x40,
  0x10,
  0x04,
  0x02,
  0x80,
  0x20,
  0x08,
  0x21,
  0x48,
  0x12,
  0x84,
];

TerminalCellGlyphRaster _boxRaster(
  int scalar, {
  int width = 7,
  int height = 15,
  int thickness = 1,
}) => TerminalCellGlyphRasterizer.rasterizeBoxDrawing(
  TerminalCellGlyphRasterRequest(
    scalar: scalar,
    cellWidth: width,
    cellHeight: height,
    lineThickness: thickness,
  ),
);

bool _edgeHasInk(TerminalCellGlyphRaster raster, int side) =>
    _edge(raster, side).any((int alpha) => alpha != 0);

Uint8List _edge(TerminalCellGlyphRaster raster, int side) {
  switch (side) {
    case _up:
      return Uint8List.fromList(<int>[
        for (int x = 0; x < raster.width; x++) raster.coverageAt(x, 0),
      ]);
    case _right:
      return Uint8List.fromList(<int>[
        for (int y = 0; y < raster.height; y++)
          raster.coverageAt(raster.width - 1, y),
      ]);
    case _down:
      return Uint8List.fromList(<int>[
        for (int x = 0; x < raster.width; x++)
          raster.coverageAt(x, raster.height - 1),
      ]);
    case _left:
      return Uint8List.fromList(<int>[
        for (int y = 0; y < raster.height; y++) raster.coverageAt(0, y),
      ]);
  }
  throw ArgumentError.value(side, 'side');
}

int _inkCount(TerminalCellGlyphRaster raster) =>
    raster.copyCoverage().where((int alpha) => alpha != 0).length;

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Uint8List _inkMask(Uint8List coverage) => Uint8List.fromList(<int>[
  for (final int alpha in coverage) alpha == 0 ? 0 : 1,
]);

bool _inkMaskContains(Uint8List actual, Uint8List required) {
  if (actual.length != required.length) return false;
  for (int index = 0; index < actual.length; index++) {
    if (required[index] != 0 && actual[index] == 0) return false;
  }
  return true;
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
