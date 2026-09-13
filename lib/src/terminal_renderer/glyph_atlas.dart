import 'dart:collection';
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'reference_renderer.dart';
import 'terminal_cell_glyph.dart';
import 'terminal_overlay.dart';

enum TerminalGlyphAtlasFormat { alpha8, rgba8Straight }

final class TerminalGlyphAtlasKey {
  const TerminalGlyphAtlasKey({
    required this.catalogGeneration,
    required this.faceId,
    required this.glyphId,
    required this.scale16_16,
  });

  factory TerminalGlyphAtlasKey.fromRaster(
    TerminalGlyphRasterBatch batch,
    TerminalRasterizedGlyph glyph,
  ) => TerminalGlyphAtlasKey(
    catalogGeneration: batch.catalogGeneration,
    faceId: glyph.faceId,
    glyphId: glyph.glyphId,
    scale16_16: batch.scale16_16,
  );

  final int catalogGeneration;
  final int faceId;
  final int glyphId;
  final int scale16_16;

  @override
  int get hashCode =>
      Object.hash(catalogGeneration, faceId, glyphId, scale16_16);

  @override
  bool operator ==(Object other) =>
      other is TerminalGlyphAtlasKey &&
      catalogGeneration == other.catalogGeneration &&
      faceId == other.faceId &&
      glyphId == other.glyphId &&
      scale16_16 == other.scale16_16;
}

/// Stable identity for one product-owned device-pixel cell glyph raster.
final class TerminalCellGlyphAtlasKey {
  const TerminalCellGlyphAtlasKey({
    required this.catalogGeneration,
    required this.scalar,
    required this.cellWidth,
    required this.cellHeight,
    required this.lineThickness,
    required this.scale16_16,
  });

  factory TerminalCellGlyphAtlasKey.fromRequest({
    required int catalogGeneration,
    required int scale16_16,
    required TerminalCellGlyphRasterRequest request,
  }) => TerminalCellGlyphAtlasKey(
    catalogGeneration: catalogGeneration,
    scalar: request.scalar,
    cellWidth: request.cellWidth,
    cellHeight: request.cellHeight,
    lineThickness: request.lineThickness,
    scale16_16: scale16_16,
  );

  final int catalogGeneration;
  final int scalar;
  final int cellWidth;
  final int cellHeight;
  final int lineThickness;
  final int scale16_16;

  @override
  int get hashCode => Object.hash(
    catalogGeneration,
    scalar,
    cellWidth,
    cellHeight,
    lineThickness,
    scale16_16,
  );

  @override
  bool operator ==(Object other) =>
      other is TerminalCellGlyphAtlasKey &&
      catalogGeneration == other.catalogGeneration &&
      scalar == other.scalar &&
      cellWidth == other.cellWidth &&
      cellHeight == other.cellHeight &&
      lineThickness == other.lineThickness &&
      scale16_16 == other.scale16_16;
}

/// Stable identity for one device-pixel Kitty image tile in the color atlas.
final class TerminalKittyImageAtlasKey {
  const TerminalKittyImageAtlasKey({
    required this.screenKindIndex,
    required this.imageId,
    required this.imageResourceGeneration,
    required this.imageContentGeneration,
    required this.placementGeneration,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.destinationX,
    required this.destinationY,
    required this.destinationWidth,
    required this.destinationHeight,
    required this.tileX,
    required this.tileY,
    required this.tileWidth,
    required this.tileHeight,
    required this.scale16_16,
  });

  final int screenKindIndex;
  final int imageId;
  final int imageResourceGeneration;
  final int imageContentGeneration;
  final int placementGeneration;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int destinationX;
  final int destinationY;
  final int destinationWidth;
  final int destinationHeight;
  final int tileX;
  final int tileY;
  final int tileWidth;
  final int tileHeight;
  final int scale16_16;

  @override
  int get hashCode => Object.hashAll(<int>[
    screenKindIndex,
    imageId,
    imageResourceGeneration,
    imageContentGeneration,
    placementGeneration,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
    destinationX,
    destinationY,
    destinationWidth,
    destinationHeight,
    tileX,
    tileY,
    tileWidth,
    tileHeight,
    scale16_16,
  ]);

  @override
  bool operator ==(Object other) =>
      other is TerminalKittyImageAtlasKey &&
      screenKindIndex == other.screenKindIndex &&
      imageId == other.imageId &&
      imageResourceGeneration == other.imageResourceGeneration &&
      imageContentGeneration == other.imageContentGeneration &&
      placementGeneration == other.placementGeneration &&
      sourceX == other.sourceX &&
      sourceY == other.sourceY &&
      sourceWidth == other.sourceWidth &&
      sourceHeight == other.sourceHeight &&
      destinationX == other.destinationX &&
      destinationY == other.destinationY &&
      destinationWidth == other.destinationWidth &&
      destinationHeight == other.destinationHeight &&
      tileX == other.tileX &&
      tileY == other.tileY &&
      tileWidth == other.tileWidth &&
      tileHeight == other.tileHeight &&
      scale16_16 == other.scale16_16;
}

final class TerminalGlyphAtlasLimits {
  const TerminalGlyphAtlasLimits({
    this.pageWidth = 512,
    this.pageHeight = 512,
    this.maximumAlphaPages = 8,
    this.maximumColorPages = 4,
    this.maximumEntries = 16384,
    this.maximumRetainedBytes = 64 * 1024 * 1024,
    this.gutter = 1,
  });

  final int pageWidth;
  final int pageHeight;
  final int maximumAlphaPages;
  final int maximumColorPages;
  final int maximumEntries;
  final int maximumRetainedBytes;
  final int gutter;

  void validate() {
    RangeError.checkValueInInterval(pageWidth, 1, 4096, 'pageWidth');
    RangeError.checkValueInInterval(pageHeight, 1, 4096, 'pageHeight');
    RangeError.checkValueInInterval(
      maximumAlphaPages,
      1,
      64,
      'maximumAlphaPages',
    );
    RangeError.checkValueInInterval(
      maximumColorPages,
      1,
      64,
      'maximumColorPages',
    );
    RangeError.checkValueInInterval(
      maximumEntries,
      1,
      1024 * 1024,
      'maximumEntries',
    );
    RangeError.checkValueInInterval(gutter, 0, 16, 'gutter');
    if (pageWidth <= gutter * 2 || pageHeight <= gutter * 2) {
      throw ArgumentError('atlas gutter leaves no usable page area');
    }
    final int colorPageBytes = pageWidth * pageHeight * 4;
    if (maximumRetainedBytes < colorPageBytes ||
        maximumRetainedBytes > 512 * 1024 * 1024) {
      throw RangeError.range(
        maximumRetainedBytes,
        colorPageBytes,
        512 * 1024 * 1024,
        'maximumRetainedBytes',
      );
    }
  }
}

final class TerminalGlyphAtlasCapacityException implements Exception {
  const TerminalGlyphAtlasCapacityException(this.message);

  final String message;

  @override
  String toString() => 'TerminalGlyphAtlasCapacityException: $message';
}

final class TerminalGlyphAtlasEntry {
  TerminalGlyphAtlasEntry._({
    required Object owner,
    required this.entryId,
    required this.key,
    this.kittyImageKey,
    this.cellGlyphKey,
    required this.format,
    required this.pageId,
    required this.pageGeneration,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.originX,
    required this.originY,
    required _AtlasRect? allocation,
    required int lastUse,
  }) : _owner = owner,
       _allocation = allocation,
       _lastUse = lastUse;

  final Object _owner;
  final int entryId;
  final TerminalGlyphAtlasKey key;
  final TerminalKittyImageAtlasKey? kittyImageKey;
  final TerminalCellGlyphAtlasKey? cellGlyphKey;
  final TerminalGlyphAtlasFormat format;
  final int pageId;
  final int pageGeneration;
  final int x;
  final int y;
  final int width;
  final int height;
  final int rowStride;
  final int originX;
  final int originY;
  final _AtlasRect? _allocation;
  int _lastUse;
  int _pinCount = 0;

  bool get isEmpty => width == 0;
  bool get isKittyImage => kittyImageKey != null;
  bool get isCellGlyph => cellGlyphKey != null;
  bool get isPinned => _pinCount != 0;
  int get pinCount => _pinCount;
}

/// Short-lived pins used while one frame is assembled before native submit.
final class TerminalGlyphAtlasBuildLease {
  TerminalGlyphAtlasBuildLease._(this._atlas);

  final TerminalGlyphAtlas _atlas;
  final LinkedHashSet<TerminalGlyphAtlasEntry> _entries = LinkedHashSet();
  bool _isClosed = false;

  bool get isClosed => _isClosed;

  void retain(TerminalGlyphAtlasEntry entry) {
    if (_isClosed) throw StateError('atlas build lease is closed');
    _atlas._validateEntry(entry);
    if (_entries.add(entry)) {
      entry._pinCount++;
      _atlas._touch(entry);
    }
  }

  void close() {
    if (_isClosed) return;
    for (final TerminalGlyphAtlasEntry entry in _entries) {
      if (entry._pinCount <= 0) {
        throw StateError('atlas build pin accounting is corrupt');
      }
      entry._pinCount--;
    }
    _entries.clear();
    _isClosed = true;
    _atlas._activeBuildLeaseCount--;
  }
}

final class TerminalGlyphAtlasPageDescriptor {
  const TerminalGlyphAtlasPageDescriptor({
    required this.pageId,
    required this.pageGeneration,
    required this.format,
    required this.width,
    required this.height,
    required this.rowStride,
  });

  final int pageId;
  final int pageGeneration;
  final TerminalGlyphAtlasFormat format;
  final int width;
  final int height;
  final int rowStride;
}

final class TerminalGlyphAtlasSnapshot {
  TerminalGlyphAtlasSnapshot({
    required this.resourceGeneration,
    required this.resetEpoch,
    required this.catalogGeneration,
    required this.scale16_16,
    required List<TerminalGlyphAtlasPageDescriptor> pages,
  }) : pages = List<TerminalGlyphAtlasPageDescriptor>.unmodifiable(pages);

  final int resourceGeneration;
  final int resetEpoch;
  final int catalogGeneration;
  final int scale16_16;
  final List<TerminalGlyphAtlasPageDescriptor> pages;
}

/// Immutable cumulative lookup metrics for one Dart-owned atlas lifetime.
final class TerminalGlyphAtlasMetrics {
  const TerminalGlyphAtlasMetrics({
    required this.hitCount,
    required this.missCount,
  });

  final int hitCount;
  final int missCount;

  int get lookupCount => _saturatingAtlasAdd(hitCount, missCount);
  double get hitRate {
    if (hitCount == 0) return 0.0;
    if (missCount == 0) return 1.0;
    final double hits = hitCount.toDouble();
    return hits / (hits + missCount.toDouble());
  }
}

/// One deterministic pressure reclamation result without resource contents.
final class TerminalGlyphAtlasReclaimResult {
  const TerminalGlyphAtlasReclaimResult({
    required this.removedEntryCount,
    required this.pinnedEntryCount,
    required this.activeBuildLeaseCount,
    required this.releasedBytes,
  });

  final int removedEntryCount;
  final int pinnedEntryCount;
  final int activeBuildLeaseCount;
  final int releasedBytes;

  bool get isDeferred => pinnedEntryCount != 0 || activeBuildLeaseCount != 0;
}

final class TerminalGlyphAtlasUpload {
  TerminalGlyphAtlasUpload._({
    required this.resourceGeneration,
    required this.pageId,
    required this.pageGeneration,
    required this.format,
    required this.pageWidth,
    required this.pageHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rowStride,
    required Uint8List bytes,
  }) : _bytes = bytes;

  final int resourceGeneration;
  final int pageId;
  final int pageGeneration;
  final TerminalGlyphAtlasFormat format;
  final int pageWidth;
  final int pageHeight;
  final int x;
  final int y;
  final int width;
  final int height;
  final int rowStride;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}

/// Bounded Dart-owned alpha/color atlas with explicit submission pins.
final class TerminalGlyphAtlas {
  TerminalGlyphAtlas({
    required int catalogGeneration,
    double scale = 1,
    this.limits = const TerminalGlyphAtlasLimits(),
  }) : _catalogGeneration = catalogGeneration,
       _scale16_16 = TerminalRasterBufferV1.scaleToFixed(scale) {
    limits.validate();
    if (catalogGeneration <= 0) {
      throw RangeError.value(
        catalogGeneration,
        'catalogGeneration',
        'must be positive',
      );
    }
  }

  final TerminalGlyphAtlasLimits limits;
  final Object _owner = Object();
  final Map<TerminalGlyphAtlasKey, TerminalGlyphAtlasEntry> _entries = {};
  final Map<TerminalCellGlyphAtlasKey, TerminalGlyphAtlasEntry>
  _cellGlyphEntries = <TerminalCellGlyphAtlasKey, TerminalGlyphAtlasEntry>{};
  final Map<TerminalKittyImageAtlasKey, TerminalGlyphAtlasEntry>
  _kittyImageEntries = <TerminalKittyImageAtlasKey, TerminalGlyphAtlasEntry>{};
  final List<_AtlasPage> _pages = [];
  final Map<int, _AtlasRect> _dirtyPageRects = {};
  final Map<int, List<TerminalGlyphAtlasEntry>> _pins = {};

  int _catalogGeneration;
  int _scale16_16;
  int _resourceGeneration = 1;
  int _resetEpoch = 0;
  int _nextEntryId = 1;
  int _nextKittySyntheticGlyphId = -1;
  int _nextPageId = 1;
  int _nextPageGeneration = 1;
  int _useClock = 1;
  int _retainedBytes = 0;
  int _evictionCount = 0;
  int _kittyImageEvictionCount = 0;
  int _hitCount = 0;
  int _missCount = 0;
  int _activeBuildLeaseCount = 0;

  int get catalogGeneration => _catalogGeneration;
  int get scale16_16 => _scale16_16;
  double get scale => _scale16_16 / 65536.0;
  int get resourceGeneration => _resourceGeneration;
  int get resetEpoch => _resetEpoch;
  int get entryCount => _entries.length;
  int get cellGlyphEntryCount => _cellGlyphEntries.length;
  int get kittyImageEntryCount => _kittyImageEntries.length;
  int get pageCount => _pages.length;
  int get alphaPageCount => _pages
      .where(
        (_AtlasPage page) => page.format == TerminalGlyphAtlasFormat.alpha8,
      )
      .length;
  int get colorPageCount => _pages
      .where(
        (_AtlasPage page) =>
            page.format == TerminalGlyphAtlasFormat.rgba8Straight,
      )
      .length;
  int get retainedBytes => _retainedBytes;
  int get evictionCount => _evictionCount;
  int get kittyImageEvictionCount => _kittyImageEvictionCount;
  int get hitCount => _hitCount;
  int get missCount => _missCount;
  int get livePinCount => _pins.length;
  int get activeBuildLeaseCount => _activeBuildLeaseCount;
  int get pendingUploadPageCount => _dirtyPageRects.length;
  TerminalGlyphAtlasMetrics get metrics =>
      TerminalGlyphAtlasMetrics(hitCount: _hitCount, missCount: _missCount);

  TerminalGlyphAtlasBuildLease beginBuildLease() {
    _activeBuildLeaseCount++;
    return TerminalGlyphAtlasBuildLease._(this);
  }

  TerminalGlyphAtlasEntry? lookup(TerminalGlyphAtlasKey key) {
    _validateKeyDomain(key);
    final TerminalGlyphAtlasEntry? entry = _entries[key];
    if (entry == null) {
      _missCount = _saturatingAtlasIncrement(_missCount);
      return null;
    }
    _hitCount = _saturatingAtlasIncrement(_hitCount);
    _touch(entry);
    return entry;
  }

  List<TerminalGlyphAtlasEntry> ingest(TerminalGlyphRasterBatch batch) {
    if (batch.catalogGeneration != _catalogGeneration ||
        batch.scale16_16 != _scale16_16) {
      throw StateError('raster batch belongs to another atlas domain');
    }
    final List<TerminalGlyphAtlasEntry> result = [];
    for (final TerminalRasterizedGlyph glyph in batch.glyphs) {
      final TerminalGlyphAtlasKey key = TerminalGlyphAtlasKey.fromRaster(
        batch,
        glyph,
      );
      final TerminalGlyphAtlasEntry? existing = _entries[key];
      if (existing != null) {
        _requireSameRaster(existing, glyph);
        _touch(existing);
        result.add(existing);
      } else {
        result.add(_insert(key, glyph));
      }
    }
    return List.unmodifiable(result);
  }

  TerminalGlyphAtlasEntry? lookupCellGlyph(TerminalCellGlyphAtlasKey key) {
    _validateCellGlyphKeyDomain(key);
    final TerminalGlyphAtlasEntry? entry = _cellGlyphEntries[key];
    if (entry == null) {
      _missCount = _saturatingAtlasIncrement(_missCount);
      return null;
    }
    _hitCount = _saturatingAtlasIncrement(_hitCount);
    _touch(entry);
    return entry;
  }

  TerminalGlyphAtlasEntry ingestCellGlyph(TerminalCellGlyphRaster raster) {
    final TerminalCellGlyphAtlasKey key = TerminalCellGlyphAtlasKey.fromRequest(
      catalogGeneration: _catalogGeneration,
      scale16_16: _scale16_16,
      request: raster.request,
    );
    _validateCellGlyphKeyDomain(key);
    final TerminalGlyphAtlasEntry? existing = _cellGlyphEntries[key];
    if (existing != null) {
      if (existing.format != TerminalGlyphAtlasFormat.alpha8 ||
          existing.width != raster.width ||
          existing.height != raster.height ||
          existing.rowStride != raster.rowStride ||
          existing.originX != 0 ||
          existing.originY != 0 ||
          !_bytesEqual(copyEntryPixels(existing), raster.copyCoverage())) {
        throw StateError('existing cell glyph key has different raster bytes');
      }
      _touch(existing);
      return existing;
    }
    final TerminalGlyphAtlasKey storageKey = TerminalGlyphAtlasKey(
      catalogGeneration: _catalogGeneration,
      faceId: -2,
      glyphId: _cellGlyphStorageId(key),
      scale16_16: _scale16_16,
    );
    if (_entries.containsKey(storageKey)) {
      throw StateError('cell glyph storage identity collision');
    }
    return _insertRaw(
      key: storageKey,
      cellGlyphKey: key,
      format: TerminalGlyphAtlasFormat.alpha8,
      width: raster.width,
      height: raster.height,
      rowStride: raster.rowStride,
      originX: 0,
      originY: 0,
      pixels: raster.copyCoverage(),
    );
  }

  TerminalGlyphAtlasEntry? lookupKittyImage(TerminalKittyImageAtlasKey key) {
    _validateKittyImageKeyDomain(key);
    final TerminalGlyphAtlasEntry? entry = _kittyImageEntries[key];
    if (entry == null) {
      _missCount = _saturatingAtlasIncrement(_missCount);
      return null;
    }
    _hitCount = _saturatingAtlasIncrement(_hitCount);
    _touch(entry);
    return entry;
  }

  TerminalGlyphAtlasEntry ingestKittyImageTile({
    required TerminalKittyImageAtlasKey key,
    required Uint8List rgba,
    TerminalRenderColorSpace inputColorSpace = TerminalRenderColorSpace.srgb,
  }) {
    _validateKittyImageKeyDomain(key);
    final int width = key.tileWidth;
    final int height = key.tileHeight;
    if (width <= 0 ||
        height <= 0 ||
        width > limits.pageWidth - limits.gutter * 2 ||
        height > limits.pageHeight - limits.gutter * 2 ||
        rgba.length != width * height * 4) {
      throw const TerminalGlyphAtlasCapacityException(
        'Kitty image tile does not fit a color atlas page',
      );
    }
    final Uint8List canonicalRgba = switch (inputColorSpace) {
      TerminalRenderColorSpace.srgb => rgba,
      TerminalRenderColorSpace.displayP3 =>
        TerminalRenderColorConverter.displayP3ToSrgbBuffer(rgba),
    };
    final TerminalGlyphAtlasEntry? existing = _kittyImageEntries[key];
    if (existing != null) {
      if (existing.width != width ||
          existing.height != height ||
          existing.rowStride != width * 4 ||
          !_bytesEqual(copyEntryPixels(existing), canonicalRgba)) {
        throw StateError('existing Kitty atlas key has different pixel bytes');
      }
      _touch(existing);
      return existing;
    }
    return _insertKittyImageTile(key, canonicalRgba);
  }

  /// Removes stale whole-image Kitty tiles in deterministic entry order.
  ///
  /// Submission/build-pinned entries remain until their owner retires and are
  /// reported so the caller can retry without discarding a live GPU resource.
  ({int removedEntryCount, int pinnedEntryCount}) pruneKittyImageResources(
    bool Function(TerminalKittyImageAtlasKey key) retain,
  ) {
    final List<TerminalGlyphAtlasEntry> stale = <TerminalGlyphAtlasEntry>[];
    for (final MapEntry<TerminalKittyImageAtlasKey, TerminalGlyphAtlasEntry>
        entry
        in _kittyImageEntries.entries) {
      if (!retain(entry.key)) stale.add(entry.value);
    }
    stale.sort(
      (TerminalGlyphAtlasEntry left, TerminalGlyphAtlasEntry right) =>
          left.entryId.compareTo(right.entryId),
    );
    var removed = 0;
    var pinned = 0;
    for (final TerminalGlyphAtlasEntry entry in stale) {
      if (entry.isPinned) {
        pinned++;
        continue;
      }
      _evict(entry);
      removed++;
    }
    return (removedEntryCount: removed, pinnedEntryCount: pinned);
  }

  /// Removes every currently unpinned reproducible atlas entry.
  ///
  /// An active frame build defers the whole operation. Submission-pinned
  /// entries are retained while independent unpinned entries are reclaimed in
  /// stable identity order, allowing the owner to retry after retirement.
  TerminalGlyphAtlasReclaimResult reclaimUnpinnedResources() {
    if (_activeBuildLeaseCount != 0) {
      return TerminalGlyphAtlasReclaimResult(
        removedEntryCount: 0,
        pinnedEntryCount: _entries.values
            .where((TerminalGlyphAtlasEntry entry) => entry.isPinned)
            .length,
        activeBuildLeaseCount: _activeBuildLeaseCount,
        releasedBytes: 0,
      );
    }
    final int retainedBefore = _retainedBytes;
    final List<TerminalGlyphAtlasEntry> candidates = _entries.values.toList()
      ..sort(
        (TerminalGlyphAtlasEntry left, TerminalGlyphAtlasEntry right) =>
            left.entryId.compareTo(right.entryId),
      );
    var removed = 0;
    var pinned = 0;
    for (final TerminalGlyphAtlasEntry entry in candidates) {
      if (entry.isPinned) {
        pinned++;
        continue;
      }
      _evict(entry);
      removed++;
    }
    return TerminalGlyphAtlasReclaimResult(
      removedEntryCount: removed,
      pinnedEntryCount: pinned,
      activeBuildLeaseCount: 0,
      releasedBytes: retainedBefore - _retainedBytes,
    );
  }

  void pinForSubmission(
    int submissionToken,
    Iterable<TerminalGlyphAtlasEntry> entries,
  ) {
    if (submissionToken <= 0 || _pins.containsKey(submissionToken)) {
      throw StateError('submission token is invalid or already pinned');
    }
    final LinkedHashSet<TerminalGlyphAtlasEntry> unique = LinkedHashSet();
    for (final TerminalGlyphAtlasEntry entry in entries) {
      _validateEntry(entry);
      unique.add(entry);
    }
    if (unique.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'must be nonempty');
    }
    final List<TerminalGlyphAtlasEntry> retained = List.of(unique);
    for (final TerminalGlyphAtlasEntry entry in retained) {
      entry._pinCount++;
      _touch(entry);
    }
    _pins[submissionToken] = retained;
  }

  void completeSubmission(int submissionToken) {
    final List<TerminalGlyphAtlasEntry>? entries = _pins.remove(
      submissionToken,
    );
    if (entries == null) {
      throw StateError('submission token is not pinned');
    }
    for (final TerminalGlyphAtlasEntry entry in entries) {
      if (entry._pinCount <= 0) {
        throw StateError('atlas pin accounting is corrupt');
      }
      entry._pinCount--;
    }
  }

  void validateEntry(
    TerminalGlyphAtlasEntry entry, {
    required int expectedResourceGeneration,
  }) {
    if (expectedResourceGeneration != _resourceGeneration) {
      throw StateError('atlas resource generation is stale');
    }
    _validateEntry(entry);
  }

  TerminalGlyphAtlasSnapshot snapshot() {
    final List<TerminalGlyphAtlasPageDescriptor> pages =
        _pages
            .map(
              (_AtlasPage page) => TerminalGlyphAtlasPageDescriptor(
                pageId: page.pageId,
                pageGeneration: page.pageGeneration,
                format: page.format,
                width: page.width,
                height: page.height,
                rowStride: page.rowStride,
              ),
            )
            .toList()
          ..sort((a, b) => a.pageId.compareTo(b.pageId));
    return TerminalGlyphAtlasSnapshot(
      resourceGeneration: _resourceGeneration,
      resetEpoch: _resetEpoch,
      catalogGeneration: _catalogGeneration,
      scale16_16: _scale16_16,
      pages: pages,
    );
  }

  /// Copies every live page as a full upload without consuming dirty state.
  ///
  /// This is the recovery/first-attachment path. Incremental consumers should
  /// use [takePendingUploads] after establishing their initial snapshot.
  List<TerminalGlyphAtlasUpload> snapshotUploads() {
    final List<_AtlasPage> pages = List<_AtlasPage>.of(_pages)
      ..sort((_AtlasPage a, _AtlasPage b) => a.pageId.compareTo(b.pageId));
    return List<TerminalGlyphAtlasUpload>.unmodifiable(
      pages.map(
        (_AtlasPage page) => TerminalGlyphAtlasUpload._(
          resourceGeneration: _resourceGeneration,
          pageId: page.pageId,
          pageGeneration: page.pageGeneration,
          format: page.format,
          pageWidth: page.width,
          pageHeight: page.height,
          x: 0,
          y: 0,
          width: page.width,
          height: page.height,
          rowStride: page.rowStride,
          bytes: Uint8List.fromList(page.pixels),
        ),
      ),
    );
  }

  List<TerminalGlyphAtlasUpload> takePendingUploads() {
    final List<_AtlasPage> dirty =
        _pages
            .where(
              (_AtlasPage page) => _dirtyPageRects.containsKey(page.pageId),
            )
            .toList()
          ..sort((_AtlasPage a, _AtlasPage b) => a.pageId.compareTo(b.pageId));
    final List<TerminalGlyphAtlasUpload> uploads = <TerminalGlyphAtlasUpload>[];
    for (final _AtlasPage page in dirty) {
      final _AtlasRect rect = _dirtyPageRects[page.pageId]!;
      final int bpp = _bytesPerPixel(page.format);
      final int rowStride = rect.width * bpp;
      final Uint8List bytes = Uint8List(rowStride * rect.height);
      for (int row = 0; row < rect.height; row++) {
        final int source = (rect.y + row) * page.rowStride + rect.x * bpp;
        bytes.setRange(
          row * rowStride,
          (row + 1) * rowStride,
          page.pixels,
          source,
        );
      }
      uploads.add(
        TerminalGlyphAtlasUpload._(
          resourceGeneration: _resourceGeneration,
          pageId: page.pageId,
          pageGeneration: page.pageGeneration,
          format: page.format,
          pageWidth: page.width,
          pageHeight: page.height,
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
          rowStride: rowStride,
          bytes: bytes,
        ),
      );
    }
    _dirtyPageRects.clear();
    return List.unmodifiable(uploads);
  }

  Uint8List copyEntryPixels(TerminalGlyphAtlasEntry entry) {
    _validateEntry(entry);
    if (entry.isEmpty) return Uint8List(0);
    final _AtlasPage page = _pageForEntry(entry);
    final int bpp = _bytesPerPixel(entry.format);
    final Uint8List result = Uint8List(entry.rowStride * entry.height);
    for (int row = 0; row < entry.height; row++) {
      final int source = (entry.y + row) * page.rowStride + entry.x * bpp;
      result.setRange(
        row * entry.rowStride,
        (row + 1) * entry.rowStride,
        page.pixels,
        source,
      );
    }
    return result;
  }

  TerminalReferencePrimitive? referencePrimitive(
    TerminalGlyphAtlasEntry entry, {
    required int x,
    required int y,
    TerminalReferenceColor maskColor = const TerminalReferenceColor(0xffffffff),
  }) {
    _validateEntry(entry);
    if (entry.isEmpty) {
      return null;
    }
    final Uint8List pixels = copyEntryPixels(entry);
    if (entry.format == TerminalGlyphAtlasFormat.alpha8) {
      return TerminalReferenceMask(
        layer: TerminalReferenceLayer.glyph,
        x: x,
        y: y,
        width: entry.width,
        height: entry.height,
        rowStride: entry.rowStride,
        coverage: pixels,
        color: maskColor,
      );
    }
    return TerminalReferenceBitmap(
      layer: TerminalReferenceLayer.glyph,
      x: x,
      y: y,
      width: entry.width,
      height: entry.height,
      rowStride: entry.rowStride,
      rgba: pixels,
    );
  }

  void reset({required int catalogGeneration, required double scale}) {
    if (_pins.isNotEmpty || _activeBuildLeaseCount != 0) {
      throw StateError('cannot reset an atlas with pinned submissions');
    }
    if (catalogGeneration <= 0) {
      throw RangeError.value(
        catalogGeneration,
        'catalogGeneration',
        'must be positive',
      );
    }
    final int scale16_16 = TerminalRasterBufferV1.scaleToFixed(scale);
    _incrementResourceGeneration();
    _catalogGeneration = catalogGeneration;
    _scale16_16 = scale16_16;
    _entries.clear();
    _cellGlyphEntries.clear();
    _kittyImageEntries.clear();
    _pages.clear();
    _dirtyPageRects.clear();
    _retainedBytes = 0;
    _resetEpoch++;
  }

  TerminalGlyphAtlasEntry _insert(
    TerminalGlyphAtlasKey key,
    TerminalRasterizedGlyph glyph,
  ) => _insertRaw(
    key: key,
    format: _atlasFormat(glyph.format),
    width: glyph.width,
    height: glyph.height,
    rowStride: glyph.rowStride,
    originX: glyph.originX,
    originY: glyph.originY,
    pixels: glyph.copyPixels(),
    diagnosticIdentity: '${glyph.faceId}:${glyph.glyphId}',
  );

  TerminalGlyphAtlasEntry _insertRaw({
    required TerminalGlyphAtlasKey key,
    TerminalCellGlyphAtlasKey? cellGlyphKey,
    required TerminalGlyphAtlasFormat format,
    required int width,
    required int height,
    required int rowStride,
    required int originX,
    required int originY,
    required Uint8List pixels,
    String diagnosticIdentity = 'cell',
  }) {
    final int bpp = _bytesPerPixel(format);
    if ((width == 0) != (height == 0) ||
        width > limits.pageWidth - limits.gutter * 2 ||
        height > limits.pageHeight - limits.gutter * 2 ||
        rowStride != width * bpp ||
        pixels.length != rowStride * height) {
      throw TerminalGlyphAtlasCapacityException(
        'glyph $diagnosticIdentity does not fit an atlas page',
      );
    }
    _ensureEntryCapacity(format);
    _AtlasPage? page;
    _AtlasRect? allocation;
    if (width != 0) {
      final int allocationWidth = width + limits.gutter * 2;
      final int allocationHeight = height + limits.gutter * 2;
      while (true) {
        final _AtlasPlacement? placement = _findPlacement(
          format,
          allocationWidth,
          allocationHeight,
        );
        if (placement != null) {
          page = placement.page;
          allocation = placement.rect;
          break;
        }
        if (_canCreatePage(format)) {
          page = _createPage(format);
          allocation = page.allocate(allocationWidth, allocationHeight);
          if (allocation == null) {
            throw StateError('new atlas page rejected a prevalidated glyph');
          }
          break;
        }
        if (!_evictForPlacement(format)) {
          throw const TerminalGlyphAtlasCapacityException(
            'all atlas eviction candidates are pinned',
          );
        }
      }
    }
    final TerminalGlyphAtlasEntry entry = TerminalGlyphAtlasEntry._(
      owner: _owner,
      entryId: _takeEntryId(),
      key: key,
      cellGlyphKey: cellGlyphKey,
      format: format,
      pageId: page?.pageId ?? 0,
      pageGeneration: page?.pageGeneration ?? 0,
      x: allocation == null ? 0 : allocation.x + limits.gutter,
      y: allocation == null ? 0 : allocation.y + limits.gutter,
      width: width,
      height: height,
      rowStride: rowStride,
      originX: originX,
      originY: originY,
      allocation: allocation,
      lastUse: _takeUseClock(),
    );
    if (page != null && allocation != null) {
      _copyRasterIntoPage(page, entry, pixels);
      page.entryIds.add(entry.entryId);
      _markDirty(page, _AtlasRect(entry.x, entry.y, entry.width, entry.height));
    }
    _entries[key] = entry;
    if (cellGlyphKey != null) _cellGlyphEntries[cellGlyphKey] = entry;
    _incrementResourceGeneration();
    return entry;
  }

  TerminalGlyphAtlasEntry _insertKittyImageTile(
    TerminalKittyImageAtlasKey imageKey,
    Uint8List rgba,
  ) {
    const TerminalGlyphAtlasFormat format =
        TerminalGlyphAtlasFormat.rgba8Straight;
    final int width = imageKey.tileWidth;
    final int height = imageKey.tileHeight;
    _ensureEntryCapacity(format);
    final int allocationWidth = width + limits.gutter * 2;
    final int allocationHeight = height + limits.gutter * 2;
    late final _AtlasPage page;
    late final _AtlasRect allocation;
    while (true) {
      final _AtlasPlacement? placement = _findPlacement(
        format,
        allocationWidth,
        allocationHeight,
      );
      if (placement != null) {
        page = placement.page;
        allocation = placement.rect;
        break;
      }
      if (_canCreatePage(format)) {
        page = _createPage(format);
        final _AtlasRect? created = page.allocate(
          allocationWidth,
          allocationHeight,
        );
        if (created == null) {
          throw StateError('new atlas page rejected a prevalidated image tile');
        }
        allocation = created;
        break;
      }
      if (!_evictForPlacement(format)) {
        throw const TerminalGlyphAtlasCapacityException(
          'all atlas eviction candidates are pinned',
        );
      }
    }
    final TerminalGlyphAtlasKey syntheticKey = TerminalGlyphAtlasKey(
      catalogGeneration: _catalogGeneration,
      faceId: -1,
      glyphId: _takeKittySyntheticGlyphId(),
      scale16_16: _scale16_16,
    );
    final TerminalGlyphAtlasEntry entry = TerminalGlyphAtlasEntry._(
      owner: _owner,
      entryId: _takeEntryId(),
      key: syntheticKey,
      kittyImageKey: imageKey,
      format: format,
      pageId: page.pageId,
      pageGeneration: page.pageGeneration,
      x: allocation.x + limits.gutter,
      y: allocation.y + limits.gutter,
      width: width,
      height: height,
      rowStride: width * 4,
      originX: 0,
      originY: 0,
      allocation: allocation,
      lastUse: _takeUseClock(),
    );
    _copyRasterIntoPage(page, entry, rgba);
    page.entryIds.add(entry.entryId);
    _markDirty(page, _AtlasRect(entry.x, entry.y, width, height));
    _entries[syntheticKey] = entry;
    _kittyImageEntries[imageKey] = entry;
    _incrementResourceGeneration();
    return entry;
  }

  void _ensureEntryCapacity(TerminalGlyphAtlasFormat format) {
    while (_entries.length >= limits.maximumEntries) {
      if (!_evictOldestUnpinned(preferredFormat: format)) {
        throw const TerminalGlyphAtlasCapacityException(
          'all entries are pinned at the atlas entry cap',
        );
      }
    }
  }

  _AtlasPlacement? _findPlacement(
    TerminalGlyphAtlasFormat format,
    int width,
    int height,
  ) {
    final List<_AtlasPage> pages =
        _pages.where((_AtlasPage page) => page.format == format).toList()
          ..sort((_AtlasPage a, _AtlasPage b) => a.pageId.compareTo(b.pageId));
    for (final _AtlasPage page in pages) {
      final _AtlasRect? rect = page.allocate(width, height);
      if (rect != null) return _AtlasPlacement(page, rect);
    }
    return null;
  }

  bool _canCreatePage(TerminalGlyphAtlasFormat format) {
    final int count = _pages
        .where((_AtlasPage page) => page.format == format)
        .length;
    final int maximum = format == TerminalGlyphAtlasFormat.alpha8
        ? limits.maximumAlphaPages
        : limits.maximumColorPages;
    final int bytes =
        limits.pageWidth * limits.pageHeight * _bytesPerPixel(format);
    return count < maximum &&
        _retainedBytes + bytes <= limits.maximumRetainedBytes;
  }

  _AtlasPage _createPage(TerminalGlyphAtlasFormat format) {
    final _AtlasPage page = _AtlasPage(
      pageId: _takePageId(),
      pageGeneration: _takePageGeneration(),
      format: format,
      width: limits.pageWidth,
      height: limits.pageHeight,
    );
    _pages.add(page);
    _retainedBytes += page.pixels.length;
    _markDirty(page, _AtlasRect(0, 0, page.width, page.height));
    _incrementResourceGeneration();
    return page;
  }

  bool _evictOldestUnpinned({
    required TerminalGlyphAtlasFormat preferredFormat,
    bool allowOtherFormats = true,
  }) {
    TerminalGlyphAtlasEntry? candidate;
    for (final TerminalGlyphAtlasEntry entry in _entries.values) {
      if (!entry.isPinned && entry.format == preferredFormat) {
        if (candidate == null || _isOlder(entry, candidate)) candidate = entry;
      }
    }
    if (candidate == null && allowOtherFormats) {
      for (final TerminalGlyphAtlasEntry entry in _entries.values) {
        if (!entry.isPinned &&
            (candidate == null || _isOlder(entry, candidate))) {
          candidate = entry;
        }
      }
    }
    if (candidate == null) return false;
    _evict(candidate);
    return true;
  }

  bool _evictForPlacement(TerminalGlyphAtlasFormat format) {
    final int formatPageCount = _pages
        .where((_AtlasPage page) => page.format == format)
        .length;
    final int maximumFormatPages = format == TerminalGlyphAtlasFormat.alpha8
        ? limits.maximumAlphaPages
        : limits.maximumColorPages;
    return _evictOldestUnpinned(
      preferredFormat: format,
      allowOtherFormats: formatPageCount < maximumFormatPages,
    );
  }

  bool _isOlder(TerminalGlyphAtlasEntry a, TerminalGlyphAtlasEntry b) =>
      a._lastUse < b._lastUse ||
      (a._lastUse == b._lastUse && a.entryId < b.entryId);

  void _evict(TerminalGlyphAtlasEntry entry) {
    _validateEntry(entry);
    if (entry.isPinned) throw StateError('cannot evict a pinned atlas entry');
    _entries.remove(entry.key);
    final TerminalCellGlyphAtlasKey? cellGlyphKey = entry.cellGlyphKey;
    if (cellGlyphKey != null) {
      _cellGlyphEntries.remove(cellGlyphKey);
    }
    final TerminalKittyImageAtlasKey? imageKey = entry.kittyImageKey;
    if (imageKey != null) {
      _kittyImageEntries.remove(imageKey);
      _kittyImageEvictionCount = _saturatingAtlasIncrement(
        _kittyImageEvictionCount,
      );
    }
    if (!entry.isEmpty) {
      final _AtlasPage page = _pageForEntry(entry);
      final _AtlasRect allocation = entry._allocation!;
      page.clear(allocation);
      page.free(allocation);
      page.entryIds.remove(entry.entryId);
      _markDirty(page, allocation);
      if (page.entryIds.isEmpty) {
        _pages.remove(page);
        _dirtyPageRects.remove(page.pageId);
        _retainedBytes -= page.pixels.length;
      }
    }
    _evictionCount++;
    _incrementResourceGeneration();
  }

  void _copyRasterIntoPage(
    _AtlasPage page,
    TerminalGlyphAtlasEntry entry,
    Uint8List source,
  ) {
    final int bpp = _bytesPerPixel(entry.format);
    for (int row = 0; row < entry.height; row++) {
      final int destination = (entry.y + row) * page.rowStride + entry.x * bpp;
      page.pixels.setRange(
        destination,
        destination + entry.rowStride,
        source,
        row * entry.rowStride,
      );
    }
  }

  void _markDirty(_AtlasPage page, _AtlasRect rect) {
    final _AtlasRect? previous = _dirtyPageRects[page.pageId];
    if (previous == null) {
      _dirtyPageRects[page.pageId] = rect;
      return;
    }
    final int left = previous.x < rect.x ? previous.x : rect.x;
    final int top = previous.y < rect.y ? previous.y : rect.y;
    final int previousRight = previous.x + previous.width;
    final int rectRight = rect.x + rect.width;
    final int previousBottom = previous.y + previous.height;
    final int rectBottom = rect.y + rect.height;
    final int right = previousRight > rectRight ? previousRight : rectRight;
    final int bottom = previousBottom > rectBottom
        ? previousBottom
        : rectBottom;
    _dirtyPageRects[page.pageId] = _AtlasRect(
      left,
      top,
      right - left,
      bottom - top,
    );
  }

  void _requireSameRaster(
    TerminalGlyphAtlasEntry entry,
    TerminalRasterizedGlyph glyph,
  ) {
    if (entry.format != _atlasFormat(glyph.format) ||
        entry.width != glyph.width ||
        entry.height != glyph.height ||
        entry.rowStride != glyph.rowStride ||
        entry.originX != glyph.originX ||
        entry.originY != glyph.originY ||
        !_bytesEqual(copyEntryPixels(entry), glyph.copyPixels())) {
      throw StateError('existing atlas key has different raster bytes');
    }
  }

  void _validateKeyDomain(TerminalGlyphAtlasKey key) {
    if (key.catalogGeneration != _catalogGeneration ||
        key.scale16_16 != _scale16_16) {
      throw StateError('glyph key belongs to another atlas domain');
    }
  }

  void _validateCellGlyphKeyDomain(TerminalCellGlyphAtlasKey key) {
    if (key.catalogGeneration != _catalogGeneration ||
        key.scale16_16 != _scale16_16) {
      throw StateError('cell glyph key belongs to another atlas domain');
    }
    TerminalCellGlyphRasterRequest(
      scalar: key.scalar,
      cellWidth: key.cellWidth,
      cellHeight: key.cellHeight,
      lineThickness: key.lineThickness,
    );
  }

  void _validateKittyImageKeyDomain(TerminalKittyImageAtlasKey key) {
    if (key.scale16_16 != _scale16_16) {
      throw StateError('Kitty image key belongs to another atlas domain');
    }
  }

  void _validateEntry(TerminalGlyphAtlasEntry entry) {
    if (!identical(entry._owner, _owner) ||
        !identical(_entries[entry.key], entry) ||
        (entry.cellGlyphKey != null &&
            !identical(_cellGlyphEntries[entry.cellGlyphKey], entry)) ||
        (entry.kittyImageKey != null &&
            !identical(_kittyImageEntries[entry.kittyImageKey], entry))) {
      throw StateError('atlas entry is stale or belongs to another atlas');
    }
    _validateKeyDomain(entry.key);
  }

  _AtlasPage _pageForEntry(TerminalGlyphAtlasEntry entry) => _pages.singleWhere(
    (_AtlasPage page) =>
        page.pageId == entry.pageId &&
        page.pageGeneration == entry.pageGeneration,
    orElse: () => throw StateError('atlas page generation is stale'),
  );

  void _touch(TerminalGlyphAtlasEntry entry) {
    entry._lastUse = _takeUseClock();
  }

  int _takeEntryId() => _takeCounter(() => _nextEntryId++, 'entry ID');

  static int _cellGlyphStorageId(TerminalCellGlyphAtlasKey key) {
    const int radix = TerminalCellGlyphRasterLimits.maximumDimension + 1;
    return (((key.scalar * radix + key.cellWidth) * radix + key.cellHeight) *
            radix) +
        key.lineThickness;
  }

  int _takeKittySyntheticGlyphId() {
    final int value = _nextKittySyntheticGlyphId--;
    if (value <= -0x7fffffffffffffff) {
      throw const TerminalGlyphAtlasCapacityException(
        'Kitty image atlas identity exhausted',
      );
    }
    return value;
  }

  int _takePageId() => _takeCounter(() => _nextPageId++, 'page ID');
  int _takePageGeneration() =>
      _takeCounter(() => _nextPageGeneration++, 'page generation');
  int _takeUseClock() => _takeCounter(() => _useClock++, 'LRU clock');

  int _takeCounter(int Function() take, String name) {
    final int value = take();
    if (value >= 0x7fffffffffffffff) {
      throw TerminalGlyphAtlasCapacityException('$name exhausted');
    }
    return value;
  }

  void _incrementResourceGeneration() {
    if (_resourceGeneration >= 0x7fffffffffffffff) {
      throw const TerminalGlyphAtlasCapacityException(
        'resource generation exhausted',
      );
    }
    _resourceGeneration++;
  }
}

const int _maximumAtlasMetric = 0x7fffffffffffffff;

int _saturatingAtlasIncrement(int value) =>
    value == _maximumAtlasMetric ? value : value + 1;

int _saturatingAtlasAdd(int left, int right) =>
    left >= _maximumAtlasMetric - right ? _maximumAtlasMetric : left + right;

final class _AtlasPlacement {
  const _AtlasPlacement(this.page, this.rect);
  final _AtlasPage page;
  final _AtlasRect rect;
}

final class _AtlasRect {
  const _AtlasRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
  int get area => width * height;
}

final class _AtlasPage {
  _AtlasPage({
    required this.pageId,
    required this.pageGeneration,
    required this.format,
    required this.width,
    required this.height,
  }) : rowStride = width * _bytesPerPixel(format),
       pixels = Uint8List(width * height * _bytesPerPixel(format)),
       freeRects = <_AtlasRect>[_AtlasRect(0, 0, width, height)];

  final int pageId;
  final int pageGeneration;
  final TerminalGlyphAtlasFormat format;
  final int width;
  final int height;
  final int rowStride;
  final Uint8List pixels;
  final List<_AtlasRect> freeRects;
  final Set<int> entryIds = {};

  _AtlasRect? allocate(int width, int height) {
    var best = -1;
    for (int index = 0; index < freeRects.length; index++) {
      final _AtlasRect candidate = freeRects[index];
      if (width <= candidate.width &&
          height <= candidate.height &&
          (best < 0 || _better(candidate, freeRects[best]))) {
        best = index;
      }
    }
    if (best < 0) return null;
    final _AtlasRect free = freeRects.removeAt(best);
    final _AtlasRect allocated = _AtlasRect(free.x, free.y, width, height);
    if (free.width > width) {
      freeRects.add(
        _AtlasRect(free.x + width, free.y, free.width - width, height),
      );
    }
    if (free.height > height) {
      freeRects.add(
        _AtlasRect(free.x, free.y + height, free.width, free.height - height),
      );
    }
    _sortFreeRects();
    return allocated;
  }

  bool _better(_AtlasRect a, _AtlasRect b) {
    if (a.area != b.area) return a.area < b.area;
    if (a.y != b.y) return a.y < b.y;
    if (a.x != b.x) return a.x < b.x;
    if (a.height != b.height) return a.height < b.height;
    return a.width < b.width;
  }

  void free(_AtlasRect rect) {
    freeRects.add(rect);
    var merged = true;
    while (merged) {
      merged = false;
      for (int first = 0; first < freeRects.length && !merged; first++) {
        for (int second = first + 1; second < freeRects.length; second++) {
          final _AtlasRect? combined = _merge(
            freeRects[first],
            freeRects[second],
          );
          if (combined != null) {
            freeRects.removeAt(second);
            freeRects[first] = combined;
            merged = true;
            break;
          }
        }
      }
    }
    _sortFreeRects();
  }

  _AtlasRect? _merge(_AtlasRect a, _AtlasRect b) {
    if (a.y == b.y && a.height == b.height) {
      if (a.x + a.width == b.x)
        return _AtlasRect(a.x, a.y, a.width + b.width, a.height);
      if (b.x + b.width == a.x)
        return _AtlasRect(b.x, b.y, a.width + b.width, a.height);
    }
    if (a.x == b.x && a.width == b.width) {
      if (a.y + a.height == b.y)
        return _AtlasRect(a.x, a.y, a.width, a.height + b.height);
      if (b.y + b.height == a.y)
        return _AtlasRect(b.x, b.y, a.width, a.height + b.height);
    }
    return null;
  }

  void clear(_AtlasRect rect) {
    final int bpp = _bytesPerPixel(format);
    for (int row = rect.y; row < rect.y + rect.height; row++) {
      final int start = row * rowStride + rect.x * bpp;
      pixels.fillRange(start, start + rect.width * bpp, 0);
    }
  }

  void _sortFreeRects() {
    freeRects.sort((_AtlasRect a, _AtlasRect b) {
      if (a.y != b.y) return a.y.compareTo(b.y);
      if (a.x != b.x) return a.x.compareTo(b.x);
      if (a.height != b.height) return a.height.compareTo(b.height);
      return a.width.compareTo(b.width);
    });
  }
}

TerminalGlyphAtlasFormat _atlasFormat(TerminalGlyphPixelFormat format) =>
    format == TerminalGlyphPixelFormat.alpha8
    ? TerminalGlyphAtlasFormat.alpha8
    : TerminalGlyphAtlasFormat.rgba8Straight;

int _bytesPerPixel(TerminalGlyphAtlasFormat format) =>
    format == TerminalGlyphAtlasFormat.alpha8 ? 1 : 4;

bool _bytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
