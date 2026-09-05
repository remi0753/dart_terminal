import 'dart:collection';
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'reference_renderer.dart';

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
  bool get isPinned => _pinCount != 0;
  int get pinCount => _pinCount;
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
    required this.catalogGeneration,
    required this.scale16_16,
    required List<TerminalGlyphAtlasPageDescriptor> pages,
  }) : pages = List<TerminalGlyphAtlasPageDescriptor>.unmodifiable(pages);

  final int resourceGeneration;
  final int catalogGeneration;
  final int scale16_16;
  final List<TerminalGlyphAtlasPageDescriptor> pages;
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
  final List<_AtlasPage> _pages = [];
  final Map<int, _AtlasRect> _dirtyPageRects = {};
  final Map<int, List<TerminalGlyphAtlasEntry>> _pins = {};

  int _catalogGeneration;
  int _scale16_16;
  int _resourceGeneration = 1;
  int _nextEntryId = 1;
  int _nextPageId = 1;
  int _nextPageGeneration = 1;
  int _useClock = 1;
  int _retainedBytes = 0;
  int _evictionCount = 0;
  int _hitCount = 0;
  int _missCount = 0;

  int get catalogGeneration => _catalogGeneration;
  int get scale16_16 => _scale16_16;
  double get scale => _scale16_16 / 65536.0;
  int get resourceGeneration => _resourceGeneration;
  int get entryCount => _entries.length;
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
  int get hitCount => _hitCount;
  int get missCount => _missCount;
  int get livePinCount => _pins.length;
  int get pendingUploadPageCount => _dirtyPageRects.length;

  TerminalGlyphAtlasEntry? lookup(TerminalGlyphAtlasKey key) {
    _validateKeyDomain(key);
    final TerminalGlyphAtlasEntry? entry = _entries[key];
    if (entry == null) {
      _missCount++;
      return null;
    }
    _hitCount++;
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
      catalogGeneration: _catalogGeneration,
      scale16_16: _scale16_16,
      pages: pages,
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
    if (_pins.isNotEmpty) {
      throw StateError('cannot reset an atlas with pinned submissions');
    }
    if (catalogGeneration <= 0) {
      throw RangeError.value(
        catalogGeneration,
        'catalogGeneration',
        'must be positive',
      );
    }
    _catalogGeneration = catalogGeneration;
    _scale16_16 = TerminalRasterBufferV1.scaleToFixed(scale);
    _entries.clear();
    _pages.clear();
    _dirtyPageRects.clear();
    _retainedBytes = 0;
    _incrementResourceGeneration();
  }

  TerminalGlyphAtlasEntry _insert(
    TerminalGlyphAtlasKey key,
    TerminalRasterizedGlyph glyph,
  ) {
    final TerminalGlyphAtlasFormat format = _atlasFormat(glyph.format);
    final int bpp = _bytesPerPixel(format);
    if ((glyph.width == 0) != (glyph.height == 0) ||
        glyph.width > limits.pageWidth - limits.gutter * 2 ||
        glyph.height > limits.pageHeight - limits.gutter * 2 ||
        glyph.rowStride != glyph.width * bpp ||
        glyph.byteLength != glyph.rowStride * glyph.height) {
      throw TerminalGlyphAtlasCapacityException(
        'glyph ${glyph.faceId}:${glyph.glyphId} does not fit an atlas page',
      );
    }
    _ensureEntryCapacity(format);
    _AtlasPage? page;
    _AtlasRect? allocation;
    if (glyph.width != 0) {
      final int allocationWidth = glyph.width + limits.gutter * 2;
      final int allocationHeight = glyph.height + limits.gutter * 2;
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
      format: format,
      pageId: page?.pageId ?? 0,
      pageGeneration: page?.pageGeneration ?? 0,
      x: allocation == null ? 0 : allocation.x + limits.gutter,
      y: allocation == null ? 0 : allocation.y + limits.gutter,
      width: glyph.width,
      height: glyph.height,
      rowStride: glyph.rowStride,
      originX: glyph.originX,
      originY: glyph.originY,
      allocation: allocation,
      lastUse: _takeUseClock(),
    );
    if (page != null && allocation != null) {
      _copyRasterIntoPage(page, entry, glyph.copyPixels());
      page.entryIds.add(entry.entryId);
      _markDirty(page, _AtlasRect(entry.x, entry.y, entry.width, entry.height));
    }
    _entries[key] = entry;
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

  void _validateEntry(TerminalGlyphAtlasEntry entry) {
    if (!identical(entry._owner, _owner) ||
        !identical(_entries[entry.key], entry)) {
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
