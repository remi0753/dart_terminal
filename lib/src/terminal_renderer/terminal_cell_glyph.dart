import 'dart:math' as math;
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

  TerminalCellGlyphRaster._owned({
    required this.request,
    required Uint8List coverage,
  }) : _coverage = coverage {
    if (coverage.length != request.byteLength) {
      throw StateError('owned cell raster has an invalid alpha byte length');
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

/// Deterministic raster entry points for product-owned cell glyph families.
abstract final class TerminalCellGlyphRasterizer {
  static TerminalCellGlyphRaster rasterizeBoxDrawing(
    TerminalCellGlyphRasterRequest request,
  ) {
    if (request.spec.family != TerminalCellGlyphFamily.boxDrawing) {
      throw ArgumentError.value(
        request.scalar,
        'request',
        'must classify as Box Drawing',
      );
    }
    final _TerminalCellGlyphCanvas canvas = _TerminalCellGlyphCanvas(request);
    switch (request.scalar) {
      case >= 0x2504 && <= 0x250b:
        final bool horizontal = request.scalar.isEven;
        final bool heavy = request.scalar.isOdd;
        final int count = request.scalar < 0x2508 ? 3 : 4;
        final int thickness = heavy
            ? request.lineThickness * 2
            : request.lineThickness;
        final int desiredGap = math.max(4, request.lineThickness);
        if (horizontal) {
          _drawHorizontalDashes(
            canvas,
            count: count,
            thickness: thickness,
            desiredGap: desiredGap,
          );
        } else {
          _drawVerticalDashes(
            canvas,
            count: count,
            thickness: thickness,
            desiredGap: desiredGap,
          );
        }
      case 0x254c:
        _drawHorizontalDashes(
          canvas,
          count: 2,
          thickness: request.lineThickness,
          desiredGap: request.lineThickness,
        );
      case 0x254d:
        _drawHorizontalDashes(
          canvas,
          count: 2,
          thickness: request.lineThickness * 2,
          desiredGap: request.lineThickness * 2,
        );
      case 0x254e:
        _drawVerticalDashes(
          canvas,
          count: 2,
          thickness: request.lineThickness,
          desiredGap: request.lineThickness * 2,
        );
      case 0x254f:
        _drawVerticalDashes(
          canvas,
          count: 2,
          thickness: request.lineThickness * 2,
          desiredGap: request.lineThickness * 2,
        );
      case >= 0x256d && <= 0x2570:
        _drawArc(canvas, request.scalar - 0x256d);
      case 0x2571:
        canvas.line(
          canvas.width + 0.5,
          -0.5,
          -0.5,
          canvas.height + 0.5,
          request.lineThickness.toDouble(),
        );
      case 0x2572:
        canvas.line(
          -0.5,
          -0.5,
          canvas.width + 0.5,
          canvas.height + 0.5,
          request.lineThickness.toDouble(),
        );
      case 0x2573:
        canvas
          ..line(
            canvas.width + 0.5,
            -0.5,
            -0.5,
            canvas.height + 0.5,
            request.lineThickness.toDouble(),
          )
          ..line(
            -0.5,
            -0.5,
            canvas.width + 0.5,
            canvas.height + 0.5,
            request.lineThickness.toDouble(),
          );
      default:
        _drawBoxLines(
          canvas,
          _BoxLines.decode(_boxLineTopologies[request.scalar - 0x2500]),
        );
    }
    return TerminalCellGlyphRaster._owned(
      request: request,
      coverage: canvas.takeCoverage(),
    );
  }
}

enum _BoxLineStyle { none, light, heavy, double }

final class _BoxLines {
  const _BoxLines({
    required this.up,
    required this.right,
    required this.down,
    required this.left,
  });

  factory _BoxLines.decode(int value) => _BoxLines(
    up: _BoxLineStyle.values[(value >> 6) & 3],
    right: _BoxLineStyle.values[(value >> 4) & 3],
    down: _BoxLineStyle.values[(value >> 2) & 3],
    left: _BoxLineStyle.values[value & 3],
  );

  final _BoxLineStyle up;
  final _BoxLineStyle right;
  final _BoxLineStyle down;
  final _BoxLineStyle left;
}

// Packed as two-bit up/right/down/left styles. Zero entries are handled by
// dedicated dash, arc, or diagonal branches before this table is consulted.
const List<int> _boxLineTopologies = <int>[
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

void _drawBoxLines(_TerminalCellGlyphCanvas canvas, _BoxLines lines) {
  final int light = canvas.request.lineThickness;
  final int heavy = light * 2;
  final int hLightTop = math.max(0, canvas.height - light) ~/ 2;
  final int hLightBottom = hLightTop + light;
  final int hHeavyTop = math.max(0, canvas.height - heavy) ~/ 2;
  final int hHeavyBottom = hHeavyTop + heavy;
  final int hDoubleTop = math.max(0, hLightTop - light);
  final int hDoubleBottom = hLightBottom + light;
  final int vLightLeft = math.max(0, canvas.width - light) ~/ 2;
  final int vLightRight = vLightLeft + light;
  final int vHeavyLeft = math.max(0, canvas.width - heavy) ~/ 2;
  final int vHeavyRight = vHeavyLeft + heavy;
  final int vDoubleLeft = math.max(0, vLightLeft - light);
  final int vDoubleRight = vLightRight + light;

  final int upBottom =
      lines.left == _BoxLineStyle.heavy || lines.right == _BoxLineStyle.heavy
      ? hHeavyBottom
      : lines.left != lines.right || lines.down == lines.up
      ? lines.left == _BoxLineStyle.double ||
                lines.right == _BoxLineStyle.double
            ? hDoubleBottom
            : hLightBottom
      : lines.left == _BoxLineStyle.none && lines.right == _BoxLineStyle.none
      ? hLightBottom
      : hLightTop;
  final int downTop =
      lines.left == _BoxLineStyle.heavy || lines.right == _BoxLineStyle.heavy
      ? hHeavyTop
      : lines.left != lines.right || lines.up == lines.down
      ? lines.left == _BoxLineStyle.double ||
                lines.right == _BoxLineStyle.double
            ? hDoubleTop
            : hLightTop
      : lines.left == _BoxLineStyle.none && lines.right == _BoxLineStyle.none
      ? hLightTop
      : hLightBottom;
  final int leftRight =
      lines.up == _BoxLineStyle.heavy || lines.down == _BoxLineStyle.heavy
      ? vHeavyRight
      : lines.up != lines.down || lines.left == lines.right
      ? lines.up == _BoxLineStyle.double || lines.down == _BoxLineStyle.double
            ? vDoubleRight
            : vLightRight
      : lines.up == _BoxLineStyle.none && lines.down == _BoxLineStyle.none
      ? vLightRight
      : vLightLeft;
  final int rightLeft =
      lines.up == _BoxLineStyle.heavy || lines.down == _BoxLineStyle.heavy
      ? vHeavyLeft
      : lines.up != lines.down || lines.right == lines.left
      ? lines.up == _BoxLineStyle.double || lines.down == _BoxLineStyle.double
            ? vDoubleLeft
            : vLightLeft
      : lines.up == _BoxLineStyle.none && lines.down == _BoxLineStyle.none
      ? vLightLeft
      : vLightRight;

  switch (lines.up) {
    case _BoxLineStyle.none:
      break;
    case _BoxLineStyle.light:
      canvas.rect(vLightLeft, 0, vLightRight, upBottom);
    case _BoxLineStyle.heavy:
      canvas.rect(vHeavyLeft, 0, vHeavyRight, upBottom);
    case _BoxLineStyle.double:
      final int leftBottom = lines.left == _BoxLineStyle.double
          ? hLightTop
          : upBottom;
      final int rightBottom = lines.right == _BoxLineStyle.double
          ? hLightTop
          : upBottom;
      canvas
        ..rect(vDoubleLeft, 0, vLightLeft, leftBottom)
        ..rect(vLightRight, 0, vDoubleRight, rightBottom);
  }
  switch (lines.right) {
    case _BoxLineStyle.none:
      break;
    case _BoxLineStyle.light:
      canvas.rect(rightLeft, hLightTop, canvas.width, hLightBottom);
    case _BoxLineStyle.heavy:
      canvas.rect(rightLeft, hHeavyTop, canvas.width, hHeavyBottom);
    case _BoxLineStyle.double:
      final int topLeft = lines.up == _BoxLineStyle.double
          ? vLightRight
          : rightLeft;
      final int bottomLeft = lines.down == _BoxLineStyle.double
          ? vLightRight
          : rightLeft;
      canvas
        ..rect(topLeft, hDoubleTop, canvas.width, hLightTop)
        ..rect(bottomLeft, hLightBottom, canvas.width, hDoubleBottom);
  }
  switch (lines.down) {
    case _BoxLineStyle.none:
      break;
    case _BoxLineStyle.light:
      canvas.rect(vLightLeft, downTop, vLightRight, canvas.height);
    case _BoxLineStyle.heavy:
      canvas.rect(vHeavyLeft, downTop, vHeavyRight, canvas.height);
    case _BoxLineStyle.double:
      final int leftTop = lines.left == _BoxLineStyle.double
          ? hLightBottom
          : downTop;
      final int rightTop = lines.right == _BoxLineStyle.double
          ? hLightBottom
          : downTop;
      canvas
        ..rect(vDoubleLeft, leftTop, vLightLeft, canvas.height)
        ..rect(vLightRight, rightTop, vDoubleRight, canvas.height);
  }
  switch (lines.left) {
    case _BoxLineStyle.none:
      break;
    case _BoxLineStyle.light:
      canvas.rect(0, hLightTop, leftRight, hLightBottom);
    case _BoxLineStyle.heavy:
      canvas.rect(0, hHeavyTop, leftRight, hHeavyBottom);
    case _BoxLineStyle.double:
      final int topRight = lines.up == _BoxLineStyle.double
          ? vLightLeft
          : leftRight;
      final int bottomRight = lines.down == _BoxLineStyle.double
          ? vLightLeft
          : leftRight;
      canvas
        ..rect(0, hDoubleTop, topRight, hLightTop)
        ..rect(0, hLightBottom, bottomRight, hDoubleBottom);
  }
}

void _drawHorizontalDashes(
  _TerminalCellGlyphCanvas canvas, {
  required int count,
  required int thickness,
  required int desiredGap,
}) {
  if (canvas.width < count * 2) {
    _drawHorizontalMiddle(canvas, canvas.request.lineThickness);
    return;
  }
  final int gapWidth = math.min(desiredGap, canvas.width ~/ (2 * count));
  final int totalDashWidth = canvas.width - count * gapWidth;
  final int dashWidth = totalDashWidth ~/ count;
  var remaining = totalDashWidth % count;
  final int y = math.max(0, canvas.height - thickness) ~/ 2;
  var x = gapWidth ~/ 2;
  for (int dash = 0; dash < count; dash++) {
    var right = x + dashWidth;
    if (remaining > 0) {
      remaining--;
      right++;
    }
    canvas.rect(x, y, right, y + thickness);
    x = right + gapWidth;
  }
}

void _drawVerticalDashes(
  _TerminalCellGlyphCanvas canvas, {
  required int count,
  required int thickness,
  required int desiredGap,
}) {
  if (canvas.height < count * 2) {
    _drawVerticalMiddle(canvas, canvas.request.lineThickness);
    return;
  }
  final int gapHeight = math.min(desiredGap, canvas.height ~/ (2 * count));
  final int totalDashHeight = canvas.height - count * gapHeight;
  final int dashHeight = totalDashHeight ~/ count;
  var remaining = totalDashHeight % count;
  final int x = math.max(0, canvas.width - thickness) ~/ 2;
  var y = 0;
  for (int dash = 0; dash < count; dash++) {
    var bottom = y + dashHeight;
    if (remaining > 0) {
      remaining--;
      bottom++;
    }
    canvas.rect(x, y, x + thickness, bottom);
    y = bottom + gapHeight;
  }
}

void _drawHorizontalMiddle(_TerminalCellGlyphCanvas canvas, int thickness) {
  final int top = math.max(0, canvas.height - thickness) ~/ 2;
  canvas.rect(0, top, canvas.width, top + thickness);
}

void _drawVerticalMiddle(_TerminalCellGlyphCanvas canvas, int thickness) {
  final int left = math.max(0, canvas.width - thickness) ~/ 2;
  canvas.rect(left, 0, left + thickness, canvas.height);
}

// Corner order follows U+256D..U+2570: down-right, down-left, up-left,
// up-right. Curves use the pinned center-biased cubic approximation between the
// straight center segments and are clipped by the cell canvas.
void _drawArc(_TerminalCellGlyphCanvas canvas, int corner) {
  final double thickness = canvas.request.lineThickness.toDouble();
  final double centerX =
      (math.max(0, canvas.width - canvas.request.lineThickness) ~/ 2) +
      thickness / 2;
  final double centerY =
      (math.max(0, canvas.height - canvas.request.lineThickness) ~/ 2) +
      thickness / 2;
  final double radius = math.min(canvas.width, canvas.height) / 2;
  final bool down = corner <= 1;
  final bool right = corner == 0 || corner == 3;
  final double verticalEdge = down ? canvas.height + 0.5 : -0.5;
  final double verticalCurve = centerY + (down ? radius : -radius);
  final double horizontalCurve = centerX + (right ? radius : -radius);
  final double horizontalEdge = right ? canvas.width + 0.5 : -0.5;
  canvas.line(centerX, verticalEdge, centerX, verticalCurve, thickness);
  final int steps = math.max(
    8,
    math.min(128, math.max(canvas.width, canvas.height)),
  );
  var previousX = centerX;
  var previousY = verticalCurve;
  const double controlFraction = 0.25;
  final double firstControlX = centerX;
  final double firstControlY =
      centerY + (down ? controlFraction * radius : -controlFraction * radius);
  final double secondControlX =
      centerX + (right ? controlFraction * radius : -controlFraction * radius);
  final double secondControlY = centerY;
  for (int step = 1; step <= steps; step++) {
    final double t = step / steps;
    final double inverse = 1 - t;
    final double x =
        inverse * inverse * inverse * centerX +
        3 * inverse * inverse * t * firstControlX +
        3 * inverse * t * t * secondControlX +
        t * t * t * horizontalCurve;
    final double y =
        inverse * inverse * inverse * verticalCurve +
        3 * inverse * inverse * t * firstControlY +
        3 * inverse * t * t * secondControlY +
        t * t * t * centerY;
    canvas.line(previousX, previousY, x, y, thickness);
    previousX = x;
    previousY = y;
  }
  canvas.line(horizontalCurve, centerY, horizontalEdge, centerY, thickness);
}

final class _TerminalCellGlyphCanvas {
  _TerminalCellGlyphCanvas(this.request)
    : _coverage = Uint8List(request.byteLength);

  final TerminalCellGlyphRasterRequest request;
  final Uint8List _coverage;

  int get width => request.cellWidth;
  int get height => request.cellHeight;

  void rect(int left, int top, int right, int bottom, [int alpha = 0xff]) {
    final int clippedLeft = left.clamp(0, width);
    final int clippedTop = top.clamp(0, height);
    final int clippedRight = right.clamp(0, width);
    final int clippedBottom = bottom.clamp(0, height);
    if (clippedLeft >= clippedRight || clippedTop >= clippedBottom) return;
    for (int y = clippedTop; y < clippedBottom; y++) {
      final int row = y * width;
      for (int x = clippedLeft; x < clippedRight; x++) {
        final int offset = row + x;
        if (_coverage[offset] < alpha) _coverage[offset] = alpha;
      }
    }
  }

  void line(double x0, double y0, double x1, double y1, double thickness) {
    final double radius = thickness / 2;
    final int left = math.max(0, (math.min(x0, x1) - radius - 1).floor());
    final int right = math.min(width, (math.max(x0, x1) + radius + 1).ceil());
    final int top = math.max(0, (math.min(y0, y1) - radius - 1).floor());
    final int bottom = math.min(height, (math.max(y0, y1) + radius + 1).ceil());
    final double vx = x1 - x0;
    final double vy = y1 - y0;
    final double squaredLength = vx * vx + vy * vy;
    for (int y = top; y < bottom; y++) {
      for (int x = left; x < right; x++) {
        final double px = x + 0.5;
        final double py = y + 0.5;
        final double projection = squaredLength == 0
            ? 0
            : ((px - x0) * vx + (py - y0) * vy) / squaredLength;
        final double t = projection.clamp(0.0, 1.0);
        final double dx = px - (x0 + t * vx);
        final double dy = py - (y0 + t * vy);
        final double distance = math.sqrt(dx * dx + dy * dy);
        final int alpha = ((radius + 0.5 - distance) * 255).round().clamp(
          0,
          255,
        );
        if (alpha == 0) continue;
        final int offset = y * width + x;
        if (_coverage[offset] < alpha) _coverage[offset] = alpha;
      }
    }
  }

  Uint8List takeCoverage() => _coverage;
}
