import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_typography.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalLiveMetalSurfaceFontTests();

void runTerminalLiveMetalSurfaceFontTests() {
  _testDefaultFont();
  _testDefaultFontRasterScaleParity();
  _testConfiguredFontPolicy();
}

void _testDefaultFont() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(
    family: TerminalLiveMetalSurface.defaultFontFamily,
    pointSize: TerminalLiveMetalSurface.defaultFontPointSize,
  );
  try {
    const String sample = 'Readable0O1l';
    final TerminalResolvedFont latin = catalog.resolve(sample);
    final TerminalFontCatalogMetrics metrics = catalog.metrics;
    final TerminalGlyphRasterBatch raster = catalog.rasterizeShaped(
      catalog.shape(sample),
      scale: 2,
    );
    final TerminalRasterizedGlyph orientation = catalog
        .rasterizeShaped(catalog.shape('L'), scale: 2)
        .glyphs
        .single;
    _expect(
      catalog.family.isEmpty &&
          TerminalLiveMetalSurface.defaultFontFamily ==
              TerminalDefaultTypography.fontFamily &&
          metrics.pointSize == TerminalDefaultTypography.fontSize &&
          latin.isMonospaced &&
          !latin.isFallback &&
          !latin.hasMissingGlyph &&
          metrics.cellWidth > 0 &&
          metrics.cellHeight > 0 &&
          metrics.baseline > 0 &&
          raster.glyphs.isNotEmpty &&
          raster.glyphs.every(
            (TerminalRasterizedGlyph glyph) =>
                !glyph.isMissing &&
                !glyph.isEmpty &&
                glyph.copyPixels().any((int value) => value != 0),
          ) &&
          _bottomBandCoverage(orientation) > _topBandCoverage(orientation),
      'live surface default uses the readable macOS system monospace metrics',
    );
  } finally {
    catalog.dispose();
  }
}

void _testDefaultFontRasterScaleParity() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(
    family: TerminalDefaultTypography.fontFamily,
    pointSize: TerminalDefaultTypography.fontSize,
  );
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
        'shared 14pt $text raster preserves logical ink size at 1x and 2x',
      );
    }

    expectParity('M', color: false, logicalTolerance: 1);
    expectParity('日', color: false, logicalTolerance: 1);
    expectParity('👩🏽‍💻', color: true, logicalTolerance: 3);
  } finally {
    catalog.dispose();
  }
}

void _testConfiguredFontPolicy() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(
    family: 'Menlo',
    pointSize: 18,
    syntheticStylePolicy: TerminalSyntheticStylePolicy.reject,
  );
  try {
    _expect(
      catalog.family == 'Menlo' &&
          catalog.metrics.pointSize == 18 &&
          catalog.syntheticStylePolicy == TerminalSyntheticStylePolicy.reject,
      'configured font family, point size, and synthetic policy are retained',
    );
  } finally {
    catalog.dispose();
  }
}

int _topBandCoverage(TerminalRasterizedGlyph glyph) =>
    _bandCoverage(glyph, fromBottom: false);

int _bottomBandCoverage(TerminalRasterizedGlyph glyph) =>
    _bandCoverage(glyph, fromBottom: true);

int _bandCoverage(TerminalRasterizedGlyph glyph, {required bool fromBottom}) {
  final List<int> pixels = glyph.copyPixels();
  final int bandHeight = glyph.height ~/ 3;
  var coverage = 0;
  for (int y = 0; y < bandHeight; y++) {
    final int row = fromBottom ? glyph.height - 1 - y : y;
    final int start = row * glyph.rowStride;
    for (int x = 0; x < glyph.width; x++) {
      coverage += pixels[start + x];
    }
  }
  return coverage;
}

_RasterInkBounds _rasterInkBounds(TerminalRasterizedGlyph glyph) {
  final List<int> pixels = glyph.copyPixels();
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
    throw StateError('live Metal font expectation failed: $description');
  }
}
