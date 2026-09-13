import 'dart:convert';
import 'dart:io';

import '../tool/ghostty_p0_p1_gap_inventory.dart';

void main() => runGhosttyP0P1GapInventoryTests();

void runGhosttyP0P1GapInventoryTests() {
  final String generated = generateGhosttyP0P1GapInventory();
  final String committed = File(ghosttyP0P1GapInventoryPath).readAsStringSync();
  final GhosttyP0P1GapInventoryResult result =
      validateGhosttyP0P1GapInventorySource(
        committed,
        expectedSource: generated,
      );
  _expect(
    result.rows == 102 &&
        result.accepted == 96 &&
        result.actionableP0 == 0 &&
        result.actionableP1 == 1 &&
        result.documentedDifferences == 2 &&
        result.externalFollowUps == 3,
    'reviewed result totals are exact',
  );
  final Map<String, Object?> report =
      jsonDecode(committed) as Map<String, Object?>;
  final List<Object?> rows = report['rows']! as List<Object?>;
  final List<Object?> gaps = report['gaps']! as List<Object?>;
  _expect(
    rows.length == 102 &&
        gaps.length == 6 &&
        rows
                .cast<Map<String, Object?>>()
                .where((row) => row['classification'] == 'actionable-p1')
                .length ==
            1 &&
        gaps
            .cast<Map<String, Object?>>()
            .where((gap) => gap['silent_misbehavior'] == true)
            .isEmpty,
    'every row and reviewed gap is represented',
  );
  _expectFailure(
    committed.replaceFirst('"actionable_p1": 1', '"actionable_p1": 2'),
    generated,
    'stale actionable total',
  );
  _expectFailure(
    committed.replaceFirst(
      '"pinned_ghostty_revision": "d4d8f622',
      '"pinned_ghostty_revision": "00000000',
    ),
    generated,
    'pinned revision drift',
  );
  final String matrix = File('FEATURE_MATRIX.md').readAsStringSync();
  _expectMatrixFailure(
    matrix.replaceFirst('| RT-02 |', '| RT-01 |'),
    'duplicate row',
  );
  _expectMatrixFailure(
    matrix.replaceFirst(
      'ghostty-org/ghostty@d4d8f62262cb1a974a7d2470d5f79f811fab15e4',
      'ghostty-org/ghostty@0000000000000000000000000000000000000000',
    ),
    'matrix revision drift',
  );
  final String sequenceInventory = File(
    'compatibility/sequence_mode_inventory.json',
  ).readAsStringSync();
  final String applicationAcceptance = File(
    'compatibility/application_matrix_acceptance.json',
  ).readAsStringSync();
  final String regressionCoverage = File(
    'compatibility/regression_coverage_report.json',
  ).readAsStringSync();
  final String implementationManifest = File(
    'compatibility/implemented_sequence_manifest.json',
  ).readAsStringSync();
  validateGhosttyP0ClosureSources(
    sequenceInventorySource: sequenceInventory,
    applicationAcceptanceSource: applicationAcceptance,
    regressionCoverageSource: regressionCoverage,
  );
  _expectP0Failure(
    sequenceInventory,
    applicationAcceptance.replaceFirst(
      '"screen_mutation": false',
      '"screen_mutation": true',
    ),
    regressionCoverage,
    'screen-mutating documented difference',
  );
  _expectP0Failure(
    sequenceInventory.replaceFirst(
      '"id": "xterm:mode:xterm-hilite-mouse-tracking",',
      '"id": "xterm:mode:unowned-hilite-mouse-tracking",',
    ),
    applicationAcceptance,
    regressionCoverage,
    'missing exact inventory owner',
  );
  _expectP0Failure(
    sequenceInventory,
    applicationAcceptance,
    regressionCoverage.replaceFirst(
      '"known_p0_silent_corruption": 0',
      '"known_p0_silent_corruption": 1',
    ),
    'silent P0 regression',
  );
  validateGhosttyP1ExtendedRenditionClosureSources(
    sequenceInventorySource: sequenceInventory,
    implementationManifestSource: implementationManifest,
  );
  _expectP1Failure(
    sequenceInventory.replaceFirst(
      '"id": "dec:csi:decsel",',
      '"id": "dec:csi:unowned-decsel",',
    ),
    implementationManifest,
    'missing DECSEL evidence',
  );
  _expectP1Failure(
    sequenceInventory,
    implementationManifest.replaceFirst(
      '"key": "csi:-1:1:34:113",',
      '"key": "csi:-1:1:34:114",',
    ),
    'missing DECSCA selector',
  );
  final String semanticRangeSource = File(
    'lib/src/terminal_core/terminal_semantic_ranges.dart',
  ).readAsStringSync();
  final String semanticRangeTestSource = File(
    'test/terminal_semantic_prompt_test.dart',
  ).readAsStringSync();
  validateGhosttyP1SemanticRangeClosureSources(
    sequenceInventorySource: sequenceInventory,
    semanticRangeSource: semanticRangeSource,
    semanticRangeTestSource: semanticRangeTestSource,
  );
  _expectSemanticRangeFailure(
    sequenceInventory,
    semanticRangeSource.replaceFirst(
      'class TerminalSemanticRangeSnapshot',
      'class MissingSemanticRangeSnapshot',
    ),
    semanticRangeTestSource,
    'missing bounded semantic range contract',
  );
  _expectSemanticRangeFailure(
    sequenceInventory,
    semanticRangeSource,
    semanticRangeTestSource.replaceAll(
      '_testRangesSurviveHistoryAndReflowThenRejectEviction',
      '_missingHistoryReflowEvictionTest',
    ),
    'missing history/reflow/eviction regression',
  );
  final String snapshotFormatterSource = File(
    'lib/src/terminal_core/terminal_snapshot.dart',
  ).readAsStringSync();
  final String snapshotRestoreSource = File(
    'lib/src/terminal_core/terminal_snapshot_restore.dart',
  ).readAsStringSync();
  final String snapshotRestoreTestSource = File(
    'test/terminal_snapshot_test.dart',
  ).readAsStringSync();
  validateGhosttyP1SnapshotRestoreClosureSources(
    snapshotFormatterSource: snapshotFormatterSource,
    snapshotRestoreSource: snapshotRestoreSource,
    snapshotRestoreTestSource: snapshotRestoreTestSource,
  );
  _expectSnapshotRestoreFailure(
    snapshotFormatterSource,
    snapshotRestoreSource.replaceFirst(
      'if (canonical != source)',
      'if (false)',
    ),
    snapshotRestoreTestSource,
    'missing canonical identity check',
  );
  _expectSnapshotRestoreFailure(
    snapshotFormatterSource,
    snapshotRestoreSource,
    snapshotRestoreTestSource.replaceFirst('restored == 8', 'restored == 7'),
    'missing complete checked-in corpus coverage',
  );
  final String compositorSource = File(
    'lib/src/terminal_renderer/terminal_screen_metal_compositor.dart',
  ).readAsStringSync();
  final String compositorTestSource = File(
    'test/terminal_screen_metal_compositor_test.dart',
  ).readAsStringSync();
  validateGhosttyP1CursorLigatureClosureSources(
    compositorSource: compositorSource,
    compositorTestSource: compositorTestSource,
  );
  _expectCursorLigatureFailure(
    compositorSource.replaceAll(
      '_cursorShapingBreak',
      '_missingCursorShapingBreak',
    ),
    compositorTestSource,
    'missing cursor shaping-break implementation',
  );
  _expectCursorLigatureFailure(
    compositorSource,
    compositorTestSource.replaceAll(
      '_testCursorShapingBreakKeepsWideAndGraphemeCellsAtomic',
      '_missingWideAndGraphemeAtomicityTest',
    ),
    'missing wide/grapheme atomicity regression',
  );
  final String rendererConfigurationSource = File(
    'packages/dart_terminal_renderer_macos/lib/src/font_configuration.dart',
  ).readAsStringSync();
  final String rendererCatalogSource = File(
    'packages/dart_terminal_renderer_macos/lib/src/font_catalog.dart',
  ).readAsStringSync();
  final String rendererNativeHeaderSource = File(
    'packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.h',
  ).readAsStringSync();
  final String rendererNativeSource = File(
    'packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m',
  ).readAsStringSync();
  final String rendererNativeTestSource = File(
    'packages/dart_terminal_renderer_macos/native/test/TerminalRendererCapabilityTests.mm',
  ).readAsStringSync();
  final String rendererTestSource = File(
    'packages/dart_terminal_renderer_macos/test/font_catalog_test.dart',
  ).readAsStringSync();
  final String productConfigurationSource = File(
    'lib/src/terminal_product_configuration.dart',
  ).readAsStringSync();
  final String productDiagnosticsSource = File(
    'lib/src/terminal_diagnostics.dart',
  ).readAsStringSync();
  final String productApplicationSource = File(
    'lib/src/terminal_application.dart',
  ).readAsStringSync();
  final String runtimeSmokeSource = File('tool/runtime_integration_smoke.dart')
      .readAsStringSync();
  final String cellGlyphSource = File(
    'lib/src/terminal_renderer/terminal_cell_glyph.dart',
  ).readAsStringSync();
  final String atlasSource = File('lib/src/terminal_renderer/glyph_atlas.dart')
      .readAsStringSync();
  final String overlaySource = File(
    'lib/src/terminal_renderer/terminal_overlay.dart',
  ).readAsStringSync();
  final String referenceRendererSource = File(
    'lib/src/terminal_renderer/reference_renderer.dart',
  ).readAsStringSync();
  final String kittyControllerSource = File(
    'lib/src/terminal_kitty_graphics_controller.dart',
  ).readAsStringSync();
  final String shaderSource = File(
    'packages/dart_terminal_renderer_macos/native/TerminalShaders.metal',
  ).readAsStringSync();
  final String metalTestSource = File('test/metal_pipeline_test.dart')
      .readAsStringSync();
  final String rasterTestSource = File('test/terminal_cell_glyph_test.dart')
      .readAsStringSync();
  validateGhosttyP1SyntheticCellGlyphClosureSources(
    cellGlyphSource: cellGlyphSource,
    atlasSource: atlasSource,
    compositorSource: compositorSource,
    rasterTestSource: rasterTestSource,
    compositorTestSource: compositorTestSource,
    productApplicationSource: productApplicationSource,
    runtimeSmokeSource: runtimeSmokeSource,
  );
  _expectSyntheticCellGlyphFailure(
    cellGlyphSource.replaceFirst(
      'acceptedScalarCount = 434',
      'acceptedScalarCount = 433',
    ),
    atlasSource,
    compositorSource,
    rasterTestSource,
    compositorTestSource,
    productApplicationSource,
    runtimeSmokeSource,
    'weakened accepted scalar count',
  );
  _expectSyntheticCellGlyphFailure(
    cellGlyphSource,
    atlasSource,
    compositorSource,
    rasterTestSource,
    compositorTestSource.replaceAll(
      'test/goldens/cell-glyphs/synthetic-corpus-',
      'test/goldens/cell-glyphs/missing-corpus-',
    ),
    productApplicationSource,
    runtimeSmokeSource,
    'missing 1x/2x checked-in corpus evidence',
  );
  _expectSyntheticCellGlyphFailure(
    cellGlyphSource,
    atlasSource,
    compositorSource,
    rasterTestSource,
    compositorTestSource,
    productApplicationSource,
    runtimeSmokeSource.replaceAll('cell_glyphs=true', 'cell_glyphs=false'),
    'missing two-runtime synthetic-cell acceptance marker',
  );
  validateGhosttyP1OverlayColorClosureSources(
    kittyControllerSource: kittyControllerSource,
    overlaySource: overlaySource,
    atlasSource: atlasSource,
    referenceRendererSource: referenceRendererSource,
    compositorSource: compositorSource,
    nativeRendererSource: rendererNativeSource,
    shaderSource: shaderSource,
    metalTestSource: metalTestSource,
    productApplicationSource: productApplicationSource,
    runtimeSmokeSource: runtimeSmokeSource,
  );
  _expectOverlayColorFailure(
    kittyControllerSource,
    overlaySource,
    atlasSource,
    referenceRendererSource,
    compositorSource,
    rendererNativeSource,
    shaderSource,
    metalTestSource.replaceFirst(
      'test/goldens/overlay-color/closure-',
      'test/goldens/overlay-color/missing-',
    ),
    productApplicationSource,
    runtimeSmokeSource,
    'missing checked-in overlay/color corpus evidence',
  );
  _expectOverlayColorFailure(
    kittyControllerSource,
    overlaySource,
    atlasSource,
    referenceRendererSource,
    compositorSource,
    rendererNativeSource,
    shaderSource,
    metalTestSource,
    productApplicationSource,
    runtimeSmokeSource.replaceFirst(
      'search_overlay=true p3_color=true',
      'search_overlay=true',
    ),
    'missing two-runtime search/P3 acceptance marker',
  );
  validateGhosttyP1FontResolutionClosureSources(
    rendererConfigurationSource: rendererConfigurationSource,
    rendererCatalogSource: rendererCatalogSource,
    rendererNativeHeaderSource: rendererNativeHeaderSource,
    rendererNativeSource: rendererNativeSource,
    rendererNativeTestSource: rendererNativeTestSource,
    rendererTestSource: rendererTestSource,
    productConfigurationSource: productConfigurationSource,
    productDiagnosticsSource: productDiagnosticsSource,
    productApplicationSource: productApplicationSource,
    runtimeSmokeSource: runtimeSmokeSource,
  );
  _expectFontResolutionFailure(
    rendererConfigurationSource.replaceFirst(
      'maximumCodepointOverrides = 256',
      'maximumCodepointOverrides = 255',
    ),
    rendererCatalogSource,
    rendererNativeHeaderSource,
    rendererNativeSource,
    rendererNativeTestSource,
    rendererTestSource,
    productConfigurationSource,
    productDiagnosticsSource,
    productApplicationSource,
    runtimeSmokeSource,
    'missing codepoint-override capacity contract',
  );
  _expectFontResolutionFailure(
    rendererConfigurationSource,
    rendererCatalogSource,
    rendererNativeHeaderSource,
    rendererNativeSource,
    rendererNativeTestSource,
    rendererTestSource,
    productConfigurationSource,
    productDiagnosticsSource,
    productApplicationSource,
    runtimeSmokeSource.replaceAll(
      'font_fallback=true font_configuration=true font_diagnostics=true',
      'font_fallback=true',
    ),
    'missing two-runtime font acceptance marker',
  );
}

void _expectFailure(String source, String expected, String message) {
  try {
    validateGhosttyP0P1GapInventorySource(source, expectedSource: expected);
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectMatrixFailure(String source, String message) {
  try {
    parseGhosttyP0P1MatrixSource(source);
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectP0Failure(
  String inventory,
  String application,
  String regression,
  String message,
) {
  try {
    validateGhosttyP0ClosureSources(
      sequenceInventorySource: inventory,
      applicationAcceptanceSource: application,
      regressionCoverageSource: regression,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectP1Failure(
  String sequenceInventory,
  String implementationManifest,
  String message,
) {
  var threw = false;
  try {
    validateGhosttyP1ExtendedRenditionClosureSources(
      sequenceInventorySource: sequenceInventory,
      implementationManifestSource: implementationManifest,
    );
  } on GhosttyP0P1GapInventoryException {
    threw = true;
  }
  _expect(threw, message);
}

void _expectSemanticRangeFailure(
  String sequenceInventory,
  String semanticRangeSource,
  String semanticRangeTestSource,
  String message,
) {
  try {
    validateGhosttyP1SemanticRangeClosureSources(
      sequenceInventorySource: sequenceInventory,
      semanticRangeSource: semanticRangeSource,
      semanticRangeTestSource: semanticRangeTestSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectSnapshotRestoreFailure(
  String snapshotFormatterSource,
  String snapshotRestoreSource,
  String snapshotRestoreTestSource,
  String message,
) {
  try {
    validateGhosttyP1SnapshotRestoreClosureSources(
      snapshotFormatterSource: snapshotFormatterSource,
      snapshotRestoreSource: snapshotRestoreSource,
      snapshotRestoreTestSource: snapshotRestoreTestSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectCursorLigatureFailure(
  String compositorSource,
  String compositorTestSource,
  String message,
) {
  try {
    validateGhosttyP1CursorLigatureClosureSources(
      compositorSource: compositorSource,
      compositorTestSource: compositorTestSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectSyntheticCellGlyphFailure(
  String cellGlyphSource,
  String atlasSource,
  String compositorSource,
  String rasterTestSource,
  String compositorTestSource,
  String productApplicationSource,
  String runtimeSmokeSource,
  String message,
) {
  try {
    validateGhosttyP1SyntheticCellGlyphClosureSources(
      cellGlyphSource: cellGlyphSource,
      atlasSource: atlasSource,
      compositorSource: compositorSource,
      rasterTestSource: rasterTestSource,
      compositorTestSource: compositorTestSource,
      productApplicationSource: productApplicationSource,
      runtimeSmokeSource: runtimeSmokeSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectFontResolutionFailure(
  String rendererConfigurationSource,
  String rendererCatalogSource,
  String rendererNativeHeaderSource,
  String rendererNativeSource,
  String rendererNativeTestSource,
  String rendererTestSource,
  String productConfigurationSource,
  String productDiagnosticsSource,
  String productApplicationSource,
  String runtimeSmokeSource,
  String message,
) {
  try {
    validateGhosttyP1FontResolutionClosureSources(
      rendererConfigurationSource: rendererConfigurationSource,
      rendererCatalogSource: rendererCatalogSource,
      rendererNativeHeaderSource: rendererNativeHeaderSource,
      rendererNativeSource: rendererNativeSource,
      rendererNativeTestSource: rendererNativeTestSource,
      rendererTestSource: rendererTestSource,
      productConfigurationSource: productConfigurationSource,
      productDiagnosticsSource: productDiagnosticsSource,
      productApplicationSource: productApplicationSource,
      runtimeSmokeSource: runtimeSmokeSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectOverlayColorFailure(
  String kittyControllerSource,
  String overlaySource,
  String atlasSource,
  String referenceRendererSource,
  String compositorSource,
  String nativeRendererSource,
  String shaderSource,
  String metalTestSource,
  String productApplicationSource,
  String runtimeSmokeSource,
  String message,
) {
  try {
    validateGhosttyP1OverlayColorClosureSources(
      kittyControllerSource: kittyControllerSource,
      overlaySource: overlaySource,
      atlasSource: atlasSource,
      referenceRendererSource: referenceRendererSource,
      compositorSource: compositorSource,
      nativeRendererSource: nativeRendererSource,
      shaderSource: shaderSource,
      metalTestSource: metalTestSource,
      productApplicationSource: productApplicationSource,
      runtimeSmokeSource: runtimeSmokeSource,
    );
  } on GhosttyP0P1GapInventoryException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
