import 'dart:math' as math;
import 'dart:typed_data';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_screen_set.dart';

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

  /// Combines two already-bounded projections while reserving the shared cap
  /// for higher-precedence overlay kinds. A projection from another viewport
  /// generation is dropped and reported as truncated.
  static TerminalGridOverlayProjection combine({
    required int sourceGeneration,
    TerminalGridOverlayProjection? first,
    TerminalGridOverlayProjection? second,
    int maximumSpans = defaultMaximumSpans,
  }) {
    RangeError.checkValueInInterval(
      maximumSpans,
      1,
      TerminalGridOverlayProjection.maximumSpans,
      'maximumSpans',
    );
    final List<TerminalGridOverlaySpan> candidates =
        <TerminalGridOverlaySpan>[];
    var isTruncated = false;
    for (final TerminalGridOverlayProjection? projection
        in <TerminalGridOverlayProjection?>[first, second]) {
      if (projection == null) continue;
      isTruncated = isTruncated || projection.isTruncated;
      if (projection.sourceGeneration != sourceGeneration) {
        isTruncated = true;
        continue;
      }
      candidates.addAll(projection.spans);
    }
    candidates.sort((
      TerminalGridOverlaySpan left,
      TerminalGridOverlaySpan right,
    ) {
      final int precedence = right.kind.paintOrder.compareTo(
        left.kind.paintOrder,
      );
      return precedence != 0 ? precedence : _compareSpans(left, right);
    });
    if (candidates.length > maximumSpans) isTruncated = true;
    return TerminalGridOverlayProjection(
      sourceGeneration: sourceGeneration,
      spans: candidates.take(maximumSpans),
      isTruncated: isTruncated,
      maximumSpans: maximumSpans,
    );
  }

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

/// Projects current hyperlink and semantic prompt/input metadata for the
/// diagnostics inspector without resolving any cell text or hyperlink target.
abstract final class TerminalInspectorOverlayProjector {
  static const int defaultMaximumScannedCells = 1048576;
  static const int maximumScannedCells = 4194304;

  static TerminalGridOverlayProjection project({
    required TerminalViewport viewport,
    required TerminalSemanticRangeSnapshot semanticRanges,
    int maximumSpans = TerminalGridOverlayProjection.defaultMaximumSpans,
    int maximumScannedCells = defaultMaximumScannedCells,
  }) {
    RangeError.checkValueInInterval(
      maximumSpans,
      1,
      TerminalGridOverlayProjection.maximumSpans,
      'maximumSpans',
    );
    RangeError.checkValueInInterval(
      maximumScannedCells,
      1,
      TerminalInspectorOverlayProjector.maximumScannedCells,
      'maximumScannedCells',
    );
    final int sourceGeneration = viewport.generation;
    final List<TerminalGridOverlaySpan> hyperlinks =
        <TerminalGridOverlaySpan>[];
    final List<TerminalGridOverlaySpan> prompts = <TerminalGridOverlaySpan>[];
    final List<TerminalGridOverlaySpan> inputs = <TerminalGridOverlaySpan>[];
    var isTruncated = semanticRanges.isTruncated;
    var scannedCells = 0;
    var scanStopped = false;

    void addHyperlink(int row, int startColumn, int endColumn) {
      if (hyperlinks.length == maximumSpans) {
        isTruncated = true;
        return;
      }
      hyperlinks.add(
        TerminalGridOverlaySpan(
          kind: TerminalGridOverlayKind.inspectorHyperlink,
          row: row,
          startColumn: startColumn,
          endColumn: endColumn,
        ),
      );
    }

    for (int row = 0; row < viewport.rows && !scanStopped; row++) {
      var currentHyperlink = 0;
      var runStart = 0;
      for (int column = 0; column < viewport.columns; column++) {
        if (scannedCells == maximumScannedCells) {
          if (currentHyperlink != 0) addHyperlink(row, runStart, column);
          isTruncated = true;
          scanStopped = true;
          break;
        }
        scannedCells++;
        final int hyperlink = viewport.hyperlinkAt(row, column);
        if (hyperlink == currentHyperlink) continue;
        if (currentHyperlink != 0) addHyperlink(row, runStart, column);
        currentHyperlink = hyperlink;
        runStart = column;
      }
      if (!scanStopped && currentHyperlink != 0) {
        addHyperlink(row, runStart, viewport.columns);
      }
    }

    void addSemantic(
      TerminalSemanticRange range,
      TerminalGridOverlayKind kind,
      List<TerminalGridOverlaySpan> destination,
    ) {
      final TerminalSelectionRange? selection = viewport.selectionRange(
        range.start,
        range.end,
      );
      final TerminalSelectionProjection? projection = selection == null
          ? null
          : viewport.projectSelection(selection);
      if (projection == null) {
        isTruncated = true;
        return;
      }
      for (final TerminalSelectionSpan span in projection.spans) {
        if (destination.length == maximumSpans) {
          isTruncated = true;
          return;
        }
        destination.add(
          TerminalGridOverlaySpan(
            kind: kind,
            row: span.row,
            startColumn: span.startColumn,
            endColumn: span.endColumn,
          ),
        );
      }
    }

    for (final TerminalSemanticRange range in semanticRanges.ranges) {
      switch (range.kind) {
        case TerminalSemanticRangeKind.prompt:
          addSemantic(
            range,
            TerminalGridOverlayKind.inspectorSemanticPrompt,
            prompts,
          );
        case TerminalSemanticRangeKind.command:
          addSemantic(
            range,
            TerminalGridOverlayKind.inspectorSemanticInput,
            inputs,
          );
        case TerminalSemanticRangeKind.output:
          break;
      }
    }

    final List<TerminalGridOverlaySpan> retained = <TerminalGridOverlaySpan>[];
    void retain(List<TerminalGridOverlaySpan> source) {
      final int remaining = maximumSpans - retained.length;
      if (source.length > remaining) isTruncated = true;
      retained.addAll(source.take(remaining));
    }

    // Semantic input and prompt geometry remains visible under hyperlink cap
    // pressure. The final projection restores canonical paint order.
    retain(_coalesceOverlaySpans(inputs));
    retain(_coalesceOverlaySpans(prompts));
    retain(hyperlinks);
    return TerminalGridOverlayProjection(
      sourceGeneration: sourceGeneration,
      spans: retained,
      isTruncated: isTruncated,
      maximumSpans: maximumSpans,
    );
  }
}

/// Monotonic content-free activation owner for the diagnostics overlay.
final class TerminalInspectorOverlayState {
  int _generation = 0;
  bool _isActive = false;

  int get generation => _generation;
  bool get isActive => _isActive;

  bool update({required int generation, required bool isActive}) {
    RangeError.checkValueInInterval(
      generation,
      1,
      0x7fffffffffffffff,
      'generation',
    );
    if (generation < _generation) {
      throw StateError('inspector overlay generation regressed');
    }
    if (generation == _generation) {
      if (isActive != _isActive) {
        throw StateError('inspector overlay generation has conflicting state');
      }
      return false;
    }
    _generation = generation;
    _isActive = isActive;
    return true;
  }

  TerminalGridOverlayProjection? project(
    TerminalViewport viewport,
    TerminalSemanticRangeSnapshot semanticRanges,
  ) => _isActive
      ? TerminalInspectorOverlayProjector.project(
          viewport: viewport,
          semanticRanges: semanticRanges,
        )
      : null;
}

/// Projects stable exact-search matches into bounded current-viewport spans.
abstract final class TerminalSearchOverlayProjector {
  static TerminalGridOverlayProjection project({
    required TerminalViewport viewport,
    required TerminalSearchResult result,
    int selectedMatchIndex = -1,
    int maximumSpans = TerminalGridOverlayProjection.defaultMaximumSpans,
  }) {
    RangeError.checkValueInInterval(
      maximumSpans,
      1,
      TerminalGridOverlayProjection.maximumSpans,
      'maximumSpans',
    );
    if (selectedMatchIndex < -1 ||
        selectedMatchIndex >= result.matches.length) {
      throw RangeError.range(
        selectedMatchIndex,
        -1,
        result.matches.isEmpty ? -1 : result.matches.length - 1,
        'selectedMatchIndex',
      );
    }

    final int viewportGeneration = viewport.generation;
    if (!viewport.isSearchResultCurrent(result)) {
      return TerminalGridOverlayProjection(
        sourceGeneration: viewportGeneration,
        spans: const <TerminalGridOverlaySpan>[],
        isTruncated: true,
        maximumSpans: maximumSpans,
      );
    }
    final List<TerminalGridOverlaySpan> ordinary = <TerminalGridOverlaySpan>[];
    final List<TerminalGridOverlaySpan> selected = <TerminalGridOverlaySpan>[];
    var retainedSpanCount = 0;
    var isTruncated = result.isTruncated;
    var capReached = false;

    void addMatch(int matchIndex, TerminalGridOverlayKind kind) {
      if (capReached) return;
      final TerminalSelectionProjection? projection = viewport.projectSelection(
        result.matches[matchIndex].range,
      );
      if (projection == null) {
        isTruncated = true;
        return;
      }
      final List<TerminalGridOverlaySpan> destination =
          kind == TerminalGridOverlayKind.searchSelectedMatch
          ? selected
          : ordinary;
      for (final TerminalSelectionSpan span in projection.spans) {
        if (retainedSpanCount == maximumSpans) {
          capReached = true;
          isTruncated = true;
          return;
        }
        destination.add(
          TerminalGridOverlaySpan(
            kind: kind,
            row: span.row,
            startColumn: span.startColumn,
            endColumn: span.endColumn,
          ),
        );
        retainedSpanCount++;
      }
    }

    // Reserve visible geometry for the selected result before ordinary matches
    // consume the bounded projection budget. Canonical paint order is restored
    // by TerminalGridOverlayProjection after coalescing.
    if (selectedMatchIndex >= 0) {
      addMatch(selectedMatchIndex, TerminalGridOverlayKind.searchSelectedMatch);
    }
    for (int index = 0; index < result.matches.length && !capReached; index++) {
      if (index == selectedMatchIndex) continue;
      addMatch(index, TerminalGridOverlayKind.searchMatch);
    }

    return TerminalGridOverlayProjection(
      sourceGeneration: viewportGeneration,
      spans: <TerminalGridOverlaySpan>[
        ..._coalesceOverlaySpans(ordinary),
        ..._coalesceOverlaySpans(selected),
      ],
      isTruncated: isTruncated,
      maximumSpans: maximumSpans,
    );
  }
}

/// Monotonic, content-free owner for live search overlay publication.
final class TerminalSearchOverlayState {
  int _generation = 0;
  TerminalSearchResult? _result;
  int _selectedMatchIndex = -1;

  int get generation => _generation;
  int get selectedMatchIndex => _selectedMatchIndex;
  bool get isClear => _result == null;

  bool update({
    required int generation,
    required TerminalSearchResult? result,
    int selectedMatchIndex = -1,
  }) {
    RangeError.checkValueInInterval(
      generation,
      1,
      0x7fffffffffffffff,
      'generation',
    );
    if (generation < _generation) {
      throw StateError('search overlay generation regressed');
    }
    if (result == null && selectedMatchIndex != -1) {
      throw ArgumentError(
        'cleared search overlay cannot retain a selected match index',
      );
    }
    if (result != null &&
        (selectedMatchIndex < -1 ||
            selectedMatchIndex >= result.matches.length)) {
      throw RangeError.range(
        selectedMatchIndex,
        -1,
        result.matches.isEmpty ? -1 : result.matches.length - 1,
        'selectedMatchIndex',
      );
    }
    if (generation == _generation) {
      if (!identical(result, _result) ||
          selectedMatchIndex != _selectedMatchIndex) {
        throw StateError('search overlay generation has conflicting state');
      }
      return false;
    }
    _generation = generation;
    _result = result;
    _selectedMatchIndex = selectedMatchIndex;
    return true;
  }

  TerminalGridOverlayProjection? project(TerminalViewport viewport) {
    final TerminalSearchResult? result = _result;
    return result == null
        ? null
        : TerminalSearchOverlayProjector.project(
            viewport: viewport,
            result: result,
            selectedMatchIndex: _selectedMatchIndex,
          );
  }
}

List<TerminalGridOverlaySpan> _coalesceOverlaySpans(
  List<TerminalGridOverlaySpan> source,
) {
  if (source.length < 2) return source;
  source.sort((TerminalGridOverlaySpan left, TerminalGridOverlaySpan right) {
    int result = left.row.compareTo(right.row);
    if (result != 0) return result;
    result = left.startColumn.compareTo(right.startColumn);
    if (result != 0) return result;
    return left.endColumn.compareTo(right.endColumn);
  });
  final List<TerminalGridOverlaySpan> result = <TerminalGridOverlaySpan>[];
  for (final TerminalGridOverlaySpan span in source) {
    if (result.isEmpty) {
      result.add(span);
      continue;
    }
    final TerminalGridOverlaySpan previous = result.last;
    if (previous.kind == span.kind &&
        previous.row == span.row &&
        span.startColumn <= previous.endColumn) {
      if (span.endColumn > previous.endColumn) {
        result[result.length - 1] = TerminalGridOverlaySpan(
          kind: previous.kind,
          row: previous.row,
          startColumn: previous.startColumn,
          endColumn: span.endColumn,
        );
      }
      continue;
    }
    result.add(span);
  }
  return result;
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
