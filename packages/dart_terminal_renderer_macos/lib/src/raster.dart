part of 'font_catalog.dart';

enum TerminalGlyphPixelFormat { alpha8, rgba8Straight }

abstract final class TerminalRasterGlyphFlags {
  static const int color = 1 << 0;
  static const int missing = 1 << 1;
  static const int knownMask = color | missing;
}

final class TerminalGlyphRasterRequest {
  const TerminalGlyphRasterRequest({
    required this.faceId,
    required this.glyphId,
  });

  final int faceId;
  final int glyphId;

  @override
  int get hashCode => Object.hash(faceId, glyphId);

  @override
  bool operator ==(Object other) =>
      other is TerminalGlyphRasterRequest &&
      faceId == other.faceId &&
      glyphId == other.glyphId;
}

final class TerminalRasterizedGlyph {
  TerminalRasterizedGlyph._({
    required this.faceId,
    required this.glyphId,
    required this.format,
    required this.flags,
    required this.originX,
    required this.originY,
    required this.width,
    required this.height,
    required this.rowStride,
    required Uint8List pixels,
  }) : _pixels = pixels;

  final int faceId;
  final int glyphId;
  final TerminalGlyphPixelFormat format;
  final int flags;

  /// Left device-pixel bearing relative to the shaped glyph position.
  final int originX;

  /// Top device-pixel bearing above the CoreText baseline.
  final int originY;

  final int width;
  final int height;
  final int rowStride;
  final Uint8List _pixels;

  int get byteLength => _pixels.length;
  bool get isColor => flags & TerminalRasterGlyphFlags.color != 0;
  bool get isMissing => flags & TerminalRasterGlyphFlags.missing != 0;
  bool get isEmpty => width == 0;

  Uint8List copyPixels() => Uint8List.fromList(_pixels);
}

final class TerminalGlyphRasterBatch {
  TerminalGlyphRasterBatch._({
    required this.catalogGeneration,
    required this.scale16_16,
    required this.packedByteLength,
    required this.pixelByteLength,
    required List<TerminalRasterizedGlyph> glyphs,
  }) : glyphs = List<TerminalRasterizedGlyph>.unmodifiable(glyphs);

  final int catalogGeneration;
  final int scale16_16;
  final int packedByteLength;
  final int pixelByteLength;
  final List<TerminalRasterizedGlyph> glyphs;

  double get scale => scale16_16 / 65536.0;
}

/// Strict decoder for the public version-one raster buffer.
abstract final class TerminalRasterBufferV1 {
  static const int maximumGlyphs = 4096;
  static const int maximumDimension = 4096;
  static const int maximumOutputBytes = 64 * 1024 * 1024;

  static int scaleToFixed(double scale) {
    if (!scale.isFinite || scale < 0.5 || scale > 4) {
      throw RangeError.value(scale, 'scale', 'must be between 0.5 and 4');
    }
    return (scale * 65536).round();
  }

  static TerminalGlyphRasterBatch decode(
    Uint8List bytes, {
    required List<TerminalGlyphRasterRequest> requests,
    required int catalogGeneration,
    required int scale16_16,
  }) {
    _validateRasterRequests(requests);
    if (scale16_16 < 1 << 15 || scale16_16 > 4 << 16) {
      throw const FormatException('invalid expected raster scale');
    }
    if (bytes.length < _rasterHeaderSize || bytes.length > maximumOutputBytes) {
      throw const FormatException('invalid packed raster buffer length');
    }
    final ByteData data = ByteData.sublistView(bytes);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    final int magic = u32(0);
    final int version = u32(4);
    final int headerSize = u32(8);
    final int totalSize = u32(12);
    final int generation = data.getUint64(16, Endian.little);
    final int encodedScale = u32(24);
    final int glyphCount = u32(28);
    final int recordsOffset = u32(32);
    final int pixelsOffset = u32(36);
    final int pixelBytes = u32(40);
    if (magic != _rasterBufferMagic ||
        version != _rasterBufferVersion ||
        headerSize != _rasterHeaderSize ||
        totalSize != bytes.length ||
        generation != catalogGeneration ||
        encodedScale != scale16_16 ||
        glyphCount != requests.length ||
        glyphCount == 0 ||
        glyphCount > maximumGlyphs ||
        recordsOffset != _rasterHeaderSize ||
        pixelsOffset != _rasterHeaderSize + glyphCount * _rasterGlyphSize ||
        pixelBytes != totalSize - pixelsOffset ||
        u32(44) != 0 ||
        u32(48) != 0 ||
        u32(52) != 0 ||
        u32(56) != 0 ||
        u32(60) != 0) {
      throw const FormatException('invalid packed raster header');
    }
    final List<TerminalRasterizedGlyph> glyphs = <TerminalRasterizedGlyph>[];
    var pixelCursor = pixelsOffset;
    for (int index = 0; index < glyphCount; index++) {
      final int offset = recordsOffset + index * _rasterGlyphSize;
      final TerminalGlyphRasterRequest request = requests[index];
      final int faceId = u32(offset);
      final int glyphId = u32(offset + 4);
      final int encodedFormat = u32(offset + 8);
      final int flags = u32(offset + 12);
      final int originX = data.getInt32(offset + 16, Endian.little);
      final int originY = data.getInt32(offset + 20, Endian.little);
      final int width = u32(offset + 24);
      final int height = u32(offset + 28);
      final int rowStride = u32(offset + 32);
      final int recordPixelsOffset = u32(offset + 36);
      final int pixelLength = u32(offset + 40);
      final TerminalGlyphPixelFormat format;
      if (encodedFormat == 1) {
        format = TerminalGlyphPixelFormat.alpha8;
      } else if (encodedFormat == 2) {
        format = TerminalGlyphPixelFormat.rgba8Straight;
      } else {
        throw const FormatException('invalid packed raster pixel format');
      }
      final int bytesPerPixel = format == TerminalGlyphPixelFormat.alpha8
          ? 1
          : 4;
      final bool color = flags & TerminalRasterGlyphFlags.color != 0;
      final bool missing = flags & TerminalRasterGlyphFlags.missing != 0;
      final bool empty = width == 0 || height == 0;
      if (faceId != request.faceId ||
          glyphId != request.glyphId ||
          flags & ~TerminalRasterGlyphFlags.knownMask != 0 ||
          color != (format == TerminalGlyphPixelFormat.rgba8Straight) ||
          missing != (glyphId == 0) ||
          (width == 0) != (height == 0) ||
          width > maximumDimension ||
          height > maximumDimension ||
          recordPixelsOffset != pixelCursor ||
          u32(offset + 44) != 0) {
        throw const FormatException('invalid packed raster glyph record');
      }
      if (empty) {
        if (originX != 0 ||
            originY != 0 ||
            rowStride != 0 ||
            pixelLength != 0) {
          throw const FormatException('invalid empty raster glyph');
        }
      } else if (rowStride != width * bytesPerPixel ||
          pixelLength != rowStride * height ||
          pixelCursor + pixelLength > totalSize) {
        throw const FormatException('invalid raster glyph pixel extent');
      }
      final Uint8List pixels = Uint8List.fromList(
        bytes.sublist(pixelCursor, pixelCursor + pixelLength),
      );
      if (format == TerminalGlyphPixelFormat.rgba8Straight) {
        for (int pixel = 0; pixel < pixels.length; pixel += 4) {
          if (pixels[pixel + 3] == 0 &&
              (pixels[pixel] != 0 ||
                  pixels[pixel + 1] != 0 ||
                  pixels[pixel + 2] != 0)) {
            throw const FormatException(
              'transparent raster pixel has nonzero straight RGB',
            );
          }
        }
      }
      glyphs.add(
        TerminalRasterizedGlyph._(
          faceId: faceId,
          glyphId: glyphId,
          format: format,
          flags: flags,
          originX: originX,
          originY: originY,
          width: width,
          height: height,
          rowStride: rowStride,
          pixels: pixels,
        ),
      );
      pixelCursor += pixelLength;
    }
    if (pixelCursor != totalSize) {
      throw const FormatException(
        'raster pixels contain a gap or trailing data',
      );
    }
    return TerminalGlyphRasterBatch._(
      catalogGeneration: generation,
      scale16_16: encodedScale,
      packedByteLength: totalSize,
      pixelByteLength: pixelBytes,
      glyphs: glyphs,
    );
  }
}

extension TerminalFontCatalogRaster on TerminalFontCatalog {
  TerminalGlyphRasterBatch rasterize(
    Iterable<TerminalGlyphRasterRequest> requests, {
    double scale = 1,
  }) {
    final int handle = _liveHandle();
    final List<TerminalGlyphRasterRequest> retained = List.of(requests);
    _validateRasterRequests(retained);
    final int scale16_16 = TerminalRasterBufferV1.scaleToFixed(scale);
    final Arena arena = Arena();
    try {
      final Pointer<_RasterRequestV1> nativeRequests = arena<_RasterRequestV1>(
        retained.length,
      );
      for (int index = 0; index < retained.length; index++) {
        nativeRequests[index]
          ..faceId = retained[index].faceId
          ..glyphId = retained[index].glyphId;
      }
      final Pointer<Uint32> required = arena<Uint32>();
      Pointer<Uint8> output = nullptr;
      var capacity = 0;
      for (int attempt = 0; attempt < 3; attempt++) {
        required.value = 0;
        final int status = _fontCatalogRasterize(
          handle,
          scale16_16,
          nativeRequests,
          retained.length,
          output,
          capacity,
          required,
        );
        if (status == _statusBufferTooSmall) {
          final int nextCapacity = required.value;
          if (nextCapacity <= capacity ||
              nextCapacity < _rasterHeaderSize ||
              nextCapacity > TerminalRasterBufferV1.maximumOutputBytes) {
            throw const FormatException('invalid native raster buffer size');
          }
          output = arena<Uint8>(nextCapacity);
          capacity = nextCapacity;
          continue;
        }
        _checkStatus(status, 'font catalog rasterize');
        if (output == nullptr ||
            required.value == 0 ||
            required.value > capacity) {
          throw const FormatException('invalid native raster completion');
        }
        return TerminalRasterBufferV1.decode(
          Uint8List.fromList(output.asTypedList(required.value)),
          requests: retained,
          catalogGeneration: generation,
          scale16_16: scale16_16,
        );
      }
      throw StateError('native raster size changed repeatedly');
    } finally {
      arena.releaseAll();
    }
  }

  TerminalGlyphRasterBatch rasterizeShaped(
    TerminalShapedText shaped, {
    double scale = 1,
  }) {
    if (shaped.catalogGeneration != generation) {
      throw StateError('shaped text belongs to another catalog generation');
    }
    final LinkedHashSet<TerminalGlyphRasterRequest> requests =
        LinkedHashSet<TerminalGlyphRasterRequest>();
    for (final TerminalShapedGlyph glyph in shaped.glyphs) {
      requests.add(
        TerminalGlyphRasterRequest(
          faceId: glyph.faceId,
          glyphId: glyph.glyphId,
        ),
      );
    }
    return rasterize(requests, scale: scale);
  }
}

void _validateRasterRequests(List<TerminalGlyphRasterRequest> requests) {
  if (requests.isEmpty ||
      requests.length > TerminalRasterBufferV1.maximumGlyphs) {
    throw ArgumentError.value(
      requests.length,
      'requests.length',
      'must be between 1 and ${TerminalRasterBufferV1.maximumGlyphs}',
    );
  }
  final Set<TerminalGlyphRasterRequest> unique = <TerminalGlyphRasterRequest>{};
  for (final TerminalGlyphRasterRequest request in requests) {
    if (request.faceId <= 0 ||
        request.faceId > 0xffffffff ||
        request.glyphId < 0 ||
        request.glyphId > 0xffff ||
        !unique.add(request)) {
      throw ArgumentError.value(
        request,
        'requests',
        'invalid or duplicate key',
      );
    }
  }
}

final class _RasterRequestV1 extends Struct {
  @Uint32()
  external int faceId;

  @Uint32()
  external int glyphId;
}

const int _rasterBufferMagic = 0x47525444;
const int _rasterBufferVersion = 1;
const int _rasterHeaderSize = 64;
const int _rasterGlyphSize = 48;

@Native<
  Int32 Function(
    Uint64,
    Uint32,
    Pointer<_RasterRequestV1>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
  )
>(symbol: 'dtr_font_catalog_rasterize', assetId: _assetId)
external int _fontCatalogRasterize(
  int handle,
  int scale16_16,
  Pointer<_RasterRequestV1> requests,
  int requestCount,
  Pointer<Uint8> output,
  int outputCapacity,
  Pointer<Uint32> outputRequired,
);
