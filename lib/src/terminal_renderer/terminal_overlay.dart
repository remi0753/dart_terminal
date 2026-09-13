import 'dart:math' as math;
import 'dart:typed_data';

import '../terminal_core/terminal_screen.dart';

/// Paint precedence for metadata-only terminal grid overlays.
///
/// Canonical terminal cells and text never enter this value. Producers retain
/// their own stable anchors and publish only current viewport geometry.
enum TerminalGridOverlayKind {
  searchMatch(10),
  searchSelectedMatch(20),
  inspectorHyperlink(30),
  inspectorSemanticPrompt(31),
  inspectorSemanticInput(32);

  const TerminalGridOverlayKind(this.paintOrder);

  final int paintOrder;
}

/// One non-empty, end-exclusive run of terminal cells on a viewport row.
final class TerminalGridOverlaySpan {
  TerminalGridOverlaySpan({
    required this.kind,
    required this.row,
    required this.startColumn,
    required this.endColumn,
  }) {
    RangeError.checkValueInInterval(row, 0, TerminalScreen.maxRows - 1, 'row');
    RangeError.checkValueInInterval(
      startColumn,
      0,
      TerminalScreen.maxColumns - 1,
      'startColumn',
    );
    RangeError.checkValueInInterval(
      endColumn,
      1,
      TerminalScreen.maxColumns,
      'endColumn',
    );
    if (startColumn >= endColumn) {
      throw ArgumentError('terminal grid overlay span must be non-empty');
    }
  }

  final TerminalGridOverlayKind kind;
  final int row;
  final int startColumn;
  final int endColumn;

  int get cellCount => endColumn - startColumn;

  @override
  bool operator ==(Object other) =>
      other is TerminalGridOverlaySpan &&
      other.kind == kind &&
      other.row == row &&
      other.startColumn == startColumn &&
      other.endColumn == endColumn;

  @override
  int get hashCode => Object.hash(kind, row, startColumn, endColumn);
}

/// Immutable, generation-bound overlay geometry for one visible grid.
final class TerminalGridOverlayProjection {
  TerminalGridOverlayProjection({
    required this.sourceGeneration,
    required Iterable<TerminalGridOverlaySpan> spans,
    this.isTruncated = false,
    int maximumSpans = defaultMaximumSpans,
  }) : spans = _copyCanonicalSpans(spans, maximumSpans) {
    RangeError.checkValueInInterval(
      sourceGeneration,
      1,
      0x7fffffffffffffff,
      'sourceGeneration',
    );
  }

  static const int defaultMaximumSpans = 4096;
  static const int maximumSpans = 4096;

  final int sourceGeneration;
  final List<TerminalGridOverlaySpan> spans;
  final bool isTruncated;

  int get spanCount => spans.length;
  int get cellCount => spans.fold<int>(
    0,
    (int total, TerminalGridOverlaySpan span) => total + span.cellCount,
  );
  bool get isEmpty => spans.isEmpty;

  static List<TerminalGridOverlaySpan> _copyCanonicalSpans(
    Iterable<TerminalGridOverlaySpan> source,
    int maximumSpans,
  ) {
    RangeError.checkValueInInterval(
      maximumSpans,
      1,
      TerminalGridOverlayProjection.maximumSpans,
      'maximumSpans',
    );
    final List<TerminalGridOverlaySpan> result = <TerminalGridOverlaySpan>[];
    for (final TerminalGridOverlaySpan span in source) {
      if (result.length == maximumSpans) {
        throw StateError('terminal grid overlay span limit exceeded');
      }
      result.add(span);
    }
    result.sort(_compareSpans);
    return List<TerminalGridOverlaySpan>.unmodifiable(result);
  }

  static int _compareSpans(
    TerminalGridOverlaySpan left,
    TerminalGridOverlaySpan right,
  ) {
    int result = left.kind.paintOrder.compareTo(right.kind.paintOrder);
    if (result != 0) return result;
    result = left.row.compareTo(right.row);
    if (result != 0) return result;
    result = left.startColumn.compareTo(right.startColumn);
    if (result != 0) return result;
    return left.endColumn.compareTo(right.endColumn);
  }
}

enum TerminalRenderColorSpace { srgb, displayP3 }

/// One straight-alpha RGBA8 color with an explicit input color space.
final class TerminalRenderColor {
  const TerminalRenderColor.srgb(this.rgba)
    : colorSpace = TerminalRenderColorSpace.srgb,
      assert(rgba >= 0 && rgba <= 0xffffffff);

  const TerminalRenderColor.displayP3(this.rgba)
    : colorSpace = TerminalRenderColorSpace.displayP3,
      assert(rgba >= 0 && rgba <= 0xffffffff);

  final int rgba;
  final TerminalRenderColorSpace colorSpace;

  int get canonicalSrgbRgba => switch (colorSpace) {
    TerminalRenderColorSpace.srgb => rgba,
    TerminalRenderColorSpace.displayP3 =>
      TerminalRenderColorConverter.displayP3ToSrgbRgba(rgba),
  };
}

/// Deterministic Display P3 to clipped sRGB conversion for RGBA8 inputs.
abstract final class TerminalRenderColorConverter {
  static const int maximumBufferBytes = 64 * 1024 * 1024;

  static int displayP3ToSrgbRgba(int rgba) {
    RangeError.checkValueInInterval(rgba, 0, 0xffffffff, 'rgba');
    final double red = _linearize((rgba >>> 24) & 0xff);
    final double green = _linearize((rgba >>> 16) & 0xff);
    final double blue = _linearize((rgba >>> 8) & 0xff);

    // D65 Display P3 to linear sRGB. Values outside the destination gamut are
    // clipped after matrix conversion; alpha does not participate.
    final double srgbRed =
        1.2247452668286217 * red -
        0.22490436529918698 * green -
        3.969158117384478e-8 * blue;
    final double srgbGreen =
        -0.04205793093772562 * red +
        1.0420810068110567 * green -
        3.079854566708477e-8 * blue;
    final double srgbBlue =
        -0.01964228026582795 * red -
        0.07865491721817101 * green +
        1.0985371937216925 * blue;

    return (_encode(srgbRed) << 24) |
        (_encode(srgbGreen) << 16) |
        (_encode(srgbBlue) << 8) |
        (rgba & 0xff);
  }

  static Uint8List displayP3ToSrgbBuffer(
    List<int> rgba, {
    int maximumBytes = maximumBufferBytes,
  }) {
    RangeError.checkValueInInterval(
      maximumBytes,
      4,
      TerminalRenderColorConverter.maximumBufferBytes,
      'maximumBytes',
    );
    if (rgba.length > maximumBytes) {
      throw StateError('Display P3 color buffer limit exceeded');
    }
    if ((rgba.length & 3) != 0) {
      throw ArgumentError.value(
        rgba.length,
        'rgba.length',
        'must contain complete RGBA8 pixels',
      );
    }
    final Uint8List result = Uint8List(rgba.length);
    for (int offset = 0; offset < rgba.length; offset += 4) {
      final int converted = displayP3ToSrgbRgba(
        (_byte(rgba[offset], offset) << 24) |
            (_byte(rgba[offset + 1], offset + 1) << 16) |
            (_byte(rgba[offset + 2], offset + 2) << 8) |
            _byte(rgba[offset + 3], offset + 3),
      );
      result[offset] = converted >>> 24;
      result[offset + 1] = converted >>> 16;
      result[offset + 2] = converted >>> 8;
      result[offset + 3] = converted;
    }
    return result;
  }

  static int _byte(int value, int index) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, 'rgba[$index]');
    }
    return value;
  }

  static double _linearize(int component) {
    final double encoded = component / 255;
    return encoded <= 0.04045
        ? encoded / 12.92
        : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _encode(double component) {
    final double linear = component.clamp(0, 1);
    final double encoded = linear <= 0.0031308
        ? linear * 12.92
        : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
    return (encoded * 255).round().clamp(0, 255);
  }
}
