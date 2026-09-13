import 'dart:math' as math;
import 'dart:typed_data';

import 'terminal_overlay.dart';

/// Draw order shared by the deterministic reference renderer and the native
/// renderer contract.
enum TerminalReferenceLayer {
  imageBelowBackground,
  cellBackground,
  selection,
  imageBelowText,
  glyph,
  imageAboveText,
  decoration,
  cursor,
}

/// Straight-alpha 8-bit sRGB color, packed as `0xRRGGBBAA`.
final class TerminalReferenceColor {
  const TerminalReferenceColor(this.rgba)
    : assert(rgba >= 0 && rgba <= 0xffffffff);

  /// Converts an explicitly tagged input once at the canonical sRGB boundary.
  factory TerminalReferenceColor.fromRenderColor(TerminalRenderColor color) =>
      TerminalReferenceColor(color.canonicalSrgbRgba);

  final int rgba;

  int get red => (rgba >> 24) & 0xff;
  int get green => (rgba >> 16) & 0xff;
  int get blue => (rgba >> 8) & 0xff;
  int get alpha => rgba & 0xff;

  static const TerminalReferenceColor transparent = TerminalReferenceColor(0);
}

/// Hard limits applied before allocating an image or traversing a scene.
final class TerminalReferenceRenderLimits {
  const TerminalReferenceRenderLimits({
    this.maximumLogicalWidth = 4096,
    this.maximumLogicalHeight = 4096,
    this.maximumScale = 4,
    this.maximumPixelCount = 16 * 1024 * 1024,
    this.maximumPrimitiveCount = 1 * 1024 * 1024,
    this.maximumSourceBytes = 64 * 1024 * 1024,
  });

  final int maximumLogicalWidth;
  final int maximumLogicalHeight;
  final int maximumScale;
  final int maximumPixelCount;
  final int maximumPrimitiveCount;
  final int maximumSourceBytes;

  void validate() {
    _requirePositive(maximumLogicalWidth, 'maximumLogicalWidth');
    _requirePositive(maximumLogicalHeight, 'maximumLogicalHeight');
    _requirePositive(maximumScale, 'maximumScale');
    _requirePositive(maximumPixelCount, 'maximumPixelCount');
    _requireNonnegative(maximumPrimitiveCount, 'maximumPrimitiveCount');
    _requireNonnegative(maximumSourceBytes, 'maximumSourceBytes');
  }
}

/// Immutable primitive consumed by [TerminalReferenceRenderer].
sealed class TerminalReferencePrimitive {
  const TerminalReferencePrimitive({
    required this.layer,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final TerminalReferenceLayer layer;
  final int x;
  final int y;
  final int width;
  final int height;

  int get sourceByteCount;
}

/// A logical-pixel rectangle filled with one straight-alpha color.
final class TerminalReferenceSolid extends TerminalReferencePrimitive {
  const TerminalReferenceSolid({
    required super.layer,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.color,
  });

  final TerminalReferenceColor color;

  @override
  int get sourceByteCount => 0;
}

/// An immutable 8-bit coverage mask tinted with one straight-alpha color.
final class TerminalReferenceMask extends TerminalReferencePrimitive {
  TerminalReferenceMask({
    required super.layer,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.rowStride,
    required List<int> coverage,
    required this.color,
  }) : _coverage = _copyUint8List(coverage, 'coverage') {
    _validateSourceShape(width, height, rowStride, _coverage.length, 1);
  }

  final int rowStride;
  final Uint8List _coverage;
  final TerminalReferenceColor color;

  @override
  int get sourceByteCount => _coverage.length;
}

/// An immutable straight-alpha RGBA8 sRGB bitmap.
final class TerminalReferenceBitmap extends TerminalReferencePrimitive {
  TerminalReferenceBitmap({
    required super.layer,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.rowStride,
    required List<int> rgba,
    this.opacity = 255,
    TerminalRenderColorSpace inputColorSpace = TerminalRenderColorSpace.srgb,
  }) : _rgba = _canonicalSrgbBitmap(
         rgba,
         inputColorSpace,
         width,
         height,
         rowStride,
       ) {
    _validateSourceShape(width, height, rowStride, _rgba.length, 4);
    RangeError.checkValueInInterval(opacity, 0, 255, 'opacity');
  }

  final int rowStride;
  final Uint8List _rgba;
  final int opacity;

  @override
  int get sourceByteCount => _rgba.length;
}

/// One immutable bitmap that can be shared by multiple sampled primitives.
final class TerminalReferenceBitmapSource {
  TerminalReferenceBitmapSource({
    required this.width,
    required this.height,
    required this.rowStride,
    required List<int> rgba,
    TerminalRenderColorSpace inputColorSpace = TerminalRenderColorSpace.srgb,
  }) : _rgba = _canonicalSrgbBitmap(
         rgba,
         inputColorSpace,
         width,
         height,
         rowStride,
       ) {
    _validateSourceShape(width, height, rowStride, _rgba.length, 4);
  }

  final int width;
  final int height;
  final int rowStride;
  final Uint8List _rgba;

  int get byteLength => _rgba.length;
}

/// A nearest-neighbor source rectangle scaled into a logical destination.
final class TerminalReferenceSampledBitmap extends TerminalReferencePrimitive {
  TerminalReferenceSampledBitmap({
    required super.layer,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.source,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    this.opacity = 255,
  }) {
    RangeError.checkValueInInterval(opacity, 0, 255, 'opacity');
    if (sourceX < 0 ||
        sourceY < 0 ||
        sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        sourceX + sourceWidth > source.width ||
        sourceY + sourceHeight > source.height) {
      throw RangeError('sampled bitmap source rectangle is out of bounds');
    }
  }

  final TerminalReferenceBitmapSource source;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int opacity;

  /// Shared source bytes are accounted once by the renderer.
  @override
  int get sourceByteCount => 0;
}

/// Owned, tightly packed straight-alpha RGBA8 sRGB image.
final class TerminalReferenceImage {
  factory TerminalReferenceImage.fromRgba({
    required int width,
    required int height,
    required int scale,
    required List<int> rgba,
    TerminalReferenceRenderLimits limits =
        const TerminalReferenceRenderLimits(),
  }) {
    limits.validate();
    _validateImageDimensions(width, height, scale, limits);
    final int expectedBytes = _checkedProduct(
      _checkedProduct(width, height, 'image pixel count'),
      4,
      'image byte count',
    );
    if (rgba.length != expectedBytes) {
      throw ArgumentError.value(
        rgba.length,
        'rgba.length',
        'must equal width * height * 4 ($expectedBytes)',
      );
    }
    return TerminalReferenceImage._(
      width: width,
      height: height,
      scale: scale,
      rgba: _copyUint8List(rgba, 'rgba'),
    );
  }

  TerminalReferenceImage._({
    required this.width,
    required this.height,
    required this.scale,
    required Uint8List rgba,
  }) : _rgba = rgba;

  final int width;
  final int height;
  final int scale;
  final Uint8List _rgba;

  int get logicalWidth => width ~/ scale;
  int get logicalHeight => height ~/ scale;
  int get rowStride => width * 4;
  int get byteLength => _rgba.length;

  /// Returns a copy so callers cannot mutate the oracle after construction.
  Uint8List copyRgbaBytes() => Uint8List.fromList(_rgba);

  /// Returns one pixel packed as `0xRRGGBBAA`.
  int pixelAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    final int offset = (y * width + x) * 4;
    return (_rgba[offset] << 24) |
        (_rgba[offset + 1] << 16) |
        (_rgba[offset + 2] << 8) |
        _rgba[offset + 3];
  }
}

/// Deterministic CPU compositor used as the renderer correctness oracle.
///
/// Coordinates and source pixels are logical pixels. [scale] expands every
/// logical source pixel into an exact `scale × scale` device-pixel block.
/// Primitives are grouped by [TerminalReferenceLayer], preserving caller order
/// only within the same layer.
abstract final class TerminalReferenceRenderer {
  static TerminalReferenceImage render({
    required int width,
    required int height,
    int scale = 1,
    TerminalReferenceColor background = TerminalReferenceColor.transparent,
    Iterable<TerminalReferencePrimitive> primitives =
        const <TerminalReferencePrimitive>[],
    TerminalReferenceRenderLimits limits =
        const TerminalReferenceRenderLimits(),
  }) {
    limits.validate();
    _validateColor(background, 'background');
    if (width <= 0 || width > limits.maximumLogicalWidth) {
      throw RangeError.range(width, 1, limits.maximumLogicalWidth, 'width');
    }
    if (height <= 0 || height > limits.maximumLogicalHeight) {
      throw RangeError.range(height, 1, limits.maximumLogicalHeight, 'height');
    }
    if (scale <= 0 || scale > limits.maximumScale) {
      throw RangeError.range(scale, 1, limits.maximumScale, 'scale');
    }
    final int pixelWidth = _checkedProduct(width, scale, 'pixel width');
    final int pixelHeight = _checkedProduct(height, scale, 'pixel height');
    _validateImageDimensions(pixelWidth, pixelHeight, scale, limits);
    final int pixelCount = _checkedProduct(
      pixelWidth,
      pixelHeight,
      'image pixel count',
    );
    final Uint8List pixels = Uint8List(
      _checkedProduct(pixelCount, 4, 'image byte count'),
    );
    _fill(pixels, background);

    final List<TerminalReferencePrimitive> retained =
        <TerminalReferencePrimitive>[];
    final Set<TerminalReferenceBitmapSource> retainedBitmapSources =
        Set<TerminalReferenceBitmapSource>.identity();
    var sourceBytes = 0;
    for (final TerminalReferencePrimitive primitive in primitives) {
      if (retained.length == limits.maximumPrimitiveCount) {
        throw StateError(
          'reference primitive limit exceeded: more than '
          '${limits.maximumPrimitiveCount}',
        );
      }
      _validatePrimitive(primitive, width, height, limits);
      sourceBytes += switch (primitive) {
        TerminalReferenceSampledBitmap() =>
          retainedBitmapSources.add(primitive.source)
              ? primitive.source.byteLength
              : 0,
        _ => primitive.sourceByteCount,
      };
      if (sourceBytes > limits.maximumSourceBytes) {
        throw StateError(
          'reference source-byte limit exceeded: $sourceBytes > '
          '${limits.maximumSourceBytes}',
        );
      }
      retained.add(primitive);
    }
    for (final TerminalReferenceLayer layer in TerminalReferenceLayer.values) {
      for (final TerminalReferencePrimitive primitive in retained) {
        if (primitive.layer != layer) {
          continue;
        }
        switch (primitive) {
          case TerminalReferenceSolid():
            _drawSolid(pixels, pixelWidth, pixelHeight, scale, primitive);
          case TerminalReferenceMask():
            _drawMask(pixels, pixelWidth, pixelHeight, scale, primitive);
          case TerminalReferenceBitmap():
            _drawBitmap(pixels, pixelWidth, pixelHeight, scale, primitive);
          case TerminalReferenceSampledBitmap():
            _drawSampledBitmap(
              pixels,
              pixelWidth,
              pixelHeight,
              scale,
              primitive,
            );
        }
      }
    }
    return TerminalReferenceImage._(
      width: pixelWidth,
      height: pixelHeight,
      scale: scale,
      rgba: pixels,
    );
  }

  static void _fill(Uint8List pixels, TerminalReferenceColor color) {
    for (int offset = 0; offset < pixels.length; offset += 4) {
      pixels[offset] = color.red;
      pixels[offset + 1] = color.green;
      pixels[offset + 2] = color.blue;
      pixels[offset + 3] = color.alpha;
    }
  }

  static void _drawSolid(
    Uint8List pixels,
    int pixelWidth,
    int pixelHeight,
    int scale,
    TerminalReferenceSolid primitive,
  ) {
    final _ClippedDeviceRect rect = _clipDeviceRect(
      primitive.x,
      primitive.y,
      primitive.width,
      primitive.height,
      scale,
      pixelWidth,
      pixelHeight,
    );
    for (int y = rect.top; y < rect.bottom; y++) {
      for (int x = rect.left; x < rect.right; x++) {
        _blend(pixels, (y * pixelWidth + x) * 4, primitive.color, 255);
      }
    }
  }

  static void _drawMask(
    Uint8List pixels,
    int pixelWidth,
    int pixelHeight,
    int scale,
    TerminalReferenceMask primitive,
  ) {
    _forEachScaledSourcePixel(
      x: primitive.x,
      y: primitive.y,
      width: primitive.width,
      height: primitive.height,
      scale: scale,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      visit: (int sourceX, int sourceY, int deviceX, int deviceY) {
        final int coverage =
            primitive._coverage[sourceY * primitive.rowStride + sourceX];
        _blend(
          pixels,
          (deviceY * pixelWidth + deviceX) * 4,
          primitive.color,
          coverage,
        );
      },
    );
  }

  static void _drawBitmap(
    Uint8List pixels,
    int pixelWidth,
    int pixelHeight,
    int scale,
    TerminalReferenceBitmap primitive,
  ) {
    _forEachScaledSourcePixel(
      x: primitive.x,
      y: primitive.y,
      width: primitive.width,
      height: primitive.height,
      scale: scale,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      visit: (int sourceX, int sourceY, int deviceX, int deviceY) {
        final int sourceOffset = sourceY * primitive.rowStride + sourceX * 4;
        _blend(
          pixels,
          (deviceY * pixelWidth + deviceX) * 4,
          TerminalReferenceColor(
            (primitive._rgba[sourceOffset] << 24) |
                (primitive._rgba[sourceOffset + 1] << 16) |
                (primitive._rgba[sourceOffset + 2] << 8) |
                primitive._rgba[sourceOffset + 3],
          ),
          primitive.opacity,
        );
      },
    );
  }

  static void _drawSampledBitmap(
    Uint8List pixels,
    int pixelWidth,
    int pixelHeight,
    int scale,
    TerminalReferenceSampledBitmap primitive,
  ) {
    _forEachScaledSourcePixel(
      x: primitive.x,
      y: primitive.y,
      width: primitive.width,
      height: primitive.height,
      scale: scale,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      visit: (int destinationX, int destinationY, int deviceX, int deviceY) {
        final int sourceX =
            primitive.sourceX +
            destinationX * primitive.sourceWidth ~/ primitive.width;
        final int sourceY =
            primitive.sourceY +
            destinationY * primitive.sourceHeight ~/ primitive.height;
        final int sourceOffset =
            sourceY * primitive.source.rowStride + sourceX * 4;
        final Uint8List rgba = primitive.source._rgba;
        _blend(
          pixels,
          (deviceY * pixelWidth + deviceX) * 4,
          TerminalReferenceColor(
            (rgba[sourceOffset] << 24) |
                (rgba[sourceOffset + 1] << 16) |
                (rgba[sourceOffset + 2] << 8) |
                rgba[sourceOffset + 3],
          ),
          primitive.opacity,
        );
      },
    );
  }

  static void _forEachScaledSourcePixel({
    required int x,
    required int y,
    required int width,
    required int height,
    required int scale,
    required int pixelWidth,
    required int pixelHeight,
    required void Function(int sourceX, int sourceY, int deviceX, int deviceY)
    visit,
  }) {
    for (int sourceY = 0; sourceY < height; sourceY++) {
      final int deviceTop = (y + sourceY) * scale;
      for (int sourceX = 0; sourceX < width; sourceX++) {
        final int deviceLeft = (x + sourceX) * scale;
        for (int dy = 0; dy < scale; dy++) {
          final int deviceY = deviceTop + dy;
          if (deviceY < 0 || deviceY >= pixelHeight) {
            continue;
          }
          for (int dx = 0; dx < scale; dx++) {
            final int deviceX = deviceLeft + dx;
            if (deviceX >= 0 && deviceX < pixelWidth) {
              visit(sourceX, sourceY, deviceX, deviceY);
            }
          }
        }
      }
    }
  }

  static void _blend(
    Uint8List pixels,
    int offset,
    TerminalReferenceColor source,
    int coverage,
  ) {
    if (coverage == 0 || source.alpha == 0) {
      return;
    }
    final double sourceAlpha = (source.alpha / 255) * (coverage / 255);
    if (sourceAlpha == 0) {
      return;
    }
    final double destinationAlpha = pixels[offset + 3] / 255;
    final double inverseSourceAlpha = 1 - sourceAlpha;
    final double outputAlpha =
        sourceAlpha + destinationAlpha * inverseSourceAlpha;
    if (outputAlpha == 0) {
      pixels[offset] = 0;
      pixels[offset + 1] = 0;
      pixels[offset + 2] = 0;
      pixels[offset + 3] = 0;
      return;
    }
    pixels[offset] = _blendLinearSrgbChannel(
      source.red,
      pixels[offset],
      sourceAlpha,
      destinationAlpha,
      inverseSourceAlpha,
      outputAlpha,
    );
    pixels[offset + 1] = _blendLinearSrgbChannel(
      source.green,
      pixels[offset + 1],
      sourceAlpha,
      destinationAlpha,
      inverseSourceAlpha,
      outputAlpha,
    );
    pixels[offset + 2] = _blendLinearSrgbChannel(
      source.blue,
      pixels[offset + 2],
      sourceAlpha,
      destinationAlpha,
      inverseSourceAlpha,
      outputAlpha,
    );
    pixels[offset + 3] = (outputAlpha * 255).round().clamp(0, 255);
  }

  static int _blendLinearSrgbChannel(
    int source,
    int destination,
    double sourceAlpha,
    double destinationAlpha,
    double inverseSourceAlpha,
    double outputAlpha,
  ) {
    final double linear =
        (_decodeSrgbByte(source) * sourceAlpha +
            _decodeSrgbByte(destination) *
                destinationAlpha *
                inverseSourceAlpha) /
        outputAlpha;
    return _encodeSrgbByte(linear);
  }

  static double _decodeSrgbByte(int component) {
    final double encoded = component / 255;
    return encoded <= 0.04045
        ? encoded / 12.92
        : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _encodeSrgbByte(double linear) {
    final double clipped = linear.clamp(0, 1);
    final double encoded = clipped <= 0.0031308
        ? clipped * 12.92
        : 1.055 * math.pow(clipped, 1 / 2.4).toDouble() - 0.055;
    return (encoded * 255).round().clamp(0, 255);
  }
}

Uint8List _canonicalSrgbBitmap(
  List<int> rgba,
  TerminalRenderColorSpace inputColorSpace,
  int width,
  int height,
  int rowStride,
) {
  _validateSourceShape(width, height, rowStride, rgba.length, 4);
  final Uint8List canonical = _copyUint8List(rgba, 'rgba');
  if (inputColorSpace == TerminalRenderColorSpace.srgb) return canonical;
  if (canonical.length > TerminalRenderColorConverter.maximumBufferBytes) {
    throw StateError('Display P3 color buffer limit exceeded');
  }
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int offset = y * rowStride + x * 4;
      final int converted = TerminalRenderColorConverter.displayP3ToSrgbRgba(
        (canonical[offset] << 24) |
            (canonical[offset + 1] << 16) |
            (canonical[offset + 2] << 8) |
            canonical[offset + 3],
      );
      canonical[offset] = converted >>> 24;
      canonical[offset + 1] = converted >>> 16;
      canonical[offset + 2] = converted >>> 8;
      canonical[offset + 3] = converted;
    }
  }
  return canonical;
}

final class _ClippedDeviceRect {
  const _ClippedDeviceRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;
}

_ClippedDeviceRect _clipDeviceRect(
  int x,
  int y,
  int width,
  int height,
  int scale,
  int pixelWidth,
  int pixelHeight,
) {
  return _ClippedDeviceRect(
    (x * scale).clamp(0, pixelWidth),
    (y * scale).clamp(0, pixelHeight),
    ((x + width) * scale).clamp(0, pixelWidth),
    ((y + height) * scale).clamp(0, pixelHeight),
  );
}

void _validatePrimitive(
  TerminalReferencePrimitive primitive,
  int width,
  int height,
  TerminalReferenceRenderLimits limits,
) {
  if (primitive.width <= 0 || primitive.width > limits.maximumLogicalWidth) {
    throw RangeError.range(
      primitive.width,
      1,
      limits.maximumLogicalWidth,
      'primitive.width',
    );
  }
  if (primitive.height <= 0 || primitive.height > limits.maximumLogicalHeight) {
    throw RangeError.range(
      primitive.height,
      1,
      limits.maximumLogicalHeight,
      'primitive.height',
    );
  }
  if (primitive.x < -limits.maximumLogicalWidth ||
      primitive.x > width + limits.maximumLogicalWidth) {
    throw RangeError('primitive.x exceeds the bounded clipping domain');
  }
  if (primitive.y < -limits.maximumLogicalHeight ||
      primitive.y > height + limits.maximumLogicalHeight) {
    throw RangeError('primitive.y exceeds the bounded clipping domain');
  }
  switch (primitive) {
    case TerminalReferenceSolid():
      _validateColor(primitive.color, 'primitive.color');
    case TerminalReferenceMask():
      _validateColor(primitive.color, 'primitive.color');
    case TerminalReferenceBitmap():
      break;
    case TerminalReferenceSampledBitmap():
      break;
  }
}

void _validateImageDimensions(
  int width,
  int height,
  int scale,
  TerminalReferenceRenderLimits limits,
) {
  _requirePositive(width, 'width');
  _requirePositive(height, 'height');
  _requirePositive(scale, 'scale');
  if (scale > limits.maximumScale) {
    throw RangeError.range(scale, 1, limits.maximumScale, 'scale');
  }
  if (width % scale != 0 || height % scale != 0) {
    throw ArgumentError('image dimensions must be divisible by scale');
  }
  if (width ~/ scale > limits.maximumLogicalWidth ||
      height ~/ scale > limits.maximumLogicalHeight) {
    throw StateError('reference image logical dimensions exceed limits');
  }
  final int pixelCount = _checkedProduct(width, height, 'image pixel count');
  if (pixelCount > limits.maximumPixelCount) {
    throw StateError(
      'reference pixel limit exceeded: $pixelCount > '
      '${limits.maximumPixelCount}',
    );
  }
}

void _validateSourceShape(
  int width,
  int height,
  int rowStride,
  int byteLength,
  int bytesPerPixel,
) {
  _requirePositive(width, 'width');
  _requirePositive(height, 'height');
  final int minimumStride = _checkedProduct(
    width,
    bytesPerPixel,
    'minimum row stride',
  );
  if (rowStride < minimumStride) {
    throw RangeError.range(rowStride, minimumStride, null, 'rowStride');
  }
  final int expectedBytes = _checkedProduct(
    rowStride,
    height,
    'source byte count',
  );
  if (byteLength != expectedBytes) {
    throw ArgumentError.value(
      byteLength,
      'source.length',
      'must equal rowStride * height ($expectedBytes)',
    );
  }
}

int _checkedProduct(int left, int right, String description) {
  if (left < 0 || right < 0) {
    throw RangeError('$description operands must be nonnegative');
  }
  final int result = left * right;
  if (left != 0 && result ~/ left != right) {
    throw StateError('$description overflow');
  }
  return result;
}

void _requirePositive(int value, String name) {
  if (value <= 0) {
    throw RangeError.value(value, name, 'must be positive');
  }
}

void _requireNonnegative(int value, String name) {
  if (value < 0) {
    throw RangeError.value(value, name, 'must be nonnegative');
  }
}

void _validateColor(TerminalReferenceColor color, String name) {
  if (color.rgba < 0 || color.rgba > 0xffffffff) {
    throw RangeError.range(color.rgba, 0, 0xffffffff, name);
  }
}

Uint8List _copyUint8List(List<int> source, String name) {
  final Uint8List result = Uint8List(source.length);
  for (int index = 0; index < source.length; index++) {
    final int value = source[index];
    if (value < 0 || value > 255) {
      throw RangeError.range(value, 0, 255, '$name[$index]');
    }
    result[index] = value;
  }
  return result;
}
