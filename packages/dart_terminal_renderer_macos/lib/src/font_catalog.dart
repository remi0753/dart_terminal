import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

part 'shaping.dart';
part 'raster.dart';

const String _assetId =
    'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

enum TerminalFontStyle { regular, bold, italic, boldItalic }

enum TerminalSyntheticStylePolicy { reject, allow }

abstract final class TerminalResolvedFontFlags {
  static const int fallback = 1 << 0;
  static const int colorGlyphs = 1 << 1;
  static const int synthetic = 1 << 2;
  static const int missingGlyph = 1 << 3;
  static const int monospaced = 1 << 4;
  static const int knownMask =
      fallback | colorGlyphs | synthetic | missingGlyph | monospaced;
}

final class TerminalFontCatalogMetrics {
  const TerminalFontCatalogMetrics({
    required this.pointSize,
    required this.cellWidth,
    required this.cellHeight,
    required this.ascent,
    required this.descent,
    required this.leading,
    required this.baseline,
    required this.underlinePosition,
    required this.underlineThickness,
    required this.strikePosition,
    required this.strikeThickness,
  });

  final double pointSize;
  final double cellWidth;
  final double cellHeight;
  final double ascent;
  final double descent;
  final double leading;
  final double baseline;
  final double underlinePosition;
  final double underlineThickness;
  final double strikePosition;
  final double strikeThickness;
}

final class TerminalResolvedFont {
  const TerminalResolvedFont({
    required this.catalogGeneration,
    required this.faceId,
    required this.flags,
    required this.requestedStyle,
    required this.utf16Length,
    required this.unicodeScalarCount,
    required this.glyphCount,
    required this.postscriptName,
  });

  final int catalogGeneration;
  final int faceId;
  final int flags;
  final TerminalFontStyle requestedStyle;
  final int utf16Length;
  final int unicodeScalarCount;
  final int glyphCount;
  final String postscriptName;

  bool get isFallback => flags & TerminalResolvedFontFlags.fallback != 0;
  bool get hasColorGlyphs => flags & TerminalResolvedFontFlags.colorGlyphs != 0;
  bool get isSynthetic => flags & TerminalResolvedFontFlags.synthetic != 0;
  bool get hasMissingGlyph =>
      flags & TerminalResolvedFontFlags.missingGlyph != 0;
  bool get isMonospaced => flags & TerminalResolvedFontFlags.monospaced != 0;
}

final class TerminalFontCatalogException implements Exception {
  const TerminalFontCatalogException({
    required this.operation,
    required this.status,
  });

  final String operation;
  final int status;

  @override
  String toString() =>
      'TerminalFontCatalogException($operation, status=$status)';
}

/// Generation-owned CoreText font resources.
///
/// All methods are synchronous bounded native calls. Applications must invoke
/// them from their font/render worker domain, never an AppKit event handler.
final class TerminalFontCatalog implements Finalizable {
  factory TerminalFontCatalog.open({
    String family = 'Menlo',
    double pointSize = 14,
    TerminalSyntheticStylePolicy syntheticStylePolicy =
        TerminalSyntheticStylePolicy.allow,
  }) {
    if (!pointSize.isFinite || pointSize < 4 || pointSize > 128) {
      throw RangeError.range(pointSize, 4, 128, 'pointSize');
    }
    if (family.length > maximumFamilyBytes) {
      throw ArgumentError.value(
        family,
        'family',
        'must be within $maximumFamilyBytes UTF-16 code units',
      );
    }
    final Uint8List familyUtf8 = Uint8List.fromList(utf8.encode(family));
    if (familyUtf8.length > maximumFamilyBytes || familyUtf8.contains(0)) {
      throw ArgumentError.value(
        family,
        'family',
        'must be NUL-free UTF-8 within $maximumFamilyBytes bytes',
      );
    }
    final Arena arena = Arena();
    try {
      final Pointer<Uint8> familyPointer = familyUtf8.isEmpty
          ? nullptr
          : arena<Uint8>(familyUtf8.length);
      if (familyUtf8.isNotEmpty) {
        familyPointer.asTypedList(familyUtf8.length).setAll(0, familyUtf8);
      }
      final Pointer<_FontCatalogSummaryV1> output =
          arena<_FontCatalogSummaryV1>();
      output.ref
        ..structSize = sizeOf<_FontCatalogSummaryV1>()
        ..version = _fontCatalogSummaryVersion;
      final int status = _fontCatalogCreate(
        familyPointer,
        familyUtf8.length,
        pointSize,
        syntheticStylePolicy == TerminalSyntheticStylePolicy.allow ? 1 : 0,
        output,
      );
      _checkStatus(status, 'font catalog create');
      try {
        final TerminalFontCatalog catalog = _fromSummary(
          output.ref,
          family,
          syntheticStylePolicy,
        );
        _catalogFinalizer.attach(
          catalog,
          Pointer<Void>.fromAddress(output.ref.handle),
          detach: catalog,
        );
        return catalog;
      } on Object {
        if (output.ref.handle != 0) {
          _fontCatalogRelease(output.ref.handle);
        }
        rethrow;
      }
    } finally {
      arena.releaseAll();
    }
  }

  TerminalFontCatalog._({
    required int handle,
    required this.generation,
    required this.family,
    required this.syntheticStylePolicy,
    required this.metrics,
    required this.availableStyleBits,
    required this.syntheticStyleBits,
    required List<int> faceIds,
  }) : _handle = handle,
       _faceIds = List<int>.unmodifiable(faceIds);

  static const int maximumFamilyBytes = 1024;
  static const int maximumResolveTextBytes = 1024 * 1024;

  int _handle;
  final int generation;
  final String family;
  final TerminalSyntheticStylePolicy syntheticStylePolicy;
  final TerminalFontCatalogMetrics metrics;
  final int availableStyleBits;
  final int syntheticStyleBits;
  final List<int> _faceIds;

  bool get isDisposed => _handle == 0;

  bool isStyleAvailable(TerminalFontStyle style) =>
      availableStyleBits & (1 << style.index) != 0;

  bool isStyleSynthetic(TerminalFontStyle style) =>
      syntheticStyleBits & (1 << style.index) != 0;

  int faceIdForStyle(TerminalFontStyle style) => _faceIds[style.index];

  TerminalResolvedFont resolve(
    String text, {
    TerminalFontStyle style = TerminalFontStyle.regular,
  }) {
    final int handle = _liveHandle();
    if (text.length > maximumResolveTextBytes) {
      throw ArgumentError.value(
        text,
        'text',
        'must be within $maximumResolveTextBytes UTF-16 code units',
      );
    }
    final Uint8List textUtf8 = Uint8List.fromList(utf8.encode(text));
    if (textUtf8.isEmpty ||
        textUtf8.length > maximumResolveTextBytes ||
        textUtf8.contains(0)) {
      throw ArgumentError.value(
        text,
        'text',
        'must be nonempty NUL-free UTF-8 within '
            '$maximumResolveTextBytes bytes',
      );
    }
    final Arena arena = Arena();
    try {
      final Pointer<Uint8> textPointer = arena<Uint8>(textUtf8.length);
      textPointer.asTypedList(textUtf8.length).setAll(0, textUtf8);
      final Pointer<_ResolvedFontV1> output = arena<_ResolvedFontV1>();
      output.ref
        ..structSize = sizeOf<_ResolvedFontV1>()
        ..version = _resolvedFontVersion;
      final int status = _fontCatalogResolve(
        handle,
        style.index,
        textPointer,
        textUtf8.length,
        output,
      );
      _checkStatus(status, 'font catalog resolve');
      return _decodeResolved(output.ref, style);
    } finally {
      arena.releaseAll();
    }
  }

  void dispose() {
    final int handle = _handle;
    if (handle == 0) {
      return;
    }
    _handle = 0;
    _catalogFinalizer.detach(this);
    _checkStatus(_fontCatalogRelease(handle), 'font catalog release');
  }

  int _liveHandle() {
    if (_handle == 0) {
      throw StateError('TerminalFontCatalog is disposed');
    }
    return _handle;
  }

  static TerminalFontCatalog _fromSummary(
    _FontCatalogSummaryV1 summary,
    String family,
    TerminalSyntheticStylePolicy syntheticStylePolicy,
  ) {
    if (summary.structSize != sizeOf<_FontCatalogSummaryV1>() ||
        summary.version != _fontCatalogSummaryVersion ||
        summary.handle == 0 ||
        summary.generation == 0 ||
        summary.availableStyleBits & ~0x0f != 0 ||
        summary.syntheticStyleBits & ~0x0e != 0 ||
        summary.availableStyleBits & summary.syntheticStyleBits != 0 ||
        summary.availableStyleBits & 1 == 0) {
      throw const FormatException('invalid native font catalog summary');
    }
    for (int index = 0; index < 4; index++) {
      if (summary.reserved[index] != 0) {
        throw const FormatException('nonzero font catalog reserved field');
      }
    }
    final List<double> metricValues = <double>[
      summary.pointSize,
      summary.cellWidth,
      summary.cellHeight,
      summary.ascent,
      summary.descent,
      summary.leading,
      summary.baseline,
      summary.underlinePosition,
      summary.underlineThickness,
      summary.strikePosition,
      summary.strikeThickness,
    ];
    if (metricValues.any((double value) => !value.isFinite) ||
        summary.pointSize <= 0 ||
        summary.cellWidth <= 0 ||
        summary.cellHeight <= 0 ||
        summary.ascent <= 0 ||
        summary.descent <= 0 ||
        summary.leading < 0 ||
        summary.baseline <= 0 ||
        summary.underlineThickness <= 0 ||
        summary.strikePosition <= 0 ||
        summary.strikeThickness <= 0) {
      throw const FormatException('invalid native font metrics');
    }
    final List<int> faceIds = <int>[
      summary.regularFaceId,
      summary.boldFaceId,
      summary.italicFaceId,
      summary.boldItalicFaceId,
    ];
    for (int style = 0; style < faceIds.length; style++) {
      final bool selectable =
          (summary.availableStyleBits | summary.syntheticStyleBits) &
              (1 << style) !=
          0;
      if (selectable != (faceIds[style] != 0)) {
        throw const FormatException('invalid native style face identity');
      }
    }
    return TerminalFontCatalog._(
      handle: summary.handle,
      generation: summary.generation,
      family: family,
      syntheticStylePolicy: syntheticStylePolicy,
      metrics: TerminalFontCatalogMetrics(
        pointSize: summary.pointSize,
        cellWidth: summary.cellWidth,
        cellHeight: summary.cellHeight,
        ascent: summary.ascent,
        descent: summary.descent,
        leading: summary.leading,
        baseline: summary.baseline,
        underlinePosition: summary.underlinePosition,
        underlineThickness: summary.underlineThickness,
        strikePosition: summary.strikePosition,
        strikeThickness: summary.strikeThickness,
      ),
      availableStyleBits: summary.availableStyleBits,
      syntheticStyleBits: summary.syntheticStyleBits,
      faceIds: faceIds,
    );
  }

  TerminalResolvedFont _decodeResolved(
    _ResolvedFontV1 resolved,
    TerminalFontStyle style,
  ) {
    if (resolved.structSize != sizeOf<_ResolvedFontV1>() ||
        resolved.version != _resolvedFontVersion ||
        resolved.catalogGeneration != generation ||
        resolved.faceId == 0 ||
        resolved.flags & ~TerminalResolvedFontFlags.knownMask != 0 ||
        resolved.requestedStyle != style.index ||
        resolved.utf16Length == 0 ||
        resolved.unicodeScalarCount == 0 ||
        resolved.glyphCount == 0 ||
        resolved.postscriptNameLength == 0 ||
        resolved.postscriptNameLength > _maximumPostscriptNameBytes) {
      throw const FormatException('invalid native resolved font record');
    }
    for (int index = 0; index < 4; index++) {
      if (resolved.reserved[index] != 0) {
        throw const FormatException('nonzero resolved font reserved field');
      }
    }
    final Uint8List nameBytes = Uint8List(resolved.postscriptNameLength);
    for (int index = 0; index < nameBytes.length; index++) {
      nameBytes[index] = resolved.postscriptName[index];
    }
    if (resolved.postscriptName[resolved.postscriptNameLength] != 0) {
      throw const FormatException('resolved font name lacks NUL terminator');
    }
    final String postscriptName = utf8.decode(nameBytes, allowMalformed: false);
    if (postscriptName.isEmpty || postscriptName.contains('\u0000')) {
      throw const FormatException('invalid resolved PostScript name');
    }
    return TerminalResolvedFont(
      catalogGeneration: resolved.catalogGeneration,
      faceId: resolved.faceId,
      flags: resolved.flags,
      requestedStyle: style,
      utf16Length: resolved.utf16Length,
      unicodeScalarCount: resolved.unicodeScalarCount,
      glyphCount: resolved.glyphCount,
      postscriptName: postscriptName,
    );
  }
}

final class _FontCatalogSummaryV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int handle;

  @Uint64()
  external int generation;

  @Double()
  external double pointSize;

  @Double()
  external double cellWidth;

  @Double()
  external double cellHeight;

  @Double()
  external double ascent;

  @Double()
  external double descent;

  @Double()
  external double leading;

  @Double()
  external double baseline;

  @Double()
  external double underlinePosition;

  @Double()
  external double underlineThickness;

  @Double()
  external double strikePosition;

  @Double()
  external double strikeThickness;

  @Uint32()
  external int availableStyleBits;

  @Uint32()
  external int syntheticStyleBits;

  @Uint32()
  external int regularFaceId;

  @Uint32()
  external int boldFaceId;

  @Uint32()
  external int italicFaceId;

  @Uint32()
  external int boldItalicFaceId;

  @Array(4)
  external Array<Uint32> reserved;
}

final class _ResolvedFontV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int catalogGeneration;

  @Uint32()
  external int faceId;

  @Uint32()
  external int flags;

  @Uint32()
  external int requestedStyle;

  @Uint32()
  external int utf16Length;

  @Uint32()
  external int unicodeScalarCount;

  @Uint32()
  external int glyphCount;

  @Uint32()
  external int postscriptNameLength;

  @Array(4)
  external Array<Uint32> reserved;

  @Array(128)
  external Array<Uint8> postscriptName;
}

const int _fontCatalogSummaryVersion = 1;
const int _resolvedFontVersion = 1;
const int _maximumPostscriptNameBytes = 127;

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Uint32,
    Double,
    Uint32,
    Pointer<_FontCatalogSummaryV1>,
  )
>(symbol: 'dtr_font_catalog_create', assetId: _assetId, isLeaf: true)
external int _fontCatalogCreate(
  Pointer<Uint8> family,
  int familyLength,
  double pointSize,
  int policyFlags,
  Pointer<_FontCatalogSummaryV1> output,
);

@Native<Int32 Function(Uint64)>(
  symbol: 'dtr_font_catalog_release',
  assetId: _assetId,
  isLeaf: true,
)
external int _fontCatalogRelease(int handle);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'dtr_font_catalog_release_finalizer',
  assetId: _assetId,
)
external void _fontCatalogReleaseFinalizer(Pointer<Void> handle);

final NativeFinalizer _catalogFinalizer = NativeFinalizer(
  Native.addressOf(_fontCatalogReleaseFinalizer),
);

@Native<
  Int32 Function(
    Uint64,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<_ResolvedFontV1>,
  )
>(symbol: 'dtr_font_catalog_resolve', assetId: _assetId, isLeaf: true)
external int _fontCatalogResolve(
  int handle,
  int style,
  Pointer<Uint8> text,
  int textLength,
  Pointer<_ResolvedFontV1> output,
);

void _checkStatus(int status, String operation) {
  if (status != 0) {
    throw TerminalFontCatalogException(operation: operation, status: status);
  }
}
