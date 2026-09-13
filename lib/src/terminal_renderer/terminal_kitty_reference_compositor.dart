import '../terminal_core/terminal_screen_set.dart';
import 'reference_renderer.dart';

/// Deterministic static-Kitty image compositor for renderer conformance tests.
abstract final class TerminalKittyReferenceCompositor {
  static TerminalReferenceImage render({
    required TerminalKittyViewportSnapshot snapshot,
    int scale = 1,
    TerminalReferenceColor background = TerminalReferenceColor.transparent,
    Iterable<TerminalReferencePrimitive> textPrimitives =
        const <TerminalReferencePrimitive>[],
    TerminalReferenceRenderLimits limits =
        const TerminalReferenceRenderLimits(),
  }) {
    limits.validate();
    if (snapshot.viewportWidth <= 0 || snapshot.viewportHeight <= 0) {
      throw StateError('Kitty viewport has no authoritative cell geometry');
    }
    if (snapshot.viewportWidth > limits.maximumLogicalWidth ||
        snapshot.viewportHeight > limits.maximumLogicalHeight ||
        scale <= 0 ||
        scale > limits.maximumScale ||
        snapshot.viewportWidth * snapshot.viewportHeight * scale * scale >
            limits.maximumPixelCount) {
      throw StateError('Kitty viewport exceeds reference render limits');
    }
    if (snapshot.images.length > 64 || snapshot.placements.length > 256) {
      throw StateError('Kitty viewport exceeds product image limits');
    }
    var sourceBytes = 0;
    for (final TerminalKittyViewportImage image in snapshot.images) {
      sourceBytes += image.byteLength;
      if (sourceBytes > limits.maximumSourceBytes) {
        throw StateError('Kitty viewport exceeds reference source-byte limit');
      }
    }
    final Map<(int, int), TerminalReferenceBitmapSource> sources =
        <(int, int), TerminalReferenceBitmapSource>{};
    for (final TerminalKittyViewportImage image in snapshot.images) {
      final (int, int) key = (image.imageId, image.resourceGeneration);
      if (sources.containsKey(key)) {
        throw StateError('duplicate Kitty viewport image generation');
      }
      sources[key] = TerminalReferenceBitmapSource(
        width: image.width,
        height: image.height,
        rowStride: image.width * 4,
        rgba: image.copyRgba(),
      );
    }

    Iterable<TerminalReferencePrimitive> scene() sync* {
      yield* textPrimitives;
      for (final TerminalKittyViewportPlacement placement
          in snapshot.placements) {
        final TerminalReferenceBitmapSource? source =
            sources[(placement.imageId, placement.imageResourceGeneration)];
        if (source == null) {
          throw StateError('Kitty placement refers to an absent resource');
        }
        yield TerminalReferenceSampledBitmap(
          layer: switch (placement.layer) {
            TerminalKittyImageLayer.belowBackground =>
              TerminalReferenceLayer.imageBelowBackground,
            TerminalKittyImageLayer.belowText =>
              TerminalReferenceLayer.imageBelowText,
            TerminalKittyImageLayer.aboveText =>
              TerminalReferenceLayer.imageAboveText,
          },
          x: placement.destinationX,
          y: placement.destinationY,
          width: placement.destinationWidth,
          height: placement.destinationHeight,
          source: source,
          sourceX: placement.source.x,
          sourceY: placement.source.y,
          sourceWidth: placement.source.width,
          sourceHeight: placement.source.height,
        );
      }
    }

    return TerminalReferenceRenderer.render(
      width: snapshot.viewportWidth,
      height: snapshot.viewportHeight,
      scale: scale,
      background: background,
      primitives: scene(),
      limits: limits,
    );
  }
}
