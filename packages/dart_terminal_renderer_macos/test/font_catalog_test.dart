import 'dart:ffi';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_font_catalog_count',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _liveFontCatalogCount();

void runFontCatalogTests() {
  _testBoundedFontCatalogConfiguration();
  _testContentFreeFontDiagnostics();
  _testConfiguredNativeFontCatalog();
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

void _testConfiguredNativeFontCatalog() {
  final TerminalFontCatalogConfiguration configuration =
      TerminalFontCatalogConfiguration(
        regularVariations: <TerminalFontVariationAxis>[
          TerminalFontVariationAxis('wght', 800),
          TerminalFontVariationAxis('ZZZZ', 1),
        ],
        codepointOverrides: <TerminalFontCodepointOverride>[
          TerminalFontCodepointOverride(
            firstScalar: 0x41,
            lastScalar: 0x43,
            family: 'Times-Roman',
          ),
          TerminalFontCodepointOverride(
            firstScalar: 0x41,
            lastScalar: 0x41,
            family: 'Menlo',
          ),
          TerminalFontCodepointOverride(
            firstScalar: 0x43,
            lastScalar: 0x43,
            family: 'Definitely Missing Font 12345',
          ),
          TerminalFontCodepointOverride(
            firstScalar: 0x1f600,
            lastScalar: 0x1f600,
            family: 'Times-Roman',
          ),
        ],
      );
  final TerminalFontCatalog configured = TerminalFontCatalog.open(
    family: '',
    configuration: configuration,
  );
  final TerminalFontCatalog baseline = TerminalFontCatalog.open(family: '');
  try {
    _expect(
      configured.configuration == configuration &&
          configured.metrics.pointSize == 14 &&
          configured.generation != baseline.generation,
      'configured catalog owns one immutable native generation',
    );
    final TerminalResolvedFont resolvedA = configured.resolve('A');
    final TerminalResolvedFont resolvedB = configured.resolve('B');
    final TerminalResolvedFont resolvedC = configured.resolve('C');
    final TerminalResolvedFont resolvedSmile = configured.resolve('😀');
    _expect(
      resolvedA.postscriptName.contains('Menlo') &&
          resolvedB.postscriptName.contains('Times') &&
          resolvedC.faceId ==
              configured.faceIdForStyle(TerminalFontStyle.regular) &&
          !resolvedC.hasMissingGlyph &&
          !resolvedC.postscriptName.contains('Missing') &&
          resolvedSmile.isFallback &&
          resolvedSmile.hasColorGlyphs &&
          !resolvedSmile.hasMissingGlyph &&
          resolvedSmile.postscriptName.contains('AppleColorEmoji'),
      'later ranges win and unusable mappings return to normal fallback',
    );
    final TerminalFontCatalogDiagnostics initial = configured.diagnostics();
    _expect(
      initial.catalogGeneration == configured.generation &&
          initial.configuredVariationCount == 2 &&
          initial.appliedVariationCount == 1 &&
          initial.unavailableVariationCount == 1 &&
          initial.configuredOverrideCount == 4 &&
          initial.availableOverrideCount == 3 &&
          initial.unavailableOverrideCount == 1 &&
          initial.overrideMatchCount == 4 &&
          initial.overrideAppliedCount == 2 &&
          initial.overrideFallbackCount == 2 &&
          initial.coreTextFallbackCount == 1 &&
          initial.missingGlyphCount == 0 &&
          initial.resolutions.length == 4 &&
          initial.resolutions.any(
            (TerminalFontResolutionDiagnostic record) =>
                record.source ==
                    TerminalFontResolutionSource.codepointOverride &&
                record.postscriptName.contains('Menlo'),
          ) &&
          initial.resolutions.any(
            (TerminalFontResolutionDiagnostic record) =>
                record.source ==
                    TerminalFontResolutionSource.codepointOverride &&
                record.postscriptName.contains('Times'),
          ) &&
          initial.resolutions.any(
            (TerminalFontResolutionDiagnostic record) =>
                record.source == TerminalFontResolutionSource.requested,
          ) &&
          initial.resolutions.any(
            (TerminalFontResolutionDiagnostic record) =>
                record.source ==
                    TerminalFontResolutionSource.coreTextFallback &&
                record.postscriptName.contains('AppleColorEmoji'),
          ),
      'native diagnostics expose bounded source counts and face identities',
    );

    final TerminalShapedText shaped = configured.shape(
      'ABC',
      options: const TerminalShapingOptions(ligatures: false),
    );
    final TerminalGlyphRasterBatch raster = configured.rasterizeShaped(
      shaped,
      scale: 2,
    );
    _expect(
      shaped.runs.length == 3 &&
          shaped.faces.length == 3 &&
          !shaped.hasMissingGlyph &&
          raster.glyphs.length == 3 &&
          raster.pixelByteLength > 0,
      'configured faces preserve ownership through shape and raster copies',
    );
    final TerminalFontCatalogDiagnostics afterShape = configured.diagnostics();
    _expect(
      afterShape.overrideMatchCount == 7 &&
          afterShape.overrideAppliedCount == 4 &&
          afterShape.overrideFallbackCount == 3,
      'successful shaping records each mapped scalar exactly once',
    );

    final TerminalRasterizedGlyph configuredM = configured
        .rasterizeShaped(configured.shape('M'), scale: 2)
        .glyphs
        .single;
    final TerminalRasterizedGlyph baselineM = baseline
        .rasterizeShaped(baseline.shape('M'), scale: 2)
        .glyphs
        .single;
    final int configuredCoverage = configuredM.copyPixels().fold<int>(
      0,
      (int total, int value) => total + value,
    );
    final int baselineCoverage = baselineM.copyPixels().fold<int>(
      0,
      (int total, int value) => total + value,
    );
    _expect(
      configuredCoverage > baselineCoverage &&
          configured.metrics.pointSize == baseline.metrics.pointSize,
      'supported weight axis changes glyph ink without changing point size',
    );
  } finally {
    configured.dispose();
    baseline.dispose();
  }
  _expectThrows<StateError>(
    configured.diagnostics,
    'disposed configured catalog cannot expose diagnostics',
  );
  _expect(
    _liveFontCatalogCount() == 0,
    'configured and baseline catalogs release every native face',
  );
}

void _testBoundedFontCatalogConfiguration() {
  final TerminalFontVariationAxis regularWeight = TerminalFontVariationAxis(
    'wght',
    425,
  );
  final TerminalFontVariationAxis boldWeight = TerminalFontVariationAxis(
    'wght',
    725,
  );
  final TerminalFontCodepointOverride broad = TerminalFontCodepointOverride(
    firstScalar: 0x2500,
    lastScalar: 0x257f,
    family: 'Menlo',
  );
  final TerminalFontCodepointOverride narrow = TerminalFontCodepointOverride(
    firstScalar: 0x2500,
    lastScalar: 0x2502,
    family: 'Times-Roman',
  );
  final TerminalFontCatalogConfiguration configuration =
      TerminalFontCatalogConfiguration(
        regularVariations: <TerminalFontVariationAxis>[regularWeight],
        boldVariations: <TerminalFontVariationAxis>[boldWeight],
        codepointOverrides: <TerminalFontCodepointOverride>[broad, narrow],
      );
  _expect(
    regularWeight.encodedTag == 0x77676874 &&
        regularWeight == TerminalFontVariationAxis('wght', 425) &&
        regularWeight != boldWeight &&
        configuration.variationCount == 2 &&
        configuration.overrideFamilyUtf8Bytes == 16 &&
        !configuration.isEmpty &&
        configuration.variationsFor(TerminalFontStyle.regular).single ==
            regularWeight &&
        configuration.variationsFor(TerminalFontStyle.bold).single ==
            boldWeight &&
        configuration.overrideForScalar(0x2501) == narrow &&
        configuration.overrideForScalar(0x2520) == broad &&
        configuration.overrideForScalar(0x41) == null &&
        TerminalFontCatalogConfiguration.empty.isEmpty,
    'font configuration is immutable, style-owned, and later-map-wins',
  );
  _expectThrows<UnsupportedError>(
    () => configuration
        .variationsFor(TerminalFontStyle.regular)
        .add(TerminalFontVariationAxis('wdth', 100)),
    'variation list is immutable',
  );
  _expectThrows<UnsupportedError>(
    () => configuration.codepointOverrides.add(broad),
    'override list is immutable',
  );

  for (final String invalidTag in <String>[
    'wgt',
    'weight',
    'wg\u0000t',
    '幅軸',
  ]) {
    _expectThrows<ArgumentError>(
      () => TerminalFontVariationAxis(invalidTag, 1),
      'invalid OpenType tag $invalidTag',
    );
  }
  for (final double invalidValue in <double>[
    double.nan,
    double.infinity,
    -65537,
    65537,
  ]) {
    _expectThrows<RangeError>(
      () => TerminalFontVariationAxis('wght', invalidValue),
      'invalid variation coordinate $invalidValue',
    );
  }
  _expectThrows<ArgumentError>(
    () => TerminalFontCatalogConfiguration(
      regularVariations: <TerminalFontVariationAxis>[
        TerminalFontVariationAxis('wght', 400),
        TerminalFontVariationAxis('wght', 500),
      ],
    ),
    'duplicate axis tag in one style',
  );
  _expectThrows<RangeError>(
    () => TerminalFontCatalogConfiguration(
      regularVariations: List<TerminalFontVariationAxis>.generate(
        TerminalFontCatalogConfiguration.maximumVariationsPerStyle + 1,
        (int index) => TerminalFontVariationAxis(
          String.fromCharCodes(<int>[
            0x41 + index ~/ 10,
            0x30 + index % 10,
            0x78,
            0x79,
          ]),
          index.toDouble(),
        ),
      ),
    ),
    'per-style variation cap',
  );
  for (final ({int first, int last}) range in <({int first, int last})>[
    (first: -1, last: 1),
    (first: 2, last: 1),
    (first: 0xd800, last: 0xd800),
    (first: 0xd7ff, last: 0xe000),
    (first: 0x110000, last: 0x110000),
  ]) {
    _expectThrows<ArgumentError>(
      () => TerminalFontCodepointOverride(
        firstScalar: range.first,
        lastScalar: range.last,
        family: 'Menlo',
      ),
      'invalid scalar range ${range.first}..${range.last}',
    );
  }
  _expectThrows<ArgumentError>(
    () => TerminalFontCodepointOverride(
      firstScalar: 0x41,
      lastScalar: 0x41,
      family: '',
    ),
    'empty override family',
  );
  _expectThrows<RangeError>(
    () => TerminalFontCatalogConfiguration(
      codepointOverrides: List<TerminalFontCodepointOverride>.filled(
        TerminalFontCatalogConfiguration.maximumCodepointOverrides + 1,
        broad,
      ),
    ),
    'override entry cap',
  );
  final TerminalFontCodepointOverride maximumFamily =
      TerminalFontCodepointOverride(
        firstScalar: 0x41,
        lastScalar: 0x41,
        family: 'A' * TerminalFontCatalog.maximumFamilyBytes,
      );
  _expectThrows<RangeError>(
    () => TerminalFontCatalogConfiguration(
      codepointOverrides: List<TerminalFontCodepointOverride>.filled(
        TerminalFontCatalogConfiguration.maximumOverrideFamilyUtf8Bytes ~/
                TerminalFontCatalog.maximumFamilyBytes +
            1,
        maximumFamily,
      ),
    ),
    'aggregate override family byte cap',
  );
}

void _testContentFreeFontDiagnostics() {
  final TerminalFontResolutionDiagnostic fallback =
      TerminalFontResolutionDiagnostic(
        source: TerminalFontResolutionSource.coreTextFallback,
        faceId: 2,
        flags:
            TerminalResolvedFontFlags.fallback |
            TerminalResolvedFontFlags.monospaced,
        postscriptName: 'HiraginoSans-W3',
        occurrenceCount: 3,
      );
  final TerminalFontCatalogDiagnostics diagnostics =
      TerminalFontCatalogDiagnostics(
        catalogGeneration: 9,
        configuredVariationCount: 2,
        appliedVariationCount: 1,
        unavailableVariationCount: 1,
        configuredOverrideCount: 2,
        availableOverrideCount: 1,
        unavailableOverrideCount: 1,
        overrideMatchCount: 5,
        overrideAppliedCount: 4,
        overrideFallbackCount: 1,
        coreTextFallbackCount: 3,
        missingGlyphCount: 0,
        resolutions: <TerminalFontResolutionDiagnostic>[fallback],
      );
  _expect(
    diagnostics.catalogGeneration == 9 &&
        diagnostics.resolutions.single.source ==
            TerminalFontResolutionSource.coreTextFallback &&
        diagnostics.resolutions.single.isFallback &&
        !diagnostics.resolutions.single.hasMissingGlyph &&
        diagnostics.resolutions.single.postscriptName == 'HiraginoSans-W3' &&
        diagnostics.resolutions.single.occurrenceCount == 3,
    'diagnostics expose only bounded counters and face identity',
  );
  _expectThrows<UnsupportedError>(
    () => diagnostics.resolutions.add(fallback),
    'diagnostic records are immutable',
  );
  _expectThrows<ArgumentError>(
    () => TerminalFontCatalogDiagnostics(
      catalogGeneration: 1,
      configuredVariationCount: 1,
      appliedVariationCount: 1,
      unavailableVariationCount: 1,
      configuredOverrideCount: 0,
      availableOverrideCount: 0,
      unavailableOverrideCount: 0,
      overrideMatchCount: 0,
      overrideAppliedCount: 0,
      overrideFallbackCount: 0,
      coreTextFallbackCount: 0,
      missingGlyphCount: 0,
    ),
    'inconsistent diagnostic totals',
  );
  _expectThrows<ArgumentError>(
    () => TerminalFontCatalogDiagnostics(
      catalogGeneration: 1,
      configuredVariationCount: 0,
      appliedVariationCount: 0,
      unavailableVariationCount: 0,
      configuredOverrideCount: 0,
      availableOverrideCount: 0,
      unavailableOverrideCount: 0,
      overrideMatchCount: 0,
      overrideAppliedCount: 0,
      overrideFallbackCount: 0,
      coreTextFallbackCount: 1,
      missingGlyphCount: 0,
      resolutions: <TerminalFontResolutionDiagnostic>[fallback, fallback],
    ),
    'duplicate diagnostic identity',
  );
  _expectThrows<ArgumentError>(
    () => TerminalFontResolutionDiagnostic(
      source: TerminalFontResolutionSource.missingGlyph,
      faceId: 1,
      flags: 1 << 20,
      postscriptName: 'Menlo-Regular',
      occurrenceCount: 1,
    ),
    'unknown diagnostic flags',
  );
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
