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
          ),
      'live surface default uses the readable macOS system monospace metrics',
    );
  } finally {
    catalog.dispose();
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('live Metal font expectation failed: $description');
  }
}
