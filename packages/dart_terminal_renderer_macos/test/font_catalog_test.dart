import 'dart:ffi';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_font_catalog_count',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _liveFontCatalogCount();

void runFontCatalogTests() {
  _expect(_liveFontCatalogCount() == 0, 'catalog registry starts empty');
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  try {
    final TerminalFontCatalogMetrics metrics = catalog.metrics;
    _expect(
      catalog.generation > 0 &&
          !catalog.isDisposed &&
          metrics.pointSize == 14 &&
          metrics.cellWidth > 0 &&
          metrics.cellHeight > 0 &&
          metrics.ascent > 0 &&
          metrics.descent > 0 &&
          metrics.leading >= 0 &&
          metrics.baseline == metrics.ascent &&
          metrics.underlinePosition.isFinite &&
          metrics.underlineThickness > 0 &&
          metrics.strikePosition > 0 &&
          metrics.strikeThickness > 0,
      'catalog exposes finite usable terminal metrics',
    );
    _expect(
      catalog.isStyleAvailable(TerminalFontStyle.regular) &&
          catalog.faceIdForStyle(TerminalFontStyle.regular) > 0,
      'regular face is always selectable',
    );
    for (final TerminalFontStyle style in TerminalFontStyle.values) {
      _expect(
        catalog.isStyleAvailable(style) || catalog.isStyleSynthetic(style),
        '$style has an explicit actual or synthetic policy',
      );
      _expect(catalog.faceIdForStyle(style) > 0, '$style has a face identity');
    }

    final TerminalResolvedFont latin = catalog.resolve('terminal');
    _expect(
      latin.catalogGeneration == catalog.generation &&
          latin.faceId == catalog.faceIdForStyle(TerminalFontStyle.regular) &&
          !latin.isFallback &&
          !latin.hasColorGlyphs &&
          !latin.hasMissingGlyph &&
          latin.isMonospaced &&
          latin.utf16Length == 8 &&
          latin.unicodeScalarCount == 8 &&
          latin.glyphCount > 0 &&
          latin.postscriptName.contains('Menlo'),
      'Latin resolves to the requested monospace face',
    );
    final TerminalResolvedFont bold = catalog.resolve(
      'B',
      style: TerminalFontStyle.bold,
    );
    _expect(
      bold.requestedStyle == TerminalFontStyle.bold &&
          bold.faceId == catalog.faceIdForStyle(TerminalFontStyle.bold) &&
          bold.isSynthetic == catalog.isStyleSynthetic(TerminalFontStyle.bold),
      'bold resolution preserves explicit style policy and face ID',
    );
    final TerminalResolvedFont cjk = catalog.resolve('日本語');
    _expect(
      cjk.isFallback &&
          !cjk.hasMissingGlyph &&
          cjk.unicodeScalarCount == 3 &&
          cjk.utf16Length == 3 &&
          cjk.postscriptName.isNotEmpty &&
          cjk.postscriptName != latin.postscriptName,
      'CJK resolves to a real fallback face',
    );
    final TerminalResolvedFont emoji = catalog.resolve('👩🏽‍💻');
    _expect(
      emoji.isFallback &&
          emoji.hasColorGlyphs &&
          !emoji.hasMissingGlyph &&
          emoji.unicodeScalarCount == 4 &&
          emoji.utf16Length == 7 &&
          emoji.postscriptName.contains('AppleColorEmoji'),
      'emoji cluster resolves to the color fallback face',
    );
    _expect(_liveFontCatalogCount() == 1, 'catalog registry owns one handle');
  } finally {
    catalog.dispose();
  }
  catalog.dispose();
  _expect(
    catalog.isDisposed && _liveFontCatalogCount() == 0,
    'catalog disposal is idempotent and releases the native handle once',
  );
  _expectThrows<StateError>(
    () => catalog.resolve('x'),
    'disposed catalog cannot resolve',
  );

  final TerminalFontCatalog system = TerminalFontCatalog.open(family: '');
  _expect(
    system.resolve('x').isMonospaced,
    'empty family selects the system monospace face deterministically',
  );
  system.dispose();

  _expectThrows<TerminalFontCatalogException>(
    () => TerminalFontCatalog.open(family: 'Definitely Missing Font 12345'),
    'unknown family is rejected',
  );
  _expectThrows<RangeError>(
    () => TerminalFontCatalog.open(pointSize: 2),
    'point size lower bound',
  );
  _expectThrows<ArgumentError>(
    () => TerminalFontCatalog.open(family: 'Menlo\u0000Bad'),
    'font family NUL rejection',
  );
  final TerminalFontCatalog input = TerminalFontCatalog.open();
  try {
    _expectThrows<ArgumentError>(() => input.resolve(''), 'empty text');
    _expectThrows<ArgumentError>(
      () => input.resolve('x\u0000y'),
      'resolve text NUL rejection',
    );
  } finally {
    input.dispose();
  }
  _expect(_liveFontCatalogCount() == 0, 'all test catalogs are released');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('font catalog expectation failed: $description');
  }
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
      'font catalog expectation failed: $description threw '
      '${error.runtimeType}',
    );
  }
  throw StateError('font catalog expectation failed: $description');
}
