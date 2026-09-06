import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalScreenMetalCompositorTests();

void runTerminalScreenMetalCompositorTests() {
  _testAnsiStylesBecomeMetalLayers();
  _testInverseBackgroundAndConcealMapping();
  _testWrappedOverflowKeepsNewestPromptVisible();
  _testWideGraphemeUsesCanonicalGrid();
  _testPreeditUsesTransientMetalLayers();
  _testPreeditRespectsRendererInstanceLimit();
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
  TerminalMetalRendererConfig rendererConfig =
      const TerminalMetalRendererConfig(),
}) {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  final TerminalShapingCache shapingCache = TerminalShapingCache(catalog);
  final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
    catalogGeneration: catalog.generation,
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
    final int viewportWidth = mathCeil(
      catalog.metrics.cellWidth * model.columns,
    );
    final int viewportHeight = mathCeil(
      catalog.metrics.cellHeight * model.rows,
    );
    final TerminalScreenMetalComposition composition =
        TerminalScreenMetalCompositor(
          catalog: catalog,
          shapingCache: shapingCache,
          atlas: atlas,
          bridge: bridge,
          styleTable: screens.styleTable,
          palette: screens.palette,
          graphemeTable: screens.graphemeTable,
        ).compose(
          model,
          frameGeneration: 1,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
          presentation: const TerminalFramePresentation(
            revision: 1,
            cursorDrawn: true,
            visualBellActive: false,
            requiresFullRedraw: true,
          ),
          preedit: preedit,
        );
    return _CompositionFixture(
      catalog: catalog,
      shapingCache: shapingCache,
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
    required this.bridge,
    required this.renderer,
    required this.composition,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final TerminalFontCatalog catalog;
  final TerminalShapingCache shapingCache;
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
