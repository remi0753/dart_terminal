import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void runShapingTests() {
  _testPackedDecoder();
  _testNativeShapingAndClusters();
  _testLigatureFeature();
  _testCacheBoundsAndIdentity();
}

void _testPackedDecoder() {
  final Uint8List valid = _minimalBuffer();
  final TerminalShapedText decoded = TerminalShapingBufferV1.decode(
    valid,
    text: 'x',
    catalogGeneration: 99,
    requestedStyle: TerminalFontStyle.regular,
  );
  _expect(
    decoded.catalogGeneration == 99 &&
        decoded.utf8Length == 1 &&
        decoded.utf16Length == 1 &&
        decoded.unicodeScalarCount == 1 &&
        decoded.runs.length == 1 &&
        decoded.faces.length == 1 &&
        decoded.glyphs.length == 1 &&
        decoded.faceById(1).postscriptName == 'Menlo' &&
        decoded.glyphs.single.utf16Length == 1,
    'strict decoder accepts one canonical packed buffer',
  );
  _expectThrows<UnsupportedError>(
    () => decoded.glyphs.add(decoded.glyphs.single),
    'decoded glyph collection is immutable',
  );

  _expectDecodeFailure(_withU32(valid, 0, 0), 'magic');
  _expectDecodeFailure(_withU32(valid, 68, 1), 'header reserved');
  _expectDecodeFailure(_withU32(valid, 60, 121), 'section offset');
  _expectDecodeFailure(_withU32(valid, 88, 1), 'run glyph start');
  _expectDecodeFailure(_withU32(valid, 100, 0), 'run UTF-16 length');
  _expectDecodeFailure(_withU32(valid, 92, 2), 'run glyph count');
  _expectDecodeFailure(_withU32(valid, 96, 2), 'run range');
  _expectDecodeFailure(_withU32(valid, 120 + 12, 1), 'face reserved');
  final Uint8List badPadding = Uint8List.fromList(valid);
  badPadding[120 + 16 + 6] = 1;
  _expectDecodeFailure(badPadding, 'face padding');
  _expectDecodeFailure(_withU32(valid, 264 + 8, 1), 'glyph run index');
  _expectDecodeFailure(_withU32(valid, 264 + 20, 0), 'glyph cluster span');
  final Uint8List nanPosition = Uint8List.fromList(valid);
  ByteData.sublistView(nanPosition)
      .setFloat64(264 + 24, double.nan, Endian.little);
  _expectDecodeFailure(nanPosition, 'non-finite position');
  _expectThrows<FormatException>(
    () => TerminalShapingBufferV1.decode(
      Uint8List.sublistView(valid, 0, valid.length - 1),
      text: 'x',
      catalogGeneration: 99,
      requestedStyle: TerminalFontStyle.regular,
    ),
    'truncated packed buffer',
  );
  _expectThrows<FormatException>(
    () => TerminalShapingBufferV1.decode(
      valid,
      text: 'y',
      catalogGeneration: 100,
      requestedStyle: TerminalFontStyle.regular,
    ),
    'generation mismatch',
  );
}

void _testNativeShapingAndClusters() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  try {
    const String mixed = 'A日本語👩🏽‍💻e\u0301';
    final TerminalShapedText shaped = catalog.shape(mixed);
    _expect(
      shaped.text == mixed &&
          shaped.catalogGeneration == catalog.generation &&
          shaped.requestedStyle == TerminalFontStyle.regular &&
          shaped.ligaturesEnabled &&
          shaped.utf8Length == 28 &&
          shaped.utf16Length == 13 &&
          shaped.unicodeScalarCount == 10 &&
          shaped.runs.length >= 3 &&
          shaped.faces.length >= 3 &&
          shaped.glyphs.isNotEmpty &&
          shaped.hasColorGlyphs &&
          !shaped.hasMissingGlyph,
      'mixed Latin/CJK/emoji/combining run preserves exact counts',
    );
    _expect(
      shaped.runs.any(
        (TerminalShapedRun run) => run.isFallback && !run.hasColorGlyphs,
      ),
      'wide CJK uses a non-color fallback run',
    );
    _expect(
      shaped.glyphs.any(
            (TerminalShapedGlyph glyph) =>
                glyph.utf16Start == 4 && glyph.utf16Length == 7,
          ) &&
          shaped.glyphs.any(
            (TerminalShapedGlyph glyph) =>
                glyph.utf16Start == 11 && glyph.utf16Length == 2,
          ),
      'emoji ZWJ/modifier and combining clusters retain logical spans',
    );
    for (final TerminalShapedGlyph glyph in shaped.glyphs) {
      _expect(
        glyph.faceId == shaped.runs[glyph.runIndex].faceId &&
            glyph.utf16Length > 0 &&
            glyph.positionX.isFinite &&
            glyph.positionY.isFinite &&
            glyph.advance.isFinite,
        'glyph maps to its run, face, position, and cluster',
      );
    }

    final TerminalShapedText emojiFlag = catalog.shape('👩🏽‍💻🇯🇵');
    _expect(
      emojiFlag.utf16Length == 11 &&
          emojiFlag.unicodeScalarCount == 6 &&
          emojiFlag.glyphs.any(
            (TerminalShapedGlyph glyph) =>
                glyph.utf16Start == 0 && glyph.utf16Length == 7,
          ) &&
          emojiFlag.glyphs.any(
            (TerminalShapedGlyph glyph) =>
                glyph.utf16Start == 7 && glyph.utf16Length == 4,
          ),
      'ZWJ/modifier and regional-indicator flag remain distinct clusters',
    );
    final TerminalShapedText arabic = catalog.shape('سلام');
    _expect(
      arabic.unicodeScalarCount == 4 &&
          arabic.runs.any((TerminalShapedRun run) => run.isRightToLeft),
      'Arabic shapes inside an RTL CoreText run while layout stays caller-owned',
    );
    final TerminalShapedText hebrew = catalog.shape('שָׁלוֹם');
    _expect(
      hebrew.unicodeScalarCount == 7 &&
          hebrew.runs.any((TerminalShapedRun run) => run.isRightToLeft) &&
          hebrew.glyphs.any(
            (TerminalShapedGlyph glyph) => glyph.utf16Length > 1,
          ),
      'Hebrew combining marks shape inside an RTL CoreText run',
    );
    final TerminalShapedText bold = catalog.shape(
      'B',
      style: TerminalFontStyle.bold,
    );
    _expect(
      bold.requestedStyle == TerminalFontStyle.bold &&
          bold.runs.single.isSynthetic ==
              catalog.isStyleSynthetic(TerminalFontStyle.bold),
      'shape result retains the explicit style policy',
    );
    _expectThrows<ArgumentError>(() => catalog.shape(''), 'empty shape input');
    _expectThrows<ArgumentError>(
      () => catalog.shape('x\u0000y'),
      'NUL shape input',
    );
    _expectThrows<ArgumentError>(
      () => catalog.shape(String.fromCharCode(0xd800)),
      'malformed UTF-16 shape input',
    );
    final Uint8List overLimitUnits = Uint8List(
      TerminalFontCatalog.maximumResolveTextBytes + 1,
    )..fillRange(0, TerminalFontCatalog.maximumResolveTextBytes + 1, 0x61);
    _expectThrows<ArgumentError>(
      () => catalog.shape(String.fromCharCodes(overLimitUnits)),
      'over-limit UTF-8 shape input',
    );
  } finally {
    catalog.dispose();
  }
  _expectThrows<StateError>(
    () => catalog.shape('x'),
    'disposed catalog cannot shape',
  );
}

void _testLigatureFeature() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open(
    family: 'Times-Roman',
    pointSize: 16,
  );
  try {
    const String text = 'office ffi affluent';
    final TerminalShapedText enabled = catalog.shape(text);
    final TerminalShapedText disabled = catalog.shape(
      text,
      options: const TerminalShapingOptions(ligatures: false),
    );
    _expect(
      enabled.glyphs.length < disabled.glyphs.length &&
          enabled.glyphs.any(
            (TerminalShapedGlyph glyph) => glyph.utf16Length > 1,
          ) &&
          disabled.glyphs.every(
            (TerminalShapedGlyph glyph) => glyph.utf16Length == 1,
          ),
      'ligature feature changes glyph count and cluster mapping',
    );
  } finally {
    catalog.dispose();
  }
}

void _testCacheBoundsAndIdentity() {
  final TerminalFontCatalog catalog = TerminalFontCatalog.open();
  try {
    final TerminalShapingCache cache = TerminalShapingCache(
      catalog,
      maximumEntries: 2,
      maximumBytes: 1024 * 1024,
    );
    final TerminalShapedText a = cache.shape('a');
    final TerminalShapedText b = cache.shape('b');
    final TerminalShapedText aHit = cache.shape('a');
    _expect(
      identical(a, aHit) &&
          cache.entryCount == 2 &&
          cache.hitCount == 1 &&
          cache.missCount == 2 &&
          cache.evictionCount == 0 &&
          cache.retainedBytes > 0 &&
          cache.retainedBytes <= cache.maximumBytes,
      'cache hit promotes and returns the immutable prior result',
    );
    cache.shape('c');
    final TerminalShapedText bAfterEviction = cache.shape('b');
    _expect(
      !identical(b, bAfterEviction) &&
          cache.entryCount == 2 &&
          cache.hitCount == 1 &&
          cache.missCount == 4 &&
          cache.evictionCount == 2 &&
          cache.retainedBytes <= cache.maximumBytes,
      'entry cap evicts the least-recently-used key',
    );

    final TerminalShapingCache keyCache = TerminalShapingCache(
      catalog,
      maximumEntries: 4,
      maximumBytes: 1024 * 1024,
    );
    final TerminalShapedText regular = keyCache.shape('ffi');
    final TerminalShapedText noLigatures = keyCache.shape(
      'ffi',
      options: const TerminalShapingOptions(ligatures: false),
    );
    final TerminalShapedText bold = keyCache.shape(
      'ffi',
      style: TerminalFontStyle.bold,
    );
    _expect(
      !identical(regular, noLigatures) &&
          !identical(regular, bold) &&
          keyCache.entryCount == 3 &&
          keyCache.missCount == 3,
      'feature and style state cannot alias an exact-byte text key',
    );

    final TerminalShapingCache byteLimited = TerminalShapingCache(
      catalog,
      maximumEntries: 4,
      maximumBytes: 80,
    );
    final TerminalShapedText uncached = byteLimited.shape('oversized-entry');
    final TerminalShapedText uncachedAgain = byteLimited.shape(
      'oversized-entry',
    );
    _expect(
      !identical(uncached, uncachedAgain) &&
          byteLimited.entryCount == 0 &&
          byteLimited.retainedBytes == 0 &&
          byteLimited.missCount == 2,
      'single entries above the byte cap are returned but never retained',
    );
    final TerminalShapedText byteProbe = catalog.shape('d');
    final int oneByteEntryCharge = byteProbe.packedByteLength + 1;
    final TerminalShapingCache byteEvicting = TerminalShapingCache(
      catalog,
      maximumEntries: 4,
      maximumBytes: oneByteEntryCharge * 2,
    );
    final TerminalShapedText d = byteEvicting.shape('d');
    final TerminalShapedText e = byteEvicting.shape('e');
    _expect(
      identical(d, byteEvicting.shape('d')) && byteEvicting.entryCount == 2,
      'byte-bounded cache promotes a hit before pressure',
    );
    byteEvicting.shape('f');
    final TerminalShapedText eAfterByteEviction = byteEvicting.shape('e');
    _expect(
      !identical(e, eAfterByteEviction) &&
          byteEvicting.entryCount == 2 &&
          byteEvicting.evictionCount == 2 &&
          byteEvicting.retainedBytes <= byteEvicting.maximumBytes,
      'byte cap independently evicts the least-recently-used entry',
    );
    keyCache.clear();
    _expect(
      keyCache.entryCount == 0 && keyCache.retainedBytes == 0,
      'cache clear releases all logical byte charges',
    );
    cache.dispose();
    cache.dispose();
    _expect(
      cache.isDisposed && cache.entryCount == 0 && cache.retainedBytes == 0,
      'cache dispose is idempotent and releases retained results',
    );
    _expectThrows<StateError>(
      () => cache.shape('a'),
      'disposed cache cannot return a stale hit',
    );
    keyCache.dispose();
    byteLimited.dispose();
    byteEvicting.dispose();
  } finally {
    catalog.dispose();
  }

  final TerminalFontCatalog staleCatalog = TerminalFontCatalog.open();
  final TerminalShapingCache staleCache = TerminalShapingCache(staleCatalog);
  final TerminalShapedText firstGeneration = staleCache.shape('generation');
  staleCatalog.dispose();
  _expectThrows<StateError>(
    () => staleCache.shape('generation'),
    'cache checks catalog liveness before returning a hit',
  );
  staleCache.dispose();
  final TerminalFontCatalog nextCatalog = TerminalFontCatalog.open();
  try {
    final TerminalShapedText nextGeneration = nextCatalog.shape('generation');
    _expect(
      firstGeneration.catalogGeneration != nextGeneration.catalogGeneration,
      'replacement catalog receives a distinct generation identity',
    );
  } finally {
    nextCatalog.dispose();
  }

  _expectThrows<RangeError>(
    () => TerminalShapingCache(nextCatalog, maximumEntries: 0),
    'cache entry lower bound',
  );
  _expectThrows<RangeError>(
    () => TerminalShapingCache(nextCatalog, maximumBytes: 79),
    'cache byte lower bound',
  );
}

Uint8List _minimalBuffer() {
  final Uint8List bytes = Uint8List(312);
  final ByteData data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  u32(0, 0x48535444);
  u32(4, 1);
  u32(8, 80);
  u32(12, bytes.length);
  data.setUint64(16, 99, Endian.little);
  u32(24, TerminalFontStyle.regular.index);
  u32(28, 1);
  u32(32, 1);
  u32(36, 1);
  u32(40, 1);
  u32(44, 1);
  u32(48, 1);
  u32(52, 1);
  u32(56, 80);
  u32(60, 120);
  u32(64, 264);

  u32(80, 1);
  u32(84, TerminalShapedRunFlags.monospaced);
  u32(88, 0);
  u32(92, 1);
  u32(96, 0);
  u32(100, 1);
  data.setFloat64(104, 8, Endian.little);

  u32(120, 1);
  u32(124, TerminalShapedRunFlags.monospaced);
  u32(128, 5);
  bytes.setAll(136, 'Menlo'.codeUnits);

  u32(264, 1);
  u32(268, 1);
  u32(272, 0);
  u32(276, 0);
  u32(280, 0);
  u32(284, 1);
  data.setFloat64(288, 0, Endian.little);
  data.setFloat64(296, 0, Endian.little);
  data.setFloat64(304, 8, Endian.little);
  return bytes;
}

Uint8List _withU32(Uint8List source, int offset, int value) {
  final Uint8List copy = Uint8List.fromList(source);
  ByteData.sublistView(copy).setUint32(offset, value, Endian.little);
  return copy;
}

void _expectDecodeFailure(Uint8List bytes, String description) {
  _expectThrows<FormatException>(
    () => TerminalShapingBufferV1.decode(
      bytes,
      text: 'x',
      catalogGeneration: 99,
      requestedStyle: TerminalFontStyle.regular,
    ),
    'corrupt $description',
  );
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('shaping expectation failed: $description');
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
      'shaping expectation failed: $description threw ${error.runtimeType}',
    );
  }
  throw StateError('shaping expectation failed: $description');
}
