import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_accessibility_presentation.dart';
import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_screen_set.dart';
import '../terminal_core/terminal_style.dart';
import '../terminal_core/terminal_unicode.dart';
import '../terminal_input/terminal_preedit.dart';
import 'frame_scheduler.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'reference_renderer.dart';
import 'terminal_cell_glyph.dart';
import 'terminal_overlay.dart';
import 'terminal_render_model.dart';

/// Signals that atlas uploads could not be published during this frame build.
///
/// The render owner may retry the newest model later. No partially synchronized
/// frame is returned or submitted.
final class TerminalMetalCompositionBackpressureException implements Exception {
  const TerminalMetalCompositionBackpressureException();

  @override
  String toString() => 'TerminalMetalCompositionBackpressureException';
}

/// Immutable result of composing one terminal screen model for Metal.
final class TerminalScreenMetalComposition {
  TerminalScreenMetalComposition({
    required this.scheduledFrame,
    required Iterable<TerminalMetalInstance> instances,
    required this.shapedRunCount,
    required this.cellGlyphCount,
    required this.renderedCellCount,
    required this.preeditCellCount,
    required this.hyperlinkHoverCellCount,
    required this.kittyImageCount,
    required this.kittyPlacementCount,
    required this.kittyTileCount,
  }) : instances = List<TerminalMetalInstance>.unmodifiable(instances);

  final TerminalScheduledMetalFrame scheduledFrame;
  final List<TerminalMetalInstance> instances;
  final int shapedRunCount;
  final int cellGlyphCount;
  final int renderedCellCount;
  final int preeditCellCount;
  final int hyperlinkHoverCellCount;
  final int kittyImageCount;
  final int kittyPlacementCount;
  final int kittyTileCount;
}

/// Canonical screen-grid to Metal composition boundary.
///
/// The damage render model is the only visible-text source. Control sequences
/// have already been consumed by the VT parser and are represented here only
/// by cell colors and style IDs. CoreText is called once per compatible run,
/// never once per cell.
final class TerminalScreenMetalCompositor {
  TerminalScreenMetalCompositor({
    required this.catalog,
    required this.shapingCache,
    required this.atlas,
    required this.bridge,
    required this.styleTable,
    required this.palette,
    required this.graphemeTable,
    this.backgroundOpacity = 1,
    this.accessibilityPresentation =
        const TerminalAccessibilityPresentation.standard(),
  }) {
    if (!identical(shapingCache.catalog, catalog) ||
        !identical(bridge.atlas, atlas) ||
        atlas.catalogGeneration != catalog.generation) {
      throw ArgumentError('Metal composition resources do not share a domain');
    }
    if (!backgroundOpacity.isFinite ||
        backgroundOpacity < 0 ||
        backgroundOpacity > 1) {
      throw RangeError.range(backgroundOpacity, 0, 1, 'backgroundOpacity');
    }
  }

  final TerminalFontCatalog catalog;
  final TerminalShapingCache shapingCache;
  final TerminalGlyphAtlas atlas;
  final TerminalGlyphAtlasMetalBridge bridge;
  final TerminalStyleTable styleTable;
  final TerminalPalette palette;
  final TerminalGraphemeTable graphemeTable;
  final double backgroundOpacity;
  final TerminalAccessibilityPresentation accessibilityPresentation;

  /// Keeps inactive panes legible while making their background subordinate.
  static const double inactivePaneBackgroundBrightness = 0.82;

  TerminalScreenMetalComposition compose(
    TerminalRenderModel model, {
    required int frameGeneration,
    required int viewportWidth,
    required int viewportHeight,
    required TerminalFramePresentation presentation,
    TerminalPreeditLayout? preedit,
    TerminalSelectionProjection? selection,
    TerminalGridOverlayProjection? gridOverlay,
    TerminalKittyViewportSnapshot? kittyImages,
    int hoveredHyperlinkId = 0,
    int contentOffsetX = 0,
    int contentOffsetY = 0,
    int? contentViewportWidth,
    int? contentViewportHeight,
  }) {
    if (!model.isInitialized) {
      throw StateError('Metal composition requires an initialized model');
    }
    if (model.requiredResourceGeneration > atlas.resourceGeneration) {
      throw StateError('Metal composition resources trail screen damage');
    }
    if (hoveredHyperlinkId < 0 ||
        hoveredHyperlinkId > TerminalScreen.maxResourceId) {
      throw RangeError.range(
        hoveredHyperlinkId,
        0,
        TerminalScreen.maxResourceId,
        'hoveredHyperlinkId',
      );
    }
    final int contentWidth =
        contentViewportWidth ?? viewportWidth - contentOffsetX * 2;
    final int contentHeight =
        contentViewportHeight ?? viewportHeight - contentOffsetY * 2;
    if (contentOffsetX < 0 ||
        contentOffsetY < 0 ||
        contentWidth <= 0 ||
        contentHeight <= 0 ||
        contentOffsetX + contentWidth > viewportWidth ||
        contentOffsetY + contentHeight > viewportHeight) {
      throw ArgumentError('terminal content rectangle exceeds the viewport');
    }

    final double scale = atlas.scale;
    final TerminalFontCatalogMetrics metrics = catalog.metrics;
    final int opaqueDefaultBackground = _rgba(
      palette.resolveToken(0, foreground: false),
    );
    final int configuredFrameBackground = _withAlpha(
      opaqueDefaultBackground,
      (backgroundOpacity * 255).round(),
    );
    final int frameBackground = presentation.isPaneActive
        ? configuredFrameBackground
        : _scaleRgbPreservingAlpha(
            configuredFrameBackground,
            inactivePaneBackgroundBrightness,
          );
    final List<TerminalMetalInstance> backgrounds = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> overlays = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> glyphInstances =
        <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> kittyImagesBelowBackground =
        <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> kittyImagesBelowText =
        <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> kittyImagesAboveText =
        <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> decorations = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> cursors = <TerminalMetalInstance>[];
    final List<_TerminalTextRun> textRuns = <_TerminalTextRun>[];
    final List<_TerminalCellGlyphPlacement> cellGlyphs =
        <_TerminalCellGlyphPlacement>[];
    var renderedCellCount = 0;
    var hyperlinkHoverCellCount = 0;

    for (int row = 0; row < model.rows; row++) {
      var column = 0;
      while (column < model.columns) {
        final int widthFlags = model.widthFlagsAt(row, column);
        final int width = widthFlags & TerminalCellFlags.widthMask;
        if (width == TerminalCellFlags.continuation) {
          column++;
          continue;
        }
        final int cellColumns = width == TerminalCellFlags.wide ? 2 : 1;
        final int styleId = model.styleAt(row, column);
        final int attributes = styleTable.attributesAt(styleId);
        final _TerminalCellColors colors = _colors(
          model.foregroundAt(row, column),
          model.backgroundAt(row, column),
          attributes,
        );
        final int left = _columnPixel(column, metrics, scale);
        final int right = _columnPixel(
          math.min(model.columns, column + cellColumns),
          metrics,
          scale,
        );
        final int top = _rowPixel(row, metrics, scale);
        final int bottom = _rowPixel(row + 1, metrics, scale);
        if (colors.backgroundRgba != opaqueDefaultBackground) {
          _addClippedSolid(
            backgrounds,
            kind: TerminalMetalInstanceKind.cellBackground,
            x: left,
            y: top,
            width: right - left,
            height: bottom - top,
            colorRgba: presentation.isPaneActive
                ? colors.backgroundRgba
                : _scaleRgbPreservingAlpha(
                    colors.backgroundRgba,
                    inactivePaneBackgroundBrightness,
                  ),
            viewportWidth: contentWidth,
            viewportHeight: contentHeight,
          );
        }

        final int content = model.contentAt(row, column);
        if (content != 0) {
          renderedCellCount++;
          final int underlineColor = styleTable.underlineColorAt(styleId);
          _addDecorations(
            decorations,
            attributes: attributes,
            colorRgba: colors.foregroundRgba,
            underlineColorRgba: underlineColor == 0
                ? colors.foregroundRgba
                : _rgba(palette.resolveToken(underlineColor, foreground: true)),
            left: left,
            right: right,
            row: row,
            metrics: metrics,
            scale: scale,
            viewportWidth: contentWidth,
            viewportHeight: contentHeight,
          );
        }
        if (hoveredHyperlinkId != 0 &&
            model.hyperlinkAt(row, column) == hoveredHyperlinkId) {
          hyperlinkHoverCellCount += cellColumns;
          _addClippedSolid(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            x: left,
            y: _underlinePixel(row, metrics, scale),
            width: right - left,
            height: accessibilityPresentation.differentiateWithoutColor
                ? math.max(2, (metrics.underlineThickness * scale).round() * 2)
                : math.max(1, (metrics.underlineThickness * scale).round()),
            colorRgba: colors.foregroundRgba,
            viewportWidth: contentWidth,
            viewportHeight: contentHeight,
          );
        }
        column += cellColumns;
      }
    }

    if (selection != null) {
      for (final TerminalSelectionSpan span in selection.spans) {
        if (span.row >= model.rows || span.endColumn > model.columns) {
          throw StateError('selection projection exceeds the render grid');
        }
        final int left = _columnPixel(span.startColumn, metrics, scale);
        final int right = _columnPixel(span.endColumn, metrics, scale);
        final int top = _rowPixel(span.row, metrics, scale);
        final int bottom = _rowPixel(span.row + 1, metrics, scale);
        _addClippedSolid(
          overlays,
          kind: TerminalMetalInstanceKind.selection,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
          colorRgba: accessibilityPresentation.increaseContrast
              ? 0xffffff58
              : 0x4a90e260,
          viewportWidth: contentWidth,
          viewportHeight: contentHeight,
        );
        if (accessibilityPresentation.increaseContrast ||
            accessibilityPresentation.differentiateWithoutColor) {
          final int thickness = math.max(1, scale.round());
          _addSelectionEdges(
            decorations,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            thickness: thickness,
            viewportWidth: contentWidth,
            viewportHeight: contentHeight,
          );
        }
      }
    }

    if (gridOverlay != null) {
      _addGridOverlay(
        gridOverlay,
        model: model,
        overlays: overlays,
        decorations: decorations,
        metrics: metrics,
        scale: scale,
        defaultBackground: opaqueDefaultBackground,
        viewportWidth: contentWidth,
        viewportHeight: contentHeight,
      );
    }

    for (int row = 0; row < model.rows; row++) {
      final _TerminalCursorShapingBreak? cursorBreak = _cursorShapingBreak(
        model,
        row,
      );
      var column = 0;
      while (column < model.columns) {
        final int widthFlags = model.widthFlagsAt(row, column);
        final int width = widthFlags & TerminalCellFlags.widthMask;
        if (width == TerminalCellFlags.continuation) {
          column++;
          continue;
        }
        final int cellColumns = width == TerminalCellFlags.wide ? 2 : 1;
        final int content = model.contentAt(row, column);
        final int attributes = styleTable.attributesAt(
          model.styleAt(row, column),
        );
        if (content == 0 ||
            TerminalStyleAttributes.has(
              attributes,
              TerminalStyleAttributes.conceal,
            )) {
          column += cellColumns;
          continue;
        }

        final TerminalFontStyle fontStyle = _fontStyle(attributes);
        final int foregroundRgba = _colors(
          model.foregroundAt(row, column),
          model.backgroundAt(row, column),
          attributes,
        ).foregroundRgba;
        final int? cellGlyphScalar = _cellGlyphScalar(
          content,
          widthFlags,
          cellColumns,
        );
        if (cellGlyphScalar != null) {
          cellGlyphs.add(
            _cellGlyphPlacement(
              scalar: cellGlyphScalar,
              row: row,
              column: column,
              colorRgba: foregroundRgba,
              metrics: metrics,
              scale: scale,
            ),
          );
          column += cellColumns;
          continue;
        }
        final int runStart = column;
        final _TerminalTextRunBuilder run = _TerminalTextRunBuilder(
          row: row,
          startColumn: runStart,
          style: fontStyle,
        );
        int nextColumn = column;
        while (nextColumn < model.columns) {
          if (nextColumn != runStart &&
              cursorBreak != null &&
              (nextColumn == cursorBreak.startColumn ||
                  runStart == cursorBreak.startColumn &&
                      nextColumn == cursorBreak.endColumn)) {
            break;
          }
          final int nextFlags = model.widthFlagsAt(row, nextColumn);
          final int nextWidth = nextFlags & TerminalCellFlags.widthMask;
          if (nextWidth == TerminalCellFlags.continuation) break;
          final int nextContent = model.contentAt(row, nextColumn);
          final int nextAttributes = styleTable.attributesAt(
            model.styleAt(row, nextColumn),
          );
          final _TerminalCellColors nextColors = _colors(
            model.foregroundAt(row, nextColumn),
            model.backgroundAt(row, nextColumn),
            nextAttributes,
          );
          if (nextContent == 0 ||
              TerminalStyleAttributes.has(
                nextAttributes,
                TerminalStyleAttributes.conceal,
              ) ||
              _fontStyle(nextAttributes) != fontStyle ||
              nextColors.foregroundRgba != foregroundRgba) {
            break;
          }
          final int nextCellColumns = nextWidth == TerminalCellFlags.wide
              ? 2
              : 1;
          if (_cellGlyphScalar(nextContent, nextFlags, nextCellColumns) !=
              null) {
            break;
          }
          run.add(_cellText(nextContent, nextFlags), nextCellColumns);
          nextColumn += nextCellColumns;
        }
        textRuns.add(run.build(foregroundRgba));
        column = nextColumn;
      }
    }

    if (presentation.visualBellActive) {
      if (accessibilityPresentation.differentiateWithoutColor) {
        _addOutline(
          overlays,
          kind: TerminalMetalInstanceKind.selection,
          left: 0,
          top: 0,
          right: contentWidth,
          bottom: contentHeight,
          thickness: math.max(2, scale.round() * 2),
          colorRgba: _contrastingRgba(opaqueDefaultBackground),
          viewportWidth: contentWidth,
          viewportHeight: contentHeight,
        );
      } else {
        _addClippedSolid(
          overlays,
          kind: TerminalMetalInstanceKind.selection,
          x: 0,
          y: 0,
          width: contentWidth,
          height: contentHeight,
          colorRgba: accessibilityPresentation.increaseContrast
              ? 0xffffff58
              : 0xffffff30,
          viewportWidth: contentWidth,
          viewportHeight: contentHeight,
        );
      }
    }

    if (preedit != null) {
      _addPreedit(
        preedit,
        overlays: overlays,
        decorations: decorations,
        textRuns: textRuns,
        metrics: metrics,
        scale: scale,
        viewportWidth: contentWidth,
        viewportHeight: contentHeight,
      );
    }

    final List<_TerminalShapedRun> shapedRuns = <_TerminalShapedRun>[];
    final Map<TerminalCellGlyphAtlasKey, TerminalCellGlyphRasterRequest>
    missingCellGlyphs =
        <TerminalCellGlyphAtlasKey, TerminalCellGlyphRasterRequest>{};
    for (final _TerminalCellGlyphPlacement placement in cellGlyphs) {
      final TerminalCellGlyphAtlasKey key =
          TerminalCellGlyphAtlasKey.fromRequest(
            catalogGeneration: catalog.generation,
            scale16_16: atlas.scale16_16,
            request: placement.request,
          );
      if (atlas.lookupCellGlyph(key) == null) {
        missingCellGlyphs[key] = placement.request;
      }
    }
    final Map<TerminalGlyphAtlasKey, TerminalGlyphRasterRequest> missing =
        <TerminalGlyphAtlasKey, TerminalGlyphRasterRequest>{};
    for (final _TerminalTextRun run in textRuns) {
      final TerminalShapedText shaped = shapingCache.shape(
        run.text,
        style: run.style,
      );
      shapedRuns.add(_TerminalShapedRun(run, shaped));
      for (final TerminalShapedGlyph glyph in shaped.glyphs) {
        final TerminalGlyphAtlasKey key = TerminalGlyphAtlasKey(
          catalogGeneration: catalog.generation,
          faceId: glyph.faceId,
          glyphId: glyph.glyphId,
          scale16_16: atlas.scale16_16,
        );
        if (atlas.lookup(key) == null) {
          missing[key] = TerminalGlyphRasterRequest(
            faceId: glyph.faceId,
            glyphId: glyph.glyphId,
          );
        }
      }
    }
    if (missing.length + missingCellGlyphs.length >
        atlas.limits.maximumEntries) {
      throw const TerminalGlyphAtlasCapacityException(
        'visible glyph set exceeds the bounded atlas entry limit',
      );
    }
    for (final TerminalCellGlyphRasterRequest request
        in missingCellGlyphs.values) {
      atlas.ingestCellGlyph(TerminalCellGlyphRasterizer.rasterize(request));
    }
    final List<TerminalGlyphRasterRequest> requests = missing.values.toList();
    for (
      int offset = 0;
      offset < requests.length;
      offset += TerminalRasterBufferV1.maximumGlyphs
    ) {
      final int end = math.min(
        requests.length,
        offset + TerminalRasterBufferV1.maximumGlyphs,
      );
      atlas.ingest(
        catalog.rasterize(requests.sublist(offset, end), scale: scale),
      );
    }
    if (bridge.synchronize() ==
        TerminalGlyphAtlasSyncDisposition.backpressured) {
      throw const TerminalMetalCompositionBackpressureException();
    }

    final TerminalGlyphAtlasBuildLease buildLease = atlas.beginBuildLease();
    final List<TerminalGlyphAtlasEntry> retainedEntries =
        <TerminalGlyphAtlasEntry>[];
    try {
      final List<_TerminalPositionedGlyph> positionedGlyphs =
          <_TerminalPositionedGlyph>[];
      for (final _TerminalCellGlyphPlacement placement in cellGlyphs) {
        final TerminalCellGlyphAtlasKey key =
            TerminalCellGlyphAtlasKey.fromRequest(
              catalogGeneration: catalog.generation,
              scale16_16: atlas.scale16_16,
              request: placement.request,
            );
        final TerminalGlyphAtlasEntry? entry = atlas.lookupCellGlyph(key);
        if (entry == null) {
          throw const TerminalGlyphAtlasCapacityException(
            'visible cell glyph was evicted before frame encoding',
          );
        }
        buildLease.retain(entry);
        retainedEntries.add(entry);
        positionedGlyphs.add(
          _TerminalPositionedGlyph(
            entry: entry,
            x: placement.x,
            y: placement.y,
            colorRgba: placement.colorRgba,
          ),
        );
      }
      for (final _TerminalShapedRun shapedRun in shapedRuns) {
        final int baseline =
            ((shapedRun.run.row * metrics.cellHeight + metrics.baseline) *
                    scale)
                .round();
        for (
          int glyphIndex = 0;
          glyphIndex < shapedRun.shaped.glyphs.length;
          glyphIndex++
        ) {
          final TerminalShapedGlyph glyph = shapedRun.shaped.glyphs[glyphIndex];
          final TerminalGlyphAtlasKey key = TerminalGlyphAtlasKey(
            catalogGeneration: catalog.generation,
            faceId: glyph.faceId,
            glyphId: glyph.glyphId,
            scale16_16: atlas.scale16_16,
          );
          final TerminalGlyphAtlasEntry? entry = atlas.lookup(key);
          if (entry == null) {
            throw const TerminalGlyphAtlasCapacityException(
              'visible glyph was evicted before frame encoding',
            );
          }
          // CoreText advances describe font/fallback typography.
          // Inter-grapheme placement remains owned by the terminal grid.
          final int x =
              (shapedRun.gridPositionX(glyphIndex, metrics.cellWidth) * scale)
                  .round() +
              entry.originX;
          final int y = baseline - entry.originY;
          if (entry.isEmpty ||
              x >= contentWidth ||
              y >= contentHeight ||
              x + entry.width <= 0 ||
              y + entry.height <= 0) {
            continue;
          }
          if (entry.width > contentWidth || entry.height > contentHeight) {
            throw const TerminalGlyphAtlasCapacityException(
              'visible glyph exceeds the Metal viewport extent',
            );
          }
          buildLease.retain(entry);
          retainedEntries.add(entry);
          positionedGlyphs.add(
            _TerminalPositionedGlyph(
              entry: entry,
              x: x,
              y: y,
              colorRgba: shapedRun.run.colorRgba,
            ),
          );
        }
      }

      final List<_TerminalKittyPositionedTile> kittyTiles = kittyImages == null
          ? const <_TerminalKittyPositionedTile>[]
          : _prepareKittyImageTiles(
              kittyImages,
              metrics: metrics,
              scale: scale,
              viewportWidth: contentWidth,
              viewportHeight: contentHeight,
              buildLease: buildLease,
              retainedEntries: retainedEntries,
            );
      if (bridge.synchronize() ==
          TerminalGlyphAtlasSyncDisposition.backpressured) {
        throw const TerminalMetalCompositionBackpressureException();
      }
      for (final _TerminalPositionedGlyph glyph in positionedGlyphs) {
        final TerminalMetalInstance? instance = bridge.glyphInstance(
          glyph.entry,
          x: glyph.x,
          y: glyph.y,
          maskColor: TerminalReferenceColor(glyph.colorRgba),
        );
        if (instance != null) glyphInstances.add(instance);
      }
      for (final _TerminalKittyPositionedTile tile in kittyTiles) {
        final TerminalMetalInstance? instance = bridge.imageInstance(
          tile.entry,
          x: tile.x,
          y: tile.y,
          layer: switch (tile.layer) {
            TerminalKittyImageLayer.belowBackground =>
              TerminalMetalImageLayer.belowBackground,
            TerminalKittyImageLayer.belowText =>
              TerminalMetalImageLayer.belowText,
            TerminalKittyImageLayer.aboveText =>
              TerminalMetalImageLayer.aboveText,
          },
        );
        if (instance == null) continue;
        switch (tile.layer) {
          case TerminalKittyImageLayer.belowBackground:
            kittyImagesBelowBackground.add(instance);
          case TerminalKittyImageLayer.belowText:
            kittyImagesBelowText.add(instance);
          case TerminalKittyImageLayer.aboveText:
            kittyImagesAboveText.add(instance);
        }
      }

      if (presentation.isPaneActive &&
          presentation.cursorDrawn &&
          model.cursorVisible) {
        final int cursorBackground = _cursorBackgroundRgba(
          model,
          row: preedit?.caretRow ?? model.cursorRow,
          column: preedit?.caretColumn ?? model.cursorColumn,
          fallback: opaqueDefaultBackground,
        );
        _addCursorAt(
          cursors,
          row: preedit?.caretRow ?? model.cursorRow,
          column: preedit?.caretColumn ?? model.cursorColumn,
          shape: preedit == null ? model.cursorShape : TerminalCursorShape.bar,
          metrics: metrics,
          scale: scale,
          viewportWidth: contentWidth,
          viewportHeight: contentHeight,
          colorRgba: accessibilityPresentation.increaseContrast
              ? _contrastingRgba(cursorBackground)
              : _rgba(palette.cursorColor, alpha: 0xc0),
        );
      }
      final List<TerminalMetalInstance> contentInstances =
          <TerminalMetalInstance>[
            ...kittyImagesBelowBackground,
            ...backgrounds,
            ...overlays,
            ...kittyImagesBelowText,
            ...glyphInstances,
            ...kittyImagesAboveText,
            ...decorations,
            ...cursors,
          ];
      final List<TerminalMetalInstance> instances =
          contentOffsetX == 0 && contentOffsetY == 0
          ? contentInstances
          : contentInstances
                .map(
                  (TerminalMetalInstance instance) => _translatedInstance(
                    instance,
                    offsetX: contentOffsetX,
                    offsetY: contentOffsetY,
                  ),
                )
                .toList(growable: false);
      final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
        renderer: bridge.renderer,
        frameGeneration: frameGeneration,
        atlasGeneration: bridge.nativeAtlasGeneration,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        scale16_16: atlas.scale16_16,
        backgroundRgba: frameBackground,
        instances: instances,
      );
      return TerminalScreenMetalComposition(
        scheduledFrame: TerminalScheduledMetalFrame(
          frame: frame,
          glyphEntries: retainedEntries,
        ),
        instances: instances,
        shapedRunCount: shapedRuns.length,
        cellGlyphCount: cellGlyphs.length,
        renderedCellCount: renderedCellCount,
        preeditCellCount: preedit?.cells.length ?? 0,
        hyperlinkHoverCellCount: hyperlinkHoverCellCount,
        kittyImageCount: kittyImages?.images.length ?? 0,
        kittyPlacementCount: kittyImages?.placements.length ?? 0,
        kittyTileCount: kittyTiles.length,
      );
    } finally {
      buildLease.close();
    }
  }

  List<_TerminalKittyPositionedTile> _prepareKittyImageTiles(
    TerminalKittyViewportSnapshot snapshot, {
    required TerminalFontCatalogMetrics metrics,
    required double scale,
    required int viewportWidth,
    required int viewportHeight,
    required TerminalGlyphAtlasBuildLease buildLease,
    required List<TerminalGlyphAtlasEntry> retainedEntries,
  }) {
    if (snapshot.images.length > 64 || snapshot.placements.length > 256) {
      throw const TerminalGlyphAtlasCapacityException(
        'Kitty viewport exceeds bounded product image limits',
      );
    }
    if (snapshot.cellWidth <= 0 || snapshot.cellHeight <= 0) {
      if (snapshot.images.isEmpty && snapshot.placements.isEmpty) {
        return const <_TerminalKittyPositionedTile>[];
      }
      throw StateError('Kitty viewport has no authoritative cell geometry');
    }
    final Map<(int, int), TerminalKittyViewportImage> images =
        <(int, int), TerminalKittyViewportImage>{};
    for (final TerminalKittyViewportImage image in snapshot.images) {
      final (int, int) key = (image.imageId, image.resourceGeneration);
      if (images.containsKey(key) ||
          image.width <= 0 ||
          image.height <= 0 ||
          image.byteLength != image.width * image.height * 4) {
        throw StateError('Kitty viewport contains an invalid image resource');
      }
      images[key] = image;
    }
    final int maximumTileWidth =
        atlas.limits.pageWidth - atlas.limits.gutter * 2;
    final int maximumTileHeight =
        atlas.limits.pageHeight - atlas.limits.gutter * 2;
    final List<_TerminalKittyPositionedTile> tiles =
        <_TerminalKittyPositionedTile>[];
    final Map<(int, int), Uint8List> sourcePixels = <(int, int), Uint8List>{};
    for (final TerminalKittyViewportPlacement placement
        in snapshot.placements) {
      final (int, int) imageKey = (
        placement.imageId,
        placement.imageResourceGeneration,
      );
      final TerminalKittyViewportImage? image = images[imageKey];
      if (image == null) {
        throw StateError('Kitty placement refers to an absent image resource');
      }
      final _TerminalKittyDeviceRect destination = _kittyDeviceRect(
        placement,
        metrics: metrics,
        scale: scale,
      );
      if (destination.width <= 0 || destination.height <= 0) continue;
      final int visibleLeft = destination.x.clamp(0, viewportWidth);
      final int visibleTop = destination.y.clamp(0, viewportHeight);
      final int visibleRight = (destination.x + destination.width).clamp(
        0,
        viewportWidth,
      );
      final int visibleBottom = (destination.y + destination.height).clamp(
        0,
        viewportHeight,
      );
      if (visibleLeft >= visibleRight || visibleTop >= visibleBottom) continue;
      final Uint8List rgba = sourcePixels.putIfAbsent(imageKey, image.copyRgba);
      for (
        int tileY = visibleTop;
        tileY < visibleBottom;
        tileY += maximumTileHeight
      ) {
        final int tileHeight = math.min(
          maximumTileHeight,
          visibleBottom - tileY,
        );
        for (
          int tileX = visibleLeft;
          tileX < visibleRight;
          tileX += maximumTileWidth
        ) {
          final int tileWidth = math.min(
            maximumTileWidth,
            visibleRight - tileX,
          );
          final TerminalKittyImageAtlasKey atlasKey =
              TerminalKittyImageAtlasKey(
                screenKindIndex: snapshot.screenKind.index,
                imageId: placement.imageId,
                imageResourceGeneration: placement.imageResourceGeneration,
                imageContentGeneration: image.contentGeneration,
                placementGeneration: placement.placementGeneration,
                sourceX: placement.source.x,
                sourceY: placement.source.y,
                sourceWidth: placement.source.width,
                sourceHeight: placement.source.height,
                destinationX: destination.x,
                destinationY: destination.y,
                destinationWidth: destination.width,
                destinationHeight: destination.height,
                tileX: tileX,
                tileY: tileY,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                scale16_16: atlas.scale16_16,
              );
          final TerminalGlyphAtlasEntry entry = atlas.ingestKittyImageTile(
            key: atlasKey,
            rgba: _sampleKittyTile(
              rgba,
              imageWidth: image.width,
              placement: placement,
              destination: destination,
              tileX: tileX,
              tileY: tileY,
              tileWidth: tileWidth,
              tileHeight: tileHeight,
            ),
          );
          buildLease.retain(entry);
          retainedEntries.add(entry);
          tiles.add(
            _TerminalKittyPositionedTile(
              entry: entry,
              x: tileX,
              y: tileY,
              layer: placement.layer,
            ),
          );
        }
      }
    }
    return tiles;
  }

  static _TerminalKittyDeviceRect _kittyDeviceRect(
    TerminalKittyViewportPlacement placement, {
    required TerminalFontCatalogMetrics metrics,
    required double scale,
  }) {
    final int left =
        ((placement.gridColumn * metrics.cellWidth + placement.cellOffsetX) *
                scale)
            .round();
    final int top =
        ((placement.gridRow * metrics.cellHeight + placement.cellOffsetY) *
                scale)
            .round();
    final int? fixedWidth = placement.fixedPixelWidth;
    final int? fixedHeight = placement.fixedPixelHeight;
    if ((fixedWidth == null) != (fixedHeight == null)) {
      throw StateError('Kitty fixed placement geometry is incomplete');
    }
    if (fixedWidth != null && fixedHeight != null) {
      return _TerminalKittyDeviceRect(
        x: left,
        y: top,
        width: (fixedWidth * scale).round(),
        height: (fixedHeight * scale).round(),
      );
    }
    final int columns = placement.requestedColumns;
    final int rows = placement.requestedRows;
    if (columns != 0 && rows != 0) {
      return _TerminalKittyDeviceRect(
        x: left,
        y: top,
        width:
            (((placement.gridColumn + columns) * metrics.cellWidth) * scale)
                .round() -
            left,
        height:
            (((placement.gridRow + rows) * metrics.cellHeight) * scale)
                .round() -
            top,
      );
    }
    if (columns != 0) {
      final int width =
          (((placement.gridColumn + columns) * metrics.cellWidth) * scale)
              .round() -
          left;
      return _TerminalKittyDeviceRect(
        x: left,
        y: top,
        width: width,
        height: _roundedRatio(
          width,
          placement.source.height,
          placement.source.width,
        ),
      );
    }
    if (rows != 0) {
      final int height =
          (((placement.gridRow + rows) * metrics.cellHeight) * scale).round() -
          top;
      return _TerminalKittyDeviceRect(
        x: left,
        y: top,
        width: _roundedRatio(
          height,
          placement.source.width,
          placement.source.height,
        ),
        height: height,
      );
    }
    return _TerminalKittyDeviceRect(
      x: left,
      y: top,
      width: (placement.source.width * scale).round(),
      height: (placement.source.height * scale).round(),
    );
  }

  static int _roundedRatio(int value, int numerator, int denominator) =>
      denominator <= 0
      ? 0
      : (value * numerator + denominator ~/ 2) ~/ denominator;

  static Uint8List _sampleKittyTile(
    Uint8List source, {
    required int imageWidth,
    required TerminalKittyViewportPlacement placement,
    required _TerminalKittyDeviceRect destination,
    required int tileX,
    required int tileY,
    required int tileWidth,
    required int tileHeight,
  }) {
    final Uint8List result = Uint8List(tileWidth * tileHeight * 4);
    for (int y = 0; y < tileHeight; y++) {
      final int sourceY =
          placement.source.y +
          (tileY + y - destination.y) *
              placement.source.height ~/
              destination.height;
      for (int x = 0; x < tileWidth; x++) {
        final int sourceX =
            placement.source.x +
            (tileX + x - destination.x) *
                placement.source.width ~/
                destination.width;
        final int sourceOffset = (sourceY * imageWidth + sourceX) * 4;
        final int destinationOffset = (y * tileWidth + x) * 4;
        result.setRange(
          destinationOffset,
          destinationOffset + 4,
          source,
          sourceOffset,
        );
      }
    }
    return result;
  }

  static TerminalMetalInstance _translatedInstance(
    TerminalMetalInstance instance, {
    required int offsetX,
    required int offsetY,
  }) {
    if (instance.kind.isImage) {
      return TerminalMetalInstance.image(
        layer: switch (instance.kind) {
          TerminalMetalInstanceKind.imageBelowBackground =>
            TerminalMetalImageLayer.belowBackground,
          TerminalMetalInstanceKind.imageBelowText =>
            TerminalMetalImageLayer.belowText,
          TerminalMetalInstanceKind.imageAboveText =>
            TerminalMetalImageLayer.aboveText,
          _ => throw StateError('unknown Metal image instance kind'),
        },
        x: instance.x + offsetX,
        y: instance.y + offsetY,
        width: instance.width,
        height: instance.height,
        atlasX: instance.atlasX,
        atlasY: instance.atlasY,
        pageIndex: instance.pageIndex,
        pageGeneration: instance.pageGeneration,
      );
    }
    return instance.kind.isGlyph
        ? TerminalMetalInstance.glyph(
            format: instance.kind == TerminalMetalInstanceKind.alphaGlyph
                ? TerminalMetalAtlasFormat.alpha8
                : TerminalMetalAtlasFormat.rgba8Straight,
            x: instance.x + offsetX,
            y: instance.y + offsetY,
            width: instance.width,
            height: instance.height,
            atlasX: instance.atlasX,
            atlasY: instance.atlasY,
            colorRgba: instance.colorRgba,
            pageIndex: instance.pageIndex,
            pageGeneration: instance.pageGeneration,
          )
        : TerminalMetalInstance.solid(
            kind: instance.kind,
            x: instance.x + offsetX,
            y: instance.y + offsetY,
            width: instance.width,
            height: instance.height,
            colorRgba: instance.colorRgba,
          );
  }

  void _addPreedit(
    TerminalPreeditLayout preedit, {
    required List<TerminalMetalInstance> overlays,
    required List<TerminalMetalInstance> decorations,
    required List<_TerminalTextRun> textRuns,
    required TerminalFontCatalogMetrics metrics,
    required double scale,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    final int foregroundRgba = _rgba(palette.resolveToken(0, foreground: true));
    _TerminalTextRunBuilder? run;
    void flushRun() {
      final _TerminalTextRunBuilder? current = run;
      if (current == null) return;
      textRuns.add(current.build(foregroundRgba));
      run = null;
    }

    for (final TerminalPreeditCell cell in preedit.cells) {
      final int left = _columnPixel(cell.column, metrics, scale);
      final int right = _columnPixel(cell.column + cell.width, metrics, scale);
      final int top = _rowPixel(cell.row, metrics, scale);
      final int bottom = _rowPixel(cell.row + 1, metrics, scale);
      if (cell.isSelected) {
        _addClippedSolid(
          overlays,
          kind: TerminalMetalInstanceKind.selection,
          x: left,
          y: top,
          width: right - left,
          height: bottom - top,
          colorRgba: 0x4a90e280,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        );
      }
      _addClippedSolid(
        decorations,
        kind: TerminalMetalInstanceKind.decoration,
        x: left,
        y: _underlinePixel(cell.row, metrics, scale),
        width: right - left,
        height: math.max(1, (metrics.underlineThickness * scale).round()),
        colorRgba: foregroundRgba,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );

      final _TerminalTextRunBuilder? current = run;
      if (current == null ||
          current.row != cell.row ||
          current.nextColumn != cell.column) {
        flushRun();
        run = _TerminalTextRunBuilder(row: cell.row, startColumn: cell.column);
      }
      run!.add(cell.text, cell.width);
    }
    flushRun();
  }

  String _cellText(int content, int widthFlags) {
    if (widthFlags & TerminalCellFlags.grapheme != 0) {
      return String.fromCharCodes(graphemeTable.scalarsAt(content));
    }
    TerminalUnicode.validateScalar(content);
    return String.fromCharCode(content);
  }

  static int? _cellGlyphScalar(int content, int widthFlags, int cellColumns) {
    if (cellColumns != 1 || widthFlags & TerminalCellFlags.grapheme != 0) {
      return null;
    }
    return TerminalCellGlyphClassifier.supports(content) ? content : null;
  }

  static _TerminalCellGlyphPlacement _cellGlyphPlacement({
    required int scalar,
    required int row,
    required int column,
    required int colorRgba,
    required TerminalFontCatalogMetrics metrics,
    required double scale,
  }) {
    final int left = _columnPixel(column, metrics, scale);
    final int right = _columnPixel(column + 1, metrics, scale);
    final int top = _rowPixel(row, metrics, scale);
    final int bottom = _rowPixel(row + 1, metrics, scale);
    final int width = right - left;
    final int height = bottom - top;
    final int thickness = math
        .max(1, (metrics.underlineThickness * scale).round())
        .clamp(1, math.min(width, height));
    return _TerminalCellGlyphPlacement(
      request: TerminalCellGlyphRasterRequest(
        scalar: scalar,
        cellWidth: width,
        cellHeight: height,
        lineThickness: thickness,
      ),
      x: left,
      y: top,
      colorRgba: colorRgba,
    );
  }

  _TerminalCellColors _colors(
    int foregroundToken,
    int backgroundToken,
    int attributes,
  ) {
    final bool inverse = TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.inverse,
    );
    final int foreground = palette.resolveToken(
      inverse ? backgroundToken : foregroundToken,
      foreground: !inverse,
    );
    final int background = palette.resolveToken(
      inverse ? foregroundToken : backgroundToken,
      foreground: inverse,
    );
    final bool faint = TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.faint,
    );
    return _TerminalCellColors(
      foregroundRgba: _rgba(foreground, alpha: faint ? 0x80 : 0xff),
      backgroundRgba: _rgba(background),
    );
  }

  static int _scaleRgbPreservingAlpha(int rgba, double brightness) {
    final int red = (((rgba >>> 24) & 0xff) * brightness).round();
    final int green = (((rgba >>> 16) & 0xff) * brightness).round();
    final int blue = (((rgba >>> 8) & 0xff) * brightness).round();
    return red << 24 | green << 16 | blue << 8 | (rgba & 0xff);
  }

  static TerminalFontStyle _fontStyle(int attributes) {
    final bool bold = TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.bold,
    );
    final bool italic = TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.italic,
    );
    if (bold && italic) return TerminalFontStyle.boldItalic;
    if (bold) return TerminalFontStyle.bold;
    if (italic) return TerminalFontStyle.italic;
    return TerminalFontStyle.regular;
  }

  static int _rgba(int taggedRgb, {int alpha = 0xff}) =>
      ((taggedRgb & 0x00ffffff) << 8) | alpha;

  static int _withAlpha(int rgba, int alpha) =>
      (rgba & 0xffffff00) | (alpha & 0xff);

  static int _columnPixel(
    int column,
    TerminalFontCatalogMetrics metrics,
    double scale,
  ) => (column * metrics.cellWidth * scale).round();

  static int _rowPixel(
    int row,
    TerminalFontCatalogMetrics metrics,
    double scale,
  ) => (row * metrics.cellHeight * scale).round();

  static void _addDecorations(
    List<TerminalMetalInstance> output, {
    required int attributes,
    required int colorRgba,
    required int underlineColorRgba,
    required int left,
    required int right,
    required int row,
    required TerminalFontCatalogMetrics metrics,
    required double scale,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    final TerminalUnderlineStyle underline = TerminalStyleAttributes.underline(
      attributes,
    );
    final int baseline = ((row * metrics.cellHeight + metrics.baseline) * scale)
        .round();
    final int underlineY = (baseline - metrics.underlinePosition * scale)
        .round();
    final int underlineThickness = math.max(
      1,
      (metrics.underlineThickness * scale).round(),
    );
    if (underline != TerminalUnderlineStyle.none) {
      final int segment = switch (underline) {
        TerminalUnderlineStyle.dotted => underlineThickness,
        TerminalUnderlineStyle.dashed => underlineThickness * 3,
        _ => right - left,
      };
      final int gap = underline == TerminalUnderlineStyle.dotted
          ? underlineThickness
          : underline == TerminalUnderlineStyle.dashed
          ? underlineThickness * 2
          : 0;
      var x = left;
      var segmentIndex = 0;
      while (x < right) {
        final int y = underline == TerminalUnderlineStyle.curly
            ? underlineY + (segmentIndex.isOdd ? underlineThickness : 0)
            : underlineY;
        _addClippedSolid(
          output,
          kind: TerminalMetalInstanceKind.decoration,
          x: x,
          y: y,
          width: math.min(segment, right - x),
          height: underlineThickness,
          colorRgba: underlineColorRgba,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        );
        x += segment + gap;
        segmentIndex++;
      }
      if (underline == TerminalUnderlineStyle.double) {
        _addClippedSolid(
          output,
          kind: TerminalMetalInstanceKind.decoration,
          x: left,
          y: underlineY + underlineThickness * 2,
          width: right - left,
          height: underlineThickness,
          colorRgba: underlineColorRgba,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        );
      }
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.strike,
    )) {
      _addClippedSolid(
        output,
        kind: TerminalMetalInstanceKind.decoration,
        x: left,
        y: (baseline - metrics.strikePosition * scale).round(),
        width: right - left,
        height: math.max(1, (metrics.strikeThickness * scale).round()),
        colorRgba: colorRgba,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.overline,
    )) {
      final int rowTop = _rowPixel(row, metrics, scale);
      _addClippedSolid(
        output,
        kind: TerminalMetalInstanceKind.decoration,
        x: left,
        y: math.max(rowTop, (baseline - metrics.ascent * scale).round()),
        width: right - left,
        height: underlineThickness,
        colorRgba: colorRgba,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }
  }

  void _addCursorAt(
    List<TerminalMetalInstance> output, {
    required int row,
    required int column,
    required TerminalCursorShape shape,
    required TerminalFontCatalogMetrics metrics,
    required double scale,
    required int viewportWidth,
    required int viewportHeight,
    required int colorRgba,
  }) {
    final int left = _columnPixel(column, metrics, scale);
    final int right = _columnPixel(column + 1, metrics, scale);
    final int top = _rowPixel(row, metrics, scale);
    final int bottom = _rowPixel(row + 1, metrics, scale);
    final int thickness = math.max(
      1,
      (metrics.underlineThickness * scale).round(),
    );
    final (int, int, int, int) rectangle = switch (shape) {
      TerminalCursorShape.block => (left, top, right - left, bottom - top),
      TerminalCursorShape.underline => (
        left,
        bottom - thickness,
        right - left,
        thickness,
      ),
      TerminalCursorShape.bar => (left, top, thickness, bottom - top),
    };
    _addClippedSolid(
      output,
      kind: TerminalMetalInstanceKind.cursor,
      x: rectangle.$1,
      y: rectangle.$2,
      width: rectangle.$3,
      height: rectangle.$4,
      colorRgba: colorRgba,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }

  int _cursorBackgroundRgba(
    TerminalRenderModel model, {
    required int row,
    required int column,
    required int fallback,
  }) {
    if (row < 0 || row >= model.rows || column < 0 || column >= model.columns) {
      return fallback;
    }
    return _colors(
      model.foregroundAt(row, column),
      model.backgroundAt(row, column),
      styleTable.attributesAt(model.styleAt(row, column)),
    ).backgroundRgba;
  }

  static void _addSelectionEdges(
    List<TerminalMetalInstance> output, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    required int thickness,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    _addClippedSolid(
      output,
      kind: TerminalMetalInstanceKind.decoration,
      x: left,
      y: top,
      width: right - left,
      height: thickness,
      colorRgba: 0xffffffff,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
    _addClippedSolid(
      output,
      kind: TerminalMetalInstanceKind.decoration,
      x: left,
      y: bottom - thickness,
      width: right - left,
      height: thickness,
      colorRgba: 0x000000ff,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
    _addClippedSolid(
      output,
      kind: TerminalMetalInstanceKind.decoration,
      x: left,
      y: top,
      width: thickness,
      height: bottom - top,
      colorRgba: 0xffffffff,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
    _addClippedSolid(
      output,
      kind: TerminalMetalInstanceKind.decoration,
      x: right - thickness,
      y: top,
      width: thickness,
      height: bottom - top,
      colorRgba: 0x000000ff,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }

  void _addGridOverlay(
    TerminalGridOverlayProjection projection, {
    required TerminalRenderModel model,
    required List<TerminalMetalInstance> overlays,
    required List<TerminalMetalInstance> decorations,
    required TerminalFontCatalogMetrics metrics,
    required double scale,
    required int defaultBackground,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    for (final TerminalGridOverlaySpan span in projection.spans) {
      if (span.row >= model.rows || span.endColumn > model.columns) {
        throw StateError('grid overlay projection exceeds the render grid');
      }
      final int left = _columnPixel(span.startColumn, metrics, scale);
      final int right = _columnPixel(span.endColumn, metrics, scale);
      final int top = _rowPixel(span.row, metrics, scale);
      final int bottom = _rowPixel(span.row + 1, metrics, scale);
      final int thickness = math.max(
        1,
        (scale *
                (accessibilityPresentation.increaseContrast ||
                        accessibilityPresentation.differentiateWithoutColor
                    ? 2
                    : 1))
            .round(),
      );
      switch (span.kind) {
        case TerminalGridOverlayKind.searchMatch:
        case TerminalGridOverlayKind.searchSelectedMatch:
          final bool selected =
              span.kind == TerminalGridOverlayKind.searchSelectedMatch;
          _addClippedSolid(
            overlays,
            kind: TerminalMetalInstanceKind.selection,
            x: left,
            y: top,
            width: right - left,
            height: bottom - top,
            colorRgba: selected
                ? accessibilityPresentation.increaseContrast
                      ? 0xffffff88
                      : 0xffa00088
                : accessibilityPresentation.increaseContrast
                ? 0xffffff50
                : 0xf5c54250,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
          if (!selected) continue;
          _addOutline(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            thickness: math.max(1, scale.round()),
            colorRgba: _contrastingRgba(defaultBackground),
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
        case TerminalGridOverlayKind.inspectorHyperlink:
          _addClippedSolid(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            x: left,
            y: bottom - thickness,
            width: right - left,
            height: thickness,
            colorRgba: accessibilityPresentation.increaseContrast
                ? _contrastingRgba(defaultBackground)
                : 0x32d7ffff,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
        case TerminalGridOverlayKind.inspectorSemanticPrompt:
          final int color = accessibilityPresentation.increaseContrast
              ? _contrastingRgba(defaultBackground)
              : 0xc678ddff;
          _addClippedSolid(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            x: left,
            y: top,
            width: right - left,
            height: thickness,
            colorRgba: color,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
          _addClippedSolid(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            x: left,
            y: top,
            width: thickness,
            height: bottom - top,
            colorRgba: color,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
        case TerminalGridOverlayKind.inspectorSemanticInput:
          _addOutline(
            decorations,
            kind: TerminalMetalInstanceKind.decoration,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            thickness: thickness,
            colorRgba: accessibilityPresentation.increaseContrast
                ? _contrastingRgba(defaultBackground)
                : 0x98c379ff,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
      }
    }
  }

  static void _addOutline(
    List<TerminalMetalInstance> output, {
    required TerminalMetalInstanceKind kind,
    required int left,
    required int top,
    required int right,
    required int bottom,
    required int thickness,
    required int colorRgba,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    for (final (int, int, int, int) edge in <(int, int, int, int)>[
      (left, top, right - left, thickness),
      (left, bottom - thickness, right - left, thickness),
      (left, top, thickness, bottom - top),
      (right - thickness, top, thickness, bottom - top),
    ]) {
      _addClippedSolid(
        output,
        kind: kind,
        x: edge.$1,
        y: edge.$2,
        width: edge.$3,
        height: edge.$4,
        colorRgba: colorRgba,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }
  }

  static int _contrastingRgba(int backgroundRgba) {
    final int rgb = backgroundRgba >>> 8;
    final double red = _linearSrgb((rgb >>> 16) & 0xff);
    final double green = _linearSrgb((rgb >>> 8) & 0xff);
    final double blue = _linearSrgb(rgb & 0xff);
    final double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    return luminance > 0.179 ? 0x000000ff : 0xffffffff;
  }

  static double _linearSrgb(int component) {
    final double value = component / 255;
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _underlinePixel(
    int row,
    TerminalFontCatalogMetrics metrics,
    double scale,
  ) {
    final int baseline = ((row * metrics.cellHeight + metrics.baseline) * scale)
        .round();
    return (baseline - metrics.underlinePosition * scale).round();
  }

  static _TerminalCursorShapingBreak? _cursorShapingBreak(
    TerminalRenderModel model,
    int row,
  ) {
    if (!model.cursorVisible || model.cursorRow != row) return null;
    var column = model.cursorColumn;
    if (column < 0 || column >= model.columns) {
      throw StateError('visible cursor exceeds the render grid');
    }
    int flags = model.widthFlagsAt(row, column);
    if ((flags & TerminalCellFlags.widthMask) ==
        TerminalCellFlags.continuation) {
      if (column == 0) {
        throw StateError('visible cursor targets an orphan continuation');
      }
      column--;
      flags = model.widthFlagsAt(row, column);
      if ((flags & TerminalCellFlags.widthMask) != TerminalCellFlags.wide) {
        throw StateError('visible cursor targets an orphan continuation');
      }
    }
    if (model.contentAt(row, column) == 0 ||
        flags & TerminalCellFlags.grapheme != 0) {
      return null;
    }
    final int width = flags & TerminalCellFlags.widthMask;
    return _TerminalCursorShapingBreak(
      column,
      column + (width == TerminalCellFlags.wide ? 2 : 1),
    );
  }

  static void _addClippedSolid(
    List<TerminalMetalInstance> output, {
    required TerminalMetalInstanceKind kind,
    required int x,
    required int y,
    required int width,
    required int height,
    required int colorRgba,
    required int viewportWidth,
    required int viewportHeight,
  }) {
    final int left = math.max(0, x);
    final int top = math.max(0, y);
    final int right = math.min(viewportWidth, x + width);
    final int bottom = math.min(viewportHeight, y + height);
    if (right <= left || bottom <= top) return;
    output.add(
      TerminalMetalInstance.solid(
        kind: kind,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
        colorRgba: colorRgba,
      ),
    );
  }
}

final class _TerminalPositionedGlyph {
  const _TerminalPositionedGlyph({
    required this.entry,
    required this.x,
    required this.y,
    required this.colorRgba,
  });

  final TerminalGlyphAtlasEntry entry;
  final int x;
  final int y;
  final int colorRgba;
}

final class _TerminalCellGlyphPlacement {
  const _TerminalCellGlyphPlacement({
    required this.request,
    required this.x,
    required this.y,
    required this.colorRgba,
  });

  final TerminalCellGlyphRasterRequest request;
  final int x;
  final int y;
  final int colorRgba;
}

final class _TerminalCursorShapingBreak {
  const _TerminalCursorShapingBreak(this.startColumn, this.endColumn);

  final int startColumn;
  final int endColumn;
}

final class _TerminalKittyPositionedTile {
  const _TerminalKittyPositionedTile({
    required this.entry,
    required this.x,
    required this.y,
    required this.layer,
  });

  final TerminalGlyphAtlasEntry entry;
  final int x;
  final int y;
  final TerminalKittyImageLayer layer;
}

final class _TerminalKittyDeviceRect {
  const _TerminalKittyDeviceRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

final class _TerminalTextRun {
  _TerminalTextRun({
    required this.row,
    required this.startColumn,
    required this.text,
    required Iterable<_TerminalTextCluster> clusters,
    required this.style,
    required this.colorRgba,
  }) : clusters = List<_TerminalTextCluster>.unmodifiable(clusters) {
    if (text.isEmpty || this.clusters.isEmpty) {
      throw ArgumentError('terminal text run must not be empty');
    }
    var expectedUtf16Start = 0;
    var expectedColumn = startColumn;
    for (final _TerminalTextCluster cluster in this.clusters) {
      if (cluster.utf16Start != expectedUtf16Start ||
          cluster.utf16End <= cluster.utf16Start ||
          cluster.startColumn != expectedColumn ||
          cluster.endColumn <= cluster.startColumn) {
        throw StateError('terminal text run has non-contiguous clusters');
      }
      expectedUtf16Start = cluster.utf16End;
      expectedColumn = cluster.endColumn;
    }
    if (expectedUtf16Start != text.length) {
      throw StateError('terminal text run does not cover its UTF-16 text');
    }
  }

  final int row;
  final int startColumn;
  final String text;
  final List<_TerminalTextCluster> clusters;
  final TerminalFontStyle style;
  final int colorRgba;

  int clusterIndexAt(int utf16Offset) {
    var low = 0;
    var high = clusters.length;
    while (low < high) {
      final int middle = low + ((high - low) >> 1);
      final _TerminalTextCluster cluster = clusters[middle];
      if (utf16Offset < cluster.utf16Start) {
        high = middle;
      } else if (utf16Offset >= cluster.utf16End) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    throw StateError('shaped glyph is outside its terminal text run');
  }
}

final class _TerminalTextRunBuilder {
  _TerminalTextRunBuilder({
    required this.row,
    required this.startColumn,
    this.style = TerminalFontStyle.regular,
  }) : nextColumn = startColumn;

  final int row;
  final int startColumn;
  final TerminalFontStyle style;
  final StringBuffer _text = StringBuffer();
  final List<_TerminalTextCluster> _clusters = <_TerminalTextCluster>[];
  int _utf16Length = 0;
  int nextColumn;

  void add(String text, int width) {
    if (text.isEmpty || (width != 1 && width != 2)) {
      throw ArgumentError('terminal text cluster must occupy one or two cells');
    }
    _clusters.add(
      _TerminalTextCluster(
        utf16Start: _utf16Length,
        utf16End: _utf16Length + text.length,
        startColumn: nextColumn,
        endColumn: nextColumn + width,
      ),
    );
    _text.write(text);
    _utf16Length += text.length;
    nextColumn += width;
  }

  _TerminalTextRun build(int colorRgba) => _TerminalTextRun(
    row: row,
    startColumn: startColumn,
    text: _text.toString(),
    clusters: _clusters,
    style: style,
    colorRgba: colorRgba,
  );
}

final class _TerminalTextCluster {
  const _TerminalTextCluster({
    required this.utf16Start,
    required this.utf16End,
    required this.startColumn,
    required this.endColumn,
  });

  final int utf16Start;
  final int utf16End;
  final int startColumn;
  final int endColumn;
}

final class _TerminalShapedRun {
  _TerminalShapedRun(this.run, this.shaped)
    : _gridLayout = _TerminalShapedGridLayout.compute(run, shaped);

  final _TerminalTextRun run;
  final TerminalShapedText shaped;
  final _TerminalShapedGridLayout _gridLayout;

  double gridPositionX(int glyphIndex, double cellWidth) =>
      _gridLayout.positionX(glyphIndex, cellWidth);
}

final class _TerminalShapedGridLayout {
  _TerminalShapedGridLayout._({
    required this.run,
    required this.shaped,
    required this.glyphClusterIndexes,
    required this.clusterNaturalOrigins,
  });

  factory _TerminalShapedGridLayout.compute(
    _TerminalTextRun run,
    TerminalShapedText shaped,
  ) {
    final List<int> glyphClusterIndexes = List<int>.filled(
      shaped.glyphs.length,
      0,
    );
    final List<double?> clusterNaturalOrigins = List<double?>.filled(
      run.clusters.length,
      null,
    );
    for (int index = 0; index < shaped.glyphs.length; index++) {
      final TerminalShapedGlyph glyph = shaped.glyphs[index];
      final int clusterIndex = run.clusterIndexAt(glyph.utf16Start);
      glyphClusterIndexes[index] = clusterIndex;
      clusterNaturalOrigins[clusterIndex] ??= glyph.positionX;
    }
    return _TerminalShapedGridLayout._(
      run: run,
      shaped: shaped,
      glyphClusterIndexes: List<int>.unmodifiable(glyphClusterIndexes),
      clusterNaturalOrigins: List<double?>.unmodifiable(clusterNaturalOrigins),
    );
  }

  final _TerminalTextRun run;
  final TerminalShapedText shaped;
  final List<int> glyphClusterIndexes;
  final List<double?> clusterNaturalOrigins;

  double positionX(int glyphIndex, double cellWidth) {
    final int clusterIndex = glyphClusterIndexes[glyphIndex];
    final _TerminalTextCluster cluster = run.clusters[clusterIndex];
    final double naturalOrigin = clusterNaturalOrigins[clusterIndex]!;
    return cluster.startColumn * cellWidth +
        shaped.glyphs[glyphIndex].positionX -
        naturalOrigin;
  }
}

final class _TerminalCellColors {
  const _TerminalCellColors({
    required this.foregroundRgba,
    required this.backgroundRgba,
  });

  final int foregroundRgba;
  final int backgroundRgba;
}
