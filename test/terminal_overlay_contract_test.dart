import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalOverlayContractTests();

void runTerminalOverlayContractTests() {
  _testOverlayGeometryIsBoundedImmutableAndCanonical();
  _testOverlayGeometryRejectsInvalidAndExcessInput();
  _testSearchProjectionCoalescesAndPrioritizesSelection();
  _testSearchProjectionDropsUnavailableAnchors();
  _testSearchOverlayStateIsMonotonicAndContentFree();
  _testDisplayP3ColorConversionVectorsAndAlpha();
  _testDisplayP3BufferConversionIsBoundedAndCopied();
}

void _testSearchOverlayStateIsMonotonicAndContentFree() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 4);
  VtParser(sink: TerminalScreenParserSink.forScreenSet(screens))
      .parse(Uint8List.fromList('find'.codeUnits));
  final TerminalSearchResult result = screens.viewport.search('in')!;
  final TerminalSearchOverlayState state = TerminalSearchOverlayState();
  _expect(
    state.update(generation: 1, result: result, selectedMatchIndex: 0) &&
        state.generation == 1 &&
        state.selectedMatchIndex == 0 &&
        !state.isClear &&
        state.project(screens.viewport)!.spanCount == 1,
    'live search state publishes one generation without retaining query text',
  );
  _expect(
    !state.update(generation: 1, result: result, selectedMatchIndex: 0),
    'an identical live search generation is idempotent',
  );
  _expectFailure(
    () => state.update(generation: 1, result: null),
    'conflicting state cannot reuse a live search generation',
  );
  _expectFailure(
    () => state.update(generation: 0, result: result, selectedMatchIndex: 0),
    'live search generation cannot regress',
  );
  _expectFailure(
    () => state.update(generation: 2, result: result, selectedMatchIndex: 1),
    'invalid selected index fails before live search state changes',
  );
  _expect(
    state.generation == 1 &&
        state.update(generation: 2, result: null) &&
        state.generation == 2 &&
        state.selectedMatchIndex == -1 &&
        state.isClear &&
        state.project(screens.viewport) == null,
    'a newer generation clears all projected search state',
  );
}

void _testSearchProjectionCoalescesAndPrioritizesSelection() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 5);
  VtParser(sink: TerminalScreenParserSink.forScreenSet(screens))
      .parse(Uint8List.fromList('aaaaa'.codeUnits));
  final TerminalSearchResult result = screens.viewport.search('aa')!;
  final TerminalGridOverlayProjection projection =
      TerminalSearchOverlayProjector.project(
        viewport: screens.viewport,
        result: result,
        selectedMatchIndex: 2,
      );
  _expect(
    result.matches.length == 4 &&
        projection.sourceGeneration == screens.viewport.generation &&
        projection.spans.length == 2 &&
        projection.spans[0] ==
            TerminalGridOverlaySpan(
              kind: TerminalGridOverlayKind.searchMatch,
              row: 0,
              startColumn: 0,
              endColumn: 5,
            ) &&
        projection.spans[1] ==
            TerminalGridOverlaySpan(
              kind: TerminalGridOverlayKind.searchSelectedMatch,
              row: 0,
              startColumn: 2,
              endColumn: 4,
            ) &&
        projection.cellCount == 7 &&
        !projection.isTruncated,
    'overlapping matches coalesce by kind and selected paint remains last',
  );

  final TerminalGridOverlayProjection capped =
      TerminalSearchOverlayProjector.project(
        viewport: screens.viewport,
        result: result,
        selectedMatchIndex: 2,
        maximumSpans: 1,
      );
  _expect(
    capped.spans.length == 1 &&
        capped.spans.single.kind ==
            TerminalGridOverlayKind.searchSelectedMatch &&
        capped.isTruncated,
    'selected search geometry is reserved before ordinary cap pressure',
  );
  _expectFailure(
    () => TerminalSearchOverlayProjector.project(
      viewport: screens.viewport,
      result: result,
      selectedMatchIndex: result.matches.length,
    ),
    'invalid selected search index fails before projection',
  );
}

void _testSearchProjectionDropsUnavailableAnchors() {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: 1,
    columns: 2,
    scrollback: TerminalScrollback(maxLines: 2, maxBytes: 1, pageRows: 1),
  );
  VtParser(sink: TerminalScreenParserSink.forScreenSet(screens))
      .parse(Uint8List.fromList('AB'.codeUnits));
  final TerminalSearchResult result = screens.viewport.search('AB')!;
  screens.primary.printScalar(0x43);
  final TerminalGridOverlayProjection projection =
      TerminalSearchOverlayProjector.project(
        viewport: screens.viewport,
        result: result,
        selectedMatchIndex: 0,
      );
  _expect(
    result.matches.length == 1 &&
        projection.isEmpty &&
        projection.isTruncated &&
        projection.sourceGeneration == screens.viewport.generation,
    'evicted stable anchors are dropped and reported without stale geometry',
  );
}

void _testOverlayGeometryIsBoundedImmutableAndCanonical() {
  final List<TerminalGridOverlaySpan> source = <TerminalGridOverlaySpan>[
    TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.inspectorSemanticInput,
      row: 2,
      startColumn: 4,
      endColumn: 6,
    ),
    TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.searchSelectedMatch,
      row: 1,
      startColumn: 2,
      endColumn: 5,
    ),
    TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.searchMatch,
      row: 3,
      startColumn: 0,
      endColumn: 1,
    ),
    TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.searchMatch,
      row: 1,
      startColumn: 8,
      endColumn: 10,
    ),
  ];
  final TerminalGridOverlayProjection projection =
      TerminalGridOverlayProjection(
        sourceGeneration: 7,
        spans: source,
        isTruncated: true,
      );
  source.clear();

  _expect(
    projection.sourceGeneration == 7 &&
        projection.spanCount == 4 &&
        projection.cellCount == 8 &&
        projection.isTruncated &&
        projection.spans[0].kind == TerminalGridOverlayKind.searchMatch &&
        projection.spans[0].row == 1 &&
        projection.spans[1].kind == TerminalGridOverlayKind.searchMatch &&
        projection.spans[2].kind ==
            TerminalGridOverlayKind.searchSelectedMatch &&
        projection.spans[3].kind ==
            TerminalGridOverlayKind.inspectorSemanticInput,
    'overlay spans are copied and sorted by explicit paint precedence',
  );
  _expectFailure(
    () => projection.spans.add(
      TerminalGridOverlaySpan(
        kind: TerminalGridOverlayKind.searchMatch,
        row: 0,
        startColumn: 0,
        endColumn: 1,
      ),
    ),
    'overlay projection is immutable',
  );
}

void _testOverlayGeometryRejectsInvalidAndExcessInput() {
  _expectFailure(
    () => TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.searchMatch,
      row: -1,
      startColumn: 0,
      endColumn: 1,
    ),
    'negative overlay row is rejected',
  );
  _expectFailure(
    () => TerminalGridOverlaySpan(
      kind: TerminalGridOverlayKind.searchMatch,
      row: 0,
      startColumn: 1,
      endColumn: 1,
    ),
    'empty overlay span is rejected',
  );
  _expectFailure(
    () => TerminalGridOverlayProjection(
      sourceGeneration: 0,
      spans: const <TerminalGridOverlaySpan>[],
    ),
    'zero overlay source generation is rejected',
  );
  _expectFailure(
    () => TerminalGridOverlayProjection(
      sourceGeneration: 1,
      maximumSpans: 2,
      spans: <TerminalGridOverlaySpan>[
        for (int index = 0; index < 3; index++)
          TerminalGridOverlaySpan(
            kind: TerminalGridOverlayKind.searchMatch,
            row: index,
            startColumn: 0,
            endColumn: 1,
          ),
      ],
    ),
    'aggregate overlay span cap is enforced before publication',
  );
}

void _testDisplayP3ColorConversionVectorsAndAlpha() {
  _expect(
    const TerminalRenderColor.srgb(0x12345678).canonicalSrgbRgba == 0x12345678,
    'canonical sRGB input remains byte exact',
  );
  _expect(
    const TerminalRenderColor.displayP3(0x8080807f).canonicalSrgbRgba ==
        0x8080807f,
    'Display P3 neutral gray preserves encoded components and alpha',
  );
  _expect(
    const TerminalRenderColor.displayP3(0xff80005a).canonicalSrgbRgba ==
        0xff77005a,
    'Display P3 orange converts to the reviewed clipped sRGB vector',
  );
  _expect(
    const TerminalRenderColor.displayP3(0x00ff00a5).canonicalSrgbRgba ==
        0x00ff00a5,
    'out-of-sRGB P3 green clips without changing alpha',
  );
}

void _testDisplayP3BufferConversionIsBoundedAndCopied() {
  final List<int> source = <int>[
    0xff,
    0x80,
    0x00,
    0x11,
    0x80,
    0x80,
    0x80,
    0x22,
  ];
  final List<int> converted =
      TerminalRenderColorConverter.displayP3ToSrgbBuffer(
        source,
        maximumBytes: 8,
      );
  source.fillRange(0, source.length, 0);
  _expect(
    _bytesEqual(converted, const <int>[
      0xff,
      0x77,
      0x00,
      0x11,
      0x80,
      0x80,
      0x80,
      0x22,
    ]),
    'P3 buffer conversion owns output and preserves each straight alpha byte',
  );
  _expectFailure(
    () => TerminalRenderColorConverter.displayP3ToSrgbBuffer(const <int>[
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ], maximumBytes: 4),
    'P3 buffer byte cap is enforced before conversion',
  );
  _expectFailure(
    () => TerminalRenderColorConverter.displayP3ToSrgbBuffer(const <int>[
      0,
      0,
      0,
    ]),
    'incomplete P3 pixels are rejected',
  );
  _expectFailure(
    () => TerminalRenderColorConverter.displayP3ToSrgbBuffer(const <int>[
      0,
      0,
      256,
      255,
    ]),
    'non-byte P3 components are rejected',
  );
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expectFailure(void Function() action, String message) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
