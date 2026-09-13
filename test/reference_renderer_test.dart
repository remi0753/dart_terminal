import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runReferenceRendererTests();

void runReferenceRendererTests() {
  _testLayerAndSameLayerOrder();
  _testMaskAndBitmapBlending();
  _testSharedSampledBitmapScaling();
  _testClippingAndScale();
  _testTransparentSourceOver();
  _testTaggedColorAndBitmapCanonicalization();
  _testInputAndOutputOwnership();
  _testBoundsAndValidation();
}

void _testTaggedColorAndBitmapCanonicalization() {
  _expect(
    TerminalReferenceColor.fromRenderColor(
          const TerminalRenderColor.displayP3(0xff80005a),
        ).rgba ==
        0xff77005a,
    'tagged reference color converts to canonical sRGB exactly once',
  );
  final Uint8List bitmapBytes = Uint8List.fromList(const <int>[
    0xff,
    0x80,
    0x00,
    0xff,
  ]);
  final Uint8List sampledBytes = Uint8List.fromList(const <int>[
    0xff,
    0x80,
    0x00,
    0xff,
    0x5a,
  ]);
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 2,
    height: 1,
    primitives: <TerminalReferencePrimitive>[
      TerminalReferenceBitmap(
        layer: TerminalReferenceLayer.glyph,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        rowStride: 4,
        rgba: bitmapBytes,
        inputColorSpace: TerminalRenderColorSpace.displayP3,
      ),
      TerminalReferenceSampledBitmap(
        layer: TerminalReferenceLayer.glyph,
        x: 1,
        y: 0,
        width: 1,
        height: 1,
        source: TerminalReferenceBitmapSource(
          width: 1,
          height: 1,
          rowStride: 5,
          rgba: sampledBytes,
          inputColorSpace: TerminalRenderColorSpace.displayP3,
        ),
        sourceX: 0,
        sourceY: 0,
        sourceWidth: 1,
        sourceHeight: 1,
      ),
    ],
  );
  bitmapBytes.fillRange(0, bitmapBytes.length, 0);
  sampledBytes.fillRange(0, sampledBytes.length, 0);
  _expect(
    image.pixelAt(0, 0) == 0xff7700ff && image.pixelAt(1, 0) == 0xff7700ff,
    'tagged P3 bitmap forms convert pixels, preserve padding, and own bytes',
  );
}

void _testSharedSampledBitmapScaling() {
  final TerminalReferenceBitmapSource source = TerminalReferenceBitmapSource(
    width: 2,
    height: 1,
    rowStride: 8,
    rgba: const <int>[255, 0, 0, 255, 0, 0, 255, 255],
  );
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 5,
    height: 1,
    primitives: <TerminalReferencePrimitive>[
      TerminalReferenceSampledBitmap(
        layer: TerminalReferenceLayer.imageBelowText,
        x: 0,
        y: 0,
        width: 4,
        height: 1,
        source: source,
        sourceX: 0,
        sourceY: 0,
        sourceWidth: 2,
        sourceHeight: 1,
      ),
      TerminalReferenceSampledBitmap(
        layer: TerminalReferenceLayer.imageAboveText,
        x: 4,
        y: 0,
        width: 1,
        height: 1,
        source: source,
        sourceX: 1,
        sourceY: 0,
        sourceWidth: 1,
        sourceHeight: 1,
      ),
    ],
    limits: const TerminalReferenceRenderLimits(maximumSourceBytes: 8),
  );
  _expect(
    image.pixelAt(0, 0) == 0xff0000ff &&
        image.pixelAt(1, 0) == 0xff0000ff &&
        image.pixelAt(2, 0) == 0x0000ffff &&
        image.pixelAt(3, 0) == 0x0000ffff &&
        image.pixelAt(4, 0) == 0x0000ffff,
    'nearest-neighbor sampling scales and crops deterministically',
  );
  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 1,
      height: 1,
      primitives: <TerminalReferencePrimitive>[
        TerminalReferenceSampledBitmap(
          layer: TerminalReferenceLayer.imageAboveText,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          source: source,
          sourceX: 0,
          sourceY: 0,
          sourceWidth: 1,
          sourceHeight: 1,
        ),
      ],
      limits: const TerminalReferenceRenderLimits(maximumSourceBytes: 7),
    ),
    'a shared sampled source is still charged once against the byte limit',
  );
}

void _testLayerAndSameLayerOrder() {
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 2,
    height: 1,
    background: const TerminalReferenceColor(0x000000ff),
    primitives: <TerminalReferencePrimitive>[
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.cursor,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xffff00ff),
      ),
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.glyph,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0x00ff00ff),
      ),
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.cellBackground,
        x: 0,
        y: 0,
        width: 2,
        height: 1,
        color: TerminalReferenceColor(0xff0000ff),
      ),
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.decoration,
        x: 1,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0x0000ffff),
      ),
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.decoration,
        x: 1,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xff00ffff),
      ),
    ],
  );
  _expect(
    image.pixelAt(0, 0) == 0xffff00ff,
    'cursor layer wins independent of caller list order',
  );
  _expect(
    image.pixelAt(1, 0) == 0xff00ffff,
    'caller order is stable within one layer',
  );
}

void _testMaskAndBitmapBlending() {
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 2,
    height: 1,
    background: const TerminalReferenceColor(0x000000ff),
    primitives: <TerminalReferencePrimitive>[
      TerminalReferenceMask(
        layer: TerminalReferenceLayer.glyph,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        rowStride: 1,
        coverage: const <int>[128],
        color: const TerminalReferenceColor(0xffffffff),
      ),
      TerminalReferenceBitmap(
        layer: TerminalReferenceLayer.glyph,
        x: 1,
        y: 0,
        width: 1,
        height: 1,
        rowStride: 4,
        rgba: const <int>[10, 20, 30, 128],
      ),
    ],
  );
  _expect(
    image.pixelAt(0, 0) == 0xbcbcbcff,
    'coverage blends in linear light before canonical sRGB encoding',
  );
  _expect(
    image.pixelAt(1, 0) == 0x050c13ff,
    'color bitmap uses linear-light straight-alpha source-over blending',
  );
}

void _testClippingAndScale() {
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 2,
    height: 2,
    scale: 2,
    background: const TerminalReferenceColor(0x010203ff),
    primitives: <TerminalReferencePrimitive>[
      const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.selection,
        x: -1,
        y: 0,
        width: 2,
        height: 1,
        color: TerminalReferenceColor(0xaabbccff),
      ),
      TerminalReferenceMask(
        layer: TerminalReferenceLayer.glyph,
        x: 1,
        y: 1,
        width: 2,
        height: 1,
        rowStride: 2,
        coverage: const <int>[255, 0],
        color: const TerminalReferenceColor(0xffffffff),
      ),
    ],
  );
  _expect(
    image.width == 4 &&
        image.height == 4 &&
        image.scale == 2 &&
        image.logicalWidth == 2 &&
        image.logicalHeight == 2 &&
        image.rowStride == 16,
    '2x surface dimensions and metadata',
  );
  for (final (int x, int y) in <(int, int)>[(0, 0), (1, 0), (0, 1), (1, 1)]) {
    _expect(
      image.pixelAt(x, y) == 0xaabbccff,
      'negative rectangle clips then expands at $x,$y',
    );
  }
  for (final (int x, int y) in <(int, int)>[(2, 2), (3, 2), (2, 3), (3, 3)]) {
    _expect(
      image.pixelAt(x, y) == 0xffffffff,
      'mask source pixel expands at $x,$y',
    );
  }
  _expect(
    image.pixelAt(2, 0) == 0x010203ff && image.pixelAt(0, 2) == 0x010203ff,
    'uncovered pixels retain the base background',
  );
}

void _testTransparentSourceOver() {
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 1,
    height: 1,
    background: const TerminalReferenceColor(0x0000ff80),
    primitives: const <TerminalReferencePrimitive>[
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.glyph,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xff000080),
      ),
    ],
  );
  _expect(
    image.pixelAt(0, 0) == 0xd5009cc0,
    'linear-light straight-alpha output remains deterministic over transparency',
  );
}

void _testInputAndOutputOwnership() {
  final Uint8List maskBytes = Uint8List.fromList(<int>[255]);
  final TerminalReferenceMask mask = TerminalReferenceMask(
    layer: TerminalReferenceLayer.glyph,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    rowStride: 1,
    coverage: maskBytes,
    color: const TerminalReferenceColor(0xffffffff),
  );
  maskBytes[0] = 0;
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 1,
    height: 1,
    primitives: <TerminalReferencePrimitive>[mask],
  );
  final Uint8List copy = image.copyRgbaBytes();
  copy.fillRange(0, copy.length, 0);
  _expect(
    image.pixelAt(0, 0) == 0xffffffff,
    'primitive and output bytes are independently owned',
  );

  final Uint8List constructorBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
  final TerminalReferenceImage constructed = TerminalReferenceImage.fromRgba(
    width: 1,
    height: 1,
    scale: 1,
    rgba: constructorBytes,
  );
  constructorBytes[0] = 9;
  _expect(
    constructed.pixelAt(0, 0) == 0x01020304,
    'image constructor copies caller bytes',
  );
}

void _testBoundsAndValidation() {
  _expectThrows(
    () => TerminalReferenceRenderer.render(width: 0, height: 1),
    'zero width is rejected',
  );
  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 1,
      height: 1,
      background: TerminalReferenceColor(-1),
    ),
    'out-of-range packed colors are rejected in release mode',
  );
  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 2,
      height: 2,
      scale: 2,
      limits: const TerminalReferenceRenderLimits(maximumPixelCount: 15),
    ),
    'scaled pixel limit is enforced before allocation',
  );
  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 1,
      height: 1,
      primitives: const <TerminalReferencePrimitive>[
        TerminalReferenceSolid(
          layer: TerminalReferenceLayer.glyph,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          color: TerminalReferenceColor(0xffffffff),
        ),
      ],
      limits: const TerminalReferenceRenderLimits(maximumPrimitiveCount: 0),
    ),
    'primitive count is bounded',
  );
  var primitiveYields = 0;
  Iterable<TerminalReferencePrimitive> excessivePrimitives() sync* {
    while (true) {
      primitiveYields++;
      yield const TerminalReferenceSolid(
        layer: TerminalReferenceLayer.glyph,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xffffffff),
      );
    }
  }

  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 1,
      height: 1,
      primitives: excessivePrimitives(),
      limits: const TerminalReferenceRenderLimits(maximumPrimitiveCount: 2),
    ),
    'unbounded primitive iterables are stopped at the configured limit',
  );
  _expect(
    primitiveYields == 3,
    'primitive admission does not materialize past the first excess item',
  );
  _expectThrows(
    () => TerminalReferenceRenderer.render(
      width: 1,
      height: 1,
      primitives: <TerminalReferencePrimitive>[
        TerminalReferenceMask(
          layer: TerminalReferenceLayer.glyph,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          rowStride: 1,
          coverage: const <int>[255],
          color: const TerminalReferenceColor(0xffffffff),
        ),
      ],
      limits: const TerminalReferenceRenderLimits(maximumSourceBytes: 0),
    ),
    'source bytes are bounded',
  );
  _expectThrows(
    () => TerminalReferenceMask(
      layer: TerminalReferenceLayer.glyph,
      x: 0,
      y: 0,
      width: 2,
      height: 1,
      rowStride: 1,
      coverage: const <int>[255],
      color: const TerminalReferenceColor(0xffffffff),
    ),
    'mask stride cannot be shorter than its row',
  );
  _expectThrows(
    () => TerminalReferenceMask(
      layer: TerminalReferenceLayer.glyph,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      rowStride: 1,
      coverage: const <int>[256],
      color: const TerminalReferenceColor(0xffffffff),
    ),
    'mask bytes are validated rather than truncated',
  );
  _expectThrows(
    () => TerminalReferenceBitmap(
      layer: TerminalReferenceLayer.glyph,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      rowStride: 4,
      rgba: const <int>[1, 2, 3],
    ),
    'bitmap byte length must be exact',
  );
  _expectThrows(
    () => TerminalReferenceImage.fromRgba(
      width: 3,
      height: 2,
      scale: 2,
      rgba: Uint8List(24),
    ),
    'image dimensions must be divisible by scale',
  );
  _expectThrows(
    () => TerminalReferenceImage.fromRgba(
      width: 4,
      height: 4,
      scale: 4,
      rgba: Uint8List(64),
      limits: const TerminalReferenceRenderLimits(maximumScale: 2),
    ),
    'decoded image scale obeys configured limits',
  );
  final TerminalReferenceImage image = TerminalReferenceRenderer.render(
    width: 1,
    height: 1,
  );
  _expectThrows(() => image.pixelAt(1, 0), 'pixel access is bounds checked');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('reference renderer expectation failed: $description');
  }
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('reference renderer expectation failed: $description');
}
