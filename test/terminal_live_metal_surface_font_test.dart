import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalLiveMetalSurfaceFontTests();

void runTerminalLiveMetalSurfaceFontTests() {
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
          metrics.pointSize == 13 &&
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

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('live Metal font expectation failed: $description');
  }
}
