import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalScreenMetalCompositorTests();

void runTerminalScreenMetalCompositorTests() {
  _testAnsiStylesBecomeMetalLayers();
  _testCursorColorUsesIndependentMetalLayer();
  _testInverseBackgroundAndConcealMapping();
  _testWrappedOverflowKeepsNewestPromptVisible();
  _testWideGraphemeUsesCanonicalGrid();
  _testCjkGlyphOriginsFollowCanonicalGrid();
  _testPreeditUsesTransientMetalLayers();
  _testSelectionProjectionUsesOverlayLayer();
  _testHyperlinkHoverUsesDecorationLayer();
  _testAccessibleOverlaysUseContrastAndGeometry();
  _testPreeditRespectsRendererInstanceLimit();
  _testContentRectangleOffsetsEveryLayer();
  _testKittyImagesUseOrdinaryMetalAtlasAndTextOrder();
  _testKittyAnimationFrameUsesContentGenerationAndNativePixels();
}

void _testAccessibleOverlaysUseContrastAndGeometry() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  _parse(
    screens,
    utf8.encode('\x1b]8;https://example.test\x07AB\x1b]8;;\x07CD'),
  );
  final TerminalSelectionRange range = screens.viewport.selectionRange(
    screens.viewport.anchorAt(0, 1),
    screens.viewport.anchorAfter(0, 2),
  )!;
  final int hyperlink = screens.activeScreen.hyperlinkAt(0, 0);
  final _CompositionFixture fixture = _compose(
    screens,
    selection: screens.viewport.projectSelection(range),
    hoveredHyperlinkId: hyperlink,
    visualBellActive: true,
    accessibilityPresentation: const TerminalAccessibilityPresentation(
      reduceMotion: false,
      increaseContrast: true,
      differentiateWithoutColor: true,
    ),
  );
  try {
    final List<TerminalMetalInstance> selections = fixture.composition.instances
        .where(
          (TerminalMetalInstance instance) =>
              instance.kind == TerminalMetalInstanceKind.selection,
        )
        .toList(growable: false);
    final List<TerminalMetalInstance> decorations = fixture
        .composition
        .instances
        .where(
          (TerminalMetalInstance instance) =>
              instance.kind == TerminalMetalInstanceKind.decoration,
        )
        .toList(growable: false);
    final TerminalMetalInstance cursor = fixture.composition.instances
        .singleWhere(
          (TerminalMetalInstance instance) =>
              instance.kind == TerminalMetalInstanceKind.cursor,
        );
    _expect(
      selections.length == 5 &&
          !selections.any(
            (TerminalMetalInstance instance) =>
                instance.width == fixture.viewportWidth &&
                instance.height ==
                    fixture.composition.scheduledFrame.frame.viewportHeight,
          ) &&
          decorations.any(
            (TerminalMetalInstance instance) =>
                instance.colorRgba == 0xffffffff,
          ) &&
          decorations.any(
            (TerminalMetalInstance instance) =>
                instance.colorRgba == 0x000000ff,
          ) &&
          decorations
              .where(
                (TerminalMetalInstance instance) =>
                    instance.colorRgba != 0xffffffff &&
                    instance.colorRgba != 0x000000ff,
              )
              .every(
                (TerminalMetalInstance instance) => instance.height >= 2,
              ) &&
          (cursor.colorRgba == 0xffffffff || cursor.colorRgba == 0x000000ff),
      'accessible composition uses a bell border, two-tone selection edges, '
      'a thick link underline, and an opaque contrasting cursor',
    );
  } finally {
    fixture.dispose();
  }
}

void _testKittyAnimationFrameUsesContentGenerationAndNativePixels() {
  for (final double scale in <double>[1, 2]) {
    final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 2);
    _parse(screens, ascii.encode('A'));
    _storeKittyImage(
      screens,
      imageId: 9,
      rgba: const <int>[255, 0, 0, 255],
      width: 1,
      height: 1,
    );
    final image = screens.primaryKittyImages.imageById(9)!;
    final int rootContentGeneration = image.contentGeneration;
    screens.primaryKittyImages.storeAnimationFrame(
      imageId: 9,
      imageNumber: 0,
      expectedResourceGeneration: image.resourceGeneration,
      width: 1,
      height: 1,
      x: 0,
      y: 0,
      baseFrame: 0,
      editFrame: 0,
      gapMilliseconds: 40,
      overwrite: true,
      backgroundRgba: 0,
      transient: false,
      rgba: Uint8List.fromList(const <int>[0, 0, 255, 255]),
    );
    final int animatedContentGeneration = image.frameContentGeneration(2);
    screens.primaryKittyImages.controlAnimation(
      imageId: 9,
      imageNumber: 0,
      control: TerminalKittyGraphicsCommandParser.parse(
        Uint8List.fromList('Ga=a,i=9,c=2,s=1'.codeUnits),
      ).animationControl,
    );
    _placeKittyImage(screens, imageId: 9, column: 0, z: 0);

    final _CompositionFixture animated = _compose(
      screens,
      scale: scale,
      includeKittyImages: true,
    );
    try {
      final TerminalGlyphAtlasEntry entry = animated
          .composition
          .scheduledFrame
          .glyphEntries
          .singleWhere((TerminalGlyphAtlasEntry entry) => entry.isKittyImage);
      final Uint8List rendered = animated.renderer.renderRgba(
        animated.composition.scheduledFrame.frame,
      );
      final int sampleX = (animated.catalog.metrics.cellWidth * scale / 2)
          .floor();
      final int sampleY = (animated.catalog.metrics.cellHeight * scale / 2)
          .floor();
      final int offset = (sampleY * animated.viewportWidth + sampleX) * 4;
      _expect(
        entry.kittyImageKey!.imageContentGeneration ==
                animatedContentGeneration &&
            animatedContentGeneration != rootContentGeneration &&
            rendered[offset] == 0 &&
            rendered[offset + 1] == 0 &&
            rendered[offset + 2] == 255 &&
            rendered[offset + 3] == 255,
        'the selected frame owns its atlas identity and native blue pixels at '
        '${scale}x',
      );
    } finally {
      animated.dispose();
    }

    screens.primaryKittyImages.controlAnimation(
      imageId: 9,
      imageNumber: 0,
      control: TerminalKittyGraphicsCommandParser.parse(
        Uint8List.fromList('Ga=a,i=9,c=1,s=1'.codeUnits),
      ).animationControl,
    );
    final _CompositionFixture root = _compose(
      screens,
      scale: scale,
      includeKittyImages: true,
    );
    try {
      final TerminalGlyphAtlasEntry entry = root
          .composition
          .scheduledFrame
          .glyphEntries
          .singleWhere((TerminalGlyphAtlasEntry entry) => entry.isKittyImage);
      final Uint8List rendered = root.renderer.renderRgba(
        root.composition.scheduledFrame.frame,
      );
      final int sampleX = (root.catalog.metrics.cellWidth * scale / 2).floor();
      final int sampleY = (root.catalog.metrics.cellHeight * scale / 2).floor();
      final int offset = (sampleY * root.viewportWidth + sampleX) * 4;
      _expect(
        entry.kittyImageKey!.imageContentGeneration == rootContentGeneration &&
            rendered[offset] == 255 &&
            rendered[offset + 1] == 0 &&
            rendered[offset + 2] == 0 &&
            rendered[offset + 3] == 255,
        'returning to the root restores its stable atlas identity and native '
        'red pixels at ${scale}x',
      );
    } finally {
      root.dispose();
    }
  }
}

void _testKittyImagesUseOrdinaryMetalAtlasAndTextOrder() {
  for (final double scale in <double>[1, 2]) {
    final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 3);
    _parse(screens, ascii.encode('A'));
    _storeKittyImage(
      screens,
      imageId: 1,
      rgba: const <int>[255, 0, 0, 255, 0, 255, 0, 255],
      width: 2,
      height: 1,
    );
    _placeKittyImage(screens, imageId: 1, column: 0, z: -1);
    _storeKittyImage(
      screens,
      imageId: 2,
      rgba: const <int>[0, 0, 255, 255],
      width: 1,
      height: 1,
    );
    _placeKittyImage(screens, imageId: 2, column: 0, z: 0);

    final _CompositionFixture fixture = _compose(
      screens,
      scale: scale,
      includeKittyImages: true,
    );
    try {
      final List<TerminalMetalInstanceKind> contentKinds = fixture
          .composition
          .instances
          .where((TerminalMetalInstance instance) => instance.kind.isGlyph)
          .map((TerminalMetalInstance instance) => instance.kind)
          .toList();
      final List<TerminalGlyphAtlasEntry> kittyEntries = fixture
          .composition
          .scheduledFrame
          .glyphEntries
          .where((TerminalGlyphAtlasEntry entry) => entry.isKittyImage)
          .toList();
      _expect(
        contentKinds.length == 3 &&
            contentKinds[0] == TerminalMetalInstanceKind.colorGlyph &&
            contentKinds[1] == TerminalMetalInstanceKind.alphaGlyph &&
            contentKinds[2] == TerminalMetalInstanceKind.colorGlyph,
        'negative and nonnegative Kitty tiles bracket text in the shared '
        'Metal glyph layer at ${scale}x',
      );
      _expect(
        fixture.composition.kittyImageCount == 2 &&
            fixture.composition.kittyPlacementCount == 2 &&
            fixture.composition.kittyTileCount == 2 &&
            fixture.atlas.kittyImageEntryCount == 2 &&
            kittyEntries.length == 2 &&
            kittyEntries.every(
              (TerminalGlyphAtlasEntry entry) =>
                  entry.width > 0 && entry.height > 0,
            ),
        'static Kitty placements become bounded, retained color-atlas tiles',
      );
      final Uint8List rendered = fixture.renderer.renderRgba(
        fixture.composition.scheduledFrame.frame,
      );
      final int sampleX = (fixture.catalog.metrics.cellWidth * scale / 2)
          .floor();
      final int sampleY = (fixture.catalog.metrics.cellHeight * scale / 2)
          .floor();
      final int sampleOffset = (sampleY * fixture.viewportWidth + sampleX) * 4;
      _expect(
        rendered[sampleOffset] == 0 &&
            rendered[sampleOffset + 1] == 0 &&
            rendered[sampleOffset + 2] == 255 &&
            rendered[sampleOffset + 3] == 255,
        'the accepted native frame shows the opaque above-text image at '
        '${scale}x',
      );
    } finally {
      fixture.dispose();
    }
  }
}

void _testContentRectangleOffsetsEveryLayer() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 2);
  _parse(screens, ascii.encode('X'));
  final _CompositionFixture baseline = _compose(screens);
  final _CompositionFixture inset = _compose(
    screens,
    contentOffsetX: 13,
    contentOffsetY: 7,
  );
  try {
    _expect(
      inset.composition.instances.length ==
          baseline.composition.instances.length,
      'content inset preserves the composed layer count',
    );
    for (
      var index = 0;
      index < baseline.composition.instances.length;
      index++
    ) {
      final TerminalMetalInstance original =
          baseline.composition.instances[index];
      final TerminalMetalInstance translated =
          inset.composition.instances[index];
      _expect(
        translated.kind == original.kind &&
            translated.x == original.x + 13 &&
            translated.y == original.y + 7 &&
            translated.width == original.width &&
            translated.height == original.height &&
            translated.colorRgba == original.colorRgba,
        'content inset translates layer $index without changing its payload',
      );
    }
    final TerminalMetalFrame frame = inset.composition.scheduledFrame.frame;
    _expect(
      frame.viewportWidth == inset.viewportWidth &&
          frame.viewportHeight == inset.viewportHeight,
      'inset content remains encoded against the complete pane viewport',
    );
  } finally {
    baseline.dispose();
    inset.dispose();
  }
}

void _testCursorColorUsesIndependentMetalLayer() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 2);
  _parse(screens, ascii.encode('X\x1b]12;#123456\x07'));
  final _CompositionFixture fixture = _compose(screens);
  try {
    final TerminalMetalInstance cursor = fixture.composition.instances
        .singleWhere(
          (TerminalMetalInstance instance) =>
              instance.kind == TerminalMetalInstanceKind.cursor,
        );
    final TerminalMetalInstance glyph = fixture.composition.instances
        .singleWhere((TerminalMetalInstance instance) => instance.kind.isGlyph);
    _expect(
      cursor.colorRgba == 0x123456c0 &&
          glyph.colorRgba == 0xe5e5e5ff &&
          screens.palette.defaultForeground ==
              TerminalPalette.xtermDefaultForeground,
      'OSC 12 colors only the Metal cursor layer, not text foreground',
    );
    final Uint8List rgba = fixture.renderer.renderRgba(
      fixture.composition.scheduledFrame.frame,
    );
    _expect(
      rgba.any((int byte) => byte != 0),
      'custom cursor color produces a native Metal frame',
    );
  } finally {
    fixture.dispose();
  }
}

void _testCjkGlyphOriginsFollowCanonicalGrid() {
  const String text = 'A日本語B';
  const List<int> terminalColumns = <int>[0, 1, 3, 5, 7];
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 8);
  _parse(screens, utf8.encode(text));
  final TerminalSelectionRange selection = screens.viewport.selectionRange(
    screens.viewport.anchorAt(0, 3),
    screens.viewport.anchorAfter(0, 3),
  )!;

  for (final double scale in <double>[1, 2]) {
    final _CompositionFixture fixture = _compose(
      screens,
      scale: scale,
      fontFamily: TerminalLiveMetalSurface.defaultFontFamily,
      selection: screens.viewport.projectSelection(selection),
    );
    try {
      final TerminalShapedText shaped = fixture.shapingCache.shape(text);
      final List<TerminalMetalInstance> glyphInstances = fixture
          .composition
          .instances
          .where((TerminalMetalInstance instance) => instance.kind.isGlyph)
          .toList();
      _expect(
        shaped.glyphs.length == terminalColumns.length &&
            glyphInstances.length == shaped.glyphs.length,
        'mixed ASCII/CJK fixture retains one visible glyph per grapheme',
      );
      final List<int> glyphOrigins = <int>[];
      for (int index = 0; index < shaped.glyphs.length; index++) {
        final TerminalShapedGlyph glyph = shaped.glyphs[index];
        final TerminalGlyphAtlasEntry entry = fixture.atlas.lookup(
          TerminalGlyphAtlasKey(
            catalogGeneration: fixture.catalog.generation,
            faceId: glyph.faceId,
            glyphId: glyph.glyphId,
            scale16_16: fixture.atlas.scale16_16,
          ),
        )!;
        glyphOrigins.add(glyphInstances[index].x - entry.originX);
      }
      final List<int> expectedOrigins = <int>[
        for (final int column in terminalColumns)
          (column * fixture.catalog.metrics.cellWidth * scale).round(),
      ];
      final TerminalMetalInstance overlay = fixture.composition.instances
          .singleWhere(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.selection,
          );
      final int expectedOverlayLeft =
          (3 * fixture.catalog.metrics.cellWidth * scale).round();
      final int expectedOverlayRight =
          (5 * fixture.catalog.metrics.cellWidth * scale).round();
      _expect(
        glyphOrigins.toString() == expectedOrigins.toString() &&
            overlay.x == expectedOverlayLeft &&
            overlay.width == expectedOverlayRight - expectedOverlayLeft,
        'CoreText fallback glyph origins and wide selection overlay follow '
        'terminal columns at ${scale}x (actual=$glyphOrigins '
        'expected=$expectedOrigins overlay=${overlay.x}/${overlay.width})',
      );
    } finally {
      fixture.dispose();
    }
  }
}

void _testHyperlinkHoverUsesDecorationLayer() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 6);
  _parse(
    screens,
    utf8.encode(
      '\x1b]8;id=hover;https://example.test\x07A界'
      '\x1b]8;;\x07X'
      '\x1b]8;id=hover;https://example.test\x07B'
      '\x1b]8;;\x07',
    ),
  );
  final int hyperlink = screens.activeScreen.hyperlinkAt(0, 0);
  final List<int> canonicalBefore = _screenContent(screens.activeScreen);
  for (final double scale in <double>[1, 2]) {
    final _CompositionFixture fixture = _compose(
      screens,
      hoveredHyperlinkId: hyperlink,
      scale: scale,
    );
    try {
      final List<TerminalMetalInstance> hover = fixture.composition.instances
          .where(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.decoration,
          )
          .toList();
      final int expectedThickness =
          (fixture.catalog.metrics.underlineThickness * scale).round().clamp(
            1,
            1 << 20,
          );
      _expect(
        fixture.composition.hyperlinkHoverCellCount == 4 &&
            hover.length == 3 &&
            hover.every(
              (TerminalMetalInstance instance) =>
                  instance.height == expectedThickness,
            ) &&
            hover[0].width ==
                (fixture.catalog.metrics.cellWidth * scale).round() &&
            hover[1].width ==
                (fixture.catalog.metrics.cellWidth * 2 * scale).round() &&
            _screenContent(screens.activeScreen).toString() ==
                canonicalBefore.toString(),
        'OSC 8 hover underlines scalar/wide/grouped cells at ${scale}x '
        'without mutating canonical content',
      );
      final Uint8List rgba = fixture.renderer.renderRgba(
        fixture.composition.scheduledFrame.frame,
      );
      _expect(
        rgba.any((int byte) => byte != 0),
        'hyperlink hover frame is accepted by native Metal at ${scale}x',
      );
    } finally {
      fixture.dispose();
    }
  }
}

void _testSelectionProjectionUsesOverlayLayer() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  for (int column = 0; column < 4; column++) {
    screens.primary.setNarrowCell(0, column, 0x41 + column, background: 2);
  }
  final TerminalSelectionRange range = screens.viewport.selectionRange(
    screens.viewport.anchorAt(0, 1),
    screens.viewport.anchorAfter(0, 2),
  )!;
  for (final double scale in <double>[1, 2]) {
    final _CompositionFixture fixture = _compose(
      screens,
      selection: screens.viewport.projectSelection(range),
      scale: scale,
    );
    try {
      final List<TerminalMetalInstance> instances =
          fixture.composition.instances;
      final int background = instances.indexWhere(
        (TerminalMetalInstance instance) =>
            instance.kind == TerminalMetalInstanceKind.cellBackground,
      );
      final int selection = instances.indexWhere(
        (TerminalMetalInstance instance) =>
            instance.kind == TerminalMetalInstanceKind.selection,
      );
      final int glyph = instances.indexWhere(
        (TerminalMetalInstance instance) => instance.kind.isGlyph,
      );
      final TerminalMetalInstance overlay = instances[selection];
      final int expectedLeft = (fixture.catalog.metrics.cellWidth * scale)
          .round();
      final int expectedRight = (fixture.catalog.metrics.cellWidth * 3 * scale)
          .round();
      _expect(
        background >= 0 &&
            selection > background &&
            glyph > selection &&
            overlay.x == expectedLeft &&
            overlay.width == expectedRight - expectedLeft &&
            overlay.height ==
                (fixture.catalog.metrics.cellHeight * scale).round(),
        'selection is clipped at ${scale}x between backgrounds and glyphs '
        '(indices=$background/$selection/$glyph '
        'rect=${overlay.x},${overlay.y},${overlay.width},${overlay.height})',
      );
    } finally {
      fixture.dispose();
    }
  }
}

void _testInverseBackgroundAndConcealMapping() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  _parse(
    screens,
    ascii.encode('\x1b[38;2;1;2;3;48;2;4;5;6;3;9;7mI\x1b[8mX\x1b[0m'),
  );
  final _CompositionFixture fixture = _compose(screens);
  try {
    final List<TerminalMetalInstance> glyphs = fixture.composition.instances
        .where((TerminalMetalInstance instance) => instance.kind.isGlyph)
        .toList();
    final List<TerminalMetalInstance> backgrounds = fixture
        .composition
        .instances
        .where(
          (TerminalMetalInstance instance) =>
              instance.kind == TerminalMetalInstanceKind.cellBackground,
        )
        .toList();
    _expect(
      fixture.composition.renderedCellCount == 2 &&
          glyphs.length == 1 &&
          glyphs.single.colorRgba == 0x040506ff &&
          backgrounds.length == 2 &&
          backgrounds.every(
            (TerminalMetalInstance instance) =>
                instance.colorRgba == 0x010203ff,
          ) &&
          fixture.composition.instances.any(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.decoration,
          ),
      'inverse swaps direct colors, conceal omits glyphs, and strike decorates',
    );
  } finally {
    fixture.dispose();
  }
}

void _testAnsiStylesBecomeMetalLayers() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 12);
  _parse(screens, <int>[...ascii.encode('\x1b[31;1;4mRED\x1b[0m ok')]);
  final TerminalScreen screen = screens.activeScreen;
  final List<int> visible = <int>[
    for (int column = 0; column < screen.columns; column++)
      screen.contentAt(0, column),
  ];
  _expect(
    visible.take(6).toList().toString() ==
            <int>[0x52, 0x45, 0x44, 0x20, 0x6f, 0x6b].toString() &&
        !visible.contains(0x1b) &&
        !visible.contains(0x5b),
    'VT control bytes are absent from the canonical visible grid',
  );

  final _CompositionFixture fixture = _compose(screens);
  try {
    final List<TerminalMetalInstance> glyphs = fixture.composition.instances
        .where((TerminalMetalInstance instance) => instance.kind.isGlyph)
        .toList();
    final int redRgba =
        ((screens.palette.resolveToken(
                  screen.foregroundAt(0, 0),
                  foreground: true,
                ) &
                0x00ffffff) <<
            8) |
        0xff;
    _expect(
      fixture.composition.shapedRunCount == 2,
      'compatible cells use two whole shaped runs',
    );
    _expect(
      fixture.composition.renderedCellCount == 6,
      'all six printable cells are represented '
      '(actual=${fixture.composition.renderedCellCount})',
    );
    _expect(
      glyphs.any(
        (TerminalMetalInstance instance) => instance.colorRgba == redRgba,
      ),
      'SGR foreground maps to the glyph mask color',
    );
    _expect(
      fixture.composition.instances.any(
        (TerminalMetalInstance instance) =>
            instance.kind == TerminalMetalInstanceKind.decoration,
      ),
      'SGR underline maps to the decoration layer',
    );
    _expect(
      fixture.composition.instances.any(
        (TerminalMetalInstance instance) =>
            instance.kind == TerminalMetalInstanceKind.cursor,
      ),
      'cursor state maps to the cursor layer',
    );
    final Uint8List rgba = fixture.renderer.renderRgba(
      fixture.composition.scheduledFrame.frame,
    );
    _expect(
      rgba.length == fixture.viewportWidth * fixture.viewportHeight * 4 &&
          rgba.any((int byte) => byte != 0),
      'canonical composition is accepted by the native Metal renderer',
    );
  } finally {
    fixture.dispose();
  }
}

void _testWrappedOverflowKeepsNewestPromptVisible() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 4);
  _parse(screens, ascii.encode('1111\r\n2222\r\nABCDEFGH\r\n\$ '));
  final TerminalScreen screen = screens.activeScreen;
  _expect(
    _rowText(screen, 0) == 'ABCD' &&
        _rowText(screen, 1) == 'EFGH' &&
        _rowText(screen, 2) == '\$   ' &&
        screen.cursorRow == 2 &&
        screen.cursorColumn == 2,
    'autowrap and overflow keep the newest prompt on the bottom screen row',
  );

  final _CompositionFixture fixture = _compose(screens);
  try {
    final int bottomTop = (2 * fixture.catalog.metrics.cellHeight).round();
    _expect(
      fixture.composition.renderedCellCount == 10 &&
          fixture.composition.instances.any(
            (TerminalMetalInstance instance) =>
                instance.kind.isGlyph && instance.y >= bottomTop,
          ) &&
          fixture.composition.instances.any(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.cursor &&
                instance.y >= bottomTop,
          ),
      'the Metal frame includes both the bottom prompt and its cursor',
    );
  } finally {
    fixture.dispose();
  }
}

void _testWideGraphemeUsesCanonicalGrid() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 8);
  _parse(screens, utf8.encode('A\u0301界Z'));
  final TerminalScreen screen = screens.activeScreen;
  _expect(
    screen.widthFlagsAt(0, 0) & TerminalCellFlags.grapheme != 0 &&
        screen.widthFlagsAt(0, 1) & TerminalCellFlags.widthMask ==
            TerminalCellFlags.wide &&
        screen.widthFlagsAt(0, 2) & TerminalCellFlags.widthMask ==
            TerminalCellFlags.continuation &&
        screen.contentAt(0, 3) == 0x5a,
    'combining and wide input retain canonical grapheme and column topology',
  );

  final _CompositionFixture fixture = _compose(screens);
  try {
    _expect(
      fixture.composition.shapedRunCount == 1 &&
          fixture.composition.renderedCellCount == 3 &&
          fixture.composition.scheduledFrame.frame.instanceCount <=
              fixture.renderer.config.maximumInstances,
      'wide and combining cells shape as one bounded terminal run',
    );
  } finally {
    fixture.dispose();
  }
}

void _testPreeditUsesTransientMetalLayers() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  _parse(screens, ascii.encode('12345'));
  final List<int> before = _screenContent(screens.activeScreen);
  final TerminalPreeditLayout preedit = TerminalPreeditLayout.compute(
    state: TerminalPreeditState(
      generation: 1,
      text: '界A',
      selectionLocation: 0,
      selectionLength: 1,
    ),
    startRow: screens.activeScreen.cursorRow,
    startColumn: screens.activeScreen.cursorColumn,
    rows: screens.activeScreen.rows,
    columns: screens.activeScreen.columns,
  );
  final _CompositionFixture fixture = _compose(screens, preedit: preedit);
  try {
    final int rowTop = fixture.catalog.metrics.cellHeight.round();
    final int selectedWidth = (fixture.catalog.metrics.cellWidth * 2).round();
    final int caretLeft = (fixture.catalog.metrics.cellWidth * 2).round();
    _expect(
      fixture.composition.preeditCellCount == 2 &&
          fixture.composition.shapedRunCount == 2 &&
          fixture.composition.instances.any(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.selection &&
                instance.x == 0 &&
                instance.y == rowTop &&
                instance.width == selectedWidth,
          ) &&
          fixture.composition.instances
                  .where(
                    (TerminalMetalInstance instance) =>
                        instance.kind == TerminalMetalInstanceKind.decoration &&
                        instance.y >= rowTop,
                  )
                  .length >=
              2 &&
          fixture.composition.instances.any(
            (TerminalMetalInstance instance) =>
                instance.kind == TerminalMetalInstanceKind.cursor &&
                instance.x == caretLeft &&
                instance.y == rowTop &&
                instance.width < fixture.catalog.metrics.cellWidth,
          ) &&
          _screenContent(screens.activeScreen).toString() == before.toString(),
      'preedit adds selected text, underline, and caret without editing the grid',
    );
    final Uint8List rgba = fixture.renderer.renderRgba(
      fixture.composition.scheduledFrame.frame,
    );
    _expect(
      rgba.any((int byte) => byte != 0),
      'CoreText preedit glyphs and overlay layers form a renderable Metal frame',
    );
  } finally {
    fixture.dispose();
  }
}

void _testPreeditRespectsRendererInstanceLimit() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 6);
  _parse(screens, ascii.encode('12345'));
  final TerminalPreeditLayout preedit = TerminalPreeditLayout.compute(
    state: TerminalPreeditState(
      generation: 1,
      text: 'AB',
      selectionLocation: 0,
      selectionLength: 0,
    ),
    startRow: screens.activeScreen.cursorRow,
    startColumn: screens.activeScreen.cursorColumn,
    rows: screens.activeScreen.rows,
    columns: screens.activeScreen.columns,
  );
  try {
    _compose(
      screens,
      preedit: preedit,
      rendererConfig: const TerminalMetalRendererConfig(maximumInstances: 8),
    );
  } on StateError catch (error) {
    _expect(
      error.message == 'Metal instance limit exceeded',
      'preedit exhaustion reports the renderer resource boundary',
    );
    return;
  }
  throw StateError('test failed: preedit frame cannot exceed instance limits');
}

_CompositionFixture _compose(
  TerminalScreenSet screens, {
  TerminalPreeditLayout? preedit,
  TerminalSelectionProjection? selection,
  int hoveredHyperlinkId = 0,
  double scale = 1,
  String fontFamily = 'Menlo',
  TerminalMetalRendererConfig rendererConfig =
      const TerminalMetalRendererConfig(),
  int contentOffsetX = 0,
  int contentOffsetY = 0,
  bool includeKittyImages = false,
  bool visualBellActive = false,
  TerminalAccessibilityPresentation accessibilityPresentation =
      const TerminalAccessibilityPresentation.standard(),
}) {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(
    family: fontFamily,
  );
  final TerminalShapingCache shapingCache = TerminalShapingCache(catalog);
  screens.updateLogicalCellSize(
    width: catalog.metrics.cellWidth,
    height: catalog.metrics.cellHeight,
  );
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: catalog.generation,
    scale: scale,
  );
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: rendererConfig,
  );
  final TerminalGlyphAtlasMetalBridge bridge = TerminalGlyphAtlasMetalBridge(
    atlas: atlas,
    renderer: renderer,
  );
  try {
    final TerminalDamagePacket packet = TerminalDamageCodec.capture(
      screens.activeScreen,
      damageGeneration: 1,
      requiredResourceGeneration: atlas.resourceGeneration,
    )!;
    final TerminalDecodedDamage damage = TerminalDamageCodec.decode(
      packet.copyBytes(),
    );
    final TerminalDamageRenderModel model = TerminalDamageRenderModel();
    final TerminalDamageApplyResult applied = model.apply(
      damage,
      availableResourceGeneration: atlas.resourceGeneration,
    );
    _expect(applied.isApplied, 'full screen damage applies to render model');
    final int contentViewportWidth = mathCeil(
      catalog.metrics.cellWidth * model.columns * scale,
    );
    final int contentViewportHeight = mathCeil(
      catalog.metrics.cellHeight * model.rows * scale,
    );
    final int viewportWidth = contentViewportWidth + contentOffsetX * 2;
    final int viewportHeight = contentViewportHeight + contentOffsetY * 2;
    final TerminalScreenMetalComposition composition =
        TerminalScreenMetalCompositor(
          catalog: catalog,
          shapingCache: shapingCache,
          atlas: atlas,
          bridge: bridge,
          styleTable: screens.styleTable,
          palette: screens.palette,
          graphemeTable: screens.graphemeTable,
          accessibilityPresentation: accessibilityPresentation,
        ).compose(
          model,
          frameGeneration: 1,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
          contentOffsetX: contentOffsetX,
          contentOffsetY: contentOffsetY,
          contentViewportWidth: contentViewportWidth,
          contentViewportHeight: contentViewportHeight,
          presentation: TerminalFramePresentation(
            revision: 1,
            cursorDrawn: true,
            visualBellActive: visualBellActive,
            requiresFullRedraw: true,
          ),
          preedit: preedit,
          selection: selection,
          kittyImages: includeKittyImages
              ? screens.captureKittyImageViewport()
              : null,
          hoveredHyperlinkId: hoveredHyperlinkId,
        );
    return _CompositionFixture(
      catalog: catalog,
      shapingCache: shapingCache,
      atlas: atlas,
      bridge: bridge,
      renderer: renderer,
      composition: composition,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  } on Object {
    bridge.abandonRenderer();
    renderer.dispose();
    shapingCache.dispose();
    catalog.dispose();
    rethrow;
  }
}

void _storeKittyImage(
  TerminalScreenSet screens, {
  required int imageId,
  required int width,
  required int height,
  required List<int> rgba,
}) {
  final stored = screens.primaryKittyImages.store(
    imageId: imageId,
    imageNumber: 0,
    width: width,
    height: height,
    transient: false,
    rgba: Uint8List.fromList(rgba),
  );
  _expect(stored.image != null, 'Kitty Metal fixture stores image $imageId');
}

void _placeKittyImage(
  TerminalScreenSet screens, {
  required int imageId,
  required int column,
  required int z,
}) {
  final TerminalLogicalAnchor anchor = screens.viewport.anchorAtScreenCell(
    TerminalScreenKind.primary,
    0,
    column,
  );
  final placed = screens.primaryKittyImages.place(
    imageId: imageId,
    imageNumber: 0,
    placementId: imageId,
    logicalLineId: anchor.logicalLineId,
    logicalLineEpoch: anchor.logicalLineEpoch,
    logicalCellOffset: anchor.cellOffset,
    sourceX: 0,
    sourceY: 0,
    sourceWidth: 0,
    sourceHeight: 0,
    cellOffsetX: 0,
    cellOffsetY: 0,
    columns: 1,
    rows: 1,
    z: z,
  );
  _expect(
    placed.placement != null,
    'Kitty Metal fixture places image $imageId',
  );
}

List<int> _screenContent(TerminalScreen screen) => <int>[
  for (int row = 0; row < screen.rows; row++)
    for (int column = 0; column < screen.columns; column++)
      screen.contentAt(row, column),
];

void _parse(TerminalScreenSet screens, List<int> bytes) {
  final VtParser parser = VtParser(
    sink: TerminalScreenParserSink.forScreenSet(screens),
  );
  parser.parse(Uint8List.fromList(bytes));
  parser.finish();
}

String _rowText(TerminalScreen screen, int row) => String.fromCharCodes(<int>[
  for (int column = 0; column < screen.columns; column++)
    screen.contentAt(row, column) == 0 ? 0x20 : screen.contentAt(row, column),
]);

int mathCeil(double value) => value.ceil();

final class _CompositionFixture {
  const _CompositionFixture({
    required this.catalog,
    required this.shapingCache,
    required this.atlas,
    required this.bridge,
    required this.renderer,
    required this.composition,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final TerminalFontCatalog catalog;
  final TerminalShapingCache shapingCache;
  final TerminalGlyphAtlas atlas;
  final TerminalGlyphAtlasMetalBridge bridge;
  final TerminalMetalRenderer renderer;
  final TerminalScreenMetalComposition composition;
  final int viewportWidth;
  final int viewportHeight;

  void dispose() {
    bridge.abandonRenderer();
    renderer.dispose();
    shapingCache.dispose();
    catalog.dispose();
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
