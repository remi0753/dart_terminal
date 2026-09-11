import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == '--write-goldens') {
    _writeGoldens();
    return;
  }
  if (arguments.isNotEmpty) {
    throw ArgumentError.value(arguments, 'arguments', 'unsupported');
  }
  runGlyphAtlasTests();
}

void runGlyphAtlasTests() {
  _testGrowthIsolationAndUploads();
  _testIncrementalUploadRectangles();
  _testEntryLruAndPins();
  _testPageAndBytePressure();
  _testResetAndValidation();
  _testKittyImageTilesShareAtlasLimitsAndPins();
  _testKittyImageResourcePruningWaitsForPins();
  _testTextGoldens();
}

void _testKittyImageTilesShareAtlasLimitsAndPins() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 1,
      maximumRetainedBytes: 8 * 8 * 4,
      gutter: 1,
    ),
  );
  TerminalKittyImageAtlasKey key(int placement, {int contentGeneration = 1}) =>
      TerminalKittyImageAtlasKey(
        screenKindIndex: 0,
        imageId: placement,
        imageResourceGeneration: 1,
        imageContentGeneration: contentGeneration,
        placementGeneration: placement,
        sourceX: 0,
        sourceY: 0,
        sourceWidth: 1,
        sourceHeight: 1,
        destinationX: placement,
        destinationY: 0,
        destinationWidth: 2,
        destinationHeight: 2,
        tileX: placement,
        tileY: 0,
        tileWidth: 2,
        tileHeight: 2,
        scale16_16: 1 << 16,
      );
  final Uint8List red = Uint8List.fromList(<int>[
    for (int index = 0; index < 4; index++) ...<int>[255, 0, 0, 255],
  ]);
  final Uint8List blue = Uint8List.fromList(<int>[
    for (int index = 0; index < 4; index++) ...<int>[0, 0, 255, 255],
  ]);
  final TerminalGlyphAtlasEntry first = atlas.ingestKittyImageTile(
    key: key(1),
    rgba: red,
  );
  final TerminalGlyphAtlasEntry duplicate = atlas.ingestKittyImageTile(
    key: key(1),
    rgba: Uint8List.fromList(red),
  );
  _expect(
    identical(first, duplicate) &&
        first.isKittyImage &&
        atlas.entryCount == 1 &&
        atlas.kittyImageEntryCount == 1 &&
        _bytesEqual(atlas.copyEntryPixels(first), red),
    'Kitty tiles are keyed separately and reuse exact color pixels',
  );
  final TerminalGlyphAtlasBuildLease lease = atlas.beginBuildLease();
  lease.retain(first);
  _expectThrows<TerminalGlyphAtlasCapacityException>(
    () => atlas.ingestKittyImageTile(
      key: key(1, contentGeneration: 2),
      rgba: blue,
    ),
    'frame-build pins prevent a visible Kitty tile from being evicted',
  );
  lease.close();
  final TerminalGlyphAtlasEntry second = atlas.ingestKittyImageTile(
    key: key(1, contentGeneration: 2),
    rgba: blue,
  );
  _expect(
    atlas.lookupKittyImage(key(1)) == null &&
        identical(
          atlas.lookupKittyImage(key(1, contentGeneration: 2)),
          second,
        ) &&
        atlas.entryCount == 1 &&
        atlas.kittyImageEntryCount == 1 &&
        atlas.evictionCount == 1,
    'a new animation content generation invalidates the unpinned old tile '
    'through the common bounded LRU ceiling',
  );
}

void _testKittyImageResourcePruningWaitsForPins() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 4,
      maximumRetainedBytes: 8 * 8 * 4,
      gutter: 1,
    ),
  );
  TerminalKittyImageAtlasKey key({
    required int resourceGeneration,
    required int contentGeneration,
  }) => TerminalKittyImageAtlasKey(
    screenKindIndex: 0,
    imageId: 7,
    imageResourceGeneration: resourceGeneration,
    imageContentGeneration: contentGeneration,
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
  );
  final Uint8List pixel = Uint8List.fromList(const <int>[1, 2, 3, 255]);
  final TerminalKittyImageAtlasKey staleRootKey = key(
    resourceGeneration: 1,
    contentGeneration: 1,
  );
  final TerminalKittyImageAtlasKey staleFrameKey = key(
    resourceGeneration: 1,
    contentGeneration: 2,
  );
  final TerminalKittyImageAtlasKey currentKey = key(
    resourceGeneration: 2,
    contentGeneration: 3,
  );
  final TerminalGlyphAtlasEntry staleRoot = atlas.ingestKittyImageTile(
    key: staleRootKey,
    rgba: pixel,
  );
  atlas.ingestKittyImageTile(key: staleFrameKey, rgba: pixel);
  final TerminalGlyphAtlasEntry current = atlas.ingestKittyImageTile(
    key: currentKey,
    rgba: pixel,
  );
  atlas.pinForSubmission(1, <TerminalGlyphAtlasEntry>[staleRoot]);

  final firstPrune = atlas.pruneKittyImageResources(
    (TerminalKittyImageAtlasKey candidate) =>
        candidate.imageResourceGeneration == 2,
  );
  _expect(
    firstPrune.removedEntryCount == 1 &&
        firstPrune.pinnedEntryCount == 1 &&
        identical(atlas.lookupKittyImage(staleRootKey), staleRoot) &&
        atlas.lookupKittyImage(staleFrameKey) == null &&
        identical(atlas.lookupKittyImage(currentKey), current),
    'whole-resource pruning removes unpinned frames and defers pinned tiles',
  );

  atlas.completeSubmission(1);
  final secondPrune = atlas.pruneKittyImageResources(
    (TerminalKittyImageAtlasKey candidate) =>
        candidate.imageResourceGeneration == 2,
  );
  _expect(
    secondPrune.removedEntryCount == 1 &&
        secondPrune.pinnedEntryCount == 0 &&
        atlas.lookupKittyImage(staleRootKey) == null &&
        identical(atlas.lookupKittyImage(currentKey), current) &&
        atlas.kittyImageEntryCount == 1 &&
        atlas.kittyImageEvictionCount == 2,
    'retired submission pins allow deterministic stale-resource cleanup',
  );
}

void _testIncrementalUploadRectangles() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 8,
      maximumRetainedBytes: 256,
      gutter: 1,
    ),
  );
  atlas.ingest(
    _batch(<_RasterSpec>[
      _RasterSpec.alpha(glyphId: 1, width: 2, height: 2, value: 20),
    ]),
  );
  final TerminalGlyphAtlasUpload initial = atlas.takePendingUploads().single;
  _expect(
    initial.x == 0 &&
        initial.y == 0 &&
        initial.width == 8 &&
        initial.height == 8 &&
        initial.pageWidth == 8 &&
        initial.pageHeight == 8 &&
        initial.rowStride == 8,
    'new page publishes one complete initialization upload',
  );
  final TerminalGlyphAtlasEntry second = atlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.alpha(glyphId: 2, width: 2, height: 2, value: 40),
        ]),
      )
      .single;
  final TerminalGlyphAtlasUpload delta = atlas.takePendingUploads().single;
  _expect(
    delta.pageId == second.pageId &&
        delta.x == second.x &&
        delta.y == second.y &&
        delta.width == second.width &&
        delta.height == second.height &&
        delta.pageWidth == 8 &&
        delta.pageHeight == 8 &&
        delta.rowStride == 2 &&
        delta.byteLength == 4 &&
        delta.copyBytes().every((int byte) => byte == 40),
    'existing page publishes only the coalesced changed rectangle',
  );
}

void _testGrowthIsolationAndUploads() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 2,
      maximumColorPages: 1,
      maximumEntries: 16,
      maximumRetainedBytes: 1024,
      gutter: 1,
    ),
  );
  final List<_RasterSpec> specs = <_RasterSpec>[
    for (int glyph = 1; glyph <= 5; glyph++)
      _RasterSpec.alpha(glyphId: glyph, width: 2, height: 2, value: glyph * 20),
    _RasterSpec.color(glyphId: 6, width: 2, height: 2),
  ];
  final TerminalGlyphRasterBatch batch = _batch(specs);
  final List<TerminalGlyphAtlasEntry> entries = atlas.ingest(batch);
  _expect(
    entries.length == 6 &&
        atlas.entryCount == 6 &&
        atlas.pageCount == 3 &&
        atlas.alphaPageCount == 2 &&
        atlas.colorPageCount == 1 &&
        atlas.retainedBytes == 8 * 8 * 2 + 8 * 8 * 4 &&
        atlas.retainedBytes <= atlas.limits.maximumRetainedBytes,
    'atlas grows bounded independent alpha and color page sets',
  );
  for (int index = 0; index < entries.length; index++) {
    _expect(
      _bytesEqual(atlas.copyEntryPixels(entries[index]), specs[index].pixels),
      'atlas copy preserves tightly packed raster $index',
    );
  }
  final TerminalGlyphAtlasSnapshot snapshot = atlas.snapshot();
  _expect(
    snapshot.resourceGeneration == atlas.resourceGeneration &&
        snapshot.pages.length == 3 &&
        snapshot.pages[0].pageId < snapshot.pages[1].pageId &&
        snapshot.pages[1].pageId < snapshot.pages[2].pageId,
    'atlas snapshot exposes ordered stable page identities',
  );
  final List<TerminalGlyphAtlasUpload> snapshotUploads = atlas
      .snapshotUploads();
  _expect(
    snapshotUploads.length == 3 &&
        snapshotUploads.every(
          (TerminalGlyphAtlasUpload upload) =>
              upload.x == 0 &&
              upload.y == 0 &&
              upload.width == 8 &&
              upload.height == 8,
        ) &&
        atlas.pendingUploadPageCount == 3,
    'full snapshot copies do not consume incremental dirty state',
  );
  final List<TerminalGlyphAtlasUpload> uploads = atlas.takePendingUploads();
  _expect(
    uploads.length == 3 &&
        uploads.every(
          (TerminalGlyphAtlasUpload upload) =>
              upload.resourceGeneration == atlas.resourceGeneration &&
              upload.byteLength == upload.rowStride * upload.height,
        ) &&
        atlas.pendingUploadPageCount == 0,
    'dirty pages drain as current-generation full-page uploads',
  );
  final Uint8List uploadCopy = uploads.first.copyBytes();
  uploadCopy.fillRange(0, uploadCopy.length, 0);
  _expect(
    uploads.first.copyBytes().any((int byte) => byte != 0),
    'upload pixel accessor returns an ownership copy',
  );
  final int generation = atlas.resourceGeneration;
  final TerminalGlyphAtlasEntry duplicate = atlas
      .ingest(_batch(<_RasterSpec>[specs.first]))
      .single;
  _expect(
    identical(duplicate, entries.first) &&
        atlas.resourceGeneration == generation &&
        atlas.pendingUploadPageCount == 0,
    'identical raster reinsertion is a hit without resource mutation',
  );
  final TerminalGlyphAtlasKey missingKey = TerminalGlyphAtlasKey(
    catalogGeneration: 1,
    faceId: 1,
    glyphId: 999,
    scale16_16: 1 << 16,
  );
  _expect(
    identical(atlas.lookup(entries.first.key), entries.first) &&
        atlas.lookup(missingKey) == null &&
        atlas.hitCount == 1 &&
        atlas.missCount == 1,
    'atlas lookup tracks hit/miss and promotes an entry',
  );
  final TerminalGlyphAtlasMetrics metrics = atlas.metrics;
  _expect(
    metrics.hitCount == 1 &&
        metrics.missCount == 1 &&
        metrics.lookupCount == 2 &&
        metrics.hitRate == 0.5,
    'atlas metrics snapshot exposes an exact lookup hit rate',
  );
  atlas.lookup(missingKey);
  final TerminalGlyphAtlasMetrics laterMetrics = atlas.metrics;
  _expect(
    metrics.missCount == 1 &&
        laterMetrics.missCount == 2 &&
        laterMetrics.lookupCount == 3 &&
        TerminalGlyphAtlas(catalogGeneration: 1).metrics.hitRate == 0.0,
    'atlas metrics snapshots are immutable and zero-lookups are defined',
  );
  _expectThrows<StateError>(
    () => atlas.ingest(
      _batch(<_RasterSpec>[
        _RasterSpec.alpha(glyphId: 1, width: 2, height: 2, value: 255),
      ]),
    ),
    'same key with different pixels',
  );
}

void _testEntryLruAndPins() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 4,
      pageHeight: 4,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 2,
      maximumRetainedBytes: 64,
      gutter: 0,
    ),
  );
  TerminalGlyphAtlasEntry addEmpty(int glyphId) => atlas
      .ingest(_batch(<_RasterSpec>[_RasterSpec.empty(glyphId: glyphId)]))
      .single;
  final TerminalGlyphAtlasEntry first = addEmpty(1);
  final TerminalGlyphAtlasEntry second = addEmpty(2);
  atlas.lookup(first.key);
  atlas.pinForSubmission(10, <TerminalGlyphAtlasEntry>[first, first]);
  final TerminalGlyphAtlasEntry third = addEmpty(3);
  _expect(
    atlas.entryCount == 2 &&
        atlas.evictionCount == 1 &&
        atlas.lookup(second.key) == null &&
        identical(atlas.lookup(first.key), first) &&
        first.pinCount == 1 &&
        atlas.livePinCount == 1,
    'entry cap evicts unpinned LRU and deduplicates a token pin set',
  );
  atlas.pinForSubmission(11, <TerminalGlyphAtlasEntry>[third]);
  final int generation = atlas.resourceGeneration;
  _expectThrows<TerminalGlyphAtlasCapacityException>(
    () => addEmpty(4),
    'all LRU candidates pinned',
  );
  _expect(
    atlas.entryCount == 2 && atlas.resourceGeneration == generation,
    'failed pinned-capacity insertion preserves atlas state',
  );
  atlas.completeSubmission(10);
  final TerminalGlyphAtlasEntry fourth = addEmpty(4);
  _expect(
    atlas.lookup(first.key) == null &&
        identical(atlas.lookup(fourth.key), fourth) &&
        third.isPinned,
    'unpin makes only the completed submission entry evictable',
  );
  _expectThrows<StateError>(
    () => atlas.completeSubmission(10),
    'submission completion is exact once',
  );
  _expectThrows<StateError>(
    () => atlas.pinForSubmission(11, <TerminalGlyphAtlasEntry>[fourth]),
    'submission token cannot be reused while live',
  );
  atlas.completeSubmission(11);
  _expect(!third.isPinned && atlas.livePinCount == 0, 'pin counts release');
}

void _testPageAndBytePressure() {
  const TerminalGlyphAtlasLimits pageLimits = TerminalGlyphAtlasLimits(
    pageWidth: 4,
    pageHeight: 4,
    maximumAlphaPages: 1,
    maximumColorPages: 1,
    maximumEntries: 8,
    maximumRetainedBytes: 64,
    gutter: 0,
  );
  final TerminalGlyphAtlas pageAtlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: pageLimits,
  );
  final TerminalGlyphAtlasEntry first = pageAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.alpha(glyphId: 1, width: 4, height: 4, value: 64),
        ]),
      )
      .single;
  pageAtlas.pinForSubmission(1, <TerminalGlyphAtlasEntry>[first]);
  _expectThrows<TerminalGlyphAtlasCapacityException>(
    () => pageAtlas.ingest(
      _batch(<_RasterSpec>[
        _RasterSpec.alpha(glyphId: 2, width: 4, height: 4, value: 128),
      ]),
    ),
    'full page cannot evict its pinned entry',
  );
  pageAtlas.completeSubmission(1);
  final int oldPage = first.pageId;
  final TerminalGlyphAtlasEntry replacement = pageAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.alpha(glyphId: 2, width: 4, height: 4, value: 128),
        ]),
      )
      .single;
  _expect(
    pageAtlas.entryCount == 1 &&
        pageAtlas.evictionCount == 1 &&
        replacement.pageId != oldPage,
    'page pressure evicts LRU, retires empty page, and allocates new identity',
  );
  _expectThrows<StateError>(
    () => pageAtlas.validateEntry(
      first,
      expectedResourceGeneration: pageAtlas.resourceGeneration,
    ),
    'evicted entry identity is stale',
  );

  final TerminalGlyphAtlas isolatedAtlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: pageLimits,
  );
  final TerminalGlyphAtlasEntry pinnedColor = isolatedAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.color(glyphId: 10, width: 4, height: 4),
        ]),
      )
      .single;
  isolatedAtlas.pinForSubmission(1, <TerminalGlyphAtlasEntry>[pinnedColor]);
  final TerminalGlyphAtlasEntry unrelatedAlpha = isolatedAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.alpha(glyphId: 11, width: 0, height: 0, value: 0),
        ]),
      )
      .single;
  _expectThrows<TerminalGlyphAtlasCapacityException>(
    () => isolatedAtlas.ingest(
      _batch(<_RasterSpec>[
        _RasterSpec.color(glyphId: 12, width: 4, height: 4),
      ]),
    ),
    'format page pressure cannot be relieved by another atlas format',
  );
  _expect(
    identical(isolatedAtlas.lookup(unrelatedAlpha.key), unrelatedAlpha) &&
        isolatedAtlas.evictionCount == 0,
    'format page pressure preserves unrelated atlas entries',
  );
  isolatedAtlas.completeSubmission(1);

  final TerminalGlyphAtlas byteAtlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: pageLimits,
  );
  final TerminalGlyphAtlasEntry alpha = byteAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.alpha(glyphId: 1, width: 4, height: 4, value: 128),
        ]),
      )
      .single;
  final TerminalGlyphAtlasEntry color = byteAtlas
      .ingest(
        _batch(<_RasterSpec>[
          _RasterSpec.color(glyphId: 2, width: 4, height: 4),
        ]),
      )
      .single;
  _expect(
    byteAtlas.entryCount == 1 &&
        byteAtlas.alphaPageCount == 0 &&
        byteAtlas.colorPageCount == 1 &&
        byteAtlas.retainedBytes == 64 &&
        byteAtlas.lookup(alpha.key) == null &&
        identical(byteAtlas.lookup(color.key), color),
    'global byte cap evicts alpha page before allocating isolated color page',
  );
  _expectThrows<TerminalGlyphAtlasCapacityException>(
    () => byteAtlas.ingest(
      _batch(<_RasterSpec>[
        _RasterSpec.alpha(glyphId: 3, width: 5, height: 1, value: 1),
      ]),
    ),
    'oversize raster is rejected before eviction',
  );
}

void _testResetAndValidation() {
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: 1,
    limits: const TerminalGlyphAtlasLimits(
      pageWidth: 8,
      pageHeight: 8,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
      maximumEntries: 8,
      maximumRetainedBytes: 256,
      gutter: 1,
    ),
  );
  final TerminalGlyphRasterBatch oldBatch = _batch(<_RasterSpec>[
    _RasterSpec.alpha(glyphId: 1, width: 2, height: 2, value: 200),
  ]);
  final TerminalGlyphAtlasEntry oldEntry = atlas.ingest(oldBatch).single;
  final int acceptedGeneration = atlas.resourceGeneration;
  final int acceptedResetEpoch = atlas.resetEpoch;
  atlas.validateEntry(oldEntry, expectedResourceGeneration: acceptedGeneration);
  atlas.pinForSubmission(1, <TerminalGlyphAtlasEntry>[oldEntry]);
  _expectThrows<StateError>(
    () => atlas.reset(catalogGeneration: 2, scale: 2),
    'reset is blocked while a submission pins resources',
  );
  atlas.completeSubmission(1);
  atlas.reset(catalogGeneration: 2, scale: 2);
  _expect(
    acceptedResetEpoch == 0 &&
        atlas.catalogGeneration == 2 &&
        atlas.scale16_16 == 2 << 16 &&
        atlas.entryCount == 0 &&
        atlas.pageCount == 0 &&
        atlas.retainedBytes == 0 &&
        atlas.resetEpoch == acceptedResetEpoch + 1 &&
        atlas.resourceGeneration > acceptedGeneration,
    'reset clears resources and advances the generation/domain',
  );
  _expectThrows<StateError>(
    () => atlas.lookup(oldEntry.key),
    'old key domain is rejected after reset',
  );
  _expectThrows<StateError>(
    () => atlas.ingest(oldBatch),
    'old raster batch is rejected after reset',
  );
  _expectThrows<StateError>(
    () => atlas.validateEntry(
      oldEntry,
      expectedResourceGeneration: atlas.resourceGeneration,
    ),
    'old entry identity is rejected after reset',
  );
  _expectThrows<StateError>(
    () => atlas.validateEntry(
      oldEntry,
      expectedResourceGeneration: acceptedGeneration,
    ),
    'old resource generation is rejected',
  );
  _expectThrows<ArgumentError>(
    () => const TerminalGlyphAtlasLimits(
      pageWidth: 2,
      pageHeight: 2,
      maximumRetainedBytes: 16,
      gutter: 1,
    ).validate(),
    'gutter must leave usable page area',
  );
}

void _testTextGoldens() {
  for (final int scale in <int>[1, 2]) {
    final File fixture = File('test/goldens/text/atlas-${scale}x.dtgi');
    _expect(fixture.existsSync(), 'checked-in atlas ${scale}x golden exists');
    final TerminalReferenceImage expected = TerminalGoldenImageCodec.decode(
      fixture.readAsBytesSync(),
    );
    final TerminalReferenceImage actual = _renderTextGolden(scale);
    TerminalGoldenImageComparator.compare(
      expected,
      actual,
    ).requireMatch('checked-in atlas ${scale}x text golden');
  }
}

TerminalReferenceImage _renderTextGolden(int scale) {
  const int logicalWidth = 256;
  const int rowHeight = 30;
  final Map<String, Object?> manifest = jsonDecode(
    File('test/goldens/text/corpus-v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final List<Object?> cases = manifest['cases']! as List<Object?>;
  final int pixelWidth = logicalWidth * scale;
  final int pixelHeight = rowHeight * cases.length * scale;
  final List<TerminalReferencePrimitive> primitives =
      <TerminalReferencePrimitive>[];
  for (int row = 0; row < cases.length; row++) {
    final Map<String, Object?> testCase = cases[row]! as Map<String, Object?>;
    final TerminalFontCatalog catalog = TerminalFontCatalog.open(
      family: testCase['family']! as String,
    );
    try {
      final TerminalShapedText shaped = catalog.shape(
        testCase['text']! as String,
        options: TerminalShapingOptions(
          ligatures: testCase['ligatures']! as bool,
        ),
      );
      final TerminalGlyphRasterBatch rasters = catalog.rasterizeShaped(
        shaped,
        scale: scale.toDouble(),
      );
      final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
        catalogGeneration: catalog.generation,
        scale: scale.toDouble(),
        limits: const TerminalGlyphAtlasLimits(
          pageWidth: 128,
          pageHeight: 64,
          maximumAlphaPages: 2,
          maximumColorPages: 2,
          maximumEntries: 256,
          maximumRetainedBytes: 128 * 64 * 8,
          gutter: 1,
        ),
      );
      final List<TerminalGlyphAtlasEntry> entries = atlas.ingest(rasters);
      final Map<TerminalGlyphAtlasKey, TerminalGlyphAtlasEntry> byKey =
          <TerminalGlyphAtlasKey, TerminalGlyphAtlasEntry>{
            for (final TerminalGlyphAtlasEntry entry in entries)
              entry.key: entry,
          };
      final int generation = atlas.resourceGeneration;
      atlas.pinForSubmission(row + 1, entries);
      final List<TerminalGlyphAtlasUpload> uploads = atlas.takePendingUploads();
      _expect(
        uploads.isNotEmpty &&
            uploads.every(
              (TerminalGlyphAtlasUpload upload) =>
                  upload.resourceGeneration == generation,
            ),
        'golden row publishes current atlas pages',
      );
      final int baseline = (row * rowHeight + 22) * scale;
      for (final TerminalShapedGlyph glyph in shaped.glyphs) {
        final TerminalGlyphAtlasKey key = TerminalGlyphAtlasKey(
          catalogGeneration: catalog.generation,
          faceId: glyph.faceId,
          glyphId: glyph.glyphId,
          scale16_16: scale << 16,
        );
        final TerminalGlyphAtlasEntry entry = byKey[key]!;
        atlas.validateEntry(entry, expectedResourceGeneration: generation);
        final TerminalReferencePrimitive? primitive = atlas.referencePrimitive(
          entry,
          x: 8 * scale + (glyph.positionX * scale).round() + entry.originX,
          y: baseline - entry.originY,
        );
        if (primitive != null) primitives.add(primitive);
      }
      atlas.completeSubmission(row + 1);
    } finally {
      catalog.dispose();
    }
  }
  final TerminalReferenceImage deviceImage = TerminalReferenceRenderer.render(
    width: pixelWidth,
    height: pixelHeight,
    background: const TerminalReferenceColor(0x10141aff),
    primitives: primitives,
  );
  return TerminalReferenceImage.fromRgba(
    width: pixelWidth,
    height: pixelHeight,
    scale: scale,
    rgba: deviceImage.copyRgbaBytes(),
  );
}

void _writeGoldens() {
  for (final int scale in <int>[1, 2]) {
    final File fixture = File('test/goldens/text/atlas-${scale}x.dtgi');
    fixture.writeAsBytesSync(
      TerminalGoldenImageCodec.encode(_renderTextGolden(scale)),
      flush: true,
    );
    stdout.writeln('wrote ${fixture.path}');
  }
}

TerminalGlyphRasterBatch _batch(
  List<_RasterSpec> specs, {
  int generation = 1,
  int scale16_16 = 1 << 16,
}) {
  final int pixelsOffset = 64 + specs.length * 48;
  final int pixelBytes = specs.fold<int>(
    0,
    (int total, _RasterSpec spec) => total + spec.pixels.length,
  );
  final Uint8List bytes = Uint8List(pixelsOffset + pixelBytes);
  final ByteData data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u32(0, 0x47525444);
  u32(4, 1);
  u32(8, 64);
  u32(12, bytes.length);
  data.setUint64(16, generation, Endian.little);
  u32(24, scale16_16);
  u32(28, specs.length);
  u32(32, 64);
  u32(36, pixelsOffset);
  u32(40, pixelBytes);
  var pixelCursor = pixelsOffset;
  final List<TerminalGlyphRasterRequest> requests =
      <TerminalGlyphRasterRequest>[];
  for (int index = 0; index < specs.length; index++) {
    final _RasterSpec spec = specs[index];
    final int record = 64 + index * 48;
    final int bpp = spec.color ? 4 : 1;
    requests.add(
      TerminalGlyphRasterRequest(faceId: spec.faceId, glyphId: spec.glyphId),
    );
    u32(record, spec.faceId);
    u32(record + 4, spec.glyphId);
    u32(record + 8, spec.color ? 2 : 1);
    u32(record + 12, spec.color ? TerminalRasterGlyphFlags.color : 0);
    data.setInt32(record + 16, spec.width == 0 ? 0 : -1, Endian.little);
    data.setInt32(
      record + 20,
      spec.height == 0 ? 0 : spec.height,
      Endian.little,
    );
    u32(record + 24, spec.width);
    u32(record + 28, spec.height);
    u32(record + 32, spec.width * bpp);
    u32(record + 36, pixelCursor);
    u32(record + 40, spec.pixels.length);
    bytes.setAll(pixelCursor, spec.pixels);
    pixelCursor += spec.pixels.length;
  }
  return TerminalRasterBufferV1.decode(
    bytes,
    requests: requests,
    catalogGeneration: generation,
    scale16_16: scale16_16,
  );
}

final class _RasterSpec {
  const _RasterSpec({
    required this.faceId,
    required this.glyphId,
    required this.color,
    required this.width,
    required this.height,
    required this.pixels,
  });

  factory _RasterSpec.alpha({
    int faceId = 1,
    required int glyphId,
    required int width,
    required int height,
    required int value,
  }) => _RasterSpec(
    faceId: faceId,
    glyphId: glyphId,
    color: false,
    width: width,
    height: height,
    pixels: List<int>.filled(width * height, value),
  );

  factory _RasterSpec.color({
    int faceId = 2,
    required int glyphId,
    required int width,
    required int height,
  }) => _RasterSpec(
    faceId: faceId,
    glyphId: glyphId,
    color: true,
    width: width,
    height: height,
    pixels: <int>[
      for (int index = 0; index < width * height; index++) ...<int>[
        255,
        index & 0xff,
        32,
        255,
      ],
    ],
  );

  factory _RasterSpec.empty({int faceId = 1, required int glyphId}) =>
      _RasterSpec(
        faceId: faceId,
        glyphId: glyphId,
        color: false,
        width: 0,
        height: 0,
        pixels: const <int>[],
      );

  final int faceId;
  final int glyphId;
  final bool color;
  final int width;
  final int height;
  final List<int> pixels;
}

bool _bytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition)
    throw StateError('glyph atlas expectation failed: $description');
}

void _expectThrows<T extends Object>(
  void Function() action,
  String description,
) {
  try {
    action();
  } on T {
    return;
  } on Object catch (error) {
    throw StateError(
      'glyph atlas expectation failed: $description threw ${error.runtimeType}',
    );
  }
  throw StateError('glyph atlas expectation failed: $description');
}
