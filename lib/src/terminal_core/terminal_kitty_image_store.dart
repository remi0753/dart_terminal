import 'dart:collection';
import 'dart:typed_data';

import 'terminal_kitty_graphics.dart';

/// Fixed product ceilings for decoded Kitty image bytes retained per screen.
abstract final class TerminalKittyImageStoreLimits {
  static const int maximumImages = 64;
  static const int maximumPlacements = 256;
  static const int maximumRetainedBytes = 16 * 1024 * 1024;
  static const int maximumImageBytes = 1024 * 1024;
  static const int maximumPixels = maximumImageBytes ~/ 4;
  static const int maximumDimension = 4096;
}

/// One immutable canonical RGBA8 image owned by a terminal screen.
final class TerminalKittyImage {
  TerminalKittyImage._({
    required this.id,
    required this.number,
    required this.width,
    required this.height,
    required this.resourceGeneration,
    required this.transient,
    required Uint8List rgba,
  }) : _rgba = Uint8List.fromList(rgba);

  final int id;
  final int number;
  final int width;
  final int height;
  final int resourceGeneration;
  final bool transient;
  final Uint8List _rgba;

  int get byteLength => _rgba.length;

  Uint8List copyRgba() => Uint8List.fromList(_rgba);
}

/// One source rectangle after intersection with its immutable image.
final class TerminalKittyImageSourceRect {
  const TerminalKittyImageSourceRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

/// Pixel and grid geometry resolved for the current logical cell metrics.
final class TerminalKittyImagePlacementGeometry {
  const TerminalKittyImagePlacementGeometry({
    required this.source,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.columns,
    required this.rows,
  });

  final TerminalKittyImageSourceRect source;
  final int cellOffsetX;
  final int cellOffsetY;
  final int pixelWidth;
  final int pixelHeight;
  final int columns;
  final int rows;
}

/// Immutable logical placement tied to one decoded image generation.
final class TerminalKittyImagePlacement {
  const TerminalKittyImagePlacement._({
    required this.placementGeneration,
    required this.imageId,
    required this.imageResourceGeneration,
    required this.placementId,
    required this.logicalLineId,
    required this.logicalLineEpoch,
    required this.logicalCellOffset,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.requestedColumns,
    required this.requestedRows,
    required this.z,
  });

  final int placementGeneration;
  final int imageId;
  final int imageResourceGeneration;
  final int placementId;
  final int logicalLineId;
  final int logicalLineEpoch;
  final int logicalCellOffset;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int cellOffsetX;
  final int cellOffsetY;
  final int requestedColumns;
  final int requestedRows;
  final int z;

  TerminalKittyImageSourceRect sourceRect(TerminalKittyImage image) {
    _requireImageGeneration(image);
    final int x = sourceX.clamp(0, image.width);
    final int y = sourceY.clamp(0, image.height);
    return TerminalKittyImageSourceRect(
      x: x,
      y: y,
      width: (sourceWidth == 0 ? image.width : sourceWidth).clamp(
        0,
        image.width - x,
      ),
      height: (sourceHeight == 0 ? image.height : sourceHeight).clamp(
        0,
        image.height - y,
      ),
    );
  }

  TerminalKittyImagePlacementGeometry geometry({
    required TerminalKittyImage image,
    required int cellWidth,
    required int cellHeight,
  }) {
    _requireImageGeneration(image);
    if (cellWidth < 0 || cellHeight < 0) {
      throw ArgumentError('logical cell dimensions must not be negative');
    }
    final TerminalKittyImageSourceRect source = sourceRect(image);
    final int offsetX = cellWidth == 0
        ? 0
        : cellOffsetX.clamp(0, cellWidth - 1);
    final int offsetY = cellHeight == 0
        ? 0
        : cellOffsetY.clamp(0, cellHeight - 1);
    late final int pixelWidth;
    late final int pixelHeight;
    if (requestedColumns == 0 && requestedRows == 0) {
      pixelWidth = source.width;
      pixelHeight = source.height;
    } else if (requestedColumns != 0 && requestedRows != 0) {
      pixelWidth = (_saturatingProduct(cellWidth, requestedColumns) - offsetX)
          .clamp(0, 0xffffffff);
      pixelHeight = (_saturatingProduct(cellHeight, requestedRows) - offsetY)
          .clamp(0, 0xffffffff);
    } else if (requestedColumns != 0) {
      pixelWidth = (_saturatingProduct(cellWidth, requestedColumns) - offsetX)
          .clamp(0, 0xffffffff);
      pixelHeight = _scaleDimension(pixelWidth, source.height, source.width);
    } else {
      pixelHeight = (_saturatingProduct(cellHeight, requestedRows) - offsetY)
          .clamp(0, 0xffffffff);
      pixelWidth = _scaleDimension(pixelHeight, source.width, source.height);
    }
    final int columns = requestedColumns != 0 && requestedRows != 0
        ? requestedColumns
        : _ceilDivide(pixelWidth + offsetX, cellWidth);
    final int rows = requestedColumns != 0 && requestedRows != 0
        ? requestedRows
        : _ceilDivide(pixelHeight + offsetY, cellHeight);
    return TerminalKittyImagePlacementGeometry(
      source: source,
      cellOffsetX: offsetX,
      cellOffsetY: offsetY,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      columns: columns,
      rows: rows,
    );
  }

  void _requireImageGeneration(TerminalKittyImage image) {
    if (image.id != imageId ||
        image.resourceGeneration != imageResourceGeneration) {
      throw StateError('Kitty placement refers to a stale image generation');
    }
  }

  static int _saturatingProduct(int left, int right) {
    final int product = left * right;
    return product > 0xffffffff ? 0xffffffff : product;
  }

  static int _scaleDimension(int value, int numerator, int denominator) {
    if (denominator == 0) return 0;
    return ((value * numerator + denominator ~/ 2) ~/ denominator).clamp(
      0,
      0xffffffff,
    );
  }

  static int _ceilDivide(int value, int divisor) {
    if (value == 0 || divisor == 0) return 0;
    return (value + divisor - 1) ~/ divisor;
  }
}

final class TerminalKittyImagePlacementPosition {
  const TerminalKittyImagePlacementPosition({
    required this.row,
    required this.column,
  });

  final int row;
  final int column;
}

typedef TerminalKittyImagePlacementPositionResolver =
    TerminalKittyImagePlacementPosition? Function(
      TerminalKittyImagePlacement placement,
    );

enum TerminalKittyImagePlacementDisposition {
  stored,
  imageMissing,
  resourceLimit,
}

final class TerminalKittyImagePlacementResult {
  const TerminalKittyImagePlacementResult(
    this.disposition, {
    this.image,
    this.placement,
  });

  final TerminalKittyImagePlacementDisposition disposition;
  final TerminalKittyImage? image;
  final TerminalKittyImagePlacement? placement;
}

final class TerminalKittyImageDeleteResult {
  const TerminalKittyImageDeleteResult({
    required this.deletedPlacements,
    required this.deletedImages,
  });

  final int deletedPlacements;
  final int deletedImages;
  bool get mutated => deletedPlacements != 0 || deletedImages != 0;
}

enum TerminalKittyImageStoreDisposition { stored, resourceLimit }

final class TerminalKittyImageStoreResult {
  const TerminalKittyImageStoreResult(this.disposition, {this.image});

  final TerminalKittyImageStoreDisposition disposition;
  final TerminalKittyImage? image;
}

/// Per-screen, reject-on-cap storage for static Kitty image data.
final class TerminalKittyImageStore {
  TerminalKittyImageStore({
    this.maximumImages = TerminalKittyImageStoreLimits.maximumImages,
    this.maximumPlacements = TerminalKittyImageStoreLimits.maximumPlacements,
    this.maximumRetainedBytes =
        TerminalKittyImageStoreLimits.maximumRetainedBytes,
  }) {
    if (maximumImages <= 0 ||
        maximumImages > TerminalKittyImageStoreLimits.maximumImages ||
        maximumPlacements <= 0 ||
        maximumPlacements > TerminalKittyImageStoreLimits.maximumPlacements ||
        maximumRetainedBytes <= 0 ||
        maximumRetainedBytes >
            TerminalKittyImageStoreLimits.maximumRetainedBytes) {
      throw ArgumentError('Kitty image store bounds exceed product limits');
    }
  }

  final int maximumImages;
  final int maximumPlacements;
  final int maximumRetainedBytes;
  final LinkedHashMap<int, TerminalKittyImage> _byId =
      LinkedHashMap<int, TerminalKittyImage>();
  final LinkedHashMap<int, TerminalKittyImagePlacement> _placements =
      LinkedHashMap<int, TerminalKittyImagePlacement>();
  var _retainedBytes = 0;
  var _nextImageId = 1;
  var _nextResourceGeneration = 1;
  var _nextPlacementGeneration = 1;
  var _stateGeneration = 1;

  int get length => _byId.length;
  int get retainedBytes => _retainedBytes;
  int get placementCount => _placements.length;
  int get stateGeneration => _stateGeneration;
  bool get isEmpty => _byId.isEmpty;

  TerminalKittyImage? imageById(int id) => _byId[id];

  TerminalKittyImage? newestImageByNumber(int number) {
    if (number <= 0 || number > 0xffffffff) return null;
    for (final TerminalKittyImage image in _byId.values.toList().reversed) {
      if (image.number == number) return image;
    }
    return null;
  }

  List<TerminalKittyImage> snapshot() =>
      List<TerminalKittyImage>.unmodifiable(_byId.values);

  List<TerminalKittyImagePlacement> placementSnapshot() =>
      List<TerminalKittyImagePlacement>.unmodifiable(_placements.values);

  TerminalKittyImageStoreResult store({
    required int imageId,
    required int imageNumber,
    required int width,
    required int height,
    required bool transient,
    required Uint8List rgba,
  }) {
    _validateIdentity(imageId, imageNumber);
    _validateImage(width, height, rgba);
    final bool generatedId = imageId == 0;
    final int resolvedId = generatedId ? _allocateImageId() : imageId;
    final TerminalKittyImage? replaced = _byId[resolvedId];
    final int projectedCount = _byId.length + (replaced == null ? 1 : 0);
    final int projectedBytes =
        _retainedBytes - (replaced?.byteLength ?? 0) + rgba.length;
    if (projectedCount > maximumImages ||
        projectedBytes > maximumRetainedBytes) {
      return const TerminalKittyImageStoreResult(
        TerminalKittyImageStoreDisposition.resourceLimit,
      );
    }
    final TerminalKittyImage image = TerminalKittyImage._(
      id: resolvedId,
      number: generatedId ? imageNumber : 0,
      width: width,
      height: height,
      resourceGeneration: _takeResourceGeneration(),
      transient: transient,
      rgba: rgba,
    );
    if (replaced != null) {
      _removePlacementsWhere(
        (TerminalKittyImagePlacement placement) =>
            placement.imageId == resolvedId,
        bumpGeneration: false,
      );
      _byId.remove(resolvedId);
    }
    _byId[resolvedId] = image;
    _retainedBytes = projectedBytes;
    _stateGeneration++;
    return TerminalKittyImageStoreResult(
      TerminalKittyImageStoreDisposition.stored,
      image: image,
    );
  }

  TerminalKittyImagePlacementResult place({
    required int imageId,
    required int imageNumber,
    required int placementId,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int logicalCellOffset,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int cellOffsetX,
    required int cellOffsetY,
    required int columns,
    required int rows,
    required int z,
  }) {
    _validateIdentity(imageId, imageNumber);
    _validatePlacement(
      placementId: placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: sourceX,
      sourceY: sourceY,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      columns: columns,
      rows: rows,
      z: z,
    );
    final TerminalKittyImage? image = imageId != 0
        ? imageById(imageId)
        : newestImageByNumber(imageNumber);
    if (image == null) {
      return const TerminalKittyImagePlacementResult(
        TerminalKittyImagePlacementDisposition.imageMissing,
      );
    }
    final TerminalKittyImagePlacement? replaced = placementId == 0
        ? null
        : _findExplicitPlacement(image.id, placementId);
    if (replaced == null && _placements.length >= maximumPlacements) {
      return TerminalKittyImagePlacementResult(
        TerminalKittyImagePlacementDisposition.resourceLimit,
        image: image,
      );
    }
    if (replaced != null) {
      _placements.remove(replaced.placementGeneration);
    }
    final int placementGeneration = _takePlacementGeneration();
    final TerminalKittyImagePlacement placement = TerminalKittyImagePlacement._(
      placementGeneration: placementGeneration,
      imageId: image.id,
      imageResourceGeneration: image.resourceGeneration,
      placementId: placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: sourceX,
      sourceY: sourceY,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      requestedColumns: columns,
      requestedRows: rows,
      z: z,
    );
    _placements[placementGeneration] = placement;
    _stateGeneration++;
    return TerminalKittyImagePlacementResult(
      TerminalKittyImagePlacementDisposition.stored,
      image: image,
      placement: placement,
    );
  }

  int removePlacementsForImage(int imageId) {
    if (imageId <= 0 || imageId > 0xffffffff) return 0;
    return _removePlacementsWhere(
      (TerminalKittyImagePlacement placement) => placement.imageId == imageId,
    );
  }

  TerminalKittyImageDeleteResult delete({
    required TerminalKittyGraphicsDeletion deletion,
    required int cursorRow,
    required int cursorColumn,
    required int screenRows,
    required int screenColumns,
    required int cellWidth,
    required int cellHeight,
    required TerminalKittyImagePlacementPositionResolver resolvePosition,
  }) {
    if (screenRows <= 0 ||
        screenColumns <= 0 ||
        cellWidth < 0 ||
        cellHeight < 0) {
      throw ArgumentError('screen dimensions or cell metrics are invalid');
    }
    final TerminalKittyGraphicsDeleteSelector selector = deletion.selector;
    if (selector == TerminalKittyGraphicsDeleteSelector.animationFrames ||
        selector ==
            TerminalKittyGraphicsDeleteSelector.animationFramesAndData) {
      throw UnsupportedError('animation frame deletion is not supported');
    }
    final bool deleteData = _selectorDeletesData(selector);
    final Set<int> dataCandidates = <int>{};
    final Set<int> directCandidates = <int>{};
    bool Function(TerminalKittyImagePlacement placement) matches;
    switch (selector) {
      case TerminalKittyGraphicsDeleteSelector.imageId:
      case TerminalKittyGraphicsDeleteSelector.imageIdAndData:
        final int id = deletion.imageId;
        if (id <= 0 || !_byId.containsKey(id)) {
          matches = (_) => false;
          break;
        }
        matches = (TerminalKittyImagePlacement placement) =>
            placement.imageId == id &&
            (deletion.placementId == 0 ||
                placement.placementId == deletion.placementId);
        if (deletion.placementId == 0) directCandidates.add(id);
        break;
      case TerminalKittyGraphicsDeleteSelector.newest:
      case TerminalKittyGraphicsDeleteSelector.newestAndData:
        final TerminalKittyImage? image = newestImageByNumber(
          deletion.imageNumber,
        );
        if (image == null) {
          matches = (_) => false;
          break;
        }
        matches = (TerminalKittyImagePlacement placement) =>
            placement.imageId == image.id &&
            (deletion.placementId == 0 ||
                placement.placementId == deletion.placementId);
        if (deletion.placementId == 0) directCandidates.add(image.id);
        break;
      case TerminalKittyGraphicsDeleteSelector.range:
      case TerminalKittyGraphicsDeleteSelector.rangeAndData:
        final int first = deletion.x;
        final int last = deletion.y;
        matches = first > last || last == 0
            ? (_) => false
            : (TerminalKittyImagePlacement placement) =>
                  placement.imageId >= first && placement.imageId <= last;
        if (deleteData && first <= last && last != 0) {
          directCandidates.addAll(
            _byId.keys.where((int id) => id >= first && id <= last),
          );
        }
        break;
      case TerminalKittyGraphicsDeleteSelector.all:
      case TerminalKittyGraphicsDeleteSelector.allAndData:
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              _intersects(
                placement,
                position,
                row: 0,
                column: 0,
                rows: screenRows,
                columns: screenColumns,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.cursor:
      case TerminalKittyGraphicsDeleteSelector.cursorAndData:
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              _containsCell(
                placement,
                position,
                cursorRow,
                cursorColumn,
                cellWidth,
                cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.cell:
      case TerminalKittyGraphicsDeleteSelector.cellAndData:
      case TerminalKittyGraphicsDeleteSelector.cellAndZ:
      case TerminalKittyGraphicsDeleteSelector.cellAndZAndData:
        if (deletion.x == 0 || deletion.y == 0) {
          matches = (_) => false;
          break;
        }
        final int row = deletion.y - 1;
        final int column = deletion.x - 1;
        final bool matchZ =
            selector == TerminalKittyGraphicsDeleteSelector.cellAndZ ||
            selector == TerminalKittyGraphicsDeleteSelector.cellAndZAndData;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              (!matchZ || placement.z == deletion.z) &&
              _containsCell(
                placement,
                position,
                row,
                column,
                cellWidth,
                cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.column:
      case TerminalKittyGraphicsDeleteSelector.columnAndData:
        if (deletion.x == 0) {
          matches = (_) => false;
          break;
        }
        final int column = deletion.x - 1;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              column >= position.column &&
              column <
                  position.column +
                      _placementColumns(placement, cellWidth, cellHeight);
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.row:
      case TerminalKittyGraphicsDeleteSelector.rowAndData:
        if (deletion.y == 0) {
          matches = (_) => false;
          break;
        }
        final int row = deletion.y - 1;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              row >= position.row &&
              row <
                  position.row +
                      _placementRows(placement, cellWidth, cellHeight);
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.z:
      case TerminalKittyGraphicsDeleteSelector.zAndData:
        matches = (TerminalKittyImagePlacement placement) =>
            placement.z == deletion.z;
        break;
      case TerminalKittyGraphicsDeleteSelector.animationFrames:
      case TerminalKittyGraphicsDeleteSelector.animationFramesAndData:
        throw StateError('animation selector reached static deletion');
    }
    final int beforePlacements = _placements.length;
    _removePlacementsWhere((TerminalKittyImagePlacement placement) {
      if (!matches(placement)) return false;
      dataCandidates.add(placement.imageId);
      return true;
    }, bumpGeneration: false);
    if (deleteData) dataCandidates.addAll(directCandidates);
    final int beforeImages = _byId.length;
    if (deleteData) {
      for (final int imageId in dataCandidates) {
        _removeImageIfUnused(imageId);
      }
    }
    final int deletedPlacements = beforePlacements - _placements.length;
    final int deletedImages = beforeImages - _byId.length;
    if (deletedPlacements != 0 || deletedImages != 0) _stateGeneration++;
    return TerminalKittyImageDeleteResult(
      deletedPlacements: deletedPlacements,
      deletedImages: deletedImages,
    );
  }

  void clear() {
    if (_byId.isEmpty && _placements.isEmpty) return;
    _byId.clear();
    _placements.clear();
    _retainedBytes = 0;
    _stateGeneration++;
  }

  TerminalKittyImagePlacement? _findExplicitPlacement(
    int imageId,
    int placementId,
  ) {
    for (final TerminalKittyImagePlacement placement in _placements.values) {
      if (placement.imageId == imageId &&
          placement.placementId == placementId) {
        return placement;
      }
    }
    return null;
  }

  int _removePlacementsWhere(
    bool Function(TerminalKittyImagePlacement placement) predicate, {
    bool bumpGeneration = true,
  }) {
    final List<int> removed = <int>[];
    for (final MapEntry<int, TerminalKittyImagePlacement> entry
        in _placements.entries) {
      if (predicate(entry.value)) removed.add(entry.key);
    }
    for (final int key in removed) {
      _placements.remove(key);
    }
    if (bumpGeneration && removed.isNotEmpty) _stateGeneration++;
    return removed.length;
  }

  bool _removeImageIfUnused(int imageId) {
    for (final TerminalKittyImagePlacement placement in _placements.values) {
      if (placement.imageId == imageId) return false;
    }
    final TerminalKittyImage? removed = _byId.remove(imageId);
    if (removed == null) return false;
    _retainedBytes -= removed.byteLength;
    return true;
  }

  int _placementColumns(
    TerminalKittyImagePlacement placement,
    int cellWidth,
    int cellHeight,
  ) {
    final TerminalKittyImage? image = _byId[placement.imageId];
    if (image == null ||
        image.resourceGeneration != placement.imageResourceGeneration) {
      return 0;
    }
    return placement
        .geometry(image: image, cellWidth: cellWidth, cellHeight: cellHeight)
        .columns;
  }

  int _placementRows(
    TerminalKittyImagePlacement placement,
    int cellWidth,
    int cellHeight,
  ) {
    final TerminalKittyImage? image = _byId[placement.imageId];
    if (image == null ||
        image.resourceGeneration != placement.imageResourceGeneration) {
      return 0;
    }
    return placement
        .geometry(image: image, cellWidth: cellWidth, cellHeight: cellHeight)
        .rows;
  }

  bool _containsCell(
    TerminalKittyImagePlacement placement,
    TerminalKittyImagePlacementPosition position,
    int row,
    int column,
    int cellWidth,
    int cellHeight,
  ) {
    final int columns = _placementColumns(placement, cellWidth, cellHeight);
    final int rows = _placementRows(placement, cellWidth, cellHeight);
    return columns > 0 &&
        rows > 0 &&
        row >= position.row &&
        row < position.row + rows &&
        column >= position.column &&
        column < position.column + columns;
  }

  bool _intersects(
    TerminalKittyImagePlacement placement,
    TerminalKittyImagePlacementPosition position, {
    required int row,
    required int column,
    required int rows,
    required int columns,
    required int cellWidth,
    required int cellHeight,
  }) {
    final int placementColumns = _placementColumns(
      placement,
      cellWidth,
      cellHeight,
    );
    final int placementRows = _placementRows(placement, cellWidth, cellHeight);
    return placementColumns > 0 &&
        placementRows > 0 &&
        position.row < row + rows &&
        position.row + placementRows > row &&
        position.column < column + columns &&
        position.column + placementColumns > column;
  }

  static bool _selectorDeletesData(
    TerminalKittyGraphicsDeleteSelector selector,
  ) => switch (selector) {
    TerminalKittyGraphicsDeleteSelector.allAndData ||
    TerminalKittyGraphicsDeleteSelector.animationFramesAndData ||
    TerminalKittyGraphicsDeleteSelector.cursorAndData ||
    TerminalKittyGraphicsDeleteSelector.newestAndData ||
    TerminalKittyGraphicsDeleteSelector.imageIdAndData ||
    TerminalKittyGraphicsDeleteSelector.cellAndData ||
    TerminalKittyGraphicsDeleteSelector.cellAndZAndData ||
    TerminalKittyGraphicsDeleteSelector.rangeAndData ||
    TerminalKittyGraphicsDeleteSelector.columnAndData ||
    TerminalKittyGraphicsDeleteSelector.rowAndData ||
    TerminalKittyGraphicsDeleteSelector.zAndData => true,
    _ => false,
  };

  int _allocateImageId() {
    for (var attempts = 0; attempts <= _byId.length; attempts++) {
      final int candidate = _nextImageId;
      _nextImageId = candidate == 0xffffffff ? 1 : candidate + 1;
      if (!_byId.containsKey(candidate)) return candidate;
    }
    throw StateError('bounded Kitty image ID space is unexpectedly exhausted');
  }

  int _takeResourceGeneration() {
    final int result = _nextResourceGeneration;
    _nextResourceGeneration++;
    return result;
  }

  int _takePlacementGeneration() {
    if (_nextPlacementGeneration > 0x7fffffffffffffff) {
      throw StateError('Kitty placement generation space is exhausted');
    }
    return _nextPlacementGeneration++;
  }

  static void _validateIdentity(int imageId, int imageNumber) {
    if (imageId < 0 ||
        imageId > 0xffffffff ||
        imageNumber < 0 ||
        imageNumber > 0xffffffff ||
        (imageId == 0) == (imageNumber == 0)) {
      throw ArgumentError(
        'exactly one positive image ID or number is required',
      );
    }
  }

  static void _validateImage(int width, int height, Uint8List rgba) {
    if (width <= 0 ||
        height <= 0 ||
        width > TerminalKittyImageStoreLimits.maximumDimension ||
        height > TerminalKittyImageStoreLimits.maximumDimension ||
        width * height > TerminalKittyImageStoreLimits.maximumPixels ||
        rgba.length != width * height * 4 ||
        rgba.length > TerminalKittyImageStoreLimits.maximumImageBytes) {
      throw ArgumentError('canonical Kitty image exceeds storage limits');
    }
  }

  static void _validatePlacement({
    required int placementId,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int logicalCellOffset,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int cellOffsetX,
    required int cellOffsetY,
    required int columns,
    required int rows,
    required int z,
  }) {
    final List<int> unsigned32 = <int>[
      placementId,
      sourceX,
      sourceY,
      sourceWidth,
      sourceHeight,
      cellOffsetX,
      cellOffsetY,
      columns,
      rows,
    ];
    if (unsigned32.any((int value) => value < 0 || value > 0xffffffff) ||
        logicalLineId <= 0 ||
        logicalLineId > 0xffffffff ||
        logicalLineEpoch <= 0 ||
        logicalLineEpoch > 0x7fffffffffffffff ||
        logicalCellOffset < 0 ||
        logicalCellOffset > 0x7fffffffffffffff ||
        z < -0x80000000 ||
        z > 0x7fffffff) {
      throw ArgumentError('Kitty placement metadata is out of range');
    }
  }
}
