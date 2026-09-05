import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runRenderResourceRebuilderTests();

void runRenderResourceRebuilderTests() {
  _testResizeScaleAndFontPublication();
  _testLivePinBackpressureRetainsPlan();
}

void _testResizeScaleAndFontPublication() {
  final TerminalScreen initialScreen = TerminalScreen(rows: 2, columns: 3)
    ..setNarrowCell(0, 0, 0x41);
  final TerminalDamageOutbox outbox = _initializedOutbox(initialScreen);
  final TerminalRenderFontConfiguration initialConfig =
      TerminalRenderFontConfiguration(generation: 1);
  final TerminalFontCatalog initialCatalog = TerminalFontCatalog.open(
    family: initialConfig.family,
    pointSize: initialConfig.pointSize,
  );
  final TerminalShapingCache initialCache = TerminalShapingCache(
    initialCatalog,
    maximumEntries: 8,
    maximumBytes: 4 * 1024 * 1024,
  );
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: initialCatalog.generation,
    limits: _atlasLimits,
  );
  final List<TerminalGlyphAtlasEntry> initialEntries = _warmAtlas(
    initialCatalog,
    initialCache,
    atlas,
  );
  final TerminalGlyphAtlasEntry initialEntry = initialEntries.single;
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: _rendererConfig,
  );
  final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
    atlas: atlas,
    renderer: renderer,
  );
  _expect(
    bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized &&
        bridge.nativeAtlasGeneration == atlas.resourceGeneration,
    'initial real CoreText atlas is published to native Metal',
  );
  final TerminalRenderRebuildCoordinator coordinator =
      TerminalRenderRebuildCoordinator(
        damageOutbox: outbox,
        initialTarget: _target(initialScreen),
        initialResources: TerminalRenderResourceGenerations(
          catalogGeneration: initialCatalog.generation,
          atlasGeneration: atlas.resourceGeneration,
        ),
      );
  final TerminalRenderResourceRebuilder rebuilder =
      TerminalRenderResourceRebuilder(
        coordinator: coordinator,
        bridge: bridge,
        catalog: initialCatalog,
        shapingCache: initialCache,
        fontConfiguration: initialConfig,
      );
  try {
    final int initialAtlasGeneration = atlas.resourceGeneration;
    final TerminalScreen resizedScreen = initialScreen.resized(
      rows: 4,
      columns: 6,
    );
    _expect(
      rebuilder.request(
            _target(resizedScreen, viewportWidth: 128, viewportHeight: 96),
          ) &&
          outbox.isPausedForFullRebuild &&
          rebuilder.tryCreateDamageTransfer() == null,
      'resize pauses damage until its matching resources are published',
    );
    var unexpectedWarmup = false;
    final TerminalRenderResourceRebuildResult resized = rebuilder.processNewest(
      fontConfiguration: initialConfig,
      warmup: (_, _, _) => unexpectedWarmup = true,
    );
    _expect(
      resized.isPublished &&
          !unexpectedWarmup &&
          identical(rebuilder.catalog, initialCatalog) &&
          identical(rebuilder.shapingCache, initialCache) &&
          atlas.resourceGeneration == initialAtlasGeneration &&
          bridge.nativeAtlasGeneration == initialAtlasGeneration &&
          outbox.isBoundToScreen(resizedScreen) &&
          !outbox.isPausedForFullRebuild,
      'resize-only rebuild preserves CoreText/cache/atlas generations',
    );
    _expectFullDamage(
      rebuilder,
      rows: 4,
      columns: 6,
      resourceGeneration: initialAtlasGeneration,
    );

    rebuilder.request(
      _target(
        resizedScreen,
        viewportWidth: 128,
        viewportHeight: 96,
        scale16_16: 2 << 16,
      ),
    );
    _expectState(
      () => rebuilder.encodeFrame(
        frameGeneration: 1,
        backgroundRgba: 0,
        instances: const <TerminalMetalInstance>[],
      ),
      'frame encoding is blocked while scale resources are unpublished',
    );
    late TerminalShapedText scaleShaped;
    late TerminalGlyphAtlasEntry scaleEntry;
    final TerminalRenderResourceRebuildResult scaled = rebuilder.processNewest(
      fontConfiguration: initialConfig,
      warmup:
          (
            TerminalFontCatalog catalog,
            TerminalShapingCache cache,
            TerminalGlyphAtlas atlas,
          ) {
            scaleShaped = cache.shape('A');
            scaleEntry = atlas
                .ingest(
                  catalog.rasterizeShaped(scaleShaped, scale: atlas.scale),
                )
                .single;
          },
    );
    _expect(
      scaled.isPublished &&
          identical(rebuilder.catalog, initialCatalog) &&
          identical(rebuilder.shapingCache, initialCache) &&
          atlas.scale16_16 == 2 << 16 &&
          atlas.resourceGeneration > initialAtlasGeneration &&
          bridge.isSynchronized &&
          bridge.nativeAtlasGeneration == atlas.resourceGeneration,
      '1x to 2x rebuild replaces and synchronizes the complete atlas',
    );
    _expectState(
      () => atlas.validateEntry(
        initialEntry,
        expectedResourceGeneration: atlas.resourceGeneration,
      ),
      '1x entry is rejected by the 2x atlas domain',
    );
    final TerminalMetalInstance scaleInstance = bridge.glyphInstance(
      scaleEntry,
      x: 0,
      y: 0,
    )!;
    final TerminalMetalFrame scaleFrame = rebuilder.encodeFrame(
      frameGeneration: 1,
      backgroundRgba: 0x102030ff,
      instances: <TerminalMetalInstance>[scaleInstance],
    );
    _expect(
      scaleFrame.viewportWidth == 128 &&
          scaleFrame.viewportHeight == 96 &&
          scaleFrame.scale16_16 == 2 << 16 &&
          scaleFrame.atlasGeneration == atlas.resourceGeneration &&
          scaleFrame.rendererGeneration == renderer.generation,
      '2x frame header uses only the published target and resource domain',
    );
    _expectFullDamage(
      rebuilder,
      rows: 4,
      columns: 6,
      resourceGeneration: atlas.resourceGeneration,
    );

    final int scaleAtlasGeneration = atlas.resourceGeneration;
    final TerminalRenderFontConfiguration replacementConfig =
        TerminalRenderFontConfiguration(
          generation: 2,
          family: 'Menlo',
          pointSize: 16,
        );
    rebuilder.request(
      _target(
        resizedScreen,
        viewportWidth: 128,
        viewportHeight: 96,
        scale16_16: 2 << 16,
        fontConfigurationGeneration: replacementConfig.generation,
      ),
    );
    late TerminalGlyphAtlasEntry fontEntry;
    final TerminalRenderResourceRebuildResult font = rebuilder.processNewest(
      fontConfiguration: replacementConfig,
      warmup:
          (
            TerminalFontCatalog catalog,
            TerminalShapingCache cache,
            TerminalGlyphAtlas atlas,
          ) {
            final TerminalShapedText shaped = cache.shape('A');
            fontEntry = atlas
                .ingest(catalog.rasterizeShaped(shaped, scale: atlas.scale))
                .single;
          },
    );
    _expect(
      font.isPublished &&
          rebuilder.catalog.generation > initialCatalog.generation &&
          rebuilder.catalog.metrics.pointSize == 16 &&
          rebuilder.shapingCache.catalog.generation ==
              rebuilder.catalog.generation &&
          initialCache.isDisposed &&
          initialCatalog.isDisposed &&
          atlas.catalogGeneration == rebuilder.catalog.generation &&
          atlas.resourceGeneration > scaleAtlasGeneration &&
          bridge.isSynchronized,
      'font rebuild swaps the real CoreText catalog/cache and native atlas',
    );
    _expectState(
      () => rebuilder.catalog.rasterizeShaped(scaleShaped, scale: atlas.scale),
      'new catalog rejects shaped text from the retired generation',
    );
    _expectState(
      () => atlas.validateEntry(
        scaleEntry,
        expectedResourceGeneration: atlas.resourceGeneration,
      ),
      'font reset rejects the retired atlas entry',
    );
    final TerminalMetalFrame fontFrame = rebuilder.encodeFrame(
      frameGeneration: 2,
      backgroundRgba: 0,
      instances: <TerminalMetalInstance>[
        bridge.glyphInstance(fontEntry, x: 0, y: 0)!,
      ],
    );
    _expect(
      fontFrame.viewportWidth == 128 &&
          fontFrame.viewportHeight == 96 &&
          fontFrame.scale16_16 == 2 << 16 &&
          fontFrame.atlasGeneration == atlas.resourceGeneration &&
          coordinator.publishedResources.catalogGeneration ==
              rebuilder.catalog.generation &&
          coordinator.publishedTarget.fontConfigurationGeneration == 2,
      'font frame and coordinator expose one matching published generation',
    );
    _expectFullDamage(
      rebuilder,
      rows: 4,
      columns: 6,
      resourceGeneration: atlas.resourceGeneration,
    );
  } finally {
    rebuilder.dispose();
    renderer.dispose();
  }
}

void _testLivePinBackpressureRetainsPlan() {
  final TerminalScreen screen = TerminalScreen(rows: 1, columns: 1);
  final TerminalDamageOutbox outbox = _initializedOutbox(screen, paneId: 52);
  final TerminalRenderFontConfiguration config =
      TerminalRenderFontConfiguration(generation: 1);
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  final TerminalShapingCache cache = TerminalShapingCache(catalog);
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: catalog.generation,
    limits: _atlasLimits,
  );
  final TerminalGlyphAtlasEntry pinnedEntry = _warmAtlas(
    catalog,
    cache,
    atlas,
  ).single;
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: _rendererConfig,
  );
  final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
    atlas: atlas,
    renderer: renderer,
  );
  _expect(
    bridge.synchronize() == TerminalGlyphAtlasSyncDisposition.synchronized,
    'initial pinned-atlas fixture has a real native generation',
  );
  final TerminalRenderRebuildCoordinator coordinator =
      TerminalRenderRebuildCoordinator(
        damageOutbox: outbox,
        initialTarget: _target(screen),
        initialResources: TerminalRenderResourceGenerations(
          catalogGeneration: catalog.generation,
          atlasGeneration: atlas.resourceGeneration,
        ),
      );
  final TerminalRenderResourceRebuilder rebuilder =
      TerminalRenderResourceRebuilder(
        coordinator: coordinator,
        bridge: bridge,
        catalog: catalog,
        shapingCache: cache,
        fontConfiguration: config,
      );
  try {
    atlas.pinForSubmission(99, <TerminalGlyphAtlasEntry>[pinnedEntry]);
    rebuilder.request(_target(screen, scale16_16: 2 << 16));
    final TerminalRenderResourceRebuildResult blocked = rebuilder.processNewest(
      fontConfiguration: config,
    );
    final int stagedGeneration = atlas.resourceGeneration;
    final TerminalRenderResourceRebuildResult retry = rebuilder.processNewest(
      fontConfiguration: config,
    );
    _expect(
      blocked.disposition ==
              TerminalRenderResourceRebuildDisposition.backpressured &&
          retry.disposition ==
              TerminalRenderResourceRebuildDisposition.backpressured &&
          coordinator.isRebuilding &&
          !coordinator.hasPendingRebuild &&
          rebuilder.hasActiveWork &&
          outbox.isPausedForFullRebuild &&
          bridge.isSynchronized &&
          atlas.resourceGeneration == stagedGeneration &&
          rebuilder.tryCreateDamageTransfer() == null,
      'live submission pin retains one newest plan without resource churn',
    );
    atlas.completeSubmission(99);
    final TerminalRenderResourceRebuildResult published = rebuilder
        .processNewest(fontConfiguration: config);
    _expect(
      published.isPublished &&
          atlas.resourceGeneration > stagedGeneration &&
          bridge.isSynchronized &&
          !coordinator.isRebuilding &&
          !outbox.isPausedForFullRebuild,
      'retired pin releases the same plan for one complete retry publication',
    );
  } finally {
    rebuilder.dispose();
    renderer.dispose();
  }
}

const TerminalGlyphAtlasLimits _atlasLimits = TerminalGlyphAtlasLimits(
  pageWidth: 64,
  pageHeight: 64,
  maximumAlphaPages: 2,
  maximumColorPages: 1,
  maximumEntries: 64,
  maximumRetainedBytes: 64 * 64 * 6,
  gutter: 1,
);

const TerminalMetalRendererConfig _rendererConfig = TerminalMetalRendererConfig(
  maximumViewportWidth: 256,
  maximumViewportHeight: 256,
  maximumInstances: 64,
  atlasWidth: 64,
  atlasHeight: 64,
  maximumAlphaPages: 2,
  maximumColorPages: 1,
);

TerminalRenderRebuildTarget _target(
  TerminalScreen screen, {
  int viewportWidth = 96,
  int viewportHeight = 64,
  int scale16_16 = 1 << 16,
  int fontConfigurationGeneration = 1,
}) => TerminalRenderRebuildTarget(
  screen: screen,
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
  scale16_16: scale16_16,
  fontConfigurationGeneration: fontConfigurationGeneration,
);

List<TerminalGlyphAtlasEntry> _warmAtlas(
  TerminalFontCatalog catalog,
  TerminalShapingCache cache,
  TerminalGlyphAtlas atlas,
) {
  final TerminalShapedText shaped = cache.shape('A');
  return atlas.ingest(catalog.rasterizeShaped(shaped, scale: atlas.scale));
}

TerminalDamageOutbox _initializedOutbox(
  TerminalScreen screen, {
  int paneId = 51,
}) {
  final TerminalDamageOutbox outbox = TerminalDamageOutbox(
    sessionId: TerminalSessionId(paneId: PaneId(paneId), generation: 1),
    screen: screen,
  );
  final TerminalDamageTransferEnvelope transfer = outbox.tryCreateTransfer(
    requiredResourceGeneration: 1,
  )!;
  _ack(outbox, transfer);
  return outbox;
}

void _expectFullDamage(
  TerminalRenderResourceRebuilder rebuilder, {
  required int rows,
  required int columns,
  required int resourceGeneration,
}) {
  final TerminalDamageOutbox outbox = rebuilder.coordinator.damageOutbox;
  final TerminalDamageTransferEnvelope? transfer = rebuilder
      .tryCreateDamageTransfer();
  if (transfer == null) {
    throw StateError('resource rebuild test expected full damage');
  }
  final TerminalDecodedDamage damage = transfer.materializeDamage(
    expectedSessionId: outbox.sessionId,
  );
  _expect(
    damage.isFullSnapshot &&
        damage.rows == rows &&
        damage.columns == columns &&
        damage.requiredResourceGeneration == resourceGeneration,
    'first damage matches the published target and atlas generation',
  );
  _ack(outbox, transfer);
}

void _ack(
  TerminalDamageOutbox outbox,
  TerminalDamageTransferEnvelope transfer,
) {
  final TerminalDamageAckHandlingResult result = outbox.acknowledge(
    TerminalDamageAcknowledgement.applied(
      sessionId: transfer.sessionId,
      damageGeneration: transfer.damageGeneration,
      acceptedBytes: transfer.byteLength,
    ),
  );
  if (!result.isAccepted) {
    throw StateError('resource rebuild test expected accepted damage ACK');
  }
}

void _expectState(void Function() action, String description) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('resource rebuild test failed: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('resource rebuild test failed: $description');
  }
}
