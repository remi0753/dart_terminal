import 'dart:convert';
import 'dart:io';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void runFontShapingTests() {
  final Object? decoded = jsonDecode(
    File('test/goldens/text/corpus-v1.json').readAsStringSync(),
  );
  _expect(decoded is Map<String, Object?>, 'text corpus is a JSON object');
  final Map<String, Object?> manifest = decoded! as Map<String, Object?>;
  _expect(
    manifest['format'] == 'dart-terminal-text-golden-corpus' &&
        manifest['version'] == 1,
    'text corpus format and version are exact',
  );
  final List<Object?> scales = manifest['scales']! as List<Object?>;
  _expect(
    scales.length == 2 && scales[0] == 1 && scales[1] == 2,
    'text corpus prepares exact 1x and 2x golden scales',
  );
  final List<Object?> cases = manifest['cases']! as List<Object?>;
  _expect(cases.length == 7, 'text corpus contains all required shape classes');
  final Set<String> identifiers = <String>{};
  for (final Object? item in cases) {
    _expect(item is Map<String, Object?>, 'text corpus case is an object');
    final Map<String, Object?> testCase = item! as Map<String, Object?>;
    final String identifier = testCase['id']! as String;
    final String family = testCase['family']! as String;
    final String text = testCase['text']! as String;
    final int cells = testCase['cells']! as int;
    final bool ligatures = testCase['ligatures']! as bool;
    _expect(
      identifiers.add(identifier) &&
          identifier.isNotEmpty &&
          family.isNotEmpty &&
          text.isNotEmpty &&
          cells > 0 &&
          cells <= 80,
      'text corpus IDs and geometry are unique and bounded',
    );
    final TerminalFontCatalog catalog = TerminalFontCatalog.open(
      family: family,
    );
    final TerminalShapingCache cache = TerminalShapingCache(
      catalog,
      maximumEntries: 4,
      maximumBytes: 4 * 1024 * 1024,
    );
    try {
      final TerminalShapingOptions options = TerminalShapingOptions(
        ligatures: ligatures,
      );
      final TerminalShapedText shaped = cache.shape(text, options: options);
      final TerminalShapedText repeated = cache.shape(text, options: options);
      _expect(
        identical(shaped, repeated) &&
            cache.hitCount == 1 &&
            cache.missCount == 1 &&
            cache.entryCount == 1 &&
            cache.retainedBytes <= cache.maximumBytes,
        '$identifier is reusable through the bounded shaping cache',
      );
      _expect(
        shaped.utf16Length == testCase['utf16Length'] &&
            shaped.unicodeScalarCount == testCase['scalarCount'],
        '$identifier preserves UTF-16 and scalar counts',
      );
      _expect(
        shaped.hasColorGlyphs == testCase['color'],
        '$identifier preserves color-face classification',
      );
      _expect(
        shaped.runs.any((TerminalShapedRun run) => run.isFallback) ==
            testCase['fallback'],
        '$identifier preserves fallback classification',
      );
      _expect(
        shaped.runs.any((TerminalShapedRun run) => run.isRightToLeft) ==
            testCase['rtl'],
        '$identifier preserves run direction',
      );
      _expect(
        shaped.glyphs.any(
              (TerminalShapedGlyph glyph) => glyph.utf16Length > 1,
            ) ==
            testCase['multiUnitCluster'],
        '$identifier preserves multi-unit cluster classification',
      );
      for (final Object? scaleValue in scales) {
        final int scale = scaleValue! as int;
        final int surfaceWidth = (catalog.metrics.cellWidth * cells * scale)
            .ceil();
        final int surfaceHeight = (catalog.metrics.cellHeight * 2 * scale)
            .ceil();
        final int baseline = (catalog.metrics.baseline * scale).round();
        _expect(
          surfaceWidth > 0 &&
              surfaceHeight > 0 &&
              baseline > 0 &&
              baseline < surfaceHeight &&
              surfaceWidth * surfaceHeight <= 4 * 1024 * 1024,
          '$identifier has bounded ${scale}x reference-surface geometry',
        );
        for (final TerminalShapedGlyph glyph in shaped.glyphs) {
          _expect(
            (glyph.positionX * scale).isFinite &&
                (glyph.positionY * scale).isFinite &&
                (glyph.advance * scale).isFinite,
            '$identifier exposes finite ${scale}x glyph placement inputs',
          );
        }
      }
    } finally {
      cache.dispose();
      catalog.dispose();
    }
  }
  _expect(
    identifiers.containsAll(<String>{
      'latin-ligature',
      'cjk-wide',
      'emoji-zwj-modifier',
      'emoji-flag',
      'combining',
      'arabic-run',
      'hebrew-combining-run',
    }),
    'text corpus covers Latin, CJK/wide, emoji, combining, and bidi shaping',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('font shaping expectation failed: $description');
  }
}
