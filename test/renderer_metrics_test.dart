import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runRendererMetricsTests();

void runRendererMetricsTests() {
  _testStrictAggregateSnapshot();
}

void _testStrictAggregateSnapshot() {
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
      bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized,
      'aggregate fixture synchronizes an empty native atlas',
    );
    final TerminalNewestFrameScheduler<int> scheduler =
        TerminalNewestFrameScheduler<int>(
          model: TerminalDamageRenderModel(),
          timingClock: _clock(<int>[10, 12, 20, 23]),
          buildFrame: (
            TerminalDamageRenderModel model, {
            required int modelRevision,
            required int frameGeneration,
            required TerminalFramePresentation presentation,
          }) => frameGeneration,
          submitFrame:
              (
                int frame, {
                required int modelRevision,
                required int frameGeneration,
              }) => TerminalFrameSubmissionOutcome.accepted(
                frameGeneration: frameGeneration,
                submissionToken: 1,
              ),
        );
    final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
    final TerminalDamagePacket packet = TerminalDamageCodec.capture(
      screen,
      damageGeneration: 1,
      requiredResourceGeneration: atlas.resourceGeneration,
    )!;
    scheduler.applyDamage(
      TerminalDamageCodec.decode(packet.copyBytes()),
      availableResourceGeneration: atlas.resourceGeneration,
      monotonicMicros: 0,
    );
    scheduler.submitNewest();
    atlas.lookup(
      const TerminalGlyphAtlasKey(
        catalogGeneration: 1,
        faceId: 1,
        glyphId: 1,
        scale16_16: 1 << 16,
      ),
    );

    final TerminalRendererMetricsSnapshot snapshot =
        TerminalRendererMetricsSnapshot.capture<int>(
          scheduler: scheduler,
          bridge: bridge,
        );
    _expect(
      snapshot.rendererGeneration == renderer.generation &&
          snapshot.atlasResourceGeneration == atlas.resourceGeneration &&
          snapshot.pendingAtlasUploadCount == 0 &&
          snapshot.pinnedSubmissionCount == 0 &&
          snapshot.frames.buildCount == 1 &&
          snapshot.frames.buildTotalMicroseconds == 2 &&
          snapshot.frames.submissionCount == 1 &&
          snapshot.frames.submissionTotalMicroseconds == 3 &&
          snapshot.atlas.hitCount == 0 &&
          snapshot.atlas.missCount == 1 &&
          snapshot.atlas.hitRate == 0.0 &&
          snapshot.native.acceptedAtlasUploadCount == 0 &&
          snapshot.native.acceptedAtlasUploadBytes == 0 &&
          snapshot.native.gpuTimingSampleCount == 0,
      'aggregate copies consistent scheduler/atlas/native generations once',
    );
    atlas.lookup(
      const TerminalGlyphAtlasKey(
        catalogGeneration: 1,
        faceId: 1,
        glyphId: 2,
        scale16_16: 1 << 16,
      ),
    );
    _expect(
      snapshot.atlas.missCount == 1,
      'aggregate retains an immutable atlas metrics snapshot',
    );
    bridge.abandonRenderer();
    _expectState(
      () => TerminalRendererMetricsSnapshot.capture<int>(
        scheduler: scheduler,
        bridge: bridge,
      ),
      'aggregate rejects an abandoned renderer ownership domain',
    );
  } finally {
    renderer.dispose();
  }
}

TerminalFrameTimingClock _clock(List<int> values) {
  var index = 0;
  return () {
    if (index >= values.length) throw StateError('metric clock exhausted');
    return values[index++];
  };
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Renderer metrics test failed: $description');
  }
}

void _expectState(void Function() action, String description) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('Renderer metrics test failed: $description');
}
