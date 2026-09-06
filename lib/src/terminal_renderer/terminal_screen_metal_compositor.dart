import 'dart:math' as math;

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_style.dart';
import '../terminal_core/terminal_unicode.dart';
import '../terminal_input/terminal_preedit.dart';
import 'frame_scheduler.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'reference_renderer.dart';
import 'terminal_damage.dart';

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
    required this.renderedCellCount,
    required this.preeditCellCount,
  }) : instances = List<TerminalMetalInstance>.unmodifiable(instances);

  final TerminalScheduledMetalFrame scheduledFrame;
  final List<TerminalMetalInstance> instances;
  final int shapedRunCount;
  final int renderedCellCount;
  final int preeditCellCount;
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
  }) {
    if (!identical(shapingCache.catalog, catalog) ||
        !identical(bridge.atlas, atlas) ||
        atlas.catalogGeneration != catalog.generation) {
      throw ArgumentError('Metal composition resources do not share a domain');
    }
  }

  final TerminalFontCatalog catalog;
  final TerminalShapingCache shapingCache;
  final TerminalGlyphAtlas atlas;
  final TerminalGlyphAtlasMetalBridge bridge;
  final TerminalStyleTable styleTable;
  final TerminalPalette palette;
  final TerminalGraphemeTable graphemeTable;

  TerminalScreenMetalComposition compose(
    TerminalDamageRenderModel model, {
    required int frameGeneration,
    required int viewportWidth,
    required int viewportHeight,
    required TerminalFramePresentation presentation,
    TerminalPreeditLayout? preedit,
  }) {
    if (!model.isInitialized) {
      throw StateError('Metal composition requires an initialized model');
    }
    if (model.requiredResourceGeneration > atlas.resourceGeneration) {
      throw StateError('Metal composition resources trail screen damage');
    }

    final double scale = atlas.scale;
    final TerminalFontCatalogMetrics metrics = catalog.metrics;
    final int defaultBackground = _rgba(
      palette.resolveToken(0, foreground: false),
    );
    final List<TerminalMetalInstance> backgrounds = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> overlays = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> glyphInstances =
        <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> decorations = <TerminalMetalInstance>[];
    final List<TerminalMetalInstance> cursors = <TerminalMetalInstance>[];
    final List<_TerminalTextRun> textRuns = <_TerminalTextRun>[];
    var renderedCellCount = 0;

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
        final int attributes = styleTable.attributesAt(
          model.styleAt(row, column),
        );
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
        if (colors.backgroundRgba != defaultBackground) {
          _addClippedSolid(
            backgrounds,
            kind: TerminalMetalInstanceKind.cellBackground,
            x: left,
            y: top,
            width: right - left,
            height: bottom - top,
            colorRgba: colors.backgroundRgba,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
        }

        final int content = model.contentAt(row, column);
        if (content != 0) {
          renderedCellCount++;
          _addDecorations(
            decorations,
            attributes: attributes,
            colorRgba: colors.foregroundRgba,
            left: left,
            right: right,
            row: row,
            metrics: metrics,
            scale: scale,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
        }
        column += cellColumns;
      }
    }

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
        final StringBuffer text = StringBuffer();
        final int runStart = column;
        int nextColumn = column;
        while (nextColumn < model.columns) {
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
          text.write(_cellText(nextContent, nextFlags));
          nextColumn += nextWidth == TerminalCellFlags.wide ? 2 : 1;
        }
        textRuns.add(
          _TerminalTextRun(
            row: row,
            startColumn: runStart,
            text: text.toString(),
            style: fontStyle,
            colorRgba: foregroundRgba,
          ),
        );
        column = nextColumn;
      }
    }

    if (presentation.visualBellActive) {
      _addClippedSolid(
        overlays,
        kind: TerminalMetalInstanceKind.selection,
        x: 0,
        y: 0,
        width: viewportWidth,
        height: viewportHeight,
        colorRgba: 0xffffff30,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }

    if (preedit != null) {
      _addPreedit(
        preedit,
        overlays: overlays,
        decorations: decorations,
        textRuns: textRuns,
        metrics: metrics,
        scale: scale,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }

    final List<_TerminalShapedRun> shapedRuns = <_TerminalShapedRun>[];
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
    if (missing.length > atlas.limits.maximumEntries) {
      throw const TerminalGlyphAtlasCapacityException(
        'visible glyph set exceeds the bounded atlas entry limit',
      );
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

    final List<TerminalGlyphAtlasEntry> retainedGlyphs =
        <TerminalGlyphAtlasEntry>[];
    for (final _TerminalShapedRun shapedRun in shapedRuns) {
      final int runLeft = _columnPixel(
        shapedRun.run.startColumn,
        metrics,
        scale,
      );
      final int baseline =
          ((shapedRun.run.row * metrics.cellHeight + metrics.baseline) * scale)
              .round();
      for (final TerminalShapedGlyph glyph in shapedRun.shaped.glyphs) {
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
        final int x =
            runLeft + (glyph.positionX * scale).round() + entry.originX;
        final int y = baseline - entry.originY;
        if (entry.isEmpty ||
            x >= viewportWidth ||
            y >= viewportHeight ||
            x + entry.width <= 0 ||
            y + entry.height <= 0) {
          continue;
        }
        if (entry.width > viewportWidth || entry.height > viewportHeight) {
          throw const TerminalGlyphAtlasCapacityException(
            'visible glyph exceeds the Metal viewport extent',
          );
        }
        final TerminalMetalInstance? instance = bridge.glyphInstance(
          entry,
          x: x,
          y: y,
          maskColor: TerminalReferenceColor(shapedRun.run.colorRgba),
        );
        if (instance != null) {
          glyphInstances.add(instance);
          retainedGlyphs.add(entry);
        }
      }
    }

    if (presentation.cursorDrawn) {
      _addCursorAt(
        cursors,
        row: preedit?.caretRow ?? model.cursorRow,
        column: preedit?.caretColumn ?? model.cursorColumn,
        shape: preedit == null ? model.cursorShape : TerminalCursorShape.bar,
        metrics: metrics,
        scale: scale,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
      );
    }
    final List<TerminalMetalInstance> instances = <TerminalMetalInstance>[
      ...backgrounds,
      ...overlays,
      ...glyphInstances,
      ...decorations,
      ...cursors,
    ];
    final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
      renderer: bridge.renderer,
      frameGeneration: frameGeneration,
      atlasGeneration: bridge.nativeAtlasGeneration,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      scale16_16: atlas.scale16_16,
      backgroundRgba: defaultBackground,
      instances: instances,
    );
    return TerminalScreenMetalComposition(
      scheduledFrame: TerminalScheduledMetalFrame(
        frame: frame,
        glyphEntries: retainedGlyphs,
      ),
      instances: instances,
      shapedRunCount: shapedRuns.length,
      renderedCellCount: renderedCellCount,
      preeditCellCount: preedit?.cells.length ?? 0,
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
          colorRgba: colorRgba,
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
          colorRgba: colorRgba,
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
      colorRgba: _rgba(palette.resolveToken(0, foreground: true), alpha: 0xc0),
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
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

final class _TerminalTextRun {
  const _TerminalTextRun({
    required this.row,
    required this.startColumn,
    required this.text,
    required this.style,
    required this.colorRgba,
  });

  final int row;
  final int startColumn;
  final String text;
  final TerminalFontStyle style;
  final int colorRgba;
}

final class _TerminalTextRunBuilder {
  _TerminalTextRunBuilder({required this.row, required this.startColumn})
    : nextColumn = startColumn;

  final int row;
  final int startColumn;
  final StringBuffer _text = StringBuffer();
  int nextColumn;

  void add(String text, int width) {
    _text.write(text);
    nextColumn += width;
  }

  _TerminalTextRun build(int colorRgba) => _TerminalTextRun(
    row: row,
    startColumn: startColumn,
    text: _text.toString(),
    style: TerminalFontStyle.regular,
    colorRgba: colorRgba,
  );
}

final class _TerminalShapedRun {
  const _TerminalShapedRun(this.run, this.shaped);

  final _TerminalTextRun run;
  final TerminalShapedText shaped;
}

final class _TerminalCellColors {
  const _TerminalCellColors({
    required this.foregroundRgba,
    required this.backgroundRgba,
  });

  final int foregroundRgba;
  final int backgroundRgba;
}
