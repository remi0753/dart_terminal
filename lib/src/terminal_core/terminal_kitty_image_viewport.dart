part of 'terminal_screen_set.dart';

/// One copied RGBA8 resource in an immutable Kitty viewport snapshot.
final class TerminalKittyViewportImage {
  TerminalKittyViewportImage._({
    required this.imageId,
    required this.resourceGeneration,
    required this.contentGeneration,
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : _rgba = rgba;

  final int imageId;
  final int resourceGeneration;
  final int contentGeneration;
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

  /// Captures only the IDs with a placement intersecting the current viewport.
  /// No image pixel buffer is copied for this animation scheduling query.
  static Set<int> captureVisibleImageIds(TerminalScreenSet screens) {
    final TerminalViewport viewport = screens.viewport;
    final int viewportGeneration = viewport.generation;
    final TerminalScreenKind kind = screens.activeKind;
    final TerminalScreen screen = screens.activeScreen;
    final TerminalKittyImageStore store = screens.activeKittyImages;
    final int storeGeneration = store.stateGeneration;
    final ({int width, int height})? cell = screens.logicalCellSize;
    if (cell == null) return const <int>{};
    final int viewportWidth = screen.columns * cell.width;
    final int viewportHeight = screen.rows * cell.height;
    final Set<int> result = <int>{};
    for (final TerminalKittyImagePlacement placement
        in store.placementSnapshot()) {
      final TerminalKittyImage? image = store.imageById(placement.imageId);
      if (image == null ||
          image.resourceGeneration != placement.imageResourceGeneration) {
        continue;
      }
      final _TerminalKittyProjectedPlacement? projected =
          _projectKittyPlacement(
            viewport: viewport,
            kind: kind,
            image: image,
            placement: placement,
            cellWidth: cell.width,
            cellHeight: cell.height,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
      if (projected != null) result.add(image.id);
    }
    _requireUnchanged(
      screens: screens,
      store: store,
      viewport: viewport,
      kind: kind,
      storeGeneration: storeGeneration,
      viewportGeneration: viewportGeneration,
    );
    return Set<int>.unmodifiable(result);
  }

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
      final _TerminalKittyProjectedPlacement? projected =
          _projectKittyPlacement(
            viewport: viewport,
            kind: kind,
            image: image,
            placement: placement,
            cellWidth: cell.width,
            cellHeight: cell.height,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
          );
      if (projected == null) continue;
      images.putIfAbsent(
        image.id,
        () => TerminalKittyViewportImage._(
          imageId: image.id,
          resourceGeneration: image.resourceGeneration,
          contentGeneration: image.contentGeneration,
          width: image.width,
          height: image.height,
          rgba: image.copyCurrentRgba(),
        ),
      );
      placements.add(
        TerminalKittyViewportPlacement(
          placementGeneration: placement.placementGeneration,
          imageId: image.id,
          imageResourceGeneration: image.resourceGeneration,
          placementId: placement.placementId,
          gridColumn: projected.position.column,
          gridRow: projected.position.row,
          cellOffsetX: projected.geometry.cellOffsetX,
          cellOffsetY: projected.geometry.cellOffsetY,
          requestedColumns: placement.requestedColumns,
          requestedRows: placement.requestedRows,
          fixedPixelWidth: placement.fixedPixelWidth,
          fixedPixelHeight: placement.fixedPixelHeight,
          source: projected.geometry.source,
          destinationX: projected.destinationX,
          destinationY: projected.destinationY,
          destinationWidth: projected.geometry.pixelWidth,
          destinationHeight: projected.geometry.pixelHeight,
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
    _requireUnchanged(
      screens: screens,
      store: store,
      viewport: viewport,
      kind: kind,
      storeGeneration: storeGeneration,
      viewportGeneration: viewportGeneration,
    );
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

  static void _requireUnchanged({
    required TerminalScreenSet screens,
    required TerminalKittyImageStore store,
    required TerminalViewport viewport,
    required TerminalScreenKind kind,
    required int storeGeneration,
    required int viewportGeneration,
  }) {
    if (store.stateGeneration != storeGeneration ||
        viewport.generation != viewportGeneration ||
        screens.activeKind != kind) {
      throw StateError('Kitty viewport state changed during capture');
    }
  }
}

final class _TerminalKittyProjectedPlacement {
  const _TerminalKittyProjectedPlacement({
    required this.position,
    required this.geometry,
    required this.destinationX,
    required this.destinationY,
  });

  final TerminalViewportPosition position;
  final TerminalKittyImagePlacementGeometry geometry;
  final int destinationX;
  final int destinationY;
}

_TerminalKittyProjectedPlacement? _projectKittyPlacement({
  required TerminalViewport viewport,
  required TerminalScreenKind kind,
  required TerminalKittyImage image,
  required TerminalKittyImagePlacement placement,
  required int cellWidth,
  required int cellHeight,
  required int viewportWidth,
  required int viewportHeight,
}) {
  final TerminalViewportPosition? position = viewport.projectedCellPositionOf(
    TerminalLogicalAnchor(
      screenKind: kind,
      logicalLineId: placement.logicalLineId,
      logicalLineEpoch: placement.logicalLineEpoch,
      cellOffset: placement.logicalCellOffset,
    ),
  );
  if (position == null) return null;
  final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
    image: image,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
  final int destinationX = position.column * cellWidth + geometry.cellOffsetX;
  final int destinationY = position.row * cellHeight + geometry.cellOffsetY;
  if (geometry.source.width <= 0 ||
      geometry.source.height <= 0 ||
      geometry.pixelWidth <= 0 ||
      geometry.pixelHeight <= 0 ||
      destinationX >= viewportWidth ||
      destinationX + geometry.pixelWidth <= 0 ||
      destinationY >= viewportHeight ||
      destinationY + geometry.pixelHeight <= 0) {
    return null;
  }
  return _TerminalKittyProjectedPlacement(
    position: position,
    geometry: geometry,
    destinationX: destinationX,
    destinationY: destinationY,
  );
}
