import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'support/kitty_reference_golden_fixture.dart';

void main() => runTerminalKittyReferenceCompositorTests();

void runTerminalKittyReferenceCompositorTests() {
  _testThreeBandBoundariesAndStableGenerationOrder();
  _testThreeBandPixelsAtOneAndTwoTimesScale();
  _testLayeringSamplingClippingAndGolden();
  _testAnimationFrameSelectionAndGolden();
  _testMissingGeometryFailsClosed();
}

void _testThreeBandBoundariesAndStableGenerationOrder() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 5);
  _seedViewportColumns(screens, 'abcde');
  screens.updateLogicalCellSize(width: 1, height: 1);
  for (int imageId = 1; imageId <= 5; imageId++) {
    _storeViewportImage(
      screens,
      imageId: imageId,
      width: 1,
      height: 1,
      rgba: const <int>[255, 0, 0, 255],
    );
  }
  _placeViewportImage(
    screens,
    imageId: 1,
    row: 0,
    column: 0,
    columns: 1,
    rows: 1,
    z: -0x40000001,
  );
  _placeViewportImage(
    screens,
    imageId: 2,
    row: 0,
    column: 1,
    columns: 1,
    rows: 1,
    z: -0x40000000,
  );
  _placeViewportImage(
    screens,
    imageId: 3,
    row: 0,
    column: 2,
    columns: 1,
    rows: 1,
    z: -1,
  );
  _placeViewportImage(
    screens,
    imageId: 4,
    row: 0,
    column: 3,
    columns: 1,
    rows: 1,
    z: 0,
  );
  _placeViewportImage(
    screens,
    imageId: 5,
    row: 0,
    column: 4,
    columns: 1,
    rows: 1,
    z: -1,
  );

  final List<TerminalKittyViewportPlacement> placements = screens
      .captureKittyImageViewport()
      .placements;
  _expect(
    placements
            .map((TerminalKittyViewportPlacement value) => value.imageId)
            .join(',') ==
        '1,2,3,5,4',
    'viewport projection sorts z first and equal z by placement generation',
  );
  _expect(
    placements[0].layer == TerminalKittyImageLayer.belowBackground &&
        placements[1].layer == TerminalKittyImageLayer.belowText &&
        placements[2].layer == TerminalKittyImageLayer.belowText &&
        placements[3].layer == TerminalKittyImageLayer.belowText &&
        placements[4].layer == TerminalKittyImageLayer.aboveText,
    'the exact extreme-negative boundary selects three stable paint bands',
  );
}

void _testThreeBandPixelsAtOneAndTwoTimesScale() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 3);
  _seedViewportColumns(screens, 'abc');
  screens.updateLogicalCellSize(width: 1, height: 1);
  for (int imageId = 1; imageId <= 3; imageId++) {
    _storeViewportImage(
      screens,
      imageId: imageId,
      width: 1,
      height: 1,
      rgba: const <int>[255, 0, 0, 255],
    );
  }
  _placeViewportImage(
    screens,
    imageId: 1,
    row: 0,
    column: 0,
    columns: 1,
    rows: 1,
    z: -0x40000001,
  );
  _placeViewportImage(
    screens,
    imageId: 2,
    row: 0,
    column: 1,
    columns: 1,
    rows: 1,
    z: -1,
  );
  _placeViewportImage(
    screens,
    imageId: 3,
    row: 0,
    column: 2,
    columns: 1,
    rows: 1,
    z: 0,
  );
  const List<TerminalReferencePrimitive> text = <TerminalReferencePrimitive>[
    TerminalReferenceSolid(
      layer: TerminalReferenceLayer.cellBackground,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      color: TerminalReferenceColor(0x0000ffff),
    ),
    TerminalReferenceSolid(
      layer: TerminalReferenceLayer.glyph,
      x: 1,
      y: 0,
      width: 2,
      height: 1,
      color: TerminalReferenceColor(0x00ff00ff),
    ),
  ];
  final TerminalKittyViewportSnapshot snapshot = screens
      .captureKittyImageViewport();
  for (final int scale in <int>[1, 2]) {
    final TerminalReferenceImage rendered =
        TerminalKittyReferenceCompositor.render(
          snapshot: snapshot,
          scale: scale,
          background: const TerminalReferenceColor(0x101010ff),
          textPrimitives: text,
        );
    final List<int> observed = <int>[
      rendered.pixelAt(0, 0),
      rendered.pixelAt(scale, 0),
      rendered.pixelAt(2 * scale, 0),
    ];
    _expect(
      observed[0] == 0x0000ffff &&
          observed[1] == 0x00ff00ff &&
          observed[2] == 0xff0000ff,
      'CPU three-band image order is exact at ${scale}x: '
      '${observed.map((int value) => value.toRadixString(16)).join(',')}',
    );
  }
}

void _testAnimationFrameSelectionAndGolden() {
  for (final int scale in <int>[1, 2]) {
    final TerminalReferenceImage rendered =
        createKittyAnimationReferenceGoldenFixture(scale: scale);
    _expect(
      rendered.pixelAt(0, 0) == 0x0000ffff &&
          rendered.pixelAt(scale, 0) == 0xffff00ff,
      'the CPU oracle projects the selected animation frame at ${scale}x',
    );
    final TerminalReferenceImage root =
        createKittyAnimationReferenceGoldenFixture(
          scale: scale,
          currentFrame: 1,
        );
    _expect(
      root.pixelAt(0, 0) == 0xff0000ff && root.pixelAt(scale, 0) == 0x00ff00ff,
      'switching to the root restores its immutable pixels at ${scale}x',
    );
    final File fixture = File(
      'test/goldens/kitty/animation-frame-${scale}x.dtgi',
    );
    _expect(
      fixture.existsSync(),
      'checked-in ${scale}x Kitty animation golden exists',
    );
    final Uint8List expectedBytes = fixture.readAsBytesSync();
    _expect(
      _bytesEqual(expectedBytes, TerminalGoldenImageCodec.encode(rendered)),
      'checked-in ${scale}x Kitty animation golden is byte exact',
    );
    TerminalGoldenImageComparator.compare(
      TerminalGoldenImageCodec.decode(expectedBytes),
      rendered,
    ).requireMatch('Kitty animation frame ${scale}x golden');
  }
}

void _testLayeringSamplingClippingAndGolden() {
  for (final int scale in <int>[1, 2]) {
    final TerminalReferenceImage rendered = createKittyReferenceGoldenFixture(
      scale: scale,
    );
    _expect(
      rendered.pixelAt(0, 0) == 0x0000ffff &&
          rendered.pixelAt(scale, 0) == 0xffffffff,
      'negative viewport y clips the first source row at ${scale}x',
    );
    _expect(
      rendered.pixelAt(scale, scale) == 0xffffffff &&
          rendered.pixelAt(2 * scale, scale) == 0x00ff00ff,
      'below-text scaling is covered by glyphs but not blank cells at ${scale}x',
    );
    _expect(
      rendered.pixelAt(scale, 2 * scale) == 0xffff00ff &&
          rendered.pixelAt(0, 2 * scale) == 0x00ffffff,
      'nonnegative image z covers glyphs while cursor remains above at ${scale}x',
    );
    final File fixture = File(
      'test/goldens/kitty/static-placement-${scale}x.dtgi',
    );
    _expect(fixture.existsSync(), 'checked-in ${scale}x Kitty golden exists');
    final Uint8List expectedBytes = fixture.readAsBytesSync();
    final Uint8List actualBytes = TerminalGoldenImageCodec.encode(rendered);
    _expect(
      _bytesEqual(expectedBytes, actualBytes),
      'checked-in ${scale}x Kitty golden is byte exact',
    );
    TerminalGoldenImageComparator.compare(
      TerminalGoldenImageCodec.decode(expectedBytes),
      rendered,
    ).requireMatch('Kitty static placement ${scale}x golden');
  }
}

void _testMissingGeometryFailsClosed() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 1);
  _expectThrows(
    () => TerminalKittyReferenceCompositor.render(
      snapshot: screens.captureKittyImageViewport(),
    ),
    'a viewport without logical cell metrics is not guessed',
  );
}

void _storeViewportImage(
  TerminalScreenSet screens, {
  required int imageId,
  required int width,
  required int height,
  required List<int> rgba,
}) {
  final result = screens.primaryKittyImages.store(
    imageId: imageId,
    imageNumber: 0,
    width: width,
    height: height,
    transient: false,
    rgba: Uint8List.fromList(rgba),
  );
  _expect(result.image != null, 'three-band fixture stores image $imageId');
}

void _seedViewportColumns(TerminalScreenSet screens, String text) {
  VtParser(sink: TerminalScreenParserSink.forScreenSet(screens))
      .parse(Uint8List.fromList(text.codeUnits));
}

void _placeViewportImage(
  TerminalScreenSet screens, {
  required int imageId,
  required int row,
  required int column,
  required int columns,
  required int rows,
  required int z,
}) {
  final TerminalLogicalAnchor anchor = screens.viewport.anchorAtScreenCell(
    TerminalScreenKind.primary,
    row,
    column,
  );
  final result = screens.primaryKittyImages.place(
    imageId: imageId,
    imageNumber: 0,
    placementId: imageId,
    logicalLineId: anchor.logicalLineId,
    logicalLineEpoch: anchor.logicalLineEpoch,
    logicalCellOffset: anchor.cellOffset,
    sourceX: 0,
    sourceY: 0,
    sourceWidth: 0,
    sourceHeight: 0,
    cellOffsetX: 0,
    cellOffsetY: 0,
    columns: columns,
    rows: rows,
    z: z,
  );
  _expect(result.placement != null, 'three-band fixture places image $imageId');
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Kitty reference compositor failed: $description');
  }
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('Kitty reference compositor failed: $description');
}
