import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void runRasterTests() {
  _testPackedRasterDecoder();
  _testLiveRasterization();
  _testLiveRasterScaleParity();
  _testLiveRasterOrientation();
  _testRasterValidationAndGeneration();
}

void _testPackedRasterDecoder() {
  const TerminalGlyphRasterRequest request = TerminalGlyphRasterRequest(
    faceId: 1,
    glyphId: 2,
  );
  final Uint8List alpha = _minimalRasterBuffer(color: false);
  final TerminalGlyphRasterBatch decoded = TerminalRasterBufferV1.decode(
    alpha,
    requests: const <TerminalGlyphRasterRequest>[request],
    catalogGeneration: 99,
    scale16_16: 1 << 16,
  );
  _expect(
    decoded.catalogGeneration == 99 &&
        decoded.scale == 1 &&
        decoded.pixelByteLength == 1 &&
        decoded.glyphs.length == 1 &&
        decoded.glyphs.single.format == TerminalGlyphPixelFormat.alpha8 &&
        decoded.glyphs.single.originX == -1 &&
        decoded.glyphs.single.originY == 2 &&
        decoded.glyphs.single.copyPixels().single == 255,
    'strict decoder accepts one canonical alpha raster',
  );
  _expectThrows<UnsupportedError>(
    () => decoded.glyphs.add(decoded.glyphs.single),
    'decoded raster list is immutable',
  );
  final Uint8List copied = decoded.glyphs.single.copyPixels();
  copied[0] = 0;
  _expect(
    decoded.glyphs.single.copyPixels().single == 255,
    'raster pixel accessor returns an ownership copy',
  );

  final Uint8List color = _minimalRasterBuffer(color: true);
  final TerminalGlyphRasterBatch decodedColor = TerminalRasterBufferV1.decode(
    color,
    requests: const <TerminalGlyphRasterRequest>[request],
    catalogGeneration: 99,
    scale16_16: 1 << 16,
  );
  _expect(
    decodedColor.pixelByteLength == 4 &&
        decodedColor.glyphs.single.isColor &&
        decodedColor.glyphs.single.format ==
            TerminalGlyphPixelFormat.rgba8Straight,
    'strict decoder accepts straight RGBA raster pixels',
  );

  _expectDecodeFailure(_withU32(alpha, 0, 0), 'magic');
  _expectDecodeFailure(_withU32(alpha, 44, 1), 'header reserved');
  _expectDecodeFailure(_withU32(alpha, 36, 111), 'pixel section');
  _expectDecodeFailure(_withU32(alpha, 64, 2), 'face identity');
  _expectDecodeFailure(_withU32(alpha, 72, 3), 'pixel format');
  _expectDecodeFailure(_withU32(alpha, 76, 1), 'color flag mismatch');
  _expectDecodeFailure(_withU32(alpha, 88, 2), 'width/stride mismatch');
  _expectDecodeFailure(_withU32(alpha, 100, 111), 'pixel gap');
  _expectDecodeFailure(_withU32(alpha, 108, 1), 'record reserved');
  final Uint8List transparentColor = Uint8List.fromList(color);
  transparentColor.setAll(112, <int>[1, 2, 3, 0]);
  _expectDecodeFailure(transparentColor, 'transparent straight RGB');
  _expectThrows<FormatException>(
    () => TerminalRasterBufferV1.decode(
      Uint8List.sublistView(alpha, 0, alpha.length - 1),
      requests: const <TerminalGlyphRasterRequest>[request],
      catalogGeneration: 99,
      scale16_16: 1 << 16,
    ),
    'truncated raster buffer',
  );
}

void _testLiveRasterization() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  try {
    final TerminalShapedText shaped = catalog.shape('A日本語👩🏽‍💻e\u0301');
    final TerminalGlyphRasterBatch one = catalog.rasterizeShaped(shaped);
    final TerminalGlyphRasterBatch two = catalog.rasterizeShaped(
      shaped,
      scale: 2,
    );
    _expect(
      one.catalogGeneration == catalog.generation &&
          one.scale16_16 == 1 << 16 &&
          one.glyphs.isNotEmpty &&
          one.glyphs.length <= shaped.glyphs.length &&
          one.glyphs.any(
            (TerminalRasterizedGlyph glyph) =>
                glyph.format == TerminalGlyphPixelFormat.alpha8,
          ) &&
          one.glyphs.any(
            (TerminalRasterizedGlyph glyph) =>
                glyph.format == TerminalGlyphPixelFormat.rgba8Straight &&
                glyph.isColor,
          ) &&
          one.pixelByteLength > 0 &&
          two.scale16_16 == 2 << 16 &&
          two.pixelByteLength > one.pixelByteLength,
      'mixed shaped glyph set rasterizes as alpha/color at 1x and 2x',
    );
    for (final TerminalRasterizedGlyph glyph in one.glyphs) {
      _expect(
        glyph.width >= 0 &&
            glyph.height >= 0 &&
            glyph.width <= TerminalRasterBufferV1.maximumDimension &&
            glyph.height <= TerminalRasterBufferV1.maximumDimension &&
            glyph.rowStride ==
                glyph.width *
                    (glyph.format == TerminalGlyphPixelFormat.alpha8 ? 1 : 4) &&
            glyph.byteLength == glyph.rowStride * glyph.height,
        'live raster has tight bounded device-pixel geometry',
      );
      if (!glyph.isEmpty) {
        final Uint8List pixels = glyph.copyPixels();
        final int channel = glyph.format == TerminalGlyphPixelFormat.alpha8
            ? 0
            : 3;
        final int step = glyph.format == TerminalGlyphPixelFormat.alpha8
            ? 1
            : 4;
        var hasCoverage = false;
        for (int offset = channel; offset < pixels.length; offset += step) {
          hasCoverage |= pixels[offset] != 0;
        }
        _expect(hasCoverage, 'visible live raster has nonzero coverage');
      }
    }
    final TerminalShapedText whitespace = catalog.shape(' ');
    final TerminalRasterizedGlyph empty = catalog
        .rasterizeShaped(whitespace)
        .glyphs
        .single;
    _expect(
      empty.isEmpty &&
          empty.width == 0 &&
          empty.height == 0 &&
          empty.rowStride == 0 &&
          empty.byteLength == 0,
      'whitespace is a valid zero-area raster entry',
    );
    final TerminalRasterizedGlyph missing = catalog
        .rasterize(<TerminalGlyphRasterRequest>[
          TerminalGlyphRasterRequest(
            faceId: catalog.faceIdForStyle(TerminalFontStyle.regular),
            glyphId: 0,
          ),
        ])
        .glyphs
        .single;
    _expect(
      missing.isMissing &&
          !missing.isColor &&
          missing.format == TerminalGlyphPixelFormat.alpha8,
      'glyph zero is explicitly marked as the missing-glyph raster',
    );
  } finally {
    catalog.dispose();
  }

  final TerminalFontCatalog ligatureCatalog = TerminalFontCatalog.open(
    family: 'Times-Roman',
  );
  try {
    final TerminalShapedText ligatures = ligatureCatalog.shape('office ffi');
    final TerminalShapedGlyph ligature = ligatures.glyphs.firstWhere(
      (TerminalShapedGlyph glyph) => glyph.utf16Length > 1,
    );
    final TerminalRasterizedGlyph raster = ligatureCatalog
        .rasterize(<TerminalGlyphRasterRequest>[
          TerminalGlyphRasterRequest(
            faceId: ligature.faceId,
            glyphId: ligature.glyphId,
          ),
        ])
        .glyphs
        .single;
    _expect(
      raster.format == TerminalGlyphPixelFormat.alpha8 && !raster.isEmpty,
      'ligature glyph rasterizes as a monochrome mask',
    );
  } finally {
    ligatureCatalog.dispose();
  }
}

void _testLiveRasterOrientation() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  try {
    final TerminalRasterizedGlyph glyph = catalog
        .rasterizeShaped(catalog.shape('L'), scale: 2)
        .glyphs
        .single;
    final Uint8List pixels = glyph.copyPixels();
    final int bandHeight = glyph.height ~/ 3;
    var topCoverage = 0;
    var bottomCoverage = 0;
    for (int y = 0; y < bandHeight; y++) {
      final int top = y * glyph.rowStride;
      final int bottom = (glyph.height - 1 - y) * glyph.rowStride;
      for (int x = 0; x < glyph.width; x++) {
        topCoverage += pixels[top + x];
        bottomCoverage += pixels[bottom + x];
      }
    }
    _expect(
      !glyph.isColor &&
          !glyph.isEmpty &&
          bandHeight > 0 &&
          bottomCoverage > topCoverage,
      'top-down capital L raster keeps its horizontal foot at the bottom',
    );
  } finally {
    catalog.dispose();
  }
}

void _testLiveRasterScaleParity() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(pointSize: 14);
  try {
    void expectParity(
      String text, {
      required bool color,
      required double logicalTolerance,
    }) {
      final TerminalShapedText shaped = catalog.shape(text);
      final TerminalRasterizedGlyph one = catalog
          .rasterizeShaped(shaped)
          .glyphs
          .single;
      final TerminalRasterizedGlyph two = catalog
          .rasterizeShaped(shaped, scale: 2)
          .glyphs
          .single;
      final _RasterInkBounds oneInk = _rasterInkBounds(one);
      final _RasterInkBounds twoInk = _rasterInkBounds(two);
      _expect(
        one.isColor == color &&
            two.isColor == color &&
            oneInk.width > 0 &&
            oneInk.height > 0 &&
            twoInk.width > oneInk.width &&
            twoInk.height > oneInk.height &&
            (twoInk.width / 2 - oneInk.width).abs() <= logicalTolerance &&
            (twoInk.height / 2 - oneInk.height).abs() <= logicalTolerance &&
            twoInk.coverage > oneInk.coverage * 3,
        '$text raster preserves its logical ink size at 1x and 2x',
      );
    }

    expectParity('M', color: false, logicalTolerance: 1);
    expectParity('日', color: false, logicalTolerance: 1);
    expectParity('👩🏽‍💻', color: true, logicalTolerance: 3);
  } finally {
    catalog.dispose();
  }
}

void _testRasterValidationAndGeneration() {
  final TerminalFontCatalog first = TerminalFontCatalog.open();
  final TerminalShapedText shaped = first.shape('x');
  final TerminalShapedGlyph glyph = shaped.glyphs.single;
  final TerminalGlyphRasterRequest request = TerminalGlyphRasterRequest(
    faceId: glyph.faceId,
    glyphId: glyph.glyphId,
  );
  _expectThrows<ArgumentError>(
    () => first.rasterize(const <TerminalGlyphRasterRequest>[]),
    'empty raster request',
  );
  _expectThrows<ArgumentError>(
    () => first.rasterize(
      List<TerminalGlyphRasterRequest>.generate(
        TerminalRasterBufferV1.maximumGlyphs + 1,
        (int index) =>
            TerminalGlyphRasterRequest(faceId: glyph.faceId, glyphId: index),
      ),
    ),
    'raster batch count upper bound',
  );
  _expectThrows<ArgumentError>(
    () => first.rasterize(<TerminalGlyphRasterRequest>[request, request]),
    'duplicate raster key',
  );
  _expectThrows<RangeError>(
    () => first.rasterize(<TerminalGlyphRasterRequest>[request], scale: 0),
    'raster scale lower bound',
  );
  _expectThrows<ArgumentError>(
    () => first.rasterize(const <TerminalGlyphRasterRequest>[
      TerminalGlyphRasterRequest(faceId: 1, glyphId: 0x10000),
    ]),
    'CoreText glyph ID width',
  );
  _expectThrows<TerminalFontCatalogException>(
    () => first.rasterize(const <TerminalGlyphRasterRequest>[
      TerminalGlyphRasterRequest(faceId: 0xffffffff, glyphId: 1),
    ]),
    'unknown face ID',
  );
  first.dispose();
  _expectThrows<StateError>(
    () => first.rasterize(<TerminalGlyphRasterRequest>[request]),
    'disposed catalog cannot rasterize',
  );

  final TerminalFontCatalog second = TerminalFontCatalog.open();
  try {
    _expectThrows<StateError>(
      () => second.rasterizeShaped(shaped),
      'shaped result cannot cross catalog generations',
    );
  } finally {
    second.dispose();
  }
}

Uint8List _minimalRasterBuffer({required bool color}) {
  final int pixelLength = color ? 4 : 1;
  final Uint8List bytes = Uint8List(112 + pixelLength);
  final ByteData data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u32(0, 0x47525444);
  u32(4, 1);
  u32(8, 64);
  u32(12, bytes.length);
  data.setUint64(16, 99, Endian.little);
  u32(24, 1 << 16);
  u32(28, 1);
  u32(32, 64);
  u32(36, 112);
  u32(40, pixelLength);

  u32(64, 1);
  u32(68, 2);
  u32(72, color ? 2 : 1);
  u32(76, color ? TerminalRasterGlyphFlags.color : 0);
  data.setInt32(80, -1, Endian.little);
  data.setInt32(84, 2, Endian.little);
  u32(88, 1);
  u32(92, 1);
  u32(96, pixelLength);
  u32(100, 112);
  u32(104, pixelLength);
  if (color) {
    bytes.setAll(112, <int>[255, 32, 16, 255]);
  } else {
    bytes[112] = 255;
  }
  return bytes;
}

Uint8List _withU32(Uint8List source, int offset, int value) {
  final Uint8List copy = Uint8List.fromList(source);
  ByteData.sublistView(copy).setUint32(offset, value, Endian.little);
  return copy;
}

void _expectDecodeFailure(Uint8List bytes, String description) {
  _expectThrows<FormatException>(
    () => TerminalRasterBufferV1.decode(
      bytes,
      requests: const <TerminalGlyphRasterRequest>[
        TerminalGlyphRasterRequest(faceId: 1, glyphId: 2),
      ],
      catalogGeneration: 99,
      scale16_16: 1 << 16,
    ),
    'corrupt $description',
  );
}

_RasterInkBounds _rasterInkBounds(TerminalRasterizedGlyph glyph) {
  final Uint8List pixels = glyph.copyPixels();
  var left = glyph.width;
  var top = glyph.height;
  var right = -1;
  var bottom = -1;
  var coverage = 0;
  final int bytesPerPixel = glyph.isColor ? 4 : 1;
  final int alphaOffset = glyph.isColor ? 3 : 0;
  for (var y = 0; y < glyph.height; y++) {
    for (var x = 0; x < glyph.width; x++) {
      final int alpha =
          pixels[y * glyph.rowStride + x * bytesPerPixel + alphaOffset];
      if (alpha == 0) continue;
      coverage += alpha;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return _RasterInkBounds(
    width: right < left ? 0 : right - left + 1,
    height: bottom < top ? 0 : bottom - top + 1,
    coverage: coverage,
  );
}

final class _RasterInkBounds {
  const _RasterInkBounds({
    required this.width,
    required this.height,
    required this.coverage,
  });

  final int width;
  final int height;
  final int coverage;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('raster expectation failed: $description');
  }
}

void _expectThrows<T extends Object>(
  void Function() action,
  String description,
) {
  try {
    action();
  } on T {
    return;
  } on Object catch (error) {
    throw StateError(
      'raster expectation failed: $description threw ${error.runtimeType}',
    );
  }
  throw StateError('raster expectation failed: $description');
}
