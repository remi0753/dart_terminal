import 'dart:collection';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'glyph_atlas.dart';
import 'reference_renderer.dart';

enum TerminalGlyphAtlasSyncDisposition { synchronized, backpressured }

/// Product-owned bridge between the Dart glyph atlas and native Metal slices.
///
/// Global atlas page IDs are mapped to stable, format-local native slices.
/// Copied dirty rectangles remain queued here until native accepts them.
final class TerminalGlyphAtlasMetalBridge {
  TerminalGlyphAtlasMetalBridge({required this.atlas, required this.renderer}) {
    if (atlas.limits.pageWidth != renderer.config.atlasWidth ||
        atlas.limits.pageHeight != renderer.config.atlasHeight ||
        atlas.limits.maximumAlphaPages > renderer.config.maximumAlphaPages ||
        atlas.limits.maximumColorPages > renderer.config.maximumColorPages) {
      throw ArgumentError('atlas limits are outside the renderer domain');
    }
    _reconcile(atlas.snapshot());
    _pendingUploads.addAll(atlas.snapshotUploads());
    // The bridge becomes the sole consumer of incremental dirty rectangles.
    // Full page copies above already contain this initial dirty state.
    atlas.takePendingUploads();
  }

  final TerminalGlyphAtlas atlas;
  final TerminalMetalRenderer renderer;
  final Map<int, int> _alphaSlots = <int, int>{};
  final Map<int, int> _colorSlots = <int, int>{};
  final Queue<TerminalGlyphAtlasUpload> _pendingUploads =
      Queue<TerminalGlyphAtlasUpload>();
  final SplayTreeSet<int> _pinnedSubmissionTokens = SplayTreeSet<int>();
  int _nativeAtlasGeneration = 0;
  int _nativeResetEpoch = -1;
  int _nativeCatalogGeneration = 0;
  int _nativeScale16_16 = 0;

  int get nativeAtlasGeneration => _nativeAtlasGeneration;
  int get pendingUploadCount => _pendingUploads.length;
  int get pinnedSubmissionCount => _pinnedSubmissionTokens.length;
  bool get isSynchronized =>
      _nativeAtlasGeneration == atlas.resourceGeneration &&
      _nativeResetEpoch == atlas.resetEpoch &&
      _nativeCatalogGeneration == atlas.catalogGeneration &&
      _nativeScale16_16 == atlas.scale16_16 &&
      _pendingUploads.isEmpty &&
      atlas.pendingUploadPageCount == 0;

  TerminalGlyphAtlasSyncDisposition synchronize() {
    TerminalGlyphAtlasSnapshot snapshot = atlas.snapshot();
    if (_nativeAtlasGeneration == 0 ||
        _nativeResetEpoch != snapshot.resetEpoch ||
        _nativeCatalogGeneration != snapshot.catalogGeneration ||
        _nativeScale16_16 != snapshot.scale16_16) {
      final TerminalGlyphAtlasSyncDisposition? reset = _resetNative(snapshot);
      if (reset != null) return reset;
    }
    _reconcile(snapshot);
    while (true) {
      if (_pendingUploads.isEmpty) {
        _pendingUploads.addAll(atlas.takePendingUploads());
        if (_pendingUploads.isEmpty) {
          snapshot = atlas.snapshot();
          if (_nativeAtlasGeneration != snapshot.resourceGeneration) {
            final TerminalGlyphAtlasSyncDisposition? reset = _resetNative(
              snapshot,
            );
            if (reset != null) return reset;
            continue;
          }
          return TerminalGlyphAtlasSyncDisposition.synchronized;
        }
        snapshot = atlas.snapshot();
        _reconcile(snapshot);
      }
      final TerminalGlyphAtlasUpload upload = _pendingUploads.first;
      final TerminalGlyphAtlasPageDescriptor? page = _pageForUpload(
        snapshot,
        upload,
      );
      if (page == null) {
        _pendingUploads.removeFirst();
        continue;
      }
      final int pageIndex = _slotMap(upload.format)[upload.pageId]!;
      final TerminalMetalUploadDisposition disposition = renderer.uploadAtlas(
        TerminalMetalAtlasUpload(
          rendererGeneration: renderer.generation,
          atlasGeneration: upload.resourceGeneration,
          pageGeneration: upload.pageGeneration,
          format: _metalFormat(upload.format),
          pageIndex: pageIndex,
          x: upload.x,
          y: upload.y,
          width: upload.width,
          height: upload.height,
          rowStride: upload.rowStride,
          bytes: upload.copyBytes(),
        ),
      );
      switch (disposition) {
        case TerminalMetalUploadDisposition.uploaded:
          _nativeAtlasGeneration = upload.resourceGeneration;
          _pendingUploads.removeFirst();
        case TerminalMetalUploadDisposition.backpressured:
          return TerminalGlyphAtlasSyncDisposition.backpressured;
        case TerminalMetalUploadDisposition.stale:
          throw StateError('native atlas generation is ahead of its bridge');
      }
    }
  }

  TerminalMetalInstance? glyphInstance(
    TerminalGlyphAtlasEntry entry, {
    required int x,
    required int y,
    TerminalReferenceColor maskColor = const TerminalReferenceColor(0xffffffff),
  }) {
    atlas.validateEntry(
      entry,
      expectedResourceGeneration: atlas.resourceGeneration,
    );
    if (entry.isEmpty) return null;
    final int? pageIndex = _slotMap(entry.format)[entry.pageId];
    if (pageIndex == null) {
      throw StateError('atlas page has not been mapped to Metal');
    }
    if (_pendingUploads.isNotEmpty || atlas.pendingUploadPageCount != 0) {
      throw StateError('atlas uploads must be synchronized before encoding');
    }
    if (_nativeAtlasGeneration == 0) {
      throw StateError('native atlas has no published generation');
    }
    return TerminalMetalInstance.glyph(
      format: _metalFormat(entry.format),
      x: x,
      y: y,
      width: entry.width,
      height: entry.height,
      atlasX: entry.x,
      atlasY: entry.y,
      colorRgba: maskColor.rgba,
      pageIndex: pageIndex,
      pageGeneration: entry.pageGeneration,
    );
  }

  TerminalMetalSubmissionResult submit(
    TerminalMetalFrame frame, {
    required Iterable<TerminalGlyphAtlasEntry> glyphEntries,
  }) {
    if (_pendingUploads.isNotEmpty || atlas.pendingUploadPageCount != 0) {
      throw StateError('atlas uploads must be synchronized before submission');
    }
    if (frame.atlasGeneration != nativeAtlasGeneration) {
      throw StateError('frame uses a stale native atlas generation');
    }
    final LinkedHashSet<TerminalGlyphAtlasEntry> retained = LinkedHashSet();
    for (final TerminalGlyphAtlasEntry entry in glyphEntries) {
      atlas.validateEntry(
        entry,
        expectedResourceGeneration: atlas.resourceGeneration,
      );
      retained.add(entry);
    }
    final TerminalMetalSubmissionResult result = renderer.submit(frame);
    if (result.isAccepted && retained.isNotEmpty) {
      atlas.pinForSubmission(result.submissionToken, retained);
      _pinnedSubmissionTokens.add(result.submissionToken);
    }
    return result;
  }

  TerminalMetalRendererState retireCompletedSubmissions() {
    final TerminalMetalRendererState snapshot = renderer.state();
    while (_pinnedSubmissionTokens.isNotEmpty &&
        _pinnedSubmissionTokens.first <= snapshot.retiredThroughToken) {
      final int token = _pinnedSubmissionTokens.first;
      _pinnedSubmissionTokens.remove(token);
      atlas.completeSubmission(token);
    }
    return snapshot;
  }

  TerminalGlyphAtlasSyncDisposition? _resetNative(
    TerminalGlyphAtlasSnapshot snapshot,
  ) {
    final TerminalMetalUploadDisposition disposition = renderer.resetAtlas(
      atlasGeneration: snapshot.resourceGeneration,
    );
    switch (disposition) {
      case TerminalMetalUploadDisposition.uploaded:
        _nativeAtlasGeneration = snapshot.resourceGeneration;
        _nativeResetEpoch = snapshot.resetEpoch;
        _nativeCatalogGeneration = snapshot.catalogGeneration;
        _nativeScale16_16 = snapshot.scale16_16;
        _alphaSlots.clear();
        _colorSlots.clear();
        _pendingUploads.clear();
        _reconcile(snapshot);
        _pendingUploads.addAll(atlas.snapshotUploads());
        // Full page copies above include every outstanding dirty rectangle.
        atlas.takePendingUploads();
        return null;
      case TerminalMetalUploadDisposition.backpressured:
        return TerminalGlyphAtlasSyncDisposition.backpressured;
      case TerminalMetalUploadDisposition.stale:
        throw StateError('native atlas generation is ahead of its bridge');
    }
  }

  void _reconcile(TerminalGlyphAtlasSnapshot snapshot) {
    _validatePages(snapshot);
    _reconcileFormat(
      snapshot,
      TerminalGlyphAtlasFormat.alpha8,
      _alphaSlots,
      renderer.config.maximumAlphaPages,
    );
    _reconcileFormat(
      snapshot,
      TerminalGlyphAtlasFormat.rgba8Straight,
      _colorSlots,
      renderer.config.maximumColorPages,
    );
  }

  void _validatePages(TerminalGlyphAtlasSnapshot snapshot) {
    final Set<int> pageIds = <int>{};
    for (final TerminalGlyphAtlasPageDescriptor page in snapshot.pages) {
      if (!pageIds.add(page.pageId) ||
          page.pageGeneration <= 0 ||
          page.pageGeneration > 0xffffffff ||
          page.width != renderer.config.atlasWidth ||
          page.height != renderer.config.atlasHeight ||
          page.rowStride != page.width * _bytesPerPixel(page.format)) {
        throw StateError('atlas snapshot cannot be represented by Metal');
      }
    }
  }

  void _reconcileFormat(
    TerminalGlyphAtlasSnapshot snapshot,
    TerminalGlyphAtlasFormat format,
    Map<int, int> slots,
    int limit,
  ) {
    final List<int> livePageIds =
        snapshot.pages
            .where(
              (TerminalGlyphAtlasPageDescriptor page) => page.format == format,
            )
            .map((TerminalGlyphAtlasPageDescriptor page) => page.pageId)
            .toList()
          ..sort();
    final Set<int> live = livePageIds.toSet();
    slots.removeWhere((int pageId, int _) => !live.contains(pageId));
    for (final int pageId in livePageIds) {
      if (slots.containsKey(pageId)) continue;
      int? available;
      for (int candidate = 0; candidate < limit; candidate++) {
        if (!slots.containsValue(candidate)) {
          available = candidate;
          break;
        }
      }
      if (available == null) {
        throw StateError('native Metal atlas slice limit exhausted');
      }
      slots[pageId] = available;
    }
  }

  TerminalGlyphAtlasPageDescriptor? _pageForUpload(
    TerminalGlyphAtlasSnapshot snapshot,
    TerminalGlyphAtlasUpload upload,
  ) {
    for (final TerminalGlyphAtlasPageDescriptor page in snapshot.pages) {
      if (page.pageId == upload.pageId &&
          page.pageGeneration == upload.pageGeneration &&
          page.format == upload.format) {
        return page;
      }
    }
    return null;
  }

  Map<int, int> _slotMap(TerminalGlyphAtlasFormat format) =>
      format == TerminalGlyphAtlasFormat.alpha8 ? _alphaSlots : _colorSlots;
}

TerminalMetalAtlasFormat _metalFormat(TerminalGlyphAtlasFormat format) =>
    format == TerminalGlyphAtlasFormat.alpha8
    ? TerminalMetalAtlasFormat.alpha8
    : TerminalMetalAtlasFormat.rgba8Straight;

int _bytesPerPixel(TerminalGlyphAtlasFormat format) =>
    format == TerminalGlyphAtlasFormat.alpha8 ? 1 : 4;
