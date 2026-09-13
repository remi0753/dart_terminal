part of 'font_catalog.dart';

/// One finite OpenType variation coordinate owned by a four-byte ASCII tag.
final class TerminalFontVariationAxis {
  factory TerminalFontVariationAxis(String tag, double value) {
    final List<int> units = tag.codeUnits;
    if (units.length != tagByteLength ||
        units.any((int unit) => unit < 0x20 || unit > 0x7e)) {
      throw ArgumentError.value(
        tag,
        'tag',
        'must contain exactly four printable ASCII bytes',
      );
    }
    if (!value.isFinite || value < minimumValue || value > maximumValue) {
      throw RangeError.value(
        value,
        'value',
        'must be finite and within $minimumValue...$maximumValue',
      );
    }
    var encodedTag = 0;
    for (final int unit in units) {
      encodedTag = (encodedTag << 8) | unit;
    }
    return TerminalFontVariationAxis._(tag, encodedTag, value);
  }

  const TerminalFontVariationAxis._(this.tag, this.encodedTag, this.value);

  static const int tagByteLength = 4;
  static const double minimumValue = -65536;
  static const double maximumValue = 65536;

  final String tag;

  /// Big-endian OpenType tag value, for example `wght` is `0x77676874`.
  final int encodedTag;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is TerminalFontVariationAxis &&
      encodedTag == other.encodedTag &&
      value == other.value;

  @override
  int get hashCode => Object.hash(encodedTag, value);
}

/// One inclusive Unicode scalar range assigned to an explicit font family.
///
/// Overlapping entries are valid. The later entry in a catalog configuration
/// has priority, matching normal layered configuration ownership.
final class TerminalFontCodepointOverride {
  factory TerminalFontCodepointOverride({
    required int firstScalar,
    required int lastScalar,
    required String family,
  }) {
    if (!_isUnicodeScalar(firstScalar) ||
        !_isUnicodeScalar(lastScalar) ||
        firstScalar > lastScalar ||
        firstScalar <= 0xdfff && lastScalar >= 0xd800) {
      throw ArgumentError.value(
        '$firstScalar..$lastScalar',
        'range',
        'must be one ordered inclusive Unicode scalar range',
      );
    }
    final Uint8List bytes = Uint8List.fromList(utf8.encode(family));
    if (bytes.isEmpty ||
        bytes.length > TerminalFontCatalog.maximumFamilyBytes ||
        bytes.contains(0)) {
      throw ArgumentError.value(
        family,
        'family',
        'must be nonempty NUL-free UTF-8 within '
            '${TerminalFontCatalog.maximumFamilyBytes} bytes',
      );
    }
    return TerminalFontCodepointOverride._(
      firstScalar,
      lastScalar,
      family,
      bytes.length,
    );
  }

  const TerminalFontCodepointOverride._(
    this.firstScalar,
    this.lastScalar,
    this.family,
    this.familyUtf8Bytes,
  );

  static const int maximumScalar = 0x10ffff;

  final int firstScalar;
  final int lastScalar;
  final String family;
  final int familyUtf8Bytes;

  bool contains(int scalar) => scalar >= firstScalar && scalar <= lastScalar;

  @override
  bool operator ==(Object other) =>
      other is TerminalFontCodepointOverride &&
      firstScalar == other.firstScalar &&
      lastScalar == other.lastScalar &&
      family == other.family;

  @override
  int get hashCode => Object.hash(firstScalar, lastScalar, family);

  static bool _isUnicodeScalar(int value) =>
      value >= 0 &&
      value <= maximumScalar &&
      (value < 0xd800 || value > 0xdfff);
}

/// Immutable, bounded request copied into one font catalog generation.
final class TerminalFontCatalogConfiguration {
  factory TerminalFontCatalogConfiguration({
    Iterable<TerminalFontVariationAxis> regularVariations =
        const <TerminalFontVariationAxis>[],
    Iterable<TerminalFontVariationAxis> boldVariations =
        const <TerminalFontVariationAxis>[],
    Iterable<TerminalFontVariationAxis> italicVariations =
        const <TerminalFontVariationAxis>[],
    Iterable<TerminalFontVariationAxis> boldItalicVariations =
        const <TerminalFontVariationAxis>[],
    Iterable<TerminalFontCodepointOverride> codepointOverrides =
        const <TerminalFontCodepointOverride>[],
  }) {
    final List<List<TerminalFontVariationAxis>> byStyle =
        <List<TerminalFontVariationAxis>>[
          _validateVariations(regularVariations, TerminalFontStyle.regular),
          _validateVariations(boldVariations, TerminalFontStyle.bold),
          _validateVariations(italicVariations, TerminalFontStyle.italic),
          _validateVariations(
            boldItalicVariations,
            TerminalFontStyle.boldItalic,
          ),
        ];
    final List<TerminalFontCodepointOverride> overrides =
        List<TerminalFontCodepointOverride>.unmodifiable(codepointOverrides);
    if (overrides.length > maximumCodepointOverrides) {
      throw RangeError.range(
        overrides.length,
        0,
        maximumCodepointOverrides,
        'codepointOverrides.length',
      );
    }
    final int familyBytes = overrides.fold<int>(
      0,
      (int total, TerminalFontCodepointOverride override) =>
          total + override.familyUtf8Bytes,
    );
    if (familyBytes > maximumOverrideFamilyUtf8Bytes) {
      throw RangeError.range(
        familyBytes,
        0,
        maximumOverrideFamilyUtf8Bytes,
        'overrideFamilyUtf8Bytes',
      );
    }
    return TerminalFontCatalogConfiguration._(
      List<List<TerminalFontVariationAxis>>.unmodifiable(byStyle),
      overrides,
      familyBytes,
    );
  }

  const TerminalFontCatalogConfiguration._(
    this._variationsByStyle,
    this.codepointOverrides,
    this.overrideFamilyUtf8Bytes,
  );

  static const int maximumVariationsPerStyle = 16;
  static const int maximumVariationCount = maximumVariationsPerStyle * 4;
  static const int maximumCodepointOverrides = 256;
  static const int maximumOverrideFamilyUtf8Bytes = 64 * 1024;

  static final TerminalFontCatalogConfiguration empty =
      TerminalFontCatalogConfiguration();

  final List<List<TerminalFontVariationAxis>> _variationsByStyle;
  final List<TerminalFontCodepointOverride> codepointOverrides;
  final int overrideFamilyUtf8Bytes;

  List<TerminalFontVariationAxis> variationsFor(TerminalFontStyle style) =>
      _variationsByStyle[style.index];

  int get variationCount => _variationsByStyle.fold<int>(
    0,
    (int total, List<TerminalFontVariationAxis> axes) => total + axes.length,
  );

  bool get isEmpty => variationCount == 0 && codepointOverrides.isEmpty;

  /// Resolves configuration precedence without consulting installed fonts.
  TerminalFontCodepointOverride? overrideForScalar(int scalar) {
    if (!TerminalFontCodepointOverride._isUnicodeScalar(scalar)) return null;
    for (int index = codepointOverrides.length - 1; index >= 0; index--) {
      final TerminalFontCodepointOverride candidate = codepointOverrides[index];
      if (candidate.contains(scalar)) return candidate;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TerminalFontCatalogConfiguration ||
        overrideFamilyUtf8Bytes != other.overrideFamilyUtf8Bytes ||
        !_listEquals(codepointOverrides, other.codepointOverrides)) {
      return false;
    }
    for (final TerminalFontStyle style in TerminalFontStyle.values) {
      if (!_listEquals(variationsFor(style), other.variationsFor(style))) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<int>[
    overrideFamilyUtf8Bytes,
    Object.hashAll(codepointOverrides),
    for (final List<TerminalFontVariationAxis> axes in _variationsByStyle)
      Object.hashAll(axes),
  ]);

  static List<TerminalFontVariationAxis> _validateVariations(
    Iterable<TerminalFontVariationAxis> input,
    TerminalFontStyle style,
  ) {
    final List<TerminalFontVariationAxis> axes =
        List<TerminalFontVariationAxis>.unmodifiable(input);
    if (axes.length > maximumVariationsPerStyle) {
      throw RangeError.range(
        axes.length,
        0,
        maximumVariationsPerStyle,
        '${style.name}Variations.length',
      );
    }
    final Set<int> tags = <int>{};
    for (final TerminalFontVariationAxis axis in axes) {
      if (!tags.add(axis.encodedTag)) {
        throw ArgumentError.value(
          axis.tag,
          '${style.name}Variations',
          'contains a duplicate axis tag',
        );
      }
    }
    return axes;
  }

  static bool _listEquals<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

enum TerminalFontResolutionSource {
  requested,
  codepointOverride,
  coreTextFallback,
  missingGlyph,
}

/// One content-free aggregate face decision in a diagnostic snapshot.
final class TerminalFontResolutionDiagnostic {
  factory TerminalFontResolutionDiagnostic({
    required TerminalFontResolutionSource source,
    required int faceId,
    required int flags,
    required String postscriptName,
    required int occurrenceCount,
  }) {
    final int nameBytes = utf8.encode(postscriptName).length;
    if (faceId <= 0 || faceId > 0xffffffff) {
      throw RangeError.range(faceId, 1, 0xffffffff, 'faceId');
    }
    if (flags & ~TerminalResolvedFontFlags.knownMask != 0) {
      throw ArgumentError.value(flags, 'flags', 'contains unknown flag bits');
    }
    if (nameBytes == 0 ||
        nameBytes > _maximumPostscriptNameBytes ||
        postscriptName.contains('\u0000')) {
      throw ArgumentError.value(
        postscriptName,
        'postscriptName',
        'must be NUL-free UTF-8 within $_maximumPostscriptNameBytes bytes',
      );
    }
    _validateDiagnosticCounter(occurrenceCount, 'occurrenceCount');
    if (occurrenceCount == 0) {
      throw RangeError.range(
        occurrenceCount,
        1,
        TerminalFontCatalogDiagnostics.maximumCounter,
        'occurrenceCount',
      );
    }
    return TerminalFontResolutionDiagnostic._(
      source,
      faceId,
      flags,
      postscriptName,
      occurrenceCount,
    );
  }

  const TerminalFontResolutionDiagnostic._(
    this.source,
    this.faceId,
    this.flags,
    this.postscriptName,
    this.occurrenceCount,
  );

  final TerminalFontResolutionSource source;
  final int faceId;
  final int flags;
  final String postscriptName;
  final int occurrenceCount;

  bool get isFallback => flags & TerminalResolvedFontFlags.fallback != 0;
  bool get hasMissingGlyph =>
      flags & TerminalResolvedFontFlags.missingGlyph != 0;
}

/// Bounded counters copied from one catalog without source text or codepoints.
final class TerminalFontCatalogDiagnostics {
  factory TerminalFontCatalogDiagnostics({
    required int catalogGeneration,
    required int configuredVariationCount,
    required int appliedVariationCount,
    required int unavailableVariationCount,
    required int configuredOverrideCount,
    required int availableOverrideCount,
    required int unavailableOverrideCount,
    required int overrideMatchCount,
    required int overrideAppliedCount,
    required int overrideFallbackCount,
    required int coreTextFallbackCount,
    required int missingGlyphCount,
    Iterable<TerminalFontResolutionDiagnostic> resolutions =
        const <TerminalFontResolutionDiagnostic>[],
  }) {
    if (catalogGeneration <= 0) {
      throw RangeError.range(
        catalogGeneration,
        1,
        maximumCounter,
        'catalogGeneration',
      );
    }
    final List<int> counters = <int>[
      configuredVariationCount,
      appliedVariationCount,
      unavailableVariationCount,
      configuredOverrideCount,
      availableOverrideCount,
      unavailableOverrideCount,
      overrideMatchCount,
      overrideAppliedCount,
      overrideFallbackCount,
      coreTextFallbackCount,
      missingGlyphCount,
    ];
    const List<String> names = <String>[
      'configuredVariationCount',
      'appliedVariationCount',
      'unavailableVariationCount',
      'configuredOverrideCount',
      'availableOverrideCount',
      'unavailableOverrideCount',
      'overrideMatchCount',
      'overrideAppliedCount',
      'overrideFallbackCount',
      'coreTextFallbackCount',
      'missingGlyphCount',
    ];
    for (int index = 0; index < counters.length; index++) {
      _validateDiagnosticCounter(counters[index], names[index]);
    }
    if (appliedVariationCount + unavailableVariationCount !=
            configuredVariationCount ||
        availableOverrideCount + unavailableOverrideCount !=
            configuredOverrideCount ||
        overrideAppliedCount + overrideFallbackCount != overrideMatchCount) {
      throw ArgumentError('font diagnostic totals are inconsistent');
    }
    final List<TerminalFontResolutionDiagnostic> copied =
        List<TerminalFontResolutionDiagnostic>.unmodifiable(resolutions);
    if (copied.length > maximumResolutionRecords) {
      throw RangeError.range(
        copied.length,
        0,
        maximumResolutionRecords,
        'resolutions.length',
      );
    }
    final Set<(TerminalFontResolutionSource, int)> identities =
        <(TerminalFontResolutionSource, int)>{};
    for (final TerminalFontResolutionDiagnostic diagnostic in copied) {
      if (!identities.add((diagnostic.source, diagnostic.faceId))) {
        throw ArgumentError('duplicate font diagnostic face identity');
      }
    }
    return TerminalFontCatalogDiagnostics._(
      catalogGeneration: catalogGeneration,
      configuredVariationCount: configuredVariationCount,
      appliedVariationCount: appliedVariationCount,
      unavailableVariationCount: unavailableVariationCount,
      configuredOverrideCount: configuredOverrideCount,
      availableOverrideCount: availableOverrideCount,
      unavailableOverrideCount: unavailableOverrideCount,
      overrideMatchCount: overrideMatchCount,
      overrideAppliedCount: overrideAppliedCount,
      overrideFallbackCount: overrideFallbackCount,
      coreTextFallbackCount: coreTextFallbackCount,
      missingGlyphCount: missingGlyphCount,
      resolutions: copied,
    );
  }

  const TerminalFontCatalogDiagnostics._({
    required this.catalogGeneration,
    required this.configuredVariationCount,
    required this.appliedVariationCount,
    required this.unavailableVariationCount,
    required this.configuredOverrideCount,
    required this.availableOverrideCount,
    required this.unavailableOverrideCount,
    required this.overrideMatchCount,
    required this.overrideAppliedCount,
    required this.overrideFallbackCount,
    required this.coreTextFallbackCount,
    required this.missingGlyphCount,
    required this.resolutions,
  });

  static const int maximumCounter = 0x7fffffffffffffff;
  static const int maximumResolutionRecords = 256;

  final int catalogGeneration;
  final int configuredVariationCount;
  final int appliedVariationCount;
  final int unavailableVariationCount;
  final int configuredOverrideCount;
  final int availableOverrideCount;
  final int unavailableOverrideCount;
  final int overrideMatchCount;
  final int overrideAppliedCount;
  final int overrideFallbackCount;
  final int coreTextFallbackCount;
  final int missingGlyphCount;
  final List<TerminalFontResolutionDiagnostic> resolutions;
}

void _validateDiagnosticCounter(int value, String name) {
  if (value < 0 || value > TerminalFontCatalogDiagnostics.maximumCounter) {
    throw RangeError.range(
      value,
      0,
      TerminalFontCatalogDiagnostics.maximumCounter,
      name,
    );
  }
}
