part of 'font_catalog.dart';

/// Feature state passed to CoreText for one whole text run.
final class TerminalShapingOptions {
  const TerminalShapingOptions({this.ligatures = true});

  final bool ligatures;

  int get featureFlags => ligatures ? _shapeFeatureLigatures : 0;
}

abstract final class TerminalShapedRunFlags {
  static const int fallback = TerminalResolvedFontFlags.fallback;
  static const int colorGlyphs = TerminalResolvedFontFlags.colorGlyphs;
  static const int synthetic = TerminalResolvedFontFlags.synthetic;
  static const int missingGlyph = TerminalResolvedFontFlags.missingGlyph;
  static const int monospaced = TerminalResolvedFontFlags.monospaced;
  static const int rightToLeft = 1 << 5;
  static const int knownMask =
      TerminalResolvedFontFlags.knownMask | rightToLeft;
}

abstract final class TerminalShapedGlyphFlags {
  static const int missing = 1 << 0;
  static const int knownMask = missing;
}

final class TerminalShapedFace {
  const TerminalShapedFace({
    required this.faceId,
    required this.flags,
    required this.postscriptName,
  });

  final int faceId;
  final int flags;
  final String postscriptName;

  bool get isFallback => flags & TerminalShapedRunFlags.fallback != 0;
  bool get hasColorGlyphs => flags & TerminalShapedRunFlags.colorGlyphs != 0;
  bool get isSynthetic => flags & TerminalShapedRunFlags.synthetic != 0;
  bool get hasMissingGlyph => flags & TerminalShapedRunFlags.missingGlyph != 0;
  bool get isMonospaced => flags & TerminalShapedRunFlags.monospaced != 0;
}

final class TerminalShapedRun {
  const TerminalShapedRun({
    required this.faceId,
    required this.flags,
    required this.firstGlyph,
    required this.glyphCount,
    required this.utf16Start,
    required this.utf16Length,
    required this.typographicWidth,
  });

  final int faceId;
  final int flags;
  final int firstGlyph;
  final int glyphCount;
  final int utf16Start;
  final int utf16Length;
  final double typographicWidth;

  int get glyphEnd => firstGlyph + glyphCount;
  int get utf16End => utf16Start + utf16Length;
  bool get isFallback => flags & TerminalShapedRunFlags.fallback != 0;
  bool get hasColorGlyphs => flags & TerminalShapedRunFlags.colorGlyphs != 0;
  bool get isSynthetic => flags & TerminalShapedRunFlags.synthetic != 0;
  bool get hasMissingGlyph => flags & TerminalShapedRunFlags.missingGlyph != 0;
  bool get isMonospaced => flags & TerminalShapedRunFlags.monospaced != 0;
  bool get isRightToLeft => flags & TerminalShapedRunFlags.rightToLeft != 0;
}

final class TerminalShapedGlyph {
  const TerminalShapedGlyph({
    required this.glyphId,
    required this.faceId,
    required this.runIndex,
    required this.flags,
    required this.utf16Start,
    required this.utf16Length,
    required this.positionX,
    required this.positionY,
    required this.advance,
  });

  final int glyphId;
  final int faceId;
  final int runIndex;
  final int flags;
  final int utf16Start;
  final int utf16Length;
  final double positionX;
  final double positionY;
  final double advance;

  int get utf16End => utf16Start + utf16Length;
  bool get isMissing => flags & TerminalShapedGlyphFlags.missing != 0;
}

/// Immutable Dart-owned result copied from one native shaping call.
final class TerminalShapedText {
  TerminalShapedText._({
    required this.text,
    required this.catalogGeneration,
    required this.requestedStyle,
    required this.featureFlags,
    required this.utf8Length,
    required this.utf16Length,
    required this.unicodeScalarCount,
    required this.packedByteLength,
    required List<TerminalShapedRun> runs,
    required List<TerminalShapedFace> faces,
    required List<TerminalShapedGlyph> glyphs,
  }) : runs = List<TerminalShapedRun>.unmodifiable(runs),
       faces = List<TerminalShapedFace>.unmodifiable(faces),
       glyphs = List<TerminalShapedGlyph>.unmodifiable(glyphs);

  final String text;
  final int catalogGeneration;
  final TerminalFontStyle requestedStyle;
  final int featureFlags;
  final int utf8Length;
  final int utf16Length;
  final int unicodeScalarCount;

  /// The deterministic logical byte charge used by the shaping cache.
  final int packedByteLength;

  final List<TerminalShapedRun> runs;
  final List<TerminalShapedFace> faces;
  final List<TerminalShapedGlyph> glyphs;

  bool get ligaturesEnabled => featureFlags & _shapeFeatureLigatures != 0;
  bool get hasColorGlyphs =>
      faces.any((TerminalShapedFace face) => face.hasColorGlyphs);
  bool get hasMissingGlyph =>
      glyphs.any((TerminalShapedGlyph glyph) => glyph.isMissing);

  TerminalShapedFace faceById(int faceId) =>
      faces.singleWhere((TerminalShapedFace face) => face.faceId == faceId);
}

/// Strict decoder for the public version-one packed shaping format.
///
/// This is public so recorded/corrupt buffers can be tested without making a
/// CoreText call. Production callers normally use [TerminalFontCatalog.shape].
abstract final class TerminalShapingBufferV1 {
  static const int maximumOutputBytes = 64 * 1024 * 1024;

  static TerminalShapedText decode(
    Uint8List bytes, {
    required String text,
    required int catalogGeneration,
    required TerminalFontStyle requestedStyle,
    TerminalShapingOptions options = const TerminalShapingOptions(),
  }) {
    final _ValidatedShapeText validated = _validateShapeText(text);
    if (bytes.length < _shapeHeaderSize || bytes.length > maximumOutputBytes) {
      throw const FormatException('invalid packed shaping buffer length');
    }
    final ByteData data = ByteData.sublistView(bytes);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    final int magic = u32(0);
    final int version = u32(4);
    final int headerSize = u32(8);
    final int totalSize = u32(12);
    final int generation = data.getUint64(16, Endian.little);
    final int style = u32(24);
    final int featureFlags = u32(28);
    final int utf8Length = u32(32);
    final int utf16Length = u32(36);
    final int scalarCount = u32(40);
    final int runCount = u32(44);
    final int faceCount = u32(48);
    final int glyphCount = u32(52);
    final int runsOffset = u32(56);
    final int facesOffset = u32(60);
    final int glyphsOffset = u32(64);
    if (magic != _shapeBufferMagic ||
        version != _shapeBufferVersion ||
        headerSize != _shapeHeaderSize ||
        totalSize != bytes.length ||
        generation != catalogGeneration ||
        style != requestedStyle.index ||
        featureFlags != options.featureFlags ||
        featureFlags & ~_shapeFeatureKnownMask != 0 ||
        utf8Length != validated.bytes.length ||
        utf16Length != validated.utf16Length ||
        scalarCount != validated.scalarCount ||
        runCount == 0 ||
        runCount > _maximumShapeRuns ||
        faceCount == 0 ||
        faceCount > _maximumShapeFaces ||
        glyphCount == 0 ||
        glyphCount > _maximumShapeGlyphs ||
        u32(68) != 0 ||
        u32(72) != 0 ||
        u32(76) != 0) {
      throw const FormatException('invalid packed shaping header');
    }
    final int expectedFacesOffset = _shapeHeaderSize + runCount * _shapeRunSize;
    final int expectedGlyphsOffset =
        expectedFacesOffset + faceCount * _shapeFaceSize;
    final int expectedTotalSize =
        expectedGlyphsOffset + glyphCount * _shapeGlyphSize;
    if (runsOffset != _shapeHeaderSize ||
        facesOffset != expectedFacesOffset ||
        glyphsOffset != expectedGlyphsOffset ||
        expectedTotalSize != totalSize ||
        expectedTotalSize > maximumOutputBytes) {
      throw const FormatException('invalid packed shaping sections');
    }

    final List<TerminalShapedFace> faces = <TerminalShapedFace>[];
    final Map<int, TerminalShapedFace> facesById = <int, TerminalShapedFace>{};
    for (int index = 0; index < faceCount; index++) {
      final int offset = facesOffset + index * _shapeFaceSize;
      final int faceId = u32(offset);
      final int flags = u32(offset + 4);
      final int nameLength = u32(offset + 8);
      if (faceId == 0 ||
          facesById.containsKey(faceId) ||
          flags & ~TerminalResolvedFontFlags.knownMask != 0 ||
          nameLength == 0 ||
          nameLength > _maximumPostscriptNameBytes ||
          u32(offset + 12) != 0) {
        throw const FormatException('invalid packed shaping face');
      }
      final int nameOffset = offset + 16;
      if (bytes[nameOffset + nameLength] != 0) {
        throw const FormatException('unterminated packed shaping face name');
      }
      for (
        int padding = nameLength + 1;
        padding <= _maximumPostscriptNameBytes;
        padding++
      ) {
        if (bytes[nameOffset + padding] != 0) {
          throw const FormatException('nonzero packed shaping face padding');
        }
      }
      final String name = utf8.decode(
        bytes.sublist(nameOffset, nameOffset + nameLength),
        allowMalformed: false,
      );
      if (name.isEmpty || name.contains('\u0000')) {
        throw const FormatException('invalid packed shaping face name');
      }
      final TerminalShapedFace face = TerminalShapedFace(
        faceId: faceId,
        flags: flags,
        postscriptName: name,
      );
      faces.add(face);
      facesById[faceId] = face;
    }

    final List<TerminalShapedRun> runs = <TerminalShapedRun>[];
    final Map<int, int> runFlagsByFace = <int, int>{};
    final List<bool> runUtf16Coverage = List<bool>.filled(utf16Length, false);
    var expectedFirstGlyph = 0;
    for (int index = 0; index < runCount; index++) {
      final int offset = runsOffset + index * _shapeRunSize;
      final int faceId = u32(offset);
      final int flags = u32(offset + 4);
      final int firstGlyph = u32(offset + 8);
      final int runGlyphCount = u32(offset + 12);
      final int utf16Start = u32(offset + 16);
      final int runUtf16Length = u32(offset + 20);
      final double width = data.getFloat64(offset + 24, Endian.little);
      final TerminalShapedFace? face = facesById[faceId];
      if (face == null ||
          flags & ~TerminalShapedRunFlags.knownMask != 0 ||
          (flags & TerminalResolvedFontFlags.knownMask) & ~face.flags != 0 ||
          firstGlyph != expectedFirstGlyph ||
          runGlyphCount == 0 ||
          firstGlyph + runGlyphCount > glyphCount ||
          runUtf16Length == 0 ||
          utf16Start + runUtf16Length > utf16Length ||
          !validated.scalarBoundaries[utf16Start] ||
          !validated.scalarBoundaries[utf16Start + runUtf16Length] ||
          !width.isFinite ||
          u32(offset + 32) != 0 ||
          u32(offset + 36) != 0) {
        throw const FormatException('invalid packed shaping run');
      }
      runs.add(
        TerminalShapedRun(
          faceId: faceId,
          flags: flags,
          firstGlyph: firstGlyph,
          glyphCount: runGlyphCount,
          utf16Start: utf16Start,
          utf16Length: runUtf16Length,
          typographicWidth: width,
        ),
      );
      for (
        int utf16Index = utf16Start;
        utf16Index < utf16Start + runUtf16Length;
        utf16Index++
      ) {
        if (runUtf16Coverage[utf16Index]) {
          throw const FormatException('overlapping packed shaping runs');
        }
        runUtf16Coverage[utf16Index] = true;
      }
      runFlagsByFace[faceId] =
          (runFlagsByFace[faceId] ?? 0) |
          (flags & TerminalResolvedFontFlags.knownMask);
      expectedFirstGlyph += runGlyphCount;
    }
    if (expectedFirstGlyph != glyphCount ||
        runUtf16Coverage.any((bool covered) => !covered)) {
      throw const FormatException('packed shaping runs do not cover input');
    }
    for (final TerminalShapedFace face in faces) {
      if (runFlagsByFace[face.faceId] != face.flags) {
        throw const FormatException('inconsistent packed shaping face flags');
      }
    }

    final List<TerminalShapedGlyph> glyphs = <TerminalShapedGlyph>[];
    final List<bool> runHasMissing = List<bool>.filled(runCount, false);
    var runIndex = 0;
    for (int index = 0; index < glyphCount; index++) {
      while (index >= runs[runIndex].glyphEnd) {
        runIndex++;
      }
      final int offset = glyphsOffset + index * _shapeGlyphSize;
      final int glyphId = u32(offset);
      final int faceId = u32(offset + 4);
      final int encodedRunIndex = u32(offset + 8);
      final int flags = u32(offset + 12);
      final int utf16Start = u32(offset + 16);
      final int glyphUtf16Length = u32(offset + 20);
      final double positionX = data.getFloat64(offset + 24, Endian.little);
      final double positionY = data.getFloat64(offset + 32, Endian.little);
      final double advance = data.getFloat64(offset + 40, Endian.little);
      final TerminalShapedRun run = runs[runIndex];
      final bool isMissing = flags & TerminalShapedGlyphFlags.missing != 0;
      if (encodedRunIndex != runIndex ||
          faceId != run.faceId ||
          flags & ~TerminalShapedGlyphFlags.knownMask != 0 ||
          (glyphId == 0) != isMissing ||
          glyphUtf16Length == 0 ||
          utf16Start < run.utf16Start ||
          utf16Start + glyphUtf16Length > run.utf16End ||
          !validated.scalarBoundaries[utf16Start] ||
          !validated.scalarBoundaries[utf16Start + glyphUtf16Length] ||
          !positionX.isFinite ||
          !positionY.isFinite ||
          !advance.isFinite) {
        throw const FormatException('invalid packed shaping glyph');
      }
      runHasMissing[runIndex] |= isMissing;
      glyphs.add(
        TerminalShapedGlyph(
          glyphId: glyphId,
          faceId: faceId,
          runIndex: runIndex,
          flags: flags,
          utf16Start: utf16Start,
          utf16Length: glyphUtf16Length,
          positionX: positionX,
          positionY: positionY,
          advance: advance,
        ),
      );
    }
    for (int index = 0; index < runCount; index++) {
      if (runs[index].hasMissingGlyph != runHasMissing[index]) {
        throw const FormatException('inconsistent packed missing-glyph flags');
      }
    }
    return TerminalShapedText._(
      text: text,
      catalogGeneration: generation,
      requestedStyle: requestedStyle,
      featureFlags: featureFlags,
      utf8Length: utf8Length,
      utf16Length: utf16Length,
      unicodeScalarCount: scalarCount,
      packedByteLength: totalSize,
      runs: runs,
      faces: faces,
      glyphs: glyphs,
    );
  }
}

extension TerminalFontCatalogShaping on TerminalFontCatalog {
  TerminalShapedText shape(
    String text, {
    TerminalFontStyle style = TerminalFontStyle.regular,
    TerminalShapingOptions options = const TerminalShapingOptions(),
  }) {
    return _shapeValidated(_validateShapeText(text), text, style, options);
  }

  TerminalShapedText _shapeValidated(
    _ValidatedShapeText validated,
    String text,
    TerminalFontStyle style,
    TerminalShapingOptions options,
  ) {
    final int handle = _liveHandle();
    final Arena arena = Arena();
    try {
      final Pointer<Uint8> textPointer = arena<Uint8>(validated.bytes.length);
      textPointer
          .asTypedList(validated.bytes.length)
          .setAll(0, validated.bytes);
      final Pointer<Uint32> required = arena<Uint32>();
      Pointer<Uint8> output = nullptr;
      var capacity = 0;
      for (int attempt = 0; attempt < 3; attempt++) {
        required.value = 0;
        final int status = _fontCatalogShape(
          handle,
          style.index,
          options.featureFlags,
          textPointer,
          validated.bytes.length,
          output,
          capacity,
          required,
        );
        if (status == _statusBufferTooSmall) {
          final int nextCapacity = required.value;
          if (nextCapacity <= capacity ||
              nextCapacity < _shapeHeaderSize ||
              nextCapacity > TerminalShapingBufferV1.maximumOutputBytes) {
            throw const FormatException('invalid native shaping buffer size');
          }
          output = arena<Uint8>(nextCapacity);
          capacity = nextCapacity;
          continue;
        }
        _checkStatus(status, 'font catalog shape');
        if (output == nullptr ||
            required.value == 0 ||
            required.value > capacity) {
          throw const FormatException('invalid native shaping completion');
        }
        return TerminalShapingBufferV1.decode(
          Uint8List.fromList(output.asTypedList(required.value)),
          text: text,
          catalogGeneration: generation,
          requestedStyle: style,
          options: options,
        );
      }
      throw StateError('native shaping size changed repeatedly');
    } finally {
      arena.releaseAll();
    }
  }
}

/// Bounded Dart-owned LRU for immutable whole-run shaping results.
final class TerminalShapingCache {
  TerminalShapingCache(
    this.catalog, {
    this.maximumEntries = 4096,
    this.maximumBytes = 64 * 1024 * 1024,
  }) {
    if (maximumEntries < 1 || maximumEntries > 65536) {
      throw RangeError.range(maximumEntries, 1, 65536, 'maximumEntries');
    }
    if (maximumBytes < _shapeHeaderSize || maximumBytes > 512 * 1024 * 1024) {
      throw RangeError.range(
        maximumBytes,
        _shapeHeaderSize,
        512 * 1024 * 1024,
        'maximumBytes',
      );
    }
  }

  final TerminalFontCatalog catalog;
  final int maximumEntries;
  final int maximumBytes;
  final LinkedHashMap<_ShapeCacheKey, _ShapeCacheEntry> _entries =
      LinkedHashMap<_ShapeCacheKey, _ShapeCacheEntry>();

  var _retainedBytes = 0;
  var _hitCount = 0;
  var _missCount = 0;
  var _evictionCount = 0;
  var _disposed = false;

  int get entryCount => _entries.length;
  int get retainedBytes => _retainedBytes;
  int get hitCount => _hitCount;
  int get missCount => _missCount;
  int get evictionCount => _evictionCount;
  bool get isDisposed => _disposed;

  TerminalShapedText shape(
    String text, {
    TerminalFontStyle style = TerminalFontStyle.regular,
    TerminalShapingOptions options = const TerminalShapingOptions(),
  }) {
    if (_disposed) {
      throw StateError('TerminalShapingCache is disposed');
    }
    catalog._liveHandle();
    final _ValidatedShapeText validated = _validateShapeText(text);
    final _ShapeCacheKey candidate = _ShapeCacheKey(
      catalogGeneration: catalog.generation,
      style: style.index,
      featureFlags: options.featureFlags,
      textBytes: validated.bytes,
    );
    final _ShapeCacheEntry? cached = _entries.remove(candidate);
    if (cached != null) {
      _entries[cached.key] = cached;
      _hitCount++;
      return cached.result;
    }
    _missCount++;
    final TerminalShapedText result = catalog._shapeValidated(
      validated,
      text,
      style,
      options,
    );
    final int charge = result.packedByteLength + candidate.textBytes.length;
    if (charge > maximumBytes) {
      return result;
    }
    while (_entries.length >= maximumEntries ||
        _retainedBytes + charge > maximumBytes) {
      final _ShapeCacheKey oldest = _entries.keys.first;
      final _ShapeCacheEntry removed = _entries.remove(oldest)!;
      _retainedBytes -= removed.byteCharge;
      _evictionCount++;
    }
    final _ShapeCacheEntry entry = _ShapeCacheEntry(
      key: candidate,
      result: result,
      byteCharge: charge,
    );
    _entries[candidate] = entry;
    _retainedBytes += charge;
    return result;
  }

  void clear() {
    if (_disposed) {
      throw StateError('TerminalShapingCache is disposed');
    }
    _entries.clear();
    _retainedBytes = 0;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _entries.clear();
    _retainedBytes = 0;
    _disposed = true;
  }
}

final class _ValidatedShapeText {
  const _ValidatedShapeText({
    required this.bytes,
    required this.utf16Length,
    required this.scalarCount,
    required this.scalarBoundaries,
  });

  final Uint8List bytes;
  final int utf16Length;
  final int scalarCount;
  final List<bool> scalarBoundaries;
}

final class _ShapeCacheKey {
  _ShapeCacheKey({
    required this.catalogGeneration,
    required this.style,
    required this.featureFlags,
    required this.textBytes,
  }) : _hashCode = _hash(catalogGeneration, style, featureFlags, textBytes);

  final int catalogGeneration;
  final int style;
  final int featureFlags;
  final Uint8List textBytes;
  final int _hashCode;

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! _ShapeCacheKey ||
        catalogGeneration != other.catalogGeneration ||
        style != other.style ||
        featureFlags != other.featureFlags ||
        textBytes.length != other.textBytes.length) {
      return false;
    }
    for (int index = 0; index < textBytes.length; index++) {
      if (textBytes[index] != other.textBytes[index]) {
        return false;
      }
    }
    return true;
  }

  static int _hash(
    int catalogGeneration,
    int style,
    int featureFlags,
    Uint8List bytes,
  ) {
    var hash = Object.hash(catalogGeneration, style, featureFlags);
    for (final int byte in bytes) {
      hash = 0x1fffffff & (hash * 31 + byte);
    }
    return hash;
  }
}

final class _ShapeCacheEntry {
  const _ShapeCacheEntry({
    required this.key,
    required this.result,
    required this.byteCharge,
  });

  final _ShapeCacheKey key;
  final TerminalShapedText result;
  final int byteCharge;
}

_ValidatedShapeText _validateShapeText(String text) {
  if (text.isEmpty) {
    throw ArgumentError.value(text, 'text', 'must be nonempty');
  }
  if (text.length > TerminalFontCatalog.maximumResolveTextBytes) {
    throw ArgumentError.value(
      text,
      'text',
      'must be within ${TerminalFontCatalog.maximumResolveTextBytes} '
          'UTF-16 code units',
    );
  }
  var scalarCount = 0;
  final List<int> units = text.codeUnits;
  final List<bool> scalarBoundaries = List<bool>.filled(
    units.length + 1,
    false,
  );
  scalarBoundaries[0] = true;
  for (int index = 0; index < units.length; index++) {
    final int unit = units[index];
    if (unit == 0) {
      throw ArgumentError.value(text, 'text', 'must be NUL-free');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xdc00 ||
          units[index + 1] > 0xdfff) {
        throw ArgumentError.value(text, 'text', 'contains malformed UTF-16');
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError.value(text, 'text', 'contains malformed UTF-16');
    }
    scalarCount++;
    scalarBoundaries[index + 1] = true;
  }
  final Uint8List bytes = Uint8List.fromList(utf8.encode(text));
  if (bytes.length > TerminalFontCatalog.maximumResolveTextBytes) {
    throw ArgumentError.value(
      text,
      'text',
      'UTF-8 exceeds ${TerminalFontCatalog.maximumResolveTextBytes} bytes',
    );
  }
  return _ValidatedShapeText(
    bytes: bytes,
    utf16Length: units.length,
    scalarCount: scalarCount,
    scalarBoundaries: scalarBoundaries,
  );
}

const int _shapeBufferMagic = 0x48535444;
const int _shapeBufferVersion = 1;
const int _shapeHeaderSize = 80;
const int _shapeRunSize = 40;
const int _shapeFaceSize = 144;
const int _shapeGlyphSize = 48;
const int _shapeFeatureLigatures = 1 << 0;
const int _shapeFeatureKnownMask = _shapeFeatureLigatures;
const int _maximumShapeRuns = 65536;
const int _maximumShapeFaces = 4096;
const int _maximumShapeGlyphs = 1024 * 1024;
const int _statusBufferTooSmall = 7;

@Native<
  Int32 Function(
    Uint64,
    Uint32,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
  )
>(symbol: 'dtr_font_catalog_shape', assetId: _assetId)
external int _fontCatalogShape(
  int handle,
  int style,
  int featureFlags,
  Pointer<Uint8> text,
  int textLength,
  Pointer<Uint8> output,
  int outputCapacity,
  Pointer<Uint32> outputRequired,
);
