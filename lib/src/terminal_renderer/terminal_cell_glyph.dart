import 'dart:typed_data';

/// Product-owned cell glyph families with deterministic device-pixel geometry.
enum TerminalCellGlyphFamily { boxDrawing, blockElement, braille, powerline }

/// One supported Unicode scalar and its product-owned geometry family.
final class TerminalCellGlyphSpec {
  const TerminalCellGlyphSpec({required this.scalar, required this.family});

  final int scalar;
  final TerminalCellGlyphFamily family;
}

/// Exact, bounded scalar classification for product-owned cell glyphs.
abstract final class TerminalCellGlyphClassifier {
  static const int acceptedScalarCount = 434;

  static TerminalCellGlyphSpec? classify(int scalar) {
    if (scalar >= 0x2500 && scalar <= 0x257f) {
      return TerminalCellGlyphSpec(
        scalar: scalar,
        family: TerminalCellGlyphFamily.boxDrawing,
      );
    }
    if (scalar >= 0x2580 && scalar <= 0x259f) {
      return TerminalCellGlyphSpec(
        scalar: scalar,
        family: TerminalCellGlyphFamily.blockElement,
      );
    }
    if (scalar >= 0x2800 && scalar <= 0x28ff) {
      return TerminalCellGlyphSpec(
        scalar: scalar,
        family: TerminalCellGlyphFamily.braille,
      );
    }
    if (scalar >= 0xe0b0 && scalar <= 0xe0bf ||
        scalar == 0xe0d2 ||
        scalar == 0xe0d4) {
      return TerminalCellGlyphSpec(
        scalar: scalar,
        family: TerminalCellGlyphFamily.powerline,
      );
    }
    return null;
  }

  static bool supports(int scalar) => classify(scalar) != null;
}

/// Hard resource limits for one alpha-only cell raster.
abstract final class TerminalCellGlyphRasterLimits {
  static const int maximumDimension = 4096;
  static const int maximumByteLength = maximumDimension * maximumDimension;
}

/// Validated device-pixel geometry for one product-owned cell raster.
final class TerminalCellGlyphRasterRequest {
  TerminalCellGlyphRasterRequest({
    required this.scalar,
    required this.cellWidth,
    required this.cellHeight,
    required this.lineThickness,
  }) : spec = _requireSpec(scalar) {
    RangeError.checkValueInInterval(
      cellWidth,
      1,
      TerminalCellGlyphRasterLimits.maximumDimension,
      'cellWidth',
    );
    RangeError.checkValueInInterval(
      cellHeight,
      1,
      TerminalCellGlyphRasterLimits.maximumDimension,
      'cellHeight',
    );
    RangeError.checkValueInInterval(
      lineThickness,
      1,
      cellWidth < cellHeight ? cellWidth : cellHeight,
      'lineThickness',
    );
    if (cellWidth * cellHeight >
        TerminalCellGlyphRasterLimits.maximumByteLength) {
      throw RangeError('cell raster exceeds the byte limit');
    }
  }

  final int scalar;
  final int cellWidth;
  final int cellHeight;
  final int lineThickness;
  final TerminalCellGlyphSpec spec;

  int get byteLength => cellWidth * cellHeight;

  /// Minimum coordinate for a fractional region.
  ///
  /// It is aligned to the complementary maximum coordinate. On odd extents,
  /// adjoining regions overlap by one device pixel instead of leaving a seam.
  int fractionMin(int numerator, int denominator, {required int extent}) {
    _validateFraction(numerator, denominator, extent);
    return extent -
        _roundFraction(denominator - numerator, denominator, extent);
  }

  /// Maximum coordinate for a fractional region, using half-up rounding.
  int fractionMax(int numerator, int denominator, {required int extent}) {
    _validateFraction(numerator, denominator, extent);
    return _roundFraction(numerator, denominator, extent);
  }

  static TerminalCellGlyphSpec _requireSpec(int scalar) {
    final TerminalCellGlyphSpec? spec = TerminalCellGlyphClassifier.classify(
      scalar,
    );
    if (spec == null) {
      throw ArgumentError.value(
        scalar,
        'scalar',
        'is not a product-owned cell glyph',
      );
    }
    return spec;
  }

  static void _validateFraction(int numerator, int denominator, int extent) {
    if (denominator <= 0 || numerator < 0 || numerator > denominator) {
      throw ArgumentError('fraction must be between zero and one');
    }
    if (extent <= 0 ||
        extent > TerminalCellGlyphRasterLimits.maximumDimension) {
      throw RangeError.range(
        extent,
        1,
        TerminalCellGlyphRasterLimits.maximumDimension,
        'extent',
      );
    }
  }

  static int _roundFraction(int numerator, int denominator, int extent) =>
      (numerator * extent * 2 + denominator) ~/ (denominator * 2);
}

/// Immutable alpha coverage produced for one validated cell request.
final class TerminalCellGlyphRaster {
  TerminalCellGlyphRaster({required this.request, required Uint8List coverage})
    : _coverage = Uint8List.fromList(coverage) {
    if (coverage.length != request.byteLength) {
      throw ArgumentError.value(
        coverage.length,
        'coverage',
        'must contain exactly ${request.byteLength} alpha bytes',
      );
    }
  }

  final TerminalCellGlyphRasterRequest request;
  final Uint8List _coverage;

  int get width => request.cellWidth;
  int get height => request.cellHeight;
  int get rowStride => request.cellWidth;
  int get byteLength => _coverage.length;

  Uint8List copyCoverage() => Uint8List.fromList(_coverage);

  int coverageAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    return _coverage[y * rowStride + x];
  }
}
