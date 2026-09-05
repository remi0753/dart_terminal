import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'frame_scheduler.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';

/// One strict immutable observation across Dart and native render ownership.
final class TerminalRendererMetricsSnapshot {
  const TerminalRendererMetricsSnapshot._({
    required this.rendererGeneration,
    required this.atlasResourceGeneration,
    required this.pendingAtlasUploadCount,
    required this.pinnedSubmissionCount,
    required this.frames,
    required this.atlas,
    required this.native,
  });

  static TerminalRendererMetricsSnapshot capture<Frame>({
    required TerminalNewestFrameScheduler<Frame> scheduler,
    required TerminalGlyphAtlasMetalBridge bridge,
  }) {
    if (bridge.isAbandoned || !bridge.isSynchronized) {
      throw StateError('renderer metrics require a synchronized live bridge');
    }
    final TerminalGlyphAtlas atlas = bridge.atlas;
    final TerminalMetalRendererState native = bridge.renderer.state();
    if (native.rendererGeneration != bridge.renderer.generation ||
        bridge.nativeAtlasGeneration != atlas.resourceGeneration ||
        bridge.pendingUploadCount != 0 ||
        atlas.pendingUploadPageCount != 0) {
      throw StateError('renderer metrics span inconsistent resource domains');
    }
    return TerminalRendererMetricsSnapshot._(
      rendererGeneration: native.rendererGeneration,
      atlasResourceGeneration: atlas.resourceGeneration,
      pendingAtlasUploadCount: bridge.pendingUploadCount,
      pinnedSubmissionCount: bridge.pinnedSubmissionCount,
      frames: scheduler.metrics,
      atlas: atlas.metrics,
      native: native,
    );
  }

  final int rendererGeneration;
  final int atlasResourceGeneration;
  final int pendingAtlasUploadCount;
  final int pinnedSubmissionCount;
  final TerminalFrameSchedulerMetrics frames;
  final TerminalGlyphAtlasMetrics atlas;
  final TerminalMetalRendererState native;
}
