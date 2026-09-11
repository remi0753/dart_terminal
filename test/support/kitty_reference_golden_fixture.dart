import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

TerminalReferenceImage createKittyReferenceGoldenFixture({required int scale}) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 4);
  screens.updateLogicalCellSize(width: 1, height: 1);

  _storeImage(
    screens,
    imageId: 103,
    width: 2,
    height: 2,
    rgba: const <int>[
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ],
  );
  _placeImage(
    screens,
    imageId: 103,
    row: 0,
    column: 0,
    columns: 2,
    rows: 2,
    z: 0,
  );
  screens.primary.scrollUp(1);

  _storeImage(
    screens,
    imageId: 101,
    width: 2,
    height: 1,
    rgba: const <int>[255, 0, 0, 255, 0, 255, 0, 255],
  );
  _placeImage(
    screens,
    imageId: 101,
    row: 1,
    column: 0,
    columns: 4,
    rows: 1,
    z: -2,
  );

  _storeImage(
    screens,
    imageId: 102,
    width: 2,
    height: 1,
    rgba: const <int>[255, 255, 0, 255, 255, 0, 255, 128],
  );
  _placeImage(
    screens,
    imageId: 102,
    row: 2,
    column: 1,
    columns: 3,
    rows: 1,
    z: 3,
  );

  return TerminalKittyReferenceCompositor.render(
    snapshot: screens.captureKittyImageViewport(),
    scale: scale,
    background: const TerminalReferenceColor(0x101820ff),
    textPrimitives: const <TerminalReferencePrimitive>[
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.cellBackground,
        x: 0,
        y: 0,
        width: 4,
        height: 3,
        color: TerminalReferenceColor(0x202830ff),
      ),
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.selection,
        x: 0,
        y: 1,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xffff0080),
      ),
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.glyph,
        x: 1,
        y: 1,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0xffffffff),
      ),
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.glyph,
        x: 1,
        y: 2,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0x00ffffff),
      ),
      TerminalReferenceSolid(
        layer: TerminalReferenceLayer.cursor,
        x: 0,
        y: 2,
        width: 1,
        height: 1,
        color: TerminalReferenceColor(0x00ffffff),
      ),
    ],
  );
}

void _storeImage(
  TerminalScreenSet screens, {
  required int imageId,
  required int width,
  required int height,
  required List<int> rgba,
}) {
  screens.primaryKittyImages.store(
    imageId: imageId,
    imageNumber: 0,
    width: width,
    height: height,
    transient: false,
    rgba: Uint8List.fromList(rgba),
  );
}

void _placeImage(
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
  screens.primaryKittyImages.place(
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
}
