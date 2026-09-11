import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runMetalPipelineTests();

void runMetalPipelineTests() {
  for (final int scale in <int>[1, 2]) {
    _testGpuAgainstReferenceGolden(scale);
  }
  _testEmptySameDomainResetSynchronization();
  _testKittyImageTileSurvivesRendererReplacement();
  _testBridgeLimitValidation();
}

void _testKittyImageTileSurvivesRendererReplacement() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 1,
      maximumRetainedBytes: 8 * 8 * 4,
      gutter: 0,
    ),
  );
  final TerminalGlyphAtlasEntry image = atlas.ingestKittyImageTile(
    key: const TerminalKittyImageAtlasKey(
      screenKindIndex: 0,
      imageId: 1,
      imageResourceGeneration: 1,
      placementGeneration: 1,
      sourceX: 0,
      sourceY: 0,
      sourceWidth: 1,
      sourceHeight: 1,
      destinationX: 0,
      destinationY: 0,
      destinationWidth: 1,
      destinationHeight: 1,
      tileX: 0,
      tileY: 0,
      tileWidth: 1,
      tileHeight: 1,
      scale16_16: 1 << 16,
    ),
    rgba: Uint8List.fromList(const <int>[0x20, 0x40, 0x80, 0xff]),
  );
  final TerminalMetalRenderer first = _openSinglePixelRenderer();
  try {
    final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
      atlas: atlas,
      renderer: first,
    );
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized,
      'first renderer accepts the Kitty image atlas page',
    );
    bridge.abandonRenderer();
  } finally {
    first.dispose();
  }

  final TerminalMetalRenderer replacement = _openSinglePixelRenderer();
  try {
    final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
      atlas: atlas,
      renderer: replacement,
    );
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized,
      'replacement renderer receives a complete Kitty image atlas snapshot',
    );
    final TerminalMetalInstance instance = bridge.glyphInstance(
      image,
      x: 0,
      y: 0,
    )!;
    final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
      renderer: replacement,
      frameGeneration: 1,
      atlasGeneration: bridge.nativeAtlasGeneration,
      viewportWidth: 1,
      viewportHeight: 1,
      scale16_16: 1 << 16,
      backgroundRgba: 0x000000ff,
      instances: <TerminalMetalInstance>[instance],
    );
    final Uint8List pixels = replacement.renderRgba(frame);
    _expect(
      pixels.length == 4 &&
          pixels[0] == 0x20 &&
          pixels[1] == 0x40 &&
          pixels[2] == 0x80 &&
          pixels[3] == 0xff,
      'replacement renderer draws the retained Kitty image tile',
    );
  } finally {
    replacement.dispose();
  }
}

TerminalMetalRenderer _openSinglePixelRenderer() => TerminalMetalRenderer.open(
  config: const TerminalMetalRendererConfig(
    maximumViewportWidth: 1,
    maximumViewportHeight: 1,
    maximumInstances: 1,
    atlasWidth: 8,
    atlasHeight: 8,
    maximumAlphaPages: 1,
    maximumColorPages: 1,
  ),
);

void _testEmptySameDomainResetSynchronization() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 1,
      maximumRetainedBytes: 8 * 8 * 4,
      gutter: 0,
    ),
  );
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: const TerminalMetalRendererConfig(
      maximumViewportWidth: 1,
      maximumViewportHeight: 1,
      maximumInstances: 1,
      atlasWidth: 8,
      atlasHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
    ),
  );
  try {
    final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
      atlas: atlas,
      renderer: renderer,
    );
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized &&
          bridge.nativeAtlasGeneration == 1,
      'empty first attachment publishes a native atlas generation',
    );
    atlas.reset(catalogGeneration: 1, scale: 1);
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized &&
          bridge.isSynchronized &&
          bridge.nativeAtlasGeneration == atlas.resourceGeneration,
      'empty same-domain reset advances native atlas without a fake glyph',
    );
  } finally {
    renderer.dispose();
  }
}

void _testGpuAgainstReferenceGolden(int scale) {
  final int atlasSide = 8 * scale;
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    scale: scale.toDouble(),
    limits: TerminalGlyphAtlasLimits(
      pageWidth: atlasSide,
      pageHeight: atlasSide,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 8,
      maximumRetainedBytes: atlasSide * atlasSide * 5,
      gutter: 1,
    ),
  );
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: TerminalMetalRendererConfig(
      maximumViewportWidth: 3 * scale,
      maximumViewportHeight: 2 * scale,
      maximumInstances: 6,
      atlasWidth: atlasSide,
      atlasHeight: atlasSide,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
    ),
  );
  try {
    final TerminalGlyphAtlasEntry alpha = atlas
        .ingest(
          _rasterBatch(
            faceId: 1,
            glyphId: 10,
            scale: scale,
            color: false,
            width: 2 * scale,
            height: 2 * scale,
            pixels: _expandPixels(
              const <int>[0, 255, 128, 64],
              width: 2,
              height: 2,
              bytesPerPixel: 1,
              scale: scale,
            ),
          ),
        )
        .single;
    final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
      atlas: atlas,
      renderer: renderer,
    );
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized &&
          bridge.pendingUploadCount == 0,
      'initial alpha atlas upload is synchronized at ${scale}x',
    );
    final int alphaGeneration = bridge.nativeAtlasGeneration;
    final TerminalGlyphAtlasEntry color = atlas
        .ingest(
          _rasterBatch(
            faceId: 2,
            glyphId: 20,
            scale: scale,
            color: true,
            width: scale,
            height: scale,
            pixels: _expandPixels(
              const <int>[255, 0, 255, 128],
              width: 1,
              height: 1,
              bytesPerPixel: 4,
              scale: scale,
            ),
          ),
        )
        .single;
    _expectThrows(
      () => bridge.glyphInstance(alpha, x: 0, y: 0),
      'encoding is blocked while an incremental upload is dirty',
    );
    _expect(
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized &&
          bridge.nativeAtlasGeneration > alphaGeneration &&
          bridge.pendingUploadCount == 0 &&
          atlas.pendingUploadPageCount == 0,
      'incremental color upload advances the complete atlas snapshot',
    );
    final TerminalMetalInstance alphaInstance = bridge.glyphInstance(
      alpha,
      x: 0,
      y: 0,
    )!;
    final TerminalMetalInstance colorInstance = bridge.glyphInstance(
      color,
      x: 2 * scale,
      y: 0,
    )!;
    final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
      renderer: renderer,
      frameGeneration: 1,
      atlasGeneration: bridge.nativeAtlasGeneration,
      viewportWidth: 3 * scale,
      viewportHeight: 2 * scale,
      scale16_16: scale << 16,
      backgroundRgba: 0x102030ff,
      instances: <TerminalMetalInstance>[
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.cellBackground,
          x: 0,
          y: 0,
          width: 2 * scale,
          height: scale,
          colorRgba: 0x804020ff,
        ),
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.selection,
          x: scale,
          y: 0,
          width: 2 * scale,
          height: 2 * scale,
          colorRgba: 0x00ff0080,
        ),
        alphaInstance,
        colorInstance,
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.decoration,
          x: 0,
          y: scale,
          width: 3 * scale,
          height: scale,
          colorRgba: 0x0000ff40,
        ),
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.cursor,
          x: scale,
          y: scale,
          width: scale,
          height: scale,
          colorRgba: 0xffff00c0,
        ),
      ],
    );
    final TerminalReferenceImage expected = TerminalGoldenImageCodec.decode(
      File('test/goldens/reference/layers-${scale}x.dtgi').readAsBytesSync(),
    );
    final Uint8List actual = renderer.renderRgba(frame);
    _expectGpuNear(
      expected.copyRgbaBytes(),
      actual,
      width: expected.width,
      scale: scale,
    );
  } finally {
    renderer.dispose();
  }
}

void _testBridgeLimitValidation() {
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: const TerminalMetalRendererConfig(
      maximumViewportWidth: 1,
      maximumViewportHeight: 1,
      maximumInstances: 1,
      atlasWidth: 8,
      atlasHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
    ),
  );
  try {
    final TerminalGlyphAtlas wrongSize = TerminalGlyphAtlas(
      catalogGeneration: 1,
      limits: const TerminalGlyphAtlasLimits(
        pageWidth: 9,
        pageHeight: 8,
        maximumAlphaPages: 1,
        maximumColorPages: 1,
        maximumEntries: 1,
        maximumRetainedBytes: 9 * 8 * 4,
      ),
    );
    _expectThrows(
      () => TerminalGlyphAtlasMetalBridge(atlas: wrongSize, renderer: renderer),
      'atlas and renderer dimensions must match exactly',
    );
  } finally {
    renderer.dispose();
  }
}

TerminalGlyphRasterBatch _rasterBatch({
  required int faceId,
  required int glyphId,
  required int scale,
  required bool color,
  required int width,
  required int height,
  required Uint8List pixels,
}) {
  const int headerBytes = 64;
  const int recordBytes = 48;
  final int rowStride = width * (color ? 4 : 1);
  final Uint8List bytes = Uint8List(headerBytes + recordBytes + pixels.length);
  final ByteData data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u32(0, 0x47525444);
  u32(4, 1);
  u32(8, headerBytes);
  u32(12, bytes.length);
  data.setUint64(16, 1, Endian.little);
  u32(24, scale << 16);
  u32(28, 1);
  u32(32, headerBytes);
  u32(36, headerBytes + recordBytes);
  u32(40, pixels.length);
  u32(headerBytes, faceId);
  u32(headerBytes + 4, glyphId);
  u32(headerBytes + 8, color ? 2 : 1);
  u32(headerBytes + 12, color ? TerminalRasterGlyphFlags.color : 0);
  data.setInt32(headerBytes + 20, height, Endian.little);
  u32(headerBytes + 24, width);
  u32(headerBytes + 28, height);
  u32(headerBytes + 32, rowStride);
  u32(headerBytes + 36, headerBytes + recordBytes);
  u32(headerBytes + 40, pixels.length);
  bytes.setAll(headerBytes + recordBytes, pixels);
  return TerminalRasterBufferV1.decode(
    bytes,
    requests: <TerminalGlyphRasterRequest>[
      TerminalGlyphRasterRequest(faceId: faceId, glyphId: glyphId),
    ],
    catalogGeneration: 1,
    scale16_16: scale << 16,
  );
}

Uint8List _expandPixels(
  List<int> source, {
  required int width,
  required int height,
  required int bytesPerPixel,
  required int scale,
}) {
  final int outputWidth = width * scale;
  final Uint8List output = Uint8List(
    outputWidth * height * scale * bytesPerPixel,
  );
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      for (int dy = 0; dy < scale; dy++) {
        for (int dx = 0; dx < scale; dx++) {
          final int sourceOffset = (y * width + x) * bytesPerPixel;
          final int destination =
              (((y * scale + dy) * outputWidth) + x * scale + dx) *
              bytesPerPixel;
          output.setRange(
            destination,
            destination + bytesPerPixel,
            source,
            sourceOffset,
          );
        }
      }
    }
  }
  return output;
}

void _expectGpuNear(
  Uint8List expected,
  Uint8List actual, {
  required int width,
  required int scale,
}) {
  _expect(
    expected.length == actual.length,
    'GPU output byte length at ${scale}x',
  );
  for (int offset = 0; offset < expected.length; offset++) {
    if ((expected[offset] - actual[offset]).abs() > 1) {
      final int pixel = offset ~/ 4;
      throw StateError(
        'GPU/reference ${scale}x mismatch at '
        '(${pixel % width}, ${pixel ~/ width}) channel ${offset % 4}: '
        'expected ${expected[offset]}, actual ${actual[offset]}',
      );
    }
  }
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('Metal pipeline test failed: $description');
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('Metal pipeline test failed: $description');
}
