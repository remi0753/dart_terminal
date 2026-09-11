part of 'terminal_screen_set.dart';

/// One copied RGBA8 resource in an immutable Kitty viewport snapshot.
final class TerminalKittyViewportImage {
  TerminalKittyViewportImage._({
    required this.imageId,
    required this.resourceGeneration,
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : _rgba = rgba;

  final int imageId;
  final int resourceGeneration;
  final int width;
  final int height;
  final Uint8List _rgba;

  int get byteLength => _rgba.length;

  Uint8List copyRgba() => Uint8List.fromList(_rgba);
}

/// One immutable placement projected into viewport-relative logical pixels.
final class TerminalKittyViewportPlacement {
  const TerminalKittyViewportPlacement({
    required this.placementGeneration,
    required this.imageId,
    required this.imageResourceGeneration,
    required this.placementId,
    required this.gridColumn,
    required this.gridRow,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.requestedColumns,
    required this.requestedRows,
    required this.fixedPixelWidth,
    required this.fixedPixelHeight,
    required this.source,
    required this.destinationX,
    required this.destinationY,
    required this.destinationWidth,
    required this.destinationHeight,
    required this.z,
  });

  final int placementGeneration;
  final int imageId;
  final int imageResourceGeneration;
  final int placementId;
  final int gridColumn;
  final int gridRow;
  final int cellOffsetX;
  final int cellOffsetY;
  final int requestedColumns;
  final int requestedRows;
  final int? fixedPixelWidth;
  final int? fixedPixelHeight;
  final TerminalKittyImageSourceRect source;
  final int destinationX;
  final int destinationY;
  final int destinationWidth;
  final int destinationHeight;
  final int z;
}

/// Generation-pinned, copied image state for one navigated terminal viewport.
final class TerminalKittyViewportSnapshot {
  const TerminalKittyViewportSnapshot._({
    required this.screenKind,
    required this.viewportGeneration,
    required this.storeGeneration,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.cellWidth,
    required this.cellHeight,
    required this.images,
    required this.placements,
  });

  final TerminalScreenKind screenKind;
  final int viewportGeneration;
  final int storeGeneration;
  final int viewportWidth;
  final int viewportHeight;
  final int cellWidth;
  final int cellHeight;
  final List<TerminalKittyViewportImage> images;
  final List<TerminalKittyViewportPlacement> placements;

  factory TerminalKittyViewportSnapshot.capture(TerminalScreenSet screens) {
    final TerminalViewport viewport = screens.viewport;
    final int viewportGeneration = viewport.generation;
    final TerminalScreenKind kind = screens.activeKind;
    final TerminalScreen screen = screens.activeScreen;
    final TerminalKittyImageStore store = screens.activeKittyImages;
    final int storeGeneration = store.stateGeneration;
    final ({int width, int height})? cell = screens.logicalCellSize;
    if (cell == null) {
      return TerminalKittyViewportSnapshot._(
        screenKind: kind,
        viewportGeneration: viewportGeneration,
        storeGeneration: storeGeneration,
        viewportWidth: 0,
        viewportHeight: 0,
        cellWidth: 0,
        cellHeight: 0,
        images: const <TerminalKittyViewportImage>[],
        placements: const <TerminalKittyViewportPlacement>[],
      );
    }
    final int viewportWidth = screen.columns * cell.width;
    final int viewportHeight = screen.rows * cell.height;
    final Map<int, TerminalKittyViewportImage> images =
        <int, TerminalKittyViewportImage>{};
    final List<TerminalKittyViewportPlacement> placements =
        <TerminalKittyViewportPlacement>[];
    for (final TerminalKittyImagePlacement placement
        in store.placementSnapshot()) {
      final TerminalKittyImage? image = store.imageById(placement.imageId);
      if (image == null ||
          image.resourceGeneration != placement.imageResourceGeneration) {
        continue;
      }
      final TerminalViewportPosition? position = viewport
          .projectedCellPositionOf(
            TerminalLogicalAnchor(
              screenKind: kind,
              logicalLineId: placement.logicalLineId,
              logicalLineEpoch: placement.logicalLineEpoch,
              cellOffset: placement.logicalCellOffset,
            ),
          );
      if (position == null) continue;
      final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
        image: image,
        cellWidth: cell.width,
        cellHeight: cell.height,
      );
      final int destinationX =
          position.column * cell.width + geometry.cellOffsetX;
      final int destinationY =
          position.row * cell.height + geometry.cellOffsetY;
      if (geometry.source.width <= 0 ||
          geometry.source.height <= 0 ||
          geometry.pixelWidth <= 0 ||
          geometry.pixelHeight <= 0 ||
          destinationX >= viewportWidth ||
          destinationX + geometry.pixelWidth <= 0 ||
          destinationY >= viewportHeight ||
          destinationY + geometry.pixelHeight <= 0) {
        continue;
      }
      images.putIfAbsent(
        image.id,
        () => TerminalKittyViewportImage._(
          imageId: image.id,
          resourceGeneration: image.resourceGeneration,
          width: image.width,
          height: image.height,
          rgba: image.copyRgba(),
        ),
      );
      placements.add(
        TerminalKittyViewportPlacement(
          placementGeneration: placement.placementGeneration,
          imageId: image.id,
          imageResourceGeneration: image.resourceGeneration,
          placementId: placement.placementId,
          gridColumn: position.column,
          gridRow: position.row,
          cellOffsetX: geometry.cellOffsetX,
          cellOffsetY: geometry.cellOffsetY,
          requestedColumns: placement.requestedColumns,
          requestedRows: placement.requestedRows,
          fixedPixelWidth: placement.fixedPixelWidth,
          fixedPixelHeight: placement.fixedPixelHeight,
          source: geometry.source,
          destinationX: destinationX,
          destinationY: destinationY,
          destinationWidth: geometry.pixelWidth,
          destinationHeight: geometry.pixelHeight,
          z: placement.z,
        ),
      );
    }
    placements.sort((
      TerminalKittyViewportPlacement left,
      TerminalKittyViewportPlacement right,
    ) {
      final int zOrder = left.z.compareTo(right.z);
      return zOrder != 0
          ? zOrder
          : left.placementGeneration.compareTo(right.placementGeneration);
    });
    final List<TerminalKittyViewportImage> orderedImages =
        images.values.toList()..sort(
          (TerminalKittyViewportImage left, TerminalKittyViewportImage right) =>
              left.imageId.compareTo(right.imageId),
        );
    if (store.stateGeneration != storeGeneration ||
        viewport.generation != viewportGeneration ||
        screens.activeKind != kind) {
      throw StateError('Kitty viewport state changed during capture');
    }
    return TerminalKittyViewportSnapshot._(
      screenKind: kind,
      viewportGeneration: viewportGeneration,
      storeGeneration: storeGeneration,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      cellWidth: cell.width,
      cellHeight: cell.height,
      images: List<TerminalKittyViewportImage>.unmodifiable(orderedImages),
      placements: List<TerminalKittyViewportPlacement>.unmodifiable(placements),
    );
  }
}
