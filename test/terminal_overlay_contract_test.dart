import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalOverlayContractTests();

void runTerminalOverlayContractTests() {
  _testOverlayGeometryIsBoundedImmutableAndCanonical();
  _testOverlayGeometryRejectsInvalidAndExcessInput();
  _testDisplayP3ColorConversionVectorsAndAlpha();
  _testDisplayP3BufferConversionIsBoundedAndCopied();
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
